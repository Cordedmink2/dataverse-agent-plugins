# dataverse-agent-plugins

Agent plugins for Microsoft Dataverse / Power Platform development. A
[Claude Code plugin marketplace](https://docs.anthropic.com/en/docs/claude-code) — each
plugin also works standalone (plain PowerShell scripts) for other agents, VS Code, and CI.

## Install (Claude Code)

    /plugin marketplace add Cordedmink2/dataverse-agent-plugins
    /plugin install dataverse-customization-xml@dataverse-agent-plugins
    /dataverse-customization-xml:setup

Update later with `/plugin marketplace update dataverse-agent-plugins` then
`/plugin update dataverse-customization-xml@dataverse-agent-plugins` (re-run setup after updates).

## Plugins

| Plugin | What it does |
|--------|--------------|
| [dataverse-customization-xml](plugins/dataverse-customization-xml/) | Schema-validated hand-editing of Dataverse customization XML (ribbon, sitemap, forms, FetchXML, charts, ISV config and more) against the official Microsoft XSDs. Standalone PowerShell validator + live lemminx LSP diagnostics. Also usable from [Codex](plugins/dataverse-customization-xml/docs/codex.md), [VS Code with no agent](plugins/dataverse-customization-xml/docs/vscode.md), and CI. |
| [power-automate-cloud-flow](plugins/power-automate-cloud-flow/) | Schema-validated hand-editing of unpacked Power Automate solution cloud-flow JSON (`Workflows/*.json`) against a bundled clientdata/WDL wrapper schema. Live `vscode-json-language-server` LSP diagnostics; headless structure checks via built-in `Test-Json`. Also usable from [Codex](plugins/power-automate-cloud-flow/docs/codex.md), [VS Code with no agent](plugins/power-automate-cloud-flow/docs/vscode.md), and CI. |

## Requirements

PowerShell 7+ (`pwsh`) on Windows, macOS or Linux. The `power-automate-cloud-flow` plugin also
needs Node.js (for its `npm`-installed JSON language server). Plugins fetch what else they need
at setup (Microsoft XSDs, lemminx binary, the JSON language server) — nothing bulky or
third-party is committed here.

## License

MIT. The Microsoft XSD schemas are downloaded from Microsoft at setup time and remain
subject to Microsoft's terms — they are not redistributed in this repo.
