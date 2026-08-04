-- Commander Casting — portrait rings.
--
-- A cast bar's job is to tell you how long is left. Blizzard's answer puts that
-- answer at the bottom of the screen, and your target's answer under their
-- frame — both a long way from the portrait you are actually looking at, and
-- both costing screen real estate that a fight has better uses for.
--
-- This draws the cast as an arc around the trim of the portrait instead. The
-- player's ring reports your cast; the target's ring reports theirs, which is
-- the one that matters when you are holding an interrupt. Nothing new is added
-- to the screen: the arc rides a rim that was already there.
--
-- Cheapness matters, because both rings can be live at once in a fight. The
-- sweeps are Cooldown frames, which the client animates for free — the OnUpdate
-- loop here only runs while something is actually casting or flashing, and the
-- text on it is dirty-checked at 20Hz rather than redrawn per frame.

local TEXTURES = "Interface\\AddOns\\Commander_Casting\\Textures\\"

-- Six ring weights, thinnest first. Thickness is baked into the art as a
-- proportion of the texture, so the addon picks the weight closest to the
-- requested pixel thickness at whatever size the ring has ended up.
local RING_FILES = {
    TEXTURES .. "Ring1.png", TEXTURES .. "Ring2.png", TEXTURES .. "Ring3.png",
    TEXTURES .. "Ring4.png", TEXTURES .. "Ring5.png", TEXTURES .. "Ring6.png",
}
local RING_RATIOS = { 0.93, 0.88, 0.80, 0.71, 0.60, 0.46 }
-- The donut's outer radius as a fraction of the texture's width
local RING_OUTER = 0.485

local GLOW_FILE = TEXTURES .. "RingGlow.png"
local TICK_FILE = TEXTURES .. "Tick.png"
local EDGE_FILE = TEXTURES .. "Edge.png"

-- Half-length of the spark's flat-alpha core, as a fraction of its texture
-- (mirrored from Harness/make_rings.py, where the art also fades out over
-- another 0.06 past each end). Sizing the quad by this lands the core exactly
-- on the ring band: the spark is cut off at the band's own thickness, and only
-- a tenth of that thickness in falloff spills past the rim.
local EDGE_CORE = 0.30
-- Blizzard's own round portrait mask, used as art: a clean disc the exact
-- shape of the portrait, so a tint never spills over the frame's metal
local PORTRAIT_DISC = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local TEXT_INTERVAL = 1 / 20     -- dirty-checked label / marker refresh
local TEST_DURATION = 3

local function DB(key, default)
    local value = CommanderCastingDB and CommanderCastingDB[key]
    if value == nil then return default end
    return value
end

local function Color(name, fallback)
    local colors = COMMANDER_CASTING_COLORS
    local color = colors[name] or colors[fallback or "GOLD"]
    return color[1], color[2], color[3]
end

local SCHOOL_COLORS = {
    Frost = "ICE", Nature = "VERDANT", Holy = "GOLD",
    Fire = "EMBER", Shadow = "VOID", Arcane = "ARCANE",
}

-- One halo, three meanings, all of them "the cast just ended, and how"
local FLASH_KINDS = {
    SUCCESS  = { color = "VERDANT", duration = 0.35, grow = 0.5 },
    FAIL     = { color = "BLOOD",   duration = 0.5,  grow = 0.25 },
    PUSHBACK = { color = "EMBER",   duration = 0.3,  grow = 0.15 },
}

-- ---------------------------------------------------------------------------
-- The two rings. Everything below is written once and driven from this table,
-- so the player's ring and the target's can never drift apart in behavior --
-- only in the settings they read.
-- ---------------------------------------------------------------------------

local RING_ORDER = { "player", "target" }

