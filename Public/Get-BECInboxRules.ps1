function Get-BECInboxRules {
    [CmdletBinding()]
    param (
        [string]$AuditLogSearchName,
        [string]$AuditLogSearchId,
        [switch]$ExportCsv,
        [string]$OutputPath = (Join-Path $pwd "BEC_Export")
    )

    # Rules made in Outlook on the web or PowerShell are logged as cmdlets; rules made in
    # desktop Outlook are logged as UpdateInboxRules
    $valid_rule_operations = @(
        "New-InboxRule",
        "Set-InboxRule",
        "Enable-InboxRule",
        "Disable-InboxRule",
        "Remove-InboxRule",
        "UpdateInboxRules"
    )

    $condition_parameters = @(
        "From", "FromAddressContainsWords", "SubjectContainsWords", "SubjectOrBodyContainsWords",
        "BodyContainsWords", "HeaderContainsWords", "SentTo", "RecipientAddressContainsWords",
        "MyNameInToOrCcBox", "HasAttachment", "FlaggedForAction", "WithImportance", "MessageTypeMatches"
    )
    $action_parameters = @(
        "ForwardTo", "ForwardAsAttachmentTo", "RedirectTo", "DeleteMessage", "SoftDeleteMessage",
        "MoveToFolder", "CopyToFolder", "MarkAsRead", "MarkImportance", "ApplyCategory",
        "StopProcessingRules", "SendTextMessageNotificationTo"
    )

    $audit_log_records = Get-BECAuditRecord -AuditLogSearchName $AuditLogSearchName -AuditLogSearchId $AuditLogSearchId -Operation $valid_rule_operations

    $inbox_rules = @(foreach ($audit_log_record in $audit_log_records) {
        $record = $audit_log_record.AuditData.AdditionalProperties

        if ($record.Operation -eq "UpdateInboxRules") {
            $properties = ConvertTo-BECPropertyTable $record.OperationProperties
            $rule_operation = $properties["RuleOperation"]
            $mailbox = Select-BECFirstValue $record.MailboxOwnerUPN $record.ObjectId
            $rule_name = $properties["RuleName"]
            $conditions = $properties["RuleCondition"]
            $actions = $properties["RuleActions"]
        } else {
            $properties = ConvertTo-BECPropertyTable $record.Parameters
            $rule_operation = $record.Operation
            $mailbox = Select-BECFirstValue $properties["Mailbox"] $record.ObjectId
            $rule_name = Select-BECFirstValue $properties["Name"] $properties["Identity"] $record.ObjectId
            $conditions = Format-BECPropertyList -PropertyTable $properties -Name $condition_parameters
            $actions = Format-BECPropertyList -PropertyTable $properties -Name $action_parameters
        }

        [PSCustomObject]@{
            CreationTime = $record.CreationTime
            UserId = $record.UserId
            ClientIPAddress = Select-BECFirstValue $record.ClientIP $record.ClientIPAddress
            SessionId = Select-BECFirstValue $record.AppAccessContext.AADSessionId $record.SessionId
            Operation = $record.Operation
            RuleOperation = $rule_operation
            Mailbox = $mailbox
            RuleName = $rule_name
            Conditions = $conditions
            Actions = $actions
            Indicators = Get-BECRuleIndicator -RuleName $rule_name -Actions $actions -Conditions $conditions
            ResultStatus = $record.ResultStatus
            ClientInfoString = $record.ClientInfoString
            AllParameters = Format-BECPropertyList -PropertyTable $properties
        }
    })

    if ($ExportCsv) {
        Export-BECResult -InputObject $inbox_rules -OutputPath $OutputPath -FileName "InboxRules.csv" -Description "inbox rule change(s)"
    }

    return $inbox_rules
}
