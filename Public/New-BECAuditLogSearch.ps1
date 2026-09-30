function New-BECAuditLogSearch {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [string[]]$UserPrincipalName,
        [string[]]$IPAddress,
        [datetime]$StartDateTime = (Get-Date).AddDays(-30),
        [datetime]$EndDateTime = (Get-Date),
        [string]$DisplayName,
        [string[]]$Operation,
        [string[]]$RecordType,
        [switch]$Wait,
        [ValidateRange(1, 1440)]
        [int]$TimeoutMinutes = 120,
        [ValidateRange(1, 3600)]
        [int]$PollIntervalSeconds = 30
    )

    if (-not $UserPrincipalName -and -not $IPAddress) {
        throw "Specify -UserPrincipalName or -IPAddress. A search across every user in the tenant will usually hit the record count limit."
    }
    if ($StartDateTime -ge $EndDateTime) {
        throw "-StartDateTime must be earlier than -EndDateTime."
    }

    if (-not $DisplayName) {
        $subject = if ($UserPrincipalName) { $UserPrincipalName[0] } else { $IPAddress[0] }
        $DisplayName = "BEC-$subject-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    }

    $body = @{
        "@odata.type" = "#microsoft.graph.security.auditLogQuery"
        displayName = $DisplayName
        filterStartDateTime = $StartDateTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
        filterEndDateTime = $EndDateTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($UserPrincipalName) { $body.userPrincipalNameFilters = @($UserPrincipalName) }
    if ($IPAddress) { $body.ipAddressFilters = @($IPAddress) }
    if ($Operation) { $body.operationFilters = @($Operation) }
    if ($RecordType) { $body.recordTypeFilters = @($RecordType) }

    if (-not $PSCmdlet.ShouldProcess($DisplayName, "Create audit log search")) {
        return
    }

    Connect-BECGraph

    $audit_log_search = New-MgBetaSecurityAuditLogQuery -BodyParameter $body -ErrorAction Stop
    Write-Host "Created audit log search '$($audit_log_search.DisplayName)' ($($audit_log_search.Id))" -BackgroundColor Black -ForegroundColor Yellow

    if ($Wait) {
        $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
        $last_status = "$($audit_log_search.Status)"

        while ("$($audit_log_search.Status)" -in @("", "notStarted", "running")) {
            if ((Get-Date) -gt $deadline) {
                Write-Warning "Audit log search '$DisplayName' is still $($audit_log_search.Status) after $TimeoutMinutes minute(s). Check again later with -AuditLogSearchId $($audit_log_search.Id)."
                break
            }

            Start-Sleep -Seconds $PollIntervalSeconds
            $audit_log_search = Get-MgBetaSecurityAuditLogQuery -AuditLogQueryId $audit_log_search.Id -ErrorAction Stop

            if ("$($audit_log_search.Status)" -ne $last_status) {
                $last_status = "$($audit_log_search.Status)"
                Write-Host "Audit log search status: $last_status" -ForegroundColor Gray
            }
        }

        if ("$($audit_log_search.Status)" -in @("failed", "cancelled")) {
            Write-Warning "Audit log search '$DisplayName' $($audit_log_search.Status)."
        }
    }

    return $audit_log_search
}
