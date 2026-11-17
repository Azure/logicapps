$installer = Join-Path $PSScriptRoot 'Install-PrivateWorkflowBundle.ps1'
. $installer -SubscriptionId '00000000-0000-0000-0000-000000000001' `
    -ResourceGroup tests -AppName test-app -BundleZip unused.zip

function New-TestBundle {
    param([string] $Path, [string] $ExtraPath, [string] $Version = '1.2.3.4')

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $entries = [ordered] @{
        'bundle.json' = "{`"id`":`"Microsoft.Azure.Functions.ExtensionBundle.Workflows`",`"version`":`"$Version`"}"
        'bin/extensions.json' = '{"extensions":[{"typeName":"Microsoft.Azure.Workflows.WebJobs.Extensions.Initialization.WorkflowExtensionStartup, Microsoft.Azure.Workflows.WebJobs.Extensions"}]}'
        'bin/Microsoft.Azure.Workflows.WebJobs.Extensions.dll' = 'test extension'
        'bin/Microsoft.Azure.Workflows.WebJobs.Extensions.Edge.dll' = 'test edge extension'
        'bin/runtimes/win-x64/native/test.dll' = 'test native file'
    }
    $archive = [IO.Compression.ZipFile]::Open($Path, 'Create')
    try {
        foreach ($entry in $entries.GetEnumerator()) {
            $writer = [IO.StreamWriter]::new($archive.CreateEntry($entry.Key).Open())
            try { $writer.Write($entry.Value) }
            finally { $writer.Dispose() }
        }
        if ($ExtraPath) {
            $writer = [IO.StreamWriter]::new($archive.CreateEntry($ExtraPath).Open())
            try { $writer.Write('extra') }
            finally { $writer.Dispose() }
        }
    }
    finally { $archive.Dispose() }
}

Describe 'Private workflow bundle cache' {
    BeforeEach {
        $bundle = Join-Path $TestDrive "$([guid]::NewGuid().ToString('N')).zip"
        New-TestBundle -Path $bundle
    }

    It 'reads the bundle identity and hashes all files including native files' {
        $manifest = Get-PrivateBundleManifest $bundle
        $manifest.Version | Should Be '1.2.3.4'
        $manifest.FileCount | Should Be 5
        ($manifest.Files.Path -contains 'bin/runtimes/win-x64/native/test.dll') | Should Be $true
        $manifest.Sha256 | Should Be (Get-FileHash $bundle).Hash
    }

    It 'hashes the ZIP in a separate Windows PowerShell process with WhatIf enabled' {
        $command = @"
. '$($installer.Replace("'", "''"))' -SubscriptionId '00000000-0000-0000-0000-000000000001' -ResourceGroup tests -AppName test-app -BundleZip unused.zip
`$WhatIfPreference = `$true
`$manifest = Get-PrivateBundleManifest -Path '$($bundle.Replace("'", "''"))'
if (`$manifest.Sha256 -ne '$((Get-FileHash $bundle).Hash)') { throw 'Preview hash differs.' }
"@
        $null = & powershell.exe -NoProfile -NonInteractive -Command $command 2>&1
        $LASTEXITCODE | Should Be 0
    }

    It 'rejects traversal, rooted paths, Windows aliases, and file-directory conflicts' {
        foreach ($route in @('../escape.dll', '/root.dll', 'C:\escape.dll', 'bin/name:stream',
            'bin/CON.txt', 'bin/trailing./file', 'bin//empty', 'bin/extensions.json/child')) {
            $invalid = Join-Path $TestDrive "$([guid]::NewGuid().ToString('N')).zip"
            New-TestBundle -Path $invalid -ExtraPath $route
            { Get-PrivateBundleManifest $invalid } | Should Throw
        }
    }

    It 'rejects duplicate Windows paths and unsafe bundle versions' {
        $duplicate = Join-Path $TestDrive 'duplicate.zip'
        New-TestBundle -Path $duplicate -ExtraPath 'BIN/EXTENSIONS.JSON'
        { Get-PrivateBundleManifest $duplicate } | Should Throw 'Duplicate'
        $invalid = Join-Path $TestDrive 'version.zip'
        New-TestBundle -Path $invalid -Version '../other'
        { Get-PrivateBundleManifest $invalid } | Should Throw 'numeric version'
    }

    It 'rejects a bundle missing its Windows native directory' {
        $archive = [IO.Compression.ZipFile]::Open($bundle, 'Update')
        try { $archive.GetEntry('bin/runtimes/win-x64/native/test.dll').Delete() }
        finally { $archive.Dispose() }
        { Get-PrivateBundleManifest $bundle } | Should Throw 'native files'
    }

    It 'promotes a complete bundle, reuses an identical cache, and rejects changed bytes' {
        $manifest = Get-PrivateBundleManifest $bundle
        $testHome = Join-Path $TestDrive 'complete'
        $stage = [guid]::NewGuid().ToString('N')
        $payload = Join-Path $testHome "data\PrivateBundleUploads\$stage\payload"
        $null = New-Item -Path $payload -ItemType Directory -Force
        [IO.Compression.ZipFile]::ExtractToDirectory($bundle, $payload)
        Install-PrivateBundleCache $testHome $stage $manifest -InspectOnly | Should Be 'Missing'
        Install-PrivateBundleCache $testHome $stage $manifest | Should Be 'Installed'
        Test-Path $payload | Should Be $false
        Install-PrivateBundleCache $testHome $stage $manifest -InspectOnly | Should Be 'AlreadyPresent'
        $cache = Join-Path $testHome "data\Functions\ExtensionBundles\$($manifest.Id)\$($manifest.Version)"
        Set-Content -LiteralPath (Join-Path $cache 'bin/extensions.json') -Value 'changed'
        { Install-PrivateBundleCache $testHome $stage $manifest } | Should Throw 'differs'
        (Get-Content -LiteralPath (Join-Path $cache 'bin/extensions.json') -Raw).Trim() | Should Be 'changed'
    }

    It 'does not publish a partial bundle or replace an existing partial cache' {
        $manifest = Get-PrivateBundleManifest $bundle
        $testHome = Join-Path $TestDrive 'partial'
        $stage = [guid]::NewGuid().ToString('N')
        $payload = Join-Path $testHome "data\PrivateBundleUploads\$stage\payload"
        $null = New-Item -Path $payload -ItemType Directory -Force
        [IO.Compression.ZipFile]::ExtractToDirectory($bundle, $payload)
        Remove-Item -LiteralPath (Join-Path $payload 'bin/extensions.json')
        { Install-PrivateBundleCache $testHome $stage $manifest } | Should Throw 'file count'
        $cache = Join-Path $testHome "data\Functions\ExtensionBundles\$($manifest.Id)\$($manifest.Version)"
        Test-Path $cache | Should Be $false
        $null = New-Item -Path $cache -ItemType Directory -Force
        { Install-PrivateBundleCache $testHome $stage $manifest -InspectOnly } | Should Throw 'file count'
    }
}

