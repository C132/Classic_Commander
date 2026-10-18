-- Commander Party Frames: the dial brush.
--
-- Your own upkeep -- Ice Barrier, Mana Shield, the wards, the Water Elemental
-- -- used to be a row each above the ally board: a name, a bar, a number, a
-- clock. Four shields was four rows, most of them an empty bar under a name
-- for most of a fight, and the block stood taller than the party it sat on.
--
-- This is the same information in the language the radial nameplates speak
-- (Commander_Plates/CommanderPlatesRadial.lua), where a unit is a disc rather
-- than a bar with things stacked beside it:
--
--      .-- time left (thin, outermost) --.
--     |  .-- absorb left (the band) --.   |
--     |  |        THE SPELL           |   |     the face is the spell's own
--     |  |   and the number on it     |   |     icon; dark when it is down,
--     |  '----------------------------'   |     wiped like a clock while it
--      '----------------------------------'     is on cooldown
--
-- so a shield is one disc, four shields are four discs on ONE line, and what
-- is not up is a dark face rather than an empty bar with its name still
-- written beside it.
--
-- Everything here is a brush, exactly as it is over there: it builds or
-- paints one widget from the values it is handed and never reads a unit or a
-- setting. CommanderPartyFrames.lua decides what a shield's state MEANS and
-- hands the answer over as a model.
--
-- Every arc is a Cooldown frame with a donut for its swipe texture, which the
-- client masks radially -- a real arc it draws for free. The clock is a
-- genuine cooldown the client animates; the absorb is a FROZEN one, a very
-- long cooldown started so the swipe sits at the fraction and re-set before
-- it has moved a thousandth of the way round. The ring and mask art is the
-- radial plate's own, copied so that neither addon needs the other.

CommanderPartyFrames_Dial = CommanderPartyFrames_Dial or {}
local D = CommanderPartyFrames_Dial

local TEX = "Interface\\AddOns\\Commander_PartyFrames\\Textures\\"
D.RING = TEX .. "DialRing.png"              -- the absorb band, flat
-- The band in each of the board's bar styles (Harness/make_dials.py): the
-- same donut with that style's shading wrapped across its thickness, lit from
-- the outer edge. White art, so the shield's colour multiplies through it --
-- a Blizzard band is a status bar bent round a face, not a block of colour.
D.BANDS = {
    FLAT = D.RING,
    BLIZZARD = TEX .. "DialRingBlizzard.png",
    GLOSS = TEX .. "DialRingGloss.png",
    BEVEL = TEX .. "DialRingBevel.png",
    RIDGE = TEX .. "DialRingRidge.png",
    GLASS = TEX .. "DialRingGlass.png",
}
D.RING_THIN = TEX .. "DialRingThin.png"     -- the clock, and the rim
D.MASK = TEX .. "DialMask.png"
-- Thickness is baked into the art as inner radius over outer radius
D.RING_RATIO, D.THIN_RATIO = 0.71, 0.88
local RING_OUTER = 0.485     -- a donut's outer radius over its texture's width
local STATIC = 86400         -- a frozen arc is a cooldown at most this long
local DRIFT = 0.001          -- ...re-set once it could have moved this share of a turn
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local WHITE = "Interface\\Buttons\\WHITE8X8"

-- Where each part of a dial of this diameter sits. Pure arithmetic, so the
-- harness can hold the layout to it without a client.
function D.Radii(size)
    local outer = size / 2
    local timeBand = outer * (1 - D.THIN_RATIO)
    local absorb = outer - timeBand - 0.5
    local absorbBand = absorb * (1 - D.RING_RATIO)
    local core = absorb - absorbBand - 0.5
    return {
        outer = outer, timeBand = timeBand,
        absorb = absorb, absorbBand = absorbBand,
        core = core,
    }
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
    -- draws a line straight across the face
    if cd.SetDrawEdge then cd:SetDrawEdge(false) end
    if texture and cd.SetSwipeTexture then cd:SetSwipeTexture(texture) end
    -- OmniCC and its kin write a countdown on every Cooldown they can find;
    -- an absorb arc a day long would read "23h"
    cd.noCooldownCount = true
    cd.noOCC = true
    cd:Hide()
    return cd
