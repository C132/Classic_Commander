-- Commander Reticle — the cursor is the cast bar.
--
-- Mouseover casting parks the mouse pointer directly on the unit frame you are
-- casting at, which means the arrow covers the health bar at the exact moment
-- you most need to read it. This module answers that twice over: it draws a
-- hollow ring around the pointer's hotspot (the middle stays empty, so the ring
-- itself hides nothing), and it puts what the pointer is standing on -- the
-- cast, and the hovered unit -- onto the ring, so occlusion stops costing you
-- information at all.
--
-- Cheapness matters: this runs a follow loop every frame while visible. The
-- radial sweeps are Cooldown frames, which the client animates for free; per
-- frame we move one frame, and everything else is dirty-checked at 12Hz.

local TEXTURES = "Interface\\AddOns\\Commander_Reticle\\Textures\\"

-- Five ring weights, thinnest first. Thickness is baked into the art as a
-- proportion, so the addon picks the weight closest to the requested pixel
-- thickness at the current ring size.
local RING_FILES = {
    TEXTURES .. "Ring1.png", TEXTURES .. "Ring2.png", TEXTURES .. "Ring3.png",
    TEXTURES .. "Ring4.png", TEXTURES .. "Ring5.png",
}
local RING_RATIOS = { 0.88, 0.80, 0.71, 0.60, 0.46 }
-- The donut's outer radius as a fraction of the texture's width
local RING_OUTER = 0.485

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local DATA_INTERVAL = 1 / 12   -- dirty-checked reads (health, countdowns)
local WATCH_INTERVAL = 0.1     -- while asleep: is it time to wake up?
local FADE_SPEED = 14
local TEST_DURATION = 2.5

local COLORS = COMMANDER_RETICLE_COLORS

local function DB(key, default)
    local value = CommanderReticleDB and CommanderReticleDB[key]
    if value == nil then return default end
    return value
end

local function Color(name, fallback)
    local color = COLORS[name] or COLORS[fallback or "GOLD"]
    return color[1], color[2], color[3]
end

-- ---------------------------------------------------------------------------
-- Spell school. No TBC API exposes a casting spell's school, so it comes from
-- the name -- the same approach Commander_Casting ships, memoized here because
-- this sits on a cast-start path that can fire several times a second.
-- ---------------------------------------------------------------------------

local SCHOOLS = {
    { "FROST",  { "frost", "ice", "freeze", "blizzard", "cone of cold" } },
    { "NATURE", { "nature", "lightning", "wrath", "bolt", "starfire", "hurricane", "tranquility", "healing", "touch", "poison", "sting" } },
    { "HOLY",   { "holy", "light", "heal", "smite", "flash", "prayer", "resurrection", "exorcism", "consecration", "judgement" } },
    { "FIRE",   { "fire", "flame", "immolate", "scorch", "pyroblast", "blast wave", "flamestrike", "searing", "incinerate" } },
    { "SHADOW", { "shadow", "mind", "psychic", "flay", "corruption", "mana burn", "devouring plague", "curse", "drain", "fear" } },
    { "ARCANE", { "arcane", "mana", "magic", "polymorph", "missiles", "explosion", "conjure", "evocation", "counterspell", "portal", "teleport" } },
}

local SCHOOL_COLORS = {
    FROST = "ICE", NATURE = "VERDANT", HOLY = "GOLD",
    FIRE = "EMBER", SHADOW = "VOID", ARCANE = "ARCANE",
}

local schoolCache = {}

local function SchoolOf(name)
    if not name then return nil end
    local cached = schoolCache[name]
    if cached ~= nil then
        return cached ~= false and cached or nil
    end
    local lowered = name:lower()
    local found = false
    for i = 1, #SCHOOLS do
        local entry = SCHOOLS[i]
        local keywords = entry[2]
        for k = 1, #keywords do
            if lowered:find(keywords[k], 1, true) then
                found = entry[1]
                break
            end
        end
        if found then break end
    end
    schoolCache[name] = found
    return found ~= false and found or nil
end

-- ---------------------------------------------------------------------------
-- Who the cast is landing on. TBC exposes no "unit I am casting at", so the
-- unit is snapshotted by GUID when the cast starts and re-resolved from a
-- small token list afterwards -- the mouseover token itself moves the instant
-- the pointer does, which is exactly the case this module exists for.
-- ---------------------------------------------------------------------------

local CANDIDATES = {
    "mouseover", "target", "focus", "player",
    "party1", "party2", "party3", "party4",
}

local snapGUID, snapToken

local function SnapshotCastUnit()
    if UnitExists("mouseover") then
        snapToken = "mouseover"
    elseif UnitExists("target") then
        snapToken = "target"
    else
        snapToken = nil
    end
    snapGUID = snapToken and UnitGUID(snapToken) or nil
end

local function CastUnit()
    if not snapGUID then return nil end
    if snapToken and UnitExists(snapToken) and UnitGUID(snapToken) == snapGUID then
        return snapToken
    end
    for i = 1, #CANDIDATES do
        local unit = CANDIDATES[i]
        if UnitExists(unit) and UnitGUID(unit) == snapGUID then
            snapToken = unit
            return unit
        end
    end
    return nil
end

-- The unit the reticle is reporting on: whatever the pointer is over, else
-- whoever the current cast is aimed at, else the target.
local function ReticleUnit()
    if UnitExists("mouseover") then return "mouseover" end
    local unit = CastUnit()
    if unit then return unit end
    if UnitExists("target") then return "target" end
    return nil
end

-- Everything that reports on a unit -- the dial, the hostility color, the
-- center health readout -- goes through one source setting, so they can never
-- disagree about who they are describing.
local function DialUnit()
    local source = DB("DialSource", "SMART")
    if source == "MOUSEOVER" then
        return UnitExists("mouseover") and "mouseover" or nil
    elseif source == "TARGET" then
        return UnitExists("target") and "target" or nil
    elseif source == "CAST_TARGET" then
        return CastUnit()
    end
    return ReticleUnit()
end

-- ---------------------------------------------------------------------------
-- Frames
-- ---------------------------------------------------------------------------

local root = CreateFrame("Frame", "CommanderReticleFrame", UIParent)
root:SetFrameStrata("TOOLTIP")
root:SetSize(38, 38)
root:EnableMouse(false)          -- never eats a click, ever
root:SetAlpha(0)
root:Hide()

