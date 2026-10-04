CommanderPingDB = _G.CommanderPingDB or {}

COMMANDER_PING_EVENTS = {
    UPDATE = "COMMANDER_PING_UPDATE"
}

local DefaultSettings = {
    EnablePing = true,
    PingSound = true,
    PingCallout = true,
    IncludeOwnPings = false,
    PingWaypoint = false,
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderPingDB, DefaultSettings)
    Commander.Notify(COMMANDER_PING_EVENTS.UPDATE)
    print("Commander Ping: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Ping",
        title = "Ping",
        addonName = "Commander_Ping",
        description = "Never miss a ping again, RTS-style: when a group member clicks the minimap, you get a sound, a bright expanding flash on the ping spot, and a chat callout naming who pinged. WoW's tiny native blip finally gets the SC2 treatment.",
        event = COMMANDER_PING_EVENTS.UPDATE,
        slash = { "/cping" },
        slashHandlers = {
            test = function()
                if CommanderPing_Test then
                    CommanderPing_Test()
                end
            end,
        },
    })

    panel:AddSection("Ping Alerts", "Use /cping test to preview the flash and sound.")
    panel:AddCheckbox({
        label = "Enable Ping Alerts",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderPingDB.EnablePing end,
        set = function(value) CommanderPingDB.EnablePing = value end,
    })
    panel:AddCheckbox({
        label = "Play Ping Sound",
        tooltip = "Play an alert sound when a ping lands.",
        get = function() return CommanderPingDB.PingSound end,
        set = function(value) CommanderPingDB.PingSound = value end,
        isEnabled = function() return CommanderPingDB.EnablePing end,
    })
    panel:AddCheckbox({
        label = "Chat Callout",
        tooltip = "Print who pinged in your chat frame. With Commander Orders loaded the line carries a [Waypoint] link: click it and the arrow points at the pinged spot.",
        get = function() return CommanderPingDB.PingCallout end,
        set = function(value) CommanderPingDB.PingCallout = value end,
        isEnabled = function() return CommanderPingDB.EnablePing end,
    })
    panel:AddCheckbox({
        label = "Include My Own Pings",
        tooltip = "Also flash and sound for your own minimap pings, not just other group members'.",
        get = function() return CommanderPingDB.IncludeOwnPings end,
        set = function(value) CommanderPingDB.IncludeOwnPings = value end,
        isEnabled = function() return CommanderPingDB.EnablePing end,
    })
    panel:AddCheckbox({
        label = "Waypoint on Group Pings",
        tooltip = function()
            local text = "Every ping becomes a Commander Orders waypoint at the pinged spot, without clicking the callout's link. It is one waypoint that each new ping moves, it is gone after a reload, and it clears when you get there. It never takes the arrow from a waypoint or route you are following, or after you cleared the arrow: the arrow points at it only when Commander Orders' Follow the Closest has nothing of yours left where you are."
            if not (CommanderOrders and CommanderOrders.Add) then
                text = text .. "\n\nNeeds Commander Orders, which is not loaded."
            end
            return text
        end,
        get = function() return CommanderPingDB.PingWaypoint end,
        set = function(value) CommanderPingDB.PingWaypoint = value end,
        isEnabled = function()
            return CommanderPingDB.EnablePing and CommanderOrders ~= nil and CommanderOrders.Add ~= nil
        end,
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Ping" then
        Commander.UI.ApplyDefaults(CommanderPingDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
