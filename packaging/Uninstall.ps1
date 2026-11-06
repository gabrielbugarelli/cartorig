[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param()
$ErrorActionPreference='Stop'
if (Get-Process -Name 'Resolve' -ErrorAction SilentlyContinue) { throw 'Close DaVinci Resolve before uninstalling' }
$dest = Join-Path ${env:ProgramFiles} 'Common Files\OFX\Plugins\CartoRigNative.ofx.bundle'
if (-not (Test-Path -LiteralPath $dest)) { Write-Host 'CartoRig Native is not installed'; return }
if ($PSCmdlet.ShouldProcess($dest,'Remove only CartoRig Native OFX bundle')) {
  Remove-Item -LiteralPath $dest -Recurse -Force
  Write-Host 'Removed CartoRig Native binary bundle; external scene files were preserved.'
}
