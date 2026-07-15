#requires -Version 7
<#
.SYNOPSIS
    Download the official Microsoft Dataverse customization XSDs into schemas/<version>/.

.DESCRIPTION
    The XSDs are Microsoft-copyrighted, so they are not committed to this repo. This script
    downloads Microsoft's Schemas.zip (URL pinned in versions.json) and installs the .xsd set.
    Idempotent: skips if the schemas are already present (use -Force to re-download).

.EXAMPLE
    pwsh scripts/Get-Schemas.ps1
    pwsh scripts/Get-Schemas.ps1 -Force
#>
[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$pluginRoot = Split-Path $PSScriptRoot -Parent
$versions = Get-Content (Join-Path $pluginRoot 'versions.json') -Raw | ConvertFrom-Json
$dest = Join-Path $pluginRoot 'schemas' $versions.schemaVersion

if ((Test-Path (Join-Path $dest 'RibbonCore.xsd')) -and -not $Force) {
    Write-Host "Schemas already present at $dest (use -Force to re-download)." -ForegroundColor Green
    exit 0
}

$url = $versions.schemasZipUrl
Write-Host "Downloading Microsoft Schemas.zip ($($versions.schemaVersion))..." -ForegroundColor Cyan
$tmpZip = Join-Path ([IO.Path]::GetTempPath()) "dataverse-schemas-$([IO.Path]::GetRandomFileName()).zip"
$tmpDir = Join-Path ([IO.Path]::GetTempPath()) "dataverse-schemas-$([IO.Path]::GetRandomFileName())"
try {
    try {
        Invoke-WebRequest -Uri $url -OutFile $tmpZip -TimeoutSec 300
    }
    catch {
        throw ("Download failed from {0}: {1}`nSee schemas/SOURCE.md for manual download steps." -f $url, $_.Exception.Message)
    }
    Expand-Archive -Path $tmpZip -DestinationPath $tmpDir
    # Locate the folder holding the XSD set regardless of the zip's internal layout.
    $core = Get-ChildItem $tmpDir -Recurse -Filter 'RibbonCore.xsd' | Select-Object -First 1
    if (-not $core) { throw "RibbonCore.xsd not found inside the zip - has Microsoft changed the layout? See schemas/SOURCE.md." }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Get-ChildItem $core.Directory -Filter '*.xsd' | Copy-Item -Destination $dest -Force
    $count = (Get-ChildItem $dest -Filter '*.xsd').Count
    if ($count -lt 12) { throw "Expected 12 XSDs, found $count in $dest." }
    Write-Host "Installed $count XSDs to $dest" -ForegroundColor Green
}
finally {
    Remove-Item $tmpZip, $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}
