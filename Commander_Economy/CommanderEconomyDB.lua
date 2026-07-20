CommanderEconomyDB = _G.CommanderEconomyDB or {}

COMMANDER_ECONOMY_EVENTS = {
    UPDATE = "COMMANDER_ECONOMY_UPDATE"
}

local DefaultSettings = {
    EnableEconomy = true,
    HourlyReport = false,
    AutoInstanceReport = true,
    BagGlow = true,
    AarStyle = "CLASSIC",
    AarScale = 1.0,
    AarPos = false,
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
            aar = function()
                if CommanderEconomy_ShowReport then CommanderEconomy_ShowReport("session") end
            end,
            share = function()
                if CommanderEconomy_ShareReport then CommanderEconomy_ShareReport() end
            end,
        },
    })

    panel:AddSection("Mission Economics")
    panel:AddCheckboxPair({
        label = "Enable Economy",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderEconomyDB.EnableEconomy end,
        set = function(value) CommanderEconomyDB.EnableEconomy = value end,
    }, {
        label = "Bag Glow",
        tooltip = "When an After Action Report opens, the items it lists glow gold in your bags until you mouse over them — spot the run's spoils at a glance.",
        get = function() return CommanderEconomyDB.BagGlow end,
        set = function(value) CommanderEconomyDB.BagGlow = value end,
        isEnabled = function() return CommanderEconomyDB.EnableEconomy end,
    })
    panel:AddCheckboxPair({
        label = "Hourly Report",
        tooltip = "Print the mission summary in chat automatically once an hour.",
        get = function() return CommanderEconomyDB.HourlyReport end,
        set = function(value) CommanderEconomyDB.HourlyReport = value end,
        isEnabled = function() return CommanderEconomyDB.EnableEconomy end,
    }, {
        label = "Instance Reports",
        tooltip = "Automatically open the After Action Report window when you leave a dungeon or raid, covering just that run: gold, experience, loot, quests, casualties, duration.",
        get = function() return CommanderEconomyDB.AutoInstanceReport end,
        set = function(value) CommanderEconomyDB.AutoInstanceReport = value end,
        isEnabled = function() return CommanderEconomyDB.EnableEconomy end,
    })
    panel:AddButtonRow({
        {
            label = "After Action Report",
            width = 150,
            tooltip = "Open the full-session After Action Report window (also: /ceco aar).",
            onClick = function()
                if CommanderEconomy_ShowReport then CommanderEconomy_ShowReport("session") end
            end,
        },
        {
            label = "Last Instance",
            width = 120,
            tooltip = "Open the report for the most recently completed dungeon or raid run.",
            onClick = function()
                if CommanderEconomy_ShowReport then CommanderEconomy_ShowReport("instance") end
            end,
        },
        {
            label = "Chat Summary",
            width = 120,
            tooltip = "Print this session's economics in chat (also: /ceco report).",
            onClick = function()
                if CommanderEconomy_Report then CommanderEconomy_Report() end
            end,
        },
        {
            label = "Reset Position",
            width = 120,
            tooltip = "Return the report window to the center of the screen.",
            onClick = function()
                CommanderEconomyDB.AarPos = false
                Commander.Notify(COMMANDER_ECONOMY_EVENTS.UPDATE)
            end,
        },
    })
    panel:AddDropdownPair({
        label = "Report Style",
        tooltip = "Framing for the After Action Report window, matching the suite's panel styles.",
        options = {
            { text = "Classic Panel", value = "CLASSIC" },
            { text = "Dark Panel", value = "DARK" },
        },
        get = function() return CommanderEconomyDB.AarStyle end,
        set = function(value) CommanderEconomyDB.AarStyle = value end,
        isEnabled = function() return CommanderEconomyDB.EnableEconomy end,
    }, nil)
    panel:AddSlider({
        label = "Report Scale",
        tooltip = "Overall size of the After Action Report window.",
        min = 0.7, max = 1.4, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderEconomyDB.AarScale end,
        set = function(value) CommanderEconomyDB.AarScale = value end,
        isEnabled = function() return CommanderEconomyDB.EnableEconomy end,
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
