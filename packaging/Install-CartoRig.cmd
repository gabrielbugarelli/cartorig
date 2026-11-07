@echo off
setlocal EnableExtensions
set "ROOT=%~dp0.."
set "SOURCE=%ROOT%\fusion"
set "TARGET=%APPDATA%\Blackmagic Design\DaVinci Resolve\Support\Fusion\Scripts\Comp"
if not exist "%SOURCE%\CartoRig Fusion-first.lua" (
  echo ERROR: CartoRig source missing. Unzip the complete package first.
  exit /b 1
)
if not exist "%SOURCE%\CartoRig\data\ne110m_countries.lua" (
  echo ERROR: CartoRig Natural Earth data missing.
  exit /b 1
)
for %%F in ("CartoRig\catalog.lua" "CartoRig\graph.lua" "CartoRig\data\ne50m_br_states.lua" "CartoRig\data\ne110m_cities.lua") do (
  if not exist "%SOURCE%\%%~F" (
    echo ERROR: Required source not found: %SOURCE%\%%~F
    echo Download the complete GitHub branch ZIP, not an older partial package.
    pause
    exit /b 1
  )
)
if not exist "%TARGET%\CartoRig" mkdir "%TARGET%\CartoRig" || exit /b 1
if not exist "%TARGET%\CartoRig\data" mkdir "%TARGET%\CartoRig\data" || exit /b 1
copy /Y "%SOURCE%\CartoRig Fusion-first.lua" "%TARGET%\CartoRig Fusion-first.lua" >nul || exit /b 1
copy /Y "%SOURCE%\CartoRig\*.lua" "%TARGET%\CartoRig\" >nul || exit /b 1
copy /Y "%SOURCE%\CartoRig\data\*.lua" "%TARGET%\CartoRig\data\" >nul || exit /b 1
echo.
echo CartoRig Fusion-first v0.2.1 installed (offline Lua + Natural Earth).
echo Installed to: "%TARGET%"
echo Startup log: "%TEMP%\CartoRig_FusionFirst_startup.log"
echo If script fails: run packaging\Diagnose-CartoRig.cmd and open Workspace ^> Console.
echo Restart Resolve, insert an empty Fusion Composition on Edit, open Fusion,
echo and start CartoRig Fusion-first in the Scripts menu.
exit /b 0
