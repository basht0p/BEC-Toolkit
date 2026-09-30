function Get-BECIdentityChanges {
    [CmdletBinding()]
    param (
        [string]$AuditLogSearchName,
        [string]$AuditLogSearchId,
        [switch]$ExportCsv,
        [string]$OutputPath = (Join-Path $pwd "BEC_Export")
    )

    # Entra operations attackers use to keep access after the password is reset.
    # The audit log writes most of these with a trailing period, which is ignored here.
    $identity_operations = @{
        "Consent to application" = "App consent or permission grant"
        "Add OAuth2PermissionGrant" = "App consent or permission grant"
        "Add delegated permission grant" = "App consent or permission grant"
        "Add app role assignment grant to user" = "App consent or permission grant"
        "Add app role assignment to service principal" = "App consent or permission grant"
        "Add application" = "New app in tenant"
        "Add service principal" = "New app in tenant"
        "Add service principal credentials" = "App credentials added"
        "User registered security info" = "Authentication method changed"
        "User registered all required security info" = "Authentication method changed"
        "User changed default security info" = "Authentication method changed"
        "User updated security info" = "Authentication method changed"
        "User deleted security info" = "Authentication method changed"
        "Admin registered security info" = "Authentication method changed"
        "Admin updated security info" = "Authentication method changed"
        "Admin deleted security info" = "Authentication method changed"
        "Reset user password" = "Password changed or reset"
        "Change user password" = "Password changed or reset"
        "Set force change user password" = "Password changed or reset"
        "Reset password (self-service)" = "Password changed or reset"
        "Change password (self-service)" = "Password changed or reset"
        "Add member to role" = "Directory role granted"
        "Add eligible member to role" = "Directory role granted"
        "Register device" = "Device registered"
        "Add registered owner to device" = "Device registered"
        "Add registered users to device" = "Device registered"
    }

    $audit_log_records = Get-BECAuditRecord -AuditLogSearchName $AuditLogSearchName -AuditLogSearchId $AuditLogSearchId

    $identity_changes = @(foreach ($audit_log_record in $audit_log_records) {
        $record = $audit_log_record.AuditData.AdditionalProperties
        $operation = "$($record.Operation)".TrimEnd(".")
        $modified_property_names = @($record.ModifiedProperties | ForEach-Object { $_.Name })

        if ($identity_operations.ContainsKey($operation)) {
            $category = $identity_operations[$operation]
        } elseif ($operation -like "Update application*Certificates and secrets management*") {
            $category = "App credentials added"
        } elseif ($operation -eq "Update user" -and ($modified_property_names -match "StrongAuthentication")) {
            # "Update user" is noisy; only MFA method and phone changes are relevant here
            $category = "Authentication method changed"
        } else {
            continue
        }

        $modified_properties = @(foreach ($modified_property in $record.ModifiedProperties) {
            "$($modified_property.Name): $($modified_property.OldValue) -> $($modified_property.NewValue)"
        })

        [PSCustomObject]@{
            CreationTime = $record.CreationTime
            UserId = $record.UserId
            ClientIPAddress = Select-BECFirstValue $record.ClientIP $record.ActorIpAddress
            SessionId = $record.AppAccessContext.AADSessionId
            Operation = $record.Operation
            Category = $category
            ResultStatus = $record.ResultStatus
            Target = $record.ObjectId
            TargetDetails = (@($record.Target | ForEach-Object { $_.ID } | Where-Object { $_ } | Select-Object -Unique) -join "; ")
            ModifiedProperties = $modified_properties -join " | "
        }
    })

    if ($ExportCsv) {
        Export-BECResult -InputObject $identity_changes -OutputPath $OutputPath -FileName "IdentityChanges.csv" -Description "identity change(s)"
    }

    return $identity_changes
}
