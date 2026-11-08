@echo off
setlocal EnableExtensions
set "SOURCE=%~dp0.."
set "TARGET=%APPDATA%\Blackmagic Design\DaVinci Resolve\Support\Fusion\Scripts\Comp"
echo CartoRig Rewrite - Preview Installer (not a certified release)
echo.
if not exist "%SOURCE%\src\cartorig\scene.lua" (
  echo Missing source files. Extract the complete package before installing.
  pause & exit /b 1
)
if not exist "%TARGET%" mkdir "%TARGET%"
if not exist "%TARGET%\CartoRig" mkdir "%TARGET%\CartoRig"
copy /Y "%SOURCE%\fusion\CartoRig Scene.lua" "%TARGET%\CartoRig Scene.lua" >nul
xcopy "%SOURCE%\src\cartorig\*" "%TARGET%\CartoRig\" /E /I /Q /Y >nul
if not exist "%TARGET%\CartoRig\data" mkdir "%TARGET%\CartoRig\data"
xcopy "%SOURCE%\data\*" "%TARGET%\CartoRig\data\" /E /I /Q /Y >nul
if exist "%SOURCE%\dist\natural-earth-10m\catalog_index.json" (
  echo Installing complete Natural Earth 10m offline data pack...
  xcopy "%SOURCE%\dist\natural-earth-10m\*" "%TARGET%\CartoRig\data\" /E /I /Q /Y >nul
)
set "FUSE_DIR=%APPDATA%\Blackmagic Design\DaVinci Resolve\Support\Fusion\Fuses"
if not exist "%FUSE_DIR%" mkdir "%FUSE_DIR%"
if exist "%SOURCE%\fuses\CartoRigOpacity.fuse" (
  copy /Y "%SOURCE%\fuses\CartoRigOpacity.fuse" "%FUSE_DIR%\CartoRigOpacity.fuse" >nul
  echo Installed experimental Control/Motion opacity Fuse in Fusion Fuses folder.
)
if not exist "%TARGET%\CartoRig\fusion_host.lua" (
  echo Installation incomplete.
  pause & exit /b 1
)
echo Installed to: "%TARGET%"
echo Restart DaVinci Resolve, open a Fusion Composition, then Scripts ^> CartoRig Scene.
echo Logs: %%TEMP%%\CartoRig_Rewrite_v2.log
pause
