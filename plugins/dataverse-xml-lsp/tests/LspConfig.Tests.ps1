#requires -Version 7
<#
    Guards the two sources of truth for lemminx file associations against drift:
    the $assoc map in scripts/Set-LspSchemaPaths.ps1 (what setup stamps) and .lsp.json
    (what ships and what lemminx actually loads). Compares pattern -> schema-filename
    pairs, not full systemId paths: the systemId is a relative path in the committed
    file and a machine-local absolute path once setup has stamped it, but the filename
    part is identical in both forms.
#>

Describe 'lemminx file association parity (.lsp.json vs Set-LspSchemaPaths.ps1)' {

    BeforeAll {
        $pluginRoot = Split-Path $PSScriptRoot -Parent

        # Extract $assoc from the script without executing it: dot-sourcing would rewrite
        # .lsp.json as a side effect. SafeGetValue evaluates the hashtable literal from
        # the AST with no code execution.
        $scriptPath = Join-Path $pluginRoot 'scripts' 'Set-LspSchemaPaths.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
        $assocAssignment = $ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $node.Left.VariablePath.UserPath -eq 'assoc'
            }, $true)
        if (-not $assocAssignment) { throw "No `$assoc assignment found in $scriptPath" }
        $hashAst = $assocAssignment.Find({ param($node) $node -is [System.Management.Automation.Language.HashtableAst] }, $true)
        if (-not $hashAst) { throw "The `$assoc assignment in $scriptPath is no longer a hashtable literal; update this test's extraction." }
        $assoc = $hashAst.SafeGetValue()

        # Script scope: these are read by the It blocks below, which run in their own scope.
        $script:expectedPairs = @($assoc.GetEnumerator() | ForEach-Object { '{0} -> {1}' -f $_.Key, $_.Value }) | Sort-Object

        $script:lsp = Get-Content (Join-Path $pluginRoot '.lsp.json') -Raw | ConvertFrom-Json

        function Get-PairSet($FileAssociations) {
            @($FileAssociations | ForEach-Object {
                    '{0} -> {1}' -f $_.pattern, ($_.systemId -split '/')[-1]
                }) | Sort-Object
        }
    }

    It 'has a non-empty association map in the script' {
        $expectedPairs.Count | Should -BeGreaterThan 0
    }

    It 'matches in the initializationOptions settings block' {
        Get-PairSet $lsp.xml.initializationOptions.settings.xml.fileAssociations |
            Should -Be $expectedPairs
    }

    It 'matches in the workspace settings block' {
        Get-PairSet $lsp.xml.settings.xml.fileAssociations |
            Should -Be $expectedPairs
    }
}
