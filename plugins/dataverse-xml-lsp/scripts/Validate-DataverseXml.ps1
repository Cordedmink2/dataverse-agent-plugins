#requires -Version 7
<#
.SYNOPSIS
    Validate a Dataverse customization XML file (or fragment) against the official XSD schemas.

.DESCRIPTION
    Picks the schema by the file's root element:
        ImportExportXml -> CustomizationsSolution.xsd          (whole customizations.xml)
        importexportxml -> ParameterXml.xsd                    (import job / config parameters - lowercase!)
        RibbonDiffXml   -> RibbonCore.xsd                      (per-entity or application ribbon)
        SiteMap         -> SiteMap.xsd                         (app navigation)
        form / forms    -> FormXml.xsd                         (form definitions)
        fetch / savedquery -> Fetch.xsd                        (FetchXML / saved views)
        datadefinition / visualization -> VisualizationDataDescription.xsd  (charts)
        configuration   -> isv.config.xsd                      (legacy ISV.Config)
        viewers         -> reports.config.xsd                  (report viewer config)
    Reports every error/warning with line/column and exits non-zero if any file fails.
    Forcing -Schema validates the whole file as-is: the wrapper extraction that normally
    applies to <forms> and <visualization> files is skipped.
    This is the tool-agnostic backbone: run it before pac pack/import so bad edits fail loud.

.EXAMPLE
    ./Validate-DataverseXml.ps1 path/to/RibbonDiff.xml

.EXAMPLE
    ./Validate-DataverseXml.ps1 src/Entities/**/RibbonDiff.xml src/Other/Customizations.xml

.EXAMPLE
    ./Validate-DataverseXml.ps1 weird.xml -Schema RibbonCore.xsd   # force a schema
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0, ValueFromRemainingArguments)]
    [string[]]$Path,

    # Folder holding the .xsd set. Defaults to schemas/<schemaVersion from versions.json>.
    [string]$SchemaDir,

    # Force a specific .xsd filename instead of auto-selecting by root element.
    [string]$Schema
)

$ErrorActionPreference = 'Stop'

if (-not $SchemaDir) {
    $ver = (Get-Content (Join-Path $PSScriptRoot '..' 'versions.json') -Raw | ConvertFrom-Json).schemaVersion
    $SchemaDir = Join-Path $PSScriptRoot '..' 'schemas' $ver
}
if (-not (Test-Path $SchemaDir)) {
    # Console.Error, not Write-Error: under ErrorActionPreference=Stop the latter throws
    # and the documented exit code 2 would never be reached.
    [Console]::Error.WriteLine("Schema directory not found: $SchemaDir")
    exit 2
}
$SchemaDir = (Resolve-Path $SchemaDir).Path

# -Schema forces this xsd for every file. Functions below read this copy: the analyzer's
# unused-parameter rule only sees same-scope usage, so the parameter itself is consumed here.
$forcedSchema = $Schema

# Case-sensitive map: ParameterXml's root 'importexportxml' differs from the customizations
# root 'ImportExportXml' only by case, and PowerShell's @{} literal is case-insensitive.
$rootToSchema = [System.Collections.Generic.Dictionary[string, string]]::new()
$rootToSchema['ImportExportXml'] = 'CustomizationsSolution.xsd'
$rootToSchema['importexportxml'] = 'ParameterXml.xsd'
$rootToSchema['RibbonDiffXml']   = 'RibbonCore.xsd'
$rootToSchema['SiteMap']         = 'SiteMap.xsd'
$rootToSchema['form']            = 'FormXml.xsd'
$rootToSchema['forms']           = 'FormXml.xsd'
$rootToSchema['fetch']           = 'Fetch.xsd'
$rootToSchema['savedquery']      = 'Fetch.xsd'
$rootToSchema['datadefinition']  = 'VisualizationDataDescription.xsd'
$rootToSchema['visualization']   = 'VisualizationDataDescription.xsd'
$rootToSchema['configuration']   = 'isv.config.xsd'
$rootToSchema['viewers']         = 'reports.config.xsd'

# Wrapper roots: pac wraps the schema's real root in container elements. For these files,
# each inner fragment (path, relative to the document element) is validated instead.
# Case-sensitive for the same reason as $rootToSchema.
$innerElementByRoot = [System.Collections.Generic.Dictionary[string, string]]::new()
$innerElementByRoot['forms']         = 'systemform/form'
$innerElementByRoot['visualization'] = 'datadescription/datadefinition'

