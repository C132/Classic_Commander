CommanderPlatesDB = _G.CommanderPlatesDB or {}

COMMANDER_PLATES_EVENTS = {
    UPDATE = "COMMANDER_PLATES_UPDATE"
}

local DATA = CommanderPlates_Data
local Draw = CommanderPlates_Draw

-- Settings revision. Bumped when a default changes meaning, so a saved value
-- from an older layout can be carried across rather than silently kept.
local SETTINGS_REV = 2

-- Defaults are the opinionated part, and the opinion is the one a high-rated
-- arena player would have on a stock UI: the bar is the CLASS, control is
-- BIG, everything else on the plate is only there when it changes what you do
-- next, and nothing about the plate's shape changes -- it just gets easier to
-- click.
local DefaultSettings = {
    Enable = true,

    -- The plate's shape. RADIAL turns every plate (totems excepted) into a
    -- disc: the unit's face in the middle, health and cast as arcs round it,
    -- auras in orbit. Everything below still applies to it where it can.
    PlateStyle = "CLASSIC",             -- CLASSIC (Blizzard's bar, layered) | RADIAL
    RadialUnits = "ALL",                -- ALL | PLAYERS | ENEMIES | ENEMY_PLAYERS
    RadialStacking = false,             -- size the client's plate stacking to the disc

    -- Radial: the rings
    RadialSize = 46,                    -- diameter to the health ring's outer edge
    RadialTargetScale = 1.2,
    RadialOffsetY = 0,
    RadialHealthThickness = 5,
    RadialHealthColor = "AUTO",         -- AUTO (class on players, reaction on NPCs) | CLASS | REACTION | palette
    RadialLowHealth = 35,               -- percent; the ring turns RadialLowHealthColor below it. 0 = off
    RadialLowHealthColor = "RED",
    RadialTrackAlpha = 0.35,
    RadialHealthTrail = true,
    RadialHealPrediction = true,
    RadialPower = "PLAYERS",            -- OFF | MANA | PLAYERS | ALL
    RadialPowerThickness = 2,
    RadialCastRing = true,
    RadialCastThickness = 3,
    RadialCastColor = "GOLD",
    RadialUninterruptibleColor = "WHITE",
    RadialCastSpark = true,
    RadialCastName = true,
    RadialInterruptFlash = true,
    RadialCastTarget = true,            -- "Polymorph >> YOU" on the cast line

    -- Radial: the face and the text
    RadialCoreArt = "CLASS",            -- CLASS (players; portrait on NPCs) | PORTRAIT | NONE
    RadialCoreText = "SMART",           -- SMART | PERCENT | HEALTH | ARENA | NONE
    RadialCoreTextSize = 0,             -- the middle number's font size in points (0 = sized off the face)
    RadialTextShade = 0.45,             -- how far the face darkens under a number written on it (0 = not at all)
    RadialCoreCast = true,              -- the spell being cast takes the face
    RadialCoreCC = true,                -- the control being sat in takes the face
    RadialName = "BELOW",               -- BELOW | ABOVE | NONE
    RadialNameSize = 10,
    RadialNameWidth = 96,
    RadialRimColor = "REACTION",        -- OFF | CLASS | REACTION | palette
    RadialBackdrop = "DARK",            -- DARK | CLASS | REACTION (dimmed tints)
    RadialBackdropAlpha = 0.6,          -- 0 = no backdrop
    RadialBackdropSize = 2,             -- px past the outer ring; negative pulls it in
    RadialGlowStyle = "SOFT",           -- see CommanderPlates_Radial.GLOW_ORDER
    RadialGlowSize = 1.0,
    RadialGlowMotion = "NONE",          -- NONE | SPIN | PULSE | BOTH
    RadialBackdropBorder = true,
    RadialEliteRim = true,
    RadialMouseover = true,
    RadialLevel = true,
    RadialRaidMarker = true,
    RadialTrinket = true,               -- an arena enemy's PvP trinket on the rim
    RadialTargetingYou = "ENEMY_PLAYERS", -- OFF | ENEMY_PLAYERS | ENEMIES
    RadialTargetingYouColor = "RED",

    -- Radial: the orbit
    RadialDebuffArc = "TOP",            -- a clock position: TOP, TOP_RIGHT, RIGHT, ...
    RadialBuffArc = "RIGHT",
    RadialDebuffGrow = "CENTER",        -- CENTER | CLOCKWISE | COUNTERCLOCKWISE
    RadialBuffGrow = "CENTER",
    RadialAuraSize = 16,
    RadialAuraGap = 2,
    RadialAuraArc = 160,                -- degrees an orbit may span before a second one starts
    RadialRoundAuras = true,
    RadialComboPoints = true,
    RadialThreat = "DPS",               -- OFF | DPS | TANK
    RadialDr = "ENEMIES",               -- OFF | ENEMIES | ENEMY_PLAYERS | ALL (needs Commander Diminish)
    RadialDrArc = "LEFT",

    -- Health bars and names
    FriendlyClassColor = true,
    ReactionScheme = "REACTION",        -- REACTION (red / blue) | REACTION_RG (red / green)
    EnemyClassColor = true,
    FriendlyNameColor = "CLASS",        -- DEFAULT | CLASS | REACTION | a palette key
    EnemyNameColor = "CLASS",
    NpcNameColor = "DEFAULT",
    HostileBorderTint = "RED",          -- OFF | CLASS | REACTION | a palette key
    FriendlyBorderTint = "BLUE",
    HealthMarkerPercent = 0,            -- 0 = off; 20 draws the Execute line
    HealthMarkerValue = 0,              -- 0 = off; a health VALUE your burst covers
    EnemyNameText = "NAME",             -- NAME | CLASS | NONE
    FriendlyNameText = "NAME",          -- NAME | CLASS | NONE

    -- Aura rows. Who sees what.
    EnemyDebuffs = "MINE_NOTABLE",      -- OFF | MINE | MINE_NOTABLE | ALL
    EnemyBuffs = "NOTABLE_PURGEABLE",   -- OFF | NOTABLE | PURGEABLE | NOTABLE_PURGEABLE | ALL
    FriendDebuffs = "NOTABLE",          -- OFF | DISPELLABLE | NOTABLE | ALL
    FriendBuffs = "MINE",               -- OFF | MINE | MINE_NOTABLE | ALL
    ShowDefensives = true,
    ShowOffensives = true,
    ShowNotableDebuffs = true,
    ShowSlows = false,
    TrackWhere = "ALWAYS",              -- ALWAYS | INSTANCES
    Whitelist = "",
    Blacklist = "",
    HideBlizzardAuras = true,

    -- Aura rows. How they look.
    AuraSize = 22,
    AuraSpacing = 2,
    AuraPerRow = 6,
    DebuffMax = 8,
    BuffMax = 4,
    BuffMaxDuration = 60,               -- seconds; 0 = no cap. Trims the half-hour raid buffs
    DebuffMaxDuration = 0,
    AuraGrow = "CENTER",                -- CENTER | LEFT | RIGHT
    AuraSort = "PRIORITY",              -- PRIORITY | TIME | TIME_DESC | NAME
    BuffRowPosition = "ABOVE",          -- ABOVE (over the debuffs) | BELOW (under the plate)
    AuraTimer = true,
    AuraTimerSize = 11,
    AuraTimerUrgent = true,
    AuraStacks = true,
    AuraSwipe = true,
    AuraOwnBorder = true,
    AuraKindBorder = true,
    PurgeGlow = true,
    AuraTooltips = false,

    -- The big control icon
    CcEnable = true,
    CcOnEnemies = true,
    CcOnFriends = true,
    CcSize = 36,
    CcAnchor = "ABOVE",                 -- ABOVE | BELOW | LEFT | RIGHT | CENTER
    CcOffsetY = 0,
    CcTimer = true,
    CcGlow = true,
    CcHideDuplicate = true,
    CcDrBadge = true,
    CcStuns = true,
    CcIncaps = true,
    CcFears = true,
    CcSilences = true,
    CcRoots = true,
    CcDisarms = true,
    CcImmunities = true,

    -- Clickable area
    HitBoxTop = 8,
    HitBoxBottom = 6,
    HitBoxSides = 0,
    FriendlyClickThrough = "NEVER",     -- NEVER | INSTANCES | ALWAYS

    -- Target, focus, and who is who
    TargetArrows = true,
    TargetArrowSize = 22,
    TargetGlow = true,
    TargetGlowColor = "WHITE",          -- CLASS | REACTION | a palette key
    TargetGlowStyle = "SOFT",           -- SOFT | OUTLINE
    TargetGlowSize = 10,
    TargetGlowAlpha = 0.75,
    FocusGlow = true,
    FocusGlowColor = "MAGENTA",
    ArenaNumbers = "REPLACE",           -- OFF | REPLACE | PREFIX
    ClassIconEnemy = true,
    ClassIconFriendly = false,
    ClassIconSize = 18,
    HealerIcon = true,
    HealerIconSize = 18,
    TotemMode = "ICON",                 -- DEFAULT | ICON
    TotemIconSize = 28,
    TotemHideLow = false,
    HideNpcs = true,
    HideNpcList = "Venomous Snake, Viper",
    FriendlyAlpha = 1.0,

    -- Cast bar
    CastTimer = true,
    CastEmphasis = true,
    CastEmphasisExtra = "",
    CastEmphasisRemove = "",
    CastEmphasisColor = "RED",          -- CLASS | REACTION | a palette key
    CastBarColor = "DEFAULT",           -- DEFAULT | CLASS | REACTION | a palette key
    CastIconSize = 0,                   -- 0 = Blizzard's

    -- Blizzard's nameplate CVars, kept as a profile
    CvApplyOnLogin = false,
}

for _, spec in ipairs(DATA.CVARS) do
    DefaultSettings[spec.key] = spec.default
end

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderPlatesDB, DefaultSettings)
    Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
    print("Commander Plates: settings restored to defaults")
end

local function Enabled()
    return CommanderPlatesDB.Enable
end

local function Notify()
    Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
end

-- Is any plate still a bar? Under Radial for everyone, the controls that
-- only shape the bar (its frame tint, the aura rows' layout, the cast bar's
-- fill) have nothing left to shape, and grey out rather than silently
-- doing nothing
local function BarsShown()
    local db = CommanderPlatesDB
    return db.Enable and not (db.PlateStyle == "RADIAL" and (db.RadialUnits or "ALL") == "ALL")
end

local function IsRadial()
    return CommanderPlatesDB.PlateStyle == "RADIAL"
end

local function Label(options, value)
    for _, o in ipairs(options) do if o.value == value then return o.text end end
    return tostring(value)
end

