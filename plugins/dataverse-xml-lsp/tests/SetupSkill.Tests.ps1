#requires -Version 7
<#
    Locks the setup skill's frontmatter. It must:
      - live at skills/dataverse-xml-lsp-setup/SKILL.md,
      - parse (have a YAML frontmatter block between the first two --- lines),
      - carry name: dataverse-xml-lsp-setup,
      - carry disable-model-invocation: true (setup is a one-time manual action; it must not
        auto-trigger and compete with the usage skill during editing).
#>

Describe 'setup skill frontmatter (dataverse-xml-lsp)' {

    BeforeAll {
        $pluginRoot = Split-Path $PSScriptRoot -Parent
        $script:skillPath = Join-Path $pluginRoot 'skills' 'dataverse-xml-lsp-setup' 'SKILL.md'
        $script:lines = Get-Content $script:skillPath

        # Parse the YAML frontmatter: the block between the first two --- lines.
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

    It 'SKILL.md exists at the relocated path' {
        Test-Path $script:skillPath | Should -BeTrue
    }

    It 'has a parseable YAML frontmatter block' {
        $fenceCount | Should -Be 2 -Because 'SKILL.md must open with a --- ... --- frontmatter block'
    }

    It 'name is dataverse-xml-lsp-setup' {
        $frontmatter['name'] | Should -Be 'dataverse-xml-lsp-setup'
    }

    It 'disables model invocation (no auto-trigger)' {
        $frontmatter['disable-model-invocation'] | Should -Be 'true' -Because 'setup is a one-time manual action; it must not auto-trigger'
    }
}
