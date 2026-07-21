# XML Validator Discoverability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `dataverse-xml-lsp`'s retained CLI validator discoverable to the agent via an auto-triggering usage skill and a `PostToolUse` hook scoped to the files the LSP cannot cover.

**Architecture:** Two additive pieces, both calling the single existing `Validate-DataverseXml.ps1`. A usage skill (with a keyword-rich description) auto-loads on Dataverse-XML work and teaches when/how to validate; a Node `PostToolUse` gate auto-runs the validator only when an edited `.xml` file's root is one of six validator-owned roots. The existing setup skill is relocated under `skills/` and gets `disable-model-invocation: true` so it stops competing during editing. No LSP change (live validation stays limited to the authoritative schemas — rationale in the spec).

**Tech Stack:** Claude Code plugin (SKILL.md, plugin.json, hooks/hooks.json), Node (ESM `.mjs`), PowerShell 7 validator, Pester tests.

**User decisions (already made):**
- "skill + wrapper hook" — build both mechanisms.
- "B — The full complement" — hook covers all six validator-owned roots (`form`, `forms`, `datadefinition`, `visualization`, `viewers`, `importexportxml`).
- "Try and fix the lsp first but if you can't, hook" — LSP fix was investigated and rejected (wrapper roots undeclared; lag-prone schemas would flood the editor). Hook it is.
- Reuse the original fat skill's `description` and headless/subagent callout in the usage skill; leave recipes/tables in `docs/guide.md`.

**Spec:** `docs/superpowers/specs/2026-07-21-xml-validator-discoverability-design.md`

---

## File Structure

| File | Responsibility | Task |
|------|----------------|------|
| `plugins/dataverse-xml-lsp/skills/dataverse-xml-lsp-setup/SKILL.md` | Existing setup skill, relocated under `skills/`, `disable-model-invocation: true` added | 1 |
| `plugins/dataverse-xml-lsp/skills/dataverse-xml-validate/SKILL.md` | NEW auto-triggering usage skill | 2 |
| `plugins/dataverse-xml-lsp/.claude-plugin/plugin.json` | `skills` array → both dirs; `version` → 2.1.0 | 1, 2, 4 |
| `plugins/dataverse-xml-lsp/hooks/hooks.json` | NEW `PostToolUse` hook registration | 3 |
| `plugins/dataverse-xml-lsp/hooks/validate-wrapper.mjs` | NEW Node gate → validator delegation | 3 |
| `plugins/dataverse-xml-lsp/tests/SetupSkill.Tests.ps1` | Updated: new path + assert `disable-model-invocation` | 1 |
| `plugins/dataverse-xml-lsp/tests/UsageSkill.Tests.ps1` | NEW: usage-skill frontmatter + both skills registered | 2 |
| `plugins/dataverse-xml-lsp/tests/Hook.Tests.ps1` | NEW: drives the gate via node, asserts exit codes | 3 |
| `plugins/dataverse-xml-lsp/tests/fixtures/invalid/visualization-wrapper.xml` | NEW: invalid chart wrapper (fills the one missing invalid fixture) | 3 |
| `plugins/dataverse-xml-lsp/README.md` | Component table: setup-skill path, usage skill, hook | 1, 4 |
| `plugins/dataverse-xml-lsp/docs/guide.md` | Correct the "no longer surfaces automatically" line | 4 |
| `CHANGELOG.md` | 2.1.0 entry | 4 |

---

### Task 1: Relocate setup skill and disable its auto-invocation

**Goal:** Move the setup skill under `skills/` and add `disable-model-invocation: true` so it no longer auto-competes during editing.

**Files:**
- Move: `plugins/dataverse-xml-lsp/SKILL.md` → `plugins/dataverse-xml-lsp/skills/dataverse-xml-lsp-setup/SKILL.md`
- Modify: `plugins/dataverse-xml-lsp/.claude-plugin/plugin.json` (`skills` field)
- Modify: `plugins/dataverse-xml-lsp/tests/SetupSkill.Tests.ps1`
- Modify: `plugins/dataverse-xml-lsp/README.md:52`

**Acceptance Criteria:**
- [ ] `plugins/dataverse-xml-lsp/SKILL.md` no longer exists; the file lives at `skills/dataverse-xml-lsp-setup/SKILL.md`.
- [ ] That SKILL.md frontmatter has `name: dataverse-xml-lsp-setup` and `disable-model-invocation: true`.
- [ ] `plugin.json` `skills` is `["./skills/dataverse-xml-lsp-setup"]` and the file is valid JSON.
- [ ] `SetupSkill.Tests.ps1` passes against the new location and asserts the disable flag.

