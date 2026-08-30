[CmdletBinding()]
param(
    [string]$MsiPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\iWorkHelper.msi'),
    [string]$ChineseTransformPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\iWorkHelper.zh-CN.mst')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$localValidation = Join-Path $root '.local\validation'
New-Item -ItemType Directory -Force -Path $localValidation | Out-Null
$installer = New-Object -ComObject WindowsInstaller.Installer

function Get-MsiRows($database, [string]$sql, [int]$columns) {
    $view = $database.OpenView($sql)
    $null = $view.Execute()
    while ($record = $view.Fetch()) {
        $row = for ($index = 1; $index -le $columns; $index++) { $record.StringData($index) }
        [pscustomobject]@{ Values = [string[]]$row }
    }
    $null = $view.Close()
}

function Assert-Equal($actual, $expected, [string]$message) {
    if ([string]$actual -ne [string]$expected) { throw "$message Expected '$expected', got '$actual'." }
}

$database = $installer.OpenDatabase((Resolve-Path $MsiPath).Path, 0)
$properties = @{}
foreach ($row in (Get-MsiRows $database 'SELECT `Property`, `Value` FROM `Property`' 2)) { $properties[$row.Values[0]] = $row.Values[1] }
Assert-Equal $properties['ALLUSERS'] '2' 'MSI must be dual-scope.'
Assert-Equal $properties['MSIINSTALLPERUSER'] '1' 'MSI must default to per-user.'
Assert-Equal $properties['MSIDEPLOYMENTCOMPLIANT'] '1' 'MSI must declare UAC-compliant authoring.'
Assert-Equal $properties['ARPSYSTEMCOMPONENT'] '1' 'Internal MSI must remain registered but hidden from ARP.'
Assert-Equal $properties['MsiLogging'] 'voicewarmupx!' 'Development MSI verbose logging must be enabled.'
foreach ($diagnosticProperty in @('IWORKHELPER_REQUESTEDSCOPE', 'IWORKHELPER_BUNDLEPLANNEDSCOPE', 'IWORKHELPER_BUNDLEELEVATED', 'IWORKHELPER_INSTALLCONTEXT')) {
    if (-not $properties.ContainsKey($diagnosticProperty)) { throw "MSI diagnostic property is missing: $diagnosticProperty" }
}
Assert-Equal $properties['ProductLanguage'] '1033' 'Base MSI must be English.'
$baseProductCode = $properties['ProductCode']
if ($baseProductCode -notmatch '^\{[0-9A-Fa-f-]{36}\}$') { throw "Base MSI ProductCode is invalid: $baseProductCode" }

$summary = $installer.SummaryInformation((Resolve-Path $MsiPath).Path, 0)
$wordCount = [int]$summary.Property(15)
if (($wordCount -band 8) -eq 0) { throw "Dual-purpose MSI must suppress Windows Installer UAC for its per-user context. Value: $wordCount" }
if (($wordCount -band 2) -eq 0) { throw "Embedded-cab MSI must retain the compressed-source flag. Value: $wordCount" }
[Runtime.InteropServices.Marshal]::FinalReleaseComObject($summary) | Out-Null

$features = Get-MsiRows $database 'SELECT `Feature`, `Feature_Parent`, `Title`, `Level` FROM `Feature`' 4
Assert-Equal $features.Count 2 'MSI must contain exactly two top-level features.'
foreach ($id in @('ExcelFeature', 'OutlookFeature')) {
    $feature = $features | Where-Object { $_.Values[0] -eq $id }
    if (-not $feature) { throw "Feature is missing: $id" }
    if ($feature.Values[1]) { throw "Feature must be top-level: $id" }
}

$featureComponents = Get-MsiRows $database 'SELECT `Feature_`, `Component_` FROM `FeatureComponents`' 2
$excelComponents = @($featureComponents | Where-Object { $_.Values[0] -eq 'ExcelFeature' } | ForEach-Object { $_.Values[1] })
$outlookComponents = @($featureComponents | Where-Object { $_.Values[0] -eq 'OutlookFeature' } | ForEach-Object { $_.Values[1] })
$overlap = @($excelComponents | Where-Object { $outlookComponents -contains $_ })
if ($overlap.Count -ne 0) { throw "Excel and Outlook share components: $($overlap -join ', ')" }

$directories = Get-MsiRows $database 'SELECT `Directory`, `Directory_Parent` FROM `Directory`' 2
$installDirectory = $directories | Where-Object { $_.Values[0] -eq 'INSTALLFOLDER' }
Assert-Equal $installDirectory.Values[1] 'ProgramFiles64Folder' 'INSTALLFOLDER must use the Windows Installer 5.0 per-user-capable ProgramFiles64Folder tree.'

$registry = Get-MsiRows $database 'SELECT `Root`, `Key`, `Name`, `Value`, `Component_` FROM `Registry`' 5
if ($registry | Where-Object { $_.Values[0] -ne '-1' }) { throw 'Install-time Registry rows must all use HKMU; fixed HKCU/HKLM resources break dual scope.' }
foreach ($officeApp in @('Excel', 'Outlook')) {
    $hostRows = @($registry | Where-Object { $_.Values[1] -eq "Software\Microsoft\Office\$officeApp\Addins\$($officeApp.Substring(0,1).ToLower())Workhelper" })
    Assert-Equal $hostRows.Count 4 "$officeApp registration row count is invalid."
    foreach ($row in $hostRows) { Assert-Equal $row.Values[0] '-1' "$officeApp registration must use HKMU." }
    $loadBehavior = $hostRows | Where-Object { $_.Values[2] -eq 'LoadBehavior' }
    Assert-Equal $loadBehavior.Values[3] '#3' "$officeApp LoadBehavior is invalid."
    $manifest = $hostRows | Where-Object { $_.Values[2] -eq 'Manifest' }
    if ($manifest.Values[3] -notmatch '^file:///\[.+Folder\].+\.vsto\|vstolocal$') { throw "$officeApp manifest registration is invalid." }
}

$launchConditions = Get-MsiRows $database 'SELECT `Condition`, `Description` FROM `LaunchCondition`' 2
foreach ($token in @('VersionNT64', 'NETFRAMEWORK48FULL', 'VSTORUNTIME32', 'OFFICE64PLATFORM')) {
    if (-not ($launchConditions | Where-Object { $_.Values[0] -match $token })) { throw "Launch condition is missing: $token" }
}

$tables = @(Get-MsiRows $database 'SELECT `Name` FROM `_Tables`' 1 | ForEach-Object { $_.Values[0] })
foreach ($machineOnlyTable in @('ServiceInstall', 'ServiceControl', 'ODBCDriver', 'ODBCTranslator')) {
    if ($tables -contains $machineOnlyTable) { throw "Machine-only MSI table is present: $machineOnlyTable" }
}
$customActions = Get-MsiRows $database 'SELECT `Action`, `Type`, `Source`, `Target` FROM `CustomAction`' 4
foreach ($action in $customActions) {
    # 307 = type 51 property assignment + first-sequence flag. It remains an
    # immediate, non-script, non-elevated action.
    if (([int]$action.Values[1] -band 0xFF) -ne 51) { throw "Only immediate type-51 property actions are allowed; found $($action.Values[0]) type $($action.Values[1])." }
}

$zhMsi = Join-Path $localValidation 'iWorkHelper.zh-CN.msi'
Copy-Item -LiteralPath $MsiPath -Destination $zhMsi -Force
$transformPath = (Resolve-Path $ChineseTransformPath).Path
$dtfAssembly = Join-Path $env:USERPROFILE '.nuget\packages\wixtoolset.sdk\7.0.0\tools\net472\WixToolset.Dtf.WindowsInstaller.dll'
Add-Type -Path $dtfAssembly
$transformDatabase = [WixToolset.Dtf.WindowsInstaller.Database]::new($zhMsi, [WixToolset.Dtf.WindowsInstaller.DatabaseOpenMode]::Transact)
$transformDatabase.ApplyTransform($transformPath)
$transformDatabase.Commit()
$transformDatabase.Dispose()
$zhDatabase = $installer.OpenDatabase($zhMsi, 0)
$zhProperties = @{}
foreach ($row in (Get-MsiRows $zhDatabase 'SELECT `Property`, `Value` FROM `Property`' 2)) { $zhProperties[$row.Values[0]] = $row.Values[1] }
Assert-Equal $zhProperties['ProductLanguage'] '2052' 'Chinese transform must set ProductLanguage to zh-CN.'
Assert-Equal $zhProperties['ProductCode'] $baseProductCode 'Language transform must not change ProductCode; Burn detection and maintenance depend on one product identity.'
$zhFeatures = Get-MsiRows $zhDatabase 'SELECT `Feature`, `Title` FROM `Feature`' 2
if (-not ($zhFeatures | Where-Object { $_.Values[0] -eq 'ExcelFeature' -and $_.Values[1] -eq 'Excel 插件' })) { throw 'Chinese Excel feature title was not applied.' }
if (-not ($zhFeatures | Where-Object { $_.Values[0] -eq 'OutlookFeature' -and $_.Values[1] -eq 'Outlook 插件' })) { throw 'Chinese Outlook feature title was not applied.' }

Write-Host "MSI database validation passed: Windows Installer 5.0 dual scope, per-user no-elevation summary flag, stable localized ProductCode, redirectable ProgramFiles64Folder, 2 isolated features, HKMU registration, launch conditions, and zh-CN transform."
