#requires -Version 7
<#
    Two guards:
    1. .lsp.json launches the portable launcher shim (scripts/lsp-launch.mjs) via node with
       ${CLAUDE_PLUGIN_ROOT} args, and carries NO machine-local absolute path. The shim resolves
       the schema at launch, so nothing is stamped per machine.
    2. The bundled schema actually distinguishes the known-good fixtures from the known-bad ones,
       via PowerShell's built-in Test-Json (the same schema the LSP loads).
#>

Describe 'flow LSP config is portable (.lsp.json launches the shim)' {

    BeforeAll {
        $pluginRoot = Split-Path $PSScriptRoot -Parent
        $script:lspPath = Join-Path $pluginRoot '.lsp.json'
        $script:raw = Get-Content $script:lspPath -Raw
        $script:lsp = $script:raw | ConvertFrom-Json
    }

    It 'launches the shim via node with ${CLAUDE_PLUGIN_ROOT} args' {
        $lsp.json.command | Should -Be 'node'
        $argstr = $lsp.json.args -join ' '
        $argstr | Should -Match 'lsp-launch\.mjs'
        $argstr | Should -Match '\$\{CLAUDE_PLUGIN_ROOT\}'
        $argstr | Should -Match '--stdio'
    }

    It 'keeps the extension-to-language wiring' {
        $lsp.json.extensionToLanguage.'.json' | Should -Be 'json'
    }

    It 'contains no machine-local absolute path' {
        # No stamped file URI, and no bare absolute path (Windows drive or POSIX root) outside the
        # ${CLAUDE_PLUGIN_ROOT} variable. Everything machine-specific is resolved at launch.
        $raw | Should -Not -Match 'file://'
        $raw | Should -Not -Match '[A-Za-z]:[\\/]'
        foreach ($a in $lsp.json.args) {
            if ($a -notmatch '\$\{CLAUDE_PLUGIN_ROOT\}') { $a | Should -Not -Match '^([A-Za-z]:[\\/]|/)' }
        }
    }
}

Describe 'bundled schema distinguishes valid from invalid fixtures' {

    BeforeAll {
        $pluginRoot = Split-Path $PSScriptRoot -Parent
        $script:schema = Join-Path $pluginRoot 'schemas' 'cloud-flow-clientdata.schema.json'
        $script:validDir = Join-Path $pluginRoot 'tests' 'fixtures' 'valid'
        $script:invalidDir = Join-Path $pluginRoot 'tests' 'fixtures' 'invalid'

        function Test-Fixture([string]$Path) {
            # Test-Json throws on a schema violation; treat that as "invalid", a clean $true as "valid".
            try { return [bool](Get-Content $Path -Raw | Test-Json -SchemaFile $script:schema -ErrorAction Stop) }
            catch { return $false }
        }
    }

    It 'accepts every valid fixture' {
        $files = @(Get-ChildItem $validDir -Filter *.json)
        $files.Count | Should -BeGreaterThan 0
        foreach ($f in $files) { Test-Fixture $f.FullName | Should -BeTrue -Because "$($f.Name) should be valid" }
    }

    It 'rejects every invalid fixture' {
        $files = @(Get-ChildItem $invalidDir -Filter *.json)
        $files.Count | Should -BeGreaterThan 0
        foreach ($f in $files) { Test-Fixture $f.FullName | Should -BeFalse -Because "$($f.Name) should be rejected" }
    }

    It 'rejects a bogus runAfter status on a nested action' {
        # nested-bad-runafter-status.json puts the bad status on an action inside a Foreach;
        # a non-recursive schema would miss it.
        $bad = Join-Path $invalidDir 'nested-bad-runafter-status.json'
        [bool](Get-Content $bad -Raw | Test-Json -SchemaFile $schema) | Should -BeFalse
    }
}
