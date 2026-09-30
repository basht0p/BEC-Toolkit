function Select-BECFirstValue {
    # Returns the first value that isn't null or an empty string
    param (
        [Parameter(ValueFromRemainingArguments)]
        [object[]]$Values
    )

    foreach ($value in $Values) {
        if ($null -ne $value -and "$value" -ne "") {
            return $value
        }
    }
}
