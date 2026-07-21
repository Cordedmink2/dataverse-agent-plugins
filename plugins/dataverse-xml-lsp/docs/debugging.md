# Debugging

## Setup fails

- **Schemas download error** — Microsoft moved the zip. Download manually per
  [schemas/SOURCE.md](../schemas/SOURCE.md) and re-run; please also open an issue.
- **lemminx download error** — Open VSX unavailable or pinned version yanked. Re-try with
  `scripts/Get-Lemminx.ps1 -Latest`, or run validator-only (`Install-Plugin.ps1 -SkipLemminx`).
- **Self-check failed** — the fixtures under `tests/fixtures/` disagree with the fetched
  schemas: almost always a schema-version mismatch. Check `versions.json` vs the folder name
  under `schemas/`.

## No live diagnostics in Claude Code

Diagnostics work straight from the committed `.lsp.json`: it launches the shim
(`scripts/lsp-launch.mjs`), which resolves the bundled XSDs at runtime from the plugin root — no
stamped paths, so a plugin update or repo move does not break it. If squiggles don't appear:

1. Is Node installed and on `PATH`? `.lsp.json` runs `node scripts/lsp-launch.mjs`; the shim
   throws loudly if the XSDs or the lemminx binary are missing. Run
   `pwsh scripts/Install-Plugin.ps1` to (re)fetch them.
2. Run `/reload-plugins` (or restart the session).
3. lemminx only validates files inside a real workspace folder.
4. Subagents and headless runs NEVER get LSP pushes — that's by design; they must run the
   validator script.

## No diagnostics in VS Code

- Is `redhat.vscode-xml` installed? Did you restart after `-UpdateVSCode`?
- Check File > Preferences > Settings > `xml.fileAssociations` — absolute paths, must exist.
- JSONC settings file makes the updater refuse to write (see [vscode.md](vscode.md)).

## Validation errors that aren't yours

The `9.0.0.2090` schema lags modern Dataverse exports. Whole-file `Customizations.xml` and
whole-form validation are **indicative**: expect "not declared" noise on newer OOB
attributes (`headerdensity`, `CanvasApps`, `contenttype`, ...). Check that no error mentions
YOUR element/attribute names; ribbon validation (`RibbonCore.xsd`) is fully authoritative.

## The final gates

`pac solution pack` runs SolutionPackager's own structural validation — if it packs, the
solution is structurally sound for import. The validator exists so you rarely get that far
with a bad edit.
