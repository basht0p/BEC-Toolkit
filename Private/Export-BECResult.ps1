function Export-BECResult {
    [CmdletBinding()]
    param (
        [AllowEmptyCollection()]
        [object[]]$InputObject,
        [Parameter(Mandatory)]
        [string]$OutputPath,
        [Parameter(Mandatory)]
        [string]$FileName,
        [Parameter(Mandatory)]
        [string]$Description
    )

    if (@($InputObject).Count -eq 0) {
        Write-Host "No $Description found in audit. Skipping export." -ForegroundColor Gray
        return
    }

    if (!(Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory | Out-Null
    }

    $export_full_path = Join-Path $OutputPath $FileName

    $InputObject | Export-Csv -Path $export_full_path -NoTypeInformation -Encoding UTF8
    Write-Host "Exporting $(@($InputObject).Count) $Description to file below:" -BackgroundColor Black -ForegroundColor Yellow
    Write-Host "$export_full_path" -BackgroundColor Black -ForegroundColor Yellow
}
