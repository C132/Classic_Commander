-- Commander Spoils — the window.
--
-- ONE frame. Everything loot-related lives inside `CommanderSpoilsFrame` as a
-- band that appears when it has something to say and takes no space when it
-- does not: pickups, the corpse, live rolls, and — when the player opens it —
-- the browsing panes underneath. One position, one scale, one lock, one
-- Escape. See DECISIONS D1.
--
-- The bands make the frame appear on their own; the panes never do. That split
-- is the whole interaction model: a roll has a deadline and has earned an
-- interruption, a ledger has not.

BINDING_HEADER_COMMANDERSPOILS = "Commander Spoils"
BINDING_NAME_COMMANDERSPOILS_TOGGLE = "Open Spoils"
BINDING_NAME_COMMANDERSPOILS_ROLL_NEED = "Roll Need (focused roll)"
BINDING_NAME_COMMANDERSPOILS_ROLL_GREED = "Roll Greed (focused roll)"
BINDING_NAME_COMMANDERSPOILS_ROLL_PASS = "Pass (focused roll)"
BINDING_NAME_COMMANDERSPOILS_ROLL_PASSALL = "Pass on everything pending"
BINDING_NAME_COMMANDERSPOILS_ROLL_CYCLE = "Focus next roll"

local E = CommanderSpoilsEngine
local EV = COMMANDER_SPOILS_EVENTS
local DB   -- bound in Apply

local floor, ceil, max, min, format = math.floor, math.ceil, math.max, math.min, string.format
local WHITE = "Interface\\Buttons\\WHITE8X8"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

-- ---------------------------------------------------------------------------
-- Every shared local is declared here, before any function body.
--
-- In Lua a local declared AFTER a function body is not in that body's scope —
-- the reference silently compiles to a global read and returns nil. This
-- module hit that bug five times during development; `Harness/globals_lint.lua`
-- now catches it mechanically, and this block is how it stays caught.
-- ---------------------------------------------------------------------------
local mainFrame, header, modeStrip, body, statusLine
local pickupBand, corpseBand, rollBand
local rows, modeButtons, scopeButton
local viewOffset, pendingNew = 0, 0
local focusedRoll, mlSlot, armedCandidate
local activePickups = {}
local menuFrame, menuBuilder
local glowFrame, glowTextures, glowTarget = nil, nil, 0
local pulse, pulseDriver, pulseAlpha
local Layout, Repaint, PaintCorpse, OpenCorpse, CloseCorpse, ApplyPosition, Reconcile
-- Repainting is DIRTY-DRIVEN, not clock-driven. Rebuilding five list buffers
-- twice a second forever is what a loot window has no business costing, and
-- the only thing that genuinely needs a clock is the relative-age column —
-- which is one SetText per visible row and is now its own cheap pass.
local dirty, lastAgeSweep = true, 0
local function MarkDirty() dirty = true end
local LayoutRollBand, PaintCandidates
local fakeSlots = nil     -- set by the Try It buttons
local savedPointApplied = false

-- ---------------------------------------------------------------------------
-- Theme. One flat table; a widget reads a constant, never computes one.
-- Four exhaustive color jurisdictions (D18): item quality colors item names,
-- class color colors player names, gold/silver colors money, the accent colors
-- state. Quality never touches a background.
-- ---------------------------------------------------------------------------
local THEME = {
    font = "Fonts\\ARIALN.TTF",
    size = 11, small = 10,
    rowH = 16, headerH = 20, modeH = 16, statusH = 14,
    -- A roll row is three stacked lines that never share space: title (14),
    -- timer (8), buttons (16), plus 4 of padding. Dense drops the timer line.
    pickupH = 18, slotH = 26, rollH = 42, rollDenseH = 34, bandHeadH = 13,
    bg      = { 0.05, 0.05, 0.06, 0.94 },
    chrome  = { 0.10, 0.10, 0.12, 1 },
    band    = { 0.08, 0.08, 0.10, 1 },
    edge    = { 0.28, 0.28, 0.32, 1 },
    text    = { 0.88, 0.88, 0.90 },
    textDim = { 0.52, 0.52, 0.56 },
    accent  = { 1.00, 0.72, 0.28 },
    hover   = { 1, 1, 1, 0.07 },
    barBack = { 1, 1, 1, 0.05 },
    good    = { 0.45, 0.85, 0.45 },
    warn    = { 1.00, 0.72, 0.28 },
    bad     = { 0.95, 0.32, 0.30 },
    coin    = { 1.00, 0.82, 0.35 },
}

local FALLBACK_ACCENT = {
    AMBER = { 1, 0.72, 0.28 }, CYAN = { 0.35, 0.8, 0.95 },
    GREEN = { 0.45, 0.85, 0.45 }, WHITE = { 1, 1, 1 },
}

-- Commander_Console is optional and must never be hard-required: read the
-- canon live, with `or {}`, and soft-fail to a local preset.
local function ResolveAccent(key)
    if key == "CLASS" then
        local info = Commander.GetClassInfo and Commander.GetClassInfo()
        if info and info.color then
            return { info.color[1], info.color[2], info.color[3] }
        end
    end
    if FALLBACK_ACCENT[key] then return FALLBACK_ACCENT[key] end
    for _, color in ipairs(CommanderConsole_Colors or {}) do
        if color.value == key and color.r then
            return { color.r, color.g, color.b }
        end
    end
    return FALLBACK_ACCENT.AMBER
end

-- Appearance bakes into THEME once at login, the same contract Meters uses.
local function ResolveTheme()
    THEME.accent = ResolveAccent(CommanderSpoilsDB.AccentColor or "AMBER")
end

local QUALITY_FALLBACK = {
    [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 },
    [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 },
    [6] = { 0.90, 0.80, 0.50 },
}

-- Memoized. This is called once per row per paint, and returning a fresh table
-- each time was the module's largest remaining allocation.
local qualityCache = {}
local function QualityColor(quality)
    if type(quality) ~= "number" then return QUALITY_FALLBACK[1] end
    local cached = qualityCache[quality]
    if cached then return cached end
    local colors = _G.ITEM_QUALITY_COLORS
    local entry = colors and colors[quality]
    cached = (entry and entry.r) and { entry.r, entry.g, entry.b }
        or QUALITY_FALLBACK[quality] or QUALITY_FALLBACK[1]
    qualityCache[quality] = cached
    return cached
end

local classCache = {}
local function ClassColor(class)
    if not class then return THEME.text end
    local cached = classCache[class]
    if cached then return cached end
    local info = Commander.GetClassInfo and Commander.GetClassInfo(class)
    cached = (info and info.color) and { info.color[1], info.color[2], info.color[3] } or THEME.text
    classCache[class] = cached
    return cached
end

local function Coin(copper)
    if type(copper) ~= "number" then return "—" end
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        local ok, text = pcall(C_CurrencyInfo.GetCoinTextureString, copper, 12)
        if ok and text then return text end
    end
    return format("%dc", copper)
end

-- Compact money for the header, where a full coin string would jitter width.
local function CoinShort(copper)
    if type(copper) ~= "number" then return "—" end
    local gold = floor(copper / 10000)
    if gold >= 1000 then return format("%.1fkg", gold / 1000) end
    if gold >= 1 then return format("%dg %ds", gold, floor((copper % 10000) / 100)) end
    local silver = floor(copper / 100)
    if silver >= 1 then return format("%ds %dc", silver, copper % 100) end
    return format("%dc", copper)
end

local function ShortTime(seconds)
    seconds = max(0, floor(seconds or 0))
    if seconds < 60 then return seconds .. "s" end
    if seconds < 3600 then return format("%dm%02ds", floor(seconds / 60), seconds % 60) end
    return format("%dh%02dm", floor(seconds / 3600), floor((seconds % 3600) / 60))
end

local function Duration(seconds)
    seconds = max(0, floor(seconds or 0))
    local hours, mins = floor(seconds / 3600), floor((seconds % 3600) / 60)
    if hours > 0 then return format("%dh %dm", hours, mins) end
    return format("%dm", mins)
end

-- The suite's standard icon trim; an untrimmed icon's grey border is the
-- loudest tell of an amateur addon.
-- Every icon in this addon comes through here, which makes it the one place
-- the suite's shared recess has to be applied. The shading itself is
-- Commander_Events' (a RequiredDep, so always loaded); registering the icon is
-- what lets a setting changed mid-session reach the rows built long before it.
local styledIcons = {}

local function ApplyIconRecess(texture)
    if not Commander.DebossIcon then return end
    Commander.DebossIcon(texture, (DB and DB.IconRecess) or "SOFT")
end

local function TrimIcon(texture)
    texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    styledIcons[texture] = true
    ApplyIconRecess(texture)
end

local function RestyleIcons()
    for texture in pairs(styledIcons) do ApplyIconRecess(texture) end
end

-- ---------------------------------------------------------------------------
-- Widget helpers
-- ---------------------------------------------------------------------------
local function MakeText(parent, size, justify, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(THEME.font, size or THEME.size, "")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    local c = color or THEME.text
    fs:SetTextColor(c[1], c[2], c[3])
    return fs
end

local function Fill(parent, layer, color)
    local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
    tex:SetTexture(WHITE)
    tex:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    return tex
end

local function MakeEdge(frame)
    local edges = {}
    for i = 1, 4 do
        local tex = frame:CreateTexture(nil, "BORDER")
        tex:SetTexture(WHITE)
        tex:SetVertexColor(THEME.edge[1], THEME.edge[2], THEME.edge[3], THEME.edge[4])
        edges[i] = tex
    end
    edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)
    return edges
end

-- ARIALN has no shape glyphs on this client and an icon file can move across a
-- patch, so chrome icons are stacks of tinted quads: they can do neither.
-- Each entry is {xOffset, yOffset, width, height, rotationDegrees}.
local GLYPH_QUADS = {
    close  = { {0,0,10,2,45}, {0,0,10,2,-45} },                           -- an X
    filter = { {0,3,10,2,0}, {0,0,6,2,0}, {0,-3,3,2,0} },                 -- a funnel
    wipe   = { {0,3,9,2,0}, {0,0,2,7,0}, {-3,0,2,7,0}, {3,0,2,7,0} },     -- a bin
    farm   = { {0,-3,9,2,0}, {-3,1,2,6,0}, {0,2,2,8,0}, {3,1,2,6,0} },    -- a crop row
    expand = { {0,3,10,2,0}, {0,0,10,2,0}, {0,-3,10,2,0} },               -- stacked rules
}

local function MakeGlyphButton(parent, glyphName, width, height)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 21, height or THEME.headerH)
    btn.glyphName = glyphName        -- how the headless harness finds buttons
    btn.hover = Fill(btn, "HIGHLIGHT", THEME.hover)
    btn.hover:SetAllPoints()
    btn.quads = {}
    for i, spec in ipairs(GLYPH_QUADS[glyphName] or GLYPH_QUADS.close) do
        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetTexture(WHITE)
        tex:SetSize(spec[3], spec[4])
        tex:SetPoint("CENTER", btn, "CENTER", spec[1], spec[2])
        if spec[5] and spec[5] ~= 0 then tex:SetRotation(math.rad(spec[5])) end
        btn.quads[i] = tex
    end
    return btn
end

local function SetGlyphColor(btn, color)
    for _, tex in ipairs(btn.quads) do
        tex:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    end
end

local function MakeTextButton(parent, height, justify, name)
    local btn = CreateFrame("Button", name, parent)
    btn:SetHeight(height or THEME.modeH)
    btn.hover = Fill(btn, "HIGHLIGHT", THEME.hover)
    btn.hover:SetAllPoints()
    btn.label = MakeText(btn, THEME.small, justify or "CENTER")
    btn.label:SetPoint("LEFT", btn, "LEFT", 4, 0)
    btn.label:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
    return btn
end

local function OpenMenu(builder, anchor)
    if not menuFrame then return end
    menuBuilder = builder
    ToggleDropDownMenu(1, nil, menuFrame, anchor, 0, 0)
end

-- ===========================================================================
-- Screen effects. The only things outside the frame, because a screen-edge
-- warning and a full-screen flash are by definition not windows.
-- ===========================================================================
local function BuildGlow()
    glowFrame = CreateFrame("Frame", nil, UIParent)
    glowFrame:SetAllPoints(UIParent)
    glowFrame:SetFrameStrata("HIGH")   -- a warning must not sit behind the bars
    glowFrame:EnableMouse(false)
    glowTextures = {}
    local specs = {
        { "TOPLEFT", "TOPRIGHT", nil, 70 },
        { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 70 },
        { "TOPLEFT", "BOTTOMLEFT", 70, nil },
        { "TOPRIGHT", "BOTTOMRIGHT", 70, nil },
    }
    for i, spec in ipairs(specs) do
        local tex = glowFrame:CreateTexture(nil, "ARTWORK")
        tex:SetTexture(WHITE)
        tex:SetPoint(spec[1]); tex:SetPoint(spec[2])
        if spec[3] then tex:SetWidth(spec[3]) else tex:SetHeight(spec[4]) end
        -- Each edge fades AWAY from its own edge, so the orientation differs
        -- per side. The colour-object signature is not in FINDINGS, so it is
        -- probed: a flat edge is an acceptable degradation, an aborted login
        -- handler is not.
        if CreateColor then
            local orientation = (i <= 2) and "VERTICAL" or "HORIZONTAL"
            local opaque, clear = CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 0)
            local first = (i == 1 or i == 4) and clear or opaque
            local second = (i == 1 or i == 4) and opaque or clear
            pcall(tex.SetGradient, tex, orientation, first, second)
        end
        tex:SetBlendMode("ADD")
        glowTextures[i] = tex
    end
    glowFrame:SetAlpha(0)
    glowFrame:Hide()
end

local function SetGlow(intensity, color)
    glowTarget = intensity or 0
    if glowTarget > 0 and color then
        for _, tex in ipairs(glowTextures) do
            tex:SetVertexColor(color[1], color[2], color[3], 1)
        end
        glowFrame:Show()
    end
end

local function BuildPulse()
    pulse = WorldFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
    pulse:SetTexture(WHITE)
    pulse:SetAllPoints(WorldFrame)
    pulse:SetBlendMode("ADD")
    pulse:SetAlpha(0)
    pulseDriver = CreateFrame("Frame")
    pulseAlpha = 0
end

