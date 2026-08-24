CommanderMomentumDB = _G.CommanderMomentumDB or {}

COMMANDER_MOMENTUM_EVENTS = {
    UPDATE = "COMMANDER_MOMENTUM_UPDATE"
}

local DefaultSettings = {
    EnableMomentum = true,
    Window = 20,
    MilestoneSound = true,
    MilestoneEmotes = false,
    BreakEmotes = false,
    BreakWarning = true,
    ResetOnDeath = true,
    ResetOnZone = true,
    KillSource = "OWN",
    AlwaysShow = false,
    Display = "HUD",
    -- Player-frame display: style is Display above; everything here shapes
    -- where it sits, how big it is, and what it says
    Placement = "PORTRAIT",
    PlayerX = 0,
    PlayerY = 0,
    PlayerSize = 52,
    PlayerAlpha = 1,
    PlayerVertical = false,
    Accent = "TIERS",
    PortraitGlow = true,
    PipCap = 10,
    CombatOnly = false,
    ShowMultiplier = true,
    ShowSeconds = false,
    ShowPace = false,
    ShowBest = false,
    ShowWindow = false,
    ShowLabel = false,
}
for key, value in pairs(Commander.UI.HudChromeDefaults("Hud", "DARK")) do
    DefaultSettings[key] = value
end

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderMomentumDB, DefaultSettings)
    Commander.Notify(COMMANDER_MOMENTUM_EVENTS.UPDATE)
    print("Commander Momentum: settings restored to defaults")
end