end

local function Masked(owner, tex)
    if not (owner.CreateMaskTexture and tex.AddMaskTexture) then return false end
    return pcall(function()
        local mask = owner:CreateMaskTexture()
        mask:SetTexture(D.MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(tex)
        tex:AddMaskTexture(mask)
    end) == true
end

-- An arc: the dim full circle it runs round, the sweep, and a plain texture
-- for a FULL arc (a cooldown at 100% is a finished one, and hides itself)
local function NewArc(w, level, file)
    local arc = { file = file }
    arc.track = w:CreateTexture(nil, "BACKGROUND", nil, 2)
    arc.track:SetTexture(file)
    arc.track:SetPoint("CENTER", w, "CENTER")
    arc.track:SetVertexColor(0.16, 0.17, 0.20, 0.9)
    arc.cd = NewSweep(w, level, file)
    arc.cd:SetPoint("CENTER", w, "CENTER")
    arc.fullFrame = CreateFrame("Frame", nil, w)
    arc.fullFrame:SetFrameLevel(level)
    arc.fullFrame:SetAllPoints(w)
    arc.full = arc.fullFrame:CreateTexture(nil, "ARTWORK")
    arc.full:SetTexture(file)
    arc.full:SetPoint("CENTER", w, "CENTER")
    arc.full:Hide()
    return arc
end

function D.New(parent)
    local w = CreateFrame("Frame", nil, parent)
    w:SetSize(1, 1)
    w:EnableMouse(false)
    local base = ((parent.GetFrameLevel and parent:GetFrameLevel()) or 1) + 1
    w:SetFrameLevel(base)
    w.dial = true

    -- The floor: one dark disc under the whole dial, so it reads the same
    -- over snow, over lava, and over whichever Frame Style is behind it
    w.backing = w:CreateTexture(nil, "BACKGROUND", nil, -6)
    w.backing:SetTexture(D.MASK)
    w.backing:SetPoint("CENTER", w, "CENTER")
    w.backing:SetVertexColor(0.03, 0.03, 0.04, 0.9)

    -- The face
    w.core = w:CreateTexture(nil, "BACKGROUND", nil, 1)
    w.core:SetPoint("CENTER", w, "CENTER")
    w.coreMasked = Masked(w, w.core)

    -- The shade: the face darkened while a number is written across it. A
    -- white 1.1k over Ice Barrier's white-blue icon has an outline and
    -- nothing inside it to tell from the picture; the shadow on the text
    -- holds its edges and this holds its middle. Above the face, below the
    -- wipe and every ring, and only up while a LIT face has text on it -- a
    -- dark one is already as dark as this would make it.
    w.shade = w:CreateTexture(nil, "BACKGROUND", nil, 2)
    w.shade:SetTexture(D.MASK)
    w.shade:SetPoint("CENTER", w, "CENTER")
    w.shade:Hide()

    -- The cooldown, as a clock wipe over the face. NOT reversed: a cooldown
    -- paints what REMAINS, so the dark wedge retreats as the spell comes back.
    w.wipe = NewSweep(w, base + 1, D.MASK)
    w.wipe:SetPoint("CENTER", w, "CENTER")
    if w.wipe.SetReverse then w.wipe:SetReverse(false) end
    if w.wipe.SetSwipeColor then w.wipe:SetSwipeColor(0, 0, 0, 0.7) end

    -- The arcs: the clock outermost, the absorb inside it
    w.time = NewArc(w, base + 2, D.RING_THIN)
    w.absorb = NewArc(w, base + 3, D.RING)

    -- Above the sweeps: everything a sweep must never cover
    local over = CreateFrame("Frame", nil, w)
    over:SetAllPoints(w)
    over:SetFrameLevel(base + 5)
    w.over = over
    -- The rim fills the pixel of air between the face and the band, and
    -- carries the state's colour when the state is one worth a colour
    w.rim = over:CreateTexture(nil, "ARTWORK", nil, 0)
    w.rim:SetTexture(D.RING_THIN)
    w.rim:SetPoint("CENTER", w, "CENTER")
    -- A planner mark riding the clock (the elemental's Freeze window)
    w.mark = over:CreateTexture(nil, "OVERLAY", nil, 3)
    w.mark:SetTexture(WHITE)
    w.mark:Hide()
    w.flash = over:CreateTexture(nil, "OVERLAY", nil, 6)
    w.flash:SetTexture(D.MASK)
    w.flash:SetBlendMode("ADD")
    w.flash:SetPoint("CENTER", w, "CENTER")
    w.flash:Hide()
    w.text = over:CreateFontString(nil, "OVERLAY")
    w.text:SetFont(FONT, 9, "OUTLINE")
    w.text:SetPoint("CENTER", w, "CENTER", 0, 0)
    -- A hard black shadow under the outline: at this size the outline alone
    -- is a hairline, and the picture behind it is as often white as not
    w.text:SetShadowColor(0, 0, 0, 1)
    w.text:SetShadowOffset(1, -1)

    -- A badge on the rim at four o'clock: a second spell that belongs to
    -- this dial's subject (Freeze, on the elemental), lit when it is ready
    -- and wiped while it is not
    w.badge = CreateFrame("Frame", nil, w)
    w.badge:SetFrameLevel(base + 6)
    w.badge.back = w.badge:CreateTexture(nil, "BACKGROUND")
    w.badge.back:SetTexture(D.MASK)
    w.badge.back:SetVertexColor(0, 0, 0, 1)
    w.badge.back:SetPoint("CENTER", w.badge, "CENTER")
    w.badge.icon = w.badge:CreateTexture(nil, "ARTWORK")
    w.badge.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    w.badge.icon:SetPoint("CENTER", w.badge, "CENTER")
    w.badge.masked = Masked(w.badge, w.badge.icon)
    w.badge.cd = NewSweep(w.badge, base + 7, D.MASK)
    w.badge.cd:SetPoint("CENTER", w.badge, "CENTER")
    if w.badge.cd.SetReverse then w.badge.cd:SetReverse(false) end
    if w.badge.cd.SetSwipeColor then w.badge.cd:SetSwipeColor(0, 0, 0, 0.7) end
    -- A count on the badge (Mending's charges), above its wipe
    local badgeOver = CreateFrame("Frame", nil, w.badge)
    badgeOver:SetAllPoints(w.badge)
    badgeOver:SetFrameLevel(base + 8)
    w.badge.text = badgeOver:CreateFontString(nil, "OVERLAY")
    w.badge.text:SetFont(FONT, 8, "OUTLINE")
    w.badge.text:SetPoint("CENTER", w.badge, "CENTER", 0, 0)
    w.badge.text:SetShadowColor(0, 0, 0, 1)
    w.badge.text:SetShadowOffset(1, -1)
    w.badge:Hide()

    w:Hide()
    return w
end

-- ---------------------------------------------------------------------------
-- Geometry, only when the size changed
-- ---------------------------------------------------------------------------
local function LayArc(arc, outer)
    local size = outer / RING_OUTER
    arc.track:SetSize(size, size)
    arc.cd:SetSize(size, size)
    arc.full:SetSize(size, size)
    arc.f, arc.setAt, arc.stop = nil, nil, nil
end

-- Which art the absorb band is drawn with. Only the FILL changes: the empty
-- track stays the plain donut, because a groove is not lit like a bar.
function D.SetBand(w, style)
    if w.band == style then return end
    w.band = style
    local file = D.BANDS[style] or D.RING
    local arc = w.absorb
    if arc.cd.SetSwipeTexture then arc.cd:SetSwipeTexture(file) end
    arc.full:SetTexture(file)
    -- A frozen arc is only re-set when its value moves; a new texture has to
    -- reach the one already standing
    arc.f, arc.setAt = nil, nil
end

-- `textSize` is the number's font size in points, or nil/0 to size it off
-- the dial.
function D.Layout(w, size, textSize)
    textSize = (textSize and textSize > 0) and textSize or nil
    if w.size == size and w.textSize == textSize then return end
    w.size, w.textSize = size, textSize
    local r = D.Radii(size)
    w.radii = r
    w:SetSize(size, size)
    w.backing:SetSize(size + 2, size + 2)

    local coreD = r.core * 2
    -- Unmasked, a square icon has to fit INSIDE the circle it stands in for
    local face = w.coreMasked and coreD or coreD * 0.7071
    w.core:SetSize(face, face)
    w.shade:SetSize(coreD, coreD)
    w.wipe:SetSize(coreD, coreD)
    w.wipeStop = nil

    LayArc(w.time, r.outer)
    LayArc(w.absorb, r.absorb)
    local rimOuter = r.core + 1.5
    w.rim:SetSize(rimOuter / RING_OUTER, rimOuter / RING_OUTER)
    w.flash:SetSize(size + 4, size + 4)

    local tick = math.max(2, math.floor(r.timeBand + 1.5))
    w.mark:SetSize(tick, tick)

    w.text:SetFont(FONT, textSize or math.max(8, math.min(12, math.floor(size * 0.34 + 0.5))), "OUTLINE")

    local badge = math.max(9, math.floor(size * 0.4 + 0.5))
    w.badge:SetSize(badge, badge)
    w.badge.back:SetSize(badge + 2, badge + 2)
    w.badge.size, w.badgeRimOn = badge, nil
    w.badge.text:SetFont(FONT, math.max(7, math.floor(badge * 0.62 + 0.5)), "OUTLINE")
    local badgeFace = w.badge.masked and badge or badge * 0.7071
    w.badge.icon:SetSize(badgeFace, badgeFace)
    w.badge.cd:SetSize(badge, badge)
    w.badge:ClearAllPoints()
    w.badge:SetPoint("CENTER", w, "CENTER", r.outer * 0.72, -r.outer * 0.72)
    w.badgeStop = nil
end

-- ---------------------------------------------------------------------------
-- Arcs
-- ---------------------------------------------------------------------------
local function ArcHide(arc)
    arc.cd:Hide()
    arc.full:Hide()
    arc.f, arc.stop = nil, nil
end

-- A frozen arc at `fraction`. It ENDS at twelve o'clock and starts
-- (1 - fraction) of the way round, so as the value drops its leading edge
-- walks clockwise toward twelve -- the empty part grows the way a clock hand
-- turns, which is the way the radial plate's health drains.
local function ArcSet(arc, fraction, r, g, b, now)
    if not fraction or fraction <= 0.002 then ArcHide(arc) return end
    arc.stop = nil
    if fraction >= 0.998 then
        arc.cd:Hide()
        arc.full:SetVertexColor(r, g, b, 1)
        arc.full:Show()
        arc.f = 1
        return
    end
    arc.full:Hide()
    local colour = r * 1e6 + g * 1e3 + b
    if arc.f and math.abs(arc.f - fraction) < 0.001 and arc.colour == colour
        and arc.setAt and now - arc.setAt < arc.span * DRIFT and arc.cd:IsShown() then
        return
    end
    -- GetTime counts from the machine's boot, and a start before zero is not
    -- something to hand the client: the cooldown is a day long only once the
    -- machine has been up a day
    local span = now < 60 and 60 or (now > STATIC and STATIC or now)
    arc.f, arc.colour, arc.setAt, arc.span = fraction, colour, now, span
    if arc.cd.SetReverse then arc.cd:SetReverse(false) end
    if arc.cd.SetSwipeColor then arc.cd:SetSwipeColor(r, g, b, 1) end
    arc.cd:SetCooldown(now - (1 - fraction) * span, span)
    arc.cd:Show()
end

-- A running arc: a real cooldown, started once and left to the client. The
-- stop time is what identifies it -- the model re-derives its start from
-- "seconds left" on every paint, which wobbles by a frame, and SetCooldown
-- restarts the animation each time it is called.
local function ArcRun(arc, stop, duration, r, g, b)
    if not stop or not duration or duration <= 0 then ArcHide(arc) return end
    arc.full:Hide()
    arc.f = nil
    if arc.stop and math.abs(arc.stop - stop) < 0.25 and arc.dur == duration
        and arc.cd:IsShown() then
        return
    end
    arc.stop, arc.dur = stop, duration
    if arc.cd.SetReverse then arc.cd:SetReverse(false) end
    if arc.cd.SetSwipeColor then arc.cd:SetSwipeColor(r, g, b, 1) end
    arc.cd:SetCooldown(stop - duration, duration)
    arc.cd:Show()
end

-- ---------------------------------------------------------------------------
-- Paint. `m` is the model:
--
--   icon                the face (a texture path)
--   coords              { l, r, t, b } of `icon` when it is one cell of an
--                       atlas (a class icon), else the icon's own crop
--   portrait            ...or a unit whose portrait is the face
--   portraitKey         who that portrait is (a GUID): it is drawn again
--                       only when this changes, or every couple of seconds
--   ghost               the face drained dark: this is not up
--   absorb              0..1 round the band, or nil for an empty track
--   absorbColor         { r, g, b }
--   timeStop, timeDur   the clock: when it ends, and how long it is in all
--   wipeStop, wipeDur   a cooldown wiped across the face
--   wipeColor           { r, g, b, a } of that wipe, else the black 0.7 of a
--                       cooldown (Team Shields draws Weakened Soul in red)
--   text, textColor     the number on the face
--   shade               0..1: how far a lit face darkens under that number
--   rim                 { r, g, b } for a state worth a colour, else nil
--   mark, markColor     a planner mark on the clock, as a fraction of it
--   badgeIcon           a second spell on the rim...
--   badgeStop, badgeDur ...and its cooldown
--   badgeText           a count on it (Mending's charges)
--   badgeRim            { r, g, b }: a coloured ring round it, else black
--   flash, flashColor   0..1 alert wash over the whole dial
--   alpha               the whole dial's opacity (out of range), else 1
-- ---------------------------------------------------------------------------
local PORTRAIT_EVERY = 2     -- a portrait re-read this often even unchanged

function D.Paint(w, m, now)
    -- The face. A portrait is a texture the client renders for us, which is
    -- not free, so it is drawn once per person rather than once per paint --
    -- and again every couple of seconds, since a portrait that has not loaded
    -- yet draws as a blank and loads later.
    if m.portrait and SetPortraitTexture then
        local key = m.portraitKey or m.portrait
        if w.portraitKey ~= key or not w.portraitAt or now - w.portraitAt > PORTRAIT_EVERY then
            SetPortraitTexture(w.core, m.portrait)
            w.portraitKey, w.portraitAt = key, now
        end
        w.core:SetTexCoord(0.12, 0.88, 0.12, 0.88)
    else
        w.portraitKey, w.portraitAt = nil, nil
        w.core:SetTexture(m.icon)
        local c = m.coords
        if c then
            -- One cell of an atlas: pulled in a little so the cell's own
            -- border does not ring the disc
            local inX, inY = (c[2] - c[1]) * 0.06, (c[4] - c[3]) * 0.06
            w.core:SetTexCoord(c[1] + inX, c[2] - inX, c[3] + inY, c[4] - inY)
        else
            w.core:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end
    if w.core.SetDesaturated then w.core:SetDesaturated(m.ghost and true or false) end
    if m.ghost then
        w.core:SetVertexColor(0.34, 0.34, 0.38, 1)
    else
        w.core:SetVertexColor(1, 1, 1, 1)
    end
    w.ghost = m.ghost and true or false

    -- The cooldown across it, in its own colour when it has one
    local wc = m.wipeColor
    local wkey = wc and (wc[1] * 1e9 + wc[2] * 1e6 + wc[3] * 1e3 + (wc[4] or 1)) or 0
    if w.wipeColorKey ~= wkey then
        w.wipeColorKey = wkey
        if w.wipe.SetSwipeColor then
            if wc then
                w.wipe:SetSwipeColor(wc[1], wc[2], wc[3], wc[4] or 0.75)
            else
                w.wipe:SetSwipeColor(0, 0, 0, 0.7)
            end
        end
    end
    if m.wipeStop and m.wipeDur and m.wipeDur > 0 and m.wipeStop > now then
        if not (w.wipeStop and math.abs(w.wipeStop - m.wipeStop) < 0.25 and w.wipe:IsShown()) then
            w.wipeStop = m.wipeStop
            w.wipe:SetCooldown(m.wipeStop - m.wipeDur, m.wipeDur)
            w.wipe:Show()
        end
    else
        w.wipeStop = nil
        w.wipe:Hide()
    end

    -- The band and the clock
    local c = m.absorbColor
    ArcSet(w.absorb, m.absorb, c and c[1] or 0.4, c and c[2] or 0.78, c and c[3] or 1, now)
    if m.timeStop and m.timeStop > now then
        ArcRun(w.time, m.timeStop, m.timeDur, 0.86, 0.88, 0.92)
    else
        ArcHide(w.time)
    end

    local rim = m.rim
    if rim then
        w.rim:SetVertexColor(rim[1], rim[2], rim[3], 1)
    else
        w.rim:SetVertexColor(0, 0, 0, 1)
    end
    w.rimColor = rim

    -- The number, and the floor under it
    if m.shade and m.shade > 0 and m.text and m.text ~= "" and not m.ghost then
        w.shade:SetVertexColor(0, 0, 0, m.shade)
        w.shade:Show()
    else
        w.shade:Hide()
    end
    w.text:SetText(m.text or "")
    local tc = m.textColor
    w.text:SetTextColor(tc and tc[1] or 1, tc and tc[2] or 1, tc and tc[3] or 1)

    -- The planner mark: where the clock's leading edge will be at that
    -- moment. The clock ends at twelve and its edge walks clockwise, so a
    -- fraction f of it remaining puts the edge (1 - f) of a turn round.
    if m.mark and m.mark > 0 and m.mark < 1 and w.radii then
        local angle = (1 - m.mark) * 2 * math.pi
        local radius = w.radii.outer - w.radii.timeBand / 2
        w.mark:ClearAllPoints()
        w.mark:SetPoint("CENTER", w, "CENTER", radius * math.sin(angle), radius * math.cos(angle))
        local mc = m.markColor
        w.mark:SetVertexColor(mc and mc[1] or 1, mc and mc[2] or 0.82, mc and mc[3] or 0.2, 1)
        w.mark:Show()
        w.markAt = m.mark
    else
        w.mark:Hide()
        w.markAt = nil
    end

    -- The badge
    if m.badgeIcon then
        w.badge.icon:SetTexture(m.badgeIcon)
        local cooling = m.badgeStop and m.badgeDur and m.badgeDur > 0 and m.badgeStop > now
        if w.badge.icon.SetDesaturated then w.badge.icon:SetDesaturated(cooling and true or false) end
        if cooling then
            if not (w.badgeStop and math.abs(w.badgeStop - m.badgeStop) < 0.25
                    and w.badge.cd:IsShown()) then
                w.badgeStop = m.badgeStop
                w.badge.cd:SetCooldown(m.badgeStop - m.badgeDur, m.badgeDur)
                w.badge.cd:Show()
            end
        else
            w.badgeStop = nil
            w.badge.cd:Hide()
        end
        w.badge.text:SetText(m.badgeText or "")
        -- The ring: the badge's black floor grown by a pixel each side and
        -- tinted, so it reads as an edge rather than as a second disc
        local br = m.badgeRim
        local size = w.badge.size or 9
        if br then
            w.badge.back:SetVertexColor(br[1], br[2], br[3], 1)
            if not w.badgeRimOn then w.badge.back:SetSize(size + 4, size + 4) end
            w.badgeRimOn = true
        else
            w.badge.back:SetVertexColor(0, 0, 0, 1)
            if w.badgeRimOn ~= false then w.badge.back:SetSize(size + 2, size + 2) end
            w.badgeRimOn = false
        end
        w.badge:Show()
    else
        w.badgeStop = nil
        w.badge:Hide()
    end

    local alpha = m.alpha or 1
    if w.alphaAt ~= alpha then
        w.alphaAt = alpha
        w:SetAlpha(alpha)
    end

    -- The alert
    if m.flash and m.flash > 0 then
        local fc = m.flashColor
        w.flash:SetVertexColor(fc and fc[1] or 1, fc and fc[2] or 0.2, fc and fc[3] or 0.2)
        w.flash:SetAlpha(0.6 * m.flash)
        w.flash:Show()
    else
        w.flash:Hide()
    end
end
