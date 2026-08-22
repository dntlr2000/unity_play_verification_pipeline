---
name: unity-play-verification
description: "Run approved Unity Editor PlayMode tests or a validated source-only scenario bundle against an isolated copy of the Unity project in the current working directory. Use only when the user explicitly invokes $unity-play-verification; never infer it from an ordinary Unity testing request."
---

# Unity Play Verification

Use the bundled PowerShell entrypoint as the sole source of dynamic Play verification truth. The verifier creates an external project copy, starts only an exact signed and approved Unity editor, requires the compatibility entry's approved source-specific Test Framework provenance plus the approved resolved package tree, parses NUnit XML and Editor.log together, and proves the original project stayed unchanged.

## Invocation policy

- Require the literal name `$unity-play-verification` in the user's request.
- Never run from implicit intent or as an automatic continuation of Doctor or Baseline.
- Never invoke `$unity-baseline-verification` or reinterpret a Baseline receipt as Play evidence.
- Never install Unity, Unity Hub, packages, modules, SDKs, or test frameworks.
- Never open the original project in Unity or add tests, packages, settings, logs, or generated files to it.

## Project-test mode

From the exact Unity project root, run:

~~~powershell
$runner = Join-Path $HOME ".agents\skills\unity-play-verification\scripts\invoke-unity-play-verification.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -ProjectRoot (Get-Location).Path
~~~

Optional `-TestFilter`, `-TestCategory`, and `-AssemblyNames` values are passed as individual Unity Test Framework arguments. Do not invent a filter when the user asks for all PlayMode tests.

## Isolated scenario mode

Use scenario mode only when the user requests project-specific input, interaction, UI, or state validation and an external source-only bundle has been prepared from the template under `templates/minimal-scenario`.

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner `
    -ProjectRoot (Get-Location).Path `
    -ScenarioBundlePath "E:\CodexValidation\scenario-bundle"
~~~

- Keep the scenario bundle outside the Unity project.
- Include only `manifest.json`, `.asmdef`, and `.cs` source files.
- Implement `IPlayVerificationScenario.Execute(PlayVerificationContext)` and invoke it through `PlayVerificationScenarioRunner.Run`.
- Use the new Input System's test APIs only when the target project already depends on that package.
- For legacy input, call an existing project test seam or public gameplay API; never automate operating-system keyboard, mouse, focus, or screen coordinates.
- Treat screenshots as retained evidence only. Do not change the machine-readable final status from visual interpretation.

## Trust boundary

- Accept only the source kind recorded by the exact compatibility entry: official Unity registry or Editor-builtin bound to the approved Unity.exe SHA-256. Treat local, embedded, git, tarball, cross-source, ambiguous, custom-scoped-registry, Editor-hash mismatch, and package-tree mismatch results as blockers.
- Source-only is not a security sandbox. Project and scenario C# run with Unity's current-user privileges.
- Use only reviewed local project and scenario source. Do not claim containment of a fully malicious project or tamper-proof same-user artifacts.
- A post-run package hash protects the verdict from promotion; it does not prevent project code from executing before that check.

## Result handling

- Accept exactly one JSON document from stdout and preserve its `schemaVersion`, evidence, warnings, failures, blockers, verification scopes, and `finalStatus`.
- Do not promote `VERIFICATION_BLOCKED`, `PLAY_FAILED`, or `ORIGINAL_PROJECT_CHANGED`.
- `PLAY_VERIFIED` means only that the selected Editor PlayMode tests or named scenario passed under the recorded exact compatibility pair.
- Never claim Player Build, device input, complete gameplay, subjective quality, performance endurance, or release readiness.
- Report the external artifact directory and concise test counts, then end with the exact JSON `finalStatus`.

## Final-status meanings

| finalStatus | Meaning |
| --- | --- |
| `PLAY_VERIFIED` | Every selected test and required scenario artifact has complete positive evidence |
| `PLAY_FAILED` | A complete run contains a concrete compilation, test, crash, or scenario failure |
| `VERIFICATION_BLOCKED` | Safety, compatibility, completeness, timeout, skip, or evidence requirements were not met |
| `ORIGINAL_PROJECT_CHANGED` | Original project content or disallowed Git metadata changed during the run |
