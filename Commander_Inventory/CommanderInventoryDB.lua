CommanderInventoryDB = _G.CommanderInventoryDB or {}
CommanderInventoryDB.listeners = _G.CommanderInventoryDB.listeners or {}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
local loaded = false
local columnsSlider
local scaleSlider

local defaultSettings = {
    columns = 4,
    scale = 1,
    locked = false,
    tooltips = true,
    showFrame = true,
}

for key, value in pairs(defaultSettings) do
    if CommanderInventoryDB[key] == nil then
        CommanderInventoryDB[key] = value
    end
end

function AddListener(func)
    if type(func) ~= "function" then
        return
    end
    table.insert(CommanderInventoryDB.listeners, func)
end

function Notify()
    if not CommanderInventoryDB.listeners then
        CommanderInventoryDB.listeners = {}
        return
    end
    
    for _, func in ipairs(CommanderInventoryDB.listeners) do
        if type(func) == "function" then
            func()
        end
    end
end

function UpdateSlider(slider, newValue)
    slider:SetValue(newValue)   
    local valueText = slider.valueText or slider:GetFontString()
    if valueText then
        valueText:SetText(tostring(newValue))
    end
end

function Reset()
    for key in pairs(CommanderInventoryDB) do
        CommanderInventoryDB[key] = nil
    end
    CommanderInventoryDB.columns = defaultSettings.columns
    CommanderInventoryDB.scale = defaultSettings.scale
    CommanderInventoryDB.locked = defaultSettings.locked
    CommanderInventoryDB.tooltips = defaultSettings.tooltips
    CommanderInventoryDB.showFrame = defaultSettings.showFrame
    if CommanderInventoryColumnsSlider then
        CommanderInventoryColumnsSlider:SetValue(defaultSettings.columns)
        CommanderInventoryColumnsSlider.valueText:SetText(defaultSettings.columns)
    end
    if CommanderInventoryScaleSlider then
        CommanderInventoryScaleSlider:SetValue(defaultSettings.scale)
        CommanderInventoryScaleSlider.valueText:SetText(string.format("%.2f", defaultSettings.scale))
    end
    Notify()
end

function CreateColumnsSlider(panel)
    columnsSlider = CreateFrame("Slider", "CIColumnsSlider", panel, "OptionsSliderTemplate")
    columnsSlider:SetPoint("TOPLEFT", 16, -64)
    columnsSlider:SetMinMaxValues(1, 12)
    columnsSlider:SetValueStep(1)
    columnsSlider:SetObeyStepOnDrag(true)
    
    local valueText = columnsSlider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    valueText:SetPoint("TOP", columnsSlider, "BOTTOM", 0, 0)
    columnsSlider.valueText = valueText
    
    columnsSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        CommanderInventoryDB.columns = value
        self.valueText:SetText(value)
        Notify()
    end) 
    
    return columnsSlider
end

function CreateScaleSlider(panel)
    local slider = CreateFrame("Slider", "CommanderInventoryScaleSlider", panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 16, -128)
    slider:SetMinMaxValues(0.5, 2.0)
    slider:SetValueStep(0.1)
    slider:SetObeyStepOnDrag(true)

    local valueText = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    valueText:SetPoint("TOP", slider, "BOTTOM", 0, 0)
    slider.valueText = valueText
    
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 10) / 10
        CommanderInventoryDB.scale = value
        self.valueText:SetText(string.format("%.2f", value))
        Notify()
    end)
    
    return slider
end

function CreateResetButton(panel)
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(120, 22)
    button:SetPoint("TOPLEFT", 16, -16)
    button:SetText("Reset Settings")
    button:SetScript("OnClick", function()
        Reset()
    end)
    return button
end

function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Commander Inventory"
    
    CreateResetButton(panel)
    columnsSlider = CreateColumnsSlider(panel)
    scaleSlider = CreateScaleSlider(panel)
    
    return panel
end

function InitializeSlashCommands(catagory)
    SLASH_CI1 = "/ci"
    SlashCmdList["CI"] = function(msg)
        msg = msg:lower()
        if msg == "" or msg == "toggle" then
            Settings.OpenToCategory(catagory)
        elseif msg == "reset" then
            Reset()
        else
            print("Usage: /ci [toggle|reset]")
        end
    end
end

local function OnUpdate()
    if columnsSlider then
        UpdateSlider(columnsSlider, CommanderInventoryDB.columns)
    end
    if scaleSlider then
        UpdateSlider(scaleSlider, CommanderInventoryDB.scale)
    end
end

frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        local category = Settings.RegisterCanvasLayoutCategory(CreateOptionsPanel(), "Commander Inventory")
        Settings.RegisterAddOnCategory(category)
        InitializeSlashCommands(category)
        _G.CommanderInventoryDB = CommanderInventoryDB
        AddListener(OnUpdate)
        OnUpdate()
        loaded = true
    elseif loaded then
        OnUpdate()
    end
end)

return CommanderInventoryDB