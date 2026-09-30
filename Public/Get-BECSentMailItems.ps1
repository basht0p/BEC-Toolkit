function Get-BECSentMailItems {
    [CmdletBinding()]
    param (
        [string]$AuditLogSearchName,
        [string]$AuditLogSearchId,
        [switch]$ExportCsv,
        [string]$OutputPath = (Join-Path $pwd "BEC_Export")
    )

    $audit_log_records = Get-BECAuditRecord -AuditLogSearchName $AuditLogSearchName -AuditLogSearchId $AuditLogSearchId -Operation "Send", "SendAs", "SendOnBehalf"

    $mail_items_sent = @(foreach ($audit_log_record in $audit_log_records) {
        $record = $audit_log_record.AuditData.AdditionalProperties
        $mail_item = $record["Item"]

        [PSCustomObject]@{
            CreationTime = $record.CreationTime
            Operation = $record.Operation
            ResultStatus = $record.ResultStatus
            UserKey = $record.UserKey
            UserId = $record.UserId
            AppId = $record.AppId
            ClientIPAddress = $record.ClientIPAddress
            ClientInfoString = $record.ClientInfoString
            MailboxGuid = $record.MailboxGuid
            MailboxOwnerUPN = $record.MailboxOwnerUPN
            SessionId = $record.SessionId
            # SendAs and SendOnBehalf record the mailbox the message appeared to come from
            SentAsUser = if ($record.SendAsUserSmtp) { $record.SendAsUserSmtp } else { $record.SendOnBehalfOfUserSmtp }
            ItemId = $mail_item.Id
            ItemInternetMessageId = $mail_item.InternetMessageId
            ItemSizeInBytes = $mail_item.SizeInBytes
            ItemSubject = $mail_item.Subject
        }
    })

    if ($ExportCsv) {
        Export-BECResult -InputObject $mail_items_sent -OutputPath $OutputPath -FileName "SentMail.csv" -Description "sent mail item(s)"
    }

    return $mail_items_sent
}
