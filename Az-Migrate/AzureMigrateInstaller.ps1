# -------------------------------------------------------------------------------------------------
#  <copyright file="AzureMigrateInstaller.ps1" company="Microsoft">
#      Copyright (c) Microsoft Corporation. All rights reserved.
#  </copyright>
#
#  Description: This script prepares the host machine for various Azure Migrate Scenarios.

#  Version: 10.3.0.0

#  Requirements:
#       Refer Readme.html for machine requirements
#       Following files should be placed in the same folder as this script before execution:
#            Scripts : WebBinding.ps1 and SetRegistryForTrustedSites.ps1
#            MSIs    : Microsoft Azure Hyper-V\Server\VMware Assessment Service.msi
#                      Microsoft Azure Hyper-V\Server\VMware Discovery Service.msi
#                      Microsoft Azure SQL Discovery and Assessment Service.msi
#                      MicrosoftAzureApplianceConfigurationManager.msi
#                      MicrosoftAzureAutoUpdate.msi
#                      MicrosoftAzureDraService.msi     (VMware Migration only)
#                      MicrosoftAzureGatewayService.exe (VMware Migration only)
#            Config  : Scenario.json
#                      {
#                           "Scenario"        : "HyperV|Physical|VMware",
#                           "Cloud"           : "Public|USGov",
#                           "ScaleOut"        : "True|False",
#                           "PrivateEndpoint" : "True|False"
#                      }
# -------------------------------------------------------------------------------------------------

#Requires -RunAsAdministrator

[CmdletBinding(DefaultParameterSetName = "NewInstall")]
param(
    [Parameter(Mandatory = $false, ParameterSetName = "NewInstall")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('HyperV', 'Physical', 'VMware')]
    [string]
    $Scenario,

    [Parameter(Mandatory = $false, ParameterSetName = "NewInstall")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('Public', 'USGov')]
    [string]
    $Cloud,

    [Parameter(Mandatory = $false, ParameterSetName = "NewInstall")]
    [Parameter(Mandatory = $false, ParameterSetName = "Upgrade")]
    [switch]
    $SkipSettingTrustedHost,

    [Parameter(Mandatory = $false, ParameterSetName = "Upgrade")]
    [switch]
    $UpgradeAgents,

    [Parameter(Mandatory = $false, ParameterSetName = "NewInstall")]
    [switch]
    $ScaleOut,

    [Parameter(Mandatory = $false, ParameterSetName = "NewInstall")]
    [switch]
    $PrivateEndpoint,

    [Parameter(Mandatory = $false, ParameterSetName = "Uninstall")]
    [switch]
    $RemoveAzMigrate,

    [Parameter(Mandatory = $false, ParameterSetName = "NewInstall")]
    [switch]
    $Repurpose,

    [Parameter(Mandatory = $false, ParameterSetName = "NewInstall")]
    [Parameter(Mandatory = $false, ParameterSetName = "Upgrade")]
    [switch]
    $DisableAutoUpdate
)

#region - These routines writes the output string to the console and also to the log file.
function Log-Info([string] $OutputText) {
    Write-Host $OutputText -ForegroundColor White
    $OutputText = [string][DateTime]::Now + " " + $OutputText
    $OutputText | ForEach-Object { Out-File -FilePath $InstallerLog -InputObject $_ -Append -Encoding "ASCII" }
}

function Log-InfoHighLight([string] $OutputText) {
    Write-Host $OutputText -ForegroundColor Cyan
    $OutputText = [string][DateTime]::Now + " " + $OutputText
    $OutputText | ForEach-Object { Out-File -FilePath $InstallerLog -InputObject $_ -Append -Encoding "ASCII" }
}

function Log-Input([string] $OutputText) {
    Write-Host $OutputText -ForegroundColor White -BackgroundColor DarkGray -NoNewline
    $OutputText = [string][DateTime]::Now + " " + $OutputText
    $OutputText | ForEach-Object { Out-File -FilePath $InstallerLog -InputObject $_ -Append -Encoding "ASCII" }
    Write-Host " " -NoNewline
}

function Log-Success([string] $OutputText) {
    Write-Host $OutputText -ForegroundColor Green
    $OutputText = [string][DateTime]::Now + " " + $OutputText
    $OutputText | ForEach-Object { Out-File -FilePath $InstallerLog -InputObject $_ -Append -Encoding "ASCII" }
}

function Log-Warning([string] $OutputText) {
    Write-Host $OutputText -ForegroundColor Yellow
    $OutputText = [string][DateTime]::Now + " " + $OutputText
    $OutputText | ForEach-Object { Out-File -FilePath $InstallerLog -InputObject $_ -Append -Encoding "ASCII" }
}

function Log-Error([string] $OutputText) {
    Write-Host $OutputText -ForegroundColor Red
    $OutputText = [string][DateTime]::Now + " " + $OutputText
    $OutputText | ForEach-Object { Out-File -FilePath $InstallerLog -InputObject $_ -Append -Encoding "ASCII" }
}
#endregion

#region - Global Initialization
$global:DefaultStringVal = "Unknown"
$global:WarningCount = 0
$global:ReuseScenario = 0
$global:SelectedFabricType = $global:DefaultStringVal
$global:SelectedCloud = $global:DefaultStringVal
$global:SelectedScaleOut = "False"
$global:SelectedPEEnabled = "False"
$global:ParameterList = $PSBoundParameters

$machineHostName = (Get-WmiObject win32_computersystem).DNSHostName
$DefaultURL = "https://" + $machineHostName + ":44368"
$TimeStamp = [DateTime]::Now.ToString("yyyy-MM-dd-HH-mm-ss")
$BackupDir = "$env:ProgramData`\Microsoft Azure"
$BackupDestination = "$env:windir`\Temp\MicrosoftAzure"
$LogFileDir = "$env:ProgramData`\Microsoft Azure\Logs"
$ConfigFileDir = "$env:ProgramData`\Microsoft Azure\Config"
# TODO: Move reading this path from registry if it exists
$CredFileDir = "$env:ProgramData`\Microsoft Azure\CredStore"
$ApplianceVersionFilePath = "$Env:SystemDrive`\Users\Public\Desktop\ApplianceVersion.txt"

$HyperVAssessmentServiceMSI = "Microsoft Azure Hyper-V Assessment Service.msi"
$HyperVDiscoveryServiceMSI = "Microsoft Azure Hyper-V Discovery Service.msi"
$ServerAssessmentServiceMSI = "Microsoft Azure Server Assessment Service.msi"
$ServerDiscoveryServiceMSI = "Microsoft Azure Server Discovery Service.msi"
$VMWareAssessmentServiceMSI = "Microsoft Azure VMware Assessment Service.msi"
$VMWareDiscoveryServiceMSI = "Microsoft Azure VMware Discovery Service.msi"
$SQLServiceMSI = "Microsoft Azure SQL Discovery and Assessment Service.msi"
$WebAppMSI = "Microsoft Azure Web App Discovery and Assessment Service.msi"
$AppCompatMSI = "Microsoft Azure Application Compatibility Assessment Service.msi"
$AssessmentServiceMSILog = "$LogFileDir\AssessmentInstaller_$TimeStamp.log"
$DiscoveryServiceMSILog = "$LogFileDir\DiscoveryInstaller_$TimeStamp.log"
$SQLServiceMSILog = "$LogFileDir\SQLInstaller_$TimeStamp.log"
$WebAppMSILog = "$LogFileDir\WebAppInstaller_$TimeStamp.log"
$AppCompatMSILog = "$LogFileDir\AppCompatInstaller_$TimeStamp.log"

$GatewayExeName = "MicrosoftAzureGatewayService.exe"
$DraMsiName = "MicrosoftAzureDRAService.msi"
$DraMsiLog = "$LogFileDir\DRAInstaller_$TimeStamp.log"

$ConfigManagerMSI = "MicrosoftAzureApplianceConfigurationManager.msi"
$ConfigManagerMSILog = "$LogFileDir\ConfigurationManagerInstaller_$TimeStamp.log"
$ApplianceJsonFilePath = "$ConfigFileDir\appliance.json"
$ApplianceJsonFileData = @{
    "Cloud"                  = "$global:SelectedCloud";
    "ComponentVersion"       = "26.0.0.1";
    "FabricType"             = "$global:SelectedFabricType";
    "ScaleOut"               = $global:SelectedScaleOut;
    "PrivateEndpointEnabled" = $global:SelectedPEEnabled;
    "VddkInstallerFolder"    = "";
    "IsApplianceRegistered"  = "false";
    "EnableProxyBypassList"  = "true";
    "ProviderId"             = "8416fccd-8af8-466e-8021-79db15038c87";
}

$AutoUpdaterMSI = "MicrosoftAzureAutoUpdate.msi"
$AutoUpdaterMSILog = "$LogFileDir\AutoUpdateInstaller_$TimeStamp.log"
$AutoUpdaterJsonFilePath = "$ConfigFileDir\AutoUpdater.json"
$AutoUpdaterJsonFileData = @{
    "Cloud"                   = "$global:SelectedCloud";
    "ComponentVersion"        = "26.0.0.0";
    "AutoUpdateEnabled"       = "True";
    "ProviderId"              = "8416fccd-8af8-466e-8021-79db15038c87";
    "AutoUpdaterDownloadLink" = "https://aka.ms/latestapplianceservices"
}

$RegAzureAppliancePath = "HKLM:\SOFTWARE\Microsoft\Azure Appliance"
$RegAzureCredStorePath = "HKLM:\Software\Microsoft\AzureAppliance"
#endregion

## Creating the logfile
New-Item -ItemType Directory -Force -Path $LogFileDir | Out-Null
$InstallerLog = "$LogFileDir\AzureMigrateScenarioInstaller_$TimeStamp.log"
Log-InfoHighLight "Log file created `"$InstallerLog`" for troubleshooting purpose.`n"

#region - Cleanup
<#
.SYNOPSIS
Create JsonFile
Usage:
    DetectAndCleanupPreviousInstallation
