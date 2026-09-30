function Get-BECAccessedMailItems {
    [CmdletBinding()]
    param (
        [string]$AuditLogSearchName,
        [string]$AuditLogSearchId,
        [switch]$ExportCsv,
        [string]$OutputPath = (Join-Path $pwd "BEC_Export")
    )

    $audit_log_records = Get-BECAuditRecord -AuditLogSearchName $AuditLogSearchName -AuditLogSearchId $AuditLogSearchId -Operation "MailItemsAccessed"

    $mail_items_accessed = @(foreach ($audit_log_record in $audit_log_records) {
        $record = $audit_log_record.AuditData.AdditionalProperties
        $operation_properties = ConvertTo-BECPropertyTable $record.OperationProperties

        foreach ($folder in $record.Folders) {
            # Sync events are logged per folder with no FolderItems; keep them as folder-level rows
            $folder_items = @($folder.FolderItems | Where-Object { $null -ne $_ })
            if ($folder_items.Count -eq 0) {
                $folder_items = @($null)
            }

            foreach ($folder_item in $folder_items) {
                [PSCustomObject]@{
                    CreationTime = $record.CreationTime
                    ResultStatus = $record.ResultStatus
                    UserKey = $record.UserKey
                    UserId = $record.UserId
                    AppId = $record.AppId
                    ClientIPAddress = $record.ClientIPAddress
                    ClientInfoString = $record.ClientInfoString
                    MailboxGuid = $record.MailboxGuid
                    MailboxOwnerUPN = $record.MailboxOwnerUPN
                    SessionId = $record.SessionId
                    MailAccessType = $operation_properties["MailAccessType"]
                    IsThrottled = $operation_properties["IsThrottled"]
                    FolderPath = $folder.Path
                    FolderId = $folder.Id
                    ItemSubject = $folder_item.Subject
                    ItemSizeInBytes = $folder_item.SizeInBytes
                    ItemInternetMessageId = $folder_item.InternetMessageId
                    ItemCreationTime = $folder_item.CreationTime
                    ItemId = $folder_item.Id
                }
            }
        }
    })

    if ($ExportCsv) {
        Export-BECResult -InputObject $mail_items_accessed -OutputPath $OutputPath -FileName "AccessedMail.csv" -Description "accessed mail item(s)"
    }

    return $mail_items_accessed
}
