@echo off
REM System Update Tool - Batch launcher
REM Usage: update-system.bat [-Action All] [-NonInteractive]
title System Update Tool

cd /d "%~dp0"
where powershell.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "update-system.ps1" %*
    exit /b %ERRORLEVEL%
)
where pwsh.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "update-system.ps1" %*
    exit /b %ERRORLEVEL%
)
echo PowerShell was not found.
pause
exit /b 1
