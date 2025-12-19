local npcAbilitiesFrame = CreateFrame("Frame")
local hotkeyButtonPressed = false
local hideAbilitiesHotkeyButtonPressed = false
local seasonId = C_Seasons.GetActiveSeason()
local checkForHotkeyReleased = false

local targetAbilitiesFrame = CreateFrame("Frame", "NpcAbilitiesTargetFrame", UIParent, "BackdropTemplate")
targetAbilitiesFrame:SetPoint("TOPLEFT", TargetFrame, "BOTTOMLEFT", 20, 5)
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

local function AddAbilityLinesToGameTooltip(id, name, description, mechanic, range, castTime, cooldown, dispelType, addedAbilityLine)
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
    appendTitleInfo("DISPLAY_ABILITY_COOLDOWN", cooldown, "SELECTED_ABILITY_COOLDOWN_DISPLAY_MODE", "cooldownText")
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

    if not UnitExists("target") then
        targetAbilitiesFrame:Hide()
        return
    end

    local inInstance, _ = IsInInstance()
    if hideAbilitiesHotkeyButtonPressed or (inInstance and NpcAbilitiesOptions["HIDE_ABILITIES_IN_INSTANCE"]) then
        targetAbilitiesFrame:Hide()
        return
    end

    local unitGUID = UnitGUID("target")
    if not unitGUID then
        targetAbilitiesFrame:Hide()
        return
    end

    local unitType, _, _, _, _, npcId = strsplit("-", unitGUID)
    if unitType ~= "Creature" then
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

    for _, abilityId in pairs(npcData.spell_ids) do
        local abilitiesData = GetDataByID('NpcAbilitiesAbilityData', abilityId)

        if abilitiesData ~= nil then
            local name = abilitiesData.name

            if not addedAbilityNames[name] then
                table.insert(abilities, {
                    id = abilityId,
                    name = name,
                    description = abilitiesData.description or ""
                })
            end
        end
    end

    if #abilities == 0 then
        targetAbilitiesFrame:Hide()
        return
    end

    local lines = {}
    local hasDescriptions = false
    local translations = _G["NpcAbilitiesTranslations"][selectedLanguage]["game"]

    for _, ability in ipairs(abilities) do
        local texture = GetSpellTexture(ability.id)
        local icon = texture and ("|T" .. texture .. ":14:14:0:0:64:64:4:60:4:60|t") or ""
        local line = icon .. " " .. ability.name

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

local targetEventFrame = CreateFrame("Frame")
targetEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
targetEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
targetEventFrame:RegisterEvent("ADDON_LOADED")
targetEventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "NpcAbilities" then
        if NpcAbilitiesOptions["ABILITY_DISPLAY_LOCATION"] == nil then
            NpcAbilitiesOptions["ABILITY_DISPLAY_LOCATION"] = "both"
        end
    elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        UpdateTargetFrameAbilities()
    end
end)

local function SetNpcAbilityData()
    local displayLocation = NpcAbilitiesOptions["ABILITY_DISPLAY_LOCATION"] or "both"
    if displayLocation == "target_frame" then
        return
    end

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
                local sodAbilityCooldown = sodAbilitiesData.cooldown or ""
                local sodAbilityDispelType = sodAbilitiesData.dispel_type or ""
                addedAbilityNames[sodAbilityName] = sodAbilityName
    
                AddAbilityLinesToGameTooltip(sodAbilityId, sodAbilityName, sodAbilityDescription, sodAbilityMechanic, sodAbilityRange, sodAbilityCastTime, sodAbilityCooldown, sodAbilityDispelType, addedAbilityLine)
                addedAbilityLine = true

                if sodAbilityDescription ~= '' then
                    addedAbilityLineWithDescription = true
                end
            end
        end
    end

    for _, abilityId in pairs(npcData.spell_ids) do
        local abilitiesData = GetDataByID('NpcAbilitiesAbilityData', abilityId)

        if abilitiesData ~= nil then
            local abilityName = abilitiesData.name
    
            if addedAbilityNames[abilityName] == nil then
                local abilityDescription = abilitiesData.description or ""
                local abilityMechanic = abilitiesData.mechanic or ""
                local abilityRange = abilitiesData.range or ""
                local abilityCastTime = abilitiesData.cast_time or ""
                local abilityCooldown = abilitiesData.cooldown or ""
                local abilityDispelType = abilitiesData.dispel_type or ""

                AddAbilityLinesToGameTooltip(abilityId, abilityName, abilityDescription, abilityMechanic, abilityRange, abilityCastTime, abilityCooldown, abilityDispelType, addedAbilityLine)
                addedAbilityLine = true

                if abilityDescription ~= '' then
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
            if NpcAbilitiesOptions["SELECTED_HOTKEY_MODE"] == "hold" then
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

GameTooltip:HookScript("OnTooltipSetUnit", SetNpcAbilityData)
