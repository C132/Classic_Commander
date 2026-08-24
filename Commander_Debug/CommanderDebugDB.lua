CommanderDebugDB = _G.CommanderDebugDB or {}

COMMANDER_DEBUG_EVENTS = {
    UPDATE = "COMMANDER_DEBUG_UPDATE",   -- settings changed
    CAPTURED = "COMMANDER_DEBUG_CAPTURED", -- a new error landed
}

-- Scope values match CommanderDebug.Capture.GetErrors
COMMANDER_DEBUG_SCOPES = {
    { text = "This Session", value = "SESSION" },
    { text = "Everything Kept", value = "ALL" },
}

local DefaultSettings = {
    Scope = "SESSION",       -- SESSION = since the last login or /reload
    OnlyCommander = false,   -- keep only errors traced to a Commander_* addon
    IncludeStacks = true,
    IncludeLocals = false,   -- locals dwarf everything else; opt in when needed
    IncludeAddonList = true,
    IncludeSystemInfo = true,
    MaxErrors = 25,
    StackLines = 14,
    LocalsLines = 20,
    PageSize = 18000,        -- characters per copy page
    AutoSelect = true,       -- focus + select the text the moment the window opens
    Announce = false,        -- chat nudge when a new error is captured
}

CommanderDebug = CommanderDebug or {}
CommanderDebug.Defaults = DefaultSettings

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderDebugDB, DefaultSettings)
    Commander.Notify(COMMANDER_DEBUG_EVENTS.UPDATE)
    print("Commander Debug: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Debug",
        title = "Debug",
        addonName = "Commander_Debug",
        description = "Gathers every Lua error the client has raised — from BugGrabber when it is installed, from its own error hook when it is not — and writes them into a single markdown prompt you can paste straight into Claude. Open the window, hit Select All, copy.",
        event = COMMANDER_DEBUG_EVENTS.UPDATE,
        slash = { "/cdebug", "/cbug" },
        slashHandlers = {
            [""] = function() CommanderDebug_Toggle() end,
            copy = function() CommanderDebug_Copy() end,
            list = function() CommanderDebug_List() end,
            clear = function() CommanderDebug_Clear() end,
            test = function() CommanderDebug_RaiseTestError() end,
        },
    })

    panel:AddSection("What Goes In The Prompt", "The report is rebuilt every time the window opens, so these apply immediately.")
    panel:AddDropdown({
        label = "Errors To Include",
        tooltip = "This Session covers everything since your last login or /reload — what you almost always want when chasing a bug you just hit.\n\nEverything Kept reaches back through BugGrabber's whole saved history (up to 500 unique errors across every session).",
        options = COMMANDER_DEBUG_SCOPES,
        get = function() return CommanderDebugDB.Scope end,
        set = function(value) CommanderDebugDB.Scope = value end,
    })
    panel:AddCheckbox({
        label = "Commander Addons Only",
        tooltip = "Drop any error that cannot be traced to a Commander_* addon. Useful when a third-party addon is spamming and drowning out your own.",
        get = function() return CommanderDebugDB.OnlyCommander end,
        set = function(value) CommanderDebugDB.OnlyCommander = value end,
    })
    panel:AddCheckboxPair({
        label = "Include Call Stacks",
        tooltip = "The call stack is usually what makes an error fixable — leave this on unless you are only after the error text.",
        get = function() return CommanderDebugDB.IncludeStacks end,
        set = function(value) CommanderDebugDB.IncludeStacks = value end,
    }, {
        label = "Include Locals",
        tooltip = "Local variable dumps at the moment of the error. Enormously verbose — worth turning on for one stubborn error, not for a full sweep.",
        get = function() return CommanderDebugDB.IncludeLocals end,
        set = function(value) CommanderDebugDB.IncludeLocals = value end,
    })
    panel:AddCheckboxPair({
        label = "Include Client Info",
        tooltip = "Client build, interface version, locale and character — context that stops the fix being written against the wrong API version.",
        get = function() return CommanderDebugDB.IncludeSystemInfo end,
        set = function(value) CommanderDebugDB.IncludeSystemInfo = value end,
    }, {
        label = "Include Addon List",
        tooltip = "The loaded addons and their versions, so a fix can account for what else is hooking the same frames.",
        get = function() return CommanderDebugDB.IncludeAddonList end,
        set = function(value) CommanderDebugDB.IncludeAddonList = value end,
    })

    panel:AddSection("Size", "A copy box has limits, and so does a prompt. Anything over the page budget is split into numbered pages you copy one at a time.")
    panel:AddSlider({
        label = "Maximum Errors",
        tooltip = "How many unique errors to include, newest first.",
        min = 5, max = 100, step = 5,
        format = "%d",
        get = function() return CommanderDebugDB.MaxErrors end,
        set = function(value) CommanderDebugDB.MaxErrors = value end,
    })
    panel:AddSliderPair({
        label = "Stack Lines",
        tooltip = "Lines kept from each call stack. The top frames are the ones that matter; the tail is usually Blizzard plumbing.",
        min = 4, max = 40, step = 1,
        format = "%d",
        get = function() return CommanderDebugDB.StackLines end,
        set = function(value) CommanderDebugDB.StackLines = value end,
        isEnabled = function() return CommanderDebugDB.IncludeStacks end,
    }, {
        label = "Locals Lines",
        tooltip = "Lines kept from each locals dump.",
        min = 5, max = 80, step = 5,
        format = "%d",
        get = function() return CommanderDebugDB.LocalsLines end,
        set = function(value) CommanderDebugDB.LocalsLines = value end,
        isEnabled = function() return CommanderDebugDB.IncludeLocals end,
    })
    panel:AddSlider({
        label = "Characters Per Page",
        tooltip = "The copy box splits the report at error boundaries once it passes this many characters. Every page carries the full header so each one stands alone as a prompt.",
        min = 4000, max = 60000, step = 1000,
        format = function(value) return string.format("%dk", value / 1000) end,
        get = function() return CommanderDebugDB.PageSize end,
        set = function(value) CommanderDebugDB.PageSize = value end,
    })

    panel:AddSection("Behaviour")
    panel:AddCheckboxPair({
        label = "Select Text On Open",
        tooltip = "Focus and highlight the whole report as soon as the window opens, so copying is a single keystroke.",
        get = function() return CommanderDebugDB.AutoSelect end,
        set = function(value) CommanderDebugDB.AutoSelect = value end,
    }, {
        label = "Announce New Errors",
        tooltip = "Print a one-line chat notice the first time each new error is captured.",
        get = function() return CommanderDebugDB.Announce end,
        set = function(value) CommanderDebugDB.Announce = value end,
    })

    panel:AddButtonRow({
        {
            label = "Open Report",
            width = 140,
            tooltip = "Build the prompt from the errors captured so far and open the copy window.",
            onClick = function() CommanderDebug_Show() end,
        },
        {
            label = "Clear Errors",
            width = 140,
            tooltip = "Throw away every captured error and start clean. When BugGrabber is installed this clears its database too — BugSack will empty with it.",
            onClick = function() CommanderDebug_Clear() end,
        },
        {
            label = "Raise Test Error",
            width = 140,
            tooltip = "Deliberately raise one harmless error so you can confirm capture is working end to end.",
            onClick = function() CommanderDebug_RaiseTestError() end,
        },
    })

    panel:Finalize({ onDefaults = Reset })

    -- The report window's Settings button needs somewhere to jump to
    CommanderDebug.CategoryID = panel._categoryID
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Debug" then
        -- SavedVariables replace the global table after the file runs, so apply defaults here
        Commander.UI.ApplyDefaults(CommanderDebugDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
