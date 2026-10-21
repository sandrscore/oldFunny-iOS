> Candidate19 fixes GIF dimensions using per-frame metadata when global dimensions
> are absent; the runtime result is still pending. Build18 compiled with48Mac
> core/6Python checks and15UIKit tests executed,14passed/1GIFloadfailed. All profile/
> search/tag/pin/subscribe, video and comment checks passed. The grid log confirms
>18totalitems versus15accessiblecells, with first/last-ID and scroll checks.
> Build18IPA independently verified ARM64/cryptid0/fixture-free, SHA256:
> `b15f9a021c3557f073f9a0b2ef6c0c3e614017ece8096b2e3483f49b0657337a`.
> No target-phone or live social write check. Build11 below remains last fully
> green offline checkpoint until every expected current test passes.

# Native iOS port status

Target: iPhone 16 / user-reported iOS 27.0.1. Bundle: `mobi.oldfunny.ios`.
**Full Android behavioral parity is incomplete.** The detailed contract and gaps
remain in [ANDROID_PARITY.md](ANDROID_PARITY.md).

| Evidence level | Current state |
| --- | --- |
| Source | 0.3.0/build 11: retained vertical panels/drafts; own-post attachment picker; retained reply root/recipient; inline serialized reactions; captured-session guards; resolved media sizing; reply/post counts and retained deleted roots |
| Automated contracts | 27 Mac Swift tests and 6 Python packaging/test-verification checks pass |
| Actual UIKit | All 7 offline tests pass, zero failures: vertical panels, slow rejection/fast return, keyboard/drafts, attachments, reply retention, paging/zoom, fitted geometry, rejected reactions, confirmed reply/delete counts |
| IPA | Downloaded and independently verified ARM64, cryptid=0, unsigned, no fixture/test code; SHA-256 `3c211f82d370d522f2f55f8762bb700ccfb12c81dfc4ef543b85b5dd68b5912c` |
| Simulator render | Feed/sidebar/comments/information reviewed on iPhone 16 / iOS 18.5; comments Refresh glyph is visible |
| Server | Earlier anonymous Featured reads succeeded; new feature behavior unverified on the real server; no live social writes used for validation |
| Target phone | User confirmed 0.1.2 sign-in/CAPTCHA and earlier feed loading. Build 11 saved session, gestures, codecs and Photos still need actual iPhone testing |

Compiled source: `9dd9ac22bfc72b1bd0b329d4f8236bd91e2b2cda`.
[CI and artifacts](https://github.com/sandrscore/oldFunny-iOS/actions/runs/39502078271).
Zeus signing/installation is a separate device step; simulator success does not
establish target OS or server parity.

Next work includes Android unsmile context eligibility,
mentions/bulk selection/depth/full state/lifecycle,
custom video/GIF zoom/play/scrub/mute and saving, full profiles/search/pins,
read queues/badges, Explore/Activity/preferences, Chats/groups and Studio/publishing.
APNs and alternate OAuth require separate iOS client setup and validation.

Authentication files and signIn/refresh/call algorithms remain unchanged. New
social endpoint wrappers add pre-write captured-session checks. The same 16
reviewed artwork files and Android/protected-file hashes are preserved. Public
source/export includes no personal credentials, sessions or original binaries.
