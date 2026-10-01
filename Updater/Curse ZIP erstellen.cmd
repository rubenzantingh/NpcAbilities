@echo off
setlocal
cd /d "%~dp0.."
where py >nul 2>nul
if not errorlevel 1 (
    py -3 Updater\build_release.py %*
) else (
    python Updater\build_release.py %*
)
set "buildResult=%errorlevel%"
echo.
if not "%buildResult%"=="0" echo ZIP-Erstellung fehlgeschlagen. Python 3.10+ muss installiert sein.
pause
exit /b %buildResult%
