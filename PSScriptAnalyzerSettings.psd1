@{
    Severity     = @('Error', 'Warning')
    # Write-Host is deliberate: these are interactive console tools reporting colored status.
    ExcludeRules = @('PSAvoidUsingWriteHost')
}
