# Native iOS port status

Target: iPhone16 / user-reported iOS27.0.1. Bundle: `mobi.oldfunny.ios`.
**Full Android behavioral parity is incomplete.** See [ANDROID_PARITY.md](ANDROID_PARITY.md).

| Evidence | Current state |
| --- | --- |
| Verified source | 0.3.0/build27, `f205168b98f5c886a26b0e758393b5137b8932e1` |
| Mac contracts | 67 Swift and six Python checks passed |
| Actual UIKit | All22 offline cases executed/passed, zero failures |
| Comment menus/depth | Role menus, separate reply-count read navigation, author targets, composer focus, capped dots/depth30 passed |
| Deleted replies | Native separate placeholder, root retention, no live controls, refresh/draft/attachment/count checks passed; screenshot reviewed |
| Previous flows | Video/GIF, retained panels, profile/search/pins/subscriptions, mentions and bulk deletion passed again |
| IPA | Independently ARM64/cryptid0/unsigned/fixture-free; SHA256 `67488a070a27fb8eb08348663dc281e097620861ba94fbe98334d2cab30798f6` |
| Candidate28 | Inbound attachment/full-post/public-picture slice,74core/23UI; local tests/parser pass, Mac/UIpending |
| Server | Three anonymous GETs verified candidate28 directAPI200 and API404->publicwebsite200 exact picture recovery; no social/read writes |
| Phone | Earlier0.1.2 login/CAPTCHA confirmed by user; current-build sessions/gestures/media/Photos untested on target |

[Build27 CI/artifacts](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40404742369).
Reports/logs/complete xcresult and original screenshots were downloaded and checked.
Candidate28 has not been certified by build27's green checks. HTTP-only thumbnail
loads, stream-time payload limits, external browser runtime, exact notice style,
format/EXIF edges and broad lifecycle cases remain gaps. Full ledger also includes
feeds/read tracking, Explore/Activity/preferences, Chats/groups and Studio.

Authentication algorithms/five auth files, Android and the same16 reviewed bitmaps
are preserved. Public exports/Release contain no personal sessions, credentials,
original apps or fabricated test media. APNs/alternate OAuth need valid iOS setup.
