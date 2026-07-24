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

-- The unit dial rides just outside the cast arc: a segmented gauge, so it can
-- never be mistaken for the continuous sweep it surrounds.
local PIP_FILE = TEXTURES .. "Pip.png"
local MAX_PIPS = 36

local dial = CreateFrame("Frame", nil, root)
dial:SetAllPoints(root)
dial:SetFrameLevel((root:GetFrameLevel() or 1) + 2)
dial:Hide()
local pips = {}

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

-- ---------------------------------------------------------------------------
-- Layout: only touches the frames when a geometry setting actually changed
-- ---------------------------------------------------------------------------

local laidSize, laidThickness, laidAperture = -1, -1, nil

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
    if laidSize == size and laidThickness == thickness and laidAperture == aperture then
        return
    end
    laidSize, laidThickness, laidAperture = size, thickness, aperture

    root:SetSize(size, size)

    local file, ratio = RingTexture(size, thickness)
    innerRatio = ratio
    if castArc.SetSwipeTexture then castArc:SetSwipeTexture(file) end

    -- Everything in the middle is sized off the hole, never off the ring, so
    -- a thicker arc never pushes content out over the rim
    local hole = size * RING_OUTER * 2 * ratio
    apertureIcon:SetSize(hole * 0.84, hole * 0.84)
    local fontSize = math.max(7, math.floor(hole * 0.5))
    apertureText:SetFont(FONT, fontSize, "OUTLINE")
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
    castArc:SetReverse(fill and true or false)
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
        local unit = DialUnit()
        if unit and UnitExists(unit) then
            local max = UnitHealthMax(unit) or 0
            if max > 0 then
                text = string.format("%d", (UnitHealth(unit) or 0) / max * 100 + 0.5)
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

local function DialColor(unit, frac)
    if DB("DialClassColor", false) then
        if UnitIsPlayer and UnitIsPlayer(unit) then
            local _, token = UnitClass(unit)
            local info = token and Commander.GetClassInfo and Commander.GetClassInfo(token)
            if info and info.color then
                return info.color[1], info.color[2], info.color[3]
            end
        end
        if UnitCanAttack("player", unit) then return Color("BLOOD") end
        return Color("VERDANT")
    end
    -- Health gradient: verdant through amber to blood
    if frac > 0.5 then
        return (1 - frac) * 2, 1, 0.15
    end
    return 1, frac * 2, 0.15
end

local laidSegments, laidPipLength, laidPipWidth, laidGap, laidDialSize = -1, -1, -1, -1, -1

local function LayoutDial()
    local segments = DB("DialSegments", 20)
    if segments < 4 then segments = 4 elseif segments > MAX_PIPS then segments = MAX_PIPS end
    local length = DB("DialLength", 5)
    local width = DB("DialWidth", 3)
    local gap = DB("DialGap", 2)
    local size = DB("RingSize", 38)
    if laidSegments == segments and laidPipLength == length and laidPipWidth == width
        and laidGap == gap and laidDialSize == size then
        return segments
    end
    laidSegments, laidPipLength, laidPipWidth = segments, length, width
    laidGap, laidDialSize = gap, size

    local radius = size * RING_OUTER + gap + length / 2
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
    local unit = DialUnit()
    if not unit or not UnitExists(unit) then
        if dial:IsShown() then dial:Hide() end
        return
    end

    local segments = LayoutDial()
    local maxHealth = UnitHealthMax(unit) or 0
    local frac = 0
    if maxHealth > 0 then frac = (UnitHealth(unit) or 0) / maxHealth end
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end

    local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
    local lit = dead and 0 or math.floor(frac * segments + 0.5)
    -- Never round a living unit down to nothing: an empty dial means dead
    if lit < 1 and not dead and frac > 0 then lit = 1 end

    local r, g, b = DialColor(unit, frac)
    if DB("DialRangeDim", true) and not InRange(unit) then
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
-- Visibility
-- ---------------------------------------------------------------------------

local function ShouldShow()
    if not DB("EnableReticle", true) then return false end
    if DB("HideMouselooking", true) and IsMouselooking and IsMouselooking() then
        return false
    end
    if DB("CombatOnly", false) and not UnitAffectingCombat("player") then
        return false
    end
    local when = DB("ShowWhen", "CASTING_OR_UNIT")
    if when == "ALWAYS" then return true end
    if when == "CASTING" then return cast.active end
    local hovering = UnitExists("mouseover") and true or false
    if when == "UNIT" then return hovering end
    return cast.active or hovering
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
local function MouseFocusFrame()
    local focus
    if GetMouseFoci then
        local ok, result = pcall(GetMouseFoci)
        if not ok then return nil end
        focus = type(result) == "table" and result[1] or result
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
    local focus = MouseFocusFrame()
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

