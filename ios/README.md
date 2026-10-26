# oldFunny iOS

**Verified checkpoint: 0.3.0/build 27. Candidate build 28 adds inbound attachment
cards and complete post/public-picture loading. Its Mac/UIKit verification is
pending. Full Android behavioral parity is incomplete.**

[Download the build 27 unsigned IPA artifact ZIP](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40404742369/artifacts/12691086021),
extract the IPA and update through Zeus. SHA-256:
`67488a070a27fb8eb08348663dc281e097620861ba94fbe98334d2cab30798f6`.
Bundle `mobi.oldfunny.ios`; minimum iOS16.0; ARM64,cryptid0,unsigned,fixture-free.
Artifact expires November2,2026; independently inspected IPA and exact source are
preserved locally in the original workspace.

[Build 27 Mac CI](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40404742369)
for source `f205168b98f5c886a26b0e758393b5137b8932e1` passed 67 core tests,
six packaging checks and all22 actual UIKit cases with zero failures. Downloaded
reports/logs confirm every expected test executed. Actual comments and dedicated
deleted-reply screenshot were reviewed on iPhone16/iOS18.5 with offline fixtures.

Role-ordered comment options, separate reply-count navigation, guest/author
routes, root/nested composer focus, depth29/30 eligibility and capped ten-dot
geometry passed. Deleted nonroot replies use Android's distinct centered caption
without author/reaction/dot children. The retained root, draft, attachment,
refresh and count assertions all passed. Previous panels/media/profile/mention/
bulk-deletion cases passed again. All social writes use fabricated transports;
current-build phone and live social behavior remain separate unverified work.

Candidate28 includes74 portable contracts and23 actual UIKit cases. Its new
attachment test exercises ImageIO crop pixels, capped card count and badges,
long-hold selection, public-picture recovery/internal Back, unavailable/failed/
withheld/blocked/link-derived states, refresh and protected drafts. Native/UI
verification is pending; no prior green checkpoint certifies these new files.

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
