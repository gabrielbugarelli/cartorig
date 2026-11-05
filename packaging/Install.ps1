# Run from a Windows PowerShell terminal (as administrator) with Resolve closed.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param([string]$BundlePath = "$(Join-Path $PSScriptRoot '..\build\CartoRigNative.ofx.bundle')")
$ErrorActionPreference = 'Stop'
$bundle = (Resolve-Path -LiteralPath $BundlePath).Path
$source = Join-Path $bundle 'Contents\Win64\CartoRigNative.ofx'
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing Win64 OFX plugin binary: $source" }
$resources = Join-Path $bundle 'Contents\Resources'
foreach ($name in @('countries.geojson','brasil-venezuela.cartorig-native.json','LICENSE-COUNTRYINFO.txt')) {
  if (-not (Test-Path -LiteralPath (Join-Path $resources $name) -PathType Leaf)) { throw "Missing resource: $name" }
}
if (Get-Process -Name 'Resolve' -ErrorAction SilentlyContinue) { throw 'Close DaVinci Resolve before installing' }
$destDir = Join-Path ${env:ProgramFiles} 'Common Files\OFX\Plugins'
$dest = Join-Path $destDir 'CartoRigNative.ofx.bundle'
if ($PSCmdlet.ShouldProcess($dest,'Install CartoRig Native OFX bundle')) {
  New-Item -ItemType Directory -Force -Path $destDir | Out-Null
  if (Test-Path -LiteralPath $dest) { throw "Destination already exists: $dest. Remove it explicitly after backing up." }
  Copy-Item -LiteralPath $bundle -Destination $dest -Recurse
  Write-Host "Installed $dest. Restart Resolve Studio 20 and verify both OpenFX effects."
}
