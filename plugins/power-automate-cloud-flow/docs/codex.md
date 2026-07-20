# Using this plugin with Codex (or any non-Claude agent)

LSP diagnostics only push into Claude Code's main session, so every other agent must validate
explicitly after each edit. There is no bespoke validator script — PowerShell 7's built-in
`Test-Json` validates against the same bundled schema the LSP loads.

## Setup

1. Clone the repo. No server install is needed for the `Test-Json` path (that's only for the LSP),
   but PowerShell 7+ (`pwsh`) is required.

2. Make the skill discoverable. Codex reads `AGENTS.md` — add:

   > When editing an unpacked Power Automate solution cloud flow (`Workflows/*.json` — the flow
   > clientdata: WDL `definition` + `connectionReferences`), follow
   > `<clone-path>/plugins/power-automate-cloud-flow/SKILL.md`, and after EVERY edit run:
   > `Get-Content <file> -Raw | Test-Json -SchemaFile <clone-path>/plugins/power-automate-cloud-flow/schemas/cloud-flow-clientdata.schema.json`
   > A schema error means the edit is structurally invalid; fix before pack/import. Then run the
   > `power-automate-flow-dev` skill's `flow-lint.ps1` for the semantic layer (runAfter /
   > connectionName resolution, hard-coded values).

3. If your Codex setup supports skill folders, point it at `plugins/power-automate-cloud-flow/`
   directly — `SKILL.md` has standard frontmatter.

## The loop

edit → `Test-Json -SchemaFile <schema> <file>` (structure) → `flow-lint.ps1` (semantics) → fix until
clean → `pac solution pack` → import.