local SPECS = {
    player = {
        unit = "player",
        prefix = "PlayerRing",
        globalName = "CommanderCastingPlayerRing",
        extras = true,                 -- latency tick and the cooldown ring
        Parent = function() return PlayerFrame end,
        Portrait = function() return PlayerPortrait end,
        -- PlayerFrame draws its own art in layers, so any child frame already
        -- sits above it; the level is taken from the frame itself
        LevelSource = function() return PlayerFrame end,
    },
    target = {
        unit = "target",
        prefix = "TargetRing",
        globalName = "CommanderCastingTargetRing",
        Parent = function() return TargetFrame end,
        Portrait = function() return TargetFramePortrait end,
        -- TargetFrame's border art lives on a child frame, so the ring has to
        -- clear that one rather than the frame underneath it
        LevelSource = function() return TargetFrameTextureFrame or TargetFrame end,
    },
}

local rings = {}
for _, key in ipairs(RING_ORDER) do
    rings[key] = {
        spec = SPECS[key],
        built = false,
        laid = {},
        cast = { active = false, channel = false, test = false, name = nil, start = 0, finish = 0 },
        flashKind = nil,
        flashStart = 0,
        lastLabel = "",
    }
end

local gcdStart, gcdDuration = 0, 0

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

local function ClearSweep(cooldown)
    if not cooldown then return end
    if cooldown.Clear then
        cooldown:Clear()
    else
        cooldown:SetCooldown(0, 0)
    end
end

local function NewSweep(parent, level)
    local sweep = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
    sweep:EnableMouse(false)
    sweep:SetFrameLevel(level)
    if sweep.SetHideCountdownNumbers then sweep:SetHideCountdownNumbers(true) end
    if sweep.SetDrawBling then sweep:SetDrawBling(false) end
    if sweep.SetDrawSwipe then sweep:SetDrawSwipe(true) end
    -- The Cooldown's own edge is a spoke drawn from the center of the frame out
    -- to its rim, and nothing masks it: on a donut it lays a bright line right
    -- across the portrait. The arc draws its own spark instead (UpdateEdge).
    if sweep.SetDrawEdge then sweep:SetDrawEdge(false) end
    if sweep.SetSwipeTexture then sweep:SetSwipeTexture(RING_FILES[3]) end
    sweep:Hide()
    return sweep
end

local function Build(ring)
    if ring.built then return true end
    local spec = ring.spec
    local parent, portrait = spec.Parent(), spec.Portrait()
    if not (parent and portrait) then return false end

    local source = spec.LevelSource() or parent
    local base = (source.GetFrameLevel and source:GetFrameLevel()) or 1

    local holder = CreateFrame("Frame", spec.globalName, parent)
    holder:EnableMouse(false)           -- never eats a click on the unit frame
    holder:SetFrameLevel(base + 5)
    holder:Hide()
    ring.holder = holder

    -- The wash over the portrait itself, anchored to the portrait rather than
    -- to the ring so growing the ring never grows the tint
    ring.tint = holder:CreateTexture(nil, "BACKGROUND")
    ring.tint:SetTexture(PORTRAIT_DISC)
    ring.tint:SetBlendMode("ADD")
    ring.tint:SetPoint("TOPLEFT", portrait, "TOPLEFT", 0, 0)
    ring.tint:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 0, 0)
    ring.tint:Hide()

    -- The empty circle the sweep runs around
    ring.track = holder:CreateTexture(nil, "ARTWORK")
    ring.track:SetAllPoints(holder)
    ring.track:Hide()

    ring.arc = NewSweep(holder, base + 6)
    ring.arc:SetAllPoints(holder)

    if spec.extras then
        ring.gcd = NewSweep(holder, base + 7)
        ring.gcd:SetPoint("CENTER", holder, "CENTER")
    end

    -- Everything that must never be eaten by the sweep sits on its own frame
    local overlay = CreateFrame("Frame", nil, holder)
    overlay:SetAllPoints(holder)
    overlay:SetFrameLevel(base + 15)
    ring.overlay = overlay

    ring.glow = overlay:CreateTexture(nil, "OVERLAY")
    ring.glow:SetTexture(GLOW_FILE)
    ring.glow:SetBlendMode("ADD")
    ring.glow:SetPoint("CENTER", holder, "CENTER")
    ring.glow:Hide()

    -- The head of the sweep. Above the arc so it reads as a spark on top of the
    -- fill rather than a notch cut out of it.
    ring.edge = overlay:CreateTexture(nil, "OVERLAY")
    ring.edge:SetTexture(EDGE_FILE)
    ring.edge:SetBlendMode("ADD")
    ring.edge:Hide()

    if spec.extras then
        ring.tick = overlay:CreateTexture(nil, "OVERLAY")
        ring.tick:SetTexture(TICK_FILE)
        ring.tick:Hide()
    end

    ring.label = overlay:CreateFontString(nil, "OVERLAY")
    ring.label:SetFont(FONT, 12, "OUTLINE")
    ring.label:Hide()

    ring.built = true
    return true
