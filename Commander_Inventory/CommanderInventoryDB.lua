CommanderInventoryDB = _G.CommanderInventoryDB or {}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
local loaded = false
local columnsSlider
local scaleSlider
local tooltipsCheckbox
local lockCheckbox

local defaultSettings = {
    columns = 4,
    scale = 1,
    locked = false,
    tooltips = true,
    showFrame = true,
}

COMMANDER_INVENTORY_EVENTS = {
    COMMANDER_INVENTORY = "COMMANDER_INVENTORY",
}

for key, value in pairs(defaultSettings) do
    if CommanderInventoryDB[key] == nil then
        CommanderInventoryDB[key] = value
    end
end

local function UpdateSlider(slider, newValue)
    slider:SetValue(newValue)   
    local valueText = slider.valueText or slider:GetFontString()
    if valueText then
        valueText:SetText(tostring(newValue))
    end
end

local function Reset()
    -- Store position before reset
    local point, relativeTo, relativePoint, xOfs, yOfs
    if CIItemGrid then
        point, relativeTo, relativePoint, xOfs, yOfs = CIItemGrid:GetPoint()
    end

    -- Reset all settings
    for key in pairs(CommanderInventoryDB) do
        CommanderInventoryDB[key] = nil
    end
    
    -- Restore defaults
    CommanderInventoryDB.columns = defaultSettings.columns
    CommanderInventoryDB.scale = defaultSettings.scale
    CommanderInventoryDB.locked = defaultSettings.locked
    CommanderInventoryDB.tooltips = defaultSettings.tooltips
    CommanderInventoryDB.showFrame = defaultSettings.showFrame
    
    -- Reset UI elements
    if CIColumnsSlider then
        CIColumnsSlider:SetValue(defaultSettings.columns)
        CIColumnsSlider.valueText:SetText(defaultSettings.columns)
    end
    if CommanderInventoryScaleSlider then
        CommanderInventoryScaleSlider:SetValue(defaultSettings.scale)
        CommanderInventoryScaleSlider.valueText:SetText(string.format("%.2f", defaultSettings.scale))
    end

    -- Restore position
    if CIItemGrid then
        CIItemGrid:ClearAllPoints()
        if point then
            CIItemGrid:SetPoint(point, relativeTo, relativePoint, xOfs, yOfs)
        else
            CIItemGrid:SetPoint("CENTER")
        end
    end

    Commander.Notify(COMMANDER_INVENTORY_EVENTS.COMMANDER_INVENTORY)
end

local function ResetPosition()
    if CIItemGrid then
        CIItemGrid:ClearAllPoints()
        CIItemGrid:SetPoint("CENTER", UIParent, "CENTER")
        Commander.Notify(COMMANDER_INVENTORY_EVENTS.COMMANDER_INVENTORY)
    end
end

local function ResetBagFrames()
    print("Resetting bag frames to default positions...")
    
    -- Reset all container frames to their default positions
    for i = 1, NUM_CONTAINER_FRAMES do
        local frame = _G["ContainerFrame" .. i]
        if frame then
            -- Clear all points first to avoid anchor family connection errors
            frame:ClearAllPoints()
            
            -- Set default position - bags are typically anchored to the right side of screen
            -- ContainerFrame1 (main bag) is usually at the bottom right
            if i == 1 then
                frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 100)
            else
                -- Additional bags stack to the left of the main bag
                local prevFrame = _G["ContainerFrame" .. (i - 1)]
                if prevFrame then
                    frame:SetPoint("RIGHT", prevFrame, "LEFT", -5, 0)
                else
                    frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 100)
                end
            end
            
            -- Reset scale to default
            frame:SetScale(1.0)
            
            -- Make sure frame is not movable (default state)
            frame:SetMovable(false)
            frame:SetUserPlaced(false)
        end
    end
    
    -- Also reset the backpack button position if it exists
    if MainMenuBarBackpackButton then
        MainMenuBarBackpackButton:ClearAllPoints()
        MainMenuBarBackpackButton:SetPoint("BOTTOMRIGHT", MainMenuBar, "BOTTOMRIGHT", -4, 2)
    end
    
    -- Reset individual bag slot buttons
    for i = 0, 3 do
        local bagButton = _G["CharacterBag" .. i .. "Slot"]
        if bagButton then
            bagButton:ClearAllPoints()
            bagButton:SetPoint("BOTTOMRIGHT", MainMenuBarBackpackButton, "BOTTOMLEFT", -2, 0)
        end
    end
    
    print("Bag frames reset to default positions!")
end

local function CreateColumnsSlider(panel)
    columnsSlider = CreateFrame("Slider", "CIColumnsSlider", panel, "OptionsSliderTemplate")
    columnsSlider:SetPoint("TOPLEFT", 16, -90)
    columnsSlider:SetMinMaxValues(1, 12)
    columnsSlider:SetValueStep(1)
    columnsSlider:SetObeyStepOnDrag(true)
    
    local valueText = columnsSlider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    valueText:SetPoint("TOP", columnsSlider, "BOTTOM", 0, 0)
    columnsSlider.valueText = valueText

    -- Initialize from saved settings before hooking OnValueChanged
    UpdateSlider(columnsSlider, CommanderInventoryDB.columns)

    columnsSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        CommanderInventoryDB.columns = value
        self.valueText:SetText(value)
        Commander.Notify(COMMANDER_INVENTORY_EVENTS.COMMANDER_INVENTORY)
    end)

    return columnsSlider
end

