CommanderSpellbookDB = _G.CommanderSpellbookDB or {}
-- Per character: the trainer spells this character told the Training view to
-- stop listing (an alt's choices are not a main's), and the spell the window
-- was last briefing. Restore Defaults never touches it.
CommanderSpellbookChar = _G.CommanderSpellbookChar or {}

COMMANDER_SPELLBOOK_EVENTS = {
    UPDATE = "COMMANDER_SPELLBOOK_UPDATE"
}

local DefaultSettings = {
    EnableSpellbook = true,
    -- Open this window wherever the game would open Blizzard's: the P key
    -- (and Shift-P for the pet), the micro button, anything that shows the
    -- stock book. Off hands Blizzard's book straight back, no reload.
    TakeOverSpellbook = true,
    -- How the Spells view files the book: "ROLE" (Healing, Damage, Crowd
    -- Control...) or "TREE" (the tabs of the stock book: General and the
    -- three trees, as foldouts)
    GroupBy = "ROLE",
    -- Where the player left the toolbar: "BOOK" (Spells), "TRAIN"
    -- (Training) or "CHECK" (Rank Check)
    Filter = "BOOK",
    ShowPassives = true,
    -- List the spells you have not learned yet among the ones you have, dim
    -- and marked with the level they come at. Off, they show only when a
    -- search names them (and always on the Training view).
    ShowUnlearned = false,
    -- The marks on a spell's row: a green +N when a higher rank can be
    -- trained now, an amber ! when a bar or macro still casts an old rank
    RowBadges = true,
    -- How many levels ahead the Training view calls "coming up"
    SoonLevels = 2,
    -- Folded groups, keyed "<view>:<group>" (ROLE:PASSIVE, TREE:tab2,
    -- TRAIN:LATER). Display state the player authored: Reset keeps it.
    Collapsed = {},
    FrameStyle = "STONE",
    FrameScale = 1.0,
    FramePos = false,
}

local STYLES = {
    { text = "Dark Stone (Default)", value = "STONE" },
    { text = "Parchment", value = "PARCHMENT" },
    { text = "Window", value = "WINDOW" },
    { text = "Dark", value = "DARK" },
}

local GROUPINGS = {
    { text = "By role (Default)", value = "ROLE" },
    { text = "By talent tree", value = "TREE" },
}

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

-- The per-character table, made whole. Safe at any time: anything that
-- writes to it calls this first rather than trusting the load order.
local function EnsureCharDB()
    if type(CommanderSpellbookChar) ~= "table" then CommanderSpellbookChar = {} end
    if type(CommanderSpellbookChar.Ignored) ~= "table" then CommanderSpellbookChar.Ignored = {} end
    return CommanderSpellbookChar
end

CommanderSpellbook = CommanderSpellbook or {}
CommanderSpellbook.EnsureCharDB = EnsureCharDB

local function Reset()
    local collapsed = CommanderSpellbookDB.Collapsed
    Commander.UI.ResetToDefaults(CommanderSpellbookDB, DefaultSettings)
    if type(collapsed) == "table" then CommanderSpellbookDB.Collapsed = collapsed end
    Commander.Notify(COMMANDER_SPELLBOOK_EVENTS.UPDATE)
    print("Commander Spellbook: settings restored to defaults")
end

local function ClearIgnored()
    local charDB = EnsureCharDB()
    local count = 0
    for _ in pairs(charDB.Ignored) do count = count + 1 end
    charDB.Ignored = {}
    Commander.Notify(COMMANDER_SPELLBOOK_EVENTS.UPDATE)
    print(string.format("Commander Spellbook: %d ignored spell%s back on this character's Training list.",
        count, count == 1 and "" or "s"))
end

