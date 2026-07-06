CommanderWhoDB = _G.CommanderWhoDB or {}

COMMANDER_WHO_EVENTS = {
    UPDATE = "COMMANDER_WHO_UPDATE"
}

local DefaultSettings = {
    ShowWhoWindow = true,
    ShowWhoButton = true,
    MaxWhisperCount = 50,  -- Safety limit for a single mass-whisper run
    WhisperDelay = 0.5,    -- Delay between whispers in seconds
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderWhoDB, DefaultSettings)
    Commander.Notify(COMMANDER_WHO_EVENTS.UPDATE)
    print("Commander Who: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Who",
        title = "Who",
        addonName = "Commander_Who",
        description = "Adds selection checkboxes and a mass whisper tool to the Who window, so you can message several players from one search.",
        event = COMMANDER_WHO_EVENTS.UPDATE,
        slash = { "/cw" },
    })

    panel:AddSection("Who Window")
    panel:AddCheckbox({
        label = "Show Who Window",
        tooltip = "Show the Who window itself. Unchecking hides the entire window.",
        get = function() return CommanderWhoDB.ShowWhoWindow end,
        set = function(value) CommanderWhoDB.ShowWhoWindow = value end,
    })
    panel:AddCheckbox({
        label = "Show Mass Whisper Toolbar",
        tooltip = "Show the column headers and the Mass Whisper / Select All / Select None buttons added to the Who window.",
        get = function() return CommanderWhoDB.ShowWhoButton end,
        set = function(value) CommanderWhoDB.ShowWhoButton = value end,
        isEnabled = function() return CommanderWhoDB.ShowWhoWindow end,
    })

    panel:AddSection("Mass Whisper")
    panel:AddSlider({
        label = "Maximum Recipients",
        tooltip = "Safety cap on how many players a single mass whisper can message.",
        min = 5, max = 100, step = 5,
        format = "%d",
        get = function() return CommanderWhoDB.MaxWhisperCount end,
        set = function(value) CommanderWhoDB.MaxWhisperCount = value end,
    })
    panel:AddSlider({
        label = "Delay Between Whispers",
        tooltip = "Seconds to wait between each whisper. Higher values are gentler on the server's chat throttle.",
        min = 0.2, max = 3.0, step = 0.1,
        format = function(value) return string.format("%.1f sec", value) end,
        get = function() return CommanderWhoDB.WhisperDelay end,
        set = function(value) CommanderWhoDB.WhisperDelay = value end,
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Who" then
        -- SavedVariables replace the global table after the file runs, so apply defaults here
        Commander.UI.ApplyDefaults(CommanderWhoDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