Describe 'Private bundle CDN coordinates' {
    It 'builds the Windows ZIP URL under a container root with or without a trailing slash' {
        foreach ($version in @('1.2.3', '1.2.3.4')) {
            foreach ($root in @('https://cdn.example.com/container', 'https://cdn.example.com/container/')) {
                Get-PrivateBundleDownloadUri -BaseUri $root -Version $version |
                    Should Be "https://cdn.example.com/container/ExtensionBundles/Microsoft.Azure.Functions.ExtensionBundle.Workflows/$version/Microsoft.Azure.Functions.ExtensionBundle.Workflows.$($version)_win-any.zip"
            }
        }
    }

    It 'rejects unsafe CDN roots and noncanonical versions' {
        foreach ($root in @('http://cdn.example.com/container', '/relative',
            'https://user:password@cdn.example.com/container', 'https://cdn.example.com/container?sig=secret',
            'https://cdn.example.com/container#fragment')) {
            { Get-PrivateBundleDownloadUri -BaseUri $root -Version '1.2.3.4' } | Should Throw 'CdnBaseUri'
        }
        foreach ($version in @('latest', '../other', '1.2', '01.2.3', '1.2.3.99999999999')) {
            { Get-PrivateBundleDownloadUri -BaseUri 'https://cdn.example.com/container' -Version $version } |
                Should Throw 'BundleVersion'
        }
    }
}

