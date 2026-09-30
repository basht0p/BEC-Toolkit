function ConvertTo-BECPropertyTable {
    [CmdletBinding()]
    [OutputType([hashtable])]
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
