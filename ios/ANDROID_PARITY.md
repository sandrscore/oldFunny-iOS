# Android → iOS behavioral parity

The reference is the project's current **oldFunny Android 4.6.7 OptionalGoogle01**
(with the SubscriptionsReads04 behavior), not a generic iFunny screen list or an
assumed equivalence with iOS 4.6.8. The Android implementation remains unchanged.
**Full parity is not complete.** This document is a contract and gap ledger;
source implementation is separate from simulator, server and phone validation.

## Evidence and scope

Local static inventory: `tools/audit_android_ios_parity.py --decoded
analysis/optional-google-build-01 --output .ios-work/ios-port/parity/android-inventory.json`.
It indexes 2,577 app/helper classes, 188 view bindings, 248 interaction entry
points and 120 Retrofit methods, plus 99 readable helper source files.
The JSON contains source paths, hashes, bound field names, event methods and
public endpoint shapes. No app execution, account data or credentials are used.
This structural index does **not** mean every implementation branch has already
been manually reviewed. Original bytecode and the generated index stay local.

Android-relative paths below are evidence in the original workspace; they are
not bundled in this public native repository. Native smali paths are relative
to `analysis/optional-google-build-01/smali_classes2/mobi/ifunny/` unless noted.
Readable extensions live in `android-src/revival/`. Existing behavior docs live
in the original workspace's `docs/`. Cancelled Shuffle/archive and withdrawn
account-linking experiments are excluded from the target, even if old source
files remain on disk.

Status: **source** means implemented but still needs the stated checks;
**partial** means a substantive mismatch remains; **missing** means no native
implementation. User confirmation from an earlier build is identified explicitly.
Never infer device/server parity from a unit test or a screenshot.

## Viewer interaction contract (manually traced)

`gallery/view/GalleryItemFrameLayout$a.onScroll/onFling` establishes a vertical
first direction, a matching ending fling direction, >1500 physical px/s, and
checks whether a descendant can consume that direction.
`gallery/GalleryFragment.a(F)/b(F)` plus `$9`'s switch table and
`gallery/fragment/f.o/p/q/r` establish the three retained panels:

| From | Gesture | To | Required state |
| --- | --- | --- | --- |
| Media | Up | Comments | Same post and page, retained thread/draft |
| Comments | Down | Media | At a scroll boundary or header; retained post/zoom |
| Media | Down | Information | Same post |
| Information | Up | Media | Retained media |
| Comments | Up | Scroll | Do not skip to another panel |
| Information | Down | Scroll | Do not skip to another panel |
| Any panel | Horizontal | Neighboring post | Keep ordinary pager behavior |
| Zoomed/scrollable child | Applicable movement | Child pan/scroll | Do not steal a pinch or scrolling gesture |
| Editing | First outside tap | Dismiss keyboard | Preserve draft; do not activate underlying row |

Android transitions animate vertically after a fling rather than mapping every
finger movement to an interactive sheet. The iOS port uses the same arrangement
and normalizes the physical velocity threshold to the display's point scale.
`ViewerInteraction.swift` tests the transition table and rejection rules;
`PostController.swift` arbitrates actual UIKit gestures, retains children and
coordinates their lifecycle. A bounded neighboring-page cache retains nearby
post panels. Process-death restoration and every gesture edge case remain checks.

## Screen and behavior ledger

