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

    Notify(COMMANDER_INVENTORY_EVENTS.COMMANDER_INVENTORY)
end

local function ResetPosition()
    if CIItemGrid then
        CIItemGrid:ClearAllPoints()
        CIItemGrid:SetPoint("CENTER", UIParent, "CENTER")
        Notify(COMMANDER_INVENTORY_EVENTS.COMMANDER_INVENTORY)
    end
end

local function ResetBagFrames()
    print("Resetting ALL bag and inventory frames to default positions...")
    
    -- Reset standard WoW container frames
    for i = 1, NUM_CONTAINER_FRAMES do
        local frame = _G["ContainerFrame" .. i]
        if frame then
            frame:ClearAllPoints()
            frame:SetScale(1.0)
            frame:SetMovable(false)
            frame:SetUserPlaced(false)
            
            if i == 1 then
                frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 100)
            else
                local prevFrame = _G["ContainerFrame" .. (i - 1)]
                if prevFrame then
                    frame:SetPoint("RIGHT", prevFrame, "LEFT", -5, 0)
                else
                    frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 100)
                end
            end
        end
    end
    
    -- Reset backpack button
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
    
    -- Reset any custom inventory addon frames (like the ones in your screenshot)
    local customFrames = {
        -- Common custom inventory frame names
        "CharacterFrame",
        "PaperDollFrame", 
        "InventoryFrame",
        "BagFrame",
        "ContainerFrame",
        "ItemFrame",
        "InventoryGrid",
        "BagGrid",
        -- Add more as needed
    }
    
    for _, frameName in ipairs(customFrames) do
        local frame = _G[frameName]
        if frame and frame:IsShown() then
            print("Resetting custom frame: " .. frameName)
            frame:ClearAllPoints()
            frame:SetScale(1.0)
            frame:SetMovable(false)
            frame:SetUserPlaced(false)
            frame:SetPoint("CENTER", UIParent, "CENTER")
        end
    end
    
    -- Reset any frames with "Bag" in the name
    for i = 1, 20 do
        local frame = _G["BagFrame" .. i] or _G["InventoryFrame" .. i] or _G["ContainerFrame" .. i]
        if frame then
            frame:ClearAllPoints()
            frame:SetScale(1.0)
            frame:SetMovable(false)
            frame:SetUserPlaced(false)
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    end
    
    -- Hide all bag frames first, then show them in default positions
    for i = 1, NUM_CONTAINER_FRAMES do
        local frame = _G["ContainerFrame" .. i]
        if frame then
            frame:Hide()
        end
    end
    
    -- Force a UI reload to ensure all changes take effect
    C_Timer.After(0.5, function()
        print("All bag frames reset! Reloading UI to ensure changes take effect...")
        ReloadUI()
    end)
end

local function ResetBagFramesImmediate()
    print("Resetting bag frames to default positions (immediate)...")
    
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

local function NuclearBagReset()
    print("NUCLEAR BAG RESET - Closing all bags and resetting everything...")
    
    -- Close all bag windows first
    for i = 1, NUM_CONTAINER_FRAMES do
        local frame = _G["ContainerFrame" .. i]
        if frame then
            frame:Hide()
        end
    end
    
    -- Close character frame if open
    if CharacterFrame and CharacterFrame:IsShown() then
        CharacterFrame:Hide()
    end
    
    -- Close any other inventory-related frames
    local framesToClose = {
        "PaperDollFrame",
        "InventoryFrame", 
        "BagFrame",
        "ItemFrame",
        "InventoryGrid",
        "BagGrid"
    }
    
    for _, frameName in ipairs(framesToClose) do
        local frame = _G[frameName]
        if frame and frame:IsShown() then
            frame:Hide()
        end
    end
    
    -- Reset all possible bag-related frames
    for i = 1, 20 do
        local frameNames = {
            "ContainerFrame" .. i,
            "BagFrame" .. i,
            "InventoryFrame" .. i,
            "ItemFrame" .. i
        }
        
        for _, frameName in ipairs(frameNames) do
            local frame = _G[frameName]
            if frame then
                frame:ClearAllPoints()
                frame:SetScale(1.0)
                frame:SetMovable(false)
                frame:SetUserPlaced(false)
                frame:Hide()
            end
        end
    end
    
    -- Reset backpack button
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
    
    print("Nuclear reset complete! All bags closed and reset. Use /reload to see changes.")
end

