@echo off
setlocal
title CartoRig - Install and Test
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-CartoRig.ps1"
set "code=%errorlevel%"
echo.
if not "%code%"=="0" (
  echo CartoRig installation did not complete. The error is above.
) else (
  echo Installation complete. Start Resolve 20 and open:
  echo Workspace ^> Scripts ^> Utility ^> CartoRig Hybrid Test
)
echo.
pause
exit /b %code%
