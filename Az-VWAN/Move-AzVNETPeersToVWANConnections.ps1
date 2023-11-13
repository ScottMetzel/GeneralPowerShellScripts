[CmdletBinding()]
param (
    [Parameter()]
    [System.String[]]$VirtualNetworkResourceID,
    [System.String]$VWANHubResourceID
)
$InformationPreference = "Continue"

### VWAN Hub
## Sanity check VWAN Hub parameter value
Write-Information -MessageData "Checking VWAN Hub parameter value."
[System.Collections.ArrayList]$VWANHubResourceIDStringArray = $VWANHubResourceID.Split("/")
[System.Int32]$VWANHubResourceIDStringArrayExpectedCount = 8
$VWANHubResourceIDStringArray.Remove(($VWANHubResourceIDStringArray | Where-Object { $_ -in @("", $null) }))

if ($VWANHubResourceIDStringArrayExpectedCount -ne $VWANHubResourceIDStringArray.Count) {
    Write-Error -Message "Count of elements in VWAN Hub Resource ID Array should be '$VWANHubResourceIDStringArrayExpectedCount' and is not. Please check supplied Resource ID and try again."
    break
}
[System.String]$VWANHubSubscriptionID = $VWANHubResourceIDStringArray[1]
[System.String]$VWANHubResourceGroupName = $VWANHubResourceIDStringArray[3]
[System.String]$VWANHubName = $VWANHubResourceIDStringArray[-1]

## Sanity check VWAN Hub Subscription ID
if ([System.Guid]$VWANHubSubscriptionID -isnot [System.Guid]) {
    Write-Error -Message "Expected a GUID for the VWAN Hub's Subscription ID and received another type. Please check supplied Resource ID and try again."
    break
}

## Check/set context and get VWAN Hub
try {
    $ErrorActionPreference = "Stop"
    ## Check/set context
    Write-Information -MessageData "Checking context."
    $GetAzContext = Get-AzContext

    if ($GetAzContext.Subscription -eq $VWANHubSubscriptionID) {
        Write-Information -MessageData "No need to switch context."
    }
    else {
        Write-Information -MessageData "Changing contexts to VWAN Hub Subscription: '$VWANSubscriptionID'."
        Get-AzSubscription -SubscriptionId $VWANHubSubscriptionID | Set-AzContext
    }

    ## Get VWAN Hub
    Write-Information -MessageData "Getting VWAN Hub."
    [Microsoft.Azure.Commands.Network.Models.PSVirtualHub]$GetVWANHub = Get-AzVirtualHub -ResourceGroupName $VWANHubResourceGroupName -Name $VWANHubName
    Write-Information -MessageData "Found VWAN Hub."
}
catch {
    Write-Error -Message "Could not find VWAN Hub with Resource ID: '$VWANHubResourceID'. Please check the supplied Resource ID and try again."
}
###
### VNet - Check
## Get VNets supplied
[System.Int32]$i = 1
[System.Int32]$VirtualNetworkResourceIDCount = $VirtualNetworkResourceID.Count
[System.Collections.ArrayList]$VNetObjectArray = @()
foreach ($VNet in $VirtualNetworkResourceID) {
    try {
        $ErrorActionPreference = "Stop"
        [System.Collections.ArrayList]$VNetResourceIDStringArray = $VNet.Split("/")
        $VNetResourceIDStringArray.Remove(($VNetResourceIDStringArray | Where-Object { $_ -in @("", $null) }))
        [System.String]$VNetSubscriptionID = $VNetResourceIDStringArray[1]
        [System.String]$VNetResourceGroupName = $VNetResourceIDStringArray[3]
        [System.String]$VNetName = $VNetResourceIDStringArray[-1]

        ## Check/set context
        Write-Information -MessageData "Checking context."
        $GetAzContext = Get-AzContext

        if ($GetAzContext.Subscription -eq $VNetSubscriptionID) {
            Write-Information -MessageData "No need to switch context."
        }
        else {
            Write-Information -MessageData "Changing contexts to subscription of VNet: '$VNetSubscriptionID'."
            Get-AzSubscription -SubscriptionId $VNetSubscriptionID | Set-AzContext
        }

        Write-Information -MessageData "Getting VNet with Resource ID: '$VNet'. VNet: '$i' of: '$VirtualNetworkResourceIDCount' VNets."
        [PSVirtualNetwork]$GetAzVNet = Get-AzVirtualNetwork -ResourceGroupName $VNetResourceGroupName -Name $VNetName
        if ($GetAzVNet) {
            Write-Information -MessageData "Found VNet: '$VNet'."
            $VNetObjectArray.Add($GetAzVNet) | Out-Null
        }
        else {
            throw
        }
    }
    catch {
        Write-Error -Message "Could not find VNet: '$VNet'. Please check the supplied Resource ID and try again."
    }
    $i++
}

