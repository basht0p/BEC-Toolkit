function Connect-BECGraph {
    [CmdletBinding()]
    param (
        [string[]]$Scopes = @("AuditLog.Read.All", "AuditLogsQuery.Read.All")
    )

    $context = Get-MgContext

    if ($null -eq $context) {
        Connect-MgGraph -Scopes $Scopes -ErrorAction Stop -NoWelcome
        return
    }

    # App-only contexts carry no delegated scopes; their permissions come from the app registration
    if ($context.AuthType -ne "Delegated") {
        return
    }

    $missing_scopes = @($Scopes | Where-Object { $_ -notin @($context.Scopes) })
    if ($missing_scopes.Count -gt 0) {
        Write-Host "Reconnecting to Microsoft Graph to add scope(s): $($missing_scopes -join ', ')" -ForegroundColor Gray
        $all_scopes = @(@($context.Scopes) + $missing_scopes | Where-Object { $_ })
        Connect-MgGraph -Scopes $all_scopes -TenantId $context.TenantId -ErrorAction Stop -NoWelcome
    }
}
