# Changelog

## 2.1.0 — 2026-07-21

### dataverse-xml-lsp

- Added a `dataverse-xml-validate` usage skill that auto-triggers on Dataverse customization XML and
  surfaces the `Validate-DataverseXml.ps1` validator (with guidance on reading its indicative output),
  including in headless / subagent / CI contexts where the LSP does not push diagnostics.
- Added a `PostToolUse` hook that auto-runs the validator on edited files whose root is one of the
  six validator-owned roots the LSP does not cover (`form`, `forms`, `datadefinition`,
  `visualization`, `viewers`, `importexportxml`), surfacing failures to the agent.
- The setup skill now carries `disable-model-invocation: true` and lives under
  `skills/dataverse-xml-lsp-setup/` so it no longer competes during editing.

## 2.0.0 — 2026-07-21

### Changed (breaking)
- Renamed plugins: `dataverse-customization-xml` → `dataverse-xml-lsp`, `power-automate-cloud-flow` → `cloud-flow-json-lsp`. Reinstall under the new id and update your `enabledPlugins` key.
- Each plugin is now an LSP server plus a single manually-run, no-description setup skill (`/<plugin>:<plugin>-setup`). The auto-triggering skill and the `/<plugin>:setup` slash command are removed — editing guidance no longer surfaces automatically; it lives in `docs/guide.md`.
- LSP schema path is resolved at launch (launcher shim), so setup no longer stamps `.lsp.json` and need not be re-run after `/plugin update`.

The `dataverse-xml-lsp` plugin keeps `Validate-DataverseXml.ps1` for CI/headless and pac wrapper-file (forms/charts) validation; those wrapper files are validator-owned (not LSP-associated).

## 1.0.1 — 2026-07-16

- Fix: installer no longer reports failure to CI-style hosts after a successful self-check
  (leaked exit code from the known-bad fixture probe).
- Fix: the validator resolves its default schema directory from `versions.json` instead of a
  hardcoded version, so schema-version bumps apply everywhere.
- Tests: added the missing invalid `viewers` fixture (36 tests).

## 1.0.0 — 2026-07-15

First public release.

- `dataverse-customization-xml` plugin: schema validation for Dataverse customization XML.
  - Standalone PowerShell 7 validator covering the full official XSD set: ribbon
    (`RibbonDiffXml`), SiteMap, forms (incl. pac `<forms>` wrappers), FetchXML (`fetch`,
    `savedquery`), charts (`datadefinition`, incl. `<visualization>` wrappers), ISV config,
    configuration-migration parameter XML, report viewers, and whole `Customizations.xml`.
  - Live lemminx LSP diagnostics for Claude Code and VS Code (RedHat XML extension).
  - Fetch-on-setup for the Microsoft XSDs and the lemminx binary (pinned in `versions.json`).
  - One-shot `Install-Plugin.ps1` with self-check; `/dataverse-customization-xml:setup`.
  - Pester test suite; CI on Windows + Ubuntu runs the real setup end-to-end.
