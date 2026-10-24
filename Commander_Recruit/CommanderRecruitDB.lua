CommanderRecruitDB = _G.CommanderRecruitDB or {}
CommanderRecruit = _G.CommanderRecruit or {}

COMMANDER_RECRUIT_EVENTS = {
    UPDATE = "COMMANDER_RECRUIT_UPDATE",
}

local DefaultSettings = {
    EnableRecruit = true,
    FreshMinutes = 15,          -- seen online inside this many minutes counts as online
    MinRating = 0,              -- hide anyone below this in a bracket (0 = everyone rated)
    -- Where "online" comes from, each its own switch
    UseWho = true,              -- /who results: the sweep's and your own
    UseLFG = true,              -- group finder listings, every member
    UseChat = true,             -- a line in a channel, guild, whisper, say or yell
    UseGuild = true,            -- the guild roster's online flag
    UseFriends = true,          -- online friends
    UseSeen = true,             -- friendly players under the cursor, targeted, on nameplates
    SocialButton = true,        -- the Recruit icon in the Social window's title bar
    -- The sweep's search order (R21), set in the window's class list
    SweepOrder = false,         -- class tokens, first searched first (false = the default order)
    SweepOff = false,           -- { [class] = true } for classes not searched
    SweepInOrder = false,       -- ask down the order instead of most rated finds first
    SweepHideOff = true,        -- the board shows only the classes searched
    HideOtherRealms = true,     -- the board shows only your realm's players (R27)
    SweepDepth = 2,             -- a steered /who must be worth this many rated finds (R26): 2, 1 or 0.5
    -- false (not nil) so Restore Defaults clears a saved drag
    Pos = false,
}

CommanderRecruit.Defaults = DefaultSettings

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function IsOn() return CommanderRecruitDB.EnableRecruit end

local function Reset()
    Commander.UI.ResetToDefaults(CommanderRecruitDB, DefaultSettings)
    Commander.Notify(COMMANDER_RECRUIT_EVENTS.UPDATE)
    print("Commander Recruit: settings restored to defaults")
end

local function Report()
    if CommanderRecruit.Status then print("Commander Recruit: " .. CommanderRecruit.Status()) end
end

local function UnwatchAll()
    if not CommanderRecruit.UnwatchAll then return end
    local removed, kept = CommanderRecruit.UnwatchAll()
    print(string.format("Commander Recruit: stopped watching everyone; %d friend%s Recruit added came off your friends list%s.",
        removed, removed == 1 and "" or "s",
        kept > 0 and string.format(", %d you already had stay%s", kept, kept == 1 and "s" or "") or ""))
end

-- How deep a steered sweep goes (R26): the fewest rated players a /who must
-- be expected to find. The numbers in the tooltips are from a model of the
-- realm's real roster with ~1,500 unrated level 70s on.
local DEPTH_OPTIONS = {
    { text = "Quick (stop under 2 a press)", value = 2 },
    { text = "Thorough (under 1)", value = 1 },
    { text = "Deep (under 0.5)", value = 0.5 },
}

