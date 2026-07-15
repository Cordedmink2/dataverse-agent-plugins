# dataverse-customization-xml

A global Claude Code plugin for **schema-validated hand-editing of Dataverse / model-driven-app
customization XML** — ribbon buttons (`RibbonDiffXml`), app navigation (`SiteMap`), forms
(`FormXml`), and the whole `Customizations.xml`. Malformed edits fail loud *before*
`pac solution import`.

## What's inside

| Path | Purpose |
|------|---------|
| `schemas/9.0.0.2090/` | The 12 official Microsoft XSDs (see `schemas/SOURCE.md`) |
| `scripts/Validate-DataverseXml.ps1` | Standalone validator — root-element → XSD, line/col errors, non-zero exit |
| `scripts/Set-LspSchemaPaths.ps1` | Stamp this machine's absolute schema paths into `.lsp.json` (+ VS Code) |
| `bin/lemminx-win32.exe` | Native lemminx XML language server (GraalVM build; no Java) |
| `.lsp.json` | Registers lemminx with Claude Code, with XSD `fileAssociations` |
| `SKILL.md` | The skill: workflow, ribbon-button recipe, gotchas |

## Two validation layers

1. **Script (backbone)** — `pwsh scripts/Validate-DataverseXml.ps1 <file>`. Works from any
   tool/shell/CI (Claude, Codex, pipelines). No Java, no network.
2. **LSP (live)** — lemminx pushes diagnostics as you edit. Wired for Claude Code (this plugin's
   `.lsp.json`) and VS Code (RedHat XML extension via `xml.fileAssociations`).

## Install on a new machine

1. Sync the plugin into `~/.claude/skills/dataverse-customization-xml/` (via the `claude-skills`
   repo). It auto-loads as `dataverse-customization-xml@skills-dir`.
2. `pwsh scripts/Get-Lemminx.ps1` — downloads the native lemminx binary into `bin/` (it's ~47 MB
   and platform-specific, so it is **not** committed; use `-TargetPlatform` for non-Windows).
3. `pwsh scripts/Set-LspSchemaPaths.ps1 -UpdateVSCode` — fixes absolute schema paths for this
   machine (`${CLAUDE_PLUGIN_ROOT}` isn't substituted inside `.lsp.json` settings).
4. `/reload-plugins` (Claude) and restart VS Code.
5. For live VS Code validation, install `redhat.vscode-xml`.

The standalone validator (`scripts/Validate-DataverseXml.ps1`) needs none of the above — only the
lemminx LSP layer requires the binary in `bin/`.

## Known caveats

- **Whole `Customizations.xml` validation is indicative only** — the `9.0.0.2090` schema lags
  current Dataverse exports (newer attributes/elements report as "not declared"). Fragment
  validation (RibbonDiff / SiteMap / FormXml) is authoritative.
- **`${CLAUDE_PLUGIN_ROOT}` is only substituted in `.lsp.json` `command`/`args`**, not in nested
  `settings` — hence the absolute-path fixup script.

See `SKILL.md` for the ribbon-button recipe and the full edit → validate → pack → import loop.
