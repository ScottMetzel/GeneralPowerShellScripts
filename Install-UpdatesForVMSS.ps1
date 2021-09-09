<#
.NOTES
===========================================================================
Created With:   Visual Studio Code
Created On:     September 8, 2021, 8:31 AM
Created by:     Scott Metzel
Organization:   -
Filename:       Install-UpdatesForVMSS.ps1
Version:        0.1
===========================================================================
.DESCRIPTION
A description of the file.
#>
param (
    [System.String]$SubscriptionID,
    [System.String]$ResourceGroupName,
    [System.String]$VMSSName,
    [System.Boolean]$Reboot = $true
)

$GetAutomationConnection = Get-AutomationConnection -Name AzureRunAsConnection
$TenantID = $GetAutomationConnection.$TenantID
$ApplicationID = $GetAutomationConnection.$ApplicationID
$CertificateThumbprint = $GetAutomationConnection.CertificateThumbprint

# Connect to Azure
Connect-AzAccount -ServicePrincipal -Tenant $TenantID -ApplicationId $ApplicationID -CertificateThumbprint $CertificateThumbprint -Verbose

# Get the subscription and set context
Get-AzSubscription -SubscriptionId $SubscriptionID | Set-AzContext

# Find the VMSS
$GetVMSS = Get-AzVmss -ResourceGroupName $ResourceGroupName -VMScaleSetName $VMSSName

# Specify settings
[System.String]$VMSSExtensionPublisherName = "Microsoft.Azure.Extensions"
[System.String]$VMSSExtensionName = "VMSS-CS"
[System.String]$VMSSExtensionType = "CustomScript"
[System.String]$VMSSExtensionTypeHandlerVersion = "2.1"
[System.String]$CommandToExecute = "sudo yum update -y"
[System.String]$VMSSExtensionSettings = @{"commandToExecute" = $CommandToExecute };

# Add / Run the Custom Script Extension
Add-AzVmssExtension -VirtualMachineScaleSet $GetVMSS -Name $VMSSExtensionName -Publisher $VMSSExtensionPublisherName  `
    -Type $vmssExtensionType -TypeHandlerVersion $VMSSExtensionTypeHandlerVersion -AutoUpgradeMinorVersion $true  `
    -Setting $VMSSExtensionSettings