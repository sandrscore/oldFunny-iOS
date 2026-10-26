# oldFunny iOS

Native iOS client targeting the project's current oldFunny Android behavior. Full behavioral parity is incomplete.

Verified checkpoint **0.3.0/build28** passed74 Mac Swift tests, six packaging checks and all23 offline UIKit cases. Downloaded logs/reports/artifact hashes were checked; the attachment screenshot was reviewed.

[Download build28's unsigned IPA artifact ZIP](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40407953474/artifacts/12691629064), extract the IPA and update through Zeus. Artifact expires November2,2026. SHA256: `8af68fb23d0a56e28a86fbdbb7762ed000b651b07d1d437de8ed9c6dcdeedd15`.

Candidate29 integrates durable read tracking, actual viewer visibility/lifecycle gates, immediate Subscriptions loading credit, filtered Featured paging and confirmed Subscriptions-only unread clearing. 90 Linux contracts/six packaging checks pass; all25 UIKit cases require Mac execution. No real read acknowledgement or social write was used for validation. Current target-iPhone checks remain separate.

See [build/signing instructions](ios/README.md), [behavior ledger](ios/ANDROID_PARITY.md) and [status](ios/PORT_STATUS.md).