Describe 'Private bundle request sequencing' {
    BeforeEach {
        $bundle = Join-Path $TestDrive "$([guid]::NewGuid().ToString('N')).zip"
        New-TestBundle -Path $bundle
        $global:PrivateBundleTestState = @{
            Requests = New-Object 'Collections.Generic.List[string]'
            AppSettings = [pscustomobject] @{ UnrelatedSetting = 'keep'; FUNCTIONS_EXTENSIONBUNDLE_SOURCE_URI = 'keep-source' }
            CachePresent = $false
            PromotionFails = $false
            SourceBundle = $bundle
            DownloadPath = $null
            DownloadFails = $false
            CorruptDownload = $false
            AuthenticationCalls = 0
        }
        function az {
            $global:PrivateBundleTestState.AuthenticationCalls++
            $global:LASTEXITCODE = 0
            'test-token'
        }
        Mock Invoke-RestMethod {
            param($Uri, $Method, $Body, $InFile, $OutFile, $Headers)
            $global:PrivateBundleTestState.Requests.Add("$Method $Uri")
            if ($Uri -like 'https://cdn.example.com/*') {
                if ($Headers) { throw 'CDN request unexpectedly contains authentication headers.' }
                $global:PrivateBundleTestState.DownloadPath = $OutFile
                if ($global:PrivateBundleTestState.DownloadFails -or $global:PrivateBundleTestState.CorruptDownload) {
                    [IO.File]::WriteAllText($OutFile, 'incomplete download')
                    if ($global:PrivateBundleTestState.DownloadFails) { throw 'Injected download failure.' }
                }
                else {
                    [IO.File]::Copy($global:PrivateBundleTestState.SourceBundle, $OutFile)
                }
                return
            }
            if ($Uri -like '*/config/appsettings/list?*') {
                return @{ properties = ($global:PrivateBundleTestState.AppSettings | ConvertTo-Json | ConvertFrom-Json) }
            }
            if ($Uri -like '*/config/appsettings?*') {
                $global:PrivateBundleTestState.AppSettings = ($Body | ConvertFrom-Json).properties
                return @{}
            }
            if ($Uri -like '*/api/command') {
                $command = ($Body | ConvertFrom-Json).command
                if ($command -like '*install.ps1*') {
                    if ($command.EndsWith(' inspect')) {
                        $output = if ($global:PrivateBundleTestState.CachePresent) { 'AlreadyPresent' } else { 'Missing' }
                    }
                    elseif ($global:PrivateBundleTestState.PromotionFails) { return @{ ExitCode = 1; Error = 'hash mismatch' } }
                    else { $output = 'Installed'; $global:PrivateBundleTestState.CachePresent = $true }
                    return @{ ExitCode = 0; Output = $output }
                }
                return @{ ExitCode = 0; Output = '' }
            }
            if ($Uri -like '*/api/*') { return @{} }
            return @{
                id = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/tests/providers/Microsoft.Web/sites/test-app'
                kind = 'functionapp,workflowapp'
                properties = @{ reserved = $false; enabledHostNames = @('test-app.scm.azurewebsites.net') }
            }
        }
        $arguments = @{
            SubscriptionId = '00000000-0000-0000-0000-000000000001'
            ResourceGroup = 'tests'; AppName = 'test-app'; BundleZip = $bundle
        }
    }

    It 'pins only after cache promotion, preserves settings, and reuses a second upload' {
        $result = & $installer @arguments
        $result.CacheStatus | Should Be 'Installed'
        $global:PrivateBundleTestState.AppSettings.UnrelatedSetting | Should Be 'keep'
        $global:PrivateBundleTestState.AppSettings.FUNCTIONS_EXTENSIONBUNDLE_SOURCE_URI | Should Be 'keep-source'
        $global:PrivateBundleTestState.AppSettings.AzureFunctionsJobHost__extensionBundle__version | Should Be '[1.2.3.4]'
        $global:PrivateBundleTestState.AppSettings.AzureFunctionsJobHost__extensionBundle__ensureLatest | Should Be 'false'
        $global:PrivateBundleTestState.Requests.Clear()
        $result = & $installer @arguments
        $result.CacheStatus | Should Be 'AlreadyPresent'
        $result.SettingsChanged | Should Be $false
        @($global:PrivateBundleTestState.Requests | Where-Object { $_ -like 'Put */api/zip/*' -or $_ -like 'Put */config/appsettings?*' }).Count | Should Be 0
    }

    It 'does not change settings when remote verification fails' {
        $global:PrivateBundleTestState.PromotionFails = $true
        { & $installer @arguments } | Should Throw 'hash mismatch'
        @($global:PrivateBundleTestState.Requests | Where-Object { $_ -like 'Put */config/appsettings?*' }).Count | Should Be 0
    }

    It 'does not mutate the app with WhatIf or contact Azure for a wrong archive hash' {
        $null = & $installer @arguments -WhatIf
        @($global:PrivateBundleTestState.Requests | Where-Object { $_ -like 'Put *' -or $_ -like '*/api/*' }).Count | Should Be 0
        $global:PrivateBundleTestState.Requests.Clear()
        { & $installer @arguments -ExpectedSha256 ('0' * 64) } | Should Throw 'ExpectedSha256'
        $global:PrivateBundleTestState.Requests.Count | Should Be 0
    }

    It 'downloads and verifies the requested version before uploading and removes the download' {
        $arguments.Remove('BundleZip')
        $result = & $installer @arguments -CdnBaseUri 'https://cdn.example.com/container/' `
            -BundleVersion '1.2.3.4' -ExpectedSha256 (Get-FileHash $bundle).Hash
        $result.Version | Should Be '1.2.3.4'
        $result.Sha256 | Should Be (Get-FileHash $bundle).Hash
        $result.CacheStatus | Should Be 'Installed'
        $global:PrivateBundleTestState.Requests[0] |
            Should Be 'Get https://cdn.example.com/container/ExtensionBundles/Microsoft.Azure.Functions.ExtensionBundle.Workflows/1.2.3.4/Microsoft.Azure.Functions.ExtensionBundle.Workflows.1.2.3.4_win-any.zip'
        Test-Path (Split-Path $global:PrivateBundleTestState.DownloadPath) | Should Be $false
        Test-Path $bundle | Should Be $true
    }

    It 'validates a CDN download with WhatIf without changing the app or leaving temporary files' {
        $arguments.Remove('BundleZip')
        $null = & $installer @arguments -CdnBaseUri 'https://cdn.example.com/container' `
            -BundleVersion '1.2.3.4' -ExpectedSha256 (Get-FileHash $bundle).Hash -WhatIf
        @($global:PrivateBundleTestState.Requests | Where-Object { $_ -like 'Put *' -or $_ -like '*/api/*' }).Count | Should Be 0
        Test-Path (Split-Path $global:PrivateBundleTestState.DownloadPath) | Should Be $false
    }

    It 'rejects mismatched CDN versions and hashes before authentication and cleans up' {
        $arguments.Remove('BundleZip')
        { & $installer @arguments -CdnBaseUri 'https://cdn.example.com/container' -BundleVersion '1.2.3.5' } |
            Should Throw 'does not match BundleVersion'
        Test-Path (Split-Path $global:PrivateBundleTestState.DownloadPath) | Should Be $false
        { & $installer @arguments -CdnBaseUri 'https://cdn.example.com/container' -BundleVersion '1.2.3.4' -ExpectedSha256 ('0' * 64) } |
            Should Throw 'ExpectedSha256'
        Test-Path (Split-Path $global:PrivateBundleTestState.DownloadPath) | Should Be $false
        $global:PrivateBundleTestState.AuthenticationCalls | Should Be 0
    }

    It 'cleans up partial and corrupt downloads without contacting Azure' {
        $arguments.Remove('BundleZip')
        $global:PrivateBundleTestState.DownloadFails = $true
        { & $installer @arguments -CdnBaseUri 'https://cdn.example.com/container' -BundleVersion '1.2.3.4' } |
            Should Throw 'Bundle request failed'
        Test-Path (Split-Path $global:PrivateBundleTestState.DownloadPath) | Should Be $false
        $global:PrivateBundleTestState.DownloadFails = $false
        $global:PrivateBundleTestState.CorruptDownload = $true
        { & $installer @arguments -CdnBaseUri 'https://cdn.example.com/container' -BundleVersion '1.2.3.4' } | Should Throw
        Test-Path (Split-Path $global:PrivateBundleTestState.DownloadPath) | Should Be $false
        $global:PrivateBundleTestState.AuthenticationCalls | Should Be 0
    }

    It 'cleans up the CDN download if remote verification fails' {
        $arguments.Remove('BundleZip')
        $global:PrivateBundleTestState.PromotionFails = $true
        { & $installer @arguments -CdnBaseUri 'https://cdn.example.com/container' -BundleVersion '1.2.3.4' } |
            Should Throw 'hash mismatch'
        Test-Path (Split-Path $global:PrivateBundleTestState.DownloadPath) | Should Be $false
        @($global:PrivateBundleTestState.Requests | Where-Object { $_ -like 'Put */config/appsettings?*' }).Count | Should Be 0
    }

    It 'does not allow local ZIP and CDN inputs together' {
        { & $installer @arguments -CdnBaseUri 'https://cdn.example.com/container' -BundleVersion '1.2.3.4' } | Should Throw
        $global:PrivateBundleTestState.Requests.Count | Should Be 0
    }
    AfterEach { Remove-Variable PrivateBundleTestState -Scope Global -ErrorAction SilentlyContinue }
}
