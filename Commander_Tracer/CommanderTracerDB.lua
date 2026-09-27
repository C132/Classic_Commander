-- Commander Tracer: the saved variables and the settings page.
--
-- The defaults are the opinionated part. The opinion: the stock layout is
-- the right STARTING point (yours to the right, theirs to the left, rising
-- and falling), everything you land is worth a line, everything that
-- happens to you is worth a quieter one, and the moments -- a kill, an
-- interrupt, a proc -- are worth saying out loud. The ledger down the left
-- is the part the stock text never had: a column that holds each event
-- long enough to be read after the fact, the way a strategy game tells you
-- a building finished while you were looking elsewhere.
--
-- Every per-lane setting is stored as <lane><Setting> (OutFontSize,
-- LogMerge, ...) from one shared list, so the six lanes cannot drift apart
-- in what they offer; every event kind is stored as <kind>Lane and
-- <kind>Ledger. The settings-reach check in Harness/ enumerates all of it.

CommanderTracerDB = _G.CommanderTracerDB or {}

COMMANDER_TRACER_EVENTS = {
    UPDATE = "COMMANDER_TRACER_UPDATE"
}

local DATA = CommanderTracer_Data
local E = CommanderTracer_Engine

local DefaultSettings = {
    Enable = true,

    -- Blizzard's own text, switched off while this runs (and given back
    -- when it stops). Both on: this module IS the combat text.
    HideBlizzardWorldText = true,    -- the engine's numbers over units in the world
    HideBlizzardPlayerText = true,   -- Blizzard_CombatText scrolling round your character

    NumberStyle = "SEPARATED",       -- PLAIN | SEPARATED | SHORT
    Strata = "LOW",                  -- where the lanes draw: BACKGROUND | LOW | MEDIUM | HIGH
    BigHitThreshold = 0,             -- a non-crit at least this big gets the crit treatment. 0 = crits only
    PetTag = true,                   -- "Pet: " in front of a pet's numbers
    CritChimeFrom = 1500,            -- the Big Crit sound rings from this amount

    -- Bookkeeping, not on the page: the CVar values this module replaced,
    -- so they can be given back exactly.
    CVarBackup = {},
}

-- The lanes: the shared list, with the lane's own overrides
for _, lane in ipairs(DATA.LANES) do
    for key, value in pairs(DATA.LANE_DEFAULTS) do
        DefaultSettings[lane.key .. key] = value
    end
    DefaultSettings[lane.key .. "Motion"] = lane.motion
    DefaultSettings[lane.key .. "Direction"] = lane.direction
    DefaultSettings[lane.key .. "FontSize"] = lane.fontSize
    DefaultSettings[lane.key .. "ColorMode"] = lane.color
    DefaultSettings[lane.key .. "Format"] = lane.format
    DefaultSettings[lane.key .. "Icon"] = lane.icon
    for key, value in pairs(Commander.UI.HudChromeDefaults(lane.key, "NONE")) do
        DefaultSettings[key] = value
    end
end
-- The ledger and the callouts hold longer than a number does, and the
-- ledger merges by default (six Fireballs are one row with a count)
DefaultSettings.LogDuration = 6
DefaultSettings.LogMerge = 4
DefaultSettings.LogMaxLines = 7
DefaultSettings.LogSpread = 0
DefaultSettings.LogOutline = "NONE"
DefaultSettings.LogIconSize = 22
DefaultSettings.CallDuration = 2.6
DefaultSettings.CallMerge = 1
DefaultSettings.CallMaxLines = 4
DefaultSettings.CallSpread = 0
DefaultSettings.CallOutline = "THICK"
DefaultSettings.CallIconSize = 24
DefaultSettings.CallCritScale = 1.2
DefaultSettings.InSpread = 30
DefaultSettings.OutSpread = 30
DefaultSettings.HealMerge = 0.5
DefaultSettings.InHealMerge = 0.5
DefaultSettings.InHealFontSize = 15

-- The kinds: where each goes
for _, kind in ipairs(DATA.KINDS) do
    DefaultSettings[kind.key .. "Lane"] = kind.lane
    DefaultSettings[kind.key .. "Ledger"] = kind.ledger
end

-- The sounds
for _, slot in ipairs(DATA.SOUND_SLOTS) do
    DefaultSettings[slot.key] = slot.default
end

CommanderTracer_Defaults = DefaultSettings

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    -- The CVar backup is not a setting: resetting the page must not forget
    -- what Blizzard's values were
    local backup = CommanderTracerDB.CVarBackup
    Commander.UI.ResetToDefaults(CommanderTracerDB, DefaultSettings)
    CommanderTracerDB.CVarBackup = backup or {}
    Commander.Notify(COMMANDER_TRACER_EVENTS.UPDATE)
    print("Commander Tracer: settings restored to defaults")
end

local function Enabled()
    return CommanderTracerDB.Enable and true or false
end

