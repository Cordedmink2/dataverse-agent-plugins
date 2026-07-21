# dataverse-xml-lsp — validator discoverability design

**Date:** 2026-07-21
**Status:** Approved design, pre-implementation
**Author:** Connor Parsons

## Summary

The `dataverse-xml-lsp` plugin (v2.0.0) is a lemminx LSP plus a retained CLI validator,
`scripts/Validate-DataverseXml.ps1`. The 2.0.0 restructure left the validator **undiscoverable**:
nothing tells an agent it exists or when to run it, and editing guidance was moved to
`docs/guide.md` (which is passive — the agent never sees it unless pointed there).

This change closes that gap with two small, additive pieces:

1. A **usage skill** (`dataverse-xml-validate`) carrying a keyword-rich `description`, so it
   auto-loads when the agent works on Dataverse customization XML. It teaches *when* to run the
   validator and *how to read its output*; it carries no editing recipes.
2. A **wrapper hook** — a `PostToolUse` hook, shipped with the plugin, that auto-runs the validator
   on the files the LSP structurally does not cover.

Both call the single existing validator — no second validation path is introduced.

## Verified facts this design rests on

These were checked against the code, the bundled XSDs, and Microsoft Learn — not assumed.

- **Skill auto-trigger:** a skill auto-triggers whenever the model finds its name+description
  relevant; the description (or, if absent, the first body paragraph) is always in context
  (name+description capped ~1536 chars), full body loads on invoke. Omitting `description` does
  **not** disable auto-trigger — only `disable-model-invocation: true` does. (Claude Code skills
  docs.)
- **Multiple skills per plugin:** supported via a `skills/<name>/SKILL.md` directory layout.
- **LSP association is by filename glob** (in `scripts/lsp-launch.mjs`), not by root element. The six
  globs cover: `RibbonDiff.xml`→RibbonCore, `[Cc]ustomizations.xml`→CustomizationsSolution,
  `SiteMap*.xml`→SiteMap, `SavedQueries/**`+`*.fetchxml`→Fetch, `isv.config.xml`→isv.config.
- **Bundled XSD roots:** `FormXml.xsd`→`<form>`, `VisualizationDataDescription.xsd`→`<datadefinition>`,
  `reports.config.xsd`→`<viewers>`, `ParameterXml.xsd`→`<importexportxml>` (lowercase),
  `CustomizationsSolution.xsd`→`<ImportExportXml>`. Neither `FormXml.xsd` nor
  `VisualizationDataDescription.xsd` declares the `<forms>`/`<visualization>` **wrapper** roots.
- **Microsoft does not document the on-disk file layout** `pac solution unpack` writes for forms and
  charts (only the packed `customizations.xml` structure: `ImportExportXml > Entities > Entity >
  FormXml > forms(@type) > form`, individual form root `<form>`). Real tool output is the only
  authority for on-disk file naming.

## Why not fix the LSP instead of adding a hook

The obvious alternative — make lemminx validate these files live — was evaluated and rejected:

- **Wrapper files can't be associated cleanly.** `<forms>`/`<visualization>` are not declared roots
  in the leaf XSDs (verified above), so lemminx errors on the wrapper root. A thin wrapper XSD is
  *authorable* (`CustomizationsSolution.xsd` already defines `SystemFormsType`/`systemform`), but it
  is bespoke schema to hand-maintain.