-- Accent choices: the streak's own escalating tiers, your class color, or
-- any Commander_Console palette entry (the suite's shared tint canon, read
-- live so an uninstalled Console just means a shorter list)
local function AccentOptions()
    local options = {
        { text = "Streak Tiers", value = "TIERS" },
        { text = "Class Color", value = "CLASS" },
    }
    local seen = { TIERS = true, CLASS = true }
    for _, color in ipairs(CommanderConsole_Colors or {}) do
        -- Console's CLASS entry carries no rgb (it resolves live) and we
        -- already offer our own; its default is labelled with a
        -- parenthetical that means nothing over here
        if color.r and not seen[color.value] then
            seen[color.value] = true
            options[#options + 1] = {
                text = (color.text or color.value):gsub("%s*%b()", ""),
                value = color.value,
            }
        end
    end
    -- A saved key whose palette entry is gone would render as a blank
    -- dropdown label; keep it selectable so nothing silently changes
    local saved = CommanderMomentumDB.Accent
    if saved and not seen[saved] then
        options[#options + 1] = { text = saved, value = saved }
    end
    return options
end

local PLACEMENTS = {
    { text = "Over Portrait", value = "PORTRAIT" },
    { text = "Over Frame", value = "OVER" },
    { text = "Above Frame", value = "ABOVE" },
    { text = "Below Frame", value = "BELOW" },
    { text = "Left of Frame", value = "LEFT" },
    { text = "Right of Frame", value = "RIGHT" },
    { text = "Top-Left Corner", value = "TOPLEFT" },
    { text = "Top-Right Corner", value = "TOPRIGHT" },
    { text = "Bottom-Left Corner", value = "BOTTOMLEFT" },
    { text = "Bottom-Right Corner", value = "BOTTOMRIGHT" },
    { text = "On the Bars", value = "BARS" },
    { text = "Under the Bars", value = "UNDERBARS" },
}

local function PlayerModeOn()
    return CommanderMomentumDB.EnableMomentum and CommanderMomentumDB.Display ~= "HUD"
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Momentum",
        title = "Momentum",
        addonName = "Commander_Momentum",
        description = "A kill-streak combo meter. Each killing blow feeds the meter and resets its drain timer; keep chaining kills and the streak climbs through escalating colors — hesitate and the bar empties, taking the streak with it. Best chains are remembered per zone and instance forever: when your session's best chain ends, you get the recap of how it stacks against the zone record and the all-time high. Pure grinding dopamine.",
        event = COMMANDER_MOMENTUM_EVENTS.UPDATE,
        slash = { "/cmom" },
        slashHandlers = {
            report = function()
                if CommanderMomentum_Report then CommanderMomentum_Report() end
            end,
            records = function()
                if CommanderMomentum_Records then CommanderMomentum_Records() end
            end,
            test = function()
                if CommanderMomentum_Test then CommanderMomentum_Test() end
            end,
            display = function()
                if CommanderMomentum_DisplayReport then CommanderMomentum_DisplayReport() end
            end,
        },
    })

    -- The player-frame styles carry a page's worth of placement options on
    -- their own, so the content flows into a scroll frame (same trick
    -- Commander_PartyFrames uses). NewPanel's header stays fixed above;
    -- AddRow is overridden on THIS panel instance only.
    local scroll = CreateFrame("ScrollFrame", "CommanderMomentumScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel._anchor, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 12)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local target = self:GetVerticalScroll() - delta * 28
        local maxScroll = self:GetVerticalScrollRange()
        if target < 0 then target = 0 elseif target > maxScroll then target = maxScroll end
        self:SetVerticalScroll(target)
    end)
    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(1, 1)
    scroll:SetScrollChild(scrollChild)
    scroll:SetScript("OnSizeChanged", function(_, w) scrollChild:SetWidth(w) end)

    local seed = CreateFrame("Frame", nil, scrollChild)
    seed:SetHeight(1)
    seed:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
    seed:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
    panel._anchor = seed
    panel._contentHeight = 0
    panel.AddRow = function(self, height, spacing)
        local row = CreateFrame("Frame", nil, scrollChild)
        row:SetHeight(height)
        row:SetPoint("TOPLEFT", self._anchor, "BOTTOMLEFT", 0, -(spacing or 8))
        row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
        self._anchor = row
        self._contentHeight = self._contentHeight + height + (spacing or 8)
        return row
    end

    panel:AddCheckboxPair({
        label = "Enable Momentum",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderMomentumDB.EnableMomentum end,
        set = function(value) CommanderMomentumDB.EnableMomentum = value end,
    }, {
        label = "Always Show",
        tooltip = "Keep the meter on screen at x0 between streaks instead of appearing only while one is alive.",
        get = function() return CommanderMomentumDB.AlwaysShow end,
        set = function(value) CommanderMomentumDB.AlwaysShow = value end,
        isEnabled = function() return CommanderMomentumDB.EnableMomentum end,
    })
    panel:AddDropdownPair({
        label = "Display Mode",
        tooltip = "Floating Meter is the standalone HUD frame with its own position and chrome. Every other style rides the default player frame and is shaped by the Player Frame Display section below.\n\nPortrait Ring: radial sweep of the window wrapping your portrait.\nPortrait Glow: the multiplier alone, with the portrait disc fading as the clock runs out.\nBadge: a compact bordered chip.\nDrain Bar: a slim bar, horizontal or vertical.\nKill Pips: one pip per kill in the chain, newest pip fading as it drains.\nText Ticker: one plain line of text, no art.\nFrame Flare: a colored glow around the whole player frame.",
        options = {
            { text = "Floating Meter", value = "HUD" },
            { text = "Portrait Ring", value = "RING" },
            { text = "Portrait Glow", value = "GLOW" },
            { text = "Badge", value = "BADGE" },
            { text = "Drain Bar", value = "BAR" },
            { text = "Kill Pips", value = "PIPS" },
            { text = "Text Ticker", value = "TICKER" },
            { text = "Frame Flare", value = "FLARE" },
        },
        get = function() return CommanderMomentumDB.Display end,
        set = function(value) CommanderMomentumDB.Display = value end,
        isEnabled = function() return CommanderMomentumDB.EnableMomentum end,
    }, {
        label = "Kill Source",
        tooltip = "My Killing Blows counts only kills where you land the final hit. Squad Kills counts every hostile that dies around you — the meter works for healers and tanks too.",
        options = {
            { text = "My Killing Blows", value = "OWN" },
            { text = "Squad Kills", value = "SQUAD" },
        },
        get = function() return CommanderMomentumDB.KillSource end,
        set = function(value) CommanderMomentumDB.KillSource = value end,
        isEnabled = function() return CommanderMomentumDB.EnableMomentum end,
    })
    panel:AddSlider({
        label = "Momentum Window",
        tooltip = "Seconds you have to land the next killing blow before the streak drains away.",
        min = 8, max = 60, step = 1,
        format = "%.0fs",
        get = function() return CommanderMomentumDB.Window end,
        set = function(value) CommanderMomentumDB.Window = value end,
        isEnabled = function() return CommanderMomentumDB.EnableMomentum end,
    })

    panel:AddSection("Player Frame Display",
        "Where the player-frame styles sit and what they say. The player frame is crowded — Casting's bar, Buffs, the PartyFrames banner all want that corner — so pick the placement that leaves your layout alone and nudge it from there. Ignored while Display Mode is Floating Meter.")
    panel:AddDropdownPair({
        label = "Placement",
        tooltip = "Which side of the player frame the readout hangs off. Over Portrait glues it to the portrait art (what Portrait Ring and Portrait Glow are built around); the corner placements sit fully outside the frame; On/Under the Bars line it up with the health and mana bars. Frame Flare wraps the whole frame and only takes the offsets.",
        options = PLACEMENTS,
        get = function() return CommanderMomentumDB.Placement end,
        set = function(value) CommanderMomentumDB.Placement = value end,
        isEnabled = PlayerModeOn,
    }, {
        label = "Accent Color",
        tooltip = "Streak Tiers keeps the escalating white → green → blue → purple → orange ladder, so the color itself tells you how big the chain is. Class Color and the Commander Console palette entries hold one fixed color instead.",
        options = AccentOptions(),
        get = function() return CommanderMomentumDB.Accent end,
        set = function(value) CommanderMomentumDB.Accent = value end,
        isEnabled = PlayerModeOn,
    })
    panel:AddSliderPair({
        label = "Offset X",
        tooltip = "Nudge the readout sideways from its placement anchor.",
        min = -300, max = 300, step = 1,
        format = "%.0f",
        get = function() return CommanderMomentumDB.PlayerX end,
        set = function(value) CommanderMomentumDB.PlayerX = value end,
        isEnabled = PlayerModeOn,
    }, {
        label = "Offset Y",
        tooltip = "Nudge the readout up or down from its placement anchor.",
        min = -300, max = 300, step = 1,
        format = "%.0f",
        get = function() return CommanderMomentumDB.PlayerY end,
        set = function(value) CommanderMomentumDB.PlayerY = value end,
        isEnabled = PlayerModeOn,
    })
    panel:AddSliderPair({
        label = "Size",
        tooltip = "The readout's base dimension: ring and glow diameter, badge height, bar length and thickness, pip size, ticker text size. 52 wraps the default portrait.",
        min = 16, max = 140, step = 1,
        format = "%.0f",
        get = function() return CommanderMomentumDB.PlayerSize end,
        set = function(value) CommanderMomentumDB.PlayerSize = value end,
        isEnabled = PlayerModeOn,
    }, {
        label = "Opacity",
        tooltip = "How solid the readout is. Turn it down for a style you want present but not competing with the frame underneath.",
        min = 0.1, max = 1, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderMomentumDB.PlayerAlpha end,
        set = function(value) CommanderMomentumDB.PlayerAlpha = value end,
        isEnabled = PlayerModeOn,
    })
    panel:AddSliderPair({
        label = "Pip Cap",
        tooltip = "Kill Pips only: how many pips are drawn before the row stops growing. Past the cap the multiplier carries the count.",
        min = 3, max = 25, step = 1,
        format = "%.0f",
        get = function() return CommanderMomentumDB.PipCap end,
        set = function(value) CommanderMomentumDB.PipCap = value end,
        isEnabled = function() return PlayerModeOn() and CommanderMomentumDB.Display == "PIPS" end,
    })
    panel:AddCheckboxPair({
        label = "Vertical Layout",
        tooltip = "Drain Bar and Kill Pips only: stand them on end, so they can run down the side of the player frame instead of across it.",
        get = function() return CommanderMomentumDB.PlayerVertical end,
        set = function(value) CommanderMomentumDB.PlayerVertical = value end,
        isEnabled = function()
            return PlayerModeOn()
                and (CommanderMomentumDB.Display == "BAR" or CommanderMomentumDB.Display == "PIPS")
        end,
    }, {
        label = "Portrait Glow",
        tooltip = "Tint the portrait disc in the streak's color for any style, not just the ones living on the portrait — the chain stays readable off your own face while the readout sits elsewhere. With Portrait Glow as the style, this glow is the timer and fades as the window drains.",
        get = function() return CommanderMomentumDB.PortraitGlow end,
        set = function(value) CommanderMomentumDB.PortraitGlow = value end,
        isEnabled = PlayerModeOn,
    })
    panel:AddCheckboxPair({
        label = "Show Multiplier",
        tooltip = "Print the chain size (x7) on the readout. Off leaves the art alone — a bare ring, bar, or pip row.",
        get = function() return CommanderMomentumDB.ShowMultiplier end,
        set = function(value) CommanderMomentumDB.ShowMultiplier = value end,
        isEnabled = PlayerModeOn,
    }, {
        label = "Show Countdown",
        tooltip = "Print the seconds left on the window as a number, updated once a second, alongside the art that already shows it draining.",
        get = function() return CommanderMomentumDB.ShowSeconds end,
        set = function(value) CommanderMomentumDB.ShowSeconds = value end,
        isEnabled = PlayerModeOn,
    })
    panel:AddCheckboxPair({
        label = "Show Pace",
        tooltip = "Print the live kill rate for the current chain (kills per minute), the same number the milestone emote brags.",
        get = function() return CommanderMomentumDB.ShowPace end,
        set = function(value) CommanderMomentumDB.ShowPace = value end,
        isEnabled = PlayerModeOn,
    }, {
        label = "Show Best Chain",
        tooltip = "Print this session's best chain next to the live one — the number to beat, always in view.",
        get = function() return CommanderMomentumDB.ShowBest end,
        set = function(value) CommanderMomentumDB.ShowBest = value end,
        isEnabled = PlayerModeOn,
    })
    panel:AddCheckboxPair({
        label = "Show Window",
        tooltip = "Print the momentum window itself (\"20s clock\") on the readout, so the rules of the chain are on screen and not just in the settings.",
        get = function() return CommanderMomentumDB.ShowWindow end,
        set = function(value) CommanderMomentumDB.ShowWindow = value end,
        isEnabled = PlayerModeOn,
    }, {
        label = "Show Label",
        tooltip = "Print the word MOMENTUM under the readout. Useful while positioning a style that is otherwise just a number.",
        get = function() return CommanderMomentumDB.ShowLabel end,
        set = function(value) CommanderMomentumDB.ShowLabel = value end,
        isEnabled = PlayerModeOn,
    })
    panel:AddCheckbox({
        label = "Combat Only",
        tooltip = "Hide the player-frame readout while you are out of combat, even with Always Show on. The chain itself keeps running — only the display waits for the next fight.",
        get = function() return CommanderMomentumDB.CombatOnly end,
        set = function(value) CommanderMomentumDB.CombatOnly = value end,
        isEnabled = PlayerModeOn,
    })
    panel:AddSection("Milestones & Callouts")

    panel:AddCheckboxPair({
        label = "Milestone Sound",
        tooltip = "Play a chime when the streak crosses a milestone (5, 10, 15, 20...).",
        get = function() return CommanderMomentumDB.MilestoneSound end,
        set = function(value) CommanderMomentumDB.MilestoneSound = value end,
        isEnabled = function() return CommanderMomentumDB.EnableMomentum end,
    }, {
        label = "Milestone Emotes",
        tooltip = "Announce milestones to everyone nearby as a custom emote with escalating flavor and your session numbers — kill chain, the window clock it has to beat, pace, total kills, best chain. Public bragging; off by default.",
        get = function() return CommanderMomentumDB.MilestoneEmotes end,
        set = function(value) CommanderMomentumDB.MilestoneEmotes = value end,
        isEnabled = function() return CommanderMomentumDB.EnableMomentum end,
    })
    panel:AddCheckboxPair({
        label = "Reset on Death",
        tooltip = "Dying breaks the live chain (lament rules apply) and zeroes the session numbers — kills and best chain start over.",
        get = function() return CommanderMomentumDB.ResetOnDeath end,
        set = function(value) CommanderMomentumDB.ResetOnDeath = value end,
        isEnabled = function() return CommanderMomentumDB.EnableMomentum end,
    }, {
        label = "Reset on Zone Change",
        tooltip = "Loading-screen transitions (entering or leaving an instance, continent travel) quietly end the chain and start fresh session numbers. A /reload in place never counts.",
        get = function() return CommanderMomentumDB.ResetOnZone end,
        set = function(value) CommanderMomentumDB.ResetOnZone = value end,
        isEnabled = function() return CommanderMomentumDB.EnableMomentum end,
    })
    panel:AddCheckboxPair({
        label = "Streak Break Emote",
        tooltip = "When the clock runs out on a live chain over x10, your character emotes the lament with your session numbers and the all-time high; chains over x15 also earn the audible /cry sob, sent after the lament so the chat log reads in order. Public; off by default.",
        get = function() return CommanderMomentumDB.BreakEmotes end,
        set = function(value) CommanderMomentumDB.BreakEmotes = value end,
        isEnabled = function() return CommanderMomentumDB.EnableMomentum end,
    }, {
        label = "Break Warning",
        tooltip = "Local heads-up (sound, chat line, meter flashes red) when a live streak has 5 seconds left. For the public group rally, enable Auto Charge Rally in Commander Comms.",
        get = function() return CommanderMomentumDB.BreakWarning end,
        set = function(value) CommanderMomentumDB.BreakWarning = value end,
        isEnabled = function() return CommanderMomentumDB.EnableMomentum end,
    })

    panel:AddSection("Tools")
    panel:AddButtonRow({
        {
            label = "Test Streak",
            width = 110,
            tooltip = "Feed two harmless test kills so you can see and position the readout, whichever display style you are on (also: /cmom test). No public emotes, session stats untouched.",
            onClick = function()
                if CommanderMomentum_Test then CommanderMomentum_Test() end
            end,
        },
        {
            label = "Session Report",
            width = 130,
            tooltip = "Print this session's kills, best chain, and any live streak, plus where you stand on the local zone record and the all-time high (also: /cmom report).",
            onClick = function()
                if CommanderMomentum_Report then CommanderMomentum_Report() end
            end,
        },
        {
            label = "Locate Readout",
            width = 130,
            tooltip = "Print where the player-frame readout currently sits, what it says, and whether it is on screen at all — for when a placement change hides it somewhere you didn't expect (also: /cmom display).",
            onClick = function()
                if CommanderMomentum_DisplayReport then CommanderMomentum_DisplayReport() end
            end,
        },
        {
            label = "Zone Records",
            width = 110,
            tooltip = "Print the best chain ever landed in each zone and instance, top score first with the all-time high on top (also: /cmom records). Records persist forever and survive settings resets.",
            onClick = function()
                if CommanderMomentum_Records then CommanderMomentum_Records() end
            end,
        },
    })

    panel:AddSection("Floating Meter",
        "Chrome for the standalone HUD frame only — the player-frame styles are positioned by the section above.")
    Commander.UI.AddHudChromeOptions(panel, CommanderMomentumDB, "Hud", {
        isEnabled = function()
            return CommanderMomentumDB.EnableMomentum and CommanderMomentumDB.Display == "HUD"
        end,
        onChanged = function() Commander.Notify(COMMANDER_MOMENTUM_EVENTS.UPDATE) end,
    })

    panel:Finalize({ onDefaults = Reset })
    scrollChild:SetHeight(panel._contentHeight + 24)
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Momentum" then
        Commander.UI.ApplyDefaults(CommanderMomentumDB, DefaultSettings)
        -- The single player-frame mode that predates the styles: its saved
        -- value is the Portrait Ring style now, and leaving it unmigrated
        -- would render as a blank dropdown label
        if CommanderMomentumDB.Display == "PORTRAIT" then
            CommanderMomentumDB.Display = "RING"
        end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
