CommanderVitalsDB = _G.CommanderVitalsDB or {}

COMMANDER_VITALS_EVENTS = {
    UPDATE = "COMMANDER_VITALS_UPDATE"
}

local DefaultSettings = {
    EnableVitals = true,
    AlwaysShow = false,
    WarnThreshold = 0.5,
    VitalsScale = 1.0,
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderVitalsDB, DefaultSettings)
    Commander.Notify(COMMANDER_VITALS_EVENTS.UPDATE)
    print("Commander Vitals: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Vitals",
        title = "Vitals",
        addonName = "Commander_Vitals",
        description = "An RTS unit wireframe for your equipment. Each armor and weapon slot gets a small condition bar — green fading to red as durability drops. Stays out of the way until something needs attention, then sits at the right edge of the screen until you repair.",
        event = COMMANDER_VITALS_EVENTS.UPDATE,
        slash = { "/cvitals" },
        slashHandlers = {},
    })

    panel:AddSection("Unit Condition")
    panel:AddCheckbox({
        label = "Enable Vitals",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderVitalsDB.EnableVitals end,
        set = function(value) CommanderVitalsDB.EnableVitals = value end,
    })
    panel:AddCheckbox({
        label = "Always Show",
        tooltip = "Keep the wireframe visible at all times instead of only when gear condition drops below the warning threshold.",
        get = function() return CommanderVitalsDB.AlwaysShow end,
        set = function(value) CommanderVitalsDB.AlwaysShow = value end,
        isEnabled = function() return CommanderVitalsDB.EnableVitals end,
    })
    panel:AddSlider({
        label = "Warning Threshold",
        tooltip = "The wireframe appears when any equipped item's durability drops to or below this percentage.",
        min = 0.05, max = 1.0, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderVitalsDB.WarnThreshold end,
        set = function(value) CommanderVitalsDB.WarnThreshold = value end,
        isEnabled = function() return CommanderVitalsDB.EnableVitals and not CommanderVitalsDB.AlwaysShow end,
    })
    panel:AddSlider({
        label = "Scale",
        tooltip = "Overall size of the wireframe.",
        min = 0.7, max = 1.5, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderVitalsDB.VitalsScale end,
        set = function(value) CommanderVitalsDB.VitalsScale = value end,
        isEnabled = function() return CommanderVitalsDB.EnableVitals end,
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Vitals" then
        Commander.UI.ApplyDefaults(CommanderVitalsDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
