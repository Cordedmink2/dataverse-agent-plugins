# Debugging

## Setup fails

- **`npm not found` / `node not found`** — install Node.js (bundles npm) and re-run. The server is
  a Node package; there is no offline fallback binary.
- **`npm ci` error** — network unavailable or the registry is down. Retry; if the lockfile is out of
  sync with `package.json`, delete `node_modules/` and re-run (the installer falls back to
  `npm install` when there is no lockfile).
- **Self-check failed** — the LSP smoke test (`scripts/lsp-smoke.mjs`) drove the real server and a
  fixture behaved unexpectedly: almost always the schema and fixtures disagree after a schema edit.
  Run `node scripts/lsp-smoke.mjs` directly to see which case failed.

## No live diagnostics in Claude Code

1. Did setup run? The `.lsp.json` schema `url` must be an absolute `file://` URI that exists —
   committed state is a relative path on purpose and does nothing until stamped.
2. `${CLAUDE_PLUGIN_ROOT}` is only substituted in `.lsp.json` `command`/`args`, NOT in `settings` —
   that's why `Set-LspSchemaPaths.ps1` exists. Re-run it (or the whole setup) after moving the plugin.
3. Run `/reload-plugins` (or restart the session) after stamping.
4. The file must match an association glob: `**/Workflows/*.json`, `**/Workflows/**/*.json`, or
   `**/*.flow.json`. A flow JSON opened outside a `Workflows/` folder and not named `*.flow.json`
   gets no schema.
5. The server validates a document only after answering its `workspace/configuration` pull — Claude
   Code handles that; a bare LSP client must too (see `scripts/lsp-smoke.mjs`).
6. Subagents and headless runs NEVER get LSP pushes — that's by design; validate with `Test-Json`.

## After `/plugin update power-automate-cloud-flow@dataverse-agent-plugins`

Setup stamps a machine-absolute schema path into the **tracked** `.lsp.json` inside the marketplace
clone, so an update may conflict on that file or reset it to the committed relative path. Re-running
`/power-automate-cloud-flow:setup` after every plugin update is the documented fix — it re-installs
the pinned server and re-stamps the path.

Contributors working in a clone: the installer dirties `.lsp.json` — don't commit the machine path.
`git update-index --skip-worktree plugins/power-automate-cloud-flow/.lsp.json` keeps it out of your
commits.

## No diagnostics in VS Code

- Did you run setup with `-UpdateVSCode`, then restart VS Code?
- Check File > Preferences > Settings (JSON) > `json.schemas` — the `url` is an absolute `file://`
  URI and the file must exist.
- A JSONC settings file (comments) makes the updater refuse to write (see [vscode.md](vscode.md)).

## Validation "errors" that aren't structural

The wrapper deliberately does not type action `inputs` (connector shapes vary by `operationId` and
aren't in the public Logic Apps schema). So the LSP will NOT flag a wrong connector parameter — that
is expected. For those, and for cross-node semantics (`runAfter`/`connectionName` resolution,
hard-coded env values), use the `power-automate-flow-dev` skill's `flow-lint.ps1`.

## The final gate

`pac solution check` / a successful `pac solution import` is authoritative for a packaged flow. The
LSP and `Test-Json` exist so you rarely get that far with a malformed file.
