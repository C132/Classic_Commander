CommanderRadarDB = _G.CommanderRadarDB or {}

COMMANDER_RADAR_EVENTS = {
    UPDATE = "COMMANDER_RADAR_UPDATE"
}

local DefaultSettings = {
    EnableRadar = true,
    ShowSweep = true,
    ShowCrosshair = false,
    SweepSpeed = 0.5,
    SweepOpacity = 0.25,
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderRadarDB, DefaultSettings)
    Commander.Notify(COMMANDER_RADAR_EVENTS.UPDATE)
    print("Commander Radar: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Radar",
        title = "Radar",
        addonName = "Commander_Radar",
        description = "Pure RTS flavor for the minimap: a radar sweep line rotating over the map, with an optional targeting crosshair. Zero gameplay effect, maximum command-center atmosphere.",
        event = COMMANDER_RADAR_EVENTS.UPDATE,
        slash = { "/cradar" },
        slashHandlers = {},
    })

    panel:AddSection("Radar")
    panel:AddCheckbox({
        label = "Enable Radar",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderRadarDB.EnableRadar end,
        set = function(value) CommanderRadarDB.EnableRadar = value end,
    })
    panel:AddCheckbox({
        label = "Radar Sweep",
        tooltip = "A slowly rotating sweep line over the minimap.",
        get = function() return CommanderRadarDB.ShowSweep end,
        set = function(value) CommanderRadarDB.ShowSweep = value end,
        isEnabled = function() return CommanderRadarDB.EnableRadar end,
    })
    panel:AddCheckbox({
        label = "Crosshair",
        tooltip = "Faint centered crosshair lines over the minimap.",
        get = function() return CommanderRadarDB.ShowCrosshair end,
        set = function(value) CommanderRadarDB.ShowCrosshair = value end,
        isEnabled = function() return CommanderRadarDB.EnableRadar end,
    })
    panel:AddSlider({
        label = "Sweep Speed",
        tooltip = "Rotations per second of the sweep line.",
        min = 0.1, max = 1.5, step = 0.1,
        format = "%.1f rps",
        get = function() return CommanderRadarDB.SweepSpeed end,
        set = function(value) CommanderRadarDB.SweepSpeed = value end,
        isEnabled = function() return CommanderRadarDB.EnableRadar and CommanderRadarDB.ShowSweep end,
    })
    panel:AddSlider({
        label = "Sweep Opacity",
        tooltip = "How visible the sweep line is.",
        min = 0.05, max = 0.6, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderRadarDB.SweepOpacity end,
        set = function(value) CommanderRadarDB.SweepOpacity = value end,
        isEnabled = function() return CommanderRadarDB.EnableRadar and CommanderRadarDB.ShowSweep end,
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Radar" then
        Commander.UI.ApplyDefaults(CommanderRadarDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
