# oldFunny iOS

**0.2.0 (build 6)** brings the first classic interface pass: a charcoal author bar, dark sidebar, full-width media, compact post controls and styled comments with avatars and attached-post previews.

[Download unsigned IPA ZIP](https://github.com/sandrscore/oldFunny-iOS/actions/runs/39488614457/artifacts/12293774317) · [Simulator screenshots](https://github.com/sandrscore/oldFunny-iOS/actions/runs/39488614457/artifacts/12295550123) · [Build](https://github.com/sandrscore/oldFunny-iOS/actions/runs/39488614457)

Extract the IPA and sign/update with Zeus. Artifact expires October 27, 2026. IPA SHA-256: `91abe2d26c5fb00cae5311145f71696fa901570da6942dac021564da2cc9a3b5`.

18 Swift tests pass, and feed/sidebar/comments were reviewed on an iPhone 16 / iOS 18.5 simulator using offline sample content. The user confirmed password/CAPTCHA sign-in in 0.1.2; this UI pass preserves that authentication code. Version 0.2.0 still needs phone installation, saved-session and live feature checks. Pull down to refresh comments; its optional header refresh icon needs polish.

This is a new Swift/UIKit client, not an APK binary conversion. Complete Android feature parity is unfinished; Chats, Studio, push and other features remain pending. No original APK/IPA, credentials, personal sessions or signing secrets are published. Only the same 16 reviewed artwork files are included.

See [build and verification instructions](ios/README.md), [feature status](ios/PORT_STATUS.md) and [protocol provenance](ios/PROTOCOL_PROVENANCE.md).
