#requires -Version 7
<#
    Locks the setup skill's no-auto-trigger behavior. The root SKILL.md must:
      - parse (have a YAML frontmatter block between the first two --- lines),
      - carry name: cloud-flow-json-lsp-setup,
      - carry NO description: key (a description would let Claude auto-invoke the skill; setup is
        run once by hand, never triggered from context).
#>

Describe 'setup skill frontmatter (cloud-flow-json-lsp)' {

    BeforeAll {
        $pluginRoot = Split-Path $PSScriptRoot -Parent
        $script:skillPath = Join-Path $pluginRoot 'SKILL.md'
        $script:lines = Get-Content $script:skillPath

        # Parse the YAML frontmatter: the block between the first two --- lines. Fail loud if the
        # file has no such block (a bare key/value list is all these skills carry).
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
        $script:fenceCount = $fence.Count
    }

    It 'has a parseable YAML frontmatter block' {
        $fenceCount | Should -Be 2 -Because 'SKILL.md must open with a --- ... --- frontmatter block'
    }

    It 'name is cloud-flow-json-lsp-setup' {
        $frontmatter['name'] | Should -Be 'cloud-flow-json-lsp-setup'
    }

    It 'has NO description key (no auto-trigger)' {
        $frontmatter.ContainsKey('description') | Should -BeFalse -Because 'a description would let the skill auto-trigger; setup is run by hand'
    }
}
