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
    Filename: New-AzPrivateEndPointWithNSGs.ps1

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
    New-AzPrivateEndPointWithNSGs.ps1 -VirtualNetworkName "VNETHub01" -VirtualNetworkSubnetName "StoragePE01" -TargetResourceID ""

    .INPUTS
    None. This runbook does not accept inputs from the pipeline.

    .OUTPUTS
    None.
#>

param (
    [System.String]$VirtualNetworkResourceGroupName,
    [System.String]$VirtualNetworkName,
    [System.String]$VirtualNetworkSubnetName
)
## Get information stream messages to show, and make sure we stop on error
$InformationPreference = "Continue"
$ErrorActionPreference = "Stop"

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
Write-Information -MessageData "Modifying subnet object to enable private endpoint network policies"
($GetAzVNET.Subnets | Where-Object -FilterScript { ($_.Psobject.Properties.Name -eq 'PrivateEndpointNetworkPolicies') -and ($_.Name -eq $VirtualNetworkSubnetName) }) | ForEach-Object -Process {
    $_.PrivateEndpointNetworkPolicies = "Enabled"
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