**Verify:** `pwsh -c "Invoke-Pester plugins/dataverse-xml-lsp/tests/SetupSkill.Tests.ps1"` → all pass.

**Steps:**

- [ ] **Step 1: Move the skill file (preserve history)**

```bash
cd plugins/dataverse-xml-lsp
mkdir -p skills/dataverse-xml-lsp-setup
git mv SKILL.md skills/dataverse-xml-lsp-setup/SKILL.md
```

- [ ] **Step 2: Add the disable flag to the moved SKILL.md frontmatter**

The frontmatter currently is just `name: dataverse-xml-lsp-setup`. Make it:

```markdown
---
name: dataverse-xml-lsp-setup
disable-model-invocation: true
---
```

Leave the body unchanged (its `${CLAUDE_PLUGIN_ROOT}/scripts/...` references resolve to the plugin root regardless of the skill's location).

- [ ] **Step 3: Point plugin.json at the relocated skill**

In `plugins/dataverse-xml-lsp/.claude-plugin/plugin.json`, change the `skills` array from `["./"]` to:

```json
  "skills": [
    "./skills/dataverse-xml-lsp-setup"
  ],
```

- [ ] **Step 4: Update SetupSkill.Tests.ps1 (path + inverted assertion)**

Replace the file with:

```powershell
#requires -Version 7
<#
    Locks the setup skill's frontmatter. It must:
      - live at skills/dataverse-xml-lsp-setup/SKILL.md,
      - parse (have a YAML frontmatter block between the first two --- lines),
      - carry name: dataverse-xml-lsp-setup,
      - carry disable-model-invocation: true (setup is a one-time manual action; it must not
        auto-trigger and compete with the usage skill during editing).
#>

Describe 'setup skill frontmatter (dataverse-xml-lsp)' {

    BeforeAll {
        $pluginRoot = Split-Path $PSScriptRoot -Parent
        $script:skillPath = Join-Path $pluginRoot 'skills' 'dataverse-xml-lsp-setup' 'SKILL.md'
        $script:lines = Get-Content $script:skillPath

        # Parse the YAML frontmatter: the block between the first two --- lines.
        $fence = @()
        for ($i = 0; $i -lt $script:lines.Count; $i++) {
            if ($script:lines[$i].Trim() -eq '---') { $fence += $i }
            if ($fence.Count -eq 2) { break }
        }
        $script:frontmatter = @{}
        if ($fence.Count -eq 2) {
            foreach ($line in $script:lines[($fence[0] + 1)..($fence[1] - 1)]) {
                if ($line -match '^\s*([A-Za-z0-9_-]+)\s*:\s*(.*?)\s*$') {
                    $script:frontmatter[$Matches[1]] = $Matches[2]
                }
            }
        }
        $script:fenceCount = $fence.Count
    }

    It 'SKILL.md exists at the relocated path' {
        Test-Path $script:skillPath | Should -BeTrue
    }

    It 'has a parseable YAML frontmatter block' {
        $fenceCount | Should -Be 2 -Because 'SKILL.md must open with a --- ... --- frontmatter block'
    }

    It 'name is dataverse-xml-lsp-setup' {
        $frontmatter['name'] | Should -Be 'dataverse-xml-lsp-setup'
    }

    It 'disables model invocation (no auto-trigger)' {
        $frontmatter['disable-model-invocation'] | Should -Be 'true' -Because 'setup is a one-time manual action; it must not auto-trigger'
    }
}
```

- [ ] **Step 5: Update the README component-table row**

In `plugins/dataverse-xml-lsp/README.md`, the row that reads:

```
| `SKILL.md` | Tiny no-description setup skill (runs `Install-Plugin.ps1`) |
```

becomes:

```
| `skills/dataverse-xml-lsp-setup/SKILL.md` | Setup skill (runs `Install-Plugin.ps1`); `disable-model-invocation` so it never auto-triggers |
```

- [ ] **Step 6: Verify and commit**

```bash
pwsh -c "Invoke-Pester plugins/dataverse-xml-lsp/tests/SetupSkill.Tests.ps1"
node -e "JSON.parse(require('fs').readFileSync('plugins/dataverse-xml-lsp/.claude-plugin/plugin.json','utf8'))" && echo "plugin.json OK"
git add -A plugins/dataverse-xml-lsp
git commit -m "Relocate setup skill under skills/ and disable its auto-invocation"
```

Expected: Pester all pass; "plugin.json OK".

---

### Task 2: Add the usage skill

**Goal:** Add an auto-triggering `dataverse-xml-validate` skill that surfaces the validator and how to read its output.

**Files:**
- Create: `plugins/dataverse-xml-lsp/skills/dataverse-xml-validate/SKILL.md`
- Modify: `plugins/dataverse-xml-lsp/.claude-plugin/plugin.json` (`skills` field)
- Create: `plugins/dataverse-xml-lsp/tests/UsageSkill.Tests.ps1`

**Acceptance Criteria:**
- [ ] `skills/dataverse-xml-validate/SKILL.md` exists with `name: dataverse-xml-validate` and a non-empty `description`.
- [ ] The body gives the validator command, the when-to-run list, and the how-to-read-output rule; it points to `docs/guide.md` and contains no ribbon recipe or root→schema table (no duplication of the guide).
- [ ] `plugin.json` `skills` lists both `./skills/dataverse-xml-lsp-setup` and `./skills/dataverse-xml-validate`; both directories exist.
- [ ] `UsageSkill.Tests.ps1` passes.

**Verify:** `pwsh -c "Invoke-Pester plugins/dataverse-xml-lsp/tests/UsageSkill.Tests.ps1"` → all pass.

**Steps:**

- [ ] **Step 1: Create the usage skill**

Create `plugins/dataverse-xml-lsp/skills/dataverse-xml-validate/SKILL.md`:

```markdown
---
name: dataverse-xml-validate
description: >-
  Use when editing, reviewing, or validating Dataverse / model-driven-app customization XML —
  RibbonDiff.xml, Customizations.xml, SiteMap, FormXml (forms), charts
  (visualization / datadefinition), FetchXML, viewers, or configuration-migration parameter XML —
  especially in headless / subagent / CI contexts or before `pac solution pack` / `pac solution
  import`. Runs the schema validator (Validate-DataverseXml.ps1) and explains how to read its output.
---

# Validate Dataverse customization XML

Run the schema validator after editing Dataverse customization XML, and always in contexts where the
live LSP does not push diagnostics (subagents, headless, CI):

```
pwsh "${CLAUDE_PLUGIN_ROOT}/scripts/Validate-DataverseXml.ps1" <file-or-dir> [more paths / globs]
```

Non-zero exit = validation failed. It picks the schema by the file's root element and fails loud on
unknown roots.

## When to run it

- **Headless / subagent / CI edits** — the lemminx LSP only pushes diagnostics in the main
  interactive session; elsewhere you get nothing unless you run this.
- **Forms, charts, viewers, parameter XML, and whole `Customizations.xml`** — the LSP does not cover
  these live; the validator owns them. (A PostToolUse hook also auto-runs it on these files.)
- **Before `pac solution pack` / `import`** — a final gate so bad edits fail here, not at import.

## How to read the output

Whole-form `FormXml` and whole-file `Customizations.xml` validation is **indicative, not
authoritative**: the bundled `9.0.0.2090` schema lags modern attributes, so it reports false "not
declared" errors on out-of-the-box content. Confirm YOUR edit is clean by checking that no error
references your own element/attribute names (grep the output for them); treat pre-existing OOB noise
as expected. The **ribbon** fragment (`RibbonCore.xsd`) is authoritative.

Full root→schema table, the ribbon-button recipe, and gotchas: `docs/guide.md`.
```

- [ ] **Step 2: Add the usage skill to plugin.json**

In `plugins/dataverse-xml-lsp/.claude-plugin/plugin.json`, make `skills`:

```json
  "skills": [
    "./skills/dataverse-xml-lsp-setup",
    "./skills/dataverse-xml-validate"
  ],
```

- [ ] **Step 3: Create UsageSkill.Tests.ps1**

Create `plugins/dataverse-xml-lsp/tests/UsageSkill.Tests.ps1`:

```powershell
#requires -Version 7
<#
    Locks the usage skill's auto-trigger contract and the two-skill registration:
      - skills/dataverse-xml-validate/SKILL.md carries name + a NON-EMPTY description (the
        description is what lets Claude auto-invoke it on Dataverse-XML work),
      - plugin.json lists both skill directories and both exist on disk.
#>

Describe 'usage skill + plugin skill registration (dataverse-xml-lsp)' {

    BeforeAll {
        $script:pluginRoot = Split-Path $PSScriptRoot -Parent
        $script:skillPath = Join-Path $pluginRoot 'skills' 'dataverse-xml-validate' 'SKILL.md'
        $script:lines = Get-Content $script:skillPath

        $fence = @()
        for ($i = 0; $i -lt $script:lines.Count; $i++) {
            if ($script:lines[$i].Trim() -eq '---') { $fence += $i }
            if ($fence.Count -eq 2) { break }
        }
        $script:frontmatter = @{}
        if ($fence.Count -eq 2) {
            foreach ($line in $script:lines[($fence[0] + 1)..($fence[1] - 1)]) {
                if ($line -match '^\s*([A-Za-z0-9_-]+)\s*:\s*(.*?)\s*$') {
                    $script:frontmatter[$Matches[1]] = $Matches[2]
                }
            }
        }

        $manifest = Get-Content (Join-Path $pluginRoot '.claude-plugin' 'plugin.json') -Raw | ConvertFrom-Json
        $script:skills = @($manifest.skills)
    }

    It 'name is dataverse-xml-validate' {
        $frontmatter['name'] | Should -Be 'dataverse-xml-validate'
    }

    It 'has a non-empty description (auto-trigger)' {
        # description uses a folded block scalar (>-), so the value sits on following lines; assert
        # the key is present and that the body under it is not empty.
        ($script:lines -join "`n") | Should -Match 'description:\s*>-'
        $descIdx = ($script:lines | Select-String -Pattern '^\s*description:' | Select-Object -First 1).LineNumber
        $descIdx | Should -Not -BeNullOrEmpty
        ($script:lines[$descIdx].Trim().Length) | Should -BeGreaterThan 0 -Because 'the folded description must have content on the next line'
    }

    It 'points to docs/guide.md rather than duplicating it' {
        ($script:lines -join "`n") | Should -Match 'docs/guide\.md'
    }

    It 'does not inline the ribbon recipe (kept in the guide)' {
        ($script:lines -join "`n") | Should -Not -Match 'CommandDefinition'
    }

    It 'registers both skill directories, and both exist' {
        $script:skills | Should -Contain './skills/dataverse-xml-lsp-setup'
        $script:skills | Should -Contain './skills/dataverse-xml-validate'
        foreach ($s in $script:skills) {
            Test-Path (Join-Path $pluginRoot ($s -replace '^\./','')) | Should -BeTrue -Because "$s must exist"
        }
    }
}
```

- [ ] **Step 4: Verify and commit**

```bash
pwsh -c "Invoke-Pester plugins/dataverse-xml-lsp/tests/UsageSkill.Tests.ps1"
git add -A plugins/dataverse-xml-lsp
git commit -m "Add dataverse-xml-validate usage skill"
```

Expected: Pester all pass.

---

### Task 3: Add the wrapper hook (gate script, registration, test)

**Goal:** Ship a `PostToolUse` hook that auto-runs the validator only on edited `.xml` files whose root is one of the six validator-owned roots, surfacing failures via exit 2.

**Files:**
- Create: `plugins/dataverse-xml-lsp/hooks/validate-wrapper.mjs`
- Create: `plugins/dataverse-xml-lsp/hooks/hooks.json`
- Create: `plugins/dataverse-xml-lsp/tests/Hook.Tests.ps1`
- Create: `plugins/dataverse-xml-lsp/tests/fixtures/invalid/visualization-wrapper.xml`

**Acceptance Criteria:**
- [ ] `hooks/hooks.json` registers `PostToolUse` with matcher `Edit|Write|MultiEdit` and a command running `node "${CLAUDE_PLUGIN_ROOT}/hooks/validate-wrapper.mjs"`.
- [ ] The gate exits 0 (no validator spawn) for: no file path, non-`.xml` path, and an `.xml` file whose root is not one of `form`, `forms`, `datadefinition`, `visualization`, `viewers`, `importexportxml`.
- [ ] For each of the six owned roots, a valid fixture → exit 0 and an invalid fixture → exit 2 with the validator output on stderr.
- [ ] Matching is case-sensitive: `ImportExportXml` (uppercase, customizations.xml) does NOT match; lowercase `importexportxml` does.

**Verify:** `pwsh -c "Invoke-Pester plugins/dataverse-xml-lsp/tests/Hook.Tests.ps1"` → all pass (validator cases skip if node/schemas absent).

**Steps:**

- [ ] **Step 1: Create the Node gate script**

Create `plugins/dataverse-xml-lsp/hooks/validate-wrapper.mjs`:

```javascript
// PostToolUse gate: auto-run the Dataverse XML validator on the files the live LSP does not cover.
//
// The LSP associates only the authoritative schemas (ribbon, sitemap, fetch, isv.config,
// customizations.xml) by filename. The lag-prone / wrapper types have no live coverage, so we run
// Validate-DataverseXml.ps1 on them post-edit and surface failures to the model (exit 2). The usage
// skill teaches how to read that output (own edits vs OOB noise).
//
// Gate order, cheapest first: no event/path -> 0; not .xml -> 0; root not validator-owned -> 0.
// Exit 0 in those cases is "nothing to do", not a masked error.
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// Validator-owned roots the LSP never associates. Case-sensitive: lowercase 'importexportxml'
// (ParameterXml) is distinct from 'ImportExportXml' (customizations.xml, which the LSP owns).
const OWNED_ROOTS = new Set([
  'form', 'forms', 'datadefinition', 'visualization', 'viewers', 'importexportxml',
]);

