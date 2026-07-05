local frame = CreateFrame("FRAME");
local ButtonsContainer
local buttons = {}
local showFrame = true
local scale = 1
local loaded = false
local locked = false
local tooltips = true
local columns = 10
local ItemGrid = CreateFrame("Frame", "CIItemGrid", UIParent, "BasicFrameTemplateWithInset")
_G.CIItemGrid = ItemGrid  -- Make ItemGrid accessible globally
_G.CIButtons = buttons  -- Make buttons accessible globally
ItemGrid:SetPoint("CENTER")
ItemGrid:SetMovable(true)
ItemGrid:SetClampedToScreen(true)
ItemGrid:EnableMouse(true)
ItemGrid:RegisterForDrag("LeftButton")
ItemGrid:SetScript("OnDragStart", function(self)
    if not locked then
        self:StartMoving()
    end
end)
ItemGrid:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
end)

-- Add after local frame declaration
local debugFrame

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("ITEM_LOCK_CHANGED")
frame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
frame:RegisterEvent("PLAYER_REGEN_ENABLED") -- Refresh buttons after combat (secure attributes are locked in combat)

local function CreateItemGrid()    
    ItemGrid.TitleText:SetText("Inventory")
    ItemGrid:SetShown(CommanderInventoryDB.showFrame)
    ItemGrid:SetScale(CommanderInventoryDB.scale)

    ButtonsContainer = CreateFrame("Frame", nil, ItemGrid)
    ButtonsContainer:SetPoint("TOPLEFT", ItemGrid, "TOPLEFT", 7, -25)
    ButtonsContainer:SetPoint("BOTTOMRIGHT", ItemGrid, "BOTTOMRIGHT", -7, 7)
end