local function Notify()
    Commander.Notify(COMMANDER_TRACER_EVENTS.UPDATE)
end

-- Console's palette, offered beside the module's own when it is loaded (the
-- TopBar pattern: read the global live, soft-fail without it). Console's
-- parentheticals are stripped and a saved key whose palette is gone gets
-- an orphan entry, or the dropdown would show a blank face.
local function ColorOptions(currentKey)
    local options, seen = {}, {}
    for _, c in ipairs(DATA.COLORS) do
        options[#options + 1] = { text = c.text, value = c.value }
        seen[c.value] = true
    end
    for _, c in ipairs(CommanderConsole_Colors or {}) do
        if c.r and not seen[c.value] then
            options[#options + 1] = { text = (c.text:gsub("%s*%b()", "")), value = c.value }
            seen[c.value] = true
        end
    end
    if currentKey and not seen[currentKey] then
        options[#options + 1] = { text = tostring(currentKey), value = currentKey }
    end
    return options
end

local LANE_OPTIONS = { { text = "Off", value = "OFF" } }
for _, lane in ipairs(DATA.LANES) do
    LANE_OPTIONS[#LANE_OPTIONS + 1] = { text = lane.short, value = lane.key }
end
-- Strings rather than booleans: Blizzard's dropdown skips its check mark
-- for a selected value of false
local LEDGER_OPTIONS = {
    { text = "Also a ledger row", value = "YES" },
    { text = "No ledger row", value = "NO" },
}

-- ---------------------------------------------------------------------------
-- The preview strip: one row per lane, drawn with the lane's own face, size,
-- outline and colour rule through the same engine calls the runtime uses,
-- so what the page shows is what the screen will show.
-- ---------------------------------------------------------------------------
local PREVIEW_H = 58
local WHITE = "Interface\\Buttons\\WHITE8X8"

local SAMPLE_HIT = { kind = "DamageDone", damage = true, amount = 1204, spellName = "Fireball", spellId = 27070, school = 4, target = "Gankmage", mergeKey = "x" }
local SAMPLE_CRIT = { kind = "DamageDone", damage = true, amount = 2410, crit = true, spellName = "Fireball", spellId = 27070, school = 4, target = "Gankmage" }
local SAMPLE_MISS = { kind = "MissDone", missType = "RESIST", spellName = "Frostbolt", spellId = 27072, school = 16, target = "Gankmage" }
local SAMPLE_BY_LANE = {
    Heal = {
        { kind = "HealDone", heal = true, amount = 1730, spellName = "Flash Heal", spellId = 25235, school = 2, target = "Leafheal" },
        { kind = "HealDone", heal = true, amount = 3120, crit = true, spellName = "Flash Heal", spellId = 25235, school = 2, target = "Leafheal" },
        { kind = "PeriodicHeal", heal = true, amount = 250, spellName = "Renew", spellId = 25222, school = 2, periodic = true, target = "Leafheal" },
    },
    In = {
        { kind = "DamageTaken", damage = true, amount = 618, spellName = "Mortal Strike", spellId = 30330, school = 1, source = "Bonecrush" },
        { kind = "DamageTaken", damage = true, amount = 1890, crit = true, spellName = "Frostbolt", spellId = 27072, school = 16, source = "Gankmage" },
        { kind = "MissTaken", missType = "DODGE", spellName = "Melee", school = 1, source = "Bonecrush" },
    },
    InHeal = {
        { kind = "HealTaken", heal = true, amount = 1450, spellName = "Flash of Light", spellId = 27137, school = 2, source = "Lightbringer" },
        { kind = "Energize", amount = 240, spellName = "Judgement of Wisdom", spellId = 27164, powerType = 0 },
        { kind = "Energize", amount = 10, spellName = "Bloodrage", spellId = 29131, powerType = 1 },
    },
    Call = {
        { kind = "KillingBlow", target = "Gankmage" },
        { kind = "Interrupt", spellName = "Polymorph", spellId = 12826, tool = "Kick", target = "Gankmage" },
        { kind = "ProcReady", spellName = "Overpower" },
    },
}

local function LaneValue(P, key)
    local v = CommanderTracerDB[P .. key]
    if v == nil then return DATA.LANE_DEFAULTS[key] end
    return v
end

local function LaneCfg(P)
    local cfg = {}
    for key in pairs(DATA.LANE_DEFAULTS) do cfg[key] = LaneValue(P, key) end
    return cfg
end

local function ApplyFace(fs, cfg, scale)
    local path = DATA.FONTS[cfg.Font] or DATA.FONTS.DEFAULT
    local size = math.max(6, math.floor((tonumber(cfg.FontSize) or 16) * (scale or 1) + 0.5))
    fs:SetFont(path, size, DATA.OUTLINES[cfg.Outline] or "OUTLINE")
    if fs.SetShadowOffset then
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, cfg.Shadow and 1 or 0)
    end
end

local function ClassColor()
    local _, class = UnitClass("player")
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return { c.r, c.g, c.b } end
    return nil
end

local function NewSample(row)
    local s = CreateFrame("Frame", nil, row)
    s:SetSize(120, 30)
    -- A font object at birth: SetText on a bare FontString is an error
    s.text = s:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    s.text:SetPoint("CENTER", s, "CENTER", 0, 0)
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetSize(16, 16)
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    s.icon:Hide()
    return s
end

local function PaintSample(s, P, cfg, rec, sizeScale)
    local main = E.Text(cfg, rec, CommanderTracerDB.NumberStyle, CommanderTracerDB.PetTag)
    ApplyFace(s.text, cfg, (rec.crit and (tonumber(cfg.CritScale) or 1.5) or 1) * (sizeScale or 1))
    s.text:SetText(main)
    local r, g, b = E.Color(cfg, rec, ClassColor(), CommanderConsole_Colors)
    s.text:SetTextColor(r, g, b)
    s.text:SetAlpha(tonumber(cfg.Alpha) or 1)
    s.icon:ClearAllPoints()
    local tex = rec.spellId and GetSpellTexture and GetSpellTexture(rec.spellId)
    if cfg.Icon ~= "NONE" and tex then
        s.icon:SetTexture(tex)
        local size = tonumber(cfg.IconSize) or 16
        s.icon:SetSize(size, size)
        if cfg.Icon == "RIGHT" then
            s.icon:SetPoint("LEFT", s.text, "RIGHT", 4, 0)
        else
            s.icon:SetPoint("RIGHT", s.text, "LEFT", -4, 0)
        end
        s.icon:Show()
    else
        s.icon:Hide()
    end
end

-- The ledger's preview is a row rather than a number: icon, main, sub, the
-- backdrop and the accent, exactly as the runtime lays one out
local function NewLedgerSample(row)
    local s = CreateFrame("Frame", nil, row)
    s:SetSize(260, 36)
    s.bg = s:CreateTexture(nil, "BACKGROUND")
    s.bg:SetTexture(WHITE)
    s.bg:SetAllPoints()
    s.accent = s:CreateTexture(nil, "BORDER")
    s.accent:SetTexture(WHITE)
    s.accent:SetWidth(3)
    s.accent:SetPoint("TOPLEFT", s, "TOPLEFT", 0, 0)
    s.accent:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 0, 0)
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    s.text = s:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    s.text:SetJustifyH("LEFT")
    s.text:SetWordWrap(false)
    s.sub = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.sub:SetJustifyH("LEFT")
    s.sub:SetWordWrap(false)
    return s
end

local function PaintLedgerSample(s, cfg, rec)
    local main, sub = E.Text(cfg, rec, CommanderTracerDB.NumberStyle, CommanderTracerDB.PetTag)
    local r, g, b = E.Color(cfg, rec, ClassColor(), CommanderConsole_Colors)
    local lineH = E.LineHeight(cfg)
    s:SetSize(math.min(tonumber(cfg.Width) or 260, 300), lineH)
    s.bg:SetVertexColor(0, 0, 0, cfg.RowBackdrop and 0.55 or 0)
    s.accent:SetVertexColor(r, g, b, cfg.RowAccent and 0.9 or 0)
    local iconSize = (cfg.Icon ~= "NONE") and (tonumber(cfg.IconSize) or 16) or 0
    s.icon:ClearAllPoints()
    s.text:ClearAllPoints()
    s.sub:ClearAllPoints()
    local tex = rec.spellId and GetSpellTexture and GetSpellTexture(rec.spellId)
    if iconSize > 0 and tex then
        s.icon:SetTexture(tex)
        s.icon:SetSize(iconSize, iconSize)
        if cfg.Icon == "RIGHT" then
            s.icon:SetPoint("RIGHT", s, "RIGHT", -6, 0)
            s.text:SetPoint("TOPLEFT", s, "TOPLEFT", 8, -4)
        else
            s.icon:SetPoint("LEFT", s, "LEFT", 7, 0)
            s.text:SetPoint("TOPLEFT", s, "TOPLEFT", 13 + iconSize, -4)
        end
        s.icon:Show()
    else
        s.icon:Hide()
        s.text:SetPoint("TOPLEFT", s, "TOPLEFT", 8, -4)
    end
    ApplyFace(s.text, cfg, 1)
    s.text:SetText(main)
    s.text:SetTextColor(r, g, b)
    s.text:SetPoint("RIGHT", s, "RIGHT", -8, 0)
    s.sub:SetPoint("TOPLEFT", s.text, "BOTTOMLEFT", 0, -1)
    s.sub:SetPoint("RIGHT", s, "RIGHT", -8, 0)
    if cfg.Sub ~= false and sub then
        ApplyFace(s.sub, cfg, 0.85)
        s.sub:SetText(sub)
        s.sub:SetTextColor(0.75, 0.75, 0.78)
        s.sub:Show()
    else
        s.sub:Hide()
    end
    s:SetAlpha(tonumber(cfg.Alpha) or 1)
end

local function AddLanePreview(panel, lane)
    local P = lane.key
    local row = panel:AddRow(PREVIEW_H, 8)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(WHITE)
    bg:SetVertexColor(0.05, 0.05, 0.05, 0.6)
    bg:SetAllPoints()
    local caption = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    caption:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 3)
    caption:SetText("Preview: a hit, a crit, a miss, in this lane's face and colours")
    local samples
    local ledger
    if P == "Log" then
        ledger = NewLedgerSample(row)
        ledger:SetPoint("LEFT", row, "LEFT", 12, 4)
        caption:SetText("Preview: one ledger row, as it lays out")
    else
        samples = {}
        for i = 1, 3 do
            samples[i] = NewSample(row)
            samples[i]:SetPoint("CENTER", row, "LEFT", 90 + (i - 1) * 190, 6)
        end
    end
    panel:AddRefresher(function()
        local cfg = LaneCfg(P)
        local recs = SAMPLE_BY_LANE[P] or { SAMPLE_HIT, SAMPLE_CRIT, SAMPLE_MISS }
        if ledger then
            PaintLedgerSample(ledger, cfg, SAMPLE_CRIT)
        else
            for i = 1, 3 do
                PaintSample(samples[i], P, cfg, recs[i], (P == "Call") and 0.7 or 1)
            end
        end
        row:SetAlpha(LaneValue(P, "Enable") and 1 or 0.4)
    end)
end

-- ---------------------------------------------------------------------------
-- Sections
-- ---------------------------------------------------------------------------

local function AddTakeoverSection(panel)
    panel:AddSection("Taking Over From Blizzard",
        "This client draws combat text twice: the engine's numbers over units out in the world, and the Blizzard_CombatText addon scrolling round your character. Both are switched off here while this module runs, and the values they had are written back the moment either box is unticked or the module is disabled, so nothing is lost by trying it.")
    panel:AddCheckboxPair({
        label = "Hide Blizzard's World Numbers",
        tooltip = "Switch off the engine's own damage and healing numbers over units in the world (the floatingCombatTextCombat* CVars: damage, healing, periodic, pet melee, pet spells). Their previous values are remembered and restored when this is unticked.",
        get = function() return CommanderTracerDB.HideBlizzardWorldText end,
        set = function(value) CommanderTracerDB.HideBlizzardWorldText = value end,
        isEnabled = Enabled,
    }, {
        label = "Hide Blizzard's Player Text",
        tooltip = "Switch off the scrolling combat text round your character (the enableFloatingCombatText CVar, which loads Blizzard_CombatText). Restored when unticked.",
        get = function() return CommanderTracerDB.HideBlizzardPlayerText end,
        set = function(value) CommanderTracerDB.HideBlizzardPlayerText = value end,
        isEnabled = Enabled,
    })
end

local function AddNumbersSection(panel)
    panel:AddSection("Numbers & Layers",
        "How every amount is written, where the lanes sit among the other frames, and what counts as a big hit.")
    panel:AddDropdownPair({
        label = "Number Style",
        tooltip = "Plain writes 1204; Separated writes 1,204; Short writes 12.3k from ten thousand up (and 1,204 below it).",
        options = DATA.NUMBER_STYLES,
        get = function() return CommanderTracerDB.NumberStyle end,
        set = function(value) CommanderTracerDB.NumberStyle = value end,
        isEnabled = Enabled,
    }, {
        label = "Draw Layer",
        tooltip = "Which layer the lanes draw on. Under Windows keeps the numbers beneath your bags and the settings window; Over the Frames puts them on top of unit frames and action bars too.",
        options = DATA.STRATA,
        get = function() return CommanderTracerDB.Strata end,
        set = function(value) CommanderTracerDB.Strata = value end,
        isEnabled = Enabled,
    })
    panel:AddSlider({
        label = "Big Hit Threshold",
        tooltip = "A hit or heal of yours at least this large gets the crit treatment (the size, the mark, the punch) even when it did not crit. 0 keeps that for real crits only.",
        min = 0, max = 6000, step = 100,
        format = function(v) if v == 0 then return "crits only" end return string.format("%d", v) end,
        get = function() return CommanderTracerDB.BigHitThreshold end,
        set = function(value) CommanderTracerDB.BigHitThreshold = value end,
        isEnabled = Enabled,
    })
    panel:AddCheckbox({
        label = "Tag Pet Numbers",
        tooltip = "Write 'Pet:' in front of anything your pet lands, so a hunter's or a warlock's two streams of numbers cannot be mistaken for one.",
        get = function() return CommanderTracerDB.PetTag end,
        set = function(value) CommanderTracerDB.PetTag = value end,
        isEnabled = Enabled,
    })
end

local function AddRoutingSections(panel)
    for _, group in ipairs(DATA.KIND_GROUPS) do
        panel:AddSection(group.title, group.note)
        for _, kind in ipairs(DATA.KINDS) do
            if kind.group == group.key then
                panel:AddDropdownPair({
                    label = kind.label,
                    tooltip = kind.tip .. "|n|nWhich lane draws it. Off draws nothing in a lane (a ledger row is still possible on the right).",
                    options = LANE_OPTIONS,
                    get = function() return CommanderTracerDB[kind.key .. "Lane"] end,
                    set = function(value) CommanderTracerDB[kind.key .. "Lane"] = value end,
                    isEnabled = Enabled,
                }, {
                    label = "Ledger Row",
                    tooltip = "Whether a " .. kind.label:lower() .. " event also gets a row in the ledger, the lingering column down the left. Not needed when its lane above IS the ledger.",
                    options = LEDGER_OPTIONS,
                    get = function() return CommanderTracerDB[kind.key .. "Ledger"] and "YES" or "NO" end,
                    set = function(value) CommanderTracerDB[kind.key .. "Ledger"] = (value == "YES") end,
                    isEnabled = function() return Enabled() and CommanderTracerDB[kind.key .. "Lane"] ~= "Log" end,
                })
            end
        end
    end
end

local function AddLaneSection(panel, lane)
    local P = lane.key
    panel:AddSection(lane.title, lane.note)
    AddLanePreview(panel, lane)

    local function On() return Enabled() and LaneValue(P, "Enable") and true or false end
    local function Motion() return LaneValue(P, "Motion") end
    local function IsStack() return On() and Motion() == "STACK" end
    local function IsScroll() return On() and (Motion() == "SCROLL" or Motion() == "FOUNTAIN") end
    local function IsFountain() return On() and Motion() == "FOUNTAIN" end
    local function NotStack() return On() and Motion() ~= "STACK" end

    panel:AddCheckbox({
        label = "Enable " .. lane.short,
        tooltip = "Draw this lane at all. A kind routed to a disabled lane simply does not appear.|n|nA locked lane never takes the mouse (so a right-click camera turn always starts, even over its anchor); unlock it from the button here or with /ctracer unlock rather than by triple right-click.",
        get = function() return CommanderTracerDB[P .. "Enable"] end,
        set = function(value) CommanderTracerDB[P .. "Enable"] = value end,
        isEnabled = Enabled,
    })
    Commander.UI.AddHudChromeOptions(panel, CommanderTracerDB, P, {
        isEnabled = On,
        onChanged = Notify,
    })
    panel:AddDropdownPair({
        label = "Motion",
        tooltip = "How an entry moves through its life.|n|nScroll: rises or falls at a steady speed.|nFountain: thrown out in an arc, alternating sides.|nPop: appears in place with a punch, holds, fades; newer ones stack.|nStack: a column of rows, newest first, that slide in and shove the rest along (the ledger's motion).",
        options = DATA.MOTIONS,
        get = function() return CommanderTracerDB[P .. "Motion"] end,
        set = function(value) CommanderTracerDB[P .. "Motion"] = value end,
        isEnabled = On,
    }, {
        label = "Direction",
        tooltip = "Scroll: which way it travels. Pop and Stack: which way newer entries pile (Down means new ones sit under the old, or for a stack, that the column grows downward from its anchor with the newest at the top).",
        options = DATA.DIRECTIONS,
        get = function() return CommanderTracerDB[P .. "Direction"] end,
        set = function(value) CommanderTracerDB[P .. "Direction"] = value end,
        isEnabled = On,
    })
    panel:AddDropdownPair({
        label = "Fountain Side",
        tooltip = "Fountain only: which side the arc is thrown to. Alternate takes turns.",
        options = DATA.SIDES,
        get = function() return CommanderTracerDB[P .. "Side"] end,
        set = function(value) CommanderTracerDB[P .. "Side"] = value end,
        isEnabled = IsFountain,
    }, {
        label = "Text",
        tooltip = "What each entry says: the amount alone, with the spell before or after it, with the target, or all of it. In a stack lane whatever is not in the main line goes on the small line under it.",
        options = DATA.FORMATS,
        get = function() return CommanderTracerDB[P .. "Format"] end,
        set = function(value) CommanderTracerDB[P .. "Format"] = value end,
        isEnabled = On,
    })
    panel:AddSliderPair({
        label = "Duration",
        tooltip = "Seconds an entry stays on screen, fade included. The ledger wants several; a scrolling number wants two or three.",
        min = 0.5, max = 12, step = 0.1,
        format = "%.1fs",
        get = function() return CommanderTracerDB[P .. "Duration"] end,
        set = function(value) CommanderTracerDB[P .. "Duration"] = value end,
        isEnabled = On,
    }, {
        label = "Speed",
        tooltip = "Scroll: pixels per second. Fountain: how hard it is thrown. Pop and Stack ignore it.",
        min = 10, max = 300, step = 5,
        format = "%.0f px/s",
        get = function() return CommanderTracerDB[P .. "Speed"] end,
        set = function(value) CommanderTracerDB[P .. "Speed"] = value end,
        isEnabled = IsScroll,
    })
    panel:AddSliderPair({
        label = "Scatter",
        tooltip = "Pixels of sideways scatter each entry is given at birth, so two numbers a moment apart do not print on top of each other. Stack lanes ignore it.",
        min = 0, max = 120, step = 2,
        format = "%.0f px",
        get = function() return CommanderTracerDB[P .. "Spread"] end,
        set = function(value) CommanderTracerDB[P .. "Spread"] = value end,
        isEnabled = NotStack,
    }, {
        label = "Merge Window",
        tooltip = "Seconds within which a repeat of the same spell joins the entry already on screen -- the amount adds up, a count appears (x3), the entry punches. Arcane Explosion on five targets becomes one line. 0 draws every hit on its own.",
        min = 0, max = 8, step = 0.1,
        format = function(v) if v == 0 then return "off" end return string.format("%.1fs", v) end,
        get = function() return CommanderTracerDB[P .. "Merge"] end,
        set = function(value) CommanderTracerDB[P .. "Merge"] = value end,
        isEnabled = On,
    })
    panel:AddSliderPair({
        label = "Max Entries",
        tooltip = "The most entries in flight at once. Past it the oldest is dropped, which is what keeps a whirlwind from painting the screen.",
        min = 1, max = 30, step = 1,
        format = "%.0f",
        get = function() return CommanderTracerDB[P .. "MaxLines"] end,
        set = function(value) CommanderTracerDB[P .. "MaxLines"] = value end,
        isEnabled = On,
    }, {
        label = "Hide Below",
        tooltip = "Amounts smaller than this are not drawn in this lane. 0 draws everything. Good for keeping a dot's ticks off the outgoing lane without turning ticks off elsewhere.",
        min = 0, max = 2000, step = 10,
        format = function(v) if v == 0 then return "show all" end return string.format("%d", v) end,
        get = function() return CommanderTracerDB[P .. "MinAmount"] end,
        set = function(value) CommanderTracerDB[P .. "MinAmount"] = value end,
        isEnabled = On,
    })
    panel:AddDropdownPair({
        label = "Font",
        tooltip = "Which face this lane writes in. All four ship with the client, so none can go missing across a patch. Rune is the face the old damage numbers used.",
        options = DATA.FONT_OPTIONS,
        get = function() return CommanderTracerDB[P .. "Font"] end,
        set = function(value) CommanderTracerDB[P .. "Font"] = value end,
        isEnabled = On,
    }, {
        label = "Outline",
        tooltip = "An outline round the text. A bare number over the world is at the mercy of whatever is behind it; an outline is what keeps it readable over snow and over a night sky alike.",
        options = DATA.OUTLINE_OPTIONS,
        get = function() return CommanderTracerDB[P .. "Outline"] end,
        set = function(value) CommanderTracerDB[P .. "Outline"] = value end,
        isEnabled = On,
    })
    panel:AddSliderPair({
        label = "Text Size",
        tooltip = "Point size of the text in this lane. A crit multiplies it by Crit Size.",
        min = 8, max = 48, step = 1,
        format = "%.0f",
        get = function() return CommanderTracerDB[P .. "FontSize"] end,
        set = function(value) CommanderTracerDB[P .. "FontSize"] = value end,
        isEnabled = On,
    }, {
        label = "Icon Size",
        tooltip = "Size of the spell icon beside the text, when one is shown.",
        min = 8, max = 48, step = 1,
        format = "%.0f",
        get = function() return CommanderTracerDB[P .. "IconSize"] end,
        set = function(value) CommanderTracerDB[P .. "IconSize"] = value end,
        isEnabled = function() return On() and LaneValue(P, "Icon") ~= "NONE" end,
    })
    panel:AddDropdownPair({
        label = "Spell Icon",
        tooltip = "Draw the spell's icon beside the text, and on which side. A swing has no icon and draws none.",
        options = DATA.ICON_PLACES,
        get = function() return CommanderTracerDB[P .. "Icon"] end,
        set = function(value) CommanderTracerDB[P .. "Icon"] = value end,
        isEnabled = On,
    }, {
        label = "Colour Rule",
        tooltip = "What decides an entry's colour.|n|nBy School: fire orange, frost blue, shadow purple, holy gold, nature green, arcane violet, physical white; heals green, misses grey, power by its kind.|nBy Kind: one colour per kind of event whatever the school.|nOne Colour: the colour picked beside this.|nClass Colour: your own class colour.",
        options = DATA.COLOR_MODES,
        get = function() return CommanderTracerDB[P .. "ColorMode"] end,
        set = function(value) CommanderTracerDB[P .. "ColorMode"] = value end,
        isEnabled = On,
    })
    panel:AddDropdownPair({
        label = "Lane Colour",
        tooltip = "The colour used when the Colour Rule is One Colour. Commander Console's palette is offered here too when it is loaded.",
        options = ColorOptions(CommanderTracerDB[P .. "FlatColor"]),
        get = function() return CommanderTracerDB[P .. "FlatColor"] end,
        set = function(value) CommanderTracerDB[P .. "FlatColor"] = value end,
        isEnabled = function() return On() and LaneValue(P, "ColorMode") == "FLAT" end,
    }, {
        label = "Crit Mark",
        tooltip = "How a crit is written, beyond being bigger: 2,410! or 2,410 crit or *2,410* or just the size.",
        options = DATA.CRIT_MARKS,
        get = function() return CommanderTracerDB[P .. "CritMark"] end,
        set = function(value) CommanderTracerDB[P .. "CritMark"] = value end,
        isEnabled = On,
    })
    panel:AddSliderPair({
        label = "Crit Size",
        tooltip = "How much larger than a normal entry a crit is drawn. 1.0 makes crits the same size as everything else.",
        min = 1, max = 2.5, step = 0.05,
        format = "%.2fx",
        get = function() return CommanderTracerDB[P .. "CritScale"] end,
        set = function(value) CommanderTracerDB[P .. "CritScale"] = value end,
        isEnabled = On,
    }, {
        label = "Opacity",
        tooltip = "How solid the lane is drawn at its brightest.",
        min = 0.2, max = 1, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderTracerDB[P .. "Alpha"] end,
        set = function(value) CommanderTracerDB[P .. "Alpha"] = value end,
        isEnabled = On,
    })
    panel:AddCheckboxPair({
        label = "Text Shadow",
        tooltip = "A one-pixel drop shadow under the text. Cheap legibility on top of the outline.",
        get = function() return CommanderTracerDB[P .. "Shadow"] end,
        set = function(value) CommanderTracerDB[P .. "Shadow"] = value end,
        isEnabled = On,
    }, {
        label = "Crit Punch",
        tooltip = "A crit lands oversized and settles to its Crit Size over a tenth of a second, rather than just appearing big.",
        get = function() return CommanderTracerDB[P .. "CritPunch"] end,
        set = function(value) CommanderTracerDB[P .. "CritPunch"] = value end,
        isEnabled = On,
    })
    panel:AddCheckboxPair({
        label = "Show Partials",
        tooltip = "Write what a hit lost on the way in brackets: (320 absorbed, 50 resisted), (200 over) on a heal, (overkill) on a kill.",
        get = function() return CommanderTracerDB[P .. "ShowPartials"] end,
        set = function(value) CommanderTracerDB[P .. "ShowPartials"] = value end,
        isEnabled = On,
    }, {
        label = "Second Line",
        tooltip = "Stack only: the small line under the main text, carrying whatever the Text setting left out (the target, the caster, what a shield ate).",
        get = function() return CommanderTracerDB[P .. "Sub"] end,
        set = function(value) CommanderTracerDB[P .. "Sub"] = value end,
        isEnabled = IsStack,
    })
    panel:AddSliderPair({
        label = "Row Width",
        tooltip = "Stack only: how wide each row is.",
        min = 120, max = 480, step = 10,
        format = "%.0f px",
        get = function() return CommanderTracerDB[P .. "Width"] end,
        set = function(value) CommanderTracerDB[P .. "Width"] = value end,
        isEnabled = IsStack,
    }, {
        label = "Slide In",
        tooltip = "Stack only: how far a new row slides in from, in pixels. 0 makes rows appear in place.",
        min = 0, max = 200, step = 5,
        format = "%.0f px",
        get = function() return CommanderTracerDB[P .. "SlideIn"] end,
        set = function(value) CommanderTracerDB[P .. "SlideIn"] = value end,
        isEnabled = IsStack,
    })
    panel:AddCheckboxPair({
        label = "Row Backdrop",
        tooltip = "Stack only: a dark panel behind each row, so the column reads as a column.",
        get = function() return CommanderTracerDB[P .. "RowBackdrop"] end,
        set = function(value) CommanderTracerDB[P .. "RowBackdrop"] = value end,
        isEnabled = IsStack,
    }, {
        label = "Row Accent",
        tooltip = "Stack only: a hairline down the row's edge in the entry's colour, so a column of rows can be read by colour before it is read by text.",
        get = function() return CommanderTracerDB[P .. "RowAccent"] end,
        set = function(value) CommanderTracerDB[P .. "RowAccent"] = value end,
        isEnabled = IsStack,
    })
end

local function AddSoundsSection(panel)
    panel:AddSection("Sounds",
        "Every noise this module can make, and which sound it makes. Picking a sound plays it, which is how two of them are told apart before the fight rather than during it.")
    local options = {}
    for _, snd in ipairs(DATA.SOUNDS) do
        options[#options + 1] = { text = snd.label, value = snd.key }
    end
    local function Spec(slot)
        return {
            label = slot.label,
            tooltip = slot.tip .. "|n|nPicking a sound plays it. A choice that stays silent is one whose file did not ship with this client -- pick another; nothing breaks either way.",
            options = options,
            get = function() return CommanderTracerDB[slot.key] or slot.default end,
            set = function(value) CommanderTracerDB[slot.key] = value end,
            onSelect = function() if CommanderTracer_PlaySound then CommanderTracer_PlaySound(slot.key) end end,
            isEnabled = Enabled,
        }
    end
    local slots = DATA.SOUND_SLOTS
    for i = 1, #slots, 2 do
        panel:AddDropdownPair(Spec(slots[i]), slots[i + 1] and Spec(slots[i + 1]) or nil)
    end
    panel:AddSlider({
        label = "Crit Chime From",
        tooltip = "The Big Crit sound rings only for a crit of yours at least this large.",
        min = 100, max = 8000, step = 100,
        format = "%.0f",
        get = function() return CommanderTracerDB.CritChimeFrom end,
        set = function(value) CommanderTracerDB.CritChimeFrom = value end,
        isEnabled = function() return Enabled() and (CommanderTracerDB.SoundCrit or "NONE") ~= "NONE" end,
    })
    local buttons = {}
    for _, slot in ipairs(slots) do
        buttons[#buttons + 1] = {
            label = slot.label,
            width = 118,
            tooltip = "Play the " .. slot.label .. " sound now.",
            onClick = function() if CommanderTracer_PlaySound then CommanderTracer_PlaySound(slot.key) end end,
        }
    end
    panel:AddButtonRow(buttons)
end

-- ---------------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------------

local function SetAllLocked(locked)
    for _, lane in ipairs(DATA.LANES) do
        CommanderTracerDB[lane.key .. "Locked"] = locked
    end
    Notify()
end

local function CreatePanel()
    local panel = Commander.UI.NewPanel({
        key = "Tracer",
        title = "Tracer",
        addonName = "Commander_Tracer",
        description = "Floating combat text, rebuilt: six lanes -- your damage, your healing, what lands on you, what heals you, a lingering ledger column that holds each event long enough to be read after the fact, and big callouts for the moments -- each with its own anchor, motion, face, colour rule and merge window, fed by the combat log so every number carries its spell, its icon and its target. Blizzard's own text is switched off while this runs and handed back when it stops.",
        event = COMMANDER_TRACER_EVENTS.UPDATE,
        slash = { "/ctracer", "/ctr" },
        slashHandlers = {
            test = function() if CommanderTracer_Test then CommanderTracer_Test() end end,
            unlock = function() SetAllLocked(false); print("Commander Tracer: every lane unlocked -- drag them, right-click one to lock it") end,
            lock = function() SetAllLocked(true); print("Commander Tracer: every lane locked") end,
            clear = function() if CommanderTracer_Clear then CommanderTracer_Clear() end end,
            report = function() if CommanderTracer_Report then CommanderTracer_Report() end end,
        },
    })

    panel:AddCheckbox({
        label = "Enable Tracer",
        tooltip = "The whole module. Off, Blizzard's own combat text is given back.",
        get = function() return CommanderTracerDB.Enable end,
        set = function(value) CommanderTracerDB.Enable = value end,
    })
    panel:AddButtonRow({
        {
            label = "Test Volley",
            tooltip = "Fire a scripted few seconds of fabricated events -- hits, a crit, a miss, a heal, damage taken, a shield, an interrupt, a proc, a kill -- through every lane, so they can all be placed and sized without a target dummy.",
            onClick = function() if CommanderTracer_Test then CommanderTracer_Test() end end,
            isEnabled = Enabled,
        },
        {
            label = "Unlock All Lanes",
            tooltip = "Unlock every lane's anchor so it can be dragged. Right-click an unlocked lane to lock it again, or triple right-click a locked one to unlock it without coming back here.",
            onClick = function() SetAllLocked(false) end,
            isEnabled = Enabled,
        },
        {
            label = "Lock All Lanes",
            tooltip = "Lock every lane where it is.",
            onClick = function() SetAllLocked(true) end,
            isEnabled = Enabled,
        },
        {
            label = "Clear Screen",
            width = 110,
            tooltip = "Drop every entry currently in flight.",
            onClick = function() if CommanderTracer_Clear then CommanderTracer_Clear() end end,
            isEnabled = Enabled,
        },
    })

    AddTakeoverSection(panel)
    AddNumbersSection(panel)
    AddRoutingSections(panel)
    for _, lane in ipairs(DATA.LANES) do
        AddLaneSection(panel, lane)
    end
    AddSoundsSection(panel)

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Tracer" then
        Commander.UI.ApplyDefaults(CommanderTracerDB, DefaultSettings)
        if type(CommanderTracerDB.CVarBackup) ~= "table" then CommanderTracerDB.CVarBackup = {} end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreatePanel()
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end

frame:SetScript("OnEvent", OnEvent)
