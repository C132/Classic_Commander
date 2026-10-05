CommanderQuestLogDB = _G.CommanderQuestLogDB or {}
-- Per character: the quests this character told the Zones tab to leave out of
-- its 100% (Ignored), and what the game was seen to pay this character for a
-- turn-in (RepObserved, written by the Questie adapter's calibration). An
-- alt's lists are not a main's, which is why they are not in the
-- account-wide table above -- and why Restore Defaults never touches them.
CommanderQuestLogChar = _G.CommanderQuestLogChar or {}

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
    -- The two clocks under the navigator: the daily reset and the weekly
    -- one (arena points, raid lockouts)
    ShowResetTimers = true,
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

    -- The tabs. ViewMode is where the player left the window, like Filter
    -- and Sort: a registered tab's id, "LOG", "ZONE" or "REP" (anything else,
    -- or a tab since switched off, opens on the Log). ShowZoneTab and
    -- ShowRepTab are the switches for the two catalogue tabs.
    ViewMode = "LOG",
    ShowZoneTab = true,
    ZoneFilter = "ALL",
    ZoneGroup = "GUIDE",
    -- Group headings folded shut on the Zones tab, keyed by the engine's
    -- fixed group titles (and chain titles). Its own table, never Collapsed:
    -- the two lists are different namespaces that happen to share a widget.
    ZoneCollapsed = {},
    -- Follow the zone the player stands in, or stay on ZonePicked (an AREA
    -- id, Questie's id space; false when nothing is pinned)
    ZoneFollow = true,
    ZonePicked = false,
    -- What counts toward a zone's 100%. Off by default, each for a reason
    -- the settings tooltips spell out.
    CountOptional = false,
    CountRival = false,
    CountExtras = false,

    -- The Reputations tab: every quest that pays one faction. Its keys are
    -- the Zones tab's under its own stem (the catalogue names them from the
    -- prefix "Rep"): RepFollow follows the faction the player watches in the
    -- game's Reputation pane (else the one their log's quests pay most),
    -- RepPicked is a faction id pinned instead (false: none; account-wide
    -- like the rest, so a pin of the other side's faction, an alt's, is
    -- passed over on this side), RepCollapsed its own fold table, keyed by
    -- its group titles.
    ShowRepTab = true,
    RepFilter = "ALL",
    RepGroup = "GUIDE",
    RepCollapsed = {},
    RepFollow = true,
    RepPicked = false,
    -- The picker lists the classic factions (the capitals, the goblin towns,
    -- Argent Dawn...) under the TBC ones, each once it has a quest for this
    -- character. Off, it is the TBC factions alone.
    RepIncludeClassic = true,
    -- Reputation on every surface that shows a quest: one number, the rules
    -- engine's (CommanderQuestLogStanding.lua), on the Log's briefing, the
    -- Zones tab, the map drawer, a waypoint's note and the quest giver's own
    -- dialog. ZoneRowRep and RepInQuestDialog are two of those surfaces,
    -- each with a switch of its own under this one.
    ShowRepEverywhere = true,
    ZoneRowRep = true,
    RepInQuestDialog = true,

    -- The world map: a completion drawer docked inside its right edge, and
    -- pins on the quest givers Questie does not draw
    MapDrawer = true,
    MapDrawerOpen = true,
    MapPins = true,
    MapPinsLocked = true,
    MapPinsAvailable = true,
    MapPinsDone = false,
    MapPinsMissed = false,
    MapZoneLabels = true,
    -- The drawer's folded groups, Done folded from the start: a zone you are
    -- working through is mostly the part you have not done
    MapCollapsed = { Done = true },
}

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    -- Collapsed is data the player authored, not an option: a Restore
    -- Defaults that forgot which zones they had folded would read as the
    -- window losing its place. ResetToDefaults only writes defaulted keys, so
    -- it is lifted out and put back rather than being left out of the table.
    -- The Zones and Reputations tabs' folds and the map drawer's are the same
    -- kind of thing and get the same treatment.
    local collapsed = CommanderQuestLogDB.Collapsed
    local zoneCollapsed = CommanderQuestLogDB.ZoneCollapsed
    local repCollapsed = CommanderQuestLogDB.RepCollapsed
    local mapCollapsed = CommanderQuestLogDB.MapCollapsed
    Commander.UI.ResetToDefaults(CommanderQuestLogDB, DefaultSettings)
    CommanderQuestLogDB.Collapsed = collapsed or {}
    if type(zoneCollapsed) == "table" then CommanderQuestLogDB.ZoneCollapsed = zoneCollapsed end
    if type(repCollapsed) == "table" then CommanderQuestLogDB.RepCollapsed = repCollapsed end
    if type(mapCollapsed) == "table" then CommanderQuestLogDB.MapCollapsed = mapCollapsed end
    Commander.Notify(COMMANDER_QUESTLOG_EVENTS.UPDATE)
    print("Commander Quest Log: settings restored to defaults")
