-- Commander Gladiator: the window.
--
-- The engine beside this file plays the match; this file only shows it. It
-- owns no rule and knows no spell by name: it steps the match on a clock,
-- listens to what the match says happened, and reads the six units every
-- frame to decide what each token looks like. A sheep is "the token's face is
-- the icon of whatever spell is holding it", and that sentence is the whole
-- of what this file knows about Polymorph.
--
-- The window opens, two fixed teams fight, a banner says who won, the record
-- ticks over, and the next match is dealt. A match nobody touches plays
-- itself; the player has two verbs to reach in with, and nothing else on the
-- window but the header takes a click:
--
--   CLICK AN ENEMY to pin it as the team's kill target. Click another and
--   the pin moves; click the pinned one and it is let go.
--   TAP A GLOWING BUTTON under the floor to fire that gladiator's big spell
--   now instead of on its next beat.
--
-- Both go straight to the engine (match:Pin, match:Tap), which decides
-- whether anything happens and to whom: no spell is aimed by hand. This file
-- delivers the click and paints what the match then is.
--
-- FOUR IDEAS
--
--   THE FLOOR IS A PICTURE, THE MATCH IS A RECTANGLE. The engine's floor is
--   100 by 50 abstract units. G.Project turns a place on it into a place on
--   screen and a size: depth pushes a token down the window and grows it, and
--   the back edge is drawn a little narrower than the front. The disc the
--   tokens stand on is only art -- but the rectangle is laid inside it, so no
--   place the engine can put a unit is off the edge of the picture, and the
--   two pillars stand outside the rectangle, where nobody can walk into them.
--   The UI smoke proves both by sweeping the whole floor rather than by
--   anybody having looked.
--
--   THE PAINTER READS, THE EVENTS ANIMATE. What a unit IS -- its health, its
--   shield, the disable it is in, whether it is dead, whether it is somebody's
--   kill target -- is read off the unit every frame and painted, with each
--   widget told only when its answer changed. So AURA_GAINED, AURA_FADED,
--   FOCUS, DEATH and ROUT need no handler and cannot be missed or drift. The
--   hand's side of it is read the same way: the pin off match.pin, and each
--   button off its gladiator and match:Lit, every frame. What
--   HAPPENED -- a press, a hit, a heal, a teleport, the bell -- has no state
--   to read afterwards, and those five are the events this file handles.
--   The match as a whole is read the same way: one line of the header says
--   how much healing dampening has left, or that a side has been routed.
--
--   HIDDEN IS PAUSED. The clock is the window's own OnUpdate, and a hidden
--   frame's OnUpdate does not run, so closing the window stops the match in
--   mid-swing and opening it carries on. Nothing here uses a timer, on
--   purpose: this is the one place in the suite where "does not tick while
--   hidden" is the feature and not the bug.
--
--   THE GATES. A match is dealt and then held, for `gates` seconds of its
--   own clock, before its first tick. What a pin is worth is decided in the
--   first second -- it is the opening or it is a change of mind -- and a
--   match that started stepping on the frame after the deal left no moment
--   to make one in. At the gates the six stand on their marks, a line counts
--   down, an enemy can be pinned (the engine settles the team's focus inside
--   Pin, so that pin IS the opening), and the buttons show but do not fire.
--
-- EVERYTHING IS BUILT ONCE. The six tokens, the three buttons, the floating
-- numbers, the projectiles and the banner are made when the window is first
-- opened and reused for ever after; a match that runs for an hour creates no widget.
-- Numbers and projectiles are rings of a fixed size -- the oldest is taken
-- when all are flying -- so there is no pool to grow and nothing to leak.
--
-- ART. Four files in Textures/, copied from Commander Plates so neither addon
-- needs the other: a white disc, two ring weights and a soft glow. Files that
-- are new since the client was started are not found until it is restarted,
-- and a texture that is not found draws nothing rather than erroring -- so
-- everything a token cannot do without (its class badge, its name, the
-- numbers, every spell icon) is the client's own art, and what is copied is
-- only what is laid around it.

CommanderGladiator = CommanderGladiator or {}
local G = CommanderGladiator
local DATA, E = CommanderGladiator_Data, CommanderGladiator_Engine
local ARENA = DATA.ARENA
local TICK = ARENA.tick

local min, max, sin, pi = math.min, math.max, math.sin, math.pi

-- The side the player's hand is on. The engine does not know there is one:
-- Pin and Tap are side-blind, and it is this file that only ever calls them
-- for this side, lets only the OTHER side's tokens take a click, and builds
-- buttons for this side's gladiators alone.
local HAND = "A"

local WINDOW_NAME = "CommanderGladiatorWindow"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local TEX = "Interface\\AddOns\\Commander_Gladiator\\Textures\\"

G.ART = {
    disc = TEX .. "CircleMask.png",
    -- Two of Plates' six ring weights: the health band, and a thinner one
    -- worn outside it for a shield. A ring's thickness is baked into the art
    -- (inner radius over outer), and its outer radius is RING_OUTER of the
    -- texture's width.
    ring = TEX .. "Ring4.png",
    rim = TEX .. "Ring2.png",
    -- Rises from GLOW_BASE of its width, which is laid on the token's edge
    glow = TEX .. "GlowSoft.png",
    classes = "Interface\\TargetingFrame\\UI-Classes-Circles",
    marks = "Interface\\TargetingFrame\\UI-RaidTargetingIcons",
    unknown = "Interface\\Icons\\INV_Misc_QuestionMark",
}
local ART = G.ART
local RING_OUTER = 0.485
local GLOW_BASE = 0.28

-- ---------------------------------------------------------------------------
-- The layout: every number the picture is made of
-- ---------------------------------------------------------------------------
-- Pixels, measured from the window's bottom-left corner.
--
-- The floor is an ellipse (floorA by floorB about floorX, floorY): a round
-- arena seen from in front and above. The engine's rectangle is laid inside
-- it as a trapezoid -- walkFront pixels either side of centre along the
-- front edge, walkBack of that along the back edge, walkDepth above and
-- below centre. Its front corners are the points nearest the ellipse's
-- edge, at (199/262)^2 + (84/136)^2 = 0.96 of the way out, so a unit's feet
-- are always on the floor.
--
-- Under the floor is the bar: one button for each of the player's
-- gladiators, in slot order, `buttonGap` apart about the window's middle
-- and centred `barY` up from its bottom edge. A button is `rim` across (its
-- class-coloured edge; the icon inside is `button`), so the bar's top is at
-- 42 + 21 = 63 and the lowest point of the floor's slab is 220 - 136 - 9 =
-- 75: the two never meet, and the owner's name fits under the button with
-- the window's edge to spare. The two halves of the hint stand either side
-- of the bar, `hintGap` clear of it and `hintWidth` wide, in the corners
-- the round floor leaves empty.
--
-- The pillars stand on the disc's left and right ends, level with its
-- middle, where the rectangle is at its narrowest against the disc. The
-- nearest a token's edge can come is the front corner, 199 + 22 = 221 out
-- and well below the pillar's foot; level with the pillar the rectangle is
-- only 187 wide. The smoke sweeps every floor position and checks the two
-- never touch.
G.LAYOUT = {
    width = 560, height = 432, header = 28,
    floorX = 280, floorY = 220, floorA = 262, floorB = 136, slab = 9,
    walkFront = 199, walkBack = 0.88, walkDepth = 84,
    scaleBack = 0.82,
    token = 44, face = 32, badge = 29,
    pillarX = 233, pillarY = 6, pillarWidth = 22, pillarHeight = 58,
    barY = 42, button = 36, rim = 42, buttonGap = 64,
    hintGap = 14, hintWidth = 130,
    -- How long a match is held at its gates, in seconds of its own clock (so
    -- half as long by the wall at 2x), and how high over the middle of the
    -- floor the line that counts it down is written: above the heads of the
    -- back row, where nothing else is until somebody casts.
    gates = 2, countY = 100,
    -- A button that was clicked and did not fire says so by shaking: this
    -- long, this many pixels either way, dying away.
    shakeTime = 0.3, shakeReach = 3,
    -- An ability whose range is at most this is delivered by hand (a bump);
    -- anything longer is thrown (a projectile). The kite distance is the
    -- engine's own line between "on top of you" and "at range".
    melee = DATA.RULES.kite,
    -- The clock. At most maxSteps ticks are taken in one frame and whatever
    -- is left over is dropped, so a frame that took five seconds costs half a
    -- second of match and not a burst of fifty ticks that takes a frame of
    -- its own to compute.
    maxSteps = 5,
    bannerTime = 3,
    -- How fast a token closes on where its unit really is, per second of
    -- match time. A tick moves a unit at most 1.6 units, and at this rate a
    -- token is never more than about one unit behind -- enough to hide the
    -- ten-hertz stepping, and quick enough that a Charge still reads as one.
    smooth = 14,
    -- The room, in floor units, two standing tokens are DRAWN apart by --
    -- or as near to it as spreadPasses rounds of G.Spread get them. See
    -- there.
    space = 10, spreadPasses = 3,
    numbers = 24, shots = 8,
    numberLife = 0.9, numberRise = 26,
    -- A number starts numberDrop under the middle of its token, in one of
    -- three lanes numberLane apart. A lane used again within numberCrowd
    -- seconds starts its number numberStack higher. See G.Number.
    numberDrop = 8, numberLane = 14, numberCrowd = 0.15, numberStack = 12,
    flight = 0.25, bumpTime = 0.18, bumpReach = 9,
    popTime = 1.2, burstTime = 0.35, sinkTime = 0.5,
}
local L = G.LAYOUT

