-- Commander Meters: the window layer — sorted bars (one or two panes), the
-- segment/mode chrome, the click-through detail view with pie breakdown,
-- the per-fight graph, the death log with its health curve, and report-to-
-- chat. Every number comes from CommanderMetersEngine; this file only
-- arranges and paints it, at a fixed 2 Hz.
--
-- Visual contract (the RTS rule: built for someone who is NOT looking at
-- it): geometry never shifts — bar height, name column, and number columns
-- are constants; only bar order and digits change. Class colors are the
-- data encoding and are never overridden; the single amber accent marks
-- active/selected state and nothing else. The entire theme is the THEME
-- table below — a widget that needs a color reads a constant.
--
-- Split view: the window can split into two side-by-side panes WITHOUT
-- changing its footprint — the total width holds, each pane takes half,
-- and the number columns condense to fit.
--
-- Each pane owns BOTH halves of what it shows, and its caption is the
-- menu for both: a MODE section and a SEGMENT section, one click away.
-- Damage beside healing on the same fight; or DAMAGE · CURRENT beside
-- DAMAGE · OVERALL, the same metric read twice — "am I ramping or falling
-- off?" — without a trip to the header. Both at once is allowed too,
-- because the caption states the pane in full either way.
--
-- The right pane FOLLOWS the window's segment until you pin it to one of
-- its own; pinned, its caption wears the accent so a divergence can never
-- be silent (the ambiguity this addon exists to kill is two views
-- reading different fights while LOOKING identical). "Follow" is the
-- default and the way back.

local E = CommanderMetersEngine
local A = CommanderMetersArena -- the arena match engine
local db

-- ---------------------------------------------------------------------------
-- Theme: the whole skin, one flat table
-- ---------------------------------------------------------------------------

local THEME = {
    font = "Fonts\\ARIALN.TTF", -- condensed, uniform digit widths (no jitter)
    fontSize = 11,
    fontSizeSmall = 10,

    bg      = { 0.045, 0.055, 0.065, 0.92 }, -- window fill
    chrome  = { 0.09, 0.11, 0.13, 1 },       -- header strip
    edge    = { 0.22, 0.27, 0.31, 1 },       -- thin panel edges
    accent  = { 1.0, 0.72, 0.10 },           -- selection/active — the only accent
    text    = { 0.92, 0.94, 0.95 },
    textDim = { 0.52, 0.58, 0.62 },
    barBack = { 1, 1, 1, 0.04 },             -- empty bar track
    hover   = { 1, 1, 1, 0.06 },
    danger  = { 0.85, 0.25, 0.2 },           -- death rows in logs, WIPE tags
    healTx  = { 0.3, 0.8, 0.35 },            -- heal rows in logs, KILL tags
    neutral = { 0.6, 0.65, 0.7 },            -- actors with no class (orphan minions)
    plotFill = { 0, 0, 0, 0.35 },            -- graph/curve plot backing

    -- Tooltip emphasis colors (GameTooltip AddLine tints)
    tipText   = { 0.95, 0.95, 0.95 },
    tipFaint  = { 0.85, 0.85, 0.85 },
    tipDim    = { 0.7, 0.7, 0.7 },
    tipHint   = { 0.45, 0.5, 0.55 },
    tipGlance = { 1, 0.85, 0.6 },
    tipResist = { 0.8, 0.7, 1 },
    tipBlock  = { 0.8, 0.8, 0.7 },
    tipAbsorb = { 0.7, 0.8, 1 },
    tipHeal   = { 0.7, 1, 0.7 },

    -- Semantic stat colors (D20): a value carries the color of WHAT it is,
    -- everywhere stats are read — mode labels, detail values, tooltips.
    -- Class colors still own actors; the accent still owns selection.
    statDmg   = { 0.95, 0.62, 0.35 },  -- damage done (ember)
    statTaken = { 0.92, 0.42, 0.28 },  -- damage taken (hotter)
    statHeal  = { 0.40, 0.85, 0.45 },  -- healing
    statDeath = { 0.85, 0.25, 0.20 },  -- deaths
    statUtil  = { 0.35, 0.80, 0.90 },  -- interrupts / dispels / cc breaks (and OFFENSIVE dispels)
    statCleanse = { 0.55, 0.90, 0.68 }, -- DEFENSIVE dispels: a debuff taken off a friend (mint)
    statApm   = { 0.72, 0.62, 0.95 },  -- actions per minute (violet)
    statCC    = { 0.86, 0.45, 1.00 },  -- crowd control (violet-magenta)
    statMana  = { 0.35, 0.55, 0.95 },  -- mana drained (mana blue)
    statCd    = { 0.95, 0.80, 0.45 },  -- cooldowns and trinkets (pale gold)
    teamUs    = { 0.30, 0.70, 0.95 },  -- arena: our team (blue)
    teamThem  = { 0.90, 0.32, 0.30 },  -- arena: the enemy team (red)
    statCrit  = { 1.00, 0.82, 0.25 },  -- crit gold
    statMiss  = { 0.55, 0.62, 0.72 },  -- misses / avoidance steel
    hpGood    = { 0.40, 0.85, 0.45 },  -- HP readouts ≥ 50%
    hpWarn    = { 1.00, 0.72, 0.10 },  -- HP 20–49%
    hpBad     = { 0.85, 0.25, 0.20 },  -- HP < 20%

    -- Pie slice palette: eight distinct hues + the "everything else" gray.
    -- These color SHARES of one actor's own output, never actors — class
    -- colors keep that job.
    pieColors = {
        { 0.96, 0.55, 0.20 }, { 0.30, 0.62, 0.92 }, { 0.42, 0.80, 0.38 },
        { 0.85, 0.36, 0.36 }, { 0.68, 0.48, 0.90 }, { 0.92, 0.82, 0.30 },
        { 0.35, 0.80, 0.78 }, { 0.88, 0.52, 0.72 },
    },
    pieOther = { 0.45, 0.48, 0.52 },

    headerH = 20,
    capH = 14,      -- per-pane mode caption strip (split view only)
    rowH = 16,
    rowGap = 1,
    graphH = 132,   -- legend 16 + plot 100 + padding
    plotH = 100,
    pieH = 118,     -- pie panel appended to the detail view
    curveH = 60,    -- death health-curve panel
    detailW = 312,
    detailRows = 9, -- ability rows in the detail view
    detailSubRows = 5, -- target/source rows
    deathTrailRows = 10, -- matches the engine's death ring (last 10 events)
}

local WHITE = "Interface\\Buttons\\WHITE8X8"

-- Accent presets the Appearance settings can pick from. The chosen one is
-- written INTO THEME.accent at login — the theme stays one flat table and
-- every consumer keeps reading the same constant. These five are Meters'
-- own; the suite tints resolve through AccentByKey below.
local ACCENTS = {
    AMBER = { 1.0, 0.72, 0.10 },
    CYAN  = { 0.25, 0.85, 0.95 },
    GREEN = { 0.35, 0.90, 0.40 },
    RED   = { 0.95, 0.35, 0.30 },
    WHITE = { 0.95, 0.95, 0.95 },
}

-- Suite tints (the TopBar pattern): Commander_Console's palette is the
-- closest thing the suite has to a canon, so any accent key the local
-- table doesn't know is looked up there — Meters offers the same named
-- colors as the rest of the suite without copying the list. CLASS resolves
-- live to the player's class color; an unknown key (Console not loaded,
-- say) falls back to amber rather than erroring.
local function AccentByKey(key)
    if key == "CLASS" then
        local info = Commander.GetClassInfo and Commander.GetClassInfo()
        if info and info.color then
            -- Copy, never alias: GetClassInfo memoizes that table for the
            -- whole suite, and THEME.accent must stay ours to own
            return { info.color[1], info.color[2], info.color[3] }
        end
    end
    if ACCENTS[key] then return ACCENTS[key] end
    for _, color in ipairs(CommanderConsole_Colors or {}) do
        if color.value == key and color.r then
            return { color.r, color.g, color.b }
        end
    end
    return ACCENTS.AMBER
end

-- Escape-code tags derived from theme colors (rebuilt after the overrides
-- resolve at login)
local LIVE_DOT, KILL_TAG, WIPE_TAG, WIN_TAG, LOSS_TAG
local ESC = {} -- precomputed "|cffRRGGBB" openers for the semantic colors

local function EscOf(c)
    return string.format("|cff%02x%02x%02x",
        c[1] * 255 + 0.5, c[2] * 255 + 0.5, c[3] * 255 + 0.5)
end

local function BuildThemeTags()
    LIVE_DOT = EscOf(THEME.accent) .. "●|r "
    KILL_TAG = " " .. EscOf(THEME.healTx) .. "KILL|r"
    WIPE_TAG = " " .. EscOf(THEME.danger) .. "WIPE|r"
    WIN_TAG = " " .. EscOf(THEME.healTx) .. "WIN|r"
    LOSS_TAG = " " .. EscOf(THEME.danger) .. "LOSS|r"
    ESC.crit = EscOf(THEME.statCrit)
    ESC.miss = EscOf(THEME.statMiss)
    ESC.text = EscOf(THEME.tipText)
    ESC.dim = EscOf(THEME.textDim)
    ESC.accent = EscOf(THEME.accent)
end
BuildThemeTags()

-- Which semantic color a mode's values wear, keyed by the engine mode key
local MODE_COLOR_KEYS = {
    DMG = "statDmg", DPS = "statDmg", TAKEN = "statTaken", HEAL = "statHeal",
    DEATHS = "statDeath", INT = "statUtil", DISPEL = "statUtil", CCBREAK = "statUtil",
    APM = "statApm",
    ARENA_DMG = "statDmg", ARENA_HEAL = "statHeal", ARENA_TAKEN = "statTaken", ARENA_CC = "statCC",
    ARENA_DISPEL = "statUtil",
}

local function ModeColor(mode)
    return THEME[MODE_COLOR_KEYS[mode.key]] or THEME.text
end

-- The arena match a pane reads: the live one while a match is on, else
-- the newest closed one
local function ArenaMatch()
    return A.Live() or A.GetMatch("last")
end

local function ArenaMatchLabel(m, plain)
    if not m then return "NO MATCH" end
    local live = A.Live() == m
    local size = m.bracket > 0 and (m.bracket .. "v" .. m.bracket) or "ARENA"
    local head = size .. (m.map and (" " .. m.map:upper()) or "")
    if live then return (plain and "" or LIVE_DOT) .. head .. " · LIVE" end
    return head .. " · " .. (m.result or "?")
end

-- A mode's rate over a duration: per second, or per minute for modes that
-- quote one (APM). The engine's CollectRows applies the same scale.
local function ModeRate(mode, value, dur)
    return value * (mode.rateScale or 1) / dur
end

local function HpColor(frac)
    if frac >= 0.5 then return THEME.hpGood end
    if frac >= 0.2 then return THEME.hpWarn end
    return THEME.hpBad
end

-- Spell icons, memoized by spellId and rendered inline via the |T|t escape
-- with the suite's standard 0.08-0.92 icon trim (5..59 of 64)
local MELEE_ICON = "Interface\\Icons\\INV_Sword_04"
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local iconCache = {}

local function IconOf(rec)
    if type(rec) ~= "table" then return FALLBACK_ICON end
    local id = rec.id
    if not id then
        if (rec.name or rec.what) == "Melee" then return MELEE_ICON end
        return FALLBACK_ICON
    end
    local icon = iconCache[id]
    if icon == nil then
        if GetSpellTexture then
            local ok, tex = pcall(GetSpellTexture, id)
            if ok and tex then icon = tex end
        end
        if not icon and GetSpellInfo then
            local ok, _, _, tex = pcall(GetSpellInfo, id)
            if ok and tex then icon = tex end
        end
        iconCache[id] = icon or false
    end
    return icon or FALLBACK_ICON
end

local function IconTag(rec, size)
    -- string.format explicitly: this sits above the local format alias
    return string.format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t", IconOf(rec), size, size)
end

-- Appearance overrides bake into THEME once, before any widget is built —
-- no registries, no restyling passes; accent/text-size changes ask for a
-- /reload (the settings panel says so). The two opacities are read live
-- from the DB each repaint instead, so their sliders apply instantly.
local function ResolveThemeOverrides()
    THEME.accent = AccentByKey(db.AccentColor)
    local size = tonumber(db.TextSize) or 11
    THEME.fontSize = size
    THEME.fontSizeSmall = size - 1
    BuildThemeTags()
end

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local format = string.format

local function FmtNum(n)
    if n >= 1e6 then return format("%.2fm", n / 1e6) end
    if n >= 1e4 then return format("%.1fk", n / 1e3) end
    if n >= 1e3 then return format("%.2fk", n / 1e3) end
    return format("%.0f", n)
end

local function FmtTime(secs)
    secs = math.floor(secs + 0.5)
    return format("%d:%02d", math.floor(secs / 60), secs % 60)
end

-- A dispel split for the small column: offensive in the utility cyan,
-- defensive in the cleanse mint ("5/3"; the tooltip names both sides)
local function SplitText(off, def)
    return EscOf(THEME.statUtil) .. format("%d", off) .. "|r" .. ESC.dim .. "/|r"
        .. EscOf(THEME.statCleanse) .. format("%d", def) .. "|r"
end

local function ShortName(name)
    if not name then return "?" end
    local dash = name:find("-", 1, true)
    if dash then return name:sub(1, dash - 1) end
    return name
end

local function ClassColor(classToken)
    if classToken then
        local info = Commander.GetClassInfo(classToken)
        if info and info.color then return info.color end
    end
    return THEME.neutral
end

local function MakeText(parent, size, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(THEME.font, size or THEME.fontSize, "")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])
    fs:SetWordWrap(false)
    return fs
end

local function MakeEdge(frame)
    for _, spec in ipairs({
        { "TOPLEFT", "TOPRIGHT", nil, 1 },
        { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, nil },
        { "TOPRIGHT", "BOTTOMRIGHT", 1, nil },
    }) do
        local line = frame:CreateTexture(nil, "BORDER")
        line:SetTexture(WHITE)
        line:SetVertexColor(THEME.edge[1], THEME.edge[2], THEME.edge[3], THEME.edge[4])
        line:SetPoint(spec[1])
        line:SetPoint(spec[2])
        if spec[3] then line:SetWidth(spec[3]) end
        if spec[4] then line:SetHeight(spec[4]) end
    end
end

-- ---------------------------------------------------------------------------
-- View state
-- ---------------------------------------------------------------------------

local view = {
    segSel = "current", -- "overall" | "current" | "last" | fight id — the
                        -- window's segment (pane 2 too, unless comparing)
    segSel2 = nil,      -- pane 2's PINNED segment; nil = follow segSel
    graphOpen = false,
    detailGuid = nil,   -- open detail actor
    detailPane = 1,     -- which pane's mode the detail follows
    detailDeath = nil,  -- selected death (deaths mode)
    pieList = 1,        -- which detail list the pie breaks down (always on;
                        -- clicking a row in either list re-targets it)
    pieKey = nil,       -- selected entry key; nil = auto-select the top one
    hiddenLines = {},   -- guid -> true, graph legend toggles (session)
    abilityOffset = 0,  -- detail list scroll offsets
    targetOffset = 0,
}

-- Panes: [1] is the always-on primary; [2] exists while the split is open.
-- Each has its own mode, bar-row pool, and wheel-scroll offset.
local panes = {
    { rows = {}, offset = 0, mode = nil },
    { rows = {}, offset = 0, mode = nil },
}

