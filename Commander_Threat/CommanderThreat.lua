-- Commander Threat: the board layer + the client-API sampler. A 4 Hz ticker
-- reads UnitDetailedThreatSituation for the whole group against the display
-- mob (attackable target, else target-of-target — Omen's load-bearing
-- fallback), sweeps nameplates for the tank/healer facts, feeds it all to
-- CommanderThreatEngine, and paints. Poll-only by design: the ticker
-- re-reads the whole truth 4×/s, so no threat event delivery needs
-- trusting, and a missed event can never wedge a stale warning.
--
-- Visual contract (Meters' RTS rule: built for someone who is NOT looking
-- at it): geometry never shifts — header, headline block, bar rows, and
-- footer are constants; only digits, bar order, and colors change. Class
-- colors are the data encoding on bars and are never overridden; the
-- single accent marks chrome; the role-aware status colors carry meaning
-- (a tank securely tanking reads green, a DPS at the ledge reads red —
-- same fact, opposite meanings). ONE bar scaling for every role: scaled
-- percentage, so full bar width IS the pull point — the aggro holder rides
-- at 100% and everyone else's bar shows true distance to the ledge.

local E = CommanderThreatEngine
local db

-- ---------------------------------------------------------------------------
-- Theme: the whole skin, one flat table
-- ---------------------------------------------------------------------------

local THEME = {
    font = "Fonts\\ARIALN.TTF", -- condensed, uniform digit widths (no jitter)

    bg      = { 0.045, 0.055, 0.065, 0.92 }, -- board fill
    chrome  = { 0.09, 0.11, 0.13, 1 },       -- header strip
    edge    = { 0.22, 0.27, 0.31, 1 },       -- thin panel edges
    accent  = { 1.0, 0.72, 0.10 },           -- chrome/active — the only accent
    text    = { 0.92, 0.94, 0.95 },
    textDim = { 0.52, 0.58, 0.62 },
    barBack = { 1, 1, 1, 0.04 },             -- empty bar track
    trackMe = { 1, 1, 1, 0.10 },             -- your row's track, slightly lit
    barAlpha = 0.30,                         -- class-colored bar fill alpha
    neutral = { 0.6, 0.65, 0.7 },            -- pets and classless units

    -- Role-aware status colors: what the number MEANS, not who it is
    statSafe   = { 0.40, 0.85, 0.45 },
    statWarn   = { 1.00, 0.72, 0.10 },
    statHot    = { 0.95, 0.55, 0.20 },
    statDanger = { 0.85, 0.25, 0.20 },

    rowGap = 1,
}

-- Density: every metric that differs between the two board layouts, in one
-- table each, so the layout is a lookup and never a branch in the painters.
-- COMPACT keeps every FACT the full board shows except the mob name (the
-- target frame already says it) — the headline block folds up into the
-- header strip at reading size and the rows tighten. HIDDEN draws no board
-- at all and reuses FULL's numbers so nothing divides by a missing metric.
local DENSITY = {
    FULL = {
        headerH = 20, headlineH = 30, rowH = 16, footerH = 16,
        bottomPad = 4, footPad = 5,
        normal = 11, small = 10, big = 20,
        rankW = 16, tpsW = 44, pctW = 40,
        nameRight = -92, nameRightNoTps = -46, nameLeft = 22,
    },
    COMPACT = {
        headerH = 18, headlineH = 0.001, rowH = 13, footerH = 14,
        bottomPad = 3, footPad = 4,
        normal = 10, small = 9, big = 13,
        rankW = 14, tpsW = 38, pctW = 34,
        nameRight = -80, nameRightNoTps = -40, nameLeft = 19,
    },
}
DENSITY.HIDDEN = DENSITY.FULL

local M = DENSITY.FULL -- current metrics; re-pointed by ApplyDensity

local WHITE = "Interface\\Buttons\\WHITE8X8"

-- Accent presets + the suite tints through Commander_Console's palette (the
-- TopBar/Meters pattern): any key the local table doesn't know is looked up
-- there, CLASS resolves live, unknown keys fall back to amber.
local ACCENTS = {
    AMBER = { 1.0, 0.72, 0.10 },
    CYAN  = { 0.25, 0.85, 0.95 },
    GREEN = { 0.35, 0.90, 0.40 },
    RED   = { 0.95, 0.35, 0.30 },
    WHITE = { 0.95, 0.95, 0.95 },
}

local function AccentByKey(key)
    if key == "CLASS" then
        local info = Commander.GetClassInfo and Commander.GetClassInfo()
        if info and info.color then
            -- Copy, never alias: GetClassInfo memoizes that table suite-wide
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

-- Bake the accent into THEME once, before any widget is built — no
-- restyling passes; the settings panel says /reload (the Meters pattern)
local function ResolveThemeOverrides()
    THEME.accent = AccentByKey(db.AccentColor)
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

local function EscOf(c)
    return format("|cff%02x%02x%02x",
        c[1] * 255 + 0.5, c[2] * 255 + 0.5, c[3] * 255 + 0.5)
end

-- Every fontstring the board owns is registered with its SIZE KIND, never a
-- number: the density switch re-fonts the whole board in one pass instead of
-- hunting anchors, and rows built later inherit the current density for free.
local fontKinds = {} -- array of { fs = <fontstring>, kind = "normal"|... }

