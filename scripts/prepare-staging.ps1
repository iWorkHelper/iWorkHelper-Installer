param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $true)]
    [string]$InstallerRoot
)

$ErrorActionPreference = 'Stop'

function Fail($Message) {
    throw "Prepare staging failed: $Message"
}

function Copy-RequiredFile($SourceDir, $DestinationDir, $FileName) {
    $src = Join-Path $SourceDir $FileName
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
        Fail "Required file not found: $src"
    }
    Copy-Item -LiteralPath $src -Destination (Join-Path $DestinationDir $FileName) -Force
}

function Get-InstallDependencyCodebases($ManifestPath) {
    [xml]$xml = Get-Content -LiteralPath $ManifestPath -Raw
    $nsmgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $nsmgr.AddNamespace('asmv2', 'urn:schemas-microsoft-com:asm.v2')
    $nodes = $xml.SelectNodes("//asmv2:dependentAssembly[@dependencyType='install']", $nsmgr)
    $items = @()
    foreach ($node in $nodes) {
        $codebase = $node.GetAttribute('codebase')
        if (-not [string]::IsNullOrWhiteSpace($codebase) -and $codebase.EndsWith('.dll', [StringComparison]::OrdinalIgnoreCase)) {
            $items += $codebase
        }
    }
    return $items | Select-Object -Unique
}

function Copy-ComponentFromManifest($Name, $SourceDir, $DestinationDir, $MainDll, $Vsto, $DllManifest) {
    if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) {
        Fail "$Name build output not found: $SourceDir"
    }

    New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
    Copy-RequiredFile $SourceDir $DestinationDir $MainDll
    Copy-RequiredFile $SourceDir $DestinationDir $Vsto
    Copy-RequiredFile $SourceDir $DestinationDir $DllManifest

    $manifestPath = Join-Path $SourceDir $DllManifest
    foreach ($dependency in (Get-InstallDependencyCodebases $manifestPath)) {
        Copy-RequiredFile $SourceDir $DestinationDir $dependency
    }
}

$stagingRoot = Join-Path $InstallerRoot 'staging'
if (Test-Path -LiteralPath $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null

$eSource = Join-Path $RepoRoot 'eWorkHelper\bin\Release'
$oLocalSource = Join-Path $RepoRoot 'oWorkHelper\bin\Release-Intranet'
$oBaiduSource = Join-Path $RepoRoot 'oWorkHelper\bin\Release-Internet'

Copy-ComponentFromManifest `
    -Name 'eWorkHelper' `
    -SourceDir $eSource `
    -DestinationDir (Join-Path $stagingRoot 'eWorkHelper') `
    -MainDll 'eWorkhelper.dll' `
    -Vsto 'eWorkhelper.vsto' `
    -DllManifest 'eWorkhelper.dll.manifest'

Copy-ComponentFromManifest `
    -Name 'oWorkHelper Local' `
    -SourceDir $oLocalSource `
    -DestinationDir (Join-Path $stagingRoot 'oWorkHelper\local') `
    -MainDll 'oWorkhelper.dll' `
    -Vsto 'oWorkhelper.vsto' `
    -DllManifest 'oWorkhelper.dll.manifest'

Copy-ComponentFromManifest `
    -Name 'oWorkHelper Baidu' `
    -SourceDir $oBaiduSource `
    -DestinationDir (Join-Path $stagingRoot 'oWorkHelper\baidu') `
    -MainDll 'oWorkhelper.dll' `
    -Vsto 'oWorkhelper.vsto' `
    -DllManifest 'oWorkhelper.dll.manifest'

& (Join-Path $InstallerRoot 'scripts\validate-staging.ps1') -StagingRoot $stagingRoot

Write-Host "Prepared staging: $stagingRoot"
