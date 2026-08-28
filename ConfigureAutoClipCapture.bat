@echo off
powershell -NoProfile -NoLogo -Command "Unblock-File -Path '%~dp0AutoClipCaptureConfigGUI.ps1'" >nul 2>&1
powershell -STA -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%~dp0AutoClipCaptureConfigGUI.ps1"
