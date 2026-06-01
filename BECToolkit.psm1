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

function Get-BECAccessedMailItems {
    [CmdletBinding()]
    param (
        [string]$AuditLogSearchName="undefined",
        [switch]$ExportCsv
    )

    $required_scopes = "AuditLog.Read.All AuditLogsQuery.Read.All"

    if($null -eq (Get-MgContext)) {
        Connect-MgGraph -Scopes $required_scopes -ErrorAction Stop -NoWelcome
    }

    if ($AuditLogSearchName -eq "undefined") {
        $audit_log_search = (Get-MgBetaSecurityAuditLogQuery | Where-Object Status -eq "succeeded")[0]
    } else {
        $audit_log_search = Get-MgBetaSecurityAuditLogQuery | Where-Object DisplayName -eq $AuditLogSearchName
        if ($null -eq $audit_log_search) {
            throw "No audit log search found with the name: $AuditLogSearchName"
        }
    }

    $audit_log_records = Get-MgBetaSecurityAuditLogQueryRecord -AuditLogQueryId $audit_log_search.Id -All | Where-Object Operation -eq "MailItemsAccessed"

    $mail_items_accessed = @()

    foreach ($record in $audit_log_records.AuditData.AdditionalProperties) {
        foreach ($folder in $record.Folders) {
            foreach ($folder_item in $folder.FolderItems) {
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
            $mail_items_accessed | Export-Csv -Path $export_full_path
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
        [switch]$ExportCsv
    )

    $required_scopes = "AuditLog.Read.All AuditLogsQuery.Read.All"

    if($null -eq (Get-MgContext)) {
        Connect-MgGraph -Scopes $required_scopes -ErrorAction Stop -NoWelcome
    }

    if ($AuditLogSearchName -eq "undefined") {
        $audit_log_search = (Get-MgBetaSecurityAuditLogQuery | Where-Object Status -eq "succeeded")[0]
    } else {
        $audit_log_search = Get-MgBetaSecurityAuditLogQuery | Where-Object DisplayName -eq $AuditLogSearchName
        if ($null -eq $audit_log_search) {
            throw "No audit log search found with the name: $AuditLogSearchName"
        }
    }

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
            $mail_items_sent | Export-Csv -Path $export_full_path
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
        [switch]$ExportCsv
    )

    $required_scopes = "AuditLog.Read.All AuditLogsQuery.Read.All"

    if($null -eq (Get-MgContext)) {
        Connect-MgGraph -Scopes $required_scopes -ErrorAction Stop -NoWelcome
    }

    if ($AuditLogSearchName -eq "undefined") {
        $audit_log_search = (Get-MgBetaSecurityAuditLogQuery | Where-Object Status -eq "succeeded")[0]
    } else {
        $audit_log_search = Get-MgBetaSecurityAuditLogQuery | Where-Object DisplayName -eq $AuditLogSearchName
        if ($null -eq $audit_log_search) {
            throw "No audit log search found with the name: $AuditLogSearchName"
        }
    }

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
            $file_operations | Export-Csv -Path $export_full_path
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
        [switch]$ExportCsv
    )

    $required_scopes = "AuditLog.Read.All AuditLogsQuery.Read.All"

    if($null -eq (Get-MgContext)) {
        Connect-MgGraph -Scopes $required_scopes -ErrorAction Stop -NoWelcome
    }

    if ($AuditLogSearchName -eq "undefined") {
        $audit_log_search = (Get-MgBetaSecurityAuditLogQuery | Where-Object Status -eq "succeeded")[0]
    } else {
        $audit_log_search = Get-MgBetaSecurityAuditLogQuery | Where-Object DisplayName -eq $AuditLogSearchName
        if ($null -eq $audit_log_search) {
            throw "No audit log search found with the name: $AuditLogSearchName"
        }
    }

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
            $sharing_operations | Export-Csv -Path $export_full_path
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
        [switch]$ExportCsv
    )

    $required_scopes = "AuditLog.Read.All AuditLogsQuery.Read.All"

    if($null -eq (Get-MgContext)) {
        Connect-MgGraph -Scopes $required_scopes -ErrorAction Stop -NoWelcome
    }

    if ($AuditLogSearchName -eq "undefined") {
        $audit_log_search = (Get-MgBetaSecurityAuditLogQuery | Where-Object Status -eq "succeeded")[0]
    } else {
        $audit_log_search = Get-MgBetaSecurityAuditLogQuery | Where-Object DisplayName -eq $AuditLogSearchName
        if ($null -eq $audit_log_search) {
            throw "No audit log search found with the name: $AuditLogSearchName"
        }
    }

    $valid_authentication_operations = @(
        "UserLoggedIn",
        "UserLoginFailed"
    )

    $audit_log_records = Get-MgBetaSecurityAuditLogQueryRecord -AuditLogQueryId $audit_log_search.Id -All | Where-Object Operation -in $valid_authentication_operations

    $authentications = @()

    foreach ($record in $audit_log_records.AuditData.AdditionalProperties) {

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
            UserAgent = $record.ExtendedProperties.Value[$record.ExtendedProperties.Name.IndexOf("UserAgent")]
            OS = $record.DeviceProperties.Value[$record.DeviceProperties.Name.IndexOf("OS")]
            BrowserType = $record.DeviceProperties.Value[$record.DeviceProperties.Name.IndexOf("BrowserType")]
            IsCompliant = $record.DeviceProperties.Value[$record.DeviceProperties.Name.IndexOf("IsCompliant")]
            IsCompliantAndManaged = $record.DeviceProperties.Value[$record.DeviceProperties.Name.IndexOf("IsCompliantAndManaged")]
            SessionId = $record.DeviceProperties.Value[$record.DeviceProperties.Name.IndexOf("SessionId")]
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
            $authentications | Export-Csv -Path $export_full_path
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
        [string]$AuditLogSearchName="undefined"
    )

    Write-Host "Running full BEC investigation. This may take a moment..."

    $accessed_mail = Get-BECAccessedMailItems -AuditLogSearchName $AuditLogSearchName -ExportCsv
    $sent_mail = Get-BECSentMailItems -AuditLogSearchName $AuditLogSearchName -ExportCsv
    $sharing_operations = Get-BECSharingOperations -AuditLogSearchName $AuditLogSearchName -ExportCsv
    $file_operations = Get-BECFileOperations -AuditLogSearchName $AuditLogSearchName -ExportCsv
    $authentications = Get-BECAuthentications -AuditLogSearchName $AuditLogSearchName -ExportCsv

    $investigation = [PSCustomObject]@{
        AccessedMail = $accessed_mail
        SentMail = $sent_mail
        SharingOperations = $sharing_operations
        FileOperations = $file_operations
        Authentications = $authentications
    }

    return $investigation
}