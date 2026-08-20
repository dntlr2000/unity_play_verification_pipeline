# Repository instructions

- Keep the pipeline standalone: production code must not load files from sibling repositories or sibling installed Skills.
- Add a short functional comment immediately above every new or materially changed PowerShell function and C# method.
- Keep all runtime artifacts and Unity project copies outside this repository and outside the source Unity project.
- Preserve the public PowerShell parameters, result schema, final-status names and verification scopes unless an explicit versioned contract change is requested.
- Do not add an approved Unity/Test Framework pair without fixtures and signed-Unity acceptance evidence.
