@echo off
REM ═══════════════════════════════════════════════════════════════════════
REM  PORTABLE RETRO GAMING SUITE - LAUNCHER
REM ═══════════════════════════════════════════════════════════════════════

title Retro Gaming Launcher

REM Resolve paths relative to this script so the folder can live anywhere
set "ROOT=%~dp0"
set "LAUNCHER_PATH=%ROOT%Launcher"

REM Change to launcher directory
cd /d "%LAUNCHER_PATH%"

if not exist "launcher.py" (
    cls
    echo.
    echo Launcher script not found in "%LAUNCHER_PATH%".
    echo Make sure the RetroGaming folder was copied completely.
    echo.
    pause
    goto END
)

REM Try to find Python
where python >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    python launcher.py
    goto END
)

where python3 >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    python3 launcher.py
    goto END
)

where py >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    py launcher.py
    goto END
)

REM Python not found
cls
echo.
echo ╔═══════════════════════════════════════════════════════════════╗
echo ║  ❌  Python Not Found                                        ║
echo ╚═══════════════════════════════════════════════════════════════╝
echo.
echo Python is required to run the game launcher.
echo.
echo Please install Python from: https://www.python.org/downloads/
echo.
echo During installation, make sure to check:
echo   ✓ "Add Python to PATH"
echo.
echo After installing Python, run SETUP.bat again to complete setup.
echo.
pause
goto END

:END
