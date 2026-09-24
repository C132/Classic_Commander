CommanderQuestLogDB = _G.CommanderQuestLogDB or {}

COMMANDER_QUESTLOG_EVENTS = {
    UPDATE = "COMMANDER_QUESTLOG_UPDATE"
}

local DefaultSettings = {
    EnableQuestLog = true,
    -- The stock log is pushed off screen rather than hidden while this is on;
    -- turning it off gives the player Blizzard's window back with no reload
    TakeOverQuestLog = true,
    ShowLevels = true,
    ShowProgress = true,
    ShowZoneCounts = true,
    ShowRewards = true,
    ConfirmAbandon = true,
    AnnounceChannel = "AUTO",
    -- View state: remembered because it is where the player left the window,
    -- not because it is a preference
    Filter = "ALL",
    Sort = "LOG",
    -- Zone headings the player folded shut in OUR window. Display state, kept
    -- deliberately clear of the client's own collapse flags.
    Collapsed = {},
    -- Dark stone by default: the parchment was, and read as too bright next
    -- to the rest of the suite even after its ink was fixed. StyleGeneration
    -- is the one-shot that moved existing logs off it -- see OnEvent.
    FrameStyle = "STONE",
    StyleGeneration = 2,
    FrameScale = 1.0,
    FramePos = false,
}

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    -- Collapsed is data the player authored, not an option: a Restore
    -- Defaults that forgot which zones they had folded would read as the
    -- window losing its place. ResetToDefaults only writes defaulted keys, so
    -- it is lifted out and put back rather than being left out of the table.
    local collapsed = CommanderQuestLogDB.Collapsed
    Commander.UI.ResetToDefaults(CommanderQuestLogDB, DefaultSettings)
    CommanderQuestLogDB.Collapsed = collapsed or {}
    Commander.Notify(COMMANDER_QUESTLOG_EVENTS.UPDATE)
    print("Commander Quest Log: settings restored to defaults")
end

local STYLES = {
    { text = "Dark Stone (Default)", value = "STONE" },
    { text = "Parchment", value = "PARCHMENT" },
    { text = "Window", value = "WINDOW" },
    { text = "Dark", value = "DARK" },
}