local function DebugBagFrames()
    print("=== BAG FRAME DEBUG INFO ===")
    
    -- Check standard container frames
    for i = 1, NUM_CONTAINER_FRAMES do
        local frame = _G["ContainerFrame" .. i]
        if frame then
            local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint()
            print(string.format("ContainerFrame%d: %s, %s, %s, %.1f, %.1f, Visible: %s", 
                i, tostring(point), tostring(relativeTo), tostring(relativePoint), 
                xOfs or 0, yOfs or 0, tostring(frame:IsShown())))
        end
    end
    
    -- Check for custom frames
    local customFrames = {
        "CharacterFrame", "PaperDollFrame", "InventoryFrame", "BagFrame", 
        "ContainerFrame", "ItemFrame", "InventoryGrid", "BagGrid"
    }
    
    for _, frameName in ipairs(customFrames) do
        local frame = _G[frameName]
        if frame then
            local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint()
            print(string.format("%s: %s, %s, %s, %.1f, %.1f, Visible: %s", 
                frameName, tostring(point), tostring(relativeTo), tostring(relativePoint), 
                xOfs or 0, yOfs or 0, tostring(frame:IsShown())))
        end
    end
    
    -- Check for numbered frames
    for i = 1, 10 do
        local frameNames = {"BagFrame" .. i, "InventoryFrame" .. i, "ItemFrame" .. i}
        for _, frameName in ipairs(frameNames) do
            local frame = _G[frameName]
            if frame then
                local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint()
                print(string.format("%s: %s, %s, %s, %.1f, %.1f, Visible: %s", 
                    frameName, tostring(point), tostring(relativeTo), tostring(relativePoint), 
                    xOfs or 0, yOfs or 0, tostring(frame:IsShown())))
            end
        end
    end
    
    print("=== END DEBUG INFO ===")
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
        -- Skip the full bag scan while the options panel isn't visible
        if not debugFrame:IsVisible() then
            return
        end

        local totalItems = 0
        local inventoryItems = 0
        local bagItems = 0
        local itemsList = {}
        local buttons = _G.CIButtons or {}  -- Get buttons safely

        -- Count and collect inventory items
        for i = 1, 19 do
            local itemID = GetInventoryItemID("player", i)
            if itemID then
                local isUsable = C_Item.IsUsableItem(itemID)
                local hasSpell = C_Item.GetItemSpell(itemID)
                local name = C_Item.GetItemInfo(itemID)
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
                    local isUsable = C_Item.IsUsableItem(itemID)
                    local hasSpell = C_Item.GetItemSpell(itemID)
                    local name = C_Item.GetItemInfo(itemID)
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
                    local itemName = button.itemLink and C_Item.GetItemInfo(button.itemLink) or "unknown"
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
    debugFrame:SetScript("OnShow", UpdateDebugInfo)

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
    
    -- Add reset bags button
    local resetBagsButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBagsButton:SetSize(120, 22)
    resetBagsButton:SetPoint("TOPLEFT", resetPosButton, "TOPRIGHT", 10, 0)
    resetBagsButton:SetText("Reset Bags")
    resetBagsButton:SetScript("OnClick", ResetBagFrames)
    
    -- Add immediate reset bags button
    local resetBagsNowButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBagsNowButton:SetSize(120, 22)
    resetBagsNowButton:SetPoint("TOPLEFT", resetBagsButton, "BOTTOMLEFT", 0, -5)
    resetBagsNowButton:SetText("Reset Bags (No Reload)")
    resetBagsNowButton:SetScript("OnClick", ResetBagFramesImmediate)
    
    -- Add nuclear reset button
    local nuclearResetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    nuclearResetButton:SetSize(120, 22)
    nuclearResetButton:SetPoint("TOPLEFT", resetBagsNowButton, "BOTTOMLEFT", 0, -5)
    nuclearResetButton:SetText("NUCLEAR RESET")
    nuclearResetButton:SetScript("OnClick", NuclearBagReset)
    
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
    _G.CIDebugFrame = debugFrame  -- Expose for event logging from CommanderInventory.lua

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
        elseif msg == "resetbags" then
            ResetBagFrames()
        elseif msg == "resetbagsnow" then
            ResetBagFramesImmediate()
        elseif msg == "nuclear" then
            NuclearBagReset()
        elseif msg == "debug" then
            DebugBagFrames()
        else
            print("Usage: /ci [toggle|reset|center|resetbags|resetbagsnow|nuclear|debug]")
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
        -- Saved variables replace the table created at file load, so re-apply defaults
        -- here for any keys missing from the saved data
        for key, value in pairs(defaultSettings) do
            if CommanderInventoryDB[key] == nil then
                CommanderInventoryDB[key] = value
            end
        end

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