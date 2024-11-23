CommanderInventoryDB = {}

local defaultSettings = {
    columns = 4,
    scale = 1,
    locked = false,
    tooltips = true,
    showFrame = true,
}

function CommanderInventoryDB:Initialize()
    if not CommanderInventoryDB then
        CommanderInventoryDB = defaultSettings
    end

    for key, value in pairs(defaultSettings) do
        if CommanderInventoryDB[key] == nil then
            CommanderInventoryDB[key] = value
        end
    end
end

function CommanderInventoryDB:Reset()
    for key, value in pairs(defaultSettings) do
        self[key] = value
    end
end

function CommanderInventoryDB:CreateColumnsSlider(panel)
    local slider = CreateFrame("Slider", "CIColumnsSlider", panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 16, -64)
    slider:SetMinMaxValues(1, 12)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(CommanderInventoryDB.columns)
    
    _G["CIColumnsSliderText"]:SetText("Columns")
    _G["CIColumnsSliderLow"]:SetText("1")
    _G["CIColumnsSliderHigh"]:SetText("12")
    
    -- Create value text
    local valueText = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    valueText:SetPoint("TOP", slider, "BOTTOM", 0, 0)
    valueText:SetText(CommanderInventoryDB.columns)
    slider.valueText = valueText
    
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        CommanderInventoryDB.columns = value
        self.valueText:SetText(value)
        if CI and CI.ItemGrid and CI.ItemGrid.UpdateButtons then
            CI.ItemGrid.UpdateButtons()
        end
    end)
    
    return slider
end

function CommanderInventoryDB:CreateResetButton(panel)
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(120, 22)
    button:SetPoint("TOPLEFT", 16, -16)
    button:SetText("Reset Settings")
    button:SetScript("OnClick", function()
        self:OnResetClicked()
    end)
    
    return button
end

function CommanderInventoryDB:OnResetClicked()
    self:Reset()
    if CI and CI.ItemGrid and CI.ItemGrid.ApplySettings then
        CI.ItemGrid.ApplySettings()
    end
end

function CommanderInventoryDB:CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Commander Inventory"
    
    self:CreateColumnsSlider(panel)
    self:CreateResetButton(panel)
    
    return panel
end

CommanderInventoryDB:Initialize()

local category = Settings.RegisterCanvasLayoutCategory(CommanderInventoryDB:CreateOptionsPanel(), "Commander Inventory")
Settings.RegisterAddOnCategory(category)

return CommanderInventoryDB