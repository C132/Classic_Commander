-- Commander Contacts: defaults, the settings page, and the load lifecycle.
--
-- The conversations are in the same SavedVariables table as the settings,
-- and Commander.UI.ResetToDefaults iterates the DEFAULTS table rather than
-- the saved one. Restore Defaults therefore rewrites exactly the keys listed
-- in DefaultSettings below and cannot touch Conversations, ActiveGroup or
-- NextID. Do not "tidy" that by adding Conversations = {} to the defaults:
-- it would turn the Restore Defaults button into a delete-everything button.
-- The Notebook documents the same rule for the same reason.
--
-- The view state (which tab was open, which thread was selected) is kept
-- out of DefaultSettings too: it is where the user was, not what they chose.

CommanderContactsDB = _G.CommanderContactsDB or {}

COMMANDER_CONTACTS_EVENTS = {
    UPDATE = "COMMANDER_CONTACTS_UPDATE",   -- a setting changed
    MESSAGE = "COMMANDER_CONTACTS_MESSAGE", -- (key, entry) a line was filed
    ROSTER = "COMMANDER_CONTACTS_ROSTER",   -- friends, ignores or a group changed
}

local DefaultSettings = {
    EnableContacts = true,

    -- The window
    FrameStyle = "DARK",
    FrameScale = 1.0,
    OpenTab = "LAST",
    UnreadOnTitle = true,
    FriendsFrameButton = true,

    -- Battle.net friends in the Friends tab
    ShowBattleNet = true,
    FoldBattleNet = false,

    -- Suggested friends
    SuggestFriends = true,
    SuggestCount = 10,
    FoldSuggested = false,
    SuggestDays = 60,

    -- What gets kept
    LogWhispers = true,
    LogOutgoing = true,
    LogGroups = true,
    LogBattleNet = true,
    KeepDays = 90,
    MaxMessages = 400,

    -- How it reads
    ShowTimestamps = true,
    Clock24 = false,
    ClassColors = true,
    DayDividers = true,
    ActivitySort = "recent",
    ShowOffline = true,
    FriendSort = "status",
}

CommanderContacts_Defaults = DefaultSettings

local STYLE_OPTIONS = {
    { text = "Dark Panel", value = "DARK" },
    { text = "Window", value = "WINDOW" },
}

local TAB_OPTIONS = {
    { text = "Where I left it", value = "LAST" },
    { text = "Friends", value = "FRIENDS" },
    { text = "Activity", value = "ACTIVITY" },
}

local ACTIVITY_SORTS = {
    { text = "Most Recent", value = "recent" },
    { text = "Unread First", value = "unread" },
    { text = "Name", value = "name" },
}

local FRIEND_SORTS = {
    { text = "Online First", value = "status" },
    { text = "Name", value = "name" },
    { text = "Level", value = "level" },
}

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderContactsDB, DefaultSettings)
    Commander.Notify(COMMANDER_CONTACTS_EVENTS.UPDATE)
    print("Commander Contacts: settings restored to defaults. Your conversations were not touched.")
end

