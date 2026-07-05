CommanderTooltipDB = _G.CommanderTooltipDB or {}

COMMANDER_TOOLTIP_EVENTS = {
    UPDATE = "COMMANDER_TOOLTIP_UPDATE"
}

local DefaultSettings = {
    ShowItemLevel = true,
    ShowVendorPrice = true,
    AnchorToCursor = true,
    xOffset = 0,
    yOffset = 0,
    Scale = 1.0,
    Anchor = "BOTTOMLEFT"
}

local function ApplyDefaultSettings()
    for key, value in pairs(DefaultSettings) do
        if CommanderTooltipDB[key] == nil then
            CommanderTooltipDB[key] = value
        end
    end
end

-- Seed defaults now for a fresh install; re-applied at PLAYER_LOGIN because
-- SavedVariables replace CommanderTooltipDB after this file has run.
ApplyDefaultSettings()

local frame = CreateFrame("FRAME")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
local loaded = false

local function Reset()
    print("Resetting Commander Tooltip")
    for key, value in pairs(DefaultSettings) do
        CommanderTooltipDB[key] = value
    end
    Notify(COMMANDER_TOOLTIP_EVENTS.UPDATE)
end

local function InitializeSlashCommands(categoryID)
    SLASH_CTOOLTIP1 = "/ctooltip"
    SlashCmdList["CTOOLTIP"] = function(msg)
        msg = msg:lower()
        if msg == "" then
            Settings.OpenToCategory(categoryID)
        end
    end
