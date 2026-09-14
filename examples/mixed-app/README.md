# Mixed fixture

This fixture intentionally exposes two package scripts and one Docker route. RepoRoute MB must preserve all three candidates and report the conflict instead of silently selecting one.

Run from the repository root:

```powershell
moon run cmd/main -- examples/mixed-app
moon run cmd/main -- examples/mixed-app --format markdown
```