local function Follow(elapsed)
    local uiScale = UIParent:GetEffectiveScale()
    if not uiScale or uiScale <= 0 then uiScale = 1 end
    local cx, cy = GetCursorPosition()
    if not cx then return end
    cx, cy = cx / uiScale, cy / uiScale

    local reach = DB("RingSize", 38) * RING_OUTER
    if DB("ShowUnitDial", true) then
        reach = reach + DB("DialGap", 2) + DB("DialLength", 5)
    end
    local wantX, wantY = DodgeOffset(cx, cy, reach)
    -- Ease into the dodge so the ring steps aside instead of snapping
    local step = (elapsed or 1) * DODGE_SPEED
    if step >= 1 then step = 1 end
    dodgeX = dodgeX + (wantX - dodgeX) * step
    dodgeY = dodgeY + (wantY - dodgeY) * step

    root:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx + dodgeX, cy + dodgeY)
end

local function Tick()
    if cast.test and cast.active and GetTime() >= cast.finish then
        cast.active, cast.test = false, false
        ApplyArc()
    end
    UpdateDial()
    UpdateAperture()
end

local function Sleep()
    awake = false
    driver:SetScript("OnUpdate", nil)
    alpha, alphaTarget = 0, 0
    root:SetAlpha(0)
    root:Hide()
end

local function DriverUpdate(_, elapsed)
    Follow(elapsed)

    sinceData = sinceData + elapsed
    if sinceData >= DATA_INTERVAL then
        sinceData = 0
        Tick()
    end

    alphaTarget = ShouldShow() and DB("Opacity", 0.95) or 0
    if alpha ~= alphaTarget then
        local step = elapsed * FADE_SPEED
        if step >= 1 then
            alpha = alphaTarget
        else
            alpha = alpha + (alphaTarget - alpha) * step
        end
        if math.abs(alpha - alphaTarget) < 0.01 then alpha = alphaTarget end
        root:SetAlpha(alpha)
        if alpha <= 0 then Sleep() end
    end
end

local function Wake()
    if awake then return end
    awake = true
    Layout()
    sinceData = DATA_INTERVAL      -- first frame reads live data, not stale
    root:Show()
    root:SetAlpha(alpha)
    driver:SetScript("OnUpdate", DriverUpdate)
    Follow(1)   -- snap into place rather than easing in from the last spot
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

function CommanderReticle_Test()
    if not DB("EnableReticle", true) then
        print("Commander Reticle: the reticle is disabled (enable it in settings or /creticle)")
        return
    end
    testIndex = testIndex % #TEST_SPELLS + 1
    local spell = TEST_SPELLS[testIndex]
    cast.active, cast.test, cast.channel = true, true, false
    cast.name, cast.icon, cast.spellID = spell[1], spell[2], nil
    cast.start = GetTime()
    cast.finish = cast.start + TEST_DURATION
    ApplyArc()
    Wake()
    print(string.format("Commander Reticle: test cast — %s, %.1f seconds. Move the pointer over a unit frame to see it in place.",
        spell[1], TEST_DURATION))
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------

local watchTicker

local function Watch()
    if not DB("EnableReticle", true) then return end
    if awake then return end
    if ShouldShow() then Wake() end
end

local function Apply()
    if DB("EnableReticle", true) then
        Layout()
        ApplyArc()
        if not watchTicker then
            watchTicker = C_Timer.NewTicker(WATCH_INTERVAL, Watch)
        end
        if ShouldShow() then
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
events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")

events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        Commander.AddListener(COMMANDER_RETICLE_EVENTS.UPDATE, Apply)
        Apply()
        -- Logging in or reloading mid-cast still gets an arc
        ReadCast()
        return
    end
    if not DB("EnableReticle", true) then return end

    if event == "UPDATE_MOUSEOVER_UNIT" then
        if not awake and ShouldShow() then Wake() end
        return
    end
    if unit ~= "player" then return end

    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        SnapshotCastUnit()
        ReadCast()
        if not awake then Wake() end
    else
        ReadCast()
    end
end)