-- External live pane modes, registered by other suite addons through
-- CommanderMeters_RegisterExternalMode (Commander_Threat's embedded pane).
-- An external mode owns its own data: the provider hands back finished
-- display rows every repaint, so none of the segment machinery applies —
-- no detail view, no graph series, no segment label.
local externalModes = {}

-- Arena pane modes: BOTH teams' seats from the arena match engine, one
-- stat each, so the split can read ARENA DMG beside ARENA HEAL for the
-- whole box. They ignore the pane's segment (a match is its own segment)
-- and open the Arena Report instead of the detail popup. `stat` names an
-- entry in CommanderMetersArena.STATS; `lists` is empty like an external
-- mode's so the segment machinery never touches a seat.
local ARENA_MODES = {
    { key = "ARENA_DMG", label = "ARENA DMG", arena = true, stat = "DMG", lists = {} },
    { key = "ARENA_HEAL", label = "ARENA HEAL", arena = true, stat = "HEAL", lists = {} },
    { key = "ARENA_TAKEN", label = "ARENA TAKEN", arena = true, stat = "TAKEN", lists = {} },
    { key = "ARENA_CC", label = "ARENA CC", arena = true, stat = "CC", lists = {} },
    { key = "ARENA_DISPEL", label = "ARENA DISPELS", arena = true, stat = "DISPEL", lists = {} },
}

local function ModeByKey(key)
    for _, m in ipairs(E.MODES) do
        if m.key == key then return m end
    end
    for _, m in ipairs(ARENA_MODES) do
        if m.key == key then return m end
    end
    -- A saved key whose provider is absent this session (addon disabled)
    -- falls through to the default mode like any unknown key
    if externalModes[key] then return externalModes[key] end
    return E.MODES[1]
end

-- Is the right pane pinned to a segment of its own? nil segSel2 means it
-- follows the window, which is the default and the way back. The pin only
-- means anything while the split is actually open.
local function PinnedPane2()
    return db and db.SplitOpen and view.segSel2 ~= nil
end

-- Which segment a pane is reading: the window's, unless the right pane
-- has been pinned away from it.
local function PaneSelector(paneIndex)
    if paneIndex == 2 and PinnedPane2() then return view.segSel2 end
    return view.segSel
end

local function PaneSegment(paneIndex)
    return E.GetSegment(PaneSelector(paneIndex))
end

local function PaneMode(paneIndex)
    local pane = panes[paneIndex]
    return (pane and pane.mode) or panes[1].mode
end

local function ViewSegment()
    return PaneSegment(1)
end

local function SuccessTag(seg, plain)
    if not seg or seg.success == nil then return "" end
    if seg.match then
        -- A match segment (D28) won or lost; KILL/WIPE are raid words
        if plain then return seg.success and " (WIN)" or " (LOSS)" end
        return seg.success and WIN_TAG or LOSS_TAG
    end
    if plain then
        return seg.success and " (KILL)" or " (WIPE)"
    end
    return seg.success and KILL_TAG or WIPE_TAG
end

local function SegmentLabel(plain, sel)
    sel = sel or view.segSel
    if sel == "overall" then return "OVERALL" end
    if sel == "current" then
        return E.InFight() and "CURRENT" or "CURRENT (IDLE)"
    end
    if sel == "last" then
        local seg = E.GetSegment("last")
        return seg and (("LAST — " .. (seg.name or "?")):upper() .. SuccessTag(seg, plain)) or "LAST"
    end
    local seg = E.GetSegment(sel)
    if seg then
        return ("F#" .. seg.id .. " — " .. (seg.name or "?")):upper() .. SuccessTag(seg, plain)
    end
    return "?"
end

-- ---------------------------------------------------------------------------
-- Frames (created once at PLAYER_LOGIN)
-- ---------------------------------------------------------------------------

local root, headerFrame, modeBtn, segBtn, shareBtn, splitBtn, graphBtn, resetBtn, arenaBtn, segFlash
local paneDivider
local graphFrame, detailFrame
local menuFrame, menuBuilder
local repaintNow -- forward: full repaint (panes + header + graph + detail)
local RepaintDetail -- forward

local function MakeHeaderButton(parent, justify)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(THEME.headerH)
    btn.text = MakeText(btn, THEME.fontSize, justify or "LEFT")
    btn.text:SetPoint("LEFT", btn, "LEFT", 4, 0)
    btn.text:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
    btn.hover = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.hover:SetTexture(WHITE)
    btn.hover:SetVertexColor(1, 1, 1, THEME.hover[4])
    btn.hover:SetAllPoints()
    return btn
end

-- Header glyphs are DRAWN — little stacks of tinted quads, the pie-spoke
-- technique at icon size. ARIALN on this client has no glyph for shape
-- characters (a "‖" renders as the missing-glyph box), and icon FILES can
-- move across client patches; quads cut from WHITE8X8 can do neither, and
-- they tint with the theme exactly like text does.
local function Quad(btn, w, h, dx, dy, rotation)
    local q = btn:CreateTexture(nil, "ARTWORK")
    q:SetTexture(WHITE)
    q:SetSize(w, h)
    q:SetPoint("CENTER", btn, "CENTER", dx, dy)
    if rotation then q:SetRotation(rotation) end
    btn.icon[#btn.icon + 1] = q
end

local GLYPHS = {
    share = function(b) -- speech bubble: the report goes to chat
        Quad(b, 11, 7, 0, 2)
        Quad(b, 3.5, 3.5, -2, -2.5, math.pi / 4)
    end,
    split = function(b) -- two panes side by side
        Quad(b, 4, 10, -3, 0)
        Quad(b, 4, 10, 3, 0)
    end,
    graph = function(b) -- three rising columns
        Quad(b, 3, 4, -4, -3)
        Quad(b, 3, 7, 0, -1.5)
        Quad(b, 3, 10, 4, 0)
    end,
    reset = function(b) -- the bin the data goes into
        Quad(b, 4, 1.5, 0, 4.75)
        Quad(b, 10, 1.5, 0, 3)
        Quad(b, 8, 7, 0, -2)
    end,
    close = function(b) -- X
        Quad(b, 1.5, 9, 0, 0, math.pi / 4)
        Quad(b, 1.5, 9, 0, 0, -math.pi / 4)
    end,
    play = function(b) -- a right-pointing wedge, built from three bars
        Quad(b, 2, 10, -3, 0)
        Quad(b, 2, 7, -0.5, 0)
        Quad(b, 2, 4, 2, 0)
        Quad(b, 2, 1.5, 4.5, 0)
    end,
    pause = function(b) -- two bars
        Quad(b, 3, 10, -2.5, 0)
        Quad(b, 3, 10, 2.5, 0)
    end,
    arena = function(b) -- crossed swords: two long blades, two short hilts
        Quad(b, 1.5, 12, 0, 0, math.pi / 3.2)
        Quad(b, 1.5, 12, 0, 0, -math.pi / 3.2)
        Quad(b, 5, 1.5, -3, -3.2, math.pi / 3.2)
        Quad(b, 5, 1.5, 3, -3.2, -math.pi / 3.2)
    end,
    skip = function(b) -- to the end: wedge + bar
        Quad(b, 2, 8, -3.5, 0)
        Quad(b, 2, 5, -1, 0)
        Quad(b, 2, 2, 1.5, 0)
        Quad(b, 2, 9, 4, 0)
    end,
}

local function SetGlyphColor(btn, c)
    for i = 1, #btn.icon do
        btn.icon[i]:SetVertexColor(c[1], c[2], c[3], 1)
    end
end

local function MakeGlyphButton(parent, glyphName)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(21, THEME.headerH)
    btn.glyphName = glyphName -- how the headless harness finds buttons
    btn.icon = {}
    btn.hover = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.hover:SetTexture(WHITE)
    btn.hover:SetVertexColor(1, 1, 1, THEME.hover[4])
    btn.hover:SetAllPoints()
    GLYPHS[glyphName](btn)
    SetGlyphColor(btn, THEME.textDim)
    return btn
end

local function OpenMenu(builder, anchor)
    menuBuilder = builder
    ToggleDropDownMenu(1, nil, menuFrame, anchor, 0, 0)
end

-- ---------------------------------------------------------------------------
-- Bar panes
-- ---------------------------------------------------------------------------

-- Top-3 scan without sorting or allocation, for the bar hover tooltip
-- (returns the record refs too, for icons)
local function TooltipTop3(map)
    local k1, v1, r1, k2, v2, r2, k3, v3, r3
    for key, rec in pairs(map) do
        local v = type(rec) == "table" and rec.total or rec
        if not v1 or v > v1 then
            k3, v3, r3, k2, v2, r2, k1, v1, r1 = k2, v2, r2, k1, v1, r1, key, v, rec
        elseif not v2 or v > v2 then
            k3, v3, r3, k2, v2, r2 = k2, v2, r2, key, v, rec
        elseif not v3 or v > v3 then
            k3, v3, r3 = key, v, rec
        end
    end
    return k1, v1, r1, k2, v2, r2, k3, v3, r3
end

local ArenaSeatTooltip -- forward: defined with the arena pane painter

-- A player's arena ratings from Commander Muster (an OptionalDep), which
-- merges what it has seen with the Commander Ladder web feed (D30). Players
-- only: a pet or a creature has none, and its name must never reach the feed
-- as a player's.
local function ArenaRatings(guid, name)
    if type(guid) ~= "string" or not guid:match("^Player%-") then return nil end
    if not (CommanderMuster and CommanderMuster.RatingsLine) then return nil end
    return CommanderMuster.RatingsLine(guid) or (name and CommanderMuster.RatingsLine(name)) or nil
end

local function BarTooltip(row)
    if not row.guid then return end
    if PaneMode(row.paneIndex).arena then
        ArenaSeatTooltip(row)
        return
    end
    local seg = PaneSegment(row.paneIndex)
    local actor = seg and seg.actors[row.guid]
    if not actor then return end
    local mode = PaneMode(row.paneIndex)
    local value = mode.value(actor)
    local dur = E.SegmentDuration(seg, time())
    local c = ClassColor(actor.class)
    local mc = ModeColor(mode)
    local td, tf = THEME.tipDim, THEME.tipFaint
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(ShortName(actor.name), c[1], c[2], c[3])
    local ratings = ArenaRatings(row.guid, actor.name)
    if ratings then
        GameTooltip:AddDoubleLine("ARENA", ratings, td[1], td[2], td[3], 1, 1, 1)
    end
    -- Label/value column pairs: dim labels left, mode-colored numbers right
    GameTooltip:AddDoubleLine(mode.valueLabel or mode.label, FmtNum(value),
        td[1], td[2], td[3], mc[1], mc[2], mc[3])
    if mode.rateLabel then
        GameTooltip:AddDoubleLine(mode.rateLabel, FmtNum(ModeRate(mode, value, dur)),
            td[1], td[2], td[3], mc[1], mc[2], mc[3])
    end
    local total = 0
    for _, other in pairs(seg.actors) do
        total = total + mode.value(other)
    end
    if total > 0 then
        GameTooltip:AddDoubleLine("% OF TOTAL", format("%.0f%%", value / total * 100),
            td[1], td[2], td[3], tf[1], tf[2], tf[3])
    end
    if mode.active then
        GameTooltip:AddDoubleLine("ACTIVE", FmtTime(actor[mode.active]),
            td[1], td[2], td[3], tf[1], tf[2], tf[3])
    end
    if mode.split then
        -- Both sides by name, then each side's top auras
        for _, part in ipairs(mode.split) do
            local pc = THEME[part.color] or mc
            GameTooltip:AddDoubleLine(part.label, FmtNum(actor[part.field] or 0),
                td[1], td[2], td[3], pc[1], pc[2], pc[3])
        end
        for li, list in ipairs(mode.lists) do
            local part = mode.split[li]
            local sideTotal = part and actor[part.field] or 0
            local k1, v1, r1, k2, v2, r2, k3, v3, r3 = TooltipTop3(actor[list.field])
            if k1 and sideTotal > 0 then
                local pc = part and THEME[part.color] or mc
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(list.title, td[1], td[2], td[3])
                for _, kv in ipairs({ { k1, v1, r1 }, { k2, v2, r2 }, { k3, v3, r3 } }) do
                    if kv[1] then
                        GameTooltip:AddDoubleLine(IconTag(kv[3], 14) .. " " .. kv[1], FmtNum(kv[2]),
                            tf[1], tf[2], tf[3], pc[1], pc[2], pc[3])
                    end
                end
            end
        end
        GameTooltip:AddLine("Click for the full breakdown", THEME.tipHint[1], THEME.tipHint[2], THEME.tipHint[3])
        GameTooltip:Show()
        return
    end
    local spec = mode.lists[1]
    if spec and value > 0 then
        local k1, v1, r1, k2, v2, r2, k3, v3, r3 = TooltipTop3(actor[spec.field])
        if k1 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine(IconTag(r1, 14) .. " " .. k1,
                format("%s  (%.0f%%)", FmtNum(v1), v1 / value * 100),
                tf[1], tf[2], tf[3], mc[1], mc[2], mc[3])
            if k2 then
                GameTooltip:AddDoubleLine(IconTag(r2, 14) .. " " .. k2,
                    format("%s  (%.0f%%)", FmtNum(v2), v2 / value * 100),
                    tf[1], tf[2], tf[3], mc[1], mc[2], mc[3])
            end
            if k3 then
                GameTooltip:AddDoubleLine(IconTag(r3, 14) .. " " .. k3,
                    format("%s  (%.0f%%)", FmtNum(v3), v3 / value * 100),
                    tf[1], tf[2], tf[3], mc[1], mc[2], mc[3])
            end
        end
    end
    GameTooltip:AddLine("Click for the full breakdown", THEME.tipHint[1], THEME.tipHint[2], THEME.tipHint[3])
    GameTooltip:Show()
end

local function BuildPaneRows(paneIndex)
    local pane = panes[paneIndex]
    local want = db.MaxRows
    for i = 1, want do
        local row = pane.rows[i]
        if not row then
            row = CreateFrame("Button", nil, pane.frame)
            row.paneIndex = paneIndex
            row:SetHeight(THEME.rowH)
            row.bar = row:CreateTexture(nil, "ARTWORK")
            row.bar:SetTexture(WHITE)
            row.bar:SetPoint("TOPLEFT")
            row.bar:SetPoint("BOTTOMLEFT")
            row.track = row:CreateTexture(nil, "BACKGROUND")
            row.track:SetTexture(WHITE)
            row.track:SetVertexColor(THEME.barBack[1], THEME.barBack[2], THEME.barBack[3], THEME.barBack[4])
            row.track:SetAllPoints()
            row.hover = row:CreateTexture(nil, "HIGHLIGHT")
            row.hover:SetTexture(WHITE)
            row.hover:SetVertexColor(1, 1, 1, THEME.hover[4])
            row.hover:SetAllPoints()
            -- Fixed columns; only digits and bar order ever change
            row.rank = MakeText(row, THEME.fontSizeSmall, "RIGHT")
            row.rank:SetPoint("LEFT", row, "LEFT", 2, 0)
            row.rank:SetWidth(16)
            row.rank:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
            row.name = MakeText(row, THEME.fontSize, "LEFT")
            row.name:SetPoint("LEFT", row, "LEFT", 22, 0)
            row.name:SetPoint("RIGHT", row, "RIGHT", -134, 0)
            row.value = MakeText(row, THEME.fontSize, "RIGHT")
            row.value:SetPoint("RIGHT", row, "RIGHT", -82, 0)
            row.value:SetWidth(52)
            row.pct = MakeText(row, THEME.fontSizeSmall, "RIGHT")
            row.pct:SetPoint("RIGHT", row, "RIGHT", -46, 0)
            row.pct:SetWidth(36)
            row.pct:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
            row.rate = MakeText(row, THEME.fontSize, "RIGHT")
            row.rate:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            row.rate:SetWidth(42)
            -- Arena modes: a 2px team stripe on the left edge (blue us, red
            -- them) — team is data with its own jurisdiction, so the class
            -- color still owns the bar and the name
            row.team = row:CreateTexture(nil, "OVERLAY")
            row.team:SetTexture(WHITE)
            row.team:SetWidth(2)
            row.team:SetPoint("TOPLEFT")
            row.team:SetPoint("BOTTOMLEFT")
            row.team:Hide()
            row:SetScript("OnClick", function(self)
                if self.guid and PaneMode(self.paneIndex).arena then
                    -- Arena rows open the Arena Report on that seat
                    if CommanderMetersArena_Open then CommanderMetersArena_Open(self.guid) end
                    return
                end
                if self.guid then
                    if view.detailGuid == self.guid and view.detailPane == self.paneIndex
                        and detailFrame:IsShown() then
                        view.detailGuid = nil
                        detailFrame:Hide()
                    else
                        view.detailGuid = self.guid
                        view.detailPane = self.paneIndex
                        view.detailDeath = nil
                        view.pieList, view.pieKey = 1, nil -- pie auto-opens on the top entry
                        view.abilityOffset, view.targetOffset = 0, 0
                        detailFrame:Show()
                    end
                    repaintNow()
                end
            end)
            row:SetScript("OnEnter", BarTooltip)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            pane.rows[i] = row
        end
        -- Column set per view state, each one fixed: full rank/name/value/
        -- %/rate at full width; condensed rank/name/value when the split
        -- halves the pane. The condensed set also tightens rank and value
        -- so the name — the column that says WHO — keeps the most room a
        -- half pane can give it.
        row.rank:SetWidth(db.SplitOpen and 12 or 16)
        row.name:SetPoint("LEFT", row, "LEFT", db.SplitOpen and 16 or 22, 0)
        row.name:SetPoint("RIGHT", row, "RIGHT", db.SplitOpen and -48 or -134, 0)
        row.value:SetPoint("RIGHT", row, "RIGHT", db.SplitOpen and -4 or -82, 0)
        row.value:SetWidth(db.SplitOpen and 40 or 52)
        row.pct:SetShown(not db.SplitOpen)
        row.rate:SetShown(not db.SplitOpen)
        row:SetPoint("TOPLEFT", pane.frame, "TOPLEFT", 0, -((i - 1) * (THEME.rowH + THEME.rowGap)))
        row:SetPoint("RIGHT", pane.frame, "RIGHT", 0, 0)
        row:Show()
    end
    for i = want + 1, #pane.rows do
        pane.rows[i]:Hide()
    end
end

-- An external mode's pane: the provider hands back finished display rows
-- ({name, class, valueText, pctText, rateText, barFrac}), painted into the
-- same fixed columns. Lives outside the segment system entirely — its
-- caption names the provider's subject (the mob), not a segment, and its
-- rows carry no guid, which is what keeps the detail view, the bar
-- tooltip, and the click path off them for free.
local function RepaintExternalPane(pane, mode, want)
    local spec = mode.external
    if pane.caption then
        local ok, cap = pcall(spec.caption or function() return nil end)
        pane.caption.text:SetText(mode.label .. ESC.dim .. "  ·  "
            .. ((ok and cap) or "LIVE") .. "|r")
        pane.caption.text:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])
    end
    -- The provider is another addon: isolate it like a Notify listener,
    -- and treat a bad answer as an empty list
    local ok, rowsData, n = pcall(spec.collect, time())
    if not ok or type(rowsData) ~= "table" then
        rowsData, n = nil, 0
    end
    n = n or 0
    local maxOff = math.max(0, n - want)
    if pane.offset > maxOff then pane.offset = maxOff end
    local off = pane.offset
    for i = 1, want do
        local row = pane.rows[i]
        local data = (i + off) <= n and rowsData[i + off]
        row.guid = nil
        if data then
            local c = ClassColor(data.class)
            row.rank:SetText(i + off)
            row.name:SetText(ShortName(data.name or "?"))
            row.name:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])
            row.value:SetText(data.valueText or "")
            row.pct:SetText(data.pctText or "")
            row.rate:SetText(data.rateText or "")
            local frac = tonumber(data.barFrac) or 0
            if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
            local w = row:GetWidth()
            if w <= 0 then
                w = db.SplitOpen and (db.FrameWidth - 1) / 2 or db.FrameWidth
            end
            row.bar:SetWidth(math.max(frac * w, 0.001))
            row.bar:SetVertexColor(c[1], c[2], c[3], db.BarOpacity or 0.30)
            row:Show()
        elseif i == 1 then
            row.rank:SetText("")
            row.name:SetText(spec.empty or "No data")
            row.name:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
            row.value:SetText("")
            row.pct:SetText("")
            row.rate:SetText("")
            row.bar:SetWidth(0.001)
            row:Show()
        else
            row:Hide()
        end
    end
end

-- An arena mode's pane: every seat of both teams from the match engine,
-- sorted by the mode's stat, with a team stripe. The caption names the
-- MATCH, not a segment. Rows carry the seat guid so hover and click
-- work, but the click opens the Arena Report, never the detail popup.
local arenaOrder = {} -- pane rows regrouped by team, reused per repaint

local function RepaintArenaPane(pane, mode, want)
    local m = ArenaMatch()
    local stat = A.StatByKey(mode.stat)
    local sc = THEME[stat.color] or THEME.text
    if pane.caption then
        pane.caption.text:SetText(mode.label .. ESC.dim .. "  ·  " .. ArenaMatchLabel(m, true) .. "|r")
        pane.caption.text:SetTextColor(sc[1], sc[2], sc[3])
    end
    if not m then
        for i = 1, want do
            local row = pane.rows[i]
            row.guid = nil
            row.team:Hide()
            if i == 1 then
                row.rank:SetText("")
                row.name:SetText("No arena match yet")
                row.name:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
                row.value:SetText("")
                row.pct:SetText("")
                row.rate:SetText("")
                row.bar:SetWidth(0.001)
                row:Show()
            else
                row:Hide()
            end
        end
        return
    end
    local t = A.Live() == m and (time() - m.tsStart) or nil
    local rowsData, n, totals, dur = A.CollectRows(m, stat, t)
    local total = totals.us + totals.them
    -- The teams never interleave: our seats first, theirs after, each
    -- side in its own order with its own rank numbers (Devin: "I don't
    -- want both teams combined")
    local order = arenaOrder
    local k = 0
    for pass = 1, 2 do
        local team = pass == 1 and "us" or "them"
        local rank = 0
        for i = 1, n do
            local data = rowsData[i]
            if data.seat.team == team then
                rank = rank + 1
                k = k + 1
                order[k] = data
                data.teamRank = rank
            end
        end
    end
    for i = k + 1, #order do order[i] = nil end
    local maxOff = math.max(0, n - want)
    if pane.offset > maxOff then pane.offset = maxOff end
    local off = pane.offset
    local top = n > 0 and rowsData[1].value or 1
    for i = 1, want do
        local row = pane.rows[i]
        local data = (i + off) <= n and order[i + off]
        if data then
            local seat = data.seat
            local c = ClassColor(seat.class)
            local tc = seat.team == "us" and THEME.teamUs or THEME.teamThem
            row.guid = seat.guid
            row.rank:SetText(data.teamRank)
            row.name:SetText(ShortName(seat.name or "?"))
            row.name:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])
            local big, small
            if stat.primary == "rate" then
                big, small = FmtNum(data.rate), FmtNum(data.value)
            elseif stat.seconds then
                big, small = FmtTime(data.value), (data.count or 0) .. "x"
            elseif stat.split then
                -- Offensive / defensive: the count is the offensive share
                local off = data.count or 0
                big, small = FmtNum(data.value), SplitText(off, data.value - off)
            else
                big = FmtNum(data.value)
                small = stat.rateLabel and FmtNum(data.rate) or ""
            end
            row.value:SetText(big)
            row.pct:SetText(total > 0 and format("%.0f%%", data.value / total * 100) or "")
            row.rate:SetText(small)
            local frac = top > 0 and data.value / top or 0
            local w = row:GetWidth()
            if w <= 0 then
                w = db.SplitOpen and (db.FrameWidth - 1) / 2 or db.FrameWidth
            end
            row.bar:SetWidth(math.max(frac * w, 0.001))
            row.bar:SetVertexColor(c[1], c[2], c[3], db.BarOpacity or 0.30)
            row.team:SetVertexColor(tc[1], tc[2], tc[3], 1)
            row.team:Show()
            row:Show()
        else
            row.guid = nil
            row.team:Hide()
            row:Hide()
        end
    end
end

-- How long between two games, in a tooltip's words
local function GapText(s)
    if s < 3600 then return format("%d min", math.max(1, math.floor(s / 60 + 0.5))) end
    if s < 86400 then return format("%.0f h", s / 3600) end
    return format("%d days", math.floor(s / 86400 + 0.5))
end

-- The Scoreboard option's half of the seat tooltip (D31): the server's
-- killing blows beside the log's deaths (the arena board answers 0 deaths
-- for everyone), the rating change — yours with before and after — and the
-- MMR with how it moved, read from that player's next game
local function ArenaScoreTipLines(m, seat, line)
    local hint = THEME.tipDim
    local _, _, kb, deaths, mmr, change = A.ScoreLine(m, seat)
    line("KILLING BLOWS / DEATHS", kb .. " / " .. deaths)
    if change then
        local text = format("%+d", change)
        if seat.token == "player" then
            local before, after = A.OurRating(m)
            if before then text = format("%d → %d  (%+d)", before, after, change) end
        end
        line("RATING CHANGE", text, change >= 0 and THEME.healTx or THEME.danger)
    end
    if not mmr then
        if m.rated == false then line("MMR", "none (skirmish)") end
        return
    end
    local after, nextOrWhy, gap, sure = A.NextMmr(m, seat)
    if after then
        line("MMR", format("%d → %d  (%+d)", mmr, after, after - mmr), after >= mmr and THEME.healTx or THEME.danger)
        GameTooltip:AddLine(format("The new MMR is %s pre-match MMR in your next game (%s later).",
            seat.token == "player" and "your" or "their", GapText(gap)), hint[1], hint[2], hint[3], true)
        if not sure then
            GameTooltip:AddLine("They were not on your team: a game of their own in between would be in this number.",
                hint[1], hint[2], hint[3], true)
        end
    else
        line("MMR", tostring(mmr))
        GameTooltip:AddLine(nextOrWhy == "PENDING"
            and "The game never reports an MMR change. It shows here after your next game in this bracket."
            or "The game never reports an MMR change, and your next game cannot tell it.",
            hint[1], hint[2], hint[3], true)
    end
end

-- Hover on an arena row: the seat's whole card — every stat the match
-- engine keeps for it, plus the server's scoreboard numbers when merged
ArenaSeatTooltip = function(row, matchOverride)
    local m = matchOverride or ArenaMatch()
    local seat = m and m.seats[row.guid]
    if not seat then return end
    local c = ClassColor(seat.class)
    local td, tf = THEME.tipDim, THEME.tipFaint
    local tc = seat.team == "us" and THEME.teamUs or THEME.teamThem
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(ShortName(seat.name or "?"), c[1], c[2], c[3])
    GameTooltip:AddDoubleLine(seat.team == "us" and "YOUR TEAM" or "ENEMY TEAM",
        (seat.spec and (seat.spec .. " ") or "") .. (seat.class or "?"),
        tc[1], tc[2], tc[3], tf[1], tf[2], tf[3])
    local function line(label, value, color)
        color = color or tf
        GameTooltip:AddDoubleLine(label, value, td[1], td[2], td[3], color[1], color[2], color[3])
    end
    -- Their ratings now, not in this match: the newest Muster knows, with its age
    local ratings = ArenaRatings(row.guid, seat.name)
    if ratings then line("ARENA", ratings) end
    local dur = A.DurationAt(m, A.Live() == m and (time() - m.tsStart) or nil)
    line("DAMAGE", format("%s  (%s DPS)", FmtNum(seat.dmg), FmtNum(seat.dmg / dur)), THEME.statDmg)
    line("HEALING", format("%s  (%s HPS)", FmtNum(seat.heal + seat.absorb), FmtNum((seat.heal + seat.absorb) / dur)), THEME.statHeal)
    line("DMG TAKEN", FmtNum(seat.taken), THEME.statTaken)
    line("CONTROL", format("%dx · %s on target", seat.ccCasts, FmtTime(seat.ccSeconds)), THEME.statCC)
    line("CONTROLLED", format("%dx · %s", seat.ccTaken, FmtTime(seat.ccTakenSeconds)), THEME.statCC)
    if seat.ccWasted > 0 then line("CC INTO IMMUNITY", tostring(seat.ccWasted), THEME.danger) end
    if seat.ccBroke > 0 then line("BROKE OWN TEAM'S CC", tostring(seat.ccBroke), THEME.danger) end
    line("KICKS", format("%d  (kicked %d)", seat.ints, seat.intsTaken), THEME.statUtil)
    line("DISPELS", format("%s%d off|r · %s%d def|r", EscOf(THEME.statUtil), seat.purges, EscOf(THEME.statCleanse), seat.dispels), THEME.statUtil)
    if (seat.shatters or 0) > 0 then line("SHIELDS SHATTERED", tostring(seat.shatters), THEME.statUtil) end
    if (seat.dispelFails or 0) > 0 then line("DISPELS THAT TOOK NOTHING", tostring(seat.dispelFails), THEME.danger) end
    if seat.purgesTaken > 0 or seat.dispelsTaken > 0 then
        line("PURGED OFF / CLEANSED OFF", format("%d / %d", seat.purgesTaken, seat.dispelsTaken))
    end
    line("KILLS / DEATHS", format("%d / %d", seat.kills, seat.deaths), THEME.statDeath)
    line("APM", format("%.0f  (%d casts)", seat.casts * 60 / dur, seat.casts), THEME.statApm)
    if seat.drained > 0 or seat.drainedTaken > 0 then
        line("MANA DRAINED", format("%s  (lost %s)", FmtNum(seat.drained), FmtNum(seat.drainedTaken)), THEME.statMana)
    end
    if seat.drinks > 0 then line("DRINKS", format("%d  (%s)", seat.drinks, FmtTime(seat.drinkSeconds)), THEME.statMana) end
    line("COOLDOWNS / TRINKETS", format("%d / %d", seat.cds, seat.trinkets), THEME.statCd)
    if seat.sb then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("SCOREBOARD (SERVER)", THEME.tipHint[1], THEME.tipHint[2], THEME.tipHint[3])
        line("DAMAGE / HEALING", FmtNum(seat.sb.dmg) .. " / " .. FmtNum(seat.sb.heal))
        if db.ArenaScoreboard then
            ArenaScoreTipLines(m, seat, line)
        else
            line("KILLING BLOWS / DEATHS", seat.sb.kb .. " / " .. seat.sb.deaths)
            if seat.sb.ratingChange then
                line("RATING CHANGE", format("%+d", seat.sb.ratingChange),
                    seat.sb.ratingChange >= 0 and THEME.healTx or THEME.danger)
            end
            if seat.sb.mmr then line("MMR", tostring(seat.sb.mmr)) end
        end
    end
    GameTooltip:AddLine("Click for the Arena Report", THEME.tipHint[1], THEME.tipHint[2], THEME.tipHint[3])
    GameTooltip:Show()
end

local function RepaintPane(paneIndex)
    local pane = panes[paneIndex]
    local sel = PaneSelector(paneIndex)
    local seg = PaneSegment(paneIndex)
    local mode = PaneMode(paneIndex)
    local now = time()
    local want = db.MaxRows

    -- External modes paint from their provider and skip the segment
    -- machinery entirely
    if mode.external then
        RepaintExternalPane(pane, mode, want)
        return
    end
    if mode.arena then
        RepaintArenaPane(pane, mode, want)
        return
    end
    -- Non-arena modes never show the team stripe
    for i = 1, want do pane.rows[i].team:Hide() end

    if pane.caption then
        local mc = ModeColor(mode)
        -- The caption is the pane's full statement — MODE in its stat
        -- color, then the segment. The segment trails DIMMED while it is
        -- the window's shared one and switches to the ACCENT the moment
        -- this pane is pinned to a segment of its own: a divergence you
        -- did not ask for can never look like agreement.
        local pinned = paneIndex == 2 and PinnedPane2()
        pane.caption.text:SetText(mode.label
            .. (pinned and ESC.accent or ESC.dim)
            .. "  ·  " .. SegmentLabel(true, sel) .. "|r")
        pane.caption.text:SetTextColor(mc[1], mc[2], mc[3])
    end

    if not seg then
        for i = 1, want do
            local row = pane.rows[i]
            if i == 1 then
                row.rank:SetText("")
                row.name:SetText(sel == "current" and "No active fight" or "No data")
                row.name:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
                row.value:SetText("")
                row.pct:SetText("")
                row.rate:SetText("")
                row.bar:SetWidth(0.001)
                row.guid = nil
                row:Show()
            else
                row:Hide()
            end
        end
        return
    end

    local rowsData, n, total, dur = E.CollectRows(seg, mode, now)
    -- Wheel scroll: the bars window shows a slice of the full ranking;
    -- rank numbers stay true to the actor's real rank
    local maxOff = math.max(0, n - want)
    if pane.offset > maxOff then pane.offset = maxOff end
    local off = pane.offset
    local top = n > 0 and rowsData[1].value or 1
    for i = 1, want do
        local row = pane.rows[i]
        local data = (i + off) <= n and rowsData[i + off]
        if data then
            local actor = data.actor
            local c = ClassColor(actor.class)
            row.guid = actor.guid
            row.rank:SetText(i + off)
            row.name:SetText(ShortName(actor.name))
            row.name:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])
            local big, small
            if mode.primary == "rate" and mode.rateLabel then
                big, small = FmtNum(data.rate), FmtNum(data.value)
            elseif mode.split then
                big = FmtNum(data.value)
                small = SplitText(actor[mode.split[1].field] or 0, actor[mode.split[2].field] or 0)
            else
                big = FmtNum(data.value)
                small = mode.rateLabel and FmtNum(data.rate) or ""
            end
            row.value:SetText(big)
            row.pct:SetText(total > 0 and format("%.0f%%", data.value / total * 100) or "")
            row.rate:SetText(small)
            local frac = top > 0 and data.value / top or 0
            local w = row:GetWidth()
            if w <= 0 then
                w = db.SplitOpen and (db.FrameWidth - 1) / 2 or db.FrameWidth
            end
            row.bar:SetWidth(math.max(frac * w, 0.001))
            row.bar:SetVertexColor(c[1], c[2], c[3], db.BarOpacity or 0.30)
            row:Show()
        else
            row.guid = nil
            row:Hide()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Graph
-- ---------------------------------------------------------------------------

