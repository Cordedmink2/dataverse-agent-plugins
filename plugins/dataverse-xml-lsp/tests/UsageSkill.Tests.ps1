#requires -Version 7
<#
    Locks the usage skill's auto-trigger contract and the two-skill registration:
      - skills/dataverse-xml-validate/SKILL.md carries name + a NON-EMPTY description (the
        description is what lets Claude auto-invoke it on Dataverse-XML work),
      - plugin.json lists both skill directories and both exist on disk.
#>

Describe 'usage skill + plugin skill registration (dataverse-xml-lsp)' {

    BeforeAll {
        $script:pluginRoot = Split-Path $PSScriptRoot -Parent
        $script:skillPath = Join-Path $pluginRoot 'skills' 'dataverse-xml-validate' 'SKILL.md'
        $script:lines = Get-Content $script:skillPath

        $fence = @()
        for ($i = 0; $i -lt $script:lines.Count; $i++) {
            if ($script:lines[$i].Trim() -eq '---') { $fence += $i }
            if ($fence.Count -eq 2) { break }
        }
        $script:frontmatter = @{}
        if ($fence.Count -eq 2) {
            foreach ($line in $script:lines[($fence[0] + 1)..($fence[1] - 1)]) {
                if ($line -match '^\s*([A-Za-z0-9_-]+)\s*:\s*(.*?)\s*$') {
                    $script:frontmatter[$Matches[1]] = $Matches[2]
                }
            }
        }

        $manifest = Get-Content (Join-Path $pluginRoot '.claude-plugin' 'plugin.json') -Raw | ConvertFrom-Json
        $script:skills = @($manifest.skills)
    }

    It 'name is dataverse-xml-validate' {
        $frontmatter['name'] | Should -Be 'dataverse-xml-validate'
    }

    It 'has a non-empty description (auto-trigger)' {
        ($script:lines -join "`n") | Should -Match 'description:\s*>-'
        $descIdx = ($script:lines | Select-String -Pattern '^\s*description:' | Select-Object -First 1).LineNumber
        $descIdx | Should -Not -BeNullOrEmpty
        ($script:lines[$descIdx].Trim().Length) | Should -BeGreaterThan 0 -Because 'the folded description must have content on the next line'
    }

    It 'points to docs/guide.md rather than duplicating it' {
        ($script:lines -join "`n") | Should -Match 'docs/guide\.md'
    }

    It 'does not inline the ribbon recipe (kept in the guide)' {
        ($script:lines -join "`n") | Should -Not -Match 'CommandDefinition'
    }

    It 'registers both skill directories, and both exist' {
        $script:skills | Should -Contain './skills/dataverse-xml-lsp-setup'
        $script:skills | Should -Contain './skills/dataverse-xml-validate'
        foreach ($s in $script:skills) {
            Test-Path (Join-Path $pluginRoot ($s -replace '^\./','')) | Should -BeTrue -Because "$s must exist"
        }
    }
}
