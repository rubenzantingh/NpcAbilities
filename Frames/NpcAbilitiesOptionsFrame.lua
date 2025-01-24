local defaultOptions = {
    SELECTED_LANGUAGE = 'en',
    AVAILABLE_LANGUAGES = {
        {value = 'en', text = 'English'},
        {value = 'es', text = 'Spanish'},
        {value = 'ru', text = 'Russian'},
        {value = 'fr', text = 'French'},
        {value = 'de', text = 'German'},
        {value = 'pt', text = 'Portuguese'},
        {value = 'ko', text = 'Korean'},
        {value = 'cn', text = 'Chinese'},
    },
    SELECTED_HOTKEY = nil,
    DISPLAY_ABILITY_MECHANIC = true
}

local addonName = ...
local optionsFrame = CreateFrame("Frame")
local LibDD = LibStub:GetLibrary("LibUIDropDownMenu-4.0")

-- General functions
local function CreateOptionDropdown(parent, relativeFrame, offsetX, offsetY, label, defaultValueLabel, optionKey, selectedKey)
    local dropdownLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    dropdownLabel:SetText(label)
    dropdownLabel:SetPoint("TOPLEFT", relativeFrame, "TOPLEFT", offsetX, offsetY - 10)

    local dropdown = LibDD:Create_UIDropDownMenu(nil, parent)
    dropdown:SetPoint("TOPLEFT", dropdownLabel, "BOTTOMLEFT", -20, -4)

    local selectedOptionLabel = defaultValueLabel
    
    LibDD:UIDropDownMenu_Initialize(dropdown, function(self, level, menuList)
        local info = LibDD:UIDropDownMenu_CreateInfo()

        local function OnDropdownValueChanged(self, arg1, arg2, checked)
            NpcAbilitiesOptions[selectedKey] = arg1
            UIDropDownMenu_SetText(dropdown, arg2)
        end

        for index, value in ipairs(NpcAbilitiesOptions[optionKey]) do
            info.text = value.text
            info.value = value.value
            info.arg1 = info.value
            info.arg2 = info.text
            info.checked = NpcAbilitiesOptions[selectedKey] == value.value
            info.func = OnDropdownValueChanged
            info.minWidth = 150

            if info.checked then
                selectedOptionLabel = value.text
            end

            LibDD:UIDropDownMenu_AddButton(info)
        end
    end)
    
    LibDD:UIDropDownMenu_SetWidth(dropdown, 150)
    UIDropDownMenu_SetText(dropdown, selectedOptionLabel)
    UIDropDownMenu_SetAnchor(dropdown, 0, 0, "TOPLEFT", dropdown)
    return dropdown
end

local function CreateCheckBox(parent, text, optionKey, onClick)
    local checkbox = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    checkbox.Text:SetText(text)
    checkbox.Text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    checkbox.Text:SetPoint("LEFT", 30, 0)
    checkbox:SetScript("OnClick", onClick)
    checkbox:SetChecked(NpcAbilitiesOptions[optionKey])
    return checkbox
end

