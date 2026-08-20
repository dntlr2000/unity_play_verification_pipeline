# Standalone architecture

## Dependency direction

~~~text
public PowerShell entrypoint
├─ Play-only core
├─ vendored Doctor scanner 0.2.1
│  └─ vendored copy-set fingerprint helper
├─ vendored exact-Unity resolution and trusted subprocess helper
├─ vendored Windows Job Object controller
├─ vendored path budget
├─ vendored Git metadata integrity
├─ compatibility registry
└─ scenario harness and template
~~~

There is no runtime edge to `unity_agent_pipeline`, its Doctor/Baseline Skill directories, a sibling repository or a developer-specific absolute path.

The three frozen schema `1.0.0` documents retain their original published `$id` URLs so their public identity does not change during repository extraction. The local validator never performs network resolution, and production execution does not load those URLs; they are identifiers, not runtime dependencies.

## Why runtime modules live inside the Skill

The installer creates one verified filesystem link, preferring a symbolic link and using a local junction only when Windows denies symbolic-link privilege:

`$HOME\.agents\skills\unity-play-verification`

PowerShell can be launched through that link. Keeping every production dependency below the linked directory prevents execution from depending on how the host resolves `$PSScriptRoot` for symbolic links. The top-level `modules` directory therefore stores provenance rather than a second executable copy.

## Isolation flow

1. Normalize and safety-check the requested Unity project and external artifact root.
2. Capture copy-set and Git metadata snapshots.
3. Run the bundled Doctor scanner and verify schema `1.1.0`, scanner `0.2.1` and its fingerprint.
4. Resolve the exact declared signed Unity executable and approved Test Framework pair.
5. Copy only the Doctor copy-set to the external session directory and prove the copied fingerprint.
6. Optionally validate and inject a source-only ScenarioBundle into the reserved isolated path.
7. Run Unity under a kill-on-close Job Object.
8. combine NUnit XML, Editor.log, exit/process evidence and optional receipt/captures.
9. re-check original copy-set and Git metadata before writing the final external result.

The original project is never passed to Unity and no artifact is written inside it.
