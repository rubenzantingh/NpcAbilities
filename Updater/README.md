# Database updater

Run **`Update database.cmd`** on Windows, or `python Updater/tools/update_database.py` from the repository root. Python 3.10+ is required; no third-party Python packages are needed. After updating the installed addon, use `/reload`. If working in a source checkout, copy the updated runtime files into the installed addon first.

The in-game collector works independently of this updater and `/combatlog`. Its observations live in WoW SavedVariables, which this updater neither reads nor modifies. See the [addon description](../README.md#npc-spell-collection-in-wow-forever).

## Downloads and recovery

The updater selects a Forever 1.60.x build from Wago and downloads the `SpellName` and `Spell` CSV tables for English, German, Spanish, French, Portuguese, Russian, Korean and Chinese. A normal uncached run makes 17 requests: one build lookup and two tables per language. It does not crawl all NPC or spell pages. Downloads are cached for 24 hours.

Progress is printed throughout; while a request is pending, a progress message appears every five seconds. Each Wago request has a 120-second total timeout including connection setup and transfer. Use `--timeout 180` to change it. Run again after cancellation or failure to reuse valid downloads. HTTP errors, invalid exports and incomplete updates do not intentionally replace the installed database; write failures are covered by rollback tests.

The spell catalog is written to `Database/forever.lua`, with its editable snapshot in `Database/forever.json`. All supported languages are included by default. New Forever text belongs in this overlay; `Database/Abilities` contains the inherited baseline.

Descriptions with unresolved tokens such as `$s1` are not imported. A previously downloaded description is removed if the new source becomes empty or unreadable, allowing the runtime's baseline/observation fallback to work. Cast times, ranges, mechanics, cooldowns and dispel types may come from the baseline or client observations; the two CSV tables do not provide all of these as display-ready text.

## NPC associations and explicit corrections

Wago spell tables do not establish which NPC casts a spell. Existing baseline associations are retained unless explicitly corrected. Combat-log imports are additive: not observing a spell is not proof that it was removed.

For a documented, complete NPC replacement, edit `Database/npc_overrides.json`:

```json
{
  "npcs": {
    "30": {
      "name": "Example NPC",
      "spell_ids": [],
      "source": "Replace this example with evidence from a real observation"
    }
  }
}
```

Do not apply this example as a claim about NPC 30. The `spell_ids` list is authoritative: an empty list suppresses all abilities, including locally learned ones. Nonempty lists similarly exclude unlisted spells. Live observations remain saved but do not override the correction. Newly supplied spell IDs must exist in the selected Wago build. The source field records your evidence; a name match alone is not proof.

Use `{"reset": true, "source": "Reason for reverting the correction"}` to remove an installed override and return to the baseline plus learned data. Simply deleting a JSON entry does not remove a correction already installed in the snapshot.

Optional Wowhead lookup: `python Updater/tools/update_database.py --npc 30 270589`. Only those NPC pages are queried. A complete abilities tab replaces that NPC's mapping; a missing tab or HTTP 404 does not prove removal. Curated corrections take precedence. Wowhead data still requires content verification.

## Import a Forever combat log

1. Enable `/combatlog` in Forever and fight the NPC. The importer reads NPC `SPELL_CAST_START` and `SPELL_CAST_SUCCESS` entries with valid creature and spell IDs.
2. Pass a log file or game directory: `python Updater/tools/update_database.py --combat-log "D:/Games/World of Warcraft/_classic_beta_"`.
3. For repeat runs, create the ignored local file `Updater/.data/config.json`:

```json
{
  "combat_logs": ["D:/Games/World of Warcraft/_classic_beta_"]
}
```

Without an explicit path, the updater checks the installed addon's game directory and standard Windows `_classic_beta_` locations. This directory name reflects the supported development client; use an explicit path if your installation differs. Log headers must identify Forever 1.60.x. Imported associations use an additive overlay and do not prohibit later live observations. The report lists the log paths, builds and accepted casts.

## Preview and backups

```powershell
python Updater/tools/update_database.py --dry-run
python Updater/tools/update_database.py --build 1.60.1.70124 --dry-run
python Updater/tools/update_database.py --refresh
python Updater/run_checks.py
```

A dry run writes `Updater/.data/preview-forever.lua` and `preview-report.json`, leaving the live database unchanged. Regular runs back up both `forever.*` files under `Updater/.data/backups/` and write `last-report.json`. Reports include source changes, cache hits, missing names and unresolved descriptions. Restore both files from the same backup to undo an update.

## Local archive

Run **`Build release ZIP.cmd`** or `python Updater/build_release.py`. The default output is `NpcAbilitiesForever.zip` in the directory above the checkout. Updater scripts, tests, reference addons, reports, cache and JSON working data are excluded. The updater must be run from the source checkout, not from this runtime-only archive.

The current contribution workflow is a GitHub branch and pull request, with no release or CurseForge upload. The existing tag workflow is only triggered by pushing a tag; do not push a release tag for this review. Its optional CurseForge step requires `CF_API_TOKEN` and your own `CF_PROJECT_ID`, with optional comma-separated `CF_GAME_VERSIONS`. None of those credentials belong in source files.
