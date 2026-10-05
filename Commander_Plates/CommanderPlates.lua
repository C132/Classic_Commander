-- Commander Plates: Blizzard's nameplates, made fit for an arena.
--
-- This is a LAYER, not a replacement. Blizzard's plate on this client is the
-- modern NamePlateUnitFrameMixin family (verified against the client's own
-- Blizzard_NamePlates on the classic_anniversary branch, build 2.5.6.69546):
-- a pooled UnitFrame per plate with HealthBarsContainer, CastBarsContainer,
-- AurasFrame and a hit-test region set through SetHitTestPoints. Every unit
-- frame here is left structurally alone. Colour is re-applied behind
-- CompactUnitFrame_UpdateHealthColor, names behind CompactUnitFrame_UpdateName,
-- the hit box behind ApplyFrameOptions (the one tick in combat that tainted
-- code is allowed to change it), and everything drawn is on an overlay frame
-- of our own parented to the unit frame. Turn the module off and the plate
-- underneath was never touched -- the alphas this file writes are the only
-- state it restores by hand, and it restores them on every unit removal,
-- because the unit frames are POOLED and the next occupant of one is somebody
-- else.
--
-- What it adds:
--   COLOUR     class-coloured health bars and names, friends and enemies
--   AURAS      two rows of icons, ours, filtered the way a PvP player filters:
--              mine always, notable always, everything only on request
--   CONTROL    one big icon for the control the unit is sitting in
--   HIT BOX    a taller clickable region under an unchanged plate
--   IDENTITY   target arrows and glow, focus glow, arena numbers, class icon,
--              a healer cross for anyone the combat log has caught healing,
--              totems as icons
--   CAST BAR   seconds left, a loud border on the casts that matter
--   CVARS      the client's own nameplate knobs as one re-applied profile
--   RADIAL     a whole second plate style: the unit as a disc, health and
--              cast as arcs round a face that turns into the spell being
--              cast or the stun being sat in, auras in orbit (Radial.lua
--              holds the brushes; the plate underneath is hidden by ALPHA,
--              the same single kind of write this file already restores)
--
-- The decisions -- what an aura IS, which one wins the big slot, what a row
-- shows -- live in CommanderPlatesEngine.lua and never touch the client.

local DATA = CommanderPlates_Data
local E = CommanderPlates_Engine

local function DB(key, default)
    local db = CommanderPlatesDB
    if not db then return default end
    local value = db[key]
    if value == nil then return default end
    return value
end

-- The engine's settings accessor: a bare read, so its own `~= false` and
-- `or default` idioms decide what a missing key means.
local function S(key) return DB(key) end

local function Enabled()
    return CommanderPlatesDB and CommanderPlatesDB.Enable == true
end

local Draw = CommanderPlates_Draw
local Radial = CommanderPlates_Radial
local WHITE = Draw.WHITE
local GLOW = "Interface\\Buttons\\UI-ActionButton-Border"
local TICK = 0.1                   -- 10Hz: timers, cast polling, alpha enforcement
local HEALER_TTL = 600
local MAX_AURAS = 40

local OWN_BORDER = { 0.95, 0.95, 0.95 }
local PLAIN_BORDER = { 0, 0, 0 }

-- ---------------------------------------------------------------------------
-- Live state
-- ---------------------------------------------------------------------------
local plates = {}                                   -- unit token -> rec
local byUF = setmetatable({}, { __mode = "k" })     -- UnitFrame -> rec (live only)
local overlays = setmetatable({}, { __mode = "k" }) -- UnitFrame -> overlay (for life)
local hookedUF = setmetatable({}, { __mode = "k" })
local healers = E.NewHealerBook(HEALER_TTL)
local whitelist, blacklist, emphasis = E.ParseList(""), E.ParseList(""), E.BuildEmphasis("", "")
local hiddenNpcs = E.ParseList("")
local canDispel, canPurge = {}, false
local playerClass
local inInstance = false
local hitBoxPending = false
local cvarsPending = false
local hintedNameOnly = false
local radialCfg = Radial.Config(S)
local radialOn = false                  -- any plate may be radial: the extra events are wanted

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------
local function ClassColor(unit)
    if not UnitClass then return end
    local _, class = UnitClass(unit)
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then return color.r, color.g, color.b, class end
end

local function ClassOf(unit)
    if not UnitClass then return nil end
    local _, class = UnitClass(unit)
    return class
end

-- HOSTILE / NEUTRAL / FRIENDLY, the way UnitReaction grades it (4 = neutral)
local function ReactionOf(unit)
    local reaction = UnitReaction and UnitReaction("player", unit)
    if reaction == nil then return UnitIsFriend("player", unit) and "FRIENDLY" or "HOSTILE" end
    if reaction <= 3 then return "HOSTILE" end
    if reaction == 4 then return "NEUTRAL" end
    return "FRIENDLY"
end

