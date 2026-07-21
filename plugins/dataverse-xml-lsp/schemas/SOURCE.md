# Dataverse customization XSD schemas

> The XSDs are **not committed** to this repo (they are Microsoft's). Run
> `pwsh scripts/Get-Schemas.ps1` to download them into `schemas/9.0.0.2090/`.
> Manual fallback: download the zip below yourself and extract the `.xsd` files
> into that folder.

These are the official Microsoft schemas for validating the Dataverse / model-driven-apps
customization file (`customizations.xml`) and its fragments (ribbon, sitemap, forms, views, charts).

- **Version:** `9.0.0.2090` (the folder name matches Microsoft's own versioning)
- **Source:** <https://download.microsoft.com/download/B/9/7/B97655A4-4E46-4E51-BA0A-C669106D563F/Schemas.zip>
- **Documented at:** <https://learn.microsoft.com/power-apps/developer/model-driven-apps/edit-customizations-xml-file-schema-validation>

## Schema map (root element → schema)

| Root element in the XML | Schema to validate against |
|-------------------------|----------------------------|
| `ImportExportXml`       | `CustomizationsSolution.xsd` (root; `xs:include`s the rest) |
| `RibbonDiffXml`         | `RibbonCore.xsd` (includes `RibbonTypes.xsd` + `RibbonWSS.xsd`) |
| `SiteMap`               | `SiteMap.xsd` (uses `SiteMapType.xsd`) |
| `form` / `forms`        | `FormXml.xsd` |

The pac-unpacked solution splits `customizations.xml` into per-entity fragments. `RibbonDiff.xml`
fragments validate standalone against `RibbonCore.xsd` because `RibbonDiffXml` is a root element in
that schema. The whole monolithic `customizations.xml` (root `ImportExportXml`) validates against
`CustomizationsSolution.xsd`.

None of the schemas declare a `targetNamespace`, so the XML uses unqualified element names.

To move to a newer schema release: update `schemaVersion` (and `schemasZipUrl` if Microsoft
publishes a new link) in `versions.json`, run `pwsh scripts/Get-Schemas.ps1 -Force`, then run the
test suite. The launcher shim reads `schemaVersion` from `versions.json` at launch, so it picks up
the new schema dir automatically — no re-stamp. (For VS Code users, re-run
`pwsh scripts/Set-LspSchemaPaths.ps1 -UpdateVSCode` to repoint their settings at the new dir.)
