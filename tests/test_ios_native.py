"""Independent packaging, project graph and source-export boundary checks."""
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from ios_native_project import generate, export_source, stage_classic
from build_ios_native import package
from preview_ios_native import verify_gesture_tests


class IOSNativeTests(unittest.TestCase):
    def test_preview_requires_every_gesture_test_to_execute_and_pass(self):
        source = 'func testSwipe() {}\nfunc testZoom() {}'
        log = "Test Case '-[OldFunnyUITests.ViewerTests testSwipe]' passed (1.0 seconds).\n"
        with self.assertRaises(RuntimeError): verify_gesture_tests(log, source)
        with self.assertRaises(RuntimeError): verify_gesture_tests('', source)
        with self.assertRaises(RuntimeError): verify_gesture_tests(log, '')
        complete = log + "Test Case '-[OldFunnyUITests.ViewerTests testZoom]' passed (1.0 seconds).\n"
        self.assertEqual(verify_gesture_tests(complete, source), ['testSwipe', 'testZoom'])

    def test_generated_project_has_complete_sources_and_resolvable_references(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            # Generate against the real sources while keeping artifacts separate.
            import shutil
            shutil.copytree(ROOT / "ios/OldFunny", root / "OldFunny")
            shutil.copytree(ROOT / "ios/OldFunnyCore/Sources", root / "OldFunnyCore/Sources")
            shutil.copytree(ROOT / "ios/UITests", root / "UITests")
            project = generate(root / "OldFunny.xcodeproj", ios=root)
            objects = project["objects"]
            self.assertEqual(objects[project["rootObject"]]["isa"], "PBXProject")
            sources = [x for x in objects.values() if x["isa"] == "PBXFileReference" and x.get("lastKnownFileType") == "sourcecode.swift"]
            actual = {x["path"] for x in sources}
            expected = {p.relative_to(ROOT / "ios").as_posix() for p in (ROOT / "ios/OldFunny").glob("*.swift")}
            expected |= {p.relative_to(ROOT / "ios").as_posix() for p in (ROOT / "ios/OldFunnyCore/Sources/OldFunnyCore").glob("*.swift")}
            expected |= {p.relative_to(ROOT / "ios").as_posix() for p in (ROOT / "ios/UITests").glob("*.swift")}
            self.assertEqual(actual, expected)
            self.assertFalse(any("Probe" in x for x in actual))
            targets = {x["name"]: x for x in objects.values() if x["isa"] == "PBXNativeTarget"}
            self.assertEqual(set(targets), {"OldFunny", "OldFunnyUITests"})
            main_sources = objects[targets["OldFunny"]["buildPhases"][0]]["files"]
            self.assertFalse(any(objects[objects[x]["fileRef"]]["path"].startswith("UITests/") for x in main_sources))
            for obj in objects.values():
                for key in ("fileRef", "productReference", "buildConfigurationList", "mainGroup", "productRefGroup"):
                    if key in obj: self.assertIn(obj[key], objects)
                for key in ("files", "children", "buildConfigurations", "buildPhases", "targets"):
                    for ref in obj.get(key, []): self.assertIn(ref, objects)
            scheme = ET.parse(root / "OldFunny.xcodeproj/xcshareddata/xcschemes/OldFunny.xcscheme")
            for ref in scheme.findall(".//BuildableReference"):
                self.assertEqual(objects[ref.attrib["BlueprintIdentifier"]]["isa"], "PBXNativeTarget")
            with self.assertRaises(ValueError): generate(root / "OldFunny.xcodeproj", "bad/id", ios=root)

    def test_source_export_excludes_original_apps_and_private_work(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "native-source.zip"
            result = export_source(output, include_assets=True)
            self.assertEqual(result["sha256"], hashlib.sha256(output.read_bytes()).hexdigest())
            with zipfile.ZipFile(output) as archive:
                names = archive.namelist()
                self.assertIn(".github/workflows/ios-native.yml", names)
                self.assertIn("ios/OldFunnyCore/Sources/OldFunnyCore/APIClient.swift", names)
                self.assertIn("tools/inspect_ipa.py", names)
                self.assertIn("ios/OldFunny/Resources/Branding/launcher.png", names)
                for name in names:
                    self.assertFalse(any(part in name.split("/") for part in (".ios-work", "analysis", "private", "SC_Info", ".local", "android-src")), name)
                    self.assertFalse(name.endswith((".ipa", ".apk", ".xapk", ".mobileprovision", ".p12", ".p8")), name)
                self.assertEqual(archive.testzip(), None)
            before = output.read_bytes()
            with self.assertRaises(ValueError): export_source(output, include_assets=True)
            self.assertEqual(output.read_bytes(), before)

    def test_app_manifest_has_separate_identity_and_no_insecure_transport_override(self):
        with (ROOT / "ios/OldFunny/Info.plist").open("rb") as stream: info = plistlib.load(stream)
        self.assertEqual(info["CFBundleDisplayName"], "oldFunny")
        self.assertNotIn("NSAppTransportSecurity", info)
        self.assertNotIn("aps-environment", info)
        ET.parse(ROOT / "ios/OldFunny/LaunchScreen.storyboard")

    def test_unsigned_packaging_reports_static_success_without_claiming_runtime(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory); app = directory / "OldFunny.app"; app.mkdir()
            info = dict(CFBundleExecutable="OldFunny", CFBundleIdentifier="mobi.oldfunny.ios", CFBundleShortVersionString="0.1.0", CFBundleVersion="1", MinimumOSVersion="16.0")
            (app / "Info.plist").write_bytes(plistlib.dumps(info))
            # Synthetic ARM64 Mach-O, never executed. Tests archive/inspection
            # behavior only, not compilation or the validity of a runnable app.
            header = struct.pack("<8I", 0xfeedfacf, 0x0100000c, 0, 2, 1, 24, 0, 0)
            command = struct.pack("<6I", 0x2c, 24, 0, 0, 0, 0)
            (app / "OldFunny").write_bytes(header + command)
            output = directory / "fixture.ipa"
            report = package(app, output)
            self.assertTrue(report["contains_arm64"])
            self.assertFalse(report["signed"])
            self.assertFalse(report["runtime_tested"])
            self.assertEqual(report["installs_and_runs"], "unverified")
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(set(archive.namelist()), {"Payload/OldFunny.app/Info.plist", "Payload/OldFunny.app/OldFunny"})
            with self.assertRaises(ValueError): package(app, output)
            (app / "embedded.mobileprovision").write_text("fixture-only")
            with self.assertRaises(ValueError): package(app, directory / "reject.ipa")
            (app / "embedded.mobileprovision").unlink()
            (app / "OldFunny").write_bytes(header + command + b"preview.invalid")
            with self.assertRaisesRegex(ValueError, "preview fixtures"):
                package(app, directory / "reject-preview.ipa")
            self.assertFalse((directory / "reject-preview.ipa").exists())

    def test_staged_resource_hashes_match_provenance(self):
        manifest = ROOT / "ios/OldFunny/Resources/resource-provenance.json"
        if not manifest.exists(): self.skipTest("Recovered resources are local-only")
        for row in json.loads(manifest.read_text()):
            parent = "Branding" if row["name"] == "launcher.png" else "Classic"
            path = ROOT / "ios/OldFunny/Resources" / parent / row["name"]
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), row["sha256"])


if __name__ == "__main__": unittest.main()
