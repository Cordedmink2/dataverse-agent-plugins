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
