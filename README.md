# BEC Investigation Module

**Purpose**  
PowerShell module for investigating Business Email Compromise (BEC) by querying Microsoft 365 audit logs and Entra sign-in logs using Microsoft Graph.

This module was created to ease the burden of crawling through clunky audit logs and nested JSON objects inside CSV files (thanks, Microsoft).


## Requirements

### Required Modules
Install these once:

```powershell
Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Beta.Security -Scope CurrentUser
```

Then import the toolkit from its folder:

```powershell
Import-Module .\BECToolkit.psd1
```

Works in Windows PowerShell 5.1 and PowerShell 7.

### Required Scopes
- `AuditLogsQuery.Read.All`: create and read Purview audit log searches
- `AuditLog.Read.All`: read Entra sign-in logs

The module connects to Microsoft Graph with these scopes if no session exists, and reconnects to add them if your current session is missing any.

The account you sign in with also needs permission to search the audit log in Microsoft Purview (for example the Audit Reader role) and to read sign-in logs (for example Security Reader). Sign-in logs through Graph require Microsoft Entra ID P1 or P2.


## Quick Start

```powershell
# 1. Create an audit log search for the compromised user and wait for it to finish
$search = New-BECAuditLogSearch -UserPrincipalName "jdoe@contoso.com" -StartDateTime "2025-05-01" -EndDateTime "2025-05-28" -Wait

# 2. Run every check against it
$investigation = Invoke-BECInvestigation -AuditLogSearchId $search.Id

# 3. Start with the summaries: which IPs and sessions did what
$investigation.IPSummary | Format-Table
$investigation.InboxRules | Where-Object Indicators | Format-List
```

Audit log searches can take anywhere from a few minutes to more than an hour to finish.


## Selecting an Audit Log Search

Every function reads from an existing, **succeeded** Purview audit log search:

- `-AuditLogSearchName` selects a search by display name. If more than one search has that name, use `-AuditLogSearchId` instead.
- `-AuditLogSearchId` selects a search by its ID.
- With neither, the first succeeded search returned by Microsoft Graph is used, and its name is printed.

Searches that are still running, failed, or cancelled are rejected. A warning is shown if the search hit its record count limit, which means the results are incomplete.

A search's records are downloaded once and reused by every function, so running several functions against the same search doesn't download it again.


## Functions

| Function | What it returns |
| --- | --- |
| `New-BECAuditLogSearch` | Creates a Purview audit log search |
| `Invoke-BECInvestigation` | Runs every check below and exports the results |
| `Get-BECAccessedMailItems` | Mail read or synced (`MailItemsAccessed`) |
| `Get-BECSentMailItems` | Mail sent (`Send`, `SendAs`, `SendOnBehalf`) |
| `Get-BECDeletedMailItems` | Mail deleted (`MoveToDeletedItems`, `SoftDelete`, `HardDelete`) |
| `Get-BECInboxRules` | Inbox rules created, changed or removed, with indicators |
| `Get-BECMailboxChanges` | Forwarding, mailbox permissions, transport rules and other mailbox settings, with indicators |
| `Get-BECSharingOperations` | SharePoint and OneDrive sharing, including anonymous links |
| `Get-BECFileOperations` | SharePoint and OneDrive file operations (`File*`) |
| `Get-BECAuthentications` | Sign-ins recorded in the audit log (`UserLoggedIn`, `UserLoginFailed`) |
| `Get-BECIdentityChanges` | App consents, new app credentials, MFA method and password changes, role grants |
| `Get-BECSignInLogs` | Entra sign-in logs, including non-interactive sign-ins |
| `Get-BECActivitySummary` | Activity grouped by IP address or session |
| `Export-BECRawAuditLog` | Every record of a search, unparsed |

All `Get-BEC*` functions that read the audit log take the same parameters:

```powershell
Get-BECInboxRules [-AuditLogSearchName <String>] [-AuditLogSearchId <String>] [-ExportCsv] [-OutputPath <String>]
```

`-ExportCsv` writes the results to `-OutputPath` (default `.\BEC_Export`).

---

### New-BECAuditLogSearch

Creates a Purview audit log search for one or more users or IP addresses. `-Wait` checks the search until it finishes.

```powershell
New-BECAuditLogSearch [-UserPrincipalName <String[]>] [-IPAddress <String[]>] [-StartDateTime <DateTime>] [-EndDateTime <DateTime>]
                      [-DisplayName <String>] [-Operation <String[]>] [-RecordType <String[]>] [-Wait] [-TimeoutMinutes <Int>]
```

The dates default to the last 30 days, and the display name defaults to `BEC-<user>-<timestamp>`.

```powershell
New-BECAuditLogSearch -UserPrincipalName "jdoe@contoso.com" -Wait

New-BECAuditLogSearch -UserPrincipalName "jdoe@contoso.com", "ap@contoso.com" -StartDateTime "2025-05-01" -EndDateTime "2025-05-28" -DisplayName "BEC-Incident-2025-05-28"
```