G.COLOURS = {
    -- Your side's health is green and theirs is red, which is the only thing
    -- on the floor that says whose token is whose
    A = { 0.30, 0.86, 0.36 },
    B = { 0.92, 0.27, 0.24 },
    damage = { 1.00, 0.62, 0.58 },
    heal = { 0.42, 1.00, 0.46 },
    absorb = { 0.72, 0.74, 0.78 },
    shield = { 0.86, 0.93, 1.00 },
    guard = { 1.00, 0.84, 0.36 },
    shadow = { 0, 0, 0, 0.40 },
    chilled = { 0.30, 0.62, 1.00, 0.55 },
    -- The header's healing line while it is only counting down. Once a side
    -- is routed the line is written in that side's own colour instead.
    dampened = { 0.80, 0.80, 0.80 },
    -- The hand's colour: the halo of a button that would fire, the disc
    -- behind the skull on a pinned enemy, the ring under the mouse
    hand = { 1.00, 0.84, 0.36 },
    -- What a button's cooldown is swept in, over its icon
    sweep = { 0, 0, 0, 0.65 },
    -- The rim and the name of a button whose gladiator is dead
    gone = { 0.30, 0.30, 0.30 },
}
local COLOURS = G.COLOURS

-- How each of the four disables reads on a token, keyed by the engine's own
-- word for it. `face` swaps the class badge for the icon of the spell doing
-- the holding (the sheep IS the Polymorph icon); `mark` pins that icon small
-- on the token's shoulder instead; `shade` dims, `tint` colours, `sway`
-- rocks it from side to side, `alpha` thins it.
G.LOOKS = {
    sheeped = { face = true },
    cycloned = { face = true, sway = true, alpha = 0.7 },
    stunned = { shade = 0.45, mark = true },
    feared = { tint = { 0.70, 0.45, 1.00 } },
}

-- The raid-target sheet, by index: a skull over the enemy your team is
-- killing, a cross over the one of yours that theirs is.
G.MARKS = { A = 7, B = 8 }

-- The four things a button can be saying, readable without a word on it.
-- `icon` and `rim` are how bright the spell and its class-coloured edge are
-- drawn; LIT alone wears the halo, SWEEP alone the dark wedge of what is
-- left of its cooldown -- over an icon at full strength, so that the part
-- already back stands out against it -- and `grey` takes the colour out
-- altogether.
--   LIT    a tap would fire it this instant
--   SWEEP  cooling down
--   DIM    ready, and nothing to fire at -- or its gladiator is a sheep, or
--          the gates are still shut
--   DEAD   its gladiator is dead
G.BUTTONS = {
    LIT = { icon = 1.00, rim = 1.00 },
    SWEEP = { icon = 1.00, rim = 0.60 },
    DIM = { icon = 0.40, rim = 0.45 },
    DEAD = { icon = 0.30, rim = 1.00, grey = true },
}

-- Whom a spell lands on, for a button's tooltip, by the engine's five
-- targeting questions (DATA.WHEN) and so for any spell a later spec brings.
-- No spell is aimed by hand, and the pin quietly decides where two of these
-- go, so the tooltip has to say it.
G.LANDS = {
    KILL_TARGET = "your kill target",
    OFF_TARGET = "the enemy healer if she is not your kill target, else on another enemy",
    MOST_HURT_ALLY = "your most hurt ally",
    GAP_CLOSER = "your kill target, while it is out of reach",
    ENEMY_NEAR = "the nearest enemy in range",
}

-- The hint, in two halves either side of the bar: one verb each. Shown until
-- the player has done both at least once, ever. Each is broken by hand into
-- two lines of a length, so that it is not left to the client's font to
-- strand one word on the second.
G.HINT = { "Click an enemy to\nset the kill target.", "Tap a glowing spell\nto fire it now." }

G.OUTCOMES = {
    A = { book = "Wins", word = "Victory", colour = { 1.00, 0.84, 0.25 } },
    B = { book = "Losses", word = "Defeat", colour = { 0.92, 0.30, 0.26 } },
    DRAW = { book = "Draws", word = "Draw", colour = { 0.80, 0.80, 0.80 } },
}

-- The match being shown and the clocks it runs on. `clock` is match-speed
-- seconds since the window was built and never rewinds; every animation is
-- timed against it, so 2x doubles the animations with the match and a closed
-- window freezes both.
--
-- `gate` is what is left of the wait at the gates, in match seconds, and nil
-- once the match is running.
G.state = { match = nil, seed = nil, acc = 0, clock = 0, rest = nil, gate = nil, number = 0, shot = 0 }
local S = G.state

-- ---------------------------------------------------------------------------
-- Floor to screen
-- ---------------------------------------------------------------------------
-- Where a unit's FEET are, and how big it is drawn there. Depth is 0 at the
-- back wall and 1 at the front: it carries the token down the window, grows
-- it from scaleBack to full size, and widens the row it stands in.
function G.Project(x, y)
    local depth = (y - ARENA.minY) / (ARENA.maxY - ARENA.minY)
    local across = (x - ARENA.minX) / (ARENA.maxX - ARENA.minX) - 0.5
    local reach = L.walkFront * (L.walkBack + (1 - L.walkBack) * depth)
    local scale = L.scaleBack + (1 - L.scaleBack) * depth
    return L.floorX + across * 2 * reach, L.floorY - (depth - 0.5) * 2 * L.walkDepth, scale
end

function G.Speed()
    return CommanderGladiatorDB.Speed == 2 and 2 or 1
end

-- The aura that put a state on a unit, for its icon. Public fields only.
function G.Aura(unit, state)
    for _, aura in ipairs(unit.auras) do
        if aura.state == state then return aura end
    end
    return nil
end

-- "Subtlety Rogue" is a caption too wide for a token; the badge already says
-- rogue, so the first word is the half that is news.
function G.ShortName(spec)
    return spec.name:match("^(%S+)") or spec.name
end

-- ---------------------------------------------------------------------------
-- The health ring
-- ---------------------------------------------------------------------------
-- Commander Plates' recipe (CommanderPlatesRadial.lua): a Cooldown frame
-- whose swipe texture is a donut, which the client masks radially into a
-- true arc. Health is a FROZEN cooldown -- a very long one, started so the
-- swipe already sits at the health share, and set again before it could have
-- crept a thousandth of a turn. GetTime counts from the machine's boot and a
-- start time before zero is not something to hand the client, so "very long"
-- is the time since boot, between a minute and a day.
--
-- A cooldown that has finished hides itself, so a FULL ring is a plain
-- texture, and an empty one is nothing over the dim track.
--
-- A button's cooldown is drawn by the same recipe and for a second reason:
-- the match's clock runs at the window's speed and stops while the window is
-- hidden, and a Cooldown left to run would keep the wall's time through
-- both. So it too is a share, worked out from the engine's ticks and frozen.
local STATIC, DRIFT = 86400, 0.001

