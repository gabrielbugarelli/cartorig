# CartoRig Windows easy-test installer. Run by double-clicking Install-CartoRig.cmd.
# Copies a prebuilt OFX plugin and a built-in Lua Resolve script. No Python required.
[CmdletBinding()]
param([switch]$Elevated)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSCommandPath
$bundle=Join-Path $root 'CartoRigNative.ofx.bundle'
$utilityScripts=@(
  'CartoRig - Create Map.lua',
  'CartoRig - Add Country.lua',
  'CartoRig - Add Route.lua',
  'CartoRig - Set Camera.lua',
  'CartoRig Hybrid Test.lua'
)
$libraryScripts=@('core.lua','countries.lua')
$nativeInstaller=Join-Path $root 'Install-CartoRigNative.ps1'
$allFiles=@($nativeInstaller,(Join-Path $bundle 'Contents\Win64\CartoRigNative.ofx'))
$allFiles+=@($utilityScripts | ForEach-Object {Join-Path $root $_})
$allFiles+=@($libraryScripts | ForEach-Object {Join-Path (Join-Path $root 'CartoRigSupport') $_})
foreach ($file in $allFiles) {
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
    throw "Incomplete CartoRig package. Missing: $file"
  }
}
if (Get-Process -Name 'Resolve' -ErrorAction SilentlyContinue) {
  throw 'Close DaVinci Resolve before installing, then reopen it to test.'
}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  if ($Elevated) {throw 'Administrator permission was not granted.'}
  Write-Host 'CartoRig requires a one-time Windows permission prompt to install OpenFX.'
  $args='-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Elevated'
  $child=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -Verb RunAs -Wait -PassThru -ArgumentList $args
  if ($child.ExitCode -ne 0) {exit $child.ExitCode}
  exit 0
}
Write-Host 'Installing CartoRig Native OpenFX...'
& $nativeInstaller -BundlePath $bundle -Upgrade -Confirm:$false
if (-not $?) {throw 'OpenFX installation failed.'}
# System-wide Scripts/Utility is a documented Resolve script-menu location.
$utility=Join-Path $env:ProgramData 'Blackmagic Design\DaVinci Resolve\Fusion\Scripts\Utility'
New-Item -ItemType Directory -Path $utility -Force | Out-Null
# Install all scripts with per-file SHA256 verification. The runtime only
# needs the prebuilt OFX bundle and Lua embedded in Resolve.
$support=Join-Path $utility 'CartoRigSupport'
New-Item -ItemType Directory -Path $support -Force | Out-Null
foreach ($filename in $utilityScripts) {
  $origin=Join-Path $root $filename
  $destination=Join-Path $utility $filename
  $staged=Join-Path $utility ('.CartoRig-stage-'+[guid]::NewGuid().ToString('N'))
  try {
    Copy-Item -LiteralPath $origin -Destination $staged -Force
    if ((Get-FileHash -LiteralPath $origin -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash) {
      throw "Script copy failed integrity verification: $filename"
    }
    Move-Item -LiteralPath $staged -Destination $destination -Force
  } finally {
    if (Test-Path -LiteralPath $staged) {Remove-Item -LiteralPath $staged -Force}
  }
}
foreach ($filename in $libraryScripts) {
  $origin=Join-Path (Join-Path $root 'CartoRigSupport') $filename
  $destination=Join-Path $support $filename
  $staged=Join-Path $support ('.CartoRig-stage-'+[guid]::NewGuid().ToString('N'))
  try {
    Copy-Item -LiteralPath $origin -Destination $staged -Force
    if ((Get-FileHash -LiteralPath $origin -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash) {
      throw "Library copy failed integrity verification: $filename"
    }
    Move-Item -LiteralPath $staged -Destination $destination -Force
  } finally {
    if (Test-Path -LiteralPath $staged) {Remove-Item -LiteralPath $staged -Force}
  }
}

Write-Host ''
Write-Host 'CartoRig Edit-first authoring installed successfully.'
Write-Host 'Open Resolve 20, select a timeline, then:'
Write-Host 'Workspace > Scripts > Utility > CartoRig - Create Map'
Write-Host 'Add Country, Add Route and Set Camera commands become available for the map clip.'
