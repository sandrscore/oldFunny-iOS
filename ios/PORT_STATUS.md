# Native iOS port status

Target: iPhone 16 / user-reported iOS 27.0.1. Bundle: `mobi.oldfunny.ios`.
**Full Android behavioral parity is incomplete.** See [ANDROID_PARITY.md](ANDROID_PARITY.md).

| Evidence | Current state |
| --- | --- |
| Verified source | 0.3.0/build 25, `a05a335c8ed9fe0eb103f75bace763180e06a165` |
| Mac contracts | 63 Swift tests and six Python packaging/test-verification checks passed |
| Actual UIKit | All 20 offline cases executed and passed, zero failures |
| Comment deletion | Partial main-root bulk, reply placeholders, root-delete close/cascade and uncertain-write read fences passed |
| Mentions | Suggestions/paging, links, exact forms, single/rapid edits and identity boundaries passed |
| Media/profile | Prior decoded video/GIF, retained panels/drafts, search/tags/pins/subscription cases passed again |
| IPA | Independently ARM64, cryptid=0, unsigned, fixture-free; SHA-256 `2466cca5f4c34aaa9fd22d84ad12be6eb5a896190e15a49971c297cd0fce8b43` |
| Candidate 27 | Dedicated deleted nonroot reply row with native caption; build26 compiled 67 Mac core/six Python and ran22 UIKit:21passed/1deleted-dot accessibility assertion failed |
| Server | Prior bounded anonymous profile/feed/schema reads; no live social writes used for validation |
| Phone | Earlier 0.1.2 password/CAPTCHA confirmed by user; current-build saved session, codecs, gestures and Photos untested on target |

[Build 25 CI/artifacts](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40010014066).
Downloaded reports/logs were checked; actual comments/mention screens reviewed.
Build 24 had 18/20 cases passing and timed out collecting results. Build 25 fixes
disabled custom-control accessibility and verifies both individual and rapid
mention edits; its complete result bundle and all-green report are retained.

Candidate 26 excludes the separate inbound attachment/public-picture prototype.
Remaining scope includes complete comment state/attachment/mention-panel physics,
profile options/indexing, feeds/reads, Explore/Activity/preferences, Chats/groups
and Studio. APNs and alternate OAuth need valid iOS client setup. Authentication
algorithms, Android sources and the same 16 reviewed bitmaps are preserved; public
exports/Release IPAs contain no personal sessions, credentials or original apps.

Build26's two new role/navigation/depth cases passed, but it is not a fully green
checkpoint. Candidate27 follows the actual Android deleted-row adapter/layout,
removes live child controls structurally and preserves root context/count paths.
All22 cases remain mandatory. Source repair is pending Mac/UIKit verification.
