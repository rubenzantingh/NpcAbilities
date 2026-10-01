-- Minimal WoW API simulation; it does not emulate protected client values or UI rendering.
return function(modern, addonName, delayed, missingIcon, savedData, config)
    config = config or {}
    local env = setmetatable({}, {__index = _G})
    env._G = env
    local addonNamespace = {}
    local frames, callbacks, timers = {}, {}, {}
    local clientLocale = config.locale or "deDE"
    local combat = false
    local currentSession = 0
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
        if self.scripts.OnTooltipCleared then self.scripts.OnTooltipCleared(self) end
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
    env.UnitAffectingCombat = function() return combat end
    env.InCombatLockdown = function() return combat end
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
            DamageMeterType = {DamageTaken = 7, EnemyDamageTaken = 10},
            DamageMeterSessionType = {Current = 1, Overall = 2},
        }
        env.C_DamageMeter = {
            GetCombatSessionFromID = function(sessionID, meterType)
                assert(not combat, "Damage Meter was read during combat")
                if meterType == 10 then
                    return {combatSources = {{name = "Known NPC", sourceCreatureID = 88880001}}}
                end
                return {combatSources = {{sourceGUID = "Player-1-1", isLocalPlayer = true}}}
            end,
            GetCombatSessionSourceFromID = function()
                assert(not combat, "Damage Meter spells were read during combat")
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
    env.NpcAbilitiesOptions = config.options or {DELAYED_TOOLTIP_LOADING = delayed, SELECTED_LANGUAGE = "de"}
    if config.fresh then env.NpcAbilitiesOptions = nil end
    env.SlashCmdList = {}
    env.UISpecialFrames = {}
    local function load(path)
        local chunk = assert(loadfile(path))
        setfenv(chunk, env)(addonName, addonNamespace)
    end
    load("Database/npcs.lua")
    load("Database/abilities.lua")
    for _, filename in ipairs({"enUS", "deDE", "esES", "frFR", "ptBR", "ruRU", "koKR", "zhCN"}) do
        load("Database/Abilities/" .. filename .. ".lua")
    end
    if config.fullDatabase then load("Database/forever.lua") end
    load("Database/priorities.lua")
    load("Localization/Translations.lua")
    load("Frames/NpcAbilitiesForeverOptionsFrame.lua")
    load("Frames/NpcAbilitiesForeverDebug.lua")
    load("NpcAbilitiesForeverCollector.lua")
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
    local function flushTimers()
        local iterations = 0
        while #timers > 0 do
            iterations = iterations + 1
            assert(iterations < 20, "Timers did not stop")
            local batch = timers
            timers = {}
            for _, timer in ipairs(batch) do timer() end
        end
    end
    flushTimers()
    assert(hookCount() == 1, "Tooltip callback must be registered once")
    event("PLAYER_LOGIN")
    flushTimers()
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
    return {env = env, event = event, tooltip = tooltip, frames = frames, addonNamespace = addonNamespace,
        getGuid = function() return guid end,
        setGuid = function(value) guid = value end,
        setLocale = function(value) clientLocale = value end,
        setCombat = function(value) combat = value end,
        flushTimers = flushTimers,
        scan = function(spells)
            env.C_DamageMeter.combatSpells = spells
            currentSession = currentSession + 1
            combat = true
            event("DAMAGE_METER_COMBAT_SESSION_UPDATED", 7, currentSession)
            flushTimers()
            combat = false
            event("PLAYER_REGEN_ENABLED")
            flushTimers()
        end,
    }
end
