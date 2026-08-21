# Unity Play Verification real-Unity acceptance

Acceptance status: **APPROVED — SELECTED EDITOR PLAYMODE TESTS AND SOURCE-ONLY SCENARIOS ONLY**

Acceptance date: **2026-08-21**

Standalone repository target: **`0.2.0`**

Play Skill: **`0.2.0`**

Result schema: **`1.0.0`**

This record contains public-safe evidence. Local user names, source paths, artifact paths, command-line access tokens, machine identifiers, and certificate owner details beyond the publisher name are intentionally omitted.

## Compatibility reapproval status

| Unity Editor | Test Framework | Approved source | Editor trust | Acceptance |
| --- | --- | --- | --- | --- |
| `2022.3.62f3` | `1.1.33` | `registry` / `https://packages.unity.com` | valid Authenticode; Unity Technologies signer; exact SHA-256 | `APPROVED` |
| `6000.0.69f1` | `1.6.0` | Editor-builtin | valid Authenticode; Unity Technologies signer; exact SHA-256 | `APPROVED` |
| `6000.5.3f1` | `1.7.0` | Editor-builtin | valid Authenticode; Unity Technologies signer; exact SHA-256 | `APPROVED` |

Compatibility schema 1.2.0 preserves the immutable 1.0.0 and registry-only 1.1.0 contracts while adding source-specific Editor identity. Registry entries require the official Unity registry origin. Builtin entries require `source: builtin`, no registry URL, and the exact approved signed Unity executable SHA-256. Every entry also pins the deterministic resolved package tree SHA-256.

| Unity Editor | Unity.exe SHA-256 | Package files | Package tree SHA-256 |
| --- | --- | ---: | --- |
| `2022.3.62f3` | `02e80b2c1d7f983375c97b612655be9f8ed852121e3a4eedf1570701c48ea5cd` | 669 | `18b9576da338b999a61157c9235f4ef3a91360cc877dbf49281a13f37e7da36b` |
| `6000.0.69f1` | `3927c20e4c76f15951989fd4866546b03d3ebfcc72bb5d708cd6397fad50451d` | 1,272 | `af8b4770ae87d4ebb657367c32add4ba20d5e204f07ccdfa1c1bbc4ef045f18f` |
| `6000.5.3f1` | `5e54f3a9953179419ddf8af860c3ccdcbb6ada45276fa9df06fdaaaa1124a118` | 1,166 | `e7b3c700661018e5c368305fcc151ae015fc6ebb8123e2dbe0bd07fb4ca69dbf` |

All package identities use canonicalization `upv-package-tree-relative-path-length-sha256-lf-v1` and two consecutive stable snapshots.

## Matrix

The production entrypoint reran the requested 18-case matrix: six cases for each of the three Editor/Test Framework pairs. It also ran one source-overlay compilation failure per Editor, for 21 results total. All results were schema-valid, every source fixture remained `UNCHANGED`, and Git metadata remained within contract.

| Unity | Case | Expected and actual | NUnit or compilation summary | Original |
| --- | --- | --- | --- | --- |
| `2022.3.62f3` | pass | `PLAY_VERIFIED` | 1 passed | `UNCHANGED` |
| `2022.3.62f3` | fail | `PLAY_FAILED` | 1 failed | `UNCHANGED` |
| `2022.3.62f3` | skip | `VERIFICATION_BLOCKED` | 1 skipped | `UNCHANGED` |
| `2022.3.62f3` | inconclusive | `VERIFICATION_BLOCKED` | 1 inconclusive | `UNCHANGED` |
| `2022.3.62f3` | zero | `VERIFICATION_BLOCKED` | 0 selected | `UNCHANGED` |
| `2022.3.62f3` | scenario | `PLAY_VERIFIED` | 1 passed; 1 PNG | `UNCHANGED` |
| `2022.3.62f3` | scenario compile failure | `PLAY_FAILED` | compiler error in `Editor.log`; no NUnit promotion | `UNCHANGED` |
| `6000.0.69f1` | pass | `PLAY_VERIFIED` | 1 passed | `UNCHANGED` |
| `6000.0.69f1` | fail | `PLAY_FAILED` | 1 failed | `UNCHANGED` |
| `6000.0.69f1` | skip | `VERIFICATION_BLOCKED` | 1 skipped | `UNCHANGED` |
| `6000.0.69f1` | inconclusive | `VERIFICATION_BLOCKED` | 1 inconclusive | `UNCHANGED` |
| `6000.0.69f1` | zero | `VERIFICATION_BLOCKED` | 0 selected | `UNCHANGED` |
| `6000.0.69f1` | scenario | `PLAY_VERIFIED` | 1 passed; 1 PNG | `UNCHANGED` |
| `6000.0.69f1` | scenario compile failure | `PLAY_FAILED` | compiler error in `Editor.log`; no NUnit promotion | `UNCHANGED` |
| `6000.5.3f1` | pass | `PLAY_VERIFIED` | 1 passed | `UNCHANGED` |
| `6000.5.3f1` | fail | `PLAY_FAILED` | 1 failed | `UNCHANGED` |
| `6000.5.3f1` | skip | `VERIFICATION_BLOCKED` | 1 skipped | `UNCHANGED` |
| `6000.5.3f1` | inconclusive | `VERIFICATION_BLOCKED` | 1 inconclusive | `UNCHANGED` |
| `6000.5.3f1` | zero | `VERIFICATION_BLOCKED` | 0 selected | `UNCHANGED` |
| `6000.5.3f1` | scenario | `PLAY_VERIFIED` | 1 passed; 1 PNG | `UNCHANGED` |
| `6000.5.3f1` | scenario compile failure | `PLAY_FAILED` | compiler error in `Editor.log`; no NUnit promotion | `UNCHANGED` |

