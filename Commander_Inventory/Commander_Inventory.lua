local addonName, CI = ...
local L = CI.L or {} -- Use an empty table if L is nil

-- Default settings
local defaults = {
    scale = 1,
    locked = false,
    showTooltips = true,
    showCooldowns = true,
    showKeybinds = true,
    buttonSize = 36,
    spacing = 2,
    columns = 4,
    rows = 3,
    prioritizeColumns = true, -- If true, columns take precedence; if false, rows do
    showFrame = true, -- New setting for frame visibility
}

-- Initialize or load settings
if not CommanderInventoryDB then
    CommanderInventoryDB = {}
end

-- Merge defaults with saved settings
for k, v in pairs(defaults) do
    if CommanderInventoryDB[k] == nil then
        CommanderInventoryDB[k] = v
    end
end

-- Create main frame
local ItemGrid = CreateFrame("Frame", "CIItemGrid", UIParent, "BasicFrameTemplateWithInset")
ItemGrid:SetPoint("CENTER")
ItemGrid:SetMovable(true)
ItemGrid:SetClampedToScreen(true)
ItemGrid:EnableMouse(true)
ItemGrid:RegisterForDrag("LeftButton")
ItemGrid:SetScript("OnDragStart", function(self)
    if not CommanderInventoryDB.locked then
        self:StartMoving()
    end
end)
ItemGrid:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
end)
ItemGrid:SetShown(CommanderInventoryDB.showFrame)

ItemGrid.TitleText:SetText(L["Commander Inventory"] or "Commander Inventory")

-- Create buttons container
local ButtonsContainer = CreateFrame("Frame", nil, ItemGrid)
ButtonsContainer:SetPoint("TOPLEFT", ItemGrid, "TOPLEFT", 7, -25)
ButtonsContainer:SetPoint("BOTTOMRIGHT", ItemGrid, "BOTTOMRIGHT", -7, 7)

-- Create buttons
local buttons = {}
local function CreateButton(index)
    local button = CreateFrame("Button", "CIItemButton"..index, ButtonsContainer, "SecureActionButtonTemplate, ActionButtonTemplate")
    button:SetSize(CommanderInventoryDB.buttonSize, CommanderInventoryDB.buttonSize)
    button:SetAttribute("type", "item")
    button:SetScript("OnEnter", function(self)
        if CommanderInventoryDB.showTooltips then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.itemLink then
                GameTooltip:SetHyperlink(self.itemLink)
            end
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

-- Function to update button cooldowns
local function UpdateCooldowns()
    for _, button in ipairs(buttons) do
        if button.itemID then
            local start, duration, enable = C_Container.GetItemCooldown(button.itemID)
            if CommanderInventoryDB.showCooldowns and duration > 0 then
                button.cooldown:SetCooldown(start, duration)
                button.cooldown:Show()
            else
                button.cooldown:Hide()
            end
        end
    end
end

-- Function to update button contents
local function UpdateButtons()
    local index = 1
    local itemIDs = {}
    
    -- Check equipped items
    for i = 1, 19 do -- 19 equipment slots
        local itemID = GetInventoryItemID("player", i)
        if itemID and IsUsableItem(itemID) and not itemIDs[itemID] then
            itemIDs[itemID] = true
            if not buttons[index] then
                buttons[index] = CreateButton(index)
            end
            local button = buttons[index]
            local texture = GetInventoryItemTexture("player", i)
            local itemLink = GetInventoryItemLink("player", i)
            local count = GetItemCount(itemID)
            
            button.icon:SetTexture(texture)
            button.itemLink = itemLink
            button.itemID = itemID
            button:SetAttribute("item", "item:"..itemID)
            
            if count > 1 then
                button.Count:SetText(count)
                button.Count:Show()
            else
                button.Count:Hide()
            end
            
            button:Show()
            index = index + 1
        end
    end
    
    -- Check bag items
    for bag = 0, NUM_BAG_FRAMES do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID and IsUsableItem(itemID) and not itemIDs[itemID] then
                itemIDs[itemID] = true
                if not buttons[index] then
                    buttons[index] = CreateButton(index)
                end
                local button = buttons[index]
                local texture = GetItemIcon(itemID)
                local itemLink = C_Container.GetContainerItemLink(bag, slot)
                local count = GetItemCount(itemID)
                
                button.icon:SetTexture(texture)
                button.itemLink = itemLink
                button.itemID = itemID
                button:SetAttribute("item", "item:"..itemID)
                
                if count > 1 then
                    button.Count:SetText(count)
                    button.Count:Show()
                else
                    button.Count:Hide()
                end
                
                button:Show()
                index = index + 1
            end
        end
    end
    
    -- Hide unused buttons
    for i = index, #buttons do
        buttons[i]:Hide()
    end
    
    -- Calculate rows and columns based on settings
    local itemCount = index - 1
    local rows, columns
    if CommanderInventoryDB.prioritizeColumns then
        columns = math.min(CommanderInventoryDB.columns, itemCount)
        rows = math.ceil(itemCount / columns)
    else
        rows = math.min(CommanderInventoryDB.rows, itemCount)
        columns = math.ceil(itemCount / rows)
    end
    
    -- Update frame size
    local width = columns * (CommanderInventoryDB.buttonSize + CommanderInventoryDB.spacing) + CommanderInventoryDB.spacing
    local height = rows * (CommanderInventoryDB.buttonSize + CommanderInventoryDB.spacing) + CommanderInventoryDB.spacing
    ButtonsContainer:SetSize(width, height)
    ItemGrid:SetSize(width + 14, height + 32)
    
    -- Reposition buttons
    for i, button in ipairs(buttons) do
        if button:IsShown() then
            local row = math.floor((i-1) / columns)
            local col = (i-1) % columns
            button:SetPoint("TOPLEFT", ButtonsContainer, "TOPLEFT", 
                CommanderInventoryDB.spacing + col * (CommanderInventoryDB.buttonSize + CommanderInventoryDB.spacing), 
                -CommanderInventoryDB.spacing - row * (CommanderInventoryDB.buttonSize + CommanderInventoryDB.spacing))
        end
    end
    
    UpdateCooldowns()
end

-- Register events
ItemGrid:RegisterEvent("PLAYER_LOGIN")
ItemGrid:RegisterEvent("BAG_UPDATE")
ItemGrid:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
ItemGrid:RegisterEvent("ITEM_LOCK_CHANGED")
ItemGrid:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")

ItemGrid:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        UpdateButtons()
        self:SetShown(CommanderInventoryDB.showFrame)
    elseif event == "BAG_UPDATE" or event == "PLAYER_EQUIPMENT_CHANGED" or event == "ITEM_LOCK_CHANGED" then
        UpdateButtons()
    elseif event == "ACTIONBAR_UPDATE_COOLDOWN" then
        UpdateCooldowns()
    end
end)

