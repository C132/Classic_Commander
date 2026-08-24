-- Commander Momentum: a decaying kill-streak meter. Killing blows (CLEU
-- PARTY_KILL with the player as source) push the streak up and refill the
-- drain bar; when the bar empties the streak is gone. Colors escalate at
-- milestones. Shown only while a streak of 2+ is alive, so the HUD stays
-- clean between pulls. Best chains persist per zone/instance, and the end
-- of a session-best chain recaps how it stacks against those records.

local BAR_WIDTH = 120
local BAR_HEIGHT = 8

local streak = 0
local lastKill = -math.huge
local announcedMilestone = 0
local totalKills = 0        -- session-wide, for the milestone brags
local bestStreak = 0
local streakStart = 0       -- GetTime when the current streak began
local testFeeding = false   -- the tester never sends public emotes
local streakIsTest = false  -- chain fed only by the tester: no break lament
local session   -- reload-resilient mirror of the state above

-- Chain record bookkeeping: which zone the live chain is scoring in and
-- what the records were before it started, so the end-of-chain recap can
-- tell "broke the record" from "the record stands".
local chainZone            -- zone/instance name of the chain's latest kill
local chainZoneBase = 0    -- that zone's record before this chain touched it
local chainAllTimeBase = 0 -- the all-time high before this chain began
local chainAllTimeBaseZone -- ...and the zone that held it
local chainBasesCaptured = false

local function SyncSession()
    if session then
        session.streak = streak
        session.milestone = announcedMilestone
        session.lastKillEpoch = (streak > 0) and time() or 0
        session.totalKills = totalKills
        session.bestStreak = bestStreak
        session.streakStartEpoch = (streak > 0)
            and (time() - math.floor(GetTime() - streakStart)) or 0
        session.chainZone = chainZone or false
        session.chainZoneBase = chainZoneBase
        session.chainAllTimeBase = chainAllTimeBase
        session.chainAllTimeBaseZone = chainAllTimeBaseZone or false
        session.chainBasesCaptured = chainBasesCaptured
    end
end

