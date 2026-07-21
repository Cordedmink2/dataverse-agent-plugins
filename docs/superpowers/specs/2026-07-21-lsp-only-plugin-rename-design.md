# LSP plugins: rename + tiny setup skill + no-restamp (XML keeps its validator) — design

Date: 2026-07-21

## Context

The `dataverse-agent-plugins` marketplace ships two plugins:
`dataverse-customization-xml` (a lemminx XML LSP for Dataverse customization XML, plus a standalone
`Validate-DataverseXml.ps1`) and `power-automate-cloud-flow` (a `vscode-json-language-server` JSON
LSP for unpacked cloud-flow clientdata). Each currently carries a large **auto-triggering** root
skill — a `SKILL.md` whose long `description` is full of trigger phrases so it activates on its own —
plus a `/<plugin>:setup` slash command that stamps a machine-local absolute schema path into
`.lsp.json` (needed because `${CLAUDE_PLUGIN_ROOT}` is not substituted inside `.lsp.json` `settings`).
That stamp must be re-run after every `/plugin update` or repo move.

The goal is that both plugins are **really good, well-tested, useful LSPs that are easy to set up and
update.** Concretely:

- Each plugin's shape is **an LSP server + one tiny, no-description setup skill.** The old
  auto-triggering skill and the setup slash command are removed; the domain guidance the skill
  carried is preserved as reference docs.
- **Eliminate the re-stamp step** so updates are effectively zero-touch.
- **Raise test coverage** so the LSP path is provably correct.
- Rename the plugins to names that say plainly what they are.

**The XML plugin keeps its existing `Validate-DataverseXml.ps1`** — the LSP structurally cannot do
what it does (validate in headless/subagent/CI contexts the LSP never reaches, and validate the pac
**wrapper files** — `<forms>`, `<visualization>` incl. escaped inner XML — by extracting the inner
fragment). It is kept scoped as the **non-LSP channel** with **no auto-hook**: the LSP owns
interactive validation, the validator owns CI/headless + wrapper files, so they never overlap or
disagree (both read the same schemas). A bespoke **flow** validator and any validation **hook** are
deliberately deferred (YAGNI) — see §10.

Outcome: two lean, well-tested LSP plugins, set up once by a manually-run skill, with no per-machine
path stamping to repeat on update, and no loss of the XML validator's unique capabilities.

## Decisions (locked with the user)

- **Names:** `dataverse-customization-xml` → `dataverse-xml-lsp`;
  `power-automate-cloud-flow` → `cloud-flow-json-lsp`. Asymmetry intentional (broad XSD-set LSP vs.
  single cloud-flow schema); a forced-symmetric `dataverse-json-lsp` was rejected as overpromising.
- **Scope = the bundled schemas.** Full scope retained — XML keeps the whole official XSD set (~10
  root types); JSON keeps its single self-contained cloud-flow wrapper.
- **Shape = LSP + setup skill.** Plus: the XML plugin **keeps** `Validate-DataverseXml.ps1` and its
  Pester test as the non-LSP channel. The flow plugin stays pure LSP (built-in `Test-Json` one-liner
  documented for ad-hoc headless checks). No flow validator, no hook, in this change.
- **No overlap.** No auto-hook. The LSP is not associated to the wrapper roots the validator owns
  (charts already excluded; ensure forms are validator-owned), so the LSP and validator never both
  claim a file and cannot disagree.
- **Setup skill shape:** keep `skills: ["./"]`; the root `SKILL.md` becomes a tiny skill named
  `<plugin>-setup` (`dataverse-xml-lsp-setup` / `cloud-flow-json-lsp-setup`) with **no `description`**
  — confirmed supported: it still loads and is invocable as `/<plugin>:<plugin>-setup`, and with no
  description Claude has nothing to auto-match, so it never auto-triggers.
- **No re-stamp:** resolve the schema path at LSP launch instead of stamping it. Build **Option 1
  (launcher shim)** first and test it; if it doesn't work properly, abandon it and build **Option 2
  (hosted schema URL)** instead (§4). Exactly one mechanism ships.
- **Guidance:** moved into a new `docs/guide.md` per plugin (not README, not deleted).
- **Setup slash command:** removed; the tiny skill is the sole setup entry point.
- **Old design specs under `docs/superpowers/specs/`:** old names updated throughout.
- **Execution/versioning:** clean rename via `git mv` (preserve history), bump both to `2.0.0`,
  CHANGELOG documents the breaking rename + restructure, work on a new branch off `main`.

## 1. End state (per plugin)

