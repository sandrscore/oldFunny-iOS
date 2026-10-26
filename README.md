# oldFunny iOS

Native iOS client targeting the project's current oldFunny Android behavior.
Full behavioral parity is incomplete.

Verified checkpoint **0.3.0/build27** passed67 Mac Swift, six packaging checks and
all22 offline UIKit cases. The deleted-reply screenshot and complete reports were
reviewed. Current target-iPhone validation remains separate and unverified.

[Download build27's unsigned IPA artifact ZIP](https://github.com/sandrscore/oldFunny-iOS/actions/runs/40404742369/artifacts/12691086021),
extract the IPA and update through Zeus. Artifact expires November2,2026.
SHA256: `67488a070a27fb8eb08348663dc281e097620861ba94fbe98334d2cab30798f6`.

Candidate28 adds inbound attachment cards, full-post loading and API404 public
picture recovery. Local74 core/six packaging checks pass;23 UIKit cases require
Mac verification. Anonymous read probes confirmed direct/recovered picture routes;
no social/read writes were used.

See [build/signing instructions](ios/README.md), [behavior ledger](ios/ANDROID_PARITY.md)
and [current status](ios/PORT_STATUS.md).
