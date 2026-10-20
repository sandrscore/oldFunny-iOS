# oldFunny iOS

New Swift/UIKit implementation of oldFunny, targeting ARM64 and iOS 16 or later.
The intended test device is iPhone 16 / iOS 27.0.1. This is a source port, not
a converted APK or a modification of iFunny's encrypted executable.

**0.1.1 connection fix prepared; updated iPhone testing pending.**
Version 0.1.0 installed and launched on the target phone, but all server requests
failed. Controlled checks reproduced server disconnects for its legacy User-Agent.
The modern iOS request profile returned HTTP 200 for Featured and app/features;
the corrected Swift client decoded five Featured posts. This validates anonymous
host requests, not fresh phone sign-in or complete server compatibility.
See [feature status](PORT_STATUS.md) before treating this as a replacement.
The Android implementation, original archives and existing accounts are preserved.
The new app uses its own `mobi.oldfunny.ios` bundle and Keychain data.

## Structure

- `OldFunny/`: UIKit app, sign-in form, Keychain store, horizontal feeds, media
  viewing, comments/replies, basic account timelines and explicit smile toggles.
- `OldFunnyCore/`: portable Foundation networking/models and offline Swift tests.
- [Protocol provenance](PROTOCOL_PROVENANCE.md): endpoints and public client ID.
- `../tools/ios_native_project.py`: assets, Xcode project, scoped source export.
- `../tools/build_ios_native.py`: tests, Mac compilation, unsigned IPA packaging,
  SHA-256 and static architecture/encryption inspection.

## Build an unsigned IPA

On a Mac with Xcode and its iOS SDK installed:

```sh
python3 tools/build_ios_native.py
```

Output after a successful build:

```text
.ios-work/ios-port/dist/oldFunny-ios-0.1.1-unsigned.ipa
.ios-work/ios-port/dist/oldFunny-ios-0.1.1-unsigned.inspection.json
.ios-work/ios-port/dist/oldFunny-ios-0.1.1-unsigned.sha256
```

The build uses no Apple account, signing certificate, provisioning profile,
downloaded iFunny executable or decryption service. The unsigned IPA is intended
for Zeus to sign on the user's phone. Signing, installation and launch remain
untested; packaging and ARM64 alone do not prove them.

For the Steam Deck without Xcode, `.github/workflows/ios-native.yml` uses a
**standard GitHub-hosted Mac runner in a public repository**. GitHub documents
these runners as free for public repositories:
https://docs.github.com/en/actions/reference/runners/github-hosted-runners
The workflow refuses private repositories to avoid potentially paid minutes.
It keeps artifacts seven days, needs no Apple secrets, and does not publish a
GitHub release or install anything on a device.

1. The scoped source is published at https://github.com/sandrscore/oldFunny-iOS.
   Keep future uploads limited to native source and the reviewed asset subset.
2. Open Actions → Build oldFunny iOS → Run workflow (or push native sources).
3. After the job passes, download `oldFunny-ios-unsigned` from its artifacts.
4. Extract and sign/install the IPA through Zeus, preserving the existing
   iFunny app. Record launch, fresh sign-in and feed results separately.

## First build: 0.1.0 (1)

[Successful Mac build](https://github.com/sandrscore/oldFunny-iOS/actions/runs/39478438577)
from commit `64b4439b2a6b0147bed4a513cc71ecde2a5de4f0` passed all 13 core tests,
compiled with Xcode 16.4 / iOS SDK 18.5, and produced the unsigned IPA.
[Download the artifact ZIP](https://github.com/sandrscore/oldFunny-iOS/actions/runs/39478438577/artifacts/12291131063)
while retained (expires October 27, 2026). Extract the IPA from the ZIP for Zeus.

IPA SHA-256: `0faaff10a27b38025f6f3fd8f260b89a22c5fbfcb9ab38cd2e2e752c46c87c76`.
Independent local inspection confirmed bundle `mobi.oldfunny.ios`, version 0.1.0,
build 1, minimum iOS 16.0, ARM64, `cryptid=0`, no FairPlay resources and no
embedded extension/framework requiring additional architecture review.
This executable was compiled from source; it is not a decrypted original iFunny.
The ZIP and IPA hashes both matched the downloaded artifact. The build used no device. The user subsequently installed and launched 0.1.0;
network requests failed, so use the 0.1.1 correction instead.

Initial phone checks: sign the IPA with Zeus, install it, check launch, then check
Featured, fresh password sign-in, Subscriptions and media/comments navigation.
Report failures without sharing passwords, tokens or authentication transcripts.
This is a partial prototype: Chats, Studio/publishing, push and other parity work
remain unfinished. A successful build is not evidence of iOS 27 runtime or live
server compatibility. The initial anonymous probes failed with the legacy request profile. Correcting
the User-Agent resolved anonymous Featured access in a controlled host test;
authenticated requests and target-phone behavior still require validation.

## Test on Linux

With Swift 5.9 or newer and its Linux runtime dependencies:

```sh
swift test --package-path ios/OldFunnyCore --scratch-path .ios-work/ios-port/core-build
```

Offline tests cover request encoding, public Basic-auth vectors, CAPTCHA origins,
modern text-video/attached-comment parsing, cursor loops, refresh and concurrent
refresh sharing, session changes, and avoiding social-write retries. These tests
do not type-check UIKit or validate an iOS install.

An explicitly enabled read-only probe makes one anonymous feed GET with a new
diagnostic installation and reports counts only:

```sh
swift run --package-path ios/OldFunnyCore OldFunnyProbe --anonymous-read-only
```

It performs no login, account lookup, social action, read acknowledgement,
upload, preference change or existing-session transfer.

## Classic resources and export

The original recovery remains under ignored `.ios-work/restoration/4.6.8/`:
116 selected resources, 575 decoded image variants, 12 parsed layout archives,
English/Portuguese strings and a searchable `ui-audit/index.html` gallery.
`baseline.json` retains the original 4.6.8 identity; that executable stays encrypted.

Stage a hash-verified icon subset and the existing Android eyepatch artwork:

```sh
python3 tools/ios_native_project.py stage-assets --android-apk dist/oldfunny-4.6.7-optional-google-01.apk
python3 tools/ios_native_project.py generate
```

The staged resources are ignored and have a provenance manifest. Builds without
these files use system symbols and a simple original oldFunny monogram.

Export only the new source, build tools and optional selected icons:

```sh
python3 tools/ios_native_project.py export-source --include-assets --output .ios-work/ios-port/oldFunny-ios-source.zip
```

Use an unused output filename. The allowlisted export excludes original app
binaries, Apple account metadata, DRM, provisioning, sessions and the Android
workspace. Inspect it before public upload.

## Compatibility limits

Fresh sign-in must be verified on the target phone. Prior Android tests showed
that successful OAuth using the public iOS client does not alone guarantee full
content/attachment visibility. This port does not promise to change the server's
installation classification.

Google/Apple sign-in, push/background delivery, Chats, Studio/publishing and many
Android additions are not implemented. App identity changes affect OAuth, Keychain
and APNs. Complete feature parity is not established by this source or its tests.