local function OnPulseDecay(_, elapsed)
    pulseAlpha = pulseAlpha - elapsed * 0.8
    if pulseAlpha <= 0 then
        pulseAlpha = 0
        pulse:SetAlpha(0)
        pulseDriver:SetScript("OnUpdate", nil)
        return
    end
    pulse:SetAlpha(pulseAlpha)
end

local function EpicPulse()
    pulse:SetVertexColor(0.55, 0.18, 0.85)
    pulseAlpha = 0.30
    pulse:SetAlpha(pulseAlpha)
    pulseDriver:SetScript("OnUpdate", OnPulseDecay)
end

-- ===========================================================================
-- Roll helpers
-- ===========================================================================
local function IsLive(roll)
    return not roll.resolved and roll.my == nil and (roll.canNeed or roll.canGreed)
end

-- Count and first-of are all the painters need, and they run at 10 Hz across
-- up to twelve rows. Neither allocates.
local function LiveRollCount()
    local count = 0
    for _, roll in ipairs(E.rolls) do
        if IsLive(roll) then count = count + 1 end
    end
    return count
end

local function FirstLiveRoll()
    for _, roll in ipairs(E.rolls) do
        if IsLive(roll) then return roll end
    end
end

local function FocusRoll()
    if focusedRoll and E.rollByID[focusedRoll] then
        local roll = E.rollByID[focusedRoll]
        if not roll.resolved then return roll end
    end
    return FirstLiveRoll()
end

-- Allocation is fine here: user-triggered, not painted.
local function CycleFocus()
    local live = {}
    for _, roll in ipairs(E.rolls) do
        if IsLive(roll) then live[#live + 1] = roll end
    end
    if #live == 0 then return end
    local current = FocusRoll()
    for i, roll in ipairs(live) do
        if roll == current then
            focusedRoll = live[(i % #live) + 1].id
            return
        end
    end
    focusedRoll = live[1].id
end

local function RollTimeLeftSeconds(roll)
    if roll.fake then
        return max(0, (roll.fakeUntil or 0) - GetTime())
    end
    if type(_G.GetLootRollTimeLeft) ~= "function" then return nil end
    local ok, ms = pcall(_G.GetLootRollTimeLeft, roll.id)
    if not ok or not ms then return nil end
    return ms / 1000
end

-- ---------------------------------------------------------------------------
-- Urgency. Sound and glow are computed ACROSS the whole band, once per stage
-- transition — six greens expiring in the same second is one chime, not six.
-- ---------------------------------------------------------------------------
local contestStage = 0

local function UpdateUrgency()
    local soonest, topQuality, live = nil, 0, 0
    for _, roll in ipairs(E.rolls) do
        if IsLive(roll) then
            live = live + 1
            local left = RollTimeLeftSeconds(roll)
            if left and (not soonest or left < soonest) then soonest = left end
            if (roll.quality or 0) > topQuality then topQuality = roll.quality or 0 end
        end
    end
    if live == 0 then
        if contestStage ~= 0 then
            contestStage = 0
            SetGlow(0)
        end
        return
    end
    local left = soonest or 999
    local stage = 1
    if left <= (DB.RollCriticalAt or 5) then stage = 3
    elseif left <= (DB.RollWarnAt or 15) then stage = 2 end

    if stage > contestStage and stage >= 2 and DB.SoundRollOpen then
        PlaySound(stage == 3 and SOUNDKIT.RAID_WARNING
            or SOUNDKIT.IG_QUEST_LIST_COMPLETE, "Master")
    end
    contestStage = stage

    -- A grey BoE must not strobe the screen.
    if DB.RollEdgeGlow and stage >= 2 and topQuality >= (DB.RollEdgeGlowMinQuality or 2) then
        SetGlow(stage == 3 and 0.45 or 0.15, stage == 3 and THEME.bad or THEME.warn)
    else
        SetGlow(0)
    end
end

-- ===========================================================================
-- Bands
--
-- Each band is a plain child Frame stacked by Layout(). A band with nothing to
-- say is hidden and contributes zero height, so the frame is exactly as tall
-- as what it currently has to tell you.
-- ===========================================================================
local function MakeBand(parent, name)
    local band = CreateFrame("Frame", name, parent)
    band.fill = Fill(band, "BACKGROUND", THEME.band)
    band.fill:SetAllPoints()
    band.rule = band:CreateTexture(nil, "BORDER")
    band.rule:SetTexture(WHITE)
    band.rule:SetHeight(1)
    band.rule:SetPoint("TOPLEFT"); band.rule:SetPoint("TOPRIGHT")
    band.rule:SetVertexColor(THEME.edge[1], THEME.edge[2], THEME.edge[3], 1)
    band.caption = MakeText(band, THEME.small, "LEFT", THEME.textDim)
    band.caption:SetPoint("TOPLEFT", band, "TOPLEFT", 6, -2)
    band.captionRight = MakeText(band, THEME.small, "RIGHT", THEME.textDim)
    band.captionRight:SetPoint("TOPRIGHT", band, "TOPRIGHT", -6, -2)
    band:Hide()
    return band
end

-- ---- pickups (what used to be a separate toast frame) --------------------
local PICKUP_TIME = 5

local function BuildPickupRows()
    pickupBand.rows = {}
    for i = 1, 4 do
        local row = CreateFrame("Frame", "CommanderSpoilsPickupRow" .. i, pickupBand)
        row:SetHeight(THEME.pickupH)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(THEME.pickupH - 4, THEME.pickupH - 4)
        row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
        TrimIcon(row.icon)
        row.label = MakeText(row, THEME.size, "LEFT")
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.right = MakeText(row, THEME.small, "RIGHT", THEME.textDim)
        row.right:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.right:SetWidth(64)
        row.label:SetPoint("RIGHT", row.right, "LEFT", -4, 0)
        row:Hide()
        pickupBand.rows[i] = row
    end
end

local function RedrawPickups()
    local now = GetTime()
    for i = #activePickups, 1, -1 do
        if activePickups[i].expires <= now then table.remove(activePickups, i) end
    end
    for i, row in ipairs(pickupBand.rows) do
        local entry = activePickups[i]
        if entry then
            row.icon:SetTexture(entry.icon or QUESTION)
            local label = entry.name or "?"
            if entry.total > 1 then label = label .. "  x" .. entry.total end
            row.label:SetText(label)
            local color = QualityColor(entry.quality)
            row.label:SetTextColor(color[1], color[2], color[3])
            row.right:SetText((entry.value and entry.value > 0) and CoinShort(entry.value) or "")
            row:Show()
        else
            row:Hide()
        end
    end
    if Reconcile then Reconcile() end
end

-- Farming one item is the case that breaks a naive stack: 200 identical rows
-- an hour is how a feature gets switched off for good. A repeat merges into
-- its existing row and refreshes the timer.
local function PushPickup(name, icon, quality, itemID, count, value)
    if DB.WireQuietWhenOpen and DB.Expanded and DB.ViewMode == "FEED" and viewOffset == 0 then
        return
    end
    local now = GetTime()
    if itemID then
        for _, entry in ipairs(activePickups) do
            if entry.itemID == itemID then
                entry.total = entry.total + (count or 1)
                entry.value = (entry.value or 0) + (value or 0)
                entry.expires = now + PICKUP_TIME
                RedrawPickups()
                -- Scheduled on BOTH paths: a merge that only refreshed the
                -- expiry left the last notice of every session on screen.
                C_Timer.After(PICKUP_TIME + 0.1, RedrawPickups)
                return
            end
        end
    end
    table.insert(activePickups, 1, {
        name = name, icon = icon, quality = quality, itemID = itemID,
        total = count or 1, value = value or 0, expires = now + PICKUP_TIME,
    })
    while #activePickups > 4 do table.remove(activePickups) end
    RedrawPickups()
    C_Timer.After(PICKUP_TIME + 0.1, RedrawPickups)
end

-- ---- corpse --------------------------------------------------------------
local function BuildCorpseRows()
    corpseBand.rows = {}
    for i = 1, 20 do
        local row = CreateFrame("Button", "CommanderSpoilsSlotRow" .. i, corpseBand)
        row:SetHeight(THEME.slotH)
        row.hover = Fill(row, "HIGHLIGHT", THEME.hover)
        row.hover:SetAllPoints()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(THEME.slotH - 6, THEME.slotH - 6)
        row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
        TrimIcon(row.icon)
        row.name = MakeText(row, THEME.size, "LEFT")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 6)
        row.name:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.sub = MakeText(row, THEME.small, "LEFT", THEME.textDim)
        row.sub:SetPoint("LEFT", row.icon, "RIGHT", 6, -6)
        row.confirm = {}
        for j, spec in ipairs({ { "TAKE", true }, { "CANCEL", false } }) do
            local btn = MakeTextButton(row, 13)
            btn:SetWidth(56)
            btn:SetPoint("RIGHT", row, "RIGHT", -4 - (j - 1) * 60, -6)
            btn.label:SetText(spec[1])
            btn.take = spec[2]
            btn:Hide()
            row.confirm[j] = btn
        end
        row:Hide()
        corpseBand.rows[i] = row
    end
    -- Master-loot candidates are rows in the same band: assigning is one
    -- operation with the slot list, and a second window would be a second
    -- thing to position.
    corpseBand.candidates = {}
    for i = 1, 40 do
        local row = CreateFrame("Button", "CommanderSpoilsCandidateRow" .. i, corpseBand)
        row:SetHeight(14)
        row.hover = Fill(row, "HIGHLIGHT", THEME.hover)
        row.hover:SetAllPoints()
        row.name = MakeText(row, THEME.small, "LEFT")
        row.name:SetPoint("LEFT", row, "LEFT", 24, 0)
        row.state = MakeText(row, THEME.small, "RIGHT", THEME.textDim)
        row.state:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row:Hide()
        corpseBand.candidates[i] = row
    end
end

local candidateScratch = {}
local function CandidateOrder(a, b)
    if a.online ~= b.online then return a.online end
    return (a.name or "") < (b.name or "")
end

PaintCandidates = function()
    for i = #candidateScratch, 1, -1 do candidateScratch[i] = nil end
    if mlSlot then
        for _, entry in ipairs(E.MasterCandidates(mlSlot)) do
            candidateScratch[#candidateScratch + 1] = entry
        end
        table.sort(candidateScratch, CandidateOrder)
    end
    for i, row in ipairs(corpseBand.candidates) do
        local entry = candidateScratch[i]
        if entry then
            local cc = ClassColor(entry.class)
            row.name:SetText(entry.name)
            row.name:SetTextColor(cc[1], cc[2], cc[3])
            local state = ""
            if not entry.online then state = "offline"
            elseif entry.dead then state = "dead" end
            if armedCandidate == entry.index then
                state = "CONFIRM →"
                row.state:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])
            else
                row.state:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
            end
            row.state:SetText(state)
            row:SetAlpha(entry.online and 1 or 0.5)
            -- The RAW probe index, never the display position: GiveMasterLoot
            -- takes the index the candidate was FOUND at.
            row.candidateIndex, row.slot = entry.index, mlSlot
            row:Show()
        else
            row:Hide()
        end
    end
    return #candidateScratch
end

local function CorpseSlots()
    return fakeSlots or E.slots
end

PaintCorpse = function()
    local slots = CorpseSlots()
    local isML = E.LootMethod() == 2 and E.IsMasterLooter()
    local y, shown = THEME.bandHeadH, 0
    for i, row in ipairs(corpseBand.rows) do
        local cap = DB.FixedSize and (DB.MaxSlotRows or 8) or #corpseBand.rows
        local slot = (i <= cap) and slots[i] or nil
        if slot then
            shown = shown + 1
            local qc = QualityColor(slot.quality)
            row.icon:SetTexture(slot.icon or QUESTION)
            local label = slot.name or "Loading…"
            if (slot.count or 1) > 1 then label = label .. "  x" .. slot.count end
            row.name:SetText(label)
            if slot.cached then
                row.name:SetTextColor(qc[1], qc[2], qc[3])
            else
                row.name:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
            end
            row.assignable = isML and (slot.quality or 0) >= (_G.MASTER_LOOT_THREHOLD or 4)
            local sub = ""
            if slot.slotType == 2 then sub = "coin"
            elseif slot.slotType == 3 then sub = "currency" end
            if row.assignable then sub = "ASSIGN ▸" end
            local binding = E.bindSlot == slot.slot
            for _, btn in ipairs(row.confirm) do btn:SetShown(binding) end
            if binding then
                sub = "BINDS TO YOU"
                row.sub:SetTextColor(THEME.bad[1], THEME.bad[2], THEME.bad[3])
            else
                row.sub:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
            end
            row.sub:SetText(sub)
            row.slot, row.link = slot.slot, slot.link
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", corpseBand, "TOPLEFT", 0, -y)
            row:SetPoint("RIGHT", corpseBand, "RIGHT", 0, 0)
            row:Show()
            y = y + THEME.slotH
        else
            row:Hide()
        end
    end
    local candidates = PaintCandidates()
    for i = 1, candidates do
        local row = corpseBand.candidates[i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", corpseBand, "TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", corpseBand, "RIGHT", 0, 0)
        y = y + 14
    end
    corpseBand.caption:SetText(fakeSlots and "CORPSE · TEST" or "CORPSE")
    local total = #slots
    corpseBand.captionRight:SetText(total > shown and format("%d of %d — take some to see the rest", shown, total)
        or (shown > 0 and (shown .. " to take") or "empty"))
    corpseBand:SetHeight(max(THEME.bandHeadH + 2, y + 2))
    corpseBand:SetShown(shown > 0)
end

-- ---- rolls ---------------------------------------------------------------
local metaScratch = {}

local function BuildRollRows()
    rollBand.rows = {}
    for i = 1, 12 do
        local row = CreateFrame("Frame", "CommanderSpoilsRollRow" .. i, rollBand)
        row:SetHeight(THEME.rollH)
        row.hover = Fill(row, "HIGHLIGHT", THEME.hover)
        row.hover:SetAllPoints()
        row.caret = Fill(row, "ARTWORK", THEME.accent)
        row.caret:SetPoint("TOPLEFT"); row.caret:SetPoint("BOTTOMLEFT")
        row.caret:SetWidth(2)
        row.caret:Hide()

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(26, 26)
        row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 7, -3)
        TrimIcon(row.icon)
        row.iconEdge = {}
        for j = 1, 4 do
            row.iconEdge[j] = row:CreateTexture(nil, "OVERLAY")
            row.iconEdge[j]:SetTexture(WHITE)
        end
        row.iconEdge[1]:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -1, 1)
        row.iconEdge[1]:SetPoint("TOPRIGHT", row.icon, "TOPRIGHT", 1, 1)
        row.iconEdge[1]:SetHeight(1)
        row.iconEdge[2]:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMLEFT", -1, -1)
        row.iconEdge[2]:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 1, -1)
        row.iconEdge[2]:SetHeight(1)
        row.iconEdge[3]:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -1, 1)
        row.iconEdge[3]:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMLEFT", -1, -1)
        row.iconEdge[3]:SetWidth(1)
        row.iconEdge[4]:SetPoint("TOPRIGHT", row.icon, "TOPRIGHT", 1, 1)
        row.iconEdge[4]:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 1, -1)
        row.iconEdge[4]:SetWidth(1)

        row.clock = MakeText(row, THEME.small, "RIGHT", THEME.textDim)
        row.clock:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -3)
        row.clock:SetWidth(42)

        row.name = MakeText(row, THEME.size, "LEFT")
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
        row.name:SetPoint("RIGHT", row.clock, "LEFT", -6, 0)

        row.meta = MakeText(row, THEME.small, "LEFT", THEME.textDim)
        row.meta:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
        row.meta:SetWidth(96)

        row.track = Fill(row, "BACKGROUND", THEME.barBack)
        row.track:SetPoint("LEFT", row.meta, "RIGHT", 6, 0)
        row.track:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.track:SetPoint("TOP", row.name, "BOTTOM", 0, -7)
        row.track:SetHeight(3)
        row.bar = Fill(row, "ARTWORK", THEME.good)
        row.bar:SetPoint("TOPLEFT", row.track, "TOPLEFT")
        row.bar:SetPoint("BOTTOM", row.track, "BOTTOM")
        row.bar:SetWidth(0.001)

        -- Line 3, left of the buttons: who has decided so far.
        row.note = MakeText(row, THEME.small, "RIGHT", THEME.textDim)
        row.note:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 3)
        row.note:SetWidth(96)

        row.buttons = {}
        for j, spec in ipairs({ { 1, "NEED" }, { 2, "GREED" }, { 0, "PASS" } }) do
            local btn = MakeTextButton(row, 14)
            btn:SetWidth(48)
            btn:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 37 + (j - 1) * 50, 2)
            btn.rollType, btn.baseLabel = spec[1], spec[2]
            btn.strike = Fill(btn, "OVERLAY", THEME.textDim)
            btn.strike:SetPoint("LEFT", btn, "LEFT", 6, 0)
            btn.strike:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
            btn.strike:SetHeight(1)
            btn.strike:Hide()
            row.buttons[j] = btn
        end
        row.verdict = MakeText(row, THEME.small, "LEFT")
        row.verdict:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 37, 3)
        row.verdict:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.verdict:Hide()
        row:Hide()
        rollBand.rows[i] = row
    end
    rollBand.passAll = MakeTextButton(rollBand, 14)
    rollBand.passAll:SetWidth(84)
    rollBand.passAll.label:SetText("PASS ALL")
    rollBand.passAll:Hide()