function rootElement(file) {
  let xml;
  try { xml = readFileSync(file, 'utf8'); } catch { return null; }
  const cleaned = xml
    .replace(/^﻿/, '')
    .replace(/<\?[\s\S]*?\?>/g, '')
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/<!DOCTYPE[^>]*>/gi, '');
  const m = cleaned.match(/<([A-Za-z_][\w.-]*)/);
  return m ? m[1] : null;
}

let raw = '';
try { raw = readFileSync(0, 'utf8'); } catch { process.exit(0); }
if (!raw.trim()) process.exit(0);

let evt;
try { evt = JSON.parse(raw); } catch { process.exit(0); }

const file = evt?.tool_input?.file_path ?? evt?.tool_output?.file_path;
if (!file || !/\.xml$/i.test(file)) process.exit(0);

const root = rootElement(file);
if (!root || !OWNED_ROOTS.has(root)) process.exit(0);

// hooks/ -> plugin root
const pluginRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const validator = join(pluginRoot, 'scripts', 'Validate-DataverseXml.ps1');
const res = spawnSync('pwsh', ['-NoProfile', '-File', validator, file], { encoding: 'utf8' });

// pwsh missing / spawn failure: can't validate -> don't cry validation-failure.
if (res.error || typeof res.status !== 'number') process.exit(0);
if (res.status === 0) process.exit(0);

