# dataverse-xml-lsp — validator discoverability design

**Date:** 2026-07-21
**Status:** Approved design, pre-implementation
**Author:** Connor Parsons

## Summary

The `dataverse-xml-lsp` plugin (v2.0.0) is a lemminx LSP plus a retained CLI validator,
`scripts/Validate-DataverseXml.ps1`. The 2.0.0 restructure removed the fat auto-triggering skill in
favour of a single no-`description` setup skill, which means the validator is now effectively
**invisible to the agent** during normal work — nothing tells an agent it exists or when to run it,
and the setup skill deliberately does not auto-trigger.

This change closes that discoverability gap with two small, additive pieces:

1. A **usage skill** (`dataverse-xml-validate`) — a *second* skill in the plugin, this one carrying a
   `description` so it auto-loads when the agent works on Dataverse customization XML. It teaches
   *when* to reach for the validator; it carries no editing recipes.
2. A **wrapper hook** — a `PostToolUse` hook, shipped with the plugin, that auto-runs the validator
   **only** on the pac form/chart wrapper files the LSP structurally cannot cover.

Both call the single existing validator — no second validation path is introduced.

## Why

The LSP covers exactly one situation: the **main interactive session, editing an LSP-associated file
type**. The validator is the channel for everything the LSP cannot reach:

- **Wrapper files (the permanent gap):** `<forms>` and `<visualization>` (pac-unpacked form/chart
  wrappers) are deliberately **not** LSP-associated — lemminx false-positives on the wrapper root — so
  the validator owns them via per-fragment validation.
- **Headless / CI / subagent edits:** no LSP diagnostic push reaches these contexts.
- **Pre-pack gate:** a deliberate sweep before `pac solution pack`/`import`.

The skill closes the "agent knows in every context" half (a subagent sees skill descriptions and can
invoke a skill; a hook's reach into subagents is not guaranteed). The hook closes the "wrapper files
get checked even when the agent forgets" half, deterministically.

## Decisions

| Question | Decision |
|---|---|
| Discoverability mechanism | Both: a usage skill (judgment/discoverability) **and** a narrow wrapper hook (deterministic enforcement) |
| Usage-skill shape | A *second* skill under the plugin, WITH a `description` so it auto-triggers on Dataverse-XML context; contains only "here's the validator and when", no editing recipes |
| Hook scope | Fires only on wrapper files — root element `forms` or `visualization`. Ordinary customization XML (ribbon, sitemap, etc.) is left alone: the LSP already covers it live, and auto-validating it would surface the pinned-schema indicative-only false positives |
| Hook gate location | In the hook script, not the matcher (matcher only filters by tool name). Non-`.xml` path → exit 0 immediately; else peek the root element |
| Hook script runtime | Node (fast startup; already a hard dependency of the LSP shim) for the cheap gate, delegating actual validation to the single existing pwsh validator |
| Hook failure behaviour | Validation failure → **exit 2** with validator output on stderr (fail-loud: the model is told immediately). Pass / non-wrapper / non-xml → exit 0, silent |
| Validation source of truth | The one existing `Validate-DataverseXml.ps1`. No second validator |
| Plugin-hook wiring | `plugins/dataverse-xml-lsp/hooks/hooks.json`; auto-active once the plugin is enabled; `${CLAUDE_PLUGIN_ROOT}` expands in the command |
| Version | Additive, non-breaking → bump `dataverse-xml-lsp` to **2.1.0** |
| Platform | Node for the hook gate; PowerShell 7 (`pwsh`) for the validator, as today |

## Architecture

### Components

| Unit | Single purpose |
|------|----------------|
| `skills/dataverse-xml-validate/SKILL.md` | Auto-triggering usage skill: teaches *when* to run the validator (headless/subagent, wrapper files, pre-pack gate) and the false-positive caveat |
| `hooks/hooks.json` | Registers the `PostToolUse` hook on `Edit\|Write\|MultiEdit` |
| `hooks/validate-wrapper.mjs` | Node gate: read hook stdin → decide whether the edited file is a validator-owned wrapper file → run the validator and translate its exit code |
| `.claude-plugin/plugin.json` | Adds the new skill path to `skills`; version → 2.1.0 |
| `scripts/Validate-DataverseXml.ps1` | Unchanged — the single validation backbone both pieces call |

### Component 1 — usage skill (`dataverse-xml-validate`)

- **Path:** `plugins/dataverse-xml-lsp/skills/dataverse-xml-validate/SKILL.md`, added to `plugin.json`'s
  `skills` array (which today is `["./"]` → becomes `["./", "./skills/dataverse-xml-validate"]`).
- **Frontmatter:** `name: dataverse-xml-validate` plus a `description` that matches the working
  context, e.g. *"Use when editing, reviewing, or validating Dataverse customization XML (ribbon,
  sitemap, forms, FetchXML, charts) — especially in headless/subagent/CI contexts or before
  `pac solution pack`/`import` — to run the schema validator."*
