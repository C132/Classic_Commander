-- Commander Casting smoke (luajit) — verification for the radial cast bars
-- drawn around the player and target portraits (2.2.0) and the melee swing ring
-- with its seal twist assist (2.3.0). Loads the REAL Commander_Events framework
-- plus all three Casting files under a WoW mock, drives casts and swings
-- through the same events the client sends, and asserts the ring geometry, the
-- sweeps, the coloring, the twist window, and the Blizzard-bar hiding.
--
-- Mock modeled on Commander_Afflictions/Harness, extended with the Cooldown
-- surface (SetCooldown / SetReverse / SetSwipeTexture / SetSwipeColor), the
-- cast-info API, the combat log and UnitAttackSpeed the swing ring reads its
-- clock from, and the unit frames the rings anchor to.
--
--   luajit Commander_Casting/Harness/casting_smoke.lua

-- Resolve the AddOns root from this file, so the harness runs from a worktree
-- and from any working directory
local SOURCE = debug.getinfo(1, "S").source:sub(2)
local ADDONS = SOURCE:match("^(.*)Commander_Casting[/\\]Harness[/\\][^/\\]+$")
if not ADDONS or ADDONS == "" then
    ADDONS = "."
else
    ADDONS = ADDONS:gsub("[/\\]$", "")
end

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end

-- ===========================================================================
-- WoW mock
-- ===========================================================================

local now = 1000
function GetTime() return now end
function GetBuildInfo() return "2.5.6", "68502", "Jul 7 2026", 20506 end
function GetNetStats() return 0, 0, 40, 120 end     -- 120ms world latency