const out = [res.stdout, res.stderr].filter(Boolean).join('\n').trim();
process.stderr.write(`Dataverse XML validation failed for ${file}:\n${out}\n`);
process.exit(2);
```

- [ ] **Step 2: Create the hook registration**

Create `plugins/dataverse-xml-lsp/hooks/hooks.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "node \"${CLAUDE_PLUGIN_ROOT}/hooks/validate-wrapper.mjs\""
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 3: Add the missing invalid chart fixture**

Create `plugins/dataverse-xml-lsp/tests/fixtures/invalid/visualization-wrapper.xml` (a `<visualization>` wrapper whose inner `datadefinition` has a bogus child, so fragment validation fails):

```xml
<visualization>
  <datadescription>
    <datadefinition><bogus /></datadefinition>
  </datadescription>
</visualization>
```

- [ ] **Step 4: Create Hook.Tests.ps1**

Create `plugins/dataverse-xml-lsp/tests/Hook.Tests.ps1`:

```powershell
#requires -Version 7
<#
    Drives the PostToolUse gate (hooks/validate-wrapper.mjs) via node with synthetic stdin JSON.
    Gate cases (node only): no-path / non-xml / LSP-owned root -> exit 0, no validator spawn.
    Delegation cases (node + schemas): each validator-owned root's valid fixture -> 0, invalid -> 2.
    Skips when node or the schema set is absent so a minimal CI stays green.
#>

Describe 'wrapper hook gate (validate-wrapper.mjs)' {

    BeforeAll {
        $script:pluginRoot = Split-Path $PSScriptRoot -Parent
        $script:hook = Join-Path $pluginRoot 'hooks' 'validate-wrapper.mjs'
        $script:fixtures = Join-Path $PSScriptRoot 'fixtures'
        $script:haveNode = [bool](Get-Command node -ErrorAction SilentlyContinue)
        $ver = (Get-Content (Join-Path $pluginRoot 'versions.json') -Raw | ConvertFrom-Json).schemaVersion
        $script:haveSchemas = Test-Path (Join-Path $pluginRoot 'schemas' $ver)

        function Invoke-Hook([string]$FilePath) {
            $json = @{ tool_input = @{ file_path = $FilePath } } | ConvertTo-Json -Compress
            $out = $json | & node $script:hook 2>&1
            [pscustomobject]@{ Exit = $LASTEXITCODE; Output = ($out -join "`n") }
        }

        # Each validator-owned root -> its fixture basename under fixtures/{valid,invalid}/.
        $script:ownedFixtures = @(
            @{ Root = 'form';            File = 'form.xml' }
            @{ Root = 'forms';           File = 'forms-wrapper.xml' }
            @{ Root = 'datadefinition';  File = 'datadefinition.xml' }
            @{ Root = 'visualization';   File = 'visualization-wrapper.xml' }
            @{ Root = 'viewers';         File = 'viewers.xml' }
            @{ Root = 'importexportxml'; File = 'parameterxml.xml' }
        )
    }

    It 'exits 0 for a non-xml path (no validator spawn)' {
        if (-not $haveNode) { Set-ItResult -Skipped -Because 'node not on PATH'; return }
        (Invoke-Hook (Join-Path $fixtures 'nope.txt')).Exit | Should -Be 0
    }

    It 'exits 0 for an LSP-owned root (ribbon)' {
        if (-not $haveNode) { Set-ItResult -Skipped -Because 'node not on PATH'; return }
        (Invoke-Hook (Join-Path $fixtures 'valid' 'ribbon.xml')).Exit | Should -Be 0
    }

    It 'exits 0 for uppercase ImportExportXml (customizations.xml, LSP-owned)' {
        if (-not $haveNode) { Set-ItResult -Skipped -Because 'node not on PATH'; return }
        # importexport.xml root is <ImportExportXml> (uppercase) -> NOT in the owned set.
        (Invoke-Hook (Join-Path $fixtures 'valid' 'importexport.xml')).Exit | Should -Be 0
    }

    It 'valid <<root>> fixture -> exit 0' -ForEach $ownedFixtures {
        if (-not $haveNode) { Set-ItResult -Skipped -Because 'node not on PATH'; return }
        if (-not $haveSchemas) { Set-ItResult -Skipped -Because 'schema set not installed'; return }
        (Invoke-Hook (Join-Path $fixtures 'valid' $File)).Exit | Should -Be 0 -Because "$Root valid fixture must pass"
    }

    It 'invalid <<root>> fixture -> exit 2 with validator output' -ForEach $ownedFixtures {
        if (-not $haveNode) { Set-ItResult -Skipped -Because 'node not on PATH'; return }
        if (-not $haveSchemas) { Set-ItResult -Skipped -Because 'schema set not installed'; return }
        $r = Invoke-Hook (Join-Path $fixtures 'invalid' $File)
        $r.Exit | Should -Be 2 -Because "$Root invalid fixture must fail the hook"
        $r.Output | Should -Match 'validation failed'
    }
}
```

- [ ] **Step 5: Verify and commit**

```bash
pwsh -c "Invoke-Pester plugins/dataverse-xml-lsp/tests/Hook.Tests.ps1"
node -e "JSON.parse(require('fs').readFileSync('plugins/dataverse-xml-lsp/hooks/hooks.json','utf8'))" && echo "hooks.json OK"
git add -A plugins/dataverse-xml-lsp
git commit -m "Add PostToolUse wrapper-validation hook for uncovered Dataverse XML roots"
```

Expected: Pester all pass (or validator cases skipped if schemas absent); "hooks.json OK".

---

### Task 4: Version bump, changelog, and doc corrections

**Goal:** Ship the change as 2.1.0 and correct docs that describe the old behaviour.

**Files:**
- Modify: `plugins/dataverse-xml-lsp/.claude-plugin/plugin.json` (`version`)
- Modify: `CHANGELOG.md`
- Modify: `plugins/dataverse-xml-lsp/docs/guide.md:3`
- Modify: `plugins/dataverse-xml-lsp/README.md`

**Acceptance Criteria:**
- [ ] `plugin.json` `version` is `2.1.0`.
- [ ] `CHANGELOG.md` has a `## 2.1.0 — 2026-07-21` entry describing the usage skill, the hook, and the setup-skill `disable-model-invocation` change.
- [ ] `docs/guide.md`'s note no longer claims the plugin "no longer surfaces this automatically" (the usage skill does surface it).
- [ ] `README.md` mentions the usage skill and the hook.
- [ ] The full plugin suite is green.