# Cache compiled schema sets by xsd filename so a batch of files loads each schema once.
$schemaSetCache = @{}

function Get-SchemaSet([string]$XsdFileName) {
    if ($schemaSetCache.ContainsKey($XsdFileName)) { return $schemaSetCache[$XsdFileName] }
    $xsdPath = Join-Path $SchemaDir $XsdFileName
    if (-not (Test-Path $xsdPath)) { throw "Schema '$XsdFileName' not found in $SchemaDir" }

    $set = [System.Xml.Schema.XmlSchemaSet]::new()
    # XmlUrlResolver lets xs:include (RibbonTypes/RibbonWSS, SiteMapType, ...) resolve from the same folder.
    $set.XmlResolver = [System.Xml.XmlUrlResolver]::new()
    # No targetNamespace in these schemas -> add under the null namespace.
    [void]$set.Add($null, $xsdPath)
    $set.Compile()
    $schemaSetCache[$XsdFileName] = $set
    return $set
}

function Get-RootElementName([string]$File) {
    $rs = [System.Xml.XmlReaderSettings]::new()
    $rs.DtdProcessing = [System.Xml.DtdProcessing]::Ignore
    $reader = [System.Xml.XmlReader]::Create($File, $rs)
    try {
        [void]$reader.MoveToContent()
        return $reader.LocalName
    }
    finally { $reader.Dispose() }
}

function Test-OneFile([string]$File) {
    try { return Test-OneFileCore $File }
    catch {
        # A missing or unparseable file fails on its own; the rest of the batch still runs
        # and the summary stays trustworthy.
        Write-Host "FAIL  $File" -ForegroundColor Red
        Write-Host ("      [ERROR] " + $_.Exception.Message) -ForegroundColor Red
        return [pscustomobject]@{ File = $File; Status = 'FAIL'; Errors = 1 }
    }
}