end

-- The per-character table, made whole. Safe to call at any time: the saved
-- variable arrives just before ADDON_LOADED, and anything that writes to it
-- (the Ignore button, Clear Ignored) calls this first rather than trusting
-- the load order.
local function EnsureCharDB()
    if type(CommanderQuestLogChar) ~= "table" then CommanderQuestLogChar = {} end
    if type(CommanderQuestLogChar.Ignored) ~= "table" then CommanderQuestLogChar.Ignored = {} end
    -- RepObserved is made by the adapter on its first sample, never here; a
    -- value that is not a table is not one it wrote, and would only be read
    -- around, so it goes
    if CommanderQuestLogChar.RepObserved ~= nil and type(CommanderQuestLogChar.RepObserved) ~= "table" then
        CommanderQuestLogChar.RepObserved = nil
    end
    return CommanderQuestLogChar
end

CommanderQuestLog = CommanderQuestLog or {}
CommanderQuestLog.EnsureCharDB = EnsureCharDB

local function ClearIgnored()
    local charDB = EnsureCharDB()
    local count = 0
    for _ in pairs(charDB.Ignored) do count = count + 1 end
    charDB.Ignored = {}
    local adapter = CommanderQuestLog and CommanderQuestLog.Questie
    if adapter and adapter.Bump then adapter.Bump("ignore") end
    print(string.format("Commander Quest Log: %d ignored quest%s back in the count for this character.",
        count, count == 1 and "" or "s"))
end

-- /cql status: what the Questie adapter can see, one line each
local function PrintStatus()
    local adapter = CommanderQuestLog and CommanderQuestLog.Questie
    if not (adapter and adapter.StatusLines) then
        print("Commander Quest Log: the Questie adapter is not loaded.")
        return
    end
    print("Commander Quest Log status:")
    for _, line in ipairs(adapter.StatusLines() or {}) do
        print("  " .. tostring(line))
    end
end

local function Enabled()
    return CommanderQuestLogDB.EnableQuestLog
end

-- The per-surface reputation switches are under the one that turns
-- reputation off everywhere
local function RepEverywhereEnabled()
    return CommanderQuestLogDB.EnableQuestLog and CommanderQuestLogDB.ShowRepEverywhere ~= false
end

