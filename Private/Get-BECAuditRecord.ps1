function Get-BECAuditRecord {
    [CmdletBinding()]
    param (
        [string]$AuditLogSearchName,
        [string]$AuditLogSearchId,
        # Operation names to keep. Entra operations are matched with or without their trailing period.
        [string[]]$Operation,
        [string]$OperationLike
    )

    $audit_log_search = Resolve-BECAuditLogSearch -AuditLogSearchName $AuditLogSearchName -AuditLogSearchId $AuditLogSearchId

    # Records of a succeeded search never change, so the last search's records are reused
    # instead of downloading them again for every function
    if ($script:BECRecordCache.SearchId -ne $audit_log_search.Id) {
        Write-Host "Downloading audit records for '$($audit_log_search.DisplayName)'. This may take a moment..." -ForegroundColor Gray
        $records = @(Get-MgBetaSecurityAuditLogQueryRecord -AuditLogQueryId $audit_log_search.Id -All -ErrorAction Stop)
        $script:BECRecordCache = @{
            SearchId = $audit_log_search.Id
            Records = $records
        }
    }

    foreach ($record in $script:BECRecordCache.Records) {
        if ($null -eq $record.AuditData) {
            continue
        }

        $record_operation = "$($record.Operation)".TrimEnd(".")

        if ($Operation -and $record_operation -notin $Operation) {
            continue
        }
        if ($OperationLike -and $record_operation -notlike $OperationLike) {
            continue
        }

        $record
    }
}