local castArc = CreateFrame("Cooldown", nil, root, "CooldownFrameTemplate")
castArc:SetAllPoints(root)
castArc:EnableMouse(false)
castArc:SetFrameLevel((root:GetFrameLevel() or 1) + 1)
if castArc.SetHideCountdownNumbers then castArc:SetHideCountdownNumbers(true) end
if castArc.SetDrawBling then castArc:SetDrawBling(false) end
if castArc.SetDrawSwipe then castArc:SetDrawSwipe(true) end
if castArc.SetSwipeTexture then castArc:SetSwipeTexture(RING_FILES[3]) end
castArc:Hide()

-- Center content lives above the sweep so a countdown is never half-eaten
local overlay = CreateFrame("Frame", nil, root)
overlay:SetAllPoints(root)
overlay:SetFrameLevel((root:GetFrameLevel() or 1) + 10)

local apertureIcon = overlay:CreateTexture(nil, "ARTWORK")
apertureIcon:SetPoint("CENTER")
apertureIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- trim the icon's own border
apertureIcon:Hide()

local apertureText = overlay:CreateFontString(nil, "OVERLAY")
apertureText:SetPoint("CENTER")
apertureText:SetFont(FONT, 11, "OUTLINE")
apertureText:Hide()

-- Outside the ring: the spell's name, and a row of combo points
local spellLabel = overlay:CreateFontString(nil, "OVERLAY")
spellLabel:SetFont(FONT, 10, "OUTLINE")
spellLabel:Hide()

local MAX_COMBO = 5
local comboPips = {}

-- The unit dial rides just outside the cast arc: a segmented gauge, so it can
-- never be mistaken for the continuous sweep it surrounds.
local PIP_FILE = TEXTURES .. "Pip.png"
local MAX_PIPS = 36

local dial = CreateFrame("Frame", nil, root)
dial:SetAllPoints(root)
dial:SetFrameLevel((root:GetFrameLevel() or 1) + 2)
dial:Hide()
local pips = {}

-- The global cooldown gets its own radius: "can I act yet" is a different
-- question from "how far along is this cast", so it never shares an arc.
local gcdArc = CreateFrame("Cooldown", nil, root, "CooldownFrameTemplate")
gcdArc:SetPoint("CENTER", root, "CENTER")
gcdArc:EnableMouse(false)
gcdArc:SetFrameLevel((root:GetFrameLevel() or 1) + 3)
if gcdArc.SetHideCountdownNumbers then gcdArc:SetHideCountdownNumbers(true) end
if gcdArc.SetDrawBling then gcdArc:SetDrawBling(false) end
if gcdArc.SetDrawEdge then gcdArc:SetDrawEdge(false) end
if gcdArc.SetSwipeTexture then gcdArc:SetSwipeTexture(RING_FILES[1]) end
gcdArc:Hide()

-- Markers sit on the arc itself: single ticks at a computed angle
local markers = CreateFrame("Frame", nil, root)
markers:SetAllPoints(root)
markers:SetFrameLevel((root:GetFrameLevel() or 1) + 4)

local latencyTick = markers:CreateTexture(nil, "OVERLAY")
latencyTick:SetTexture(TEXTURES .. "Pip.png")
latencyTick:Hide()

-- Feedback halo: one soft donut, tinted and grown per event
local glow = overlay:CreateTexture(nil, "OVERLAY")
glow:SetTexture(TEXTURES .. "RingGlow.png")
glow:SetBlendMode("ADD")
glow:SetPoint("CENTER", root, "CENTER")
glow:Hide()

-- The pointer itself, kept deliberately separate from the ring assembly: it
-- marks the true click point, so it never smooths, offsets, or dodges. With
-- Hide System Cursor on, this IS the mouse pointer -- three pixels of it.
local HOTSPOT_FILES = {
    DOT = TEXTURES .. "Dot.png",
    CROSS = TEXTURES .. "Cross.png",
    PLUS = TEXTURES .. "Plus.png",
}

local hot = CreateFrame("Frame", "CommanderReticleHotspot", UIParent)
hot:SetFrameStrata("TOOLTIP")
hot:SetSize(10, 10)
hot:EnableMouse(false)
hot:SetAlpha(0)
hot:Hide()

local hotTexture = hot:CreateTexture(nil, "OVERLAY")
hotTexture:SetAllPoints(hot)
hotTexture:SetTexture(HOTSPOT_FILES.DOT)

-- ---------------------------------------------------------------------------
-- Cast state
-- ---------------------------------------------------------------------------

local cast = {
    active = false,
    channel = false,
    test = false,
    name = nil,
    icon = nil,
    spellID = nil,
    start = 0,
    finish = 0,
}

local awake = false
local alpha, alphaTarget = 0, 0
local innerRatio = RING_RATIOS[3]
local sinceData = 0
local lastApertureText = ""

local gcdStart, gcdDuration = 0, 0

-- One halo, four meanings. Shake is only honored for the kinds that set it.
local FLASH_KINDS = {
    SUCCESS  = { color = "VERDANT", duration = 0.35, grow = 0.55 },
    FAIL     = { color = "BLOOD",   duration = 0.50, grow = 0.25, shake = true },
    PUSHBACK = { color = "EMBER",   duration = 0.30, grow = 0.15 },
    ERROR    = { color = "BLOOD",   duration = 0.40, grow = 0.20, shake = true },
}
local flashKind, flashStart = nil, 0

local hotAlpha, hotAlphaTarget = 0, 0
local smoothX, smoothY
local cursorHidden = false

-- Demo mode: a standing pretend cast and a pretend unit draining from full, so
-- every option on both pages can be judged from the settings panel instead of
-- requiring a real target and a real fight to look at.
local DEMO_DURATION = 20
local demoUntil, demoHealth, demoCombo = 0, 1, 0
local StartTestCast   -- forward declaration; the tester defines it below

local function DemoActive()
    return demoUntil > GetTime()
end

-- ---------------------------------------------------------------------------
-- Layout: only touches the frames when a geometry setting actually changed
-- ---------------------------------------------------------------------------

local laidSize, laidThickness, laidAperture, laidIconScale = -1, -1, nil, -1

local function RingTexture(size, thickness)
    local outer = size * RING_OUTER
    if outer <= 0 then return RING_FILES[3], RING_RATIOS[3] end
    local wanted = 1 - (thickness / outer)
    local best, bestDiff = 3, math.huge
    for i = 1, #RING_RATIOS do
        local diff = math.abs(RING_RATIOS[i] - wanted)
        if diff < bestDiff then best, bestDiff = i, diff end
    end
    return RING_FILES[best], RING_RATIOS[best]
end

