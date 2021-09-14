#Requires -Modules @{ ModuleName="Az.Resources"; ModuleVersion="3.0.0.0"}
<#
    .SYNOPSIS
    This script registers for a new Resource Provider feature

    .DESCRIPTION
    This script registers for a new Resource Provider feature, which is typically in public preview

    .NOTES
    ###################################################################################################################
    Created With: Microsoft Visual Studio Code
    Created On: September 9, 2021
    Author: Scott Metzel
    Organization: -
    Filename: Register-AzProviderFeatureWithLoop.ps1

    Version History:
    ## Version ##   ## Edited By ## ## Date ##          ## Notes ######################################################
    0.1             Scott Metzel    September 9, 2021   Initial Version based on prior script
    ###################################################################################################################

    .EXAMPLE
    Register-AzProviderFeatureWithLoop.ps1 -ProviderNameSpace "Microsoft.Network" -FeatureName "AllowPrivateEndpointNSG"

    .INPUTS
    None. This runbook does not accept inputs from the pipeline.

    .OUTPUTS
    None.
#>
[CmdletBinding()]
param (
    [Parameter(
        Mandatory = $false
    )]
    [ValidateScript(
        {
            ($_ -split "\.").Count -eq 2
        }
    )]
    [System.String]$ProviderNameSpace = "Microsoft.Network",
    [Parameter(
        Mandatory = $false
    )]
    [ValidateNotNullOrEmpty()]
    [System.String]$FeatureName = "AllowPrivateEndpointNSG"
)
## Get information stream messages to show, and make sure we stop on error
$InformationPreference = "Continue"
$ErrorActionPreference = "Stop"

## Get the Preview Feature state
if ($true -eq $RegisterPreviewNSGFeature) {
    $GetAzProviderFeature = Get-AzProviderFeature -ProviderNamespace $ProviderNameSpace -FeatureName $FeatureName
    [System.String]$AzProviderFeatureRegistrationState = $GetAzProviderFeature.RegistrationState

    ## Register for it if not registered
    if ("NotRegistered" -eq $AzProviderFeatureRegistrationState) {
        Write-Information -MessageData "Preview Feature state is: '$AzProviderFeatureRegistrationState'. Registering."
        Register-AzProviderFeature -ProviderNamespace $ProviderNameSpace -FeatureName $FeatureName
    }
    elseif ($AzProviderFeatureRegistrationState -eq "Registered") {
        Write-Information -MessageData "Preview Feature state is: '$AzProviderFeatureRegistrationState'. Skipping registration."
    }
    else {
        Write-Warning -Message "Preview Feature state is: '$AzProviderFeatureRegistrationState'. Please try again in a bit."
        throw
    }

    ######## Loop until the preview feature is registered
    do {
        Write-Information -MessageData "Checking preview feature registration state again..."
        $GetAzProviderFeatureAgain = Get-AzProviderFeature -ProviderNamespace $ProviderNameSpace -FeatureName $FeatureName
        [System.String]$AzProviderFeatureRegistrationStateAgain = $GetAzProviderFeatureAgain.RegistrationState
        Write-Information -MessageData "Preview Feature state is: '$AzProviderFeatureRegistrationState'"

        if ("Registered" -ne $AzProviderFeatureRegistrationStateAgain) {
            Write-Information -MessageData "Preview Feature registration state is not 'Registered'. Waiting for 5 seconds..."
            Start-Sleep -Seconds 5
        }

    } while ("Registered" -ne $AzProviderFeatureRegistrationStateAgain)
    ######## End Loop
}