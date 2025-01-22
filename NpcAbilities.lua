local npcAbilitiesFrame = CreateFrame("Frame")
local hotkeyButtonPressed = false
local seasonId = C_Seasons.GetActiveSeason()

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

local function AddAbilityLinesToGameTooltip(id, name, description, mechanic, addedAbilityLine)
    if not addedAbilityLine then
        GameTooltip:AddLine(" ")
    end

    local texture = GetSpellTexture(id);
    local icon = "|T" .. texture .. ":12:12:0:0:64:64:4:60:4:60|t"
    local mechanicText = ""

    if mechanic ~= "" and NpcAbilitiesOptions["DISPLAY_ABILITY_MECHANIC"] then
        mechanicText = " - " .. mechanic
    end

    GameTooltip:AddLine(icon .. " " .. name .. mechanicText)

    if hotkeyButtonPressed then
        GameTooltip:AddLine(description, 1, 1, 1, true)
    end
end

local function SetNpcAbilityData()
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

            if sodAbilitiesData == nil then
                return
            end

            local sodAbilityName = sodAbilitiesData.name
            local sodAbilityDescription = sodAbilitiesData.description or ""
            local sodAbilityMechanic = sodAbilitiesData.mechanic or ""
            addedAbilityNames[sodAbilityName] = sodAbilityName

            AddAbilityLinesToGameTooltip(sodAbilityId, sodAbilityName, sodAbilityDescription, sodAbilityMechanic, addedAbilityLine)
            addedAbilityLine = true

            if sodAbilityDescription ~= '' then
                addedAbilityLineWithDescription = true
            end
        end
    end

    for _, classicAbilityId in pairs(npcData.classic_spell_ids) do
        local classicAbilitiesData = GetDataByID('NpcAbilitiesAbilityData', classicAbilityId)

        if classicAbilitiesData == nil then
            return
        end

        local classicAbilityName = classicAbilitiesData.name

        if addedAbilityNames[classicAbilityName] then
            return
        end

        local classicAbilityDescription = classicAbilitiesData.description or ""
        local classicAbilityMechanic = classicAbilitiesData.mechanic or ""

        AddAbilityLinesToGameTooltip(classicAbilityId, classicAbilityName, classicAbilityDescription, classicAbilityMechanic, addedAbilityLine)
        addedAbilityLine = true

        if classicAbilityDescription ~= '' then
            addedAbilityLineWithDescription = true
        end
    end

    if addedAbilityLineWithDescription and not hotkeyButtonPressed and NpcAbilitiesOptions["SELECTED_HOTKEY"] then
        local hotkey = NpcAbilitiesOptions["SELECTED_HOTKEY"]
        GameTooltip:AddLine("(Press " .. hotkey .. " for details)", 0.8, 0.8, 0.8)
    end

    if addedAbilityLineWithDescription and not hotkeyButtonPressed and not NpcAbilitiesOptions["SELECTED_HOTKEY"] then
        GameTooltip:AddLine("(Hotkey not bound)", 0.8, 0.8, 0.8)
    end
end

local function SetHotkeyButtonPressed(self, key, eventType)
   if NpcAbilitiesOptions["SELECTED_HOTKEY"] then
       if eventType == "OnKeyDown" and key == NpcAbilitiesOptions["SELECTED_HOTKEY"] then
            if hotkeyButtonPressed then
               hotkeyButtonPressed = false
            else
               hotkeyButtonPressed = true
            end
        
            GameTooltip:SetUnit("mouseover");
       end
   end
end

npcAbilitiesFrame:SetScript("OnKeyDown", function(self, key) SetHotkeyButtonPressed(self, key, "OnKeyDown") end)
npcAbilitiesFrame:SetPropagateKeyboardInput(true)
npcAbilitiesFrame:RegisterEvent("MODIFIER_STATE_CHANGED")

GameTooltip:HookScript("OnTooltipSetUnit", SetNpcAbilityData)
