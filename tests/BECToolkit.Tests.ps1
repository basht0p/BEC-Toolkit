#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# The Graph stand-ins only declare parameters for mocks to bind, and test data is shared with mocks
# through global variables because mock bodies run in the module's scope
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Parameter-only stand-ins for mocked Graph cmdlets')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Test data shared with mocks')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test helpers only build objects in memory')]
param ()

BeforeAll {
    # Stand-ins for the Microsoft Graph cmdlets so the module loads without the Graph SDK.
    # Each is mocked below; the stand-ins only provide the parameters the module passes.
    function global:Get-MgContext { [CmdletBinding()] param () }
    function global:Connect-MgGraph { [CmdletBinding()] param ($Scopes, $TenantId, [switch]$NoWelcome) }
    function global:Invoke-MgGraphRequest { [CmdletBinding()] param ($Method, $Uri) }
    function global:Get-MgBetaSecurityAuditLogQuery { [CmdletBinding()] param ($AuditLogQueryId) }
    function global:Get-MgBetaSecurityAuditLogQueryRecord { [CmdletBinding()] param ($AuditLogQueryId, [switch]$All) }
    function global:New-MgBetaSecurityAuditLogQuery { [CmdletBinding()] param ($BodyParameter) }

    $module_root = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $module_root "BECToolkit.psm1") -Force

    # Audit data arrives from the Graph SDK as nested dictionaries and arrays, not PSCustomObjects
    function ConvertTo-TestValue {
        param ($Value)

        if ($Value -is [System.Management.Automation.PSCustomObject]) {
            $table = @{}
            foreach ($property in $Value.PSObject.Properties) {
                $table[$property.Name] = ConvertTo-TestValue $property.Value
            }
            return $table
        }
        if ($Value -is [array]) {
            return , @($Value | ForEach-Object { ConvertTo-TestValue $_ })
        }
        return $Value
    }

    function New-TestRecord {
        param ([string]$Json)

        $data = ConvertTo-TestValue ($Json | ConvertFrom-Json)

        [PSCustomObject]@{
            Id = [guid]::NewGuid().ToString()
            CreatedDateTime = $data.CreationTime
            Operation = $data.Operation
            AuditLogRecordType = "exchangeItem"
            Service = "Exchange"
            UserPrincipalName = $data.UserId
            UserId = $data.UserId
            UserType = "regular"
            ClientIp = $data.ClientIP
            ObjectId = $data.ObjectId
            AuditData = [PSCustomObject]@{ AdditionalProperties = $data }
        }
    }

    function New-TestSearch {
        param (
            [string]$Id,
            [string]$Name,
            [string]$Status = "succeeded",
            [bool]$LimitExceeded = $false,
            [string[]]$Users = @()
        )

        [PSCustomObject]@{
            Id = $Id
            DisplayName = $Name
            Status = $Status
            UserPrincipalNameFilters = $Users
            FilterStartDateTime = (Get-Date).AddDays(-3)
            FilterEndDateTime = (Get-Date)
            AdditionalProperties = @{ isRecordCountLimitExceeded = $LimitExceeded }
        }
    }
}

AfterAll {
    Remove-Module BECToolkit -ErrorAction SilentlyContinue
    foreach ($name in "Get-MgContext", "Connect-MgGraph", "Invoke-MgGraphRequest", "Get-MgBetaSecurityAuditLogQuery", "Get-MgBetaSecurityAuditLogQueryRecord", "New-MgBetaSecurityAuditLogQuery") {
        Remove-Item "Function:\$name" -ErrorAction SilentlyContinue
    }
    Remove-Variable BECTestSearches, BECTestRecords, BECTestContext -Scope Global -ErrorAction SilentlyContinue
}

