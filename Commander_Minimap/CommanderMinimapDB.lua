CommanderMinimapDB = CommanderMinimapDB or {}

COMMANDER_MINIMAP_EVENTS = {
    COMMANDER_MINIMAP = "COMMANDER_MINIMAP",
}

local defaultSettings = {
    ShowMinimapButton = true,
    XPDisplayMode = "PERCENTAGE",
    MinimapScale = 1.37,
    LockMinimap = false,
    TidyAddonButtons = true,
    TidyFadedOpacity = 0,
    BoardStyle = "NONE",
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
        description = "Reshapes the minimap into a square, movable RTS-style map: scroll to zoom, drag to reposition, clock tucked into the corner, and an information button that answers 'how far to the next level?'",
        event = COMMANDER_MINIMAP_EVENTS.COMMANDER_MINIMAP,
        slash = { "/cmap" },
    })

    panel:AddSection("Minimap", "Scale applies immediately; drag the map itself to reposition it while unlocked.")
    panel:AddSlider({
        label = "Minimap Scale",
        tooltip = "Overall size of the minimap.",
        min = 0.8, max = 2.0, step = 0.01,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderMinimapDB.MinimapScale end,
        set = function(value) CommanderMinimapDB.MinimapScale = value end,
    })
    panel:AddDropdown({
        label = "Board Style",
        tooltip = "Frame the square minimap in the suite's board styling — the same Classic Plate and Dark Panel the command card and HUD modules use. None leaves the map bare.",
        options = {
            { text = "None", value = "NONE" },
            { text = "Classic Plate", value = "CLASSIC" },
            { text = "Dark Panel", value = "DARK" },
        },
        width = 150,
        get = function() return CommanderMinimapDB.BoardStyle end,
        set = function(value) CommanderMinimapDB.BoardStyle = value end,
    })
    panel:AddCheckbox({
        label = "Lock Minimap",
        tooltip = "Prevent the minimap from being dragged to a new position.",
        get = function() return CommanderMinimapDB.LockMinimap end,
        set = function(value) CommanderMinimapDB.LockMinimap = value end,
    })
    panel:AddCheckbox({
        label = "Tidy Addon Buttons",
        tooltip = "Fade other addons' minimap buttons until you mouse over the minimap. Blizzard's own elements (tracking, mail, clock, zone text) and the Commander information button always stay visible.",
        get = function() return CommanderMinimapDB.TidyAddonButtons end,
        set = function(value) CommanderMinimapDB.TidyAddonButtons = value end,
    })
    panel:AddSlider({
        label = "Faded Button Opacity",
        tooltip = "How visible the tidied addon buttons stay when you are not hovering the minimap. 0% hides them completely.",
        min = 0, max = 0.5, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderMinimapDB.TidyFadedOpacity end,
        set = function(value) CommanderMinimapDB.TidyFadedOpacity = value end,
        isEnabled = function() return CommanderMinimapDB.TidyAddonButtons end,
    })

    panel:AddSection("Information Button", "Left-click opens game windows, right-click shows character stats, middle-click lists professions.")
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
