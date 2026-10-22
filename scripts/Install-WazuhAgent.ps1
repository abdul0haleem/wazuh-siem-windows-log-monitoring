<#
.SYNOPSIS
    Automated silent deployment and enrollment script for Wazuh Agent on Windows.

.DESCRIPTION
    Downloads the specified Wazuh Agent MSI package, executes a silent installation
    configured to point to the designated Wazuh Manager IP/Hostname and Agent Name,
    starts the WazuhSvc service, and verifies its operational status.

.PARAMETER ManagerIP
    The IPv4 address or hostname of the Wazuh Manager / Server.

.PARAMETER AgentName
    The descriptive name to assign to this endpoint in Wazuh Manager.

.PARAMETER Version
    The Wazuh Agent release version to download. Default is 4.14.7-1.

.EXAMPLE
    .\Install-WazuhAgent.ps1 -ManagerIP "192.168.43.155" -AgentName "Windows-11-SOC-Lab"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$ManagerIP = "192.168.43.155",

    [Parameter(Mandatory = $false)]
    [string]$AgentName = "Windows-11-SOC-Lab",

    [Parameter(Mandatory = $false)]
    [string]$Version = "4.14.7-1"
)

# 1. Require Administrative Privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script requires Administrator privileges. Please re-run PowerShell as Administrator."
    exit 1
}

$installerUrl = "https://packages.wazuh.com/4.x/windows/wazuh-agent-$Version.msi"
$tempPath = "$env:TEMP\wazuh-agent.msi"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "  Wazuh Agent Automated Deployment" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Manager Address : $ManagerIP"
Write-Host "Agent Name      : $AgentName"
Write-Host "Agent Version   : $Version"
Write-Host "Installer URL   : $installerUrl"
Write-Host ""

# 2. Download the MSI Installer
Write-Host "[1/4] Downloading Wazuh Agent installer..." -ForegroundColor Yellow
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $installerUrl -OutFile $tempPath -UseBasicParsing
    Write-Host "      Download completed successfully." -ForegroundColor Green
} catch {
    Write-Error "Failed to download Wazuh Agent installer from $installerUrl. Error: $_"
    exit 1
}

# 3. Silent Installation & Configuration
Write-Host "[2/4] Installing and enrolling Wazuh Agent silently..." -ForegroundColor Yellow
$msiArgs = "/i `"$tempPath`" /q WAZUH_MANAGER=`"$ManagerIP`" WAZUH_AGENT_NAME=`"$AgentName`""
$process = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru

if ($process.ExitCode -ne 0) {
    Write-Error "MSI installation failed with exit code $($process.ExitCode)."
    exit $process.ExitCode
}
Write-Host "      Installation completed successfully." -ForegroundColor Green

# Clean up installer artifact
if (Test-Path $tempPath) {
    Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
}

# 4. Start the Service
Write-Host "[3/4] Starting Wazuh Agent service ('WazuhSvc')..." -ForegroundColor Yellow
try {
    Start-Service -Name "WazuhSvc" -ErrorAction Stop
    Write-Host "      Service started successfully." -ForegroundColor Green
} catch {
    Write-Warning "Could not start service immediately: $_"
}

# 5. Verify Service Status
Write-Host "[4/4] Verifying agent service status..." -ForegroundColor Yellow
Start-Sleep -Seconds 2
$svc = Get-Service -Name "WazuhSvc" -ErrorAction SilentlyContinue

if ($svc -and $svc.Status -eq "Running") {
    Write-Host ""
    Write-Host "SUCCESS: Wazuh Agent is running and connected!" -ForegroundColor Green
    Write-Host "Status: $($svc.Status) | Name: $($svc.Name) | Display: $($svc.DisplayName)"
} else {
    Write-Warning "Wazuh Agent service status is currently: $($svc.Status)."
    Write-Warning "Please check Event Viewer or 'C:\Program Files (x86)\ossec-agent\ossec.log' for diagnostic details."
}
