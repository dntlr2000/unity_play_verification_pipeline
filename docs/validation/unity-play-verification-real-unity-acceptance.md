# Unity Play Verification real-Unity acceptance

Acceptance status: **APPROVED — SELECTED EDITOR PLAYMODE TESTS AND SOURCE-ONLY SCENARIOS ONLY**

Acceptance date: **2026-08-20**

Standalone repository target: **`0.2.0`**

Play Skill: **`0.2.0`**

Result schema: **`1.0.0`**

This record contains public-safe evidence. Local user names, source paths, artifact paths, command-line access tokens, machine identifiers, and certificate owner details beyond the publisher name are intentionally omitted.

## Approved compatibility pairs

| Unity Editor | Test Framework | Editor trust | Acceptance |
| --- | --- | --- | --- |
| `2022.3.62f3` | `1.1.33` | valid Authenticode; Unity Technologies signer | `APPROVED` |
| `6000.0.69f1` | `1.6.0` | valid Authenticode; Unity Technologies signer | `APPROVED` |
| `6000.5.3f1` | `1.7.0` | valid Authenticode; Unity Technologies signer | `APPROVED` |

The three executable SHA-256 values observed during the sealed run were:

| Unity Editor | Unity.exe SHA-256 |
| --- | --- |
| `2022.3.62f3` | `02e80b2c1d7f983375c97b612655be9f8ed852121e3a4eedf1570701c48ea5cd` |
| `6000.0.69f1` | `3927c20e4c76f15951989fd4866546b03d3ebfcc72bb5d708cd6397fad50451d` |
| `6000.5.3f1` | `5e54f3a9953179419ddf8af860c3ccdcbb6ada45276fa9df06fdaaaa1124a118` |

## Matrix

The production entrypoint ran six isolated cases for every pair, 18 cases total. Every expected and actual final status matched.

| Unity | Case | Expected and actual | NUnit summary | Original |
| --- | --- | --- | --- | --- |
| `2022.3.62f3` | pass | `PLAY_VERIFIED` | 1 passed | `UNCHANGED` |
| `2022.3.62f3` | fail | `PLAY_FAILED` | 1 failed | `UNCHANGED` |
| `2022.3.62f3` | skip | `VERIFICATION_BLOCKED` | 1 skipped | `UNCHANGED` |
| `2022.3.62f3` | inconclusive | `VERIFICATION_BLOCKED` | 1 inconclusive | `UNCHANGED` |
| `2022.3.62f3` | zero | `VERIFICATION_BLOCKED` | 0 selected | `UNCHANGED` |
| `2022.3.62f3` | scenario | `PLAY_VERIFIED` | 1 passed; 1 PNG | `UNCHANGED` |
| `6000.0.69f1` | pass | `PLAY_VERIFIED` | 1 passed | `UNCHANGED` |
| `6000.0.69f1` | fail | `PLAY_FAILED` | 1 failed | `UNCHANGED` |
| `6000.0.69f1` | skip | `VERIFICATION_BLOCKED` | 1 skipped | `UNCHANGED` |
| `6000.0.69f1` | inconclusive | `VERIFICATION_BLOCKED` | 1 inconclusive | `UNCHANGED` |
| `6000.0.69f1` | zero | `VERIFICATION_BLOCKED` | 0 selected | `UNCHANGED` |
| `6000.0.69f1` | scenario | `PLAY_VERIFIED` | 1 passed; 1 PNG | `UNCHANGED` |
| `6000.5.3f1` | pass | `PLAY_VERIFIED` | 1 passed | `UNCHANGED` |
| `6000.5.3f1` | fail | `PLAY_FAILED` | 1 failed | `UNCHANGED` |
| `6000.5.3f1` | skip | `VERIFICATION_BLOCKED` | 1 skipped | `UNCHANGED` |
| `6000.5.3f1` | inconclusive | `VERIFICATION_BLOCKED` | 1 inconclusive | `UNCHANGED` |
| `6000.5.3f1` | zero | `VERIFICATION_BLOCKED` | 0 selected | `UNCHANGED` |
| `6000.5.3f1` | scenario | `PLAY_VERIFIED` | 1 passed; 1 PNG | `UNCHANGED` |

Each pass case used a multi-frame `[UnityTest]`. Each fail case contained a deliberate assertion failure with complete NUnit XML. Skip, Inconclusive, and zero-selection cases were rejected without promotion. Each scenario case compiled the isolated overlay, produced the exact expected assertion receipt, and created a non-empty 1280×720 PNG whose SHA-256 was recorded. Screenshot pixels were not used for pass/fail.

The final standalone migration rerun reported `caseCount: 18`, `acceptanceStatus: APPROVED`, 18 schema-valid result documents, and summary SHA-256 `f7c92ddb1735caa2f8f782f29afcda3af9eb2f6d99901aff4c04a1a5eae58463`. The external artifact tree remains preserved on the acceptance host and is not committed because it contains local paths and generated Unity data.

## Production hashes

| File | SHA-256 |
| --- | --- |
| `scripts/invoke-unity-play-verification.ps1` | `80c7818a78e200035600ef0672bda272de339c71f20eae64f3b780e0471c4a41` |
| `scripts/lib/unity-play-verification-core.ps1` | `044521d110e09555686442ea2f3af574266c34423cf356cca82a1fd253b1cdbc` |
| `harness/PlayVerificationHarness.cs` | `0bc54dcda85452c3bfa308502bff5c193bde9d829a7d56fe7169e7bdf0f25e2a` |
| `unity-play-verification-result-1.0.0.schema.json` | `92e5dc69d9aceeefc5724a91e44411a9c6423fa9294e342dbe365017efe63ac3` |
| `unity-play-scenario-1.0.0.schema.json` | `dc97645c4a5fe029a19dd868b2b2fa2cc4657b14c50cd407d5bec2833bdba186` |
| `unity-play-compatibility-1.0.0.schema.json` | `2a5bf36cc674f64a836b6070adbc9848aabb4215aa92b3edbcd64776ac559d3b` |
| `config/unity-play-compatibility.json` | `715e8e0c756658d3796c53ffa77835c23d6c9e80e6d6537ef620b9fd385f624e` |

These hashes identify the standalone production candidate. The 2026-08-20 migration rerun described above revalidated this exact set; documentation, repository metadata, and tests may have separate hashes.

## Safety evidence

- Unity received only an external copy; no command line contained the original project path.
- Base-copy fingerprint equaled the source fingerprint before every run.
- Original copy-set status was `UNCHANGED` after every run.
- Acceptance fixtures intentionally had no `.git`; Git metadata status was consistently `NOT_PRESENT` and unchanged. Separate Doctor/Baseline regression suites cover in-project Git mutation classification.
- Job Object creation, kill-on-close configuration, assignment, and zero-active-process accounting were required.
- An unrelated user-opened Unity project was safely distinguished by exact `-projectPath`; it was neither stopped nor modified.
- Scenario manifests and compatibility entries were constrained to exact required property sets, duplicate receipt IDs were rejected, and the scenario bundle hash was rechecked immediately before overlay copying.
- An exact-ProductVersion unsigned fake remained blocked by the production Authenticode gate and was executable only through the internal process-control test seam.
- No Unity, package, module, Test Framework, SDK, or certificate was installed by the verifier.

## Scope boundary

This approval proves only the recorded Editor PlayMode selection and source-only scenario contract. It does not approve Player Build, standalone or device players, OS input automation, networking, performance endurance, complete gameplay, subjective feel, visual quality, accessibility, or release readiness.
