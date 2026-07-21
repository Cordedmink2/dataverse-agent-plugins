#requires -Version 7
<#
    Install-Plugin.ps1 is documented as idempotent (safe to re-run after /plugin update). This
    proves it: run it TWICE and require the second run to exit 0.

    The run exercises the real install (JSON server + end-to-end smoke self-check), so it is guarded
    to SKIP cleanly when the environment can't support it without network work:
      - node absent          -> the shim/self-check can't launch,
      - server entry absent  -> Install-JsonLanguageServer would run `npm ci` (network).
    When both are present the run is warm and network-free.
#>

Describe 'Install-Plugin is idempotent (cloud-flow-json-lsp)' {

    BeforeAll {
        $script:pluginRoot = Split-Path $PSScriptRoot -Parent
        $script:install = Join-Path $pluginRoot 'scripts' 'Install-Plugin.ps1'
        $script:pwshExe = [Environment]::ProcessPath  # this host is pwsh 7 (#requires); reuse it

        $serverEntry = Join-Path $pluginRoot 'node_modules' 'vscode-langservers-extracted' 'lib' 'json-language-server' 'node' 'jsonServerMain.js'
        $script:haveServer = Test-Path $serverEntry
        $script:haveNode = [bool](Get-Command node -ErrorAction SilentlyContinue)
    }

    It 'exits 0 when run twice in a row' {
        if (-not $haveNode) { Set-ItResult -Skipped -Because 'node is not on PATH'; return }
        if (-not $haveServer) { Set-ItResult -Skipped -Because 'JSON language server is not installed (node_modules); a run would `npm ci`'; return }

        & $pwshExe -NoProfile -File $install *> $null
        $LASTEXITCODE | Should -Be 0 -Because 'first install run should succeed'
        $out = & $pwshExe -NoProfile -File $install 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "second (idempotent) run should also succeed. Output:`n$($out -join "`n")"
    }
}
