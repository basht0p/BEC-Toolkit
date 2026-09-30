function Get-BECActivitySummary {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$Investigation,
        [ValidateSet("IPAddress", "Session")]
        [string]$GroupBy = "IPAddress"
    )

    process {
        # Flatten every category into one timeline of who, where and what
        $activity = @(foreach ($category in $Investigation.PSObject.Properties) {
            foreach ($row in @($category.Value)) {
                if ($null -eq $row -or $null -eq $row.PSObject.Properties["CreationTime"] -or $null -eq $row.PSObject.Properties["UserId"]) {
                    continue
                }

                $location = if ($row.PSObject.Properties["Country"]) {
                    (@($row.City, $row.State, $row.Country) | Where-Object { $_ }) -join ", "
                }

                [PSCustomObject]@{
                    Category = $category.Name
                    Time = ConvertTo-BECTimestamp $row.CreationTime
                    User = $row.UserId
                    IPAddress = ConvertTo-BECIPAddress $row.ClientIPAddress
                    SessionId = if ($row.PSObject.Properties["SessionId"]) { $row.SessionId }
                    Client = Select-BECFirstValue $row.PSObject.Properties["ClientInfoString"].Value $row.PSObject.Properties["UserAgent"].Value
                    Location = $location
                }
            }
        })

        $group_property = if ($GroupBy -eq "Session") { "SessionId" } else { "IPAddress" }
        $groups = $activity | Where-Object { $_.$group_property } | Group-Object -Property $group_property

        $summary = @(foreach ($group in $groups) {
            $times = @($group.Group.Time | Where-Object { $_ } | Sort-Object)
            $category_counts = ($group.Group | Group-Object Category | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join "; "
            $clients = (@($group.Group.Client | Where-Object { $_ } | Select-Object -Unique) | Select-Object -First 5) -join " | "
            $locations = (@($group.Group.Location | Where-Object { $_ } | Select-Object -Unique)) -join "; "
            $users = (@($group.Group.User | Where-Object { $_ } | Sort-Object -Unique)) -join "; "

            if ($GroupBy -eq "Session") {
                [PSCustomObject]@{
                    SessionId = $group.Name
                    Users = $users
                    IPAddresses = (@($group.Group.IPAddress | Where-Object { $_ } | Sort-Object -Unique)) -join "; "
                    Locations = $locations
                    FirstSeen = $times | Select-Object -First 1
                    LastSeen = $times | Select-Object -Last 1
                    EventCount = $group.Count
                    Activity = $category_counts
                    Clients = $clients
                }
            } else {
                [PSCustomObject]@{
                    IPAddress = $group.Name
                    Locations = $locations
                    Users = $users
                    FirstSeen = $times | Select-Object -First 1
                    LastSeen = $times | Select-Object -Last 1
                    EventCount = $group.Count
                    SessionCount = @($group.Group.SessionId | Where-Object { $_ } | Select-Object -Unique).Count
                    Activity = $category_counts
                    Clients = $clients
                }
            }
        })

        $summary | Sort-Object FirstSeen
    }
}
