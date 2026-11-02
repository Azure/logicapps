#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs and configures the MSMQ Broker on a Windows Server VM.

.DESCRIPTION
    This script verifies all prerequisites, installs missing components, downloads
    the service from a NuGet package source, registers it as a Windows Service,
    and configures the firewall.

    The service binaries are distributed as a NuGet package (Microsoft.Azure.Workflows.MsmqBroker).
    The script downloads the package, extracts the publish output,
    and installs it as a Windows Service.

    Prerequisites checked/installed:
      - Windows Server OS
      - Administrator privileges
      - MSMQ Windows feature
      - .NET 8 Runtime (installed if missing, or bundled in self-contained package)
      - Firewall rule for the service port
      - Windows Service registration

.PARAMETER InstallPath
    Destination folder for the service binaries on the VM.
    Default: C:\Services\MsmqBroker

.PARAMETER Port
    TCP port the service listens on. Default: 5050

.PARAMETER VNetCidr
    CIDR range for the firewall inbound rule. Only traffic from this range can
    reach the service. Default: 10.0.0.0/8

.PARAMETER ServiceName
    Windows Service name. Default: MsmqBroker

.PARAMETER NuGetSource
    NuGet feed URL or local folder path containing Microsoft.Azure.Workflows.MsmqBroker.nupkg.
    Default: current directory (.\)

.PARAMETER PackageVersion
    Version of the Microsoft.Azure.Workflows.MsmqBroker NuGet package to install.
    Default: 1.3.0

.PARAMETER WebhookMaxSubscriptions
    Maximum number of concurrent queue subscriptions. Overrides the Webhook section
    in appsettings.json. Default: not set (uses appsettings value of 50).

.PARAMETER WebhookMaxDeliveryAttempts
    Maximum delivery attempts per message. Overrides the Webhook section
    in appsettings.json. Default: not set (uses appsettings value of 3).

.PARAMETER WebhookMaxConsecutiveFailures
    Number of consecutive delivery failures before auto-unsubscribing.
    Overrides the Webhook section in appsettings.json. Default: not set (uses appsettings value of 10).

.PARAMETER WebhookFailureCooldownMinutes
    Cooldown window in minutes. Auto-unsubscribe only triggers when both the failure
    threshold and this cooldown have elapsed. Overrides the Webhook section in
    appsettings.json. Default: not set (uses appsettings value of 30).

.EXAMPLE
    .\Install-MsmqEnvironmentService.ps1 -NuGetSource "C:\packages"

.EXAMPLE
    .\Install-MsmqEnvironmentService.ps1 -NuGetSource "https://pkgs.dev.azure.com/myorg/_packaging/myfeed/nuget/v3/index.json"

.EXAMPLE
    .\Install-MsmqEnvironmentService.ps1 -Port 8080 -VNetCidr "172.16.0.0/12"

.EXAMPLE
    .\Install-MsmqEnvironmentService.ps1 -NuGetSource "C:\packages" -WebhookMaxDeliveryAttempts 5 -WebhookMaxConsecutiveFailures 10
