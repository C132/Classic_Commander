CommanderOrdersDB = _G.CommanderOrdersDB or {}

COMMANDER_ORDERS_EVENTS = {
    UPDATE = "COMMANDER_ORDERS_UPDATE"
}

local DefaultSettings = {
    EnableOrders = true,
    OrderSound = true,
    -- Waypoint (mapID/x/y) persists here so an order survives /reload
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderOrdersDB, DefaultSettings)
    CommanderOrdersDB.Waypoint = nil
    Commander.Notify(COMMANDER_ORDERS_EVENTS.UPDATE)
    print("Commander Orders: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Orders",
        title = "Orders",
        addonName = "Commander_Orders",
        description = "Issue yourself move orders like an RTS: Ctrl+Right-click anywhere on the world map and an on-screen arrow guides you there with a live distance readout. The order completes automatically when you arrive, and survives reloads until you do.",
        event = COMMANDER_ORDERS_EVENTS.UPDATE,
        slash = { "/corder" },
        slashHandlers = {
            clear = function()
                if CommanderOrders_ClearOrder then
                    CommanderOrders_ClearOrder(true)
                end
            end,
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

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Orders" then
        Commander.UI.ApplyDefaults(CommanderOrdersDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
