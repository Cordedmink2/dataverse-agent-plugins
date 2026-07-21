# VS Code-only setup (no agent)

Live schema validation while hand-editing Dataverse XML in VS Code.

Prerequisite: PowerShell 7+ (`pwsh`) — Windows ships only Windows PowerShell 5.1, and the
scripts have `#requires -Version 7`.

1. Clone this repo anywhere.
2. Run:

   ```
   pwsh plugins/dataverse-xml-lsp/scripts/Install-Plugin.ps1 -UpdateVSCode -SkipLemminx
   ```

   This fetches the Microsoft XSDs and writes `xml.fileAssociations` (absolute paths) into
   your VS Code user settings. VS Code uses the RedHat extension's own server, not this
   plugin's lemminx binary or launcher shim, so `-SkipLemminx` avoids the ~47 MB download (and
   the Node requirement) here — the VS Code association only needs the XSDs.
3. Install the **XML** extension by Red Hat (`redhat.vscode-xml`) and restart VS Code.
4. Open any `RibbonDiff.xml` / `SiteMap*.xml` / `Customizations.xml` / `*.fetchxml` /
   `FormXml/**/*.xml` / `SavedQueries/**/*.xml` / `isv.config.xml` — schema errors appear as
   squiggles + Problems entries. (Chart `<visualization>` files deliberately get no
   association — their wrapper root isn't in the XSD — validate those with the script.)

The standalone validator also works as a plain CLI for pre-commit hooks or CI:

```
pwsh plugins/dataverse-xml-lsp/scripts/Validate-DataverseXml.ps1 <files-or-globs>
```

## Settings-update notes

- If your `settings.json` contains comments (JSONC), the script refuses to modify it (a
  rewrite would strip the comments) and prints the exact `xml.fileAssociations` /
  `xml.validation.*` block — add that by hand instead.
- The comment check isn't airtight: a zero-whitespace comment like `"key":1,// note` can slip
  past it, in which case the rewrite strips that comment. The script writes
  `settings.json.bak` next to your settings before every write — note the `.bak` is from the
  **last** run, not the original.
- Only the stable VS Code settings path is auto-detected. VS Code Insiders / VSCodium users:
  run the script anyway (it targets the stable settings path), then copy the
  `xml.fileAssociations` array it wrote into your editor's own `settings.json` (plus
  `"xml.validation.enabled": true` and `"xml.validation.schema.enabled": "always"`). The
  associations come from `Set-LspSchemaPaths.ps1`, not from `.lsp.json` (which carries no
  associations — the Claude Code launcher shim injects those at runtime). The script already
  expands `**/[Cc]ustomizations.xml` into two plain patterns — `**/Customizations.xml` and
  `**/customizations.xml` — because the RedHat extension doesn't support character-class globs.