end

-- ---------------------------------------------------------------------------
-- Geometry. Only touched when a size setting actually changed: the signature
-- below is every number the layout depends on.
-- ---------------------------------------------------------------------------

-- Nearest ring weight for a requested pixel thickness at a given frame size
local function RingTexture(frameSize, thickness)
    local outer = frameSize * RING_OUTER
    if outer <= 0 then return RING_FILES[3], RING_RATIOS[3] end
    local wanted = 1 - (thickness / outer)
    local best, bestDiff = 3, math.huge
    for i = 1, #RING_RATIOS do
        local diff = math.abs(RING_RATIOS[i] - wanted)
        if diff < bestDiff then best, bestDiff = i, diff end
    end
    return RING_FILES[best], RING_RATIOS[best]
end

local function Layout(ring)
    local spec = ring.spec
    local prefix = spec.prefix
    local portrait = spec.Portrait()

    -- The portrait is 64px on both frames, but read it rather than assume it:
    -- a unit-frame skin is free to resize the art underneath us
    local portraitSize = (portrait and portrait:GetWidth()) or 0
    if not portraitSize or portraitSize <= 0 then portraitSize = 64 end

    local frameSize = portraitSize * DB(prefix .. "Scale", 1.14)
    local thickness = DB(prefix .. "Thickness", 5)
    local offsetX, offsetY = DB(prefix .. "OffsetX", 0), DB(prefix .. "OffsetY", 0)
    local textSize = DB(prefix .. "TextSize", 12)
    local textPlace = DB(prefix .. "TextPlace", "BELOW")
    local gcdThickness = DB(prefix .. "GCDThickness", 3)
    local gcdPlace = DB(prefix .. "GCDPlacement", "INSIDE")

    local signature = string.format("%.2f:%d:%d:%d:%d:%s:%d:%s",
        frameSize, thickness, offsetX, offsetY, textSize, textPlace, gcdThickness, gcdPlace)
    if ring.laid.signature == signature then return end
    ring.laid.signature = signature

    ring.holder:SetSize(frameSize, frameSize)
    ring.holder:ClearAllPoints()
    ring.holder:SetPoint("CENTER", portrait, "CENTER", offsetX, offsetY)

    local file, ratio = RingTexture(frameSize, thickness)
    ring.laid.ratio = ratio
    ring.laid.frameSize = frameSize
    if ring.arc.SetSwipeTexture then ring.arc:SetSwipeTexture(file) end
    ring.track:SetTexture(file)

    -- What the band on screen actually measures, which is near the requested
    -- thickness but rarely equal to it: the weight is the nearest of six.
    -- Anything riding the band has to measure it rather than trust the setting,
    -- or it sits off the ring by the rounding.
    local outer = frameSize * RING_OUTER
    local band = outer * (1 - ratio)
    ring.laid.band = band
    ring.laid.radius = outer - band / 2

    -- Core as long as the band is thick; the art's falloff does the rest
    local edgeSize = band / (EDGE_CORE * 2)
    ring.edge:SetSize(edgeSize, edgeSize)

    ring.glow:SetSize(frameSize * 1.3, frameSize * 1.3)

    ring.label:SetFont(FONT, textSize, "OUTLINE")
    ring.label:ClearAllPoints()
    if textPlace == "CENTER" then
        ring.label:SetPoint("CENTER", ring.holder, "CENTER", 0, 0)
    elseif textPlace == "ABOVE" then
        ring.label:SetPoint("BOTTOM", ring.holder, "TOP", 0, 2)
    else
        ring.label:SetPoint("TOP", ring.holder, "BOTTOM", 0, -2)
    end

    if ring.gcd then
        -- Both placements come down to "where should this ring's outer edge
        -- land"; the weight of art is then chosen for the pixel thickness.
        local gcdSize
        if gcdPlace == "OUTSIDE" then
            gcdSize = (frameSize * RING_OUTER + 1 + gcdThickness) / RING_OUTER
        else
            local hole = frameSize * RING_OUTER * ratio
            gcdSize = math.max(8, (hole - 1) / RING_OUTER)
        end
        ring.gcd:SetSize(gcdSize, gcdSize)
        if ring.gcd.SetSwipeTexture then
            ring.gcd:SetSwipeTexture((RingTexture(gcdSize, gcdThickness)))
        end
    end
