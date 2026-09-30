@{
    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        # Status messages are written with Write-Host on purpose for colored console output.
        # Since PowerShell 5 they go to the information stream, so -InformationAction can silence them.
        'PSAvoidUsingWriteHost',
        # Public function names such as Get-BECAccessedMailItems predate the linter and are kept for compatibility
        'PSUseSingularNouns'
    )
}
