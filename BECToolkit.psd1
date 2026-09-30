@{
    RootModule = 'BECToolkit.psm1'
    ModuleVersion = '2.0.0'
    GUID = 'c51175cf-2cba-4d05-b20b-0f682f783697'
    Author = 'basht0p'
    Description = 'Investigate Business Email Compromise (BEC) by querying Microsoft 365 audit logs and Entra sign-in logs through Microsoft Graph.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    RequiredModules = @(
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.Beta.Security'
    )

    FunctionsToExport = @(
        'Get-BECAccessedMailItems',
        'Get-BECAuthentications',
        'Get-BECDeletedMailItems',
        'Get-BECFileOperations',
        'Get-BECIdentityChanges',
        'Get-BECInboxRules',
        'Get-BECMailboxChanges',
        'Get-BECSentMailItems',
        'Get-BECSharingOperations',
        'Invoke-BECInvestigation'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags = @('BEC', 'Security', 'IncidentResponse', 'Microsoft365', 'Purview', 'AuditLog', 'MicrosoftGraph')
            ProjectUri = 'https://github.com/basht0p/BEC-Toolkit'
        }
    }
}