Describe "BECToolkit" {
    BeforeAll {
        Mock -ModuleName BECToolkit Write-Host { }
        Mock -ModuleName BECToolkit Get-MgContext { $global:BECTestContext }
        Mock -ModuleName BECToolkit Connect-MgGraph { }
        Mock -ModuleName BECToolkit Get-MgBetaSecurityAuditLogQuery {
            if ($AuditLogQueryId) {
                $global:BECTestSearches | Where-Object Id -eq $AuditLogQueryId
            } else {
                $global:BECTestSearches
            }
        }
        Mock -ModuleName BECToolkit Get-MgBetaSecurityAuditLogQueryRecord { $global:BECTestRecords }
    }

    BeforeEach {
        $global:BECTestContext = [PSCustomObject]@{
            AuthType = "Delegated"
            Scopes = @("AuditLog.Read.All", "AuditLogsQuery.Read.All")
            TenantId = "tenant-1"
        }
        $global:BECTestSearches = @(New-TestSearch -Id "s1" -Name "Case" -Users "a@contoso.com")
        $global:BECTestRecords = @()

        InModuleScope BECToolkit {
            $script:BECRecordCache = @{ SearchId = $null; Records = @() }
            $script:BECWarnedSearchIds.Clear()
        }
    }

    Context "Module" {
        It "exports exactly the functions in Public" {
            $module_root = Split-Path $PSScriptRoot -Parent
            $public = @(Get-ChildItem (Join-Path $module_root "Public") -Filter "*.ps1" | ForEach-Object { $_.BaseName } | Sort-Object)
            $manifest = Import-PowerShellDataFile (Join-Path $module_root "BECToolkit.psd1")

            @($manifest.FunctionsToExport | Sort-Object) | Should -Be $public
            @((Get-Command -Module BECToolkit).Name | Sort-Object) | Should -Be $public
        }
    }

    Context "Connecting to Microsoft Graph" {
        It "connects when there is no session" {
            $global:BECTestContext = $null

            Get-BECSentMailItems | Out-Null

            Should -Invoke -ModuleName BECToolkit Connect-MgGraph -Times 1 -Exactly
        }

        It "reconnects to the same tenant when a scope is missing" {
            $global:BECTestContext.Scopes = @("AuditLogsQuery.Read.All")

            Get-BECSentMailItems | Out-Null

            Should -Invoke -ModuleName BECToolkit Connect-MgGraph -Times 1 -Exactly -ParameterFilter {
                $TenantId -eq "tenant-1" -and "AuditLog.Read.All" -in $Scopes -and "AuditLogsQuery.Read.All" -in $Scopes
            }
        }

        It "leaves an app-only session alone" {
            $global:BECTestContext = [PSCustomObject]@{ AuthType = "AppOnly"; Scopes = @(); TenantId = "tenant-1" }

            Get-BECSentMailItems | Out-Null

            Should -Invoke -ModuleName BECToolkit Connect-MgGraph -Times 0 -Exactly
        }
    }

    Context "Selecting the audit log search" {
        It "fails clearly when no search has succeeded" {
            $global:BECTestSearches = @(New-TestSearch -Id "s1" -Name "Case" -Status "running")

            { Get-BECSentMailItems } | Should -Throw -ExpectedMessage "No succeeded audit log searches found*"
        }

        It "rejects a search that hasn't finished" {
            $global:BECTestSearches = @(New-TestSearch -Id "s1" -Name "Case" -Status "running")

            { Get-BECSentMailItems -AuditLogSearchName "Case" } | Should -Throw -ExpectedMessage "*has status 'running'*"
        }

        It "rejects a name that matches more than one search" {
            $global:BECTestSearches = @((New-TestSearch -Id "s1" -Name "Case"), (New-TestSearch -Id "s2" -Name "Case"))

            { Get-BECSentMailItems -AuditLogSearchName "Case" } | Should -Throw -ExpectedMessage "Multiple audit log searches*s1*s2*"
        }

        It "fails when no search has the name" {
            { Get-BECSentMailItems -AuditLogSearchName "Nope" } | Should -Throw -ExpectedMessage "No audit log search found with the name: Nope"
        }

        It "selects a search by ID" {
            $global:BECTestSearches = @((New-TestSearch -Id "s1" -Name "One"), (New-TestSearch -Id "s2" -Name "Two"))

            Get-BECSentMailItems -AuditLogSearchId "s2" | Out-Null

            Should -Invoke -ModuleName BECToolkit Get-MgBetaSecurityAuditLogQueryRecord -Times 1 -Exactly -ParameterFilter { $AuditLogQueryId -eq "s2" }
        }

        It "warns once per search when the record count limit was exceeded" {
            Mock -ModuleName BECToolkit Write-Warning { }
            $global:BECTestSearches = @(New-TestSearch -Id "s1" -Name "Case" -LimitExceeded $true)

            Get-BECSentMailItems | Out-Null
            Get-BECInboxRules | Out-Null

            Should -Invoke -ModuleName BECToolkit Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -like "*record count limit*" }
        }
    }

    Context "Downloading records" {
        It "downloads a search's records once for several functions" {
            Get-BECSentMailItems | Out-Null
            Get-BECAccessedMailItems | Out-Null
            Get-BECInboxRules | Out-Null

            Should -Invoke -ModuleName BECToolkit Get-MgBetaSecurityAuditLogQueryRecord -Times 1 -Exactly
        }

        It "downloads again for a different search" {
            $global:BECTestSearches = @((New-TestSearch -Id "s1" -Name "One"), (New-TestSearch -Id "s2" -Name "Two"))

            Get-BECSentMailItems -AuditLogSearchId "s1" | Out-Null
            Get-BECSentMailItems -AuditLogSearchId "s2" | Out-Null

            Should -Invoke -ModuleName BECToolkit Get-MgBetaSecurityAuditLogQueryRecord -Times 2 -Exactly
        }
    }

    Context "Get-BECAuthentications" {
        It "leaves missing properties empty instead of taking another property's value" {
            $global:BECTestRecords = @(New-TestRecord '{"Operation":"UserLoggedIn","CreationTime":"2026-09-01T10:00:00","UserId":"a@contoso.com","ClientIP":"1.2.3.4",
                "ExtendedProperties":[{"Name":"RequestType","Value":"OAuth2:Authorize"}],
                "DeviceProperties":[{"Name":"OS","Value":"Windows10"},{"Name":"BrowserType","Value":"Edge"},{"Name":"SessionId","Value":"sess-1"}]}')

            $result = Get-BECAuthentications

            $result.UserAgent | Should -BeNullOrEmpty
            $result.IsCompliant | Should -BeNullOrEmpty
            $result.SessionId | Should -Be "sess-1"
        }

        It "reads a property list with a single entry" {
            $global:BECTestRecords = @(New-TestRecord '{"Operation":"UserLoggedIn","CreationTime":"2026-09-01T10:00:00","UserId":"a@contoso.com",
                "ExtendedProperties":[{"Name":"UserAgent","Value":"Mozilla/5.0"}],"DeviceProperties":[{"Name":"OS","Value":"MacOs"}]}')

            $result = Get-BECAuthentications

            $result.UserAgent | Should -Be "Mozilla/5.0"
            $result.OS | Should -Be "MacOs"
            $result.BrowserType | Should -BeNullOrEmpty
        }
    }

    Context "Get-BECAccessedMailItems" {
        It "keeps Sync events as folder-level rows" {
            $global:BECTestRecords = @(
                New-TestRecord '{"Operation":"MailItemsAccessed","CreationTime":"2026-09-01T12:00:00","UserId":"a@contoso.com",
                    "OperationProperties":[{"Name":"MailAccessType","Value":"Sync"},{"Name":"IsThrottled","Value":"False"}],
                    "Folders":[{"Id":"f1","Path":"\\Inbox"},{"Id":"f2","Path":"\\Sent Items"}]}'
                New-TestRecord '{"Operation":"MailItemsAccessed","CreationTime":"2026-09-01T12:05:00","UserId":"a@contoso.com",
                    "OperationProperties":[{"Name":"MailAccessType","Value":"Bind"}],
                    "Folders":[{"Id":"f1","Path":"\\Inbox","FolderItems":[{"Id":"i1","Subject":"Invoice"},{"Id":"i2","Subject":"Wire details"}]}]}'
            )

            $result = Get-BECAccessedMailItems

            $result.Count | Should -Be 4
            @($result | Where-Object MailAccessType -eq "Sync").FolderPath | Should -Be @("\Inbox", "\Sent Items")
            $result | Where-Object MailAccessType -eq "Sync" | ForEach-Object { $_.ItemSubject | Should -BeNullOrEmpty }
            @($result | Where-Object MailAccessType -eq "Bind").ItemSubject | Should -Be @("Invoice", "Wire details")
        }
    }

    Context "Get-BECSentMailItems" {
        It "includes SendAs with the mailbox the message was sent as" {
            $global:BECTestRecords = @(
                New-TestRecord '{"Operation":"Send","CreationTime":"2026-09-01T12:00:00","UserId":"a@contoso.com","Item":{"Id":"m1","Subject":"Hello"}}'
                New-TestRecord '{"Operation":"SendAs","CreationTime":"2026-09-01T12:01:00","UserId":"a@contoso.com","SendAsUserSmtp":"ceo@contoso.com","Item":{"Id":"m2","Subject":"Wire today"}}'
            )

            $result = Get-BECSentMailItems

            $result.Count | Should -Be 2
            ($result | Where-Object Operation -eq "SendAs").SentAsUser | Should -Be "ceo@contoso.com"
            ($result | Where-Object Operation -eq "SendAs").ItemSubject | Should -Be "Wire today"
        }
    }

    Context "Get-BECInboxRules" {
        It "flags a hidden rule created with New-InboxRule" {
            $global:BECTestRecords = @(New-TestRecord '{"Operation":"New-InboxRule","CreationTime":"2026-09-01T12:01:00","UserId":"a@contoso.com","ClientIP":"5.6.7.8:51234",
                "Parameters":[{"Name":"Name","Value":"."},{"Name":"MoveToFolder","Value":"RSS Feeds"},{"Name":"SubjectOrBodyContainsWords","Value":"invoice;payment"},
                              {"Name":"MarkAsRead","Value":"True"},{"Name":"DeleteMessage","Value":"False"}]}')

            $result = Get-BECInboxRules

            $result.RuleName | Should -Be "."
            $result.Actions | Should -Be "MoveToFolder=RSS Feeds; MarkAsRead=True"
            $result.Conditions | Should -Be "SubjectOrBodyContainsWords=invoice;payment"
            $result.Indicators | Should -Match "rarely checked folder"
            $result.Indicators | Should -Match "Marks mail as read"
            $result.Indicators | Should -Match "payment or security keywords"
            $result.Indicators | Should -Match "Suspicious rule name"
            $result.Indicators | Should -Not -Match "Deletes mail"
        }

        It "reads rules created in desktop Outlook" {
            $global:BECTestRecords = @(New-TestRecord '{"Operation":"UpdateInboxRules","CreationTime":"2026-09-01T12:02:00","UserId":"a@contoso.com","MailboxOwnerUPN":"a@contoso.com",
                "OperationProperties":[{"Name":"RuleName","Value":"Updates"},{"Name":"RuleActions","Value":"Forward to evil@example.com"},
                                       {"Name":"RuleCondition","Value":"From contains bank"},{"Name":"RuleOperation","Value":"AddMailboxRule"}]}')

            $result = Get-BECInboxRules

            $result.RuleOperation | Should -Be "AddMailboxRule"
            $result.RuleName | Should -Be "Updates"
            $result.Indicators | Should -Match "Forwards or redirects mail"
        }
    }

    Context "Get-BECMailboxChanges" {
        It "flags mailbox forwarding and full access grants" {
            $global:BECTestRecords = @(
                New-TestRecord '{"Operation":"Set-Mailbox","CreationTime":"2026-09-01T12:03:00","UserId":"a@contoso.com",
                    "Parameters":[{"Name":"Identity","Value":"a@contoso.com"},{"Name":"ForwardingSmtpAddress","Value":"smtp:evil@example.com"}]}'
                New-TestRecord '{"Operation":"Add-MailboxPermission","CreationTime":"2026-09-01T12:04:00","UserId":"admin@contoso.com",
                    "Parameters":[{"Name":"Identity","Value":"ceo@contoso.com"},{"Name":"AccessRights","Value":"FullAccess"}]}'
                New-TestRecord '{"Operation":"Set-Mailbox","CreationTime":"2026-09-01T12:05:00","UserId":"admin@contoso.com",
                    "Parameters":[{"Name":"Identity","Value":"b@contoso.com"},{"Name":"CustomAttribute1","Value":"x"}]}'
            )

            $result = Get-BECMailboxChanges

            $result.Count | Should -Be 3
            $result[0].Indicators | Should -Be "Sets mailbox forwarding"
            $result[0].Target | Should -Be "a@contoso.com"
            $result[1].Indicators | Should -Be "Grants full mailbox access"
            $result[2].Indicators | Should -BeNullOrEmpty
        }
    }

    Context "Get-BECDeletedMailItems" {
        It "returns one row per deleted message" {
            $global:BECTestRecords = @(New-TestRecord '{"Operation":"SoftDelete","CreationTime":"2026-09-01T12:05:00","UserId":"a@contoso.com","Folder":{"Path":"\\Inbox"},
                "AffectedItems":[{"Id":"d1","Subject":"RE: Invoice"},{"Id":"d2","Subject":"Is this you?"}]}')

            $result = Get-BECDeletedMailItems

            $result.ItemSubject | Should -Be @("RE: Invoice", "Is this you?")
            $result.FolderPath | Should -Be @("\Inbox", "\Inbox")
        }
    }

    Context "Get-BECIdentityChanges" {
        It "matches Entra operations with a trailing period and skips unrelated user updates" {
            $global:BECTestRecords = @(
                New-TestRecord '{"Operation":"Consent to application.","CreationTime":"2026-09-01T12:08:00","UserId":"a@contoso.com","ObjectId":"sp-1",
                    "Target":[{"ID":"eM Client","Type":1},{"ID":"eM Client","Type":1}],
                    "ModifiedProperties":[{"Name":"ConsentAction.Permissions","NewValue":"Mail.ReadWrite","OldValue":""}]}'
                New-TestRecord '{"Operation":"Update user.","CreationTime":"2026-09-01T12:09:00","UserId":"a@contoso.com",
                    "ModifiedProperties":[{"Name":"StrongAuthenticationPhoneAppDetail","NewValue":"[new]","OldValue":"[]"}]}'
                New-TestRecord '{"Operation":"Update user.","CreationTime":"2026-09-01T12:10:00","UserId":"sync@contoso.com",
                    "ModifiedProperties":[{"Name":"LastDirSyncTime","NewValue":"x","OldValue":"y"}]}'
                New-TestRecord '{"Operation":"Send","CreationTime":"2026-09-01T12:11:00","UserId":"a@contoso.com"}'
            )

            $result = Get-BECIdentityChanges

            $result.Count | Should -Be 2
            $result[0].Category | Should -Be "App consent or permission grant"
            $result[0].TargetDetails | Should -Be "eM Client"
            $result[0].ModifiedProperties | Should -Be "ConsentAction.Permissions:  -> Mail.ReadWrite"
            $result[1].Category | Should -Be "Authentication method changed"
        }
    }

    Context "Get-BECSignInLogs" {
        BeforeAll {
            Mock -ModuleName BECToolkit Invoke-MgGraphRequest {
                if ($Uri -like "*skiptoken*") {
                    return @{ value = @(@{ createdDateTime = "2026-09-01T09:00:00Z"; userPrincipalName = "a@contoso.com"; ipAddress = "1.2.3.4"; isInteractive = $true }) }
                }
                return @{
                    value = @(@{
                        createdDateTime = "2026-09-01T10:00:00Z"; userPrincipalName = "a@contoso.com"; ipAddress = "5.6.7.8"; sessionId = "sess-1"
                        signInEventTypes = @("nonInteractiveUser"); location = @{ city = "Lagos"; countryOrRegion = "NG" }
                        status = @{ errorCode = 0 }; riskEventTypes_v2 = @("unfamiliarFeatures", "anonymizedIPAddress")
                    })
                    "@odata.nextLink" = "https://graph.microsoft.com/beta/auditLogs/signIns?`$skiptoken=abc"
                }
            }
        }

        It "follows paging, sorts by time and flattens the sign-in" {
            $result = Get-BECSignInLogs -AuditLogSearchId "s1"

            $result.Count | Should -Be 2
            $result[0].ClientIPAddress | Should -Be "1.2.3.4"
            $result[0].SignInEventType | Should -Be "interactiveUser"
            $result[1].City | Should -Be "Lagos"
            $result[1].Country | Should -Be "NG"
            $result[1].SessionId | Should -Be "sess-1"
            $result[1].RiskEventTypes | Should -Be "unfamiliarFeatures,anonymizedIPAddress"
            Should -Invoke -ModuleName BECToolkit Invoke-MgGraphRequest -Times 2 -Exactly
        }

        It "includes non-interactive sign-ins unless -InteractiveOnly is set" {
            Get-BECSignInLogs -UserPrincipalName "a@contoso.com" -StartDateTime (Get-Date).AddDays(-1) -EndDateTime (Get-Date) | Out-Null
            Should -Invoke -ModuleName BECToolkit Invoke-MgGraphRequest -Times 1 -ParameterFilter { [uri]::UnescapeDataString($Uri) -like "*nonInteractiveUser*" }

            Get-BECSignInLogs -UserPrincipalName "b@contoso.com" -StartDateTime (Get-Date).AddDays(-1) -EndDateTime (Get-Date) -InteractiveOnly | Out-Null
            Should -Invoke -ModuleName BECToolkit Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter {
                $unescaped = [uri]::UnescapeDataString($Uri)
                $unescaped -like "*b@contoso.com*" -and $unescaped -notlike "*signInEventTypes*"
            }
        }

        It "escapes apostrophes in user names" {
            Get-BECSignInLogs -UserPrincipalName "o'brien@contoso.com" -StartDateTime (Get-Date).AddDays(-1) -EndDateTime (Get-Date) | Out-Null

            Should -Invoke -ModuleName BECToolkit Invoke-MgGraphRequest -ParameterFilter { [uri]::UnescapeDataString($Uri) -like "*userPrincipalName eq 'o''brien@contoso.com'*" }
        }

        It "fails when there are no users to look up" {
            $global:BECTestSearches = @(New-TestSearch -Id "s1" -Name "Case")

            { Get-BECSignInLogs -AuditLogSearchId "s1" } | Should -Throw -ExpectedMessage "No users to look up*"
        }
    }

    Context "New-BECAuditLogSearch" {
        BeforeAll {
            Mock -ModuleName BECToolkit Start-Sleep { }
            Mock -ModuleName BECToolkit New-MgBetaSecurityAuditLogQuery {
                $global:BECCreatedBody = $BodyParameter
                [PSCustomObject]@{ Id = "new-1"; DisplayName = $BodyParameter.displayName; Status = "notStarted" }
            }
        }

        It "requires a user or IP address" {
            { New-BECAuditLogSearch } | Should -Throw -ExpectedMessage "Specify -UserPrincipalName or -IPAddress*"
        }

        It "creates the search with the given filters" {
            $start = [datetime]::new(2026, 9, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
            $end = [datetime]::new(2026, 9, 10, 0, 0, 0, [System.DateTimeKind]::Utc)

            $result = New-BECAuditLogSearch -UserPrincipalName "a@contoso.com" -StartDateTime $start -EndDateTime $end -Operation "New-InboxRule" -DisplayName "Case-1"

            $result.Id | Should -Be "new-1"
            $global:BECCreatedBody.displayName | Should -Be "Case-1"
            $global:BECCreatedBody.filterStartDateTime | Should -Be "2026-09-01T00:00:00Z"
            $global:BECCreatedBody.filterEndDateTime | Should -Be "2026-09-10T00:00:00Z"
            $global:BECCreatedBody.userPrincipalNameFilters | Should -Be @("a@contoso.com")
            $global:BECCreatedBody.operationFilters | Should -Be @("New-InboxRule")
            $global:BECCreatedBody.ContainsKey("ipAddressFilters") | Should -BeFalse
        }

        It "creates nothing with -WhatIf" {
            New-BECAuditLogSearch -UserPrincipalName "a@contoso.com" -WhatIf

            Should -Invoke -ModuleName BECToolkit New-MgBetaSecurityAuditLogQuery -Times 0 -Exactly
        }

        It "waits until the search finishes" {
            $global:BECPollCount = 0
            Mock -ModuleName BECToolkit Get-MgBetaSecurityAuditLogQuery {
                $global:BECPollCount++
                $status = if ($global:BECPollCount -lt 3) { "running" } else { "succeeded" }
                [PSCustomObject]@{ Id = "new-1"; DisplayName = "Case-1"; Status = $status }
            } -ParameterFilter { $AuditLogQueryId -eq "new-1" }

            $result = New-BECAuditLogSearch -UserPrincipalName "a@contoso.com" -Wait -PollIntervalSeconds 1

            $result.Status | Should -Be "succeeded"
            Should -Invoke -ModuleName BECToolkit Start-Sleep -Times 3 -Exactly
        }
    }

    Context "Get-BECActivitySummary" {
        It "groups activity by IP address, ignoring ports" {
            $investigation = [PSCustomObject]@{
                InboxRules = @([PSCustomObject]@{ CreationTime = "2026-09-01T12:00:00"; UserId = "a@contoso.com"; ClientIPAddress = "5.6.7.8:51234"; SessionId = $null })
                SignInLogs = @([PSCustomObject]@{ CreationTime = "2026-09-01T11:00:00Z"; UserId = "a@contoso.com"; ClientIPAddress = "5.6.7.8"; SessionId = "sess-1"; UserAgent = "Mozilla/5.0"; City = "Lagos"; State = $null; Country = "NG" })
                AccessedMail = @([PSCustomObject]@{ CreationTime = "2026-09-01T13:00:00"; UserId = "a@contoso.com"; ClientIPAddress = "1.2.3.4"; SessionId = "sess-2"; ClientInfoString = "Client=OWA" })
            }

            $result = @(Get-BECActivitySummary -Investigation $investigation -GroupBy IPAddress)

            $result.Count | Should -Be 2
            $result[0].IPAddress | Should -Be "5.6.7.8"
            $result[0].Locations | Should -Be "Lagos, NG"
            $result[0].FirstSeen | Should -Be "2026-09-01T11:00:00Z"
            $result[0].LastSeen | Should -Be "2026-09-01T12:00:00Z"
            $result[0].Activity | Should -Be "InboxRules=1; SignInLogs=1"
            $result[0].SessionCount | Should -Be 1
            $result[1].IPAddress | Should -Be "1.2.3.4"
        }

        It "groups activity by session" {
            $investigation = [PSCustomObject]@{
                SignInLogs = @([PSCustomObject]@{ CreationTime = "2026-09-01T11:00:00Z"; UserId = "a@contoso.com"; ClientIPAddress = "5.6.7.8"; SessionId = "sess-1" })
                AccessedMail = @([PSCustomObject]@{ CreationTime = "2026-09-01T13:00:00"; UserId = "a@contoso.com"; ClientIPAddress = "1.2.3.4"; SessionId = "sess-1" })
            }

            $result = @($investigation | Get-BECActivitySummary -GroupBy Session)

            $result.Count | Should -Be 1
            $result[0].SessionId | Should -Be "sess-1"
            $result[0].IPAddresses | Should -Be "1.2.3.4; 5.6.7.8"
            $result[0].EventCount | Should -Be 2
        }
    }

    Context "Exports" {
        It "writes UTF-8 CSV files without a #TYPE line" {
            # JSON escapes keep this file ASCII, which Windows PowerShell 5.1 reads reliably
            $global:BECTestRecords = @(New-TestRecord '{"Operation":"Send","CreationTime":"2026-09-01T12:00:00","UserId":"a@contoso.com","Item":{"Id":"m1","Subject":"\u00dcberweisung \u20ac"}}')
            $expected_subject = "$([char]0x00DC)berweisung $([char]0x20AC)"

            Get-BECSentMailItems -ExportCsv -OutputPath (Join-Path $TestDrive "export") | Out-Null

            $path = Join-Path $TestDrive "export/SentMail.csv"
            $lines = @(Get-Content $path -Encoding UTF8)
            $lines[0] | Should -BeLike '"CreationTime",*'
            (Import-Csv $path -Encoding UTF8).ItemSubject | Should -Be $expected_subject
        }

        It "skips the file when there are no results" {
            Get-BECSentMailItems -ExportCsv -OutputPath (Join-Path $TestDrive "empty") | Out-Null

            Join-Path $TestDrive "empty/SentMail.csv" | Should -Not -Exist
        }

        It "exports the raw audit log with AuditData as JSON" {
            $global:BECTestRecords = @(New-TestRecord '{"Operation":"New-InboxRule","CreationTime":"2026-09-01T12:00:00","UserId":"a@contoso.com","Parameters":[{"Name":"Name","Value":"."}]}')

            $result = Export-BECRawAuditLog -OutputPath (Join-Path $TestDrive "raw") -PassThru

            Join-Path $TestDrive "raw/RawAuditLog.csv" | Should -Exist
            $result.Operation | Should -Be "New-InboxRule"
            ($result.AuditData | ConvertFrom-Json).Parameters[0].Value | Should -Be "."
        }
    }

    Context "Invoke-BECInvestigation" {
        BeforeAll {
            Mock -ModuleName BECToolkit Invoke-MgGraphRequest { throw "Tenant does not have a SKU required for this API" }
        }

        It "exports every result into its own run folder and continues without sign-in logs" {
            Mock -ModuleName BECToolkit Write-Warning { }
            $global:BECTestRecords = @(
                New-TestRecord '{"Operation":"New-InboxRule","CreationTime":"2026-09-01T12:00:00","UserId":"a@contoso.com","ClientIP":"5.6.7.8","Parameters":[{"Name":"Name","Value":"."}]}'
                New-TestRecord '{"Operation":"Send","CreationTime":"2026-09-01T12:05:00","UserId":"a@contoso.com","ClientIPAddress":"5.6.7.8","Item":{"Id":"m1","Subject":"Hi"}}'
            )

            Push-Location $TestDrive
            try {
                $result = Invoke-BECInvestigation
            } finally {
                Pop-Location
            }

            $result.OutputPath | Should -BeLike (Join-Path $TestDrive "BEC_Export*Case")
            $files = @(Get-ChildItem $result.OutputPath | ForEach-Object { $_.Name } | Sort-Object)
            $files | Should -Be @("InboxRules.csv", "IPSummary.csv", "RawAuditLog.csv", "SentMail.csv")
            $result.IPSummary.IPAddress | Should -Be "5.6.7.8"
            $result.AuditLogSearch.Id | Should -Be "s1"
            Should -Invoke -ModuleName BECToolkit Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -like "Couldn't read sign-in logs*" }
            Should -Invoke -ModuleName BECToolkit Get-MgBetaSecurityAuditLogQueryRecord -Times 1 -Exactly
        }
    }

    Context "Helpers" {
        It "strips ports from IP addresses" {
            InModuleScope BECToolkit {
                ConvertTo-BECIPAddress "1.2.3.4:5678" | Should -Be "1.2.3.4"
                ConvertTo-BECIPAddress "[2001:db8::1]:443" | Should -Be "2001:db8::1"
                ConvertTo-BECIPAddress "2001:db8::1" | Should -Be "2001:db8::1"
                ConvertTo-BECIPAddress "1.2.3.4" | Should -Be "1.2.3.4"
            }
        }

        It "normalizes timestamps to UTC" {
            InModuleScope BECToolkit {
                ConvertTo-BECTimestamp "2026-09-01T10:00:00" | Should -Be "2026-09-01T10:00:00Z"
                ConvertTo-BECTimestamp "2026-09-01T10:00:00Z" | Should -Be "2026-09-01T10:00:00Z"
                ConvertTo-BECTimestamp ([datetime]::new(2026, 9, 1, 10, 0, 0, [System.DateTimeKind]::Utc)) | Should -Be "2026-09-01T10:00:00Z"
                ConvertTo-BECTimestamp $null | Should -BeNullOrEmpty
            }
        }
    }
}
