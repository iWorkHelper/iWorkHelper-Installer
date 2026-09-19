param(
    [string]$InstallerVersion = '1.3.0',
    [switch]$SkipPluginBuild,
    [switch]$AcquirePrerequisites
)

$ErrorActionPreference = 'Stop'

$InstallerFileVersion = if ($InstallerVersion -match '^\d+\.\d+\.\d+$') { "$InstallerVersion.0" } else { $InstallerVersion }

function Fail($Message) {
    Write-Error "ERROR: $Message"
    exit 1
}

function Find-MSBuild {
    $candidates = @()
    $cmd = Get-Command msbuild.exe -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += $cmd.Source }
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($root) {
            $candidates += Get-ChildItem -LiteralPath $root -Filter MSBuild.exe -Recurse -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty FullName
        }
    }
    $match = $candidates | Where-Object { $_ -match '\\Microsoft Visual Studio\\2022\\.*\\MSBuild\\Current\\Bin\\(amd64\\)?MSBuild\.exe$' } | Select-Object -First 1
    if (-not $match) {
        $match = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    }
    return $match
}

function Find-ISCC {
    $candidates = @()
    $cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += $cmd.Source }
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($root) {
            $candidates += (Join-Path $root 'Inno Setup 7\ISCC.exe')
            $candidates += (Join-Path $root 'Inno Setup 6\ISCC.exe')
        }
    }
    if ($env:LocalAppData) {
        $candidates += (Join-Path $env:LocalAppData 'Programs\Inno Setup 7\ISCC.exe')
        $candidates += (Join-Path $env:LocalAppData 'Programs\Inno Setup 6\ISCC.exe')
    }
    return $candidates | Select-Object -Unique | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

function Get-ProductVersion($Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Fail "Version source file not found: $Path"
    }
    $info = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
    if (-not [string]::IsNullOrWhiteSpace($info.ProductVersion)) {
        return $info.ProductVersion
    }
    if (-not [string]::IsNullOrWhiteSpace($info.FileVersion)) {
        return $info.FileVersion
    }
    Fail "Unable to read version from: $Path"
}

function Find-ManifestCertificateThumbprint {
    if (-not [string]::IsNullOrWhiteSpace($env:IWORKHELPER_MANIFEST_CERT_THUMBPRINT)) {
        return $env:IWORKHELPER_MANIFEST_CERT_THUMBPRINT
    }

    $subject = '*iWorkHelper Development Manifest Signing*'
    $cert = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -like $subject } |
        Sort-Object NotAfter -Descending |
        Select-Object -First 1

    if ($cert) {
        return $cert.Thumbprint
    }

    return $null
}

