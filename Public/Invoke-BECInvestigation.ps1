function Invoke-BECInvestigation {
    [CmdletBinding()]
    param (
        [string]$AuditLogSearchName,
        [string]$AuditLogSearchId,
        [string]$OutputPath,
        [switch]$SkipSignInLogs
    )

    Write-Host "Running full BEC investigation. This may take a moment..."

    # Resolve once so every export comes from the same audit log search
    $audit_log_search = Resolve-BECAuditLogSearch -AuditLogSearchName $AuditLogSearchName -AuditLogSearchId $AuditLogSearchId

    # Each run gets its own folder so earlier results are never overwritten
    if (-not $OutputPath) {
        $safe_search_name = $audit_log_search.DisplayName -replace '[^\w.-]', '_'
        $OutputPath = Join-Path (Join-Path $pwd "BEC_Export") "$(Get-Date -Format 'yyyyMMdd-HHmmss')_$safe_search_name"
    }

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
        SignInLogs = @()
    }

    if (-not $SkipSignInLogs) {
        if (@($audit_log_search.UserPrincipalNameFilters | Where-Object { $_ }).Count -eq 0) {
            Write-Host "Skipping sign-in logs: the audit log search doesn't filter on users. Run Get-BECSignInLogs -UserPrincipalName to get them." -ForegroundColor Gray
        } else {
            try {
                $investigation.SignInLogs = Get-BECSignInLogs @search_parameters
            } catch {
                Write-Warning "Couldn't read sign-in logs, continuing without them: $($_.Exception.Message)"
            }
        }
    }

    $ip_summary = @(Get-BECActivitySummary -Investigation $investigation -GroupBy IPAddress)
    $session_summary = @(Get-BECActivitySummary -Investigation $investigation -GroupBy Session)
    Export-BECResult -InputObject $ip_summary -OutputPath $OutputPath -FileName "IPSummary.csv" -Description "IP address(es)"
    Export-BECResult -InputObject $session_summary -OutputPath $OutputPath -FileName "SessionSummary.csv" -Description "session(s)"

    Export-BECRawAuditLog -AuditLogSearchId $audit_log_search.Id -OutputPath $OutputPath

    $investigation | Add-Member -NotePropertyName IPSummary -NotePropertyValue $ip_summary
    $investigation | Add-Member -NotePropertyName SessionSummary -NotePropertyValue $session_summary
    $investigation | Add-Member -NotePropertyName AuditLogSearch -NotePropertyValue $audit_log_search
    $investigation | Add-Member -NotePropertyName OutputPath -NotePropertyValue $OutputPath

    Write-Host "Investigation complete. Results are in $OutputPath" -BackgroundColor Black -ForegroundColor Yellow

    return $investigation
}
