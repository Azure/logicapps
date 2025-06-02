$reportFile = "0. Report.txt"
"Troubleshooting Environment`n" | Out-File -FilePath $reportFile -Encoding utf8

function Write-Report {
    param (
        [Parameter(Mandatory)]
        [string]$Data,

        [string]$ForegroundColor
    )
    if ($ForegroundColor) {
        Write-Host $Data -ForegroundColor $ForegroundColor
    } else {
        Write-Host $Data
    }
    $Data | Out-File -FilePath $reportFile -Encoding utf8 -Append
}

# Check if kubectl is installed
if ($IsLinux) {
    $kubectlInstalled = bash -c "command -v kubectl"
    if (-not $kubectlInstalled) {
        Write-Report -Data "kubectl is not installed ... Trying to install kubectl"
        sudo apt-get update
        sudo apt-get install -y apt-transport-https ca-certificates curl gnupg
        # If the folder `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
        # sudo mkdir -p -m 755 /etc/apt/keyrings
        curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
        sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg # allow unprivileged APT programs to read this keyring
        # This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
        echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
        sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list   # helps tools such as command-not-found to work correctly
        sudo apt-get update
        sudo apt-get install -y kubectl
    }
} else {
    if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
        Write-Report -Data "kubectl is not installed or not found in PATH."
        Write-Report -Data "Trying to install kubectl"
        Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
        choco install kubernetes-cli -y
    }
}

