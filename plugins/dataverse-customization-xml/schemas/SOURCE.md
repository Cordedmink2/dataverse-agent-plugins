# Dataverse customization XSD schemas

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

To refresh: download the zip above, replace the version folder, and update the version here.
