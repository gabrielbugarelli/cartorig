# Install/upgrade only CartoRig Native. Requires administrator; Resolve must be closed.
# Dry-run: .\Install-CartoRigNative.ps1 -Upgrade -WhatIf
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param([string]$BundlePath,[switch]$Upgrade)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($BundlePath)) {
  $artifactBundle = Join-Path $PSScriptRoot 'CartoRigNative.ofx.bundle'
  $developerBundle = Join-Path $PSScriptRoot '..\build\CartoRigNative.ofx.bundle'
  $BundlePath = if (Test-Path -LiteralPath $artifactBundle) { $artifactBundle } else { $developerBundle }
}
$bundle = (Resolve-Path -LiteralPath $BundlePath).Path
$binary = Join-Path $bundle 'Contents\Win64\CartoRigNative.ofx'
if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) {
  throw "Missing Win64 plugin binary: $binary"
}
$resources = Join-Path $bundle 'Contents\Resources'
foreach ($name in @('countries.geojson','brasil-venezuela.cartorig-native.json','LICENSE-COUNTRYINFO.txt')) {
  if (-not (Test-Path -LiteralPath (Join-Path $resources $name) -PathType Leaf)) {
    throw "Missing resource: $name"
  }
}
if (Get-Process -Name 'Resolve' -ErrorAction SilentlyContinue) {
  throw 'Close DaVinci Resolve before installing or upgrading.'
}
$destDir = Join-Path $env:ProgramFiles 'Common Files\OFX\Plugins'
$dest = Join-Path $destDir 'CartoRigNative.ofx.bundle'
if ([IO.Path]::GetFullPath($bundle).TrimEnd('\') -ieq [IO.Path]::GetFullPath($dest).TrimEnd('\')) {
  throw 'Source and destination must not be the same folder.'
}
if ((Test-Path -LiteralPath $dest) -and -not $Upgrade) {
  throw 'CartoRig Native already exists. Pass -Upgrade to replace it safely.'
}
$operation = if (Test-Path -LiteralPath $dest) { 'Upgrade CartoRig Native OpenFX' } else { 'Install CartoRig Native OpenFX' }
if ($PSCmdlet.ShouldProcess($dest,$operation)) {
  New-Item -ItemType Directory -Force -Path $destDir | Out-Null
  $suffix = [guid]::NewGuid().ToString('N')
  $stage = Join-Path $destDir ('.CartoRigNative.stage.' + $suffix)
  $backup = Join-Path $destDir ('.CartoRigNative.backup.' + $suffix)
  try {
    Copy-Item -LiteralPath $bundle -Destination $stage -Recurse -Force
    if (-not (Test-Path -LiteralPath (Join-Path $stage 'Contents\Win64\CartoRigNative.ofx') -PathType Leaf)) {
      throw 'Staged plugin binary missing.'
    }
    if (Test-Path -LiteralPath $dest) {
      Move-Item -LiteralPath $dest -Destination $backup
    }
    Move-Item -LiteralPath $stage -Destination $dest
    if (Test-Path -LiteralPath $backup) {
      Remove-Item -LiteralPath $backup -Recurse -Force
    }
    Write-Host "Installed at $dest. Restart DaVinci Resolve."
  } catch {
    if (Test-Path -LiteralPath $stage) {
      Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ((Test-Path -LiteralPath $backup) -and -not (Test-Path -LiteralPath $dest)) {
      Move-Item -LiteralPath $backup -Destination $dest
    }
    throw
  }
}
