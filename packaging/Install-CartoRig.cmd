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
for %%F in (CartoRigBase.fuse CartoRigRegion.fuse CartoRigCamera.fuse) do (
  if not exist "%SOURCE%\fuses\%%F" (
    echo ERROR: Missing required renderer %%F. No files were installed.
    pause & exit /b 1
  )
)
if not exist "%SOURCE%\data\manifest.json" (
  echo ERROR: Offline dataset manifest missing. No files were installed.
  pause & exit /b 1
)
if not exist "%TARGET%" mkdir "%TARGET%"
if not exist "%TARGET%\CartoRig" mkdir "%TARGET%\CartoRig"
copy /Y "%SOURCE%\fusion\CartoRig Scene.lua" "%TARGET%\CartoRig Scene.lua" >nul
copy /Y "%SOURCE%\fusion\CartoRig Host Diagnostics.lua" "%TARGET%\CartoRig Host Diagnostics.lua" >nul
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
)
for %%F in (CartoRigBase.fuse CartoRigRegion.fuse CartoRigCamera.fuse) do (
  if not exist "%SOURCE%\fuses\%%F" (
    echo ERROR: Missing required Fuse %%F. Extract the complete package first.
    pause & exit /b 1
  )
  copy /Y "%SOURCE%\fuses\%%F" "%FUSE_DIR%\%%F" >nul
  if errorlevel 1 (
    echo ERROR: Failed to install %%F.
    pause & exit /b 1
  )
)
echo Installed CartoRig Base Map, Region and Camera Inspector Fuses.
if not exist "%TARGET%\CartoRig\fusion_host.lua" (
  echo Installation incomplete.
  pause & exit /b 1
)
echo Installed to: "%TARGET%"
echo Restart DaVinci Resolve, open a Fusion Composition, then Scripts ^> CartoRig Scene.
echo Logs: %%TEMP%%\CartoRig_Rewrite_v2.log
pause
