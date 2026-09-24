-- Commander Oracle: the Arathi Basin battle computer.
--
-- Reads the board off the client (flags from the map's area POIs, resources
-- from the resource widget), hands it to CommanderOracleEngine, and draws the
-- answer. The split is deliberate: everything that decides anything lives in
-- the engine, which the headless harness runs without a client. This file
-- only reads and draws.

local AB = CommanderOracle_AB
local E = CommanderOracle_Engine
local RS = CommanderOracle_Roster
local POI = CommanderOracle_POI
local FACTION_COLORS = CommanderOracle_FACTION_COLORS
local Opposite = CommanderOracle_Opposite

local WHITE = "Interface\\Buttons\\WHITE8X8"
local INF = math.huge
local PANEL_WIDTH = 226
local PAD = 8

-- The client's widget for a two-sided resource race. Named through the Enum
-- where it exists, with the wire value behind it: this is the one number in
-- the file that comes from the client rather than from a table we control.
local WIDGET_TYPES = Enum and Enum.UIWidgetVisualizationType or nil
local ICON_AND_TEXT = (WIDGET_TYPES and WIDGET_TYPES.IconAndText) or 0
local DOUBLE_STATUS_BAR = (WIDGET_TYPES and WIDGET_TYPES.DoubleStatusBar) or 2

local board = {}            -- [nodeIndex] = { state, owner, assaulter, node }
local contested = {}        -- [nodeKey] = { since = GetTime(), exact = bool }
local scores = { alliance = nil, horde = nil, at = nil, estimated = false }
local myFaction, enemyFaction
local inBasin = false
-- Wider than inBasin on purpose: the projection is Arathi's, but the roster
-- tabs need nothing but the battlefield scoreboard, which every battleground
-- has. See the tab block below.
local inBattleground = false
-- Arena is neither: the board has nothing to say there, but the class-colour
-- marking does, so it is tracked separately rather than folded into either.
local inArena = false
local demoUntil = 0
local lastVerdict, swingFlashUntil = nil, 0

-- Assigned much further down. A local declared after a closure that uses it
-- silently compiles to a global read (Harness/globals_lint.lua is the net),
-- and the tab buttons are built long before the redraw they trigger exists.
local Tick

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local function DB() return CommanderOracleDB end

local function Color(faction)
    return FACTION_COLORS[faction] or FACTION_COLORS.NEUTRAL
end

local function Tint(fontString, faction)
    local c = Color(faction)
    fontString:SetTextColor(c.r, c.g, c.b)
end

-- ---------------------------------------------------------------------------
-- Combat, and what it takes away
--
-- The roster rows are secure buttons (see the note on them below), and the
-- protection walks UP the frame tree: once the board carries one, anchoring a
-- section, resizing the board, showing or hiding anything, and re-binding a
-- row are all refused for as long as you are in combat.
--
-- So every structural call in this file goes through these. They are no-ops
-- rather than errors while the board is frozen, and the render pass paints
-- through them regardless -- textures and fontstrings are never protected, so
-- what the board SAYS stays live even while its shape is held.
-- ---------------------------------------------------------------------------

local function InCombat()
    return InCombatLockdown and InCombatLockdown() and true or false
end

local function Frozen(f)
    return InCombat() and f.IsProtected and f:IsProtected()
end

local function SafeShown(f, want)
    want = want and true or false
    if (f:IsShown() and true or false) == want then return true end
    if Frozen(f) then return false end
    f:SetShown(want)
    return true
end

local function SafeHeight(f, height)
    if Frozen(f) then return false end
    f:SetHeight(height)
    return true
end

local function SafePoint(f, point, rel, relPoint, x, y)
    if Frozen(f) then return false end
    f:ClearAllPoints()
    f:SetPoint(point, rel, relPoint, x, y)
    return true
end

local function SafeAttribute(f, key, value)
    if InCombat() then return false end
    f:SetAttribute(key, value)
    return true
end

local function FactionName(faction)
    if faction == "ALLIANCE" then return "Alliance" end
    if faction == "HORDE" then return "Horde" end
    return "Neutral"
end

-- ---------------------------------------------------------------------------
-- Where we are
-- ---------------------------------------------------------------------------

local function InArathiBasin()
    if GetInstanceInfo then
        local _, instanceType, _, _, _, _, _, instanceMapID = GetInstanceInfo()
        if instanceType == "pvp" and instanceMapID == AB.instanceMapID then
            return true
        end
    end
    -- The map is the fallback, not the primary: on a loading screen
    -- GetInstanceInfo settles before the map does.
    if C_Map and C_Map.GetBestMapForUnit then
        return C_Map.GetBestMapForUnit("player") == AB.uiMapID
    end
    return false
end

-- ---------------------------------------------------------------------------
-- The flags
-- ---------------------------------------------------------------------------

-- Only one of a node's five POIs is live at a time, so whatever the map hands
-- back reads straight through the canon into a board state. No icon paths, no
-- localized text, nothing that a patch or a locale can move under us.
local function ReadBoard()
    local fresh = {}
    if not (C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIForMap) then return fresh end

    for _, poiID in ipairs(C_AreaPoiInfo.GetAreaPOIForMap(AB.uiMapID) or {}) do
        local entry = POI[poiID]
        if entry then
            fresh[entry.node.index] = {
                node = entry.node,
                state = entry.state,
                owner = entry.owner,
                assaulter = entry.assaulter,
            }
        end
    end
    return fresh
end

-- Flags take a full minute, and the minute is the whole tactical question:
-- a node three seconds from landing is not worth turning around for. We know
-- the exact clock whenever we SAW it start; walking in on one already ticking
-- leaves only an upper bound, and the board says which it is rather than
-- inventing a number.
local function TrackContested(fresh)
    local now = GetTime()
    for index, node in pairs(fresh) do
        local key = node.node.key
        if node.state == "CONTESTED" then
            local previous = board[index]
            if not contested[key] then
                contested[key] = {
                    since = now,
                    -- Exact only if we watched it change hands
                    exact = previous ~= nil and previous.state ~= "CONTESTED",
                    assaulter = node.assaulter,
                }
            elseif contested[key].assaulter ~= node.assaulter then
                -- Reclicked by the other side: a fresh minute, and we saw it
                contested[key] = { since = now, exact = true, assaulter = node.assaulter }
            end
        else
            contested[key] = nil
        end
    end
    -- A node that dropped off the map entirely stops ticking too
    for index, node in pairs(board) do
        if not fresh[index] then contested[node.node.key] = nil end
    end
end

-- Seconds left on a ticking flag, plus whether that number is exact.
local function CaptureRemaining(nodeKey)
    local entry = contested[nodeKey]
    if not entry then return nil end
    local left = AB.captureSeconds - (GetTime() - entry.since)
    if left < 0 then left = 0 end
    return left, entry.exact
end

-- ---------------------------------------------------------------------------
-- The resources
-- ---------------------------------------------------------------------------

