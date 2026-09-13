@echo off
REM Diagnostics + Auto-Repair Tool - Batch launcher
REM Usage: diagnose.bat [-Fix] [-Json] [-NonInteractive]
title Retro Gaming Diagnostics

cd /d "%~dp0"
where powershell.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "diagnose.ps1" %*
    exit /b %ERRORLEVEL%
)
where pwsh.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "diagnose.ps1" %*
    exit /b %ERRORLEVEL%
)
echo PowerShell was not found.
pause
exit /b 1