local function CreateButton(index)
    local button = CreateFrame("Button", "CIItemButton"..index, ButtonsContainer, "SecureActionButtonTemplate, ActionButtonTemplate")
    button:SetSize(40, 40)
    button:SetAttribute("type", "item")
    -- 2.5.5 secure buttons act on key-down by default (ActionButtonUseKeyDown), so register both
    button:RegisterForClicks("AnyUp", "AnyDown")
    
    -- Create cooldown frame
    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints()
    button.cooldown:SetDrawEdge(true)
    button.cooldown:SetDrawSwipe(true)
    
    button:SetScript("OnEnter", function(self)
        if tooltips then
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

local function UpdateButtonCooldown(button)
    if button.itemID then
        local start, duration, enabled = C_Container.GetItemCooldown(button.itemID)
        if enabled and duration > 0 then
            button.cooldown:SetCooldown(start, duration)
        else
            button.cooldown:Clear()
        end
    end
end

local function UpdateButtons()
    -- Secure attributes and Show/Hide are blocked in combat; PLAYER_REGEN_ENABLED refreshes afterwards
    if InCombatLockdown() then
        return
    end

    local index = 1
    local itemIDs = {}
    local errors = {}
    local seenItems = {} -- Track items we've already added

    -- First pass: Get equipped items
    for i = 1, 19 do
        local success, itemID = pcall(GetInventoryItemID, "player", i)
        if not success then
            table.insert(errors, "Failed to get inventory item " .. i)
        elseif itemID and not seenItems[itemID] then -- Check if we haven't seen this item yet
            -- Check if item is usable before creating button
            local isUsable = C_Item.IsUsableItem(itemID)
            local hasSpell = C_Item.GetItemSpell(itemID)
            if (isUsable or hasSpell) then
                seenItems[itemID] = true -- Mark this item as seen
                if not buttons[index] then
                    buttons[index] = CreateButton(index)
                end
                
                local button = buttons[index]
                button.icon:SetTexture(GetInventoryItemTexture("player", i))
                button.itemLink = GetInventoryItemLink("player", i)
                button.itemID = itemID
                button:SetAttribute("item", "item:"..itemID)

                local count = C_Item.GetItemCount(itemID)
                button.Count:SetShown(count > 1)
                if count > 1 then
                    button.Count:SetText(count)
                end
                
                button:Show()
                index = index + 1
            end
        end
    end
    
    -- Second pass: Get bag items
    for bag = 0, NUM_BAG_FRAMES do
        local success, slots = pcall(C_Container.GetContainerNumSlots, bag)
        if not success then
            table.insert(errors, "Failed to get slots for bag " .. bag)
        else
            for slot = 1, slots do
                local success, itemID = pcall(C_Container.GetContainerItemID, bag, slot)
                if not success then
                    table.insert(errors, string.format("Failed to get item in bag %d slot %d", bag, slot))
                elseif itemID and not seenItems[itemID] then -- Check if we haven't seen this item yet
                    -- Check if item is usable before creating button
                    local isUsable = C_Item.IsUsableItem(itemID)
                    local hasSpell = C_Item.GetItemSpell(itemID)
                    if (isUsable or hasSpell) then
                        seenItems[itemID] = true -- Mark this item as seen
                        if not buttons[index] then
                            buttons[index] = CreateButton(index)
                        end
                        
                        local button = buttons[index]
                        button.icon:SetTexture(C_Item.GetItemIconByID(itemID))
                        button.itemLink = C_Container.GetContainerItemLink(bag, slot)
                        button.itemID = itemID
                        button:SetAttribute("item", "item:"..itemID)

                        local count = C_Item.GetItemCount(itemID)
                        button.Count:SetShown(count > 1)
                        if count > 1 then
                            button.Count:SetText(count)
                        end
                        
                        button:Show()
                        index = index + 1
                    end
                end
            end
        end
    end

    if #errors > 0 then
        print("Commander Inventory Errors:")
        for _, err in ipairs(errors) do
            print(" - " .. err)
        end
    end

    -- Update cooldowns for all visible buttons
    for i = 1, index - 1 do
        if buttons[i]:IsShown() then
            UpdateButtonCooldown(buttons[i])
        end
    end

    -- Hide remaining buttons
    for i = index, #buttons do
        buttons[i]:Hide()
    end
    
    -- Update grid layout
    local itemCount = index - 1
    local rows = math.ceil(itemCount / columns)
    
    local spacing = 2
    local buttonSize = 40
    local width = columns * (buttonSize + spacing) + spacing
    local height = rows * (buttonSize + spacing) + spacing
    
    ButtonsContainer:SetSize(width, height)
    ItemGrid:SetSize(width + 14, height + 32)
    
    -- Position all buttons
    for i, button in ipairs(buttons) do
        if button:IsShown() then
            local row = math.floor((i-1) / columns)
            local col = (i-1) % columns
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", ButtonsContainer, "TOPLEFT",
                spacing + col * (buttonSize + spacing),
                -spacing - row * (buttonSize + spacing))
        end
    end
end

local function LoadSettings()
    showFrame = CommanderInventoryDB.showFrame
    scale = CommanderInventoryDB.scale
    tooltips = CommanderInventoryDB.tooltips
    columns = CommanderInventoryDB.columns  
    locked = CommanderInventoryDB.locked

    if ItemGrid then
        ItemGrid:SetShown(CommanderInventoryDB.showFrame)
        ItemGrid:SetScale(CommanderInventoryDB.scale)
    end
    UpdateButtons()
end

frame:SetScript("OnEvent", function(self, event)
    if debugFrame then
        debugFrame.LogEvent(event)
    end
    
    if event == "PLAYER_LOGIN" then
        CreateItemGrid()
        UpdateButtons()
        LoadSettings()
        AddListener(COMMANDER_INVENTORY_EVENTS.COMMANDER_INVENTORY, LoadSettings)
        debugFrame = _G.CIDebugFrame -- Get reference to debug frame
        loaded = true
    elseif event == "ACTIONBAR_UPDATE_COOLDOWN" and loaded then
        -- Only update cooldowns without rebuilding the entire grid
        for _, button in ipairs(buttons) do
            if button:IsShown() then
                UpdateButtonCooldown(button)
            end
        end
    elseif loaded then
        UpdateButtons()
    end
end)