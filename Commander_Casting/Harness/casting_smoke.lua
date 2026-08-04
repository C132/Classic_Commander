-- Commander Casting smoke (luajit) — verification for the 2.2.0 change: the
-- radial cast bars drawn around the player and target portraits. Loads the
-- REAL Commander_Events framework plus all three Casting files under a WoW
-- mock, drives casts through the same events the client sends, and asserts the
-- ring geometry, the sweep, the coloring, and the Blizzard-bar hiding.
--
-- Mock modeled on Commander_Afflictions/Harness, extended with the Cooldown
-- surface (SetCooldown / SetReverse / SetSwipeTexture / SetSwipeColor), the
-- cast-info API, and the unit frames the rings anchor to.
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
        local fn = function(s) local t = NewWidget(kind); t.__parent = s; return t end
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

SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2 }
function PlaySound() end
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

function UnitCastingInfo(unit)
    local cast = casts[unit]
    if not cast or cast.channel then return nil end
    return cast.name, cast.name, "icon", cast.start * 1000, cast.finish * 1000, false, nil, nil
end

function UnitChannelInfo(unit)
    local cast = casts[unit]
    if not cast or not cast.channel then return nil end
    return cast.name, cast.name, "icon", cast.start * 1000, cast.finish * 1000, false, nil
end

function GetSpellCooldown() return now, 1.5, 1 end

-- ---- Blizzard unit frames the rings hang off -------------------------------

PlayerFrame = NewWidget("Button", "PlayerFrame")
PlayerPortrait = NewWidget("Texture", "PlayerPortrait")
PlayerPortrait:SetSize(64, 64)

TargetFrame = NewWidget("Button", "TargetFrame")
TargetFramePortrait = NewWidget("Texture", "TargetFramePortrait")
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

-- Children of a ring holder, in creation order: tint, track, arc, [gcd],
-- overlay, glow, [tick], label
local function ChildrenOf(holder)
    local kids = {}
    for _, f in ipairs(allFrames) do
        if f.__parent == holder then kids[#kids + 1] = f end
    end
    return kids
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
CHECK(playerArc.__drawEdge == true, "leading edge on by default")

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

DB.PlayerRingText = "NAME"
Redraw()
CHECK(#harnessFailedErrors == 0, "spell-name label clean", harnessFailedErrors[1])
DB.PlayerRingText = "NONE"
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