local function MakeText(parent, kind, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    kind = kind or "normal"
    fs:SetFont(THEME.font, M[kind], "")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])
    fs:SetWordWrap(false)
    fontKinds[#fontKinds + 1] = { fs = fs, kind = kind }
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

-- The number's meaning as a color: distance to the ledge (Damage/Healer's
-- own %, or the chaser's % against a tank)
local function BandColor(pct)
    local warnAt = (db and db.WarnAt) or 80
    if pct >= 100 then return THEME.statDanger end
    if pct >= warnAt then return THEME.statHot end
    if pct >= warnAt - 15 then return THEME.statWarn end
    return THEME.statSafe
end

local function BandWord(pct)
    local warnAt = (db and db.WarnAt) or 80
    if pct >= 100 then return "PULL" end
    if pct >= warnAt then return "HOT" end
    if pct >= warnAt - 15 then return "RISING" end
    return "SAFE"
end

-- ---------------------------------------------------------------------------
-- Roster + sampling
-- ---------------------------------------------------------------------------

local rosterUnits = {}

local function RefreshRoster()
    wipe(rosterUnits)
    local n = 0
    if IsInRaid() then
        -- The player is one of the raidN tokens; adding "player" too would
        -- only feed the GUID dedupe below
        for i = 1, GetNumGroupMembers() do
            n = n + 1; rosterUnits[n] = "raid" .. i
            n = n + 1; rosterUnits[n] = "raidpet" .. i
        end
    else
        n = n + 1; rosterUnits[n] = "player"
        n = n + 1; rosterUnits[n] = "pet"
        if IsInGroup() then
            for i = 1, 4 do
                n = n + 1; rosterUnits[n] = "party" .. i
                n = n + 1; rosterUnits[n] = "partypet" .. i
            end
        end
    end
end

-- Omen's load-bearing fallback: a healer targeting the tank reads the
-- tank's target's threat list
local function DisplayMob()
    if UnitExists("target") and UnitCanAttack("player", "target") then
        return "target"
    end
    if UnitExists("targettarget") and UnitCanAttack("player", "targettarget") then
        return "targettarget"
    end
    return nil
end

local obs = {}     -- observation scratch, engine copies out of it
local obsSeen = {} -- per-scan GUID dedupe

local function ScanMob(mobUnit)
    local n = 0
    wipe(obsSeen)
    for i = 1, #rosterUnits do
        local unit = rosterUnits[i]
        if UnitExists(unit) then
            local tanking, status, scaled, raw, value = UnitDetailedThreatSituation(unit, mobUnit)
            if value then
                local guid = UnitGUID(unit)
                if guid and not obsSeen[guid] then
                    obsSeen[guid] = true
                    n = n + 1
                    local o = obs[n]
                    if not o then o = {}; obs[n] = o end
                    local isPet = unit:find("pet", 1, true) ~= nil
                    local _, classToken = UnitClass(unit)
                    o.guid = guid
                    o.name = UnitName(unit)
                    o.class = not isPet and classToken or nil -- pet "classes" are noise
                    o.isPlayer = UnitIsUnit(unit, "player")
                    o.isPet = isPet
                    o.value = value / 100 -- the API reports threat × 100
                    o.raw = raw or 0
                    o.scaled = scaled or 0
                    o.tanking = tanking and true or false
                    o.status = status or 0
                end
            end
        end
    end
    return n
end

-- A mob counts as engaged with US when we are on its threat list or its
-- target is in the group — never just "in combat", or someone else's world
-- mobs would pad a tank's held/loose counts
local function EngagedTarget(u)
    local tu = u .. "target"
    if not UnitExists(tu) then return nil end
    if UnitIsUnit(tu, "player") then return "player" end
    if UnitIsUnit(tu, "pet")
        or (UnitPlayerOrPetInParty and UnitPlayerOrPetInParty(tu))
        or (UnitPlayerOrPetInRaid and UnitPlayerOrPetInRaid(tu)) then
        return "group"
    end
    return nil
end

local function SweepPlates(roleNow, now)
    local engaged, held = 0, 0
    local worst, worstName, inbound = 0, nil, nil
    local plates = C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates()
    if plates then
        for i = 1, #plates do
            local u = plates[i].namePlateUnitToken
            if u and UnitExists(u) and UnitCanAttack("player", u)
                and not (UnitIsDeadOrGhost and UnitIsDeadOrGhost(u)) then
                local mine = UnitThreatSituation("player", u)
                local targets = EngagedTarget(u)
                if mine ~= nil or targets then
                    engaged = engaged + 1
                    if targets == "player" then
                        held = held + 1
                        if roleNow == "HEALER" and not inbound then
                            inbound = UnitName(u)
                        end
                    end
                    if roleNow == "HEALER" then
                        local tanking, _, scaled = UnitDetailedThreatSituation("player", u)
                        local eff = tanking and 100 or (scaled or 0)
                        if eff > worst then
                            worst, worstName = eff, UnitName(u)
                        end
                    end
                end
            end
        end
    end
    E.SetPlateFacts(engaged, held, worst, worstName, inbound, now)
end

-- ---------------------------------------------------------------------------
-- Alert delivery: board flash + klaxon + vignette
-- ---------------------------------------------------------------------------

-- Approaching the line is quieter than aggro actually moving
local ALERT_STRENGTH = {
    PULL_WARN = 0.5, CHASE_WARN = 0.5,
    AGGRO_GAINED = 0.85, AGGRO_LOST = 0.85, INBOUND = 0.7,
}

-- Full-screen red pulse: the Impact vignette language (LowHealth art is
-- itself red — exactly the color threat danger wants), decaying on a Frame
-- driver because Textures cannot carry OnUpdate scripts on this client
local vignette = { texture = nil, alpha = 0, decay = 1 }
local vignetteDriver = CreateFrame("Frame")

local function VignetteDecay(_, elapsed)
    vignette.alpha = vignette.alpha - elapsed * vignette.decay
    if vignette.alpha <= 0 then
        vignette.alpha = 0
        vignetteDriver:SetScript("OnUpdate", nil)
    end
    vignette.texture:SetAlpha(vignette.alpha)
end

local function PulseVignette(strength)
    if not vignette.texture then
        local t = WorldFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
        t:SetTexture("Interface\\FullScreenTextures\\LowHealth")
        t:SetAllPoints(WorldFrame)
        t:SetBlendMode("ADD")
        t:SetAlpha(0)
        vignette.texture = t
    end
    -- A weaker overlapping pulse must not re-extend a stronger active one
    if strength >= vignette.alpha then
        vignette.alpha = strength
        vignette.decay = strength / 1.1
        vignette.texture:SetAlpha(strength)
    end
    vignetteDriver:SetScript("OnUpdate", VignetteDecay)
end

-- ---------------------------------------------------------------------------
-- Frames (created once at PLAYER_LOGIN)
-- ---------------------------------------------------------------------------

local root, headerFrame, headFlash, headerTitle, mobText, roleBtn
local headlineFrame, bigText, labelText, statusText
local rowsFrame, footerText
local boardRows = {}
local menuFrame, menuBuilder
local view = { offset = 0 }
local testStart, testUntil = 0, 0
local Tick -- forward: the sampler/painter driven by the ticker
local FlashTarget -- forward: the target-frame readout's alert pulse

local flashAlpha = 0
local function FlashDecay(_, elapsed)
    flashAlpha = flashAlpha - elapsed * 1.2
    if flashAlpha <= 0 then
        headFlash:Hide()
        headerFrame:SetScript("OnUpdate", nil)
    else
        headFlash:SetAlpha(flashAlpha)
    end
end

local function FlashHeader()
    flashAlpha = 0.55
    headFlash:SetAlpha(flashAlpha)
    headFlash:Show()
    headerFrame:SetScript("OnUpdate", FlashDecay)
end

local function OnAlert(kind)
    FlashHeader()
    if FlashTarget then FlashTarget() end
    if db.WarnSound then
        pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
    end
    if db.WarnFlash then
        PulseVignette(ALERT_STRENGTH[kind] or 0.5)
    end
end

local function DrainAlerts()
    E.DrainAlerts(OnAlert)
end

local function OpenMenu(builder, anchor)
    menuBuilder = builder
    ToggleDropDownMenu(1, nil, menuFrame, anchor, 0, 0)
end

local ROLE_OPTIONS = {
    { text = "Tank", value = "TANK" },
    { text = "Damage", value = "DAMAGE" },
    { text = "Healer", value = "HEALER" },
}

local function RoleMenu()
    local current = E.GetRole()
    for _, option in ipairs(ROLE_OPTIONS) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = option.text
        info.checked = (option.value == current)
        local value = option.value
        info.func = function()
            CommanderThreat_SetRole(value)
        end
        UIDropDownMenu_AddButton(info)
    end
end

-- ---------------------------------------------------------------------------
-- Board construction
-- ---------------------------------------------------------------------------

local function BuildRows()
    local want = db.BarRows
    for i = 1, want do
        local row = boardRows[i]
        if not row then
            row = CreateFrame("Frame", nil, rowsFrame)
            row.track = row:CreateTexture(nil, "BACKGROUND")
            row.track:SetTexture(WHITE)
            row.track:SetAllPoints()
            row.bar = row:CreateTexture(nil, "ARTWORK")
            row.bar:SetTexture(WHITE)
            row.bar:SetPoint("TOPLEFT")
            row.bar:SetPoint("BOTTOMLEFT")
            -- The holder stripe: 2px on the row's left edge marking who the
            -- mob is actually on — data, so it stays out of the accent
            row.stripe = row:CreateTexture(nil, "OVERLAY")
            row.stripe:SetTexture(WHITE)
            row.stripe:SetVertexColor(THEME.text[1], THEME.text[2], THEME.text[3], 0.9)
            row.stripe:SetWidth(2)
            row.stripe:SetPoint("TOPLEFT")
            row.stripe:SetPoint("BOTTOMLEFT")
            row.stripe:Hide()
            -- Fixed columns; only digits and bar order ever change
            row.rank = MakeText(row, "small", "RIGHT")
            row.rank:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
            row.name = MakeText(row, "normal", "LEFT")
            row.tps = MakeText(row, "normal", "RIGHT")
            row.tps:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
            row.pct = MakeText(row, "normal", "RIGHT")
            boardRows[i] = row
        end
        -- Column geometry is re-applied every call, not just at creation: the
        -- density switch runs through here
        row:SetHeight(M.rowH)
        row.rank:ClearAllPoints()
        row.rank:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.rank:SetWidth(M.rankW)
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", row, "LEFT", M.nameLeft, 0)
        row.tps:ClearAllPoints()
        row.tps:SetPoint("RIGHT", row, "RIGHT", M.nameRightNoTps, 0)
        row.tps:SetWidth(M.tpsW)
        row.pct:ClearAllPoints()
        row.pct:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.pct:SetWidth(M.pctW)
        -- The name column keeps whatever room the TPS column releases
        row.name:SetPoint("RIGHT", row, "RIGHT",
            db.ShowTPS and M.nameRight or M.nameRightNoTps, 0)
        row.tps:SetShown(db.ShowTPS and true or false)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", rowsFrame, "TOPLEFT", 0, -((i - 1) * (M.rowH + THEME.rowGap)))
        row:SetPoint("RIGHT", rowsFrame, "RIGHT", 0, 0)
        row:Show()
    end
    for i = want + 1, #boardRows do
        boardRows[i]:Hide()
    end
end

local function Layout()
    local slots = db.BarRows
    local rowsHeight = slots * (M.rowH + THEME.rowGap)
    root:SetSize(db.FrameWidth,
        M.headerH + M.headlineH + rowsHeight + M.footerH + M.bottomPad)
    rowsFrame:SetHeight(rowsHeight)
end

-- Re-point every metric-dependent widget at the current density. Runs on
-- login and on any settings change, so Full ⇄ Compact is instant — no
-- /reload note, because nothing here is baked at creation (the accent is).
local function ApplyDensity()
    local compact = (db.BoardLayout == "COMPACT")
    for i = 1, #fontKinds do
        local e = fontKinds[i]
        e.fs:SetFont(THEME.font, M[e.kind], "")
    end

    headerFrame:SetHeight(M.headerH)
    headlineFrame:SetHeight(M.headlineH)
    roleBtn:SetHeight(M.headerH)

    -- Compact folds the headline trio up into the header strip: the static
    -- THREAT word and the mob name yield the room (the title is decoration,
    -- and the mob's name is on the target frame you are already looking at)
    headerTitle:SetShown(not compact)
    mobText:SetShown(not compact)

    bigText:ClearAllPoints()
    labelText:ClearAllPoints()
    statusText:ClearAllPoints()
    if compact then
        bigText:SetParent(headerFrame)
        labelText:SetParent(headerFrame)
        statusText:SetParent(headerFrame)
        bigText:SetPoint("LEFT", headerFrame, "LEFT", 6, 0)
        statusText:SetPoint("RIGHT", roleBtn, "LEFT", -4, 0)
        labelText:SetPoint("LEFT", bigText, "RIGHT", 6, 0)
        labelText:SetPoint("RIGHT", statusText, "LEFT", -6, 0)
    else
        bigText:SetParent(headlineFrame)
        labelText:SetParent(headlineFrame)
        statusText:SetParent(headlineFrame)
        bigText:SetPoint("LEFT", headlineFrame, "LEFT", 6, 0)
        statusText:SetPoint("RIGHT", headlineFrame, "RIGHT", -6, 0)
        labelText:SetPoint("LEFT", bigText, "RIGHT", 8, -1)
        labelText:SetPoint("RIGHT", statusText, "LEFT", -6, 0)
    end

    footerText:ClearAllPoints()
    footerText:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 6, M.footPad)
    footerText:SetPoint("RIGHT", root, "RIGHT", -6, 0)
end

local function BuildBoard()
    root = CreateFrame("Frame", "CommanderThreatFrame", UIParent)
    root:SetFrameStrata("MEDIUM")
    root:SetClampedToScreen(true)
    root.fill = root:CreateTexture(nil, "BACKGROUND")
    root.fill:SetTexture(WHITE)
    root.fill:SetVertexColor(THEME.bg[1], THEME.bg[2], THEME.bg[3], THEME.bg[4])
    root.fill:SetAllPoints()
    MakeEdge(root)

    headerFrame = CreateFrame("Frame", nil, root)
    headerFrame:SetHeight(M.headerH)
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

    headerTitle = MakeText(headerFrame, "small", "LEFT")
    headerTitle:SetPoint("LEFT", headerFrame, "LEFT", 6, 0)
    headerTitle:SetText("THREAT")
    headerTitle:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])

    -- Alert flash over the whole strip; fades on the header's OnUpdate
    -- (Textures cannot carry OnUpdate scripts on this client). Kept UNDER
    -- the OVERLAY text: compact parks the headline percentage in this strip,
    -- and an alert must never wash out the number it is alerting about.
    headFlash = headerFrame:CreateTexture(nil, "ARTWORK", nil, 7)
    headFlash:SetTexture(WHITE)
    headFlash:SetVertexColor(THEME.statDanger[1], THEME.statDanger[2], THEME.statDanger[3], 1)
    headFlash:SetAllPoints()
    headFlash:Hide()

    -- The role tag: the board-side face of the role dropdown
    roleBtn = CreateFrame("Button", nil, headerFrame)
    roleBtn.headerRole = "role" -- how the headless harness finds it
    roleBtn:SetHeight(M.headerH)
    roleBtn:SetWidth(58)
    roleBtn:SetPoint("RIGHT", headerFrame, "RIGHT", 0, 0)
    roleBtn.text = MakeText(roleBtn, "small", "RIGHT")
    roleBtn.text:SetPoint("RIGHT", roleBtn, "RIGHT", -6, 0)
    roleBtn.text:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])
    roleBtn.hover = roleBtn:CreateTexture(nil, "HIGHLIGHT")
    roleBtn.hover:SetTexture(WHITE)
    roleBtn.hover:SetVertexColor(1, 1, 1, 0.06)
    roleBtn.hover:SetAllPoints()
    roleBtn:SetScript("OnClick", function(self)
        OpenMenu(RoleMenu, self)
    end)
    Commander.UI.AttachTooltip(roleBtn, "Role",
        "Which side of threat this character manages — the whole board reshapes around it. Click to switch (kept per character; also /cthreat tank, damage, healer).")

    mobText = MakeText(headerFrame, "small", "LEFT")
    mobText:SetPoint("LEFT", headerTitle, "RIGHT", 8, 0)
    mobText:SetPoint("RIGHT", roleBtn, "LEFT", -4, 0)
    mobText:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])

    headlineFrame = CreateFrame("Frame", nil, root)
    headlineFrame:SetHeight(M.headlineH)
    headlineFrame:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, 0)
    headlineFrame:SetPoint("RIGHT", root, "RIGHT", 0, 0)
    -- The headline trio is re-parented and re-anchored by ApplyDensity (into
    -- the header strip when compact); only its content is painted below
    bigText = MakeText(headlineFrame, "big", "LEFT")
    statusText = MakeText(headlineFrame, "normal", "RIGHT")
    labelText = MakeText(headlineFrame, "small", "LEFT")
    labelText:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])

    rowsFrame = CreateFrame("Frame", nil, root)
    rowsFrame:SetPoint("TOPLEFT", headlineFrame, "BOTTOMLEFT", 0, 0)
    rowsFrame:SetPoint("RIGHT", root, "RIGHT", 0, 0)
    rowsFrame:EnableMouseWheel(true)
    rowsFrame:SetScript("OnMouseWheel", function(_, delta)
        view.offset = math.max(0, view.offset - delta)
        if Tick then Tick() end
    end)

    footerText = MakeText(root, "small", "LEFT")
    footerText:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])

    menuFrame = CreateFrame("Frame", "CommanderThreatMenu", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(menuFrame, function()
        if menuBuilder then menuBuilder() end
    end, "MENU")
end

-- ---------------------------------------------------------------------------
-- Painting
-- ---------------------------------------------------------------------------

local function SetColor(fs, c)
    fs:SetTextColor(c[1], c[2], c[3])
end

-- Your own percentage's color, read through your role
local function PlayerPctColor(r)
    if r.tanking then
        if E.GetRole() == "TANK" then
            return r.status == 3 and THEME.statSafe or THEME.statWarn
        end
        return THEME.statDanger
    end
    return BandColor(r.scaled)
end

local function PaintRow(row, r)
    row.rank:SetText(r.rank)
    if r.isPlayer then
        SetColor(row.rank, THEME.accent)
        row.track:SetVertexColor(THEME.trackMe[1], THEME.trackMe[2], THEME.trackMe[3], THEME.trackMe[4])
    else
        SetColor(row.rank, THEME.textDim)
        row.track:SetVertexColor(THEME.barBack[1], THEME.barBack[2], THEME.barBack[3], THEME.barBack[4])
    end
    row.name:SetText(ShortName(r.name))
    local cc = r.isPet and THEME.neutral or ClassColor(r.class)
    row.name:SetTextColor(cc[1], cc[2], cc[3])
    if db.ShowTPS then
        row.tps:SetText(r.tps and r.tps >= 1 and FmtNum(r.tps) or "")
    end
    row.pct:SetText(format("%d%%", math.min(r.scaled, 999) + 0.5))
    if r.isPlayer then
        SetColor(row.pct, PlayerPctColor(r))
    else
        SetColor(row.pct, THEME.textDim)
    end
    local frac = r.scaled / 100
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    row.bar:SetWidth(math.max(0.001, frac * (root:GetWidth() or db.FrameWidth)))
    row.bar:SetVertexColor(cc[1], cc[2], cc[3], THEME.barAlpha)
    row.stripe:SetShown(r.tanking and true or false)
    row:Show()
end

local function PaintRows()
    local rows, n = E.Rows()
    local slots = db.BarRows
    local maxOffset = n > slots and (n - slots) or 0
    if view.offset > maxOffset then view.offset = maxOffset end

    if n == 0 then
        local row = boardRows[1]
        if row then
            row.rank:SetText("")
            row.name:SetText("No threat data")
            row.name:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
            if db.ShowTPS then row.tps:SetText("") end
            row.pct:SetText("")
            row.bar:SetWidth(0.001)
            row.track:SetVertexColor(THEME.barBack[1], THEME.barBack[2], THEME.barBack[3], THEME.barBack[4])
            row.stripe:Hide()
            row:Show()
        end
        for i = 2, slots do
            if boardRows[i] then boardRows[i]:Hide() end
        end
        return
    end

    local p = E.PlayerRow()
    local visN = n < slots and n or slots
    for i = 1, visN do
        local r = rows[view.offset + i]
        -- Omen's "always show self": when your rank is outside the visible
        -- window, the last slot becomes you, real rank and all
        if i == visN and p and (p.rank <= view.offset or p.rank > view.offset + visN) then
            r = p
        end
        PaintRow(boardRows[i], r)
    end
    for i = visN + 1, slots do
        if boardRows[i] then boardRows[i]:Hide() end
    end
end

local function PaintHeadline()
    local roleNow = E.GetRole()
    local p = E.PlayerRow()
    local _, name = E.Mob()
    local plate = E.PlateFacts()
    local _, n = E.Rows()

    mobText:SetText(name and name:upper() or "")
    roleBtn.text:SetText(roleNow)

    local big, bigC, label, status, statusC

    if roleNow == "TANK" then
        if p and p.tanking then
            local chase, chaser = E.ChaserScaled()
            big = format("%d%%", chase + 0.5)
            bigC = BandColor(chase)
            label = chaser and ("CHASE · " .. ShortName(chaser.name):upper()) or "NO CHASE"
            if p.status == 3 then
                status, statusC = "SECURE", THEME.statSafe
            else
                status, statusC = "SLIPPING", THEME.statWarn
            end
        elseif p then
            big = format("%d%%", math.min(p.scaled, 999) + 0.5)
            bigC = THEME.statDanger
            local holder = E.TankingRow()
            label = holder and ("TO TAKE · " .. ShortName(holder.name):upper()) or "TO TAKE"
            status, statusC = "NOT TANKING", THEME.statDanger
        else
            big, bigC = "—", THEME.textDim
            label, status, statusC = n > 0 and "NOT ON LIST" or "NO THREAT", "", THEME.textDim
        end
    elseif roleNow == "HEALER" then
        local eff = 0
        local effName
        if p then
            eff = p.tanking and 100 or p.scaled
        end
        if plate.worst > eff then
            eff, effName = plate.worst, plate.worstName
        end
        if p or plate.engaged > 0 then
            big = format("%d%%", math.min(eff, 999) + 0.5)
            bigC = BandColor(eff)
            local peakName = effName or name
            label = peakName and ("PEAK · " .. peakName:upper()) or "PEAK"
        else
            big, bigC = "—", THEME.textDim
            label = "NO THREAT"
        end
        if plate.inbound then
            status, statusC = "INBOUND", THEME.statDanger
        elseif p and p.tanking then
            status, statusC = "AGGRO", THEME.statDanger
        elseif p or plate.engaged > 0 then
            status, statusC = BandWord(eff), BandColor(eff)
        else
            status, statusC = "", THEME.textDim
        end
    else -- DAMAGE
        if p and p.tanking then
            big, bigC = "AGGRO", THEME.statDanger
            label = name and name:upper() or ""
            status, statusC = "", THEME.statDanger
        elseif p then
            big = format("%d%%", math.min(p.scaled, 999) + 0.5)
            bigC = BandColor(p.scaled)
            label = "TO PULL"
            status, statusC = BandWord(p.scaled), BandColor(p.scaled)
        else
            big, bigC = "—", THEME.textDim
            label, status, statusC = "NO THREAT", "", THEME.textDim
        end
    end

    bigText:SetText(big)
    SetColor(bigText, bigC)
    labelText:SetText(label or "")
    statusText:SetText(status or "")
    SetColor(statusText, statusC)
end

local function PaintFooter()
    local roleNow = E.GetRole()
    local plate = E.PlateFacts()
    if roleNow == "TANK" then
        if plate.engaged > 0 then
            local text = format("HELD %d/%d", plate.held, plate.engaged)
            if plate.loose > 0 then
                text = text .. "   " .. EscOf(THEME.statDanger) .. "LOOSE " .. plate.loose .. "|r"
            end
            footerText:SetText(text)
        else
            footerText:SetText("HELD —")
        end
    elseif roleNow == "HEALER" then
        if plate.inbound then
            footerText:SetText(EscOf(THEME.statDanger) .. "INBOUND · " .. plate.inbound:upper() .. "|r")
        else
            footerText:SetText("INBOUND · NONE")
        end
    else
        local holder = E.TankingRow()
        if holder then
            local cc = holder.isPet and THEME.neutral or ClassColor(holder.class)
            footerText:SetText("HOLDER · " .. EscOf(cc) .. ShortName(holder.name):upper() .. "|r")
        else
            footerText:SetText("HOLDER · —")
        end
    end
end

local function Paint()
    if not root then return end
    PaintHeadline()
    PaintRows()
    PaintFooter()
end

-- ---------------------------------------------------------------------------
-- Meters embed: the threat list as a live pane inside Commander_Meters,
-- through its external-mode contract (soft dependency, the TopBar pattern —
-- everything here no-ops when Meters is absent). The engine, the tick, and
-- every warning run exactly as before; only the rendering surface moves,
-- and the standalone board retires while the embed is active.
-- ---------------------------------------------------------------------------

local embedRegistered = false
local providerRows = {} -- pooled display rows handed to Meters' 2 Hz repaint

local function EmbedActive()
    return (db and db.MetersEmbed and embedRegistered) or false
end

-- Meters' split view condenses to rank/name/value columns, so the scaled
-- percentage — the number that matters — rides in valueText; the wide
-- window adds absolute threat (pctText) and TPS (rateText)
local function ProviderCollect()
    local rows, n = E.Rows()
    for i = 1, n do
        local r = rows[i]
        local out = providerRows[i]
        if not out then out = {}; providerRows[i] = out end
        out.name = r.name
        out.class = (not r.isPet) and r.class or nil
        out.valueText = format("%d%%", math.min(r.scaled, 999) + 0.5)
        out.pctText = FmtNum(r.value)
        out.rateText = (db.ShowTPS and r.tps and r.tps >= 1) and FmtNum(r.tps) or ""
        local frac = r.scaled / 100
        if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
        out.barFrac = frac
    end
    return providerRows, n
end

local function ProviderCaption()
    local _, name = E.Mob()
    return name and name:upper() or "NO TARGET"
end

-- Idempotent: registration follows the setting. Called from Apply (login,
-- any settings change) so the embed also recovers if Meters loads without
-- Threat's checkbox being touched.
local function SyncEmbedRegistration()
    if not db then return end
    if db.MetersEmbed and not embedRegistered and CommanderMeters_RegisterExternalMode then
        embedRegistered = CommanderMeters_RegisterExternalMode({
            key = "THREAT",
            label = "THREAT",
            collect = ProviderCollect,
            caption = ProviderCaption,
            empty = "No threat data",
        }) and true or false
    elseif not db.MetersEmbed and embedRegistered then
        if CommanderMeters_RetireExternalMode then
            CommanderMeters_RetireExternalMode("THREAT")
        end
        embedRegistered = false
    end
end

-- The settings checkbox's set() calls this: enabling is an explicit user
-- action, so it also opens Meters' split with the THREAT pane. The silent
-- login path (SyncEmbedRegistration via Apply) never forces the split —
-- Meters' own SplitOpen/SplitMode persistence decides there.
function CommanderThreat_EmbedToggled(on)
    SyncEmbedRegistration()
    if on and embedRegistered and CommanderMeters_ShowExternalPane then
        CommanderMeters_ShowExternalPane("THREAT")
    end
end

-- ---------------------------------------------------------------------------
-- Target-frame readout: the same role-adaptive number drawn on Blizzard's
-- target frame, so it sits where your eyes already are. Two surfaces, freely
-- combined — a slim BAR along the bottom of the target's health bar (full
-- width IS the pull point: the board's encoding, unchanged) and the
-- percentage on a small PLATE centred on the target's portrait, hung either
-- just under it or just inside its top edge. Purely additive: the board, the
-- Meters embed, the engine, and every warning are untouched by it, and
-- everything here soft-fails if Blizzard's frame is not where we expect.
-- ---------------------------------------------------------------------------

local TARGET_BAR_H = 4
local TARGET_BAR_W = 119 -- Blizzard's target health bar width, if it reads 0
local TAG_H = 16
local TAG_MIN_W = 30

-- Which surfaces each mode draws. The tag's PLACEMENT is read from the mode
-- name itself in ApplyTargetPlacement, so this table stays a pure on/off map.
local TARGET_MODES = {
    OFF          = { bar = false, tag = false },
    BAR          = { bar = true,  tag = false },
    BELOW        = { bar = false, tag = true },
    BAR_BELOW    = { bar = true,  tag = true },
    PORTRAIT     = { bar = false, tag = true },
    BAR_PORTRAIT = { bar = true,  tag = true },
}

local tgt -- built once at login, nil if the target frame could not be found

local function TargetHealthBar()
    return _G.TargetFrameHealthBar
        or (_G.TargetFrame and (_G.TargetFrame.HealthBar or _G.TargetFrame.healthbar))
end

-- Blizzard names it globally and UnitFrame_Initialize also parks it on the
-- frame; take either
local function TargetPortrait()
    return _G.TargetFramePortrait or (_G.TargetFrame and _G.TargetFrame.portrait)
end

local function BuildTargetReadout()
    local host = _G.TargetFrame
    local hb = TargetHealthBar()
    if not host or not hb then return end

    -- Mouse stays off every piece: the target frame is protected and its
    -- clicks are load-bearing (the Resources player-frame precedent)
    local bar = CreateFrame("Frame", "CommanderThreatTargetBar", host)
    bar:EnableMouse(false)
    bar:SetHeight(TARGET_BAR_H)
    bar:SetPoint("BOTTOMLEFT", hb, "BOTTOMLEFT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", hb, "BOTTOMRIGHT", 0, 0)
    bar:SetFrameLevel((hb:GetFrameLevel() or 2) + 3)
    bar.track = bar:CreateTexture(nil, "ARTWORK")
    bar.track:SetTexture(WHITE)
    bar.track:SetVertexColor(0, 0, 0, 0.55)
    bar.track:SetAllPoints()
    bar.fill = bar:CreateTexture(nil, "OVERLAY")
    bar.fill:SetTexture(WHITE)
    bar.fill:SetPoint("TOPLEFT")
    bar.fill:SetPoint("BOTTOMLEFT")
    bar:Hide()

    -- The percentage rides its own small plate — dark fill and the board's
    -- thin steel edge — because it lands on Blizzard's portrait art, where
    -- bare text has nothing behind it to read against. Outlined type on top
    -- of the plate for the same reason.
    local tag = CreateFrame("Frame", "CommanderThreatTargetTag", host)
    tag:EnableMouse(false)
    tag:SetSize(TAG_MIN_W, TAG_H)
    -- Levelled off TargetFrameTextureFrame, where Blizzard's border art
    -- actually lives, and high enough to clear Commander_Casting's portrait
    -- ring (holder at that same source +5, glow/label overlay at +15 — it
    -- rings THIS portrait). A threat number is an alarm and a cast ring is
    -- information, so the alarm takes the z-order.
    local levelSource = _G.TargetFrameTextureFrame or host
    tag:SetFrameLevel(((levelSource.GetFrameLevel and levelSource:GetFrameLevel()) or 1) + 20)
    tag.fill = tag:CreateTexture(nil, "BACKGROUND")
    tag.fill:SetTexture(WHITE)
    tag.fill:SetVertexColor(0.02, 0.03, 0.04, 0.78)
    tag.fill:SetAllPoints()
    MakeEdge(tag)
    local text = tag:CreateFontString(nil, "OVERLAY")
    text:SetFont(THEME.font, 12, "OUTLINE")
    text:SetJustifyH("CENTER")
    text:SetPoint("CENTER", tag, "CENTER", 0, 0)
    text:SetWordWrap(false)
    tag:Hide()

    -- The alert pulse washes the whole health bar, so it reads the same
    -- whether the user runs Bar, Text, or both
    local flash = host:CreateTexture(nil, "OVERLAY")
    flash:SetTexture(WHITE)
    flash:SetVertexColor(THEME.statDanger[1], THEME.statDanger[2], THEME.statDanger[3], 1)
    flash:SetBlendMode("ADD")
    flash:SetPoint("TOPLEFT", hb, "TOPLEFT", 0, 0)
    flash:SetPoint("BOTTOMRIGHT", hb, "BOTTOMRIGHT", 0, 0)
    flash:SetAlpha(0)
    flash:Hide()

    tgt = { bar = bar, fill = bar.fill, tag = tag, text = text,
            flash = flash, healthBar = hb, live = false }
end

-- Re-anchor the plate for the current mode: hung just under the portrait, or
-- just inside its top edge, centred on it either way. The portrait is the
-- target frame's one landmark that never moves with a name, a level, or a
-- rare/elite border, which is why both placements key off it.
local function ApplyTargetPlacement()
    if not tgt then return end
    local tag = tgt.tag
    tag:ClearAllPoints()
    local portrait = TargetPortrait()
    if not portrait then
        -- No portrait to hang off: the number still gets somewhere honest
        tag:SetPoint("BOTTOMRIGHT", tgt.healthBar, "TOPRIGHT", 0, 1)
        return
    end
    if db.TargetEmbed == "PORTRAIT" or db.TargetEmbed == "BAR_PORTRAIT" then
        tag:SetPoint("TOP", portrait, "TOP", 0, -2)
    else
        tag:SetPoint("TOP", portrait, "BOTTOM", 0, -1)
    end
end

-- The plate grows to whatever the string needs, but only when the string
-- actually changes: this runs 4×/s
local function SetTagText(value)
    if tgt.lastTagText == value then return end
    tgt.lastTagText = value
    tgt.text:SetText(value)
    local width = tgt.text:GetStringWidth() or 0
    tgt.tag:SetWidth(math.max(TAG_MIN_W, width + 10))
end

local tgtFlashAlpha = 0
local tgtFlashDriver = CreateFrame("Frame")

local function TargetFlashDecay(_, elapsed)
    tgtFlashAlpha = tgtFlashAlpha - elapsed * 1.4
    if tgtFlashAlpha <= 0 then
        tgtFlashAlpha = 0
        tgt.flash:Hide()
        tgtFlashDriver:SetScript("OnUpdate", nil)
        return
    end
    tgt.flash:SetAlpha(tgtFlashAlpha)
end

-- Only pulses when the readout is actually showing a number: a wash over an
-- empty target frame would be a warning about nothing
FlashTarget = function()
    if not tgt or not tgt.live then return end
    tgtFlashAlpha = 0.45
    tgt.flash:SetAlpha(tgtFlashAlpha)
    tgt.flash:Show()
    tgtFlashDriver:SetScript("OnUpdate", TargetFlashDecay)
end

-- The number, read through the role, for the targeted mob: Damage and Healer
-- see their own climb (AGGRO once it is theirs); a tank sees the chaser's
-- climb while holding, and their own climb to take it back when not. nil
-- means there is nothing honest to show.
local function TargetReading()
    local p = E.PlayerRow()
    if not p then return nil end
    if E.GetRole() == "TANK" then
        if p.tanking then
            local chase = E.ChaserScaled()
            return chase, BandColor(chase), false
        end
        return math.min(p.scaled, 999), THEME.statDanger, false
    end
    if p.tanking then
        return 100, THEME.statDanger, true
    end
    return math.min(p.scaled, 999), BandColor(p.scaled), false
end

local function PaintTarget()
    if not tgt then return end
    local spec = TARGET_MODES[db.TargetEmbed] or TARGET_MODES.OFF
    local pct, color, aggro
    -- Attackable target only: an unattackable one means the engine's list
    -- came from target-of-target (Omen's fallback, D1), and that mob's
    -- number does not belong on THIS frame
    if db.EnableThreat and (spec.bar or spec.tag)
        and UnitExists("target") and UnitCanAttack("player", "target") then
        pct, color, aggro = TargetReading()
    end
    if not pct then
        tgt.live = false
        tgt.bar:Hide()
        tgt.tag:Hide()
        return
    end
    tgt.live = true
    if spec.bar then
        local frac = pct / 100
        if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
        local width = tgt.healthBar:GetWidth() or 0
        if width <= 0 then width = TARGET_BAR_W end
        tgt.fill:SetWidth(math.max(0.001, frac * width))
        tgt.fill:SetVertexColor(color[1], color[2], color[3], 0.9)
        tgt.bar:Show()
    else
        tgt.bar:Hide()
    end
    if spec.tag then
        SetTagText(aggro and "AGGRO" or format("%d%%", math.min(pct, 999) + 0.5))
        tgt.text:SetTextColor(color[1], color[2], color[3])
        tgt.tag:Show()
    else
        tgt.tag:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Visibility + apply
-- ---------------------------------------------------------------------------

-- The standalone board draws only when it is the chosen surface: a Hidden
-- layout or a live Meters embed retires it outright
local function BoardActive()
    return (db.EnableThreat and db.BoardLayout ~= "HIDDEN" and not EmbedActive()) or false
end

local function UpdateVisibility()
    if not root then return end
    -- The target-frame readout is an independent surface, so it repaints on
    -- every tick path — including the ones that return before Paint()
    PaintTarget()
    -- No unlock exception for a retired board: there is nothing to place,
    -- and the warnings plus the target readout keep running from the tick
    if not BoardActive() then
        root:SetShown(false)
        return
    end
    local show = false
    if not db.CombatOnly then
        show = true
    else
        local _, n = E.Rows()
        show = InCombatLockdown() or n > 0 or testStart > 0
    end
    if Commander.UI.HudUnlocked(db, "Hud") then
        show = true
    end
    root:SetShown(show)
end

local function Apply()
    if not root then return end
    E.SetRole(CommanderThreat_GetRole())
    SyncEmbedRegistration()
    ApplyTargetPlacement()
    M = DENSITY[db.BoardLayout] or DENSITY.FULL
    ApplyDensity()
    Layout()
    BuildRows()
    Commander.UI.ApplyHudChrome(root, db, "Hud", {
        defaultPoint = { point = "LEFT", x = 46, y = -60 },
        title = "Commander Threat",
    })
    UpdateVisibility()
    Paint()
end

-- ---------------------------------------------------------------------------
-- Test fight: a scripted 12s cast pushed through the REAL ingest path, so
-- every role can preview its whole alert chain (approach → warn → aggro
-- moving) from the settings panel or /cthreat test
-- ---------------------------------------------------------------------------

local TEST_LEN = 12

local function PutTestObs(n, guid, name, class, isPlayer, isPet, value, top, tanking, status)
    n = n + 1
    local o = obs[n]
    if not o then o = {}; obs[n] = o end
    o.guid, o.name, o.class = guid, name, class
    o.isPlayer, o.isPet = isPlayer, isPet
    o.value = value
    o.raw = top > 0 and (value / top * 100) or 0
    o.scaled = tanking and 100 or (o.raw / 1.1) -- the fake fight is all melee
    o.tanking = tanking
    o.status = status or (tanking and 3 or 0)
    return n
end

local function RunTestFight(now)
    local t = now - testStart
    local f = t / TEST_LEN
    if f > 1 then f = 1 end
    local roleNow = E.GetRole()
    local playerName = UnitName("player") or "You"
    local _, playerClass = UnitClass("player")
    E.SetMob("Creature-0-0-0-0-0-CTTEST", "Training Dummy")
    local n = 0
    if roleNow == "TANK" then
        -- You hold; Vexa climbs 45% → 120% and rips at 110: chase warning
        -- on the way up, AGGRO_LOST at the rip
        local you = 1400 + t * 380
        local ratio = 0.45 + f * 0.75
        local vexa = you * ratio
        local top = vexa > you and vexa or you
        local holding = ratio < 1.1
        n = PutTestObs(n, "test-you", playerName, playerClass, true, false, you, top, holding,
            holding and (ratio >= 0.95 and 2 or 3) or 0)
        n = PutTestObs(n, "test-vexa", "Vexa Nightwind", "ROGUE", false, false, vexa, top, not holding)
        n = PutTestObs(n, "test-moon", "Elder Moonbrook", "PRIEST", false, false, you * 0.22, top, false)
        n = PutTestObs(n, "test-grit", "Grit", nil, false, true, you * 0.34, top, false)
        E.SetPlateFacts(5, t > 6 and 3 or 4, 0, nil, nil, now)
    else
        -- Brakk holds; you climb 50% → 122% and take it at 110: pull
        -- warning on the way up, AGGRO_GAINED at the top
        local tank = 1600 + t * 300
        local ratio = 0.5 + f * 0.72
        local you = tank * ratio
        local top = you > tank and you or tank
        local taking = ratio >= 1.1
        n = PutTestObs(n, "test-brakk", "Brakk Shieldwall", "WARRIOR", false, false, tank, top, not taking)
        n = PutTestObs(n, "test-you", playerName, playerClass, true, false, you, top, taking)
        n = PutTestObs(n, "test-vexa", "Vexa Nightwind", "ROGUE", false, false, tank * 0.55, top, false)
        n = PutTestObs(n, "test-grit", "Grit", nil, false, true, tank * 0.3, top, false)
        if roleNow == "HEALER" then
            -- A second mob runs slightly hotter than the display one, and
            -- turns INBOUND at t=8
            local worst = (you / top * 100) / 1.1 + 6
            if worst > 100 then worst = 100 end
            E.SetPlateFacts(3, 2, worst, "Ravenous Stalker",
                t > 8 and "Ravenous Stalker" or nil, now)
        else
            E.SetPlateFacts(0, 0, 0, nil, nil, now)
        end
    end
    E.Ingest(obs, n, now)
end

function CommanderThreat_Test()
    if not db or not root then return end
    if not db.EnableThreat then
        print("Commander Threat: enable the module first (/cthreat)")
        return
    end
    E.Reset()
    view.offset = 0
    testStart = GetTime()
    testUntil = testStart + TEST_LEN
    local roleNow = E.GetRole()
    print("Commander Threat: test fight running — "
        .. roleNow:sub(1, 1) .. roleNow:sub(2):lower() .. " role, " .. TEST_LEN .. "s")
    if Tick then Tick() end
end

-- ---------------------------------------------------------------------------
-- The tick: sample → ingest → paint → alerts. Poll-only (see the header
-- comment); runs 4×/s from a ticker so a hidden board never starves it,
-- with a three-compare idle path when nothing is happening.
-- ---------------------------------------------------------------------------

Tick = function()
    if not db or not root then return end
    local now = GetTime()
    if not db.EnableThreat then
        if testStart > 0 then
            testStart, testUntil = 0, 0
            E.Reset()
        end
        UpdateVisibility()
        return
    end

    if testStart > 0 then
        if now >= testUntil then
            testStart, testUntil = 0, 0
            E.Reset()
            print("Commander Threat: test complete")
        else
            RunTestFight(now)
            -- Embedded: Meters' own repaint reads the provider — the
            -- hidden standalone board skips its paint, alerts still fire
            if BoardActive() then Paint() end
            -- Surfaces first, alerts second: an alert pulse needs the target
            -- readout to already know whether it is showing anything
            UpdateVisibility()
            DrainAlerts()
            return
        end
    end

    local _, hadRows = E.Rows()
    if not InCombatLockdown() and hadRows == 0
        and not Commander.UI.HudUnlocked(db, "Hud") then
        UpdateVisibility()
        return
    end

    local mobUnit = DisplayMob()
    if mobUnit then
        E.SetMob(UnitGUID(mobUnit), UnitName(mobUnit))
    else
        E.SetMob(nil, nil)
    end
    local roleNow = E.GetRole()
    if roleNow ~= "DAMAGE" then
        SweepPlates(roleNow, now)
    end
    local n = mobUnit and ScanMob(mobUnit) or 0
    E.Ingest(obs, n, now)
    if BoardActive() then Paint() end
    UpdateVisibility()
    DrainAlerts()
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")

local function OnEvent(_, event)
    if event == "PLAYER_LOGIN" then
        db = CommanderThreatDB
        -- The threat API is the whole data layer: without it, stand down
        -- loudly instead of erroring per tick
        if not UnitDetailedThreatSituation then
            print("|cff66ccffCommander Threat|r: |cffff4433this client has no threat API (UnitDetailedThreatSituation) — the module is standing down.|r")
            return
        end
        ResolveThemeOverrides()
        E.Init(db, CommanderThreat_GetRole())
        BuildBoard()
        BuildTargetReadout()
        RefreshRoster()
        events:RegisterEvent("PLAYER_TARGET_CHANGED")
        events:RegisterEvent("GROUP_ROSTER_UPDATE")
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        C_Timer.NewTicker(0.25, Tick)
        Commander.AddListener(COMMANDER_THREAT_EVENTS.UPDATE, Apply)
        Apply()
        return
    end
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        RefreshRoster()
        return
    end
    -- PLAYER_TARGET_CHANGED and the combat edges get an immediate sample:
    -- the ticker would cover them within 250 ms, but a mob switch or pull
    -- deserves a same-frame answer
    Tick()
end

events:SetScript("OnEvent", OnEvent)
