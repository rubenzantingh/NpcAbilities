@echo off
setlocal
cd /d "%~dp0.."
echo NpcAbilitiesForever - Update spells and observed NPC abilities
echo Downloads Wago tables as CSV; does not crawl all NPC pages.
echo Run again to resume after cancellation; downloaded tables are reused.
echo.
echo Starting Python ...
where py >nul 2>nul
if not errorlevel 1 (
    py -3 -u Updater\tools\update_database.py %*
) else (
    python -u Updater\tools\update_database.py %*
)
set "updateResult=%errorlevel%"
echo.
if not "%updateResult%"=="0" echo Update failed. See the error above; existing addon data is preserved.
pause
exit /b %updateResult%
