# Native iOS port status

Target: iPhone 16 / user-reported iOS 27.0.1. Bundle: `mobi.oldfunny.ios`.
**Full behavioral parity is incomplete.** [ANDROID_PARITY.md](ANDROID_PARITY.md)
is the detailed contract, evidence map and gap ledger.

| Evidence level | Current state |
| --- | --- |
| Source | 0.3.0/build 9 candidate: original-touch gesture arbitration; retained reply root/recipient/draft; inline reactions/net scores; fitted sizing; captured-session guards. Existing panels, attachments, Collective and post actions preserved |
| Portable checks | 26 Swift contract tests and 6 Python packaging/test-verification checks pass locally |
| Mac compilation | Build 8 source `81709ce66c7568f25ed2d60f0a2f1d620f5ec897` compiled successfully; build 9 pending |
| IPA inspection | Downloaded build 8: ARM64, cryptid=0, unsigned, no preview markers/test bundles; SHA-256 `824edafacbc964a54c057226ef5a9072770204206bb1a20920c124e387583d82` |
| UIKit gestures | Build 8: 4 executed, 3 passed, 1 failed (downward return fling); header, paging/zoom, attachments/draft and keyboard dismissal pass; build 9 pending |
| Server | Earlier anonymous Featured read succeeded. No new live social writes or personal session used for agent validation |
| Target iPhone | User confirmed 0.1.2 sign-in/CAPTCHA and earlier feed loading; 0.3.0 candidate gestures/media/Photos/session relaunch untested |

Video/GIF controls still use AVPlayer; precise Android zoom/tap/seeking/mute
rules, GIF conversion, comments mentions/bulk deletion, complete profiles/search/
pins, read queues/badges, Explore/Activity/preferences, Chats/groups and Studio/
publishing remain gaps. APNs and alternate OAuth require separate iOS setup and
validation. Details and acceptance gates are maintained in the parity ledger.

Authentication flow and the reviewed 16 artwork files are preserved. Feature
endpoints changed APIClient; sign-in/shared-refresh/request authentication logic
was not changed. Android/protected files still match the saved baseline.
No credentials, sessions or original binaries are included in public source.