#>
function DetectAndCleanupPreviousInstallation {
    [int]$maxRetryLimit = 3
    [int]$retryCount = 0

    if ($global:ReuseScenario -eq 1) {
        $ZipFilePath = "$BackupDestination`\Backup_$TimeStamp.zip"
        Log-Info "Zip and backup the configuration to the path: $ZipFilePath"
        [void](New-Item -ItemType "Directory" -Path $BackupDestination -Force)

        ## Compress file.
        [void][Reflection.Assembly]::LoadWithPartialName( "System.IO.Compression.FileSystem" )
        [void]([System.IO.Compression.ZipFile]::CreateFromDirectory($BackupDir, $ZipFilePath) | Out-File -FilePath $InstallerLog -NoClobber -Append)
        Log-Success "[OK]`n"
    }

    Log-InfoHighLight "Initiating removal of previously installed agents (if found installed) in next 5 seconds..."
    Start-Sleep -Seconds 5
    Log-Info "This cleanup process can take up to 2-3 minutes.`n"

    UnInstallProgram("Microsoft Azure Server Assessment Service")
    UnInstallProgram("Microsoft Azure Server Discovery Service")
    UnInstallProgram("Microsoft Azure Hyper-V Assessment Service")
    UnInstallProgram("Microsoft Azure Hyper-V Discovery Service")
    UnInstallProgram("Microsoft Azure VMware Assessment Service")
    UnInstallProgram("Microsoft Azure VMware Discovery Service")
    UnInstallProgram("Microsoft Azure Appliance Auto Update")
    UnInstallProgram("Microsoft Azure Appliance Configuration Manager")
    UnInstallProgram("Microsoft Azure Dra Service")
    UnInstallProgram("Microsoft Azure Gateway Service")
    UnInstallProgram("Microsoft Azure SQL Discovery and Assessment Service")
    UnInstallProgram("Microsoft Azure Web App Discovery and Assessment Service")
    #UnInstallProgram("Microsoft Azure Application Compatibility Assessment Service")

    #Restart IIS
    "iisreset.exe /restart" | Out-Null

    CleanupPerformanceCounter

    if ($UpgradeAgents -eq $false) {
        while ($maxRetryLimit -gt $retryCount) {
            $Error.Clear()
            Log-info "Cleaning up previous configuration files and settings..."

            if ([System.IO.File]::Exists($ApplianceVersionFilePath)) {
                Remove-Item -Path $ApplianceVersionFilePath -Force
            }

            if ([System.IO.File]::Exists($AutoUpdaterJsonFilePath)) {
                Remove-Item –Path $AutoUpdaterJsonFilePath -Force
            }

            if (Test-Path $RegAzureCredStorePath) {
                Remove-Item -Path $RegAzureCredStorePath -Force -Recurse
            }

            if (Test-Path $ApplianceJsonFilePath) {
                Remove-Item –Path $ApplianceJsonFilePath -Force
            }

            if (Test-Path $ConfigFileDir -PathType Any) {
                Remove-Item -Path $ConfigFileDir -Force -Recurse
            }

            if (Test-Path $CredFileDir -PathType Container) {
                Remove-Item $CredFileDir -Force -Recurse
            }

            if (Test-Path $LogFileDir -PathType Container) {
                # Remove all folders under Log folder.
                Get-ChildItem -Recurse $LogFileDir | Where-Object { $_.PSIsContainer } | Remove-Item -Recurse -Force
            }

            if (Test-Path $RegAzureAppliancePath) {
                Remove-Item $RegAzureAppliancePath -Force -Recurse
            }

            if ($Error.Count -eq 0) {
                break
            }
            else {
                $retryCount++
                Log-InfoHighLight $Error
                Log-Warning "Retry attempt #$retryCount of #$maxRetryLimit : Please ensure that none of the files at the folder location '$BackupDir' are currently opened.`n"
                Start-Sleep -Seconds 10
            }
        }
    }

    if ($Error.Count -eq 0) {
        Log-Success "[OK]`n"
    }
    else {
        Log-Error $Error
        Log-Error "Cleanup attempt failed. Aborting..."
        Log-Warning "Please take remedial action on the above error and retry executing the script again or contact Microsoft Support for assistance."
        exit -2
    }

    if ($RemoveAzMigrate -eq $true) {
        Log-Success "Cleanup completed successfully. Exiting..."
        exit 0
    }
}

<#
.SYNOPSIS
Cleans up Performance monitor data collector set
Usage:
    CleanupPerformanceCounter
#>

function CleanupPerformanceCounter {
    param(
        [string]$CollectorSetName = "AzureAppliancePerfMonitor"
    )

    try {
        $collectorset = New-Object -COM Pla.DataCollectorSet
        $collectorset.Query($CollectorSetName, $null)

        if ($collectorset.name -eq $CollectorSetName) {
            if ($collectorset.Status -eq 1) {
                $collectorset.Stop($false);
            }

            $null = $collectorset.Delete()
        }

        $PerfFileDir = "$env:windir`\Temp\MicrosoftAzure\" + $CollectorSetName
        if (Test-Path $PerfFileDir -PathType Container) {
            # Remove all folders under perf data folder.
            Get-ChildItem -Recurse $PerfFileDir | Where-Object { $_.PSIsContainer } | Remove-Item -Recurse -Force
        }

    }
    catch [Exception] {
        $OutputText = [string][DateTime]::Now + " " + "Unable to delete performance counter successfully. $_.Exception Please manually delete $CollectorSetName from PerfMon under User Defined collector sets. Continuing..."
        $OutputText | ForEach-Object { Out-File -FilePath $InstallerLog -InputObject $_ -Append -Encoding "ASCII" }
    }

    $Error.Clear()
}

<#
.SYNOPSIS
Install MSI
Usage:
    UnInstallProgram -ProgramCaption $ProgramCaption
#>

function UnInstallProgram {
    param(
        [string] $ProgramCaption
    )

    $app = Get-WmiObject -Class Win32_Product -Filter "Caption = '$ProgramCaption' "

    if ($app) {
        Log-Info "$ProgramCaption found installed. Proceeding with uninstallation."
        Start-Sleep -Seconds 2
        [void]($app.Uninstall())

        if ($?) {
            Log-Success "[Uninstall Successful]`n"
        }
        else {
            $global:WarningCount++
            Log-Warning "Warning #$global:WarningCount : Unable to uninstall successfully. Please manually uninstall $ProgramCaption from Control Panel. Continuing..."
        }
    }

    $Error.Clear()
}
#endregion

<#
.SYNOPSIS
Install MSI
Usage:
    InstallMSI -MSIFilePath $MSIFilePath -MSIInstallLogName $MSIInstallLogName
#>

function InstallMSI {
    param(
        [string] $MSIFilePath,
        [string] $MSIInstallLogName,
        [switch] $OptionalComponent
    )

    [int]$maxRetryLimit = 5
    [int]$retryCount = 0

    Log-Info "Installing $MSIFilePath..."

    if (-Not (Test-Path -Path $MSIFilePath -PathType Any)) {
        if ($OptionalComponent.IsPresent) {
            Log-InfoHighLight "Optional Component MSI not found: $MSIFilePath. Continuing..."
            Log-Warning "[Skipping]`n"
            return
        }

        Log-Error "MSI not found: $MSIFilePath. Aborting..."
        Log-Warning "Please download the installation script and uncompress the contents again and rerun the PowerShell script."
        exit -3
    }

    while ($maxRetryLimit -gt $retryCount) {
        $Error.Clear()
        $process = (Start-Process -Wait -PassThru -FilePath msiexec -ArgumentList `
                "/i `"$MSIFilePath`" /quiet /lv `"$MSIInstallLogName`"")

        $returnCode = $process.ExitCode;

        if ($returnCode -eq 0 -or $returnCode -eq 3010) {
            Log-Success "[OK]`n"
            return
        }
        else {
            $retryCount++
            Log-InfoHighLight "$MSIFilePath installation failed with $returnCode."
            Log-Warning "Retry attempt #$retryCount of #$maxRetryLimit.`n"
            Start-Sleep -Seconds 10
        }
    }

    Log-Error "$MSIFilePath installation failed. More logs available at $MSIInstallLogName. Aborting..."
    Log-Warning "Please refer to http://www.msierrors.com/ to get details about the error code: $returnCode and rerun the script. If required please share the installation log file $MSIInstallLogName while contacting Microsoft Support."
    exit -3
}

<#
.SYNOPSIS
Create JsonFile
Usage:
    CreateJsonFile -JsonFileData $JsonFileData -JsonFilePath $JsonFilePath
#>
function CreateJsonFile {
    param(
        $JsonFileData,
        [string] $JsonFilePath
    )

    if ($UpgradeAgents -and (Test-Path -Path $JsonFilePath)) {
        Log-Info "Skip creating config file:  $JsonFilePath..."
        return;
    }

    Log-Info "Creating config file: $JsonFilePath..."

    New-Item -Path $ConfigFileDir -type directory -Force | Out-Null
    $JsonFileData | ConvertTo-Json | Add-Content -Path $JsonFilePath -Encoding UTF8

    if ($?) {
        Log-Success "[OK]`n"
    }
    else {
        Log-Error "Failure in creating $JsonFilePath. Aborting..."
        Log-Warning "Please take remedial action on the below error or contact Microsoft Support for assistance."
        Log-Error $_
        exit -4
    }
}

<#
.SYNOPSIS
Enables IIS modules.
Usage:
    EnableIIS
#>

