local CommanderTooltip = {
    name = "Commander_Tooltip",
    frame = nil,
    loaded = false
}

function CommanderTooltip:OnGameTooltipSetItem(tooltip)
    if not CommanderTooltipDB.ShowItemLevel then return end

    local _, link = tooltip:GetItem()
    if not link then return end

    local itemLevel = C_Item.GetDetailedItemLevelInfo(link)
    if itemLevel then
        tooltip:AddLine("Item Level: " .. itemLevel, 1, 1, 1)
    end

    -- Add vendor price directly in OnGameTooltipSetItem
    if CommanderTooltipDB.ShowVendorPrice then
        local itemID = C_Item.GetItemInfoInstant(link)
        if itemID then
            local price = select(11, C_Item.GetItemInfo(itemID))
            if price and price > 0 then
                SetTooltipMoney(tooltip, price, nil, "Vendor Price:")
            end
        end
    end
end

-- Runs as a secure post-hook on GameTooltip_SetDefaultAnchor, so it only ever
-- sees tooltips that Blizzard just default-anchored (SetOwner ANCHOR_NONE +
-- a single SetPoint to UIParent). Tooltips that are owner-anchored to a
-- specific frame (bag item buttons, Questie icons, action buttons, ...) never
-- pass through here, so we can never fight their anchor code.
function CommanderTooltip:OnSetDefaultAnchor(tooltip, parent)
    if tooltip ~= GameTooltip then return end

    if CommanderTooltipDB.AnchorToCursor then
        -- ANCHOR_CURSOR_RIGHT follows the cursor client-side and honors
        -- offsets; no manual repositioning is ever needed.
        tooltip:SetOwner(parent, "ANCHOR_CURSOR_RIGHT", CommanderTooltipDB.xOffset, CommanderTooltipDB.yOffset)
    else
        -- Re-point the freshly default-anchored tooltip to the user's chosen
        -- corner of the screen. Anchoring only to UIParent keeps the anchor
        -- family acyclic no matter what other addons do.
        tooltip:ClearAllPoints()
        tooltip:SetPoint(CommanderTooltipDB.Anchor, UIParent, CommanderTooltipDB.Anchor, CommanderTooltipDB.xOffset, CommanderTooltipDB.yOffset)
    end
end

function CommanderTooltip:ApplyScale()
    -- Scale lives outside the anchor system, so it is safe to apply to a
    -- live tooltip at any time.
    GameTooltip:SetScale(CommanderTooltipDB.Scale)
    ItemRefTooltip:SetScale(CommanderTooltipDB.Scale)
end

function CommanderTooltip:SetupTooltips()
    -- Apply scale
    self:ApplyScale()

    -- Hooks are registered exactly once at load; the handlers read the
    -- settings on each call, so settings changes need no re-hooking.
    GameTooltip:HookScript("OnTooltipSetItem", function(tooltip, ...)
        self:OnGameTooltipSetItem(tooltip, ...)
    end)
    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
        self:OnSetDefaultAnchor(tooltip, parent)
    end)
end

function CommanderTooltip:OnUpdate()
    -- Settings changes only take effect for the NEXT tooltip shown, via the
    -- GameTooltip_SetDefaultAnchor hook; a live tooltip is never re-anchored
    -- from here. Scale is the one setting that is safe to apply immediately.
    self:ApplyScale()
end

function CommanderTooltip:OnAwake()
    self:SetupTooltips()
    Commander.AddListener(COMMANDER_TOOLTIP_EVENTS.UPDATE, function() self:OnUpdate() end)
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
