@echo off
setlocal EnableExtensions
set "TARGET=%APPDATA%\Blackmagic Design\DaVinci Resolve\Support\Fusion\Scripts\Comp"
echo This removes only the CartoRig rewrite files, not your projects.
choice /M "Uninstall CartoRig Rewrite Preview"
if errorlevel 2 exit /b 0
if exist "%TARGET%\CartoRig Scene.lua" del "%TARGET%\CartoRig Scene.lua"
if exist "%TARGET%\CartoRig" rmdir /S /Q "%TARGET%\CartoRig"
echo CartoRig rewrite installation removed. Existing project files were not deleted.
pause
