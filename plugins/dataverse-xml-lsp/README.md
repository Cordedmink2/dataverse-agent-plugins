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

The setup command fetches the Microsoft XSDs and the lemminx binary and runs a self-check. It
requires PowerShell 7+ (`pwsh`) — Windows ships only Windows PowerShell 5.1, and the scripts
have `#requires -Version 7`. Then run `/reload-plugins` (or restart the session) so the LSP
starts. The launcher shim resolves the bundled schema at runtime, so nothing machine-specific
is stamped into `.lsp.json`.

## Setup script directly (non-Claude consumers)

The slash command is a thin wrapper around one idempotent script:

```
pwsh scripts/Install-Plugin.ps1 [-UpdateVSCode] [-SkipLemminx] [-TargetPlatform <win32-x64|linux-x64|darwin-x64|darwin-arm64>]
```

- `-UpdateVSCode` also writes `xml.fileAssociations` into your VS Code user settings.
- `-SkipLemminx` skips the ~47 MB LSP binary — validator-only setup (fine for CI and non-Claude
  agents).
- `-TargetPlatform` overrides the auto-detected OS/arch for the lemminx download.

Run this one script rather than the individual `Get-*` scripts — a partial manual setup can
leave the XSDs or the lemminx binary missing, so the launcher shim throws at startup instead of
validating silently against nothing.

## What's inside

| Path | Purpose |
|------|---------|
| `skills/dataverse-xml-lsp-setup/SKILL.md` | Setup skill (runs `Install-Plugin.ps1`); `disable-model-invocation` so it never auto-triggers |
| `skills/dataverse-xml-validate/SKILL.md` | Auto-triggering usage skill: surfaces the validator + how to read its output |
| `hooks/validate-wrapper.mjs`, `hooks/hooks.json` | PostToolUse hook: auto-validates edited forms/charts/viewers/parameter/whole-customizations files the LSP doesn't cover |
| `scripts/Install-Plugin.ps1` | One-shot setup: schemas + lemminx + self-check |
| `scripts/Validate-DataverseXml.ps1` | Standalone validator — root-element → XSD, line/col errors, non-zero exit |
| `scripts/Get-Schemas.ps1` | Download the official Microsoft XSDs into `schemas/<version>/` |
| `scripts/Get-Lemminx.ps1` | Download the native lemminx binary into `bin/` (SHA256-verified) |
| `scripts/lsp-launch.mjs` | Launcher shim — spawns lemminx and injects the bundled XSD associations at runtime |
| `scripts/Set-LspSchemaPaths.ps1` | Write the XSD associations into VS Code user settings (`-UpdateVSCode`; Claude Code uses the shim instead) |
| `.lsp.json` | Launches lemminx via the shim, which resolves the bundled XSDs at runtime — no stamped paths |
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

The launcher shim resolves the bundled schema at runtime, so `.lsp.json` is portable — you do
**not** need to re-run setup after a plugin update or a repo move. Re-run it only when an update
bumps the pinned schema/lemminx version and you need the new assets fetched. Schema-version bumps
are driven by `versions.json`; the procedure is in `schemas/SOURCE.md`.

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
  `settings` — which is why the launcher shim (`scripts/lsp-launch.mjs`), handed the plugin root
  as an argv, injects the XSD associations at runtime instead of `.lsp.json` carrying them.

## License

The plugin is MIT-licensed (see the repo root `LICENSE`). The Microsoft XSDs are downloaded
from Microsoft at setup time and remain subject to Microsoft's terms — they are not
redistributed in this repo.

See [`docs/guide.md`](docs/guide.md) for the ribbon-button recipe and the full edit → validate → pack → import loop.
