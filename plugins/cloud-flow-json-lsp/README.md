# cloud-flow-json-lsp

A Claude Code plugin for **live schema validation of unpacked Power Automate solution cloud-flow
JSON** — the `Workflows/<name>-<guid>.json` files `pac solution unpack` produces (the flow
clientdata: a WDL `definition` plus its `connectionReferences`). Malformed structure shows up as
editor diagnostics *before* `pac solution import`.

**See [`docs/guide.md`](docs/guide.md) for editing guidance.**

This is the **shape** layer. Cross-node semantics (`runAfter` targets a real sibling, `connectionName`
resolves, hard-coded env values) and the export/pack/import round-trip live in the
`power-automate-flow-dev` skill. See [`docs/guide.md`](docs/guide.md) for the split.

## The validation layer

**LSP (live)** — `vscode-json-language-server` (from `vscode-langservers-extracted`) pushes
diagnostics as you edit, using the bundled draft-07 wrapper schema. Wired for Claude Code (this
plugin's `.lsp.json`) and usable in VS Code (built-in JSON language features via `json.schemas`).

There is no separate CLI validator script: for headless/CI structure checks, PowerShell's built-in
`Test-Json -SchemaFile schemas/cloud-flow-clientdata.schema.json` validates against the same schema
the LSP loads.

## Install (Claude Code)

```
/plugin marketplace add Cordedmink2/dataverse-agent-plugins
/plugin install cloud-flow-json-lsp@dataverse-agent-plugins
/cloud-flow-json-lsp:cloud-flow-json-lsp-setup
```

The setup command installs the pinned JSON language server (`npm ci`) and runs an end-to-end
self-check that drives the real server. It requires PowerShell 7+ (`pwsh`) and Node.js (for
`npm`/`node`). Then run `/reload-plugins` (or restart the session) so the LSP starts. The launcher
shim resolves the bundled schema at runtime, so nothing machine-specific is stamped into `.lsp.json`.

## Setup script directly (non-Claude consumers)

The slash command is a thin wrapper around one idempotent script:

```
pwsh scripts/Install-Plugin.ps1 [-UpdateVSCode]
```

- `-UpdateVSCode` also writes the `json.schemas` association into your VS Code user settings.

Run this one script rather than the individual `Install-*` scripts — a partial manual setup can
leave `node_modules/` or the schema missing, so the launcher shim throws at startup instead of
validating silently against nothing.

## What's inside

| Path | Purpose |
|------|---------|
| `SKILL.md` | Tiny no-description setup skill (runs `Install-Plugin.ps1`) |
| `scripts/Install-Plugin.ps1` | One-shot setup: server install + self-check |
| `scripts/Install-JsonLanguageServer.ps1` | `npm ci` the pinned JSON language server into `node_modules/` |
| `scripts/lsp-launch.mjs` | Launcher shim — spawns the JSON server and injects the bundled schema association at runtime |
| `scripts/Set-LspSchemaPaths.ps1` | Write the `json.schemas` association into VS Code user settings (`-UpdateVSCode`; Claude Code uses the shim instead) |
| `scripts/lsp-smoke.mjs` | End-to-end LSP health check (drives the server, asserts the schema fires) |
| `.lsp.json` | Launches the JSON server via the shim, which resolves the bundled schema at runtime — no stamped path |
| `package.json` / `package-lock.json` | Pin the JSON language server version |
| `schemas/cloud-flow-clientdata.schema.json` | The bundled draft-07 wrapper schema |
| `schemas/SOURCE.md` | What the schema validates, what it deliberately doesn't, how to refresh |
| `tests/` | Pester suite (config parity + fixture validation) + valid/invalid fixtures |
| `docs/` | Guides for Codex, VS Code-only, and debugging |

The JSON language server (`node_modules/`) is **installed at setup, not shipped**. The schema is
hand-maintained and committed.

## Updating

```
/plugin marketplace update dataverse-agent-plugins
/plugin update cloud-flow-json-lsp@dataverse-agent-plugins
/cloud-flow-json-lsp:cloud-flow-json-lsp-setup
```

The launcher shim resolves the bundled schema at runtime, so `.lsp.json` is portable — you do
**not** need to re-run setup after a plugin update or a repo move. Re-run it only when an update
bumps the pinned server version and you need the new `node_modules/` installed.

## Other consumers

- **Codex / any non-Claude agent** — see [`docs/codex.md`](docs/codex.md).
- **VS Code only (no agent)** — see [`docs/vscode.md`](docs/vscode.md).
- **CI / pre-commit** — validate structure with `Test-Json`:
  `Get-Content <flow>.json -Raw | Test-Json -SchemaFile schemas/cloud-flow-clientdata.schema.json`.

Something not working? [`docs/debugging.md`](docs/debugging.md).

## Known caveats

- **The wrapper is loose on action inputs by design** — `OpenApiConnection` connector actions aren't
  in Microsoft's public Logic Apps schema, so a strict `$ref` would produce more false positives than
  real findings. Structure is validated; `pac solution check` / a successful import is authoritative.
- **`${CLAUDE_PLUGIN_ROOT}` is only substituted in `.lsp.json` `command`/`args`**, not in nested
  `settings` — which is why the launcher shim (`scripts/lsp-launch.mjs`), handed the plugin root
  as an argv, injects the schema association at runtime instead of `.lsp.json` carrying it.

## License

MIT (see the repo root `LICENSE`). The bundled schema is original to this repo. The JSON language
server is installed from npm at setup and remains under its own license.

See [`docs/guide.md`](docs/guide.md) for the shape-vs-semantics layering and how this plugin pairs
with the `power-automate-flow-dev` skill.
