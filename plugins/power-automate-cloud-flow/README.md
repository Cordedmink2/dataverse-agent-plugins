# power-automate-cloud-flow

A Claude Code plugin for **live schema validation of unpacked Power Automate solution cloud-flow
JSON** — the `Workflows/<name>-<guid>.json` files `pac solution unpack` produces (the flow
clientdata: a WDL `definition` plus its `connectionReferences`). Malformed structure shows up as
editor diagnostics *before* `pac solution import`.

This is the **shape** layer. Cross-node semantics (`runAfter` targets a real sibling, `connectionName`
resolves, hard-coded env values) and the export/pack/import round-trip live in the
`power-automate-flow-dev` skill. See `SKILL.md` for the split.

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
/plugin install power-automate-cloud-flow@dataverse-agent-plugins
/power-automate-cloud-flow:setup
```

The setup command installs the pinned JSON language server (`npm ci`), stamps this machine's
absolute schema path into `.lsp.json`, and runs an end-to-end self-check that drives the real server.
It requires PowerShell 7+ (`pwsh`) and Node.js (for `npm`/`node`). Then run `/reload-plugins` (or
restart the session) so the LSP starts with the stamped path.

## Setup script directly (non-Claude consumers)

The slash command is a thin wrapper around one idempotent script:

```
pwsh scripts/Install-Plugin.ps1 [-UpdateVSCode]
```

- `-UpdateVSCode` also writes the `json.schemas` association into your VS Code user settings.

Run this one script rather than the individual `Install-*`/`Set-*` scripts — a partial manual setup
can leave a running server pointing at a broken relative schema path.

## What's inside

| Path | Purpose |
|------|---------|
| `SKILL.md` | The skill: the shape-vs-semantics split, what attaches, gotchas |
| `commands/setup.md` | The `/power-automate-cloud-flow:setup` slash command |
| `scripts/Install-Plugin.ps1` | One-shot setup: server install + path stamping + self-check |
| `scripts/Install-JsonLanguageServer.ps1` | `npm ci` the pinned JSON language server into `node_modules/` |
| `scripts/Set-LspSchemaPaths.ps1` | Stamp this machine's absolute schema `file://` URI into `.lsp.json` (+ VS Code) |
| `scripts/lsp-smoke.mjs` | End-to-end LSP health check (drives the server, asserts the schema fires) |
| `.lsp.json` | Registers the JSON server with Claude Code, with the flow `json.schemas` association |
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
/plugin update power-automate-cloud-flow@dataverse-agent-plugins
/power-automate-cloud-flow:setup
```

Re-run setup after every update — it re-installs the pinned server and re-stamps the schema path (see
`docs/debugging.md` for why).

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
  `settings` — hence the absolute-path fixup script.

## License

MIT (see the repo root `LICENSE`). The bundled schema is original to this repo. The JSON language
server is installed from npm at setup and remains under its own license.

See `SKILL.md` for the shape-vs-semantics layering and how this plugin pairs with the
`power-automate-flow-dev` skill.