end

-- ---------------------------------------------------------------------------
-- Color
-- ---------------------------------------------------------------------------

local function ReactionColor(unit)
    if unit and UnitExists(unit) then
        if UnitCanAttack("player", unit) then
            return Color("BLOOD")
        elseif UnitIsFriend("player", unit) then
            return Color("VERDANT")
        end
    end
    return Color("GOLD")
end

local function ArcColor(ring)
    local prefix = ring.spec.prefix
    local unit = ring.spec.unit
    local mode = DB(prefix .. "ColorMode", "SCHOOL")

    if mode == "FIXED" then
        return Color(DB(prefix .. "Color", "GOLD"))
    elseif mode == "REACTION" then
        return ReactionColor(unit)
    elseif mode == "CLASS" then
        -- Anything that is not a player has no class color to take, so it
        -- falls back to the reading that always means something: reaction
        if unit == "player" or (UnitExists(unit) and UnitIsPlayer(unit)) then
            local _, token = UnitClass(unit)
            local info = Commander.GetClassInfo and Commander.GetClassInfo(token)
            if info and info.color then
                return info.color[1], info.color[2], info.color[3]
            end
        end
        return ReactionColor(unit)
    end

    local school = CommanderCasting_SchoolOf(ring.cast.name)
    return Color(SCHOOL_COLORS[school] or "GOLD")
end

-- ---------------------------------------------------------------------------
-- Cast state
-- ---------------------------------------------------------------------------

local function ReadCast(ring)
    local unit = ring.spec.unit
    local cast = ring.cast

    local name, _, _, startMS, endMS = UnitCastingInfo(unit)
    local channel = false
    if not name then
        local channelName, _, _, channelStart, channelEnd = UnitChannelInfo(unit)
        if channelName then
            name, startMS, endMS, channel = channelName, channelStart, channelEnd, true
        end
    end

    if not name or not startMS or not endMS then
        -- A pretend cast is only ever ended by its own clock, never by the
        -- absence of a real one
        if cast.active and not cast.test then
            cast.active, cast.channel, cast.name = false, false, nil
        end
        return
    end

    cast.active, cast.test, cast.channel = true, false, channel
    cast.name = name
    cast.start, cast.finish = startMS / 1000, endMS / 1000
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

local function GCDActive()
    return gcdDuration > 0 and (GetTime() - gcdStart) < gcdDuration
end

local function ApplyGCD(ring)
    local gcd = ring.gcd
    if not gcd then return end
    if not (DB(ring.spec.prefix .. "GCD", false) and GCDActive()) then
        ClearSweep(gcd)
        gcd:Hide()
        return
    end
    -- It is a cooldown; it should unwind like one, whatever the cast arc does
    if gcd.SetReverse then gcd:SetReverse(false) end
    local r, g, b = Color(DB(ring.spec.prefix .. "GCDColor", "STEEL"))
    if gcd.SetSwipeColor then gcd:SetSwipeColor(r, g, b, 1) end
    gcd:SetCooldown(gcdStart, gcdDuration)
    gcd:Show()
