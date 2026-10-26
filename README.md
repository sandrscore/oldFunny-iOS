# oldFunny iOS

Native iOS client targeting current oldFunny Android behavior. Full behavioral parity is incomplete.

Build29 source `98e048e8c8e6f5f8e77c6d256eede91e2e6b83a1` passed90 Mac Swift tests, six packaging checks and all25 offline UIKit cases. Exact reports, archive hashes and actual read-tracking captures were checked. Separate regressions reproduced read-wrapper token-refresh rejection and cross-feed queue starvation; focused30 corrects both.

Candidate30 passes93 Linux Swift tests/six packaging checks. All25 native cases remain mandatory, with expanded fake token-refresh/pending-clear/duplicate prevention assertions. Authentication algorithms, Android and reviewed16 bitmaps are preserved. No real read acknowledgment or social write was used for validation; current target-phone checks remain separate.

The earlier build28 IPA is retained as the preceding checkpoint while30 verifies: [download unsigned artifact ZIP](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40407953474/artifacts/12691629064), extract and update through Zeus. Expires November2,2026. SHA256 `8af68fb23d0a56e28a86fbdbb7762ed000b651b07d1d437de8ed9c6dcdeedd15`.

See [build/signing instructions](ios/README.md), [behavior ledger](ios/ANDROID_PARITY.md) and [status](ios/PORT_STATUS.md).