-- /cql rep [faction]: the Reputations tab on a faction found by name (any
-- part of it, any case, apostrophes optional: "shatar", "cons", "Honor
-- Hold") or by id; no name follows the faction you watch. The tab file
-- does the finding, from the names the client and the data know.
local function OpenReputations(text)
    local reps = CommanderQuestLog and CommanderQuestLog.Reps
    if not (reps and reps.OpenTo) then
        print("Commander Quest Log: the Reputations tab is not loaded.")
        return
    end
    reps.OpenTo(text)
end

local function PinsEnabled()
    return CommanderQuestLogDB.EnableQuestLog and CommanderQuestLogDB.MapPins ~= false
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
        description = "The campaign ledger: one double-wide window over the whole quest log. Every quest down the left under its zone — searchable, sortable, filterable — and the full briefing on the right: objectives with their progress, the description, every reward, and Track, Share, Announce and Abandon on the same screen. With Questie loaded, a Zones tab and a drawer on the world map show every quest a zone holds for this character: what is done, what is open, what is locked or missed and why, and how close the zone is to 100%.",
        event = COMMANDER_QUESTLOG_EVENTS.UPDATE,
        slash = { "/cql", "/cquests" },
        slashHandlers = {
            [""] = function() if CommanderQuestLog_Toggle then CommanderQuestLog_Toggle() end end,
            -- The Zones tab on the zone you stand in, following you from there
            zone = function()
                if CommanderQuestLog_OpenToZone then CommanderQuestLog_OpenToZone() end
            end,
            -- The Reputations tab following the faction you watch; with a
            -- name after it, see the wrapper after Finalize below
            rep = function() OpenReputations(nil) end,
            status = PrintStatus,
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
    panel:AddCheckbox({
        label = "Reset Timers",
        tooltip = "Two countdowns under the quest list: how long until the daily quests reset, and how long until the weekly reset that pays out arena points and clears raid lockouts. Hover either for the server time it lands on; the weekly one also lists your current lockouts.",
        get = function() return CommanderQuestLogDB.ShowResetTimers end,
        set = function(value)
            CommanderQuestLogDB.ShowResetTimers = value
            if CommanderQuestLog and CommanderQuestLog.AnchorNavPane then
                CommanderQuestLog.AnchorNavPane()
            end
        end,
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

    -- Going past three sections flips the page to first-fold-open with a
    -- search box over it. That is the framework's rule for a long page, and
    -- this one now is.
    panel:AddSection("Zones & Completion")
    panel:AddCheckbox({
        label = "Zones Tab",
        tooltip = "A tab in the quest log window: every quest a zone holds for this character, read from Questie's database, with a completion bar and a guide to what to do next. Needs Questie; the Log tab works without it.",
        get = function() return CommanderQuestLogDB.ShowZoneTab ~= false end,
        set = function(value) CommanderQuestLogDB.ShowZoneTab = value end,
        isEnabled = Enabled,
    })
    panel:AddCheckboxPair({
        label = "Count Optional Quests",
        tooltip = "Questie keeps some quests off its map on purpose — most are sets removed in later patches, and several of those exclude each other. Off, they are listed under Optional and left out of a zone's 100%, so a zone can actually reach it.",
        get = function() return CommanderQuestLogDB.CountOptional == true end,
        set = function(value) CommanderQuestLogDB.CountOptional = value end,
        isEnabled = Enabled,
    }, {
        label = "Count Both Aldor and Scryers",
        tooltip = "Off, quests gated on the Shattrath faction you did not side with are listed under Other faction and left out of the 100%: the other side can be ground back up, but a completion figure should not assume you will. On, both sides count.",
        get = function() return CommanderQuestLogDB.CountRival == true end,
        set = function(value) CommanderQuestLogDB.CountRival = value end,
        isEnabled = Enabled,
    })
    panel:AddCheckbox({
        label = "Count Dungeon and Class Quests That Start Here",
        tooltip = "Dungeon, class and profession quests are filed under their own headings, not under the zone whose quest giver they stand beside. Off, they are listed under Also starting here without counting; on, they count toward that zone's 100%.",
        get = function() return CommanderQuestLogDB.CountExtras == true end,
        set = function(value) CommanderQuestLogDB.CountExtras = value end,
        isEnabled = Enabled,
    })
    panel:AddButtonRow({
        {
            label = "Open Zones",
            width = 110,
            tooltip = "Open the quest log on the Zones tab at the zone you are standing in (also: /cql zone).",
            onClick = function()
                if CommanderQuestLog_OpenToZone then CommanderQuestLog_OpenToZone() end
            end,
            isEnabled = Enabled,
        },
        {
            label = "Clear Ignored (per character)",
            width = 200,
            tooltip = "Put every quest this character told the Zones tab to ignore back into its zone's 100%. Each character keeps its own list, so this one's is the only one cleared.",
            onClick = ClearIgnored,
            isEnabled = Enabled,
        },
    })

    panel:AddSection("Reputation")
    panel:AddCheckboxPair({
        label = "Reputations Tab",
        tooltip = "A tab in the quest log window grouped by faction: every quest that pays one faction, what each is worth to this character, what is left, whether quests alone reach the next standing or Exalted, the quests to do before their door shuts, and the repeatables and dailies that carry on from there. Needs Questie; the Log tab works without it.",
        get = function() return CommanderQuestLogDB.ShowRepTab ~= false end,
        set = function(value) CommanderQuestLogDB.ShowRepTab = value end,
        isEnabled = Enabled,
    }, {
        label = "Classic Factions in the Picker",
        tooltip = "List the older factions too — the capital cities, the goblin towns, Argent Dawn and the rest — each under its own heading after the Outland ones, once it has a quest for this character. Off, the picker is the Outland factions alone.",
        get = function() return CommanderQuestLogDB.RepIncludeClassic ~= false end,
        set = function(value) CommanderQuestLogDB.RepIncludeClassic = value end,
        isEnabled = Enabled,
    })
    panel:AddCheckbox({
        label = "Reputation on Every Quest",
        tooltip = "Say what a quest is worth in reputation wherever it is shown — the Log's briefing, the Zones tab, the map drawer, a waypoint's note, the quest giver's own window — including \"No reputation\" for a quest that pays none. One number everywhere, worked out by this module's own rules: Diplomacy and the Hallow's End buff, the Aldor and Scryers losses, spillover, and the quests whose reward stops at a standing. Once you have turned a quest in, what the game actually paid replaces the estimate.",
        get = function() return CommanderQuestLogDB.ShowRepEverywhere ~= false end,
        set = function(value) CommanderQuestLogDB.ShowRepEverywhere = value end,
        isEnabled = Enabled,
    })
    panel:AddCheckboxPair({
        label = "Reputation on Zone Rows",
        tooltip = "A short figure and the faction it is for (\"+250 HH\") beside each quest on the Zones tab's list, and on the world map drawer's rows while the map is maximized: the most it pays any one faction, and which. The row's tooltip and the briefing carry the whole line.",
        get = function() return CommanderQuestLogDB.ZoneRowRep ~= false end,
        set = function(value) CommanderQuestLogDB.ZoneRowRep = value end,
        isEnabled = RepEverywhereEnabled,
    }, {
        label = "Reputation in the Quest Dialog",
        tooltip = "A line in the quest giver's own window — when a quest is offered and when it is handed in — saying what it will pay (\"Reputation: +250 Honor Hold\", or \"No reputation\"). A plain line of text added under the rewards; nothing of the game's own window is changed.",
        get = function() return CommanderQuestLogDB.RepInQuestDialog ~= false end,
        set = function(value) CommanderQuestLogDB.RepInQuestDialog = value end,
        isEnabled = RepEverywhereEnabled,
    })
    panel:AddButtonRow({
        {
            label = "Open Reputations",
            width = 130,
            tooltip = "Open the quest log on the Reputations tab at the faction you watch (also: /cql rep, or /cql rep followed by a faction's name).",
            onClick = function() OpenReputations(nil) end,
            isEnabled = Enabled,
        },
    })

    panel:AddSection("World Map")
    panel:AddCheckboxPair({
        label = "Completion Drawer",
        tooltip = "A panel inside the world map's right edge: the shown zone's completion and its quests, or on a continent every zone's percentage. Click its header to fold it to a strip.",
        get = function() return CommanderQuestLogDB.MapDrawer ~= false end,
        set = function(value) CommanderQuestLogDB.MapDrawer = value end,
        isEnabled = Enabled,
    }, {
        label = "Quest Giver Pins",
        tooltip = "Marks on the world map for quest givers Questie does not draw. Questie's own marks are left exactly as they are; these only fill in what it leaves out.",
        get = function() return CommanderQuestLogDB.MapPins ~= false end,
        set = function(value) CommanderQuestLogDB.MapPins = value end,
        isEnabled = Enabled,
    })
    panel:AddCheckboxPair({
        label = "Locked Givers",
        tooltip = "Pin the givers of quests you cannot take yet — waiting on your level, an earlier quest, reputation or a skill. Questie never draws these.",
        get = function() return CommanderQuestLogDB.MapPinsLocked ~= false end,
        set = function(value) CommanderQuestLogDB.MapPinsLocked = value end,
        isEnabled = PinsEnabled,
    }, {
        label = "Available Givers Questie Hides",
        tooltip = "Pin the givers of quests you can take now that Questie is not drawing itself. Quests Questie does draw are never pinned twice.",
        get = function() return CommanderQuestLogDB.MapPinsAvailable ~= false end,
        set = function(value) CommanderQuestLogDB.MapPinsAvailable = value end,
        isEnabled = PinsEnabled,
    })
    panel:AddCheckboxPair({
        label = "Completed Givers",
        tooltip = "Pin the givers of quests you have already turned in, for a zone you are sweeping a second time.",
        get = function() return CommanderQuestLogDB.MapPinsDone == true end,
        set = function(value) CommanderQuestLogDB.MapPinsDone = value end,
        isEnabled = PinsEnabled,
    }, {
        label = "Missed Givers",
        tooltip = "Pin the givers of quests this character can no longer get, each with the reason in its tooltip.",
        get = function() return CommanderQuestLogDB.MapPinsMissed == true end,
        set = function(value) CommanderQuestLogDB.MapPinsMissed = value end,
        isEnabled = PinsEnabled,
    })
    panel:AddCheckbox({
        label = "Zone Percentages on Continent Maps",
        tooltip = "On a continent map, a small label over each zone with how much of it you have done. Zones are worked out in the background, a few a second, so the labels fill in as you watch. The labels are map pins, so they go with Quest Giver Pins.",
        get = function() return CommanderQuestLogDB.MapZoneLabels ~= false end,
        set = function(value) CommanderQuestLogDB.MapZoneLabels = value end,
        isEnabled = PinsEnabled,
    })

    panel:Finalize({ onDefaults = Reset })

    -- The framework matches a subcommand on the whole line, so "/cql rep
    -- shatar" would be its usage message. A faction's name after "rep" is
    -- taken here, ahead of it; every other line goes on to the framework.
    local key = "COMMANDERUI_QUESTLOG"
    local framework = SlashCmdList and SlashCmdList[key]
    if type(framework) == "function" then
        SlashCmdList[key] = function(msg)
            local text = type(msg) == "string" and msg:match("^%s*[Rr][Ee][Pp]%s+(.-)%s*$") or nil
            if text and text ~= "" then
                OpenReputations(text)
                return
            end
            return framework(msg)
        end
    end
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
        if type(CommanderQuestLogDB.ZoneCollapsed) ~= "table" then
            CommanderQuestLogDB.ZoneCollapsed = {}
        end
        if type(CommanderQuestLogDB.RepCollapsed) ~= "table" then
            CommanderQuestLogDB.RepCollapsed = {}
        end
        if type(CommanderQuestLogDB.MapCollapsed) ~= "table" then
            CommanderQuestLogDB.MapCollapsed = { Done = true }
        end
        EnsureCharDB()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
