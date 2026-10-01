local addonName, addon = ...
local Debug = addon and addon.Debug
local npcAbilitiesFrame = CreateFrame("Frame")
local hotkeyButtonPressed = false
local hideAbilitiesHotkeyButtonPressed = false
local seasonId = C_Seasons and C_Seasons.GetActiveSeason and C_Seasons.GetActiveSeason()
local checkForHotkeyReleased = false
local interfaceVersion = select(4, GetBuildInfo())
local isForever = interfaceVersion >= 16000 and interfaceVersion < 17000
local learnedData
local damageMeterListenerRegistered = false
local liveDataCollectionEnabled = true
local collectionEventsRegistered = false
local watchedNameplateCount = 0
local watchedUnits = {}
local observedNpcNames = {}
local damageMeterFirstEventLogged = false
local lastDecoratedTooltipNpcId

local function RefreshDebugWindow()
    if not Debug then return end
    Debug.SetStatus({
        build = GetBuildInfo(),
        interfaceVersion = interfaceVersion,
        isForever = isForever,
        savedVariablesLoaded = type(NpcAbilitiesLearnedData) == "table",
        damageMeterAvailable = damageMeterListenerRegistered,
        collectionEnabled = liveDataCollectionEnabled,
        watchedNameplateCount = watchedNameplateCount,
    })
end

local function DebugText(english, german)
    if Debug and Debug.Localize then return Debug.Localize(english, german) end
    return english
end

local function GetAbilityTexture(spellId)
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellId)
    elseif GetSpellTexture then
        return GetSpellTexture(spellId)
    end
end

local function GetNpcIdFromGUID(guid)
    -- Restricted identities must not be compared or split in the modern client.
    if issecretvalue and issecretvalue(guid) then return nil end
    if type(guid) ~= "string" then return nil end

    local unitType, _, _, _, _, npcId = strsplit("-", guid)
    if unitType == "Creature" then
        return tonumber(npcId)
    end
end

local priorityColors = {
    [1] = {hex = "ff0000", r = 1, g = 0, b = 0},
    [2] = {hex = "ff9900", r = 1, g = 0.6, b = 0},
    [3] = {hex = "ffcc00", r = 1, g = 0.8, b = 0},
    [4] = {hex = "00ff00", r = 0, g = 1, b = 0}
}

local targetAbilitiesFrame = CreateFrame("Frame", "NpcAbilitiesForeverTargetFrame", UIParent, "BackdropTemplate")
targetAbilitiesFrame:SetPoint("TOPLEFT", TargetFrame, "BOTTOMLEFT", 2.5, 5)
targetAbilitiesFrame:SetSize(200, 50)
targetAbilitiesFrame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
})
targetAbilitiesFrame:SetBackdropColor(0, 0, 0, 0.8)
targetAbilitiesFrame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
targetAbilitiesFrame:Hide()

local targetAbilitiesContent = targetAbilitiesFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
targetAbilitiesContent:SetPoint("TOPLEFT", targetAbilitiesFrame, "TOPLEFT", 8, -8)
targetAbilitiesContent:SetPoint("RIGHT", targetAbilitiesFrame, "RIGHT", -8, 0)
targetAbilitiesContent:SetJustifyH("LEFT")
targetAbilitiesContent:SetJustifyV("TOP")
targetAbilitiesContent:SetWordWrap(true)
targetAbilitiesContent:SetNonSpaceWrap(true)

local function GetAddonLocaleCode(locale)
    local language = (locale or GetLocale()):sub(1, 2):lower()
    return language == "zh" and "cn" or language
end

local function GetDataByID(dataType, dataId)
    local data = _G[dataType]
    if not data then return nil end

    local convertedId = tonumber(dataId)
    if not convertedId then return nil end

    if dataType == "NpcAbilitiesNpcData" then
        local foreverData = isForever and _G["NpcAbilitiesForeverData"]
        local npc = (foreverData and foreverData.npcs[convertedId]) or data[convertedId]
        local learned = learnedData and learnedData.npcs[convertedId]
        if learned then
            local result = {classic_spell_ids = {}, sod_spell_ids = npc and npc.sod_spell_ids or {}}
            local seen, additions = {}, {}
            for _, spellId in ipairs(npc and npc.classic_spell_ids or {}) do
                table.insert(result.classic_spell_ids, spellId)
                seen[spellId] = true
            end
            for spellId in pairs(learned.spells) do
                if not seen[spellId] then table.insert(additions, spellId) end
            end
            table.sort(additions)
            for _, spellId in ipairs(additions) do table.insert(result.classic_spell_ids, spellId) end
            return result
        end
        return npc
    else
        local languageCode = NpcAbilitiesOptions["SELECTED_LANGUAGE"]
        local foreverData = isForever and _G["NpcAbilitiesForeverData"]
        local baseAbility = (data[languageCode] and data[languageCode][convertedId])
            or (data.en and data.en[convertedId])
        local learnedAbility
        if learnedData then
            -- Use learned metadata to fill gaps in the downloaded spell records.
            local localized = learnedData.abilities[languageCode]
            local client = learnedData.abilities[GetAddonLocaleCode()]
            local english = learnedData.abilities.en
            learnedAbility = (localized and localized[convertedId])
                or (client and client[convertedId]) or (english and english[convertedId])
            if not learnedAbility then
                for _, language in pairs(learnedData.abilities) do
                    if language[convertedId] then learnedAbility = language[convertedId]; break end
                end
            end
        end
        if foreverData then
            local localized = foreverData.abilities[languageCode]
            local english = foreverData.abilities.en
            local ability = (localized and localized[convertedId]) or (english and english[convertedId])
            if ability or baseAbility or learnedAbility then
                local result = {}
                for _, field in ipairs({"name", "description", "mechanic", "range", "cast_time", "cooldown", "dispel_type"}) do
                    local value = ability and ability[field]
                    if value == nil or value == "" then value = baseAbility and baseAbility[field] end
                    if value == nil or value == "" then value = learnedAbility and learnedAbility[field] end
                    result[field] = value
                end
                return result
            end
        end
        if baseAbility then
            if not learnedAbility then return baseAbility end
            local result = {}
            for _, field in ipairs({"name", "description", "mechanic", "range", "cast_time", "cooldown", "dispel_type"}) do
                local value = baseAbility[field]
                if value == nil or value == "" then value = learnedAbility[field] end
                result[field] = value
            end
            return result
        end
        return learnedAbility
    end

    return nil
