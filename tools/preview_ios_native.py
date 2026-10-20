#!/usr/bin/env python3
"""Render the real UIKit screens with offline fixtures in a disposable simulator."""
from __future__ import annotations
import json
from pathlib import Path
import subprocess
import sys
import time

from ios_native_project import ROOT, IOS, generate


def run(*args, timeout=120):
    return subprocess.check_output(list(args), text=True, stderr=subprocess.STDOUT, timeout=timeout)


def main():
    if sys.platform != "darwin": raise SystemExit("UI previews require Xcode and an installed iOS simulator runtime")
    output = ROOT / ".ios-work/ios-port/ui-previews"; output.mkdir(parents=True, exist_ok=True)
    report = {"offline_fixtures": True, "real_account_used": False, "real_api_used": False,
              "target_phone_tested": False, "screenshots": []}
    device = None
    try:
        generate(IOS / "OldFunny.xcodeproj")
        work = ROOT / ".ios-work/ios-port/preview-build"
        command = ["xcodebuild", "-project", str(IOS / "OldFunny.xcodeproj"), "-scheme", "OldFunny",
                   "-configuration", "Debug", "-sdk", "iphonesimulator", "-destination", "generic/platform=iOS Simulator",
                   "-derivedDataPath", str(work), "ARCHS=arm64", "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO",
                   "SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG CLASSIC_UI_PREVIEW", "build"]
        with (output / "build.log").open("w") as log:
            subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=600)
        app = work / "Build/Products/Debug-iphonesimulator/OldFunny.app"
        if b"preview.invalid" not in (app / "OldFunny").read_bytes():
            raise RuntimeError("Refusing to launch a simulator preview without its offline fixture configuration")
        runtimes = json.loads(run("xcrun", "simctl", "list", "runtimes", "--json"))["runtimes"]
        sdk = tuple(int(n) for n in run("xcrun", "--sdk", "iphonesimulator", "--show-sdk-version").strip().split("."))
        choices = [r for r in runtimes if r.get("isAvailable") and ".iOS-" in r["identifier"]
                   and tuple(int(n) for n in r["version"].split("."))[:2] <= sdk[:2]]
        if not choices: raise RuntimeError("No installed, available iOS runtime compatible with the selected Xcode SDK")
        runtime = max(choices, key=lambda r: tuple(int(n) for n in r["version"].split(".")))
        types = json.loads(run("xcrun", "simctl", "list", "devicetypes", "--json"))["devicetypes"]
        kind = next((d for d in types if d["name"] == "iPhone 16"), None)
        if kind is None: kind = next(d for d in types if d["name"].startswith("iPhone"))
        device = run("xcrun", "simctl", "create", "OldFunnyOfflinePreview", kind["identifier"], runtime["identifier"]).strip()
        run("xcrun", "simctl", "boot", device)
        run("xcrun", "simctl", "bootstatus", device, "-b", timeout=300)
        run("xcrun", "simctl", "status_bar", device, "override", "--time", "9:41", "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3", "--batteryState", "charged", "--batteryLevel", "100")
        run("xcrun", "simctl", "install", device, str(app))
        report.update(simulator_device=kind["name"], simulator_ios=runtime["version"])
        for name, args in [("feed", []), ("sidebar", ["--preview-sidebar"]), ("comments", ["--preview-comments"])]:
            run("xcrun", "simctl", "launch", "--terminate-running-process", device, "mobi.oldfunny.ios", *args)
            time.sleep(3)
            path = output / (name + ".png")
            run("xcrun", "simctl", "io", device, "screenshot", "--type=png", str(path))
            report["screenshots"].append(path.name)
        report["success"] = True
    except Exception as error:
        report.update(success=False, error=str(error))
        log = output / "build.log"
        if log.exists(): print("\n".join(log.read_text(errors="replace").splitlines()[-50:]))
        raise
    finally:
        (output / "preview.json").write_text(json.dumps(report, indent=2) + "\n")
        if device:
            subprocess.run(["xcrun", "simctl", "shutdown", device], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
            subprocess.run(["xcrun", "simctl", "delete", device], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
    print(json.dumps(report, indent=2))


if __name__ == "__main__": main()