local GRAPH_LINES = 5
local GRAPH_STEP = 2   -- px per sample column
local SMOOTH = 2       -- moving average half-window (5 buckets total)

local graph = {
    lines = {},   -- [i] = {quads={}, used=0, samples={}, guid, color, legend}
    columns = 0,
    span = 1,
    ymax = 1,
}

local function GraphSample(series, b0, b1, nBuckets)
    -- Average rate over [b0..b1], smoothed ±SMOOTH buckets
    local lo, hi = b0 - SMOOTH, b1 + SMOOTH
    if lo < 1 then lo = 1 end
    if hi > nBuckets then hi = nBuckets end
    local sum = 0
    for b = lo, hi do
        sum = sum + (series[b] or 0)
    end
    return sum / (hi - lo + 1)
end

local function LayoutGraphLine(line)
    for q = line.used + 1, #line.quads do
        line.quads[q]:Hide()
    end
end

local function RepaintGraph()
    local plot = graphFrame.plot
    local seg = ViewSegment()
    local mode = panes[1].mode
    local showable = seg and seg ~= E.GetOverall() and seg.series and mode.series
    graphFrame.msg:SetText(
        (not seg and "NO ACTIVE FIGHT") or
        (mode.arena and "THE MATCH TIMELINE LIVES IN THE ARENA REPORT (/cm arena)") or
        (not mode.series and "NO GRAPH FOR THIS MODE") or
        (seg == E.GetOverall() and "PER-FIGHT ONLY — PICK A FIGHT SEGMENT") or
        (not seg.series and "GRAPH EXPIRED (KEPT FOR THE NEWEST 5 FIGHTS)") or "")

    local plotW = plot:GetWidth()
    if plotW <= 0 then plotW = db.FrameWidth - 12 end

    local usedLegend = 0
    if showable then
        local now = time()
        local dur = E.SegmentDuration(seg, now)
        -- The last event of a fight lands in bucket floor(dur)+1 — sample
        -- through it or every closed fight's graph loses its final second
        local nBuckets = math.min(math.floor(dur) + 1, 3600)
        local columns = math.floor(plotW / GRAPH_STEP)
        local span = math.ceil(nBuckets / columns)
        columns = math.ceil(nBuckets / span)
        graph.columns, graph.span = columns, span

        -- Pick the top actors for this mode, honoring legend toggles
        local rowsData, n = E.CollectRows(seg, mode, now)
        local ymax = 0
        local li = 0
        for r = 1, n do
            if li >= GRAPH_LINES then break end
            local actor = rowsData[r].actor
            local series = actor[mode.series]
            if series then
                li = li + 1
                local line = graph.lines[li]
                line.guid = actor.guid
                line.name = ShortName(actor.name)
                line.color = ClassColor(actor.class)
                line.hidden = view.hiddenLines[actor.guid] or false
                local samples = line.samples
                for c = 1, columns do
                    local b0 = (c - 1) * span + 1
                    local v = GraphSample(series, b0, math.min(b0 + span - 1, nBuckets), nBuckets)
                    samples[c] = v
                    if not line.hidden and v > ymax then ymax = v end
                end
                for c = columns + 1, #samples do samples[c] = nil end
            end
        end
        usedLegend = li
        graph.used = li
        graph.ymax = ymax > 0 and ymax or 1

        for i = 1, li do
            local line = graph.lines[i]
            line.used = 0
            if not line.hidden then
                for c = 1, columns do
                    local v = line.samples[c]
                    local h = v / graph.ymax * (THEME.plotH - 4)
                    line.used = line.used + 1
                    local quad = line.quads[line.used]
                    if not quad then
                        quad = plot:CreateTexture(nil, "ARTWORK")
                        quad:SetTexture(WHITE)
                        quad:SetSize(GRAPH_STEP, 2)
                        line.quads[line.used] = quad
                    end
                    quad:SetVertexColor(line.color[1], line.color[2], line.color[3], 0.95)
                    quad:ClearAllPoints()
                    quad:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", (c - 1) * GRAPH_STEP, h)
                    quad:Show()
                end
            end
            LayoutGraphLine(line)
        end
        graphFrame.scale:SetText(FmtNum(graph.ymax * (mode.rateScale or 1)) .. " " .. (mode.rateLabel or "/S"))
        local mc = ModeColor(mode)
        graphFrame.scale:SetTextColor(mc[1], mc[2], mc[3])
        -- Honest about the series cap: buckets stop at one hour
        if math.floor(dur) + 1 > 3600 then
            graphFrame.span:SetText("FIRST HOUR SHOWN · " .. FmtTime(dur))
        else
            graphFrame.span:SetText(FmtTime(dur))
        end
    else
        graph.used = 0
        graphFrame.scale:SetText("")
        graphFrame.span:SetText("")
    end
    for i = graph.used + 1, GRAPH_LINES do
        local line = graph.lines[i]
        line.guid = nil
        line.used = 0
        LayoutGraphLine(line)
    end

    -- Legend chips: pitch derives from the live legend width so five chips
    -- always fit inside the window at any Window Width
    local legendW = graphFrame.legend:GetWidth()
    if not legendW or legendW <= 0 then legendW = db.FrameWidth - 12 end
    local pitch = math.floor(legendW / GRAPH_LINES)
    for i = 1, GRAPH_LINES do
        local line = graph.lines[i]
        local chip = line.legend
        chip:SetWidth(math.max(pitch - 3, 20))
        chip:ClearAllPoints()
        chip:SetPoint("LEFT", graphFrame.legend, "LEFT", (i - 1) * pitch, 0)
        if i <= usedLegend then
            chip.swatch:SetVertexColor(line.color[1], line.color[2], line.color[3], line.hidden and 0.25 or 1)
            chip.text:SetText(line.name or "?")
            chip.text:SetTextColor(
                line.hidden and THEME.textDim[1] or THEME.text[1],
                line.hidden and THEME.textDim[2] or THEME.text[2],
                line.hidden and THEME.textDim[3] or THEME.text[3])
            chip:Show()
        else
            chip:Hide()
        end
    end
end

local function BuildGraph()
    graphFrame = CreateFrame("Frame", nil, root)
    graphFrame:SetHeight(THEME.graphH)

    local legend = CreateFrame("Frame", nil, graphFrame)
    graphFrame.legend = legend
    legend:SetHeight(14)
    legend:SetPoint("TOPLEFT", graphFrame, "TOPLEFT", 6, -2)
    legend:SetPoint("RIGHT", graphFrame, "RIGHT", -6, 0)

    local plot = CreateFrame("Frame", nil, graphFrame)
    graphFrame.plot = plot
    plot:SetPoint("TOPLEFT", graphFrame, "TOPLEFT", 6, -18)
    plot:SetPoint("RIGHT", graphFrame, "RIGHT", -6, 0)
    plot:SetHeight(THEME.plotH)
    plot.fill = plot:CreateTexture(nil, "BACKGROUND")
    plot.fill:SetTexture(WHITE)
    plot.fill:SetVertexColor(THEME.plotFill[1], THEME.plotFill[2], THEME.plotFill[3], THEME.plotFill[4])
    plot.fill:SetAllPoints()
    MakeEdge(plot)

    graphFrame.msg = MakeText(plot, THEME.fontSize, "CENTER")
    graphFrame.msg:SetPoint("CENTER")
    graphFrame.msg:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])

    graphFrame.scale = MakeText(plot, THEME.fontSizeSmall, "LEFT")
    graphFrame.scale:SetPoint("TOPLEFT", plot, "TOPLEFT", 3, -2)
    graphFrame.scale:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
    graphFrame.span = MakeText(plot, THEME.fontSizeSmall, "RIGHT")
    graphFrame.span:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", -3, 2)
    graphFrame.span:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])

    -- Hover readout: hairline + values at the hovered second
    plot.hair = plot:CreateTexture(nil, "OVERLAY")
    plot.hair:SetTexture(WHITE)
    plot.hair:SetVertexColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.8)
    plot.hair:SetWidth(1)
    plot.hair:SetPoint("TOP", plot, "TOPLEFT", 0, 0)
    plot.hair:SetPoint("BOTTOM", plot, "BOTTOMLEFT", 0, 0)
    plot.hair:Hide()
    plot.readout = MakeText(plot, THEME.fontSizeSmall, "CENTER")
    plot.readout:SetPoint("TOP", plot, "TOP", 0, 12)
    plot.readout:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])

    plot:EnableMouse(true)
    plot:SetScript("OnEnter", function() plot.hovering = true end)
    plot:SetScript("OnLeave", function()
        plot.hovering = false
        plot.hair:Hide()
        plot.readout:SetText("")
    end)
    plot:SetScript("OnUpdate", function(self)
        if not self.hovering or graph.used == 0 then return end
        local x = GetCursorPosition() / self:GetEffectiveScale() - self:GetLeft()
        local c = math.floor(x / GRAPH_STEP) + 1
        if c < 1 or c > graph.columns then
            self.hair:Hide()
            self.readout:SetText("")
            return
        end
        self.hair:ClearAllPoints()
        self.hair:SetPoint("TOP", self, "TOPLEFT", (c - 0.5) * GRAPH_STEP, 0)
        self.hair:SetPoint("BOTTOM", self, "BOTTOMLEFT", (c - 0.5) * GRAPH_STEP, 0)
        self.hair:Show()
        local out = FmtTime((c - 1) * graph.span)
        for i = 1, graph.used do
            local line = graph.lines[i]
            if not line.hidden and line.samples[c] then
                out = out .. " · " .. (line.name or "?") .. " " .. FmtNum(line.samples[c])
            end
        end
        self.readout:SetText(out)
    end)

    for i = 1, GRAPH_LINES do
        local chip = CreateFrame("Button", nil, legend)
        chip:SetSize(44, 14) -- resized to the live legend pitch on repaint
        chip:SetPoint("LEFT", legend, "LEFT", (i - 1) * 46, 0)
        chip.swatch = chip:CreateTexture(nil, "ARTWORK")
        chip.swatch:SetTexture(WHITE)
        chip.swatch:SetSize(7, 7)
        chip.swatch:SetPoint("LEFT")
        chip.text = MakeText(chip, THEME.fontSizeSmall, "LEFT")
        chip.text:SetPoint("LEFT", chip.swatch, "RIGHT", 3, 0)
        chip.text:SetPoint("RIGHT", chip, "RIGHT", 0, 0)
        local index = i
        chip:SetScript("OnClick", function()
            local line = graph.lines[index]
            if line.guid then
                view.hiddenLines[line.guid] = not view.hiddenLines[line.guid] or nil
                RepaintGraph()
            end
        end)
        graph.lines[i] = { quads = {}, used = 0, samples = {}, legend = chip }
    end
end

-- ---------------------------------------------------------------------------
-- Detail window (abilities/targets + pie, or the death log + health curve)
-- ---------------------------------------------------------------------------

local detailAbilityRows, detailTargetRows = {}, {}
local detailScratch, detailScratch2 = {}, {}
local detailN1, detailN2 = 0, 0 -- record counts from the last repaint
local pieFrame, curveFrame
local ShareMenu -- forward: the detail head's share glyph opens the channel menu

local DETAIL_BASE_H = 20 + 16 + (THEME.detailRows + 1) * (THEME.rowH - 1)
    + (THEME.deathTrailRows + 1) * (THEME.rowH - 1) + 18

local function DetailMode()
    return PaneMode(view.detailPane)
end

-- The detail belongs to the pane its bar was clicked in — comparing, that
-- is also which SEGMENT it reads, so its subtitle must never quote the
-- window's selection over the pane's
local function DetailSelector()
    return PaneSelector(view.detailPane)
end

local function BuildDetailRow(parent, small)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(THEME.rowH - 2)
    row.hover = row:CreateTexture(nil, "HIGHLIGHT")
    row.hover:SetTexture(WHITE)
    row.hover:SetVertexColor(1, 1, 1, THEME.hover[4])
    row.hover:SetAllPoints()
    -- The 10px left gutter is reserved for the pie-slice swatch, so the
    -- name column never moves when the pie opens
    row.swatch = row:CreateTexture(nil, "ARTWORK")
    row.swatch:SetTexture(WHITE)
    row.swatch:SetSize(7, 7)
    row.swatch:SetPoint("LEFT", row, "LEFT", 3, 0)
    row.swatch:Hide()
    row.name = MakeText(row, small and THEME.fontSizeSmall or THEME.fontSize, "LEFT")
    row.name:SetPoint("LEFT", row, "LEFT", 14, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -128, 0)
    row.value = MakeText(row, THEME.fontSize, "RIGHT")
    row.value:SetPoint("RIGHT", row, "RIGHT", -78, 0)
    row.value:SetWidth(50)
    row.pct = MakeText(row, THEME.fontSizeSmall, "RIGHT")
    row.pct:SetPoint("RIGHT", row, "RIGHT", -44, 0)
    row.pct:SetWidth(34)
    row.pct:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
    row.extra = MakeText(row, THEME.fontSizeSmall, "RIGHT")
    row.extra:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.extra:SetWidth(40)
    row.extra:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
    return row
end

-- Hoisted comparator: the 2 Hz detail repaint must not allocate closures
local function RecOrder(x, y)
    if x.key == nil then return false end
    if y.key == nil then return true end
    if x.value ~= y.value then return x.value > y.value end
    return x.key < y.key
end

local function SortedRecords(map, scratch)
    local n = 0
    for key, rec in pairs(map) do
        n = n + 1
        local slot = scratch[n]
        if not slot then slot = {}; scratch[n] = slot end
        slot.key = key
        slot.rec = rec
        slot.value = type(rec) == "table" and rec.total or rec
    end
    for i = n + 1, #scratch do scratch[i].key = nil end
    table.sort(scratch, RecOrder)
    return n
end

local function AbilityTooltip(row)
    local rec = row.recRef
    if not rec or type(rec) ~= "table" then return end
    local td, tf = THEME.tipDim, THEME.tipFaint
    local hits = rec.count
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    -- Title carries the spell's own icon
    GameTooltip:SetText(IconTag(rec, 18) .. " " .. (row.keyRef or "?"), 1, 1, 1)
    GameTooltip:AddDoubleLine("HITS", tostring(hits),
        td[1], td[2], td[3], tf[1], tf[2], tf[3])
    if hits > 0 or rec.crit > 0 then
        GameTooltip:AddDoubleLine("CRITS", format("%d  (%.0f%%)",
            rec.crit, hits > 0 and rec.crit / hits * 100 or 0),
            td[1], td[2], td[3], THEME.statCrit[1], THEME.statCrit[2], THEME.statCrit[3])
    end
    if rec.miss > 0 then
        GameTooltip:AddDoubleLine("MISSES", tostring(rec.miss),
            td[1], td[2], td[3], THEME.statMiss[1], THEME.statMiss[2], THEME.statMiss[3])
    end
    if hits > 0 and rec.min then
        GameTooltip:AddDoubleLine("MIN / AVG / MAX",
            format("%s · %s%s|r · %s", FmtNum(rec.min or 0), ESC.text,
                FmtNum(rec.total / hits), FmtNum(rec.max or 0)),
            td[1], td[2], td[3], tf[1], tf[2], tf[3])
    end
    if rec.glance > 0 then
        GameTooltip:AddDoubleLine("GLANCING", format("%d  (%.0f%%)",
            rec.glance, hits > 0 and rec.glance / hits * 100 or 0),
            td[1], td[2], td[3], THEME.tipGlance[1], THEME.tipGlance[2], THEME.tipGlance[3])
    end
    if rec.crush > 0 then
        GameTooltip:AddDoubleLine("CRUSHING", format("%d  (%.0f%%)",
            rec.crush, hits > 0 and rec.crush / hits * 100 or 0),
            td[1], td[2], td[3], THEME.tipGlance[1], THEME.tipGlance[2], THEME.tipGlance[3])
    end
    if rec.resisted > 0 then
        GameTooltip:AddDoubleLine("RESISTED", FmtNum(rec.resisted),
            td[1], td[2], td[3], THEME.tipResist[1], THEME.tipResist[2], THEME.tipResist[3])
    end
    if rec.blocked > 0 then
        GameTooltip:AddDoubleLine("BLOCKED", FmtNum(rec.blocked),
            td[1], td[2], td[3], THEME.tipBlock[1], THEME.tipBlock[2], THEME.tipBlock[3])
    end
    if rec.absorbed > 0 then
        GameTooltip:AddDoubleLine("ABSORBED BY SHIELDS", FmtNum(rec.absorbed),
            td[1], td[2], td[3], THEME.tipAbsorb[1], THEME.tipAbsorb[2], THEME.tipAbsorb[3])
    end
    if rec.overheal > 0 then
        GameTooltip:AddDoubleLine("OVERHEAL", FmtNum(rec.overheal),
            td[1], td[2], td[3], THEME.tipHeal[1], THEME.tipHeal[2], THEME.tipHeal[3])
    end
    GameTooltip:Show()
end

-- Death-log entries keep the raw spellId, so their hover tooltip is the
-- real spell tooltip (what the ability actually does) with the event's
-- own numbers appended under it. Melee/environmental entries have no id
-- and fall back to a plain titled tooltip.
local function DeathEntryTooltip(row, entry, deathTs)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local shown = entry.id and pcall(GameTooltip.SetSpellByID, GameTooltip, entry.id)
    if not shown and entry.id then
        shown = pcall(GameTooltip.SetHyperlink, GameTooltip, "spell:" .. entry.id)
    end
    if not shown then
        GameTooltip:SetText(IconTag(entry, 18) .. " " .. (entry.what or "?"), 1, 1, 1)
    end
    local td, tf = THEME.tipDim, THEME.tipFaint
    if entry.amount then
        local heal = entry.kind == 2
        local c = heal and THEME.healTx or THEME.danger
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(heal and "HEALED FOR" or "HIT FOR",
            (heal and "+" or "-") .. FmtNum(entry.amount),
            td[1], td[2], td[3], c[1], c[2], c[3])
    end
    if entry.hp and entry.hpMax and entry.hpMax > 0 then
        local frac = entry.hp / entry.hpMax
        local hc = HpColor(frac)
        GameTooltip:AddDoubleLine("HP AFTER", format("%d%%", frac * 100),
            td[1], td[2], td[3], hc[1], hc[2], hc[3])
    end
    if deathTs and entry.ts then
        GameTooltip:AddDoubleLine("BEFORE DEATH", format("%.1fs", deathTs - entry.ts),
            td[1], td[2], td[3], tf[1], tf[2], tf[3])
    end
    GameTooltip:Show()
end

-- Pie: each slice is one entry's share of the list total, drawn as ~120
-- thin rotated spokes from a pooled set (no wedge art, no libraries).
local PIE_SPOKES = 120
local PIE_R = 44

local pieSlices = {} -- [i] = {frac, color, key} reused

local function RepaintPie()
    if not view.pieList then
        pieFrame:Hide()
        return
    end
    local scratch = view.pieList == 1 and detailScratch or detailScratch2
    local n = view.pieList == 1 and detailN1 or detailN2
    if n == 0 then
        pieFrame:Hide()
        return
    end
    pieFrame:Show()

    local total = 0
    for i = 1, n do total = total + scratch[i].value end
    if total <= 0 then
        pieFrame:Hide()
        return
    end

    -- Top 8 slices + OTHER
    local sliceCount = math.min(n, 8)
    local acc = 0
    for i = 1, sliceCount do
        local s = pieSlices[i]
        if not s then s = {}; pieSlices[i] = s end
        s.frac = scratch[i].value / total
        s.color = THEME.pieColors[i]
        s.key = scratch[i].key
        acc = acc + s.frac
    end
    local slices = sliceCount
    if acc < 0.999 then
        slices = sliceCount + 1
        local s = pieSlices[slices]
        if not s then s = {}; pieSlices[slices] = s end
        s.frac = 1 - acc
        s.color = THEME.pieOther
        s.key = nil
    end

    -- Selected readout. A clicked entry ranked past the top 8 keeps its own
    -- identity: its readout shows its own share while the OTHER slice
    -- highlights — the key is never stomped, so click-again-to-close works
    -- for every row.
    local selPct, selName, selIsOther
    for i = 1, sliceCount do
        if pieSlices[i].key == view.pieKey then
            selPct, selName = pieSlices[i].frac * 100, pieSlices[i].key
        end
    end
    if not selPct then
        for i = 1, n do
            if scratch[i].key == view.pieKey then
                selPct = scratch[i].value / total * 100
                selName = view.pieKey
                selIsOther = true
                break
            end
        end
    end
    if not selPct then
        -- The selected entry vanished entirely (reset, segment switch)
        selPct, selName = pieSlices[1].frac * 100, pieSlices[1].key
        view.pieKey = pieSlices[1].key
    end
    -- The readout wears the selected slice's color, tying number to wedge
    local selColor = THEME.accent
    if selIsOther then
        selColor = THEME.pieOther
    else
        for i = 1, sliceCount do
            if pieSlices[i].key == view.pieKey then selColor = pieSlices[i].color end
        end
    end
    pieFrame.pct:SetText(format("%.0f%%", selPct))
    pieFrame.pct:SetTextColor(selColor[1], selColor[2], selColor[3])
    pieFrame.label:SetText(selName or "?")
    pieFrame.label:SetTextColor(selColor[1], selColor[2], selColor[3])

    -- Paint the spokes
    local twoPi = math.pi * 2
    local sliceIdx, sliceEnd = 1, pieSlices[1].frac
    for sp = 1, PIE_SPOKES do
        local frac = (sp - 0.5) / PIE_SPOKES
        while frac > sliceEnd and sliceIdx < slices do
            sliceIdx = sliceIdx + 1
            sliceEnd = sliceEnd + pieSlices[sliceIdx].frac
        end
        local quad = pieFrame.spokes[sp]
        if not quad then
            quad = pieFrame:CreateTexture(nil, "ARTWORK")
            quad:SetTexture(WHITE)
            quad:SetSize(3, PIE_R)
            pieFrame.spokes[sp] = quad
        end
        local color = pieSlices[sliceIdx].color
        local sel = pieSlices[sliceIdx].key == view.pieKey
            or (selIsOther and pieSlices[sliceIdx].key == nil)
        quad:SetVertexColor(color[1], color[2], color[3], sel and 1 or 0.8)
        local theta = frac * twoPi
        quad:ClearAllPoints()
        quad:SetPoint("CENTER", pieFrame, "LEFT",
            10 + PIE_R + math.sin(theta) * PIE_R / 2,
            math.cos(theta) * PIE_R / 2)
        quad:SetRotation(-theta)
        quad:Show()
    end
end

local function BuildPie()
    pieFrame = CreateFrame("Frame", nil, detailFrame)
    pieFrame:SetHeight(THEME.pieH)
    pieFrame:SetPoint("BOTTOMLEFT", detailFrame, "BOTTOMLEFT", 4, 14)
    pieFrame:SetPoint("RIGHT", detailFrame, "RIGHT", -4, 0)
    pieFrame.spokes = {}
    pieFrame.pct = MakeText(pieFrame, 16, "LEFT")
    pieFrame.pct:SetPoint("LEFT", pieFrame, "LEFT", 10 + PIE_R * 2 + 14, 8)
    pieFrame.pct:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])
    pieFrame.label = MakeText(pieFrame, THEME.fontSize, "LEFT")
    pieFrame.label:SetPoint("TOPLEFT", pieFrame.pct, "BOTTOMLEFT", 0, -2)
    pieFrame.label:SetPoint("RIGHT", pieFrame, "RIGHT", -4, 0)
    pieFrame.hint = MakeText(pieFrame, THEME.fontSizeSmall, "LEFT")
    pieFrame.hint:SetPoint("TOPLEFT", pieFrame.label, "BOTTOMLEFT", 0, -6)
    pieFrame.hint:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
    pieFrame.hint:SetText("SHARES OF THIS LIST\nHOVER ANY ROW TO INSPECT IT")
    pieFrame:Hide()
end

