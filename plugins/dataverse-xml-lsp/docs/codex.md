# Using this plugin with Codex (or any non-Claude agent)

The **validator script is the whole story** for agents other than Claude Code: LSP
diagnostics only push into Claude Code's main session, so every other agent must run the
script after each edit.

## Setup

1. Clone the repo and run setup (no LSP needed, so skip the binary):

   ```
   pwsh plugins/dataverse-xml-lsp/scripts/Install-Plugin.ps1 -SkipLemminx
   ```

   This fetches the Microsoft XSDs and runs a self-check; requires PowerShell 7+ (`pwsh`).

2. Make the skill discoverable. Codex reads `AGENTS.md` — add:

   > When editing Dataverse customization XML (RibbonDiff.xml, SiteMap, FormXml,
   > Customizations.xml, FetchXML, charts), follow
   > `<clone-path>/plugins/dataverse-xml-lsp/docs/guide.md`, and after EVERY edit run:
   > `pwsh <clone-path>/plugins/dataverse-xml-lsp/scripts/Validate-DataverseXml.ps1 <file>`
   > Non-zero exit = the edit is invalid; fix before pack/import.

3. If your Codex setup supports skill folders, point it at
   `plugins/dataverse-xml-lsp/docs/guide.md` directly for the full editing guidance.

## The loop

edit → `Validate-DataverseXml.ps1 <file>` → fix until PASS → `pac solution pack` → import.
