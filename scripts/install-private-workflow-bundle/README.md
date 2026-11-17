# Install a private workflow bundle

Use `Install-PrivateWorkflowBundle.ps1` to install a private extension bundle in an
existing **Windows Logic Apps Standard** app. Supply a local Windows bundle ZIP,
or an HTTPS CDN container root and an exact version.

The script verifies the files in the app's bundle cache before pinning the app to
that version. **Changing bundle settings recycles the app.** It does not create
resources, deploy workflows, change the hosting plan, or publish a bundle to a CDN.

## Prerequisites

- Windows PowerShell 5.1 or later.
- Azure CLI installed and signed in with `az login`.
- An existing Windows Logic Apps Standard app in Azure public cloud.
- Permission to read and update the app settings and access its Kudu endpoint
  using Microsoft Entra authentication. The script does not enable SCM Basic Auth.
- Network access to Azure management, the app's SCM endpoint, and the CDN if used.

Linux apps, deployment slots, sovereign clouds, and custom
`AzureFunctionsJobHost__extensionBundle__downloadPath` settings are not supported.

## Download and install from a CDN

Run these commands from this directory. Replace the placeholders with your app
and bundle coordinates:

```powershell
az login

$target = @{
    SubscriptionId = '<subscription-id>'
    ResourceGroup  = '<resource-group>'
    AppName        = '<logic-app-name>'
}

.\Install-PrivateWorkflowBundle.ps1 @target `
    -CdnBaseUri 'https://<cdn-host>/<container>' `
    -BundleVersion '1.2.3.4' `
    -WhatIf
```

`-WhatIf` downloads and validates the ZIP and reads the target app settings, but
does not upload files or change the app. **Remove `-WhatIf` to install.**

`CdnBaseUri` must be the container root, not an index file, version directory, or
ZIP URL. The script downloads this path beneath it:

```text
ExtensionBundles/Microsoft.Azure.Functions.ExtensionBundle.Workflows/<version>/Microsoft.Azure.Functions.ExtensionBundle.Workflows.<version>_win-any.zip
```

The CDN must allow anonymous HTTPS downloads. Credentials, query strings
(including SAS tokens), and fragments in `CdnBaseUri` are not supported.
Azure credentials are not sent to the CDN. Versions must have three or four
numeric parts, such as `1.2.3` or `1.2.3.4`; ranges and `latest` are not accepted.
The version inside `bundle.json` must match the requested version.

## Install a local ZIP

Use `-BundleZip` instead of the two CDN parameters:

```powershell
.\Install-PrivateWorkflowBundle.ps1 @target `
    -BundleZip 'C:\bundles\Microsoft.Azure.Functions.ExtensionBundle.Workflows.1.2.3.4_win-any.zip' `
    -WhatIf
```

Pass the Windows platform bundle ZIP, not the outer pipeline-artifact ZIP.
The ZIP must contain `bundle.json` at its root and the extension assemblies,
startup registration, and Windows native files under `bin`.
The local ZIP is not deleted or changed.

For either input mode, add `-ExpectedSha256` with a trusted 64-character SHA-256
digest to require an exact archive match:

```powershell
.\Install-PrivateWorkflowBundle.ps1 @target `
    -BundleZip 'C:\bundles\bundle_win-any.zip' `
    -ExpectedSha256 '<trusted-sha256>' `
    -WhatIf
```

Use a digest from the bundle publisher or an independently verified artifact.
A version string alone does not establish which source commit produced a bundle.

## What installation changes

The script:

1. Validates the archive paths, bundle identity, version, required files, and
   optional archive hash.
2. Uploads to a unique staging directory through Kudu.
3. Checks every extracted file's path, length, and SHA-256 hash before moving the
   complete payload into the versioned bundle cache.
4. Pins these app settings, preserving unrelated settings:

| Setting | Value |
|---|---|
| `AzureFunctionsJobHost__extensionBundle__id` | `Microsoft.Azure.Functions.ExtensionBundle.Workflows` |
| `AzureFunctionsJobHost__extensionBundle__version` | `[<version>]` |
| `AzureFunctionsJobHost__extensionBundle__ensureLatest` | `false` |

The cache location is:

```text
%HOME%\data\Functions\ExtensionBundles\Microsoft.Azure.Functions.ExtensionBundle.Workflows\<version>
```

An identical cached bundle is reused. A partial cache or different content at the
same version causes an error; the script does not overwrite that version.
An identical repeat install leaves settings unchanged.

The script preserves `FUNCTIONS_EXTENSIONBUNDLE_SOURCE_URI`. Supplying
`-CdnBaseUri` selects the installer download source; it does not configure a
runtime CDN fallback. The installed cache must remain available.

## Results and cleanup

A successful install returns the app ID, bundle ID and version, archive hash,
file count, uncompressed size, and these fields:

| Field | Meaning |
|---|---|
| `CacheStatus` | `Installed` or `AlreadyPresent`. |
| `SettingsChanged` | Whether the script updated the bundle app settings. |
| `StagingCleaned` | Whether it removed the remote staging directory. |

Downloaded ZIPs use a temporary local directory that the script removes on
success or failure. It removes remote staging after a successful install.
If cleanup fails, the warning identifies the directory to inspect. Failed uploads
can also leave their unique directory under `%HOME%\data\PrivateBundleUploads`.
Do not delete the active bundle cache to clean up staging.

The script does not run workflow smoke tests or roll back automatically. After
installation, allow the app to recycle, verify the loaded runtime version, and
run a representative workflow. Do not issue an overlapping restart.

Before installing, record the original values or absence of the three bundle
settings above. To switch to a previous known-good bundle, rerun the installer
with that bundle. To restore normal bundle selection, restore the original
settings and verify the app and workflows recover.

## Run the tests

The tests use generated ZIP fixtures and mocked Azure/CDN requests; they do not
change an Azure app. Run them with Windows PowerShell and Pester 3.4.0:

```powershell
Import-Module Pester -RequiredVersion 3.4.0
$result = Invoke-Pester -Script .\Install-PrivateWorkflowBundle.Tests.ps1 -PassThru
if ($result.FailedCount -gt 0 -or $result.TotalCount -eq 0) {
    throw 'Bundle installer tests failed or no tests were discovered.'
}
```
