#requires -Version 7
<#
.SYNOPSIS
    Install the pinned vscode-json-language-server (from vscode-langservers-extracted) into the
    plugin's node_modules/ via npm.

.DESCRIPTION
    The server is a Node package (~a few MB), NOT committed to the repo. Run once after
    installing/syncing the plugin on a machine. Uses `npm ci` against the committed
    package-lock.json for a deterministic, pinned install; falls back to `npm install` if no
    lockfile is present yet. Idempotent: skips the install when the pinned server entry is already
    present unless -Force.

.EXAMPLE
    pwsh scripts/Install-JsonLanguageServer.ps1
    pwsh scripts/Install-JsonLanguageServer.ps1 -Force     # reinstall even if already present
#>
[CmdletBinding()]
param(
    # Reinstall even when node_modules already contains the server entry.
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$pluginRoot = Split-Path $PSScriptRoot -Parent

# The single load-bearing file: if this exists, the LSP command in .lsp.json can launch.
$serverEntry = Join-Path $pluginRoot 'node_modules' 'vscode-langservers-extracted' 'lib' 'json-language-server' 'node' 'jsonServerMain.js'

if (-not $Force -and (Test-Path $serverEntry)) {
    Write-Host "JSON language server already present (use -Force to reinstall)" -ForegroundColor Green
    return
}

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    throw "npm was not found on PATH. Install Node.js (which bundles npm) and re-run."
}

Push-Location $pluginRoot
try {
    $useCi = Test-Path (Join-Path $pluginRoot 'package-lock.json')
    $cmd = if ($useCi) { 'ci' } else { 'install' }
    Write-Host "Running 'npm $cmd' in $pluginRoot ..." -ForegroundColor Cyan
    # --no-audit/--no-fund keep the output focused; --omit=dev because the server is a runtime dep.
    & npm $cmd --no-audit --no-fund --omit=dev
    if ($LASTEXITCODE -ne 0) { throw "npm $cmd failed with exit code $LASTEXITCODE." }
}
finally { Pop-Location }

if (-not (Test-Path $serverEntry)) {
    throw "npm completed but the server entry was not found at $serverEntry - package layout changed?"
}
Write-Host "Installed JSON language server ($serverEntry)" -ForegroundColor Green
