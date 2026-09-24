-- Commander Arena Frames board smoke (luajit)
--
--     luajit Commander_ArenaFrames/Harness/arenaframes_board_smoke.lua
--
-- The engine smoke next door covers the reasoning with no client attached.
-- This one covers the half that reasoning cannot reach: what the board
-- actually PAINTS once a real client has answered. It loads all four files of
-- the module over a WoW mock (lifted from the Party Frames harness, which is
-- where the widget model was built), drives real events, and asserts on the
-- text and the colours that come out the other end.
--
-- Every section here exists because of a specific failure:
--
--   A  the state strip, and the fact that CROWD CONTROL leads it. A sap used
--      to reach the board only as a 16-pixel icon sorted BELOW every buff the
--      enemy had, on a five-slot strip -- so five buffs pushed it off
--      entirely, and the one thing the board most needed to say was the first
--      thing it discarded.
--   B  the priority ladder between the five states that can claim the strip.
--   C  silence. TBC gives it no diminishing returns at all, so a lockout
--      carries no DR category -- and a board that derives control from the DR
--      table alone never draws a locked-out healer.
--   D  the health number surviving the strip. The strip covers the health bar
--      (a child frame draws over its parent's OVERLAY whatever the layers
--      say), so without its own copy of the number it deletes the one figure
--      an arena is most often decided by.
--   E  the enemy the client will not answer for. A stealthed rogue used to be
--      drawn at FULL health, which is the most misleading thing an arena
--      frame can say about the enemy who just vanished at 20%.
--   F  the board coming DOWN. Leaving an arena flipped a flag and wiped the
--      state, but nothing called Draw -- so the board stayed on screen frozen
--      on the last frame of the game that just ended.
--   G  names. `#name` counts BYTES, so a ten-byte cut through an accented
--      name lands mid-sequence and draws a replacement glyph.
-- ===========================================================================

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end
local function EQ(got, want, label)
    CHECK(got == want, label, string.format("got %s, want %s", tostring(got), tostring(want)))
end

local now = 1000
function GetTime() return now end
function time() return 1000000 + now end
function date(fmt, t) return os.date(fmt or "%c", t or (1000000 + now)) end
function GetBuildInfo() return "2.5.6", "68502", "Jul 7 2026", 20506 end

