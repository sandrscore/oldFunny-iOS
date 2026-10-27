# oldFunny iOS

**Verified checkpoint: 0.3.0/build 30. Full Android behavioral parity is incomplete.**

[Download the build 30 unsigned IPA artifact ZIP](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40413896528/artifacts/12695150733), extract the IPA and update through Zeus. SHA-256:
`2742eacbc8252e8daf8a575383e2dc7ed9d9f0dcff48780fcb917da77ef7bfab`.
Bundle `mobi.oldfunny.ios`; minimum iOS 16; ARM64, cryptid0, unsigned and fixture-free. Artifact expires November 2, 2026. The independently inspected IPA and exact source are preserved locally.

[Build 30 Mac CI](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40413896528), source `b526db3d7745dcd68754edd49547eb4932d3279e`, passed 93 Swift tests, six packaging checks and all 25 actual UIKit cases. Downloaded reports/logs match every expected test; artifact hashes and two actual read-tracking screenshots were checked. Fake HTTP exercised same-account token refresh, failed Featured ACK without blocking Subs, delayed media/visibility, immediate Subs credit, failed/cancelled/confirmed clear and disabled pending choice. Current-build target-phone behavior remains unverified.

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

Build 23 stopped during app compilation on a remaining read-refresh call to the
removed deleted-context helper; no IPA or UI test execution resulted. Build 24
restores that read helper separately from confirmed root deletion.

Build 26 compiled with 67 Mac core/six packaging checks and executed all 22 UIKit
cases: 21 passed, including both new role/navigation/depth tests. The deleted-reply
case failed because a depth-strip accessibility element remained discoverable.
That assertion alone does not establish whether dots were visibly drawn. Android's
reply adapter uses a distinct placeholder layout for deleted nonroot replies;
build 27 adopts that structure and exact caption with no live author/reaction/dot
children. The root context uses its existing separate path. Count, draft, attachment
and refresh assertions remain required; no UIKit case is removed. The inbound
multi-attachment/public-picture work remains excluded from this focused repair.

Candidate 28 follows Android AttachmentSpec/PictureComments/PreviewCrop: up to four
cards, primary/link-derived fallback, proportional thumbnail selection, comic-top
and video-center crop, GIF/VIDEO badges, known-unavailable and failed-preview
states, withheld text and suppression for abused/deleted comments. Tapping reads
the complete post before pushing its viewer, preserving comment/draft Back state.
Only an API404 can use the credential-free public-picture JSON recovery path.
The thumbnail cache is separate from full-post GIF playback: strict10MiB LRU,
two workers,64 waiters,8MiB compressed payload and power-of-two sampling to1024.
Missing original-author data never grants moderation to a republisher.

All74 portable Swift contracts and six packaging checks pass locally. The new
23rd UIKit case checks actual ImageIO-decoded crop pixels, four-card limit,
attachment hold-selection, unavailable/failed/withheld/blocked/link-derived states,
404 recovery, full-post navigation and retained drafts. It has not run on Mac yet.
Three bounded anonymous GETs additionally confirmed one API200 full-picture read
and one API404->website200 exact-ID recovery. No account/session or social/read
write was used. Legacy HTTP-only thumbnails, stream-time download limits,
external-browser runtime checks and exact notice presentation remain gaps.

The recovery trigger is the actual HTTP404 status. A status404 JSON envelope on
HTTP200 does not invoke website recovery. The shared request loop returns its raw
HTTP result before parsing, retaining account fences/read-only refresh/no write
replay; content and ordinary callers check their captured epoch again.

Candidate29 integrates durable per-account seen/pending history, serialized idempotent acknowledgements, counters and filtered Featured paging. Actual selected/window/foreground/panel/drawer/pager gates use a continuous1800ms rendered-media timer for Featured; Subscriptions04 credits settled loading selections immediately. Active failures retry after10s, successful queued batches continue immediately. Sidebar shows reconciled Subs unread and offers confirmed mark-all only on its long hold. Atomic private files persist IDs/progress, while credentials remain in Keychain.

90 Linux core tests, six packaging checks and Debug/Release syntax parsing pass. Two new offline UIKit cases (25 total) exercise loading/visible exposure, drawer/comments/prefetch exclusion, immediate Subs credit/stale counters and cancelled/failed/confirmed explicit clear/navigation. These native cases await Mac execution; build28 remains the verified IPA. Read fixtures never use a real account or service. Featured stale-cache policy, other sidebar destinations/counters, exhaustive lifecycle/process/device coverage and the full ledger remain open.

### Build29 results and focused30 read correction

Source `98e048e8c8e6f5f8e77c6d256eede91e2e6b83a1`, [Mac CI](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40411120296), passed90 Mac Swift, six Python and all25 actual UIKit cases, zero failures. Exact names/logs/preview.json and archive digests checked; actual Featured selected-read and Subs confirmed-clear screenshots reviewed. IPA independently ARM64/cryptid0/fixture-free, SHA256 `479fc8f3123f3e31eaadf17d6a07c240a98cb785f37163ef957559eb1ce10b1d`. New UI checks completed rendered-delay/drawer/comments/prefetch exclusion and actual settled reads, loading Subs immediate credit/stale counter retention, cancelled/failed/confirmed explicit clear and navigation retention. No real read ACK/social write or target-phone test.

Separate regression tests reproduced two29 issues: an existing GET401->token refresh->GET200 was rejected by the new wrapper as sessionChanged, and failed Featured ACKs prevented Subs ACK/counters. Candidate30 permits one read retry only for a changed token in the same account key/epoch/signed status and returns the accepted context; account/sign-out changes still reject without retry. Queues now make independent progress under the same lock while failed IDs remain pending. Authentication algorithms and single-attempt social-write rules are unchanged.

30 also resets exposure synchronously on panel changes, avoids redundant fixture trace UI updates, and displays a disabled explicit clear choice while pending. The existing Subs native case now requires actual fake token refresh and checks pending choice/duplicate prevention; all25 cases remain. 93 Linux core tests, six packaging checks and native syntax pass;30 Mac/UI results pending. Other ledger gaps remain open.

### Build31 results and focused32 compile correction

Build31 source `5862dbae71f7739f178bb90b24a0c4c4014f2d34`, [Mac CI](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40438785287), passed all99 Mac Swift tests and six packaging checks. Release compilation then failed because ExploreController introduced `next`, `hash` and `tag` properties that collide with inherited UIKit/NSObject properties. No IPA was produced and zero of 26 UIKit cases ran. Focused32 renames those stored properties and retains the exact same behavior and all26 cases; Mac compilation/UI verification remain pending. Build30 remains the verified IPA.
