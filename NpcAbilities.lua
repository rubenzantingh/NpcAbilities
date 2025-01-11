local addonName, addonTable = ...

local npcAbilitiesFrame = CreateFrame("Frame")
local hotkeyButtonPressed = false

local function GetDataByID(dataType, dataId)
    local data = addonTable[dataType]
    if not data then return nil end

    local convertedId = tonumber(dataId)
    if not convertedId then return nil end

    if dataType == "npcData" then
        return data[convertedId]
    else
        local languageCode = NpcAbilitiesOptions["SELECTED_LANGUAGE"]
        if data[languageCode] then
            return data[languageCode][convertedId]
        end
    end

    return nil
end

local function AddAbilityLinesToGameTooltip(id, name, description, addedAbilityLine)
    if not addedAbilityLine then
        GameTooltip:AddLine(" ")
    end

    local texture = GetSpellTexture(id);
    local icon = "|T" .. texture .. ":12:12:0:0:64:64:4:60:4:60|t"

    GameTooltip:AddLine(icon .. " " .. name)

    if hotkeyButtonPressed then
        GameTooltip:AddLine(description, 1, 1, 1, true)
    end
end

local function SetNpcAbilityData()
    local _, unitId = GameTooltip:GetUnit()
    local unitGUID = UnitGUID(unitId)

    if unitGUID then
        local unitType, _, _, _, _, npcId = strsplit("-", unitGUID)

        if unitType == "Creature" then
            local npcData = GetDataByID('npcData', npcId)

            if npcData then
                local addedAbilityLine = false
                local addedAbilityLineWithDescription = false

                for _, abilityId in pairs(npcData.spell_ids) do
                    local abilitiesData = GetDataByID('abilityData', abilityId)

                    if abilitiesData then
                        local abilityName = abilitiesData.name
                        local abilityDescription = string.gsub(abilitiesData.description or "", "%[q%]", "")

                        AddAbilityLinesToGameTooltip(abilityId, abilityName, abilityDescription, addedAbilityLine)
                        addedAbilityLine = true

                        if abilityDescription ~= '' then
                            addedAbilityLineWithDescription = true
                        end
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
        end
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
