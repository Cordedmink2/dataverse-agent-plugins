---
name: dataverse-xml-lsp-setup
---

# dataverse-xml-lsp setup

This plugin is a lemminx XML LSP for Dataverse customization XML (plus `scripts/Validate-DataverseXml.ps1` for CI/headless). Run once per machine:

`pwsh "${CLAUDE_PLUGIN_ROOT}/scripts/Install-Plugin.ps1"` (add `-UpdateVSCode` to also wire VS Code). Then run `/reload-plugins`. If it fails, see `docs/debugging.md`. Editing guidance: `docs/guide.md`.
