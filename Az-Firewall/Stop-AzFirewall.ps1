# Stop an existing firewall

$azfw = Get-AzFirewall -Name "AzureFirewall_Prod-VWAN-Hub-01" -ResourceGroupName "Prod-RG-NetworkInfrastructure-01"
$azfw.Deallocate()
Set-AzFirewall -AzureFirewall $azfw