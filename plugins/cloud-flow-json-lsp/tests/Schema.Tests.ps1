#requires -Version 7
# Headless (node-independent) schema regression via Test-Json. Every fixture under
# tests/fixtures/{valid,invalid} must match/violate the bundled clientdata schema.

Describe 'cloud-flow clientdata schema (Test-Json)' {
    BeforeAll {
        $script:pluginRoot = Split-Path $PSScriptRoot -Parent
        $script:schema = Join-Path $pluginRoot 'schemas' 'cloud-flow-clientdata.schema.json'
        $script:fixtures = Join-Path $PSScriptRoot 'fixtures'

        function Test-Fixture([string]$Path) {
            try { Get-Content $Path -Raw | Test-Json -SchemaFile $script:schema -ErrorAction Stop; return $true }
            catch { return $false }
        }
    }

    It 'passes every valid fixture' {
        foreach ($f in Get-ChildItem (Join-Path $fixtures 'valid') -Filter *.json) {
            (Test-Fixture $f.FullName) | Should -BeTrue -Because "$($f.Name) should be schema-valid"
        }
    }

    It 'fails every invalid fixture' {
        foreach ($f in Get-ChildItem (Join-Path $fixtures 'invalid') -Filter *.json) {
            (Test-Fixture $f.FullName) | Should -BeFalse -Because "$($f.Name) should violate the schema"
        }
    }

    It 'rejects a bogus runAfter status on a NESTED action specifically' {
        (Test-Fixture (Join-Path $fixtures 'invalid' 'nested-bad-runafter-status.json')) | Should -BeFalse
    }
}