-- Slash command to toggle frame
SLASH_CI1 = "/ci"
SlashCmdList["CI"] = function(msg)
    msg = msg:lower()
    if msg == "" or msg == "toggle" then
        CommanderInventoryDB.showFrame = not CommanderInventoryDB.showFrame
        ItemGrid:SetShown(CommanderInventoryDB.showFrame)
    elseif msg == "reset" then
        ItemGrid:ClearAllPoints()
        ItemGrid:SetPoint("CENTER")
    elseif msg == "config" then
        InterfaceOptionsFrame_OpenToCategory("Commander Inventory")
    else
        print("Usage: /ci [toggle|reset|config]")
    end
end

-- Function to apply settings
local function ApplySettings()
    ItemGrid:SetScale(CommanderInventoryDB.scale)
    ItemGrid:SetShown(CommanderInventoryDB.showFrame)
    
    for _, button in ipairs(buttons) do
        button:SetSize(CommanderInventoryDB.buttonSize, CommanderInventoryDB.buttonSize)
        
        if CommanderInventoryDB.showKeybinds then
            button.HotKey:Show()
        else
            button.HotKey:Hide()
        end
    end
    
    if CommanderInventoryDB.locked then
        ItemGrid:SetMovable(false)
        ItemGrid:EnableMouse(false)
    else
        ItemGrid:SetMovable(true)
        ItemGrid:EnableMouse(true)
    end
    
    UpdateButtons()
end

-- Call ApplySettings on PLAYER_LOGIN and whenever settings change
ItemGrid:RegisterEvent("PLAYER_LOGIN")
ItemGrid:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        ApplySettings()
    end
end)

-- Expose functions for external use
CI.ItemGrid = {
    UpdateButtons = UpdateButtons,
    ApplySettings = ApplySettings,
}

-- Function to update a setting
local function UpdateSetting(key, value)
    CommanderInventoryDB[key] = value
    ApplySettings()
end

-- Expose UpdateSetting function
CI.UpdateSetting = UpdateSetting

-- Register a callback for when settings change
if CI.Settings and CI.Settings.RegisterCallback then
    CI.Settings.RegisterCallback("SettingsChanged", ApplySettings)
end

-- Create a timer to periodically check for setting changes
local settingsCheckTimer = C_Timer.NewTicker(1, function()
    for key, value in pairs(CommanderInventoryDB) do
        if defaults[key] ~= nil and value ~= defaults[key] then
            ApplySettings()
            break
        end
    end
end)
