@echo off
setlocal
cd /d "%~dp0.."
echo NpcAbilitiesForever - Zauber und beobachtete NPC-Faehigkeiten aktualisieren
echo Es werden wenige Wago-Tabellen als CSV geladen; kein NPC-Komplettabruf.
echo Bei Abbruch erneut starten; geladene Tabellen werden wiederverwendet.
echo.
echo Starte Python ...
where py >nul 2>nul
if not errorlevel 1 (
    py -3 -u Updater\tools\update_database.py %*
) else (
    python -u Updater\tools\update_database.py %*
)
set "updateResult=%errorlevel%"
echo.
if not "%updateResult%"=="0" echo Update fehlgeschlagen. Die konkrete Ursache steht oben; vorhandene Addon-Daten bleiben erhalten.
pause
exit /b %updateResult%
