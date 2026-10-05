-- Commander Diminish board smoke (luajit)
--
--     luajit Commander_Diminish/Harness/diminish_board_smoke.lua
--
-- The engine smoke next door covers the rules with no client attached. This
-- covers the half the rules cannot reach: WHERE a strip is drawn and WHAT
-- picture each ladder wears. Both were decisions that changed, and both are
-- invisible to an engine test:
--
--   A  the icons. A ladder used to wear whichever spell last opened it, so
--      "stun" was a Cheap Shot one moment and a Bash the next. It wears the
--      category's own picture now -- Hammer of Justice for a stun, Polymorph
--      for the polymorph ladder -- unless the player asks for the other.
--   B  embedding. The module was born as a floating window with a named strip
--      per person. A strip now sits on the frame of the person it is about:
--      an ally's Commander Party Frames row, a unit frame for the target and
--      focus -- and NOT AT ALL for an arena enemy, whose ladders Commander
--      Arena Frames already draws on their row.
--   C  the window is still there to be chosen, and behaves as it always did.
--   D  switching the module off takes embedded strips with it. They are
--      parented to other people's frames, so hiding this module's own root no
--      longer hides them -- which is exactly the kind of thing that leaves an
--      icon stranded on a target frame until the next reload.
-- ===========================================================================

local ADDONS = "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end
local function EQ(got, want, label)
    CHECK(got == want, label, "got " .. tostring(got) .. ", want " .. tostring(want))
end

-- ===========================================================================
-- WoW mock: only what a strip of icons touches
-- ===========================================================================
local now = 1000
function GetTime() return now end
print = function() end

local caughtErrors = {}
local eventRegistry, allFrames = {}, {}

local NewWidget
local WidgetMT = {}
local RECORD = {
    Show = function(s) s.__shown = true end,
    Hide = function(s) s.__shown = false end,
    SetShown = function(s, v) s.__shown = not not v end,
    IsShown = function(s) return s.__shown end,
    -- Visible is shown all the way up, which is the whole point of parenting
    -- a strip to the frame it describes
    IsVisible = function(s)
        local f = s
        while f do
            if not f.__shown then return false end
            f = f.__parent
        end
        return true
    end,
    SetParent = function(s, p) s.__parent = p end,
    GetParent = function(s) return s.__parent end,
    SetPoint = function(s, point, rel, relPoint, x, y)
        s.__points = s.__points or {}
        s.__points[#s.__points + 1] = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
    end,
    ClearAllPoints = function(s) s.__points = {} end,
    SetSize = function(s, w, h) s.__w, s.__h = w, h end,
    GetWidth = function(s) return s.__w or 100 end,
    GetHeight = function(s) return s.__h or 20 end,
    SetTexture = function(s, t) s.__texture = t end,
    GetTexture = function(s) return s.__texture end,
    SetText = function(s, t) s.__text = t end,
    GetText = function(s) return s.__text end,
    SetFrameLevel = function(s, l) s.__level = l end,
    GetFrameLevel = function(s) return s.__level or 1 end,
    SetShadowOffset = function(s, x, y) s.__shadow = { x, y } end,
    GetFont = function() return "Fonts\\FRIZQT__.TTF", 10, "" end,
    SetScript = function(s, name, fn) s.__scripts[name] = fn end,
    HookScript = function(s, name, fn) s.__scripts[name] = fn end,
    GetScript = function(s, name) return s.__scripts[name] end,
    RegisterEvent = function(s, event)
        eventRegistry[event] = eventRegistry[event] or {}
        table.insert(eventRegistry[event], s)
    end,
    UnregisterEvent = function(s, event)
        local list = eventRegistry[event] or {}
        for i = #list, 1, -1 do if list[i] == s then table.remove(list, i) end end
    end,
    CreateTexture = function(s) local t = NewWidget("Texture"); t.__parent = s; return t end,
    CreateFontString = function(s) local t = NewWidget("FontString"); t.__parent = s; return t end,
}
WidgetMT.__index = function(self, key)
    if type(key) ~= "string" then return nil end
    local fn = RECORD[key]
    if fn then return fn end
    if key:match("^Set") or key:match("^Get") or key:match("^Is") or key:match("^Enable")
        or key:match("^Register") or key:match("^Clear") or key:match("^Create")
        or key:match("^Start") or key:match("^Stop") then
        return function() end
    end
    return nil
end
NewWidget = function(kind, name)
    return setmetatable({ __kind = kind, __name = name, __scripts = {}, __shown = true }, WidgetMT)
end
function CreateFrame(kind, name, parent)
    local f = NewWidget(kind, name)
    f.__parent = parent
    if name then _G[name] = f end
    allFrames[#allFrames + 1] = f
    return f
end
UIParent = NewWidget("Frame", "UIParent")
GameTooltip = NewWidget("GameTooltip", "GameTooltip")
for _, f in ipairs({ "GameFontNormal", "GameFontNormalSmall", "GameFontHighlight",
    "GameFontHighlightSmall", "GameFontDisableSmall" }) do
    _G[f] = NewWidget("Font")
end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
strsub, strlen, strbyte = string.sub, string.len, string.byte
unpack = unpack or table.unpack
SlashCmdList = {}
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 0.5, g = 0.5, b = 0.5 } end })