local function Call(name, ...)
    local fn = _G[name]
    if type(fn) == "function" then return fn(...) end
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Contacts",
        title = "Contacts",
        addonName = "Commander_Contacts",
        description = "Your friends list, your ignore list, and every whisper and party line you have received, kept. Three tabs across the top and a Slack-shaped window under them: the people or threads down the left, the one you picked on the right. Friends and Ignore are the game's own lists with more room and a notes box. Activity is the part the game never had: a thread per person who has ever whispered you, friend or stranger, and a thread per party you have been in, with what everyone said, and a box at the bottom to answer from.",
        event = COMMANDER_CONTACTS_EVENTS.UPDATE,
        slash = { "/ccontacts", "/cfriends" },
        slashHandlers = {
            [""] = function() Call("CommanderContacts_Toggle") end,
            friends = function() Call("CommanderContacts_ShowTab", "friends") end,
            ignore = function() Call("CommanderContacts_ShowTab", "ignore") end,
            activity = function() Call("CommanderContacts_ShowTab", "activity") end,
            stats = function() Call("CommanderContacts_PrintStats") end,
        },
    })

    panel:AddSection("Contacts")
    panel:AddCheckbox({
        label = "Enable Contacts",
        tooltip = "Master switch. Your conversations are kept either way — turning this off stops new lines being filed and puts the window away.",
        get = function() return CommanderContactsDB.EnableContacts end,
        set = function(value) CommanderContactsDB.EnableContacts = value end,
    })
    panel:AddDropdownPair({
        label = "Window Style",
        tooltip = "Dark Panel matches the rest of the suite's windows. Window keeps the game's own frame art.",
        options = STYLE_OPTIONS,
        get = function() return CommanderContactsDB.FrameStyle end,
        set = function(value) CommanderContactsDB.FrameStyle = value end,
        isEnabled = function() return CommanderContactsDB.EnableContacts end,
    }, {
        label = "Open On",
        tooltip = "Which tab the window opens to. Where I left it remembers the last one, thread and all.",
        options = TAB_OPTIONS,
        get = function() return CommanderContactsDB.OpenTab end,
        set = function(value) CommanderContactsDB.OpenTab = value end,
        isEnabled = function() return CommanderContactsDB.EnableContacts end,
    })
    panel:AddSlider({
        label = "Window Scale",
        tooltip = "Size of the whole window.",
        min = 0.7, max = 1.4, step = 0.05,
        format = "%.2f",
        get = function() return CommanderContactsDB.FrameScale end,
        set = function(value) CommanderContactsDB.FrameScale = value end,
        isEnabled = function() return CommanderContactsDB.EnableContacts end,
    })
    panel:AddCheckboxPair({
        label = "Unread Count In The Title",
        tooltip = "Print how many unread lines are waiting after the window's title, and on the Activity tab.",
        get = function() return CommanderContactsDB.UnreadOnTitle end,
        set = function(value) CommanderContactsDB.UnreadOnTitle = value end,
        isEnabled = function() return CommanderContactsDB.EnableContacts end,
    }, {
        label = "Button On The Friends Window",
        tooltip = "A Contacts button between the two at the bottom of the game's own Friends and Ignore tabs, opening this window on the matching tab.",
        get = function() return CommanderContactsDB.FriendsFrameButton end,
        set = function(value) CommanderContactsDB.FriendsFrameButton = value end,
        isEnabled = function() return CommanderContactsDB.EnableContacts end,
    })

    panel:AddSection("What Gets Kept",
        "Lines are filed as they arrive, whoever they are from. Nothing here deletes what is already kept.")
    panel:AddCheckboxPair({
        label = "Whispers",
        tooltip = "Every whisper you receive, filed under the person who sent it — friend or not.",
        get = function() return CommanderContactsDB.LogWhispers end,
        set = function(value) CommanderContactsDB.LogWhispers = value end,
        isEnabled = function() return CommanderContactsDB.EnableContacts end,
    }, {
        label = "Your Replies",
        tooltip = "The whispers you send, so a thread reads as a conversation rather than one side of one.",
        get = function() return CommanderContactsDB.LogOutgoing end,
        set = function(value) CommanderContactsDB.LogOutgoing = value end,
        isEnabled = function() return CommanderContactsDB.EnableContacts and CommanderContactsDB.LogWhispers end,
    })
    panel:AddCheckboxPair({
        label = "Party And Raid Chat",
        tooltip = "Party, raid, raid warning and battleground chat, one thread per group you were in, from the moment you joined to the moment you left.",
        get = function() return CommanderContactsDB.LogGroups end,
        set = function(value) CommanderContactsDB.LogGroups = value end,
        isEnabled = function() return CommanderContactsDB.EnableContacts end,
    }, {
        label = "Battle.net Whispers",
        tooltip = "Whispers from Battle.net friends, filed under the account rather than whichever character they were on.",
        get = function() return CommanderContactsDB.LogBattleNet end,
        set = function(value) CommanderContactsDB.LogBattleNet = value end,
        isEnabled = function() return CommanderContactsDB.EnableContacts end,
    })
    panel:AddSliderPair({
        label = "Keep Lines For",
        tooltip = "Lines older than this are dropped at login. Slide it to zero to keep everything forever.",
        min = 0, max = 365, step = 5,
        format = "%d days",
        get = function() return CommanderContactsDB.KeepDays end,
        set = function(value) CommanderContactsDB.KeepDays = value end,
        isEnabled = function() return CommanderContactsDB.EnableContacts end,
    }, {
        label = "Lines Per Thread",
        tooltip = "The most lines one thread keeps. The oldest go first.",
        min = 50, max = 2000, step = 50,
        format = "%d",
        get = function() return CommanderContactsDB.MaxMessages end,
        set = function(value)
            CommanderContactsDB.MaxMessages = value
            if CommanderContactsStore and CommanderContactsStore.SetMaxMessages then
                CommanderContactsStore.SetMaxMessages(value)
            end
        end,
        isEnabled = function() return CommanderContactsDB.EnableContacts end,
    })

    panel:AddSection("How It Reads")
    panel:AddCheckboxPair({
        label = "Timestamps",
        tooltip = "The time beside each run of lines.",
        get = function() return CommanderContactsDB.ShowTimestamps end,
        set = function(value) CommanderContactsDB.ShowTimestamps = value end,
        isEnabled = function() return CommanderContactsDB.EnableContacts end,
    }, {
        label = "24-Hour Clock",
        tooltip = "21:14 rather than 9:14 PM.",
        get = function() return CommanderContactsDB.Clock24 end,
        set = function(value) CommanderContactsDB.Clock24 = value end,
        isEnabled = function() return CommanderContactsDB.EnableContacts and CommanderContactsDB.ShowTimestamps end,
    })
    panel:AddCheckboxPair({
        label = "Class Colours",
        tooltip = "Colour names by class wherever the class is known: the friends list knows it while a friend is online, and a whisper carries it.",
        get = function() return CommanderContactsDB.ClassColors end,
        set = function(value) CommanderContactsDB.ClassColors = value end,
        isEnabled = function() return CommanderContactsDB.EnableContacts end,
    }, {
        label = "Day Dividers",
        tooltip = "A rule with the date on it where a thread crosses midnight.",
        get = function() return CommanderContactsDB.DayDividers end,
        set = function(value) CommanderContactsDB.DayDividers = value end,
        isEnabled = function() return CommanderContactsDB.EnableContacts end,
    })
    panel:AddDropdownPair({
        label = "Sort Activity By",
        tooltip = "The order of the Activity sidebar. Pinned threads stay on top whatever this says.",
        options = ACTIVITY_SORTS,
        get = function() return CommanderContactsDB.ActivitySort end,
        set = function(value) CommanderContactsDB.ActivitySort = value end,
        isEnabled = function() return CommanderContactsDB.EnableContacts end,
    }, {
        label = "Sort Friends By",
        tooltip = "The order of the Friends sidebar within its Online and Offline sections.",
        options = FRIEND_SORTS,
        get = function() return CommanderContactsDB.FriendSort end,
        set = function(value) CommanderContactsDB.FriendSort = value end,
        isEnabled = function() return CommanderContactsDB.EnableContacts end,
    })
    panel:AddCheckbox({
        label = "Show Offline Friends",
        tooltip = "List friends who are not online under an Offline heading. Off shows only who is here now.",
        get = function() return CommanderContactsDB.ShowOffline end,
        set = function(value) CommanderContactsDB.ShowOffline = value end,
        isEnabled = function() return CommanderContactsDB.EnableContacts end,
    })
    panel:AddCheckboxPair({
        label = "Show Battle.net Friends",
        tooltip = "List Battle.net friends in their own section under the character friends. Off leaves them to the game's own window.",
        get = function() return CommanderContactsDB.ShowBattleNet end,
        set = function(value) CommanderContactsDB.ShowBattleNet = value end,
        isEnabled = function() return CommanderContactsDB.EnableContacts end,
    }, {
        label = "Fold Battle.net Away",
        tooltip = "Keep the Battle.net section folded to its heading. Clicking the heading in the window folds and unfolds it too; this is what it goes back to.",
        get = function() return CommanderContactsDB.FoldBattleNet end,
        set = function(value) CommanderContactsDB.FoldBattleNet = value end,
        isEnabled = function() return CommanderContactsDB.EnableContacts and CommanderContactsDB.ShowBattleNet end,
    })

    panel:AddSection("Suggested Friends",
        "Players from your realm who stood out in your battlegrounds, or who wear an arena title, listed under your friends with a line saying why.")
    panel:AddCheckboxPair({
        label = "Suggest Friends",
        tooltip = "Watch the scoreboard at the end of every battleground and the titles of the people in it. Nothing is asked of anyone; it only reads what the game already shows.",
        get = function() return CommanderContactsDB.SuggestFriends end,
        set = function(value) CommanderContactsDB.SuggestFriends = value end,
        isEnabled = function() return CommanderContactsDB.EnableContacts end,
    }, {
        label = "Fold Suggestions Away",
        tooltip = "Keep the Suggested section folded to its heading. Clicking the heading folds and unfolds it too.",
        get = function() return CommanderContactsDB.FoldSuggested end,
        set = function(value) CommanderContactsDB.FoldSuggested = value end,
        isEnabled = function() return CommanderContactsDB.EnableContacts and CommanderContactsDB.SuggestFriends end,
    })
    panel:AddSliderPair({
        label = "Suggestions To Show",
        tooltip = "How many names the Suggested section lists, best first.",
        min = 3, max = 25, step = 1,
        format = "%d",
        get = function() return CommanderContactsDB.SuggestCount end,
        set = function(value) CommanderContactsDB.SuggestCount = value end,
        isEnabled = function() return CommanderContactsDB.EnableContacts and CommanderContactsDB.SuggestFriends end,
    }, {
        label = "Remember Performers For",
        tooltip = "Someone not seen in a battleground for this long is forgotten at login. Zero remembers everyone.",
        min = 0, max = 365, step = 5,
        format = "%d days",
        get = function() return CommanderContactsDB.SuggestDays end,
        set = function(value) CommanderContactsDB.SuggestDays = value end,
        isEnabled = function() return CommanderContactsDB.EnableContacts and CommanderContactsDB.SuggestFriends end,
    })

    panel:AddButtonRow({
        {
            label = "Open Contacts",
            width = 130,
            tooltip = "Open the window (also: /ccontacts).",
            onClick = function() Call("CommanderContacts_Show") end,
        },
        {
            label = "What's In There?",
            width = 140,
            tooltip = "Print how many people, groups and lines are kept (also: /ccontacts stats).",
            onClick = function() Call("CommanderContacts_PrintStats") end,
        },
        {
            label = "Forget Suggestions",
            width = 140,
            tooltip = "Drop every performer record. Names you marked Not Interested stay dismissed.",
            onClick = function() Call("CommanderContacts_ForgetSuggestions") end,
        },
    })

    panel:Finalize({
        onDefaults = Reset,
        defaultsTooltip = "Reset every option on this page. Your conversations are not touched — this button cannot delete a line of chat.",
    })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Contacts" then
        Commander.UI.ApplyDefaults(CommanderContactsDB, DefaultSettings)
        -- The store normalises whatever came off disk before anything reads
        -- it, so every later caller may assume the invariants hold.
        CommanderContactsStore.SetMaxMessages(CommanderContactsDB.MaxMessages)
        CommanderContactsStore.Attach(CommanderContactsDB)
        CommanderContactsScout.Attach(CommanderContactsDB)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
        CommanderContactsScout.Prune(CommanderContactsDB.SuggestDays)
        local lines, threads = CommanderContactsStore.Prune(CommanderContactsDB.KeepDays)
        if lines > 0 or threads > 0 then
            print(string.format("Commander Contacts: dropped %d old line%s%s.",
                lines, lines == 1 and "" or "s",
                threads > 0 and string.format(" and %d empty thread%s", threads, threads == 1 and "" or "s") or ""))
        end
    end
end

frame:SetScript("OnEvent", OnEvent)
