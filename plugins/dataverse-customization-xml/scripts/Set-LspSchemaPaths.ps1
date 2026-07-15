#requires -Version 7
<#
.SYNOPSIS
    Stamp this machine's absolute schema paths into .lsp.json and (optionally) VS Code settings.

.DESCRIPTION
    ${CLAUDE_PLUGIN_ROOT} is NOT substituted inside .lsp.json initializationOptions/settings, so the
    lemminx fileAssociations systemIds must be absolute. Run this once after installing/syncing the
    plugin on a new machine (e.g. via the claude-skills repo) to point them at THIS machine's plugin
    location. Re-run after changing the schema version folder.

.EXAMPLE
    pwsh scripts/Set-LspSchemaPaths.ps1
    pwsh scripts/Set-LspSchemaPaths.ps1 -SchemaVersion 9.0.0.2090 -UpdateVSCode
#>
[CmdletBinding()]
param(
    [string]$SchemaVersion = '9.0.0.2090',
    [switch]$UpdateVSCode
)

$ErrorActionPreference = 'Stop'
$pluginRoot = Split-Path $PSScriptRoot -Parent
$schemaDir = (Join-Path $pluginRoot "schemas\$SchemaVersion")
if (-not (Test-Path $schemaDir)) { throw "Schema dir not found: $schemaDir" }
$schemaDirFwd = ((Resolve-Path $schemaDir).Path) -replace '\\', '/'

# pattern -> schema filename
$assoc = [ordered]@{
    '**/RibbonDiff.xml'        = 'RibbonCore.xsd'
    '**/[Cc]ustomizations.xml' = 'CustomizationsSolution.xsd'
    '**/SiteMap*.xml'          = 'SiteMap.xsd'
    '**/FormXml/**/*.xml'      = 'FormXml.xsd'
}
$fileAssociations = @($assoc.GetEnumerator() | ForEach-Object {
        [ordered]@{ pattern = $_.Key; systemId = "$schemaDirFwd/$($_.Value)" }
    })

# --- .lsp.json ---
$lspPath = Join-Path $pluginRoot '.lsp.json'
$lsp = Get-Content $lspPath -Raw | ConvertFrom-Json
$xmlBlock = [ordered]@{
    validation       = [ordered]@{ enabled = $true; schema = [ordered]@{ enabled = 'always' } }
    fileAssociations = $fileAssociations
}
$lsp.xml.initializationOptions.settings.xml = $xmlBlock
$lsp.xml.settings.xml = $xmlBlock
$lsp | ConvertTo-Json -Depth 20 | Set-Content $lspPath -Encoding UTF8
Write-Host "Updated $lspPath" -ForegroundColor Green

# --- VS Code user settings.json (optional) ---
if ($UpdateVSCode) {
    $settingsPath = Join-Path $env:APPDATA 'Code\User\settings.json'
    if (Test-Path $settingsPath) {
        $s = Get-Content $settingsPath -Raw | ConvertFrom-Json
        # RedHat XML uses two explicit entries for Customizations/customizations.
        $vscodeAssoc = @()
        foreach ($kv in $assoc.GetEnumerator()) {
            $pattern = $kv.Key -replace '\[Cc\]', 'C'   # RedHat glob has no char classes
            $vscodeAssoc += [ordered]@{ pattern = $pattern; systemId = "$schemaDirFwd/$($kv.Value)" }
            if ($kv.Key -match '\[Cc\]') {
                $vscodeAssoc += [ordered]@{ pattern = ($kv.Key -replace '\[Cc\]', 'c'); systemId = "$schemaDirFwd/$($kv.Value)" }
            }
        }
        $s | Add-Member -NotePropertyName 'xml.fileAssociations' -NotePropertyValue $vscodeAssoc -Force
        $s | Add-Member -NotePropertyName 'xml.validation.enabled' -NotePropertyValue $true -Force
        $s | Add-Member -NotePropertyName 'xml.validation.schema.enabled' -NotePropertyValue 'always' -Force
        $s | ConvertTo-Json -Depth 20 | Set-Content $settingsPath -Encoding UTF8
        Write-Host "Updated $settingsPath" -ForegroundColor Green
    }
    else { Write-Host "VS Code settings.json not found; skipped." -ForegroundColor Yellow }
}

Write-Host "`nDone. Reload plugins (/reload-plugins) or restart VS Code to apply." -ForegroundColor Cyan
