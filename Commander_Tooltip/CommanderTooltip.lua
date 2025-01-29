local CommanderTooltip = {
    name = "Commander_Tooltip",
    frame = nil,
    loaded = false
}

function CommanderTooltip:OnGameTooltipSetItem(tooltip)
    if not CommanderTooltipDB.ShowItemLevel then return end
    
    local _, link = tooltip:GetItem()
    if not link then return end
    
    local itemLevel = GetDetailedItemLevelInfo(link)
    if itemLevel then
        tooltip:AddLine("Item Level: " .. itemLevel, 1, 1, 1)
    end
    
    -- Add vendor price directly in OnGameTooltipSetItem
    if CommanderTooltipDB.ShowVendorPrice then
        local itemID = GetItemInfoInstant(link)
        if itemID then
            local price = select(11, GetItemInfo(itemID))
            if price and price > 0 then
                SetTooltipMoney(tooltip, price, nil, "Vendor Price:")
            end
        end
    end
end

function CommanderTooltip:UpdateTooltipPosition(tooltip)
    if not CommanderTooltipDB.AnchorToCursor then return end
    
    local scale = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    x = x / scale + CommanderTooltipDB.xOffset
    y = y / scale + CommanderTooltipDB.yOffset
    
    local anchor = CommanderTooltipDB.Anchor
    tooltip:ClearAllPoints()
    
    if anchor == "TOPLEFT" then
        y = y - tooltip:GetHeight()
    elseif anchor == "TOPRIGHT" then
        x = x - tooltip:GetWidth()
        y = y - tooltip:GetHeight()
    elseif anchor == "BOTTOMRIGHT" then
        x = x - tooltip:GetWidth()
    elseif anchor == "TOP" then
        x = x - tooltip:GetWidth() / 2
        y = y - tooltip:GetHeight()
    elseif anchor == "BOTTOM" then
        x = x - tooltip:GetWidth() / 2
    elseif anchor == "LEFT" then
        y = y - tooltip:GetHeight() / 2
    elseif anchor == "RIGHT" then
        x = x - tooltip:GetWidth()
        y = y - tooltip:GetHeight() / 2
    elseif anchor == "CENTER" then
        x = x - tooltip:GetWidth() / 2
        y = y - tooltip:GetHeight() / 2
    end
    
    tooltip:SetPoint(anchor, UIParent, "BOTTOMLEFT", x, y)
end

function CommanderTooltip:SetupTooltips()
    -- Apply scale
    GameTooltip:SetScale(CommanderTooltipDB.Scale)
    ItemRefTooltip:SetScale(CommanderTooltipDB.Scale)
    
    -- Hook scripts
    GameTooltip:HookScript("OnTooltipSetItem", function(tooltip, ...) 
        self:OnGameTooltipSetItem(tooltip, ...) 
    end)
    GameTooltip:HookScript("OnUpdate", function(tooltip, ...) 
        self:UpdateTooltipPosition(tooltip, ...) 
    end)
end

function CommanderTooltip:OnUpdate()
    -- Handle ShowItemLevel changes
    if CommanderTooltipDB.ShowItemLevel then
        GameTooltip:HookScript("OnTooltipSetItem", function(tooltip, ...) 
            self:OnGameTooltipSetItem(tooltip, ...) 
        end)
    else
        GameTooltip:SetScript("OnTooltipSetItem", nil)
    end

    -- Handle AnchorToCursor changes
    if CommanderTooltipDB.AnchorToCursor then
        GameTooltip:HookScript("OnUpdate", function(tooltip, ...) 
            self:UpdateTooltipPosition(tooltip, ...) 
        end)
    else
        GameTooltip:SetScript("OnUpdate", nil)
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -CONTAINER_OFFSET_X - 13, CONTAINER_OFFSET_Y)
    end

    -- Apply scale changes
    GameTooltip:SetScale(CommanderTooltipDB.Scale)
    ItemRefTooltip:SetScale(CommanderTooltipDB.Scale)
end

function CommanderTooltip:OnAwake()
    self:SetupTooltips()
    AddListener(COMMANDER_TOOLTIP_EVENTS.UPDATE, function() self:OnUpdate() end)
    self.loaded = true
end

function CommanderTooltip:OnDestroy()
    -- Cleanup if needed
end

function CommanderTooltip:OnEvent(event, ...)
    if event == "PLAYER_LOGIN" then
        self:OnAwake()
    elseif event == "PLAYER_LOGOUT" then
        self:OnDestroy()
    elseif self.loaded then
        self:OnUpdate()
    end
end

-- Create and setup frame
CommanderTooltip.frame = CreateFrame("Frame")
CommanderTooltip.frame:RegisterEvent("PLAYER_LOGIN")
CommanderTooltip.frame:RegisterEvent("PLAYER_LOGOUT")
CommanderTooltip.frame:SetScript("OnEvent", function(_, event, ...) 
    CommanderTooltip:OnEvent(event, ...) 
end)

-- Expose functions for settings panel
function UpdateShowItemLevel(value)
    CommanderTooltipDB.ShowItemLevel = value
    Notify(COMMANDER_TOOLTIP_EVENTS.UPDATE)
end

function UpdateShowVendorPrice(value)
    CommanderTooltipDB.ShowVendorPrice = value
    Notify(COMMANDER_TOOLTIP_EVENTS.UPDATE)
end

function UpdateAnchorToCursor(value)
    CommanderTooltipDB.AnchorToCursor = value
    Notify(COMMANDER_TOOLTIP_EVENTS.UPDATE)
end

function UpdateXOffset(value)
    CommanderTooltipDB.xOffset = value
    Notify(COMMANDER_TOOLTIP_EVENTS.UPDATE)
end

function UpdateYOffset(value)
    CommanderTooltipDB.yOffset = value
    Notify(COMMANDER_TOOLTIP_EVENTS.UPDATE)
end

function UpdateScale(value)
    CommanderTooltipDB.Scale = value
    Notify(COMMANDER_TOOLTIP_EVENTS.UPDATE)
end