function EnableIIS {
    Log-Info "Enabling IIS Role and other dependent features..."

    $OS = Get-WmiObject Win32_OperatingSystem

    if ($OS.Caption.contains("Server") -eq $true) {

        # Setup a simple version check to install roles specific to 2019 (or newer?)
        [System.Version]$OSVersion = $OS.Version
        [System.Version]$2019Version = "10.0.17763"

        [System.Collections.ArrayList]$FeatureArray = @(
            "WAS",
            "WAS-Config-APIs",
            "WAS-Process-Model",
            "Web-App-Dev",
            "Web-Asp-Net45",
            "Web-CGI",
            "Web-Common-Http",
            "Web-Default-Doc",
            "Web-Dir-Browsing",
            "Web-Filtering",
            "Web-Health",
            "Web-Http-Errors",
            "Web-Http-Logging",
            "Web-Http-Redirect",
            "Web-Log-Libraries",
            "Web-Mgmt-Console",
            "Web-Mgmt-Service",
            "Web-Mgmt-Tools",
            "Web-Net-Ext45",
            "Web-Performance",
            "Web-Request-Monitor",
            "Web-Scripting-Tools",
            "Web-Security",
            "Web-Server",
            "Web-Stat-Compression",
            "Web-Static-Content",
            "Web-Url-Auth",
            "Web-WebServer",
            "Web-Windows-Auth"
        )
        if ($OSVersion -ge $2019Version) {
            Log-Info "OS version is: '$OSVersion'. Will install roles and features for Server 2019 or newer."
        }
        else {
            Log-Info "OS version is: '$OSVersion'. Installing roles and features for Server 2016."
            $FeatureArray.Add("PowerShell-ISE") | Out-Null
        }
        Install-WindowsFeature -FeatureName $FeatureArray
    }
    else {
        Log-InfoHighLight "Windows client SKU is not supported for Azure Migrate Appliance Operating System. To be used for testing purpose only..."
        Enable-WindowsOptionalFeature -Online -FeatureName NetFx4Extended-ASPNET45, IIS-WebServerRole, `
            IIS-WebServer, IIS-CommonHttpFeatures, IIS-HttpErrors, IIS-HttpRedirect, IIS-ApplicationDevelopment, `
            IIS-NetFxExtensibility, IIS-NetFxExtensibility45, IIS-HealthAndDiagnostics, IIS-HttpLogging, `
            IIS-LoggingLibraries, IIS-RequestMonitor, IIS-HttpTracing, IIS-Security, IIS-URLAuthorization, `
            IIS-RequestFiltering, IIS-IPSecurity, IIS-Performance, IIS-HttpCompressionDynamic, `
            IIS-WebServerManagementTools, IIS-ManagementScriptingTools, IIS-IIS6ManagementCompatibility, `
            IIS-Metabase, WAS-WindowsActivationService, WAS-ProcessModel, WAS-NetFxEnvironment, WAS-ConfigurationAPI, `
            IIS-HostableWebCore, IIS-StaticContent, IIS-DefaultDocument, IIS-DirectoryBrowsing, IIS-WebDAV, `
            IIS-WebSockets, IIS-ApplicationInit, IIS-ASPNET, IIS-ASPNET45, IIS-ASP, IIS-CGI, IIS-ISAPIExtensions, `
            IIS-ISAPIFilter, IIS-ServerSideIncludes, IIS-CustomLogging, IIS-BasicAuthentication, IIS-HttpCompressionStatic, `
            IIS-ManagementConsole, IIS-ManagementService, IIS-WMICompatibility | Out-Null
    }

    if ($?) {
        Log-Success "[OK]`n"
    }
    else {
        Log-Error "Failure to enable the required role(s) with error $Errors. Aborting..."
        Log-Warning "Please ensure the following roles are enabled manually: PowerShell-ISE, `
            WAS (Windows Activation Service), WAS-Process-Model, WAS-Config-APIs, Web-Server (IIS), '
            Web-WebServer, Web-Mgmt-Service, Web-Request-Monitor, Web-Common-Http, Web-Static-Content, '
            Web-Default-Doc, Web-Dir-Browsing, Web-Http-Errors, Web-App-Dev, Web-CGI, Web-Health,'
            Web-Http-Logging, Web-Log-Libraries, Web-Security, Web-Filtering, Web-Performance, '
            Web-Stat-Compression, Web-Mgmt-Tools, Web-Mgmt-Console, Web-Scripting-Tools, '
            Web-Asp-Net45, Web-Net-Ext45, Web-Http-Redirect, Web-Windows-Auth, Web-Url-Auth"
        exit -5
    }
}

<#
.SYNOPSIS
Add AzureCloud registry which used to identify NationalCloud
Usage:
    AddAzureCloudRegistry
#>

function AddingRegistryKeys {
    Log-Info "Adding\Updating Registry Keys...`n"
    $AzureCloudName = "Public"

    if ( -not (Test-Path $RegAzureAppliancePath)) {
        Log-Info "`tCreating Registry Node: $RegAzureAppliancePath"
        New-Item -Path $RegAzureAppliancePath -Force | Out-Null
    }

    New-ItemProperty -Path $RegAzureAppliancePath -Name AzureCloud -Value $AzureCloudName `
        -Force | Out-Null
    New-ItemProperty -Path $RegAzureAppliancePath -Name Type -Value Physical -Force | Out-Null

    if ( -not (Test-Path $RegAzureCredStorePath)) {
        Log-Info "`tCreating Registry Node: $RegAzureCredStorePath"
        New-Item -Path $RegAzureCredStorePath -Force | Out-Null
    }

    New-ItemProperty -Path $RegAzureCredStorePath -Name CredStoreDefaultPath `
        -Value "%Programdata%\Microsoft Azure\CredStore\Credentials.json" -Force | Out-Null

    Log-Info "`tSetting isSudo property as enabled for Linux VM discovery..."
    New-ItemProperty -Path $RegAzureCredStorePath -Name isSudo -PropertyType "DWord" -Value 1 -Force | Out-Null

    if ($DisableAutoUpdate -eq $true) {
        Log-Info "`tDisabling Auto Update for Azure Migrate..."
        New-ItemProperty -Path $RegAzureCredStorePath -Name AutoUpdate -PropertyType "DWord" -Value 0 -Force | Out-Null
        $global:WarningCount++
        Log-Warning "Warning #$global:WarningCount : Disabling Auto Update is not recomended. To enable Auto Update navigate to https://go.microsoft.com/fwlink/?linkid=2134524. Continuing..."
    }
    else {
        New-ItemProperty -Path $RegAzureCredStorePath -Name AutoUpdate -PropertyType "DWord" -Value 1 -Force | Out-Null
    }

    if ( $?) {
        Log-Success "`n[OK]`n"
    }
    else {
        Log-Error "Failed to add\update registry keys. Aborting..."
        Log-Warning "Please ensure that the current user has access to add\update registry keys under the path: $RegAzureAppliancePath and $RegAzureCredStorePath"
        exit -6
    }
}

<#
.SYNOPSIS
Validate OS version
Usage:
    ValidateOSVersion
#>
function ValidateOSVersion {
    [System.Version]$ver = "0.0"
    [System.Version]$minVer = "10.0"

    Log-Info "Verifying supported Operating System version..."

    $OS = Get-WmiObject Win32_OperatingSystem
    $ver = $OS.Version

    If ($ver -lt $minVer) {
        Log-Error "The os version is $ver, minimum supported version is Windows Server 2016 ($minVer). Aborting..."
        log-Warning "Windows Server Core and Windows client SKUs are not supported."
        exit -7
    }
    elseif ($OS.Caption.contains("Server") -eq $false) {
        Log-Error "OS should be Windows Server 2016. Aborting..."
        log-Warning "Windows Server Core and Windows client SKUs are not supported."
        exit -8
    }
    else {
        Log-Success "[OK]`n"
    }
}

<#
.SYNOPSIS
custom script run after the Windows Setup process.
Usage:
    CreateApplianceVersionFile
#>

function CreateApplianceVersionFile {
    Log-Info "Creating Appliance Version File..."
    $ApplianceVersion = "6." + (Get-Date).ToString('yy.MM.dd')
    $fileContent = "$ApplianceVersion"

    if ([System.IO.File]::Exists($ApplianceVersionFilePath)) {
        Remove-Item -Path $ApplianceVersionFilePath -Force
    }

    # Create Appliance version text file.
    New-Item $ApplianceVersionFilePath -ItemType File -Value $ApplianceVersion -Force | Out-Null
    Set-ItemProperty $ApplianceVersionFilePath -Name IsReadOnly -Value $true

    if ($?) {
        Log-Success "[OK]`n"
    }
    else {
        Log-InfoHighLight "Failed to create Appliance Version file with at $ApplianceVersionFilePath. Continuing..."
    }
}

<#
.SYNOPSIS
Validate and exit if minimum defined PowerShell version is not available.
Usage:
    ValidatePSVersion
#>

function ValidatePSVersion {
    [System.Version]$minVer = "4.0"

    Log-Info "Verifying the PowerShell version to run the script..."

    if ($PSVersionTable.PSVersion) {
        $global:PsVer = $PSVersionTable.PSVersion
    }

    If ($global:PsVer -lt $minVer) {
        Log-Error "PowerShell version $minVer, or higher is required. Current PowerShell version is $global:PsVer. Aborting..."
        exit -11;
    }
    else {
        Log-Success "[OK]`n"
    }
}

<#
.SYNOPSIS
Validate and exit if PS process in not 64-bit as few cmdlets like install-windowsfeature is not available in 32-bit.
Usage:
    ValidateIsPowerShell64BitProcess
#>

function ValidateIsPowerShell64BitProcess {
    Log-Info "Verifying the PowerShell is running in 64-bit mode..."

    # This check is valid for PowerShell 3.0 and higher only.
    if ([Environment]::Is64BitProcess) {
        Log-Success "[OK]`n"
    }
    else {
        Log-Warning "PowerShell process is found to be 32-bit. While launching PowerShell do not select Windows PowerShell (x86) and rerun the script. Aborting..."
        Log-Error "[Failed]`n"
        exit -11;
    }
}

<#
.SYNOPSIS
Ensure IIS backend services are in running state. During IISReset they can remain in stop state as well.
Usage:
    StartIISServices
#>

function StartIISServices {
    Log-Info "Ensuring critical services for Azure Migrate appliance configuration manager are running..."

    Start-Service -Name WAS
    Start-Service -Name W3SVC

    if ($?) {
        Log-Success "[OK]`n"
    }
    else {
        Log-Error "Failed to start services WAS/W3SVC. Aborting..."
        Log-Warning "Manually start the services WAS and W3SVC"
        exit -12
    }
}

<#
.SYNOPSIS
Set Trusted Hosts in the host\current machine.
Usage:
    SetTrustedHosts
#>