-- ---------------------------------------------------------------------------
-- Zone records: the best chain ever landed in each zone or instance, kept
-- in CommanderMomentumDB.Records — deliberately outside DefaultSettings so
-- a settings reset never erases history. Written live on each kill (a
-- crash can't eat a record); the celebration waits for the chain to end.
-- ---------------------------------------------------------------------------

local function Records()
    if not CommanderMomentumDB.Records then
        CommanderMomentumDB.Records = {}
    end
    return CommanderMomentumDB.Records
end

-- Instances score under their instance name; the open world under the zone
-- the player is standing in (GetInstanceInfo only knows the continent there)
local function RecordZoneName()
    local name, instanceType = GetInstanceInfo()
    if instanceType and instanceType ~= "none" and name and name ~= "" then
        return name
    end
    local zone = GetRealZoneText()
    if zone and zone ~= "" then
        return zone
    end
    return name or "Parts Unknown"
end

local function ZoneBest(zone)
    local rec = zone and CommanderMomentumDB.Records
        and CommanderMomentumDB.Records[zone]
    return (rec and tonumber(rec.best)) or 0
end

-- Highest recorded chain across every zone; ties go to whoever held it first
local function AllTimeRecord()
    local best, zone, when = 0, nil, math.huge
    for name, rec in pairs(CommanderMomentumDB.Records or {}) do
        local b = tonumber(rec and rec.best) or 0
        local w = tonumber(rec and rec.when) or math.huge
        if b > best or (b == best and b > 0 and w < when) then
            best, zone, when = b, name, w
        end
    end
    return best, zone
end

local root = CreateFrame("Frame", "CommanderMomentumFrame", UIParent)
root:SetPoint("TOP", UIParent, "TOP", 0, -260)
root:SetSize(BAR_WIDTH + 10, 44)
root:SetFrameStrata("MEDIUM")
root:Hide()

local streakText = root:CreateFontString(nil, "OVERLAY")
streakText:SetFontObject(GameFontNormalHuge)
streakText:SetPoint("TOP", root, "TOP", 0, 0)

local labelText = root:CreateFontString(nil, "OVERLAY")
labelText:SetFontObject(GameFontHighlightSmall)
labelText:SetPoint("TOP", streakText, "BOTTOM", 0, -1)
labelText:SetText("MOMENTUM")
labelText:SetTextColor(0.8, 0.8, 0.8)

local barBG = root:CreateTexture(nil, "BACKGROUND")
barBG:SetTexture("Interface\\Buttons\\WHITE8X8")
barBG:SetVertexColor(0, 0, 0, 0.55)
barBG:SetSize(BAR_WIDTH, BAR_HEIGHT)
barBG:SetPoint("BOTTOM", root, "BOTTOM", 0, 0)

local bar = root:CreateTexture(nil, "ARTWORK")
bar:SetTexture("Interface\\Buttons\\WHITE8X8")
bar:SetSize(BAR_WIDTH, BAR_HEIGHT)
bar:SetPoint("LEFT", barBG, "LEFT", 0, 0)

-- Escalating streak colors: white -> green -> blue -> purple -> orange
local function StreakColor()
    if streak >= 20 then
        return 1, 0.5, 0.1
    elseif streak >= 15 then
        return 0.7, 0.35, 1
    elseif streak >= 10 then
        return 0.35, 0.65, 1
    elseif streak >= 5 then
        return 0.3, 1, 0.4
    end
    return 0.95, 0.95, 0.95
end

-- ---------------------------------------------------------------------------
-- Player-frame display: the streak rides the default player frame instead of
-- the floating meter. The suite already crowds that corner (Casting's bar,
-- Buffs' rows, the PartyFrames banner), so no single spot can be the right
-- one — instead there are seven readout styles, a dozen places to hang them,
-- and offsets/size/opacity/contents on top, so the streak can be tucked into
-- whatever gap the rest of your layout leaves free.
--
--   RING   radial window sweep wrapping the portrait (the original)
--   GLOW   number only, with the portrait disc fading as the clock runs out
--   BADGE  compact bordered chip: multiplier and the seconds left
--   BAR    slim drain bar, horizontal or vertical
--   PIPS   one pip per kill in the chain; the newest pip fades as it drains
--   TICKER one plain text line, no art — "x7 · 12s · 6.4/min"
--   FLARE  a colored glow around the whole player frame, fading with the clock
-- ---------------------------------------------------------------------------

-- widgetPoint, anchorPoint, default nudge x/y. PORTRAIT hangs off the
-- portrait texture; every other placement off the player frame itself.
local PLACEMENTS = {
    PORTRAIT    = { "CENTER", "CENTER", 0, 0, portrait = true },
    OVER        = { "CENTER", "CENTER", 0, 0 },
    ABOVE       = { "BOTTOM", "TOP", 0, 2 },
    BELOW       = { "TOP", "BOTTOM", 0, -2 },
    LEFT        = { "RIGHT", "LEFT", -4, 0 },
    RIGHT       = { "LEFT", "RIGHT", 4, 0 },
    TOPLEFT     = { "BOTTOMRIGHT", "TOPLEFT", 12, -4 },
    TOPRIGHT    = { "BOTTOMLEFT", "TOPRIGHT", -12, -4 },
    BOTTOMLEFT  = { "TOPRIGHT", "BOTTOMLEFT", 12, 6 },
    BOTTOMRIGHT = { "TOPLEFT", "BOTTOMRIGHT", -12, 6 },
    BARS        = { "LEFT", "LEFT", 84, 4 },       -- over the health/mana bars
    UNDERBARS   = { "TOPLEFT", "BOTTOMLEFT", 84, -2 },
}

local player   -- widget bundle, built lazily on the first player-frame draw
local OnDrain  -- forward declaration: the drain driver lives with the meter
               -- below, but the player display re-attaches it on every draw
               -- (Combat Only can hide the frame mid-chain, which drops it)

local function DisplayMode()
    local mode = (CommanderMomentumDB and CommanderMomentumDB.Display) or "HUD"
    -- "PORTRAIT" was the one and only player-frame mode before the styles
    -- split out; saved settings still carry it
    if mode == "PORTRAIT" then return "RING" end
    return mode
end

local function PlayerMode()
    return DisplayMode() ~= "HUD"
end

-- Accent: the escalating streak tiers by default, or a fixed color — your
-- class, or any Commander_Console palette entry read live from the shared
-- canon (soft-failing back to the tiers when Console isn't installed)
local function AccentColor()
    local key = (CommanderMomentumDB and CommanderMomentumDB.Accent) or "TIERS"
    if key == "CLASS" then
        local _, class = UnitClass("player")
        local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if color then return color.r, color.g, color.b end
    elseif key ~= "TIERS" then
        for _, color in ipairs(CommanderConsole_Colors or {}) do
            if color.value == key and color.r then
                return color.r, color.g, color.b
            end
        end
    end
    return StreakColor()
end

local function PlayerSize()
    return (CommanderMomentumDB and CommanderMomentumDB.PlayerSize) or 52
end

local function EnsurePlayerWidgets()
    if player then return true end
    if not PlayerFrame then return false end
    local p = {}
    local baseLevel = (PlayerFrame:GetFrameLevel() or 1)

    p.root = CreateFrame("Frame", "CommanderMomentumPlayer", PlayerFrame)
    p.root:SetSize(52, 52)
    p.root:SetFrameStrata(PlayerFrame:GetFrameStrata() or "MEDIUM")
    p.root:SetFrameLevel(baseLevel + 8)
    p.root:Hide()

    -- Portrait disc tint: an optional layer for any style, on its own frame
    -- glued to the portrait so it stays put even when the readout itself is
    -- parked somewhere else. The round alpha-mask art used as a texture
    -- gives a clean disc; additive, so the face glows instead of being
    -- painted over.
    p.tintHost = CreateFrame("Frame", nil, PlayerFrame)
    if PlayerPortrait then
        p.tintHost:SetAllPoints(PlayerPortrait)
    else
        p.tintHost:SetSize(56, 56)
        p.tintHost:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 42, -12)
    end
    p.tintHost:SetFrameLevel(baseLevel + 7)
    p.tint = p.tintHost:CreateTexture(nil, "OVERLAY")
    p.tint:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    p.tint:SetAllPoints(p.tintHost)
    p.tint:SetBlendMode("ADD")
    p.tintHost:Hide()

    -- RING: the client animates the radial sweep itself, and the ring art
    -- means the swipe only ever draws ring pixels — an arc around the
    -- portrait, never a dark wedge over the face
    p.cooldown = CreateFrame("Cooldown", nil, p.root, "CooldownFrameTemplate")
    p.cooldown:SetAllPoints(p.root)
    if p.cooldown.SetHideCountdownNumbers then
        p.cooldown:SetHideCountdownNumbers(true)
    end
    if p.cooldown.SetDrawEdge then
        p.cooldown:SetDrawEdge(false)
    end
    if p.cooldown.SetSwipeTexture then
        p.cooldown:SetSwipeTexture("Interface\\AddOns\\Commander_Momentum\\Textures\\Ring")
    elseif p.cooldown.SetUseCircularEdge then
        -- Old-style fallback: at least clip the default wedge round
        p.cooldown:SetUseCircularEdge(true)
    end
    p.cooldown:Hide()

    -- FLARE: the soft square glow art blown up around the whole player
    -- frame, additive so it reads as light on the chassis
    p.flare = p.root:CreateTexture(nil, "BACKGROUND")
    p.flare:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    p.flare:SetBlendMode("ADD")
    p.flare:SetAllPoints(p.root)
    p.flare:Hide()

    -- BADGE chrome and the BAR's track/fill share the root
    p.badge = CreateFrame("Frame", nil, p.root, "BackdropTemplate")
    p.badge:SetAllPoints(p.root)
    p.badge:SetFrameLevel(baseLevel + 8)
    p.badge:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    p.badge:Hide()

    p.barBG = p.root:CreateTexture(nil, "BACKGROUND")
    p.barBG:SetTexture("Interface\\Buttons\\WHITE8X8")
    p.barBG:SetVertexColor(0, 0, 0, 0.55)
    p.barBG:SetAllPoints(p.root)
    p.barBG:Hide()
    p.barFill = p.root:CreateTexture(nil, "ARTWORK")
    p.barFill:SetTexture("Interface\\Buttons\\WHITE8X8")
    p.barFill:Hide()

    p.pips = {}

    -- Text rides its own higher frame so it always sits above the sweep
    local textHolder = CreateFrame("Frame", nil, p.root)
    textHolder:SetAllPoints(p.root)
    textHolder:SetFrameLevel(baseLevel + 14)
    p.textHolder = textHolder
    p.main = textHolder:CreateFontString(nil, "OVERLAY")
    p.main:SetFontObject(GameFontNormalLarge)
    p.sub = textHolder:CreateFontString(nil, "OVERLAY")
    p.sub:SetFontObject(GameFontHighlightSmall)

    player = p
    return true
end

-- Outlined text keeps the numbers legible over portrait art and bar fills
local function SetOutlinedFont(text, size)
    local path = text:GetFont()
    if path then
        pcall(text.SetFont, text, path, size, "OUTLINE")
    end
end

local function EnsurePips(count)
    local p = player
    for i = #p.pips + 1, count do
        local pip = p.root:CreateTexture(nil, "ARTWORK")
        pip:SetTexture("Interface\\Buttons\\WHITE8X8")
        p.pips[i] = pip
    end
    for i = count + 1, #p.pips do
        p.pips[i]:Hide()
    end
end

local function HidePlayerDisplay()
    if not player then return end
    player.root:Hide()
    player.root:SetScript("OnUpdate", nil)
    player.tintHost:Hide()
    if player.cooldown.Clear then
        player.cooldown:Clear()
    else
        player.cooldown:SetCooldown(0, 0)
    end
end

-- Seconds left on the window and that as a 0..1 fraction
local function WindowRemaining()
    local window = (CommanderMomentumDB and CommanderMomentumDB.Window) or 20
    if streak < 1 then return 0, 0, window end
    local remaining = (lastKill + window) - GetTime()
    if remaining <= 0 then return 0, 0, window end
    return remaining, remaining / window, window
end

-- The optional extras, in a fixed order, joined into one line. Which of
-- them appear is entirely up to the settings — the readout can be a bare
-- multiplier or a full status line.
local function InfoLine(remaining)
    local db = CommanderMomentumDB
    local parts = {}
    if db.ShowSeconds and remaining > 0 then
        parts[#parts + 1] = string.format("%ds", math.ceil(remaining))
    end
    if db.ShowPace and streak >= 2 then
        local elapsed = GetTime() - streakStart
        if elapsed > 5 then
            parts[#parts + 1] = string.format("%.1f/min", streak / (elapsed / 60))
        end
    end
    if db.ShowBest then
        parts[#parts + 1] = string.format("best x%d", math.max(bestStreak, streak))
    end
    if db.ShowWindow then
        parts[#parts + 1] = string.format("%ds clock",
            math.floor((db.Window or 20) + 0.5))
    end
    if db.ShowLabel then
        parts[#parts + 1] = "MOMENTUM"
    end
    return table.concat(parts, " · ")
end

-- The ticker has no art to give it a footprint, so its frame takes the
-- width of the line itself — otherwise a 1px-wide anchor would sit the
-- text half on top of whatever it was placed next to
local function SizeTicker()
    local p = player
    p.root:SetSize(math.max(p.main:GetStringWidth() or 20, 8), p.tickerHeight or 12)
end

-- Per-frame half of the player display: only what the draining clock
-- actually changes. Layout, colors and text that don't tick live in
-- UpdatePlayerDisplay.
local function TickPlayerDisplay()
    local p = player
    if not (p and p.root:IsShown()) then return end
    local db = CommanderMomentumDB
    local mode = DisplayMode()
    local remaining, fraction = WindowRemaining()

    if mode == "BAR" then
        local length = math.max(p.barLength * fraction, 1)
        if db.PlayerVertical then
            p.barFill:SetSize(p.barThickness, length)
        else
            p.barFill:SetSize(length, p.barThickness)
        end
    elseif mode == "PIPS" then
        local lead = p.pips[math.min(streak, p.pipCount or 0)]
        if lead then
            lead:SetAlpha(0.25 + fraction * 0.75)
        end
    elseif mode == "FLARE" then
        p.flare:SetAlpha(0.15 + fraction * 0.65)
    elseif mode == "GLOW" and db.PortraitGlow then
        p.tint:SetAlpha(0.1 + fraction * 0.5)
    end

    -- Text only rewrites when the displayed second actually changes
    if db.ShowSeconds then
        local seconds = math.ceil(remaining)
        if seconds ~= p.lastSeconds then
            p.lastSeconds = seconds
            local line = InfoLine(remaining)
            if mode == "TICKER" then
                p.main:SetText(p.mainPrefix .. line)
                SizeTicker()
            else
                p.sub:SetText(line)
                -- The line can appear or empty out mid-window (the seconds
                -- piece dies with the clock), so visibility follows it
                p.sub:SetShown(line ~= "")
            end
        end
    end
end

-- Full re-draw of the player-frame readout: placement, geometry, colors,
-- which pieces are shown. Called on kills, on settings changes, and
-- whenever the streak ends.
local function UpdatePlayerDisplay()
    if not (CommanderMomentumDB and CommanderMomentumDB.EnableMomentum) or not PlayerMode() then
        HidePlayerDisplay()
        return
    end
    if not EnsurePlayerWidgets() then return end
    local db = CommanderMomentumDB
    local p = player
    local mode = DisplayMode()

    local show = streak >= 2 or db.AlwaysShow
    if show and db.CombatOnly and not UnitAffectingCombat("player") then
        show = false
    end
    if not show then
        HidePlayerDisplay()
        return
    end

    local r, g, b = AccentColor()
    if streak < 2 then r, g, b = 0.6, 0.6, 0.6 end
    local remaining, fraction = WindowRemaining()
    local size = PlayerSize()

    -- Placement: anchor the readout wherever the rest of your UI has room
    local place = PLACEMENTS[db.Placement or "PORTRAIT"] or PLACEMENTS.PORTRAIT
    local anchorFrame = (place.portrait and PlayerPortrait) or PlayerFrame
    p.root:ClearAllPoints()
    p.root:SetPoint(place[1], anchorFrame, place[2],
        place[3] + (db.PlayerX or 0), place[4] + (db.PlayerY or 0))
    p.root:SetAlpha(db.PlayerAlpha or 1)

    -- Every style starts from a clean slate: only the pieces the selected
    -- style uses get shown again below
    p.cooldown:Hide()
    p.flare:Hide()
    p.badge:Hide()
    p.barBG:Hide()
    p.barFill:Hide()
    for _, pip in ipairs(p.pips) do pip:Hide() end
    p.main:ClearAllPoints()
    p.sub:ClearAllPoints()
    p.main:Hide()
    p.sub:Hide()
    p.lastSeconds = nil

    local mainText = db.ShowMultiplier and string.format("x%d", streak) or ""
    local infoText = InfoLine(remaining)
    p.mainPrefix = ""

    if mode == "RING" then
        p.root:SetSize(size, size)
        p.cooldown:Show()
        if p.cooldown.SetSwipeColor then
            p.cooldown:SetSwipeColor(r, g, b, 0.95)
        end
        local window = db.Window or 20
        if streak >= 1 and remaining > 0 then
            p.cooldown:SetCooldown(lastKill, window)
        elseif p.cooldown.Clear then
            p.cooldown:Clear()
        end
        p.main:SetPoint("CENTER")
        p.sub:SetPoint("TOP", p.root, "BOTTOM", 0, -1)
        SetOutlinedFont(p.main, math.max(10, math.floor(size * 0.38)))
    elseif mode == "GLOW" then
        p.root:SetSize(size, size)
        p.main:SetPoint("CENTER")
        p.sub:SetPoint("TOP", p.root, "BOTTOM", 0, -1)
        SetOutlinedFont(p.main, math.max(10, math.floor(size * 0.42)))
    elseif mode == "BADGE" then
        local height = math.max(18, math.floor(size * 0.52))
        p.root:SetSize(math.max(34, math.floor(size * 1.15)),
            (infoText ~= "" and height + 12) or height)
        p.badge:SetBackdropColor(0, 0, 0, 0.6)
        p.badge:SetBackdropBorderColor(r, g, b, 0.9)
        p.badge:Show()
        if infoText ~= "" then
            p.main:SetPoint("TOP", p.root, "TOP", 0, -3)
            p.sub:SetPoint("BOTTOM", p.root, "BOTTOM", 0, 3)
        else
            p.main:SetPoint("CENTER")
            p.sub:SetPoint("TOP", p.root, "BOTTOM", 0, -1)
        end
        SetOutlinedFont(p.main, math.max(10, math.floor(height * 0.62)))
    elseif mode == "BAR" then
        p.barLength = math.max(20, math.floor(size * 2.4))
        p.barThickness = math.max(4, math.floor(size * 0.2))
        if db.PlayerVertical then
            p.root:SetSize(p.barThickness, p.barLength)
            p.barFill:SetPoint("BOTTOM", p.root, "BOTTOM", 0, 0)
        else
            p.root:SetSize(p.barLength, p.barThickness)
            p.barFill:SetPoint("LEFT", p.root, "LEFT", 0, 0)
        end
        p.barBG:Show()
        p.barFill:SetVertexColor(r, g, b, 0.9)
        p.barFill:Show()
        p.main:SetPoint("CENTER")
        p.sub:SetPoint("TOP", p.root, "BOTTOM", 0, -1)
        SetOutlinedFont(p.main, math.max(9, math.floor(p.barThickness * 1.1)))
    elseif mode == "PIPS" then
        -- One pip per kill in the chain, so the chain is countable at a
        -- glance; past the cap the pips stop and the multiplier carries it
        local cap = db.PipCap or 10
        local count = math.max(math.min(streak, cap), 1)
        local pipSize = math.max(4, math.floor(size * 0.22))
        local gap = math.max(2, math.floor(pipSize * 0.35))
        p.pipCount = count
        EnsurePips(count)
        local span = count * pipSize + (count - 1) * gap
        if db.PlayerVertical then
            p.root:SetSize(pipSize, span)
        else
            p.root:SetSize(span, pipSize)
        end
        for i = 1, count do
            local pip = p.pips[i]
            pip:SetSize(pipSize, pipSize)
            pip:ClearAllPoints()
            if db.PlayerVertical then
                pip:SetPoint("BOTTOM", p.root, "BOTTOM", 0, (i - 1) * (pipSize + gap))
            else
                pip:SetPoint("LEFT", p.root, "LEFT", (i - 1) * (pipSize + gap), 0)
            end
            pip:SetVertexColor(r, g, b, 0.95)
            pip:SetAlpha(1)
            pip:Show()
        end
        p.main:SetPoint(db.PlayerVertical and "LEFT" or "BOTTOM",
            p.root, db.PlayerVertical and "RIGHT" or "TOP", db.PlayerVertical and 4 or 0, 2)
        p.sub:SetPoint("TOP", p.root, "BOTTOM", 0, -2)
        SetOutlinedFont(p.main, math.max(9, math.floor(size * 0.28)))
    elseif mode == "TICKER" then
        -- No art at all: one line of text that says everything you asked for
        p.mainPrefix = (mainText ~= "" and infoText ~= "") and (mainText .. " · ")
            or mainText
        mainText = p.mainPrefix .. infoText
        infoText = ""
        p.tickerHeight = math.max(10, math.floor(size * 0.3))
        p.root:SetSize(8, p.tickerHeight)
        p.main:SetPoint("CENTER")
        SetOutlinedFont(p.main, math.max(9, math.floor(size * 0.26)))
    elseif mode == "FLARE" then
        -- The glow wraps the whole chassis; placement offsets still nudge it
        p.root:SetSize((PlayerFrame:GetWidth() or 200) * 0.92,
            (PlayerFrame:GetHeight() or 100) * 1.1)
        p.flare:SetVertexColor(r, g, b)
        p.flare:Show()
        p.main:SetPoint("CENTER", p.root, "CENTER", 0, 0)
        p.sub:SetPoint("TOP", p.root, "BOTTOM", 0, -1)
        SetOutlinedFont(p.main, math.max(10, math.floor(size * 0.34)))
    end

    if mainText ~= "" then
        p.main:SetText(mainText)
        p.main:SetTextColor(r, g, b)
        p.main:Show()
        if mode == "TICKER" then SizeTicker() end
    end
    if infoText ~= "" then
        p.sub:SetText(infoText)
        p.sub:SetTextColor(0.85, 0.85, 0.85)
        p.sub:Show()
    end

    -- The portrait glow is available to every style, not just the ones
    -- living on the portrait — a chain is readable from the face alone
    if db.PortraitGlow and streak >= 2 then
        p.tint:SetVertexColor(r, g, b)
        p.tint:SetAlpha(mode == "GLOW" and (0.1 + fraction * 0.5)
            or (0.18 + math.min(streak, 20) / 20 * 0.17))
        p.tintHost:Show()
    else
        p.tintHost:Hide()
    end

    p.root:Show()
    p.root:SetScript("OnUpdate", streak >= 2 and OnDrain or nil)
    TickPlayerDisplay()
end

-- Public lament when a real streak dies on the clock; only chains over
-- x10 are worth announcing, and only chains over x15 earn the audible
-- /cry sob (sent after the lament so the chat log reads in order).
-- The window is named out loud: a bystander who reads "broken by 20s
-- without a kill" learns the rules of the game from the lament itself.
local BREAK_LINES = {
    "loses momentum — the x%d chain is broken by %ds without a kill! (%s)",
    "watches a x%d streak slip away — the %ds kill clock ran out. (%s)",
}

local function EndStreak(announceBreak)
    local endedStreak = streak
    streak = 0
    announcedMilestone = 0
    local wasTestChain = streakIsTest
    streakIsTest = false
    local enabled = CommanderMomentumDB and CommanderMomentumDB.EnableMomentum
    -- Local record recap when a milestone-worthy chain ends: broken records
    -- always report; otherwise the session's best chain gets the standing —
    -- zone record and all-time high — as its epitaph. Record claims compare
    -- against pre-chain baselines and require the chain to actually hold the
    -- written record, so test-inflated chains can never take credit.
    local newAllTime = false
    if enabled and not wasTestChain and endedStreak >= 5 then
        local zone = chainZone or RecordZoneName()
        local zoneBest = ZoneBest(zone)
        local atBest, atZone = AllTimeRecord()
        -- A chain restored from a pre-records session never captured its
        -- baselines; treat the current records as the baseline (no claims)
        local zoneBase = chainBasesCaptured and chainZoneBase or zoneBest
        local atBase = chainBasesCaptured and chainAllTimeBase or atBest
        local atBaseZone = chainBasesCaptured and chainAllTimeBaseZone or atZone
        newAllTime = endedStreak == atBest and endedStreak > atBase
        local standing
        if newAllTime then
            if atBase >= 2 and atBaseZone then
                standing = string.format("NEW ALL-TIME HIGH in %s! (previous x%d — %s)",
                    zone, atBase, atBaseZone == zone and "set right here" or atBaseZone)
            else
                standing = string.format("a new all-time high — the record books open in %s", zone)
            end
        elseif endedStreak == zoneBest and endedStreak > zoneBase then
            if zoneBase >= 2 then
                standing = string.format("new record for %s (was x%d) — all-time high x%d (%s)",
                    zone, zoneBase, atBest, atZone)
            else
                standing = string.format("first record for %s — all-time high x%d (%s)",
                    zone, atBest, atZone)
            end
        elseif endedStreak == bestStreak and zoneBest >= 2 then
            if atZone == zone then
                standing = string.format("%s record x%d is the all-time high", zone, zoneBest)
            else
                standing = string.format("%s record x%d, all-time high x%d (%s)",
                    zone, zoneBest, atBest, atZone)
            end
        end
        if standing then
            print(string.format("|cffffb830Commander Momentum:|r %sx%d chain ends — %s",
                endedStreak == bestStreak and "session best " or "", endedStreak, standing))
        end
    end
    if announceBreak and not wasTestChain
        and enabled
        and CommanderMomentumDB.BreakEmotes
        and endedStreak > 10 then
        local atBest = AllTimeRecord()
        local stats = string.format("%d kills this session, best chain x%d",
            totalKills, bestStreak)
        if newAllTime then
            stats = string.format("%s, a NEW all-time high x%d", stats, atBest)
        elseif atBest >= 2 then
            stats = string.format("%s, all-time high x%d", stats, atBest)
        end
        local window = math.floor((CommanderMomentumDB.Window or 20) + 0.5)
        SendChatMessage(string.format(BREAK_LINES[math.random(#BREAK_LINES)],
            endedStreak, window, stats), "EMOTE")
        if endedStreak > 15 then
            DoEmote("CRY")
        end
    end
    -- Chain bookkeeping dies with the chain; the next one recaptures fresh
    chainZone = nil
    chainZoneBase = 0
    chainAllTimeBase = 0
    chainAllTimeBaseZone = nil
    chainBasesCaptured = false
    SyncSession()
    local keepShown = CommanderMomentumDB and CommanderMomentumDB.EnableMomentum
        and DisplayMode() == "HUD"
        and (CommanderMomentumDB.AlwaysShow
            or Commander.UI.HudUnlocked(CommanderMomentumDB, "Hud"))
    root:SetShown(keepShown or false)
    root:SetScript("OnUpdate", nil)
    if keepShown then
        streakText:SetText("x0")
        streakText:SetTextColor(0.6, 0.6, 0.6)
        bar:SetSize(1, BAR_HEIGHT)
    end
    if player then
        player.root:SetScript("OnUpdate", nil)
        UpdatePlayerDisplay()
    end
end

local sinceDraw = 0
-- Assigns the forward-declared local above, not a new global
function OnDrain(self, elapsed)
    sinceDraw = sinceDraw + elapsed
    if sinceDraw < 0.05 then return end
    sinceDraw = 0
    local window = CommanderMomentumDB.Window or 20
    local remaining = (lastKill + window) - GetTime()
    if remaining <= 0 then
        -- The clock ran out on a live streak: the one true "broken" path
        EndStreak(true)
        return
    end
    bar:SetSize(math.max(BAR_WIDTH * (remaining / window), 1), BAR_HEIGHT)
    -- The drain driver rides whichever frame is actually on screen, so the
    -- player-frame styles animate from the same tick as the floating meter
    TickPlayerDisplay()
end

local function Refresh()
    local r, g, b = StreakColor()
    streakText:SetText(string.format("x%d", streak))
    streakText:SetTextColor(r, g, b)
    bar:SetVertexColor(r, g, b, 0.9)
end

-- Public: current streak and seconds left on its window (nil remaining
-- when no live streak). Commander_Comms' auto charge rally reads this.
function CommanderMomentum_GetStreakInfo()
    if not (CommanderMomentumDB and CommanderMomentumDB.EnableMomentum) then
        return 0, nil
    end
    if streak < 2 then
        return streak, nil
    end
    local window = CommanderMomentumDB.Window or 20
    local remaining = (lastKill + window) - GetTime()
    if remaining <= 0 then
        return streak, nil
    end
    return streak, remaining
end

-- Public brag at each milestone: a flavor line escalating with the tier
-- plus the session's numbers, sent as a custom emote for everyone nearby.
-- The chain window rides along ("x10 chain on a 20s kill clock") — without
-- it "x10 chain" is just a number and reads as noise; with it, anyone
-- nearby knows a clock is running and what the chain costs to hold.
local FLAVOR_TIERS = {
    { min = 20, lines = { "erupts in TOTAL ANNIHILATION!", "is beyond containment!" } },
    { min = 15, lines = { "is absolutely unstoppable!", "has become the battlefield!" } },
    { min = 10, lines = { "is on a full rampage!", "carves through the enemy line!" } },
    { min = 0, lines = { "is heating up!", "builds deadly momentum!" } },
}

local function BuildBrag()
    local flavor
    for _, tier in ipairs(FLAVOR_TIERS) do
        if streak >= tier.min then
            flavor = tier.lines[math.random(#tier.lines)]
            break
        end
    end
    local pace = ""
    local elapsed = GetTime() - streakStart
    if elapsed > 10 then
        pace = string.format(", %.1f kills/min", streak / (elapsed / 60))
    end
    local window = math.floor((CommanderMomentumDB.Window or 20) + 0.5)
    return string.format(
        "%s (x%d chain on a %ds kill clock%s — %d kills this session, best chain x%d)",
        flavor, streak, window, pace, totalKills, math.max(bestStreak, streak))
end

local warnedThisWindow = false

local function OnKill()
    -- Enforce the window even for streaks too small to show: without this,
    -- a streak of 1 never expires (no visible frame, no drain driver) and
    -- any two kills ever would chain into a bogus x2
    local window = CommanderMomentumDB.Window or 20
    if GetTime() - lastKill > window then
        streak = 0
        announcedMilestone = 0
        -- A chain of 1 dies silently (no EndStreak); scrub its bookkeeping
        -- here so the new chain recaptures fresh baselines
        chainZone = nil
        chainBasesCaptured = false
    end
    warnedThisWindow = false
    if streak == 0 then
        streakStart = GetTime()
    end
    streak = streak + 1
    if testFeeding then
        if streak <= 2 then streakIsTest = true end
    else
        streakIsTest = false
    end
    totalKills = totalKills + 1
    if streak > bestStreak then
        bestStreak = streak
    end
    lastKill = GetTime()
    -- Zone-record bookkeeping: baselines captured on the chain's first real
    -- kill (before this kill can move a record), then records written live.
    -- Test kills never touch the books.
    if not testFeeding then
        if not chainBasesCaptured then
            chainBasesCaptured = true
            chainAllTimeBase, chainAllTimeBaseZone = AllTimeRecord()
        end
        local zone = RecordZoneName()
        if zone ~= chainZone then
            chainZone = zone
            chainZoneBase = ZoneBest(zone)
        end
        if streak >= 2 and streak > ZoneBest(zone) then
            local rec = Records()[zone]
            if rec then
                rec.best, rec.when = streak, time()
            else
                Records()[zone] = { best = streak, when = time() }
            end
        end
    end
    SyncSession()
    if streak >= 2 then
        if PlayerMode() then
            -- The drain driver rides the player-frame readout so window
            -- expiry still ends the streak while the floating meter is down
            root:Hide()
            UpdatePlayerDisplay()
            if player then
                player.root:SetScript("OnUpdate", OnDrain)
            end
        else
            Refresh()
            Commander.UI.ApplyHudChrome(root, CommanderMomentumDB, "Hud", {
                defaultPoint = { point = "TOP", x = 0, y = -260 },
            })
            root:Show()
            root:SetScript("OnUpdate", OnDrain)
        end
    end
    if PlayerMode() then
        UpdatePlayerDisplay()
    end
    local milestone = math.floor(streak / 5) * 5
    if milestone >= 5 and milestone > announcedMilestone then
        announcedMilestone = milestone
        SyncSession()
        if CommanderMomentumDB.MilestoneSound then
            PlaySound(SOUNDKIT.READY_CHECK, "Master")
        end
        print(string.format("|cffffb830Commander Momentum:|r x%d streak", streak))
        if CommanderMomentumDB.MilestoneEmotes and not testFeeding then
            SendChatMessage(BuildBrag(), "EMOTE")
        end
    end
end

-- Where the player-frame readout is and what it says right now — the answer
-- to "I changed the placement and now I can't find it" (/cmom display).
-- Returns what it prints so the harness can assert on the same values.
function CommanderMomentum_DisplayReport()
    local db = CommanderMomentumDB
    local mode = DisplayMode()
    if mode == "HUD" then
        print("Commander Momentum: the floating meter owns the display — unlock it (Frame Style options) to drag it anywhere.")
        return mode
    end
    local shown = (player and player.root:IsShown()) and true or false
    local mainText = (player and player.main:IsShown() and player.main:GetText()) or ""
    local subText = (player and player.sub:IsShown() and player.sub:GetText()) or ""
    local reading = mainText
    if subText ~= "" then
        reading = (reading ~= "" and (reading .. " / " .. subText)) or subText
    end
    print(string.format(
        "Commander Momentum: %s style on the player frame at %s (%d, %d), size %d — %s",
        mode, db.Placement or "PORTRAIT",
        math.floor(db.PlayerX or 0), math.floor(db.PlayerY or 0),
        math.floor(db.PlayerSize or 52),
        shown and (reading ~= "" and ("reading \"" .. reading .. "\"") or "on screen, art only")
            or "hidden right now (no live chain, or Combat Only out of combat)"))
    return mode, db.Placement or "PORTRAIT", shown, mainText, subText
end

-- Standard suite report and tester
function CommanderMomentum_Report()
    local zone = RecordZoneName()
    local zoneBest = ZoneBest(zone)
    local atBest, atZone = AllTimeRecord()
    local standing
    if atBest < 2 then
        standing = "no zone records on the books yet"
    elseif zone == atZone then
        standing = string.format("%s record x%d is the all-time high", zone, zoneBest)
    elseif zoneBest >= 2 then
        standing = string.format("%s record x%d, all-time high x%d (%s)",
            zone, zoneBest, atBest, atZone)
    else
        standing = string.format("no record for %s yet — all-time high x%d (%s)",
            zone, atBest, atZone)
    end
    print(string.format(
        "Commander Momentum: %d kill%s this session, best chain x%d%s — %s",
        totalKills, totalKills == 1 and "" or "s", bestStreak,
        streak >= 2 and string.format(" (live streak x%d)", streak) or "",
        standing))
end

-- The record books: every zone's best chain, top score first
function CommanderMomentum_Records()
    local list = {}
    for name, rec in pairs(CommanderMomentumDB.Records or {}) do
        local best = tonumber(rec and rec.best) or 0
        if best >= 2 then
            list[#list + 1] = { zone = name, best = best, when = tonumber(rec.when) }
        end
    end
    if #list == 0 then
        print("Commander Momentum: no zone records yet — chain two kills somewhere and the books open")
        return
    end
    table.sort(list, function(a, b)
        if a.best ~= b.best then return a.best > b.best end
        return (a.when or math.huge) < (b.when or math.huge)
    end)
    print(string.format("|cffffb830Commander Momentum:|r zone records (%d zone%s)",
        #list, #list == 1 and "" or "s"))
    local shown = math.min(#list, 15)
    for i = 1, shown do
        local entry = list[i]
        print(string.format("  x%d — %s%s%s",
            entry.best, entry.zone,
            entry.when and date(" (%m/%d/%y)", entry.when) or "",
            i == 1 and " |cffffb830— all-time high|r" or ""))
    end
    if #list > shown then
        print(string.format("  ...and %d more", #list - shown))
    end
end

function CommanderMomentum_Test()
    if not (CommanderMomentumDB and CommanderMomentumDB.EnableMomentum) then
        print("Commander Momentum: module is disabled (enable it in settings or /cmom)")
        return
    end
    -- Feed two kills through the real pipeline so the live display and
    -- drain are genuine, but keep session stats and public emotes clean
    local savedKills, savedBest = totalKills, bestStreak
    testFeeding = true
    OnKill()
    OnKill()
    testFeeding = false
    totalKills, bestStreak = savedKills, savedBest
    SyncSession()
    print(string.format("Commander Momentum: test kills fed — live x%d streak, watch it drain", streak))
end

local function Apply()
    if not (CommanderMomentumDB and CommanderMomentumDB.EnableMomentum) then
        EndStreak()
        root:Hide()
        return
    end
    UpdatePlayerDisplay()
    if PlayerMode() then
        -- A player-frame style owns the display; keep the floating meter
        -- down but move its drain driver over if a streak is live
        root:Hide()
        root:SetScript("OnUpdate", nil)
        if streak >= 2 and player then
            player.root:SetScript("OnUpdate", OnDrain)
        end
        return
    end
    if player then
        player.root:SetScript("OnUpdate", nil)
    end
    if streak >= 2 then
        root:SetScript("OnUpdate", OnDrain)
    end
    local unlocked = Commander.UI.HudUnlocked(CommanderMomentumDB, "Hud")
    -- Visibility derives from state, never from the sticky IsShown():
    -- re-locking or turning Always Show off must actually hide an idle meter
    local shouldShow = streak >= 2 or unlocked or CommanderMomentumDB.AlwaysShow
    if shouldShow then
        Commander.UI.ApplyHudChrome(root, CommanderMomentumDB, "Hud", {
            title = "Momentum",
            defaultPoint = { point = "TOP", x = 0, y = -260 },
        })
        root:Show()
        Refresh()
        if streak < 2 then
            streakText:SetText(string.format("x%d", streak))
            streakText:SetTextColor(0.6, 0.6, 0.6)
            bar:SetSize(unlocked and BAR_WIDTH or 1, BAR_HEIGHT)
        end
    else
        root:Hide()
    end
end

-- Display-independent watchdog: streak expiry and the near-break warning
-- must fire even when no meter frame happens to be visible — game logic
-- can never ride an OnUpdate driver alone. The frame drivers still handle
-- the smooth bar drain; this catches what they miss.
C_Timer.NewTicker(1, function()
    if not (CommanderMomentumDB and CommanderMomentumDB.EnableMomentum) then return end
    if streak < 2 then return end
    local window = CommanderMomentumDB.Window or 20
    local remaining = (lastKill + window) - GetTime()
    if remaining <= 0 then
        EndStreak(true)
        return
    end
    -- Local heads-up before the chain dies (the public Charge rally is
    -- Commander_Comms' Auto Charge Rally option)
    if CommanderMomentumDB.BreakWarning and not warnedThisWindow and remaining <= 5 then
        warnedThisWindow = true
        PlaySound(SOUNDKIT.READY_CHECK, "Master")
        print(string.format("|cffff4030Commander Momentum:|r x%d streak breaking in %d seconds!",
            streak, math.ceil(remaining)))
        local flashRed = function(text)
            if text then text:SetTextColor(1, 0.25, 0.2) end
        end
        flashRed(streakText)
        flashRed(player and player.main)
    end
end)

-- Session resets: the momentum "session" is a fighting stretch, not the
-- whole login — death ends it, and so does a loading-screen transition
-- (instance entry/exit, continent change). Zone identity is tracked in
-- the persisted session, so a /reload in place never counts as a change.
local function ResetSessionStats()
    totalKills, bestStreak = 0, 0
    SyncSession()
end

local function CurrentZoneKey()
    local _, instanceType, _, _, _, _, _, instanceMapID = GetInstanceInfo()
    return tostring(instanceType or "none") .. ":" .. tostring(instanceMapID or 0)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_DEAD")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
-- Combat Only lives or dies on these two: without them the readout would
-- linger until the next kill or settings touch
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- A /reload must not eat a live streak: restore it with the kill
        -- clock converted from epoch back into GetTime's domain
        local fresh
        session, fresh = Commander.RestoreSession(CommanderMomentumDB, {
            streak = 0, milestone = 0, lastKillEpoch = 0,
            totalKills = 0, bestStreak = 0, streakStartEpoch = 0,
            zoneKey = false,
            chainZone = false, chainZoneBase = 0,
            chainAllTimeBase = 0, chainAllTimeBaseZone = false,
            chainBasesCaptured = false,
        })
        totalKills = session.totalKills or 0
        bestStreak = session.bestStreak or 0
        if not fresh and session.streak > 0 and session.lastKillEpoch > 0 then
            streak = session.streak
            announcedMilestone = session.milestone
            lastKill = GetTime() - math.max(time() - session.lastKillEpoch, 0)
            if session.streakStartEpoch > 0 then
                streakStart = GetTime() - math.max(time() - session.streakStartEpoch, 0)
            end
            -- Record bookkeeping rides along so a /reload mid-chain still
            -- knows what the chain has to beat
            chainZone = session.chainZone or nil
            chainZoneBase = session.chainZoneBase or 0
            chainAllTimeBase = session.chainAllTimeBase or 0
            chainAllTimeBaseZone = session.chainAllTimeBaseZone or nil
            chainBasesCaptured = session.chainBasesCaptured or false
        end
        Commander.AddListener(COMMANDER_MOMENTUM_EVENTS.UPDATE, Apply)
        -- Nothing notifies at startup: Always Show / unlocked-at-reload
        -- need an initial apply or the frame stays invisible until a
        -- streak or a settings touch
        Apply()
        return
    end
    if not (CommanderMomentumDB and CommanderMomentumDB.EnableMomentum) then return end
    if event == "PLAYER_DEAD" then
        if CommanderMomentumDB.ResetOnDeath then
            -- Dying breaks the chain (lament rules apply) and zeroes the
            -- session numbers: the next fight starts a fresh story
            EndStreak(true)
            ResetSessionStats()
        end
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        if session then
            local key = CurrentZoneKey()
            if CommanderMomentumDB.ResetOnZone and session.zoneKey and session.zoneKey ~= key then
                -- The loading screen already broke the flow; end quietly
                EndStreak()
                ResetSessionStats()
            end
            session.zoneKey = key
        end
        return
    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        if CommanderMomentumDB.CombatOnly then
            UpdatePlayerDisplay()
        end
        return
    end
    local _, subevent, _, sourceGUID, _, _, _, _, _, destFlags = CombatLogGetCurrentEventInfo()
    if CommanderMomentumDB.KillSource == "SQUAD" then
        -- Any hostile NPC death nearby feeds the meter — momentum for
        -- healers and tanks, not just whoever lands the killing blow.
        -- Pets, guardians, and totems die noisily but are not kills.
        if subevent == "UNIT_DIED" and destFlags
            and bit.band(destFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) > 0
            and bit.band(destFlags, COMBATLOG_OBJECT_CONTROL_NPC) > 0
            and bit.band(destFlags, (COMBATLOG_OBJECT_TYPE_PET or 0x1000)
                + (COMBATLOG_OBJECT_TYPE_GUARDIAN or 0x2000)) == 0 then
            OnKill()
        end
    elseif subevent == "PARTY_KILL" and sourceGUID == UnitGUID("player") then
        OnKill()
    end
end)