#>
[CmdletBinding()]
param(
    [string]$InstallPath = "C:\Services\MsmqBroker",
    [int]$Port = 5050,
    [string]$VNetCidr = "10.0.0.0/8",
    [string]$ServiceName = "MsmqBroker",
    [string]$NuGetSource = ".\",
    [string]$PackageVersion = "1.3.0",
    [int]$WebhookMaxSubscriptions = 0,
    [int]$WebhookMaxDeliveryAttempts = 0,
    [int]$WebhookMaxConsecutiveFailures = 0,
    [int]$WebhookFailureCooldownMinutes = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Step  { param([string]$Message) Write-Host "`n[$script:step] $Message" -ForegroundColor Cyan; $script:step++ }
function Write-Pass  { param([string]$Message) Write-Host "    [PASS] $Message" -ForegroundColor Green }
function Write-Warn  { param([string]$Message) Write-Host "    [WARN] $Message" -ForegroundColor Yellow }
function Write-Fail  { param([string]$Message) Write-Host "    [FAIL] $Message" -ForegroundColor Red }
function Write-Info  { param([string]$Message) Write-Host "    $Message" -ForegroundColor Gray }

$script:step = 1
$failed = $false

Write-Host "============================================================" -ForegroundColor White
Write-Host " MSMQ Broker Service - Prerequisite and Install Script" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White

# ---------------------------------------------------------------------------
# 1. OS Check
# ---------------------------------------------------------------------------
Write-Step "Checking Windows Server OS"

$os = Get-CimInstance Win32_OperatingSystem
if ($os.ProductType -eq 3) {
    Write-Pass "Windows Server detected: $($os.Caption)"
}
elseif ($os.ProductType -eq 1) {
    Write-Warn "Windows Client detected ($($os.Caption)). Production deployments should use Windows Server."
}
else {
    Write-Warn "Unexpected OS product type: $($os.ProductType). Proceeding anyway."
}

# ---------------------------------------------------------------------------
# 2. MSMQ Feature
# ---------------------------------------------------------------------------
Write-Step "Checking MSMQ Windows feature"

$msmqFeature = $null
if (Get-Command Install-WindowsFeature -ErrorAction SilentlyContinue) {
    $msmqFeature = Get-WindowsFeature MSMQ-Server
    if ($msmqFeature.Installed) {
        Write-Pass "MSMQ-Server feature is installed."
    }
    else {
        Write-Info "MSMQ-Server is not installed. Installing now..."
        $result = Install-WindowsFeature -Name MSMQ-Server,MSMQ-HTTP-Support -IncludeManagementTools
        if ($result.Success) {
            Write-Pass "MSMQ-Server with HTTP Support installed successfully."
        }
        else {
            Write-Fail "MSMQ-Server installation failed. Exit code: $($result.ExitCode)"
            $failed = $true
        }
    }

    # Ensure HTTP Support is enabled even if MSMQ-Server was already installed.
    $httpFeature = Get-WindowsFeature MSMQ-HTTP-Support
    if (-not $httpFeature.Installed) {
        Write-Info "MSMQ-HTTP-Support is not installed. Installing now..."
        $httpResult = Install-WindowsFeature -Name MSMQ-HTTP-Support
        if ($httpResult.Success) {
            Write-Pass "MSMQ-HTTP-Support installed successfully."
        }
        else {
            Write-Fail "MSMQ-HTTP-Support installation failed. Exit code: $($httpResult.ExitCode)"
            $failed = $true
        }
    }
    else {
        Write-Pass "MSMQ-HTTP-Support feature is installed."
    }
}
elseif (Get-Command Enable-WindowsOptionalFeature -ErrorAction SilentlyContinue) {
    $state = (Get-WindowsOptionalFeature -Online -FeatureName MSMQ-Server).State
    if ($state -eq "Enabled") {
        Write-Pass "MSMQ-Server feature is enabled."
    }
    else {
        Write-Info "MSMQ-Server is not enabled. Enabling now..."

        # On Windows client, MSMQ-Server requires parent feature MSMQ-Container.
        $container = Get-WindowsOptionalFeature -Online -FeatureName MSMQ-Container -ErrorAction SilentlyContinue
        if ($container -and $container.State -ne "Enabled") {
            Write-Info "Enabling parent feature MSMQ-Container first..."
            Enable-WindowsOptionalFeature -Online -FeatureName MSMQ-Container -All -NoRestart
        }

        Enable-WindowsOptionalFeature -Online -FeatureName MSMQ-Server -All -NoRestart
        Write-Pass "MSMQ-Server enabled. A reboot may be required."
    }

    # Ensure HTTP Support is enabled even if MSMQ-Server was already enabled.
    $httpState = (Get-WindowsOptionalFeature -Online -FeatureName MSMQ-HTTP -ErrorAction SilentlyContinue).State
    if ($httpState -ne "Enabled") {
        Write-Info "MSMQ-HTTP is not enabled. Enabling with all parent features..."

        # Use -All to automatically enable all required parent features (IIS, WAS, etc.).
        Enable-WindowsOptionalFeature -Online -FeatureName MSMQ-HTTP -All -NoRestart
        Write-Pass "MSMQ-HTTP enabled (with all parent features). A reboot may be required."
    }
    else {
        Write-Pass "MSMQ-HTTP feature is enabled."
    }
}
else {
    Write-Fail "Cannot determine MSMQ installation method. Install MSMQ manually."
    $failed = $true
}

# Verify MSMQ service is running.
$msmqService = Get-Service -Name MSMQ -ErrorAction SilentlyContinue
if ($msmqService) {
    if ($msmqService.Status -eq "Running") {
        Write-Pass "MSMQ service is running."
    }
    else {
        Write-Info "MSMQ service is $($msmqService.Status). Starting..."
        Start-Service -Name MSMQ
        Write-Pass "MSMQ service started."
    }
}
else {
    Write-Fail "MSMQ service not found after installation."
    $failed = $true
}

# ---------------------------------------------------------------------------
# 3. .NET 8 SDK
# ---------------------------------------------------------------------------
Write-Step "Checking .NET 8 SDK"

$dotnetInstalled = $false
$dotnetCmd = Get-Command dotnet -ErrorAction SilentlyContinue
if ($dotnetCmd) {
    $sdks = & dotnet --list-sdks
    $sdk8 = $sdks | Where-Object { $_ -match "^8\." }
    if ($sdk8) {
        Write-Pass ".NET 8 SDK found: $($sdk8 | Select-Object -First 1)"
        $dotnetInstalled = $true
    }
}

if (-not $dotnetInstalled) {
    Write-Info ".NET 8 SDK not found. Installing..."

    # Download the official dotnet-install script from Microsoft.
    $installScript = Join-Path $env:TEMP "dotnet-install.ps1"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri "https://dot.net/v1/dotnet-install.ps1" -OutFile $installScript -UseBasicParsing -ErrorAction Stop

    # dotnet-install.ps1 is a PowerShell script — it does not set $LASTEXITCODE.
    # Use $? to check success under Set-StrictMode -Version Latest.
    & $installScript -Channel 8.0 -InstallDir "C:\Program Files\dotnet"
    if ($?) {
        Write-Pass ".NET 8 SDK installed."
        $dotnetInstalled = $true
    }
    else {
        Write-Fail ".NET 8 SDK installation failed. Download manually from https://dotnet.microsoft.com/download/dotnet/8.0"
        $failed = $true
    }

    Remove-Item $installScript -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# 4. Download and extract NuGet package
# ---------------------------------------------------------------------------
Write-Step "Installing Microsoft.Azure.Workflows.MsmqBroker package (v$PackageVersion)"

$exeName = "Microsoft.Azure.Workflows.MsmqBroker.Package"
$exePath = Join-Path $InstallPath "$exeName.exe"
$packageName = "Microsoft.Azure.Workflows.MsmqBroker"

# Stop service if running (so we can overwrite binaries).
$existingSvc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingSvc -and $existingSvc.Status -eq "Running") {
    Write-Info "Stopping existing service before update..."
    Stop-Service -Name $ServiceName -Force
    Start-Sleep -Seconds 2
}

# Helper: Extract .nupkg to InstallPath.
function Install-FromNupkg {
    param([string]$NupkgPath)

    if (-not (Test-Path $InstallPath)) { New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null }

    $tempExtract = Join-Path $env:TEMP "MsmqBroker_extract"
    if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force }

    # Expand-Archive in Windows PowerShell 5.1 only accepts .zip extensions.
    $tempZip = Join-Path $env:TEMP "$packageName.$PackageVersion.zip"
    Copy-Item -Path $NupkgPath -Destination $tempZip -Force
    Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force
    Remove-Item $tempZip -ErrorAction SilentlyContinue

    $toolsPath = Join-Path $tempExtract "tools"
    if (Test-Path $toolsPath) {
        Copy-Item "$toolsPath\*" -Destination $InstallPath -Recurse -Force
        Write-Pass "Extracted package content to $InstallPath."
    }
    else {
        Write-Fail "Package does not contain a tools\ directory."
        $script:failed = $true
    }

    Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
}

