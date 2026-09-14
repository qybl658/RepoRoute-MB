# RepoRoute MB

RepoRoute MB is a MoonBit library and CLI that discovers explicit repository launch entrypoints without executing project code. Every candidate includes its source file, line, prerequisite, reason, and confidence so humans and coding agents can distinguish evidence from guesses.

## Why

Unfamiliar repositories often expose several plausible launch routes through package scripts, language manifests, Dockerfiles, and Compose files. Returning one unexplained command hides conflicts and makes automated hand-off unsafe. RepoRoute MB emits a deterministic run contract and leaves goal/environment selection to its caller.

## Supported evidence

| Ecosystem | Evidence | Candidate |
|---|---|---|
| Node.js | `package.json` scripts plus lockfile | `npm`, `pnpm`, `yarn`, or `bun` script |
| Python | `[project.scripts]` in `pyproject.toml` | installed console script |
| Rust | `[package]` in `Cargo.toml` | `cargo run` |
| MoonBit | `moon.mod` plus `cmd/main/moon.pkg` | `moon run cmd/main` |
| Docker | `Dockerfile` and `CMD`/`ENTRYPOINT` | build and run candidate |
| Compose | `compose.yaml` or `docker-compose.yml` | `docker compose up --build` |

The first release intentionally scans known root-level manifests only. It does not execute arbitrary code or claim to understand free-form README instructions.

## Run

Install the [MoonBit toolchain](https://www.moonbitlang.com/download/), then:

```powershell
moon update
moon run cmd/main -- C:\path\to\repository
moon run cmd/main -- C:\path\to\repository --format markdown
```

## Library

The pure `scan(root, files)` API accepts an array of `SourceFile` values. This keeps parsers deterministic and easy to test; filesystem access stays in the CLI adapter.
Input file paths accept both Windows and POSIX separators and are normalized in emitted evidence.

## Verify

Every push and pull request runs the same checks on both Windows and Linux through GitHub Actions.

```powershell
moon fmt --check
moon check --deny-warn
moon test --deny-warn
moon run cmd/main -- .
```

Tests cover lockfile selection, source line evidence, PEP 621 scripts, invalid JSON, mixed ecosystems, Markdown output, and empty repositories.

For a reproducible mixed-project demonstration:

```powershell
moon run cmd/main -- examples/mixed-app
```

The machine-readable output contract is documented by [schema/run-contract.schema.json](schema/run-contract.schema.json). A concise product overview is available in [docs/overview.md](docs/overview.md).

## Project status

RepoRoute MB is under active development. Current work focuses on stable output contracts, broader reproducible fixtures, and evidence-backed compatibility checks. See [ROADMAP.md](ROADMAP.md).

## License

Apache-2.0. See [LICENSE](LICENSE).
