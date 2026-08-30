$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$errors = [System.Collections.Generic.List[string]]::new()

$wxs = Get-ChildItem -LiteralPath $root -Recurse -File -Include *.wxs,*.wxl,*.wixproj,*.csproj,*.cs,*.ps1,*.md
$joined = ($wxs | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
$executableSources = ($wxs | Where-Object { $_.Extension -In @('.wxs', '.wixproj', '.ps1') -and $_.DirectoryName -ne $PSScriptRoot } | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"

if ($joined -match '[A-Za-z]:\\Users\\') { $errors.Add('A user-machine absolute path was found.') }
if ($joined -match '(?i)(api[_-]?key|secret[_-]?key|access[_-]?token)\s*[=:]\s*[^<\s]+') { $errors.Add('A possible credential assignment was found.') }
if ($executableSources -match '(?i)Copy-Item[^\r\n]*(bin\\Release|obj\\|publish\\)[^\r\n]*\*') { $errors.Add('A broad build/publish directory copy pattern was found.') }

$package = Get-Content -LiteralPath (Join-Path $root 'MSI\Package.wxs') -Raw
foreach ($required in @('ExcelFeature', 'OutlookFeature', 'Scope="perUserOrMachine"', 'NETFRAMEWORK48FULL', 'VSTORUNTIME', 'OFFICE64PATH')) {
    if ($package -notmatch [regex]::Escape($required)) { $errors.Add("MSI requirement missing: $required") }
}

$registryText = (Get-Content (Join-Path $root 'MSI\Excel.wxs') -Raw) + (Get-Content (Join-Path $root 'MSI\Outlook.wxs') -Raw)
foreach ($required in @('Root="HKMU"', '|vstolocal', 'LoadBehavior', 'Value="3"')) {
    if ($registryText -notmatch [regex]::Escape($required)) { $errors.Add("Registration requirement missing: $required") }
}

$ba = (Get-Content (Join-Path $root 'BootstrapperApplication\Bootstrapper.cs') -Raw) + (Get-Content (Join-Path $root 'BootstrapperApplication\InstallerWindow.cs') -Raw)
foreach ($required in @('BundleScope.PerMachine', 'BundleScope.PerUser', 'engine.Elevate(hwnd)', 'DirectoryPermission.CanWrite', 'ApplyOverridableVariables', 'ParseCommandLine', 'SelectedLanguage', 'InstallFolder', 'WixStdBAScope', 'WixBundleAuthoredScope', 'WixBundlePlannedScope', 'WixBundleElevated', 'ExcelFeature', 'OutlookFeature', 'LaunchAction.Repair', 'LaunchAction.Uninstall', 'WixBundleCommandLineAction', 'WixBundleUILevel', 'RequestState.ForcePresent', 'MsiEnumRelatedProducts', 'InstallLocation')) {
    if ($ba -notmatch [regex]::Escape($required)) { $errors.Add("Custom BA requirement missing: $required") }
}
if ($ba -notmatch 'Chinese = true' -or $ba -notmatch 'IsChecked = true') { $errors.Add('Simplified Chinese is not the default language.') }

if ($errors.Count -gt 0) { throw ($errors -join [Environment]::NewLine) }
Write-Host "Static installer validation passed ($($wxs.Count) source files scanned)."
