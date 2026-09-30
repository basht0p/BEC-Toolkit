function Get-BECAuthentications {
    [CmdletBinding()]
    param (
        [string]$AuditLogSearchName,
        [string]$AuditLogSearchId,
        [switch]$ExportCsv,
        [string]$OutputPath = (Join-Path $pwd "BEC_Export")
    )

    $valid_authentication_operations = @(
        "UserLoggedIn",
        "UserLoginFailed"
    )

    $audit_log_records = Get-BECAuditRecord -AuditLogSearchName $AuditLogSearchName -AuditLogSearchId $AuditLogSearchId -Operation $valid_authentication_operations

    $authentications = @(foreach ($audit_log_record in $audit_log_records) {
        $record = $audit_log_record.AuditData.AdditionalProperties
        $extended_properties = ConvertTo-BECPropertyTable $record.ExtendedProperties
        $device_properties = ConvertTo-BECPropertyTable $record.DeviceProperties

        [PSCustomObject]@{
            CreationTime = $record.CreationTime
            UserId = $record.UserId
            UserKey = $record.UserKey
            ClientIPAddress = $record.ClientIP
            ActorIPAddress = $record.ActorIpAddress
            Operation = $record.Operation
            ResultStatus = $record.ResultStatus
            ErrorNumber = $record.ErrorNumber
            LogonError = $record.LogonError
            ApplicationId = $record.ApplicationId
            UserAgent = $extended_properties["UserAgent"]
            OS = $device_properties["OS"]
            BrowserType = $device_properties["BrowserType"]
            IsCompliant = $device_properties["IsCompliant"]
            IsCompliantAndManaged = $device_properties["IsCompliantAndManaged"]
            SessionId = $device_properties["SessionId"]
        }
    })

    if ($ExportCsv) {
        Export-BECResult -InputObject $authentications -OutputPath $OutputPath -FileName "Authentications.csv" -Description "authentication(s)"
    }

    return $authentications
}
