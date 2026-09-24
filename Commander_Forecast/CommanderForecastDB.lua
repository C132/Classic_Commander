CommanderForecastDB = _G.CommanderForecastDB or {}
CommanderForecastLog = _G.CommanderForecastLog or {}

COMMANDER_FORECAST_EVENTS = {
    UPDATE = "COMMANDER_FORECAST_UPDATE"
}

local DefaultSettings = {
    EnableForecast = true,

    -- What the number counts
    Metric = "TOTAL",           -- TOTAL | PER_SECOND | PER_MANA
    Number = "AVERAGE",         -- AVERAGE | HIT | CRIT
    Source = "AUTO",            -- AUTO | MEASURED | MODEL
    ApplyHitChance = true,
    MinSamples = 3,

    -- What it watches
    Learn = true,
    LearnWindow = 20,
    ShowOnItems = true,
    RequireTarget = false,

    -- How it draws
    Anchor = "BOTTOM",          -- TOP | BOTTOM | CENTER
    OffsetY = 2,
    FontSize = 12,
    CompactNumbers = true,
    ColorBySource = true,
    ShowTooltipBreakdown = true,
}

CommanderForecast = _G.CommanderForecast or {}
CommanderForecast.Defaults = DefaultSettings

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderForecastDB, DefaultSettings)
    Commander.Notify(COMMANDER_FORECAST_EVENTS.UPDATE)
    print("Commander Forecast: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Forecast",
        title = "Forecast",
        addonName = "Commander_Forecast",
        description = "Prints the estimated output of every spell on its own icon — what one cast would do to the target you are holding. It opens with a model built from the spell's tooltip and your gear's spell power, then replaces that with what the spell has actually landed for on targets like this one, which is the only number that knows your talents and your buffs. Damage, healing and absorbs; per cast, per second, or per point of mana.",
        event = COMMANDER_FORECAST_EVENTS.UPDATE,
        slash = { "/cforecast", "/cfc" },
        slashHandlers = {
            report = function()
                if CommanderForecast_Report then CommanderForecast_Report() end
            end,
            forget = function()
                if CommanderForecast_Forget then CommanderForecast_Forget() end
            end,
        },
    })

    panel:AddSection("Forecast")
    panel:AddCheckboxPair({
        label = "Enable Forecast",
        tooltip = "Master switch. Off clears every number from your bars and stops all recording.",
        get = function() return CommanderForecastDB.EnableForecast end,
        set = function(value) CommanderForecastDB.EnableForecast = value end,
    }, {
        label = "Only With A Target",
        tooltip = "Hide the numbers entirely when you have nothing targeted, instead of showing what the cast would do with no target modifiers applied.",
        get = function() return CommanderForecastDB.RequireTarget end,
        set = function(value) CommanderForecastDB.RequireTarget = value end,
        isEnabled = function() return CommanderForecastDB.EnableForecast end,
    })

    panel:AddDropdown({
        label = "Metric",
        tooltip = "Total is the whole cast, damage-over-time included. Per second divides by the cast time (an instant is charged the 1.5s global). Per mana divides by the mana it costs — the number that decides a downrank.",
        options = {
            { text = "Total per cast", value = "TOTAL" },
            { text = "Per second", value = "PER_SECOND" },
            { text = "Per mana", value = "PER_MANA" },
        },
        get = function() return CommanderForecastDB.Metric end,
        set = function(value) CommanderForecastDB.Metric = value end,
        isEnabled = function() return CommanderForecastDB.EnableForecast end,
    })
    panel:AddDropdown({
        label = "Number Shown",
        tooltip = "Average folds in your crit chance and (optionally) your chance to miss — the number to plan a rotation against. Normal hit and Critical hit are the two ends of the roll.",
        options = {
            { text = "Average expected", value = "AVERAGE" },
            { text = "Normal hit", value = "HIT" },
            { text = "Critical hit", value = "CRIT" },
        },
        get = function() return CommanderForecastDB.Number end,
        set = function(value) CommanderForecastDB.Number = value end,
        isEnabled = function() return CommanderForecastDB.EnableForecast end,
    })

    panel:AddSection("Where the number comes from",
        "Measured beats modeled on every spell you have actually cast: the log already knows your talents, your buffs and the target's armour, none of which any API will tell the model.")
    panel:AddDropdown({
        label = "Source",
        tooltip = "Best available: model a spell until the log has enough of it, then switch. Measured only: show nothing until the spell has been cast enough times. Modeled only: ignore the log entirely.",
        options = {
            { text = "Best available", value = "AUTO" },
            { text = "Measured only", value = "MEASURED" },
            { text = "Modeled only", value = "MODEL" },
        },
        get = function() return CommanderForecastDB.Source end,
        set = function(value) CommanderForecastDB.Source = value end,
        isEnabled = function() return CommanderForecastDB.EnableForecast end,
    })
    panel:AddCheckboxPair({
        label = "Learn From Combat Log",
        tooltip = "Record what your spells land for. Off freezes what has already been learned; it does not erase it.",
        get = function() return CommanderForecastDB.Learn end,
        set = function(value) CommanderForecastDB.Learn = value end,
        isEnabled = function() return CommanderForecastDB.EnableForecast end,
    }, {
        label = "Apply Hit Chance",
        tooltip = "Reduce the average by your chance to miss this target — measured from your own misses where there are enough of them, and from TBC's level tables otherwise. Off shows what a landed cast does.",
        get = function() return CommanderForecastDB.ApplyHitChance end,
        set = function(value) CommanderForecastDB.ApplyHitChance = value end,
        isEnabled = function() return CommanderForecastDB.EnableForecast end,
    })
    panel:AddSliderPair({
        label = "Learning Window",
        tooltip = "How many recent casts the measured average tracks. Smaller follows your current buffs and gear faster; larger is steadier.",
        min = 5, max = 100, step = 5,
        format = "%.0f casts",
        get = function() return CommanderForecastDB.LearnWindow end,
        set = function(value) CommanderForecastDB.LearnWindow = value end,
        isEnabled = function() return CommanderForecastDB.EnableForecast and CommanderForecastDB.Learn end,
    }, {
        label = "Samples Before Trusting",
        tooltip = "How many landed casts a spell needs before the measured number replaces the modeled one.",
        min = 1, max = 20, step = 1,
        format = "%.0f casts",
        get = function() return CommanderForecastDB.MinSamples end,
        set = function(value) CommanderForecastDB.MinSamples = value end,
        isEnabled = function() return CommanderForecastDB.EnableForecast end,
    })

    panel:AddSection("Appearance")
    panel:AddDropdown({
        label = "Position On Icon",
        tooltip = "Where the number sits. Bottom shares its corner with the macro name; top shares with the keybind.",
        options = {
            { text = "Bottom", value = "BOTTOM" },
            { text = "Top", value = "TOP" },
            { text = "Center", value = "CENTER" },
        },
        get = function() return CommanderForecastDB.Anchor end,
        set = function(value) CommanderForecastDB.Anchor = value end,
        isEnabled = function() return CommanderForecastDB.EnableForecast end,
    })
    panel:AddSliderPair({
        label = "Font Size",
        min = 8, max = 22, step = 1,
        format = "%.0f pt",
        get = function() return CommanderForecastDB.FontSize end,
        set = function(value) CommanderForecastDB.FontSize = value end,
        isEnabled = function() return CommanderForecastDB.EnableForecast end,
    }, {
        label = "Vertical Nudge",
        tooltip = "Move the number off whatever it is sitting on.",
        min = -14, max = 14, step = 1,
        format = "%.0f px",
        get = function() return CommanderForecastDB.OffsetY end,
        set = function(value) CommanderForecastDB.OffsetY = value end,
        isEnabled = function() return CommanderForecastDB.EnableForecast end,
    })
    panel:AddCheckboxPair({
        label = "Compact Numbers",
        tooltip = "Write 1240 as 1.2k, so a four-digit hit still fits on a 36-pixel icon.",
        get = function() return CommanderForecastDB.CompactNumbers end,
        set = function(value) CommanderForecastDB.CompactNumbers = value end,
        isEnabled = function() return CommanderForecastDB.EnableForecast end,
    }, {
        label = "Color By Source",
        tooltip = "White for a measured number, dimmed blue for a modeled one — so a number you have not earned yet says so without a tooltip.",
        get = function() return CommanderForecastDB.ColorBySource end,
        set = function(value) CommanderForecastDB.ColorBySource = value end,
        isEnabled = function() return CommanderForecastDB.EnableForecast end,
    })
    panel:AddCheckboxPair({
        label = "Tooltip Breakdown",
        tooltip = "Add the working to an action button's tooltip: base, what your spell power contributed through which coefficient, crit, hit, and how many casts the measurement rests on.",
        get = function() return CommanderForecastDB.ShowTooltipBreakdown end,
        set = function(value) CommanderForecastDB.ShowTooltipBreakdown = value end,
        isEnabled = function() return CommanderForecastDB.EnableForecast end,
    }, {
        label = "Number Items Too",
        tooltip = "Put a number on healthstones, potions and bandages as well — modeled from the item's own text.",
        get = function() return CommanderForecastDB.ShowOnItems end,
        set = function(value) CommanderForecastDB.ShowOnItems = value end,
        isEnabled = function() return CommanderForecastDB.EnableForecast end,
    })

    panel:AddButtonRow({
        {
            label = "Report",
            width = 110,
            tooltip = "Print every spell the log has learned, with its measured average and sample count (also: /cfc report).",
            onClick = function()
                if CommanderForecast_Report then CommanderForecast_Report() end
            end,
        },
        {
            label = "Forget All",
            width = 110,
            tooltip = "Erase everything measured on this character and fall back to the model (also: /cfc forget).",
            onClick = function()
                if CommanderForecast_Forget then CommanderForecast_Forget() end
            end,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Forecast" then
        Commander.UI.ApplyDefaults(CommanderForecastDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