- **Body (tight):**
  - The one command: `pwsh "${CLAUDE_PLUGIN_ROOT}/scripts/Validate-DataverseXml.ps1" <files-or-dir>`.
  - *When*: headless/subagent edits, the form/chart wrapper files, and as a pre-pack gate.
  - What it covers that the live LSP does not (headless reach + the wrapper files).
  - The indicative-only false-positive caveat (pinned `9.0.0.2090` schema; grep errors for your own
    element/attribute names).
  - Pointer to `docs/guide.md`. **No** editing recipes — those stay in the guide.
- This is categorically not the fat skill removed in 2.0.0: setup stays manual (no description);
  usage auto-triggers (has a description). Clean split.

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
3. Peek the root element name (read the first element of the file). If it is **not** `forms` or
   `visualization` → exit 0. This is the boundary: the LSP owns everything else in the main session.
4. Otherwise spawn `pwsh -File <plugin>/scripts/Validate-DataverseXml.ps1 <file>`, inheriting/capturing
   output.
   - Validator exit 0 → hook exit 0 (silent).
   - Validator non-zero → write the captured validator output to **stderr** and **exit 2**, so the
     model is told the wrapper edit is invalid and should fix it.

The edit has already landed when the hook runs (documented PostToolUse behaviour); exit 2 is a
post-edit signal, not a block.

### Data flow

**Interactive main session, editing a wrapper file:**
```
Edit .../Entities/<entity>/FormXml/.../form.xml  → PostToolUse → validate-wrapper.mjs
  root == <forms>?  yes → Validate-DataverseXml.ps1
     invalid → exit 2, stderr → model sees the schema errors → fixes
     valid   → exit 0 (silent)
```

**Editing ordinary customization XML (e.g. RibbonDiff):** hook sees root not in
{forms, visualization} → exit 0. The live LSP handles it; no double validation, no false-positive
noise.

**Headless / subagent / pre-pack:** the usage skill (auto-loaded via its description, or invoked
explicitly) tells the agent to run `Validate-DataverseXml.ps1` over the target files.

## Boundaries & fail-loud

- **One validator, one truth.** Skill and hook both call `Validate-DataverseXml.ps1`. The
  root-element boundary (`forms`/`visualization` = validator-owned) mirrors the validator's own
  `$innerElementByRoot` map — stated once.
- **Fail loud, don't mask** (repo principle): the hook does not swallow validation failures — it
  surfaces them via exit 2. The validator already exits non-zero on failure and lists unknown roots.
  The hook gate itself stays minimal: it exits 0 only for the genuinely-not-our-concern cases
  (non-xml, non-wrapper root), which are valid "nothing to do" outcomes, not masked errors.

## Testing

Pester (existing suite) plus a Node test for the hook gate:

- **Skill:** `dataverse-xml-validate/SKILL.md` has a **non-empty** `description` (contrast the setup
  skill, which must stay empty), and its path is present in `plugin.json`'s `skills` array.
- **Hook registration:** `hooks/hooks.json` parses, targets `PostToolUse` with an `Edit|Write|MultiEdit`
  matcher and a command referencing `validate-wrapper.mjs`.
- **Hook gate (`validate-wrapper.mjs`), driven with synthetic stdin JSON:**
  - non-`.xml` `file_path` → exit 0, no validator spawn.
  - `.xml` file whose root is `RibbonDiffXml` (LSP-owned) → exit 0, no validator spawn.
  - valid `<forms>`/`<visualization>` wrapper fixture → exit 0.
  - invalid wrapper fixture → exit 2, validator output on stderr.
  - Reuse existing `tests/fixtures/{valid,invalid}/` where a wrapper fixture exists; add a minimal
    wrapper fixture pair if none is present.

Verify command: `Invoke-Pester plugins` green, and the Node hook test green.

## Out of scope

- Any change to the validator's behaviour or schema set.
- A hook for the flow (`cloud-flow-json-lsp`) plugin — this change is XML-only.
- Broadening the hook to non-wrapper roots (would reintroduce false-positive noise).
- The previously-deferred bespoke flow validator CLI.

## Success criteria

- An agent editing a pac-unpacked `<forms>`/`<visualization>` file that is schema-invalid is told so
  immediately (exit 2 feedback), without the user prompting.
- An agent working on Dataverse XML in a headless/subagent context has the validator surfaced via the
  usage skill.
- Editing ordinary customization XML produces no hook output and no extra validation.
- `Invoke-Pester plugins` is green, including the new skill/hook tests. Version is 2.1.0.