-- Death health curve: HP% over the trail window, damage red / heals green,
-- ending in the drop to zero.
local function RepaintCurve()
    local d = view.detailDeath
    local mode = DetailMode()
    if not (mode.deaths and d and #d.log > 0) then
        curveFrame:Hide()
        return
    end
    curveFrame:Show()
    local w = curveFrame:GetWidth()
    if not w or w <= 0 then w = THEME.detailW - 8 end
    local h = THEME.curveH - 8
    local pad = 8
    local n = #d.log

    -- Collect drawable points (entries with an hp snapshot)
    local used = 0
    for i = 1, n do
        local entry = d.log[i]
        if entry.hp and entry.hpMax and entry.hpMax > 0 then
            used = used + 1
            local pt = curveFrame.points[used]
            if not pt then
                pt = curveFrame:CreateTexture(nil, "OVERLAY")
                pt:SetTexture(WHITE)
                pt:SetSize(4, 4)
                curveFrame.points[used] = pt
            end
            -- x always reflects the entry's position in the trail, even
            -- when leading entries had no hp snapshot to draw
            local x = pad + (i - 1) / n * (w - pad * 2)
            local y = 4 + (entry.hp / entry.hpMax) * (h - 8)
            local c = entry.kind == 2 and THEME.healTx or THEME.danger
            pt:SetVertexColor(c[1], c[2], c[3], 1)
            pt:ClearAllPoints()
            pt:SetPoint("CENTER", curveFrame, "BOTTOMLEFT", x, y)
            pt:Show()
            pt.x, pt.y = x, y
        end
    end
    -- The death itself: hp hits zero at the right edge
    used = used + 1
    local zero = curveFrame.points[used]
    if not zero then
        zero = curveFrame:CreateTexture(nil, "OVERLAY")
        zero:SetTexture(WHITE)
        zero:SetSize(4, 4)
        curveFrame.points[used] = zero
    end
    zero:SetVertexColor(THEME.danger[1], THEME.danger[2], THEME.danger[3], 1)
    zero:ClearAllPoints()
    zero:SetPoint("CENTER", curveFrame, "BOTTOMLEFT", w - pad, 4)
    zero:Show()
    zero.x, zero.y = w - pad, 4
    for i = used + 1, #curveFrame.points do curveFrame.points[i]:Hide() end

    -- Connect consecutive points with rotated segments
    local segs = 0
    for i = 2, used do
        local a, b = curveFrame.points[i - 1], curveFrame.points[i]
        local dx, dy = b.x - a.x, b.y - a.y
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 1 then
            segs = segs + 1
            local q = curveFrame.segs[segs]
            if not q then
                q = curveFrame:CreateTexture(nil, "ARTWORK")
                q:SetTexture(WHITE)
                curveFrame.segs[segs] = q
            end
            q:SetSize(len, 2)
            q:SetVertexColor(THEME.text[1], THEME.text[2], THEME.text[3], 0.7)
            q:ClearAllPoints()
            q:SetPoint("CENTER", curveFrame, "BOTTOMLEFT", (a.x + b.x) / 2, (a.y + b.y) / 2)
            q:SetRotation(math.atan2(dy, dx))
            q:Show()
        end
    end
    for i = segs + 1, #curveFrame.segs do curveFrame.segs[i]:Hide() end
end

local function BuildCurve()
    curveFrame = CreateFrame("Frame", nil, detailFrame)
    curveFrame:SetHeight(THEME.curveH)
    curveFrame:SetPoint("BOTTOMLEFT", detailFrame, "BOTTOMLEFT", 4, 14)
    curveFrame:SetPoint("RIGHT", detailFrame, "RIGHT", -4, 0)
    curveFrame.fill = curveFrame:CreateTexture(nil, "BACKGROUND")
    curveFrame.fill:SetTexture(WHITE)
    curveFrame.fill:SetVertexColor(THEME.plotFill[1], THEME.plotFill[2], THEME.plotFill[3], THEME.plotFill[4])
    curveFrame.fill:SetAllPoints()
    MakeEdge(curveFrame)
    curveFrame.points = {}
    curveFrame.segs = {}
    curveFrame.tag = MakeText(curveFrame, THEME.fontSizeSmall, "LEFT")
    curveFrame.tag:SetPoint("TOPLEFT", curveFrame, "TOPLEFT", 3, -2)
    curveFrame.tag:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
    curveFrame.tag:SetText("HP")
    curveFrame:Hide()
end

RepaintDetail = function()
    if not detailFrame:IsShown() then return end
    local seg = PaneSegment(view.detailPane)
    local mode = DetailMode()
    local now = time()

    -- External rows never open the detail (no guid), but a detail already
    -- open when its pane SWITCHES to an external mode would repaint through
    -- segment fields the mode does not have — close it instead
    if mode.external or mode.arena then
        view.detailGuid = nil
        detailFrame:Hide()
        return
    end

    -- Deaths mode: the detail window is the death log + health curve
    if mode.deaths then
        pieFrame:Hide()
        detailFrame:SetHeight(DETAIL_BASE_H + THEME.curveH + 4)
        detailFrame.title:SetText("DEATH LOG")
        detailFrame.title:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])
        detailFrame.sub:SetText(SegmentLabel(nil, DetailSelector()))
        detailFrame.list1Title:SetText("DEATHS (CLICK ONE)")
        detailFrame.list2Title:SetText("LAST EVENTS BEFORE DEATH")
        detailFrame.col1V:SetText("TIME")
        detailFrame.col1P:SetText("")
        detailFrame.col1E:SetText("")
        detailFrame.col2V:SetText("AMOUNT")
        detailFrame.col2P:SetText("HP")
        detailFrame.col2E:SetText("")
        -- Collect deaths: fight segments own their logs; Overall aggregates
        local deaths = detailScratch
        local n = 0
        local function harvest(s)
            if not s then return end
            for i = #s.deaths, 1, -1 do
                n = n + 1
                local slot = deaths[n]
                if not slot then slot = {}; deaths[n] = slot end
                slot.death = s.deaths[i]
            end
        end
        if view.segSel == "overall" then
            harvest(E.GetCurrent())
            local fightList = E.GetFights()
            for i = 1, #fightList do harvest(fightList[i]) end
        else
            harvest(seg)
        end
        for i = n + 1, #deaths do deaths[i].death = nil end
        detailN1 = 0

        -- Self-healing selection: after any wipe (button, slash, auto-reset,
        -- engine-side) a stale selected death must never keep painting
        local selValid = false
        for i = 1, n do
            if deaths[i].death == view.detailDeath then selValid = true end
        end
        if not selValid then
            view.detailDeath = n > 0 and deaths[1].death or nil
        end
        -- The share glyph exists exactly when there is a death to report
        detailFrame.share:SetShown(view.detailDeath ~= nil)

        local maxOff = math.max(0, n - THEME.detailRows)
        if view.abilityOffset > maxOff then view.abilityOffset = maxOff end
        for i = 1, THEME.detailRows do
            local row = detailAbilityRows[i]
            local slot = deaths[i + view.abilityOffset]
            row.swatch:Hide()
            if slot and slot.death then
                local d = slot.death
                local blow = d.log[#d.log]
                row.name:SetText(ShortName(d.name)
                    .. (blow and (" — " .. IconTag(blow, 12) .. " " .. (blow.what or "?")) or ""))
                row.name:SetTextColor(THEME.danger[1], THEME.danger[2], THEME.danger[3])
                row.value:SetText(date("%H:%M:%S", d.ts))
                row.value:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
                row.pct:SetText("")
                row.extra:SetText("")
                row.deathRef = d
                row.blowRef = blow
                row.recRef = nil
                row.keyRef = nil
                row:Show()
            else
                row.deathRef = nil
                row.blowRef = nil
                row:Hide()
            end
        end
        local d = view.detailDeath
        for i = 1, THEME.deathTrailRows do
            local row = detailTargetRows[i]
            if not row then break end
            row.swatch:Hide()
            local entry = d and d.log[#d.log - i + 1]
            if entry then
                local hasHp = entry.hp and entry.hpMax and entry.hpMax > 0
                local hpText = hasHp and format("%d%%", entry.hp / entry.hpMax * 100) or "?"
                row.name:SetText(format("-%.1fs  %s %s", d.ts - entry.ts,
                    IconTag(entry, 12), entry.what or "?"))
                local c = entry.kind == 2 and THEME.healTx or THEME.danger
                row.name:SetTextColor(c[1], c[2], c[3])
                row.value:SetText((entry.kind == 2 and "+" or "-") .. FmtNum(entry.amount or 0))
                row.value:SetTextColor(c[1], c[2], c[3])
                row.pct:SetText(hpText)
                -- HP readout by threshold: the death spiral reads by color
                local hc = hasHp and HpColor(entry.hp / entry.hpMax) or THEME.textDim
                row.pct:SetTextColor(hc[1], hc[2], hc[3])
                row.extra:SetText("HP")
                row.extra:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
                row.recRef = nil
                row.logRef = entry
                row.keyRef = nil
                row:Show()
            else
                row.logRef = nil
                row:Hide()
            end
        end
        RepaintCurve()
        return
    end

    curveFrame:Hide()
    detailFrame.share:Hide()
    detailFrame:SetHeight(DETAIL_BASE_H + THEME.pieH + 4) -- pie is always on

    local actor = seg and seg.actors[view.detailGuid]
    if not actor then
        detailFrame.title:SetText("NO DATA IN THIS SEGMENT")
        detailFrame.title:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
        detailFrame.sub:SetText(SegmentLabel(nil, DetailSelector()))
        detailFrame.list1Title:SetText("")
        detailFrame.list2Title:SetText("")
        detailFrame.col1V:SetText("")
        detailFrame.col1P:SetText("")
        detailFrame.col1E:SetText("")
        detailFrame.col2V:SetText("")
        detailFrame.col2P:SetText("")
        detailFrame.col2E:SetText("")
        for i = 1, THEME.detailRows do detailAbilityRows[i]:Hide() end
        for i = 1, #detailTargetRows do detailTargetRows[i]:Hide() end
        pieFrame:Hide()
        return
    end

    local c = ClassColor(actor.class)
    local mc = ModeColor(mode)
    detailFrame.title:SetText(ShortName(actor.name):upper())
    detailFrame.title:SetTextColor(c[1], c[2], c[3])
    local total = mode.value(actor)
    local dur = E.SegmentDuration(seg, now)
    detailFrame.sub:SetText(format("%s%s|r · %s · %s%s|r%s%s",
        EscOf(mc), mode.label, SegmentLabel(nil, DetailSelector()), EscOf(mc), FmtNum(total),
        mode.rateLabel and format(" (%s %s)", FmtNum(ModeRate(mode, total, dur)), mode.rateLabel) or "",
        mode.active and format(" · ACTIVE %s", FmtTime(actor[mode.active])) or ""))

    local lists = mode.lists
    local spec1, spec2 = lists[1], lists[2]

    detailFrame.list1Title:SetText(spec1 and spec1.title or "")
    detailFrame.col1V:SetText(spec1 and "TOTAL" or "")
    detailFrame.col1P:SetText(spec1 and "%" or "")
    detailFrame.col1E:SetText(spec1 and "N/CRIT" or "")
    if spec1 then
        local n = SortedRecords(actor[spec1.field], detailScratch)
        detailN1 = n
        local maxOff = math.max(0, n - THEME.detailRows)
        if view.abilityOffset > maxOff then view.abilityOffset = maxOff end
        for i = 1, THEME.detailRows do
            local row = detailAbilityRows[i]
            local idx = i + view.abilityOffset
            local slot = detailScratch[idx]
            if slot and slot.key then
                local rec = slot.rec
                row.name:SetText((type(rec) == "table" and (IconTag(rec, 12) .. " ") or "") .. slot.key)
                row.name:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])
                row.value:SetText(FmtNum(slot.value))
                row.value:SetTextColor(mc[1], mc[2], mc[3])
                row.pct:SetText(total > 0 and format("%.0f%%", slot.value / total * 100) or "")
                if type(rec) == "table" and rec.min then
                    row.extra:SetText(format("%d/%d", rec.count, rec.crit))
                    -- Crit-carrying abilities flag themselves in gold
                    local xc = rec.crit > 0 and THEME.statCrit or THEME.textDim
                    row.extra:SetTextColor(xc[1], xc[2], xc[3])
                else
                    row.extra:SetText("")
                end
                row.recRef = type(rec) == "table" and rec or nil
                row.keyRef = slot.key
                row.listIndex = 1
                row.deathRef = nil
                row.blowRef = nil
                if view.pieList == 1 then
                    local color = idx <= 8 and THEME.pieColors[idx] or THEME.pieOther
                    row.swatch:SetVertexColor(color[1], color[2], color[3], 1)
                    row.swatch:Show()
                else
                    row.swatch:Hide()
                end
                row:Show()
            else
                row:Hide()
            end
        end
    else
        detailN1 = 0
        for i = 1, THEME.detailRows do detailAbilityRows[i]:Hide() end
    end

    detailFrame.list2Title:SetText(spec2 and spec2.title or "")
    detailFrame.col2V:SetText(spec2 and "TOTAL" or "")
    detailFrame.col2P:SetText(spec2 and "%" or "")
    detailFrame.col2E:SetText("")
    if spec2 then
        local n = SortedRecords(actor[spec2.field], detailScratch2)
        detailN2 = n
        local maxOff = math.max(0, n - THEME.detailSubRows)
        if view.targetOffset > maxOff then view.targetOffset = maxOff end
        for i = 1, THEME.detailSubRows do
            local row = detailTargetRows[i]
            local idx = i + view.targetOffset
            local slot = detailScratch2[idx]
            if slot and slot.key then
                -- A records list (aura names) keeps its icons and the whole
                -- name: ShortName would cut "Mind-numbing Poison" at the dash
                if spec2.records then
                    local rec = slot.rec
                    row.name:SetText((type(rec) == "table" and (IconTag(rec, 12) .. " ") or "") .. slot.key)
                else
                    row.name:SetText(ShortName(slot.key))
                end
                row.name:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])
                row.value:SetText(FmtNum(slot.value))
                row.value:SetTextColor(mc[1], mc[2], mc[3])
                row.pct:SetText(total > 0 and format("%.0f%%", slot.value / total * 100) or "")
                row.pct:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
                row.extra:SetText("")
                row.extra:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
                row.recRef = nil
                row.logRef = nil
                row.keyRef = slot.key
                row.listIndex = 2
                if view.pieList == 2 then
                    local color = idx <= 8 and THEME.pieColors[idx] or THEME.pieOther
                    row.swatch:SetVertexColor(color[1], color[2], color[3], 1)
                    row.swatch:Show()
                else
                    row.swatch:Hide()
                end
                row:Show()
            else
                row:Hide()
            end
        end
        for i = THEME.detailSubRows + 1, #detailTargetRows do detailTargetRows[i]:Hide() end
    else
        detailN2 = 0
        for i = 1, #detailTargetRows do detailTargetRows[i]:Hide() end
    end

    RepaintPie()
end

local function DetailRowClick(row)
    if row.deathRef then
        view.detailDeath = row.deathRef
        RepaintDetail()
        return
    end
    if row.keyRef and row.listIndex then
        -- Clicking still selects (hover already did); kept so muscle
        -- memory from the click era never dead-ends
        view.pieList, view.pieKey = row.listIndex, row.keyRef
        RepaintDetail()
    end
end

-- Hover drives inspection: resting the mouse on any record row re-targets
-- the pie to it — readout, swatch hand-off, slice highlight — with no
-- click, and raises its tooltip. The selection is sticky on leave so the
-- readout survives the mouse traveling over to the pie to read it.
-- Death rows tooltip only: selecting the inspected death stays on click,
-- because the mouse path from a death row down to its trail crosses the
-- other death rows, and hover-select would re-target mid-travel.
local function DetailRowHover(row)
    if row.logRef then
        local d = view.detailDeath
        DeathEntryTooltip(row, row.logRef, d and d.ts)
        return
    end
    if row.deathRef then
        if row.blowRef then
            DeathEntryTooltip(row, row.blowRef, row.deathRef.ts)
        end
        return
    end
    if row.keyRef and row.listIndex
        and (view.pieList ~= row.listIndex or view.pieKey ~= row.keyRef) then
        view.pieList, view.pieKey = row.listIndex, row.keyRef
        RepaintDetail()
    end
    AbilityTooltip(row)
end

local function BuildDetail()
    -- A floating popup, not a side panel: opens screen-center, dragged by
    -- its title bar, and keeps wherever you put it for the session
    detailFrame = CreateFrame("Frame", "CommanderMetersDetailFrame", UIParent)
    detailFrame:SetSize(THEME.detailW, DETAIL_BASE_H)
    detailFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    detailFrame:SetFrameStrata("DIALOG")
    detailFrame:SetMovable(true)
    detailFrame:SetClampedToScreen(true)
    detailFrame.fill = detailFrame:CreateTexture(nil, "BACKGROUND")
    detailFrame.fill:SetTexture(WHITE)
    detailFrame.fill:SetVertexColor(THEME.bg[1], THEME.bg[2], THEME.bg[3], THEME.bg[4])
    detailFrame.fill:SetAllPoints()
    MakeEdge(detailFrame)
    detailFrame:Hide()
    tinsert(UISpecialFrames, "CommanderMetersDetailFrame")

    local head = CreateFrame("Frame", nil, detailFrame)
    head:SetHeight(THEME.headerH)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head.fill = head:CreateTexture(nil, "BACKGROUND")
    head.fill:SetTexture(WHITE)
    head.fill:SetVertexColor(THEME.chrome[1], THEME.chrome[2], THEME.chrome[3], THEME.chrome[4])
    head.fill:SetAllPoints()
    -- The title bar is the drag handle (the close button, a child, wins
    -- clicks over it as usual)
    head:EnableMouse(true)
    head:RegisterForDrag("LeftButton")
    head:SetScript("OnDragStart", function()
        detailFrame:StartMoving()
    end)
    head:SetScript("OnDragStop", function()
        detailFrame:StopMovingOrSizing()
    end)

    detailFrame.title = MakeText(head, THEME.fontSize, "LEFT")
    detailFrame.title:SetPoint("LEFT", head, "LEFT", 6, 0)
    detailFrame.title:SetPoint("RIGHT", head, "RIGHT", -20, 0)

    local close = MakeGlyphButton(head, "close")
    close:SetSize(16, 16)
    close:SetPoint("RIGHT", head, "RIGHT", -2, 0)
    close:SetScript("OnClick", function()
        view.detailGuid = nil
        view.pieList, view.pieKey = 1, nil
        detailFrame:Hide()
    end)

    -- Deaths mode grows a share glyph on the title bar: report THIS death
    -- from where you are reading it (same channel menu as the header's)
    detailFrame.share = MakeGlyphButton(head, "share")
    detailFrame.share:SetSize(16, 16)
    detailFrame.share:SetPoint("RIGHT", close, "LEFT", -2, 0)
    detailFrame.share:SetScript("OnClick", function(self) OpenMenu(ShareMenu, self) end)
    Commander.UI.AttachTooltip(detailFrame.share, "Share",
        "Report this death's log to a chat channel. Nothing is ever sent automatically.")
    detailFrame.share:Hide()

    detailFrame.sub = MakeText(detailFrame, THEME.fontSizeSmall, "LEFT")
    detailFrame.sub:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 6, -2)
    detailFrame.sub:SetPoint("RIGHT", detailFrame, "RIGHT", -6, 0)
    detailFrame.sub:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])

    detailFrame.list1Title = MakeText(detailFrame, THEME.fontSizeSmall, "LEFT")
    detailFrame.list1Title:SetPoint("TOPLEFT", detailFrame.sub, "BOTTOMLEFT", 0, -6)
    detailFrame.list1Title:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])

    -- Column header labels, right-aligned over the value/%/extra columns
    -- (their texts are set per view in RepaintDetail)
    local function MakeColLabel(anchorTo, anchorPoint, x, y)
        local fs = MakeText(detailFrame, THEME.fontSizeSmall, "RIGHT")
        fs:SetPoint("TOPRIGHT", anchorTo, anchorPoint, x, y)
        fs:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
        return fs
    end
    -- list rows anchor their columns at RIGHT -78/-44/-4 inside lists that
    -- end 4px from the frame edge
    detailFrame.col1V = MakeColLabel(detailFrame.sub, "BOTTOMRIGHT", -76, -6)
    detailFrame.col1P = MakeColLabel(detailFrame.sub, "BOTTOMRIGHT", -42, -6)
    detailFrame.col1E = MakeColLabel(detailFrame.sub, "BOTTOMRIGHT", -2, -6)

    local list1 = CreateFrame("Frame", nil, detailFrame)
    list1:SetPoint("TOPLEFT", detailFrame.list1Title, "BOTTOMLEFT", -2, -2)
    list1:SetPoint("RIGHT", detailFrame, "RIGHT", -4, 0)
    list1:SetHeight(THEME.detailRows * (THEME.rowH - 1))
    list1:EnableMouseWheel(true)
    list1:SetScript("OnMouseWheel", function(_, delta)
        view.abilityOffset = math.max(0, view.abilityOffset - delta)
        RepaintDetail()
    end)
    for i = 1, THEME.detailRows do
        local row = BuildDetailRow(list1)
        row:SetPoint("TOPLEFT", list1, "TOPLEFT", 0, -((i - 1) * (THEME.rowH - 1)))
        row:SetPoint("RIGHT", list1, "RIGHT", 0, 0)
        row:SetScript("OnEnter", DetailRowHover)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", DetailRowClick)
        detailAbilityRows[i] = row
    end

    detailFrame.list2Title = MakeText(detailFrame, THEME.fontSizeSmall, "LEFT")
    detailFrame.list2Title:SetPoint("TOPLEFT", list1, "BOTTOMLEFT", 2, -4)
    detailFrame.list2Title:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])
    detailFrame.col2V = MakeColLabel(list1, "BOTTOMRIGHT", -78, -4)
    detailFrame.col2P = MakeColLabel(list1, "BOTTOMRIGHT", -44, -4)
    detailFrame.col2E = MakeColLabel(list1, "BOTTOMRIGHT", -4, -4)

    local list2 = CreateFrame("Frame", nil, detailFrame)
    list2:SetPoint("TOPLEFT", detailFrame.list2Title, "BOTTOMLEFT", -2, -2)
    list2:SetPoint("RIGHT", detailFrame, "RIGHT", -4, 0)
    -- Sized for the death trail (the taller consumer): all 10 ring events
    -- must be viewable, matching the "last ten hits" promise
    list2:SetHeight(THEME.deathTrailRows * (THEME.rowH - 1))
    list2:EnableMouseWheel(true)
    list2:SetScript("OnMouseWheel", function(_, delta)
        view.targetOffset = math.max(0, view.targetOffset - delta)
        RepaintDetail()
    end)
    for i = 1, THEME.deathTrailRows do
        local row = BuildDetailRow(list2, true)
        row:SetPoint("TOPLEFT", list2, "TOPLEFT", 0, -((i - 1) * (THEME.rowH - 1)))
        row:SetPoint("RIGHT", list2, "RIGHT", 0, 0)
        row:SetScript("OnEnter", DetailRowHover)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", DetailRowClick)
        detailTargetRows[i] = row
    end

    detailFrame.hint = MakeText(detailFrame, THEME.fontSizeSmall, "CENTER")
    detailFrame.hint:SetPoint("BOTTOM", detailFrame, "BOTTOM", 0, 3)
    detailFrame.hint:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
    detailFrame.hint:SetText("WHEEL SCROLLS · HOVER AN ENTRY TO INSPECT IT · DRAG THE TITLE TO MOVE")

    BuildPie()
    BuildCurve()
end

-- ---------------------------------------------------------------------------
-- Header + repaint
-- ---------------------------------------------------------------------------

