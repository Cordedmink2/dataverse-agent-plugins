#requires -Version 7
<#
.SYNOPSIS
    Validate a Dataverse customization XML file (or fragment) against the official XSD schemas.

.DESCRIPTION
    Picks the schema by the file's root element:
        ImportExportXml -> CustomizationsSolution.xsd   (whole customizations.xml)
        RibbonDiffXml   -> RibbonCore.xsd                (per-entity or application ribbon)
        SiteMap         -> SiteMap.xsd                   (app navigation)
        form / forms    -> FormXml.xsd                   (form definitions)
    Reports every error/warning with line/column and exits non-zero if any file fails.
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

    # Folder holding the .xsd set. Defaults to the plugin's bundled schemas/9.0.0.2090.
    [string]$SchemaDir,

    # Force a specific .xsd filename instead of auto-selecting by root element.
    [string]$Schema
)

$ErrorActionPreference = 'Stop'

if (-not $SchemaDir) {
    $SchemaDir = Join-Path $PSScriptRoot '..\schemas\9.0.0.2090'
}
if (-not (Test-Path $SchemaDir)) {
    Write-Error "Schema directory not found: $SchemaDir"
    exit 2
}
$SchemaDir = (Resolve-Path $SchemaDir).Path

$rootToSchema = @{
    'ImportExportXml' = 'CustomizationsSolution.xsd'
    'RibbonDiffXml'   = 'RibbonCore.xsd'
    'SiteMap'         = 'SiteMap.xsd'
    'form'            = 'FormXml.xsd'
    'forms'           = 'FormXml.xsd'
}

# pac unpacks forms as <forms><systemform>...<form/>...</systemform></forms>, but FormXml.xsd's
# root is <form>. For such files, validate each inner <form> (XPath) against the schema.
$innerElementByRoot = @{ 'forms' = 'systemform/form' }

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
    $root = Get-RootElementName $File

    if ($Schema) {
        $xsd = $Schema
    }
    elseif ($rootToSchema.ContainsKey($root)) {
        $xsd = $rootToSchema[$root]
    }
    else {
        Write-Host "SKIP  $File" -ForegroundColor Yellow
        Write-Host "      Unknown root element <$root> - no schema mapping. Use -Schema to force one." -ForegroundColor Yellow
        return [pscustomobject]@{ File = $File; Status = 'SKIP'; Errors = 0 }
    }

    $set = Get-SchemaSet $xsd

    $errors = [System.Collections.Generic.List[string]]::new()
    $handler = [System.Xml.Schema.ValidationEventHandler] {
        param($sender, $e)
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

    # Build the list of XML inputs to validate: either the whole file, or (for a pac wrapper
    # like <forms>) each inner fragment validated against the schema's real root element.
    $inputs = [System.Collections.Generic.List[object]]::new()
    if (-not $Schema -and $innerElementByRoot.ContainsKey($root)) {
        $doc = [System.Xml.XmlDocument]::new()
        $doc.Load($File)
        foreach ($node in $doc.DocumentElement.SelectNodes($innerElementByRoot[$root])) {
            $inputs.Add([System.IO.StringReader]::new($node.OuterXml))
        }
        if ($inputs.Count -eq 0) { $errors.Add("      [ERROR] no <$($innerElementByRoot[$root])> element found under <$root>") }
    }
    else {
        $inputs.Add($File)
    }

    foreach ($input in $inputs) {
        $reader = [System.Xml.XmlReader]::Create($input, $rs)
        try { while ($reader.Read()) { } }
        catch {
            # Well-formedness (parse) errors surface as exceptions, not validation events.
            $errors.Add("      [ERROR] " + $_.Exception.Message)
        }
        finally { $reader.Dispose() }
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
if (-not $files) { Write-Error "No files matched: $($Path -join ', ')"; exit 2 }

$results = foreach ($f in $files) { Test-OneFile $f }

$failed = @($results | Where-Object Status -eq 'FAIL')
Write-Host ""
Write-Host ("{0} file(s): {1} passed, {2} failed, {3} skipped" -f `
        $results.Count,
    (@($results | Where-Object Status -eq 'PASS')).Count,
    $failed.Count,
    (@($results | Where-Object Status -eq 'SKIP')).Count)

exit ([int]($failed.Count -gt 0))