end

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Commander Tooltip"
    -- Add settings to panel
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Commander Tooltip Settings")

    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetText("Configure Commander Tooltip options below.")

    local resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetButton:SetSize(100, 22)
    resetButton:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)
    resetButton:SetText("Reset")
    resetButton:SetScript("OnClick", function() Reset() end)

    local showItemLevelCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    showItemLevelCheckbox:SetPoint("TOPLEFT", resetButton, "BOTTOMLEFT", 0, -8)
    showItemLevelCheckbox.Text:SetText("Show Item Level")
    showItemLevelCheckbox:SetChecked(CommanderTooltipDB.ShowItemLevel)
    showItemLevelCheckbox:SetScript("OnClick", function(self) CommanderTooltipDB.ShowItemLevel = self:GetChecked() Notify(COMMANDER_TOOLTIP_EVENTS.UPDATE) end)

    local showVendorPriceCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    showVendorPriceCheckbox:SetPoint("TOPLEFT", showItemLevelCheckbox, "BOTTOMLEFT", 0, -8)
    showVendorPriceCheckbox.Text:SetText("Show Vendor Price")
    showVendorPriceCheckbox:SetChecked(CommanderTooltipDB.ShowVendorPrice)
    showVendorPriceCheckbox:SetScript("OnClick", function(self) CommanderTooltipDB.ShowVendorPrice = self:GetChecked() Notify(COMMANDER_TOOLTIP_EVENTS.UPDATE) end)

    local anchorToCursorCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    anchorToCursorCheckbox:SetPoint("TOPLEFT", showVendorPriceCheckbox, "BOTTOMLEFT", 0, -8)
    anchorToCursorCheckbox.Text:SetText("Anchor to Cursor")
    anchorToCursorCheckbox:SetChecked(CommanderTooltipDB.AnchorToCursor)
    anchorToCursorCheckbox:SetScript("OnClick", function(self) CommanderTooltipDB.AnchorToCursor = self:GetChecked() Notify(COMMANDER_TOOLTIP_EVENTS.UPDATE) end)

    local anchorDropdown = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
    anchorDropdown:SetPoint("TOPLEFT", anchorToCursorCheckbox, "BOTTOMLEFT", -15, -8)
    UIDropDownMenu_SetWidth(anchorDropdown, 100)
    UIDropDownMenu_SetText(anchorDropdown, CommanderTooltipDB.Anchor)
    
    local function AnchorDropdown_Initialize(self, level)
        local info = UIDropDownMenu_CreateInfo()
        info.func = function(self)
            CommanderTooltipDB.Anchor = self.value
            UIDropDownMenu_SetText(anchorDropdown, self.value)
            Notify(COMMANDER_TOOLTIP_EVENTS.UPDATE)
        end
        
        local anchors = {"TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT"}
        for _, anchor in ipairs(anchors) do
            info.text = anchor
            info.value = anchor
            info.checked = (CommanderTooltipDB.Anchor == anchor)
            UIDropDownMenu_AddButton(info)
        end
    end
    
    UIDropDownMenu_Initialize(anchorDropdown, AnchorDropdown_Initialize)

    -- X Offset Control
    local xOffsetSlider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    xOffsetSlider:SetPoint("TOPLEFT", anchorDropdown, "BOTTOMLEFT", 15, -8)
    xOffsetSlider:SetSize(200, 22)
    xOffsetSlider:SetMinMaxValues(-50, 50)
    xOffsetSlider:SetValue(CommanderTooltipDB.xOffset)
    xOffsetSlider:SetValueStep(1)
    xOffsetSlider:SetObeyStepOnDrag(true)
    xOffsetSlider.Text:SetText("X Offset")
    xOffsetSlider.Low:SetText("-50")
    xOffsetSlider.High:SetText("+50")
    
    local xOffsetValue = xOffsetSlider:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    xOffsetValue:SetPoint("TOP", xOffsetSlider, "BOTTOM", 0, 0)
    xOffsetValue:SetText(string.format("Current: %d", CommanderTooltipDB.xOffset))
    
    xOffsetSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        CommanderTooltipDB.xOffset = value
        xOffsetValue:SetText(string.format("Current: %d", value))
        Notify(COMMANDER_TOOLTIP_EVENTS.UPDATE)
    end)

    -- Y Offset Control
    local yOffsetSlider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    yOffsetSlider:SetPoint("TOPLEFT", xOffsetSlider, "BOTTOMLEFT", 0, -24)
    yOffsetSlider:SetSize(200, 22)
    yOffsetSlider:SetMinMaxValues(-50, 50)
    yOffsetSlider:SetValue(CommanderTooltipDB.yOffset)
    yOffsetSlider:SetValueStep(1)
    yOffsetSlider:SetObeyStepOnDrag(true)
    yOffsetSlider.Text:SetText("Y Offset")
    yOffsetSlider.Low:SetText("-50")
    yOffsetSlider.High:SetText("+50")
    
    local yOffsetValue = yOffsetSlider:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    yOffsetValue:SetPoint("TOP", yOffsetSlider, "BOTTOM", 0, 0)
    yOffsetValue:SetText(string.format("Current: %d", CommanderTooltipDB.yOffset))
    
    yOffsetSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        CommanderTooltipDB.yOffset = value
        yOffsetValue:SetText(string.format("Current: %d", value))
        Notify(COMMANDER_TOOLTIP_EVENTS.UPDATE)
    end)

    -- Scale Control
    local scaleSlider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOPLEFT", yOffsetSlider, "BOTTOMLEFT", 0, -24)
    scaleSlider:SetSize(200, 22)
    scaleSlider:SetMinMaxValues(0.5, 2.0)
    scaleSlider:SetValue(CommanderTooltipDB.Scale)
    scaleSlider:SetValueStep(0.1)
    scaleSlider:SetObeyStepOnDrag(true)
    scaleSlider.Text:SetText("Tooltip Scale")
    scaleSlider.Low:SetText("50%")
    scaleSlider.High:SetText("200%")
    
    local scaleValue = scaleSlider:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    scaleValue:SetPoint("TOP", scaleSlider, "BOTTOM", 0, 0)
    scaleValue:SetText(string.format("Current: %.0f%%", CommanderTooltipDB.Scale * 100))
    
    scaleSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 10) / 10 -- Round to 1 decimal place
        CommanderTooltipDB.Scale = value
        scaleValue:SetText(string.format("Current: %.0f%%", value * 100))
        Notify(COMMANDER_TOOLTIP_EVENTS.UPDATE)
    end)

    return panel
end

local function OnUpdate()
    -- Update tooltip settings
end

local function OnAwake()
    local panel = CreateOptionsPanel()
    local category = Settings.RegisterCanvasLayoutSubcategory(MainCategory, panel, "Commander Tooltip")
    local categoryID = category:GetID()
    Settings.RegisterAddOnCategory(category)
    InitializeSlashCommands(categoryID)
    AddListener(COMMANDER_TOOLTIP_EVENTS.UPDATE, OnUpdate)
end

local function OnDestroy()
    -- Cleanup if needed
end

local function OnEvent(self, event)
    if event == "PLAYER_LOGIN" then
        ApplyDefaultSettings()
        OnAwake()
        loaded = true
    elseif event == "PLAYER_LOGOUT" then
        OnDestroy()
    elseif loaded then
        OnUpdate()
    end
end

frame:SetScript("OnEvent", OnEvent)
