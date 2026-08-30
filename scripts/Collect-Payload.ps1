[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$installerRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $installerRoot
$payloadRoot = Join-Path $installerRoot 'Payload'
$excelSource = Join-Path $workspaceRoot 'eWorkHelper\bin\Release'
$outlookLocalSource = Join-Path $workspaceRoot 'oWorkHelper\bin\Release-Intranet'
$outlookLocalOnlineSource = Join-Path $workspaceRoot 'oWorkHelper\bin\Release-Internet'
$excelTarget = Join-Path $payloadRoot 'Excel'
$outlookLocalTarget = Join-Path $payloadRoot 'OutlookLocal'
$outlookLocalOnlineTarget = Join-Path $payloadRoot 'OutlookLocalOnline'
$legacyOutlookTarget = Join-Path $payloadRoot 'Outlook'

$excelFiles = @(
    'eWorkhelper.dll',
    'eWorkhelper.dll.manifest',
    'eWorkhelper.vsto',
    'Microsoft.Office.Tools.Common.v4.0.Utilities.dll'
)
$outlookFiles = @(
    'oWorkhelper.dll', 'oWorkhelper.dll.manifest', 'oWorkhelper.vsto',
    'Microsoft.Office.Tools.Common.v4.0.Utilities.dll',
    'Microsoft.Office.Tools.Outlook.v4.0.Utilities.dll',
    'Microsoft.Bcl.HashCode.dll', 'System.Buffers.dll', 'System.Memory.dll',
    'System.Numerics.Vectors.dll', 'System.Runtime.CompilerServices.Unsafe.dll',
    'UglyToad.PdfPig.dll', 'UglyToad.PdfPig.Core.dll',
    'UglyToad.PdfPig.DocumentLayoutAnalysis.dll', 'UglyToad.PdfPig.Fonts.dll',
    'UglyToad.PdfPig.Package.dll', 'UglyToad.PdfPig.Tokenization.dll',
    'UglyToad.PdfPig.Tokens.dll'
)

foreach ($target in @($excelTarget, $outlookLocalTarget, $outlookLocalOnlineTarget)) {
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    New-Item -ItemType Directory -Path $target -Force | Out-Null
}
if (Test-Path -LiteralPath $legacyOutlookTarget) {
    Remove-Item -LiteralPath $legacyOutlookTarget -Recurse -Force
}

function Copy-RequiredFiles([string]$source, [string]$target, [string[]]$files) {
    foreach ($name in $files) {
        $path = Join-Path $source $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required payload is missing: $name" }
        Copy-Item -LiteralPath $path -Destination $target
    }
}

Copy-RequiredFiles $excelSource $excelTarget $excelFiles
Copy-RequiredFiles $outlookLocalSource $outlookLocalTarget $outlookFiles
Copy-RequiredFiles $outlookLocalOnlineSource $outlookLocalOnlineTarget $outlookFiles

foreach ($manifest in @(
    (Join-Path $excelTarget 'eWorkhelper.vsto'),
    (Join-Path $outlookLocalTarget 'oWorkhelper.vsto'),
    (Join-Path $outlookLocalOnlineTarget 'oWorkhelper.vsto')
)) {
    $text = Get-Content -LiteralPath $manifest -Raw
    if ($text -notmatch '<deployment install="false"') { throw "Unexpected VSTO deployment manifest: $manifest" }
}

$localHash = (Get-FileHash -LiteralPath (Join-Path $outlookLocalTarget 'oWorkhelper.dll') -Algorithm SHA256).Hash
$localOnlineHash = (Get-FileHash -LiteralPath (Join-Path $outlookLocalOnlineTarget 'oWorkhelper.dll') -Algorithm SHA256).Hash
if ($localHash -eq $localOnlineHash) {
    throw 'Outlook Local and LocalOnline main assemblies are identical; verify Release-Intranet and Release-Internet were both built.'
}

Write-Host "Collected $($excelFiles.Count) Excel files, $($outlookFiles.Count) Outlook Local files, and $($outlookFiles.Count) Outlook LocalOnline files into separate Payload directories."
