# power-automate-cloud-flow — plugin design (retrospective)

**Date:** 2026-07-21
**Status:** Retrospective spec — documents shipped v1.0.0 (commit `fff8ff0`). Written after the fact to
capture intended scope and to audit the build for sprawl.
**Author:** Connor Parsons

## Summary

`power-automate-cloud-flow` is the second plugin in the `dataverse-agent-plugins` marketplace. It
provides **live JSON-schema validation of unpacked Power Automate solution cloud-flow files** — the
`Workflows/<name>-<guid>.json` that `pac solution unpack` writes. That file is the flow's
*clientdata*: a Workflow Definition Language (WDL) `definition` plus its `connectionReferences`.
Malformed structure surfaces as editor diagnostics **while you type**, instead of failing later at
`pac solution import`.

It is deliberately **one layer of a two-layer story**:

- **Shape (this plugin):** JSON well-formedness and the clientdata/WDL wrapper structure —
  `properties.definition` present; `definition` has `$schema`/`triggers`/`actions`; `runAfter`
  statuses are the WDL enum. Expressible in JSON Schema, enforced live via an LSP.
- **Semantics (the `power-automate-flow-dev` skill):** cross-node rules JSON Schema *cannot* express
  (`runAfter` naming a real sibling, `connectionName` resolving, hard-coded env values) plus the
  export → pack → import → verify round-trip. Enforced by that skill's `flow-lint.ps1`.

The scope boundary between these two layers is the single most important design decision, and it is
what keeps the plugin small. This plugin never tries to do semantics.

## Decisions (reconstructed from the build)

| Question | Decision |
|---|---|
| What is validated | JSON **shape** of unpacked cloud-flow clientdata only — not connector semantics, not the round-trip |
| Validation mechanism (live) | `vscode-json-language-server` (from `vscode-langservers-extracted`, pinned `4.10.0`) via `.lsp.json` |
| Validation mechanism (headless/CI) | PowerShell built-in `Test-Json -SchemaFile <schema>` against the **same** bundled schema — no bespoke CLI validator |
| Schema authorship | Hand-maintained draft-07 wrapper, **committed** to the repo (original work; contrast the Dataverse XSDs which are Microsoft-copyrighted and downloaded) |
| Action `inputs` strictness | **Left untyped on purpose** — `OpenApiConnection` connector actions aren't in the public Logic Apps schema, so a strict `$ref` would drown real errors in false positives |
| File association | `**/Workflows/*.json`, `**/Workflows/**/*.json`, `**/*.flow.json` only — deliberately **not** every `*.json` |
| Language server distribution | Installed at setup via `npm ci` (pinned lockfile), **not committed** — `node_modules/` is gitignored |
| Setup shape | One idempotent entry script (`Install-Plugin.ps1`) → install server → stamp path → end-to-end self-check |
| Why a path-stamping step exists | `${CLAUDE_PLUGIN_ROOT}` is substituted in `.lsp.json` `command`/`args` but **not** in nested `settings`, so the schema `url` must be stamped to a machine-absolute `file://` URI |
| Authoritative gate | `pac solution check` / a successful `pac solution import` — the plugin exists so you rarely reach that with a malformed file |
| Platform | PowerShell 7+ (`pwsh`) cross-platform; Node.js for the server |

## Architecture

### Components

