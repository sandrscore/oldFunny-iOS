# oldFunny iOS

**0.3.0 build 8 candidate: Android behavior port in progress.**

Retained media/comments/information panels now reproduce the Android vertical
navigation arrangement. Comments keep text and one attached post while switching
panels and using the own-post picker. Single-attempt comment actions, unsmile,
republish, Collective and explicit Photos saving are implemented in source.
Full Android parity remains incomplete; see [the behavioral ledger](ANDROID_PARITY.md).
Video still uses AVPlayer controls, and profiles/search, read tracking,
Explore/Activity/settings, Chats/groups and Studio/publishing still need work.

Build 7 from commit `618c148e596d8f8a3bd199c1bbdaa58a70922071` passed Mac Release
compilation and 22 core tests. Its downloaded IPA independently verifies as
version 0.3.0/build 7, bundle `mobi.oldfunny.ios`, ARM64, cryptid=0, unsigned, with
no preview fixture marker or UI-test bundle. SHA-256:
`e1a4c6693c6af8116a3706b00ee6c945629c7a6679df356b264277a481ae00f6`.
[Build and artifacts](https://github.com/sandrscore/oldFunny-iOS/actions/runs/39493347021).
Its UIKit run executed three tests: one passed and two failed (header context and
keyboard-dismissal touch routing). These are being corrected in build 8.

Build 8 source fixes the per-post feed header, adds a visible attachment X, corrects first-outside-tap keyboard routing,
extends the offline picker/draft UI tests and makes gesture success a mandatory
CI gate after diagnostics are retained. It is not yet compiled or phone-tested.
Six local Python packaging/test-gate checks and 22 Swift contract tests pass.

The user confirmed password sign-in and in-app CAPTCHA in 0.1.2 on their iPhone
16 / reported iOS 27.0.1. That flow is preserved. The current gesture candidate
has not been signed or tested on that phone; session relaunch, gestures, codecs
and Photos behavior require device checks. Agent validation uses offline fixture
transports and performs no live social writes. APIClient gained feature endpoints;
its sign-in, shared refresh and request authentication algorithms remain unchanged.

The previous 0.2.0/build 6 IPA remains preserved locally with SHA-256
`91abe2d26c5fb00cae5311145f71696fa901570da6942dac021564da2cc9a3b5`.
Minimum iOS: 16.0. Zeus signing/installation are separate user device steps.

## Build and test

On a Mac with Xcode and an iOS SDK:

```sh
python3 tools/build_ios_native.py
```

The output is .ios-work/ios-port/dist/oldFunny-ios-0.3.0-unsigned.ipa, with a
.sha256 file and .inspection.json report. Choose an unused --output path for
repeat builds. No Apple account, signing certificate or original iFunny binary
is used. Zeus signing and installation are separate device steps.

The public repository's Build oldFunny iOS workflow uses a standard GitHub-hosted
Mac runner. It refuses private repositories to avoid paid private-repository
minutes; artifacts are retained seven days. No Apple secrets are configured.

On Linux or Mac with Swift 5.9 or newer:

```sh
swift test --package-path ios/OldFunnyCore --scratch-path .ios-work/ios-port/core-build
```

Tests cover public protocol signatures, request encoding, trusted CAPTCHA
callbacks, session storage/refresh boundaries, paging, attached posts and modern
avatar schemas. A separately enabled OldFunnyProbe --anonymous-read-only performs
one anonymous feed GET; it performs no sign-in or social writes.

## Offline UIKit previews

```sh
# Mac with an installed iOS simulator runtime:
python3 tools/preview_ios_native.py
```

The tool compiles a separate CLASSIC_UI_PREVIEW configuration, creates its own
disposable simulator, renders feed/sidebar/comments/information and runs UIKit gesture tests, saves PNGs and preview.json
under .ios-work/ios-port/ui-previews, then removes that simulator. It uses no real
account, Keychain session or API request. The preview marker is checked before
launch, including Xcode's separate Debug library. Release packaging refuses it.
The fixture code is excluded from the Release IPA.

## Resources and source export

Only the same 16 reviewed PNGs are included. Some recovered catalog variants
(smile/comments/subscribe) are entirely transparent; native vector equivalents
now render those controls. Their original files and hashes remain preserved.
The approved Android eyepatch launcher and recovered Featured icon are retained.
Local reference screenshots and original archives are excluded from publication.

```sh
python3 tools/ios_native_project.py generate
python3 tools/ios_native_project.py export-source --include-assets --output .ios-work/ios-port/oldFunny-ios-source.zip
```

Use an unused output filename. The export allowlists native code, tools,
documentation, tests and reviewed icons. It excludes app archives, credentials,
sessions, DRM, provisioning and the Android workspace. Generated Xcode projects,
asset catalogs, local tools and build work remain ignored.

The original recovery under .ios-work/restoration/4.6.8 and baseline.json retain
iFunny iOS 4.6.8's identity/resources. Its executable stays encrypted and is not
part of the native source build. The Android implementation remains unchanged.