-- The Cooldown itself: `art` is the shape it sweeps, centred on its parent.
-- It never takes the mouse, so a click on a button's wedge is a click on the
-- button.
function G.NewSweep(parent, size, art)
    local cd = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
    cd:EnableMouse(false)
    cd:SetSize(size, size)
    cd:SetPoint("CENTER", parent, "CENTER")
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
    if cd.SetDrawBling then cd:SetDrawBling(false) end
    if cd.SetDrawSwipe then cd:SetDrawSwipe(true) end
    -- The Cooldown's own edge is a spoke from the centre out, which on a
    -- donut is a line drawn straight across the face
    if cd.SetDrawEdge then cd:SetDrawEdge(false) end
    if cd.SetSwipeTexture then cd:SetSwipeTexture(art) end
    -- OmniCC and its kin write a countdown on every Cooldown they can find,
    -- and a health ring a day long would read "23h"
    cd.noCooldownCount = true
    cd.noOCC = true
    cd:Hide()
    return cd
end

function G.NewArc(token)
    local arc = {}
    local size = (L.token / 2) / RING_OUTER
    arc.track = token:CreateTexture(nil, "BACKGROUND", nil, 2)
    arc.track:SetTexture(ART.ring)
    arc.track:SetSize(size, size)
    arc.track:SetPoint("CENTER", token, "CENTER")
    arc.track:SetVertexColor(0.05, 0.05, 0.07, 0.6)

    arc.cd = G.NewSweep(token, size, ART.ring)

    arc.fullFrame = CreateFrame("Frame", nil, token)
    arc.fullFrame:SetAllPoints(token)
    arc.full = arc.fullFrame:CreateTexture(nil, "ARTWORK")
    arc.full:SetTexture(ART.ring)
    arc.full:SetSize(size, size)
    arc.full:SetPoint("CENTER", token, "CENTER")
    arc.full:Hide()
    return arc
end

-- The arc ends at twelve o'clock and its other end walks clockwise toward
-- it as the share falls. `now` is GetTime(). A colour may carry a fourth
-- number, how solid it is drawn: a ring's has none and is solid.
function G.ArcSet(arc, fraction, colour, now)
    if fraction <= 0.002 then
        if arc.fraction ~= 0 then
            arc.fraction, arc.setAt = 0, nil
            arc.cd:Hide()
            arc.full:Hide()
        end
        return
    end
    if fraction >= 0.998 then
        if arc.fraction ~= 1 or arc.colour ~= colour then
            arc.fraction, arc.colour, arc.setAt = 1, colour, nil
            arc.cd:Hide()
            arc.full:SetVertexColor(colour[1], colour[2], colour[3], colour[4] or 1)
            arc.full:Show()
        end
        return
    end
    -- A sweep that is already showing this share in this colour is left
    -- alone until it is old enough to have crept
    if arc.setAt and math.abs(arc.fraction - fraction) < 0.001 and arc.colour == colour
        and now - arc.setAt < arc.span * DRIFT then
        return
    end
    local span = min(max(now, 60), STATIC)
    arc.fraction, arc.colour, arc.setAt, arc.span = fraction, colour, now, span
    arc.full:Hide()
    -- Not reversed: a cooldown paints what REMAINS, which runs from the
    -- sweep's edge clockwise round to twelve
    if arc.cd.SetReverse then arc.cd:SetReverse(false) end
    if arc.cd.SetSwipeColor then arc.cd:SetSwipeColor(colour[1], colour[2], colour[3], colour[4] or 1) end
    arc.cd:SetCooldown(now - (1 - fraction) * span, span)
    arc.cd:Show()
end

-- ---------------------------------------------------------------------------
-- A token
-- ---------------------------------------------------------------------------
-- A spell icon as a small round thing. The client's icons carry a dark
-- border, trimmed here; the rounding is the suite's shared mask, which keeps
-- a square icon rather than losing it on a client that will not mask.
function G.NewSpellIcon(parent, layer, sublevel, size)
    local icon = parent:CreateTexture(nil, layer, nil, sublevel)
    icon:SetSize(size, size)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    Commander.RoundIcon(icon)
    icon:Hide()
    return icon
end

-- Three frames deep, so the ring can sit between what is under a token and
-- the face on top of it: the token itself (glow, shield rim, the ring's
-- track), the ring's two frames one level up, the face one above that.
-- G.Stack sets all four levels together whenever the token's place in the
-- depth order changes.
--
-- It is a Button so that it can be clicked, and it takes the mouse only
-- while it is an enemy that can be pinned (G.PaintState switches it): never
-- one of the player's own, so that a rogue standing on the enemy it is
-- stabbing cannot eat the click meant for that enemy, and not once dead. A
-- token that takes the mouse also takes a drag of the window that starts on
-- it; the header and the floor still drag.
function G.NewToken(id)
    local stage, overlay = G.stage, G.overlay
    local token = CreateFrame("Button", nil, stage)
    token.id = id
    token:SetSize(L.token, L.token)
    token:EnableMouse(false)
    token:SetScript("OnClick", G.ClickToken)

    -- On the floor, not on the token: a shadow must lie under every token,
    -- whichever of them is in front
    token.shadow = stage:CreateTexture(nil, "ARTWORK")
    token.shadow:SetTexture(ART.disc)

    local glowSize = (L.token / 2 + 1) / GLOW_BASE
    token.glow = token:CreateTexture(nil, "BACKGROUND", nil, -1)
    token.glow:SetTexture(ART.glow)
    token.glow:SetBlendMode("ADD")
    token.glow:SetSize(glowSize, glowSize)
    token.glow:SetPoint("CENTER", token, "CENTER")
    token.glow:SetVertexColor(COLOURS.guard[1], COLOURS.guard[2], COLOURS.guard[3])
    token.glow:Hide()

    -- Under the mouse: the client shows a HIGHLIGHT texture while the
    -- pointer is over a frame that takes the mouse, and at no other time, so
    -- this ring is "a click here would pin it" with nothing to keep in step
    token.hover = token:CreateTexture(nil, "HIGHLIGHT")
    token.hover:SetTexture(ART.glow)
    token.hover:SetBlendMode("ADD")
    token.hover:SetSize(glowSize, glowSize)
    token.hover:SetPoint("CENTER", token, "CENTER")
    token.hover:SetVertexColor(COLOURS.hand[1], COLOURS.hand[2], COLOURS.hand[3])

    -- The shield: a pale band worn just outside the health ring
    local rimSize = (L.token / 2 + 3.5) / RING_OUTER
    token.rim = token:CreateTexture(nil, "BACKGROUND", nil, 1)
    token.rim:SetTexture(ART.rim)
    token.rim:SetSize(rimSize, rimSize)
    token.rim:SetPoint("CENTER", token, "CENTER")
    token.rim:SetVertexColor(COLOURS.shield[1], COLOURS.shield[2], COLOURS.shield[3], 0.95)
    token.rim:Hide()

    token.arc = G.NewArc(token)

    local face = CreateFrame("Frame", nil, token)
    face:SetAllPoints(token)
    token.face = face
    token.disc = face:CreateTexture(nil, "BACKGROUND")
    token.disc:SetTexture(ART.disc)
    token.disc:SetSize(L.face, L.face)
    token.disc:SetPoint("CENTER", face, "CENTER")
    token.badge = face:CreateTexture(nil, "ARTWORK")
    token.badge:SetSize(L.badge, L.badge)
    token.badge:SetPoint("CENTER", face, "CENTER")
    token.swap = G.NewSpellIcon(face, "ARTWORK", 1, L.badge)
    token.swap:SetPoint("CENTER", face, "CENTER")
    -- Low on the left shoulder, under the kill mark and over the name: at
    -- the feet, where it was first put, it sat across the name's own line
    token.frost = G.NewSpellIcon(face, "OVERLAY", 1, 17)
    token.frost:SetPoint("CENTER", face, "BOTTOMLEFT", 5, 10)
    token.pin = G.NewSpellIcon(face, "OVERLAY", 2, 16)
    token.pin:SetPoint("CENTER", face, "TOPRIGHT", -5, -5)
    token.mark = face:CreateTexture(nil, "OVERLAY", nil, 3)
    token.mark:SetTexture(ART.marks)
    token.mark:SetSize(15, 15)
    token.mark:SetPoint("CENTER", face, "TOPLEFT", 5, -5)
    token.mark:Hide()
    -- The player's order: a disc in the hand's colour behind the skull of
    -- the enemy that was pinned, so a pinned skull is a skull on gold
    token.order = face:CreateTexture(nil, "OVERLAY", nil, 2)
    token.order:SetTexture(ART.disc)
    token.order:SetSize(23, 23)
    token.order:SetPoint("CENTER", token.mark, "CENTER")
    token.order:SetVertexColor(COLOURS.hand[1], COLOURS.hand[2], COLOURS.hand[3])
    token.order:Hide()
    token.name = face:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    token.name:SetPoint("TOP", face, "BOTTOM", 0, 1)

    -- The spell call-out rides above the token but is not part of it: it is
    -- not scaled by depth and it draws over every token
    token.popIcon = G.NewSpellIcon(overlay, "ARTWORK", 0, 22)
    token.popText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    token.popText:SetFont(FONT, 10, "OUTLINE")
    token.popText:SetPoint("TOP", token.popIcon, "BOTTOM", 0, -1)
    token.popText:Hide()

    token.bumpAt, token.popAt, token.lane = -math.huge, -math.huge, 0
    -- When each of the three number lanes was last used. See G.Number.
    token.laneAt = { -math.huge, -math.huge, -math.huge }
    return token