Each pass case used a multi-frame `[UnityTest]`. Deliberate failures produced complete NUnit XML. Skip, Inconclusive, and zero-selection cases were blocked without promotion. Each successful scenario produced the exact receipt and one non-empty 12,152-byte PNG with SHA-256 `5caaf573ffc294827df39b5de5bf9f433ac2d1f443c29ff696d19fd12d36c47b`; pixels were not judged. Each broken overlay produced `scriptCompilation: VERIFIED_FAILURE`, retained matching package identity, proved zero remaining Job Object processes, and ended `PLAY_FAILED`.

The sealed rerun reported `caseCount: 21`, `approvedIdentityCaseCount: 21`, `sourcePolicyBlockedCaseCount: 0`, and `acceptanceStatus: APPROVED`. Its public-safe summary SHA-256 is `1bb38b202cdb8a71bd543a5fc81a374b874dd4e6792f340f7df421842128d157`. The separate three-Editor package-discovery summary has SHA-256 `5f395b3ab85876ecdab92ac76e6c3ac1365ca58628b13f9534c3f23034756bd1` and status `COMPLETE`. Both external artifact trees remain preserved on the acceptance host and are not committed because they contain local paths and generated Unity data.

## Production hashes

| File | SHA-256 |
| --- | --- |
| `scripts/invoke-unity-play-verification.ps1` | `ad5d1d71e93c177b54c991c5ab5a58671081149c4f720d053a8701d2f8ea5dec` |
| `scripts/lib/unity-play-verification-core.ps1` | `1c40fa02c5a2d44bc2c7af6f162949bc57dbc41c8bf7fe988bee36026e7e400c` |
| `scripts/lib/unity-test-framework-identity.ps1` | `ecd29468afe9986b3e4ec3c839ce1174bf2b1dbca2eab2f01f13280ef2eb852b` |
| `harness/PlayVerificationHarness.cs` | `0bc54dcda85452c3bfa308502bff5c193bde9d829a7d56fe7169e7bdf0f25e2a` |
| `unity-play-verification-result-1.0.0.schema.json` | `92e5dc69d9aceeefc5724a91e44411a9c6423fa9294e342dbe365017efe63ac3` |
| `unity-play-scenario-1.0.0.schema.json` | `dc97645c4a5fe029a19dd868b2b2fa2cc4657b14c50cd407d5bec2833bdba186` |
| `unity-play-compatibility-1.0.0.schema.json` | `2a5bf36cc674f64a836b6070adbc9848aabb4215aa92b3edbcd64776ac559d3b` |
| `unity-play-compatibility-1.1.0.schema.json` | `4627915e91f8d955135902d2116dc7e2f6ddb26ca388628bb4d1220634085493` |
| `unity-play-compatibility-1.2.0.schema.json` | `70e70317a6b23267bd09033dd27cb9fffd3891700fec9ea81dbfa7c1731b0931` |
| `config/unity-play-compatibility.json` | `17e054cd31a9ce641ec605a8299c1ea22ad92031e58dd2fa2c3c706a12a5546d` |

These hashes identify the standalone production candidate. The 2026-08-21 rerun described above revalidated this exact set; documentation, repository metadata, tests, and the test-only schema validator may have separate hashes.

## Safety evidence

- Unity received only external E-drive copies; no command line contained a source project path.
- Base-copy fingerprint equaled the source fingerprint before every run, and source copy-set status was `UNCHANGED` afterward.
- Acceptance fixtures intentionally had no `.git`; Git metadata status was consistently `NOT_PRESENT`. Separate contract tests prove byte-level Git metadata mutation classification and final-status precedence.
- Job Object creation, kill-on-close configuration, assignment, and zero-active-process accounting were required.
- Scenario manifests and compatibility entries were constrained to exact required property sets, duplicate receipt IDs were rejected, and the scenario bundle hash was rechecked immediately before overlay copying.
- All 21 production runs recorded matching preflight/post-run source kinds, exactly one resolved package, two stable package snapshots, the approved package SHA-256, and the approved Unity executable SHA-256.
- Unity 6 packages remained explicitly `builtin` with null registry origin; they were never represented as official registry content.
- An exact-ProductVersion unsigned fake remained blocked by the production Authenticode gate and was executable only through the internal process-control test seam.
- No Unity, package, module, Test Framework, SDK, or certificate was installed by the verifier.

## Scope boundary

This approval proves only the recorded Editor PlayMode selection and source-only scenario contract. It does not approve Player Build, standalone or device players, OS input automation, networking, performance endurance, complete gameplay, subjective feel, visual quality, accessibility, or release readiness.

Source-only validation is not a security sandbox. The Unity project and scenario C# execute with the same user privileges as Unity. The verifier checks reviewed project code, an approved toolchain identity, and evidence completeness; it does not contain a fully malicious project or prevent that project from modifying same-user artifacts. Post-run package hashing protects promotion to `PLAY_VERIFIED`, but it does not sandbox code before that code executes or make artifacts tamper-proof against a malicious process with the same privileges.
