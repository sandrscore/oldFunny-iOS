# Native iOS port status

Target: iPhone16 / user-reported iOS27.0.1. Bundle: `mobi.oldfunny.ios`.
**Full Android behavioral parity is incomplete.** See [ANDROID_PARITY.md](ANDROID_PARITY.md).

| Evidence | Current state |
| --- | --- |
| Verified source | 0.3.0/build28, `1fe0428699b6185792f721bac73aad03fc1e929b` |
| Mac contracts | 74 Swift and six Python checks passed |
| Actual UIKit | All23 offline cases executed/passed, zero failures |
| Comment menus/depth | Role menus, separate reply-count read navigation, author targets, composer focus, capped dots/depth30 passed |
| Deleted replies | Native separate placeholder, root retention, no live controls, refresh/draft/attachment/count checks passed; screenshot reviewed |
| Previous flows | Video/GIF, retained panels, profile/search/pins/subscriptions, mentions and bulk deletion passed again |
| IPA | Independently ARM64/cryptid0/unsigned/fixture-free; SHA256 `8af68fb23d0a56e28a86fbdbb7762ed000b651b07d1d437de8ed9c6dcdeedd15` |
| Attachments | Actual crop pixels, four-card cap/badges, hold selection, API404 recovery/Back, unavailable/failed/withheld/linked/blocked states and draft retention passed |
| Server | Three anonymous GETs verified candidate28 directAPI200 and API404->publicwebsite200 exact picture recovery; no social/read writes |
| Phone | Earlier0.1.2 login/CAPTCHA confirmed by user; current-build sessions/gestures/media/Photos untested on target |

[Build28 CI/artifacts](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40407953474).
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
