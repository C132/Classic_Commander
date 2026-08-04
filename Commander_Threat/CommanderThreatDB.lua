CommanderThreatDB = _G.CommanderThreatDB or {}

COMMANDER_THREAT_EVENTS = {
    UPDATE = "COMMANDER_THREAT_UPDATE"
}

-- ---------------------------------------------------------------------------
-- Schema versioning: the Meters ladder, seeded at v1 so a future reshape can
-- rename or retype keys without ever losing a user's setup.
-- ---------------------------------------------------------------------------

local DB_VERSION = 1
local MIGRATIONS = {
    -- v1 is the original release; future reshapes slot in here.
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

-- The settings list is DERIVED, not accumulated — the derivation lives in
-- DECISIONS.md D3 and the ceiling is 10. Role is the tenth: it lives in the
-- per-character RoleByChar map below, deliberately OUTSIDE this table so
-- Restore Defaults never wipes a character's role (the Orders rally-point
-- precedent for prized per-character state).
local DefaultSettings = {
    EnableThreat = true,
    WarnAt = 80,           -- warning threshold, role-contextual: your pull %
                           -- (Damage/Healer) or the chaser's % of you (Tank)
    WarnSound = true,      -- raid-warning klaxon on any threat alert
    WarnFlash = true,      -- full-screen red vignette pulse on any alert
    ShowTPS = true,        -- threat-per-second column on the bars
    BarRows = 8,           -- bar rows on the board (Meters' Bar Rows)
    FrameWidth = 240,      -- board width in pixels (Meters' Window Width)
    CombatOnly = true,     -- board shows only in combat / while threat exists
    BoardLayout = "FULL",  -- FULL | COMPACT | HIDDEN — the standalone board's
                           -- density, or no standalone board at all
    TargetEmbed = "OFF",   -- OFF | BAR | TEXT | BOTH — the role-adaptive
                           -- readout drawn on Blizzard's target frame
    MetersEmbed = false,   -- render inside Commander_Meters as a live THREAT
                           -- pane instead of the standalone board
    AccentColor = "AMBER", -- AMBER | CYAN | GREEN | RED | WHITE, or any
                           -- Commander_Console suite tint — bake-at-login
}
for key, value in pairs(Commander.UI.HudChromeDefaults("Hud", "DARK")) do
    DefaultSettings[key] = value
end

-- ---------------------------------------------------------------------------
-- Role storage: one role per CHARACTER (a tank alt and a healer main must
-- never share it), keyed Name-Realm in the account-wide DB.
-- ---------------------------------------------------------------------------

local VALID_ROLES = { TANK = true, DAMAGE = true, HEALER = true }

local function RoleKey()
    local name = UnitName("player")
    local realm = GetRealmName and GetRealmName() or ""
    return (name or "?") .. "-" .. (realm or "")
end

function CommanderThreat_GetRole()
    local map = CommanderThreatDB.RoleByChar
    local role = map and map[RoleKey()]
    if role and VALID_ROLES[role] then
        return role
    end
    return "DAMAGE"
end

function CommanderThreat_SetRole(role)
    if not VALID_ROLES[role] then return end
    CommanderThreatDB.RoleByChar = CommanderThreatDB.RoleByChar or {}
    if CommanderThreatDB.RoleByChar[RoleKey()] == role then return end
    CommanderThreatDB.RoleByChar[RoleKey()] = role
    print("Commander Threat: role set to " .. role:sub(1, 1) .. role:sub(2):lower())
    Commander.Notify(COMMANDER_THREAT_EVENTS.UPDATE)
end

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    -- ResetToDefaults bypasses the widgets' set() closures, so the
    -- bake-at-login accent needs its reload hint issued here. RoleByChar is
    -- not in DefaultSettings, so every character's role survives the reset.
    local needsReload = CommanderThreatDB.AccentColor ~= DefaultSettings.AccentColor
    Commander.UI.ResetToDefaults(CommanderThreatDB, DefaultSettings)
    Commander.Notify(COMMANDER_THREAT_EVENTS.UPDATE)
    print("Commander Threat: settings restored to defaults (roles kept)")
    if needsReload then
        print("|cff66ccffCommander Threat|r: accent change applies after /reload")
    end
end

local function Enabled()
    return CommanderThreatDB.EnableThreat
end

-- The chrome block pushes this page past the Settings canvas, so its rows
-- flow into a scroll frame — AddRow overridden on the panel INSTANCE only
-- (the Reticle/Quartermaster/Meters pattern).
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

local function CreateCorePanel()
    local panel = Commander.UI.NewPanel({
        key = "Threat",
        title = "Threat",
        addonName = "Commander_Threat",
        description = "Role-adaptive threat meter. Pick your role and the board reshapes around it: damage dealers and healers watch their distance to pulling aggro (full bar width IS the pull point — the 110% melee / 130% ranged thresholds are already folded in), tanks watch their grip, the closest chaser, and how many engaged mobs they actually hold. Warnings are edge-triggered: one klaxon at the threshold, a louder one when aggro actually moves. Where it draws is yours to pick — the full board, a compact one, a readout on your target frame, a pane inside Commander Meters, or nothing but the warnings.",
        event = COMMANDER_THREAT_EVENTS.UPDATE,
        slash = { "/cthreat", "/ct" },
        slashHandlers = {
            test = function() if CommanderThreat_Test then CommanderThreat_Test() end end,
            tank = function() CommanderThreat_SetRole("TANK") end,
            damage = function() CommanderThreat_SetRole("DAMAGE") end,
            healer = function() CommanderThreat_SetRole("HEALER") end,
        },
    })
    local finishScroll = MakeScrollable(panel, "CommanderThreatCoreScroll")

    panel:AddSection("Threat")

    panel:AddCheckbox({
        label = "Enable Threat",
        tooltip = "Master switch. Off stops all threat sampling and hides the board.",
        get = function() return CommanderThreatDB.EnableThreat end,
        set = function(value) CommanderThreatDB.EnableThreat = value end,
    })

    panel:AddDropdown({
        label = "Role",
        tooltip = "Which side of threat this CHARACTER manages — each character keeps its own. Damage and Healer watch their climb toward pulling aggro; Tank watches the grip and whoever is climbing toward them. Also switchable from the board's header tag and /cthreat tank, damage, healer.",
        options = {
            { text = "Tank", value = "TANK" },
            { text = "Damage", value = "DAMAGE" },
            { text = "Healer", value = "HEALER" },
        },
        get = function() return CommanderThreat_GetRole() end,
        set = function(value) CommanderThreat_SetRole(value) end,
        isEnabled = Enabled,
    })

    panel:AddSection("Warnings",
        "One threshold, read through your role: as Damage or Healer it is YOUR percentage toward pulling; as Tank it is the closest chaser's percentage toward pulling off you.")

    panel:AddSlider({
        label = "Warn At",
        tooltip = "Threshold that arms the warning (flash, klaxon, vignette). It re-arms after falling 10 points back below, so a value jittering across the line alarms once, not per tick.",
        min = 50, max = 100, step = 5,
        format = "%d%%",
        get = function() return CommanderThreatDB.WarnAt end,
        set = function(value) CommanderThreatDB.WarnAt = value end,
        isEnabled = Enabled,
    })

    panel:AddCheckboxPair({
        label = "Warning Sound",
        tooltip = "The raid-warning klaxon on any threat alert. An alarm has one correct sound, so there is no chime list here.",
        get = function() return CommanderThreatDB.WarnSound end,
        set = function(value) CommanderThreatDB.WarnSound = value end,
        isEnabled = Enabled,
    }, {
        label = "Screen Flash",
        tooltip = "A brief red vignette pulse at the screen edges on any threat alert — stronger when aggro actually moves than when you are merely approaching the line.",
        get = function() return CommanderThreatDB.WarnFlash end,
        set = function(value) CommanderThreatDB.WarnFlash = value end,
        isEnabled = Enabled,
    })

    panel:AddSection("Display")

    panel:AddCheckboxPair({
        label = "Show TPS",
        tooltip = "Per-bar threat-per-second column (a short moving average). Off gives the name column the room back.",
        get = function() return CommanderThreatDB.ShowTPS end,
        set = function(value) CommanderThreatDB.ShowTPS = value end,
        isEnabled = Enabled,
    }, {
        label = "Only In Combat",
        tooltip = "Show the board only while you are in combat or a threat list still exists. Off keeps it on screen all the time. An unlocked board always shows so you can place it (a Hidden board stays hidden — there is nothing to place).",
        get = function() return CommanderThreatDB.CombatOnly end,
        set = function(value) CommanderThreatDB.CombatOnly = value end,
        isEnabled = Enabled,
    })

    panel:AddDropdownPair({
        label = "Board Layout",
        tooltip = "How much board to draw. Full is the standard one: the big headline percentage, its label (your chaser as a tank, your peak mob as a healer), the mob name, the bars, and the footer fact. Compact folds that headline up into the header strip at reading size and tightens every row — about a third less height for the same facts, minus the mob name (your target frame already says it). Hidden retires the board outright and leaves the warnings and the target-frame readout to carry the module.",
        options = {
            { text = "Full", value = "FULL" },
            { text = "Compact", value = "COMPACT" },
            { text = "Hidden", value = "HIDDEN" },
        },
        get = function() return CommanderThreatDB.BoardLayout end,
        set = function(value) CommanderThreatDB.BoardLayout = value end,
        isEnabled = Enabled,
    }, {
        label = "Target Frame",
        tooltip = "Also draw your threat number on Blizzard's target frame, where you are already looking. Bar is a slim fill along the bottom of the target's health bar — full width IS the pull point, exactly like the board's bars. Text is the percentage above the health bar's right end, reading AGGRO once the mob is yours. Bar + Text draws both. It is role-adaptive like everything else: Damage and Healer see their own climb, a tank sees the chaser's climb while holding and their own climb to take it back when not. Shown only for an attackable target you actually have a threat list on.",
        options = {
            { text = "Off", value = "OFF" },
            { text = "Bar", value = "BAR" },
            { text = "Text", value = "TEXT" },
            { text = "Bar + Text", value = "BOTH" },
        },
        get = function() return CommanderThreatDB.TargetEmbed end,
        set = function(value) CommanderThreatDB.TargetEmbed = value end,
        isEnabled = Enabled,
    })

    panel:AddCheckbox({
        label = "Embed in Commander Meters",
        tooltip = "Retire the standalone board and show the threat list as a live THREAT pane inside Commander Meters instead: enabling opens Meters' split view with threat in the second pane, and Meters' pane menus offer THREAT from then on. Every warning — klaxon, board flash, screen vignette — keeps firing either way; only the surface moves. Needs Commander_Meters (grayed out without it).",
        get = function() return CommanderThreatDB.MetersEmbed end,
        set = function(value)
            CommanderThreatDB.MetersEmbed = value
            if CommanderThreat_EmbedToggled then CommanderThreat_EmbedToggled(value) end
        end,
        isEnabled = function()
            return CommanderThreatDB.EnableThreat
                and CommanderMeters_RegisterExternalMode ~= nil
        end,
    })

    panel:AddSliderPair({
        label = "Bar Rows",
        tooltip = "How many bars the board shows. Everyone is still tracked; the wheel scrolls the rest, and your own row is always visible.",
        min = 4, max = 15, step = 1,
        format = "%d",
        get = function() return CommanderThreatDB.BarRows end,
        set = function(value) CommanderThreatDB.BarRows = value end,
        isEnabled = Enabled,
    }, {
        label = "Window Width",
        tooltip = "Width of the board in pixels.",
        min = 200, max = 340, step = 10,
        format = "%d",
        get = function() return CommanderThreatDB.FrameWidth end,
        set = function(value) CommanderThreatDB.FrameWidth = value end,
        isEnabled = Enabled,
    })

    -- Accent choices: Threat's own five plus every suite tint from
    -- Commander_Console (the TopBar pattern), so the whole suite can match
    -- from one named palette. Console absent → just the local five, and a
    -- saved suite key quietly resolves to amber on the board.
    local accentOptions = {
        { text = "Amber", value = "AMBER" },
        { text = "Cyan", value = "CYAN" },
        { text = "Green", value = "GREEN" },
        { text = "Red", value = "RED" },
        { text = "White", value = "WHITE" },
    }
    for _, color in ipairs(CommanderConsole_Colors or {}) do
        -- Console's parentheticals ("Steel (Default)") describe Console,
        -- not Threat — strip them
        accentOptions[#accentOptions + 1] = {
            text = (color.text or color.value):gsub("%s*%(.-%)$", ""),
            value = color.value,
        }
    end
    -- A saved suite tint with Console gone must still label the dropdown
    -- (the framework shows "" for a value it has no option for).
    do
        local saved = CommanderThreatDB.AccentColor
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
        tooltip = "The single active/selected color in the chrome (header rule, role tag, your rank). Never touches class-colored bars or the role-aware status colors. The suite tints match Commander_Console's palette; Class Color follows your class. " .. RELOAD_NOTE,
        options = accentOptions,
        get = function() return CommanderThreatDB.AccentColor end,
        set = function(value)
            if CommanderThreatDB.AccentColor ~= value then
                CommanderThreatDB.AccentColor = value
                print("|cff66ccffCommander Threat|r: accent change applies after /reload")
            end
        end,
        isEnabled = Enabled,
    })

    panel:AddButtonRow({
        {
            label = "Test Board",
            tooltip = "Run a scripted 12-second fake fight through the real ingest path for your CURRENT role — it walks the whole alert chain (approach, warn, aggro moving) so you can preview every warning. Same as /cthreat test.",
            onClick = function() if CommanderThreat_Test then CommanderThreat_Test() end end,
        },
    })

    -- Chrome last, per the suite convention
    panel:AddSection("Frame")
    Commander.UI.AddHudChromeOptions(panel, CommanderThreatDB, "Hud", {
        isEnabled = Enabled,
        onChanged = function() Commander.Notify(COMMANDER_THREAT_EVENTS.UPDATE) end,
        defaultPoint = { point = "LEFT", x = 46, y = -60 },
    })

    panel:Finalize({
        onDefaults = Reset,
        defaultsTooltip = "Reset every option on this page to its default value. Character roles are kept — only the role dropdown itself can change them.",
    })
    finishScroll()
end

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Commander_Threat" then
        Migrate(CommanderThreatDB)
        Commander.UI.ApplyDefaults(CommanderThreatDB, DefaultSettings)
        CommanderThreatDB.RoleByChar = CommanderThreatDB.RoleByChar or {}
        frame:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateCorePanel()
    end
end)
