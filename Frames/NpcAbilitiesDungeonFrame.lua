local addonName, addonTable = ...

local FRAME_NAME = "NpcAbilitiesDungeonFrame"
local DEFAULT_WIDTH = 520
local DEFAULT_HEIGHT = 380
local MIN_WIDTH = 420
local MIN_HEIGHT = 260
local DUNGEON_LIST_WIDTH = 170
local ROW_HEIGHT = 20
local ROW_ICON_SIZE = 14
local MAX_ROW_ABILITY_ICONS = 8
local ROW_LEVEL_ICON_SIZE = 14

-- NPC level ids from the data: the icon in the list and the translation key of its label
local NPC_LEVELS = {
    [1] = {atlas = "nameplates-icon-elite-gold", translationKey = "npcLevelEliteText"},
    [2] = {atlas = "nameplates-icon-elite-silver", translationKey = "npcLevelRareEliteText"},
    [3] = {texture = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", translationKey = "npcLevelBossText"}
}

local dungeonFrame = nil
local dungeonScrollBox = nil
local npcScrollBox = nil
local npcListTitle = nil
local searchBox = nil
local selectedDungeonId = nil
local currentDungeonId = nil
local hoveredNpcRow = nil

-- Data helpers
local function GetDungeonData()
    local data = _G["NpcAbilitiesDungeonData"]

    if not data then
        return {}
    end

    return data[NpcAbilitiesOptions["SELECTED_LANGUAGE"]] or data["en"] or {}
end

local function GetTranslation(key)
    local translations = _G["NpcAbilitiesTranslations"]
    local selectedTranslations = translations[NpcAbilitiesOptions["SELECTED_LANGUAGE"]] or translations["en"]

    return selectedTranslations["game"][key] or translations["en"]["game"][key]
end

-- NPC entries are {name = ..., type = ..., level = ...}; older data only has the name
local function GetNpcInfo(npcEntry)
    if type(npcEntry) == "table" then
        return npcEntry.name, npcEntry.type, npcEntry.level
    end

    return npcEntry, nil, nil
end

-- e.g. "Humanoid (Elite)", "Undead (Boss)" or just "Beast"
local function GetNpcClassificationText(npcType, npcLevel)
    local levelText = nil

    if npcLevel and NPC_LEVELS[npcLevel] then
        levelText = GetTranslation(NPC_LEVELS[npcLevel].translationKey)
    end

    if npcType == "Uncategorized" or npcType == "" then
        npcType = nil
    end

    if npcType and levelText then
        return npcType .. " (" .. levelText .. ")"
    end

    return npcType or levelText
end

-- Dungeons are keyed by zone id, which the game doesn't expose inside an instance.
-- They're matched on instance_id first, falling back to the name in any of the available
-- languages for entries without one. Names aren't unique (e.g. Blackrock Depths is both a
-- dungeon and a raid), so a name match of the instance's type wins, and otherwise the
-- highest zone id (usually the current version).
local function GetCurrentDungeonId()
    if not IsInInstance() then
        return nil
    end

    local IsAccessible = addonTable.IsAccessible
    local instanceName, instanceType, _, _, _, _, _, instanceId = GetInstanceInfo()
    local dungeonData = _G["NpcAbilitiesDungeonData"] or {}

    if IsAccessible(instanceId) and instanceId then
        local matchedDungeonId = nil

        for _, languageData in pairs(dungeonData) do
            for dungeonId, dungeon in pairs(languageData) do
                if dungeon.instance_id == instanceId and next(dungeon.npcs or {}) and (not matchedDungeonId or dungeonId > matchedDungeonId) then
                    matchedDungeonId = dungeonId
                end
            end
        end

        if matchedDungeonId then
            return matchedDungeonId
        end
    end

    local zoneName = GetRealZoneText()
    local dungeonType = instanceType == "raid" and "raid" or "dungeon"
    local namesToMatch = {}

    for _, name in ipairs({instanceName, zoneName}) do
        if IsAccessible(name) and name and name ~= "" then
            namesToMatch[name] = true
        end
    end

    local bestDungeonId = nil
    local bestTypeMatches = false

    for _, languageData in pairs(dungeonData) do
        for dungeonId, dungeon in pairs(languageData) do
            if namesToMatch[dungeon.name] and next(dungeon.npcs or {}) then
                local typeMatches = dungeon.type == dungeonType

                if not bestDungeonId or (typeMatches and not bestTypeMatches) or (typeMatches == bestTypeMatches and dungeonId > bestDungeonId) then
                    bestDungeonId = dungeonId
                    bestTypeMatches = typeMatches
                end
            end
        end
    end

    return bestDungeonId
end

