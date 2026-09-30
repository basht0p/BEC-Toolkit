function Invoke-BECInvestigation {
    [CmdletBinding()]
    param (
        [string]$AuditLogSearchName,
        [string]$AuditLogSearchId,
        [string]$OutputPath = (Join-Path $pwd "BEC_Export")
    )

    Write-Host "Running full BEC investigation. This may take a moment..."

    # Resolve once so every export comes from the same audit log search
    $audit_log_search = Resolve-BECAuditLogSearch -AuditLogSearchName $AuditLogSearchName -AuditLogSearchId $AuditLogSearchId
    $search_parameters = @{
        AuditLogSearchId = $audit_log_search.Id
        ExportCsv = $true
        OutputPath = $OutputPath
    }

    $investigation = [PSCustomObject]@{
        AccessedMail = Get-BECAccessedMailItems @search_parameters
        SentMail = Get-BECSentMailItems @search_parameters
        DeletedMail = Get-BECDeletedMailItems @search_parameters
        InboxRules = Get-BECInboxRules @search_parameters
        MailboxChanges = Get-BECMailboxChanges @search_parameters
        SharingOperations = Get-BECSharingOperations @search_parameters
        FileOperations = Get-BECFileOperations @search_parameters
        Authentications = Get-BECAuthentications @search_parameters
        IdentityChanges = Get-BECIdentityChanges @search_parameters
    }

    return $investigation
}