end

local function GetAbilityNameKey(name, spellId)
    if type(name) ~= "string" then return tostring(spellId) end
    local plainName = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    plainName = plainName:gsub("%s+", " "):match("^%s*(.-)%s*$")
    return plainName:lower()
end

local genericAttackSpellNames = {
    ["attack"] = true,
    ["auto attack"] = true,
    ["melee"] = true,
    ["melee attack"] = true,
    ["angreifen"] = true,
    ["nahkampfangriff"] = true,
    ["automatischer angriff"] = true,
    ["ataque"] = true,
    ["ataque automático"] = true,
    ["ataque automatico"] = true,
    ["attaque"] = true,
    ["attaque automatique"] = true,
    ["ataque corpo a corpo"] = true,
    ["攻擊"] = true,
    ["攻击"] = true,
    ["공격"] = true,
}

local genericAttackSpellCache = {}

local function IsGenericAttackSpell(spellId, spellName)
    if spellId == 6603 then return true end
    local nameKey = GetAbilityNameKey(spellName, spellId)
    if genericAttackSpellNames[nameKey] then return true end
    if type(spellId) ~= "number" then return false end
    if genericAttackSpellCache[spellId] ~= nil then return genericAttackSpellCache[spellId] end
    local clientSpellName
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellId)
        if ok and type(info) == "table" and not (issecretvalue and issecretvalue(info.name)) then clientSpellName = info.name end
    elseif type(GetSpellInfo) == "function" then
        local ok, name = pcall(GetSpellInfo, spellId)
        if ok then clientSpellName = name end
    end
    if type(clientSpellName) == "string" and genericAttackSpellNames[GetAbilityNameKey(clientSpellName, spellId)] then
        genericAttackSpellCache[spellId] = true
        return true
    end
    if C_Spell and type(C_Spell.IsRangedAutoAttackSpell) == "function" then
        local ok, isAutoAttack = pcall(C_Spell.IsRangedAutoAttackSpell, spellId)
        if ok and isAutoAttack == true then return true end
    end
    genericAttackSpellCache[spellId] = false
    return false
end

local function GetAbilityPriority(spellId)
    local priorityData = _G['NpcAbilitiesPriorityData']
    if priorityData then
        return priorityData[spellId]
    end
    return nil
end

local function SortAbilitiesByPriority(abilities)
    table.sort(abilities, function(a, b)
        local priorityA = GetAbilityPriority(a.id) or 4
        local priorityB = GetAbilityPriority(b.id) or 4
        return priorityA < priorityB
    end)
end

local function AddAbilityLinesToGameTooltip(id, name, description, mechanic, range, castTime, cooldown, dispelType, addedAbilityLine)
    if not addedAbilityLine then
        GameTooltip:AddLine(" ")
    end

    local options = NpcAbilitiesOptions
    local selectedLanguage = options["SELECTED_LANGUAGE"]
    local translations = _G["NpcAbilitiesTranslations"][selectedLanguage]["game"]

    local texture = GetAbilityTexture(id)
    local icon = texture and ("|T" .. texture .. ":12:12:0:0:64:64:4:60:4:60|t") or ""
    local abilityNameText = icon .. " " .. name

    local function appendTitleInfo(display, value, mode, label)
        if value ~= "" and options[display] then
            local text = " - " .. value
            if options[mode] == "title" then
                abilityNameText = abilityNameText .. text
            end
        end
    end

    appendTitleInfo("DISPLAY_ABILITY_MECHANIC", mechanic, "SELECTED_ABILITY_MECHANIC_DISPLAY_MODE", "mechanicText")
    appendTitleInfo("DISPLAY_ABILITY_RANGE", range, "SELECTED_ABILITY_RANGE_DISPLAY_MODE", "rangeText")
    appendTitleInfo("DISPLAY_ABILITY_CAST_TIME", castTime, "SELECTED_ABILITY_CAST_TIME_DISPLAY_MODE", "castTimeText")
    appendTitleInfo("DISPLAY_ABILITY_COOLDOWN", cooldown, "SELECTED_ABILITY_COOLDOWN_DISPLAY_MODE", "cooldownText")
    appendTitleInfo("DISPLAY_ABILITY_DISPEL_TYPE", dispelType, "SELECTED_ABILITY_DISPEL_TYPE_DISPLAY_MODE", "dispelTypeText")

    if options["DISPLAY_PRIORITY_INDICATORS"] then
        local priority = GetAbilityPriority(id) or 4
        local colors = priorityColors[priority]
        GameTooltip:AddLine(abilityNameText, colors.r, colors.g, colors.b)
    else
        GameTooltip:AddLine(abilityNameText)
    end

    if hotkeyButtonPressed then
        local function addSeparateLine(display, value, mode, labelKey)
            if value ~= "" and options[display] and options[mode] == "separate" then
                GameTooltip:AddLine(translations[labelKey] .. ": " .. value, 1, 1, 1, true)
            end
        end

        addSeparateLine("DISPLAY_ABILITY_MECHANIC", mechanic, "SELECTED_ABILITY_MECHANIC_DISPLAY_MODE", "mechanicText")
        addSeparateLine("DISPLAY_ABILITY_RANGE", range, "SELECTED_ABILITY_RANGE_DISPLAY_MODE", "rangeText")
        addSeparateLine("DISPLAY_ABILITY_CAST_TIME", castTime, "SELECTED_ABILITY_CAST_TIME_DISPLAY_MODE", "castTimeText")
        addSeparateLine("DISPLAY_ABILITY_COOLDOWN", cooldown, "SELECTED_ABILITY_COOLDOWN_DISPLAY_MODE", "cooldownText")
        addSeparateLine("DISPLAY_ABILITY_DISPEL_TYPE", dispelType, "SELECTED_ABILITY_DISPEL_TYPE_DISPLAY_MODE", "dispelTypeText")

        GameTooltip:AddLine(description, 1, 1, 1, true)
    end
