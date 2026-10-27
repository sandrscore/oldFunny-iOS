# oldFunny iOS

Native iOS client targeting current oldFunny Android behavior. Full behavioral parity is incomplete.

Verified build30 passed93 Mac Swift tests, six packaging checks and all25 offline UIKit cases. Exact reports and artifact hashes were checked; actual selected-read and confirmed-clear screenshots were reviewed.

[Download build30 unsigned IPA artifact ZIP](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40413896528/artifacts/12695150733), extract and update through Zeus. Expires November 2, 2026. IPA SHA256 `2742eacbc8252e8daf8a575383e2dc7ed9d9f0dcff48780fcb917da77ef7bfab`.

Candidate31 adds Explore tag tiles, user/tag search, shared mixed recent history, paged tag grids and retained viewers with exact tag-source reactions. 99 portable Swift contracts and six packaging checks pass; all26 UIKit cases require Mac verification. Three bounded anonymous GETs confirmed Explore/suggestions/tag-feed responses; no real social writes or read acknowledgements. Current target-phone checks remain separate.

See [build/signing instructions](ios/README.md), [behavior ledger](ios/ANDROID_PARITY.md) and [status](ios/PORT_STATUS.md).
