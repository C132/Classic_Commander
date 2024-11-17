local CommanderInventorySettings = {}

-- Initialize default settings
local defaultSettings = {
    rows = 3,
    columns = 4,
    scale = 1,
    locked = false,
    showTooltips = true,
    showCooldowns = true,
    showKeybinds = true,
    buttonSize = 36,
    spacing = 2,
    prioritizeColumns = true,
    showFrame = true, -- New setting for frame visibility
}

-- Function to initialize or load settings
function CommanderInventorySettings:Initialize()
    if not CommanderInventoryDB then
        CommanderInventoryDB = {}
    end

    for key, value in pairs(defaultSettings) do
        if CommanderInventoryDB[key] == nil then
            CommanderInventoryDB[key] = value
        end
    end

    self:ApplySettings()
end

-- Function to get a setting
function CommanderInventorySettings:GetSetting(key)
    return CommanderInventoryDB[key]
end

-- Function to set a setting
function CommanderInventorySettings:SetSetting(key, value)
    if defaultSettings[key] ~= nil then
        CommanderInventoryDB[key] = value
        self:ApplySettings()
    else
        error("Attempted to set invalid setting: " .. tostring(key))
    end
end

-- Function to reset settings to default
function CommanderInventorySettings:ResetToDefault()
    for key, value in pairs(defaultSettings) do
        CommanderInventoryDB[key] = value
    end
    self:ApplySettings()
end

-- Function to create options panel
function CommanderInventorySettings:CreateOptionsPanel()
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
            CommanderInventorySettings:SetSetting(name, roundedValue)
            valueText:SetText(string.format("%.2f", roundedValue))
        end)
        
        slider:SetValue(self:GetSetting(name))
        valueText:SetText(string.format("%.2f", self:GetSetting(name)))
        
        return slider
    end
    
    local rowsSlider = CreateSlider("rows", 1, 10, 1)
    rowsSlider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -40)
    
    local columnsSlider = CreateSlider("columns", 1, 10, 1)
    columnsSlider:SetPoint("TOPLEFT", rowsSlider, "BOTTOMLEFT", 0, -40)
    
    local scaleSlider = CreateSlider("scale", 0.5, 2, 0.05)
    scaleSlider:SetPoint("TOPLEFT", columnsSlider, "BOTTOMLEFT", 0, -40)
    
    local buttonSizeSlider = CreateSlider("buttonSize", 20, 60, 1)
    buttonSizeSlider:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, -40)
    
    local spacingSlider = CreateSlider("spacing", 0, 10, 1)
    spacingSlider:SetPoint("TOPLEFT", buttonSizeSlider, "BOTTOMLEFT", 0, -40)
    
    local function CreateCheckbox(name)
        local checkbox = CreateFrame("CheckButton", "CI_" .. name .. "Checkbox", panel, "InterfaceOptionsCheckButtonTemplate")
        checkbox.Text:SetText(name:gsub("^%l", string.upper):gsub("(%u)(%u%l)", "%1 %2"))
        checkbox:SetChecked(self:GetSetting(name))
        
        checkbox:SetScript("OnClick", function(self)
            CommanderInventorySettings:SetSetting(name, self:GetChecked())
        end)
        
        return checkbox
    end
    
    local lockedCheckbox = CreateCheckbox("locked")
    lockedCheckbox:SetPoint("TOPLEFT", spacingSlider, "BOTTOMLEFT", 0, -20)
    
    local showTooltipsCheckbox = CreateCheckbox("showTooltips")
    showTooltipsCheckbox:SetPoint("TOPLEFT", lockedCheckbox, "BOTTOMLEFT", 0, -10)
    
    local showCooldownsCheckbox = CreateCheckbox("showCooldowns")
    showCooldownsCheckbox:SetPoint("TOPLEFT", showTooltipsCheckbox, "BOTTOMLEFT", 0, -10)
    
    local showKeybindsCheckbox = CreateCheckbox("showKeybinds")
    showKeybindsCheckbox:SetPoint("TOPLEFT", showCooldownsCheckbox, "BOTTOMLEFT", 0, -10)
    
    local prioritizeColumnsCheckbox = CreateCheckbox("prioritizeColumns")
    prioritizeColumnsCheckbox:SetPoint("TOPLEFT", showKeybindsCheckbox, "BOTTOMLEFT", 0, -10)
    
    local showFrameCheckbox = CreateCheckbox("showFrame")
    showFrameCheckbox:SetPoint("TOPLEFT", prioritizeColumnsCheckbox, "BOTTOMLEFT", 0, -10)
    
    return panel
end

-- Function to apply settings
function CommanderInventorySettings:ApplySettings()
    if CI and CI.ItemGrid and CI.ItemGrid.ApplySettings then
        CI.ItemGrid.ApplySettings()
    end
    
    -- Apply frame visibility setting
    if CI and CI.ItemGrid then
        if self:GetSetting("showFrame") then
            CI.ItemGrid:Show()
        else
            CI.ItemGrid:Hide()
        end
    end
end

-- Initialize settings when this file is loaded
CommanderInventorySettings:Initialize()

-- Create options panel
local optionsPanel = CommanderInventorySettings:CreateOptionsPanel()
Settings.RegisterCanvasLayoutCategory(optionsPanel, "Commander Inventory")

-- Register events for saving and loading settings
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("ADDON_LOADED")

eventFrame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Inventory" then
        CommanderInventorySettings:Initialize()
    elseif event == "PLAYER_LOGIN" then
        CommanderInventorySettings:ApplySettings()
    elseif event == "PLAYER_LOGOUT" then
        -- Settings are automatically saved because we're directly modifying CommanderInventoryDB
    end
end)

-- Return the settings manager
return CommanderInventorySettings