local function RepaintHeader()
    -- The mode label wears its stat's color — which meter you are reading
    -- is visible from the corner of an eye (selection state stays amber)
    local mc = ModeColor(panes[1].mode)
    modeBtn.text:SetText(panes[1].mode.label)
    modeBtn.text:SetTextColor(mc[1], mc[2], mc[3])
    -- While the left pane reads an arena match, the segment label would
    -- describe a fight nobody is looking at — name the match instead (the
    -- button's menu still moves the segment for the right pane and detail)
    if panes[1].mode.arena then
        segBtn.text:SetText(ArenaMatchLabel(ArenaMatch()))
    else
        local live = view.segSel == "current" and E.InFight()
        segBtn.text:SetText((live and LIVE_DOT or "") .. SegmentLabel())
    end
    SetGlyphColor(graphBtn, view.graphOpen and THEME.accent or THEME.textDim)
    SetGlyphColor(splitBtn, db.SplitOpen and THEME.accent or THEME.textDim)
    SetGlyphColor(arenaBtn, (CommanderMetersArena_IsShown and CommanderMetersArena_IsShown()) and THEME.accent or THEME.textDim)
end

repaintNow = function()
    if not root or not root:IsShown() then return end
    RepaintHeader()
    RepaintPane(1)
    if db.SplitOpen then RepaintPane(2) end
    if view.graphOpen then RepaintGraph() end
    RepaintDetail()
end

-- The visually obvious transition for auto-switching: the segment button
-- flashes amber and fades. The fade runs on the BUTTON's OnUpdate —
-- textures cannot carry OnUpdate scripts on this client.
local function FlashSegment()
    segFlash:SetAlpha(1)
    segFlash:Show()
    local t = 0
    segBtn:SetScript("OnUpdate", function(_, elapsed)
        t = t + elapsed
        local a = 1 - t / 0.8
        if a <= 0 then
            segFlash:Hide()
            segBtn:SetScript("OnUpdate", nil)
        else
            segFlash:SetAlpha(a)
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Menus (all one level deep)
-- ---------------------------------------------------------------------------

-- paneIndex 2 addresses the compare pane's own segment; anything else is
-- the window's shared selection. Only "current"/"overall" persist —
-- "last" and fight ids are session-scoped on both selectors alike.
local function SelectSegment(sel, paneIndex)
    if paneIndex == 2 then
        view.segSel2 = sel -- nil: the pane follows the window again
        if sel == nil then
            db.SplitSegment = "follow"
        elseif sel == "overall" or sel == "current" then
            db.SplitSegment = sel
        end
        panes[2].offset = 0
    else
        view.segSel = sel
        if sel == "overall" or sel == "current" then
            db.ViewSegment = sel
        end
        panes[1].offset, panes[2].offset = 0, 0
    end
    view.detailDeath = nil
    repaintNow()
end

local function SegmentMenu(paneIndex)
    -- An unpinned right pane has no segment of its OWN, so nothing in its
    -- list is checked — the FOLLOW entry above it carries the checkmark
    local current = (paneIndex == 2 and not PinnedPane2())
        and false or PaneSelector(paneIndex or 1)
    local function AddSeg(text, sel)
        local info = UIDropDownMenu_CreateInfo()
        info.text = text
        info.checked = current == sel
        info.func = function() SelectSegment(sel, paneIndex) end
        UIDropDownMenu_AddButton(info)
    end
    AddSeg("OVERALL", "overall")
    AddSeg("CURRENT", "current")
    AddSeg("LAST", "last")
    local fightList = E.GetFights()
    for i = 1, #fightList do
        local seg = fightList[i]
        AddSeg(format("F#%d — %s (%s)%s", seg.id, seg.name or "?", FmtTime(seg.dur),
            SuccessTag(seg)), seg.id)
    end
end

local function AddMenuTitle(text)
    local info = UIDropDownMenu_CreateInfo()
    info.text, info.isTitle, info.notCheckable = text, true, true
    UIDropDownMenu_AddButton(info)
end

local function ModeMenu(paneIndex)
    local function AddModeEntry(mode)
        local info = UIDropDownMenu_CreateInfo()
        info.text = mode.label
        info.checked = panes[paneIndex].mode == mode
        local m = mode
        info.func = function()
            panes[paneIndex].mode = m
            if paneIndex == 1 then
                db.ViewMode = m.key
            else
                db.SplitMode = m.key
            end
            panes[paneIndex].offset = 0
            view.abilityOffset, view.targetOffset = 0, 0
            view.pieList, view.pieKey = 1, nil
            repaintNow()
        end
        UIDropDownMenu_AddButton(info)
    end
    for _, mode in ipairs(E.MODES) do
        AddModeEntry(mode)
    end
    -- Arena modes: both teams, from the match engine — and the way into
    -- the report itself, so the window is discoverable from the menu a
    -- user already opens
    AddMenuTitle("ARENA — BOTH TEAMS")
    for _, mode in ipairs(ARENA_MODES) do
        AddModeEntry(mode)
    end
    local open = UIDropDownMenu_CreateInfo()
    open.text = "OPEN ARENA REPORT…"
    open.notCheckable = true
    open.func = function() if CommanderMetersArena_Toggle then CommanderMetersArena_Toggle() end end
    UIDropDownMenu_AddButton(open)
    -- External modes (sorted for a stable menu) join the bottom of the list
    local keys = {}
    for key in pairs(externalModes) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        AddModeEntry(externalModes[key])
    end
end

-- The caption IS the pane, so its menu is the whole pane: what it
-- measures and which stretch of combat it measures over — two titled
-- sections, still one level deep. The left pane's segment section is the
-- window's own (that caption and the header's segment button are the
-- same control); the right pane's PINS a segment of its own, with
-- FOLLOW LEFT PANE as the default and the way back.
local function PaneMenu(paneIndex)
    AddMenuTitle(paneIndex == 2 and "RIGHT PANE SHOWS" or "LEFT PANE SHOWS")
    ModeMenu(paneIndex)

    -- An external pane owns its data outright and knows nothing about
    -- segments (D22) — offering it one would be a lie
    local pm = panes[paneIndex].mode
    if pm and (pm.external or pm.arena) then return end

    AddMenuTitle("OVER")
    if paneIndex == 2 then
        local info = UIDropDownMenu_CreateInfo()
        info.text = "FOLLOW LEFT PANE"
        info.checked = not PinnedPane2()
        info.func = function() SelectSegment(nil, 2) end
        UIDropDownMenu_AddButton(info)
    end
    SegmentMenu(paneIndex)
end

local function ResetMenu()
    local info = UIDropDownMenu_CreateInfo()
    info.text = "RESET FIGHT (current pull only)"
    info.notCheckable = true
    info.func = function() CommanderMeters_WipeFight() end
    UIDropDownMenu_AddButton(info)
    info = UIDropDownMenu_CreateInfo()
    info.text = "RESET EVERYTHING (overall + all fights)"
    info.notCheckable = true
    info.func = function() CommanderMeters_WipeAll() end
    UIDropDownMenu_AddButton(info)
end

-- ---------------------------------------------------------------------------
-- Report to chat
-- ---------------------------------------------------------------------------

local REPORT_LINES = 5
local reportScratch = {}

local function BuildReportLines()
    local mode = panes[1].mode
    -- An external pane reports its provider's rows as-is (still manual-only)
    if mode.external then
        local ok, rowsData, n = pcall(mode.external.collect, time())
        if not ok or type(rowsData) ~= "table" or (n or 0) == 0 then return 0 end
        local okCap, cap = pcall(mode.external.caption or function() return nil end)
        reportScratch[1] = format("Commander Meters — %s, %s",
            mode.label, (okCap and cap) or "LIVE")
        local count = math.min(n, REPORT_LINES)
        for i = 1, count do
            local data = rowsData[i]
            reportScratch[i + 1] = format("%d. %s  %s", i,
                ShortName(data.name or "?"), data.valueText or "")
        end
        return count + 1
    end
    if mode.arena then
        local m = ArenaMatch()
        if not m then return 0 end
        local stat = A.StatByKey(mode.stat)
        local t = A.Live() == m and (time() - m.tsStart) or nil
        local rowsData, n, totals, dur = A.CollectRows(m, stat, t)
        if n == 0 then return 0 end
        reportScratch[1] = format("Commander Meters — %s, %s (%s)", mode.label,
            ArenaMatchLabel(m, true), FmtTime(dur))
        local count = math.min(n, REPORT_LINES)
        for i = 1, count do
            local data = rowsData[i]
            reportScratch[i + 1] = format("%d. %s (%s)  %s", i, ShortName(data.seat.name or "?"),
                data.seat.team == "us" and "us" or "enemy",
                stat.seconds and FmtTime(data.value) or FmtNum(data.value))
        end
        return count + 1
    end
    local seg = ViewSegment()
    if not seg then return 0 end
    local now = time()
    local rowsData, n, total, dur = E.CollectRows(seg, mode, now)
    reportScratch[1] = format("Commander Meters — %s, %s (%s)",
        mode.label, SegmentLabel(true), FmtTime(dur))
    local count = math.min(n, REPORT_LINES)
    -- A header with no ranking under it is noise, not a report
    if count == 0 then return 0 end
    for i = 1, count do
        local data = rowsData[i]
        local line = format("%d. %s  %s", i, ShortName(data.actor.name), FmtNum(data.value))
        if mode.rateLabel then
            line = line .. format(" (%s %s, %.0f%%)", FmtNum(data.rate), mode.rateLabel,
                total > 0 and data.value / total * 100 or 0)
        end
        reportScratch[i + 1] = line
    end
    return count + 1
end

-- The selected death's report: a header (who, when, which segment) and
-- the trail's last events oldest-first, ending at the killing blow — the
-- same story the death log tells, told forward. Chat gets plain text
-- only: no icon escapes, no colors, and the header + REPORT_LINES cap
-- keeps a death exactly as heavy as a top-5 ranking.
local function BuildDeathReportLines(d)
    reportScratch[1] = format("Commander Meters — DEATH: %s %s, %s",
        ShortName(d.name), date("%H:%M:%S", d.ts), SegmentLabel(true, DetailSelector()))
    local nLog = #d.log
    local count = math.min(nLog, REPORT_LINES)
    for i = 1, count do
        local entry = d.log[nLog - count + i]
        local hasHp = entry.hp and entry.hpMax and entry.hpMax > 0
        reportScratch[i + 1] = format("-%.1fs  %s  %s%s%s",
            d.ts - entry.ts, entry.what or "?",
            entry.kind == 2 and "+" or "-", FmtNum(entry.amount or 0),
            hasHp and format("  (%d%% HP)", entry.hp / entry.hpMax * 100) or "")
    end
    return count + 1
end

local function SendReport(channel)
    local lines
    -- An open death log IS the current view: share reports the selected
    -- death's trail instead of the pane ranking (the header alone still
    -- carries who/when even for a death with an empty trail)
    if detailFrame and detailFrame:IsShown() and DetailMode().deaths
        and view.detailDeath then
        lines = BuildDeathReportLines(view.detailDeath)
    else
        lines = BuildReportLines()
    end
    if lines == 0 then
        print("|cff66ccffCommander Meters|r: nothing to report in this segment")
        return
    end
    for i = 1, lines do
        SendChatMessage(reportScratch[i], channel)
    end
end

function ShareMenu()
    local function entry(label, channel, shown)
        if not shown then return end
        local info = UIDropDownMenu_CreateInfo()
        info.text = label
        info.notCheckable = true
        info.func = function() SendReport(channel) end
        UIDropDownMenu_AddButton(info)
    end
    local inInstanceGroup = IsInGroup and LE_PARTY_CATEGORY_INSTANCE
        and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
    -- Home-category channels fail inside instance groups on this client
    -- (the verified battleground SendChatMessage lesson) — PARTY and RAID
    -- both need the home-group gate, with INSTANCE offered there instead
    local inHomeParty = IsInGroup
        and ((LE_PARTY_CATEGORY_HOME and IsInGroup(LE_PARTY_CATEGORY_HOME))
            or (not LE_PARTY_CATEGORY_HOME and IsInGroup() and not inInstanceGroup))
    entry("SAY", "SAY", true)
    entry("PARTY", "PARTY", inHomeParty)
    entry("RAID", "RAID", IsInRaid() and not inInstanceGroup)
    entry("INSTANCE", "INSTANCE_CHAT", inInstanceGroup)
    entry("GUILD", "GUILD", IsInGuild and IsInGuild())
end

-- ---------------------------------------------------------------------------
-- Window construction + layout
-- ---------------------------------------------------------------------------

local function Layout()
    local rowsH = db.MaxRows * (THEME.rowH + THEME.rowGap)
    local capH = db.SplitOpen and THEME.capH or 0
    local h = THEME.headerH + 2 + capH + rowsH + 2
    if view.graphOpen then h = h + THEME.graphH end
    -- The footprint holds: splitting never widens the window. The panes
    -- take half each, and their number columns condense to match.
    root:SetSize(db.FrameWidth, h)

    -- While split, the pane captions are the mode statements and menus,
    -- so the header's mode button — pane 1's duplicate — yields its width
    -- to the squeezed segment button
    modeBtn:SetShown(not db.SplitOpen)
    segBtn:ClearAllPoints()
    if db.SplitOpen then
        segBtn:SetPoint("LEFT", headerFrame, "LEFT", 0, 0)
    else
        segBtn:SetPoint("LEFT", modeBtn, "RIGHT", 0, 0)
    end
    segBtn:SetPoint("RIGHT", headerFrame, "RIGHT", -105, 0)

    for i = 1, 2 do
        local pane = panes[i]
        pane.caption:SetHeight(db.SplitOpen and THEME.capH or 0.001)
        pane.caption.text:SetShown(db.SplitOpen and true or false)
    end
    panes[2].caption:SetShown(db.SplitOpen and true or false)
    panes[2].frame:SetShown(db.SplitOpen and true or false)
    paneDivider:SetShown(db.SplitOpen and true or false)

    -- The divider fills exactly the 1px seam the caption math reserves
    -- ([center, center+1] — hence the half-pixel offset) and stops at the
    -- bars: it separates the PANES, never the full-width graph below them
    paneDivider:ClearAllPoints()
    paneDivider:SetPoint("TOP", headerFrame, "BOTTOM", 0.5, 0)
    paneDivider:SetPoint("BOTTOM", headerFrame, "BOTTOM", 0.5, -(2 + capH + rowsH))

    -- Pane widths: full window single, half each when split
    panes[1].frame:ClearAllPoints()
    panes[1].frame:SetPoint("TOPLEFT", panes[1].caption, "BOTTOMLEFT", 0, 0)
    if db.SplitOpen then
        panes[1].frame:SetPoint("RIGHT", root, "CENTER", 0, 0)
    else
        panes[1].frame:SetPoint("RIGHT", root, "RIGHT", 0, 0)
    end
    panes[1].frame:SetHeight(rowsH)
    panes[2].frame:SetHeight(rowsH)

    graphFrame:ClearAllPoints()
    graphFrame:SetPoint("TOPLEFT", panes[1].frame, "BOTTOMLEFT", 0, -2)
    graphFrame:SetPoint("RIGHT", root, "RIGHT", 0, 0)
    graphFrame:SetShown(view.graphOpen)
end


local function BuildWindow()
    root = CreateFrame("Frame", "CommanderMetersFrame", UIParent)
    root:SetFrameStrata("MEDIUM")
    root:SetClampedToScreen(true)
    root.fill = root:CreateTexture(nil, "BACKGROUND")
    root.fill:SetTexture(WHITE)
    root.fill:SetVertexColor(THEME.bg[1], THEME.bg[2], THEME.bg[3], THEME.bg[4])
    root.fill:SetAllPoints()
    MakeEdge(root)

    headerFrame = CreateFrame("Frame", nil, root)
    headerFrame:SetHeight(THEME.headerH)
    headerFrame:SetPoint("TOPLEFT")
    headerFrame:SetPoint("TOPRIGHT")
    headerFrame.fill = headerFrame:CreateTexture(nil, "BACKGROUND")
    headerFrame.fill:SetTexture(WHITE)
    headerFrame.fill:SetVertexColor(THEME.chrome[1], THEME.chrome[2], THEME.chrome[3], THEME.chrome[4])
    headerFrame.fill:SetAllPoints()
    local rule = headerFrame:CreateTexture(nil, "BORDER")
    rule:SetTexture(WHITE)
    rule:SetVertexColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.5)
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")

    menuFrame = CreateFrame("Frame", "CommanderMetersMenu", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(menuFrame, function()
        if menuBuilder then menuBuilder() end
    end, "MENU")

    modeBtn = MakeHeaderButton(headerFrame, "LEFT")
    modeBtn.headerRole = "mode" -- how the headless harness finds it
    modeBtn:SetPoint("LEFT", headerFrame, "LEFT", 0, 0)
    modeBtn:SetWidth(74)
    modeBtn:SetScript("OnClick", function(self)
        OpenMenu(function() ModeMenu(1) end, self)
    end)
    Commander.UI.AttachTooltip(modeBtn, "Mode", "What the bars measure. Click for the list. (While split, each pane's caption is its own menu — mode AND segment — and this button steps aside.)")

    segBtn = MakeHeaderButton(headerFrame, "LEFT")
    segBtn.headerRole = "segment" -- how the headless harness finds it
    segBtn:SetPoint("LEFT", modeBtn, "RIGHT", 0, 0)
    segBtn:SetPoint("RIGHT", headerFrame, "RIGHT", -105, 0)
    segBtn:SetScript("OnClick", function(self)
        OpenMenu(function() SegmentMenu(1) end, self)
    end)
    Commander.UI.AttachTooltip(segBtn, "Segment", function()
        local seg = ViewSegment()
        local extra = ""
        if seg then
            extra = "\nDuration " .. FmtTime(E.SegmentDuration(seg, time()))
        end
        local scope = PinnedPane2()
            and "Which stretch of combat the window shows — the right pane is PINNED to its own right now, so this moves everything but it."
            or "Which stretch of combat the whole window (both panes, detail, graph) shows."
        return scope .. " Click for Overall, Current, Last, and every kept fight." .. extra
    end)
    segFlash = segBtn:CreateTexture(nil, "OVERLAY")
    segFlash:SetTexture(WHITE)
    segFlash:SetVertexColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.45)
    segFlash:SetAllPoints()
    segFlash:Hide()

    -- Arena Report: the one way the report opens besides /cm arena and
    -- the ARENA rows — it never opens itself
    arenaBtn = MakeGlyphButton(headerFrame, "arena")
    arenaBtn.headerRole = "arena"
    arenaBtn:SetPoint("RIGHT", headerFrame, "RIGHT", -84, 0)
    arenaBtn:SetScript("OnClick", function()
        if CommanderMetersArena_Toggle then CommanderMetersArena_Toggle() end
        repaintNow()
    end)
    Commander.UI.AttachTooltip(arenaBtn, "Arena Report", "Open or close the Arena Report: both teams of every recorded match, ten stats, a replayable timeline, insights and history. It never opens on its own.")

    shareBtn = MakeGlyphButton(headerFrame, "share")
    shareBtn.headerRole = "share" -- how the headless harness finds it
    shareBtn:SetPoint("RIGHT", headerFrame, "RIGHT", -63, 0)
    shareBtn:SetScript("OnClick", function(self) OpenMenu(ShareMenu, self) end)
    Commander.UI.AttachTooltip(shareBtn, "Share", "Report the current view's top 5 — or the open death log — to a chat channel. Nothing is ever sent automatically.")

    splitBtn = MakeGlyphButton(headerFrame, "split")
    splitBtn:SetScript("OnClick", function()
        db.SplitOpen = not db.SplitOpen
        -- The rows reflow their column set for the new pane width before
        -- the geometry moves
        BuildPaneRows(1)
        BuildPaneRows(2)
        Layout()
        repaintNow()
    end)
    splitBtn:SetPoint("RIGHT", headerFrame, "RIGHT", -42, 0)
    Commander.UI.AttachTooltip(splitBtn, "Split View",
        "Split the window into two half-width panes; the footprint never changes."
        .. "\n\nEach pane's CAPTION is its own menu — what it measures and which"
        .. " segment it measures over. So the split can be damage beside healing"
        .. " on one fight, or the same metric twice (DAMAGE · CURRENT beside"
        .. " DAMAGE · OVERALL), or both."
        .. "\n\nThe right pane follows the header's segment until you pin it to"
        .. " one of its own; pinned, its caption wears the accent.")

    graphBtn = MakeGlyphButton(headerFrame, "graph")
    graphBtn:SetPoint("RIGHT", headerFrame, "RIGHT", -21, 0)
    graphBtn:SetScript("OnClick", function()
        view.graphOpen = not view.graphOpen
        Layout()
        repaintNow()
    end)
    Commander.UI.AttachTooltip(graphBtn, "Graph", "Toggle the per-fight throughput graph (left pane's mode). Graphs exist for fight segments only (kept for the newest five fights).")

    resetBtn = MakeGlyphButton(headerFrame, "reset")
    resetBtn:SetPoint("RIGHT", headerFrame, "RIGHT", 0, 0)
    resetBtn:SetScript("OnClick", function(self) OpenMenu(ResetMenu, self) end)
    Commander.UI.AttachTooltip(resetBtn, "Reset", "RESET FIGHT restarts the current pull's numbers; RESET EVERYTHING wipes Overall, every kept fight, graphs, and death logs. Both are instant.")

    -- Panes: captions (mode label strips, split view only) + row frames
    for i = 1, 2 do
        local pane = panes[i]
        local caption = CreateFrame("Button", nil, root)
        pane.caption = caption
        caption.paneIndex = i -- mirrors row.paneIndex, for the harness
        caption:SetHeight(0.001)
        caption.text = MakeText(caption, THEME.fontSizeSmall, "LEFT")
        caption.text:SetPoint("LEFT", caption, "LEFT", 4, 0)
        caption.text:SetPoint("RIGHT", caption, "RIGHT", -4, 0)
        caption.text:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])
        caption.text:Hide()
        caption.hover = caption:CreateTexture(nil, "HIGHLIGHT")
        caption.hover:SetTexture(WHITE)
        caption.hover:SetVertexColor(1, 1, 1, THEME.hover[4])
        caption.hover:SetAllPoints()
        local index = i
        caption:SetScript("OnClick", function(self)
            OpenMenu(function() PaneMenu(index) end, self)
        end)
        Commander.UI.AttachTooltip(caption, "Pane", function()
            if index == 2 then
                return "This pane, both halves: what it measures and which segment it measures over. Click for the list.\n\nOVER › FOLLOW LEFT PANE keeps it on the header's segment (the default); pick a segment instead to pin it — Current here beside Overall there reads a ramp at a glance. A pinned caption wears the accent."
            end
            return "This pane, both halves: what it measures and which segment it measures over. Click for the list. Its segment is the window's, so the header's segment button is the same control."
        end)

        local frame = CreateFrame("Frame", nil, root)
        pane.frame = frame
        frame:EnableMouseWheel(true)
        frame:SetScript("OnMouseWheel", function(_, delta)
            pane.offset = math.max(0, pane.offset - delta)
            repaintNow()
        end)
    end
    panes[1].caption:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, -2)
    panes[1].caption:SetPoint("RIGHT", root, "CENTER", 0, 0)
    panes[2].caption:SetPoint("TOPLEFT", panes[1].caption, "TOPRIGHT", 1, 0)
    panes[2].caption:SetPoint("RIGHT", root, "RIGHT", 0, 0)
    panes[2].frame:SetPoint("TOPLEFT", panes[2].caption, "BOTTOMLEFT", 0, 0)
    panes[2].frame:SetPoint("RIGHT", root, "RIGHT", 0, 0)

    paneDivider = root:CreateTexture(nil, "BORDER")
    paneDivider:SetTexture(WHITE)
    paneDivider:SetVertexColor(THEME.edge[1], THEME.edge[2], THEME.edge[3], THEME.edge[4])
    paneDivider:SetWidth(1)
    -- Anchored by Layout (its reach depends on the caption/row heights)
    paneDivider:Hide()

    BuildGraph()
    BuildDetail()

    root:HookScript("OnHide", function()
        detailFrame:Hide()
    end)

    -- 2 Hz repaint, whatever the event rate is doing
    local acc = 0
    root:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= 0.5 then
            acc = 0
            repaintNow()
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Apply (settings listener) + visibility
-- ---------------------------------------------------------------------------

