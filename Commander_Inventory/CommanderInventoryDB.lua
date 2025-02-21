CommanderInventoryDB = _G.CommanderInventoryDB or {}

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
    if CommanderInventoryColumnsSlider then
        CommanderInventoryColumnsSlider:SetValue(defaultSettings.columns)
        CommanderInventoryColumnsSlider.valueText:SetText(defaultSettings.columns)
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

    Notify(COMMANDER_INVENTORY_EVENTS.COMMANDER_INVENTORY)
end

local function ResetPosition()
    if ItemGrid then
        ItemGrid:ClearAllPoints()
        ItemGrid:SetPoint("CENTER", UIParent, "CENTER")
        Notify(COMMANDER_INVENTORY_EVENTS.COMMANDER_INVENTORY)
    end
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
    
    columnsSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        CommanderInventoryDB.columns = value
        self.valueText:SetText(value)
        Notify(COMMANDER_INVENTORY_EVENTS.COMMANDER_INVENTORY)
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

    scaleSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 10) / 10
        CommanderInventoryDB.scale = value
        self.valueText:SetText(string.format("%.2f", value))
        Notify(COMMANDER_INVENTORY_EVENTS.COMMANDER_INVENTORY)
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

local function CreateDebugInfo(panel)
    local debugFrame = CreateFrame("Frame", nil, panel)
    debugFrame:SetSize(400, 300)
    debugFrame:SetPoint("TOPLEFT", 16, -270)
    
    -- Create a scrollable container for debug info
    local scrollFrame = CreateFrame("ScrollFrame", nil, debugFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetSize(380, 280)
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(360, 500)  -- Make it tall enough for all debug info
    scrollFrame:SetScrollChild(content)
    
    -- Title
    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT")
    title:SetText("Debug Information")
    
    -- Create debug text sections
    local sections = {
        itemCount = content:CreateFontString(nil, "ARTWORK", "GameFontNormal"),
        frameInfo = content:CreateFontString(nil, "ARTWORK", "GameFontNormal"),
        buttonInfo = content:CreateFontString(nil, "ARTWORK", "GameFontNormal"),
        itemDetails = content:CreateFontString(nil, "ARTWORK", "GameFontNormal"),
        eventLog = content:CreateFontString(nil, "ARTWORK", "GameFontNormal"),
    }
    
    sections.itemCount:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    sections.frameInfo:SetPoint("TOPLEFT", sections.itemCount, "BOTTOMLEFT", 0, -10)
    sections.buttonInfo:SetPoint("TOPLEFT", sections.frameInfo, "BOTTOMLEFT", 0, -10)
    sections.itemDetails:SetPoint("TOPLEFT", sections.buttonInfo, "BOTTOMLEFT", 0, -10)
    sections.eventLog:SetPoint("TOPLEFT", sections.itemDetails, "BOTTOMLEFT", 0, -10)
    
    -- Event logging
    local eventLog = {}
    local function LogEvent(event, ...)
        table.insert(eventLog, 1, string.format("[%s] %s: %s", 
            date("%H:%M:%S"), event, table.concat({...}, ", ")))
        if #eventLog > 10 then table.remove(eventLog) end
    end
    
    local function UpdateDebugInfo()
        local totalItems = 0
        local inventoryItems = 0
        local bagItems = 0
        local itemsList = {}
        local buttons = _G.CIButtons or {}  -- Get buttons safely
        
        -- Count and collect inventory items
        for i = 1, 19 do
            local itemID = GetInventoryItemID("player", i)
            if itemID then
                local isUsable = IsUsableItem(itemID)
                local hasSpell = GetItemSpell(itemID)
                local name = GetItemInfo(itemID)
                table.insert(itemsList, string.format("Equipped[%d]: %s (ID: %d, Usable: %s, Spell: %s)",
                    i, name or "unknown", itemID, tostring(isUsable), tostring(hasSpell ~= nil)))
                if isUsable or hasSpell then
                    inventoryItems = inventoryItems + 1
                    totalItems = totalItems + 1
                end
            end
        end
        
        -- Count and collect bag items
        for bag = 0, NUM_BAG_FRAMES do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local itemID = C_Container.GetContainerItemID(bag, slot)
                if itemID then
                    local isUsable = IsUsableItem(itemID)
                    local hasSpell = GetItemSpell(itemID)
                    local name = GetItemInfo(itemID)
                    table.insert(itemsList, string.format("Bag[%d,%d]: %s (ID: %d, Usable: %s, Spell: %s)",
                        bag, slot, name or "unknown", itemID, tostring(isUsable), tostring(hasSpell ~= nil)))
                    if isUsable or hasSpell then
                        bagItems = bagItems + 1
                        totalItems = totalItems + 1
                    end
                end
            end
        end
        
        -- Update sections with error handling
        sections.itemCount:SetText(string.format(
            "Item Counts:\n" ..
            "Total Usable Items: %d\n" ..
            "Equipped Items: %d\n" ..
            "Bag Items: %d\n" ..
            "Visible Buttons: %d\n" ..
            "Total Buttons: %d",
            totalItems, inventoryItems, bagItems, 
            #buttons,  -- This is now safe since we have a default empty table
            totalItems))  -- Expected number of buttons
        
        if CIItemGrid then
            local point, _, _, x, y = CIItemGrid:GetPoint()
            local scale = CIItemGrid:GetScale()
            local shown = CIItemGrid:IsShown()
            sections.frameInfo:SetText(string.format(
                "\nFrame Status:\n" ..
                "Position: %s [%.0f, %.0f]\n" ..
                "Scale: %.2f\n" ..
                "Visible: %s\n" ..
                "Size: %dx%d",
                point or "nil", x or 0, y or 0, scale, 
                tostring(shown),
                CIItemGrid:GetWidth() or 0,
                CIItemGrid:GetHeight() or 0))
        else
            sections.frameInfo:SetText("\nFrame Status: Not created")
        end
        
        -- Button information with more detail
        local buttonStatus = {}
        if #buttons > 0 then
            for i, button in ipairs(buttons) do
                if button:IsShown() then
                    local itemName = button.itemLink and GetItemInfo(button.itemLink) or "unknown"
                    table.insert(buttonStatus, string.format(
                        "Button[%d]: ItemID=%s, Name=%s, Visible=%s, Position=[%d,%d]",
                        i, tostring(button.itemID),
                        itemName,
                        tostring(button:IsVisible()),
                        button:GetLeft() or 0,
                        button:GetTop() or 0))
                end
            end
        else
            table.insert(buttonStatus, "No buttons created yet")
        end
        
        sections.buttonInfo:SetText(string.format(
            "\nButton Status: (Total: %d)\n%s",
            #buttons,
            table.concat(buttonStatus, "\n")))
        
        -- Add mismatch warning if needed
        if totalItems ~= #buttons then
            sections.buttonInfo:SetText(sections.buttonInfo:GetText() .. string.format(
                "\n\nWARNING: Mismatch between usable items (%d) and buttons (%d)",
                totalItems, #buttons))
        end
        
        -- Item details
        sections.itemDetails:SetText(string.format(
            "\nDetailed Item List:\n%s",
            table.concat(itemsList, "\n")))
        
        -- Event log
        sections.eventLog:SetText(string.format(
            "\nRecent Events:\n%s",
            table.concat(eventLog, "\n")))
    end
    
    -- Add refresh button
    local refreshButton = CreateFrame("Button", nil, debugFrame, "UIPanelButtonTemplate")
    refreshButton:SetSize(80, 22)
    refreshButton:SetPoint("TOPRIGHT", debugFrame, "TOPRIGHT", 0, 0)
    refreshButton:SetText("Refresh")
    refreshButton:SetScript("OnClick", UpdateDebugInfo)
    
    debugFrame.Update = UpdateDebugInfo
    debugFrame.LogEvent = LogEvent
    
    -- Register for updates
    AddListener(COMMANDER_INVENTORY_EVENTS.COMMANDER_INVENTORY, UpdateDebugInfo)
    C_Timer.NewTicker(1, UpdateDebugInfo)
    
    return debugFrame
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
    local tooltipsCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    tooltipsCheckbox:SetPoint("TOPLEFT", 16, -200)
    tooltipsCheckbox.Text:SetText("Show Tooltips")
    tooltipsCheckbox:SetChecked(CommanderInventoryDB.tooltips)
    tooltipsCheckbox:SetScript("OnClick", function(self)
        CommanderInventoryDB.tooltips = self:GetChecked()
        Notify(COMMANDER_INVENTORY_EVENTS.COMMANDER_INVENTORY)
    end)
    
    -- Add checkbox for frame lock
    local lockCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    lockCheckbox:SetPoint("TOPLEFT", 16, -230)
    lockCheckbox.Text:SetText("Lock Frame Position")
    lockCheckbox:SetChecked(CommanderInventoryDB.locked)
    lockCheckbox:SetScript("OnClick", function(self)
        CommanderInventoryDB.locked = self:GetChecked()
        Notify(COMMANDER_INVENTORY_EVENTS.COMMANDER_INVENTORY)
    end)
    
    -- Add debug info after the checkboxes
    local debugFrame = CreateDebugInfo(panel)
    
    return panel
end

local function InitializeSlashCommands(categoryID)
    SLASH_CI1 = "/ci"
    SlashCmdList["CI"] = function(msg)
        msg = msg:lower()
        if msg == "" or msg == "toggle" then
            CommanderInventoryDB.showFrame = not CommanderInventoryDB.showFrame
            Notify(COMMANDER_INVENTORY_EVENTS.COMMANDER_INVENTORY)
        elseif msg == "reset" then
            Reset()
        elseif msg == "center" then
            ResetPosition()
        else
            print("Usage: /ci [toggle|reset|center]")
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
        local panel = CreateOptionsPanel()
        local category = Settings.RegisterCanvasLayoutSubcategory(MainCategory, panel, "Commander Inventory")
        local categoryID = category:GetID()
        Settings.RegisterAddOnCategory(category)
        InitializeSlashCommands(categoryID)
        _G.CommanderInventoryDB = CommanderInventoryDB
        AddListener(COMMANDER_INVENTORY_EVENTS.COMMANDER_INVENTORY, OnUpdate)
        OnUpdate()
        loaded = true
    elseif loaded then
        OnUpdate()
    end
end)

return CommanderInventoryDB