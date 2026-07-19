CommanderProductionDB = _G.CommanderProductionDB or {}

COMMANDER_PRODUCTION_EVENTS = {
    UPDATE = "COMMANDER_PRODUCTION_UPDATE"
}

local DefaultSettings = {
    EnableProduction = true,
    MinDuration = 10,
    MaxBars = 5,
    ReadyAlert = true,
    AlwaysShow = false,
    FixedHeight = false,
    Layout = "BARS_DOWN",
    BarWidth = 110,
    CooldownOverlay = "BAR",
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

    panel:AddCheckboxPair({
        label = "Enable Production",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderProductionDB.EnableProduction end,
        set = function(value) CommanderProductionDB.EnableProduction = value end,
    }, {
        label = "Always Show",
        tooltip = "Keep the frame on screen even with an empty queue, instead of appearing only while something is on cooldown.",
        get = function() return CommanderProductionDB.AlwaysShow end,
        set = function(value) CommanderProductionDB.AlwaysShow = value end,
        isEnabled = function() return CommanderProductionDB.EnableProduction end,
    })
    panel:AddDropdownPair({
        label = "Layout",
        tooltip = "Bars list spells with names and grow down or up from the frame's anchor. Icon Strip is the SC2 replay production tab: icons marching left to right (hover an icon for the full spell tooltip).",
        options = {
            { text = "Bars — grow down", value = "BARS_DOWN" },
            { text = "Bars — grow up", value = "BARS_UP" },
            { text = "Icon Strip", value = "ICONS" },
        },
        get = function() return CommanderProductionDB.Layout end,
        set = function(value) CommanderProductionDB.Layout = value end,
        isEnabled = function() return CommanderProductionDB.EnableProduction end,
    }, {
        label = "Cooldown Overlay",
        tooltip = "How each icon shows its cooldown progress: the slim Progress Bar, a classic Radial Sweep over the icon, both at once, or a Timer Text countdown. Sweep and Timer also apply to the small icons in the Bars layouts.",
        options = {
            { text = "Progress Bar", value = "BAR" },
            { text = "Radial Sweep", value = "SWEEP" },
            { text = "Sweep + Bar", value = "BOTH" },
            { text = "Timer Text", value = "TEXT" },
        },
        get = function() return CommanderProductionDB.CooldownOverlay end,
        set = function(value) CommanderProductionDB.CooldownOverlay = value end,
        isEnabled = function() return CommanderProductionDB.EnableProduction end,
    })
    panel:AddSlider({
        label = "Bar Width",
        tooltip = "Width of the progress bars in the Bars layouts — widen until names and timers fit.",
        min = 100, max = 240, step = 5,
        format = "%.0f px",
        get = function() return CommanderProductionDB.BarWidth end,
        set = function(value) CommanderProductionDB.BarWidth = value end,
        isEnabled = function()
            return CommanderProductionDB.EnableProduction and CommanderProductionDB.Layout ~= "ICONS"
        end,
    })
    panel:AddSliderPair({
        label = "Minimum Cooldown",
        tooltip = "Only track cooldowns at least this long — keeps short rotational abilities and the global cooldown out of the queue.",
        min = 3, max = 60, step = 1,
        format = "%.0fs",
        get = function() return CommanderProductionDB.MinDuration end,
        set = function(value) CommanderProductionDB.MinDuration = value end,
        isEnabled = function() return CommanderProductionDB.EnableProduction end,
    }, {
        label = "Queue Length",
        tooltip = "Maximum number of entries shown at once (the soonest-ready cooldowns win).",
        min = 1, max = 8, step = 1,
        format = "%.0f",
        get = function() return CommanderProductionDB.MaxBars end,
        set = function(value) CommanderProductionDB.MaxBars = value end,
        isEnabled = function() return CommanderProductionDB.EnableProduction end,
    })
    panel:AddCheckboxPair({
        label = "Ready Alert",
        tooltip = "Print a chat callout and play a click when a tracked cooldown finishes.",
        get = function() return CommanderProductionDB.ReadyAlert end,
        set = function(value) CommanderProductionDB.ReadyAlert = value end,
        isEnabled = function() return CommanderProductionDB.EnableProduction end,
    }, {
        label = "Fixed Frame Size",
        tooltip = "Keep the frame (and its styled backdrop) sized for the full queue length instead of shrinking to what is currently shown — a stable panel that never jumps around. Applies to both layouts.",
        get = function() return CommanderProductionDB.FixedHeight end,
        set = function(value) CommanderProductionDB.FixedHeight = value end,
        isEnabled = function() return CommanderProductionDB.EnableProduction end,
    })

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
