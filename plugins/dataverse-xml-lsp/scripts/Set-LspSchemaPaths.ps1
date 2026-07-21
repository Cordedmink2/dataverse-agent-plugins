#requires -Version 7
<#
.SYNOPSIS
    Wire the bundled Dataverse XSDs into VS Code user settings (optional editor integration).

.DESCRIPTION
    Claude Code no longer needs any stamped path or per-OS binary name: the launcher shim
    (scripts/lsp-launch.mjs) discovers the lemminx binary and resolves the absolute XSD systemIds
    at launch from ${CLAUDE_PLUGIN_ROOT}, so .lsp.json stays portable and is never edited. This
    script now only serves the separate VS Code consumer, whose settings.json cannot reference
    ${CLAUDE_PLUGIN_ROOT} and so needs machine-local file paths.

.EXAMPLE
    pwsh scripts/Set-LspSchemaPaths.ps1 -UpdateVSCode
#>
[CmdletBinding()]
param(
    # Defaults to the schemaVersion pinned in versions.json.
    [string]$SchemaVersion,
    [switch]$UpdateVSCode,

    # Test hook: redirect the VS Code settings.json path so -UpdateVSCode can be exercised
    # against a scratch file instead of the real user settings.
    [Parameter(DontShow)]
    [string]$SettingsPathOverride
)

$ErrorActionPreference = 'Stop'
$pluginRoot = Split-Path $PSScriptRoot -Parent

if (-not $UpdateVSCode) {
    Write-Host "Nothing to do: Claude Code resolves schemas at launch via the shim. Pass -UpdateVSCode to wire the VS Code editor path." -ForegroundColor Yellow
    return
}

if (-not $SchemaVersion) {
    $SchemaVersion = (Get-Content (Join-Path $pluginRoot 'versions.json') -Raw | ConvertFrom-Json).schemaVersion
}
$schemaDir = Join-Path $pluginRoot 'schemas' $SchemaVersion

# pattern -> schema filename. Charts (<visualization>) AND forms (<forms>) have no association on
# purpose: they are pac WRAPPER files whose root the XSD doesn't declare, so whole-file validation
# would only produce a false error on the wrapper root. The validator (Validate-DataverseXml.ps1)
# owns them via per-fragment extraction (systemform/form, datadescription/datadefinition). Kept in
# sync with the associations the shim (scripts/lsp-launch.mjs) injects for Claude Code.
$assoc = [ordered]@{
    '**/RibbonDiff.xml'        = 'RibbonCore.xsd'
    '**/[Cc]ustomizations.xml' = 'CustomizationsSolution.xsd'
    '**/SiteMap*.xml'          = 'SiteMap.xsd'
    '**/SavedQueries/**/*.xml' = 'Fetch.xsd'
    '**/*.fetchxml'            = 'Fetch.xsd'
    '**/isv.config.xml'        = 'isv.config.xsd'
}

# Every XSD about to be wired must actually exist - a partial extraction or wrong
# -SchemaVersion would otherwise point VS Code at nonexistent files.
$missingXsds = @($assoc.Values | Sort-Object -Unique |
        Where-Object { -not (Test-Path (Join-Path $schemaDir $_)) })
if ($missingXsds.Count -gt 0) {
    throw "Missing XSD(s) in ${schemaDir}: $($missingXsds -join ', '). Run scripts/Get-Schemas.ps1 first."
}
$schemaDirFwd = ((Resolve-Path $schemaDir).Path) -replace '\\', '/'

# --- VS Code user settings.json ---
if ($SettingsPathOverride) {
    $settingsPath = $SettingsPathOverride
}
else {
    $userDir = if ($IsWindows) { Join-Path $env:APPDATA 'Code\User' }
    elseif ($IsMacOS) { "$HOME/Library/Application Support/Code/User" }
    else { "$HOME/.config/Code/User" }
    $settingsPath = Join-Path $userDir 'settings.json'
}
if (Test-Path $settingsPath) {
    # RedHat XML globs have no char classes -> expand [Cc] into two entries.
    $vscodeAssoc = @()
    foreach ($kv in $assoc.GetEnumerator()) {
        $pattern = $kv.Key -replace '\[Cc\]', 'C'
        $vscodeAssoc += [ordered]@{ pattern = $pattern; systemId = "$schemaDirFwd/$($kv.Value)" }
        if ($kv.Key -match '\[Cc\]') {
            $vscodeAssoc += [ordered]@{ pattern = ($kv.Key -replace '\[Cc\]', 'c'); systemId = "$schemaDirFwd/$($kv.Value)" }
        }
    }

    # ConvertFrom-Json silently accepts JSONC, so rewriting a commented settings.json
    # would strip every comment with no error. Refuse instead and show what to add.
    # Comment tokens must follow line-start or whitespace: bare '//' would match URLs
    # (https://...) and bare '/*' would match the glob patterns this script itself writes
    # (**/*.xml).
    $raw = Get-Content $settingsPath -Raw
    if ($raw -match '(?m)(^|\s)(//|/\*)') {
        Write-Host "$settingsPath contains comments, which this script cannot preserve; not modified." -ForegroundColor Yellow
        Write-Host "Add these settings manually:" -ForegroundColor Yellow
        $manual = [ordered]@{
            'xml.fileAssociations'          = $vscodeAssoc
            'xml.validation.enabled'        = $true
            'xml.validation.schema.enabled' = 'always'
        }
        Write-Host ($manual | ConvertTo-Json -Depth 5)
    }
    else {
        $s = $raw | ConvertFrom-Json
        # Merge by pattern: keep the user's associations for patterns that are not ours
        # (e.g. their own pom.xml mapping), replace/append ours.
        $ourPatterns = @($vscodeAssoc | ForEach-Object { $_.pattern })
        $kept = @()
        if ($s.PSObject.Properties['xml.fileAssociations']) {
            $kept = @($s.'xml.fileAssociations' | Where-Object { $_.pattern -notin $ourPatterns })
        }
        $s | Add-Member -NotePropertyName 'xml.fileAssociations' -NotePropertyValue ($kept + $vscodeAssoc) -Force
        $s | Add-Member -NotePropertyName 'xml.validation.enabled' -NotePropertyValue $true -Force
        $s | Add-Member -NotePropertyName 'xml.validation.schema.enabled' -NotePropertyValue 'always' -Force
        Copy-Item $settingsPath "$settingsPath.bak" -Force
        $s | ConvertTo-Json -Depth 20 | Set-Content $settingsPath -Encoding UTF8
        Write-Host "Updated $settingsPath (backup at $settingsPath.bak)" -ForegroundColor Green
    }
}
else { Write-Host "VS Code settings.json not found at $settingsPath; skipped." -ForegroundColor Yellow }

Write-Host "`nDone. Restart VS Code to apply." -ForegroundColor Cyan
