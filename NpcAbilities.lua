local npcAbilitiesFrame = CreateFrame("Frame")
local hotkeyButtonPressed = false
local hideAbilitiesHotkeyButtonPressed = false
local seasonId = C_Seasons.GetActiveSeason()
local checkForHotkeyReleased = false

local function GetDataByID(dataType, dataId)
    data = _G[dataType]
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

local function AddAbilityLinesToGameTooltip(id, name, description, mechanic, range, castTime, dispelType, addedAbilityLine)
    if not addedAbilityLine then
        GameTooltip:AddLine(" ")
    end

    local options = NpcAbilitiesOptions
    local selectedLanguage = options["SELECTED_LANGUAGE"]
    local translations = _G["NpcAbilitiesTranslations"][selectedLanguage]["game"]

    local texture = GetSpellTexture(id)
    local icon = "|T" .. texture .. ":12:12:0:0:64:64:4:60:4:60|t"
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
    appendTitleInfo("DISPLAY_ABILITY_DISPEL_TYPE", dispelType, "SELECTED_ABILITY_DISPEL_TYPE_DISPLAY_MODE", "dispelTypeText")

    GameTooltip:AddLine(abilityNameText)

    if hotkeyButtonPressed then
        local function addSeparateLine(display, value, mode, labelKey)
            if value ~= "" and options[display] and options[mode] == "separate" then
                GameTooltip:AddLine(translations[labelKey] .. ": " .. value, 1, 1, 1, true)
            end
        end

        addSeparateLine("DISPLAY_ABILITY_MECHANIC", mechanic, "SELECTED_ABILITY_MECHANIC_DISPLAY_MODE", "mechanicText")
        addSeparateLine("DISPLAY_ABILITY_RANGE", range, "SELECTED_ABILITY_RANGE_DISPLAY_MODE", "rangeText")
        addSeparateLine("DISPLAY_ABILITY_CAST_TIME", castTime, "SELECTED_ABILITY_CAST_TIME_DISPLAY_MODE", "castTimeText")
        addSeparateLine("DISPLAY_ABILITY_DISPEL_TYPE", dispelType, "SELECTED_ABILITY_DISPEL_TYPE_DISPLAY_MODE", "dispelTypeText")

        GameTooltip:AddLine(description, 1, 1, 1, true)
    end
end


local function SetNpcAbilityData()
    inInstance, _ = IsInInstance()

    if hideAbilitiesHotkeyButtonPressed or (inInstance and NpcAbilitiesOptions["HIDE_ABILITIES_IN_INSTANCE"]) then
        return
    end

    local _, unitId = GameTooltip:GetUnit()

    if not unitId then
        return
    end

    local unitGUID = UnitGUID(unitId)

    if not unitGUID then
        return
    end

    local unitType, _, _, _, _, npcId = strsplit("-", unitGUID)

    if unitType ~= "Creature" then
        return
    end

    local npcData = GetDataByID('NpcAbilitiesNpcData', npcId)

    if npcData == nil then
       return
    end

    local addedAbilityLine = false
    local addedAbilityLineWithDescription = false
    local addedAbilityNames = {}

    if seasonId == 2 then
        for _, sodAbilityId in pairs(npcData.sod_spell_ids) do
            local sodAbilitiesData = GetDataByID('NpcAbilitiesAbilityData', sodAbilityId)

            if sodAbilitiesData ~= nil then
                local sodAbilityName = sodAbilitiesData.name
                local sodAbilityDescription = sodAbilitiesData.description or ""
                local sodAbilityMechanic = sodAbilitiesData.mechanic or ""
                local sodAbilityRange = sodAbilitiesData.range or ""
                local sodAbilityCastTime = sodAbilitiesData.cast_time or ""
                local sodAbilityDispelType = sodAbilitiesData.dispel_type or ""
                addedAbilityNames[sodAbilityName] = sodAbilityName
    
                AddAbilityLinesToGameTooltip(sodAbilityId, sodAbilityName, sodAbilityDescription, sodAbilityMechanic, sodAbilityRange, sodAbilityCastTime, sodAbilityDispelType, addedAbilityLine)
                addedAbilityLine = true

                if sodAbilityDescription ~= '' then
                    addedAbilityLineWithDescription = true
                end
            end
        end
    end

    for _, classicAbilityId in pairs(npcData.classic_spell_ids) do
        local classicAbilitiesData = GetDataByID('NpcAbilitiesAbilityData', classicAbilityId)

        if classicAbilitiesData ~= nil then
            local classicAbilityName = classicAbilitiesData.name
    
            if addedAbilityNames[classicAbilityName] == nil then
                local classicAbilityDescription = classicAbilitiesData.description or ""
                local classicAbilityMechanic = classicAbilitiesData.mechanic or ""
                local classicAbilityRange = classicAbilitiesData.range or ""
                local classicAbilityCastTime = classicAbilitiesData.cast_tome or ""
                local classicAbilityDispelType = classicAbilitiesData.dispel_type or ""

                AddAbilityLinesToGameTooltip(classicAbilityId, classicAbilityName, classicAbilityDescription, classicAbilityMechanic, classicAbilityRange, classicAbilityCastTime, classicAbilityDispelType, addedAbilityLine)
                addedAbilityLine = true

                if classicAbilityDescription ~= '' then
                    addedAbilityLineWithDescription = true
                end
            end
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
        
            GameTooltip:SetUnit("mouseover");
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
       end
   end
end

npcAbilitiesFrame:SetScript("OnKeyDown", function(self, key) SetHotkeyButtonPressed(self, key, "OnKeyDown") end)
npcAbilitiesFrame:SetPropagateKeyboardInput(true)
npcAbilitiesFrame:RegisterEvent("MODIFIER_STATE_CHANGED")

GameTooltip:HookScript("OnTooltipSetUnit", SetNpcAbilityData)
