# dataverse-xml-lsp — editing guide

> This is the manual replacement for the old auto-loaded skill; the plugin no longer surfaces this automatically.

## Dataverse customization XML (schema-validated)

Edit Dataverse customization XML so malformed edits **fail loud before `pac solution import`**,
not silently at import time. Two validation layers share the same official Microsoft XSD set
(`schemas/9.0.0.2090/`, fetched at setup — if the validator exits 2 with "Schema directory not
found", run `/dataverse-xml-lsp:dataverse-xml-lsp-setup` or `pwsh scripts/Install-Plugin.ps1`):

1. **`scripts/Validate-DataverseXml.ps1`** — the backbone. Run it after every edit and before
   pack/import. Tool-agnostic (any shell, CI, Codex). No Java, no network.
2. **lemminx LSP** — live diagnostics while editing (this plugin's `.lsp.json`, and VS Code's
   RedHat XML extension via `xml.fileAssociations`). Diagnostics push into context on file edit.

> **Subagents / headless contexts must use layer 1 (the script).** LSP diagnostics only auto-push
> in the main interactive session — a spawned subagent (Agent tool), a workflow step, or any
> non-main-session context does NOT receive them. In those contexts, always run
> `Validate-DataverseXml.ps1` explicitly after editing; don't assume squiggles appeared. The
> script is self-contained (pwsh + the fetched XSDs) and needs no LSP.

## Always validate after editing

```
pwsh <plugin>/scripts/Validate-DataverseXml.ps1 <path-to-xml> [more paths / globs]
```

It picks the schema by the file's **root element**:

| Root element        | Schema                        | Notes |
|---------------------|-------------------------------|-------|
| `RibbonDiffXml`     | `RibbonCore.xsd`              | Per-entity `RibbonDiff.xml` or app ribbon — **authoritative** |
| `SiteMap`           | `SiteMap.xsd`                 | App navigation — authoritative |
| `form` / `forms`    | `FormXml.xsd`                 | Forms; pac's `<forms>` wrapper → each inner `systemform/form` validated — indicative (schema lags modern form attrs) |
| `fetch`             | `Fetch.xsd`                   | FetchXML queries (`.fetchxml` files, query fragments) — authoritative |
| `savedquery`        | `Fetch.xsd`                   | pac `SavedQueries/*.xml` — authoritative |
| `visualization` / `datadefinition` | `VisualizationDataDescription.xsd` | Charts; the `<visualization>` wrapper's inner `datadescription/datadefinition` is validated (escaped inner XML handled — see gotchas) |
| `configuration`     | `isv.config.xsd`              | Legacy ISV config |
| `importexportxml` (lowercase) | `ParameterXml.xsd`  | Configuration-migration parameter XML — note the case difference from `ImportExportXml` |
| `viewers`           | `reports.config.xsd`          | Report viewers config |
| `ImportExportXml`   | `CustomizationsSolution.xsd`  | Whole `Customizations.xml` — **indicative only** (see caveat) |

Unknown root elements **fail loud** (exit 1) and list the supported roots — use
`-Schema <file.xsd>` to force one.

Non-zero exit = validation failed. Fix and re-run until clean, then pack/import.

## Adding a ribbon (command-bar) button — the common task

In a pac-unpacked solution, edit the entity's `Entities/<entity>/RibbonDiff.xml`. Fill the
empty `<CustomActions/>` and `<CommandDefinitions/>`. Minimal valid shape (Microsoft-verified):

```xml
<RibbonDiffXml>
  <CustomActions>
    <CustomAction Id="<prefix>.<entity>.<name>.CustomAction"
                  Location="Mscrm.Form.<entity>.MainTab.Save.Controls._children" Sequence="45">
      <CommandUIDefinition>
        <Button Id="<prefix>.<entity>.<name>.Button"
                Command="<prefix>.<entity>.<name>.Command"
                LabelText="$LocLabels:<prefix>.<entity>.<name>.LabelText"
                Alt="$LocLabels:<prefix>.<entity>.<name>.Alt"
                Sequence="45" TemplateAlias="o1"
                Image16by16="$webresource:<prefix>_icon.svg"
                Image32by32="$webresource:<prefix>_icon.svg" />
      </CommandUIDefinition>
    </CustomAction>
  </CustomActions>
  <Templates><RibbonTemplates Id="Mscrm.Templates" /></Templates>
  <CommandDefinitions>
    <CommandDefinition Id="<prefix>.<entity>.<name>.Command">
      <EnableRules />   <!-- required even if empty -->
      <DisplayRules />  <!-- required even if empty -->
      <Actions>
        <JavaScriptFunction Library="$webresource:<prefix>_yourscript.js"
                            FunctionName="Namespace.functionName">
          <CrmParameter Value="PrimaryControl" />
        </JavaScriptFunction>
      </Actions>
    </CommandDefinition>
  </CommandDefinitions>
  <LocLabels>
    <LocLabel Id="<prefix>.<entity>.<name>.LabelText">
      <Titles><Title description="My Button" languagecode="1033" /></Titles>
    </LocLabel>
    <LocLabel Id="<prefix>.<entity>.<name>.Alt">
      <Titles><Title description="My Button" languagecode="1033" /></Titles>
    </LocLabel>
  </LocLabels>
</RibbonDiffXml>
```

Rules that the XSD does **not** catch (get them right by hand):
- `Location` targeting a container ends in `._children`. Common: form `Mscrm.Form.<entity>.MainTab.<Group>.Controls._children`; homepage grid `Mscrm.HomepageGrid.<entity>.MainTab...`; subgrid `Mscrm.SubGrid.<entity>...`.
- `EnableRules` and `DisplayRules` are **required** on a `CommandDefinition` (may be empty).
- `Command` on the `Button` must match a `CommandDefinition/@Id`.
- The `JavaScriptFunction/@Library` web resource must exist in the solution.
- Use a publisher prefix + dotted naming for all `Id`s.

The full loop (round-trip a fragment): edit `RibbonDiff.xml` → validate with the script →
`pac solution pack` → `pac solution import` → confirm in the app. Use the `pac-cli` skill for
pack/import mechanics.

## Gotchas (learned building this)

- **Whole-file `Customizations.xml` AND whole-form `FormXml` validation are indicative, not
  authoritative.** The bundled schema is `9.0.0.2090`; modern Dataverse exports/forms include
  newer attributes/elements it doesn't declare (`OrganizationVersion`, `CanvasApps`, empty
  `AppModules`; on forms `headerdensity`, `contenttype`, `UClientRecordSourcesJSON`, …), so it
  reports false "not declared" errors. Confirm your OWN edits are clean by checking no error
  references them (grep the output for your element/attribute names), and treat pre-existing OOB
  noise as expected. The **ribbon** fragment (`RibbonCore.xsd`) is stable and fully authoritative.