end

local function UpdateTargetFrameAbilities()
    local displayLocation = NpcAbilitiesOptions["ABILITY_DISPLAY_LOCATION"] or "both"
    if displayLocation == "tooltip" then
        targetAbilitiesFrame:Hide()
        return
    end

    local hotkeyMode = NpcAbilitiesOptions["SELECTED_HOTKEY_MODE"]
    if (hotkeyMode == "toggle_and_hide" or hotkeyMode == "hold_and_hide") and not hotkeyButtonPressed then
        targetAbilitiesFrame:Hide()
        return
    end

    if not UnitExists("target") then
        targetAbilitiesFrame:Hide()
        return
    end

    local inInstance, _ = IsInInstance()
    if hideAbilitiesHotkeyButtonPressed or (inInstance and NpcAbilitiesOptions["HIDE_ABILITIES_IN_INSTANCE"]) then
        targetAbilitiesFrame:Hide()
        return
    end

    local npcId = GetNpcIdFromGUID(UnitGUID("target"))
    if not npcId then
        targetAbilitiesFrame:Hide()
        return
    end

    local npcData = GetDataByID('NpcAbilitiesNpcData', npcId)
    if npcData == nil then
        targetAbilitiesFrame:Hide()
        return
    end

    local options = NpcAbilitiesOptions
    local selectedLanguage = options["SELECTED_LANGUAGE"]
    local abilities = {}
    local addedAbilityNames = {}

    for _, classicAbilityId in pairs(npcData.classic_spell_ids) do
        local classicAbilitiesData = GetDataByID('NpcAbilitiesAbilityData', classicAbilityId)

        if classicAbilitiesData ~= nil then
            local name = classicAbilitiesData.name

            local nameKey = GetAbilityNameKey(name, classicAbilityId)
            if not IsGenericAttackSpell(classicAbilityId, name) and not addedAbilityNames[nameKey] then
                addedAbilityNames[nameKey] = true
                table.insert(abilities, {
                    id = classicAbilityId,
                    name = name,
                    description = classicAbilitiesData.description or ""
                })
            end
        end
    end

    if #abilities == 0 then
        targetAbilitiesFrame:Hide()
        return
    end

    if options["DISPLAY_PRIORITY_INDICATORS"] then
        SortAbilitiesByPriority(abilities)
    end

    local lines = {}
    local hasDescriptions = false
    local translations = _G["NpcAbilitiesTranslations"][selectedLanguage]["game"]

    for _, ability in ipairs(abilities) do
        local texture = GetAbilityTexture(ability.id)
        local icon = texture and ("|T" .. texture .. ":14:14:0:0:64:64:4:60:4:60|t") or ""
        local line = icon .. " " .. ability.name

        if options["DISPLAY_PRIORITY_INDICATORS"] then
            local priority = GetAbilityPriority(ability.id) or 4
            local colors = priorityColors[priority]
            line = "|cff" .. colors.hex .. icon .. " " .. ability.name .. "|r"
        end

        table.insert(lines, line)

        if hotkeyButtonPressed and ability.description ~= "" then
            table.insert(lines, "|cffffffff" .. ability.description .. "|r")
        end

        if ability.description ~= "" then
            hasDescriptions = true
        end
    end

    if hasDescriptions and not hotkeyButtonPressed then
        if options["SELECTED_HOTKEY"] then
            local hotkey = options["SELECTED_HOTKEY"]
            local hotkeyText = "|cffaaaaaa(" .. translations["hotkeyExplanatoryTextOne"] .. " " .. hotkey .. " " .. translations["hotkeyExplanatoryTextTwo"] .. ")|r"
            table.insert(lines, hotkeyText)
        else
            table.insert(lines, "|cffaaaaaa(" .. translations["hotkeyNotBoundText"] .. ")|r")
        end
    end

    local text = table.concat(lines, "\n")
    local targetAbilitiesFrameBackDrop = targetAbilitiesFrame:GetBackdrop()

    local frameWidth = TargetFrame:GetWidth() - (targetAbilitiesFrame:GetBackdrop().edgeSize * 2) - 16
    targetAbilitiesFrame:SetWidth(frameWidth)
    targetAbilitiesContent:SetWidth(frameWidth - 16)
    targetAbilitiesContent:SetText(text)

    local textHeight = targetAbilitiesContent:GetStringHeight()
    targetAbilitiesFrame:SetHeight(textHeight + 16)
    targetAbilitiesFrame:Show()
