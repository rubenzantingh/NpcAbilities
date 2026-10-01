local _, addon = ...
local Collector = {}
addon.Collector = Collector

local frame = CreateFrame("Frame")
local enabled, available, scheduled = false, false, false
local generation = 0
local pending, processed, order = {}, {}, {}
local observe, statusChanged
local MAX_SESSIONS = 20

local function Public(value)
    return not (issecretvalue and issecretvalue(value))
end

local function ValidID(value)
    return Public(value) and type(value) == "number" and value > 0
        and value < math.huge and value == math.floor(value)
end

local function InCombat()
    return (UnitAffectingCombat and UnitAffectingCombat("player"))
        or (InCombatLockdown and InCombatLockdown())
end

local function Status()
    local count = 0
    for _ in pairs(pending) do count = count + 1 end
    if statusChanged then statusChanged(enabled, available, count) end
end

local function Log(english, german)
    addon.Debug.AddLine("DAMAGE_METER: " .. addon.Debug.Localize(english, german))
end

local function Sources(sessionID, meterType)
    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, meterType)
    if not ok or not Public(session) or type(session) ~= "table" then return nil end
    local sources = session.combatSources
    if Public(sources) and type(sources) == "table" then return sources end
end

local function ReadSession(sessionID)
    local types = Enum.DamageMeterType
    local enemies = Sources(sessionID, types.EnemyDamageTaken)
    local victims = Sources(sessionID, types.DamageTaken)
    if not enemies or not victims then return false end

    -- Names are only a join inside this specific session, never a global NPC key.
    -- More than one creature ID for a name makes the join ambiguous.
    local byName = {}
    for _, enemy in ipairs(enemies) do
        if Public(enemy) and type(enemy) == "table" then
            local name, id = enemy.name, enemy.sourceCreatureID
            if not ValidID(id) and Public(enemy.sourceGUID) and type(enemy.sourceGUID) == "string" then
                id = tonumber(enemy.sourceGUID:match("^Creature%-[^-]+%-[^-]+%-[^-]+%-[^-]+%-(%d+)%-"))
            end
            if Public(name) and type(name) == "string" and name ~= "" then
                local key = name:lower()
                if not ValidID(id) or byName[key] == false or (byName[key] and byName[key].id ~= id) then
                    byName[key] = false
                else
                    byName[key] = {id = id, name = name}
                end
            end
        end
    end

    local seen = processed[sessionID] or {}
    processed[sessionID] = seen
    local complete = true
    for _, victim in ipairs(victims) do
        if Public(victim) and type(victim) == "table" then
            local guid = Public(victim.sourceGUID) and victim.sourceGUID or nil
            local id = Public(victim.sourceCreatureID) and victim.sourceCreatureID or nil
            local ok, container = pcall(C_DamageMeter.GetCombatSessionSourceFromID,
                sessionID, types.DamageTaken, guid, id)
            local spells = ok and Public(container) and type(container) == "table" and container.combatSpells
            if Public(spells) and type(spells) == "table" then
                for _, spell in ipairs(spells) do
                    if Public(spell) and type(spell) == "table" and ValidID(spell.spellID) then
                        local details = spell.combatSpellDetails
                        if Public(details) and type(details) == "table" and Public(details.unitName)
                            and type(details.unitName) == "string" then
                            local name = details.unitName
                            local npc = byName[name:lower()]
                            local isPet = not Public(details.isPet) or details.isPet == true
                            local isMob = Public(details.isMob) and details.isMob ~= false
                            if npc and not isPet and isMob then
                                local key = npc.id .. ":" .. spell.spellID
                                if not seen[key] then
                                    local spellName = Public(spell.spellName) and spell.spellName or nil
                                    -- Successful observations are cached; missing metadata can be retried.
                                    if observe(npc.id, npc.name, spell.spellID, spellName, sessionID) then
                                        seen[key] = true
                                    else
                                        complete = false
                                    end
                                end
                            elseif not isPet and isMob then
                                complete = false
                                local key = "missing:" .. name .. ":" .. spell.spellID
                                if not seen[key] then
                                    seen[key] = true
                                    Log("session " .. sessionID .. ": skipped spell " .. spell.spellID .. " from '" .. name .. "' (no unique session NPC ID)",
                                        "Sitzung " .. sessionID .. ": Zauber " .. spell.spellID .. " von '" .. name .. "' verworfen (keine eindeutige NPC-ID in dieser Sitzung)")
                                end
                            end
                        else
                            complete = false
                        end
                    end
                end
            else
                complete = false
            end
        end
    end
    return complete
end

local Schedule
Schedule = function()
    if scheduled or not enabled or not available or InCombat() or not next(pending) then return end
    scheduled = true
    local token = generation
    C_Timer.After(0.25, function()
        if token ~= generation then return end
        scheduled = false
        if not enabled or InCombat() then return end
        for sessionID, attempts in pairs(pending) do
            if ReadSession(sessionID) then
                pending[sessionID] = nil
            elseif attempts >= 2 then
                pending[sessionID] = nil
                Log("session " .. sessionID .. ": incomplete or restricted data; stopped after three attempts",
                    "Sitzung " .. sessionID .. ": unvollstaendige oder geschuetzte Daten; nach drei Versuchen beendet")
            else
                pending[sessionID] = attempts + 1
            end
        end
        Status()
        Schedule()
    end)
end

local function Reset()
    generation = generation + 1
    scheduled = false
    pending, processed, order = {}, {}, {}
end

frame:SetScript("OnEvent", function(_, event, meterType, sessionID)
    if event == "DAMAGE_METER_RESET" then
        Reset()
        Status()
    elseif event == "PLAYER_REGEN_ENABLED" then
        Schedule()
    elseif event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
        if not Public(meterType) or (meterType ~= Enum.DamageMeterType.DamageTaken
            and meterType ~= Enum.DamageMeterType.EnemyDamageTaken) or not ValidID(sessionID) then return end
        if not processed[sessionID] then
            processed[sessionID] = {}
            table.insert(order, sessionID)
            if #order > MAX_SESSIONS then
                local expired = table.remove(order, 1)
                pending[expired], processed[expired] = nil, nil
            end
        end
        pending[sessionID] = pending[sessionID] or 0
        Status()
        Schedule()
    end
end)

function Collector.SetEnabled(value)
    enabled = value ~= false
    Reset()
    frame:UnregisterAllEvents()
    if enabled and available then
        frame:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        frame:RegisterEvent("DAMAGE_METER_RESET")
    end
    Status()
end

function Collector.Initialize(isForever, value, callback, onStatus)
    observe, statusChanged = callback, onStatus
    available = isForever and C_DamageMeter ~= nil
        and type(C_DamageMeter.GetCombatSessionFromID) == "function"
        and type(C_DamageMeter.GetCombatSessionSourceFromID) == "function"
        and Enum and Enum.DamageMeterType
        and type(Enum.DamageMeterType.DamageTaken) == "number"
        and type(Enum.DamageMeterType.EnemyDamageTaken) == "number"
        and C_Timer and type(C_Timer.After) == "function" or false
    Collector.SetEnabled(value)
end
