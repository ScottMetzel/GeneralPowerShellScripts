<#
.NOTES
===========================================================================
Created With:   Visual Studio Code
Created On:     September 8, 2021, 8:31 AM
Created by:     Scott Metzel
Organization:   -
Filename:       Install-SyslogForwarderUpdatesInVMSS.ps1
Version:        0.1
===========================================================================
.DESCRIPTION
A description of the file.
#>

param (
    [System.String]$SubscriptionID,
    [System.String]$ResourceGroupName,
    [System.String]$VMSSName,
    [Parameter(
        Mandatory = $false
    )]
    [ValidateSet(
        "All",
        "FirstHalf",
        "LastHalf",
        IgnoreCase = $true
    )]
    [System.String]$UpdateStrategy = "All"
)

$InformationPreference = "Continue"
$ErrorActionPreference = "Stop"

Write-Verbose -Message "Getting Automation Connection."
$GetAutomationConnection = Get-AutomationConnection -Name AzureRunAsConnection
$TenantID = $GetAutomationConnection.TenantID
$ApplicationID = $GetAutomationConnection.ApplicationID
$CertificateThumbprint = $GetAutomationConnection.CertificateThumbprint

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

# Connect to Azure
Write-Verbose -Message "Connecting to Azure."
Connect-AzAccount -ServicePrincipal -Tenant $TenantID -ApplicationId $ApplicationID -CertificateThumbprint $CertificateThumbprint -Verbose

# Get the subscription and set context
Get-AzSubscription -SubscriptionId $SubscriptionID | Set-AzContext

# Create a new array to store the VMSS instances in
[System.Collections.ArrayList]$VMSSInstances = @()

# Get the VMSS Instances
Write-Verbose -Message "Getting VMSS Instances"
Get-AzVmssVM -ResourceGroupName $ResourceGroupName -VMScaleSetName $VMSSName | ForEach-Object -Process {
    $VMSSInstances.Add($_) | Out-Null
}

Write-Verbose -Message "Getting count of VMSS VMs"
[System.Int32]$VMSSInstanceCount = $VMSSInstances.Count

Write-Verbose -Message "Found: '$VMSSInstanceCount' VMSS VMs."

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

<#
    Now with the selected instances identified, start updating depending on our approach.
#>
Write-Verbose -Message "Will update instances from set in Resource Group: '$ResourceGroupName' and VMSS: '$VMSSName'"
$VMSSInstancesToUpdate | ForEach-Object -Process {
    [System.String]$InstanceName = $_.name

    Write-Verbose -Message "$InstanceName"
}

# Create a simple counter and get the total count of instances to update
[System.Int32]$c = 1
[System.Int32]$VMSSInstancesToUpdateCount = $VMSSInstancesToUpdate.Count

# Define the script to run as a string
[System.String]$ScriptToRun = "sudo firewall-cmd --remove-service=syslog&&sudo yum update -y&&nohup sudo shutdown -r 1 > /dev/null 2>&1 &"

# Temporarily write out the script to a file
Write-Verbose -Message "Temporarily writing script out to a path."
[System.String]$ScriptName = "Install-Updates.sh"
[System.String]$ScriptPath = [System.String]::Concat(".\", $ScriptName)
$ScriptToRun | Out-File -FilePath $ScriptPath -Encoding utf8 -Force

# Now start invoking the commands
Write-Verbose -Message "Updating VMSS instances..."
foreach ($Instance in $VMSSInstancesToUpdate) {
    try {
        $ErrorActionPreference = "Stop"
        [System.String]$InstanceName = $Instance.name
        Write-Verbose -Message "Updating instance: '$InstanceName'. Number: '$c' of: '$VMSSInstancesToUpdateCount' instances."
        Invoke-AzVmssVMRunCommand -VirtualMachineScaleSetVM $Instance -CommandId "RunShellScript" -ScriptPath $ScriptPath

        $c++
    }
    catch {
        $_
        Write-Error -Message "There was an error executing the command on one or more VMSS instances."

        # Remove the temporarily written script from the file system on error.
        Remove-Item -Path $ScriptPath -Force
        throw
    }
}

Write-Verbose -Message "All done!"

# Remove the temporarily written script from the file system on completion.
Remove-Item -Path $ScriptPath -Force