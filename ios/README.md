# oldFunny iOS

**0.3.0 build 9 candidate: Android behavior port in progress.**

Retained media/comments/information panels reproduce the Android vertical
arrangement. Comments keep text and one attached post across panels/picker Back.
The next source slice adds retained reply threads with root context and a selected
recipient chip, root-read/recipient-write routing, inline reactions/net score,
pre-write session fencing and viewport-based image sizing. Full parity remains
incomplete; see [the behavioral ledger](ANDROID_PARITY.md).

Build 8 (`81709ce66c7568f25ed2d60f0a2f1d620f5ec897`) compiled and passed 22 Mac
contract tests and 6 Python checks. Its downloaded IPA independently verifies as
0.3.0/build 8, ARM64, cryptid=0, unsigned, no preview/test code. SHA-256:
`824edafacbc964a54c057226ef5a9072770204206bb1a20920c124e387583d82`.
[CI and diagnostics](https://github.com/sandrscore/oldFunny-iOS/actions/runs/39495282820).
UIKit executed four tests: three passed, one failed. Header context, attachment
picker/draft retention, paging/zoom and keyboard dismissal pass; downward header
fling still fails. The mandatory CI gate reports failure. It is not a verified
gesture release. Build 9 fixes gesture admission using the original touch target;
it is not yet compiled. Its 26 local Swift tests and 6 Python checks pass.

Video still uses AVPlayer controls. Comments mentions/bulk deletion/depth/state
rules, profiles/search/pins, read queues, Explore/Activity/settings, Chats/groups
and Studio/publishing remain incomplete. Source, portable tests, UIKit automation,
server behavior and actual iPhone testing are tracked separately.

The user confirmed password sign-in and in-app CAPTCHA in 0.1.2 on iPhone 16 /
reported iOS 27.0.1. That flow is preserved; sign-in, refresh and authenticated-call
algorithms are unchanged. Current agent validation uses offline fixtures only.
Saved-session relaunch, gestures, codecs and Photos still need phone checks.
The previous 0.2.0/build 6 IPA remains preserved locally with SHA-256
`91abe2d26c5fb00cae5311145f71696fa901570da6942dac021564da2cc9a3b5`.
Bundle: `mobi.oldfunny.ios`. Minimum iOS: 16.0. Zeus signing is a separate device step.

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
