@echo off
REM ═══════════════════════════════════════════════════════════════════════
REM  PORTABLE RETRO GAMING SUITE - SETUP
REM ═══════════════════════════════════════════════════════════════════════

title Retro Gaming Setup

REM Check if running as administrator
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo ╔═══════════════════════════════════════════════════════════╗
    echo ║  Administrator Rights Recommended                         ║
    echo ╚═══════════════════════════════════════════════════════════╝
    echo.
    echo Some features work better with administrator rights.
    echo Right-click this file and select "Run as administrator"
    echo.
    echo Press any key to continue anyway, or close this window...
    pause >nul
)

cd /d "%~dp0"

echo.
echo ╔═══════════════════════════════════════════════════════════════╗
echo ║                                                               ║
echo ║      🎮  PORTABLE RETRO GAMING SUITE SETUP  🎮              ║
echo ║                                                               ║
echo ╚═══════════════════════════════════════════════════════════════╝
echo.
echo Starting setup...
echo.

REM Run PowerShell setup script
powershell.exe -ExecutionPolicy Bypass -File "SETUP.ps1"

if %ERRORLEVEL% neq 0 (
    echo.
    echo Setup encountered an error.
    pause
    exit /b 1
)

exit /b 0
