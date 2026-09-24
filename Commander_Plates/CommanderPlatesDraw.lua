-- Commander Plates: the brushes.
--
-- Everything here draws with WHITE8X8 quads and gradients, never with an art
-- file: a tinted quad renders identically on every client build, tints to
-- any colour, and -- the reason this is its own file -- can be drawn on the
-- settings page as well as on a plate. The previews inline in the options
-- use exactly these functions, so what the page shows is what the plate does.
--
-- Two shapes:
--   RING   four hard quads around a frame -- the "outline" style
--   HALO   four gradient quads fading outward plus four soft corners -- a
--          real glow, blurred by the gradient rather than by an art file
--
-- Plus ResolveColor, which turns the palette keys a dropdown offers (WHITE,
-- RED, ..., CLASS, REACTION) into rgb for a given unit.

CommanderPlates_Draw = CommanderPlates_Draw or {}
local Draw = CommanderPlates_Draw
local DATA = CommanderPlates_Data

local WHITE = "Interface\\Buttons\\WHITE8X8"
Draw.WHITE = WHITE

local SIDES = { "top", "bottom", "left", "right" }
local CORNERS = { "tl", "tr", "bl", "br" }

function Draw.NewQuad(parent, layer, sub)
    local tex = parent:CreateTexture(nil, layer or "OVERLAY", nil, sub)
    tex:SetTexture(WHITE)
    return tex
end

-- ---------------------------------------------------------------------------
-- Colour keys
-- ---------------------------------------------------------------------------

-- key: a PALETTE key, "CLASS", "REACTION" (hostile red / friendly blue) or
-- "REACTION_RG" (hostile red / friendly green). ctx: { class = "MAGE",
-- reaction = "HOSTILE" | "NEUTRAL" | "FRIENDLY" }. Always returns rgb.
function Draw.ResolveColor(key, ctx)
    ctx = ctx or {}
    if key == "CLASS" then
        local color = ctx.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[ctx.class]
        if color then return color.r, color.g, color.b end
        return 1, 1, 1
    elseif key == "REACTION" or key == "REACTION_RG" then
        local set = key == "REACTION_RG" and DATA.REACTION_TINT_RG or DATA.REACTION_TINT
        local tint = set[ctx.reaction or "HOSTILE"] or set.HOSTILE
        return tint[1], tint[2], tint[3]
    end
    local c = DATA.PALETTE[key] or DATA.PALETTE.WHITE
    return c[1], c[2], c[3]
end