end

-- Where the sweep's head is right now, as a share of the cast. Both fill
-- directions put the boundary between drawn and undrawn in the same place --
-- reversing only swaps which side of it is painted -- so one angle serves both.
local function CastProgress(cast)
    local duration = cast.finish - cast.start
    if duration <= 0 then return nil end
    local progress = (GetTime() - cast.start) / duration
    if progress < 0 then return 0 end
    if progress > 1 then return 1 end
    return progress
end

-- Ride the spark on the head of the sweep. Called every frame while a cast is
-- live -- the arc itself is animated by the client, and this is the one piece
-- of it the client will not move for us.
local function MoveEdge(ring)
    if not ring.edgeLive then return end
    local progress = CastProgress(ring.cast)
    if not progress then return end
    -- Clockwise from twelve o'clock, the same convention as the latency tick
    local theta = progress * math.pi * 2
    local radius = ring.laid.radius or 0
    ring.edge:SetPoint("CENTER", ring.overlay, "CENTER",
        math.sin(theta) * radius, math.cos(theta) * radius)
    ring.edge:SetRotation(-theta)
end

local function UpdateEdge(ring, casting, r, g, b)
    if not (casting and DB(ring.spec.prefix .. "Edge", true)) then
        ring.edgeLive = false
        ring.edge:Hide()
        return
    end
    -- Halfway to white: a spark reads as heat coming off the arc, not as more
    -- of the same color laid over it
    ring.edge:SetVertexColor((r + 1) / 2, (g + 1) / 2, (b + 1) / 2)
    ring.edgeLive = true
    MoveEdge(ring)
    ring.edge:Show()
end

-- The point in the cast where the next one can already be queued
local function UpdateLatency(ring)
    local tick = ring.tick
    if not tick then return end
    local cast = ring.cast
    if not (DB(ring.spec.prefix .. "Latency", false) and cast.active and not cast.channel) then
        tick:Hide()
        return
    end
    local duration = cast.finish - cast.start
    local latency = 0
    if GetNetStats then
        local _, _, _, world = GetNetStats()
        latency = (world or 0) / 1000
    end
    if duration <= 0 or latency <= 0 or latency >= duration then
        tick:Hide()
        return
    end
    -- Angles run clockwise from twelve o'clock, matching the sweep
    local theta = (1 - latency / duration) * math.pi * 2
    local band = ring.laid.band or 5
    local radius = ring.laid.radius or 0
    local size = band + 6
    tick:SetSize(size, size)
    tick:SetPoint("CENTER", ring.overlay, "CENTER",
        math.sin(theta) * radius, math.cos(theta) * radius)
    tick:SetRotation(-theta)
    tick:SetVertexColor(Color("BONE"))
    tick:Show()
end

local function UpdateLabel(ring)
    local prefix = ring.spec.prefix
    local mode = DB(prefix .. "Text", "NONE")
    local cast = ring.cast
    if mode == "NONE" or not cast.active then
        if ring.label:IsShown() then ring.label:Hide() end
        ring.lastLabel = ""
        return
    end

    local text
    if mode == "TIME" then
        local remaining = cast.finish - GetTime()
        if remaining < 0 then remaining = 0 end
        text = string.format("%.1f", remaining)
    else
        text = cast.name
    end
    if not text then
        ring.label:Hide()
        ring.lastLabel = ""
        return
    end

    -- SetText on every tick is pure churn; the seconds only change 10x a second
    if text ~= ring.lastLabel then
        ring.lastLabel = text
        ring.label:SetText(text)
    end
    ring.label:SetTextColor(ArcColor(ring))
    if not ring.label:IsShown() then ring.label:Show() end
end

