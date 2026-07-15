#requires -Version 7
<#
.SYNOPSIS
    Download the native lemminx XML language server binary into the plugin's bin/ folder.

.DESCRIPTION
    The binary is large (~47 MB) and platform-specific, so it is NOT committed to the skills repo.
    Run this once after installing/syncing the plugin on a machine. Auto-detects the current OS/arch
    and pulls the version pinned in versions.json from the RedHat vscode-xml package on Open VSX —
    no Java required. Use -Latest to fetch the newest release instead of the pin.

.EXAMPLE
    pwsh scripts/Get-Lemminx.ps1                       # auto-detected platform, pinned version
    pwsh scripts/Get-Lemminx.ps1 -TargetPlatform linux-x64
    pwsh scripts/Get-Lemminx.ps1 -Latest
#>
[CmdletBinding()]
param(
    # Auto-detected from the current OS/arch when omitted.
    [ValidateSet('win32-x64', 'linux-x64', 'darwin-x64', 'darwin-arm64')]
    [string]$TargetPlatform,

    # Fetch the newest release instead of the version pinned in versions.json.
    [switch]$Latest
)

$ErrorActionPreference = 'Stop'
$pluginRoot = Split-Path $PSScriptRoot -Parent

if (-not $TargetPlatform) {
    $arm = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64'
    $TargetPlatform = if ($IsWindows) { 'win32-x64' }
    elseif ($IsMacOS) { if ($arm) { 'darwin-arm64' } else { 'darwin-x64' } }
    else { 'linux-x64' }
}

$bin = Join-Path $pluginRoot 'bin'
New-Item -ItemType Directory -Force -Path $bin | Out-Null

# The native binary name inside the vsix differs by OS.
$exeName = switch -Wildcard ($TargetPlatform) {
    'win32-*'  { 'lemminx-win32.exe' }
    'linux-*'  { 'lemminx-linux' }
    'darwin-*' { 'lemminx-osx-x86_64' }
}

$version = if ($Latest) { 'latest' }
else { (Get-Content (Join-Path $pluginRoot 'versions.json') -Raw | ConvertFrom-Json).vscodeXmlVersion }

Write-Host "Querying Open VSX for redhat.vscode-xml ($TargetPlatform, $version)..." -ForegroundColor Cyan
$meta = Invoke-RestMethod "https://open-vsx.org/api/redhat/vscode-xml/$TargetPlatform/$version" -TimeoutSec 60
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
        if (-not $IsWindows) { chmod +x $out }
    }
    finally { $zip.Dispose() }
}
finally { Remove-Item $tmp -ErrorAction SilentlyContinue }

Write-Host "`nDone. Ensure .lsp.json 'command' points at bin/$exeName, then /reload-plugins." -ForegroundColor Cyan
