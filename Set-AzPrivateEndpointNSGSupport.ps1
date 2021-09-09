#Requires -Modules @{ ModuleName="Az.Network"; ModuleVersion="4.0.0.0"}, @{ ModuleName="Az.Resources"; ModuleVersion="3.0.0.0"}
<#
    .SYNOPSIS
    This script enables a subnet with private endpoints present to have traffic controlled by an Azure NSG

    .DESCRIPTION
    This script enables a subnet with private endpoints present to have traffic controlled by an Azure NSG.

    .NOTES
    ###################################################################################################################
    Created With: Microsoft Visual Studio Code
    Created On: September 9, 2021
    Author: Scott Metzel
    Organization: -
    Filename: Set-AzPrivateEndpointNSGSupport.ps1

    Version History:
    ## Version ##   ## Edited By ## ## Date ##          ## Notes ######################################################
    0.1             Scott Metzel    September 7, 2021   Initial Version
    0.2             Scott Metzel    September 9, 2021   Replaced notes block with something more formal.
                                                        Removed provider feature registration.
                                                        Added requires statement
                                                        Script now works with all Private Endpoint resources.
    ###################################################################################################################

    Reference articles:
    https://azure.microsoft.com/en-us/updates/public-preview-of-private-link-network-security-group-support/
    https://docs.microsoft.com/en-us/azure/private-link/create-private-endpoint-powershell
    https://docs.microsoft.com/en-us/azure/private-link/disable-private-endpoint-network-policy

    .EXAMPLE
    Set-AzPrivateEndpointNSGSupport.ps1 -VirtualNetworResourceID "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/Dev-RG-NetworkInfrastructure-01/providers/Microsoft.Network/virtualNetworks/Dev-VNET-Hub-01" -VirtualNetworkSubnetName "StoragePE01" -Operation "Enable"

    .INPUTS
    None. This runbook does not accept inputs from the pipeline.

    .OUTPUTS
    None.
#>
[CmdletBinding()]
param (
    [Parameter(
        Mandatory = $true
    )]
    [ValidateScript(
        {
            (($_ -split "/").Count -eq 9) -and (($_ -split "/")[1] -eq "subscriptions") -and ([System.Guid]::TryParse(($_ -split "/")[2], [System.Management.Automation.PSReference]([System.Guid]::empty))) -and (($_ -split "/")[3] -eq "resourceGroups") -and (($_ -split "/")[5] -eq "providers") -and (($_ -split "/")[6] -eq "Microsoft.Network") -and (($_ -split "/")[7] -eq "virtualNetworks")
        }
    )]
    [System.String]$VirtualNetworkResourceID,
    [Parameter(
        Mandatory = $true
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]$VirtualNetworkSubnetName,
    [Parameter(
        Mandatory = $false
    )]
    [ValidateSet(
        "Disable",
        "Enable",
        IgnoreCase = $true
    )]
    [System.String]$Operation = "Enable"
)
## Get information stream messages to show, and make sure we stop on error
$InformationPreference = "Continue"
$ErrorActionPreference = "Stop"

# Get the resource group name and name of the virtual network from the resource ID to reduce parameters / complexity
Write-Information -MessageData "Deriving Virtual Network name and resource group name."
[System.Collections.ArrayList]$VirtualNetworkResourceIDArray = $VirtualNetworkResourceID -split "/"
[System.String]$VirtualNetworkResourceGroupName = $VirtualNetworkResourceIDArray[4]
[System.String]$VirtualNetworkName = $VirtualNetworkResourceIDArray[-1]

## Parameter splat for the get virtual network cmdlet
[System.Collections.Hashtable]$GetAzVNETSplat = @{
    ResourceGroupName = $VirtualNetworkResourceGroupName
    Name              = $VirtualNetworkName
}

## Get the Virtual Network
Write-Information -MessageData "Getting Virtual Network"
$GetAzVNET = Get-AzVirtualNetwork @GetAzVNETSplat

## Enable Network Policies on all subnets in the Virtual Network
### Get the subnets where the PrivateEndpointNetworkPolicies property exists and where the subnet name matches the $VirtualNetworkSubnetName variable, then enable PrivateEndpoint Network Policies on the subnet object. The changes haven't been committed to the virtual network yet.

switch ($Operation) {
    "Disable" {
        Write-Information -MessageData "Modifying subnet object to disable private endpoint network policies"
        ($GetAzVNET.Subnets | Where-Object -FilterScript { ($_.Psobject.Properties.Name -eq 'PrivateEndpointNetworkPolicies') -and ($_.Name -eq $VirtualNetworkSubnetName) }) | ForEach-Object -Process {
            $_.PrivateEndpointNetworkPolicies = "Disabled"
        }
    }
    "Enable" {
        Write-Information -MessageData "Modifying subnet object to enable private endpoint network policies"
        ($GetAzVNET.Subnets | Where-Object -FilterScript { ($_.Psobject.Properties.Name -eq 'PrivateEndpointNetworkPolicies') -and ($_.Name -eq $VirtualNetworkSubnetName) }) | ForEach-Object -Process {
            $_.PrivateEndpointNetworkPolicies = "Enabled"
        }
    }
    default {
        Write-Error -Message "An unknown option was chosen"
    }
}

### Now commit the changes
Write-Information -MessageData "Committing changes to the virtual network"
$GetAzVNET | Set-AzVirtualNetwork | Out-Null

## Now get the virtual network and subnet again to show the changes have been committed
Write-Information -MessageData "Getting the virtual network again."
$GetAzVNET2 = Get-AzVirtualNetwork @GetAzVNETSplat
[System.String]$GetAzVNET2SubnetPENPState = ($GetAzVNET2.Subnets | Where-Object -FilterScript { ($_.Psobject.Properties.Name -eq 'PrivateEndpointNetworkPolicies') -and $_.Name -eq $VirtualNetworkSubnetName }).PrivateEndpointNetworkPolicies

[System.String]$MessageData = "The PrivateEndpointNetworkPolicies property of the subnet named: '$VirtualNetworkSubnetName' in the Virtual Network named: '$VirtualNetworkName' is set to: '$GetAzVNET2SubnetPENPState'"
Write-Information -MessageData $MessageData