function SetTrustedHosts {
    $currentList = Get-Item WSMan:\localhost\Client\TrustedHosts
    Log-Info "The current value of $($currentList.Name) = $($currentList.Value)"

    if ($SkipSettingTrustedHost) {
        $global:WarningCount++
        Log-Warning "Warning #$global:WarningCount : Skipping setting Trusted Host List for WinRM. Please manually set Trusted Host list to Windows hosts/servers that will be accessed from this appliance/machine."
        Log-InfoHighLight "Not specifying workgroup machines in the Trusted Host list leads to Validate-Operation failure during onboarding through Azure Migrate appliance configuration manager. Continuing...`n"

        return
    }

    if ($currentList -ne $null) {
        # Need to add a better than *. * will be used for preview.
        $list = "*"
        Log-Info "Adding $($list) as trusted hosts to the current host machine..."

        Set-Item WSMan:\localhost\Client\TrustedHosts $list.ToString() -Force

        if ($?) {
            Log-Success "[OK]`n"
        }
        else {
            Log-Error "Failure in adding trusted hosts. Aborting..."
            Log-Warning "Please use -SkipSettingTrustedHost flag to skip this step and rerun this script."
            exit -13
        }
    }
    else {
        Log-Error "Unable to get trusted host list. Aborting..."
        exit -13
    }
}

<#
.SYNOPSIS
Uninstall IE as IE is not compatible with Azure Migrate ConfigManager. IE cannot be uninstalled like regular programs.
Usage:
    UninstallInternetExplorer
#>

function UninstallInternetExplorer {
    if ((Get-WindowsOptionalFeature -Online -FeatureName "Internet-Explorer-Optional-amd64").State -eq "Disabled") {
        Log-Info "Internet Explorer has already been uninstalled. Skipping uninstallation and continuing..."
        Log-Success "[OK]`n"

        return
    }

    do {
        Log-InfoHighLight "The latest Azure Migrate appliance configuration manager is not supported on Internet Explorer 11 or lower."
        Log-InfoHighLight "You can either uninstall Internet Explorer using this script and open the appliance URL https://$machineHostName`:44368 on any other browser except Internet Explorer."
        Log-Input "Do you want to remove Internet Explorer browser from this machine now? This will force a machine reboot immediately. Press [Y] to continue with the uninstallation or [N] to manually uninstall Internet Explorer..."
        $userChoice = Read-Host
    }while ("y", "n" -NotContains $userChoice.Trim())

    if ($userChoice.Trim() -eq "n") {
        $global:WarningCount++
        Log-Error "Skipping IE uninstallation..."
        Log-Warning "Warning #$global:WarningCount User Action Required - Remove Internet Explorer as the default browser and then launch Azure Migrate appliance configuration manager using the shortcut placed on the desktop.`n"
    }
    else {
        dism /online /disable-feature /featurename:Internet-Explorer-Optional-amd64 /NoRestart

        # Restart the machine
        shutdown -r -t 60 -f
        Log-Success "[OK]"
        Log-InfoHighLight 'Restarting machine $machineHostName in 60 seconds. To abort this restart execute "shutdown /a" - Not Recommended.'

        # Exit the script as restart is pending.
        exit 0
    }
}

<#
.SYNOPSIS
Install New Edge Browser.
Usage:
    InstallEdgeBrowser
#>

function InstallEdgeBrowser {
    $edgeInstallerFilePath = ""

    if ( Test-Path -Path "HKLM:\SOFTWARE\Clients\StartMenuInternet\Microsoft Edge") {
        Log-Info "New Edge browser is already installed. Skipping installation and continuing..."
        Log-Success "[OK]`n"
        return
    }

    do {
        Log-InfoHighLight "The latest Azure Migrate appliance configuration manager is not supported on Internet Explorer 11 or lower. So you would need to install any of these browsers to continue with appliance configuration manager -Edge (latest version), Chrome (latest version), Firefox (latest version)."
        Log-Input "Do you want to install New Edge browser now (highly recomended)? [Y/N] - You may skip Edge browser installation (select 'N') in case you are already using a browser from the above list:"
        $userChoice = Read-Host
    }while ("y", "n" -NotContains $userChoice.Trim())

    if ($userChoice.Trim() -eq "n") {
        $global:WarningCount++
        Log-Error "Skipping Microsoft Edge browser installation..."
        Log-Warning "Warning #$global:WarningCount User Action Required - Install the Edge browser manually or use a browser from the above list.`n"
        return
    }
    else {
        $regHive = "HKLM:\Software\Policies\Microsoft\Edge"
        if ( -not (Test-Path $regHive)) {
            New-Item -Path $regHive -Force
        }

        New-ItemProperty -Path $regHive -Name "HideFirstRunExperience" -PropertyType "dword" -Value 1 -Force | Out-Null

        if ($global:SelectedPEEnabled -eq $true) {
            Log-Info "`nInstalling the Microsoft Edge using offline installer."
            $edgeInstallerFilePath = "$PSScriptRoot\MicrosoftEdgeEnterpriseX64.msi"
            $process = Start-Process -Wait -PassThru -FilePath msiexec -ArgumentList "/i `"$edgeInstallerFilePath`" /quiet /lv `"$Env:ProgramData\Microsoft Azure\Logs\MicrosoftEdgex64Enterprise.log`""
        }
        else {
            Log-Info "`nDownloading and installing the latest Microsoft Edge."
            $edgeInstallerFilePath = "$PSScriptRoot\MicrosoftEdgeSetup.exe"
            $process = Start-Process -Wait -PassThru -FilePath `"$edgeInstallerFilePath`"
        }

        $returnCode = $process.ExitCode;
        if ($returnCode -eq 0 -or $returnCode -eq 3010) {
            $edgeShortCut = "$env:SystemDrive`\Users\Public\Desktop\Microsoft Edge.lnk"
            if (Test-Path $edgeShortCut) {
                Remove-Item -Path $edgeShortCut -Force | Out-Null
            }

            Log-Info "Set the new Microsoft Edge browser as the default browser manually to open Azure Migrate Appliance Configuration Manager with URL https://$machineHostName`:44368 next time onwards..."
            Log-Info "Microsoft Edge installation completed successfully on $machineHostName machine."
            Log-Success "[OK]`n"

        }
        else {
            $global:WarningCount++
            Log-Error "$edgeInstallerFilePath installation failed on $machineHostName machine with errorcode: $returnCode."
            Log-Warning "Warning #$global:WarningCount User Action Required - Manually download and install Microsoft Edge browser manually from the location: https://www.microsoft.com/en-us/edge/business/download. Continuing...`n"
        }
    }
}

#region - Detect user intent

<#
.SYNOPSIS
Detect fabric value from parameter/preset file/user input.
Usage:
    DetectFabric -presetJsonContent $presetJsonContent
#>

function DetectFabric {
    param(
        $presetJsonContent
    )

    $scenarioText = "Physical or other (AWS, GCP, Xen, etc.)"
    $scenarioSubText = "Unknown"
    $scenarioSubTextForHyperV = "discover and assess the servers running in your Hyper-V environment"
    $scenarioSubTextForPhysical = "discover and assess the servers running as $scenarioText"
    $scenarioSubTextForVMware = "discover, assess and migrate the servers running in your VMware environment"
    $expectedScenarioList = "HyperV", "Physical", "VMware", "VMwareV2"
    $scenarioSwitch = "Unknown"
    $selectionMode = ""

    if ($Scenario) {
        $scenarioSwitch = $Scenario
    }
    elseif ($presetJsonContent.Scenario -and $expectedScenarioList -contains $presetJsonContent.Scenario.Trim()) {
        $scenarioSwitch = $presetJsonContent.Scenario.Trim()
        $selectionMode = "(preconfigured)"
    }
    else {
        do {
            Log-Info "1. VMware `n2. Hyper-V `n3. $scenarioText"
            Log-Input "Please enter the option for desired scenario [1, 2 or 3]:"
            $scenarioSwitch = Read-Host
            $scenarioSwitch = $scenarioSwitch.Trim()
            Log-InfoHighLight ""

            if ("1", "2", "3" -NotContains $scenarioSwitch) {
                Log-Error "[Incorrect input]"
                Log-Warning "Supported options are: 1, 2 or 3 only. Please try again...`n"
                continue
            }

            break
        }while ($true)
    }

    switch ($scenarioSwitch) {
        { $_ -eq 1 -or $_ -eq "VMware" -or $_ -eq "VMwareV2" } {
            $global:SelectedFabricType = $scenarioText = "VMware"
            $scenarioSubText = $scenarioSubTextForVMware
            break
        }

        { $_ -eq 2 -or $_ -eq "HyperV" } {
            $global:SelectedFabricType = $scenarioText = "HyperV"
            $scenarioSubText = $scenarioSubTextForHyperV
            break
        }

        { $_ -eq 3 -or $_ -eq "Physical" } {
            #$scenarioText = Already Initialized
            $global:SelectedFabricType = "Physical"
            $scenarioSubText = $scenarioSubTextForPhysical
            break
        }

        default {
            Log-Error "Unexpected Scenario option. $selectionMode Aborting..."
            Log-Warning "Know more about the supported scenarios for Azure Migrate: https://go.microsoft.com/fwlink/?linkid=2164248"
            exit -1
        }
    }

    Log-Info "Selected scenario: $global:SelectedFabricType $selectionMode"
    Log-Success "[OK]`n"

    return $scenarioText, $scenarioSubText
}

<#
.SYNOPSIS
Detect Cloud value from parameter/preset file/user input.
Usage:
    DetectCloud -presetJsonContent $presetJsonContent
#>

