# dataverse-agent-plugins — public repo design

**Date:** 2026-07-15
**Status:** Approved design, pre-implementation
**Author:** Connor Parsons

## Summary

Create a public GitHub repo `Cordedmink2/dataverse-agent-plugins`: a Claude Code plugin
marketplace whose founding plugin is `dataverse-customization-xml` — schema-validated
hand-editing of Dataverse customization XML (ribbon, sitemap, forms, FetchXML, charts, and the
rest of the official schema set), with a standalone PowerShell validator and live lemminx LSP
diagnostics. The existing private copy at `~/.claude/skills/dataverse-customization-xml/`
(mirrored in the private claude-skills repo) becomes the seed content and is then retired in
favour of the public marketplace install.

## Decisions (settled during brainstorming)

| Question | Decision |
|---|---|
| Audience / install model | Claude Code plugin marketplace first; Codex and VS Code-only paths documented |
| Validator scope | Extend to every root element the 12-XSD set declares (~9 validators), not just the current 5 |
| Microsoft XSDs | **Not committed** — fetched from Microsoft's official `Schemas.zip` URL at setup |
| Platform support | Cross-platform via PowerShell 7 (Windows/macOS/Linux); OS-aware lemminx fetch and path stamping |
| Repo name | `dataverse-agent-plugins` (multi-plugin marketplace; room for future plugins) |
| Repo structure | Marketplace at root, plugins under `plugins/<name>/` |
| License | MIT |
| CI | GitHub Actions, windows + ubuntu matrix |
| Git authorship | Commits authored as Connor, no AI attribution |

## Repo layout

```
dataverse-agent-plugins/
├── .claude-plugin/marketplace.json        # lists plugins/* (source: ./plugins/…)
├── README.md                              # marketplace overview + install one-liner
├── llms.txt                               # LLM-facing index (llmstxt.org format)
├── LICENSE                                # MIT
├── CHANGELOG.md
├── .github/workflows/ci.yml
└── plugins/
    └── dataverse-customization-xml/
        ├── .claude-plugin/plugin.json     # version 1.0.0
        ├── SKILL.md                       # workflow, ribbon recipe, gotchas
        ├── README.md                      # plugin-level: full setup, all consumers
        ├── .lsp.json                      # lemminx registration (paths stamped at setup)
        ├── commands/setup.md              # /dataverse-customization-xml:setup
        ├── scripts/
        │   ├── Install-Plugin.ps1         # one-shot: schemas + lemminx + path stamping + self-check
        │   ├── Get-Schemas.ps1            # NEW: fetch Microsoft Schemas.zip → schemas/<ver>/
        │   ├── Get-Lemminx.ps1            # OS-detecting by default (Open VSX download)
        │   ├── Set-LspSchemaPaths.ps1     # stamps schema paths + per-OS binary path; -UpdateVSCode
        │   └── Validate-DataverseXml.ps1  # extended root-element map
        ├── schemas/
        │   ├── SOURCE.md                  # attribution + manual-refresh instructions
        │   └── .gitignore                 # fetched XSD folders not committed
        ├── tests/                         # Pester tests + XML fixtures (valid/invalid per type)
        └── docs/
            ├── codex.md                   # wiring skill + validator into Codex
            ├── vscode.md                  # VS Code-only usage (no agent)
            └── debugging.md               # LSP not starting, false positives, final gates
```

Install UX:

1. `/plugin marketplace add Cordedmink2/dataverse-agent-plugins`
2. `/plugin install dataverse-customization-xml@dataverse-agent-plugins`
3. `/dataverse-customization-xml:setup` (or `pwsh scripts/Install-Plugin.ps1`)

Updates arrive via `/plugin marketplace update dataverse-agent-plugins` then
`/plugin update dataverse-customization-xml@dataverse-agent-plugins`; re-running setup
afterwards is always safe (idempotent).

## Component design

### Validator (`Validate-DataverseXml.ps1`)

- Root-element → XSD map extended from the current 5 entries (`ImportExportXml`,
  `RibbonDiffXml`, `SiteMap`, `form`, `forms`) to **every top-level `xs:element` the 12-XSD set
  declares** — including FetchXML (`Fetch.xsd`), charts (`VisualizationDataDescription.xsd`),
  `isv.config.xsd`, `ParameterXml.xsd`, and `reports.config.xsd`. Exact root-element names are
  **enumerated from the XSDs during implementation** (read each schema's top-level
  `xs:element` declarations), not guessed.
- Keeps current behaviour: picks schema by the file's root element, per-`<form>` fragment
  validation for pac-unpacked forms files, line/col errors, non-zero exit on failure.
- Fails loud on unknown root elements (lists supported roots) — no silent skips.
- SKILL.md's authoritative-vs-indicative table gains a row per newly supported type
  (determined empirically against real pac-unpacked output during implementation).

### Schema fetching (`Get-Schemas.ps1`, new)

- Downloads Microsoft's official `Schemas.zip`
  (`https://download.microsoft.com/download/B/9/7/B97655A4-4E46-4E51-BA0A-C669106D563F/Schemas.zip`)
  and unpacks into `schemas/<version>/` (initially `9.0.0.2090`, pinned in `versions.json`).
- XSDs are **never committed** — avoids redistributing Microsoft-copyrighted files.
  `schemas/SOURCE.md` carries attribution, the download URL, the Learn documentation link, and
  manual-download fallback instructions.
