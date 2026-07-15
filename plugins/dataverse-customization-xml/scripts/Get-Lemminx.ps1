#requires -Version 7
<#
.SYNOPSIS
    Download the native lemminx XML language server binary into the plugin's bin/ folder.

.DESCRIPTION
    The binary is large (~47 MB) and platform-specific, so it is NOT committed to the skills repo.
    Run this once after installing/syncing the plugin on a machine. Auto-detects the current OS/arch
    and pulls the version pinned in versions.json from the RedHat vscode-xml package on Open VSX -
    no Java required. Use -Latest to fetch the newest release instead of the pin.

    The binary is discovered inside the vsix (extension/server/lemminx-*), verified against the
    .sha256 shipped next to it, and only then swapped into bin/ under its original name (any
    previous bin/lemminx* file is removed, so bin/ only ever holds one binary). A successful
    install writes bin/.lemminx-version; re-runs skip the download when it matches unless -Force.

.EXAMPLE
    pwsh scripts/Get-Lemminx.ps1                       # auto-detected platform, pinned version
    pwsh scripts/Get-Lemminx.ps1 -TargetPlatform linux-x64
    pwsh scripts/Get-Lemminx.ps1 -Latest
    pwsh scripts/Get-Lemminx.ps1 -Force                # re-download even if already present
