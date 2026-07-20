# Changelog

## Unreleased

- New plugin `power-automate-cloud-flow`: live schema validation of unpacked Power Automate
  solution cloud-flow JSON (`Workflows/*.json`).
  - Bundled draft-07 clientdata/WDL wrapper schema (structure only — connector `inputs` left
    loose by design, since `OpenApiConnection` isn't in the public Logic Apps schema).
  - Live `vscode-json-language-server` LSP diagnostics for Claude Code (and VS Code via
    `json.schemas`); the server is `npm ci`-installed at setup, pinned in `package-lock.json`.
  - One-shot `Install-Plugin.ps1` whose self-check drives the real LSP end-to-end
    (`scripts/lsp-smoke.mjs`) and asserts the schema fires; `/power-automate-cloud-flow:setup`.
  - Headless/CI structure checks via PowerShell's built-in `Test-Json` (no bespoke validator).
  - Semantic linting (runAfter / connectionName resolution, hard-coded values) stays in the
    `power-automate-flow-dev` skill; this plugin is the shape layer.

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
