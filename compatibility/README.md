# Compatibility registry

The runtime registry is kept inside the installable Skill at:

`skills/codex/unity-play-verification/config/unity-play-compatibility.json`

Its active contract is `schemas/unity-play-compatibility-1.2.0.schema.json`. The published `1.0.0` and `1.1.0` schemas remain immutable for historical consumers. A pair is executable only when the exact Unity version, Unity executable SHA-256, resolved Test Framework version, source kind, and package tree match an `APPROVED` entry backed by the acceptance evidence named in that entry.

Every 1.2.0 entry pins `allowedSourceKind`, the signed Unity executable SHA-256, a deterministic package-tree SHA-256, and the canonicalization version. Registry entries additionally pin `https://packages.unity.com`; Editor-builtin entries require a null registry origin and no lock URL. Runtime preflight rejects local, embedded, git, tarball, ambiguous, cross-source, and intercepting scoped-registry evidence before Unity. After Unity exits, the isolated lock provenance and exactly one resolved package tree must still match the entry.

The current registry approves `2022.3.62f3 + 1.1.33` from Unity's registry and the Editor-builtin `6000.0.69f1 + 1.6.0` and `6000.5.3f1 + 1.7.0` pairs. Builtin approval never represents those packages as registry content; it binds each package hash to the exact separately approved signed Editor binary.

Adding a pair requires parser fixtures and a signed-Unity acceptance run. Near-version substitution, Unity Hub launch, installation and automatic update remain forbidden.
