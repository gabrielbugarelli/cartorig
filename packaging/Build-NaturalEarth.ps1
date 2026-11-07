# One-command full Natural Earth data producer, release workstation ONLY.
# No network access unless -AllowNetwork is passed explicitly.
# Usage:
#   ./packaging/Build-NaturalEarth.ps1 -Workspace 'D:\CartoRigBuild' \
#     -Output 'D:\CartoRigNaturalEarth' -AllowNetwork -MaxDownloads 100
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Workspace,
  [Parameter(Mandatory=$true)][string]$Output,
  [switch]$AllowNetwork,
  [switch]$SetupDependencies,
  [int]$MaxDownloads = 100,
  [string]$Python = 'python'
)
$ErrorActionPreference = 'Stop'
if ($MaxDownloads -lt 0) { throw 'MaxDownloads must not be negative.' }
$repository = Split-Path -Parent $PSScriptRoot
$requirements = Join-Path $repository 'tools\natural_earth\requirements-release.txt'
if (-not (Get-Command $Python -ErrorAction SilentlyContinue)) {
  throw 'Python not found. Install a supported Python version first.'
}
if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
  throw 'ImageMagick 7 (magick) is required for Natural Earth PSD raster variants on the release workstation.'
}
Push-Location $repository
try {
  if ($SetupDependencies) {
    & $Python -m pip install -r $requirements
    if ($LASTEXITCODE -ne 0) { throw 'Python build-only dependency installation failed.' }
  }
  $arguments = @(
    '-m','tools.natural_earth.release_pipeline',
    '--workspace',$Workspace,'--output',$Output,
    '--max-downloads',([string]$MaxDownloads),'--resume'
  )
  if ($AllowNetwork) { $arguments += '--allow-network' }
  & $Python @arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Natural Earth data producer did not certify a complete pack (exit $LASTEXITCODE). Source downloads and staged data remain resumable."
  }
  & $Python -m tools.natural_earth.verify_release --root $Output
  if ($LASTEXITCODE -ne 0) {
    throw 'Offline package verification failed; do not distribute this directory.'
  }
  Write-Host 'Complete Natural Earth data pack prepared and verified.'
  Write-Host "Copy the data directory to the offline Resolve workstation: $Output"
  Write-Host 'Install with packaging/Install-DataPack.ps1 -SourceRoot <copied folder>.'
}
finally {
  Pop-Location
}
