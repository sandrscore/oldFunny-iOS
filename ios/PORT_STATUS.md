> Build 11 source adds count/read-generation/deleted-root and Refresh corrections; uncompiled. The verified checkpoint described below is build 10.

# Native iOS port status

Target: iPhone 16 / user-reported iOS 27.0.1. Bundle: `mobi.oldfunny.ios`.
**Full Android behavioral parity is incomplete.** The detailed contract and gaps
remain in [ANDROID_PARITY.md](ANDROID_PARITY.md).

| Evidence level | Current state |
| --- | --- |
| Source | 0.3.0/build 10: retained vertical panels/drafts; own-post attachment picker; retained reply root/recipient; inline serialized reactions; captured-session guards; resolved media sizing |
| Automated contracts | 26 Mac Swift tests and 6 Python packaging/test-verification checks pass |
| Actual UIKit | All 6 offline tests pass, zero failures: vertical panels, slow rejection/fast return, keyboard/drafts, attachments, reply retention, paging/zoom, fitted geometry, rejected reactions |
| IPA | Downloaded and independently verified ARM64, cryptid=0, unsigned, no fixture/test code; SHA-256 `fe571fee9fe8403d3990acbff354706a9cd3c294299ab1f300c915ffdcb6c334` |
| Simulator render | Feed/sidebar/comments/information reviewed on iPhone 16 / iOS 18.5; initial comments Refresh glyph is invisible although its control works |
| Server | Earlier anonymous Featured reads succeeded; new feature behavior unverified on the real server; no live social writes used for validation |
| Target phone | User confirmed 0.1.2 sign-in/CAPTCHA and earlier feed loading. Build 10 saved session, gestures, codecs and Photos still need actual iPhone testing |

Compiled source: `5cca16ac45ac9c208269c6737ef1e36ef582b2a6`.
[CI and artifacts](https://github.com/sandrscore/oldFunny-iOS/actions/runs/39499100759).
Zeus signing/installation is a separate device step; simulator success does not
establish target OS or server parity.

Next work includes visible Refresh, Android unsmile context eligibility,
reply-to-post counts/root deletion, mentions/bulk selection/depth/state/lifecycle,
custom video/GIF zoom/play/scrub/mute and saving, full profiles/search/pins,
read queues/badges, Explore/Activity/preferences, Chats/groups and Studio/publishing.
APNs and alternate OAuth require separate iOS client setup and validation.

Authentication files and signIn/refresh/call algorithms remain unchanged. New
social endpoint wrappers add pre-write captured-session checks. The same 16
reviewed artwork files and Android/protected-file hashes are preserved. Public
source/export includes no personal credentials, sessions or original binaries.
