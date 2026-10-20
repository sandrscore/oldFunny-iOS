# Native iOS port status

Target: iPhone 16 / iOS 27.0.1. Bundle ID: `mobi.oldfunny.ios`.

This is **an incomplete first implementation**, not a feature-complete APK
conversion. The first unsigned ARM64 IPA compiled successfully on the public Mac
runner; [build and download details](README.md#first-build-010-1). It has not been
signed, installed or run on an iPhone.

| Area | Source implemented | Validation and remaining work |
| --- | --- | --- |
| App-client requests | HTTPS, documented iOS Basic protocol, installation cookie, refused API redirects | Offline tests; live anonymous feed probe separate; server classification unknown |
| Password sign-in | Native form, bootstrap/OAuth/account lookup, origin-checked CAPTCHA link | Offline protocol tests; actual CAPTCHA completion/session issuance not device-tested |
| Session storage/refresh | Device-only Keychain; shared refresh; old-account response fencing; local removal | Portable core tests; Keychain integration needs Mac/device checks |
| Featured / Subscriptions | Endpoint routing, paging, duplicate/cursor-loop handling, horizontal viewer, refresh | Offline models; UIKit and live accounts unverified; no persistent feed cache yet |
| Profile | Author and own-account timelines | Basic timeline only; no profile editing, advanced search, pins or featured grid yet |
| Media | Still-image zoom, WebP via ImageIO, bounded small GIF preview, native AVPlayer controls, text-video title/body | Device/codec checks pending; long-image fidelity, GIF frame timing, video zoom/trim/scrub parity pending |
| Comments | Paginated thread/replies, text sending, opening attached posts | Offline request tests; no live publication; inline thumbnails, mentions, attachment picker and deletion pending |
| Reactions/share | Explicit smile toggle and public-link share sheet | No live social writes; device checks pending; unsmile/repub features pending |
| Read tracking | Bounded read-acknowledgement API method | Exposure timers, durable per-account read queues/filtering and subscription badges not connected yet |
| Classic appearance | Dark/yellow chrome, staged original icons and approved Android launcher | Partial styling; original full screen layouts not recreated or visually verified |
| Build/signing | Generated Xcode project, Mac build script, unsigned IPA packaging/inspection, public-repo CI | Local script tests; Xcode 16.4 build and 13 Mac core tests passed; downloaded IPA hashes and ARM64/cryptid=0 verified; Zeus install pending |
| Studio/publishing | Not implemented yet | Caption/comics/GIF/video editing, drafts, uploads/task polling and publishing need native implementations |
| Chats/groups | Not implemented yet | REST/WAMP state machine, attachments, groups/discovery/drafts/read receipts pending |
| Notifications | Not implemented yet | APNs requires independent signing/entitlement/server registration; sockets do not establish background push parity |
| Other sign-in | Not implemented yet | Google/Apple/web OAuth require client IDs/callbacks and separate validation |
| Search/settings/saves | Not implemented yet | Advanced search, privacy/settings, Photos exports, pinning and other Android additions remain on the parity checklist |

No user credentials or existing sessions are embedded in source or export. The
app does not modify or sign out the existing iFunny app. Android implementation
changes are excluded from this port.

Next required milestone: target-phone Zeus signing, installation, launch and
fresh sign-in/feed checks. Resolve those failures before claiming an Android replacement or testing
live publishing/chat writes.
