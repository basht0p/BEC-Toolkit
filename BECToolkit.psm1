# Audit records of the most recently read search, shared by every function
$script:BECRecordCache = @{ SearchId = $null; Records = @() }
$script:BECWarnedSearchIds = New-Object 'System.Collections.Generic.HashSet[string]'

$private_functions = @(Get-ChildItem -Path (Join-Path $PSScriptRoot "Private") -Filter "*.ps1" -ErrorAction SilentlyContinue)
$public_functions = @(Get-ChildItem -Path (Join-Path $PSScriptRoot "Public") -Filter "*.ps1" -ErrorAction SilentlyContinue)

foreach ($function_file in @($private_functions + $public_functions)) {
    . $function_file.FullName
}

Export-ModuleMember -Function $public_functions.BaseName
