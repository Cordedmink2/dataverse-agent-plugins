# Close three validator gaps (dataverse-xml-lsp + cloud-flow-json-lsp)

Date: 2026-07-22
Status: Approved for planning

## Background

Testing both plugins against a real client solution export (712 customization XML files
and 12 unpacked cloud flows) surfaced three gaps where a validator silently fails to
cover the most common real-export shapes. Each finding below was reproduced against the
installed plugins (cache paths, freshly downloaded schemas, LSP servers reloaded), so the
gaps are in the mapping/schema logic, not in setup.

| Finding | Plugin | Real-data evidence |
|---------|--------|--------------------|
| `<savedqueries>` wrapper root rejected | dataverse-xml-lsp | 295 / 712 files fail root detection |
| `<AppModuleSiteMap>` root rejected | dataverse-xml-lsp | modern per-app sitemaps uncovered |
| Nested-action errors not caught | cloud-flow-json-lsp | bogus `runAfter` in a nested action passes silently |

Two design facts established during investigation drive the approach:

- `AppModuleSiteMap` contains an inner `<SiteMap>` element carrying the Area/Group/SubArea
  tree. Extracting and validating that inner element against `SiteMap.xsd` produces **0
  errors** on real data — so this fix is authoritative, not indicative.
- A real `<savedquery>` fragment carries `layoutxml` / `LocalizedNames` (absent from the
  bundled `Fetch.xsd`) and omits elements the schema marks required. Validation is
  therefore **indicative** — the same situation as FormXml today.

## Goals

- Real exported saved queries and per-app sitemaps validate instead of being rejected at
  root detection.
- Cloud-flow structural validation reaches actions nested inside Scope / If / Foreach /
  Switch, not just top-level actions.
- Every fix ships with a regression test derived from the real-export shapes.

## Non-goals

- Making saved-query validation authoritative (patching the Microsoft XSD) — deferred to
  the roadmap.
- Semantic flow linting (condition rows, connection-reference resolution, etc.) — deferred
  to the roadmap.
- The minor "directory input is shallow / flags Entity.xml" polish — out of scope.

## Design

All three changes are small; two reuse existing machinery.

### Fix A — `dataverse-xml-lsp`: `<savedqueries>` wrapper root

Root cause: `Validate-DataverseXml.ps1` maps the singular inner element `savedquery`, but
pac exports the file with a `<savedqueries>` wrapper, so root detection reports
`Unknown root element <savedqueries>`.

Changes:

- `scripts/Validate-DataverseXml.ps1`: add `innerElementByRoot['savedqueries'] =
  'savedquery'`. This reuses the existing per-fragment extraction loop (identical code path
  to `forms` -> `systemform/form`); no new logic. Each `<savedquery>` child is validated
  against `Fetch.xsd`.
- `hooks/validate-wrapper.mjs`: add `savedqueries` to `OWNED_ROOTS` so the PostToolUse hook
  runs the CLI validator after an edit.
- `scripts/lsp-launch.mjs`: remove the stale live association `**/SavedQueries/**/*.xml ->
  Fetch.xsd`. It mis-fires: lemminx validates the whole document, whose root
  `<savedqueries>` is not declared in `Fetch.xsd`, producing a misleading root-level error.
  Coverage moves to the hook, consistent with the other wrapper/lag-prone roots.

Behaviour: **indicative**. The known OOB errors (`layoutxml` not declared; required
`name` / `returnedtypecode` reported missing) are expected noise, read the same way as
FormXml — confirm your own edit is not named in the output.

### Fix B — `dataverse-xml-lsp`: `<AppModuleSiteMap>` wrapper root

Root cause: model-driven-app sitemaps export with root `<AppModuleSiteMap>`, which is not
in the root map; the `**/SiteMap*.xml` glob does not match the filename either.

Changes:

- `scripts/Validate-DataverseXml.ps1`: add `rootToSchema['AppModuleSiteMap'] =
  'SiteMap.xsd'` and `innerElementByRoot['AppModuleSiteMap'] = 'SiteMap'`. The inner
  `<SiteMap>` subtree is extracted and validated.
