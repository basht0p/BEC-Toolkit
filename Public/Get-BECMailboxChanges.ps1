function Get-BECMailboxChanges {
    [CmdletBinding()]
    param (
        [string]$AuditLogSearchName,
        [string]$AuditLogSearchId,
        [switch]$ExportCsv,
        [string]$OutputPath = (Join-Path $pwd "BEC_Export")
    )

    $valid_mailbox_operations = @(
        "Set-Mailbox",
        "Add-MailboxPermission",
        "Remove-MailboxPermission",
        "Add-RecipientPermission",
        "Remove-RecipientPermission",
        "Add-MailboxFolderPermission",
        "Set-MailboxFolderPermission",
        "Set-CASMailbox",
        "Set-MailboxJunkEmailConfiguration",
        "New-TransportRule",
        "Set-TransportRule"
    )

    $audit_log_records = Get-BECAuditRecord -AuditLogSearchName $AuditLogSearchName -AuditLogSearchId $AuditLogSearchId -Operation $valid_mailbox_operations

    $mailbox_changes = @(foreach ($audit_log_record in $audit_log_records) {
        $record = $audit_log_record.AuditData.AdditionalProperties
        $parameters = ConvertTo-BECPropertyTable $record.Parameters
        $operation = $record.Operation

        $indicators = @()
        if ($operation -eq "Set-Mailbox" -and (Select-BECFirstValue $parameters["ForwardingSmtpAddress"] $parameters["ForwardingAddress"])) {
            $indicators += "Sets mailbox forwarding"
        }
        if ($operation -eq "Set-Mailbox" -and $parameters["GrantSendOnBehalfTo"]) {
            $indicators += "Grants Send on Behalf"
        }
        if ($operation -eq "Add-MailboxPermission" -and "$($parameters["AccessRights"])" -match "FullAccess") {
            $indicators += "Grants full mailbox access"
        }
        if ($operation -eq "Add-RecipientPermission") {
            $indicators += "Grants Send As"
        }
        if ($operation -like "*-MailboxFolderPermission") {
            $indicators += "Changes folder permissions"
        }
        if ($operation -like "*-TransportRule" -and (Format-BECPropertyList -PropertyTable $parameters -Name "RedirectMessageTo", "BlindCopyTo", "CopyTo", "AddToRecipients", "DeleteMessage")) {
            $indicators += "Transport rule forwards or deletes mail"
        }
        if ($operation -eq "Set-MailboxJunkEmailConfiguration" -and (Format-BECPropertyList -PropertyTable $parameters -Name "BlockedSendersAndDomains", "TrustedSendersAndDomains")) {
            $indicators += "Changes junk mail filtering"
        }
        if ($operation -eq "Set-CASMailbox" -and (@("ImapEnabled", "PopEnabled", "ActiveSyncEnabled", "EwsEnabled", "MAPIEnabled") | Where-Object { "$($parameters[$_])" -eq "True" })) {
            $indicators += "Enables a mail protocol"
        }

        [PSCustomObject]@{
            CreationTime = $record.CreationTime
            UserId = $record.UserId
            ClientIPAddress = Select-BECFirstValue $record.ClientIP $record.ClientIPAddress
            SessionId = Select-BECFirstValue $record.AppAccessContext.AADSessionId $record.SessionId
            Operation = $operation
            Target = Select-BECFirstValue $parameters["Identity"] $record.ObjectId
            Indicators = $indicators -join "; "
            ResultStatus = $record.ResultStatus
            Parameters = Format-BECPropertyList -PropertyTable $parameters
        }
    })

    if ($ExportCsv) {
        Export-BECResult -InputObject $mailbox_changes -OutputPath $OutputPath -FileName "MailboxChanges.csv" -Description "mailbox change(s)"
    }

    return $mailbox_changes
}