-- Which friend-or-foe scheme stands in wherever a colour falls back to
-- standing (an NPC under a class setting, the disc's automatic colour)
local function ReactionKey()
    return DB("ReactionScheme", "REACTION")
end

-- rgb for a colour key against this plate's unit
local function Color(rec, key)
    return Draw.ResolveColor(key, { class = ClassOf(rec.unit), reaction = ReactionOf(rec.unit) })
end

local NewQuad = Draw.NewQuad
local NewRing, RingAnchor, RingShow = Draw.NewRing, Draw.RingAnchor, Draw.RingShow
local NewHalo, HaloAnchor, HaloShow = Draw.NewHalo, Draw.HaloAnchor, Draw.HaloShow

local function HealthBar(uf)
    return uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar or uf.healthBar
end

local function CastBar(uf)
    return uf.CastBarsContainer and uf.CastBarsContainer.castBar
end

local function NameInsideBar()
    local setup, consts = NamePlateSetupOptions, NamePlateConstants
    return setup and consts and consts.NAME_ANCHOR_STYLES
        and setup.unitNameAnchorStyle == consts.NAME_ANCHOR_STYLES.InsideHealthBar
end

local function IsMine(sourceUnit)
    if not sourceUnit then return false end
    return UnitIsUnit(sourceUnit, "player") or UnitIsUnit(sourceUnit, "pet") or false
end

-- ---------------------------------------------------------------------------
-- Icons: one structure for the rows and the big slot alike.
-- ---------------------------------------------------------------------------
local function NewIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.border = NewQuad(f, "BACKGROUND")
    f.border:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    f.border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints()
    f.cd:SetReverse(true)
    if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(true) end
    if f.cd.SetDrawEdge then f.cd:SetDrawEdge(false) end
    if f.cd.SetDrawBling then f.cd:SetDrawBling(false) end
    f.cd:SetSwipeColor(0, 0, 0, 0.6)

    -- Text on its own frame, above the cooldown's swipe
    f.text = CreateFrame("Frame", nil, f)
    f.text:SetAllPoints()
    f.text:SetFrameLevel(f.cd:GetFrameLevel() + 1)
    f.count = f.text:CreateFontString(nil, "OVERLAY")
    f.count:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    f.count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, 0)
    f.timer = f.text:CreateFontString(nil, "OVERLAY")
    f.timer:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    f.timer:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.badge = f.text:CreateFontString(nil, "OVERLAY")
    f.badge:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    f.badge:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 2)
    f.badge:Hide()
    -- All three are written on the aura's own icon: see Radial.Legible
    Radial.Legible(f.count); Radial.Legible(f.timer); Radial.Legible(f.badge)

    f.glow = f:CreateTexture(nil, "OVERLAY", nil, 3)
    f.glow:SetTexture(GLOW)
    f.glow:SetBlendMode("ADD")
    f.glow:SetPoint("CENTER")
    f.glow:Hide()

    f:SetScript("OnEnter", function(self)
        if not self.unit then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.auraInstanceID and GameTooltip.SetUnitAuraByAuraInstanceID then
            pcall(GameTooltip.SetUnitAuraByAuraInstanceID, GameTooltip, self.unit, self.auraInstanceID)
        elseif self.spellId then
            pcall(GameTooltip.SetSpellByID, GameTooltip, self.spellId)
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:EnableMouse(false)
    f:Hide()
    return f
end

local function SizeIcon(f, size, textSize)
    f:SetSize(size, size)
    f.glow:SetSize(size * 1.75, size * 1.75)
    f.count:SetFont(STANDARD_TEXT_FONT, textSize, "OUTLINE")
    f.timer:SetFont(STANDARD_TEXT_FONT, textSize, "OUTLINE")
    f.badge:SetFont(STANDARD_TEXT_FONT, math.max(10, math.floor(textSize * 0.9)), "OUTLINE")
end

-- Paint one aura onto an icon. Border: kind tint, dispel tint, "mine", or
-- black. Glow: purgeable, or the big slot's category.
local function PaintIcon(f, aura, unit, opts)
    f.unit = unit
    f.auraInstanceID = aura.auraInstanceID
    f.spellId = aura.spellId
    f.expirationTime = aura.expirationTime or 0
    f.icon:SetTexture(aura.icon or DATA.FALLBACK_ICON)

    local r, g, b = PLAIN_BORDER[1], PLAIN_BORDER[2], PLAIN_BORDER[3]
    if opts.kindBorder and aura.tint then
        r, g, b = aura.tint[1], aura.tint[2], aura.tint[3]
    elseif opts.ownBorder and aura.isMine then
        r, g, b = OWN_BORDER[1], OWN_BORDER[2], OWN_BORDER[3]
    end
    f.border:SetVertexColor(r, g, b, 1)

    if opts.stacks and (aura.applications or 0) > 1 then
        f.count:SetText(aura.applications)
        f.count:Show()
    else
        f.count:Hide()
    end

    if opts.swipe and aura.duration and aura.duration > 0 and aura.expirationTime and aura.expirationTime > 0 then
        f.cd:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
        f.cd:Show()
    else
        f.cd:Hide()
    end

    if opts.glow then
        f.glow:SetVertexColor(opts.glow[1], opts.glow[2], opts.glow[3], 0.9)
        f.glow:Show()
    elseif opts.purgeGlow and aura.purgeable then
        f.glow:SetVertexColor(0.4, 0.8, 1, 0.9)
        f.glow:Show()
    else
        f.glow:Hide()
    end

    f.showTimer = opts.timer
    f.urgent = opts.urgent
    f.timer:SetShown(opts.timer == true)
    f.timer:SetTextColor(1, 1, 1)
    f.wasRed = false

    -- The DR bracket, from Commander Diminish when it is loaded and watching
    if opts.drBadge and CommanderDiminish_Brackets and aura.spellId then
        local current, nextBracket = CommanderDiminish_Brackets(opts.guid, aura.spellId)
        local label
        if current and current > 1 then
            label = DATA.BRACKET_LABEL[current]
            local tint = DATA.BRACKET_TINT[current]
            f.badge:SetTextColor(tint[1], tint[2], tint[3])
        end
        if nextBracket and nextBracket >= 4 then
            label = (label or "") .. DATA.NEXT_IMMUNE_LABEL
            f.badge:SetTextColor(0.92, 0.26, 0.26)
        end
        f.badge:SetText(label or "")
        f.badge:SetShown(label ~= nil)
    else
        f.badge:Hide()
    end

    f:EnableMouse(opts.tooltips == true)
    f:Show()
end

local function TickIcon(f, now)
    if not f.showTimer then return end
    if f.expirationTime and f.expirationTime > 0 then
        local remaining = f.expirationTime - now
        f.timer:SetText(E.FormatTime(remaining))
        if f.urgent then
            local red = remaining > 0 and remaining < 3
            if red ~= f.wasRed then
                f.wasRed = red
                if red then f.timer:SetTextColor(1, 0.3, 0.3) else f.timer:SetTextColor(1, 1, 1) end
            end
        end
    else
        f.timer:SetText("")
    end
end

-- ---------------------------------------------------------------------------
-- The overlay: everything this module draws on one plate.
-- ---------------------------------------------------------------------------
local function NewOverlay(uf)
    local ov = CreateFrame("Frame", nil, uf)
    ov:SetAllPoints(uf)
    ov:SetFrameLevel((uf:GetFrameLevel() or 1) + 5)
    ov.icons = {}
    ov.big = NewIcon(ov)
    ov.targetRing = NewRing(ov, 2)
    ov.focusRing = NewRing(ov, 2)
    ov.castRing = NewRing(ov, 2)
    ov.targetHalo = NewHalo(ov)
    ov.focusHalo = NewHalo(ov)

    ov.arrowL = ov:CreateTexture(nil, "OVERLAY", nil, 4)
    ov.arrowL:SetTexture(DATA.ARROW_ICON)
    ov.arrowR = ov:CreateTexture(nil, "OVERLAY", nil, 4)
    ov.arrowR:SetTexture(DATA.ARROW_ICON)
    ov.arrowR:SetTexCoord(1, 0, 0, 1)

    ov.classIcon = ov:CreateTexture(nil, "OVERLAY", nil, 4)
    ov.classIcon:SetTexture(DATA.CLASS_ICON)
    ov.healerIcon = ov:CreateTexture(nil, "OVERLAY", nil, 4)
    ov.healerIcon:SetTexture(DATA.HEALER_ICON)
    ov.healerIcon:SetTexCoord(unpack(DATA.HEALER_ICON_COORDS))
    ov.totemIcon = ov:CreateTexture(nil, "OVERLAY", nil, 4)
    ov.totemIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ov.totemRing = NewRing(ov, 1)

    ov.marker = NewQuad(ov, "OVERLAY", 3)
    ov.marker:SetWidth(1)
    ov.markerValue = NewQuad(ov, "OVERLAY", 3)
    ov.markerValue:SetWidth(1)

    ov.castTimer = ov:CreateFontString(nil, "OVERLAY")
    ov.castTimer:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    ov.castIcon = ov:CreateTexture(nil, "OVERLAY", nil, 4)
    ov.castIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ov.castIconBorder = NewQuad(ov, "OVERLAY", 3)
    ov.castIconBorder:SetVertexColor(0, 0, 0, 1)

    -- The radial plate is built the first time a plate needs it
    ov.orbitRound, ov.orbitSquare = {}, {}

    ov:Hide()
    return ov
end

local function HideAll(ov)
    for _, f in ipairs(ov.icons) do f:Hide() end
    ov.big:Hide()
    RingShow(ov.targetRing, false)
    RingShow(ov.focusRing, false)
    RingShow(ov.castRing, false)
    RingShow(ov.totemRing, false)
    HaloShow(ov.targetHalo, false)
    HaloShow(ov.focusHalo, false)
    ov.arrowL:Hide(); ov.arrowR:Hide()
    ov.classIcon:Hide(); ov.healerIcon:Hide(); ov.totemIcon:Hide()
    ov.marker:Hide(); ov.markerValue:Hide()
    ov.castTimer:Hide(); ov.castIcon:Hide(); ov.castIconBorder:Hide()
    if ov.radial then Radial.Clear(ov.radial) end
    for _, f in ipairs(ov.orbitRound) do f:Hide() end
    for _, f in ipairs(ov.orbitSquare) do f:Hide() end
    ov:Hide()
end

-- ---------------------------------------------------------------------------
-- Blizzard-frame state this module WRITES, and therefore restores. Alphas
-- only; nothing else on the plate is ours.
-- ---------------------------------------------------------------------------
-- Blizzard's plate textures a disc cannot hide by alpha. The selection
-- highlight (the faint bar on mouseover and target) is ignoreParentAlpha, so
-- a health bar at alpha 0 leaves it drawn; the aggro flare and flash run on
-- alpha ANIMATIONS that overwrite any alpha written to them; the behind-the-
-- camera arrow hangs off the name. Under a disc they are HIDDEN, and kept
-- hidden by a hook on their own Show / SetShown (Blizzard_NamePlates.xml on
-- classic_anniversary is where each is declared).
local RADIAL_HIDDEN = {
    "selectionHighlight", "aggroHighlightBase", "aggroHighlightAdditive",
    "aggroHighlightMask", "aggroFlash", "behindCameraIcon",
}
local guardedParts = setmetatable({}, { __mode = "k" })

local function KeepHidden(uf, tex)
    if guardedParts[tex] then return end
    guardedParts[tex] = true
    local function Guard(self)
        local rec = byUF[uf]
        if rec and rec.wasRadial and self:IsShown() then self:Hide() end
    end
    hooksecurefunc(tex, "Show", Guard)
    hooksecurefunc(tex, "SetShown", Guard)
end

local function HideRadialHighlights(uf)
    for _, key in ipairs(RADIAL_HIDDEN) do
        local tex = uf[key]
        if tex and tex.Hide then
            KeepHidden(uf, tex)
            tex:Hide()
        end
    end
end

-- Handed back in the state Blizzard's own bookkeeping says they are in
local function RestoreRadialHighlights(uf)
    if uf.selectionHighlight and CompactUnitFrame_UpdateSelectionHighlight then
        pcall(CompactUnitFrame_UpdateSelectionHighlight, uf)
    end
    if uf.aggroHighlightShown then
        for _, key in ipairs({ "aggroHighlightBase", "aggroHighlightAdditive", "aggroHighlightMask" }) do
            if uf[key] then uf[key]:Show() end
        end
    end
    if uf.behindCameraIcon then uf.behindCameraIcon:SetShown(uf.isBehindCamera == true) end
end

local function RestoreBlizzard(rec)
    local uf = rec.uf
    if uf.HealthBarsContainer then uf.HealthBarsContainer:SetAlpha(1) end
    if uf.name then uf.name:SetAlpha(1) end
    local cb = CastBar(uf)
    if cb and cb.Icon then cb.Icon:SetAlpha(1) end
    uf:SetAlpha(1)
    if uf.LevelFrame then uf.LevelFrame:SetAlpha(1) end
    if uf.CastBarsContainer then uf.CastBarsContainer:SetAlpha(1) end
    if uf.RaidTargetFrame then uf.RaidTargetFrame:SetAlpha(1) end
    if uf.ClassificationFrame then uf.ClassificationFrame:SetAlpha(1) end
    if rec.wasRadial then
        rec.wasRadial = nil
        RestoreRadialHighlights(uf)
    end
    local hb = HealthBar(uf)
    if hb and hb.bgTexture then hb.bgTexture:SetVertexColor(1, 1, 1, 1) end
    if cb and cb.Border then cb.Border:SetVertexColor(1, 1, 1, 1) end
    if rec.castTinted and cb and cb.UpdateBarFillTexture then
        rec.castTinted = nil
        pcall(cb.UpdateBarFillTexture, cb, false)
    end
end

-- ---------------------------------------------------------------------------
-- The frame around the bar -- Blizzard's border art (gold in the Classic
-- style, dark in the modern ones), tinted so a class-coloured bar still
-- reads as friend or foe at a glance
-- ---------------------------------------------------------------------------
local function ApplyBorderTint(rec)
    local uf = rec.uf
    local hb, cb = HealthBar(uf), CastBar(uf)
    local key = Enabled() and (rec.isFriend and DB("FriendlyBorderTint", "BLUE") or DB("HostileBorderTint", "RED")) or "OFF"
    local r, g, b = 1, 1, 1
    if key ~= "OFF" then r, g, b = Color(rec, key) end
    if hb and hb.bgTexture then hb.bgTexture:SetVertexColor(r, g, b, 1) end
    if cb and cb.Border then cb.Border:SetVertexColor(r, g, b, 1) end
end

-- ---------------------------------------------------------------------------
-- Colour
-- ---------------------------------------------------------------------------
local function WantClassBar(rec)
    if not Enabled() or not rec.isPlayer then return false end
    if rec.isFriend then return DB("FriendlyClassColor", true) end
    return DB("EnemyClassColor", true)
end