local MIN_OPTIONS = {
    { text = "Everyone rated", value = 0 },
    { text = "1500 and up", value = 1500 },
    { text = "1600 and up", value = 1600 },
    { text = "1650 and up", value = 1650 },
    { text = "1800 and up", value = 1800 },
    { text = "2000 and up", value = 2000 },
    { text = "2200 and up", value = 2200 },
}

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Recruit",
        title = "Recruit",
        addonName = "Commander_Recruit",
        description = "Rated players of your faction who are online right now, one ladder per bracket — 2v2, 3v3 and 5v5 side by side, highest first — so you can find someone to queue with. Left-click a name to open your conversation with them (Commander Contacts), right-click to invite. Nothing in the game lists everyone who is online, so the board is filled from everywhere a player can only appear while they are on: /who results, the group finder's listings, chat, your guild and friends, and players you see. Sweep fills it properly: one /who per press, aimed by the Commander Ladder feed's list of your realm's rated players at where the most of them not yet seen should be — arena matches, their guilds, their class and race — with the bar saying what comes next; without the feed, every class at level 70, split by race where /who's 50-name limit cuts it short (the game only lets an addon send /who from a click or a key, so bind one: Key Bindings > AddOns > Commander Recruit > \"Sweep: Next /who\"). Ratings come from Commander Muster and the Commander Ladder feed. /crecruit opens it.",
        event = COMMANDER_RECRUIT_EVENTS.UPDATE,
        slash = { "/crecruit", "/recruit" },
        slashHandlers = {
            [""] = function() if CommanderRecruit_Toggle then CommanderRecruit_Toggle() end end,
            show = function() if CommanderRecruit_Toggle then CommanderRecruit_Toggle() end end,
            sweep = function() if CommanderRecruit_SweepStep then CommanderRecruit_SweepStep() end end,
            status = Report,
            clear = function()
                if CommanderRecruit.Clear then CommanderRecruit.Clear() end
                print("Commander Recruit: forgot everyone seen online")
            end,
            unwatch = UnwatchAll,
        },
    })

    panel:AddSection("Recruit")
    panel:AddCheckboxPair({
        label = "Enable Recruit",
        tooltip = "Master switch. Off, nothing is watched and the window stays shut.",
        get = function() return CommanderRecruitDB.EnableRecruit end,
        set = function(value) CommanderRecruitDB.EnableRecruit = value end,
    }, {
        label = "Button In Social Window",
        tooltip = "A Recruit icon in the Social window's title bar (O), left of its close button, on every tab. Click it to open or close Recruit.",
        get = function() return CommanderRecruitDB.SocialButton end,
        set = function(value) CommanderRecruitDB.SocialButton = value end,
        isEnabled = IsOn,
    })
    panel:AddSliderPair({
        label = "Online For",
        tooltip = "Someone counts as online for this long after they were last seen anywhere. A /who, your guild roster or your friends list taking them off says so at once.",
        min = 5, max = 60, step = 5,
        format = "%.0f min",
        get = function() return CommanderRecruitDB.FreshMinutes end,
        set = function(value) CommanderRecruitDB.FreshMinutes = value end,
        isEnabled = IsOn,
    }, nil)
    panel:AddDropdown({
        label = "Lowest Rating Shown",
        tooltip = "Hide anyone below this in a bracket. They still count as online, and still appear in a bracket where they clear it.",
        options = MIN_OPTIONS,
        width = 180,
        get = function() return CommanderRecruitDB.MinRating end,
        set = function(value) CommanderRecruitDB.MinRating = value end,
        isEnabled = IsOn,
    })
    panel:AddDropdown({
        label = "Sweep Depth",
        tooltip = "How far a sweep keeps asking. Each /who lists at most 50 players and about one in six level 70s is rated, so the last rated players cost the most presses. On a model of your realm's roster, a busy evening: Quick finds about 70% of the rated Horde online in ~50 presses (Alliance ~60% in ~22); Thorough about 80% in ~100 (Alliance ~70% in ~40); Deep about 90% in ~190 (Alliance ~80% in ~85). A sweep under way takes a change on its next press.",
        options = DEPTH_OPTIONS,
        width = 220,
        get = function() return CommanderRecruitDB.SweepDepth end,
        set = function(value) CommanderRecruitDB.SweepDepth = value end,
        isEnabled = IsOn,
    })

    panel:AddSection("Where Online Comes From",
        "Every one of these is somewhere a player can only show up while logged in, and all of them are your faction already (say and yell, which the other faction can reach you on, are checked by race).")
    panel:AddCheckboxPair({
        label = "/who",
        tooltip = "Every /who answer: the sweep's, and any /who you run yourself.",
        get = function() return CommanderRecruitDB.UseWho end,
        set = function(value) CommanderRecruitDB.UseWho = value end,
        isEnabled = IsOn,
    }, {
        label = "Group Finder",
        tooltip = "Every member of every listing the group finder shows you, whenever you search.",
        get = function() return CommanderRecruitDB.UseLFG end,
        set = function(value) CommanderRecruitDB.UseLFG = value end,
        isEnabled = IsOn,
    })
    panel:AddCheckboxPair({
        label = "Chat",
        tooltip = "Anyone who says something in a channel, your guild, a whisper, say or yell.",
        get = function() return CommanderRecruitDB.UseChat end,
        set = function(value) CommanderRecruitDB.UseChat = value end,
        isEnabled = IsOn,
    }, {
        label = "Guild",
        tooltip = "Your guildmates the roster says are online (and off again the moment it says they are not).",
        get = function() return CommanderRecruitDB.UseGuild end,
        set = function(value) CommanderRecruitDB.UseGuild = value end,
        isEnabled = IsOn,
    })
    panel:AddCheckboxPair({
        label = "Friends",
        tooltip = "Friends who are online.",
        get = function() return CommanderRecruitDB.UseFriends end,
        set = function(value) CommanderRecruitDB.UseFriends = value end,
        isEnabled = IsOn,
    }, {
        label = "Players You See",
        tooltip = "Friendly players under your cursor, on your target, or on a nameplate.",
        get = function() return CommanderRecruitDB.UseSeen end,
        set = function(value) CommanderRecruitDB.UseSeen = value end,
        isEnabled = IsOn,
    })

    panel:AddSection("Watch List",
        "Click the dot beside a name to watch that player: Recruit adds them to this character's friends list with the note \"Recruit watch\", and the server then tells you when they are on — no sweep needed. Someone already on your friends list is only marked. Stop watching and Recruit takes off the list only the friends it added itself; rewrite a watched friend's note and they are yours, never removed. Adding a friend needs a click, like /who; removing does not.")
    local watchRow = panel:AddRow(20, 6)
    local watchText = watchRow:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    watchText:SetPoint("TOPLEFT", watchRow, "TOPLEFT", 0, 0)
    watchText:SetPoint("RIGHT", watchRow, "RIGHT", 0, 0)
    watchText:SetJustifyH("LEFT")
    panel:AddRefresher(function()
        local n, on = 0, 0
        if CommanderRecruit.WatchCounts then n, on = CommanderRecruit.WatchCounts() end
        watchText:SetText(n > 0 and string.format("Watching %d on this character, %d online now.", n, on)
            or "Watching nobody on this character.")
    end)
    panel:AddButtonRow({
        {
            label = "Stop Watching All",
            width = 150,
            tooltip = "Stop watching everyone on this character. The friends Recruit added come off your friends list; friends you already had stay (also: /crecruit unwatch).",
            onClick = function()
                UnwatchAll()
                panel:Refresh()
            end,
        },
    })

    local row = panel:AddRow(20, 6)
    local status = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    status:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    status:SetJustifyH("LEFT")
    panel:AddRefresher(function()
        status:SetText(CommanderRecruit.Status and CommanderRecruit.Status() or "")
    end)

    panel:AddButtonRow({
        {
            label = "Open",
            width = 110,
            tooltip = "Open the online ladder (also: /crecruit).",
            onClick = function() if CommanderRecruit_Toggle then CommanderRecruit_Toggle() end end,
        },
        {
            label = "Forget All",
            width = 110,
            tooltip = "Forget everyone seen online so far (also: /crecruit clear).",
            onClick = function()
                if CommanderRecruit.Clear then CommanderRecruit.Clear() end
                panel:Refresh()
            end,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Recruit" then
        Commander.UI.ApplyDefaults(CommanderRecruitDB, DefaultSettings)
        -- The ladder probe's settings, gone with it (R17)
        for _, key in ipairs({ "ProbeMinRating", "ProbeBracket", "ProbeBatch", "ProbeBlocked", "QuietProbes" }) do
            CommanderRecruitDB[key] = nil
        end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