- `hooks/validate-wrapper.mjs`: add `AppModuleSiteMap` to `OWNED_ROOTS`.

Behaviour: **authoritative** (0 errors on real data). No live LSP association — lemminx
cannot do per-fragment extraction, so this follows the wrapper-root-via-hook pattern.

### Fix C — `cloud-flow-json-lsp`: recursive nested-action validation

Root cause: `schemas/cloud-flow-clientdata.schema.json` constrains only the top-level
`actions` map. Actions nested inside a container (`Scope` / `If` / `Foreach` / `Switch`)
fall under `additionalProperties: true` and are unchecked, so a bogus nested `runAfter`
status or a missing nested `type` passes silently.

Changes:

- Hoist the action object shape into `definitions/action` (draft-07 keyword `definitions`,
  not `$defs`, so the bundled and VS Code validators both resolve it).
- `$ref` `#/definitions/action` from `definition.actions.additionalProperties` and,
  recursively, from the container keys inside an action: `actions`, `else.actions`,
  `cases.*.actions`, `default.actions`.
- Keep `inputs` untyped (the intentional looseness that avoids OpenApiConnection false
  positives). Only `type` presence and the `runAfter` status enum are enforced, now at any
  depth.

## Testing

Each plugin gains fixtures derived from the real-export shapes, kept minimal:

- dataverse-xml-lsp: a valid `<savedqueries>` file (passes with only the documented OOB
  noise), a valid `<AppModuleSiteMap>` file (passes clean), and an invalid variant of each.
- cloud-flow-json-lsp: a valid nested-action flow and an invalid one with a bogus
  `runAfter` status on a nested action — which must now be caught.

Assertions extend the existing suites:

- `dataverse-xml-lsp/tests/Validate-DataverseXml.Tests.ps1`: new roots resolve to the right
  schema and inner element; valid/invalid fixtures behave as expected.
- `dataverse-xml-lsp/tests/Hook.Tests.ps1`: the hook now claims `savedqueries` and
  `AppModuleSiteMap`.
- `dataverse-xml-lsp` LSP association test: the `SavedQueries` association is gone.
- `cloud-flow-json-lsp`: the setup self-check / smoke test gains the nested-bad-runAfter
  case and confirms a diagnostic fires.

Committed fixtures stay minimal and synthetic (derived from the real shapes, not client
data). Two real client exports — `Claude/QEII` and `Claude/NZLS` — are available locally as
additional corpora for a broad pre-release sweep of each fix; they are not committed.

## Docs and versioning

- `dataverse-xml-lsp/docs/guide.md`: add both new roots to the root->schema table; extend
  the "indicative, not authoritative" note to name `savedqueries`.
- `CHANGELOG.md`: one entry per plugin.
- Version bumps: `dataverse-xml-lsp` 2.1.0 -> 2.2.0; `cloud-flow-json-lsp` 2.0.0 -> 2.1.0.

## Roadmap (documented, not built here)

1. **Authoritative saved queries.** Add a post-download patch step in
   `dataverse-xml-lsp/scripts/Get-Schemas.ps1` that extends the stock `Fetch.xsd` (declare
   `layoutxml` / `LocalizedNames`, relax the required attributes) so saved queries validate
   cleanly rather than indicatively, and the patch survives XSD re-download.
2. **Flow semantic-validate skill.** Port the checks from the personal
   `power-automate-flow-dev` skill (`flow-lint.ps1` + `flow-validate-conditions.ps1`) into
   `cloud-flow-json-lsp` as a bundled semantic layer above the shape schema: `runAfter`
   integrity and cycles, `connectionName` -> `connectionReferences` resolution,
   child-invoker connection detection, hardcoded env GUID/host/site-URL warnings, and
   condition-row checks (empty and/or groups, empty operands, the always-true
   `{"equals":["",""]}` row, stringified literals). This is the "Semantics" layer the guide
   already references as living in an external skill.
