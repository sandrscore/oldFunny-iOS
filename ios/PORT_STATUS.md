# Native iOS port status

Target: iPhone 16 / user-reported iOS 27.0.1. Bundle: `mobi.oldfunny.ios`.
**Full behavioral parity is incomplete.** [ANDROID_PARITY.md](ANDROID_PARITY.md)
is the detailed contract, evidence map and gap ledger.

| Evidence level | Current state |
| --- | --- |
| Source | 0.3.0/build 8 candidate: retained vertical panels, comment attachment picker/draft protection/actions, Collective, unsmile/republish/Photos; header context/X/test-gate corrections |
| Portable checks | 22 Swift contract tests and 6 Python packaging/test-verification checks pass locally |
| Mac compilation | Build 7 source `618c148e596d8f8a3bd199c1bbdaa58a70922071` compiled successfully; build 8 pending |
| IPA inspection | Downloaded build 7: ARM64, cryptid=0, unsigned, no preview markers/test bundles; SHA-256 `e1a4c6693c6af8116a3706b00ee6c945629c7a6679df356b264277a481ae00f6` |
| UIKit gestures | Build 7: 3 executed, 1 passed, 2 failed (header context and keyboard-dismissal routing); build 8 tests pending |
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
