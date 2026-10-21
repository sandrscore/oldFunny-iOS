#!/usr/bin/env python3
"""Render the real UIKit screens with offline fixtures in a disposable simulator."""
from __future__ import annotations
import json
from pathlib import Path
import re
import subprocess
import sys
import time
import math
import struct
import wave

from ios_native_project import ROOT, IOS, generate


def run(*args, timeout=120):
    return subprocess.check_output(list(args), text=True, stderr=subprocess.STDOUT, timeout=timeout)


def verify_gesture_tests(log: str, source: str) -> list[str]:
    """An exit status alone must not certify a skipped or empty test suite."""
    expected = set(re.findall(r"func (test\w+)\(", source))
    passed = set(re.findall(r"Test Case '-\[[^ ]*ViewerTests (test\w+)\]' passed", log))
    if not expected or expected != passed:
        raise RuntimeError("Gesture tests not all verified: " + ", ".join(sorted(expected - passed) or ["no expected tests"]))
    return sorted(passed)


def main():
    if sys.platform != "darwin": raise SystemExit("UI previews require Xcode and an installed iOS simulator runtime")
    output = ROOT / ".ios-work/ios-port/ui-previews"; output.mkdir(parents=True, exist_ok=True)
    report = {"offline_fixtures": True, "real_account_used": False, "real_api_used": False,
              "target_phone_tested": False, "screenshots": []}
    device = None; stage = "build"
    try:
        stage = "fixture-media"
        audio = output / "fixture-audio.wav"
        with wave.open(str(audio), "wb") as stream:
            stream.setnchannels(1); stream.setsampwidth(2); stream.setframerate(44100)
            stream.writeframes(b"".join(struct.pack("<h", int(500 * math.sin(2 * math.pi * 440 * n / 44100))) for n in range(546840)))
        fixture = output / "fixture-video.mp4"
        run("swift", str(ROOT / "tools/render_ios_video_fixture.swift"), str(fixture), str(audio), timeout=180)
        report["generated_video_fixture"] = {"duration_ms": 12400, "audio": True, "source": "synthetic CI output"}
        gif_fixture = output / "fixture-animation.gif"
        run("swift", str(ROOT / "tools/render_ios_gif_fixture.swift"), str(gif_fixture), timeout=120)
        report["generated_gif_fixture"] = {"frames": 82, "uneven_delays": True, "source": "synthetic CI output"}
        stage = "build"
        generate(IOS / "OldFunny.xcodeproj")
        work = ROOT / ".ios-work/ios-port/preview-build"
        command = ["xcodebuild", "-project", str(IOS / "OldFunny.xcodeproj"), "-scheme", "OldFunny",
                   "-configuration", "Debug", "-sdk", "iphonesimulator", "-destination", "generic/platform=iOS Simulator",
                   "-derivedDataPath", str(work), "ARCHS=arm64", "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO",
                   "SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG CLASSIC_UI_PREVIEW", "build"]
        with (output / "build.log").open("w") as log:
            subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=600)
        app = work / "Build/Products/Debug-iphonesimulator/OldFunny.app"
        # Xcode 16 can place Debug app code in OldFunny.debug.dylib while its
        # executable is a small launcher. Inspect both layouts before launch.
        preview_binaries = [app / "OldFunny", *app.rglob("*.dylib")]
        if not any(b"preview.invalid" in path.read_bytes() for path in preview_binaries):
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
        stage = "simulator"
        device = run("xcrun", "simctl", "create", "OldFunnyOfflinePreview", kind["identifier"], runtime["identifier"]).strip()
        run("xcrun", "simctl", "boot", device)
        run("xcrun", "simctl", "bootstatus", device, "-b", timeout=300)
        run("xcrun", "simctl", "status_bar", device, "override", "--time", "9:41", "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3", "--batteryState", "charged", "--batteryLevel", "100")
        run("xcrun", "simctl", "install", device, str(app))
        report.update(simulator_device=kind["name"], simulator_ios=runtime["version"])
        stage = "screenshots"
        for name, args in [("feed", []), ("sidebar", ["--preview-sidebar"]), ("comments", ["--preview-comments"]), ("information", ["--preview-information"]), ("profile", ["--preview-profile"]), ("profile-search", ["--preview-profile-search"])]:
            run("xcrun", "simctl", "launch", "--terminate-running-process", device, "mobi.oldfunny.ios", *args)
            time.sleep(3)
            path = output / (name + ".png")
            run("xcrun", "simctl", "io", device, "screenshot", "--type=png", str(path))
            report["screenshots"].append(path.name)
        # Exercise actual touch gestures in the separately compiled offline app.
        # Policy unit tests alone cannot establish UIKit recognizer arbitration.
        # xcodebuild test installs its build product again. Copy this generated
        # fixture after test compilation, then run without rebuilding the app.
        test_command = ["xcodebuild", "-project", str(IOS / "OldFunny.xcodeproj"), "-scheme", "OldFunny",
                        "-configuration", "Debug", "-destination", "platform=iOS Simulator,id=" + device,
                        "-derivedDataPath", str(work), "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO",
                        "SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG CLASSIC_UI_PREVIEW",
                        "-parallel-testing-enabled", "NO", "build-for-testing"]
        stage = "gesture-tests"
        with (output / "ui-tests.log").open("w") as log:
            subprocess.run(test_command, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=600)
            import shutil
            shutil.copyfile(fixture, app / fixture.name)
            shutil.copyfile(gif_fixture, app / gif_fixture.name)
            test_command[-1:] = ["-resultBundlePath", str(output / "ViewerTests.xcresult"), "test-without-building"]
            subprocess.run(test_command, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=600)
        report["ui_gesture_tests"] = verify_gesture_tests((output / "ui-tests.log").read_text(), (IOS / "UITests/ViewerTests.swift").read_text())
        report["ui_gesture_tests_passed"] = True
        report["success"] = True
    except Exception as error:
        report.update(success=False, failed_stage=stage, error=str(error))
        log = output / ("ui-tests.log" if stage == "gesture-tests" else "build.log")
        if log.exists(): print("\n".join(log.read_text(errors="replace").splitlines()[-50:]))
        raise
    finally:
        (output / "preview.json").write_text(json.dumps(report, indent=2) + "\n")
        result = output / "ViewerTests.xcresult"
        if result.exists():
            # The root includes issue summaries even when the app terminates
            # before an XCTest assertion can describe the underlying exception.
            with (output / "xcresult-summary.json").open("w") as summary, (output / "xcresult-export.log").open("w") as errors:
                subprocess.run(["xcrun", "xcresulttool", "get", "object", "--legacy", "--format", "json", "--path", str(result)], stdout=summary, stderr=errors, timeout=60)
        if device:
            # This disposable simulator only runs fabricated offline fixtures.
            # Preserve app fault details before deleting it, including when an
            # XCTest element timeout is really an app termination.
            with (output / "simulator-app.log").open("w") as log:
                subprocess.run(["xcrun", "simctl", "spawn", device, "log", "show", "--style", "compact", "--last", "15m", "--predicate", 'process == "OldFunny"'], stdout=log, stderr=subprocess.STDOUT, timeout=60)
            subprocess.run(["xcrun", "simctl", "shutdown", device], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
            subprocess.run(["xcrun", "simctl", "delete", device], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
    print(json.dumps(report, indent=2))


if __name__ == "__main__": main()
