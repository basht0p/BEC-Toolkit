$required_modules = @(
    "Microsoft.Graph.Applications",
    "Microsoft.Graph.Authentication",
    "Microsoft.Graph.Beta.Security"
)

foreach ($module in $required_modules){
    try {
        Import-Module $module -ErrorAction Stop
    }
    catch {
        Install-Module $module
        Import-Module $module -ErrorAction Stop
    }
}

function Resolve-BECAuditLogSearch {
    [CmdletBinding()]
    param (
        [string]$AuditLogSearchName="undefined",
        [string]$AuditLogSearchId
    )

    $required_scopes = "AuditLog.Read.All AuditLogsQuery.Read.All"

    if($null -eq (Get-MgContext)) {
        Connect-MgGraph -Scopes $required_scopes -ErrorAction Stop -NoWelcome
    }

    if ($AuditLogSearchId) {
        $audit_log_search = Get-MgBetaSecurityAuditLogQuery -AuditLogQueryId $AuditLogSearchId -ErrorAction Stop
    } elseif ($AuditLogSearchName -eq "undefined") {
        $succeeded_searches = @(Get-MgBetaSecurityAuditLogQuery | Where-Object Status -eq "succeeded")
        if ($succeeded_searches.Count -eq 0) {
            throw "No succeeded audit log searches found. Create an audit log search and wait for it to complete, or pass -AuditLogSearchName."
        }
        $audit_log_search = $succeeded_searches[0]
        Write-Host "Using audit log search '$($audit_log_search.DisplayName)' ($($audit_log_search.Id))" -ForegroundColor Gray
    } else {
        $matching_searches = @(Get-MgBetaSecurityAuditLogQuery | Where-Object DisplayName -eq $AuditLogSearchName)
        if ($matching_searches.Count -eq 0) {
            throw "No audit log search found with the name: $AuditLogSearchName"
        }
        if ($matching_searches.Count -gt 1) {
            $search_list = ($matching_searches | ForEach-Object { "$($_.Id) ($($_.Status))" }) -join ", "
            throw "Multiple audit log searches found with the name: $AuditLogSearchName. Use -AuditLogSearchId with one of: $search_list"
        }
        $audit_log_search = $matching_searches[0]
    }

    if ($audit_log_search.Status -ne "succeeded") {
        throw "Audit log search '$($audit_log_search.DisplayName)' ($($audit_log_search.Id)) has status '$($audit_log_search.Status)'. Wait for it to succeed before investigating."
    }

    $limit_exceeded = $audit_log_search.IsRecordCountLimitExceeded
    if ($null -eq $limit_exceeded -and $null -ne $audit_log_search.AdditionalProperties) {
        $limit_exceeded = $audit_log_search.AdditionalProperties["isRecordCountLimitExceeded"]
    }
    if ($limit_exceeded -eq $true) {
        Write-Warning "Audit log search '$($audit_log_search.DisplayName)' exceeded its record count limit. Results are incomplete; narrow the search (users, dates, operations) and run it again."
    }

    return $audit_log_search
}

function ConvertTo-BECPropertyTable {
    param (
        $Properties
    )

    $property_table = @{}

    foreach ($property in @($Properties)) {
        if ($null -ne $property -and $null -ne $property.Name) {
            $property_table[$property.Name] = $property.Value
        }
    }

    return $property_table
}

