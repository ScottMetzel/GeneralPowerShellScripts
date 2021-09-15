param (
    [System.String]$AutomationAccountResourceGroupName,
    [System.String]$AutomationAccountName,
    [System.String[]]$Modules = @("Az")
)
$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"

Write-Information -MessageData "Finding modules..."
[System.Int32]$c = 1
[System.Int32]$ModuleCount = $Modules.Count
foreach ($Module in $Modules) {
    Write-Information -MessageData "Working on module: '$Module'. Module: '$c' of: '$ModuleCount'."

    $FindModule = Find-Module -Name $Module


    [System.Collections.ArrayList]$ModuleDependencies = @()

    $FindModule.Dependencies | ForEach-Object -Process {
        $ModuleDependencies.Add($_) | Out-Null
    }

    Write-Information -MessageData "Finding if module has dependencies."
    if ($ModuleDependencies.Count -gt 0) {
        Write-Warning -Message "Module has dependencies. Getting those first."

        [System.Int32]$i = 1
        [System.Int32]$ModuleDependencyCount = $ModuleDependencies.Count
        foreach ($Dependency in $ModuleDependencies) {
            [System.String]$ModuleDependencyName = $Dependency.Name
            Write-Information -MessageData "Finding dependent module: '$ModuleDependencyName'."
            $FindDependendModule = Find-Module -Name $ModuleDependencyName

            [System.String]$ModuleDependencySourceLocation = $FindDependendModule.RepositorySourceLocation
            [System.String]$ModuleDependencyVersion = $FindDependendModule.Version
            [System.String]$ModuleDependencyURI = [System.String]::Concat($ModuleDependencySourceLocation, "/package/", $ModuleDependencyName, "/", $ModuleDependencyVersion)
            Write-Information -MessageData "Working on module dependency: '$ModuleDependencyName'. Dependency: '$i' of: '$ModuleDependencyCount'."

            try {
                $ErrorActionPreference = "Stop"
                New-AzAutomationModule -ResourceGroupName $AutomationAccountResourceGroupName -AutomationAccountName $AutomationAccountName -Name $ModuleDependencyName -ContentLinkUri $ModuleDependencyURI

                Write-Information -MessageData "Checking module dependency installation state."
                do {
                    $GetAzAutomationModuleDependencyInAccount = Get-AzAutomationModule -ResourceGroupName $AutomationAccountResourceGroupName -AutomationAccountName $AutomationAccountName -Name $ModuleDependencyName -ErrorAction SilentlyContinue

                    [System.String]$ModuleDependencyProvisioningState = $GetAzAutomationModuleDependencyInAccount.ProvisioningState

                    [System.Boolean]$ModuleDependencyInstalled = $false
                    if ($ModuleDependencyProvisioningState -notin @("Created", "Succeeded")) {
                        Write-Information -MessageData "Module dependency: '$ModuleDependencyName' is not installed. State: '$ModuleDependencyProvisioningState'. Rechecking in 5 seconds."
                        [System.Boolean]$ModuleDependencyInstalled = $false
                        Start-Sleep -Seconds 5
                    }
                    else {
                        Write-Information -MessageData "Module dependency: '$ModuleDependencyName' is installed. State: '$ModuleDependencyProvisioningState'. Moving to next module dependency."

                        [System.Boolean]$ModuleDependencyInstalled = $true
                    }

                } while ($false -eq $ModuleDependencyInstalled)
            }
            catch {
                $_
                throw
            }

            $i++
        }
    }

    # Now install the module
    [System.String]$ModuleName = $Dependency.Name
    [System.String]$ModuleSourceLocation = $Dependency.RepositorySourceLocation
    [System.String]$ModuleVersion = $Dependency.Version
    [System.String]$ModuleURI = [System.String]::Concat($ModuleSourceLocation, "/package/", $ModuleName, "/", $ModuleVersion)
    Write-Information -MessageData "Installing module: '$Module'. Module: '$c' of: '$ModuleCount'."
    New-AzAutomationModule -ResourceGroupName $AutomationAccountResourceGroupName -AutomationAccountName $AutomationAccountName -Name $ModuleName -ContentLinkUri $ModuleURI
    $c++
}