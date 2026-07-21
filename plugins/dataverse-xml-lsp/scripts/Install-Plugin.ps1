#requires -Version 7
<#
.SYNOPSIS
    One-shot plugin setup: fetch schemas + lemminx and run a self-check.

.DESCRIPTION
    Idempotent - safe to re-run after /plugin update or a schema version bump. Claude Code resolves
    schemas and the lemminx binary at launch via scripts/lsp-launch.mjs, so no machine-local path
    is ever stamped into .lsp.json. The self-check validates a known-good and a known-bad fixture
    so a broken install fails here, not at first real use. Pass -UpdateVSCode to also wire the
    separate VS Code editor associations.

.EXAMPLE
    pwsh scripts/Install-Plugin.ps1
    pwsh scripts/Install-Plugin.ps1 -UpdateVSCode
    pwsh scripts/Install-Plugin.ps1 -SkipLemminx     # validator-only (no LSP)
#>
[CmdletBinding()]
param(
    [switch]$UpdateVSCode,
    [switch]$SkipLemminx,
    [ValidateSet('win32-x64', 'linux-x64', 'darwin-x64', 'darwin-arm64')]
    [string]$TargetPlatform
)

$ErrorActionPreference = 'Stop'
$pluginRoot = Split-Path $PSScriptRoot -Parent

# Child scripts must fail via throw, never exit <nonzero>: an exit through '&' returns
# to this script without stopping it, so the failure would go unnoticed.
Write-Host "== 1/4 Schemas ==" -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'Get-Schemas.ps1')

Write-Host "== 2/4 lemminx ==" -ForegroundColor Cyan
if ($SkipLemminx) { Write-Host "Skipped (-SkipLemminx)." }
else {
    $lemminxArgs = @{}
    if ($TargetPlatform) { $lemminxArgs.TargetPlatform = $TargetPlatform }
    & (Join-Path $PSScriptRoot 'Get-Lemminx.ps1') @lemminxArgs
}

Write-Host "== 3/4 VS Code association (optional) ==" -ForegroundColor Cyan
if ($UpdateVSCode) { & (Join-Path $PSScriptRoot 'Set-LspSchemaPaths.ps1') -UpdateVSCode }
else { Write-Host "Skipped (Claude Code resolves schemas at launch via the shim; pass -UpdateVSCode to wire VS Code)." }

Write-Host "== 4/4 Self-check ==" -ForegroundColor Cyan
$validator = Join-Path $PSScriptRoot 'Validate-DataverseXml.ps1'
$fixtures = Join-Path $pluginRoot 'tests' 'fixtures'
$pwshExe = [Environment]::ProcessPath  # this host is pwsh 7 (#requires), so reuse it rather than trusting PATH
$out = & $pwshExe -NoProfile -File $validator (Join-Path $fixtures 'valid' 'ribbon.xml') 2>&1
if ($LASTEXITCODE -ne 0) { $out | Write-Host; throw "Self-check FAILED: known-good fixture did not validate." }
$out = & $pwshExe -NoProfile -File $validator (Join-Path $fixtures 'invalid' 'ribbon.xml') 2>&1
if ($LASTEXITCODE -ne 1) { $out | Write-Host; throw "Self-check FAILED: known-bad fixture was not rejected." }

# The known-bad check above leaves $LASTEXITCODE at 1 by design. Clear it so a dot-sourcing
# host that propagates it (e.g. CI's `pwsh -command ". script.ps1"`) reads success as success.
$global:LASTEXITCODE = 0

Write-Host "`nSetup complete - self-check passed." -ForegroundColor Green
Write-Host "Claude Code: run /reload-plugins (or restart the session)."
Write-Host "VS Code live validation: install the 'redhat.vscode-xml' extension (re-run with -UpdateVSCode if you skipped it)."
