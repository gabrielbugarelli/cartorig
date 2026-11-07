# Persistent 51-source Natural Earth acquisition and native 1440p/4K QA.
# Actual in-host DaVinci Resolve tests are a separate acceptance gate.
# Example: .\packaging\Run-NaturalEarth-QA.ps1 -Workspace D:\CartoRigBuild -Output D:\CartoRigExperimental -AllowNetwork -SetupDependencies
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Workspace,
  [Parameter(Mandatory=$true)][string]$Output,
  [switch]$AllowNetwork,
  [switch]$SetupDependencies,
  [switch]$SkipNativeQA,
  [switch]$InstallExperimentalPack,
  [ValidateRange(1,52)][int]$MaxDownloads=12,
  [ValidateRange(1,100)][int]$MaxBatches=10,
  [ValidateRange(0,1000)][double]$MinFreeGiB=50,
  [string]$Python='python'
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repository=Split-Path -Parent $PSScriptRoot
if (-not (Get-Command $Python -ErrorAction SilentlyContinue)) {
  throw 'Python is required on the persistent Windows release workstation.'
}
if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
  throw 'ImageMagick 7 (magick) is required to convert publisher PSD raster variants.'
}
if ($InstallExperimentalPack -and (Get-Process -Name Resolve -ErrorAction SilentlyContinue)) {
  throw 'Close DaVinci Resolve before updating its offline Natural Earth data.'
}
Push-Location $repository
try {
  if ($SetupDependencies) {
    if (-not $AllowNetwork) {
      throw '-SetupDependencies requires explicit -AllowNetwork on the release workstation.'
    }
    & $Python -m pip install -r 'tools/natural_earth/requirements-release.txt'
    if ($LASTEXITCODE -ne 0) {throw 'Python release-only dependency installation failed.'}
  }
  $native=$null
  if (-not $SkipNativeQA) {
    if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
      throw 'CMake + Visual Studio C++ are needed for native 1440p/4K QA.'
    }
    $buildDir=Join-Path $repository 'build\natural-earth-workstation-qa'
    & cmake -S $repository -B $buildDir -DCMAKE_BUILD_TYPE=Release -DCARTORIG_BUILD_TESTS=ON
    if ($LASTEXITCODE -ne 0) {throw 'CMake configure failed.'}
    & cmake --build $buildDir --config Release --target cartorig_ne_raster_preview --parallel 2
    if ($LASTEXITCODE -ne 0) {throw 'Native CartoRig C++ raster preview build failed.'}
    foreach ($candidate in @(
      (Join-Path $buildDir 'Release\cartorig_ne_raster_preview.exe'),
      (Join-Path $buildDir 'cartorig_ne_raster_preview.exe')
    )) {
      if (Test-Path -LiteralPath $candidate -PathType Leaf) {$native=$candidate;break}
    }
    if (-not $native) {throw 'Built native raster preview executable was not found.'}
  }
  $arguments=@(
    '-m','tools.natural_earth.workstation_cycle',
    '--workspace',$Workspace,'--output',$Output,
    '--max-downloads',([string]$MaxDownloads),
    '--max-batches',([string]$MaxBatches),
    '--min-free-gib',$MinFreeGiB.ToString([Globalization.CultureInfo]::InvariantCulture)
  )
  if ($AllowNetwork) {$arguments+='--allow-network'}
  if ($native) {$arguments+=@('--native-preview',$native)}
  & $Python @arguments
  if ($LASTEXITCODE -ne 0) {
    Write-Warning 'Not complete: source archives and checkpoints are preserved. See workstation-qa-report.json and rerun the identical command.'
    throw '51-source experimental pack or native QA did not pass.'
  }
  Write-Host 'Experimental offline pack and native source-backed checks completed.'
  Write-Host 'Result: EXPERIMENTAL_INCOMPLETE, not NATURAL_EARTH_COMPLETE.'
  Write-Host "QA evidence: $(Join-Path $Workspace 'workstation-qa-report.json')"
  if ($InstallExperimentalPack) {
    # An explicitly requested QA rerun must upgrade the already installed
    # experimental pack rather than fail after successful re-verification.
    & (Join-Path $PSScriptRoot 'Install-DataPack.ps1') -SourceRoot $Output -AllowIncomplete -Upgrade -Confirm:$false
    if (-not $?) {throw 'Experimental offline data pack installation failed.'}
    Write-Host 'Offline data installed; restart DaVinci Resolve 20 for in-host acceptance.'
  }
}
finally {
  Pop-Location
}
