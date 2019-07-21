## Credit for the original version goes to: http://sharepointjack.com/2017/powershell-script-to-remove-duplicate-old-modules/
#Requires -RunAsAdministrator

$InformationPreference = 'Continue'

Write-Information -MessageData "Getting installed modules..."
[System.Collections.ArrayList]$GetInstalledModules = Get-InstalledModule

[System.Int32]$c = 1
[System.Int32]$InstalledModuleCount = $GetInstalledModules.Count

Write-Information -MessageData "Entering loop..."
foreach ($InstalledModule in $GetInstalledModules) {
    [System.String]$ModuleName = $InstalledModule.Name
    Write-Information -MessageData "Working on module: '$ModuleName'. '$c' of '$InstalledModuleCount' modules to check."

    Write-Information -MessageData "Getting all installed versions of: '$ModuleName'."
    $GetAllVersionsOfModule = Get-InstalledModule $ModuleName -AllVersions | Sort-Object -Property Version -Descending
    [System.Int32]$InstalledVersionCount = $GetAllVersionsOfModule.Count

    if ($InstalledVersionCount -gt 1) {
        Write-Information -MessageData "There are: '$InstalledVersionCount' installed versions of this module."

        [System.String]$MostRecentVersion = $GetAllVersionsOfModule[0].Version
        [System.Collections.ArrayList]$OlderVersions = $GetAllVersionsOfModule | Where-Object -FilterScript {$_.Version -lt $MostRecentVersion}
        [System.Int32]$OlderVersionCount = $OlderVersions.Count

        Write-Information -MessageData "The most recent version of this module is: '$MostRecentVersion'. Will remove: '$OlderVersionCount' older versions."

        [System.Int32]$j = 1
        foreach ($OlderVersion in $OlderVersions) {
            [System.String]$OlderVersionName = $OlderVersion.Name
            [System.String]$OlderVersionVersion = $OlderVersion.Version
            Write-Information -MessageData "Uninstalling: '$OlderVersionName' with version: '$OlderVersionVersion'."

            $OlderVersion | Uninstall-Module -Force

            Write-Information -MessageData "Uninstalled. Moving on."

            $j++
        }

    }
    else {
        Write-Information -MessageData "Since there is only one installed version, not checking for duplicates."
    }

    $c++
}

Write-Information -MessageData "All duplicate & older versions uninstalled. Exiting."