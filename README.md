# dataverse-agent-plugins

Agent plugins for Microsoft Dataverse / Power Platform development. A
[Claude Code plugin marketplace](https://docs.anthropic.com/en/docs/claude-code) — each
plugin also works standalone (plain PowerShell scripts) for other agents, VS Code, and CI.

## Install (Claude Code)

    /plugin marketplace add Cordedmink2/dataverse-agent-plugins
    /plugin install dataverse-xml-lsp@dataverse-agent-plugins
    /dataverse-xml-lsp:dataverse-xml-lsp-setup

Update later with `/plugin marketplace update dataverse-agent-plugins` then
`/plugin update dataverse-xml-lsp@dataverse-agent-plugins` (re-run setup after updates).

## Plugins

| Plugin | What it does |
|--------|--------------|
| [dataverse-xml-lsp](plugins/dataverse-xml-lsp/) | LSP + CLI validator for Dataverse customization XML (ribbon, sitemap, forms, FetchXML, charts, ISV config and more) against the official Microsoft XSDs. Live lemminx LSP diagnostics + a standalone PowerShell validator. Also usable from [Codex](plugins/dataverse-xml-lsp/docs/codex.md), [VS Code with no agent](plugins/dataverse-xml-lsp/docs/vscode.md), and CI. |
| [cloud-flow-json-lsp](plugins/cloud-flow-json-lsp/) | JSON LSP for unpacked Power Automate cloud-flow clientdata (`Workflows/*.json`), validated against a bundled clientdata/WDL wrapper schema. Live `vscode-json-language-server` LSP diagnostics; headless structure checks via built-in `Test-Json`. Also usable from [Codex](plugins/cloud-flow-json-lsp/docs/codex.md), [VS Code with no agent](plugins/cloud-flow-json-lsp/docs/vscode.md), and CI. |

## Requirements

PowerShell 7+ (`pwsh`) on Windows, macOS or Linux. The `cloud-flow-json-lsp` plugin also
needs Node.js (for its `npm`-installed JSON language server). Plugins fetch what else they need
at setup (Microsoft XSDs, lemminx binary, the JSON language server) — nothing bulky or
third-party is committed here.

## License

MIT. The Microsoft XSD schemas are downloaded from Microsoft at setup time and remain
subject to Microsoft's terms — they are not redistributed in this repo.
