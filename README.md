# oldFunny iOS

A new Swift/UIKit oldFunny client in progress.

[Download 0.1.1 (build 2), unsigned IPA artifact ZIP](https://github.com/sandrscore/oldFunny-iOS/actions/runs/39480215788/artifacts/12291750634) — extract the IPA and sign/update through Zeus. Artifact expires October 27, 2026.

This fixes server disconnects caused by the legacy 4.6.8 User-Agent. Controlled anonymous requests now return HTTP 200 and the corrected Swift client decodes Featured posts. The Mac build and all 15 core tests pass. Updated target-phone behavior and fresh sign-in still require testing.

See [build instructions and verification](ios/README.md) and [feature status](ios/PORT_STATUS.md). Chats, Studio/publishing, push and other features remain unfinished. This is a native source port, not an APK binary conversion or a feature-complete release.
