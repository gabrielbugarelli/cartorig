@echo off
setlocal
set "HERE=%~dp0"
set "SOURCE=%HERE%..\fusion\CartoRig Fusion-first POC.lua"
set "TARGET=%APPDATA%\Blackmagic Design\DaVinci Resolve\Support\Fusion\Scripts\Comp"
if not exist "%SOURCE%" (
  echo Missing: "%SOURCE%"
  exit /b 1
)
if not exist "%TARGET%" mkdir "%TARGET%" || exit /b 1
copy /Y "%SOURCE%" "%TARGET%\CartoRig Fusion-first POC.lua" >nul || exit /b 1
echo Installed proof script into: "%TARGET%"
echo Restart DaVinci Resolve, insert a NEW Fusion Composition in Edit, open Fusion,
echo and launch Scripts ^> CartoRig Fusion-first POC.
exit /b 0
