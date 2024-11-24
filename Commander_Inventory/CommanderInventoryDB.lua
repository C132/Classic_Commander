CommanderInventoryDB = CommanderInventoryDB or {}

defaultSettings = {
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

function CreateColumnsSlider(panel)
    local slider = CreateFrame("Slider", "CIColumnsSlider", panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 16, -64)
    slider:SetMinMaxValues(1, 12)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(CommanderInventoryDB.columns)
    
    _G["CIColumnsSliderText"]:SetText("Columns")
    _G["CIColumnsSliderLow"]:SetText("1")
    _G["CIColumnsSliderHigh"]:SetText("12")
    
    local valueText = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    valueText:SetPoint("TOP", slider, "BOTTOM", 0, 0)
    valueText:SetText(CommanderInventoryDB.columns)
    slider.valueText = valueText
    
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        CommanderInventoryDB.columns = value
        self.valueText:SetText(value)
        UpdateButtons()
    end)
    
    return slider
end

function CreateResetButton(panel)
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(120, 22)
    button:SetPoint("TOPLEFT", 16, -16)
    button:SetText("Reset Settings")
    button:SetScript("OnClick", function()
        CommanderInventoryDB:Reset()
    end)
    return button
end

function CommanderInventoryDB:Reset()
    for key in pairs(CommanderInventoryDB) do
        CommanderInventoryDB[key] = nil
    end
    CommanderInventoryDB.columns = defaultSettings.columns
    CommanderInventoryDB.scale = defaultSettings.scale
    CommanderInventoryDB.locked = defaultSettings.locked
    CommanderInventoryDB.tooltips = defaultSettings.tooltips
    CommanderInventoryDB.showFrame = defaultSettings.showFrame
    UpdateButtons()
    if CommanderInventoryColumnsSlider then
        CommanderInventoryColumnsSlider:SetValue(defaultSettings.columns)
        CommanderInventoryColumnsSlider.valueText:SetText(defaultSettings.columns)
    end
    if CommanderInventoryScaleSlider then
        CommanderInventoryScaleSlider:SetValue(defaultSettings.scale)
        CommanderInventoryScaleSlider.valueText:SetText(string.format("%.2f", defaultSettings.scale))
    end
    print("Commander Inventory settings reset.")
end

function CreateScaleSlider(panel)
    local slider = CreateFrame("Slider", "CommanderInventoryScaleSlider", panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 16, -128)
    slider:SetMinMaxValues(0.5, 2.0)
    slider:SetValueStep(0.1)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(CommanderInventoryDB.scale)
    
    _G["CommanderInventoryScaleSliderText"]:SetText("Scale")
    _G["CommanderInventoryScaleSliderLow"]:SetText("0.5")
    _G["CommanderInventoryScaleSliderHigh"]:SetText("2.0")
    
    local valueText = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    valueText:SetPoint("TOP", slider, "BOTTOM", 0, 0)
    valueText:SetText(string.format("%.2f", CommanderInventoryDB.scale))
    slider.valueText = valueText
    
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 10) / 10
        CommanderInventoryDB.scale = value
        self.valueText:SetText(string.format("%.2f", value))
        ItemGrid:SetScale(value)
    end)
    
    return slider
end

function CommanderInventoryDB:CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Commander Inventory"
    
    CreateResetButton(panel)
    CreateColumnsSlider(panel)
    CreateScaleSlider(panel)
    
    return panel
end

CommanderInventoryDB:Initialize()

local category = Settings.RegisterCanvasLayoutCategory(CommanderInventoryDB:CreateOptionsPanel(), "Commander Inventory")
Settings.RegisterAddOnCategory(category)

_G.CommanderInventoryDB = CommanderInventoryDB
return CommanderInventoryDB