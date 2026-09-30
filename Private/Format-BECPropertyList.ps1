function Format-BECPropertyList {
    # Formats selected entries of a name/value table as "Name=Value; Name=Value".
    # Entries that are empty or "False" are left out, so only settings that were actually applied show.
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [hashtable]$PropertyTable,
        [string[]]$Name
    )

    $names = if ($Name) { $Name } else { @($PropertyTable.Keys | Sort-Object) }

    $entries = foreach ($property_name in $names) {
        $value = $PropertyTable[$property_name]
        if ($null -eq $value -or "$value" -eq "" -or "$value" -eq "False") {
            continue
        }
        "$property_name=$(@($value) -join ',')"
    }

    return (@($entries) -join "; ")
}
