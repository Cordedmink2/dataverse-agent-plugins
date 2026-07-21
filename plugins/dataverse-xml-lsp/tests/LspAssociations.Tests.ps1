#requires -Version 7
<#
    The XML LSP and the validator must not both own the same files. The validator owns pac's
    WRAPPER files - <forms> (form definitions) and <visualization> (charts) - because it extracts
    and validates the inner fragment (systemform/form, datadescription/datadefinition). lemminx
    cannot do that: pointed at a wrapper file it validates the WHOLE document against a schema whose
    root is the inner element, so it false-positives on the wrapper root
    (e.g. "cvc-elt.1.a: Cannot find the declaration of element 'forms'").

    The design (docs/superpowers/specs) states the LSP is not associated to the wrapper roots the
    validator owns. This reads the association map straight out of the shim (scripts/lsp-launch.mjs)
    and asserts no association glob targets a forms or chart wrapper file.
#>

Describe 'XML LSP is not associated to validator-owned wrapper roots' {

    BeforeAll {
        $pluginRoot = Split-Path $PSScriptRoot -Parent
        $shim = Join-Path $pluginRoot 'scripts' 'lsp-launch.mjs'
        $raw = Get-Content $shim -Raw

        # Pull `const assoc = { 'glob': 'File.xsd', ... };` out of the shim and parse the pairs.
        $block = [regex]::Match($raw, 'const\s+assoc\s*=\s*\{(.*?)\};', 'Singleline')
        $script:assoc = @{}
        foreach ($m in [regex]::Matches($block.Groups[1].Value, "'([^']+)'\s*:\s*'([^']+)'")) {
            $script:assoc[$m.Groups[1].Value] = $m.Groups[2].Value
        }

        # Minimal glob -> regex (supports **, *, and character classes like [Cc]); paths use '/'.
        function Test-GlobMatch([string]$Glob, [string]$Path) {
            $rx = [regex]::Escape($Glob)
            $rx = $rx -replace '\\\*\\\*/', '(?:.*/)?'   # **/  -> any (or no) leading dirs
            $rx = $rx -replace '\\\*\\\*', '.*'           # **   -> anything
            $rx = $rx -replace '\\\*', '[^/]*'            # *    -> anything but a separator
            $rx = $rx -replace '\\\[', '['
            $rx = $rx -replace '\\\]', ']'
            return [regex]::IsMatch($Path, "^$rx$")
        }
        $script:matcher = ${function:Test-GlobMatch}

        # Representative pac-unpacked wrapper file paths (root <forms> / <visualization>).
        $script:formsWrapper = 'src/Entities/account/FormXml/main/00000000-0000-0000-0000-000000000000.xml'
    }

    It 'parses a non-empty association map from the shim' {
        $assoc.Count | Should -BeGreaterThan 0
    }

    It 'does not associate the visualization/chart wrapper (validator-owned)' {
        # Charts are validator-only: no association may point at the chart schema.
        $assoc.Values | Should -Not -Contain 'VisualizationDataDescription.xsd'
    }

    It 'does not associate pac forms wrapper files (validator-owned)' {
        $hit = @()
        foreach ($glob in $assoc.Keys) {
            if (& $matcher $glob $formsWrapper) { $hit += "$glob -> $($assoc[$glob])" }
        }
        $hit | Should -BeNullOrEmpty -Because "no LSP association may match a pac <forms> wrapper file ($formsWrapper); lemminx would false-positive on the <forms> root. Matched: $($hit -join ', ')"
    }
}
