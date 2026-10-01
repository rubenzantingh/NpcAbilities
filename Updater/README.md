# Forever-Datenbank per Doppelklick aktualisieren

**Automatisches Lernen im Spiel:** Das Addon ergänzt in Forever neue NPC-Zauber bereits live und zeigt sie sofort an. Dafür sind weder dieser Updater noch `/combatlog` erforderlich. Die Beobachtungen liegen separat in WoWs `NpcAbilitiesLearnedData`-SavedVariables und bleiben bei Datenbank-Updates erhalten. Dieser Updater aktualisiert den ausgelieferten Zauberkatalog und kann zusätzlich vorhandene Logdateien importieren; er liest den Lernspeicher nicht ein. Details: [Addon-README](../README.md#fähigkeiten-direkt-im-spiel-lernen-forever).

`Updater/Datenbank aktualisieren.cmd` doppelklicken. Python 3.10 oder neuer ist erforderlich, zusätzliche Pakete nicht. Anschließend im Spiel `/reload` ausführen. Wenn das Projekt nicht im installierten Addon-Ordner liegt, die aktualisierten Addon-Dateien dorthin kopieren.

Das Fenster zeigt jeden Arbeitsschritt sowie Cache-Zugriffe und Download-Adressen an. Während einer Wago-Anfrage erscheinen alle fünf Sekunden die bisherige Wartezeit und die empfangene Datenmenge. Jede Anfrage hat ein Gesamtzeitlimit von 120 Sekunden, einschließlich Verbindungsaufbau und Übertragung. Bei einem Timeout bleiben die vorhandenen Addon-Daten erhalten; später erneut starten. Das Zeitlimit lässt sich bei Bedarf mit `--timeout 180` ändern. Ein zunächst unveränderter Zähler von `0 KiB` bedeutet, dass noch auf die Verbindung oder Antwort gewartet wird.

Zur Laufzeitdiagnose im Spiel `/nabdebug` eingeben. Das Fenster zeigt empfangene Zaubereinträge und erklärt, warum sie gelernt oder verworfen wurden. Mit `/nabdebug clear` das Protokoll leeren. Details stehen in der [Addon-README](../README.md#fähigkeiten-direkt-im-spiel-lernen-forever).

Der Standardlauf lädt von [Wago Tools](https://wago.tools/) genau den neuesten verfügbaren **Forever-Build 1.60.x** und daraus die Tabellen `SpellName` und `Spell` für alle unterstützten Sprachen: Englisch, Deutsch, Spanisch, Französisch, Portugiesisch, Russisch, Koreanisch und Chinesisch. Das sind normalerweise **17 HTTP-Anfragen** (ein Build-Index und je zwei CSV-Dateien für acht Sprachen), keine Einzelabrufe aller NPCs oder Zauber. Die Tabellen werden 24 Stunden zwischengespeichert. Ein Lauf mit `--refresh` lädt sie erneut. Ein HTTP 403/429 oder ein unvollständiger Export bricht ab, ohne die Addon-Daten zu ersetzen. Wago veröffentlicht für diesen CSV-Export derzeit kein festes Abrufkontingent; Erreichbarkeit und Nutzungsregeln können sich ändern.

Der Updater importiert den **vollständigen Zauberkatalog** des Forever-Builds, auch IDs, die noch keinem bekannten NPC zugeordnet sind, und legt Namen und lesbare Beschreibungen für jede unterstützte Sprache im `abilities`-Overlay in `Database/forever.lua` ab. So sind beispielsweise beide Wago-IDs von „Windstachel“ (1248802 und 1301968) nach dem Lauf auch auf Spanisch und in den übrigen Sprachen lokalisiert. Die Dateien unter `Database/Abilities` bleiben die unveränderten Basisdaten des ursprünglichen Addons; neue Forever-Übersetzungen liegen im dafür vorgesehenen Forever-Overlay. Das macht den Zauber noch nicht automatisch im NPC-Tooltip sichtbar: Dafür muss die passende ID dem NPC zugeordnet sein. Wago liefert viele Beschreibungen als Vorlagen mit Platzhaltern wie `$d` und `$t1`. Solche Vorlagen oder beschädigte Texte werden **nicht** angezeigt; die bisherigen Beschreibungen aus der Addon-Datenbank bleiben als Rückfall erhalten. Die Angaben zu Mechanik, Reichweite, Zauberzeit, Abklingzeit und Bannart bleiben ebenfalls erhalten, weil die beiden Wago-Tabellen dafür keine fertig lokalisierten Tooltip-Texte liefern.

## NPCs und entfernte Fähigkeiten

Client-Tabellen enthalten keine vollständige Liste, welcher NPC welche Fähigkeit benutzt. Deshalb bleiben alle bisherigen NPC-Zuordnungen zunächst bestehen. **Für automatische Ergänzungen** kann der Updater das von Forever geschriebene Kampfprotokoll auswerten: Bei `SPELL_CAST_START` und `SPELL_CAST_SUCCESS` stehen NPC-ID und Zauber-ID zusammen. So können neue NPCs und beobachtete Fähigkeiten beim nächsten Doppelklick erscheinen, ohne Wowhead einzeln abzufragen. Das gilt nur für NPCs und Zauber, die im Protokoll tatsächlich vorkommen. Ein nicht beobachteter Zauber gilt **nicht** als entfernt; für vollständige Korrekturen und entfernte Fähigkeiten dient weiterhin [`Database/npc_overrides.json`](../Database/npc_overrides.json). Beispiel:

```json
{
  "npcs": {
    "270589": {
      "name": "Beispiel-NPC",
      "spell_ids": [11918, 12345],
      "source": "Beobachtung im Spiel am 2026-09-29"
    },
    "30": {
      "name": "Waldspinne",
      "spell_ids": [],
      "source": "Im Spiel überprüft: keine Fähigkeit"
    }
  }
}
```

Die Liste `spell_ids` ist für den jeweiligen NPC **vollständig**: Nicht aufgeführte alte Fähigkeiten werden entfernt, eine leere Liste blendet alle aus. Eine neu eingetragene Zauber-ID muss im Forever-Build von Wago vorhanden sein. Die Angabe `source` dokumentiert die Prüfung; sie wird nicht im Spiel angezeigt. Zum Zurücksetzen einer bereits übernommenen Forever-Zuordnung dient `{"reset": true, "source": "Grund"}` beim betreffenden NPC. Das Entfernen eines Eintrags aus der JSON-Datei allein löscht eine früher übernommene Zuordnung nicht.

### Kampfprotokoll für den Doppelklick einrichten

1. In Forever im Spielchat **`/combatlog`** eingeben und mit dem NPC kämpfen. Das Spiel schreibt `Logs/WoWCombatLog.txt` im Forever-Ordner `_classic_beta_`. Ist dieses Projekt direkt unter `_classic_beta_/Interface/AddOns/` installiert, findet der Updater die Datei beim Doppelklick selbst.
2. Liegt das Projekt woanders, einmalig `Updater/.data/config.json` anlegen. Pfade in JSON mit **Schrägstrichen** schreiben, zum Beispiel:

```json
{
  "combat_logs": ["D:/Games/World of Warcraft/_classic_beta_"]
}
```

Alternativ für einen einzelnen Lauf im Addon-Hauptordner: `py Updater/tools/update_database.py --combat-log "D:/Games/World of Warcraft/_classic_beta_"`. Der Spielordner oder die Logdatei können angegeben werden. Im Abschlussbericht stehen die gefundenen Builds, Kampfereignisse und ergänzten NPC-Zuordnungen. Meldet der Updater „Kein Forever-Kampfprotokoll gefunden“, wurden **keine neuen NPC-Fähigkeiten automatisch zugeordnet**. Ein Log mit anderem Build als 1.60.x wird abgewiesen. Kampfprotokolle zeigen nur tatsächlich gewirkte Zauber; manche NPC-Fähigkeiten sind darum trotz langer Spielzeit noch unbekannt.

Optional lassen sich einzelne NPCs gezielt gegen den Wowhead-Forever-Reiter „Abilities“ prüfen, etwa `py Updater/tools/update_database.py --npc 30 270589`. **Nur diese angegebenen NPC-Seiten** werden abgerufen; es gibt keinen Vollimport über Wowhead. Ein fehlender Reiter oder 404 gilt nicht als Löschbeleg. Manuell eingetragene Korrekturen haben Vorrang. Wowhead-Zuordnungen können unvollständig oder falsch sein; für verlässliche Korrekturen die IDs im Spiel prüfen und in `npc_overrides.json` festhalten.

## Vorschau, Bericht und Backup

```powershell
py Updater/tools/update_database.py --dry-run
py Updater/tools/update_database.py --build 1.60.1.70058 --dry-run
py Updater/tools/update_database.py --refresh
py -m unittest discover -s Updater/tests -p 'test_*.py'
```

`--dry-run` lässt die installierte Datenbank unverändert und schreibt `Updater/.data/preview-forever.lua` sowie `Updater/.data/preview-report.json`. Ein regulärer Lauf schreibt `Database/forever.lua` und `Database/forever.json` und legt vor einer Änderung ein Backup beider Dateien unter `Updater/.data/backups/` ab. `Updater/.data/last-report.json` enthält Build, Abrufzahlen, NPC-Änderungen, ausgewertete Kampfprotokolle, fehlende Namen und die Anzahl nicht aufgelöster Beschreibungsvorlagen. „Neue Sprach-/Zaubereinträge“ meint neu **im lokalen Overlay**, nicht zwingend neu im Spiel. Ein erneuter Lauf mit denselben Quelldaten ändert nichts.

Zum Rückgängigmachen beide `forever.*`-Dateien aus demselben Backup nach `Database` kopieren und `/reload` ausführen. Die ursprünglichen Classic-Dateien werden vom Updater nicht verändert. Auf anderen Classic-Versionen bleibt die bisherige Datenbank aktiv.

## Sauberes CurseForge-ZIP

`Updater/Curse ZIP erstellen.cmd` doppelklicken. Das erzeugt **`NpcAbilitiesForever.zip` im Ordner über dem Addon-Projekt**, direkt bereit für den manuellen CurseForge-Upload. Im ZIP liegen nur die vom Addon benötigten Lua-, XML- und TOC-Dateien sowie die Lizenz. `Updater/`, Tests, Cache, Berichte, Backups und die JSON-Arbeitsdaten werden nicht mitgepackt. Vor dem Erstellen des ZIPs bei Bedarf `Updater/Datenbank aktualisieren.cmd` ausführen, damit `Database/forever.lua` aktuell ist.

Von der Kommandozeile aus: `py Updater/build_release.py`. Der Builder verwendet den Addon-Namen `NpcAbilitiesForever` für ZIP-Datei und Addon-Ordner im Archiv. Der GitHub-Tag-Workflow verwendet denselben ZIP-Builder.

Beim manuellen Upload auf CurseForge die unterstützten Spielversionen auswählen. Für den automatischen Tag-Upload müssen das CurseForge-API-Token als Secret `CF_API_TOKEN` und die **eigene** CurseForge-Projekt-ID als Repository-Variable `CF_PROJECT_ID` hinterlegt werden. Die bisherige Projekt-ID gehörte zur Originalversion und wird nicht verwendet. Die Versions-IDs können optional kommasepariert als Repository-Variable `CF_GAME_VERSIONS` hinterlegt werden; ohne diese Variable sendet das Skript keine Versions-IDs. Ohne API-Token oder Projekt-ID erstellt der Tag-Workflow weiterhin das GitHub-Release und überspringt den CurseForge-Upload.