- **Even the singular-root files should not be live-validated.** Every validator-owned type is an
  **indicative-only / lagging** schema (the documented `9.0.0.2090` gotcha: modern form/chart
  attributes aren't declared → false "not declared" errors). The LSP's existing association set is
  exactly the **authoritative, stable** schemas (RibbonCore, SiteMap, Fetch, isv.config); the
  complement it omits is exactly the **lag-prone** ones. The boundary already tracks schema
  trustworthiness. Live diagnostics on lag-prone forms/charts would flood the editor with false
  positives and train everyone to ignore squiggles — a downgrade.
- **No documented glob to associate on.** Microsoft doesn't specify the unpacked file layout, so a
  reliable lemminx file-association pattern can't be derived from docs anyway.

Conclusion: keep live validation limited to the trustworthy schemas (unchanged), and reach the
lag-prone/wrapper files through the **deliberately-run** validator — surfaced post-edit by a hook and
interpreted with the guidance the skill carries.

## Decisions

| Question | Decision |
|---|---|
| Discoverability mechanism | Both: a usage skill (judgment + interpretation + headless reach) **and** a wrapper hook (deterministic post-edit trigger) |
| Fix the LSP for these files? | No — see "Why not fix the LSP". Live validation stays limited to the authoritative schemas |
| Usage-skill shape | A second skill under `skills/dataverse-xml-validate/`, WITH a keyword-rich `description` adapted from the original fat skill. Contains *when to run* + *how to read output* only; recipes/tables stay in `docs/guide.md` |
| Setup-skill correction | Add `disable-model-invocation: true` to the existing `dataverse-xml-lsp-setup` skill so it stops auto-competing during normal editing (it is a one-time manual action) |
| Hook scope (roots) | All six validator-owned roots the LSP never covers: `form`, `forms`, `datadefinition`, `visualization`, `viewers`, `importexportxml` (lowercase). Ordinary customization XML (ribbon, sitemap, fetch, isv.config, uppercase customizations) is left to the live LSP |
| Hook gate location | In the hook script, not the matcher. Non-`.xml` path → exit 0 immediately; else peek the root element and proceed only for the six roots |
| Hook script runtime | Node (fast startup; already a hard dependency of the LSP shim) for the cheap gate, delegating validation to the single existing pwsh validator |
| Hook failure behaviour | Validation failure → **exit 2** with validator output on stderr (fail-loud: the model is told immediately and interprets it via the skill's OOB-noise rule). Pass / non-matching → exit 0, silent |
| Cry-wolf mitigation | The lag means the validator can report OOB false positives on valid files. The skill teaches the model to grep the output for *its own* element/attribute names and treat pre-existing OOB errors as expected — the interpretation the validator's design assumes |
| Validation source of truth | The one existing `Validate-DataverseXml.ps1`. No second validator |
| Plugin-hook wiring | `plugins/dataverse-xml-lsp/hooks/hooks.json`; auto-active once the plugin is enabled; `${CLAUDE_PLUGIN_ROOT}` expands in the command |
| Version | Additive, non-breaking → bump `dataverse-xml-lsp` to **2.1.0** |
| Platform | Node for the hook gate; PowerShell 7 (`pwsh`) for the validator, as today |

## Architecture

### Components

| Unit | Single purpose |
|------|----------------|
| `skills/dataverse-xml-validate/SKILL.md` | Auto-triggering usage skill: teaches *when* to run the validator (headless/subagent, wrapper/lag-prone files, pre-pack gate) and *how* to read its output |
| `skills/dataverse-xml-lsp-setup/SKILL.md` | The existing setup skill, relocated under `skills/` and given `disable-model-invocation: true` |
| `hooks/hooks.json` | Registers the `PostToolUse` hook on `Edit\|Write\|MultiEdit` |
| `hooks/validate-wrapper.mjs` | Node gate: read hook stdin → decide whether the edited file is a validator-owned root → run the validator and translate its exit code |
| `.claude-plugin/plugin.json` | Points `skills` at both skill directories; version → 2.1.0 |
| `scripts/Validate-DataverseXml.ps1` | Unchanged — the single validation backbone both pieces call |

### Component 1 — usage skill (`dataverse-xml-validate`)

- **Path:** `plugins/dataverse-xml-lsp/skills/dataverse-xml-validate/SKILL.md`.
- **Frontmatter:** `name: dataverse-xml-validate` plus a keyword-rich `description` adapted from the
  original fat skill — e.g. *"Use when editing, reviewing, or validating Dataverse / model-driven-app
  customization XML — RibbonDiff.xml, Customizations.xml, SiteMap, FormXml (forms), charts, FetchXML —
  especially in headless/subagent/CI contexts or before `pac solution pack`/`import`. Runs the
  schema validator (Validate-DataverseXml.ps1)."* (Keep under the ~1536-char name+description cap;
  key use case first.)
- **Body (tight):**
  - The command: `pwsh "${CLAUDE_PLUGIN_ROOT}/scripts/Validate-DataverseXml.ps1" <files-or-dir>`.
  - *When*: headless/subagent edits (the live LSP doesn't push there), the lag-prone/wrapper files
    (forms, charts, viewers, parameter XML, whole customizations.xml), and as a pre-pack gate.
  - *How to read output* (the interpretation layer, adapted from the original gotcha): whole-form /
    whole-file validation is **indicative** — grep the output for your own element/attribute names;
    treat pre-existing OOB "not declared" errors as expected noise. The ribbon fragment is
    authoritative.
  - Pointer to `docs/guide.md` for the full root→schema table and the ribbon recipe. **No** editing
    recipes inline.

### Component 2 — wrapper hook

Registered in `plugins/dataverse-xml-lsp/hooks/hooks.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          { "type": "command", "command": "node \"${CLAUDE_PLUGIN_ROOT}/hooks/validate-wrapper.mjs\"" }
        ]
      }
    ]
  }
}
```

`hooks/validate-wrapper.mjs` logic:

1. Read the full hook JSON from stdin; take `tool_input.file_path` (fall back to
   `tool_output.file_path`). No path → exit 0.
2. If the path does not end in `.xml` (case-insensitive) → exit 0 immediately (the cheap common
   case; no file read).
3. Peek the root element name (first element of the file). If it is **not** one of
   `form`, `forms`, `datadefinition`, `visualization`, `viewers`, `importexportxml` (case-sensitive:
   lowercase `importexportxml` is ParameterXml, distinct from `ImportExportXml`) → exit 0.
4. Otherwise spawn `pwsh -File <plugin>/scripts/Validate-DataverseXml.ps1 <file>`, capturing output.
   - Validator exit 0 → hook exit 0 (silent).
   - Validator non-zero → write the captured validator output to **stderr** and **exit 2**.

The edit has already landed when the hook runs (documented PostToolUse behaviour); exit 2 is a
post-edit signal, not a block. The skill's interpretation rule is what keeps exit-2 from crying wolf.

### Data flow

**Interactive main session, editing a form file:**
```
Edit .../<entity>/FormXml/.../form.xml  → PostToolUse → validate-wrapper.mjs
  root ∈ {form,forms,...}?  yes → Validate-DataverseXml.ps1
     non-zero → exit 2, stderr → model sees output → applies skill's grep-your-own-names rule → fixes real errors
     zero     → exit 0 (silent)
```

**Editing ordinary customization XML (RibbonDiff, SiteMap, fetch, isv.config, Customizations.xml):**
root not in the six → hook exit 0. The live LSP handles it; no double validation, no lag noise.

**Headless / subagent / pre-pack:** the usage skill (auto-loaded via its description, or invoked
explicitly) tells the agent to run `Validate-DataverseXml.ps1` over the target files.

## Boundaries & fail-loud

- **One validator, one truth.** Skill and hook both call `Validate-DataverseXml.ps1`.
- **Fail loud, don't mask:** the hook surfaces validation failures via exit 2 rather than swallowing
  them. It exits 0 only for genuinely-not-our-concern cases (non-xml, non-matching root) — valid
  "nothing to do" outcomes, not masked errors. The skill supplies the interpretation the validator's
  output assumes, so fail-loud does not become cry-wolf.

## Testing

Pester (existing suite) plus a Node test for the hook gate:

- **Usage skill:** `dataverse-xml-validate/SKILL.md` has a **non-empty** `description`, and both skills
  are discovered by the plugin (assert `plugin.json` `skills` resolves both directories).
- **Setup skill:** `dataverse-xml-lsp-setup` frontmatter now carries `disable-model-invocation: true`.
- **Hook registration:** `hooks/hooks.json` parses, targets `PostToolUse` with an
  `Edit|Write|MultiEdit` matcher and a command referencing `validate-wrapper.mjs`.
- **Hook gate (`validate-wrapper.mjs`), driven with synthetic stdin JSON:**
  - non-`.xml` `file_path` → exit 0, no validator spawn.
  - `.xml` file whose root is `RibbonDiffXml` (LSP-owned) → exit 0, no validator spawn.
  - each of the six validator-owned roots, valid fixture → exit 0; invalid fixture → exit 2 with
    validator output on stderr.
  - Reuse existing `tests/fixtures/{valid,invalid}/` (which already cover `form`, `forms-wrapper`,
    `datadefinition`, `visualization-wrapper`, `viewers`, `parameterxml`).

Verify command: `Invoke-Pester plugins` green, and the Node hook test green.

## Out of scope

- Any change to the validator's behaviour or schema set (including the noted `<visualization>` vs
  `<datadefinition>` root ambiguity — a follow-up to check against real pac output, not this change).
- Associating any of these file types with the live LSP (rejected above).
- A hook for the flow (`cloud-flow-json-lsp`) plugin — this change is XML-only.
- The previously-deferred bespoke flow validator CLI.

## Success criteria

- An agent editing a schema-invalid pac-unpacked form/chart/viewers/parameter file is told so
  immediately (exit 2 feedback), and — via the skill — reads the output correctly (own edits vs OOB
  noise), without the user prompting.
- An agent working on Dataverse XML in a headless/subagent context has the validator surfaced via the
  usage skill.
- Editing ordinary customization XML produces no hook output and no extra validation.
- The setup skill no longer auto-competes during editing.
- `Invoke-Pester plugins` is green, including the new skill/hook tests. Version is 2.1.0.
