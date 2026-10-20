# oldFunny iOS

**0.3.0 build 10 candidate: Android behavior port in progress.**

The native viewer retains media/comments/information panels and comment drafts.
Attachments keep one own post through picker Back/refresh/removal. Replies retain
their root, selected recipient and draft across Back; inline reactions use one
attempt and a captured-session guard. Full parity remains incomplete; see the
[behavioral ledger](ANDROID_PARITY.md) for all gaps and acceptance gates.

Build 9 (`c031918b4e8adc8274092e7a0e3ac74eaeaf2a75`) compiled with 26 Mac contract
tests and 6 Python checks. Downloaded IPA: 0.3.0/build 9, ARM64, cryptid=0,
unsigned, no preview/test code. SHA-256:
`d9bbd4d6d0b63f9c51af94b88df0b976deb25babdd3381acaf561b6916945cd9`.
[CI diagnostics](https://github.com/sandrscore/oldFunny-iOS/actions/runs/39497337990).
UIKit: 6 executed, 4 passed, 2 failed. Attachments, shared draft, reply retention
and rejected reaction pass. Media remains 300pt high; a synthetic downward drag
ends below Android's 1500 physical px/s threshold and correctly stays in comments.
Build 10 moves sizing to the resolved viewport and tests both slow rejection and
an above-threshold fling. Mac/UIKit verification is pending. It is not a verified
gesture release; no new candidate has been tested on the target phone.

Video/GIF custom controls, reply/post count propagation and deletion states,
mentions/bulk deletion, complete profiles/search/pins, reads, Explore/Activity/
settings, Chats/groups and Studio/publishing remain unfinished. Source, automated
checks, server behavior and actual iPhone tests are tracked separately.

The user confirmed 0.1.2 password sign-in/CAPTCHA on iPhone 16 / reported iOS
27.0.1. Sign-in, refresh and request-authentication algorithms remain unchanged.
Agent validation uses offline fixtures and no live social writes. Saved-session
relaunch, gestures, codecs and Photos still require phone checks. The previous
0.2.0/build 6 IPA remains preserved with SHA-256
`91abe2d26c5fb00cae5311145f71696fa901570da6942dac021564da2cc9a3b5`.
Bundle: `mobi.oldfunny.ios`. Minimum iOS: 16.0. Zeus signing is a separate step.

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