function DetectCloud {
    param(
        $presetJsonContent
    )

    $cloudSwitch = "Unknown"
    $expectedCloudList = "Public", "Azure Public", "USGov", "USNat", "USSec", "AzureChina", "Azure China", "CNProd"
    $selectionMode = ""
    $cloudTypeText = ""

    if ($Cloud) {
        $cloudSwitch = $Cloud
    }
    elseif ($presetJsonContent.Cloud -and $expectedCloudList -contains $presetJsonContent.Cloud.Trim()) {
        $cloudSwitch = $presetJsonContent.Cloud.Trim()
        $selectionMode = "(preconfigured)"
    }
    else {
        do {
            log-info "1. Azure Public `n2. Azure US Government" #`n3. Azure China"
            Log-Input "Please enter the option for desired cloud [1 or 2]:"
            $cloudSwitch = Read-Host
            $cloudSwitch = $cloudSwitch.Trim()
            Log-InfoHighLight ""

            if ("1", "2" -NotContains $cloudSwitch) {
                Log-Error "[Incorrect input]"
                Log-Warning "Supported options are: 1 or 2 only. Please try again...`n"
                continue
            }

            break
        }while ($true)
    }

    switch ($cloudSwitch) {
        { $_ -eq 1 -or $_ -eq "Public" -or $_ -eq "Azure Public" } {
            $global:SelectedCloud = "Public"
            $cloudTypeText = "Azure Public"
        }

        { $_ -eq 2 -or $_ -eq "USGov" } {
            $global:SelectedCloud = "USGov"
            $cloudTypeText = "Azure US Government"
        }

        { $_ -eq "USNat" } {
            $global:SelectedCloud = "USNat"
            $cloudTypeText = "USNat"
        }

        { $_ -eq "USSec" } {
            $global:SelectedCloud = "USSec"
            $cloudTypeText = "USSec"
        }
        { $_ -eq 3 -or $_ -eq "CNProd" -or $_ -eq "AzureChina" -or $_ -eq "Azure China" } {
            $global:SelectedCloud = "AzureChina"
            $cloudTypeText = "Azure China"
        }

        default {
            Log-Error "Unexpected Cloud option. $selectionMode Aborting..."
            Log-Warning "Know more about the supported clouds for Azure Migrate: https://go.microsoft.com/fwlink/?linkid=2164248"
            exit -1
        }
    }

    Log-Info "Selected cloud: $cloudTypeText $selectionMode"
    Log-Success "[OK]`n"

    return $cloudTypeText
}

<#
.SYNOPSIS
Detect Appliance type (Primary/ScaleOut) from parameter/preset file/user input.
Usage:
    DetectApplianceType -presetJsonContent $presetJsonContent
#>

function DetectApplianceType {
    param(
        $presetJsonContent
    )

    $applianceUnit = "primary"
    $applianceTypeSwitch = "Unknown"
    $expectedBooleanValue = "False", "True"
    $selectionMode = ""

    if ($global:ParameterList.ContainsKey("ScaleOut")) {
        $applianceTypeSwitch = $ScaleOut
    }
    elseif ($presetJsonContent.ScaleOut -and $expectedBooleanValue -contains $presetJsonContent.ScaleOut.Trim()) {
        $applianceTypeSwitch = $presetJsonContent.ScaleOut.Trim()
        $selectionMode = "(preconfigured)"
    }
    else {
        if ($global:SelectedFabricType -ne "vmware") {
            $global:SelectedScaleOut = "false"
            return $applianceUnit
        }

        do {
            Log-Info "1. Primary appliance to discover, assess and migrate servers"
            Log-Info "2. Scale-out appliance to replicate more servers concurrently"
            Log-InfoHighLight "Know more about the scale-out capability for migration: https://go.microsoft.com/fwlink/?linkid=2151823"
            Log-Input "Please enter the option for desired configuration [1 or 2]:"
            $applianceTypeSwitch = Read-Host
            $applianceTypeSwitch = $applianceTypeSwitch.Trim()
            Log-InfoHighLight ""

            if ("1", "2" -NotContains $applianceTypeSwitch) {
                Log-Error "[Incorrect input]"
                Log-Warning "Supported options are: 1 or 2 only. Please try again...`n"
                continue
            }

            break;
        }while ($true)
    }

    switch ($applianceTypeSwitch) {
        { $_ -eq 1 -or $_ -eq $false -or $_ -eq "false" } {
            $global:SelectedScaleOut = "False"
            $applianceTypeText = "Selected configuration: This appliance will be setup as a primary appliance $selectionMode"
            $applianceUnit = "primary"
        }

        { $_ -eq 2 -or $_ -eq $true -or $_ -eq "true" } {
            $global:SelectedScaleOut = "True"
            $applianceTypeText = "Selected configuration: This appliance will be setup to scale-out migrations $selectionMode"
            $applianceUnit = "scale-out"
        }

        default {
            Log-Error "Unexpected Appliance type. Aborting..."
            Log-Warning "Know more about the scale-out capability for migration: https://go.microsoft.com/fwlink/?linkid=2151823"
            exit -1
        }
    }

    if ($global:SelectedFabricType -ne "VMware" -and $global:SelectedScaleOut -eq "true") {
        Log-Error "Only VMware scenario is supported with scale-out capability. Aborting..."
        Log-Warning "Please execute the script again. Know more about how to execute a script with parameters: https://go.microsoft.com/fwlink/?linkid=2164248`n"
        exit -1
    }
    else {
        Log-Info $applianceTypeText
        Log-Success "[OK]`n"
    }

    return $applianceUnit
}

<#
.SYNOPSIS
Detect cloud access type (Public/Private link) from parameter/preset file/user input.
Usage:
    DetectCloudAccessType -presetJsonContent $presetJsonContent
#>

function DetectCloudAccessType {
    param(
        $presetJsonContent
    )

    $cloudAccessType = "public"
    $cloudAccessTypeSwitch = "Unknown"
    $expectedBooleanValue = "False", "True"
    $selectionMode = ""

    if ($global:SelectedCloud -eq "AzureChina") {
        #Azure China has only public endpoint support.
        $cloudAccessTypeSwitch = "false"
    }
    elseif ($global:ParameterList.ContainsKey("PrivateEndpoint")) {
        $cloudAccessTypeSwitch = $PrivateEndpoint
    }
    elseif ($presetJsonContent.PrivateEndpoint -and $expectedBooleanValue -contains $presetJsonContent.PrivateEndpoint.Trim()) {
        $cloudAccessTypeSwitch = $presetJsonContent.PrivateEndpoint.Trim()
        $selectionMode = "(preconfigured)"
    }
    else {
        do {
            Log-Info "1. Set up an appliance for a Migrate project created with default (public endpoint) connectivity"
            Log-Info "2. Set up an appliance for a Migrate project created with private endpoint connectivity"
            Log-InfoHighLight "Know more about the private endpoint connectivity: https://go.microsoft.com/fwlink/?linkid=2155739"
            Log-Input "Please enter the option for desired configuration [1 or 2]:"
            $cloudAccessTypeSwitch = Read-Host
            $cloudAccessTypeSwitch = $cloudAccessTypeSwitch.Trim()
            Log-InfoHighLight ""

            if ("1", "2" -NotContains $cloudAccessTypeSwitch) {
                Log-Error "[Incorrect input]"
                Log-Warning "Supported options are: 1 or 2 only. Please try again...`n"
                continue
            }

            break;
        }while ($true)
    }

    switch ($cloudAccessTypeSwitch) {
        { $_ -eq 1 -or $_ -eq $false -or $_ -eq "false" } {
            $global:SelectedPEEnabled = "false"
            $cloudAccessTypeText = "Selected connectivity: This appliance will be configured for the default (Public endpoint) connectivity $selectionMode"
            $cloudAccessType = "default (public endpoint)"
        }

        { $_ -eq 2 -or $_ -eq $true -or $_ -eq "true" } {
            $global:SelectedPEEnabled = "true"
            $cloudAccessTypeText = "Selected connectivity: This appliance will be optimized for private endpoint connectivity $selectionMode"
            $cloudAccessType = "private endpoint"
        }

        default {
            Log-Error "Unexpected cloud access type. Aborting..."
            Log-Warning "Know more about the private endpoint connectivity: https://go.microsoft.com/fwlink/?linkid=2155739"
            exit -1
        }
    }

    Log-Info $cloudAccessTypeText
    Log-Success "[OK]`n"

    return $cloudAccessType
}

<#
.SYNOPSIS
Detect presets for various parameters.
Usage:
    DetectPresets
#>

