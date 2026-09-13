@echo off
REM =======================================================================
REM  PORTABLE RETRO GAMING SUITE - LAUNCHER
REM  Usage: LAUNCH.bat [--text] [--check] [--scan] [--launch NES/Game] ...
REM  All arguments are forwarded to launcher.py.
REM
REM  This script never closes silently on failure: if anything goes wrong
REM  you get the error, the Python version, the last log lines, and a pause.
REM =======================================================================

setlocal
title Retro Gaming Launcher
set "EXITCODE=0"

REM Resolve paths relative to this script so the folder can live anywhere
set "ROOT=%~dp0"
set "LAUNCHER_PATH=%ROOT%Launcher"
set "LOG_FILE=%ROOT%Logs\launcher.log"

if not exist "%LAUNCHER_PATH%\launcher.py" (
    echo.
    echo Launcher script not found in "%LAUNCHER_PATH%".
    echo Make sure the RetroGaming folder was copied completely.
    echo.
    set "EXITCODE=1"
    pause
    goto END
)

cd /d "%LAUNCHER_PATH%" 2>nul
if errorlevel 1 (
    echo.
    echo Cannot access "%LAUNCHER_PATH%".
    echo Check the folder permissions and try again.
    echo.
    set "EXITCODE=1"
    pause
    goto END
)

REM Warn (but continue) when RetroArch is missing - the launcher shows guidance.
if not exist "%ROOT%Emulators\RetroArch\retroarch.exe" (
    echo.
    echo +---------------------------------------------------------------+
    echo ^|  RetroArch is not installed yet.                              ^|
    echo ^|  Run SETUP.bat first for automatic installation, or           ^|
    echo ^|  continue to browse ^(games will not launch until setup^).    ^|
    echo +---------------------------------------------------------------+
    echo.
    timeout /t 4 /nobreak >nul
)

REM Find a WORKING Python. Every candidate must actually run (--version must
REM exit 0), which automatically skips the broken Windows Store stub that
REM `where` alone would accept.
set "PYCMD="
for %%P in (python python3 py) do (
    if not defined PYCMD (
        where %%P >nul 2>&1
        if not errorlevel 1 (
            %%P --version >nul 2>&1
            if not errorlevel 1 set "PYCMD=%%P"
        )
    )
)

if not defined PYCMD (
    echo.
    echo +---------------------------------------------------------------+
    echo ^|  Python Not Found                                             ^|
    echo +---------------------------------------------------------------+
    echo.
    echo Python is required to run the game launcher.
    echo.
    echo Option 1 ^(automatic^): run SETUP.bat - it can install Python for you.
    echo Option 2 ^(manual^): install from https://www.python.org/downloads/
    echo   During installation, make sure to check:
    echo     [x] "Add Python to PATH^)"
    echo.
    echo NOTE: if the Microsoft Store opens when you type python, you only
    echo have the Store stub, not real Python. Either install Python from
    echo python.org, or disable the stub here:
    echo   Settings - Apps - Advanced app settings - App execution aliases
    echo.
    echo After installing Python, run SETUP.bat again to complete setup.
    echo.
    set "EXITCODE=1"
    pause
    goto END
)

echo Starting Retro Gaming Launcher ^(%PYCMD%^) ...
%PYCMD% launcher.py %*
set "EXITCODE=%ERRORLEVEL%"
if "%EXITCODE%"=="0" goto END

echo.
echo +---------------------------------------------------------------+
echo ^|  The launcher stopped with an error ^(code %EXITCODE%^).       ^|
echo +---------------------------------------------------------------+
echo.
echo Python used:
%PYCMD% --version
echo.
echo Last 20 lines of Logs\launcher.log:
where powershell.exe >nul 2>&1
if errorlevel 1 goto SHOWLOGPATH
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '%LOG_FILE%' -Tail 20"
goto AFTERLOG
:SHOWLOGPATH
echo (Could not print the log automatically - open this file manually:)
:AFTERLOG
echo %LOG_FILE%
echo.
echo If this keeps happening, run Tools\diagnose.bat for an automatic fix.
echo.
pause
goto END

:END
endlocal & exit /b %EXITCODE%