local function Layout()
    local size = DB("RingSize", 38)
    local thickness = DB("RingThickness", 5)
    local aperture = DB("Aperture", "NONE")
    local iconScale = DB("ApertureIconSize", 0.85)
    if laidSize == size and laidThickness == thickness and laidAperture == aperture
        and laidIconScale == iconScale then
        return
    end
    laidSize, laidThickness, laidAperture = size, thickness, aperture
    laidIconScale = iconScale

    root:SetSize(size, size)

    local file, ratio = RingTexture(size, thickness)
    innerRatio = ratio
    if castArc.SetSwipeTexture then castArc:SetSwipeTexture(file) end

    -- Everything in the middle is sized off the hole, never off the ring, so
    -- a thicker arc never pushes content out over the rim
    -- Icon size is a share of the hole, so it tracks ring size on its own;
    -- past 100% it deliberately spills over the arc for people who want the
    -- icon to be the reticle
    local hole = size * RING_OUTER * 2 * ratio
    local icon = math.max(4, hole * iconScale)
    apertureIcon:SetSize(icon, icon)
    local fontSize = math.max(7, math.floor(hole * 0.5))
    apertureText:SetFont(FONT, fontSize, "OUTLINE")
end

-- Taking the system arrow away and drawing nothing in its place would leave
-- the player with no pointer at all, so the dot is forced on in that case.
local function HotspotStyle()
    local style = DB("HotspotStyle", "NONE")
    if style == "NONE" and DB("HideSystemCursor", false) then return "DOT" end
    return style
end

local laidHotStyle, laidHotSize, laidHotColor = nil, -1, nil

local function LayoutHotspot()
    local style = HotspotStyle()
    local size = DB("HotspotSize", 10)
    local color = DB("HotspotColor", "BONE")
    if laidHotStyle == style and laidHotSize == size and laidHotColor == color then
        return style
    end
    laidHotStyle, laidHotSize, laidHotColor = style, size, color
    if style == "NONE" then
        hotTexture:Hide()
        return style
    end
    hotTexture:SetTexture(HOTSPOT_FILES[style] or HOTSPOT_FILES.DOT)
    local r, g, b = Color(color, "BONE")
    hotTexture:SetVertexColor(r, g, b, 1)
    hot:SetSize(size, size)
    hotTexture:Show()
    return style
end

local laidLayer

local function ApplyLayer()
    local layer = DB("Layer", "TOOLTIP")
    if laidLayer == layer then return end
    laidLayer = layer
    root:SetFrameStrata(layer)
    hot:SetFrameStrata(layer)
    -- Changing strata re-sorts levels, so the stack is pinned again from the
    -- root's new level: arc, dial, cooldown, markers, center, and the click
    -- point above all of it.
    local base = root:GetFrameLevel() or 1
    castArc:SetFrameLevel(base + 1)
    dial:SetFrameLevel(base + 2)
    gcdArc:SetFrameLevel(base + 3)
    markers:SetFrameLevel(base + 4)
    overlay:SetFrameLevel(base + 10)
    hot:SetFrameLevel(base + 20)
end

local function ApplyGeometry()
    Layout()
    LayoutHotspot()
    ApplyLayer()
end

-- Taking the arrow away, and the one hard rule about it:
--
--   "If the cursor is hovering over WorldFrame, the SetCursor function will
--    have no effect - cursor is locked to reflect what the player is
--    currently pointing at."
--
-- That is the engine, not something an addon can out-argue, and it is why the
-- arrow always comes back the moment the pointer leaves the UI. It also does
-- not matter much: mouseover casting happens on unit FRAMES, which are UI, and
-- the swap works there. Pointing SetCursor at a path that does not resolve is
-- the documented way to hide the cursor outright, so it needs no art at all.
local MISSING_CURSOR = TEXTURES .. "NoSuchCursor"

local function HideSystemCursor()
    if not SetCursor then return end
    pcall(SetCursor, MISSING_CURSOR)
    cursorHidden = true
end

local function RestoreSystemCursor()
    if not cursorHidden then return end
    cursorHidden = false
    if ResetCursor then pcall(ResetCursor) end
end

-- ---------------------------------------------------------------------------
-- The cast arc
-- ---------------------------------------------------------------------------

local function ArcColor()
    local mode = DB("CastColorMode", "SCHOOL")
    if mode == "FIXED" then
        return Color(DB("CastColor", "GOLD"))
    elseif mode == "CLASS" then
        local info = Commander.GetClassInfo and Commander.GetClassInfo()
        if info and info.color then
            return info.color[1], info.color[2], info.color[3]
        end
        return Color("BONE")
    elseif mode == "HOSTILITY" then
        local unit = DialUnit()
        if unit then
            if UnitCanAttack("player", unit) then
                return Color("BLOOD")
            elseif UnitIsFriend("player", unit) then
                return Color("VERDANT")
            end
        end
        return Color("GOLD")
    end
    local school = SchoolOf(cast.name)
    return Color(school and SCHOOL_COLORS[school] or "GOLD")
end

local function ApplyArc()
    if not (cast.active and DB("ShowCastArc", true)) then
        if castArc.Clear then castArc:Clear() end
        castArc:Hide()
        return
    end
    local duration = cast.finish - cast.start
    if duration <= 0 then
        castArc:Hide()
        return
    end
    local fill
    if cast.channel then
        fill = DB("ChannelFill", false)
    else
        fill = DB("CastFill", true)
    end
    if castArc.SetReverse then castArc:SetReverse(fill and true or false) end
    local r, g, b = ArcColor()
    if castArc.SetSwipeColor then castArc:SetSwipeColor(r, g, b, 1) end
    if castArc.SetDrawEdge then castArc:SetDrawEdge(DB("CastEdge", true) and true or false) end
    castArc:SetCooldown(cast.start, duration)
    castArc:Show()
end

-- ---------------------------------------------------------------------------
-- Center content
-- ---------------------------------------------------------------------------

local function UpdateAperture()
    local mode = DB("Aperture", "NONE")
    if mode == "NONE" then
        apertureIcon:Hide()
        apertureText:Hide()
        return
    end

    local opacity = DB("ApertureOpacity", 0.85)
    if mode == "ICON" then
        apertureText:Hide()
        if cast.active and cast.icon then
            apertureIcon:SetTexture(cast.icon)
            apertureIcon:SetAlpha(opacity)
            apertureIcon:Show()
        else
            apertureIcon:Hide()
        end
        return
    end

    apertureIcon:Hide()
    local text
    if mode == "TIME" then
        if cast.active then
            local remaining = cast.finish - GetTime()
            if remaining < 0 then remaining = 0 end
            text = string.format("%.1f", remaining)
        end
    elseif mode == "HEALTH" then
        if DemoActive() then
            text = string.format("%d", demoHealth * 100 + 0.5)
        else
            local unit = DialUnit()
            if unit and UnitExists(unit) then
                local max = UnitHealthMax(unit) or 0
                if max > 0 then
                    text = string.format("%d", (UnitHealth(unit) or 0) / max * 100 + 0.5)
                end
            end
        end
    end

    if not text then
        apertureText:Hide()
        lastApertureText = ""
        return
    end
    -- Dirty-checked: SetText on every data tick is pure churn
    if text ~= lastApertureText then
        lastApertureText = text
        apertureText:SetText(text)
    end
    apertureText:SetAlpha(opacity)
    apertureText:Show()