end

function G.Stack(token, level)
    token:SetFrameLevel(level)
    token.arc.cd:SetFrameLevel(level + 1)
    token.arc.fullFrame:SetFrameLevel(level + 1)
    token.face:SetFrameLevel(level + 2)
end

-- Dress a token as its unit, when a match is dealt. Every deal so far is
-- the same six, but a token is whatever unit it was handed: nothing here
-- or anywhere else in the file knows which spec stands in which slot.
function G.Dress(token, unit)
    token.x, token.y = unit.x, unit.y
    token.deadAt, token.bumpAt, token.popAt = nil, -math.huge, -math.huge

    local class = unit.spec.class
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if coords then
        token.badge:SetTexture(ART.classes)
        token.badge:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        token.badge:SetTexture(ART.unknown)
        token.badge:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    local colour = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    token.colour = colour and { colour.r, colour.g, colour.b } or { 1, 1, 1 }
    token.health = COLOURS[unit.side]
    token.name:SetText(G.ShortName(unit.spec))
    -- Everything the painter caches is "what the widgets show now", and stays
    -- true across a deal -- except the tint, which was mixed into the class
    -- colour the token had before this one
    token.tintKey = nil
end

-- Where the token is, in two steps. First every token closes on its unit
-- by `blend` of the distance: that is the smoothing, and `x`, `y` are where
-- the engine has the unit as near as the eye can tell.
function G.Follow(token, unit, blend)
    token.x = token.x + (unit.x - token.x) * blend
    token.y = token.y + (unit.y - token.y) * blend
    token.standX, token.standY = token.x, token.y
end

-- Then the living are given room. The engine lets a melee stand under five
-- units from its target, which on this floor is one token drawn on top of
-- another: two rings in one place and neither readable. So any two standing
-- tokens nearer than `space` are each drawn half the shortfall further
-- apart, along the line between them, and nobody is pushed off the floor.
-- It moves a melee and its target about ten pixels each and barely anybody
-- else -- a caster already keeps nine units from a melee -- and it changes
-- only where a token is DRAWN (`standX`, `standY`); the match never hears
-- of it.
--
-- Once round the pairs does not do it. A push into a wall is handed straight
-- back by the clamp, so a pair in a corner got half its room; and with three
-- in a row the middle one is pushed clear of the first and then back onto it
-- by the third. So the pairs and the clamp are gone round `spreadPasses`
-- times, each making up half of what the one before left: two on one spot in
-- a corner end 8.75 units apart where one pass left them 5.
--
-- It is a settling and not a promise. Over forty matches watched through
-- the smoke's mock, one pass left some living pair more than half a unit
-- short of its room in a third of all frames, and in thirty-one of the forty
-- two tokens sat more than 16 pixels into each other for a second or longer.
-- Three passes leave a pair short in an eighth of the frames and that second
-- of pile-up in two matches of the forty. More passes close what is left
-- (five: one frame in forty), and they are one number in the layout.
function G.Spread(match)
    local tokens = G.tokens
    for _ = 1, L.spreadPasses do
        for i = 1, #tokens - 1 do
            local a = tokens[i]
            for j = i + 1, #tokens do
                local b = tokens[j]
                if match.units[i].alive and match.units[j].alive then
                    local dx, dy = b.standX - a.standX, b.standY - a.standY
                    local distance = math.sqrt(dx * dx + dy * dy)
                    if distance < L.space then
                        local push = (L.space - distance) / 2
                        if distance > 0 then
                            dx, dy = dx / distance, dy / distance
                        else
                            -- Two on exactly one spot have no line between
                            -- them: the lower id goes left
                            dx, dy = 1, 0
                        end
                        a.standX, a.standY = a.standX - dx * push, a.standY - dy * push
                        b.standX, b.standY = b.standX + dx * push, b.standY + dy * push
                    end
                end
            end
        end
        for _, token in ipairs(tokens) do
            token.standX = min(max(token.standX, ARENA.minX), ARENA.maxX)
            token.standY = min(max(token.standY, ARENA.minY), ARENA.maxY)
        end
    end
end

-- And then it is put there: carried off its mark by a bump or a sway, and
-- once dead sunk toward its own shadow and shrunk.
function G.PaintPlace(token, unit, look)
    local px, py, scale = G.Project(token.standX, token.standY)

    local sunk = 0
    if not unit.alive then
        token.deadAt = token.deadAt or S.clock
        sunk = min(1, (S.clock - token.deadAt) / L.sinkTime)
    end
    token.sunk = sunk

    local ox, oy = 0, 0
    local age = S.clock - token.bumpAt
    if age < L.bumpTime then
        local reach = sin(pi * age / L.bumpTime) * L.bumpReach
        ox, oy = token.bumpX * reach, token.bumpY * reach
    end
    if look and look.sway then ox = ox + sin(S.clock * 14) * 3 end

    local drawn = scale * (1 - 0.2 * sunk)
    local cx = px + ox
    local cy = py + oy + (L.token / 2) * scale * (1 - 0.65 * sunk)
    if token.drawn ~= drawn then
        token.drawn = drawn
        token:SetScale(drawn)
    end
    -- A scaled frame's offsets are in its own units, so the screen position
    -- is divided back out
    token:SetPoint("CENTER", G.stage, "BOTTOMLEFT", cx / drawn, cy / drawn)
    token.shadow:SetSize(38 * scale, 13 * scale)
    token.shadow:SetPoint("CENTER", G.stage, "BOTTOMLEFT", px, py)
    token.cx, token.cy, token.top = cx, cy, cy + (L.token / 2) * drawn
end

-- What the token is: its face, its pins, its colour. Each widget is told
-- only when its answer changed.
function G.PaintState(token, unit, match, hold, look)
    local dead = not unit.alive
    if token.dead ~= dead then
        token.dead = dead
        token.badge:SetDesaturated(dead)
        token.arc.track:SetShown(not dead)
    end

    local face = look and look.face and hold.ability.icon or nil
    if token.faceIcon ~= face then
        token.faceIcon = face
        if face then
            token.swap:SetTexture(face)
            token.swap:Show()
            token.badge:Hide()
        else
            token.swap:Hide()
            token.badge:Show()
        end
    end

    local pin = look and look.mark and hold.ability.icon or nil
    if token.pinIcon ~= pin then
        token.pinIcon = pin
        if pin then token.pin:SetTexture(pin) end
        token.pin:SetShown(pin ~= nil)
    end

    local root = not dead and G.Aura(unit, "rooted")
    local frost = root and root.ability.icon or nil
    if token.frostIcon ~= frost then
        token.frostIcon = frost
        if frost then token.frost:SetTexture(frost) end
        token.frost:SetShown(frost ~= nil)
    end

    local shade = (dead and 0.5) or (look and look.shade) or 1
    local tint = look and look.tint
    local tr, tg, tb = shade, shade, shade
    if tint then tr, tg, tb = shade * tint[1], shade * tint[2], shade * tint[3] end
    local tintKey = tr * 1e6 + tg * 1e3 + tb
    if token.tintKey ~= tintKey then
        token.tintKey = tintKey
        token.badge:SetVertexColor(tr, tg, tb)
        token.disc:SetVertexColor(token.colour[1] * tr, token.colour[2] * tg, token.colour[3] * tb)
    end

    local alpha = (dead and 1 - 0.55 * token.sunk) or (look and look.alpha) or 1
    if token.alpha ~= alpha then
        token.alpha = alpha
        token:SetAlpha(alpha)
    end

    -- Whether a click here would be a pin: an enemy, standing, in a match
    -- still being fought. The hover ring goes with the mouse.
    local open = unit.side ~= HAND and not dead and not match.over
    if token.open ~= open then
        token.open = open
        token:EnableMouse(open)
    end

    -- The pin is read off the match, not heard from it: a click on the
    -- enemy the team is already killing changes no focus and says nothing,
    -- and a pinned enemy that is a sheep is not the team's focus at all
    -- while it is one -- but the order was taken, and the token says so.
    local ordered = open and match.pin[HAND] == unit
    if token.ordered ~= ordered then
        token.ordered = ordered
        token.order:SetShown(ordered)
    end

    -- The other side's kill target is this unit, or the player has pinned
    -- it: mark it, until the bell
    local hunted = not dead and not match.over and match.focus[unit.side == "A" and "B" or "A"] == unit
    local mark = (hunted or ordered) and G.MARKS[unit.side] or nil
    if token.markIndex ~= mark then
        token.markIndex = mark
        if mark then
            local col, row = (mark - 1) % 4, math.floor((mark - 1) / 4)
            token.mark:SetTexCoord(col / 4, (col + 1) / 4, row / 4, (row + 1) / 4)
        end
        token.mark:SetShown(mark ~= nil)
    end

    local chilled = not dead and unit:Is("slowed")
    if token.chilled ~= chilled or token.shadowDead ~= dead then
        token.chilled, token.shadowDead = chilled, dead
        local c = chilled and COLOURS.chilled or COLOURS.shadow
        token.shadow:SetVertexColor(c[1], c[2], c[3], dead and c[4] * 0.5 or c[4])
    end