local printLog = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    printLog[#printLog + 1] = table.concat(parts, " ")
end

local caughtErrors = {}
function geterrorhandler()
    return function(err) caughtErrors[#caughtErrors + 1] = tostring(err) end
end

-- Drive one frame's OnUpdate and RECORD what it throws. Every scenario below
-- pumps OnUpdate to make the board repaint, and they all used to do it under a
-- bare pcall — which meant a repaint that errored looked exactly like a
-- repaint that worked, and the run stayed green. That is how a live banner
-- indexing past its segment pool got shipped past a full-green harness.
local function PumpFrame(f, elapsed)
    local u = f.__scripts and f.__scripts.OnUpdate
    if not u then return end
    local ok, err = pcall(u, f, elapsed or 10)
    if not ok then caughtErrors[#caughtErrors + 1] = "OnUpdate: " .. tostring(err) end
end

local NUMERIC_GETTERS = {
    GetWidth = 100, GetHeight = 20, GetScale = 1, GetEffectiveScale = 1,
    GetFrameLevel = 2, GetLeft = 0, GetBottom = 0, GetTop = 0, GetRight = 0,
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

-- Protected frames, modeled the way the client does. A frame built from a
-- secure template is protected, and so is every ANCESTOR of one — hiding a
-- container would hide the secure button inside it, so the engine walks up
-- the parent chain. That is the whole reason Show() on a plain frame full of
-- secure buttons is a blocked call in combat, which is what the field report
-- caught. Every attempt is recorded and dropped, exactly like the real thing.
blockedCalls = {}
local function Blocked(s, what)
    if not (inCombat and s.__protected) then return false end
    blockedCalls[#blockedCalls + 1] = (s.__name or s.__kind or "?") .. ":" .. what
    return true
end

local WidgetMT = {}
WidgetMT.__index = function(self, key)
    if type(key) ~= "string" then return nil end
    if key == "IsProtected" then
        local fn = function(s) return s.__protected == true, s.__secureTemplate == true end
        rawset(self, key, fn); return fn
    end
    -- Size getters report what was actually SET, falling back to the generic
    -- number only for widgets nobody sized. The banner measures its button
    -- cluster with GetWidth to know where the readout starts, so a constant
    -- 100 here would model 13px buttons as 100px ones and truncate a banner
    -- that is fine in game.
    if key == "GetWidth" or key == "GetHeight" then
        local field = (key == "GetWidth") and "__w" or "__h"
        local fallback = NUMERIC_GETTERS[key]
        local fn = function(s) return rawget(s, field) or fallback end
        rawset(self, key, fn); return fn
    end
    -- Scale, on the same terms as size. The header's right-hand controls are
    -- SCALED rather than resized -- their glyphs are drawn from a dozen quads
    -- each, so the cheap way to make them bigger is one call on the button --
    -- and a flat 1 here would make the whole Control Size setting invisible
    -- to this harness. It also matters that a getter reports what was set:
    -- the engine skips its own SetScale when the frame already carries the
    -- value it wants.
    if key == "SetScale" then
        local fn = function(s, v) s.__scale = v end
        rawset(self, key, fn); return fn
    end
    if key == "GetScale" or key == "GetEffectiveScale" then
        local fn = function(s) return rawget(s, "__scale") or 1 end
        rawset(self, key, fn); return fn
    end
    -- Face, size and outline, recorded for the same reason the colours are:
    -- "what is this written in" is a question the Header section now answers,
    -- and a no-op would let every answer pass.
    if key == "SetFont" then
        local fn = function(s, path, size, flags) s.__font = { path, size, flags } end
        rawset(self, key, fn); return fn
    end
    if NUMERIC_GETTERS[key] ~= nil then
        local v = NUMERIC_GETTERS[key]
        local fn = function() return v end
        rawset(self, key, fn); return fn
    end
    if key == "SetPoint" then
        local fn = function(s, point, rel, relPoint, x, y)
            s.__points = s.__points or {}
            s.__points[#s.__points + 1] = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
        end
        rawset(self, key, fn); return fn
    end
    if key == "ClearAllPoints" then
        local fn = function(s) s.__points = {}; s.__allPoints = nil end
        rawset(self, key, fn); return fn
    end
    -- Recorded for the renderer: a region that fills its parent (or another
    -- region) has a geometry, and "no points" would read as "nowhere".
    if key == "SetAllPoints" then
        local fn = function(s, rel) s.__allPoints = rel or s.__parent or true end
        rawset(self, key, fn); return fn
    end
    if key == "SetJustifyH" then
        local fn = function(s, j) s.__justify = j end
        rawset(self, key, fn); return fn
    end
    if key == "SetFrameLevel" then
        local fn = function(s, level) s.__level = level end
        rawset(self, key, fn); return fn
    end
    if key == "GetFrameLevel" then
        local fn = function(s) return rawget(s, "__level") or 2 end
        rawset(self, key, fn); return fn
    end
    if key == "SetSize" then
        local fn = function(s, w, h)
            if Blocked(s, "SetSize") then return end
            s.__w, s.__h = w, h
        end
        rawset(self, key, fn); return fn
    end
    -- Bars are sized with SetWidth, not SetSize. Recording it is what lets a
    -- test see how wide a fill actually came out — the difference between a
    -- healthy bar and one drawn across the whole screen.
    if key == "SetWidth" then
        local fn = function(s, w) s.__w = w end
        rawset(self, key, fn); return fn
    end
    if key == "SetHeight" then
        local fn = function(s, h) s.__h = h end
        rawset(self, key, fn); return fn
    end
    if key == "SetAttribute" then
        local fn = function(s, k, v) s.__attr = s.__attr or {}; s.__attr[k] = v end
        rawset(self, key, fn); return fn
    end
    if key == "GetAttribute" then
        local fn = function(s, k) return s.__attr and s.__attr[k] end
        rawset(self, key, fn); return fn
    end
    if key == "SetTexture" then
        local fn = function(s, tex) s.__texture = tex end
        rawset(self, key, fn); return fn
    end
    if key == "GetTexture" then
        local fn = function(s) return s.__texture end
        rawset(self, key, fn); return fn
    end
    -- Recorded, not a no-op: which way a sweep runs is the difference between
    -- "this buff is draining" and "this cooldown is coming back", and getting
    -- it backwards is invisible to every other assertion here
    -- Wrapped height, modelled rather than stubbed: the settings framework
    -- sizes section rows off this, so a flat number would make the growth path
    -- untestable — which is exactly how a checkbox ended up drawn on top of a
    -- paragraph. ~5px a character over a ~430px content width, 12px a line.
    if key == "GetStringHeight" then
        local fn = function(s)
            local text = s.__text or ""
            if text == "" then return 0 end
            local width = (s.__w and s.__w > 0) and s.__w or 430
            return math.max(12, math.ceil(#text * 5 / width) * 12)
        end
        rawset(self, key, fn); return fn
    end
    if key == "SetReverse" then
        local fn = function(s, rev) s.__reverse = rev and true or false end
        rawset(self, key, fn); return fn
    end
    if key == "SetCooldown" then
        local fn = function(s, start, dur) s.__cdStart, s.__cdDur = start, dur end
        rawset(self, key, fn); return fn
    end
    -- Recorded rather than left to the generic no-op: which sweeps wear the
    -- leading-edge spark is the whole of that option, and a no-op would let
    -- it be set on everything (or nothing) without a single test noticing
    if key == "SetDrawEdge" then
        local fn = function(s, draw) s.__drawEdge = not not draw end
        rawset(self, key, fn); return fn
    end
    if key == "SetVertexColor" then
        local fn = function(s, r, g, b, a) s.__color = { r, g, b, a } end
        rawset(self, key, fn); return fn
    end
    -- Recorded into the SAME field SetVertexColor uses, because to a test the
    -- question is "what colour is this" and not which call put it there. All
    -- of this board's chrome is drawn rather than loaded, so without this the
    -- colour of every glyph was simply invisible to the harness.
    if key == "SetColorTexture" then
        local fn = function(s, r, g, b, a) s.__color = { r, g, b, a } end
        rawset(self, key, fn); return fn
    end
    -- ...and the same field again for text. Urgency on this board is carried
    -- as much by what colour a number is as by what the number says — a red
    -- countdown and a green one are different instructions — and until this
    -- was recorded every one of those was invisible to the harness.
    if key == "SetTextColor" then
        local fn = function(s, r, g, b, a) s.__color = { r, g, b, a } end
        rawset(self, key, fn); return fn
    end
    if key == "SetDesaturated" then
        local fn = function(s, d) s.__desat = not not d end
        rawset(self, key, fn); return fn
    end
    if key == "SetText" then
        local fn = function(s, text) s.__text = text end
        rawset(self, key, fn); return fn
    end
    if key == "GetText" then
        local fn = function(s) return s.__text end
        rawset(self, key, fn); return fn
    end
    if key == "SetAlpha" then
        local fn = function(s, a) s.__alpha = a end
        rawset(self, key, fn); return fn
    end
    if key == "GetAlpha" then
        local fn = function(s) return s.__alpha or 1 end
        rawset(self, key, fn); return fn
    end
    if key == "Show" then
        local fn = function(s)
            if Blocked(s, "Show") then return end
            s.__shown = true
        end
        rawset(self, key, fn); return fn
    end
    if key == "Hide" then
        local fn = function(s)
            if Blocked(s, "Hide") then return end
            s.__shown = false
        end
        rawset(self, key, fn); return fn
    end
    if key == "SetShown" then
        local fn = function(s, shown)
            if Blocked(s, "SetShown") then return end
            s.__shown = not not shown
        end
        rawset(self, key, fn); return fn
    end
    if key == "IsShown" or key == "IsVisible" then
        local fn = function(s) return s.__shown end
        rawset(self, key, fn); return fn
    end
    if key == "GetFont" then
        local fn = function() return "Fonts\\FRIZQT__.TTF", 10, "" end
        rawset(self, key, fn); return fn
    end
    if key == "CreateTexture" then
        -- Layer and sublevel are kept: anything laid OVER an icon has to land
        -- above it in the parent's draw order, and that is worth asserting
        local fn = function(s, _, layer, _, sublevel)
            local t = NewWidget("Texture")
            t.__parent, t.__layer, t.__sublevel = s, layer, sublevel or 0
            return t
        end
        rawset(self, key, fn); return fn
    end
    if key == "GetParent" then
        local fn = function(s) return s.__parent end
        rawset(self, key, fn); return fn
    end
    if key == "GetDrawLayer" then
        local fn = function(s) return s.__layer or "ARTWORK", s.__sublevel or 0 end
        rawset(self, key, fn); return fn
    end
    if key == "CreateFontString" then
        local fn = function(s)
            local t = NewWidget("FontString")
            t.__parent = s
            s.__fontStrings = s.__fontStrings or {}
            s.__fontStrings[#s.__fontStrings + 1] = t
            return t
        end
        rawset(self, key, fn); return fn
    end
    if key == "RegisterForClicks" then
        local fn = function(s, ...) s.__clicks = { ... } end
        rawset(self, key, fn); return fn
    end
    if key == "SetScript" or key == "HookScript" then
        local fn = function(s, name, handler) s.__scripts[name] = handler end
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
    local w = setmetatable({ __kind = kind, __name = name, __scripts = {}, __shown = true }, WidgetMT)
    -- Every widget, in creation order, for the renderer next door: it draws
    -- the test board from this mock's own record of what was laid out where.
    if _G.__widgets then _G.__widgets[#_G.__widgets + 1] = w end
    return w
end

local allFrames = {}
function CreateFrame(frameType, name, parent, template)
    local f = NewWidget(frameType, name)
    f.__template = template
    f.__parent = parent
    if template and template:find("Secure") then
        f.__secureTemplate, f.__protected = true, true
        local p = parent
        while p do p.__protected = true; p = p.__parent end
    end
    if frameType == "CheckButton" or (template and template:find("CheckButton")) then
        f.Text = NewWidget("FontString")
    end
    if name then _G[name] = f end
    allFrames[#allFrames + 1] = f
    return f
end

UIParent = NewWidget("Frame", "UIParent")
WorldFrame = NewWidget("Frame", "WorldFrame")
GameTooltip = NewWidget("GameTooltip", "GameTooltip")
UISpecialFrames = {}
tinsert = table.insert
tremove = table.remove
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack
strsplit = function(sep, s) return s end

for _, f in ipairs({ "GameFontNormal", "GameFontNormalLarge", "GameFontNormalSmall",
    "GameFontNormalHuge", "GameFontHighlight", "GameFontHighlightSmall",
    "GameFontDisable", "GameFontDisableSmall", "NumberFontNormalSmall",
    "NumberFontNormal", "GameFontRedSmall" }) do
    _G[f] = NewWidget("Font")
end

SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2,
    IG_CHARACTER_INFO_TAB = 841, READY_CHECK = 8960, RAID_WARNING = 8959 }
-- Sounds are recorded rather than swallowed: the Mending alert's whole
-- contract is WHEN it makes a noise, so the noise has to be observable.
_G.__sounds = {}
function PlaySound(id) _G.__sounds[#_G.__sounds + 1] = id end
function PlaySoundFile(f) _G.__sounds[#_G.__sounds + 1] = f end
function _G.__clearSounds() for i = #_G.__sounds, 1, -1 do _G.__sounds[i] = nil end end
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
C_AddOns = { GetAddOnMetadata = function() return "4.2.0" end }

local timers = {}
C_Timer = {
    After = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end,
    NewTicker = function(interval, fn)
        local t = { interval = interval, fn = fn }
        t.Cancel = function(self) self.cancelled = true end
        return t
    end,
}

-- These were all no-ops, and a no-op dropdown mock cannot see the one thing
-- that actually goes wrong with a dropdown: an options table built with the
-- wrong key. Every other control in the settings file captions itself with
-- `label`, the dropdown framework reads `text`, and a table using the former
-- builds a control whose face and whose every entry are BLANK -- with no
-- error, at build time, on a page nothing was asserting about. It shipped.
--
-- So: run the initializer, record what the entries and the face are given,
-- and let CheckDropdowns below fail on an empty one.
function UIDropDownMenu_Initialize(frame, fn)
    if not (frame and fn) then return end
    frame.__ddEntries = {}
    _G.__ddCurrent = frame
    local ok, err = pcall(fn, frame)
    if not ok then caughtErrors[#caughtErrors + 1] = "dropdown init: " .. tostring(err) end
    _G.__ddCurrent = nil
end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info)
    local f = _G.__ddCurrent
    if f and f.__ddEntries and info then
        f.__ddEntries[#f.__ddEntries + 1] = info
    end
end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetSelectedValue(frame, value)
    if frame then frame.__ddValue = value end
end
function UIDropDownMenu_SetText(frame, text)
    if frame then frame.__ddText = text end
end
function UIDropDownMenu_EnableDropDown() end
function UIDropDownMenu_DisableDropDown() end
function UIDropDownMenu_Refresh() end
function ToggleDropDownMenu() end
SlashCmdList = {}


-- ===========================================================================
-- The arena client
-- ===========================================================================

local ADDONS = "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"

-- One table per arena seat. `present` is the client answering for them at all,
-- which is the distinction the board turns on: an enemy who goes unseen is
-- still in the game and still owns their row.
local enemies = {}
local inInstanceType = "arena"
local playerTarget, playerFocus

local function Enemy(index)
    return enemies[index]
end
local function UnitIndex(unit)
    local n = type(unit) == "string" and unit:match("^arena(%d)$")
    return n and tonumber(n) or nil
end
local function Seat(unit)
    local index = UnitIndex(unit)
    local e = index and enemies[index]
    if e and e.present then return e end
    return nil
end

function UnitExists(unit)
    if unit == "player" then return true end
    if unit == "focus" then return playerFocus ~= nil end
    local unitTarget = type(unit) == "string" and unit:match("^(arena%d)target$")
    if unitTarget then return Seat(unitTarget) ~= nil and Seat(unitTarget).target ~= nil end
    return Seat(unit) ~= nil
end
function UnitGUID(unit)
    if unit == "player" then return "Player-Me" end
    local index = UnitIndex(unit)
    -- The GUID is sticky the way the client's is: a seat keeps its identity
    -- even in the moments the client will not answer for the unit.
    return index and enemies[index] and enemies[index].guid or nil
end
function UnitName(unit)
    local e = Seat(unit); return e and e.name or nil
end
function UnitClass(unit)
    local e = Seat(unit); return e and e.class, e and e.class
end
function UnitRace(unit)
    local e = Seat(unit); return e and e.race, e and e.race
end
function UnitHealth(unit) local e = Seat(unit); return e and e.health or 0 end
function UnitHealthMax(unit) local e = Seat(unit); return e and e.healthMax or 0 end
function UnitPower(unit) local e = Seat(unit); return e and e.power or 0 end
function UnitPowerMax(unit) local e = Seat(unit); return e and e.powerMax or 0 end
function UnitPowerType(unit) local e = Seat(unit); return e and e.powerType or 0 end
function UnitIsDeadOrGhost(unit) local e = Seat(unit); return e and e.dead or false end
function UnitIsUnit(a, b)
    if b == "target" then return playerTarget == a end
    if b == "focus" then return playerFocus == a end
    if b == "player" then return a == "player" end
    return a == b
end
function UnitCastingInfo(unit)
    local e = Seat(unit)
    local c = e and e.cast
    if not c or c.channel then return nil end
    return c.name, c.name, c.icon, c.start * 1000, c.stop * 1000
end
function UnitChannelInfo(unit)
    local e = Seat(unit)
    local c = e and e.cast
    if not c or not c.channel then return nil end
    return c.name, c.name, c.icon, c.start * 1000, c.stop * 1000
end

C_UnitAuras = {
    GetAuraDataByIndex = function(unit, index, filter)
        local e = Seat(unit)
        if not e then return nil end
        local list = (filter == "HELPFUL") and e.buffs or e.debuffs
        return list and list[index] or nil
    end,
}

C_PvP = {
    RequestCrowdControlSpell = function() end,
    GetArenaCrowdControlInfo = function(unit)
        local e = Seat(unit)
        if not e or not e.trinket then return nil end
        return 42292, e.trinket.start or 0, e.trinket.duration or 0
    end,
}

function GetNumArenaOpponents()
    local count = 0
    for index = 1, 5 do if enemies[index] then count = index end end
    return count
end
GetNumArenaOpponentSpecs = nil          -- this client does not ship the prep API
function IsActiveBattlefieldArena() return inInstanceType == "arena" end
function IsInInstance() return inInstanceType ~= nil, inInstanceType end
function InCombatLockdown() return false end
function IsInGroup() return true end
function IsInRaid() return false end
LE_PARTY_CATEGORY_INSTANCE = 2
function SendChatMessage() end
function SetCVar() end
function GetCVar() return "1" end
function GetNumSpellTabs() return 0 end
function GetSpellTabInfo() return nil end
function GetSpellBookItemName() return nil end
function IsSpellKnown() return false end

-- Spell names and icons, for the ids the scenarios use.
local SPELL = {
    [6770]  = "Sap",              [118]   = "Polymorph",
    [408]   = "Kidney Shot",      [1833]  = "Cheap Shot",
    [5782]  = "Fear",             [2094]  = "Blind",
    [3355]  = "Freezing Trap Effect",
    [15487] = "Silence",          [24259] = "Spell Lock",
    [45438] = "Ice Block",        [122]   = "Frost Nova",
    [676]   = "Disarm",           [1715]  = "Hamstring",
    [871]   = "Shield Wall",      [12472] = "Icy Veins",
    [2983]  = "Sprint",           [1044]  = "Hand of Freedom",
    [23920] = "Spell Reflection", [430]   = "Drink",
    [1784]  = "Stealth",          [42292] = "PvP Trinket",
    [133]   = "Fireball",
}
function GetSpellInfo(id)
    if type(id) ~= "number" then return nil end
    local name = SPELL[id]
    if not name then return nil end
    return name, "", "Interface\\Icons\\Spell_" .. id
end
function GetSpellTexture(id) return "Interface\\Icons\\Spell_" .. tostring(id) end

RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 0.5, g = 0.5, b = 0.5 } end })
CLASS_ICON_TCOORDS = setmetatable({}, { __index = function() return { 0, 0.25, 0, 0.25 } end })

local combatEvent
function CombatLogGetCurrentEventInfo() return unpack(combatEvent) end

-- --- the suite's shared frame ----------------------------------------------
local listeners = {}
Commander = {
    AddListener = function(event, fn)
        listeners[event] = listeners[event] or {}
        table.insert(listeners[event], fn)
    end,
    -- Recorded rather than raised. A settings change goes straight into
    -- Apply, which relays out every row -- so an error there is a layout bug,
    -- and a bare call would abort the whole run instead of naming the setting
    -- that caused it.
    Notify = function(event)
        for _, fn in ipairs(listeners[event] or {}) do
            local ok, err = pcall(fn)
            if not ok then
                caughtErrors[#caughtErrors + 1] = "Notify: " .. tostring(err)
            end
        end
    end,
    DebossIcon = function() end,
    UI = {
        HudChromeDefaults = function() return { HudStyle = "NONE", HudScale = 1,
                                                HudLocked = true, HudPos = {} } end,
        ApplyHudChrome = function() end,
        AddHudChromeOptions = function() end,
        AttachTooltip = function() end,
        FormatPercent = function(v) return tostring(v) end,
        ResetToDefaults = function() end,
        ApplyDefaults = function(db, defaults)
            for key, value in pairs(defaults) do
                if db[key] == nil then
                    if type(value) == "table" then
                        local copy = {}
                        for k, v in pairs(value) do copy[k] = v end
                        db[key] = copy
                    else
                        db[key] = value
                    end
                end
            end
        end,
        -- Permissive, but not a blanket no-op: AddRow really does hand back a
        -- frame the caller builds widgets on, and a stub that returned the
        -- panel instead turns every grid cell into a nil-method error.
        NewPanel = function()
            local panel = { __refreshers = {} }
            local noop = function() return panel end
            panel.AddRow = function(_, height) 
                local row = CreateFrame("Frame", nil, UIParent)
                row:SetSize(500, height or 20)
                return row
            end
            panel.AddSpacer = panel.AddRow
            panel.AddRefresher = function(_, fn)
                panel.__refreshers[#panel.__refreshers + 1] = fn
            end
            return setmetatable(panel, { __index = function(_, key)
                if type(key) == "string" and key:match("^Add") then return noop end
                if key == "Finalize" or key == "ResizeScroll" then return noop end
                return nil
            end })
        end,
    },
}

-- ===========================================================================
-- Load the module, in TOC order
-- ===========================================================================

local function Load(file)
    local path = ADDONS .. "/Commander_ArenaFrames/" .. file
    local chunk, err = loadfile(path)
    if not chunk then error("could not load " .. file .. ": " .. tostring(err)) end
    local ok, runErr = pcall(chunk)
    if not ok then error("error running " .. file .. ": " .. tostring(runErr)) end
end

Load("CommanderArenaFramesData.lua")
Load("CommanderArenaFramesEngine.lua")
Load("CommanderArenaFramesDB.lua")
Load("CommanderArenaFrames.lua")

local function Fire(event, ...)
    for _, frame in ipairs(eventRegistry[event] or {}) do
        local handler = frame.__scripts and frame.__scripts.OnEvent
        if handler then
            local ok, err = pcall(handler, frame, event, ...)
            if not ok then
                caughtErrors[#caughtErrors + 1] = event .. ": " .. tostring(err)
            end
        end
    end
end

-- Every scenario repaints through the real ticker, so a paint that throws is
-- a recorded failure rather than a silently identical result.
local function Tick(seconds)
    now = now + (seconds or 0.1)
    for _, frame in ipairs(allFrames) do
        local update = frame.__scripts and frame.__scripts.OnUpdate
        if update then
            local ok, err = pcall(update, frame, seconds or 0.1)
            if not ok then caughtErrors[#caughtErrors + 1] = "OnUpdate: " .. tostring(err) end
        end
    end
end

local function Aura(id, left, duration, source)
    return {
        spellId = id, name = SPELL[id], icon = "Interface\\Icons\\Spell_" .. id,
        applications = 1, duration = duration or 10,
        expirationTime = left and (now + left) or 0,
        sourceUnit = source, dispelName = "Magic",
    }
end

local function Spawn(index, spec)
    enemies[index] = {
        guid = "Enemy-" .. index, present = true,
        name = spec.name, class = spec.class, race = spec.race or "Human",
        health = spec.health or 8000, healthMax = 10000,
        power = 5000, powerMax = 10000, powerType = 0,
        buffs = spec.buffs or {}, debuffs = spec.debuffs or {},
        cast = spec.cast, dead = spec.dead,
    }
    return enemies[index]
end

local function Row(index) return _G["CommanderArenaFramesRow" .. index] end
local function Board() return _G.CommanderArenaFramesFrame end

Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD")
CHECK(#caughtErrors == 0, "load: the module comes up clean", caughtErrors[1])

local function CLEU(subevent, sourceGUID, destGUID, spellId)
    combatEvent = {
        now, subevent, false, sourceGUID or "", "src", 0, 0,
        destGUID or "", "dst", 0, 0, spellId, SPELL[spellId] or "?",
    }
    Fire("COMBAT_LOG_EVENT_UNFILTERED")
end

local function Starts(text, prefix)
    return type(text) == "string" and text:sub(1, #prefix) == prefix
end

Fire("ADDON_LOADED", "Commander_ArenaFrames")

-- ===========================================================================
-- A: the state strip leads with crowd control
-- ===========================================================================

Spawn(1, { class = "ROGUE", name = "Nightfall", health = 8000,
           debuffs = { Aura(6770, 8, 10, "player") } })
Fire("PLAYER_ENTERING_WORLD")
Fire("UNIT_AURA", "arena1")
Tick()

local row, state = Row(1), Row(1).state
CHECK(Board():IsShown(), "A: the board is up")
CHECK(row:IsShown(), "A: and the enemy has a row")
CHECK(state:IsShown(), "A: a sapped enemy gets the state strip")
CHECK(Starts(state.label:GetText(), "INCAP"),
      "A: named the way a player says it, not by DR category", state.label:GetText())
-- 7.9 rather than 8.0: Tick advances the clock before it repaints, exactly
-- as a frame of the game does.
EQ(state.timer:GetText(), "7.9", "A: with the seconds left on it")
EQ(state.hp:GetText(), "80%", "A: and the health number is still there")
-- The control's icon is on the class square, not the strip: the square
-- carries the icon, the sweep and the seconds, and the strip keeps the word.
CHECK(row.ccBox:IsShown(), "A: the class square is borrowed for the control")
CHECK(not row.classIcon:IsShown(), "A: and the class icon yields to it")
EQ(row.ccBox.icon:GetTexture(), "Interface\\Icons\\Spell_6770", "A: it shows the control's own icon")
EQ(row.ccBox.text:GetText(), "7.9", "A: with the seconds written on it")
CHECK(not state.icon:IsShown(), "A: so the strip does not repeat it")

-- The drain is the clock: eight of ten seconds left is eight tenths of the bar.
local barW = state.drain:GetWidth()
CHECK(barW and barW > 0, "A: the drain has width")
Tick(4)
Fire("UNIT_AURA", "arena1")
Tick()
CHECK(state.drain:GetWidth() < barW, "A: and it drains as the control runs out")
EQ(state.timer:GetText(), "3.8", "A: the clock keeps counting")

-- ...and the aura strip no longer buries it. Five of the enemy's own buffs
-- used to push a Sap off a five-slot strip entirely.
Enemy(1).buffs = { Aura(871, 9, 10), Aura(12472, 9, 10), Aura(2983, 9, 10),
                   Aura(1044, 9, 10), Aura(23920, 9, 10) }
Fire("UNIT_AURA", "arena1")
Tick()
EQ(row.auraSlots[1].icon:GetTexture(), "Interface\\Icons\\Spell_6770",
   "A: the control is FIRST on the aura strip, above five buffs")
Enemy(1).buffs = {}

-- The strip never covers the bar (2026-09-13): no backing, the fill and its
-- colour stay, the row's own number stays, and only the name yields.
CHECK(state.bg == nil, "A: the strip has no backing to hide the bar behind")
CHECK(row.health.fill:IsShown(), "A: the health fill is still drawn under the strip")
do
    local c = row.health.fill.__color
    -- the mock answers every class with the same grey: the class colour, not
    -- a state tint and not the execute red
    CHECK(c and c[1] == 0.5 and c[2] == 0.5 and c[3] == 0.5, "A: ...in its class colour",
          c and table.concat({ c[1], c[2], c[3] }, ","))
end
CHECK(row.healthText:IsShown() and row.healthText:GetText() == "80%",
      "A: the row's own health number is the one on screen", row.healthText:GetText())
CHECK(not row.name:IsShown(), "A: the name yields to the word while the state is up")
CHECK(state.drain:GetHeight() < row.health.fill:GetHeight(),
      "A: the drain is a line under the bar, not the bar")
CHECK(state.rim and state.rim[1].__color and state.rim[1].__color[4] > 0.5,
      "A: a tinted rim frames the bar")
-- Let the sap run out: the name comes back
Tick(5)
Enemy(1).debuffs = {}
Fire("UNIT_AURA", "arena1")
Tick()
CHECK(not state:IsShown(), "A: strip down once the control has run out")
CHECK(row.name:IsShown(), "A: and the name is back")
Enemy(1).debuffs = { Aura(6770, 8, 10, "player") }
Fire("UNIT_AURA", "arena1")
Tick()
CHECK(state:IsShown(), "A: (re-sapped for the sections below)")

-- The colour modes. The default is now by class (the Gladdy pass), so the
-- value ladder is switched on explicitly for its own checks.
do
    local function Colour() return row.health.fill.__color end
    CommanderArenaFramesDB.HealthBarColor = "VALUE"
    Enemy(1).health = 3000
    Fire("UNIT_HEALTH", "arena1")
    Tick()
    local c = Colour()
    CHECK(c[1] > 0.85 and c[2] > 0.45 and c[2] < 0.65, "A: 30% by value reads orange, on the way to red", table.concat({ c[1], c[2], c[3] }, ","))
    Enemy(1).health = 1500
    Fire("UNIT_HEALTH", "arena1")
    Tick()
    c = Colour()
    CHECK(math.abs(c[1] - 0.90) < 0.01 and math.abs(c[2] - 0.16) < 0.01, "A: 15% is the execute red, whatever the mode", table.concat({ c[1], c[2], c[3] }, ","))
    Enemy(1).health = 8000
    Fire("UNIT_HEALTH", "arena1")
    CommanderArenaFramesDB.HealthBarColor = "CLASS"
    Tick()
    c = Colour()
    -- the mock answers every class with the same grey, which is still not the value colour
    CHECK(c[1] == 0.5 and c[2] == 0.5 and c[3] == 0.5, "A: by class, the bar takes the class colour", table.concat({ c[1], c[2], c[3] }, ","))
    CommanderArenaFramesDB.HealthBarColor = "FLAT"
    Tick()
    c = Colour()
    CHECK(math.abs(c[1] - 0.72) < 0.01 and math.abs(c[2] - 0.24) < 0.01, "A: plain is the flat red", table.concat({ c[1], c[2], c[3] }, ","))
    CommanderArenaFramesDB.HealthBarColor = "CLASS"
    Tick()
end

-- ===========================================================================
-- B: what the next one in that category would land at
-- ===========================================================================

CLEU("SPELL_AURA_APPLIED", "Player-Me", "Enemy-1", 6770)
Fire("UNIT_AURA", "arena1")
Tick()
CHECK(state.label:GetText():find("1/2"),
      "B: with the sap on them, the NEXT incapacitate reads half",
      state.label:GetText())

CLEU("SPELL_AURA_REMOVED", "Player-Me", "Enemy-1", 6770)
CLEU("SPELL_AURA_APPLIED", "Player-Me", "Enemy-1", 118)
Fire("UNIT_AURA", "arena1")
Tick()
CHECK(state.label:GetText():find("1/4"),
      "B: a polymorph after it takes the same ladder to a quarter",
      state.label:GetText())

CommanderArenaFramesDB.CCNextBracket = false
Tick()
CHECK(not state.label:GetText():find("1/4"), "B: and the bracket is a setting")
CommanderArenaFramesDB.CCNextBracket = true

-- ===========================================================================
-- C: silence -- the state no DR ladder can reach
-- ===========================================================================

EQ(CommanderArenaFrames_Engine.Category(15487), nil,
   "C: TBC gives silence no diminishing returns at all")

Spawn(2, { class = "PRIEST", name = "Mendicant", health = 9500,
           debuffs = { Aura(15487, 3, 5, "player") } })
Fire("PLAYER_ENTERING_WORLD")
Fire("UNIT_AURA", "arena2")
Tick()
local s2 = Row(2).state
CHECK(s2:IsShown(), "C: a locked-out healer still gets the strip")
CHECK(Starts(s2.label:GetText(), "SILENCED"), "C: and it says so", s2.label:GetText())
CHECK(not s2.label:GetText():find("1/"),
      "C: with no bracket, because there is no ladder to quote")
EQ(s2.hp:GetText(), "95%", "C: health survives a lockout too")

-- ===========================================================================
-- D: the priority ladder
-- ===========================================================================

-- A full control outranks an immunity: the clock is the thing being played
-- around, and the two almost never coexist.
Enemy(2).buffs = { Aura(45438, 6, 10) }
Enemy(2).debuffs = { Aura(6770, 8, 10, "player") }
Fire("UNIT_AURA", "arena2")
Tick()
CHECK(Starts(s2.label:GetText(), "INCAP"),
      "D: a sap outranks an ice block", s2.label:GetText())

-- ...but an immunity outranks a lockout.
Enemy(2).debuffs = { Aura(15487, 3, 5, "player") }
Fire("UNIT_AURA", "arena2")
Tick()
EQ(s2.label:GetText(), "Ice Block", "D: an ice block outranks a silence")

-- A drink is below both, and above a stealth.
Enemy(2).buffs, Enemy(2).debuffs = { Aura(430, 20, 20) }, {}
Fire("UNIT_AURA", "arena2")
Tick()
CHECK(Starts(s2.label:GetText(), "DRINKING"), "D: drinking claims the strip when nothing else does",
      s2.label:GetText())

Enemy(2).buffs = {}
Fire("UNIT_AURA", "arena2")
Tick()
CHECK(not s2:IsShown(), "D: and the strip comes down when the state does")

-- Every one of them is a switch.
Enemy(1).debuffs = { Aura(2094, 4, 6, "player") }
Fire("UNIT_AURA", "arena1")
Tick()
CHECK(Starts(state.label:GetText(), "BLINDED"), "D: a blind reads as blinded", state.label:GetText())
CommanderArenaFramesDB.CCBanner = false
Tick()
CHECK(not state:IsShown(), "D: ...and the crowd-control bar can be switched off")
CommanderArenaFramesDB.CCBanner = true
Tick()
CHECK(state:IsShown(), "D: and back on")

-- ===========================================================================
-- E: a control whose own clock has run out must not stick
-- ===========================================================================

-- The scan deliberately bails on a unit the client will not answer for, so an
-- expired state has to lapse on its own or it sits there for the whole match.
Enemy(1).present = false
Tick(8)
CHECK(not state:IsShown(), "E: an expired control lapses even with no scan to clear it")

-- ===========================================================================
-- F: the enemy the client will not answer for
-- ===========================================================================

CHECK(Row(1):IsShown(), "F: an unseen enemy keeps their row")
EQ(row.healthText:GetText(), "80%",
   "F: and their LAST KNOWN health -- not a full bar, which is the most "
   .. "misleading thing a board can say about the enemy who just vanished")
local dim = row.healthText.__color
CHECK(dim and dim[1] < 0.9, "F: drawn dimmed, so it reads as stale")
Enemy(1).present = true
Enemy(1).debuffs = {}
Fire("UNIT_AURA", "arena1")
Tick()
local live = row.healthText.__color
CHECK(live and live[1] > 0.9, "F: and bright again the moment they are back")

-- A corpse drops what was on it rather than carrying it for the rest of the game.
Enemy(1).debuffs = { Aura(6770, 9, 10, "player") }
Fire("UNIT_AURA", "arena1")
Tick()
CHECK(state:IsShown(), "F: the sap is up")
Enemy(1).dead = true
Fire("UNIT_AURA", "arena1")
Tick()
CHECK(not state:IsShown(), "F: and gone the moment they die")
Enemy(1).dead = false
Enemy(1).debuffs = {}
Fire("UNIT_AURA", "arena1")

-- ===========================================================================
-- G: names are cut in characters, not bytes
-- ===========================================================================

-- Complete UTF-8: every lead byte is followed by exactly as many
-- continuation bytes as it promises, and the string ends on a whole one.
local function WholeUTF8(text)
    local index, length = 1, #text
    while index <= length do
        local byte = text:byte(index)
        local extra
        if byte < 0x80 then extra = 0
        elseif byte >= 0xF0 then extra = 3
        elseif byte >= 0xE0 then extra = 2
        elseif byte >= 0xC0 then extra = 1
        else return false end                     -- a continuation with no lead
        for step = 1, extra do
            local continuation = text:byte(index + step)
            if not continuation or continuation < 0x80 or continuation >= 0xC0 then
                return false
            end
        end
        index = index + extra + 1
    end
    return true
end

Enemy(1).name = "Ástríðrsdóttir"        -- 14 characters, 19 bytes
Fire("ARENA_OPPONENT_UPDATE", "arena1", "seen")
Tick()
EQ(row.name:GetText(), "Ástríðrsdó", "G: ten CHARACTERS, and every one of them whole")
CHECK(WholeUTF8(row.name:GetText()), "G: nothing severed")

-- Eight is the length that proves it. `name:sub(1, 8)` lands INSIDE the
-- two-byte 'ð' and the row draws a replacement glyph -- and it is precisely
-- the long names that get cut, so the bug only ever shows on the enemy whose
-- name did not fit.
CommanderArenaFramesDB.NameMaxChars = 8
CommanderArenaFramesDB.Enable = true
Commander.Notify(COMMANDER_ARENAFRAMES_EVENTS.UPDATE)
Tick()
EQ(row.name:GetText(), "Ástríðrs", "G: eight characters, cut clear of the sequence")
CHECK(WholeUTF8(row.name:GetText()), "G: and still whole where a byte cut would sever")
CHECK(not WholeUTF8(Enemy(1).name:sub(1, 8)), "G: ...which a byte cut demonstrably does not")
CommanderArenaFramesDB.NameMaxChars = 10

-- ===========================================================================
-- H: the board comes down when the arena ends
-- ===========================================================================

CHECK(Board():IsShown(), "H: the board is up during the game")
inInstanceType = nil
enemies = {}
Fire("PLAYER_ENTERING_WORLD")
Tick()
CHECK(not Board():IsShown(),
      "H: and DOWN when it ends -- it used to stay on screen frozen on the "
      .. "last frame of the game that just finished")

-- ===========================================================================
-- I: the test board
-- ===========================================================================
--
-- /caf test fabricates state and then runs the REAL painters over it, which
-- is the whole design -- a test board drawn by its own code path proves that
-- the test board works, which is not the question anyone is asking. So it has
-- to be exercised here or the one place a player looks at the board outside a
-- game is the one place nothing checks.

-- The renderer's two hooks: settings to draw the board under, and then --
-- with the test board up and painted -- the tree itself. It is handed Tick
-- so it can repaint after adjusting a seat.
if _G.__beforeTestBoard then _G.__beforeTestBoard() end
CommanderArenaFrames_Test()
Tick()
if _G.__afterTestBoard then _G.__afterTestBoard(Tick) end
CHECK(Board():IsShown(), "I: the test board comes up outside an arena")
local seen = {}
for index = 1, 3 do
    local strip = Row(index).state
    if strip:IsShown() then seen[#seen + 1] = strip.label:GetText() end
end
EQ(#seen, 3, "I: all three test enemies carry a state strip")
CHECK(table.concat(seen, "|"):find("SILENCED"), "I: one of them is locked out",
      table.concat(seen, "|"))
CHECK(table.concat(seen, "|"):find("INCAP"), "I: one of them is sapped",
      table.concat(seen, "|"))
CHECK(table.concat(seen, "|"):find("Ice Block"), "I: and one is untouchable",
      table.concat(seen, "|"))

-- The look: the pieces borrowed from Gladdy, each checked where it lives.
-- The mage brings a Water Elemental, so their row carries the pet band; the
-- rogue brings nothing, so theirs does not -- and the difference is HEIGHT,
-- which is the part a reshape-in-combat rule cares about.
do
    local mage, rogue = Row(1), Row(3)
    CHECK(mage.pet.bar.bg:IsShown(), "I: a mage's row carries the pet band")
    EQ(mage.pet.name:GetText(), "Water Elemental", "I: naming the pet")
    CHECK(mage.pet.bar.fill:IsShown() and mage.pet.bar.fill:GetWidth() < mage.pet.bar.bg:GetWidth(),
          "I: with the pet's health as a fill")
    CHECK(not rogue.pet.bar.bg:IsShown(), "I: a rogue's row has no pet band")
    CHECK(mage:GetHeight() > rogue:GetHeight(), "I: so the mage's row is the taller",
          mage:GetHeight() .. " vs " .. rogue:GetHeight())
    -- Three elements at one height on the top block
    EQ(mage.trinket:GetHeight(), mage.classIcon:GetHeight(), "I: the trinket fills the row like the class square")
    CHECK(mage.edgeBars.edges[1]:IsShown() and mage.edgeClass.edges[1]:IsShown()
          and mage.edgeTrinket.edges[1]:IsShown(), "I: black lines around all three")
    CHECK(mage.backdrop:IsShown(), "I: and a plate under the row")
    -- The targeted row wears a ring; the untargeted one does not
    CHECK(mage.ring.edges[1]:IsShown(), "I: the target ring is up on the targeted row")
    CHECK(not rogue.ring.edges[1]:IsShown(), "I: and down on the untargeted one")
    -- Sweeps: a cooldown that is counting has its face; the trinket on
    -- cooldown too; a slot that is ready has none.
    local swept, plain = 0, 0
    for _, slot in ipairs(mage.cdSlots) do
        if slot:IsShown() then
            if slot.sweep:IsShown() then swept = swept + 1 else plain = plain + 1 end
        end
    end
    -- Blink is UTIL, and UTIL is off out of the box: two of the three used
    CHECK(swept >= 2, "I: the used cooldowns carry a sweep", swept)
    CHECK(plain >= 1, "I: and the unused ones do not", plain)
    CHECK(Row(2).trinket.sweep:IsShown(), "I: the trinket on cooldown is swept")
    CHECK(not mage.trinket.sweep:IsShown(), "I: and the ready one is not")
    -- Slot text sits on the frame ABOVE the sweep, or it goes dark under it
    CHECK(mage.cdSlots[1].text:GetParent() == mage.cdSlots[1].top, "I: slot text rides above the sweep")
    -- The cast bar carries its spark on the fill's edge
    CHECK(mage.cast.spark:IsShown(), "I: a casting enemy's bar has a spark")
    CHECK(not rogue.cast.spark:IsShown() or not rogue.cast:IsShown(), "I: and a silent one does not")
end

-- The fabricated clocks re-arm, so a thirty-second test board is a full board
-- for all thirty rather than a blank one after the first Sap runs out.
Tick(12)
CHECK(Row(3).state:IsShown(), "I: and the strips are still up twelve seconds in")

-- It clears itself, and takes the board with it.
Tick(30)
CHECK(not Board():IsShown(), "I: the test board clears itself, and comes down")

-- A settings change has to be able to reshape rows with no enemy behind them.
Commander.Notify(COMMANDER_ARENAFRAMES_EVENTS.UPDATE)
Tick()
CHECK(not Board():IsShown(), "I: and a settings change on an empty board is quiet")

-- ===========================================================================
-- J: the settings sweep
-- ===========================================================================
--
-- Every section above runs the DEFAULT board, and the defaults are one point
-- in an eighty-setting space. A layout bug that only appears with the power
-- bar off, or the cast bar overlaid on the health bar, or the brackets below
-- the row, is a bug nothing above would ever reach -- and those are exactly
-- the combinations a player reaches on their first visit to the page.
--
-- This does not assert on appearance. It asserts that every one of them
-- LAYS OUT AND PAINTS, with an enemy in every interesting state, without
-- throwing -- which is the failure that takes a board off the screen mid-game.

inInstanceType = "arena"
Spawn(1, { class = "MAGE", name = "Frostspite",
           debuffs = { Aura(6770, 8, 10, "player") } })
Spawn(2, { class = "PRIEST", name = "Mendicant",
           debuffs = { Aura(15487, 3, 5, "player") },
           cast = { name = "Greater Heal", icon = "x", start = now - 1, stop = now + 1.5 } })
Spawn(3, { class = "WARRIOR", name = "Bladefall", buffs = { Aura(871, 8, 10) } })
Fire("PLAYER_ENTERING_WORLD")
for index = 1, 3 do Fire("UNIT_AURA", "arena" .. index) end
Tick()

local SWEEP = {
    { "CastBarPosition", "OVERLAY" }, { "CastBarPosition", "BELOW" },
    { "CastBar", false },             { "CastBar", true },
    { "PowerBar", false },            { "PowerBar", true },
    { "HealthText", "NONE" },         { "HealthText", "BOTH" },
    { "HealthText", "DEFICIT" },      { "HealthText", "PERCENT" },
    { "DRPosition", "BELOW" },        { "DRPosition", "LEFT" },
    { "DRPosition", "RIGHT" },        { "DR", false }, { "DR", true },
    { "ShowClassIcon", false },       { "ShowClassIcon", true },
    { "Trinket", false },             { "Trinket", true },
    { "Auras", false },               { "Auras", true },
    { "AuraShow", "ALL" },            { "AuraShow", "PURGEABLE" },
    { "AuraShow", "NOTED" },
    { "Cooldowns", false },           { "Cooldowns", true },
    { "CooldownFit", "WRAP" },        { "CooldownFit", "FIT" },
    { "Density", "TIGHT" },           { "Density", "ROOMY" }, { "Density", "AUTO" },
    { "Padding", 0 },                 { "Padding", 6 }, { "Padding", 1 },
    { "Grow", "UP" },                 { "Grow", "DOWN" },
    { "ShowRace", true },             { "ShowSpec", false },
    { "ShowSpec", true },             { "ShowRace", false },
    { "RowHeight", 16 },              { "RowHeight", 44 }, { "RowHeight", 28 },
    { "FrameWidth", 120 },            { "FrameWidth", 320 }, { "FrameWidth", 200 },
}
local sweepErrors = #caughtErrors
for _, change in ipairs(SWEEP) do
    CommanderArenaFramesDB[change[1]] = change[2]
    Commander.Notify(COMMANDER_ARENAFRAMES_EVENTS.UPDATE)
    for index = 1, 3 do Fire("UNIT_AURA", "arena" .. index) end
    Tick()
    if #caughtErrors > sweepErrors then
        CHECK(false, "J: " .. change[1] .. " = " .. tostring(change[2]),
              caughtErrors[#caughtErrors])
        sweepErrors = #caughtErrors
    end
end
CHECK(#caughtErrors == sweepErrors, "J: every setting lays out and paints")
CHECK(Board():IsShown(), "J: and the board survives the whole sweep")
CHECK(Row(1).state:IsShown(), "J: with the crowd-control strip still up")

CHECK(#caughtErrors == 0, "the whole run paints without throwing",
      caughtErrors[1])
for i = 2, #caughtErrors do io.write("      also: ", caughtErrors[i], "\n") end

io.write(string.format("\n%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
