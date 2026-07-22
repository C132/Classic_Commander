CommanderRankCheckDB = _G.CommanderRankCheckDB or {}

COMMANDER_RANKCHECK_EVENTS = {
    UPDATE = "COMMANDER_RANKCHECK_UPDATE"
}

local DefaultSettings = {
    EnableRankCheck = true,
    ShowSpellbookButton = true,
    CheckActionBars = true,
    CheckMacros = true,
    AnnounceClean = true,
}

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderRankCheckDB, DefaultSettings)
    Commander.Notify(COMMANDER_RANKCHECK_EVENTS.UPDATE)
    print("Commander Rank Check: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "RankCheck",
        title = "Rank Check",
        addonName = "Commander_RankCheck",
        description = "A unit test for your loadout: it scans every action bar slot and macro for a spell cast at an out-of-date rank, then reports any that a higher rank in your spellbook could replace — the classic chore of re-dragging spells and editing macros after you train. Run it with /crank or the button in the spellbook window.",
        event = COMMANDER_RANKCHECK_EVENTS.UPDATE,
        slash = { "/crank" },
        slashHandlers = {
            [""] = function()
                if CommanderRankCheck_Run then CommanderRankCheck_Run() end
            end,
        },
    })

    panel:AddCheckboxPair({
        label = "Enable Rank Check",
        tooltip = "Master switch. When off, the spellbook button and /crank do nothing.",
        get = function() return CommanderRankCheckDB.EnableRankCheck end,
        set = function(value) CommanderRankCheckDB.EnableRankCheck = value end,
    }, {
        label = "Spellbook Button",
        tooltip = "Show a Rank Check button inside the spellbook window.",
        get = function() return CommanderRankCheckDB.ShowSpellbookButton end,
        set = function(value) CommanderRankCheckDB.ShowSpellbookButton = value end,
        isEnabled = function() return CommanderRankCheckDB.EnableRankCheck end,
    })
    panel:AddCheckboxPair({
        label = "Check Action Bars",
        tooltip = "Scan every action bar slot (all pages and side bars) for out-of-date spell ranks.",
        get = function() return CommanderRankCheckDB.CheckActionBars end,
        set = function(value) CommanderRankCheckDB.CheckActionBars = value end,
        isEnabled = function() return CommanderRankCheckDB.EnableRankCheck end,
    }, {
        label = "Check Macros",
        tooltip = "Scan macros for /cast lines naming an out-of-date rank. A macro that casts a spell with no rank always uses your highest, so it is never flagged.",
        get = function() return CommanderRankCheckDB.CheckMacros end,
        set = function(value) CommanderRankCheckDB.CheckMacros = value end,
        isEnabled = function() return CommanderRankCheckDB.EnableRankCheck end,
    })
    panel:AddCheckbox({
        label = "Announce When Clean",
        tooltip = "Print a PASS line when everything is up to date. Off prints only when issues are found.",
        get = function() return CommanderRankCheckDB.AnnounceClean end,
        set = function(value) CommanderRankCheckDB.AnnounceClean = value end,
        isEnabled = function() return CommanderRankCheckDB.EnableRankCheck end,
    })

    panel:AddButtonRow({
        {
            label = "Run Check",
            width = 110,
            tooltip = "Scan your bars and macros now (also: /crank).",
            onClick = function()
                if CommanderRankCheck_Run then CommanderRankCheck_Run() end
            end,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_RankCheck" then
        Commander.UI.ApplyDefaults(CommanderRankCheckDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