function Get-FileHashItems($Root) {
    Get-ChildItem -LiteralPath $Root -File -Recurse | Sort-Object FullName | ForEach-Object {
        [pscustomobject]@{
            path = $_.FullName.Substring($Root.Length + 1).Replace('\', '/')
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    }
}

function Test-PortableExecutable($Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        if ($stream.Length -lt 512) {
            return $false
        }

        $reader = New-Object System.IO.BinaryReader($stream)
        if ($reader.ReadUInt16() -ne 0x5A4D) {
            return $false
        }

        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        if ($peOffset -le 0 -or $peOffset -gt ($stream.Length - 4)) {
            return $false
        }

        $stream.Position = $peOffset
        return $reader.ReadUInt32() -eq 0x00004550
    }
    finally {
        $stream.Dispose()
    }
}

function Get-CertificateName($Certificate) {
    if (-not $Certificate) {
        return ''
    }

    $name = $Certificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
    if ([string]::IsNullOrWhiteSpace($name)) {
        return $Certificate.Subject
    }

    return $name
}

function Test-MicrosoftPublisher($Signature) {
    $names = @(
        (Get-CertificateName $Signature.SignerCertificate),
        $Signature.SignerCertificate.Subject,
        (Get-CertificateName $Signature.TimeStamperCertificate),
        $Signature.TimeStamperCertificate.Subject
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($name in $names) {
        if ($name -match 'Microsoft') {
            return $true
        }
    }

    return $false
}

function Get-VstoRedistExpectation($LockPath) {
    # I-10: prerequisites.lock.json is the single source of truth for the expected VSTO
    # Runtime version prefix and download source. build.ps1 must not carry its own copy of
    # those facts; it only checks that the lock file itself is usable.
    if (-not (Test-Path -LiteralPath $LockPath -PathType Leaf)) {
        Fail "VSTO Runtime prerequisite lock file not found: $LockPath. Run scripts\acquire-prerequisites.ps1 first."
    }

    $lock = Get-Content -LiteralPath $LockPath -Raw | ConvertFrom-Json
    $locked = $lock.prerequisites.vstoRuntime
    if (-not $locked) {
        Fail "VSTO Runtime prerequisite lock file is missing prerequisites.vstoRuntime: $LockPath"
    }

    $lockedSource = [string]$locked.source
    $lockedVersion = [string]$locked.version
    if ([string]::IsNullOrWhiteSpace($lockedSource) -or
        $lockedSource -notmatch '^https://download\.microsoft\.com/.*/vstor_redist\.exe$' -or
        $lockedVersion -notmatch '^\d+\.\d+(\.\d+)*$') {
        Fail "VSTO Runtime prerequisite lock file declares an unusable source or version. Source='$lockedSource' Version='$lockedVersion' LockFile=$LockPath"
    }

    return [pscustomobject]@{
        source = $lockedSource
        version = $lockedVersion
        raw = $locked
    }
}

function Test-VstoRedistPayload($Path, $LockPath) {
    $minimumSizeBytes = 30MB

    $expectation = Get-VstoRedistExpectation $LockPath
    $expectedVersionPrefix = $expectation.version
    $expectedSource = $expectation.source
    $locked = $expectation.raw

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Fail "VSTO Runtime prerequisite payload not found: $Path. Place the official Microsoft vstor_redist.exe there before building the offline installer."
    }

    $item = Get-Item -LiteralPath $Path
    if ($item.Name -ne 'vstor_redist.exe') {
        Fail "Unexpected VSTO Runtime prerequisite file name: $($item.Name). Expected vstor_redist.exe."
    }

    if (-not (Test-PortableExecutable $Path)) {
        Fail "VSTO Runtime prerequisite payload is not a valid Windows executable: $Path. Re-download the official Microsoft vstor_redist.exe; HTML download pages or web stubs are not acceptable."
    }

    if ($item.Length -lt $minimumSizeBytes) {
        Fail "VSTO Runtime prerequisite payload is unexpectedly small ($($item.Length) bytes): $Path. Use the full official Microsoft vstor_redist.exe for offline installation."
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid') {
        Fail "VSTO Runtime prerequisite Authenticode signature is not valid. Status=$($signature.Status)"
    }

    if (-not (Test-MicrosoftPublisher $signature)) {
        Fail "VSTO Runtime prerequisite signer is not Microsoft. Signer=$($signature.SignerCertificate.Subject)"
    }

    $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
    if (($versionInfo.FileVersion -notlike "$expectedVersionPrefix*") -and ($versionInfo.ProductVersion -notlike "$expectedVersionPrefix*")) {
        Fail "Unexpected VSTO Runtime prerequisite version. FileVersion=$($versionInfo.FileVersion) ProductVersion=$($versionInfo.ProductVersion) Expected=$expectedVersionPrefix*"
    }

    $hash = Get-FileHash -LiteralPath $Path -Algorithm SHA256

    if ($locked.sha256 -ne $hash.Hash) {
        Fail "VSTO Runtime prerequisite lock SHA256 mismatch. Expected=$($locked.sha256) Actual=$($hash.Hash)"
    }
    if ([int64]$locked.sizeBytes -ne [int64]$item.Length) {
        Fail "VSTO Runtime prerequisite lock size mismatch. Expected=$($locked.sizeBytes) Actual=$($item.Length)"
    }

    return [pscustomobject]@{
        path = 'prerequisites/vstor_redist.exe'
        source = $expectedSource
        version = $expectedVersionPrefix
        fileVersion = $versionInfo.FileVersion
        productVersion = $versionInfo.ProductVersion
        sizeBytes = $item.Length
        sha256 = $hash.Hash
        authenticodeStatus = [string]$signature.Status
        signer = Get-CertificateName $signature.SignerCertificate
    }
}

$installerRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repoRoot = (Resolve-Path (Join-Path $installerRoot '..')).Path
$buildDir = Join-Path $installerRoot 'build'
$stagingRoot = Join-Path $installerRoot 'staging'
$vstoRedist = Join-Path $installerRoot 'prerequisites\vstor_redist.exe'
$vstoRedistLock = Join-Path $installerRoot 'prerequisites\prerequisites.lock.json'

New-Item -ItemType Directory -Path $buildDir -Force | Out-Null

$msbuild = Find-MSBuild
if (-not $msbuild) {
    Fail "MSBuild.exe not found. Install Visual Studio 2022 with Office/SharePoint development workload."
}

$iscc = Find-ISCC
if (-not $iscc) {
    Fail "ISCC.exe not found. Install Inno Setup 7 from https://jrsoftware.org/isdl.php or winget package JRSoftware.InnoSetup.7."
}

if ($AcquirePrerequisites) {
    & (Join-Path $installerRoot 'scripts\acquire-prerequisites.ps1')
    if (-not $?) { Fail "Acquire prerequisites failed." }
}

$vstoRedistPayload = Test-VstoRedistPayload $vstoRedist $vstoRedistLock

$manifestCertThumbprint = Find-ManifestCertificateThumbprint
if (-not $manifestCertThumbprint) {
    Fail "VSTO manifest signing certificate not found. Set IWORKHELPER_MANIFEST_CERT_THUMBPRINT or install a development/test manifest signing certificate."
}

Write-Host "MSBuild: $msbuild"
Write-Host "ISCC   : $iscc"
Write-Host "Manifest Certificate: found development/test certificate in certificate store"

if (-not $SkipPluginBuild) {
    Write-Host "Building eWorkHelper Release..."
    & $msbuild (Join-Path $repoRoot 'eWorkHelper\eWorkhelper.sln') /t:Restore,Rebuild /p:Configuration=Release /p:Platform="Any CPU" /p:SignManifests=true /p:ManifestCertificateThumbprint=$manifestCertThumbprint
    if ($LASTEXITCODE -ne 0) { Fail "eWorkHelper Release build failed." }

    Write-Host "Building oWorkHelper Release-Intranet (Local)..."
    & $msbuild (Join-Path $repoRoot 'oWorkHelper\oWorkhelper.sln') /t:Restore,Rebuild /p:Configuration=Release-Intranet /p:Platform="Any CPU" /p:SignManifests=true /p:ManifestCertificateThumbprint=$manifestCertThumbprint
    if ($LASTEXITCODE -ne 0) { Fail "oWorkHelper Release-Intranet build failed." }

    Write-Host "Building oWorkHelper Release-Internet (Baidu)..."
    & $msbuild (Join-Path $repoRoot 'oWorkHelper\oWorkhelper.sln') /t:Restore,Rebuild /p:Configuration=Release-Internet /p:Platform="Any CPU" /p:SignManifests=true /p:ManifestCertificateThumbprint=$manifestCertThumbprint
    if ($LASTEXITCODE -ne 0) { Fail "oWorkHelper Release-Internet build failed." }
}

& (Join-Path $installerRoot 'scripts\prepare-staging.ps1') `
    -RepoRoot $repoRoot `
    -InstallerRoot $installerRoot

$eDll = Join-Path $stagingRoot 'eWorkHelper\eWorkhelper.dll'
$oLocalDll = Join-Path $stagingRoot 'oWorkHelper\local\oWorkhelper.dll'
$oBaiduDll = Join-Path $stagingRoot 'oWorkHelper\baidu\oWorkhelper.dll'
$eVersion = Get-ProductVersion $eDll
$oLocalVersion = Get-ProductVersion $oLocalDll
$oBaiduVersion = Get-ProductVersion $oBaiduDll
if ($oLocalVersion -ne $oBaiduVersion) {
    Fail "oWorkHelper Local and Baidu versions differ: Local=$oLocalVersion, Baidu=$oBaiduVersion"
}

$manifest = [pscustomobject]@{
    installerVersion = $InstallerVersion
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    oWorkHelperDefaultVariant = 'Baidu'
    trustMode = 'Development/Test'
    eWorkHelperVersion = $eVersion
    oWorkHelperVersion = $oBaiduVersion
    oWorkHelperVariants = [pscustomobject]@{
        Local = [pscustomobject]@{
            buildConfiguration = 'Release-Intranet'
            version = $oLocalVersion
            displayName = '仅本地 OCR'
        }
        Baidu = [pscustomobject]@{
            buildConfiguration = 'Release-Internet'
            version = $oBaiduVersion
            displayName = '本地 + Baidu OCR'
        }
    }
    files = Get-FileHashItems $stagingRoot
    prerequisites = [pscustomobject]@{
        vstoRuntime = $vstoRedistPayload
    }
}
$manifestPath = Join-Path $buildDir 'packaged-components.json'
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

$iss = Join-Path $installerRoot 'installer\iWorkHelper.iss'
if (-not (Test-Path -LiteralPath $iss -PathType Leaf)) {
    Fail "Inno Setup script not found: $iss"
}

Write-Host "Building installer..."
& $iscc "/DInstallerVersion=$InstallerVersion" "/DInstallerFileVersion=$InstallerFileVersion" "/DEWorkHelperVersion=$eVersion" "/DOWorkHelperVersion=$oBaiduVersion" "/DOWorkHelperLocalVersion=$oLocalVersion" "/DOWorkHelperBaiduVersion=$oBaiduVersion" $iss
if ($LASTEXITCODE -ne 0) { Fail "ISCC compile failed." }

$output = Join-Path $buildDir ("iWorkHelper-Setup-$InstallerVersion.exe")
if (-not (Test-Path -LiteralPath $output -PathType Leaf)) {
    Fail "Installer output not found: $output"
}

Write-Host ""
Write-Host "BUILD SUCCESS"
Write-Host ""
Write-Host "Installer:"
Write-Host $output
Write-Host ""
Write-Host "Installer Version:"
Write-Host $InstallerVersion
Write-Host ""
Write-Host "Included:"
Write-Host "eWorkHelper $eVersion"
Write-Host "oWorkHelper Local $oLocalVersion"
Write-Host "oWorkHelper Baidu $oBaiduVersion"
Write-Host ""
Write-Host "oWorkHelper Default Variant:"
Write-Host "Baidu"
Write-Host ""
Write-Host "Prerequisites:"
Write-Host "VSTO Runtime payload $($vstoRedistPayload.sizeBytes) bytes SHA256=$($vstoRedistPayload.sha256)"
Write-Host "VSTO Runtime version $($vstoRedistPayload.fileVersion) signer=$($vstoRedistPayload.signer) Authenticode=$($vstoRedistPayload.authenticodeStatus)"
