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
if not exist "%TARGET%\CartoRig" mkdir "%TARGET%\CartoRig" || exit /b 1
if not exist "%TARGET%\CartoRig\data" mkdir "%TARGET%\CartoRig\data" || exit /b 1
copy /Y "%SOURCE%\CartoRig Fusion-first.lua" "%TARGET%\CartoRig Fusion-first.lua" >nul || exit /b 1
copy /Y "%SOURCE%\CartoRig\*.lua" "%TARGET%\CartoRig\" >nul || exit /b 1
copy /Y "%SOURCE%\CartoRig\data\*.lua" "%TARGET%\CartoRig\data\" >nul || exit /b 1
echo.
echo CartoRig Fusion-first installed (offline Lua + Natural Earth).
echo Restart Resolve, insert an empty Fusion Composition on Edit, open Fusion,
echo and start CartoRig Fusion-first in the Scripts menu.
exit /b 0