if ($IsLinux) {
    Write-Report -Data "Running on Linux. Checking if 'nc' and 'nslookup' installed."
    # Check if nc is installed
    $ncInstalled = bash -c "command -v nc"
    if (-not $ncInstalled) {
        Write-Report -Data "Installing netcat (nc)..."
        sudo apt update
        sudo apt install -y netcat
    }

    # Check if nslookup is installed
    $nslooupInstalled = bash -c "command -v nslookup"
    if (-not $nslooupInstalled) {
        Write-Report -Data "Installing dnsutils..."
        sudo apt update
        sudo apt install -y dnsutils
    }
} else {
    Write-Report -Data "Running on Windows. Checking if 'Test-NetConnection' and 'nslookup' installed."
    if (-not (Get-Command Test-NetConnection -ErrorAction SilentlyContinue)) {
        Write-Report -Data "❌ Test-NetConnection is not available. You're likely running PowerShell Core."
    } 

    if (-not (Get-Command nslookup.exe -ErrorAction SilentlyContinue)) {
        Write-Report -Data "❌ nslookup not found. Attempting to install..."

        # Check if running as Administrator
        if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {

            Write-Report -Data "Script is not running as Administrator. Relaunching with elevation..." -ForegroundColor Yellow

            # Relaunch as Administrator
            $newProcess = Start-Process -FilePath "powershell" `
                -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
                -Verb RunAs -PassThru

            # Exit current session
            exit
        }

        # Enable RSAT DNS Tools (requires admin rights)
        Add-WindowsCapability -Online -Name "Rsat.Dns.Tools~~~~0.0.1.0"
    }
}



# ---------- Helper Functions ----------
function Write-Section {
    param([string]$Title)
    Write-Report -Data "`n----------------------------------------------------------------" -ForegroundColor Cyan
    Write-Report -Data "$Title" -ForegroundColor Cyan
    Write-Report -Data "----------------------------------------------------------------`n" -ForegroundColor Cyan
}

function Invoke-CommandAndSaveOutput {
    param (
        [Parameter(Mandatory)]
        [string]$Command,

        [Parameter(Mandatory)]
        [string]$OutputFile,

        [switch]$Append
    )

    try {
        # Run the command
        $output = (Invoke-Expression $Command) -join "`n"

        # Output to console
        Write-Report -Data $output

        # Write to file (append if -Append is specified)
        if ($Append) {
            "`n" | Out-File -FilePath $OutputFile -Encoding utf8 -Append
            $Command | Out-File -FilePath $OutputFile -Encoding utf8 -Append
            $output | Out-File -FilePath $OutputFile -Encoding utf8 -Append
            Write-Report -Data "✅ Output appended to $OutputFile" -ForegroundColor Green
        } else {
            $Command | Out-File -FilePath $OutputFile -Encoding utf8 -Force
            $output | Out-File -FilePath $OutputFile -Encoding utf8 -Append
            Write-Report -Data "✅ Output written to $OutputFile" -ForegroundColor Green
        }
    } catch {
        Write-Report -Data "❌ Error running command: $Command" -ForegroundColor Red
        Write-Report -Data $_.Exception.Message -ForegroundColor Red
    }
}

function PrintAndSaveOutput {
    param (
        [Parameter(Mandatory)]
        [string]$Data,

        [Parameter(Mandatory)]
        [string]$OutputFile,

        [string]$Color,

        [switch]$Append
    )

    try {
        # Output to console
        if ($Color) {
            Write-Report -Data $Data -ForegroundColor $Color
        } else {
            Write-Report -Data $Data
        }

        # Write to file (append if -Append is specified)
        if ($OutputFile) {
            if ($Append) {
                $Data | Out-File -FilePath $OutputFile -Encoding utf8 -Append
            } else {
                $Data | Out-File -FilePath $OutputFile -Encoding utf8 -Force
                Write-Report -Data "✅ Output written to $OutputFile" -ForegroundColor Green
            }
        }
    } catch {
        Write-Report -Data "❌ Error running command: $Command" -ForegroundColor Red
        Write-Report -Data $_.Exception.Message -ForegroundColor Red
    }
}

function Ensure-Directory {
    param ([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Write-PodEventsAndLogs {
    param (
        [string]$Namespace,
        [string]$PodName,
        [string]$OutputDir
    )
    Ensure-Directory $OutputDir
    $eventsDir = "$OutputDir\podEvents\"
    $logsDir = "$OutputDir\podLogs\"
    Ensure-Directory $eventsDir
    Ensure-Directory $logsDir
    Write-Report -Data "Getting events and logs for pod: $PodName" -ForegroundColor Cyan
    $eventsFile = Join-Path $eventsDir "$PodName.txt"
	$selector = "involvedObject.kind=Pod,involvedObject.name=$PodName"
    kubectl get events --field-selector $selector -n $Namespace | Out-File -FilePath $eventsFile -Encoding utf8
    Write-Report -Data "✅ Events written to $eventsFile" -ForegroundColor Green

    $podJson = kubectl get pod $PodName -n $Namespace -o json | ConvertFrom-Json
    $containers = $podJson.spec.containers
    $statuses = $podJson.status.containerStatuses

    foreach ($container in $containers) {
        $name = $container.name
        $status = $statuses | Where-Object { $_.name -eq $name }

        if (-not $status.state.waiting) {
            $logFile = Join-Path $logsDir "$PodName($name).log"
            try {
                kubectl logs $PodName -c $name -n $Namespace | Out-File -FilePath $logFile -Encoding utf8
                Write-Report -Data "✅ Logs for container '$name' saved to $logFile" -ForegroundColor Green
            } catch {
                Write-Report -Data "❌ Failed to get logs for container '$name'" -ForegroundColor Red
            }
        }
        else {
            Write-Report -Data "⚠️ container '$name' is in waiting state, so skipping capturing log." -ForegroundColor Yellow
        }
    }
}


function Analyze-PodsHealth {
    param (
        [Parameter(Mandatory)]
        [array]$FilteredPods,

        [Parameter(Mandatory)]
        [string]$PodsReportFile,

        [Parameter(Mandatory)]
        [string]$LogOutputDir
    )

    $now = Get-Date
    $problemFound = $false
    $podDisplayList = @()

    foreach ($pod in $FilteredPods) {
        $podName = $pod.metadata.name
        $namespace = $pod.metadata.namespace
        $status = $pod.status.phase
        $containers = $pod.status.containerStatuses
        $startTime = Get-Date $pod.status.startTime
        $uptime = ($now - $startTime).TotalMinutes

        $restarts = 0
        foreach ($container in $containers) {
            $restarts += $container.restartCount
        }

        $highlight = $false
        $failed = $false
        $reason = ""

        $containerProblems = @()

        foreach ($container in $containers) {
            if ($container.state.waiting) {
                $containerProblems += $container.state.waiting.reason
            } elseif ($container.state.terminated) {
                $containerProblems += $container.state.terminated.reason
            }
        }

        if ($containerProblems.Count -gt 0) {
            $highlight = $true
            $failed = $true
            $status = ($containerProblems -join ", ")
            $reason = "Container Issue: " + ($containerProblems -join ", ") + " => Please check container logs"
        } elseif ($status -ne "Running") {
            $highlight = $true
            $failed = $true
            $reason = "Status: $status"
        } elseif ($uptime -le 60 -and $restarts -gt 1) {
            $highlight = $true
            $reason = "Restarted $restarts times in last hour"
        }

        if ($highlight) { $problemFound = $true }

        $podDisplayList += [PSCustomObject]@{
            Namespace = $namespace
            PodName   = $podName
            Status    = $status
            Restarts  = $restarts
            UptimeMin = [math]::Round($uptime, 1)
            Reason    = $reason
            Failed    = $failed
        }
    }

    # Display formatting
    $colWidths = @{
        Namespace = 25
        PodName   = 70
        Status    = 18
        Restarts  = 10
        UptimeMin = 12
        Reason    = 40
    }

    $header = "{0,-$($colWidths.Namespace)}{1,-$($colWidths.PodName)}{2,-$($colWidths.Status)}{3,-$($colWidths.Restarts)}{4,-$($colWidths.UptimeMin)}{5,-$($colWidths.Reason)}" -f `
        "Namespace", "PodName", "Status", "Restarts", "Uptime(min)", "Reason"
    PrintAndSaveOutput -Data "$header" -OutputFile $PodsReportFile
    PrintAndSaveOutput -Data "$("-" * ($colWidths.Values | Measure-Object -Sum).Sum)" -OutputFile $PodsReportFile -Append

    foreach ($pod in $podDisplayList) {
        $color = if ($pod.Failed) { "Red" } elseif ($pod.Reason -ne "") { "Yellow" } else { "Green" }
        $line = "{0,-$($colWidths.Namespace)}{1,-$($colWidths.PodName)}{2,-$($colWidths.Status)}{3,-$($colWidths.Restarts)}{4,-$($colWidths.UptimeMin)}{5,-$($colWidths.Reason)}" -f `
            $pod.Namespace, $pod.PodName, $pod.Status, $pod.Restarts, $pod.UptimeMin, $pod.Reason
        PrintAndSaveOutput -Data $line -OutputFile $PodsReportFile -Append -Color $color
    }

    if (-not $problemFound) {
        Write-Report -Data "`n✅ All pods starting are healthy." -ForegroundColor Green
    }

    # Save logs for failed pods
    foreach ($pod in $podDisplayList) {
        if ($pod.Failed) {
            Write-PodEventsAndLogs -Namespace $pod.Namespace -PodName $pod.PodName -OutputDir $LogOutputDir
        }
    }
}

# -------------------------

# ---------- Kubernetes Current Context ----------
Write-Section "kubectl current context ==> $(kubectl config current-context)"

# ---------- Kubernetes Cluster Info ----------
Write-Section "Cluster Info"
Invoke-CommandAndSaveOutput -Command "kubectl cluster-info" -OutputFile "1. cluster-info.txt"


# ---------- Kubernetes Node Resource Usage ----------
Write-Section "Kubernetes Node Resource Usage"
$outputFileNodeReport = "2. k8s-nodes-report.txt"
Invoke-CommandAndSaveOutput -Command "kubectl get nodes -o wide" -OutputFile $outputFileNodeReport
Invoke-CommandAndSaveOutput -Command "kubectl top nodes" -OutputFile $outputFileNodeReport -Append

# Get usage info (from metrics-server)
$nodesUsage = kubectl top nodes --no-headers | ForEach-Object {
    $parts = ($_ -split '\s+')
    [PSCustomObject]@{
        Node        = $parts[0]
        CPU_Used_m  = [int]($parts[1] -replace 'm','')
        Mem_Used_Mi = [int]($parts[3] -replace 'Mi','')
    }
}

# Get node capacity from kubectl
$nodes = kubectl get nodes -o json | ConvertFrom-Json

# Process each node
$final = foreach ($node in $nodes.items) {
    $nodeName = $node.metadata.name

    # CPU capacity (convert to millicores)
    $cpuCapRaw = $node.status.capacity.cpu
    $cpuTotal_m = if ($cpuCapRaw -match 'm$') {
        [int]($cpuCapRaw -replace 'm','')
    } else {
        [int]$cpuCapRaw * 1000
    }

    # Memory capacity (convert from Ki to Mi)
    $memTotal_Ki = [int64]($node.status.capacity.memory -replace 'Ki','')
    $memTotal_Mi = [math]::Round($memTotal_Ki / 1024)

    # Match with usage info
    $usage = $nodesUsage | Where-Object { $_.Node -eq $nodeName }

    if ($usage) {
        $cpuUsed = $usage.CPU_Used_m
        $memUsed = $usage.Mem_Used_Mi

        $cpuPercent = [math]::Round(($cpuUsed / $cpuTotal_m) * 100, 2)
        $memPercent = [math]::Round(($memUsed / $memTotal_Mi) * 100, 2)

        $cpuWarn = if ($cpuPercent -gt 80) { "⚠️ High CPU" } else { "" }
        $memWarn = if ($memPercent -gt 80) { "⚠️ High Memory" } else { "" }

        [PSCustomObject]@{
            Node           = $nodeName
            CPU_Used_m     = $cpuUsed
            CPU_Total_m    = $cpuTotal_m
            CPU_Used_Pct   = "$cpuPercent%"
            CPU_Status     = $cpuWarn
            Mem_Used_Mi    = $memUsed
            Mem_Total_Mi   = $memTotal_Mi
            Mem_Used_Pct   = "$memPercent%"
            Mem_Status     = $memWarn
        }
    }
}

# Section 2: save final usage report
# Define column headers
PrintAndSaveOutput -Data "`nUsage Report" -OutputFile $outputFileNodeReport -Append 
$headers = "Node`t`t`tCPU_Used(m)`tCPU_Total(m)`tCPU_Used(%)`tCPU_Status`tMem_Used(Mi)`tMem_Total(Mi)`tMem_Used(%)`tMem_Status"
PrintAndSaveOutput -Data $headers -OutputFile $outputFileNodeReport -Append 

# Write rows with guaranteed column count (fill empty status columns explicitly)
foreach ($item in $final) {
    $cpuStatus = if ($item.CPU_Status) { $item.CPU_Status } else { "---" }
    $memStatus = if ($item.Mem_Status) { $item.Mem_Status } else { "---" }

    $line = "$($item.Node)`t$($item.CPU_Used_m)`t$($item.CPU_Total_m)`t$($item.CPU_Used_Pct)`t$cpuStatus`t$($item.Mem_Used_Mi)`t$($item.Mem_Total_Mi)`t$($item.Mem_Used_Pct)`t$memStatus"
    PrintAndSaveOutput -Data $line -OutputFile $outputFileNodeReport -Append 
    #Add-Content -Path $outputFileNodeReport -Value $line
}


# ---------- ARC Pod Issues ----------
Write-Section "Azure-Arc Pods Issues (Not Running / Recent Restarts <1h)"

$namespace = "azure-arc"
$outputFileArcPods = "3. azure-arc-pods-report.txt"
$arcLogsDir = "logs_arc"
#Invoke-CommandAndSaveOutput -Command "kubectl get pods -n $namespace -o wide" -OutputFile $outputFileArcPods 

Write-Report -Data "Checking pods in namespace: $namespace..." -ForegroundColor Cyan
# Try to get pods JSON from the namespace
try {
    $podJsonRaw = kubectl get pods -n $namespace -o json 2>&1
    if ($podJsonRaw -match "Error from server|NotFound|no resources found") {
        Write-Report -Data "❌ Namespace '$namespace' not found or no pods exist." -ForegroundColor Red
        exit
    }
    $podInfo = $podJsonRaw | ConvertFrom-Json
} catch {
    Write-Report -Data "❌ Failed to retrieve pod data. Check access and kubectl configuration." -ForegroundColor Red
    exit
}
if (-not $podInfo.items -or $podInfo.items.Count -eq 0) {
    Write-Report -Data "⚠️ No pods found in namespace '$namespace'." -ForegroundColor Yellow
    exit
}
else {
    Analyze-PodsHealth -FilteredPods $podInfo.items -PodsReportFile $outputFileArcPods -LogOutputDir $arcLogsDir
}


# ---------- Container App System Pods Issues ----------
Write-Section "Container App System Pods Issues (Not Running / Recent Restarts <1h)"

$podPrefix = "microsoft-app-environment-k8se"
$outputFileSystemPods = "4. capps-system-pods-report.txt"
$systemLogDir = "logs_system"

Write-Report -Data "Searching for pods starting with '$podPrefix' across all namespaces..." -ForegroundColor Cyan

# Get all pods across all namespaces as JSON
try {
    $podJsonRaw = kubectl get pods --all-namespaces -o json 2>&1
    if ($podJsonRaw -match "Error from server|NotFound") {
        Write-Report -Data "❌ Error retrieving pods. Check your cluster access." -ForegroundColor Red
        exit
    }

    $podInfo = $podJsonRaw | ConvertFrom-Json
} catch {
    Write-Report -Data "❌ Failed to retrieve pod data." -ForegroundColor Red
    exit
}

# Filter pods that start with the target prefix
$filteredPods = $podInfo.items | Where-Object { $_.metadata.name -like "$podPrefix*" }

if (-not $filteredPods -or $filteredPods.Count -eq 0) {
    Write-Report -Data "⚠️ No pods found starting with '$podPrefix'." -ForegroundColor Yellow
    exit
}
else {
    Analyze-PodsHealth -FilteredPods $filteredPods -PodsReportFile $outputFileSystemPods -LogOutputDir $systemLogDir
}



# ---------- Get All Services ----------
Write-Section "All Services Info"
Invoke-CommandAndSaveOutput -Command "kubectl get svc -A" -OutputFile "5. services-info.txt"

Write-Section "Check envoy and its connectivity"
$targetServiceName = "microsoft-app-environment-k8se-envoy"
$port = 443
$envoyAccessFile = "6. envoy-access-info.txt"

# Get all services across namespaces in JSON format
$services = kubectl get svc -A -o json | ConvertFrom-Json

# Find the service with the matching name
$match = $services.items | Where-Object { $_.metadata.name -eq $targetServiceName }

if ($match) {
    $namespace = $match.metadata.namespace
    $externalIp = $match.status.loadBalancer.ingress[0].ip

    PrintAndSaveOutput -Data "Found service '$targetServiceName' in namespace '$namespace'" -OutputFile $envoyAccessFile

    if ($externalIp) {
        PrintAndSaveOutput -Data "External IP: $externalIp" -OutputFile $envoyAccessFile -Append
        if ($IsLinux) {
            Write-Report -Data "Testing connection to $externalIp on $port using nc..."
            $bashCmd = "nc -zv $externalIp $port 2>&1"
            $output = bash -c "$bashCmd"

            if ($output -like "*succeeded*" -or $output -like "*open*") {
                PrintAndSaveOutput -Data "✅ Connection to $externalIp on port $port succeeded." -OutputFile $envoyAccessFile -Append -Color Green
            } else {
                PrintAndSaveOutput -Data "❌ Connection to $externalIp on port $port failed." -OutputFile $envoyAccessFile -Append -Color Red
            }
            PrintAndSaveOutput -Data "`n$output" -OutputFile $envoyAccessFile -Append
        }
        else {
            # Test the connection
            $result = Test-NetConnection -ComputerName $externalIp -Port $port
            if ($result.TcpTestSucceeded) {
                PrintAndSaveOutput -Data "✅ Connection to $externalIp on port $port succeeded." -OutputFile $envoyAccessFile -Append -Color Green
            } else {
                PrintAndSaveOutput -Data "❌ Connection to $externalIp on port $port failed." -OutputFile $envoyAccessFile -Append -Color Red
            }
            $formatted = "ComputerName    : $($result.ComputerName)`n" +
                         "RemoteAddress   : $($result.RemoteAddress)`n" +
                         "RemotePort      : $($result.RemotePort)`n" +
                         "InterfaceAlias  : $($result.InterfaceAlias)`n" +
                         "SourceAddress   : $($result.SourceAddress.ToString())`n" +
                         "TcpTestSucceeded: $($result.TcpTestSucceeded)"
            PrintAndSaveOutput -Data "`n$formatted" -OutputFile $envoyAccessFile -Append
        }
        
        # ---------- Check if environment domain is resolving to envoy ip  ----------
        Write-Section "Check if environment domain is resolving to envoy ip"
        $configMapYaml = kubectl get configmap coredns-custom -n kube-system -o yaml
        $lines = $configMapYaml -split "`n"
        $domainLines = $lines | Where-Object { $_ -match '\.k4apps\.io:53' }
        $foundDomains = @()
        foreach ($line in $domainLines) {
            if ($line -match '([a-zA-Z0-9\.\-]+\.k4apps\.io):53') {
                $domain = "any.$($matches[1])"
                $foundDomains += $domain
                PrintAndSaveOutput -Data "`n✅ Found environment dns resolution for domain: $domain" -OutputFile $envoyAccessFile -Append
                $nslookupResult = nslookup $domain 2>&1
                $lines = $nslookupResult -split "`n"
                $resolvedIp = $null
                foreach ($line in $lines) {
                    if ($line) {
                        Write-Report -Data $line
                    }
                    if ($line -match '^\s*Address:\s*([\d\.]+)$') {
                        $resolvedIp = $matches[1]
                    }
                }
                if ($resolvedIp) {
                    PrintAndSaveOutput -Data "🌐 Resolved IP for $domain => $resolvedIp" -OutputFile $envoyAccessFile -Append -Color Green
                } else {
                    PrintAndSaveOutput -Data "❌  Could not resolve domain => $domain" -OutputFile $envoyAccessFile -Append -Color Red
                }

                if ($resolvedIp -eq $externalIp) {
                    PrintAndSaveOutput -Data "✅ $domain is correctly resolving to envoy exposed ip - $externalIp" -OutputFile $envoyAccessFile -Append -Color Green
                } else {
                    PrintAndSaveOutput -Data "❌ $domain is not resolving to envoy exposed ip - $externalIp" -OutputFile $envoyAccessFile -Append -Color Red
                }
            }
        }
        if ($foundDomains.Count -eq 0) {
            PrintAndSaveOutput -Data "❌ No matching domain found in CoreDNS config." -OutputFile $envoyAccessFile -Append -Color Red
        }

    } else {
        PrintAndSaveOutput -Data "❌ No external IP assigned yet for service '$targetServiceName'." -OutputFile $envoyAccessFile -Append -Color Red
    }
} else {
    PrintAndSaveOutput -Data "❌ Service '$targetServiceName' not found in any namespace." -OutputFile $envoyAccessFile -Append -Color Red
}

# ---------- CoreDNS issues ----------
Write-Section "Verify coredns configurations"
$outdir = "coredns_configs"
Ensure-Directory $outdir

$corednsdepoyment = $(kubectl get deploy coredns -n kube-system -o yaml)
$corednsconfigmap = $(kubectl get configmap coredns -n kube-system -o yaml)
$corednscustomconfigmap = $(kubectl get configMap coredns-custom -n kube-system -o yaml)

if (-not $($corednsconfigmap -join "`n").Contains("import custom/*.server")) {
    Write-Report -Data "❌ 'import custom/*.server' is NOT found in the CoreDNS configmap." -ForegroundColor Red
} else {
    Write-Report -Data "✅ coredns config map seems configured correct." -ForegroundColor Green
}

if (-not $($corednsdepoyment -join "`n").Contains("name: custom-config-volume") -or -not $($corednsdepoyment -join "`n").Contains("name: coredns-custom") -or -not $($corednsdepoyment -join "`n").Contains("mountPath: /etc/coredns/custom") ) {
    Write-Report -Data "❌ 'custom coredns config is not mounted in coredns deployment." -ForegroundColor Red
} else {
    Write-Report -Data "✅ custom coredns config is correctly mounted in coredns deployment." -ForegroundColor Green
}

$corednsdepoyment > "$outdir\coredns_deployment.yaml"
$corednsconfigmap > "$outdir\coredns_configmap.yaml"
$corednscustomconfigmap > "$outdir\coredns_custom_configmap.yaml"


# ---------- LogicApps Issues ----------
Write-Section "Listing all LogicApps deployments"

# Output file path
$outputFile = "7. workflowapp-deployments.txt"

# Get all deployments in all namespaces
$deployments = kubectl get deployments --all-namespaces -o json | ConvertFrom-Json

# Filter for workflowapp
$filtered = $deployments.items | Where-Object {
    $_.metadata.annotations.'k8se.microsoft.com/appKind' -ieq 'workflowapp'
}

PrintAndSaveOutput -Data "=== All WorkflowApp Deployments ===" -OutputFile $outputFile

# Header
$header = "{0,-60} {1,-7} {2,-11} {3,-10} {4,-6}" -f "NAME", "READY", "UP-TO-DATE", "AVAILABLE", "AGE"
PrintAndSaveOutput -Data $header -OutputFile $outputFile -Append

$unavailablePodDetails = @()
$unavailablePodDetails += "`n=== Pods from Deployments with AVAILABLE < 1 ==="
$unavailablePods = @()  # Store unavailable pod info for second loop

if ($filtered.Count -lt 1) {
    PrintAndSaveOutput -Data "There are no LogicApps deployments in the environment." -OutputFile $outputFile -Append -Color Yellow
}

foreach ($dep in $filtered) {
    $name = $dep.metadata.name
    $namespace = $dep.metadata.namespace
    $status = $dep.status

    $replicas = $status.replicas
    $readyReplicas = $status.readyReplicas
    $updatedReplicas = $status.updatedReplicas
    $availableReplicas = $status.availableReplicas

    # Handle nulls
    if (-not $replicas) { $replicas = 0 }
    if (-not $readyReplicas) { $readyReplicas = 0 }
    if (-not $updatedReplicas) { $updatedReplicas = 0 }
    if (-not $availableReplicas) { $availableReplicas = 0 }

    $ready = "$readyReplicas/$replicas"

    # Age
    $creation = [datetime]$dep.metadata.creationTimestamp
    $now = Get-Date
    $ageSpan = $now - $creation
    if ($ageSpan.TotalDays -ge 1) {
        $age = "{0}d" -f [math]::Floor($ageSpan.TotalDays)
    } else {
        $age = "{0}h" -f [math]::Floor($ageSpan.TotalHours)
    }

    # Add to deployment table
    $line = "{0,-60} {1,-7} {2,-11} {3,-10} {4,-6}" -f $name, $ready, $updatedReplicas, $availableReplicas, $age

    # If not available, get a pod from the deployment
    if ($availableReplicas -lt 1) {
        PrintAndSaveOutput -Data $line -OutputFile $outputFile -Append -Color Red
        # Convert matchLabels to a hashtable manually
        $matchLabels = @{}

        foreach ($prop in $dep.spec.selector.matchLabels.PSObject.Properties) {
            $matchLabels[$prop.Name] = $prop.Value
        }

        $labelParts = @()

        foreach ($kv in $matchLabels.GetEnumerator()) {
            $labelParts += "$($kv.Key)=$($kv.Value)"
        }

        $selector = $labelParts -join ","

        # Get pods matching the selector
        $podJson = kubectl get pods -n $namespace -l $selector -o json | ConvertFrom-Json

        if ($podJson.items.Count -gt 0) {
            $pod = $podJson.items[0]
            $podName = $pod.metadata.name

            $unavailablePodDetails += @(
                "Deployment: $name",
                "Namespace:  $namespace",
                "Pod:        $podName",
                ""
            )
			
			# Store for separate log gathering
            $unavailablePods += [PSCustomObject]@{
                Name      = $name
                Namespace = $namespace
                PodName   = $podName
            }
        } else {
            $unavailablePodDetails += @(
                "Deployment: $name",
                "Namespace:  $namespace",
                "Pod:        (No matching pods found)",
                ""
            )
        }
    }
    else {
        PrintAndSaveOutput -Data $line -OutputFile $outputFile -Append -Color Green
    }
}

if ($unavailablePods.Count -gt 0) {
    Write-Report -Data "`n Get the logs for any pods in failed deployments..." -ForegroundColor Yellow
    # Separate loop to collect logs/events
    foreach ($entry in $unavailablePods) {
        $depdir = "logs_$($entry.Name)"
        Write-PodEventsAndLogs -Namespace $entry.Namespace -PodName $entry.PodName -OutputDir $depdir
    }
}