-- Every widget the client is showing, so the probe and the reader agree on
-- what they are looking at.
local function EachWidget(callback)
    if not (C_UIWidgetManager and C_UIWidgetManager.GetAllWidgetsBySetID) then return end
    local setIDs = {}
    for _, getter in ipairs({ "GetTopCenterWidgetSetID", "GetBelowMinimapWidgetSetID", "GetObjectiveTrackerWidgetSetID" }) do
        local fn = C_UIWidgetManager[getter]
        if fn then
            local ok, setID = pcall(fn)
            if ok and setID then setIDs[#setIDs + 1] = setID end
        end
    end
    for _, setID in ipairs(setIDs) do
        local ok, widgets = pcall(C_UIWidgetManager.GetAllWidgetsBySetID, setID)
        if ok and widgets then
            for _, widget in ipairs(widgets) do
                callback(setID, widget)
            end
        end
    end
end

-- How this client actually reports Arathi Basin resources.
--
-- NOT a DoubleStatusBar, which is the retail shape and what this reached for
-- first: on the Anniversary client the score is Blizzard's old always-up text
-- rendered through the modern widget system, as TWO IconAndText widgets, one
-- per faction, each reading "Bases: 1  Resources: 20/2000". Verified in a live
-- Arathi Basin 2026-09-06 — the DoubleStatusBar read came back empty while
-- Blizzard's own display was showing exactly that text. The bar path is kept
-- below as a fallback in case another battleground or a later patch uses it.
--
-- Only the NUMBERS are parsed, never the words, so this survives any locale:
-- the score and cap are the pair around the slash, and the base count is the
-- number in front of them.
local function ParseResourceText(text)
    if type(text) ~= "string" then return nil end
    local score, max = text:match("(%d+)%s*/%s*(%d+)")
    if not score then return nil end
    local head = text:match("^(.-)%d+%s*/%s*%d+") or ""
    return tonumber(score), tonumber(max), tonumber(head:match("(%d+)") or "")
end

-- The widget carries the cap the SERVER is running, and every projection is
-- measured against it. 2000 is the TBC canon and what this will be in
-- practice, but a server that tuned it would otherwise make every number here
-- quietly wrong — so take the client's word over our table when it gives one.
local function AdoptCap(max)
    if type(max) == "number" and max >= 500 and max <= 5000 and max ~= AB.maxScore then
        AB.maxScore = max
    end
end

-- Both faction lines, in the order the client lists them — which is not yet
-- known to be Alliance first.
local function ReadResourceWidgets()
    local lines = {}
    EachWidget(function(_, widget)
        if widget.widgetType == ICON_AND_TEXT then
            local getter = C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo
            if not getter then return end
            local ok, info = pcall(getter, widget.widgetID)
            if ok and info then
                local score, max, bases = ParseResourceText(info.text)
                if score then
                    lines[#lines + 1] = {
                        score = score, max = max, bases = bases,
                        order = widget.orderIndex or #lines,
                    }
                end
            end
        elseif widget.widgetType == DOUBLE_STATUS_BAR and #lines == 0 then
            local getter = C_UIWidgetManager.GetDoubleStatusBarWidgetVisualizationInfo
            if not getter then return end
            local ok, info = pcall(getter, widget.widgetID)
            if ok and info and info.leftBarValue and info.rightBarValue then
                lines[1] = { score = info.leftBarValue, max = info.leftBarMax, order = 1 }
                lines[2] = { score = info.rightBarValue, max = info.rightBarMax, order = 2 }
            end
        end
    end)
    table.sort(lines, function(a, b) return (a.order or 0) < (b.order or 0) end)
    if lines[1] then AdoptCap(lines[1].max) end
    return lines
end

-- Which of the two lines is the Alliance.
--
-- Settled by arithmetic, never by reading a string. Each line states how many
-- bases its side holds, and the map already told us exactly how many bases
-- each faction holds — so whenever the two counts differ, matching them names
-- the sides with certainty. The answer is remembered, because the counts are
-- only equal for the odd moment and a resolution once made stays good.
local resolvedSwap = nil

local function ResolveSides(lines, allianceBases, hordeBases)
    local setting = DB().ScoreBars or "AUTO"
    if setting == "LEFT_ALLIANCE" then return lines[1].score, lines[2].score end
    if setting == "LEFT_HORDE" then return lines[2].score, lines[1].score end

    local first, second = lines[1], lines[2]
    if first.bases and second.bases and first.bases ~= second.bases then
        if first.bases == allianceBases and second.bases == hordeBases then
            resolvedSwap = false
        elseif first.bases == hordeBases and second.bases == allianceBases then
            resolvedSwap = true
        end
    end

    if resolvedSwap then return second.score, first.score end
    return first.score, second.score
end

-- ---------------------------------------------------------------------------
-- The snapshot the engine is asked about
-- ---------------------------------------------------------------------------

local function Snapshot()
    local counts = E.CountBases(board)
    local allianceScore, hordeScore = scores.alliance, scores.horde
    return {
        allianceScore = allianceScore or 0,
        hordeScore = hordeScore or 0,
        allianceBases = counts.ALLIANCE,
        hordeBases = counts.HORDE,
    }, counts, (allianceScore ~= nil and hordeScore ~= nil)
end

local function Poll()
    local fresh = ReadBoard()
    if next(fresh) then
        TrackContested(fresh)
        board = fresh
    end

    local counts = E.CountBases(board)
    local lines = ReadResourceWidgets()
    if lines[1] and lines[2] then
        local alliance, horde = ResolveSides(lines, counts.ALLIANCE, counts.HORDE)
        scores.alliance, scores.horde = alliance, horde
        scores.at = GetTime()
        scores.estimated = false
    elseif scores.alliance and scores.at then
        -- The widget went quiet. Rather than freeze a stale number on screen,
        -- carry both sides forward at the income the map says they have, and
        -- SAY that the figure is now ours rather than the server's.
        local elapsed = GetTime() - scores.at
        if elapsed > 3 then
            scores.alliance = math.min(AB.maxScore, scores.alliance + E.Rate(counts.ALLIANCE) * elapsed)
            scores.horde = math.min(AB.maxScore, scores.horde + E.Rate(counts.HORDE) * elapsed)
            scores.at = GetTime()
            scores.estimated = true
        end
    end
end

-- ---------------------------------------------------------------------------
-- The board on screen
--
-- Three densities over ONE set of frames. Full draws resource bars and a row
-- per rung of the ladder; Compact swaps the bars for their own numbers and
-- folds the ladder into a single strip; Minimal collapses the whole read onto
-- one line. Nothing is created twice — density only moves anchors, swaps font
-- objects and hides what it does not use, so switching is free and the export
-- the harness reads stays the same shape at every level.
-- ---------------------------------------------------------------------------

local frame = CreateFrame("Frame", "CommanderOracleFrame", UIParent)
frame:SetWidth(PANEL_WIDTH)
frame:SetHeight(120)
frame:SetFrameStrata("MEDIUM")
frame:Hide()

-- Section heights and gaps per density. The ladder's compact form is a header
-- plus one two-line strip; Minimal drops whole sections into the verdict line.
local DENSITY = {
    FULL    = { pad = 10, comms = 24, verdict = 44, race = 40, ladder = 16 + 6 * 17, nodes = 38, call = 32 },
    COMPACT = { pad = 7,  comms = 22, verdict = 24, race = 20, ladder = 14 + 30,     nodes = 34, call = 20 },
    MINIMAL = { pad = 5,  comms = 20, verdict = 24, race = 0,  ladder = 0,           nodes = 34, call = 20 },
}

local function DensityKey()
    local key = DB() and DB().Density
    return DENSITY[key] and key or "COMPACT"
end

local sections = {}

local function NewSection(height)
    local section = CreateFrame("Frame", nil, frame)
    section:SetWidth(PANEL_WIDTH)
    section:SetHeight(height)
    section.baseHeight = height
    sections[#sections + 1] = section
    return section
end

-- Every fontstring the board owns, so the no-backdrop treatment and the
-- per-density font swap can be applied in one pass rather than remembered at
-- forty call sites.
local allText = {}

local function NewText(parent, fontObject, justify)
    fontObject = fontObject or "GameFontHighlight"
    local text = parent:CreateFontString(nil, "OVERLAY", fontObject)
    text:SetJustifyH(justify or "LEFT")
    allText[#allText + 1] = { fs = text, object = fontObject }
    return text
end

-- Give a fontstring a different font object for the current density; the
-- treatment pass below puts the outline back on afterwards.
local function Restyle(fontString, fontObject)
    for _, entry in ipairs(allText) do
        if entry.fs == fontString then entry.object = fontObject end
    end
end

-- What makes "no background" actually usable.
--
-- With a backdrop behind it, plain text reads fine. Floating over the world it
-- does not: a white number on Arathi's snow is invisible at exactly the moment
-- you need it. An outline and a hard shadow cost nothing and make the board
-- legible on any ground, which is the difference between a clean option and an
-- unusable one. SetFont is given the fontstring's OWN file and size with only
-- the OUTLINE flag — the one flag string this client accepts (an invalid flag
-- hard-errors and takes the whole file with it), and it is pcall'd besides.
local function ApplyTextTreatment()
    local outline = DB() and DB().TextOutline
    for _, entry in ipairs(allText) do
        local fs = entry.fs
        fs:SetFontObject(entry.object)
        -- The shadow is not optional: it is what separates the text from the
        -- world when there is no panel behind it, and it costs no legibility
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
        if outline and fs.GetFont then
            local file, size = fs:GetFont()
            if file and size then
                pcall(fs.SetFont, fs, file, size, "OUTLINE")
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- The tabs
--
-- Oracle answers one question about the basin and a completely different one
-- about the forty people fighting over it, and they do not belong on the
-- screen at the same time: the projection is something you glance at
-- mid-fight, the roster is something you read. Tabs rather than more sections,
-- so the board stays the height of one answer.
--
-- BATTLE is the Arathi board and is only offered in Arathi. The roster tabs
-- need nothing but the battlefield scoreboard -- which every battleground has
-- -- so they are offered in all of them.
-- ---------------------------------------------------------------------------

local TAB_BATTLE, TAB_TOP, TAB_MINE, TAB_THEIRS = "BATTLE", "TOP", "MINE", "THEIRS"
local TAB_ORDER = { TAB_BATTLE, TAB_TOP, TAB_MINE, TAB_THEIRS }
local TAB_HEIGHT = 15
local TAB_GAP = 3
local NEUTRAL_TAB = { r = 0.86, g = 0.86, b = 0.86 }

-- Assigned once the things they drive exist, for the same scoping reason as
-- BuildComms/SendComms below.
local SelectTab, ActiveTab, TabFaction

local tabSection = NewSection(TAB_HEIGHT)
tabSection.buttons = {}

for _, key in ipairs(TAB_ORDER) do
    local button = CreateFrame("Button", nil, tabSection)
    button.key = key
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetTexture(WHITE)
    button.bg:SetAllPoints()
    -- Same hairline-under-the-label treatment as the comms buttons: the board
    -- has no chrome and tabs drawn as folders would be the loudest thing on it
    button.rule = button:CreateTexture(nil, "ARTWORK")
    button.rule:SetTexture(WHITE)
    button.rule:SetHeight(1)
    button.rule:SetPoint("BOTTOMLEFT")
    button.rule:SetPoint("BOTTOMRIGHT")
    button.label = NewText(button, "GameFontHighlightSmall", "CENTER")
    button.label:SetPoint("CENTER", button, "CENTER", 0, 1)
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", function(self)
        if SelectTab then SelectTab(self.key) end
    end)
    button:SetScript("OnEnter", function(self) self.hovered = true end)
    button:SetScript("OnLeave", function(self) self.hovered = false end)
    tabSection.buttons[#tabSection.buttons + 1] = button
end

-- Tabs share the width of whatever is actually offered, so dropping BATTLE
-- outside Arathi widens the other three rather than leaving a gap
local function LayoutTabs(keys)
    if Frozen(tabSection) then return end
    local shown = {}
    for _, key in ipairs(keys) do shown[key] = true end
    local width = math.floor((PANEL_WIDTH - (#keys - 1) * TAB_GAP) / math.max(#keys, 1))
    local slot = 0
    for _, button in ipairs(tabSection.buttons) do
        if shown[button.key] then
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", tabSection, "TOPLEFT", slot * (width + TAB_GAP), 0)
            button:SetSize(width, TAB_HEIGHT)
            button:Show()
            slot = slot + 1
        else
            button:Hide()
        end
    end
end

-- ---------------------------------------------------------------------------
-- The comms header
--
-- Oracle knows three things nobody else on the team can see, and a HUD that
-- keeps them to itself is half an addon. These are the buttons for saying
-- them.
--
-- Every send is a click. Oracle never speaks on its own and never batches --
-- an addon that talks in battleground chat unprompted is one people ask you to
-- uninstall -- and each button is throttled, greys out when it has nothing
-- true to say, and shows the EXACT line it will post in its tooltip before you
-- commit to it.
-- ---------------------------------------------------------------------------

-- Assigned further down, once the projection helpers they lean on exist. A
-- local declared after a closure that uses it silently compiles to a global,
-- so these are declared here on purpose (Harness/globals_lint.lua is the net).
local BuildComms, SendComms

local COMMS_BUTTONS = {
    { key = "CALL",   label = "CALL",   color = { r = 0.62, g = 0.72, b = 0.85 } },
    { key = "DEFEND", label = "DEFEND", color = { r = 1.00, g = 0.35, b = 0.30 } },
    { key = "TAKE",   label = "TAKE",   color = { r = 1.00, g = 0.85, b = 0.40 } },
}

local commsSection = NewSection(DENSITY.COMPACT.comms)
commsSection.buttons = {}

local COMMS_GAP = 4
local COMMS_WIDTH = math.floor((PANEL_WIDTH - (#COMMS_BUTTONS - 1) * COMMS_GAP) / #COMMS_BUTTONS)

for index, spec in ipairs(COMMS_BUTTONS) do
    local button = CreateFrame("Button", nil, commsSection)
    button:SetPoint("TOPLEFT", commsSection, "TOPLEFT", (index - 1) * (COMMS_WIDTH + COMMS_GAP), 0)
    button:SetSize(COMMS_WIDTH, DENSITY.COMPACT.comms - 1)
    button.spec = spec

    -- Flat tinted quads rather than Blizzard's panel art: the board's whole
    -- point is that it can sit on the screen with no chrome, and a stone
    -- button frame would be the loudest thing on it.
    -- A hairline under the label instead of a filled slab. Three saturated
    -- blocks across the top was the loudest thing on a board whose whole point
    -- is to sit quietly on the screen; the colour lives in the text now, and
    -- the fill only appears under the cursor so it still reads as a button.
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetTexture(WHITE)
    button.bg:SetAllPoints()

    button.rule = button:CreateTexture(nil, "ARTWORK")
    button.rule:SetTexture(WHITE)
    button.rule:SetHeight(1)
    button.rule:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    button.rule:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)

    button.label = NewText(button, "GameFontHighlight", "CENTER")
    button.label:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.label:SetText(spec.label)

    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", function(self)
        if SendComms then SendComms(self.spec.key) end
    end)
    button:SetScript("OnEnter", function(self) self.hovered = true end)
    button:SetScript("OnLeave", function(self) self.hovered = false end)

    -- The tooltip is the confirmation step: it is the line itself, verbatim,
    -- so nothing is ever posted to thirty nine other people unseen.
    Commander.UI.AttachTooltip(button, spec.label, function()
        local ready = BuildComms and BuildComms()
        local message = ready and ready[spec.key]
        if message then
            return "Post to battleground chat:\n\n" .. message
        end
        return "Nothing to say yet -- this button reports only when it has something true to add."
    end, "ANCHOR_BOTTOM")

    commsSection.buttons[index] = button
end

-- One rule under the whole header. Grouping the buttons costs a single pixel
-- and saves the eye from treating them as three more rows of content.
commsSection.divider = commsSection:CreateTexture(nil, "ARTWORK")
commsSection.divider:SetTexture(WHITE)
commsSection.divider:SetHeight(1)
commsSection.divider:SetVertexColor(1, 1, 1, 0.12)
commsSection.divider:SetPoint("BOTTOMLEFT", commsSection, "BOTTOMLEFT", 0, 0)
commsSection.divider:SetPoint("BOTTOMRIGHT", commsSection, "BOTTOMRIGHT", 0, 0)

-- A resource bar: track, fill, the server's own near-victory line at 1800,
-- and the numbers written over it. Full density only.
local function NewBar(parent, y)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    bar:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    bar:SetHeight(17)

    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetTexture(WHITE)
    bar.track:SetVertexColor(1, 1, 1, 0.10)
    bar.track:SetAllPoints()

    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetTexture(WHITE)
    bar.fill:SetPoint("TOPLEFT")
    bar.fill:SetPoint("BOTTOMLEFT")
    bar.fill:SetWidth(1)

    -- The 1800 line: crossing it is the server's own "near victory", and the
    -- point at which a single flag stops being a rotation and starts being
    -- the game.
    bar.warn = bar:CreateTexture(nil, "OVERLAY")
    bar.warn:SetTexture(WHITE)
    bar.warn:SetVertexColor(1, 0.9, 0.4, 0.55)
    bar.warn:SetWidth(1)
    bar.warn:SetPoint("TOP")
    bar.warn:SetPoint("BOTTOM")

    bar.label = NewText(bar, "GameFontHighlight", "LEFT")
    bar.label:SetPoint("LEFT", bar, "LEFT", 3, 0)
    bar.value = NewText(bar, "GameFontHighlight", "RIGHT")
    bar.value:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    return bar
end

local function SetBar(bar, faction, score, bases, showWarn)
    local color = Color(faction)
    local fraction = math.max(0, math.min(1, (score or 0) / AB.maxScore))
    bar.fill:SetWidth(math.max(1, PANEL_WIDTH * fraction))
    bar.fill:SetVertexColor(color.r, color.g, color.b, 0.55)
    bar.label:SetText(string.format("%s  %d", FactionName(faction), bases))
    Tint(bar.label, faction)
    bar.value:SetText(string.format("%d", math.floor((score or 0) + 0.5)))
    bar.warn:ClearAllPoints()
    bar.warn:SetPoint("TOP", bar, "TOPLEFT", PANEL_WIDTH * (AB.warnScore / AB.maxScore), 0)
    bar.warn:SetPoint("BOTTOM", bar, "BOTTOMLEFT", PANEL_WIDTH * (AB.warnScore / AB.maxScore), 0)
    bar.warn:SetShown(showWarn and true or false)
end

-- The verdict: who wins from here, by how much, and how long that takes.
local verdictSection = NewSection(DENSITY.COMPACT.verdict)
verdictSection.headline = NewText(verdictSection, "GameFontNormal", "LEFT")
verdictSection.detail = NewText(verdictSection, "GameFontHighlight", "LEFT")
-- The swing alert as a pulsing rule in the left margin. As a full-width wash
-- over the verdict it was the loudest thing the board ever did, for three
-- seconds, at the exact moment you most need to read the verdict under it.
verdictSection.flash = verdictSection:CreateTexture(nil, "OVERLAY")
verdictSection.flash:SetTexture(WHITE)
verdictSection.flash:SetWidth(3)
verdictSection.flash:SetPoint("TOPRIGHT", verdictSection, "TOPLEFT", -5, 0)
verdictSection.flash:SetPoint("BOTTOMRIGHT", verdictSection, "BOTTOMLEFT", -5, 0)
verdictSection.flash:Hide()

-- The race. Full draws it as two bars; the denser levels write the same four
-- numbers as text, which is all the bars were ever carrying.
local raceSection = NewSection(DENSITY.COMPACT.race)
raceSection.top = NewBar(raceSection, -1)
raceSection.bottom = NewBar(raceSection, -21)
raceSection.mine = NewText(raceSection, "GameFontHighlightSmall", "LEFT")
raceSection.mine:SetPoint("LEFT", raceSection, "LEFT", 0, 0)
raceSection.theirs = NewText(raceSection, "GameFontHighlightSmall", "RIGHT")
raceSection.theirs:SetPoint("RIGHT", raceSection, "RIGHT", 0, 0)

-- The ladder: what each possible hold is worth from the present score.
--
-- Every row assumes the enemy takes every base we do not hold, so a row is a
-- GUARANTEE rather than a forecast — "hold three and you win even if they own
-- the other two". That is why the headline verdict and the ladder can
-- disagree: the verdict reads the board as it actually stands (a neutral or
-- ticking node pays nobody), the ladder prices the worst case. The header says
-- so on screen at every density, because a number whose assumption is
-- invisible is a trap.
local ladderSection = NewSection(DENSITY.COMPACT.ladder)
ladderSection.header = NewText(ladderSection, "GameFontHighlightSmall", "LEFT")
ladderSection.header:SetPoint("TOPLEFT", ladderSection, "TOPLEFT", 0, 0)

ladderSection.rows = {}
for index = 1, 6 do
    local row = CreateFrame("Frame", nil, ladderSection)
    row:SetHeight(17)
    row:SetPoint("TOPLEFT", ladderSection, "TOPLEFT", 0, -(16 + (index - 1) * 17))
    row:SetPoint("RIGHT", ladderSection, "RIGHT", 0, 0)

    -- A drawn wedge rather than a glyph: this client's condensed font renders
    -- shape characters as missing-glyph boxes, and a tinted quad cannot be
    -- moved by a patch.
    row.marker = row:CreateTexture(nil, "OVERLAY")
    row.marker:SetTexture(WHITE)
    row.marker:SetSize(3, 12)
    row.marker:SetPoint("LEFT", row, "LEFT", 0, 0)

    row.bases = NewText(row, "GameFontHighlightSmall", "LEFT")
    row.bases:SetPoint("LEFT", row, "LEFT", 9, 0)
    row.outcome = NewText(row, "GameFontHighlightSmall", "LEFT")
    row.outcome:SetPoint("LEFT", row, "LEFT", 56, 0)
    row.time = NewText(row, "GameFontHighlightSmall", "RIGHT")
    row.time:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    ladderSection.rows[index] = row
end

-- The compact ladder: the same five rungs as a strip, hold over margin. Five
-- cells rather than six — a row for holding nothing is never a decision.
--
-- The strip carries a label column, which the roomy version does not need
-- because its rows spell themselves out ("3  win by 383"). Stripped to bare
-- digits, two stacked rows of numbers say nothing at all about which is which
-- — a reader who does not already know the feature cannot recover it from the
-- screen, and a number nobody can read is not a compact one, it is a wasted
-- one.
local LADDER_CELLS = 5
local LADDER_LABEL = 26
local CELL_WIDTH = math.floor(
    (PANEL_WIDTH - LADDER_LABEL - (LADDER_CELLS - 1) * 2) / LADDER_CELLS)
ladderSection.cells = {}
for index = 1, LADDER_CELLS do
    local cell = CreateFrame("Frame", nil, ladderSection)
    cell:SetSize(CELL_WIDTH, 30)
    cell:SetPoint("TOPLEFT", ladderSection, "TOPLEFT",
        LADDER_LABEL + (index - 1) * (CELL_WIDTH + 2), -14)

    cell.marker = cell:CreateTexture(nil, "BACKGROUND")
    cell.marker:SetTexture(WHITE)
    cell.marker:SetAllPoints()

    cell.bases = NewText(cell, "GameFontHighlightSmall", "CENTER")
    cell.bases:SetPoint("TOP", cell, "TOP", 0, -1)
    cell.bases:SetWidth(CELL_WIDTH)
    cell.margin = NewText(cell, "GameFontHighlight", "CENTER")
    cell.margin:SetPoint("TOP", cell.bases, "BOTTOM", 0, -1)
    cell.margin:SetWidth(CELL_WIDTH)
    ladderSection.cells[index] = cell
end

-- Anchored to the first cell's own two lines rather than to a guessed offset,
-- so the labels sit on exactly the rows they name whatever the fonts do.
ladderSection.axisHold = NewText(ladderSection, "GameFontDisableSmall", "RIGHT")
ladderSection.axisHold:SetPoint("RIGHT", ladderSection.cells[1].bases, "LEFT", -4, 0)
ladderSection.axisHold:SetWidth(LADDER_LABEL - 4)
ladderSection.axisHold:SetText("hold")
ladderSection.axisEnds = NewText(ladderSection, "GameFontDisableSmall", "RIGHT")
ladderSection.axisEnds:SetPoint("RIGHT", ladderSection.cells[1].margin, "LEFT", -4, 0)
ladderSection.axisEnds:SetWidth(LADDER_LABEL - 4)
ladderSection.axisEnds:SetText("ends")

-- The whole feature in a paragraph, for the reader who has just met a grid of
-- signed numbers and has no idea what question they answer.
if ladderSection.EnableMouseMotion then
    pcall(ladderSection.EnableMouseMotion, ladderSection, true)
elseif ladderSection.EnableMouse then
    ladderSection:EnableMouse(true)
end
Commander.UI.AttachTooltip(ladderSection, "Win-condition ladder", function()
    return "Every rung asks one question: if you hold that many bases and they"
        .. " take every other one, how does the race to " .. AB.maxScore .. " end?\n\n"
        .. "So the number under a hold is the margin you FINISH on -- green you"
        .. " win by it, red you lose by it. The rung you are standing on is lit.\n\n"
        .. "It is a guarantee rather than a forecast: \"hold three and you win"
        .. " even if they own the other two\". That is why it can disagree with"
        .. " the verdict above -- the verdict reads the board as it actually"
        .. " stands, where a flag still ticking pays nobody, and the ladder"
        .. " prices the worst case."
end, "ANCHOR_LEFT")

-- The five flags
local nodeSection = NewSection(DENSITY.COMPACT.nodes)
nodeSection.pips = {}
local PIP_WIDTH = math.floor((PANEL_WIDTH - 4 * 3) / 5)
for index = 1, 5 do
    local pip = CreateFrame("Frame", nil, nodeSection)
    pip:SetSize(PIP_WIDTH, 30)
    pip:SetPoint("TOPLEFT", nodeSection, "TOPLEFT", (index - 1) * (PIP_WIDTH + 3), 0)

    pip.name = NewText(pip, "GameFontHighlight", "CENTER")
    pip.name:SetPoint("TOP", pip, "TOP", 0, 0)
    pip.name:SetWidth(PIP_WIDTH)

    -- Ownership as a rule UNDER the name rather than a colour block behind it.
    -- Text sitting on a tinted quad is the single messiest thing the old board
    -- did: it fought its own background for contrast five times over, and the
    -- colour carries just as well as a 3px underline.
    pip.swatch = pip:CreateTexture(nil, "ARTWORK")
    pip.swatch:SetTexture(WHITE)
    pip.swatch:SetPoint("TOPLEFT", pip, "TOPLEFT", 0, -16)
    pip.swatch:SetPoint("TOPRIGHT", pip, "TOPRIGHT", 0, -16)
    pip.swatch:SetHeight(3)

    pip.timer = NewText(pip, "GameFontHighlightSmall", "CENTER")
    pip.timer:SetPoint("TOP", pip.swatch, "BOTTOM", 0, -2)
    pip.timer:SetWidth(PIP_WIDTH)
    nodeSection.pips[index] = pip
end

-- The call
local callSection = NewSection(DENSITY.COMPACT.call)
callSection.text = NewText(callSection, "GameFontHighlight", "LEFT")
callSection.text:SetPoint("TOPLEFT", callSection, "TOPLEFT", 0, 0)
callSection.text:SetPoint("RIGHT", callSection, "RIGHT", 0, 0)

-- ---------------------------------------------------------------------------
-- The roster
--
-- These two views read the BATTLEFIELD SCOREBOARD -- the server's own numbers
-- for all forty players -- rather than the combat log, which only ever saw the
-- hundred yards around you. That is the whole reason the enemy side can be
-- ranked at all.
--
-- The arithmetic is not in this file. CommanderOracleRoster.lua scores and
-- ranks with no client API at all, the same split the projection engine uses,
-- so the harness can hold the score to account without a battleground.
-- ---------------------------------------------------------------------------

local ROW_HEIGHT = 13
local GROUP_HEADER = 14
local MAX_TOP_ROWS = 5
local MAX_GROUPS = 6
local MAX_GROUP_ROWS = 5
local SCORE_REQUEST_INTERVAL = 3
local SCORE_STALE_AFTER = 15

local roster = {
    report = nil,       -- the ranked read, rebuilt only when new scores land
    at = nil,           -- when the client last handed us a scoreboard
    requestedAt = 0,
    asked = false,
    demo = false,
}

-- Assigned with the raid markers further down: leaving a battleground drops
-- the roster, and the icons we put on people have to go with it. Declared here
-- because a local declared after its use compiles to a global read that is
-- always nil -- which would have meant marks that never came off.
local ClearOurMarks

local function ResetRoster()
    if ClearOurMarks then ClearOurMarks() end
    roster.report, roster.at = nil, nil
    roster.requestedAt, roster.asked, roster.demo = 0, false, false
end

local function TopCount()
    local count = math.floor(tonumber(DB() and DB().TopCount) or 3)
    if count < 1 then count = 1 end
    if count > MAX_TOP_ROWS then count = MAX_TOP_ROWS end
    return count
end

-- The scoreboard is a server round trip: ask, then read what comes back on
-- UPDATE_BATTLEFIELD_SCORE. Asking is throttled AND only happens while a
-- roster tab is actually on screen -- there is no reason to poll the server on
-- behalf of a view nobody is looking at.
local function RequestScores(force)
    if not RequestBattlefieldScoreData then return end
    local now = GetTime()
    if not inBattleground and not force then return end
    if not force and (now - roster.requestedAt) < SCORE_REQUEST_INTERVAL then return end
    roster.requestedAt = now
    roster.asked = true
    RequestBattlefieldScoreData()
end

local function ReadScoreboard()
    if not (RS and GetNumBattlefieldScores and GetBattlefieldScore) then return end
    local count = GetNumBattlefieldScores() or 0
    if count <= 0 then return end

    -- The objective columns belong to the map, not to us: bases in Arathi,
    -- flags in Warsong, five separate ones in Alterac. Read the client's own
    -- labels rather than shipping a table a new battleground would falsify.
    local columns = {}
    if GetNumBattlefieldStats and GetBattlefieldStatInfo then
        for index = 1, (GetNumBattlefieldStats() or 0) do
            local label = GetBattlefieldStatInfo(index)
            columns[index] = (label and label ~= "" and label) or ("Objective " .. index)
        end
    end

    local players = {}
    for index = 1, count do
        local name, killingBlows, honorableKills, deaths, honorGained, faction,
            _, _, _, classToken, damageDone, healingDone = GetBattlefieldScore(index)
        -- faction 0 is Horde and 1 is Alliance here -- the order Blizzard's own
        -- TBC WorldStateFrame counts the sides in
        local side = faction == 1 and "ALLIANCE" or (faction == 0 and "HORDE" or nil)
        if name and side then
            local objectives = {}
            if GetBattlefieldStatData then
                for column = 1, #columns do
                    objectives[column] = GetBattlefieldStatData(index, column) or 0
                end
            end
            players[#players + 1] = {
                -- Cross-realm rows arrive as "Name-Realm", and the realm is
                -- never the part you are looking for at a glance
                name = name:match("^([^%-]+)") or name,
                faction = side,
                classToken = classToken,
                killingBlows = killingBlows,
                honorableKills = honorableKills,
                deaths = deaths,
                honor = honorGained,
                damage = damageDone,
                healing = healingDone,
                objectives = objectives,
            }
        end
    end
    if #players == 0 then return end

    local runTime = 0
    if GetBattlefieldInstanceRunTime then
        runTime = (GetBattlefieldInstanceRunTime() or 0) / 1000
    end

    roster.report = RS.Rank(players, {
        myFaction = myFaction,
        topCount = TopCount(),
        columns = columns,
        runTime = runTime,
    })
    roster.at = GetTime()
    roster.demo = false
end

-- ---------------------------------------------------------------------------
-- Who the client will actually point at
--
-- A battleground hands out unit tokens for your own raid and for nothing else.
-- The enemy side has no tokens at all: everything you can learn about where
-- one of them is comes from a token you happen to be holding at that moment --
-- your target, your focus, whatever the mouse is over, whatever the client has
-- spawned a nameplate for. So the registry is REBUILT from what is available
-- rather than remembered, and a name that is not in it has no range. It does
-- not get a guess.
-- ---------------------------------------------------------------------------

local UNIT_REFRESH = 0.4

local ALLY_TOKENS = { "player" }
for index = 1, 4 do ALLY_TOKENS[#ALLY_TOKENS + 1] = "party" .. index end
for index = 1, 40 do ALLY_TOKENS[#ALLY_TOKENS + 1] = "raid" .. index end

-- The only four ways an enemy ever gets a token
local LOOSE_TOKENS = { "target", "focus", "mouseover" }

local nameplateUnits = {}     -- token -> true, kept by NAME_PLATE_UNIT_ADDED
local unitByName = {}
local unitsAt = 0

local function RememberUnit(token)
    if not (token and UnitName and UnitExists and UnitExists(token)) then return end
    local name, realm = UnitName(token)
    if not name then return end
    unitByName[name:lower()] = token
    if realm and realm ~= "" then
        unitByName[(name .. "-" .. realm):lower()] = token
    end
end

local function RefreshUnits(force)
    if not force and (GetTime() - unitsAt) < UNIT_REFRESH then return end
    unitsAt = GetTime()
    for key in pairs(unitByName) do unitByName[key] = nil end
    for _, token in ipairs(ALLY_TOKENS) do RememberUnit(token) end
    for _, token in ipairs(LOOSE_TOKENS) do RememberUnit(token) end
    for token in pairs(nameplateUnits) do RememberUnit(token) end
end

local function TokenFor(entry)
    if not entry then return nil end
    local token = entry.fullName and unitByName[entry.fullName:lower()]
    if not token and entry.name then token = unitByName[entry.name:lower()] end
    return token
end

-- The range shapes are documented in CommanderOracleRoster.lua. Short version:
-- measured for your own raid, an upper bound for anyone else we hold a unit
-- for, nothing at all for the rest -- which in a battleground is most of the
-- enemy team, most of the time.
local function RangeFor(entry)
    local token = TokenFor(entry)
    if not token then return nil end
    if UnitIsUnit and UnitIsUnit(token, "player") then return { yards = 0 } end

    -- Real coordinates, which the client gives out for the raid you are in and
    -- for nobody else. UnitPosition returns y BEFORE x -- the distance does not
    -- care, but the next person to read this does.
    if UnitPosition then
        local myY, myX, _, myInstance = UnitPosition("player")
        local theirY, theirX, _, theirInstance = UnitPosition(token)
        if myX and theirX and myInstance == theirInstance then
            return { yards = RS.Distance(myX, myY, theirX, theirY) }
        end
    end

    -- There used to be an interaction-band ladder here, over
    -- CheckInteractDistance, to put an upper bound on an enemy we cannot
    -- measure. That function is PROTECTED on this client (2.5.6): the call is
    -- blocked and returns nothing, so the ladder never produced a bound -- it
    -- only raised ADDON_ACTION_BLOCKED, ten times a refresh, from inside a
    -- pcall that could not catch it (a taint block is a client event, not a
    -- Lua error, so pcall is no defence at all).
    --
    -- R.RangeText and R.RangeColor still understand { within = n }; nothing
    -- produces one today. A future unprotected range source can fill it back
    -- in. Do not fill it back in with this one.
    -- We are holding a unit for them and the client will not price it. That is
    -- still worth saying: it means they are on screen.
    return { seen = true }
end

-- ---------------------------------------------------------------------------
-- Raid markers
--
-- The one thing this addon does that lands on thirty-nine other people's
-- screens, so it is off until you switch it on and gated three ways: only in a
-- battleground, only while you actually hold the lead or an assist (the server
-- refuses otherwise), and only on your OWN side -- which is also the only side
-- the client hands out unit tokens for, so for once the request and the
-- constraint agree.
--
-- Two rules keep it from being a nuisance:
--
--   Marks are STICKY. A player keeps the icon they were given until they fall
--   well out of the top, not the instant two people swap places on the third
--   decimal. Re-marking the raid every three seconds would be worse than not
--   marking it at all.
--
--   We only ever clear a mark we placed, and we never take one that is already
--   somebody else's. A star we did not set is not ours to remove, and an addon
--   that fights the raid leader over an icon gets uninstalled.
-- ---------------------------------------------------------------------------

local MARK_INTERVAL = 1.0
local MAX_MARKS = 8
-- How far past the cut a marked player has to fall before losing the icon
local MARK_GRACE = 2

local marks = {}            -- name -> the mark index WE set on them
local markedAt = 0

local ARENA_TEAM = { "player", "party1", "party2", "party3", "party4" }

local function MarkCount()
    local count = math.floor(tonumber(DB() and DB().MarkCount) or 3)
    if count < 1 then count = 1 end
    if count > MAX_MARKS then count = MAX_MARKS end
    return count
end

-- Which kind of marking this place calls for, or nil for none. Two modes,
-- because the two places have nothing in common: a battleground team is forty
-- strangers ranked by what they have done, an arena team is four people you
-- came with, and the only thing worth saying about them is who is who.
local function MarkingMode()
    local db = DB()
    if not (db and db.EnableOracle) then return nil end
    if not (SetRaidTarget and GetRaidTargetIndex) then return nil end
    -- The server refuses a marker from anyone else, so asking first saves a
    -- pass of pointless calls rather than a pass of errors
    local leader = UnitIsGroupLeader and UnitIsGroupLeader("player")
    local assistant = UnitIsGroupAssistant and UnitIsGroupAssistant("player")
    if not (leader or assistant) then return nil end
    if inArena then
        return db.MarkArenaTeam and "ARENA" or nil
    end
    if inBattleground then
        return db.MarkTop and "TOP" or nil
    end
    return nil
end

local function TokenForName(name)
    return name and unitByName[name:lower()] or nil
end

-- Ours to clear only while it is still ours: if the icon on them has changed,
-- somebody else has taken that player over and we let go of them instead.
local function ReleaseMark(name)
    local index = marks[name]
    marks[name] = nil
    if not index then return end
    local token = TokenForName(name)
    if token and (GetRaidTargetIndex(token) or 0) == index then
        SetRaidTarget(token, 0)
    end
end

ClearOurMarks = function()
    for name in pairs(marks) do ReleaseMark(name) end
end

-- The one place a mark is ever written, so the three rules hold for both
-- modes: only onto an empty slot, only re-placed if OURS was cleared, and
-- never over an icon somebody else put there.
local function PlaceMark(name, index)
    local token = TokenForName(name)
    if not token then return false end
    if CanBeRaidTarget and not CanBeRaidTarget(token) then return false end
    local current = GetRaidTargetIndex(token) or 0
    if marks[name] == index then
        if current == 0 then SetRaidTarget(token, index) end
        return true
    end
    if current ~= 0 then return false end
    marks[name] = index
    SetRaidTarget(token, index)
    return true
end

-- Arena: the team is five people at most and a class never changes, so there
-- is nothing to be sticky about -- the same team always resolves to the same
-- icons, and the only churn is somebody joining or leaving.
-- `UnitClass and UnitClass(unit)` does NOT do what it looks like: `and` yields
-- a single value, so the call is truncated to its first return and the class
-- token -- which is the second -- comes back nil. Written that way this marked
-- nobody at all, silently, because a team with no classes has no assignment.
local function ClassOf(unit)
    if not UnitClass then return nil end
    local _, class = UnitClass(unit)
    return class
end

local function UpdateArenaMarks()
    local classes, names = {}, {}
    for _, unit in ipairs(ARENA_TEAM) do
        if UnitExists and UnitExists(unit) and UnitName then
            local name = UnitName(unit)
            if name then
                names[#names + 1] = name
                classes[#classes + 1] = ClassOf(unit)
            end
        end
    end

    local assigned = RS and RS.AssignMarks(classes) or {}
    local wanted = {}
    for slot, index in pairs(assigned) do
        if names[slot] then wanted[names[slot]] = index end
    end

    for name in pairs(marks) do
        if not wanted[name] then ReleaseMark(name) end
    end
    for name, index in pairs(wanted) do
        PlaceMark(name, index)
    end
end

local function UpdateMarks()
    local mode = MarkingMode()
    if not mode then
        if next(marks) then ClearOurMarks() end
        return
    end
    if (GetTime() - markedAt) < MARK_INTERVAL then return end
    markedAt = GetTime()

    if mode == "ARENA" then
        UpdateArenaMarks()
        return
    end

    local report = roster.report
    local group = report and report.ready and myFaction and report.factions[myFaction]
    if not group then return end

    local count = MarkCount()

    -- Where everybody stands, so the sticky rule has something to measure
    local rank = {}
    for index, entry in ipairs(group.players) do rank[entry.name] = index end

    -- Anyone who has fallen well past the cut (or off the scoreboard) gives
    -- their icon back
    for name in pairs(marks) do
        local place = rank[name]
        if not place or place > count + MARK_GRACE then
            ReleaseMark(name)
        end
    end

    local used = {}
    for _, index in pairs(marks) do used[index] = true end

    for place = 1, count do
        local entry = group.players[place]
        if entry then
            local index = marks[entry.name]
            if index then
                PlaceMark(entry.name, index)
            else
                for candidate = 1, count do
                    if not used[candidate] then
                        if PlaceMark(entry.name, candidate) then
                            used[candidate] = true
                        end
                        break
                    end
                end
            end
        end
    end
end

-- The icon a player is actually carrying, whoever put it there. Read rather
-- than remembered, so the board shows the raid's real marks and not just ours.
local function RaidMarkFor(entry)
    if not (entry and GetRaidTargetIndex) then return nil end
    local token = TokenForName(entry.name)
    if not token then return nil end
    local index = GetRaidTargetIndex(token)
    if index and index >= 1 and index <= MAX_MARKS then return index end
    return nil
end

-- The eight icons live in one 4x2 sheet
local function RaidMarkCoords(index)
    local column = (index - 1) % 4
    local row = math.floor((index - 1) / 4)
    return column * 0.25, (column + 1) * 0.25, row * 0.25, (row + 1) * 0.25
end

local function ShowRange()
    local db = DB()
    return not db or db.ShowDistance ~= false
end

-- A row keeps the player's NAME, never the scored entry: rankings are rebuilt
-- from scratch and a kept reference is a number that quietly stops moving.
local function RowEntry(row)
    local report = roster.report
    if row.player and report and report.byName then
        local live = report.byName[row.player]
        if live then return live end
    end
    return row.entry
end

-- How old the numbers on screen are. The scoreboard is a round trip and the
-- server can simply stop answering; a board that keeps drawing a frozen
-- ranking without saying so is lying quietly.
local function RosterAge()
    if not roster.at then return nil end
    return GetTime() - roster.at
end

local function StaleSuffix()
    local age = RosterAge()
    if roster.demo or not age or age <= SCORE_STALE_AFTER then return "" end
    return string.format("  %ds old", math.floor(age))
end

local function ClassTint(fontString, entry)
    local info = entry.classToken and Commander.GetClassInfo
        and Commander.GetClassInfo(entry.classToken)
    local color = info and info.color
    if color then
        fontString:SetTextColor(color[1], color[2], color[3])
    else
        fontString:SetTextColor(0.92, 0.92, 0.92)
    end
end

-- Impact is a share of the best in THIS match, so the bands are about how
-- close to the top of the board somebody is, not about an absolute
local function ImpactColor(impact)
    if impact >= 70 then return 1.00, 0.85, 0.40 end
    if impact >= 40 then return 0.92, 0.92, 0.92 end
    return 0.62, 0.62, 0.62
end

-- ---------------------------------------------------------------------------
-- Clickable rows
--
-- Left-click targets the player on the row, right-click focuses them. Both are
-- PROTECTED actions -- the only route an addon has is a secure button carrying
-- `/targetexact <name>` and `/focus <name>` -- and that buys one hard rule:
--
--   a secure button cannot be re-bound, moved, shown or hidden in combat.
--
-- So the row's STRUCTURE (which player is on it, where it sits, whether it is
-- shown) is settled out of combat and holds while you fight, and the row's
-- PAINT (name, score, range, highlight) is written on every frame either way
-- -- textures and fontstrings are never protected. That split is the whole
-- design: what you are reading is always live, and what you are clicking can
-- never disagree with what you are reading, because the name is painted from
-- the same assignment that set the macro.
--
-- The protection walks UP the frame tree, so the board itself is protected
-- once it carries these. Every layout call in this file goes through the Safe*
-- wrappers below for that reason.
-- ---------------------------------------------------------------------------

local function NewRosterRow(parent, withReason)
    local row = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    row:SetHeight(ROW_HEIGHT)
    row:SetWidth(PANEL_WIDTH)
    row:RegisterForClicks("AnyUp")
    row:SetAttribute("type1", "macro")
    row:SetAttribute("type2", "macro")
    row:SetScript("OnEnter", function(self) self.hovered = true end)
    row:SetScript("OnLeave", function(self) self.hovered = false end)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetTexture(WHITE)
    row.bg:SetAllPoints()
    row.bg:SetVertexColor(1, 1, 1, 0)

    row.rank = NewText(row, "GameFontDisableSmall", "RIGHT")
    row.rank:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.rank:SetWidth(10)
    -- A raid marker takes the rank slot: a player carrying an icon does not
    -- also need to be told they are third
    row.mark = row:CreateTexture(nil, "OVERLAY")
    row.mark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    row.mark:SetSize(11, 11)
    row.mark:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.mark:Hide()
    row.name = NewText(row, "GameFontHighlightSmall", "LEFT")
    row.name:SetPoint("LEFT", row, "LEFT", 14, 0)
    row.name:SetWordWrap(false)
    row.range = NewText(row, "GameFontDisableSmall", "RIGHT")
    row.range:SetWidth(32)
    row.range:SetWordWrap(false)
    row.value = NewText(row, "GameFontNormalSmall", "RIGHT")
    if withReason then
        row.reason = NewText(row, "GameFontDisableSmall", "RIGHT")
        row.reason:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.reason:SetWidth(46)
        row.reason:SetWordWrap(false)
        row.value:SetPoint("RIGHT", row, "RIGHT", -50, 0)
        row.value:SetWidth(24)
        row.range:SetPoint("RIGHT", row, "RIGHT", -78, 0)
        -- Two name widths, because the range column is a setting and a short
        -- name column with nothing next to it just looks broken
        row.nameWide = PANEL_WIDTH - 14 - 50 - 24 - 4
        row.nameNarrow = row.nameWide - 34
    else
        row.value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.value:SetWidth(58)
        row.range:SetPoint("RIGHT", row, "RIGHT", -62, 0)
        row.nameWide = PANEL_WIDTH - 14 - 58 - 4
        row.nameNarrow = row.nameWide - 34
    end
    row.name:SetWidth(row.nameWide)
    return row
end

-- Structure. Refuses in combat rather than half-applying: a row whose macro
-- did not take must not be relabelled either, or it targets somebody other
-- than the name printed on it.
local function BindRow(row, entry)
    if row.player == (entry and entry.name) then return true end
    if InCombat() then return false end
    row.player = entry and entry.name or nil
    if entry then
        -- The scoreboard's own spelling, realm stripped: /targetexact matches
        -- on the plain name
        SafeAttribute(row, "macrotext1", "/targetexact " .. entry.name)
        SafeAttribute(row, "macrotext2", "/focus " .. entry.name)
    else
        SafeAttribute(row, "macrotext1", "")
        SafeAttribute(row, "macrotext2", "")
    end
    return true
end

-- Read back off the game rather than remembered from the click: your target
-- changes for a hundred reasons that are not this list.
local function PaintRowMark(row, entry)
    local index = entry and RaidMarkFor(entry)
    if index then
        row.mark:SetTexCoord(RaidMarkCoords(index))
        row.mark:Show()
        row.rank:Hide()
    else
        row.mark:Hide()
        row.rank:Show()
    end
end

local function PaintRowHighlight(row)
    local name = row.player
    local red, green, blue, alpha = 1, 1, 1, 0
    if name and UnitName then
        if UnitName("target") == name then
            red, green, blue, alpha = 1, 0.85, 0.40, 0.22
        elseif UnitName("focus") == name then
            red, green, blue, alpha = 0.55, 0.78, 1, 0.18
        end
    end
    if alpha == 0 and row.hovered then alpha = 0.12 end
    row.bg:SetVertexColor(red, green, blue, alpha)
end

-- One place that fills the range cell, so the two views can never disagree
-- about what the client said
local function SetRowRange(row, entry)
    local wanted = ShowRange()
    row.name:SetWidth(wanted and row.nameNarrow or row.nameWide)
    row.range:SetShown(wanted)
    if not wanted then return end
    local range = RangeFor(entry)
    row.range:SetText(RS.RangeText(range))
    row.range:SetTextColor(RS.RangeColor(range))
end

-- The whole score, in the one place there is room to show its working. A
-- number whose parts are invisible is the same trap the ladder header warns
-- about, and Impact has four of them.
local function AttachImpactTooltip(row)
    Commander.UI.AttachTooltip(row, "Impact", function()
        local entry = RowEntry(row)
        if not entry then return nil end
        local report = roster.report
        local weights = report and report.weights or {}
        local lines = {
            entry.name .. "  --  " .. tostring(entry.impact) .. " impact",
            "",
        }
        local columns = (report and report.columns) or {}
        -- The crunch: share of the best, what it is worth, and the raw figure
        -- with its rate beside it -- the way a post-game screen reads.
        local function Part(label, share, weight, detail)
            if not weight or weight <= 0 then return end
            lines[#lines + 1] = string.format("%-9s %3d%%  x%.2f   %s", label,
                math.floor((share or 0) * 100 + 0.5), weight, detail or "")
        end

        local outputDetail = RS.Short(entry.currency or 0)
        if entry.rates and entry.rates.output then
            outputDetail = outputDetail .. "  " .. entry.rates.output
        end
        Part(entry.outputKey == "healing" and "Healing" or "Damage",
            entry.shares.output, weights.output, outputDetail)

        Part("Trade", entry.shares.trade, weights.trade, string.format(
            "%s per life  %d lost", RS.Short(entry.perLife or 0), math.floor(entry.deaths)))

        local killDetail = string.format("%d", math.floor(entry.killingBlows))
        if entry.rates and entry.rates.kills then
            killDetail = killDetail .. "  " .. entry.rates.kills
        end
        Part("Kills", entry.shares.kills, weights.kills, killDetail)

        Part((columns[1] and columns[1]:match("^(%a+)")) or "Bases",
            entry.shares.objectives, weights.objectives,
            string.format("%d", math.floor(entry.objectiveTotal)))

        lines[#lines + 1] = ""
        lines[#lines + 1] = "Each share is measured against the mean of the top three"
            .. " in this match, so 100 is as good as anyone here is doing."
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Left-click to target, right-click to focus."
        return table.concat(lines, "\n")
    end, "ANCHOR_LEFT")
end

-- TOP: the best players on either side. Mine first, matching the tab order --
-- a board that reorders itself between two views of the same data is one you
-- have to re-read every time you look at it.
local topSection = NewSection(120)
topSection.summary = NewText(topSection, "GameFontHighlightSmall", "LEFT")
topSection.summary:SetPoint("TOPLEFT", topSection, "TOPLEFT", 0, 0)
topSection.summary:SetWidth(PANEL_WIDTH)
topSection.summary:SetWordWrap(true)
topSection.blocks = {}

for index = 1, 2 do
    local blockSpec = { rows = {} }
    blockSpec.header = NewText(topSection, "GameFontNormalSmall", "LEFT")
    blockSpec.tally = NewText(topSection, "GameFontDisableSmall", "RIGHT")
    for slot = 1, MAX_TOP_ROWS do
        local row = NewRosterRow(topSection, true)
        AttachImpactTooltip(row)
        blockSpec.rows[slot] = row
    end
    topSection.blocks[index] = blockSpec
end

-- The faction view: one side, broken into what a battleground actually pays
-- for. The three universal boards, then one per objective column the client
-- says this map has.
local rosterSection = NewSection(200)
rosterSection.header = NewText(rosterSection, "GameFontNormalSmall", "LEFT")
rosterSection.header:SetPoint("TOPLEFT", rosterSection, "TOPLEFT", 0, 0)
rosterSection.tally = NewText(rosterSection, "GameFontDisableSmall", "RIGHT")
rosterSection.tally:SetPoint("TOPRIGHT", rosterSection, "TOPRIGHT", 0, 0)
rosterSection.empty = NewText(rosterSection, "GameFontDisableSmall", "LEFT")
rosterSection.empty:SetPoint("TOPLEFT", rosterSection, "TOPLEFT", 0, -GROUP_HEADER - 2)
rosterSection.empty:SetWidth(PANEL_WIDTH)
rosterSection.groups = {}

for index = 1, MAX_GROUPS do
    local groupSpec = { rows = {} }
    groupSpec.header = NewText(rosterSection, "GameFontDisableSmall", "LEFT")
    for slot = 1, MAX_GROUP_ROWS do
        local row = NewRosterRow(rosterSection, false)
        AttachImpactTooltip(row)
        groupSpec.rows[slot] = row
    end
    rosterSection.groups[index] = groupSpec
end

-- What the view can say when it has no ranking to draw. Never a blank panel:
-- "nothing yet" and "nothing here" are different answers.
local function RosterExcuse()
    local report = roster.report
    if report and not report.ready then return report.reason end
    if not inBattleground and not roster.demo then
        return "No battleground. The roster reads the battlefield scoreboard."
    end
    if roster.asked then return "Reading the scoreboard..." end
    return "Waiting for the scoreboard."
end

-- Paint: never protected, so it runs every frame in combat and out. This is
-- what keeps a held row honest -- the score and the range on it are live even
-- while the ORDER is frozen, and the name is written from the same assignment
-- that set the macro, so it can never point at somebody else.
local function PaintTopRow(row)
    local entry = RowEntry(row)
    if entry then
        row.name:SetText(entry.name)
        ClassTint(row.name, entry)
        row.value:SetText(tostring(entry.impact))
        row.value:SetTextColor(ImpactColor(entry.impact))
        row.reason:SetText(entry.reason)
        SetRowRange(row, entry)
    end
    PaintRowMark(row, entry)
    PaintRowHighlight(row)
end

local function PaintGroupRow(row)
    local entry = RowEntry(row)
    if entry then
        row.name:SetText(entry.name)
        ClassTint(row.name, entry)
        local value = row.column and entry.objectives[row.column]
            or (row.field and entry[row.field])
        row.value:SetText(RS.Format(value or 0, row.format))
        row.value:SetTextColor(0.92, 0.92, 0.92)
        SetRowRange(row, entry)
    end
    PaintRowMark(row, entry)
    PaintRowHighlight(row)
end

local function RenderTop()
    local report = roster.report
    local ready = report and report.ready
    local summary = ready and report.summary or RosterExcuse()
    -- Structure holds while you fight; everything below that line is paint
    local frozen = Frozen(topSection)

    topSection.summary:SetText(summary or "")
    if ready then
        topSection.summary:SetTextColor(1, 0.85, 0.40)
    else
        topSection.summary:SetTextColor(0.70, 0.70, 0.70)
    end
    local height = topSection.summary:GetStringHeight() or ROW_HEIGHT
    if height <= 0 then height = ROW_HEIGHT end
    local y = math.ceil(height) + 6

    local order = { myFaction or "ALLIANCE", enemyFaction or Opposite(myFaction or "ALLIANCE") }
    local count = TopCount()
    for index, faction in ipairs(order) do
        local blockSpec = topSection.blocks[index]
        local group = ready and report.factions[faction]
        if not group or #group.players == 0 then
            if not frozen then
                blockSpec.header:Hide()
                blockSpec.tally:Hide()
                for _, row in ipairs(blockSpec.rows) do
                    BindRow(row, nil)
                    SafeShown(row, false)
                end
            end
        else
            blockSpec.header:Show()
            blockSpec.header:SetText(FactionName(faction):upper())
            Tint(blockSpec.header, faction)
            blockSpec.tally:Show()
            blockSpec.tally:SetText(string.format("%d kills / %d down%s",
                math.floor(group.totals.kills), math.floor(group.totals.deaths),
                index == 1 and StaleSuffix() or ""))
            if not frozen then
                blockSpec.header:ClearAllPoints()
                blockSpec.header:SetPoint("TOPLEFT", topSection, "TOPLEFT", 0, -y)
                blockSpec.tally:ClearAllPoints()
                blockSpec.tally:SetPoint("TOPRIGHT", topSection, "TOPRIGHT", 0, -y)
            end
            y = y + GROUP_HEADER

            for slot, row in ipairs(blockSpec.rows) do
                if frozen then
                    if row:IsShown() and row.player then PaintTopRow(row) end
                else
                    local entry = slot <= count and group.players[slot]
                    if entry then
                        BindRow(row, entry)
                        SafePoint(row, "TOPLEFT", topSection, "TOPLEFT", 0, -y)
                        row.rank:SetText(tostring(slot))
                        PaintTopRow(row)
                        SafeShown(row, true)
                        y = y + ROW_HEIGHT
                    else
                        BindRow(row, nil)
                        SafeShown(row, false)
                    end
                end
            end
            y = y + 3
        end
    end

    if not frozen then SafeHeight(topSection, math.max(y, 1)) end
end

local function RenderRoster(faction)
    local report = roster.report
    local group = report and report.ready and report.factions[faction]
    local frozen = Frozen(rosterSection)

    rosterSection.header:SetText(FactionName(faction):upper())
    Tint(rosterSection.header, faction)

    local y = GROUP_HEADER + 2
    if not group or #group.players == 0 then
        rosterSection.tally:SetText("")
        rosterSection.empty:Show()
        rosterSection.empty:SetText(RosterExcuse() or "")
        rosterSection.empty:SetTextColor(0.70, 0.70, 0.70)
        if not frozen then
            for _, groupSpec in ipairs(rosterSection.groups) do
                groupSpec.header:Hide()
                for _, row in ipairs(groupSpec.rows) do
                    BindRow(row, nil)
                    SafeShown(row, false)
                end
            end
            local height = rosterSection.empty:GetStringHeight() or ROW_HEIGHT
            SafeHeight(rosterSection, y + math.max(math.ceil(height), ROW_HEIGHT))
        end
        return
    end

    rosterSection.empty:Hide()
    rosterSection.tally:SetText(string.format("%d up  %s dmg  %s heal%s",
        math.floor(group.totals.players), RS.Short(group.totals.damage),
        RS.Short(group.totals.healing), StaleSuffix()))

    local count = TopCount()
    for index, groupSpec in ipairs(rosterSection.groups) do
        local data = group.groups[index]
        -- A board nobody has scored on is HIDDEN rather than drawn empty: an
        -- Arathi with no caps yet should not reserve three blank rows under a
        -- heading, twice
        if not data or #data.rows == 0 then
            if not frozen then
                groupSpec.header:Hide()
                for _, row in ipairs(groupSpec.rows) do
                    BindRow(row, nil)
                    SafeShown(row, false)
                end
            end
        else
            groupSpec.header:Show()
            groupSpec.header:SetText(data.label)
            groupSpec.header:SetTextColor(0.62, 0.62, 0.62)
            if not frozen then
                groupSpec.header:ClearAllPoints()
                groupSpec.header:SetPoint("TOPLEFT", rosterSection, "TOPLEFT", 0, -y)
            end
            y = y + GROUP_HEADER

            for slot, row in ipairs(groupSpec.rows) do
                if frozen then
                    if row:IsShown() and row.player then PaintGroupRow(row) end
                else
                    local entry = slot <= count and data.rows[slot]
                    if entry then
                        BindRow(row, entry.player)
                        row.field, row.column, row.format = data.field, data.column, data.format
                        SafePoint(row, "TOPLEFT", rosterSection, "TOPLEFT", 0, -y)
                        row.rank:SetText(tostring(slot))
                        PaintGroupRow(row)
                        SafeShown(row, true)
                        y = y + ROW_HEIGHT
                    else
                        BindRow(row, nil)
                        SafeShown(row, false)
                    end
                end
            end
            y = y + 2
        end
    end

    if not frozen then SafeHeight(rosterSection, math.max(y, 1)) end
end

-- ---------------------------------------------------------------------------
-- Which tab is up
-- ---------------------------------------------------------------------------

-- BATTLE is only offered where the projection means something. Outside Arathi
-- the tab is not greyed out, it is GONE -- an Arathi Basin answer in a Warsong
-- Gulch is not a disabled feature, it is a wrong one.
local function BattleAvailable()
    if inBasin or demoUntil > GetTime() then return true end
    return Commander.UI.HudUnlocked(DB(), "Board") and true or false
end

local function AvailableTabs()
    local db = DB()
    local keys = {}
    if BattleAvailable() then keys[#keys + 1] = TAB_BATTLE end
    if not db or db.ShowPerformers ~= false then
        keys[#keys + 1] = TAB_TOP
        keys[#keys + 1] = TAB_MINE
        keys[#keys + 1] = TAB_THEIRS
    end
    if #keys == 0 then keys[1] = TAB_BATTLE end
    return keys
end

ActiveTab = function()
    local db = DB()
    local keys = AvailableTabs()
    local wanted = db and db.Tab
    for _, key in ipairs(keys) do
        if key == wanted then return key, keys end
    end
    return keys[1], keys
end

TabFaction = function(key)
    if key == TAB_MINE then return myFaction end
    if key == TAB_THEIRS then return enemyFaction end
    return nil
end

local function TabLabel(key)
    if key == TAB_BATTLE then return "BATTLE" end
    if key == TAB_TOP then return "TOP" end
    local faction = TabFaction(key)
    if faction then return FactionName(faction):upper() end
    return key == TAB_MINE and "US" or "THEM"
end

SelectTab = function(key)
    local db = DB()
    if not db then return end
    db.Tab = key
    -- A tab somebody just clicked is a tab they want current
    if key ~= TAB_BATTLE and inBattleground then RequestScores(true) end
    if Tick then Tick() end
end

local function RenderTabs(keys, active, pending)
    LayoutTabs(keys)
    for _, button in ipairs(tabSection.buttons) do
        if button:IsShown() then
            local faction = TabFaction(button.key)
            local color = faction and Color(faction) or NEUTRAL_TAB
            local waiting = pending == button.key
            button.label:SetText(waiting and (TabLabel(button.key) .. "*")
                or TabLabel(button.key))
            local on = button.key == active
            button.bg:SetVertexColor(color.r, color.g, color.b,
                (on or button.hovered) and 0.16 or 0)
            button.rule:SetVertexColor(color.r, color.g, color.b, on and 0.9 or 0.22)
            if on then
                button.label:SetTextColor(color.r, color.g, color.b)
            elseif waiting then
                -- Asked for, and waiting on the fight to end
                button.label:SetTextColor(1, 0.85, 0.40)
                button.rule:SetVertexColor(1, 0.85, 0.40, 0.45)
            else
                button.label:SetTextColor(color.r * 0.52, color.g * 0.52, color.b * 0.52)
            end
        end
    end
end

-- Move the pieces that sit differently at each density. Runs only when the
-- density actually changes, so the per-frame path stays a pure redraw.
local appliedDensity, appliedOutline
-- The tab whose content is actually on screen, which is not always the tab
-- that was asked for: see the note in Render.
local appliedTab

local function ApplyDensity()
    local key = DensityKey()
    local metrics = DENSITY[key]
    local full = key == "FULL"
    local minimal = key == "MINIMAL"

    commsSection.baseHeight = metrics.comms
    commsSection:SetHeight(metrics.comms)
    for _, button in ipairs(commsSection.buttons) do
        button:SetHeight(metrics.comms - 1)
    end

    verdictSection.baseHeight = metrics.verdict
    verdictSection:SetHeight(metrics.verdict)
    -- Single anchor plus an explicit width at every density. Sharing a row on
    -- one anchor each and no width, a long verdict ran straight into a long
    -- clock in the middle of the line — which is most of what "messy" was.
    verdictSection.headline:ClearAllPoints()
    verdictSection.detail:ClearAllPoints()
    if full then
        -- Headline over its own detail line, the roomy reading
        Restyle(verdictSection.headline, "GameFontNormalLarge")
        verdictSection.headline:SetJustifyH("LEFT")
        verdictSection.headline:SetWidth(PANEL_WIDTH)
        verdictSection.headline:SetPoint("TOPLEFT", verdictSection, "TOPLEFT", 0, -1)
        verdictSection.detail:SetJustifyH("LEFT")
        verdictSection.detail:SetWidth(PANEL_WIDTH)
        verdictSection.detail:SetPoint("TOPLEFT", verdictSection.headline, "BOTTOMLEFT", 0, -4)
    else
        -- Verdict left, the clock (and on Minimal the call) right, each with
        -- its own half of the row and no way into the other's
        Restyle(verdictSection.headline, "GameFontNormalLarge")
        local headWidth = math.floor(PANEL_WIDTH * 0.50)
        verdictSection.headline:SetJustifyH("LEFT")
        verdictSection.headline:SetWidth(headWidth)
        verdictSection.headline:SetPoint("LEFT", verdictSection, "LEFT", 0, 0)
        verdictSection.detail:SetJustifyH("RIGHT")
        verdictSection.detail:SetWidth(PANEL_WIDTH - headWidth - 6)
        verdictSection.detail:SetPoint("RIGHT", verdictSection, "RIGHT", 0, 0)
    end
    verdictSection.headline:SetWordWrap(false)
    verdictSection.detail:SetWordWrap(false)

    raceSection.baseHeight = metrics.race
    raceSection:SetHeight(math.max(metrics.race, 1))
    raceSection.top:SetShown(full)
    raceSection.bottom:SetShown(full)
    raceSection.mine:SetShown(not full)
    raceSection.theirs:SetShown(not full)

    ladderSection.baseHeight = metrics.ladder
    ladderSection:SetHeight(math.max(metrics.ladder, 1))
    for _, row in ipairs(ladderSection.rows) do row:SetShown(full) end
    for _, cell in ipairs(ladderSection.cells) do cell:SetShown(not full) end
    -- The label column belongs to the strip; the roomy rows say it in words
    ladderSection.axisHold:SetShown(not full)
    ladderSection.axisEnds:SetShown(not full)
    ladderSection.header:SetText(full and "hold  -  if they take the rest" or "if they take the rest")
    ladderSection.header:SetTextColor(0.62, 0.62, 0.62)

    nodeSection.baseHeight = metrics.nodes
    nodeSection:SetHeight(metrics.nodes)
    for _, pip in ipairs(nodeSection.pips) do
        pip:SetHeight(metrics.nodes - 2)
    end

    callSection.baseHeight = metrics.call
    callSection:SetHeight(math.max(metrics.call, 1))
    -- Wrapping is what makes the call two lines tall; the dense levels want it
    -- on one line and would rather clip than grow
    callSection.text:SetWordWrap(full)

    appliedDensity = key
    appliedOutline = DB() and DB().TextOutline
    ApplyTextTreatment()
    return key, metrics, full, minimal
end

-- Flow whichever sections are switched on and size the frame to exactly what
-- is left, so turning a section off shrinks the board rather than leaving a
-- hole in it.
local function Layout(pad)
    -- Anchoring sections and resizing the board are protected calls once the
    -- roster rows are secure buttons, so the board holds the shape it had when
    -- the fight started. Nothing it SAYS is frozen -- every number on it is
    -- painted by the render pass above, which is never protected.
    if Frozen(frame) then return end
    local previous, total = nil, 0
    for _, section in ipairs(sections) do
        if section:IsShown() then
            section:ClearAllPoints()
            if previous then
                section:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -pad)
                total = total + pad
            else
                section:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            end
            previous = section
            total = total + section:GetHeight()
        end
    end
    frame:SetHeight(math.max(total, 1))
end

-- ---------------------------------------------------------------------------
-- The call — the one line worth acting on
-- ---------------------------------------------------------------------------

local WIN_COLOR = { r = 0.30, g = 1.00, b = 0.40 }
local LOSS_COLOR = { r = 1.00, g = 0.35, b = 0.30 }
local HEAT_COLOR = { r = 1.00, g = 0.85, b = 0.40 }
local IDLE_COLOR = { r = 0.75, g = 0.75, b = 0.75 }

-- Built once and used by the board, the one-line read and the chat call, so
-- what Oracle says to the group is exactly what it is telling you. `terse`
-- drops the sentence around the instruction for the dense levels.
local function BuildCall(snapshot, counts, haveScores, terse)
    if not myFaction then return "Pick a side.", IDLE_COLOR end
    if not haveScores then return terse and "Reading..." or "Waiting on the scoreboard.", IDLE_COLOR end

    local mine = counts[myFaction] or 0
    local minimum = E.MinimumHold(snapshot, myFaction)

    if not minimum then
        return terse and "Gone - they are at the cap" or "GONE. They are at the cap.", LOSS_COLOR
    end

    if mine > minimum then
        local spare = mine - minimum
        if terse then return string.format("Hold %d - %d spare", minimum, spare), WIN_COLOR end
        return string.format("HOLD %d. You can lose %d and still win.", minimum, spare), WIN_COLOR
    end

    if mine == minimum then
        if terse then return string.format("Hold all %d", mine), HEAT_COLOR end
        return string.format("HOLD ALL %d. Losing one loses the game.", mine), HEAT_COLOR
    end

    -- We are short. The number that matters is not which base — it is how
    -- long we have left to take one before it stops mattering.
    --
    -- But only while that is soon enough to be a deadline. Early on, with both
    -- scores near zero, the algebra honestly returns something like two hours
    -- — a real answer to a question nobody is asking, and on screen it reads
    -- as a broken clock. So the deadline is shown only when it lands BEFORE
    -- the game is otherwise decided; past that horizon there is simply no
    -- urgency to report yet.
    local need = minimum - mine
    local deadline = E.Deadline(snapshot, myFaction, minimum)
    local horizon = E.Outcome(snapshot, myFaction).seconds
    local soonEnough = deadline.seconds and deadline.seconds ~= INF
        and (horizon == INF or deadline.seconds < horizon)
    if deadline.winsNow and soonEnough then
        local clock = E.FormatClock(deadline.seconds)
        if terse then return string.format("Take %d more - %s left", need, clock), LOSS_COLOR end
        return string.format("TAKE %d MORE within %s, or it is out of reach.", need, clock), LOSS_COLOR
    end
    if terse then return string.format("Take %d more to win", need), LOSS_COLOR end
    return string.format("TAKE %d MORE. Nothing less wins.", need), LOSS_COLOR
end

-- ---------------------------------------------------------------------------
-- What the comms buttons say
-- ---------------------------------------------------------------------------

local COMMS_THROTTLE = 8        -- per button
local COMMS_GLOBAL_THROTTLE = 2 -- across all of them
local commsSentAt, commsLastAny = {}, 0

local function CommsReady(key)
    local now = GetTime()
    if (now - commsLastAny) < COMMS_GLOBAL_THROTTLE then return false end
    local sent = commsSentAt[key]
    return not sent or (now - sent) >= COMMS_THROTTLE
end

-- A short verdict clause the messages share.
local function VerdictClause(outcome)
    if outcome.stalled then return "nobody is scoring" end
    if outcome.win then
        return string.format("we WIN by %s in %s", E.FormatMargin(outcome.margin), E.FormatClock(outcome.seconds))
    end
    if outcome.loss then
        return string.format("we LOSE by %s in %s", E.FormatMargin(outcome.margin), E.FormatClock(outcome.seconds))
    end
    return "dead heat"
end

-- The three lines, rebuilt on demand. Returns a table keyed by button; a nil
-- entry means that button has nothing true to say and stays greyed out.
BuildComms = function()
    local snapshot, counts, haveScores = Snapshot()
    if not (haveScores and myFaction and enemyFaction) then return {} end

    local outcome = E.Outcome(snapshot, myFaction)
    local mine = counts[myFaction] or 0
    local minimum = E.MinimumHold(snapshot, myFaction)
    local mineScore = myFaction == "ALLIANCE" and snapshot.allianceScore or snapshot.hordeScore
    local theirScore = myFaction == "ALLIANCE" and snapshot.hordeScore or snapshot.allianceScore
    local messages = {}

    -- CALL: the whole read, in the order someone reading chat wants it
    messages.CALL = string.format("[Oracle] %db %d vs %d %db - %s. %s",
        mine, math.floor(mineScore + 0.5), math.floor(theirScore + 0.5), counts[enemyFaction] or 0,
        VerdictClause(outcome), (BuildCall(snapshot, counts, haveScores)))

    -- DEFEND: what they are taking right now and what it costs us. The cost is
    -- the part only Oracle can supply -- everyone can see a flag turning grey,
    -- nobody else can see that this particular one is the game.
    local ticking = {}
    for index = 1, 5 do
        local node = board[index]
        if node and node.state == "CONTESTED" and node.assaulter == enemyFaction then
            local remaining, exact = CaptureRemaining(AB.nodes[index].key)
            if remaining and remaining > 0.5 then
                ticking[#ticking + 1] = string.format("%s %s%ds", AB.nodes[index].name,
                    exact and "" or "<", math.ceil(remaining))
            else
                ticking[#ticking + 1] = AB.nodes[index].name
            end
        end
    end

    if #ticking > 0 then
        -- Where the board lands if none of it is turned around
        local projected = E.CountBases(E.ResolveContested(board))
        local after = E.Outcome({
            allianceScore = snapshot.allianceScore,
            hordeScore = snapshot.hordeScore,
            allianceBases = projected.ALLIANCE,
            hordeBases = projected.HORDE,
        }, myFaction)
        messages.DEFEND = string.format("[Oracle] DEFEND %s - if they land, %s.",
            table.concat(ticking, ", "), VerdictClause(after))
    elseif minimum and mine > 0 and mine == minimum then
        -- Nothing ticking, but we are holding exactly the minimum: every base
        -- is load-bearing and a trade loses the game
        messages.DEFEND = string.format("[Oracle] HOLD ALL %d - we are on the line, losing any one base loses this.",
            mine)
    end

    -- TAKE: how many more, and by when
    if minimum and mine < minimum then
        local need = minimum - mine
        local deadline = E.Deadline(snapshot, myFaction, minimum)
        local horizon = outcome.seconds
        local soonEnough = deadline.seconds and deadline.seconds ~= INF
            and (horizon == INF or deadline.seconds < horizon)
        if deadline.winsNow and soonEnough then
            messages.TAKE = string.format("[Oracle] Need %d more base%s within %s or this is out of reach. Now: %s.",
                need, need == 1 and "" or "s", E.FormatClock(deadline.seconds), VerdictClause(outcome))
        else
            messages.TAKE = string.format("[Oracle] Need %d more base%s - %d wins it, nothing less does.",
                need, need == 1 and "" or "s", minimum)
        end
    elseif not minimum then
        messages.TAKE = "[Oracle] They are at the cap. This one is gone."
    end

    return messages
end

-- A battleground is an instance group: RAID is not a valid channel there even
-- though IsInRaid() is true.
SendComms = function(key)
    local messages = BuildComms()
    local message = messages[key]
    if not message then
        print("Commander Oracle: nothing to report on " .. key .. " yet.")
        return false
    end
    if not CommsReady(key) then return false end

    commsSentAt[key] = GetTime()
    commsLastAny = GetTime()
    if IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        SendChatMessage(message, "INSTANCE_CHAT")
    else
        print(message)
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

local function RenderVerdict(snapshot, counts, haveScores, full, minimal)
    if not haveScores then
        verdictSection.headline:SetText(full and "READING THE BOARD" or "READING")
        verdictSection.headline:SetTextColor(IDLE_COLOR.r, IDLE_COLOR.g, IDLE_COLOR.b)
        verdictSection.detail:SetText(full and "no resources reported yet" or "")
        verdictSection.detail:SetTextColor(0.74, 0.74, 0.74)
        verdictSection.flash:Hide()
        return
    end

    local outcome = E.Outcome(snapshot, myFaction)
    local color, headline

    if outcome.stalled then
        color, headline = IDLE_COLOR, "NO INCOME"
    elseif outcome.win then
        color = WIN_COLOR
        headline = (full and "WIN BY " or "WIN ") .. E.FormatMargin(outcome.margin)
    elseif outcome.loss then
        color = LOSS_COLOR
        headline = (full and "LOSS BY " or "LOSS ") .. E.FormatMargin(outcome.margin)
    else
        color, headline = HEAT_COLOR, "DEAD HEAT"
    end

    verdictSection.headline:SetText(headline)
    verdictSection.headline:SetTextColor(color.r, color.g, color.b)

    local detail
    if full then
        detail = outcome.stalled and "nobody is holding a base" or ("ends in " .. E.FormatClock(outcome.seconds))
        if scores.estimated then detail = detail .. "  (estimated)" end
    else
        -- Dense: the clock alone. It shares the row with the verdict and there
        -- is no room on 226px for a third thing at a size worth reading.
        detail = outcome.stalled and "" or E.FormatClock(outcome.seconds)
        if scores.estimated then detail = detail .. "  ~" end
    end

    -- Where the game is going if nobody turns a flag around. Only worth
    -- saying when it disagrees with the board as it stands.
    if DB().ShowPending and E.CountBases(board).CONTESTED > 0 then
        local projected = E.CountBases(E.ResolveContested(board))
        local after = E.Outcome({
            allianceScore = snapshot.allianceScore,
            hordeScore = snapshot.hordeScore,
            allianceBases = projected.ALLIANCE,
            hordeBases = projected.HORDE,
        }, myFaction)
        if after.win ~= outcome.win then
            if full then
                detail = detail .. (after.win and "  |  flags in flight FLIP it to you"
                    or "  |  flags in flight FLIP it to them")
            else
                detail = detail .. (after.win and "  FLIP+" or "  FLIP-")
            end
        end
    end
    verdictSection.detail:SetText(detail)
    verdictSection.detail:SetTextColor(0.74, 0.74, 0.74)

    if swingFlashUntil > GetTime() then
        local pulse = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(GetTime() * 6))
        verdictSection.flash:SetVertexColor(color.r, color.g, color.b, pulse)
        verdictSection.flash:Show()
    else
        verdictSection.flash:Hide()
    end
end

local function RenderRace(snapshot, counts, haveScores, full)
    local mineScore = myFaction == "ALLIANCE" and snapshot.allianceScore or snapshot.hordeScore
    local theirScore = myFaction == "ALLIANCE" and snapshot.hordeScore or snapshot.allianceScore
    local mineBases, theirBases = counts[myFaction] or 0, counts[enemyFaction] or 0

    if full then
        if not haveScores then
            SetBar(raceSection.top, myFaction or "NEUTRAL", 0, 0, false)
            SetBar(raceSection.bottom, enemyFaction or "NEUTRAL", 0, 0, false)
            return
        end
        local warn = DB().NearVictoryAlert
        SetBar(raceSection.top, myFaction, mineScore, mineBases, warn and mineScore >= AB.warnScore)
        SetBar(raceSection.bottom, enemyFaction, theirScore, theirBases, warn and theirScore >= AB.warnScore)
        return
    end

    -- Dense: "3 bases  1240" against "980  2 bases". The bars only ever carried
    -- these four numbers and a fraction the numbers already imply. The word is
    -- spelled out because two bare numbers side by side ("2  50") genuinely
    -- cannot be told apart, and which one is the base count is the whole point.
    local function BaseLabel(count)
        return string.format("%d base%s", count, count == 1 and "" or "s")
    end
    if not haveScores then
        raceSection.mine:SetText(BaseLabel(mineBases))
        raceSection.theirs:SetText(BaseLabel(theirBases))
    else
        raceSection.mine:SetText(string.format("%s  %d", BaseLabel(mineBases), math.floor(mineScore + 0.5)))
        raceSection.theirs:SetText(string.format("%d  %s", math.floor(theirScore + 0.5), BaseLabel(theirBases)))
    end
    Tint(raceSection.mine, myFaction)
    Tint(raceSection.theirs, enemyFaction)
    -- Past the server's own near-victory line, the number itself goes hot
    if haveScores and DB().NearVictoryAlert then
        if mineScore >= AB.warnScore then raceSection.mine:SetTextColor(1, 0.9, 0.4) end
        if theirScore >= AB.warnScore then raceSection.theirs:SetTextColor(1, 0.9, 0.4) end
    end
end

-- The colour and wording every rung shares, whichever way it is drawn.
local function RungLook(data)
    if data.stalled then return IDLE_COLOR, "no income", "--" end
    if data.win then
        return WIN_COLOR, "win by " .. E.FormatMargin(data.margin), "+" .. E.FormatMargin(data.margin)
    end
    if data.loss then
        return LOSS_COLOR, "loss by " .. E.FormatMargin(data.margin), "-" .. E.FormatMargin(data.margin)
    end
    return HEAT_COLOR, "dead heat", "0"
end

local function RenderLadder(snapshot, counts, haveScores, full)
    local rows = haveScores and E.Ladder(snapshot, myFaction) or {}
    local mine = counts[myFaction] or -1

    if full then
        for index, row in ipairs(ladderSection.rows) do
            local data = rows[index]
            if not data then
                row.bases:SetText("")
                row.outcome:SetText("")
                row.time:SetText("")
                row.marker:Hide()
            else
                local current = data.bases == mine
                local color, long = RungLook(data)
                row.marker:SetShown(current)
                row.marker:SetVertexColor(color.r, color.g, color.b, 1)
                row.bases:SetText(tostring(data.bases))
                row.outcome:SetText(long)
                row.outcome:SetTextColor(color.r, color.g, color.b)
                -- The row you are standing on reads at full strength; the
                -- rest are the alternatives, and should look like it
                local alpha = current and 1 or 0.55
                row.outcome:SetAlpha(alpha)
                row.bases:SetAlpha(alpha)
                row.bases:SetTextColor(1, 1, 1)
                row.time:SetText(data.stalled and "" or E.FormatClock(data.seconds))
                row.time:SetTextColor(0.62, 0.62, 0.62)
                row.time:SetAlpha(alpha)
            end
        end
        return
    end

    -- Dense: rungs 5..1 across, hold over margin, the one you are on lit
    for index, cell in ipairs(ladderSection.cells) do
        local bases = LADDER_CELLS + 1 - index          -- 5, 4, 3, 2, 1
        local data
        for _, row in ipairs(rows) do
            if row.bases == bases then data = row end
        end
        if not data then
            cell.bases:SetText(tostring(bases))
            cell.margin:SetText("")
            cell.marker:Hide()
            cell.bases:SetAlpha(0.4)
        else
            local current = bases == mine
            local color, _, short = RungLook(data)
            cell.bases:SetText(tostring(bases))
            cell.bases:SetTextColor(1, 1, 1)
            cell.margin:SetText(short)
            cell.margin:SetTextColor(color.r, color.g, color.b)
            local alpha = current and 1 or 0.5
            cell.bases:SetAlpha(alpha)
            cell.margin:SetAlpha(alpha)
            -- No wedge to spare at this size: the cell you are on is marked
            -- by lighting the cell itself
            cell.marker:SetShown(current)
            if current then cell.marker:SetVertexColor(color.r, color.g, color.b, 0.18) end
        end
    end
end

local function RenderNodes(full)
    for index, pip in ipairs(nodeSection.pips) do
        local canonNode = AB.nodes[index]
        local node = board[index]
        pip.name:SetText(canonNode.short)

        if not node then
            pip.swatch:SetVertexColor(0.4, 0.4, 0.4, 0.4)
            pip.name:SetTextColor(0.55, 0.55, 0.55)
            pip.timer:SetText("")
        elseif node.state == "CONTESTED" then
            local color = Color(node.assaulter)
            -- Half-lit: nobody is being paid for this one while it ticks
            pip.swatch:SetVertexColor(color.r, color.g, color.b, 0.5)
            pip.name:SetTextColor(1, 0.9, 0.5)
            local remaining, exact = CaptureRemaining(canonNode.key)
            -- Past the full minute the flag has landed and the map simply has
            -- not caught up yet; a clock frozen at 0s reads like a bug
            if remaining and remaining > 0.5 then
                pip.timer:SetText(string.format("%s%ds", exact and "" or "~", math.ceil(remaining)))
                pip.timer:SetTextColor(1, 0.85, 0.4)
            else
                pip.timer:SetText("cap")
            end
        elseif node.state == "OWNED" then
            local color = Color(node.owner)
            pip.swatch:SetVertexColor(color.r, color.g, color.b, 1)
            pip.name:SetTextColor(1, 1, 1)
            pip.timer:SetText("")
        else
            pip.swatch:SetVertexColor(0.7, 0.7, 0.7, 0.45)
            pip.name:SetTextColor(0.8, 0.8, 0.8)
            pip.timer:SetText(full and "open" or "-")
            pip.timer:SetTextColor(0.7, 0.7, 0.7)
        end
    end
end

-- A button that has nothing true to say is greyed out rather than hidden: the
-- header must not reflow under the cursor mid-fight.
local function RenderComms()
    local messages = BuildComms()
    for _, button in ipairs(commsSection.buttons) do
        local spec = button.spec
        local live = messages[spec.key] ~= nil
        local ready = live and CommsReady(spec.key)
        local color = spec.color

        if not live then
            button.bg:SetVertexColor(0, 0, 0, 0)
            button.rule:SetVertexColor(0.5, 0.5, 0.5, 0.25)
            button.label:SetTextColor(0.42, 0.42, 0.42)
        elseif not ready then
            -- Just sent: still readable, visibly not armed
            button.bg:SetVertexColor(0, 0, 0, 0)
            button.rule:SetVertexColor(color.r, color.g, color.b, 0.3)
            button.label:SetTextColor(color.r * 0.5, color.g * 0.5, color.b * 0.5)
        else
            button.bg:SetVertexColor(color.r, color.g, color.b, button.hovered and 0.22 or 0)
            button.rule:SetVertexColor(color.r, color.g, color.b, button.hovered and 1 or 0.7)
            button.label:SetTextColor(color.r, color.g, color.b)
        end
        button:SetEnabled(live and true or false)
    end
end

local function Render()
    local snapshot, counts, haveScores = Snapshot()
    local db = DB()

    -- Density and the text treatment are structural: reapply only on change,
    -- and never while the board is frozen -- every move it makes is protected
    if (appliedDensity ~= DensityKey() or appliedOutline ~= db.TextOutline)
        and not Frozen(frame) then
        ApplyDensity()
    end
    local key = appliedDensity
    local metrics = DENSITY[key]
    local full, minimal = key == "FULL", key == "MINIMAL"

    -- Minimal drops the race and the ladder — the two sections that are
    -- context rather than instruction — and keeps the verdict, the call and
    -- the flags. Their own switches are ignored at that density.
    --
    -- And a section with nothing to say is HIDDEN rather than drawn empty: an
    -- unprojectable board used to reserve six blank ladder rows and leave a
    -- hole the size of the addon in the middle of the frame.
    local tab, tabKeys = ActiveTab()
    local battle = tab == TAB_BATTLE
    local factionTab = tab == TAB_MINE or tab == TAB_THEIRS
    -- One tab is not a tab strip: with the roster switched off, or outside a
    -- battleground with the board unlocked for placing, the row is just a rule
    -- across the top of the frame and it does not earn its pixels.
    SafeShown(tabSection, #tabKeys > 1)

    -- Only ask the server for a scoreboard while somebody is actually reading
    -- one. RequestScores throttles on top of this.
    if not battle and inBattleground then RequestScores() end

    local canProject = haveScores and myFaction ~= nil
    SafeShown(commsSection, battle and db.ShowComms and canProject)
    SafeShown(verdictSection, battle and db.ShowVerdict)
    SafeShown(raceSection, battle and db.ShowRace and not minimal)
    SafeShown(ladderSection, battle and db.ShowLadder and not minimal and canProject)
    SafeShown(nodeSection, battle and db.ShowNodes)
    SafeShown(callSection, battle and (db.ShowCallout or minimal) and canProject)
    SafeShown(topSection, tab == TAB_TOP)
    SafeShown(rosterSection, factionTab)

    -- A tab clicked mid-fight cannot take: showing and hiding these is
    -- protected once the rows carry a secure click. The strip lights the tab
    -- you are actually LOOKING at and marks the one you asked for as pending,
    -- rather than lighting a tab whose content is not on screen.
    if not Frozen(frame) then appliedTab = tab end
    if tabSection:IsShown() then
        RenderTabs(tabKeys, appliedTab or tab, appliedTab ~= tab and tab or nil)
    end

    if topSection:IsShown() then RenderTop() end
    if rosterSection:IsShown() then
        RenderRoster(TabFaction(tab) or myFaction or "ALLIANCE")
    end
    if commsSection:IsShown() then RenderComms() end
    if verdictSection:IsShown() then RenderVerdict(snapshot, counts, haveScores, full, minimal) end
    if raceSection:IsShown() then RenderRace(snapshot, counts, haveScores, full) end
    if ladderSection:IsShown() then RenderLadder(snapshot, counts, haveScores, full) end
    if nodeSection:IsShown() then RenderNodes(full) end
    if callSection:IsShown() then
        local text, color = BuildCall(snapshot, counts, haveScores, not full)
        callSection.text:SetText(text)
        callSection.text:SetTextColor(color.r, color.g, color.b)
        if full then
            local height = callSection.text:GetStringHeight()
            if height and height > 0 then
                SafeHeight(callSection, math.max(callSection.baseHeight, math.ceil(height) + 4))
            end
        else
            SafeHeight(callSection, callSection.baseHeight)
        end
    end

    Layout(metrics.pad)
end

-- ---------------------------------------------------------------------------
-- Swing: the alert worth having
-- ---------------------------------------------------------------------------

-- Not "the score changed" — the score changes every few seconds and none of it
-- is news. This fires when the ANSWER changes: a flag landed somewhere and the
-- game you were going to win is now one you are going to lose.
local function CheckSwing(snapshot, haveScores)
    if not (haveScores and inBasin) then return end
    local db = DB()
    local race = E.Race(snapshot)
    local verdict = race.stalled and "STALL" or (race.winner or "HEAT")

    if lastVerdict and lastVerdict ~= verdict and db.SwingAlert then
        swingFlashUntil = GetTime() + 3
        if db.SwingSound and PlaySound and SOUNDKIT then
            PlaySound(SOUNDKIT.RAID_WARNING or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
    end
    lastVerdict = verdict
end

-- ---------------------------------------------------------------------------
-- Visibility
-- ---------------------------------------------------------------------------

local DEFAULT_POINT = { point = "TOPLEFT", x = 24, y = -220 }

local function ApplyChrome()
    Commander.UI.ApplyHudChrome(frame, DB(), "Board", {
        defaultPoint = DEFAULT_POINT,
        title = "Oracle",
    })
end

local function ResetMatch()
    board = {}
    contested = {}
    scores = { alliance = nil, horde = nil, at = nil, estimated = false }
    resolvedSwap = nil
    lastVerdict, swingFlashUntil = nil, 0
end

-- Committing to "we have left" the instant the client says so would wipe the
-- match on every death: releasing to the graveyard fires
-- PLAYER_ENTERING_WORLD with the player reported OUTSIDE the instance, and in
-- a battleground that happens constantly. Entering is taken at once; leaving
-- has to hold for a grace period before the contested clocks, the carried
-- score and the resolved widget sides are thrown away.
local EXIT_GRACE = 10
local basinSeenAt = 0

-- The battleground we are standing in, by its instance map, or nil for
-- anywhere that is not one.
local function BattlegroundMapID()
    if not GetInstanceInfo then return nil end
    local _, instanceType, _, _, _, _, _, instanceMapID = GetInstanceInfo()
    if instanceType ~= "pvp" then return nil end
    return instanceMapID or 0
end

local battlegroundSeenAt = 0

local function InArena()
    if not GetInstanceInfo then return false end
    local _, instanceType = GetInstanceInfo()
    return instanceType == "arena"
end

local function RefreshZone()
    local now = GetTime()
    local mapID = BattlegroundMapID()
    -- No grace period on this one: an arena is over the moment it is over, and
    -- there is no graveyard-release flicker to ride out
    local arena = InArena()
    if arena ~= inArena then
        inArena = arena
        if not arena and ClearOurMarks then ClearOurMarks() end
    end
    local basin = InArathiBasin()
    -- Arathi is a battleground even on the tick where GetInstanceInfo has not
    -- caught up and only the map has
    local battleground = basin or (mapID ~= nil)

    if basin then
        basinSeenAt = now
        if not inBasin then
            inBasin = true
            ResetMatch()
        end
    end
    if battleground then
        battlegroundSeenAt = now
        if not inBattleground then
            inBattleground = true
            ResetRoster()
        end
    end

    -- Standing in a DIFFERENT battleground settles it at once. The grace
    -- period is for the graveyard-release flicker, where the client reports us
    -- in no instance at all for a moment; a client saying we are on another
    -- battleground's map is not flickering, and holding an Arathi projection
    -- over a Warsong Gulch for ten seconds would be worse than holding none.
    local elsewhere = mapID ~= nil and mapID ~= AB.instanceMapID
    if inBasin and not basin and (elsewhere or (now - basinSeenAt) >= EXIT_GRACE) then
        inBasin = false
        ResetMatch()
    end
    if inBattleground and not battleground and (now - battlegroundSeenAt) >= EXIT_GRACE then
        inBattleground = false
        ResetRoster()
    end
end

local zoneCheckedAt = 0

Tick = function()
    local db = DB()
    if not db then return end

    -- The exit grace above only expires if something keeps asking.
    if (GetTime() - zoneCheckedAt) >= 1 then
        zoneCheckedAt = GetTime()
        RefreshZone()
    end

    local demo = demoUntil > GetTime()
    local unlocked = Commander.UI.HudUnlocked(db, "Board")
    -- Every battleground, not just Arathi: the roster tabs have something to
    -- say in all of them, and the BATTLE tab takes itself away where it does
    -- not (see AvailableTabs).
    local wanted = db.EnableOracle and (inBasin or inBattleground or demo or unlocked)

    if not wanted then
        if frame:IsShown() then frame:Hide() end
        RefreshUnits()
        UpdateMarks()
        return
    end

    if inBasin and not demo then
        Poll()
        local snapshot, _, haveScores = Snapshot()
        CheckSwing(snapshot, haveScores)
    end

    if not frame:IsShown() then frame:Show() end
    RefreshUnits()
    UpdateMarks()
    Render()
end

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

-- A worked position, so the board can be placed and read outside a
-- battleground: three bases to two, level on resources — the exact spot where
-- the scoreboard says "tied" and the answer is "you are winning by 333".
-- The roster tabs read a scoreboard, and outside a battleground there is not
-- one -- so the demo brings its own. Three empty tabs place nothing, and
-- placing the board is what the demo is for.
local function DemoRoster()
    local mine = myFaction or "ALLIANCE"
    local theirs = enemyFaction or Opposite(mine)
    local rows = {
        { name = "Ashvale", faction = mine, classToken = "WARRIOR",
          killingBlows = 9, deaths = 3, damage = 214000, healing = 0, objectives = { 2, 1 } },
        { name = "Brackwater", faction = mine, classToken = "PRIEST",
          killingBlows = 1, deaths = 2, damage = 12000, healing = 186000, objectives = { 0, 2 } },
        { name = "Coldiron", faction = mine, classToken = "ROGUE",
          killingBlows = 7, deaths = 5, damage = 168000, healing = 0, objectives = { 4, 0 } },
        { name = "Dunhollow", faction = mine, classToken = "MAGE",
          killingBlows = 3, deaths = 6, damage = 141000, healing = 0, objectives = { 0, 0 } },
        { name = "Emberlin", faction = mine, classToken = "DRUID",
          killingBlows = 0, deaths = 4, damage = 9000, healing = 74000, objectives = { 1, 1 } },
        { name = "Grimjaw", faction = theirs, classToken = "WARLOCK",
          killingBlows = 12, deaths = 2, damage = 251000, healing = 0, objectives = { 1, 0 } },
        { name = "Hexmark", faction = theirs, classToken = "SHAMAN",
          killingBlows = 0, deaths = 1, damage = 15000, healing = 240000, objectives = { 0, 3 } },
        { name = "Kelthuz", faction = theirs, classToken = "HUNTER",
          killingBlows = 5, deaths = 4, damage = 176000, healing = 0, objectives = { 2, 0 } },
        { name = "Morgrath", faction = theirs, classToken = "PALADIN",
          killingBlows = 2, deaths = 3, damage = 61000, healing = 38000, objectives = { 0, 1 } },
        { name = "Nazgrint", faction = theirs, classToken = "WARRIOR",
          killingBlows = 4, deaths = 7, damage = 133000, healing = 0, objectives = { 1, 1 } },
    }
    if not RS then return nil end
    return RS.Rank(rows, {
        myFaction = mine,
        topCount = TopCount(),
        columns = { "Bases Assaulted", "Bases Defended" },
        runTime = 480,
    })
end

function CommanderOracle_Test()
    myFaction = myFaction or "ALLIANCE"
    enemyFaction = Opposite(myFaction)
    local mine, theirs = myFaction, enemyFaction
    board = {
        [1] = { node = AB.nodes[1], state = "OWNED", owner = mine },
        [2] = { node = AB.nodes[2], state = "OWNED", owner = mine },
        [3] = { node = AB.nodes[3], state = "CONTESTED", assaulter = theirs },
        [4] = { node = AB.nodes[4], state = "OWNED", owner = theirs },
        [5] = { node = AB.nodes[5], state = "OWNED", owner = mine },
    }
    contested = { [AB.nodes[3].key] = { since = GetTime(), exact = true, assaulter = theirs } }
    scores = { alliance = 1000, horde = 1000, at = GetTime(), estimated = false }
    demoUntil = GetTime() + 30
    roster.report = DemoRoster()
    roster.at = GetTime()
    roster.demo = true
    Tick()
    print("Commander Oracle: demo board up for 30 seconds -- every tab, with a worked scoreboard behind the roster.")
end

-- Manual only, and one source of truth: the slash commands post exactly what
-- the header buttons post.
function CommanderOracle_Call() SendComms("CALL") end
function CommanderOracle_Defend() SendComms("DEFEND") end
function CommanderOracle_Take() SendComms("TAKE") end

-- What to run if the resources ever read wrong. Dumps every widget the client
-- is showing, so the reader and a bug report are looking at the same thing.
function CommanderOracle_Probe()
    local found = 0
    EachWidget(function(setID, widget)
        found = found + 1
        local line = string.format("Oracle probe: set %s  widget %s  type %s",
            tostring(setID), tostring(widget.widgetID), tostring(widget.widgetType))
        -- The text is the whole diagnosis for a resource read that goes wrong,
        -- so print it verbatim alongside what the parser made of it
        if widget.widgetType == ICON_AND_TEXT and C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo then
            local ok, info = pcall(C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo, widget.widgetID)
            if ok and info then
                local score, max, bases = ParseResourceText(info.text)
                line = line .. string.format("  ICON+TEXT text=%q -> score=%s max=%s bases=%s",
                    tostring(info.text), tostring(score), tostring(max), tostring(bases))
            end
        elseif widget.widgetType == DOUBLE_STATUS_BAR and C_UIWidgetManager.GetDoubleStatusBarWidgetVisualizationInfo then
            local ok, info = pcall(C_UIWidgetManager.GetDoubleStatusBarWidgetVisualizationInfo, widget.widgetID)
            if ok and info then
                line = line .. string.format("  DOUBLE BAR left=%s/%s right=%s/%s",
                    tostring(info.leftBarValue), tostring(info.leftBarMax),
                    tostring(info.rightBarValue), tostring(info.rightBarMax))
            end
        end
        print(line)
    end)
    if found == 0 then
        print("Oracle probe: the client is showing no widgets here.")
    end

    local poiCount = 0
    for _, poiID in ipairs((C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIForMap
        and C_AreaPoiInfo.GetAreaPOIForMap(AB.uiMapID)) or {}) do
        local entry = POI[poiID]
        poiCount = poiCount + 1
        print(string.format("Oracle probe: POI %d -> %s", poiID,
            entry and (entry.node.name .. " " .. entry.state .. " " .. tostring(entry.owner or entry.assaulter or ""))
            or "UNKNOWN"))
    end
    print(string.format("Oracle probe: %d widgets, %d map POIs, in Arathi Basin = %s",
        found, poiCount, tostring(inBasin)))
    print(string.format("Oracle probe: cap %d, faction %s, scores %s / %s%s, line order %s",
        AB.maxScore, tostring(myFaction), tostring(scores.alliance), tostring(scores.horde),
        scores.estimated and " (estimated)" or "",
        resolvedSwap == nil and "unresolved" or (resolvedSwap and "second line is Alliance"
            or "first line is Alliance")))
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")

-- Registering an event this client only exposes as a callback throws; ask
-- first where the API allows it, and never let one bad name take the file out.
local function SafeRegister(name)
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(name) then
        return false
    end
    return pcall(events.RegisterEvent, events, name)
end

SafeRegister("PLAYER_ENTERING_WORLD")
SafeRegister("ZONE_CHANGED_NEW_AREA")
SafeRegister("AREA_POIS_UPDATED")
SafeRegister("UPDATE_UI_WIDGET")
SafeRegister("UPDATE_ALL_UI_WIDGETS")
SafeRegister("UPDATE_BATTLEFIELD_SCORE")
SafeRegister("NAME_PLATE_UNIT_ADDED")
SafeRegister("NAME_PLATE_UNIT_REMOVED")
SafeRegister("PLAYER_REGEN_ENABLED")
SafeRegister("GROUP_ROSTER_UPDATE")

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "NAME_PLATE_UNIT_ADDED" then
        -- Nameplates are the only sensor that ever names an enemy for us
        if arg1 then nameplateUnits[arg1] = true end
        RefreshUnits(true)
        return
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if arg1 then nameplateUnits[arg1] = nil end
        return
    elseif event == "GROUP_ROSTER_UPDATE" then
        RefreshUnits(true)
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- The moment the protection lifts, everything that was held goes in
        Tick()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        local _, faction = UnitFactionGroup("player")
        myFaction = faction and faction:upper() or myFaction
        enemyFaction = Opposite(myFaction)
        RefreshZone()
        ApplyChrome()
    elseif event == "UPDATE_BATTLEFIELD_SCORE" then
        -- The answer to our request, and the only moment the ranking is
        -- rebuilt: forty players re-scored on a quarter-second redraw would be
        -- work nobody asked for. Blizzard's own scoreboard sits on this event
        -- too, so it arrives whether or not we asked -- hence the check that
        -- somebody is actually looking at a ranking before building one.
        if frame:IsShown() and ActiveTab() ~= TAB_BATTLE then
            ReadScoreboard()
        end
    elseif inBasin then
        -- The map and the widgets both push; taking the push means a flag
        -- change lands on the board immediately rather than up to a quarter
        -- second later, which is the difference between a countdown that
        -- starts on time and one that starts late.
        Poll()
    end
end)

Commander.AddListener(COMMANDER_ORACLE_EVENTS.UPDATE, function()
    ApplyChrome()
    Tick()
end)

C_Timer.NewTicker(0.25, Tick)

-- Exposed for the headless harness so a test can read exactly what the player
-- would see on the board. Nothing in the addon reads this back.
CommanderOracle_Sections = {
    frame = frame,
    tabs = tabSection,
    top = topSection,
    roster = rosterSection,
    scores = roster,
    comms = commsSection,
    verdict = verdictSection,
    race = raceSection,
    ladder = ladderSection,
    nodes = nodeSection,
    call = callSection,
}
