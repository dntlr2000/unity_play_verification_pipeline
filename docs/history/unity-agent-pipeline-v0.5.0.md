# Unity Agent Pipeline v0.5.0 release notes

Release contract status: **FINAL**

Release identifier: **`v0.5.0`**

Release date: **2026-08-19**

This file records invariant release requirements for the v0.1 Play verification stage. The authoritative publication state, when published, is the annotated `v0.5.0` tag and matching GitHub Release.

## Components

| Component | Version | Contract |
| --- | --- | --- |
| `$unity-project-doctor` | `0.2.1` | static scanner schema `1.1.0` |
| `$unity-baseline-verification` | `0.2.0` | isolated script-compilation baseline |
| `$unity-play-verification` | `0.1.0` | existing Editor PlayMode tests in an isolated copy |
| Play result schema | `1.0.0` | four final statuses and separated verification scopes |

The concurrently developed `$unity-editmode-verification` `0.1.0` component remains Unreleased and is not part of this release contract.

## v0.1 scope

- Adds the Play explicit-only Skill without changing Doctor, Baseline, or the separate Unreleased EditMode result contracts.
- Runs existing project PlayMode tests with `-runTests -batchmode -testPlatform PlayMode`.
- Uses a fixed argument allowlist and omits `-nographics`, `-quit`, and `-runSynchronously`.
- Requires exact signed Unity and an approved Unity/Test Framework registry pair.
- Parses NUnit XML, Editor.log, exit code, Job Object shutdown, source fingerprint, and Git metadata together.
- Rejects zero tests, Skip, Inconclusive, missing/corrupt evidence, timeout, and unsafe preflight conditions.
- Limits `PLAY_VERIFIED` to the selected Editor PlayMode tests.

## Release invariants

- Repository `VERSION` for this stage is `0.5.0`; Play Skill `VERSION` is `0.1.0`.
- Doctor and Baseline component versions and schemas remain unchanged.
- The production entrypoint blocks unsigned fake Unity; fixture execution is confined to parser/process seams.
- Doctor, Baseline, and Play static suites pass; every PowerShell file parses; `git diff --check` passes; the checkout remains unchanged after tests.
- Both pre-existing Skills and the new Play Skill keep `allow_implicit_invocation: false`.

This stage is preserved as the v0.1 contract boundary. Repository v0.6.0 supersedes it by adding the separately approved scenario overlay without widening v0.1 claims.
