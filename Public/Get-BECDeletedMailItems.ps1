function Get-BECDeletedMailItems {
    [CmdletBinding()]
    param (
        [string]$AuditLogSearchName,
        [string]$AuditLogSearchId,
        [switch]$ExportCsv,
        [string]$OutputPath = (Join-Path $pwd "BEC_Export")
    )

    $valid_delete_operations = @(
        "MoveToDeletedItems",
        "SoftDelete",
        "HardDelete"
    )

    $audit_log_records = Get-BECAuditRecord -AuditLogSearchName $AuditLogSearchName -AuditLogSearchId $AuditLogSearchId -Operation $valid_delete_operations

    $deleted_mail_items = @(foreach ($audit_log_record in $audit_log_records) {
        $record = $audit_log_record.AuditData.AdditionalProperties

        $affected_items = @($record.AffectedItems | Where-Object { $null -ne $_ })
        if ($affected_items.Count -eq 0) {
            $affected_items = @($null)
        }

        foreach ($affected_item in $affected_items) {
            [PSCustomObject]@{
                CreationTime = $record.CreationTime
                Operation = $record.Operation
                ResultStatus = $record.ResultStatus
                UserId = $record.UserId
                ClientIPAddress = $record.ClientIPAddress
                ClientInfoString = $record.ClientInfoString
                SessionId = Select-BECFirstValue $record.AppAccessContext.AADSessionId $record.SessionId
                LogonType = $record.LogonType
                MailboxOwnerUPN = $record.MailboxOwnerUPN
                FolderPath = Select-BECFirstValue $affected_item.ParentFolder.Path $record.Folder.Path
                DestinationFolderPath = $record.DestFolder.Path
                ItemSubject = $affected_item.Subject
                ItemInternetMessageId = $affected_item.InternetMessageId
                ItemId = $affected_item.Id
            }
        }
    })

    if ($ExportCsv) {
        Export-BECResult -InputObject $deleted_mail_items -OutputPath $OutputPath -FileName "DeletedMail.csv" -Description "deleted mail item(s)"
    }

    return $deleted_mail_items
}
