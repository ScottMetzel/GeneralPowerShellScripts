<#
    v0.1 - Initial version

    Inspired by:
    https://azure.microsoft.com/en-us/updates/public-preview-of-private-link-network-security-group-support/
    https://docs.microsoft.com/en-us/azure/private-link/create-private-endpoint-powershell
    https://docs.microsoft.com/en-us/azure/private-link/disable-private-endpoint-network-policy
#>

param (
    [System.String]$VirtualNetworkName = "Dev-VNET-Hub-01",
    [System.String]$VirtualNetworkSubnetName = "PL-KeyVault01",
    [System.String]$KeyVaultName = "Dev-KV-ADDS-01"
)
## Get information stream messages to show, and make sure we stop on error
$InformationPreference = "Continue"
$ErrorActionPreference = "Stop"

## Get the Preview Feature state
$GetAzProviderFeature = Get-AzProviderFeature -ProviderNamespace "Microsoft.Network" -FeatureName "AllowPrivateEndpointNSG"
[System.String]$AzProviderFeatureRegistrationState = $GetAzProviderFeature.RegistrationState

## Register for it if not registered
if ("NotRegistered" -eq $AzProviderFeatureRegistrationState) {
    Write-Information -MessageData "Preview Feature state is: '$AzProviderFeatureRegistrationState'. Registering."
    Register-AzProviderFeature -ProviderNamespace "Microsoft.Network" -FeatureName "AllowPrivateEndpointNSG"
}
elseif ("Pending" -eq $AzProviderFeatureRegistrationState) {
    Write-Warning -Message "Preview Feature state is: '$AzProviderFeatureRegistrationState'. Please try again in a bit."
    throw
}
else {
    Write-Information -MessageData "Preview Feature state is: '$AzProviderFeatureRegistrationState'. Skipping registration."
}

######## Loop until the preview feature is registered
do {
    Write-Information -MessageData "Checking preview feature registration state again..."
    $GetAzProviderFeatureAgain = Get-AzProviderFeature -ProviderNamespace "Microsoft.Network" -FeatureName "AllowPrivateEndpointNSG"
    [System.String]$AzProviderFeatureRegistrationStateAgain = $GetAzProviderFeatureAgain.RegistrationState
    Write-Information -MessageData "Preview Feature state is: '$AzProviderFeatureRegistrationState'"

    if ("Registered" -ne $AzProviderFeatureRegistrationStateAgain) {
        Write-Information -MessageData "Preview Feature registration state is not 'Registered'. Waiting for 5 seconds..."
        Start-Sleep -Seconds 5
    }

} while ("Registered" -ne $AzProviderFeatureRegistrationStateAgain)
######## End Loop

## Parameter splat for the get virtual network cmdlet
[System.Collections.Hashtable]$GetAzVNETSplat = @{
    Name = $VirtualNetworkName
}

## Get the Virtual Network
Write-Information -MessageData "Getting Virtual Network"
$GetAzVNET = Get-AzVirtualNetwork @GetAzVNETSplat

## Get the Key Vault
[System.Collections.Hashtable]$GetAzKVSplat = @{
    Name = $KeyVaultName
}

Write-Information -MessageData "Getting Key Vault"
$GetAzKV = Get-AzKeyVault @GetAzKVSplat

## Enable Network Policies on all subnets in the Virtual Network
### Get the subnets where the PrivateEndpointNetworkPolicies property exists and where the subnet name matches the $VirtualNetworkSubnetName variable, then enable PrivateEndpoint Network Policies on the subnet object. The changes haven't been committed to the virtual network yet.
Write-Information -MessageData "Modifying subnet object to enable private endpoint network policies"
($GetAzVNET.Subnets | Where-Object -FilterScript { ($_.Psobject.Properties.Name -eq 'PrivateEndpointNetworkPolicies') -and $_.Name -eq $VirtualNetworkSubnetName }) | ForEach-Object -Process {
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

## Get the Virtual Network subnet
$GetAzVNetSubnet = $GetAzVNET2.Subnets | Where-Object -FilterScript { $_.Name -eq $VirtualNetworkSubnetName }

### Get the Group ID for the Key Vault, which we'll need shortly
Write-Information -MessageData "Getting the GroupId for the Key Vault"
$GetAzKVGroupID = (Get-AzPrivateLinkResource -PrivateLinkResourceId $GetAzKV.ResourceId).GroupId

### Create a name for the Private Link Service Connection based on the Key Vault name
[System.String]$NewAzPLSCName = [System.String]::Concat($GetAzKV.VaultName, "-PLSC-01")

### Parameter splat for the Private Link Service Connection cmdlet
[System.Collections.Hashtable]$NewAzPLSCSplat = @{
    Name                 = $NewAzPLSCName
    PrivateLinkServiceId = $GetAzKV.ResourceId
    GroupId              = $GetAzKVGroupID
}

### Now create the Private Link Service Connection
Write-Information -MessageData "Creating the Private Link Service Connection"
$NewAzPLSC = New-AzPrivateLinkServiceConnection @NewAzPLSCSplat

### Create a name for the Private Endpoint Azure resource based on the Key Vault name
[System.String]$NewAzPEName = [System.String]::Concat($GetAzKV.VaultName, "-PE-01")

### Parameter splat for the Private Endpoint cmdlet
$NewAzPESplat = @{
    ResourceGroupName            = $GetAzKV.ResourceGroupName
    Name                         = $NewAzPEName
    Location                     = $GetAzKV.Location
    Subnet                       = $GetAzVNetSubnet
    PrivateLinkServiceConnection = $NewAzPLSC
}

### Now create the Private Endpoint
Write-Information -MessageData "Creating the Private Endpoint"
New-AzPrivateEndpoint @NewAzPESplat