# Installs the verified Natural Earth data directory without accessing any URL.
# No administrative rights required when using the default LOCALAPPDATA path.
# Usage:
#   ./Install-DataPack.ps1 -SourceRoot D:\CartoRigData -Upgrade
#   ./Install-DataPack.ps1 -SourceRoot D:\CartoRigData -AllowIncomplete -WhatIf
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
  [Parameter(Mandatory=$true)][string]$SourceRoot,
  [string]$Destination = (Join-Path $env:LOCALAPPDATA 'CartoRigNative\NaturalEarth'),
  [switch]$Upgrade,
  [switch]$AllowIncomplete
)
$ErrorActionPreference = 'Stop'

function Assert-Pack([string]$Root,[bool]$AllowExperimental) {
  $manifestPath = Join-Path $Root 'pack.json'
  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw 'Offline Natural Earth pack manifest is missing.'
  }
  $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 |
              ConvertFrom-Json -Depth 20
  if ($manifest.schema_version -ne 1 -or
      $manifest.format -ne 'cartorig-natural-earth-offline-v1') {
    throw 'Unsupported Natural Earth pack manifest.'
  }
  if (-not $manifest.complete -and -not $AllowExperimental) {
    throw 'Pack is not certified complete. Use -AllowIncomplete only for experimental tests.'
  }
  $entries = @($manifest.files)
  if ($entries.Count -eq 0 -or $entries.Count -gt 1000000) {
    throw 'Invalid Natural Earth pack file count.'
  }
  $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($entry in $entries) {
    $pathName = [string]$entry.path
    if ([string]::IsNullOrWhiteSpace($pathName) -or
        $pathName.StartsWith('/') -or $pathName.StartsWith('\') -or
        $pathName.Contains(':') -or $pathName.Contains('\') -or
        $pathName -match '(^|/)\.\.?(?:/|$)' -or
        -not $seen.Add($pathName)) {
      throw "Unsafe or duplicated data path in manifest: $pathName"
    }
    $absolute = [IO.Path]::GetFullPath((Join-Path $Root $pathName))
    if (-not $absolute.StartsWith($rootFull,[StringComparison]::OrdinalIgnoreCase)) {
      throw 'Manifest path escapes data pack root.'
    }
    $file = Get-Item -LiteralPath $absolute -Force -ErrorAction Stop
    if ($file.PSIsContainer -or
        (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
      throw "Invalid or linked pack asset: $pathName"
    }
    if ($file.Length -ne [int64]$entry.bytes -or
        (Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash.ToLowerInvariant() -ne
            ([string]$entry.sha256).ToLowerInvariant()) {
      throw "Natural Earth pack integrity failure: $pathName"
    }
  }
  $essential = @('vector/natural_earth_vector.gpkg',
                 'vector/supplements.gpkg','vector/catalog.sqlite',
                 'raster/validated-raster-assets.json')
  foreach ($item in $essential) {
    if (-not $seen.Contains($item)) { throw "Essential data pack asset missing: $item" }
  }
  return $manifest
}

$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$dest = [IO.Path]::GetFullPath($Destination)
if ([IO.Path]::GetFullPath($source).TrimEnd('\','/') -ieq
    $dest.TrimEnd('\','/')) {
  throw 'Source and destination must be different locations.'
}
if (Get-Process -Name 'Resolve' -ErrorAction SilentlyContinue) {
  throw 'Close DaVinci Resolve before changing Natural Earth data.'
}
$sourcePack = Assert-Pack -Root $source -AllowExperimental $AllowIncomplete.IsPresent
if ((Test-Path -LiteralPath $dest) -and -not $Upgrade) {
  throw 'Natural Earth data pack already installed. Use -Upgrade.'
}
$parent = Split-Path -Parent $dest
if ($PSCmdlet.ShouldProcess($dest,"Install verified offline Natural Earth pack $($sourcePack.pack_id)")) {
  New-Item -ItemType Directory -Path $parent -Force | Out-Null
  $nonce=[guid]::NewGuid().ToString('N')
  $stage=Join-Path $parent ('.NaturalEarth.stage.'+$nonce)
  $backup=Join-Path $parent ('.NaturalEarth.backup.'+$nonce)
  try {
    # Copy into the destination volume first, so final directory rename is
    # atomic on NTFS and never exposes a half-copied live data pack.
    Copy-Item -LiteralPath $source -Destination $stage -Recurse -Force
    $stagedPack=Assert-Pack -Root $stage -AllowExperimental $AllowIncomplete.IsPresent
    if ($stagedPack.pack_id -ne $sourcePack.pack_id) {
      throw 'Staged data pack identity has changed.'
    }
    if (Test-Path -LiteralPath $dest) {
      Move-Item -LiteralPath $dest -Destination $backup
    }
    Move-Item -LiteralPath $stage -Destination $dest
    if (Test-Path -LiteralPath $backup) {
      Remove-Item -LiteralPath $backup -Recurse -Force
    }
    Write-Host "Installed offline pack: $dest"
    Write-Host "Pack ID: $($stagedPack.pack_id)"
    Write-Host 'Set Vector GeoPackage to <installed>\vector\natural_earth_vector.gpkg'
    Write-Host 'Set Raster tiles directory to <installed>\raster'
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
