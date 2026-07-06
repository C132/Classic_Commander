CommanderMinimapDB = CommanderMinimapDB or {}

COMMANDER_MINIMAP_EVENTS = {
    COMMANDER_MINIMAP = "COMMANDER_MINIMAP",
}

local defaultSettings = {
    ShowMinimapButton = true,
    XPDisplayMode = "PERCENTAGE",
    MinimapScale = 1.37,
}

local XP_DISPLAY_MODES = {
    {text = "XP Percentage", value = "PERCENTAGE"},
    {text = "Kills to Level", value = "KILLS_TO_LEVEL"},
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

-- Defaults are applied in ADDON_LOADED: SavedVariables replace the global
-- after this file runs, so applying them at file scope would be overwritten
local function ApplyDefaults()
    Commander.UI.ApplyDefaults(CommanderMinimapDB, defaultSettings)
end

local function Reset()
    Commander.UI.ResetToDefaults(CommanderMinimapDB, defaultSettings)
    Commander.Notify(COMMANDER_MINIMAP_EVENTS.COMMANDER_MINIMAP)
    print("Commander Minimap: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Minimap",
        title = "Minimap",
        addonName = "Commander_Minimap",
        description = "Reshapes the minimap into a square, movable RTS-style map with a repositioned clock, mouse-wheel zoom, and an information button that tracks XP progress.",
        event = COMMANDER_MINIMAP_EVENTS.COMMANDER_MINIMAP,
        slash = { "/cmap" },
    })

    panel:AddSection("Minimap")
    panel:AddSlider({
        label = "Minimap Scale",
        tooltip = "Overall size of the minimap.",
        min = 0.8, max = 2.0, step = 0.01,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderMinimapDB.MinimapScale end,
        set = function(value) CommanderMinimapDB.MinimapScale = value end,
    })

    panel:AddSection("Information Button")
    panel:AddCheckbox({
        label = "Show Information Button",
        tooltip = "Show the button beside the minimap: left-click opens game windows, right-click shows character stats, middle-click lists professions.",
        get = function() return CommanderMinimapDB.ShowMinimapButton end,
        set = function(value) CommanderMinimapDB.ShowMinimapButton = value end,
    })
    panel:AddDropdown({
        label = "Button Text",
        tooltip = "What the information button displays: your XP progress as a percentage, or an estimate of how many kills you need to level based on your last kill.",
        options = XP_DISPLAY_MODES,
        width = 150,
        get = function() return CommanderMinimapDB.XPDisplayMode end,
        set = function(value) CommanderMinimapDB.XPDisplayMode = value end,
        isEnabled = function() return CommanderMinimapDB.ShowMinimapButton end,
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnAwake()
    -- Booleans are handled by ApplyDefaults (nil checks), so a saved "false" is not clobbered
    CommanderMinimapDB.lastXPGain = CommanderMinimapDB.lastXPGain or 0
    CommanderMinimapDB.killsToLevel = CommanderMinimapDB.killsToLevel or 0
    CommanderMinimapDB.lastXPSource = CommanderMinimapDB.lastXPSource or ""

    CreateOptionsPanel()
end

local function OnEvent(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "Commander_Minimap" then
            ApplyDefaults()
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        OnAwake()
    end
end

frame:SetScript("OnEvent", OnEvent)
