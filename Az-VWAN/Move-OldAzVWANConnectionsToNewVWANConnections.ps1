[CmdletBinding()]
param (
    [Parameter()]
    [System.String[]]$VirtualNetworkResourceID,
    [System.String]$SourceVWANHubResourceID,
    [System.String]$DestinationVWANHubResourceID
)
$InformationPreference = "Continue"

### Source VWAN Hub
## Sanity check Source VWAN Hub parameter value
Write-Information -MessageData "Checking Source VWAN Hub parameter value."
[System.Collections.ArrayList]$SourceVWANHubResourceIDStringArray = $SourceVWANHubResourceID.Split("/")
[System.Int32]$SourceVWANHubResourceIDStringArrayExpectedCount = 8
$SourceVWANHubResourceIDStringArray.Remove(($SourceVWANHubResourceIDStringArray | Where-Object { $_ -in @("", $null) }))

if ($SourceVWANHubResourceIDStringArrayExpectedCount -ne $SourceVWANHubResourceIDStringArray.Count) {
    Write-Error -Message "Count of elements in Source VWAN Hub Resource ID Array should be '$SourceVWANHubResourceIDStringArrayExpectedCount' and is not. Please check supplied Resource ID and try again."
    break
}
[System.String]$SourceVWANHubSubscriptionID = $SourceVWANHubResourceIDStringArray[1]
[System.String]$SourceVWANHubResourceGroupName = $SourceVWANHubResourceIDStringArray[3]
[System.String]$SourceVWANHubName = $SourceVWANHubResourceIDStringArray[-1]

## Sanity check Source VWAN Hub Subscription ID
if ([System.Guid]$SourceVWANHubSubscriptionID -isnot [System.Guid]) {
    Write-Error -Message "Expected a GUID for the Source VWAN Hub's Subscription ID and received another type. Please check supplied Resource ID and try again."
    break
}

## Check/set context and get Source VWAN Hub
try {
    $ErrorActionPreference = "Stop"
    ## Check/set context
    Write-Information -MessageData "Checking context."
    $GetAzContext = Get-AzContext

    if ($GetAzContext.Subscription -eq $SourceVWANHubSubscriptionID) {
        Write-Information -MessageData "No need to switch context."
    }
    else {
        Write-Information -MessageData "Changing contexts to Source VWAN Hub Subscription: '$SourceVWANSubscriptionID'."
        Get-AzSubscription -SubscriptionId $SourceVWANHubSubscriptionID | Set-AzContext
    }

    ## Get Source VWAN Hub
    Write-Information -MessageData "Getting Source VWAN Hub."
    [Microsoft.Azure.Commands.Network.Models.PSVirtualHub]$GetSourceVWANHub = Get-AzVirtualHub -ResourceGroupName $SourceVWANHubResourceGroupName -Name $SourceVWANHubName
    Write-Information -MessageData "Found Source VWAN Hub."
}
catch {
    Write-Error -Message "Could not find Source VWAN Hub with Resource ID: '$SourceVWANHubResourceID'. Please check the supplied Resource ID and try again."
}
###
### Destination VWAN Hub
## Sanity check Destination VWAN Hub parameter value
Write-Information -MessageData "Checking Destination VWAN Hub parameter value."
[System.Collections.ArrayList]$DestinationVWANHubResourceIDStringArray = $DestinationVWANHubResourceID.Split("/")
[System.Int32]$DestinationVWANHubResourceIDStringArrayExpectedCount = 8
$DestinationVWANHubResourceIDStringArray.Remove(($DestinationVWANHubResourceIDStringArray | Where-Object { $_ -in @("", $null) }))

if ($DestinationVWANHubResourceIDStringArrayExpectedCount -ne $DestinationVWANHubResourceIDStringArray.Count) {
    Write-Error -Message "Count of elements in Destination VWAN Hub Resource ID Array should be '$DestinationVWANHubResourceIDStringArrayExpectedCount' and is not. Please check supplied Resource ID and try again."
    break
}
[System.String]$DestinationVWANHubSubscriptionID = $DestinationVWANHubResourceIDStringArray[1]
[System.String]$DestinationVWANHubResourceGroupName = $DestinationVWANHubResourceIDStringArray[3]
[System.String]$DestinationVWANHubName = $DestinationVWANHubResourceIDStringArray[-1]

## Sanity check Destination VWAN Hub Subscription ID
if ([System.Guid]$DestinationVWANHubSubscriptionID -isnot [System.Guid]) {
    Write-Error -Message "Expected a GUID for the Destination VWAN Hub's Subscription ID and received another type. Please check supplied Resource ID and try again."
    break
}

