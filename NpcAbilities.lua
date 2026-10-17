local addonName, addonTable = ...

local npcAbilitiesFrame = CreateFrame("Frame")
local hotkeyButtonPressed = false
local hideAbilitiesHotkeyButtonPressed = false
local checkForHotkeyReleased = false

local function IsAccessible(value)
    if canaccessvalue then
        return canaccessvalue(value)
    end

    if issecretvalue then
        return not issecretvalue(value)
    end

    return true
end

addonTable.IsAccessible = IsAccessible

local function GetDataByID(dataType, dataId)
    local data = _G[dataType]
    if not data then return nil end

    local convertedId = tonumber(dataId)
    if not convertedId then return nil end

    if dataType == "NpcAbilitiesNpcData" then
        return data[convertedId]
    else
        local languageCode = NpcAbilitiesOptions["SELECTED_LANGUAGE"]
        if data[languageCode] then
            return data[languageCode][convertedId]
        end
    end

    return nil
end

local function GetNpcAbilities(npcId)
    local abilities = {}
    local npcData = GetDataByID('NpcAbilitiesNpcData', npcId)

    if npcData then
        for _, abilityId in pairs(npcData.spell_ids) do
            local abilityData = GetDataByID('NpcAbilitiesAbilityData', abilityId)

            if abilityData then
                table.insert(abilities, {id = abilityId, data = abilityData})
            end
        end
    end

    return abilities
end

addonTable.GetNpcAbilities = GetNpcAbilities

local function AddAbilityLinesToTooltip(tooltip, id, name, description, mechanic, range, castTime, dispelType, addedAbilityLine)
    if not addedAbilityLine then
        tooltip:AddLine(" ")
    end

    local options = NpcAbilitiesOptions
    local selectedLanguage = options["SELECTED_LANGUAGE"]
    local translations = _G["NpcAbilitiesTranslations"][selectedLanguage]["game"]

    local texture = C_Spell.GetSpellTexture(id)
    local abilityNameText = name

    if IsAccessible(texture) and texture then
        abilityNameText = "|T" .. texture .. ":12:12:0:0:64:64:4:60:4:60|t " .. name
    end

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
    appendTitleInfo("DISPLAY_ABILITY_DISPEL_TYPE", dispelType, "SELECTED_ABILITY_DISPEL_TYPE_DISPLAY_MODE", "dispelTypeText")

    tooltip:AddLine(abilityNameText)

    if hotkeyButtonPressed then
        local function addSeparateLine(display, value, mode, labelKey)
            if value ~= "" and options[display] and options[mode] == "separate" then
                tooltip:AddLine(translations[labelKey] .. ": " .. value, 1, 1, 1, true)
            end
        end

        addSeparateLine("DISPLAY_ABILITY_MECHANIC", mechanic, "SELECTED_ABILITY_MECHANIC_DISPLAY_MODE", "mechanicText")
        addSeparateLine("DISPLAY_ABILITY_RANGE", range, "SELECTED_ABILITY_RANGE_DISPLAY_MODE", "rangeText")
        addSeparateLine("DISPLAY_ABILITY_CAST_TIME", castTime, "SELECTED_ABILITY_CAST_TIME_DISPLAY_MODE", "castTimeText")
        addSeparateLine("DISPLAY_ABILITY_DISPEL_TYPE", dispelType, "SELECTED_ABILITY_DISPEL_TYPE_DISPLAY_MODE", "dispelTypeText")

        tooltip:AddLine(description, 1, 1, 1, true)
    end
end