-- DEFAULT (leave Blizzard's), CLASS, REACTION or a palette key
local function NameColorKey(rec)
    if not Enabled() then return "DEFAULT" end
    if not rec.isPlayer then return DB("NpcNameColor", "DEFAULT") end
    if rec.isFriend then return DB("FriendlyNameColor", "CLASS") end
    return DB("EnemyNameColor", "CLASS")
end

local function ApplyHealthColor(rec)
    local uf, unit = rec.uf, rec.unit
    if not WantClassBar(rec) then return end
    if not UnitIsConnected(unit) or UnitIsDeadOrGhost(unit) then return end
    local r, g, b = ClassColor(unit)
    if not r then return end
    local bar = HealthBar(uf)
    if not bar then return end
    local oldR, oldG, oldB = bar:GetStatusBarColor()
    if oldR ~= r or oldG ~= g or oldB ~= b then
        bar:SetStatusBarColor(r, g, b)
        if uf.selectionHighlight then uf.selectionHighlight:SetVertexColor(r, g, b) end
    end
end

local function ApplyName(rec)
    local uf, unit = rec.uf, rec.unit
    local name = uf.name
    if not name or not Enabled() then return end
    if rec.isPlayer and name:IsShown() then
        local textMode = rec.isFriend and DB("FriendlyNameText", "NAME") or DB("EnemyNameText", "NAME")
        if textMode == "CLASS" then
            local localized = UnitClass(unit)
            if localized then name:SetText(localized) end
        elseif textMode == "NONE" then
            name:SetText("")
        end
    end
    local mode = DB("ArenaNumbers", "REPLACE")
    if rec.arena and mode ~= "OFF" and name:IsShown() then
        if mode == "REPLACE" then
            name:SetText(tostring(rec.arena))
        else
            local text = name:GetText() or ""
            if text == "" then
                name:SetText(tostring(rec.arena))
            elseif not text:match("^%d+ ") then
                name:SetText(rec.arena .. " " .. text)
            end
        end
    end
    local key = NameColorKey(rec)
    if key ~= "DEFAULT" and not (UnitIsDeadOrGhost(unit) and not rec.isPlayer) then
        if key == "CLASS" and not rec.isPlayer then key = ReactionKey() end   -- an NPC has no class colour
        local r, g, b = Color(rec, key)
        name:SetVertexColor(r, g, b)
    end
end

-- ---------------------------------------------------------------------------
-- Hit box
-- ---------------------------------------------------------------------------
local function ApplyHitBox(rec)
    local plate, uf = rec.plate, rec.uf
    if not plate or not plate.SetHitTestPoints then return end
    if not Enabled() then return end
    if plate.CanChangeHitTestPoints and not plate:CanChangeHitTestPoints() then
        hitBoxPending = true
        return
    end
    local hb = HealthBar(uf)
    if not hb then return end
    local box = E.HitBox(S, rec.isFriend, inInstance)
    local points
    if box.clickThrough then
        -- A zero-area box: the plate is still there, the mouse goes through it
        points = {
            { point = "TOPLEFT", relativeTo = hb, relativePoint = "TOPLEFT", offsetX = 0, offsetY = 0 },
            { point = "BOTTOMRIGHT", relativeTo = hb, relativePoint = "TOPLEFT", offsetX = 0, offsetY = 0 },
        }
    elseif rec.radial then
        -- The disc and the name under it, from the bar's centre where the
        -- disc is anchored
        local cfg = radialCfg
        local half = cfg.radii.outer
        local below = half + ((cfg.name == "BELOW") and (cfg.nameSize + 4) or 0)
        local above = half + ((cfg.name == "ABOVE") and (cfg.nameSize + 4) or 0)
        points = {
            { point = "TOPLEFT", relativeTo = hb, relativePoint = "CENTER",
              offsetX = -(half + box.sides), offsetY = cfg.offsetY + above + box.top },
            { point = "BOTTOMRIGHT", relativeTo = hb, relativePoint = "CENTER",
              offsetX = half + box.sides, offsetY = cfg.offsetY - below - box.bottom },
        }
    elseif box.top == 0 and box.bottom == 0 and box.sides == 0 then
        return -- Blizzard's own box stands
    else
        -- Blizzard's box, then ours on top of it (NamePlateUnitFrameMixin:ApplyFrameOptions)
        local setup = NamePlateSetupOptions
        local halfH = ((setup and setup.healthBarHeight) or 10) / 2
        local extraX = 10 + box.sides
        if NameInsideBar() or not uf.name then
            points = {
                { point = "TOPLEFT", relativeTo = hb, relativePoint = "TOPLEFT", offsetX = -extraX, offsetY = halfH + box.top },
                { point = "BOTTOMRIGHT", relativeTo = hb, relativePoint = "BOTTOMRIGHT", offsetX = extraX, offsetY = -(halfH + box.bottom) },
            }
        else
            points = {
                { point = "TOPLEFT", relativeTo = uf.name, relativePoint = "TOPLEFT", offsetX = -extraX - 4, offsetY = box.top },
                { point = "BOTTOMRIGHT", relativeTo = hb, relativePoint = "BOTTOMRIGHT", offsetX = extraX, offsetY = -(halfH + box.bottom) },
            }
        end
    end
    pcall(plate.SetHitTestPoints, plate, points)
end

-- ---------------------------------------------------------------------------
-- The radial plate. Blizzard's plate stays exactly where it is and goes to
-- alpha 0 -- the one kind of write this module already makes and restores --
-- and a disc drawn by CommanderPlatesRadial.lua takes its place on the same
-- anchor, so the client's stacking, scaling and clamping carry it unchanged.
-- ---------------------------------------------------------------------------
local POWER_FALLBACK = {
    MANA = { 0.00, 0.55, 1.00 }, RAGE = { 1.00, 0.00, 0.00 },
    ENERGY = { 1.00, 1.00, 0.00 }, FOCUS = { 1.00, 0.50, 0.25 },
}
local ELITE_RIM = { 1.00, 0.82, 0.20 }
local RARE_RIM = { 0.80, 0.86, 0.96 }

local function UsesCombo()
    return playerClass == "ROGUE" or playerClass == "DRUID"
end

local function RadialWidget(rec)
    local ov = rec.ov
    if not ov.radial then ov.radial = Radial.New(ov) end
    return ov.radial
end

-- Every piece of Blizzard's plate the disc replaces, as a list so hiding and
-- giving back can never disagree about what was hidden
local function BlizzardParts(uf)
    return { uf.HealthBarsContainer, uf.name, uf.CastBarsContainer, uf.LevelFrame,
        uf.RaidTargetFrame, uf.ClassificationFrame }
end

local function HideBlizzardForRadial(rec)
    local parts = BlizzardParts(rec.uf)
    for i = 1, 6 do
        local part = parts[i]
        if part and part.SetAlpha then part:SetAlpha(0) end
    end
    rec.wasRadial = true
    HideRadialHighlights(rec.uf)
end

-- The bar-mode layer, all of it: a radial plate draws none of it
local function HideClassicLayer(ov)
    for _, f in ipairs(ov.icons) do f:Hide() end
    ov.big:Hide()
    RingShow(ov.targetRing, false)
    RingShow(ov.focusRing, false)
    RingShow(ov.castRing, false)
    RingShow(ov.totemRing, false)
    HaloShow(ov.targetHalo, false)
    HaloShow(ov.focusHalo, false)
    ov.arrowL:Hide(); ov.arrowR:Hide()
    ov.classIcon:Hide(); ov.healerIcon:Hide(); ov.totemIcon:Hide()
    ov.marker:Hide(); ov.markerValue:Hide()
    ov.castTimer:Hide(); ov.castIcon:Hide(); ov.castIconBorder:Hide()
end

local function HideOrbit(ov)
    for _, f in ipairs(ov.orbitRound) do f:Hide() end
    for _, f in ipairs(ov.orbitSquare) do f:Hide() end
end

-- The plate went back to being a bar: every piece comes back
local function ReleaseRadial(rec)
    if not rec.wasRadial then return end
    rec.wasRadial = nil
    local parts = BlizzardParts(rec.uf)
    for i = 1, 6 do
        local part = parts[i]
        if part and part.SetAlpha then part:SetAlpha(1) end
    end
    RestoreRadialHighlights(rec.uf)
    if rec.ov.radial then Radial.Clear(rec.ov.radial) end
    HideOrbit(rec.ov)
    rec.coreCC, rec.castCore, rec.casting, rec.loudCast = nil, nil, nil, nil
end

-- What the name label says: the same rules the bar mode applies to
-- Blizzard's own name text
local function DisplayName(rec)
    local unit = rec.unit
    local text = UnitName(unit) or ""
    if rec.isPlayer then
        local mode = rec.isFriend and DB("FriendlyNameText", "NAME") or DB("EnemyNameText", "NAME")
        if mode == "CLASS" then
            text = UnitClass(unit) or text
        elseif mode == "NONE" then
            text = ""
        end
    end
    local arenaMode = DB("ArenaNumbers", "REPLACE")
    if rec.arena and arenaMode ~= "OFF" then
        if arenaMode == "REPLACE" or text == "" then
            text = tostring(rec.arena)
        else
            text = rec.arena .. " " .. text
        end
    end
    return text
end

local function NameRGB(rec)
    local key = NameColorKey(rec)
    if key == "DEFAULT" then
        if rec.isPlayer then return 1, 1, 1 end
        key = ReactionKey()
    end
    if key == "CLASS" and not rec.isPlayer then key = ReactionKey() end
    return Color(rec, key)
end

local function HealthRGB(rec, fraction)
    local cfg, unit = radialCfg, rec.unit
    if cfg.lowHealth > 0 and fraction > 0 and fraction * 100 < cfg.lowHealth then
        return Color(rec, cfg.lowColor)
    end
    if not rec.isPlayer and UnitIsTapDenied and UnitIsTapDenied(unit) then
        return 0.55, 0.55, 0.55
    end
    local key = cfg.healthColor
    if key == "AUTO" then
        if rec.isPlayer and WantClassBar(rec) then
            local r, g, b = ClassColor(unit)
            if r then return r, g, b end
        end
        key = ReactionKey()
    end
    if key == "CLASS" and not rec.isPlayer then key = ReactionKey() end
    return Color(rec, key)
end

-- The thin ring round the face: standing, rank, or the control it sits in
local function RadialRim(rec)
    local w, cfg = rec.ov.radial, radialCfg
    if not w then return end
    local r, g, b
    local cls = rec.classification
    if rec.coreCC and rec.coreCC.tint then
        r, g, b = unpack(rec.coreCC.tint)
    elseif cfg.eliteRim and (cls == "elite" or cls == "worldboss") then
        r, g, b = unpack(ELITE_RIM)
    elseif cfg.eliteRim and (cls == "rare" or cls == "rareelite") then
        r, g, b = unpack(RARE_RIM)
    elseif cfg.rimColor == "OFF" then
        r, g, b = 0, 0, 0
    else
        local key = cfg.rimColor
        if key == "CLASS" and not rec.isPlayer then key = ReactionKey() end
        r, g, b = Color(rec, key)
    end
    if cfg.mouseover and rec.mouseover then
        r, g, b = (r + 1) / 2, (g + 1) / 2, (b + 1) / 2
    end
    Radial.SetRim(w, r, g, b, 1)
end

-- The middle of the disc: a control's seconds, a cast's seconds, or what
-- the Core Text setting asks for
local function RadialCenterText(rec, now)
    local w, cfg = rec.ov.radial, radialCfg
    if not w then return end
    local text, r, g, b = "", 1, 1, 1
    local cc, cast = rec.coreCC, rec.castCore
    if cc then
        if DB("CcTimer", true) and cc.expiration and cc.expiration > 0 then
            local left = cc.expiration - now
            text = E.FormatTime(left)
            if DB("AuraTimerUrgent", true) and left > 0 and left < 3 then r, g, b = 1, 0.3, 0.3 end
        end
    elseif cast then
        if DB("CastTimer", true) and rec.castEnd then
            local left = rec.castEnd - now
            text = left > 0 and string.format("%.1f", left) or ""
        end
    elseif rec.dead then
        text, r, g, b = "Dead", 0.7, 0.7, 0.7
    else
        local arena = (rec.arena and DB("ArenaNumbers", "REPLACE") ~= "OFF") and rec.arena or nil
        text = E.CoreText(cfg.coreText, rec.hpFrac or 1, rec.hpValue, arena)
    end
    if w.lastCenter == text and w.lastCenterR == r then return end
    w.lastCenter, w.lastCenterR = text, r
    Radial.SetCenterText(w, text, r, g, b)
end

-- The face itself: control beats cast beats identity. `force` redraws a
-- portrait whose unit has not changed but whose picture has.
local function PaintRadialCore(rec, force)
    local w, cfg = rec.ov.radial, radialCfg
    if not w then return end
    local cc, cast = rec.coreCC, rec.castCore
    local showsClass = false
    if cc then
        Radial.SetCore(w, "ICON", cc.icon)
        Radial.SetCoreSwipe(w, cc.start, cc.duration)
        Radial.SetDrBadge(w, cc.drText, cc.drR, cc.drG, cc.drB)
    elseif cast then
        Radial.SetCore(w, "ICON", cast.icon)
        Radial.SetCoreSwipe(w, nil)
        Radial.SetDrBadge(w, nil)
    else
        Radial.SetCoreSwipe(w, nil)
        Radial.SetDrBadge(w, nil)
        local art = cfg.coreArt
        if art == "CLASS" and rec.isPlayer and rec.class then
            Radial.SetCore(w, "CLASS", rec.class)
            showsClass = true
        elseif art == "CLASS" or art == "PORTRAIT" then
            -- Keyed by GUID, not token: a pooled token is somebody else next
            Radial.SetCore(w, "PORTRAIT", rec.unit, nil, force or w.coreGuid ~= rec.guid)
            w.coreGuid = rec.guid
        else
            Radial.SetCore(w, "NONE")
        end
    end
    -- Whenever the face is not the class, the class rides the rim as a badge
    local wantBadge = rec.isPlayer and not showsClass
        and ((rec.isFriend and DB("ClassIconFriendly", false)) or (not rec.isFriend and DB("ClassIconEnemy", true)))
    Radial.SetClassBadge(w, wantBadge and rec.class or nil)
    RadialRim(rec)
    w.lastCenter = nil
    RadialCenterText(rec, GetTime())
end

local function RadialHealth(rec, now)
    local w, cfg, unit = rec.ov.radial, radialCfg, rec.unit
    if not w then return end
    local cur, max = UnitHealth(unit) or 0, UnitHealthMax(unit) or 0
    local fraction = UnitIsDeadOrGhost(unit) and 0 or E.Fraction(cur, max)
    rec.hpFrac = fraction
    local value = cur
    if max == 100 and rec.isPlayer then
        value = nil
        if Commander.Health and Commander.Health.Current then
            value = Commander.Health.Current(unit)
        end
    end
    rec.hpValue = value
    local heal = 0
    if cfg.healPredict and UnitGetIncomingHeals and max > 100 then
        heal = (UnitGetIncomingHeals(unit) or 0) / max
    end
    local r, g, b = HealthRGB(rec, fraction)
    Radial.SetHealth(w, cfg, fraction, r, g, b, now, heal)
    rec.dead = UnitIsDeadOrGhost(unit) and true or false
    Radial.SetDead(w, rec.dead)

    -- The two markers the bar draws as lines, as ticks across the arc
    if rec.isFriend then
        Radial.SetMarker(w, "pct", nil)
        Radial.SetMarker(w, "value", nil)
    else
        local pct = tonumber(DB("HealthMarkerPercent", 0)) or 0
        Radial.SetMarker(w, "pct", pct / 100, 1, 1, 1)
        local mark = tonumber(DB("HealthMarkerValue", 0)) or 0
        local maxHealth = mark > 0 and max or 0
        if maxHealth == 100 and Commander.Health and Commander.Health.Current then
            local _, est = Commander.Health.Current(unit)
            maxHealth = est or 0
        end
        Radial.SetMarker(w, "value", maxHealth > 0 and mark / maxHealth or nil, 1, 0.82, 0.2)
    end
    if not (rec.coreCC or rec.castCore) then RadialCenterText(rec, now) end
end

local function WantPower(rec)
    local mode = radialCfg.powerMode
    if mode == "ALL" then return true end
    if mode == "PLAYERS" then return rec.isPlayer end
    if mode == "MANA" then return rec.isPlayer and rec.powerToken == "MANA" end
    return false
end

local function RadialPower(rec, now)
    local w, cfg, unit = rec.ov.radial, radialCfg, rec.unit
    if not w then return end
    local _, token = UnitPowerType(unit)
    rec.powerToken = token
    local max = UnitPowerMax(unit) or 0
    if not WantPower(rec) or max <= 0 then
        Radial.SetPower(w, cfg, nil)
        return
    end
    local color = (PowerBarColor and token and PowerBarColor[token]) or POWER_FALLBACK[token] or POWER_FALLBACK.MANA
    local r, g, b = color.r or color[1], color.g or color[2], color.b or color[3]
    Radial.SetPower(w, cfg, E.Fraction(UnitPower(unit), max), r, g, b, now)
end

-- The warning halo: a loud cast outranks threat while it lasts
local function RadialAlert(rec)
    local w, cfg = rec.ov.radial, radialCfg
    if not w then return end
    if rec.loudCast then
        Radial.SetAlert(w, true, rec.loudCast[1], rec.loudCast[2], rec.loudCast[3], 0.9)
        return
    end
    if rec.isPlayer or cfg.threat == "OFF" or not UnitThreatSituation then
        Radial.SetAlert(w, false)
        return
    end
    local tint = E.ThreatTint(cfg.threat, UnitThreatSituation("player", rec.unit))
    if tint then
        Radial.SetAlert(w, true, Color(rec, tint))
    else
        Radial.SetAlert(w, false)
    end
end

local function RadialRaid(rec)
    local w = rec.ov.radial
    if not w then return end
    local index = radialCfg.raid and GetRaidTargetIndex and GetRaidTargetIndex(rec.unit) or nil
    Radial.SetRaid(w, index)
end

-- Name, level and raid marker: who this is, independent of what it is doing
local function RadialIdentity(rec)
    local w, cfg, unit = rec.ov.radial, radialCfg, rec.unit
    if not w then return end
    local reserve = (cfg.combo and UsesCombo()) and (cfg.pipSize + 2) or 0
    local nr, ng, nb = NameRGB(rec)
    Radial.SetName(w, cfg, DisplayName(rec), nr, ng, nb, reserve)
    Radial.SetBacking(w, 0, 0, 0, 0.85)
    -- The backdrop: dark, or a dimmed tint of the class or the standing
    local br, bg, bb = 0.02, 0.02, 0.03
    if cfg.backdrop == "CLASS" or cfg.backdrop == "REACTION" then
        local key = (cfg.backdrop == "CLASS" and rec.isPlayer) and "CLASS" or ReactionKey()
        local r, g, b = Color(rec, key)
        br, bg, bb = r * 0.28, g * 0.28, b * 0.28
    end
    Radial.SetBackdrop(w, br, bg, bb, cfg.backdropAlpha, cfg.backdropBorder)
    if cfg.level and not rec.isPlayer and UnitLevel then
        local level = UnitLevel(unit) or 0
        local text = level > 0 and tostring(level) or "??"
        local cls = rec.classification
        if cls == "elite" or cls == "rareelite" or cls == "worldboss" then text = text .. "+" end
        local r, g, b = 1, 0.1, 0.1
        if level > 0 then
            local c = GetCreatureDifficultyColor and GetCreatureDifficultyColor(level)
            if c then r, g, b = c.r, c.g, c.b else r, g, b = 1, 0.82, 0 end
        end
        Radial.SetLevel(w, text, r, g, b)
    else
        Radial.SetLevel(w, nil)
    end
    RadialRaid(rec)
end

-- Round the disc: debuffs over the top, buffs down the side, and the control
-- the unit is sitting in either takes the face or floats above it all
local function RadialAuras(rec, pick)
    local ov, w, cfg, unit = rec.ov, rec.ov.radial, radialCfg, rec.unit
    if not w then return end
    local round = cfg.roundAuras
    local pool, other = ov.orbitRound, ov.orbitSquare
    if not round then pool, other = other, pool end
    for _, f in ipairs(other) do f:Hide() end

    local nd, nb = #pick.debuffs, #pick.buffs
    for i = #pool + 1, nd + nb do
        pool[i] = round and Radial.NewOrbitIcon(w.auraLayer) or NewIcon(w.auraLayer)
    end
    for i = nd + nb + 1, #pool do pool[i]:Hide() end

    local size = cfg.auraSize
    local textSize = math.max(8, math.floor(size * 0.55))
    local opts = {
        kindBorder = DB("AuraKindBorder", true), ownBorder = DB("AuraOwnBorder", true),
        stacks = DB("AuraStacks", true), swipe = DB("AuraSwipe", true),
        timer = DB("AuraTimer", true), purgeGlow = DB("PurgeGlow", true),
        tooltips = DB("AuraTooltips", false), urgent = DB("AuraTimerUrgent", true),
    }
    local index = 1
    for _, list in ipairs({ pick.debuffs, pick.buffs }) do
        for _, aura in ipairs(list) do
            local f = pool[index]; index = index + 1
            SizeIcon(f, size, textSize)
            PaintIcon(f, aura, unit, opts)
        end
    end
    local slotsD = Radial.LayoutOrbit(w, cfg, pool, 1, nd, cfg.debuffArc, cfg.debuffGrow)
    local slotsB = Radial.LayoutOrbit(w, cfg, pool, nd + 1, nb, cfg.buffArc, cfg.buffGrow)
    local all = {}
    for _, s in ipairs(slotsD) do all[#all + 1] = s end
    for _, s in ipairs(slotsB) do all[#all + 1] = s end
    rec.orbitLeft, rec.orbitRight = E.OrbitSideExtents(all, size, DB("TargetArrowSize", 22) / 2)

    local big = pick.big
    local spec = big and big.kind and DATA.KIND[big.kind]
    if big and cfg.coreCC then
        ov.big:Hide()
        local cc = {
            icon = big.icon, tint = spec and spec.tint,
            expiration = big.expirationTime or 0,
            duration = big.duration or 0,
        }
        cc.start = cc.expiration - cc.duration
        if DB("CcDrBadge", true) and CommanderDiminish_Brackets and big.spellId then
            local current, nextBracket = CommanderDiminish_Brackets(rec.guid, big.spellId)
            if current and current > 1 then
                cc.drText = DATA.BRACKET_LABEL[current]
                cc.drR, cc.drG, cc.drB = unpack(DATA.BRACKET_TINT[current])
            end
            if nextBracket and nextBracket >= 4 then
                cc.drText = (cc.drText or "") .. DATA.NEXT_IMMUNE_LABEL
                cc.drR, cc.drG, cc.drB = 0.92, 0.26, 0.26
            end
        end
        rec.coreCC = cc
    elseif big then
        rec.coreCC = nil
        local ccSize = DB("CcSize", 36)
        SizeIcon(ov.big, ccSize, math.max(11, math.floor(ccSize * 0.38)))
        PaintIcon(ov.big, big, unit, {
            kindBorder = true, stacks = false, swipe = true,
            timer = DB("CcTimer", true), tooltips = opts.tooltips, urgent = opts.urgent,
            glow = (DB("CcGlow", true) and spec) and spec.tint or nil,
            drBadge = DB("CcDrBadge", true), guid = rec.guid,
        })
        -- Above the disc and whatever orbits over the top of it
        local top = cfg.radii.outer
        for _, s in ipairs(all) do
            if s[2] > 0 then top = math.max(top, s[2] + size / 2) end
        end
        ov.big:ClearAllPoints()
        ov.big:SetPoint("BOTTOM", w, "CENTER", 0, top + 2 + DB("CcOffsetY", 0))
    else
        rec.coreCC = nil
        ov.big:Hide()
    end
    PaintRadialCore(rec)
end

-- Combo points on the target's disc
local function RadialCombo(rec)
    local w, cfg = rec.ov.radial, radialCfg
    if not w then return end
    local combo = 0
    if cfg.combo and GetComboPoints and UnitIsUnit(rec.unit, "target") then
        combo = GetComboPoints("player", "target") or 0
    end
    if rec.combo ~= combo then
        rec.combo = combo
        Radial.SetPips(w, cfg, combo, 5)
    end
end

-- Target and focus: the halo, the arrows, the size, the combo points
local function RadialTarget(rec)
    local ov, w, cfg, unit = rec.ov, rec.ov.radial, radialCfg, rec.unit
    if not w then return end
    local hbc = rec.uf.HealthBarsContainer or HealthBar(rec.uf) or rec.uf
    local isTarget = UnitIsUnit(unit, "target")
    local isFocus = UnitIsUnit(unit, "focus")
    Radial.Place(w, hbc, cfg, isTarget)

    local gr, gg, gb = Color(rec, DB("TargetGlowColor", "WHITE"))
    if isTarget and DB("TargetGlow", true) then
        Radial.SetGlow(w, true, gr, gg, gb, DB("TargetGlowAlpha", 0.75), cfg.glowMotion)
    elseif isFocus and DB("FocusGlow", true) then
        local fr, fg, fb = Color(rec, DB("FocusGlowColor", "MAGENTA"))
        Radial.SetGlow(w, true, fr, fg, fb, DB("TargetGlowAlpha", 0.75), cfg.glowMotion)
    else
        Radial.SetGlow(w, false)
    end
    Radial.SetArrows(w, cfg, isTarget and DB("TargetArrows", true), DB("TargetArrowSize", 22),
        gr, gg, gb, math.max(rec.orbitLeft or 0, rec.drLeft or 0), math.max(rec.orbitRight or 0, rec.drRight or 0))

    Radial.SetHealer(w, DB("HealerIcon", true) and rec.isPlayer and not rec.isFriend
        and healers:Is(rec.guid, GetTime()))

    RadialCombo(rec)
end

-- Diminishing returns round the disc, from Commander Diminish when it is
-- loaded and watching this unit
local DR_SCRATCH = {}
local function DrIcon(spellId, cat)
    -- A ladder's picture is Commander Diminish's to choose (its Icons
    -- setting: the category's own, or the last spell's), so the same ladder
    -- is the same icon on the plate as everywhere else it is drawn
    if cat and CommanderDiminish_Icon then
        local icon = CommanderDiminish_Icon(cat, spellId)
        if icon then return icon end
    end
    if not spellId then return DATA.FALLBACK_ICON end
    return (GetSpellTexture and GetSpellTexture(spellId))
        or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellId))
        or DATA.FALLBACK_ICON
end

local function WantDr(rec)
    local mode = radialCfg.drMode
    if mode == "OFF" or not CommanderDiminish_Open then return false end
    if mode == "ENEMIES" then return not rec.isFriend end
    if mode == "ENEMY_PLAYERS" then return rec.isPlayer and not rec.isFriend end
    return true
end

local function RadialDr(rec, now)
    local w = rec.ov.radial
    if not w then return end
    local open = WantDr(rec) and CommanderDiminish_Open(rec.guid, now, DR_SCRATCH) or nil
    local reset = (CommanderDiminish_Data and CommanderDiminish_Data.DR_RESET) or 15
    rec.drRows = E.DrRows(open, reset, DrIcon, rec.drRows)
    local slots = Radial.SetDrStrip(w, radialCfg, rec.drRows, radialCfg.drArc)
    local size = math.max(10, math.floor(radialCfg.auraSize * 0.85))
    rec.drLeft, rec.drRight = E.OrbitSideExtents(slots, size, DB("TargetArrowSize", 22) / 2)
end

-- The PvP trinket: the one enemy cooldown the client answers for, and only
-- for an arena seat (see Commander Arena Frames, which reads it the same way)
local function RadialTrinket(rec)
    local w = rec.ov.radial
    if not w then return end
    if not (radialCfg.trinket and rec.arena and C_PvP and C_PvP.GetArenaCrowdControlInfo) then
        Radial.SetTrinket(w, nil)
        return
    end
    local ok, spellId, startMS, durationMS = pcall(C_PvP.GetArenaCrowdControlInfo, "arena" .. rec.arena)
    if not ok or not spellId then
        Radial.SetTrinket(w, nil)
        return
    end
    local start, duration
    if startMS and durationMS and startMS > 0 and durationMS > 0 then
        start, duration = startMS / 1000, durationMS / 1000
    end
    Radial.SetTrinket(w, DrIcon(spellId), start, duration)
end

local function RequestTrinkets()
    if not (C_PvP and C_PvP.RequestCrowdControlSpell) then return end
    for i = 1, 5 do
        if UnitExists("arena" .. i) then pcall(C_PvP.RequestCrowdControlSpell, "arena" .. i) end
    end
end

-- An enemy whose target is you
local function RadialTargetsYou(rec)
    local w, cfg = rec.ov.radial, radialCfg
    if not w then return end
    local shown = E.WantTargetsYou(cfg.targetsYou, rec.isPlayer, rec.isFriend)
        and UnitIsUnit(rec.unit .. "target", "player") or false
    if shown ~= rec.targetsYou then
        rec.targetsYou = shown
        if shown then
            Radial.SetTargetsYou(w, true, Color(rec, cfg.targetsYouColor))
        else
            Radial.SetTargetsYou(w, false)
        end
    end
end

-- Who a cast is aimed at, as the cast line's tail: their name in their
-- colour, or YOU in red
local function CastTargetText(rec)
    local token = rec.unit .. "target"
    if not UnitExists(token) then return nil end
    if UnitIsUnit(token, "player") then return "|cffff4040YOU|r" end
    local name = UnitName(token)
    if not name or name == "" then return nil end
    local r, g, b
    if UnitIsPlayer(token) then r, g, b = ClassColor(token) end
    if not r then r, g, b = Draw.ResolveColor(ReactionKey(), { reaction = ReactionOf(token) }) end
    return string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), name)
