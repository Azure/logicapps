#requires -Version 5.1
<#
.SYNOPSIS
Uploads a private workflow bundle into a Windows Logic App Standard bundle cache.
.DESCRIPTION
Uses the current Azure CLI login and Azure public-cloud ARM/SCM endpoints. Requires
permission to read/update app settings and use Kudu. Does not enable publishing
credentials, deploy wwwroot, change the hosting plan, or restart the app explicitly.

Checks every extracted file before promoting the bundle and pinning its version.
An identical cached bundle is reused; different content at that version is rejected.
Accepts a local Windows ZIP or downloads an exact version from an anonymous HTTPS
CDN container root. Downloaded ZIPs are temporary and use the same validation.
WhatIf downloads and validates the bundle but does not change the app.
Pinning settings recycles the app. Workflow/runtime smoke checks remain the caller's
responsibility. The cache must remain available; this does not publish a CDN fallback.
.EXAMPLE
.\Install-PrivateWorkflowBundle.ps1 -SubscriptionId <subscription> `
    -ResourceGroup <group> -AppName <app> -BundleZip C:\bundles\bundle_win-any.zip
.EXAMPLE
.\Install-PrivateWorkflowBundle.ps1 -SubscriptionId <subscription> `
    -ResourceGroup <group> -AppName <app> `
    -CdnBaseUri https://cdn.example.com/container -BundleVersion 1.198.2.1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Zip')]
param(
    [Parameter(Mandatory = $true)]
    [guid] $SubscriptionId,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-zA-Z0-9_.()-]+$')]
    [string] $ResourceGroup,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]$')]
    [string] $AppName,
    [Parameter(Mandatory = $true, ParameterSetName = 'Zip')]
    [string] $BundleZip,
    [Parameter(Mandatory = $true, ParameterSetName = 'Cdn')]
    [uri] $CdnBaseUri,
    [Parameter(Mandatory = $true, ParameterSetName = 'Cdn')]
    [ValidatePattern('^\d+\.\d+\.\d+(\.\d+)?$')]
    [string] $BundleVersion,
    [ValidatePattern('^[a-fA-F0-9]{64}$')]
    [string] $ExpectedSha256
)

function Get-PrivateBundleDownloadUri {
    param([uri] $BaseUri, [string] $Version)

    if (-not $BaseUri.IsAbsoluteUri -or $BaseUri.Scheme -ne 'https' -or
        $BaseUri.UserInfo -or $BaseUri.Query -or $BaseUri.Fragment) {
        throw 'CdnBaseUri must be an absolute HTTPS container root without credentials, a query, or a fragment.'
    }
    $parsedVersion = $null
    if ($Version -notmatch '^\d+\.\d+\.\d+(\.\d+)?$' -or
        -not [Version]::TryParse($Version, [ref] $parsedVersion) -or
        $parsedVersion.ToString() -cne $Version) {
        throw 'BundleVersion must be an exact canonical numeric version.'
    }
    $bundleId = 'Microsoft.Azure.Functions.ExtensionBundle.Workflows'
    return "$($BaseUri.AbsoluteUri.TrimEnd('/'))/ExtensionBundles/$bundleId/$Version/$bundleId.$($Version)_win-any.zip"
}

function Get-PrivateBundleManifest {
    param([string] $Path)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $routes = @{}
        $files = @(
            foreach ($entry in $archive.Entries) {
                $route = $entry.FullName.Replace('\', '/').TrimEnd('/')
                if (-not $route -or $route.StartsWith('/') -or $route -match '[\x00-\x1f<>:"|?*]') {
                    throw "Unsafe archive path '$($entry.FullName)'."
                }
                foreach ($segment in $route.Split('/')) {
                    if (-not $segment -or $segment -in @('.', '..') -or $segment -match '[ .]$' -or
                        $segment -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)') {
                        throw "Unsafe archive path '$($entry.FullName)'."
                    }
                }
                if ((($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) {
                    throw "Archive links are not supported: '$route'."
                }
                if ($routes.ContainsKey($route)) {
                    throw "Duplicate archive path '$route'."
                }
                $directory = $entry.FullName.EndsWith('/') -or $entry.FullName.EndsWith('\')
                $routes[$route] = $directory
                if ($directory) { continue }
                $stream = $entry.Open()
                $hasher = [Security.Cryptography.SHA256]::Create()
                try {
                    [pscustomobject] @{
                        Path = $route
                        Length = $entry.Length
                        Sha256 = [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-', '')
                    }
                }
                finally {
                    $hasher.Dispose()
                    $stream.Dispose()
                }
            }
        )
        foreach ($route in @($routes.Keys)) {
            $parent = $route
            while ($parent.Contains('/')) {
                $parent = $parent.Substring(0, $parent.LastIndexOf('/'))
                if ($routes.ContainsKey($parent) -and -not $routes[$parent]) {
                    throw "File/directory conflict at '$parent'."
                }
            }
        }
        foreach ($required in @('bundle.json', 'bin/extensions.json',
            'bin/Microsoft.Azure.Workflows.WebJobs.Extensions.dll',
            'bin/Microsoft.Azure.Workflows.WebJobs.Extensions.Edge.dll')) {
            if (-not ($files | Where-Object { $_.Path -ceq $required -and $_.Length -gt 0 })) {
                throw "Bundle is missing '$required'. Use an extracted Windows platform bundle ZIP."
            }
        }
        if (-not ($files | Where-Object { $_.Path -like 'bin/runtimes/win-x64/native/*' })) {
            throw 'Bundle is missing Windows x64 native files.'
        }
        $reader = [IO.StreamReader]::new($archive.GetEntry('bundle.json').Open())
        try { $metadata = $reader.ReadToEnd() | ConvertFrom-Json }
        finally { $reader.Dispose() }
        $parsedVersion = $null
        if ($metadata.id -cne 'Microsoft.Azure.Functions.ExtensionBundle.Workflows' -or
            $metadata.version -notmatch '^\d+\.\d+\.\d+(\.\d+)?$' -or
            -not [Version]::TryParse($metadata.version, [ref] $parsedVersion) -or
            $parsedVersion.ToString() -cne $metadata.version) {
            throw 'Expected a workflow bundle with a numeric version.'
        }
        $reader = [IO.StreamReader]::new($archive.GetEntry('bin/extensions.json').Open())
        try { $extensions = $reader.ReadToEnd() | ConvertFrom-Json }
        finally { $reader.Dispose() }
        if (-not ($extensions.extensions | Where-Object {
            $_.typeName -like 'Microsoft.Azure.Workflows.WebJobs.Extensions.Initialization.WorkflowExtensionStartup,*'
        })) {
            throw 'Bundle does not register WorkflowExtensionStartup.'
        }
        # NOTE(rohithah): Stream hashing avoids the Windows PowerShell path lookup that WhatIf skips.
        $archiveStream = [IO.File]::OpenRead($Path)
        try { $archiveHash = (Get-FileHash -InputStream $archiveStream -Algorithm SHA256).Hash }
        finally { $archiveStream.Dispose() }
        [pscustomobject] @{
            Id = $metadata.id
            Version = $metadata.version
            Sha256 = $archiveHash
            Files = $files
            FileCount = $files.Count
            UncompressedBytes = ($files | Measure-Object Length -Sum).Sum
        }
    }
    finally { $archive.Dispose() }
}

function Assert-PrivateBundleFiles {
    param([string] $Root, [object] $Manifest)

    if ((Get-Item -LiteralPath $Root -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'Bundle cache root is a reparse point.'
    }
    $items = @(Get-ChildItem -LiteralPath $Root -Force -Recurse -ErrorAction Stop)
    if ($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) {
        throw 'Bundle cache contains a reparse point.'
    }
    if (@($items | Where-Object { -not $_.PSIsContainer }).Count -ne $Manifest.FileCount) {
        throw 'Bundle cache file count differs from the archive.'
    }
    foreach ($file in $Manifest.Files) {
        $path = Join-Path $Root $file.Path.Replace('/', '\')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            (Get-Item -LiteralPath $path).Length -ne $file.Length -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.Sha256) {
            throw "Bundle cache differs at '$($file.Path)'."
        }
    }
}

function Install-PrivateBundleCache {
    param([string] $HomePath, [string] $StageName, [object] $Manifest, [switch] $InspectOnly)

    if ($StageName -notmatch '^[a-f0-9]{32}$' -or
        $Manifest.Id -cne 'Microsoft.Azure.Functions.ExtensionBundle.Workflows' -or
        $Manifest.Version -notmatch '^\d+\.\d+\.\d+(\.\d+)?$') {
        throw 'Invalid bundle cache coordinates.'
    }
    $cacheParent = Join-Path $HomePath "data\Functions\ExtensionBundles\$($Manifest.Id)"
    $destination = Join-Path $cacheParent $Manifest.Version
    if (Test-Path -LiteralPath $destination) {
        Assert-PrivateBundleFiles -Root $destination -Manifest $Manifest
        return 'AlreadyPresent'
    }
    if ($InspectOnly) { return 'Missing' }

    $payload = Join-Path $HomePath "data\PrivateBundleUploads\$StageName\payload"
    Assert-PrivateBundleFiles -Root $payload -Manifest $Manifest
    $null = New-Item -Path $cacheParent -ItemType Directory -Force
    [IO.Directory]::Move($payload, $destination)
    return 'Installed'
}

function Invoke-PrivateBundleRequest {
    param([hashtable] $Arguments)

    try { Invoke-RestMethod @Arguments -ErrorAction Stop -TimeoutSec 600 }
    catch {
        # NOTE(rohithah): App-settings responses can contain secrets; keep them out of errors.
        $status = if ($_.Exception.Response) { [int] $_.Exception.Response.StatusCode } else { 'unavailable' }
        throw "Bundle request failed: $($Arguments.Method) $($Arguments.Uri) (HTTP $status). Check access and app state."
    }
}

function Invoke-PrivateBundleCommand {
    param([string] $ScmUri, [hashtable] $Headers, [string] $Command)

    $response = Invoke-PrivateBundleRequest @{
        Method = 'Post'; Headers = $Headers; Uri = "$ScmUri/api/command"
        ContentType = 'application/json'
        Body = (@{ command = $Command; dir = 'C:\home' } | ConvertTo-Json -Compress)
    }
    if ($response.ExitCode -ne 0) {
        throw "Bundle cache command failed: $($response.Error)"
    }
    return $response.Output.Trim()
}

if ($MyInvocation.InvocationName -ne '.') {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    $downloadDirectory = $null
    $archiveLock = $null
    try {
        if ($PSCmdlet.ParameterSetName -eq 'Cdn') {
            $downloadUri = Get-PrivateBundleDownloadUri -BaseUri $CdnBaseUri -Version $BundleVersion
            $downloadDirectory = Join-Path ([IO.Path]::GetTempPath()) "logicapps-private-bundle-$([guid]::NewGuid().ToString('N'))"
            $null = [IO.Directory]::CreateDirectory($downloadDirectory)
            $bundlePath = Join-Path $downloadDirectory 'bundle.zip'
            $null = Invoke-PrivateBundleRequest @{
                Method = 'Get'; Uri = $downloadUri; OutFile = $bundlePath
            }
        }
        else {
            $bundlePath = (Resolve-Path -LiteralPath $BundleZip).ProviderPath
        }
        $archiveLock = [IO.File]::Open($bundlePath, 'Open', 'Read', 'Read')
        $manifest = Get-PrivateBundleManifest -Path $bundlePath
        if ($PSCmdlet.ParameterSetName -eq 'Cdn' -and $manifest.Version -cne $BundleVersion) {
            throw 'Downloaded bundle version does not match BundleVersion.'
        }
        if ($ExpectedSha256 -and $manifest.Sha256 -ne $ExpectedSha256) {
            throw 'Bundle ZIP does not match ExpectedSha256.'
        }
        $token = az account get-access-token --subscription $SubscriptionId `
            --resource https://management.azure.com/ --query accessToken -o tsv --only-show-errors
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
            throw 'Azure CLI authentication failed. Run az login for the target subscription.'
        }
        $headers = @{ Authorization = "Bearer $token" }
        $siteUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Web/sites/$AppName"
        $site = Invoke-PrivateBundleRequest @{ Method = 'Get'; Headers = $headers; Uri = "$siteUri`?api-version=2023-12-01" }
        $scmHost = "$AppName.scm.azurewebsites.net"
        if ($site.kind -notmatch '(^|,)workflowapp(,|$)' -or $site.properties.reserved -or
            $site.properties.enabledHostNames -notcontains $scmHost) {
            throw 'Target must be a Windows Logic App Standard with an Azure public-cloud SCM endpoint.'
        }
        $settingsUri = "$siteUri/config/appsettings"
        $settings = Invoke-PrivateBundleRequest @{
            Method = 'Post'; Headers = $headers; Uri = "$settingsUri/list?api-version=2023-12-01"
        }
        if ($settings.properties.AzureFunctionsJobHost__extensionBundle__downloadPath) {
            throw 'Custom bundle download paths are not supported.'
        }
        if (-not $PSCmdlet.ShouldProcess($site.id, "Upload and pin workflow bundle $($manifest.Version) ($($manifest.Sha256))")) {
            return
        }

        $stageName = [guid]::NewGuid().ToString('N')
        $scmUri = "https://$scmHost"
        $remoteStage = "%HOME%\data\PrivateBundleUploads\$stageName"
        $null = Invoke-PrivateBundleCommand -ScmUri $scmUri -Headers $headers `
            -Command "mkdir `"$remoteStage`""
        $stageUri = "$scmUri/api/vfs/data/PrivateBundleUploads/$stageName"
        $remoteScript = @"
