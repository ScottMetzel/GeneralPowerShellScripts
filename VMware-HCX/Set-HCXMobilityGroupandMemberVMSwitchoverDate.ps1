[CmdletBinding()]
param (
    [System.String]$MobilityGroupName,
    [System.DateTime]$NewSwitchoverDate = (Get-Date).AddMonths(1),
    [switch]$Recursive
)
$InformationPreference = "Continue"

# Get the HCX Mobility Group
Write-Information -MessageData "Getting HCX Mobility Group: '$MobilityGroupName'."
$GetHCXMobilityGroup = Get-HCXMobilityGroup -Name $MobilityGroupName -ErrorAction SilentlyContinue
if ($GetHCXMobilityGroup) {
    Write-Information -MessageData "Found HCX Mobility Group: '$MobilityGroupName'."
}
else {
    Write-Warning -Message "Did not find HCX Mobility Group: '$MobilityGroupName'. Please check the group name and try again."
    throw
}

# With the group found, set the scheduled end time, aka switchover date.
[System.String]$NewSwitchoverDateString = $NewSwitchoverDate.ToString()
Write-Information -MessageData "Setting HCX Mobility Group switchover date to: '$NewSwitchoverDateString'."
try {
    $ErrorActionPreference = "Stop"
    Set-HCXMobilityGroupConfiguration -MobilityGroup $GetHCXMobilityGroup -ScheduleEndTime $NewSwitchoverDate
}
catch {
    $_
    Write-Error -Message "Could not set HCX Mobility Group configuration."
}

# Define migration states to avoid
[System.Collections.ArrayList]$MigrationStatesToAvoid = @("MIGRATE_CANCELED", "MIGRATE_FAILED", "MIGRATED")

# Create a new Array List and add the mobility group member migrations to it which haven't been canceled, aren't failed, nor already migrated
Write-Information -MessageData "Adding group member migrations to a new array."
[System.Collection.ArrayList]$MobilityGroupMigrations = @()
$GetHCXMobilityGroup.Migration | Where-Object -FilterScript { $_.State -notin $MigrationStatesToAvoid } | ForEach-Object -Process {
    $MobilityGroupMigrations.Add($_) | Out-Null
}

[System.Int32]$MobilityGroupMigrationsCount = $MobilityGroupMigrations.Count

# If the date should be set recursively and there's at least one migration in the group, then set the new date for group member migrations.
if ($Recursive -and ($MobilityGroupMigrationsCount -gt 0)) {
    Write-Information -MessageData "Will set switchover date for mobility group member migrations."

    # Create a simple counter for tracking
    [System.Int32]$i = 1

    # Loop through each migration and set the new date
    Write-Information -MessageData "About to loop through group member migrations and set new switchover date."
    foreach ($HCXMigration in $MobilityGroupMigrations) {
        [System.String]$VMName = $HCXMigration.VM.Name
        Write-Information -MessageData "Setting switchover date for VM: '$VMName' to: '$NewSwitchoverDateString'. HCX VM: '$i' of: '$MobilityGroupMigrationsCount' VMs."

        try {
            $ErrorActionPreference = "Continue"
            Set-HCXMigration -Migration $HCXMigration -ScheduleEndTime $NewSwitchoverDate
        }
        catch {
            $_
            Write-Error -Message "Could not set migration configuration for migration with VM name: '$VMName' in HCX Mobility Group: '$MobilityGroupName'."
            throw
        }
        $i++
    }
}
else {
    Write-Information -MessageData "The recursive parameter was not specified or no migrations were found in the mobility group."
}
Write-Information -MessageData "All done! Happy migrating."