local function RenderFlash(ring)
    if not ring.flashKind then return end
    local spec = FLASH_KINDS[ring.flashKind]
    local progress = (GetTime() - ring.flashStart) / spec.duration
    if progress >= 1 then
        ring.flashKind = nil
        ring.glow:Hide()
        return
    end
    local size = (ring.laid.frameSize or 64) * (1.3 + spec.grow * progress)
    ring.glow:SetSize(size, size)
    ring.glow:SetAlpha((1 - progress) * 0.85)
end

local ApplyRing    -- forward declaration: the driver below closes over it

local function Flash(ring, kind)
    if not ring.built then return end
    local spec = FLASH_KINDS[kind]
    if not spec then return end
    ring.flashKind, ring.flashStart = kind, GetTime()
    ring.glow:SetVertexColor(Color(spec.color))
    ring.glow:SetAlpha(0.85)
    ring.glow:Show()
end

function ApplyRing(ring)
    if not Build(ring) then return end
    local prefix = ring.spec.prefix

    if not (DB("EnablePortraitRings", true) and DB(prefix .. "Enabled", true)) then
        ClearSweep(ring.arc)
        ClearSweep(ring.gcd)
        ring.flashKind = nil
        ring.edgeLive = false
        ring.holder:Hide()
        return
    end

    Layout(ring)

    local cast = ring.cast
    local duration = cast.finish - cast.start
    local casting = cast.active and duration > 0
    local always = DB(prefix .. "ShowWhen", "CASTING") == "ALWAYS"
    local gcdWants = ring.gcd and DB(prefix .. "GCD", false) and GCDActive()

    if not (casting or always or ring.flashKind or gcdWants) then
        ClearSweep(ring.arc)
        ClearSweep(ring.gcd)
        ring.edgeLive = false
        ring.holder:Hide()
        return
    end

    ring.holder:SetAlpha(DB(prefix .. "Opacity", 1))
    ring.holder:Show()

    -- The empty circle belongs to the cast arc, so it comes up with it -- a
    -- ring on screen for the cooldown sweep alone does not drag it along
    if (casting or always) and DB(prefix .. "Track", true) then
        ring.track:SetVertexColor(0.55, 0.55, 0.60, DB(prefix .. "TrackOpacity", 0.25))
        ring.track:Show()
    else
        ring.track:Hide()
    end

    local r, g, b = ArcColor(ring)

    if casting then
        local fill
        if cast.channel then
            fill = DB(prefix .. "ChannelFill", false)
        else
            fill = DB(prefix .. "CastFill", true)
        end
        if ring.arc.SetReverse then ring.arc:SetReverse(fill and true or false) end
        if ring.arc.SetSwipeColor then ring.arc:SetSwipeColor(r, g, b, 1) end
        ring.arc:SetCooldown(cast.start, duration)
        ring.arc:Show()
    else
        ClearSweep(ring.arc)
        ring.arc:Hide()
    end

    UpdateEdge(ring, casting, r, g, b)

    if casting and DB(prefix .. "Tint", false) then
        ring.tint:SetVertexColor(r, g, b, DB(prefix .. "TintStrength", 0.25))
        ring.tint:Show()
    else
        ring.tint:Hide()
    end

    ApplyGCD(ring)
    UpdateLatency(ring)
    UpdateLabel(ring)
end

-- ---------------------------------------------------------------------------
-- The driver: only alive while something is actually moving
-- ---------------------------------------------------------------------------

local driver = CreateFrame("Frame")
driver:Hide()
local sinceText = 0

local function Busy()
    for i = 1, #RING_ORDER do
        local ring = rings[RING_ORDER[i]]
        if ring.cast.active or ring.flashKind then return true end
    end
    return GCDActive()
end

local function Wake()
    if driver:IsShown() then return end
    sinceText = TEXT_INTERVAL      -- the first frame reads live data, not stale
    driver:Show()
end

