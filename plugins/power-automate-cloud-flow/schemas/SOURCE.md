# Power Automate cloud-flow clientdata schema

`cloud-flow-clientdata.schema.json` is a **hand-maintained** JSON Schema (draft-07). It is committed
to the repo — unlike the Dataverse XSDs (Microsoft-copyrighted, downloaded at setup), this schema is
ours to ship.

## What it validates

The JSON shape of an unpacked solution cloud flow — the file `pac solution unpack` writes under
`Workflows/<name>-<guid>.json`. That file is the flow's `clientdata`: a wrapper around the Workflow
Definition Language (WDL) `definition` plus its `connectionReferences`.

- `properties.definition` is **required** (a flow with no definition is malformed).
- `definition` requires `$schema`, `triggers`, `actions`.
- `runAfter` statuses are constrained to the WDL enum (`Succeeded` / `Failed` / `Skipped` / `TimedOut`).
- Everything is `additionalProperties: true` — legacy and connector-specific fields are tolerated.

## What it deliberately does NOT validate

The strict WDL action vocabulary. Power Automate connector actions (`OpenApiConnection`) are not in
Microsoft's public Logic Apps `workflowdefinition.json` schema, so `$ref`-ing that schema in would
drown real errors in false positives. This wrapper checks **structure**; the authoritative gate for a
packaged flow is `pac solution check` / a successful `pac solution import`.

Cross-node semantic checks (a `runAfter` naming a real sibling, a `connectionName` resolving to a
declared connection reference, hard-coded environment values) are **inexpressible in JSON Schema** and
live in the `power-automate-flow-dev` skill's `flow-lint.ps1`, not here. This plugin is the live LSP
layer; that skill is the semantic-lint layer.

## Refreshing

There is no upstream download. Edit the schema by hand as the flow shape evolves, then run the test
suite (`tests/`) — the fixtures under `tests/fixtures/valid` and `tests/fixtures/invalid` are the
regression gate.
