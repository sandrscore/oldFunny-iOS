# oldFunny iOS

Native iOS client targeting current oldFunny Android behavior. Full behavioral parity is incomplete.

Verified build30 passed93 Mac Swift tests, six packaging checks and all25 offline UIKit cases. Exact reports and artifact hashes were checked; selected-read and confirmed-clear screenshots were reviewed.

[Download build30 unsigned IPA artifact ZIP](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40413896528/artifacts/12695150733), extract and update through Zeus. Expires November 2, 2026. IPA SHA256 `2742eacbc8252e8daf8a575383e2dc7ed9d9f0dcff48780fcb917da77ef7bfab`.

Candidate31 adds Explore tag tiles, user/tag search, shared mixed history and paged tag grids with retained viewers. Its99 Mac core and six packaging tests passed, but Release compilation stopped on three UIKit property-name collisions; zero UIKit cases ran and no IPA was produced. Focused32 renames those properties, preserving all26 UI cases and behavior. Mac and simulator verification is pending. Three anonymous GETs verified Explore/suggestions/tag-feed responses; no real social writes or read acknowledgements. Target-phone checks remain separate.

See [build/signing instructions](ios/README.md), [behavior ledger](ios/ANDROID_PARITY.md) and [status](ios/PORT_STATUS.md).

Build32 CI ran 26 UIKit tests with 25 passing; the Explore case stopped at an incorrect selected-smile accessibility-label assertion. Build33 corrects both selected-state expectations while retaining all cases; its CI and phone checks remain pending. Build30 remains the verified checkpoint.

Build33 CI ran 26 UIKit tests with 25 passing. Empty Explore recents still exposed recycled cells to accessibility. Build34 hides the empty table and retains all tests; CI and current phone checks remain pending. Build30 remains the verified checkpoint.
