#requires -Version 7
# Runs the validator as a child process so exit codes are unambiguous.

BeforeDiscovery {
    $script:validValidatedByRoot = @(
        'ribbon.xml', 'sitemap.xml', 'form.xml', 'forms-wrapper.xml', 'fetch.xml',
        'savedquery.xml', 'datadefinition.xml', 'visualization-wrapper.xml',
        'isvconfig.xml', 'parameterxml.xml', 'viewers.xml', 'importexport.xml'
    )
    $script:invalidFixtures = @(
        'ribbon.xml', 'sitemap.xml', 'form.xml', 'fetch.xml', 'savedquery.xml',
        'datadefinition.xml', 'isvconfig.xml', 'parameterxml.xml', 'importexport.xml'
    )
}

BeforeAll {
    $script:validator = Join-Path $PSScriptRoot '..' 'scripts' 'Validate-DataverseXml.ps1'
    $script:fixtures  = Join-Path $PSScriptRoot 'fixtures'

    function Invoke-Validator {
        param([string[]]$Paths)
        pwsh -NoProfile -File $script:validator @Paths *> $null
        return $LASTEXITCODE
    }
}

Describe 'Validate-DataverseXml' {

    Context 'valid fixtures (auto root-element mapping)' {
        It 'passes <_>' -ForEach $validValidatedByRoot {
            Invoke-Validator (Join-Path $fixtures 'valid' $_) | Should -Be 0
        }
    }

    Context 'invalid fixtures' {
        It 'fails <_>' -ForEach $invalidFixtures {
            Invoke-Validator (Join-Path $fixtures 'invalid' $_) | Should -Be 1
        }
    }

    Context 'root-element handling' {
        It 'fails loud on an unknown root element' {
            $tmp = Join-Path ([IO.Path]::GetTempPath()) 'unknown-root-test.xml'
            Set-Content $tmp '<unknownroot />'
            try { Invoke-Validator $tmp | Should -Be 1 }
            finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
        }

        It 'is case-sensitive: ImportExportXml and importexportxml hit different schemas' {
            # Each is only valid against its own schema; if the map were case-insensitive
            # one of these two would validate against the wrong XSD and fail.
            Invoke-Validator (Join-Path $fixtures 'valid' 'importexport.xml') | Should -Be 0
            Invoke-Validator (Join-Path $fixtures 'valid' 'parameterxml.xml') | Should -Be 0
        }

        It 'reports failure when a wrapper contains no inner element' {
            $tmp = Join-Path ([IO.Path]::GetTempPath()) 'empty-forms-test.xml'
            Set-Content $tmp '<forms />'
            try { Invoke-Validator $tmp | Should -Be 1 }
            finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
        }
    }

    Context 'batch behaviour' {
        It 'returns 1 when any file in a batch fails' {
            Invoke-Validator @(
                (Join-Path $fixtures 'valid' 'ribbon.xml'),
                (Join-Path $fixtures 'invalid' 'ribbon.xml')
            ) | Should -Be 1
        }
    }
}
