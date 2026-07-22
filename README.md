# dataverse-agent-plugins

Catch broken Dataverse / Power Platform customization files **while you edit them** — before
`pac solution import` fails at the end of a long round-trip.

This is a [Claude Code plugin marketplace](https://docs.anthropic.com/en/docs/claude-code) with
two language-server (LSP) plugins. Each one validates a kind of hand-edited solution file against a
real schema and shows the errors inline as you type. Every plugin also runs **standalone** — plain
PowerShell/Node with no agent — so the same checks work from other agents, VS Code, or CI.

## Plugins

| Plugin | Validates | How |
|--------|-----------|-----|
| [dataverse-xml-lsp](plugins/dataverse-xml-lsp/) | Dataverse customization XML — ribbon (`RibbonDiff.xml`), sitemap, app sitemap, forms, saved queries, FetchXML, charts, ISV config, `Customizations.xml` | Live [lemminx](https://github.com/eclipse/lemminx) LSP diagnostics against the official Microsoft XSDs, plus a standalone PowerShell validator (`Validate-DataverseXml.ps1`) for wrapper files and CI |
| [cloud-flow-json-lsp](plugins/cloud-flow-json-lsp/) | Unpacked Power Automate cloud-flow clientdata (`Workflows/*.json`) | Live `vscode-json-language-server` diagnostics against a bundled clientdata/WDL wrapper schema; headless checks via built-in `Test-Json` |

## When would I use this?

- **You edit solution files as code.** You unpack a solution (`pac solution unpack`), tweak a ribbon
  button, a form, a sitemap, or a cloud flow by hand, then pack and import. These plugins turn the
  errors that would otherwise only appear at import time into red squiggles while you edit.
- **An agent is editing them for you.** In Claude Code (or Codex), the validator runs after edits so
  the agent sees its own mistakes and fixes them, instead of confidently producing a file that won't
  import.
- **You want a CI gate.** Run the standalone validator over changed files in a pipeline so a bad edit
  fails the build, not the deployment.

Neither plugin talks to Dataverse or needs auth — they validate files on disk. A successful
`pac solution import` / `pac solution check` remains the final authority; these catch the large
class of mistakes you don't need a live environment to find.

## Install (Claude Code)

Add the marketplace once:

    /plugin marketplace add Cordedmink2/dataverse-agent-plugins

Then install whichever plugin you need and run its one-time, per-machine setup (this fetches the
Microsoft XSDs / lemminx / JSON language server — nothing bulky is committed to the repo):

    /plugin install dataverse-xml-lsp@dataverse-agent-plugins
    /dataverse-xml-lsp:dataverse-xml-lsp-setup

    /plugin install cloud-flow-json-lsp@dataverse-agent-plugins
    /cloud-flow-json-lsp:cloud-flow-json-lsp-setup

Run `/reload-plugins` afterwards. Update later with
`/plugin marketplace update dataverse-agent-plugins`, then
`/plugin update <plugin>@dataverse-agent-plugins`, and re-run that plugin's setup.

## Use it without Claude Code

Each plugin works from other tools — see its docs:

- **Other agents (Codex, etc.):** `plugins/<plugin>/docs/codex.md`
- **VS Code, no agent:** `plugins/<plugin>/docs/vscode.md`
- **CI / headless:** the standalone validator (`Validate-DataverseXml.ps1`) or `Test-Json`; see the
  same docs.

## Requirements

PowerShell 7+ (`pwsh`) on Windows, macOS, or Linux. `cloud-flow-json-lsp` also needs Node.js (for its
`npm`-installed JSON language server). Setup fetches the rest.

## Roadmap

Planned, not yet built (design detail in
[the validator-gaps spec](docs/superpowers/specs/2026-07-22-validator-gaps-design.md)):

- **Authoritative saved-query validation.** Saved queries currently validate *indicatively* — the
  bundled Microsoft `Fetch.xsd` lags real exports (`layoutxml`, `LocalizedNames`), so a few
  expected "not declared" errors are noise, the same as whole-form `FormXml`. A setup-time patch
  step would extend the schema so saved queries validate cleanly and the patch survives an XSD
  re-download.
- **Semantic cloud-flow linting.** A layer above the JSON shape check that catches things a schema
  can't express: `runAfter` naming a non-sibling action or a cycle, a `connectionName` that resolves
  to no declared connection reference (the top cause of a flow importing turned Off), child-invoker
  connection mistakes, hard-coded environment GUIDs / host / site URLs, and condition rows that are
  empty or always-true (`{"equals":["",""]}`). Bundled into `cloud-flow-json-lsp` as its "semantics"
  layer.

## License

MIT. The Microsoft XSD schemas are downloaded from Microsoft at setup time and remain subject to
Microsoft's terms — they are not redistributed in this repo.