**Verify:** `pwsh -c "Invoke-Pester plugins/dataverse-xml-lsp"` → all pass; `grep '\"version\"' plugins/dataverse-xml-lsp/.claude-plugin/plugin.json` shows `2.1.0`.

**Steps:**

- [ ] **Step 1: Bump the plugin version**

In `plugins/dataverse-xml-lsp/.claude-plugin/plugin.json`, set `"version": "2.1.0"`.

- [ ] **Step 2: Add a CHANGELOG entry**

At the top of `CHANGELOG.md` (below any header, above `## 2.0.0`), add:

```markdown
## 2.1.0 — 2026-07-21

### dataverse-xml-lsp

- Added a `dataverse-xml-validate` usage skill that auto-triggers on Dataverse customization XML and
  surfaces the `Validate-DataverseXml.ps1` validator (with guidance on reading its indicative output),
  including in headless / subagent / CI contexts where the LSP does not push diagnostics.
- Added a `PostToolUse` hook that auto-runs the validator on edited files whose root is one of the
  six validator-owned roots the LSP does not cover (`form`, `forms`, `datadefinition`,
  `visualization`, `viewers`, `importexportxml`), surfacing failures to the agent.
- The setup skill now carries `disable-model-invocation: true` and lives under
  `skills/dataverse-xml-lsp-setup/` so it no longer competes during editing.
```

