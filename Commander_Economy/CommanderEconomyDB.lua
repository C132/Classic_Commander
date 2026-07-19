CommanderEconomyDB = _G.CommanderEconomyDB or {}

COMMANDER_ECONOMY_EVENTS = {
    UPDATE = "COMMANDER_ECONOMY_UPDATE"
}

local DefaultSettings = {
    EnableEconomy = true,
    HourlyReport = false,
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderEconomyDB, DefaultSettings)
    Commander.Notify(COMMANDER_ECONOMY_EVENTS.UPDATE)
    print("Commander Economy: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Economy",
        title = "Economy",
        addonName = "Commander_Economy",
        description = "The end-of-mission score screen, running all session. Economy quietly tracks gold earned and spent, experience gained and per-hour rate, quests turned in, and casualties — then reports on demand, like tabbing to the economy panel in an RTS.",
        event = COMMANDER_ECONOMY_EVENTS.UPDATE,
        slash = { "/ceco" },
        slashHandlers = {
            report = function()
                if CommanderEconomy_Report then CommanderEconomy_Report() end
            end,
        },
    })

    panel:AddSection("Mission Economics")
    panel:AddCheckbox({
        label = "Enable Economy",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderEconomyDB.EnableEconomy end,
        set = function(value) CommanderEconomyDB.EnableEconomy = value end,
    })
    panel:AddCheckbox({
        label = "Hourly Report",
        tooltip = "Print the mission summary in chat automatically once an hour.",
        get = function() return CommanderEconomyDB.HourlyReport end,
        set = function(value) CommanderEconomyDB.HourlyReport = value end,
        isEnabled = function() return CommanderEconomyDB.EnableEconomy end,
    })
    panel:AddButtonRow({
        {
            label = "Mission Summary",
            width = 140,
            tooltip = "Print this session's economics in chat (also: /ceco report).",
            onClick = function()
                if CommanderEconomy_Report then CommanderEconomy_Report() end
            end,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Economy" then
        Commander.UI.ApplyDefaults(CommanderEconomyDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
