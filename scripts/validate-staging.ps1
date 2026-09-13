param(
    [Parameter(Mandatory = $true)]
    [string]$StagingRoot
)

$ErrorActionPreference = 'Stop'

function Fail($Message) {
    throw "Staging validation failed: $Message"
}

function Get-InstallDependencyCodebases($ManifestPath) {
    [xml]$xml = Get-Content -LiteralPath $ManifestPath -Raw
    $nsmgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $nsmgr.AddNamespace('asmv2', 'urn:schemas-microsoft-com:asm.v2')
    $nodes = $xml.SelectNodes("//asmv2:dependentAssembly[@dependencyType='install']", $nsmgr)
    $items = @()
    foreach ($node in $nodes) {
        $codebase = $node.GetAttribute('codebase')
        if (-not [string]::IsNullOrWhiteSpace($codebase)) {
            $items += $codebase
        }
    }
    return $items
}

function Test-Component($Name, $MainDll, $Vsto, $DllManifest) {
    $dir = Join-Path $StagingRoot $Name
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        Fail "$Name directory not found: $dir"
    }

    foreach ($file in @($MainDll, $Vsto, $DllManifest)) {
        $path = Join-Path $dir $file
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Fail "$Name required file not found: $file"
        }
    }

    $dependencies = Get-InstallDependencyCodebases (Join-Path $dir $DllManifest)
    foreach ($dependency in $dependencies) {
        $path = Join-Path $dir $dependency
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Fail "$Name manifest dependency not found: $dependency"
        }
    }

    $pdb = Get-ChildItem -LiteralPath $dir -Filter *.pdb -File -ErrorAction SilentlyContinue
    if ($pdb) {
        Fail "$Name staging contains PDB files"
    }
}

Test-Component -Name 'eWorkHelper' -MainDll 'eWorkhelper.dll' -Vsto 'eWorkhelper.vsto' -DllManifest 'eWorkhelper.dll.manifest'
Test-Component -Name 'oWorkHelper\local' -MainDll 'oWorkhelper.dll' -Vsto 'oWorkhelper.vsto' -DllManifest 'oWorkhelper.dll.manifest'
Test-Component -Name 'oWorkHelper\baidu' -MainDll 'oWorkhelper.dll' -Vsto 'oWorkhelper.vsto' -DllManifest 'oWorkhelper.dll.manifest'

$localDll = Join-Path $StagingRoot 'oWorkHelper\local\oWorkhelper.dll'
$baiduDll = Join-Path $StagingRoot 'oWorkHelper\baidu\oWorkhelper.dll'
$localHash = (Get-FileHash -LiteralPath $localDll -Algorithm SHA256).Hash
$baiduHash = (Get-FileHash -LiteralPath $baiduDll -Algorithm SHA256).Hash
if ($localHash -eq $baiduHash) {
    Fail "oWorkHelper Local and Baidu main DLL hashes are identical; variant staging may be contaminated"
}

Write-Host "Staging validation passed: $StagingRoot"
