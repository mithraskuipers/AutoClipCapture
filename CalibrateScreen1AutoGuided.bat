@echo off
echo This calibration step is OBSOLETE - AutoClipCapture.ps1 now asks you to
echo position the mouse and click OK automatically right before the SQL
echo pipeline starts (e.g. when you press Ctrl+Shift+M). You shouldn't need
echo to run this anymore.
echo.
choice /C YN /M "Run the old calibration anyway"
if errorlevel 2 exit /b 0
powershell -NoProfile -NoLogo -Command "Unblock-File -Path '%~dp0CalibrateScreen1AutoGuided.ps1'" >nul 2>&1
powershell -STA -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%~dp0CalibrateScreen1AutoGuided.ps1"
