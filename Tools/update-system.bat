@echo off
REM System Update Tool - Batch launcher
title System Update Tool

cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "update-system.ps1"
exit /b %ERRORLEVEL%
