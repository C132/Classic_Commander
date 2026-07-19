CommanderProductionDB = _G.CommanderProductionDB or {}

COMMANDER_PRODUCTION_EVENTS = {
    UPDATE = "COMMANDER_PRODUCTION_UPDATE"
}

local DefaultSettings = {
    EnableProduction = true,
    MinDuration = 10,
    MaxBars = 5,
    ReadyAlert = true,
}
for key, value in pairs(Commander.UI.HudChromeDefaults("Hud", "CLASSIC")) do
    DefaultSettings[key] = value
end

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderProductionDB, DefaultSettings)
    Commander.Notify(COMMANDER_PRODUCTION_EVENTS.UPDATE)
    print("Commander Production: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Production",
        title = "Production",
        addonName = "Commander_Production",
        description = "Your cooldowns as a production queue. Every ability on cooldown becomes a bar filling toward ready — like watching units build in an RTS — stacked at the left edge of the screen, longest waits at the bottom, with an optional callout the moment something finishes.",
        event = COMMANDER_PRODUCTION_EVENTS.UPDATE,
        slash = { "/cprod" },
        slashHandlers = {},
    })

    panel:AddSection("Production Queue")
    panel:AddCheckbox({
        label = "Enable Production",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderProductionDB.EnableProduction end,
        set = function(value) CommanderProductionDB.EnableProduction = value end,
    })
    panel:AddSlider({
        label = "Minimum Cooldown",
        tooltip = "Only track cooldowns at least this long — keeps short rotational abilities and the global cooldown out of the queue.",
        min = 3, max = 60, step = 1,
        format = "%.0fs",
        get = function() return CommanderProductionDB.MinDuration end,
        set = function(value) CommanderProductionDB.MinDuration = value end,
        isEnabled = function() return CommanderProductionDB.EnableProduction end,
    })
    panel:AddSlider({
        label = "Queue Length",
        tooltip = "Maximum number of bars shown at once (the soonest-ready cooldowns win).",
        min = 1, max = 8, step = 1,
        format = "%.0f bars",
        get = function() return CommanderProductionDB.MaxBars end,
        set = function(value) CommanderProductionDB.MaxBars = value end,
        isEnabled = function() return CommanderProductionDB.EnableProduction end,
    })
    panel:AddCheckbox({
        label = "Ready Alert",
        tooltip = "Print a chat callout and play a click when a tracked cooldown finishes.",
        get = function() return CommanderProductionDB.ReadyAlert end,
        set = function(value) CommanderProductionDB.ReadyAlert = value end,
        isEnabled = function() return CommanderProductionDB.EnableProduction end,
    })

    panel:AddSection("Frame")
    Commander.UI.AddHudChromeOptions(panel, CommanderProductionDB, "Hud", {
        isEnabled = function() return CommanderProductionDB.EnableProduction end,
        onChanged = function() Commander.Notify(COMMANDER_PRODUCTION_EVENTS.UPDATE) end,
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Production" then
        Commander.UI.ApplyDefaults(CommanderProductionDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
