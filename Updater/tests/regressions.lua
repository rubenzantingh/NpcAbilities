local setup = assert(loadfile("Updater/tests/wow_mock.lua"))()
local tests = 0
local function test(name, fn)
    fn()
    tests = tests + 1
    print("PASS: " .. name)
    collectgarbage("collect")
end
local function context(saved, config)
    return setup(true, "NpcAbilitiesForever", false, false, saved, config)
end
local function guid(id) return "Creature-0-1-0-1-" .. id .. "-0000000001" end
local function spell(id, name)
    return {spellID = id, spellName = "Observed spell", combatSpellDetails = {unitName = name or "Known NPC", isMob = true, isPet = false}}
end

test("First install defaults and Chinese options", function()
    local c = context(nil, {fresh = true, locale = "zhCN"})
    assert(c.env.NpcAbilitiesOptions.SELECTED_LANGUAGE == "en")
    assert(c.env.NpcAbilitiesOptions.LIVE_DATA_COLLECTION_ENABLED == true)
    local label = c.env.NpcAbilitiesTranslations.cn.options.liveDataCollectionEnabledLabel
    local found = false
    for _, frame in ipairs(c.frames) do
        if frame.Text and frame.Text.text == label then found = true end
    end
    assert(found, "Chinese option labels fell back to English")
    assert(c.env.ARTWORK == nil, "A heading created a global named ARTWORK")
end)

test("Malformed settings and nested observations preserve valid entries", function()
    local c = context({npcs = {[30] = {}, [40] = {spells = {[6016] = true, bad = true, [0] = true}},
        bad = false}, abilities = {de = {[6016] = {name = "Valid", description = false}}, en = false}},
        {options = {SELECTED_LANGUAGE = "invalid", LIVE_DATA_COLLECTION_ENABLED = "no", AVAILABLE_LANGUAGES = false}})
    assert(c.env.NpcAbilitiesOptions.SELECTED_LANGUAGE == "en")
    assert(c.env.NpcAbilitiesOptions.LIVE_DATA_COLLECTION_ENABLED == true)
    assert(c.env.NpcAbilitiesLearnedData.npcs[40].spells[6016].source == "legacy-name-match")
    assert(c.env.NpcAbilitiesLearnedData.npcs[40].spells[0] == nil)
    assert(c.env.NpcAbilitiesLearnedData.abilities.de[6016].description == nil)
    assert(c.tooltip(guid(30)) ~= "")
    local old = context(nil, {options = true})
    assert(old.env.NpcAbilitiesOptions.SELECTED_LANGUAGE == "en")
end)

test("Explicit NPC corrections override learned data; additive imports do not", function()
    local c = context({npcs = {[30] = {spells = {[11918] = true}}}, abilities = {}})
    c.env.NpcAbilitiesForeverData = {npcs = {[30] = {classic_spell_ids = {}, sod_spell_ids = {}}}, abilities = {}}
    assert(c.tooltip(guid(30)) == "", "Learned spell bypassed an empty correction")
    c.env.NpcAbilitiesForeverData.npcs[30].authoritative = false
    assert(c.tooltip(guid(30)) ~= "", "Additive import hid a learned spell")
end)

test("Spanish observations take precedence over English fallback per field", function()
    local c = context()
    c.setLocale("esES")
    c.env.NpcAbilitiesOptions.SELECTED_LANGUAGE = "es"
    c.env.NpcAbilitiesForeverData = {npcs = {}, abilities = {en = {[88880002] = {name = "English", description = "Old English"}}}}
    c.env.C_Spell.GetSpellInfo = function() return {name = "Nombre", castTime = 2000, minRange = 0, maxRange = 30} end
    c.env.C_Spell.GetSpellDescription = function() return "Descripcion" end
    c.scan({spell(88880002)})
    local saved = c.env.NpcAbilitiesLearnedData.abilities.es[88880002]
    assert(saved.name == "Nombre" and saved.description == "Descripcion")
    assert(saved.cast_time == "2 segundos")
    assert(c.tooltip(guid(88880001)):find("Nombre", 1, true))
    c.env.C_Spell.GetSpellDescription = function() return "Actualizada" end
    c.scan({spell(88880002)})
    assert(saved.description == "Actualizada", "A later observation could not update metadata")
end)

test("Target frame respects title and separate detail settings", function()
    local c = context()
    local o = c.env.NpcAbilitiesOptions
    o.ABILITY_DISPLAY_LOCATION = "both"
    o.DISPLAY_ABILITY_CAST_TIME, o.DISPLAY_ABILITY_RANGE = true, true
    c.event("PLAYER_TARGET_CHANGED")
    local text = c.env.NpcAbilitiesForeverTargetFrame.font.text
    assert(text:find("Sofort", 1, true) and text:find("5 Meter", 1, true))
    o.SELECTED_ABILITY_CAST_TIME_DISPLAY_MODE = "separate"
    o.SELECTED_HOTKEY = "F6"
    for _, frame in ipairs(c.frames) do
        if frame.events.MODIFIER_STATE_CHANGED then frame.scripts.OnKeyDown(frame, "F6") end
    end
    assert(c.env.NpcAbilitiesForeverTargetFrame.font.text:find("Zauberzeit: Sofort", 1, true))
end)

