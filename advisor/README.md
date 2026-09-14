# advisor package

Public API:

- `get_settings()` reports the effective OpenAI-compatible endpoint/model and
  whether a credential is available, never the credential itself.
- `configure(base_url, model)` opens the Windows credential dialog and persists
  the API key only as current-user DPAPI ciphertext under LocalAppData.
- `analyze(root, question, allow_send)` requires explicit context consent, sends
  at most 32 KiB from fixed README/manifest names, and returns validated response
  metadata plus the model answer without executing it.
- `choose_candidate(...)` may select only an existing zero-based candidate
  index and returns `None` for malformed or out-of-range model output.
- `propose_deployment_plan(root, goal, allow_send)` generates a typed,
  README-backed proposal but does not execute or expose its steps for execution.
  Render `proposal.to_json()` for review; it includes the canonical bound root,
  exact program/argv, purposes, evidence, and the un-sandboxed-code warning.
- `authorize_deployment_plan(proposal, root, allow_execute)` rechecks the
  canonical root and releases `Array[DeploymentStep]` only after explicit
  consent. `LEARN` and `IGNORE` proposals can be reviewed but not authorized.

Deployment plans contain no command-line string or shell interpreter. Every
argv sequence must occur verbatim in a supported README, the work directory is
fixed to the canonical repository root, and the validator rejects unknown or
interactive operations, shell operators, credentials, host/global paths,
destructive lifecycle commands, and privileged/container-mount flags.

Environment values override persisted endpoint/model settings:
`REPOWAYFINDER_AI_BASE_URL`, `REPOWAYFINDER_AI_MODEL`, and
`REPOWAYFINDER_AI_API_KEY`. `OPENROUTER_API_KEY` and `DEEPSEEK_API_KEY` are
accepted as credential compatibility fallbacks. Custom endpoints must be HTTPS
and credential-free.

Re-running secure configuration atomically replaces only this app-owned
credential record; no plaintext backup or temporary key file is created.
