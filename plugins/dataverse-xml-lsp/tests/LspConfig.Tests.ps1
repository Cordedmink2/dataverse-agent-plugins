#requires -Version 7
<#
    Guards that .lsp.json is portable: it launches the launcher shim (scripts/lsp-launch.mjs) via
    node with ${CLAUDE_PLUGIN_ROOT} args and carries NO machine-local absolute path or per-OS
    lemminx binary name. The shim discovers the binary and resolves the XSD systemIds at launch, so
    nothing is stamped per machine. (The XSD associations themselves are exercised end-to-end by
    the validator and its fixtures in Validate-DataverseXml.Tests.ps1.)
#>

Describe 'XML LSP config is portable (.lsp.json launches the shim)' {

    BeforeAll {
        $pluginRoot = Split-Path $PSScriptRoot -Parent
        $script:lspPath = Join-Path $pluginRoot '.lsp.json'
        $script:raw = Get-Content $script:lspPath -Raw
        $script:lsp = $script:raw | ConvertFrom-Json
    }

    It 'launches the shim via node with ${CLAUDE_PLUGIN_ROOT} args' {
        $lsp.xml.command | Should -Be 'node'
        $argstr = $lsp.xml.args -join ' '
        $argstr | Should -Match 'lsp-launch\.mjs'
        $argstr | Should -Match '\$\{CLAUDE_PLUGIN_ROOT\}'
        $argstr | Should -Match '--stdio'
    }

    It 'keeps the extension-to-language wiring' {
        $lsp.xml.extensionToLanguage.'.xml' | Should -Be 'xml'
        $lsp.xml.extensionToLanguage.'.fetchxml' | Should -Be 'xml'
    }

    It 'contains no machine-local absolute path or lemminx binary name' {
        # No stamped file URI, no bare absolute path (Windows drive or POSIX root) outside the
        # ${CLAUDE_PLUGIN_ROOT} variable, and no per-OS lemminx binary name. All resolved at launch.
        $raw | Should -Not -Match 'file://'
        $raw | Should -Not -Match '[A-Za-z]:[\\/]'
        $raw | Should -Not -Match 'lemminx'
        foreach ($a in $lsp.xml.args) {
            if ($a -notmatch '\$\{CLAUDE_PLUGIN_ROOT\}') { $a | Should -Not -Match '^([A-Za-z]:[\\/]|/)' }
        }
    }
}
