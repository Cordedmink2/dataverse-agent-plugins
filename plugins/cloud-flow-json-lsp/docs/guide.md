# cloud-flow-json-lsp — editing guide

> This is the manual replacement for the old auto-loaded skill; the plugin no longer surfaces this automatically.

## Power Automate cloud-flow JSON (schema-validated)

A solution cloud flow, once `pac solution unpack`ed, is `Workflows/<name>-<guid>.json`: the flow's
**clientdata** — a Workflow Definition Language (WDL) `definition` plus its `connectionReferences`.
This plugin makes malformed edits to that file **surface as live LSP diagnostics** while you type,
instead of failing at `pac solution import`.

It is one layer of a two-layer story — do not confuse them:

| Layer | What it checks | Where |
|-------|----------------|-------|
| **Shape (this plugin)** | JSON well-formedness + the clientdata/WDL wrapper structure: `properties.definition` present, `definition` has `$schema`/`triggers`/`actions`, `runAfter` statuses are the WDL enum, validated recursively through Scope/If/Foreach/Switch. Live, in-editor. | `schemas/cloud-flow-clientdata.schema.json` via `vscode-json-language-server` (`.lsp.json`) |
| **Semantics (the `power-automate-flow-dev` skill)** | Cross-node rules JSON Schema *cannot* express: `runAfter` naming a real sibling, `connectionName` resolving to a declared connection reference, child-invoker connections, hard-coded environment values, condition rows. Plus the export → unpack → edit → pack → import → verify round-trip. | that skill's `flow-lint.ps1` |

**Rule of thumb:** the LSP catches "this isn't a well-formed flow file." `flow-lint.ps1` catches "this
is well-formed but will import Off / route to the wrong place." Run both before pack/import.

## Setup (once per machine)

The JSON language server is a Node package fetched via npm; it is not committed. Run:

```
/cloud-flow-json-lsp:cloud-flow-json-lsp-setup
```

or directly `pwsh "${CLAUDE_PLUGIN_ROOT}/scripts/Install-Plugin.ps1"`. That installs the pinned server
(`npm ci`) and runs an end-to-end self-check that drives the real server and confirms the schema
fires. The launcher shim (`scripts/lsp-launch.mjs`) resolves the bundled schema's absolute `file://`
URI at runtime, so nothing is stamped into `.lsp.json`. Then `/reload-plugins`.

## What attaches to what

The schema associates (see `.lsp.json`) with:

- `**/Workflows/*.json` and `**/Workflows/**/*.json` — unpacked solution cloud flows
- `**/*.flow.json` — a convenience convention for a standalone flow file

It deliberately does **not** claim every `*.json` in the workspace.

## Subagents / headless contexts

LSP diagnostics only auto-push in the **main interactive session**. A spawned subagent, a workflow
step, or any non-main-session context does NOT receive them. In those contexts validate structure
explicitly with PowerShell's built-in `Test-Json`:

```
Get-Content <flow>.json -Raw | Test-Json -SchemaFile "${CLAUDE_PLUGIN_ROOT}/schemas/cloud-flow-clientdata.schema.json"
```

(and run the `power-automate-flow-dev` skill's `flow-lint.ps1` for the semantic layer).

## Gotchas

- **The wrapper is intentionally loose on action inputs.** Power Automate connector actions
  (`OpenApiConnection`) are not in Microsoft's public Logic Apps schema, so a strict `$ref` would
  drown real errors in false positives. `inputs` is left untyped; structure is what's validated.
  `pac solution check` / a successful import remains the authoritative gate.
- **`${CLAUDE_PLUGIN_ROOT}` is not substituted** inside `.lsp.json` `initializationOptions`/`settings`
  — only in `command`/`args`. That's why the launcher shim (`scripts/lsp-launch.mjs`), handed the
  plugin root as an argv, injects the schema association at runtime, computing an absolute `file://`
  URI. `.lsp.json` carries no path, so it stays portable — no re-stamp is needed after a plugin
  update or a repo move.
- **The JSON server validates a document only after answering its `workspace/configuration` pull.**
  Claude Code and VS Code both handle that; a bare LSP client must too (see `scripts/lsp-smoke.mjs`
  for a reference client).
