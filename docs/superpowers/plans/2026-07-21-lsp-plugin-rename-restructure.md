# LSP Plugin Rename + No-Restamp Restructure — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename both marketplace plugins to LSP-first names, replace each auto-triggering skill + setup command with one tiny no-description setup skill, eliminate the per-machine schema-path re-stamp, and raise test coverage — without losing the XML plugin's CLI validator.

**Architecture:** Each plugin stays `skills: ["./"]` with a tiny `SKILL.md` (name only, no description). The LSP resolves its bundled schema at launch via a launcher shim referenced in `.lsp.json` `command`/`args` (where `${CLAUDE_PLUGIN_ROOT}` substitutes), so no absolute path is stamped. The XML plugin keeps `Validate-DataverseXml.ps1` as the non-LSP/CI channel (no hook). Guidance moves to `docs/guide.md`.

**Tech Stack:** Claude Code plugins (`.claude-plugin/plugin.json`, `.lsp.json`), PowerShell 7 scripts, Node (`vscode-langservers-extracted` JSON server + a node shim), lemminx (Java) for XML, Pester + PSScriptAnalyzer, GitHub Actions.

**User decisions (already made):**
- "I want both plugins to just be lsp servers" with "a tiny skill with no description that they have to manually run to independently setup".
- Names: `dataverse-customization-xml` → `dataverse-xml-lsp`; `power-automate-cloud-flow` → `cloud-flow-json-lsp` (asymmetry intentional; `dataverse-json-lsp` rejected).
- "Keep the XML validator"; flow stays pure LSP; no flow validator and no hook in this change (deferred).
- Guidance → `docs/guide.md`; setup slash command removed; old `docs/superpowers/specs/` updated throughout.
- "try and develop option 1 first and test it and if it doesn't work properly, fallback to option 2" — shim first (gate), hosted-URL only if the shim fails testing; exactly one ships.
- Clean rename via `git mv`, bump both to `2.0.0`, CHANGELOG documents the breaking rename, work on branch `refactor/lsp-only-plugin-rename`.
- Scope = the bundled schemas (full scope kept, incl. the two "indicative" XML layers with their caveat).

**Spec:** `docs/superpowers/specs/2026-07-21-lsp-only-plugin-rename-design.md`

---

## File structure (after rename)

```
plugins/dataverse-xml-lsp/          plugins/cloud-flow-json-lsp/
  .claude-plugin/plugin.json          .claude-plugin/plugin.json     (name, version 2.0.0, desc)
  .lsp.json                           .lsp.json                      (launch via shim, no stamped path)
  SKILL.md  (name: *-setup, no desc)  SKILL.md  (name: *-setup, no desc)
  scripts/
    Install-Plugin.ps1  (no stamping)   Install-Plugin.ps1  (no stamping)
    lsp-launch.mjs  (NEW shim)          lsp-launch.mjs  (NEW shim)
    Get-Schemas.ps1 Get-Lemminx.ps1     Install-JsonLanguageServer.ps1  lsp-smoke.mjs
    Validate-DataverseXml.ps1 (KEPT)
    (Set-LspSchemaPaths.ps1 retired for CC path)
  schemas/  tests/                    schemas/  tests/  package*.json
  docs/ guide.md(NEW) codex vscode debugging
```

Both delete `commands/setup.md`. The XML plugin keeps `tests/Validate-DataverseXml.Tests.ps1`.

---

### Task 1: Launcher-shim feasibility spike (DECISION GATE)

**Goal:** Prove whether a small launcher can inject the schema association into each server at runtime (so `.lsp.json` needs no stamped absolute path), and decide Option 1 (shim) vs Option 2 (hosted URL) for the rest of the plan.

> **USER-ORDERED GATE — NON-SKIPPABLE.** This task was requested by the user in the current conversation ("develop option 1 first and test it and if it doesn't work properly, fallback to option 2"). It MUST NOT be closed by walking around it, by declaring it "verified inline", or by substituting a cheaper check. Close only after every item in `acceptanceCriteria` has been re-validated independently, with output captured.

