#Requires -Modules @{ ModuleName="PowerShellGet"; ModuleVersion="2.0.0.0"}, @{ ModuleName="Az.Automation"; ModuleVersion="1.7.0.0"}
<#
    .SYNOPSIS
    This script adds PowerShell modules to an Azure Automation Account

    .DESCRIPTION
    This script adds PowerShell modules to an Azure Automation Account, optionally including dependencies. It can also
    be used to effectively update modules in an account, if modules are already present.

    .NOTES
    ###################################################################################################################
    Created With: Microsoft Visual Studio Code
    Created On: September 15, 2021
    Author: Scott Metzel
    Organization: -
    Filename: Install-AzAutomationAccountModuleWithDependencies.ps1

    Version History:
    ## Version ##   ## Edited By ## ## Date ##          ## Notes ######################################################
    0.1             Scott Metzel    September 15, 2021  Initial version
    ###################################################################################################################

    .EXAMPLE
    Install-AzAutomationAccountModuleWithDependencies.ps1 -ResourceGroupName "Prod-RG-Operations-01" -AutomationAccountName "Prod-AA-Operations-01" -ModuleNames "Az", "PowerCLI"

    .EXAMPLE
    Install-AzAutomationAccountModuleWithDependencies.ps1 -ResourceGroupName "Prod-RG-Operations-01" -AutomationAccountName "Prod-AA-Operations-01" -ModuleNames "Az", "PowerCLI" -DependenciesOnly $true

    .EXAMPLE
    Install-AzAutomationAccountModuleWithDependencies.ps1 -ResourceGroupName "Prod-RG-Operations-01" -AutomationAccountName "Prod-AA-Operations-01" -ModuleNames "Az", "PowerCLI" -SkipDependencies $true

    .INPUTS
    None. This runbook does not accept inputs from the pipeline.

    .OUTPUTS
    None.
#>
[CmdletBinding()]
param (
    [System.String]$ResourceGroupName,
    [System.String]$AutomationAccountName,
    [System.String[]]$ModuleNames = @("Az"),
    [System.Boolean]$DependenciesOnly = $false,
    [System.Boolean]$SkipDependencies = $false
)
$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"

[System.Int32]$c = 1
[System.Int32]$ModuleCount = $ModuleNames.Count

