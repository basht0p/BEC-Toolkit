function ConvertTo-BECTimestamp {
    # Normalizes audit and sign-in times to UTC ISO 8601 strings ("2026-09-01T12:00:00Z").
    # Audit records store UTC times without a zone, so zone-less strings are read as UTC.
    [CmdletBinding()]
    [OutputType([string])]
    param (
        $Value
    )

    if ($null -eq $Value -or "$Value" -eq "") {
        return $null
    }

    if ($Value -is [datetimeoffset]) {
        return $Value.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
    }

    if ($Value -is [datetime]) {
        $date_time = if ($Value.Kind -eq [System.DateTimeKind]::Unspecified) { [datetime]::SpecifyKind($Value, [System.DateTimeKind]::Utc) } else { $Value.ToUniversalTime() }
        return $date_time.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
    }

    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse("$Value", [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
        return $parsed.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
    }

    return "$Value"
}
