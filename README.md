# oldFunny iOS

A native iOS client targeting the project's current oldFunny Android behavior.
Full behavioral parity is incomplete.

The verified checkpoint is **0.3.0 build 25**: 63 Mac Swift tests, six packaging
checks and all 20 offline UIKit cases passed. No new target-iPhone validation or
live social writes were used.

[Download build 25's unsigned IPA artifact ZIP](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40010014066/artifacts/12526400847),
extract the IPA and update through Zeus. The artifact expires October 30, 2026.
IPA SHA-256: `2466cca5f4c34aaa9fd22d84ad12be6eb5a896190e15a49971c297cd0fce8b43`.

Candidate build 27 follows Android's dedicated deleted-reply placeholder layout.
Build26 compiled and ran22 UIKit cases:21 passed,1 deleted-depth-strip assertion
failed. All22 remain mandatory in27; Mac/UIKit verification is pending.

See [build and signing instructions](ios/README.md), the
[behavioral parity ledger](ios/ANDROID_PARITY.md), and [current status](ios/PORT_STATUS.md).
