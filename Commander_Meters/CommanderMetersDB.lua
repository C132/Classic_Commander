CommanderMetersDB = _G.CommanderMetersDB or {}
-- Second SavedVariables: raw combat-log dumps from /cmeters dump, kept apart
-- from settings so Restore Defaults never touches a captured session.
-- (A third, CommanderMetersSession, holds the opt-in Overall+Last snapshot
-- written at logout; the engine owns its shape.)
CommanderMetersLog = _G.CommanderMetersLog or {}
-- Fourth SavedVariables: closed arena matches (CommanderMetersArenaLog),
-- written at logout when Arena › Keep Matches is above zero; the arena
-- engine owns its shape.

COMMANDER_METERS_EVENTS = {
    UPDATE = "COMMANDER_METERS_UPDATE"
}

-- ---------------------------------------------------------------------------
-- Schema versioning: every settings reshape ships as a migration step, so
-- an upgrade can rename or retype keys without ever losing a user's setup.
-- MIGRATIONS[n] migrates version n -> n+1; the ladder runs in order.
-- ---------------------------------------------------------------------------

local DB_VERSION = 3
local MIGRATIONS = {
    -- v1 was the pre-versioning original release; v2 adds the version
    -- stamp itself plus the batch-3 keys (new keys need no migration —
    -- ApplyDefaults fills them). Future reshapes slot in here.
    [1] = function(db) end,
    -- v3: the Arena Report never opens itself (Devin: "only when I click
    -- the button"), so the ArenaAutoOpen key is retired
    [2] = function(db) db.ArenaAutoOpen = nil end,
}

local function Migrate(db)
    local v = tonumber(db.DBVersion) or 1
    while v < DB_VERSION do
        local step = MIGRATIONS[v]
        if step then step(db) end
        v = v + 1
    end
    db.DBVersion = DB_VERSION
end

-- The settings list is DERIVED, not accumulated (the derivation lives in
-- DECISIONS.md D12; the ceiling was re-derived to 14 in D18 when Devin
-- requested the appearance/persistence/lock batch — every key past the
-- original eight carries its justification there). Geometry stays fixed.
local DefaultSettings = {
    EnableMeters = true,
    MaxRows = 8,            -- bar rows per pane
    FrameWidth = 240,
    AutoSwitchCurrent = true, -- follow combat: Current on pull, Last on kill
    IdleTimeout = 3,        -- seconds of silence (out of combat) ending a fight
    PersistData = false,    -- Overall+Last survive /reload (logout-write only)

    -- Auto-reset triggers: each wipes ALL meter data, same as RESET ALL.
    -- Off by default, independently toggleable (brief-mandated trio).
    AutoResetOnNewFight = false,
    AutoResetOnInstance = false,
    AutoResetOnReadyCheck = false,

    -- Appearance: overrides resolved into the THEME table. Opacities apply
    -- live; accent and text size bake into widgets at login (/reload).
    AccentColor = "AMBER",  -- AMBER | CYAN | GREEN | RED | WHITE, or any
                            -- Commander_Console suite tint (GOLD, FEL,
                            -- CLASS, ...) — unknown keys fall back to amber
    TextSize = 11,          -- 10 | 11 | 12 (/reload to apply)
    BgOpacity = 0.92,       -- window fill alpha
    BarOpacity = 0.30,      -- bar fill alpha behind the text
    ClickThrough = false,   -- locked window ignores the mouse on bars/graph

    -- Persisted view state (written by the window chrome, no panel widget)
    WindowShown = true,
    ViewMode = "DMG",
    ViewSegment = "current", -- "current" | "overall" ("last"/fight ids are session-scoped)
    SplitOpen = false,       -- second pane open (the header's split toggle)
    SplitMode = "HEAL",      -- the second pane's mode
    SplitSegment = "follow", -- the second pane's segment: "follow" (the
                             -- window's, the default) | "current" |
                             -- "overall". "last" and fight ids stay
                             -- session-scoped exactly like ViewSegment.
    LastInstanceKey = false, -- auto-reset baseline: persists so a /reload
                             -- inside an instance never counts as entering it

    -- Arena (D27): both teams recorded per match, the report window, and
    -- how many past matches survive a logout
    ArenaRecord = true,      -- record arena matches (both teams, replayable)
    ArenaKeepMatches = 6,    -- past matches saved across logout (0 = session only)
}
for key, value in pairs(Commander.UI.HudChromeDefaults("Hud", "DARK")) do
    DefaultSettings[key] = value
end

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    -- ResetToDefaults bypasses the widgets' set() closures, so the
    -- bake-at-login options need their reload hint issued here
    local needsReload = CommanderMetersDB.AccentColor ~= DefaultSettings.AccentColor
        or CommanderMetersDB.TextSize ~= DefaultSettings.TextSize
    Commander.UI.ResetToDefaults(CommanderMetersDB, DefaultSettings)
    Commander.Notify(COMMANDER_METERS_EVENTS.UPDATE)
    print("Commander Meters: settings restored to defaults")
    if needsReload then
        print("|cff66ccffCommander Meters|r: appearance change applies after /reload")
    end
end

local function Enabled()
    return CommanderMetersDB.EnableMeters
end

local RELOAD_NOTE = "Takes effect after /reload (baked into the window at login)."

local function NoteReload()
    print("|cff66ccffCommander Meters|r: appearance change applies after /reload")
end

local function CreateCorePanel()
    local panel = Commander.UI.NewPanel({
        key = "Meters",
        title = "Meters",
        addonName = "Commander_Meters",
        description = "The battle report — live damage, healing, damage-taken, utility, and death meters with per-fight segments. Bars read at a glance mid-pull; split the window for two stats at once — or for one stat on two segments, Current beside Overall, since each pane's caption sets both its mode and its segment — click a bar for its full breakdown and pie chart, open the graph for throughput over the fight, and check the death log for the last ten hits before anyone dropped. Pets and totems always count under their owner.",
        event = COMMANDER_METERS_EVENTS.UPDATE,
        slash = { "/cmeters", "/cm" },
        slashHandlers = {
            [""] = function() if CommanderMeters_Toggle then CommanderMeters_Toggle() end end,
            test = function() if CommanderMeters_Test then CommanderMeters_Test() end end,
            wipe = function() if CommanderMeters_WipeAll then CommanderMeters_WipeAll() end end,
            wipefight = function() if CommanderMeters_WipeFight then CommanderMeters_WipeFight() end end,
            lock = function() if CommanderMeters_SetLock then CommanderMeters_SetLock(true) end end,
            unlock = function() if CommanderMeters_SetLock then CommanderMeters_SetLock(false) end end,
            dump = function() if CommanderMeters_Dump then CommanderMeters_Dump() end end,
            health = function() if CommanderMeters_Health then CommanderMeters_Health() end end,
            arena = function() if CommanderMeters_ArenaToggle then CommanderMeters_ArenaToggle() end end,
            arenatest = function() if CommanderMeters_ArenaTest then CommanderMeters_ArenaTest() end end,
        },
    })

    panel:AddSection("Meter")

    panel:AddCheckboxPair({
        label = "Enable Meters",
        tooltip = "Master switch. Off stops all combat-log recording and hides the window; existing data is kept until you wipe it.",
        get = function() return CommanderMetersDB.EnableMeters end,
        set = function(value) CommanderMetersDB.EnableMeters = value end,
    }, {
        label = "Follow Combat",
        tooltip = "Switch the window to the Current fight when combat starts and to Last when it ends (the segment button flashes so the change is never silent). Off keeps whatever segment you picked.",
        get = function() return CommanderMetersDB.AutoSwitchCurrent end,
        set = function(value) CommanderMetersDB.AutoSwitchCurrent = value end,
        isEnabled = Enabled,
    })

    panel:AddSliderPair({
        label = "Bar Rows",
        tooltip = "How many bars each pane shows. Everything is still recorded; the wheel scrolls the rest.",
        min = 4, max = 15, step = 1,
        format = "%d",
        get = function() return CommanderMetersDB.MaxRows end,
        set = function(value) CommanderMetersDB.MaxRows = value end,
        isEnabled = Enabled,
    }, {
        label = "Window Width",
        tooltip = "Width of the meter window in pixels. Splitting never changes it — the two panes share the width, so the window's footprint holds.",
        min = 200, max = 340, step = 10,
        format = "%d",
        get = function() return CommanderMetersDB.FrameWidth end,
        set = function(value) CommanderMetersDB.FrameWidth = value end,
        isEnabled = Enabled,
    })

    panel:AddSlider({
        label = "Fight Ends After",
        tooltip = "Seconds without any group combat activity (while you are out of combat) before the fight is closed into Last. The fight's duration always ends at its last real event, never at this deadline. Inside an arena or battleground this never applies: the whole match is one fight, closed when a winner is declared.",
        min = 2, max = 10, step = 1,
        format = "%d sec",
        get = function() return CommanderMetersDB.IdleTimeout end,
        set = function(value) CommanderMetersDB.IdleTimeout = value end,
        isEnabled = Enabled,
    })

    panel:AddCheckbox({
        label = "Keep Data Through /reload",
        tooltip = "Save Overall and the Last fight when you log out or /reload, and resume them if you come back within 10 minutes. Written only at a clean logout — a crash loses the session either way. Fight history beyond Last stays session-only.",
        get = function() return CommanderMetersDB.PersistData end,
        set = function(value) CommanderMetersDB.PersistData = value end,
        isEnabled = Enabled,
    })

    panel:AddSection("Appearance",
        "The theme stays one flat table — these write into it. Accent and text size bake in at login and need a /reload; the opacities apply live.")

    -- Accent choices: Meters' own five plus every suite tint from
    -- Commander_Console (the TopBar pattern), so the whole suite can match
    -- from one named palette. Console absent → just the local five, and a
    -- saved suite key quietly resolves to amber in the window.
    local accentOptions = {
        { text = "Amber", value = "AMBER" },
        { text = "Cyan", value = "CYAN" },
        { text = "Green", value = "GREEN" },
        { text = "Red", value = "RED" },
        { text = "White", value = "WHITE" },
    }
    for _, color in ipairs(CommanderConsole_Colors or {}) do
        -- Console's parentheticals ("Steel (Default)") describe Console,
        -- not Meters — strip them
        accentOptions[#accentOptions + 1] = {
            text = (color.text or color.value):gsub("%s*%(.-%)$", ""),
            value = color.value,
        }
    end
    -- A saved suite tint with Console gone must still label the dropdown
    -- (the framework shows "" for a value it has no option for). The
    -- window already falls back to amber; the label says why.
    do
        local saved = CommanderMetersDB.AccentColor
        local known = false
        for _, opt in ipairs(accentOptions) do
            if opt.value == saved then known = true end
        end
        if saved and not known then
            accentOptions[#accentOptions + 1] = {
                text = tostring(saved):sub(1, 1):upper() .. tostring(saved):sub(2):lower()
                    .. " (Commander_Console missing — shown as Amber)",
                value = saved,
            }
        end
    end

    panel:AddDropdownPair({
        label = "Accent Color",
        tooltip = "The single active/selected color in the chrome (segment dot, selections, header glyphs, graph hairline). Never touches class-colored bars. The suite tints match Commander_Console's palette so the whole HUD can agree; Class Color follows your class. " .. RELOAD_NOTE,
        options = accentOptions,
        get = function() return CommanderMetersDB.AccentColor end,
        set = function(value)
            if CommanderMetersDB.AccentColor ~= value then
                CommanderMetersDB.AccentColor = value
                NoteReload()
            end
        end,
        isEnabled = Enabled,
    }, {
        label = "Text Size",
        tooltip = "Base font size for the window and detail views. " .. RELOAD_NOTE,
        options = {
            { text = "Small (10)", value = 10 },
            { text = "Standard (11)", value = 11 },
            { text = "Large (12)", value = 12 },
        },
        get = function() return CommanderMetersDB.TextSize end,
        set = function(value)
            if CommanderMetersDB.TextSize ~= value then
                CommanderMetersDB.TextSize = value
                NoteReload()
            end
        end,
        isEnabled = Enabled,
    })

    panel:AddSliderPair({
        label = "Background Opacity",
        tooltip = "How solid the window fill is. Lower to see the world through the meter.",
        min = 0.2, max = 1.0, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderMetersDB.BgOpacity end,
        set = function(value) CommanderMetersDB.BgOpacity = value end,
        isEnabled = Enabled,
    }, {
        label = "Bar Opacity",
        tooltip = "How strong the class-colored bar fills are behind the text.",
        min = 0.10, max = 0.80, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderMetersDB.BarOpacity end,
        set = function(value) CommanderMetersDB.BarOpacity = value end,
        isEnabled = Enabled,
    })

    panel:AddCheckbox({
        label = "Click-Through When Locked",
        tooltip = "A locked window ignores the mouse on bars, panes, and the graph — clicks pass to the game world. The header strip and the split captions stay clickable so you can always reach the menus (and /cmeters lock, /cmeters unlock work regardless).",
        get = function() return CommanderMetersDB.ClickThrough end,
        set = function(value) CommanderMetersDB.ClickThrough = value end,
        isEnabled = Enabled,
    })

    panel:AddSection("Arena",
        "Arena matches are recorded as a whole: both teams, every seat, from the gates to the result — damage, healing, control with DR brackets, kicks, dispels, kills, mana, cooldowns — with a replayable timeline. The crossed-swords button in the meter window (or /cm arena) opens the report; ARENA modes in the meter window show both teams live.")

    panel:AddCheckbox({
        label = "Record Arena Matches",
        tooltip = "Record every arena match you play into the Arena Report. Off leaves the meter window's ordinary modes untouched and records nothing arena-specific. The report never opens on its own — the crossed-swords button in the meter window, /cm arena, or an ARENA row opens it.",
        get = function() return CommanderMetersDB.ArenaRecord end,
        set = function(value) CommanderMetersDB.ArenaRecord = value end,
        isEnabled = Enabled,
    })

    panel:AddSlider({
        label = "Keep Matches",
        tooltip = "How many past arena matches are saved when you log out or /reload, so a night of games can be reviewed later. With the replay's cast and aura logs a typical 3v3 weighs 200–400 KB on disk and a long 5v5 up to about 1 MB; six matches stay under a few megabytes. 0 keeps matches for this session only.",
        min = 0, max = 20, step = 1,
        format = "%d",
        get = function() return CommanderMetersDB.ArenaKeepMatches end,
        set = function(value) CommanderMetersDB.ArenaKeepMatches = value end,
        isEnabled = function() return Enabled() and CommanderMetersDB.ArenaRecord end,
    })

    panel:AddButtonRow({
        {
            label = "Arena Report",
            tooltip = "Open the Arena Report (same as /cm arena).",
            onClick = function() if CommanderMeters_ArenaToggle then CommanderMeters_ArenaToggle() end end,
        },
        {
            label = "Test Match",
            tooltip = "Inject a canned 3v3 through the real arena engine so the report has a match to show (same as /cm arenatest).",
            onClick = function() if CommanderMeters_ArenaTest then CommanderMeters_ArenaTest() end end,
        },
        {
            label = "Forget Matches",
            tooltip = "Drop every recorded arena match, including the saved history.",
            onClick = function() if CommanderMeters_ArenaForget then CommanderMeters_ArenaForget() end end,
        },
    })

    panel:AddSection("Auto Reset",
        "Each trigger wipes ALL meter data — Overall, every saved fight, graphs, and death logs — exactly like the window's RESET › EVERYTHING. All off by default.")

    panel:AddCheckboxPair({
        label = "On New Fight",
        tooltip = "Wipe everything when a new fight starts, so the meter only ever shows the pull you are on.",
        get = function() return CommanderMetersDB.AutoResetOnNewFight end,
        set = function(value) CommanderMetersDB.AutoResetOnNewFight = value end,
        isEnabled = Enabled,
    }, {
        label = "On Entering an Instance",
        tooltip = "Wipe everything when you enter a dungeon, raid, or battleground.",
        get = function() return CommanderMetersDB.AutoResetOnInstance end,
        set = function(value) CommanderMetersDB.AutoResetOnInstance = value end,
        isEnabled = Enabled,
    })

    panel:AddCheckbox({
        label = "On Ready Check",
        tooltip = "Wipe everything when a ready check starts.",
        get = function() return CommanderMetersDB.AutoResetOnReadyCheck end,
        set = function(value) CommanderMetersDB.AutoResetOnReadyCheck = value end,
        isEnabled = Enabled,
    })

    panel:AddButtonRow({
        {
            label = "Show / Hide Window",
            tooltip = "Toggle the meter window (same as bare /cmeters).",
            onClick = function() if CommanderMeters_Toggle then CommanderMeters_Toggle() end end,
        },
        {
            label = "Test Fight",
            tooltip = "Inject a small canned fight (crits, a pet, an interrupt, a death) through the real parser so every view has something to show. RESET › EVERYTHING clears it.",
            onClick = function() if CommanderMeters_Test then CommanderMeters_Test() end end,
        },
    })

    -- Chrome last, per the suite convention
    panel:AddSection("Frame")
    Commander.UI.AddHudChromeOptions(panel, CommanderMetersDB, "Hud", {
        isEnabled = Enabled,
        onChanged = function() Commander.Notify(COMMANDER_METERS_EVENTS.UPDATE) end,
        defaultPoint = { point = "RIGHT", x = -46, y = -60 },
    })

    panel:Finalize({
        onDefaults = Reset,
        defaultsTooltip = "Reset every option on this page to its default value. Meter DATA is untouched — that is what the window's RESET button (or /cmeters wipe) is for.",
    })
end

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Commander_Meters" then
        Migrate(CommanderMetersDB)
        Commander.UI.ApplyDefaults(CommanderMetersDB, DefaultSettings)
        frame:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateCorePanel()
    end
end)
