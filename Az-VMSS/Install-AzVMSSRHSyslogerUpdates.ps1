#Requires -Modules @{ ModuleName="Az.Accounts"; ModuleVersion="2.5.0.0"}, @{ ModuleName="Az.Compute"; ModuleVersion="4.17.0.0"}
<#
    .SYNOPSIS
    This runbook installs updates on Azure Virtual Machine Scale Sets which are running RedHat Linux

    .DESCRIPTION
    This runbook installs updates on Azure Virtual Machine Scale Sets which are running RedHat Linux (e.g., RedHat
    Enterprise Linux aka "RHEL"). It does this by running 'yum update' on all or some Azure VM Scale Set instances.
    The runbook is designed to work with Scale Set instances which have been configured as Syslog forwarders, which
    should be listening on port 514 TCP.

    This runbook is designed to run as a runbook in an Azure Automation Account however, it can be run as a script
    if 'Script' is supplied as the value for the 'RunMethod' parameter. Supplying 'RunAs' indicates the runbook
    will try to connect to the Azure Resource Manager using a Service Principal, aka a 'Run As' account. Specifying
    'ManagedIdentity' indicates it will try connecting using the newer Managed Identity feature, which is in preview
    as of this writing.

    As mentioned, the runbook can install updates on all or some VM Scale Set instances. The behavior is driven by
    supplying different parameter values for the 'UpdateStrategy' parameter. The runbook always takes a conservative
    approach to running commands on scale set instances; if a VMSS has 3 nodes, and 'FirstHalf' is supplied as the
    parameter value for the 'UpdateStrategy' parameter, only the first node will have commands run on it. Meanwhile,
    using this same scenario, supplying 'LastHalf' will run commands on the other 2 nodes.

    .NOTES
    ###################################################################################################################
    Created With:   Microsoft Visual Studio Code
    Created On:     September 8, 2021
    Author:         Scott Metzel
    Organization:   -
    Filename:       Install-AzVMSSRHSyslogerUpdates.ps1

    Version History:
    ## Version ##   ## Edited By ## ## Date ##          ## Notes ######################################################
    0.1             Scott Metzel    September 8, 2021  Initial version
    ###################################################################################################################

    .EXAMPLE
    Install-AzVMSSRHSyslogerUpdates.ps1 -SubscriptionID "00000000-0000-0000-0000-000000000000" -ResourceGroupName "Prod-RG-SyslogForwarders-01" -VMSSNames "Prod-VMSS-SyslogForwarders-01"

    .EXAMPLE
    Install-AzVMSSRHSyslogerUpdates.ps1 -SubscriptionID "00000000-0000-0000-0000-000000000000" -ResourceGroupName "Prod-RG-SyslogForwarders-01" -VMSSNames "Prod-VMSS-SyslogForwarders-01" -UpdateStrategy "FirstHalf"

    .EXAMPLE
    Install-AzVMSSRHSyslogerUpdates.ps1 -SubscriptionID "00000000-0000-0000-0000-000000000000" -ResourceGroupName "Prod-RG-SyslogForwarders-01" -VMSSNames "Prod-VMSS-SyslogForwarders-01" -UpdateStrategy "LastHalf"

    .EXAMPLE
    Install-AzVMSSRHSyslogerUpdates.ps1 -SubscriptionID "00000000-0000-0000-0000-000000000000" -ResourceGroupName "Prod-RG-SyslogForwarders-01" -VMSSNames "Prod-VMSS-SyslogForwarders-01", "Prod-VMSS-SyslogForwarders-02" -UpdateStrategy "FirstHalf" -RunMethod "Script"

    .INPUTS
    None. This runbook does not accept inputs from the pipeline.

    .OUTPUTS
    None.
#>

