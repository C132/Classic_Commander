-- Commander Plates: the radial plate's brushes.
--
-- The radial plate is the portrait treatment the suite already gives the
-- player and target frames -- buffs round the portrait, the cast as an arc on
-- its trim, the key fact standing in for the face -- applied to every
-- nameplate in the world. Instead of a bar with things stacked above and
-- beside it, each unit is a disc:
--
--        debuffs orbit over the top
--      .-- cast arc (outermost ring) --.
--     |  .-- health arc --.            |    buffs orbit down one side
--     |  |  .-- power --. |            |
--     |  |  |   CORE    | |            |    the core is the class, or the
--     |  |  '-----------' |            |    spell being cast, or the stun
--     |  '----------------'            |    the unit is sitting in
--      '------------------------------'
--              name, then the cast's name
--
-- Everything here is a brush: it builds or paints one widget from values it
-- is handed and never reads a unit. The runtime hands it a live unit's
-- values; the settings page hands it a mock's -- so, as with the bar-mode
-- preview, what the page shows is what the plate does.
--
-- Every ring is a Cooldown frame with a donut as its swipe texture: the
-- client masks the donut radially, which is a real arc it draws for free (see
-- the suite's API notes). A cast is a genuine cooldown the client animates;
-- health is a FROZEN one -- a very long cooldown, started so the swipe sits
-- at the health fraction, and re-set before it has moved a thousandth of the
-- way round. How long "very long" is depends on the clock: GetTime() counts
-- from the machine's boot, and a start time before zero is not something to
-- hand the client, so the cooldown is a day long only once the machine has
-- been up a day, and never longer than the time since boot.

CommanderPlates_Radial = CommanderPlates_Radial or {}
local R = CommanderPlates_Radial
local E = CommanderPlates_Engine
local DATA = CommanderPlates_Data

local TEX = "Interface\\AddOns\\Commander_Plates\\Textures\\"
-- The ring art, copied from Commander Casting's generator (Harness/make_rings.py
-- over there) so neither addon needs the other: six weights, thinnest first,
-- thickness baked in as inner radius over outer radius
R.RING_FILES = {
    TEX .. "Ring1.png", TEX .. "Ring2.png", TEX .. "Ring3.png",
    TEX .. "Ring4.png", TEX .. "Ring5.png", TEX .. "Ring6.png",
}
R.RING_RATIOS = { 0.93, 0.88, 0.80, 0.71, 0.60, 0.46 }
R.RING_OUTER = 0.485         -- the donut's outer radius over the texture's width
-- The glows (Harness/make_glows.py). Every one rises from GLOW_BASE of its
-- width -- the disc's edge -- and is fully transparent from GLOW_REACH out,
-- so none of them ends in the hard square the old art did, and all of them
-- are safe to spin.
R.GLOW_FILE = TEX .. "GlowSoft.png"
R.GLOW_STYLES = {
    SOFT = TEX .. "GlowSoft.png", EMBER = TEX .. "GlowEmber.png",
    RUNIC = TEX .. "GlowRunic.png", ARCANE = TEX .. "GlowArcane.png",
    RADIANT = TEX .. "GlowRadiant.png", FROST = TEX .. "GlowFrost.png",
    VOID = TEX .. "GlowVoid.png", HALO = TEX .. "GlowHalo.png",
    SIGIL = TEX .. "GlowSigil.png", STORM = TEX .. "GlowStorm.png",
}
R.GLOW_ORDER = { "SOFT", "EMBER", "RUNIC", "ARCANE", "RADIANT", "FROST", "VOID", "HALO", "SIGIL", "STORM" }
R.GLOW_LABEL = {
    SOFT = "Soft Halo", EMBER = "Emberflame", RUNIC = "Runebound", ARCANE = "Arcane Orbit",
    RADIANT = "Radiant Sunburst", FROST = "Frostshard", VOID = "Voidsmoke", HALO = "Holy Halo",
    SIGIL = "Star Sigil", STORM = "Stormcall",
}
R.TICK_FILE = TEX .. "Tick.png"
R.EDGE_FILE = TEX .. "Edge.png"
R.MASK_FILE = TEX .. "CircleMask.png"
-- The clock wipe's halves (Harness/make_wipe.py); the disc in them is
-- WIPE_RADIUS of the texture's width, inside a transparent margin
R.HALF_RIGHT = TEX .. "HalfRight.png"
R.HALF_LEFT = TEX .. "HalfLeft.png"
local WIPE_RADIUS = 0.46
R.RAID_FILE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local GLOW_BASE = 0.28       -- where every glow rises from, over its width
local SPIN_RATE = 0.5        -- radians a second, for the turning glows
local EDGE_CORE = 0.30       -- half-length of the spark's flat core over its width
local STATIC = 86400         -- a frozen arc is a cooldown at most this long
local DRIFT = 0.001          -- ...re-set once it could have moved this share of a turn
local ICON_INSET = 0.08
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local function Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- ---------------------------------------------------------------------------
-- The settings, read once per pass into one table
-- ---------------------------------------------------------------------------
function R.Config(get)
    local function G(key, default)
        local v = get(key)
        if v == nil then return default end
        return v
    end
    local cfg = {
        size = G("RadialSize", 46),
        targetScale = G("RadialTargetScale", 1.2),
        offsetY = G("RadialOffsetY", 0),
        healthThick = G("RadialHealthThickness", 5),
        healthColor = G("RadialHealthColor", "AUTO"),
        lowHealth = G("RadialLowHealth", 35),
        lowColor = G("RadialLowHealthColor", "RED"),
        trackAlpha = G("RadialTrackAlpha", 0.35),
        trail = G("RadialHealthTrail", true),
        healPredict = G("RadialHealPrediction", true),
        powerMode = G("RadialPower", "PLAYERS"),
        powerThick = G("RadialPowerThickness", 2),
        cast = G("RadialCastRing", true),
        castThick = G("RadialCastThickness", 3),
        castColor = G("RadialCastColor", "GOLD"),
        shieldColor = G("RadialUninterruptibleColor", "WHITE"),
        spark = G("RadialCastSpark", true),
        castName = G("RadialCastName", true),
        interruptFlash = G("RadialInterruptFlash", true),
        coreArt = G("RadialCoreArt", "CLASS"),
        coreText = G("RadialCoreText", "SMART"),
        textShade = G("RadialTextShade", 0.45),
        coreTextSize = G("RadialCoreTextSize", 0),
        coreCast = G("RadialCoreCast", true),
        coreCC = G("RadialCoreCC", true),
        name = G("RadialName", "BELOW"),
        nameSize = G("RadialNameSize", 10),
        nameWidth = G("RadialNameWidth", 96),
        auraSize = G("RadialAuraSize", 16),
        auraGap = G("RadialAuraGap", 2),
        auraSpacing = G("AuraSpacing", 2),
        maxArc = G("RadialAuraArc", 160),
        debuffArc = E.RADIAL_ARCS[G("RadialDebuffArc", "TOP")] or 0,
        buffArc = E.RADIAL_ARCS[G("RadialBuffArc", "RIGHT")] or 90,
        roundAuras = G("RadialRoundAuras", true),
        debuffGrow = G("RadialDebuffGrow", "CENTER"),
        buffGrow = G("RadialBuffGrow", "CENTER"),
        drMode = G("RadialDr", "ENEMIES"),
        drArc = E.RADIAL_ARCS[G("RadialDrArc", "LEFT")] or 270,
        castTarget = G("RadialCastTarget", true),
        trinket = G("RadialTrinket", true),
        targetsYou = G("RadialTargetingYou", "ENEMY_PLAYERS"),
        targetsYouColor = G("RadialTargetingYouColor", "RED"),
        combo = G("RadialComboPoints", true),
        threat = G("RadialThreat", "DPS"),
        raid = G("RadialRaidMarker", true),
        level = G("RadialLevel", true),
        eliteRim = G("RadialEliteRim", true),
        mouseover = G("RadialMouseover", true),
        rimColor = G("RadialRimColor", "REACTION"),
        backdrop = G("RadialBackdrop", "DARK"),
        backdropAlpha = G("RadialBackdropAlpha", 0.6),
        backdropPad = G("RadialBackdropSize", 2),
        glowStyle = G("RadialGlowStyle", "SOFT"),
        glowScale = G("RadialGlowSize", 1.0),
        glowMotion = G("RadialGlowMotion", "NONE"),
        backdropBorder = G("RadialBackdropBorder", true),
    }
    cfg.power = cfg.powerMode ~= "OFF"
    cfg.radii = E.RadialRadii({
        size = cfg.size, healthThick = cfg.healthThick,
        power = cfg.power, powerThick = cfg.powerThick,
        cast = cfg.cast, castThick = cfg.castThick,
        auraSize = cfg.auraSize, auraGap = cfg.auraGap,
    })
    cfg.pipSize = math.max(4, math.floor(cfg.castThick + 2))
    cfg.signature = table.concat({
        cfg.size, cfg.healthThick, tostring(cfg.power), cfg.powerThick, tostring(cfg.cast),
        cfg.castThick, cfg.nameSize, cfg.nameWidth, cfg.name, cfg.offsetY, cfg.backdropPad,
        cfg.glowStyle, cfg.glowScale, tostring((cfg.backdropAlpha or 0) > 0),
        cfg.textShade, cfg.coreTextSize,
    }, ":")
    return cfg
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------
local function NewSweep(parent, level, texture)
    local cd = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
    cd:EnableMouse(false)
    cd:SetFrameLevel(level)
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
    if cd.SetDrawBling then cd:SetDrawBling(false) end
    if cd.SetDrawSwipe then cd:SetDrawSwipe(true) end
    -- The Cooldown's own edge is a spoke from the centre out: on a donut it
    -- draws a line straight across the face. The cast arc has its own spark.
    if cd.SetDrawEdge then cd:SetDrawEdge(false) end
    if texture and cd.SetSwipeTexture then cd:SetSwipeTexture(texture) end
    -- OmniCC and its kin write a countdown on every Cooldown they can find;
    -- a health ring a day long would read "23h"
    cd.noCooldownCount = true
    cd.noOCC = true
    cd:Hide()
    return cd