local CHANNELS = {
    { text = "Automatic", value = "AUTO" },
    { text = "Party / Raid", value = "GROUP" },
    { text = "Say", value = "SAY" },
    { text = "Guild", value = "GUILD" },
    { text = "Yourself only", value = "SELF" },
}

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "QuestLog",
        title = "Quest Log",
        addonName = "Commander_QuestLog",
        description = "The campaign ledger: one double-wide window over the whole quest log. Every quest down the left under its zone — searchable, sortable, filterable — and the full briefing on the right: objectives with their progress, the description, every reward, and Track, Share, Announce and Abandon on the same screen.",
        event = COMMANDER_QUESTLOG_EVENTS.UPDATE,
        slash = { "/cql", "/cquests" },
        slashHandlers = {
            [""] = function() if CommanderQuestLog_Toggle then CommanderQuestLog_Toggle() end end,
        },
    })

    panel:AddSection("The Ledger")
    panel:AddCheckboxPair({
        label = "Enable Quest Log",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderQuestLogDB.EnableQuestLog end,
        set = function(value) CommanderQuestLogDB.EnableQuestLog = value end,
    }, {
        label = "Replace the Stock Quest Log",
        tooltip = "Open this window wherever the game would have opened Blizzard's — the L key, the micro button, a quest link. Off, both windows are available and this one answers to /cql and its own key binding.",
        get = function() return CommanderQuestLogDB.TakeOverQuestLog end,
        set = function(value) CommanderQuestLogDB.TakeOverQuestLog = value end,
        isEnabled = function() return CommanderQuestLogDB.EnableQuestLog end,
    })
    panel:AddDropdown({
        label = "Window Style",
        tooltip = "Dark Stone is the quest log's own border on the dark stone of the game's dialog boxes; Parchment is the stock log's paper; Window is the suite's inset panel; Dark is the flat HUD panel.",
        options = STYLES,
        width = 160,
        get = function() return CommanderQuestLogDB.FrameStyle end,
        set = function(value)
            CommanderQuestLogDB.FrameStyle = value
            if CommanderQuestLog and CommanderQuestLog.ApplyFraming then
                CommanderQuestLog.ApplyFraming(true)
            end
        end,
        isEnabled = function() return CommanderQuestLogDB.EnableQuestLog end,
    })
    panel:AddSlider({
        label = "Window Scale",
        tooltip = "Size of the whole window. The grip in its bottom right corner drives this too.",
        min = 0.6, max = 1.6, step = 0.05,
        format = "%.2fx",
        get = function() return CommanderQuestLogDB.FrameScale end,
        set = function(value)
            CommanderQuestLogDB.FrameScale = value
            if CommanderQuestLog and CommanderQuestLog.ApplyPosition then
                CommanderQuestLog.ApplyPosition()
            end
        end,
        isEnabled = function() return CommanderQuestLogDB.EnableQuestLog end,
    })

    panel:AddSection("The Navigator")
    panel:AddCheckboxPair({
        label = "Quest Levels",
        tooltip = "Show each quest's level beside its name, coloured by how it rates against yours.",
        get = function() return CommanderQuestLogDB.ShowLevels end,
        set = function(value) CommanderQuestLogDB.ShowLevels = value end,
        isEnabled = function() return CommanderQuestLogDB.EnableQuestLog end,
    }, {
        label = "Progress Bars",
        tooltip = "Draw a thin bar under each quest showing how far through its objectives you are.",
        get = function() return CommanderQuestLogDB.ShowProgress end,
        set = function(value) CommanderQuestLogDB.ShowProgress = value end,
        isEnabled = function() return CommanderQuestLogDB.EnableQuestLog end,
    })
    panel:AddCheckboxPair({
        label = "Zone Counts",
        tooltip = "Show \"3/5\" beside each zone heading: how many of its quests are ready to turn in.",
        get = function() return CommanderQuestLogDB.ShowZoneCounts end,
        set = function(value) CommanderQuestLogDB.ShowZoneCounts = value end,
        isEnabled = function() return CommanderQuestLogDB.EnableQuestLog end,
    }, {
        label = "Rewards",
        tooltip = "Show the reward icons on the briefing. Off, the briefing is objectives and description only.",
        get = function() return CommanderQuestLogDB.ShowRewards end,
        set = function(value) CommanderQuestLogDB.ShowRewards = value end,
        isEnabled = function() return CommanderQuestLogDB.EnableQuestLog end,
    })

    panel:AddSection("Actions")
    panel:AddCheckbox({
        label = "Confirm Before Abandoning",
        tooltip = "Ask before dropping a quest. Leave this on: abandoning is not undoable, and a quest chain you have to walk back three zones for is a long afternoon.",
        get = function() return CommanderQuestLogDB.ConfirmAbandon end,
        set = function(value) CommanderQuestLogDB.ConfirmAbandon = value end,
        isEnabled = function() return CommanderQuestLogDB.EnableQuestLog end,
    })
    panel:AddDropdown({
        label = "Announce To",
        tooltip = "Where the Announce button sends a quest's progress. Automatic picks your raid, then your party, then yourself.",
        options = CHANNELS,
        width = 160,
        get = function() return CommanderQuestLogDB.AnnounceChannel end,
        set = function(value) CommanderQuestLogDB.AnnounceChannel = value end,
        isEnabled = function() return CommanderQuestLogDB.EnableQuestLog end,
    })
    panel:AddButtonRow({
        {
            label = "Open the Ledger",
            width = 130,
            tooltip = "Open the quest log window (also: /cql, and a key binding under Commander Quest Log).",
            onClick = function()
                if CommanderQuestLog_Toggle then CommanderQuestLog_Toggle() end
            end,
        },
        {
            label = "Reset Position",
            width = 120,
            tooltip = "Put the window back in the middle of the screen.",
            onClick = function()
                CommanderQuestLogDB.FramePos = false
                if CommanderQuestLog and CommanderQuestLog.ApplyPosition then
                    CommanderQuestLog.ApplyPosition()
                end
            end,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_QuestLog" then
        -- One-shot: a log saved before StyleGeneration existed that is on
        -- PARCHMENT is on it because that was the default, not because it was
        -- picked. It moves to the new default once; ApplyDefaults then stamps
        -- the generation, so a Parchment chosen after this stays chosen.
        if CommanderQuestLogDB.StyleGeneration == nil and CommanderQuestLogDB.FrameStyle == "PARCHMENT" then
            CommanderQuestLogDB.FrameStyle = "STONE"
        end
        Commander.UI.ApplyDefaults(CommanderQuestLogDB, DefaultSettings)
        if type(CommanderQuestLogDB.Collapsed) ~= "table" then
            CommanderQuestLogDB.Collapsed = {}
        end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