```
plugins/dataverse-xml-lsp/                 plugins/cloud-flow-json-lsp/
  .claude-plugin/plugin.json                 .claude-plugin/plugin.json
  .lsp.json  (launches via shim, §4)         .lsp.json  (launches via shim, §4)
  SKILL.md   ← tiny, NO description           SKILL.md   ← tiny, NO description
  (name: dataverse-xml-lsp-setup)             (name: cloud-flow-json-lsp-setup)
  scripts/Validate-DataverseXml.ps1  ← KEPT   scripts/  (lsp-smoke.mjs, install)
  scripts/  schemas/  tests/                  schemas/  tests/  package*.json
  docs/
    guide.md   ← NEW (moved guidance)
    codex.md  vscode.md  debugging.md
  REMOVED: commands/setup.md                 REMOVED: commands/setup.md
  RETIRED: scripts/Set-LspSchemaPaths.ps1 (Claude Code path; see §4)
```

`skills: ["./"]` stays. The XML plugin keeps `tests/Validate-DataverseXml.Tests.ps1`.

## 2. Rename mapping

| Thing | Old → New |
|---|---|
| dir + `plugin.json` name + marketplace `name`/`source` | `dataverse-customization-xml` → **`dataverse-xml-lsp`** |
| dir + `plugin.json` name + marketplace `name`/`source` | `power-automate-cloud-flow` → **`cloud-flow-json-lsp`** |
| `SKILL.md` `name:` (differs from plugin name — has `-setup`) | → **`dataverse-xml-lsp-setup`** / **`cloud-flow-json-lsp-setup`** |
| flow `package.json` / `package-lock.json` name | `power-automate-cloud-flow-lsp` → **`cloud-flow-json-lsp`** |
| flow schema `$id` URL (`schemas/cloud-flow-clientdata.schema.json`) | `.../power-automate-cloud-flow/...` → `.../cloud-flow-json-lsp/...` |
| `.claude/settings.json` `enabledPlugins` key | `dataverse-customization-xml@dataverse-agent-plugins` → `dataverse-xml-lsp@dataverse-agent-plugins` |

Reference rewrites (from the full pre-work inventory): `.claude-plugin/marketplace.json` (`name` +
`source` + LSP-first `description`), each `plugin.json` `description`, `.github/workflows/ci.yml`
(all `plugins/<old>/…` paths + cache keys), root `README.md`, `llms.txt`, `CHANGELOG.md` (new top
entry only), both `docs/superpowers/specs/*.md` (old names updated throughout), and each plugin's `README.md` +
`docs/{codex,vscode,debugging}.md`. `.lsp.json` config keys (`"xml"`/`"json"`) and test fixtures are
untouched by the rename.

## 3. The tiny setup skill (`SKILL.md`)

Frontmatter carries `name:` (`<plugin>-setup`) only — **no `description:`**. Body is ~4 lines and
folds in what `commands/setup.md` did, minus path stamping (§4 removes it):

- State the plugin is an LSP server (XML: plus the `Validate-DataverseXml.ps1` CLI for CI/headless).
- One-time per machine: `pwsh "${CLAUDE_PLUGIN_ROOT}/scripts/Install-Plugin.ps1"` (append
  `-UpdateVSCode` to also wire the VS Code editor path); ask about `-UpdateVSCode` before running.
- On success remind to run `/reload-plugins`; on failure point at `docs/debugging.md`.
- Editing guidance lives in `docs/guide.md`.

