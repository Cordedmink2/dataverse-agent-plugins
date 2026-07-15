#requires -Version 7
<#
.SYNOPSIS
    Download the official Microsoft Dataverse customization XSDs into schemas/<version>/.

.DESCRIPTION
    The XSDs are Microsoft-copyrighted, so they are not committed to this repo. This script
    downloads Microsoft's Schemas.zip (URL pinned in versions.json) and installs the .xsd set.
    Idempotent: skips if the complete schema set is already present (use -Force to re-download).
    The set is verified in a staging location and only then swapped into place, so the
    destination is never left in a partial state that looks complete.

.EXAMPLE
    pwsh scripts/Get-Schemas.ps1
    pwsh scripts/Get-Schemas.ps1 -Force
#>
[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$expectedCount = 12
$pluginRoot = Split-Path $PSScriptRoot -Parent
$versions = Get-Content (Join-Path $pluginRoot 'versions.json') -Raw | ConvertFrom-Json
$dest = Join-Path $pluginRoot 'schemas' $versions.schemaVersion

$have = if (Test-Path $dest) { (Get-ChildItem $dest -Filter '*.xsd').Count } else { 0 }
if ($have -eq $expectedCount -and -not $Force) {
    Write-Host "Schemas already present at $dest (use -Force to re-download)." -ForegroundColor Green
    exit 0
}

$url = $versions.schemasZipUrl
Write-Host "Downloading Microsoft Schemas.zip ($($versions.schemaVersion))..." -ForegroundColor Cyan
$tmpZip = Join-Path ([IO.Path]::GetTempPath()) "dataverse-schemas-$([IO.Path]::GetRandomFileName()).zip"
$tmpDir = Join-Path ([IO.Path]::GetTempPath()) "dataverse-schemas-$([IO.Path]::GetRandomFileName())"
try {
    try {
        Invoke-WebRequest -Uri $url -OutFile $tmpZip -TimeoutSec 300 -MaximumRetryCount 2 -RetryIntervalSec 5
    }
    catch {
        throw ("Download failed from {0}: {1}`nSee schemas/SOURCE.md for manual download steps." -f $url, $_.Exception.Message)
    }
    try {
        Expand-Archive -Path $tmpZip -DestinationPath $tmpDir
        # Locate the folder holding the XSD set regardless of the zip's internal layout.
        $core = Get-ChildItem $tmpDir -Recurse -Filter 'RibbonCore.xsd' | Select-Object -First 1
        if (-not $core) { throw 'RibbonCore.xsd not found inside the zip - has Microsoft changed the layout?' }
    }
    catch {
        throw ("Could not extract the XSD set from the zip downloaded from {0}: {1}`nSee schemas/SOURCE.md for manual download steps." -f $url, $_.Exception.Message)
    }
    # Verify the staged set is complete before touching $dest, then swap it in whole.
    $staged = Get-ChildItem $core.Directory -Filter '*.xsd'
    if ($staged.Count -ne $expectedCount) {
        throw "Expected $expectedCount XSDs in the zip, found $($staged.Count) in $($core.Directory)."
    }
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $staged | Copy-Item -Destination $dest -Force
    Write-Host "Installed $($staged.Count) XSDs to $dest" -ForegroundColor Green
}
finally {
    Remove-Item $tmpZip, $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}
