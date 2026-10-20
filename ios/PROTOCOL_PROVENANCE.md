# API and resource provenance

This app is implemented from the Android project's documented protocol findings,
not decrypted iOS instructions. The 4.6.8 executable stays encrypted and is not
linked into the new app.

Original UI reference: 4.6.8 / build 4121 / external ID 822002140 /
`ru.flysoft.ifunny`, released 2017-05-16. Original IPA SHA-256:
`45b28724621d0950c94c3d983d43292f0917a5962f7895926e2851b14bc6e48f`.

| Contract | Workspace evidence |
| --- | --- |
| `https://api.ifnapp.com/v4/`, installation/project/language headers | `android-diagnostics/revival/OrganicLoginProbe.java`, `tools/probe_api.py` |
| Public client `JuiUH&3822` and SHA-1 signature format | `docs/organic-login.md`, `OrganicLoginProbe.java`; public generator: https://github.com/tomdvies/IFunnyAPIStuff/blob/main/basictokengeneration.py |
| `GET app/features`, `POST oauth2/token` password form without `client_id` | Earlier approved diagnostic comparison in `docs/organic-login.md` |
| `GET account`, `feeds/featured`, `timelines/home`, `timelines/users/{uid}` | Supplied Retrofit interfaces; `tools/featured_feed_patch.py`, `docs/comment-posting.md` |
| `data.content.items`, `content.paging.cursors.next` | `tests/android/FeaturedFeedCheck.java`, `android-src/revival/CommentPostFeed.java` |
| `GET/POST content/{id}/comments`, `comments/{id}/replies` | Supplied Retrofit interface; `docs/comment-posting.md` |
| `text` and optional existing-post `content` comment form fields | Modern official APK interface and `docs/comment-posting.md` |
| `PUT/DELETE content/{id}/smiles?from=...` | Supplied Retrofit interface |
| `PUT reads/{ids}?from=feat|subs` | `docs/featured-feed.md`, `docs/subscriptions-reads.md` |
| Text-video `title`, `description`, MP4 `url`, `video_clip.screen_url` | Sanitized `tests/fixtures/text-video-with-text.json` |
| Comment `attachments.content` and modern thumbnails | Sanitized picture-comment fixtures |

Public app-client constants are not personal passwords, Apple credentials,
bearer tokens or signing identities. This app generates its own installation,
copies no existing account session, and stores its returned session in Keychain.

Matching request shape does not prove all current methods work, fresh login
passes anti-abuse classification, or every attachment is visible. Offline tests
and builds make no live social actions.

Classic icons come from the hash-checked recovery catalog. The Android launcher
provides the approved oldFunny eyepatch artwork. Staging records each PNG hash;
executables, Apple account metadata, provisioning and DRM are excluded.

## Connection correction (0.1.1)

The first native build incorrectly sent `iFunny/4.6.8(4121)` as its server-facing
User-Agent. A controlled comparison held the generated installation, public
Basic signature, host, routes and other headers constant. Legacy requests to
`feeds/featured` and `app/features` disconnected before an HTTP response; the
observed modern iOS profile `iFunny/10.45.1(25370)` returned HTTP 200 for both.
That profile was already recorded in this workspace's approved modern-iPhone
request investigation (`docs/organic-login.md`,
`tools/capture_client_eligibility.py`). A follow-up verified the generic actual
`UIDevice.model` form. The corrected Swift transport/model pipeline decoded five
Featured posts with usable media URLs. No user sessions, sign-in attempts or
social writes were used. Sanitized host evidence is under ignored
`.ios-work/ios-port/connection-fix/`.

`Wire.apiUserAgent` now supplies that server protocol profile to the native app
and probe. The independent oldFunny app version remains in Info.plist.
Connection failures preserve only Foundation's numeric URLError code and a
fixed explanation; raw error userInfo, URLs, headers and bodies remain excluded.
This does not establish fresh-login, visibility classification or feature parity.