local printLog = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    printLog[#printLog + 1] = table.concat(parts, " ")
end

local harnessFailedErrors = {}
function geterrorhandler()
    return function(err) harnessFailedErrors[#harnessFailedErrors + 1] = tostring(err) end
end

local NUMERIC_GETTERS = {
    GetScale = 1, GetEffectiveScale = 1, GetFrameLevel = 2,
    GetLeft = 0, GetBottom = 0, GetTop = 0, GetRight = 0,
    GetStringWidth = 10, GetID = 1, GetNumPoints = 1,
}

local function IsMethodName(key)
    return type(key) == "string" and (key:match("^Set") or key:match("^Get") or key:match("^Is")
        or key:match("^Can") or key:match("^Enable") or key:match("^Disable")
        or key:match("^Register") or key:match("^Unregister") or key:match("^Hook")
        or key:match("^Clear") or key:match("^Create") or key:match("^Show")
        or key:match("^Hide") or key:match("^Raise") or key:match("^Start")
        or key:match("^Stop") or key:match("^Add") or key:match("^Lock"))
end

local eventRegistry = {}
local allRegions = {}       -- every texture and font string, in creation order
local NewWidget

-- Widget methods the assertions read back. Everything else falls through to a
-- generated no-op, exactly as the other suite harnesses do.
local RECORDERS = {
    SetPoint = function(s, point, rel, relPoint, x, y)
        s.__points = s.__points or {}
        s.__points[#s.__points + 1] = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
    end,
    ClearAllPoints = function(s) s.__points = {} end,
    SetSize = function(s, w, h) s.__w, s.__h = w, h end,
    GetWidth = function(s) return s.__w or 0 end,
    GetHeight = function(s) return s.__h or 0 end,
    SetText = function(s, text) s.__text = text end,
    GetText = function(s) return s.__text end,
    Show = function(s) s.__shown = true end,
    Hide = function(s) s.__shown = false end,
    SetShown = function(s, shown) s.__shown = not not shown end,
    IsShown = function(s) return s.__shown end,
    IsVisible = function(s) return s.__shown end,
    SetAlpha = function(s, a) s.__alpha = a end,
    GetAlpha = function(s) return s.__alpha or 1 end,
    GetFont = function() return "Fonts\\FRIZQT__.TTF", 10, "" end,
    SetTexture = function(s, tex) s.__texture = tex end,
    GetTexture = function(s) return s.__texture end,
    GetParent = function(s) return s.__parent end,
    GetDrawLayer = function(s) return s.__layer or "ARTWORK", s.__sublevel or 0 end,
    SetVertexColor = function(s, r, g, b, a) s.__color = { r, g, b, a } end,
    SetRotation = function(s, radians) s.__rotation = radians end,
    -- Cooldown
    SetCooldown = function(s, start, duration) s.__cooldown = { start = start, duration = duration } end,
    Clear = function(s) s.__cooldown = nil end,
    SetReverse = function(s, value) s.__reverse = not not value end,
    SetSwipeTexture = function(s, tex) s.__swipeTexture = tex end,
    SetSwipeColor = function(s, r, g, b, a) s.__swipeColor = { r, g, b, a } end,
    SetDrawEdge = function(s, value) s.__drawEdge = not not value end,
}

local WidgetMT = {}
WidgetMT.__index = function(self, key)
    if type(key) ~= "string" then return nil end
    local recorder = RECORDERS[key]
    if recorder then rawset(self, key, recorder); return recorder end
    if NUMERIC_GETTERS[key] ~= nil then
        local value = NUMERIC_GETTERS[key]
        local fn = function() return value end
        rawset(self, key, fn); return fn
    end
    if key == "CreateTexture" or key == "CreateMaskTexture" or key == "CreateFontString" then
        local kind = key == "CreateFontString" and "FontString" or "Texture"
        -- Layer and sublevel are recorded: where a region sits in the parent's
        -- draw order is the whole question for anything laid over a portrait
        local fn = function(s, _, layer, _, sublevel)
            local t = NewWidget(kind); t.__parent = s
            t.__layer, t.__sublevel = layer, sublevel or 0
            allRegions[#allRegions + 1] = t
            return t
        end
        rawset(self, key, fn); return fn
    end
    if key == "SetScript" then
        local fn = function(s, name, handler) s.__scripts[name] = handler end
        rawset(self, key, fn); return fn
    end
    if key == "HookScript" then
        local fn = function(s, name, handler)
            s.__hooks[name] = s.__hooks[name] or {}
            table.insert(s.__hooks[name], handler)
        end
        rawset(self, key, fn); return fn
    end
    if key == "GetScript" then
        local fn = function(s, name) return s.__scripts[name] end
        rawset(self, key, fn); return fn
    end
    if key == "RegisterEvent" then
        local fn = function(s, event)
            eventRegistry[event] = eventRegistry[event] or {}
            table.insert(eventRegistry[event], s)
        end
        rawset(self, key, fn); return fn
    end
    if key == "UnregisterAllEvents" then
        -- Real, not a generated no-op: the swing ring drops the combat log
        -- entirely when it is switched off, and that is worth asserting
        local fn = function(s)
            for _, list in pairs(eventRegistry) do
                for i = #list, 1, -1 do
                    if list[i] == s then table.remove(list, i) end
                end
            end
        end
        rawset(self, key, fn); return fn
    end
    if key == "UnregisterEvent" then
        local fn = function(s, event)
            local list = eventRegistry[event]
            if list then
                for i = #list, 1, -1 do
                    if list[i] == s then table.remove(list, i) end
                end
            end
        end
        rawset(self, key, fn); return fn
    end
    if IsMethodName(key) then
        local fn = function() end
        rawset(self, key, fn); return fn
    end
    return nil
end

NewWidget = function(kind, name)
    return setmetatable({ __kind = kind, __name = name, __scripts = {}, __hooks = {}, __shown = true },
        WidgetMT)
end

local allFrames = {}
function CreateFrame(frameType, name, parent, template)
    local f = NewWidget(frameType, name)
    f.__template = template
    f.__parent = parent
    if frameType == "CheckButton" or (template and template:find("CheckButton")) then
        f.Text = NewWidget("FontString")
    end
    if name then _G[name] = f end
    allFrames[#allFrames + 1] = f
    return f
end

-- Fire a frame's OnShow, hooks included -- the Blizzard bars are suppressed by
-- an OnShow hook, so re-showing one has to run the hook the client would
local function FireShow(frame)
    frame:Show()
    local hooks = frame.__hooks.OnShow
    if hooks then
        for _, handler in ipairs(hooks) do handler(frame) end
    end
end

UIParent = NewWidget("Frame", "UIParent")
WorldFrame = NewWidget("Frame", "WorldFrame")
GameTooltip = NewWidget("GameTooltip", "GameTooltip")
UISpecialFrames = {}
tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack

GameFontNormal = NewWidget("Font")
GameFontNormalLarge = NewWidget("Font")
GameFontNormalHuge = NewWidget("Font")
GameFontHighlight = NewWidget("Font")
GameFontHighlightSmall = NewWidget("Font")
GameFontDisableSmall = NewWidget("Font")
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

SOUNDKIT = {
    IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2,
    IG_CHARACTER_INFO_TAB = 841,
}
local soundsPlayed = {}
function PlaySound(kit) soundsPlayed[#soundsPlayed + 1] = kit end
BACKDROP_SLIDER_8_8 = {}

local categories = {}
Settings = {
    RegisterCanvasLayoutCategory = function(panel)
        local cat = { __panel = panel, GetID = function() return #categories + 1 end }
        categories[#categories + 1] = cat; return cat
    end,
    RegisterCanvasLayoutSubcategory = function(parent, panel)
        local cat = { __panel = panel, GetID = function() return #categories + 1 end }
        categories[#categories + 1] = cat; return cat
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
}
C_AddOns = { GetAddOnMetadata = function() return "2.2.0" end }
C_Timer = {
    After = function() end,
    NewTicker = function()
        local t = { cancelled = false }
        t.Cancel = function(self) self.cancelled = true end
        return t
    end,
}

local menuCaptured = {}
local dropdownInits = {}
function UIDropDownMenu_Initialize(frame, fn) dropdownInits[frame] = fn end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info) menuCaptured[#menuCaptured + 1] = info end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetSelectedValue() end
function UIDropDownMenu_SetText() end
function UIDropDownMenu_EnableDropDown() end
function UIDropDownMenu_DisableDropDown() end
function ToggleDropDownMenu(level, value, frame)
    menuCaptured = {}
    local init = dropdownInits[frame]
    if init then init(frame) end
end

SlashCmdList = {}

RAID_CLASS_COLORS = { MAGE = { r = 0.41, g = 0.80, b = 0.94 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
CLASS_ICON_TCOORDS = {}

-- ---- Units -----------------------------------------------------------------

local units = {
    player = { class = "MAGE", exists = true, isPlayer = true, attackable = false, friend = true },
    target = { class = "WARRIOR", exists = false, isPlayer = true, attackable = true, friend = false },
}
local casts = {}     -- unit -> { name, start, finish, channel }

function UnitExists(unit) return units[unit] and units[unit].exists or false end
function UnitIsPlayer(unit) return units[unit] and units[unit].isPlayer or false end
function UnitCanAttack(_, unit) return units[unit] and units[unit].attackable or false end
function UnitIsFriend(_, unit) return units[unit] and units[unit].friend or false end
function UnitClass(unit)
    local u = units[unit]
    if not u then return nil end
    return u.class, u.class
end

-- A cast reports its art unless the fixture says it has none
local function CastIcon(cast)
    if cast.noIcon then return nil end
    return cast.icon or "Interface\\Icons\\Spell_Test"
end

function UnitCastingInfo(unit)
    local cast = casts[unit]
    if not cast or cast.channel then return nil end
    return cast.name, cast.name, CastIcon(cast), cast.start * 1000, cast.finish * 1000, false, nil, nil
end

function UnitChannelInfo(unit)
    local cast = casts[unit]
    if not cast or not cast.channel then return nil end
    return cast.name, cast.name, CastIcon(cast), cast.start * 1000, cast.finish * 1000, false, nil
end

function GetSpellCooldown() return now, 1.5, 1 end

-- ---- The melee swing, the combat log, and the player's seal ----------------

function UnitGUID(unit) return unit == "player" and "Player-1-AAAA" or "Creature-0-BBBB" end

-- Main hand and off hand, the two returns the swing ring reads its clock from
local attackSpeed = { main = 2.4, off = nil }
function UnitAttackSpeed() return attackSpeed.main, attackSpeed.off end

-- Names for the seal ids Commander_Casting resolves; anything else is unknown,
-- so a wrong id in that list would show up as a seal that never registers
local SPELL_NAMES = {
    [20375] = "Seal of Command", [31892] = "Seal of Blood",
    [31801] = "Seal of Vengeance", [21082] = "Seal of the Crusader",
    [21084] = "Seal of Righteousness", [20164] = "Seal of Justice",
    [20165] = "Seal of Light", [20166] = "Seal of Wisdom",
}
function GetSpellInfo(id) return SPELL_NAMES[id] end

local playerBuffs = {}      -- list of { name = ... }
C_UnitAuras = {
    GetBuffDataByIndex = function(unit, index)
        if unit ~= "player" then return nil end
        return playerBuffs[index]
    end,
}

-- CLEU is read out of the client's own accessor rather than passed as event
-- arguments, so the fixture is staged the same way
local clue = {}
function CombatLogGetCurrentEventInfo() return unpack(clue, 1, 21) end

-- A swing of the player's, in the modern CLEU layout this client runs:
-- isOffHand rides argument 21 on SWING_DAMAGE and argument 13 on SWING_MISSED.
local function PlayerSwing(offHand, missed, source)
    clue = {}
    clue[1] = now
    clue[2] = missed and "SWING_MISSED" or "SWING_DAMAGE"
    clue[4] = source or "Player-1-AAAA"
    if missed then
        clue[12] = "DODGE"
        clue[13] = offHand or nil
    else
        clue[12] = 500
        clue[21] = offHand or nil
    end
end

-- ---- Blizzard unit frames the rings hang off -------------------------------

-- Both portraits are regions of the unit frame itself, at the layer Blizzard
-- puts them on; the frame's metal and its level number are drawn by CHILD
-- frames above that. Modeled here because where the spell icon lands in this
-- stack is the difference between covering a face and covering the level.
PlayerFrame = NewWidget("Button", "PlayerFrame")
PlayerPortrait = NewWidget("Texture", "PlayerPortrait")
PlayerPortrait.__parent, PlayerPortrait.__layer = PlayerFrame, "ARTWORK"
PlayerPortrait:SetSize(64, 64)

TargetFrame = NewWidget("Button", "TargetFrame")
TargetFramePortrait = NewWidget("Texture", "TargetFramePortrait")
TargetFramePortrait.__parent, TargetFramePortrait.__layer = TargetFrame, "BORDER"
TargetFramePortrait:SetSize(64, 64)
TargetFrameTextureFrame = NewWidget("Frame", "TargetFrameTextureFrame")

PlayerCastingBarFrame = NewWidget("StatusBar", "PlayerCastingBarFrame")
TargetFrameSpellBar = NewWidget("StatusBar", "TargetFrameSpellBar")
TargetFrame.spellbar = TargetFrameSpellBar

-- ===========================================================================
-- Load the real framework + addon
-- ===========================================================================

local function Load(path)
    local chunk = assert(loadfile(path))
    chunk()
end

local function Fire(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    local snap = {}
    for i, f in ipairs(list) do snap[i] = f end
    for _, frame in ipairs(snap) do
        local handler = frame.__scripts.OnEvent
        if handler then handler(frame, event, ...) end
    end
end

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
Load(ADDONS .. "/Commander_Casting/CommanderCastingDB.lua")
Load(ADDONS .. "/Commander_Casting/CommanderCasting.lua")
Load(ADDONS .. "/Commander_Casting/CommanderCastingPortrait.lua")

Fire("ADDON_LOADED", "Commander_Casting")
Fire("PLAYER_LOGIN")
CHECK(#harnessFailedErrors == 0, "login clean", harnessFailedErrors[1])

local DB = CommanderCastingDB
CHECK(DB.EnablePortraitRings == true, "portrait rings default on")
CHECK(DB.PlayerRingScale == 1.14, "player ring scale default", DB.PlayerRingScale)
CHECK(DB.HidePlayerCastBar == false, "Blizzard bars are left alone by default")

local playerRing = _G.CommanderCastingPlayerRing
local targetRing = _G.CommanderCastingTargetRing
CHECK(playerRing ~= nil, "player ring frame built")
CHECK(targetRing ~= nil, "target ring frame built")

local function Redraw() Commander.Notify(COMMANDER_CASTING_EVENTS.UPDATE) end

-- Child FRAMES of a ring holder, in creation order: the cast arc, then the
-- player's extra sweeps (cooldown, swing), then the overlay everything that
-- must not be eaten by a sweep is drawn on
local function ChildrenOf(holder)
    local kids = {}
    for _, f in ipairs(allFrames) do
        if f.__parent == holder then kids[#kids + 1] = f end
    end
    return kids
end

-- By kind rather than by index: the extras are optional and the overlay is
-- always the one frame among them that is not a sweep
local function OverlayOf(holder)
    for _, f in ipairs(ChildrenOf(holder)) do
        if f.__kind == "Frame" then return f end
    end
end

local playerArc = ChildrenOf(playerRing)[1]
local targetArc = ChildrenOf(targetRing)[1]
CHECK(playerArc and playerArc.__kind == "Cooldown", "player arc is a Cooldown frame",
    playerArc and playerArc.__kind)

-- ===========================================================================
-- Spell school parsing is shared by the glow and the rings
-- ===========================================================================

CHECK(CommanderCasting_SchoolOf("Frostbolt") == "Frost", "school: Frostbolt")
CHECK(CommanderCasting_SchoolOf("Shadow Bolt") == "Shadow",
    "school: a spell naming its own school beats a greedy keyword (bolt)")
CHECK(CommanderCasting_SchoolOf("Fire Blast") == "Fire", "school: Fire Blast is not Shadow")
CHECK(CommanderCasting_SchoolOf("Greater Heal") == "Holy", "school: keyword pass still runs")
CHECK(CommanderCasting_SchoolOf("Blizzard") == "Frost", "school: keyword with no school in the name")
CHECK(CommanderCasting_SchoolOf("Mind Blast") == "Shadow", "school: Mind Blast")
CHECK(CommanderCasting_SchoolOf("Chain Lightning") == "Nature", "school: Chain Lightning")
CHECK(CommanderCasting_SchoolOf("Corruption") == "Unknown", "school: no keyword")
CHECK(CommanderCasting_SchoolOf(nil) == "Unknown", "school: nil name is safe")

-- ===========================================================================
-- The player ring
-- ===========================================================================

CHECK(playerRing.__shown == false, "idle: no cast, no ring")

casts.player = { name = "Frostbolt", start = now, finish = now + 3, channel = false }
Fire("UNIT_SPELLCAST_START", "player")
CHECK(#harnessFailedErrors == 0, "cast start clean", harnessFailedErrors[1])

CHECK(playerRing.__shown == true, "casting: ring shown")
CHECK(playerRing.__w == 64 * 1.14, "ring diameter is the portrait times the scale", playerRing.__w)
local anchor = playerRing.__points[1]
CHECK(anchor and anchor.rel == PlayerPortrait and anchor.point == "CENTER",
    "ring centers on the portrait", anchor and anchor.point)
CHECK(playerArc.__cooldown and playerArc.__cooldown.duration == 3,
    "arc runs for the length of the cast", playerArc.__cooldown and playerArc.__cooldown.duration)
CHECK(playerArc.__reverse == true, "a cast fills clockwise by default", playerArc.__reverse)

-- ---- The leading edge ------------------------------------------------------
-- The Cooldown's own edge is a spoke from the center of the frame to its rim,
-- so on a donut it draws straight across the portrait. It stays off, and the
-- arc rides its own spark, cut to the thickness of the band it sits on.

CHECK(playerArc.__drawEdge == false,
    "the Cooldown's own edge stays off -- it would lay a line across the portrait")

local RING_OUTER = 0.485
local RATIOS = { 0.93, 0.88, 0.80, 0.71, 0.60, 0.46 }
local EDGE_CORE, EDGE_FADE = 0.30, 0.06

-- What the ring art actually measures on screen for a requested thickness: the
-- weight is the nearest of six, so the band is near the setting, not equal to it
local function Band(frameSize, thickness)
    local outer = frameSize * RING_OUTER
    local wanted = 1 - thickness / outer
    local best, bestDiff = 1, math.huge
    for i = 1, #RATIOS do
        local diff = math.abs(RATIOS[i] - wanted)
        if diff < bestDiff then best, bestDiff = i, diff end
    end
    local band = outer * (1 - RATIOS[best])
    return band, outer - band / 2      -- thickness, and the mid-band radius
end

local function RegionOf(parent, file)
    for _, region in ipairs(allRegions) do
        if region.__parent == parent and region.__texture
            and region.__texture:find(file, 1, true) then return region end
    end
end

local function RegionsOf(parent, kind)
    local out = {}
    for _, region in ipairs(allRegions) do
        if region.__parent == parent and region.__kind == kind then out[#out + 1] = region end
    end
    return out
end

local playerOverlay = OverlayOf(playerRing)
local spark = playerOverlay and RegionOf(playerOverlay, "Edge.png")
CHECK(spark ~= nil, "the arc draws its own leading edge")
CHECK(spark.__shown == true, "casting: the spark is up")

local function Offset(region)
    local point = region.__points[#region.__points]
    return point and point.x or 0, point and point.y or 0
end

local band, midBand = Band(64 * 1.14, 5)
CHECK(math.abs(spark.__w * EDGE_CORE * 2 - band) < 0.001,
    "the spark's solid core is exactly as deep as the ring band",
    spark.__w * EDGE_CORE * 2 .. " vs " .. band)
CHECK(spark.__w == spark.__h, "the spark stays square, so rotating it never clips its ends")

-- What runs past the band is the art's falloff and nothing more
local overhang = (spark.__w * (EDGE_CORE + EDGE_FADE) * 2 - band) / 2
CHECK(overhang > 0 and overhang < band * 0.15,
    "and only a tenth of the band in fade spills past it", overhang / band)

local x, y = Offset(spark)
CHECK(math.abs(math.sqrt(x * x + y * y) - midBand) < 0.001,
    "the spark rides the middle of the band, not the middle of the frame",
    math.sqrt(x * x + y * y) .. " vs " .. midBand)
CHECK(math.abs(x) < 0.001 and math.abs(y - midBand) < 0.001,
    "a cast that has not started yet puts it at twelve o'clock", x .. "," .. y)

local ice = COMMANDER_CASTING_COLORS.ICE
CHECK(spark.__color and spark.__color[1] > ice[1] and spark.__color[1] < 1,
    "the spark reads as heat off the arc: the cast's color, part way to white",
    spark.__color and spark.__color[1])

DB.PlayerRingEdge = false
Redraw()
CHECK(spark.__shown == false, "Leading Edge off takes it away")
DB.PlayerRingEdge = true
Redraw()
CHECK(spark.__shown == true, "and back on brings it back")

local ice = COMMANDER_CASTING_COLORS.ICE
CHECK(playerArc.__swipeColor and playerArc.__swipeColor[1] == ice[1] and playerArc.__swipeColor[3] == ice[3],
    "Frostbolt colors the arc Ice", playerArc.__swipeColor and playerArc.__swipeColor[1])

DB.PlayerRingColorMode = "CLASS"
Redraw()
CHECK(math.abs(playerArc.__swipeColor[1] - 0.41) < 0.001, "class color mode uses the player's class",
    playerArc.__swipeColor[1])
DB.PlayerRingColorMode = "FIXED"
DB.PlayerRingColor = "BLOOD"
Redraw()
CHECK(playerArc.__swipeColor[1] == COMMANDER_CASTING_COLORS.BLOOD[1], "fixed color mode")
DB.PlayerRingColorMode = "SCHOOL"

-- Geometry re-lays out live
DB.PlayerRingScale = 1.5
DB.PlayerRingOffsetX = 6
Redraw()
CHECK(playerRing.__w == 64 * 1.5, "ring resizes when the scale changes", playerRing.__w)
CHECK(playerRing.__points[1].x == 6, "ring takes the horizontal offset", playerRing.__points[1].x)
DB.PlayerRingScale, DB.PlayerRingOffsetX = 1.14, 0
Redraw()

-- Thicker arcs pick heavier art
local thinTexture = playerArc.__swipeTexture
DB.PlayerRingThickness = 14
Redraw()
CHECK(playerArc.__swipeTexture ~= thinTexture, "thickness picks a different ring weight",
    playerArc.__swipeTexture)
DB.PlayerRingThickness = 5
Redraw()
CHECK(playerArc.__swipeTexture == thinTexture, "and picks the same one back")

-- Channels read the other way round
casts.player = { name = "Arcane Missiles", start = now, finish = now + 5, channel = true }
Fire("UNIT_SPELLCAST_CHANNEL_START", "player")
CHECK(playerArc.__reverse == false, "a channel unwinds, so it never reads like a cast",
    playerArc.__reverse)

-- Cast ends: everything comes down
casts.player = nil
Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player")
CHECK(playerRing.__shown == false, "cast over: ring hidden again")

-- Always mode keeps the empty track up
DB.PlayerRingShowWhen = "ALWAYS"
Redraw()
CHECK(playerRing.__shown == true, "Always: the empty track stays around the portrait")
CHECK(playerArc.__cooldown == nil, "Always: but no sweep without a cast")
DB.PlayerRingShowWhen = "CASTING"
Redraw()
CHECK(playerRing.__shown == false, "back to While Casting")

-- Master switch
DB.EnablePortraitRings = false
Redraw()
CHECK(playerRing.__shown == false, "master switch off hides the ring")
casts.player = { name = "Frostbolt", start = now, finish = now + 3 }
Fire("UNIT_SPELLCAST_START", "player")
CHECK(playerRing.__shown == false, "master switch off ignores casts entirely")
casts.player = nil
DB.EnablePortraitRings = true
Redraw()

-- ===========================================================================
-- Label, latency tick, cooldown ring, flashes, and the driver's lifecycle
-- ===========================================================================

-- The one OnUpdate this module runs; nothing else may keep it alive
local driver
for _, f in ipairs(allFrames) do
    if f.__scripts.OnUpdate and f.__parent == nil and f ~= playerRing then driver = f end
end
CHECK(driver ~= nil, "driver frame found")
local function Pump(elapsed)
    if driver and driver.__shown then driver.__scripts.OnUpdate(driver, elapsed or 0.1) end
end

DB.PlayerRingText = "TIME"
DB.PlayerRingLatency = true
DB.PlayerRingTint = true
casts.player = { name = "Pyroblast", start = now, finish = now + 6 }
Fire("UNIT_SPELLCAST_START", "player")
CHECK(driver.__shown == true, "a live cast wakes the driver")

now = now + 2
Pump(0.1)
CHECK(#harnessFailedErrors == 0, "driver tick clean", harnessFailedErrors[1])

-- A third of the way through a six-second cast: past twelve, heading right and
-- down -- the same direction the sweep fills
local x, y = Offset(spark)
CHECK(x > 0 and y < 0, "the spark runs clockwise with the sweep", x .. "," .. y)

-- ...and it does so every frame. The label's 20Hz tick is too coarse for
-- something the client is drawing smoothly underneath it.
now = now + 0.01
Pump(0.01)
local movedX, movedY = Offset(spark)
CHECK(movedX ~= x or movedY ~= y, "the spark moves on a frame the label sits out")
CHECK(math.abs(math.sqrt(movedX * movedX + movedY * movedY) - midBand) < 0.001,
    "and never leaves the band while it travels")

DB.PlayerRingText = "NAME"
Redraw()
CHECK(#harnessFailedErrors == 0, "spell-name label clean", harnessFailedErrors[1])

-- The other label form: the spell's own art, standing in for the portrait
local labelText = RegionsOf(playerOverlay, "FontString")[1]
local onPlayerFrame = RegionsOf(PlayerFrame, "Texture")
local spellIcon, iconShade = onPlayerFrame[1], onPlayerFrame[2]
CHECK(labelText ~= nil and spellIcon ~= nil, "the ring has a text label and a portrait icon")
CHECK(labelText.__shown == true, "spell name is on screen before the switch")

-- Where it lives is the whole point: on the portrait's own frame, one sublevel
-- up. The frame's metal and the level number are drawn by child frames above
-- this one, so they stay on top of the icon instead of being buried by it.
CHECK(spellIcon.__parent == PlayerFrame, "the icon is a region of the portrait's own frame")
CHECK(spellIcon.__layer == "ARTWORK" and spellIcon.__sublevel == 1,
    "sitting one sublevel above the portrait -- under the frame's own art",
    tostring(spellIcon.__layer) .. ":" .. tostring(spellIcon.__sublevel))

DB.PlayerRingText = "ICON"
Redraw()
CHECK(spellIcon.__shown == true, "Spell Icon draws the cast's own art")
CHECK(spellIcon.__texture == "Interface\\Icons\\Spell_Test",
    "and it is the icon the cast reported", spellIcon.__texture)
CHECK(labelText.__shown == false, "the written label steps aside rather than stacking with it")

-- The recess: its own art, one sublevel above the icon it shades
CHECK(iconShade ~= nil and iconShade.__texture:find("IconShadeDeep", 1, true) ~= nil,
    "the deboss shading is drawn from its own art", iconShade and iconShade.__texture)
CHECK(iconShade.__sublevel == spellIcon.__sublevel + 1,
    "and lies directly on top of the icon", iconShade.__sublevel)
CHECK(iconShade.__shown == true, "on by default, since the icon is what it shades")
CHECK(iconShade.__w == spellIcon.__w and iconShade.__h == spellIcon.__h,
    "it is exactly the icon's own disc", iconShade.__w)

-- Every style is real art, and each one is its own file
local seen = {}
for _, style in ipairs({ "SOFT", "DEEP", "CARVED", "WELL" }) do
    DB.PlayerRingIconDeboss = style
    Redraw()
    local file = iconShade.__texture
    CHECK(iconShade.__shown == true and file ~= nil and seen[file] == nil,
        "deboss style " .. style .. " has art of its own", file)
    seen[file] = style
end

DB.PlayerRingIconDeboss = "OFF"
Redraw()
CHECK(iconShade.__shown == false and spellIcon.__shown == true,
    "switching the deboss off leaves the icon flat, not gone")

-- The setting used to be a checkbox; a saved boolean still means what it meant
DB.PlayerRingIconDeboss = true
Redraw()
CHECK(iconShade.__shown == true and iconShade.__texture:find("Soft", 1, true) ~= nil,
    "a saved true still draws the shading that checkbox drew", iconShade.__texture)
DB.PlayerRingIconDeboss = false
Redraw()
CHECK(iconShade.__shown == false, "and a saved false still draws none")
DB.PlayerRingIconDeboss = "DEEP"
Redraw()

-- It takes the portrait's place: centered on the ring, filling the hole the
-- arc leaves and stopping exactly where the band starts
local hole = (64 * 1.14 * RING_OUTER - band) * 2
CHECK(math.abs(spellIcon.__w - hole) < 0.001 and spellIcon.__w == spellIcon.__h,
    "the icon is a disc filling the ring's inner hole", spellIcon.__w .. " vs " .. hole)
local iconX, iconY = Offset(spellIcon)
CHECK(iconX == 0 and iconY == 0, "and it is centered on the ring, not hung beside it",
    iconX .. "," .. iconY)

-- Ring Size is what sizes it now, so the two can never disagree...
DB.PlayerRingScale = 0.9
Redraw()
CHECK(spellIcon.__w < hole, "a tighter ring cuts the icon down with it", spellIcon.__w)

-- ...up to the portrait, past which the ring is out on the frame's metal trim
DB.PlayerRingScale = 1.6
Redraw()
CHECK(spellIcon.__w == 64, "a ring out on the trim does not drag the icon over it",
    spellIcon.__w)
DB.PlayerRingScale = 1.14
DB.PlayerRingTextPlace = "ABOVE"
Redraw()
local _, aboveY = Offset(spellIcon)
CHECK(aboveY == 0, "Label Position is the written label's alone", aboveY)
DB.PlayerRingTextPlace = "BELOW"

-- Nothing to draw beats a blank disc over someone's face
casts.player = { name = "Pyroblast", start = now, finish = now + 6, noIcon = true }
Fire("UNIT_SPELLCAST_START", "player")
CHECK(spellIcon.__shown == false, "a cast reporting no art leaves the portrait alone")
casts.player = { name = "Pyroblast", start = now, finish = now + 6 }
Fire("UNIT_SPELLCAST_START", "player")
CHECK(spellIcon.__shown == true, "and the next cast that has art brings it back")

casts.player = nil
Fire("UNIT_SPELLCAST_STOP", "player")
CHECK(spellIcon.__shown == false and iconShade.__shown == false,
    "icon and shading both come down with the cast, giving the face back")
casts.player = { name = "Pyroblast", start = now, finish = now + 6 }
Fire("UNIT_SPELLCAST_START", "player")

DB.PlayerRingText = "NONE"
Redraw()
CHECK(spellIcon.__shown == false and labelText.__shown == false, "None shows neither form")
DB.PlayerRingLatency = false
DB.PlayerRingTint = false

-- Global cooldown ring: its own radius, unwinding whichever way the cast goes
DB.PlayerRingGCD = true
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 116)
local gcdSweep = ChildrenOf(playerRing)[2]
CHECK(gcdSweep and gcdSweep.__kind == "Cooldown", "cooldown ring is its own sweep",
    gcdSweep and gcdSweep.__kind)
CHECK(gcdSweep.__cooldown ~= nil and gcdSweep.__cooldown.duration == 1.5,
    "cooldown ring runs the global cooldown", gcdSweep.__cooldown and gcdSweep.__cooldown.duration)
CHECK(gcdSweep.__reverse == false, "cooldown ring unwinds")
CHECK(gcdSweep.__w ~= playerRing.__w, "cooldown ring sits on its own radius",
    gcdSweep.__w .. " vs " .. playerRing.__w)
local inside = gcdSweep.__w
DB.PlayerRingGCDPlacement = "OUTSIDE"
Redraw()
CHECK(gcdSweep.__w > inside, "Outside puts the cooldown ring past the arc", gcdSweep.__w)
DB.PlayerRingGCDPlacement = "INSIDE"
DB.PlayerRingGCD = false
Redraw()

-- An interrupted cast flashes; the flash keeps the ring up past the cast
DB.PlayerRingFailFlash = true
casts.player = { name = "Pyroblast", start = now, finish = now + 6 }
Fire("UNIT_SPELLCAST_START", "player")
casts.player = nil
Fire("UNIT_SPELLCAST_INTERRUPTED", "player")
CHECK(playerRing.__shown == true, "the interrupt flash keeps the ring on screen")

-- ...and lets go once it has burned down, taking the driver with it
now = now + 2
Pump(0.1)
Pump(0.1)
CHECK(driver.__shown == false, "driver sleeps once nothing is moving")
CHECK(playerRing.__shown == false, "and the ring comes down with it")
CHECK(#harnessFailedErrors == 0, "flash teardown clean", harnessFailedErrors[1])

-- ===========================================================================
-- The swing ring, and the seal twist assist riding on it
-- ===========================================================================

local swingSweep = ChildrenOf(playerRing)[3]
CHECK(swingSweep and swingSweep.__kind == "Cooldown", "swing ring is its own sweep",
    swingSweep and swingSweep.__kind)
CHECK(DB.PlayerRingSwing == false, "swing ring is off until it is asked for")

local function CombatLogWatchers()
    local list = eventRegistry["COMBAT_LOG_EVENT_UNFILTERED"]
    return list and #list or 0
end
CHECK(CombatLogWatchers() == 0,
    "and the combat log is not parsed at all while it is off", CombatLogWatchers())

DB.PlayerRingSwing = true
Redraw()
CHECK(CombatLogWatchers() == 1, "switching it on picks the combat log up")
CHECK(playerRing.__shown == false,
    "but nothing is drawn until a swing has actually been seen -- there is no honest "
    .. "way to draw the first swing of a fight")

PlayerSwing()
Fire("COMBAT_LOG_EVENT_UNFILTERED")
CHECK(swingSweep.__cooldown ~= nil and swingSweep.__cooldown.duration == 2.4,
    "a swing of your own starts the clock at the weapon's own speed",
    swingSweep.__cooldown and swingSweep.__cooldown.duration)
CHECK(swingSweep.__reverse == true, "and it fills toward the blow landing")
CHECK(playerRing.__shown == true, "the ring comes up for a swing with no cast behind it")
CHECK(driver.__shown == true, "and the driver wakes for it")

local ownClock = swingSweep.__cooldown.start
now = now + 0.5
PlayerSwing(false, false, "Creature-0-BBBB")
Fire("COMBAT_LOG_EVENT_UNFILTERED")
CHECK(swingSweep.__cooldown.start == ownClock, "someone else's swing is not your swing",
    swingSweep.__cooldown.start)

PlayerSwing(false, true)
Fire("COMBAT_LOG_EVENT_UNFILTERED")
CHECK(swingSweep.__cooldown.start == now, "a swing that missed is still a spent swing",
    swingSweep.__cooldown.start)

-- Two weapons, two clocks: one arc can only carry one of them
attackSpeed.off = 1.6
local mainClock = swingSweep.__cooldown.start
now = now + 0.5
PlayerSwing(true)
Fire("COMBAT_LOG_EVENT_UNFILTERED")
CHECK(swingSweep.__cooldown.start == mainClock,
    "an off-hand swing leaves the main-hand ring alone", swingSweep.__cooldown.start)
DB.PlayerRingSwingHand = "OFF"
Redraw()
CHECK(swingSweep.__cooldown.duration == 1.6, "switching hands counts the other weapon",
    swingSweep.__cooldown.duration)
DB.PlayerRingSwingHand = "MAIN"
attackSpeed.off = nil
Redraw()
CHECK(swingSweep.__cooldown.duration == 2.4, "and back again")

-- Its own radius, and its own slot when something else wants the same side
CHECK(swingSweep.__w > playerRing.__w, "Outside puts the swing ring past the cast arc",
    swingSweep.__w .. " vs " .. playerRing.__w)
local aloneSize = swingSweep.__w
DB.PlayerRingGCD = true
DB.PlayerRingGCDPlacement = "OUTSIDE"
Redraw()
CHECK(swingSweep.__w > aloneSize,
    "two extras on the same side stack outward instead of landing on each other",
    swingSweep.__w .. " vs " .. aloneSize)
CHECK(gcdSweep.__w < swingSweep.__w, "the cooldown ring taking the nearer slot of the two",
    gcdSweep.__w .. " vs " .. swingSweep.__w)
DB.PlayerRingGCD = false
DB.PlayerRingGCDPlacement = "INSIDE"
Redraw()
CHECK(swingSweep.__w == aloneSize, "and the swing ring steps back once it has the side to itself",
    swingSweep.__w)

-- Haste under a swing already in flight rewrites the clock rather than
-- restarting it: the same SHARE of the swing is left
now = now + 0.5
PlayerSwing()
Fire("COMBAT_LOG_EVENT_UNFILTERED")
now = now + 1.2                     -- exactly half of a 2.4 second swing
attackSpeed.main = 1.2
Fire("UNIT_ATTACK_SPEED", "player")
local hasted = swingSweep.__cooldown
CHECK(math.abs((hasted.start + hasted.duration - now) - 0.6) < 0.001,
    "haste halves what is LEFT of the swing, not the whole of it",
    hasted.start + hasted.duration - now)
CHECK(hasted.duration == 1.2, "over a ring that is a full sweep of the new speed",
    hasted.duration)
attackSpeed.main = 2.4

-- ---- The twist window ------------------------------------------------------

local function TicksOf(parent)
    local out = {}
    for _, region in ipairs(allRegions) do
        if region.__parent == parent and region.__texture
            and region.__texture:find("Tick.png", 1, true) then out[#out + 1] = region end
    end
    return out
end
-- The latency tick is built first, the twist mark second
local twistTick = TicksOf(playerOverlay)[2]
CHECK(twistTick ~= nil, "the swing ring has a mark of its own for the window")
CHECK(twistTick.__shown == false, "nothing marked until the assist is switched on")

now = now + 0.6
PlayerSwing()
Fire("COMBAT_LOG_EVENT_UNFILTERED")
DB.PlayerRingTwist = true
Redraw()
CHECK(twistTick.__shown == false, "still nothing while there is no seal to twist out of")

playerBuffs[1] = { name = "Seal of Command" }
Fire("UNIT_AURA", "player")
Redraw()
CHECK(twistTick.__shown == true, "a seal running is what opens the window")

local sband, sradius = Band(swingSweep.__w, 3)
local tx, ty = Offset(twistTick)
CHECK(math.abs(math.sqrt(tx * tx + ty * ty) - sradius) < 0.001,
    "the mark rides the swing ring's own band, not the cast arc's",
    math.sqrt(tx * tx + ty * ty) .. " vs " .. sradius)
CHECK(math.abs(twistTick.__w - (sband + 6)) < 0.001, "and is sized off that band too",
    twistTick.__w)
-- 0.4s of a 2.4s swing is the last sixth of it: back round past nine o'clock,
-- climbing toward the twelve where the blow lands
CHECK(tx < 0 and ty > 0, "sitting just short of twelve o'clock", tx .. "," .. ty)

local bone = COMMANDER_CASTING_COLORS.BONE
CHECK(swingSweep.__swipeColor[1] == bone[1],
    "outside the window the ring is just a swing timer", swingSweep.__swipeColor[1])

DB.PlayerRingTwistSound = true
local cues = #soundsPlayed
now = now + 2.1                     -- 0.3s left: inside a 0.4s window
Pump(0.1)
local verdant = COMMANDER_CASTING_COLORS.VERDANT
CHECK(swingSweep.__swipeColor[1] == verdant[1] and swingSweep.__swipeColor[2] == verdant[2],
    "inside it the ring turns the twist color", swingSweep.__swipeColor[1])
CHECK(#soundsPlayed == cues + 1, "and the cue sounds as the window opens",
    #soundsPlayed - cues)
Pump(0.1)
CHECK(#soundsPlayed == cues + 1, "once, not on every tick it stays open",
    #soundsPlayed - cues)

-- The seal gate can be let go of, for anyone timing something else off a swing
playerBuffs[1] = nil
Fire("UNIT_AURA", "player")
Redraw()
CHECK(twistTick.__shown == false, "losing the seal closes the window")
DB.PlayerRingTwistSeal = false
Redraw()
CHECK(twistTick.__shown == true, "unless the assist was told not to wait for one")
DB.PlayerRingTwistSeal = true

-- A swing nobody renewed lets everything go, driver included
now = now + 0.5
Pump(0.1)
Pump(0.1)
CHECK(swingSweep.__shown == false, "the swing ran out and the ring came down",
    swingSweep.__shown)
CHECK(twistTick.__shown == false, "taking the twist mark with it")
CHECK(driver.__shown == false, "and the driver sleeps once the swing is over")
CHECK(playerRing.__shown == false, "leaving the portrait alone again")

DB.PlayerRingTwist = false
DB.PlayerRingTwistSound = false
DB.PlayerRingSwing = false
Redraw()
CHECK(CombatLogWatchers() == 0, "switching the ring off drops the combat log again",
    CombatLogWatchers())
CHECK(#harnessFailedErrors == 0, "swing ring clean throughout", harnessFailedErrors[1])

-- ===========================================================================
-- The target ring
-- ===========================================================================

CHECK(targetRing.__shown == false, "no target, no target ring")

units.target.exists = true
casts.target = { name = "Pyroblast", start = now, finish = now + 6, channel = false }
Fire("PLAYER_TARGET_CHANGED")
CHECK(targetRing.__shown == true, "a target already casting is picked up on target change")
CHECK(targetArc.__cooldown and targetArc.__cooldown.duration == 6, "target arc runs their cast",
    targetArc.__cooldown and targetArc.__cooldown.duration)
local ember = COMMANDER_CASTING_COLORS.EMBER
CHECK(targetArc.__swipeColor[1] == ember[1] and targetArc.__swipeColor[2] == ember[2],
    "Pyroblast colors the target arc Ember")

DB.TargetRingColorMode = "REACTION"
Redraw()
CHECK(targetArc.__swipeColor[1] == COMMANDER_CASTING_COLORS.BLOOD[1],
    "reaction mode reads an attackable target as hostile")
DB.TargetRingColorMode = "SCHOOL"

-- A unit that stops existing mid-cast sends nothing: the clock is the backstop
casts.target = nil
units.target.exists = false
now = now + 7
Pump(0.1)
Pump(0.1)
CHECK(targetRing.__shown == false, "a cast whose unit vanished is not left sweeping forever")
CHECK(driver.__shown == false, "and the driver stops with it")

-- Dropping the target drops their cast with it
Fire("PLAYER_TARGET_CHANGED")
CHECK(targetRing.__shown == false, "target lost: ring gone")

-- The two rings are independent
units.target.exists = true
casts.target = { name = "Shadow Bolt", start = now, finish = now + 3 }
Fire("PLAYER_TARGET_CHANGED")
DB.TargetRingEnabled = false
Redraw()
CHECK(targetRing.__shown == false, "target ring switched off on its own")
casts.player = { name = "Frostbolt", start = now, finish = now + 3 }
Fire("UNIT_SPELLCAST_START", "player")
CHECK(playerRing.__shown == true, "while the player's ring keeps working")
DB.TargetRingEnabled = true
casts.player, casts.target = nil, nil
Fire("UNIT_SPELLCAST_STOP", "player")
units.target.exists = false
Fire("PLAYER_TARGET_CHANGED")

-- ===========================================================================
-- Hiding Blizzard's own cast bars
-- ===========================================================================

CHECK(PlayerCastingBarFrame.__shown == true, "Blizzard player bar untouched to start")

DB.HidePlayerCastBar = true
DB.HideTargetCastBar = true
Redraw()
CHECK(PlayerCastingBarFrame.__shown == false, "player cast bar hidden")
CHECK(TargetFrameSpellBar.__shown == false, "target cast bar hidden")

-- Blizzard showing it again during a cast must not win
FireShow(PlayerCastingBarFrame)
CHECK(PlayerCastingBarFrame.__shown == false, "the bar stays hidden when Blizzard re-shows it")

DB.HidePlayerCastBar = false
Redraw()
FireShow(PlayerCastingBarFrame)
CHECK(PlayerCastingBarFrame.__shown == true, "turning the option off gives the bar back")
DB.HideTargetCastBar = false
Redraw()

-- ===========================================================================
-- Tester
-- ===========================================================================

local before = #printLog
CommanderCasting_TestRings()
CHECK(#printLog > before, "test rings reports what it started")
CHECK(playerRing.__shown == true, "test rings draws a pretend cast")
CHECK(#harnessFailedErrors == 0, "test rings clean", harnessFailedErrors[1])

-- ===========================================================================
-- Settings pages
-- ===========================================================================

local modules = Commander.GetModules()
local sawCasting, sawRings = false, false
for _, info in ipairs(modules) do
    if info.key == "Casting" then sawCasting = true end
    if info.key == "CastingRings" then sawRings = true end
end
CHECK(sawCasting, "Casting page registered")
CHECK(sawRings, "Casting Rings page registered")
CHECK(SlashCmdList.COMMANDERUI_CASTINGRINGS ~= nil, "/cring registered")

SlashCmdList.COMMANDERUI_CASTINGRINGS("test")
CHECK(#harnessFailedErrors == 0, "/cring test clean", harnessFailedErrors[1])

-- The fullscreen glow still works off the shared school resolver
local glowBefore = #harnessFailedErrors
casts.player = { name = "Immolate", start = now, finish = now + 2 }
Fire("UNIT_SPELLCAST_START", "player")
CHECK(#harnessFailedErrors == glowBefore, "fullscreen glow survives the shared resolver",
    harnessFailedErrors[glowBefore + 1])

io.write(string.format("\n%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