end

-- Health, the shield over it, and Pain Suppression's glow under it.
function G.PaintHealth(token, unit, now)
    local alive = unit.alive
    G.ArcSet(token.arc, alive and unit.health / unit.healthMax or 0, token.health, now)

    local shielded = alive and unit.absorb > 0
    if token.shielded ~= shielded then
        token.shielded = shielded
        token.rim:SetShown(shielded)
    end

    local guarded = alive and unit:Is("suppressed")
    if token.guarded ~= guarded then
        token.guarded = guarded
        token.glow:SetShown(guarded)
    end
    if guarded then token.glow:SetAlpha(0.65 + 0.3 * sin(S.clock * 7)) end
end

-- The spell call-out above a token: up at once, held, gone in the last
-- quarter of its time.
function G.PaintPop(token)
    local age = S.clock - token.popAt
    local live = age < L.popTime
    if token.popLive ~= live then
        token.popLive = live
        token.popIcon:SetShown(live)
        token.popText:SetShown(live)
    end
    if not live then return end
    local p = age / L.popTime
    local alpha = p > 0.75 and (1 - p) / 0.25 or 1
    -- Icon over name over token: the name's line sits between them
    token.popIcon:SetPoint("CENTER", G.overlay, "BOTTOMLEFT", token.cx, token.top + 27 + 6 * p)
    token.popIcon:SetAlpha(alpha)
    token.popText:SetAlpha(alpha)
end

function G.PaintToken(token, unit, match, now)
    local hold = unit.disabled and G.Aura(unit, unit.disabled)
    local look = hold and G.LOOKS[unit.disabled] or nil
    G.PaintPlace(token, unit, look)
    G.PaintState(token, unit, match, hold, look)
    G.PaintHealth(token, unit, now)
    G.PaintPop(token)
end

-- ---------------------------------------------------------------------------
-- Depth order
-- ---------------------------------------------------------------------------
-- A token nearer the front draws over one behind it, and the dead lie under
-- everybody. The six are sorted every frame -- six is nothing -- but a frame
-- level is only set when a token's rank actually changed, which is a few
-- times a match.
function G.Behind(a, b)
    if a.depth ~= b.depth then return a.depth < b.depth end
    return a.id < b.id
end