end

local function PaintCastLine(rec)
    local w = rec.ov.radial
    local line = rec.castLine
    if not (w and line) then return end
    local text = line.name
    if radialCfg.castTarget and line.target then text = text .. " \194\187 " .. line.target end
    Radial.SetCastName(w, text, line.r, line.g, line.b)
end

-- The cast, read straight from the unit: Blizzard's bar is invisible now,
-- but UnitCastingInfo was always the truth it drew
local function TickRadialCast(rec, now)
    local w, cfg, unit = rec.ov.radial, radialCfg, rec.unit
    if not w then return end
    local name, _, texture, startMS, endMS, _, _, notInterruptible = UnitCastingInfo(unit)
    local channel = false
    if not name then
        name, _, texture, startMS, endMS, _, notInterruptible = UnitChannelInfo(unit)
        channel = name ~= nil
    end
    if not name or not startMS or not endMS then
        if rec.casting then
            rec.casting, rec.castCore, rec.castEnd, rec.loudCast, rec.castLine = nil, nil, nil, nil, nil
            Radial.ClearCast(w)
            Radial.SetCastName(w, nil)
            PaintRadialCore(rec)
            RadialAlert(rec)
        end
        return
    end
    -- Pushback moves the end, so the end is part of what "the same cast" means
    local key = name .. ":" .. startMS .. ":" .. endMS
    if rec.casting ~= key then
        rec.casting = key
        local loud = DB("CastEmphasis", true) and E.IsEmphasised(emphasis, name)
        local r, g, b
        if notInterruptible then
            r, g, b = Color(rec, cfg.shieldColor)
        elseif loud then
            r, g, b = Color(rec, DB("CastEmphasisColor", "RED"))
        else
            r, g, b = Color(rec, cfg.castColor)
        end
        rec.loudCast = loud and { r, g, b } or nil
        rec.castEnd = endMS / 1000
        Radial.SetCast(w, cfg, startMS / 1000, (endMS - startMS) / 1000, channel, r, g, b)
        if cfg.castName then
            rec.castLine = { name = name, r = r, g = g, b = b, target = CastTargetText(rec) }
            PaintCastLine(rec)
        else
            rec.castLine = nil
            Radial.SetCastName(w, nil)
        end
        rec.castCore = (cfg.coreCast and not rec.coreCC) and { icon = texture } or nil
        PaintRadialCore(rec)
        RadialAlert(rec)
    elseif rec.castLine and cfg.castTarget then
        -- The caster may swap targets mid-cast; the line follows
        local target = CastTargetText(rec)
        if target ~= rec.castLine.target then
            rec.castLine.target = target
            PaintCastLine(rec)
        end
    end