| Unit | Single purpose |
|------|----------------|
| `schemas/cloud-flow-clientdata.schema.json` | The draft-07 wrapper schema — the one source of validation truth, loaded by both the LSP and `Test-Json` |
| `.lsp.json` | Registers the JSON server with Claude Code and carries the `json.schemas` file-match association |
| `scripts/Install-Plugin.ps1` | One-shot orchestrator: install → stamp → self-check (3 steps) |
| `scripts/Install-JsonLanguageServer.ps1` | `npm ci` the pinned server into `node_modules/`; idempotent, `-Force` to reinstall |
| `scripts/Set-LspSchemaPaths.ps1` | Stamp the machine-absolute `file://` schema URI into `.lsp.json` (and optionally VS Code settings) |
| `scripts/lsp-smoke.mjs` | End-to-end health check: drives the real server over both push and pull config-delivery models and asserts valid fixtures are clean / invalid fixtures flag |
| `commands/setup.md` | The `/power-automate-cloud-flow:setup` slash command — thin wrapper over `Install-Plugin.ps1` |
| `tests/LspConfig.Tests.ps1` | Pester guards: config parity (`.lsp.json` ↔ the script's source-of-truth globs, read via AST) + fixtures distinguish valid/invalid |
| `tests/fixtures/{valid,invalid}/` | Regression corpus for the schema |
| `SKILL.md` / `README.md` / `schemas/SOURCE.md` / `docs/*` | Skill entry point, human README, schema rationale, and consumer/debugging guides |

### Data flow

**Setup (once per machine, re-run after every update):**

```
/power-automate-cloud-flow:setup
  → Install-Plugin.ps1
      1. Install-JsonLanguageServer.ps1   (npm ci → node_modules/)
      2. Set-LspSchemaPaths.ps1           (stamp absolute file:// URI into .lsp.json)
      3. lsp-smoke.mjs                     (drive real server, assert schema fires; fail loud here)
  → /reload-plugins
```

**Validation (main interactive session):** edit `Workflows/*.json` → LSP pushes diagnostics live
against the stamped schema.

**Validation (subagent / headless / CI):** no LSP push by design →
`Get-Content <flow> -Raw | Test-Json -SchemaFile <schema>` against the same schema.

### Why the setup is a self-checking three-step, not a one-liner

The failure mode being defended against is a **running server pointing at a broken relative schema
path** — silent non-validation. The install/stamp/self-check sequence makes a broken install fail at
setup time (loud), consistent with the repo owner's "fail loud, don't mask" principle. The smoke test
running *both* push and pull config-delivery models hedges against Claude Code's under-documented
`workspace/configuration` behavior.

## Sprawl & quality assessment

The concern that prompted this spec was that the plugin might have been built without a design and
grown sprawl. Honest verdict: **the code is tight; the prose is redundant.**

### What is well-scoped (no action needed)

- **Single source of validation truth.** One schema serves both the live LSP and the headless
  `Test-Json` path. There is no second, drifting validator. This is the strongest design choice.
- **The shape/semantics boundary is explicit and consistently honored.** Nothing in this plugin
  attempts cross-node semantics; it points at `power-automate-flow-dev` for that. Scope creep is
  actively resisted.
- **Every script has one job**, and the entry script composes them. File count (~20) is proportionate
  to the job; no file is doing two unrelated things.
- **Tests guard the two things that actually rot:** config parity between `.lsp.json` and the stamping
  script's source-of-truth globs (via AST read, not execution — a genuinely careful touch), and that
  the schema still separates the valid/invalid corpus.
- **`node_modules/` is installed, not shipped;** the schema is committed. Correct call on both.

### Sprawl found: documentation redundancy (the real finding)

Three facts are each restated in four-to-six places:

| Repeated fact | Appears in |
|---|---|
| Shape-vs-semantics split / "use `flow-lint.ps1` for semantics" | `SKILL.md`, `README.md`, `SOURCE.md`, `docs/debugging.md`, `docs/codex.md`, `docs/vscode.md` |
| `${CLAUDE_PLUGIN_ROOT}` not substituted in `settings` → why stamping exists | `SKILL.md`, `README.md`, `Set-LspSchemaPaths.ps1` header, `docs/debugging.md` |
| "`inputs` left untyped on purpose (false positives)" | `SKILL.md`, `README.md`, `SOURCE.md`, `docs/debugging.md` |

Some repetition is legitimate — a debugging doc *should* restate a gotcha as a troubleshooting step,
and `SKILL.md` (agent-facing) vs `README.md` (human-facing) serve different readers. But the current
spread means a change to any of these three facts must be hand-propagated to 4–6 files, and drift is
likely. This is maintenance sprawl, not feature sprawl.

**Recommended (optional) cleanup:**
- Make `SKILL.md` the single canonical statement of the shape/semantics boundary and the two design
  caveats; have `README.md` and the `docs/*` files link to it rather than re-explain.
- Keep the troubleshooting *symptoms* in `docs/debugging.md` but point to the canonical *why*.

### Minor observations (not sprawl, noted for completeness)

- `.lsp.json` carries the `json` settings block **twice** (`initializationOptions.settings` and
  `settings`) to cover both config-delivery models. This is intentional and guarded by a parity test,
  but it is duplicated state — the smoke test's two-scenario design is what justifies keeping both.
- The stamping step dirties a **tracked** file (`.lsp.json`) with a machine path. This is documented
  (`docs/debugging.md` notes `git update-index --skip-worktree`), but it remains an inherent friction
  of the "substitute in `command`/`args` but not `settings`" limitation, not a defect in the plugin.

### Bottom line

No decomposition needed and no feature to cut. The plugin does one thing and its scope boundary is
sound. The only worthwhile follow-up is consolidating the repeated prose so the three load-bearing
facts live in one place each.
