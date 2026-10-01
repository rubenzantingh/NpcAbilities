-- Run from the addon directory with Lua 5.1: lua Updater/tests/compatibility.lua
local function runScenario(modern, addonName, delayed, missingIcon, savedData)
    local env = setmetatable({}, {__index = _G})
    env._G = env
    local addonNamespace = {}
    local frames, callbacks, timers = {}, {}, {}
    local clientLocale = "deDE"
    local guid = "Creature-0-1-0-1-30-0000000001"
    local unitGuids = {}
    local secret = {}
    local methods = {}
    local function noop() end
    for name in string.gmatch("SetPoint SetSize SetBackdropColor SetBackdropBorderColor SetJustifyH SetJustifyV SetWordWrap SetNonSpaceWrap SetPropagateKeyboardInput SetFont SetFontObject SetTextColor SetColorTexture EnableMouseWheel SetScrollChild SetMaxLines SetFading SetInsertMode EnableMouse SetMovable RegisterForDrag StartMoving StopMovingOrSizing", "%S+") do
        methods[name] = noop
    end
    function methods:SetScript(name, fn) self.scripts[name] = fn end
    function methods:HookScript(name, fn)
        assert(not modern or name ~= "OnTooltipSetUnit", "Removed tooltip script used")
        self.scripts[name] = fn
        if name == "OnTooltipSetUnit" then
            self.hookCount = (self.hookCount or 0) + 1
        end
    end
    function methods:RegisterEvent(event) self.events[event] = true end
    function methods:RegisterUnitEvent(event, unit) self.events[event] = true; self.unitToken = unit end
    function methods:UnregisterEvent(event) self.events[event] = nil end
    function methods:UnregisterAllEvents() self.events = {} end
    function methods:Hide() self.shown = false end
    function methods:Show() self.shown = true end
    function methods:IsShown() return self.shown end
    function methods:SetBackdrop(value) self.backdrop = value end
    function methods:GetBackdrop() return self.backdrop end
    function methods:SetWidth(value) self.width = value end
    function methods:GetWidth() return self.width or 200 end
    function methods:SetHeight(value) self.height = value end
    function methods:GetStringHeight() return 30 end
    function methods:SetText(value) self.text = value end
    function methods:AddMessage(value) self.messages = self.messages or {}; table.insert(self.messages, value) end
    function methods:Clear() self.messages = {} end
    function methods:ScrollUp() end
    function methods:ScrollDown() end
    function methods:SetChecked(value) self.checked = value end
    function methods:GetChecked() return self.checked end
    function methods:GetUnit() return "Known NPC", "mouseover" end
    function methods:AddLine(text) table.insert(self.lines, text) end
    function methods:SetUnit(unit)
        assert(unit == "mouseover", "Live refresh changed the tooltip unit")
        self.lines = {}
        self.refreshCount = (self.refreshCount or 0) + 1
        if modern then
            callbacks[1](self, {guid = guid})
        else
            self.scripts.OnTooltipSetUnit(self)
        end
    end
    function env.CreateFrame(kind, name, parent, template)
        local frame = setmetatable({scripts = {}, events = {}, lines = {}}, {__index = methods})
        table.insert(frames, frame)
        if name then env[name] = frame end
        if kind == "CheckButton" then frame.Text = env.CreateFrame("FontString") end
        return frame
    end
    function methods:CreateFontString(name) local font = env.CreateFrame("FontString", name); self.font = font; return font end
    function methods:CreateTexture() return env.CreateFrame("Texture") end
    env.UIParent = env.CreateFrame("Frame")
    env.TargetFrame = env.CreateFrame("Frame")
    env.GameTooltip = env.CreateFrame("GameTooltip")
    env.GetLocale = function() return clientLocale end
    env.GetBuildInfo = function() return "", "", "", modern and 16001 or 11509 end
    env.UnitGUID = function(unit) return unitGuids[unit] or guid end
    env.UnitName = function(unit) return unit == "nameplate1" and "Observed NPC" or "Known NPC" end
    env.UnitExists = function(unit) return (unit == nil or unit == "target") and guid ~= nil or unitGuids[unit] ~= nil end
    env.UnitIsPlayer = function() return false end
    env.UnitPlayerControlled = function() return false end
    env.UnitReaction = function() return 3 end
    env.GetSpellInfo = function(spellId) return "Observed spell", nil, nil, nil, nil, nil, spellId end
    env.IsInInstance = function() return false end
    env.issecretvalue = function(value) return value == secret end
    env.bit = {band = function(a, b)
        local result, place = 0, 1
        while a > 0 and b > 0 do
            if a % 2 == 1 and b % 2 == 1 then result = result + place end
            a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
        end
        return result
    end}
    env.COMBATLOG_OBJECT_TYPE_NPC = 0x800
    env.COMBATLOG_OBJECT_CONTROL_NPC = 0x200
    env.COMBATLOG_OBJECT_CONTROL_PLAYER = 0x100
    env.COMBATLOG_OBJECT_REACTION_HOSTILE = 0x40
    env.COMBATLOG_OBJECT_REACTION_NEUTRAL = 0x20
    env.NpcAbilitiesLearnedData = savedData
    env.strsplit = function(delimiter, value)
        assert(value ~= secret, "Restricted GUID was parsed")
        local parts = {}
        for part in string.gmatch(value, "[^" .. delimiter .. "]+") do table.insert(parts, part) end
        return unpack(parts)
    end
    local function texture() if not missingIcon then return 12345 end end
    if modern then
        env.C_Spell = {GetSpellTexture = texture}
        env.Enum = {
            TooltipDataType = {Unit = 2},
            DamageMeterType = {DamageTaken = 1},
            DamageMeterSessionType = {Current = 1, Overall = 2},
        }
        env.C_DamageMeter = {
            GetCombatSessionFromType = function()
                return {combatSources = {{sourceGUID = "source", sourceCreatureID = 88880001}}}
            end,
            GetCombatSessionSourceFromType = function()
                return {combatSpells = env.C_DamageMeter.combatSpells}
            end,
        }
        env.C_DamageMeter.combatSpells = {}
        if missingIcon then
            env.Enum.CombatLogObject = {TypeNpc = 0x800, ControlNpc = 0x200,
                ControlPlayer = 0x100, ReactionHostile = 0x40, ReactionNeutral = 0x20}
            env.COMBATLOG_OBJECT_TYPE_NPC = nil
            env.COMBATLOG_OBJECT_CONTROL_NPC = nil
            env.COMBATLOG_OBJECT_CONTROL_PLAYER = nil
            env.COMBATLOG_OBJECT_REACTION_HOSTILE = nil
            env.COMBATLOG_OBJECT_REACTION_NEUTRAL = nil
        end
        env.TooltipDataProcessor = {AddTooltipPostCall = function(kind, callback)
            assert(kind == 2)
            table.insert(callbacks, callback)
        end}
    else
        env.C_Seasons = {GetActiveSeason = function() return 0 end}
        env.GetSpellTexture = texture
    end
    env.C_Timer = {After = function(seconds, callback)
        assert(seconds == 5)
        table.insert(timers, callback)
    end}
    local lib = {}
    function lib:Create_UIDropDownMenu() return env.CreateFrame("Frame") end
    function lib:UIDropDownMenu_Initialize(frame, callback) callback(frame) end
    function lib:UIDropDownMenu_CreateInfo() return {} end
    function lib:UIDropDownMenu_AddButton() end
    function lib:UIDropDownMenu_SetWidth(frame, value) frame:SetWidth(value) end
    function lib:UIDropDownMenu_SetText(frame, value) frame:SetText(value) end
    function lib:UIDropDownMenu_SetAnchor() end
    env.LibStub = {GetLibrary = function() return lib end}
    env.Settings = {
        RegisterCanvasLayoutCategory = function(panel) return panel end,
        RegisterAddOnCategory = function(panel) assert(panel.name == "NpcAbilitiesForever") end,
    }
    env.NpcAbilitiesOptions = {DELAYED_TOOLTIP_LOADING = delayed, SELECTED_LANGUAGE = "de"}
    env.SlashCmdList = {}
    env.UISpecialFrames = {}
    local function load(path)
        local chunk = assert(loadfile(path))
        setfenv(chunk, env)(addonName, addonNamespace)
    end
    load("Database/npcs.lua")
    load("Database/abilities.lua")
    load("Database/Abilities/deDE.lua")
    load("Database/priorities.lua")
    load("Localization/Translations.lua")
    load("Frames/NpcAbilitiesForeverOptionsFrame.lua")
    load("Frames/NpcAbilitiesForeverDebug.lua")
    load("NpcAbilitiesForever.lua")
    local function event(name, ...)
        for _, frame in ipairs(frames) do
            if frame.events[name] then frame.scripts.OnEvent(frame, name, ...) end
        end
    end
    local function hookCount() return #callbacks + (env.GameTooltip.hookCount or 0) end
    event("ADDON_LOADED", "UnrelatedAddon")
    assert(hookCount() == 0)
    event("ADDON_LOADED", addonName)
    assert(hookCount() == (delayed and 0 or 1))
    event("PLAYER_LOGIN")
    for _, timer in ipairs(timers) do timer() end
    assert(hookCount() == 1, "Tooltip callback must be registered once")
    event("ADDON_LOADED", addonName)
    assert(hookCount() == 1, "Duplicate tooltip callback")
    assert(env.NpcAbilitiesForeverDebugFrame and env.SlashCmdList.NPCABILITIESFOREVERDEBUG, "In-game debug window not registered")
    env.SlashCmdList.NPCABILITIESFOREVERDEBUG("")
    assert(env.NpcAbilitiesForeverDebugFrame.shown, "Debug slash command did not open window")
    env.SlashCmdList.NPCABILITIESFOREVERDEBUG("")
    assert(not env.NpcAbilitiesForeverDebugFrame.shown, "Debug slash command did not close window")
    local function tooltip(tooltipGuid, frame)
        env.GameTooltip.lines = {}
        if env.GameTooltip.scripts.OnTooltipCleared then
            env.GameTooltip.scripts.OnTooltipCleared(env.GameTooltip)
        end
        if modern then
            callbacks[1](frame or env.GameTooltip, {guid = tooltipGuid})
        else
            env.GameTooltip.scripts.OnTooltipSetUnit(env.GameTooltip)
        end
        return table.concat(env.GameTooltip.lines, "\n")
    end
    if savedData then
        env.NpcAbilitiesOptions.ABILITY_DISPLAY_LOCATION = "both"
        guid = "Creature-0-1-0-1-88880001-0000000002"
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
        guid = "Creature-0-1-0-1-270589-0000000001"
        assert(tooltip(guid):find("Forever ability", 1, true), "New NPC was not found")
    else
        assert(tooltip(guid):find(expected, 1, true), "Forever overlay changed Classic display")
    end

    for _, unknown in ipairs({"Creature-0-1-0-1-999999999-1", "Player-0-30", "invalid", secret}) do
        guid = unknown
        assert(tooltip(guid) == "", "Unknown/restricted unit received abilities")
        event("PLAYER_TARGET_CHANGED")
        assert(not env.NpcAbilitiesForeverTargetFrame.shown)
    end
    guid = nil
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

    guid = "Creature-0-1-0-1-88880001-0000000001"
    event("PLAYER_TARGET_CHANGED")
    env.GameTooltip:Show()
    tooltip(guid)
    local function scan(spells)
        env.C_DamageMeter.combatSpells = spells
        event("DAMAGE_METER_COMBAT_SESSION_UPDATED")
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
    clientLocale = "zhCN"
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
