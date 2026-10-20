> Build 11 source is a candidate for comment count/read-generation/deleted-root and Refresh fixes. The verified build 10 IPA below remains the phone checkpoint. Build 11 Mac/UIKit checks are pending.

# oldFunny iOS

**0.3.0 build 10: verified offline viewer/gesture checkpoint.**

[Download the unsigned IPA artifact ZIP](https://github.com/sandrscore/oldFunny-iOS/actions/runs/39499100759/artifacts/12297949206),
extract the IPA and sign/update through Zeus. SHA-256:
`fe571fee9fe8403d3990acbff354706a9cd3c294299ab1f300c915ffdcb6c334`.
Bundle: `mobi.oldfunny.ios`; minimum iOS 16.0; ARM64, cryptid=0, unsigned.
Artifact expires October 27, 2026; a local verified copy is preserved in the
original workspace. Original binaries, credentials and sessions are excluded.

[Successful Mac CI](https://github.com/sandrscore/oldFunny-iOS/actions/runs/39499100759)
for source `5cca16ac45ac9c208269c6737ef1e36ef582b2a6` passed 26 core tests,
6 packaging/test-verification checks and all 6 actual UIKit tests. The downloaded
IPA, preview report and test logs were independently checked. Four simulator
screens were reviewed on iPhone 16 / iOS 18.5 using offline fixtures only.

Tests cover vertical comments/information entry and return, slow-fling rejection,
keyboard dismissal, retained drafts and reply recipients through Back, attachment
picker/Back/refresh/removal, paging/zoom priority, fitted image size and rejected
inline reactions preserving drafts. Production gesture thresholds remain the
Android values. This verifies those fixture interactions, not full Android parity
or iOS 27 compatibility. See [the behavioral ledger](ANDROID_PARITY.md).

The current comments Refresh control is tappable but its initial glyph is
invisible in simulator renders; a follow-up is required. Unsmile eligibility,
reply/post count propagation, deletion states/depth, mentions/bulk deletion,
custom video/GIF controls, complete profiles/search/pins, read tracking,
Explore/Activity/settings, Chats/groups and Studio/publishing remain unfinished.

The user confirmed 0.1.2 password sign-in/CAPTCHA on iPhone 16 / reported iOS
27.0.1. Its sign-in, refresh and request-authentication algorithms are preserved;
new social actions add a captured-session fence. No live social write or new
phone validation was performed. After Zeus update, saved sign-in, vertical
panels, unsent drafts, image/video viewing and Photos still need phone checks.

The previous 0.2.0/build 6 IPA remains preserved with SHA-256
`91abe2d26c5fb00cae5311145f71696fa901570da6942dac021564da2cc9a3b5`.

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
