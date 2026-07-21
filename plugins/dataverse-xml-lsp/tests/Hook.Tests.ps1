#requires -Version 7
<#
    Drives the PostToolUse gate (hooks/validate-wrapper.mjs) via node with synthetic stdin JSON.
    Gate cases (node only): no-path / non-xml / LSP-owned root -> exit 0, no validator spawn.
    Delegation cases (node + schemas): each validator-owned root's valid fixture -> 0, invalid -> 2.
    Skips when node or the schema set is absent so a minimal CI stays green.
#>

Describe 'wrapper hook gate (validate-wrapper.mjs)' {

    BeforeDiscovery {
        $script:ownedFixtures = @(
            @{ Root = 'form';            File = 'form.xml' }
            @{ Root = 'forms';           File = 'forms-wrapper.xml' }
            @{ Root = 'datadefinition';  File = 'datadefinition.xml' }
            @{ Root = 'visualization';   File = 'visualization-wrapper.xml' }
            @{ Root = 'viewers';         File = 'viewers.xml' }
            @{ Root = 'importexportxml'; File = 'parameterxml.xml' }
        )
    }

    BeforeAll {
        $script:pluginRoot = Split-Path $PSScriptRoot -Parent
        $script:hook = Join-Path $pluginRoot 'hooks' 'validate-wrapper.mjs'
        $script:fixtures = Join-Path $PSScriptRoot 'fixtures'
        $script:haveNode = [bool](Get-Command node -ErrorAction SilentlyContinue)
        $ver = (Get-Content (Join-Path $pluginRoot 'versions.json') -Raw | ConvertFrom-Json).schemaVersion
        $script:haveSchemas = Test-Path (Join-Path $pluginRoot 'schemas' $ver)

        function Invoke-Hook([string]$FilePath) {
            $json = @{ tool_input = @{ file_path = $FilePath } } | ConvertTo-Json -Compress
            $out = $json | & node $script:hook 2>&1
            [pscustomobject]@{ Exit = $LASTEXITCODE; Output = ($out -join "`n") }
        }
    }

    It 'exits 0 for a non-xml path (no validator spawn)' {
        if (-not $haveNode) { Set-ItResult -Skipped -Because 'node not on PATH'; return }
        (Invoke-Hook (Join-Path $fixtures 'nope.txt')).Exit | Should -Be 0
    }

    It 'exits 0 for an LSP-owned root (ribbon)' {
        if (-not $haveNode) { Set-ItResult -Skipped -Because 'node not on PATH'; return }
        (Invoke-Hook (Join-Path $fixtures 'valid' 'ribbon.xml')).Exit | Should -Be 0
    }

    It 'exits 0 for uppercase ImportExportXml even when the file is invalid (case-sensitive gate did not spawn)' {
        if (-not $haveNode) { Set-ItResult -Skipped -Because 'node not on PATH'; return }
        # invalid/importexport.xml has root <ImportExportXml> (uppercase, LSP-owned). An INVALID file
        # exiting 0 proves the gate excluded it by case WITHOUT running the validator; a case-
        # insensitive gate would have spawned it and returned 2.
        (Invoke-Hook (Join-Path $fixtures 'invalid' 'importexport.xml')).Exit | Should -Be 0
    }

    It 'valid <root> fixture -> exit 0' -ForEach $ownedFixtures {
        if (-not $haveNode) { Set-ItResult -Skipped -Because 'node not on PATH'; return }
        if (-not $haveSchemas) { Set-ItResult -Skipped -Because 'schema set not installed'; return }
        (Invoke-Hook (Join-Path $fixtures 'valid' $File)).Exit | Should -Be 0 -Because "$Root valid fixture must pass"
    }

    It 'invalid <root> fixture -> exit 2 with validator output' -ForEach $ownedFixtures {
        if (-not $haveNode) { Set-ItResult -Skipped -Because 'node not on PATH'; return }
        if (-not $haveSchemas) { Set-ItResult -Skipped -Because 'schema set not installed'; return }
        $r = Invoke-Hook (Join-Path $fixtures 'invalid' $File)
        $r.Exit | Should -Be 2 -Because "$Root invalid fixture must fail the hook"
        $r.Output | Should -Match 'validation failed'
    }
}
