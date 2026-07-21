#requires -Version 7
<#
.SYNOPSIS
    Stamp the machine-local absolute schema path into .lsp.json (and optionally VS Code user
    settings) so the JSON language server can load the bundled flow schema.

.DESCRIPTION
    ${CLAUDE_PLUGIN_ROOT} is substituted in .lsp.json 'command'/'args' (so the node server path
    stays a variable) but NOT inside 'initializationOptions'/'settings'. The json.schemas 'url'
    there must therefore be an absolute file URI for THIS machine. Run after install/update or
    after moving the plugin.

.EXAMPLE
    pwsh scripts/Set-LspSchemaPaths.ps1
    pwsh scripts/Set-LspSchemaPaths.ps1 -UpdateVSCode
#>
[CmdletBinding()]
param(
    [switch]$UpdateVSCode,

    # Test hook: redirect the VS Code settings.json path so -UpdateVSCode can be exercised
    # against a scratch file instead of the real user settings.
    [Parameter(DontShow)]
    [string]$SettingsPathOverride
)

$ErrorActionPreference = 'Stop'
$pluginRoot = Split-Path $PSScriptRoot -Parent

# Source of truth for the schema association (guarded against .lsp.json drift by
# tests/LspConfig.Tests.ps1). One schema, many file-match globs. Do NOT associate every *.json.
$schemaFile = 'cloud-flow-clientdata.schema.json'
$fileMatch = @(
    '**/Workflows/*.json'
    '**/Workflows/**/*.json'
    '**/*.flow.json'
)

$schemaPath = Join-Path $pluginRoot 'schemas' $schemaFile
if (-not (Test-Path $schemaPath)) {
    throw "Schema not found: $schemaPath"
}
# Build the file URI by hand (file:///C:/... on Windows, file:///home/... on POSIX). Do NOT use
# [uri].AbsoluteUri: on Linux PowerShell it yields an empty string for a rooted POSIX path.
$abs = (Resolve-Path $schemaPath).Path -replace '\\', '/'
if ($abs -notmatch '^/') { $abs = "/$abs" }   # Windows drive path (C:/...) needs the leading slash
$schemaUri = 'file://' + ($abs -replace ' ', '%20')

$jsonBlock = [ordered]@{
    validate = [ordered]@{ enable = $true }
    schemas  = @(
        [ordered]@{ fileMatch = $fileMatch; url = $schemaUri }
    )
}

# --- .lsp.json ---
$lspPath = Join-Path $pluginRoot '.lsp.json'
$lsp = Get-Content $lspPath -Raw | ConvertFrom-Json
$lsp.json.initializationOptions.settings.json = $jsonBlock
$lsp.json.settings.json = $jsonBlock
$lsp | ConvertTo-Json -Depth 20 | Set-Content $lspPath -Encoding UTF8
Write-Host "Updated $lspPath (schema -> $schemaUri)" -ForegroundColor Green

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
        $ourEntry = [ordered]@{ fileMatch = $fileMatch; url = $schemaUri }

        # ConvertFrom-Json silently accepts JSONC, so rewriting a commented settings.json would
        # strip every comment with no error. Refuse instead and show what to add. Comment tokens
        # must follow line-start or whitespace: bare '//' would match URLs (https://...) and bare
        # '/*' would match the glob patterns this script itself writes (**/*.json).
        $raw = Get-Content $settingsPath -Raw
        if ($raw -match '(?m)(^|\s)(//|/\*)') {
            Write-Host "$settingsPath contains comments, which this script cannot preserve; not modified." -ForegroundColor Yellow
            Write-Host "Add this to json.schemas manually:" -ForegroundColor Yellow
            Write-Host ($ourEntry | ConvertTo-Json -Depth 5)
        }
        else {
            $s = $raw | ConvertFrom-Json
            # Merge by url: keep the user's other schema associations, replace/append ours.
            $kept = @()
            if ($s.PSObject.Properties['json.schemas']) {
                $kept = @($s.'json.schemas' | Where-Object { $_.url -ne $schemaUri })
            }
            $s | Add-Member -NotePropertyName 'json.schemas' -NotePropertyValue ($kept + $ourEntry) -Force
            Copy-Item $settingsPath "$settingsPath.bak" -Force
            $s | ConvertTo-Json -Depth 20 | Set-Content $settingsPath -Encoding UTF8
            Write-Host "Updated $settingsPath (backup at $settingsPath.bak)" -ForegroundColor Green
        }
    }
    else { Write-Host "VS Code settings.json not found at $settingsPath; skipped." -ForegroundColor Yellow }
}

Write-Host "`nDone. Reload plugins (/reload-plugins) or restart VS Code to apply." -ForegroundColor Cyan