- [ ] **Step 3: Correct the guide's stale note**

In `plugins/dataverse-xml-lsp/docs/guide.md`, replace the line:

```
> This is the manual replacement for the old auto-loaded skill; the plugin no longer surfaces this automatically.
```

with:

```
> Full reference for the `dataverse-xml-validate` skill and the validation hook. The skill surfaces the validator automatically on Dataverse-XML work; this guide holds the root→schema table, the ribbon recipe, and the gotchas.
```

- [ ] **Step 4: Mention the new pieces in the README**

In `plugins/dataverse-xml-lsp/README.md`, add these rows to the component table (near the setup-skill row):

```
| `skills/dataverse-xml-validate/SKILL.md` | Auto-triggering usage skill: surfaces the validator + how to read its output |
| `hooks/validate-wrapper.mjs`, `hooks/hooks.json` | PostToolUse hook: auto-validates edited forms/charts/viewers/parameter/whole-customizations files the LSP doesn't cover |
```

- [ ] **Step 5: Verify and commit**

```bash
pwsh -c "Invoke-Pester plugins/dataverse-xml-lsp"
grep '"version"' plugins/dataverse-xml-lsp/.claude-plugin/plugin.json
git add -A plugins/dataverse-xml-lsp CHANGELOG.md
git commit -m "Release dataverse-xml-lsp 2.1.0: validator discoverability skill + hook"
```