---

### Invoke-BECInvestigation

Runs every check, exports each result to CSV, and writes an IP summary, a session summary and the raw audit log.

```powershell
Invoke-BECInvestigation [-AuditLogSearchName <String>] [-AuditLogSearchId <String>] [-OutputPath <String>] [-SkipSignInLogs]
```

Each run writes to its own folder, `.\BEC_Export\<timestamp>_<search name>`, unless you pass `-OutputPath`. Sign-in logs are read for the users the search filters on; if they can't be read (for example without an Entra ID P1 license), the run continues without them.

```powershell
Invoke-BECInvestigation -AuditLogSearchName "BEC-Incident-2025-05-28"
```

The returned object has one property per check, plus `IPSummary`, `SessionSummary`, `AuditLogSearch` and `OutputPath`.

---

### Get-BECAccessedMailItems

Bind events (individual messages opened) produce one row per message. Sync events (a client downloaded a whole folder) produce one row per folder with the item columns empty; treat every item in that folder as accessed. The `MailAccessType` column tells the two apart.

---

### Get-BECInboxRules

Covers rules made in Outlook on the web or PowerShell (`New-InboxRule`, `Set-InboxRule`, `Enable-InboxRule`, `Disable-InboxRule`, `Remove-InboxRule`) and in desktop Outlook (`UpdateInboxRules`).

The `Indicators` column flags common BEC traits:
- forwards or redirects mail
- deletes mail
- moves mail to a rarely checked folder (RSS Feeds, Conversation History, Archive and similar)
- marks mail as read
- targets payment or security keywords (invoice, wire, payroll, phish, hack and similar)
- a throwaway rule name such as `.`

---

### Get-BECMailboxChanges

Covers `Set-Mailbox`, mailbox, recipient and folder permission changes, `Set-CASMailbox`, `Set-MailboxJunkEmailConfiguration` and transport rules. The `Indicators` column flags forwarding, full access and Send As grants, transport rules that forward or delete mail, junk mail filtering changes and newly enabled mail protocols.

---

### Get-BECIdentityChanges

Entra changes attackers use to keep access after a password reset:
- app consents and permission grants
- new apps and app credentials
- authentication method (MFA) changes
- password changes and resets
- directory role grants
- device registrations

The `Category` column groups them.

---

### Get-BECSignInLogs

Reads Entra sign-in logs, including non-interactive sign-ins, where token replay from an attacker usually shows up. Each sign-in includes location, risk, device and Conditional Access details. Users and dates default to the audit log search's filters.

```powershell
Get-BECSignInLogs [-UserPrincipalName <String[]>] [-StartDateTime <DateTime>] [-EndDateTime <DateTime>]
                  [-AuditLogSearchName <String>] [-AuditLogSearchId <String>] [-InteractiveOnly] [-ExportCsv] [-OutputPath <String>]
```

```powershell
Get-BECSignInLogs -UserPrincipalName "jdoe@contoso.com" -StartDateTime (Get-Date).AddDays(-7) -EndDateTime (Get-Date) -ExportCsv
```

Entra keeps sign-in logs for 30 days (7 days without Entra ID P1 or P2).

---

### Get-BECActivitySummary

Groups the results of `Invoke-BECInvestigation` by IP address or session. Each row shows the users involved, the first and last time the IP or session was seen, a count of events per category, and the clients used. Sign-in log locations are added where available.

```powershell
$investigation | Get-BECActivitySummary -GroupBy IPAddress
$investigation | Get-BECActivitySummary -GroupBy Session
```

---

### Export-BECRawAuditLog

Exports every record of a search without parsing: the standard record fields plus the complete `AuditData` as JSON. Use it when you need the original data for evidence or for fields the other functions don't extract.

```powershell
Export-BECRawAuditLog -AuditLogSearchName "BEC-Incident-2025-05-28" -OutputPath .\Evidence
```

---

## Export Output

`Invoke-BECInvestigation` writes these files; the individual functions write the same file names with `-ExportCsv`. Files with no results are skipped.

```
.\BEC_Export\<timestamp>_<search name>\
├── AccessedMail.csv
├── SentMail.csv
├── DeletedMail.csv
├── InboxRules.csv
├── MailboxChanges.csv
├── SharingOperations.csv
├── FileOperations.csv
├── Authentications.csv
├── IdentityChanges.csv
├── SignInLogs.csv
├── IPSummary.csv
├── SessionSummary.csv
└── RawAuditLog.csv
```

Times are in UTC. CSV files are UTF-8.


## Development

Run the tests and the linter from the repository root:

```powershell
Invoke-Pester -Path .\tests
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```

The tests stub out the Microsoft Graph cmdlets, so they don't need the Graph modules or a tenant. GitHub Actions runs both on every push and pull request.

---

*Documentation generated using AI.*
