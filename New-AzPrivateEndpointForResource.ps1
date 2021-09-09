#Requires -Modules @{ ModuleName="Az.Network"; ModuleVersion="4.0.0.0"}, @{ ModuleName="Az.Resources"; ModuleVersion="3.0.0.0"}
<#
    .SYNOPSIS
    This script creates a private endpoint for a resource.

    .DESCRIPTION
    This script creates a private endpoint for a resource.

    .NOTES
    ###################################################################################################################
    Created With: Microsoft Visual Studio Code
    Created On: September 9, 2021
    Author: Scott Metzel
    Organization: -
    Filename: New-AzPrivateEndpointForResource.ps1

    Version History:
    ## Version ##   ## Edited By ## ## Date ##          ## Notes ######################################################
    0.1             Scott Metzel    September 7, 2021   Initial Version based on prior script
    ###################################################################################################################

    Reference articles:
    https://azure.microsoft.com/en-us/updates/public-preview-of-private-link-network-security-group-support/
    https://docs.microsoft.com/en-us/azure/private-link/create-private-endpoint-powershell
    https://docs.microsoft.com/en-us/azure/private-link/disable-private-endpoint-network-policy

    .EXAMPLE
    New-AzPrivateEndpointForResource.ps1 -VirtualNetworkName "VNETHub01" -VirtualNetworkSubnetName "StoragePE01" -TargetResourceID ""

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
        Mandatory = $true
    )]
    [ValidateScript(
        {
            (($_ -split "/").Count -eq 9) -and (($_ -split "/")[1] -eq "subscriptions") -and ([System.Guid]::TryParse(($_ -split "/")[2], [System.Management.Automation.PSReference]([System.Guid]::empty))) -and (($_ -split "/")[3] -eq "resourceGroups") -and (($_ -split "/")[5] -eq "providers")
        }
    )]
    [System.String]$TargetResourceID
)
## Get information stream messages to show, and make sure we stop on error
$InformationPreference = "Continue"
$ErrorActionPreference = "Stop"

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

## Get the Virtual Network subnet
Write-Information -MessageData "Getting Virtual Network subnet"
$GetAzVNetSubnet = $GetAzVNET.Subnets | Where-Object -FilterScript { $_.Name -eq $VirtualNetworkSubnetName }

# Get the resource to create a private endpoint for
Write-Information -MessageData "Getting the Azure resource to create a private endpoint for."
$GetAzResource = Get-AzResource -ResourceId $TargetResourceID

### Get the Group ID for the Azure resource, which we'll need shortly
Write-Information -MessageData "Getting the GroupId for the target Azure resource."
$GetAzResourceGroupID = (Get-AzPrivateLinkResource -PrivateLinkResourceId $GetAzResource.ResourceId).GroupId

### Create a name for the Private Link Service Connection based on the Azure resource name
[System.String]$NewAzPLSCName = [System.String]::Concat($GetAzResource.Name, "-PLSC-01")

### Parameter splat for the Private Link Service Connection cmdlet
[System.Collections.Hashtable]$NewAzPLSCSplat = @{
    Name                 = $NewAzPLSCName
    PrivateLinkServiceId = $GetAzResource.ResourceId
    GroupId              = $GetAzResourceGroupID
}

### Now create the Private Link Service Connection
Write-Information -MessageData "Creating the Private Link Service Connection"
$NewAzPLSC = New-AzPrivateLinkServiceConnection @NewAzPLSCSplat

### Create a name for the Private Endpoint Azure resource based on the target Azure resource name
[System.String]$NewAzPEName = [System.String]::Concat($GetAzResource.VaultName, "-PE-01")

### Parameter splat for the Private Endpoint cmdlet
$NewAzPESplat = @{
    ResourceGroupName            = $GetAzResource.ResourceGroupName
    Name                         = $NewAzPEName
    Location                     = $GetAzResource.Location
    Subnet                       = $GetAzVNetSubnet
    PrivateLinkServiceConnection = $NewAzPLSC
}

### Now create the Private Endpoint
Write-Information -MessageData "Creating the Private Endpoint"
New-AzPrivateEndpoint @NewAzPESplat