## Check/set context and get Destination VWAN Hub
try {
    $ErrorActionPreference = "Stop"
    ## Check/set context
    Write-Information -MessageData "Checking context."
    $GetAzContext = Get-AzContext

    if ($GetAzContext.Subscription -eq $DestinationVWANHubSubscriptionID) {
        Write-Information -MessageData "No need to switch context."
    }
    else {
        Write-Information -MessageData "Changing contexts to Destination VWAN Hub Subscription: '$DestinationVWANSubscriptionID'."
        Get-AzSubscription -SubscriptionId $DestinationVWANHubSubscriptionID | Set-AzContext
    }

    ## Get Destination VWAN Hub
    Write-Information -MessageData "Getting Destination VWAN Hub."
    [Microsoft.Azure.Commands.Network.Models.PSVirtualHub]$GetDestinationVWANHub = Get-AzVirtualHub -ResourceGroupName $DestinationVWANHubResourceGroupName -Name $DestinationVWANHubName
    Write-Information -MessageData "Found Destination VWAN Hub."
}
catch {
    Write-Error -Message "Could not find Destination VWAN Hub with Resource ID: '$DestinationVWANHubResourceID'. Please check the supplied Resource ID and try again."
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

Write-Information -MessageData "Source VWAN Hub, Destination VWAN Hub, and Virtual Networks validated."
###
### Source VWAN Hub - Remove Connections
[System.Int32]$i = 1
[System.Int32]$VirtualNetworkResourceIDCount = $VirtualNetworkResourceID.Count
foreach ($VNet in $VirtualNetworkResourceID) {
    Write-Information -MessageData "Removing VNet Connection from Source VWAN Hub with VNet Resource ID: '$VNet'. VNet: '$i' of: '$VirtualNetworkResourceIDCount' VNets."

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

        if ($GetAzContext.Subscription -eq $SourceVWANHubSubscriptionID) {
            Write-Information -MessageData "No need to switch context."
        }
        else {
            Write-Information -MessageData "Changing contexts to subscription of Source VWAN Hub: '$SourceVWANHubSubscriptionID'."
            Get-AzSubscription -SubscriptionId $VNetSubscriptionID | Set-AzContext
        }

        ## Get and remove VNet Connections.
        Get-AzVirtualHubVnetConnection -ParentObject $GetSourceVWANHub

    }
    catch {
        Write-Error -Message "An error was encountered while removing VNet Connections from the Source VWAN Hub."
    }
    $i++
}
Write-Information -MessageData "All VNet Connections removed."
###
### Destination VWAN Hub - Create VNet Connections
## With all VNet peerings removed, now create Destination VWAN VNet connections
Write-Information -MessageData "Creating VNet connections in a VWAN to the Destination VWAN Hub."

## Check/set context
Write-Information -MessageData "Checking context."
$GetAzContext = Get-AzContext

if ($GetAzContext.Subscription -eq $DestinationVWANSubscriptionID) {
    Write-Information -MessageData "No need to switch context."
}
else {
    Write-Information -MessageData "Changing contexts to Destination VWAN Subscription: '$DestinationVWANSubscriptionID'."
    Get-AzSubscription -SubscriptionId $DestinationVWANSubscriptionID | Set-AzContext
}

[System.Int32]$i = 1
[System.Int32]$VNetResourceIDCount = $VirtualNetworkResourceID.Count
foreach ($VNet in $VirtualNetworkResourceID) {
    [System.Collections.ArrayList]$VNetResourceIDStringArray = $VNet.Split("/")
    $VNetResourceIDStringArray.Remove(($VNetResourceIDStringArray | Where-Object { $_ -in @("", $null) }))
    [System.String]$VNetSubscriptionID = $VNetResourceIDStringArray[1]
    [System.String]$VNetResourceGroupName = $VNetResourceIDStringArray[3]
    [System.String]$VNetName = $VNetResourceIDStringArray[-1]
    [System.String]$VNetConnectionName = [System.String]::Concat($DestinationVWANHubName, "_to_", $VNetName)

    try {
        $ErrorActionPreference = "Stop"
        Write-Information -MessageData "Creating VNet connection for VNet: '$VNetName' to Destination VWAN Hub: '$DestinationVWANHubName'. Connection: '$i' of: '$VNetResourceIDCount' connections to create."
        New-AzVirtualHubVnetConnection -ParentObject $GetVWANHub -RemoteVirtualNetworkId $VNet -Name $VNetConnectionName
    }
    catch {
        Write-Error -Message "An error ocurred while creating a VNet connection for VNet: '$VNetResourceID' to Destination VWAN Hub: '$DestinationVWANHubResourceID'."
    }

    $i++
}
###
Write-Information -MessageData "All done!"