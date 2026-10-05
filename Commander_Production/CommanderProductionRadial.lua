-- Commander Production: the radial disc's brushes.
--
-- The treatment Commander Plates gives a nameplate, given to a cooldown.
-- Instead of an icon with a bar under it, each entry in the queue is a disc:
--
--      .-- cooldown ring --.      full when the cooldown starts, draining
--     |   .-- FACE ---.    |      clockwise to empty the moment it is back,
--     |   |  the spell |   |      with a spark riding its head
--     |   '-----------'    |
--      '-------------------'      the countdown is written across the face
--
-- all of it on a dark backdrop, so it reads against snow and against a black
-- cave alike. A finished cooldown that lingers lights its ring green, closes
-- it, and raises a glow behind the disc.
--
-- Everything here is a brush: it builds or paints one disc from values it is
-- handed and never reads a spell. The ring is a Cooldown frame with a donut
-- as its swipe texture -- the client masks the donut radially, which is a
-- real arc it animates for free (see the suite's API notes) -- so a disc
-- costs nothing per frame beyond its spark.
--
-- Angles run the way the client's own Cooldown sweep runs: CLOCKWISE FROM
-- TWELVE O'CLOCK. The ring ENDS at twelve, so as the cooldown runs its edge
-- walks clockwise toward it.

CommanderProduction_Radial = CommanderProduction_Radial or {}
local R = CommanderProduction_Radial

local TEX = "Interface\\AddOns\\Commander_Production\\Textures\\"
-- The art is Commander Plates' (Harness/copy_radial_art.py copies it, and the
-- smoke diffs the copies) so neither addon needs the other. Six ring weights,
-- thinnest first, thickness baked in as inner radius over outer radius.
R.RING_FILES = {
    TEX .. "Ring1.png", TEX .. "Ring2.png", TEX .. "Ring3.png",
    TEX .. "Ring4.png", TEX .. "Ring5.png", TEX .. "Ring6.png",
}
R.RING_RATIOS = { 0.93, 0.88, 0.80, 0.71, 0.60, 0.46 }
R.RING_OUTER = 0.485         -- the donut's outer radius over the texture's width
-- Every glow rises from GLOW_BASE of its width -- the disc's edge -- and is
-- fully transparent well inside its own border, so all of them are safe to spin
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
R.EDGE_FILE = TEX .. "Edge.png"
R.MASK_FILE = TEX .. "CircleMask.png"
-- The clock wipe's halves; the disc in them is WIPE_RADIUS of the texture's
-- width, inside a transparent margin
R.HALF_RIGHT = TEX .. "HalfRight.png"
R.HALF_LEFT = TEX .. "HalfLeft.png"
R.FLASH_TIME = 0.6           -- how long the burst on a finished cooldown lasts
local WIPE_RADIUS = 0.46
local GLOW_BASE = 0.28       -- where every glow rises from, over its width
local SPIN_RATE = 0.5        -- radians a second, for the turning glows
local EDGE_CORE = 0.30       -- half-length of the spark's flat core over its width
local ICON_INSET = 0.08
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

-- ---------------------------------------------------------------------------
-- Geometry, with no client attached
-- ---------------------------------------------------------------------------