-- The options table for a colour dropdown. `extra` prepends entries such as
-- { text = "Off", value = "OFF" }; CLASS and both REACTION schemes are always
-- offered.
function Draw.ColorOptions(extra)
    local options = {}
    for _, entry in ipairs(extra or {}) do options[#options + 1] = entry end
    options[#options + 1] = { text = "Unit's class", value = "CLASS" }
    options[#options + 1] = { text = "Hostile red / friendly blue", value = "REACTION" }
    options[#options + 1] = { text = "Hostile red / friendly green", value = "REACTION_RG" }
    for _, key in ipairs(DATA.PALETTE_ORDER) do
        options[#options + 1] = { text = DATA.PALETTE_LABEL[key], value = key }
    end
    return options
end

-- ---------------------------------------------------------------------------
-- Ring: the outline
-- ---------------------------------------------------------------------------
function Draw.NewRing(parent, thickness, sub)
    local ring = { thickness = thickness or 2 }
    for _, side in ipairs(SIDES) do
        ring[side] = Draw.NewQuad(parent, "OVERLAY", sub or 2)
    end
    return ring
end

function Draw.RingAnchor(ring, target, pad)
    local t = ring.thickness
    pad = pad or 1
    for _, side in ipairs(SIDES) do ring[side]:ClearAllPoints() end
    ring.top:SetPoint("BOTTOMLEFT", target, "TOPLEFT", -pad - t, pad)
    ring.top:SetPoint("BOTTOMRIGHT", target, "TOPRIGHT", pad + t, pad)
    ring.top:SetHeight(t)
    ring.bottom:SetPoint("TOPLEFT", target, "BOTTOMLEFT", -pad - t, -pad)
    ring.bottom:SetPoint("TOPRIGHT", target, "BOTTOMRIGHT", pad + t, -pad)
    ring.bottom:SetHeight(t)
    ring.left:SetPoint("TOPRIGHT", target, "TOPLEFT", -pad, pad)
    ring.left:SetPoint("BOTTOMRIGHT", target, "BOTTOMLEFT", -pad, -pad)
    ring.left:SetWidth(t)
    ring.right:SetPoint("TOPLEFT", target, "TOPRIGHT", pad, pad)
    ring.right:SetPoint("BOTTOMLEFT", target, "BOTTOMRIGHT", pad, -pad)
    ring.right:SetWidth(t)
end

function Draw.RingShow(ring, shown, r, g, b, a)
    for _, side in ipairs(SIDES) do
        local tex = ring[side]
        tex:SetShown(shown)
        if shown then tex:SetVertexColor(r, g, b, a or 1) end
    end
end

-- ---------------------------------------------------------------------------
-- Halo: the glow. A real blur rather than a built one: Blizzard's own
-- UI-ActionButton-Border is a soft rounded glow ring with a transparent
-- middle. Two things make it usable here. It is DESATURATED, because the art
-- is baked yellow and a yellow ring times a blue tint is green; grey times
-- blue is blue. And it is drawn as THREE SLICES -- a left cap, a stretched
-- middle, a right cap -- each scaled uniformly from the ring's height, so the
-- band is the same thickness along the top as down the sides whatever the
-- bar's aspect ratio. Stretched whole over a 130x12 bar the sides come out
-- five times thicker than the top; sliced, they match.
-- ---------------------------------------------------------------------------
Draw.HALO_TEXTURE = "Interface\\Buttons\\UI-ActionButton-Border"
local HALO_CAP = 0.4        -- share of the art that is a cap (corner + a little straight)

function Draw.NewHalo(parent, sub)
    local halo = {}
    for _, part in ipairs({ "left", "mid", "right" }) do
        local tex = parent:CreateTexture(nil, "OVERLAY", nil, sub or 1)
        tex:SetTexture(Draw.HALO_TEXTURE)
        tex:SetBlendMode("ADD")
        if tex.SetDesaturated then tex:SetDesaturated(true) end
        halo[part] = tex
    end
    halo.left:SetTexCoord(0, HALO_CAP, 0, 1)
    halo.mid:SetTexCoord(HALO_CAP, 1 - HALO_CAP, 0, 1)
    halo.right:SetTexCoord(1 - HALO_CAP, 1, 0, 1)
    -- Kept for callers that still address the old quads; all point at the middle
    halo.top, halo.bottom = halo.mid, halo.mid
    return halo
end

-- `size` is how far the glow reaches past the target's edge. The ring's
-- height follows from that; the caps' width from the height, so the corners
-- keep their shape.
function Draw.HaloAnchor(halo, target, size)
    size = size or 10
    halo.size = size
    local targetH = (target.GetHeight and target:GetHeight()) or 12
    if targetH <= 1 then targetH = 12 end
    -- The art's glow band sits inside its own square with margins; reach
    -- past the edge by `size` means the ring is about 2.2 sizes taller than
    -- the target, since the band itself is roughly a third of the margin
    local h = targetH + size * 2.2
    local cap = h * HALO_CAP
    halo.left:ClearAllPoints(); halo.mid:ClearAllPoints(); halo.right:ClearAllPoints()
    local pad = size * 1.1
    halo.left:SetPoint("TOPLEFT", target, "TOPLEFT", -pad - cap * 0.25, pad)
    halo.left:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", -pad - cap * 0.25, -pad)
    halo.left:SetWidth(cap)
    halo.right:SetPoint("TOPRIGHT", target, "TOPRIGHT", pad + cap * 0.25, pad)
    halo.right:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", pad + cap * 0.25, -pad)
    halo.right:SetWidth(cap)
    halo.mid:SetPoint("TOPLEFT", halo.left, "TOPRIGHT", 0, 0)
    halo.mid:SetPoint("BOTTOMRIGHT", halo.right, "BOTTOMLEFT", 0, 0)
end

function Draw.HaloShow(halo, shown, r, g, b, alpha)
    alpha = alpha or 0.75
    for _, part in ipairs({ "left", "mid", "right" }) do
        halo[part]:SetShown(shown)
        if shown then halo[part]:SetVertexColor(r, g, b, alpha) end
    end
end
