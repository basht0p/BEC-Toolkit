# BEC Investigation Module

**Purpose**  
PowerShell module for investigating Business Email Compromise (BEC) by querying Microsoft 365 audit logs using Microsoft Graph.

This module was created to ease the burden of crawling through clunky audit logs and nested JSON objects inside CSV files (thanks, Microsoft).


## Requirements

> This module will automatically connect to Microsoft Graph if no context is present.

### Required Modules
- `Microsoft.Graph.Applications`
- `Microsoft.Graph.Authentication`
- `Microsoft.Graph.Beta.Security`

### Required Scopes
- `AuditLog.Read.All`
- `AuditLogsQuery.Read.All`


## Functions

### Get-BECAccessedMailItems

Retrieves `MailItemsAccessed` events.

```powershell
Get-BECAccessedMailItems [-AuditLogSearchName <String>] [-ExportCsv]
```

**Examples**

```powershell
# Use the most recent successful audit log search
Get-BECAccessedMailItems

# Use a specific audit log search by name
Get-BECAccessedMailItems -AuditLogSearchName "BEC-Incident-2025-05-28"

# Export results to CSV
Get-BECAccessedMailItems -AuditLogSearchName "BEC-Incident-2025-05-28" -ExportCsv
```

---

### Get-BECSentMailItems

Retrieves `Send` events.

```powershell
Get-BECSentMailItems [-AuditLogSearchName <String>] [-ExportCsv]
```

**Examples**

```powershell
Get-BECSentMailItems

Get-BECSentMailItems -AuditLogSearchName "BEC-Incident-2025-05-28" -ExportCsv
```

---

### Get-BECFileOperations

Retrieves file operations (`File*`).

```powershell
Get-BECFileOperations [-AuditLogSearchName <String>] [-ExportCsv]
```

**Examples**

```powershell
Get-BECFileOperations -ExportCsv

Get-BECFileOperations -AuditLogSearchName "BEC-Incident-2025-05-28" -ExportCsv
```

---

### Get-BECSharingOperations

Retrieves sharing-related operations.

```powershell
Get-BECSharingOperations [-AuditLogSearchName <String>] [-ExportCsv]
```

**Examples**

```powershell
Get-BECSharingOperations

Get-BECSharingOperations -AuditLogSearchName "BEC-Incident-2025-05-28" -ExportCsv
```

---

### Get-BECAuthentications

Retrieves authentication events (`UserLoggedIn`, `UserLoginFailed`).

```powershell
Get-BECAuthentications [-AuditLogSearchName <String>] [-ExportCsv]
```

**Examples**

```powershell
Get-BECAuthentications -ExportCsv

Get-BECAuthentications -AuditLogSearchName "BEC-Incident-2025-05-28" -ExportCsv
```

---

### Invoke-BECInvestigation

Runs the full BEC investigation (all functions) and exports results.

```powershell
Invoke-BECInvestigation [-AuditLogSearchName <String>]
```

**Examples**

```powershell
# Run full investigation using the latest successful audit log search
Invoke-BECInvestigation

# Run full investigation against a named audit log search
Invoke-BECInvestigation -AuditLogSearchName "BEC-Incident-2025-05-28"
```

---

## Export Output

When using `-ExportCsv` (or `Invoke-BECInvestigation`), files with results are written to:

```
.\BEC_Export\
├── AccessedMail.csv
├── SentMail.csv
├── FileOperations.csv
├── SharingOperations.csv
└── Authentications.csv
```

---

## Typical Usage Workflow

```powershell
# 1. Run a full investigation against a specific audit log search
Invoke-BECInvestigation -AuditLogSearchName "BEC-Q2-2025"

# 2. Or run individual functions as needed
Get-BECAccessedMailItems -AuditLogSearchName "BEC-Q2-2025" -ExportCsv
Get-BECSentMailItems -AuditLogSearchName "BEC-Q2-2025" -ExportCsv
Get-BECAuthentications -AuditLogSearchName "BEC-Q2-2025" -ExportCsv
```

---

*Documentation generated using AI.*