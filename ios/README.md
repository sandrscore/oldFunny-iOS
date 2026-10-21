# oldFunny iOS

**Verified checkpoint: 0.3.0/build 21. Candidate build 23 verifies bulk selection
and corrects root-deletion return/counts; its Mac/UIKit checks are pending. Full parity is incomplete.**

[Download the build 21 unsigned IPA artifact ZIP](https://github.com/sandrscore/oldFunny-iOS/actions/runs/39539381754/artifacts/12318721806),
extract the IPA and update through Zeus. SHA-256:
`e6f1731005e4f8660bebc288f1c11b3e15f7ff6c21c14b915b51f79b0c661aff`.
Bundle `mobi.oldfunny.ios`; minimum iOS 16.0; ARM64, cryptid=0, unsigned.
Artifact expires October 28, 2026; the independently inspected IPA and exact
source archive are preserved locally in the original workspace.

[Build 21 Mac CI](https://github.com/sandrscore/oldFunny-iOS/actions/runs/39539381754) for source `4c990a36420f8f9e2d5dfbb6c55ee603cdace6e1` passed
58 core tests, 6 packaging checks and all 17 actual UIKit tests with zero failures.
Downloaded reports and logs confirm each expected test executed. Offline tests
cover retained panels/drafts/replies/attachments, counts, decoded video seeking,
pause/mute/zoom/return, long GIF pixels/timing/loop/phase, classified triple taps,
profiles/search/tags/pins/subscriptions, and mention choice/link/send/error flows.
Mention tests verify exact selected IDs/UTF-16 offsets and attachment fields,
first-tap keyboard dismissal, profile navigation, unconfirmed-draft retention and
identity removal after editing the name. These are iPhone 16 / iOS 18.5 fixtures,
separate from server notifications and actual target-phone validation.

Candidate 22 added original-post-author pencil/hold selection, stable row highlight,
ordered bulk requests and positional acknowledgments. Only confirmed rows affect
counts; failed rows stay selected. Main-root removal counts its replies; reply
removal retains deleted positions and root context. An uncertain receipt locks
selection until a replacement read succeeds, including after a failed refresh.
The app compiled with 63 Mac core tests and six packaging checks passing. The
new test target failed to compile because duplicate-placeholder counts used an
element instead of a query; none of the 20 UIKit cases executed. Candidate 23
corrects those queries and the traced root-deletion behavior: deleting a root
closes its reply screen and removes root plus replies from the post total. The
old retained-thread fixture expectation is replaced with the actual Android
contract. All 20 UIKit cases remain required; native verification is pending.

Remaining work includes ordinary comment tap/options parity, reply-depth/state/
layout rules, mention-panel physics, large-profile indexing/options, feeds/reads,
Explore/Activity/settings, Chats/groups and Studio/publishing. Special media/Photos,
saved-session and new interaction cases still need phone checks. See the complete
[behavioral ledger](ANDROID_PARITY.md); fixture success does not establish parity.

The user's last target-phone confirmation is earlier 0.1.2 sign-in/CAPTCHA.
Authentication algorithms, Android sources and the same 16 reviewed bitmap assets
are preserved. Public exports exclude credentials, personal sessions, original
binaries and generated fixture media. No live social action was performed.

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