# Locate .nupkg: local file, local directory, or remote feed.
if ($NuGetSource -like "*.nupkg" -and (Test-Path $NuGetSource)) {
    $localNupkg = $NuGetSource
}
else {
    $localNupkg = Join-Path $NuGetSource "$packageName.$PackageVersion.nupkg"
}

if (Test-Path $localNupkg) {
    Write-Info "Found local package: $localNupkg"
    Install-FromNupkg -NupkgPath $localNupkg
}
else {
    # Download from remote NuGet feed.
    # NOTE(vmalhotra): NuGet V3 flat container URL format for package download.
    $nugetSrc = if ($NuGetSource -eq ".\") { "https://api.nuget.org/v3-flatcontainer" } else { $NuGetSource }
    $lowerId = $packageName.ToLower()
    $lowerVersion = $PackageVersion.ToLower()
    $downloadUrl = "$($nugetSrc.TrimEnd('/'))/$lowerId/$lowerVersion/$lowerId.$lowerVersion.nupkg"
    $downloadedNupkg = Join-Path $env:TEMP "$packageName.$PackageVersion.nupkg"

    Write-Info "Downloading from: $downloadUrl"
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadedNupkg -UseBasicParsing -ErrorAction Stop
        Write-Info "Downloaded package from NuGet feed."
        Install-FromNupkg -NupkgPath $downloadedNupkg
        Remove-Item $downloadedNupkg -ErrorAction SilentlyContinue
    }
    catch {
        Write-Fail "Failed to download package from $downloadUrl"
        Write-Info "Place $packageName.$PackageVersion.nupkg next to this script and re-run."
        $failed = $true
    }
}

