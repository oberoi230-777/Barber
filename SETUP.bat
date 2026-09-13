@echo off
REM ═══════════════════════════════════════════════════════════════════════
REM  PORTABLE RETRO GAMING SUITE - SETUP
REM  Usage: SETUP.bat [-Unattended] [-IncludeSampleRoms] [-QuickSetup] ...
REM  All arguments are forwarded to SETUP.ps1. Example for zero-click setup:
REM      SETUP.bat -Unattended -IncludeSampleRoms
REM ═══════════════════════════════════════════════════════════════════════

title Retro Gaming Setup
cd /d "%~dp0"

REM Check if running as administrator (recommended, not required)
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo +---------------------------------------------------------------+
    echo ^|  Administrator Rights Recommended                             ^|
    echo +---------------------------------------------------------------+
    echo.
    echo Some features work better with administrator rights.
    echo Right-click this file and select "Run as administrator"
    echo.
    echo Continuing in 5 seconds... press Ctrl+C to cancel.
    timeout /t 5 /nobreak >nul
)

echo.
echo +---------------------------------------------------------------+
echo ^|                                                               ^|
echo ^|      PORTABLE RETRO GAMING SUITE SETUP                         ^|
echo ^|                                                               ^|
echo +---------------------------------------------------------------+
echo.
echo Starting setup...
echo.

REM Prefer Windows PowerShell 5.1 (most compatible), fall back to pwsh 7+
where powershell.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "SETUP.ps1" %*
    goto SETUP_DONE
)

where pwsh.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "SETUP.ps1" %*
    goto SETUP_DONE
)

echo PowerShell was not found. This suite requires Windows PowerShell.
pause
exit /b 1

:SETUP_DONE
if %ERRORLEVEL% neq 0 (
    echo.
    echo Setup encountered an error. Check the log in the Logs\ folder.
    pause
    exit /b 1
)

exit /b 0