local function Apply()
    if not root then return end
    -- The panes re-adopt the DB's modes: equal already on every normal
    -- path (the menus write the DB as they switch), they diverge only
    -- when Restore Defaults rewrites the DB under a live session — and
    -- then the DB is the truth
    panes[1].mode = ModeByKey(db.ViewMode)
    panes[2].mode = ModeByKey(db.SplitMode)
    BuildPaneRows(1)
    BuildPaneRows(2)
    Layout()
    root.fill:SetVertexColor(THEME.bg[1], THEME.bg[2], THEME.bg[3], db.BgOpacity or THEME.bg[4])
    -- Click-through: bars, panes, and the graph release the mouse entirely
    -- so clicks land in the world; the header strip stays interactive (and
    -- new rows from a Bar Rows change are covered — this runs after
    -- BuildPaneRows every time)
    local mouse = not db.ClickThrough
    for p = 1, 2 do
        local pane = panes[p]
        for i = 1, #pane.rows do
            pane.rows[i]:EnableMouse(mouse)
        end
        pane.frame:EnableMouseWheel(mouse)
        -- Captions are chrome, not content: while split they are the only
        -- mode menus, so like the header strip they never go click-through
        pane.caption:EnableMouse(true)
    end
    graphFrame.plot:EnableMouse(mouse)
    for i = 1, GRAPH_LINES do
        graph.lines[i].legend:EnableMouse(mouse)
    end
    Commander.UI.ApplyHudChrome(root, db, "Hud", {
        defaultPoint = { point = "RIGHT", x = -46, y = -60 },
        title = "Commander Meters",
    })
    root:SetShown((db.EnableMeters and db.WindowShown)
        or Commander.UI.HudUnlocked(db, "Hud"))
    -- The detail popup is anchored to the window but parented to UIParent:
    -- it must never outlive a hidden window (the OnHide hook covers the
    -- chrome's own close paths too)
    if not root:IsShown() then
        detailFrame:Hide()
    end
    repaintNow()
end

-- ---------------------------------------------------------------------------
-- Engine hookup: fight transitions, roster, CC names
-- ---------------------------------------------------------------------------

local function OnFightStart()
    -- An engine-side wipe (AutoResetOnNewFight) can invalidate a pinned
    -- fight number the instant a new pull opens
    if type(view.segSel) == "number" and not E.GetSegment(view.segSel) then
        view.segSel = "current"
    end
    if type(view.segSel2) == "number" and not E.GetSegment(view.segSel2) then
        view.segSel2 = "overall"
    end
    if db.AutoSwitchCurrent and view.segSel ~= "current" then
        view.segSel = "current"
        FlashSegment()
    end
end

local function OnFightEnd(seg)
    if db.AutoSwitchCurrent and view.segSel == "current" then
        view.segSel = "last"
        FlashSegment()
    elseif type(view.segSel) == "number" and not E.GetSegment(view.segSel) then
        -- The fight the user was looking at just got pruned
        view.segSel = "last"
    end
    -- A PINNED right pane never auto-follows combat: it is the fixed
    -- reference the left pane is being read against, and Follow Combat
    -- yanking it to Last would collapse the comparison at every kill.
    -- Only a pruned fight id moves it, and then to Overall, which can
    -- never be pruned.
    if type(view.segSel2) == "number" and not E.GetSegment(view.segSel2) then
        view.segSel2 = "overall"
    end
end

local PET_TOKEN = { player = "pet" }
for i = 1, 4 do PET_TOKEN["party" .. i] = "partypet" .. i end
for i = 1, 40 do PET_TOKEN["raid" .. i] = "raidpet" .. i end

local function MapPetOf(ownerToken)
    local petToken = PET_TOKEN[ownerToken]
    if not petToken or not UnitExists(petToken) then return end
    local petGuid, ownerGuid = UnitGUID(petToken), UnitGUID(ownerToken)
    if petGuid and ownerGuid then
        E.SetOwner(petGuid, ownerGuid, UnitName(petToken), time())
    end
end

local function RosterUnit(token)
    if not UnitExists(token) then return end
    local guid = UnitGUID(token)
    if not guid then return end
    local _, class = UnitClass(token)
    E.SetRosterEntry(guid, token, UnitName(token), class)
    MapPetOf(token)
end

local function RefreshRoster()
    E.ClearRoster()
    RosterUnit("player")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            RosterUnit("raid" .. i)
        end
    else
        for i = 1, 4 do
            RosterUnit("party" .. i)
        end
    end
end

-- CC auras whose breaks count in the CC BREAKS mode, resolved locale-safe
-- from base spell IDs at login (all ranks share the base name)
local CC_IDS = {
    118,   -- Polymorph
    6770,  -- Sap
    1776,  -- Gouge
    5782,  -- Fear
    8122,  -- Psychic Scream
    5484,  -- Howl of Terror
    6358,  -- Seduction
    2637,  -- Hibernate
    3355,  -- Freezing Trap Effect
    9484,  -- Shackle Undead
    19386, -- Wyvern Sting
    2094,  -- Blind
    339,   -- Entangling Roots
    1513,  -- Scare Beast
    10326, -- Turn Evil
    710,   -- Banish
    20066, -- Repentance
    122,   -- Frost Nova
}

-- Native-first spell name lookup: C_Spell.GetSpellInfo (table OR tuple
-- shape, both handled) before the deprecation-track global.
local function SpellName(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and info then
            if type(info) == "table" then return info.name end
            if type(info) == "string" then return info end
        end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, id)
        if ok and type(name) == "string" then return name end
    end
end

local function LoadCCNames()
    local names = {}
    local resolved = 0
    for _, id in ipairs(CC_IDS) do
        local name = SpellName(id)
        if name then
            names[name] = true
            resolved = resolved + 1
        end
    end
    if resolved < #CC_IDS then
        print(format("|cff66ccffCommander Meters|r: only %d/%d CC names resolved — CC BREAKS may undercount",
            resolved, #CC_IDS))
    end
    E.SetCCNames(names)
    A.SetCCNames(names)
end

-- ---------------------------------------------------------------------------
-- Slash-reachable commands
-- ---------------------------------------------------------------------------

function CommanderMeters_Toggle()
    db.WindowShown = not db.WindowShown
    Apply()
end

-- Quick lock control without the settings trip: /cmeters lock | unlock
-- (drives the same suite HudChrome state as the panel's Unlock checkbox)
function CommanderMeters_SetLock(locked)
    db.HudLocked = locked
    Apply()
    print("|cff66ccffCommander Meters|r: window " ..
        (locked and "locked" or "unlocked — drag it anywhere, right-click it to lock"))
end

function CommanderMeters_WipeFight()
    E.ResetCurrent(time())
    view.detailDeath = nil
    print("|cff66ccffCommander Meters|r: current fight reset" ..
        (E.InFight() and " — this pull records fresh from now" or ""))
    repaintNow()
end

-- Shared by the button/slash wipe and every auto-reset trigger, so no
-- reset path can leave stale view state behind
local function WipeAllData(reason)
    E.ResetAll(time())
    view.segSel = E.InFight() and "current" or db.ViewSegment
    if type(view.segSel) == "number" or view.segSel == "last" then
        view.segSel = "current"
    end
    if type(view.segSel2) == "number" or view.segSel2 == "last" then
        view.segSel2 = "overall"
    end
    view.detailDeath = nil
    panes[1].offset, panes[2].offset = 0, 0
    print("|cff66ccffCommander Meters|r: everything reset" ..
        (reason and (" (" .. reason .. ")") or "") ..
        " — overall, fights, graphs, death logs")
    repaintNow()
end

function CommanderMeters_WipeAll()
    WipeAllData(nil)
end

local capturing = false

function CommanderMeters_Dump()
    if capturing then
        capturing = false
        E.SetCapture(nil)
        print(format("|cff66ccffCommander Meters|r: capture stopped — %d raw events saved to CommanderMetersLog (flushed on logout/reload)",
            CommanderMetersLog.events and #CommanderMetersLog.events or 0))
    else
        capturing = true
        CommanderMetersLog.events = {}
        CommanderMetersLog.capturedAt = date("%Y-%m-%d %H:%M:%S")
        CommanderMetersLog.build = { GetBuildInfo() }
        E.SetCapture(CommanderMetersLog.events)
        print("|cff66ccffCommander Meters|r: capturing raw combat events (cap 2000) — /cmeters dump again to stop")
    end
end

function CommanderMeters_Health()
    print("|cff66ccffCommander Meters|r health:")
    local fightList = E.GetFights()
    print(format("  fights kept: %d · in fight: %s · capture: %s (%d events)",
        #fightList, tostring(E.InFight()), tostring(capturing), E.CaptureCount()))
    local any = false
    for key, count in pairs(E.GetAnomalies()) do
        any = true
        print(format("  |cffff8833anomaly|r ×%d: %s", count, key))
    end
    if not any then
        print("  no parse anomalies this session")
    end
    -- Arena engine: matches, live state, rule data, its own anomalies
    print(format("  arena: %d match%s kept · live: %s · rule data: %s",
        #A.GetMatches(), #A.GetMatches() == 1 and "" or "es", tostring(A.InMatch()),
        (CommanderMetersArena_DataNote and CommanderMetersArena_DataNote()) or "complete (DR table + cooldown book)"))
    for key, count in pairs(A.GetAnomalies()) do
        print(format("  |cffff8833arena anomaly|r ×%d: %s", count, key))
    end
end

-- Injects a small canned fight through the REAL parser (sentinel GUIDs, a
-- pet, crits, misses, an absorb, overheal, an interrupt, a dispel, casts
-- for APM, one death) so every view has something to show. RESET
-- EVERYTHING clears it.
function CommanderMeters_Test()
    if not (db and db.EnableMeters) then
        print("|cff66ccffCommander Meters|r: meters are disabled — enable them in the settings first")
        return
    end
    local now = time()
    local P1, P2, P3 = "Player-0-CMTEST01", "Player-0-CMTEST02", "Player-0-CMTEST03"
    local PET = "Pet-0-CMTEST-PET1"
    local M1, M2 = "Creature-0-0-0-0-9001-CMTEST1", "Creature-0-0-0-0-9001-CMTEST2"
    local FP, FPP = 0x511, 0x512    -- group players (mine / party)
    local FPET = 0x1112             -- party player-controlled pet
    local FM = 0xA48                -- hostile NPC
    E.SetRosterEntry(P1, nil, "Vanguard", "WARRIOR")
    E.SetRosterEntry(P2, nil, "Diabolist", "WARLOCK")
    E.SetRosterEntry(P3, nil, "Confessor", "PRIEST")
    local t = now - 24
    local function ev(offset, ...)
        E.OnCleu(t + offset, ...)
    end
    ev(0.0, "SPELL_SUMMON", nil, P2, "Diabolist", FPP, 0, PET, "Grimtongue", FPET, 0, 688, "Summon Felguard", 32)
    for i = 0, 9 do
        ev(1 + i * 2, "SWING_DAMAGE", nil, P1, "Vanguard", FP, 0, M1, "Training Dummy", FM, 0,
            380 + i * 7, 0, 1, 0, 0, 0, i % 4 == 0, i % 5 == 3, false, false)
        ev(2 + i * 2, "SPELL_DAMAGE", nil, P2, "Diabolist", FPP, 0, M1, "Training Dummy", FM, 0,
            686, "Shadow Bolt", 32, 900 + i * 11, 0, 32, i % 3 == 2 and 55 or 0, 0, 0, i % 3 == 0, false, false, false)
        ev(2.5 + i * 2, "SWING_DAMAGE", nil, PET, "Grimtongue", FPET, 0, M2, "Dummy Guard", FM, 0,
            210 + i * 3, 0, 1, 0, 0, 0, false, false, false, false)
    end
    -- Casts for APM: the warlock hard-casts every bolt, the warrior presses
    -- something every other second, the priest heals; the pet's cast and
    -- the warrior's wand are not keypresses and must not count
    for i = 0, 9 do
        ev(1.9 + i * 2, "SPELL_CAST_SUCCESS", nil, P2, "Diabolist", FPP, 0, M1, "Training Dummy", FM, 0,
            686, "Shadow Bolt", 32)
        ev(1 + i * 2, "SPELL_CAST_SUCCESS", nil, P1, "Vanguard", FP, 0, M1, "Training Dummy", FM, 0,
            i % 2 == 0 and 11567 or 7373, i % 2 == 0 and "Heroic Strike" or "Hamstring", 1)
        ev(2.4 + i * 2, "SPELL_CAST_SUCCESS", nil, PET, "Grimtongue", FPET, 0, M2, "Dummy Guard", FM, 0,
            30213, "Cleave", 1)
    end
    ev(4.0, "SPELL_CAST_SUCCESS", nil, P1, "Vanguard", FP, 0, M1, "Training Dummy", FM, 0,
        5019, "Shoot", 1)
    ev(12.9, "SPELL_CAST_SUCCESS", nil, P3, "Confessor", FP, 0, P1, "Vanguard", FP, 0,
        2060, "Greater Heal", 2)
    ev(13.9, "SPELL_CAST_SUCCESS", nil, P3, "Confessor", FP, 0, P1, "Vanguard", FP, 0,
        139, "Renew", 2)
    ev(5.2, "SWING_MISSED", nil, P1, "Vanguard", FP, 0, M1, "Training Dummy", FM, 0, "DODGE", false, 0)
    ev(9.7, "SPELL_MISSED", nil, P2, "Diabolist", FPP, 0, M2, "Dummy Guard", FM, 0,
        686, "Shadow Bolt", 32, "RESIST", false, 0)
    ev(10.5, "SPELL_INTERRUPT", nil, P1, "Vanguard", FP, 0, M2, "Dummy Guard", FM, 0,
        6552, "Pummel", 1, 12345, "Dummy Bolt", 32)
    ev(10.8, "SPELL_DISPEL", nil, P3, "Confessor", FP, 0, P1, "Vanguard", FP, 0,
        527, "Dispel Magic", 2, 23456, "Dummy Curse", 32, "DEBUFF")
    -- ...and an offensive one: a buff off the dummy (the DISPELS split)
    ev(11.2, "SPELL_DISPEL", nil, P3, "Confessor", FP, 0, M1, "Training Dummy", FM, 0,
        988, "Dispel Magic", 2, 23457, "Dummy Ward", 2, "BUFF")
    ev(11.0, "SPELL_DAMAGE", nil, M1, "Training Dummy", FM, 0, P1, "Vanguard", FP, 0,
        15621, "Skull Crack", 1, 1500, 0, 1, 0, 0, 350, false, false, true, false)
    -- The priest's shield eats a hit (healer absorb credit + attacker damage)
    ev(12.0, "SPELL_ABSORBED", nil, M2, "Dummy Guard", FM, 0, P3, "Confessor", FP, 0,
        P3, "Confessor", FP, 0, 17, "Power Word: Shield", 2, 620, false)
    ev(12.0, "SWING_MISSED", nil, M2, "Dummy Guard", FM, 0, P3, "Confessor", FP, 0, "ABSORB", false, 620)
    ev(13.0, "SPELL_HEAL", nil, P3, "Confessor", FP, 0, P1, "Vanguard", FP, 0,
        2060, "Greater Heal", 2, 2400, 700, 0, true)
    ev(14.0, "SPELL_PERIODIC_HEAL", nil, P3, "Confessor", FP, 0, P1, "Vanguard", FP, 0,
        139, "Renew", 2, 300, 0, 0, false)
    for i = 0, 4 do
        ev(15 + i, "SPELL_DAMAGE", nil, M1, "Training Dummy", FM, 0, P3, "Confessor", FP, 0,
            15621, "Skull Crack", 1, 900 + i * 120, i == 4 and 200 or 0, 1, 0, 0, 0, false, false, false, false)
    end
    ev(20.5, "UNIT_DIED", nil, nil, nil, 0x80000000, 0, P3, "Confessor", FP, 0, 0, false)
    print("|cff66ccffCommander Meters|r: test fight injected — it closes into LAST in a few seconds; RESET › EVERYTHING clears it")
    repaintNow()
end


-- ---------------------------------------------------------------------------
-- Arena: match lifecycle, rosters, HP snapshots, the scoreboard
-- ---------------------------------------------------------------------------

local ARENA_UNITS = { "arena1", "arena2", "arena3", "arena4", "arena5" }
local ARENA_PETS = { "arenapet1", "arenapet2", "arenapet3", "arenapet4", "arenapet5" }
local US_UNITS = { "player", "party1", "party2", "party3", "party4" }
local US_PETS = { "pet", "partypet1", "partypet2", "partypet3", "partypet4" }
local arenaEvents -- the frame that registers UNIT_HEALTH only while a match is on
local arenaHpAcc = 0

local function InArenaNow()
    if IsActiveBattlefieldArena then
        local ok, isArena = pcall(IsActiveBattlefieldArena)
        if ok and isArena then return true end
    end
    local _, instanceType = IsInInstance()
    return instanceType == "arena"
end

-- A seat from a unit token. Nil answers (stealth, out of range) leave the
-- seat's identity alone — the engine treats nil as "not right now".
local function ArenaSeatFromUnit(team, token)
    if not UnitExists(token) then return end
    local guid = UnitGUID(token)
    if not guid then return end
    local _, class = UnitClass(token)
    -- The race FILE token (second return: "BloodElf"), the racial book's key
    local race
    if UnitRace then
        local _, raceToken = UnitRace(token)
        race = raceToken
    end
    A.SetSeat(team, guid, UnitName(token), class, race, token)
    return guid
end

-- Opponent specs from the prep phase: the one API that names an enemy's
-- spec outright. GetSpecializationInfoByID gives class + spec name.
local function ArenaReadSpecs()
    if not (GetNumArenaOpponentSpecs and GetArenaOpponentSpec and GetSpecializationInfoByID) then return end
    local ok, count = pcall(GetNumArenaOpponentSpecs)
    if not ok or type(count) ~= "number" then return end
    for index = 1, math.min(count, 5) do
        local okSpec, specId = pcall(GetArenaOpponentSpec, index)
        if okSpec and type(specId) == "number" and specId > 0 then
            local okInfo, _, specName, _, _, _, classToken = pcall(GetSpecializationInfoByID, specId)
            local token = ARENA_UNITS[index]
            local guid = UnitExists(token) and UnitGUID(token)
            if okInfo and guid then
                A.SetSeat("them", guid, nil, classToken, nil, token, specName)
            end
        end
    end
end

local function ArenaScanRoster()
    if not A.Live() then return end
    for i, token in ipairs(US_UNITS) do
        local owner = ArenaSeatFromUnit("us", token)
        local petToken = US_PETS[i]
        if owner and UnitExists(petToken) then
            local petGuid = UnitGUID(petToken)
            if petGuid then A.SetOwner(petGuid, owner, UnitName(petToken)) end
        end
    end
    for i, token in ipairs(ARENA_UNITS) do
        local owner = ArenaSeatFromUnit("them", token)
        local petToken = ARENA_PETS[i]
        if owner and UnitExists(petToken) then
            local petGuid = UnitGUID(petToken)
            if petGuid then A.SetOwner(petGuid, owner, UnitName(petToken)) end
        end
    end
    ArenaReadSpecs()
end

-- HP for every seat we can read, once a second (UNIT_HEALTH is also fed
-- as it arrives; this pass covers units whose events we missed)
local function ArenaSampleUnit(token, now)
    if not UnitExists(token) then return end
    local guid = UnitGUID(token)
    if not guid then return end
    A.SetHealth(guid, UnitHealth(token), UnitHealthMax(token), now)
    if UnitPower and UnitPowerMax then
        local ptype = UnitPowerType and UnitPowerType(token) or 0
        A.SetPower(guid, UnitPower(token), UnitPowerMax(token), ptype, now)
    end
end

local function ArenaSampleHealth(now)
    local m = A.Live()
    if not m then return end
    for _, token in ipairs(US_UNITS) do ArenaSampleUnit(token, now) end
    for _, token in ipairs(ARENA_UNITS) do ArenaSampleUnit(token, now) end
end

-- The enemy's PvP trinket, from the client itself (the one enemy cooldown
-- it answers for): C_PvP.GetArenaCrowdControlInfo(unit) -> spellId, start
-- and duration in MILLISECONDS on the GetTime clock, zero while ready.
-- The combat log misses it — each medallion casts its own item spell —
-- so this is the source that makes the badge true for enemies.
local trinketAsked = {}

local function ArenaReadTrinkets()
    local m = A.Live()
    if not m or not (C_PvP and C_PvP.GetArenaCrowdControlInfo) then return end
    for _, token in ipairs(ARENA_UNITS) do
        if UnitExists(token) then
            local guid = UnitGUID(token)
            if guid then
                if not trinketAsked[guid] and C_PvP.RequestCrowdControlSpell then
                    trinketAsked[guid] = true
                    pcall(C_PvP.RequestCrowdControlSpell, token)
                end
                local ok, spellId, startMs, durMs = pcall(C_PvP.GetArenaCrowdControlInfo, token)
                if ok and type(startMs) == "number" and type(durMs) == "number" and startMs > 0 and durMs > 0 then
                    -- Press time on the epoch clock: now minus how long ago it started
                    local ago = GetTime() - startMs / 1000
                    if ago < 0 then ago = 0 end
                    local name = type(spellId) == "number" and GetSpellInfo and GetSpellInfo(spellId) or nil
                    A.OnTrinket(guid, time() - ago, durMs / 1000, type(spellId) == "number" and spellId or nil,
                        type(name) == "string" and name or nil)
                end
            end
        end
    end
end

-- Our own side's press, from the cast event (the combat log names an
-- item spell; this names the unit and the spell id directly)
local function ArenaOnUnitCast(unit, spellId)
    if not A.Live() or not unit or type(spellId) ~= "number" then return end
    if unit ~= "player" and not unit:find("^party%d$") then return end
    local name = GetSpellInfo and GetSpellInfo(spellId) or nil
    if type(name) ~= "string" then name = nil end
    if not A.IsTrinketSpell(spellId, name) then return end
    local guid = UnitGUID(unit)
    if guid then A.OnTrinket(guid, time(), nil, spellId, name) end
end

local function ArenaMapName()
    local name = GetInstanceInfo and GetInstanceInfo()
    if type(name) == "string" and name ~= "" then return name end
    return GetRealZoneText and GetRealZoneText() or nil
end

-- The core meter reads a match as ONE fight (D28): the label its segment
-- closes with names the match the way the replay does
local function MatchLabel(m)
    if not m then return nil end
    local size = m.bracket > 0 and (m.bracket .. "v" .. m.bracket) or "Arena"
    return size .. " " .. (m.map or "Arena")
end

-- Our personal ratings before the gates: GetPersonalRatedInfo(i) ->
-- rating @1 ... teamSize @12 (i is a slot, not a bracket). Asked for on
-- entry (RequestRatedInfo -> PVP_RATED_STATS_UPDATE); the engine only
-- accepts it while the match is undecided, so "before" is never post-match.
local myRatingRead = {}

local function ArenaReadMyRatings()
    local m = A.Live()
    if not m or not GetPersonalRatedInfo then return end
    for k in pairs(myRatingRead) do myRatingRead[k] = nil end
    for i = 1, 3 do
        local ok, rating, _, _, _, _, _, _, _, _, _, _, teamSize = pcall(GetPersonalRatedInfo, i)
        if ok and type(rating) == "number" and type(teamSize) == "number" then
            myRatingRead[teamSize] = rating
        end
    end
    A.SetMyRatings(m, myRatingRead)
end

local function ArenaBegin()
    if not (db and db.EnableMeters and db.ArenaRecord) then return end
    if A.Live() then return end
    E.SetMatch(true)
    A.Begin(time(), ArenaMapName())
    ArenaScanRoster()
    ArenaReadMyRatings() -- whatever the client already holds; the request refreshes it
    if RequestRatedInfo then pcall(RequestRatedInfo) end
    for k in pairs(trinketAsked) do trinketAsked[k] = nil end
    if arenaEvents then
        pcall(arenaEvents.RegisterEvent, arenaEvents, "UNIT_HEALTH")
        pcall(arenaEvents.RegisterEvent, arenaEvents, "UNIT_POWER_UPDATE")
        pcall(arenaEvents.RegisterEvent, arenaEvents, "UNIT_SPELLCAST_SUCCEEDED")
    end
end

-- The scoreboard, read into the engine's row shape. GetBattlefieldScore:
-- name, killingBlows, honorableKills, deaths, honorGained, faction, rank,
-- race, class, classToken, damageDone, healingDone, ratingChange,
-- preMatchMMR (Blizzard's TBC WorldStateFrame order).
local scoreRows = {}

local function ArenaReadScoreboard()
    if not (GetNumBattlefieldScores and GetBattlefieldScore) then return nil end
    local ok, count = pcall(GetNumBattlefieldScores)
    if not ok or (count or 0) <= 0 then return nil end
    for i = #scoreRows, 1, -1 do scoreRows[i] = nil end
    for index = 1, count do
        local okRow, name, kb, hk, deaths, honor, faction, _, race, _, classToken, dmg, heal, ratingChange, mmr =
            pcall(GetBattlefieldScore, index)
        -- A row whose first value is not a name is not a player. The client
        -- has been seen to answer 1 there (ArenaArmory's StripRealm crash,
        -- 2026-10-16), and a number seated as a name breaks every string
        -- read of it downstream.
        if okRow and type(name) == "string" and name ~= "" then
            scoreRows[#scoreRows + 1] = { name = name, kb = kb, hk = hk, deaths = deaths, honor = honor,
                faction = faction, race = race, classToken = classToken, dmg = dmg, heal = heal,
                ratingChange = ratingChange, mmr = mmr }
        end
    end
    return scoreRows
end

-- Team ratings: GetBattlefieldTeamInfo(index) -> teamName, oldTeamRating,
-- newTeamRating, teamRating(MMR) in Blizzard's TBC scoreboard. Index 0/1
-- are the arena factions (green/gold); ours comes from
-- GetBattlefieldArenaFaction. Every value is type-checked; anything odd
-- is simply not recorded. A teamless season (GetCurrentArenaSeasonUsesTeams
-- false, the Anniversary ladder) has no team rating: Blizzard's board shows
-- each player's own ratingChange instead, and so does the replay.
local function ArenaSeasonTeamless()
    if not GetCurrentArenaSeasonUsesTeams then return false end
    local ok, usesTeams = pcall(GetCurrentArenaSeasonUsesTeams)
    return ok and not usesTeams
end

local function ArenaReadTeamInfo(m, ourFaction)
    if not GetBattlefieldTeamInfo or type(ourFaction) ~= "number" then return end
    local teamless = ArenaSeasonTeamless()
    for index = 0, 1 do
        local ok, name, before, after, mmr = pcall(GetBattlefieldTeamInfo, index)
        if ok then
            A.SetTeamInfo(m, index == ourFaction and "us" or "them",
                { name = name, before = before, after = after, mmr = mmr, teamless = teamless })
        end
    end
end

-- Rated or skirmish, the way Blizzard's board decides it
local function ArenaReadRanked(m)
    if not IsActiveBattlefieldArena then return end
    local ok, isArena, isRanked = pcall(IsActiveBattlefieldArena)
    if ok and isArena then m.rated = isRanked and true or false end
end

local SCORE_REFRESH_S = 120
local scoreRefresh = { m = nil, faction = nil, untilTs = 0 } -- the closed match whose board is still up

local function ArenaFinishIfDecided()
    local m = A.Live()
    if not m then return end
    if not GetBattlefieldWinner then return end
    local ok, winner = pcall(GetBattlefieldWinner)
    if not ok or winner == nil then return end
    local ourFaction
    if GetBattlefieldArenaFaction then
        local okF, f = pcall(GetBattlefieldArenaFaction)
        if okF then ourFaction = f end
    end
    local result
    if type(winner) == "number" and type(ourFaction) == "number" then
        result = winner == ourFaction and "WIN" or "LOSS"
    else
        result = "DRAW"
    end
    ArenaReadRanked(m)
    local rows = ArenaReadScoreboard()
    if rows then A.MergeScoreboard(m, rows, ourFaction) end
    ArenaReadTeamInfo(m, ourFaction)
    local runTime
    if GetBattlefieldInstanceRunTime then
        local okR, ms = pcall(GetBattlefieldInstanceRunTime)
        if okR and type(ms) == "number" and ms > 0 then runTime = ms / 1000 end
    end
    ArenaReadTrinkets() -- a last read, so a press in the final second lands
    if arenaEvents then
        pcall(arenaEvents.UnregisterEvent, arenaEvents, "UNIT_HEALTH")
        pcall(arenaEvents.UnregisterEvent, arenaEvents, "UNIT_POWER_UPDATE")
        pcall(arenaEvents.UnregisterEvent, arenaEvents, "UNIT_SPELLCAST_SUCCEEDED")
    end
    E.SetMatch(false, MatchLabel(m), result, time())
    local done = A.Finish(time(), result, runTime)
    if done and db.ArenaScoreboard then
        scoreRefresh.m, scoreRefresh.faction, scoreRefresh.untilTs = done, ourFaction, time() + SCORE_REFRESH_S
    end
end

-- The Scoreboard option keeps reading the board after the result, while
-- it is up: the ratings can land a beat after the winner (ArenaArmory
-- retries for twenty seconds for exactly this), and Blizzard's own board
-- asks the server every frame while shown, so UPDATE_BATTLEFIELD_SCORE
-- keeps coming until we leave. Each read merges onto the CLOSED match;
-- only a changed number repaints. Leaving the arena, a new match, or two
-- minutes end it.
local function ArenaRefreshScore()
    local m = scoreRefresh.m
    if not m then return end
    if A.Live() or time() > scoreRefresh.untilTs or not db.ArenaScoreboard or not InArenaNow() then
        scoreRefresh.m = nil
        return
    end
    local rows = ArenaReadScoreboard()
    if not rows then return end
    local rev = m.sbRev
    A.MergeScoreboard(m, rows, scoreRefresh.faction)
    ArenaReadTeamInfo(m, scoreRefresh.faction)
    if m.sbRev ~= rev then repaintNow() end
end

-- Battlegrounds get the same one-fight-per-match reading (no replay —
-- forty players are beyond the log's reach — but DAMAGE, HEALING, deaths
-- and the graph read per game, not per skirmish at a node)
local bgActive = false
local bgName = nil

local function InBattlegroundNow()
    local _, instanceType = IsInInstance()
    return instanceType == "pvp"
end

local function BattlegroundResult()
    if not GetBattlefieldWinner then return nil end
    local ok, winner = pcall(GetBattlefieldWinner)
    if not ok or type(winner) ~= "number" then return nil end
    -- 0 = Horde, 1 = Alliance (the TBC WorldStateFrame convention)
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local mine = faction == "Alliance" and 1 or (faction == "Horde" and 0 or nil)
    if mine == nil then return "DRAW" end
    return winner == mine and "WIN" or "LOSS"
end

local function BattlegroundZoneCheck()
    if not db then return end
    local inBg = InBattlegroundNow()
    if inBg and not bgActive then
        bgActive = true
        bgName = ArenaMapName()
        E.SetMatch(true)
    elseif not inBg and bgActive then
        bgActive = false
        E.SetMatch(false, bgName, nil, time())
        bgName = nil
    end
end

local function BattlegroundFinishIfDecided()
    if not bgActive then return end
    local result = BattlegroundResult()
    if not result then return end
    bgActive = false
    E.SetMatch(false, bgName, result, time())
    bgName = nil
end

local function ArenaZoneCheck()
    if not db then return end
    BattlegroundZoneCheck()
    local inArena = InArenaNow()
    if not inArena then scoreRefresh.m = nil end
    if inArena then
        ArenaBegin()
    elseif A.Live() then
        -- Left without a result: the engine archives it as LEFT if the
        -- gates ever opened, discards it otherwise
        if arenaEvents then
            pcall(arenaEvents.UnregisterEvent, arenaEvents, "UNIT_HEALTH")
            pcall(arenaEvents.UnregisterEvent, arenaEvents, "UNIT_POWER_UPDATE")
            pcall(arenaEvents.UnregisterEvent, arenaEvents, "UNIT_SPELLCAST_SUCCEEDED")
        end
        E.SetMatch(false, MatchLabel(A.Live()), nil, time())
        A.Abort(time())
    end
end

local function OnArenaMatchStart(m)
    if CommanderMetersArena_OnMatchStart then CommanderMetersArena_OnMatchStart(m) end
    repaintNow()
end

-- The report never opens itself at match end: the header's arena glyph,
-- /cm arena, or a click on an ARENA row opens it. (An open report does
-- switch to the finished match, see CommanderMetersArena_OnMatchEnd.)
local function OnArenaMatchEnd(m)
    if CommanderMetersArena_OnMatchEnd then CommanderMetersArena_OnMatchEnd(m) end
    repaintNow()
end

-- Rule data for the arena engine, from the suite when installed: the DR
-- table (Arena Frames or Diminish — same generated block), the cooldown
-- book and the drink list (Arena Frames). Without them CC still counts by
-- name and cooldowns are simply not tracked; the health command says so.
local arenaDataNote = nil

local function LoadArenaData()
    local dr = (CommanderArenaFrames_Data and CommanderArenaFrames_Data.DR_BY_SPELL)
        or (CommanderDiminish_Data and CommanderDiminish_Data.DR_BY_SPELL)
    local extra = CommanderArenaFrames_Data and CommanderArenaFrames_Data.CONTROL_EXTRA
    if dr then
        A.SetDRTable(dr, extra)
    else
        arenaDataNote = "no DR table (install Commander_ArenaFrames or Commander_Diminish for CC brackets)"
    end
    -- The trinket's localized spell name (the English aliases ship in the engine)
    A.SetTrinketNames({ SpellName(42292) })
    A.SetFeignNames({ SpellName(5384) })
    if CommanderArenaFrames_Data then
        A.SetBook(CommanderArenaFrames_Data.ENEMY_BOOK, CommanderArenaFrames_Data.RACIAL_BOOK)
        A.SetDrinkIds(CommanderArenaFrames_Data.DRINK_IDS)
        A.SetSpecMarkers(CommanderArenaFrames_Data.SPEC_MARKERS)
    else
        -- The drink auras alone are worth carrying: the classic TBC water
        -- ids (the same list Arena Frames generated)
        A.SetDrinkIds({ 430, 431, 432, 1133, 1135, 1137, 10250, 22734, 27089, 34291 })
        arenaDataNote = (arenaDataNote and (arenaDataNote .. "; ") or "")
            .. "no cooldown book (install Commander_ArenaFrames to log enemy cooldowns)"
    end
end

function CommanderMetersArena_DataNote()
    return arenaDataNote
end

function CommanderMeters_ArenaToggle()
    if CommanderMetersArena_Toggle then CommanderMetersArena_Toggle() end
end

-- Injects a canned 3v3 (RMP vs warrior/druid/warlock) through the REAL
-- arena engine, with HP snapshots, so the Arena Report can be read
-- without queueing. The match closes as a WIN at once and joins the
-- match list like any other.
function CommanderMeters_ArenaTest()
    if not (db and db.EnableMeters) then
        print("|cff66ccffCommander Meters|r: meters are disabled — enable them in the settings first")
        return
    end
    if A.Live() then
        print("|cff66ccffCommander Meters|r: a real match is being recorded — the test waits")
        return
    end
    local ME, R2, P3 = "Player-0-CMARENA01", "Player-0-CMARENA02", "Player-0-CMARENA03"
    local W1, D2, L3 = "Player-1-CMARENA11", "Player-1-CMARENA12", "Player-1-CMARENA13"
    local FEL = "Pet-0-CMARENA-FEL"
    local FME, FPARTY, FENEMY, FEPET = 0x511, 0x512, 0x548, 0x1148
    local now = time()
    local t0 = now - 200
    local m = A.Begin(t0, "Nagrand Arena")
    A.SetSeat("us", ME, "Frostweaver", "MAGE", "Human", "player", "Frost")
    A.SetSeat("us", R2, "Shiv", "ROGUE", "NightElf", "party1", "Sub")
    A.SetSeat("us", P3, "Vespers", "PRIEST", "Dwarf", "party2", "Disc")
    A.SetSeat("them", W1, "Gorehowl", "WARRIOR", "Orc", "arena1") -- spec revealed by Mortal Strike
    A.SetSeat("them", D2, "Leafshade", "DRUID", "Tauren", "arena2", "Resto")
    A.SetSeat("them", L3, "Nethra", "WARLOCK", "Undead", "arena3", "Affli")
    A.SetOwner(FEL, L3, "Felhunter")
    local hp = { [ME] = 8200, [R2] = 7600, [P3] = 8900, [W1] = 11800, [D2] = 9400, [L3] = 8100 }
    local hpMax = { [ME] = 8200, [R2] = 7600, [P3] = 8900, [W1] = 11800, [D2] = 9400, [L3] = 8100 }
    local ev -- the event queue's entry point, defined with the queue below
    local pow = { [ME] = 1000, [R2] = 1000, [P3] = 1000, [W1] = 0, [D2] = 1000, [L3] = 1000 }
    local powType = { [ME] = 0, [R2] = 3, [P3] = 0, [W1] = 1, [D2] = 0, [L3] = 0 }
    local function snap(g, t)
        A.SetHealth(g, math.max(hp[g], 0), hpMax[g], t0 + t)
        A.SetPower(g, pow[g], 1000, powType[g], t0 + t)
    end
    for g in pairs(hp) do snap(g, 0) end
    local function spend(g, t, amount)
        pow[g] = math.max(0, math.min(1000, pow[g] - amount))
        A.SetPower(g, pow[g], 1000, powType[g], t0 + t)
    end
    local function castStart(t, sg, sn, sf, id, name)
        ev(t, "SPELL_CAST_START", nil, sg, sn, sf, 0, "", "", 0x80000000, 0, id, name, 16)
    end
    local function buff(t, sub, sg, sn, sf, dg, dn, df, id, name)
        ev(t, sub, nil, sg, sn, sf, 0, dg, dn, df, 0, id, name, 1, "BUFF")
    end
    -- The script below is written by subject, not by clock; the engine
    -- expects the combat log's chronological order, so events queue up
    -- and are replayed sorted by time (emission order breaks ties)
    local queue = {}
    ev = function(t, ...)
        queue[#queue + 1] = { t = t, n = #queue + 1, argn = select("#", ...), ... }
    end
    -- The script's numbers outrun the HP pools (it is a demonstration,
    -- not a simulation): a non-fatal hit never reads below 5%, and the
    -- scripted deaths set 0 themselves
    local function dmg(t, sg, sn, sf, dg, dn, df, id, name, amount, crit)
        ev(t, "SPELL_DAMAGE", nil, sg, sn, sf, 0, dg, dn, df, 0, id, name, 16, amount, 0, 16, 0, 0, 0, crit or false, false, false, false)
        hp[dg] = math.max(hp[dg] - amount, hpMax[dg] * 0.05)
        snap(dg, t)
    end
    local function swing(t, sg, sn, sf, dg, dn, df, amount, crit)
        ev(t, "SWING_DAMAGE", nil, sg, sn, sf, 0, dg, dn, df, 0, amount, 0, 1, 0, 0, 0, crit or false, false, false, false)
        hp[dg] = math.max(hp[dg] - amount, hpMax[dg] * 0.05)
        snap(dg, t)
    end
    local function heal(t, sg, sn, sf, dg, dn, df, id, name, amount, over)
        ev(t, "SPELL_HEAL", nil, sg, sn, sf, 0, dg, dn, df, 0, id, name, 2, amount, over or 0, 0, false)
        hp[dg] = math.min(hp[dg] + amount - (over or 0), hpMax[dg])
        snap(dg, t)
    end
    local function aura(t, sub, sg, sn, sf, dg, dn, df, id, name)
        ev(t, sub, nil, sg, sn, sf, 0, dg, dn, df, 0, id, name, 1, "DEBUFF")
    end
    local function cast(t, sg, sn, sf, id, name, dg)
        -- dg: the spell's target seat when it has one (who they are on)
        ev(t, "SPELL_CAST_SUCCESS", nil, sg, sn, sf, 0, dg or "", "", dg and 0x548 or 0x80000000, 0, id, name, 1)
    end
    -- Gates at +60 (prep fades on us); pre-gate buffs on both sides
    buff(30, "SPELL_AURA_APPLIED", ME, "Frostweaver", FME, ME, "Frostweaver", FME, 27134, "Ice Barrier")
    buff(31, "SPELL_AURA_APPLIED", P3, "Vespers", FPARTY, ME, "Frostweaver", FME, 25389, "Prayer of Fortitude")
    buff(31, "SPELL_AURA_APPLIED", P3, "Vespers", FPARTY, R2, "Shiv", FPARTY, 25389, "Prayer of Fortitude")
    buff(32, "SPELL_AURA_APPLIED", D2, "Leafshade", FENEMY, W1, "Gorehowl", FENEMY, 26991, "Gift of the Wild")
    buff(32, "SPELL_AURA_APPLIED", D2, "Leafshade", FENEMY, D2, "Leafshade", FENEMY, 26992, "Thorns")
    buff(33, "SPELL_AURA_APPLIED", L3, "Nethra", FENEMY, L3, "Nethra", FENEMY, 27260, "Fel Armor")
    aura(60, "SPELL_AURA_REMOVED", ME, "Frostweaver", FME, ME, "Frostweaver", FME, 32727, "Arena Preparation")
    -- Opener: sap the druid, cheap shot the warlock, mage sheeps the warrior
    aura(64, "SPELL_AURA_APPLIED", R2, "Shiv", FPARTY, D2, "Leafshade", FENEMY, 11297, "Sap")
    cast(64, R2, "Shiv", FPARTY, 11297, "Sap")
    aura(66, "SPELL_AURA_APPLIED", R2, "Shiv", FPARTY, L3, "Nethra", FENEMY, 1833, "Cheap Shot")
    cast(66, R2, "Shiv", FPARTY, 1833, "Cheap Shot")
    aura(67, "SPELL_AURA_APPLIED", ME, "Frostweaver", FME, W1, "Gorehowl", FENEMY, 12826, "Polymorph")
    cast(67, ME, "Frostweaver", FME, 12826, "Polymorph")
    for i = 0, 3 do
        swing(67 + i, R2, "Shiv", FPARTY, L3, "Nethra", FENEMY, 380 + i * 25, i == 1)
        cast(67.5 + i, R2, "Shiv", FPARTY, 26862, "Sinister Strike", L3)
        dmg(67.5 + i, R2, "Shiv", FPARTY, L3, "Nethra", FENEMY, 26862, "Sinister Strike", 640 + i * 30, i == 2)
    end
    aura(70, "SPELL_AURA_REMOVED", R2, "Shiv", FPARTY, L3, "Nethra", FENEMY, 1833, "Cheap Shot")
    aura(70.2, "SPELL_AURA_APPLIED", R2, "Shiv", FPARTY, L3, "Nethra", FENEMY, 408, "Kidney Shot")
    cast(70.2, R2, "Shiv", FPARTY, 408, "Kidney Shot")
    -- Warrior breaks out of sheep on trinket at +71
    cast(71, W1, "Gorehowl", FENEMY, 42292, "PvP Trinket")
    aura(71, "SPELL_AURA_REMOVED", ME, "Frostweaver", FME, W1, "Gorehowl", FENEMY, 12826, "Polymorph")
    -- Warrior charges the rogue, breaks the druid's sap by mistake with a sweeping strike
    aura(72, "SPELL_AURA_APPLIED", W1, "Gorehowl", FENEMY, R2, "Shiv", FPARTY, 11578, "Charge Stun")
    cast(72, W1, "Gorehowl", FENEMY, 11578, "Charge")
    -- The mage's Frostbolt breaks the rogue's Sap on the druid: the own-team
    -- break the report counts as a mistake
    cast(72.8, ME, "Frostweaver", FME, 27072, "Frostbolt")
    dmg(72.8, ME, "Frostweaver", FME, D2, "Leafshade", FENEMY, 27072, "Frostbolt", 1380, false)
    ev(72.8, "SPELL_AURA_BROKEN_SPELL", nil, ME, "Frostweaver", FME, 0, D2, "Leafshade", FENEMY, 0,
        11297, "Sap", 1, 27072, "Frostbolt", 16, "DEBUFF")
    aura(73, "SPELL_AURA_REMOVED", W1, "Gorehowl", FENEMY, R2, "Shiv", FPARTY, 11578, "Charge Stun")
    -- Intercept eight seconds after the Charge stun faded: the same STUN
    -- ladder, so it lands at half
    aura(80, "SPELL_AURA_APPLIED", W1, "Gorehowl", FENEMY, R2, "Shiv", FPARTY, 20615, "Intercept Stun")
    cast(80, W1, "Gorehowl", FENEMY, 20615, "Intercept")
    aura(81.5, "SPELL_AURA_REMOVED", W1, "Gorehowl", FENEMY, R2, "Shiv", FPARTY, 20615, "Intercept Stun")
    -- Mage damage on the warlock; warlock fears the priest; warrior hits the mage
    for i = 0, 7 do
        -- Hard casts: a start, then the success a cast time later; the
        -- mage's mana and the warrior's rage move with them
        castStart(73 + i * 2.5, ME, "Frostweaver", FME, 27072, "Frostbolt")
        cast(75 + i * 2.5, ME, "Frostweaver", FME, 27072, "Frostbolt", L3)
        spend(ME, 75 + i * 2.5, 45)
        dmg(75 + i * 2.5, ME, "Frostweaver", FME, L3, "Nethra", FENEMY, 27072, "Frostbolt", 1450 + i * 40, i % 3 == 0)
        spend(W1, 74.5 + i * 2.5, -120)
        swing(74.5 + i * 2.5, W1, "Gorehowl", FENEMY, ME, "Frostweaver", FME, 520 + i * 18, i % 4 == 1)
        cast(75 + i * 2.5, W1, "Gorehowl", FENEMY, 30330, "Mortal Strike", ME)
        dmg(75 + i * 2.5, W1, "Gorehowl", FENEMY, ME, "Frostweaver", FME, 30330, "Mortal Strike", 900 + i * 35, i % 3 == 2)
        castStart(74 + i * 2.5, P3, "Vespers", FPARTY, 25235, "Flash Heal")
        cast(75.5 + i * 2.5, P3, "Vespers", FPARTY, 25235, "Flash Heal", ME)
        spend(P3, 75.5 + i * 2.5, 60)
        heal(75.5 + i * 2.5, P3, "Vespers", FPARTY, ME, "Frostweaver", FME, 25235, "Flash Heal", 1800, i % 2 == 0 and 300 or 0)
        cast(76 + i * 2.5, D2, "Leafshade", FENEMY, 33763, "Lifebloom", L3)
        heal(76 + i * 2.5, D2, "Leafshade", FENEMY, L3, "Nethra", FENEMY, 33763, "Lifebloom", 600, 0)
    end
    aura(76, "SPELL_AURA_REMOVED", R2, "Shiv", FPARTY, L3, "Nethra", FENEMY, 408, "Kidney Shot")
    aura(78, "SPELL_AURA_APPLIED", L3, "Nethra", FENEMY, P3, "Vespers", FPARTY, 6215, "Fear")
    cast(78, L3, "Nethra", FENEMY, 6215, "Fear")
    ev(80, "SPELL_DISPEL", nil, P3, "Vespers", FPARTY, 0, P3, "Vespers", FPARTY, 0, 527, "Dispel Magic", 2, 6215, "Fear", 32, "DEBUFF")
    -- A Greater Heal that the kick below stops mid-cast; a shield on the mage
    castStart(85.2, D2, "Leafshade", FENEMY, 26980, "Regrowth")
    buff(84, "SPELL_AURA_APPLIED", P3, "Vespers", FPARTY, ME, "Frostweaver", FME, 25218, "Power Word: Shield")
    buff(114, "SPELL_AURA_REMOVED", P3, "Vespers", FPARTY, ME, "Frostweaver", FME, 25218, "Power Word: Shield")
    -- Felhunter spell-locks the priest; mage counterspells the druid
    aura(82, "SPELL_AURA_APPLIED", FEL, "Felhunter", FEPET, P3, "Vespers", FPARTY, 24259, "Spell Lock")
    cast(82, FEL, "Felhunter", FEPET, 19647, "Spell Lock")
    aura(85, "SPELL_AURA_REMOVED", FEL, "Felhunter", FEPET, P3, "Vespers", FPARTY, 24259, "Spell Lock")
    ev(86, "SPELL_INTERRUPT", nil, ME, "Frostweaver", FME, 0, D2, "Leafshade", FENEMY, 0, 2139, "Counterspell", 64, 26980, "Regrowth", 8)
    cast(86, ME, "Frostweaver", FME, 2139, "Counterspell")
    -- Priest purges lifebloom, mana burns the druid; druid drinks
    ev(88, "SPELL_DISPEL", nil, P3, "Vespers", FPARTY, 0, L3, "Nethra", FENEMY, 0, 527, "Dispel Magic", 2, 33763, "Lifebloom", 8, "BUFF")
    cast(88, P3, "Vespers", FPARTY, 527, "Dispel Magic")
    for i = 0, 2 do
        cast(90 + i * 3, P3, "Vespers", FPARTY, 25380, "Mana Burn")
        ev(90 + i * 3, "SPELL_DRAIN", nil, P3, "Vespers", FPARTY, 0, D2, "Leafshade", FENEMY, 0, 25380, "Mana Burn", 32, 1100, 0, 0)
    end
    aura(100, "SPELL_AURA_APPLIED", D2, "Leafshade", FENEMY, D2, "Leafshade", FENEMY, 27089, "Drink")
    aura(109, "SPELL_AURA_REMOVED", D2, "Leafshade", FENEMY, D2, "Leafshade", FENEMY, 27089, "Drink")
    -- A wasted sheep into a trinket-immune? No: a Polymorph resisted
    ev(96, "SPELL_MISSED", nil, ME, "Frostweaver", FME, 0, W1, "Gorehowl", FENEMY, 0, 12826, "Polymorph", 64, "RESIST", false, 0, false)
    -- Enemy cooldowns: Shield Wall, Pain... a druid Barkskin, a warlock Death Coil (horror CC)
    cast(97, W1, "Gorehowl", FENEMY, 871, "Shield Wall")
    cast(98, D2, "Leafshade", FENEMY, 22812, "Barkskin")
    aura(99, "SPELL_AURA_APPLIED", L3, "Nethra", FENEMY, ME, "Frostweaver", FME, 27223, "Death Coil")
    cast(99, L3, "Nethra", FENEMY, 27223, "Death Coil")
    aura(102, "SPELL_AURA_REMOVED", L3, "Nethra", FENEMY, ME, "Frostweaver", FME, 27223, "Death Coil")
    -- Second stun ladder step on the warlock (half), then the kill
    aura(104, "SPELL_AURA_APPLIED", R2, "Shiv", FPARTY, L3, "Nethra", FENEMY, 1833, "Cheap Shot")
    cast(104, R2, "Shiv", FPARTY, 1833, "Cheap Shot")
    for i = 0, 3 do
        swing(104.5 + i, R2, "Shiv", FPARTY, L3, "Nethra", FENEMY, 410 + i * 20, i == 0)
        cast(105 + i, ME, "Frostweaver", FME, 27072, "Frostbolt")
        dmg(105 + i, ME, "Frostweaver", FME, L3, "Nethra", FENEMY, 27072, "Frostbolt", 1500 + i * 60, i == 3)
    end
    aura(108, "SPELL_AURA_REMOVED", R2, "Shiv", FPARTY, L3, "Nethra", FENEMY, 1833, "Cheap Shot")
    cast(109, ME, "Frostweaver", FME, 27072, "Frostbolt")
    dmg(109.5, ME, "Frostweaver", FME, L3, "Nethra", FENEMY, 27072, "Frostbolt", 2200, true)
    hp[L3] = 0
    snap(L3, 109.5)
    ev(110, "UNIT_DIED", nil, nil, nil, 0x80000000, 0, L3, "Nethra", FENEMY, 0)
    -- The felhunter's Devour Magic at the priest's shield: resisted, a
    -- dispel that took nothing (the dispel log's failed line)
    ev(92, "SPELL_MISSED", nil, FEL, "Felhunter", FEPET, 0, ME, "Frostweaver", FME, 0, 27277, "Devour Magic", 32, "RESIST", false, 0, false)
    -- MASS DISPEL: the druid roots the mage; the priest's Mass Dispel takes
    -- the roots off the mage (defensive) and Gift of the Wild and Thorns
    -- off the warrior and the druid (offensive) — one cast, three removals,
    -- the sequence the dispel log reads back (cast between two Flash Heals)
    aura(114, "SPELL_AURA_APPLIED", D2, "Leafshade", FENEMY, ME, "Frostweaver", FME, 26989, "Entangling Roots")
    cast(114, D2, "Leafshade", FENEMY, 26989, "Entangling Roots", ME)
    castStart(116.3, P3, "Vespers", FPARTY, 32375, "Mass Dispel")
    cast(117.8, P3, "Vespers", FPARTY, 32375, "Mass Dispel")
    spend(P3, 117.8, 140)
    ev(117.8, "SPELL_DISPEL", nil, P3, "Vespers", FPARTY, 0, ME, "Frostweaver", FME, 0, 32375, "Mass Dispel", 1, 26989, "Entangling Roots", 8, "DEBUFF")
    aura(117.8, "SPELL_AURA_REMOVED", D2, "Leafshade", FENEMY, ME, "Frostweaver", FME, 26989, "Entangling Roots")
    ev(117.8, "SPELL_DISPEL", nil, P3, "Vespers", FPARTY, 0, W1, "Gorehowl", FENEMY, 0, 32592, "Mass Dispel", 1, 26991, "Gift of the Wild", 8, "BUFF")
    buff(117.8, "SPELL_AURA_REMOVED", D2, "Leafshade", FENEMY, W1, "Gorehowl", FENEMY, 26991, "Gift of the Wild")
    ev(117.8, "SPELL_DISPEL", nil, P3, "Vespers", FPARTY, 0, D2, "Leafshade", FENEMY, 0, 32592, "Mass Dispel", 1, 26992, "Thorns", 8, "BUFF")
    buff(117.8, "SPELL_AURA_REMOVED", D2, "Leafshade", FENEMY, D2, "Leafshade", FENEMY, 26992, "Thorns")
    -- The warrior and druid fight on; the mage takes a beating, gets healed
    for i = 0, 5 do
        swing(111 + i * 2, W1, "Gorehowl", FENEMY, ME, "Frostweaver", FME, 560 + i * 20, i == 2)
        cast(112 + i * 2, P3, "Vespers", FPARTY, 25235, "Flash Heal")
        heal(112 + i * 2, P3, "Vespers", FPARTY, ME, "Frostweaver", FME, 25235, "Flash Heal", 1700, 200)
        cast(111.5 + i * 2, R2, "Shiv", FPARTY, 26862, "Sinister Strike")
        dmg(111.5 + i * 2, R2, "Shiv", FPARTY, D2, "Leafshade", FENEMY, 26862, "Sinister Strike", 700 + i * 25, i == 4)
    end
    -- The healer is sheeped through the kill: the insight every arena
    -- player looks for first ("was their healer controlled when we killed?")
    aura(126, "SPELL_AURA_APPLIED", ME, "Frostweaver", FME, D2, "Leafshade", FENEMY, 12826, "Polymorph")
    cast(126, ME, "Frostweaver", FME, 12826, "Polymorph")
    aura(134, "SPELL_AURA_REMOVED", ME, "Frostweaver", FME, D2, "Leafshade", FENEMY, 12826, "Polymorph")
    -- Warrior dies to the rogue's Eviscerate; druid dies to a Frostbolt
    aura(124, "SPELL_AURA_APPLIED", R2, "Shiv", FPARTY, W1, "Gorehowl", FENEMY, 8643, "Kidney Shot")
    cast(124, R2, "Shiv", FPARTY, 8643, "Kidney Shot")
    for i = 0, 2 do
        cast(124.5 + i, ME, "Frostweaver", FME, 27072, "Frostbolt")
        dmg(124.5 + i, ME, "Frostweaver", FME, W1, "Gorehowl", FENEMY, 27072, "Frostbolt", 1600, i == 1)
        dmg(125 + i, R2, "Shiv", FPARTY, W1, "Gorehowl", FENEMY, 26865, "Eviscerate", 1900 + i * 200, i == 2)
    end
    aura(129, "SPELL_AURA_REMOVED", R2, "Shiv", FPARTY, W1, "Gorehowl", FENEMY, 8643, "Kidney Shot")
    dmg(129.5, R2, "Shiv", FPARTY, W1, "Gorehowl", FENEMY, 26865, "Eviscerate", 2400, true)
    hp[W1] = 0
    snap(W1, 129.5)
    ev(130, "UNIT_DIED", nil, nil, nil, 0x80000000, 0, W1, "Gorehowl", FENEMY, 0)
    for i = 0, 3 do
        cast(131 + i * 2, ME, "Frostweaver", FME, 27072, "Frostbolt")
        dmg(131 + i * 2, ME, "Frostweaver", FME, D2, "Leafshade", FENEMY, 27072, "Frostbolt", 1700, i == 3)
        dmg(132 + i * 2, R2, "Shiv", FPARTY, D2, "Leafshade", FENEMY, 26862, "Sinister Strike", 750, false)
    end
    hp[D2] = 0
    snap(D2, 139.5)
    ev(140, "UNIT_DIED", nil, nil, nil, 0x80000000, 0, D2, "Leafshade", FENEMY, 0)
    -- The debuffs the uptime drawer reads: poisons and the Frostbolt chill
    -- kept on the warlock and the druid (dropped while the druid was
    -- sheeped), the warrior's Mortal Strike kept on the mage
    aura(68, "SPELL_AURA_APPLIED", R2, "Shiv", FPARTY, L3, "Nethra", FENEMY, 27189, "Wound Poison V")
    for i = 1, 3 do aura(68 + i, "SPELL_AURA_APPLIED_DOSE", R2, "Shiv", FPARTY, L3, "Nethra", FENEMY, 27189, "Wound Poison V") end
    aura(68.5, "SPELL_AURA_APPLIED", R2, "Shiv", FPARTY, L3, "Nethra", FENEMY, 11201, "Crippling Poison")
    aura(80.5, "SPELL_AURA_REMOVED", R2, "Shiv", FPARTY, L3, "Nethra", FENEMY, 11201, "Crippling Poison")
    aura(105, "SPELL_AURA_APPLIED", R2, "Shiv", FPARTY, L3, "Nethra", FENEMY, 11201, "Crippling Poison")
    aura(75, "SPELL_AURA_APPLIED", ME, "Frostweaver", FME, L3, "Nethra", FENEMY, 27072, "Frostbolt")
    for i = 1, 7 do aura(75 + i * 2.5, "SPELL_AURA_REFRESH", ME, "Frostweaver", FME, L3, "Nethra", FENEMY, 27072, "Frostbolt") end
    aura(101.5, "SPELL_AURA_REMOVED", ME, "Frostweaver", FME, L3, "Nethra", FENEMY, 27072, "Frostbolt")
    aura(105, "SPELL_AURA_APPLIED", ME, "Frostweaver", FME, L3, "Nethra", FENEMY, 27072, "Frostbolt")
    aura(111.5, "SPELL_AURA_APPLIED", R2, "Shiv", FPARTY, D2, "Leafshade", FENEMY, 27189, "Wound Poison V")
    for i = 1, 4 do aura(111.5 + i * 2, "SPELL_AURA_APPLIED_DOSE", R2, "Shiv", FPARTY, D2, "Leafshade", FENEMY, 27189, "Wound Poison V") end
    aura(132, "SPELL_AURA_REFRESH", R2, "Shiv", FPARTY, D2, "Leafshade", FENEMY, 27189, "Wound Poison V")
    aura(112, "SPELL_AURA_APPLIED", R2, "Shiv", FPARTY, D2, "Leafshade", FENEMY, 11201, "Crippling Poison")
    aura(124, "SPELL_AURA_REMOVED", R2, "Shiv", FPARTY, D2, "Leafshade", FENEMY, 11201, "Crippling Poison")
    aura(133, "SPELL_AURA_APPLIED", R2, "Shiv", FPARTY, D2, "Leafshade", FENEMY, 11201, "Crippling Poison")
    aura(131, "SPELL_AURA_APPLIED", ME, "Frostweaver", FME, D2, "Leafshade", FENEMY, 27072, "Frostbolt")
    aura(75, "SPELL_AURA_APPLIED", W1, "Gorehowl", FENEMY, ME, "Frostweaver", FME, 30330, "Mortal Strike")
    for i = 1, 7 do aura(75 + i * 2.5, "SPELL_AURA_REFRESH", W1, "Gorehowl", FENEMY, ME, "Frostweaver", FME, 30330, "Mortal Strike") end
    aura(102.5, "SPELL_AURA_REMOVED", W1, "Gorehowl", FENEMY, ME, "Frostweaver", FME, 30330, "Mortal Strike")
    -- The rest of each breakdown (D33), past the one spell each player
    -- leans on: the mage's Water Elemental, Ice Lance and Fire Blast, the
    -- priest's shield absorbs, Renew, Prayer of Mending and Shadow Word:
    -- Pain, the druid's Rejuvenation and Regrowth. Queued straight, with no
    -- casts and no HP moves: the scripted health, cast bars and deaths stay
    -- exactly as they were
    local WE, FWE = "Creature-0-CMARENA-WE", 0x2111
    A.SetOwner(WE, ME, "Water Elemental")
    local function hit(t, sg, sn, sf, dg, dn, df, id, name, amount, crit, periodic)
        ev(t, periodic and "SPELL_PERIODIC_DAMAGE" or "SPELL_DAMAGE", nil, sg, sn, sf, 0, dg, dn, df, 0,
            id, name, 16, amount, 0, 16, 0, 0, 0, crit or false, false, false, false)
    end
    local function mend(t, sg, sn, sf, dg, dn, df, id, name, amount, over, periodic)
        ev(t, periodic and "SPELL_PERIODIC_HEAL" or "SPELL_HEAL", nil, sg, sn, sf, 0, dg, dn, df, 0,
            id, name, 2, amount, over or 0, 0, false)
    end
    for i = 0, 3 do hit(76 + i * 6, WE, "Water Elemental", FWE, L3, "Nethra", FENEMY, 31707, "Waterbolt", 520 + i * 20, i == 2) end
    hit(102.5, ME, "Frostweaver", FME, L3, "Nethra", FENEMY, 30455, "Ice Lance", 640)
    hit(103.5, ME, "Frostweaver", FME, L3, "Nethra", FENEMY, 30455, "Ice Lance", 1310, true)
    hit(128, ME, "Frostweaver", FME, W1, "Gorehowl", FENEMY, 27079, "Fire Blast", 980)
    hit(136.5, ME, "Frostweaver", FME, D2, "Leafshade", FENEMY, 30455, "Ice Lance", 660)
    for i, amount in ipairs({ 480, 610, 390 }) do
        ev(84 + i * 3, "SPELL_ABSORBED", nil, W1, "Gorehowl", FENEMY, 0, ME, "Frostweaver", FME, 0,
            30330, "Mortal Strike", 1, P3, "Vespers", FPARTY, 0, 25218, "Power Word: Shield", 2, amount, false)
    end
    for i = 0, 4 do mend(96 + i * 3, P3, "Vespers", FPARTY, ME, "Frostweaver", FME, 25222, "Renew", 222, i == 4 and 222 or 0, true) end
    mend(122, P3, "Vespers", FPARTY, R2, "Shiv", FPARTY, 33110, "Prayer of Mending", 800)
    for i = 0, 5 do hit(113 + i * 3, P3, "Vespers", FPARTY, W1, "Gorehowl", FENEMY, 25368, "Shadow Word: Pain", 186, false, true) end
    for i = 0, 5 do mend(77 + i * 3, D2, "Leafshade", FENEMY, L3, "Nethra", FENEMY, 26982, "Rejuvenation", 265, 0, true) end
    for i = 0, 3 do mend(112 + i * 3, D2, "Leafshade", FENEMY, W1, "Gorehowl", FENEMY, 26982, "Rejuvenation", 265, i == 3 and 80 or 0, true) end
    mend(121, D2, "Leafshade", FENEMY, W1, "Gorehowl", FENEMY, 26980, "Regrowth", 1650)
    table.sort(queue, function(a, b)
        if a.t ~= b.t then return a.t < b.t end
        return a.n < b.n
    end)
    for _, q in ipairs(queue) do
        A.OnCleu(t0 + q.t, unpack(q, 1, q.argn))
    end
    A.MergeScoreboard(m, {
        { name = "Frostweaver", kb = 2, hk = 3, deaths = 0, dmg = 31200, heal = 0, ratingChange = 14, mmr = 1912, classToken = "MAGE" },
        { name = "Shiv", kb = 1, hk = 3, deaths = 0, dmg = 18400, heal = 0, ratingChange = 14, mmr = 1904, classToken = "ROGUE" },
        { name = "Vespers", kb = 0, hk = 3, deaths = 0, dmg = 200, heal = 26900, ratingChange = 14, mmr = 1898, classToken = "PRIEST" },
        { name = "Gorehowl", kb = 0, hk = 0, deaths = 1, dmg = 17800, heal = 0, ratingChange = -13, mmr = 1876, classToken = "WARRIOR" },
        { name = "Leafshade", kb = 0, hk = 0, deaths = 1, dmg = 100, heal = 8400, ratingChange = -13, mmr = 1881, classToken = "DRUID" },
        { name = "Nethra", kb = 0, hk = 0, deaths = 1, dmg = 2100, heal = 0, ratingChange = -13, mmr = 1869, classToken = "WARLOCK" },
    })
    A.SetTeamInfo(m, "us", { name = "Frostbite Warrant", before = 1850, after = 1864, mmr = 1905 })
    A.SetTeamInfo(m, "them", { name = "Leaf Me Alone", before = 1871, after = 1858, mmr = 1875 })
    A.Finish(t0 + 141, "WIN", 81)
    print("|cff66ccffCommander Meters|r: arena test match injected (3v3, WIN) — /cm arena opens the report; RESET › EVERYTHING clears meter data but the match list keeps it (Arena › Forget Matches removes it)")
end

function CommanderMeters_ArenaForget()
    A.ResetAll()
    CommanderMetersArenaLog = nil
    if CommanderMetersArena_OnMatchEnd then CommanderMetersArena_OnMatchEnd(nil) end
    print("|cff66ccffCommander Meters|r: arena match history forgotten")
    repaintNow()
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Cross-addon: external live pane modes (the Commander_Threat embed).
-- spec = { key, label, collect(now) -> rows, n, caption() -> string,
-- empty = "no-rows line" }. Display rows carry {name, class, valueText,
-- pctText, rateText, barFrac} — finished strings and a 0..1 bar fraction,
-- so the provider owns its numbers and Meters only arranges them. The
-- provider must return POOLED rows (this runs on the 2 Hz repaint).
-- ---------------------------------------------------------------------------

function CommanderMeters_RegisterExternalMode(spec)
    if type(spec) ~= "table" or type(spec.key) ~= "string"
        or type(spec.collect) ~= "function" then
        return false
    end
    externalModes[spec.key] = {
        key = spec.key,
        label = spec.label or spec.key,
        external = spec,
        lists = {}, -- series/value/rateLabel absent: no graph, no detail
    }
    -- A pane may already be SAVED to this mode: SplitMode persists, and it
    -- resolves before the provider's addon logs in (login order) — re-adopt
    -- so the pane comes back as itself instead of the fallback mode
    if root then Apply() end
    return true
end

function CommanderMeters_RetireExternalMode(key)
    if not externalModes[key] then return end
    externalModes[key] = nil
    if db then
        -- Point orphaned panes back at real modes so ModeByKey's fallback
        -- never has to guess
        if db.ViewMode == key then db.ViewMode = "DMG" end
        if db.SplitMode == key then db.SplitMode = "HEAL" end
    end
    if root then Apply() end
end

-- The provider-side "show me": opens the split with the external mode in
-- pane 2 (and surfaces the window if it was toggled off). An explicit user
-- action on the provider's side, so surfacing is the right default.
function CommanderMeters_ShowExternalPane(key)
    if not externalModes[key] or not db then return false end
    db.SplitOpen = true
    db.SplitMode = key
    db.WindowShown = true
    if root then Apply() end
    return true
end

local GetCLEU = (C_CombatLog and C_CombatLog.GetCurrentEventInfo)
    or CombatLogGetCurrentEventInfo

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")

-- One getter call feeds both engines: varargs ride the stack, no table
local function DispatchCleu(...)
    E.OnCleu(...)
    if A.Live() then A.OnCleu(...) end
end

local function OnEvent(_, event, arg1, arg2, arg3, arg4, arg5)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if db and db.EnableMeters then
            DispatchCleu(GetCLEU())
        end
        return
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        ArenaOnUnitCast(arg1, arg3)
        return
    end
    if event == "ARENA_CROWD_CONTROL_SPELL_UPDATE" or event == "ARENA_COOLDOWNS_UPDATE" then
        ArenaReadTrinkets()
        return
    end
    if event == "UNIT_HEALTH" or event == "UNIT_POWER_UPDATE" then
        local m = A.Live()
        if m and arg1 then
            local guid = UnitGUID(arg1)
            if guid and m.seats[guid] then ArenaSampleUnit(arg1, time()) end
        end
        return
    end
    if event == "PLAYER_LOGIN" then
        db = CommanderMetersDB
        ResolveThemeOverrides()
        E.Init(db, time())
        E.onFightStart = OnFightStart
        E.onFightEnd = OnFightEnd
        -- Opt-in resume: adopt the logout snapshot if it is fresh and sane
        if db.PersistData and _G.CommanderMetersSession then
            if E.ImportSession(_G.CommanderMetersSession, time()) then
                print("|cff66ccffCommander Meters|r: session resumed — Overall and Last carried through the reload")
            end
        end
        panes[1].mode = ModeByKey(db.ViewMode)
        panes[2].mode = ModeByKey(db.SplitMode)
            view.segSel = db.ViewSegment == "overall" and "overall" or "current"
        view.segSel2 = (db.SplitSegment == "current" or db.SplitSegment == "overall")
            and db.SplitSegment or nil
        BuildWindow()
        RefreshRoster()
        LoadCCNames()
        LoadArenaData()
        A.onMatchStart = OnArenaMatchStart
        A.onMatchEnd = OnArenaMatchEnd
        arenaEvents = events
        if (tonumber(db.ArenaKeepMatches) or 0) > 0 and _G.CommanderMetersArenaLog then
            local adopted = A.Import(_G.CommanderMetersArenaLog)
            if adopted > 0 then
                print(format("|cff66ccffCommander Meters|r: %d arena match%s restored — /cm arena", adopted, adopted == 1 and "" or "es"))
            end
        end
        -- The Arena Report builds itself on first open (match end, /cm
        -- arena, or an ARENA row) — a raider who never queues pays nothing
        -- CLEU: plain registration works today; the docs flag it like the
        -- callback-only MINIMAP_PING, so keep the callback path as a net —
        -- and if the getter itself is gone (deprecation shim disabled and
        -- C_CombatLog moved), say so loudly instead of erroring per event
        if not GetCLEU then
            print("|cff66ccffCommander Meters|r: |cffff4433this client exposes no combat-log getter — recording is disabled.|r Run /cmeters health and report it.")
        else
            local ok = pcall(events.RegisterEvent, events, "COMBAT_LOG_EVENT_UNFILTERED")
            if not ok and events.RegisterEventCallback then
                pcall(events.RegisterEventCallback, events, "COMBAT_LOG_EVENT_UNFILTERED")
            end
        end
        events:RegisterEvent("PLAYER_LOGOUT")
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        events:RegisterEvent("GROUP_ROSTER_UPDATE")
        events:RegisterEvent("UNIT_PET")
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        events:RegisterEvent("READY_CHECK")
        -- Naming/tagging refinement only; segmentation never depends on these
        pcall(events.RegisterEvent, events, "ENCOUNTER_START")
        pcall(events.RegisterEvent, events, "ENCOUNTER_END")
        -- Arena: soft-registered, since the arena surface is where this
        -- client's retail-era UI seam shows (UNIT_HEALTH joins only while
        -- a match is on)
        events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        pcall(events.RegisterEvent, events, "UPDATE_BATTLEFIELD_SCORE")
        pcall(events.RegisterEvent, events, "ARENA_OPPONENT_UPDATE")
        pcall(events.RegisterEvent, events, "ARENA_PREP_OPPONENT_SPECIALIZATIONS")
        pcall(events.RegisterEvent, events, "ARENA_CROWD_CONTROL_SPELL_UPDATE")
        pcall(events.RegisterEvent, events, "ARENA_COOLDOWNS_UPDATE")
        pcall(events.RegisterEvent, events, "PVP_RATED_STATS_UPDATE")
        C_Timer.NewTicker(1, function()
            local now = time()
            E.Tick(now)
            if A.Live() then
                -- Cheap insurance against a missed roster event: ten unit
                -- reads a second while a match is on
                ArenaScanRoster()
                ArenaSampleHealth(now)
                ArenaReadTrinkets()
            end
        end)
        Commander.AddListener(COMMANDER_METERS_EVENTS.UPDATE, Apply)
        Apply()
        -- After Apply, never before: Apply is what builds the panes' rows, and
        -- a login or /reload INSIDE an arena starts the match right here,
        -- whose start repaints the meter. Before 2.5.1 this ran first and
        -- that repaint indexed rows that did not exist yet.
        ArenaZoneCheck()
        return
    end
    if event == "PLAYER_LOGOUT" then
        -- Fires on /reload too — the only moment SavedVariables flush
        if db and db.PersistData then
            CommanderMetersSession = E.ExportSession(time())
        else
            CommanderMetersSession = nil
        end
        -- Arena history: a live match at logout is archived as LEFT first
        -- so a /reload mid-match keeps what was recorded
        if A.Live() then A.Abort(time()) end
        local keep = db and tonumber(db.ArenaKeepMatches) or 0
        if keep > 0 then
            CommanderMetersArenaLog = A.Export(keep)
        else
            CommanderMetersArenaLog = nil
        end
        return
    end
    if event == "UPDATE_BATTLEFIELD_SCORE" then
        -- The refresh first: on the event that ends a match it has no
        -- target yet, so the board is read once there, not twice
        ArenaRefreshScore()
        ArenaFinishIfDecided()
        BattlegroundFinishIfDecided()
        return
    end
    if event == "ARENA_OPPONENT_UPDATE" or event == "ARENA_PREP_OPPONENT_SPECIALIZATIONS" then
        if not A.Live() then ArenaZoneCheck() end
        ArenaScanRoster()
        return
    end
    if event == "ZONE_CHANGED_NEW_AREA" then
        ArenaZoneCheck()
        return
    end
    if event == "PVP_RATED_STATS_UPDATE" then
        ArenaReadMyRatings()
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        E.SetPlayerCombat(true, time())
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        E.SetPlayerCombat(false, time())
        return
    end
    if event == "GROUP_ROSTER_UPDATE" then
        RefreshRoster()
        ArenaScanRoster()
        return
    end
    if event == "UNIT_PET" then
        MapPetOf(arg1)
        ArenaScanRoster()
        return
    end
    if event == "ENCOUNTER_START" then
        E.OnEncounterStart(arg2)
        return
    end
    if event == "ENCOUNTER_END" then
        E.OnEncounterEnd(arg2, arg5, time())
        repaintNow()
        return
    end
    if event == "READY_CHECK" then
        if db.AutoResetOnReadyCheck then
            WipeAllData("ready check")
        end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        RefreshRoster()
        ArenaZoneCheck()
        ArenaScanRoster()
        local inInstance, instanceType = IsInInstance()
        local key = inInstance and (instanceType .. (select(8, GetInstanceInfo()) or "")) or nil
        -- The baseline lives in the DB, not on this frame: a /reload inside
        -- an instance is NOT "entering" it, and must never wipe the session
        -- a PersistData import just resumed
        local prev = db.LastInstanceKey or nil
        if db.AutoResetOnInstance and key and key ~= prev then
            WipeAllData("new instance")
        end
        db.LastInstanceKey = key or false
        return
    end
end

events:SetScript("OnEvent", OnEvent)

-- ---------------------------------------------------------------------------
-- Shared with CommanderMetersArenaUI.lua (loaded after this file): the
-- theme and the drawing helpers, so the Arena Report is cut from the same
-- cloth without a second theme table or a copied helper.
-- ---------------------------------------------------------------------------

CommanderMeters_UI = {
    THEME = THEME, WHITE = WHITE, ESC = ESC,
    MakeText = MakeText, MakeEdge = MakeEdge, MakeHeaderButton = MakeHeaderButton,
    MakeGlyphButton = MakeGlyphButton, SetGlyphColor = SetGlyphColor, Quad = Quad,
    OpenMenu = OpenMenu, AddMenuTitle = AddMenuTitle, ShareMenu = ShareMenu,
    FmtNum = FmtNum, FmtTime = FmtTime, ShortName = ShortName, ClassColor = ClassColor,
    IconTag = IconTag, IconOf = IconOf, HpColor = HpColor, EscOf = EscOf,
    ArenaMatchLabel = ArenaMatchLabel, ArenaSeatTooltip = function(row, m) ArenaSeatTooltip(row, m) end,
    Repaint = function() repaintNow() end,
    DB = function() return db end,
}
