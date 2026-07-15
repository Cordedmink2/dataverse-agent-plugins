# dataverse-agent-plugins

Agent plugins for Microsoft Dataverse / Power Platform development. A
[Claude Code plugin marketplace](https://docs.anthropic.com/en/docs/claude-code) — each
plugin also works standalone (plain PowerShell scripts) for other agents, VS Code, and CI.

## Install (Claude Code)

    /plugin marketplace add Cordedmink2/dataverse-agent-plugins
    /plugin install dataverse-customization-xml
    /dataverse-customization-xml:setup

Update later with `/plugin update dataverse-customization-xml` (re-run setup after updates).

## Plugins

| Plugin | What it does |
|--------|--------------|
| [dataverse-customization-xml](plugins/dataverse-customization-xml/) | Schema-validated hand-editing of Dataverse customization XML (ribbon, sitemap, forms, FetchXML, charts, ISV config and more) against the official Microsoft XSDs. Standalone PowerShell validator + live lemminx LSP diagnostics. Also usable from [Codex](plugins/dataverse-customization-xml/docs/codex.md), [VS Code with no agent](plugins/dataverse-customization-xml/docs/vscode.md), and CI. |

## Requirements

PowerShell 7+ (`pwsh`) on Windows, macOS or Linux. Plugins fetch what else they need at
setup (Microsoft XSDs, lemminx binary) — nothing bulky or third-party is committed here.

## License

MIT. The Microsoft XSD schemas are downloaded from Microsoft at setup time and remain
subject to Microsoft's terms — they are not redistributed in this repo.