test("Same-name spells with different details remain visible", function()
    local c = context()
    c.env.NpcAbilitiesForeverData = {npcs = {[30] = {classic_spell_ids = {88880002, 88880003, 88880004}, sod_spell_ids = {}}},
        abilities = {de = {[88880002] = {name = "Same name", range = "5 yards"},
            [88880003] = {name = "Same name", range = "30 yards"},
            [88880004] = {name = "Same name", range = "30 yards"}}}}
    c.env.NpcAbilitiesOptions.DISPLAY_ABILITY_RANGE = true
    local text = c.tooltip(guid(30))
    assert(text:find("5 yards", 1, true) and text:find("30 yards", 1, true))
    local _, count = text:gsub("Same name", "")
    assert(count == 2, "Only completely identical display rows should be grouped")
end)

test("Collection uses session NPC IDs, never current target or Overall", function()
    local c = context()
    local reads = 0
    c.env.C_DamageMeter.GetCombatSessionFromID = function(id, meterType)
        reads = reads + 1
        assert(id == 101)
        if meterType == 10 then return {combatSources = {{name = "Known NPC", sourceCreatureID = 88880001}}} end
        return {combatSources = {{sourceGUID = "Player-1-1"}}}
    end
    c.setGuid(guid(88880009)) -- Same visible name, unrelated to session 101.
    c.env.C_DamageMeter.combatSpells = {spell(88880002)}
    c.setCombat(true)
    for _ = 1, 10 do c.event("DAMAGE_METER_COMBAT_SESSION_UPDATED", 7, 101) end
    c.flushTimers()
    assert(reads == 0)
    c.setCombat(false)
    c.event("PLAYER_REGEN_ENABLED")
    c.flushTimers()
    assert(reads == 2, "Duplicate events were not coalesced")
    local saved = c.env.NpcAbilitiesLearnedData.npcs
    assert(saved[88880001].spells[88880002].sessionID == 101)
    assert(saved[88880009] == nil, "Historical data was assigned to the visible NPC")
    for _ = 1, 10 do c.event("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 101) end
    c.flushTimers()
    assert(reads == 2, "Unrelated meter events caused reads")
end)

test("Ambiguous, unidentified and pet casters are not learned", function()
    local c = context()
    c.env.C_DamageMeter.GetCombatSessionFromID = function(_, meterType)
        if meterType == 10 then return {combatSources = {
            {name = "Known NPC", sourceCreatureID = 88880001}, {name = "Known NPC", sourceCreatureID = 88880009}}} end
        return {combatSources = {{sourceGUID = "Player-1-1"}}}
    end
    c.scan({spell(88880002), spell(88880003, "Unidentified")})
    assert(next(c.env.NpcAbilitiesLearnedData.npcs) == nil)
    local p = context()
    local pet = spell(88880002); pet.combatSpellDetails.isPet = true
    p.scan({pet})
    assert(next(p.env.NpcAbilitiesLearnedData.npcs) == nil)
end)

test("Repeated notifications skip metadata; disable cancels queued work", function()
    local c = context()
    local lookups = 0
    c.env.C_Spell.GetSpellInfo = function() lookups = lookups + 1; return {name = "Observed spell"} end
    c.scan({spell(88880002)})
    local before = lookups
    c.event("DAMAGE_METER_COMBAT_SESSION_UPDATED", 7, 1)
    c.flushTimers()
    assert(lookups == before, "Unchanged spells were resolved again")
    c.env.C_DamageMeter.combatSpells = {spell(88880003)}
    c.event("DAMAGE_METER_COMBAT_SESSION_UPDATED", 7, 2)
    c.addonNamespace.SetLiveDataCollectionEnabled(false)
    c.flushTimers()
    assert(c.env.NpcAbilitiesLearnedData.npcs[88880001].spells[88880003] == nil)
    for _, frame in ipairs(c.frames) do
        assert(not frame.events.NAME_PLATE_UNIT_ADDED, "Unnecessary nameplate listener remains")
        assert(not frame.events.DAMAGE_METER_COMBAT_SESSION_UPDATED, "Collector did not unregister")
    end
end)

test("Unavailable data retries are bounded; reset cancels work", function()
    local c = context()
    local calls = 0
    c.env.C_DamageMeter.GetCombatSessionFromID = function() calls = calls + 1; error("Unavailable") end
    c.scan({spell(88880002)})
    assert(calls == 6, "Expected two reads per attempt, with at most three attempts")
    c.event("DAMAGE_METER_COMBAT_SESSION_UPDATED", 7, 2)
    c.event("DAMAGE_METER_RESET")
    c.flushTimers()
    assert(calls == 6)
end)

print("PASS: " .. tests .. " audit regression scenarios")
