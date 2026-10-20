# oldFunny iOS

A new Swift/UIKit oldFunny client in progress.

[Download 0.1.2 (build 3), unsigned IPA artifact ZIP](https://github.com/sandrscore/oldFunny-iOS/actions/runs/39482055586/artifacts/12291623017) — extract the IPA and sign/update through Zeus. Artifact expires October 27, 2026.

This build keeps manual CAPTCHA verification in an isolated in-app WebKit view and intercepts its scoped completion locally, then resumes sign-in once. It replaces the browser handoff that opened official iFunny. The Mac build and all 17 core tests pass; live CAPTCHA completion and authenticated sign-in still need a target-phone test.

Featured loads on the phone with the prior 0.1.1 request-header correction. See [build instructions and verification](ios/README.md) and [feature status](ios/PORT_STATUS.md). Chats, Studio/publishing, push and other features remain unfinished. This is a native source port, not an APK binary conversion or a feature-complete release.