end

local function Masked(owner, tex)
    if not (owner.CreateMaskTexture and tex.AddMaskTexture) then return false end
    return pcall(function()
        local mask = owner:CreateMaskTexture()
        mask:SetTexture(R.MASK_FILE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(tex)
        tex:AddMaskTexture(mask)
    end) == true
end

-- An arc: the dim full circle it runs round, the sweep, and a plain texture
-- for a FULL arc (a cooldown at 100% is a finished one, and hides itself)
local function NewArc(w, level, layer)
    local arc = {}
    arc.track = w:CreateTexture(nil, "BACKGROUND", nil, layer or 2)
    arc.track:SetPoint("CENTER", w, "CENTER")
    arc.track:Hide()
    arc.cd = NewSweep(w, level)
    arc.cd:SetPoint("CENTER", w, "CENTER")
    arc.fullFrame = CreateFrame("Frame", nil, w)
    arc.fullFrame:SetFrameLevel(level)
    arc.fullFrame:SetAllPoints(w)
    arc.full = arc.fullFrame:CreateTexture(nil, "ARTWORK")
    arc.full:SetPoint("CENTER", w, "CENTER")
    arc.full:Hide()
    return arc
end

local function NewGlow(w, layer, sub)
    local tex = w:CreateTexture(nil, layer, nil, sub)
    tex:SetTexture(R.GLOW_FILE)
    tex:SetBlendMode("ADD")
    tex:SetPoint("CENTER", w, "CENTER")
    tex:Hide()
    return tex
end

-- Every number on this plate is written over a picture -- a class icon, a
-- portrait, a spell -- and the picture is as often white as it is dark. The
-- one-pixel outline alone is not a floor under a white number on a white
-- icon: at these sizes it is a hairline the eye does not find. A hard black
-- shadow under the outline doubles the dark edge on the side text is read
-- from, and costs nothing.
function R.Legible(fs)
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) end
    if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
    fs.legible = true
end

local function NewText(parent, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size or 10, "OUTLINE")
    R.Legible(fs)
    fs:Hide()
    return fs
end

