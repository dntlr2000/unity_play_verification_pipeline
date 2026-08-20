# Vendored runtime dependencies

The installed `$unity-play-verification` Skill is intentionally self-contained. Runtime copies live below `skills/codex/unity-play-verification/scripts/vendor`; this file records their immutable source and update policy.

Source repository snapshot:

- source project: `unity_agent_pipeline`
- source commit: `5e95f9157e4716682c614d421fa9c3ebd7c837b5`
- Doctor component: `0.2.1`
- Doctor result schema: `1.1.0`
- Doctor scanner: `0.2.1`
- Baseline component supplying shared safety modules: `0.2.0`

| Vendored file | Purpose | Upstream SHA-256 | Vendored SHA-256 |
| --- | --- | --- | --- |
| `doctor/inspect-unity-project.ps1` | bundled read-only Doctor scanner | `aec20fbf43b00a0438158110088bf9ef656264b94e956a0901dfd7c80fb2d197` | `aec20fbf43b00a0438158110088bf9ef656264b94e956a0901dfd7c80fb2d197` |
| `doctor/lib/unity-project-fingerprint.ps1` | exact copy-set snapshot and stable fingerprint | `757a2bf5ef5a45e68bb6b71b766f0b31d7b5a77174b6985809f22fe8f0f69b0a` | `757a2bf5ef5a45e68bb6b71b766f0b31d7b5a77174b6985809f22fe8f0f69b0a` |
| `shared/unity-baseline-orchestration.ps1` | trusted PowerShell subprocess and exact Unity discovery | `1b0ddb5a60329300df0dc211b90b9cad3a75db12d7bc8b8b88584d844ac30984` | `395af0d5341da7c3b6405338b6842449c5c91e9ddf8261c4c52512af627e4c37` |
| `shared/unity-process-job.ps1` | kill-on-close Windows Job Object execution | `747d64f077c5bb1acfe744082898614ab6489cd4ffb66f8f6f311db635a0b72c` | `747d64f077c5bb1acfe744082898614ab6489cd4ffb66f8f6f311db635a0b72c` |
| `shared/git-metadata-integrity.ps1` | before/after Git metadata snapshot and assessment | `2feadfb3d199ffc4556e90b1a35036d11f1a70c7b5bbf1207ec3b4eaaa2bcb7d` | `2feadfb3d199ffc4556e90b1a35036d11f1a70c7b5bbf1207ec3b4eaaa2bcb7d` |
| `shared/unity-isolation-path-budget.ps1` | destination containment and Windows path budget | `4cac8265e1d7eb8eaf6719e1c0378700bfd623acc2a35f61680d53179cebc61f` | `24f9b9b10fa70ab66ed5a5a5ad19516d1ec4ccc5152a9f89a453e7d0ae246974` |
| `shared/json-schema-validator.ps1` | local Draft 2020-12 subset validation used by tests | `b21559e96b0bc0cc6680ad2278e7a4a696e0b97cc62b00421127fea6da30fa3e` | `b21559e96b0bc0cc6680ad2278e7a4a696e0b97cc62b00421127fea6da30fa3e` |

These files are pinned copies, not imports. The vendored files preserve the upstream text with repository line-ending normalization; both byte hashes are recorded so that provenance and installed bytes are independently verifiable. Runtime code must never locate the source repository, a sibling repository, or globally installed Doctor/Baseline Skills.

When updating a copy:

1. review the upstream diff and keep only modules required by Play Verification;
2. preserve PowerShell 5.1 compatibility and method-level comments;
3. update this source commit/version/hash table;
4. rerun all fixtures, installer checks and every approved signed-Unity pair;
5. update the public-safe acceptance record and compatibility registry together.

A future common-library extraction can replace vendoring, but creating a third repository is outside this migration.
