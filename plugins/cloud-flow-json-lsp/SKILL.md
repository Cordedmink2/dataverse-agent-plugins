---
name: cloud-flow-json-lsp-setup
---

# cloud-flow-json-lsp setup

This plugin is a JSON LSP for unpacked Power Automate cloud-flow clientdata (`Workflows/*.json`). Run once per machine:

`pwsh "${CLAUDE_PLUGIN_ROOT}/scripts/Install-Plugin.ps1"` (add `-UpdateVSCode` to also wire VS Code). Then run `/reload-plugins`. If it fails, see `docs/debugging.md`. Editing guidance: `docs/guide.md`.