end

-- ---------------------------------------------------------------------------
-- The unit dial. This is the half of the module that makes occlusion stop
-- mattering: whatever the pointer is covering, that unit's health is on the
-- pointer. Pips are pooled and only recolored when the reading changes.
-- ---------------------------------------------------------------------------

local function InRange(unit)
    -- While casting, the spell itself is the authority
    if cast.active and cast.name and IsSpellInRange then
        local ok, result = pcall(IsSpellInRange, cast.name, unit)
        if ok and result ~= nil then return result == 1 end
    end
    -- Otherwise the 40yd party check, which is the one that matters to a healer
    if UnitInRange then
        local ok, inRange, checked = pcall(UnitInRange, unit)
        if ok and checked then return inRange and true or false end
    end
    return true
end

-- unit may be nil in demo mode, where the player's own class stands in
local function DialColor(unit, frac)
    if DB("DialClassColor", false) then
        if not unit or (UnitIsPlayer and UnitIsPlayer(unit)) then
            local token
            if unit then
                local _, classToken = UnitClass(unit)
                token = classToken
            end
            local info = Commander.GetClassInfo and Commander.GetClassInfo(token)
            if info and info.color then
                return info.color[1], info.color[2], info.color[3]
            end
        end
        if unit and UnitCanAttack("player", unit) then return Color("BLOOD") end
        return Color("VERDANT")
    end
    -- Health gradient: verdant through amber to blood
    if frac > 0.5 then
        return (1 - frac) * 2, 1, 0.15
    end
    return 1, frac * 2, 0.15
end

local laidSegments, laidPipLength, laidPipWidth, laidGap, laidDialSize = -1, -1, -1, -1, -1
local laidDialStyle, laidDialPlace

local function LayoutDial()
    local style = DB("DialStyle", "SEGMENTED")
    local segments = style == "SOLID" and MAX_PIPS or DB("DialSegments", 20)
    if segments < 4 then segments = 4 elseif segments > MAX_PIPS then segments = MAX_PIPS end
    local length = DB("DialLength", 5)
    local width = DB("DialWidth", 3)
    local gap = DB("DialGap", 2)
    local size = DB("RingSize", 38)
    local place = DB("DialPlacement", "OUTSIDE")
    if laidSegments == segments and laidPipLength == length and laidPipWidth == width
        and laidGap == gap and laidDialSize == size and laidDialStyle == style
        and laidDialPlace == place then
        return segments
    end
    laidSegments, laidPipLength, laidPipWidth = segments, length, width
    laidGap, laidDialSize = gap, size
    laidDialStyle, laidDialPlace = style, place

    local radius
    if place == "INSIDE" then
        -- Tuck the dial into the hole instead of ringing the arc; keeps the
        -- whole reticle inside the cursor's own footprint
        radius = size * RING_OUTER * innerRatio - gap - length / 2
        if radius < length then radius = length end
    else
        radius = size * RING_OUTER + gap + length / 2
    end
    if style == "SOLID" then
        -- Widen each pip to its full share of the circumference, so the gauge
        -- reads as one continuous band rather than a row of ticks
        width = math.max(2, (2 * math.pi * radius) / segments + 1)
    end

    for i = 1, segments do
        local pip = pips[i]
        if not pip then
            pip = dial:CreateTexture(nil, "ARTWORK")
            pip:SetTexture(PIP_FILE)
            pips[i] = pip
        end
        -- Angles run clockwise from twelve o'clock, matching the sweep inside
        local theta = (i - 1) / segments * (math.pi * 2)
        pip:SetSize(width, length)
        pip:SetPoint("CENTER", dial, "CENTER", math.sin(theta) * radius, math.cos(theta) * radius)
        pip:SetRotation(-theta)
        pip:Show()
    end
    for i = segments + 1, #pips do
        pips[i]:Hide()
    end
    return segments
end

local lastLit, lastDialR, lastDialG, lastDialB, lastDialSegments = -1, -1, -1, -1, -1

local function UpdateDial()
    if not DB("ShowUnitDial", true) then
        if dial:IsShown() then dial:Hide() end
        return
    end
    local unit, frac, dead
    if DemoActive() then
        frac, dead = demoHealth, false
    else
        unit = DialUnit()
        if not unit or not UnitExists(unit) then
            if dial:IsShown() then dial:Hide() end
            return
        end
        local maxHealth = UnitHealthMax(unit) or 0
        frac = maxHealth > 0 and ((UnitHealth(unit) or 0) / maxHealth) or 0
        dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
    end
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end

    local segments = LayoutDial()
    local lit = dead and 0 or math.floor(frac * segments + 0.5)
    -- Never round a living unit down to nothing: an empty dial means dead
    if lit < 1 and not dead and frac > 0 then lit = 1 end

    local r, g, b = DialColor(unit, frac)
    if unit and DB("DialRangeDim", true) and not InRange(unit) then
        r, g, b = r * 0.4, g * 0.4, b * 0.4
    end

    if lit ~= lastLit or r ~= lastDialR or g ~= lastDialG or b ~= lastDialB
        or segments ~= lastDialSegments then
        lastLit, lastDialR, lastDialG, lastDialB = lit, r, g, b
        lastDialSegments = segments
        for i = 1, segments do
            if i <= lit then
                pips[i]:SetVertexColor(r, g, b, 1)
            else
                pips[i]:SetVertexColor(0.18, 0.18, 0.20, 0.75)
            end
        end
    end
    if not dial:IsShown() then dial:Show() end
end

-- ---------------------------------------------------------------------------
-- Global cooldown, latency, and feedback
-- ---------------------------------------------------------------------------

local laidGCD = { size = -1, ring = -1, thickness = -1, place = nil, reach = -1 }

local function OuterReach()
    local reach = DB("RingSize", 38) * RING_OUTER
    if DB("ShowUnitDial", true) and DB("DialPlacement", "OUTSIDE") ~= "INSIDE" then
        reach = reach + DB("DialGap", 2) + DB("DialLength", 5)
    end
    return reach
end

