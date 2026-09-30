function Get-BECRuleIndicator {
    # Flags inbox rule traits commonly seen in BEC: forwarding, deleting or hiding mail,
    # targeting payment or security keywords, and throwaway rule names
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [string]$RuleName,
        [string]$Actions,
        [string]$Conditions
    )

    $indicators = @()

    if ($Actions -match "Forward|Redirect") {
        $indicators += "Forwards or redirects mail"
    }
    if ($Actions -match "Delete") {
        $indicators += "Deletes mail"
    }
    if ($Actions -match "RSS|Conversation History|Archive|Junk|Deleted Items|Notes|Sync Issues") {
        $indicators += "Moves mail to a rarely checked folder"
    }
    if ($Actions -match "MarkAsRead") {
        $indicators += "Marks mail as read"
    }
    if ($Conditions -match "invoice|payment|wire|bank|\bach\b|remit|transfer|payroll|deposit|\bw-?2\b|hack|phish|spam|compromise|fraud|password|security") {
        $indicators += "Targets payment or security keywords"
    }
    if ($RuleName -and ($RuleName.Trim().Length -le 2 -or $RuleName -notmatch "[A-Za-z0-9]")) {
        $indicators += "Suspicious rule name"
    }

    return ($indicators -join "; ")
}
