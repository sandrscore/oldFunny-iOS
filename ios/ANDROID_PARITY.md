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
| Sidebar destinations | Featured, Collective, Subscriptions, Explore, Profile, Chats, Activity, Studio, preferences; `main/menu`, `ChatsActivity`, `NewCaptionStudio` | Partial: Featured/Collective/Subs/Profile/Account only; remaining destinations must have real implementations |
| Drawer gestures | Open/close gestures, scrim, selected row, retained section; `main/IFunnyMenuActivity` | Partial: menu tap, shade and left-swipe close; edge-open and navigation restoration pending |
| Sidebar counts | Real Featured/Subs/Chats counters, no invented badges; `FeaturedFeed`, `SubscriptionsReads`, `ChatsBadge` | Missing |
| Mark as viewed | Long-hold Subscriptions only; clear on confirmed success; `SidebarViewed` | Missing; never restore cancelled Featured action |
| Featured refresh | Latest page on stale return, retained recent position, no countdown/shuffle; `FeaturedFeed` | Partial: paging/refresh; stale cache policy pending |
| Featured reads | Foreground selected post only, per-account ledger, retry and skip viewed; `FeaturedReads` | Missing integration; API method alone is insufficient |
| Subscription reads | Immediate settled selection, local unread credit, server reconciliation, durable queues; `SubscriptionsReads` | Missing |
| Collective | POST form `limit/next` to `/feeds/collective`; `Retrofit$RestInterface.getCollective` in primary smali | Source added; current server and device reads pending |
| Horizontal viewer | Retain index, edge pagination, page ordering and return position; `gallery/GalleryFragment` | Source, needs new phone regression |
| Comments entry | Up gesture and comment-button tap share retained panel; native trace above | Source, actual UIKit gesture tests required |
| Comments exit | Down at boundary, header Back; preserve post/zoom/draft | Source, UIKit and phone checks required |
| Information entry/exit | Down from media, up to return; retained child | Source; counts/date/author/text/tags shown; full action parity pending |
| Information actions | Original author/republisher, date, views/smiles/repubs, user lists, tags/edit tags; `IFunnyWorkInfoFragment` | Partial: author routes and details; user-list/tag navigation/editing missing |
| Image fit | Native fit/centering, tall images and title/body alignment; `ContentBehavior`, `ModernPostText` | Partial: width/fit/scroll/pinch; full-resolution tall-image fidelity pending |
| Pinch/pan bounds | Image-style scale/pan with pager handoff at bounds; `ContentBehavior` | Partial: still-image zoom, no full edge handoff parity |
| Double tap | Native smile toggle; `GalleryFragment.b(View)` | Source added; no live reaction used during checks |
| Triple tap | Preserve original unsmile gesture; native content listener | Missing; footer unsmile available, exact gesture still to trace |
| Smile/unsmile | Toggle mutually exclusive state, counts and signed-out route; original Retrofit methods | Source; request tests, live/device checks pending |
| Video/GIF zoom | Same transformed content as images; `VideoControls` and native behavior | Missing: video still uses AVPlayer controls |
| Tap playback | Pause/resume only in video; margins hide chrome; paused triangle scales with video | Partial: native AVPlayer controls, Android tap/chrome rules missing |
| Scrubber | Only >10s, transparent 24dp hit area, elapsed/total during drag, coalesced accurate seek, retained play state; `VideoControls` | Partial: native player provides seeking; exact control/behavior pending |
| Mute | Hide while pinching/zoomed, retain audio state; `VideoControls` | Partial: native player audio controls only |
| GIF rendering | Timing/loop/dimensions, MP4-backed GIF support; `VideoCompatibility` | Partial: bounded UIImage animation and native MP4, full timing parity pending |
| Post hold menu | Share/Save/Chat/Pin/More with ownership and format eligibility; gallery menu patches | Partial: link/copy/share/Save/repub added; Chat/Pin/More missing |
| Republish | POST `/content/{cid}/republished?from=...`, DELETE to remove; original Retrofit methods | Source added, explicit confirmation and no replay; live checks pending |
| Image save | Save original supported media to gallery; native options | Source added for Photos; actual permission/format/device checks pending |
| GIF save | Original GIF or MP4→animated GIF, frames/timing preserved; `GifSaving` | Partial: original GIF save; MP4 GIF currently saved as video, conversion missing |
| Video save | Original MP4 with audio; `VideoSaving` | Source added; file fidelity/Photos device test pending |
| Post sharing | Public links, internal post navigation, platform share targets | Partial: iOS share sheet and copy link; in-app inbound link routing missing |
| Comment layout | Blue author, round avatar, date, proportional preview, replies/smile counts; native CommentViews/PictureComments | Partial: basic rows/previews; exact top/hidden/deleted states and in-row reactions pending |
| Thread paging | Cursor continuation, dedupe, retry without losing loaded rows | Source, endpoint/server pagination checks pending |
| Replies | Root parent context, recipient chip, mentions, retained thread; `AnswersFragment` | Partial: reply pages; root/recipient chip/notification semantics missing |
| Comment options | Copy, smile/unsmile, reply, report, owned deletion | Source added to hold menu; per-action request tests and live/device validation pending |
| Comment selection | Pencil/hold multi-selection, permitted rows, immediate partial-success counts; `CommentDelete` | Missing bulk mode; single delete added |
| Comment delete ack | Empty successful bulk results mean success only with explicit outer status | Missing bulk mode; do not invent equivalent receipts for malformed responses |
| Attachment plus | Full-screen 3-column own posts/reposts, cursor paging, retained draft on Back; `CommentPostFeed`, `NativePostGrid` | Source added; picker needs simulator/account fixture and device checks |
| Attachment choice | One thumbnail+X, replace/remove independently of text | Source: visible X added in build 8; draft revision tests pass; offline picker/Back/refresh/removal UI test added, execution and phone checks pending |
| Attachment send | `text` + one `content` ID to comment/reply endpoint; no separate upload | Source now connected; no live comments submitted by agent |
| Draft success/failure | Clear exact submitted revision only; retain newer edits/uncertain writes | Source and tests; lifecycle/process restoration pending |
| Send retries | Never replay an uncertain social write; `comment-send-01`, `CommentComposer` | Existing single-attempt API retained; refresh-only GET retry preserved |
| Mentions | Unicode offsets, exact IDs, suggestions/recent users/avatars, chips/colors and notification fields; `CommentMentions`, `MentionComments` | Missing |
| Keyboard dismissal | First outside tap dismisses and preserves text/attachment/recipient, next tap normal | Source basic text/attachment behavior; recipient/mention parts missing |
| User profile | Information header, posts/reposts grid, subscriptions/subscribers, actions; profile fragments | Partial: timeline viewer only |
| Own profile | Account identity, editing, cover/avatar, counters, settings | Missing beyond account/session screen and own timeline |
| Featured profile count | Dedicated `/timelines/users/{uid}/featured`, 3-column grid; `ProfileFeatured` | Missing |
| Grid viewer return | Swipe full snapshot, continue same endpoint, Back to retained grid | Missing general grid/viewer handoff |
| Profile pinning | Own profile only, max3, server readback, pinned menu/grid mark; `ProfilePins` | Missing |
| Advanced profile search | Combined media, all tags (AND), original author, repub toggle; `ProfileSearch*` | Missing |
| Search state | Progressive bounded history scan, cancel stale filters, retain results/scroll, clear on exit | Missing |
| User/tag Explore | Real user/tag search, recent users/tags, tag galleries | Missing |
| Subscribe/block | Confirmed subscribe/unsubscribe/block state with ownership rules | Missing |
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
| Session storage | Device-only Keychain, shared refresh, account fencing; no token in media/logs | Existing source/tests; relaunch and new build phone checks pending |
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

## Checkpoint audit (2026-10-20)

Build 7 (`618c148e…`) compiled on the public Mac runner. Its downloaded IPA was
independently inspected: version 0.3.0/build 7, ARM64, cryptid=0, no preview marker
or test bundle. SHA-256: `e1a4c6693c6af8116a3706b00ee6c945629c7a6679df356b264277a481ae00f6`.
Its actual UIKit run executed three tests: one passed, two failed (header context
and a keyboard-dismissal tap opening the underlying profile). It is not a
verified gesture checkpoint.

Build 8 source corrects per-post header context, adds the visible attachment X, corrects keyboard-dismissal routing,
and extends offline UIKit coverage to attachment selection, picker Back, refresh
and removal without losing text. The workflow retains diagnostics before a
mandatory gate requiring every gesture test to execute and pass. These source
changes have not yet been compiled. Local verification: 22 Swift contract tests
and 6 packaging/test-gate checks pass. Android/protected-file hashes still match
the preserved baseline. No live service write or iPhone test was performed.