local function LayoutGCD()
    local size = DB("RingSize", 38)
    local ring = DB("RingThickness", 5)
    local thickness = DB("GCDThickness", 3)
    local place = DB("GCDPlacement", "INSIDE")
    local reach = OuterReach()
    if laidGCD.size == size and laidGCD.ring == ring and laidGCD.thickness == thickness
        and laidGCD.place == place and laidGCD.reach == reach then
        return
    end
    laidGCD.size, laidGCD.ring, laidGCD.thickness = size, ring, thickness
    laidGCD.place, laidGCD.reach = place, reach

    -- Both cases come down to "where should this ring's outer edge land"; the
    -- weight of art is then chosen for the requested pixel thickness.
    local frameSize
    if place == "OUTSIDE" then
        frameSize = (reach + 2 + thickness) / RING_OUTER
    else
        local holeRadius = size * RING_OUTER * innerRatio
        frameSize = math.max(6, (holeRadius - 1) / RING_OUTER)
    end
    gcdArc:SetSize(frameSize, frameSize)
    if gcdArc.SetSwipeTexture then
        gcdArc:SetSwipeTexture((RingTexture(frameSize, thickness)))
    end
end

local function GCDActive()
    return gcdDuration > 0 and (GetTime() - gcdStart) < gcdDuration
end

local function ApplyGCD()
    if not (DB("ShowGCD", false) and GCDActive()) then
        if gcdArc.Clear then gcdArc:Clear() end
        gcdArc:Hide()
        return
    end
    LayoutGCD()
    -- It is a cooldown; it should unwind like one
    if gcdArc.SetReverse then gcdArc:SetReverse(false) end
    local r, g, b = Color(DB("GCDColor", "STEEL"))
    if gcdArc.SetSwipeColor then gcdArc:SetSwipeColor(r, g, b, 1) end
    gcdArc:SetCooldown(gcdStart, gcdDuration)
    gcdArc:Show()
end

-- UNIT_SPELLCAST_SUCCEEDED carries the spell that just went off, and its
-- cooldown is the global cooldown whenever it is short enough to be one.
local function ReadGCD(spellID)
    if not (spellID and GetSpellCooldown) then return end
    local ok, start, duration = pcall(GetSpellCooldown, spellID)
    if not ok or not start or not duration then return end
    if duration > 0 and duration <= 1.5 then
        gcdStart, gcdDuration = start, duration
        ApplyGCD()
        return true
    end
    return false
end

-- The point in the cast where the next one can already be queued
local function UpdateLatency()
    if not (DB("ShowLatency", false) and cast.active and not cast.channel) then
        latencyTick:Hide()
        return
    end
    local duration = cast.finish - cast.start
    local latency = 0
    if GetNetStats then
        local _, _, _, world = GetNetStats()
        latency = (world or 0) / 1000
    end
    if duration <= 0 or latency <= 0 or latency >= duration then
        latencyTick:Hide()
        return
    end
    local theta = (1 - latency / duration) * math.pi * 2
    local thickness = DB("RingThickness", 5)
    local radius = DB("RingSize", 38) * RING_OUTER - thickness / 2
    local r, g, b = Color("BONE")
    latencyTick:SetSize(2, thickness + 4)
    latencyTick:SetPoint("CENTER", markers, "CENTER",
        math.sin(theta) * radius, math.cos(theta) * radius)
    latencyTick:SetRotation(-theta)
    latencyTick:SetVertexColor(r, g, b, 1)
    latencyTick:Show()
end

-- The spell's name and your combo points both hang below the ring, so the
-- label reserves room for the pips whenever they are switched on.
local laidLabelSize, laidLabelPlace, laidLabelPips = -1, nil, nil

local function LayoutSpellLabel()
    local size = DB("RingSize", 38)
    local place = DB("SpellNamePlace", "BELOW")
    local pips = DB("ShowComboPips", false) and true or false
    if laidLabelSize == size and laidLabelPlace == place and laidLabelPips == pips then
        return
    end
    laidLabelSize, laidLabelPlace, laidLabelPips = size, place, pips
    spellLabel:SetFont(FONT, math.max(8, math.floor(size * 0.26)), "OUTLINE")
    spellLabel:ClearAllPoints()
    if place == "ABOVE" then
        spellLabel:SetPoint("BOTTOM", root, "TOP", 0, 3)
    else
        local drop = pips and (math.max(3, size * 0.14) + 5) or 3
        spellLabel:SetPoint("TOP", root, "BOTTOM", 0, -drop)
    end
end

local lastSpellLabel = ""

local function UpdateSpellLabel()
    if not (DB("ShowSpellName", false) and cast.active and cast.name) then
        spellLabel:Hide()
        lastSpellLabel = ""
        return
    end
    LayoutSpellLabel()
    local text = cast.name
    local limit = DB("SpellNameMax", 14)
    if limit > 0 and #text > limit then
        text = text:sub(1, limit)
    end
    if text ~= lastSpellLabel then
        lastSpellLabel = text
        spellLabel:SetText(text)
    end
    local r, g, b = ArcColor()
    spellLabel:SetTextColor(r, g, b, 1)
    spellLabel:Show()
end

local laidComboSize = -1
local lastCombo = -1

local function UpdateCombo()
    if not DB("ShowComboPips", false) then
        if lastCombo ~= 0 then
            lastCombo = 0
            for i = 1, #comboPips do comboPips[i]:Hide() end
        end
        return
    end

    local points = 0
    if DemoActive() then
        points = demoCombo
    elseif GetComboPoints then
        local ok, value = pcall(GetComboPoints, "player", "target")
        if ok then points = value or 0 end
    end

    local size = DB("RingSize", 38)
    local dot = math.max(3, math.floor(size * 0.14))
    if laidComboSize ~= size then
        laidComboSize = size
        local spacing = dot + 2
        for i = 1, MAX_COMBO do
            local pip = comboPips[i]
            if not pip then
                pip = overlay:CreateTexture(nil, "OVERLAY")
                pip:SetTexture(HOTSPOT_FILES.DOT)
                comboPips[i] = pip
            end
            pip:SetSize(dot, dot)
            pip:ClearAllPoints()
            pip:SetPoint("TOP", root, "BOTTOM",
                (i - (MAX_COMBO + 1) / 2) * spacing, -3)
        end
        lastCombo = -1
    end

    if points == lastCombo then return end
    lastCombo = points
    for i = 1, MAX_COMBO do
        local pip = comboPips[i]
        if i <= points then
            -- Cool at one point, hot at five
            pip:SetVertexColor(1, 1 - (i - 1) / MAX_COMBO * 0.9, 0.2, 1)
            pip:Show()
        else
            pip:Hide()
        end
    end
end

local function RenderFlash()
    if not flashKind then return end
    local spec = FLASH_KINDS[flashKind]
    local progress = (GetTime() - flashStart) / spec.duration
    if progress >= 1 then
        flashKind = nil
        glow:Hide()
        return
    end
    local size = DB("RingSize", 38) * (1.3 + spec.grow * progress)
    glow:SetSize(size, size)
    glow:SetAlpha((1 - progress) * 0.85)
