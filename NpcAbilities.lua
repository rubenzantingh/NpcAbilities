local addonName, addonTable = ...

local npcAbilitiesFrame = CreateFrame("Frame")
local hotkeyButtonPressed = false
local hideAbilitiesHotkeyButtonPressed = false
local checkForHotkeyReleased = false

local function GetDataByID(dataType, dataId)
    local convertedId = tonumber(dataId)
    if not convertedId then return nil end

    if dataType == "npcData" then
        return _G["NpcAbilitiesNpcData"][convertedId]
    elseif dataType == "abilityData" then
        return _G["NpcAbilitiesAbilityData"][NpcAbilitiesOptions["SELECTED_LANGUAGE"]][convertedId]
    end

    return nil
end

local function AddAbilityLinesToGameTooltip(id, name, description, mechanic, addedAbilityLine)
    if not addedAbilityLine then
        GameTooltip:AddLine(" ")
    end

    local texture = C_Spell.GetSpellTexture(id);
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
    if hideAbilitiesHotkeyButtonPressed then
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

    if unitType == "Creature" then
        local npcData = GetDataByID('npcData', npcId)

        if npcData then
            local addedAbilityLine = false
            local addedAbilityLineWithDescription = false

            for _, abilityId in pairs(npcData.spell_ids) do
                local abilitiesData = GetDataByID('abilityData', abilityId)

                if abilitiesData then
                    local abilityName = abilitiesData.name
                    local abilityDescription = abilitiesData.description or ""
                    local abilityMechanic = abilitiesData.mechanic or ""

                    AddAbilityLinesToGameTooltip(abilityId, abilityName, abilityDescription, abilityMechanic, addedAbilityLine)
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

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, SetNpcAbilityData)