Expected: full plugin Pester suite green; version shows 2.1.0.

---

## Manual verification (after all tasks — interactive, not automatable)

The auto-trigger and hook-firing behaviours can only be confirmed in a live Claude Code session:

1. `/plugin update dataverse-xml-lsp@dataverse-agent-plugins` (or reinstall), then `/reload-plugins`.
2. Confirm the XML LSP still attaches (no new load error introduced).
3. Edit a pac-unpacked form/chart file with a deliberate schema break → confirm the hook reports the failure.
4. Confirm the `dataverse-xml-lsp-setup` skill no longer auto-surfaces during ordinary editing.

---

## Self-Review

**Spec coverage:** usage skill (Task 2), setup-skill `disable-model-invocation` (Task 1), wrapper hook + six roots + case-sensitivity (Task 3), skill body carries description+headless+OOB-rule and points to guide (Task 2), tests for skill/hook/fixtures (Tasks 1–3), 2.1.0 + docs (Task 4), "why not fix the LSP" is a spec decision requiring no code. All covered.

**Placeholder scan:** every code/file step contains full content; no TBDs. Pass.

**Type/name consistency:** skill dir names, the six roots, `OWNED_ROOTS`, fixture basenames, and `plugin.json` `skills` paths match across Tasks 1–4. Pass.
