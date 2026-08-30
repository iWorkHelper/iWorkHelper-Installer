[CmdletBinding()]
param(
    [string]$BundlePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\iWorkHelper-Setup-1.0.9-x64.exe'),
    [string]$ExpectedVersion,
    [string]$ExpectedProductCode
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$extractRoot = Join-Path $root '.local\bundle-validation'
$resolvedExtractRoot = [IO.Path]::GetFullPath($extractRoot)
$resolvedLocalRoot = [IO.Path]::GetFullPath((Join-Path $root '.local'))
if (-not $resolvedExtractRoot.StartsWith($resolvedLocalRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Bundle extraction target escaped the local validation directory.'
}
if (Test-Path -LiteralPath $resolvedExtractRoot) { Remove-Item -LiteralPath $resolvedExtractRoot -Recurse -Force }

dotnet wix burn extract $BundlePath -out $resolvedExtractRoot -outba (Join-Path $resolvedExtractRoot 'ba') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Bundle extraction failed.' }
[xml]$manifest = Get-Content -LiteralPath (Join-Path $resolvedExtractRoot 'ba\manifest.xml')
$ns = New-Object Xml.XmlNamespaceManager($manifest.NameTable)
$ns.AddNamespace('b', 'http://wixtoolset.org/schemas/v4/2008/Burn')

$registration = $manifest.SelectSingleNode('//b:Registration', $ns)
if ($registration.Scope -ne 'perUserOrMachine') { throw 'Bundle is not configurable-scope.' }
if ($ExpectedVersion -and $registration.Version -ne $ExpectedVersion) { throw "Bundle version mismatch. Expected $ExpectedVersion, got $($registration.Version)." }

$packages = @($manifest.SelectNodes('//b:Chain/*', $ns))
if ($packages.Count -ne 1 -or $packages[0].Id -ne 'iWorkHelperMsi') { throw 'Bundle chain must contain only the dual-purpose MSI.' }
if ($packages | Where-Object { $_.LocalName -ne 'MsiPackage' }) { throw 'Runtime packages must not be in the Bundle chain.' }
if ($manifest.SelectNodes('//@Condition') | Where-Object { $_.Value -match '\bnumeric\s' }) {
    throw 'Burn 7 conditions must not contain the legacy numeric prefix syntax.'
}

$msiPackage = $manifest.SelectSingleNode('//b:MsiPackage[@Id="iWorkHelperMsi"]', $ns)
if ($msiPackage.Scope -ne 'perUserOrMachine') { throw 'MSI package scope was not propagated to Burn.' }
$burnFeatures = @($msiPackage.SelectNodes('b:MsiFeature', $ns) | ForEach-Object { $_.Id })
foreach ($featureId in @('ExcelFeature', 'OutlookFeature', 'OutlookLocalOnlineFeature')) {
    if ($burnFeatures -notcontains $featureId) { throw "Burn MSI feature selection is missing: $featureId" }
}
if ($ExpectedVersion -and $msiPackage.Version -ne $ExpectedVersion) { throw "Chained MSI version mismatch. Expected $ExpectedVersion, got $($msiPackage.Version)." }
if ($ExpectedProductCode -and $msiPackage.ProductCode -ne $ExpectedProductCode) { throw "Chained MSI ProductCode mismatch. Expected $ExpectedProductCode, got $($msiPackage.ProductCode)." }
$transformProperty = $msiPackage.SelectSingleNode('b:MsiProperty[@Id="TRANSFORMS"]', $ns)
if (-not $transformProperty -or $transformProperty.Condition -ne 'SelectedLanguage = "zh-CN"') { throw 'zh-CN transform selection is invalid.' }
$folderProperty = $msiPackage.SelectSingleNode('b:MsiProperty[@Id="INSTALLFOLDER"]', $ns)
if (-not $folderProperty -or $folderProperty.Value -ne '[InstallFolder]') { throw 'Custom install folder is not passed to MSI.' }
$outlookEditionProperty = $msiPackage.SelectSingleNode('b:MsiProperty[@Id="OUTLOOKEDITION"]', $ns)
if (-not $outlookEditionProperty -or $outlookEditionProperty.Value -ne '[OutlookEdition]') { throw 'Outlook edition is not passed to MSI.' }
foreach ($mapping in @{
    IWORKHELPER_REQUESTEDSCOPE='[InstallScope]'
    IWORKHELPER_BUNDLEPLANNEDSCOPE='[WixBundlePlannedScope]'
    IWORKHELPER_BUNDLEELEVATED='[WixBundleElevated]'
}.GetEnumerator()) {
    $property = $msiPackage.SelectSingleNode("b:MsiProperty[@Id='$($mapping.Key)']", $ns)
    if (-not $property -or $property.Value -ne $mapping.Value) { throw "MSI diagnostic scope mapping is invalid: $($mapping.Key)" }
}
if ($msiPackage.HasAttribute('Visible') -and $msiPackage.Visible -ne 'no') { throw 'Internal MSI must be hidden from ARP; Bundle is the only public entry.' }

foreach ($payload in @('iWorkHelper.BootstrapperApplication.exe', 'WixToolset.BootstrapperApplicationApi.dll', 'mbanative.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $resolvedExtractRoot "ba\$payload"))) { throw "Custom BA payload is missing: $payload" }
}
$variables = @($manifest.SelectNodes('//b:Variable', $ns))
$baDataPath = Join-Path $resolvedExtractRoot 'ba\BootstrapperApplicationData.xml'
[xml]$baData = Get-Content -LiteralPath $baDataPath
$overridableVariables = @($baData.SelectNodes('//*[local-name()="WixStdbaOverridableVariable"]') | ForEach-Object { $_.Name })
foreach ($variable in @('InstallFolder', 'SelectedLanguage', 'InstallExcel', 'InstallOutlook', 'OutlookEdition', 'InstallPerMachine', 'InstallScope')) {
    if (-not ($variables | Where-Object { $_.Id -eq $variable -and $_.Persisted -eq 'yes' })) { throw "Persisted BA variable is missing: $variable" }
    if ($overridableVariables -notcontains $variable) { throw "Overridable BA variable is missing: $variable" }
}
$outlookEditionVariable = $variables | Where-Object { $_.Id -eq 'OutlookEdition' }
if ($outlookEditionVariable.Value -ne 'LocalOnline') { throw 'Fresh Bundle installations must default to Outlook LocalOnline.' }

$manifestRaw = Get-Content -LiteralPath (Join-Path $resolvedExtractRoot 'ba\manifest.xml') -Raw
foreach ($required in @('OfficePlatform', 'VstoRuntimeVersion32', 'NetFrameworkRelease', 'WindowsCurrentBuild')) {
    if ($manifestRaw -notmatch [regex]::Escape($required)) { throw "Bundle search is missing: $required" }
}

Write-Host 'Bundle validation passed: custom BA, persisted UI choices, configurable scope, custom folder, no elevating runtime packages, and embedded zh-CN transform.'
