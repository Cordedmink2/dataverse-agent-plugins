# dataverse-xml-lsp

A Claude Code plugin for **schema-validated hand-editing of Dataverse / model-driven-app
customization XML** — ribbon buttons (`RibbonDiffXml`), app navigation (`SiteMap`), forms
(`FormXml`), FetchXML, charts, and the whole `Customizations.xml`. Malformed edits fail loud
*before* `pac solution import`.

**See [`docs/guide.md`](docs/guide.md) for editing guidance.**

## Two validation layers

1. **Script (backbone)** — `pwsh scripts/Validate-DataverseXml.ps1 <file>`. Works from any
   tool/shell/CI (Claude, Codex, pipelines). No Java, no network.
2. **LSP (live)** — lemminx pushes diagnostics as you edit. Wired for Claude Code (this plugin's
   `.lsp.json`) and VS Code (RedHat XML extension via `xml.fileAssociations`).

## Install (Claude Code)

```
/plugin marketplace add Cordedmink2/dataverse-agent-plugins
/plugin install dataverse-xml-lsp@dataverse-agent-plugins
/dataverse-xml-lsp:dataverse-xml-lsp-setup
```

The setup command fetches the Microsoft XSDs and the lemminx binary, stamps this machine's
absolute paths, and runs a self-check. It requires PowerShell 7+ (`pwsh`) — Windows ships
only Windows PowerShell 5.1, and the scripts have `#requires -Version 7`. Then run
`/reload-plugins` (or restart the session) so the LSP starts with the stamped paths.

## Setup script directly (non-Claude consumers)

The slash command is a thin wrapper around one idempotent script:

```
pwsh scripts/Install-Plugin.ps1 [-UpdateVSCode] [-SkipLemminx] [-TargetPlatform <win32-x64|linux-x64|darwin-x64|darwin-arm64>]
```

- `-UpdateVSCode` also writes `xml.fileAssociations` into your VS Code user settings.
- `-SkipLemminx` skips the ~47 MB LSP binary — validator-only setup (fine for CI and non-Claude
  agents).
- `-TargetPlatform` overrides the auto-detected OS/arch for the lemminx download.

Run this one script rather than the individual `Get-*`/`Set-*` scripts — a partial manual setup
can leave a running lemminx pointing at broken relative schema paths.

## What's inside

| Path | Purpose |
|------|---------|
| `SKILL.md` | Tiny no-description setup skill (runs `Install-Plugin.ps1`) |
| `scripts/Install-Plugin.ps1` | One-shot setup: schemas + lemminx + path stamping + self-check |
| `scripts/Validate-DataverseXml.ps1` | Standalone validator — root-element → XSD, line/col errors, non-zero exit |
| `scripts/Get-Schemas.ps1` | Download the official Microsoft XSDs into `schemas/<version>/` |
| `scripts/Get-Lemminx.ps1` | Download the native lemminx binary into `bin/` (SHA256-verified) |
| `scripts/Set-LspSchemaPaths.ps1` | Stamp this machine's absolute schema paths into `.lsp.json` (+ VS Code) |
| `.lsp.json` | Registers lemminx with Claude Code, with XSD `fileAssociations` |
| `versions.json` | Pinned schema version/URL and lemminx (vscode-xml) version |
| `schemas/SOURCE.md` | Where the XSDs come from and how to bump the version |
| `tests/` | Pester suite + valid/invalid fixtures for every mapped root |
| `docs/` | Guides for Codex, VS Code-only, and debugging |

The Microsoft XSDs (`schemas/<version>/`) and the lemminx binary (`bin/`) are **fetched at
setup, not shipped** — the XSDs are Microsoft-copyrighted and the binary is large and
platform-specific.

## Updating

```
/plugin marketplace update dataverse-agent-plugins
/plugin update dataverse-xml-lsp@dataverse-agent-plugins
/dataverse-xml-lsp:dataverse-xml-lsp-setup
```

Re-run setup after every update — it re-stamps paths and re-checks the fetched assets (see
`docs/debugging.md` for why). Schema-version bumps are driven by `versions.json`; the procedure
is in `schemas/SOURCE.md`.

## Other consumers

- **Codex / any non-Claude agent** — see [`docs/codex.md`](docs/codex.md).
- **VS Code only (no agent)** — see [`docs/vscode.md`](docs/vscode.md).
- **CI / pre-commit** — call the validator script directly:
  `pwsh scripts/Validate-DataverseXml.ps1 <files-or-globs>` (non-zero exit on failure).

Something not working? [`docs/debugging.md`](docs/debugging.md).

## Known caveats

- **Whole `Customizations.xml` validation is indicative only** — the `9.0.0.2090` schema lags
  current Dataverse exports (newer attributes/elements report as "not declared"). RibbonDiff /
  SiteMap fragment validation is authoritative; FormXml is indicative (the schema lags modern
  form attributes like `headerdensity`, `contenttype`).
- **`${CLAUDE_PLUGIN_ROOT}` is only substituted in `.lsp.json` `command`/`args`**, not in nested
  `settings` — hence the absolute-path fixup script.

## License

The plugin is MIT-licensed (see the repo root `LICENSE`). The Microsoft XSDs are downloaded
from Microsoft at setup time and remain subject to Microsoft's terms — they are not
redistributed in this repo.

See [`docs/guide.md`](docs/guide.md) for the ribbon-button recipe and the full edit → validate → pack → import loop.
