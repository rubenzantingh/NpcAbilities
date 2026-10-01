# Data provenance and unresolved associations

- `npcs.lua`, `priorities.lua` and `Abilities/*.lua` originate from NpcAbilities. Their syntactic validity does not establish that every inherited association remains correct in Forever.
- `forever.json` records the imported Wago build and source. `forever.lua` is its generated runtime representation. The shipped snapshot contains spell data but currently no extra NPC mappings.
- In-game observations use a unique NPC-name join between incoming damage and enemy creature IDs from the same Damage Meter session. They are inferred and stored with `confidence = "unverified"`, `source = "damage-meter-session-name"` and the session ID. Session IDs are diagnostic, not globally unique evidence. Legacy observations are retained as `legacy-name-match`; previously incorrect associations cannot be repaired automatically without evidence.
- Explicit user corrections and complete Wowhead mappings are authoritative. Combat-log imports are additive. Neither an empty observation set nor a missing source page proves that an NPC lost an ability.

## Audit correction

NPC 5645 originally referenced spell IDs 744, **5645** and 7159. Spell 5645 has no entry in any shipped baseline locale or in Wago snapshot 1.60.1.70124. The dangling reference was removed; the other two IDs were preserved. No replacement spell ID is asserted, and the removal is not a claim that this NPC has no additional abilities. Recovering the intended ID requires independent source evidence.

## Equal names are not aliases

The snapshot gives equal display names to distinct spell IDs for NPCs 6112, 7483, 7484 and 14666 (Windfury Totem variants). Some baseline ranges differ. These IDs have not been declared equivalent. The renderer groups only fully identical display records, retaining all underlying IDs; differing descriptions, ranges, cast times or other fields remain distinct.

## Sources and rights

The original project is [rubenzantingh/NpcAbilities](https://github.com/rubenzantingh/NpcAbilities). Spell imports use [Wago Tools](https://wago.tools/); optional NPC lookups use [Wowhead Forever](https://www.wowhead.com/forever). Bundled LibStub declares itself public domain in its source. LibUIDropDownMenu retains its upstream author/source comments.

The repository's existing LICENSE remains unchanged. This contribution does not assert a new redistribution license or approval for an independent release.
