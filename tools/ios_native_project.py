#!/usr/bin/env python3
"""Generate a self-contained Xcode project for the new native oldFunny client.

No downloaded IPA/APK, session, signing identity, or account file is included.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "ios"
PRODUCT = "OldFunny"


def identity(name: str) -> str:
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def openstep(value, indent=0):
    pad = "\t" * indent
    if isinstance(value, dict):
        return "{\n" + "".join(pad + "\t" + json.dumps(str(k)) + " = " + openstep(v, indent + 1) + ";\n" for k, v in value.items()) + pad + "}"
    if isinstance(value, list):
        return "(\n" + "".join(pad + "\t" + openstep(x, indent + 1) + ",\n" for x in value) + pad + ")"
    if isinstance(value, int):
        return str(value)
    return json.dumps(str(value))


def generate(output: Path, bundle: str = "mobi.oldfunny.ios", ios: Path = IOS):
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9-]*(?:\.[A-Za-z0-9-]+){2,}", bundle):
        raise ValueError("Use a reverse-DNS bundle identifier")
    output.mkdir(parents=True, exist_ok=True)
    objects = {}

    def obj(object_key, kind, **fields):
        key = identity(object_key)
        objects[key] = {"isa": kind, **fields}
        return key

    source_refs, source_builds = [], []
    source_files = sorted((ios / "OldFunny").glob("*.swift")) + sorted((ios / "OldFunnyCore/Sources/OldFunnyCore").glob("*.swift"))
    for path in source_files:
        relative = path.relative_to(ios).as_posix()
        ref = obj(relative, "PBXFileReference", lastKnownFileType="sourcecode.swift", path=relative, sourceTree="SOURCE_ROOT")
        source_refs.append(ref)
        source_builds.append(obj(relative + ":build", "PBXBuildFile", fileRef=ref))
    resources, resource_refs = [], []
    paths = [ios / "OldFunny/LaunchScreen.storyboard"]
    paths += sorted((ios / "OldFunny/Resources/Classic").glob("*.png"))
    if (ios / "OldFunny/Resources/Assets.xcassets").exists():
        paths.append(ios / "OldFunny/Resources/Assets.xcassets")
    for path in paths:
        relative = path.relative_to(ios).as_posix()
        kind = "folder.assetcatalog" if path.suffix == ".xcassets" else "file.storyboard" if path.suffix == ".storyboard" else "image.png"
        ref = obj(relative, "PBXFileReference", lastKnownFileType=kind, path=relative, sourceTree="SOURCE_ROOT")
        resource_refs.append(ref)
        resources.append(obj(relative + ":build", "PBXBuildFile", fileRef=ref))
    framework_refs, framework_builds = [], []
    for name in ("UIKit", "AVKit", "AVFoundation", "WebKit", "Security", "ImageIO", "Photos"):
        ref = obj(name, "PBXFileReference", lastKnownFileType="wrapper.framework", path=f"System/Library/Frameworks/{name}.framework", sourceTree="SDKROOT")
        framework_refs.append(ref); framework_builds.append(obj(name + ":build", "PBXBuildFile", fileRef=ref))
    product = obj("product", "PBXFileReference", explicitFileType="wrapper.application", includeInIndex=0, path="OldFunny.app", sourceTree="BUILT_PRODUCTS_DIR")
    products = obj("products", "PBXGroup", children=[product], name="Products", sourceTree="<group>")
    main_group = obj("main", "PBXGroup", children=source_refs + resource_refs + framework_refs + [products], sourceTree="<group>")
    sources = obj("sources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=source_builds, runOnlyForDeploymentPostprocessing=0)
    resource_phase = obj("resources", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=resources, runOnlyForDeploymentPostprocessing=0)
    framework_phase = obj("frameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=framework_builds, runOnlyForDeploymentPostprocessing=0)
    common = {
        "SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "16.0", "SWIFT_VERSION": "5.0",
        "CLANG_ENABLE_MODULES": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "SWIFT_STRICT_CONCURRENCY": "minimal",
    }
    target_settings = {
        "PRODUCT_NAME": PRODUCT, "PRODUCT_BUNDLE_IDENTIFIER": bundle,
        "INFOPLIST_FILE": "OldFunny/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
        "TARGETED_DEVICE_FAMILY": "1,2", "CODE_SIGNING_ALLOWED": "NO", "CODE_SIGNING_REQUIRED": "NO",
        "ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES": "YES", "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    }
    if (ios / "OldFunny/Resources/Assets.xcassets/AppIcon.appiconset").exists():
        target_settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
    lists = []
    for label, settings in (("project", common), ("target", target_settings)):
        configs = []
        for mode in ("Debug", "Release"):
            options = dict(settings)
            if mode == "Debug": options["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone"
            else: options["SWIFT_COMPILATION_MODE"] = "wholemodule"
            configs.append(obj(f"{label}:{mode}", "XCBuildConfiguration", buildSettings=options, name=mode))
        lists.append(obj(label + ":configs", "XCConfigurationList", buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release"))
    target = obj("target", "PBXNativeTarget", buildConfigurationList=lists[1], buildPhases=[sources, framework_phase, resource_phase], buildRules=[], dependencies=[], name=PRODUCT, productName=PRODUCT, productReference=product, productType="com.apple.product-type.application")
    project = obj("project", "PBXProject", attributes={"LastUpgradeCheck": "1600"}, buildConfigurationList=lists[0], compatibilityVersion="Xcode 14.0", developmentRegion="en", hasScannedForEncodings=0, knownRegions=["en", "Base"], mainGroup=main_group, productRefGroup=products, projectDirPath="", projectRoot="", targets=[target])
    ui_target = None
    ui_sources = sorted((ios / "UITests").glob("*.swift"))
    if ui_sources:
        refs, builds = [], []
        for path in ui_sources:
            relative = path.relative_to(ios).as_posix()
            ref = obj(relative, "PBXFileReference", lastKnownFileType="sourcecode.swift", path=relative, sourceTree="SOURCE_ROOT")
            refs.append(ref); builds.append(obj(relative + ":build", "PBXBuildFile", fileRef=ref))
        objects[main_group]["children"] += refs
        ui_product = obj("ui-product", "PBXFileReference", explicitFileType="wrapper.cfbundle", includeInIndex=0, path="OldFunnyUITests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
        objects[products]["children"].append(ui_product)
        ui_configs = []
        for mode in ("Debug", "Release"):
            ui_configs.append(obj("ui:" + mode, "XCBuildConfiguration", name=mode, buildSettings={"PRODUCT_NAME": "OldFunnyUITests", "PRODUCT_BUNDLE_IDENTIFIER": bundle + ".uitests", "GENERATE_INFOPLIST_FILE": "YES", "TARGETED_DEVICE_FAMILY": "1,2", "CODE_SIGNING_ALLOWED": "NO", "CODE_SIGNING_REQUIRED": "NO", "TEST_TARGET_NAME": PRODUCT}))
        ui_list = obj("ui-configs", "XCConfigurationList", buildConfigurations=ui_configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Debug")
        ui_phase = obj("ui-sources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=builds, runOnlyForDeploymentPostprocessing=0)
        proxy = obj("ui-proxy", "PBXContainerItemProxy", containerPortal=project, proxyType=1, remoteGlobalIDString=target, remoteInfo=PRODUCT)
        dependency = obj("ui-dependency", "PBXTargetDependency", target=target, targetProxy=proxy)
        ui_target = obj("ui-target", "PBXNativeTarget", buildConfigurationList=ui_list, buildPhases=[ui_phase], buildRules=[], dependencies=[dependency], name="OldFunnyUITests", productName="OldFunnyUITests", productReference=ui_product, productType="com.apple.product-type.bundle.ui-testing")
        objects[project]["targets"].append(ui_target)
    document = {"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": project}
    (output / "project.pbxproj").write_text("// !$*UTF8*$!\n" + openstep(document) + "\n")
    # SOURCE_ROOT must be ios/, so default project lives directly inside ios/.
    if output.parent.resolve() != ios.resolve():
        raise ValueError("Place the generated .xcodeproj directly in the iOS source directory")
    schemes = output / "xcshareddata/xcschemes"; schemes.mkdir(parents=True, exist_ok=True)
    test_action = "" if ui_target is None else f'''<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ui_target}" BuildableName="OldFunnyUITests.xctest" BlueprintName="OldFunnyUITests" ReferencedContainer="container:OldFunny.xcodeproj"/></TestableReference></Testables></TestAction>'''
    (schemes / "OldFunny.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="OldFunny.app" BlueprintName="OldFunny" ReferencedContainer="container:OldFunny.xcodeproj"/>
    </BuildActionEntry>
  </BuildActionEntries></BuildAction>
  {test_action}
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="OldFunny.app" BlueprintName="OldFunny" ReferencedContainer="container:OldFunny.xcodeproj"/></BuildableProductRunnable>
  </LaunchAction>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
    return document


def stage_classic(work: Path, apk: Path | None = None, ios: Path = IOS):
    audit = work / "ui-audit"
    catalog = json.loads((audit / "catalog-images.json").read_text())
    selected = {"comments", "featured", "subscribe", "unsmile", "smile", "smile1", "smile2"}
    out = ios / "OldFunny/Resources/Classic"; out.mkdir(parents=True, exist_ok=True)
    records = []
    for entry in catalog["variants"]:
        name = entry["name"]
        stem = name.split("@")[0].removesuffix(".png")
        if stem not in selected or Path(name).name != name: continue
        path = (audit / entry["file"]).resolve()
        if not path.is_relative_to(audit.resolve()): raise ValueError("Invalid asset path")
        content = path.read_bytes()
        if hashlib.sha256(content).hexdigest() != entry["sha256"]: raise ValueError("Resource hash mismatch")
        (out / name).write_bytes(content)
        records.append({"name": name, "sha256": entry["sha256"], "origin": "iFunny iOS 4.6.8 resource"})
    if apk:
        # Copy the already approved oldFunny eyepatch artwork, without modifying
        # the Android APK or executing any archive entry.
        with zipfile.ZipFile(apk) as archive:
            content = archive.read("res/drawable-xxhdpi-v4/launcher.png")
        branding = ios / "OldFunny/Resources/Branding"; branding.mkdir(parents=True, exist_ok=True)
        (branding / "launcher.png").write_bytes(content)
        records.append({"name": "launcher.png", "sha256": hashlib.sha256(content).hexdigest(), "origin": "existing oldFunny Android launcher"})
    manifest = ios / "OldFunny/Resources/resource-provenance.json"
    manifest.write_text(json.dumps(records, indent=2) + "\n")
    return records


def export_source(output: Path, include_assets: bool):
    if output.exists(): raise ValueError("Choose a new source bundle path")
    paths = sorted((IOS / "OldFunny").glob("*.swift"))
    paths += [IOS / "OldFunny/Info.plist", IOS / "OldFunny/LaunchScreen.storyboard", IOS / "README.md", IOS / "PORT_STATUS.md", IOS / "PROTOCOL_PROVENANCE.md", IOS / "OldFunnyCore/Package.swift", IOS / "port.json"]
    if (IOS / "ANDROID_PARITY.md").exists(): paths.append(IOS / "ANDROID_PARITY.md")
    paths += sorted((IOS / "OldFunnyCore/Sources").rglob("*.swift"))
    paths += sorted((IOS / "OldFunnyCore/Tests").rglob("*.swift"))
    paths += sorted((IOS / "UITests").glob("*.swift"))
    paths += [ROOT / "tools/ios_native_project.py", ROOT / "tools/build_ios_native.py", ROOT / "tools/preview_ios_native.py", ROOT / "tools/render_ios_icon.swift", ROOT / "tools/inspect_ipa.py", ROOT / "tools/audit_android_ios_parity.py", ROOT / ".github/workflows/ios-native.yml"]
    paths += [ROOT / "tests/test_ios_native.py"]
    if include_assets:
        paths += sorted((IOS / "OldFunny/Resources/Classic").glob("*.png"))
        paths += sorted((IOS / "OldFunny/Resources/Branding").glob("*.png"))
        manifest = IOS / "OldFunny/Resources/resource-provenance.json"
        if manifest.exists(): paths.append(manifest)
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in paths: archive.write(path, path.relative_to(ROOT).as_posix())
        archive.writestr("README.md", "# oldFunny iOS\n\nNew native iOS implementation in progress. See [build instructions](ios/README.md) and [feature status](ios/PORT_STATUS.md). This is not an APK-to-IPA conversion or a feature-complete release.\n")
        archive.writestr(".gitignore", "*.ipa\n*.apk\n*.mobileprovision\n*.p12\n*.p8\n.ios-work/\n.local/\n.build/\n.swiftpm/\nDerivedData/\n*.xcuserstate\nxcuserdata/\nios/OldFunny.xcodeproj/\nios/OldFunny/Resources/Assets.xcassets/\n")
    return {"path": str(output), "files": len(paths), "sha256": hashlib.sha256(output.read_bytes()).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    command = parser.add_subparsers(dest="command", required=True)
    generate_parser = command.add_parser("generate")
    generate_parser.add_argument("--bundle-id", default="mobi.oldfunny.ios")
    assets = command.add_parser("stage-assets")
    assets.add_argument("--work", type=Path, default=ROOT / ".ios-work/restoration/4.6.8")
    assets.add_argument("--android-apk", type=Path)
    export = command.add_parser("export-source")
    export.add_argument("--output", required=True, type=Path)
    export.add_argument("--include-assets", action="store_true")
    args = parser.parse_args()
    if args.command == "generate":
        result = generate(IOS / "OldFunny.xcodeproj", args.bundle_id)
        print(json.dumps({"project": "ios/OldFunny.xcodeproj", "objects": len(result["objects"])}))
    elif args.command == "stage-assets": print(json.dumps({"staged": len(stage_classic(args.work, args.android_apk))}))
    else: print(json.dumps(export_source(args.output, args.include_assets), indent=2))


if __name__ == "__main__": main()