#>
[CmdletBinding()]
param(
    # Auto-detected from the current OS/arch when omitted.
    [ValidateSet('win32-x64', 'linux-x64', 'darwin-x64', 'darwin-arm64')]
    [string]$TargetPlatform,

    # Fetch the newest release instead of the version pinned in versions.json.
    [switch]$Latest,

    # Re-download even when bin/.lemminx-version says the wanted version is already installed.
    [switch]$Force
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
$markerPath = Join-Path $bin '.lemminx-version'

# The marker's binary filename must belong to the requested platform, otherwise switching
# platforms would be skipped as "already present". A foreign marker just re-downloads.
$platformFilePattern = switch ($TargetPlatform) {
    'win32-x64'    { 'lemminx-win32*' }
    'linux-x64'    { 'lemminx-linux*' }
    'darwin-x64'   { 'lemminx-osx-x86_64*' }
    'darwin-arm64' { 'lemminx-osx-aarch_64*' }
}

# bin/.lemminx-version holds "<version> <binary-filename>" from the last successful install.
function Test-LemminxInstalled([string]$WantedVersion) {
    if (-not (Test-Path $markerPath)) { return $false }
    # An empty or unparseable marker means "not installed", never a crash.
    $raw = Get-Content $markerPath -Raw
    if (-not $raw) { return $false }
    $tokens = @($raw.Trim() -split '\s+')
    if ($tokens.Count -ne 2) { return $false }
    return $tokens[0] -eq $WantedVersion -and
    $tokens[1] -like $platformFilePattern -and
    (Test-Path (Join-Path $bin $tokens[1]))
}

$version = if ($Latest) { 'latest' }
else { (Get-Content (Join-Path $pluginRoot 'versions.json') -Raw | ConvertFrom-Json).vscodeXmlVersion }

if (-not $Force -and -not $Latest -and (Test-LemminxInstalled $version)) {
    Write-Host "lemminx $version already present (use -Force to re-download)" -ForegroundColor Green
    exit 0
}

Write-Host "Querying Open VSX for redhat.vscode-xml ($TargetPlatform, $version)..." -ForegroundColor Cyan
try {
    $meta = Invoke-RestMethod "https://open-vsx.org/api/redhat/vscode-xml/$TargetPlatform/$version" `
        -TimeoutSec 60 -MaximumRetryCount 2 -RetryIntervalSec 5
}
catch {
    if ($_.Exception.Response.StatusCode -eq [System.Net.HttpStatusCode]::NotFound) {
        throw "Version $version not found for $TargetPlatform on Open VSX - check vscodeXmlVersion in versions.json or retry with -Latest."
    }
    throw
}

# -Latest only resolves to a concrete version here, so its marker check follows the query.
if (-not $Force -and $Latest -and (Test-LemminxInstalled $meta.version)) {
    Write-Host "lemminx $($meta.version) already present (use -Force to re-download)" -ForegroundColor Green
    exit 0
}

$url = $meta.files.download
Write-Host "Version $($meta.version); downloading vsix..." -ForegroundColor Cyan

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "vscode-xml-$([System.IO.Path]::GetRandomFileName()).vsix"
# Stage inside bin/ so the final Move-Item is an atomic same-volume rename (the system temp
# dir can sit on another drive); the leading dot keeps it out of lemminx* filters and globs.
$staged = Join-Path $bin ".staged-$([System.IO.Path]::GetRandomFileName())"
try {
    Invoke-WebRequest -Uri $url -OutFile $tmp -TimeoutSec 300 -MaximumRetryCount 2 -RetryIntervalSec 5
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    try { $zip = [System.IO.Compression.ZipFile]::OpenRead($tmp) }
    catch { throw "Failed to open the vsix downloaded from $url as a zip archive: $($_.Exception.Message)" }
    try {
        # The binary's name inside the vsix differs by OS/arch, so discover it rather than
        # hardcode it. Each binary ships with a .sha256 checksum entry - skip those - and the
        # truthy $_.Name clause skips directory entries (their Name is empty).
        $entries = @($zip.Entries | Where-Object {
                $_.FullName -like 'extension/server/lemminx-*' -and
                $_.FullName -notlike '*.sha256' -and
                $_.Name
            })
        if ($entries.Count -eq 0) {
            throw 'No lemminx-* binary found under extension/server/ in the vsix - layout changed?'
        }
        if ($entries.Count -gt 1) {
            throw "Expected exactly one lemminx-* binary in the vsix, found $($entries.Count): $($entries.FullName -join ', ')"
        }
        $entry = $entries[0]
        $exeName = $entry.Name

        # The binary's SHA256 ships next to it in the vsix, named after the binary minus any
        # extension (lemminx-win32.exe -> lemminx-win32.sha256, lemminx-linux-x86_64 ->
        # lemminx-linux-x86_64.sha256). Content: the hex digest, optionally followed by a filename.
        $shaName = [System.IO.Path]::ChangeExtension($entry.FullName, 'sha256')
        $shaEntry = $zip.Entries | Where-Object FullName -eq $shaName
        if (-not $shaEntry) { throw "No $shaName checksum entry in the vsix." }
        $reader = [System.IO.StreamReader]::new($shaEntry.Open())
        try { $expectedHash = ($reader.ReadToEnd().Trim() -split '\s+')[0] }
        finally { $reader.Dispose() }
        if ($expectedHash -notmatch '^[0-9a-fA-F]{64}$') {
            throw "Could not parse a SHA256 digest from $($shaEntry.FullName): got '$expectedHash'"
        }

        # Extract to the staging file and verify BEFORE replacing the installed binary, so a
        # corrupt or partial download never clobbers a working one.
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $staged, $true)
        $actualHash = (Get-FileHash $staged -Algorithm SHA256).Hash
        if ($actualHash -ne $expectedHash) {
            throw "SHA256 mismatch for ${exeName}: vsix checksum $expectedHash, extracted file $actualHash"
        }

        # A leftover binary from another platform/version would break downstream bin/lemminx* globs.
        Get-ChildItem $bin -Filter 'lemminx*' -File | Remove-Item -Force
        $out = Join-Path $bin $exeName
        Move-Item $staged $out -Force
        Write-Host "Extracted $out ($([math]::Round((Get-Item $out).Length/1MB,1)) MB, SHA256 verified)" -ForegroundColor Green
        if (-not $IsWindows) {
            chmod +x $out
            if ($LASTEXITCODE) { throw "chmod +x failed for $out" }
        }
        Set-Content -Path $markerPath -Value "$($meta.version) $exeName"
    }
    finally { $zip.Dispose() }
}
finally { Remove-Item $tmp, $staged -ErrorAction SilentlyContinue }

Write-Host "`nDone. Ensure .lsp.json 'command' points at bin/$exeName, then /reload-plugins." -ForegroundColor Cyan
