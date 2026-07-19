CommanderIdleDB = _G.CommanderIdleDB or {}

COMMANDER_IDLE_EVENTS = {
    UPDATE = "COMMANDER_IDLE_UPDATE"
}

local DefaultSettings = {
    EnableIdle = true,
    IdleSeconds = 30,
    IdleSound = true,
    IdleWhileResting = false,
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderIdleDB, DefaultSettings)
    Commander.Notify(COMMANDER_IDLE_EVENTS.UPDATE)
    print("Commander Idle: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Idle",
        title = "Idle Alert",
        addonName = "Commander_Idle",
        description = "The RTS idle-worker alert, for your character: stand around doing nothing — no moving, no fighting, no casting — and a pulsing pocket-watch button appears in the corner. Click it to open your orders (the quest log) and get back to work.",
        event = COMMANDER_IDLE_EVENTS.UPDATE,
        slash = { "/cidle" },
        slashHandlers = {
            test = function()
                if CommanderIdle_Test then CommanderIdle_Test() end
            end,
        },
    })

    panel:AddSection("Idle Alert")
    panel:AddCheckbox({
        label = "Enable Idle Alert",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderIdleDB.EnableIdle end,
        set = function(value) CommanderIdleDB.EnableIdle = value end,
    })
    panel:AddSlider({
        label = "Idle Threshold",
        tooltip = "How long you must be completely inactive before the alert appears.",
        min = 10, max = 120, step = 5,
        format = "%d sec",
        get = function() return CommanderIdleDB.IdleSeconds end,
        set = function(value) CommanderIdleDB.IdleSeconds = value end,
        isEnabled = function() return CommanderIdleDB.EnableIdle end,
    })
    panel:AddCheckbox({
        label = "Play Sound",
        tooltip = "Play a soft chime when the idle alert first appears.",
        get = function() return CommanderIdleDB.IdleSound end,
        set = function(value) CommanderIdleDB.IdleSound = value end,
        isEnabled = function() return CommanderIdleDB.EnableIdle end,
    })
    panel:AddCheckbox({
        label = "Alert While Resting",
        tooltip = "Also alert inside inns and cities. Off by default — parking in an inn is usually intentional.",
        get = function() return CommanderIdleDB.IdleWhileResting end,
        set = function(value) CommanderIdleDB.IdleWhileResting = value end,
        isEnabled = function() return CommanderIdleDB.EnableIdle end,
    })

    panel:AddButtonRow({
        {
            label = "Test Alert",
            width = 110,
            tooltip = "Show the idle alert right now — click the pocket watch or start moving to dismiss it (also: /cidle test).",
            onClick = function()
                if CommanderIdle_Test then CommanderIdle_Test() end
            end,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Idle" then
        Commander.UI.ApplyDefaults(CommanderIdleDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
