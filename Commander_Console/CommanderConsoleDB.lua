CommanderConsoleDB = _G.CommanderConsoleDB or {}

COMMANDER_CONSOLE_EVENTS = {
    UPDATE = "COMMANDER_CONSOLE_UPDATE"
}

-- The console strip's height is fixed by the artwork baked into Console3.png
-- (a fullscreen overlay), so it is deliberately not a setting: a different
-- viewport inset would misalign the world edge with the art.
local DefaultSettings = {
    ShowConsole = false,
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderConsoleDB, DefaultSettings)
    Commander.Notify(COMMANDER_CONSOLE_EVENTS.UPDATE)
    print("Commander Console: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Console",
        title = "Console",
        addonName = "Commander_Console",
        description = "Frames the game world with an RTS-style console: the viewport is raised and a command console backdrop fills the bottom of the screen.",
        event = COMMANDER_CONSOLE_EVENTS.UPDATE,
        slash = { "/cc" },
        slashHandlers = {
            toggle = function()
                CommanderConsoleDB.ShowConsole = not CommanderConsoleDB.ShowConsole
                Commander.Notify(COMMANDER_CONSOLE_EVENTS.UPDATE)
            end,
        },
    })

    panel:AddSection("Console")
    panel:AddCheckbox({
        label = "Show Console",
        tooltip = "Enable the console backdrop and shrink the game viewport to make room for it. The console's height is fixed by its artwork.",
        get = function() return CommanderConsoleDB.ShowConsole end,
        set = function(value) CommanderConsoleDB.ShowConsole = value end,
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
