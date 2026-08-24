CommanderDossierDB = _G.CommanderDossierDB or {}
CommanderDossierFile = _G.CommanderDossierFile or {}

COMMANDER_DOSSIER_EVENTS = {
    UPDATE = "COMMANDER_DOSSIER_UPDATE"
}

-- ---------------------------------------------------------------------------
-- Schema versioning: the Meters ladder. DBVersion is deliberately NOT a
-- default, so Restore Defaults can never un-migrate a database.
-- ---------------------------------------------------------------------------

local DB_VERSION = 1
local MIGRATIONS = {}

local function Migrate(db)
    local v = tonumber(db.DBVersion) or DB_VERSION
    while v < DB_VERSION do
        local step = MIGRATIONS[v]
        if step then step(db) end
        v = v + 1
    end
    db.DBVersion = DB_VERSION
end

-- Settings live here; INTELLIGENCE lives in CommanderDossierFile. Two saved
-- variables on purpose (the Quartermaster ledger precedent): restoring
-- settings must never cost you months of gathered records.
local DefaultSettings = {
    EnableDossier = true,
    BoardMode = "ENEMIES",     -- ENEMIES | ALLIES | BOTH | HIDDEN
    ShowAllCategories = false, -- dim pips for categories with no window open
    BarRows = 5,
    FrameWidth = 300,
    CombatOnly = true,
    ImmuneWarn = true,         -- klaxon + flash when a category goes immune
    RecordIntel = true,        -- master switch for the persistent file
    KeepDays = 180,            -- 0 = keep forever; annotated records always kept
    AccentColor = "AMBER",     -- bake-at-login, the Threat/Meters precedent
}
for key, value in pairs(Commander.UI.HudChromeDefaults("Hud", "DARK")) do
    DefaultSettings[key] = value
end

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    local needsReload = CommanderDossierDB.AccentColor ~= DefaultSettings.AccentColor
    Commander.UI.ResetToDefaults(CommanderDossierDB, DefaultSettings)
    Commander.Notify(COMMANDER_DOSSIER_EVENTS.UPDATE)
    print("Commander Dossier: settings restored to defaults (the file is untouched)")
    if needsReload then
        print("|cff66ccffCommander Dossier|r: accent change applies after /reload")
    end
end

local function Enabled()
    return CommanderDossierDB.EnableDossier
end

local function BoardShown()
    return CommanderDossierDB.EnableDossier and CommanderDossierDB.BoardMode ~= "HIDDEN"
end

-- The chrome block pushes this page past the Settings canvas, so its rows
-- flow into a scroll frame — AddRow overridden on the panel INSTANCE only
-- (the Reticle/Quartermaster/Meters/Threat pattern).
local function MakeScrollable(panel, frameName)
    local scroll = CreateFrame("ScrollFrame", frameName, panel, "UIPanelScrollFrameTemplate")
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
    scroll:SetScript("OnSizeChanged", function(_, width) scrollChild:SetWidth(width) end)

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

    return function()
        scrollChild:SetHeight(panel._contentHeight + 24)
    end
end

local RELOAD_NOTE = "Takes effect after /reload (baked into the board at login)."

local function KeepDaysFormat(value)
    if value <= 0 then return "Forever" end
    return string.format("%d days", value)
end