# Final check: verify executable exists.
if (-not (Test-Path $exePath)) {
    if (-not $failed) {
        Write-Fail "$exeName.exe not found at $InstallPath after extraction."
        $failed = $true
    }
}
else {
    Write-Pass "Service executable verified: $exePath"
}

# ---------------------------------------------------------------------------
# 5. Configure appsettings.json
# ---------------------------------------------------------------------------
Write-Step "Configuring appsettings.json"

$settingsFile = Join-Path $InstallPath "appsettings.json"
if (Test-Path $settingsFile) {
    $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json
    $changed = $false

    # Ensure Urls binds to the correct port on all interfaces.
    $expectedUrl = "http://0.0.0.0:$Port"
    if ($settings.Urls -ne $expectedUrl) {
        $settings.Urls = $expectedUrl
        $changed = $true
        Write-Info "Set Urls to $expectedUrl."
    }

    # Apply Webhook overrides to the nested Webhook section.
    $webhookOverrides = @{
        MaxSubscriptions       = $WebhookMaxSubscriptions
        MaxDeliveryAttempts    = $WebhookMaxDeliveryAttempts
        MaxConsecutiveFailures = $WebhookMaxConsecutiveFailures
        FailureCooldownMinutes = $WebhookFailureCooldownMinutes
    }

    foreach ($key in $webhookOverrides.Keys) {
        $value = $webhookOverrides[$key]
        if ($value -gt 0 -and $settings.Webhook.$key -ne $value) {
            $settings.Webhook.$key = $value
            $changed = $true
            Write-Info "Set Webhook.$key to $value."
        }
    }

    if ($changed) {
        $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsFile -Encoding UTF8
        Write-Pass "appsettings.json updated."
    }
    else {
        Write-Pass "appsettings.json already configured correctly."
    }
}
else {
    Write-Warn "appsettings.json not found at $settingsFile. It will use defaults."
}

# ---------------------------------------------------------------------------
# 6. Firewall rule
# ---------------------------------------------------------------------------
Write-Step "Configuring firewall rule for port $Port"