function Test-OneFileCore([string]$File) {
    $root = Get-RootElementName $File

    if ($forcedSchema) {
        $xsd = $forcedSchema
    }
    elseif ($rootToSchema.ContainsKey($root)) {
        $xsd = $rootToSchema[$root]
    }
    else {
        Write-Host "FAIL  $File" -ForegroundColor Red
        Write-Host "      Unknown root element <$root> - no schema mapping." -ForegroundColor Red
        Write-Host "      Supported roots: $(($rootToSchema.Keys | Sort-Object) -join ', ')." -ForegroundColor Red
        Write-Host "      Use -Schema <file.xsd> to force a schema." -ForegroundColor Red
        return [pscustomobject]@{ File = $File; Status = 'FAIL'; Errors = 1 }
    }

    $set = Get-SchemaSet $xsd

    $errors = [System.Collections.Generic.List[string]]::new()
    # No param block: the delegate's first (sender) argument is unused, and any named-but-unused
    # parameter trips PSReviewUnusedParameter. $args[1] is the ValidationEventArgs.
    $handler = [System.Xml.Schema.ValidationEventHandler] {
        $e = $args[1]
        $sev = if ($e.Severity -eq [System.Xml.Schema.XmlSeverityType]::Warning) { 'WARN' } else { 'ERROR' }
        $line = $e.Exception.LineNumber
        $col = $e.Exception.LinePosition
        $errors.Add(("      [{0}] line {1}, col {2}: {3}" -f $sev, $line, $col, $e.Message))
    }

    $rs = [System.Xml.XmlReaderSettings]::new()
    $rs.ValidationType = [System.Xml.ValidationType]::Schema
    $rs.Schemas = $set
    $rs.ValidationFlags = $rs.ValidationFlags `
        -bor [System.Xml.Schema.XmlSchemaValidationFlags]::ReportValidationWarnings
    $rs.add_ValidationEventHandler($handler)

    # Read one XML input (file path, TextReader or XmlReader) through the validating settings.
    # Well-formedness (parse) errors surface as exceptions, not validation events.
    function Read-WithValidation([object]$XmlInput) {
        $reader = [System.Xml.XmlReader]::Create($XmlInput, $rs)
        try { while ($reader.Read()) { } }
        catch { $errors.Add("      [ERROR] " + $_.Exception.Message) }
        finally { $reader.Dispose() }
    }

    # Validate the whole file, or - for a pac wrapper root like <forms> - each inner fragment.
    if (-not $forcedSchema -and $innerElementByRoot.ContainsKey($root)) {
        $parts = @($innerElementByRoot[$root] -split '/')
        $found = 0

        # ReadSubtree keeps the source reader's line info, so fragment errors report real
        # file positions (re-serializing OuterXml would restart numbering at line 1).
        $outerSettings = [System.Xml.XmlReaderSettings]::new()
        $outerSettings.DtdProcessing = [System.Xml.DtdProcessing]::Ignore
        $outer = [System.Xml.XmlReader]::Create($File, $outerSettings)
        try {
            $nameAtDepth = @{}
            while ($outer.Read()) {
                if ($outer.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
                $nameAtDepth[$outer.Depth] = $outer.LocalName
                if ($outer.Depth -ne $parts.Count) { continue }
                $onPath = $true
                for ($i = 0; $i -lt $parts.Count; $i++) {
                    if ($nameAtDepth[$i + 1] -cne $parts[$i]) { $onPath = $false; break }
                }
                if ($onPath) {
                    $found++
                    Read-WithValidation $outer.ReadSubtree()
                }
            }
        }
        finally { $outer.Dispose() }

        if ($found -eq 0) {
            # Some exports store the fragment as escaped XML text inside the wrapper (charts
            # especially: <datadescription>&lt;datadefinition ...&gt;). Unescape and validate
            # that; positions are then relative to the fragment, not the file.
            $fragName = $parts[-1]
            $doc = [System.Xml.XmlDocument]::new()
            $doc.Load($File)
            $container = $doc.DocumentElement.SelectSingleNode($parts[0])
            $text = if ($container) { $container.InnerText } else { '' }
            if ($text.Trim()) {
                $innerDoc = [System.Xml.XmlDocument]::new()
                $parsed = $false
                try {
                    $innerDoc.LoadXml($text)
                    $parsed = $true
                }
                catch {
                    $errors.Add("      [ERROR] <$($parts[0])> contains text that is not parseable XML; expected a <$fragName> element (possibly escaped). $($_.Exception.Message)")
                }
                if ($parsed) {
                    $frag = if ($innerDoc.DocumentElement.LocalName -ceq $fragName) { $innerDoc.DocumentElement }
                    else { $innerDoc.DocumentElement.SelectSingleNode(".//$fragName") }
                    if ($frag) {
                        $errors.Add("      [WARN] validating escaped XML inside <$($parts[0])>; line/col are relative to the unescaped fragment")
                        Read-WithValidation ([System.IO.StringReader]::new($frag.OuterXml))
                    }
                    else {
                        $errors.Add("      [ERROR] escaped XML inside <$($parts[0])> contains no <$fragName> element")
                    }
                }
            }
            else {
                $errors.Add("      [ERROR] no <$($innerElementByRoot[$root])> element found under <$root>")
            }
        }
    }
    else {
        Read-WithValidation $File
    }

    $errCount = ($errors | Where-Object { $_ -match '\[ERROR\]' }).Count
    if ($errCount -eq 0) {
        Write-Host "PASS  $File" -ForegroundColor Green -NoNewline
        Write-Host "  (root <$root> vs $xsd)" -ForegroundColor DarkGray
        $errors | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }  # warnings only
    }
    else {
        Write-Host "FAIL  $File" -ForegroundColor Red -NoNewline
        Write-Host "  (root <$root> vs $xsd)" -ForegroundColor DarkGray
        $errors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    }
    return [pscustomobject]@{ File = $File; Status = if ($errCount) { 'FAIL' } else { 'PASS' }; Errors = $errCount }
}

# Expand globs / directories into concrete files.
$files = foreach ($p in $Path) {
    $resolved = Get-ChildItem -Path $p -File -ErrorAction SilentlyContinue
    if ($resolved) { $resolved.FullName } else { $p }
}
$files = $files | Sort-Object -Unique
if (-not $files) { [Console]::Error.WriteLine("No files matched: $($Path -join ', ')"); exit 2 }

$results = foreach ($f in $files) { Test-OneFile $f }

$failed = @($results | Where-Object Status -eq 'FAIL')
Write-Host ""
Write-Host ("{0} file(s): {1} passed, {2} failed" -f `
        $results.Count,
    (@($results | Where-Object Status -eq 'PASS')).Count,
    $failed.Count)

exit ([int]($failed.Count -gt 0))
