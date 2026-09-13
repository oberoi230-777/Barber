@echo off
REM ROM Organization Tool - Batch launcher (was missing in v1.x)
REM Usage: organize-roms.bat -SourceFolder "C:\Downloads\ROMs" [-MoveFiles] [-DryRun]
title ROM Organization Tool

cd /d "%~dp0"
where powershell.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "organize-roms.ps1" %*
    exit /b %ERRORLEVEL%
)
where pwsh.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "organize-roms.ps1" %*
    exit /b %ERRORLEVEL%
)
echo PowerShell was not found.
pause
exit /b 1
