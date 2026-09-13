@echo off
REM ═══════════════════════════════════════════════════════════════════════
REM  PORTABLE RETRO GAMING SUITE - LAUNCHER
REM  Usage: LAUNCH.bat [--text] [--check] [--scan] [--launch NES/Game] ...
REM  All arguments are forwarded to launcher.py.
REM ═══════════════════════════════════════════════════════════════════════

title Retro Gaming Launcher

REM Resolve paths relative to this script so the folder can live anywhere
set "ROOT=%~dp0"
set "LAUNCHER_PATH=%ROOT%Launcher"

if not exist "%LAUNCHER_PATH%\launcher.py" (
    cls
    echo.
    echo Launcher script not found in "%LAUNCHER_PATH%".
    echo Make sure the RetroGaming folder was copied completely.
    echo.
    pause
    goto END
)

REM Warn (but continue) when RetroArch is missing - the launcher shows guidance.
if not exist "%ROOT%Emulators\RetroArch\retroarch.exe" (
    echo.
    echo +---------------------------------------------------------------+
    echo ^|  RetroArch is not installed yet.                              ^|
    echo ^|  Run SETUP.bat first for automatic installation, or           ^|
    echo ^|  continue to browse (games will not launch until setup).     ^|
    echo +---------------------------------------------------------------+
    echo.
    timeout /t 4 /nobreak >nul
)

cd /d "%LAUNCHER_PATH%"

REM Try to find Python (arguments forwarded to launcher.py)
where python >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    python launcher.py %*
    goto END
)

where python3 >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    python3 launcher.py %*
    goto END
)

where py >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    py launcher.py %*
    goto END
)

REM Python not found
cls
echo.
echo +---------------------------------------------------------------+
echo ^|  Python Not Found                                              ^|
echo +---------------------------------------------------------------+
echo.
echo Python is required to run the game launcher.
echo.
echo Option 1 (automatic): run SETUP.bat - it can install Python for you.
echo Option 2 (manual): install from https://www.python.org/downloads/
echo   During installation, make sure to check:
echo     [x] "Add Python to PATH"
echo.
echo After installing Python, run SETUP.bat again to complete setup.
echo.
pause
goto END

:END
