CommanderOrdersDB = _G.CommanderOrdersDB or {}

COMMANDER_ORDERS_EVENTS = {
    UPDATE = "COMMANDER_ORDERS_UPDATE"
}

local DefaultSettings = {
    EnableOrders = true,
    OrderSound = true,
    -- Waypoint (mapID/x/y) persists here so an order survives /reload;
    -- RallyPoints[1..4] are the saved rally slots (kept out of defaults so
    -- resets never touch them)
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderOrdersDB, DefaultSettings)
    CommanderOrdersDB.Waypoint = nil
    Commander.Notify(COMMANDER_ORDERS_EVENTS.UPDATE)
    print("Commander Orders: settings restored to defaults (rally points kept)")
end

local function PointTooltip(slot)
    return function()
        local p = CommanderOrdersDB.RallyPoints and CommanderOrdersDB.RallyPoints[slot]
        if p then
            return string.format("Currently: %s (%.0f, %.0f)", p.zone or "unknown", (p.x or 0) * 100, (p.y or 0) * 100)
        end
        return "No rally point marked in this slot yet."
    end
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Orders",
        title = "Orders",
        addonName = "Commander_Orders",
        description = "Issue yourself move orders like an RTS: Ctrl+Right-click anywhere on the world map and an on-screen arrow guides you there with a live distance readout. The order completes automatically when you arrive, and survives reloads until you do. Rally points remember up to four spots — your farming corner, the meeting stone — and order you back to any of them.",
        event = COMMANDER_ORDERS_EVENTS.UPDATE,
        slash = { "/corder" },
        slashHandlers = {
            clear = function()
                if CommanderOrders_ClearOrder then
                    CommanderOrders_ClearOrder(true)
                end
            end,
            ["set 1"] = function() CommanderOrders_RallySet(1) end,
            ["set 2"] = function() CommanderOrders_RallySet(2) end,
            ["set 3"] = function() CommanderOrders_RallySet(3) end,
            ["set 4"] = function() CommanderOrders_RallySet(4) end,
            ["go 1"] = function() CommanderOrders_RallyGo(1) end,
            ["go 2"] = function() CommanderOrders_RallyGo(2) end,
            ["go 3"] = function() CommanderOrders_RallyGo(3) end,
            ["go 4"] = function() CommanderOrders_RallyGo(4) end,
            list = function() CommanderOrders_RallyList() end,
        },
    })

    panel:AddSection("Move Orders", "Ctrl+Right-click the world map to issue an order; click the arrow or /corder clear to cancel.")
    panel:AddCheckbox({
        label = "Enable Move Orders",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderOrdersDB.EnableOrders end,
        set = function(value) CommanderOrdersDB.EnableOrders = value end,
    })
    panel:AddCheckbox({
        label = "Order Sounds",
        tooltip = "Play a confirmation sound when an order is issued and a completion sound when you arrive.",
        get = function() return CommanderOrdersDB.OrderSound end,
        set = function(value) CommanderOrdersDB.OrderSound = value end,
        isEnabled = function() return CommanderOrdersDB.EnableOrders end,
    })
    panel:AddButtonRow({
        {
            label = "Clear Current Order",
            tooltip = "Cancel the active move order and hide the arrow.",
            onClick = function()
                if CommanderOrders_ClearOrder then
                    CommanderOrders_ClearOrder(true)
                end
            end,
        },
    })

    panel:AddSection("Rally Points", "Mark your current position, then rally back to it any time (also: /corder set 1, /corder go 1). Points persist between sessions and survive resets.")
    panel:AddButtonRow({
        { label = "Mark Rally 1", width = 105, tooltip = PointTooltip(1), onClick = function() CommanderOrders_RallySet(1) end },
        { label = "Mark Rally 2", width = 105, tooltip = PointTooltip(2), onClick = function() CommanderOrders_RallySet(2) end },
        { label = "Mark Rally 3", width = 105, tooltip = PointTooltip(3), onClick = function() CommanderOrders_RallySet(3) end },
        { label = "Mark Rally 4", width = 105, tooltip = PointTooltip(4), onClick = function() CommanderOrders_RallySet(4) end },
    })
    panel:AddButtonRow({
        { label = "Rally To 1", width = 105, tooltip = PointTooltip(1), onClick = function() CommanderOrders_RallyGo(1) end },
        { label = "Rally To 2", width = 105, tooltip = PointTooltip(2), onClick = function() CommanderOrders_RallyGo(2) end },
        { label = "Rally To 3", width = 105, tooltip = PointTooltip(3), onClick = function() CommanderOrders_RallyGo(3) end },
        { label = "Rally To 4", width = 105, tooltip = PointTooltip(4), onClick = function() CommanderOrders_RallyGo(4) end },
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Orders" then
        Commander.UI.ApplyDefaults(CommanderOrdersDB, DefaultSettings)
        if type(CommanderOrdersDB.RallyPoints) ~= "table" then
            CommanderOrdersDB.RallyPoints = {}
        end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
