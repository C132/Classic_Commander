CommanderMomentumDB = _G.CommanderMomentumDB or {}

COMMANDER_MOMENTUM_EVENTS = {
    UPDATE = "COMMANDER_MOMENTUM_UPDATE"
}

local DefaultSettings = {
    EnableMomentum = true,
    Window = 20,
    MilestoneSound = true,
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
        slashHandlers = {},
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
    panel:AddDropdown({
        label = "Display Mode",
        tooltip = "Floating Meter is the standalone HUD frame. Portrait Overlay lives on the default player frame instead: a radial timer sweeps the momentum window over your portrait with the multiplier centered on it.",
        options = {
            { text = "Floating Meter", value = "HUD" },
            { text = "Portrait Overlay", value = "PORTRAIT" },
        },
        width = 160,
        get = function() return CommanderMomentumDB.Display end,
        set = function(value) CommanderMomentumDB.Display = value end,
        isEnabled = function() return CommanderMomentumDB.EnableMomentum end,
    })
    panel:AddDropdown({
        label = "Kill Source",
        tooltip = "My Killing Blows counts only kills where you land the final hit. Squad Kills counts every hostile that dies around you — the meter works for healers and tanks too.",
        options = {
            { text = "My Killing Blows", value = "OWN" },
            { text = "Squad Kills", value = "SQUAD" },
        },
        width = 160,
        get = function() return CommanderMomentumDB.KillSource end,
        set = function(value) CommanderMomentumDB.KillSource = value end,
        isEnabled = function() return CommanderMomentumDB.EnableMomentum end,
    })
    panel:AddSlider({
        label = "Momentum Window",
        tooltip = "Seconds you have to land the next killing blow before the streak drains away.",
        min = 8, max = 60, step = 1,
        format = "%.0fs",
        get = function() return CommanderMomentumDB.Window end,
        set = function(value) CommanderMomentumDB.Window = value end,
        isEnabled = function() return CommanderMomentumDB.EnableMomentum end,
    })
    panel:AddCheckbox({
        label = "Milestone Sound",
        tooltip = "Play a chime when the streak crosses a milestone (5, 10, 15, 20...).",
        get = function() return CommanderMomentumDB.MilestoneSound end,
        set = function(value) CommanderMomentumDB.MilestoneSound = value end,
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