function R.New(parent)
    local w = CreateFrame("Frame", nil, parent)
    w:SetSize(1, 1)
    w:EnableMouse(false)
    local base = ((parent.GetFrameLevel and parent:GetFrameLevel()) or 1) + 1
    w:SetFrameLevel(base)
    w.base = base
    w.laid = {}

    -- Behind everything: the soft halos, then the backdrop the whole disc
    -- sits on, so it reads against snow and against a black cave alike
    w.glow = NewGlow(w, "BACKGROUND", -8)       -- target / focus
    w.alert = NewGlow(w, "BACKGROUND", -7)      -- threat
    w.backdrop = w:CreateTexture(nil, "BACKGROUND", nil, -6)
    w.backdrop:SetTexture(R.MASK_FILE)
    w.backdrop:SetPoint("CENTER", w, "CENTER")
    w.backdropRim = w:CreateTexture(nil, "BACKGROUND", nil, -5)
    w.backdropRim:SetTexture(R.RING_FILES[2])
    w.backdropRim:SetPoint("CENTER", w, "CENTER")
    w.coreBg = w:CreateTexture(nil, "BACKGROUND", nil, 0)
    w.coreBg:SetTexture(R.MASK_FILE)
    w.coreBg:SetPoint("CENTER", w, "CENTER")

    -- The face in the middle
    w.core = w:CreateTexture(nil, "BACKGROUND", nil, 1)
    w.core:SetPoint("CENTER", w, "CENTER")
    w.coreMasked = Masked(w, w.core)

    -- A control's countdown over the face, as a clock wipe CLIPPED to it: two
    -- half discs, each masked to its own half of the face and turned to the
    -- countdown (E.WipeAngles). A Cooldown's swipe cannot take a mask, and an
    -- unmasked one is free to paint past the face onto the rings.
    w.wipe = {}
    for i, clip in ipairs({ R.HALF_RIGHT, R.HALF_LEFT }) do
        local tex = w:CreateTexture(nil, "BACKGROUND", nil, 2)
        tex:SetTexture(R.HALF_RIGHT)
        tex:SetPoint("CENTER", w, "CENTER")
        tex:SetVertexColor(0, 0, 0, 0.6)
        tex:Hide()
        w.wipe[i] = tex
        local ok = w.CreateMaskTexture and tex.AddMaskTexture and pcall(function()
            local mask = w:CreateMaskTexture()
            mask:SetTexture(clip, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetPoint("CENTER", w, "CENTER")
            tex:AddMaskTexture(mask)
            tex.clip = mask
        end)
        w.wipeMasked = (i == 1 or w.wipeMasked) and ok == true
    end

    -- The shade: the face darkened while a number is written across it. The
    -- shadow on the text holds its edges; this is what holds its MIDDLE -- a
    -- white "60" over a paladin's white-gold class icon has an edge and
    -- nothing inside it to tell from the picture. Above the face and the
    -- wipe, below every ring, and only ever up while there is text to read.
    w.shade = w:CreateTexture(nil, "BACKGROUND", nil, 3)
    w.shade:SetTexture(R.MASK_FILE)
    w.shade:SetPoint("CENTER", w, "CENTER")
    w.shade:SetVertexColor(0, 0, 0, 0.45)
    w.shade:Hide()

    -- The arcs, lowest first: a heal on the way and the trail of health just
    -- lost both sit UNDER the health arc and start where it does, so all that
    -- shows of them is the part that runs past it
    -- Every ring draws ABOVE the face and whatever darkens it
    w.powerArc = NewArc(w, base + 2, 2)
    w.healArc = NewArc(w, base + 2, 2)
    w.trailArc = NewArc(w, base + 3, 2)
    w.healthArc = NewArc(w, base + 4, 3)
    w.castArc = NewArc(w, base + 4, 2)
    -- The trail and the heal draw no track of their own: the health arc's is theirs
    w.trailArc.noTrack, w.healArc.noTrack = true, true

    -- The fallback for a client with no masks: a Cooldown, kept BELOW the
    -- rings so that even unclipped it can only ever darken the face
    w.coreCd = NewSweep(w, base + 1, R.MASK_FILE)
    w.coreCd:SetPoint("CENTER", w, "CENTER")
    if w.coreCd.SetReverse then w.coreCd:SetReverse(true) end
    if w.coreCd.SetSwipeColor then w.coreCd:SetSwipeColor(0, 0, 0, 0.6) end

    -- Above the sweeps: everything a sweep must never cover
    local over = CreateFrame("Frame", nil, w)
    over:SetAllPoints(w)
    over:SetFrameLevel(base + 6)
    w.over = over
    w.rim = over:CreateTexture(nil, "ARTWORK", nil, 0)
    w.rim:SetTexture(R.RING_FILES[1])
    w.rim:SetPoint("CENTER", w, "CENTER")
    w.flash = NewGlow(w.over, "OVERLAY", 6)
    w.spark = over:CreateTexture(nil, "OVERLAY", nil, 4)
    w.spark:SetTexture(R.EDGE_FILE)
    w.spark:SetBlendMode("ADD")
    w.spark:Hide()
    w.ticks = {}
    for _, key in ipairs({ "pct", "value" }) do
        local t = over:CreateTexture(nil, "OVERLAY", nil, 3)
        t:SetTexture(R.TICK_FILE)
        t:Hide()
        w.ticks[key] = t
    end
    w.pips = {}
    for i = 1, 5 do
        local p = over:CreateTexture(nil, "OVERLAY", nil, 2)
        p:SetTexture(R.MASK_FILE)
        p:Hide()
        w.pips[i] = p
    end
    w.raid = over:CreateTexture(nil, "OVERLAY", nil, 5)
    w.raid:SetTexture(R.RAID_FILE)
    w.raid:Hide()
    w.healer = over:CreateTexture(nil, "OVERLAY", nil, 5)
    w.healer:SetTexture(DATA.HEALER_ICON)
    w.healer:SetTexCoord(unpack(DATA.HEALER_ICON_COORDS))
    w.healer:Hide()
    w.classBadge = over:CreateTexture(nil, "OVERLAY", nil, 5)
    w.classBadge:SetTexture(DATA.CLASS_ICON)
    w.classBadge:Hide()
    -- "Looking at you": a thin ring just outside everything else
    w.youRing = over:CreateTexture(nil, "ARTWORK", nil, 1)
    w.youRing:SetTexture(R.RING_FILES[2])
    w.youRing:SetPoint("CENTER", w, "CENTER")
    w.youRing:Hide()
    w.arrowL = over:CreateTexture(nil, "OVERLAY", nil, 4)
    w.arrowL:SetTexture(DATA.ARROW_ICON)
    w.arrowL:Hide()
    w.arrowR = over:CreateTexture(nil, "OVERLAY", nil, 4)
    w.arrowR:SetTexture(DATA.ARROW_ICON)
    w.arrowR:SetTexCoord(1, 0, 0, 1)
    w.arrowR:Hide()

    -- The PvP trinket, on the rim at twelve: its own icon, green when ready,
    -- its cooldown sweeping when not (built once New's other parts exist)
    w.centerText = NewText(over, 11)
    w.centerText:SetPoint("CENTER", w, "CENTER", 0, 0)
    w.drBadge = NewText(over, 9)
    w.levelText = NewText(over, 9)
    w.nameText = NewText(over, 10)
    if w.nameText.SetWordWrap then w.nameText:SetWordWrap(false) end
    w.castText = NewText(over, 9)
    if w.castText.SetWordWrap then w.castText:SetWordWrap(false) end

    -- The auras have their own layer, above the rings and below nothing
    w.auraLayer = CreateFrame("Frame", nil, w)
    w.auraLayer:SetAllPoints(w)
    w.auraLayer:SetFrameLevel(base + 8)

    w.trinket = R.NewOrbitIcon(over)
    w.trinket.cd:SetFrameLevel(base + 7)
    if w.trinket.cd.SetReverse then w.trinket.cd:SetReverse(false) end
    w.trinket.text:SetFrameLevel(base + 8)

    w:SetScript("OnUpdate", nil)
    w:Hide()
    return w
end

-- ---------------------------------------------------------------------------
-- Geometry, only when a number it depends on changed
-- ---------------------------------------------------------------------------
local function LayArc(arc, outer, thickness)
    local index = E.RingWeight(outer, thickness, R.RING_RATIOS)
    local file, ratio = R.RING_FILES[index], R.RING_RATIOS[index]
    local size = outer / R.RING_OUTER
    arc.track:SetTexture(file)
    arc.track:SetSize(size, size)
    arc.cd:SetSize(size, size)
    if arc.cd.SetSwipeTexture then arc.cd:SetSwipeTexture(file) end
    arc.full:SetTexture(file)
    arc.full:SetSize(size, size)
    -- What the band on screen measures -- the nearest of six weights, rarely
    -- the requested pixel count -- so markers riding it measure, not trust
    arc.band = outer * (1 - ratio)
    arc.radius = outer - arc.band / 2
    arc.f, arc.setAt = nil, nil
end

function R.Layout(w, cfg)
    if w.laid.signature == cfg.signature then return end
    w.laid.signature = cfg.signature
    local r = cfg.radii
    w.laid.radii = r
    local box = r.outer * 2
    w:SetSize(box, box)

    local coreD = r.core * 2
    w.coreBg:SetSize(coreD + 2, coreD + 2)
    local coreSize = w.coreMasked and coreD or coreD * 0.7071
    w.core:SetSize(coreSize, coreSize)
    w.coreCd:SetSize(coreSize, coreSize)
    w.shade:SetSize(coreD, coreD)
    w.laid.textShade = cfg.textShade or 0
    w.shade:SetVertexColor(0, 0, 0, w.laid.textShade)
    if w.laid.textShade <= 0 then w.shade:Hide() end
    local wipeSize = (coreSize / 2) / WIPE_RADIUS
    for _, tex in ipairs(w.wipe) do
        tex:SetSize(wipeSize, wipeSize)
        if tex.clip then tex.clip:SetSize(wipeSize, wipeSize) end
    end
    -- How far past the outer ring the backdrop reaches (negative pulls it in,
    -- never smaller than the face it sits behind)
    local backR = math.max(r.core + 1, r.outer + (cfg.backdropPad or 2))
    w.laid.backdropRadius = backR
    w.backdrop:SetSize(backR * 2, backR * 2)
    w.backdropRim:SetSize((backR + 1) / R.RING_OUTER, (backR + 1) / R.RING_OUTER)
    -- The rim fills the pixel of air between the face and the first band
    local rimOuter = r.core + 1.5
    w.rim:SetSize(rimOuter / R.RING_OUTER, rimOuter / R.RING_OUTER)

    LayArc(w.healthArc, r.health, cfg.healthThick)
    LayArc(w.trailArc, r.health, cfg.healthThick)
    LayArc(w.healArc, r.health, cfg.healthThick)
    if r.power then LayArc(w.powerArc, r.power, cfg.powerThick) end
    if r.cast then LayArc(w.castArc, r.cast, cfg.castThick) end

    -- Every glow rises from the plate's visible edge: the backdrop's when
    -- there is one, else the outermost ring
    local edge = r.outer
    if (cfg.backdropAlpha or 0) > 0 and w.laid.backdropRadius then edge = math.max(edge, w.laid.backdropRadius) end
    local glowSize = (edge + 1) / GLOW_BASE
    w.glow:SetTexture(R.GLOW_STYLES[cfg.glowStyle] or R.GLOW_FILE)
    w.glow:SetSize(glowSize * cfg.glowScale, glowSize * cfg.glowScale)
    w.alert:SetSize(glowSize * 1.05, glowSize * 1.05)
    w.flash:SetSize(glowSize * 1.12, glowSize * 1.12)
    w.laid.glowMotion = cfg.glowMotion

    local castBand = (r.cast and w.castArc.band) or 3
    local sparkSize = castBand / (EDGE_CORE * 2)
    w.spark:SetSize(sparkSize, sparkSize)
    local tickSize = w.healthArc.band + 6
    for _, t in pairs(w.ticks) do t:SetSize(tickSize, tickSize) end

    local pip = cfg.pipSize
    for _, p in ipairs(w.pips) do p:SetSize(pip, pip) end

    local badge = math.max(10, math.floor(cfg.size * 0.3))
    for _, tex in ipairs({ w.raid, w.healer, w.classBadge }) do tex:SetSize(badge, badge) end
    w.laid.badge = badge

    -- The number in the middle: sized off the face unless the player has said
    -- otherwise, and the DR bracket under it keeps its proportion to it either
    -- way -- a badge that stayed small under a number made large would read
    -- as a footnote to it.
    local centerSize = math.max(8, math.floor(r.core * 0.85))
    if (cfg.coreTextSize or 0) > 0 then centerSize = cfg.coreTextSize end
    w.centerText:SetFont(FONT, centerSize, "OUTLINE")
    w.drBadge:SetFont(FONT, math.max(8, math.floor(centerSize * 0.65)), "OUTLINE")
    w.levelText:SetFont(FONT, math.max(8, math.floor(cfg.size * 0.2)), "OUTLINE")
    w.nameText:SetFont(FONT, cfg.nameSize, "OUTLINE")
    w.nameText:SetWidth(cfg.nameWidth)
    w.castText:SetFont(FONT, math.max(8, cfg.nameSize - 1), "OUTLINE")
    w.castText:SetWidth(cfg.nameWidth)

    -- Badges on the rim, at their clock positions
    local function OnRim(tex, deg, radius)
        local x, y = E.ArcPoint(radius, deg / 360)
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", w, "CENTER", x, y)
    end
    -- Just outside the rings (and the backdrop's edge), never on them
    local badgeR = r.outer + 2 + badge / 2
    w.laid.badgeRadius = badgeR
    OnRim(w.raid, E.RADIAL_BADGES.raid, badgeR)
    OnRim(w.healer, E.RADIAL_BADGES.healer, badgeR)
    OnRim(w.classBadge, E.RADIAL_BADGES.class, badgeR)
    OnRim(w.levelText, E.RADIAL_BADGES.level, badgeR)
    OnRim(w.trinket, E.RADIAL_BADGES.trinket, badgeR)
    w.trinket:SetSize(badge, badge)
    local youOuter = r.outer + 3
    w.youRing:SetSize(youOuter / R.RING_OUTER, youOuter / R.RING_OUTER)
    w.drBadge:ClearAllPoints()
    w.drBadge:SetPoint("TOP", w, "CENTER", 0, -r.core * 0.25)
end

-- The disc sits on the plate's own anchor (the health bar Blizzard would
-- have drawn), so the client's stacking and scaling carry it unchanged
function R.Place(w, anchor, cfg, isTarget)
    w:ClearAllPoints()
    local scale = isTarget and cfg.targetScale or 1
    if w.laid.scale ~= scale then
        w.laid.scale = scale
        w:SetScale(scale)
    end
    -- A point's offset is in the frame's own (scaled) units
    w:SetPoint("CENTER", anchor, "CENTER", 0, cfg.offsetY / scale)
end

-- ---------------------------------------------------------------------------
-- Arcs
-- ---------------------------------------------------------------------------
local function ArcHide(arc)
    arc.cd:Hide()
    arc.full:Hide()
    arc.f = nil
end

-- A frozen arc at `fraction`. The arc ENDS at twelve o'clock and starts
-- (1 - fraction) of the way round, so as the value drops its leading edge
-- walks CLOCKWISE toward twelve -- the empty part grows the way a clock hand
-- turns. Everything layered on the same ring (the damage trail, incoming
-- heals) shares that end, so what shows of each is the stretch just before
-- the health arc's edge.
local function ArcSet(arc, fraction, r, g, b, a, now)
    a = a or 1
    if not fraction or fraction <= 0.002 then ArcHide(arc) return end
    if fraction >= 0.998 then
        arc.cd:Hide()
        arc.full:SetVertexColor(r, g, b, a)
        arc.full:Show()
        arc.f = 1
        return
    end
    arc.full:Hide()
    local colour = r * 1e6 + g * 1e3 + b + a * 1e-3
    if arc.f and math.abs(arc.f - fraction) < 0.001 and arc.colour == colour
        and arc.setAt and now - arc.setAt < arc.span * DRIFT and arc.cd:IsShown() then
        return
    end
    local span = Clamp(now, 60, STATIC)
    arc.f, arc.colour, arc.setAt, arc.span = fraction, colour, now, span
    -- Not reversed: a cooldown paints what REMAINS, which runs from the
    -- sweep's edge clockwise round to twelve
    if arc.cd.SetReverse then arc.cd:SetReverse(false) end
    if arc.cd.SetSwipeColor then arc.cd:SetSwipeColor(r, g, b, a) end
    arc.cd:SetCooldown(now - (1 - fraction) * span, span)
    arc.cd:Show()
end

local function ArcTrack(arc, shown, alpha)
    if shown and not arc.noTrack then
        arc.track:SetVertexColor(0.05, 0.05, 0.07, alpha or 0.35)
        arc.track:Show()
    else
        arc.track:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- The animation clock: the cast spark, the interrupt flash, the damage trail.
-- Only runs while one of them is live.
-- ---------------------------------------------------------------------------
local function Animating(w)
    return w.sparkLive or w.flashUntil or w.trailLive or w.wipeLive or w.glowLive
end

-- Turn the two halves of the clock wipe to `p` of the face darkened
local function PaintWipe(w, p)
    local a1, a2 = E.WipeAngles(p)
    if w.wipe[1].SetRotation then
        w.wipe[1]:SetRotation(-math.rad(a1))
        w.wipe[2]:SetRotation(-math.rad(a2))
    end
    w.wipePhase = p
end

local function MoveSpark(w, now)
    local c = w.castLive
    if not c or c.duration <= 0 then w.spark:Hide() return end
    local p = Clamp((now - c.start) / c.duration, 0, 1)
    if c.channel then p = 1 - p end
    local x, y, theta = E.ArcPoint(w.castArc.radius or 0, p)
    w.spark:ClearAllPoints()
    w.spark:SetPoint("CENTER", w, "CENTER", x, y)
    if w.spark.SetRotation then w.spark:SetRotation(-theta) end
end

local function OnUpdate(w, elapsed)
    local now = GetTime()
    if w.glowLive then
        local motion = w.glowMotion
        if (motion == "SPIN" or motion == "BOTH") and w.glow.SetRotation then
            w.glow:SetRotation(-(now * SPIN_RATE) % (math.pi * 2))
        end
        if motion == "PULSE" or motion == "BOTH" then
            w.glow:SetAlpha(0.65 + 0.35 * (0.5 + 0.5 * math.sin(now * 3.2)))
        end
    end
    if w.sparkLive then MoveSpark(w, now) end
    if w.wipeLive then
        local p = (now - w.wipeStart) / w.wipeDuration
        if p >= 1 then
            w.wipeLive = false
            for _, tex in ipairs(w.wipe) do tex:Hide() end
        else
            PaintWipe(w, p)
        end
    end
    if w.flashUntil then
        local left = w.flashUntil - now
        if left <= 0 then
            w.flashUntil = nil
            w.flash:Hide()
            if w.flashText then w.castText:Hide(); w.flashText = nil end
        else
            w.flash:SetAlpha(Clamp(left / 0.6, 0, 1))
        end
    end
    if w.trailLive then
        local value, moving = E.TrailStep(w.trailValue, w.trailTarget, now - (w.trailSince or now), elapsed, 0.35, 0.9)
        w.trailValue = value
        if value > w.trailTarget + 0.002 then
            ArcSet(w.trailArc, value, 1, 0.85, 0.55, 0.85, now)
        else
            ArcHide(w.trailArc)
        end
        w.trailLive = moving
    end
    if not Animating(w) then w:SetScript("OnUpdate", nil) end
end

local function Animate(w)
    if Animating(w) and not w:GetScript("OnUpdate") then w:SetScript("OnUpdate", OnUpdate) end
end

-- ---------------------------------------------------------------------------
-- Painting. Each takes plain values; none reads a unit.
-- ---------------------------------------------------------------------------

-- Health, with the heal on its way and the trail of what the last hit took
function R.SetHealth(w, cfg, fraction, r, g, b, now, heal)
    ArcTrack(w.healthArc, true, cfg.trackAlpha)
    ArcSet(w.healthArc, fraction, r, g, b, 1, now)
    if cfg.healPredict and heal and heal > 0.002 and fraction < 0.998 then
        ArcSet(w.healArc, math.min(1, fraction + heal), 0.35, 0.95, 0.45, 0.55, now)
    else
        ArcHide(w.healArc)
    end
    if cfg.trail then
        if w.trailValue and fraction < w.trailValue - 0.002 then
            -- A fresh hit restarts the hold; a hit landing mid-slide does not
            -- push the ghost back UP past where it already was
            if not w.trailLive then w.trailSince = now end
            w.trailTarget = fraction
            w.trailLive = true
            ArcSet(w.trailArc, w.trailValue, 1, 0.85, 0.55, 0.85, now)
            Animate(w)
        else
            w.trailValue, w.trailTarget, w.trailLive = fraction, fraction, false
            ArcHide(w.trailArc)
        end
    else
        w.trailValue, w.trailLive = fraction, false
        ArcHide(w.trailArc)
    end
end

-- Forget the trail (a new occupant of a pooled plate is somebody else)
function R.ResetTrail(w)
    w.trailValue, w.trailTarget, w.trailLive = nil, nil, false
    ArcHide(w.trailArc)
end

function R.SetPower(w, cfg, fraction, r, g, b, now)
    if not (cfg.power and fraction) then
        ArcTrack(w.powerArc, false)
        ArcHide(w.powerArc)
        return
    end
    ArcTrack(w.powerArc, true, cfg.trackAlpha)
    ArcSet(w.powerArc, fraction, r, g, b, 1, now)
end

-- A live cast: the client animates the arc; the spark is ours
function R.SetCast(w, cfg, start, duration, channel, r, g, b)
    if not (cfg.cast and duration and duration > 0) then R.ClearCast(w) return end
    local arc = w.castArc
    ArcTrack(arc, true, cfg.trackAlpha)
    arc.full:Hide()
    if arc.cd.SetReverse then arc.cd:SetReverse(not channel) end
    if arc.cd.SetSwipeColor then arc.cd:SetSwipeColor(r, g, b, 1) end
    arc.cd:SetCooldown(start, duration)
    arc.cd:Show()
    w.castLive = { start = start, duration = duration, channel = channel }
    if cfg.spark then
        w.spark:SetVertexColor((r + 1) / 2, (g + 1) / 2, (b + 1) / 2)
        w.spark:Show()
        w.sparkLive = true
        MoveSpark(w, GetTime())
        Animate(w)
    else
        w.sparkLive = false
        w.spark:Hide()
    end
end

function R.ClearCast(w)
    local arc = w.castArc
    arc.cd:Hide()
    arc.full:Hide()
    ArcTrack(arc, false)
    w.castLive = nil
    w.sparkLive = false
    w.spark:Hide()
end

-- "It just got kicked": a burst on the ring, and the cast line saying so
function R.Flash(w, r, g, b, text)
    w.flash:SetVertexColor(r, g, b, 1)
    w.flash:SetAlpha(1)
    w.flash:Show()
    w.flashUntil = GetTime() + 0.6
    if text then
        w.castText:SetText(text)
        w.castText:SetTextColor(r, g, b)
        w.castText:Show()
        w.flashText = true
    end
    Animate(w)
end

-- The face: CLASS (a class token), PORTRAIT (a unit), ICON (a texture), NONE.
-- Unchanged faces are skipped -- a portrait is a render, not a texture swap --
-- unless `force` says the picture behind the same key has changed.
function R.SetCore(w, kind, value, coords, force)
    local key = kind .. ":" .. tostring(value)
    if not force and w.coreKey == key then return end
    w.coreKey = key
    local core = w.core
    if kind == "CLASS" then
        local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[value]
        if not tc then kind = "NONE" else
            core:SetTexture(DATA.CLASS_ICON)
            core:SetTexCoord(unpack(tc))
        end
    elseif kind == "PORTRAIT" then
        if SetPortraitTexture and value then
            core:SetTexCoord(0, 1, 0, 1)
            SetPortraitTexture(core, value)
        else
            kind = "NONE"
        end
    elseif kind == "ICON" then
        core:SetTexture(value or DATA.FALLBACK_ICON)
        if coords then core:SetTexCoord(unpack(coords)) else
            core:SetTexCoord(ICON_INSET, 1 - ICON_INSET, ICON_INSET, 1 - ICON_INSET)
        end
    end
    core:SetShown(kind ~= "NONE")
    w.coreKind = kind
end

-- A control's countdown over the face: the masked clock wipe, or on a
-- client without masks the Cooldown (below the rings, so still never on them)
function R.SetCoreSwipe(w, start, duration)
    local live = start and duration and duration > 0 and GetTime() < start + duration
    if not live then
        w.coreCd:Hide()
        w.wipeLive = false
        for _, tex in ipairs(w.wipe) do tex:Hide() end
        return
    end
    if w.wipeMasked then
        w.coreCd:Hide()
        w.wipeStart, w.wipeDuration, w.wipeLive = start, duration, true
        for _, tex in ipairs(w.wipe) do tex:Show() end
        PaintWipe(w, (GetTime() - start) / duration)
        Animate(w)
    else
        w.coreCd:SetCooldown(start, duration)
        w.coreCd:Show()
    end
end

-- The backdrop: a disc behind all of it, and a thin rim round its edge
function R.SetBackdrop(w, r, g, b, a, border)
    if not a or a <= 0 then
        w.backdrop:Hide()
    else
        w.backdrop:SetVertexColor(r, g, b, a)
        w.backdrop:Show()
    end
    if border then
        w.backdropRim:SetVertexColor(0, 0, 0, math.min(1, (a or 0) + 0.3))
        w.backdropRim:Show()
    else
        w.backdropRim:Hide()
    end
end

function R.SetBacking(w, r, g, b, a)
    w.coreBg:SetVertexColor(r, g, b, a or 0.85)
end

function R.SetRim(w, r, g, b, a)
    if not r then w.rim:Hide() return end
    w.rim:SetVertexColor(r, g, b, a or 1)
    w.rim:Show()
end

-- The target / focus glow. `motion` NONE | SPIN | PULSE | BOTH; the motion
-- runs on the widget's own clock only while the glow is up
function R.SetGlow(w, shown, r, g, b, a, motion)
    if not shown then
        w.glow:Hide()
        w.glowLive = false
        return
    end
    w.glow:SetVertexColor(r, g, b, a or 0.8)
    w.glow:SetAlpha(1)
    if w.glow.SetRotation then w.glow:SetRotation(0) end
    w.glow:Show()
    w.glowMotion = motion or "NONE"
    w.glowLive = w.glowMotion ~= "NONE"
    if w.glowLive then Animate(w) end
end

function R.SetAlert(w, shown, r, g, b, a)
    if not shown then w.alert:Hide() return end
    w.alert:SetVertexColor(r, g, b, a or 0.7)
    w.alert:Show()
end

-- A line across the health band where the arc's edge will be when the unit
-- is down to `fraction` (the arc ends at twelve, so that is 1 - fraction of
-- the way round)
function R.SetMarker(w, key, fraction, r, g, b)
    local t = w.ticks[key]
    if not t then return end
    if not fraction or fraction <= 0 or fraction >= 1 then t:Hide() return end
    local x, y, theta = E.ArcPoint(w.healthArc.radius or 0, 1 - fraction)
    t:ClearAllPoints()
    t:SetPoint("CENTER", w, "CENTER", x, y)
    if t.SetRotation then t:SetRotation(-theta) end
    t:SetVertexColor(r, g, b, 0.95)
    t:Show()
end

function R.SetCenterText(w, text, r, g, b)
    if not text or text == "" then
        w.centerText:Hide()
        w.shade:Hide()
        return
    end
    w.centerText:SetText(text)
    w.centerText:SetTextColor(r or 1, g or 1, b or 1)
    w.centerText:Show()
    -- The face goes dark under the number for exactly as long as there is one
    w.shade:SetShown((w.laid.textShade or 0) > 0)
end

function R.SetDrBadge(w, text, r, g, b)
    if not text or text == "" then w.drBadge:Hide() return end
    w.drBadge:SetText(text)
    w.drBadge:SetTextColor(r or 1, g or 1, b or 1)
    w.drBadge:Show()
end

function R.SetLevel(w, text, r, g, b)
    if not text or text == "" then w.levelText:Hide() return end
    w.levelText:SetText(text)
    w.levelText:SetTextColor(r or 1, g or 1, b or 1)
    w.levelText:Show()
end

-- Combo points round the bottom of the ring, just outside it
function R.SetPips(w, cfg, n, max)
    max = max or 5
    local r = cfg.radii
    local radius = r.outer + cfg.pipSize / 2 + 2
    local step = math.deg(2 * math.asin(math.min(0.99, (cfg.pipSize + 2) / (2 * radius))))
    for i, p in ipairs(w.pips) do
        if n and n > 0 and i <= max then
            local deg = 180 + (((max + 1) / 2) - i) * step
            local x, y = E.ArcPoint(radius, deg / 360)
            p:ClearAllPoints()
            p:SetPoint("CENTER", w, "CENTER", x, y)
            if i <= n then
                p:SetVertexColor(E.ComboTint(n, max))
            else
                p:SetVertexColor(0.1, 0.1, 0.1, 0.8)
            end
            p:Show()
        else
            p:Hide()
        end
    end
end

-- A raid target icon, 1-8
function R.SetRaid(w, index)
    if not index then w.raid:Hide() return end
    if SetRaidTargetIconTexture then
        SetRaidTargetIconTexture(w.raid, index)
    else
        local col, row = (index - 1) % 4, math.floor((index - 1) / 4)
        w.raid:SetTexCoord(col / 4, (col + 1) / 4, row / 4, (row + 1) / 4)
    end
    w.raid:Show()
end

-- The trinket: nil icon hides it. start/duration in seconds; none = ready.
function R.SetTrinket(w, icon, start, duration)
    local f = w.trinket
    if not icon then f:Hide() return end
    f.icon:SetTexture(icon)
    local down = start and duration and duration > 0 and start + duration > GetTime()
    if down then
        f.border:SetVertexColor(0.92, 0.26, 0.26, 1)
        if f.icon.SetDesaturated then f.icon:SetDesaturated(true) end
        f.cd:SetCooldown(start, duration)
        f.cd:Show()
    else
        f.border:SetVertexColor(0.3, 1, 0.3, 1)
        if f.icon.SetDesaturated then f.icon:SetDesaturated(false) end
        f.cd:Hide()
    end
    f.timer:Hide(); f.count:Hide(); f.badge:Hide(); f.glow:Hide()
    f:Show()
end

function R.SetTargetsYou(w, shown, r, g, b)
    if not shown then w.youRing:Hide() return end
    w.youRing:SetVertexColor(r, g, b, 0.95)
    w.youRing:Show()
end

-- A corpse: the face goes grey
function R.SetDead(w, dead)
    if w.dead == dead then return end
    w.dead = dead
    if w.core.SetDesaturated then w.core:SetDesaturated(dead) end
    w.core:SetAlpha(dead and 0.5 or 1)
end

function R.SetHealer(w, shown)
    w.healer:SetShown(shown == true)
end

function R.SetClassBadge(w, class)
    local tc = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if not tc then w.classBadge:Hide() return end
    w.classBadge:SetTexCoord(unpack(tc))
    w.classBadge:Show()
end

-- The name, and under it the spell being cast. `reserve` is extra room
-- below the ring (combo pips) the text has to clear.
function R.SetName(w, cfg, text, r, g, b, reserve)
    local fs = w.nameText
    if cfg.name == "NONE" or not text or text == "" then fs:Hide() else
        fs:SetText(text)
        fs:SetTextColor(r or 1, g or 1, b or 1)
        fs:Show()
    end
    local outer = cfg.radii.outer
    fs:ClearAllPoints()
    w.castText:ClearAllPoints()
    if cfg.name == "ABOVE" then
        fs:SetPoint("BOTTOM", w, "CENTER", 0, outer + 2)
        w.castText:SetPoint("TOP", w, "CENTER", 0, -(outer + 2 + (reserve or 0)))
    else
        fs:SetPoint("TOP", w, "CENTER", 0, -(outer + 2 + (reserve or 0)))
        w.castText:SetPoint("TOP", fs, "BOTTOM", 0, -1)
    end
end

function R.SetCastName(w, text, r, g, b)
    if w.flashText then return end   -- "Interrupted" holds the line until it fades
    if not text or text == "" then w.castText:Hide() return end
    w.castText:SetText(text)
    w.castText:SetTextColor(r or 1, g or 1, b or 1)
    w.castText:Show()
end

-- Target arrows either side, clear of whatever orbits at that height
function R.SetArrows(w, cfg, shown, size, r, g, b, leftReach, rightReach)
    if not shown then w.arrowL:Hide(); w.arrowR:Hide() return end
    local outer = cfg.radii.outer
    local left = math.max(outer, leftReach or 0) + 2
    local right = math.max(outer, rightReach or 0) + 2
    for _, tex in ipairs({ w.arrowL, w.arrowR }) do
        tex:SetSize(size, size)
        tex:SetVertexColor(r, g, b)
        tex:Show()
    end
    w.arrowL:ClearAllPoints()
    w.arrowL:SetPoint("RIGHT", w, "CENTER", -left, 0)
    w.arrowR:ClearAllPoints()
    w.arrowR:SetPoint("LEFT", w, "CENTER", right, 0)
end

-- ---------------------------------------------------------------------------
-- The orbit: round aura icons, the same fields the bar mode's icons carry so
-- the runtime paints both with one function
-- ---------------------------------------------------------------------------
function R.NewOrbitIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.round = true
    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetTexture(R.MASK_FILE)
    f.border:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    f.border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(ICON_INSET, 1 - ICON_INSET, ICON_INSET, 1 - ICON_INSET)
    Masked(f, f.icon)

    f.cd = NewSweep(f, (f:GetFrameLevel() or 1) + 1, R.MASK_FILE)
    f.cd:SetAllPoints()
    if f.cd.SetReverse then f.cd:SetReverse(true) end
    if f.cd.SetSwipeColor then f.cd:SetSwipeColor(0, 0, 0, 0.6) end

    f.text = CreateFrame("Frame", nil, f)
    f.text:SetAllPoints()
    f.text:SetFrameLevel((f.cd:GetFrameLevel() or 2) + 1)
    f.count = f.text:CreateFontString(nil, "OVERLAY")
    f.count:SetFont(FONT, 9, "OUTLINE")
    f.count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -1)
    f.timer = f.text:CreateFontString(nil, "OVERLAY")
    f.timer:SetFont(FONT, 9, "OUTLINE")
    f.timer:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.badge = f.text:CreateFontString(nil, "OVERLAY")
    f.badge:SetFont(FONT, 9, "OUTLINE")
    f.badge:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2)
    -- Written on an aura's own icon, which is whatever colour the spell is
    R.Legible(f.count); R.Legible(f.timer); R.Legible(f.badge)
    f.badge:Hide()
    f.glow = f:CreateTexture(nil, "OVERLAY", nil, 3)
    f.glow:SetTexture(R.GLOW_FILE)
    f.glow:SetBlendMode("ADD")
    f.glow:SetPoint("CENTER")
    f.glow:Hide()
    f:EnableMouse(false)
    f:Hide()
    return f
