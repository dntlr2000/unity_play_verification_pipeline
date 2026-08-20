# Unity Agent Pipeline v0.6.0 release notes

Release contract status: **FINAL**

Release identifier: **`v0.6.0`**

Release date: **2026-08-19**

The authoritative publication state, when published, is the annotated `v0.6.0` Git tag and the GitHub Release that names the same tag. This document defines the immutable release contract and does not claim that publication was performed by the implementation task.

## Components

| Component | Version | Contract |
| --- | --- | --- |
| `$unity-project-doctor` | `0.2.1` | scanner schema `1.1.0` and deterministic copy-set fingerprint |
| `$unity-baseline-verification` | `0.2.0` | one-command isolated script-compilation baseline |
| `$unity-play-verification` | `0.2.0` | existing PlayMode tests plus source-only isolated scenario overlay |
| Play result schema | `1.0.0` | fixed top-level evidence areas and four final statuses |
| Scenario manifest schema | `1.0.0` | IDs, filter, timeout, Scenes, assertions, captures, graphics requirement |
| Compatibility registry schema | `1.0.0` | exact Unity/Test Framework approvals |

The repository version is `0.6.0`. Component versions remain independent.

The concurrently developed `$unity-editmode-verification` `0.1.0` component remains Unreleased and is not part of this release contract.

## Highlights

- Adds a validated external scenario bundle containing only `manifest.json`, `.asmdef`, and `.cs` files.
- Injects the bundled harness and scenario only after the base isolated copy matches the original fingerprint.
- Provides Scene loading, frame waits, bounded conditions, named assertions, and 1280×720 RenderTexture PNG capture.
- Requires receipt scenario ID, Scene set, assertion set, capture set, and verifier-owned capture paths to match the manifest exactly.
- Hashes every scenario file, harness tree, receipt, NUnit XML, logs, Unity executable, and requested PNG.
- Keeps screenshot pixels outside automatic pass/fail decisions.
- Allows unrelated Unity projects only after exact command-line association; an open source project or ambiguous live process still blocks.

## Real-Unity approval

Acceptance status: **APPROVED — SELECTED EDITOR PLAYMODE TESTS AND SOURCE-ONLY SCENARIOS ONLY**

The production entrypoint completed an 18-case matrix across the following exact pairs:

- Unity `2022.3.62f3` + Test Framework `1.1.33`
- Unity `6000.0.69f1` + Test Framework `1.6.0`
- Unity `6000.5.3f1` + Test Framework `1.7.0`

For each pair, a multi-frame pass returned `PLAY_VERIFIED`, a deliberate failure returned `PLAY_FAILED`, Skip/Inconclusive/zero-selection returned `VERIFICATION_BLOCKED`, and the scenario receipt plus PNG returned `PLAY_VERIFIED`. Original copy-set integrity remained `UNCHANGED` in every case. The [public-safe acceptance record](../validation/unity-play-verification-real-unity-acceptance.md) contains the matrix and sealed hashes.

## Safety and scope

- The original project is never passed to Unity and receives no overlay, generated metadata, log, test, package, or setting.
- Artifacts and the isolated project are preserved outside the original project and are not automatically removed.
- Unity Hub, installers, package installers, OS input automation, arbitrary Unity arguments, remote code, precompiled scenario binaries, native plugins, reparse points, and path escapes are prohibited.
- Player Build, actual devices, standalone input backends, network multi-client tests, performance endurance, complete gameplay, subjective feel, visual quality, and release readiness remain outside the contract.

## Release invariants

- The tagged commit contains repository `VERSION` `0.6.0`, Play Skill `VERSION` `0.2.0`, Doctor `0.2.1`, and Baseline `0.2.0`.
- The three approved compatibility entries reference the public-safe acceptance record.
- Production scripts, harness, schemas, registry, final-status precedence, and explicit invocation policy match the accepted implementation hashes.
- Doctor, Baseline, Unreleased EditMode compatibility, and Play regression suites pass against the exact release commit.
- Every PowerShell file parses without errors, `git diff --check` passes, and tests leave the checkout unchanged.
- Four Windows workflows succeed before tagging; the real-Unity matrix remains a manually controlled release gate.
- The annotated tag is not moved or replaced, and the matching GitHub Release does not widen the approval claim.

This file records invariant release requirements, not a live publication checklist, so it remains valid before and after publication.
