> 0.3.0 build 7 is being compiled and checked against the Android behavior inventory in [ANDROID_PARITY.md](ANDROID_PARITY.md). The 0.2.0 artifact below is the previous build.

# oldFunny iOS

**0.2.0 (build 6): first classic interface pass.**

A new Swift/UIKit client with a charcoal author/avatar bar, dark sidebar,
full-width black media viewer, compact smile/comment/share controls, and classic
comment rows with blue names, circular avatars, dates and attached-post previews.
The sidebar opens Featured, Subscriptions, Profile and Account. Existing image
zoom, native video controls, text-video titles/body and explicit actions remain.

[Download the unsigned IPA artifact ZIP](https://github.com/sandrscore/oldFunny-iOS/actions/runs/39488614457/artifacts/12293774317)
— extract the IPA and sign/update through Zeus. Artifact expires October 27, 2026.
A verified local copy remains in the original workspace's ignored .ios-work.

IPA SHA-256: `91abe2d26c5fb00cae5311145f71696fa901570da6942dac021564da2cc9a3b5`.
Bundle: `mobi.oldfunny.ios`. Minimum iOS: 16.0. Executable: ARM64, cryptid=0,
unsigned, built from this source. This is not an APK binary conversion or a
modification of iFunny's encrypted executable.

## Verification and device check

[Successful Mac build](https://github.com/sandrscore/oldFunny-iOS/actions/runs/39488614457)
from source commit `5f58a60fa4c428e5eb9f5870d774efc24cbd2f03` passed all 18
portable Swift tests and compiled both the iPhone Release app and simulator
preview. Five local Python build/export tests passed. The downloaded artifact
and IPA hashes were independently verified; no embedded architecture blockers,
FairPlay resources or offline preview fixture marker were found in the release.

[Simulator screenshots](https://github.com/sandrscore/oldFunny-iOS/actions/runs/39488614457/artifacts/12295550123)
show the actual feed, open sidebar and comments on an iPhone 16 / iOS 18.5
simulator. These were visually inspected with offline generated sample content.
They establish layout only, not real server/account behavior or iOS 27 support.

The user confirmed Featured loading, and successful password sign-in with CAPTCHA
in 0.1.2 on their iPhone 16 / reported iOS 27.0.1. Six authentication/session
source files are byte-for-byte unchanged by this UI pass. The new build has not
been signed, installed or tested on that phone. Update via Zeus, then check saved
sign-in, feed swiping, sidebar routes, image/video viewing and comments. Pull down
to refresh comments; the optional trailing header refresh icon needs follow-up
visual polish. No posting/chat action is required for these initial checks.

Complete Android feature parity remains unfinished. Collective, Explore/search,
Chats, Studio/publishing, push, Google/Apple sign-in, advanced profile/settings,
read queues/badges, Photos exports and other additions still require native work.
See [feature status](PORT_STATUS.md) and [protocol provenance](PROTOCOL_PROVENANCE.md).

## Build and test

On a Mac with Xcode and an iOS SDK:

```sh
python3 tools/build_ios_native.py
```

The output is .ios-work/ios-port/dist/oldFunny-ios-0.2.0-unsigned.ipa, with a
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
disposable simulator, renders feed/sidebar/comments, saves PNGs and preview.json
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
