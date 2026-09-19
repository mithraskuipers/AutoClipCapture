@echo off
setlocal EnableExtensions
title AutoClipCapture

rem ------------------------------------------------------------------
rem  AutoClipCapture launcher
rem
rem  Double-click for an interactive menu: start, calibrate or edit.
rem  These shortcuts still work and skip the menu entirely:
rem      StartAutoClipCapture.bat Start
rem      StartAutoClipCapture.bat Calibrate
rem      StartAutoClipCapture.bat EditConfig
rem ------------------------------------------------------------------

rem Downloaded .ps1 files get blocked by Windows - clear that first.
powershell -NoProfile -NoLogo -Command "Get-ChildItem -Path '%~dp0*.ps1' | Unblock-File" >nul 2>&1

set "SCRIPT=%~dp0AutoClipCapture.ps1"
set "ACC_CFG=%~dp0AutoClipCaptureConfig.json"
set "DIRECT="

if /I "%~1"=="Start" (
    set "DIRECT=1"
    goto :start
)
if /I "%~1"=="Calibrate" (
    set "DIRECT=1"
    goto :calibrate
)
if /I "%~1"=="EditConfig" (
    set "DIRECT=1"
    goto :edit
)

:menu
cls
echo ==================================================
echo    AutoClipCapture
echo ==================================================
echo.

rem Work out the calibration state. Exit code of the check below:
rem   0 = config found and every pipeline is calibrated
rem   1 = no AutoClipCaptureConfig.json yet
rem   2 = config found, but at least one pipeline is not calibrated
rem   3 = config found, but it could not be read
rem The test mirrors the one AutoClipCapture.ps1 itself uses at startup.
powershell -NoProfile -NoLogo -Command "$p = $env:ACC_CFG; if (-not (Test-Path -LiteralPath $p)) { exit 1 }; $bad = 0; try { $c = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json -ErrorAction Stop; foreach ($pl in @($c.Pipelines)) { if ($null -eq $pl) { continue }; $s = $pl.Screen1Select; if ($null -eq $s -or [double]$s.CharWidthPx -le 0 -or [double]$s.CharHeightPx -le 0 -or $null -eq $s.FirstDataRowLineIndex -or $null -eq $s.SelectionColumnIndex) { $bad++ } } } catch { exit 3 }; if ($bad -gt 0) { exit 2 }; exit 0"
set "CALSTATE=%errorlevel%"

set "REC2="
if "%CALSTATE%"=="0" echo    Status: CALIBRATED - config found, all pipelines are calibrated.
if "%CALSTATE%"=="1" echo    Status: NOT CALIBRATED - no AutoClipCaptureConfig.json found yet.
if "%CALSTATE%"=="2" echo    Status: NOT CALIBRATED - at least one pipeline still needs calibration.
if "%CALSTATE%"=="3" echo    Status: WARNING - AutoClipCaptureConfig.json could not be read.
if "%CALSTATE%"=="2" set "REC2=   (recommended)"

echo.
echo    What would you like to do?
echo.
echo      1  Start AutoClipCapture
echo      2  Calibrate%REC2%
echo      3  Edit settings
echo      4  Quit
echo.
choice /C 1234 /N /M "   Enter a number (1-4): "

if errorlevel 4 goto :quit
if errorlevel 3 goto :edit
if errorlevel 2 goto :calibrate
goto :start

:start
cls
echo Starting AutoClipCapture...
echo.
powershell -STA -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%SCRIPT%"
goto :end

:calibrate
cls
echo Starting calibration...
echo.
powershell -STA -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%SCRIPT%" -Calibrate
if defined DIRECT goto :end
goto :menu

:edit
cls
echo Opening the settings editor - close it to return to the menu...
echo.
powershell -STA -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%SCRIPT%" -EditConfig
if defined DIRECT goto :end
goto :menu

:end
pause
endlocal
exit /b

:quit
endlocal
exit /b
