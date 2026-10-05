CommanderDiminishDB = _G.CommanderDiminishDB or {}

COMMANDER_DIMINISH_EVENTS = {
    UPDATE = "COMMANDER_DIMINISH_UPDATE"
}

local DATA = CommanderDiminish_Data

-- Defaults are the opinionated part of this file, and the opinion is that a DR
-- tracker's job is to answer one question -- "will the next one land whole" --
-- fast enough to be read mid-fight. So: the character's own ladders drawn in
-- full and greyed until they open (which is a strip of three or four icons,
-- not sixteen, precisely because it is tailored), a reset clock on each, and
-- everything that would turn it into a second combat log left off.
local DefaultSettings = {
    Enable = true,

    -- Where it draws. Arena and battleground on, the world off: outdoors this
    -- is a strip that flickers on every mob you fight, and world PvP is not
    -- what a DR tracker is for. Turn it on if you duel.
    ShowInArena = true,
    ShowInBattleground = true,
    ShowInWorld = false,
    CombatOnly = false,

    -- Whose ladders. Target and focus are the battleground answer; the arena
    -- rows are the arena one. Self is on because the ladder being run on YOU
    -- is the one you cannot see any other way -- there is no enemy nameplate
    -- that tells you your own fear DR.
    ShowSelf = true,
    ShowTarget = true,
    ShowFocus = true,
    ShowArena = true,
    ShowParty = true,            -- the people in your party: what is being run on THEM
    ShowRecent = false,          -- everyone you have CC'd lately; a BG mode
    RecentMax = 3,

    -- Which categories, on an ENEMY. MINE is the tailoring: the ladders this
    -- character can actually open, read out of the spellbook rather than out
    -- of a table of classes, so it follows a respec without being told.
    -- Categories being run on someone are always drawn whatever this says --
    -- see the note in the Categories section.
    Scope = "MINE",              -- MINE | ALL | CUSTOM
    ShowFull = true,             -- draw the profile greyed before anything opens

    -- Where a strip sits. EMBEDDED puts each one on the frame of the person
    -- it is about -- an ally's Commander Party Frames row, your target's and
    -- focus's unit frames -- and draws nothing for an arena enemy, whose
    -- ladders Commander Arena Frames already carries on their row. WINDOW is
    -- the board this module was born as: one floating frame, a named strip
    -- per person.
    Placement = "EMBEDDED",      -- EMBEDDED | WINDOW
    EmbedIconSize = 20,          -- an embedded strip's icons, in pixels
    EmbedSide = "ABOVE",         -- which side of a UNIT frame: ABOVE | BELOW | LEFT | RIGHT
    EmbedOffsetX = 0,            -- nudge for strips on a UNIT frame (target, focus, ...)
    EmbedOffsetY = 0,

    -- Layout (the window's)
    Grow = "DOWN",               -- DOWN | UP
    IconSize = 30,
    IconSpacing = 3,
    RowSpacing = 6,
    ShowName = true,
    NameMaxChars = 10,
    NameSize = 11,

    -- What is written on a cell
    ShowBracket = true,          -- the 1/2, 1/4, X badge
    ShowTimer = true,            -- seconds until the category resets
    ShowSwipe = true,            -- the clock sweep under the icon
    TimerSize = 12,
    DesaturateFull = true,       -- grey a category nothing has opened yet
    HeldGlow = true,             -- mark a category that is up RIGHT NOW
    -- CATEGORY: the ladder's own picture (Hammer of Justice for stun,
    -- Polymorph for poly...). SPELL: whichever spell last opened it.
    IconSource = "CATEGORY",
}

for key, value in pairs(Commander.UI.HudChromeDefaults("Hud", "DARK")) do
    DefaultSettings[key] = value
end

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderDiminishDB, DefaultSettings)
    Commander.Notify(COMMANDER_DIMINISH_EVENTS.UPDATE)
    print("Commander Diminish: settings restored to defaults")
end

local function Enabled()
    return CommanderDiminishDB.Enable
end

