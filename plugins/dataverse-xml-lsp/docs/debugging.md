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

1. Did setup run? `.lsp.json` systemIds must be absolute paths that exist — committed state
   is relative-on-purpose and does nothing.
2. `${CLAUDE_PLUGIN_ROOT}` is only substituted in `.lsp.json` `command`/`args`, NOT in
   settings — that's why `Set-LspSchemaPaths.ps1` exists. Re-run it (or the whole setup)
   after moving the plugin.
3. Run `/reload-plugins` (or restart the session) after stamping.
4. lemminx only validates files inside a real workspace folder.
5. Subagents and headless runs NEVER get LSP pushes — that's by design; they must run the
   validator script.

## After `/plugin update dataverse-xml-lsp@dataverse-agent-plugins`

Setup stamps machine-absolute paths into the **tracked** `.lsp.json` inside the marketplace
clone, so an update may conflict on that file or reset it to the committed relative paths.
Re-running `/dataverse-xml-lsp:dataverse-xml-lsp-setup` after every plugin update is the documented
fix — it re-stamps the paths and re-verifies the fetched assets.

Contributors working in a clone of this repo: the installer dirties `.lsp.json` — don't
commit the machine paths. `git update-index --skip-worktree plugins/dataverse-xml-lsp/.lsp.json`
is one way to keep it out of your commits.

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