end

-- Kicked: the burst on the ring, and "Interrupted" where the spell name was
local function RadialInterrupted(rec)
    local w = rec.ov.radial
    if not (w and radialCfg.interruptFlash) then return end
    Radial.Flash(w, 1, 0.25, 0.25, "Interrupted")
end

-- ---------------------------------------------------------------------------
-- Auras
-- ---------------------------------------------------------------------------
local function ReadAuras(rec)
    local unit = rec.unit
    local list = rec.auras
    local n = 0
    for _, filter in ipairs({ "HARMFUL", "HELPFUL" }) do
        for i = 1, MAX_AURAS do
            local a = C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
            if not a then break end
            n = n + 1
            local t = list[n]
            if not t then t = {}; list[n] = t end
            t.name = a.name
            t.spellId = a.spellId
            t.icon = a.icon
            t.isHarmful = filter == "HARMFUL"
            -- sourceUnit ONLY. AuraData.isFromPlayerOrPlayerPet is the old
            -- castByPlayer flag on this client -- "cast by A player rather
            -- than an NPC" -- so on a friendly player it is true for every
            -- buff they have, and a "mine" filter built on it shows everything
            -- (seen in the field 2026-09-12). Blizzard's own friendly buff list
            -- trusts sourceUnit alone, and so does this.
            t.isMine = IsMine(a.sourceUnit)
            t.isStealable = a.isStealable == true
            t.dispelName = a.dispelName
            t.applications = a.applications or 0
            t.duration = a.duration or 0
            t.expirationTime = a.expirationTime or 0
            t.auraInstanceID = a.auraInstanceID
            t.kind, t.tint, t.dispellable, t.purgeable = nil, nil, nil, nil
        end
    end
    for i = #list, n + 1, -1 do list[i] = nil end
    return list
end

local function RowAnchor(rec)
    local uf = rec.uf
    if uf.name and uf.name:IsShown() and not NameInsideBar() then
        return uf.name
    end
    return uf.HealthBarsContainer or HealthBar(uf)
end

