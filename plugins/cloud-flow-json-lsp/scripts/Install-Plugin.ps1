#requires -Version 7
<#
.SYNOPSIS
    One-shot plugin setup: install the JSON language server and run an end-to-end self-check.

.DESCRIPTION
    Idempotent - safe to re-run after /plugin update. Claude Code resolves the bundled schema at
    launch via scripts/lsp-launch.mjs, so no machine-local path is ever stamped into .lsp.json.
    The self-check drives that shim over stdio and confirms the schema fires (valid fixtures clean,
    invalid fixtures flagged), so a broken install fails here, not at first real use.
    Pass -UpdateVSCode to also wire the separate VS Code editor association.

.EXAMPLE
    pwsh scripts/Install-Plugin.ps1
    pwsh scripts/Install-Plugin.ps1 -UpdateVSCode
#>
[CmdletBinding()]
param(
    [switch]$UpdateVSCode
)

$ErrorActionPreference = 'Stop'

# Child scripts must fail via throw, never exit <nonzero>: an exit through '&' returns to this
# script without stopping it, so the failure would go unnoticed.
Write-Host "== 1/3 JSON language server ==" -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'Install-JsonLanguageServer.ps1')

Write-Host "== 2/3 VS Code association (optional) ==" -ForegroundColor Cyan
if ($UpdateVSCode) { & (Join-Path $PSScriptRoot 'Set-LspSchemaPaths.ps1') -UpdateVSCode }
else { Write-Host "Skipped (Claude Code resolves the schema at launch via the shim; pass -UpdateVSCode to wire VS Code)." }

Write-Host "== 3/3 Self-check (end-to-end LSP diagnostics) ==" -ForegroundColor Cyan
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw "node was not found on PATH. Install Node.js and re-run."
}
$smoke = Join-Path $PSScriptRoot 'lsp-smoke.mjs'
& node $smoke
if ($LASTEXITCODE -ne 0) { throw "Self-check FAILED: LSP smoke test exited $LASTEXITCODE (see output above)." }

Write-Host "`nSetup complete - self-check passed." -ForegroundColor Green
Write-Host "Claude Code: run /reload-plugins (or restart the session)."
Write-Host "VS Code live validation: install nothing extra (built-in JSON language features); re-run with -UpdateVSCode to add the json.schemas association to your user settings."
