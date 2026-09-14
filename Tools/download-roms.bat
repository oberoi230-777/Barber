@echo off
REM ROM Download Tool v3 - catalog-driven legal free/homebrew games
REM Usage:
REM   download-roms.bat
REM   download-roms.bat -System All
REM   download-roms.bat -System Everything -MaxFiles 5
REM   download-roms.bat -System NES -Overwrite
REM   download-roms.bat -Query "tic80 cart" -ListOnly
title Free Games Download Tool

cd /d "%~dp0"
where powershell.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "download-roms.ps1" %*
    exit /b %ERRORLEVEL%
)
where pwsh.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "download-roms.ps1" %*
    exit /b %ERRORLEVEL%
)
echo PowerShell was not found.
pause
exit /b 1
