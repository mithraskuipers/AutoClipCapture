@echo off
powershell -NoProfile -NoLogo -Command "Unblock-File -Path '%~dp0CalibrateScreen1AutoGuided.ps1'" >nul 2>&1
powershell -STA -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%~dp0CalibrateScreen1AutoGuided.ps1"
