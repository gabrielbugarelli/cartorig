# Exercises the offline Natural Earth installer on Windows without network.
$ErrorActionPreference='Stop'
$root=Join-Path $env:TEMP ("cartorig-pack-ci-"+[guid]::NewGuid().ToString('N'))
$source=Join-Path $root 'source'
$destination=Join-Path $root 'installed'
$script=Join-Path $PSScriptRoot '..\packaging\Install-DataPack.ps1'
try {
  python tests/create_pack_fixture.py $source
  if ($LASTEXITCODE -ne 0) { throw 'Pack fixture failed' }
  $rejected=$false
  try {
    & $script -SourceRoot $source -Destination $destination -Confirm:$false
  } catch { $rejected=$true }
  if (-not $rejected) { throw 'Incomplete pack installed without explicit opt-in' }
  & $script -SourceRoot $source -Destination $destination -AllowIncomplete -Confirm:$false
  $installedManifest=Join-Path $destination 'pack.json'
  if (-not (Test-Path -LiteralPath $installedManifest)) {
    throw 'Data installer did not deploy the verified pack'
  }
  & $script -SourceRoot $source -Destination $destination -AllowIncomplete -Upgrade -Confirm:$false
  $target=Join-Path $source 'vector\catalog.sqlite'
  [IO.File]::AppendAllText($target,'TAMPERED')
  $rejected=$false
  try {
    & $script -SourceRoot $source -Destination $destination -AllowIncomplete -Upgrade -Confirm:$false
  } catch { $rejected=$true }
  if (-not $rejected) { throw 'Tampered data was accepted' }
  if (-not (Test-Path -LiteralPath $installedManifest)) {
    throw 'Previously installed valid pack was destroyed by failed upgrade'
  }
  Write-Host 'PASS: unsigned/incomplete guard, offline install, verified upgrade, tamper rejection'
} finally {
  if (Test-Path -LiteralPath $root) {
    Remove-Item -LiteralPath $root -Recurse -Force
  }
}
