[CmdletBinding()]
param (
    [System.String]$ProviderNameSpace = "Microsoft.Network",
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