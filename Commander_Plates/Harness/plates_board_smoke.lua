-- Commander Plates board smoke (luajit)
--
--     luajit Commander_Plates/Harness/plates_board_smoke.lua
--
-- The engine smoke next door covers the reasoning with no client attached.
-- This one covers what the engine cannot reach: the RUNTIME, which hooks
-- Blizzard's plate, paints an overlay on it, and -- the part that goes wrong
-- silently -- writes alphas onto Blizzard's own frames and must give them
-- back, because unit frames are POOLED and the next occupant of one is
-- somebody else. All four files load over the suite's WoW widget mock (lifted
-- from the Arena Frames harness) plus a model of Blizzard's nameplate frame
-- family exactly as NamePlateUnitFrameMixin lays it out on this client:
-- HealthBarsContainer.healthBar, name, CastBarsContainer.castBar, AurasFrame
-- with UpdateShownState, ApplyFrameOptions, and a plate with SetHitTestPoints
-- gated by CanChangeHitTestPoints.
--
-- Sections:
--   A  a plate arrives: overlay built, hit box widened, Blizzard's aura
--      frame hidden, class colour applied to a friendly player
--   B  auras: rows paint, the big slot takes the stun, timers tick
--   C  target arrows and glow follow PLAYER_TARGET_CHANGED
--   D  a totem becomes an icon and Blizzard's bar goes to alpha 0 --
--      and comes BACK when the unit leaves, on the same pooled frame
--   E  the hit box in combat: refused by the client, applied at REGEN
--   F  disabling the module restores every plate
--   G  arena numbers, healer cross, cast bar emphasis and timer
--   H  the settings page builds without error and every dropdown has faces
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
        or key:match("^Stop") or key:match("^Add") or key:match("^Lock") or key:match("^Has"))
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
    -- Draw order is recorded: "beneath every ring" is a claim about levels
    if key == "SetFrameLevel" then
        local fn = function(s, v) s.__level = v end
        rawset(self, key, fn); return fn
    end
    if key == "GetFrameLevel" then
        local fn = function(s) return rawget(s, "__level") or NUMERIC_GETTERS.GetFrameLevel end
        rawset(self, key, fn); return fn
    end
    -- Masks exist on this client, and the radial plate's clock wipe depends
    -- on them: a mock without them only ever tests the fallback
    if key == "CreateMaskTexture" then
        local fn = function(s) local m = NewWidget("MaskTexture"); m.__parent = s; return m end
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
        local fn = function(s) s.__points = {} end
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
    -- Rotation is recorded: the glows spin, the wipe turns, and a no-op
    -- would let all of it be wrong without a single failure
    if key == "SetRotation" then
        local fn = function(s, rad) s.__rot = rad end
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
    -- Recorded: a number written over a picture is only readable for its dark
    -- edge, and "does this text have one" is a question a no-op cannot answer
    if key == "SetShadowOffset" then
        local fn = function(s, x, y) s.__shadow = { x, y } end
        rawset(self, key, fn); return fn
    end
    if key == "SetShadowColor" then
        local fn = function(s, r, g, b, a) s.__shadowColor = { r, g, b, a } end
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
    return setmetatable({ __kind = kind, __name = name, __scripts = {}, __shown = true }, WidgetMT)
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
-- The nameplate client
-- ===========================================================================

local ADDONS = "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"

function hooksecurefunc(a, b, c)
    if type(a) == "string" then
        local name, fn = a, b
        local orig = _G[name]
        _G[name] = function(...)
            local r = { orig(...) }
            fn(...)
            return unpack(r)
        end
    else
        local tbl, name, fn = a, b, c
        local orig = tbl[name]
        tbl[name] = function(...)
            local r = { orig(...) }
            fn(...)
            return unpack(r)
        end
    end
end

bit = bit or require("bit")
COMBATLOG_OBJECT_TYPE_PLAYER = 0x400
COMBATLOG_OBJECT_REACTION_HOSTILE = 0x40
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
RAID_CLASS_COLORS = {
    MAGE = { r = 0.41, g = 0.8, b = 0.94 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    PRIEST = { r = 1, g = 1, b = 1 }, SHAMAN = { r = 0, g = 0.44, b = 0.87 },
}
CLASS_ICON_TCOORDS = { MAGE = { 0.25, 0.5, 0, 0.25 }, WARRIOR = { 0, 0.25, 0, 0.25 }, PRIEST = { 0.5, 0.75, 0.25, 0.5 }, SHAMAN = { 0.25, 0.5, 0.25, 0.5 } }
NamePlateConstants = { NAME_ANCHOR_STYLES = { InsideHealthBar = 1, AboveHealthBar = 2, CenteredAboveHealthBar = 3 } }
NamePlateSetupOptions = { healthBarHeight = 10, unitNameAnchorStyle = 3 }

local inCombatNow = false
function InCombatLockdown() return inCombatNow end
local instanceType = nil
function IsInInstance() return instanceType ~= nil, instanceType end

local cvars = { nameplateShowOnlyNameForFriendlyPlayerUnits = "0", nameplateMaxDistance = "41",
    nameplateSelectedScale = "1", nameplateShowAll = "1", nameplateShowFriendlyClassColor = "1",
    nameplateShowClassColor = "1", nameplateMinAlpha = "0.6", nameplateMinScale = "0.8",
    nameplateNotSelectedAlpha = "0.75", nameplateOccludedAlphaMult = "0.4", nameplateOverlapV = "1.1",
    nameplateOverlapH = "0.8", nameplateTargetBehindMaxDistance = "40", nameplateShowEnemyPets = "1",
    nameplateShowEnemyGuardians = "1", nameplateShowEnemyTotems = "1", nameplateShowFriendlyPets = "1",
    nameplateShowFriendlyTotems = "1", nameplateShowFriendlyNpcs = "1", nameplateSelectedAlpha = "1" }
local cvarWrites = {}
C_CVar = {
    GetCVar = function(name) return cvars[name] end,
    SetCVar = function(name, value) cvars[name] = value; cvarWrites[#cvarWrites + 1] = name .. "=" .. value end,
}
C_Spell = { GetSpellTexture = function(id) return "Interface\\Icons\\Spell_" .. tostring(id) end }
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
function GetSpellTexture(id) return "Interface\\Icons\\Spell_" .. tostring(id) end

-- Units: one table per nameplate token
local units = {}
local playerTarget, playerFocus
local arena = {}   -- "arena1" -> unit token

local function U(unit)
    if unit == "player" then return { guid = "Player-ME", name = "Me", class = "PRIEST", player = true, friend = true } end
    if unit == "target" then return playerTarget and units[playerTarget] end
    if unit == "focus" then return playerFocus and units[playerFocus] end
    if arena[unit] then return units[arena[unit]] end
    return units[unit]
end
function UnitExists(unit) return U(unit) ~= nil end
function UnitReaction(_, unit)
    local u = U(unit)
    if not u then return nil end
    if u.neutral then return 4 end
    return u.friend and 5 or 2
end
function UnitHealthMax(unit) local u = U(unit); return u and (u.maxhp or 9000) or 0 end
function UnitGUID(unit) local u = U(unit); return u and u.guid end
function UnitName(unit) local u = U(unit); return u and u.name end
function UnitClass(unit) local u = U(unit); if u and u.class then return u.class, u.class end end
function UnitIsPlayer(unit) local u = U(unit); return u and u.player or false end
function UnitTreatAsPlayerForDisplay() return false end
function UnitIsFriend(_, unit) local u = U(unit); return u and u.friend or false end
function UnitCanAttack(_, unit) local u = U(unit); return u and not u.friend or false end
function UnitIsConnected() return true end
function UnitIsDeadOrGhost(unit) local u = U(unit); return u and u.dead or false end
function UnitIsUnit(a, b)
    local ua, ub = U(a), U(b)
    return ua ~= nil and ua == ub
end
function UnitCastingInfo(unit)
    local u = U(unit)
    if u and u.cast then return u.cast.name, u.cast.name, u.cast.icon, u.cast.startMS, u.cast.endMS end
end
function UnitChannelInfo() return nil end
C_UnitAuras = {
    GetAuraDataByIndex = function(unit, index, filter)
        local u = U(unit)
        if not u then return nil end
        local list = (filter == "HELPFUL") and u.buffs or u.debuffs
        return list and list[index] or nil
    end,
}
local combatEvent = {}
function CombatLogGetCurrentEventInfo() return unpack(combatEvent) end

-- Blizzard's nameplate frame family, one per unit token
local plates = {}
local hitTestLog = {}
local function NewPlate(unit)
    local plate = NewWidget("Frame", "NamePlate_" .. unit)
    plate.__canChange = true
    plate.CanChangeHitTestPoints = function(s) return s.__canChange end
    plate.SetHitTestPoints = function(s, points)
        if not s.__canChange then error("RequiresCanChangeHitTestPoints") end
        s.__hit = points
        hitTestLog[#hitTestLog + 1] = unit
    end
    plate.GetFrameOptions = function() return { useClassColors = true } end

    local uf = NewWidget("Button", "NamePlate_" .. unit .. "_UF")
    uf.__parent = plate
    uf.unit = unit
    uf.HealthBarsContainer = NewWidget("Frame")
    uf.HealthBarsContainer.__parent = uf
    uf.HealthBarsContainer.healthBar = NewWidget("StatusBar")
    uf.HealthBarsContainer.healthBar.__w = 120
    uf.HealthBarsContainer.healthBar.__color = { 0.67, 0.67, 1 }
    uf.HealthBarsContainer.healthBar.GetStatusBarColor = function(s) return unpack(s.__color) end
    uf.HealthBarsContainer.healthBar.SetStatusBarColor = function(s, r, g, b) s.__color = { r, g, b } end
    uf.HealthBarsContainer.healthBar.bgTexture = NewWidget("Texture")
    uf.healthBar = uf.HealthBarsContainer.healthBar
    uf.selectionHighlight = NewWidget("Texture")
    uf.name = NewWidget("FontString")
    uf.name.__text = U(unit) and U(unit).name
    uf.CastBarsContainer = NewWidget("Frame")
    uf.CastBarsContainer.castBar = NewWidget("StatusBar")
    uf.CastBarsContainer.castBar.__shown = false
    uf.CastBarsContainer.castBar.Icon = NewWidget("Texture")
    uf.CastBarsContainer.castBar.Border = NewWidget("Texture")
    uf.CastBarsContainer.castBar.__parent = uf.CastBarsContainer
    uf.CastBarsContainer.__parent = uf
    uf.CastBarsContainer.castBar.SetStatusBarColor = function(s2, r, g, b) s2.__color = { r, g, b } end
    uf.CastBarsContainer.castBar.SetStatusBarTexture = function(s2, tex) s2.__texture = tex end
    uf.CastBarsContainer.castBar.UpdateBarFillTexture = function(s2)
        s2.__texture = "blizzard-atlas"; s2.__color = { 1, 1, 1 }
    end
    uf.LevelFrame = NewWidget("Frame")
    -- The textures Blizzard_NamePlates.xml hangs on the unit frame itself:
    -- the selection highlight IGNORES parent alpha, so it has to be modelled
    for _, key in ipairs({ "selectionHighlight", "aggroHighlightBase", "aggroHighlightAdditive",
        "aggroHighlightMask", "aggroFlash", "behindCameraIcon" }) do
        uf[key] = NewWidget("Texture")
        uf[key].__shown = false
    end
    uf.AurasFrame = NewWidget("Frame")
    uf.AurasFrame.__parent = uf
    uf.AurasFrame.UpdateShownState = function(s) s.__shown = true end
    uf.ApplyFrameOptions = function(s)
        s.__applied = (s.__applied or 0) + 1
        plate:SetHitTestPoints({ blizzard = true })
    end
    uf.UpdateAnchors = function() end
    uf.IsForbidden = function() return false end
    plate.UnitFrame = uf
    return plate
end

C_NamePlate = {
    GetNamePlateForUnit = function(unit) return plates[unit] end,
}

-- Blizzard's colouring and naming, the two functions the runtime hooks
function CompactUnitFrame_UpdateHealthColor(frame)
    frame.healthBar:SetStatusBarColor(0.67, 0.67, 1)   -- Blizzard's flat friendly blue
end
-- Blizzard's selection highlight: shown on the target (and, on this client,
-- the mouseover)
function CompactUnitFrame_UpdateSelectionHighlight(frame)
    frame.selectionHighlight:SetShown(UnitIsUnit(frame.unit, "target"))
end
function CompactUnitFrame_UpdateName(frame)
    local u = U(frame.unit)
    frame.name:SetText(u and u.name or "")
    frame.name:SetVertexColor(1, 1, 1)
    frame.name.__shown = true
end

-- --- the suite's shared frame ----------------------------------------------
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
        AttachTooltip = function() end,
        FormatPercent = function(v) return tostring(v) end,
        ResetToDefaults = function() end,
        ApplyDefaults = function(db, defaults)
            for key, value in pairs(defaults) do
                if db[key] == nil then db[key] = value end
            end
        end,
    },
}