Write-Information -MessageData "Entering main module loop."
foreach ($Module in $ModuleNames) {
    Write-Information -MessageData "Working on module: '$Module'. Module: '$c' of: '$ModuleCount'."

    Write-Information -MessageData "Finding module: '$Module'."
    $FindModule = Find-Module -Name $Module

    if ($FindModule) {
        Write-Information -MessageData "Module found in gallery. Parsing version."
        $ModuleInGalleryVersion = $FindModule.Version
    }
    else {
        Write-Error -Message "Module: '$Module' not found in gallery."
        throw
    }

    if ($false -eq $SkipDependencies) {
        [System.Collections.ArrayList]$ModuleDependencies = @()

        $FindModule.Dependencies | Sort-Object -Property Name | ForEach-Object -Process {
            $ModuleDependencies.Add($_) | Out-Null
        }

        Write-Information -MessageData "Finding if module has dependencies."
        if ($ModuleDependencies.Count -gt 0) {
            Write-Warning -Message "Module has dependencies. Getting those first."

            [System.Int32]$i = 1
            [System.Int32]$ModuleDependencyCount = $ModuleDependencies.Count
            foreach ($Dependency in $ModuleDependencies) {
                [System.String]$ModuleDependencyName = $Dependency.Name
                Write-Information -MessageData "Working on module dependency: '$ModuleDependencyName'. Dependency: '$i' of: '$ModuleDependencyCount'."

                Write-Information -MessageData "Finding dependent module: '$ModuleDependencyName' in gallery."
                $FindDependendModule = Find-Module -Name $ModuleDependencyName

                if ($FindDependendModule) {
                    Write-Information -MessageData "Dependent module found in gallery. Parsing version."
                    $DepdendentModuleInGalleryVersion = $FindDependendModule.Version
                }
                else {
                    Write-Error -Message "Dependent module: '$ModuleDependencyName' not found in gallery."
                    throw
                }

                Write-Information -MessageData "Checking if dependent module exists in Automation Account."
                $GetDependentModuleInAA = Get-AzAutomationModule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $ModuleDependencyName -ErrorAction "SilentlyContinue"

                [System.Boolean]$InstallDependentModule = $false
                if ($GetDependentModuleInAA) {
                    Write-Information -MessageData "Dependent module found in Automation Account."

                    if ($GetDependentModuleInAA.ProvisioningState -in @("Failed")) {
                        Write-Warning -Message "Found module is in failed state in Automation Account. Will attempt to reinstall."
                        [System.Boolean]$InstallDependentModule = $true
                    }
                    else {
                        Write-Information -MessageData "Parsing version of module in Automation Account."
                        [System.Version]$DependentModuleinAAVersion = [System.Version]::Parse($GetDependentModuleInAA.Version)

                        if ($DepdendentModuleInGalleryVersion -gt $DependentModuleinAAVersion) {
                            Write-Information -MessageData "Version found in gallery: '$DepdendentModuleInGalleryVersion' is higher than the one already in the Automation Account: '$DependentModuleinAAVersion'."
                            [System.Boolean]$InstallDependentModule = $true
                        }
                        else {
                            Write-Information -MessageData "Version found in gallery: '$DepdendentModuleInGalleryVersion' is not higher than the one already in the Automation Account: '$DependentModuleinAAVersion'."
                            [System.Boolean]$InstallDependentModule = $false
                        }
                    }
                }
                else {
                    Write-Information -MessageData "Dependent module not found in Automation Account."
                    [System.Boolean]$InstallDependentModule = $true
                }

                if ($InstallDependentModule) {
                    Write-Information -MessageData "Will install dependent module: '$ModuleDependencyName' in Automation Account."
                    [System.String]$ModuleDependencySourceLocation = $FindDependendModule.RepositorySourceLocation
                    [System.String]$ModuleDependencyVersion = $FindDependendModule.Version
                    [System.String]$ModuleDependencyURI = [System.String]::Concat($ModuleDependencySourceLocation, "/package/", $ModuleDependencyName, "/", $ModuleDependencyVersion)

                    try {
                        $ErrorActionPreference = "Stop"
                        Write-Information -MessageData "Installing dependent module."
                        New-AzAutomationModule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $ModuleDependencyName -ContentLinkUri $ModuleDependencyURI

                        # Set a counter for reinstallation attempts. If the counter goes above a value, bail.
                        [System.Int32]$r = 1
                        [System.Int32]$rMax = 5
                        Write-Information -MessageData "Checking module dependency installation state."
                        do {
                            $GetAzAutomationModuleDependencyInAccount = Get-AzAutomationModule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $ModuleDependencyName -ErrorAction SilentlyContinue

                            [System.String]$ModuleDependencyProvisioningState = $GetAzAutomationModuleDependencyInAccount.ProvisioningState
                            [System.Boolean]$ModuleDependencyInstalled = $false

                            if ($r -gt $rMax) {
                                Write-Error -Message "Module dependency: '$ModuleDependencyName' has failed to install: '$r' times, which is greater than the limit of: '$rMax'. Please investigate and try again."
                                throw
                            }

                            if ($ModuleDependencyProvisioningState -notin @("Created", "Succeeded")) {
                                Write-Information -MessageData "Module dependency: '$ModuleDependencyName' is not installed. State: '$ModuleDependencyProvisioningState'. Rechecking in 5 seconds."
                                [System.Boolean]$ModuleDependencyInstalled = $false
                                Start-Sleep -Seconds 5
                            }
                            elseif ($ModuleDependencyProvisioningState -in @("Failed")) {
                                Write-Warning -Message "Found module is in failed state in Automation Account. Will attempt to reinstall. Reinstall attempt: '$r' of: '$rMax'."
                                New-AzAutomationModule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $ModuleDependencyName -ContentLinkUri $ModuleDependencyURI

                                $r++
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
                }
                else {
                    Write-Information -MessageData "Not installing dependent module. Moving to next dependent module or parent module."
                }

                $i++
            }
        }
    }
    else {
        Write-Information -MessageData "Skipping dependencies."
    }

    if ($false -eq $DependenciesOnly) {
        Write-Information -MessageData "Checking if module exists in Automation Account."
        $GetModuleInAA = Get-AzAutomationModule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $Module -ErrorAction "SilentlyContinue"

        [System.Boolean]$InstallModule = $false
        if ($GetModuleInAA) {
            Write-Information -MessageData "Module found in Automation Account. Parsing version."
            [System.Version]$ModuleinAAVersion = [System.Version]::Parse($GetModuleInAA.Version)

            if ($ModuleInGalleryVersion -gt $ModuleinAAVersion) {
                Write-Information -MessageData "Version found in gallery: '$ModuleInGalleryVersion' is higher than the one already in the Automation Account: '$ModuleinAAVersion'."
                [System.Boolean]$InstallModule = $true
            }
            else {
                Write-Information -MessageData "Version found in gallery: '$ModuleInGalleryVersion' is not higher than the one already in the Automation Account: '$ModuleinAAVersion'."
                [System.Boolean]$InstallModule = $false
            }
        }
        else {
            Write-Information -MessageData "Module not found in Automation Account."
            [System.Boolean]$InstallModule = $true
        }

        # Now install the module
        if ($InstallModule) {
            Write-Information -MessageData "Will install module: '$Module' in Automation Account."

            [System.String]$ModuleName = $FindModule.Name
            [System.String]$ModuleSourceLocation = $FindModule.RepositorySourceLocation
            [System.String]$ModuleVersion = $FindModule.Version
            [System.String]$ModuleURI = [System.String]::Concat($ModuleSourceLocation, "/package/", $ModuleName, "/", $ModuleVersion)
            try {
                $ErrorActionPreference = "Stop"

                Write-Information -MessageData "Installing module: '$Module'. Module: '$c' of: '$ModuleCount'."
                New-AzAutomationModule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $ModuleName -ContentLinkUri $ModuleURI

                # Set a counter for reinstallation attempts. If the counter goes above a value, bail.
                [System.Int32]$r = 1
                [System.Int32]$rMax = 5

                Write-Information -MessageData "Checking module installation state."
                do {
                    $GetAzAutomationModuleInAccount = Get-AzAutomationModule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $ModuleName -ErrorAction SilentlyContinue

                    [System.String]$ModuleProvisioningState = $GetAzAutomationModuleInAccount.ProvisioningState
                    [System.Boolean]$ModuleInstalled = $false

                    if ($r -gt $rMax) {
                        Write-Error -Message "Module: '$ModuleName' has failed to install: '$r' times, which is greater than the limit of: '$rMax'. Please investigate and try again."
                        throw
                    }

                    if ($ModuleProvisioningState -notin @("Created", "Succeeded")) {
                        Write-Information -MessageData "Module: '$ModuleName' is not installed. State: '$ModuleProvisioningState'. Rechecking in 5 seconds."
                        [System.Boolean]$ModuleInstalled = $false
                        Start-Sleep -Seconds 5
                    }
                    elseif ($ModuleProvisioningState -in @("Failed")) {
                        Write-Warning -Message "Found module is in failed state in Automation Account. Will attempt to reinstall. Reinstall attempt: '$r' of: '$rMax'."
                        New-AzAutomationModule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $ModuleName -ContentLinkUri $ModuleURI

                        $r++
                    }
                    else {
                        Write-Information -MessageData "Module: '$ModuleName' is installed. State: '$ModuleProvisioningState'. Moving to next module or exiting."

                        [System.Boolean]$ModuleInstalled = $true
                    }

                } while ($false -eq $ModuleInstalled)
            }
            catch {
                $_
                throw
            }

        }
        else {
            Write-Information -MessageData "Not installing module. Moving to next parent module or exiting."
        }
    }
    else {
        Write-Information -MessageData "Skipping parent module installation."
    }

    $c++
}