@echo off
powershell -NoProfile -NoLogo -Command "Get-ChildItem -Path '%~dp0*.ps1' | Unblock-File" >nul 2>&1

if /I "%~1"=="EditConfig" (
    powershell -STA -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%~dp0AutoClipCapture.ps1" -EditConfig
) else if /I "%~1"=="Calibrate" (
    powershell -STA -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%~dp0AutoClipCapture.ps1" -Calibrate
) else (
    powershell -STA -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%~dp0AutoClipCapture.ps1"
)
pause
