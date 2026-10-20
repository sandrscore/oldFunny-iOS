#!/usr/bin/env python3
"""Compile the native iOS app on a Mac and package an unsigned ARM64 IPA for Zeus."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import zipfile

from ios_native_project import ROOT, IOS, generate
from inspect_ipa import inspect


def make_icons():
    resources = IOS / "OldFunny/Resources"
    assets = resources / "Assets.xcassets"
    icon = assets / "AppIcon.appiconset"
    icon.mkdir(parents=True, exist_ok=True)
    (assets / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}))
    source = resources / "Branding/launcher.png"
    subprocess.run(["swift", str(ROOT / "tools/render_ios_icon.swift"), str(source) if source.exists() else "-", str(icon / "icon-1024.png")], check=True)
    entries = []
    for idiom, sizes in (("iphone", [(20, 2), (20, 3), (29, 2), (29, 3), (40, 2), (40, 3), (60, 2), (60, 3)]),
                         ("ipad", [(20, 1), (20, 2), (29, 1), (29, 2), (40, 1), (40, 2), (76, 1), (76, 2), (83.5, 2)])):
        for points, scale in sizes:
            pixels = int(points * scale); filename = f"icon-{pixels}.png"
            subprocess.run(["sips", "-z", str(pixels), str(pixels), str(icon / "icon-1024.png"), "--out", str(icon / filename)], check=True, stdout=subprocess.DEVNULL)
            entries.append({"idiom": idiom, "size": f"{points}x{points}", "scale": f"{scale}x", "filename": filename})
    entries.append({"idiom": "ios-marketing", "size": "1024x1024", "scale": "1x", "filename": "icon-1024.png"})
    (icon / "Contents.json").write_text(json.dumps({"images": entries, "info": {"author": "xcode", "version": 1}}, indent=2))


def package(app: Path, output: Path):
    if output.exists(): raise ValueError("Choose a new IPA output filename; existing artifacts are preserved")
    with (app / "Info.plist").open("rb") as stream: info = plistlib.load(stream)
    executable = app / info["CFBundleExecutable"]
    if not executable.is_file(): raise ValueError("Built executable missing")
    if any(b"preview.invalid" in path.read_bytes() for path in [executable, *app.rglob("*.dylib")]):
        raise ValueError("Offline preview fixtures must not be packaged in the Release IPA")
    if (app / "embedded.mobileprovision").exists(): raise ValueError("Expected unsigned app without account provisioning")
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(app.rglob("*")):
            if path.is_file(): archive.write(path, "Payload/OldFunny.app/" + path.relative_to(app).as_posix())
    report = inspect(output)
    if not report["contains_arm64"] or report["drm_resource_count"]:
        raise ValueError("Built IPA failed ARM64/DRM inspection")
    if any(value == "encrypted" for value in report["main_encryption_status"].values()):
        raise ValueError("Unexpected encrypted executable in a source build")
    if report["components_requiring_architecture_review"]:
        raise ValueError("Embedded executable lacks ARM64")
    report.update(acquisition="compiled from new oldFunny Swift source", successfully_downloaded=None,
                  signed=False, runtime_tested=False, installs_and_runs="unverified", ui_match="partial classic styling; exact layouts unverified",
                  feature_parity="incomplete; see ios/PORT_STATUS.md")
    output.with_suffix(".inspection.json").write_text(json.dumps(report, indent=2) + "\n")
    output.with_suffix(".sha256").write_text(report["sha256"] + "  " + output.name + "\n")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    version = plistlib.loads((IOS / "OldFunny/Info.plist").read_bytes())["CFBundleShortVersionString"]
    parser.add_argument("--output", type=Path, default=ROOT / f".ios-work/ios-port/dist/oldFunny-ios-{version}-unsigned.ipa")
    parser.add_argument("--work", type=Path, default=ROOT / ".ios-work/ios-port/xcode")
    parser.add_argument("--bundle-id", default="mobi.oldfunny.ios")
    args = parser.parse_args()
    if sys.platform != "darwin": parser.error("The iOS SDK requires a Mac build host. Use the prepared GitHub Actions workflow; Linux can test OldFunnyCore.")
    if args.output.exists(): parser.error("Choose a new IPA filename")
    subprocess.run(["swift", "test", "--package-path", str(IOS / "OldFunnyCore"), "--scratch-path", str(args.work / "core-tests")], check=True)
    make_icons()
    generate(IOS / "OldFunny.xcodeproj", args.bundle_id)
    subprocess.run([
        "xcodebuild", "-project", str(IOS / "OldFunny.xcodeproj"), "-scheme", "OldFunny",
        "-configuration", "Release", "-sdk", "iphoneos", "-destination", "generic/platform=iOS",
        "-derivedDataPath", str(args.work), "ARCHS=arm64", "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "build"
    ], check=True)
    app = args.work / "Build/Products/Release-iphoneos/OldFunny.app"
    result = package(app, args.output)
    print(json.dumps({"ipa": result["path"], "sha256": result["sha256"], "contains_arm64": True,
                      "signed": False, "runtime_tested": False, "feature_parity": "incomplete"}, indent=2))


if __name__ == "__main__": main()