end

-- ---------------------------------------------------------------------------
-- What the pointer is over. GetMouseFoci allocates a table per call, so the
-- answer is taken once per data tick and shared by everything that needs it:
-- the dodge, and the decision about whether the arrow may be hidden here.
-- ---------------------------------------------------------------------------

local MouseFocusFrame   -- defined with the follow loop, below
local cachedFocus

local function RefreshMouseFocus()
    cachedFocus = MouseFocusFrame and MouseFocusFrame() or nil
end

-- Where the arrow is allowed to be taken away: anywhere over the interface.
-- Over the world the engine overrules us whatever we do (cachedFocus is nil
-- there, since WorldFrame/UIParent are filtered out), so there is nothing to
-- decide -- if the pointer is on a real UI frame, the swap can land.
local function CursorScopeAllows()
    return cachedFocus ~= nil
end

-- ---------------------------------------------------------------------------
-- Visibility
-- ---------------------------------------------------------------------------

local function ShouldShowRing()
    if not DB("EnableReticle", true) then return false end
    if DB("HideMouselooking", true) and IsMouselooking and IsMouselooking() then
        return false
    end
    -- A flash is a deliberate signal: never fade out mid-message
    if flashKind then return true end
    if DemoActive() then return true end
    if DB("CombatOnly", false) and not UnitAffectingCombat("player") then
        return false
    end
    local when = DB("ShowWhen", "CASTING_OR_UNIT")
    if when == "ALWAYS" then return true end
    -- With the global cooldown ring on, "busy" includes waiting on the GCD --
    -- that ring is useless if it is hidden for the whole of the wait
    local busy = cast.active or (DB("ShowGCD", false) and GCDActive())
    if when == "CASTING" then return busy end
    local hovering = UnitExists("mouseover") and true or false
    if when == "UNIT" then return hovering end
    return busy or hovering
end

-- The hotspot outlives the ring: once the system arrow is gone, the dot has to
-- be on screen whenever the pointer is, whatever the ring is doing.
local function ShouldShowHotspot(ringVisible)
    if not DB("EnableReticle", true) then return false end
    if HotspotStyle() == "NONE" then return false end
    if DB("HideMouselooking", true) and IsMouselooking and IsMouselooking() then
        return false
    end
    -- With the arrow gone, the hotspot is the only pointer there is -- but
    -- only where it is actually gone, or you get two pointers at once
    if DB("HideSystemCursor", false) and CursorScopeAllows() then return true end
    return ringVisible
end

-- ---------------------------------------------------------------------------
-- The follow loop
-- ---------------------------------------------------------------------------

local driver = CreateFrame("Frame")
local DODGE_SPEED = 12
local dodgeX, dodgeY = 0, 0

-- The frame under the pointer, or nil. GetMouseFoci is this framework's
-- version and returns a list; GetMouseFocus is the older single-frame call.
-- Both are guarded: neither is worth an error inside a per-frame loop.
MouseFocusFrame = function()
    local focus
    if GetMouseFoci then
        local ok, result = pcall(GetMouseFoci)
        if not ok then return nil end
        -- GetMouseFoci returns a LIST: the first entry, or nil for an empty
        -- list (pointer over nothing). Take result[1] rather than `result or`,
        -- which would hand back the empty list itself as a bogus focus.
        if type(result) == "table" then
            focus = result[1]
        else
            focus = result
        end
    elseif GetMouseFocus then
        local ok, result = pcall(GetMouseFocus)
        if not ok then return nil end
        focus = result
    end
    if not focus or focus == WorldFrame or focus == UIParent then return nil end
    return focus
end


-- How far to step the ring off whatever it is sitting on. The hotspot itself
-- never moves -- only the ring gets out of the way, so aim is untouched.
local function DodgeOffset(cx, cy, radius)
    local mode = DB("DodgeMode", "OFF")
    if mode == "OFF" or not UnitExists("mouseover") then return 0, 0 end

    local distance = DB("DodgeDistance", 26)
    if mode == "UP" then return 0, distance end
    if mode == "DOWN" then return 0, -distance end
    if mode == "LEFT" then return -distance, 0 end
    if mode == "RIGHT" then return distance, 0 end

    -- AUTO: leave by the nearest edge of the frame under the pointer
    local focus = cachedFocus
    if not focus or not focus.GetRect then return 0, distance end
    local ok, left, bottom, width, height = pcall(focus.GetRect, focus)
    if not ok or not left or not width or width <= 0 or not height then
        return 0, distance
    end
    local relative = 1
    if focus.GetEffectiveScale then
        local focusScale = focus:GetEffectiveScale()
        local uiScale = UIParent:GetEffectiveScale()
        if focusScale and uiScale and uiScale > 0 then relative = focusScale / uiScale end
    end
    left, bottom = left * relative, bottom * relative
    width, height = width * relative, height * relative

    local up = (bottom + height) - cy + radius
    local down = cy - bottom + radius
    local right = (left + width) - cx + radius
    local leftward = cx - left + radius
    if up < 0 then up = 0 end
    if down < 0 then down = 0 end
    if right < 0 then right = 0 end
    if leftward < 0 then leftward = 0 end

    local best, bestValue = "UP", up
    if down < bestValue then best, bestValue = "DOWN", down end
    if right < bestValue then best, bestValue = "RIGHT", right end
    if leftward < bestValue then best, bestValue = "LEFT", leftward end
    -- Nudge, never teleport: a huge frame under the pointer just gets a nudge
    if bestValue > distance then bestValue = distance end

    if best == "UP" then return 0, bestValue end
    if best == "DOWN" then return 0, -bestValue end
    if best == "RIGHT" then return bestValue, 0 end
    return -bestValue, 0
end

-- Where the ring is trying to stand, refreshed on the data tick rather than
-- every frame: GetMouseFoci hands back a fresh table per call, and the ring
-- eases toward the answer anyway, so asking twelve times a second is both
-- cheaper and indistinguishable.
local dodgeTargetX, dodgeTargetY = 0, 0
local lastCursorX, lastCursorY = 0, 0
local dodgeStale = true

local function UpdateDodgeTarget()
    dodgeTargetX, dodgeTargetY = DodgeOffset(lastCursorX, lastCursorY, OuterReach())
end

