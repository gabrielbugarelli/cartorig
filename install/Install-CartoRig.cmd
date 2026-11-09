@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-CartoRig.ps1"
if errorlevel 1 (
  echo.
  echo CartoRig installation failed. Check the message above.
  pause
  exit /b 1
)
echo.
echo CartoRig files copied. Restart DaVinci Resolve Studio 20.
pause
exit /b 0
