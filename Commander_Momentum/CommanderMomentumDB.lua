CommanderMomentumDB = _G.CommanderMomentumDB or {}

COMMANDER_MOMENTUM_EVENTS = {
    UPDATE = "COMMANDER_MOMENTUM_UPDATE"
}

local DefaultSettings = {
    EnableMomentum = true,
    Window = 20,
    MilestoneSound = true,
    MilestoneEmotes = false,
    BreakEmotes = false,
    BreakFloor = 2,
    BreakWarning = true,
    ResetOnDeath = true,
    ResetOnZone = true,
    KillSource = "OWN",
    AlwaysShow = false,
    Display = "HUD",
}
for key, value in pairs(Commander.UI.HudChromeDefaults("Hud", "DARK")) do
    DefaultSettings[key] = value
end

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderMomentumDB, DefaultSettings)
    Commander.Notify(COMMANDER_MOMENTUM_EVENTS.UPDATE)
    print("Commander Momentum: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Momentum",
        title = "Momentum",
        addonName = "Commander_Momentum",
        description = "A kill-streak combo meter. Each killing blow feeds the meter and resets its drain timer; keep chaining kills and the streak climbs through escalating colors — hesitate and the bar empties, taking the streak with it. Pure grinding dopamine.",
        event = COMMANDER_MOMENTUM_EVENTS.UPDATE,
        slash = { "/cmom" },
        slashHandlers = {
            report = function()
                if CommanderMomentum_Report then CommanderMomentum_Report() end
            end,
            test = function()
                if CommanderMomentum_Test then CommanderMomentum_Test() end
            end,
        },
    })

    panel:AddCheckboxPair({
        label = "Enable Momentum",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderMomentumDB.EnableMomentum end,
        set = function(value) CommanderMomentumDB.EnableMomentum = value end,
    }, {
        label = "Always Show",
        tooltip = "Keep the meter on screen at x0 between streaks instead of appearing only while one is alive.",
        get = function() return CommanderMomentumDB.AlwaysShow end,
        set = function(value) CommanderMomentumDB.AlwaysShow = value end,
        isEnabled = function() return CommanderMomentumDB.EnableMomentum end,
    })
    panel:AddDropdownPair({
        label = "Display Mode",
        tooltip = "Floating Meter is the standalone HUD frame. Portrait Overlay lives on the default player frame instead: a radial timer sweeps the momentum window over your portrait with the multiplier centered on it.",
        options = {
            { text = "Floating Meter", value = "HUD" },
            { text = "Portrait Overlay", value = "PORTRAIT" },
        },
        get = function() return CommanderMomentumDB.Display end,
        set = function(value) CommanderMomentumDB.Display = value end,
        isEnabled = function() return CommanderMomentumDB.EnableMomentum end,
    }, {
        label = "Kill Source",
        tooltip = "My Killing Blows counts only kills where you land the final hit. Squad Kills counts every hostile that dies around you — the meter works for healers and tanks too.",
        options = {
            { text = "My Killing Blows", value = "OWN" },
            { text = "Squad Kills", value = "SQUAD" },
        },
        get = function() return CommanderMomentumDB.KillSource end,
        set = function(value) CommanderMomentumDB.KillSource = value end,
        isEnabled = function() return CommanderMomentumDB.EnableMomentum end,
    })
    panel:AddSliderPair({
        label = "Momentum Window",
        tooltip = "Seconds you have to land the next killing blow before the streak drains away.",
        min = 8, max = 60, step = 1,
        format = "%.0fs",
        get = function() return CommanderMomentumDB.Window end,
        set = function(value) CommanderMomentumDB.Window = value end,
        isEnabled = function() return CommanderMomentumDB.EnableMomentum end,
    }, {
        label = "Lament Streaks From",
        tooltip = "Minimum chain size worth announcing when it breaks (with Streak Break Emote on).",
        min = 2, max = 10, step = 1,
        format = "x%.0f",
        get = function() return CommanderMomentumDB.BreakFloor end,
        set = function(value) CommanderMomentumDB.BreakFloor = value end,
        isEnabled = function()
            return CommanderMomentumDB.EnableMomentum and CommanderMomentumDB.BreakEmotes
        end,
    })
    panel:AddCheckboxPair({
        label = "Milestone Sound",
        tooltip = "Play a chime when the streak crosses a milestone (5, 10, 15, 20...).",
        get = function() return CommanderMomentumDB.MilestoneSound end,
        set = function(value) CommanderMomentumDB.MilestoneSound = value end,
        isEnabled = function() return CommanderMomentumDB.EnableMomentum end,
    }, {
        label = "Milestone Emotes",
        tooltip = "Announce milestones to everyone nearby as a custom emote with escalating flavor and your session numbers — kill chain, pace, total kills, best chain. Public bragging; off by default.",
        get = function() return CommanderMomentumDB.MilestoneEmotes end,
        set = function(value) CommanderMomentumDB.MilestoneEmotes = value end,
        isEnabled = function() return CommanderMomentumDB.EnableMomentum end,
    })
    panel:AddButtonRow({
        {
            label = "Test Streak",
            width = 110,
            tooltip = "Feed two harmless test kills so you can see and position the meter (also: /cmom test). No public emotes, session stats untouched.",
            onClick = function()
                if CommanderMomentum_Test then CommanderMomentum_Test() end
            end,
        },
        {
            label = "Session Report",
            width = 130,
            tooltip = "Print this session's kills, best chain, and any live streak (also: /cmom report).",
            onClick = function()
                if CommanderMomentum_Report then CommanderMomentum_Report() end
            end,
        },
    })
    panel:AddCheckboxPair({
        label = "Reset on Death",
        tooltip = "Dying breaks the live chain (lament rules apply) and zeroes the session numbers — kills and best chain start over.",
        get = function() return CommanderMomentumDB.ResetOnDeath end,
        set = function(value) CommanderMomentumDB.ResetOnDeath = value end,
        isEnabled = function() return CommanderMomentumDB.EnableMomentum end,
    }, {
        label = "Reset on Zone Change",
        tooltip = "Loading-screen transitions (entering or leaving an instance, continent travel) quietly end the chain and start fresh session numbers. A /reload in place never counts.",
        get = function() return CommanderMomentumDB.ResetOnZone end,
        set = function(value) CommanderMomentumDB.ResetOnZone = value end,
        isEnabled = function() return CommanderMomentumDB.EnableMomentum end,
    })
    panel:AddCheckboxPair({
        label = "Streak Break Emote",
        tooltip = "When the clock runs out on a live chain (floor set by Lament Streaks From), your character audibly cries — the real /cry voice line — and emotes the lament with your session numbers. Public; off by default.",
        get = function() return CommanderMomentumDB.BreakEmotes end,
        set = function(value) CommanderMomentumDB.BreakEmotes = value end,
        isEnabled = function() return CommanderMomentumDB.EnableMomentum end,
    }, {
        label = "Break Warning",
        tooltip = "Local heads-up (sound, chat line, meter flashes red) when a live streak has 5 seconds left. For the public group rally, enable Auto Charge Rally in Commander Comms.",
        get = function() return CommanderMomentumDB.BreakWarning end,
        set = function(value) CommanderMomentumDB.BreakWarning = value end,
        isEnabled = function() return CommanderMomentumDB.EnableMomentum end,
    })

    Commander.UI.AddHudChromeOptions(panel, CommanderMomentumDB, "Hud", {
        isEnabled = function()
            return CommanderMomentumDB.EnableMomentum and CommanderMomentumDB.Display ~= "PORTRAIT"
        end,
        onChanged = function() Commander.Notify(COMMANDER_MOMENTUM_EVENTS.UPDATE) end,
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Momentum" then
        Commander.UI.ApplyDefaults(CommanderMomentumDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
