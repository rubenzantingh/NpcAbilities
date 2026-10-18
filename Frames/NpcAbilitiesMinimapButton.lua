local addonName, addonTable = ...

local ICON = "Interface\\Icons\\INV_Misc_Book_09"
local minimapButtonFrame = CreateFrame("Frame")

local function GetTranslation(key)
    local translations = _G["NpcAbilitiesTranslations"]
    local selectedTranslations = translations[NpcAbilitiesOptions["SELECTED_LANGUAGE"]] or translations["en"]

    return selectedTranslations["game"][key] or translations["en"]["game"][key]
end

-- Shows or hides the button, called from the options panel
addonTable.SetMinimapButtonShown = function(shown)
    local LibDBIcon = LibStub("LibDBIcon-1.0")

    NpcAbilitiesOptions["SHOW_MINIMAP_BUTTON"] = shown
    NpcAbilitiesOptions["MINIMAP_BUTTON"].hide = not shown

    if shown then
        LibDBIcon:Show(addonName)
    else
        LibDBIcon:Hide(addonName)
    end
end

local function CreateMinimapButton()
    local dataObject = LibStub("LibDataBroker-1.1"):NewDataObject(addonName, {
        type = "launcher",
        text = addonName,
        icon = ICON,
        OnClick = function()
            addonTable.ToggleDungeonFrame()
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine(addonName)
            tooltip:AddLine(GetTranslation("dungeonToggleText"), 1, 1, 1)
        end
    })

    -- LibDBIcon stores the button position (minimapPos) and visibility (hide) in this table
    NpcAbilitiesOptions["MINIMAP_BUTTON"].hide = not NpcAbilitiesOptions["SHOW_MINIMAP_BUTTON"]

    LibStub("LibDBIcon-1.0"):Register(addonName, dataObject, NpcAbilitiesOptions["MINIMAP_BUTTON"])
end

minimapButtonFrame:RegisterEvent("PLAYER_LOGIN")
minimapButtonFrame:SetScript("OnEvent", CreateMinimapButton)
