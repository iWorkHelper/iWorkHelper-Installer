[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$MsiPath
)

$ErrorActionPreference = 'Stop'
$installer = New-Object -ComObject WindowsInstaller.Installer

foreach ($path in $MsiPath) {
    $resolvedPath = (Resolve-Path -LiteralPath $path).Path
    # PID_WORDCOUNT (15) is a bit field. Preserve the source compression flags
    # and set bit 3 so Windows Installer does not initiate UAC for per-user use.
    $summary = $installer.SummaryInformation($resolvedPath, 1)
    try {
        $wordCount = [int]$summary.Property(15)
        $summary.Property(15) = $wordCount -bor 8
        $summary.Persist()
    }
    finally {
        [Runtime.InteropServices.Marshal]::FinalReleaseComObject($summary) | Out-Null
    }
}

[Runtime.InteropServices.Marshal]::FinalReleaseComObject($installer) | Out-Null
