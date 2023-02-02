# Start the firewall

$azfw = Get-AzFirewall -Name "AzureFirewall_Prod-VWAN-Hub-01" -ResourceGroupName "Prod-RG-NetworkInfrastructure-01"
$vnet = Get-AzVirtualNetwork -ResourceGroupName "Prod-RG-NetworkInfrastructure-01" -Name "VNet Name"
$publicip1 = Get-AzPublicIpAddress -Name "Public IP1 Name" -ResourceGroupName "Prod-RG-NetworkInfrastructure-01"
$publicip2 = Get-AzPublicIpAddress -Name "Public IP2 Name" -ResourceGroupName "Prod-RG-NetworkInfrastructure-01"
$azfw.Allocate($vnet, @($publicip1, $publicip2))

Set-AzFirewall -AzureFirewall $azfw