function G.Restack(match)
    -- The levels are counted up from the stage's own, read each time: the
    -- window is top-level, and the client moves it up the strata when it is
    -- clicked. Tokens left on levels counted from where it USED to be would
    -- be under their own floor.
    local base = G.stage:GetFrameLevel() + 1
    if G.baseLevel ~= base then
        G.baseLevel = base
        G.overlay:SetFrameLevel(base + #G.order * 3 + 2)
        for _, token in ipairs(G.order) do token.rank = nil end
    end
    for _, token in ipairs(G.order) do
        token.depth = token.standY - (match.units[token.id].alive and 0 or 1000)
    end
    table.sort(G.order, G.Behind)
    for rank, token in ipairs(G.order) do
        if token.rank ~= rank then
            token.rank = rank
            G.Stack(token, G.baseLevel + (rank - 1) * 3)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Things that fly: numbers, projectiles, the area ring
-- ---------------------------------------------------------------------------
-- A floating number on a token. Direct hits are larger than a dot's tick
-- and a crit is larger again; the size is set once, when it is thrown.
--
-- It starts on the token's face and rises to about its top edge. It used to
-- start AT the top edge, and the band above a token belongs to the spell
-- call-out: every number thrown while one was up rose straight through the
-- spell's name.
function G.Number(token, text, colour, crit, small)
    S.number = S.number % L.numbers + 1
    local fs = G.numbers[S.number]
    fs:SetFont(FONT, (crit and 17) or (small and 10) or 13, "OUTLINE")
    fs:SetText(text)
    fs:SetTextColor(colour[1], colour[2], colour[3])
    -- Three lanes, taken in turn, so a hit and the heal that answers it are
    -- side by side rather than one on top of the other. A fourth number in
    -- the same breath comes back round to the first one's lane, at the same
    -- height and the same instant, and would be written exactly over it for
    -- the whole of its life -- so a lane used this tick or the last starts
    -- its next number a line higher. No longer than that: two ticks on, the
    -- earlier number has risen ten pixels by itself, and a lift would put the
    -- new one onto it rather than clear of it.
    local lane = token.lane % 3 + 1
    token.lane = lane
    local lift = S.clock - token.laneAt[lane] < L.numberCrowd and L.numberStack or 0
    token.laneAt[lane] = S.clock
    fs.x, fs.y = token.cx + (lane - 2) * L.numberLane, token.cy - L.numberDrop + lift
    fs.born, fs.live = S.clock, true
    fs:Show()
end

function G.PaintNumbers()
    for _, fs in ipairs(G.numbers) do
        if fs.live then
            local p = (S.clock - fs.born) / L.numberLife
            if p >= 1 then
                fs.live = false
                fs:Hide()
            else
                -- Fast off the token and slowing, then fading over the last third
                fs:SetPoint("CENTER", G.overlay, "BOTTOMLEFT", fs.x, fs.y + L.numberRise * (1 - (1 - p) * (1 - p)))
                fs:SetAlpha(p > 0.65 and (1 - p) / 0.35 or 1)
            end
        end
    end
end

-- A projectile is the ability's own icon, thrown from where the caster was
-- to wherever the target is by the time it lands. It is only a picture: the
-- engine applied the effect on the tick it was pressed.
function G.Shoot(from, to, icon)
    S.shot = S.shot % L.shots + 1
    local shot = G.shots[S.shot]
    shot:SetTexture(icon)
    shot.fromX, shot.fromY, shot.to, shot.born, shot.live = from.cx, from.cy, to, S.clock, true
    shot:Show()
end

function G.PaintShots()
    for _, shot in ipairs(G.shots) do
        if shot.live then
            local p = (S.clock - shot.born) / L.flight
            if p >= 1 then
                shot.live = false
                shot:Hide()
            else
                local to = shot.to
                shot:SetPoint("CENTER", G.overlay, "BOTTOMLEFT",
                    shot.fromX + (to.cx - shot.fromX) * p,
                    shot.fromY + (to.cy - shot.fromY) * p + sin(pi * p) * 8)
            end
        end
    end
end

-- An area ability: one ring on the floor, spreading from the caster's feet
-- to the ability's range. There is one of it because there is one area spell
-- in the data and its cooldown is twelve seconds.
function G.Burst(token, ability)
    local burst = G.burst
    local px, py = G.Project(token.standX, token.standY)
    burst:SetPoint("CENTER", G.stage, "BOTTOMLEFT", px, py)
    burst.reach = ability.range / (ARENA.maxX - ARENA.minX) * 2 * L.walkFront
    burst.born, burst.live = S.clock, true
    burst:Show()
end

function G.PaintBurst()
    local burst = G.burst
    if not burst.live then return end
    local p = (S.clock - burst.born) / L.burstTime
    if p >= 1 then
        burst.live = false
        burst:Hide()
        return
    end
    -- The ring art's band ends at RING_OUTER of its width; the floor is
    -- shallower than it is wide by the same ratio the walk rectangle is
    local width = 2 * burst.reach * p / (2 * RING_OUTER)
    local squash = (L.walkDepth / (ARENA.maxY - ARENA.minY)) / (L.walkFront / (ARENA.maxX - ARENA.minX))
    burst:SetSize(max(width, 1), max(width * squash, 1))
    burst:SetAlpha(0.85 * (1 - p))
end

-- ---------------------------------------------------------------------------
-- The hand: the pin, the bar, the gates, the hint
-- ---------------------------------------------------------------------------
-- The hint is on screen until the player has done both verbs once, ever.
-- The two flags are settings, so Restore Defaults brings it back.
function G.ShowHint()
    local db = CommanderGladiatorDB
    local shown = not (db.Pinned and db.Tapped)
    for _, half in ipairs(G.hints) do half:SetShown(shown) end
end

-- A click on an enemy token. Whether it pins, moves the pin or lets it go
-- is the engine's to say, and so is whether it does anything at all; the
-- mark is painted from match.pin on the next frame.
function G.ClickToken(token)
    local match = S.match
    if match and match:Pin(HAND, match.units[token.id]) then
        CommanderGladiatorDB.Pinned = true
        G.ShowHint()
    end
end

-- A click on a button. Lit, and the gates open, the spell fires here and
-- now -- and what the match said about it is heard here and now too, so the
-- call-out and the projectile leave on the click and not on the next tick.
-- Anything else is a miss, and the button shakes its head: a click that did
-- nothing and said nothing would read as a click that was not taken.
function G.ClickButton(button)
    local match = S.match
    if match and not S.gate and match:Tap(button.unit) then
        CommanderGladiatorDB.Tapped = true
        G.ShowHint()
        G.Hear(match:Drain())
        return
    end
    button.missAt = S.clock
end

function G.EnterButton(button)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(button.tipTitle, 1, 1, 1)
    GameTooltip:AddLine(button.tipText, nil, nil, nil, true)
    GameTooltip:Show()
end

function G.LeaveButton()
    GameTooltip:Hide()
end

-- One button of the bar. Its place is fixed for ever: a thing to be hit in
-- a hurry does not move.
function G.NewButton(x)
    local stage = G.stage
    local button = CreateFrame("Button", nil, stage)
    button:SetSize(L.rim, L.rim)
    button.x = x
    button:SetPoint("CENTER", stage, "BOTTOMLEFT", x, L.barY)

    local haloSize = (L.rim / 2 + 1) / GLOW_BASE
    button.halo = button:CreateTexture(nil, "BACKGROUND", nil, -1)
    button.halo:SetTexture(ART.glow)
    button.halo:SetBlendMode("ADD")
    button.halo:SetSize(haloSize, haloSize)
    button.halo:SetPoint("CENTER", button, "CENTER")
    button.halo:SetVertexColor(COLOURS.hand[1], COLOURS.hand[2], COLOURS.hand[3])
    button.halo:Hide()

    button.rim = button:CreateTexture(nil, "BACKGROUND", nil, 1)
    button.rim:SetTexture(ART.disc)
    button.rim:SetSize(L.rim, L.rim)
    button.rim:SetPoint("CENTER", button, "CENTER")

    button.icon = G.NewSpellIcon(button, "ARTWORK", 0, L.button)
    button.icon:SetPoint("CENTER", button, "CENTER")
    button.icon:Show()

    -- The cooldown: the wedge of what is left, and the plain disc that
    -- stands in for it on the tick the spell was pressed (see G.ArcSet)
    button.sweep = { cd = G.NewSweep(button, L.button, ART.disc) }
    button.sweep.full = button:CreateTexture(nil, "OVERLAY")
    button.sweep.full:SetTexture(ART.disc)
    button.sweep.full:SetSize(L.button, L.button)
    button.sweep.full:SetPoint("CENTER", button, "CENTER")
    button.sweep.full:Hide()

    button.name = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.name:SetPoint("TOP", button, "BOTTOM", 0, -1)

    button.missAt = -math.huge
    button:SetScript("OnClick", G.ClickButton)
    button:SetScript("OnEnter", G.EnterButton)
    button:SetScript("OnLeave", G.LeaveButton)
    return button
end

-- Hand a button its gladiator, when a match is dealt: the big spell's icon,
-- the owner's class colour round it and short name under it, and the
-- tooltip's two lines. Like a token, a button is whatever unit it was
-- handed.
function G.DressButton(button, unit, colour)
    local big = unit.big
    button.unit, button.colour = unit, colour
    button.icon:SetTexture(big.icon)
    button.name:SetText(G.ShortName(unit.spec))
    local lands = G.LANDS[big.when]
    if big.below then lands = lands .. string.format(", once under %d%% health", big.below * 100) end
    button.tipTitle = big.name
    button.tipText = unit.spec.name .. ": lands on " .. lands .. "."
    -- A new owner is a new colour under the same word, so what the painter
    -- remembers of the last match's look is forgotten
    button.state, button.missAt = nil, -math.huge
end

-- What each button is saying, read off its gladiator every frame. The
-- cooldown is the engine's own count of ticks -- the tick the spell is back
-- against the tick it is -- as a share of the row's cooldown.
function G.PaintBar(match, now)
    for _, button in ipairs(G.buttons) do
        local unit = button.unit
        local big = unit.big
        local left = (unit.ready[big.key] or 0) - match.tick
        local state = "DIM"
        if not unit.alive then
            state = "DEAD"
        elseif left > 0 then
            state = "SWEEP"
        elseif not S.gate and match:Lit(unit) then
            state = "LIT"
        end
        G.ArcSet(button.sweep, state == "SWEEP" and left / (big.cooldown / TICK) or 0, COLOURS.sweep, now)

        if button.state ~= state then
            button.state = state
            local look = G.BUTTONS[state]
            local colour = look.grey and COLOURS.gone or button.colour
            button.icon:SetDesaturated(look.grey == true)
            button.icon:SetVertexColor(look.icon, look.icon, look.icon)
            button.rim:SetVertexColor(colour[1] * look.rim, colour[2] * look.rim, colour[3] * look.rim)
            if look.grey then
                button.name:SetTextColor(colour[1], colour[2], colour[3])
            else
                button.name:SetTextColor(1, 1, 1)
            end
            button.halo:SetShown(state == "LIT")
        end
        if state == "LIT" then button.halo:SetAlpha(0.65 + 0.3 * sin(S.clock * 7)) end

        local age = S.clock - button.missAt
        local shake = 0
        if age < L.shakeTime then
            shake = sin(4 * pi * age / L.shakeTime) * L.shakeReach * (1 - age / L.shakeTime)
        end
        if button.shake ~= shake then
            button.shake = shake
            button:SetPoint("CENTER", G.stage, "BOTTOMLEFT", button.x + shake, L.barY)
        end
    end
end

-- The line that counts the gates down, in whole seconds still to go. The
-- text is only made when the number changes.
function G.PaintGate()
    local left = S.gate and math.ceil(S.gate - 1e-9) or nil
    if G.countSaid == left then return end
    G.countSaid = left
    if left then G.count:SetText(string.format("Gates open in %d", left)) end
    G.count:SetShown(left ~= nil)
end

-- ---------------------------------------------------------------------------
-- What the match said happened
-- ---------------------------------------------------------------------------
-- How an ability travels, worked out from its row and remembered per row: a
-- unit that MOVES is its own delivery, an area spell is a ring on the floor,
-- a short range is a bump and a long one is a throw.
G.delivery = {}

function G.Delivery(ability)
    local how = G.delivery[ability]
    if how then return how end
    how = ability.range <= L.melee and "BUMP" or "SHOT"
    if ability.area then how = "BURST" end
    for _, effect in ipairs(ability.effects) do
        if effect.kind == "MOVE" then how = "SELF" end
    end
    G.delivery[ability] = how
    return how
end

G.On = {}

function G.On.ABILITY(event)
    local token, target = G.tokens[event.source], G.tokens[event.target]
    local ability = event.ability
    -- The signature spells are the point of a spec, so each is called out by
    -- icon and name; a filler pressed every other second is not
    if not event.basic then
        token.popAt = S.clock
        token.popIcon:SetTexture(ability.icon)
        token.popText:SetText(ability.name)
    end
    local how = G.Delivery(ability)
    if how == "BURST" then
        G.Burst(token, ability)
    elseif token == target then
        return
    elseif how == "BUMP" then
        local dx, dy = target.cx - token.cx, target.cy - token.cy
        local distance = math.sqrt(dx * dx + dy * dy)
        if distance > 0 then
            token.bumpAt, token.bumpX, token.bumpY = S.clock, dx / distance, dy / distance
        end
    elseif how == "SHOT" then
        G.Shoot(token, target, ability.icon)
    end
end

function G.On.DAMAGE(event)
    local token = G.tokens[event.target]
    if event.amount > 0 then
        G.Number(token, tostring(event.amount), COLOURS.damage, event.crit, event.periodic)
    end
    if event.absorbed > 0 then
        G.Number(token, tostring(event.absorbed), COLOURS.absorb, false, true)
    end
end

function G.On.HEAL(event)
    G.Number(G.tokens[event.target], "+" .. event.amount, COLOURS.heal, event.crit, event.periodic)
end

-- A teleport is not smoothed -- gliding across the floor is exactly what a
-- Shadowstep is not. A dash is left to the smoothing, which closes a Charge
-- in about a fifth of a second.
function G.On.MOVE(event)
    if event.mode ~= "TELEPORT" then return end
    local token = G.tokens[event.source]
    token.x, token.y = event.toX, event.toY
end

-- The bell: the book is written, the banner goes up, and the next match is
-- dealt when the banner has had its time.
function G.On.END(event)
    local outcome = G.OUTCOMES[event.winner]
    local db = CommanderGladiatorDB
    db[outcome.book] = (db[outcome.book] or 0) + 1
    G.ShowRecord()
    G.banner:SetText(outcome.word)
    G.banner:SetTextColor(outcome.colour[1], outcome.colour[2], outcome.colour[3])
    G.banner:Show()
    G.bannerBand:Show()
    S.rest = L.bannerTime
end

function G.Hear(events)
    for _, event in ipairs(events) do
        local handler = G.On[event.kind]
        if handler then handler(event) end
    end
end

-- ---------------------------------------------------------------------------
-- The loop
-- ---------------------------------------------------------------------------
function G.ShowRecord()
    local db = CommanderGladiatorDB
    local text = string.format("%d won   %d lost", db.Wins or 0, db.Losses or 0)
    if (db.Draws or 0) > 0 then text = text .. string.format("   %d drawn", db.Draws) end
    G.record:SetText(text)
end

-- The header's healing line. Dampening is in nearly every match -- nineteen
-- in twenty run past the twenty seconds where it starts, one in five past
-- the thirty-four where healing ends -- and it was nowhere on screen: heals
-- quietly shrank, then the healers stopped pressing them, and a spectator
-- could not tell that rule from a bug. So the line is empty while healing is
-- whole, counts it down ("Healing 43%") while it is not, and says "No
-- healing" at the end.
--
-- A rout takes the line over, in the routed side's colour -- the same green
-- and red the health rings wear, which is how the floor says whose a token
-- is. About one match in three has one. From there the match is the kill:
-- nothing heals that side, every hit on it lands harder, and "Routed" is why
-- the last healer falls so fast.
--
-- Read off the match every frame like everything else that is a state, and
-- the text is only made when what it would say has changed: `said` is the
-- routed side, or the whole percent, or nil for nothing to say.
function G.PaintHealing(match)
    local said = match.routed
    if not said then
        local share = match:Dampening()
        -- The nearest whole percent, and nought of them is "No healing".
        -- The data gives dampening fourteen seconds, a 140th a tick, so its
        -- first tick reads 99 and its last reads 1: it is never "Healing
        -- 100%", and never nought while there is some
        if share < 1 then said = math.floor(share * 100 + 0.5) end
    end
    if G.healingSaid == said then return end
    G.healingSaid = said
    if not said then
        G.healing:Hide()
        return
    end
    local colour = COLOURS.dampened
    if said == match.routed then
        colour = COLOURS[said]
        G.healing:SetText("Routed")
    elseif said == 0 then
        G.healing:SetText("No healing")
    else
        G.healing:SetText(string.format("Healing %d%%", said))
    end
    G.healing:SetTextColor(colour[1], colour[2], colour[3])
    G.healing:Show()
end

function G.Paint(match, dt)
    local blend = 1 - math.exp(-L.smooth * dt)
    local now = GetTime()
    for id, token in ipairs(G.tokens) do
        G.Follow(token, match.units[id], blend)
    end
    G.Spread(match)
    for id, token in ipairs(G.tokens) do
        G.PaintToken(token, match.units[id], match, now)
    end
    G.Restack(match)
    G.PaintNumbers()
    G.PaintShots()
    G.PaintBurst()
    G.PaintHealing(match)
    G.PaintBar(match, now)
    G.PaintGate()
end

-- Deal the next match. The seed is taken from the book and the book is moved
-- on in the same breath, so a reload in the middle of a match carries on
-- with the next one rather than dealing this one again.
function G.Deal()
    local db = CommanderGladiatorDB
    local seed = db.Seed or 1
    db.Seed = seed + 1
    local match = E.NewMatch(DATA.TEAMS.A, DATA.TEAMS.B, seed)
    S.match, S.seed, S.acc, S.rest, S.gate = match, seed, 0, nil, L.gates

    G.banner:Hide()
    G.bannerBand:Hide()
    for _, fs in ipairs(G.numbers) do
        fs.live = false
        fs:Hide()
    end
    for _, shot in ipairs(G.shots) do
        shot.live = false
        shot:Hide()
    end
    G.burst.live = false
    G.burst:Hide()
    for id, token in ipairs(G.tokens) do
        G.Dress(token, match.units[id])
    end
    -- The bar is the hand's side in slot order, which is the order the
    -- match lists them in
    local slot = 0
    for id, unit in ipairs(match.units) do
        if unit.side == HAND then
            slot = slot + 1
            G.DressButton(G.buttons[slot], unit, G.tokens[id].colour)
        end
    end
    -- Painted once at once: the first event of the match needs to know where
    -- its tokens are
    G.Paint(match, 0)
end

function G.OnUpdate(_, elapsed)
    local match = S.match
    if not match then return end
    local budget = L.maxSteps * TICK
    local dt = elapsed * G.Speed()

    if S.gate then
        -- At the gates: the match's clock is spent on the wait and no tick
        -- is taken. A hitch costs the wait what it would have cost the
        -- match, and the frame that opens the gates steps nothing -- what
        -- it had left over is dropped, like any other remainder here.
        S.gate = S.gate - min(dt, budget)
        if S.gate <= 1e-9 then S.gate = nil end
    else
        S.acc = S.acc + dt
        local steps = 0
        -- The hair under TICK is for frames that add up to a tick in
        -- arithmetic and to a whisker less in floating point
        while S.acc >= TICK - 1e-9 and steps < L.maxSteps do
            S.acc = max(0, S.acc - TICK)
            steps = steps + 1
            if not match.over then
                match:Step()
                G.Hear(match:Drain())
            end
        end
        -- A hitch is dropped, not owed
        if S.acc >= TICK then S.acc = 0 end
    end
    S.clock = S.clock + min(dt, budget)

    if S.rest then
        S.rest = S.rest - min(elapsed, budget)
        if S.rest <= 0 then
            G.Deal()
            return
        end
    end
    G.Paint(match, min(dt, budget))
end

-- ---------------------------------------------------------------------------
-- Building it, once
-- ---------------------------------------------------------------------------
function G.Disc(parent, layer, sublevel, width, height, x, y, r, g, b, a)
    local disc = parent:CreateTexture(nil, layer, nil, sublevel)
    disc:SetTexture(ART.disc)
    disc:SetSize(width, height)
    disc:SetPoint("CENTER", parent, "BOTTOMLEFT", x, y)
    disc:SetVertexColor(r, g, b, a or 1)
    return disc
end

-- A pillar is a cylinder out of five flat pieces: a shadow on the floor, a
-- body, the round of its foot, a lit strip down one side and a paler cap.
-- Nothing in the engine stands where it is; it is scenery.
function G.BuildPillar(stage, x, y)
    local width, height = L.pillarWidth, L.pillarHeight
    local round = width * 0.36
    G.Disc(stage, "BORDER", 0, width * 1.7, round * 1.5, x + 3, y - 1, 0, 0, 0, 0.35)
    G.Disc(stage, "BORDER", 1, width, round, x, y, 0.33, 0.30, 0.28)
    local body = stage:CreateTexture(nil, "BORDER", nil, 1)
    body:SetColorTexture(0.33, 0.30, 0.28, 1)
    body:SetSize(width, height)
    body:SetPoint("BOTTOM", stage, "BOTTOMLEFT", x, y)
    local lit = stage:CreateTexture(nil, "BORDER", nil, 2)
    lit:SetColorTexture(0.45, 0.42, 0.38, 1)
    lit:SetSize(width * 0.28, height)
    lit:SetPoint("BOTTOM", stage, "BOTTOMLEFT", x - width * 0.2, y)
    G.Disc(stage, "BORDER", 3, width, round, x, y + height, 0.55, 0.51, 0.46)
    return body
end

function G.BuildStage(window)
    local stage = CreateFrame("Frame", nil, window)
    stage:SetAllPoints(window)
    G.stage = stage

    -- The slab's edge is the same ellipse again, a little lower and darker;
    -- the floor laid over it leaves a crescent showing along the front
    G.Disc(stage, "BACKGROUND", 1, L.floorA * 2, L.floorB * 2, L.floorX, L.floorY - L.slab, 0.13, 0.11, 0.09)
    G.floor = G.Disc(stage, "BACKGROUND", 2, L.floorA * 2, L.floorB * 2, L.floorX, L.floorY, 0.37, 0.32, 0.25)
    G.Disc(stage, "BACKGROUND", 3, L.floorA * 1.4, L.floorB * 1.4, L.floorX, L.floorY, 0.41, 0.36, 0.28)

    G.pillars = {
        G.BuildPillar(stage, L.floorX - L.pillarX, L.floorY + L.pillarY),
        G.BuildPillar(stage, L.floorX + L.pillarX, L.floorY + L.pillarY),
    }

    G.burst = stage:CreateTexture(nil, "ARTWORK", nil, 1)
    G.burst:SetTexture(ART.rim)
    G.burst:SetVertexColor(0.80, 0.93, 1.00)
    G.burst:Hide()

    -- Above every token, whatever their order: numbers, projectiles, spell
    -- call-outs and the banner. G.Restack gives it and the tokens their
    -- levels.
    local overlay = CreateFrame("Frame", nil, stage)
    overlay:SetAllPoints(stage)
    G.overlay = overlay

    G.tokens, G.order = {}, {}
    for id = 1, #DATA.TEAMS.A + #DATA.TEAMS.B do
        local token = G.NewToken(id)
        G.tokens[id], G.order[id] = token, token
    end

    G.numbers = {}
    for index = 1, L.numbers do
        local fs = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:Hide()
        G.numbers[index] = fs
    end
    G.shots = {}
    for index = 1, L.shots do
        G.shots[index] = G.NewSpellIcon(overlay, "ARTWORK", 1, 18)
    end

    G.BuildBar(stage, overlay)

    G.bannerBand = overlay:CreateTexture(nil, "BORDER")
    G.bannerBand:SetColorTexture(0, 0, 0, 0.55)
    G.bannerBand:SetSize(L.width - 8, 58)
    G.bannerBand:SetPoint("CENTER", overlay, "BOTTOMLEFT", L.floorX, L.floorY + 20)
    G.bannerBand:Hide()
    G.banner = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    G.banner:SetFont(FONT, 34, "OUTLINE")
    G.banner:SetPoint("CENTER", G.bannerBand, "CENTER", 0, 0)
    G.banner:Hide()
end

-- The bar, the hint either side of it, and the line that counts the gates
-- down.
function G.BuildBar(stage, overlay)
    G.buttons = {}
    local count = #DATA.TEAMS[HAND]
    for slot = 1, count do
        G.buttons[slot] = G.NewButton(L.floorX + (slot - (count + 1) / 2) * L.buttonGap)
    end

    -- Each half is given a width as well, so that a font wider than the
    -- lines were broken for still wraps inside its corner, and is set
    -- against the bar
    local reach = (count - 1) / 2 * L.buttonGap + L.rim / 2 + L.hintGap
    G.hints = {}
    for index, text in ipairs(G.HINT) do
        local left = index == 1
        local half = stage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        half:SetWidth(L.hintWidth)
        half:SetJustifyH(left and "RIGHT" or "LEFT")
        half:SetPoint(left and "RIGHT" or "LEFT", stage, "BOTTOMLEFT", L.floorX + (left and -reach or reach), L.barY)
        half:SetText(text)
        G.hints[index] = half
    end

    G.count = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    G.count:SetFont(FONT, 16, "OUTLINE")
    G.count:SetPoint("CENTER", overlay, "BOTTOMLEFT", L.floorX, L.floorY + L.countY)
    G.count:Hide()
end

function G.BuildHeader(window)
    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -9)
    title:SetText("Commander Gladiator")

    G.record = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    G.record:SetPoint("TOP", window, "TOP", 0, -10)

    local line = window:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.08)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", window, "TOPLEFT", 6, -L.header)
    line:SetPoint("TOPRIGHT", window, "TOPRIGHT", -6, -L.header)

    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", window, "TOPRIGHT", 2, 2)

    -- The same setting the settings page carries, one click away from the
    -- match it changes. It goes through the module's update event so the
    -- page and the button can never disagree.
    local speed = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    speed:SetSize(36, 20)
    speed:SetPoint("TOPRIGHT", window, "TOPRIGHT", -30, -4)
    speed:SetScript("OnClick", function()
        CommanderGladiatorDB.Speed = G.Speed() == 2 and 1 or 2
        Commander.Notify(COMMANDER_GLADIATOR_EVENTS.UPDATE)
    end)
    Commander.UI.AttachTooltip(speed, "Match Speed", "Flip between normal and double speed.")
    G.speedButton = speed

    -- How much healing is left, or who has been routed: see G.PaintHealing.
    -- Beside the record, in the gap before the speed button, and empty until
    -- there is something to say.
    G.healing = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    G.healing:SetPoint("LEFT", G.record, "RIGHT", 14, 0)
    G.healing:Hide()