-- ---------------------------------------------------------------------------
-- Per-category overrides. Only what the user has CHANGED is stored, so the
-- saved variables never carry a row for a category left alone -- which means a
-- later change to a default actually reaches everyone who never touched it.
-- ---------------------------------------------------------------------------

local function CustomGet(key)
    local store = CommanderDiminishDB.CustomCategories
    return (store and store[key]) and true or false
end

local function CustomSet(key, value)
    local store = CommanderDiminishDB.CustomCategories
    if not store then
        store = {}
        CommanderDiminishDB.CustomCategories = store
    end
    store[key] = value and true or nil
end

-- Read by the tracker as well as by this page, so the two can never disagree
-- about which categories are live.
function CommanderDiminish_CustomCategory(key)
    return CustomGet(key)
end

-- ---------------------------------------------------------------------------
-- A toggle GRID. A column of sixteen checkboxes is unreadable; cells laid out
-- in rows, lit when tracked and ghosted when not, each with the category's own
-- note on its tooltip, is not.
-- ---------------------------------------------------------------------------

local CELL_W, CELL_H, CELL_GAP = 116, 20, 4

local function PaintCell(cell)
    local on = cell.isOn()
    cell.bg:SetVertexColor(on and 0.22 or 0.10, on and 0.30 or 0.10, on and 0.24 or 0.10, 0.9)
    cell.label:SetTextColor(on and 1 or 0.45, on and 1 or 0.45, on and 1 or 0.45)
end

local function NewCell(panel, row, index, perRow, spec)
    local cell = CreateFrame("Button", nil, row)
    cell:SetSize(CELL_W, CELL_H)
    local column = (index - 1) % perRow
    local line = math.floor((index - 1) / perRow)
    cell:SetPoint("TOPLEFT", row, "TOPLEFT",
        2 + column * (CELL_W + CELL_GAP), -line * (CELL_H + CELL_GAP))

    cell.bg = cell:CreateTexture(nil, "BACKGROUND")
    cell.bg:SetAllPoints()
    cell.bg:SetTexture("Interface\\Buttons\\WHITE8X8")

    local tint = DATA.CAT_TINT[spec.key]
    if tint then
        cell.swatch = cell:CreateTexture(nil, "ARTWORK")
        cell.swatch:SetTexture("Interface\\Buttons\\WHITE8X8")
        cell.swatch:SetPoint("LEFT", cell, "LEFT", 3, 0)
        cell.swatch:SetSize(3, CELL_H - 6)
        cell.swatch:SetVertexColor(tint[1], tint[2], tint[3])
    end

    cell.label = cell:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cell.label:SetPoint("LEFT", cell, "LEFT", 10, 0)
    cell.label:SetPoint("RIGHT", cell, "RIGHT", -4, 0)
    cell.label:SetJustifyH("LEFT")
    cell.label:SetText(spec.label)

    cell.isOn = spec.isOn
    cell:SetScript("OnClick", function(self)
        spec.toggle()
        PaintCell(self)
        Commander.Notify(COMMANDER_DIMINISH_EVENTS.UPDATE)
    end)
    Commander.UI.AttachTooltip(cell, spec.label, spec.tooltip)
    panel:AddRefresher(function() PaintCell(cell) end)
    return cell
end

