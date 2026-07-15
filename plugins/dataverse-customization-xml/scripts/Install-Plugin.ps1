#requires -Version 7
<#
.SYNOPSIS
    One-shot plugin setup: fetch schemas + lemminx, stamp machine paths, run a self-check.

.DESCRIPTION
    Idempotent - safe to re-run after /plugin update or a schema version bump.
    The self-check validates a known-good and a known-bad fixture so a broken install fails
    here, not at first real use.

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

Write-Host "== 3/4 Path stamping ==" -ForegroundColor Cyan
$binDir = Join-Path $pluginRoot 'bin'
if ($SkipLemminx -and -not (Get-ChildItem $binDir -Filter 'lemminx*' -File -ErrorAction SilentlyContinue)) {
    Write-Host "Skipped (no lemminx binary; validator-only setup)."
}
else {
    & (Join-Path $PSScriptRoot 'Set-LspSchemaPaths.ps1') -UpdateVSCode:$UpdateVSCode
}

Write-Host "== 4/4 Self-check ==" -ForegroundColor Cyan
$validator = Join-Path $PSScriptRoot 'Validate-DataverseXml.ps1'
$fixtures = Join-Path $pluginRoot 'tests' 'fixtures'
$pwshExe = [Environment]::ProcessPath  # this host is pwsh 7 (#requires), so reuse it rather than trusting PATH
$out = & $pwshExe -NoProfile -File $validator (Join-Path $fixtures 'valid' 'ribbon.xml') 2>&1
if ($LASTEXITCODE -ne 0) { $out | Write-Host; throw "Self-check FAILED: known-good fixture did not validate." }
$out = & $pwshExe -NoProfile -File $validator (Join-Path $fixtures 'invalid' 'ribbon.xml') 2>&1
if ($LASTEXITCODE -ne 1) { $out | Write-Host; throw "Self-check FAILED: known-bad fixture was not rejected." }

Write-Host "`nSetup complete - self-check passed." -ForegroundColor Green
Write-Host "Claude Code: run /reload-plugins (or restart the session)."
Write-Host "VS Code live validation: install the 'redhat.vscode-xml' extension (re-run with -UpdateVSCode if you skipped it)."
