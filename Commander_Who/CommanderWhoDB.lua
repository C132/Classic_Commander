-- CommanderWhoDB.lua
--
-- Saved variables, defaults, the one-time migration off the 2.1 schema, and
-- the settings page. Nothing here touches the Who window; it writes the DB and
-- fires COMMANDER_WHO_EVENTS.UPDATE, and the host and UI files react.

CommanderWhoDB = _G.CommanderWhoDB or {}

COMMANDER_WHO_EVENTS = {
    -- Settings changed: re-read the DB and re-apply chrome/visibility.
    UPDATE = "COMMANDER_WHO_UPDATE",
    -- The result set or the selection changed: repaint both views.
    SELECTION = "COMMANDER_WHO_SELECTION",
    -- A mass whisper run started, advanced, finished or was stopped.
    RUN = "COMMANDER_WHO_RUN",
}

-- Prefix for the shared HUD chrome keys (WindowStyle / WindowScale /
-- WindowLocked / WindowPos) used by the mass whisper window.
COMMANDER_WHO_CHROME = "Window"

local DefaultSettings = {
    -- The Commander strip beside the Who tab (count, All/None/Invert, Mass
    -- Whisper). Turning it off leaves Blizzard's Who window completely alone.
    ShowToolbar = true,
    -- The per-row tick boxes in the Who list.
    ShowRowCheckboxes = true,
    -- Whether a fresh /who arrives with everything already ticked. Default
    -- off: mass whispering fifty strangers you have not looked at is the
    -- failure mode this module exists to avoid, and Select All is one click.
    SelectNewResults = false,
    -- Ask before a run starts, showing the recipient count and how long it
    -- will take.
    ConfirmBeforeSending = true,
    -- Safety cap on a single run.
    MaxWhisperCount = 25,
    -- Seconds between sends. One second is the honest default: the server's
    -- chat throttle is what disconnects you, and a 25-recipient run is 24
    -- seconds either way.
    WhisperDelay = 1.0,
}

for key, value in pairs(Commander.UI.HudChromeDefaults(COMMANDER_WHO_CHROME, "WINDOW")) do
    DefaultSettings[key] = value
end

COMMANDER_WHO_DEFAULTS = DefaultSettings

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

-- ---------------------------------------------------------------------------
-- Migration off 2.1
-- ---------------------------------------------------------------------------
-- ShowWhoButton became ShowToolbar. ShowWhoWindow is deleted outright rather
-- than carried forward: it called WhoFrame:SetShown() on a timer, which fights
-- FriendsFrame's own tab logic in both directions -- it force-showed the Who
-- panel at login and force-hid it out from under the tab that owns it (D5).
-- There is no replacement because there was no working feature.

local function Migrate(db)
    if db.ShowWhoButton ~= nil then
        if db.ShowToolbar == nil then
            db.ShowToolbar = db.ShowWhoButton and true or false
        end
        db.ShowWhoButton = nil
    end
    db.ShowWhoWindow = nil
    -- A saved delay from 2.1 could be 0.2s, below the floor the slider now
    -- offers. Clamp it so the stored value and the widget agree.
    if type(db.WhisperDelay) == "number" and db.WhisperDelay < 0.3 then
        db.WhisperDelay = 0.3
    end
    if type(db.MaxWhisperCount) ~= "number" or db.MaxWhisperCount < 5 then
        db.MaxWhisperCount = DefaultSettings.MaxWhisperCount
    end
end

local function Reset()
    Commander.UI.ResetToDefaults(CommanderWhoDB, DefaultSettings)
    Commander.Notify(COMMANDER_WHO_EVENTS.UPDATE)
    print("Commander Who: settings restored to defaults")
end

-- Soft calls into the sibling files: a file that failed to load must cost a
-- feature, never a settings page that errors on every click.
local function Host(method, ...)
    local api = _G.CommanderWho
    if api and type(api[method]) == "function" then
        return api[method](...)
    end
    print("Commander Who: the Who window integration is not loaded.")
end

