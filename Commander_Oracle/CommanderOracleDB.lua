CommanderOracleDB = _G.CommanderOracleDB or {}

COMMANDER_ORACLE_EVENTS = {
    UPDATE = "COMMANDER_ORACLE_UPDATE"
}

local DefaultSettings = {
    EnableOracle = true,
    ShowComms = true,
    -- Compact by default: this is a HUD read at a glance mid-fight, not a
    -- report. Full is there when you want the bars and a row per rung.
    Density = "COMPACT",
    -- What makes the no-backdrop styles usable — see the note in
    -- CommanderOracle.lua's ApplyTextTreatment.
    TextOutline = false,
    ShowVerdict = true,
    ShowRace = true,
    ShowLadder = true,
    ShowNodes = true,
    ShowCallout = true,
    ShowPending = true,
    SwingAlert = true,
    SwingSound = true,
    NearVictoryAlert = true,
    -- Which end of the client's resource widget is the Alliance. AUTO watches
    -- which bar climbs faster and settles it against the base counts we read
    -- off the map, which is the only locale-proof way to know.
    ScoreBars = "AUTO",
    -- The roster tabs. Which tab is up is remembered on purpose: it is where
    -- you left the board, not a preference you should have to re-set every
    -- time you zone in.
    ShowPerformers = true,
    Tab = "BATTLE",
    TopCount = 3,
    ShowDistance = true,
    -- OFF by default, and deliberately: raid markers land on thirty-nine other
    -- people's screens, and a feature that writes to a raid should be one you
    -- switched on rather than one you inherited.
    MarkTop = false,
    MarkCount = 3,
    MarkArenaTeam = false,
}
-- No backdrop by default. The board is meant to sit on the screen as text and
-- nothing else; the dropdown still offers the suite's panels and the window
-- for anyone who wants a frame around it.
for key, value in pairs(Commander.UI.HudChromeDefaults("Board", "NONE")) do
    DefaultSettings[key] = value
