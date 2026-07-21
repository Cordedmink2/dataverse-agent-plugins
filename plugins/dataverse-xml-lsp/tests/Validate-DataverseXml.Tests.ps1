#requires -Version 7
# Runs the validator as a child process so exit codes are unambiguous.

BeforeDiscovery {
    $script:validValidatedByRoot = @(
        'ribbon.xml', 'sitemap.xml', 'form.xml', 'forms-wrapper.xml', 'fetch.xml',
        'savedquery.xml', 'datadefinition.xml', 'visualization-wrapper.xml',
        'visualization-escaped.xml', 'isvconfig.xml', 'parameterxml.xml',
        'viewers.xml', 'importexport.xml'
    )
    $script:invalidFixtures = @(
        'ribbon.xml', 'sitemap.xml', 'form.xml', 'forms-wrapper.xml', 'fetch.xml',
        'savedquery.xml', 'datadefinition.xml', 'isvconfig.xml', 'parameterxml.xml',
        'viewers.xml', 'importexport.xml'
    )
}

BeforeAll {
    $script:validator = Join-Path $PSScriptRoot '..' 'scripts' 'Validate-DataverseXml.ps1'
    $script:fixtures  = Join-Path $PSScriptRoot 'fixtures'

    # Captures the validator's output alongside the exit code so a failed assertion
    # shows the actual diagnostics instead of a bare exit-code mismatch.
    function Invoke-Validator {
        param([string[]]$Paths)
        $out = pwsh -NoProfile -File $script:validator @Paths 2>&1 | Out-String
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $out }
    }
}

Describe 'Validate-DataverseXml' {

    Context 'valid fixtures (auto root-element mapping)' {
        It 'passes <_>' -ForEach $validValidatedByRoot {
            $r = Invoke-Validator (Join-Path $fixtures 'valid' $_)
            $r.ExitCode | Should -Be 0 -Because $r.Output
        }
    }

    Context 'invalid fixtures' {
        It 'fails <_>' -ForEach $invalidFixtures {
            $r = Invoke-Validator (Join-Path $fixtures 'invalid' $_)
            $r.ExitCode | Should -Be 1 -Because $r.Output
        }
    }

    Context 'root-element handling' {
        It 'fails loud on an unknown root element' {
            $tmp = Join-Path $TestDrive 'unknown-root-test.xml'
            Set-Content $tmp '<unknownroot />'
            $r = Invoke-Validator $tmp
            $r.ExitCode | Should -Be 1 -Because $r.Output
            $r.Output | Should -Match 'Unknown root element' -Because $r.Output
        }

        It 'is case-sensitive: ImportExportXml and importexportxml hit different schemas' {
            # Each is only valid against its own schema; if the map were case-insensitive
            # one of these two would validate against the wrong XSD and fail.
            $r1 = Invoke-Validator (Join-Path $fixtures 'valid' 'importexport.xml')
            $r1.ExitCode | Should -Be 0 -Because $r1.Output
            $r2 = Invoke-Validator (Join-Path $fixtures 'valid' 'parameterxml.xml')
            $r2.ExitCode | Should -Be 0 -Because $r2.Output
        }

        It 'reports failure when a wrapper contains no inner element' {
            $tmp = Join-Path $TestDrive 'empty-forms-test.xml'
            Set-Content $tmp '<forms />'
            $r = Invoke-Validator $tmp
            $r.ExitCode | Should -Be 1 -Because $r.Output
        }

        It 'exits 2 when the schema directory is missing' {
            pwsh -NoProfile -File $script:validator (Join-Path $fixtures 'valid' 'ribbon.xml') `
                -SchemaDir (Join-Path $TestDrive 'no-such-dir') *> $null
            $LASTEXITCODE | Should -Be 2
        }
    }

    Context 'wrapper fragment diagnostics' {
        It 'reports the original file line for an error inside a wrapper fragment' {
            $r = Invoke-Validator (Join-Path $fixtures 'invalid' 'forms-wrapper.xml')
            $r.ExitCode | Should -Be 1 -Because $r.Output
            # The <column> missing its required width attribute sits on line 7 of the fixture;
            # fragment re-serialization would report a fragment-relative line instead.
            $r.Output | Should -Match 'line 7,' -Because $r.Output
        }
    }

    Context 'escaped chart datadescription' {
        It 'fails with an explicit message when datadescription text is not parseable XML' {
            $tmp = Join-Path $TestDrive 'garbage-datadescription.xml'
            Set-Content $tmp '<visualization><datadescription>not xml at all</datadescription></visualization>'
            $r = Invoke-Validator $tmp
            $r.ExitCode | Should -Be 1 -Because $r.Output
            $r.Output | Should -Match 'not parseable XML' -Because $r.Output
        }
    }

    Context 'batch behaviour' {
        It 'returns 1 when any file in a batch fails' {
            $r = Invoke-Validator @(
                (Join-Path $fixtures 'valid' 'ribbon.xml'),
                (Join-Path $fixtures 'invalid' 'ribbon.xml')
            )
            $r.ExitCode | Should -Be 1 -Because $r.Output
        }

        It 'continues past an unparseable file and still validates the rest' {
            $bad = Join-Path $TestDrive 'unparseable.xml'
            Set-Content $bad ''
            $r = Invoke-Validator @($bad, (Join-Path $fixtures 'valid' 'ribbon.xml'))
            $r.ExitCode | Should -Be 1 -Because $r.Output
            $r.Output | Should -Match 'PASS\s+.*ribbon\.xml' -Because $r.Output
            $r.Output | Should -Match '2 file\(s\): 1 passed, 1 failed' -Because $r.Output
        }

        It 'fails per-file (not aborting) for a nonexistent path' {
            $r = Invoke-Validator @(
                (Join-Path $TestDrive 'does-not-exist.xml'),
                (Join-Path $fixtures 'valid' 'sitemap.xml')
            )
            $r.ExitCode | Should -Be 1 -Because $r.Output
            $r.Output | Should -Match '2 file\(s\): 1 passed, 1 failed' -Because $r.Output
        }
    }
}
