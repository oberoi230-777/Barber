@echo off
REM Controller Test Tool - Batch launcher
title Controller Test

cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "test-controller.ps1"
exit /b %ERRORLEVEL%
