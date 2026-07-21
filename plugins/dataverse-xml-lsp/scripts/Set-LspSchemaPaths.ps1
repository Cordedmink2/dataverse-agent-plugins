#requires -Version 7
<#
.SYNOPSIS
    Stamp machine-local absolute schema paths and the per-OS lemminx binary into .lsp.json
    (and optionally VS Code user settings).

.DESCRIPTION
    ${CLAUDE_PLUGIN_ROOT} is NOT substituted inside .lsp.json initializationOptions/settings,
    so the lemminx fileAssociation systemIds must be absolute paths for THIS machine. The
    'command' field keeps the ${CLAUDE_PLUGIN_ROOT} variable (it IS substituted there) but the
    binary filename is OS-specific. Run after install/update or after changing schema version.

.EXAMPLE
    pwsh scripts/Set-LspSchemaPaths.ps1
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

if (-not $SchemaVersion) {
    $SchemaVersion = (Get-Content (Join-Path $pluginRoot 'versions.json') -Raw | ConvertFrom-Json).schemaVersion
}
$schemaDir = Join-Path $pluginRoot 'schemas' $SchemaVersion

# pattern -> schema filename. Charts have no association: their <visualization> wrapper root
# is not declared in the XSD, so whole-file LSP validation would only produce a false error;
# the validator script extracts and validates the inner <datadefinition> instead.
$assoc = [ordered]@{
    '**/RibbonDiff.xml'        = 'RibbonCore.xsd'
    '**/[Cc]ustomizations.xml' = 'CustomizationsSolution.xsd'
    '**/SiteMap*.xml'          = 'SiteMap.xsd'
    '**/FormXml/**/*.xml'      = 'FormXml.xsd'
    '**/SavedQueries/**/*.xml' = 'Fetch.xsd'
    '**/*.fetchxml'            = 'Fetch.xsd'
    '**/isv.config.xml'        = 'isv.config.xsd'
}

# Every XSD about to be stamped must actually exist - a partial extraction or wrong
# -SchemaVersion would otherwise stamp paths to nonexistent files.
$missingXsds = @($assoc.Values | Sort-Object -Unique |
        Where-Object { -not (Test-Path (Join-Path $schemaDir $_)) })
if ($missingXsds.Count -gt 0) {
    throw "Missing XSD(s) in ${schemaDir}: $($missingXsds -join ', '). Run scripts/Get-Schemas.ps1 first."
}
$schemaDirFwd = ((Resolve-Path $schemaDir).Path) -replace '\\', '/'
$fileAssociations = @($assoc.GetEnumerator() | ForEach-Object {
        [ordered]@{ pattern = $_.Key; systemId = "$schemaDirFwd/$($_.Value)" }
    })

# lemminx binary name must match whatever Get-Lemminx.ps1 installed on this OS. Get-Lemminx.ps1
# discovers the binary's real name inside the vsix rather than hardcoding it (per-OS names are
# e.g. lemminx-win32.exe, lemminx-linux-x86_64, lemminx-osx-x86_64, lemminx-osx-aarch_64), so
# find it here the same way instead of guessing.
$binDir = Join-Path $pluginRoot 'bin'
$binaries = @(Get-ChildItem $binDir -Filter 'lemminx*' -File -ErrorAction SilentlyContinue)
if ($binaries.Count -ne 1) {
    throw "Expected exactly one lemminx binary in $binDir, found $($binaries.Count). Run scripts/Get-Lemminx.ps1 first."
}
$exeName = $binaries[0].Name

# --- .lsp.json ---
$lspPath = Join-Path $pluginRoot '.lsp.json'
$lsp = Get-Content $lspPath -Raw | ConvertFrom-Json
$xmlBlock = [ordered]@{
    validation       = [ordered]@{ enabled = $true; schema = [ordered]@{ enabled = 'always' } }
    fileAssociations = $fileAssociations
}
$lsp.xml.command = '${CLAUDE_PLUGIN_ROOT}/bin/' + $exeName
$lsp.xml.initializationOptions.settings.xml = $xmlBlock
$lsp.xml.settings.xml = $xmlBlock
$lsp | ConvertTo-Json -Depth 20 | Set-Content $lspPath -Encoding UTF8
Write-Host "Updated $lspPath" -ForegroundColor Green

# --- VS Code user settings.json (optional) ---
if ($UpdateVSCode) {
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
}

Write-Host "`nDone. Reload plugins (/reload-plugins) or restart VS Code to apply." -ForegroundColor Cyan