end

local tooltipHookRegistered = false
local SetNpcAbilityData

local function RegisterTooltipHook()
    if tooltipHookRegistered then return end

    GameTooltip:HookScript("OnTooltipCleared", function()
        lastDecoratedTooltipNpcId = nil
    end)

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
            if tooltip == GameTooltip then
                SetNpcAbilityData(tooltip, data)
            end
        end)
    else
        GameTooltip:HookScript("OnTooltipSetUnit", SetNpcAbilityData)
    end
    tooltipHookRegistered = true
end

local function RefreshLearnedNpc(npcId)
    if GetNpcIdFromGUID(UnitGUID("target")) == npcId then
        UpdateTargetFrameAbilities()
    end
    if tooltipHookRegistered and GameTooltip:IsShown() then
        local _, unit = GameTooltip:GetUnit()
        if issecretvalue and issecretvalue(unit) then return end
        if unit and GetNpcIdFromGUID(UnitGUID(unit)) == npcId then
            -- Rebuild the unit tooltip so existing ability lines are not duplicated.
            GameTooltip:SetUnit(unit)
            GameTooltip:Show()
        end
    end
end

local function IsPublicSpellValue(value)
    return not (issecretvalue and issecretvalue(value))
end

local function FormatObservedSeconds(milliseconds, locale)
    if type(milliseconds) ~= "number" or not IsPublicSpellValue(milliseconds) or milliseconds < 0 then return nil end
    local text = string.format("%.1f", milliseconds / 1000):gsub("%.0$", "")
    if locale == "deDE" or locale == "frFR" or locale == "esES" or locale == "ptBR" then
        text = text:gsub("%.", ",")
    end
    if milliseconds == 0 then
        local instant = {deDE = "Sofort", enUS = "Instant", enGB = "Instant", esES = "Instantáneo", frFR = "Instantané", ptBR = "Instantâneo", ruRU = "Мгновенно", koKR = "즉시", zhCN = "瞬发", zhTW = "瞬發"}
        return instant[locale] or "Instant"
    end
    local units = {
        deDE = " Sekunden", enUS = " seconds", enGB = " seconds", esES = " segundos", frFR = " secondes",
        ptBR = " segundos", ruRU = " сек.", koKR = "초", zhCN = "秒", zhTW = "秒",
    }
    return text .. (units[locale] or " seconds")
end

local function FormatObservedRange(minRange, maxRange, locale)
    if type(minRange) ~= "number" or not IsPublicSpellValue(minRange) then minRange = 0 end
    if type(maxRange) ~= "number" or not IsPublicSpellValue(maxRange) then maxRange = 0 end
    if maxRange <= 0 and minRange <= 0 then return nil end
    local units = {
        deDE = " Meter", enUS = " yards", enGB = " yards", esES = " metros", frFR = " mètres",
        ptBR = " metros", ruRU = " м", koKR = "미터", zhCN = "码", zhTW = "碼",
    }
    local function numberText(value)
        local text = string.format("%.1f", value):gsub("%.0$", "")
        if locale == "deDE" or locale == "frFR" or locale == "esES" or locale == "ptBR" then
            text = text:gsub("%.", ",")
        end
        return text
    end
    local rangeText
    if minRange > 0 and maxRange > minRange then
        rangeText = numberText(minRange) .. "-" .. numberText(maxRange)
    else
        rangeText = numberText(maxRange > 0 and maxRange or minRange)
    end
    return rangeText .. (units[locale] or " yards")
end

local function GetObservedSpellMetadata(spellId, spellName)
    local locale = GetLocale()
    local metadata = {name = spellName}
    local info
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local ok, result = pcall(C_Spell.GetSpellInfo, spellId)
        if ok and type(result) == "table" and IsPublicSpellValue(result) then info = result end
    end

    local castTime, minRange, maxRange
    if info then
        if IsPublicSpellValue(info.name) and type(info.name) == "string" and info.name ~= "" then metadata.name = info.name end
        castTime, minRange, maxRange = info.castTime, info.minRange, info.maxRange
    end
    if type(GetSpellInfo) == "function"
        and (not IsPublicSpellValue(castTime) or type(castTime) ~= "number"
            or not IsPublicSpellValue(minRange) or type(minRange) ~= "number"
            or not IsPublicSpellValue(maxRange) or type(maxRange) ~= "number") then
        local ok, name, _, _, legacyCastTime, legacyMinRange, legacyMaxRange = pcall(GetSpellInfo, spellId)
        if ok then
            if (not metadata.name or metadata.name == "") and IsPublicSpellValue(name) and type(name) == "string" then
                metadata.name = name
            end
            if type(castTime) ~= "number" then castTime = legacyCastTime end
            if type(minRange) ~= "number" then minRange = legacyMinRange end
            if type(maxRange) ~= "number" then maxRange = legacyMaxRange end
        end
    end

    local description
    if C_Spell and type(C_Spell.GetSpellDescription) == "function" then
        local ok, value = pcall(C_Spell.GetSpellDescription, spellId)
        if ok and IsPublicSpellValue(value) and type(value) == "string" and value ~= "" then description = value end
    end
    if (not description or description == "") and type(GetSpellDescription) == "function" then
        local ok, value = pcall(GetSpellDescription, spellId)
        if ok and IsPublicSpellValue(value) and type(value) == "string" and value ~= "" then description = value end
    end
    metadata.description = description
    metadata.cast_time = FormatObservedSeconds(castTime, locale)
    metadata.range = FormatObservedRange(minRange, maxRange, locale)
    return metadata