end

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderOracleDB, DefaultSettings)
    Commander.Notify(COMMANDER_ORACLE_EVENTS.UPDATE)
    print("Commander Oracle: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Oracle",
        title = "Oracle",
        addonName = "Commander_Oracle",
        description = "The battleground battle computer. In Arathi Basin the BATTLE tab reads the five flags off the map and the resources off the client's own widget, runs the race to 2000 forward at the real tick rates, and answers what actually decides the game: who wins from here and by how much, the least you have to hold, and how long you have left to take the base that saves it. In EVERY battleground the roster tabs read the server's own scoreboard — all forty players, not just the ones your combat log could see — and rank both sides by Impact -- output, the trade they got for it, killing blows, and objectives last and lightest -- so the healer to focus and the player carrying the enemy team are named rather than buried in a table of totals.",
        event = COMMANDER_ORACLE_EVENTS.UPDATE,
        slash = { "/coracle", "/cbasin" },
        slashHandlers = {
            test = function() if CommanderOracle_Test then CommanderOracle_Test() end end,
            call = function() if CommanderOracle_Call then CommanderOracle_Call() end end,
            defend = function() if CommanderOracle_Defend then CommanderOracle_Defend() end end,
            take = function() if CommanderOracle_Take then CommanderOracle_Take() end end,
            probe = function() if CommanderOracle_Probe then CommanderOracle_Probe() end end,
            -- Commander Orders 3.1: Go to the Flag (also a key binding) and
            -- every place the battleground map names, each with a [Go] link
            flag = function() if CommanderOracle_GoToFlag then CommanderOracle_GoToFlag() end end,
            nodes = function() if CommanderOracle_Nodes then CommanderOracle_Nodes() end end,
        },
    })


    panel:AddSection("Battle Computer")
    panel:AddCheckbox({
        label = "Enable Oracle",
        tooltip = "Master switch. The board shows itself on entering Arathi Basin and puts itself away when you leave.",
        get = function() return CommanderOracleDB.EnableOracle end,
        set = function(value) CommanderOracleDB.EnableOracle = value end,
    })

    panel:AddDropdownPair({
        label = "Density",
        tooltip = "How much room the board takes. Compact writes the resources as their own numbers instead of bars and folds the win-condition ladder into a single strip — the same information in well under half the height. Minimal collapses the whole read onto one line (verdict, clock and the call) over the node board. Full is the roomy version with bars and a row per rung.",
        options = {
            { text = "Compact", value = "COMPACT" },
            { text = "Minimal", value = "MINIMAL" },
            { text = "Full", value = "FULL" },
        },
        get = function() return CommanderOracleDB.Density or "COMPACT" end,
        set = function(value) CommanderOracleDB.Density = value end,
        isEnabled = function() return CommanderOracleDB.EnableOracle end,
    }, nil)
    panel:AddCheckbox({
        label = "Heavy Outline",
        tooltip = "Draw a full outline around every number as well as the shadow. The shadow is always on — it is what makes Frame Style: None usable, since plain text over Arathi's snow and grass disappears at exactly the moment you need it. The outline on top is heavier: at this text size it closes up the inside of the letters and can read as a smudge, so it is off by default. Turn it on if you run a very busy background.",
        get = function() return CommanderOracleDB.TextOutline end,
        set = function(value) CommanderOracleDB.TextOutline = value end,
        isEnabled = function() return CommanderOracleDB.EnableOracle end,
    })

    panel:AddSection("What the board shows", "Every section can be turned off on its own; the board shrinks to fit whatever is left. Minimal density folds the race, the ladder and the call into its single line, so those three switches only bite at Compact and Full.")
    panel:AddCheckbox({
        label = "Comms Header",
        tooltip = "A row of three buttons across the top of the board for telling the battlegroup the things only Oracle can see. CALL posts the whole read; DEFEND names the flags they are taking right now AND what losing them costs (everyone can see a flag turning grey — nobody else can see that this one is the game); TAKE posts how many more bases are needed and how long there is left to get them. Nothing is ever sent on its own: each line is one click, each button is throttled, a button with nothing true to say greys out, and hovering a button shows you the exact line it will post before you commit to it. Also on /coracle call, /coracle defend and /coracle take if you would rather bind them.",
        get = function() return CommanderOracleDB.ShowComms end,
        set = function(value) CommanderOracleDB.ShowComms = value end,
        isEnabled = function() return CommanderOracleDB.EnableOracle end,
    })
    panel:AddCheckboxPair({
        label = "Verdict",
        tooltip = "The headline: who this game goes to from the present board, by how many resources, and how long that takes.",
        get = function() return CommanderOracleDB.ShowVerdict end,
        set = function(value) CommanderOracleDB.ShowVerdict = value end,
        isEnabled = function() return CommanderOracleDB.EnableOracle end,
    }, {
        label = "The Race",
        tooltip = "Both sides' resources against the 2000 cap, with the income each is actually banking.",
        get = function() return CommanderOracleDB.ShowRace end,
        set = function(value) CommanderOracleDB.ShowRace = value end,
        isEnabled = function() return CommanderOracleDB.EnableOracle end,
    })
    panel:AddCheckboxPair({
        label = "Win-Condition Ladder",
        tooltip = "One row per hold, five bases down to none: what each is worth from where the score stands right now. The row you are actually on is marked.",
        get = function() return CommanderOracleDB.ShowLadder end,
        set = function(value) CommanderOracleDB.ShowLadder = value end,
        isEnabled = function() return CommanderOracleDB.EnableOracle end,
    }, {
        label = "Node Board",
        tooltip = "The five flags, who holds each, and a live countdown on any that is ticking. With Commander Orders loaded, click a flag and the arrow points at it; the waypoint goes away when the match does.",
        get = function() return CommanderOracleDB.ShowNodes end,
        set = function(value) CommanderOracleDB.ShowNodes = value end,
        isEnabled = function() return CommanderOracleDB.EnableOracle end,
    })
    panel:AddCheckboxPair({
        label = "The Call",
        tooltip = "The single line worth acting on: hold what you have, take one more, or the clock you have left to do it in.",
        get = function() return CommanderOracleDB.ShowCallout end,
        set = function(value) CommanderOracleDB.ShowCallout = value end,
        isEnabled = function() return CommanderOracleDB.EnableOracle end,
    }, {
        label = "Count Flags In Flight",
        tooltip = "Also project the board as it will stand once every flag currently ticking lands with whoever started it — where the game is going if nobody intervenes.",
        get = function() return CommanderOracleDB.ShowPending end,
        set = function(value) CommanderOracleDB.ShowPending = value end,
        isEnabled = function() return CommanderOracleDB.EnableOracle end,
    })

    panel:AddSection("Top performers",
        "The roster tabs rank both sides off the battlefield scoreboard, which every battleground has — so they work in all of them, while the BATTLE tab stays Arathi's. Left-click a row to target, right-click to focus.")
    panel:AddCheckbox({
        label = "Roster Tabs",
        tooltip = "Add the TOP tab (the best players on either side, scored) and a tab per faction (that side broken down by killing blows, damage, healing and the map's own objective columns) to the board. Every row on them is clickable: left-click targets that player, right-click focuses them. Turn this off and Oracle is the Arathi board and nothing else.",
        get = function() return CommanderOracleDB.ShowPerformers end,
        set = function(value) CommanderOracleDB.ShowPerformers = value end,
        isEnabled = function() return CommanderOracleDB.EnableOracle end,
    })
    panel:AddSlider({
        label = "Players Per Board",
        tooltip = "How many players each ranking lists. Three is the number you can actually act on; five is closer to a scoreboard.",
        min = 1, max = 5, step = 1,
        format = function(value) return string.format("%d", value) end,
        get = function() return CommanderOracleDB.TopCount end,
        set = function(value) CommanderOracleDB.TopCount = value end,
        isEnabled = function()
            return CommanderOracleDB.EnableOracle and CommanderOracleDB.ShowPerformers
        end,
    })

    panel:AddCheckbox({
        label = "Show Range",
        tooltip = "Add a range column to the rankings. The client measures real yards only for players in your own raid; for anyone else it gives an upper bound when you are holding a unit for them (your target, your focus, the mouse, a nameplate) and nothing at all otherwise — the column says which, and never guesses.",
        get = function() return CommanderOracleDB.ShowDistance end,
        set = function(value) CommanderOracleDB.ShowDistance = value end,
        isEnabled = function()
            return CommanderOracleDB.EnableOracle and CommanderOracleDB.ShowPerformers
        end,
    })

    panel:AddSection("Raid markers",
        "Off until you turn it on. While you hold the lead or an assist, Oracle can mark your own side: in a battleground by who is playing best, in an arena by class colour.")
    panel:AddCheckbox({
        label = "Mark Our Top Players",
        tooltip = "Put a raid icon on each of your side's top players by Impact, and keep it up to date through the match. Requires you to be the raid leader or an assistant — the server refuses a marker from anyone else. Marks are sticky (a player keeps their icon until they fall well out of the top, so nothing re-shuffles on a rounding difference), Oracle only ever removes an icon it placed itself, and it never takes one that is already somebody else's.",
        get = function() return CommanderOracleDB.MarkTop end,
        set = function(value) CommanderOracleDB.MarkTop = value end,
        isEnabled = function() return CommanderOracleDB.EnableOracle end,
    })
    panel:AddSlider({
        label = "Players Marked",
        tooltip = "How many of your side's top players carry an icon. Eight is every marker the game has.",
        min = 1, max = 8, step = 1,
        format = function(value) return string.format("%d", value) end,
        get = function() return CommanderOracleDB.MarkCount end,
        set = function(value) CommanderOracleDB.MarkCount = value end,
        isEnabled = function()
            return CommanderOracleDB.EnableOracle and CommanderOracleDB.MarkTop
        end,
    })

    panel:AddCheckbox({
        label = "Mark Arena Team By Class",
        tooltip = "In an arena, put a raid icon on each of your own team matched to their CLASS COLOUR — the druid takes the orange circle, the rogue the yellow star, the priest the skull, and so on. Hue decides, so nobody ends up on an icon that looks nothing like them, and a team with two of the same class still gets two different icons. Requires you to be the party leader. Same care as above: only icons Oracle placed are ever removed.",
        get = function() return CommanderOracleDB.MarkArenaTeam end,
        set = function(value) CommanderOracleDB.MarkArenaTeam = value end,
        isEnabled = function() return CommanderOracleDB.EnableOracle end,
    })

    panel:AddSection("Alerts")
    panel:AddCheckboxPair({
        label = "Swing Alert",
        tooltip = "Flash the verdict when the projection flips — the moment a base changed hands and the game changed with it. This is the alert worth having: it fires when the answer changes, not when the score does.",
        get = function() return CommanderOracleDB.SwingAlert end,
        set = function(value) CommanderOracleDB.SwingAlert = value end,
        isEnabled = function() return CommanderOracleDB.EnableOracle end,
    }, {
        label = "Swing Sound",
        tooltip = "Play a note with the swing flash.",
        get = function() return CommanderOracleDB.SwingSound end,
        set = function(value) CommanderOracleDB.SwingSound = value end,
        isEnabled = function() return CommanderOracleDB.EnableOracle and CommanderOracleDB.SwingAlert end,
    })
    panel:AddCheckbox({
        label = "Near-Victory Warning",
        tooltip = "Mark the race bar as either side crosses 1800, the server's own near-victory line.",
        get = function() return CommanderOracleDB.NearVictoryAlert end,
        set = function(value) CommanderOracleDB.NearVictoryAlert = value end,
        isEnabled = function() return CommanderOracleDB.EnableOracle end,
    })

    panel:AddSection("Reading the client")
    panel:AddDropdown({
        label = "Resource Lines",
        tooltip = "Which of the client's two resource lines belongs to the Alliance. Auto settles it by arithmetic rather than by reading text: each line states how many bases its side holds, and the map already said exactly how many each faction holds, so matching the two names the sides with certainty the moment the counts differ. Set it by hand only if Auto ever gets it wrong.",
        options = {
            { text = "Auto", value = "AUTO" },
            { text = "First is Alliance", value = "LEFT_ALLIANCE" },
            { text = "First is Horde", value = "LEFT_HORDE" },
        },
        get = function() return CommanderOracleDB.ScoreBars or "AUTO" end,
        set = function(value) CommanderOracleDB.ScoreBars = value end,
        isEnabled = function() return CommanderOracleDB.EnableOracle end,
    })
    panel:AddButtonRow({
        {
            label = "Demo Board",
            width = 120,
            tooltip = "Put a worked Arathi Basin position on screen so the board can be placed and sized outside a battleground (also: /coracle test).",
            onClick = function() if CommanderOracle_Test then CommanderOracle_Test() end end,
        },
        {
            label = "Call It",
            width = 120,
            tooltip = "Post the current read to battleground chat as one line — the same thing the header's CALL button does. Manual only; Oracle never says anything to anyone on its own (also: /coracle call).",
            onClick = function() if CommanderOracle_Call then CommanderOracle_Call() end end,
        },
        {
            label = "Probe Widgets",
            width = 120,
            tooltip = "Dump every UI widget the client is showing to your chat frame, with the numbers in it. What to run if the resources ever read wrong (also: /coracle probe).",
            onClick = function() if CommanderOracle_Probe then CommanderOracle_Probe() end end,
        },
    })

    Commander.UI.AddHudChromeOptions(panel, CommanderOracleDB, "Board", {
        isEnabled = function() return CommanderOracleDB.EnableOracle end,
        onChanged = function() Commander.Notify(COMMANDER_ORACLE_EVENTS.UPDATE) end,
        defaultPoint = { point = "TOPLEFT", x = 24, y = -220 },
    })

    panel:Finalize({ onDefaults = Reset })
    -- After Finalize: its first Refresh is what grows the wrapped section
    -- notes, and the scroll child has to be sized around the result
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Oracle" then
        Commander.UI.ApplyDefaults(CommanderOracleDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
