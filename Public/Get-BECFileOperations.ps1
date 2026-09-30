function Get-BECFileOperations {
    [CmdletBinding()]
    param (
        [string]$AuditLogSearchName,
        [string]$AuditLogSearchId,
        [switch]$ExportCsv,
        [string]$OutputPath = (Join-Path $pwd "BEC_Export")
    )

    $audit_log_records = Get-BECAuditRecord -AuditLogSearchName $AuditLogSearchName -AuditLogSearchId $AuditLogSearchId -OperationLike "File*"

    $file_operations = @(foreach ($audit_log_record in $audit_log_records) {
        $record = $audit_log_record.AuditData.AdditionalProperties

        [PSCustomObject]@{
            CreationTime = $record.CreationTime
            UserId = $record.UserId
            ClientIPAddress = $record.ClientIP
            Operation = $record.Operation
            SourceRelativeUrl = $record.SourceRelativeUrl
            SourceFileName = $record.SourceFileName
            SourceFileExtension = $record.SourceFileExtension
            ApplicationDisplayName = $record.ApplicationDisplayName
            BrowserName = $record.BrowserName
            ManagedDevice = $record.IsManagedDevice
            ItemType = $record.ItemType
            SessionId = $record.AppAccessContext.AADSessionId
            Platform = $record.Platform
            UserAgent = $record.UserAgent
            ObjectId = $record.ObjectId
        }
    })

    if ($ExportCsv) {
        Export-BECResult -InputObject $file_operations -OutputPath $OutputPath -FileName "FileOperations.csv" -Description "file operation(s)"
    }

    return $file_operations
}