end

local function StoreObservedSpell(npcId, sourceName, spellId, spellName, event, metadata)
    if type(spellId) ~= "number" or spellId <= 0 or spellId == math.huge or spellId ~= math.floor(spellId) then
        Debug.AddLine(event .. " | NPC " .. tostring(npcId) .. " | "
            .. DebugText("REJECTED: invalid spell ID", "VERWORFEN: keine gueltige Zauber-ID"))
        return
    end
    if type(spellName) ~= "string" or spellName == "" then
        Debug.AddLine(event .. " | NPC " .. tostring(npcId) .. " | " .. DebugText(
            "spell " .. spellId .. " | REJECTED: spell name unavailable",
            "Zauber " .. spellId .. " | VERWORFEN: Zaubername nicht verfuegbar"))
        return
    end
    if IsGenericAttackSpell(spellId, spellName) then
        Debug.AddLine(event .. " | NPC " .. tostring(npcId) .. " | " .. spellName .. " (" .. spellId .. ") | "
            .. DebugText("SKIPPED: generic attack", "uebersprungen: Standardangriff"))
        return
    end
    local alreadyLearned = learnedData.npcs[npcId]
    local associationKnown = alreadyLearned and alreadyLearned.spells[spellId]

    local changed = false
    metadata = metadata or GetObservedSpellMetadata(spellId, spellName)
    local language = GetAddonLocaleCode()
    learnedData.abilities[language] = learnedData.abilities[language] or {}
    local learnedAbility = learnedData.abilities[language][spellId]
    if type(learnedAbility) ~= "table" then
        learnedAbility = {}
        learnedData.abilities[language][spellId] = learnedAbility
    end
    local currentAbility = GetDataByID("NpcAbilitiesAbilityData", spellId)
    for _, field in ipairs({"name", "description", "mechanic", "range", "cast_time", "cooldown", "dispel_type"}) do
        local value = metadata[field]
        if (currentAbility == nil or currentAbility[field] == nil or currentAbility[field] == "")
            and learnedAbility[field] == nil and type(value) == "string" and value ~= "" then
            learnedAbility[field] = value
            changed = true
        end
    end
    local npc = GetDataByID("NpcAbilitiesNpcData", npcId)
    local known = false
    for _, knownId in ipairs(npc and npc.classic_spell_ids or {}) do
        if knownId == spellId then known = true; break end
    end
    if not associationKnown and not known then
        local learned = learnedData.npcs[npcId]
        if not learned then
            learned = {name = type(sourceName) == "string" and sourceName or nil, spells = {}}
            learnedData.npcs[npcId] = learned
        end
        learned.spells[spellId] = true
        changed = true
    end
    if changed then
        local outcome = (associationKnown or known)
            and DebugText("INFO UPDATED", "Infos ergaenzt")
            or DebugText("LEARNED", "GELERNT")
        Debug.AddLine(event .. " | NPC " .. tostring(npcId) .. " | " .. spellName .. " (" .. spellId .. ") | " .. outcome)
        RefreshLearnedNpc(npcId)
    else
        Debug.AddLine(event .. " | NPC " .. tostring(npcId) .. " | " .. spellName .. " (" .. spellId .. ") | "
            .. DebugText("already learned", "bereits gelernt"))
    end
end

local function CacheVisibleNpcName(unit)
    local npcId = GetNpcIdFromGUID(UnitGUID(unit))
    local npcName = UnitName(unit)
    local reaction = UnitReaction and UnitReaction("player", unit)
    if npcId and type(npcName) == "string" and not (issecretvalue and issecretvalue(npcName))
        and not (issecretvalue and issecretvalue(reaction))
        and (type(reaction) ~= "number" or (reaction >= 1 and reaction <= 4)) then
        observedNpcNames[npcName:lower()] = {id = npcId, name = npcName}
    end
end

local function TrackNpcUnit(unit)
    CacheVisibleNpcName(unit)
    if watchedUnits[unit] then return end
    watchedUnits[unit] = true
    if unit:match("^nameplate") then watchedNameplateCount = watchedNameplateCount + 1 end
    RefreshDebugWindow()
end

local function UntrackNpcUnit(unit)
    if not watchedUnits[unit] then return end
    watchedUnits[unit] = nil
    if unit:match("^nameplate") then watchedNameplateCount = math.max(0, watchedNameplateCount - 1) end
    RefreshDebugWindow()
end

