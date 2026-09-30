function ConvertTo-BECIPAddress {
    # Strips the port that Exchange admin records append ("1.2.3.4:5678", "[2001:db8::1]:443")
    # so the same client matches across record types
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [string]$Value
    )

    if (-not $Value) {
        return $null
    }

    $address = $Value.Trim()

    if ($address -match '^\[(?<ip>[^\]]+)\](:\d+)?$') {
        return $Matches.ip
    }
    if ($address -match '^(?<ip>\d{1,3}(\.\d{1,3}){3}):\d+$') {
        return $Matches.ip
    }

    return $address
}
