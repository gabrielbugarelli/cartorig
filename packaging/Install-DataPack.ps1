# Offline verified Natural Earth data pack installer (PowerShell 5.1+).
# Does not access the network; keeps previous installation on upgrade failure.
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
  [Parameter(Mandatory=$true)][string]$SourceRoot,
  [string]$Destination = (Join-Path $env:LOCALAPPDATA 'CartoRigNative\NaturalEarth'),
  [switch]$Upgrade,
  [switch]$AllowIncomplete
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Pack {
  param([Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)][bool]$AllowExperimental)
  $rootPath = [IO.Path]::GetFullPath($Root)
  if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) {
    throw 'Offline Natural Earth data pack root is missing.'
  }
  $manifestFile = Join-Path $rootPath 'pack.json'
  if (-not (Test-Path -LiteralPath $manifestFile -PathType Leaf)) {
    throw 'Offline Natural Earth pack manifest is missing.'
  }
  $manifest = Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($manifest.schema_version -ne 1 -or
      $manifest.format -ne 'cartorig-natural-earth-offline-v1') {
    throw 'Unsupported Natural Earth data pack manifest.'
  }
  if ($manifest.complete -eq $true) {
    if ($manifest.status -ne 'NATURAL_EARTH_COMPLETE') {
      throw 'Complete data pack has inconsistent certification status.'
    }
  } else {
    if ($manifest.status -ne 'EXPERIMENTAL_INCOMPLETE' -or -not $AllowExperimental) {
      throw 'Pack is incomplete. -AllowIncomplete is for test fixtures only.'
    }
  }
  $entries = @($manifest.files)
  if ($entries.Count -lt 1 -or $entries.Count -gt 1000000) {
    throw 'Invalid Natural Earth data pack file count.'
  }
  $rootPrefix = $rootPath.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
  $names = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  $canonicalLines = New-Object 'System.Collections.Generic.List[string]'
  $previous = ''
  [decimal]$total = 0
  foreach ($entry in $entries) {
    $relative = [string]$entry.path
    if ([string]::IsNullOrWhiteSpace($relative) -or
        $relative -notmatch '^[A-Za-z0-9][A-Za-z0-9_./-]{0,255}$' -or
        $relative.StartsWith('/') -or
        $relative -eq 'pack.json' -or
        $relative -match '(^|/)\.\.?(/|$)' -or
        -not $names.Add($relative)) {
      throw "Unsafe or duplicate data pack path: $relative"
    }
    if ($previous.Length -gt 0 -and
        [string]::CompareOrdinal($previous,$relative) -ge 0) {
      throw 'Noncanonical manifest order; expected sorted file paths.'
    }
    $previous = $relative
    $absolute = [IO.Path]::GetFullPath((Join-Path $rootPath $relative))
    if (-not $absolute.StartsWith($rootPrefix,[StringComparison]::OrdinalIgnoreCase)) {
      throw "Pack file path escapes data root: $relative"
    }
    $file = Get-Item -LiteralPath $absolute -Force -ErrorAction Stop
    if ($file.PSIsContainer -or
        (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
      throw "Invalid or linked data file: $relative"
    }
    [decimal]$length = [decimal]$entry.bytes
    $hash = ([string]$entry.sha256).ToLowerInvariant()
    if ($length -lt 0 -or $length -gt [decimal][long]::MaxValue -or
        $hash -notmatch '^[0-9a-f]{64}$' -or
        [decimal]$file.Length -ne $length -or
        (Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hash) {
      throw "Natural Earth file size or SHA256 mismatch: $relative"
    }
    $total += $length
    # Filenames are restricted to ASCII letters/digits/._/-; no escaping
    # ambiguity is possible. Match Python json.dumps(sort_keys=True,
    # separators=(',',':')) canonical per-file dictionary representation.
    $canonicalLines.Add(('{"bytes":' + $length.ToString([Globalization.CultureInfo]::InvariantCulture) +
                         ',"path":"' + $relative + '","sha256":"' + $hash + '"}'))
  }
  foreach ($required in @(
    'vector/natural_earth_vector.gpkg',
    'vector/supplements.gpkg',
    'vector/catalog.sqlite',
    'raster/validated-raster-assets.json'
  )) {
    if (-not $names.Contains($required)) {
      throw "Natural Earth pack missing essential asset: $required"
    }
  }
  foreach ($actual in (Get-ChildItem -LiteralPath $rootPath -Recurse -Force)) {
    if (($actual.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "Offline data pack contains a symbolic link: $($actual.FullName)"
    }
    if (-not $actual.PSIsContainer) {
      $relative = $actual.FullName.Substring($rootPrefix.Length).Replace('\','/')
      if ($relative -ne 'pack.json' -and -not $names.Contains($relative)) {
        throw "Undeclared file in offline data pack: $relative"
      }
    }
  }
  $canonical = '[' + [string]::Join(',', $canonicalLines.ToArray()) + ']'
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [Text.Encoding]::UTF8.GetBytes($canonical)
    $actualId = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()
  } finally { $sha.Dispose() }
  if ($actualId -ne ([string]$manifest.pack_id).ToLowerInvariant()) {
    throw 'Natural Earth pack_id differs from canonical file contents.'
  }
  return [PSCustomObject]@{
    Id = $actualId
    Bytes = $total
    Certified = [bool]$manifest.complete
    Files = $entries.Count
  }
}

$source = (Resolve-Path -LiteralPath $SourceRoot -ErrorAction Stop).Path
$dest = [IO.Path]::GetFullPath($Destination)
$sourceFull = [IO.Path]::GetFullPath($source).TrimEnd('\','/')
$destFull = $dest.TrimEnd('\','/')
if ($sourceFull -ieq $destFull -or
    $destFull.StartsWith($sourceFull + [IO.Path]::DirectorySeparatorChar,
                         [StringComparison]::OrdinalIgnoreCase) -or
    $sourceFull.StartsWith($destFull + [IO.Path]::DirectorySeparatorChar,
                           [StringComparison]::OrdinalIgnoreCase)) {
  throw 'Source and destination must not be equal or nested.'
}
if (Get-Process -Name 'Resolve' -ErrorAction SilentlyContinue) {
  throw 'Close DaVinci Resolve before changing offline Natural Earth data.'
}
$sourceProof = Assert-Pack -Root $source -AllowExperimental $AllowIncomplete.IsPresent
if ((Test-Path -LiteralPath $dest) -and -not $Upgrade) {
  throw 'Natural Earth pack is already installed; use -Upgrade.'
}
$parent = Split-Path -Parent $dest
$volume = [IO.Path]::GetPathRoot($dest)
if ($volume -and $volume -match '^[A-Za-z]:\\') {
  $drive = New-Object IO.DriveInfo $volume
  [decimal]$headroom = [Math]::Max(536870912.0,[double]$sourceProof.Bytes * 0.05)
  if ([decimal]$drive.AvailableFreeSpace -lt ($sourceProof.Bytes + $headroom)) {
    throw 'Not enough free disk space for verified staged installation.'
  }
}

if ($PSCmdlet.ShouldProcess($dest, "Install Natural Earth $($sourceProof.Id)")) {
  New-Item -ItemType Directory -Path $parent -Force | Out-Null
  $nonce = [guid]::NewGuid().ToString('N')
  $stage = Join-Path $parent ('.NaturalEarth.stage.' + $nonce)
  $backup = Join-Path $parent ('.NaturalEarth.backup.' + $nonce)
  $committed = $false
  try {
    Copy-Item -LiteralPath $source -Destination $stage -Recurse -Force
    $stageProof = Assert-Pack -Root $stage -AllowExperimental $AllowIncomplete.IsPresent
    if ($stageProof.Id -ne $sourceProof.Id) {
      throw 'Copied data pack identity differs from source.'
    }
    if (Test-Path -LiteralPath $dest) {
      Move-Item -LiteralPath $dest -Destination $backup
    }
    Move-Item -LiteralPath $stage -Destination $dest
    $committed = $true
  } catch {
    if (Test-Path -LiteralPath $stage) {
      Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ((Test-Path -LiteralPath $backup) -and -not (Test-Path -LiteralPath $dest)) {
      Move-Item -LiteralPath $backup -Destination $dest
    }
    throw
  }
  if ($committed) {
    if (Test-Path -LiteralPath $backup) {
      try {
        Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction Stop
      } catch {
        Write-Warning "Installed successfully, but old backup needs manual cleanup: $backup"
      }
    }
    Write-Host "Natural Earth data pack installed: $dest"
    Write-Host "Pack SHA256 identity: $($stageProof.Id)"
    Write-Host "Verified source files: $($stageProof.Files)"
  }
}