local function CreateScaleSlider(panel)
    scaleSlider = CreateFrame("Slider", "CommanderInventoryScaleSlider", panel, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOPLEFT", 16, -160)
    scaleSlider:SetMinMaxValues(0.5, 2.0)
    scaleSlider:SetValueStep(0.1)
    scaleSlider:SetObeyStepOnDrag(true)

    -- Add a label for the slider
    local sliderLabel = scaleSlider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sliderLabel:SetPoint("TOPLEFT", -60, 0)
    sliderLabel:SetText("Scale:")

    local valueText = scaleSlider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    valueText:SetPoint("TOP", scaleSlider, "BOTTOM", 0, 0)
    scaleSlider.valueText = valueText

    -- Initialize from saved settings before hooking OnValueChanged
    UpdateSlider(scaleSlider, CommanderInventoryDB.scale)

    scaleSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 10) / 10
        CommanderInventoryDB.scale = value
        self.valueText:SetText(string.format("%.2f", value))
        Commander.Notify(COMMANDER_INVENTORY_EVENTS.COMMANDER_INVENTORY)
    end)

    return scaleSlider
end

local function CreateResetButton(panel)
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(120, 22)
    button:SetPoint("TOPLEFT", 16, -40)
    button:SetText("Reset Settings")
    button:SetScript("OnClick", function()
        Reset()
    end)
    return button
end

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Commander Inventory"
    
    -- Add a title
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Commander Inventory Settings")
    
    -- Adjust reset button position to be below title
    local resetButton = CreateResetButton(panel)
    resetButton:SetPoint("TOPLEFT", 16, -40)
    
    -- Add reset position button
    local resetPosButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetPosButton:SetSize(120, 22)
    resetPosButton:SetPoint("TOPLEFT", resetButton, "TOPRIGHT", 10, 0)
    resetPosButton:SetText("Reset Position")
    resetPosButton:SetScript("OnClick", ResetPosition)
    
    -- Add reset bags button
    local resetBagsButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBagsButton:SetSize(120, 22)
    resetBagsButton:SetPoint("TOPLEFT", resetPosButton, "TOPRIGHT", 10, 0)
    resetBagsButton:SetText("Reset Bags")
    resetBagsButton:SetScript("OnClick", ResetBagFrames)

    -- Adjust columns slider position
    columnsSlider = CreateColumnsSlider(panel)
    columnsSlider:SetPoint("TOPLEFT", 16, -90)
    
    -- Add proper labels for columns slider
    _G[columnsSlider:GetName().."Text"]:SetText("Number of Columns")
    _G[columnsSlider:GetName().."Low"]:SetText("1")
    _G[columnsSlider:GetName().."High"]:SetText("12")
    
    -- Adjust scale slider position and labels
    scaleSlider = CreateScaleSlider(panel)
    scaleSlider:SetPoint("TOPLEFT", 16, -160)
    _G[scaleSlider:GetName().."Text"]:SetText("UI Scale")
    _G[scaleSlider:GetName().."Low"]:SetText("0.5")
    _G[scaleSlider:GetName().."High"]:SetText("2.0")
    
    -- Add checkbox for tooltips
    tooltipsCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    tooltipsCheckbox:SetPoint("TOPLEFT", 16, -200)
    tooltipsCheckbox.Text:SetText("Show Tooltips")
    tooltipsCheckbox:SetChecked(CommanderInventoryDB.tooltips)
    tooltipsCheckbox:SetScript("OnClick", function(self)
        CommanderInventoryDB.tooltips = self:GetChecked()
        Commander.Notify(COMMANDER_INVENTORY_EVENTS.COMMANDER_INVENTORY)
    end)

    -- Add checkbox for frame lock
    lockCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    lockCheckbox:SetPoint("TOPLEFT", 16, -230)
    lockCheckbox.Text:SetText("Lock Frame Position")
    lockCheckbox:SetChecked(CommanderInventoryDB.locked)
    lockCheckbox:SetScript("OnClick", function(self)
        CommanderInventoryDB.locked = self:GetChecked()
        Commander.Notify(COMMANDER_INVENTORY_EVENTS.COMMANDER_INVENTORY)
    end)

    return panel
end

local function InitializeSlashCommands()
    SLASH_CI1 = "/ci"
    SlashCmdList["CI"] = function(msg)
        msg = msg:lower()
        if msg == "" or msg == "toggle" then
            CommanderInventoryDB.showFrame = not CommanderInventoryDB.showFrame
            Commander.Notify(COMMANDER_INVENTORY_EVENTS.COMMANDER_INVENTORY)
        elseif msg == "reset" then
            Reset()
        elseif msg == "center" then
            ResetPosition()
        elseif msg == "resetbags" then
            ResetBagFrames()
        else
            print("Usage: /ci [toggle|reset|center|resetbags]")
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
    if tooltipsCheckbox then
        tooltipsCheckbox:SetChecked(CommanderInventoryDB.tooltips)
    end
    if lockCheckbox then
        lockCheckbox:SetChecked(CommanderInventoryDB.locked)
    end
end

frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- Saved variables replace the table created at file load, so re-apply defaults
        -- here for any keys missing from the saved data
        for key, value in pairs(defaultSettings) do
            if CommanderInventoryDB[key] == nil then
                CommanderInventoryDB[key] = value
            end
        end

        local panel = CreateOptionsPanel()
        Settings.RegisterCanvasLayoutSubcategory(Commander.MainCategory, panel, "Commander Inventory")
        InitializeSlashCommands()
        _G.CommanderInventoryDB = CommanderInventoryDB
        Commander.AddListener(COMMANDER_INVENTORY_EVENTS.COMMANDER_INVENTORY, OnUpdate)
        loaded = true
    elseif loaded then
        OnUpdate()
    end
end)