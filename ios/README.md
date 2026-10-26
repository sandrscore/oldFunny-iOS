# oldFunny iOS

**Verified checkpoint: 0.3.0/build 25. Candidate build 27 follows build 26
with a dedicated deleted-reply placeholder row. Mac/UIKit verification is pending. Full parity is incomplete.**

[Download the build 25 unsigned IPA artifact ZIP](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40010014066/artifacts/12526400847),
extract the IPA and update through Zeus. SHA-256:
`2466cca5f4c34aaa9fd22d84ad12be6eb5a896190e15a49971c297cd0fce8b43`.
Bundle `mobi.oldfunny.ios`; minimum iOS 16.0; ARM64, cryptid=0, unsigned.
Artifact expires October 30, 2026; the independently inspected IPA and exact source
archive are preserved locally in the original workspace.

[Build 25 Mac CI](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40010014066)
for source `a05a335c8ed9fe0eb103f75bace763180e06a165` passed 63 core tests,
6 packaging checks and all 20 actual UIKit cases with zero failures. Downloaded
reports/logs confirm every expected test executed. Comments and incoming mention
screenshots were reviewed on iPhone 16 / iOS 18.5 with offline fixtures.

Tests cover retained panels/drafts/replies/attachments, actual video/GIF decoding,
profiles/search/tags/pins/subscriptions, mention choice/link/exact send fields,
partial bulk deletion, reply placeholders, and complete root-delete return/counts.
The uncertain-write case checks a physical disabled-control tap cannot retry,
a failed read keeps selection locked and a successful read unlocks it. Mention
edits check trailing-space identity retention, interior deletion invalidation and
rapid consecutive deletes without restoring an identity. All social writes use
fake transports. Server notifications and current-build phone validation remain
separate, unverified requirements.

Candidate 26 changes ordinary comment taps to the native role-ordered options
dialog and gives reply counts their own read-only navigation. Reply requires
sign-in and focuses the appropriate composer; depth 30 removes Reply. Reply dots
follow depth-1 capped at 10 on phones/15 on tablets. Avatar/date taps open the
author profile. Two new UI cases check roles, real navigation/focus, capped dot
geometry, the depth boundary, first outside keyboard tap and draft/recipient
retention. All 22 cases remain required. Portable contracts total 67; the separate
inbound multi-attachment/public-picture prototype is excluded from this candidate.

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
