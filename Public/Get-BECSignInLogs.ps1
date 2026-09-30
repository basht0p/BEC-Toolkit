function Get-BECSignInLogs {
    [CmdletBinding()]
    param (
        [string[]]$UserPrincipalName,
        [datetime]$StartDateTime,
        [datetime]$EndDateTime,
        [string]$AuditLogSearchName,
        [string]$AuditLogSearchId,
        [switch]$InteractiveOnly,
        [switch]$ExportCsv,
        [string]$OutputPath = (Join-Path $pwd "BEC_Export")
    )

    Connect-BECGraph

    # Users and dates not given are taken from the audit log search
    $has_start = $PSBoundParameters.ContainsKey("StartDateTime")
    $has_end = $PSBoundParameters.ContainsKey("EndDateTime")
    if (-not $UserPrincipalName -or -not $has_start -or -not $has_end) {
        $audit_log_search = Resolve-BECAuditLogSearch -AuditLogSearchName $AuditLogSearchName -AuditLogSearchId $AuditLogSearchId
        if (-not $UserPrincipalName) { $UserPrincipalName = @($audit_log_search.UserPrincipalNameFilters | Where-Object { $_ }) }
        if (-not $has_start -and $audit_log_search.FilterStartDateTime) { $StartDateTime = $audit_log_search.FilterStartDateTime; $has_start = $true }
        if (-not $has_end -and $audit_log_search.FilterEndDateTime) { $EndDateTime = $audit_log_search.FilterEndDateTime; $has_end = $true }
    }

    if (-not $UserPrincipalName) {
        throw "No users to look up. Pass -UserPrincipalName, or use an audit log search that filters on users."
    }
    if (-not $has_start -or -not $has_end) {
        throw "No date range to look up. Pass -StartDateTime and -EndDateTime."
    }

    if ($StartDateTime -lt (Get-Date).AddDays(-30)) {
        Write-Warning "Entra keeps sign-in logs for 30 days (7 days without Microsoft Entra ID P1 or P2). Sign-ins before then won't be returned."
    }

    $start = $StartDateTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
    $end = $EndDateTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)

    $sign_ins = @(foreach ($user in $UserPrincipalName) {
        # Without an explicit event type filter the API returns interactive sign-ins only.
        # Non-interactive sign-ins matter here: token replay from an attacker shows up there.
        $filter = "createdDateTime ge $start and createdDateTime le $end and userPrincipalName eq '$($user.Replace("'", "''"))'"
        if (-not $InteractiveOnly) {
            $filter += " and signInEventTypes/any(t: t eq 'interactiveUser' or t eq 'nonInteractiveUser')"
        }

        $uri = "beta/auditLogs/signIns?`$filter=$([uri]::EscapeDataString($filter))"

        while ($uri) {
            $response = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop

            foreach ($sign_in in $response.value) {
                $event_types = if ($sign_in.signInEventTypes) { @($sign_in.signInEventTypes) } elseif ($sign_in.isInteractive) { @("interactiveUser") } else { @("nonInteractiveUser") }

                [PSCustomObject]@{
                    CreationTime = ConvertTo-BECTimestamp $sign_in.createdDateTime
                    UserId = $sign_in.userPrincipalName
                    ClientIPAddress = $sign_in.ipAddress
                    SessionId = $sign_in.sessionId
                    SignInEventType = $event_types -join ","
                    AppDisplayName = $sign_in.appDisplayName
                    ClientAppUsed = $sign_in.clientAppUsed
                    ResourceDisplayName = $sign_in.resourceDisplayName
                    City = $sign_in.location.city
                    State = $sign_in.location.state
                    Country = $sign_in.location.countryOrRegion
                    AutonomousSystemNumber = $sign_in.autonomousSystemNumber
                    ErrorCode = $sign_in.status.errorCode
                    FailureReason = $sign_in.status.failureReason
                    ConditionalAccessStatus = $sign_in.conditionalAccessStatus
                    AuthenticationRequirement = $sign_in.authenticationRequirement
                    RiskLevelDuringSignIn = $sign_in.riskLevelDuringSignIn
                    RiskState = $sign_in.riskState
                    RiskEventTypes = @($sign_in.riskEventTypes_v2) -join ","
                    OperatingSystem = $sign_in.deviceDetail.operatingSystem
                    Browser = $sign_in.deviceDetail.browser
                    DeviceId = $sign_in.deviceDetail.deviceId
                    IsCompliant = $sign_in.deviceDetail.isCompliant
                    IsManaged = $sign_in.deviceDetail.isManaged
                    TrustType = $sign_in.deviceDetail.trustType
                    UserAgent = $sign_in.userAgent
                    IncomingTokenType = $sign_in.incomingTokenType
                    CorrelationId = $sign_in.correlationId
                    UniqueTokenIdentifier = $sign_in.uniqueTokenIdentifier
                    Id = $sign_in.id
                }
            }

            $uri = $response["@odata.nextLink"]
        }
    })

    $sign_ins = @($sign_ins | Sort-Object CreationTime)

    if ($ExportCsv) {
        Export-BECResult -InputObject $sign_ins -OutputPath $OutputPath -FileName "SignInLogs.csv" -Description "sign-in(s)"
    }

    return $sign_ins
}
