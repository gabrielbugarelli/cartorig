# CartoRig Windows easy-test installer. Run by double-clicking Install-CartoRig.cmd.
# Copies a prebuilt OFX plugin and a built-in Lua Resolve script. No Python required.
[CmdletBinding()]
param([switch]$Elevated)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSCommandPath
$bundle=Join-Path $root 'CartoRigNative.ofx.bundle'
$script=Join-Path $root 'CartoRig Hybrid Test.lua'
$nativeInstaller=Join-Path $root 'Install-CartoRigNative.ps1'
foreach ($file in @($script,$nativeInstaller,(Join-Path $bundle 'Contents\Win64\CartoRigNative.ofx'))) {
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
$target=Join-Path $utility 'CartoRig Hybrid Test.lua'
$stage=Join-Path $utility ('.CartoRig-Hybrid-Test.'+[guid]::NewGuid().ToString('N')+'.tmp')
try {
  Copy-Item -LiteralPath $script -Destination $stage -Force
  if (-not (Test-Path -LiteralPath $stage -PathType Leaf)) {
    throw 'Could not stage CartoRig test script.'
  }
  Move-Item -LiteralPath $stage -Destination $target -Force
}
finally {
  if (Test-Path -LiteralPath $stage) {Remove-Item -LiteralPath $stage -Force}
}
if ((Get-FileHash -LiteralPath $script -Algorithm SHA256).Hash -ne
    (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash) {
  throw 'CartoRig script did not pass SHA256 verification after installation.'
}
Write-Host ''
Write-Host 'CartoRig installed successfully.'
Write-Host '1. Open DaVinci Resolve Studio 20.'
Write-Host '2. Choose Workspace > Scripts > Utility > CartoRig Hybrid Test.'
Write-Host '3. The script creates only a new disposable CartoRig Fusion QA project.'
Write-Host 'Save any current Resolve work before running the test.'
