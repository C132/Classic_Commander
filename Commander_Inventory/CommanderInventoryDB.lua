local CommanderInventoryDB = {}

local defaultSettings = {
    rows = 3,
    columns = 4,
    scale = 1,
    locked = false,
    tooltips = true,
    showFrame = true,
}

function CommanderInventoryDB:Initialize()
    if not CommanderInventoryDB then
        CommanderInventoryDB = {}
    end

    for key, value in pairs(defaultSettings) do
        if CommanderInventoryDB[key] == nil then
            CommanderInventoryDB[key] = value
        end
    end
end

function CommanderInventoryDB:GetSetting(key)
    return CommanderInventoryDB[key]
end

function CommanderInventoryDB:SetSetting(key, value)
    if defaultSettings[key] ~= nil then
        CommanderInventoryDB[key] = value
    else
        error("Attempted to set invalid setting: " .. tostring(key))
    end
end

function CommanderInventoryDB:CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Commander Inventory"
    
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Commander Inventory Options")
    
    local function CreateSlider(name, min, max, step)
        local slider = CreateFrame("Slider", "CI_" .. name .. "Slider", panel, "OptionsSliderTemplate")
        slider:SetWidth(200)
        slider:SetMinMaxValues(min, max)
        slider:SetValueStep(step)
        slider:SetObeyStepOnDrag(true)
        
        local label = slider:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        label:SetPoint("BOTTOM", slider, "TOP", 0, 5)
        label:SetText(name:gsub("^%l", string.upper):gsub("(%u)(%u%l)", "%1 %2"))
        
        local valueText = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        valueText:SetPoint("TOP", slider, "BOTTOM", 0, -5)
        
        slider:SetScript("OnValueChanged", function(self, value)
            local roundedValue = math.floor(value * 100 + 0.5) / 100
            CommanderInventoryDB:SetSetting(name, roundedValue)
            valueText:SetText(string.format("%.2f", roundedValue))
        end)
        
        slider:SetValue(CommanderInventoryDB:GetSetting(name))
        valueText:SetText(string.format("%.2f", CommanderInventoryDB:GetSetting(name)))
        
        return slider
    end
    
    local rowsSlider = CreateSlider("rows", 1, 10, 1)
    rowsSlider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -40)
    
    local columnsSlider = CreateSlider("columns", 1, 10, 1)
    columnsSlider:SetPoint("TOPLEFT", rowsSlider, "BOTTOMLEFT", 0, -40)
    
    local scaleSlider = CreateSlider("scale", 0.5, 2, 0.05)
    scaleSlider:SetPoint("TOPLEFT", columnsSlider, "BOTTOMLEFT", 0, -40)
    
    local function CreateCheckbox(name)
        local checkbox = CreateFrame("CheckButton", "CI_" .. name .. "Checkbox", panel, "InterfaceOptionsCheckButtonTemplate")
        checkbox.Text:SetText(name:gsub("^%l", string.upper):gsub("(%u)(%u%l)", "%1 %2"))
        checkbox:SetChecked(CommanderInventoryDB:GetSetting(name))
        
        checkbox:SetScript("OnClick", function(self)
            CommanderInventoryDB:SetSetting(name, self:GetChecked())
        end)
        
        return checkbox
    end
    
    local lockedCheckbox = CreateCheckbox("locked")
    lockedCheckbox:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, -20)
    
    local tooltipsCheckbox = CreateCheckbox("tooltips") 
    tooltipsCheckbox:SetPoint("TOPLEFT", lockedCheckbox, "BOTTOMLEFT", 0, -10)
    
    local showFrameCheckbox = CreateCheckbox("showFrame")
    showFrameCheckbox:SetPoint("TOPLEFT", tooltipsCheckbox, "BOTTOMLEFT", 0, -10)
    
    return panel
end

CommanderInventoryDB:Initialize()

local optionsPanel = CommanderInventoryDB:CreateOptionsPanel()
optionsPanel.name = "Commander"
local catagory = Settings.RegisterCanvasLayoutCategory(optionsPanel, "Commander Inventory")
Settings.RegisterAddOnCategory(catagory, "Commander Inventory")

return CommanderInventoryDB