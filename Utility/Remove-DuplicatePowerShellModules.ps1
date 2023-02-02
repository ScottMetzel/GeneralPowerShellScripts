[CmdletBinding()]
$InformationPreference = "Continue"

[System.Collections.ArrayList]$InstalledModuleArray = @()

Write-Information -MessageData "Getting installed modules."
Get-InstalledModule | Sort-Object -Property Name, Version | ForEach-Object -Process {
    $InstalledModuleArray.Add($_) | Out-Null
}

[System.Int32]$InstalledModuleCount = $InstalledModuleArray.Count
[System.Int32]$i = 1
Write-Information -MessageData "Found: '$InstalledModuleCount' installed modules."

Write-Information -MessageData "Searching for and removing older duplicate versions."
foreach ($Module in $InstalledModuleArray) {
    [System.String]$ModuleName = $Module.Name
    Write-Information -MessageData "Getting newest installed version of module: '$ModuleName'. Module: '$i' of: '$InstalledModuleCount' modules."
    $GetNewestModule = Get-InstalledModule -Name $ModuleName
    $NewestModuleVersion = $GetNewestModule.Version

    Write-Information -MessageData "Getting all installed versions of module: '$ModuleName'."
    [System.Collections.ArrayList]$AllModuleVersionsArray = @()

    Get-InstalledModule -Name $ModuleName -AllVersions | Where-Object -FilterScript { $_.Version -ne $NewestModuleVersion } | ForEach-Object -Process {
        $AllModuleVersionsArray.Add($_) | Out-Null
    }

    [System.Int32]$AllModuleVersionsArrayCount = $AllModuleVersionsArray.Count
    [System.Int32]$c = 1
    if (1 -ge $AllModuleVersionsArrayCount) {
        Write-Information -MessageData "Only found one installed version of: '$ModuleName'."
    }
    else {
        Write-Information -MessageData "Testing if module: '$ModuleName' is in current session."
        if (Get-Module -Name $ModuleName) {
            try {
                $ErrorActionPreference = "Continue"
                Write-Information -MessageData "Removing module: '$ModuleName' from session."
                Remove-Module -Name $ModuleName -Force -ErrorAction "Continue"
            }
            catch {
                Write-Warning -Message "Could not remove module: '$ModuleName' from session. Moving on."
            }
        }
        else {
            Write-Information -MessageData "Module: '$ModuleName' is not in current session."
        }

        Write-Information -MessageData "Latest installed version of: '$ModuleName' is: '$NewestModuleVersion'."
        Write-Information -MessageData "Will remove: '$AllModuleVersionsArrayCount' older installed versions of: '$ModuleName'."
        foreach ($DuplicateModule in $AllModuleVersionsArray) {
            [System.String]$DuplicateModuleVersion = $DuplicateModule.Version
            if ($DuplicateModuleVersion -ne $NewestModuleVersion) {
                try {
                    $ErrorActionPreference = "Stop"

                    Write-Warning -Message "Uninstalling version: '$DuplicateModuleVersion'. Older version: '$c' of: '$AllModuleVersionsArrayCount' older versions."
                    $DuplicateModule | Uninstall-Module -Force
                    Write-Information -MessageData "Uninstalled version: '$DuplicateModuleVersion'."
                }
                catch {
                    $_
                    Write-Error -Message "There was an issue uninstalling version: '$DuplicateModuleVersion' of module: '$ModuleName'. Please try again."
                }
                $c++
            }
        }
        Write-Information -MessageData "All older versions of: '$ModuleName' uninstalled."
    }

    if ($i -ge $InstalledModuleCount) {
        Write-Information -MessageData ""
        Write-Information -MessageData "All older versions of modules uninstalled."
    }
    else {
        Write-Information -MessageData "Moving to next module."
    }
    $i++
}