**Files:**
- Create (throwaway, under scratchpad — not committed): a prototype shim per server + a driver reusing the existing `plugins/power-automate-cloud-flow/scripts/lsp-smoke.mjs` as the client.
- Record the decision at the top of the spec file `docs/superpowers/specs/2026-07-21-lsp-only-plugin-rename-design.md` under a new "Spike result" note.

**Acceptance Criteria:**
- [ ] A node shim spawns `vscode-json-language-server`, receives the plugin root as an argv, and makes the server validate `tests/fixtures/valid/simple-flow.json` clean and `tests/fixtures/invalid/*.json` as errors — driven from a working directory that is NOT the plugin root, with NO absolute path written into any config file.
- [ ] The equivalent is confirmed for lemminx (inject `xml.fileAssociations` `systemId` from the plugin-root argv) against the XML valid/invalid ribbon fixtures.
- [ ] A go/no-go decision is written to the spec: shim works for both → Option 1; otherwise → Option 2 (hosted URL), naming which server failed and why.

**Verify:** `node <spike-driver> --plugin-root <abs-path> --cwd <some-other-dir>` prints the invalid fixture's diagnostics and exits non-zero on the bad fixture, zero on the good one — for both servers.

**Steps:**

- [ ] **Step 1: Install both servers locally** so the spike can drive real binaries.

```bash
pwsh plugins/power-automate-cloud-flow/scripts/Install-Plugin.ps1
pwsh plugins/dataverse-customization-xml/scripts/Install-Plugin.ps1
```

