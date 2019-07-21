## Credit for the original version goes to: http://sharepointjack.com/2017/powershell-script-to-remove-duplicate-old-modules/
Write-Host "this will remove all old versions of installed modules"
Write-Host "be sure to run this as an admin" -foregroundcolor yellow
Write-Host "(You can update all your Azure RM modules with update-module Azurerm -force)"

$mods = Get-InstalledModule

foreach ($Mod in $mods) {
    Write-Host "Checking $($mod.name)"
    $latest = Get-InstalledModule $mod.name
    $specificmods = Get-InstalledModule $mod.name -allversions
    Write-Host "$($specificmods.count) versions of this module found [ $($mod.name) ]"

    foreach ($sm in $specificmods) {
        if ($sm.version -ne $latest.version) {
            Write-Host "uninstalling $($sm.name) - $($sm.version) [latest is $($latest.version)]"
            $sm | Uninstall-Module -force
            Write-Host "done uninstalling $($sm.name) - $($sm.version)"
            Write-Host "    --------"
        }

    }
    Write-Host "------------------------"
}
Write-Host "done"