local function CreateOptionsPanel()
    local db = CommanderWhoDB

    local panel = Commander.UI.NewPanel({
        key = "Who",
        title = "Who",
        addonName = "Commander_Who",
        description = "Turns /who into a recruiting tool: tick the players you want out of the search results — the ticks follow the player, not the row, so scrolling and re-sorting keep them — then type one message and it whispers exactly that set, throttled, with a running count and a stop button.",
        event = COMMANDER_WHO_EVENTS.UPDATE,
        -- One command only. The 2.1 build also registered "/cw", which the
        -- chat edit box's command matching confuses with the whisper family
        -- (D6); it is gone and is not coming back.
        slash = { "/cwho" },
        slashHandlers = {
            whisper = function() Host("OpenWhisperWindow") end,
            all     = function() Host("SelectAll") end,
            none    = function() Host("SelectNone") end,
        },
    })

    panel:AddSection("Who Window")
    panel:AddCheckbox({
        label = "Show Commander Toolbar",
        tooltip = "The strip beside the Who tab: how many are selected, All / None / Invert, and the Mass Whisper button. Unchecking leaves Blizzard's Who window untouched.",
        get = function() return db.ShowToolbar end,
        set = function(value) db.ShowToolbar = value end,
    })
    panel:AddCheckbox({
        label = "Show Tick Boxes On Who Rows",
        tooltip = "Adds a tick box to each row of the Who list. Shift-click a box to select the whole range from the last one you clicked. Unchecking restores Blizzard's row layout exactly.",
        get = function() return db.ShowRowCheckboxes end,
        set = function(value) db.ShowRowCheckboxes = value end,
    })
    panel:AddCheckbox({
        label = "Pre-select New Search Results",
        tooltip = "Tick every player a new /who returns. Off by default — a selection you did not make is a mass whisper you did not mean to send. Ticks you have already made are kept when the same player comes back in a later search either way.",
        get = function() return db.SelectNewResults end,
        set = function(value) db.SelectNewResults = value end,
    })

    panel:AddSection("Mass Whisper", "The delay and the recipient cap keep you clear of the server's chat throttle, which disconnects you rather than warning you.")
    panel:AddSlider({
        label = "Maximum Recipients",
        tooltip = "Hard cap on a single run. Anything selected beyond it is reported before the run starts, never silently dropped.",
        min = 5, max = 100, step = 5,
        format = "%d",
        get = function() return db.MaxWhisperCount end,
        set = function(value) db.MaxWhisperCount = value end,
    })
    panel:AddSlider({
        label = "Delay Between Whispers",
        tooltip = "Seconds between each send. Below roughly half a second a long run risks a disconnect for chat flooding.",
        min = 0.3, max = 3.0, step = 0.1,
        format = function(value) return string.format("%.1f sec", value) end,
        get = function() return db.WhisperDelay end,
        set = function(value) db.WhisperDelay = value end,
    })
    panel:AddCheckbox({
        label = "Confirm Before Sending",
        tooltip = "Show a confirmation naming the recipient count and how long the run will take before the first whisper goes out.",
        get = function() return db.ConfirmBeforeSending end,
        set = function(value) db.ConfirmBeforeSending = value end,
    })

    panel:AddSection("Mass Whisper Window")
    Commander.UI.AddHudChromeOptions(panel, db, COMMANDER_WHO_CHROME, {
        onChanged = function() Commander.Notify(COMMANDER_WHO_EVENTS.UPDATE) end,
        defaultPoint = { point = "CENTER", x = 0, y = 0 },
    })

    panel:AddButtonRow({
        {
            label = "Open Mass Whisper",
            tooltip = "Open the mass whisper window. Also available as /cwho whisper, or from the toolbar on the Who tab.",
            onClick = function() Host("OpenWhisperWindow") end,
        },
    })

    panel:Finalize({
        onDefaults = Reset,
        defaultsTooltip = "Reset every option on this page to its default value. Your current Who selection is not affected.",
    })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Who" then
        -- SavedVariables replace the global table after the file runs, so
        -- defaults and migration both have to happen here.
        CommanderWhoDB = _G.CommanderWhoDB or {}
        Migrate(CommanderWhoDB)
        Commander.UI.ApplyDefaults(CommanderWhoDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
