@echo off
setlocal EnableExtensions
set "TARGET=%APPDATA%\Blackmagic Design\DaVinci Resolve\Support\Fusion\Scripts\Comp"
set "LOG=%TEMP%\CartoRig_FusionFirst_startup.log"
echo === CartoRig Fusion-first installation diagnostics ===
echo Target: "%TARGET%"
echo.
for %%F in ("CartoRig Fusion-first.lua" "CartoRig\catalog.lua" "CartoRig\graph.lua" "CartoRig\data\ne110m_countries.lua" "CartoRig\data\ne50m_br_states.lua" "CartoRig\data\ne110m_cities.lua") do (
  if exist "%TARGET%\%%~F" (echo OK      %%~F) else (echo MISSING %%~F)
)
echo.
echo === Latest CartoRig startup log ===
if exist "%LOG%" (
  type "%LOG%"
  echo.
  echo To open in Notepad: notepad "%LOG%"
) else (
  echo No startup log found. The installed script may be an older version,
  echo or the entry point has not run. Restart Resolve and try again.
)
echo.
echo Resolve script errors also appear in Workspace ^> Console.
pause
