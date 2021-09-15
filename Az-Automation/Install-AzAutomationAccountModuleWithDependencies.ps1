$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"
[System.Collections.ArrayList]$Modules = @("Az")

Write-Information -MessageData "Finding modules..."
[System.Int32]$c = 1
[System.Int32]$ModuleCount = $Modules.Count
foreach ($Module in $Modules) {
    Write-Information -MessageData "Working on module: '$Module'. Module: '$c' of: '$ModuleCount'."

    $FindModule = Find-Module -Name $Module

    [System.Collections.Hashtable]$ModuleDependencies = $FindModule.Dependencies

    if ($ModuleDependencies.Count -gt 0) {
        Write-Warning -Message "Module has dependencies. Getting those first."

        [System.Int32]$i = 1
        [System.Int32]$ModuleDependencyCount = $ModuleDependencies.Count
        foreach ($Dependency in $ModuleDependencies) {
            [System.String]$ModuleDependencyName = $Dependency.Name
            [System.String]$ModuleDependencySourceLocation = $Dependency.RepositorySourceLocation
            [System.String]$ModuleDependencyVersion = $Dependency.Version
            [System.String]$ModuleURI = [System.String]::Concat($ModuleDependencySourceLocation, "/package/", $ModuleDependencyName, "/", $ModuleDependencyVersion)
            Write-Information -MessageData "Working on module dependency: '$ModuleDependencyName'. Dependency: '$i' of: '$ModuleDependencyCount'."

            try {
                $ErrorActionPreference = "Stop"
                New-AzAutomationModule -ResourceGroupName $AutomationAccountResourceGroupName -AutomationAccountName $AutomationAccountName -Name $ModuleDependencyName -ContentLinkUri $ModuleURI
            }
            catch {
                $_
                throw
            }
        }
    }
    $c++
}

#necessary modules list
$deps1 = @("Az.Accounts", "Az.Storage", "Az.Compute")

foreach ($dep in $deps1) {
    $module = Find-Module -Name $dep
    $link = $module.RepositorySourceLocation + "/package/" + $module.Name + "/" + $module.Version
    New-AzAutomationModule -AutomationAccountName $AutomationAccountName -Name $module.Name -ContentLinkUri $link -ResourceGroupName $ResourceGroupName
    if ($dep -eq "Az.Accounts") {
        #Az.Accounts is a dependency for Az.Storage and Az.Compute modules
        Write-Host "Sleeping for 180 sec in order to wait the installation of the Az.Accounts module"
        Start-Sleep 180
    }
}