# Native iOS port status

Target: iPhone16 / user-reported iOS27.0.1. Bundle: `mobi.oldfunny.ios`.
**Full Android behavioral parity is incomplete.** See [ANDROID_PARITY.md](ANDROID_PARITY.md).

| Evidence | Current state |
| --- | --- |
| Verified source | 0.3.0/build30, `b526db3d7745dcd68754edd49547eb4932d3279e` |
| Mac contracts | 93 Swift and six Python checks passed |
| Actual UIKit | All25 offline cases executed/passed, zero failures |
| Comment menus/depth | Role menus, separate reply-count read navigation, author targets, composer focus, capped dots/depth30 passed |
| Deleted replies | Native separate placeholder, root retention, no live controls, refresh/draft/attachment/count checks passed; screenshot reviewed |
| Previous flows | Video/GIF, retained panels, profile/search/pins/subscriptions, mentions and bulk deletion passed again |
| IPA | Independently ARM64/cryptid0/unsigned/fixture-free; SHA256 `2742eacbc8252e8daf8a575383e2dc7ed9d9f0dcff48780fcb917da77ef7bfab` |
| Attachments | Actual crop pixels, four-card cap/badges, hold selection, API404 recovery/Back, unavailable/failed/withheld/linked/blocked states and draft retention passed |
| Server | Three anonymous GETs verified candidate28 directAPI200 and API404->publicwebsite200 exact picture recovery; no social/read writes |
| Phone | Earlier0.1.2 login/CAPTCHA confirmed by user; current-build sessions/gestures/media/Photos untested on target |

[Build30 CI/artifacts](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40413896528).
Reports/logs/complete xcresult and original screenshots were downloaded and checked.
HTTP-only thumbnail
loads, stream-time payload limits, external browser runtime, exact notice style,
format/EXIF edges and broad lifecycle cases remain gaps. Full ledger also includes
feeds/read tracking, Explore/Activity/preferences, Chats/groups and Studio.

Authentication algorithms/five auth files, Android and the same16 reviewed bitmaps
are preserved. Public exports/Release contain no personal sessions, credentials,
original apps or fabricated test media. APNs/alternate OAuth need valid iOS setup.

Candidate29 integrates durable per-account seen/pending history, serialized idempotent acknowledgements, counters and filtered Featured paging. Actual selected/window/foreground/panel/drawer/pager gates use a continuous1800ms rendered-media timer for Featured; Subscriptions04 credits settled loading selections immediately. Active failures retry after10s, successful queued batches continue immediately. Sidebar shows reconciled Subs unread and offers confirmed mark-all only on its long hold. Atomic private files persist IDs/progress, while credentials remain in Keychain.

90 Linux core tests, six packaging checks and Debug/Release syntax parsing pass. Two new offline UIKit cases (25 total) exercise loading/visible exposure, drawer/comments/prefetch exclusion, immediate Subs credit/stale counters and cancelled/failed/confirmed explicit clear/navigation. These native cases await Mac execution; build28 remains the verified IPA. Read fixtures never use a real account or service. Featured stale-cache policy, other sidebar destinations/counters, exhaustive lifecycle/process/device coverage and the full ledger remain open.

### Build29 results and focused30 read correction

Source `98e048e8c8e6f5f8e77c6d256eede91e2e6b83a1`, [Mac CI](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40411120296), passed90 Mac Swift, six Python and all25 actual UIKit cases, zero failures. Exact names/logs/preview.json and archive digests checked; actual Featured selected-read and Subs confirmed-clear screenshots reviewed. IPA independently ARM64/cryptid0/fixture-free, SHA256 `479fc8f3123f3e31eaadf17d6a07c240a98cb785f37163ef957559eb1ce10b1d`. New UI checks completed rendered-delay/drawer/comments/prefetch exclusion and actual settled reads, loading Subs immediate credit/stale counter retention, cancelled/failed/confirmed explicit clear and navigation retention. No real read ACK/social write or target-phone test.

Separate regression tests reproduced two29 issues: an existing GET401->token refresh->GET200 was rejected by the new wrapper as sessionChanged, and failed Featured ACKs prevented Subs ACK/counters. Candidate30 permits one read retry only for a changed token in the same account key/epoch/signed status and returns the accepted context; account/sign-out changes still reject without retry. Queues now make independent progress under the same lock while failed IDs remain pending. Authentication algorithms and single-attempt social-write rules are unchanged.

30 also resets exposure synchronously on panel changes, avoids redundant fixture trace UI updates, and displays a disabled explicit clear choice while pending. The existing Subs native case now requires actual fake token refresh and checks pending choice/duplicate prevention; all25 cases remain. 93 Linux core tests, six packaging checks and native syntax pass;30 Mac/UI results pending. Other ledger gaps remain open.

### Build31 results and focused32 compile correction

Build31 source `5862dbae71f7739f178bb90b24a0c4c4014f2d34`, [Mac CI](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40438785287), passed all99 Mac Swift tests and six packaging checks. Release compilation then failed because ExploreController introduced `next`, `hash` and `tag` properties that collide with inherited UIKit/NSObject properties. No IPA was produced and zero of 26 UIKit cases ran. Focused32 renames those stored properties and retains the exact same behavior and all26 cases; Mac compilation/UI verification remain pending. Build30 remains the verified IPA.
# Build32 simulator result and build33 candidate

Build32 [Mac CI](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40439060560) compiled the unsigned IPA, passed 99 core and six packaging checks, and ran 26 UIKit tests with 25 passing. Explore stopped because the test expected `27 smiles, smile` after the button correctly changed to `27 smiles, remove smile`; the simulator hierarchy confirms the fixture accepted the trending reaction. Build33 corrects both selected-label expectations and retains all 26 tests. Its simulator run and current iPhone testing remain pending; build30 is still the verified checkpoint.

# Build33 result and focused build34 candidate

Build33 [Mac CI](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40441128123) passed 99 core and six packaging checks, compiled the unsigned IPA, and ran 26 UIKit cases with 25 passing. Explore progressed through its earlier reaction and mixed-history checks, then exposed recycled cells still present in UIKit's accessibility hierarchy after clearing all recents. Build34 hides the empty table and checks the empty message as well as the absence of stale cells. All 26 cases remain required; its Mac run and current iPhone testing remain pending. Build30 remains the verified checkpoint.

