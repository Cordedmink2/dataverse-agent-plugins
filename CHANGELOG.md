# Changelog

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