local function BuildDungeonListData()
    local dungeons = {}
    local raids = {}

    for dungeonId, dungeon in pairs(GetDungeonData()) do
        if next(dungeon.npcs or {}) then
            local entry = {dungeonId = dungeonId, name = dungeon.name, current = dungeonId == currentDungeonId}

            table.insert(dungeon.type == "raid" and raids or dungeons, entry)
        end
    end

    local function sortCurrentFirstThenByName(a, b)
        if a.current ~= b.current then
            return a.current
        end

        if a.name == b.name then
            return a.dungeonId < b.dungeonId
        end

        return a.name < b.name
    end

    local listData = {}

    local function addGroup(headerKey, entries)
        if #entries == 0 then
            return
        end

        table.sort(entries, sortCurrentFirstThenByName)
        table.insert(listData, {header = GetTranslation(headerKey)})

        for _, entry in ipairs(entries) do
            table.insert(listData, entry)
        end
    end

    addGroup("dungeonDungeonsText", dungeons)
    addGroup("dungeonRaidsText", raids)

    return listData
end

local function BuildNpcListData()
    local dungeon = selectedDungeonId and GetDungeonData()[selectedDungeonId]

    if not dungeon then
        return {}
    end

    local filter = strlower(searchBox:GetText() or "")
    local listData = {}

    for npcId, npcEntry in pairs(dungeon.npcs or {}) do
        local name, npcType, npcLevel = GetNpcInfo(npcEntry)

        if filter == "" or strlower(name):find(filter, 1, true) then
            table.insert(listData, {
                npcId = npcId,
                name = name,
                npcType = npcType,
                npcLevel = npcLevel,
                abilities = addonTable.GetNpcAbilities(npcId)
            })
        end
    end

    table.sort(listData, function(a, b)
        if a.name == b.name then
            return a.npcId < b.npcId
        end

        return a.name < b.name
    end)

    return listData
end

-- Tooltip
local function ShowNpcTooltip(row)
    hoveredNpcRow = row

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.npcName, 1, 0.82, 0)

    local classificationText = GetNpcClassificationText(row.npcType, row.npcLevel)

    if classificationText then
        GameTooltip:AddLine(classificationText, 1, 1, 1)
    end

    if not addonTable.AddNpcAbilitiesToTooltip(GameTooltip, row.npcId) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(GetTranslation("noAbilityDataText"), 0.6, 0.6, 0.6)
    end

    GameTooltip:Show()
end

local function HideNpcTooltip()
    if hoveredNpcRow and GameTooltip:GetOwner() == hoveredNpcRow then
        GameTooltip:Hide()
    end

    hoveredNpcRow = nil
end

-- Called by the hotkey handlers, returns true when the hovered row's tooltip was redrawn
addonTable.RefreshDungeonTooltip = function()
    if hoveredNpcRow and hoveredNpcRow:IsVisible() and hoveredNpcRow:IsMouseOver() and GameTooltip:GetOwner() == hoveredNpcRow then
        ShowNpcTooltip(hoveredNpcRow)
        return true
    end

    return false
end

-- Rows
local function SetupRow(row)
    if row.Text then
        return
    end

    row.Selected = row:CreateTexture(nil, "BACKGROUND")
    row.Selected:SetAllPoints()
    row.Selected:SetColorTexture(1, 0.82, 0, 0.15)

    row.Highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.Highlight:SetAllPoints()
    row.Highlight:SetColorTexture(1, 1, 1, 0.1)

    row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Text:SetJustifyH("LEFT")
    row.Text:SetWordWrap(false)

    row.LevelIcon = row:CreateTexture(nil, "ARTWORK")
    row.LevelIcon:SetSize(ROW_LEVEL_ICON_SIZE, ROW_LEVEL_ICON_SIZE)
    row.LevelIcon:SetPoint("LEFT", 4, 0)

    row.AbilityIcons = {}
end

local function SetupHeaderRow(row, elementData)
    row:EnableMouse(false)
    row:SetScript("OnClick", nil)
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    row.Selected:Hide()
    row.LevelIcon:Hide()

    for _, icon in ipairs(row.AbilityIcons) do
        icon:Hide()
    end

    row.Text:SetFontObject("GameFontNormalSmall")
    row.Text:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
    row.Text:ClearAllPoints()
    row.Text:SetPoint("LEFT", 2, -2)
    row.Text:SetPoint("RIGHT", -2, -2)
    row.Text:SetText(elementData.header)
end

local function UpdateSelectedDungeonRows()
    dungeonScrollBox:ForEachFrame(function(row)
        row.Selected:SetShown(row.dungeonId ~= nil and row.dungeonId == selectedDungeonId)
    end)
end

local SelectDungeon