| Area / control | Required Android behavior and evidence | Native status / acceptance needed |
| --- | --- | --- |
| Sidebar destinations | Featured, Collective, Subscriptions, Explore, Profile, Chats, Activity, Studio, preferences; `main/menu`, `ChatsActivity`, `NewCaptionStudio` | Partial: Featured/Collective/Subs/Profile/Account, plus local candidate31 Explore. Other destinations need real implementations. |
| Drawer gestures | Open/close gestures, scrim, selected row, retained section; `main/IFunnyMenuActivity` | Partial: menu tap, shade and left-swipe close; edge-open and navigation restoration pending |
| Sidebar counts | Real Featured/Subs/Chats counters, no invented badges; `FeaturedFeed`, `SubscriptionsReads`, `ChatsBadge` | Candidate29 Subs only, unknown remains absent; Featured/Chats missing |
| Mark as viewed | Long-hold Subscriptions only; clear on confirmed success; `SidebarViewed` | Build30 offline UIKit verifies cancel, failed/confirmed clear, disabled pending choice and no duplicate. Phone and exact notice styling remain. |
| Featured refresh | Fresh head on persisted-cache entry, retained recent saved instance, no countdown/shuffle; `FeaturedFeed` | Partial: paging/refresh; stale cache policy pending |
| Featured reads | Foreground selected post only, per-account ledger, retry and skip viewed; `FeaturedReads` | Build30 offline UIKit verifies delayed render, drawer/comments/prefetch exclusion and settled timed reads; durable queues/filtering and scoped refresh have core coverage. Phone/lifecycle and partial-failure scheduling remain. |
| Subscription reads | Immediate settled selection, local unread credit, server reconciliation, durable queues; `SubscriptionsReads` | Build30 offline UIKit verifies immediate loading credit, stale counter and explicit-clear lifecycle; core tests cover persistence/account fences. Process/device coverage remains. |
| Collective | POST form `limit/next` to `/feeds/collective`; `Retrofit$RestInterface.getCollective` in primary smali | Source added; current server and device reads pending |
| Horizontal viewer | Retain index, edge pagination, page ordering and return position; `gallery/GalleryFragment` | Source, needs new phone regression |
| Comments entry | Up gesture and comment-button tap share retained panel; native trace above | Build 19 offline UIKit verifies up gesture and comment button share one retained panel; target-phone and remaining scroll-boundary cases pending. |
| Comments exit | Down at boundary, header Back; preserve post/zoom/draft | Build 19 offline UIKit verifies slow-drag rejection, fast downward return and Back with retained draft; phone and additional boundaries pending. |
| Information entry/exit | Down from media, up to return; retained child | Build 19 offline UIKit verifies down/up retained panel flow; full information actions and phone checks remain. |
| Information actions | Original author/republisher, date, views/smiles/repubs, user lists, tags/edit tags; `IFunnyWorkInfoFragment` | Partial: author routes and details; user-list/tag navigation/editing missing |
| Image fit | Native fit/centering, tall images and title/body alignment; `ContentBehavior`, `ModernPostText` | Partial: width/fit/scroll/pinch; full-resolution tall-image fidelity pending |
| Pinch/pan bounds | Image-style scale/pan with pager handoff at bounds; `ContentBehavior` | Partial: still-image zoom, no full edge handoff parity |
| Double tap | Native smile toggle; `GalleryFragment.b(View)` | Source added; no live reaction used during checks |
| Triple tap | Content a$3.c(MotionEvent) → GalleryFragment.c(View); resumed, not-abused, signed-in and r() eligibility | Build 19 offline UIKit verifies Collective eligibility and deferred triple classification without an earlier smile. Tag destination and BR signed-out double-tap exception remain gaps. |
| Smile/unsmile | Toggle mutually exclusive state, counts and signed-out route; original Retrofit methods | Source; request tests, live/device checks pending |
| Video/GIF zoom | Same transformed content as images; `VideoControls` and native behavior | Build 19 offline UIKit verifies shared video transform, mute during zoom and retained pause across page/panel return. Full pan-edge handoff, format and device cases remain partial. |
| Tap playback | Pause/resume only in video; margins hide chrome; paused triangle scales with video | Build 19 actual-player fixture verifies confirmed tap pause/resume and retained manual pause. Transformed surface/indicator and margin chrome are in source; all edge geometry and phone cases remain checks. |
| Scrubber | Only >10s, transparent 24dp hit area, elapsed/total during drag, coalesced accurate seek, retained play state; `VideoControls` | Build 19 actual sparse-keyframe fixture verifies decoded-frame seeking, retained manual pause and playback restart. Core queue tests cover coalescing/inactive completions; exhaustive lifecycle/codec/device cases remain. |
| Mute | Hide while pinching/zoomed, retain audio state; `VideoControls` | Build 19 offline UIKit verifies mute toggle, zoom hiding, return-to-fit restoration and restart when enabling sound during playback. App-scoped default-off/10-minute reset is in source; phone/audio-session cases pending. |
| GIF rendering | Timing/loop/dimensions, MP4-backed GIF support; `VideoCompatibility` | Build 19 offline UIKit verifies 82-frame decoded RGB, uneven 7580ms timing, loop and retained inactive phase. ImageIO actor uses a 3-frame LRU, 30MiB/10000-frame/2Mpx/2048-dimension bounds. Full-resolution/disposal/transparency/malformed-format cases remain partial. |
| Post hold menu | Share/Save/Chat/Pin/More with ownership and format eligibility; gallery menu patches | Partial: link/copy/share/Photos/repub and own-profile Pin context implemented; pin readback/grid badge passes offline UIKit in build 19. Chat and other menu actions remain missing. |
| Republish | POST `/content/{cid}/republished?from=...`, DELETE to remove; original Retrofit methods | Source added, explicit confirmation and no replay; live checks pending |
| Image save | Save original supported media to gallery; native options | Source added for Photos; actual permission/format/device checks pending |
| GIF save | Original GIF or MP4→animated GIF, frames/timing preserved; `GifSaving` | Partial: original GIF save; MP4 GIF currently saved as video, conversion missing |
| Video save | Original MP4 with audio; `VideoSaving` | Source added; file fidelity/Photos device test pending |
| Post sharing | Public links, internal post navigation, platform share targets | Partial: iOS share sheet and copy link; in-app inbound link routing missing |
| Comment layout | Blue author, round avatar, date, proportional preview, replies/smile counts; native CommentViews/PictureComments | Build28 offline UIKit verifies role menus/separate reply counts, depth29/30 and capped dots, distinct deleted-reply rows without live controls, and actual inbound card rendering/crops. Exact hidden/top/recent-count, typography and broader lifecycle states remain gaps. |
| Thread paging | Cursor continuation, dedupe, retry without losing loaded rows | Source, endpoint/server pagination checks pending |
| Replies | Root parent context, recipient chip, mentions, retained thread; `AnswersFragment` | Build28 repeats root/recipient/draft/mention assertions and corrected confirmed root-deletion close with the complete root+replies count delta. Reply-only deletion keeps native placeholders/root context. Broader process/lifecycle cases remain. |
| Comment options | Own comment Reply/Delete; other on own original post Reply/Report/Remove; other/guest Reply/Profile/Report. Answers removes Reply at depth30; CommentsFragment/AnswersFragment | Build28 repeats all role-ordered tap/nonowner-hold dialogs, original-owner selection, guest/profile routes, separate reply-count navigation, authenticated composer focus and depth29/30 boundaries. Phone and remaining state edges unverified. |
| Comment selection | Pencil/hold multi-selection, permitted rows, immediate partial-success counts; `CommentDelete` | Build25 offline UIKit verifies original-author pencil/attachment hold, selection toggles, root exclusion, partial results, reply placeholders and count deltas. Physical disabled tap cannot retry; failed read stays locked, successful read unlocks. Server/phone cases remain. |
| Comment delete ack | Empty successful bulk results mean success only with explicit outer status | Build25: explicit successful empty array/positional 2xx contracts, failed/missing rows retained, unknown envelopes rejected, POST method=DELETE without replay. Five bulk/owner contracts and all20 UIKit cases passed; live writes/phone validation remain absent. |
| Incoming attachment cards | Max4, fallback/unavailable/withheld/abused states, exact crop and full-post navigation; `AttachmentSpec`, `PictureComments`, `PreviewCrop`, `PublicPictures` | Build28 offline UIKit verifies decoded RGB crop, cap/badges/hold, failed/deleted/withheld/blocked/linked states, exact API404 website recovery and draft/Back. Three anonymous GETs separately verified server routes. HTTP-only previews, stream-time size bounds, browser/notice and format/device edges remain. |
| Attachment plus | Full-screen 3-column own posts/reposts, cursor paging, retained draft on Back; `CommentPostFeed`, `NativePostGrid` | Build 19 offline UIKit verifies 3-column own-post picker, Back and draft retention. Real account pagination and phone checks pending. |
| Attachment choice | One thumbnail+X, replace/remove independently of text | Build 19 offline UIKit verifies choice, visible X, replacement/picker Back/refresh/removal with text retention. Phone checks pending. |
| Attachment send | `text` + one `content` ID to comment/reply endpoint; no separate upload | Source now connected; no live comments submitted by agent |
| Draft success/failure | Clear exact submitted revision only; retain newer edits/uncertain writes | Source and tests; lifecycle/process restoration pending |
| Send retries | Never replay an uncertain social write; `comment-send-01`, `CommentComposer` | Existing single-attempt API retained; refresh-only GET retry preserved |
| Mentions | Unicode offsets, exact IDs, suggestions/recent users/avatars, colors and notification fields; `CommentMentions`, `MentionComments` | Build 21 verifies default/typed paged choice, selected identities and UTF-16 forms, blue incoming links/profile taps, unconfirmed draft retention and edit invalidation. Panel inertia/fling handoff, process restoration, server notifications and phone validation remain gaps. |
| Keyboard dismissal | First outside tap dismisses and preserves text/attachment/recipient, next tap normal | Build 21 offline UIKit verifies text/attachment/recipient and mention-link outside-tap dismissal followed by normal navigation. Remaining gesture/process/phone cases pending. |
| User profile | Information header, posts/reposts grid, subscriptions/subscribers, actions; profile fragments | Build 19 offline UIKit verifies header/grid/info, subscriber list and confirmed subscribe readback using fixtures. Bounded anonymous schema reads succeeded; full profile actions and phone checks remain. |
| Own profile | Account identity, editing, cover/avatar, counters, settings | Partial: account identity, posts/info/featured/counters and own pin context implemented; editing, cover/avatar uploads and full settings still missing. |
| Featured profile count | Dedicated `/timelines/users/{uid}/featured`, 3-column grid; `ProfileFeatured` | Dedicated featured endpoint and owner/flag filtering. Build 19 offline UIKit verifies separate 3-column featured grid/gallery/Back; earlier anonymous server read succeeded. Device/server-account edges pending. |
| Grid viewer return | Swipe full snapshot, continue same endpoint, Back to retained grid | Build 19 offline UIKit verifies shared snapshot paging and Back preserves grid scroll; same-source pagination is in source. Large histories, process restoration and phone cases pending. |
| Profile pinning | Own profile only, max3, server readback, pinned menu/grid mark; `ProfilePins` | Build 19 offline UIKit verifies own pin acknowledgment/readback and grid badge. Max3/account/source contracts pass; live user-controlled writes and phone cases pending. |
| Advanced profile search | Combined media, all tags (AND), original author, repub toggle; `ProfileSearch*` | Build 19 offline UIKit verifies combined media/AND tags/original author/repub toggle, suspended author restoration, actual result counts/last-result reachability, tag editing/suggestions/recents and Clear filters. Large-history index/device cases remain partial. |
| Search state | Progressive bounded history scan, cancel stale filters, retain results/scroll, clear on exit | Partial: cancellable off-main rescans, query/account/read generations, sparse-page continuation, retained loaded results/cursor and failure retry. Full raw post history still in memory; disk-backed large-history index remains required. |
| User/tag Explore | Real user/tag search, recent users/tags, tag galleries | Candidate31 source: actual search and tag routes, mixed10 recents, type-only clear, retained grid/viewer and pagination. Core/server read evidence exists; UIKit/phone pending. |
| Subscribe/block | Confirmed subscribe/unsubscribe/block state with ownership rules | Build28 repeats offline UIKit confirmed subscribe/unsubscribe readback and uncertain-state reconciliation from build19. Block UI/API and real user-controlled/device validation remain gaps. |
| Profile social links | Public X/Facebook links as implemented; `ProfileSocialLinks` | Missing; cancelled account-linking experiments excluded |
| Activity | Real events, unread state, mentions/chat filters and server settings | Missing |
| Chats inbox | Real cached inbox/search, unread badge, long-hold/pencil selection; `ChatsActivity`, `ChatsRepository` | Missing |
| Chats connection | TLS WAMP/WebSocket, selected account fencing, resume reads, bounded frames; `ChatsWire`, `ChatsSocket` | Missing |
| Chat history | Long.MAX_VALUE initial cursor, older paging, unread positioning, horizontal time reveal | Missing |
| Chat sending | Durable outbox before send, no replay, local/server ID reconciliation, newest-draft protection | Missing |
| Chat receipts | Publication acceptance ≠ delivery/read; latest-only receipt, authoritative events | Missing |
| Chat attachments | Imported photo/video, independent media cache/crop, internal post cards and player | Missing |
| Chat share | Post hold→Chat multi-recipient Send Meme, optional note, per-target results; `ChatsShare` | Missing |
| Chats info | Eligibility-gated profile Chat button, DM information/mute; `ChatsProfile` | Missing |
| Chat bulk actions | Confirmed mute/unmute/hide/leave/delete; durable uncertain-command fences | Missing |
| Groups | Private/open, discovery/search, invite/member/admin rules, service notices; `ChatsData`, `ChatsActivity` | Missing |
| Notifications | Foreground banner, swipe/tap/timeouts; mention/chat preferences; real background push | Missing; iOS APNs needs independent entitlements/server registration, not Android FCM code |
| Privacy | Who can chat: All/Friends/Nobody; save with readback; `ChatsPrivacy` | Missing |
| Studio menu | Existing Meme/comics/caption/GIF tools and repaired assets; `StudioAssets` | Missing |
| New Caption | Text/image/GIF/video, title/body/caption placement and black/white panels; `NewCaptionStudio` | Missing |
| Crop/trim/audio | Source-space crop, 100ms–90s trim, accurate paused frames, mute; NewCaption helpers | Missing |
| Review/tags | Native review, optional tags; no location/scheduling/audience | Missing |
| Publishing | Multipart contenthub contract, immutable snapshot, one upload, task polling and native progress | Missing |
| Studio drafts | Independent durable drafts, recover uncertain upload, never overwrite newer draft | Missing |
| Email/password CAPTCHA | Bootstrap/token/account, manual WKWebView, trusted callback and cancellation | User confirmed 0.1.2; flow preserved, new version needs regression |
| Session storage | Device-only Keychain, shared refresh, account fencing; no token in media/logs | Existing source/tests plus stale-UI write-session rejection; sign-in/refresh/authenticated-call algorithms unchanged. Relaunch/new build phone checks pending |
| Alternate sign-in | Preserve supported native Google/Apple/web OAuth functionality | Missing; requires valid iOS client setup, not Android identifiers |
| Preferences | Existing Android settings, notification filters, privacy, account controls and cache policy | Partial: local session removal only |
| Offline/lifecycle | Navigation/cache restoration, draft survival, memory/background cleanup | Partial; foreground/media pause and account isolation exist, full persistence pending |
| Accessibility | Equivalent labels, hit areas, readable dynamic text and non-gesture alternatives | Partial; buttons/custom actions exist, full screen audit pending |