end

local function PaintRollRow(row, roll, dense, focus)
    -- Dense mode splits the note and the buttons onto the same line, so a
    -- 34px row still has a clear track above them.
    row:SetHeight(dense and THEME.rollDenseH or THEME.rollH)
    local qc = QualityColor(roll.quality)
    row.icon:SetTexture(roll.icon or QUESTION)
    for _, tex in ipairs(row.iconEdge) do tex:SetVertexColor(qc[1], qc[2], qc[3], 1) end

    local name = roll.name
    if not name and roll.itemID then
        local cached = E.Meta(roll.itemID)
        name = cached and cached.name
    end
    name = name or "Loading…"
    if (roll.count or 1) > 1 then name = name .. "  x" .. roll.count end
    row.name:SetText(name)
    row.name:SetTextColor(qc[1], qc[2], qc[3])
    row.name:SetAlpha(1)

    for i = #metaScratch, 1, -1 do metaScratch[i] = nil end
    if roll.bop then metaScratch[#metaScratch + 1] = "BoP" end
    local meta = roll.itemID and E.Meta(roll.itemID)
    if meta and meta.equipLoc and _G[meta.equipLoc] then
        metaScratch[#metaScratch + 1] = _G[meta.equipLoc]
    end
    row.meta:SetText(table.concat(metaScratch, " · "))
    row.meta:SetShown(not dense)
    if roll.bop then
        row.meta:SetTextColor(0.95, 0.45, 0.40)
    else
        row.meta:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
    end

    row.caret:SetShown(focus == roll)
    row.roll = roll

    if roll.resolved then
        row.track:Hide(); row.bar:Hide(); row.clock:SetText("")
        for _, btn in ipairs(row.buttons) do btn:Hide() end
        row.note:SetText("")
        row.verdict:Show()
        local text, color = "RESOLVED", THEME.textDim
        if roll.cancelled then
            text = "WITHDRAWN"
        elseif roll.orphaned then
            text = "NO RESULT — the server stopped reporting"
        elseif roll.won then
            text = roll.myRoll and format("WON  ·  %s %d", E.RollTypeName[roll.my] or "ROLL", roll.myRoll) or "WON"
            color = THEME.accent
        elseif roll.allPassed then
            text = "EVERYONE PASSED"
        elseif roll.missed then
            text, color = "MISSED — no roll cast", THEME.bad
        elseif roll.winner then
            local suffix = roll.winnerRoll and format(" %s %d",
                E.RollTypeName[roll.winnerType] or "", roll.winnerRoll) or ""
            text, color = "LOST — " .. roll.winner .. suffix, ClassColor(roll.winnerClass)
        end
        row.verdict:SetText(text)
        row.verdict:SetTextColor(color[1], color[2], color[3])
        return
    end
    row.verdict:Hide()

    -- The bind confirm takes over the row in place, so the corpse stays visible.
    if roll.confirm then
        row.track:Hide(); row.bar:Hide(); row.clock:SetText("")
        row.note:SetText(roll.confirm.reason or "This will bind to you.")
        row.note:SetTextColor(THEME.bad[1], THEME.bad[2], THEME.bad[3])
        for i, btn in ipairs(row.buttons) do
            btn.confirmMode = (i <= 2)
            btn.strike:Hide()
            btn:SetAlpha(1)
            if i == 1 then btn.label:SetText("CONFIRM"); btn:Show()
            elseif i == 2 then btn.label:SetText("BACK"); btn:Show()
            else btn:Hide() end
        end
        return
    end
    for _, btn in ipairs(row.buttons) do btn.confirmMode = nil end

    -- Nothing to decide: with neither Need nor Greed available the row is pure
    -- noise in a 25-man, so it collapses to one line carrying the server's own
    -- reason — and it still goes in the log.
    if DB.CollapseIneligible and not roll.canNeed and not roll.canGreed then
        row:SetHeight(THEME.rollDenseH - 8)
        row.track:Hide(); row.bar:Hide()
        for _, btn in ipairs(row.buttons) do btn:Hide() end
        row.note:SetText(_G["LOOT_ROLL_INELIGIBLE_REASON" .. tostring(roll.reasonNeed)]
            or "You cannot roll on this item.")
        row.note:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
        row.name:SetAlpha(0.6)
        local seconds = RollTimeLeftSeconds(roll)
        row.clock:SetText(seconds and ShortTime(seconds) or "")
        return
    end

    local seconds = RollTimeLeftSeconds(roll)
    local total = roll.rollTime and (roll.rollTime / 1000) or nil
    -- Dense mode drops the timer STRIP, not the countdown: the number moves up
    -- beside the item name so nothing is ever drawn over anything.
    row.track:SetShown(not dense)
    row.bar:SetShown(not dense)
    if seconds and total and total > 0 then
        local frac = max(0, min(1, seconds / total))
        row.bar:SetWidth(max(0.001, row.track:GetWidth() * frac))
        local color = THEME.good
        if seconds <= (DB.RollCriticalAt or 5) then color = THEME.bad
        elseif seconds <= (DB.RollWarnAt or 15) then color = THEME.warn end
        row.bar:SetVertexColor(color[1], color[2], color[3], 1)
    else
        -- No reliable denominator after a /reload: a numeric countdown is
        -- honest, a bar against an invented total is not.
        row.bar:SetWidth(0.001)
    end
    row.clock:SetText(seconds and (seconds <= 10 and format("%d", ceil(seconds)) or ShortTime(seconds)) or "—")
    if seconds and seconds <= (DB.RollCriticalAt or 5) then
        row.clock:SetTextColor(THEME.bad[1], THEME.bad[2], THEME.bad[3])
    else
        row.clock:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
    end

    -- "3 rolled", never "3/5": numPlayers counts players who have DECIDED, and
    -- group size is not eligibility. Inventing a denominator is a lie that
    -- eventually surfaces as a bug.
    local decided = roll.decided or 0
    row.note:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
    if roll.auto then
        row.note:SetText("auto-passed — below your quality floor")
        row.note:SetTextColor(THEME.warn[1], THEME.warn[2], THEME.warn[3])
    elseif roll.my ~= nil then
        row.note:SetText(format("you chose %s   ·   %d rolled", E.RollTypeName[roll.my] or "?", decided))
    elseif decided > 0 then
        row.note:SetText(format("%d rolled", decided))
    else
        row.note:SetText("")
    end
    row.note:Show()

    local guarded = not roll.auto and GetTime() < (roll.guardUntil or 0)
    for _, btn in ipairs(row.buttons) do
        btn.label:SetText(btn.baseLabel)
        local eligible, reason = true, nil
        if btn.rollType == 1 and not roll.canNeed then
            eligible = false
            reason = _G["LOOT_ROLL_INELIGIBLE_REASON" .. tostring(roll.reasonNeed)]
                or "You cannot roll Need on this item."
        elseif btn.rollType == 2 and not roll.canGreed then
            eligible = false
            reason = _G["LOOT_ROLL_INELIGIBLE_REASON" .. tostring(roll.reasonGreed)]
                or "You cannot roll Greed on this item."
        end
        btn.eligible, btn.reason = eligible, reason
        btn.strike:SetShown(not eligible)
        btn:SetAlpha(not eligible and 0.35 or (guarded and 0.55) or 1)
        local color = (roll.my == btn.rollType) and THEME.accent or THEME.text
        btn.label:SetTextColor(color[1], color[2], color[3])
        btn:Show()
    end
end

-- D10 promises the guard re-arms "on any row that moves more than 8px during
-- a collapse". It was set once at creation and never touched again — and rows
-- reflow constantly, which is the exact click it exists to eat.
local lastRollTop = {}

LayoutRollBand = function()
    local count = #E.rolls
    if count == 0 then
        -- The empty branch must still tear the band down: leaving the rows
        -- shown inside a frame that stays visible painted ghost rolls over
        -- the pane list.
        for _, row in ipairs(rollBand.rows) do row:Hide() end
        rollBand.passAll:Hide()
        rollBand:SetHeight(1)
        rollBand:Hide()
        SetGlow(0)
        contestStage = 0
        for id in pairs(lastRollTop) do lastRollTop[id] = nil end
        return
    end
    local dense = count > 4
    local focus = FocusRoll()
    local y = THEME.bandHeadH
    local cap = DB.FixedSize and (DB.MaxRollRows or 3) or #rollBand.rows
    local shown = min(count, cap, #rollBand.rows)
    for i, row in ipairs(rollBand.rows) do
        local roll = E.rolls[i]
        if roll and i <= shown then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", rollBand, "TOPLEFT", 0, -y)
            row:SetPoint("RIGHT", rollBand, "RIGHT", 0, 0)
            local moved = lastRollTop[roll.id]
            if moved and math.abs(moved - y) > 8 and not roll.resolved then
                roll.guardUntil = max(roll.guardUntil or 0,
                    GetTime() + (DB.RollGuardMs or 300) / 1000)
            end
            lastRollTop[roll.id] = y
            PaintRollRow(row, roll, dense, focus)
            row:Show()
            y = y + row:GetHeight() + 1
        else
            row:Hide()
        end
    end
    local live = LiveRollCount()
    rollBand.caption:SetText("ROLLS")
    -- Overflow is stated, never silent: a live Need you cannot see is the
    -- exact failure the module exists to prevent.
    rollBand.captionRight:SetText(count > shown and format("+%d MORE", count - shown)
        or (live > 0 and (live .. " live") or ""))
    if live >= 3 then
        rollBand.passAll:ClearAllPoints()
        rollBand.passAll:SetPoint("TOPRIGHT", rollBand, "TOPRIGHT", -4, -y)
        rollBand.passAll:Show()
        y = y + 15
    else
        rollBand.passAll:Hide()
    end
    rollBand:SetHeight(y + 2)
    rollBand:Show()
end

-- ===========================================================================
-- Header, mode strip, body, status
-- ===========================================================================
local MODES = { "FEED", "HAUL", "ROLLS", "BAGS", "PARTY" }
local MODE_HELP = {
    FEED  = "What just happened — every pickup, every roll, every copper.",
    HAUL  = "What this scope gave you, gathered by item.",
    ROLLS = "Who won what, what you rolled, and every roll you missed.",
    BAGS  = "Why your bags are full.",
    PARTY = "Where the loot is going.",
}
local SCOPES = { "SESSION", "RUN", "HOUR" }

local function ScopeSegment()
    -- Ending a farm while its scope is selected used to leave the button
    -- reading FARM over an empty fold with no FARM entry left to un-select.
    if DB.ViewScope == "FARM" and not E.FarmActive() then
        DB.ViewScope = "SESSION"
    end
    return E.SegmentFor(DB.ViewScope)
end

local function BuildHeader()
    header = CreateFrame("Frame", nil, mainFrame)
    header:SetHeight(THEME.headerH)
    header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT")
    header.fill = Fill(header, "BACKGROUND", THEME.chrome)
    header.fill:SetAllPoints()
    header.rule = header:CreateTexture(nil, "BORDER")
    header.rule:SetTexture(WHITE)
    header.rule:SetHeight(1)
    header.rule:SetPoint("BOTTOMLEFT"); header.rule:SetPoint("BOTTOMRIGHT")
    header.rule:SetVertexColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.5)

    header.title = MakeText(header, THEME.small, "LEFT", THEME.accent)
    header.title:SetPoint("LEFT", header, "LEFT", 6, 0)
    header.title:SetText("SPOILS")

    -- The header never changes meaning when you switch panes. A dashboard
    -- whose top-line numbers redefine themselves under a tab click is the
    -- classic sin.
    header.value = MakeTextButton(header, THEME.headerH, "LEFT")
    header.items = MakeText(header, THEME.small, "LEFT", THEME.text)
    header.best = MakeText(header, THEME.small, "LEFT")
    _G.CommanderSpoilsHeaderBest = header.best   -- harness hook
    header.bags = MakeTextButton(header, THEME.headerH, "RIGHT")

    header.glyphs = {}
    local order = { "filter", "farm", "wipe", "expand" }
    for i, name in ipairs(order) do
        local btn = MakeGlyphButton(header, name)
        btn:SetPoint("RIGHT", header, "RIGHT", -(#order - i) * 21, 0)
        SetGlyphColor(btn, THEME.textDim)
        header.glyphs[name] = btn
    end
end

-- Laid out from the real width every time it changes. Fixed fields keep their
-- size; the best-find is elastic and hides below the width where it would
-- start colliding rather than rendering on top of its neighbour.
local HEADER_TITLE_W, HEADER_VALUE_W = 36, 92
local HEADER_ITEMS_W, HEADER_BAGS_W, HEADER_GLYPHS_W = 50, 46, 84
local headerWidth = 0

local function LayoutHeader(width)
    if width == headerWidth then return end
    headerWidth = width
    local left = 6 + HEADER_TITLE_W
    header.value:ClearAllPoints()
    header.value:SetPoint("LEFT", header, "LEFT", left, 0)
    header.value:SetWidth(HEADER_VALUE_W)
    left = left + HEADER_VALUE_W + 4

    -- The item count yields too. Below ~330 there is no room for it and the
    -- elastic field alone cannot absorb the collision.
    header.items:ClearAllPoints()
    if width >= 330 then
        header.items:SetPoint("LEFT", header, "LEFT", left, 0)
        header.items:SetWidth(HEADER_ITEMS_W)
        header.items:Show()
        left = left + HEADER_ITEMS_W + 6
    else
        header.items:Hide()
    end

    local right = HEADER_GLYPHS_W + 4
    header.bags:ClearAllPoints()
    header.bags:SetPoint("RIGHT", header, "RIGHT", -right, 0)
    header.bags:SetWidth(HEADER_BAGS_W)
    right = right + HEADER_BAGS_W + 6

    local spare = width - left - right
    if spare >= 60 then
        header.best:ClearAllPoints()
        header.best:SetPoint("LEFT", header, "LEFT", left, 0)
        header.best:SetWidth(spare)
        header.best:Show()
    else
        header.best:Hide()
    end
end

local function BuildModeStrip()
    modeStrip = CreateFrame("Frame", nil, mainFrame)
    modeStrip:SetHeight(THEME.modeH)
    modeStrip.fill = Fill(modeStrip, "BACKGROUND", { 0.07, 0.07, 0.09, 1 })
    modeStrip.fill:SetAllPoints()
    modeButtons = {}
    for i, mode in ipairs(MODES) do
        -- Named for the headless harness, which measures them to prove the
        -- strip fits the frame at every supported width.
        local btn = MakeTextButton(modeStrip, THEME.modeH, nil, "CommanderSpoilsModeButton" .. i)
        -- Width is set by LayoutModeStrip from the real frame width; five
        -- fixed 62px buttons plus a 90px scope needs 418 and overflowed a
        -- narrow frame.
        btn:SetPoint("TOP", modeStrip, "TOP", 0, 0)
        btn:SetPoint("BOTTOM", modeStrip, "BOTTOM", 0, 0)
        btn.mode = mode
        btn:SetScript("OnClick", function()
            DB.ViewMode = mode
            viewOffset, pendingNew = 0, 0
            Commander.Notify(EV.UPDATE)
        end)
        Commander.UI.AttachTooltip(btn, mode, MODE_HELP[mode])
        modeButtons[i] = btn
    end
    scopeButton = MakeTextButton(modeStrip, THEME.modeH, "RIGHT", "CommanderSpoilsScopeButton")
    scopeButton:SetPoint("RIGHT", modeStrip, "RIGHT", -4, 0)
    scopeButton:SetScript("OnClick", function(self)
        if DB.ViewMode == "BAGS" then return end
        OpenMenu(function()
            for _, scope in ipairs(SCOPES) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = scope
                info.checked = DB.ViewScope == scope
                info.func = function() DB.ViewScope = scope; Commander.Notify(EV.UPDATE) end
                UIDropDownMenu_AddButton(info)
            end
            if E.FarmActive() then
                local info = UIDropDownMenu_CreateInfo()
                info.text = "FARM"
                info.checked = DB.ViewScope == "FARM"
                info.func = function() DB.ViewScope = "FARM"; Commander.Notify(EV.UPDATE) end
                UIDropDownMenu_AddButton(info)
            end
        end, self)
    end)
end

-- Body row columns scale with the frame too: fixed 96/78 columns left an item
-- name 64px at the narrow end.
local rowColumnWidth = 0
local ROLL_BUTTON_RIGHT = 37 + 3 * 50   -- x where the PASS button ends
local function LayoutRowColumns(width)
    if width == rowColumnWidth or not rows then return end
    rowColumnWidth = width
    -- The roll note starts after the last button, never on top of it.
    if rollBand and rollBand.rows then
        local noteW = max(0, width - ROLL_BUTTON_RIGHT - 12)
        for _, row in ipairs(rollBand.rows) do
            row.note:SetWidth(max(40, min(96, noteW)))
            row.note:SetShown(noteW >= 40)
        end
    end
    local rightW = max(52, min(78, floor(width * 0.22)))
    local midW = max(60, min(96, floor(width * 0.27)))
    for _, row in ipairs(rows) do
        row.right:SetWidth(rightW)
        row.mid:SetWidth(midW)
    end
end

local modeStripWidth = 0
local function LayoutModeStrip(width)
    if width == modeStripWidth then return end
    modeStripWidth = width
    local scopeW = min(90, max(56, floor(width * 0.24)))
    scopeButton:SetWidth(scopeW)
    local available = width - 8 - scopeW - 4
    local each = max(40, floor(available / #MODES))
    for i, btn in ipairs(modeButtons) do
        btn:SetWidth(each)
        btn:ClearAllPoints()
        btn:SetPoint("TOP", modeStrip, "TOP", 0, 0)
        btn:SetPoint("BOTTOM", modeStrip, "BOTTOM", 0, 0)
        btn:SetPoint("LEFT", modeStrip, "LEFT", 4 + (i - 1) * each, 0)
    end
end

local function BuildRow(parent, index)
    local row = CreateFrame("Button", "CommanderSpoilsRow" .. index, parent)
    row:SetHeight(THEME.rowH)
    row.hover = Fill(row, "HIGHLIGHT", THEME.hover)
    row.hover:SetAllPoints()
    row.track = Fill(row, "BACKGROUND", THEME.barBack)
    row.track:SetAllPoints()
    row.track:Hide()
    -- A 2px accent tick in the left gutter marks your OWN pickups: you should
    -- be able to find your loot in a group feed by scanning two pixels.
    row.tick = Fill(row, "ARTWORK", THEME.accent)
    row.tick:SetPoint("TOPLEFT"); row.tick:SetPoint("BOTTOMLEFT")
    row.tick:SetWidth(2)
    row.tick:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(THEME.rowH - 3, THEME.rowH - 3)
    row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
    TrimIcon(row.icon)
    row.name = MakeText(row, THEME.size, "LEFT")
    row.mid = MakeText(row, THEME.small, "RIGHT", THEME.textDim)
    row.mid:SetWidth(96)
    row.right = MakeText(row, THEME.small, "RIGHT", THEME.textDim)
    row.right:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.right:SetWidth(78)
    row.mid:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
    row.name:SetPoint("RIGHT", row.mid, "LEFT", -6, 0)
    row.section = MakeText(row, THEME.small, "CENTER", THEME.textDim)
    row.section:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.section:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.section:Hide()
    row:Hide()
    return row
end

local function BuildBody()
    body = CreateFrame("Frame", nil, mainFrame)
    body.empty = MakeText(body, THEME.size, "CENTER", THEME.textDim)
    body.empty:SetPoint("TOP", body, "TOP", 0, -26)
    body.empty:SetPoint("LEFT"); body.empty:SetPoint("RIGHT")
    body.emptyHint = MakeText(body, THEME.small, "CENTER", THEME.textDim)
    body.emptyHint:SetPoint("TOP", body.empty, "BOTTOM", 0, -6)
    body.emptyHint:SetPoint("LEFT"); body.emptyHint:SetPoint("RIGHT")
    rows = {}
    body:EnableMouseWheel(true)
    body:SetScript("OnMouseWheel", function(_, delta)
        local step = IsShiftKeyDown() and (DB.MaxRows or 12) or 1
        viewOffset = max(0, viewOffset - delta * step)
        if viewOffset == 0 then pendingNew = 0 end
        MarkDirty()
        Repaint()
    end)
end

local function BuildStatus()
    statusLine = CreateFrame("Frame", nil, mainFrame)
    statusLine:SetHeight(THEME.statusH)
    statusLine.fill = Fill(statusLine, "BACKGROUND", THEME.chrome)
    statusLine.fill:SetAllPoints()
    -- The left field is anchored on BOTH sides so it truncates instead of
    -- running underneath the filters and the row count. Anchoring only LEFT
    -- is why the bottom of the window was three strings drawn on top of
    -- each other at 350px.
    statusLine.left = MakeText(statusLine, THEME.small, "LEFT", THEME.textDim)
    statusLine.left:SetPoint("LEFT", statusLine, "LEFT", 6, 0)
    statusLine.right = MakeText(statusLine, THEME.small, "RIGHT", THEME.textDim)
    statusLine.right:SetPoint("RIGHT", statusLine, "RIGHT", -6, 0)
    statusLine.filters = {}
    for i, name in ipairs({ "ALL", "MINE", "NOTABLE" }) do
        local btn = MakeTextButton(statusLine, THEME.statusH)
        btn.filter = name
        btn.label:SetText(name)
        btn:SetScript("OnClick", function()
            DB.FeedFilter = name
            viewOffset = 0
            Commander.Notify(EV.UPDATE)
        end)
        statusLine.filters[i] = btn
    end
    statusLine.newPill = MakeTextButton(statusLine, THEME.statusH)
    statusLine.newPill:SetScript("OnClick", function()
        viewOffset, pendingNew = 0, 0
        MarkDirty(); Repaint()
    end)
    statusLine.newPill:Hide()
end

-- ===========================================================================
-- List builders. Every buffer recycles its rows: these rebuild on the 2 Hz
-- painter, and allocating a wrapper per row per repaint is precisely what the
-- suite's reference module exists to not do.
-- ===========================================================================
local function Recycled(pool, index)
    local row = pool[index]
    if not row then row = {}; pool[index] = row end
    for key in pairs(row) do row[key] = nil end
    return row
end

local feedBuffer, feedPool = {}, {}
local haulBuffer = {}
local bagBuffer, bagPool, hogScratch, bucketScratch = {}, {}, {}, {}
local partyBuffer = {}
local rollBuffer, rollPool = {}, {}

local function HogOrder(a, b)
    if a.slots ~= b.slots then return a.slots > b.slots end
    return a.value > b.value
end
local function BucketOrder(a, b) return a.stacks > b.stacks end
local function PartyOrder(a, b) return a.items > b.items end

-- Comparators are hoisted, not closured per repaint; the sort mode rides a
-- module local instead of an upvalue capture.
local haulSortMode = "VALUE"
local function HaulOrder(a, b)
    if haulSortMode == "QTY" then return a.count > b.count end
    if haulSortMode == "NAME" then
        local ma, mb = E.Meta(a.itemID), E.Meta(b.itemID)
        return ((ma and ma.name) or "") < ((mb and mb.name) or "")
    end
    if a.value ~= b.value then return a.value > b.value end
    return a.count > b.count
end

local function BuildFeedList()
    for i = #feedBuffer, 1, -1 do feedBuffer[i] = nil end
    local filter = DB.FeedFilter
    local filtered, lastSource = 0, nil
    for _, entry in ipairs(E.Feed) do
        local keep = true
        if filter == "MINE" and not entry.mine then keep = false end
        if filter == "NOTABLE" then
            if entry.kind == "item" then
                keep = entry.itemID and E.IsNotable(entry.itemID, entry.quality) or false
            elseif entry.kind == "money" then
                keep = entry.split and entry.copper >= 10000
            end
        end
        if keep then
            if entry.sourceName and entry.sourceName ~= lastSource then
                lastSource = entry.sourceName
                local marker = Recycled(feedPool, #feedBuffer + 1)
                marker.section = entry.sourceName
                feedBuffer[#feedBuffer + 1] = marker
            end
            -- Consecutive pickups of the same thing are one line with a total.
            -- Twenty rows of "Netherweave Cloth x5" is not a feed, it is noise.
            local previous = feedBuffer[#feedBuffer]
            if previous and previous.group and entry.kind == "item"
                and previous.kind == "item"
                and previous.itemID == entry.itemID and previous.mine == entry.mine
                and previous.who == entry.who then
                previous.count = previous.count + (entry.count or 1)
                previous.value = (previous.value or 0) + (entry.value or 0)
                previous.merged = previous.merged + 1
            elseif previous and previous.group and entry.kind == "money" and previous.kind == "money"
                and previous.mine == entry.mine then
                previous.copper = previous.copper + (entry.copper or 0)
                previous.merged = previous.merged + 1
            else
                local group = Recycled(feedPool, #feedBuffer + 1)
                for key, value in pairs(entry) do group[key] = value end
                group.group, group.merged = true, 1
                feedBuffer[#feedBuffer + 1] = group
            end
        else
            filtered = filtered + 1
        end
    end
    return filtered
end

local function BuildHaulList()
    for i = #haulBuffer, 1, -1 do haulBuffer[i] = nil end
    local stats = E.Fold(ScopeSegment())
    for _, item in pairs(stats.byItem) do haulBuffer[#haulBuffer + 1] = item end
    haulSortMode = DB.HaulSort
    table.sort(haulBuffer, HaulOrder)
    return stats
end

local function BuildBagList()
    for i = #bagBuffer, 1, -1 do bagBuffer[i] = nil end
    local census = E.Census()
    local row = Recycled(bagPool, 1)
    row.free, row.label = true, "FREE"
    row.count, row.slots = census.slotsFree, census.slotsTotal
    bagBuffer[1] = row

    for i = #bucketScratch, 1, -1 do bucketScratch[i] = nil end
    for _, entry in pairs(census.byBucket) do bucketScratch[#bucketScratch + 1] = entry end
    table.sort(bucketScratch, BucketOrder)
    for _, entry in ipairs(bucketScratch) do
        row = Recycled(bagPool, #bagBuffer + 1)
        row.bucket = entry.bucket
        row.label = E.Buckets[entry.bucket] and E.Buckets[entry.bucket].label or "?"
        row.count, row.slots, row.value = entry.items, entry.stacks, entry.value
        bagBuffer[#bagBuffer + 1] = row
    end
    if census.reclaimable and census.reclaimable > 0 then
        row = Recycled(bagPool, #bagBuffer + 1)
        row.merge, row.label = true, "PARTIAL STACKS"
        row.count, row.slots = census.partialSlots, census.reclaimable
        bagBuffer[#bagBuffer + 1] = row
    end
    -- The literal answer to "what is taking up space".
    for i = #hogScratch, 1, -1 do hogScratch[i] = nil end
    for _, hog in pairs(census.hogs) do hogScratch[#hogScratch + 1] = hog end
    table.sort(hogScratch, HogOrder)
    if #hogScratch > 0 then
        row = Recycled(bagPool, #bagBuffer + 1)
        row.section = "TAKING THE MOST ROOM"
        bagBuffer[#bagBuffer + 1] = row
        for i = 1, min(5, #hogScratch) do
            local hog = hogScratch[i]
            local meta = E.Meta(hog.itemID)
            row = Recycled(bagPool, #bagBuffer + 1)
            row.hog, row.itemID, row.quality = true, hog.itemID, hog.quality
            row.label = (meta and meta.name) or ("item:" .. hog.itemID)
            row.count, row.slots, row.value = hog.items, hog.slots, hog.value
            row.link = meta and meta.link
            bagBuffer[#bagBuffer + 1] = row
        end
    end
    return census
end

local function BuildPartyList()
    for i = #partyBuffer, 1, -1 do partyBuffer[i] = nil end
    for _, row in pairs(E.Party) do partyBuffer[#partyBuffer + 1] = row end
    table.sort(partyBuffer, PartyOrder)
end

-- The pane's job is "everything rolled on, and what everyone did" — so each
-- contest is a header row followed by one row per participant, inline. Clicking
-- through to a popup for the thing the pane exists to show was the wrong call.
local function PushRollHeader(live, logged)
    local row = Recycled(rollPool, #rollBuffer + 1)
    row.live, row.logged = live, logged
    rollBuffer[#rollBuffer + 1] = row
    return row
end

local function PushRoller(name, class, rollType, value, winner)
    local row = Recycled(rollPool, #rollBuffer + 1)
    row.roller = true
    row.name, row.class, row.rollType, row.value, row.winner = name, class, rollType, value, winner
    rollBuffer[#rollBuffer + 1] = row
end

local function BuildRollList()
    for i = #rollBuffer, 1, -1 do rollBuffer[i] = nil end
    for _, roll in ipairs(E.rolls) do
        if not roll.resolved then
            PushRollHeader(roll, nil)
            for _, entry in ipairs(roll.rollers) do
                PushRoller(entry.name, entry.class, entry.rollType, entry.roll, entry.winner)
            end
        end
    end
    local log = E.Data and E.Data.rolls or {}
    local seg = ScopeSegment()
    -- No segment means the scope is not running at all (RUN outside an
    -- instance). Falling back to 0 showed the whole 60-day log under a control
    -- that said RUN; showing nothing but the live rolls is the honest answer.
    local since = seg and seg.startEpoch
    -- Stop once there is more than a screenful past the scroll offset: the log
    -- holds 400 contests with up to 25 participants each, and the pane paints
    -- twelve rows.
    if not since then return end
    local budget = (DB.MaxRows or 12) + viewOffset + 2
    for i = #log, 1, -1 do
        if #rollBuffer >= budget then break end
        local entry = log[i]
        if (entry.t or 0) >= since then
            PushRollHeader(nil, entry)
            if entry.p then
                for _, packed in ipairs(entry.p) do
                    local name, class, rollType, value = strsplit(":", packed)
                    PushRoller(name, class, tonumber(rollType), (value ~= "" and value) or nil,
                        name == entry.w)
                end
            else
                PushRoller(entry.w or "everyone passed", entry.wc, entry.wt, entry.wr, entry.w ~= nil)
            end
        end
    end
end

-- ===========================================================================
-- Row painting
-- ===========================================================================
local function EnsureRows(want)
    for i = 1, want do
        local row = rows[i]
        if not row then
            row = BuildRow(body, i)
            row:SetScript("OnEnter", function(self)
                if self.link then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink(self.link)
                    if self.tipExtra then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine(self.tipExtra, THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], true)
                    end
                    GameTooltip:Show()
                elseif self.tipTitle then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(self.tipTitle, 1, 1, 1)
                    if self.tipExtra then
                        GameTooltip:AddLine(self.tipExtra, THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], true)
                    end
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row:SetScript("OnClick", function(self, button)
                if button == "RightButton" and self.itemID then
                    OpenMenu(function()
                        local pinned = DB.PinnedItems and DB.PinnedItems[self.itemID]
                        local info = UIDropDownMenu_CreateInfo()
                        info.text = "Always notify for this"
                        info.checked = pinned == true
                        info.func = function() E.Pin(self.itemID, pinned == true and nil or true) end
                        UIDropDownMenu_AddButton(info)
                        info = UIDropDownMenu_CreateInfo()
                        info.text = "Never notify for this"
                        info.checked = pinned == false
                        info.func = function() E.Pin(self.itemID, pinned == false and nil or false) end
                        UIDropDownMenu_AddButton(info)
                        info = UIDropDownMenu_CreateInfo()
                        info.text = "Link to party"
                        info.notCheckable = true
                        info.func = function()
                            if self.link then
                                local channel = (IsInRaid and IsInRaid()) and "RAID"
                                    or (IsInGroup and IsInGroup()) and "PARTY" or "SAY"
                                SendChatMessage(self.link, channel)
                            end
                        end
                        UIDropDownMenu_AddButton(info)
                    end, self)
                    return
                end
                if IsShiftKeyDown() and self.link then
                    if _G.ChatEdit_InsertLink then ChatEdit_InsertLink(self.link) end
                    return
                end
                if IsControlKeyDown() and self.link and _G.DressUpItemLink then
                    DressUpItemLink(self.link)
                    return
                end
                if self.onClick then self.onClick(self) end
            end)
            rows[i] = row
            rowColumnWidth = 0     -- force a re-measure now that a row exists
        end
        row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -((i - 1) * THEME.rowH))
        row:SetPoint("RIGHT", body, "RIGHT", 0, 0)
    end
    for i = want + 1, #rows do rows[i]:Hide() end
end

-- Rows are shared across panes, so every field a pane tints must be reset —
-- otherwise the age column keeps the last winner's class colour.
local function ResetRow(row)
    row.track:Hide(); row.tick:Hide(); row.section:Hide()
    row.icon:Show(); row.name:Show(); row.mid:Show(); row.right:Show()
    row.link, row.itemID, row.onClick = nil, nil, nil
    row.tipTitle, row.tipExtra, row.ageStamp = nil, nil, nil
    row.name:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])
    row.mid:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
    row.right:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
    row.name:SetPoint("RIGHT", row.mid, "LEFT", -6, 0)
end

local function SectionRow(row, text)
    ResetRow(row)
    row.icon:Hide(); row.name:Hide(); row.mid:Hide(); row.right:Hide()
    row.section:SetText(text)
    row.section:Show()
    row:Show()
end

local function PaintFeedRow(row, entry, now)
    if entry.section then SectionRow(row, entry.section) return end
    ResetRow(row)
    row.tick:SetShown(entry.mine == true)
    if entry.kind == "money" then
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
        row.name:SetText(Coin(entry.copper))
        row.name:SetTextColor(THEME.coin[1], THEME.coin[2], THEME.coin[3])
        row.mid:SetText(entry.split and "your share" or "")
        row.tipTitle = "Coin"
    elseif entry.kind == "outflow" then
        row.icon:SetTexture(entry.icon or QUESTION)
        row.name:SetText("− " .. (entry.name or "?") .. (entry.count > 1 and ("  x" .. entry.count) or ""))
        row.name:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
        row.mid:SetText(entry.reason or "")
        row.itemID = entry.itemID
    elseif entry.kind == "currency" then
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_Token_ArgentDawn")
        row.name:SetText(entry.label or "Currency")
        row.mid:SetText("x" .. (entry.count or 1))
    else
        -- An item first seen with a cold cache logs with no name and no
        -- quality; re-derive rather than rendering a white "?" forever.
        local meta = entry.itemID and E.Meta(entry.itemID)
        local name = entry.name or (meta and meta.name)
        local quality = entry.quality or (meta and meta.quality)
        local qc = QualityColor(quality)
        row.icon:SetTexture(entry.icon or (meta and meta.icon) or QUESTION)
        local label = name or "?"
        if (entry.count or 1) > 1 then label = label .. "  x" .. entry.count end
        row.name:SetText(label)
        row.name:SetTextColor(qc[1], qc[2], qc[3])
        row.link, row.itemID = entry.link or (meta and meta.link), entry.itemID
        if not entry.mine and entry.who then
            local cc = ClassColor(select(2, UnitClass(entry.who)))
            row.mid:SetText(entry.who)
            row.mid:SetTextColor(cc[1], cc[2], cc[3])
        else
            row.mid:SetText("")
        end
    end
    if entry.merged and entry.merged > 1 and entry.kind ~= "item" then
        row.mid:SetText(format("x%d", entry.merged))
    end
    row.ageStamp = DB.LiveAges and (entry.t or now) or nil
    row.right:SetText(DB.LiveAges and ShortTime(now - (entry.t or now))
        or date("%H:%M", entry.t or now))
    row:Show()
end

local EMPTY_STATE = {
    FEED  = { "NOTHING YET · LOOT SOMETHING.", "Chat loot lines are off — they appear here instead." },
    HAUL  = { "NO SPOILS THIS SCOPE", "Widen the scope, or go hit something." },
    ROLLS = { "NO ROLLS SEEN", "Group loot rolls appear here, live and after." },
    BAGS  = { "BAGS EMPTY", "" },
    PARTY = { "SOLO", "Party income appears when you group. It resets when the group does." },
}

local function PaintHeader()
    local stats = E.Fold(ScopeSegment())
    local label = (DB.ValueMode == "MARKET" and "MARKET " or "VENDOR ")
        .. CoinShort(stats.value + stats.gold)
    if stats.coverage then
        label = label .. format("  %d%%", floor(stats.coverage * 100 + 0.5))
    end
    header.value.label:SetText(label)
    -- Amber past a day stale, dim past three: the freshness is the number's
    -- credibility, and an unmarked market price is a guess wearing a suit.
    local stale = stats.stalestDays
    if stats.coverage and stale and stale > 3 then
        header.value.label:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
    elseif stats.coverage and stale and stale > 1 then
        header.value.label:SetTextColor(THEME.warn[1], THEME.warn[2], THEME.warn[3])
    else
        header.value.label:SetTextColor(THEME.coin[1], THEME.coin[2], THEME.coin[3])
    end
    header.items:SetText(stats.items .. " ITEMS")
    if stats.bestItemID and header.best:IsShown() then
        local meta = E.Meta(stats.bestItemID)
        local qc = QualityColor(stats.bestQuality)
        header.best:SetText(meta and meta.name or "")
        header.best:SetTextColor(qc[1], qc[2], qc[3])
    else
        header.best:SetText("")
    end
    local census = E.Census()
    local free = census.slotsFree or 0
    header.bags.label:SetText(format("%d/%d", free, census.slotsTotal or 0))
    local warn = DB.JunkWarnSlots or 6
    local color = (free <= warn and THEME.bad) or (free <= warn * 2 and THEME.warn) or THEME.text
    header.bags.label:SetTextColor(color[1], color[2], color[3])
    SetGlyphColor(header.glyphs.farm, E.FarmActive() and THEME.accent or THEME.textDim)
    SetGlyphColor(header.glyphs.expand, DB.Expanded and THEME.accent or THEME.textDim)
end

local function PaintModeStrip()
    for _, btn in ipairs(modeButtons) do
        local active = DB.ViewMode == btn.mode
        local label = btn.mode
        if btn.mode == "ROLLS" then
            local live = LiveRollCount()
            if live > 0 then label = label .. " ●" .. live end
        elseif btn.mode == "FEED" and pendingNew > 0 then
            label = label .. " ●" .. pendingNew
        elseif btn.mode == "BAGS" then
            local census = E.Census()
            if (census.slotsFree or 99) <= (DB.JunkWarnSlots or 6) then label = label .. " !" end
        end
        btn.label:SetText(label)
        local color = active and THEME.accent or THEME.textDim
        btn.label:SetTextColor(color[1], color[2], color[3])
    end
    -- BAGS and PARTY have no time dimension: the control says so rather than
    -- silently doing nothing.
    local scoped = DB.ViewMode ~= "BAGS" and DB.ViewMode ~= "PARTY"
    if scoped then
        scopeButton.label:SetText(DB.ViewScope .. " ▾")
        scopeButton.label:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])
        scopeButton:SetAlpha(1)
    else
        scopeButton.label:SetText(DB.ViewMode == "BAGS" and "NOW" or "THIS GROUP")
        scopeButton.label:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
        scopeButton:SetAlpha(0.5)
    end
end

-- Right-to-left: the filters own the right end on FEED, the row count owns it
-- everywhere else, and whatever is left over is the left field's — which
-- truncates rather than overlapping.
local FILTER_W, PILL_W, COUNT_W = 46, 60, 74
local statusKey = nil

local function LayoutStatus(width, onFeed, pill)
    local key = width .. (onFeed and "F" or "-") .. (pill and "P" or "-")
    if key == statusKey then return end
    statusKey = key
    local right = 6
    if onFeed then
        for i = #statusLine.filters, 1, -1 do
            local btn = statusLine.filters[i]
            btn:SetWidth(FILTER_W)
            btn:ClearAllPoints()
            btn:SetPoint("TOP", statusLine, "TOP", 0, 0)
            btn:SetPoint("BOTTOM", statusLine, "BOTTOM", 0, 0)
            btn:SetPoint("RIGHT", statusLine, "RIGHT", -right, 0)
            btn:Show()
            right = right + FILTER_W
        end
        statusLine.right:Hide()
    else
        for _, btn in ipairs(statusLine.filters) do btn:Hide() end
        statusLine.right:SetWidth(COUNT_W)
        statusLine.right:Show()
        right = right + COUNT_W
    end
    if pill then
        statusLine.newPill:SetWidth(PILL_W)
        statusLine.newPill:ClearAllPoints()
        statusLine.newPill:SetPoint("TOP", statusLine, "TOP", 0, 0)
        statusLine.newPill:SetPoint("BOTTOM", statusLine, "BOTTOM", 0, 0)
        statusLine.newPill:SetPoint("RIGHT", statusLine, "RIGHT", -right, 0)
        statusLine.newPill:Show()
        right = right + PILL_W
    else
        statusLine.newPill:Hide()
    end
    statusLine.left:ClearAllPoints()
    statusLine.left:SetPoint("LEFT", statusLine, "LEFT", 6, 0)
    statusLine.left:SetPoint("RIGHT", statusLine, "RIGHT", -(right + 4), 0)
end

local function PaintStatus(filtered, total)
    local width = DB.FrameWidth or 350
    local onFeed = DB.ViewMode == "FEED"
    local pill = pendingNew > 0 and viewOffset > 0 and onFeed
    LayoutStatus(width, onFeed, pill)

    local seg = ScopeSegment()
    local elapsed = seg and (time() - (seg.startEpoch or time())) or 0
    local rate = select(1, E.TrailingRate(5))
    -- The loot method's threshold clause is the first thing to go: it is the
    -- least useful half of the least useful field.
    local method = E.LootMethodText()
    if width < 420 then method = method:gsub("%s*·%s*THRESHOLD.*$", "") end
    local text = format("%s · %s · %s/hr", method, Duration(elapsed), CoinShort(floor(rate)))
    if onFeed and filtered and filtered > 0 then
        text = text .. "  ·  " .. filtered .. " hidden"
    end
    statusLine.left:SetText(text)

    for _, btn in ipairs(statusLine.filters) do
        local active = DB.FeedFilter == btn.filter
        local color = active and THEME.accent or THEME.textDim
        btn.label:SetTextColor(color[1], color[2], color[3])
    end
    if not onFeed then
        if DB.ViewMode == "PARTY" then
            statusLine.right:SetText("IN RANGE ONLY")
        else
            statusLine.right:SetText(total and (total .. " ROWS") or "")
        end
    end
    if pill then
        statusLine.newPill.label:SetText("▲ " .. pendingNew)
        statusLine.newPill.label:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])
    end
end

local function PaintPanes()
    local want = DB.MaxRows or 12
    EnsureRows(want)
    LayoutRowColumns(DB.FrameWidth or 350)
    PaintModeStrip()
    local mode, now = DB.ViewMode, time()
    local list, filtered

    if mode == "FEED" then filtered = BuildFeedList(); list = feedBuffer
    elseif mode == "HAUL" then BuildHaulList(); list = haulBuffer
    elseif mode == "BAGS" then BuildBagList(); list = bagBuffer
    elseif mode == "PARTY" then BuildPartyList(); list = partyBuffer
    else BuildRollList(); list = rollBuffer end

    local total = #list
    viewOffset = min(viewOffset, max(0, total - want))

    if total == 0 then
        local empty = EMPTY_STATE[mode]
        local sessionStats = E.Fold(E.SegmentFor("SESSION"))
        if DB.ViewScope ~= "SESSION" and sessionStats.items > 0
            and mode ~= "BAGS" and mode ~= "PARTY" then
            body.empty:SetText("NOTHING IN THIS SCOPE")
            body.emptyHint:SetText(format("Session has %d items — widen the scope.", sessionStats.items))
        else
            body.empty:SetText(empty[1])
            body.emptyHint:SetText(empty[2])
        end
        body.empty:Show(); body.emptyHint:Show()
        for i = 1, #rows do rows[i]:Hide() end
        PaintStatus(filtered, total)
        return
    end
    body.empty:Hide(); body.emptyHint:Hide()

    for i = 1, want do
        local row = rows[i]
        local entry = list[i + viewOffset]
        if not entry then
            row:Hide()
        elseif mode == "FEED" then
            PaintFeedRow(row, entry, now)
        elseif mode == "HAUL" then
            ResetRow(row)
            local meta = E.Meta(entry.itemID)
            local qc = QualityColor(entry.quality or (meta and meta.quality))
            row.icon:SetTexture(meta and meta.icon or QUESTION)
            row.name:SetText((meta and meta.name) or ("item:" .. entry.itemID))
            row.name:SetTextColor(qc[1], qc[2], qc[3])
            row.mid:SetText("x" .. entry.count)
            -- Reconciled acquisitions are in the ledger but are not income, so
            -- the row says so rather than quietly failing to sum to the header.
            if entry.other then
                row.right:SetText(entry.value > 0 and ("(" .. CoinShort(entry.value) .. ")") or "—")
                row.tipExtra = "Arrived by mail, vendor or trade — counted in the ledger, not as income."
            else
                row.right:SetText(entry.value > 0 and CoinShort(entry.value) or "—")
                local lifetime = E.Data.lifetime[entry.itemID]
                row.tipExtra = lifetime and format("Lifetime: %d", lifetime[1]) or nil
            end
            row.link, row.itemID = meta and meta.link, entry.itemID
            row:Show()
        elseif mode == "BAGS" and entry.section then
            SectionRow(row, entry.section)
        elseif mode == "BAGS" then
            ResetRow(row)
            if entry.hog then
                local meta = E.Meta(entry.itemID)
                local qc = QualityColor(entry.quality)
                row.icon:SetTexture(meta and meta.icon or QUESTION)
                row.name:SetText(entry.label)
                row.name:SetTextColor(qc[1], qc[2], qc[3])
                row.mid:SetText(entry.count .. " in " .. entry.slots)
                row.right:SetText(entry.value > 0 and CoinShort(entry.value) or "")
                row.link, row.itemID = entry.link, entry.itemID
            else
                row.icon:Hide()
                row.track:Show()
                row.name:ClearAllPoints()
                row.name:SetPoint("LEFT", row, "LEFT", 8, 0)
                row.name:SetPoint("RIGHT", row.mid, "LEFT", -6, 0)
                row.name:SetText(entry.label)
                if entry.free then
                    row.name:SetTextColor(THEME.good[1], THEME.good[2], THEME.good[3])
                    row.mid:SetText(format("%d / %d", entry.count, entry.slots))
                    row.right:SetText("")
                elseif entry.merge then
                    row.name:SetTextColor(THEME.warn[1], THEME.warn[2], THEME.warn[3])
                    row.mid:SetText(entry.count .. " partial")
                    row.right:SetText(entry.slots .. " reclaimable")
                    row.onClick = function()
                        if _G.CommanderBags_SortBags then CommanderBags_SortBags()
                        else print("|cff66ccffCommander Spoils|r: Commander_Bags is not loaded — nothing to sort with") end
                    end
                    row.tipTitle = "Partial stacks"
                    row.tipExtra = _G.CommanderBags_SortBags and "Click to run Commander_Bags' sort." or nil
                else
                    row.mid:SetText(entry.count .. " in " .. entry.slots)
                    row.right:SetText(entry.value > 0 and CoinShort(entry.value) or "")
                    if entry.bucket == E.BucketIndex.JUNK then
                        local grey = QUALITY_FALLBACK[0]
                        row.name:SetTextColor(grey[1], grey[2], grey[3])
                        row.tipTitle = "Junk"
                        row.tipExtra = (_G.CommanderLogisticsDB and CommanderLogisticsDB.AutoSellJunk)
                            and "Commander Logistics will sell these at the next merchant."
                            or "Spoils never sells anything — Commander Logistics owns vendoring."
                    end
                end
            end
            row:Show()
        elseif mode == "PARTY" then
            ResetRow(row)
            row.icon:Hide()
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", row, "LEFT", 8, 0)
            row.name:SetPoint("RIGHT", row.mid, "LEFT", -6, 0)
            local cc = ClassColor(select(2, UnitClass(entry.name)))
            row.name:SetText(entry.name)
            row.name:SetTextColor(cc[1], cc[2], cc[3])
            row.mid:SetText(format("N%d G%d P%d", entry.need, entry.greed, entry.pass))
            row.right:SetText(entry.items .. " items")
            row.link = entry.bestLink
            row:Show()
        elseif entry.roller then
            -- One participant of the contest above: what they chose and what
            -- they rolled. Indented so the grouping reads without a rule.
            ResetRow(row)
            row.icon:Hide()
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", row, "LEFT", 26, 0)
            row.name:SetPoint("RIGHT", row.mid, "LEFT", -6, 0)
            local cc = ClassColor(entry.class)
            row.name:SetText((entry.winner and "★ " or "") .. (entry.name or "?"))
            row.name:SetTextColor(cc[1], cc[2], cc[3])
            local choice = E.RollTypeName[entry.rollType]
            row.mid:SetText(choice or "no roll")
            if entry.rollType == 1 then
                row.mid:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])
            elseif entry.rollType == 0 then
                row.mid:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
            end
            row.right:SetText(entry.value and tostring(entry.value) or "—")
            if entry.winner then
                row.right:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])
            end
            row:Show()
        else
            ResetRow(row)
            local roll = entry.live
            if roll then
                local qc = QualityColor(roll.quality)
                row.icon:SetTexture(roll.icon or QUESTION)
                row.name:SetText(roll.name or "Loading…")
                row.name:SetTextColor(qc[1], qc[2], qc[3])
                row.mid:SetText(roll.my ~= nil and (E.RollTypeName[roll.my] or "") or "—")
                local seconds = RollTimeLeftSeconds(roll)
                row.right:SetText(seconds and ("LIVE " .. ShortTime(seconds)) or "LIVE")
                row.right:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])
                row.link, row.itemID = roll.link, roll.itemID
            else
                local logged = entry.logged
                local meta = logged.id and E.Meta(logged.id)
                local qc = QualityColor(logged.q)
                row.icon:SetTexture(meta and meta.icon or QUESTION)
                row.name:SetText(meta and meta.name or "?")
                row.name:SetTextColor(qc[1], qc[2], qc[3])
                local mine = logged.my
                if mine == -1 then
                    row.mid:SetText("MISSED")
                    row.mid:SetTextColor(THEME.bad[1], THEME.bad[2], THEME.bad[3])
                elseif mine ~= nil then
                    row.mid:SetText(format("%s %s", E.RollTypeName[mine] or "", logged.myRoll or ""))
                else
                    row.mid:SetText("—")
                end
                if logged.w then
                    local wc = ClassColor(logged.wc)
                    row.right:SetText(logged.w)
                    row.right:SetTextColor(wc[1], wc[2], wc[3])
                else
                    row.right:SetText("all passed")
                end
                row.link, row.itemID = meta and meta.link, logged.id
            end
            row:Show()
        end
    end
    PaintStatus(filtered, total)
end

-- ===========================================================================
-- Layout — the point of the single frame
-- ===========================================================================
local function BandsActive()
    return (#activePickups > 0) or corpseBand:IsShown() or (#E.rolls > 0)
end

-- The single source of truth for "is the window on screen". Anything that
-- makes a band appear or disappear must end here — and the ticker asks the
-- same question, so the two can never disagree about it.
local function ShouldShow()
    if not DB then return false end
    if Commander.UI.HudUnlocked(DB, "Hud") then return true end
    if not DB.EnableSpoils then return false end
    -- Always on: idle and collapsed that is a one-line readout of value,
    -- items and bag space, which is a reasonable thing to want parked on the
    -- screen. It costs nothing extra — the repaint is still dirty-driven.
    return DB.AlwaysShow or DB.Expanded or BandsActive()
end

Reconcile = function()
    if not mainFrame or not DB then return end
    Layout()
    mainFrame:SetShown(ShouldShow())
end

Layout = function()
    if not mainFrame then return end
    local width = DB.FrameWidth or 350
    LayoutHeader(width)
    LayoutModeStrip(width)
    LayoutRowColumns(width)
    local y = THEME.headerH

    if #activePickups > 0 then
        pickupBand:ClearAllPoints()
        pickupBand:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, -y)
        pickupBand:SetPoint("RIGHT", mainFrame, "RIGHT", 0, 0)
        pickupBand:SetHeight(#activePickups * THEME.pickupH + 2)
        for i, row in ipairs(pickupBand.rows) do
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", pickupBand, "TOPLEFT", 0, -((i - 1) * THEME.pickupH + 1))
            row:SetPoint("RIGHT", pickupBand, "RIGHT", 0, 0)
        end
        pickupBand:Show()
        y = y + pickupBand:GetHeight()
    else
        pickupBand:Hide()
    end

    if corpseBand:IsShown() then
        corpseBand:ClearAllPoints()
        corpseBand:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, -y)
        corpseBand:SetPoint("RIGHT", mainFrame, "RIGHT", 0, 0)
        y = y + corpseBand:GetHeight()
    end

    if rollBand:IsShown() then
        rollBand:ClearAllPoints()
        rollBand:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, -y)
        rollBand:SetPoint("RIGHT", mainFrame, "RIGHT", 0, 0)
        y = y + rollBand:GetHeight()
    end

    if DB.Expanded then
        modeStrip:ClearAllPoints()
        modeStrip:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, -y)
        modeStrip:SetPoint("RIGHT", mainFrame, "RIGHT", 0, 0)
        modeStrip:Show()
        y = y + THEME.modeH + 1

        local bodyH = (DB.MaxRows or 12) * THEME.rowH
        body:ClearAllPoints()
        body:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, -y)
        body:SetPoint("RIGHT", mainFrame, "RIGHT", 0, 0)
        body:SetHeight(bodyH)
        body:Show()
        y = y + bodyH

        statusLine:ClearAllPoints()
        statusLine:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, -y)
        statusLine:SetPoint("RIGHT", mainFrame, "RIGHT", 0, 0)
        statusLine:Show()
        y = y + THEME.statusH
    else
        modeStrip:Hide(); body:Hide(); statusLine:Hide()
    end

    mainFrame:SetSize(width, y + 1)
end

Repaint = function()
    -- Cleared before the visibility guard: leaving it set while the window is
    -- closed meant the ticker re-entered every 0.25s for the whole session,
    -- which is the exact cost the dirty flag exists to avoid.
    dirty = false
    if not mainFrame or not mainFrame:IsShown() then return end
    PaintHeader()
    if DB.Expanded then PaintPanes() end
end

-- Everything a repaint would redo except the list rebuild: only the age
-- column actually changes with the clock.
local function SweepAges()
    if not (mainFrame and mainFrame:IsShown() and DB.Expanded) then return end
    if DB.ViewMode ~= "FEED" or not DB.LiveAges then return end
    local now = time()
    for i = 1, #rows do
        local row = rows[i]
        if row.ageStamp then
            row.right:SetText(ShortTime(now - row.ageStamp))
        end
    end
end

-- ===========================================================================
-- Position and the corpse
-- ===========================================================================
local cursorX, cursorY

-- With the panes open the frame is a reading surface at a fixed place and must
-- not move. Collapsed, it follows the cursor to the corpse, then goes back to
-- where the player put it.
ApplyPosition = function(sampleCursor)
    if not mainFrame then return end
    local following = DB.SalvageAnchor == "CURSOR" and not DB.Expanded and corpseBand:IsShown()
    if following then
        if sampleCursor then cursorX, cursorY = GetCursorPosition() end
        if cursorX then
            local scale = mainFrame:GetEffectiveScale()
            if not scale or scale == 0 then scale = 1 end
            mainFrame:ClearAllPoints()
            mainFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
                cursorX / scale + 14, cursorY / scale + 14)
            savedPointApplied = false
            return
        end
    end
    if not savedPointApplied then
        Commander.UI.ApplyHudChrome(mainFrame, DB, "Hud", {
            title = "Commander Spoils",
            defaultPoint = { point = "CENTER", x = 0, y = 0 },
        })
        savedPointApplied = true
    end
end

OpenCorpse = function()
    if not DB.SuppressLootWindow or not DB.EnableSpoils then return end
    E.RebuildSlots()
    -- Autoloot sweeps most corpses clean. When it does, showing nothing is
    -- right; when slots are left behind (bind confirms, full bags), showing
    -- only the remainder beats a bare window that looks like autoloot failed.
    if E.autoLoot and #E.slots == 0 then
        corpseBand:Hide()
        Layout()
        return
    end
    PaintCorpse()
    ApplyPosition(true)
    Layout()
end

CloseCorpse = function()
    mlSlot, armedCandidate, fakeSlots = nil, nil, nil
    corpseBand:Hide()
    ApplyPosition(false)
    Layout()
end

-- ===========================================================================
-- Apply
-- ===========================================================================
local function Apply()
    DB = CommanderSpoilsDB
    dirty = true
    -- Rows are pooled and built once; a recess changed in settings has to be
    -- carried to the ones that already exist
    RestyleIcons()
    CommanderSpoils_Suppression.Sync()
    local enabled = DB.EnableSpoils

    savedPointApplied = false
    ApplyPosition(false)
    -- The frame appears on its own only for the live bands; the panes never
    -- open it (D2 R1). One function decides this, and everything that changes
    -- a band ends there.
    Reconcile()
    if not enabled then
        SetGlow(0)
        corpseBand:Hide(); rollBand:Hide(); pickupBand:Hide()
    end
    Repaint()
end

-- ===========================================================================
-- Public surface
-- ===========================================================================
function CommanderSpoils_Toggle()
    DB.Expanded = not DB.Expanded
    Apply()
end

function CommanderSpoils_ToggleFarm()
    if E.FarmActive() then
        E.StopFarm()
        print("|cff66ccffCommander Spoils|r: farm ended")
    else
        E.StartFarm(GetRealZoneText and GetRealZoneText() or "Farm")
        print("|cff66ccffCommander Spoils|r: farm started — /cspoils farm again to stop")
    end
end

function CommanderSpoils_Report()
    local seg = E.SegmentFor(DB.ViewScope)
    local stats = E.Fold(seg)
    if stats.items == 0 and stats.gold == 0 then
        print("|cff66ccffCommander Spoils|r: nothing acquired in this scope yet")
        return
    end
    local elapsed = seg and (time() - (seg.startEpoch or time())) or 0
    print(format("|cff66ccffCommander Spoils|r: %s — %d items, %s vendor, %s coin over %s",
        seg and seg.label or "Session", stats.items, CoinShort(stats.value),
        CoinShort(stats.gold), Duration(elapsed)))
    local names = { [0] = "poor", "common", "uncommon", "rare", "epic", "legendary" }
    local parts = {}
    for quality = 5, 0, -1 do
        local count = stats.byQuality[quality] or 0
        if count > 0 then parts[#parts + 1] = format("%d %s", count, names[quality]) end
    end
    if #parts > 0 then print("  " .. table.concat(parts, ", ")) end
    if stats.bestItemID then
        local meta = E.Meta(stats.bestItemID)
        print("  best find: " .. ((meta and meta.link) or (meta and meta.name) or "?"))
    end
    if stats.otherValue > 0 then
        print(format("  (%s arrived by mail, vendor or trade — not counted as income)",
            CoinShort(stats.otherValue)))
    end
end

-- Two-step, because the glyph sits two pixels from the pane toggle and there
-- is no undo. The arm expires on its own so it can never sit hot.
local wipeArmedUntil = 0

function CommanderSpoils_Wipe(force)
    if not force and GetTime() > wipeArmedUntil then
        wipeArmedUntil = GetTime() + 5
        print("|cff66ccffCommander Spoils|r: click again within 5 seconds to erase the whole ledger — there is no undo.")
        return
    end
    wipeArmedUntil = 0
    E.Wipe()
    viewOffset, pendingNew = 0, 0
    for i = #activePickups, 1, -1 do activePickups[i] = nil end
    RedrawPickups()
    Apply()
end

function CommanderSpoils_PrintSize()
    local data = E.Data
    if not data then return end
    local lifetime = 0
    for _ in pairs(data.lifetime) do lifetime = lifetime + 1 end
    print(format("|cff66ccffCommander Spoils|r: %d events / %d, %d segments, %d rolls, %d coin rows, %d lifetime items",
        #data.events, E.Limits.events, #data.segments, #data.rolls, #data.money.log, lifetime))
    -- Prints the client's own names for the trade-goods subclasses, so the
    -- hardcoded bucket map can be verified in a single login (ASSUMPTIONS 1).
    if C_Item and C_Item.GetItemSubClassInfo then
        local names = {}
        for i = 0, 15 do
            local ok, name = pcall(C_Item.GetItemSubClassInfo, 7, i)
            if ok and name then names[#names + 1] = i .. "=" .. name end
        end
        print("  trade goods subclasses: " .. table.concat(names, " "))
    end
end

-- ---------------------------------------------------------------------------
-- Try It — every button drives the real painting code with fake data, so the
-- player can see and place each band without waiting for a raid. Fake rolls
-- carry `fake = true` and are never sent to the server.
-- ---------------------------------------------------------------------------
local TEST_ITEMS = {
    { id = 28429, name = "Girdle of Ferocity", icon = "Interface\\Icons\\INV_Belt_15", quality = 4, bop = true },
    { id = 21877, name = "Netherweave Cloth", icon = "Interface\\Icons\\INV_Fabric_Netherweave", quality = 1 },
    { id = 22526, name = "Star of Elune", icon = "Interface\\Icons\\INV_Misc_Gem_Diamond_03", quality = 3 },
    { id = 5637,  name = "Large Fang", icon = "Interface\\Icons\\INV_Misc_MonsterFang_01", quality = 0 },
}
local fakeRollSeq = 0

local function FakeRoll(spec, seconds)
    fakeRollSeq = fakeRollSeq + 1
    local id = -fakeRollSeq        -- negative ids can never collide with real ones
    local roll = {
        id = id, fake = true, icon = spec.icon, name = spec.name, count = 1,
        quality = spec.quality, bop = spec.bop,
        canNeed = spec.quality >= 2, canGreed = true,
        reasonNeed = 1, reasonGreed = 1, itemID = spec.id,
        rollTime = seconds * 1000, startedAt = GetTime(),
        fakeUntil = GetTime() + seconds,
        guardUntil = GetTime() + (DB.RollGuardMs or 300) / 1000,
        rollers = {},
    }
    E.rolls[#E.rolls + 1] = roll
    E.rollByID[id] = roll
    return roll
end

function CommanderSpoils_Test(what)
    what = tostring(what or "pickup"):lower()
    if what == "pickup" then
        local spec = TEST_ITEMS[1]
        PushPickup(spec.name, spec.icon, spec.quality, spec.id, 1, 90000)
        if DB.EpicFlash then EpicPulse() end
        Apply()
    elseif what == "roll" then
        FakeRoll(TEST_ITEMS[1], 30)
        focusedRoll = nil
        LayoutRollBand(); Apply()
    elseif what == "wave" then
        for i = 1, 6 do FakeRoll(TEST_ITEMS[(i % #TEST_ITEMS) + 1], 20 + i * 3) end
        focusedRoll = nil
        if DB.SoundRollOpen then PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE, "Master") end
        LayoutRollBand(); Apply()
    elseif what == "win" then
        local target
        for _, roll in ipairs(E.rolls) do
            if roll.fake and not roll.resolved then target = roll break end
        end
        if not target then target = FakeRoll(TEST_ITEMS[1], 30) end
        target.my, target.myRoll, target.decided = 1, 94, 2
        target.rollers = {
            { name = UnitName("player"), class = select(2, UnitClass("player")),
              rollType = 1, roll = 94, winner = true, me = true },
            { name = "Grimbold", class = "WARRIOR", rollType = 2, roll = 71 },
        }
        target.resolved, target.resolvedAt = true, GetTime()
        target.won, target.winner = true, UnitName("player")
        if DB.SoundRollWon then PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE, "Master") end
        LayoutRollBand(); Apply()
    elseif what == "corpse" then
        fakeSlots = {}
        for i, spec in ipairs(TEST_ITEMS) do
            fakeSlots[i] = {
                slot = i, icon = spec.icon, name = spec.name, count = (i == 2) and 5 or 1,
                quality = spec.quality, slotType = 1, cached = true,
                link = "|Hitem:" .. spec.id .. "|h",
            }
        end
        E.bindSlot = 1          -- so the inline bind confirm is visible too
        PaintCorpse()
        ApplyPosition(true)
        Apply()
    elseif what == "clear" then
        for i = #E.rolls, 1, -1 do
            if E.rolls[i].fake then
                E.rollByID[E.rolls[i].id] = nil
                table.remove(E.rolls, i)
            end
        end
        E.bindSlot, fakeSlots = nil, nil
        for i = #activePickups, 1, -1 do activePickups[i] = nil end
        RedrawPickups()
        corpseBand:Hide()
        LayoutRollBand(); Apply()
        print("|cff66ccffCommander Spoils|r: test data cleared")
    else
        print("|cff66ccffCommander Spoils|r: try pickup | roll | wave | win | corpse | clear")
    end
end

-- The guard exists to stop a row moving under a cursor. A keypress cannot
-- misclick, so bindings bypass it — a fast player's Need must not vanish.
local function KeyRoll(rollType)
    local roll = FocusRoll()
    if not roll then return end
    roll.guardUntil = 0
    if roll.fake then
        roll.my = rollType
        LayoutRollBand(); Layout()
        return
    end
    E.Roll(roll.id, rollType)
end
function CommanderSpoils_RollNeed()  KeyRoll(1) end
function CommanderSpoils_RollGreed() KeyRoll(2) end
function CommanderSpoils_RollPass()  KeyRoll(0) end
-- Same reasoning as KeyRoll: a keypress cannot misclick, so the binding is
-- not subject to the guard that exists to stop a moving row being clicked.
function CommanderSpoils_PassAll()
    for _, roll in ipairs(E.rolls) do
        if not roll.resolved and roll.my == nil then roll.guardUntil = 0 end
    end
    E.PassAll()
end
function CommanderSpoils_CycleRoll() CycleFocus() end

-- ===========================================================================
-- Wiring
-- ===========================================================================
local function OnLootEntry(entry)
    if not entry.itemID then return end
    -- A vendor purchase or a mail collection is not a pickup; announcing it is
    -- the reconciler leaking into the alerts.
    if entry.source == E.SrcKind.OTHER then return end
    local meta = E.Meta(entry.itemID)
    local quality = entry.quality or (meta and meta.quality)
    if E.IsNotable(entry.itemID, quality) then
        PushPickup((meta and meta.name) or "?", meta and meta.icon, quality,
            entry.itemID, entry.count, (entry.unitValue or 0) * entry.count)
        if DB.SoundToast then PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE, "Master") end
    end
    if (quality or 0) >= 4 and DB.EpicFlash then EpicPulse() end
    if viewOffset > 0 then pendingNew = pendingNew + 1 end
    MarkDirty()
    Apply()
end

local function OnRollEvent(roll, phase)
    if phase == "start" and roll then
        focusedRoll = focusedRoll or roll.id
        -- A roll OPENING is the moment the alert is named for. Fired here
        -- rather than from the urgency ladder, which cannot chime before the
        -- 15-second warning stage — 45 seconds late on a 60-second roll.
        -- Gated on being the first of a batch so a wave pull chimes once.
        if DB.SoundRollOpen and (roll.canNeed or roll.canGreed) then
            local others = 0
            for _, other in ipairs(E.rolls) do
                if other ~= roll and IsLive(other) then others = others + 1 end
            end
            if others == 0 then PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE, "Master") end
        end
        -- Auto-pass is never silent: the ghost row says what it passed.
        local floorQ = DB.AutoPassBelowQuality or 0
        if floorQ > 0 and (roll.quality or 0) < floorQ then
            C_Timer.After(2, function()
                if roll.my == nil and not roll.resolved then
                    roll.auto = true
                    E.Roll(roll.id, 0)
                end
            end)
        end
    elseif phase == "resolved" and roll and roll.won then
        if DB.SoundRollWon then PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE, "Master") end
    end
    LayoutRollBand()
    Apply()
end

local ticker = CreateFrame("Frame")
local paintAcc, rollAcc = 0, 0

ticker:SetScript("OnUpdate", function(_, elapsed)
    -- The cheap gate first: with nothing pending, nothing dirty and no glow to
    -- settle, this costs one comparison per frame and returns.
    if not dirty and #E.rolls == 0 and not (glowFrame and glowFrame:IsShown()) then
        if not (DB and DB.LiveAges and DB.Expanded and mainFrame and mainFrame:IsShown()) then
            return
        end
    end
    paintAcc = paintAcc + elapsed
    if paintAcc >= 0.25 then
        paintAcc = 0
        if dirty then
            Repaint()
        else
            -- Ages tick once a second, and only the text changes.
            local now = GetTime()
            if now - lastAgeSweep >= 1 then
                lastAgeSweep = now
                SweepAges()
            end
        end
    end
    if #E.rolls > 0 then
        -- 5 Hz, and only while a roll is on screen: rolls are rare and bounded,
        -- and a countdown does not need sixty updates a second.
        rollAcc = rollAcc + elapsed
        if rollAcc >= 0.2 then
            rollAcc = 0
            -- Fake rolls expire on their own clock so the Try It buttons
            -- cannot leave the band up forever.
            for _, roll in ipairs(E.rolls) do
                if roll.fake and not roll.resolved and RollTimeLeftSeconds(roll) <= 0 then
                    roll.resolved, roll.resolvedAt = true, GetTime()
                    roll.missed = roll.my == nil
                end
            end
            E.PruneRolls()
            LayoutRollBand()
            UpdateUrgency()
            Layout()
            if ShouldShow() ~= mainFrame:IsShown() then Reconcile() end
            -- Only the ROLLS pane's contents track the countdown; every other
            -- pane rebuilding five buffers at 5 Hz was the cost D2c removed.
            if DB.Expanded and DB.ViewMode == "ROLLS" then MarkDirty() end
        end
    end
    if glowFrame and glowFrame:IsShown() then
        local current = glowFrame:GetAlpha()
        if math.abs(current - glowTarget) < 0.01 then
            glowFrame:SetAlpha(glowTarget)
            if glowTarget == 0 then glowFrame:Hide() end
        else
            glowFrame:SetAlpha(current + (glowTarget - current) * min(1, elapsed * 6))
        end
    end
end)

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function()
    DB = CommanderSpoilsDB
    ResolveTheme()   -- appearance bakes in before a single widget is built

    mainFrame = CreateFrame("Frame", "CommanderSpoilsFrame", UIParent)
    mainFrame:SetFrameStrata("MEDIUM")
    mainFrame:SetClampedToScreen(true)
    mainFrame.fill = Fill(mainFrame, "BACKGROUND", THEME.bg)
    mainFrame.fill:SetAllPoints()
    MakeEdge(mainFrame)
    if UISpecialFrames then table.insert(UISpecialFrames, "CommanderSpoilsFrame") end

    menuFrame = CreateFrame("Frame", "CommanderSpoilsMenu", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(menuFrame, function()
        if menuBuilder then menuBuilder() end
    end, "MENU")

    BuildHeader()
    pickupBand = MakeBand(mainFrame, "CommanderSpoilsPickups")
    pickupBand.caption:Hide(); pickupBand.captionRight:Hide()
    corpseBand = MakeBand(mainFrame, "CommanderSpoilsCorpse")
    rollBand = MakeBand(mainFrame, "CommanderSpoilsRolls")
    BuildPickupRows(); BuildCorpseRows(); BuildRollRows()
    BuildModeStrip(); BuildBody(); BuildStatus()
    -- The PARTY ceiling is too long for a 350px status line, so the line says
    -- "IN RANGE ONLY" and the whole sentence lives one hover away. Stating the
    -- limit somewhere the player will actually meet it is the point (D9).
    statusLine:EnableMouse(true)
    Commander.UI.AttachTooltip(statusLine, "Spoils", function()
        if DB.ViewMode == "PARTY" then
            return "Party rows come from loot messages you were in range to see, and from roll history. Other players' gold, bags and gear are not knowable — the game does not broadcast them.|n|nThe ledger resets when the group does."
        end
        return format("%s.|n|nThe per-hour figure is the last five minutes, not the session average.",
            E.LootMethodText())
    end)
    BuildGlow(); BuildPulse()

    -- Escape hides the frame directly, past the toggle, so the persisted state
    -- has to follow. A corpse being read ends its server session here — but
    -- ONLY here: never from a restyle or a parent hiding, which is the mirror
    -- of the FrameXML LootFrame_OnHide trap this module exists to avoid.
    mainFrame:HookScript("OnHide", function()
        if not DB then return end
        DB.Expanded = false
        if corpseBand:IsShown() and E.lootOpen and UIParent:IsShown() then
            if type(_G.CloseLoot) == "function" then pcall(_G.CloseLoot) end
        end
    end)

    header.glyphs.expand:SetScript("OnClick", CommanderSpoils_Toggle)
    header.glyphs.wipe:SetScript("OnClick", function() CommanderSpoils_Wipe() end)
    header.glyphs.wipe:SetScript("OnEnter", function(self)
        if GetTime() <= wipeArmedUntil then SetGlyphColor(self, THEME.bad) end
    end)
    header.glyphs.wipe:SetScript("OnLeave", function(self)
        SetGlyphColor(self, THEME.textDim)
    end)
    header.glyphs.farm:SetScript("OnClick", function() CommanderSpoils_ToggleFarm() end)
    header.glyphs.filter:SetScript("OnClick", function(self)
        OpenMenu(function()
            for _, spec in ipairs({
                { "FilterArmor", "Gear for my armor type" },
                { "FilterRecipes", "Recipes and patterns" },
                { "FilterTradeGoods", "Trade goods" },
                { "FilterConsumables", "Consumables" },
                { "FilterQuest", "Quest items" },
                { "FilterBoP", "Anything bind-on-pickup" },
            }) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = spec[2]
                info.checked = DB[spec[1]]
                info.keepShownOnClick = true
                info.func = function() DB[spec[1]] = not DB[spec[1]]; Commander.Notify(EV.UPDATE) end
                UIDropDownMenu_AddButton(info)
            end
            if DB.ViewMode == "HAUL" then
                for _, spec in ipairs({ { "VALUE", "Sort by value" }, { "QTY", "Sort by quantity" },
                                        { "NAME", "Sort by name" } }) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = spec[2]
                    info.checked = DB.HaulSort == spec[1]
                    info.func = function() DB.HaulSort = spec[1]; Commander.Notify(EV.UPDATE) end
                    UIDropDownMenu_AddButton(info)
                end
            end
        end, self)
    end)
    Commander.UI.AttachTooltip(header.glyphs.expand, "Panes",
        "Open the browsing panes: the feed, the haul, the roll log, your bags and the party.")
    Commander.UI.AttachTooltip(header.glyphs.filter, "What gets announced",
        "Which item classes raise a pickup notice. Right-click any row to pin or mute a single item.")
    Commander.UI.AttachTooltip(header.glyphs.farm, "Farm",
        "Start or stop a named farm segment. It survives a client restart, unlike the session.")
    Commander.UI.AttachTooltip(header.glyphs.wipe, "Wipe history",
        "Clears the whole ledger. Settings are untouched. There is no undo.")
    Commander.UI.AttachTooltip(header.value, "Value acquired", function()
        local stats = E.Fold(ScopeSegment())
        local rateValue, rateItems = E.TrailingRate(5)
        local text = format("%s of items plus %s of coin.|n|nLast 5 minutes: %s/hr, %d items/hr.",
            CoinShort(stats.value), CoinShort(stats.gold),
            CoinShort(floor(rateValue)), floor(rateItems))
        if stats.coverage then
            text = text .. format("|n|nMarket priced %d%% of these items%s. The rest are at vendor price.",
                floor(stats.coverage * 100 + 0.5),
                stats.stalestDays and format(", oldest scan %d day%s old",
                    floor(stats.stalestDays), floor(stats.stalestDays) == 1 and "" or "s") or "")
        end
        if stats.otherValue > 0 then
            text = text .. format("|n|nA further %s arrived by mail, vendor or trade — in the ledger, not counted as income.",
                CoinShort(stats.otherValue))
        end
        return text .. "|n|nCLICK FOR THE ROWS"
    end)
    header.value:SetScript("OnClick", function()
        DB.Expanded, DB.ViewMode = true, "HAUL"
        Commander.Notify(EV.UPDATE)
    end)
    Commander.UI.AttachTooltip(header.bags, "Bag space", function()
        local census = E.Census()
        local text = format("%d free of %d slots.", census.slotsFree or 0, census.slotsTotal or 0)
        if census.minutesToFull then
            text = text .. format("|nAt the current rate, full in about %d minutes.",
                floor(census.minutesToFull))
        end
        if census.junk and census.junk.stacks > 0 then
            text = text .. format("|n%d junk stacks worth %s.",
                census.junk.stacks, CoinShort(census.junk.value))
        end
        return text .. "|n|nCLICK FOR THE ROWS"
    end)
    header.bags:SetScript("OnClick", function()
        DB.Expanded, DB.ViewMode = true, "BAGS"
        Commander.Notify(EV.UPDATE)
    end)

    for _, row in ipairs(corpseBand.rows) do
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(self)
            if not self.slot or fakeSlots then return end
            if self.assignable then
                mlSlot, armedCandidate = self.slot, nil
                PaintCorpse(); Layout()
                return
            end
            E.TakeSlot(self.slot)
        end)
        row:SetScript("OnEnter", function(self)
            if self.link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.link)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        for _, btn in ipairs(row.confirm) do
            btn:SetScript("OnClick", function(self)
                if self.take and not fakeSlots then E.ConfirmSlot(row.slot) end
                E.bindSlot = nil
                PaintCorpse(); Layout()
            end)
        end
    end
    for _, row in ipairs(corpseBand.candidates) do
        row:SetScript("OnClick", function(self)
            if armedCandidate ~= self.candidateIndex then
                -- Arming IS the confirmation: Blizzard's
                -- CONFIRM_LOOT_DISTRIBUTION dialog is suppressed, so this
                -- replaces the safety we removed.
                armedCandidate = self.candidateIndex
                PaintCorpse(); Layout()
                return
            end
            if type(_G.GiveMasterLoot) == "function" then
                pcall(_G.GiveMasterLoot, self.slot, self.candidateIndex)
            end
            armedCandidate, mlSlot = nil, nil
            PaintCorpse(); Layout()
        end)
    end

    for _, row in ipairs(rollBand.rows) do
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            local roll = self.roll
            if not roll then return end
            focusedRoll = roll.id
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            local shown = false
            if not roll.fake and GameTooltip.SetLootRollItem then
                shown = pcall(GameTooltip.SetLootRollItem, GameTooltip, roll.id)
            end
            if not shown and roll.link then GameTooltip:SetHyperlink(roll.link); shown = true end
            if not shown then GameTooltip:SetText(roll.name or "?", 1, 1, 1) end
            if #roll.rollers > 0 then
                GameTooltip:AddLine(" ")
                for _, entry in ipairs(roll.rollers) do
                    local cc = ClassColor(entry.class)
                    GameTooltip:AddDoubleLine(entry.name,
                        (E.RollTypeName[entry.rollType] or "—") .. "  " .. (entry.roll or "—"),
                        cc[1], cc[2], cc[3],
                        THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
                end
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        for _, btn in ipairs(row.buttons) do
            btn:SetScript("OnClick", function(self)
                local roll = row.roll
                if not roll then return end
                if self.confirmMode then
                    if self.rollType == 1 then
                        E.ConfirmRoll(roll.id, roll.confirm and roll.confirm.rollType or 1)
                    else
                        -- Declining un-casts the roll: leaving `my` set would
                        -- claim a Need that never happened and silence the
                        -- missed-roll counter.
                        E.DeclineRoll(roll.id)
                    end
                    return
                end
                if not self.eligible then return end
                if roll.fake then
                    roll.my = self.rollType
                    LayoutRollBand(); Layout()
                    return
                end
                E.Roll(roll.id, self.rollType)
            end)
            btn:SetScript("OnEnter", function(self)
                if self.reason then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(self.baseLabel, 1, 1, 1)
                    GameTooltip:AddLine(self.reason, THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], true)
                    GameTooltip:Show()
                end
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
    end
    rollBand.passAll:SetScript("OnClick", function() E.PassAll() end)
    rollBand:EnableMouseWheel(true)
    rollBand:SetScript("OnMouseWheel", function() CycleFocus() end)

    -- The engine repaints the corpse through this rather than the settings
    -- bus, so a bind confirm reaches the band even with the panes closed.
    E.OnSalvageDirty = function()
        if not DB.EnableSpoils then return end
        if corpseBand:IsShown() then PaintCorpse() else OpenCorpse() end
        MarkDirty()
        Reconcile()
    end
    -- Item data arriving late is a repaint, not a relayout.
    E.OnDataDirty = MarkDirty

    E.Init()

    Commander.AddListener(EV.UPDATE, Apply)
    Commander.AddListener(EV.LOOT, OnLootEntry)
    Commander.AddListener(EV.ROLL, OnRollEvent)
    Commander.AddListener(EV.CENSUS, MarkDirty)
    Commander.AddListener(EV.OUTFLOW, MarkDirty)
    Commander.AddListener(EV.MONEY, MarkDirty)

    local lootWatch = CreateFrame("Frame")
    lootWatch:RegisterEvent("LOOT_OPENED")
    lootWatch:RegisterEvent("LOOT_CLOSED")
    lootWatch:RegisterEvent("LOOT_SLOT_CLEARED")
    lootWatch:RegisterEvent("LOOT_SLOT_CHANGED")
    lootWatch:SetScript("OnEvent", function(_, event)
        if not DB.EnableSpoils then return end
        if event == "LOOT_OPENED" then
            OpenCorpse(); Apply()
        elseif event == "LOOT_CLOSED" then
            CloseCorpse(); Apply()
        elseif corpseBand:IsShown() then
            E.RebuildSlots()
            PaintCorpse(); Layout()
            if #E.slots == 0 then CloseCorpse(); Apply() end
        end
    end)

    Apply()

    -- First run just opens the window and explains itself. Nothing needs
    -- forcing off any more — every suppression defaults off, so a fresh
    -- install and a Restore Defaults land in the same honest place.
    if not DB.SeenIntro then
        DB.SeenIntro = true
        DB.Expanded = true
        Apply()
        print("|cff66ccffCommander Spoils|r: loot can live in one window instead of your chat frame. Nothing has changed yet — the settings page has Try It buttons that show you each piece, and |cffffffff/cspoils takeover|r hands Spoils the lot. |cffffffff/cspoils restore|r undoes everything, any time.")
    end

    -- Tells the DB file's watchdog that the UI got here. Without this flag,
    -- everything Blizzard is handed back two seconds from now.
    CommanderSpoils_Ready = true
end)
