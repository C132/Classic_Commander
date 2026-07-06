CommanderConsoleDB = _G.CommanderConsoleDB or {}

COMMANDER_CONSOLE_EVENTS = {
    UPDATE = "COMMANDER_CONSOLE_UPDATE"
}

local DefaultSettings = {
    ShowConsole = false,
    ConsoleHeight = 150,
}

local function ApplyDefaults()
    for key, value in pairs(DefaultSettings) do
        if CommanderConsoleDB[key] == nil then
            CommanderConsoleDB[key] = value
        end
    end
end

local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    for key, value in pairs(DefaultSettings) do
        CommanderConsoleDB[key] = value
    end
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
            reset = Reset,
            toggle = function()
                CommanderConsoleDB.ShowConsole = not CommanderConsoleDB.ShowConsole
                Commander.Notify(COMMANDER_CONSOLE_EVENTS.UPDATE)
            end,
        },
    })

    panel:AddSection("Console")
    panel:AddCheckbox({
        label = "Show Console",
        tooltip = "Enable the console backdrop and shrink the game viewport to make room for it.",
        get = function() return CommanderConsoleDB.ShowConsole end,
        set = function(value) CommanderConsoleDB.ShowConsole = value end,
    })
    panel:AddSlider({
        label = "Console Height",
        tooltip = "How many pixels of the bottom of the screen the console area occupies.",
        min = 60, max = 300, step = 10,
        format = "%d px",
        get = function() return CommanderConsoleDB.ConsoleHeight end,
        set = function(value) CommanderConsoleDB.ConsoleHeight = value end,
        isEnabled = function() return CommanderConsoleDB.ShowConsole end,
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnAwake()
    -- Merge defaults here so SavedVariables are already loaded
    ApplyDefaults()
    CreateOptionsPanel()
end

local function OnEvent(self, event)
    if event == "PLAYER_LOGIN" then
        OnAwake()
    end
end

frame:SetScript("OnEvent", OnEvent)