`Install-Plugin.ps1` keeps the **heavy per-machine install** (flow: `npm ci`; XML: fetch XSDs +
lemminx binary) and the **end-to-end self-check** (XML's stays validator-based since the validator is
kept; flow's stays the `lsp-smoke.mjs` LSP drive), and stays idempotent. Its **path-stamping step is
removed** once §4 lands — the script no longer edits `.lsp.json`, so it need not run again after an
update.

## 4. No-restamp: schema path resolved at launch (Option 1 primary, Option 2 fallback)

**Problem.** `${CLAUDE_PLUGIN_ROOT}` is substituted in `.lsp.json` `command`/`args`/`env`/
`workspaceFolder` but **not** in `settings`/`initializationOptions`, where the schema `url` lives, so
today the absolute path is stamped per machine and re-stamped after each update/move. Relative paths
there resolve against the workspace (not the plugin), and the pac-generated documents can't carry
`$schema`/`schemaLocation`.

**Option 1 — launcher shim (build and test first).** Launch the server via a small wrapper
referenced in `command`/`args` (where `${CLAUDE_PLUGIN_ROOT}` *does* substitute). The shim receives
the plugin root as an argument, spawns the real language server, and injects the absolute schema
association at runtime — for the JSON server by supplying the `json.schemas` config it pulls via
`workspace/configuration`; for lemminx by supplying `xml.fileAssociations` `systemId`. The committed
`.lsp.json` is then fully portable: no per-machine state, no network, no re-stamp. Target design.

**Option 2 — hosted schema URL (fallback, only if the shim fails testing).** The flow schema is
self-contained (0 external `$ref`s), so it can be referenced by a stable `https://` URL with
`handledSchemaProtocols: ["file","https"]`. For the XML plugin this requires hosting the XSD set
(its `xs:include`s resolve relative to the schema URL). Trade-off: first-use network fetch (cached)
and coupling to a live URL.

**Strategy:** implement and test Option 1 on both servers. If it works, ship it; Option 2 is never
built. If it doesn't, **replace** it with Option 2. Exactly one mechanism ships. Either way,
per-machine stamping for the Claude Code LSP is eliminated and `Set-LspSchemaPaths.ps1` is retired
for that path. (The XML validator resolves its XSDs from the local `schemas/` dir independently of
this and is unaffected. VS Code's own association via `-UpdateVSCode` is a separate, optional editor
consumer, out of scope for the shim.)

## 5. Guidance relocation → `docs/guide.md`

The current rich `SKILL.md` bodies move (near-verbatim) into a new `docs/guide.md` per plugin — XML:
the two-layer (LSP live + validator) loop, the ribbon recipe, "rules the XSD doesn't catch",
gotchas, schema refresh; flow: the shape note, attach globs, the ad-hoc `Test-Json` one-liner for
headless checks, gotchas. `docs/codex.md`'s "follow `SKILL.md`" pointers are repointed to
`docs/guide.md` (XML `codex.md` keeps the validator as the story for non-Claude agents). Each plugin
`README.md` keeps a prominent pointer to `docs/guide.md`, and `docs/guide.md` opens by noting it is
the manual replacement for the old auto-loaded skill.

## 6. Versioning, changelog, branch

- Both `plugin.json` versions → **2.0.0**.
- New top CHANGELOG entry: plugins renamed (old → new); restructured to LSP + a single manually-run
  no-description setup skill; guidance moved to `docs/guide.md`; setup slash command removed;
  re-stamp eliminated. (XML validator retained — no behavior loss there.) Called out as **breaking**
  — reinstall under the new plugin id and update the `enabledPlugins` key — and states the §9
  consequence so the change isn't silent.
- All work on a new branch off `main` (e.g. `refactor/lsp-only-plugin-rename`).

## 7. Testing (raise to "well-tested")

On top of the existing Pester suites (which cover `.lsp.json`↔script parity and schema good/bad
fixtures, and resolve paths via `$PSScriptRoot` so the rename doesn't break them):

- **Setup skill guard** — each root `SKILL.md` parses, has `name: <plugin>-setup`, and has **no
  `description`** (locks the no-auto-trigger behavior).
- **Idempotency** — `Install-Plugin.ps1` run twice is clean and the self-check still passes.
- **Launcher shim** (if Option 1 ships) — drive the shim and confirm the server loads the schema and
  flags a bad fixture from a working dir that is NOT the plugin root (proving no stamping needed).
- **XML LSP smoke** — add a lemminx end-to-end smoke (parity with the flow `lsp-smoke.mjs`) so the
  actual XML LSP diagnostic path is covered, not only the validator.
- **Keep** `Validate-DataverseXml.Tests.ps1` (validator retained). Confirm the LSP is not associated
  to the wrapper roots the validator owns (no LSP/validator disagreement on `<forms>`/`<visualization>`).

## 8. Verification (end-to-end)

1. `pwsh …/Install-Plugin.ps1` for both — heavy install + self-check pass.
2. `Invoke-Pester plugins` and `Invoke-ScriptAnalyzer -Path plugins -Recurse` — green (incl. §7).
3. CI: updated `.github/workflows/ci.yml` paths resolve and the workflow runs.
4. `/reload-plugins`: both plugins load with **no load error**; the LSP servers attach via the shim
   with no stamped path; the tiny setup skill lists **without a description** and is manually
   invocable; invoking it installs cleanly.
5. `grep -ri` for both old slugs (excluding `node_modules`/`.git`) returns only the intentional
   `CHANGELOG.md` 1.0.x historical mentions.

## 9. Consequences (accepted trade-off)

- **No auto-guidance.** With the fat auto-triggering skill gone, editing a matching file no longer
  pulls the recipe or gotchas into context; what remains automatic is the LSP's **live diagnostics**
  (main session only) and — for XML — whatever the user runs via `Validate-DataverseXml.ps1`.
  Guidance is opt-in via `docs/guide.md`, kept discoverable through each README's pointer, and the
  CHANGELOG notes the change so it isn't silent.
- **Validation capability is otherwise unchanged:** the XML validator still covers headless/CI and
  the pac wrapper files; the flow plugin still has the built-in `Test-Json` one-liner for ad-hoc
  headless checks.

## 10. Deferred (candidate follow-ups, not in this change)

Parked for a later, additive change once the LSP core is solid:

- A bespoke **flow** validator CLI (a thin `Test-Json` wrapper: globs, exit codes, readable errors)
  for symmetry and CI ergonomics.
- A `PostToolUse` **hook** that auto-runs a validator on matching edits — pending an empirical check
  that such hooks fire in subagents/headless, and mindful of main-session overlap with the LSP
  (which is exactly why it's deferred, not adopted, here).
