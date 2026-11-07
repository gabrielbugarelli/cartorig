# NE-SOURCE-02: release workstation only, no paid GitHub infrastructure.
# Acquire ALL available official sources even when one publisher ZIP is 404.
# Never certifies Natural Earth Complete; optional output is experimental only.
# Examples:
#   .\packaging\Acquire-NaturalEarth.ps1 -Workspace 'D:\CartoRigBuild' -AllowNetwork -SkipReviewedUnavailable -MaxDownloads 12
#   .\packaging\Acquire-NaturalEarth.ps1 -Workspace 'D:\CartoRigBuild' -AllowNetwork -SkipReviewedUnavailable -BuildExperimental -Output 'D:\CartoRigExperimental'
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Workspace,
  [switch]$AllowNetwork,
  [switch]$SkipReviewedUnavailable,
  [switch]$BuildExperimental,
  [string]$Output,
  [ValidateRange(0,100)][int]$MaxDownloads=12,
  [string]$Python='python'
)

$ErrorActionPreference='Stop'
if (-not (Get-Command $Python -ErrorAction SilentlyContinue)) {
  throw 'Python interpreter was not found. Install Python 3.12 and select -Python.'
}
if ($BuildExperimental -and (-not $SkipReviewedUnavailable -or
                              [string]::IsNullOrWhiteSpace($Output))) {
  throw 'Experimental pack requires -SkipReviewedUnavailable and an explicit -Output path.'
}
$repository=Split-Path -Parent $PSScriptRoot
Push-Location $repository
try {
  $module=if ($BuildExperimental) {
    'tools.natural_earth.build_experimental'
  } else {
    'tools.natural_earth.acquire_available'
  }
  $arguments=@('-m',$module,'--workspace',$Workspace,
               '--max-downloads',([string]$MaxDownloads))
  if ($AllowNetwork) { $arguments+='--allow-network' }
  if ($BuildExperimental) {
    $arguments+=@('--output',$Output)
  } elseif ($SkipReviewedUnavailable) {
    $arguments+='--skip-reviewed-unavailable'
  }
  & $Python @arguments
  $code=$LASTEXITCODE
  if ($code -eq 2) {
    Write-Warning 'Acquisition is incomplete; rerun this command to resume verified ZIPs. No pack was certified.'
    return
  }
  if ($code -ne 0) {
    throw "Natural Earth acquisition or experimental build failed (exit $code)."
  }
  if ($BuildExperimental) {
    Write-Warning 'EXPERIMENTAL_INCOMPLETE: offline QA use only; never distribute as Natural Earth Complete.'
  } else {
    Write-Host 'Acquisition phase inspected. The 52-source COMPLETE release gate is unchanged.'
  }
}
finally {
  Pop-Location
}