local function CreatePanel()
    local panel = Commander.UI.NewPanel({
        key = "Dossier",
        title = "Dossier",
        addonName = "Commander_Dossier",
        description = "Intelligence on the enemy — the only module in the suite that faces outward. The board tracks diminishing returns live: one row per player, one pip per category, each saying what your NEXT crowd control in that category will land at and how long until the window resets. The file remembers the players themselves: class, race, guild, every spell of theirs you have witnessed, the specialisation that implies, and your own record against them. Nothing leaves your client.",
        event = COMMANDER_DOSSIER_EVENTS.UPDATE,
        slash = { "/cdossier", "/cdoss" },
        slashHandlers = {
            [""] = function()
                if CommanderDossier_ToggleFile then CommanderDossier_ToggleFile() end
            end,
            test = function() if CommanderDossier_Test then CommanderDossier_Test() end end,
            report = function() if CommanderDossier_Report then CommanderDossier_Report() end end,
            board = function() if CommanderDossier_ToggleBoard then CommanderDossier_ToggleBoard() end end,
            wipe = function() if CommanderDossier_Wipe then CommanderDossier_Wipe() end end,
        },
    })
    local finishScroll = MakeScrollable(panel, "CommanderDossierPanelScroll")

    panel:AddSection("Dossier")

    panel:AddCheckbox({
        label = "Enable Dossier",
        tooltip = "Master switch. Off stops all combat-log watching: no diminishing-return tracking, no board, and nothing new written to the file. What you have already gathered is kept.",
        get = function() return CommanderDossierDB.EnableDossier end,
        set = function(value) CommanderDossierDB.EnableDossier = value end,
    })

    panel:AddSection("Diminishing Returns",
        "Windows are per player, per category, and the reset clock starts when the effect FADES — not when it lands. Three applications and the fourth is an immunity. Against creatures only stuns and Kidney Shot diminish at all, and the board will not pretend otherwise.")

    panel:AddDropdown({
        label = "Board",
        tooltip = "Whose windows to draw. Enemies answers 'can I re-CC this target'. Allies answers 'will their next fear land full on my healer' — the same facts read from the other side. Both stacks them, hostile rows first. Hidden retires the board and leaves the file and the immunity warning to carry the module.",
        options = {
            { text = "Enemies", value = "ENEMIES" },
            { text = "Allies", value = "ALLIES" },
            { text = "Both", value = "BOTH" },
            { text = "Hidden", value = "HIDDEN" },
        },
        get = function() return CommanderDossierDB.BoardMode end,
        set = function(value) CommanderDossierDB.BoardMode = value end,
        isEnabled = Enabled,
    })

    panel:AddCheckboxPair({
        label = "Show All Categories",
        tooltip = "Draw every diminishing-return category on every row, dimmed until a window opens. Off shows only the categories actually diminishing, so a fresh target is an empty row and a chain-CCed healer is a wall of colour — the density of the board becomes the read.",
        get = function() return CommanderDossierDB.ShowAllCategories end,
        set = function(value) CommanderDossierDB.ShowAllCategories = value end,
        isEnabled = BoardShown,
    }, {
        label = "Only In Combat",
        tooltip = "Show the board only while you are in combat. Off keeps it up whenever anything is diminishing. An unlocked board always shows so you can place it.",
        get = function() return CommanderDossierDB.CombatOnly end,
        set = function(value) CommanderDossierDB.CombatOnly = value end,
        isEnabled = BoardShown,
    })

    panel:AddCheckbox({
        label = "Immunity Warning",
        tooltip = "A raid-warning klaxon and a brief screen flash the moment a category goes immune on somebody — the point at which continuing to cast that school of crowd control is a wasted global. Fires once per category per target, not per attempt.",
        get = function() return CommanderDossierDB.ImmuneWarn end,
        set = function(value) CommanderDossierDB.ImmuneWarn = value end,
        isEnabled = Enabled,
    })

    panel:AddSliderPair({
        label = "Board Rows",
        tooltip = "How many players the board draws at once. The busiest rows win — most categories diminishing first, then most recently touched.",
        min = 2, max = 10, step = 1,
        format = "%d",
        get = function() return CommanderDossierDB.BarRows end,
        set = function(value) CommanderDossierDB.BarRows = value end,
        isEnabled = BoardShown,
    }, {
        label = "Board Width",
        tooltip = "Width of the board in pixels. The category pips wrap to fit it.",
        min = 200, max = 420, step = 20,
        format = "%d",
        get = function() return CommanderDossierDB.FrameWidth end,
        set = function(value) CommanderDossierDB.FrameWidth = value end,
        isEnabled = BoardShown,
    })

    panel:AddSection("The File",
        "Records are account-wide and keyed by name and realm. They are yours alone — the module never sends anyone's record anywhere, and never names a player in chat.")

    panel:AddCheckbox({
        label = "Record Intelligence",
        tooltip = "Keep a persistent record of every enemy player the combat log names: class, race, guild, level, the spells you have watched them use, and your own kills and deaths against them. Off leaves the live board working and writes nothing new to disk.",
        get = function() return CommanderDossierDB.RecordIntel end,
        set = function(value) CommanderDossierDB.RecordIntel = value end,
        isEnabled = Enabled,
    })

    panel:AddSlider({
        label = "Keep Records For",
        tooltip = "Age out records nobody has seen in this long, at login. A record you have written a note on is NEVER pruned — the note is the reason it exists. Set to Forever to keep everything.",
        min = 0, max = 365, step = 30,
        format = KeepDaysFormat,
        get = function() return CommanderDossierDB.KeepDays end,
        set = function(value) CommanderDossierDB.KeepDays = value end,
        isEnabled = function()
            return CommanderDossierDB.EnableDossier and CommanderDossierDB.RecordIntel
        end,
    })

    panel:AddButtonRow({
        {
            label = "Open File",
            tooltip = "Open the dossier window: every player you have met, searchable, with their inferred specialisation and your record against them. Same as /cdossier.",
            onClick = function()
                if CommanderDossier_ToggleFile then CommanderDossier_ToggleFile() end
            end,
        },
        {
            label = "Test Board",
            tooltip = "Run a scripted arena opener through the real ingest path — a stun chain onto one target, a fear chain onto another — so you can see every diminishing state and the immunity warning without finding a duel partner. Same as /cdossier test.",
            onClick = function() if CommanderDossier_Test then CommanderDossier_Test() end end,
        },
    })

    panel:AddButtonRow({
        {
            label = "Report",
            tooltip = "Print a summary of the file to chat: how many players you have met, your overall record, and the one who has killed you most. Same as /cdossier report.",
            onClick = function() if CommanderDossier_Report then CommanderDossier_Report() end end,
        },
        {
            label = "Wipe The File",
            tooltip = "Delete every intelligence record, permanently. Asks first. Settings are untouched — and Restore Defaults, below, never touches the file.",
            onClick = function() if CommanderDossier_Wipe then CommanderDossier_Wipe() end end,
        },
    })

    panel:AddSection("Appearance")

    -- Accent choices: the local five plus every suite tint from
    -- Commander_Console (the TopBar pattern), so the whole suite can match
    -- from one named palette.
    local accentOptions = {
        { text = "Amber", value = "AMBER" },
        { text = "Cyan", value = "CYAN" },
        { text = "Green", value = "GREEN" },
        { text = "Red", value = "RED" },
        { text = "White", value = "WHITE" },
    }
    for _, color in ipairs(CommanderConsole_Colors or {}) do
        accentOptions[#accentOptions + 1] = {
            text = (color.text or color.value):gsub("%s*%(.-%)$", ""),
            value = color.value,
        }
    end
    do
        local saved = CommanderDossierDB.AccentColor
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

    panel:AddDropdown({
        label = "Accent Color",
        tooltip = "The single active colour in the chrome (header rule, headings, selection). Never touches the class-coloured names or the diminishing-state colours, which carry data. " .. RELOAD_NOTE,
        options = accentOptions,
        get = function() return CommanderDossierDB.AccentColor end,
        set = function(value)
            if CommanderDossierDB.AccentColor ~= value then
                CommanderDossierDB.AccentColor = value
                print("|cff66ccffCommander Dossier|r: accent change applies after /reload")
            end
        end,
        isEnabled = Enabled,
    })

    -- Chrome last, per the suite convention
    panel:AddSection("Frame")
    Commander.UI.AddHudChromeOptions(panel, CommanderDossierDB, "Hud", {
        isEnabled = BoardShown,
        onChanged = function() Commander.Notify(COMMANDER_DOSSIER_EVENTS.UPDATE) end,
        defaultPoint = { point = "RIGHT", x = -40, y = 120 },
    })

    panel:Finalize({
        onDefaults = Reset,
        defaultsTooltip = "Reset every option on this page to its default value. Your intelligence records are NOT touched — only Wipe The File can remove those.",
    })
    finishScroll()
end

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Commander_Dossier" then
        Migrate(CommanderDossierDB)
        Commander.UI.ApplyDefaults(CommanderDossierDB, DefaultSettings)
        CommanderDossierFile.Chars = CommanderDossierFile.Chars or {}
        frame:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreatePanel()
    end
end)
