> Candidate16 compiled with42 Mac core tests and6 packaging checks passing;
> 12/13 UIKit tests passed; the remaining repub-toggle assertion contradicted Android
> semantics (author predicate is suspended). Build17 corrects it to18 direct matches. Independently inspected IPA SHA256:
> `d4166bafd0f8a94c79edca890fcf50c4512218d6f697188534ffbc22389de8e5`.
> It contains custom video/seek controls and native profile/grid/featured/filter/
> subscriber/pin/subscribe source. Newer tag-editor source is awaiting the next
> candidate; its12 portable profile tests pass. Build11 below remains the fully
> verified offline checkpoint until the new UIKit suite passes.
>
> Five bounded anonymous GETs verified current public profile/timeline/featured/
> tag-suggestion schemas, with no credentials or social/read writes. No new
> target-phone validation has been performed.

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