local function InitializeDungeonRow(row, elementData)
    SetupRow(row)
    row.dungeonId = elementData.dungeonId

    if elementData.header then
        SetupHeaderRow(row, elementData)
        return
    end

    row:EnableMouse(true)
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    row:SetScript("OnClick", function()
        SelectDungeon(elementData.dungeonId)
    end)
    row.LevelIcon:Hide()

    row.Text:SetFontObject("GameFontHighlightSmall")
    row.Text:ClearAllPoints()
    row.Text:SetPoint("LEFT", 8, 0)
    row.Text:SetPoint("RIGHT", -2, 0)

    for _, icon in ipairs(row.AbilityIcons) do
        icon:Hide()
    end

    row.Text:SetText(elementData.name)

    if elementData.current then
        row.Text:SetTextColor(GREEN_FONT_COLOR:GetRGB())
    else
        row.Text:SetTextColor(1, 1, 1)
    end

    row.Selected:SetShown(elementData.dungeonId == selectedDungeonId)
end

local function InitializeNpcRow(row, elementData)
    SetupRow(row)
    row.dungeonId = nil
    row.npcId = elementData.npcId
    row.npcName = elementData.name
    row.npcType = elementData.npcType
    row.npcLevel = elementData.npcLevel

    if elementData.header then
        SetupHeaderRow(row, elementData)
        return
    end

    row:EnableMouse(true)
    row:SetScript("OnClick", nil)
    row:SetScript("OnEnter", ShowNpcTooltip)
    row:SetScript("OnLeave", HideNpcTooltip)
    row.Selected:Hide()

    local IsAccessible = addonTable.IsAccessible
    local shownIcons = 0

    for _, ability in ipairs(elementData.abilities) do
        if shownIcons >= MAX_ROW_ABILITY_ICONS then
            break
        end

        local texture = C_Spell.GetSpellTexture(ability.id)

        if IsAccessible(texture) and texture then
            shownIcons = shownIcons + 1

            local icon = row.AbilityIcons[shownIcons]

            if not icon then
                icon = row:CreateTexture(nil, "ARTWORK")
                icon:SetSize(ROW_ICON_SIZE, ROW_ICON_SIZE)
                icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                icon:SetPoint("RIGHT", -4 - (shownIcons - 1) * (ROW_ICON_SIZE + 2), 0)
                row.AbilityIcons[shownIcons] = icon
            end

            icon:SetTexture(texture)
            icon:Show()
        end
    end

    for index = shownIcons + 1, #row.AbilityIcons do
        row.AbilityIcons[index]:Hide()
    end

    local levelIcon = NPC_LEVELS[elementData.npcLevel]
    local hasLevelIcon = false

    if levelIcon and levelIcon.atlas then
        hasLevelIcon = row.LevelIcon:SetAtlas(levelIcon.atlas)
    elseif levelIcon then
        row.LevelIcon:SetTexture(levelIcon.texture)
        row.LevelIcon:SetTexCoord(0, 1, 0, 1)
        hasLevelIcon = true
    end

    row.LevelIcon:SetShown(hasLevelIcon)

    -- Names line up whether or not a row has a level icon
    row.Text:SetFontObject("GameFontHighlightSmall")
    row.Text:ClearAllPoints()
    row.Text:SetPoint("LEFT", ROW_LEVEL_ICON_SIZE + 8, 0)
    row.Text:SetPoint("RIGHT", -8 - shownIcons * (ROW_ICON_SIZE + 2), 0)
    row.Text:SetText(elementData.name)

    if #elementData.abilities > 0 then
        row.Text:SetTextColor(1, 1, 1)
    else
        row.Text:SetTextColor(0.5, 0.5, 0.5)
    end
end

-- Lists
local function CreateScrollList(parent, initializer)
    local scrollBox = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
    local scrollBar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Button", initializer)

    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    return scrollBox
end

local function RefreshNpcList()
    HideNpcTooltip()

    local dungeon = selectedDungeonId and GetDungeonData()[selectedDungeonId]
    npcListTitle:SetText(dungeon and dungeon.name or "")

    npcScrollBox:SetDataProvider(CreateDataProvider(BuildNpcListData()))
end

SelectDungeon = function(dungeonId)
    selectedDungeonId = dungeonId
    NpcAbilitiesOptions["DUNGEON_FRAME_SELECTED_DUNGEON_ID"] = dungeonId

    UpdateSelectedDungeonRows()
    RefreshNpcList()
end

local function RefreshDungeonList(selectCurrentDungeon)
    local previousCurrentDungeonId = currentDungeonId
    currentDungeonId = GetCurrentDungeonId()

    local listData = BuildDungeonListData()
    dungeonScrollBox:SetDataProvider(CreateDataProvider(listData))

    local dungeonIdToSelect = selectedDungeonId or NpcAbilitiesOptions["DUNGEON_FRAME_SELECTED_DUNGEON_ID"]

    if currentDungeonId and (selectCurrentDungeon or currentDungeonId ~= previousCurrentDungeonId) then
        dungeonIdToSelect = currentDungeonId
    end

    if not dungeonIdToSelect or not GetDungeonData()[dungeonIdToSelect] then
        dungeonIdToSelect = nil

        for _, entry in ipairs(listData) do
            if entry.dungeonId then
                dungeonIdToSelect = entry.dungeonId
                break
            end
        end
    end

    SelectDungeon(dungeonIdToSelect)
