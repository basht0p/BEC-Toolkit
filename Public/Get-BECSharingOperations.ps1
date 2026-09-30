function Get-BECSharingOperations {
    [CmdletBinding()]
    param (
        [string]$AuditLogSearchName,
        [string]$AuditLogSearchId,
        [switch]$ExportCsv,
        [string]$OutputPath = (Join-Path $pwd "BEC_Export")
    )

    $valid_sharing_operations = @(
        "SharingSet",
        "SharingLinkUpdated",
        "SharingLinkCreated",
        "SharingInheritanceBroken",
        "SharingInvitationCreated",
        "AnonymousLinkCreated",
        "AnonymousLinkUpdated",
        "AnonymousLinkUsed",
        "CompanyLinkCreated",
        "SecureLinkUpdated",
        "SecureLinkCreated",
        "PermissionLevelAdded",
        "AddedToSharingLink",
        "AddedToSecureLink"
    )

    $audit_log_records = Get-BECAuditRecord -AuditLogSearchName $AuditLogSearchName -AuditLogSearchId $AuditLogSearchId -Operation $valid_sharing_operations

    $sharing_operations = @(foreach ($audit_log_record in $audit_log_records) {
        $record = $audit_log_record.AuditData.AdditionalProperties

        [PSCustomObject]@{
            CreationTime = $record.CreationTime
            UserId = $record.UserId
            ClientIPAddress = $record.ClientIP
            Operation = $record.Operation
            # Who or what the item was shared with (a user, group, or link type such as Anonymous)
            TargetUserOrGroupName = $record.TargetUserOrGroupName
            TargetUserOrGroupType = $record.TargetUserOrGroupType
            EventData = $record.EventData
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
        Export-BECResult -InputObject $sharing_operations -OutputPath $OutputPath -FileName "SharingOperations.csv" -Description "sharing operation(s)"
    }

    return $sharing_operations
}
