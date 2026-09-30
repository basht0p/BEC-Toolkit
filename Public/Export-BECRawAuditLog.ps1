function Export-BECRawAuditLog {
    [CmdletBinding()]
    param (
        [string]$AuditLogSearchName,
        [string]$AuditLogSearchId,
        [string]$OutputPath = (Join-Path $pwd "BEC_Export"),
        [string]$FileName = "RawAuditLog.csv",
        [switch]$PassThru
    )

    $audit_log_records = Get-BECAuditRecord -AuditLogSearchName $AuditLogSearchName -AuditLogSearchId $AuditLogSearchId

    # Every record of the search, unparsed: the standard record fields plus AuditData as JSON
    $raw_records = @(foreach ($audit_log_record in $audit_log_records) {
        [PSCustomObject]@{
            Id = $audit_log_record.Id
            CreatedDateTime = ConvertTo-BECTimestamp $audit_log_record.CreatedDateTime
            Operation = $audit_log_record.Operation
            AuditLogRecordType = "$($audit_log_record.AuditLogRecordType)"
            Service = $audit_log_record.Service
            UserPrincipalName = $audit_log_record.UserPrincipalName
            UserId = $audit_log_record.UserId
            UserType = "$($audit_log_record.UserType)"
            ClientIp = $audit_log_record.ClientIp
            ObjectId = $audit_log_record.ObjectId
            AuditData = ConvertTo-Json -InputObject $audit_log_record.AuditData.AdditionalProperties -Depth 20 -Compress
        }
    })

    Export-BECResult -InputObject $raw_records -OutputPath $OutputPath -FileName $FileName -Description "raw audit record(s)"

    if ($PassThru) {
        return $raw_records
    }
}
