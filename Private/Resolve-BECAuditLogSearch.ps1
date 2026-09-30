function Resolve-BECAuditLogSearch {
    [CmdletBinding()]
    param (
        [string]$AuditLogSearchName,
        [string]$AuditLogSearchId
    )

    Connect-BECGraph

    if ($AuditLogSearchId) {
        $audit_log_search = Get-MgBetaSecurityAuditLogQuery -AuditLogQueryId $AuditLogSearchId -ErrorAction Stop
    } elseif (-not $AuditLogSearchName -or $AuditLogSearchName -eq "undefined") {
        $succeeded_searches = @(Get-MgBetaSecurityAuditLogQuery | Where-Object Status -eq "succeeded")
        if ($succeeded_searches.Count -eq 0) {
            throw "No succeeded audit log searches found. Create one with New-BECAuditLogSearch, or pass -AuditLogSearchName."
        }
        $audit_log_search = $succeeded_searches[0]
        Write-Host "Using audit log search '$($audit_log_search.DisplayName)' ($($audit_log_search.Id))" -ForegroundColor Gray
    } else {
        $matching_searches = @(Get-MgBetaSecurityAuditLogQuery | Where-Object DisplayName -eq $AuditLogSearchName)
        if ($matching_searches.Count -eq 0) {
            throw "No audit log search found with the name: $AuditLogSearchName"
        }
        if ($matching_searches.Count -gt 1) {
            $search_list = ($matching_searches | ForEach-Object { "$($_.Id) ($($_.Status))" }) -join ", "
            throw "Multiple audit log searches found with the name: $AuditLogSearchName. Use -AuditLogSearchId with one of: $search_list"
        }
        $audit_log_search = $matching_searches[0]
    }

    if ($audit_log_search.Status -ne "succeeded") {
        throw "Audit log search '$($audit_log_search.DisplayName)' ($($audit_log_search.Id)) has status '$($audit_log_search.Status)'. Wait for it to succeed before investigating."
    }

    # Warn once per search, not once per function that reads it
    if (-not $script:BECWarnedSearchIds.Contains($audit_log_search.Id)) {
        $limit_exceeded = $audit_log_search.IsRecordCountLimitExceeded
        if ($null -eq $limit_exceeded -and $null -ne $audit_log_search.AdditionalProperties) {
            $limit_exceeded = $audit_log_search.AdditionalProperties["isRecordCountLimitExceeded"]
        }
        if ($limit_exceeded -eq $true) {
            Write-Warning "Audit log search '$($audit_log_search.DisplayName)' exceeded its record count limit. Results are incomplete; narrow the search (users, dates, operations) and run it again."
            [void]$script:BECWarnedSearchIds.Add($audit_log_search.Id)
        }
    }

    return $audit_log_search
}
