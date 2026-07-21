#requires -Version 7
<#
    Install-Plugin.ps1 is documented as idempotent (safe to re-run after /plugin update or a schema
    version bump). This proves it: run it TWICE and require the second run to exit 0.

    The run exercises the real install (schema + lemminx resolution + self-check), so it is guarded
    to SKIP cleanly when the environment can't support it without network work:
      - node absent            -> the shim/self-check can't launch,
      - lemminx binary absent  -> Get-Lemminx would download ~47 MB,
      - schema set absent      -> Get-Schemas would download Microsoft's Schemas.zip.
    When all three are present the run is warm and network-free.
#>

Describe 'Install-Plugin is idempotent (dataverse-xml-lsp)' {

    BeforeAll {
        $script:pluginRoot = Split-Path $PSScriptRoot -Parent
        $script:install = Join-Path $pluginRoot 'scripts' 'Install-Plugin.ps1'
        $script:pwshExe = [Environment]::ProcessPath  # this host is pwsh 7 (#requires); reuse it

        $binDir = Join-Path $pluginRoot 'bin'
        $script:haveLemminx = (Test-Path $binDir) -and @(Get-ChildItem $binDir -Filter 'lemminx*' -ErrorAction SilentlyContinue).Count -ge 1
        $ver = (Get-Content (Join-Path $pluginRoot 'versions.json') -Raw | ConvertFrom-Json).schemaVersion
        $schemaDir = Join-Path $pluginRoot 'schemas' $ver
        $script:haveSchemas = (Test-Path $schemaDir) -and @(Get-ChildItem $schemaDir -Filter '*.xsd' -ErrorAction SilentlyContinue).Count -ge 1
        $script:haveNode = [bool](Get-Command node -ErrorAction SilentlyContinue)
    }

    It 'exits 0 when run twice in a row' {
        if (-not $haveNode) { Set-ItResult -Skipped -Because 'node is not on PATH'; return }
        if (-not $haveLemminx) { Set-ItResult -Skipped -Because 'lemminx binary is not installed (bin/ empty); a run would download it'; return }
        if (-not $haveSchemas) { Set-ItResult -Skipped -Because 'schema set is not present; a run would download Schemas.zip'; return }

        & $pwshExe -NoProfile -File $install *> $null
        $LASTEXITCODE | Should -Be 0 -Because 'first install run should succeed'
        $out = & $pwshExe -NoProfile -File $install 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "second (idempotent) run should also succeed. Output:`n$($out -join "`n")"
    }
}