local function InitializeOptions()
    local optionsPanel = CreateFrame("Frame", "NpcAbilitiesOptionsPanel", UIParent)
    optionsPanel.name = "NpcAbilities"

    -- Vars
    local titleOffsetY = -22
    local subTitleOffsetY = -30
    local fieldOffsetX = 25
    local fieldOffsetY = -10

    -- Options panel title
    local panelTitle = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    panelTitle:SetPoint("TOPLEFT", optionsPanel, 6, titleOffsetY)
    panelTitle:SetText("NpcAbilities")
    panelTitle:SetTextColor(1, 1, 1)
    panelTitle:SetFont("Fonts\\FRIZQT__.TTF", 20)

    local panelTitleUnderline = optionsPanel:CreateTexture(nil, "ARTWORK")
    panelTitleUnderline:SetColorTexture(1, 1, 1, 0.3)
    panelTitleUnderline:SetPoint("TOPLEFT", panelTitle, "BOTTOMLEFT", 0, -9)
    panelTitleUnderline:SetPoint("TOPRIGHT", optionsPanel, "TOPRIGHT", -16, -31)

    -- Scrollable frame
    local optionsContainerScrollFrame = CreateFrame("ScrollFrame", nil, optionsPanel, "UIPanelScrollFrameTemplate")
    optionsContainerScrollFrame:SetPoint("TOPLEFT", panelTitleUnderline, 0, -10)
    optionsContainerScrollFrame:SetPoint("BOTTOMRIGHT", -38, 30)

    local scrollSpeed = 50

    optionsContainerScrollFrame:EnableMouseWheel(true)
    optionsContainerScrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local newOffset = self:GetVerticalScroll() - (delta * scrollSpeed)
        newOffset = math.max(0, math.min(newOffset, self:GetVerticalScrollRange()))
        self:SetVerticalScroll(newOffset)
    end)

    local optionsContainer = CreateFrame("Frame")
    optionsContainerScrollFrame:SetScrollChild(optionsContainer)
    optionsContainer:SetWidth(UIParent:GetWidth())
    optionsContainer:SetHeight(1)

    -- General options
    local generalOptionsTitle = optionsContainer:CreateFontString("ARTWORK", nil, "GameFontHighlightLarge")
    generalOptionsTitle:SetPoint("TOPLEFT", 8, titleOffsetY)
    generalOptionsTitle:SetText("General options")
    generalOptionsTitle:SetTextColor(1, 1, 1)

    -- General options: Language
    local languageDropdown = CreateOptionDropdown(
        optionsContainer,
        generalOptionsTitle,
        fieldOffsetX,
        subTitleOffsetY,
        "Select language:",
        "English",
        "AVAILABLE_LANGUAGES",
        "SELECTED_LANGUAGE"
    )

    -- General options: Mechanic
    local displayAbilitiesMechanicCheckbox = CreateCheckBox(optionsContainer, "Display ability mechanic", "DISPLAY_ABILITY_MECHANIC", function(self)
        local checked = self:GetChecked()
        NpcAbilitiesOptions["DISPLAY_ABILITY_MECHANIC"] = checked
    end)
    displayAbilitiesMechanicCheckbox:SetPoint("TOPLEFT", languageDropdown, fieldOffsetX - 10, subTitleOffsetY + fieldOffsetY)

    -- General options: Hotkey
    local hotkeyDescription = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontnormalSmall")
    hotkeyDescription:SetPoint("TOPLEFT", displayAbilitiesMechanicCheckbox, "BOTTOMLEFT", 0, fieldOffsetY)
    hotkeyDescription:SetText("Register Hotkey (right-click to unbind):")

    local registerHotkeyButton = CreateFrame("Button", "NpcAbilitiesRegisterHotkeyButton", optionsPanel, "UIPanelButtonTemplate")
    registerHotkeyButton:SetWidth(120)
    registerHotkeyButton:SetHeight(25)
    registerHotkeyButton:SetPoint("TOPLEFT", hotkeyDescription, "TOPLEFT", 0, -12)

    if NpcAbilitiesOptions.SELECTED_HOTKEY then
        registerHotkeyButton:SetText(NpcAbilitiesOptions.SELECTED_HOTKEY)
    else
        registerHotkeyButton:SetText("Not Bound")
    end

    local waitingForKey = false

    registerHotkeyButton:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            if not waitingForKey then
                waitingForKey = true
                registerHotkeyButton:SetText("Press button..")
            end
        elseif button == "RightButton" then
            waitingForKey = false
            registerHotkeyButton:SetText("Not Bound")
            NpcAbilitiesOptions.SELECTED_HOTKEY = nil
        end
    end)

    local function SetHotkeyButton(self, key)
        if waitingForKey then
            NpcAbilitiesOptions.SELECTED_HOTKEY = key
            registerHotkeyButton:SetText(NpcAbilitiesOptions.SELECTED_HOTKEY)
            waitingForKey = false
        end
    end

    registerHotkeyButton:SetScript("OnKeyDown", SetHotkeyButton)
    registerHotkeyButton:SetPropagateKeyboardInput(true)

    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(optionsPanel)
    else
        local category = Settings.RegisterCanvasLayoutCategory(optionsPanel, optionsPanel.name);
        Settings.RegisterAddOnCategory(category);
    end
end

local function addonLoaded(self, event, addonLoadedName)
    if addonLoadedName == addonName then
        NpcAbilitiesOptions = NpcAbilitiesOptions or defaultOptions

        for key, value in pairs(defaultOptions) do
            if NpcAbilitiesOptions[key] == nil then
                NpcAbilitiesOptions[key] = value
            end
        end

        InitializeOptions()
    end
end

optionsFrame:RegisterEvent("ADDON_LOADED")
optionsFrame:SetScript("OnEvent", addonLoaded)