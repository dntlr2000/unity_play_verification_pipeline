# Compatibility registry

The runtime registry is kept inside the installable Skill at:

`skills/codex/unity-play-verification/config/unity-play-compatibility.json`

Its contract is `schemas/unity-play-compatibility-1.0.0.schema.json`. A pair is executable only when the exact Unity version and resolved Test Framework version match an `APPROVED` entry backed by the acceptance evidence named in that entry.

Adding a pair requires parser fixtures and a signed-Unity acceptance run. Near-version substitution, Unity Hub launch, installation and automatic update remain forbidden.