- **Form files are validated per inner `<form>`.** pac unpacks forms as
  `<forms><systemform>…<form/>…</systemform></forms>`, but `FormXml.xsd`'s root is `<form>`. The
  validator validates each `systemform/form` subtree in place, so reported line/col are real
  positions in the file.
- **Chart `<visualization>` files with escaped inner XML are handled.** Some exports store the
  `datadescription` content as escaped text (`&lt;datadefinition …&gt;`) rather than nested
  XML. The validator unescapes and validates that fragment too, emitting a WARN that line/col
  are relative to the unescaped fragment rather than the file.
- **The ultimate structural gate is `pac solution pack`** — it runs SolutionPackager's own
  validation. If it packs, the solution is structurally sound for import.
- **`${CLAUDE_PLUGIN_ROOT}` is not substituted** inside `.lsp.json` `initializationOptions`/
  `settings` — only in `command`/`args`. Schema `systemId`s there use absolute paths. On a new
  machine (or after a plugin update), run `/dataverse-xml-lsp:dataverse-xml-lsp-setup` — or
  `scripts/Set-LspSchemaPaths.ps1` alone — to re-stamp them (and VS Code settings).
- lemminx validates a document only inside a real workspace and after answering its
  `workspace/configuration` pull — Claude Code and VS Code both handle that; a bare LSP client
  must too.

## Refreshing the schemas

To move to a newer schema release: update `schemaVersion` (and `schemasZipUrl` if Microsoft
publishes a new link) in `versions.json`, run `pwsh scripts/Get-Schemas.ps1 -Force`, run
`pwsh scripts/Set-LspSchemaPaths.ps1`, then run the test suite. Details in `schemas/SOURCE.md`.
