param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$VstoRedistUrl = 'https://download.microsoft.com/download/5/d/2/5d24f8f8-efbb-4b63-aa33-3785e3104713/vstor_redist.exe'
$ExpectedFileName = 'vstor_redist.exe'
$ExpectedVersionPrefix = '10.0.60917'
$MinimumSizeBytes = 30MB

function Fail($Message) {
    Write-Error "ERROR: $Message"
    exit 1
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

function Test-VstoRedistPayload($Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Fail "VSTO Runtime prerequisite payload not found: $Path"
    }

    $item = Get-Item -LiteralPath $Path
    if ($item.Name -ne $ExpectedFileName) {
        Fail "Unexpected prerequisite file name: $($item.Name). Expected: $ExpectedFileName"
    }

    if ($item.Length -lt $MinimumSizeBytes) {
        Fail "VSTO Runtime prerequisite payload is too small ($($item.Length) bytes): $Path"
    }

    if (-not (Test-PortableExecutable $Path)) {
        Fail "VSTO Runtime prerequisite payload is not a valid Windows PE executable: $Path"
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid') {
        Fail "Authenticode signature is not valid for $Path. Status=$($signature.Status)"
    }

    if (-not (Test-MicrosoftPublisher $signature)) {
        Fail "Authenticode signer is not Microsoft. Signer=$($signature.SignerCertificate.Subject)"
    }

    $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
    $fileVersion = $versionInfo.FileVersion
    $productVersion = $versionInfo.ProductVersion
    if (($fileVersion -notlike "$ExpectedVersionPrefix*") -and ($productVersion -notlike "$ExpectedVersionPrefix*")) {
        Fail "Unexpected VSTO Runtime version. FileVersion=$fileVersion ProductVersion=$productVersion Expected=$ExpectedVersionPrefix*"
    }

    $hash = Get-FileHash -LiteralPath $Path -Algorithm SHA256
    $signer = Get-CertificateName $signature.SignerCertificate

    return [pscustomobject]@{
        name = $ExpectedFileName
        source = $VstoRedistUrl
        version = $ExpectedVersionPrefix
        fileVersion = $fileVersion
        productVersion = $productVersion
        sizeBytes = $item.Length
        sha256 = $hash.Hash
        authenticodeStatus = [string]$signature.Status
        signer = $signer
        signerSubject = $signature.SignerCertificate.Subject
        acquiredAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    }
}

$installerRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$prereqDir = Join-Path $installerRoot 'prerequisites'
$finalPath = Join-Path $prereqDir $ExpectedFileName
$lockPath = Join-Path $prereqDir 'prerequisites.lock.json'

New-Item -ItemType Directory -Path $prereqDir -Force | Out-Null

if ((Test-Path -LiteralPath $finalPath -PathType Leaf) -and -not $Force) {
    Write-Host "Validating existing prerequisite: $finalPath"
    $payload = Test-VstoRedistPayload $finalPath
} else {
    $tempPath = Join-Path $prereqDir ($ExpectedFileName + '.download.tmp')
    if (Test-Path -LiteralPath $tempPath) {
        Remove-Item -LiteralPath $tempPath -Force
    }

    try {
        Write-Host "Downloading Microsoft VSTO Runtime:"
        Write-Host $VstoRedistUrl
        Invoke-WebRequest -Uri $VstoRedistUrl -OutFile $tempPath -MaximumRedirection 0

        Rename-Item -LiteralPath $tempPath -NewName $ExpectedFileName -Force
        $payload = Test-VstoRedistPayload $finalPath
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force
        }
        if ((Test-Path -LiteralPath $finalPath) -and $Force) {
            Remove-Item -LiteralPath $finalPath -Force
        }
        Fail $_.Exception.Message
    }
}

$lock = [pscustomobject]@{
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    prerequisites = [pscustomobject]@{
        vstoRuntime = $payload
    }
}
$lock | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $lockPath -Encoding UTF8

Write-Host ""
Write-Host "VSTO Runtime prerequisite ready"
Write-Host "Path              : $finalPath"
Write-Host "Version           : $($payload.fileVersion)"
Write-Host "ProductVersion    : $($payload.productVersion)"
Write-Host "SizeBytes         : $($payload.sizeBytes)"
Write-Host "SHA256            : $($payload.sha256)"
Write-Host "Authenticode      : $($payload.authenticodeStatus)"
Write-Host "Signer            : $($payload.signer)"
Write-Host "Lock              : $lockPath"

exit 0
