#requires -Version 7
<#
.SYNOPSIS
    Wire the bundled flow schema into VS Code user settings (optional editor integration).

.DESCRIPTION
    Claude Code no longer needs any stamped path: the launcher shim (scripts/lsp-launch.mjs)
    resolves the absolute schema url at launch from ${CLAUDE_PLUGIN_ROOT}, so .lsp.json stays
    portable and is never edited. This script now only serves the separate VS Code consumer, whose
    settings.json cannot reference ${CLAUDE_PLUGIN_ROOT} and so needs a machine-local file URI.

.EXAMPLE
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

if (-not $UpdateVSCode) {
    Write-Host "Nothing to do: Claude Code resolves the schema at launch via the shim. Pass -UpdateVSCode to wire the VS Code editor path." -ForegroundColor Yellow
    return
}

# The schema association VS Code needs: one schema, many file-match globs. Do NOT associate
# every *.json. Kept in sync with the globs the shim (scripts/lsp-launch.mjs) injects.
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

Write-Host "`nDone. Restart VS Code to apply." -ForegroundColor Cyan