function DetectPresets {
    $presetFilePath = "$PSScriptRoot\Preset.json"
    $applianceUnit = "primary"
    $AccessType = "public"
    [string] $userChoice = "y"

    if (Test-Path $ApplianceJsonFilePath) {
        $applianceJsonContent = Get-Content $ApplianceJsonFilePath | Out-String | ConvertFrom-Json

        if ($applianceJsonContent.IsApplianceRegistered.ToLower() -eq "true") {
            $global:SelectedCloud = $applianceJsonContent.Cloud

            if ($applianceJsonContent.FabricType -like "vmware*") {
                # Handle VMwareV2 to VMware name conversion
                $global:SelectedFabricType = "VMware"
            }
            else {
                $global:SelectedFabricType = $applianceJsonContent.FabricType
            }

            if ($applianceJsonContent.ScaleOut -eq "true") {
                $applianceUnit = "scale-out"
                $global:SelectedScaleOut = "True"
            }

            if ($applianceJsonContent.PrivateEndpointEnabled -eq "true") {
                $AccessType = "private"
                $global:SelectedPEEnabled = "True"
            }

            # This machine has been already registered as an Azure Migrate appliance
            $global:ReuseScenario = 1

            do {
                # Skip the confirmation
                if ($Repurpose.IsPresent -or $UpgradeAgents.IsPresent) {
                    $userChoice = "y"
                    break
                }

                Log-Error "This host $machineHostName has already been registered as a $applianceUnit Azure Migrate appliance with Migrate Project on $global:SelectedCloud cloud for $global:SelectedFabricType scenario with $AccessType endpoint connectivity. If you choose to proceed, configuration files from the previous installation will be lost permanently."
                Log-Input "Enter [Y] to continue or [N] to abort:"
                $userChoice = Read-Host
                Log-InfoHighLight ""
            }while ("y", "n" -NotContains $userChoice.Trim())
        }

        if ($userChoice.Trim() -eq "n") {
            Log-Error "You have chosen to exit. Aborting..."
            Log-Warning "Know more about how to execute a script with parameters: https://go.microsoft.com/fwlink/?linkid=2164248"
            exit -1
        }
    }

    if ($UpgradeAgents.IsPresent) {
        if ($global:ReuseScenario -eq 0) {
            Log-Error "This host $machineHostName has not been registered as an Azure Migrate appliance. 'UpgradeAgents' parameter is not supported in this state. Aborting..."
            Log-Warning "Please execute the script again. Know more about how to execute a script with parameters: https://go.microsoft.com/fwlink/?linkid=2164248"
            exit -15
        }
        else {
            return
        }
    }
    else {
        # [Optional] Clean up global options
        $global:SelectedFabricType = $global:DefaultStringVal
        $global:SelectedCloud = $global:DefaultStringVal
        $global:SelectedScaleOut = "False"
        $global:SelectedPEEnabled = "False"
    }

    if ($RemoveAzMigrate -eq $true) {
        # Do nothing.
        return
    }

    if ([System.IO.File]::Exists($presetFilePath)) {
        Log-Info "Attempting to read mandatory parameters from the preset file: $presetFilePath."

        try {
            $presetJsonContent = Get-Content $presetFilePath | Out-String | ConvertFrom-Json
        }
        catch {
            Log-Error "Unable to read the preset file due to error: $_"
            Log-Warning "Retry executing the script after resolving this issue or removing the preset file.`n"
            exit -1
        }

        Log-Success "[OK]`n"
    }

    $scenarioText, $scenarioSubText = DetectFabric($presetJsonContent)
    $cloudTypeText = DetectCloud($presetJsonContent)
    $applianceUnit = DetectApplianceType($presetJsonContent)
    $cloudAccessType = DetectCloudAccessType($presetJsonContent)

    if ($scenarioText -contains "VMware" -and $global:SelectedScaleOut -eq "True") {
        $message = "You have chosen to set up a $applianceUnit appliance to initiate concurrent replications on servers in your VMware environment to an Azure Migrate project with $cloudAccessType connectivity on $cloudTypeText cloud."
    }
    else {
        $message = "You have chosen to set up an appliance to $scenarioSubText to an Azure Migrate project with $cloudAccessType connectivity on $cloudTypeText cloud."
    }

    Log-InfoHighLight $message

    do {
        Log-Info "If this is not the desired configuration to set up the appliance, you can abort and execute the script again."
        Log-Input "Enter [Y] to continue with the deployment or [N] to abort:"
        $userChoice = Read-Host
        Log-InfoHighLight ""
    }while ("y", "n" -NotContains $userChoice.Trim())

    Log-InfoHighLight ""
    if ($userChoice.Trim() -eq "n") {
        Log-Error "You have chosen to exit. Aborting..."
        Log-Warning "Know more about how to execute a script with parameters: https://go.microsoft.com/fwlink/?linkid=2164248"
        exit 0
    }
}

#endregion

<#
.SYNOPSIS
Install Gateway service.
Usage:
    InstallGatewayService -$gatewayPackagerPath "$$gatewayPackagerPath" -$MSIInstallLogName "ToDo"
#>

function InstallGatewayService {
    param(
        [string] $gatewayPackagerPath,
        [string] $MSIInstallLogName
    )

    [int]$maxRetryLimit = 5
    [int]$retryCount = 0
    [string]$filePath = "$PSScriptRoot\GATEWAYSETUPINSTALLER.EXE"

    $extractCmd = "`"$gatewayPackagerPath`"" + " /q /x:`"$PSScriptRoot`""

    Log-Info "Extracting and Installing Gateway Service..."

    while ($maxRetryLimit -gt $retryCount) {
        $Error.Clear()

        Invoke-Expression "& $extractCmd"
        Start-Sleep -Seconds 5

        $process = (Start-Process -Wait -PassThru -FilePath "$filePath" -ArgumentList "CommandLineInstall ")
        $returnCode = $process.ExitCode;

        if ($returnCode -eq 0 -or $returnCode -eq 3010) {
            Log-Success "[OK]`n"
            return
        }
        else {
            $retryCount++
            Log-InfoHighLight "$filePath installation failed with $returnCode."
            Log-Warning "Retry attempt #$retryCount of #$maxRetryLimit.`n"
            Start-Sleep -Seconds 10
        }
    }

    Log-Error "Gateway service installation failed. Aborting..."
    Log-Warning "Please refer to http://www.msierrors.com/ to get details about the error code: $returnCode. Please share the installation log file NONAME while contacting Microsoft Support."
    exit -16
}

<#
.SYNOPSIS
Validate if Replication Appliance (ASR) component is installed on this host machine
Usage:
    ValidateRepAppliance -ProgramName
#>
function ValidateRepAppliance {
    param(
        [string] $programName
    )

    [bool] $x86_check = $False
    [bool] $x64_check = $False

    Log-Info "Verifying that no replication appliance/Azure Site Recovery components are already installed on this host..."

    try {
        $x86_check = ((Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*) | Where-Object { $_."DisplayName" -like "*$programName*" } ).DisplayName.Length -gt 0;
        # ASR doesn't install x64 components hence the check is not being performed.
        #$x64_check = ((Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*) | Where-Object { $_."DisplayName" -like "*$programName*" } ).DisplayName.Length -gt 0;

        If ($x86_check -eq $true) {
            Log-Error "Replication appliance/Azure Site Recovery component(s) ‘$programName’ is already installed on this host. Aborting..."
            Log-Warning "Please use another host to set up the Azure Migrate appliance or remove the existing Replication appliance/Azure Site Recovery component(s) from this host and execute the script again."
            exit -1
        }
        else {
            Log-Success "[OK]`n"
        }
    }
    catch {
        Log-Error "[Failed to verify]"
        Log-InfoHighLight "Error Record: $_.Exception.ErrorRecord"
        Log-InfoHighLight "Exception caught:  $_.Exception"
        Log-Warning "Continuing with the script execution..."
        $Error.Clear()
    }
}

<#
.SYNOPSIS
Increase the maxenvelopsize from default 500KB to a higher size.
This is essential for WMI calls to get cluster resources.
Usage:
    IncreaseWSManPayloadSize
#>

function IncreaseWSManPayloadSize {
    $MaxWSManPayloadSizeKB = 10240
    Log-Info "Increasing the maxenvelopsize from 500KB to 10MB..."

    Set-Item -Path WSMan:\localhost\MaxEnvelopeSizeKb -Value $MaxWSManPayloadSizeKB

    if ($?) {
        Log-Success "[OK]`n"
    }
    else {
        Log-Error "Failure in increasing WSMan envelope size. Aborting..."
        exit -13
    }
}

