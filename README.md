# NpcAbilitiesForever

## Description and features

NpcAbilitiesForever is a development fork of [NpcAbilities by Ruben Zantingh](https://github.com/rubenzantingh/NpcAbilities), prepared for upstream review. It adds each NPC's known abilities to its game tooltip. You can display them in the tooltip, below the target frame, or in both places. A configurable hotkey reveals additional ability details, including mechanic, range, cast time, cooldown, and dispel type when available. Both display locations respect the detail settings. Ability names can use a single color or colors based on their priority.

The display language can be selected in the addon's options. The database includes English, German, Spanish, French, Brazilian Portuguese, Russian, Korean, and Simplified Chinese. Localized observations fill missing fields before another language is used as a fallback. Identical display rows are grouped; equally named spells with different descriptions or details remain visible. Their underlying IDs are kept separate.

The TOC targets Classic interface 11509 and Forever interface 16001. Live collection is enabled only on Forever. LibStub and LibUIDropDownMenu are bundled; no other addon or reference folder is required.

### NPC spell collection in WoW Forever

On Forever 1.60.x, collection is enabled by default and can be disabled in the addon options. After combat, the addon reads incoming damage and the enemy roster from the **same Damage Meter session ID**. The enemy roster supplies creature IDs. Names are used only to join those two lists within that session; missing or ambiguous matches are skipped. Current targets and historical overall totals are never used to guess an identity. Generic attacks and pet damage are ignored.

This remains an inferred association, not proof that a particular NPC cast a spell. The API does not expose a direct caster GUID on each incoming spell row. Observations record their source, session ID and unverified status. Older observations remain available and are marked as legacy observations. An enemy absent from the session's enemy roster cannot be learned, even if its spell appears in incoming damage. Non-damaging abilities are not discovered by this collector.

The collector coalesces relevant events, skips repeated spell metadata, bounds its session cache and retries, and unregisters its collection events when disabled. It has no nameplate listener or per-frame collection loop. A reset of the Damage Meter clears pending work.

Observations are saved locally in `NpcAbilitiesLearnedData`; they are not shared or written into the shipped database. WoW saves them on `/reload` or logout. Updates preserve valid saved settings and observations and repair malformed records. Explicit NPC corrections take precedence over learned associations.

Use `/nabdebug` to open or close the debug window and `/nabdebug clear` to clear its log. It explains skipped observations and disabled collection. The window can be moved and closed with X or Escape. Debug text defaults to English, with German text when German is selected.

### Database updater

The updater downloads the Forever spell catalog from [Wago Tools](https://wago.tools/), including localized names and readable descriptions in eight languages. It imports spells even before they are associated with NPCs. Associations can come from in-game observations, local Forever combat logs or documented corrections in `Database/npc_overrides.json`. Downloading a spell name does not establish an NPC association.

On Windows, run `Updater/Update database.cmd`. Python 3.10 or newer is required; no additional Python packages are needed. The updater creates backups and a change report. It does not read the SavedVariables learning store. See the [updater guide](Updater/README.md).

## Install a development build

Clone or download this repository, then run `Updater/Build release ZIP.cmd` or `python Updater/build_release.py`. Extract the resulting `NpcAbilitiesForever` folder into the appropriate client's `Interface/AddOns` directory. The archive contains runtime files and the existing license; it excludes updater scripts, tests, reference addons, cached downloads and JSON working files.

When replacing an existing NpcAbilitiesForever installation, keep WoW's SavedVariables and replace the addon files while the game is closed. Disable the original NpcAbilities if it is installed alongside this fork: both use the original shared data globals. Switching from the original addon folder is not an automatic SavedVariables migration; back up your settings before switching.

This branch is for GitHub contribution and in-game testing. It is not a published CurseForge release. The existing [license](LICENSE) and original author credit are unchanged.

## Validation and contribution

Run `python Updater/run_checks.py`. It uses the Python standard library and either Lua 5.1 or the optional `lupa` package for Lua tests (`python -m pip install lupa`). These are offline tests and WoW API simulations, not in-game validation.

The [manual test checklist](TESTING.md) covers installation, reloads, existing settings, collection and display behavior. [Data notes](Database/DATA_NOTES.md) distinguish structural validation from confirmed associations. Feedback and technical suggestions are welcome through GitHub issues and pull requests.