end

function G.Build()
    local window = CreateFrame("Frame", WINDOW_NAME, UIParent)
    window:SetSize(L.width, L.height)
    window:SetFrameStrata("MEDIUM")
    window:SetToplevel(true)
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        if point then CommanderGladiatorDB.Pos = { point = point, x = x, y = y } end
    end)
    window:Hide()
    -- The suite's dark panel, as on the Debug and Telemetry windows. It is a
    -- tint and the world shows through it, which does not matter here: the
    -- floor is its own background
    Commander.UI.ApplyStyleBackdrop(window, "DARK")
    -- Escape closes it. Added to, never assigned: assigning a FrameXML
    -- global taints it for every secure reader after
    if UISpecialFrames then table.insert(UISpecialFrames, WINDOW_NAME) end

    local pos = CommanderGladiatorDB.Pos
    if pos and pos.point then
        window:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 0)
    else
        window:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end

    G.window = window
    G.BuildHeader(window)
    G.BuildStage(window)
    G.Apply()
    G.ShowRecord()

    -- A match in progress when the window was closed is still there, frozen
    -- on the tick it was closed on; only the very first opening deals one
    window:SetScript("OnShow", function()
        if not S.match then G.Deal() end
    end)
    window:SetScript("OnUpdate", G.OnUpdate)
    return window
end

-- The settings changed, here or on the settings page.
function G.Apply()
    if not G.window then return end
    G.speedButton:SetText(G.Speed() .. "x")
    G.ShowHint()
    if not CommanderGladiatorDB.Enabled then G.window:Hide() end
end

-- /cglad. The window is built the first time it is asked for, so somebody
-- who never plays pays for none of it. It never opens by itself.
function G.Toggle()
    if not CommanderGladiatorDB.Enabled then
        print("Commander Gladiator is switched off -- /cglad settings turns it back on")
        return
    end
    local window = G.window or G.Build()
    if window:IsShown() then
        window:Hide()
    else
        window:Show()
    end
end

Commander.AddListener(COMMANDER_GLADIATOR_EVENTS.UPDATE, G.Apply)
