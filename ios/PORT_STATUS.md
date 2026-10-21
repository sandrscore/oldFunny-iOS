# Native iOS port status

Target: iPhone 16 / user-reported iOS 27.0.1. Bundle: `mobi.oldfunny.ios`.
**Full Android behavioral parity is incomplete.** See [ANDROID_PARITY.md](ANDROID_PARITY.md).

| Evidence | Current state |
| --- | --- |
| Verified source | 0.3.0/build 19, `86394bb2f59dd7cd16e7593ee2ddcf1dea80b906` |
| Mac contracts | 48 Swift tests and 6 Python packaging/test-verification checks passed |
| Actual UIKit | All 15 offline tests executed and passed; zero failures |
| Media checks | Actual decoded video seeking and long GIF pixels, uneven timing, loop and retained phase passed |
| Profile checks | Grid/featured return, combined filters and result reachability, tag editor, pin readback and subscriptions passed |
| IPA | Independently verified ARM64, cryptid=0, unsigned and fixture-free; SHA-256 `86fe2202410f483ee52fe45791d019eedc672aa4dff7be019967b775b0af84c5` |
| New candidate | Build 21: focused mention UI query correction; build 20 compiled with 58 Mac tests and 17 UIKit tests executed, 15 passed and 2 query-type failures |
| Server | Earlier bounded anonymous profile/feed/schema reads succeeded; no live social writes used for validation |
| Phone | User confirmed earlier 0.1.2 sign-in/CAPTCHA; build 19/21 saved session, codecs, gestures and Photos untested on target |

[Build 19 CI/artifacts](https://github.com/sandrscore/oldFunny-iOS/actions/runs/39526685353). Downloaded reports and per-test logs were
checked. Profile and search screenshots were reviewed. Full scope includes
remaining comment state/depth/bulk handling, mention panel physics, profile
options/indexing, feeds/reads, Explore/Activity/preferences, Chats/groups and
Studio/publishing. APNs/alternate OAuth require valid iOS client setup.

Authentication algorithms, Android sources and the same 16 reviewed bitmap
assets are preserved. Public exports exclude credentials, personal sessions,
original binaries and generated test media. No live social action was performed.