local function LayoutRow(icons, startIndex, list, anchor, baseY, below, size, spacing, grow, perRow)
    local slots = E.RowLayout(#list, size, spacing, grow, perRow)
    for i, aura in ipairs(list) do
        local f = icons[startIndex + i - 1]
        local x, y = slots[i][1], slots[i][2]
        f:ClearAllPoints()
        if below then
            f:SetPoint("CENTER", anchor, "BOTTOM", x, -(baseY + y))
        else
            f:SetPoint("CENTER", anchor, "TOP", x, baseY + y)
        end
    end
    local lines = math.ceil(#list / math.max(1, perRow))
    return lines * (size + spacing)
end

local function TrackingHere()
    return DB("TrackWhere", "ALWAYS") ~= "INSTANCES" or inInstance
end

local function HideAuraLayer(ov)
    for _, f in ipairs(ov.icons) do f:Hide() end
    ov.big:Hide()
end

local function RefreshAuras(rec)
    local ov, uf, unit = rec.ov, rec.uf, rec.unit
    if not Enabled() then return end
    if not TrackingHere() then
        HideAuraLayer(ov)
        rec.rowsHeight, rec.bigWhere = 0, nil
        if rec.radial then
            HideOrbit(ov)
            if rec.coreCC then rec.coreCC = nil; PaintRadialCore(rec) end
        end
        return
    end
    local auras = ReadAuras(rec)
    local pick = E.Select(auras, {
        isFriend = rec.isFriend, isPlayer = rec.isPlayer,
        canDispel = canDispel, canPurge = canPurge,
        S = S, whitelist = whitelist, blacklist = blacklist,
    })
    if rec.radial then
        for _, f in ipairs(ov.icons) do f:Hide() end
        RadialAuras(rec, pick)
        RadialDr(rec, GetTime())
        ov:Show()
        return
    end

    local size = DB("AuraSize", 22)
    local spacing = DB("AuraSpacing", 2)
    local perRow = DB("AuraPerRow", 6)
    local grow = DB("AuraGrow", "CENTER")
    local textSize = DB("AuraTimerSize", 11)
    local opts = {
        kindBorder = DB("AuraKindBorder", true), ownBorder = DB("AuraOwnBorder", true),
        stacks = DB("AuraStacks", true), swipe = DB("AuraSwipe", true),
        timer = DB("AuraTimer", true), purgeGlow = DB("PurgeGlow", true),
        tooltips = DB("AuraTooltips", false), urgent = DB("AuraTimerUrgent", true),
    }

    local needed = #pick.debuffs + #pick.buffs
    for i = #ov.icons + 1, needed do ov.icons[i] = NewIcon(ov) end
    for i, f in ipairs(ov.icons) do
        if i > needed then f:Hide() end
    end

    local index = 1
    for _, aura in ipairs(pick.debuffs) do
        local f = ov.icons[index]; index = index + 1
        SizeIcon(f, size, textSize)
        PaintIcon(f, aura, unit, opts)
    end
    for _, aura in ipairs(pick.buffs) do
        local f = ov.icons[index]; index = index + 1
        SizeIcon(f, size, textSize)
        PaintIcon(f, aura, unit, opts)
    end

    -- Rows: debuffs above the name (or bar), buffs above those or under the plate
    local anchor = RowAnchor(rec)
    local pad = 4
    local used = 0
    if #pick.debuffs > 0 then
        used = LayoutRow(ov.icons, 1, pick.debuffs, anchor, pad, false, size, spacing, grow, perRow)
    end
    if #pick.buffs > 0 then
        if DB("BuffRowPosition", "ABOVE") == "BELOW" then
            local cbc = uf.CastBarsContainer or uf
            LayoutRow(ov.icons, #pick.debuffs + 1, pick.buffs, cbc, pad, true, size, spacing, grow, perRow)
        else
            used = used + LayoutRow(ov.icons, #pick.debuffs + 1, pick.buffs, anchor, pad + used, false, size, spacing, grow, perRow)
        end
    end
    rec.rowsHeight = used

    -- The big slot
    local big = pick.big
    if big then
        local ccSize = DB("CcSize", 36)
        SizeIcon(ov.big, ccSize, math.max(11, math.floor(ccSize * 0.38)))
        local spec = big.kind and DATA.KIND[big.kind]
        PaintIcon(ov.big, big, unit, {
            kindBorder = true, stacks = false, swipe = true,
            timer = DB("CcTimer", true), tooltips = opts.tooltips, urgent = opts.urgent,
            glow = (DB("CcGlow", true) and spec) and spec.tint or nil,
            drBadge = DB("CcDrBadge", true), guid = rec.guid,
        })
        local hbc = uf.HealthBarsContainer or HealthBar(uf)
        local where = DB("CcAnchor", "ABOVE")
        local dy = DB("CcOffsetY", 0)
        ov.big:ClearAllPoints()
        if where == "LEFT" then
            ov.big:SetPoint("RIGHT", hbc, "LEFT", -(rec.leftUsed or 4), dy)
        elseif where == "RIGHT" then
            ov.big:SetPoint("LEFT", hbc, "RIGHT", 4, dy)
        elseif where == "ABOVE" then
            ov.big:SetPoint("BOTTOM", anchor, "TOP", 0, pad + used + 2 + dy)
        elseif where == "BELOW" then
            ov.big:SetPoint("TOP", uf.CastBarsContainer or hbc, "BOTTOM", 0, -4 + dy)
        else
            ov.big:SetPoint("CENTER", hbc, "CENTER", 0, dy)
        end
        rec.bigWhere = where
    else
        ov.big:Hide()
        rec.bigWhere = nil
    end
    ov:Show()
end

-- ---------------------------------------------------------------------------
-- Identity: arrows, glows, class icon, healer cross, totem, marker
-- ---------------------------------------------------------------------------
local function GlowColor(rec)
    return Color(rec, DB("TargetGlowColor", "WHITE"))
end

-- One glow, either style, on a target region
local function ShowGlow(ring, halo, target, shown, r, g, b)
    if not shown then
        RingShow(ring, false)
        HaloShow(halo, false)
        return
    end
    if DB("TargetGlowStyle", "SOFT") == "OUTLINE" then
        HaloShow(halo, false)
        RingAnchor(ring, target, 1)
        RingShow(ring, true, r, g, b)
    else
        RingShow(ring, false)
        HaloAnchor(halo, target, DB("TargetGlowSize", 10))
        HaloShow(halo, true, r, g, b, DB("TargetGlowAlpha", 0.75))
    end
end

local function RefreshTarget(rec)
    local ov, uf, unit = rec.ov, rec.uf, rec.unit
    local hbc = uf.HealthBarsContainer or HealthBar(uf)
    if not hbc or not Enabled() then return end
    if rec.radial then RadialTarget(rec) return end
    local glowAt = (rec.totem and ov.totemIcon:IsShown()) and ov.totemIcon or hbc
    local isTarget = UnitIsUnit(unit, "target")
    local isFocus = UnitIsUnit(unit, "focus")

    if isTarget and DB("TargetGlow", true) then
        ShowGlow(ov.targetRing, ov.targetHalo, glowAt, true, GlowColor(rec))
    else
        ShowGlow(ov.targetRing, ov.targetHalo, glowAt, false)
    end
    if isFocus and not isTarget and DB("FocusGlow", true) then
        ShowGlow(ov.focusRing, ov.focusHalo, glowAt, true, Color(rec, DB("FocusGlowColor", "MAGENTA")))
    else
        ShowGlow(ov.focusRing, ov.focusHalo, glowAt, false)
    end

    local arrows = isTarget and DB("TargetArrows", true)
    local arrowSize = DB("TargetArrowSize", 22)
    local leftUsed = 4
    if arrows then
        local r, g, b = GlowColor(rec)
        for _, tex in ipairs({ ov.arrowL, ov.arrowR }) do
            tex:SetSize(arrowSize, arrowSize)
            tex:SetVertexColor(r, g, b)
            tex:Show()
        end
        ov.arrowL:ClearAllPoints()
        ov.arrowL:SetPoint("RIGHT", glowAt, "LEFT", -2, 0)
        ov.arrowR:ClearAllPoints()
        ov.arrowR:SetPoint("LEFT", glowAt, "RIGHT", 2, 0)
        leftUsed = leftUsed + arrowSize
    else
        ov.arrowL:Hide(); ov.arrowR:Hide()
    end

    -- Class icon, outside the arrow
    local wantClass = rec.isPlayer and ((rec.isFriend and DB("ClassIconFriendly", false)) or (not rec.isFriend and DB("ClassIconEnemy", true)))
    if wantClass then
        local _, _, _, class = ClassColor(unit)
        local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
        if coords then
            local sz = DB("ClassIconSize", 18)
            ov.classIcon:SetTexCoord(unpack(coords))
            ov.classIcon:SetSize(sz, sz)
            ov.classIcon:ClearAllPoints()
            ov.classIcon:SetPoint("RIGHT", hbc, "LEFT", -leftUsed, 0)
            ov.classIcon:Show()
            leftUsed = leftUsed + sz + 2
        else
            ov.classIcon:Hide()
        end
    else
        ov.classIcon:Hide()
    end
    rec.leftUsed = leftUsed
    if rec.bigWhere == "LEFT" then
        ov.big:ClearAllPoints()
        ov.big:SetPoint("RIGHT", hbc, "LEFT", -leftUsed, DB("CcOffsetY", 0))
    end

    -- Healer cross, right side, after the big icon if that is where it lives
    local rightUsed = 4 + ((rec.bigWhere == "RIGHT" and ov.big:IsShown()) and (DB("CcSize", 36) + 4) or 0)
    if arrows then rightUsed = rightUsed + arrowSize end
    if DB("HealerIcon", true) and rec.isPlayer and not rec.isFriend and healers:Is(rec.guid, GetTime()) then
        local sz = DB("HealerIconSize", 18)
        ov.healerIcon:SetSize(sz, sz)
        ov.healerIcon:ClearAllPoints()
        ov.healerIcon:SetPoint("LEFT", hbc, "RIGHT", rightUsed, 0)
        ov.healerIcon:Show()
    else
        ov.healerIcon:Hide()
    end
end

local function PlaceMarker(tex, hb, fraction, r, g, b)
    if not fraction or fraction <= 0 or fraction >= 1 then tex:Hide() return end
    local width = hb:GetWidth() or 0
    if width <= 1 then tex:Hide() return end
    tex:ClearAllPoints()
    tex:SetPoint("TOP", hb, "TOPLEFT", width * fraction, 0)
    tex:SetPoint("BOTTOM", hb, "BOTTOMLEFT", width * fraction, 0)
    tex:SetVertexColor(r, g, b, 0.85)
    tex:Show()
end

-- Two lines on an enemy's bar: a PERCENT (Execute range) and a VALUE (the
-- health your own burst combo covers -- a decision about a number, not a
-- fraction, so it moves with the unit's maximum health)
local function RefreshMarker(rec)
    local ov, uf = rec.ov, rec.uf
    local hb = HealthBar(uf)
    if rec.radial and Enabled() then
        ov.marker:Hide(); ov.markerValue:Hide()
        RadialHealth(rec, GetTime())
        return
    end
    if not Enabled() or rec.isFriend or not hb or rec.totem then
        ov.marker:Hide(); ov.markerValue:Hide()
        return
    end
    local pct = tonumber(DB("HealthMarkerPercent", 0)) or 0
    PlaceMarker(ov.marker, hb, pct / 100, 1, 1, 1)
    local value = tonumber(DB("HealthMarkerValue", 0)) or 0
    local maxHealth = value > 0 and UnitHealthMax and UnitHealthMax(rec.unit) or 0
    -- A hostile player's maximum is reported as 100 (percent only); the
    -- Events hub's health book has the reverse-engineered number
    if maxHealth == 100 and Commander.Health and Commander.Health.Current then
        local _, est = Commander.Health.Current(rec.unit)
        maxHealth = est or 0
    end
    if maxHealth and maxHealth > 0 then
        PlaceMarker(ov.markerValue, hb, value / maxHealth, 1, 0.82, 0.2)
    else
        ov.markerValue:Hide()
    end
end

-- The unit frame's alpha, decided in ONE place so the three reasons to fade a
-- plate cannot fight over it. Restored to 1 on removal (RestoreBlizzard).
local function RefreshPlateAlpha(rec)
    local uf = rec.uf
    if not Enabled() then uf:SetAlpha(1) return end
    local alpha = 1
    if rec.hiddenNpc then
        alpha = 0
    elseif rec.totem and rec.totem.tier == "LOW" and DB("TotemHideLow", false) then
        alpha = 0
    elseif rec.isFriend then
        alpha = DB("FriendlyAlpha", 1) or 1
    end
    if uf:GetAlpha() ~= alpha then uf:SetAlpha(alpha) end
end

local function RefreshTotem(rec)
    local ov, uf = rec.ov, rec.uf
    local info = rec.totem
    local hbc = uf.HealthBarsContainer or HealthBar(uf)
    if not info or not Enabled() or DB("TotemMode", "ICON") ~= "ICON" then
        ov.totemIcon:Hide()
        RingShow(ov.totemRing, false)
        if info then
            -- Icon mode is off but the totem still exists: Blizzard's plate
            if hbc then hbc:SetAlpha(1) end
            if uf.name then uf.name:SetAlpha(1) end
        end
        return
    end
    local size = DB("TotemIconSize", 28)
    if info.tier == "LOW" then size = math.floor(size * 0.66) end
    local texture = (GetSpellTexture and GetSpellTexture(info.spell))
        or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(info.spell))
    ov.totemIcon:SetTexture(texture or DATA.FALLBACK_ICON)
    ov.totemIcon:SetSize(size, size)
    ov.totemIcon:ClearAllPoints()
    ov.totemIcon:SetPoint("BOTTOM", hbc or uf, "BOTTOM", 0, 0)
    ov.totemIcon:Show()
    RingAnchor(ov.totemRing, ov.totemIcon, 0)
    RingShow(ov.totemRing, true, 0, 0, 0, 1)
    if hbc then hbc:SetAlpha(0) end
    if uf.name then uf.name:SetAlpha(0) end
    if uf.LevelFrame then uf.LevelFrame:SetAlpha(0) end
    ov:Show()
end

-- ---------------------------------------------------------------------------
-- Cast bar colour. Blizzard's modern fill is a yellow atlas painted white
-- (UpdateBarFillTexture), so a tint has to swap the fill for a plain bar and
-- colour that; the per-frame hook below re-applies it every time Blizzard
-- repaints the fill (cast start, finish, interrupt). DEFAULT hands the fill
-- back by running Blizzard's own painter once.
-- ---------------------------------------------------------------------------
local CAST_FILL = "Interface\\TargetingFrame\\UI-StatusBar"

local function ApplyCastColor(rec)
    local cb = CastBar(rec.uf)
    if not cb then return end
    local key = Enabled() and DB("CastBarColor", "DEFAULT") or "DEFAULT"
    if key == "DEFAULT" then
        if rec.castTinted then
            rec.castTinted = nil
            if cb.UpdateBarFillTexture then pcall(cb.UpdateBarFillTexture, cb, false) end
        end
        return
    end
    local r, g, b = Color(rec, key)
    rec.castTinted = true
    cb:SetStatusBarTexture(CAST_FILL)
    cb:SetStatusBarColor(r, g, b)
end

-- ---------------------------------------------------------------------------
-- Cast bar: polled, because a cast bar that is shown IS the truth and a
-- separate event registration per plate would only repeat it
-- ---------------------------------------------------------------------------
local function TickCast(rec, now)
    local ov, uf, unit = rec.ov, rec.uf, rec.unit
    if rec.radial then TickRadialCast(rec, now) return end
    local cb = CastBar(uf)
    if not cb or not Enabled() then return end
    local shown = cb:IsShown()
    if not shown then
        if rec.casting then
            rec.casting = nil
            ov.castTimer:Hide(); ov.castIcon:Hide(); ov.castIconBorder:Hide()
            RingShow(ov.castRing, false)
            if cb.Icon then cb.Icon:SetAlpha(1) end
        end
        return
    end
    local name, _, texture, _, endMS = UnitCastingInfo(unit)
    if not name then
        name, _, texture, _, endMS = UnitChannelInfo(unit)
    end
    if not name then
        if rec.casting then
            rec.casting = nil
            ov.castTimer:Hide(); ov.castIcon:Hide(); ov.castIconBorder:Hide()
            RingShow(ov.castRing, false)
            if cb.Icon then cb.Icon:SetAlpha(1) end
        end
        return
    end

    if rec.casting ~= name then
        rec.casting = name
        local loud = DB("CastEmphasis", true) and E.IsEmphasised(emphasis, name)
        if loud then
            local r, g, b = Color(rec, DB("CastEmphasisColor", "RED"))
            RingAnchor(ov.castRing, cb, 1)
            RingShow(ov.castRing, true, r, g, b, 1)
        else
            RingShow(ov.castRing, false)
        end
        local iconSize = DB("CastIconSize", 0) or 0
        if iconSize > 0 then
            ov.castIcon:SetTexture(texture or DATA.FALLBACK_ICON)
            ov.castIcon:SetSize(iconSize, iconSize)
            ov.castIcon:ClearAllPoints()
            ov.castIcon:SetPoint("RIGHT", cb, "LEFT", -3, 0)
            ov.castIcon:Show()
            ov.castIconBorder:ClearAllPoints()
            ov.castIconBorder:SetPoint("TOPLEFT", ov.castIcon, "TOPLEFT", -1, 1)
            ov.castIconBorder:SetPoint("BOTTOMRIGHT", ov.castIcon, "BOTTOMRIGHT", 1, -1)
            ov.castIconBorder:Show()
            if cb.Icon then cb.Icon:SetAlpha(0) end
        else
            ov.castIcon:Hide(); ov.castIconBorder:Hide()
            if cb.Icon then cb.Icon:SetAlpha(1) end
        end
        if DB("CastTimer", true) then
            ov.castTimer:ClearAllPoints()
            ov.castTimer:SetPoint("RIGHT", cb, "RIGHT", -3, 0)
            ov.castTimer:Show()
        else
            ov.castTimer:Hide()
        end
        ov:Show()
    end
    if ov.castTimer:IsShown() and endMS then
        local remaining = endMS / 1000 - now
        ov.castTimer:SetText(remaining > 0 and string.format("%.1f", remaining) or "")
    end
end

-- ---------------------------------------------------------------------------
-- Blizzard's own aura icons
-- ---------------------------------------------------------------------------
local function WantBlizzardAurasHidden(rec)
    -- A radial plate hides the bar Blizzard's icons are anchored to, so they
    -- would float over nothing: under a disc they are always down
    return Enabled() and (DB("HideBlizzardAuras", true) or (rec ~= nil and rec.radial == true))
end

local function EnforceBlizzardAuras(rec)
    local af = rec.uf.AurasFrame
    if not af then return end
    if WantBlizzardAurasHidden(rec) then
        if af:IsShown() then af:Hide() end
    elseif rec.blizzAurasHidden then
        if af.UpdateShownState then pcall(af.UpdateShownState, af) end
    end
    rec.blizzAurasHidden = WantBlizzardAurasHidden(rec)
end

-- ---------------------------------------------------------------------------
-- Per-plate identity and the full refresh
-- ---------------------------------------------------------------------------
local function ArenaIndexOf(unit)
    for i = 1, 5 do
        local token = "arena" .. i
        if UnitExists(token) and UnitIsUnit(unit, token) then return i end
    end
end

local function Identify(rec)
    local unit = rec.unit
    rec.guid = UnitGUID(unit)
    rec.isPlayer = UnitIsPlayer(unit) or (UnitTreatAsPlayerForDisplay and UnitTreatAsPlayerForDisplay(unit)) or false
    rec.isFriend = UnitIsFriend("player", unit) and true or false
    if rec.isFriend and rec.isPlayer and UnitCanAttack("player", unit) then rec.isFriend = false end
    rec.arena = ArenaIndexOf(unit)
    rec.totem = nil
    rec.hiddenNpc = false
    if not rec.isPlayer then
        local name = UnitName(unit)
        local info = E.TotemInfo(name)
        if info then rec.totem = info end
        rec.hiddenNpc = DB("HideNpcs", true) and E.IsHiddenNpc(name, false, hiddenNpcs)
    end
    rec.class = ClassOf(unit)
    rec.classification = UnitClassification and UnitClassification(unit) or nil
    rec.radial = Enabled() and E.WantRadial(S, rec.isPlayer, rec.isFriend, rec.totem ~= nil) or false
end

local function RefreshRadialPlate(rec)
    local ov = rec.ov
    HideClassicLayer(ov)
    HideBlizzardForRadial(rec)
    local w = RadialWidget(rec)
    Radial.Layout(w, radialCfg)
    w:Show()
    ov:Show()
    local now = GetTime()
    RadialIdentity(rec)
    RefreshAuras(rec)          -- the orbit, and whether a control takes the face
    RadialTarget(rec)
    RadialHealth(rec, now)
    RadialPower(rec, now)
    RadialAlert(rec)
    rec.targetsYou = nil
    RadialTargetsYou(rec)
    RadialTrinket(rec)
    TickRadialCast(rec, now)
end

local function RefreshPlate(rec)
    if not Enabled() then
        HideAll(rec.ov)
        RestoreBlizzard(rec)
        EnforceBlizzardAuras(rec)
        return
    end
    EnforceBlizzardAuras(rec)
    if rec.radial then
        RefreshPlateAlpha(rec)
        RefreshRadialPlate(rec)
        return
    end
    ReleaseRadial(rec)
    RefreshPlateAlpha(rec)
    RefreshTotem(rec)
    RefreshAuras(rec)
    RefreshTarget(rec)
    RefreshMarker(rec)
    ApplyBorderTint(rec)
    ApplyCastColor(rec)
    ApplyHealthColor(rec)
    ApplyName(rec)
end

local function InstallHooks(uf)
    if hookedUF[uf] then return end
    hookedUF[uf] = true
    -- The hit box, on the one tick tainted code may change it in combat
    if uf.ApplyFrameOptions then
        hooksecurefunc(uf, "ApplyFrameOptions", function(self)
            local rec = byUF[self]
            if rec then ApplyHitBox(rec) end
        end)
    end
    -- Re-anchor what depends on the bar's geometry when Blizzard re-lays it
    if uf.UpdateAnchors then
        hooksecurefunc(uf, "UpdateAnchors", function(self)
            local rec = byUF[self]
            if rec and Enabled() then
                RefreshMarker(rec)
                RefreshTarget(rec)
                ApplyBorderTint(rec)   -- UpdateAnchors re-sets the border art
            end
        end)
    end
    local cb = CastBar(uf)
    if cb and cb.UpdateBarFillTexture then
        hooksecurefunc(cb, "UpdateBarFillTexture", function(self)
            local rec = byUF[self:GetParent() and self:GetParent():GetParent()]
            if rec and rec.castTinted then ApplyCastColor(rec) end
        end)
    end
    if uf.AurasFrame and uf.AurasFrame.UpdateShownState then
        hooksecurefunc(uf.AurasFrame, "UpdateShownState", function(self)
            local rec = byUF[self:GetParent()]
            if rec and WantBlizzardAurasHidden(rec) then self:Hide() end
        end)
    end
end

local function OnPlateAdded(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    local uf = plate and plate.UnitFrame
    if not uf or (uf.IsForbidden and uf:IsForbidden()) then return end
    -- The personal resource plate is Commander Nameplate's business, and
    -- nothing here (arrows, a healer cross, your own buffs) belongs on it
    if UnitIsUnit(unit, "player") then return end
    local ov = overlays[uf]
    if not ov then
        ov = NewOverlay(uf)
        overlays[uf] = ov
    end
    InstallHooks(uf)
    local rec = plates[unit] or { auras = {} }
    rec.unit, rec.plate, rec.uf, rec.ov = unit, plate, uf, ov
    plates[unit] = rec
    byUF[uf] = rec
    Identify(rec)
    -- Blizzard's ApplyFrameOptions ran before this event; our hook was not yet
    -- installed the first time this unit frame was seen, so apply once here.
    ApplyHitBox(rec)
    RefreshPlate(rec)
end

local function OnPlateRemoved(unit)
    local rec = plates[unit]
    if not rec then return end
    HideAll(rec.ov)
    RestoreBlizzard(rec)
    rec.casting, rec.castCore, rec.coreCC, rec.loudCast, rec.combo, rec.mouseover = nil, nil, nil, nil, nil, nil
    rec.targetsYou, rec.dead = nil, nil
    byUF[rec.uf] = nil
    plates[unit] = nil
end

-- ---------------------------------------------------------------------------
-- CVars
-- ---------------------------------------------------------------------------
local function CVarExists(name)
    return C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(name) ~= nil
end

function CommanderPlates_ApplyCVar(spec)
    if not CVarExists(spec.cvar) then return false end
    if InCombatLockdown and InCombatLockdown() then
        cvarsPending = true
        return false
    end
    local value = DB(spec.key, spec.default)
    if spec.bool then
        value = value and "1" or "0"
    else
        value = tostring(value)
    end
    local ok = pcall(C_CVar.SetCVar, spec.cvar, value)
    return ok
end

function CommanderPlates_ApplyCVars(announce)
    if InCombatLockdown and InCombatLockdown() then
        cvarsPending = true
        if announce then print("Commander Plates: CVars will be applied when combat ends.") end
        return
    end
    local n = 0
    for _, spec in ipairs(DATA.CVARS) do
        if CommanderPlates_ApplyCVar(spec) then n = n + 1 end
    end
    cvarsPending = false
    if announce then print(string.format("Commander Plates: %d nameplate CVars applied.", n)) end
end

function CommanderPlates_ReadCVars()
    if not CommanderPlatesDB then return end
    for _, spec in ipairs(DATA.CVARS) do
        if CVarExists(spec.cvar) then
            local raw = C_CVar.GetCVar(spec.cvar)
            if spec.bool then
                CommanderPlatesDB[spec.key] = raw == "1"
            else
                local num = tonumber(raw)
                if num then CommanderPlatesDB[spec.key] = num end
            end
        end
    end
end

function CommanderPlates_PrintHealers()
    local now = GetTime()
    healers:Prune(now)
    print(string.format("Commander Plates: %d enemy healer(s) remembered in the last %d minutes.",
        healers:Count(), HEALER_TTL / 60))
end

-- ---------------------------------------------------------------------------
-- Settings changed
-- ---------------------------------------------------------------------------
local function RefreshProfile()
    -- The value marker on enemy players needs the health book running
    if (tonumber(DB("HealthMarkerValue", 0)) or 0) > 0 and Commander.Health and Commander.Health.Watch then
        Commander.Health.Watch()
    end
    whitelist = E.ParseList(DB("Whitelist", ""))
    blacklist = E.ParseList(DB("Blacklist", ""))
    hiddenNpcs = E.ParseList(DB("HideNpcList", ""))
    emphasis = E.BuildEmphasis(DB("CastEmphasisExtra", ""), DB("CastEmphasisRemove", ""))
    if not playerClass and UnitClass then
        local _, class = UnitClass("player")
        playerClass = class
    end
    canDispel = E.DispelSet(playerClass)
    canPurge = E.CanPurge(playerClass)
    radialCfg = Radial.Config(S)
    radialOn = Enabled() and DB("PlateStyle", "CLASSIC") == "RADIAL"
end

-- Friendly class colour needs a bar to colour; Blizzard's name-only mode for
-- friendly players removes it. Said once per session, never forced.
local function HintNameOnly()
    if hintedNameOnly or not Enabled() or not DB("FriendlyClassColor", true) then return end
    if C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("nameplateShowOnlyNameForFriendlyPlayerUnits") == "1" then
        hintedNameOnly = true
        print("Commander Plates: Blizzard's 'Friendly Players: Name Only' is on, so friendly players have no health bar to colour. Turn it off under Blizzard's Nameplate CVars in /cplates.")
    end
end

local events = CreateFrame("Frame")

-- What only a disc needs to hear. Registered while radial plates are on, so
-- the bar mode pays nothing for them; each through pcall, because a client
-- that never shipped one of them refuses the registration outright.
local RADIAL_EVENTS = {
    "UNIT_HEALTH", "UNIT_HEALTH_FREQUENT", "UNIT_HEAL_PREDICTION",
    "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_DISPLAYPOWER", "UNIT_MAXPOWER",
    "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE",
    "RAID_TARGET_UPDATE", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_NAME_UPDATE",
    "UNIT_LEVEL", "UNIT_CLASSIFICATION_CHANGED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_TARGET", "ARENA_CROWD_CONTROL_SPELL_UPDATE", "ARENA_COOLDOWNS_UPDATE",
}
local radialListening = false

local function RefreshRadialListening()
    if radialOn == radialListening then return end
    radialListening = radialOn
    for _, event in ipairs(RADIAL_EVENTS) do
        if radialOn then
            pcall(events.RegisterEvent, events, event)
        else
            pcall(events.UnregisterEvent, events, event)
        end
    end
end

-- Stacking. The client keeps plates apart by the PLATE's size, which is the
-- bar's; a disc is narrower and taller, so crowded discs overlap. Opt-in, it
-- sizes the plates to the disc. Global (every enemy plate, and friendly ones
-- when friends are discs too), refused in combat, and handed back by
-- running Blizzard's own sizing pass.
local stackingApplied, stackingPending = false, false

local function StackSize()
    local cfg = radialCfg
    local d = cfg.radii.outer * 2
    local nameH = (cfg.name ~= "NONE") and (cfg.nameSize + 6) or 0
    return math.floor(d + 24), math.floor(d + nameH + 4)
end

local function ApplyStacking()
    if not (C_NamePlate and C_NamePlate.SetNamePlateEnemySize) then return end
    local want = radialOn and DB("RadialStacking", false) == true
    if not want and not stackingApplied then return end
    if InCombatLockdown and InCombatLockdown() then
        stackingPending = true
        return
    end
    stackingPending = false
    if want then
        local width, height = StackSize()
        pcall(C_NamePlate.SetNamePlateEnemySize, width, height)
        local scope = DB("RadialUnits", "ALL")
        if (scope == "ALL" or scope == "PLAYERS") and C_NamePlate.SetNamePlateFriendlySize then
            pcall(C_NamePlate.SetNamePlateFriendlySize, width, height)
        end
        stackingApplied = true
    else
        stackingApplied = false
        local driver = NamePlateDriverFrame
        if driver and driver.UpdateNamePlateOptions then pcall(driver.UpdateNamePlateOptions, driver) end
    end
end

-- Blizzard re-sizes plates on its own (UI scale, its own options): ours goes
-- back on right behind it
if NamePlateDriverFrame and NamePlateDriverFrame.UpdateNamePlateOptions then
    hooksecurefunc(NamePlateDriverFrame, "UpdateNamePlateOptions", function()
        if stackingApplied then
            stackingApplied = false
            ApplyStacking()
        end
    end)
end

-- Blizzard's own hit box, which only Blizzard's own pass knows how to draw
local function RestoreBlizzardHitBox(rec)
    if not (InCombatLockdown and InCombatLockdown()) and rec.uf.ApplyFrameOptions
        and NamePlateSetupOptions and rec.plate.GetFrameOptions then
        pcall(rec.uf.ApplyFrameOptions, rec.uf, NamePlateSetupOptions, rec.plate:GetFrameOptions())
    end
end

local function RefreshHealerListening()
    if Enabled() and DB("HealerIcon", true) then
        events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    else
        events:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end
end

local function Apply()
    RefreshProfile()
    RefreshHealerListening()
    RefreshRadialListening()
    ApplyStacking()
    for _, rec in pairs(plates) do
        local wasRadial = rec.radial
        Identify(rec)
        -- A disc's box is ours; the bar's may be Blizzard's untouched one
        if wasRadial and not rec.radial then RestoreBlizzardHitBox(rec) end
        ApplyHitBox(rec)
        RefreshPlate(rec)
        if not Enabled() then
            -- Hand the bar and name back to Blizzard's own colouring
            if CompactUnitFrame_UpdateHealthColor then pcall(CompactUnitFrame_UpdateHealthColor, rec.uf) end
            if CompactUnitFrame_UpdateName then pcall(CompactUnitFrame_UpdateName, rec.uf) end
            -- And the hit box
            RestoreBlizzardHitBox(rec)
        end
    end
    HintNameOnly()
end

-- ---------------------------------------------------------------------------
-- Global hooks: colour and names, right behind Blizzard's own pass
-- ---------------------------------------------------------------------------
if CompactUnitFrame_UpdateHealthColor then
    hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(frame)
        local rec = byUF[frame]
        if rec then ApplyHealthColor(rec) end
    end)
end
if CompactUnitFrame_UpdateName then
    hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
        local rec = byUF[frame]
        if rec then
            ApplyName(rec)
            if rec.radial and Enabled() then RadialIdentity(rec) end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local function RefreshZone()
    local _, kind = IsInInstance()
    inInstance = kind == "arena" or kind == "pvp"
end

local function OnCombatLog()
    local _, sub, _, srcGUID, _, srcFlags, _, _, _, _, _, _, spellName = CombatLogGetCurrentEventInfo()
    if sub ~= "SPELL_HEAL" and sub ~= "SPELL_CAST_SUCCESS" then return end
    if not E.IsHealerSpell(spellName) then return end
    if not srcFlags or bit.band(srcFlags, COMBATLOG_OBJECT_TYPE_PLAYER) == 0 then return end
    if bit.band(srcFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) == 0 then return end
    local now = GetTime()
    local known = healers:Is(srcGUID, now)
    healers:Mark(srcGUID, now)
    if not known then
        for _, rec in pairs(plates) do
            if rec.guid == srcGUID then RefreshTarget(rec) end
        end
    end
end

events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_FOCUS_CHANGED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("UNIT_AURA")
events:RegisterEvent("UNIT_FACTION")
events:RegisterEvent("UNIT_MAXHEALTH")
pcall(events.RegisterEvent, events, "ARENA_OPPONENT_UPDATE")

-- The disc's own events. Unit events name a nameplate token; the rest touch
-- every radial plate at once.
local function OnRadialEvent(event, unit)
    if not Enabled() then return end
    local now = GetTime()
    if event == "RAID_TARGET_UPDATE" then
        for _, rec in pairs(plates) do if rec.radial then RadialRaid(rec) end end
        return
    elseif event == "UNIT_THREAT_SITUATION_UPDATE" or event == "UNIT_THREAT_LIST_UPDATE" then
        -- The situation event names the player, the list event the mob: the
        -- cheap answer to both is every NPC disc on screen
        for _, rec in pairs(plates) do
            if rec.radial and not rec.isPlayer then RadialAlert(rec) end
        end
        return
    elseif event == "ARENA_CROWD_CONTROL_SPELL_UPDATE" or event == "ARENA_COOLDOWNS_UPDATE" then
        for _, rec in pairs(plates) do
            if rec.radial and rec.arena then RadialTrinket(rec) end
        end
        return
    end
    local rec = plates[unit]
    if not (rec and rec.radial) then return end
    if event == "UNIT_HEALTH" or event == "UNIT_HEALTH_FREQUENT" or event == "UNIT_HEAL_PREDICTION" then
        RadialHealth(rec, now)
    elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT"
        or event == "UNIT_DISPLAYPOWER" or event == "UNIT_MAXPOWER" then
        RadialPower(rec, now)
    elseif event == "UNIT_PORTRAIT_UPDATE" or event == "UNIT_MODEL_CHANGED" then
        if not (rec.coreCC or rec.castCore) then PaintRadialCore(rec, true) end
    elseif event == "UNIT_NAME_UPDATE" or event == "UNIT_LEVEL" or event == "UNIT_CLASSIFICATION_CHANGED" then
        rec.classification = UnitClassification and UnitClassification(unit) or nil
        RadialIdentity(rec)
        RadialRim(rec)
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        RadialInterrupted(rec)
    elseif event == "UNIT_TARGET" then
        RadialTargetsYou(rec)
    end
end

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        RefreshProfile()
        RefreshZone()
        RefreshHealerListening()
        RefreshRadialListening()
        ApplyStacking()
        if Enabled() and DB("CvApplyOnLogin", false) then CommanderPlates_ApplyCVars(false) end
        HintNameOnly()
    elseif event == "PLAYER_ENTERING_WORLD" then
        RefreshZone()
        for _, rec in pairs(plates) do
            Identify(rec)
            RefreshPlate(rec)
        end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        OnPlateAdded(arg1)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        OnPlateRemoved(arg1)
    elseif event == "UNIT_AURA" then
        local rec = plates[arg1]
        if rec and Enabled() then RefreshAuras(rec) end
    elseif event == "UNIT_FACTION" then
        local rec = plates[arg1]
        if rec then
            Identify(rec)
            RefreshPlate(rec)
        end
    elseif event == "UNIT_MAXHEALTH" then
        local rec = plates[arg1]
        if rec and Enabled() then RefreshMarker(rec) end
    elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
        for _, rec in pairs(plates) do RefreshTarget(rec) end
    elseif event == "ARENA_OPPONENT_UPDATE" then
        if radialOn and radialCfg.trinket then RequestTrinkets() end
        for _, rec in pairs(plates) do
            local was = rec.arena
            rec.arena = ArenaIndexOf(rec.unit)
            if was ~= rec.arena and CompactUnitFrame_UpdateName then
                pcall(CompactUnitFrame_UpdateName, rec.uf)
            end
            if rec.radial then RadialTrinket(rec) end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if hitBoxPending then
            hitBoxPending = false
            for _, rec in pairs(plates) do ApplyHitBox(rec) end
        end
        if cvarsPending then CommanderPlates_ApplyCVars(false) end
        if stackingPending then ApplyStacking() end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog()
    elseif radialOn then
        OnRadialEvent(event, arg1)
    end
end)

if Commander and Commander.AddListener then
    Commander.AddListener(COMMANDER_PLATES_EVENTS.UPDATE, Apply)
end

-- ---------------------------------------------------------------------------
-- The clock: timers, cast bars, and keeping Blizzard's aura frame down
-- ---------------------------------------------------------------------------
local ticker = CreateFrame("Frame")
ticker.since = 0
ticker.sincePrune = 0
ticker.sinceSlow = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
    self.since = self.since + elapsed
    if self.since < TICK then return end
    self.since = 0
    if not Enabled() then return end
    local now = GetTime()
    -- Twice a second, the disc re-reads what an event could have missed:
    -- health (a unit that took damage the frame its plate appeared), the
    -- combo points on the target, and threat
    self.sinceSlow = self.sinceSlow + TICK
    local slow = self.sinceSlow >= 0.5
    if slow then self.sinceSlow = 0 end
    for _, rec in pairs(plates) do
        local ov = rec.ov
        for _, f in ipairs(ov.icons) do
            if f:IsShown() then TickIcon(f, now) end
        end
        if ov.big:IsShown() then TickIcon(ov.big, now) end
        if rec.radial and ov.radial then
            for _, f in ipairs(ov.orbitRound) do
                if f:IsShown() then TickIcon(f, now) end
            end
            for _, f in ipairs(ov.orbitSquare) do
                if f:IsShown() then TickIcon(f, now) end
            end
            if rec.coreCC or rec.castCore then RadialCenterText(rec, now) end
            if radialCfg.mouseover then
                local over = UnitIsUnit(rec.unit, "mouseover") and true or false
                if over ~= (rec.mouseover or false) then
                    rec.mouseover = over
                    RadialRim(rec)
                end
            end
            if slow then
                RadialHealth(rec, now)
                RadialPower(rec, now)
                RadialCombo(rec)
                RadialDr(rec, now)
                RadialTargetsYou(rec)
                if rec.arena then RadialTrinket(rec) end
                if not rec.isPlayer then RadialAlert(rec) end
                -- Blizzard owns these frames and may show one again: a disc
                -- with a bar peeking out behind it is two plates
                local hbc = rec.uf.HealthBarsContainer
                if hbc and hbc:GetAlpha() ~= 0 then HideBlizzardForRadial(rec) end
            end
        end
        TickCast(rec, now)
        if rec.blizzAurasHidden and rec.uf.AurasFrame and rec.uf.AurasFrame:IsShown() then
            rec.uf.AurasFrame:Hide()
        end
    end
    self.sincePrune = self.sincePrune + TICK
    if self.sincePrune > 30 then
        self.sincePrune = 0
        healers:Prune(now)
    end
end)
