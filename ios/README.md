# oldFunny iOS

**Verified checkpoint: 0.3.0/build 19. Candidate build 20 adds comment mentions;
its Mac compilation and UIKit tests are pending. Full Android parity is incomplete.**

[Download the build 19 unsigned IPA artifact ZIP](https://github.com/sandrscore/oldFunny-iOS/actions/runs/39526685353/artifacts/12313263187),
extract the IPA and update through Zeus. SHA-256:
`86fe2202410f483ee52fe45791d019eedc672aa4dff7be019967b775b0af84c5`.
Bundle `mobi.oldfunny.ios`; minimum iOS 16.0; ARM64, cryptid=0, unsigned.
Artifacts expire October 28, 2026; an independently verified local copy and exact
source archive are preserved in the original workspace.

[Build 19 Mac CI](https://github.com/sandrscore/oldFunny-iOS/actions/runs/39526685353) for source `86394bb2f59dd7cd16e7593ee2ddcf1dea80b906` passed
48 core tests, 6 packaging/test-verification checks and all 15 actual UIKit tests.
The downloaded reports and logs confirm execution with zero failures. Tests cover
vertical panels/drafts/replies/attachments, paging/zoom, confirmed comment counts,
video decoded-frame seeking/pause/mute/zoom/return, long GIF decoded pixels/timing/
loop/retained phase, context-gated triple taps, profiles/featured/grid return,
combined search, tag editing, pin readback and subscriptions. These are offline
fixtures on iPhone 16 / iOS 18.5, separate from server and target-phone validation.

Build 20 source adds authenticated mention suggestions, exact selected user IDs
and UTF-16 edit ranges, colored draft names and incoming profile links, and the
`user_mentions` send field. Two added UIKit tests exercise selection/pagination,
attachment and Back retention, uncertain receipts, link taps and confirmed reply
forms. 58 portable core tests pass locally; current Mac/UIKit verification is
pending. No live comments or mention notifications were sent.

Remaining work includes full comment state/depth/bulk handling, suggestion panel
physics, large-profile indexing and other profile options, feed/read queues,
Explore/Activity/settings, Chats/groups and Studio/publishing. Special GIF/codec/
Photos cases and new saved-session behavior still require phone checks. See the
[behavioral ledger](ANDROID_PARITY.md) for the complete scope and gaps.

The user's last target-phone confirmation is 0.1.2 sign-in/CAPTCHA. Authentication
algorithms and the same 16 reviewed bitmap assets are preserved; credentials,
sessions and original binaries are excluded. Android remains unchanged.

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