local function Open(filter)
    if CommanderSpellbook_Open then CommanderSpellbook_Open(filter) end
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Spellbook",
        title = "Spellbook",
        addonName = "Commander_Spellbook",
        description = "The spellbook as one window: every spell you know in one searchable list, filed into foldouts by what it does (or by talent tree), one row per spell however many ranks it has — and the ranks laid out beside it, the ones you know and the ones still to train. A Training view lists what your class trainer will teach you now, what comes in the next levels and what it costs; a Rank Check view lists the bars and macros still casting an old rank, with a button to update them.",
        event = COMMANDER_SPELLBOOK_EVENTS.UPDATE,
        slash = { "/csb", "/cspellbook" },
        slashHandlers = {
            [""] = function() if CommanderSpellbook_Toggle then CommanderSpellbook_Toggle() end end,
            train = function() Open("TRAIN") end,
            training = function() Open("TRAIN") end,
            check = function() Open("CHECK") end,
            ranks = function() Open("CHECK") end,
        },
    })

    panel:AddSection("The Book")
    panel:AddCheckboxPair({
        label = "Enable Spellbook",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderSpellbookDB.EnableSpellbook end,
        set = function(value) CommanderSpellbookDB.EnableSpellbook = value end,
    }, {
        label = "Replace the Stock Spellbook",
        tooltip = "Open this window wherever the game would have opened Blizzard's — the spellbook and pet book keys, the micro button, another addon asking. Off, both are available and this one answers to /csb and its own key binding. In combat a micro-button click still opens Blizzard's book: it cannot be put away mid-fight.",
        get = function() return CommanderSpellbookDB.TakeOverSpellbook end,
        set = function(value)
            CommanderSpellbookDB.TakeOverSpellbook = value
            if CommanderSpellbook.ApplyBindings then CommanderSpellbook.ApplyBindings() end
        end,
        isEnabled = function() return CommanderSpellbookDB.EnableSpellbook end,
    })
    panel:AddDropdown({
        label = "Group Spells",
        tooltip = "By role files every spell under what it does: Healing, Damage, Crowd Control, Defensive, Buffs, Forms, Utility, Travel, Pet, then Racial, Professions and General. By talent tree keeps the stock book's tabs, as foldouts. The dropdown on the window's toolbar switches it too.",
        options = GROUPINGS,
        width = 160,
        get = function() return CommanderSpellbookDB.GroupBy end,
        set = function(value) CommanderSpellbookDB.GroupBy = value end,
        isEnabled = function() return CommanderSpellbookDB.EnableSpellbook end,
    })
    panel:AddDropdown({
        label = "Window Style",
        tooltip = "Dark Stone is the dialog border on the dark stone of the game's dialog boxes; Parchment is the stock book's paper; Window is the suite's inset panel; Dark is the flat HUD panel.",
        options = STYLES,
        width = 160,
        get = function() return CommanderSpellbookDB.FrameStyle end,
        set = function(value)
            CommanderSpellbookDB.FrameStyle = value
            if CommanderSpellbook.ApplyFraming then CommanderSpellbook.ApplyFraming(true) end
        end,
        isEnabled = function() return CommanderSpellbookDB.EnableSpellbook end,
    })
    panel:AddSlider({
        label = "Window Scale",
        tooltip = "Size of the whole window. The grip in its bottom right corner drives this too.",
        min = 0.6, max = 1.6, step = 0.05,
        format = "%.2fx",
        get = function() return CommanderSpellbookDB.FrameScale end,
        set = function(value)
            CommanderSpellbookDB.FrameScale = value
            if CommanderSpellbook.ApplyPosition then CommanderSpellbook.ApplyPosition() end
        end,
        isEnabled = function() return CommanderSpellbookDB.EnableSpellbook end,
    })

    panel:AddSection("The List")
    panel:AddCheckboxPair({
        label = "Show Passives",
        tooltip = "List passive spells (in their own Passives foldout when grouping by role). They cannot be cast or put on a bar; off keeps the list to what you press.",
        get = function() return CommanderSpellbookDB.ShowPassives end,
        set = function(value) CommanderSpellbookDB.ShowPassives = value end,
        isEnabled = function() return CommanderSpellbookDB.EnableSpellbook end,
    }, {
        label = "Show Unlearned Spells",
        tooltip = "List the class spells you have not learned yet among the ones you have, dim, with the level they come at. Off, they appear only when a search names them, and always on the Training view.",
        get = function() return CommanderSpellbookDB.ShowUnlearned end,
        set = function(value) CommanderSpellbookDB.ShowUnlearned = value end,
        isEnabled = function() return CommanderSpellbookDB.EnableSpellbook end,
    })
    panel:AddCheckboxPair({
        label = "Rank Badges on Rows",
        tooltip = "Mark a spell's row with a green +N when a trainer can teach you a higher rank now, and an amber ! when a bar or macro still casts an older rank than you know (Commander Rank Check).",
        get = function() return CommanderSpellbookDB.RowBadges end,
        set = function(value) CommanderSpellbookDB.RowBadges = value end,
        isEnabled = function() return CommanderSpellbookDB.EnableSpellbook end,
    })

    panel:AddSection("Training")
    panel:AddSlider({
        label = "Coming Up Within",
        tooltip = "How many levels ahead the Training view lists under Coming up; anything later folds into Later.",
        min = 1, max = 10, step = 1,
        format = function(value) return string.format("%d level%s", value, value == 1 and "" or "s") end,
        get = function() return CommanderSpellbookDB.SoonLevels end,
        set = function(value) CommanderSpellbookDB.SoonLevels = value end,
        isEnabled = function() return CommanderSpellbookDB.EnableSpellbook end,
    })
    panel:AddButtonRow({
        {
            label = "Open Training",
            width = 120,
            tooltip = "Open the window on the Training view (also: /csb train).",
            onClick = function() Open("TRAIN") end,
        },
        {
            label = "Clear Ignored",
            width = 120,
            tooltip = "Put every spell this character told the Training view to ignore back on the list.",
            onClick = ClearIgnored,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Spellbook" then
        Commander.UI.ApplyDefaults(CommanderSpellbookDB, DefaultSettings)
        if type(CommanderSpellbookDB.Collapsed) ~= "table" then
            CommanderSpellbookDB.Collapsed = {}
        end
        EnsureCharDB()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
