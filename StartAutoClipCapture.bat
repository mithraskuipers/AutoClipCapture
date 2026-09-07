@echo off
powershell -NoProfile -NoLogo -Command "Get-ChildItem -Path '%~dp0*.ps1' | Unblock-File" >nul 2>&1
powershell -STA -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%~dp0AutoClipCapture.ps1"
pause