#region - Main
try {
    $Error.Clear()

    # Validate PowerShell, OS version and user role.
    ValidatePSVersion
    ValidateIsPowerShell64BitProcess
    ValidateOSVersion

    # Check if any of the ASR component is not installed on this machine.
    ValidateRepAppliance("Microsoft Azure Site Recovery Configuration/Process Server")

    # Detect the presets to know what needs to be installed.
    DetectPresets

    # Detect and take user intent to cleanup previous installation if found.
    DetectAndCleanupPreviousInstallation

    # Add the required registry keys.
    AddingRegistryKeys

    # Enable IIS.
    EnableIIS

    # Set trusted hosts to machine.
    SetTrustedHosts

    ## Increase WSMan Payload Size.
    IncreaseWSManPayloadSize

    # Install Discovery, Assessment and MIgration agents based on the scenario .
    switch ($global:SelectedFabricType) {
        HyperV {
            $ApplianceJsonFileData.FabricType = "HyperV"
            InstallMSI -MSIFilePath "$PSScriptRoot\$HyperVDiscoveryServiceMSI" `
                -MSIInstallLogName $DiscoveryServiceMSILog
            InstallMSI -MSIFilePath "$PSScriptRoot\$HyperVAssessmentServiceMSI" `
                -MSIInstallLogName $AssessmentServiceMSILog
        }
        Physical {
            $ApplianceJsonFileData.FabricType = "Physical"
            InstallMSI -MSIFilePath "$PSScriptRoot\$ServerDiscoveryServiceMSI" `
                -MSIInstallLogName $DiscoveryServiceMSILog
            InstallMSI -MSIFilePath "$PSScriptRoot\$ServerAssessmentServiceMSI" `
                -MSIInstallLogName $AssessmentServiceMSILog
        }
        VMware {
            $ApplianceJsonFileData.FabricType = "VMwareV2"
            $ApplianceJsonFileData.VddkInstallerFolder = "%programfiles%\\VMware\\VMware Virtual Disk Development Kit";

            if ($global:SelectedScaleOut -eq "False") {
                InstallMSI -MSIFilePath "$PSScriptRoot\$VMwareDiscoveryServiceMSI" `
                    -MSIInstallLogName $DiscoveryServiceMSILog
                InstallMSI -MSIFilePath "$PSScriptRoot\$VMwareAssessmentServiceMSI" `
                    -MSIInstallLogName $AssessmentServiceMSILog
                InstallMSI -MSIFilePath "$PSScriptRoot\$SQLServiceMSI" `
                    -MSIInstallLogName $SQLServiceMSILog

                InstallMSI -MSIFilePath "$PSScriptRoot\$WebAppMSI" `
                    -MSIInstallLogName $WebAppMSILog
                <#InstallMSI -MSIFilePath "$PSScriptRoot\$AppCompatMSI" `
                    -MSIInstallLogName $AppCompatMSILog -OptionalComponent
                #>

                InstallMSI -MSIFilePath "$PSScriptRoot\$DraMsiName" `
                    -MSIInstallLogName $DraMsiLog
            }
            else {
                $ApplianceJsonFileData.ScaleOutCapabilities = "0"
            }

            # LogFilePath needs to be added.
            InstallGatewayService "$PSScriptRoot\$GatewayExeName" ""
        }
        default {
            Log-Error "Unexpected Scenario selected:$global:SelectedFabricType. Aborting..."
            Log-Warning "Please retry the script with -Scenario parameter."
            exit -20
        }
    }

    # Install Appliance Configuration Manager
    $ApplianceJsonFileData.Cloud = $global:SelectedCloud
    $ApplianceJsonFileData.ScaleOut = $global:SelectedScaleOut
    $ApplianceJsonFileData.PrivateEndpointEnabled = $global:SelectedPEEnabled;
    CreateJsonFile -JsonFileData $ApplianceJsonFileData -JsonFilePath $ApplianceJsonFilePath
    InstallMSI -MSIFilePath "$PSScriptRoot\$ConfigManagerMSI" -MSIInstallLogName $ConfigManagerMSILog

    # Client SKU has BasicAuthentication disabled by default
    Set-WebConfigurationProperty -Filter '/system.webServer/security/authentication/basicAuthentication' -Name enabled -Value true -PSPath 'IIS:\' -Location "Microsoft Azure Appliance Configuration Manager"
    Set-WebConfigurationProperty -Filter '/system.web/trust' -Name "level" -Value "Full" -PSPath "IIS:\sites\Microsoft Azure Appliance Configuration Manager"

    # Install Agent updater.
    $AutoUpdaterJsonFileData.Cloud = $global:SelectedCloud
    CreateJsonFile -JsonFileData $AutoUpdaterJsonFileData -JsonFilePath $AutoUpdaterJsonFilePath
    InstallMSI -MSIFilePath "$PSScriptRoot\$AutoUpdaterMSI" -MSIInstallLogName $AutoUpdaterMSILog

    # Custom script for IIS bindings and launch UI.
    CreateApplianceVersionFile

    # Ensure critical services for ConfigManager are in running state.
    StartIISServices

    # Execute WebBinding scripts
    if (-Not (Test-Path -Path "$PSScriptRoot\WebBinding.ps1" -PathType Any)) {
        Log-Error "Script file not found: `"$PSScriptRoot\WebBinding.ps1`". Aborting..."
        Log-Warning "Please download the package again and retry."
        exit -9
    }
    else {
        Log-Info "Running powershell script `"$PSScriptRoot\WebBinding.ps1`"..."
        & "$PSScriptRoot\WebBinding.ps1" | Out-Null
        if ($?) {
            Log-Success "[OK]`n"
        }
        else {
            Log-Error "Script execution failed. Aborting..."
            Log-Warning "Please download the package again and retry."
            exit -9
        }
    }

    # Execute SetRegistryForTrustedSites scripts
    if (-Not (Test-Path -Path "$PSScriptRoot\SetRegistryForTrustedSites.ps1" -PathType Any)) {
        Log-Error "Script file not found: `"$PSScriptRoot\SetRegistryForTrustedSites.ps1`". Aborting..."
        Log-Warning "Please download the package again and retry."
        exit -9
    }
    else {
        Log-Info "Running powershell script `"$PSScriptRoot\SetRegistryForTrustedSites.ps1`" with argument '-LaunchApplication $false'..."
        & "$PSScriptRoot\SetRegistryForTrustedSites.ps1" -LaunchApplication $false | Out-Null

        if ($?) {
            Log-Success "[OK]`n"
        }
        else {
            Log-Error "Script execution failed. Aborting..."
            Log-Warning "Please download the installer package again and retry."
            exit -9
        }
    }

    # Install Edge Browser and uninstall IE
    InstallEdgeBrowser
    UninstallInternetExplorer

    if ($global:WarningCount -gt 0) {
        Log-Success "Installation completed with warning(s)."
        Log-Warning "Please review the $global:WarningCount warning(s) hit during script execution and take manual corrective action as suggested in the warning(s) before using Azure Migrate appliance configuration manager."
        Log-Info "You can scroll up to view the warning(s). The warning messages appear in YELLOW coloured text."
        Start-Sleep -Seconds 10
    }
    else {
        Log-Success "Installation completed successfully. Launching Azure Migrate appliance configuration manager to start the onboarding process..."
        Start-Process $DefaultURL
    }

    Log-InfoHighLight "`nYou may use the shortcut placed on the desktop to manually launch `"Azure Migrate appliance configuration manager`"."
}
catch {
    Log-Error "`n[Script execution failed with error] $_"
    Log-Error "[Exception caught] $_.Exception"
    Log-Warning "Retry executing the script after resolving the issue(s) or contact Microsoft Support."
    exit -1
}

#endregion
# SIG # Begin signature block
# MIIjewYJKoZIhvcNAQcCoIIjbDCCI2gCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBckoW3+6y/nVhd
# qWzIb6QfZaNODd9pr7aUXVnuVmeNPKCCDXYwggX0MIID3KADAgECAhMzAAAB3vl+
# gOdHKPWkAAAAAAHeMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjAxMjE1MjEzMTQ0WhcNMjExMjAyMjEzMTQ0WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQC42o7GuqPBrC9Z9N+JtpXANgk2m77zmZSuuBKQmr5pZRmQCht/u/V21N5nwBWK
# NGwCZNdI98dyYGYORRZgrMOh8JWxDBjLMQYtqklGLw5ZPw3OCGCIM2ZU0snDlvZ3
# nKwys5NtPlY4shJxcVM2dhMnXhRTqvtexmeWpfmvtiop7jJn2Sdq0iDybDyU2vMz
# nH2ASetgjvuW2eP4d6zQXlboTBBu1ZxTv/aCRrWCWUPge8lHr3wtiPJHMyxmRHXT
# ulS2VksZ6iI9RLOdlqup9UOcnKRaj1usJKjwADu75+fegAZ4HPWSEXXmpBmuhvbT
# Euwa04eiL7ZKbG3mY9EqpiJ7AgMBAAGjggFzMIIBbzAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUbrkwVx/G26M/PsNzHEotPDOdBMcw
# RQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEW
# MBQGA1UEBRMNMjMwMDEyKzQ2MzAwODAfBgNVHSMEGDAWgBRIbmTlUAXTgqoXNzci
# tW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3JsMGEG
# CCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3J0
# MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBAHBTJKafCqTZswwxIpvl
# yU+K/+9oxjswaMqV+yGkRLa7LDqf917yb+IHjsPphMwe0ncDkpnNtKazW2doVHh3
# wMNXUYX6DzyVg1Xr/MTYaai0/GkPR/RN4MSBfoVBDzXJSisnYEWlK1TbI1J1mNTU
# iyiaktveVsH3xQyOVXQEpKFW17xYoHGjYm8s5v22mRE/ShVgsEW9ckxeQbJPCkPc
# PiqD4eXwPguTxv06Pwxva8lsjsPDvo2EgwozBCNGRAxsv2pEl0bh+yOtaFpfQWG7
# yMskiLQwWWoWFyuzm6yiKmZ/jdfO98xR1bFUhQMdwQoMi0lCUMx6YQJj1WpNUTDq
# X0ttJGny2aPWsoOgZ5fzKHNfCowOA+7hLc6gCVRBzyMN/xvV19aKymPt8I/J5gqA
# ZCQT19YgNKyhHUYS4GnFyMr/0GCezE8kexDGeQ3JX1TpHQvcz/dghK30fWM9z44l
# BjNcMV/HtTuefSFsr9tCp53wVaw65LudxSjH+/a2zUa85KKCBzj/GU4OhDaa5Wd4
# 8jr0JSm/515Ynzm1Xje5Ai/qo9xaGCrjrVcJUxBXd/SZPorm3HN6U1aJnL2Kw6nY
# 8Rs205CIWT28aFTecMQ6+KnMt1NZR4pogBnnpWSLc92JMbUd1Z6IbauU6U/oOjyl
# WOtkYUKbyE7EvK9GwUQXMds/MIIHejCCBWKgAwIBAgIKYQ6Q0gAAAAAAAzANBgkq
# hkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5
# IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEwOTA5WjB+MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYDVQQDEx9NaWNyb3NvZnQg
# Q29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIIC
# CgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+laUKq4BjgaBEm6f8MMHt03
# a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc6Whe0t+bU7IKLMOv2akr
# rnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4Ddato88tt8zpcoRb0Rrrg
# OGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+lD3v++MrWhAfTVYoonpy
# 4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nkkDstrjNYxbc+/jLTswM9
# sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6A4aN91/w0FK/jJSHvMAh
# dCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmdX4jiJV3TIUs+UsS1Vz8k
# A/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL5zmhD+kjSbwYuER8ReTB
# w3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zdsGbiwZeBe+3W7UvnSSmn
# Eyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3T8HhhUSJxAlMxdSlQy90
# lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS4NaIjAsCAwEAAaOCAe0w
# ggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRIbmTlUAXTgqoXNzcitW2o
# ynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYD
# VR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBDuRQFTuHqp8cx0SOJNDBa
# BgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2Ny
# bC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3JsMF4GCCsG
# AQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3J0MIGfBgNV
# HSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEFBQcCARYzaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1hcnljcHMuaHRtMEAGCCsG
# AQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkAYwB5AF8AcwB0AGEAdABl
# AG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn8oalmOBUeRou09h0ZyKb
# C5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7v0epo/Np22O/IjWll11l
# hJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0bpdS1HXeUOeLpZMlEPXh6
# I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/KmtYSWMfCWluWpiW5IP0
# wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvyCInWH8MyGOLwxS3OW560
# STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBpmLJZiWhub6e3dMNABQam
# ASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJihsMdYzaXht/a8/jyFqGa
# J+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYbBL7fQccOKO7eZS/sl/ah
# XJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbSoqKfenoi+kiVH6v7RyOA
# 9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sLgOppO6/8MO0ETI7f33Vt
# Y5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtXcVZOSEXAQsmbdlsKgEhr
# /Xmfwb1tbWrJUnMTDXpQzTGCFVswghVXAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAAHe+X6A50co9aQAAAAAAd4wDQYJYIZIAWUDBAIB
# BQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEILc14ncZ4Rkrt6XodaO24jkP
# BvW23wf2LlphXMyYgeFHMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8A
# cwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
# BQAEggEAJwbo42VDaRJ1DH2LaGeqEvPnbfOe3R2LgoNQ2uBVYyyjRVyQ2vGcU1gG
# qdTisqGPtMjOquweMDye7BhksZqDU3sxCSyQgvUNwxSFC2WTjxsk0yELXfbGJdJv
# OXDOVebWVpHgfAvOYBv8A4OCRSv8ZhzGnfcukwCR4m89R5R2xc3lRIdRMDjqH2H3
# aOJkOl1/IOluq75ccTsB0+NSa+I5cqwSd++YGnTF2uqDliTFHFC9+qUESUyA73gs
# +Yp4lMo4Pqkp8qYgLTUTIZOPkSJL8qX3Cu4wyn91IA020dXnIEzvmpDj3XKg/lnk
# ylPHHFKqPtXdlX8nrwC5oEzgTrRvhKGCEuUwghLhBgorBgEEAYI3AwMBMYIS0TCC
# Es0GCSqGSIb3DQEHAqCCEr4wghK6AgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFRBgsq
# hkiG9w0BCRABBKCCAUAEggE8MIIBOAIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFl
# AwQCAQUABCCkTuNi+oXENaVBp6sbtt8lOk+G+QlwO17SlAmTakrwGAIGYXny0TMY
# GBMyMDIxMTAyOTEzMjYzMy4wNTNaMASAAgH0oIHQpIHNMIHKMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1l
# cmljYSBPcGVyYXRpb25zMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjpERDhDLUUz
# MzctMkZBRTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCC
# DjwwggTxMIID2aADAgECAhMzAAABToyx6+3XsuMAAAAAAAFOMA0GCSqGSIb3DQEB
# CwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
# BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTIwMTExMjE4MjYw
# MVoXDTIyMDIxMTE4MjYwMVowgcoxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMx
# JjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOkREOEMtRTMzNy0yRkFFMSUwIwYDVQQD
# ExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIIBIjANBgkqhkiG9w0BAQEF
# AAOCAQ8AMIIBCgKCAQEAhvub6PVK/ZO5whOmpVPZNQL/w+RtG0SzkkES35e+v7Ii
# cA1b5SbPa7J8Zl6Ktlbv+QQlZwIuvW9J1CKyTV0ET68QW8tZC9llo4AMuDljZYU8
# 2FjfEmCwNTqsI7wTZ3K9VXo3hyNNfBtXucPGMKsAYbivyGoSAjP7fFKEwSISj7Gx
# tzQiJ3M1ORoB3qxtDMqe7oPfvBLOo6AJdqbvPBnnx4OPETpwhgL5m98T6aXYVB86
# UsD4Yy7zBz54pUADdiI0HJwK8XQUNyOpZThCFsCXaIp9hhvxYlTMryvdm1jgsGUo
# +NqXAVzTbKG9EqPcsUSV3x0rslP3zIH610zqtIaNqQIDAQABo4IBGzCCARcwHQYD
# VR0OBBYEFKI1URMmQuP2suvn5sJpatqmYBnhMB8GA1UdIwQYMBaAFNVjOlyKMZDz
# Q3t8RhvFM2hahW1VMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9z
# b2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1RpbVN0YVBDQV8yMDEwLTA3LTAx
# LmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWlj
# cm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljVGltU3RhUENBXzIwMTAtMDctMDEuY3J0
# MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZIhvcNAQEL
# BQADggEBAKOJnMitkq+BZReVYE5EXdTznlXmxFgryY4bNSKm1X0iXnzVly+YmC8X
# NnybHDXu4vOsq2wX7E4Y/Lr0Fe5cdCRBrfzU+p5VJ2MciQdmSjdaTwAnCjJhy3l1
# C+gTK4GhPVZecyUMq+YRn2uhi0Hl3q7f/FsSuOX7rADVxasxDgfKYMMnZYcWha/k
# e2B/HnPvhCZvsiCBerQtZ+WL1suJkDSgZBbpOdhcQyqCEkNNrrccy1Zit8ERN0lW
# 2hkNDosReuXMplTlpiyBBZsotJhpCOZLykAaW4JfH6Dija8NBfPkOVLOgH6Cdda2
# yuR1Jt1Lave+UisHAFcwCQnjOmGVuZcwggZxMIIEWaADAgECAgphCYEqAAAAAAAC
# MA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRo
# b3JpdHkgMjAxMDAeFw0xMDA3MDEyMTM2NTVaFw0yNTA3MDEyMTQ2NTVaMHwxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jv
# c29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A
# MIIBCgKCAQEAqR0NvHcRijog7PwTl/X6f2mUa3RUENWlCgCChfvtfGhLLF/Fw+Vh
# wna3PmYrW/AVUycEMR9BGxqVHc4JE458YTBZsTBED/FgiIRUQwzXTbg4CLNC3ZOs
# 1nMwVyaCo0UN0Or1R4HNvyRgMlhgRvJYR4YyhB50YWeRX4FUsc+TTJLBxKZd0WET
# bijGGvmGgLvfYfxGwScdJGcSchohiq9LZIlQYrFd/XcfPfBXday9ikJNQFHRD5wG
# Pmd/9WbAA5ZEfu/QS/1u5ZrKsajyeioKMfDaTgaRtogINeh4HLDpmc085y9Euqf0
# 3GS9pAHBIAmTeM38vMDJRF1eFpwBBU8iTQIDAQABo4IB5jCCAeIwEAYJKwYBBAGC
# NxUBBAMCAQAwHQYDVR0OBBYEFNVjOlyKMZDzQ3t8RhvFM2hahW1VMBkGCSsGAQQB
# gjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/
# MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fOmhjEMFYGA1UdHwRPME0wS6BJ
# oEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01p
# Y1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYB
# BQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljUm9v
# Q2VyQXV0XzIwMTAtMDYtMjMuY3J0MIGgBgNVHSABAf8EgZUwgZIwgY8GCSsGAQQB
# gjcuAzCBgTA9BggrBgEFBQcCARYxaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL1BL
# SS9kb2NzL0NQUy9kZWZhdWx0Lmh0bTBABggrBgEFBQcCAjA0HjIgHQBMAGUAZwBh
# AGwAXwBQAG8AbABpAGMAeQBfAFMAdABhAHQAZQBtAGUAbgB0AC4gHTANBgkqhkiG
# 9w0BAQsFAAOCAgEAB+aIUQ3ixuCYP4FxAz2do6Ehb7Prpsz1Mb7PBeKp/vpXbRkw
# s8LFZslq3/Xn8Hi9x6ieJeP5vO1rVFcIK1GCRBL7uVOMzPRgEop2zEBAQZvcXBf/
# XPleFzWYJFZLdO9CEMivv3/Gf/I3fVo/HPKZeUqRUgCvOA8X9S95gWXZqbVr5MfO
# 9sp6AG9LMEQkIjzP7QOllo9ZKby2/QThcJ8ySif9Va8v/rbljjO7Yl+a21dA6fHO
# mWaQjP9qYn/dxUoLkSbiOewZSnFjnXshbcOco6I8+n99lmqQeKZt0uGc+R38ONiU
# 9MalCpaGpL2eGq4EQoO4tYCbIjggtSXlZOz39L9+Y1klD3ouOVd2onGqBooPiRa6
# YacRy5rYDkeagMXQzafQ732D8OE7cQnfXXSYIghh2rBQHm+98eEA3+cxB6STOvdl
# R3jo+KhIq/fecn5ha293qYHLpwmsObvsxsvYgrRyzR30uIUBHoD7G4kqVDmyW9rI
# DVWZeodzOwjmmC3qjeAzLhIp9cAvVCch98isTtoouLGp25ayp0Kiyc8ZQU3ghvkq
# mqMRZjDTu3QyS99je/WZii8bxyGvWbWu3EQ8l1Bx16HSxVXjad5XwdHeMMD9zOZN
# +w2/XU/pnR4ZOC+8z1gFLu8NoFA12u8JJxzVs341Hgi62jbb01+P3nSISRKhggLO
# MIICNwIBATCB+KGB0KSBzTCByjELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEm
# MCQGA1UECxMdVGhhbGVzIFRTUyBFU046REQ4Qy1FMzM3LTJGQUUxJTAjBgNVBAMT
# HE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WiIwoBATAHBgUrDgMCGgMVAIPL
# j8S9P/rDvjTvcVg8eVEvEH4CoIGDMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAg
# UENBIDIwMTAwDQYJKoZIhvcNAQEFBQACBQDlJmtpMCIYDzIwMjExMDI5MjA0NTI5
# WhgPMjAyMTEwMzAyMDQ1MjlaMHcwPQYKKwYBBAGEWQoEATEvMC0wCgIFAOUma2kC
# AQAwCgIBAAICJgsCAf8wBwIBAAICEVkwCgIFAOUnvOkCAQAwNgYKKwYBBAGEWQoE
# AjEoMCYwDAYKKwYBBAGEWQoDAqAKMAgCAQACAwehIKEKMAgCAQACAwGGoDANBgkq
# hkiG9w0BAQUFAAOBgQCM4cLXA0SI/nIF3q69+MUZODYl+LSw5ZfJinW9yQ/1XVte
# xO+r3VgCS5ffFTuiCstFmHBDRI+9Mu3eBHttzGw7IzMAie3848EQvb/INyHEah7q
# sr30Gk4SUwG+v53my/D3hyS1qIHAphwR00y41MBJAA7rN9LnB67Nqt0lqAhbBzGC
# Aw0wggMJAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAB
# Toyx6+3XsuMAAAAAAAFOMA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMx
# DQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEID4HK6DLeNfXXrWjL0r/pNW2
# woLq2UNvoKoxL0kOnB9KMIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQgCP4N
# 4phLi4HnMP66HUIKRN3vMjEriAKO/up948olL5IwgZgwgYCkfjB8MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAU6Msevt17LjAAAAAAABTjAiBCBvdrfM
# JEIgbqx6cFMRIv542vEVvJOBQU8G6jaWXPoWhDANBgkqhkiG9w0BAQsFAASCAQAw
# bhkXPn2jo9IekPiUCTLsJQxAoR3FpKmhJgE25B7IErQRY8/ML4hdBvlxrMDx+Upy
# GX2Xc9uD2yL6f62N/4kuVLCkqbVMqMlsRz9k+1IALqce3A07xvbL+HAbO3zMJAPi
# ZXYOegPkbFEuwnsMh6zKdYiXbeiHa3c/2U7Q5Dy9NJy05zW7Uzs1V440faNwzV7g
# dNuQrb94+SX/epcCDXK2zA2BFR2srWedetJi+gLSdl1cEGciId+mbtkquO/XniW3
# ZrKkwSLClaZh5cUEZg6MtGpzx3iabWskJ6qEY0d941QXL/zJvmz57tFsoXvkGBnR
# 97lmxMOt/eEULAv0wf3Q
# SIG # End signature block