$ruleName = "MSMQ Broker (Port $Port)"
$existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
if ($existingRule) {
    Write-Pass "Firewall rule already exists: $ruleName"
}
else {
    New-NetFirewallRule `
        -DisplayName $ruleName `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort $Port `
        -Action Allow `
        -RemoteAddress $VNetCidr `
        -Description "Allow inbound traffic to MSMQ Broker from VNet ($VNetCidr)."
    Write-Pass "Firewall rule created: Allow TCP/$Port from $VNetCidr."
}

# ---------------------------------------------------------------------------
# 7. Windows Service registration
# ---------------------------------------------------------------------------
Write-Step "Registering Windows Service: $ServiceName"

$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
$serviceBinPath = "`"$exePath`""

if ($existingService) {
    Write-Pass "Service is already registered: $ServiceName"

    # Stop before updating binary path if needed.
    if ($existingService.Status -eq "Running") {
        Write-Info "Stopping service for update..."
        Stop-Service -Name $ServiceName -Force
    }
}
else {
    Write-Info "Creating service: $ServiceName"
    sc.exe create $ServiceName binPath= $serviceBinPath start= auto DisplayName= "MSMQ Broker"
    if ($LASTEXITCODE -eq 0) {
        Write-Pass "Service created."
    }
    else {
        Write-Fail "sc.exe create failed with exit code $LASTEXITCODE."
        $failed = $true
    }
}

# Configure service recovery: restart on failure.
sc.exe failure $ServiceName reset= 86400 actions= restart/5000/restart/10000/restart/30000 | Out-Null
Write-Info "Service recovery policy set: restart after 5s, 10s, 30s."

# ---------------------------------------------------------------------------
# 8. Start the service
# ---------------------------------------------------------------------------
Write-Step "Starting service"

if ($failed) {
    Write-Fail "Skipping service start due to earlier failures. Fix the issues above and re-run."
}
else {
    Start-Service -Name $ServiceName
    Start-Sleep -Seconds 3

    $svc = Get-Service -Name $ServiceName
    if ($svc.Status -eq "Running") {
        Write-Pass "Service is running."
    }
    else {
        Write-Fail "Service status: $($svc.Status). Check the Windows Event Log for details."
        $failed = $true
    }
}

# ---------------------------------------------------------------------------
# 9. Health check
# ---------------------------------------------------------------------------
Write-Step "Running health check"

if (-not $failed) {
    try {
        $health = Invoke-RestMethod -Uri "http://localhost:$Port/api/admin/health" -TimeoutSec 10
        Write-Pass "Health endpoint responded."
        Write-Info "  Status:              $($health.status)"
        Write-Info "  Started At:          $($health.startedAt)"
    }
    catch {
        Write-Warn "Health check failed: $($_.Exception.Message)"
        Write-Info "The service may still be starting. Try: Invoke-RestMethod http://localhost:$Port/api/admin/health"
    }
}
else {
    Write-Info "Skipped (earlier failures)."
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host "`n============================================================" -ForegroundColor White
if ($failed) {
    Write-Host " COMPLETED WITH ERRORS -- Review [FAIL] items above." -ForegroundColor Red
}
else {
    Write-Host " ALL PREREQUISITES MET - Service is running." -ForegroundColor Green
    Write-Host ""
    Write-Host " Service:   $ServiceName" -ForegroundColor White
    Write-Host " Port:      $Port" -ForegroundColor White
    Write-Host " Binaries:  $InstallPath" -ForegroundColor White
    Write-Host " Package:   $packageName v$PackageVersion" -ForegroundColor White
    Write-Host " Firewall:  TCP/$Port from $VNetCidr" -ForegroundColor White
    Write-Host ""
    Write-Host " Next: Configure your Logic App MSMQ connector to:" -ForegroundColor White
    Write-Host "   Send URL: http://<vm-private-ip>:$Port/api/msmq/send" -ForegroundColor Gray
}
Write-Host "============================================================" -ForegroundColor White