## Validation gates

1. Portable contract tests: panel table, physical fling threshold, axis/reversal,
   scroll/edit/pinch rejection, draft revisions, exact Android HTTP methods/fields,
   authentication/account fences and no write replay.
2. Actual UIKit automation with **offline fixtures only**: swipe entry/return,
   button parity, draft retention, information return, horizontal paging and zoom.
3. Visually inspect actual simulator screens; fixture builds stay out of Release.
4. Sign/update the unsigned ARM64 IPA using Zeus; check the target phone, saved
   sign-in, gestures and media. Simulator iOS 18.5 does not prove iOS 27.0.1.
5. Real server reads and explicit user-controlled writes per feature. Do not
   create, react to, delete or send real content simply to claim parity.

Apple references for native implementation: [gesture admission](https://developer.apple.com/documentation/uikit/uigesturerecognizerdelegate/gesturerecognizershouldbegin(_:)),
[UI automation](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication),
[Photos add-only authorization](https://developer.apple.com/documentation/photos/phphotolibrary/requestauthorization(for:handler:)).

## Verified checkpoint (2026-10-20)

**0.3.0 build 10**, source `5cca16ac45ac9c208269c6737ef1e36ef582b2a6`,
[Mac CI](https://github.com/sandrscore/oldFunny-iOS/actions/runs/39499100759).
26 Mac Swift contract tests, 6 Python checks and **all 6 actual UIKit tests pass**
with zero failures. The downloaded preview.json and ui-tests.log were independently
checked; each expected test executed. Actual screenshots of feed/sidebar/comments/
information were reviewed on iPhone 16 / iOS 18.5 with offline fixtures.

UIKit establishes the tested fixture flows: up into comments; slow downward drag
rejected; above-threshold downward fling back to media; information down/up;
keyboard outside tap without underlying navigation; retained drafts through panel
and reply Back; attachment choice/picker Back/refresh/removal; horizontal pages,
zoom priority and resolved media geometry; unconfirmed inline reaction retaining
the draft. These tests do not cover every scroll boundary, long thread, format,
permission, server action, account or process-lifecycle edge case.

Downloaded IPA independently verifies as build 10, ARM64, cryptid=0, unsigned,
with no fixture marker or UI-test bundle. SHA-256:
`fe571fee9fe8403d3990acbff354706a9cd3c294299ab1f300c915ffdcb6c334`.
No current build has been tested on the target iPhone / user-reported iOS 27.0.1.
No live social write was used. The existing password/CAPTCHA confirmation remains
from the user's 0.1.2 installation; saved-session/new-build regression is pending.

The nominal 750pt/s coordinate drag in build 9 actually ended at 412pt/s = 1236
physical px/s. Its rejection was correct. Build 10 tests slow rejection and an
above-threshold synthetic fling; the Android >1500px/s threshold is unchanged.
Viewport-driven sizing fixes the previously measured 300pt media placeholder.
Previous failing candidates and their logs/IPAs are preserved locally.

Known remaining issues include unsmile context eligibility, full deleted/hidden
states, recent-count/depth rules, mentions, bulk deletion and process persistence.
Custom video/GIF controls, profiles/search/pins, reads, Explore/Activity/settings,
Chats/groups and Studio remain required. Authentication files and signIn/refresh/
call algorithms are unchanged; social endpoint wrappers add captured-session
checks. Android/protected hashes match baseline. **Full parity is not complete.**

### Verified follow-up: build 11

Read generations are separate from account generations, so a successful mutation
refresh no longer invalidates an open picker or another draft edit. Reads pause
while a write is unresolved; requested/account refresh resumes when it finishes.
Confirmed reply insert/delete deltas propagate to post totals, with subsequent
reply metadata reconciliation avoiding a second delta. Root deletion retains a
deleted placeholder and leaves reply count unchanged; retained child roots update
when their parent is deleted. Full hidden/abused/top/depth rules remain gaps.
The default Refresh symbol is recreated after view loading to address the missing
initial icon; its visibility was confirmed from the downloaded simulator screenshot.

An explicit per-launch offline transport mode supplies reply/delete acknowledgments
for a new UI test checking post totals, refresh, deleted root context and retained
replies. It has no network transport and is absent from Release. Existing rejected
write tests remain. [Mac CI](https://github.com/sandrscore/oldFunny-iOS/actions/runs/39502078271)
for source `9dd9ac22bfc72b1bd0b329d4f8236bd91e2b2cda` passed 27 Swift tests,
6 Python checks and all 7 UIKit tests with zero failures. Downloaded reports and
logs were checked. Independently inspected build 11 is ARM64, cryptid=0, unsigned,
with fixtures absent. IPA SHA-256:
`3c211f82d370d522f2f55f8762bb700ccfb12c81dfc4ef543b85b5dd68b5912c`.
No real social action or new target-phone check was performed.

### Profile and media candidates (verification in progress)

Build16 compiled on Mac with42 core tests and6 packaging checks passing. Its
unsigned ARM64 IPA was independently inspected, cryptid0 and fixture-free:
SHA256 `d4166bafd0f8a94c79edca890fcf50c4512218d6f697188534ffbc22389de8e5`.
UIKit13 tests executed,12passed/1failed: an incorrect test expected no results
when repubs off suspends the author predicate. Build17 verifies18directmatches.
Do not use this as a verified
replacement for build11. Builds13/14 compiled but each failed2 of9 UIKit tests;
video decoded-frame seek/pause checks passed before the failed reverse-pinch
assertion. Build16 targets the actual video viewport and repairs feed reset.

A bounded anonymous profile probe verified current public profile, timeline,
featured and tag-suggestion schemas (5 GETs, no personal session, no writes).
It decoded14 first-page timeline entries and10 matching-owner/featured entries.
This is server read evidence, not verification of logged-in actions or iOS27.
Reproduce with `swift run --package-path ios/OldFunnyCore OldFunnyProbe
--anonymous-profile-read-only`; counts vary with the public feed.

Android `ProfileSearchTagsActivity` reuses `TagsEditActivity`: tags.xml gives5
tags,2–100 UTF16 chars; removable chips preserve pending text, Back commits it,
recent history holds10, and suggestions use GET `/tags/suggested?q=...` with
`data.tags.items[].tag`. The native tag-editor source follows this contract;
its new UI test and two portable contracts require the next candidate build.

### Candidate17 results and candidate18 GIF work

Build17 source `c8fd6925d1dc34e3206aa190b38b95b02c8c5ed2` compiled with44Mac
core/6Python checks passing. All14UIKit tests executed;13passed. New tag editor
suggestions/limit/chip removal/pending Back/recent clearing passed; retained
video/seek/pixels/zoom/mute/paging, Collective triple classifier, profiles/featured/
grid return/pin/subscribe passed. One combined-search assertion still failed
expecting18accessiblecells. Candidate18 exposes actual collection item count,
checks specific direct/source-backed IDs and scroll reachability, and logs both
counts to resolve viewport accessibility versus source results. Full UI gate
remains red until all expected tests pass; do not certify search parity early.

Candidate18 source replaces main-post GIF arrays with ImageIO actor/3-frameLRU,
per-frame cumulative timing and CADisplayLink, retained active phase and lifecycle
fences. Android video/c$h uses readFrameLooped and max20ms timestamp-delta delay;
the new schedule follows that floor and loops. Static avatar/grid/comment previews
match Android PictureComments Bitmap decoding and cannot poison main GIF cache.
Limits:30MiBcompressed,10000frames,2Mpx/frame,2048longestdimension. Full original
resolution and special transparent/disposal/malformed-GIF edges remain checks.
A generated82-frame Debug-only GIF test checks actual decoded RGB, uneven-delay
phase, last frame81, looping and paused panel return. All48 portable tests pass,
but native GIF compile/UI test has not yet run. Source files and fixtures remain
separate from the independently inspected build17IPA. No Android changes or live
social writes were made.

### Candidate18 results and focused19fix

Build18 compiled with48Mac/6Python checks,15UIKit executed14pass/1GIFloadfailure.
All profile/search/tag/pin/subscribe, retained video and comments tests passed.
The actual trace is `data source=18 posts, accessibility cells=15`: prior failing
search assertions counted viewport cells. New checks verify actual item counts,
source/direct IDs, first/last reachability and query scroll reset. Wrapped tags
remain tappable; selected-author retention/disable/restore and Clear filters pass.

The GIF test failed before the animation view appeared. Candidate19 falls back
to first-frame pixel dimensions when ImageIO global properties lack them and
records generated fixture global/frame metadata. Native GIF runtime remains
unverified until its complete pixel/timing/loop/pause test passes. 19 isolates
this fix; unfinished mention prototypes in the original workspace are excluded.
Build18IPA independently verified ARM64/cryptid0/no fixtures:
`b15f9a021c3557f073f9a0b2ef6c0c3e614017ece8096b2e3483f49b0657337a`.
No target-phone/live-social check and no Android changes.

### Verified checkpoint 19 and candidate 20

Build 19 source `86394bb2f59dd7cd16e7593ee2ddcf1dea80b906`,
[Mac CI](https://github.com/sandrscore/oldFunny-iOS/actions/runs/39526685353),
passed 48 Mac Swift, 6 Python and all 15 UIKit tests with zero failures. The
ImageIO fixture confirms global dimensions are zero and first-frame dimensions
320x320; fallback resolves the load failure. Actual decoded GIF frame 81, uneven
7580ms loop, green/blue pixels and inactive-panel phase retention now pass.
Video, profile/search/tag/pin/subscribe and previous comment tests also pass.
The downloaded IPA independently verifies ARM64/cryptid0/fixture exclusion:
`86fe2202410f483ee52fe45791d019eedc672aa4dff7be019967b775b0af84c5`.
Reports, exact source ZIP and local IPA are retained. No new phone/live-write check.

Build 20 incorporates the inherited local mention contracts and native UI.
`MentionDocument` follows Android exact UTF-16 identities, boundary edits, token
rules, ASCII trim and inclusive send offsets. Selected users replace @query;
plain typed names never gain an ID. Draft revisions retain identity with text,
attachment and reply recipient. Incoming blue/bold glyph links open the actual ID;
first outside keyboard tap is dismissal only. Suggestions use authenticated
9-default/20-paged endpoints, 250ms typed debounce, query/account fences and dedupe.
A resizable overlay remains above the recipient/composer footer. Full Android
inertia/fling handoff is still missing. Exact server notification behavior and
account/process edge cases require further validation.

58 portable Swift tests and 6 packaging checks pass locally. Added offline UIKit
tests verify actual choice/pagination, link navigation, rejected root form with
retained draft/attachment, identity removal after an interior edit, and accepted
selected-recipient reply with exact mention/attachment fields. These native/UI
additions are pending Mac verification; no real comment/notification is sent.

### Build 20 results and focused candidate 21

Source `3d0f2d0238cda5bf9201ee7ee1a52f7cb5c05876`, run 39537778581,
compiled with 58 Mac core and 6 Python checks passing. All 17 UIKit tests ran:
15 passed, 2 mention tests failed on static-text queries. The actual accessibility
hierarchy exposes interactive mention bodies as buttons. It contains the accepted
`Hello ReaderTwo` reply, and the incoming blue/bold link is visible in the reviewed
screenshot. Link navigation, uncertain receipt and subsequent assertions still
require execution; an earlier lookup failure does not verify them.
Downloaded build 20 IPA independently verifies ARM64/cryptid0/fixture exclusion,
SHA-256 `97bf3f9efd8506509e23529464d4de2a45b79a6ae225f9863b5ddc99f00a9b44`.

Candidate 21 changes only the two queries to locate the known body identifiers
across accessibility types and still asserts the exact reply text. App/core source
matches build 20. The new bulk selection prototype in the original workspace is
excluded from this focused candidate. All 17 tests remain mandatory; target phone,
server notifications and live social writes remain untested.

### Verified checkpoint 21 and bulk candidate 22

Source `4c990a36420f8f9e2d5dfbb6c55ee603cdace6e1`,
[Mac CI](https://github.com/sandrscore/oldFunny-iOS/actions/runs/39539381754),
passed 58 Mac core, 6 Python and all 17 actual UIKit tests with zero failures.
Both mention tests completed every remaining assertion: default/typed paged
choice and dedupe, exact identity, attachment and Back retention, first outside
keyboard tap, actual mentioned profile, uncertain root form/draft, interior edit
removing identity, and accepted selected-recipient reply with exact fields.
Reports and logs were downloaded/checked; the incoming link screenshot reviewed.
IPA independently verifies ARM64/cryptid0/fixture exclusion, SHA-256:
`e6f1731005e4f8660bebc288f1c11b3e15f7ff6c21c14b915b51f79b0c661aff`.
No new phone or live social/notification validation was performed.

Candidate 22 ports Android selection deletion from CommentsFragment, its action
mode handler, CommentsFragmentImpl/AnswersFragment and revival.CommentDelete.
The request is POST /content/{postID}/comments?method=DELETE with ordered id CSV.
Explicit empty data.responses plus successful outer status acknowledges all
valid unique IDs. Otherwise only positional 2xx results apply; malformed/unknown
receipts never invent acceptance. Failed/missing rows remain selected. The main
root delta includes its replies; reply rows become deleted_self and preserve the
root/positions. Original source author owns the pencil/hold selection, and reply
root context is excluded. Unknown receipts block selection until a successful
replacement read; a failed refresh keeps the lock. Account generations and no
write replay remain enforced, with draft and attachment retained.

63 Linux core tests (including five bulk/owner contracts), six Python checks and
native syntax parsing pass. Three added actual UI tests cover partial root counts,
empty reply receipts, root exclusion, full attachment hold, uncertain write and
failed/successful read recovery. The 20-case Mac/UIKit run is pending. Ordinary
row tap/options and depth/state rules are explicitly still incomplete.

### Build 22 results and candidate 23: compilation plus root-deletion correction

Build 22 source `f73e27b4e190992d98ee4154812fd334d3f995f3`, run 39541214313,
compiled Release/Debug app with 63 Mac core/six Python checks passing. The UI test
target failed to compile on two XCUIElement.count uses, so **zero of 20 UI tests
executed**. The downloaded IPA independently verifies ARM64/cryptid0/no fixtures,
SHA `383e201c9d298708b9c6a88ed0ac7db9ae8014a54071928a248a0e4a22a49175`.
Candidate 23 counts the matching label query, preserving the exact two-row checks.

Further native tracing corrects a substantive earlier fixture assumption:
CommentsFragment$h calls a(Comment) on start, b(Comment) on success. In Answers,
a(root) shows progress (V is a progress dialog, not a close operation); b(root)
subtracts replies+1, sets deleted and calls AnswersActivity.a(root), which finishes
the reply screen. CommentsFragmentImpl's single-root deletion also subtracts its
replies before the common -1/removal. Successful root deletion therefore removes
the whole thread and returns to the main list. The old build-11/21 retained-root
success expectation was a fixture implementation check and did not match this
native contract. Pre-existing deleted-context rendering is a separate state case.

Candidate 23 applies the complete root delta, evicts its cached thread, detaches
obsolete child read/count callbacks and returns after confirmation dismissal.
The offline receipt now cascades root/replies and the existing test verifies
6 total -> delete root+3 replies -> 2 total, automatic return, Refresh and footer
without double count. Reply-only deletion retains placeholders as before.
The frozen candidate includes these native/fixture changes and test compilation
fixes; the separate local menu/depth/dot/page40 policy prototype is excluded.
All 20 actual UI tests remain required; Mac/UI execution is pending. No live
social write, new phone test or complete-parity claim is made.

### Candidate 24: retain the read-side root helper

Build 23 source `0e6a0cb8abade38ef60648b8e148ab580962f0d1`, run 39542985465,
passed 63 Mac core/six packaging checks, then app compilation failed because
read refresh still called the removed markRootDeleted helper. No IPA or UI test
execution resulted. Candidate 24 restores the read-side helper for pre-existing
deleted root context; confirmed deletion continues through the separate complete
thread-removal/return path. All 20 UI cases remain required. The local menu/depth/
page40 prototype stays excluded from this focused build.

### Build 24 results and focused candidate 25

Source `3f7a90f59cde67023d54fc5c8853f73cc74fe232`, run 39543370601,
compiled with 63 Mac core/six Python checks passing. All 20 UIKit cases executed:
18 passed, including partial root removal/counts, reply placeholders/root retention,
and confirmed single-root deletion returning with the complete thread delta.
The uncertain-selection case failed on accessibility isEnabled; the custom
UIControl already had its guard disabled but did not expose the notEnabled trait.
The mention test observed one of two rapid synthesized deletions. Later assertions
in these two cases remain unverified. No full-green claim follows from 18 passes.
Xcodebuild exceeded 600s after 503s of XCTest plus startup; the job was cancelled
and its result bundle was incomplete. Downloaded logs/artifact hashes were checked.
IPA independently verifies ARM64/cryptid0/no test fixtures, SHA-256
`4b81c390e5096ad45db9b86cfbfc1a2a9d89569bbe1b58338e49903e1f8e0001`.

Candidate 25 exposes the disabled trait and adds a physical no-retry tap check.
Mention styling skips identical attributed-string assignments; UI checks cover
trailing-space deletion retaining identity, interior deletion removing it, and
rapid consecutive deletes without recreating the old identity. Tests get 900s and
the free public Mac job 30 minutes to finalize reports; all 20 cases stay required.
The local options/depth/page40 work is excluded from this focused candidate.
Target-phone, live writes/notifications and full parity remain unverified.

### Verified checkpoint 25 and candidate 26

Source `a05a335c8ed9fe0eb103f75bace763180e06a165`,
[Mac CI](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40010014066),
passed 63 Mac Swift, six Python checks and all 20 actual UIKit cases with zero
failures. Reports and complete xcresult/logs were downloaded and artifact hashes
checked. Both previously failing flows completed all assertions: physical disabled
Delete cannot send another request, failed/successful read recovery preserves draft,
and individual/rapid mention edits retain/remove identity at the correct boundary.
Partial bulk results, reply placeholders and corrected root-delete close/counts
passed again. Comments and incoming-mention screenshots reviewed. IPA independent
ARM64/cryptid0/fixture exclusion, SHA-256
`2466cca5f4c34aaa9fd22d84ad12be6eb5a896190e15a49971c297cd0fce8b43`.
Protected169/Android137 hashes match. No new phone/live-social validation.

Candidate26 integrates traced role-ordered ordinary-tap/nonowner-hold options,
original-owner hold selection, separate reply-count read navigation, authenticated
Reply with root/nested composer focus, depth30 eligibility and depth-1 dots capped
10phone/15tablet. Actual avatar/date targets route to the author profile. Existing
UI tests now use actual Reply actions and stable reply-count identifiers; two new
cases cover role order/guest/profile routes, exact dot geometry, 29/30 boundary,
keyboard dismissal and preserved text/recipient. 67 portable contracts pass;
all22 UIKit cases remain mandatory and Mac/UI pending. The separate multi-card/
public-picture recovery work is excluded. Full state/attachment/render/lifecycle
and remaining screen ledger requirements are not implied complete.

### Build 26 results and focused candidate 27

Source `a4344cb4110e870f2814afa04fc764ec6a7cc893`,
[Mac CI](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40013017468),
passed 67 Mac core and six Python checks; all22 UIKit cases executed,21 passed.
Both new role-order/menu, direct author targets, guest reply navigation,
root/nested composer focus, capped ten-dot geometry, depth29/30 boundary and
draft-retention cases passed. The bulk-reply test failed on the absence of a
reachable depth-strip element after deletion. The assertion does not prove its
visible pixel state. Remaining assertions in that case await a passing execution.
IPA independently ARM64/cryptid0/fixture-free, SHA-256
`59df23594b0c52c2b8fa005c6801fd016e9e67e3bd9f0b1bab330e75ce89a6bc`.

Android comments/a.b(Comment) chooses root type1 before deletion type2; type2
inflates comment_deleted_item with centered 15dp padding, middle truncation and
caption 'Comment was eaten by a black hole'. It contains no live author, reactions
or depth strip. Candidate27 uses a separate cell for deleted nonroot replies and
keeps root context on its existing path. The original zero-dot assertion remains,
plus author/reaction absence, exact caption, refresh/draft/count checks. All22
cases are mandatory; Mac/UIpending. Inbound multi-card/public-picture changes
remain separate. No new phone or live social validation; full parity incomplete.

### Local candidate 28: inbound attachment and content navigation slice

Readable AttachmentSpec, PictureComments, PreviewCrop and PublicPictures/WebPostData
are the specification. Native cards preserve max4 entries, deleted/blocked/unavailable
states, ID-less previews, link-derived fallback, exact thumbnail priority, bounded
geometry and ARGB, badge taxonomy, first-comic-panel/centered-video source crops,
image-only rows and withheld placeholders. Abused/deleted rows suppress attachments
and mention links. Full post loading uses GET content/{id} and validates returned
identity. Only an API404 recovers a published non-abused matching picture from the
website JSON. No script executes; website requests carry no API authorization or
cookies. Session generations and cancellation fence late content responses. Parent
thread/draft remains underneath internal viewer Back. Original-owner moderation
now remains nil when source data omits the original author.

Thumbnail loading has an independent strict10MiB LRU, two workers and64 waiters,
8MiB compressed-file validation and power-of-two ImageIO sampling to1024. Fixtures
supply encoded PNG data to the actual decoder/queue/cache rather than returning a
ready-made bitmap. The 23rd UI case checks actual pixel crops, cap/badges, hold to
select, unavailable/failed/withheld/blocked/link-derived states, refresh replacement,
API404 recovery and draft/Back. All22 existing cases remain required. Local74Core,
six Python checks and native syntax pass; new native files have not Maccompiled.
These tests do not prove HTTP-only preview support, stream-time payload enforcement,
external browser behavior, all image/codec edges or Android toast presentation.

2026-10-26 anonymous read evidence:3 GETs total, no account/session/read ack/social
write. A known attachment resolved through API200 (1075x823), and a long picture
resolved API404->website200 (638x4719), matching each requested ID and full media.
This establishes the implemented server-read routes on that date; it does not
establish target-phone gestures, notifications or live action behavior. The public
build27 currently excludes this slice and remains under its own22-case UI gate.

### Verified checkpoint 27 and candidate28 verification

Source `f205168b98f5c886a26b0e758393b5137b8932e1`,
[Mac CI](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40404742369),
passed67 Mac core/six Python and all22 actual UIKit cases, zero failures. The
previous deleted-depth assertion and every subsequent refresh/draft/attachment/
count assertion passed. Root context is retained; deleted nonroot rows have exact
centered caption and no author/reaction/dot children. Actual XCTest screenshot
was extracted losslessly from its payloadRef and visually reviewed, plus comments.
Both role/menu/author/guest/navigation/focus/depth cases and previous media/profile/
mention/bulk cases passed again. Artifact hashes/logs/full result were checked.
IPA independently ARM64/cryptid0/fixture exclusion, SHA256
`67488a070a27fb8eb08348663dc281e097620861ba94fbe98334d2cab30798f6`.
All169 protected/137 Android-doc hashes match. No new phone/live social validation.

Candidate28 now goes to Mac with74 core and23 mandatory UIKit cases. The inbound
fixture additionally checks real card hold selection and a refresh replacing
withheld data with link-derived cards/blocked-creator state, preserving the draft.
The candidate's new files are not certified by27's green result. Remaining limits
above and the full screen ledger stay open; parity is not complete.

The recovery trigger is the actual HTTP404 status. A status404 JSON envelope on
HTTP200 does not invoke website recovery. The shared request loop returns its raw
HTTP result before parsing, retaining account fences/read-only refresh/no write
replay; content and ordinary callers check their captured epoch again.

### Verified checkpoint 28

Source `1fe0428699b6185792f721bac73aad03fc1e929b`, [Mac CI](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40407953474), passed74 Mac Swift, six Python and all23 actual UIKit cases with zero failures. Exact expected names, downloaded logs/preview.json and artifact hashes checked. Attachment screenshot reviewed; the new test completed all crop, selection, recovery/Back, unavailable/failed/withheld/blocked/link-derived and draft assertions. IPA independently ARM64/cryptid0/fixture-free, SHA256 `8af68fb23d0a56e28a86fbdbb7762ed000b651b07d1d437de8ed9c6dcdeedd15`. Protected169/Android-doc137 hashes match. No new target-phone or live social/read-ack validation. Attachment limits and remaining ledger stay open.

Local unpublished read work adds ReadTracking/ReadServices, durable private per-scope JSON, session-fenced serialized acknowledgements/counters/clear/feed filtering and15 tests (89 Linux total). Native visibility, scheduling and sidebar integration are in progress; build28 excludes all read changes.

### Build29 results and focused30 read correction

Source `98e048e8c8e6f5f8e77c6d256eede91e2e6b83a1`, [Mac CI](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40411120296), passed90 Mac Swift, six Python and all25 actual UIKit cases, zero failures. Exact names/logs/preview.json and archive digests checked; actual Featured selected-read and Subs confirmed-clear screenshots reviewed. IPA independently ARM64/cryptid0/fixture-free, SHA256 `479fc8f3123f3e31eaadf17d6a07c240a98cb785f37163ef957559eb1ce10b1d`. New UI checks completed rendered-delay/drawer/comments/prefetch exclusion and actual settled reads, loading Subs immediate credit/stale counter retention, cancelled/failed/confirmed explicit clear and navigation retention. No real read ACK/social write or target-phone test.

Separate regression tests reproduced two29 issues: an existing GET401->token refresh->GET200 was rejected by the new wrapper as sessionChanged, and failed Featured ACKs prevented Subs ACK/counters. Candidate30 permits one read retry only for a changed token in the same account key/epoch/signed status and returns the accepted context; account/sign-out changes still reject without retry. Queues now make independent progress under the same lock while failed IDs remain pending. Authentication algorithms and single-attempt social-write rules are unchanged.

30 also resets exposure synchronously on panel changes, avoids redundant fixture trace UI updates, and displays a disabled explicit clear choice while pending. The existing Subs native case now requires actual fake token refresh and checks pending choice/duplicate prevention; all25 cases remain. 93 Linux core tests, six packaging checks and native syntax pass;30 Mac/UI results pending. Other ledger gaps remain open.

### Verified checkpoint 30 and local Explore candidate

Source `b526db3d7745dcd68754edd49547eb4932d3279e`, [Mac CI](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40413896528), passed 93 Mac Swift, six Python and all25 actual UIKit cases. Exact logs/names/preview and artifact hashes checked; selected Featured and confirmed Subs screenshots reviewed. The expanded Subs case completed fake GET401/token refresh/GET200, pending disabled choice, duplicate prevention, failed and confirmed clear. IPA independently ARM64/cryptid0/fixture-free, SHA256 `2742eacbc8252e8daf8a575383e2dc7ed9d9f0dcff48780fcb917da77ef7bfab`. No current phone or real write/ACK validation. Full parity remains incomplete.

Local Explore source adds a sidebar destination, tag tiles and suggestions/user tabs, exact tag/channel routes, mixed10-item history with type-only profile-picker clearing, and a paged tag grid sharing its retained swipe viewer. 99 Linux core tests, six packaging checks and native syntax pass;26 UIKit cases await Mac. Three anonymous GETs confirmed Explore/suggestion/tag-feed data (13 tiles,10 suggestions,27 decoded posts with continuation), with no account, ACK or social write. Color/header/channel destinations, broader state restoration and target-phone behavior remain gaps.

### Build31 results and focused32 compile correction

Build31 source `5862dbae71f7739f178bb90b24a0c4c4014f2d34`, [Mac CI](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40438785287), passed all99 Mac Swift tests and six packaging checks. Release compilation then failed because ExploreController introduced `next`, `hash` and `tag` properties that collide with inherited UIKit/NSObject properties. No IPA was produced and zero of 26 UIKit cases ran. Focused32 renames those stored properties and retains the exact same behavior and all26 cases; Mac compilation/UI verification remain pending. Build30 remains the verified IPA.
