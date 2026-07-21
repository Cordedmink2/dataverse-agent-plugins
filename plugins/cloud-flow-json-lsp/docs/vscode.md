# VS Code-only setup (no agent)

Live schema validation while hand-editing Power Automate cloud-flow JSON in VS Code. VS Code's
built-in JSON language features do the validation — no extension required.

Prerequisites: PowerShell 7+ (`pwsh`) and Node.js. The scripts have `#requires -Version 7`; Windows
ships only Windows PowerShell 5.1.

1. Clone this repo anywhere.
2. Run:

   ```
   pwsh plugins/cloud-flow-json-lsp/scripts/Install-Plugin.ps1 -UpdateVSCode
   ```

   This installs the pinned JSON language server (used by the Claude Code path; VS Code uses its
   own built-in one) and writes a `json.schemas` association (absolute `file://` URI) into your VS
   Code user settings.
3. Restart VS Code.
4. Open any `Workflows/*.json` (an unpacked solution flow) or a `*.flow.json` file — schema errors
   appear as squiggles + Problems entries. Other `*.json` files are untouched.

For headless/CI structure checks (no editor), use PowerShell's built-in `Test-Json`:

```
Get-Content <flow>.json -Raw | Test-Json -SchemaFile plugins/cloud-flow-json-lsp/schemas/cloud-flow-clientdata.schema.json
```

## Settings-update notes

- If your `settings.json` contains comments (JSONC), the script refuses to modify it (a rewrite
  would strip the comments) and prints the exact `json.schemas` entry to add by hand.
- The script writes `settings.json.bak` next to your settings before every write — the `.bak` is
  from the **last** run, not the original.
- Only the stable VS Code settings path is auto-detected. VS Code Insiders / VSCodium users: run the
  script anyway, then copy the stamped entry from the plugin's `.lsp.json`
  (`json.schemas`) into your editor's `settings.json`.