function Get-BECAccessedMailItems {
    [CmdletBinding()]
    param (
        [string]$AuditLogSearchName="undefined",
        [string]$AuditLogSearchId,
        [switch]$ExportCsv
    )

    $audit_log_search = Resolve-BECAuditLogSearch -AuditLogSearchName $AuditLogSearchName -AuditLogSearchId $AuditLogSearchId

    $audit_log_records = Get-MgBetaSecurityAuditLogQueryRecord -AuditLogQueryId $audit_log_search.Id -All | Where-Object Operation -eq "MailItemsAccessed"

    $mail_items_accessed = @()

    foreach ($record in $audit_log_records.AuditData.AdditionalProperties) {
        $operation_properties = ConvertTo-BECPropertyTable $record.OperationProperties

        foreach ($folder in $record.Folders) {
            # Sync events are logged per folder with no FolderItems; keep them as folder-level rows
            $folder_items = @($folder.FolderItems | Where-Object { $null -ne $_ })
            if ($folder_items.Count -eq 0) {
                $folder_items = @($null)
            }

            foreach ($folder_item in $folder_items) {
                $mail_items_accessed += [PSCustomObject]@{
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
    }

    if ($ExportCsv) {
        $export_folder_path = Join-Path $pwd "BEC_Export"
        
        if (!(Test-Path $export_folder_path)) {
            New-Item -Path $export_folder_path -ItemType Directory | Out-Null
        }

        $export_filename = "AccessedMail.csv"
        $export_full_path = Join-Path $export_folder_path $export_filename

        if ($mail_items_accessed.Count -gt 0) {
            $mail_items_accessed | Export-Csv -Path $export_full_path -NoTypeInformation
            Write-Host "Exporting $($mail_items_accessed.Count) accessed mail item(s) to file below:" -BackgroundColor Black -ForegroundColor Yellow
            Write-Host "$export_full_path" -BackgroundColor Black -ForegroundColor Yellow
        } else {
            Write-Host "No accessed mail found in audit. Skipping export." -ForegroundColor Gray
        }
    }

    return $mail_items_accessed
}

function Get-BECSentMailItems {
    [CmdletBinding()]
    param (
        [string]$AuditLogSearchName="undefined",
        [string]$AuditLogSearchId,
        [switch]$ExportCsv
    )

    $audit_log_search = Resolve-BECAuditLogSearch -AuditLogSearchName $AuditLogSearchName -AuditLogSearchId $AuditLogSearchId

    $audit_log_records = Get-MgBetaSecurityAuditLogQueryRecord -AuditLogQueryId $audit_log_search.Id -All | Where-Object Operation -eq "Send"

    $mail_items_sent = @()

    foreach ($record in $audit_log_records.AuditData.AdditionalProperties) {
        $mail_item = $record["Item"]

        $mail_items_sent += [PSCustomObject]@{
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
            ItemId = $mail_item.Id
            ItemInternetMessageId = $mail_item.InternetMessageId
            ItemSizeInBytes = $mail_item.SizeInBytes
            ItemSubject = $mail_item.Subject
        }
    }

    if ($ExportCsv) {
        $export_folder_path = Join-Path $pwd "BEC_Export"
        
        if (!(Test-Path $export_folder_path)) {
            New-Item -Path $export_folder_path -ItemType Directory | Out-Null
        }

        $export_filename = "SentMail.csv"
        $export_full_path = Join-Path $export_folder_path $export_filename

        if ($mail_items_sent.Count -gt 0) {
            $mail_items_sent | Export-Csv -Path $export_full_path -NoTypeInformation
            Write-Host "Exporting $($mail_items_sent.Count) sent mail item(s) to file below:" -BackgroundColor Black -ForegroundColor Yellow
            Write-Host "$export_full_path" -BackgroundColor Black -ForegroundColor Yellow
        } else {
            Write-Host "No sent mail found in audit. Skipping export." -ForegroundColor Gray
        }
    }

    return $mail_items_sent
}

function Get-BECFileOperations {
    [CmdletBinding()]
    param (
        [string]$AuditLogSearchName="undefined",
        [string]$AuditLogSearchId,
        [switch]$ExportCsv
    )

    $audit_log_search = Resolve-BECAuditLogSearch -AuditLogSearchName $AuditLogSearchName -AuditLogSearchId $AuditLogSearchId

    $audit_log_records = Get-MgBetaSecurityAuditLogQueryRecord -AuditLogQueryId $audit_log_search.Id -All | Where-Object Operation -like "File*"

    $file_operations = @()

    foreach ($record in $audit_log_records.AuditData.AdditionalProperties) {

        $file_operations += [PSCustomObject]@{
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
    }

    if ($ExportCsv) {
        $export_folder_path = Join-Path $pwd "BEC_Export"
        
        if (!(Test-Path $export_folder_path)) {
            New-Item -Path $export_folder_path -ItemType Directory | Out-Null
        }

        $export_filename = "FileOperations.csv"
        $export_full_path = Join-Path $export_folder_path $export_filename

        if ($file_operations.Count -gt 0) {
            $file_operations | Export-Csv -Path $export_full_path -NoTypeInformation
            Write-Host "Exporting $($file_operations.Count) file operation(s) to file below:" -BackgroundColor Black -ForegroundColor Yellow
            Write-Host "$export_full_path" -BackgroundColor Black -ForegroundColor Yellow
        } else {
            Write-Host "No file operations found in audit. Skipping export." -ForegroundColor Gray
        }
    }

    return $file_operations
}

function Get-BECSharingOperations {
    [CmdletBinding()]
    param (
        [string]$AuditLogSearchName="undefined",
        [string]$AuditLogSearchId,
        [switch]$ExportCsv
    )

    $audit_log_search = Resolve-BECAuditLogSearch -AuditLogSearchName $AuditLogSearchName -AuditLogSearchId $AuditLogSearchId

    $valid_sharing_operations = @(
        "SharingSet",
        "SharingLinkUpdated",
        "SharingLinkCreated",
        "SharingInheritanceBroken",
        "SecureLinkUpdated",
        "SecureLinkCreated",
        "PermissionLevelAdded",
        "AddedToSharingLink",
        "AddedToSecureLink"
    )

    $audit_log_records = Get-MgBetaSecurityAuditLogQueryRecord -AuditLogQueryId $audit_log_search.Id -All | Where-Object Operation -in $valid_sharing_operations

    $sharing_operations = @()

    foreach ($record in $audit_log_records.AuditData.AdditionalProperties) {

        $sharing_operations += [PSCustomObject]@{
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
    }

    if ($ExportCsv) {
        $export_folder_path = Join-Path $pwd "BEC_Export"
        
        if (!(Test-Path $export_folder_path)) {
            New-Item -Path $export_folder_path -ItemType Directory | Out-Null
        }

        $export_filename = "SharingOperations.csv"
        $export_full_path = Join-Path $export_folder_path $export_filename

        if ($sharing_operations.Count -gt 0) {
            $sharing_operations | Export-Csv -Path $export_full_path -NoTypeInformation
            Write-Host "Exporting $($sharing_operations.Count) sharing operation(s) to file below:" -BackgroundColor Black -ForegroundColor Yellow
            Write-Host "$export_full_path" -BackgroundColor Black -ForegroundColor Yellow
        } else {
            Write-Host "No sharing operations found in audit. Skipping export." -ForegroundColor Gray
        }
    }

    return $sharing_operations
}

function Get-BECAuthentications {
    [CmdletBinding()]
    param (
        [string]$AuditLogSearchName="undefined",
        [string]$AuditLogSearchId,
        [switch]$ExportCsv
    )

    $audit_log_search = Resolve-BECAuditLogSearch -AuditLogSearchName $AuditLogSearchName -AuditLogSearchId $AuditLogSearchId

    $valid_authentication_operations = @(
        "UserLoggedIn",
        "UserLoginFailed"
    )

    $audit_log_records = Get-MgBetaSecurityAuditLogQueryRecord -AuditLogQueryId $audit_log_search.Id -All | Where-Object Operation -in $valid_authentication_operations

    $authentications = @()

    foreach ($record in $audit_log_records.AuditData.AdditionalProperties) {
        $extended_properties = ConvertTo-BECPropertyTable $record.ExtendedProperties
        $device_properties = ConvertTo-BECPropertyTable $record.DeviceProperties

        $authentications += [PSCustomObject]@{
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
    }

    if ($ExportCsv) {
        $export_folder_path = Join-Path $pwd "BEC_Export"
        
        if (!(Test-Path $export_folder_path)) {
            New-Item -Path $export_folder_path -ItemType Directory | Out-Null
        }

        $export_filename = "Authentications.csv"
        $export_full_path = Join-Path $export_folder_path $export_filename

        if ($authentications.Count -gt 0) {
            $authentications | Export-Csv -Path $export_full_path -NoTypeInformation
            Write-Host "Exporting $($authentications.Count) authentication(s) to file below:" -BackgroundColor Black -ForegroundColor Yellow
            Write-Host "$export_full_path" -BackgroundColor Black -ForegroundColor Yellow
        } else {
            Write-Host "No authentications found in audit. Skipping export." -ForegroundColor Gray
        }
    }

    return $authentications
}

function Invoke-BECInvestigation {
    [CmdletBinding()]
    param (
        [string]$AuditLogSearchName="undefined",
        [string]$AuditLogSearchId
    )

    Write-Host "Running full BEC investigation. This may take a moment..."

    # Resolve once so every export comes from the same audit log search
    $AuditLogSearchId = (Resolve-BECAuditLogSearch -AuditLogSearchName $AuditLogSearchName -AuditLogSearchId $AuditLogSearchId).Id

    $accessed_mail = Get-BECAccessedMailItems -AuditLogSearchId $AuditLogSearchId -ExportCsv
    $sent_mail = Get-BECSentMailItems -AuditLogSearchId $AuditLogSearchId -ExportCsv
    $sharing_operations = Get-BECSharingOperations -AuditLogSearchId $AuditLogSearchId -ExportCsv
    $file_operations = Get-BECFileOperations -AuditLogSearchId $AuditLogSearchId -ExportCsv
    $authentications = Get-BECAuthentications -AuditLogSearchId $AuditLogSearchId -ExportCsv

    $investigation = [PSCustomObject]@{
        AccessedMail = $accessed_mail
        SentMail = $sent_mail
        SharingOperations = $sharing_operations
        FileOperations = $file_operations
        Authentications = $authentications
    }

    return $investigation
}

Export-ModuleMember -Function Get-BECAccessedMailItems, Get-BECSentMailItems, Get-BECFileOperations, Get-BECSharingOperations, Get-BECAuthentications, Invoke-BECInvestigation
