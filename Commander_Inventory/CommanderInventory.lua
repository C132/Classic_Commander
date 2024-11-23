CommanderInventoryDB:Initialize()

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

ItemGrid.TitleText:SetText("Inventory")

local ButtonsContainer = CreateFrame("Frame", nil, ItemGrid)
ButtonsContainer:SetPoint("TOPLEFT", ItemGrid, "TOPLEFT", 7, -25)
ButtonsContainer:SetPoint("BOTTOMRIGHT", ItemGrid, "BOTTOMRIGHT", -7, 7)

local buttons = {}
local function CreateButton(index)
    local button = CreateFrame("Button", "CIItemButton"..index, ButtonsContainer, "SecureActionButtonTemplate, ActionButtonTemplate")
    button:SetSize(40, 40)
    button:SetAttribute("type", "item")
    button:SetScript("OnEnter", function(self)
        if CommanderInventoryDB.tooltips then
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

local function UpdateButtons()
    local index = 1
    local itemIDs = {}
    
    for _, location in ipairs({
        {type = "inventory", start = 1, stop = 19},
        {type = "bags", start = 0, stop = NUM_BAG_FRAMES}
    }) do
        if location.type == "inventory" then
            for i = location.start, location.stop do
                local itemID = GetInventoryItemID("player", i)
                if itemID and IsUsableItem(itemID) and not itemIDs[itemID] then
                    itemIDs[itemID] = true
                    if not buttons[index] then
                        buttons[index] = CreateButton(index)
                    end
                    
                    local button = buttons[index]
                    button.icon:SetTexture(GetInventoryItemTexture("player", i))
                    button.itemLink = GetInventoryItemLink("player", i)
                    button.itemID = itemID
                    button:SetAttribute("item", "item:"..itemID)
                    
                    local count = GetItemCount(itemID)
                    button.Count:SetShown(count > 1)
                    if count > 1 then
                        button.Count:SetText(count)
                    end
                    
                    button:Show()
                    index = index + 1
                end
            end
        else
            for bag = location.start, location.stop do
                for slot = 1, C_Container.GetContainerNumSlots(bag) do
                    local itemID = C_Container.GetContainerItemID(bag, slot)
                    if itemID and IsUsableItem(itemID) and not itemIDs[itemID] then
                        itemIDs[itemID] = true
                        if not buttons[index] then
                            buttons[index] = CreateButton(index)
                        end
                        
                        local button = buttons[index]
                        button.icon:SetTexture(GetItemIcon(itemID))
                        button.itemLink = C_Container.GetContainerItemLink(bag, slot)
                        button.itemID = itemID
                        button:SetAttribute("item", "item:"..itemID)
                        
                        local count = GetItemCount(itemID)
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

    for i = index, #buttons do
        buttons[i]:Hide()
    end
    
    local itemCount = index - 1
    local columns = CommanderInventoryDB.columns
    local rows = math.ceil(itemCount / columns)
    
    local spacing = 2
    local buttonSize = 40
    local width = columns * (buttonSize + spacing) + spacing
    local height = rows * (buttonSize + spacing) + spacing
    
    ButtonsContainer:SetSize(width, height)
    ItemGrid:SetSize(width + 14, height + 32)
    
    for i, button in ipairs(buttons) do
        if button:IsShown() then
            local row = math.floor((i-1) / columns)
            local col = (i-1) % columns
            button:SetPoint("TOPLEFT", ButtonsContainer, "TOPLEFT",
                spacing + col * (buttonSize + spacing),
                -spacing - row * (buttonSize + spacing))
        end
    end
end

ItemGrid:RegisterEvent("PLAYER_LOGIN")
ItemGrid:RegisterEvent("BAG_UPDATE")
ItemGrid:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
ItemGrid:RegisterEvent("ITEM_LOCK_CHANGED")

ItemGrid:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:SetShown(CommanderInventoryDB.showFrame)
    end
    UpdateButtons()
end)

SLASH_CI1 = "/ci"
SlashCmdList["CI"] = function(msg)
    msg = msg:lower()
    if msg == "" or msg == "toggle" then
        Settings.OpenToCategory("Commander Inventory")
    elseif msg == "reset" then
        CommanderInventoryDB:Reset()
        ItemGrid:ClearAllPoints()
        ItemGrid:SetPoint("CENTER")
        UpdateButtons()
    else
        print("Usage: /ci [toggle|reset]")
    end
end