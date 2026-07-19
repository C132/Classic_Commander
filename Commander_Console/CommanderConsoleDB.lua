CommanderConsoleDB = _G.CommanderConsoleDB or {}

COMMANDER_CONSOLE_EVENTS = {
    UPDATE = "COMMANDER_CONSOLE_UPDATE"
}

-- Shared with CommanderConsole.lua (this file loads first). The console
-- strip's height is fixed by the artwork (a fullscreen overlay whose art
-- band ends 150 UI units up), so height is deliberately not a setting —
-- but the art itself, its tint, and its opacity are.
CommanderConsole_Styles = {
    { text = "Full Console", value = "FULL", file = "Console3.png" },
    { text = "Low Profile", value = "LOW_PROFILE", file = "Console3_LowProfile.png" },
}

CommanderConsole_Colors = {
    { text = "Steel (Default)", value = "STEEL", r = 1, g = 1, b = 1 },
    { text = "Ember", value = "EMBER", r = 1, g = 0.55, b = 0.4 },
    { text = "Forest", value = "FOREST", r = 0.6, g = 1, b = 0.65 },
    { text = "Frost", value = "FROST", r = 0.6, g = 0.8, b = 1 },
    { text = "Arcane", value = "ARCANE", r = 0.8, g = 0.6, b = 1 },
    { text = "Gold", value = "GOLD", r = 1, g = 0.85, b = 0.5 },
}

local DefaultSettings = {
    ShowConsole = false,
    ConsoleStyle = "FULL",
    ConsoleColor = "STEEL",
    ConsoleOpacity = 1.0,
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderConsoleDB, DefaultSettings)
    Commander.Notify(COMMANDER_CONSOLE_EVENTS.UPDATE)
    print("Commander Console: settings restored to defaults")
end

local function BuildOptions(list)
    local options = {}
    for _, entry in ipairs(list) do
        options[#options + 1] = { text = entry.text, value = entry.value }
    end
    return options
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Console",
        title = "Console",
        addonName = "Commander_Console",
        description = "Frames the game world like a classic RTS: the viewport rises and an armored command console fills the bottom of the screen, docking neatly under the suite's action bar, minimap, and bag panels.",
        event = COMMANDER_CONSOLE_EVENTS.UPDATE,
        slash = { "/cconsole", "/cc" },
        slashHandlers = {
            toggle = function()
                CommanderConsoleDB.ShowConsole = not CommanderConsoleDB.ShowConsole
                Commander.Notify(COMMANDER_CONSOLE_EVENTS.UPDATE)
            end,
        },
    })

    panel:AddSection("Console", "The console's height is matched to its artwork, so it always lines up with the world edge.")
    panel:AddCheckbox({
        label = "Show Console",
        tooltip = "Enable the console backdrop and shrink the game viewport to make room for it.",
        get = function() return CommanderConsoleDB.ShowConsole end,
        set = function(value) CommanderConsoleDB.ShowConsole = value end,
    })

    panel:AddSection("Appearance", "Pick the console's silhouette, metal tint, and how solid it appears over the world.")
    panel:AddDropdown({
        label = "Console Style",
        tooltip = "Full Console includes the raised side towers; Low Profile trims everything to one flat rail across the bottom.",
        options = BuildOptions(CommanderConsole_Styles),
        width = 160,
        get = function() return CommanderConsoleDB.ConsoleStyle end,
        set = function(value) CommanderConsoleDB.ConsoleStyle = value end,
        isEnabled = function() return CommanderConsoleDB.ShowConsole end,
    })
    panel:AddDropdown({
        label = "Console Color",
        tooltip = "Tint applied to the console metal. Steel is the untinted artwork.",
        options = BuildOptions(CommanderConsole_Colors),
        width = 160,
        get = function() return CommanderConsoleDB.ConsoleColor end,
        set = function(value) CommanderConsoleDB.ConsoleColor = value end,
        isEnabled = function() return CommanderConsoleDB.ShowConsole end,
    })
    panel:AddSlider({
        label = "Console Opacity",
        tooltip = "How solid the console artwork is. Lower values let the world show through.",
        min = 0.2, max = 1.0, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderConsoleDB.ConsoleOpacity end,
        set = function(value) CommanderConsoleDB.ConsoleOpacity = value end,
        isEnabled = function() return CommanderConsoleDB.ShowConsole end,
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event)
    if event == "PLAYER_LOGIN" then
        -- Merge defaults here so SavedVariables are already loaded
        Commander.UI.ApplyDefaults(CommanderConsoleDB, DefaultSettings)
        -- Drop the briefly-shipped ConsoleHeight setting; the art is fixed-size
        CommanderConsoleDB.ConsoleHeight = nil
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
