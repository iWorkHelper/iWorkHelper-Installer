[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = '1.0.0',
    [ValidateSet('Release-Intranet', 'Release-Internet')]
    [string]$OutlookConfiguration = 'Release-Intranet',
    [string]$ManifestCertificateThumbprint,
    [switch]$SkipAddinBuild,
    [switch]$SkipInstallerBuild
)

$ErrorActionPreference = 'Stop'
$installerRoot = $PSScriptRoot
$workspaceRoot = Split-Path -Parent $installerRoot
$payloadRoot = Join-Path $installerRoot 'Payload'
$artifactsRoot = Join-Path $installerRoot 'artifacts'
$msbuild = Join-Path ${env:ProgramFiles} 'Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe'

# dotnet resolves repository-local tool manifests from the current directory.
# Keep the script callable from either this repository or its parent workspace.
Set-Location -LiteralPath $installerRoot

if (-not (Test-Path -LiteralPath $msbuild)) {
    throw 'Visual Studio 2022 MSBuild was not found. Install Visual Studio with Office/SharePoint development tools.'
}

if (-not $SkipAddinBuild) {
    if (-not $ManifestCertificateThumbprint) {
        throw 'ManifestCertificateThumbprint is required. Run scripts\Ensure-DevelopmentCertificate.ps1 or provide a release certificate thumbprint.'
    }
    & $msbuild (Join-Path $workspaceRoot 'eWorkHelper\eWorkhelper.sln') /restore /t:Build /p:Configuration=Release "/p:Platform=Any CPU" "/p:ManifestCertificateThumbprint=$ManifestCertificateThumbprint" /p:ManifestKeyFile=
    if ($LASTEXITCODE -ne 0) { throw 'eWorkHelper Release build failed.' }

    & $msbuild (Join-Path $workspaceRoot 'oWorkHelper\oWorkhelper.sln') /restore /t:Build "/p:Configuration=$OutlookConfiguration" "/p:Platform=Any CPU" "/p:ManifestCertificateThumbprint=$ManifestCertificateThumbprint" /p:ManifestKeyFile=
    if ($LASTEXITCODE -ne 0) { throw 'oWorkHelper Release build failed.' }
}

& (Join-Path $installerRoot 'scripts\Collect-Payload.ps1') -OutlookConfiguration $OutlookConfiguration
& (Join-Path $installerRoot 'tests\Test-InstallerSources.ps1')

if ($SkipInstallerBuild) {
    Write-Host 'Payload and static validation completed; WiX build was skipped.'
    exit 0
}

New-Item -ItemType Directory -Force -Path $artifactsRoot | Out-Null
$productCodeInput = [Text.Encoding]::UTF8.GetBytes("iWorkHelper MSI|$Version")
$productCodeHash = [Security.Cryptography.SHA256]::Create().ComputeHash($productCodeInput)
$productCodeBytes = [byte[]]$productCodeHash[0..15]
$installerProductCode = '{' + ([Guid]::new($productCodeBytes)).ToString().ToUpperInvariant() + '}'
dotnet tool restore
if ($LASTEXITCODE -ne 0) { throw 'WiX tool restore failed.' }
dotnet wix eula accept wix7
if ($LASTEXITCODE -ne 0) { throw 'WiX 7 EULA acceptance failed.' }
# Version/ProductCode are preprocessor constants and are not sufficient for
# MSBuild's up-to-date check, so force a rebuild for every requested version.
dotnet build (Join-Path $installerRoot 'MSI\iWorkHelper.Msi.wixproj') -c Release -t:Rebuild "/p:InstallerVersion=$Version" "/p:InstallerProductCode=$installerProductCode"
if ($LASTEXITCODE -ne 0) { throw 'MSI build failed.' }

$localizedMsis = Get-ChildItem (Join-Path $installerRoot 'MSI\bin') -Recurse -Filter 'iWorkHelper.msi'
$englishMsi = $localizedMsis | Where-Object FullName -Match '[\\/]en-US[\\/]' | Select-Object -First 1
$chineseMsi = $localizedMsis | Where-Object FullName -Match '[\\/]zh-CN[\\/]' | Select-Object -First 1
if (-not $englishMsi -or -not $chineseMsi) { throw 'Both en-US and zh-CN MSI outputs are required.' }
$baseMsi = Join-Path $artifactsRoot 'iWorkHelper.msi'
$zhMst = Join-Path $artifactsRoot 'iWorkHelper.zh-CN.mst'
Copy-Item -LiteralPath $englishMsi.FullName -Destination $baseMsi -Force
$chineseMsiPath = [string]$chineseMsi.FullName
# WiX 7 Scope="perUserOrMachine" authors the dual-context properties, but its
# generated Summary Word Count does not set the no-elevation bit. Without that
# bit Windows Installer itself raises UAC before a per-user MSI transaction can
# start. Patch both language databases before producing the language transform.
& (Join-Path $installerRoot 'scripts\Set-MsiPerUserNoElevation.ps1') -MsiPath @($baseMsi, $chineseMsiPath)
dotnet wix msi transform -t language $baseMsi $chineseMsiPath -out $zhMst
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $zhMst)) { throw 'zh-CN language transform creation failed.' }

# Build the custom BA explicitly. The Bundle build below intentionally disables
# ProjectReference builds so it cannot regenerate the versioned MSI.
dotnet build (Join-Path $installerRoot 'BootstrapperApplication\iWorkHelper.BootstrapperApplication.csproj') -c Release
if ($LASTEXITCODE -ne 0) { throw 'Bootstrapper Application build failed.' }

# The MSI was built above with the version-specific deterministic ProductCode.
# Do not let the Bundle ProjectReference rebuild it with default properties.
# The MSI is an artifacts-path payload, which MSBuild does not track as a normal
# project input. Force rebinding so a version bump cannot reuse a stale Chain.
dotnet build (Join-Path $installerRoot 'Bundle\iWorkHelper.Bundle.wixproj') -c Release -t:Rebuild "/p:InstallerVersion=$Version" /p:BuildProjectReferences=false
if ($LASTEXITCODE -ne 0) { throw 'Bootstrapper build failed.' }

$builtExe = Get-ChildItem (Join-Path $installerRoot 'Bundle\bin') -Recurse -Filter "iWorkHelper-Setup-$Version-x64.exe" | Select-Object -First 1
if (-not $builtExe) { throw 'Built bootstrapper was not found.' }
Copy-Item -LiteralPath $builtExe.FullName -Destination $artifactsRoot -Force
dotnet wix msi validate $baseMsi
if ($LASTEXITCODE -ne 0) { throw 'MSI ICE validation failed.' }
& (Join-Path $installerRoot 'tests\Test-MsiDatabase.ps1') -MsiPath $baseMsi -ChineseTransformPath $zhMst
& (Join-Path $installerRoot 'tests\Test-Bundle.ps1') -BundlePath (Join-Path $artifactsRoot $builtExe.Name) -ExpectedVersion $Version -ExpectedProductCode $installerProductCode
Write-Host "Final installer: artifacts\$($builtExe.Name)"
