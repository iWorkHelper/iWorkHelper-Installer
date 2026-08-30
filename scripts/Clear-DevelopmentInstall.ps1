[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Execute,
    [string[]]$InstallFolder
)

$ErrorActionPreference = 'Stop'
$bundleUpgradeCode = '{CF2BEB8E-9E86-4A5C-A207-C2EC669DA283}'
$msiUpgradeCode = '{A8F80F1A-7323-4C14-ACD0-281A333CDA33}'
$windowsInstaller = New-Object -ComObject WindowsInstaller.Installer
$msiProductCodes = @($windowsInstaller.RelatedProducts($msiUpgradeCode))
$uninstallRoots = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)

function Get-IWorkHelperRegistration {
    foreach ($root in $uninstallRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($key in Get-ChildItem -LiteralPath $root) {
            $item = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            $bundleCodes = @($item.BundleUpgradeCode)
            $isBundle = $bundleCodes -contains $bundleUpgradeCode
            $isMsi = $item.WindowsInstaller -eq 1 -and $msiProductCodes -contains $key.PSChildName
            if ($isBundle -or $isMsi) {
                [pscustomobject]@{
                    Kind = if ($isBundle) { 'Bundle' } else { 'MSI' }
                    Scope = if ($root -like 'HKCU:*') { 'PerUser' } else { 'PerMachine' }
                    Key = $key.PSChildName
                    DisplayName = $item.DisplayName
                    DisplayVersion = $item.DisplayVersion
                    UninstallString = $item.UninstallString
                    QuietUninstallString = $item.QuietUninstallString
                    RegistryPath = $key.PSPath
                }
            }
        }
    }
}

$registrations = @(Get-IWorkHelperRegistration)
$registrations | Format-Table Kind, Scope, Key, DisplayVersion -AutoSize
if (-not $Execute) {
    Write-Host 'Dry run only. Re-run with -Execute after reviewing the exact registrations above.'
    return
}

# Burn first, then any orphaned MSI left by older development builds.
foreach ($registration in @($registrations | Sort-Object @{ Expression = { if ($_.Kind -eq 'Bundle') { 0 } else { 1 } } })) {
    if ($registration.Kind -eq 'Bundle') {
        $command = if ($registration.QuietUninstallString) { $registration.QuietUninstallString } else { $registration.UninstallString }
        if ($command -notmatch '^"([^"]+)"\s*(.*)$') { throw "Unexpected Bundle uninstall command for $($registration.Key)." }
        $exe = $Matches[1]
        $arguments = ($Matches[2] + ' /quiet /norestart').Trim()
        if ($PSCmdlet.ShouldProcess("$($registration.Kind) $($registration.Key)", 'Run registered uninstaller')) {
            $process = Start-Process -FilePath $exe -ArgumentList $arguments -Wait -PassThru
            if ($process.ExitCode -notin 0, 3010) { throw "Bundle cleanup failed with exit code $($process.ExitCode)." }
        }
    }
    elseif ($registration.Key -match '^\{[0-9A-Fa-f-]{36}\}$' -and $PSCmdlet.ShouldProcess("MSI $($registration.Key)", 'Uninstall orphaned product')) {
        $process = Start-Process msiexec.exe -ArgumentList '/x', $registration.Key, '/qn', '/norestart' -Wait -PassThru
        if ($process.ExitCode -notin 0, 1605, 3010) { throw "MSI cleanup failed with exit code $($process.ExitCode)." }
    }
}

foreach ($folder in $InstallFolder) {
    $resolved = [IO.Path]::GetFullPath($folder)
    if ([IO.Path]::GetFileName($resolved) -ne 'iWorkHelper') { throw "Refusing non-iWorkHelper folder: $folder" }
    $manifestKeys = @(
        'HKCU:\Software\Microsoft\Office\Excel\Addins\eWorkhelper',
        'HKCU:\Software\Microsoft\Office\Outlook\Addins\oWorkhelper',
        'HKLM:\Software\Microsoft\Office\Excel\Addins\eWorkhelper',
        'HKLM:\Software\Microsoft\Office\Outlook\Addins\oWorkhelper'
    )
    $owned = $false
    foreach ($key in $manifestKeys) {
        $manifest = (Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).Manifest
        if ($manifest -and $manifest.IndexOf($resolved, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $owned = $true }
    }
    if (-not $owned) { throw "Refusing folder without matching iWorkHelper Add-in registration: $folder" }
    if ($PSCmdlet.ShouldProcess($resolved, 'Remove orphaned development install folder')) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

Write-Host "Cleanup complete for Bundle upgrade code $bundleUpgradeCode and MSI upgrade code $msiUpgradeCode."