- [ ] **Step 2: Prototype the JSON shim.** In the scratchpad, write a node script that:
  reads `--plugin-root`; spawns `node <pluginRoot>/node_modules/.../jsonServerMain.js --stdio`;
  proxies stdio; and injects `json.schemas:[{fileMatch:[...], url:"file://<pluginRoot>/schemas/cloud-flow-clientdata.schema.json"}]` into the config the server pulls (answer the server's `workspace/configuration` request, and set `initializationOptions.settings.json.schemas` on the `initialize` it forwards). Reuse `lsp-smoke.mjs` as the driving client but launch the shim instead of the server, and run it from a temp cwd.

- [ ] **Step 3: Confirm JSON validation fires** with no stamped path (good fixture clean, bad fixtures flagged). Capture output.

- [ ] **Step 4: Prototype the lemminx shim** the same way, injecting `xml.fileAssociations` (systemId = `file://<pluginRoot>/schemas/<ver>/<xsd>`) for the ribbon glob; drive it against `tests/fixtures/valid/ribbon.xml` and `invalid/ribbon.xml`.

- [ ] **Step 5: Decide and record.** If both work → Option 1 (shim). If either can't inject reliably → Option 2 (hosted URL) for the whole plan. Append a "Spike result (YYYY-MM-DD)" note to the spec stating the decision and evidence.

- [ ] **Step 6: Commit the decision note** (spike prototypes stay in scratchpad, uncommitted).

```bash
git add docs/superpowers/specs/2026-07-21-lsp-only-plugin-rename-design.md
git commit -m "Record launcher-shim spike result (Option 1 vs 2 decision)"
```

---

### Task 2: Rename both plugins (atomic)

**Goal:** Move both plugin directories to the new names and update every reference in one coherent commit, so the tree is never half-renamed.

**Files:**
- Move: `plugins/dataverse-customization-xml/` → `plugins/dataverse-xml-lsp/`; `plugins/power-automate-cloud-flow/` → `plugins/cloud-flow-json-lsp/` (via `git mv`).
- Modify: `.claude-plugin/marketplace.json`; each `.claude-plugin/plugin.json`; `plugins/cloud-flow-json-lsp/package.json` + `package-lock.json`; `plugins/cloud-flow-json-lsp/schemas/cloud-flow-clientdata.schema.json` (`$id`); `.claude/settings.json`; `.github/workflows/ci.yml`; `README.md`; `llms.txt`; `docs/superpowers/specs/2026-07-15-dataverse-agent-plugins-repo-design.md`; `docs/superpowers/specs/2026-07-21-power-automate-cloud-flow-plugin-design.md`; each plugin's `README.md`, `docs/codex.md`, `docs/vscode.md`, `docs/debugging.md`.
- Delete: `plugins/*/commands/setup.md` (both).

**Acceptance Criteria:**
- [ ] Both plugin dirs exist under the new names; `git mv` preserved history.
- [ ] `marketplace.json` has both new `name`+`source`; both `plugin.json` have new `name`, `"version": "2.0.0"`, and an LSP-first `description`.
- [ ] Flow `package.json`/`package-lock.json` name = `cloud-flow-json-lsp`; flow schema `$id` uses the new path.
- [ ] `.claude/settings.json` key is `dataverse-xml-lsp@dataverse-agent-plugins`.
- [ ] CI paths/cache keys point at the new dirs; `commands/setup.md` gone from both.
- [ ] `grep -ri` for both old slugs (excluding `node_modules`/`.git`) returns only `CHANGELOG.md` 1.0.x lines.

**Verify:** `grep -rin --exclude-dir=node_modules --exclude-dir=.git -e dataverse-customization-xml -e power-automate-cloud-flow .` → only CHANGELOG 1.0.x hits; then `pwsh -c "Invoke-Pester plugins"` → all pass.

**Steps:**

- [ ] **Step 1: Move the directories.**

```bash
git mv plugins/dataverse-customization-xml plugins/dataverse-xml-lsp
git mv plugins/power-automate-cloud-flow plugins/cloud-flow-json-lsp
git rm plugins/dataverse-xml-lsp/commands/setup.md plugins/cloud-flow-json-lsp/commands/setup.md
```

- [ ] **Step 2: Update manifests.** In `.claude-plugin/marketplace.json` set both `name` + `source` (`./plugins/dataverse-xml-lsp`, `./plugins/cloud-flow-json-lsp`) and reword each `description` to lead with "LSP". In each `plugins/*/.claude-plugin/plugin.json` set `name` to the new slug, `"version": "2.0.0"`, and an LSP-first `description`.

- [ ] **Step 3: Update flow npm identity + schema id.** In `plugins/cloud-flow-json-lsp/package.json` and `package-lock.json` set `name` to `cloud-flow-json-lsp`. In `schemas/cloud-flow-clientdata.schema.json` change `$id` to `https://github.com/Cordedmink2/dataverse-agent-plugins/cloud-flow-json-lsp/cloud-flow-clientdata.schema.json`.

- [ ] **Step 4: Update repo-level references.** `.claude/settings.json` enabledPlugins key; `.github/workflows/ci.yml` (cache `path:` + `key:` + the `run:` script paths for both plugins); `README.md`; `llms.txt`; both `docs/superpowers/specs/*.md` (replace old slugs/paths/`/…:setup` command refs throughout).

- [ ] **Step 5: Update per-plugin docs.** In each plugin's `README.md` and `docs/{codex,vscode,debugging}.md`, replace old slug, paths, install/update commands, and `/<old>:setup` references. (The `/<plugin>:setup` command no longer exists — reword those to the setup-skill invocation, finalized in Task 5.)

- [ ] **Step 6: Verify + commit.**

```bash
grep -rin --exclude-dir=node_modules --exclude-dir=.git -e dataverse-customization-xml -e power-automate-cloud-flow . | grep -v CHANGELOG.md
pwsh -c "Invoke-Pester plugins"
git add -A
git commit -m "Rename plugins to dataverse-xml-lsp and cloud-flow-json-lsp (2.0.0)"
```

---

### Task 3: No-restamp schema resolution (productionize the spike)

**Goal:** Ship the mechanism chosen in Task 1 so the committed `.lsp.json` resolves its schema on every machine with no stamping, and remove the stamping step from setup.

**Files:**
- Option 1 (shim, primary): Create `plugins/dataverse-xml-lsp/scripts/lsp-launch.mjs` and `plugins/cloud-flow-json-lsp/scripts/lsp-launch.mjs` (hardened from the Task 1 prototype). Modify both `.lsp.json` (`command: "node"`, `args: ["${CLAUDE_PLUGIN_ROOT}/scripts/lsp-launch.mjs", "${CLAUDE_PLUGIN_ROOT}", "--stdio"]`; remove the stamped `settings`/`initializationOptions` schema `url`). Modify both `scripts/Install-Plugin.ps1` (drop the `Set-LspSchemaPaths.ps1` call for the CC path). Retire `Set-LspSchemaPaths.ps1` for the CC path (keep only the `-UpdateVSCode` branch if VS Code stamping is still wanted).
- Option 2 (hosted URL, only if Task 1 said so): host the schema(s); set `handledSchemaProtocols` to include `https`; put the stable URL in `.lsp.json`; same Install-Plugin/Set-LspSchemaPaths simplification.

**Acceptance Criteria:**
- [ ] `.lsp.json` contains no machine-local absolute path; it uses `${CLAUDE_PLUGIN_ROOT}` (shim) or an `https://` URL (fallback).
- [ ] After copying the plugin to a fresh path and running the LSP, the schema still loads (no re-stamp).
- [ ] `Install-Plugin.ps1` no longer edits `.lsp.json`.

**Verify:** From a temp copy of the plugin dir, drive the LSP via the shim/URL against a bad fixture and confirm diagnostics fire — no stamping step run. (Shim: `node scripts/lsp-launch.mjs <abs-plugin-root> --stdio` fed an LSP init + a bad doc → diagnostics.)

**Steps:**

- [ ] **Step 1: Productionize the launcher** from Task 1's prototype into `scripts/lsp-launch.mjs` for each plugin (JSON server for flow, lemminx for XML), reading `process.argv[2]` as the plugin root and injecting the schema association as the spike proved. (Exact injection code = the working prototype from Task 1.)

- [ ] **Step 2: Point `.lsp.json` at the shim.** Replace `command`/`args` to launch `lsp-launch.mjs` with `${CLAUDE_PLUGIN_ROOT}` as an arg; delete the stamped schema `url` from `settings`/`initializationOptions` (the shim supplies it). Keep the `fileMatch` globs the shim needs (pass them in the shim or keep them in a non-path-bearing settings block).

- [ ] **Step 3: De-stamp setup.** In `Install-Plugin.ps1`, remove the `Set-LspSchemaPaths.ps1` invocation for the Claude Code path. Retire the CC-path logic in `Set-LspSchemaPaths.ps1` (leave the `-UpdateVSCode` editor-association branch if kept).

- [ ] **Step 4: Verify from a moved copy.**

```bash
cp -r plugins/cloud-flow-json-lsp "$TMP/moved-flow"
node "$TMP/moved-flow/scripts/lsp-launch.mjs" "$TMP/moved-flow" --stdio   # driven by the smoke client → bad fixture flagged
```

- [ ] **Step 5: Commit.**

```bash
git add plugins/*/scripts/lsp-launch.mjs plugins/*/.lsp.json plugins/*/scripts/Install-Plugin.ps1 plugins/*/scripts/Set-LspSchemaPaths.ps1
git commit -m "Resolve LSP schema path at launch; drop per-machine stamping"
```

---

### Task 4: Move guidance to `docs/guide.md`

**Goal:** Preserve the rich domain guidance the auto-triggering skill carried by moving it into a reference doc, before the skill is shrunk.

**Files:**
- Create: `plugins/dataverse-xml-lsp/docs/guide.md`, `plugins/cloud-flow-json-lsp/docs/guide.md`.
- Modify: each plugin's `docs/codex.md` (repoint "follow `SKILL.md`" → `docs/guide.md`); each plugin's `README.md` (add a prominent pointer to `docs/guide.md`).

**Acceptance Criteria:**
- [ ] `docs/guide.md` (XML) contains the validate loop, the ribbon/command-bar recipe, the "rules the XSD doesn't catch" list, gotchas, and schema-refresh section from the old `SKILL.md`.
- [ ] `docs/guide.md` (flow) contains the shape note, attach globs, the ad-hoc `Test-Json` one-liner, and gotchas.
- [ ] Each `guide.md` opens noting it is the manual replacement for the old auto-loaded skill; `codex.md` and `README.md` point at it.

**Verify:** `grep -l "manual replacement for the old" plugins/*/docs/guide.md` lists both; `grep -r "guide.md" plugins/*/README.md plugins/*/docs/codex.md` shows the pointers.

**Steps:**

- [ ] **Step 1: Create `docs/guide.md`** for each plugin by moving the body of the current `SKILL.md` (everything below the frontmatter) into it, with a one-line preamble: `> This is the manual replacement for the old auto-loaded skill; the plugin no longer surfaces this automatically.`

- [ ] **Step 2: Repoint pointers.** In each `docs/codex.md`, change "follow `SKILL.md`" to "follow `docs/guide.md`". In each `README.md`, add a line: `See docs/guide.md for editing guidance.`

- [ ] **Step 3: Commit.**

```bash
git add plugins/*/docs/guide.md plugins/*/docs/codex.md plugins/*/README.md
git commit -m "Move plugin editing guidance into docs/guide.md"
```

---

### Task 5: Shrink `SKILL.md` to a tiny no-description setup skill

**Goal:** Replace each auto-triggering skill body with a tiny, no-description skill whose only job is to run setup.

**Files:**
- Modify (overwrite): `plugins/dataverse-xml-lsp/SKILL.md`, `plugins/cloud-flow-json-lsp/SKILL.md`.

**Acceptance Criteria:**
- [ ] Frontmatter has `name:` (`dataverse-xml-lsp-setup` / `cloud-flow-json-lsp-setup`) and **no `description:`**.
- [ ] Body is ~4 lines: what the plugin is, the one-time `Install-Plugin.ps1` command (mention `-UpdateVSCode`), the `/reload-plugins` reminder + `docs/debugging.md` on failure, and the `docs/guide.md` pointer.
- [ ] `/reload-plugins` lists the skill with no description and it is manually invocable as `/<plugin>:<plugin>-setup`.

**Verify:** `pwsh -c "Invoke-Pester plugins"` (the Task 6 setup-skill guard passes); manual `/reload-plugins` then `/dataverse-xml-lsp:dataverse-xml-lsp-setup` runs setup.

**Steps:**

- [ ] **Step 1: Write the XML `SKILL.md`.**

```markdown
---
name: dataverse-xml-lsp-setup
---

# dataverse-xml-lsp setup

This plugin is a lemminx XML LSP for Dataverse customization XML (plus `scripts/Validate-DataverseXml.ps1` for CI/headless). Run once per machine:

`pwsh "${CLAUDE_PLUGIN_ROOT}/scripts/Install-Plugin.ps1"` (add `-UpdateVSCode` to also wire VS Code). Then run `/reload-plugins`. If it fails, see `docs/debugging.md`. Editing guidance: `docs/guide.md`.
```

- [ ] **Step 2: Write the flow `SKILL.md`.**

```markdown
---
name: cloud-flow-json-lsp-setup
---

# cloud-flow-json-lsp setup

This plugin is a JSON LSP for unpacked Power Automate cloud-flow clientdata (`Workflows/*.json`). Run once per machine:

`pwsh "${CLAUDE_PLUGIN_ROOT}/scripts/Install-Plugin.ps1"` (add `-UpdateVSCode` to also wire VS Code). Then run `/reload-plugins`. If it fails, see `docs/debugging.md`. Editing guidance: `docs/guide.md`.
```

- [ ] **Step 3: Commit.**

```bash
git add plugins/*/SKILL.md
git commit -m "Replace auto-triggering skills with tiny no-description setup skills"
```

---

### Task 6: Tests — raise to well-tested

**Goal:** Lock the new behaviors with tests: no-description skill, setup idempotency, XML LSP smoke, and shim resolution.

**Files:**
- Create: `plugins/dataverse-xml-lsp/tests/SetupSkill.Tests.ps1`, `plugins/cloud-flow-json-lsp/tests/SetupSkill.Tests.ps1`; `plugins/dataverse-xml-lsp/scripts/lsp-smoke-xml.mjs` (or `.ps1`) + a test invoking it.
- Modify: keep `plugins/dataverse-xml-lsp/tests/Validate-DataverseXml.Tests.ps1` (unchanged); extend `LspConfig.Tests.ps1` if needed to assert the shim launch shape.

**Acceptance Criteria:**
- [ ] A test asserts each `SKILL.md` parses, `name` == `<plugin>-setup`, and there is no `description` key.
- [ ] A test runs `Install-Plugin.ps1` twice and asserts the second run succeeds (idempotent).
- [ ] An XML LSP smoke drives lemminx end-to-end (good fixture clean, bad flagged), parity with `cloud-flow-json-lsp/scripts/lsp-smoke.mjs`.
- [ ] `Validate-DataverseXml.Tests.ps1` still passes; a test asserts the LSP is NOT associated to wrapper roots (`<forms>`, `<visualization>`).

**Verify:** `pwsh -c "Invoke-Pester plugins"` → all green, including the new suites.

**Steps:**

- [ ] **Step 1: Setup-skill guard test** (both plugins), e.g. `plugins/dataverse-xml-lsp/tests/SetupSkill.Tests.ps1`:

```powershell
#requires -Version 7
Describe 'setup skill frontmatter' {
    BeforeAll {
        $skill = Join-Path (Split-Path $PSScriptRoot -Parent) 'SKILL.md'
        $fm = (Get-Content $skill -Raw) -split '(?m)^---\s*$' | Select-Object -Index 1
    }
    It 'names the skill <plugin>-setup' { $fm | Should -Match 'name:\s*dataverse-xml-lsp-setup' }
    It 'has no description key'         { $fm | Should -Not -Match '(?m)^\s*description\s*:' }
}
```

- [ ] **Step 2: Run it to see it pass** (after Task 5): `pwsh -c "Invoke-Pester plugins/dataverse-xml-lsp/tests/SetupSkill.Tests.ps1"` → PASS.

- [ ] **Step 3: Idempotency test** — a Pester `It` that runs `Install-Plugin.ps1` twice and asserts `$LASTEXITCODE -eq 0` both times (guard with a skip when `node`/network unavailable so CI stays green).

- [ ] **Step 4: XML LSP smoke** — adapt `cloud-flow-json-lsp/scripts/lsp-smoke.mjs` to drive lemminx via the shim, assert the invalid ribbon fixture yields diagnostics and the valid one does not; add a Pester wrapper test.

- [ ] **Step 5: Wrapper-root non-association assertion** — a test that reads `.lsp.json` (and/or `Set-LspSchemaPaths` associations) and asserts no association glob targets forms/chart wrapper files.

- [ ] **Step 6: Commit.**

```bash
git add plugins/*/tests/SetupSkill.Tests.ps1 plugins/dataverse-xml-lsp/scripts/lsp-smoke-xml.mjs plugins/*/tests
git commit -m "Add tests: no-description skill, setup idempotency, XML LSP smoke"
```

---

### Task 7: CHANGELOG + final end-to-end verification (ACCEPTANCE GATE)

**Goal:** Document the breaking 2.0.0 change and prove the whole restructure works end-to-end.

> **USER-ORDERED GATE — NON-SKIPPABLE.** This task was requested by the user in the current conversation (the north-star: "really good and well tested"). It MUST NOT be closed by walking around it, by declaring it "verified inline", or by substituting a cheaper check. Close only after every item in `acceptanceCriteria` has been re-validated independently, with output captured.

**Files:**
- Modify: `CHANGELOG.md` (new top entry).

**Acceptance Criteria:**
- [ ] CHANGELOG top entry documents: renames (old→new), LSP + tiny no-description setup skill, guidance → `docs/guide.md`, setup command removed, re-stamp eliminated; marked **breaking** with the reinstall + `enabledPlugins` migration note; states the "no auto-guidance" consequence.
- [ ] `Install-Plugin.ps1` self-check passes for both plugins.
- [ ] `Invoke-Pester plugins` and `Invoke-ScriptAnalyzer -Path plugins -Recurse` are green.
- [ ] `/reload-plugins` loads both with no load error; LSPs attach via the shim with no stamped path; each setup skill lists with no description and is invocable.

**Verify:** the four commands below all succeed; `/reload-plugins` shows both plugins + LSPs with no error.

**Steps:**

- [ ] **Step 1: Write the CHANGELOG entry** at the top of `CHANGELOG.md`:

```markdown
## 2.0.0

### Changed (breaking)
- Renamed plugins: `dataverse-customization-xml` → `dataverse-xml-lsp`, `power-automate-cloud-flow` → `cloud-flow-json-lsp`. Reinstall under the new id and update your `enabledPlugins` key.
- Each plugin is now an LSP server plus a single manually-run, no-description setup skill (`/<plugin>:<plugin>-setup`). The auto-triggering skill and the `/<plugin>:setup` slash command are removed — editing guidance no longer surfaces automatically; it lives in `docs/guide.md`.
- LSP schema path is resolved at launch, so setup no longer stamps `.lsp.json` and need not be re-run after `/plugin update`.

The XML plugin keeps `Validate-DataverseXml.ps1` for CI/headless/wrapper-file validation.
```

- [ ] **Step 2: Run the full verification.**

```bash
pwsh plugins/dataverse-xml-lsp/scripts/Install-Plugin.ps1
pwsh plugins/cloud-flow-json-lsp/scripts/Install-Plugin.ps1
pwsh -c "Invoke-Pester plugins"
pwsh -c "Invoke-ScriptAnalyzer -Path plugins -Recurse" 
```
Expected: both installs report "self-check passed"; Pester all pass; ScriptAnalyzer clean.

- [ ] **Step 3: Reload and eyeball.** `/reload-plugins` → both plugins load, no load error, LSP servers attach; `/<plugin>:<plugin>-setup` is listed without a description and runs.

- [ ] **Step 4: Commit.**

```bash
git add CHANGELOG.md
git commit -m "Document 2.0.0 breaking restructure in CHANGELOG"
```

---

## Self-review

- **Spec coverage:** rename (T2), no-restamp shim/URL (T1 decision, T3), tiny no-description skill (T5), guidance→guide.md (T4), XML validator kept (T2/T6 keep the script+test), tests incl. no-desc guard + idempotency + XML smoke + wrapper non-association (T6), versioning + CHANGELOG (T2 version, T7 changelog), verification incl. grep + reload (T2, T7). All spec sections map to a task.
- **Placeholders:** the only deferred code is `lsp-launch.mjs`'s exact injection body, which is intentionally the *output of the Task 1 spike* (can't be finalized before the spike proves it) — Task 3 productionizes that verified prototype. Every other step carries real commands/code.
- **Type/name consistency:** skill names `dataverse-xml-lsp-setup` / `cloud-flow-json-lsp-setup`, shim `scripts/lsp-launch.mjs`, guide `docs/guide.md` used consistently across tasks.