-- Every section of the page is a foldout. The key is what its open/closed
-- state is remembered by; the summary is the few words its header shows
-- while shut, so a closed page still reads as a table of what is set.
local FOLDS = {
    ["Health Bars & Names"] = { key = "bars", summary = function()
        local db = CommanderPlatesDB
        return (db.EnemyClassColor or db.FriendlyClassColor) and "Class colours on" or "Blizzard's colours" end },
    ["Buffs & Debuffs: What Is Shown"] = { key = "aurafilter", summary = function()
        local db = CommanderPlatesDB
        local names = { OFF = "off", MINE = "mine", MINE_NOTABLE = "mine + notable", ALL = "all", NOTABLE = "notable",
            PURGEABLE = "purgeable", NOTABLE_PURGEABLE = "notable + purgeable", DISPELLABLE = "dispellable" }
        return "Enemy debuffs: " .. (names[db.EnemyDebuffs] or "?") .. "  \194\183  friend buffs: " .. (names[db.FriendBuffs] or "?") end },
    ["Buffs & Debuffs: How They Look"] = { key = "auralook", summary = function()
        return IsRadial() and "" or (CommanderPlatesDB.AuraSize .. "px icons") end },
    ["Loose Control: The Big Icon"] = { key = "cc", summary = function()
        return CommanderPlatesDB.CcEnable and "On" or "Off" end },
    ["Clickable Area & Friendly Plates"] = { key = "hitbox", summary = function()
        local db = CommanderPlatesDB
        return db.FriendlyClickThrough ~= "NEVER" and "Friendly click-through" or "" end },
    ["Target, Focus & Who Is Who"] = { key = "identity", summary = function()
        local db = CommanderPlatesDB
        local on = {}
        if db.TargetGlow then on[#on + 1] = "glow" end
        if db.TargetArrows then on[#on + 1] = "arrows" end
        if db.HealerIcon then on[#on + 1] = "healers" end
        return table.concat(on, ", ") end },
    ["Totems & Clutter"] = { key = "totems", summary = function()
        return CommanderPlatesDB.TotemMode == "ICON" and "Totems as icons" or "Blizzard's totems" end },
    ["Cast Bar"] = { key = "cast", summary = function()
        return CommanderPlatesDB.CastEmphasis and "Emphasis on" or "" end },
    ["Blizzard's Nameplate CVars"] = { key = "cvars", summary = function()
        return CommanderPlatesDB.CvApplyOnLogin and "Applied at login" or "Not applied at login" end },
    ["Radial: The Rings"] = { key = "radialrings", isShown = IsRadial, summary = function()
        return CommanderPlatesDB.RadialSize .. "px disc" end },
    ["Radial: The Face & The Text"] = { key = "radialface", isShown = IsRadial },
    ["Radial: The Orbit"] = { key = "radialorbit", isShown = IsRadial },
}

local function Section(panel, title, subtext)
    return panel:AddFoldout(title, subtext, FOLDS[title])
end

-- ---------------------------------------------------------------------------
-- A text row: the shared panel has no edit box, and a whitelist needs one.
-- Commits on Enter and on focus leaving, never per keystroke -- a half-typed
-- "Poly" would otherwise flicker every plate as it matched nothing.
-- ---------------------------------------------------------------------------
local textCounter = 0
local function AddTextRow(panel, opts)
    local row = panel:AddRow(44, 6)
    local label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 2, 0)
    label:SetText(opts.label)

    textCounter = textCounter + 1
    if panel.TagRow then panel:TagRow(row, opts.label, opts.tooltip) end
    local box = CreateFrame("EditBox", "CommanderPlatesText" .. textCounter, row, "InputBoxTemplate")
    box:SetSize(opts.width or 440, 20)
    box:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -18)
    box:SetAutoFocus(false)
    box:SetMaxLetters(1000)
    Commander.UI.AttachTooltip(box, opts.label, opts.tooltip)

    local function Commit(self)
        local value = self:GetText() or ""
        if value ~= (opts.get() or "") then
            opts.set(value)
            panel:_Changed()
        end
    end
    box:SetScript("OnEnterPressed", function(self) Commit(self); self:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(self) self:SetText(opts.get() or ""); self:ClearFocus() end)
    box:SetScript("OnEditFocusLost", Commit)

    panel:AddRefresher(function()
        if not box:HasFocus() then box:SetText(opts.get() or "") end
    end)
    return box
end

-- ---------------------------------------------------------------------------
-- The preview: two mock plates drawn on the page with the same brushes the
-- real plates use, re-read from the settings on every refresh. Left is an
-- enemy mage you are targeting, sitting in a Polymorph with your Corruption
-- and Curse of Agony on him and a Frostbolt in flight; right is a friendly
-- druid you have focused. Nothing here is a screenshot -- change a control
-- and the plate changes.
-- ---------------------------------------------------------------------------
local PREVIEW_H = 168
local PREVIEW_BAR_W, PREVIEW_BAR_H = 128, 12
local PREVIEW_ICONS = {
    "Interface\\Icons\\Spell_Shadow_AbominationExplosion",
    "Interface\\Icons\\Spell_Shadow_CurseOfSargeras",
    "Interface\\Icons\\Spell_Frost_FrostBolt02",
}
local PREVIEW_CC = "Interface\\Icons\\Spell_Nature_Polymorph"
local PREVIEW_MAXHP = 9000

local function PreviewIcon(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.border = Draw.NewQuad(f, "BACKGROUND")
    f.border:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    f.border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.glow = f:CreateTexture(nil, "OVERLAY", nil, 3)
    f.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    f.glow:SetBlendMode("ADD")
    f.glow:SetPoint("CENTER")
    f.timer = f:CreateFontString(nil, "OVERLAY")
    f.timer:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    f.timer:SetPoint("CENTER")
    f.badge = f:CreateFontString(nil, "OVERLAY")
    f.badge:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    f.badge:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 2)
    return f
end

local function NewMockPlate(row, x, spec)
    local m = CreateFrame("Frame", nil, row)
    m:SetSize(PREVIEW_BAR_W + 120, PREVIEW_H)
    m:SetPoint("TOP", row, "TOPLEFT", x, 0)
    m.spec = spec

    m.bar = CreateFrame("Frame", nil, m)
    m.bar:SetSize(PREVIEW_BAR_W, PREVIEW_BAR_H)
    m.bar:SetPoint("CENTER", m, "CENTER", 0, -14)
    m.barBg = Draw.NewQuad(m.bar, "BACKGROUND", -1)
    m.barBg:SetAllPoints()
    m.barBg:SetVertexColor(0.08, 0.08, 0.08, 0.9)
    m.fill = Draw.NewQuad(m.bar, "BACKGROUND", 0)
    m.fill:SetPoint("TOPLEFT")
    m.fill:SetPoint("BOTTOMLEFT")
    m.fill:SetWidth(PREVIEW_BAR_W * spec.health)
    m.frameRing = Draw.NewRing(m.bar, 2, 0)          -- stands in for Blizzard's border art
    m.markerPct = Draw.NewQuad(m.bar, "OVERLAY", 3); m.markerPct:SetWidth(1)
    m.markerVal = Draw.NewQuad(m.bar, "OVERLAY", 3); m.markerVal:SetWidth(1)

    m.name = m:CreateFontString(nil, "OVERLAY")
    m.name:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    m.name:SetPoint("BOTTOM", m.bar, "TOP", 0, 3)

    m.castBar = CreateFrame("Frame", nil, m)
    m.castBar:SetSize(PREVIEW_BAR_W, 8)
    m.castBar:SetPoint("TOP", m.bar, "BOTTOM", 0, -3)
    m.castBg = Draw.NewQuad(m.castBar, "BACKGROUND", -1); m.castBg:SetAllPoints(); m.castBg:SetVertexColor(0.08, 0.08, 0.08, 0.9)
    m.castFill = Draw.NewQuad(m.castBar, "BACKGROUND", 0)
    m.castFill:SetPoint("TOPLEFT"); m.castFill:SetPoint("BOTTOMLEFT"); m.castFill:SetWidth(PREVIEW_BAR_W * 0.6)
    m.castFill:SetVertexColor(1, 0.7, 0)   -- Blizzard's yellow, until PaintMock says otherwise
    m.castRing = Draw.NewRing(m.castBar, 2, 2)
    m.castTimer = m:CreateFontString(nil, "OVERLAY")
    m.castTimer:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    m.castTimer:SetPoint("RIGHT", m.castBar, "RIGHT", -2, 0)
    m.castTimer:SetText("1.4")

    m.glowRing = Draw.NewRing(m, 2, 2)
    m.glowHalo = Draw.NewHalo(m, 1)
    m.arrowL = m:CreateTexture(nil, "OVERLAY", nil, 4); m.arrowL:SetTexture(DATA.ARROW_ICON)
    m.arrowR = m:CreateTexture(nil, "OVERLAY", nil, 4); m.arrowR:SetTexture(DATA.ARROW_ICON); m.arrowR:SetTexCoord(1, 0, 0, 1)
    m.classIcon = m:CreateTexture(nil, "OVERLAY", nil, 4); m.classIcon:SetTexture(DATA.CLASS_ICON)

    m.auras = {}
    for i = 1, #PREVIEW_ICONS do m.auras[i] = PreviewIcon(m, 22) end
    m.big = PreviewIcon(m, 36)
    return m
end

local function PaintMock(m)
    local db = CommanderPlatesDB
    local spec = m.spec
    local ctx = { class = spec.class, reaction = spec.reaction }
    local isFriend = spec.reaction == "FRIENDLY"
    local classKey = isFriend and "FriendlyClassColor" or "EnemyClassColor"

    -- Bar
    if db[classKey] then
        m.fill:SetVertexColor(Draw.ResolveColor("CLASS", ctx))
    elseif isFriend then
        m.fill:SetVertexColor(0.667, 0.667, 1)
    else
        m.fill:SetVertexColor(1, 0, 0)
    end
    -- Frame tint (the stand-in border is gold when untinted, like the Classic art)
    local tintKey = isFriend and db.FriendlyBorderTint or db.HostileBorderTint
    Draw.RingAnchor(m.frameRing, m.bar, 0)
    if tintKey and tintKey ~= "OFF" then
        Draw.RingShow(m.frameRing, true, Draw.ResolveColor(tintKey, ctx))
    else
        Draw.RingShow(m.frameRing, true, 0.85, 0.7, 0.3)
    end
    -- Name
    local textMode = isFriend and db.FriendlyNameText or db.EnemyNameText
    local text = spec.name
    if textMode == "CLASS" then text = spec.className elseif textMode == "NONE" then text = "" end
    if not isFriend and db.ArenaNumbers == "REPLACE" then text = "2" elseif not isFriend and db.ArenaNumbers == "PREFIX" and text ~= "" then text = "2 " .. text end
    m.name:SetText(text)
    local nameKey = isFriend and db.FriendlyNameColor or db.EnemyNameColor
    if nameKey == "DEFAULT" then
        m.name:SetTextColor(1, 1, 1)
    else
        m.name:SetTextColor(Draw.ResolveColor(nameKey, ctx))
    end
    -- Markers (enemy only)
    local function Marker(tex, fraction, r, g, b)
        if isFriend or not fraction or fraction <= 0 or fraction >= 1 then tex:Hide() return end
        tex:ClearAllPoints()
        tex:SetPoint("TOP", m.bar, "TOPLEFT", PREVIEW_BAR_W * fraction, 0)
        tex:SetPoint("BOTTOM", m.bar, "BOTTOMLEFT", PREVIEW_BAR_W * fraction, 0)
        tex:SetVertexColor(r, g, b, 0.85)
        tex:Show()
    end
    Marker(m.markerPct, (db.HealthMarkerPercent or 0) / 100, 1, 1, 1)
    Marker(m.markerVal, (db.HealthMarkerValue or 0) / PREVIEW_MAXHP, 1, 0.82, 0.2)
    -- Glow: the enemy is the target, the friend the focus
    local glowOn = isFriend and db.FocusGlow or db.TargetGlow
    local glowKey = isFriend and db.FocusGlowColor or db.TargetGlowColor
    local r, g, b = Draw.ResolveColor(glowKey, ctx)
    if glowOn and db.TargetGlowStyle == "OUTLINE" then
        Draw.HaloShow(m.glowHalo, false)
        Draw.RingAnchor(m.glowRing, m.bar, 3)
        Draw.RingShow(m.glowRing, true, r, g, b)
    elseif glowOn then
        Draw.RingShow(m.glowRing, false)
        Draw.HaloAnchor(m.glowHalo, m.bar, math.min(db.TargetGlowSize or 10, 16))
        Draw.HaloShow(m.glowHalo, true, r, g, b, db.TargetGlowAlpha or 0.75)
    else
        Draw.RingShow(m.glowRing, false)
        Draw.HaloShow(m.glowHalo, false)
    end
    -- Arrows on the target only
    local arrows = not isFriend and db.TargetArrows
    local arrowSize = math.min(db.TargetArrowSize or 22, 26)
    local leftUsed = 6
    m.arrowL:SetShown(arrows); m.arrowR:SetShown(arrows)
    if arrows then
        local ar, ag, ab = Draw.ResolveColor(db.TargetGlowColor, ctx)
        for _, tex in ipairs({ m.arrowL, m.arrowR }) do tex:SetSize(arrowSize, arrowSize); tex:SetVertexColor(ar, ag, ab) end
        m.arrowL:ClearAllPoints(); m.arrowL:SetPoint("RIGHT", m.bar, "LEFT", -4, 0)
        m.arrowR:ClearAllPoints(); m.arrowR:SetPoint("LEFT", m.bar, "RIGHT", 4, 0)
        leftUsed = leftUsed + arrowSize
    end
    -- Class icon
    local wantClass = isFriend and db.ClassIconFriendly or (not isFriend and db.ClassIconEnemy)
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[spec.class]
    if wantClass and coords then
        local sz = math.min(db.ClassIconSize or 18, 24)
        m.classIcon:SetTexCoord(unpack(coords))
        m.classIcon:SetSize(sz, sz)
        m.classIcon:ClearAllPoints()
        m.classIcon:SetPoint("RIGHT", m.bar, "LEFT", -leftUsed, 0)
        m.classIcon:Show()
        leftUsed = leftUsed + sz + 2
    else
        m.classIcon:Hide()
    end
    -- Aura row above the name
    local size = math.min(db.AuraSize or 22, 26)
    local spacing = db.AuraSpacing or 2
    local grow = db.AuraGrow or "CENTER"
    local rowMode = isFriend and db.FriendBuffs or db.EnemyDebuffs
    local shown = rowMode == "OFF" and 0 or (isFriend and 1 or #PREVIEW_ICONS)
    local slots = CommanderPlates_Engine.RowLayout(shown, size, spacing, grow, db.AuraPerRow or 6)
    local rowHeight = shown > 0 and (size + spacing) or 0
    for i, f in ipairs(m.auras) do
        if i <= shown then
            f:SetSize(size, size)
            f.icon:SetTexture(isFriend and "Interface\\Icons\\Spell_Nature_Rejuvenation" or PREVIEW_ICONS[i])
            local mine = i ~= 2
            if db.AuraKindBorder and i == 2 and not isFriend then
                f.border:SetVertexColor(0.90, 0.20, 0.20)     -- a notable debuff's tint
            elseif db.AuraOwnBorder and mine then
                f.border:SetVertexColor(0.95, 0.95, 0.95)
            else
                f.border:SetVertexColor(0, 0, 0)
            end
            f.timer:SetShown(db.AuraTimer == true)
            f.timer:SetFont(STANDARD_TEXT_FONT, math.min(db.AuraTimerSize or 11, 12), "OUTLINE")
            f.timer:SetText(({ "12", "8", "2.4" })[i])
            if db.AuraTimer and db.AuraTimerUrgent and i == 3 then f.timer:SetTextColor(1, 0.3, 0.3) else f.timer:SetTextColor(1, 1, 1) end
            f.glow:Hide()
            f.badge:Hide()
            f:ClearAllPoints()
            f:SetPoint("CENTER", m.name, "TOP", slots[i][1], 3 + slots[i][2])
            f:Show()
        else
            f:Hide()
        end
    end
    -- The big control icon
    local ccOn = db.CcEnable and (isFriend and db.CcOnFriends or (not isFriend and db.CcOnEnemies)) and db.CcIncaps
    if ccOn then
        local ccSize = math.min(db.CcSize or 36, 40)
        m.big:SetSize(ccSize, ccSize)
        m.big.glow:SetSize(ccSize * 1.75, ccSize * 1.75)
        m.big.icon:SetTexture(PREVIEW_CC)
        m.big.border:SetVertexColor(0.60, 0.80, 1.00)
        m.big.glow:SetShown(db.CcGlow == true)
        m.big.glow:SetVertexColor(0.60, 0.80, 1.00, 0.9)
        m.big.timer:SetShown(db.CcTimer == true)
        m.big.timer:SetFont(STANDARD_TEXT_FONT, math.max(11, math.floor(ccSize * 0.38)), "OUTLINE")
        m.big.timer:SetText("4")
        m.big.badge:SetShown(db.CcDrBadge == true)
        m.big.badge:SetText(DATA.BRACKET_LABEL[2])
        m.big.badge:SetTextColor(unpack(DATA.BRACKET_TINT[2]))
        m.big:ClearAllPoints()
        local where, dy = db.CcAnchor or "ABOVE", db.CcOffsetY or 0
        if where == "LEFT" then
            m.big:SetPoint("RIGHT", m.bar, "LEFT", -leftUsed, dy)
        elseif where == "RIGHT" then
            m.big:SetPoint("LEFT", m.bar, "RIGHT", 4 + (arrows and arrowSize or 0), dy)
        elseif where == "BELOW" then
            m.big:SetPoint("TOP", m.castBar, "BOTTOM", 0, -4 + dy)
        elseif where == "CENTER" then
            m.big:SetPoint("CENTER", m.bar, "CENTER", 0, dy)
        else
            m.big:SetPoint("BOTTOM", m.name, "TOP", 0, 3 + rowHeight + 2 + dy)
        end
        m.big:Show()
    else
        m.big:Hide()
    end
    -- Cast bar: the enemy is casting Polymorph (emphasised), the friend Regrowth
    if (db.CastBarColor or "DEFAULT") == "DEFAULT" then
        m.castFill:SetVertexColor(1, 0.7, 0)
    else
        m.castFill:SetVertexColor(Draw.ResolveColor(db.CastBarColor, ctx))
    end
    local loud = not isFriend and db.CastEmphasis
    Draw.RingAnchor(m.castRing, m.castBar, 1)
    if loud then
        Draw.RingShow(m.castRing, true, Draw.ResolveColor(db.CastEmphasisColor or "RED", ctx))
    else
        Draw.RingShow(m.castRing, false)
    end
    m.castTimer:SetShown(db.CastTimer == true)
end

-- The third plate: an enemy Grounding Totem, as Blizzard draws it or as an icon
local function NewMockTotem(row, x)
    local t = CreateFrame("Frame", nil, row)
    t:SetSize(90, PREVIEW_H)
    t:SetPoint("TOP", row, "TOPLEFT", x, 0)
    t.bar = CreateFrame("Frame", nil, t)
    t.bar:SetSize(64, 8)
    t.bar:SetPoint("CENTER", t, "CENTER", 0, -14)
    t.barBg = Draw.NewQuad(t.bar, "BACKGROUND", -1); t.barBg:SetAllPoints(); t.barBg:SetVertexColor(0.08, 0.08, 0.08, 0.9)
    t.fill = Draw.NewQuad(t.bar, "BACKGROUND", 0); t.fill:SetAllPoints(); t.fill:SetVertexColor(1, 0, 0)
    t.frameRing = Draw.NewRing(t.bar, 1, 0)
    t.name = t:CreateFontString(nil, "OVERLAY")
    t.name:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    t.name:SetPoint("BOTTOM", t.bar, "TOP", 0, 2)
    t.name:SetText("Grounding Totem")
    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    t.icon:SetPoint("BOTTOM", t.bar, "BOTTOM", 0, 0)
    t.iconRing = Draw.NewRing(t, 1, 2)
    t.label = t:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    t.label:SetPoint("TOP", t.bar, "BOTTOM", 0, -6)
    return t
end

local function PaintMockTotem(t)
    local db = CommanderPlatesDB
    local asIcon = db.TotemMode == "ICON"
    local tintKey = db.HostileBorderTint
    Draw.RingAnchor(t.frameRing, t.bar, 0)
    if tintKey and tintKey ~= "OFF" then
        Draw.RingShow(t.frameRing, not asIcon, Draw.ResolveColor(tintKey, { reaction = "HOSTILE" }))
    else
        Draw.RingShow(t.frameRing, not asIcon, 0.85, 0.7, 0.3)
    end
    t.bar:SetAlpha(asIcon and 0 or 1)
    t.name:SetAlpha(asIcon and 0 or 1)
    if asIcon then
        local size = math.min(db.TotemIconSize or 28, 40)
        local texture = (GetSpellTexture and GetSpellTexture(DATA.TOTEMS["Grounding Totem"].spell))
            or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(DATA.TOTEMS["Grounding Totem"].spell))
        t.icon:SetTexture(texture or DATA.FALLBACK_ICON)
        t.icon:SetSize(size, size)
        t.icon:Show()
        Draw.RingAnchor(t.iconRing, t.icon, 0)
        Draw.RingShow(t.iconRing, true, 0, 0, 0, 1)
        t.label:SetText("totem as icon")
    else
        t.icon:Hide()
        Draw.RingShow(t.iconRing, false)
        t.label:SetText("totem, Blizzard's")
    end
end

-- The radial preview: the same two units as discs, painted by the brushes
-- the live plates use. The mage is casting a Polymorph at you (the face is
-- the spell, the sweep loops every few seconds); the druid is sheeped (the
-- face is the sheep, its countdown sweeping over it).
local Radial = CommanderPlates_Radial
local PREVIEW_CAST = "Interface\\Icons\\Spell_Nature_Polymorph"

local function NewRadialMock(row, x, spec)
    local m = CreateFrame("Frame", nil, row)
    m:SetSize(200, PREVIEW_H)
    m:SetPoint("TOP", row, "TOPLEFT", x, 0)
    m.spec = spec
    m.anchor = CreateFrame("Frame", nil, m)
    m.anchor:SetSize(1, 1)
    m.anchor:SetPoint("CENTER", m, "CENTER", 0, 4)
    m.w = Radial.New(m)
    m.round, m.square = {}, {}
    for i = 1, #PREVIEW_ICONS do
        m.round[i] = Radial.NewOrbitIcon(m.w.auraLayer)
        m.square[i] = PreviewIcon(m.w.auraLayer, 16)
    end
    return m
end

local function PaintRadialMock(m, now)
    local db = CommanderPlatesDB
    local spec = m.spec
    local ctx = { class = spec.class, reaction = spec.reaction }
    local isFriend = spec.reaction == "FRIENDLY"
    local cfg = Radial.Config(function(key) return db[key] end)
    local w = m.w
    Radial.Layout(w, cfg)
    Radial.Place(w, m.anchor, cfg, not isFriend)
    w:Show()

    -- Health: class, reaction or a palette key, or the low-health colour
    local key = cfg.healthColor
    local classOn = isFriend and db.FriendlyClassColor or db.EnemyClassColor
    if key == "AUTO" then key = classOn and "CLASS" or (db.ReactionScheme or "REACTION") end
    local r, g, b = Draw.ResolveColor(key, ctx)
    if cfg.lowHealth > 0 and spec.health * 100 < cfg.lowHealth then r, g, b = Draw.ResolveColor(cfg.lowColor, ctx) end
    w.trailValue = nil
    Radial.SetHealth(w, cfg, spec.health, r, g, b, now, isFriend and 0.1 or 0)
    if not isFriend and cfg.trail then
        -- A standing trail, so the page shows what the option draws
        w.trailValue, w.trailTarget, w.trailLive = spec.health + 0.12, spec.health, false
        Radial.SetHealth(w, cfg, spec.health, r, g, b, now, 0)
        w.trailLive = false
    end
    local wantPower = cfg.powerMode == "ALL" or cfg.powerMode == "PLAYERS" or cfg.powerMode == "MANA"
    Radial.SetPower(w, cfg, wantPower and spec.mana or nil, 0, 0.55, 1, now)
    Radial.SetMarker(w, "pct", (not isFriend) and (db.HealthMarkerPercent or 0) / 100 or nil, 1, 1, 1)
    Radial.SetMarker(w, "value", (not isFriend) and (db.HealthMarkerValue or 0) / PREVIEW_MAXHP or nil, 1, 0.82, 0.2)

    -- Name
    local text = spec.name
    local textMode = isFriend and db.FriendlyNameText or db.EnemyNameText
    if textMode == "CLASS" then text = spec.className elseif textMode == "NONE" then text = "" end
    if not isFriend and db.ArenaNumbers == "REPLACE" then text = "2" elseif not isFriend and db.ArenaNumbers == "PREFIX" and text ~= "" then text = "2 " .. text end
    local nameKey = isFriend and db.FriendlyNameColor or db.EnemyNameColor
    local nr, ng, nb = 1, 1, 1
    if nameKey ~= "DEFAULT" then nr, ng, nb = Draw.ResolveColor(nameKey, ctx) end
    Radial.SetName(w, cfg, text, nr, ng, nb, (cfg.combo and not isFriend) and (cfg.pipSize + 2) or 0)

    -- The face: the mage's cast, the druid's sheep
    local ccTint = DATA.KIND.POLY.tint
    local sheeped = isFriend and cfg.coreCC and db.CcEnable and db.CcOnFriends and db.CcIncaps
    local casting = (not isFriend) and cfg.coreCast
    Radial.SetDrBadge(w, nil)
    if sheeped then
        Radial.SetCore(w, "ICON", PREVIEW_CC)
        Radial.SetCoreSwipe(w, now - 2, 8)
        Radial.SetCenterText(w, db.CcTimer and "6" or "")
        if db.CcDrBadge then Radial.SetDrBadge(w, DATA.BRACKET_LABEL[2], unpack(DATA.BRACKET_TINT[2])) end
    elseif casting then
        Radial.SetCore(w, "ICON", PREVIEW_CAST)
        Radial.SetCoreSwipe(w, nil)
        Radial.SetCenterText(w, db.CastTimer and "1.4" or "")
    else
        Radial.SetCoreSwipe(w, nil)
        if cfg.coreArt == "NONE" then Radial.SetCore(w, "NONE") else Radial.SetCore(w, "CLASS", spec.class) end
        local mid = CommanderPlates_Engine.CoreText(cfg.coreText, spec.health, spec.health * PREVIEW_MAXHP,
            (not isFriend and db.ArenaNumbers ~= "OFF") and 2 or nil)
        Radial.SetCenterText(w, mid)
    end
    Radial.SetClassBadge(w, (sheeped or casting) and ((isFriend and db.ClassIconFriendly) or (not isFriend and db.ClassIconEnemy)) and spec.class or nil)
    Radial.SetBacking(w, 0, 0, 0, 0.85)
    local br, bg, bb = 0.02, 0.02, 0.03
    if cfg.backdrop == "CLASS" or cfg.backdrop == "REACTION" then
        local key = cfg.backdrop == "CLASS" and "CLASS" or (db.ReactionScheme or "REACTION")
        local r2, g2, b2 = Draw.ResolveColor(key, ctx)
        br, bg, bb = r2 * 0.28, g2 * 0.28, b2 * 0.28
    end
    Radial.SetBackdrop(w, br, bg, bb, cfg.backdropAlpha, cfg.backdropBorder)
    if sheeped then
        Radial.SetRim(w, ccTint[1], ccTint[2], ccTint[3], 1)
    elseif cfg.rimColor == "OFF" then
        Radial.SetRim(w, 0, 0, 0, 1)
    else
        Radial.SetRim(w, Draw.ResolveColor(cfg.rimColor, ctx))
    end

    -- The cast, looping: the enemy is casting the emphasised Polymorph
    if not isFriend and cfg.cast then
        local loud = db.CastEmphasis
        local cr, cg, cb = Draw.ResolveColor(loud and (db.CastEmphasisColor or "RED") or cfg.castColor, ctx)
        m.castStart = now
        Radial.SetCast(w, cfg, now - 0.6, 2.5, false, cr, cg, cb)
        local line = cfg.castName and ("Polymorph" .. (cfg.castTarget and " \194\187 |cffff4040YOU|r" or "")) or nil
        Radial.SetCastName(w, line, cr, cg, cb)
        Radial.SetAlert(w, loud, cr, cg, cb, 0.9)
    else
        Radial.ClearCast(w)
        Radial.SetCastName(w, nil)
        Radial.SetAlert(w, false)
    end

    -- Target and focus
    local glowOn = isFriend and db.FocusGlow or db.TargetGlow
    local gr, gg, gb = Draw.ResolveColor(isFriend and db.FocusGlowColor or db.TargetGlowColor, ctx)
    Radial.SetGlow(w, glowOn, gr, gg, gb, db.TargetGlowAlpha or 0.75, cfg.glowMotion)
    Radial.SetPips(w, cfg, (cfg.combo and not isFriend) and 3 or 0, 5)
    Radial.SetRaid(w, (cfg.raid and not isFriend) and 8 or nil)
    Radial.SetHealer(w, false)
    -- The mage is looking at you, and has his trinket up
    if not isFriend and cfg.targetsYou ~= "OFF" then
        Radial.SetTargetsYou(w, true, Draw.ResolveColor(cfg.targetsYouColor, ctx))
    else
        Radial.SetTargetsYou(w, false)
    end
    Radial.SetTrinket(w, (not isFriend and cfg.trinket) and "Interface\\Icons\\INV_Jewelry_TrinketPVP_01" or nil)
    Radial.SetLevel(w, nil)

    -- The orbit: three dots on the mage, a Rejuvenation on the druid
    local pool, other = m.round, m.square
    if not cfg.roundAuras then pool, other = other, pool end
    for _, f in ipairs(other) do f:Hide() end
    local rowMode = isFriend and db.FriendBuffs or db.EnemyDebuffs
    local shown = rowMode == "OFF" and 0 or (isFriend and 1 or #PREVIEW_ICONS)
    for i, f in ipairs(pool) do
        if i <= shown then
            f:SetSize(cfg.auraSize, cfg.auraSize)
            f.icon:SetTexture(isFriend and "Interface\\Icons\\Spell_Nature_Rejuvenation" or PREVIEW_ICONS[i])
            if db.AuraKindBorder and i == 2 and not isFriend then
                f.border:SetVertexColor(0.90, 0.20, 0.20)
            elseif db.AuraOwnBorder and i ~= 2 then
                f.border:SetVertexColor(0.95, 0.95, 0.95)
            else
                f.border:SetVertexColor(0, 0, 0)
            end
            f.timer:SetShown(db.AuraTimer == true)
            f.timer:SetFont(STANDARD_TEXT_FONT, math.max(8, math.floor(cfg.auraSize * 0.55)), "OUTLINE")
            f.timer:SetText(({ "12", "8", "2.4" })[i])
            if db.AuraTimer and db.AuraTimerUrgent and i == 3 then f.timer:SetTextColor(1, 0.3, 0.3) else f.timer:SetTextColor(1, 1, 1) end
            f.glow:Hide()
            f:Show()
        else
            f:Hide()
        end
    end
    local slots = Radial.LayoutOrbit(w, cfg, pool, 1, shown, isFriend and cfg.buffArc or cfg.debuffArc,
        isFriend and cfg.buffGrow or cfg.debuffGrow)
    -- The mage was stunned a few seconds ago: the next stun lands at half,
    -- and the category resets in nine seconds
    local E = CommanderPlates_Engine
    local drOn = (not isFriend) and cfg.drMode ~= "OFF"
    local drRows = E.DrRows(drOn and { { cat = "STUN", bracket = 2, resetAt = now + 9, last = 1833 } } or nil, 15,
        function() return "Interface\\Icons\\Ability_CheapShot" end)
    local drSlots = Radial.SetDrStrip(w, cfg, drRows, cfg.drArc)
    for _, s in ipairs(drSlots) do slots[#slots + 1] = s end
    local left, right = E.OrbitSideExtents(slots, cfg.auraSize, (db.TargetArrowSize or 22) / 2)
    Radial.SetArrows(w, cfg, (not isFriend) and db.TargetArrows, math.min(db.TargetArrowSize or 22, 26), gr, gg, gb, left, right)
end

local function AddPreviewRow(panel)
    local row = panel:AddRow(PREVIEW_H, 8)
    local bg = Draw.NewQuad(row, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetVertexColor(0.05, 0.05, 0.05, 0.6)
    local enemy = NewMockPlate(row, 118, { name = "Gankmage", className = "Mage", class = "MAGE", reaction = "HOSTILE", health = 0.62 })
    local friend = NewMockPlate(row, 340, { name = "Leafheal", className = "Druid", class = "DRUID", reaction = "FRIENDLY", health = 0.85 })
    local radialEnemy = NewRadialMock(row, 118, { name = "Gankmage", className = "Mage", class = "MAGE", reaction = "HOSTILE", health = 0.42, mana = 0.55 })
    local radialFriend = NewRadialMock(row, 340, { name = "Leafheal", className = "Druid", class = "DRUID", reaction = "FRIENDLY", health = 0.85, mana = 0.7 })
    local totem = NewMockTotem(row, 500)
    local caption = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    caption:SetPoint("BOTTOM", row, "BOTTOM", 0, 4)
    local function Repaint()
        local radial = CommanderPlatesDB.PlateStyle == "RADIAL"
        local scope = CommanderPlatesDB.RadialUnits or "ALL"
        -- Which of the two follow the style is the Radial Plates For setting
        local enemyRadial = radial
        local friendRadial = radial and (scope == "ALL" or scope == "PLAYERS")
        enemy:SetShown(not enemyRadial); radialEnemy:SetShown(enemyRadial)
        friend:SetShown(not friendRadial); radialFriend:SetShown(friendRadial)
        local now = GetTime()
        if enemyRadial then PaintRadialMock(radialEnemy, now) else PaintMock(enemy) end
        if friendRadial then PaintRadialMock(radialFriend, now) else PaintMock(friend) end
        PaintMockTotem(totem)
        if radial then
            caption:SetText("Preview: an enemy mage you are targeting, casting Polymorph, with your dots on him  |  a friendly druid on focus, sheeped  |  a totem keeps its own look")
        else
            caption:SetText("Preview: an enemy mage you are targeting, sheeped, with your dots on him  |  a friendly druid on focus, with your Rejuvenation  |  a Grounding Totem")
        end
    end
    -- The mage's cast loops while the page is open, so the sweep and its
    -- spark are seen moving rather than described
    row.since = 0
    row:SetScript("OnUpdate", function(self, elapsed)
        self.since = self.since + elapsed
        if self.since < 2.5 then return end
        self.since = 0
        if radialEnemy:IsShown() and CommanderPlatesDB.RadialCastRing then
            PaintRadialMock(radialEnemy, GetTime())
        end
    end)
    panel:AddRefresher(Repaint)
    return row
end

-- ---------------------------------------------------------------------------
-- Sections
-- ---------------------------------------------------------------------------

local function AddBarsSection(panel)
    Section(panel, "Health Bars & Names",
        "The bar is the class. Friendly players in their class colour is the thing Blizzard's plates never quite did on this client; enemies too, so a glance says warlock before the name is read.")
    panel:AddCheckboxPair({
        label = "Friendly Players: Class Colour",
        tooltip = "Colour a friendly player's health bar in their class colour instead of Blizzard's flat blue. Requires Blizzard's 'name only' friendly mode to be off (see Blizzard CVars below) -- a name has no bar to colour.",
        get = function() return CommanderPlatesDB.FriendlyClassColor end,
        set = function(v) CommanderPlatesDB.FriendlyClassColor = v end,
        isEnabled = Enabled,
    }, {
        label = "Enemy Players: Class Colour",
        tooltip = "Colour an enemy player's health bar by class instead of hostile red.",
        get = function() return CommanderPlatesDB.EnemyClassColor end,
        set = function(v) CommanderPlatesDB.EnemyClassColor = v end,
        isEnabled = Enabled,
    })
    panel:AddDropdown({
        label = "Friend / Foe Colours",
        tooltip = "The pair of colours that means 'enemy' and 'friend' wherever a plate is coloured by standing rather than by class: NPC bars and names, the radial ring's automatic colour, the name of whoever a cast is aimed at. Red / blue is Blizzard's; red / green is the classic friendly-green. Each colour setting below also offers both by name.",
        options = {
            { text = "Hostile red / friendly blue", value = "REACTION" },
            { text = "Hostile red / friendly green", value = "REACTION_RG" },
        },
        width = 200,
        get = function() return CommanderPlatesDB.ReactionScheme end,
        set = function(v) CommanderPlatesDB.ReactionScheme = v end,
        isEnabled = Enabled,
    })
    panel:AddDropdownPair({
        label = "Hostile Frame Tint",
        tooltip = "Tint the frame around a hostile unit's bar -- the gold border art in the Classic style, the dark one in the modern styles. With class-coloured bars on both sides this is what says 'enemy' at a glance.",
        options = Draw.ColorOptions({ { text = "Off", value = "OFF" } }),
        get = function() return CommanderPlatesDB.HostileBorderTint end,
        set = function(v) CommanderPlatesDB.HostileBorderTint = v end,
        isEnabled = BarsShown,
    }, {
        label = "Friendly Frame Tint",
        tooltip = "Tint the frame around a friendly unit's bar.",
        options = Draw.ColorOptions({ { text = "Off", value = "OFF" } }),
        get = function() return CommanderPlatesDB.FriendlyBorderTint end,
        set = function(v) CommanderPlatesDB.FriendlyBorderTint = v end,
        isEnabled = BarsShown,
    })
    panel:AddDropdownPair({
        label = "Enemy Name Colour",
        tooltip = "Colour of the name text over an enemy player's plate. 'Hostile red / friendly blue' colours by standing instead of class.",
        options = Draw.ColorOptions({ { text = "Blizzard's", value = "DEFAULT" } }),
        get = function() return CommanderPlatesDB.EnemyNameColor end,
        set = function(v) CommanderPlatesDB.EnemyNameColor = v end,
        isEnabled = Enabled,
    }, {
        label = "Friendly Name Colour",
        tooltip = "Colour of the name text over a friendly player's plate.",
        options = Draw.ColorOptions({ { text = "Blizzard's", value = "DEFAULT" } }),
        get = function() return CommanderPlatesDB.FriendlyNameColor end,
        set = function(v) CommanderPlatesDB.FriendlyNameColor = v end,
        isEnabled = Enabled,
    })
    panel:AddDropdown({
        label = "NPC Name Colour",
        tooltip = "Colour of the name text over NPC plates. 'Hostile red / friendly blue' also gives neutral NPCs yellow, the way the old plates did.",
        options = Draw.ColorOptions({ { text = "Blizzard's", value = "DEFAULT" } }),
        get = function() return CommanderPlatesDB.NpcNameColor end,
        set = function(v) CommanderPlatesDB.NpcNameColor = v end,
        isEnabled = Enabled,
    })
    panel:AddDropdownPair({
        label = "Enemy Player Names",
        tooltip = "What the name text over an enemy player's plate says. 'Class' is the arena habit -- 'Mage' reads faster than a name you have never seen; 'Nothing' leaves the class icon and colour to do the talking. Arena numbers still apply.",
        options = {
            { text = "Their name", value = "NAME" },
            { text = "Their class", value = "CLASS" },
            { text = "Nothing", value = "NONE" },
        },
        get = function() return CommanderPlatesDB.EnemyNameText end,
        set = function(v) CommanderPlatesDB.EnemyNameText = v end,
        isEnabled = Enabled,
    }, {
        label = "Friendly Player Names",
        tooltip = "What the name text over a friendly player's plate says.",
        options = {
            { text = "Their name", value = "NAME" },
            { text = "Their class", value = "CLASS" },
            { text = "Nothing", value = "NONE" },
        },
        get = function() return CommanderPlatesDB.FriendlyNameText end,
        set = function(v) CommanderPlatesDB.FriendlyNameText = v end,
        isEnabled = Enabled,
    })
    panel:AddSlider({
        label = "Health Marker (percent)",
        tooltip = "Draw a thin white line across every enemy health bar at this percentage -- 20 for a warrior's Execute range. 0 draws nothing.",
        min = 0, max = 50, step = 1,
        format = function(v) return v == 0 and "Off" or (v .. "%") end,
        get = function() return CommanderPlatesDB.HealthMarkerPercent end,
        set = function(v) CommanderPlatesDB.HealthMarkerPercent = v end,
        isEnabled = Enabled,
    })
    AddTextRow(panel, {
        label = "Health Marker (value)",
        tooltip = "Draw a thin gold line at this much HEALTH on every enemy bar -- the number your burst combo covers, say Mind Blast + Shadow Word: Pain. It moves with each unit's maximum health, so below the line means dead. For enemy players, whose maximum the client only reports as a percent, the line uses the combat-log estimate (see Commander Nameplate's 'Estimate Enemy Player Health') and appears once one exists. 0 or blank draws nothing.",
        width = 120,
        get = function() local v = CommanderPlatesDB.HealthMarkerValue or 0; return v > 0 and tostring(v) or "" end,
        set = function(v) CommanderPlatesDB.HealthMarkerValue = tonumber((v or ""):match("%d+")) or 0 end,
    })
end

local function AddAuraFilterSection(panel)
    Section(panel, "Buffs & Debuffs: What Is Shown",
        "Your own casts are always the baseline. 'Notable' adds the auras that decide fights whether or not you cast them: control, immunities, offensive and defensive cooldowns, Mortal Strike, Viper Sting, Curse of Tongues. The whitelist wins over every filter; the blacklist loses only to the whitelist.")
    panel:AddDropdownPair({
        label = "Enemy Debuffs",
        tooltip = "Debuffs drawn over an ENEMY's plate. 'Mine + notable' is the arena answer: your own damage and control, plus anyone else's control so you can see the kill window.",
        options = {
            { text = "Off", value = "OFF" },
            { text = "Mine", value = "MINE" },
            { text = "Mine + notable", value = "MINE_NOTABLE" },
            { text = "Everything", value = "ALL" },
        },
        width = 150,
        get = function() return CommanderPlatesDB.EnemyDebuffs end,
        set = function(v) CommanderPlatesDB.EnemyDebuffs = v end,
        isEnabled = Enabled,
    }, {
        label = "Enemy Buffs",
        tooltip = "Buffs drawn over an ENEMY's plate. 'Notable' is their cooldowns and immunities; 'purgeable' is whatever your class can strip off (Purge, Dispel Magic, Spellsteal, Devour Magic).",
        options = {
            { text = "Off", value = "OFF" },
            { text = "Notable", value = "NOTABLE" },
            { text = "Purgeable", value = "PURGEABLE" },
            { text = "Notable + purgeable", value = "NOTABLE_PURGEABLE" },
            { text = "Everything", value = "ALL" },
        },
        width = 150,
        get = function() return CommanderPlatesDB.EnemyBuffs end,
        set = function(v) CommanderPlatesDB.EnemyBuffs = v end,
        isEnabled = Enabled,
    })
    panel:AddDropdownPair({
        label = "Friendly Debuffs",
        tooltip = "Debuffs drawn over a FRIEND's plate. 'Dispellable' is only what your class can lift, bordered in the dispel type's colour; 'notable' adds control on them so you can see your healer is sheeped.",
        options = {
            { text = "Off", value = "OFF" },
            { text = "Dispellable by me", value = "DISPELLABLE" },
            { text = "Dispellable + notable", value = "NOTABLE" },
            { text = "Everything", value = "ALL" },
        },
        width = 150,
        get = function() return CommanderPlatesDB.FriendDebuffs end,
        set = function(v) CommanderPlatesDB.FriendDebuffs = v end,
        isEnabled = Enabled,
    }, {
        label = "Friendly Buffs",
        tooltip = "Buffs drawn over a FRIEND's plate. 'Mine' is the HoTs, shields and blessings YOU put there -- the thing to track when you are the healer.",
        options = {
            { text = "Off", value = "OFF" },
            { text = "Mine", value = "MINE" },
            { text = "Mine + notable", value = "MINE_NOTABLE" },
            { text = "Everything", value = "ALL" },
        },
        width = 150,
        get = function() return CommanderPlatesDB.FriendBuffs end,
        set = function(v) CommanderPlatesDB.FriendBuffs = v end,
        isEnabled = Enabled,
    })
    panel:AddCheckboxPair({
        label = "Notable: Defensive Cooldowns",
        tooltip = "Shield Wall, Pain Suppression, Barkskin, Earth Shield, Power Word: Shield and the like count as notable.",
        get = function() return CommanderPlatesDB.ShowDefensives end,
        set = function(v) CommanderPlatesDB.ShowDefensives = v end,
        isEnabled = Enabled,
    }, {
        label = "Notable: Offensive Cooldowns",
        tooltip = "Arcane Power, Recklessness, Bloodlust, Adrenaline Rush, Avenging Wrath and the like count as notable -- the burst window.",
        get = function() return CommanderPlatesDB.ShowOffensives end,
        set = function(v) CommanderPlatesDB.ShowOffensives = v end,
        isEnabled = Enabled,
    })
    panel:AddCheckboxPair({
        label = "Notable: Fight-Deciding Debuffs",
        tooltip = "Mortal Strike, Wound Poison, Viper Sting, Curse of Tongues, Unstable Affliction and the like count as notable.",
        get = function() return CommanderPlatesDB.ShowNotableDebuffs end,
        set = function(v) CommanderPlatesDB.ShowNotableDebuffs = v end,
        isEnabled = Enabled,
    }, {
        label = "Notable: Slows",
        tooltip = "Hamstring, Crippling Poison, Frost Shock, Earthbind and every other slow count as notable. Off by default -- a battleground is nothing but slows.",
        get = function() return CommanderPlatesDB.ShowSlows end,
        set = function(v) CommanderPlatesDB.ShowSlows = v end,
        isEnabled = Enabled,
    })
    panel:AddDropdown({
        label = "Track Auras",
        tooltip = "Where the aura rows and the big control icon draw. 'Everywhere' includes the open world and dungeons; 'Arenas & battlegrounds' keeps the plates plain outside PvP instances. Colours, hit boxes and target marks are not affected.",
        options = {
            { text = "Everywhere", value = "ALWAYS" },
            { text = "Arenas & battlegrounds", value = "INSTANCES" },
        },
        width = 200,
        get = function() return CommanderPlatesDB.TrackWhere end,
        set = function(v) CommanderPlatesDB.TrackWhere = v end,
        isEnabled = Enabled,
    })
    AddTextRow(panel, {
        label = "Always Show (whitelist)",
        tooltip = "Spell names or ids, separated by commas. Anything here is drawn on every plate whatever the filters above say.",
        get = function() return CommanderPlatesDB.Whitelist end,
        set = function(v) CommanderPlatesDB.Whitelist = v end,
    })
    AddTextRow(panel, {
        label = "Never Show (blacklist)",
        tooltip = "Spell names or ids, separated by commas. Anything here is never drawn, unless the whitelist also names it.",
        get = function() return CommanderPlatesDB.Blacklist end,
        set = function(v) CommanderPlatesDB.Blacklist = v end,
    })
    panel:AddCheckbox({
        label = "Replace Blizzard's Aura Icons",
        tooltip = "Hide the aura icons Blizzard's own plates draw so the rows above are the only ones. Turn off to keep both.",
        get = function() return CommanderPlatesDB.HideBlizzardAuras end,
        set = function(v) CommanderPlatesDB.HideBlizzardAuras = v end,
        isEnabled = Enabled,
    })
end

local function AddAuraLookSection(panel)
    Section(panel, "Buffs & Debuffs: How They Look",
        "Debuffs sit above the name; buffs above those, or under the plate if you would rather they stayed out of the way.")
    panel:AddSliderPair({
        label = "Icon Size",
        tooltip = "Size of each aura icon in the rows.",
        min = 14, max = 40, step = 1,
        get = function() return CommanderPlatesDB.AuraSize end,
        set = function(v) CommanderPlatesDB.AuraSize = v end,
        isEnabled = BarsShown,
    }, {
        label = "Icon Spacing",
        tooltip = "Gap between icons.",
        min = 0, max = 10, step = 1,
        get = function() return CommanderPlatesDB.AuraSpacing end,
        set = function(v) CommanderPlatesDB.AuraSpacing = v end,
        isEnabled = Enabled,
    })
    panel:AddSliderPair({
        label = "Icons Per Row",
        tooltip = "How many icons before a row wraps upward onto a second line.",
        min = 2, max = 12, step = 1,
        get = function() return CommanderPlatesDB.AuraPerRow end,
        set = function(v) CommanderPlatesDB.AuraPerRow = v end,
        isEnabled = BarsShown,
    }, {
        label = "Timer Text Size",
        tooltip = "Font size of the remaining-time text on each icon.",
        min = 8, max = 18, step = 1,
        get = function() return CommanderPlatesDB.AuraTimerSize end,
        set = function(v) CommanderPlatesDB.AuraTimerSize = v end,
        isEnabled = function() return Enabled() and CommanderPlatesDB.AuraTimer end,
    })
    panel:AddSliderPair({
        label = "Most Debuffs Shown",
        tooltip = "Cap on the debuff row. The ones that matter most are kept (see Sort).",
        min = 1, max = 16, step = 1,
        get = function() return CommanderPlatesDB.DebuffMax end,
        set = function(v) CommanderPlatesDB.DebuffMax = v end,
        isEnabled = Enabled,
    }, {
        label = "Most Buffs Shown",
        tooltip = "Cap on the buff row.",
        min = 1, max = 12, step = 1,
        get = function() return CommanderPlatesDB.BuffMax end,
        set = function(v) CommanderPlatesDB.BuffMax = v end,
        isEnabled = Enabled,
    })
    local function Seconds(v)
        if v == 0 then return "No cap" end
        if v >= 60 and v % 60 == 0 then return (v / 60) .. " min" end
        return v .. " s"
    end
    panel:AddSliderPair({
        label = "Buffs: Longest Shown",
        tooltip = "Buffs that last longer than this are not drawn -- the half-hour Fortitude, Mark of the Wild and Intellect that would otherwise fill every friendly plate. A buff with no duration counts as longer than any cap. The whitelist is exempt, and so is anything your class can purge off an enemy -- the long buffs are the ones worth stripping. 'No cap' shows them all.",
        min = 0, max = 300, step = 5,
        format = Seconds,
        get = function() return CommanderPlatesDB.BuffMaxDuration end,
        set = function(v) CommanderPlatesDB.BuffMaxDuration = v end,
        isEnabled = Enabled,
    }, {
        label = "Debuffs: Longest Shown",
        tooltip = "Debuffs that last longer than this are not drawn. Off by default -- a long debuff on an enemy is usually one worth knowing about (Hunter's Mark, Curse of Elements).",
        min = 0, max = 300, step = 5,
        format = Seconds,
        get = function() return CommanderPlatesDB.DebuffMaxDuration end,
        set = function(v) CommanderPlatesDB.DebuffMaxDuration = v end,
        isEnabled = Enabled,
    })
    panel:AddDropdownPair({
        label = "Grow",
        tooltip = "Which way a row extends from the plate's centre.",
        options = {
            { text = "Centred", value = "CENTER" },
            { text = "Leftward", value = "LEFT" },
            { text = "Rightward", value = "RIGHT" },
        },
        get = function() return CommanderPlatesDB.AuraGrow end,
        set = function(v) CommanderPlatesDB.AuraGrow = v end,
        isEnabled = BarsShown,
    }, {
        label = "Sort",
        tooltip = "Order within a row. 'What matters' puts control first, then your own, then soonest to expire -- so the cap trims the right end.",
        options = {
            { text = "What matters", value = "PRIORITY" },
            { text = "Ending soonest", value = "TIME" },
            { text = "Ending last", value = "TIME_DESC" },
            { text = "Name", value = "NAME" },
        },
        get = function() return CommanderPlatesDB.AuraSort end,
        set = function(v) CommanderPlatesDB.AuraSort = v end,
        isEnabled = Enabled,
    })
    panel:AddDropdown({
        label = "Buff Row",
        tooltip = "Where the buff row sits: stacked above the debuffs, or tucked under the plate beneath the cast bar.",
        options = {
            { text = "Above the debuffs", value = "ABOVE" },
            { text = "Under the plate", value = "BELOW" },
        },
        width = 160,
        get = function() return CommanderPlatesDB.BuffRowPosition end,
        set = function(v) CommanderPlatesDB.BuffRowPosition = v end,
        isEnabled = BarsShown,
    })
    panel:AddCheckboxPair({
        label = "Remaining Time",
        tooltip = "Write the seconds left on each icon. Tenths under three seconds.",
        get = function() return CommanderPlatesDB.AuraTimer end,
        set = function(v) CommanderPlatesDB.AuraTimer = v end,
        isEnabled = Enabled,
    }, {
        label = "Stack Count",
        tooltip = "Write the stack count on icons that have one (Sunder Armor, Deadly Poison, Lifebloom).",
        get = function() return CommanderPlatesDB.AuraStacks end,
        set = function(v) CommanderPlatesDB.AuraStacks = v end,
        isEnabled = Enabled,
    })
    panel:AddCheckboxPair({
        label = "Clock Sweep",
        tooltip = "Darken each icon clockwise as it runs out.",
        get = function() return CommanderPlatesDB.AuraSwipe end,
        set = function(v) CommanderPlatesDB.AuraSwipe = v end,
        isEnabled = Enabled,
    }, {
        label = "Mark My Own",
        tooltip = "Give the auras YOU cast a bright border, so your Corruption and the other warlock's read differently.",
        get = function() return CommanderPlatesDB.AuraOwnBorder end,
        set = function(v) CommanderPlatesDB.AuraOwnBorder = v end,
        isEnabled = Enabled,
    })
    panel:AddCheckboxPair({
        label = "Colour Border By Kind",
        tooltip = "Tint the border by what the aura is: gold for stuns, blue for incapacitates, purple for fears, orange for silences, green for roots, dispel-type colours on friends.",
        get = function() return CommanderPlatesDB.AuraKindBorder end,
        set = function(v) CommanderPlatesDB.AuraKindBorder = v end,
        isEnabled = Enabled,
    }, {
        label = "Purgeable Glow",
        tooltip = "Glow an enemy buff your class can strip off. Only shows for priests, shamans, mages and warlocks.",
        get = function() return CommanderPlatesDB.PurgeGlow end,
        set = function(v) CommanderPlatesDB.PurgeGlow = v end,
        isEnabled = Enabled,
    })
    panel:AddCheckboxPair({
        label = "Red Under Three Seconds",
        tooltip = "Turn the remaining-time text red as an aura enters its last three seconds -- the moment to pre-cast the next control, or to expect the sap to break.",
        get = function() return CommanderPlatesDB.AuraTimerUrgent end,
        set = function(v) CommanderPlatesDB.AuraTimerUrgent = v end,
        isEnabled = function() return Enabled() and CommanderPlatesDB.AuraTimer end,
    }, {
        label = "Tooltips On Hover",
        tooltip = "Let the mouse rest on an aura icon to read its tooltip. OFF keeps the icons click-through, which is what you want in a fight.",
        get = function() return CommanderPlatesDB.AuraTooltips end,
        set = function(v) CommanderPlatesDB.AuraTooltips = v end,
        isEnabled = Enabled,
    })
end

local function AddCcSection(panel)
    Section(panel, "Loose Control: The Big Icon",
        "One large icon on the plate for the control the unit is sitting in right now -- stuns, incapacitates, fears, silences, roots, disarms, and the immunities that mean stop casting. The highest-priority one wins; ties go to whichever lasts longer.")
    panel:AddCheckboxPair({
        label = "Show On Enemies",
        tooltip = "The big icon on enemy plates: your kill window, and the moment their healer cannot heal.",
        get = function() return CommanderPlatesDB.CcOnEnemies end,
        set = function(v) CommanderPlatesDB.CcOnEnemies = v end,
        isEnabled = function() return Enabled() and CommanderPlatesDB.CcEnable end,
    }, {
        label = "Show On Friends",
        tooltip = "The big icon on friendly plates: your healer is sheeped, your partner is stunned. The thing to dispel or trinket for.",
        get = function() return CommanderPlatesDB.CcOnFriends end,
        set = function(v) CommanderPlatesDB.CcOnFriends = v end,
        isEnabled = function() return Enabled() and CommanderPlatesDB.CcEnable end,
    })
    panel:AddSliderPair({
        label = "Icon Size",
        tooltip = "Size of the big icon.",
        min = 20, max = 64, step = 1,
        get = function() return CommanderPlatesDB.CcSize end,
        set = function(v) CommanderPlatesDB.CcSize = v end,
        isEnabled = function() return Enabled() and CommanderPlatesDB.CcEnable end,
    }, {
        label = "Vertical Nudge",
        tooltip = "Move the big icon up or down from its anchor.",
        min = -40, max = 40, step = 1,
        get = function() return CommanderPlatesDB.CcOffsetY end,
        set = function(v) CommanderPlatesDB.CcOffsetY = v end,
        isEnabled = function() return Enabled() and CommanderPlatesDB.CcEnable end,
    })
    panel:AddDropdown({
        label = "Anchor",
        tooltip = "Where the big icon sits: above the plate (over the aura rows), under the cast bar, off the bar's left or right end, or -- covering the health it is there to explain -- over the bar itself.",
        options = {
            { text = "Above the plate", value = "ABOVE" },
            { text = "Below the cast bar", value = "BELOW" },
            { text = "Left of the bar", value = "LEFT" },
            { text = "Right of the bar", value = "RIGHT" },
            { text = "Over the bar", value = "CENTER" },
        },
        width = 150,
        get = function() return CommanderPlatesDB.CcAnchor end,
        set = function(v) CommanderPlatesDB.CcAnchor = v end,
        isEnabled = function() return BarsShown() and CommanderPlatesDB.CcEnable end,
    })
    panel:AddCheckboxPair({
        label = "Remaining Time",
        tooltip = "Write the seconds left on the big icon.",
        get = function() return CommanderPlatesDB.CcTimer end,
        set = function(v) CommanderPlatesDB.CcTimer = v end,
        isEnabled = function() return Enabled() and CommanderPlatesDB.CcEnable end,
    }, {
        label = "Coloured Glow",
        tooltip = "Glow the big icon in its category's colour -- gold stun, blue incapacitate, purple fear, orange silence, green root, white immunity.",
        get = function() return CommanderPlatesDB.CcGlow end,
        set = function(v) CommanderPlatesDB.CcGlow = v end,
        isEnabled = function() return Enabled() and CommanderPlatesDB.CcEnable end,
    })
    panel:AddCheckboxPair({
        label = "Do Not Repeat It In The Row",
        tooltip = "The aura in the big slot is dropped from the debuff row so it is drawn once. Off draws it in both places.",
        get = function() return CommanderPlatesDB.CcHideDuplicate end,
        set = function(v) CommanderPlatesDB.CcHideDuplicate = v end,
        isEnabled = function() return Enabled() and CommanderPlatesDB.CcEnable end,
    }, {
        label = "DR Badge (needs Commander Diminish)",
        tooltip = "Write the diminishing-returns bracket the control landed at on the big icon -- \194\189 for half, \194\188 for a quarter, and an X when the NEXT one would be immune. Read live from Commander Diminish, so it shows wherever that tracker is watching (arenas and battlegrounds by default).",
        get = function() return CommanderPlatesDB.CcDrBadge end,
        set = function(v) CommanderPlatesDB.CcDrBadge = v end,
        isEnabled = function() return Enabled() and CommanderPlatesDB.CcEnable end,
    })
    panel:AddCheckboxPair({
        label = "Stuns",
        tooltip = "Cheap Shot, Kidney Shot, Hammer of Justice, Charge, Intercept, Bash, Pounce, War Stomp, and every proc stun.",
        get = function() return CommanderPlatesDB.CcStuns end,
        set = function(v) CommanderPlatesDB.CcStuns = v end,
        isEnabled = function() return Enabled() and CommanderPlatesDB.CcEnable end,
    }, {
        label = "Incapacitates",
        tooltip = "Polymorph, Sap, Gouge, Repentance, Blind, Cyclone, Freezing Trap, Hibernate, Wyvern Sting, Banish, Dragon's Breath, Scatter Shot.",
        get = function() return CommanderPlatesDB.CcIncaps end,
        set = function(v) CommanderPlatesDB.CcIncaps = v end,
        isEnabled = function() return Enabled() and CommanderPlatesDB.CcEnable end,
    })
    panel:AddCheckboxPair({
        label = "Fears & Horrors",
        tooltip = "Fear, Psychic Scream, Howl of Terror, Intimidating Shout, Seduction, Death Coil, Mind Control.",
        get = function() return CommanderPlatesDB.CcFears end,
        set = function(v) CommanderPlatesDB.CcFears = v end,
        isEnabled = function() return Enabled() and CommanderPlatesDB.CcEnable end,
    }, {
        label = "Silences",
        tooltip = "Silence, Counterspell, Spell Lock, Silencing Shot, Garrote, Arcane Torrent. TBC has no DR on these, so they come from the name list.",
        get = function() return CommanderPlatesDB.CcSilences end,
        set = function(v) CommanderPlatesDB.CcSilences = v end,
        isEnabled = function() return Enabled() and CommanderPlatesDB.CcEnable end,
    })
    panel:AddCheckboxPair({
        label = "Roots",
        tooltip = "Frost Nova, Entangling Roots, Frostbite, Improved Hamstring, Feral Charge, Chastise.",
        get = function() return CommanderPlatesDB.CcRoots end,
        set = function(v) CommanderPlatesDB.CcRoots = v end,
        isEnabled = function() return Enabled() and CommanderPlatesDB.CcEnable end,
    }, {
        label = "Disarms",
        tooltip = "Disarm and Riposte.",
        get = function() return CommanderPlatesDB.CcDisarms end,
        set = function(v) CommanderPlatesDB.CcDisarms = v end,
        isEnabled = function() return Enabled() and CommanderPlatesDB.CcEnable end,
    })
    panel:AddCheckbox({
        label = "Immunities",
        tooltip = "Divine Shield, Ice Block, Blessing of Protection, Cloak of Shadows, Spell Reflection, Deterrence, Evasion, Grounding Totem take the big slot when no control is up -- the moment to stop casting at someone.",
        get = function() return CommanderPlatesDB.CcImmunities end,
        set = function(v) CommanderPlatesDB.CcImmunities = v end,
        isEnabled = function() return Enabled() and CommanderPlatesDB.CcEnable end,
    })
end

local function AddHitBoxSection(panel)
    Section(panel, "Clickable Area & Friendly Plates",
        "The plate looks exactly the same; the region the mouse hits is taller. Blizzard's own box is the health bar plus a little; these add to it. Friendly plates can also be faded or made click-through so they stop standing between you and the enemy.")
    panel:AddSliderPair({
        label = "Extra Above",
        tooltip = "Extra clickable pixels above the health bar. The name sits there, and clicking a name should select.",
        min = 0, max = 30, step = 1,
        get = function() return CommanderPlatesDB.HitBoxTop end,
        set = function(v) CommanderPlatesDB.HitBoxTop = v end,
        isEnabled = Enabled,
    }, {
        label = "Extra Below",
        tooltip = "Extra clickable pixels below the health bar, over the cast bar.",
        min = 0, max = 30, step = 1,
        get = function() return CommanderPlatesDB.HitBoxBottom end,
        set = function(v) CommanderPlatesDB.HitBoxBottom = v end,
        isEnabled = Enabled,
    })
    panel:AddSlider({
        label = "Extra Sides",
        tooltip = "Extra clickable pixels to the left and right of the bar. Keep small; wide boxes overlap the neighbour's plate.",
        min = 0, max = 30, step = 1,
        get = function() return CommanderPlatesDB.HitBoxSides end,
        set = function(v) CommanderPlatesDB.HitBoxSides = v end,
        isEnabled = Enabled,
    })
    panel:AddSlider({
        label = "Friendly Plate Opacity",
        tooltip = "Fade every friendly plate so the enemy ones stand out. 100% leaves them as Blizzard draws them.",
        min = 0.2, max = 1.0, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderPlatesDB.FriendlyAlpha end,
        set = function(v) CommanderPlatesDB.FriendlyAlpha = v end,
        isEnabled = Enabled,
    })
    panel:AddDropdown({
        label = "Friendly Plates Click-Through",
        tooltip = "Make friendly plates ignore the mouse so a click lands on the enemy standing behind your teammate. 'In instances' is the arena and battleground answer. Takes effect as plates appear; a plate already on screen updates when it next re-anchors.",
        options = {
            { text = "Never", value = "NEVER" },
            { text = "In arenas & battlegrounds", value = "INSTANCES" },
            { text = "Always", value = "ALWAYS" },
        },
        width = 200,
        get = function() return CommanderPlatesDB.FriendlyClickThrough end,
        set = function(v) CommanderPlatesDB.FriendlyClickThrough = v end,
        isEnabled = Enabled,
    })
end

local function AddIdentitySection(panel)
    Section(panel, "Target, Focus & Who Is Who",
        "Arrows and a glow on the plate you have selected, a second glow on your focus, arena numbers in place of names, a class icon, and a cross over anyone the combat log has seen healing.")
    panel:AddCheckboxPair({
        label = "Target Arrows",
        tooltip = "Two arrows pointing in at your current target's health bar.",
        get = function() return CommanderPlatesDB.TargetArrows end,
        set = function(v) CommanderPlatesDB.TargetArrows = v end,
        isEnabled = Enabled,
    }, {
        label = "Target Glow",
        tooltip = "A coloured border around your current target's health bar.",
        get = function() return CommanderPlatesDB.TargetGlow end,
        set = function(v) CommanderPlatesDB.TargetGlow = v end,
        isEnabled = Enabled,
    })
    panel:AddSliderPair({
        label = "Arrow Size",
        tooltip = "Size of the target arrows.",
        min = 12, max = 40, step = 1,
        get = function() return CommanderPlatesDB.TargetArrowSize end,
        set = function(v) CommanderPlatesDB.TargetArrowSize = v end,
        isEnabled = function() return Enabled() and CommanderPlatesDB.TargetArrows end,
    }, {
        label = "Class Icon Size",
        tooltip = "Size of the class icon beside the bar.",
        min = 10, max = 32, step = 1,
        get = function() return CommanderPlatesDB.ClassIconSize end,
        set = function(v) CommanderPlatesDB.ClassIconSize = v end,
        isEnabled = function() return BarsShown() and (CommanderPlatesDB.ClassIconEnemy or CommanderPlatesDB.ClassIconFriendly) end,
    })
    panel:AddDropdownPair({
        label = "Target Glow Colour",
        tooltip = "Colour of the target glow and arrows. 'Unit's class' reads as a brighter version of the bar; 'hostile red / friendly blue' says which side the target is on.",
        options = Draw.ColorOptions(),
        get = function() return CommanderPlatesDB.TargetGlowColor end,
        set = function(v) CommanderPlatesDB.TargetGlowColor = v end,
        isEnabled = function() return Enabled() and CommanderPlatesDB.TargetGlow end,
    }, {
        label = "Focus Glow Colour",
        tooltip = "Colour of the focus glow.",
        options = Draw.ColorOptions(),
        get = function() return CommanderPlatesDB.FocusGlowColor end,
        set = function(v) CommanderPlatesDB.FocusGlowColor = v end,
        isEnabled = function() return Enabled() and CommanderPlatesDB.FocusGlow end,
    })
    panel:AddDropdownPair({
        label = "Glow Style",
        tooltip = "'Soft' is a real glow -- a halo that fades out from the bar's edge. 'Outline' is a hard two-pixel border.",
        options = {
            { text = "Soft glow", value = "SOFT" },
            { text = "Hard outline", value = "OUTLINE" },
        },
        get = function() return CommanderPlatesDB.TargetGlowStyle end,
        set = function(v) CommanderPlatesDB.TargetGlowStyle = v end,
        isEnabled = function() return BarsShown() and (CommanderPlatesDB.TargetGlow or CommanderPlatesDB.FocusGlow) end,
    }, {
        label = "Arena Numbers",
        tooltip = "In an arena, write the opponent's number (1-5) on their plate so 'sheep 2' means something. 'Replace' puts it in place of the name; 'prefix' in front of it.",
        options = {
            { text = "Off", value = "OFF" },
            { text = "Replace name", value = "REPLACE" },
            { text = "Prefix name", value = "PREFIX" },
        },
        get = function() return CommanderPlatesDB.ArenaNumbers end,
        set = function(v) CommanderPlatesDB.ArenaNumbers = v end,
        isEnabled = Enabled,
    })
    panel:AddSliderPair({
        label = "Glow Reach",
        tooltip = "How far the soft glow spreads from the bar, in pixels.",
        min = 4, max = 24, step = 1,
        get = function() return CommanderPlatesDB.TargetGlowSize end,
        set = function(v) CommanderPlatesDB.TargetGlowSize = v end,
        isEnabled = function() return BarsShown() and CommanderPlatesDB.TargetGlowStyle == "SOFT" end,
    }, {
        label = "Glow Strength",
        tooltip = "How bright the soft glow is at the bar's edge.",
        min = 0.2, max = 1.0, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderPlatesDB.TargetGlowAlpha end,
        set = function(v) CommanderPlatesDB.TargetGlowAlpha = v end,
        isEnabled = function() return Enabled() and CommanderPlatesDB.TargetGlowStyle == "SOFT" end,
    })
    panel:AddCheckboxPair({
        label = "Focus Glow",
        tooltip = "A glow around your focus target's health bar, in the focus colour.",
        get = function() return CommanderPlatesDB.FocusGlow end,
        set = function(v) CommanderPlatesDB.FocusGlow = v end,
        isEnabled = Enabled,
    }, {
        label = "Healer Cross",
        tooltip = "A healer icon beside the plate of any ENEMY the combat log has seen cast a healer's spell -- Greater Heal, Holy Light, Chain Heal, Regrowth and so on. Remembered for ten minutes.",
        get = function() return CommanderPlatesDB.HealerIcon end,
        set = function(v) CommanderPlatesDB.HealerIcon = v end,
        isEnabled = Enabled,
    })
    panel:AddCheckboxPair({
        label = "Class Icon: Enemies",
        tooltip = "The class icon beside an enemy player's health bar.",
        get = function() return CommanderPlatesDB.ClassIconEnemy end,
        set = function(v) CommanderPlatesDB.ClassIconEnemy = v end,
        isEnabled = Enabled,
    }, {
        label = "Class Icon: Friends",
        tooltip = "The class icon beside a friendly player's health bar.",
        get = function() return CommanderPlatesDB.ClassIconFriendly end,
        set = function(v) CommanderPlatesDB.ClassIconFriendly = v end,
        isEnabled = Enabled,
    })
    panel:AddSlider({
        label = "Healer Cross Size",
        tooltip = "Size of the healer icon.",
        min = 10, max = 32, step = 1,
        get = function() return CommanderPlatesDB.HealerIconSize end,
        set = function(v) CommanderPlatesDB.HealerIconSize = v end,
        isEnabled = function() return Enabled() and CommanderPlatesDB.HealerIcon end,
    })
end

local function AddTotemSection(panel)
    Section(panel, "Totems & Clutter",
        "A totem's plate says 'Searing Totem IV' over a sliver of bar. As an icon it says 'Grounding' from across the room, which is the thing you actually need to know. And some plates are better gone altogether.")
    panel:AddDropdown({
        label = "Totem Plates",
        tooltip = "'Icon' replaces the bar and name on a totem's plate with the totem's own spell icon, larger for the totems that change what you do next (Grounding, Tremor, Earthbind, Mana Tide, Windfury, cleansing totems).",
        options = {
            { text = "Blizzard's", value = "DEFAULT" },
            { text = "Icon", value = "ICON" },
        },
        get = function() return CommanderPlatesDB.TotemMode end,
        set = function(v) CommanderPlatesDB.TotemMode = v end,
        isEnabled = Enabled,
    })
    panel:AddCheckbox({
        label = "Hide Scenery Totems",
        tooltip = "Fade out the plates of totems that do not change your decisions -- Searing, Stoneskin, resistance and stat totems. Grounding, Tremor, Earthbind and their kind stay.",
        get = function() return CommanderPlatesDB.TotemHideLow end,
        set = function(v) CommanderPlatesDB.TotemHideLow = v end,
        isEnabled = Enabled,
    })
    panel:AddCheckbox({
        label = "Hide Listed NPCs",
        tooltip = "Fade out the plates of the NPCs named below entirely. The default is a hunter's Snake Trap -- up to ten plates at once, every one of them between you and the hunter.",
        get = function() return CommanderPlatesDB.HideNpcs end,
        set = function(v) CommanderPlatesDB.HideNpcs = v end,
        isEnabled = Enabled,
    })
    AddTextRow(panel, {
        label = "NPCs To Hide",
        tooltip = "NPC names, separated by commas, whose plates are faded out while 'Hide Listed NPCs' is on.",
        get = function() return CommanderPlatesDB.HideNpcList end,
        set = function(v) CommanderPlatesDB.HideNpcList = v end,
    })
    panel:AddSlider({
        label = "Totem Icon Size",
        tooltip = "Size of the icon for important totems. Scenery totems draw at two thirds of it.",
        min = 16, max = 48, step = 1,
        get = function() return CommanderPlatesDB.TotemIconSize end,
        set = function(v) CommanderPlatesDB.TotemIconSize = v end,
        isEnabled = function() return Enabled() and CommanderPlatesDB.TotemMode == "ICON" end,
    })
end

local function AddCastSection(panel)
    Section(panel, "Cast Bar",
        "Blizzard's cast bar, with the seconds left written on it and a loud border around the casts that matter -- control that is about to land, the big heals, and the two casts that empty a mana bar.")
    panel:AddCheckboxPair({
        label = "Seconds Left",
        tooltip = "Write the time remaining on the cast bar.",
        get = function() return CommanderPlatesDB.CastTimer end,
        set = function(v) CommanderPlatesDB.CastTimer = v end,
        isEnabled = Enabled,
    }, {
        label = "Emphasise Important Casts",
        tooltip = "Glow the cast bar for Polymorph, Fear, Cyclone, Greater Heal, Holy Light, Pyroblast, Drain Mana and their kind. Add your own below.",
        get = function() return CommanderPlatesDB.CastEmphasis end,
        set = function(v) CommanderPlatesDB.CastEmphasis = v end,
        isEnabled = Enabled,
    })
    panel:AddDropdown({
        label = "Cast Bar Colour",
        tooltip = "Colour of the cast bar's fill. 'Hostile red / friendly blue' makes an enemy's cast read as a threat and a friend's as a heal on the way; 'Unit's class' matches the health bar. Blizzard's is the yellow art.",
        options = Draw.ColorOptions({ { text = "Blizzard's", value = "DEFAULT" } }),
        width = 160,
        get = function() return CommanderPlatesDB.CastBarColor end,
        set = function(v) CommanderPlatesDB.CastBarColor = v end,
        isEnabled = BarsShown,
    })
    panel:AddDropdownPair({
        label = "Emphasis Colour",
        tooltip = "Colour of the emphasis border.",
        options = Draw.ColorOptions(),
        get = function() return CommanderPlatesDB.CastEmphasisColor end,
        set = function(v) CommanderPlatesDB.CastEmphasisColor = v end,
        isEnabled = function() return Enabled() and CommanderPlatesDB.CastEmphasis end,
    }, {
        label = "Cast Icon Size",
        tooltip = "Draw the spell's icon beside the cast bar at this size. 'Blizzard's' leaves the small default icon alone.",
        options = {
            { text = "Blizzard's", value = 0 },
            { text = "Small (16)", value = 16 },
            { text = "Medium (22)", value = 22 },
            { text = "Large (28)", value = 28 },
            { text = "Huge (36)", value = 36 },
        },
        get = function() return CommanderPlatesDB.CastIconSize end,
        set = function(v) CommanderPlatesDB.CastIconSize = v end,
        isEnabled = BarsShown,
    })
    AddTextRow(panel, {
        label = "Also Emphasise",
        tooltip = "Spell names, separated by commas, added to the emphasis list.",
        get = function() return CommanderPlatesDB.CastEmphasisExtra end,
        set = function(v) CommanderPlatesDB.CastEmphasisExtra = v end,
    })
    AddTextRow(panel, {
        label = "Do Not Emphasise",
        tooltip = "Spell names, separated by commas, removed from the default emphasis list.",
        get = function() return CommanderPlatesDB.CastEmphasisRemove end,
        set = function(v) CommanderPlatesDB.CastEmphasisRemove = v end,
    })
end

local function AddCVarSection(panel)
    Section(panel, "Blizzard's Nameplate CVars",
        "The settings that live in the game client rather than in this addon -- distance, target scale, non-target fade, stacking -- kept here as one profile. Changing a control writes the CVar at once (out of combat); 'Apply at login' re-asserts the whole set every session so a patch or another character cannot drift it.")
    panel:AddCheckbox({
        label = "Apply This Profile At Login",
        tooltip = "Write every CVar below at login. Off leaves the client's saved values alone unless you change a control.",
        get = function() return CommanderPlatesDB.CvApplyOnLogin end,
        set = function(v) CommanderPlatesDB.CvApplyOnLogin = v end,
        isEnabled = Enabled,
    })
    local sliders, bools = {}, {}
    for _, spec in ipairs(DATA.CVARS) do
        if spec.bool then bools[#bools + 1] = spec else sliders[#sliders + 1] = spec end
    end
    local function Missing(spec)
        return C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(spec.cvar) == nil
    end
    local function SliderOpts(spec)
        return {
            label = spec.label,
            tooltip = spec.tooltip .. (Missing(spec) and "\n\n|cffff6060This CVar does not exist on this client; the control does nothing.|r" or ""),
            min = spec.min, max = spec.max, step = spec.step,
            format = spec.step < 1 and function(v) return string.format("%.2f", v) end or nil,
            get = function() return CommanderPlatesDB[spec.key] end,
            set = function(v) CommanderPlatesDB[spec.key] = v; CommanderPlates_ApplyCVar(spec) end,
            isEnabled = function() return Enabled() and not Missing(spec) end,
        }
    end
    for i = 1, #sliders, 2 do
        panel:AddSliderPair(SliderOpts(sliders[i]), sliders[i + 1] and SliderOpts(sliders[i + 1]) or nil)
    end
    local function BoolOpts(spec)
        return {
            label = spec.label,
            tooltip = spec.tooltip .. (Missing(spec) and "\n\n|cffff6060This CVar does not exist on this client; the control does nothing.|r" or ""),
            get = function() return CommanderPlatesDB[spec.key] end,
            set = function(v) CommanderPlatesDB[spec.key] = v; CommanderPlates_ApplyCVar(spec) end,
            isEnabled = function() return Enabled() and not Missing(spec) end,
        }
    end
    for i = 1, #bools, 2 do
        panel:AddCheckboxPair(BoolOpts(bools[i]), bools[i + 1] and BoolOpts(bools[i + 1]) or nil)
    end
    panel:AddButtonRow({
        {
            label = "Apply Profile Now",
            tooltip = "Write every CVar above to the client now.",
            onClick = function() CommanderPlates_ApplyCVars(true) end,
            isEnabled = Enabled,
        },
        {
            label = "Read From Game",
            tooltip = "Copy the client's current values into this profile, so the controls show what the game is actually doing.",
            onClick = function() CommanderPlates_ReadCVars(); Notify() end,
            isEnabled = Enabled,
        },
    })
end

-- ---------------------------------------------------------------------------
-- The radial plate's sections
-- ---------------------------------------------------------------------------
local function RadialOn()
    return Enabled() and CommanderPlatesDB.PlateStyle == "RADIAL"
end

local CLOCK_OPTIONS = {
    { text = "Top", value = "TOP" },
    { text = "Top right", value = "TOP_RIGHT" },
    { text = "Right", value = "RIGHT" },
    { text = "Bottom right", value = "BOTTOM_RIGHT" },
    { text = "Bottom", value = "BOTTOM" },
    { text = "Bottom left", value = "BOTTOM_LEFT" },
    { text = "Left", value = "LEFT" },
    { text = "Top left", value = "TOP_LEFT" },
}

local function AddStyleSection(panel)
    panel:AddSection("Plate Style",
        "Two different plates. 'Classic' is Blizzard's bar with everything on this page layered onto it. 'Radial' replaces the bar with a disc -- the unit's face in the middle, health and the cast as arcs around it, auras in orbit -- the way the suite already draws the portraits on your own unit frames. Totems keep their own look in either style.", { plain = true })
    panel:AddDropdownPair({
        label = "Nameplate Style",
        tooltip = "Classic: Blizzard's own health bar, improved in place.\n\nRadial: every plate becomes a disc. The middle shows the unit's class (or portrait), and turns into the spell they are casting or the stun they are sitting in. The health bar is the ring around it; mana sits inside it; the cast sweeps around the outside with a spark on its head; debuffs and buffs orbit the ring. Target and focus glow, arena numbers, the healer cross, the value and Execute markers, cast emphasis and the whole aura filter all carry over.",
        options = {
            { text = "Classic bar", value = "CLASSIC" },
            { text = "Radial", value = "RADIAL" },
        },
        get = function() return CommanderPlatesDB.PlateStyle end,
        set = function(v) CommanderPlatesDB.PlateStyle = v end,
        isEnabled = Enabled,
    }, {
        label = "Radial Plates For",
        tooltip = "Which plates become discs. Everything else keeps the classic bar -- 'Enemy players' is the arena setting: the five plates that matter are discs, the pets and NPCs stay out of the way as bars.",
        options = {
            { text = "Everyone", value = "ALL" },
            { text = "Players", value = "PLAYERS" },
            { text = "Enemies", value = "ENEMIES" },
            { text = "Enemy players", value = "ENEMY_PLAYERS" },
        },
        get = function() return CommanderPlatesDB.RadialUnits end,
        set = function(v) CommanderPlatesDB.RadialUnits = v end,
        isEnabled = RadialOn,
    })
end

local function AddRadialRingsSection(panel)
    Section(panel, "Radial: The Rings",
        "From the middle out: power, health, the cast. Health runs round to twelve o'clock and drains clockwise as it drops, the empty part growing like a clock hand turning; the Execute and value markers above sit where that edge will be -- 20% at a little before ten. A hit leaves a pale trail that catches up a moment later, so you see what the last blow took.")
    panel:AddSliderPair({
        label = "Disc Size",
        tooltip = "Diameter of the disc, to the outside of the health ring. The cast ring and the orbit are drawn outside this.",
        min = 28, max = 80, step = 1,
        get = function() return CommanderPlatesDB.RadialSize end,
        set = function(v) CommanderPlatesDB.RadialSize = v end,
        isEnabled = RadialOn,
    }, {
        label = "Target Size",
        tooltip = "How much bigger your target's disc is drawn, on top of Blizzard's own target scale.",
        min = 1.0, max = 1.6, step = 0.05,
        format = function(v) return string.format("%.2fx", v) end,
        get = function() return CommanderPlatesDB.RadialTargetScale end,
        set = function(v) CommanderPlatesDB.RadialTargetScale = v end,
        isEnabled = RadialOn,
    })
    panel:AddDropdownPair({
        label = "Backdrop",
        tooltip = "A disc behind the whole plate, so the rings read against bright snow and a dark cave alike. 'Dark' is near-black; the tints are the unit's class or its standing, dimmed well down so the rings stay the brightest thing on it.",
        options = {
            { text = "Dark", value = "DARK" },
            { text = "Class tint", value = "CLASS" },
            { text = "Friend / foe tint", value = "REACTION" },
        },
        get = function() return CommanderPlatesDB.RadialBackdrop end,
        set = function(v) CommanderPlatesDB.RadialBackdrop = v end,
        isEnabled = function() return RadialOn() and (CommanderPlatesDB.RadialBackdropAlpha or 0) > 0 end,
    })
    panel:AddSliderPair({
        label = "Backdrop Opacity",
        tooltip = "How solid the backdrop is. 0 draws none.",
        min = 0, max = 1, step = 0.05,
        format = function(v) return v == 0 and "Off" or string.format("%d%%", v * 100) end,
        get = function() return CommanderPlatesDB.RadialBackdropAlpha end,
        set = function(v) CommanderPlatesDB.RadialBackdropAlpha = v end,
        isEnabled = RadialOn,
    }, {
        label = "Backdrop Size",
        tooltip = "How far the backdrop reaches past the outermost ring, in pixels. Larger gives the orbiting icons something to sit on too; negative pulls it in behind the rings, down to just the face.",
        min = -20, max = 40, step = 1,
        format = function(v) return (v > 0 and "+" or "") .. v .. " px" end,
        get = function() return CommanderPlatesDB.RadialBackdropSize end,
        set = function(v) CommanderPlatesDB.RadialBackdropSize = v end,
        isEnabled = function() return RadialOn() and (CommanderPlatesDB.RadialBackdropAlpha or 0) > 0 end,
    })
    local glowOptions = {}
    for _, key in ipairs(Radial.GLOW_ORDER) do
        glowOptions[#glowOptions + 1] = { text = Radial.GLOW_LABEL[key], value = key }
    end
    panel:AddDropdownPair({
        label = "Target Glow Style",
        tooltip = "The glow round your target's disc (and your focus's), in the colour and strength set under Target, Focus & Who Is Who.\n\nSoft Halo: a clean bloom.\nEmberflame: licking flame tongues.\nRunebound: a ring of glowing runes.\nArcane Orbit: twin rings with spiralling motes.\nRadiant Sunburst: rays of light.\nFrostshard: ice spikes and barbs.\nVoidsmoke: swirling shadow wisps.\nHoly Halo: a bright ring with cardinal flares.\nStar Sigil: an eight-pointed star of orbs.\nStormcall: crackling lightning.",
        options = glowOptions,
        width = 160,
        get = function() return CommanderPlatesDB.RadialGlowStyle end,
        set = function(v) CommanderPlatesDB.RadialGlowStyle = v end,
        isEnabled = function() return RadialOn() and (CommanderPlatesDB.TargetGlow or CommanderPlatesDB.FocusGlow) end,
    }, {
        label = "Glow Motion",
        tooltip = "Turn the glow slowly (the runes, the sigil and the storm come alive), breathe it in and out, or both. Only the target's and focus's discs ever carry a glow, so it costs next to nothing.",
        options = {
            { text = "Still", value = "NONE" },
            { text = "Spin", value = "SPIN" },
            { text = "Pulse", value = "PULSE" },
            { text = "Spin and pulse", value = "BOTH" },
        },
        get = function() return CommanderPlatesDB.RadialGlowMotion end,
        set = function(v) CommanderPlatesDB.RadialGlowMotion = v end,
        isEnabled = function() return RadialOn() and (CommanderPlatesDB.TargetGlow or CommanderPlatesDB.FocusGlow) end,
    })
    panel:AddSlider({
        label = "Glow Size",
        tooltip = "How far the glow reaches out from the disc.",
        min = 0.6, max = 1.6, step = 0.05,
        format = function(v) return string.format("%d%%", v * 100) end,
        get = function() return CommanderPlatesDB.RadialGlowSize end,
        set = function(v) CommanderPlatesDB.RadialGlowSize = v end,
        isEnabled = function() return RadialOn() and (CommanderPlatesDB.TargetGlow or CommanderPlatesDB.FocusGlow) end,
    })
    panel:AddCheckbox({
        label = "Backdrop Border",
        tooltip = "A thin dark line round the edge of the backdrop, so neighbouring plates separate cleanly.",
        get = function() return CommanderPlatesDB.RadialBackdropBorder end,
        set = function(v) CommanderPlatesDB.RadialBackdropBorder = v end,
        isEnabled = RadialOn,
    })
    panel:AddSliderPair({
        label = "Health Ring Thickness",
        tooltip = "Thickness of the health ring in pixels (the nearest of six weights of ring art).",
        min = 2, max = 12, step = 1,
        get = function() return CommanderPlatesDB.RadialHealthThickness end,
        set = function(v) CommanderPlatesDB.RadialHealthThickness = v end,
        isEnabled = RadialOn,
    }, {
        label = "Vertical Offset",
        tooltip = "Move the disc up or down from where Blizzard's bar would be.",
        min = -40, max = 40, step = 1,
        get = function() return CommanderPlatesDB.RadialOffsetY end,
        set = function(v) CommanderPlatesDB.RadialOffsetY = v end,
        isEnabled = RadialOn,
    })
    panel:AddDropdownPair({
        label = "Health Ring Colour",
        tooltip = "'Automatic' is the class on players (following the class-colour settings above) and hostile red / neutral yellow / friendly blue on NPCs. An NPC someone else has tagged is always grey.",
        options = Draw.ColorOptions({ { text = "Automatic", value = "AUTO" } }),
        get = function() return CommanderPlatesDB.RadialHealthColor end,
        set = function(v) CommanderPlatesDB.RadialHealthColor = v end,
        isEnabled = RadialOn,
    }, {
        label = "Low Health Colour",
        tooltip = "The colour the health ring turns below the Low Health threshold.",
        options = Draw.ColorOptions(),
        get = function() return CommanderPlatesDB.RadialLowHealthColor end,
        set = function(v) CommanderPlatesDB.RadialLowHealthColor = v end,
        isEnabled = function() return RadialOn() and (CommanderPlatesDB.RadialLowHealth or 0) > 0 end,
    })
    panel:AddSliderPair({
        label = "Low Health Threshold",
        tooltip = "Below this percentage the whole health ring changes colour -- the kill window, readable from across the room. 0 turns it off.",
        min = 0, max = 60, step = 1,
        format = function(v) return v == 0 and "Off" or (v .. "%") end,
        get = function() return CommanderPlatesDB.RadialLowHealth end,
        set = function(v) CommanderPlatesDB.RadialLowHealth = v end,
        isEnabled = RadialOn,
    }, {
        label = "Empty Ring Opacity",
        tooltip = "How visible the empty part of each ring is. 0 draws only what is filled.",
        min = 0, max = 1, step = 0.05,
        format = function(v) return string.format("%d%%", v * 100) end,
        get = function() return CommanderPlatesDB.RadialTrackAlpha end,
        set = function(v) CommanderPlatesDB.RadialTrackAlpha = v end,
        isEnabled = RadialOn,
    })
    panel:AddCheckboxPair({
        label = "Damage Trail",
        tooltip = "When health drops, the part that was lost stays as a pale arc for a moment and then drains away -- the size of the last hit, at a glance.",
        get = function() return CommanderPlatesDB.RadialHealthTrail end,
        set = function(v) CommanderPlatesDB.RadialHealthTrail = v end,
        isEnabled = RadialOn,
    }, {
        label = "Incoming Heals",
        tooltip = "Heals already being cast on the unit, drawn as a green arc running on past its health. Only where the client reports incoming heals, and only on units whose real health it knows.",
        get = function() return CommanderPlatesDB.RadialHealPrediction end,
        set = function(v) CommanderPlatesDB.RadialHealPrediction = v end,
        isEnabled = RadialOn,
    })
    panel:AddDropdownPair({
        label = "Power Ring",
        tooltip = "A thin ring inside the health ring for mana, rage or energy. 'Mana users' is the arena view: whose mana is running out.",
        options = {
            { text = "Off", value = "OFF" },
            { text = "Mana users", value = "MANA" },
            { text = "Players", value = "PLAYERS" },
            { text = "Everyone", value = "ALL" },
        },
        get = function() return CommanderPlatesDB.RadialPower end,
        set = function(v) CommanderPlatesDB.RadialPower = v end,
        isEnabled = RadialOn,
    }, {
        label = "Power Ring Thickness",
        tooltip = "Thickness of the power ring in pixels.",
        options = {
            { text = "Hairline (1)", value = 1 },
            { text = "Thin (2)", value = 2 },
            { text = "Medium (3)", value = 3 },
            { text = "Thick (4)", value = 4 },
        },
        get = function() return CommanderPlatesDB.RadialPowerThickness end,
        set = function(v) CommanderPlatesDB.RadialPowerThickness = v end,
        isEnabled = function() return RadialOn() and CommanderPlatesDB.RadialPower ~= "OFF" end,
    })
    panel:AddCheckboxPair({
        label = "Cast Ring",
        tooltip = "Sweep the cast around the outside of the disc: filling clockwise for a cast, draining for a channel.",
        get = function() return CommanderPlatesDB.RadialCastRing end,
        set = function(v) CommanderPlatesDB.RadialCastRing = v end,
        isEnabled = RadialOn,
    }, {
        label = "Spark On The Cast",
        tooltip = "A bright spark riding the head of the cast sweep, so where it is reads at a glance.",
        get = function() return CommanderPlatesDB.RadialCastSpark end,
        set = function(v) CommanderPlatesDB.RadialCastSpark = v end,
        isEnabled = function() return RadialOn() and CommanderPlatesDB.RadialCastRing end,
    })
    panel:AddDropdownPair({
        label = "Cast Colour",
        tooltip = "Colour of an ordinary cast. The casts on the emphasis list use the Emphasis Colour from the Cast Bar section, and light the warning halo while they last.",
        options = Draw.ColorOptions(),
        get = function() return CommanderPlatesDB.RadialCastColor end,
        set = function(v) CommanderPlatesDB.RadialCastColor = v end,
        isEnabled = function() return RadialOn() and CommanderPlatesDB.RadialCastRing end,
    }, {
        label = "Can't Interrupt Colour",
        tooltip = "Colour of a cast that cannot be interrupted, so you do not waste the kick.",
        options = Draw.ColorOptions(),
        get = function() return CommanderPlatesDB.RadialUninterruptibleColor end,
        set = function(v) CommanderPlatesDB.RadialUninterruptibleColor = v end,
        isEnabled = function() return RadialOn() and CommanderPlatesDB.RadialCastRing end,
    })
    panel:AddSliderPair({
        label = "Cast Ring Thickness",
        tooltip = "Thickness of the cast ring in pixels.",
        min = 2, max = 8, step = 1,
        get = function() return CommanderPlatesDB.RadialCastThickness end,
        set = function(v) CommanderPlatesDB.RadialCastThickness = v end,
        isEnabled = function() return RadialOn() and CommanderPlatesDB.RadialCastRing end,
    })
    panel:AddCheckboxPair({
        label = "Spell Name Under The Name",
        tooltip = "Write the spell being cast under the unit's name, in the cast's colour.",
        get = function() return CommanderPlatesDB.RadialCastName end,
        set = function(v) CommanderPlatesDB.RadialCastName = v end,
        isEnabled = RadialOn,
    }, {
        label = "Flash On Interrupt",
        tooltip = "A red burst on the ring and 'Interrupted' under the name when a cast is cut short -- your kick landed, or somebody else's did.",
        get = function() return CommanderPlatesDB.RadialInterruptFlash end,
        set = function(v) CommanderPlatesDB.RadialInterruptFlash = v end,
        isEnabled = RadialOn,
    })
    panel:AddCheckbox({
        label = "Who The Cast Is Aimed At",
        tooltip = "After the spell's name, the name of the caster's target in their class colour -- or YOU, in red, when the Polymorph is coming for you.",
        get = function() return CommanderPlatesDB.RadialCastTarget end,
        set = function(v) CommanderPlatesDB.RadialCastTarget = v end,
        isEnabled = function() return RadialOn() and CommanderPlatesDB.RadialCastName end,
    })
    panel:AddCheckbox({
        label = "Stack Plates By The Disc",
        tooltip = "The game keeps plates from overlapping by the size of the PLATE, which is still the bar's -- wide and flat. Discs are narrow and tall, so in a crowd they overlap. This sizes the game's plates to the disc (out of combat; it takes effect as plates reappear).\n\nIt applies to every enemy plate, and to friendly ones when friends are discs too -- so under a narrower 'Radial Plates For' the plates that stay bars get narrower bars.",
        get = function() return CommanderPlatesDB.RadialStacking end,
        set = function(v) CommanderPlatesDB.RadialStacking = v end,
        isEnabled = RadialOn,
    })
end

local function AddRadialFaceSection(panel)
    Section(panel, "Radial: The Face & The Text",
        "The middle of the disc is the most valuable pixel on the plate, so it changes with what matters most: the control the unit is sitting in beats the spell it is casting, which beats who it is. The number in it follows the same order -- seconds of the stun, seconds of the cast, then health.")
    panel:AddDropdownPair({
        label = "Face",
        tooltip = "What the middle shows when nothing more urgent is happening. 'Class' shows the class emblem on players and the portrait on NPCs.",
        options = {
            { text = "Class", value = "CLASS" },
            { text = "Portrait", value = "PORTRAIT" },
            { text = "Nothing", value = "NONE" },
        },
        get = function() return CommanderPlatesDB.RadialCoreArt end,
        set = function(v) CommanderPlatesDB.RadialCoreArt = v end,
        isEnabled = RadialOn,
    }, {
        label = "Number In The Middle",
        tooltip = "'Smart' is the arena number in an arena, the health percent once the unit is hurt, and nothing at full health. 'Health' is the real number (the combat-log estimate for enemy players).",
        options = {
            { text = "Smart", value = "SMART" },
            { text = "Health percent", value = "PERCENT" },
            { text = "Health value", value = "HEALTH" },
            { text = "Arena number", value = "ARENA" },
            { text = "Nothing", value = "NONE" },
        },
        get = function() return CommanderPlatesDB.RadialCoreText end,
        set = function(v) CommanderPlatesDB.RadialCoreText = v end,
        isEnabled = RadialOn,
    })
    panel:AddSlider({
        label = "Number Size",
        tooltip = "The font size of the number in the middle. Auto sizes it off the face, so it grows and shrinks with Plate Size; a fixed size stays put whatever the plate does. The DR bracket under it keeps its proportion to it.",
        min = 0, max = 24, step = 1,
        format = function(v) return v == 0 and "Auto" or string.format("%dpt", v) end,
        get = function() return CommanderPlatesDB.RadialCoreTextSize end,
        set = function(v) CommanderPlatesDB.RadialCoreTextSize = (v > 0 and v < 8) and 8 or v end,
        isEnabled = RadialOn,
    })
    panel:AddSlider({
        label = "Darken Face Under Text",
        tooltip = "How far the face darkens while a number is written across it. Every number on the plate also carries a black shadow, which holds its edges; this is what holds its middle -- a white 60 over a white-gold class icon has an outline and nothing inside it to tell from the picture. The face is only ever darkened while there is a number on it. 0 leaves the picture untouched.",
        min = 0, max = 0.8, step = 0.05,
        format = function(v) return v == 0 and "Off" or string.format("%d%%", v * 100 + 0.5) end,
        get = function() return CommanderPlatesDB.RadialTextShade end,
        set = function(v) CommanderPlatesDB.RadialTextShade = v end,
        isEnabled = RadialOn,
    })
    panel:AddCheckboxPair({
        label = "Casting: Spell Becomes The Face",
        tooltip = "While the unit casts, the middle shows the spell's icon and the seconds left, the way your own portrait does with Commander Casting.",
        get = function() return CommanderPlatesDB.RadialCoreCast end,
        set = function(v) CommanderPlatesDB.RadialCoreCast = v end,
        isEnabled = RadialOn,
    }, {
        label = "Controlled: Control Becomes The Face",
        tooltip = "The big 'loose control' icon moves into the middle of the disc: the stun or sheep with its countdown sweeping over it, the ring round it in the control's colour, and the DR bracket under the timer. Off floats the big icon above the disc instead.",
        get = function() return CommanderPlatesDB.RadialCoreCC end,
        set = function(v) CommanderPlatesDB.RadialCoreCC = v end,
        isEnabled = RadialOn,
    })
    panel:AddDropdownPair({
        label = "Name",
        tooltip = "Where the name goes. Name text, colour and arena numbers follow the Health Bars & Names settings above.",
        options = {
            { text = "Below the disc", value = "BELOW" },
            { text = "Above the disc", value = "ABOVE" },
            { text = "Hidden", value = "NONE" },
        },
        get = function() return CommanderPlatesDB.RadialName end,
        set = function(v) CommanderPlatesDB.RadialName = v end,
        isEnabled = RadialOn,
    }, {
        label = "Rim Colour",
        tooltip = "The thin ring around the face. It turns gold for elites and silver for rares (below), takes the colour of a control the unit is in, and brightens under the mouse.",
        options = Draw.ColorOptions({ { text = "Off (black)", value = "OFF" } }),
        get = function() return CommanderPlatesDB.RadialRimColor end,
        set = function(v) CommanderPlatesDB.RadialRimColor = v end,
        isEnabled = RadialOn,
    })
    panel:AddSliderPair({
        label = "Name Size",
        tooltip = "Font size of the name.",
        min = 7, max = 16, step = 1,
        get = function() return CommanderPlatesDB.RadialNameSize end,
        set = function(v) CommanderPlatesDB.RadialNameSize = v end,
        isEnabled = function() return RadialOn() and CommanderPlatesDB.RadialName ~= "NONE" end,
    }, {
        label = "Name Width",
        tooltip = "How wide the name may run before it is cut short.",
        min = 50, max = 180, step = 2,
        get = function() return CommanderPlatesDB.RadialNameWidth end,
        set = function(v) CommanderPlatesDB.RadialNameWidth = v end,
        isEnabled = function() return RadialOn() and CommanderPlatesDB.RadialName ~= "NONE" end,
    })
    panel:AddCheckboxPair({
        label = "Elite & Rare Rim",
        tooltip = "Gold rim on elites and bosses, silver on rares.",
        get = function() return CommanderPlatesDB.RadialEliteRim end,
        set = function(v) CommanderPlatesDB.RadialEliteRim = v end,
        isEnabled = RadialOn,
    }, {
        label = "Mouseover Highlight",
        tooltip = "Brighten the rim of the disc under the mouse.",
        get = function() return CommanderPlatesDB.RadialMouseover end,
        set = function(v) CommanderPlatesDB.RadialMouseover = v end,
        isEnabled = RadialOn,
    })
    panel:AddCheckboxPair({
        label = "NPC Level",
        tooltip = "The level on the rim of NPC discs, coloured by difficulty the way the target frame colours it, with a + for elites and ?? for a boss.",
        get = function() return CommanderPlatesDB.RadialLevel end,
        set = function(v) CommanderPlatesDB.RadialLevel = v end,
        isEnabled = RadialOn,
    }, {
        label = "Raid Target Marker",
        tooltip = "The skull, cross and the rest, on the rim at seven o'clock.",
        get = function() return CommanderPlatesDB.RadialRaidMarker end,
        set = function(v) CommanderPlatesDB.RadialRaidMarker = v end,
        isEnabled = RadialOn,
    })
    panel:AddCheckbox({
        label = "Arena Trinket",
        tooltip = "An arena enemy's PvP trinket on the rim at twelve o'clock, read from the client itself: a green rim when it is ready, greyed out with its cooldown sweeping once it has been used. The one enemy cooldown the game will tell you about from the first second.",
        get = function() return CommanderPlatesDB.RadialTrinket end,
        set = function(v) CommanderPlatesDB.RadialTrinket = v end,
        isEnabled = RadialOn,
    })
    panel:AddDropdownPair({
        label = "Ring On Whoever Targets You",
        tooltip = "A thin ring round the disc of every enemy whose target is you: the rogue about to open on you in a battleground, the arena team swapping to you before the first hit lands.",
        options = {
            { text = "Off", value = "OFF" },
            { text = "Enemy players", value = "ENEMY_PLAYERS" },
            { text = "All enemies", value = "ENEMIES" },
        },
        get = function() return CommanderPlatesDB.RadialTargetingYou end,
        set = function(v) CommanderPlatesDB.RadialTargetingYou = v end,
        isEnabled = RadialOn,
    }, {
        label = "Targets-You Colour",
        tooltip = "Colour of that ring.",
        options = Draw.ColorOptions(),
        get = function() return CommanderPlatesDB.RadialTargetingYouColor end,
        set = function(v) CommanderPlatesDB.RadialTargetingYouColor = v end,
        isEnabled = function() return RadialOn() and CommanderPlatesDB.RadialTargetingYou ~= "OFF" end,
    })
end

local function AddRadialOrbitSection(panel)
    Section(panel, "Radial: The Orbit",
        "The buffs and debuffs the filters above choose, as round icons circling the disc -- debuffs in one arc, buffs in another. An arc that fills up starts a second ring further out rather than running all the way round.")
    panel:AddDropdownPair({
        label = "Debuffs Orbit",
        tooltip = "Where the debuff arc is centred.",
        options = CLOCK_OPTIONS,
        get = function() return CommanderPlatesDB.RadialDebuffArc end,
        set = function(v) CommanderPlatesDB.RadialDebuffArc = v end,
        isEnabled = RadialOn,
    }, {
        label = "Buffs Orbit",
        tooltip = "Where the buff arc is centred.",
        options = CLOCK_OPTIONS,
        get = function() return CommanderPlatesDB.RadialBuffArc end,
        set = function(v) CommanderPlatesDB.RadialBuffArc = v end,
        isEnabled = RadialOn,
    })
    local GROW_OPTIONS = {
        { text = "Fan out both ways", value = "CENTER" },
        { text = "Clockwise from it", value = "CLOCKWISE" },
        { text = "Counter-clockwise from it", value = "COUNTERCLOCKWISE" },
    }
    panel:AddDropdownPair({
        label = "Debuffs Grow",
        tooltip = "How the debuffs spread from their clock position: fanned out evenly either side of it, or starting on it and running round one way (the first debuff always sits exactly on the position).",
        options = GROW_OPTIONS,
        get = function() return CommanderPlatesDB.RadialDebuffGrow end,
        set = function(v) CommanderPlatesDB.RadialDebuffGrow = v end,
        isEnabled = RadialOn,
    }, {
        label = "Buffs Grow",
        tooltip = "How the buffs spread from their clock position.",
        options = GROW_OPTIONS,
        get = function() return CommanderPlatesDB.RadialBuffGrow end,
        set = function(v) CommanderPlatesDB.RadialBuffGrow = v end,
        isEnabled = RadialOn,
    })
    panel:AddSliderPair({
        label = "Orbit Icon Size",
        tooltip = "Size of the aura icons in orbit.",
        min = 10, max = 30, step = 1,
        get = function() return CommanderPlatesDB.RadialAuraSize end,
        set = function(v) CommanderPlatesDB.RadialAuraSize = v end,
        isEnabled = RadialOn,
    }, {
        label = "Orbit Distance",
        tooltip = "Gap between the outermost ring and the orbit.",
        min = 0, max = 12, step = 1,
        get = function() return CommanderPlatesDB.RadialAuraGap end,
        set = function(v) CommanderPlatesDB.RadialAuraGap = v end,
        isEnabled = RadialOn,
    })
    panel:AddSliderPair({
        label = "Orbit Span",
        tooltip = "How far round the disc one arc of icons may run, in degrees, before the next icons start a second orbit further out.",
        min = 60, max = 360, step = 10,
        format = function(v) return v .. "\194\176" end,
        get = function() return CommanderPlatesDB.RadialAuraArc end,
        set = function(v) CommanderPlatesDB.RadialAuraArc = v end,
        isEnabled = RadialOn,
    })
    panel:AddCheckboxPair({
        label = "Round Icons",
        tooltip = "Circle-cut aura icons with a round countdown sweep. Off keeps the square icons of the classic plate.",
        get = function() return CommanderPlatesDB.RadialRoundAuras end,
        set = function(v) CommanderPlatesDB.RadialRoundAuras = v end,
        isEnabled = RadialOn,
    }, {
        label = "Combo Points",
        tooltip = "Your combo points as pips around the bottom of your target's disc (rogues and druids).",
        get = function() return CommanderPlatesDB.RadialComboPoints end,
        set = function(v) CommanderPlatesDB.RadialComboPoints = v end,
        isEnabled = RadialOn,
    })
    panel:AddDropdown({
        label = "Threat Halo",
        tooltip = "A warning halo on NPC discs. 'Damage / healer': orange as the mob is about to turn on you, red once it has. 'Tank': red on anything you are not holding, orange on what is slipping.",
        options = {
            { text = "Off", value = "OFF" },
            { text = "Damage / healer", value = "DPS" },
            { text = "Tank", value = "TANK" },
        },
        get = function() return CommanderPlatesDB.RadialThreat end,
        set = function(v) CommanderPlatesDB.RadialThreat = v end,
        isEnabled = RadialOn,
    })
    panel:AddDropdownPair({
        label = "Diminishing Returns",
        tooltip = "Every control category open on the unit, as a small icon in its own arc: the spell that opened it, what the NEXT one would do across it (\194\189 half, \194\188 quarter, X immune), and the fifteen seconds to reset sweeping away once the control is gone. Needs Commander Diminish, and follows its zone settings (by default: arenas and battlegrounds).",
        options = {
            { text = "Off", value = "OFF" },
            { text = "Enemies", value = "ENEMIES" },
            { text = "Enemy players", value = "ENEMY_PLAYERS" },
            { text = "Everyone", value = "ALL" },
        },
        get = function() return CommanderPlatesDB.RadialDr end,
        set = function(v) CommanderPlatesDB.RadialDr = v end,
        isEnabled = RadialOn,
    }, {
        label = "Diminishing Returns Orbit",
        tooltip = "Where the diminishing-returns arc is centred.",
        options = CLOCK_OPTIONS,
        get = function() return CommanderPlatesDB.RadialDrArc end,
        set = function(v) CommanderPlatesDB.RadialDrArc = v end,
        isEnabled = function() return RadialOn() and CommanderPlatesDB.RadialDr ~= "OFF" end,
    })
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Plates",
        title = "Plates",
        addonName = "Commander_Plates",
        description = "Blizzard's own nameplates, made fit for an arena: class-coloured health bars on friends and enemies, your buffs and debuffs tracked on both, one big icon for the control a unit is sitting in, and a taller clickable area under exactly the same-looking plate. Everything is a layer on the default plate -- turn the module off and the plate underneath is untouched.",
        event = COMMANDER_PLATES_EVENTS.UPDATE,
        slash = { "/cplates", "/cpl" },
        slashHandlers = {
            radial = function()
                CommanderPlatesDB.PlateStyle = "RADIAL"; Notify()
                print("Commander Plates: radial plates.")
            end,
            classic = function()
                CommanderPlatesDB.PlateStyle = "CLASSIC"; Notify()
                print("Commander Plates: classic bar plates.")
            end,
            cvars = function() CommanderPlates_ApplyCVars(true) end,
            healers = function() CommanderPlates_PrintHealers() end,
        },
    })

    panel:AddCheckbox({
        label = "Enable Commander Plates",
        tooltip = "Turn every layer this module adds on or off. Off restores Blizzard's plates exactly as they were.",
        get = function() return CommanderPlatesDB.Enable end,
        set = function(v) CommanderPlatesDB.Enable = v end,
    })
    -- Always on the page: the one choice that shapes everything else, what it
    -- looks like, and the way to find any other option
    AddStyleSection(panel)
    AddPreviewRow(panel)
    panel:AddSearchBox({ placeholder = "Search plate options..." })

    -- Everything else folds. The disc's own sections lead while plates are
    -- discs (and are gone while they are bars); then what applies to both,
    -- most-used first; the client's CVars last
    AddRadialRingsSection(panel)
    AddRadialFaceSection(panel)
    AddRadialOrbitSection(panel)
    AddBarsSection(panel)
    AddAuraFilterSection(panel)
    AddAuraLookSection(panel)
    AddCcSection(panel)
    AddIdentitySection(panel)
    AddCastSection(panel)
    AddTotemSection(panel)
    AddHitBoxSection(panel)
    AddCVarSection(panel)

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addon)
    if event == "ADDON_LOADED" and addon == "Commander_Plates" then
        CommanderPlatesDB = CommanderPlatesDB or {}
        local db = CommanderPlatesDB
        if (db.Rev or 1) < 2 then
            -- 1.0: name colour was a pair of booleans; the big icon sat over
            -- the bar, which hid the health it was drawn to explain
            if db.FriendlyNameClassColor ~= nil then
                db.FriendlyNameColor = db.FriendlyNameClassColor and "CLASS" or "DEFAULT"
            end
            if db.EnemyNameClassColor ~= nil then
                db.EnemyNameColor = db.EnemyNameClassColor and "CLASS" or "DEFAULT"
            end
            db.FriendlyNameClassColor, db.EnemyNameClassColor = nil, nil
            if db.CcAnchor == "CENTER" then db.CcAnchor = "ABOVE" end
        end
        db.Rev = SETTINGS_REV
        Commander.UI.ApplyDefaults(db, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)
