# Native iOS port status

Target: iPhone 16 / iOS 27.0.1. Bundle ID: `mobi.oldfunny.ios`.

Version 0.2.0 (build 6) is the first classic interface pass. Release compilation,
18 Mac core tests, local packaging checks and three offline simulator renders
passed. The feed, sidebar and comments were visually inspected on iPhone 16 /
iOS 18.5. The user previously confirmed Featured and password/CAPTCHA sign-in
in 0.1.2 on their target phone. This UI pass preserves those auth source files.
The new version's target-phone UI and saved-session behavior remain untested;
complete Android feature parity is unfinished.

| Area | Source implemented | Validation and remaining work |
| --- | --- | --- |
| App-client requests | HTTPS, documented iOS Basic protocol, installation cookie, refused API redirects | Modern iOS protocol profile: anonymous Featured and app/features return 200; Swift decodes 5 posts; authenticated classification unknown |
| Password sign-in | Native form, bootstrap/OAuth/account lookup, manual in-app CAPTCHA and origin/frame-checked callback | Offline protocol tests; User confirmed 0.1.2 CAPTCHA completion and successful password sign-in; 0.2.0 preserves this code |
| Session storage/refresh | Device-only Keychain; shared refresh; old-account response fencing; local removal | 0.1.2 sign-in/session creation user-confirmed; refresh/relaunch persistence still needs device checks |
| Featured / Subscriptions | Endpoint routing, paging, duplicate/cursor-loop handling, horizontal viewer, refresh | Featured previously phone-confirmed; 0.2.0 simulator layout reviewed; Subscriptions and persistent feed cache need work |
| Profile | Author and own-account timelines | Basic timeline only; no profile editing, advanced search, pins or featured grid yet |
| Media | Still-image zoom, WebP via ImageIO, bounded small GIF preview, native AVPlayer controls, text-video title/body | Device/codec checks pending; long-image fidelity, GIF frame timing, video zoom/trim/scrub parity pending |
| Comments | Paginated thread/replies, text sending, opening attached posts | Inline attached-post previews, avatars and author profile links added; offline request tests; mentions, attachment picker and deletion pending |
| Reactions/share | Explicit smile toggle and public-link share sheet | No live social writes; device checks pending; unsmile/repub features pending |
| Read tracking | Bounded read-acknowledgement API method | Exposure timers, durable per-account read queues/filtering and subscription badges not connected yet |
| Classic appearance | Flat charcoal author bar, dark sidebar, full-width viewer, small counters, classic comment rows, reviewed original icons | Three simulator screens reviewed; exact original layouts and target-phone UI remain unverified; comments header refresh polish pending |
| Build/signing | Generated Xcode project, Mac build script, unsigned IPA packaging/inspection, public-repo CI | 0.2.0 build 6 Mac compilation and 18 core tests passed; IPA hashes/ARM64/cryptid=0 verified; simulator launch/layout checked; Zeus phone update pending |
| Studio/publishing | Not implemented yet | Caption/comics/GIF/video editing, drafts, uploads/task polling and publishing need native implementations |
| Chats/groups | Not implemented yet | REST/WAMP state machine, attachments, groups/discovery/drafts/read receipts pending |
| Notifications | Not implemented yet | APNs requires independent signing/entitlement/server registration; sockets do not establish background push parity |
| Other sign-in | Not implemented yet | Google/Apple/web OAuth require client IDs/callbacks and separate validation |
| Search/settings/saves | Not implemented yet | Advanced search, privacy/settings, Photos exports, pinning and other Android additions remain on the parity checklist |

No user credentials or existing sessions are embedded in source or export. The
app does not modify or sign out the existing iFunny app. Android implementation
changes are excluded from this port.

Next required milestone: target-phone Zeus signing and updating to 0.2.0, then
classic UI/navigation/media/comments checks and saved-session regression. Resolve those failures before claiming an Android replacement or testing
live publishing/chat writes.
