@echo off
REM ROM Download Tool - Batch launcher
title ROM Download Tool

cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "download-roms.ps1"
exit /b %ERRORLEVEL%
