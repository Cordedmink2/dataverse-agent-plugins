#requires -Version 7
<#
    Two guards:
    1. File-association parity between the $fileMatch / $schemaFile source of truth in
       scripts/Set-LspSchemaPaths.ps1 (what setup stamps) and .lsp.json (what ships and what the
       JSON language server actually loads). Compares glob list + schema filename, not the full
       url: the committed url is a relative path and a machine-local file URI once stamped, but
       the filename part is identical in both forms.
    2. The bundled schema actually distinguishes the known-good fixtures from the known-bad ones,
       via PowerShell's built-in Test-Json (the same schema the LSP loads).
#>

Describe 'flow LSP config parity (.lsp.json vs Set-LspSchemaPaths.ps1)' {

    BeforeAll {
        $pluginRoot = Split-Path $PSScriptRoot -Parent

        # Extract $fileMatch and $schemaFile from the script without executing it: dot-sourcing
        # would rewrite .lsp.json as a side effect. SafeGetValue reads the literals from the AST.
        $scriptPath = Join-Path $pluginRoot 'scripts' 'Set-LspSchemaPaths.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)

        # Collect every string literal on the assignment's right-hand side. Works for both a single
        # string ($schemaFile = '...') and a newline- or comma-separated array (@('a' 'b' 'c')).
        function Get-AssignmentString([System.Management.Automation.Language.Ast]$Root, [string]$Name) {
            $assign = $Root.Find({
                    param($node)
                    $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $node.Left.VariablePath.UserPath -eq $Name
                }, $true)
            if (-not $assign) { throw "No `$$Name assignment found in $scriptPath" }
            return @($assign.Right.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) | ForEach-Object { $_.Value })
        }

        $script:expectedGlobs = @(Get-AssignmentString $ast 'fileMatch') | Sort-Object
        $script:expectedSchemaFile = @(Get-AssignmentString $ast 'schemaFile')[0]
        $script:lsp = Get-Content (Join-Path $pluginRoot '.lsp.json') -Raw | ConvertFrom-Json

        function Get-Assoc($Schemas) {
            $entry = @($Schemas)[0]
            [pscustomobject]@{
                Globs      = @($entry.fileMatch) | Sort-Object
                SchemaFile = ($entry.url -split '[\\/]')[-1]
            }
        }
    }

    It 'has a non-empty glob list and a schema file in the script' {
        $expectedGlobs.Count | Should -BeGreaterThan 0
        $expectedSchemaFile | Should -Not -BeNullOrEmpty
    }

    It 'matches in the initializationOptions settings block' {
        $a = Get-Assoc $lsp.json.initializationOptions.settings.json.schemas
        $a.Globs | Should -Be $expectedGlobs
        $a.SchemaFile | Should -Be $expectedSchemaFile
    }

    It 'matches in the workspace settings block' {
        $a = Get-Assoc $lsp.json.settings.json.schemas
        $a.Globs | Should -Be $expectedGlobs
        $a.SchemaFile | Should -Be $expectedSchemaFile
    }

    It 'launches the JSON server via node + jsonServerMain.js' {
        $lsp.json.command | Should -Be 'node'
        ($lsp.json.args -join ' ') | Should -Match 'jsonServerMain\.js'
        ($lsp.json.args -join ' ') | Should -Match '--stdio'
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
}
