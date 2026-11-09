# Tests the real installer preflight on Windows PowerShell 5.1.
# This fixture never invokes an elevated install or writes into Resolve paths.
$ErrorActionPreference = 'Stop'
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('CartoRig-Installer-Test-' + [guid]::NewGuid().ToString('N'))
try {
    $data = Join-Path $root 'CartoRigFusion.ofx.bundle\Contents\Resources\data'
    $native = Join-Path $root 'CartoRigFusion.ofx.bundle\Contents\Win64'
    $scripts = Join-Path $root 'Fusion\Scripts\Comp'
    $support = Join-Path $scripts 'CartoRigSupport'
    New-Item -ItemType Directory -Force -Path $data,$native,$support | Out-Null
    Copy-Item -LiteralPath 'install\Install-CartoRig.ps1' -Destination (Join-Path $root 'Install-CartoRig.ps1')
    Set-Content -LiteralPath (Join-Path $native 'CartoRigFusion.ofx') -Value 'dummy binary' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $scripts 'CartoRig Scene.lua') -Value '-- fixture' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $support 'scene.lua') -Value '-- fixture' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $support 'scene_tree.lua') -Value '-- fixture' -Encoding ASCII
    $geometry = Join-Path $data 'geometry.crgeo'
    $catalog = Join-Path $data 'catalog.tsv'
    Set-Content -LiteralPath $geometry -Value 'fixture geometry' -Encoding ASCII
    Set-Content -LiteralPath $catalog -Value 'fixture catalog' -Encoding ASCII
    function Write-Manifest([bool] $offline) {
        $value = @{
            format = 'CRG1'
            network_required_by_runtime = -not $offline
            geometry_sha256 = (Get-FileHash -LiteralPath $geometry -Algorithm SHA256).Hash.ToLowerInvariant()
            catalog_sha256 = (Get-FileHash -LiteralPath $catalog -Algorithm SHA256).Hash.ToLowerInvariant()
            features = 1
        } | ConvertTo-Json -Depth 4
        [System.IO.File]::WriteAllText((Join-Path $data 'manifest.json'),$value)
    }
    function Run-Preflight {
        # Failing fixtures intentionally produce stderr. Windows PowerShell 5.1
        # turns redirected native stderr into NativeCommandError when Stop is
        # enabled, so capture the child exit code instead of piping stderr.
        $installer = Join-Path $root 'Install-CartoRig.ps1'
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $installer + '" -VerifyPackageOnly'
        $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments `
            -Wait -PassThru -NoNewWindow
        return [int] $process.ExitCode
    }
    Write-Manifest $true
    if ((Run-Preflight) -ne 0) { throw 'Valid offline manifest must pass.' }

    # Tamper with bytes but not the publisher SHA256: installer must fail.
    Add-Content -LiteralPath $catalog -Value 'tampered' -Encoding ASCII
    if ((Run-Preflight) -eq 0) { throw 'Tampered offline data must fail.' }

    Write-Manifest $true
    if ((Run-Preflight) -ne 0) { throw 'Rehashed fixture must pass again.' }

    # Runtime network dependency must fail, regardless of matching hashes.
    Write-Manifest $false
    if ((Run-Preflight) -eq 0) { throw 'Online-dependent package must fail.' }

    Write-Manifest $true
    Remove-Item -LiteralPath (Join-Path $support 'scene.lua') -Force
    if ((Run-Preflight) -eq 0) { throw 'Incomplete Fusion payload must fail.' }

    Write-Host 'PASS installer: valid, tampered, network-dependent, missing payload.'
} finally {
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}