-- Adds the ability lines of an NPC to a tooltip. Returns false when there is no ability data for the NPC.
local function AddNpcAbilitiesToTooltip(tooltip, npcId)
    local abilities = GetNpcAbilities(npcId)
    local addedAbilityLine = false
    local addedAbilityLineWithDescription = false

    for _, ability in ipairs(abilities) do
        local abilitiesData = ability.data
        local abilityName = abilitiesData.name
        local abilityDescription = abilitiesData.description or ""
        local abilityMechanic = abilitiesData.mechanic or ""
        local abilityRange = abilitiesData.range or ""
        local abilityCastTime = abilitiesData.cast_time or ""
        local abilityDispelType = abilitiesData.dispel_type or ""

        AddAbilityLinesToTooltip(tooltip, ability.id, abilityName, abilityDescription, abilityMechanic, abilityRange, abilityCastTime, abilityDispelType, addedAbilityLine)
        addedAbilityLine = true

        if abilityDescription ~= '' then
            addedAbilityLineWithDescription = true
        end
    end

    local selectedLanguage = NpcAbilitiesOptions["SELECTED_LANGUAGE"]

    if addedAbilityLineWithDescription and not hotkeyButtonPressed and NpcAbilitiesOptions["SELECTED_HOTKEY"] then
        local hotkey = NpcAbilitiesOptions["SELECTED_HOTKEY"]
        local hotkeyExplanatoryText = "(" .. _G["NpcAbilitiesTranslations"][selectedLanguage]["game"]["hotkeyExplanatoryTextOne"] .. " " .. hotkey .. " " ..  _G["NpcAbilitiesTranslations"][selectedLanguage]["game"]["hotkeyExplanatoryTextTwo"] .. ")"
        tooltip:AddLine(hotkeyExplanatoryText, 0.8, 0.8, 0.8)
    end

    if addedAbilityLineWithDescription and not hotkeyButtonPressed and not NpcAbilitiesOptions["SELECTED_HOTKEY"] then
        tooltip:AddLine("(" .. _G["NpcAbilitiesTranslations"][selectedLanguage]["game"]["hotkeyNotBoundText"] .. ")", 0.8, 0.8, 0.8)
    end

    return addedAbilityLine
end

addonTable.AddNpcAbilitiesToTooltip = AddNpcAbilitiesToTooltip

-- Redraws the tooltip after a hotkey press: the hovered dungeon overview row if there is one, otherwise the mouseover unit.
local function RefreshTooltip()
    if addonTable.RefreshDungeonTooltip and addonTable.RefreshDungeonTooltip() then
        return
    end

    GameTooltip:SetUnit("mouseover")
end

local function SetNpcAbilityData()
    local inInstance = IsInInstance()

    if hideAbilitiesHotkeyButtonPressed or (inInstance and NpcAbilitiesOptions["HIDE_ABILITIES_IN_INSTANCE"]) then
        return
    end

    local _, unitId = GameTooltip:GetUnit()

    if not IsAccessible(unitId) or not unitId then
        return
    end

    local unitGUID = UnitGUID(unitId)

    if not IsAccessible(unitGUID) or not unitGUID then
        return
    end

    local unitType, _, _, _, _, npcId = strsplit("-", unitGUID)

    if unitType == "Creature" then
        AddNpcAbilitiesToTooltip(GameTooltip, npcId)
    end
end

local function CheckHotkeyState()
    local hotkey = NpcAbilitiesOptions["SELECTED_HOTKEY"]

    if not IsKeyDown(hotkey) then
        checkForHotkeyReleased = false
        hotkeyButtonPressed = false
        RefreshTooltip()
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
           if NpcAbilitiesOptions["SELECTED_HOTKEY_MODE"] == "hold" then
               StartCheckingHotkey()
           end

            if hotkeyButtonPressed then
               hotkeyButtonPressed = false
            else
               hotkeyButtonPressed = true
            end
        
            RefreshTooltip()
       end
   end

   if NpcAbilitiesOptions["HIDE_ABILITIES_SELECTED_HOTKEY"] then
       if eventType == "OnKeyDown" and key == NpcAbilitiesOptions["HIDE_ABILITIES_SELECTED_HOTKEY"] then
           if hideAbilitiesHotkeyButtonPressed then
              hideAbilitiesHotkeyButtonPressed = false
           else
              hideAbilitiesHotkeyButtonPressed = true
           end

           RefreshTooltip()
       end
   end
end

npcAbilitiesFrame:SetScript("OnKeyDown", function(self, key) SetHotkeyButtonPressed(self, key, "OnKeyDown") end)
npcAbilitiesFrame:SetPropagateKeyboardInput(true)
npcAbilitiesFrame:RegisterEvent("MODIFIER_STATE_CHANGED")

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, SetNpcAbilityData)