driver:SetScript("OnUpdate", function(_, elapsed)
    -- Per frame, both of them: a spark that only moved with the label would
    -- stutter around a ring the client is drawing smoothly underneath it
    for i = 1, #RING_ORDER do
        local ring = rings[RING_ORDER[i]]
        RenderFlash(ring)
        MoveEdge(ring)
    end

    sinceText = sinceText + elapsed
    if sinceText >= TEXT_INTERVAL then
        sinceText = 0
        local now = GetTime()
        for i = 1, #RING_ORDER do
            local ring = rings[RING_ORDER[i]]
            if not ring.built then
                -- nothing to do until the unit frame exists
            elseif ring.cast.active and now >= ring.cast.finish then
                -- A cast's own events normally end it, and pushback pushes
                -- this moment back before it arrives. The clock is the
                -- backstop for the case that sends nothing: a unit that
                -- stops existing mid-cast, which would otherwise leave an
                -- arc sweeping around a portrait forever.
                if not ring.cast.test then ReadCast(ring) end
                if ring.cast.finish <= now then
                    ring.cast.active, ring.cast.test = false, false
                end
                ApplyRing(ring)
            elseif ring.cast.active then
                UpdateLatency(ring)
                UpdateLabel(ring)
            end
        end
        if gcdDuration > 0 and not GCDActive() then
            gcdDuration = 0
            for i = 1, #RING_ORDER do
                ApplyGCD(rings[RING_ORDER[i]])
            end
            ApplyRing(rings.player)
        end
    end

    if not Busy() then
        driver:Hide()
        -- Whatever was only on screen for the cast comes down with it
        for i = 1, #RING_ORDER do
            ApplyRing(rings[RING_ORDER[i]])
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Blizzard's own cast bars. Hidden by hooking OnShow rather than by tearing
-- their events off, so switching the option back off hands the bar straight
-- back to Blizzard -- it simply reappears on the next cast.
-- ---------------------------------------------------------------------------

local BLIZZARD_BARS = {
    -- The player has two: the managed bar above the action bars, and the
    -- centered overlay the "cast bar underneath the character" option uses
    { key = "HidePlayerCastBar", Frames = function()
        return PlayerCastingBarFrame, OverlayPlayerCastingBarFrame, CastingBarFrame
    end },
    { key = "HideTargetCastBar", Frames = function()
        return TargetFrameSpellBar, TargetFrame and TargetFrame.spellbar
    end },
}

-- Frame globals differ by client and some of these are the same frame twice,
-- so the list is built by hand: a nil in the middle would silently truncate an
-- ipairs walk over a table constructor.
local function CollectBars(...)
    local bars = {}
    for i = 1, select("#", ...) do
        local bar = select(i, ...)
        if bar and bar.HookScript and not bars[bar] then
            bars[bar] = true
            bars[#bars + 1] = bar
        end
    end
    return bars
end

local function ApplyBarHiding()
    for i = 1, #BLIZZARD_BARS do
        local entry = BLIZZARD_BARS[i]
        local hide = DB(entry.key, false) and true or false
        local bars = CollectBars(entry.Frames())
        for b = 1, #bars do
            local bar = bars[b]
            if not bar.commanderCastingHooked then
                bar.commanderCastingHooked = true
                bar:HookScript("OnShow", function(self)
                    if DB(entry.key, false) then self:Hide() end
                end)
            end
            if hide and bar:IsShown() then bar:Hide() end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Tester: a pretend cast on both rings, so every option on the page can be
-- judged without waiting for a fight to hand you one.
-- ---------------------------------------------------------------------------

local TEST_SPELLS = {
    "Greater Heal", "Frostbolt", "Immolate", "Shadow Bolt", "Lightning Bolt", "Arcane Missiles",
}
local testIndex = 0

local function StartTestCast(ring, name)
    local cast = ring.cast
    cast.active, cast.test, cast.channel = true, true, false
    cast.name = name
    cast.start = GetTime()
    cast.finish = cast.start + TEST_DURATION
    ApplyRing(ring)
end

function CommanderCasting_TestRings()
    if not DB("EnablePortraitRings", true) then
        print("Commander Casting: portrait rings are disabled (enable them in settings or /cring)")
        return
    end
    local player = DB("PlayerRingEnabled", true)
    local target = DB("TargetRingEnabled", true)
    if not (player or target) then
        print("Commander Casting: both portrait rings are switched off — nothing to test")
        return
    end

    testIndex = testIndex % #TEST_SPELLS + 1
    local name = TEST_SPELLS[testIndex]
    if player then StartTestCast(rings.player, name) end
    if target then StartTestCast(rings.target, name) end
    Wake()

    print(string.format("Commander Casting: test cast — %s, %d seconds. Change any setting and watch it take effect live.",
        name, TEST_DURATION))
    if target and not UnitExists("target") then
        print("Commander Casting: no target — the target ring has no portrait to draw on yet.")
    end
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------

local function ApplyAll()
    for i = 1, #RING_ORDER do
        ApplyRing(rings[RING_ORDER[i]])
    end
    ApplyBarHiding()
    if Busy() then Wake() end
end

-- UNIT_SPELLCAST_SUCCEEDED carries the spell that just went off, and its
-- cooldown is the global cooldown whenever it is short enough to be one.
local function ReadGCD(spellID)
    if not (spellID and GetSpellCooldown) then return end
    local ok, start, duration = pcall(GetSpellCooldown, spellID)
    if not ok or not start or not duration then return end
    if duration > 0 and duration <= 1.5 then
        gcdStart, gcdDuration = start, duration
        return true
    end
    return false
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("UNIT_SPELLCAST_START")
events:RegisterEvent("UNIT_SPELLCAST_STOP")
events:RegisterEvent("UNIT_SPELLCAST_FAILED")
events:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
events:RegisterEvent("UNIT_SPELLCAST_DELAYED")
events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
events:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
events:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

events:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if event == "PLAYER_LOGIN" then
        Commander.AddListener(COMMANDER_CASTING_EVENTS.UPDATE, ApplyAll)
        -- Logging in or reloading mid-cast still gets an arc
        for i = 1, #RING_ORDER do
            ReadCast(rings[RING_ORDER[i]])
        end
        ApplyAll()
        return
    end

    if event == "PLAYER_TARGET_CHANGED" then
        -- A new target is a different cast (usually none at all), and the
        -- pretend one belonged to whoever was standing there before
        rings.target.cast.test = false
        rings.target.cast.active = false
        rings.target.flashKind = nil
        ReadCast(rings.target)
        ApplyRing(rings.target)
        if Busy() then Wake() end
        return
    end

    local key = (unit == "player" and "player") or (unit == "target" and "target") or nil
    if not key then return end
    local ring = rings[key]
    local prefix = ring.spec.prefix

    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        ReadCast(ring)
        ApplyRing(ring)
        Wake()
        return
    end

    -- Feedback reads the state the cast was in BEFORE this event resolves it,
    -- so an instant that never had an arc never gets a flash. Success is the
    -- one that also excludes channels: a channel reports itself as succeeded
    -- the moment it starts, which is the opposite of what the flash means.
    local wasActive = ring.cast.active and not ring.cast.test
    local wasCasting = wasActive and not ring.cast.channel
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Gated on the option: reading a global cooldown nobody asked to see
        -- would wake the driver for a second and a half after every spell
        if key == "player" and DB("PlayerRingGCD", false) and ReadGCD(spellID) then
            ApplyGCD(rings.player)
        end
        if wasCasting and DB(prefix .. "SuccessFlash", false) then Flash(ring, "SUCCESS") end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
        if wasActive and DB(prefix .. "FailFlash", true) then Flash(ring, "FAIL") end
    elseif event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        if wasActive and DB(prefix .. "PushbackFlash", false) then Flash(ring, "PUSHBACK") end
    end

    ReadCast(ring)
    ApplyRing(ring)
    if Busy() then Wake() end
end)