end

-- Frame
local function SaveFrameLayout(frame)
    local point, _, relativePoint, x, y = frame:GetPoint(1)

    NpcAbilitiesOptions["DUNGEON_FRAME_LAYOUT"] = {
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
        width = frame:GetWidth(),
        height = frame:GetHeight()
    }
end

local function CreateDungeonFrame()
    local frame = CreateFrame("Frame", FRAME_NAME, UIParent, "BasicFrameTemplateWithInset")
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveFrameLayout(self)
    end)

    local layout = NpcAbilitiesOptions["DUNGEON_FRAME_LAYOUT"]

    if layout then
        frame:SetSize(layout.width, layout.height)
        frame:SetPoint(layout.point, UIParent, layout.relativePoint, layout.x, layout.y)
    else
        frame:SetSize(DEFAULT_WIDTH, DEFAULT_HEIGHT)
        frame:SetPoint("CENTER")
    end

    local title = frame.TitleText

    if not title then
        title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", 0, -5)
    end

    title:SetText("NpcAbilities")

    -- Dungeon list
    dungeonScrollBox = CreateScrollList(frame, InitializeDungeonRow)
    dungeonScrollBox:SetPoint("TOPLEFT", 10, -30)
    dungeonScrollBox:SetPoint("BOTTOMLEFT", 10, 10)
    dungeonScrollBox:SetWidth(DUNGEON_LIST_WIDTH)

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.15)
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", dungeonScrollBox, "TOPRIGHT", 16, 0)
    divider:SetPoint("BOTTOMLEFT", dungeonScrollBox, "BOTTOMRIGHT", 16, 0)

    -- NPC list
    npcListTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    npcListTitle:SetPoint("TOPLEFT", divider, "TOPRIGHT", 10, -2)
    npcListTitle:SetPoint("RIGHT", -12, 0)
    npcListTitle:SetJustifyH("LEFT")
    npcListTitle:SetWordWrap(false)

    searchBox = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
    searchBox:SetHeight(20)
    searchBox:SetAutoFocus(false)
    searchBox:SetPoint("TOPLEFT", npcListTitle, "BOTTOMLEFT", 6, -6)
    searchBox:SetPoint("RIGHT", -14, 0)
    searchBox:HookScript("OnTextChanged", function()
        if npcScrollBox then
            RefreshNpcList()
        end
    end)

    npcScrollBox = CreateScrollList(frame, InitializeNpcRow)
    npcScrollBox:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -6, -6)
    npcScrollBox:SetPoint("BOTTOMRIGHT", -26, 22)

    -- Resize grip
    local resizeButton = CreateFrame("Button", nil, frame)
    resizeButton:SetSize(16, 16)
    resizeButton:SetPoint("BOTTOMRIGHT", -4, 4)
    resizeButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeButton:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeButton:SetScript("OnMouseDown", function()
        frame:StartSizing("BOTTOMRIGHT")
    end)
    resizeButton:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        SaveFrameLayout(frame)
    end)

    frame:SetScript("OnShow", function()
        if searchBox.Instructions then
            searchBox.Instructions:SetText(GetTranslation("dungeonSearchText"))
        end

        RefreshDungeonList(true)
    end)

    frame:SetScript("OnHide", HideNpcTooltip)

    frame:SetScript("OnEvent", function(self)
        if self:IsShown() then
            RefreshDungeonList(false)
        end
    end)
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

    table.insert(UISpecialFrames, FRAME_NAME)

    frame:Hide()

    return frame
end

local function ToggleDungeonFrame()
    if not dungeonFrame then
        dungeonFrame = CreateDungeonFrame()
    end

    dungeonFrame:SetShown(not dungeonFrame:IsShown())
end

addonTable.ToggleDungeonFrame = ToggleDungeonFrame

SLASH_NPCABILITIES1 = "/npca"
SLASH_NPCABILITIES2 = "/npcabilities"
SlashCmdList["NPCABILITIES"] = ToggleDungeonFrame

-- Addon compartment (referenced from the .toc)
function NpcAbilities_OnAddonCompartmentClick()
    ToggleDungeonFrame()
end

function NpcAbilities_OnAddonCompartmentEnter(_, menuButtonFrame)
    GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
    GameTooltip:SetText("NpcAbilities")
    GameTooltip:AddLine(GetTranslation("dungeonToggleText"), 1, 1, 1)
    GameTooltip:Show()
end

function NpcAbilities_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