-- WoW Forever hides combat-log payloads from regular addons, but the built-in
-- damage meter (also used by Details) exposes aggregated damage sessions. Read
-- the player's incoming-damage source list after each update and learn spell
-- IDs from NPC sources when the client makes those values inspectable.
local function LearnDamageMeterSpells()
    local damageMeter = C_DamageMeter
    local meterTypes = Enum and Enum.DamageMeterType
    local sessionTypes = Enum and Enum.DamageMeterSessionType
    if not damageMeter or type(damageMeter.GetCombatSessionFromType) ~= "function"
        or type(damageMeter.GetCombatSessionSourceFromType) ~= "function"
        or not meterTypes or not sessionTypes then
        return
    end

    local damageTaken = meterTypes.DamageTaken
    if type(damageTaken) ~= "number" then return end
    local sessions = {sessionTypes.Current, sessionTypes.Overall}
    local found = {}
    local function readable(value)
        return not (issecretvalue and issecretvalue(value))
    end

    -- The DamageTaken rows belong to the victim (usually the player). Details'
    -- source shows that the caster is recorded per spell in combatSpellDetails.
    -- Resolve that name back to a currently visible hostile NPC GUID.
    local npcByName = {}
    for name, npc in pairs(observedNpcNames) do npcByName[name] = npc end
    local function addNpcUnit(unit)
        if not UnitExists(unit) then return end
        local npcId = GetNpcIdFromGUID(UnitGUID(unit))
        local unitName = UnitName(unit)
        if not npcId or not readable(unitName) or type(unitName) ~= "string" then return end
        local reaction = UnitReaction and UnitReaction("player", unit)
        if readable(reaction) and type(reaction) == "number" and reaction >= 1 and reaction <= 4 then
            npcByName[unitName:lower()] = {id = npcId, name = unitName}
        end
    end
    addNpcUnit("target")
    addNpcUnit("focus")
    for unit in pairs(watchedUnits) do addNpcUnit(unit) end

    for _, sessionType in ipairs(sessions) do
        if type(sessionType) == "number" then
            local ok, session = pcall(damageMeter.GetCombatSessionFromType, sessionType, damageTaken)
            if ok and type(session) == "table" and readable(session.combatSources) then
                local sources = session.combatSources
                if type(sources) == "table" then
                    for index = 1, #sources do
                        local source = sources[index]
                        if type(source) == "table" then
                            local spellOk, spellContainer = pcall(
                                damageMeter.GetCombatSessionSourceFromType,
                                sessionType, damageTaken, source.sourceGUID, source.sourceCreatureID)
                            local spells = spellOk and type(spellContainer) == "table"
                                and spellContainer.combatSpells or nil
                            if type(spells) == "table" and readable(spells) then
                                for spellIndex = 1, #spells do
                                    local spell = spells[spellIndex]
                                    if type(spell) == "table" and readable(spell.spellID) then
                                        local spellId = spell.spellID
                                        local details = readable(spell.combatSpellDetails) and spell.combatSpellDetails or nil
                                        local casterName = details and readable(details.unitName) and details.unitName or nil
                                        if type(casterName) == "string" then
                                            local npc = npcByName[casterName:lower()]
                                            if npc then
                                                local spellName = readable(spell.spellName) and spell.spellName or nil
                                                if type(spellName) ~= "string" or spellName == "" then
                                                    local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellId)
                                                    spellName = spellInfo and spellInfo.name
                                                    if not spellName and GetSpellInfo then spellName = GetSpellInfo(spellId) end
                                                end
                                                if not readable(spellName) then spellName = nil end
                                                local metadata = GetObservedSpellMetadata(spellId, spellName)
                                                spellName = metadata.name or spellName
                                                if type(spellId) == "number" and type(spellName) == "string" and spellName ~= "" then
                                                    local key = npc.id .. ":" .. spellId
                                                    if not found[key] then
                                                        found[key] = true
                                                        StoreObservedSpell(npc.id, npc.name, spellId, spellName, "DAMAGE_METER", metadata)
                                                    end
                                                end
                                            elseif type(spellId) == "number" then
                                                local missingKey = casterName:lower() .. ":" .. spellId
                                                if not found[missingKey] then
                                                    found[missingKey] = true
                                                    Debug.AddLine("DAMAGE_METER: " .. DebugText(
                                                        "spell " .. spellId .. " from '" .. casterName .. "' found; NPC ID could not be matched",
                                                        "Zauber " .. spellId .. " von '" .. casterName .. "' erkannt, NPC-ID nicht zuordenbar"))
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local learningFrame = CreateFrame("Frame")
local collectionEvents = {
    "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED",
    "DAMAGE_METER_COMBAT_SESSION_UPDATED",
    "PLAYER_REGEN_ENABLED",
}

local function SetLiveDataCollectionEnabled(enabled)
    liveDataCollectionEnabled = enabled ~= false
    local shouldListen = isForever and liveDataCollectionEnabled and damageMeterListenerRegistered
    if shouldListen ~= collectionEventsRegistered then
        collectionEventsRegistered = shouldListen
        for _, event in ipairs(collectionEvents) do
            if shouldListen then learningFrame:RegisterEvent(event) else learningFrame:UnregisterEvent(event) end
        end
        if shouldListen then
            TrackNpcUnit("target")
            TrackNpcUnit("focus")
            for index = 1, 40 do
                local unit = "nameplate" .. index
                if UnitExists(unit) then TrackNpcUnit(unit) end
            end
        else
            watchedUnits = {}
            observedNpcNames = {}
            watchedNameplateCount = 0
        end
    end
    RefreshDebugWindow()
