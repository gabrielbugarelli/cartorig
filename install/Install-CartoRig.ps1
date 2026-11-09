#requires -version 5.1
# Offline RC1 installer; only CartoRig-owned paths are modified.
[CmdletBinding()]
param([switch] $Elevated)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$bundle=Join-Path $root 'CartoRigFusion.ofx.bundle'
$manifest=Join-Path $bundle 'Contents\Resources\data\manifest.json'
$geometry=Join-Path $bundle 'Contents\Resources\data\geometry.crgeo'
$catalog=Join-Path $bundle 'Contents\Resources\data\catalog.tsv'
$plugin=Join-Path $bundle 'Contents\Win64\CartoRigFusion.ofx'
$script=Join-Path $root 'Fusion\Scripts\Comp\CartoRig Scene.lua'
$support=Join-Path $root 'Fusion\Scripts\Comp\CartoRigSupport\scene.lua'
foreach($path in @($manifest,$geometry,$catalog,$plugin,$script,$support)){
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){
        throw "Incomplete CartoRig package: $path"
    }
}
if(Get-Process -Name 'Resolve' -ErrorAction SilentlyContinue){
    throw 'Close DaVinci Resolve completely before installing CartoRig.'
}
$meta=Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
if($meta.format -ne 'CRG1' -or $meta.network_required_by_runtime -ne $false){
    throw 'CartoRig offline data manifest is invalid.'
}
$geoHash=(Get-FileHash -LiteralPath $geometry -Algorithm SHA256).Hash.ToLowerInvariant()
$catHash=(Get-FileHash -LiteralPath $catalog -Algorithm SHA256).Hash.ToLowerInvariant()
if($geoHash -ne [string]$meta.geometry_sha256 -or
   $catHash -ne [string]$meta.catalog_sha256){
    throw 'Natural Earth data integrity check failed. Obtain a complete RC package.'
}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=New-Object Security.Principal.WindowsPrincipal($identity)
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
    if($Elevated){throw 'Administrator access was not granted.'}
    $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',
            ('"' + $MyInvocation.MyCommand.Path + '"'),'-Elevated')
    $process=Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs -Wait -PassThru
    if($process.ExitCode -ne 0){throw "Elevated setup failed ($($process.ExitCode))."}
    Write-Host 'CartoRig installation completed with administrator rights.'
    exit 0
}
$ofxHome=Join-Path $env:ProgramFiles 'Common Files\OFX\Plugins'
$destination=Join-Path $ofxHome 'CartoRigFusion.ofx.bundle'
$compHome=Join-Path $env:APPDATA 'Blackmagic Design\DaVinci Resolve\Support\Fusion\Scripts\Comp'
New-Item -ItemType Directory -Force -Path $ofxHome,$compHome | Out-Null
$staged=Join-Path $ofxHome 'CartoRigFusion.ofx.bundle.staging'
if(Test-Path $staged){Remove-Item -LiteralPath $staged -Recurse -Force}
Copy-Item -LiteralPath $bundle -Destination $staged -Recurse -Force
$backup=Join-Path $env:TEMP ('CartoRigFusion-backup-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
if(Test-Path -LiteralPath $destination){
    Move-Item -LiteralPath $destination -Destination $backup
}
try{
    Move-Item -LiteralPath $staged -Destination $destination
}catch{
    if(Test-Path $backup){Move-Item -LiteralPath $backup -Destination $destination}
    throw
}
$supportDir=Join-Path $compHome 'CartoRigSupport'
New-Item -ItemType Directory -Force -Path $supportDir | Out-Null
Copy-Item -LiteralPath $script -Destination (Join-Path $compHome 'CartoRig Scene.lua') -Force
Copy-Item -LiteralPath $support -Destination (Join-Path $supportDir 'scene.lua') -Force
$dataDir=Join-Path $destination 'Contents\Resources\data'
# Windows PowerShell 5.1 Set-Content -Encoding UTF8 writes a BOM.
# The Fusion Lua script reads this as raw bytes; a BOM corrupts the path.
$installRoot=Join-Path $supportDir 'install-root.txt'
$utf8WithoutBom=New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($installRoot, $dataDir + [Environment]::NewLine, $utf8WithoutBom)
Write-Host 'Installed CartoRig Fusion OpenFX and Scene UIManager script.'
Write-Host 'Resolve Studio 20 > Fusion > Workspace > Scripts > Comp > CartoRig Scene.'
Write-Host "Natural Earth features: $($meta.features). The plugin is offline."
if(Test-Path $backup){Write-Host "Previous CartoRig installation preserved at $backup"}
