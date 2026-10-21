# Native iOS port status

Target: iPhone 16 / user-reported iOS 27.0.1. Bundle: `mobi.oldfunny.ios`.
**Full Android behavioral parity is incomplete.** See [ANDROID_PARITY.md](ANDROID_PARITY.md).

| Evidence | Current state |
| --- | --- |
| Verified source | 0.3.0/build 21, `4c990a36420f8f9e2d5dfbb6c55ee603cdace6e1` |
| Mac contracts | 58 Swift tests and 6 Python packaging/test-verification checks passed |
| Actual UIKit | All 17 offline tests executed and passed, zero failures |
| Mentions | Actual suggestion selection, pagination, profile link, uncertain receipt and exact accepted reply fields passed |
| Media/profile | Prior decoded video/GIF, panels/drafts, search/tags/pins/subscription cases passed again |
| IPA | Independently verified ARM64, cryptid=0, unsigned and fixture-free; SHA-256 `e6f1731005e4f8660bebc288f1c11b3e15f7ff6c21c14b915b51f79b0c661aff` |
| New candidate | Build 22: original-author bulk selection/receipt/count/read-recovery source; 63 Linux core tests and 6 packaging checks pass, 20 UIKit tests pending |
| Server | Earlier bounded anonymous profile/feed/schema reads succeeded; no live social writes used for validation |
| Phone | Earlier 0.1.2 sign-in/CAPTCHA confirmed by user; build 21/22 saved session, codecs, gestures and Photos untested on target |

[Build 21 CI/artifacts](https://github.com/sandrscore/oldFunny-iOS/actions/runs/39539381754). Downloaded reports/logs were checked and the
incoming mention screenshot reviewed. Remaining scope includes ordinary row tap/
options, depth and full comment states, mention panel physics, profile options/
indexing, feeds/reads, Explore/Activity/preferences, Chats/groups and Studio.
Valid iOS client setup is required for APNs and alternate OAuth.

Authentication algorithms, Android sources and the same 16 reviewed bitmap assets
are preserved. No credentials, personal sessions, original binaries or generated
test media are included in public source exports or Release IPAs.