end

if addon then addon.SetLiveDataCollectionEnabled = SetLiveDataCollectionEnabled end

learningFrame:RegisterEvent("ADDON_LOADED")
learningFrame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == addonName then
        if isForever then
            if type(NpcAbilitiesLearnedData) ~= "table" then NpcAbilitiesLearnedData = {} end
            learnedData = NpcAbilitiesLearnedData
            if type(learnedData.npcs) ~= "table" then learnedData.npcs = {} end
            if type(learnedData.abilities) ~= "table" then learnedData.abilities = {} end
            learnedData.version = 1
            damageMeterListenerRegistered = C_DamageMeter ~= nil
                and type(C_DamageMeter.GetCombatSessionFromType) == "function"
                and type(C_DamageMeter.GetCombatSessionSourceFromType) == "function"
                and Enum ~= nil and Enum.DamageMeterType ~= nil and Enum.DamageMeterSessionType ~= nil
        end
        learningFrame:UnregisterEvent("ADDON_LOADED")
        SetLiveDataCollectionEnabled(NpcAbilitiesOptions.LIVE_DATA_COLLECTION_ENABLED)
    elseif collectionEventsRegistered and learnedData and event == "NAME_PLATE_UNIT_ADDED" then
        TrackNpcUnit(name)
    elseif collectionEventsRegistered and event == "NAME_PLATE_UNIT_REMOVED" then
        UntrackNpcUnit(name)
    elseif collectionEventsRegistered and learnedData and (event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED") then
        TrackNpcUnit(event == "PLAYER_TARGET_CHANGED" and "target" or "focus")
    elseif collectionEventsRegistered and learnedData
        and (event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" or event == "PLAYER_REGEN_ENABLED") then
        local inCombat = (UnitAffectingCombat and UnitAffectingCombat("player")) or (InCombatLockdown and InCombatLockdown())
        if not inCombat then
            if event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" and not damageMeterFirstEventLogged then
                damageMeterFirstEventLogged = true
                Debug.AddLine("DAMAGE_METER: " .. DebugText("session updated after combat", "Sitzung nach dem Kampf aktualisiert"))
            end
            LearnDamageMeterSpells()
        end
    end
end)

local targetEventFrame = CreateFrame("Frame")
targetEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
targetEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
targetEventFrame:RegisterEvent("PLAYER_LOGIN")
targetEventFrame:RegisterEvent("ADDON_LOADED")
targetEventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        if NpcAbilitiesOptions["ABILITY_DISPLAY_LOCATION"] == nil then
            NpcAbilitiesOptions["ABILITY_DISPLAY_LOCATION"] = "both"
        end

        if not NpcAbilitiesOptions["DELAYED_TOOLTIP_LOADING"] then
            RegisterTooltipHook()
        end
    elseif event == "PLAYER_LOGIN" then
        if NpcAbilitiesOptions["DELAYED_TOOLTIP_LOADING"] then
            C_Timer.After(5, RegisterTooltipHook)
        else
            RegisterTooltipHook()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateTargetFrameAbilities()
    elseif event == "PLAYER_TARGET_CHANGED" then
        UpdateTargetFrameAbilities()
    end
end)

