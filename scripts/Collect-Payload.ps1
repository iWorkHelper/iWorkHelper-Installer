[CmdletBinding()]
param(
    [ValidateSet('Release-Intranet', 'Release-Internet')]
    [string]$OutlookConfiguration = 'Release-Intranet'
)

$ErrorActionPreference = 'Stop'
$installerRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $installerRoot
$payloadRoot = Join-Path $installerRoot 'Payload'
$excelSource = Join-Path $workspaceRoot 'eWorkHelper\bin\Release'
$outlookSource = Join-Path $workspaceRoot "oWorkHelper\bin\$OutlookConfiguration"
$excelTarget = Join-Path $payloadRoot 'Excel'
$outlookTarget = Join-Path $payloadRoot 'Outlook'

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

foreach ($target in @($excelTarget, $outlookTarget)) {
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    New-Item -ItemType Directory -Path $target -Force | Out-Null
}

function Copy-RequiredFiles([string]$source, [string]$target, [string[]]$files) {
    foreach ($name in $files) {
        $path = Join-Path $source $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required payload is missing: $name" }
        Copy-Item -LiteralPath $path -Destination $target
    }
}

Copy-RequiredFiles $excelSource $excelTarget $excelFiles
Copy-RequiredFiles $outlookSource $outlookTarget $outlookFiles

foreach ($manifest in @((Join-Path $excelTarget 'eWorkhelper.vsto'), (Join-Path $outlookTarget 'oWorkhelper.vsto'))) {
    $text = Get-Content -LiteralPath $manifest -Raw
    if ($text -notmatch '<deployment install="false"') { throw "Unexpected VSTO deployment manifest: $manifest" }
}

Write-Host "Collected $($excelFiles.Count) Excel files and $($outlookFiles.Count) Outlook files into Payload."