-- A settings-panel mock that actually BUILDS the controls, so a typo in a
-- method name or an options table with the wrong key is a failure here
-- rather than on the live page. Every Add* records what it was given.
local built = { checks = 0, sliders = 0, dropdowns = {}, sections = 0, buttons = 0, rows = 0 }
builtPanel = nil
Commander.UI.NewPanel = function(opts)
    local panel = { __refreshers = {}, __opts = opts }
    builtPanel = panel
    panel.AddRow = function(_, height)
        built.rows = built.rows + 1
        local row = CreateFrame("Frame", nil, UIParent)
        row:SetSize(500, height or 20)
        return row
    end
    panel.AddSpacer = panel.AddRow
    panel.AddRefresher = function(_, fn) panel.__refreshers[#panel.__refreshers + 1] = fn end
    panel.AddSection = function(_, text, sub) built.sections = built.sections + 1; assert(type(text) == "string") end
    built.folds = {}
    panel.AddFoldout = function(_, text, sub, o)
        built.sections = built.sections + 1
        assert(type(text) == "string" and type(o) == "table" and o.key, "foldout '" .. tostring(text) .. "' has a key")
        built.folds[#built.folds + 1] = { title = text, opts = o }
        return {}
    end
    panel.EndFoldout = function() end
    panel.AddSearchBox = function() built.search = (built.search or 0) + 1 end
    panel.TagRow = function() end
    local function Check(o) assert(type(o.label) == "string" and o.get and o.set, "checkbox shape"); built.checks = built.checks + 1 end
    panel.AddCheckbox = function(_, o) Check(o) end
    panel.AddCheckboxPair = function(_, a, b) Check(a); if b then Check(b) end end
    local function Slider(o)
        assert(type(o.label) == "string" and o.min and o.max and o.step and o.get and o.set, "slider shape: " .. tostring(o.label))
        built.sliders = built.sliders + 1
    end
    panel.AddSlider = function(_, o) Slider(o) end
    panel.AddSliderPair = function(_, a, b) Slider(a); if b then Slider(b) end end
    local function Drop(o)
        assert(type(o.label) == "string" and type(o.options) == "table" and o.get and o.set, "dropdown shape")
        for _, entry in ipairs(o.options) do
            assert(type(entry.text) == "string" and entry.text ~= "", "dropdown '" .. o.label .. "' has a faceless entry")
            assert(entry.value ~= nil, "dropdown '" .. o.label .. "' has a nil value")
        end
        built.dropdowns[#built.dropdowns + 1] = o
    end
    panel.AddDropdown = function(_, o) Drop(o) end
    panel.AddDropdownPair = function(_, a, b) Drop(a); if b then Drop(b) end end
    panel.AddButtonRow = function(_, list) for _, b in ipairs(list) do assert(b.label and b.onClick); built.buttons = built.buttons + 1 end end
    panel.Finalize = function() end
    panel._Changed = function() Commander.Notify(opts.event) end
    return panel
end

-- ===========================================================================
-- Load the module, in TOC order
-- ===========================================================================

local function Load(file)
    local path = ADDONS .. "/Commander_Plates/" .. file
    local chunk, err = loadfile(path)
    if not chunk then error("could not load " .. file .. ": " .. tostring(err)) end
    local ok, runErr = pcall(chunk)
    if not ok then error("error running " .. file .. ": " .. tostring(runErr)) end
end

Load("CommanderPlatesData.lua")
Load("CommanderPlatesEngine.lua")
Load("CommanderPlatesDraw.lua")
Load("CommanderPlatesRadial.lua")
Load("CommanderPlatesDB.lua")
Load("CommanderPlates.lua")

local function Fire(event, ...)
    for _, frame in ipairs(eventRegistry[event] or {}) do
        local handler = frame.__scripts and frame.__scripts.OnEvent
        if handler then
            local ok, err = pcall(handler, frame, event, ...)
            if not ok then caughtErrors[#caughtErrors + 1] = event .. ": " .. tostring(err) end
        end
    end
end

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

local function Aura(name, id, left, duration, mine, extra)
    local a = { name = name, spellId = id, icon = "Interface\\Icons\\" .. name, duration = duration or 8,
        expirationTime = now + (left or 8), applications = 0, sourceUnit = mine and "player" or "nameplate8",
        auraInstanceID = id * 100 + math.random(1, 99) }
    for k, v in pairs(extra or {}) do a[k] = v end
    return a
end

-- Bring a unit into the world with a plate, the way the client does: Blizzard
-- runs ApplyFrameOptions (setting ITS hit box) and then NAME_PLATE_UNIT_ADDED
local function Spawn(unit, spec)
    units[unit] = spec
    spec.debuffs = spec.debuffs or {}
    spec.buffs = spec.buffs or {}
    local plate = plates[unit] or NewPlate(unit)
    plates[unit] = plate
    plate.UnitFrame.unit = unit
    plate.UnitFrame.name.__text = spec.name
    plate.UnitFrame:ApplyFrameOptions()
    CompactUnitFrame_UpdateHealthColor(plate.UnitFrame)
    CompactUnitFrame_UpdateName(plate.UnitFrame)
    plate.UnitFrame.AurasFrame:UpdateShownState()
    Fire("NAME_PLATE_UNIT_ADDED", unit)
    return plate
end

local function Despawn(unit)
    Fire("NAME_PLATE_UNIT_REMOVED", unit)
    units[unit] = nil
end

-- The overlay is the one child frame the runtime parents to the unit frame
local function Overlay(plate)
    for _, f in ipairs(allFrames) do
        if f.__parent == plate.UnitFrame and f.icons and f.big then return f end
    end
end

local function ShownIcons(ov)
    local n = 0
    for _, f in ipairs(ov.icons) do if f.__shown then n = n + 1 end end
    return n
end

local function ShownIconNames(ov)
    local out = {}
    for _, f in ipairs(ov.icons) do if f.__shown then out[#out + 1] = (f.icon.__texture or ""):match("[^\\]+$") or "" end end
    return table.concat(out, ",")
end

local function Ring(ring) return ring.top.__shown end

local function NoErrors(label)
    CHECK(#caughtErrors == 0, label, caughtErrors[1])
    for i = #caughtErrors, 1, -1 do caughtErrors[i] = nil end
end

-- ===========================================================================
Fire("ADDON_LOADED", "Commander_Plates")
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD")
NoErrors("login runs clean")

-- ---------------------------------------------------------------------------
io.write("A. a plate arrives\n")
hitTestLog = {}
local friend = Spawn("nameplate1", { guid = "Player-F1", name = "Healbot", class = "PRIEST", player = true, friend = true })
NoErrors("friendly plate added without error")
local ov = Overlay(friend)
CHECK(ov ~= nil, "an overlay frame was parented to the unit frame")
local color = friend.UnitFrame.healthBar.__color
CHECK(color[1] == 1 and color[2] == 1 and color[3] == 1, "friendly priest bar recoloured to the PRIEST class colour", table.concat(color, ","))
local nameColor = friend.UnitFrame.name.__color
CHECK(nameColor and nameColor[1] == 1, "friendly name coloured by class")
CHECK(#hitTestLog >= 2 and friend.__hit and not friend.__hit.blizzard, "the hit box was widened after Blizzard's own pass")
CHECK(friend.__hit[1].offsetY == 5 + 8 or friend.__hit[1].offsetY == 8, "top extends by HitBoxTop (" .. tostring(friend.__hit[1].offsetY) .. ")")
CHECK(friend.__hit[2].offsetY == -(5 + 6), "bottom extends by HitBoxBottom (" .. tostring(friend.__hit[2].offsetY) .. ")")
CHECK(friend.UnitFrame.AurasFrame.__shown == false, "Blizzard's aura frame is hidden")
friend.UnitFrame.AurasFrame:UpdateShownState()
CHECK(friend.UnitFrame.AurasFrame.__shown == false, "...and stays hidden when Blizzard re-shows it")

local tint = friend.UnitFrame.healthBar.bgTexture.__color
CHECK(tint and tint[3] == 1 and tint[1] == 0.35, "friendly frame tinted blue (" .. (tint and table.concat(tint, ",") or "nil") .. ")")
CHECK(friend.UnitFrame.CastBarsContainer.castBar.Border.__color[3] == 1, "...cast bar border too")

-- Blizzard recolours on its own events; the hook follows
CompactUnitFrame_UpdateHealthColor(friend.UnitFrame)
CHECK(friend.UnitFrame.healthBar.__color[1] == 1, "a Blizzard recolour is followed by ours")

-- The player's own plate is left alone
units["nameplate9"] = { guid = "Player-ME", name = "Me", class = "PRIEST", player = true, friend = true }
plates["nameplate9"] = NewPlate("nameplate9")
playerTarget = nil
-- make nameplate9 answer as the player
local realU = U
U = function(unit) if unit == "nameplate9" then return realU("player") end return realU(unit) end
UnitIsUnit = function(a, b) local ua, ub = U(a), U(b); return ua ~= nil and (ua == ub or (ua.guid and ua.guid == (ub and ub.guid))) end
Fire("NAME_PLATE_UNIT_ADDED", "nameplate9")
CHECK(Overlay(plates["nameplate9"]) == nil, "the personal plate gets no overlay")
Fire("NAME_PLATE_UNIT_REMOVED", "nameplate9")
plates["nameplate9"] = nil

-- ---------------------------------------------------------------------------
io.write("B. auras and the big slot\n")
local enemy = Spawn("nameplate2", { guid = "Player-E1", name = "Gankmage", class = "MAGE", player = true, friend = false })
NoErrors("enemy plate added")
local eov = Overlay(enemy)
local ec = enemy.UnitFrame.healthBar.__color
CHECK(math.abs(ec[1] - 0.41) < 0.01, "enemy mage bar in MAGE colour")
local etint = enemy.UnitFrame.healthBar.bgTexture.__color
CHECK(etint and etint[1] == 1 and etint[2] == 0.25, "hostile frame tinted red (" .. table.concat(etint, ",") .. ")")
CommanderPlatesDB.HostileBorderTint = "OFF"
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(enemy.UnitFrame.healthBar.bgTexture.__color[1] == 1 and enemy.UnitFrame.healthBar.bgTexture.__color[2] == 1, "tint OFF -> white")
CommanderPlatesDB.HostileBorderTint = "REACTION"
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(enemy.UnitFrame.healthBar.bgTexture.__color[1] == 0.95, "REACTION tint on a hostile is red")
CommanderPlatesDB.HostileBorderTint = "RED"
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
-- Names by reaction
CommanderPlatesDB.EnemyNameColor = "REACTION"
CompactUnitFrame_UpdateName(enemy.UnitFrame)
CHECK(enemy.UnitFrame.name.__color[1] == 0.95 and enemy.UnitFrame.name.__color[2] == 0.2, "enemy name in hostile red")
CommanderPlatesDB.EnemyNameColor = "DEFAULT"
CompactUnitFrame_UpdateName(enemy.UnitFrame)
CHECK(enemy.UnitFrame.name.__color[1] == 1 and enemy.UnitFrame.name.__color[2] == 1, "DEFAULT leaves Blizzard's white")
CommanderPlatesDB.EnemyNameColor = "CLASS"
CompactUnitFrame_UpdateName(enemy.UnitFrame)
-- A neutral NPC's name under the NPC setting
local npc = Spawn("nameplate7", { guid = "Creature-N1", name = "Wandering Ogre", player = false, friend = false, neutral = true })
CHECK(npc.UnitFrame.name.__color[1] == 1 and npc.UnitFrame.name.__color[2] == 1, "NPC name left alone by default")
CommanderPlatesDB.NpcNameColor = "REACTION"
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(npc.UnitFrame.name.__color[2] == 0.85, "REACTION on a neutral NPC is yellow (" .. table.concat(npc.UnitFrame.name.__color, ",") .. ")")
CommanderPlatesDB.NpcNameColor = "CLASS"
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(npc.UnitFrame.name.__color[2] == 0.85, "CLASS on an NPC falls back to reaction rather than white")
CommanderPlatesDB.NpcNameColor = "DEFAULT"
Despawn("nameplate7")
CHECK(npc.UnitFrame.healthBar.bgTexture.__color[1] == 1 and npc.UnitFrame.healthBar.bgTexture.__color[2] == 1, "frame tint restored to white on removal")
units.nameplate2.debuffs = {
    Aura("Corruption", 172, 12, 18, true),
    Aura("Rend", 772, 10, 15, false),
    Aura("Cheap Shot", 1833, 3, 4, false),
    Aura("Hamstring", 1715, 10, 15, false),
}
units.nameplate2.buffs = {
    Aura("Arcane Power", 12042, 10, 15, false),
    Aura("Power Word: Fortitude", 1243, 1000, 1800, false, { isStealable = true }),
}
Fire("UNIT_AURA", "nameplate2")
NoErrors("UNIT_AURA refresh clean")
CHECK(eov.big.__shown == true, "the big slot is shown")
CHECK(eov.big.icon.__texture == "Interface\\Icons\\Cheap Shot", "...and it holds the stun", eov.big.icon.__texture)
CHECK(eov.big.glow.__shown == true, "the big slot glows")
CHECK(eov.big.__points[1].point == "BOTTOM" and eov.big.__points[1].rel == enemy.UnitFrame.name, "default anchor is ABOVE the plate, not over the bar")
CommanderPlatesDB.CcAnchor = "BELOW"
Fire("UNIT_AURA", "nameplate2")
CHECK(eov.big.__points[1].point == "TOP" and eov.big.__points[1].rel == enemy.UnitFrame.CastBarsContainer, "BELOW hangs under the cast bar")
CommanderPlatesDB.CcAnchor = "CENTER"
Fire("UNIT_AURA", "nameplate2")
CHECK(eov.big.__points[1].point == "CENTER", "CENTER still available for those who want it")
CommanderPlatesDB.CcAnchor = "ABOVE"
-- Health markers: percent (white) and value (gold, moving with max health)
CommanderPlatesDB.HealthMarkerPercent = 20
CommanderPlatesDB.HealthMarkerValue = 4500
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(eov.marker.__shown == true and eov.marker.__points[1].x == 24, "20% line at 20% of a 120px bar (" .. tostring(eov.marker.__points[1].x) .. ")")
CHECK(eov.markerValue.__shown == true and eov.markerValue.__points[1].x == 60, "4500 of 9000 max health at the middle (" .. tostring(eov.markerValue.__points[1].x) .. ")")
units.nameplate2.maxhp = 18000
Fire("UNIT_MAXHEALTH", "nameplate2")
CHECK(eov.markerValue.__points[1].x == 30, "...and moves when max health changes (" .. tostring(eov.markerValue.__points[1].x) .. ")")
CHECK(ov.marker.__shown ~= true and ov.markerValue.__shown ~= true, "no markers on a friend")
CommanderPlatesDB.HealthMarkerValue = 20000
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(eov.markerValue.__shown == false, "a value above max health draws nothing")
CommanderPlatesDB.HealthMarkerPercent = 0
CommanderPlatesDB.HealthMarkerValue = 0
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(eov.marker.__shown == false, "markers off")
local names = ShownIconNames(eov)
CHECK(names == "Corruption,Arcane Power,Power Word: Fortitude", "rows: my Corruption; notable buff + purgeable buff for a priest (" .. names .. ")")
CHECK(eov.big.timer.__text == nil or eov.big.timer.__text == "", "timer text not yet written before a tick")
Tick(0.1)
NoErrors("tick clean")
CHECK(eov.big.timer.__text == "2.9", "big-slot timer reads tenths under three seconds", eov.big.timer.__text)
-- The purgeable buff glows for a priest
local purge
for _, f in ipairs(eov.icons) do if f.__shown and f.icon.__texture == "Interface\\Icons\\Power Word: Fortitude" then purge = f end end
CHECK(purge and purge.glow.__shown == true, "the purgeable buff glows")
-- Stun ends: the big slot empties
table.remove(units.nameplate2.debuffs, 3)
Fire("UNIT_AURA", "nameplate2")
CHECK(eov.big.__shown == false, "stun gone -> big slot hidden")
-- Whitelist makes Rend show
CommanderPlatesDB.Whitelist = "Rend"
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
NoErrors("settings change clean")
CHECK(ShownIconNames(eov):find("Rend") ~= nil, "whitelisted Rend appears (" .. ShownIconNames(eov) .. ")")
CommanderPlatesDB.Whitelist = ""
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)

-- The friendly "mine" filter must not trust isFromPlayerOrPlayerPet: on this
-- client it is the old castByPlayer flag, true for any PLAYER's cast, so on a
-- friendly player it is true for every buff they carry
units.nameplate1.buffs = {
    Aura("Renew", 139, 10, 15, true),
    Aura("Power Word: Fortitude", 1243, 1000, 1800, false, { isFromPlayerOrPlayerPet = true }),
    Aura("Mark of the Wild", 1126, 1000, 1800, false, { isFromPlayerOrPlayerPet = true, sourceUnit = "party2" }),
    Aura("Arcane Intellect", 1459, 1000, 1800, false, { isFromPlayerOrPlayerPet = true, sourceUnit = nil }),
}
Fire("UNIT_AURA", "nameplate1")
CHECK(ShownIconNames(ov) == "Renew", "friendly MINE shows only my Renew, whatever castByPlayer says (" .. ShownIconNames(ov) .. ")")
units.nameplate1.buffs = {}
Fire("UNIT_AURA", "nameplate1")

-- ---------------------------------------------------------------------------
io.write("C. target and focus\n")
playerTarget = "nameplate2"
Fire("PLAYER_TARGET_CHANGED")
CHECK(eov.targetHalo.top.__shown == true and Ring(eov.targetRing) ~= true, "SOFT: a halo on the target, no hard ring")
CommanderPlatesDB.TargetGlowStyle = "OUTLINE"
Fire("PLAYER_TARGET_CHANGED")
CHECK(Ring(eov.targetRing) == true and eov.targetHalo.top.__shown == false, "OUTLINE: the ring, no halo")
CommanderPlatesDB.TargetGlowColor = "REACTION"
Fire("PLAYER_TARGET_CHANGED")
CHECK(eov.targetRing.top.__color[1] == 0.95, "REACTION glow on a hostile target is red")
CommanderPlatesDB.TargetGlowColor = "WHITE"
Fire("PLAYER_TARGET_CHANGED")
CHECK(Ring(eov.targetRing) == true, "target ring on the target")
CHECK(eov.arrowL.__shown == true and eov.arrowR.__shown == true, "arrows on the target")
CHECK(Ring(ov.targetRing) ~= true, "no ring on the non-target")
CHECK(eov.classIcon.__shown == true, "class icon on an enemy player")
CHECK(ov.classIcon.__shown ~= true, "no class icon on a friend by default")
playerFocus = "nameplate1"
Fire("PLAYER_FOCUS_CHANGED")
CHECK(Ring(ov.focusRing) == true, "focus ring on the focus")
CHECK(ov.focusRing.top.__color[1] == 0.95 and ov.focusRing.top.__color[3] == 0.85, "focus glow in the focus colour (magenta)")
playerTarget = nil
Fire("PLAYER_TARGET_CHANGED")
CHECK(Ring(eov.targetRing) ~= true and eov.arrowL.__shown ~= true, "target cleared -> ring and arrows gone")
CommanderPlatesDB.TargetGlowColor = "CLASS"
playerTarget = "nameplate2"
Fire("PLAYER_TARGET_CHANGED")
CHECK(math.abs(eov.targetRing.top.__color[1] - 0.41) < 0.01, "CLASS glow colour uses the target's class")
CommanderPlatesDB.TargetGlowColor = "WHITE"
CommanderPlatesDB.TargetGlowStyle = "SOFT"
Fire("PLAYER_TARGET_CHANGED")

-- ---------------------------------------------------------------------------
io.write("D. totems, and the pooled frame giving its alphas back\n")
local totem = Spawn("nameplate3", { guid = "Creature-T1", name = "Grounding Totem", player = false, friend = false })
NoErrors("totem plate added")
local tov = Overlay(totem)
CHECK(tov.totemIcon.__shown == true, "Grounding Totem drawn as an icon")
CHECK(tov.totemIcon.__texture == "Interface\\Icons\\Spell_8177", "...the Grounding Totem spell icon", tov.totemIcon.__texture)
CHECK(totem.UnitFrame.HealthBarsContainer.__alpha == 0, "Blizzard's bar hidden by alpha")
CHECK(totem.UnitFrame.name.__alpha == 0, "Blizzard's name hidden by alpha")
CHECK(totem.UnitFrame.__alpha == 1 or totem.UnitFrame.__alpha == nil, "a HIGH totem's plate stays visible")
Despawn("nameplate3")
CHECK(totem.UnitFrame.HealthBarsContainer.__alpha == 1, "bar alpha restored on removal")
CHECK(totem.UnitFrame.name.__alpha == 1, "name alpha restored on removal")
CHECK(tov.totemIcon.__shown == false and tov.__shown == false, "overlay hidden on removal")
-- The same pooled unit frame now carries a player
plates["nameplate3"].UnitFrame.unit = "nameplate3"
local reuse = Spawn("nameplate3", { guid = "Player-E2", name = "Nextguy", class = "WARRIOR", player = true, friend = false })
CHECK(reuse.UnitFrame.HealthBarsContainer.__alpha == 1 and reuse.UnitFrame.name.__alpha == 1, "the reused frame shows its new occupant's bar")
CHECK(Overlay(reuse) == tov, "the overlay is reused, not rebuilt")
CHECK(tov.totemIcon.__shown ~= true, "no totem icon on a warrior")
Despawn("nameplate3")
-- Scenery totem hidden when asked
CommanderPlatesDB.TotemHideLow = true
local searing = Spawn("nameplate4", { guid = "Creature-T2", name = "Searing Totem IV", player = false, friend = false })
CHECK(searing.UnitFrame.__alpha == 0, "Searing Totem faded out under Hide Scenery Totems")
Despawn("nameplate4")
CHECK(searing.UnitFrame.__alpha == 1, "...and the pooled frame's alpha comes back")
CommanderPlatesDB.TotemHideLow = false

-- Snake Trap and friendly fade
local snake = Spawn("nameplate6", { guid = "Creature-S1", name = "Venomous Snake", player = false, friend = false })
CHECK(snake.UnitFrame.__alpha == 0, "a Snake Trap snake's plate is faded out")
CommanderPlatesDB.HideNpcs = false
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(snake.UnitFrame.__alpha == 1, "...and back with the option off")
CommanderPlatesDB.HideNpcs = true
Despawn("nameplate6")
CHECK(snake.UnitFrame.__alpha == 1, "alpha restored on removal even while the option is on")
CommanderPlatesDB.FriendlyAlpha = 0.5
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(friend.UnitFrame.__alpha == 0.5, "friendly plate faded to the slider")
CHECK(enemy.UnitFrame.__alpha == 1 or enemy.UnitFrame.__alpha == nil, "enemy plate untouched")
CommanderPlatesDB.FriendlyAlpha = 1
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(friend.UnitFrame.__alpha == 1, "friendly plate back to full")
NoErrors("clutter section clean")

-- ---------------------------------------------------------------------------
io.write("E. the hit box under combat\n")
inCombatNow = true
enemy.__canChange = false      -- the client refuses tainted changes mid-fight
CommanderPlatesDB.HitBoxTop = 20
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
NoErrors("settings change in combat clean")
CHECK(enemy.__hit[1].offsetY ~= 25, "the refused change is not applied (" .. tostring(enemy.__hit[1].offsetY) .. ")")
enemy.__canChange = true
inCombatNow = false
Fire("PLAYER_REGEN_ENABLED")
CHECK(enemy.__hit[1].offsetY == 25 or enemy.__hit[1].offsetY == 20, "...and lands at REGEN (" .. tostring(enemy.__hit[1].offsetY) .. ")")
CommanderPlatesDB.HitBoxTop = 8
-- Friendly click-through in an instance
instanceType = "arena"
Fire("PLAYER_ENTERING_WORLD")
CommanderPlatesDB.FriendlyClickThrough = "INSTANCES"
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(friend.__hit[2].relativePoint == "TOPLEFT" and friend.__hit[2].offsetX == 0, "friendly plate given a zero-area hit box in an arena")
CHECK(enemy.__hit[2].relativePoint == "BOTTOMRIGHT", "enemy plate keeps a real box")
CommanderPlatesDB.FriendlyClickThrough = "NEVER"
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(friend.__hit[2].relativePoint == "BOTTOMRIGHT", "friendly box back to normal")

-- ---------------------------------------------------------------------------
io.write("F. disabling the module\n")
CommanderPlatesDB.Enable = false
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
NoErrors("disable clean")
CHECK(eov.__shown == false and ov.__shown == false, "overlays hidden")
CHECK(friend.UnitFrame.AurasFrame.__shown == true, "Blizzard's aura frame handed back")
local fc = friend.UnitFrame.healthBar.__color
CHECK(fc[1] == 0.67, "Blizzard's own colour restored (" .. table.concat(fc, ",") .. ")")
CHECK(friend.__hit.blizzard == true, "Blizzard's own hit box re-applied")
local late = Spawn("nameplate5", { guid = "Player-E3", name = "Latecomer", class = "MAGE", player = true, friend = false })
CHECK(late.__hit.blizzard == true and late.UnitFrame.AurasFrame.__shown == true, "a plate arriving while disabled is untouched")
CHECK(late.UnitFrame.healthBar.__color[1] == 0.67, "...and not recoloured")
CommanderPlatesDB.Enable = true
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(math.abs(late.UnitFrame.healthBar.__color[1] - 0.41) < 0.01, "re-enable recolours the live plates")
Despawn("nameplate5")

-- ---------------------------------------------------------------------------
io.write("G. arena numbers, healers, cast bar\n")
arena["arena1"] = "nameplate2"
Fire("ARENA_OPPONENT_UPDATE", "arena1", "seen")
CHECK(enemy.UnitFrame.name.__text == "1", "arena opponent named by number (" .. tostring(enemy.UnitFrame.name.__text) .. ")")
CommanderPlatesDB.ArenaNumbers = "PREFIX"
CompactUnitFrame_UpdateName(enemy.UnitFrame)
CHECK(enemy.UnitFrame.name.__text == "1 Gankmage", "PREFIX mode (" .. tostring(enemy.UnitFrame.name.__text) .. ")")
CompactUnitFrame_UpdateName(enemy.UnitFrame)
CHECK(enemy.UnitFrame.name.__text == "1 Gankmage", "...prefixed once, not twice")
CommanderPlatesDB.ArenaNumbers = "REPLACE"
arena["arena1"] = nil

CHECK(eov.healerIcon.__shown ~= true, "no healer cross before any heal is seen")
combatEvent = { now, "SPELL_HEAL", false, "Player-E1", "Gankmage", bit.bor(0x400, 0x40), 0, "Player-E4", "x", 0, 0, 2060, "Greater Heal" }
Fire("COMBAT_LOG_EVENT_UNFILTERED")
CHECK(eov.healerIcon.__shown == true, "Greater Heal from a hostile player -> healer cross on their plate")
combatEvent = { now, "SPELL_HEAL", false, "Player-F1", "Healbot", bit.bor(0x400, 0x10), 0, "Player-ME", "x", 0, 0, 2060, "Greater Heal" }
Fire("COMBAT_LOG_EVENT_UNFILTERED")
CHECK(ov.healerIcon.__shown ~= true, "a FRIENDLY healer gets no cross")

enemy.UnitFrame.CastBarsContainer.castBar.__shown = true
units.nameplate2.cast = { name = "Polymorph", icon = "Interface\\Icons\\Poly", startMS = now * 1000, endMS = (now + 1.5) * 1000 }
Tick(0.1)
NoErrors("cast tick clean")
CHECK(Ring(eov.castRing) == true, "Polymorph cast is emphasised")
CHECK(eov.castTimer.__shown == true and eov.castTimer.__text == "1.4", "cast timer reads remaining (" .. tostring(eov.castTimer.__text) .. ")")
units.nameplate2.cast = { name = "Frostbolt", icon = "Interface\\Icons\\Fb", startMS = now * 1000, endMS = (now + 2) * 1000 }
Tick(0.1)
CHECK(Ring(eov.castRing) ~= true, "Frostbolt is not emphasised")
-- Cast bar colour
local ecb = enemy.UnitFrame.CastBarsContainer.castBar
ecb:UpdateBarFillTexture(false)
CHECK(ecb.__texture == "blizzard-atlas", "DEFAULT leaves Blizzard's fill alone")
CommanderPlatesDB.CastBarColor = "REACTION"
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(ecb.__texture ~= "blizzard-atlas" and ecb.__color[1] == 0.95, "REACTION: plain fill, hostile red (" .. tostring(ecb.__texture) .. ")")
ecb:UpdateBarFillTexture(false)   -- Blizzard repaints on a cast start...
CHECK(ecb.__color[1] == 0.95 and ecb.__texture ~= "blizzard-atlas", "...and the hook re-tints straight after")
local fcb = friend.UnitFrame.CastBarsContainer.castBar
CHECK(fcb.__color[3] == 1 and fcb.__color[1] == 0.35, "friendly cast bar in friendly blue")
CommanderPlatesDB.CastBarColor = "DEFAULT"
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(ecb.__texture == "blizzard-atlas" and ecb.__color[1] == 1, "back to DEFAULT hands the fill back to Blizzard")
ecb:UpdateBarFillTexture(false)
CHECK(ecb.__texture == "blizzard-atlas", "...and the hook stays quiet")
CommanderPlatesDB.CastIconSize = 28
CommanderPlatesDB.CastEmphasisExtra = "Frostbolt"
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
units.nameplate2.cast = { name = "Frostbolt", icon = "Interface\\Icons\\Fb", startMS = now * 1000, endMS = (now + 2) * 1000 }
enemy.UnitFrame.CastBarsContainer.castBar.__shown = false
Tick(0.1)
enemy.UnitFrame.CastBarsContainer.castBar.__shown = true
Tick(0.1)
CHECK(Ring(eov.castRing) == true, "user-added emphasis works")
CHECK(eov.castIcon.__shown == true and enemy.UnitFrame.CastBarsContainer.castBar.Icon.__alpha == 0, "big cast icon replaces Blizzard's")
enemy.UnitFrame.CastBarsContainer.castBar.__shown = false
units.nameplate2.cast = nil
Tick(0.1)
CHECK(eov.castIcon.__shown == false and enemy.UnitFrame.CastBarsContainer.castBar.Icon.__alpha == 1, "cast over: icon alpha given back")
CommanderPlatesDB.CastIconSize = 0
CommanderPlatesDB.CastEmphasisExtra = ""

-- CVars
cvarWrites = {}
CommanderPlates_ApplyCVars(false)
CHECK(#cvarWrites == #CommanderPlates_Data.CVARS, "every profile CVar written (" .. #cvarWrites .. ")")
CHECK(cvars.nameplateShowOnlyNameForFriendlyPlayerUnits == "0" and cvars.nameplateShowAll == "1", "bool CVars written as 0/1")
inCombatNow = true
cvarWrites = {}
CommanderPlates_ApplyCVars(false)
CHECK(#cvarWrites == 0, "no CVar writes in combat")
inCombatNow = false
Fire("PLAYER_REGEN_ENABLED")
CHECK(#cvarWrites == #CommanderPlates_Data.CVARS, "...deferred to REGEN")
cvars.nameplateMaxDistance = "30"
CommanderPlates_ReadCVars()
CHECK(CommanderPlatesDB.CvMaxDistance == 30, "Read From Game imports the client's value")

-- Name text modes
CommanderPlatesDB.EnemyNameText = "CLASS"
CompactUnitFrame_UpdateName(enemy.UnitFrame)
CHECK(enemy.UnitFrame.name.__text == "MAGE", "enemy name as class (" .. tostring(enemy.UnitFrame.name.__text) .. ")")
CommanderPlatesDB.EnemyNameText = "NONE"
CompactUnitFrame_UpdateName(enemy.UnitFrame)
CHECK(enemy.UnitFrame.name.__text == "", "enemy name blanked")
arena["arena1"] = "nameplate2"
CommanderPlatesDB.ArenaNumbers = "PREFIX"
Fire("ARENA_OPPONENT_UPDATE", "arena1", "seen")
CHECK(enemy.UnitFrame.name.__text == "1", "PREFIX on a blank name is just the number (" .. tostring(enemy.UnitFrame.name.__text) .. ")")
arena["arena1"] = nil
Fire("ARENA_OPPONENT_UPDATE", "arena1", "cleared")
CommanderPlatesDB.ArenaNumbers = "REPLACE"
CommanderPlatesDB.EnemyNameText = "NAME"
CompactUnitFrame_UpdateName(enemy.UnitFrame)
CHECK(enemy.UnitFrame.name.__text == "Gankmage", "name restored once the seat is cleared (" .. tostring(enemy.UnitFrame.name.__text) .. ")")
CHECK(friend.UnitFrame.name.__text == "Healbot", "friendly name untouched by the enemy setting")

-- DR badge through Commander Diminish's accessor
function CommanderDiminish_Brackets(guid, spellId)
    if guid == "Player-E1" and spellId == 1833 then return 2, 3, "STUN" end
    if guid == "Player-E1" and spellId == 118 then return 3, 4, "POLY" end
end
units.nameplate2.debuffs = { Aura("Cheap Shot", 1833, 3, 4, false) }
Fire("UNIT_AURA", "nameplate2")
CHECK(eov.big.badge.__shown == true and eov.big.badge.__text == "\194\189", "half bracket badge (" .. tostring(eov.big.badge.__text) .. ")")
units.nameplate2.debuffs = { Aura("Polymorph", 118, 3, 4, false) }
Fire("UNIT_AURA", "nameplate2")
CHECK(eov.big.badge.__text == "\194\188X", "quarter, and next is immune (" .. tostring(eov.big.badge.__text) .. ")")
CommanderPlatesDB.CcDrBadge = false
Fire("UNIT_AURA", "nameplate2")
CHECK(eov.big.badge.__shown == false, "badge off")
CommanderPlatesDB.CcDrBadge = true
CommanderDiminish_Brackets = nil
Fire("UNIT_AURA", "nameplate2")
CHECK(eov.big.badge.__shown == false, "no Diminish, no badge, no error")
NoErrors("badge path clean")

-- Urgent timer
Tick(0.1)
CHECK(eov.big.timer.__color and eov.big.timer.__color[1] == 1 and eov.big.timer.__color[2] < 0.5, "timer red under three seconds")
units.nameplate2.debuffs = { Aura("Polymorph", 118, 8, 8, false) }
Fire("UNIT_AURA", "nameplate2")
Tick(0.1)
CHECK(eov.big.timer.__color[2] == 1, "timer white with eight seconds left")

-- Track only in instances
instanceType = nil
Fire("PLAYER_ENTERING_WORLD")
CommanderPlatesDB.TrackWhere = "INSTANCES"
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(eov.big.__shown == false and ShownIcons(eov) == 0, "outside an instance, INSTANCES hides the aura layer")
CHECK(eov.targetHalo.top.__shown == true, "...but the target glow stays")
instanceType = "pvp"
Fire("PLAYER_ENTERING_WORLD")
CHECK(eov.big.__shown == true, "entering a battleground brings it back")
CommanderPlatesDB.TrackWhere = "ALWAYS"
instanceType = nil
Fire("PLAYER_ENTERING_WORLD")
units.nameplate2.debuffs = {}

Despawn("nameplate1"); Despawn("nameplate2")
NoErrors("teardown clean")

-- ---------------------------------------------------------------------------
io.write("R. the radial plate\n")
-- The unit reads a disc needs and the bar never did
function UnitHealth(unit) local u = U(unit); return u and (u.hp or u.maxhp or 9000) or 0 end
function UnitPowerType(unit) local u = U(unit); local t = u and u.ptype or "MANA"; return 0, t end
function UnitPower(unit) local u = U(unit); return u and (u.power or 50) or 0 end
function UnitPowerMax(unit) local u = U(unit); return u and (u.maxpower or 100) or 0 end
function UnitLevel(unit) local u = U(unit); return u and (u.level or 70) or 0 end
function UnitClassification(unit) local u = U(unit); return u and u.classification or "normal" end
function GetRaidTargetIndex(unit) local u = U(unit); return u and u.raid end
function UnitThreatSituation(_, unit) local u = U(unit); return u and u.threat end
function UnitGetIncomingHeals(unit) local u = U(unit); return u and u.incoming or 0 end
local comboPoints = 0
function GetComboPoints() return comboPoints end
function SetPortraitTexture(tex, unit) tex.__portrait = unit; tex.__texture = "portrait:" .. tostring(unit) end
function GetCreatureDifficultyColor() return { r = 1, g = 1, b = 0 } end
local interruptedFired = false

local function Radial(plate) local o = Overlay(plate); return o and o.radial end
-- A frozen arc's fraction, read back off the cooldown it was set as: an
-- unreversed cooldown paints what REMAINS, so the fraction is the remainder
local function ArcFraction(arc)
    if arc.full.__shown then return 1 end
    if not arc.cd.__shown or not arc.cd.__cdDur then return 0 end
    return 1 - (now - arc.cd.__cdStart) / arc.cd.__cdDur
end
local function Near(a, b, eps) return math.abs((a or -99) - b) < (eps or 0.01) end

CommanderPlatesDB.PlateStyle = "RADIAL"
CommanderPlatesDB.RadialUnits = "ALL"
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
NoErrors("switching to radial runs clean")

local rm = Spawn("nameplate4", { guid = "Player-R1", name = "Gankmage", class = "MAGE", player = true, friend = false,
    hp = 60, maxhp = 100, power = 50, maxpower = 100, ptype = "MANA" })
NoErrors("a radial plate arrives clean")
local rov = Overlay(rm)
local w = Radial(rm)
CHECK(w ~= nil and w.__shown == true, "the disc is built and shown")
CHECK(rm.UnitFrame.HealthBarsContainer.__alpha == 0, "Blizzard's bar goes to alpha 0 under the disc")
CHECK(rm.UnitFrame.name.__alpha == 0, "...its name too")
CHECK(rm.UnitFrame.CastBarsContainer.__alpha == 0, "...and its cast bar")
CHECK(rm.UnitFrame.AurasFrame.__shown == false, "Blizzard's aura icons stay down under a disc")
CHECK(rov.icons[1] == nil or rov.icons[1].__shown == false, "no bar-mode aura rows on a disc")
CHECK(w.core.__texture == CommanderPlates_Data.CLASS_ICON, "the face is the class emblem", w.core.__texture)
CHECK(Near(ArcFraction(w.healthArc), 0.6), "health ring at 60%", ArcFraction(w.healthArc))
CHECK(w.healthArc.cd.__reverse == false, "health ring ends at twelve and drains clockwise (an unreversed sweep)")
CHECK(Near(ArcFraction(w.powerArc), 0.5), "mana ring at 50%", ArcFraction(w.powerArc))
CHECK(w.nameText.__text == "Gankmage" and w.nameText.__shown, "the name under the disc")
CHECK(w.backdrop.__shown == true and w.backdrop.__color[4] == CommanderPlatesDB.RadialBackdropAlpha, "a backdrop behind the disc")
CHECK(w.backdropRim.__shown == true, "...with a border")
local cfgNow = CommanderPlates_Radial.Config(function(k) return CommanderPlatesDB[k] end)
CHECK(w.backdrop.__w > cfgNow.radii.outer * 2, "...larger than every ring")
local function OffRings(tex)
    local pt = tex.__points and tex.__points[1]
    return pt and math.sqrt(pt.x * pt.x + pt.y * pt.y) - (tex.__w or 0) / 2 >= cfgNow.radii.outer - 0.01
end
CHECK(OffRings(w.raid) and OffRings(w.healer) and OffRings(w.trinket) and OffRings(w.classBadge), "no badge sits on the rings")
CommanderPlatesDB.RadialBackdropAlpha = 0
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(w.backdrop.__shown == false, "backdrop opacity 0: no backdrop")
CommanderPlatesDB.RadialBackdropAlpha = 0.6
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(w.centerText.__text == "60", "SMART centre text: the percent once hurt", w.centerText.__text)

-- A number on the face has to be readable whatever the face is. The outline
-- alone is a hairline at these sizes -- white on a white class icon had an
-- edge nobody could find and nothing inside it -- so every number carries a
-- hard black shadow, and the face goes dark under it while it is there.
do
    local function Shadowed(fs)
        return fs.__shadow and fs.__shadow[1] == 1 and fs.__shadow[2] == -1
            and fs.__shadowColor and fs.__shadowColor[1] == 0 and fs.__shadowColor[4] == 1
    end
    CHECK(Shadowed(w.centerText), "the number in the middle carries a black shadow under its outline")
    CHECK(Shadowed(w.drBadge) and Shadowed(w.nameText) and Shadowed(w.castText) and Shadowed(w.levelText),
        "and so does every other piece of text on the plate")
    local orbit = CommanderPlates_Radial.NewOrbitIcon(UIParent)
    CHECK(Shadowed(orbit.timer) and Shadowed(orbit.count) and Shadowed(orbit.badge),
        "an aura's timer and stacks are written on its own icon, and are shadowed too")
    CHECK(w.shade.__shown == true, "the face is shaded while a number is written on it")
    CHECK(w.shade.__color and w.shade.__color[1] == 0 and w.shade.__color[4] == 0.45,
        "black, at the strength the setting asks for", w.shade.__color and w.shade.__color[4])
    local radii = CommanderPlates_Radial.Config(function(k) return CommanderPlatesDB[k] end).radii
    CHECK(w.shade.__w == radii.core * 2, "over the face and nothing else: it stops short of the rings",
        tostring(w.shade.__w) .. " vs " .. tostring(radii.core * 2))
    CommanderPlatesDB.RadialTextShade = 0
    Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
    CHECK(w.centerText.__shown == true and w.shade.__shown == false,
        "at 0 the picture is left alone and the number stays")
    CommanderPlatesDB.RadialTextShade = 0.45
    Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
    CHECK(w.shade.__shown == true, "and it comes back with the setting")

    -- ...and how big it is written is the player's to say. Auto is the size
    -- the face implies; a number is that many points whatever the plate does.
    local auto = math.max(8, math.floor(radii.core * 0.85))
    CHECK(w.centerText.__font and w.centerText.__font[2] == auto, "Auto sizes the number off the face",
        w.centerText.__font and w.centerText.__font[2])
    CommanderPlatesDB.RadialCoreTextSize = 18
    Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
    CHECK(w.centerText.__font[2] == 18, "a set size is that size", w.centerText.__font[2])
    CHECK(w.drBadge.__font[2] == math.floor(18 * 0.65), "and the DR bracket keeps its proportion to it",
        w.drBadge.__font[2])
    CommanderPlatesDB.RadialCoreTextSize = 0
    Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
    CHECK(w.centerText.__font[2] == auto, "back to Auto, back to the face's size", w.centerText.__font[2])
end
CHECK(rm.__hit and rm.__hit[1].relativePoint == "CENTER" and rm.__hit[1].offsetX < 0, "hit box is the disc, from the bar's centre")
local half = CommanderPlates_Radial.Config(function(k) return CommanderPlatesDB[k] end).radii.outer
CHECK(Near(rm.__hit[2].offsetX, half + (CommanderPlatesDB.HitBoxSides or 0)), "...as wide as the disc", rm.__hit[2].offsetX)

-- An arena number replaces the percent in the middle
arena["arena2"] = "nameplate4"
Fire("ARENA_OPPONENT_UPDATE")
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(w.centerText.__text == "2", "in an arena the middle is the arena number", w.centerText.__text)
CHECK(w.nameText.__text == "2", "...and the name follows ArenaNumbers = REPLACE", w.nameText.__text)
arena["arena2"] = nil
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)

-- Health drops: low-health colour and the damage trail
units.nameplate4.hp = 30
Fire("UNIT_HEALTH", "nameplate4")
CHECK(Near(ArcFraction(w.healthArc), 0.3), "UNIT_HEALTH moves the ring to 30%")
local hc = w.healthArc.cd.__color or {}
local swipe = w.healthArc.cd
CHECK(w.trailArc.cd.__shown == true and Near(ArcFraction(w.trailArc), 0.6), "the trail holds the lost 30% for a moment", ArcFraction(w.trailArc))
for _ = 1, 30 do Tick(0.1); PumpFrame(w, 0.1) end
CHECK(w.trailArc.cd.__shown == false, "...then drains away")
CHECK(w:GetScript("OnUpdate") == nil, "the animation clock stops once nothing moves")
CHECK(w.centerText.__text == "30", "centre text follows health")

-- Execute marker on the ring
CommanderPlatesDB.HealthMarkerPercent = 25
Fire("UNIT_MAXHEALTH", "nameplate4")
CHECK(w.ticks.pct.__shown == true, "the Execute marker is a tick on the ring")
local tp = w.ticks.pct.__points and w.ticks.pct.__points[1]
CHECK(tp and tp.x < -1 and math.abs(tp.y) < 0.01, "...at nine o'clock for 25%: where the clockwise-draining edge will be", tp and (tp.x .. "," .. tp.y))
CommanderPlatesDB.HealthMarkerPercent = 0
Fire("UNIT_MAXHEALTH", "nameplate4")
CHECK(w.ticks.pct.__shown == false, "...and goes with the setting")

-- Auras orbit: a debuff at the top of the disc
units.nameplate4.debuffs = { Aura("Corruption", 172, 12, 18, true) }
Fire("UNIT_AURA", "nameplate4")
local orb = rov.orbitRound[1]
CHECK(orb ~= nil and orb.__shown == true, "my Corruption orbits the disc")
local p = orb and orb.__points and orb.__points[1]
CHECK(p and Near(p.x, 0, 0.5) and p.y > half, "...centred over the top, outside the rings", p and (p.x .. "," .. p.y))
CHECK(orb and orb.round == true, "...as a round icon")
-- Debuffs over the top, buffs down the right: the two arcs never share a side
units.nameplate4.buffs = { Aura("Arcane Power", 12042, 10, 15, false, { isStealable = true }) }
Fire("UNIT_AURA", "nameplate4")
local dp1 = rov.orbitRound[1].__points[1]
local bp1 = rov.orbitRound[2] and rov.orbitRound[2].__points and rov.orbitRound[2].__points[1]
CHECK(dp1 and dp1.y > half and math.abs(dp1.x) < 1, "the debuff sits at twelve")
CHECK(bp1 and bp1.x > half and math.abs(bp1.y) < 1, "the notable buff sits at three", bp1 and (bp1.x .. "," .. bp1.y))
CommanderPlatesDB.RadialBuffArc = "BOTTOM"
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
bp1 = rov.orbitRound[2].__points[1]
CHECK(bp1.y < -half and math.abs(bp1.x) < 1, "Buffs Orbit = Bottom moves them to six", bp1.x .. "," .. bp1.y)
CommanderPlatesDB.RadialBuffArc = "RIGHT"
units.nameplate4.buffs = {}
Fire("UNIT_AURA", "nameplate4")
-- The backdrop is sized by its own setting
local cfgB = CommanderPlates_Radial.Config(function(k) return CommanderPlatesDB[k] end)
local before = w.backdrop.__w
CommanderPlatesDB.RadialBackdropSize = 20
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(Near(w.backdrop.__w, (cfgB.radii.outer + 20) * 2), "Backdrop Size +20 reaches 20px past the rings", w.backdrop.__w)
CommanderPlatesDB.RadialBackdropSize = -40
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(Near(w.backdrop.__w, (cfgB.radii.core + 1) * 2), "...and pulled all the way in it stops at the face", w.backdrop.__w)
CommanderPlatesDB.RadialBackdropSize = 2
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(Near(w.backdrop.__w, before), "...and back")
CommanderPlatesDB.RadialRoundAuras = false
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(rov.orbitSquare[1] and rov.orbitSquare[1].__shown == true and orb.__shown == false, "Round Icons off swaps in square ones")
CommanderPlatesDB.RadialRoundAuras = true
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)

-- A cast: the arc sweeps, the face turns into the spell, the name line reads it
units.nameplate4.cast = { name = "Polymorph", icon = "Interface\\Icons\\Poly", startMS = now * 1000, endMS = (now + 1.5) * 1000 }
Tick(0.1)
CHECK(w.castArc.cd.__shown == true and Near(w.castArc.cd.__cdDur, 1.5), "the cast sweeps the outer ring")
CHECK(w.castArc.cd.__reverse == true, "...filling, since it is a cast")
CHECK(w.core.__texture == "Interface\\Icons\\Poly", "the face becomes the spell", w.core.__texture)
CHECK(w.castText.__text == "Polymorph" and w.castText.__shown, "the spell's name under the unit's")
CHECK(w.alert.__shown == true, "an emphasised cast lights the warning halo")
CHECK(w.spark.__shown == true and w:GetScript("OnUpdate") ~= nil, "the spark rides the sweep")
CHECK(w.centerText.__text == "30", "a cast never takes the health number's place", w.centerText.__text)
CHECK(w.subText.__shown and tonumber(w.subText.__text) ~= nil, "...its seconds count down on the small line under it", w.subText.__text)
local subPoint = w.subText.__points and w.subText.__points[1]
CHECK(subPoint and subPoint.y < 0 and w.centerText.__points[1].y == 0, "...below the middle, the number still on it")
local castR = w.castArc.track.__w and (w.castArc.track.__w * CommanderPlates_Radial.RING_OUTER)
CHECK(castR and castR - 3 - cfgB.radii.health >= 2, "the cast ring floats 2px off the plate", castR)
units.nameplate4.cast = nil
Tick(0.1)
CHECK(w.castArc.cd.__shown == false and w.core.__texture == CommanderPlates_Data.CLASS_ICON, "cast over: ring clear, face back to the class")
CHECK(w.alert.__shown == false and w.castText.__shown == false, "...halo and spell name gone")
CHECK(w.subText.__shown == false and w.centerText.__text == "30", "...the clock line goes, the number stays put")

-- A kick
Fire("UNIT_SPELLCAST_INTERRUPTED", "nameplate4")
CHECK(w.flash.__shown == true and w.castText.__text == "Interrupted", "an interrupt bursts on the ring")
for _ = 1, 10 do PumpFrame(w, 0.1); now = now + 0.1 end
CHECK(w.flash.__shown == false and w.castText.__shown == false, "...and fades")

-- Control takes the face
units.nameplate4.debuffs = { Aura("Corruption", 172, 12, 18, true), Aura("Cheap Shot", 1833, 3, 4, false) }
Fire("UNIT_AURA", "nameplate4")
CHECK(w.core.__texture == "Interface\\Icons\\Cheap Shot", "a stun takes the face", w.core.__texture)
CHECK(w.centerText.__text == "30", "...but never the health number", w.centerText.__text)
CHECK(w.subText.__shown and w.subText.__text ~= "", "...its seconds go on the line under it", w.subText.__text)
CHECK(w.wipe[1].__shown == true and w.wipe[2].__shown == true and w.coreCd.__shown == false, "...its countdown a clock wipe over it, not a Cooldown")
CHECK(w.wipe[1].__layer == "BACKGROUND" and w.coreCd:GetFrameLevel() < w.healthArc.cd:GetFrameLevel(), "...drawn beneath every ring")
CHECK(Near(w.wipe[1].__w, (half2core or w.core.__w) / 2 / 0.46, 0.01), "...the wipe's disc exactly the face's size", w.wipe[1].__w)
CHECK(w.rim.__color and w.rim.__color[1] == 1 and w.rim.__color[2] == 0.85, "...the rim in the stun's colour")
CHECK(rov.big.__shown == false, "...and the floating big icon stays away")
local orbited = 0
for _, f in ipairs(rov.orbitRound) do if f.__shown then orbited = orbited + 1 end end
EQ(orbited, 1, "the stun is not drawn twice (only Corruption orbits)")
CommanderPlatesDB.RadialCoreCC = false
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(rov.big.__shown == true and w.core.__texture == CommanderPlates_Data.CLASS_ICON, "Control-becomes-face off: the big icon floats instead")
CHECK(rov.big.__points[1].rel == w and rov.big.__points[1].y > half, "...above the disc")
CommanderPlatesDB.RadialCoreCC = true
units.nameplate4.debuffs = {}
Fire("UNIT_AURA", "nameplate4")
CHECK(w.core.__texture == CommanderPlates_Data.CLASS_ICON and w.wipe[1].__shown == false, "control over: the face comes back, wipe gone")

-- Target: glow, arrows, bigger, combo points
comboPoints = 3
playerTarget = "nameplate4"
Fire("PLAYER_TARGET_CHANGED")
-- Blizzard shows its selection highlight -- a bar-shaped texture that
-- ignores parent alpha -- the moment the unit is targeted. Under a disc it
-- has to stay down, or a faint bar pokes out either side of it.
rm.UnitFrame.selectionHighlight:Show()
CHECK(rm.UnitFrame.selectionHighlight.__shown == false, "Blizzard's selection highlight is kept hidden under a disc")
rm.UnitFrame.selectionHighlight:SetShown(true)
CHECK(rm.UnitFrame.selectionHighlight.__shown == false, "...through SetShown too")
rm.UnitFrame.aggroHighlightBase:SetShown(true)
CHECK(rm.UnitFrame.aggroHighlightBase.__shown == false, "...and the aggro flare over the bar")
CHECK(w.glow.__shown == true, "the target glows")
CHECK(w.arrowL.__shown == true and w.arrowR.__shown == true, "...with arrows either side")
CHECK(w.__scale == CommanderPlatesDB.RadialTargetScale, "...drawn bigger", w.__scale)
local lit = 0
for _, pip in ipairs(w.pips) do if pip.__shown and pip.__color and pip.__color[2] > 0.5 then lit = lit + 1 end end
EQ(lit, 3, "three combo points lit")
playerTarget = nil
comboPoints = 0
Fire("PLAYER_TARGET_CHANGED")
CHECK(w.glow.__shown == false and w.arrowL.__shown == false and w.__scale == 1, "untargeted: back to normal")

-- The glow: ten styles, every one on disk, sized from the plate's edge,
-- and a motion that only runs while it is up
for _, key in ipairs(CommanderPlates_Radial.GLOW_ORDER) do
    local file = CommanderPlates_Radial.GLOW_STYLES[key]:gsub("^Interface\\AddOns\\", ADDONS .. "/"):gsub("\\", "/")
    local fh = io.open(file, "rb")
    CHECK(fh ~= nil, "glow art on disk: " .. key, file)
    if fh then fh:close() end
    CHECK(CommanderPlates_Radial.GLOW_LABEL[key] ~= nil, "glow style has a name: " .. key)
end
CommanderPlatesDB.RadialGlowStyle = "STORM"
CommanderPlatesDB.RadialGlowMotion = "SPIN"
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
playerTarget = "nameplate4"
Fire("PLAYER_TARGET_CHANGED")
CHECK(w.glow.__texture and w.glow.__texture:find("GlowStorm.png", 1, true), "Target Glow Style picks the art", w.glow.__texture)
local cfgG = CommanderPlates_Radial.Config(function(k) return CommanderPlatesDB[k] end)
local edgeG = math.max(cfgG.radii.outer, cfgG.radii.outer + CommanderPlatesDB.RadialBackdropSize)
CHECK(Near(w.glow.__w, (edgeG + 1) / 0.28), "the glow rises from the backdrop's edge", w.glow.__w)
now = now + 1
PumpFrame(w, 0.1)
CHECK(w.glow.__rot and w.glow.__rot ~= 0, "Spin turns it", w.glow.__rot)
CommanderPlatesDB.RadialGlowSize = 1.5
CommanderPlatesDB.RadialGlowMotion = "PULSE"
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(Near(w.glow.__w, (edgeG + 1) / 0.28 * 1.5), "Glow Size scales it", w.glow.__w)
now = now + 0.37
PumpFrame(w, 0.1)
CHECK(w.glow.__alpha and w.glow.__alpha < 1 and w.glow.__alpha >= 0.65, "Pulse breathes it", w.glow.__alpha)
playerTarget = nil
Fire("PLAYER_TARGET_CHANGED")
CHECK(w.glow.__shown == false and not w.glowLive, "untargeted: the glow and its motion stop")
CommanderPlatesDB.RadialGlowStyle, CommanderPlatesDB.RadialGlowMotion, CommanderPlatesDB.RadialGlowSize = "SOFT", "NONE", 1.0
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)

-- A healer cross on the rim
combatEvent = { 0, "SPELL_HEAL", false, "Player-R1", "Gankmage", 0x400 + 0x40, 0, "x", "y", 0, 0, 0, "Flash Heal" }
Fire("COMBAT_LOG_EVENT_UNFILTERED")
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(w.healer.__shown == true, "a caught healer wears the cross on the rim")

-- An NPC: portrait, level, elite rim, raid marker, threat
local elite = Spawn("nameplate5", { guid = "Creature-E1", name = "Ogre Mauler", player = false, friend = false,
    classification = "elite", level = 63, raid = 8, threat = 1, hp = 9000, maxhp = 9000 })
local ew = Radial(elite)
CHECK(ew and ew.core.__portrait == "nameplate5", "an NPC's face is its portrait")
CHECK(ew.levelText.__text == "63+", "level on the rim with the elite +", ew.levelText.__text)
CHECK(ew.rim.__color and ew.rim.__color[1] == 1 and ew.rim.__color[2] == 0.82, "elite rim in gold")
CHECK(ew.raid.__shown == true, "the skull on the rim")
CHECK(ew.alert.__shown == true and ew.alert.__color[2] > 0.4, "threat 1 (about to pull) glows orange for a damage dealer")
units.nameplate5.threat = 3
Fire("UNIT_THREAT_LIST_UPDATE", "nameplate5")
CHECK(ew.alert.__color[2] < 0.4, "...red once it has turned")
CommanderPlatesDB.RadialThreat = "TANK"
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(ew.alert.__shown == false, "a tank holding it sees nothing")
CommanderPlatesDB.RadialThreat = "DPS"
units.nameplate5.raid = nil
Fire("RAID_TARGET_UPDATE")
CHECK(ew.raid.__shown == false, "raid marker cleared")
CHECK(ew.centerText.__shown == false, "SMART: nothing in the middle at full health")
CHECK(ew.shade.__shown == false, "...and with no number on it, the face is not darkened")

-- Totems keep their own look
local rt = Spawn("nameplate6", { guid = "Creature-T9", name = "Grounding Totem", player = false, friend = false })
local rtov = Overlay(rt)
CHECK(rtov.radial == nil or rtov.radial.__shown == false, "a totem never becomes a disc")
CHECK(rtov.totemIcon.__shown == true and rt.UnitFrame.HealthBarsContainer.__alpha == 0, "...it stays an icon, exactly as before")

-- Scope: enemy players only
CommanderPlatesDB.RadialUnits = "ENEMY_PLAYERS"
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(ew.__shown == false and elite.UnitFrame.HealthBarsContainer.__alpha == 1, "ENEMY_PLAYERS: the NPC gets its bar back")
CHECK(elite.UnitFrame.name.__alpha == 1 and elite.UnitFrame.CastBarsContainer.__alpha == 1, "...name and cast bar too")
CHECK(w.__shown == true, "...the enemy mage stays a disc")
CommanderPlatesDB.RadialUnits = "ALL"
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(ew.__shown == true and elite.UnitFrame.HealthBarsContainer.__alpha == 0, "ALL again: the NPC is a disc again")

-- A pooled frame's next occupant: the disc leaves with the unit
Despawn("nameplate5")
CHECK(elite.UnitFrame.HealthBarsContainer.__alpha == 1 and elite.UnitFrame.name.__alpha == 1, "removal hands the bar back")
CHECK(ew.__shown == false, "...and hides the disc")
local again = Spawn("nameplate5", { guid = "Creature-W1", name = "Wolf", player = false, friend = false, hp = 50, maxhp = 100 })
CHECK(Radial(again) == ew and ew.__shown == true and Near(ArcFraction(ew.healthArc), 0.5), "the next occupant reuses the disc with its own health")
CHECK(ew.trailArc.cd.__shown == false, "...and inherits no damage trail")

-- Diminishing returns round an enemy disc, from Commander Diminish
local drOpen = {}
function CommanderDiminish_Open(guid) if guid == "Player-R1" then return drOpen end end
drOpen[1] = { cat = "STUN", bracket = 2, held = false, resetAt = now + 10, last = 1833 }
Fire("UNIT_AURA", "nameplate4")
CHECK(w.drIcons and w.drIcons[1] and w.drIcons[1].__shown == true, "an open stun category orbits the disc")
CHECK(w.drIcons[1].timer.__text == "\194\189", "...labelled with what the next stun would do")
CHECK(w.drIcons[1].cd.__shown and w.drIcons[1].cd.__reverse == false and Near(w.drIcons[1].cd.__cdDur, 15), "...its reset sweeping away")
local dp = w.drIcons[1].__points[1]
CHECK(dp and dp.x < 0, "...on the left, by default")
drOpen[1] = nil
for _ = 1, 6 do Tick(0.1) end
CHECK(w.drIcons[1].__shown == false, "reset: the icon goes on the next slow tick")
CommanderDiminish_Open = nil

-- Who the cast is aimed at
units.nameplate4.target = "player"
local realU2 = U
U = function(unit)
    local base = unit:match("^(nameplate%d+)target$")
    if base then
        local u = realU2(base)
        if u and u.target == "player" then return realU2("player") end
        return u and u.target and realU2(u.target) or nil
    end
    return realU2(unit)
end
units.nameplate4.cast = { name = "Fear", icon = "Interface\\Icons\\Fear", startMS = now * 1000, endMS = (now + 1.5) * 1000 }
Tick(0.1)
CHECK(w.castText.__text and w.castText.__text:find("Fear \194\187 |cffff4040YOU|r", 1, true), "the cast line says it is coming for YOU", w.castText.__text)
units.nameplate4.target = "nameplate5"
Tick(0.1)
CHECK(w.castText.__text and w.castText.__text:find("Wolf", 1, true), "...and follows a mid-cast target swap", w.castText.__text)
CommanderPlatesDB.RadialCastTarget = false
units.nameplate4.cast.endMS = (now + 1.6) * 1000
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
Tick(0.1)
CHECK(w.castText.__text == "Fear", "the target tail goes with its setting", w.castText.__text)
CommanderPlatesDB.RadialCastTarget = true
units.nameplate4.cast, units.nameplate4.target = nil, nil
U = realU2
Tick(0.1)

-- Targeting you, the arena trinket, and a corpse
units.nameplate4.target = "player"
U = function(unit)
    local base = unit:match("^(nameplate%d+)target$")
    if base then
        local u = realU2(base)
        if u and u.target == "player" then return realU2("player") end
        return u and u.target and realU2(u.target) or nil
    end
    return realU2(unit)
end
Fire("UNIT_TARGET", "nameplate4")
CHECK(w.youRing.__shown == true and w.youRing.__color[1] == 1 and w.youRing.__color[2] == 0.25, "an enemy player targeting you wears the red ring")
units.nameplate4.target = nil
Fire("UNIT_TARGET", "nameplate4")
CHECK(w.youRing.__shown == false, "...gone when they look away")
U = realU2

local trinketState = { 42292, 0, 0 }
C_PvP = { GetArenaCrowdControlInfo = function(unit) if unit == "arena2" then return unpack(trinketState) end end,
          RequestCrowdControlSpell = function() end }
arena["arena2"] = "nameplate4"
Fire("ARENA_OPPONENT_UPDATE")
CHECK(w.trinket.__shown == true and w.trinket.icon.__texture == "Interface\\Icons\\Spell_42292", "arena seat 2: its trinket on the rim", w.trinket.icon.__texture)
CHECK(w.trinket.border.__color[2] == 1 and w.trinket.cd.__shown == false, "...ready: green, no sweep")
trinketState = { 42292, now * 1000, 120000 }
Fire("ARENA_CROWD_CONTROL_SPELL_UPDATE", "arena2")
CHECK(w.trinket.cd.__shown == true and Near(w.trinket.cd.__cdDur, 120) and w.trinket.icon.__desat == true, "used: greyed, two minutes sweeping")
arena["arena2"] = nil
Fire("ARENA_OPPONENT_UPDATE")
CHECK(w.trinket.__shown == false, "out of the arena seat: no trinket")
C_PvP = nil

units.nameplate4.dead, units.nameplate4.hp = true, 0
Fire("UNIT_HEALTH", "nameplate4")
CHECK(w.core.__desat == true and w.centerText.__text == "Dead", "a corpse: grey face, 'Dead' in the middle")
units.nameplate4.dead, units.nameplate4.hp = nil, 60
Fire("UNIT_HEALTH", "nameplate4")
CHECK(w.core.__desat == false and w.centerText.__text == "60", "...and alive again (a resurrect)")
NoErrors("targets-you, trinket and corpse clean")

-- Stacking: the plates sized to the disc, and handed back
local sizes = {}
C_NamePlate.SetNamePlateEnemySize = function(w2, h2) sizes.enemy = { w2, h2 } end
C_NamePlate.SetNamePlateFriendlySize = function(w2, h2) sizes.friend = { w2, h2 } end
local driverPasses = 0
NamePlateDriverFrame = { UpdateNamePlateOptions = function() driverPasses = driverPasses + 1 end }
CommanderPlatesDB.RadialStacking = true
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(sizes.enemy and sizes.enemy[2] > sizes.enemy[1] - 30 and sizes.friend, "Stack Plates By The Disc sizes enemy and friendly plates", sizes.enemy and table.concat(sizes.enemy, "x"))
inCombatNow = true
sizes.enemy = nil
CommanderPlatesDB.RadialSize = 60
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(sizes.enemy == nil, "...never in combat")
inCombatNow = false
Fire("PLAYER_REGEN_ENABLED")
CHECK(sizes.enemy ~= nil, "...applied as combat ends")
CommanderPlatesDB.RadialSize = 46
CommanderPlatesDB.RadialStacking = false
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(driverPasses == 1, "turned off: Blizzard's own sizing pass runs once to hand the plates back", driverPasses)
NoErrors("DR, cast target and stacking clean")

-- Back to the bar: everything given back
CommanderPlatesDB.PlateStyle = "CLASSIC"
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(w.__shown == false and rm.UnitFrame.HealthBarsContainer.__alpha == 1, "Classic again: disc gone, bar back")
CHECK(rm.UnitFrame.CastBarsContainer.__alpha == 1 and rm.UnitFrame.name.__alpha == 1, "...cast bar and name back")
playerTarget = "nameplate4"
Fire("PLAYER_TARGET_CHANGED")
CompactUnitFrame_UpdateSelectionHighlight(rm.UnitFrame)
CHECK(rm.UnitFrame.selectionHighlight.__shown == true, "a bar plate gets its selection highlight back when targeted")
playerTarget = nil
Fire("PLAYER_TARGET_CHANGED")
CHECK(rm.__hit and rm.__hit[1].relativePoint ~= "CENTER", "...and the bar's hit box")
CHECK(rtov.totemIcon.__shown == true, "the totem never noticed")
NoErrors("radial section clean")

-- Off while radial: every plate restored
CommanderPlatesDB.PlateStyle = "RADIAL"
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(w.__shown == true, "radial again")
CommanderPlatesDB.Enable = false
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
CHECK(w.__shown == false and rm.UnitFrame.HealthBarsContainer.__alpha == 1 and rm.UnitFrame.CastBarsContainer.__alpha == 1, "module off: the radial plate is gone and Blizzard's is whole")
CommanderPlatesDB.Enable = true
CommanderPlatesDB.PlateStyle = "CLASSIC"
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
Despawn("nameplate4"); Despawn("nameplate5"); Despawn("nameplate6")
NoErrors("radial teardown clean")

-- The friend-or-foe scheme: red / green instead of red / blue
local guard = Spawn("nameplate8", { guid = "Creature-G1", name = "Stormwind Guard", player = false, friend = true })
CommanderPlatesDB.NpcNameColor = "REACTION_RG"
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
local gc = guard.UnitFrame.name.__color
CHECK(gc and gc[1] == 0.3 and gc[2] == 0.9, "'Hostile red / friendly green' paints a friendly NPC's name green", gc and table.concat(gc, ","))
CommanderPlatesDB.ReactionScheme = "REACTION_RG"
CommanderPlatesDB.NpcNameColor = "CLASS"
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
gc = guard.UnitFrame.name.__color
CHECK(gc and gc[2] == 0.9, "...and a CLASS setting on an NPC falls back to the chosen scheme", gc and table.concat(gc, ","))
CommanderPlatesDB.ReactionScheme = "REACTION"
Commander.Notify(COMMANDER_PLATES_EVENTS.UPDATE)
gc = guard.UnitFrame.name.__color
CHECK(gc and gc[3] == 1 and gc[1] == 0.35, "red / blue again: friendly blue", gc and table.concat(gc, ","))
CommanderPlatesDB.NpcNameColor = "DEFAULT"
Despawn("nameplate8")
NoErrors("reaction scheme clean")

-- ---------------------------------------------------------------------------
io.write("H. the settings page\n")
CHECK(built.sections >= 9, "sections built (" .. built.sections .. ")")
CHECK(built.checks >= 40, "checkboxes built (" .. built.checks .. ")")
CHECK(built.sliders >= 20, "sliders built (" .. built.sliders .. ")")
CHECK(#built.dropdowns >= 12, "dropdowns built (" .. #built.dropdowns .. ")")
CHECK(built.buttons >= 2, "buttons built (" .. built.buttons .. ")")
CHECK(built.rows >= 6, "text and preview rows built (" .. built.rows .. ")")
-- The preview repaints from the settings without error, under every anchor
-- and both glow styles
for _, anchor in ipairs({ "ABOVE", "BELOW", "LEFT", "RIGHT", "CENTER" }) do
    CommanderPlatesDB.CcAnchor = anchor
    for _, style in ipairs({ "SOFT", "OUTLINE" }) do
        CommanderPlatesDB.TargetGlowStyle = style
        for _, fn in ipairs(builtPanel.__refreshers) do
            local ok, err = pcall(fn)
            if not ok then caughtErrors[#caughtErrors + 1] = "preview refresh: " .. tostring(err) end
        end
    end
end
CommanderPlatesDB.CcAnchor = "ABOVE"
CommanderPlatesDB.TargetGlowStyle = "SOFT"
NoErrors("preview repaints clean under every anchor and style")
-- The page folds: every section a foldout with its own remembered key, one
-- search box, the radial sections only while plates are discs, and each
-- summary answers without error
CHECK(built.search == 1, "one search box above the foldouts")
local foldKeys, radialFolds = {}, 0
for _, f in ipairs(built.folds) do
    CHECK(not foldKeys[f.opts.key], "foldout key is unique: " .. f.opts.key)
    foldKeys[f.opts.key] = true
    if f.opts.summary then
        local ok, text = pcall(f.opts.summary)
        CHECK(ok and type(text) == "string", "summary of '" .. f.title .. "' is text", tostring(text))
    end
    if f.opts.isShown then
        radialFolds = radialFolds + 1
        CommanderPlatesDB.PlateStyle = "CLASSIC"
        CHECK(f.opts.isShown() == false, "'" .. f.title .. "' is hidden while plates are bars")
        CommanderPlatesDB.PlateStyle = "RADIAL"
        CHECK(f.opts.isShown() == true, "...and shown while they are discs")
        CommanderPlatesDB.PlateStyle = "CLASSIC"
    end
end
CHECK(#built.folds >= 12 and radialFolds == 3, "twelve foldouts, three of them radial (" .. #built.folds .. "/" .. radialFolds .. ")")
-- Bar-only controls grey out once every plate is a disc
local barOnly
for _, d in ipairs(built.dropdowns) do if d.label == "Cast Bar Colour" then barOnly = d end end
CommanderPlatesDB.PlateStyle, CommanderPlatesDB.RadialUnits = "RADIAL", "ALL"
CHECK(barOnly and barOnly.isEnabled() == false, "a bar-only control greys out when every plate is a disc")
CommanderPlatesDB.RadialUnits = "ENEMY_PLAYERS"
CHECK(barOnly and barOnly.isEnabled() == true, "...but not while some plates are still bars")
CommanderPlatesDB.PlateStyle, CommanderPlatesDB.RadialUnits = "CLASSIC", "ALL"
-- The style switches by slash command
builtPanel.__opts.slashHandlers.radial()
CHECK(CommanderPlatesDB.PlateStyle == "RADIAL", "/cplates radial")
builtPanel.__opts.slashHandlers.classic()
CHECK(CommanderPlatesDB.PlateStyle == "CLASSIC", "/cplates classic")
-- ...and as discs, under every scope, name place, face and icon shape
CommanderPlatesDB.PlateStyle = "RADIAL"
for _, scope in ipairs({ "ALL", "PLAYERS", "ENEMIES", "ENEMY_PLAYERS" }) do
    CommanderPlatesDB.RadialUnits = scope
    for _, place in ipairs({ "BELOW", "ABOVE", "NONE" }) do
        CommanderPlatesDB.RadialName = place
        for _, art in ipairs({ "CLASS", "PORTRAIT", "NONE" }) do
            CommanderPlatesDB.RadialCoreArt = art
            CommanderPlatesDB.RadialRoundAuras = not CommanderPlatesDB.RadialRoundAuras
            CommanderPlatesDB.RadialCoreCC = not CommanderPlatesDB.RadialCoreCC
            for _, fn in ipairs(builtPanel.__refreshers) do
                local ok, err = pcall(fn)
                if not ok then caughtErrors[#caughtErrors + 1] = "radial preview refresh: " .. tostring(err) end
            end
        end
    end
end
for _, f in ipairs(allFrames) do PumpFrame(f, 3) end
CommanderPlatesDB.PlateStyle, CommanderPlatesDB.RadialUnits = "CLASSIC", "ALL"
CommanderPlatesDB.RadialName, CommanderPlatesDB.RadialCoreArt = "BELOW", "CLASS"
CommanderPlatesDB.RadialRoundAuras, CommanderPlatesDB.RadialCoreCC = true, true
NoErrors("radial preview repaints clean under every combination")
-- Every dropdown's current value is one of its options
for _, d in ipairs(built.dropdowns) do
    local cur, found = d.get(), false
    for _, e in ipairs(d.options) do if e.value == cur then found = true end end
    CHECK(found, "dropdown '" .. d.label .. "' default is one of its options", tostring(cur))
end
NoErrors("no errors anywhere")

io.write(string.format("\n%d checks, %d failed\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
