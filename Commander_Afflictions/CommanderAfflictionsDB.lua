CommanderAfflictionsDB = _G.CommanderAfflictionsDB or {}

COMMANDER_AFFLICTIONS_EVENTS = {
    UPDATE = "COMMANDER_AFFLICTIONS_UPDATE"
}

local DefaultSettings = {
    EnableAfflictions = true,
    MaxBars = 6,
    ShowTargetNames = true,
    AlwaysShow = false,
    FixedHeight = false,
    Layout = "BARS_DOWN",
    BarWidth = 130,
    DrainOverlay = "BAR",
}
for key, value in pairs(Commander.UI.HudChromeDefaults("Hud", "CLASSIC")) do
    DefaultSettings[key] = value
end

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderAfflictionsDB, DefaultSettings)
    Commander.Notify(COMMANDER_AFFLICTIONS_EVENTS.UPDATE)
    print("Commander Afflictions: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Afflictions",
        title = "Afflictions",
        addonName = "Commander_Afflictions",
        description = "Your afflictions as a live operations board. Every debuff you land — DoTs, curses, diseases, stuns — becomes a draining bar, and the board stays truthful: dispels, immunities, and target deaths remove bars the moment they happen, not when a timer guesses.",
        event = COMMANDER_AFFLICTIONS_EVENTS.UPDATE,
        slash = { "/caff" },
        slashHandlers = {
            test = function()
                if CommanderAfflictions_Test then CommanderAfflictions_Test() end
            end,
        },
    })

    panel:AddCheckboxPair({
        label = "Enable Afflictions",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderAfflictionsDB.EnableAfflictions end,
        set = function(value) CommanderAfflictionsDB.EnableAfflictions = value end,
    }, {
        label = "Show Target Names",
        tooltip = "Append the afflicted unit's name to each bar (useful when dotting multiple targets).",
        get = function() return CommanderAfflictionsDB.ShowTargetNames end,
        set = function(value) CommanderAfflictionsDB.ShowTargetNames = value end,
        isEnabled = function() return CommanderAfflictionsDB.EnableAfflictions end,
    })
    panel:AddCheckboxPair({
        label = "Always Show",
        tooltip = "Keep the board frame on screen even with nothing afflicted.",
        get = function() return CommanderAfflictionsDB.AlwaysShow end,
        set = function(value) CommanderAfflictionsDB.AlwaysShow = value end,
        isEnabled = function() return CommanderAfflictionsDB.EnableAfflictions end,
    }, {
        label = "Fixed Frame Size",
        tooltip = "Keep the frame (and its styled backdrop) sized for the full board length instead of shrinking to what is currently shown. Applies to both layouts.",
        get = function() return CommanderAfflictionsDB.FixedHeight end,
        set = function(value) CommanderAfflictionsDB.FixedHeight = value end,
        isEnabled = function() return CommanderAfflictionsDB.EnableAfflictions end,
    })
    panel:AddDropdownPair({
        label = "Layout",
        tooltip = "Bars list afflictions with names and grow down or up from the frame's anchor. Icon Strip is the SC2 replay production tab: icons marching left to right (hover for the full debuff tooltip).",
        options = {
            { text = "Bars — grow down", value = "BARS_DOWN" },
            { text = "Bars — grow up", value = "BARS_UP" },
            { text = "Icon Strip", value = "ICONS" },
        },
        get = function() return CommanderAfflictionsDB.Layout end,
        set = function(value) CommanderAfflictionsDB.Layout = value end,
        isEnabled = function() return CommanderAfflictionsDB.EnableAfflictions end,
    }, {
        label = "Drain Overlay",
        tooltip = "How each icon shows the remaining time: the slim Drain Bar, a Radial Sweep over the icon, both at once, or Timer Text. Sweep and Timer also apply to the small icons in the Bars layouts; unknown-duration afflictions keep their full bar.",
        options = {
            { text = "Drain Bar", value = "BAR" },
            { text = "Radial Sweep", value = "SWEEP" },
            { text = "Sweep + Bar", value = "BOTH" },
            { text = "Timer Text", value = "TEXT" },
        },
        get = function() return CommanderAfflictionsDB.DrainOverlay end,
        set = function(value) CommanderAfflictionsDB.DrainOverlay = value end,
        isEnabled = function() return CommanderAfflictionsDB.EnableAfflictions end,
    })
    panel:AddSliderPair({
        label = "Bar Width",
        tooltip = "Width of the drain bars in the Bars layouts — widen until spell and target names fit.",
        min = 100, max = 260, step = 5,
        format = "%.0f",
        get = function() return CommanderAfflictionsDB.BarWidth end,
        set = function(value) CommanderAfflictionsDB.BarWidth = value end,
        isEnabled = function()
            return CommanderAfflictionsDB.EnableAfflictions and CommanderAfflictionsDB.Layout ~= "ICONS"
        end,
    }, {
        label = "Board Length",
        tooltip = "Maximum number of afflictions shown at once (soonest to expire first).",
        min = 1, max = 20, step = 1,
        format = "%.0f",
        get = function() return CommanderAfflictionsDB.MaxBars end,
        set = function(value) CommanderAfflictionsDB.MaxBars = value end,
        isEnabled = function() return CommanderAfflictionsDB.EnableAfflictions end,
    })
    panel:AddButtonRow({
        {
            label = "Test Board",
            width = 110,
            tooltip = "Inject sample afflictions so you can see and position the board without combat (also: /caff test).",
            onClick = function()
                if CommanderAfflictions_Test then CommanderAfflictions_Test() end
            end,
        },
    })

    Commander.UI.AddHudChromeOptions(panel, CommanderAfflictionsDB, "Hud", {
        isEnabled = function() return CommanderAfflictionsDB.EnableAfflictions end,
        onChanged = function() Commander.Notify(COMMANDER_AFFLICTIONS_EVENTS.UPDATE) end,
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Afflictions" then
        Commander.UI.ApplyDefaults(CommanderAfflictionsDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
