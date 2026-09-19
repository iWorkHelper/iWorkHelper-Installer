param()

$ErrorActionPreference = 'Stop'

function Assert-Equal($Expected, $Actual, $Name) {
    if ($Expected -ne $Actual) {
        throw "FAIL ${Name}: expected '$Expected', actual '$Actual'"
    }
    Write-Host "PASS $Name"
}

function Compare-VersionNumeric([string]$Left, [string]$Right) {
    $leftParts = $Left.Split('.') | ForEach-Object { [int64]$_ }
    $rightParts = $Right.Split('.') | ForEach-Object { [int64]$_ }
    $count = [Math]::Max($leftParts.Count, $rightParts.Count)
    for ($i = 0; $i -lt $count; $i++) {
        $l = if ($i -lt $leftParts.Count) { $leftParts[$i] } else { 0 }
        $r = if ($i -lt $rightParts.Count) { $rightParts[$i] } else { 0 }
        if ($l -lt $r) { return -1 }
        if ($l -gt $r) { return 1 }
    }
    return 0
}

function Get-InstallDecision([bool]$Installed, [bool]$RecordSafe, [string]$InstalledVersion, [string]$PackageVersion) {
    if (-not $Installed) { return 'first-install' }
    if (-not $RecordSafe) { return 'unsafe-state' }
    $comparison = Compare-VersionNumeric $InstalledVersion $PackageVersion
    if ($comparison -lt 0) { return 'upgrade' }
    if ($comparison -eq 0) { return 'repair' }
    return 'downgrade-blocked'
}

function Get-InstallPath([bool]$Installed, [bool]$RecordSafe, [string]$ExistingPath, [string]$DefaultPath) {
    if ($Installed -and $RecordSafe -and -not [string]::IsNullOrWhiteSpace($ExistingPath)) {
        return $ExistingPath.TrimEnd('\')
    }
    return $DefaultPath
}

# Pure policy tests. Registry and Office/VSTO integration tests require a disposable
# Windows/Office installation and are intentionally not faked by this script.
Assert-Equal -Expected 'first-install' -Actual (Get-InstallDecision $false $true '' '1.2.0') -Name 'T01 first install'
Assert-Equal -Expected 'repair' -Actual (Get-InstallDecision $true $true '1.2.0' '1.2.0') -Name 'T02 same version repair'
Assert-Equal -Expected 'upgrade' -Actual (Get-InstallDecision $true $true '1.1.9' '1.2.0') -Name 'T03 lower version upgrade'
Assert-Equal -Expected 'downgrade-blocked' -Actual (Get-InstallDecision $true $true '1.3.0' '1.2.0') -Name 'T05 downgrade blocked'
Assert-Equal -Expected 'unsafe-state' -Actual (Get-InstallDecision $true $false '1.1.0' '1.2.0') -Name 'T06 inconsistent record blocked'
Assert-Equal -Expected 'D:\Custom\iWorkHelper' -Actual (Get-InstallPath $true $true 'D:\Custom\iWorkHelper\' 'C:\Program Files\iWorkHelper') -Name 'T04 custom path inherited'
Assert-Equal -Expected 1 -Actual (Compare-VersionNumeric '1.10.0' '1.2.0') -Name 'numeric version comparison'
Assert-Equal -Expected 0 -Actual (Compare-VersionNumeric '1.2' '1.2.0') -Name 'missing zero component'
Write-Host 'Policy tests passed. T04/T07-T14 require real installer, registry, Outlook and Office validation.'
