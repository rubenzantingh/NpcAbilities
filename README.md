# NpcAbilitiesForever

## Description and features

NpcAbilitiesForever adds each NPC's known abilities to its game tooltip. You can display them in the tooltip, below the target frame, or in both places. A configurable hotkey reveals additional ability details, including mechanic, range, cast time, cooldown, and dispel type when that data is available. Ability names can use a single color or colors based on their priority.

The display language can be selected in the addon's options. The database currently includes English, German, Spanish, French, Brazilian Portuguese, Russian, Korean, and Simplified Chinese. Spell data comes from third-party sources and may be incomplete or inaccurate.

### Live NPC spell collection in WoW Forever

On WoW Forever 1.60.x, the addon can learn NPC spell associations while you play. Collection is enabled by default and can be disabled in the addon options. After combat, it reads the built-in Damage Meter's incoming-damage data, identifies NPC spells when the client exposes their IDs, and associates them with a visible hostile or neutral NPC. Generic attacks such as "Attack" are ignored. Learned abilities then appear for NPCs with the same creature ID.

Live observations are saved locally in WoW's `NpcAbilitiesLearnedData` SavedVariables and are not added to the shipped database or shared with other players. WoW writes SavedVariables on reload or logout, so observations since the last save can be lost if the game crashes. The collector depends on the Damage Meter data being available and the caster being matched to an observed NPC; some spells or NPCs may not be identified.

Use `/nabdebug` to open or close the live-collection debug window. It shows recent observations and why entries were learned or skipped. Use `/nabdebug clear` to clear its log. The window can be moved and closed with Escape.

### Database updater

The updater downloads the Forever spell catalog from [Wago Tools](https://wago.tools/), including localized names and readable descriptions in all eight supported languages. It includes spells even before they are assigned to a particular NPC. NPC-to-spell associations can be learned in-game, imported from a local Forever combat log, or curated in `Database/npc_overrides.json`. The updater creates backups and a change report when it updates the local database.

On Windows, double-click `Updater/Datenbank aktualisieren.cmd` to run it. Python 3.10 or newer is required; no extra Python packages are needed. After an update, run `/reload` in game. The updater does not read the in-game SavedVariables learning store. See the [updater guide](Updater/README.md) for its options, reports, and database recovery instructions.

## Download

Once listed, the addon will be available through the CurseForge Client and on its CurseForge project page. For a manual install, download `NpcAbilitiesForever.zip` from the [GitHub Releases page](https://github.com/KirzunTaiyor/NpcAbilitiesForever/releases) and extract the `NpcAbilitiesForever` folder into your WoW `Interface/AddOns` directory.

The ZIP contains only the addon's runtime files. Updater scripts, tests, cached downloads, and database working files are excluded.

## Contribution

Feedback and technical suggestions are welcome. Please open an [issue](https://github.com/KirzunTaiyor/NpcAbilitiesForever/issues) or submit a pull request on GitHub. CurseForge comments are welcome once the project page is available.
