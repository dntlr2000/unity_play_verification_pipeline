# Standalone architecture

## Dependency direction

~~~text
public PowerShell entrypoint
├─ Play-only core
├─ Test Framework provenance and package-tree identity
├─ vendored Doctor scanner 0.2.1
│  └─ vendored copy-set fingerprint helper
├─ vendored exact-Unity resolution and trusted subprocess helper
├─ vendored Windows Job Object controller
├─ vendored path budget
├─ vendored Git metadata integrity
├─ compatibility registry schema 1.2.0
└─ scenario harness and template
~~~

There is no runtime edge to `unity_agent_pipeline`, its Doctor/Baseline Skill directories, a sibling repository or a developer-specific absolute path.

The three original schema `1.0.0` documents and compatibility schema `1.1.0` retain their published `$id` URLs and bytes. Source-specific Editor binding was added as `unity-play-compatibility-1.2.0.schema.json`; neither prior compatibility schema was rewritten. The local validator never performs network resolution, and production execution does not load schema URLs; they are identifiers, not runtime dependencies.

## Why runtime modules live inside the Skill

The installer creates one verified filesystem link, preferring a symbolic link and using a local junction only when Windows denies symbolic-link privilege:

`$HOME\.agents\skills\unity-play-verification`

PowerShell can be launched through that link. Keeping every production dependency below the linked directory prevents execution from depending on how the host resolves `$PSScriptRoot` for symbolic links. The top-level `modules` directory therefore stores provenance rather than a second executable copy.

## Isolation flow

1. Normalize and safety-check the requested Unity project and external artifact root.
2. Capture copy-set and Git metadata snapshots.
3. Run the bundled Doctor scanner and verify schema `1.1.0`, scanner `0.2.1` and its fingerprint.
4. Validate the exact Test Framework declaration, approved registry or Editor-builtin lock source, optional registry origin, and scoped-registry routing before Unity.
5. Resolve the exact declared Unity executable and require its ProductVersion, Unity Technologies signature, and SHA-256 to match the source-specific approved pair.
6. Copy only the Doctor copy-set to the external session directory and prove the copied fingerprint.
7. Optionally validate and inject a source-only ScenarioBundle into the reserved isolated path.
8. Run Unity under a kill-on-close Job Object.
9. Re-read isolated post-run provenance, locate exactly one resolved Test Framework package, and require two identical deterministic tree snapshots matching the approved SHA-256.
10. Combine NUnit XML, Editor.log, exit/process evidence and optional receipt/captures.
11. Re-check original copy-set and Git metadata before writing the final external result.

The original project is never passed to Unity and no artifact is written inside it.

## Threat boundary

Isolation protects the original-project workflow and verdict evidence; it is not a security sandbox. Unity project code and scenario C# execute with the current user's privileges. A fully malicious project can attempt same-user filesystem or artifact changes, and this pipeline does not claim OS-level containment or tamper-proof storage. Post-run provenance and package hashing prevent incomplete or substituted toolchain evidence from being promoted, but they do not prevent untrusted code from executing before the post-run check. Use the pipeline only with reviewed local project and scenario source.
