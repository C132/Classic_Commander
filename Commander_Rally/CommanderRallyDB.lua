CommanderRallyDB = _G.CommanderRallyDB or {}

COMMANDER_RALLY_EVENTS = {
    UPDATE = "COMMANDER_RALLY_UPDATE"
}

local DefaultSettings = {
    EnableRally = true,
    RallySound = true,
    Points = {},
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    -- Deliberately keep saved rally points: reset restores toggles, it does
    -- not throw away the user's marked locations
    local points = CommanderRallyDB.Points
    Commander.UI.ResetToDefaults(CommanderRallyDB, DefaultSettings)
    CommanderRallyDB.Points = points or {}
    Commander.Notify(COMMANDER_RALLY_EVENTS.UPDATE)
    print("Commander Rally: settings restored to defaults (rally points kept)")
end

local function PointTooltip(slot)
    return function()
        local p = CommanderRallyDB.Points and CommanderRallyDB.Points[slot]
        if p then
            return string.format("Currently: %s (%.0f, %.0f)", p.zone or "unknown", (p.x or 0) * 100, (p.y or 0) * 100)
        end
        return "No rally point marked in this slot yet."
    end
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Rally",
        title = "Rally",
        addonName = "Commander_Rally",
        description = "Rally points, straight out of an RTS base. Mark up to four spots — your farming corner, the meeting stone, the flight master — and order yourself back to any of them with a Commander Orders arrow. Points persist between sessions.",
        event = COMMANDER_RALLY_EVENTS.UPDATE,
        slash = { "/crally" },
        slashHandlers = {
            ["set 1"] = function() CommanderRally_Set(1) end,
            ["set 2"] = function() CommanderRally_Set(2) end,
            ["set 3"] = function() CommanderRally_Set(3) end,
            ["set 4"] = function() CommanderRally_Set(4) end,
            ["go 1"] = function() CommanderRally_Go(1) end,
            ["go 2"] = function() CommanderRally_Go(2) end,
            ["go 3"] = function() CommanderRally_Go(3) end,
            ["go 4"] = function() CommanderRally_Go(4) end,
            list = function() CommanderRally_List() end,
        },
    })

    panel:AddSection("Rally Points", "Mark your current position, then rally back to it any time (also: /crally set 1, /crally go 1).")
    panel:AddCheckbox({
        label = "Enable Rally Points",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderRallyDB.EnableRally end,
        set = function(value) CommanderRallyDB.EnableRally = value end,
    })
    panel:AddCheckbox({
        label = "Rally Sound",
        tooltip = "Play a confirmation click when a rally point is marked.",
        get = function() return CommanderRallyDB.RallySound end,
        set = function(value) CommanderRallyDB.RallySound = value end,
        isEnabled = function() return CommanderRallyDB.EnableRally end,
    })
    panel:AddButtonRow({
        { label = "Mark Rally 1", width = 105, tooltip = PointTooltip(1), onClick = function() CommanderRally_Set(1) end },
        { label = "Mark Rally 2", width = 105, tooltip = PointTooltip(2), onClick = function() CommanderRally_Set(2) end },
        { label = "Mark Rally 3", width = 105, tooltip = PointTooltip(3), onClick = function() CommanderRally_Set(3) end },
        { label = "Mark Rally 4", width = 105, tooltip = PointTooltip(4), onClick = function() CommanderRally_Set(4) end },
    })
    panel:AddButtonRow({
        { label = "Rally To 1", width = 105, tooltip = PointTooltip(1), onClick = function() CommanderRally_Go(1) end },
        { label = "Rally To 2", width = 105, tooltip = PointTooltip(2), onClick = function() CommanderRally_Go(2) end },
        { label = "Rally To 3", width = 105, tooltip = PointTooltip(3), onClick = function() CommanderRally_Go(3) end },
        { label = "Rally To 4", width = 105, tooltip = PointTooltip(4), onClick = function() CommanderRally_Go(4) end },
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Rally" then
        Commander.UI.ApplyDefaults(CommanderRallyDB, DefaultSettings)
        if type(CommanderRallyDB.Points) ~= "table" then
            CommanderRallyDB.Points = {}
        end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