param (
    [Parameter(
        Mandatory = $true
    )]
    [ValidateScript(
        {
            [System.Guid]::Parse($_)
        }
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]$SubscriptionID,
    [Parameter(
        Mandatory = $true
    )]
    [ValidateLength(
        1,
        90
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]$ResourceGroupName,
    [Parameter(
        Mandatory = $true
    )]
    [ValidateScript(
        {
            $_ | ForEach-Object -Process {
                if (($_.Length -lt 1) -or ($_.Length -gt 64)) {
                    $false
                }
                else {
                    $true
                }
            }
        }
    )]
    [ValidateNotNullOrEmpty()]
    [System.String[]]$VMSSNames,
    [Parameter(
        Mandatory = $false
    )]
    [ValidateSet(
        "All",
        "FirstHalf",
        "LastHalf",
        IgnoreCase = $true
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]$UpdateStrategy = "All",
    [Parameter(
        Mandatory = $false
    )]
    [ValidateSet(
        "ManagedIdentity",
        "RunAs",
        "Script",
        IgnoreCase = $true
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]$RunMethod = "ManagedIdentity"
)

$InformationPreference = "Continue"
$ErrorActionPreference = "Stop"

# Import modules while suppressing verbose output
[System.Collections.ArrayList]$ModulesToImport = @(
    "Az.Accounts",
    "Az.Compute"
)

[System.Int32]$c = 1
[System.Int32]$ModulesToImportCount = $ModulesToImport.Count
foreach ($Module in $ModulesToImport) {
    Write-Verbose -Message "Importing module: '$Module'. Module: '$c' of: '$ModulesToImportCount'."

    $OriginalVerbosePreference = $Global:VerbosePreference
    $Global:VerbosePreference = 'SilentlyContinue'

    Get-Module -Name $Module -ListAvailable | Import-Module | Out-Null

    $Global:VerbosePreference = $OriginalVerbosePreference
    $c++
}

# Connect to Azure depending on the run method
switch ($RunMethod) {
    "ManagedIdentity" {
        Write-Verbose -Message "Connecting to Azure using a Managed Identity"
        Connect-AzAccount -Identity
    }
    "RunAs" {
        Write-Verbose -Message "Will connect to Azure using a Service Principal."

        Write-Verbose -Message "Getting Automation Connection."
        $GetAutomationConnection = Get-AutomationConnection -Name AzureRunAsConnection
        $TenantID = $GetAutomationConnection.TenantID
        $ApplicationID = $GetAutomationConnection.ApplicationID
        $CertificateThumbprint = $GetAutomationConnection.CertificateThumbprint

        Write-Verbose -Message "Connecting to Azure using a Service Principal."
        Connect-AzAccount -ServicePrincipal -Tenant $TenantID -ApplicationId $ApplicationID -CertificateThumbprint $CertificateThumbprint -Verbose
    }
    "Script" {
        Write-Verbose -Message "Not connecting to Azure since this is being run via a script. Assuming connectivity."
    }
    default {
        Write-Error -Message "Unknown connection method specified."
        throw
    }
}

# Get the subscription and set context
Get-AzSubscription -SubscriptionId $SubscriptionID | Set-AzContext

# Setup basic counters
[System.Int32]$c = 1
[System.Int32]$VMSSCount = $VMSSNames.Count

# Enter the VMSS loop for running the command across multiple scale sets in the same resource group.
Write-Verbose -Message "Entering main VMSS instance loop."
foreach ($VMSSName in $VMSSNames) {
    Write-Verbose -Message "Working on VMSS: '$VMSSName'. Set: '$c' of: '$VMSSCount'."
    # Create a new array to store the VMSS instances in
    [System.Collections.ArrayList]$VMSSInstances = @()

    # Get the VMSS instances
    Write-Verbose -Message "Getting instances in VMSS."
    Get-AzVmssVM -ResourceGroupName $ResourceGroupName -VMScaleSetName $VMSSName | ForEach-Object -Process {
        $VMSSInstances.Add($_) | Out-Null
    }

    Write-Verbose -Message "Getting count of instances in set."
    [System.Int32]$VMSSInstanceCount = $VMSSInstances.Count

    Write-Verbose -Message "Found: '$VMSSInstanceCount' instances in set."

    # Find the first half of the set
    [System.Int32]$VMSSInstanceCountFirstHalf = [math]::floor(($VMSSInstanceCount * 0.5))

    # Create a new array to store the objects of the first half of the array
    [System.Collections.ArrayList]$VMSSInstancesToUpdate = @()

    switch ($UpdateStrategy) {
        "All" {
            Write-Verbose -Message "Update strategy: ""All"" selected."
            # Since we're patching everything, the selected count equals the count of instances
            [System.Int32]$SelectedVMSSInstanceCount = $VMSSInstanceCount

            # Now select the last half of the original array and add it to the new array
            $VMSSInstances | ForEach-Object -Process {
                $VMSSInstancesToUpdate.Add($_) | Out-Null
            }
        }
        "FirstHalf" {
            Write-Verbose -Message "Update strategy: ""FirstHalf"" selected."
            if ($VMSSInstanceCountFirstHalf -le 0) {
                <#
                If the calculated first half of the VMSS is 0, we know we have 1 instance in the set,
                so the first half equals the count of the whole set
            #>
                [System.Int32]$SelectedVMSSInstanceCount = $VMSSInstanceCount
            }
            else {
                # Otherwise, the halfway mark equals the calculated first half
                [System.Int32]$SelectedVMSSInstanceCount = $VMSSInstanceCountFirstHalf
            }
            # Now select the first half of the original array and add it to the new array
            $VMSSInstances | Select-Object -First $SelectedVMSSInstanceCount | ForEach-Object -Process {
                $VMSSInstancesToUpdate.Add($_) | Out-Null
            }
        }
        "LastHalf" {
            Write-Verbose -Message "Update strategy: ""LastHalf"" selected."

            if ($VMSSInstanceCountFirstHalf -le 0) {
                <#
                Like before, if the calculated first half of the VMSS is less than or equal to 0, we know we have 1
                instance in the set, since 1 times 0.5 and rounded down equals 0, so the first half equals the count of the whole set
            #>
                [System.Int32]$SelectedVMSSInstanceCount = $VMSSInstanceCount
            }
            else {
                <#
                Otherwise, since we're being conservative about finding the halfway mark, and so we don't leave
                out any instances which might be in the middle of the array and left behind, the last half should
                equal the total count of instances minus the first half
            #>
                [System.Int32]$SelectedVMSSInstanceCount = $VMSSInstanceCount - $VMSSInstanceCountFirstHalf
            }

            # Now select the last half of the original array and add it to the new array
            $VMSSInstances | Select-Object -Last $SelectedVMSSInstanceCount | ForEach-Object -Process {
                $VMSSInstancesToUpdate.Add($_) | Out-Null
            }
        }
        default {
            Write-Error -Message "Unknown update strategy selected."
            throw
        }
    }

    # Now with the selected instances identified, start updating depending on our approach.

    Write-Verbose -Message "Will update the following instances from set in Resource Group: '$ResourceGroupName' and VMSS: '$VMSSName'"
    $VMSSInstancesToUpdate | ForEach-Object -Process {
        [System.String]$InstanceName = $_.name

        Write-Verbose -Message "$InstanceName"
    }

    # Create a simple counter and get the total count of instances to update
    [System.Int32]$i = 1
    [System.Int32]$VMSSInstancesToUpdateCount = $VMSSInstancesToUpdate.Count

    # Define the script to run as a string
    [System.String]$ScriptToRun = "sudo firewall-cmd --remove-service=syslog&&sudo yum update -y&&nohup sudo shutdown -r 1 > /dev/null 2>&1 &"

    # Temporarily write out the script to a file

    [System.String]$ScriptName = "Install-Updates.sh"
    [System.String]$ScriptPath = [System.String]::Concat(".\", $ScriptName)
    Write-Verbose -Message "Temporarily writing shell commands out to a shell script at path: '$ScriptPath'."
    $ScriptToRun | Out-File -FilePath $ScriptPath -Encoding utf8 -Force

    # Test the path to the script
    if (Test-Path -Path $ScriptPath) {
        Write-Verbose -Message "Script at path: '$ScriptPath' found."
    }
    else {
        Write-Error -Message "Script at path: '$ScriptPath' not found. Please check values and try again."
        throw
    }

    # Now start invoking the commands
    Write-Verbose -Message "Updating VMSS instances..."
    foreach ($Instance in $VMSSInstancesToUpdate) {
        try {
            $ErrorActionPreference = "Continue"
            [System.String]$InstanceName = $Instance.name
            Write-Verbose -Message "Updating instance: '$InstanceName'. Number: '$i' of: '$VMSSInstancesToUpdateCount' instances."
            Invoke-AzVmssVMRunCommand -VirtualMachineScaleSetVM $Instance -CommandId "RunShellScript" -ScriptPath $ScriptPath

            $i++
        }
        catch {
            $_
            Write-Warning -Message "There was an error executing the command on instance: '$InstanceName' of VMSS: '$VMSSName'."
        }
    }

    if ($c -ge $VMSSCount) {
        Write-Verbose -Message "Exiting VMSS loop."
    }
    else {
        Write-Verbose -Message "Moving on to next VMSS."
    }

    $c++
}

Write-Verbose -Message "All done!"

# Remove the temporarily written script from the file system on completion if found.
if (Test-Path -Path $ScriptPath) {
    Write-Verbose -Message "Removing temporary shell script at path: '$ScriptPath'."
    Remove-Item -Path $ScriptPath -Force
}
else {
    Write-Information -MessageData "Script at path: '$ScriptPath' not found. Moving on."
}

Write-Verbose -Message "Exiting runbook."