`$ErrorActionPreference = 'Stop'
function Assert-PrivateBundleFiles { ${function:Assert-PrivateBundleFiles} }
function Install-PrivateBundleCache { ${function:Install-PrivateBundleCache} }
`$manifest = Get-Content -LiteralPath (Join-Path `$PSScriptRoot 'manifest.json') -Raw | ConvertFrom-Json
Install-PrivateBundleCache -HomePath `$env:HOME -StageName '$stageName' -Manifest `$manifest -InspectOnly:([bool]`$args[0])
"@
        foreach ($upload in @(
            @{ Name = 'manifest.json'; Text = ($manifest | ConvertTo-Json -Depth 6 -Compress) },
            @{ Name = 'install.ps1'; Text = $remoteScript }
        )) {
            $null = Invoke-PrivateBundleRequest @{
                Method = 'Put'; Headers = $headers; Uri = "$stageUri/$($upload.Name)"
                ContentType = 'application/octet-stream'; Body = [Text.Encoding]::UTF8.GetBytes($upload.Text)
            }
        }
        $command = "powershell.exe -NoProfile -NonInteractive -File `"$remoteStage\install.ps1`""
        $cacheStatus = Invoke-PrivateBundleCommand -ScmUri $scmUri -Headers $headers -Command "$command inspect"
        if ($cacheStatus -eq 'Missing') {
            Write-Verbose "Uploading $($manifest.FileCount) files to staging directory '$stageName'."
            $null = Invoke-PrivateBundleRequest @{
                Method = 'Put'; Headers = $headers; Uri = "$scmUri/api/zip/data/PrivateBundleUploads/$stageName/payload/"
                ContentType = 'application/zip'; InFile = $bundlePath
            }
            $cacheStatus = Invoke-PrivateBundleCommand -ScmUri $scmUri -Headers $headers -Command $command
        }
        if ($cacheStatus -notin @('Installed', 'AlreadyPresent')) {
            throw "Unexpected cache result '$cacheStatus'. App settings were not changed."
        }

        $settings = Invoke-PrivateBundleRequest @{
            Method = 'Post'; Headers = $headers; Uri = "$settingsUri/list?api-version=2023-12-01"
        }
        $desired = @{
            AzureFunctionsJobHost__extensionBundle__id = $manifest.Id
            AzureFunctionsJobHost__extensionBundle__version = "[$($manifest.Version)]"
            AzureFunctionsJobHost__extensionBundle__ensureLatest = 'false'
        }
        $settingsChanged = $false
        foreach ($name in $desired.Keys) {
            if ($settings.properties.$name -cne $desired[$name]) {
                $settingsChanged = $true
                $settings.properties | Add-Member -MemberType NoteProperty -Name $name -Value $desired[$name] -Force
            }
        }
        if ($settingsChanged) {
            $null = Invoke-PrivateBundleRequest @{
                Method = 'Put'; Headers = $headers; Uri = "$settingsUri`?api-version=2023-12-01"
                ContentType = 'application/json'
                Body = (@{ properties = $settings.properties } | ConvertTo-Json -Depth 10 -Compress)
            }
        }
        $actual = Invoke-PrivateBundleRequest @{
            Method = 'Post'; Headers = $headers; Uri = "$settingsUri/list?api-version=2023-12-01"
        }
        foreach ($name in $desired.Keys) {
            if ($actual.properties.$name -cne $desired[$name]) {
                throw "App-setting verification failed for '$name'. The verified cache remains available."
            }
        }
        $stagingCleaned = $false
        try {
            $null = Invoke-PrivateBundleCommand -ScmUri $scmUri -Headers $headers `
                -Command "powershell.exe -NoProfile -NonInteractive -Command `"Remove-Item -LiteralPath '$remoteStage' -Recurse -Force`""
            $stagingCleaned = $true
        }
        catch {
            Write-Warning "Bundle is installed and pinned, but staging cleanup failed. Remove only 'data\PrivateBundleUploads\$stageName' after SCM recovers."
        }
        [pscustomobject] @{
            AppId = $site.id
            BundleId = $manifest.Id
            Version = $manifest.Version
            Sha256 = $manifest.Sha256
            FileCount = $manifest.FileCount
            UncompressedBytes = $manifest.UncompressedBytes
            CacheStatus = $cacheStatus
            SettingsChanged = $settingsChanged
            StagingCleaned = $stagingCleaned
        }
    }
    finally {
        if ($archiveLock) { $archiveLock.Dispose() }
        if ($downloadDirectory -and (Test-Path -LiteralPath $downloadDirectory)) {
            try { Remove-Item -LiteralPath $downloadDirectory -Recurse -Force -WhatIf:$false -Confirm:$false }
            catch { Write-Warning "Could not remove temporary bundle directory '$downloadDirectory'." }
        }
    }
}
