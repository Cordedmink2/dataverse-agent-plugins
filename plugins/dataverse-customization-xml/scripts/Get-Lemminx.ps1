#requires -Version 7
<#
.SYNOPSIS
    Download the native lemminx XML language server binary into the plugin's bin/ folder.

.DESCRIPTION
    The binary is large (~47 MB) and platform-specific, so it is NOT committed to the skills repo.
    Run this once after installing/syncing the plugin on a machine. Pulls the native (GraalVM)
    lemminx from the RedHat vscode-xml package on Open VSX — no Java required.

.EXAMPLE
    pwsh scripts/Get-Lemminx.ps1                       # win32-x64 (default)
    pwsh scripts/Get-Lemminx.ps1 -TargetPlatform linux-x64
#>
[CmdletBinding()]
param(
    [ValidateSet('win32-x64', 'linux-x64', 'darwin-x64', 'darwin-arm64')]
    [string]$TargetPlatform = 'win32-x64'
)

$ErrorActionPreference = 'Stop'
$pluginRoot = Split-Path $PSScriptRoot -Parent
$bin = Join-Path $pluginRoot 'bin'
New-Item -ItemType Directory -Force -Path $bin | Out-Null

# The native binary name inside the vsix differs by OS.
$exeName = switch -Wildcard ($TargetPlatform) {
    'win32-*'  { 'lemminx-win32.exe' }
    'linux-*'  { 'lemminx-linux' }
    'darwin-*' { 'lemminx-osx-x86_64' }
}

Write-Host "Querying Open VSX for redhat.vscode-xml ($TargetPlatform)..." -ForegroundColor Cyan
$meta = Invoke-RestMethod "https://open-vsx.org/api/redhat/vscode-xml/$TargetPlatform/latest" -TimeoutSec 60
$url = $meta.files.download
Write-Host "Version $($meta.version); downloading vsix..." -ForegroundColor Cyan

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "vscode-xml-$([System.IO.Path]::GetRandomFileName()).vsix"
try {
    Invoke-WebRequest -Uri $url -OutFile $tmp -TimeoutSec 300
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($tmp)
    try {
        $entry = $zip.Entries | Where-Object FullName -eq "extension/server/$exeName"
        if (-not $entry) { throw "Could not find extension/server/$exeName in the vsix." }
        $out = Join-Path $bin $exeName
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $out, $true)
        Write-Host "Extracted $out ($([math]::Round((Get-Item $out).Length/1MB,1)) MB)" -ForegroundColor Green
    }
    finally { $zip.Dispose() }
}
finally { Remove-Item $tmp -ErrorAction SilentlyContinue }

Write-Host "`nDone. Ensure .lsp.json 'command' points at bin/$exeName, then /reload-plugins." -ForegroundColor Cyan
