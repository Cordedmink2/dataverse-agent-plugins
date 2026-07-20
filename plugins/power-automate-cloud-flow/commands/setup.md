---
description: Install the JSON language server + stamp the machine-local schema path (run once after install/update)
---

Run this plugin's setup script and report the result:

1. Ask the user whether they also want VS Code's JSON schema association configured
   (adds `json.schemas` to their VS Code user settings).
2. Run: `pwsh "${CLAUDE_PLUGIN_ROOT}/scripts/Install-Plugin.ps1"` — append ` -UpdateVSCode`
   if they said yes.
3. Show the self-check outcome. If setup failed, show the error verbatim and point the user
   at `${CLAUDE_PLUGIN_ROOT}/docs/debugging.md`.
4. If setup succeeded, remind the user to run `/reload-plugins` so the JSON LSP starts with the
   stamped schema path.
