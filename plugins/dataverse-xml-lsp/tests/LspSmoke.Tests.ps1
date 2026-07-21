#requires -Version 7
<#
    Drives the XML LSP end-to-end through the launcher shim (scripts/lsp-launch.mjs) via node, the
    same path Claude Code uses. scripts/lsp-smoke.mjs acts as an LSP client that supplies NO schema
    of its own (and answers any workspace/configuration pull with {}), opens the ribbon fixtures,
    and asserts the shim-injected fileAssociations fire: valid ribbon -> 0 diagnostics, invalid ->
    >= 1. This is the only test that exercises node + the shim + real lemminx together (the
    validator self-check bypasses them).

    Guarded to SKIP when node or the lemminx binary is absent, so a validator-only CI stays green.
#>

Describe 'XML LSP smoke (node + shim + lemminx)' {

    BeforeAll {
        $script:pluginRoot = Split-Path $PSScriptRoot -Parent
        $script:smoke = Join-Path $pluginRoot 'scripts' 'lsp-smoke.mjs'
        $binDir = Join-Path $pluginRoot 'bin'
        $script:haveLemminx = (Test-Path $binDir) -and @(Get-ChildItem $binDir -Filter 'lemminx*' -ErrorAction SilentlyContinue).Count -ge 1
        $script:haveNode = [bool](Get-Command node -ErrorAction SilentlyContinue)
    }

    It 'valid ribbon -> 0 diagnostics, invalid -> >= 1 (schema fires via the shim)' {
        if (-not $haveNode) { Set-ItResult -Skipped -Because 'node is not on PATH'; return }
        if (-not $haveLemminx) { Set-ItResult -Skipped -Because 'lemminx binary is not installed (bin/ empty)'; return }

        $out = & node $smoke 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "the shim-driven smoke should pass. Output:`n$($out -join "`n")"
    }
}