local function Follow(elapsed)
    local uiScale = UIParent:GetEffectiveScale()
    if not uiScale or uiScale <= 0 then uiScale = 1 end
    local cx, cy = GetCursorPosition()
    if not cx then return end
    cx, cy = cx / uiScale, cy / uiScale
    lastCursorX, lastCursorY = cx, cy
    if dodgeStale then
        dodgeStale = false
        RefreshMouseFocus()
        UpdateDodgeTarget()
    end

    -- Ease into the dodge so the ring steps aside instead of snapping
    local step = (elapsed or 1) * DODGE_SPEED
    if step >= 1 then step = 1 end
    dodgeX = dodgeX + (dodgeTargetX - dodgeX) * step
    dodgeY = dodgeY + (dodgeTargetY - dodgeY) * step

    -- A failed cast can shove the ring around a little. Driven off GetTime so
    -- it is deterministic and needs no random source.
    local shakeX, shakeY = 0, 0
    if flashKind and DB("FailShake", false) then
        local spec = FLASH_KINDS[flashKind]
        local progress = (GetTime() - flashStart) / spec.duration
        if spec.shake and progress < 1 then
            local amplitude = (1 - progress) * 4
            shakeX = math.sin(GetTime() * 70) * amplitude
            shakeY = math.cos(GetTime() * 91) * amplitude
        end
    end

    -- The click point, exactly: no offset, no dodge, no smoothing
    hot:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)

    local wantsX = cx + dodgeX + shakeX + DB("OffsetX", 0)
    local wantsY = cy + dodgeY + shakeY + DB("OffsetY", 0)
    local smoothing = DB("Smoothing", 0)
    if smoothing > 0 and smoothX and elapsed and elapsed < 1 then
        -- Higher smoothing = slower chase. Exponential so it is frame-rate
        -- independent rather than tied to however fast the client is drawing.
        local speed = 30 * (1 - smoothing) + 1.5
        local step = elapsed * speed
        if step >= 1 then step = 1 end
        smoothX = smoothX + (wantsX - smoothX) * step
        smoothY = smoothY + (wantsY - smoothY) * step
    else
        smoothX, smoothY = wantsX, wantsY
    end

    root:SetPoint("CENTER", UIParent, "BOTTOMLEFT", smoothX, smoothY)
end

local function Tick()
    RefreshMouseFocus()
    UpdateDodgeTarget()

    -- Demo mode drives a pretend unit down from full and cycles combo points,
    -- so every option can be judged without a target or a fight
    if DemoActive() then
        local remaining = demoUntil - GetTime()
        demoHealth = 0.08 + 0.92 * (remaining / DEMO_DURATION)
        demoCombo = math.floor((DEMO_DURATION - remaining) / 2.5) % (MAX_COMBO + 1)
    end

    if cast.test and cast.active and GetTime() >= cast.finish then
        cast.active, cast.test = false, false
        ApplyArc()
    end
    -- Keep the pretend cast looping for the length of the demo
    if DemoActive() and not cast.active and StartTestCast then
        StartTestCast()
    end

    if gcdDuration > 0 and not GCDActive() then
        gcdDuration = 0
        ApplyGCD()
    end
    UpdateDial()
    UpdateLatency()
    UpdateAperture()
    UpdateSpellLabel()
    UpdateCombo()
end

local function Sleep()
    awake = false
    driver:SetScript("OnUpdate", nil)
    alpha, alphaTarget = 0, 0
    hotAlpha, hotAlphaTarget = 0, 0
    root:SetAlpha(0)
    root:Hide()
    hot:SetAlpha(0)
    hot:Hide()
    RestoreSystemCursor()
end

local function Fade(current, target, elapsed)
    local step = elapsed * DB("FadeSpeed", FADE_SPEED)
    if step >= 1 then return target end
    current = current + (target - current) * step
    if math.abs(current - target) < 0.01 then return target end
    return current
end

local function DriverUpdate(_, elapsed)
    Follow(elapsed)
    RenderFlash()

    sinceData = sinceData + elapsed
    if sinceData >= DATA_INTERVAL then
        sinceData = 0
        Tick()
    end

    local opacity = DB("Opacity", 0.95)
    local ringWants = ShouldShowRing()
    local hotWants = ShouldShowHotspot(ringWants)
    alphaTarget = ringWants and opacity or 0
    hotAlphaTarget = hotWants and opacity or 0

    if alpha ~= alphaTarget then
        alpha = Fade(alpha, alphaTarget, elapsed)
        root:SetAlpha(alpha)
    end
    if hotAlpha ~= hotAlphaTarget then
        hotAlpha = Fade(hotAlpha, hotAlphaTarget, elapsed)
        hot:SetAlpha(hotAlpha)
        hot:SetShown(hotAlpha > 0)
    end

    -- The client re-asserts the cursor on every focus change, so the swap is
    -- re-applied every frame while it is meant to be gone. Never while
    -- something is being dragged: that cursor is carrying an item or a spell,
    -- and blanking it would hide what you are holding.
    if hotWants and DB("HideSystemCursor", false) and CursorScopeAllows()
        and not (GetCursorInfo and GetCursorInfo()) then
        HideSystemCursor()
    elseif cursorHidden then
        RestoreSystemCursor()
    end

    if alpha <= 0 and hotAlpha <= 0 then Sleep() end
end

local function Wake()
    if awake then return end
    awake = true
    ApplyGeometry()
    sinceData = DATA_INTERVAL      -- first frame reads live data, not stale
    smoothX, smoothY = nil, nil    -- snap, never sweep in from the last spot
    dodgeStale = true              -- and stand where this pointer wants it now
    root:Show()
    root:SetAlpha(alpha)
    if HotspotStyle() ~= "NONE" then
        hot:Show()
        hot:SetAlpha(hotAlpha)
    end
    driver:SetScript("OnUpdate", DriverUpdate)
    Follow(1)
end

local function Flash(kind)
    local spec = FLASH_KINDS[kind]
    if not spec then return end
    flashKind, flashStart = kind, GetTime()
    local r, g, b = Color(spec.color)
    glow:SetVertexColor(r, g, b, 1)
    glow:SetAlpha(0.85)
    glow:Show()
    Wake()
end

-- ---------------------------------------------------------------------------
-- Cast tracking
-- ---------------------------------------------------------------------------

local function ReadCast()
    local name, _, icon, startMS, endMS, _, _, _, spellID = UnitCastingInfo("player")
    local channel = false
    if not name then
        local cname, _, cicon, cstart, cend, _, _, cspell = UnitChannelInfo("player")
        if cname then
            name, icon, startMS, endMS, spellID = cname, cicon, cstart, cend, cspell
            channel = true
        end
    end

    if not name or not startMS or not endMS then
        if cast.active and not cast.test then
            cast.active, cast.channel = false, false
            cast.name, cast.icon, cast.spellID = nil, nil, nil
            ApplyArc()
        end
        return
    end

    cast.active, cast.test, cast.channel = true, false, channel
    cast.name, cast.icon, cast.spellID = name, icon, spellID
    cast.start, cast.finish = startMS / 1000, endMS / 1000
    ApplyArc()
