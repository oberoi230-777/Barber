@echo off
REM Controller Test Tool - Batch launcher
REM Usage: test-controller.bat [-TextOnly] [-Seconds 10]
title Controller Test

cd /d "%~dp0"
where powershell.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "test-controller.ps1" %*
    exit /b %ERRORLEVEL%
)
where pwsh.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "test-controller.ps1" %*
    exit /b %ERRORLEVEL%
)
echo PowerShell was not found.
pause
exit /b 1