Write-Information -MessageData "VWAN Hub and Virtual Networks validated."
###
### VNet - Peerings
## Find VNets and remove peerings
[System.Int32]$i = 1
[System.Int32]$VirtualNetworkResourceIDCount = $VirtualNetworkResourceID.Count
foreach ($VNet in $VirtualNetworkResourceID) {
    Write-Information -MessageData "Getting VNet with Resource ID: '$VNet'. VNet: '$i' of: '$VirtualNetworkResourceIDCount' VNets."

    try {
        $ErrorActionPreference = "Stop"
        [System.Collections.ArrayList]$VNetResourceIDStringArray = $VNet.Split("/")
        $VNetResourceIDStringArray.Remove(($VNetResourceIDStringArray | Where-Object { $_ -in @("", $null) }))
        [System.String]$VNetSubscriptionID = $VNetResourceIDStringArray[1]
        [System.String]$VNetResourceGroupName = $VNetResourceIDStringArray[3]
        [System.String]$VNetName = $VNetResourceIDStringArray[-1]

        ## Check/set context
        Write-Information -MessageData "Checking context."
        $GetAzContext = Get-AzContext

        if ($GetAzContext.Subscription -eq $VNetSubscriptionID) {
            Write-Information -MessageData "No need to switch context."
        }
        else {
            Write-Information -MessageData "Changing contexts to subscription: '$VNetSubscriptionID'."
            Get-AzSubscription -SubscriptionId $VNetSubscriptionID | Set-AzContext
        }


        ## Check for and remove VNet Peers
        [System.Collections.ArrayList]$VNetPeerings = @()

        Get-AzVirtualNetworkPeering -ResourceGroupName $VNetResourceGroupName -VirtualNetworkName $VNetName | ForEach-Object -Process {
            $VNetPeerings.Add($_) | Out-Null
        }

        ## If the VNet has peerings, then remove them.
        if ($VNetPeerings.Count -gt 0) {
            Write-Information -MessageData "Found VNet peers to remove for VNet: '$VNet'."

            ## Remove VNet Peers
            foreach ($Peer in $VNetPeerings) {
                [System.String]$VNetPeeringName = $Peer.Name
                try {
                    $ErrorActionPreference = "Stop"
                    Write-Information -MessageData "Trying to remove VNet Peering: '$VNetPeeringName'."
                    Remove-AzVirtualNetworkPeering -ResourceGroupName $VNetResourceGroupName -VirtualNetworkName $VNet -Name $VNetPeeringName -Force
                }
                catch {
                    Write-Error -Message "An error was encountered while removing VNet Peerings. Last VNet Peering to be removed was: '$VNetPeeringName' on VNet: '$VNet'."
                }
            }
        }
    }
    catch {
        Write-Error -Message "An error was encountered while moving VNet Peers."
    }
    $i++
}
Write-Information -MessageData "All VNet peerings removed."
###
### VWAN Hub - Create VNet Connections
## With all VNet peerings removed, now create VWAN VNet connections
Write-Information -MessageData "Creating VNet connections in the VWAN to the VWAN Hub."

## Check/set context
Write-Information -MessageData "Checking context."
$GetAzContext = Get-AzContext

if ($GetAzContext.Subscription -eq $VWANSubscriptionID) {
    Write-Information -MessageData "No need to switch context."
}
else {
    Write-Information -MessageData "Changing contexts to VWAN Subscription: '$VWANSubscriptionID'."
    Get-AzSubscription -SubscriptionId $VWANSubscriptionID | Set-AzContext
}

[System.Int32]$i = 1
[System.Int32]$VNetResourceIDCount = $VirtualNetworkResourceID.Count
foreach ($VNet in $VirtualNetworkResourceID) {
    [System.Collections.ArrayList]$VNetResourceIDStringArray = $VNet.Split("/")
    $VNetResourceIDStringArray.Remove(($VNetResourceIDStringArray | Where-Object { $_ -in @("", $null) }))
    [System.String]$VNetSubscriptionID = $VNetResourceIDStringArray[1]
    [System.String]$VNetResourceGroupName = $VNetResourceIDStringArray[3]
    [System.String]$VNetName = $VNetResourceIDStringArray[-1]
    [System.String]$VNetConnectionName = [System.String]::Concat($VWANHubName, "_to_", $VNetName)

    try {
        $ErrorActionPreference = "Stop"
        Write-Information -MessageData "Creating VNet connection for VNet: '$VNetName' to VWAN Hub: '$VWANHubName'. Connection: '$i' of: '$VNetResourceIDCount' connections to create."
        New-AzVirtualHubVnetConnection -ParentObject $GetVWANHub -RemoteVirtualNetworkId $VNet -Name $VNetConnectionName
    }
    catch {
        Write-Error -Message "An error ocurred while creating a VNet connection for VNet: '$VNetResourceID' to VWAN Hub: '$VWANHubResourceID'."
    }

    $i++
}
###
Write-Information -MessageData "All done!"