local addonName, addon = ...
addon = addon or {}

local Debug = {}
addon.Debug = Debug

local header
local log
local frame = CreateFrame("Frame", "NpcAbilitiesForeverDebugFrame", UIParent, "BackdropTemplate")
frame:SetSize(680, 400)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = {left = 2, right = 2, top = 2, bottom = 2},
})
frame:SetBackdropColor(0, 0, 0, 0.94)
frame:SetBackdropBorderColor(0.7, 0.7, 0.7, 1)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:Hide()

local title = frame:CreateFontString("NpcAbilitiesForeverDebugTitle", "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -12)
title:SetText("NpcAbilitiesForever | Combat Debug")

local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
closeButton:SetScript("OnClick", function() frame:Hide() end)

header = frame:CreateFontString("NpcAbilitiesForeverDebugStatus", "OVERLAY", "GameFontHighlightSmall")
header:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
header:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
header:SetHeight(64)
header:SetJustifyH("LEFT")
header:SetJustifyV("TOP")
header:SetWordWrap(true)

log = CreateFrame("ScrollingMessageFrame", "NpcAbilitiesForeverDebugLog", frame)
log:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
log:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 14)
log:SetFontObject("GameFontHighlightSmall")
log:SetJustifyH("LEFT")
log:SetMaxLines(200)
log:SetFading(false)
log:SetInsertMode("BOTTOM")
log:EnableMouseWheel(true)
log:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then self:ScrollUp() else self:ScrollDown() end
end)

UISpecialFrames = UISpecialFrames or {}
table.insert(UISpecialFrames, "NpcAbilitiesForeverDebugFrame")
SLASH_NPCABILITIESFOREVERDEBUG1 = "/nabdebug"
SLASH_NPCABILITIESFOREVERDEBUG2 = "/npcabilitiesforeverdebug"
SlashCmdList = SlashCmdList or {}

local function IsGerman()
    return NpcAbilitiesOptions and NpcAbilitiesOptions.SELECTED_LANGUAGE == "de"
end

function Debug.Localize(english, german)
    if IsGerman() then return german end
    return english
end

function Debug.Refresh(status)
    status = status or Debug.status
    if not status then return end
    local isGerman = IsGerman()
    title:SetText(isGerman and "NpcAbilitiesForever | Kampf-Debug" or "NpcAbilitiesForever | Combat Debug")

    local lines = {
        string.format(
            Debug.Localize("Client: %s (%d) | Forever: %s | SavedVariables: %s",
                "Client: %s (%d) | Forever: %s | Gespeicherte Variablen: %s"),
            status.build, status.interfaceVersion,
            status.isForever and Debug.Localize("Yes", "Ja") or Debug.Localize("No", "Nein"),
            status.savedVariablesLoaded and Debug.Localize("loaded", "geladen") or Debug.Localize("MISSING", "FEHLEN")),
        string.format(
            Debug.Localize("Collection: %s | Damage Meter: %s | Reads after combat | Pending sessions: %d",
                "Sammlung: %s | Damage Meter: %s | Auslesen nach dem Kampf | Ausstehende Sitzungen: %d"),
            status.collectionEnabled and Debug.Localize("ON", "AN") or Debug.Localize("OFF", "AUS"),
            status.damageMeterAvailable and Debug.Localize("AVAILABLE", "VERFUEGBAR")
                or Debug.Localize("UNAVAILABLE", "NICHT VERFUEGBAR"),
            status.queuedSessionCount),
        Debug.Localize("Latest results are listed below. /nabdebug toggles this window; /nabdebug clear clears the log.",
            "Letzte Ergebnisse stehen unten. /nabdebug blendet dieses Fenster ein oder aus; /nabdebug clear leert das Protokoll."),
    }

    if not status.collectionEnabled then
        table.insert(lines, Debug.Localize(
            'Collection is OFF. Enable "Collect NPC spell data in-game (after combat)" in the NpcAbilitiesForever options.',
            'Das Sammeln ist AUS. Aktiviere „NPC-Zauberdaten im Spiel nach dem Kampf sammeln“ in den NpcAbilitiesForever-Optionen.'))
    end
    header:SetHeight(status.collectionEnabled and 64 or 108)
    header:SetText(table.concat(lines, "\n"))
end

function Debug.SetStatus(status)
    Debug.status = status
    Debug.Refresh(status)
end

function Debug.AddLine(line)
    log:AddMessage(line)
end

function Debug.Clear()
    log:Clear()
end

SlashCmdList.NPCABILITIESFOREVERDEBUG = function(message)
    if message == "clear" then
        Debug.Clear()
        Debug.Refresh()
        return
    end
    if frame:IsShown() then frame:Hide() else frame:Show() end
    Debug.Refresh()
end