end

-- ---------------------------------------------------------------------------
-- Tester
-- ---------------------------------------------------------------------------

local TEST_SPELLS = {
    { "Greater Heal", "Interface\\Icons\\Spell_Holy_GreaterHeal" },
    { "Frostbolt", "Interface\\Icons\\Spell_Frost_FrostBolt02" },
    { "Immolate", "Interface\\Icons\\Spell_Fire_Immolation" },
    { "Shadow Bolt", "Interface\\Icons\\Spell_Shadow_ShadowBolt" },
    { "Lightning Bolt", "Interface\\Icons\\Spell_Nature_Lightning" },
    { "Arcane Missiles", "Interface\\Icons\\Spell_Nature_StarFall" },
}
local testIndex = 0

-- Assigns the forward-declared local so the demo loop can restart it
StartTestCast = function()
    testIndex = testIndex % #TEST_SPELLS + 1
    local spell = TEST_SPELLS[testIndex]
    cast.active, cast.test, cast.channel = true, true, false
    cast.name, cast.icon, cast.spellID = spell[1], spell[2], nil
    cast.start = GetTime()
    cast.finish = cast.start + TEST_DURATION
    ApplyArc()
    return spell
end

function CommanderReticle_Test()
    if not DB("EnableReticle", true) then
        print("Commander Reticle: the reticle is disabled (enable it in settings or /creticle)")
        return
    end
    local spell = StartTestCast()
    Wake()
    print(string.format("Commander Reticle: test cast — %s, %.1f seconds. Move the pointer over a unit frame to see it in place.",
        spell[1], TEST_DURATION))
end

-- Everything at once, for as long as it takes to make up your mind: a looping
-- pretend cast, a pretend unit bleeding from full to nearly dead, and combo
-- points cycling. Lets every option be judged from the settings page itself.
function CommanderReticle_Demo()
    if not DB("EnableReticle", true) then
        print("Commander Reticle: the reticle is disabled (enable it in settings or /creticle)")
        return
    end
    demoUntil = GetTime() + DEMO_DURATION
    demoHealth, demoCombo = 1, 0
    StartTestCast()
    Wake()
    print(string.format("|cff66ccffCommander Reticle|r: demo running for %d seconds — pretend cast, pretend target draining from full. Change any setting and watch it take effect live.",
        DEMO_DURATION))
end

function CommanderReticle_DemoStop()
    demoUntil = 0
    if cast.test then
        cast.active, cast.test = false, false
        ApplyArc()
    end
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------

local watchTicker

local function Watch()
    if not DB("EnableReticle", true) then return end
    if awake then return end
    -- Hiding the arrow over the interface means waking wherever the pointer is
    -- over a UI frame -- which only the mouse-focus tells us, and the driver
    -- that normally refreshes it is asleep. So sample it here while idle, but
    -- only when the feature that needs it is on.
    if DB("HideSystemCursor", false) then RefreshMouseFocus() end
    local ringWants = ShouldShowRing()
    if ringWants or ShouldShowHotspot(ringWants) then Wake() end
end

-- Cast-relevant UI errors, resolved from the client's own localized strings so
-- the match is locale-safe. Anything not in here is somebody else's problem.
local CAST_ERRORS = {}

local function BuildErrorSet()
    local keys = {
        "SPELL_FAILED_OUT_OF_RANGE", "SPELL_FAILED_LINE_OF_SIGHT",
        "SPELL_FAILED_UNIT_NOT_INFRONT", "SPELL_FAILED_BAD_TARGETS",
        "SPELL_FAILED_TARGETS_DEAD", "SPELL_FAILED_NOT_BEHIND",
        "SPELL_FAILED_NO_POWER", "ERR_OUT_OF_MANA", "ERR_OUT_OF_RAGE",
        "ERR_OUT_OF_ENERGY", "SPELL_FAILED_CASTER_AURASTATE",
    }
    for i = 1, #keys do
        local text = _G[keys[i]]
        if type(text) == "string" then CAST_ERRORS[text] = true end
    end
end

local function Apply()
    if DB("EnableReticle", true) then
        ApplyGeometry()
        ApplyArc()
        ApplyGCD()
        -- Turning the swap off in settings has to hand the arrow straight back
        if not DB("HideSystemCursor", false) then
            RestoreSystemCursor()
        end
        if not watchTicker then
            watchTicker = C_Timer.NewTicker(WATCH_INTERVAL, Watch)
        end
        local ringWants = ShouldShowRing()
        if ringWants or ShouldShowHotspot(ringWants) then
            Wake()
        end
    else
        if watchTicker then
            watchTicker:Cancel()
            watchTicker = nil
        end
        Sleep()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("UNIT_SPELLCAST_START")
events:RegisterEvent("UNIT_SPELLCAST_STOP")
events:RegisterEvent("UNIT_SPELLCAST_FAILED")
events:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
events:RegisterEvent("UNIT_SPELLCAST_DELAYED")
events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
events:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
events:RegisterEvent("UI_ERROR_MESSAGE")

events:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "PLAYER_LOGIN" then
        BuildErrorSet()
        Commander.AddListener(COMMANDER_RETICLE_EVENTS.UPDATE, Apply)
        Apply()
        -- Logging in or reloading mid-cast still gets an arc
        ReadCast()
        return
    end
    if not DB("EnableReticle", true) then return end

    if event == "UPDATE_MOUSEOVER_UNIT" then
        if not awake and ShouldShowRing() then Wake() end
        return
    end
    if event == "UI_ERROR_MESSAGE" then
        if DB("ErrorFlash", false) and CAST_ERRORS[arg2] then Flash("ERROR") end
        return
    end
    if arg1 ~= "player" then return end

    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        SnapshotCastUnit()
        ReadCast()
        if not awake then Wake() end
        return
    end

    -- Feedback reads the state the cast was in BEFORE this event resolves it.
    -- Channels announce themselves as succeeded the moment they start, so they
    -- are excluded; instants never had an arc to celebrate.
    local wasCasting = cast.active and not cast.test and not cast.channel
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        ReadGCD(arg3)
        if wasCasting and DB("SuccessPop", true) then Flash("SUCCESS") end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
        if wasCasting and DB("FailFlash", true) then Flash("FAIL") end
    elseif event == "UNIT_SPELLCAST_DELAYED" then
        if wasCasting and DB("PushbackFlash", true) then Flash("PUSHBACK") end
    end
    ReadCast()
end)