-- --- the client: who is where -------------------------------------------------
local units = {}        -- token -> { guid, name, class, hostile }
local instanceType = "arena"
function UnitExists(unit) return units[unit] ~= nil end
function UnitIsPlayer(unit) return units[unit] ~= nil end
function UnitGUID(unit) return units[unit] and units[unit].guid or nil end
function UnitName(unit) return units[unit] and units[unit].name or nil end
function UnitClass(unit) local u = units[unit]; return u and u.class, u and u.class end
function UnitCanAttack(_, unit) return units[unit] and units[unit].hostile or false end
function IsInInstance() return instanceType ~= nil, instanceType end
function InCombatLockdown() return false end
function GetSpellTexture(id) return "Interface\\Icons\\Spell_" .. tostring(id) end
function GetSpellInfo(id) return "Spell" .. tostring(id), nil, "Interface\\Icons\\Spell_" .. tostring(id) end
function GetNumSpellTabs() return 0 end
function GetPlayerInfoByGUID() return nil, "MAGE" end

local combatEvent
function CombatLogGetCurrentEventInfo() return unpack(combatEvent) end

-- --- the suite ------------------------------------------------------------------
local listeners = {}
Commander = {
    AddListener = function(event, fn)
        listeners[event] = listeners[event] or {}
        table.insert(listeners[event], fn)
    end,
    Notify = function(event)
        for _, fn in ipairs(listeners[event] or {}) do
            local ok, err = pcall(fn)
            if not ok then caughtErrors[#caughtErrors + 1] = "Notify: " .. tostring(err) end
        end
    end,
    UI = {
        HudChromeDefaults = function() return { HudStyle = "NONE", HudScale = 1, HudLocked = true, HudPos = false } end,
        ApplyHudChrome = function(frame) frame.__chromed = (frame.__chromed or 0) + 1 end,
        AddHudChromeOptions = function() end,
        AttachTooltip = function() end,
        ResetToDefaults = function() end,
        ApplyDefaults = function(db, defaults)
            for key, value in pairs(defaults) do
                if db[key] == nil then db[key] = value end
            end
        end,
        NewPanel = function()
            local panel = {}
            local noop = function() return panel end
            panel.AddRow = function(_, height)
                local row = CreateFrame("Frame", nil, UIParent)
                row:SetSize(500, height or 20)
                return row
            end
            return setmetatable(panel, { __index = function(_, key)
                if type(key) == "string" and (key:match("^Add") or key == "Finalize") then return noop end
                return nil
            end })
        end,
    },
}

-- ===========================================================================
-- Load, in TOC order
-- ===========================================================================
local function Load(file)
    local chunk, err = loadfile(ADDONS .. "/Commander_Diminish/" .. file)
    if not chunk then error("could not load " .. file .. ": " .. tostring(err)) end
    chunk()
end
Load("CommanderDiminishData.lua")
Load("CommanderDiminishEngine.lua")
Load("CommanderDiminishDB.lua")
Load("CommanderDiminish.lua")

local function Fire(event, ...)
    for _, frame in ipairs(eventRegistry[event] or {}) do
        local handler = frame.__scripts.OnEvent
        if handler then
            local ok, err = pcall(handler, frame, event, ...)
            if not ok then caughtErrors[#caughtErrors + 1] = event .. ": " .. tostring(err) end
        end
    end
end
local function Tick(seconds)
    now = now + (seconds or 0.2)
    for _, frame in ipairs(allFrames) do
        local update = frame.__scripts.OnUpdate
        if update then
            local ok, err = pcall(update, frame, seconds or 0.2)
            if not ok then caughtErrors[#caughtErrors + 1] = "OnUpdate: " .. tostring(err) end
        end
    end
end
local function CLEU(subevent, destGUID, destName, spellId)
    combatEvent = { now, subevent, false, "Player-Src", "src", 0, 0, destGUID, destName, 0, 0, spellId }
    Fire("COMBAT_LOG_EVENT_UNFILTERED")
end

units.player = { guid = "Player-Me", name = "Me", class = "MAGE" }
Fire("ADDON_LOADED", "Commander_Diminish")
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD")
CHECK(#caughtErrors == 0, "the module comes up clean", caughtErrors[1])

local db = CommanderDiminishDB
local root = _G.CommanderDiminishFrame
local function Strip(i) return _G["CommanderDiminishStrip" .. i] end
local function Shown()
    local out = {}
    for i = 1, 12 do
        local s = Strip(i)
        if s and s.__shown then out[#out + 1] = s end
    end
    return out
end
local function Anchor(strip) return strip.__points[#strip.__points] end

-- The frames a strip can sit on
local targetFrame = CreateFrame("Frame", "TargetFrame", UIParent)
local focusFrame = CreateFrame("Frame", "FocusFrame", UIParent)
local playerFrame = CreateFrame("Frame", "PlayerFrame", UIParent)
focusFrame.__shown = false

EQ(db.Placement, "EMBEDDED", "out of the box a strip sits on a frame, not in a window")
EQ(db.IconSource, "CATEGORY", "and wears its category's own picture")

-- ===========================================================================
-- A: the icons
-- ===========================================================================
-- A hostile target, stunned by a Cheap Shot (1833): the stun ladder is open.
units.target = { guid = "Player-Enemy", name = "Bladefall", class = "WARRIOR", hostile = true }
db.Scope = "ALL"
Commander.Notify(COMMANDER_DIMINISH_EVENTS.UPDATE)
CLEU("SPELL_AURA_APPLIED", "Player-Enemy", "Bladefall", 1833)
Tick()

local function CellFor(strip, texture)
    for _, cell in ipairs(strip.cells) do
        if cell.__shown and cell.icon.__texture == texture then return cell end
    end
end
local strips = Shown()
CHECK(#strips == 1, "a hostile target gets a strip", #strips)
local strip = strips[1]
CHECK(CellFor(strip, "Interface\\Icons\\Spell_853") ~= nil,
    "the stun ladder wears Hammer of Justice -- not the Cheap Shot that opened it")
CHECK(CellFor(strip, "Interface\\Icons\\Spell_1833") == nil, "the opener's own icon is nowhere on it")
CHECK(CellFor(strip, "Interface\\Icons\\Spell_118") ~= nil,
    "and the polymorph ladder, at rest, wears Polymorph")

-- The same question asked by another module (Commander Plates draws these
-- round a nameplate) gets the same answer
EQ(CommanderDiminish_Icon("STUN", 1833), "Interface\\Icons\\Spell_853",
   "the exported icon is the category's too")

db.IconSource = "SPELL"
Tick()
CHECK(CellFor(strip, "Interface\\Icons\\Spell_1833") ~= nil,
    "Last Spell: an opened ladder wears the spell that opened it")
CHECK(CellFor(strip, "Interface\\Icons\\Spell_118") ~= nil,
    "...and one nothing has opened still wears the category's, having no spell to wear")
EQ(CommanderDiminish_Icon("STUN", 1833), "Interface\\Icons\\Spell_1833", "and the export follows the setting")
db.IconSource = "CATEGORY"
Tick()

-- The numbers on a cell are written on a spell icon
local anyCell = strip.cells[1]
CHECK(anyCell.timer.__shadow and anyCell.timer.__shadow[1] == 1 and anyCell.badge.__shadow,
    "a cell's clock and badge carry a shadow under their outline")

-- ===========================================================================
-- B: embedded
-- ===========================================================================
CHECK(root.__shown == false, "embedded: the module's own window is not on screen")
EQ(strip.__parent, targetFrame, "the target's strip is parented to the target's frame")
EQ(Anchor(strip).rel, targetFrame, "and anchored to it")
CHECK(strip.label.__shown == false, "with no name over it: the frame already says whose it is")
EQ(strip.cells[1].__w, 20, "at the embedded size, not the window's")

-- The nudge moves a unit-frame strip
local baseX, baseY = Anchor(strip).x, Anchor(strip).y
db.EmbedOffsetX, db.EmbedOffsetY = 10, -4
Tick()
CHECK(Anchor(strip).x == baseX + 10 and Anchor(strip).y == baseY - 4, "the unit-frame nudge moves it",
    tostring(Anchor(strip).x) .. "," .. tostring(Anchor(strip).y))
db.EmbedOffsetX, db.EmbedOffsetY = 0, 0
Tick()

-- Which side of the unit frame it sits on is a setting, not a guess to be
-- nudged around: Below hangs it from the frame's bottom edge
do
    local a = Anchor(strip)
    CHECK(a.point == "BOTTOMLEFT" and a.relPoint == "TOPLEFT", "by default it sits above the frame",
        a.point .. " -> " .. a.relPoint)
    local sides = {
        BELOW = { "TOPLEFT", "BOTTOMLEFT" }, LEFT = { "RIGHT", "LEFT" },
        RIGHT = { "LEFT", "RIGHT" }, ABOVE = { "BOTTOMLEFT", "TOPLEFT" },
    }
    for _, side in ipairs({ "BELOW", "LEFT", "RIGHT", "ABOVE" }) do
        db.EmbedSide = side
        Tick()
        a = Anchor(strip)
        CHECK(a.point == sides[side][1] and a.relPoint == sides[side][2] and a.rel == targetFrame,
            side .. ": the strip moves to that side of the target frame", a.point .. " -> " .. a.relPoint)
    end
    db.EmbedSide = "BELOW"
    Tick()
    a = Anchor(strip)
    CHECK(a.y <= 0 and a.x == 7, "below starts at the bars' left edge, under the frame",
        a.x .. "," .. a.y)
    db.EmbedOffsetY = -30
    Tick()
    EQ(Anchor(strip).y, a.y - 30, "and the nudge still moves it from there")
    db.EmbedSide, db.EmbedOffsetY = "ABOVE", 0
    Tick()
end

-- A target with no frame up gets no strip, rather than one floating free
targetFrame.__shown = false
Tick()
CHECK(#Shown() == 0, "no frame to sit on: no strip, and nothing left floating", #Shown())
targetFrame.__shown = true
Tick()
CHECK(#Shown() == 1, "the frame back, the strip back")

-- An arena enemy whose ladders Commander Arena Frames already draws on their
-- row is not drawn a second time
function CommanderArenaFrames_ShowsDR(guid) return guid == "Player-Enemy" end
Tick()
CHECK(#Shown() == 0, "an enemy already on the arena board is left to the arena board", #Shown())
CommanderArenaFrames_ShowsDR = nil
Tick()

-- You, feared: your own row on Commander Party Frames carries it, clear of
-- that board's dispel strip
local partyRow = CreateFrame("Frame", "PartyRowMe", UIParent)
local mateRow = CreateFrame("Frame", "PartyRowMate", UIParent)
function CommanderPartyFrames_RowFor(guid)
    if guid == "Player-Me" then return partyRow, 71 end
    if guid == "Player-Mate" then return mateRow, 71 end
    return nil
end
CLEU("SPELL_AURA_APPLIED", "Player-Me", "Me", 5782)
Tick()
local mine
for _, s in ipairs(Shown()) do if s.__parent == partyRow then mine = s end end
CHECK(mine ~= nil, "what is being run on you sits on your own party row")
if mine then
    local a = Anchor(mine)
    CHECK(a.point == "LEFT" and a.relPoint == "RIGHT" and a.x == 71,
        "to the right of the row, past the end of the board's dispel strip", tostring(a.x))
    CHECK(CellFor(mine, "Interface\\Icons\\Spell_5782") ~= nil, "wearing Fear")
    EQ(#(function() local n = {} for _, c in ipairs(mine.cells) do if c.__shown then n[#n + 1] = c end end return n end)(), 1,
       "and only what has actually been opened on you")
end

-- A teammate, sapped: their row carries theirs
units.party1 = { guid = "Player-Mate", name = "Mendicant", class = "PRIEST" }
CLEU("SPELL_AURA_APPLIED", "Player-Mate", "Mendicant", 118)
Tick()
local theirs
for _, s in ipairs(Shown()) do if s.__parent == mateRow then theirs = s end end
CHECK(theirs ~= nil, "a party member's ladders sit on that party member's row")
CHECK(theirs and CellFor(theirs, "Interface\\Icons\\Spell_118") ~= nil, "wearing Polymorph")
db.ShowParty = false
Tick()
theirs = nil
for _, s in ipairs(Shown()) do if s.__parent == mateRow then theirs = s end end
CHECK(theirs == nil, "and the party switch takes it off")
db.ShowParty = true
Tick()

-- Without Party Frames, you fall back to your own unit frame
local keepRowFor = CommanderPartyFrames_RowFor
CommanderPartyFrames_RowFor = nil
Tick()
mine = nil
for _, s in ipairs(Shown()) do if s.__parent == playerFrame then mine = s end end
CHECK(mine ~= nil, "with no party board loaded, your strip sits on your own unit frame")
CommanderPartyFrames_RowFor = keepRowFor
Tick()

-- ===========================================================================
-- C: the window, for whoever wants one
-- ===========================================================================
db.Placement = "WINDOW"
Commander.Notify(COMMANDER_DIMINISH_EVENTS.UPDATE)
Tick()
CHECK(root.__shown == true, "window: the board is up")
local inWindow = 0
for _, s in ipairs(Shown()) do
    if s.__parent == root then inWindow = inWindow + 1 end
end
EQ(inWindow, #Shown(), "and every strip is in it")
CHECK(#Shown() >= 2, "one per person", #Shown())
CHECK(Shown()[1].label.__shown == true, "each with a name over it")
EQ(Shown()[1].cells[1].__w, 30, "at the window's own icon size")

-- ===========================================================================
-- D: off is off, wherever the strips were hanging
-- ===========================================================================
db.Placement = "EMBEDDED"
Commander.Notify(COMMANDER_DIMINISH_EVENTS.UPDATE)
Tick()
CHECK(root.__shown == false and #Shown() >= 2, "back on the frames")
db.Enable = false
Commander.Notify(COMMANDER_DIMINISH_EVENTS.UPDATE)
Tick()
EQ(#Shown(), 0, "switched off: nothing is left hanging on anybody's frame")
db.Enable = true
Commander.Notify(COMMANDER_DIMINISH_EVENTS.UPDATE)
Tick()

-- Leaving for somewhere this does not draw takes them down the same way
instanceType = nil
Fire("PLAYER_ENTERING_WORLD")
Tick()
EQ(#Shown(), 0, "out of the arena: every strip comes down")

CHECK(#caughtErrors == 0, "the whole run draws without throwing", caughtErrors[1])
for i = 2, #caughtErrors do io.write("      also: ", caughtErrors[i], "\n") end

io.write(string.format("\n%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