end

-- Place icons[from .. from+count-1] round the orbit from `center` degrees,
-- growing the way `grow` says. Returns the slots, so the caller can see what
-- it covered.
function R.LayoutOrbit(w, cfg, icons, from, count, center, grow)
    local slots = E.OrbitLayout(count, cfg.radii.orbit, cfg.auraSize, cfg.auraSpacing, center, cfg.maxArc, grow)
    for i = 1, count do
        local f = icons[from + i - 1]
        local s = slots[i]
        f:ClearAllPoints()
        f:SetPoint("CENTER", w, "CENTER", s[1], s[2])
    end
    return slots
end

-- ---------------------------------------------------------------------------
-- Diminishing returns round the disc: one small icon per category that is
-- open on the unit -- the last spell that opened it, the bracket the NEXT one
-- would land at written across it, and, once the aura is gone, the fifteen
-- seconds to reset sweeping away. rows: { icon, label, r, g, b, start,
-- duration } (start nil = held: something is still up, the clock is frozen).
-- ---------------------------------------------------------------------------
function R.SetDrStrip(w, cfg, rows, center)
    w.drIcons = w.drIcons or {}
    local pool = w.drIcons
    local n = rows and #rows or 0
    local size = math.max(10, math.floor(cfg.auraSize * 0.85))
    for i = #pool + 1, n do pool[i] = R.NewOrbitIcon(w.auraLayer) end
    for i = n + 1, #pool do pool[i]:Hide() end
    if n == 0 then return {} end
    for i = 1, n do
        local row, f = rows[i], pool[i]
        f:SetSize(size, size)
        f.icon:SetTexture(row.icon or DATA.FALLBACK_ICON)
        f.border:SetVertexColor(row.r, row.g, row.b, 1)
        f.timer:SetFont(FONT, math.max(8, math.floor(size * 0.6)), "OUTLINE")
        f.timer:SetText(row.label or "")
        f.timer:SetTextColor(row.r, row.g, row.b)
        f.timer:Show()
        f.count:Hide(); f.badge:Hide(); f.glow:Hide()
        if row.start and row.duration and row.duration > 0 then
            -- The reset: dark over what is LEFT, so it clears as it comes back
            if f.cd.SetReverse then f.cd:SetReverse(false) end
            f.cd:SetCooldown(row.start, row.duration)
            f.cd:Show()
        else
            f.cd:Hide()
        end
        f:Show()
    end
    local slots = E.OrbitLayout(n, cfg.radii.orbit, size, cfg.auraSpacing, center, cfg.maxArc)
    for i = 1, n do
        pool[i]:ClearAllPoints()
        pool[i]:SetPoint("CENTER", w, "CENTER", slots[i][1], slots[i][2])
    end
    return slots
