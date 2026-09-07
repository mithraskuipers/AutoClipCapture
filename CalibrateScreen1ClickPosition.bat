@echo off
powershell -NoProfile -NoLogo -Command "Unblock-File -Path '%~dp0CalibrateScreen1ClickPosition.ps1'" >nul 2>&1
powershell -STA -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%~dp0CalibrateScreen1ClickPosition.ps1"
pause
