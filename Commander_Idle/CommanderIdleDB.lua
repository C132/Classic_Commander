CommanderIdleDB = _G.CommanderIdleDB or {}

COMMANDER_IDLE_EVENTS = {
    UPDATE = "COMMANDER_IDLE_UPDATE"
}

local DefaultSettings = {
    EnableIdle = true,
    IdleSeconds = 30,
    IdleSound = true,
    IdleWhileResting = false,
    RPEmote = false,
    -- The battleground AFK clock
    WatchBattleground = true,
    ClockWarnUnder = 60,
    ClockSound = true,
    ClockAnnounce = false,
}
for key, value in pairs(Commander.UI.HudChromeDefaults("Clock", "DARK")) do
    DefaultSettings[key] = value
end

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
        description = "The RTS idle-worker alert, for your character: stand around doing nothing — no moving, no fighting, no casting — and a pulsing pocket-watch button appears in the corner. Click it to open your orders (the quest log) and get back to work. In a battleground it becomes the AFK clock, which stays silent and shows one number when you are actually about to be thrown out.",
        event = COMMANDER_IDLE_EVENTS.UPDATE,
        slash = { "/cidle" },
        slashHandlers = {
            test = function()
                if CommanderIdle_Test then CommanderIdle_Test() end
            end,
            bg = function()
                if CommanderIdle_ClockTest then CommanderIdle_ClockTest() end
            end,
            status = function()
                if CommanderIdle_ClockReport then CommanderIdle_ClockReport() end
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
    panel:AddCheckbox({
        label = "Idle RP Emote",
        tooltip = "When the alert appears, perform a short class-appropriate emote in character — an Arcanist ponders, a Vanguard flexes, a Shadowblade glances about. This is a visible /emote seen by nearby players, so it is off by default.",
        get = function() return CommanderIdleDB.RPEmote end,
        set = function(value) CommanderIdleDB.RPEmote = value end,
        isEnabled = function() return CommanderIdleDB.EnableIdle end,
    })

    -- -----------------------------------------------------------------------
    -- The battleground half
    --
    -- Two different things throw you out of a battleground and only one of
    -- them has any in-game warning:
    --
    --   * No keyboard or mouse input for five minutes flags you Away, and
    --     going Away inside a battleground removes you INSTANTLY with a
    --     15-minute Deserter. No debuff first, no countdown, no message.
    --     Fighting does not reset it. Only input does.
    --   * Three teammates pressing Report AFK starts Idle -> Inactive ->
    --     kicked, which is slow and clears the moment you hit an enemy.
    --
    -- So the clock leads with the first one, and it stays hidden until you
    -- are inside the warning window. A player holding a base sees nothing
    -- all match.
    -- -----------------------------------------------------------------------
    local function ClockOn()
        return CommanderIdleDB.EnableIdle and CommanderIdleDB.WatchBattleground
    end

    panel:AddSection("Battleground AFK Clock",
        "One number, only when you are about to be thrown out. Silent otherwise.")
    panel:AddCheckbox({
        label = "Show the AFK Clock",
        tooltip = "In a battleground, count down the auto-AFK kick — and if teammates report you, the real remaining time on the Idle and Inactive debuffs instead.",
        get = function() return CommanderIdleDB.WatchBattleground end,
        set = function(value) CommanderIdleDB.WatchBattleground = value end,
        isEnabled = function() return CommanderIdleDB.EnableIdle end,
    })
    panel:AddSlider({
        label = "Warn Under",
        tooltip = "How much of the five-minute auto-AFK clock is left before the bar appears. Below this you see one countdown; above it, nothing at all. Raise it if you want more room, lower it for near-total silence.",
        min = 15, max = 180, step = 15,
        format = "%d sec",
        get = function() return CommanderIdleDB.ClockWarnUnder end,
        set = function(value) CommanderIdleDB.ClockWarnUnder = value end,
        isEnabled = ClockOn,
    })
    panel:AddCheckboxPair({
        label = "Clock Sound",
        tooltip = "Chime when the bar first appears, then again at 30 and 10 seconds.",
        get = function() return CommanderIdleDB.ClockSound end,
        set = function(value) CommanderIdleDB.ClockSound = value end,
        isEnabled = ClockOn,
    }, {
        label = "Say It In Chat",
        tooltip = "Also print a line to chat when the clock appears. Off by default — the bar is the point.",
        get = function() return CommanderIdleDB.ClockAnnounce end,
        set = function(value) CommanderIdleDB.ClockAnnounce = value end,
        isEnabled = ClockOn,
    })

    Commander.UI.AddHudChromeOptions(panel, CommanderIdleDB, "Clock", {
        isEnabled = ClockOn,
        onChanged = function() Commander.Notify(COMMANDER_IDLE_EVENTS.UPDATE) end,
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
        {
            label = "Test AFK Clock",
            width = 130,
            tooltip = "Walk the clock through each countdown — auto-AFK, idle, inactive — without a battleground, so you can see it and place it (also: /cidle bg).",
            onClick = function()
                if CommanderIdle_ClockTest then CommanderIdle_ClockTest() end
            end,
        },
        {
            label = "Where Am I?",
            width = 120,
            tooltip = "Print what is counting down on you right now, including the auto-AFK clock (also: /cidle status).",
            onClick = function()
                if CommanderIdle_ClockReport then CommanderIdle_ClockReport() end
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