- If the download URL is dead: fail loud with a clear error pointing at SOURCE.md's manual
  steps. No silent fallback.

### Lemminx fetching (`Get-Lemminx.ps1`, updated)

- Detects OS/arch by default (`win32-x64`, `linux-x64`, `darwin-x64`, `darwin-arm64`);
  `-TargetPlatform` still overrides. Downloads the native lemminx binary from the pinned
  `redhat.vscode-xml` release on Open VSX into `bin/` (gitignored, ~47 MB).

### Path stamping (`Set-LspSchemaPaths.ps1`, updated)

- Stamps this machine's absolute schema paths into `.lsp.json` (`${CLAUDE_PLUGIN_ROOT}` is not
  substituted inside `initializationOptions`/`settings` — known Claude Code limitation) **and**
  stamps the per-OS lemminx binary filename into the `command` field.
- `-UpdateVSCode` also writes `xml.fileAssociations` into VS Code user settings.
- `.lsp.json` file-association patterns extended to match the new schema types, with patterns
  derived from how `pac solution unpack` actually names those files.

### Setup orchestrator (`Install-Plugin.ps1`, new)

Single idempotent entry point, also wrapped by the `commands/setup.md` slash command:

1. `Get-Schemas.ps1` — fetch + unpack pinned schema version.
2. `Get-Lemminx.ps1` — fetch OS-matched binary.
3. `Set-LspSchemaPaths.ps1` — stamp paths (`-UpdateVSCode` passthrough).
4. **Self-check:** run `Validate-DataverseXml.ps1` against a bundled known-good fixture and a
   known-bad fixture; report pass/fail. Setup only reports success if the self-check passes.

### Version pinning (`versions.json`, new)

Small manifest pinning the schema version (`9.0.0.2090`) and the lemminx / vscode-xml release,
so installs are reproducible. A `-Latest` switch on the fetch scripts and a documented bump
procedure (update `versions.json`, run setup, run tests, commit) handle deliberate upgrades.

### Marketplace + plugin manifests

- `.claude-plugin/marketplace.json` at repo root, listing
  `{ "name": "dataverse-customization-xml", "source": "./plugins/dataverse-customization-xml" }`.
- Plugin's `plugin.json` bumped to `1.0.0` for the public release.

### llms.txt

Root `llms.txt` per the llmstxt.org convention: one-paragraph summary, then curated links to
SKILL.md, the plugin README, the three docs pages, and `schemas/SOURCE.md`. An index, not a
content mirror.

## Non-Claude consumers

- **Codex** (`docs/codex.md`): point Codex at SKILL.md via its skills/AGENTS.md mechanism; lead
  with the validator script as the edit loop, since Codex receives no LSP diagnostic push.
  SKILL.md already mandates the script for headless/non-main-session contexts.
- **VS Code-only** (`docs/vscode.md`): run setup with `-UpdateVSCode`, install
  `redhat.vscode-xml`, done. The validator is also usable as a plain CLI/CI tool with no agent
  or editor at all.

## Error handling

- All fetch scripts fail loud with actionable messages (dead URL → manual instructions; wrong
  platform → supported list). No catch-and-continue.
- Validator: unknown root element is an error, not a skip; validation failure exits non-zero.
- Setup self-check makes a broken install visible immediately instead of at first real use.

## Testing & CI

- **Pester tests** (`tests/`): for each supported schema type, a valid fixture must pass and an
  invalid fixture must fail with a schema error. Plus unit-ish tests for root-element detection
  and the forms fragment extraction.
- **GitHub Actions** (`ci.yml`), matrix `windows-latest` + `ubuntu-latest`:
  1. Run `Install-Plugin.ps1` end-to-end (proves fetch URLs, OS detection, path stamping).
  2. Run the Pester suite.
  3. PSScriptAnalyzer lint on all scripts.
- CI red = the public setup story is broken — the single most important signal for this repo.

## Debugging story (`docs/debugging.md`)

Covers: confirming lemminx is running in Claude Code; where lemminx logs live; the
`${CLAUDE_PLUGIN_ROOT}` stamping gotcha; interpreting indicative-only false positives from the
lagging `9.0.0.2090` schema (grep errors for your own element/attribute names); and the final
structural gate being `pac solution pack`.

## Migration of the existing private setup

After the public repo is live and CI is green:

1. Install from the public marketplace on Connor's machine; run setup; verify against a real
   pac-unpacked solution (an existing private workspace).
2. Remove `~/.claude/skills/dataverse-customization-xml/` (the skills-dir copy) so only the
   marketplace install remains.
3. Remove the skill from the private claude-skills repo (single source of truth = public repo).
4. Update the workspace memory file that points at the old location.

## Out of scope

- Publishing to any marketplace other than the repo's own (e.g. community marketplaces) — can
  follow later.
- Additional plugins in the marketplace — the layout allows them; none are designed here.
- Bash ports of the scripts — pwsh 7 is the supported runtime on all platforms.
- Schema versions other than the pinned one — the bump procedure exists, but multi-version
  support does not.

## Success criteria

- A fresh machine (Windows or Linux, with pwsh 7) can go from
  `/plugin marketplace add` → `/plugin install dataverse-customization-xml@dataverse-agent-plugins`
  → setup → validating a Dataverse XML file, with every step working first try.
- CI is green on both OSes, including the end-to-end setup run.
- Connor's own machine runs the public plugin with the private copies removed.
