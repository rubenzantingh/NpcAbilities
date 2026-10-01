local setup = assert(loadfile("Updater/tests/wow_mock.lua"))()
local c = setup(true, "NpcAbilitiesForever", false, false, nil, {fullDatabase = true})
local env, count = c.env, 0
local options = env.NpcAbilitiesOptions
options.ABILITY_DISPLAY_LOCATION = "both"
options.DISPLAY_PRIORITY_INDICATORS = true
options.SELECTED_HOTKEY = "F6"
for _, field in ipairs({"MECHANIC", "RANGE", "CAST_TIME", "COOLDOWN", "DISPEL_TYPE"}) do
    options["DISPLAY_ABILITY_" .. field] = true
    options["SELECTED_ABILITY_" .. field .. "_DISPLAY_MODE"] = "separate"
end
for _, frame in ipairs(c.frames) do
    if frame.events.MODIFIER_STATE_CHANGED then frame.scripts.OnKeyDown(frame, "F6") end
end

for language in pairs(env.NpcAbilitiesAbilityData) do
    options.SELECTED_LANGUAGE = language
    for npcID, npc in pairs(env.NpcAbilitiesNpcData) do
        assert(type(npcID) == "number" and npcID > 0 and npcID == math.floor(npcID))
        for _, list in ipairs({npc.classic_spell_ids, npc.sod_spell_ids}) do
            local seen = {}
            for _, spellID in ipairs(list) do
                assert(not seen[spellID], "Duplicate NPC spell ID: " .. npcID .. ":" .. spellID)
                seen[spellID] = true
                local record = env.NpcAbilitiesForeverData.abilities[language][spellID]
                    or env.NpcAbilitiesAbilityData[language][spellID]
                    or env.NpcAbilitiesForeverData.abilities.en[spellID]
                    or env.NpcAbilitiesAbilityData.en[spellID]
                assert(record and type(record.name) == "string", "Missing spell: " .. npcID .. ":" .. spellID)
            end
        end
        local guid = "Creature-0-1-0-1-" .. npcID .. "-0000000001"
        c.setGuid(guid)
        c.tooltip(guid)
        c.event("PLAYER_TARGET_CHANGED")
        count = count + 1
    end
end
print("PASS: " .. count .. " full-database NPC/language combinations and spell references (simulated)")
