[CmdletBinding()]
param(
    [string]$Subject = 'CN=iWorkHelper Development Manifest Signing'
)

$ErrorActionPreference = 'Stop'
$installerRoot = Split-Path -Parent $PSScriptRoot
$localRoot = Join-Path $installerRoot '.local\certificates'
$thumbprintFile = Join-Path $localRoot 'vsto-manifest-thumbprint.txt'
New-Item -ItemType Directory -Force -Path $localRoot | Out-Null

$certificate = Get-ChildItem Cert:\CurrentUser\My | Where-Object {
    $_.Subject -eq $Subject -and $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date).AddDays(30)
} | Sort-Object NotAfter -Descending | Select-Object -First 1

if (-not $certificate) {
    $certificate = New-SelfSignedCertificate -Type CodeSigningCert -Subject $Subject `
        -CertStoreLocation Cert:\CurrentUser\My -KeyAlgorithm RSA -KeyLength 3072 `
        -HashAlgorithm SHA256 -KeyExportPolicy Exportable -NotAfter (Get-Date).AddYears(2)
}

$cerPath = Join-Path $localRoot 'iWorkHelper-development.cer'
Export-Certificate -Cert $certificate -FilePath $cerPath -Force | Out-Null

Set-Content -LiteralPath $thumbprintFile -Value $certificate.Thumbprint -Encoding ascii
Write-Output $certificate.Thumbprint