-- A point on a circle, fraction of the way round clockwise from twelve.
-- Returns x, y (y up, the client's convention) and the angle in radians,
-- which is also what Texture:SetRotation wants negated.
function R.ArcPoint(radius, fraction)
    local theta = (fraction or 0) * math.pi * 2
    return math.sin(theta) * radius, math.cos(theta) * radius, theta
end

-- For a band `thickness` pixels thick with its outer edge at `outer`, the
-- nearest of the six ring weights
function R.RingWeight(outer, thickness)
    if not outer or outer <= 0 then return 3 end
    local wanted = 1 - (thickness or 0) / outer
    local best, bestDiff = 1, math.huge
    for i = 1, #R.RING_RATIOS do
        local diff = math.abs(R.RING_RATIOS[i] - wanted)
        if diff < bestDiff then best, bestDiff = i, diff end
    end
    return best
end

-- The masked clock wipe over the face: the fraction of the cooldown that
-- REMAINS stays dark, and what has elapsed is clear -- a wedge opening
-- clockwise from twelve, its edge at the same angle as the ring's. It is
-- drawn with two copies of a left-half disc -- the first clipped to the left
-- half of the face, the second to the right -- each turned COUNTERCLOCKWISE
-- by the degrees returned. With nothing remaining both are turned out of
-- their clips; at a half the left one fills its half; at all of it both do.
function R.WipeAngles(remaining)
    if not remaining or remaining < 0 then remaining = 0 elseif remaining > 1 then remaining = 1 end
    return math.min(remaining, 0.5) * 360 - 180, math.max(remaining, 0.5) * 360 - 180
end

-- The settings, read once per draw into one reused table. The radii run from
-- the middle out: the face, a pixel of air, the ring, and the backdrop past
-- it. `cell` is the square a disc needs in the queue's grid. The signature
-- covers everything Layout applies; what is painted per draw is left out.
function R.Config(db, cfg)
    cfg = cfg or {}
    cfg.size = db.RadialSize or 40
    cfg.thick = db.RadialThickness or 4
    cfg.trackAlpha = db.RadialTrackAlpha or 0.35
    cfg.spark = db.RadialSpark ~= false
    cfg.countdown = db.RadialCountdown ~= false
    cfg.textShade = db.RadialTextShade or 0.45
    cfg.wipe = db.RadialWipe == true
    cfg.backdropAlpha = db.RadialBackdropAlpha or 0.6
    cfg.backdropPad = db.RadialBackdropSize or 2
    cfg.backdropBorder = db.RadialBackdropBorder ~= false
    cfg.glowStyle = db.RadialGlowStyle or "SOFT"
    cfg.glowScale = db.RadialGlowSize or 1
    cfg.glowMotion = db.RadialGlowMotion or "NONE"
    cfg.flash = db.RadialReadyFlash ~= false

    cfg.outer = cfg.size / 2
    cfg.core = math.max(4, cfg.outer - cfg.thick - 1)
    -- How far past the ring the backdrop reaches (negative pulls it in, never
    -- smaller than the face it sits behind)
    cfg.backdropRadius = cfg.backdropAlpha > 0
        and math.max(cfg.core + 1, cfg.outer + cfg.backdropPad) or nil
    cfg.edge = math.max(cfg.outer, cfg.backdropRadius or 0)
    cfg.cell = cfg.edge * 2
    cfg.signature = string.format("%s|%s|%.2f|%.2f|%.2f|%s|%s|%s|%.2f",
        cfg.size, cfg.thick, cfg.trackAlpha, cfg.textShade, cfg.backdropAlpha,
        cfg.backdropPad, tostring(cfg.backdropBorder), cfg.glowStyle, cfg.glowScale)
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
    -- draws a line straight across the face. The ring has its own spark.
    if cd.SetDrawEdge then cd:SetDrawEdge(false) end
    if texture and cd.SetSwipeTexture then cd:SetSwipeTexture(texture) end
    -- OmniCC and its kin write a countdown on every Cooldown they can find;
    -- the disc writes its own
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

local function NewGlow(owner, anchor, layer, sub)
    local tex = owner:CreateTexture(nil, layer, nil, sub)
    tex:SetTexture(R.GLOW_FILE)
    tex:SetBlendMode("ADD")
    tex:SetPoint("CENTER", anchor, "CENTER")
    tex:Hide()
    return tex
end

-- `parent` is the queue row the disc stands in for
function R.New(parent)
    local w = CreateFrame("Frame", nil, parent)
    w:SetSize(1, 1)
    w:SetPoint("CENTER", parent, "CENTER")
    w:EnableMouse(false)
    local base = ((parent.GetFrameLevel and parent:GetFrameLevel()) or 1) + 1
    w:SetFrameLevel(base)

    -- The READY glow is drawn on the ROW, a level below every disc in the
    -- queue: it reaches well past its own disc, and must light the gap
    -- between neighbours without washing over their faces
    w.glow = NewGlow(parent, w, "BACKGROUND", -8)

    -- The backdrop the whole disc sits on, and a thin rim round its edge
    w.backdrop = w:CreateTexture(nil, "BACKGROUND", nil, -6)
    w.backdrop:SetTexture(R.MASK_FILE)
    w.backdrop:SetPoint("CENTER", w, "CENTER")
    w.backdropRim = w:CreateTexture(nil, "BACKGROUND", nil, -5)
    w.backdropRim:SetTexture(R.RING_FILES[2])
    w.backdropRim:SetPoint("CENTER", w, "CENTER")
    w.coreBg = w:CreateTexture(nil, "BACKGROUND", nil, 0)
    w.coreBg:SetTexture(R.MASK_FILE)
    w.coreBg:SetVertexColor(0, 0, 0, 0.85)
    w.coreBg:SetPoint("CENTER", w, "CENTER")

    -- The face: the spell's icon, cut round. Sublevel 2 is left free for the
    -- suite's icon recess, which lays itself one above whatever it shades.
    w.core = w:CreateTexture(nil, "BACKGROUND", nil, 1)
    w.core:SetPoint("CENTER", w, "CENTER")
    w.core:SetTexCoord(ICON_INSET, 1 - ICON_INSET, ICON_INSET, 1 - ICON_INSET)
    w.coreMasked = Masked(w, w.core)

    -- The clock wipe over the face, CLIPPED to it: two half discs, each
    -- masked to its own half of the face and turned to the cooldown
    -- (R.WipeAngles). A Cooldown's swipe cannot take a mask, and an unmasked
    -- one is free to paint past the face onto the ring.
    w.wipe = {}
    for i, clip in ipairs({ R.HALF_LEFT, R.HALF_RIGHT }) do
        local tex = w:CreateTexture(nil, "BACKGROUND", nil, 3)
        tex:SetTexture(R.HALF_LEFT)
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

    -- The shade: the face darkened while the countdown is written across it.
    -- The shadow on the text holds its edges; this is what holds its MIDDLE
    -- over a white-gold icon. Only ever up while there is a number to read.
    w.shade = w:CreateTexture(nil, "BACKGROUND", nil, 4)
    w.shade:SetTexture(R.MASK_FILE)
    w.shade:SetPoint("CENTER", w, "CENTER")
    w.shade:Hide()

    -- The ring: the dim full circle it runs round, the sweep, and a plain
    -- texture for a FULL ring (a cooldown at its end is a finished one, and
    -- hides itself) -- which is what a READY entry wears
    local arc = {}
    arc.track = w:CreateTexture(nil, "BACKGROUND", nil, 5)
    arc.track:SetPoint("CENTER", w, "CENTER")
    arc.cd = NewSweep(w, base + 2)
    arc.cd:SetPoint("CENTER", w, "CENTER")
    arc.fullFrame = CreateFrame("Frame", nil, w)
    arc.fullFrame:SetFrameLevel(base + 2)
    arc.fullFrame:SetAllPoints(w)
    arc.full = arc.fullFrame:CreateTexture(nil, "ARTWORK")
    arc.full:SetPoint("CENTER", w, "CENTER")
    arc.full:Hide()
    w.arc = arc

    -- The wipe's fallback for a client with no masks: a Cooldown, kept BELOW
    -- the ring so that even unclipped it can only ever darken the face
    w.coreCd = NewSweep(w, base + 1, R.MASK_FILE)
    w.coreCd:SetPoint("CENTER", w, "CENTER")
    if w.coreCd.SetSwipeColor then w.coreCd:SetSwipeColor(0, 0, 0, 0.6) end

    -- Above the sweeps: everything a sweep must never cover
    local over = CreateFrame("Frame", nil, w)
    over:SetAllPoints(w)
    over:SetFrameLevel(base + 4)
    w.over = over
    -- The rim fills the pixel of air between the face and the ring
    w.rim = over:CreateTexture(nil, "ARTWORK", nil, 0)
    w.rim:SetTexture(R.RING_FILES[1])
    w.rim:SetVertexColor(0, 0, 0, 1)
    w.rim:SetPoint("CENTER", w, "CENTER")
    w.spark = over:CreateTexture(nil, "OVERLAY", nil, 4)
    w.spark:SetTexture(R.EDGE_FILE)
    w.spark:SetBlendMode("ADD")
    w.spark:Hide()
    w.flash = NewGlow(over, w, "OVERLAY", 6)

    -- Written over a spell's icon, which is as often white as it is dark: an
    -- outline, and a hard black shadow under it to double the dark edge
    w.text = over:CreateFontString(nil, "OVERLAY")
    w.text:SetFont(FONT, 11, "OUTLINE")
    if w.text.SetShadowColor then w.text:SetShadowColor(0, 0, 0, 1) end
    if w.text.SetShadowOffset then w.text:SetShadowOffset(1, -1) end
    w.text:SetPoint("CENTER", w, "CENTER", 0, 0)
    w.text:Hide()

    w:SetScript("OnUpdate", nil)
    w:Hide()
    return w
end

-- ---------------------------------------------------------------------------
-- Geometry, only when a number it depends on changed
-- ---------------------------------------------------------------------------
function R.Layout(w, cfg)
    if w.laid == cfg.signature then return end
    w.laid = cfg.signature
    w:SetSize(cfg.cell, cfg.cell)

    local coreD = cfg.core * 2
    w.coreBg:SetSize(coreD + 2, coreD + 2)
    -- Unmasked, the icon stays a square: the largest one the face holds
    local coreSize = w.coreMasked and coreD or coreD * 0.7071
    w.core:SetSize(coreSize, coreSize)
    w.coreCd:SetSize(coreSize, coreSize)
    w.shade:SetSize(coreD, coreD)
    w.shadeAlpha = cfg.textShade
    w.shade:SetVertexColor(0, 0, 0, cfg.textShade)
    if cfg.textShade <= 0 then w.shade:Hide() end
    local wipeSize = (coreSize / 2) / WIPE_RADIUS
    for _, tex in ipairs(w.wipe) do
        tex:SetSize(wipeSize, wipeSize)
        if tex.clip then tex.clip:SetSize(wipeSize, wipeSize) end
    end

    if cfg.backdropRadius then
        local backR = cfg.backdropRadius
        w.backdrop:SetSize(backR * 2, backR * 2)
        w.backdrop:SetVertexColor(0.04, 0.04, 0.05, cfg.backdropAlpha)
        w.backdrop:Show()
        w.backdropRim:SetSize((backR + 1) / R.RING_OUTER, (backR + 1) / R.RING_OUTER)
        w.backdropRim:SetVertexColor(0, 0, 0, math.min(1, cfg.backdropAlpha + 0.3))
        w.backdropRim:SetShown(cfg.backdropBorder)
    else
        w.backdrop:Hide()
        w.backdropRim:Hide()
    end
    local rimOuter = cfg.core + 1.5
    w.rim:SetSize(rimOuter / R.RING_OUTER, rimOuter / R.RING_OUTER)

    local arc = w.arc
    local index = R.RingWeight(cfg.outer, cfg.thick)
    local file, ratio = R.RING_FILES[index], R.RING_RATIOS[index]
    local size = cfg.outer / R.RING_OUTER
    arc.track:SetTexture(file)
    arc.track:SetSize(size, size)
    arc.track:SetVertexColor(0.05, 0.05, 0.07, cfg.trackAlpha)
    arc.track:SetShown(cfg.trackAlpha > 0)
    arc.cd:SetSize(size, size)
    if arc.cd.SetSwipeTexture then arc.cd:SetSwipeTexture(file) end
    arc.full:SetTexture(file)
    arc.full:SetSize(size, size)
    -- What the band on screen measures -- the nearest of six weights, rarely
    -- the requested pixel count -- so the spark riding it measures, not trusts
    arc.band = cfg.outer * (1 - ratio)
    arc.radius = cfg.outer - arc.band / 2

    -- Every glow rises from the disc's visible edge: the backdrop's when
    -- there is one, else the ring's
    local glowSize = (cfg.edge + 1) / GLOW_BASE
    w.glow:SetTexture(R.GLOW_STYLES[cfg.glowStyle] or R.GLOW_FILE)
    w.glow:SetSize(glowSize * cfg.glowScale, glowSize * cfg.glowScale)
    w.flash:SetSize(glowSize * 1.12, glowSize * 1.12)

    local sparkSize = arc.band / (EDGE_CORE * 2)
    w.spark:SetSize(sparkSize, sparkSize)
    w.text:SetFont(FONT, math.max(8, math.floor(cfg.core * 0.85)), "OUTLINE")
end

-- ---------------------------------------------------------------------------
-- The animation clock: the spark, the face wipe, the ready flash, a glow in
-- motion. Only runs while one of them is live.
-- ---------------------------------------------------------------------------
local function Animating(w)
    return w.sparkLive or w.wipeLive or w.flashUntil or w.glowLive
end

local function Elapsed(w, now)
    local p = (now - w.cdStart) / w.cdDuration
    if p < 0 then return 0 elseif p > 1 then return 1 end
    return p
end

local function MoveSpark(w, now)
    local x, y, theta = R.ArcPoint(w.arc.radius or 0, Elapsed(w, now))
    w.spark:ClearAllPoints()
    w.spark:SetPoint("CENTER", w, "CENTER", x, y)
    if w.spark.SetRotation then w.spark:SetRotation(-theta) end
end

local function PaintWipe(w, now)
    local remaining = 1 - Elapsed(w, now)
    local a1, a2 = R.WipeAngles(remaining)
    if w.wipe[1].SetRotation then
        w.wipe[1]:SetRotation(math.rad(a1))
        w.wipe[2]:SetRotation(math.rad(a2))
    end
    -- Under a half, the second copy is turned wholly out of its clip -- but
    -- its straight edge still lies along the clip's, and two antialiased
    -- edges meeting leave a hairline down the face. Hidden, there is none.
    local second = remaining > 0.5
    if w.wipeSecond ~= second then
        w.wipeSecond = second
        w.wipe[2]:SetShown(second)
    end
end

local function OnUpdate(w)
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
    if w.wipeLive then PaintWipe(w, now) end
    if w.flashUntil then
        local left = w.flashUntil - now
        if left <= 0 then
            w.flashUntil = nil
            w.flash:Hide()
        else
            w.flash:SetAlpha(left / R.FLASH_TIME)
        end
    end
    if not Animating(w) then w:SetScript("OnUpdate", nil) end
end

local function Animate(w)
    if Animating(w) and not w:GetScript("OnUpdate") then w:SetScript("OnUpdate", OnUpdate) end
end

-- ---------------------------------------------------------------------------
-- Painting. Each takes plain values; none reads a spell. The queue repaints
-- every disc ten times a second and hands a row a different entry whenever
-- the order changes, so every one of these is cheap when nothing moved and
-- right whatever the disc was showing before.
-- ---------------------------------------------------------------------------

function R.SetIcon(w, texture)
    if w.icon == texture then return end
    w.icon = texture
    w.core:SetTexture(texture)
end

local function SetGlow(w, shown, r, g, b, motion)
    if not shown then
        if w.glowShown then
            w.glowShown, w.glowLive = false, false
            w.glow:Hide()
        end
        return
    end
    if w.glowShown and w.glowMotion == motion then return end
    w.glowShown, w.glowMotion = true, motion
    w.glow:SetVertexColor(r, g, b, 0.8)
    w.glow:SetAlpha(1)
    if w.glow.SetRotation then w.glow:SetRotation(0) end
    w.glow:Show()
    w.glowLive = motion ~= "NONE"
end

local function WipeOff(w)
    if w.wipeLive then
        w.wipeLive = false
        for _, tex in ipairs(w.wipe) do tex:Hide() end
    end
    if w.wipeCd then
        w.wipeCd = false
        w.coreCd:Hide()
    end
end

-- A cooldown on its way back: the client animates the ring; the spark and
-- the wipe are ours
function R.SetPending(w, cfg, start, duration, r, g, b)
    local arc = w.arc
    local fresh = w.cdStart ~= start or w.cdDuration ~= duration
    if fresh then
        w.cdStart, w.cdDuration, w.readyAt = start, duration, nil
        arc.full:Hide()
        if arc.cd.SetSwipeColor then arc.cd:SetSwipeColor(r, g, b, 1) end
        arc.cd:SetCooldown(start, duration)
        arc.cd:Show()
        w.spark:SetVertexColor((r + 1) / 2, (g + 1) / 2, (b + 1) / 2)
        SetGlow(w, false)
    end
    if cfg.spark then
        if not w.sparkLive or fresh then
            w.sparkLive = true
            w.spark:Show()
            MoveSpark(w, GetTime())
        end
    elseif w.sparkLive then
        w.sparkLive = false
        w.spark:Hide()
    end
    if not cfg.wipe then
        WipeOff(w)
    elseif w.wipeMasked then
        if not w.wipeLive or fresh then
            w.wipeLive, w.wipeSecond = true, nil
            w.wipe[1]:Show()
            PaintWipe(w, GetTime())
        end
    elseif not w.wipeCd or fresh then
        w.wipeCd = true
        w.coreCd:SetCooldown(start, duration)
        w.coreCd:Show()
    end
    Animate(w)
end

-- A finished cooldown lingering on the queue: the ring closed in the ready
-- colour, a glow behind the disc, and a burst the moment it came back
function R.SetReady(w, cfg, readyAt, r, g, b)
    if w.readyAt ~= readyAt then
        w.readyAt = readyAt
        w.cdStart, w.cdDuration = nil, nil
        local arc = w.arc
        arc.cd:Hide()
        arc.full:SetVertexColor(r, g, b, 1)
        arc.full:Show()
        if w.sparkLive then
            w.sparkLive = false
            w.spark:Hide()
        end
        WipeOff(w)
        if cfg.flash and GetTime() < readyAt + R.FLASH_TIME then
            w.flash:SetVertexColor(r, g, b, 1)
            w.flash:SetAlpha(1)
            w.flash:Show()
            w.flashUntil = readyAt + R.FLASH_TIME
        end
    end
    SetGlow(w, cfg.glowStyle ~= "OFF", r, g, b, cfg.glowMotion)
    Animate(w)
end

-- The countdown across the face; nil takes it (and the shade under it) off
function R.SetCountdown(w, text)
    if not text or text == "" then
        w.text:Hide()
        w.shade:Hide()
        return
    end
    w.text:SetText(text)
    w.text:Show()
    w.shade:SetShown((w.shadeAlpha or 0) > 0)
end

-- Everything off: the queue has gone back to bars or to plain icons
function R.Clear(w)
    w.cdStart, w.cdDuration, w.readyAt = nil, nil, nil
    w.arc.cd:Hide()
    w.arc.full:Hide()
    w.sparkLive = false
    w.spark:Hide()
    WipeOff(w)
    SetGlow(w, false)
    w.flashUntil = nil
    w.flash:Hide()
    w.text:Hide()
    w.shade:Hide()
    w:SetScript("OnUpdate", nil)
    w:Hide()
end