end

-- Everything off: the widget is going back into the pool with its plate
function R.Clear(w)
    R.ClearCast(w)
    R.ResetTrail(w)
    ArcHide(w.healthArc); ArcHide(w.healArc); ArcHide(w.powerArc)
    ArcTrack(w.healthArc, false); ArcTrack(w.powerArc, false)
    w.coreCd:Hide()
    w.wipeLive = false
    for _, tex in ipairs(w.wipe) do tex:Hide() end
    w.coreKey = nil
    w.flashUntil, w.flashText = nil, nil
    w.flash:Hide(); w.glow:Hide(); w.alert:Hide()
    w.glowLive = false
    for _, t in pairs(w.ticks) do t:Hide() end
    for _, p in ipairs(w.pips) do p:Hide() end
    w.raid:Hide(); w.healer:Hide(); w.classBadge:Hide()
    w.trinket:Hide(); w.youRing:Hide()
    R.SetDead(w, false)
    w.arrowL:Hide(); w.arrowR:Hide()
    for _, f in ipairs(w.drIcons or {}) do f:Hide() end
    w.centerText:Hide(); w.drBadge:Hide(); w.levelText:Hide()
    w.shade:Hide()
    w.nameText:Hide(); w.castText:Hide()
    w:SetScript("OnUpdate", nil)
    w:Hide()
end