SetNpcAbilityData = function(tooltip, data)
    local displayLocation = NpcAbilitiesOptions["ABILITY_DISPLAY_LOCATION"] or "both"
    if displayLocation == "target_frame" then
        return
    end

    local hotkeyMode = NpcAbilitiesOptions["SELECTED_HOTKEY_MODE"]
    if (hotkeyMode == "toggle_and_hide" or hotkeyMode == "hold_and_hide") and not hotkeyButtonPressed then
        return
    end

    local inInstance, _ = IsInInstance()

    if hideAbilitiesHotkeyButtonPressed or (inInstance and NpcAbilitiesOptions["HIDE_ABILITIES_IN_INSTANCE"]) then
        return
    end

    local npcId = GetNpcIdFromGUID(data and data.guid)
    if not npcId then
        local _, unitId = GameTooltip:GetUnit()
        if issecretvalue and issecretvalue(unitId) then return end
        if unitId then
            npcId = GetNpcIdFromGUID(UnitGUID(unitId))
        end
    end
    if not npcId then return end
    if lastDecoratedTooltipNpcId == npcId then return end

    local npcData = GetDataByID('NpcAbilitiesNpcData', npcId)

    if npcData == nil then
       return
    end

    local abilities = {}
    local addedAbilityNames = {}

    if seasonId == 2 then
        for _, sodAbilityId in pairs(npcData.sod_spell_ids) do
            local sodAbilitiesData = GetDataByID('NpcAbilitiesAbilityData', sodAbilityId)

            if sodAbilitiesData ~= nil then
                local sodAbilityName = sodAbilitiesData.name
                local nameKey = GetAbilityNameKey(sodAbilityName, sodAbilityId)
                if not IsGenericAttackSpell(sodAbilityId, sodAbilityName) and not addedAbilityNames[nameKey] then
                    addedAbilityNames[nameKey] = true
                    table.insert(abilities, {
                        id = sodAbilityId,
                        name = sodAbilityName,
                        description = sodAbilitiesData.description or "",
                        mechanic = sodAbilitiesData.mechanic or "",
                        range = sodAbilitiesData.range or "",
                        cast_time = sodAbilitiesData.cast_time or "",
                        cooldown = sodAbilitiesData.cooldown or "",
                        dispel_type = sodAbilitiesData.dispel_type or ""
                    })
                end
            end
        end
    end

    for _, classicAbilityId in pairs(npcData.classic_spell_ids) do
        local classicAbilitiesData = GetDataByID('NpcAbilitiesAbilityData', classicAbilityId)

        if classicAbilitiesData ~= nil then
            local classicAbilityName = classicAbilitiesData.name

            local nameKey = GetAbilityNameKey(classicAbilityName, classicAbilityId)
            if not IsGenericAttackSpell(classicAbilityId, classicAbilityName) and not addedAbilityNames[nameKey] then
                addedAbilityNames[nameKey] = true
                table.insert(abilities, {
                    id = classicAbilityId,
                    name = classicAbilityName,
                    description = classicAbilitiesData.description or "",
                    mechanic = classicAbilitiesData.mechanic or "",
                    range = classicAbilitiesData.range or "",
                    cast_time = classicAbilitiesData.cast_time or "",
                    cooldown = classicAbilitiesData.cooldown or "",
                    dispel_type = classicAbilitiesData.dispel_type or ""
                })
            end
        end
    end

    if #abilities == 0 then
        return
    end

    -- TooltipDataProcessor may report the same unit more than once during a
    -- single tooltip build. Keep this render idempotent until the tooltip clears.
    lastDecoratedTooltipNpcId = npcId

    if NpcAbilitiesOptions["DISPLAY_PRIORITY_INDICATORS"] then
        SortAbilitiesByPriority(abilities)
    end

    local addedAbilityLine = false
    local addedAbilityLineWithDescription = false

    for _, ability in ipairs(abilities) do
        AddAbilityLinesToGameTooltip(ability.id, ability.name, ability.description, ability.mechanic, ability.range, ability.cast_time, ability.cooldown, ability.dispel_type, addedAbilityLine)
        addedAbilityLine = true

        if ability.description ~= '' then
            addedAbilityLineWithDescription = true
        end
    end

    local selectedLanguage = NpcAbilitiesOptions["SELECTED_LANGUAGE"]

    if addedAbilityLineWithDescription and not hotkeyButtonPressed and NpcAbilitiesOptions["SELECTED_HOTKEY"] then
        local hotkey = NpcAbilitiesOptions["SELECTED_HOTKEY"]
        local hotkeyExplanatoryText = "(" .. _G["NpcAbilitiesTranslations"][selectedLanguage]["game"]["hotkeyExplanatoryTextOne"] .. " " .. hotkey .. " " ..  _G["NpcAbilitiesTranslations"][selectedLanguage]["game"]["hotkeyExplanatoryTextTwo"] .. ")"
        GameTooltip:AddLine(hotkeyExplanatoryText, 0.8, 0.8, 0.8)
    end

    if addedAbilityLineWithDescription and not hotkeyButtonPressed and not NpcAbilitiesOptions["SELECTED_HOTKEY"] then
        GameTooltip:AddLine("(" .. _G["NpcAbilitiesTranslations"][selectedLanguage]["game"]["hotkeyNotBoundText"] .. ")", 0.8, 0.8, 0.8)
    end
end

local function CheckHotkeyState()
    local hotkey = NpcAbilitiesOptions["SELECTED_HOTKEY"]

    if not IsKeyDown(hotkey) then
        checkForHotkeyReleased = false
        hotkeyButtonPressed = false
        GameTooltip:SetUnit("mouseover");
        UpdateTargetFrameAbilities()
        npcAbilitiesFrame:SetScript("OnUpdate", nil)
    end
end

local function StartCheckingHotkey()
    checkForHotkeyReleased = true

    npcAbilitiesFrame:SetScript("OnUpdate", function(self, elapsed)
        CheckHotkeyState()
    end)
end

local function SetHotkeyButtonPressed(self, key, eventType)
   if NpcAbilitiesOptions["SELECTED_HOTKEY"] then
       if eventType == "OnKeyDown" and key == NpcAbilitiesOptions["SELECTED_HOTKEY"] then
            if NpcAbilitiesOptions["SELECTED_HOTKEY_MODE"] == "hold" or NpcAbilitiesOptions["SELECTED_HOTKEY_MODE"] == "hold_and_hide" then
                StartCheckingHotkey()
            end

            if hotkeyButtonPressed then
               hotkeyButtonPressed = false
            else
               hotkeyButtonPressed = true
            end

            GameTooltip:SetUnit("mouseover");
            UpdateTargetFrameAbilities()
       end
   end

   if NpcAbilitiesOptions["HIDE_ABILITIES_SELECTED_HOTKEY"] then
       if eventType == "OnKeyDown" and key == NpcAbilitiesOptions["HIDE_ABILITIES_SELECTED_HOTKEY"] then
           if hideAbilitiesHotkeyButtonPressed then
              hideAbilitiesHotkeyButtonPressed = false
           else
              hideAbilitiesHotkeyButtonPressed = true
           end

           GameTooltip:SetUnit("mouseover");
           UpdateTargetFrameAbilities()
       end
   end
end

npcAbilitiesFrame:SetScript("OnKeyDown", function(self, key) SetHotkeyButtonPressed(self, key, "OnKeyDown") end)
npcAbilitiesFrame:SetPropagateKeyboardInput(true)
npcAbilitiesFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
