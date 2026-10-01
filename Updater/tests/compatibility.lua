-- Run from the addon directory with Lua 5.1: lua Updater/tests/compatibility.lua
local setup = assert(loadfile("Updater/tests/wow_mock.lua"))()
local function runScenario(modern, addonName, delayed, missingIcon, savedData)
    local context = setup(modern, addonName, delayed, missingIcon, savedData)
    local env, event, tooltip = context.env, context.event, context.tooltip
    local frames, addonNamespace = context.frames, context.addonNamespace
    local guid = context.getGuid()
    if savedData then
        env.NpcAbilitiesOptions.ABILITY_DISPLAY_LOCATION = "both"
        guid = "Creature-0-1-0-1-88880001-0000000002"; context.setGuid(guid)
        local text = tooltip(guid)
        if modern then
            assert(text:find("Observed spell", 1, true), "Learned data was lost after reload")
            event("PLAYER_TARGET_CHANGED")
            assert(env.NpcAbilitiesForeverTargetFrame.font.text:find("Observed spell", 1, true))
        else
            assert(text == "", "Forever observations leaked into Classic")
        end
        return
    end
    local expected = env.NpcAbilitiesAbilityData.de[11918].name
    assert(tooltip(guid):find(expected, 1, true), "Known Classic NPC ability missing")
    assert(tooltip(nil):find(expected, 1, true), "Unit-token fallback failed")
    if modern then assert(tooltip(guid, env.CreateFrame("GameTooltip")) == "", "Unrelated tooltip modified") end

    env.NpcAbilitiesOptions.ABILITY_DISPLAY_LOCATION = "both"
    event("PLAYER_TARGET_CHANGED")
    assert(env.NpcAbilitiesForeverTargetFrame.shown)
    assert(env.NpcAbilitiesForeverTargetFrame.font.text:find(expected, 1, true))
    env.NpcAbilitiesOptions.ABILITY_DISPLAY_LOCATION = "target_frame"
    assert(tooltip(guid) == "")
    env.NpcAbilitiesOptions.ABILITY_DISPLAY_LOCATION = "tooltip"
    event("PLAYER_TARGET_CHANGED")
    assert(not env.NpcAbilitiesForeverTargetFrame.shown)
    env.NpcAbilitiesOptions.ABILITY_DISPLAY_LOCATION = "both"
    env.NpcAbilitiesOptions.SELECTED_HOTKEY_MODE = "hold_and_hide"
    assert(tooltip(guid) == "")
    event("PLAYER_TARGET_CHANGED")
    assert(not env.NpcAbilitiesForeverTargetFrame.shown)
    env.NpcAbilitiesOptions.SELECTED_HOTKEY_MODE = "toggle"

    -- Wago may only provide a name; old tooltip details must fill missing fields.
    env.NpcAbilitiesForeverData = {npcs = {}, abilities = {de = {[11918] = {name = "Neuer Giftname"}}}}
    if modern then
        assert(tooltip(guid):find("Neuer Giftname", 1, true), "Partial spell overlay failed")
    else
        assert(tooltip(guid):find(expected, 1, true))
    end

    -- Forever overrides must replace old mappings, support new NPCs, and fall
    -- back to English for updated spells without a selected-language entry.
    env.NpcAbilitiesForeverData = {
        npcs = {
            [30] = {classic_spell_ids = {987654}, sod_spell_ids = {}},
            [270589] = {classic_spell_ids = {987654}, sod_spell_ids = {}},
        },
        abilities = {
            en = {[987654] = {name = "Forever ability", description = "Updated"}},
            es = {[987654] = {name = "Habilidad localizada"}},
        },
    }
    if modern then
        local text = tooltip(guid)
        assert(text:find("Forever ability", 1, true))
        assert(not text:find(expected, 1, true), "Old ability survived an authoritative replacement")
        env.NpcAbilitiesOptions.SELECTED_LANGUAGE = "es"
        assert(tooltip(guid):find("Habilidad localizada", 1, true), "Selected-language spell data was not used")
        env.NpcAbilitiesOptions.SELECTED_LANGUAGE = "de"
        event("PLAYER_TARGET_CHANGED")
        assert(env.NpcAbilitiesForeverTargetFrame.font.text:find("Forever ability", 1, true))
        env.NpcAbilitiesForeverData.npcs[30].classic_spell_ids = {}
        assert(tooltip(guid) == "", "Explicit empty mapping fell back to Classic")
        event("PLAYER_TARGET_CHANGED")
        assert(not env.NpcAbilitiesForeverTargetFrame.shown)
        guid = "Creature-0-1-0-1-270589-0000000001"; context.setGuid(guid)
        assert(tooltip(guid):find("Forever ability", 1, true), "New NPC was not found")
    else
        assert(tooltip(guid):find(expected, 1, true), "Forever overlay changed Classic display")
    end

    for _, unknown in ipairs({"Creature-0-1-0-1-999999999-1", "Player-0-30", "invalid"}) do
        guid = unknown; context.setGuid(guid)
        assert(tooltip(guid) == "", "Unknown/restricted unit received abilities")
        event("PLAYER_TARGET_CHANGED")
        assert(not env.NpcAbilitiesForeverTargetFrame.shown)
    end
    guid = nil; context.setGuid(guid)
    assert(tooltip(nil) == "")
    event("PLAYER_TARGET_CHANGED")
    assert(not env.NpcAbilitiesForeverTargetFrame.shown)

    if not modern then
        assert(env.NpcAbilitiesLearnedData == nil, "Learning enabled outside Forever")
        assert(tooltip(guid) == "")
        return
    end

    local learningFrame
    for _, frame in ipairs(frames) do
        if frame.events.DAMAGE_METER_COMBAT_SESSION_UPDATED then learningFrame = frame end
    end
    assert(learningFrame, "Live collection should be enabled by default")

    guid = "Creature-0-1-0-1-88880001-0000000001"; context.setGuid(guid)
    event("PLAYER_TARGET_CHANGED")
    env.GameTooltip:Show()
    tooltip(guid)
    local function scan(spells)
        context.scan(spells)
    end
    scan({
        {spellID = 88880002, spellName = "Observed spell", combatSpellDetails = {unitName = "Known NPC"}},
        {spellID = 6603, spellName = "Angreifen", combatSpellDetails = {unitName = "Known NPC"}},
    })

    local learned = env.NpcAbilitiesLearnedData
    assert(learned.npcs[88880001].spells[88880002], "Damage Meter spell was not learned after combat")
    assert(not learned.npcs[88880001].spells[6603], "Generic attack was learned")
    assert(learned.abilities.de[88880002].name == "Observed spell")
    assert(env.NpcAbilitiesForeverTargetFrame.shown, "Target frame not refreshed after learning")
    assert(env.NpcAbilitiesForeverTargetFrame.font.text:find("Observed spell", 1, true))
    assert(table.concat(env.GameTooltip.lines, "\n"):find("Observed spell", 1, true), "Open tooltip not refreshed after learning")
    assert(table.concat(env.NpcAbilitiesForeverDebugLog.messages, "\n"):find("GELERNT", 1, true), "Debug window did not explain learning result")

    local collectionCheckbox
    local label = env.NpcAbilitiesTranslations.de.options.liveDataCollectionEnabledLabel
    for _, frame in ipairs(frames) do
        if frame.Text and frame.Text.text == label then collectionCheckbox = frame; break end
    end
    assert(collectionCheckbox, "Live data collection setting is missing")
    collectionCheckbox.checked = false
    collectionCheckbox.scripts.OnClick(collectionCheckbox)
    assert(env.NpcAbilitiesOptions.LIVE_DATA_COLLECTION_ENABLED == false)
    assert(not learningFrame.events.DAMAGE_METER_COMBAT_SESSION_UPDATED, "Collection listener stayed active when disabled")
    local debugStatus = env.NpcAbilitiesForeverDebugStatus.text
    assert(debugStatus:find("Sammlung: AUS", 1, true), "Disabled state was not shown in German")
    assert(debugStatus:find("in den NpcAbilitiesForever-Optionen", 1, true), "Disabled-state options hint missing")
    assert(debugStatus:find("/nabdebug", 1, true), "Short debug command was not shown")
    env.NpcAbilitiesOptions.SELECTED_LANGUAGE = "en"
    addonNamespace.Debug.Refresh()
    debugStatus = env.NpcAbilitiesForeverDebugStatus.text
    assert(debugStatus:find("Collection is OFF", 1, true), "Disabled state was not shown in English")
    assert(debugStatus:find("NpcAbilitiesForever options", 1, true), "English options hint missing")
    assert(env.NpcAbilitiesForeverDebugTitle.text:find("Combat Debug", 1, true), "English debugger title missing")
    env.NpcAbilitiesOptions.SELECTED_LANGUAGE = "de"
    addonNamespace.Debug.Refresh()
    scan({{spellID = 88880003, spellName = "Disabled spell", combatSpellDetails = {unitName = "Known NPC"}}})
    assert(not learned.npcs[88880001].spells[88880003], "Spell learned while collection was disabled")

    collectionCheckbox.checked = true
    collectionCheckbox.scripts.OnClick(collectionCheckbox)
    assert(learningFrame.events.DAMAGE_METER_COMBAT_SESSION_UPDATED, "Collection listener did not resume when enabled")
    context.setLocale("zhCN")
    scan({{spellID = 88880003, spellName = "Re-enabled spell", combatSpellDetails = {unitName = "Known NPC"}}})
    assert(learned.npcs[88880001].spells[88880003], "Collection did not resume after being enabled")
    assert(learned.abilities.cn[88880003].name == "Re-enabled spell", "Simplified Chinese locale was not normalized")
    return learned
end

local count = 0
for _, modern in ipairs({true, false}) do
    for _, name in ipairs({"NpcAbilitiesForever"}) do
        for _, delayed in ipairs({false, true}) do
            for _, missingIcon in ipairs({false, true}) do
                local saved = runScenario(modern, name, delayed, missingIcon)
                if saved then
                    runScenario(true, name, delayed, missingIcon, saved)
                    runScenario(false, name, delayed, missingIcon, saved)
                end
                count = count + 1
            end
        end
    end
end
print("PASS: " .. count .. " startup/display scenarios, post-combat learning, collection toggle, reload and version isolation")