local function AddGrid(panel, specs, perRow)
    local lines = math.ceil(#specs / perRow)
    local row = panel:AddRow(lines * (CELL_H + CELL_GAP) + 4, 6)
    for index, spec in ipairs(specs) do
        NewCell(panel, row, index, perRow, spec)
    end
end

-- ---------------------------------------------------------------------------
-- Sections
-- ---------------------------------------------------------------------------

local function AddWhereSection(panel)
    panel:AddSection("Where It Draws",
        "Arena and battlegrounds, which is where diminishing returns decide anything. The world is off by default: outdoors the strip would flicker on every mob you pull, and a DR ladder against a boar is not a thing anyone needs. Turn it on if you duel or roam.")

    panel:AddCheckboxPair({
        label = "Arenas",
        tooltip = "Draw in arena. The arena rows below give you a strip per enemy, keyed to the arena unit tokens.",
        get = function() return CommanderDiminishDB.ShowInArena end,
        set = function(value) CommanderDiminishDB.ShowInArena = value end,
        isEnabled = Enabled,
    }, {
        label = "Battlegrounds",
        tooltip = "Draw in battlegrounds. There are no arena unit tokens here, so the tracker follows your target and focus instead -- and, if you turn it on below, everyone you have CC'd recently.",
        get = function() return CommanderDiminishDB.ShowInBattleground end,
        set = function(value) CommanderDiminishDB.ShowInBattleground = value end,
        isEnabled = Enabled,
    })

    panel:AddCheckboxPair({
        label = "Out in the world",
        tooltip = "Draw everywhere else -- duels, world PvP, anywhere at all. Off by default because a strip that reacts to every mob you fight stops being glanceable.",
        get = function() return CommanderDiminishDB.ShowInWorld end,
        set = function(value) CommanderDiminishDB.ShowInWorld = value end,
        isEnabled = Enabled,
    }, {
        label = "Only in combat",
        tooltip = "Hide the whole tracker out of combat. The ladders keep running underneath either way -- this hides the display, it does not stop the tracking, so a strip that comes back mid-fight is still correct.",
        get = function() return CommanderDiminishDB.CombatOnly end,
        set = function(value) CommanderDiminishDB.CombatOnly = value end,
        isEnabled = Enabled,
    })
end

local function AddWhoSection(panel)
    panel:AddSection("Whose Ladders",
        "One strip per person. Target and focus are the battleground answer -- there are no enemy unit tokens there, so the two units you have chosen are the two the client will talk about. Your own row is on because the ladder being run on YOU is the one nothing else can show you: no enemy nameplate says how many fears you have eaten.")

    panel:AddCheckboxPair({
        label = "Yourself",
        tooltip = "What is being done to you. This row ignores the category filter entirely and shows anything that has been opened on you -- the filter answers 'what can I cast', which is the wrong question about incoming CC.",
        get = function() return CommanderDiminishDB.ShowSelf end,
        set = function(value) CommanderDiminishDB.ShowSelf = value end,
        isEnabled = Enabled,
    }, {
        label = "Your target",
        tooltip = "The strip for whoever you have targeted. On a hostile target it shows the ladders YOU can open; on a friendly one it flips to what is being done to them, which is what a healer wants from a partner's row.",
        get = function() return CommanderDiminishDB.ShowTarget end,
        set = function(value) CommanderDiminishDB.ShowTarget = value end,
        isEnabled = Enabled,
    })

    panel:AddCheckboxPair({
        label = "Your focus",
        tooltip = "The same strip for your focus. In a battleground this is the one that matters: focus the healer, keep their fear ladder on screen while you fight somebody else.",
        get = function() return CommanderDiminishDB.ShowFocus end,
        set = function(value) CommanderDiminishDB.ShowFocus = value end,
        isEnabled = Enabled,
    }, {
        label = "Arena opponents",
        tooltip = "A strip per arena enemy, from the arena unit tokens. Arena only -- those tokens do not exist anywhere else, which is exactly why the target and focus rows are here.",
        get = function() return CommanderDiminishDB.ShowArena end,
        set = function(value) CommanderDiminishDB.ShowArena = value end,
        isEnabled = Enabled,
    })

    panel:AddCheckbox({
        label = "Your party",
        tooltip = "What is being run on the people you are grouped with. Your healer's fear ladder is the one a team plays around, and nothing else on screen shows it. Like your own row, these ignore the category filter and draw only what has actually been opened on them.",
        get = function() return CommanderDiminishDB.ShowParty end,
        set = function(value) CommanderDiminishDB.ShowParty = value end,
        isEnabled = Enabled,
    })

    panel:AddCheckbox({
        label = "Anyone you have CC'd recently",
        tooltip = "The battleground problem, solved the only way it can be: you sap someone, swap target, and their ladder is still the thing you need. This adds a strip for whoever you have most recently landed control on, whether or not they are targeted -- and drops them again once every ladder on them has reset.",
        get = function() return CommanderDiminishDB.ShowRecent end,
        set = function(value) CommanderDiminishDB.ShowRecent = value end,
        isEnabled = Enabled,
    })

    panel:AddSlider({
        label = "How many recent",
        tooltip = "The cap on those extra strips. Three is about as many as anyone reads mid-fight.",
        min = 1, max = 8, step = 1, format = "%d",
        get = function() return CommanderDiminishDB.RecentMax end,
        set = function(value) CommanderDiminishDB.RecentMax = value end,
        isEnabled = function() return Enabled() and CommanderDiminishDB.ShowRecent end,
    })
end

local function AddCategorySection(panel)
    panel:AddSection("Which Ladders",
        "The tailoring. TBC has sixteen diminishing-returns categories and no character can open more than a handful of them, so the default is the handful YOURS can -- read out of your spellbook rather than out of a table of classes. That is what makes it right across a respec (an arcane mage has no Dragon's Breath row; talent into fire and one appears), across a rank you have not trained yet, and across a pet swap, without anyone maintaining a list.\n\nOne rule sits above this setting: a category that has actually been opened on someone is ALWAYS drawn, filter or no filter. The filter answers 'what can I cast'. A fear ladder running on your healer is not about what you can cast, and hiding it would be hiding the only reason to look.")

    panel:AddDropdown({
        label = "Categories shown on an enemy",
        tooltip = "MINE is the tailoring -- the ladders your spellbook can open, recalculated whenever your spells change. ALL shows the full sixteen, which is honest and unreadable. CUSTOM is MINE plus whatever you tick below, which is what you want if you play with a partner whose CC you want to keep track of.",
        options = {
            { text = "Mine (auto)", value = "MINE" },
            { text = "All sixteen", value = "ALL" },
            { text = "Mine + chosen", value = "CUSTOM" },
        },
        get = function() return CommanderDiminishDB.Scope end,
        set = function(value) CommanderDiminishDB.Scope = value end,
        isEnabled = Enabled,
    })

    panel:AddCheckbox({
        label = "Draw the whole set, greyed, before anything opens",
        tooltip = "On: your ladders sit there in grey and light up as they open, so the strip never changes shape and you can read it by position. This is only readable BECAUSE the set is tailored -- three or four icons, not sixteen. Off: a category appears the moment it is opened and vanishes when it resets, which is quieter and gives you nothing to glance at between fights.",
        get = function() return CommanderDiminishDB.ShowFull end,
        set = function(value) CommanderDiminishDB.ShowFull = value end,
        isEnabled = Enabled,
    })

    panel:AddSection("Add To Your Set",
        "Only read when the setting above is on 'Mine + chosen'. Each of these joins your own ladders rather than replacing them.")

    local specs = {}
    for _, group in ipairs(DATA.DR_GROUPS or {}) do
        specs[#specs + 1] = {
            key = group.key,
            label = group.label,
            tooltip = group.note,
            isOn = function() return CustomGet(group.key) end,
            toggle = function() CustomSet(group.key, not CustomGet(group.key)) end,
        }
    end
    AddGrid(panel, specs, 4)
end

local function AddLayoutSection(panel)
    panel:AddSection("Where It Sits",
        "On The Frames puts each strip on the frame of the person it is about, so there is nothing floating on its own: an ally's ladders sit beside their row on Commander Party Frames (yours included), and your target's and focus's sit on their unit frames. An arena enemy's are not drawn here at all -- Commander Arena Frames already carries them on that enemy's row. A person with no frame on screen gets no strip. Its Own Window is the original board: one movable frame with a named strip per person.")

    panel:AddDropdown({
        label = "Placement",
        tooltip = "On The Frames: each strip is attached to the frame of the person it describes, and shows, hides, moves and scales with it. Its Own Window: one floating board, placed with Unlock & Move.\n\nRecently-CC'd strips have no frame to sit on, so they only draw in the window.",
        options = {
            { text = "On the frames", value = "EMBEDDED" },
            { text = "Its own window", value = "WINDOW" },
        },
        width = 180,
        get = function() return CommanderDiminishDB.Placement end,
        set = function(value) CommanderDiminishDB.Placement = value end,
        isEnabled = Enabled,
    })

    panel:AddSlider({
        label = "Icon size on a frame",
        tooltip = "How big an embedded strip's icons are. A party row is 22 pixels tall, so 20 sits inside it.",
        min = 12, max = 36, step = 1, format = "%dpx",
        get = function() return CommanderDiminishDB.EmbedIconSize end,
        set = function(value) CommanderDiminishDB.EmbedIconSize = value end,
        isEnabled = function() return Enabled() and CommanderDiminishDB.Placement == "EMBEDDED" end,
    })

    panel:AddDropdown({
        label = "Side of a unit frame",
        tooltip = "Where the strip sits on your target's, your focus's and your own unit frame. Above is the clear band over the name bar. Below hangs it from the frame's bottom edge, under the bars -- which is also where the game puts the unit's buffs and debuffs, so use the nudge sliders under this to clear them. Left and Right stand it beside the frame.\n\nStrips on Commander Party Frames rows are placed by that board and are not moved by this.",
        options = {
            { text = "Above", value = "ABOVE" },
            { text = "Below", value = "BELOW" },
            { text = "Left", value = "LEFT" },
            { text = "Right", value = "RIGHT" },
        },
        width = 180,
        get = function() return CommanderDiminishDB.EmbedSide end,
        set = function(value) CommanderDiminishDB.EmbedSide = value end,
        isEnabled = function() return Enabled() and CommanderDiminishDB.Placement == "EMBEDDED" end,
    })

    panel:AddSliderPair({
        label = "Unit frame nudge, across",
        tooltip = "Moves the strips that sit on a unit frame -- your target, your focus, yourself and Blizzard's party frames -- left or right from where they are put by default (just above the name bar). Strips on Commander Party Frames rows are placed by that board and do not move with this.",
        min = -120, max = 120, step = 1, format = "%d",
        get = function() return CommanderDiminishDB.EmbedOffsetX end,
        set = function(value) CommanderDiminishDB.EmbedOffsetX = value end,
        isEnabled = function() return Enabled() and CommanderDiminishDB.Placement == "EMBEDDED" end,
    }, {
        label = "Unit frame nudge, up",
        tooltip = "The same, up or down.",
        min = -120, max = 120, step = 1, format = "%d",
        get = function() return CommanderDiminishDB.EmbedOffsetY end,
        set = function(value) CommanderDiminishDB.EmbedOffsetY = value end,
        isEnabled = function() return Enabled() and CommanderDiminishDB.Placement == "EMBEDDED" end,
    })

    panel:AddSection("Layout",
        "A HUD, not a window. The strip is meant to be read at the edge of your attention while you are doing something else, which is an argument for fewer, larger icons rather than more.")

    panel:AddDropdownPair({
        label = "Grow",
        tooltip = "Which way extra strips stack from the anchor.",
        options = { { text = "Down", value = "DOWN" }, { text = "Up", value = "UP" } },
        get = function() return CommanderDiminishDB.Grow end,
        set = function(value) CommanderDiminishDB.Grow = value end,
        isEnabled = Enabled,
    }, nil)

    panel:AddSliderPair({
        label = "Icon size",
        tooltip = "Bigger than you think. This is read peripherally.",
        min = 16, max = 56, step = 1, format = "%d",
        get = function() return CommanderDiminishDB.IconSize end,
        set = function(value) CommanderDiminishDB.IconSize = value end,
        isEnabled = Enabled,
    }, {
        label = "Between icons",
        tooltip = "Gap between the categories in one strip.",
        min = 0, max = 12, step = 1, format = "%d",
        get = function() return CommanderDiminishDB.IconSpacing end,
        set = function(value) CommanderDiminishDB.IconSpacing = value end,
        isEnabled = Enabled,
    })

    panel:AddSliderPair({
        label = "Between strips",
        tooltip = "Gap between one person's strip and the next.",
        min = 0, max = 24, step = 1, format = "%d",
        get = function() return CommanderDiminishDB.RowSpacing end,
        set = function(value) CommanderDiminishDB.RowSpacing = value end,
        isEnabled = Enabled,
    }, {
        label = "Name size",
        tooltip = "Point size of the label over each strip.",
        min = 8, max = 18, step = 1, format = "%d",
        get = function() return CommanderDiminishDB.NameSize end,
        set = function(value) CommanderDiminishDB.NameSize = value end,
        isEnabled = function() return Enabled() and CommanderDiminishDB.ShowName end,
    })

    panel:AddCheckboxPair({
        label = "Label each strip",
        tooltip = "Who the strip belongs to -- YOU, the target, the focus, an arena seat, or a name. With more than one strip on screen this is the difference between reading it and guessing.",
        get = function() return CommanderDiminishDB.ShowName end,
        set = function(value) CommanderDiminishDB.ShowName = value end,
        isEnabled = Enabled,
    }, nil)

    panel:AddSlider({
        label = "Name length",
        tooltip = "Names are cut to this many characters. Battleground names are long and the strip is not.",
        min = 4, max = 16, step = 1, format = "%d",
        get = function() return CommanderDiminishDB.NameMaxChars end,
        set = function(value) CommanderDiminishDB.NameMaxChars = value end,
        isEnabled = function() return Enabled() and CommanderDiminishDB.ShowName end,
    })
end

local function AddCellSection(panel)
    panel:AddSection("On Each Icon",
        "Three things can be written on a category: how far down the ladder it is, how long until it resets, and whether it is running RIGHT NOW. The third is the one people leave out and then misread the other two -- a category with something still on it is not counting down at all, because the fifteen seconds do not start until the aura fades.")

    panel:AddCheckboxPair({
        label = "Bracket badge",
        tooltip = "The half, quarter, or X in the corner: what the NEXT one in this category would land at. Colour says the same thing, so you can turn the text off once you have learned it.",
        get = function() return CommanderDiminishDB.ShowBracket end,
        set = function(value) CommanderDiminishDB.ShowBracket = value end,
        isEnabled = Enabled,
    }, {
        label = "Reset timer",
        tooltip = "Seconds until the category is back to full. It starts when the aura FADES, not when it lands -- which is why a stun that just landed shows no clock at all: nothing is counting yet.",
        get = function() return CommanderDiminishDB.ShowTimer end,
        set = function(value) CommanderDiminishDB.ShowTimer = value end,
        isEnabled = Enabled,
    })

    panel:AddCheckboxPair({
        label = "Clock sweep",
        tooltip = "The sweep under the icon, running out with the reset. Reads faster than the number at a glance and costs nothing to have both.",
        get = function() return CommanderDiminishDB.ShowSwipe end,
        set = function(value) CommanderDiminishDB.ShowSwipe = value end,
        isEnabled = Enabled,
    }, {
        label = "Mark what is up right now",
        tooltip = "A bright rim on a category that has something active in it. This is the frozen-clock case: nothing is counting down, and a strip that only showed numbers would show nothing at all at the exact moment the most is happening.",
        get = function() return CommanderDiminishDB.HeldGlow end,
        set = function(value) CommanderDiminishDB.HeldGlow = value end,
        isEnabled = Enabled,
    })

    panel:AddDropdown({
        label = "Icons",
        tooltip = "The picture each ladder wears. Category is the classic set every DR tracker has taught -- Hammer of Justice for a stun, Polymorph for the polymorph ladder, Fear for fear, Kidney Shot, Blind, Frost Nova for a root -- always the same picture for the same ladder. Last Spell draws an opened ladder with whichever spell opened it: a stun wearing a Hammer of Justice was a paladin, at the price of a different icon every time. Commander Plates draws its DR icons the same way.",
        options = {
            { text = "Category (classic)", value = "CATEGORY" },
            { text = "Last spell", value = "SPELL" },
        },
        width = 180,
        get = function() return CommanderDiminishDB.IconSource end,
        set = function(value) CommanderDiminishDB.IconSource = value end,
        isEnabled = Enabled,
    })

    panel:AddCheckbox({
        label = "Grey a ladder nothing has opened",
        tooltip = "Only matters with the greyed set drawn. Desaturating the untouched ones is what makes a full strip readable -- the lit ones are the ones with anything to say.",
        get = function() return CommanderDiminishDB.DesaturateFull end,
        set = function(value) CommanderDiminishDB.DesaturateFull = value end,
        isEnabled = function() return Enabled() and CommanderDiminishDB.ShowFull end,
    })

    panel:AddSlider({
        label = "Timer size",
        tooltip = "Point size of the reset clock on each icon.",
        min = 8, max = 20, step = 1, format = "%d",
        get = function() return CommanderDiminishDB.TimerSize end,
        set = function(value) CommanderDiminishDB.TimerSize = value end,
        isEnabled = function() return Enabled() and CommanderDiminishDB.ShowTimer end,
    })
end

-- ---------------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------------

local function CreateCorePanel()
    local panel = Commander.UI.NewPanel({
        key = "Diminish",
        title = "Diminish",
        addonName = "Commander_Diminish",
        description = "A diminishing-returns tracker for battlegrounds and arena, tailored to whatever you are playing. The ladders it draws are the ones your own spellbook can open -- read at login and again whenever your spells change, so it follows a respec rather than a list somebody maintained. TBC's real rules underneath: Kidney Shot on its own ladder, proc stuns separate from cast stuns, no bracket at all on silence, a fifteen-second clock that starts when the aura FADES and freezes while anything in the category is still up, and CC broken by damage caught properly -- it arrives as a different combat-log event, and a tracker that misses it leaves the bracket stuck for the rest of the game.",
        event = COMMANDER_DIMINISH_EVENTS.UPDATE,
        slash = { "/cdr", "/cdim" },
        slashHandlers = {
            test = function() if CommanderDiminish_Test then CommanderDiminish_Test() end end,
            report = function() if CommanderDiminish_Report then CommanderDiminish_Report() end end,
            -- The dispatcher matches the WHOLE message against these keys and
            -- passes nothing, so an argument has to be its own key.
            log = function() if CommanderDiminish_Log then CommanderDiminish_Log() end end,
            ["log off"] = function() if CommanderDiminish_Log then CommanderDiminish_Log("off") end end,
            lock = function()
                CommanderDiminishDB.HudLocked = not CommanderDiminishDB.HudLocked
                Commander.Notify(COMMANDER_DIMINISH_EVENTS.UPDATE)
                print("Commander Diminish: strip "
                    .. (CommanderDiminishDB.HudLocked and "locked" or "unlocked -- drag it, right-click to lock"))
            end,
        },
    })

    panel:AddCheckbox({
        label = "Enable Diminish",
        tooltip = "The whole module.",
        get = function() return CommanderDiminishDB.Enable end,
        set = function(value) CommanderDiminishDB.Enable = value end,
    })

    panel:AddButtonRow({
        {
            label = "Test Strip",
            tooltip = "Draw a full board with fabricated ladders -- one part-way down, one held, one immune, one clean -- so it can be placed and sized without queueing. Works anywhere; clears itself after a few seconds.",
            onClick = function() if CommanderDiminish_Test then CommanderDiminish_Test() end end,
            isEnabled = Enabled,
        },
        {
            label = "What Can I Open?",
            tooltip = "Print the ladders this character's spellbook can open, and the spell that proved each one. The answer to 'why is there no fear row'.",
            onClick = function() if CommanderDiminish_Report then CommanderDiminish_Report() end end,
            isEnabled = Enabled,
        },
        {
            label = "Unlock & Move",
            tooltip = "Unlock the strip so it can be dragged. Right-click it to lock again, or triple right-click a locked one to unlock it without coming back here.",
            onClick = function()
                CommanderDiminishDB.HudLocked = false
                Commander.Notify(COMMANDER_DIMINISH_EVENTS.UPDATE)
            end,
            isEnabled = Enabled,
        },
    })

    AddWhereSection(panel)
    AddWhoSection(panel)
    AddCategorySection(panel)
    AddLayoutSection(panel)
    AddCellSection(panel)

    -- Chrome last, per the suite convention
    Commander.UI.AddHudChromeOptions(panel, CommanderDiminishDB, "Hud", {
        isEnabled = Enabled,
        onChanged = function() Commander.Notify(COMMANDER_DIMINISH_EVENTS.UPDATE) end,
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Diminish" then
        Commander.UI.ApplyDefaults(CommanderDiminishDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateCorePanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
