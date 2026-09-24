-- Commander Party Frames banner smoke (luajit) — run per SUPPORTED class
-- (a class with no layer has no board and no banner, so there is nothing
-- here to assert against):
--     luajit partyframes_banner_smoke.lua MAGE
--     luajit partyframes_banner_smoke.lua PRIEST
--     luajit partyframes_banner_smoke.lua DRUID
--     luajit partyframes_banner_smoke.lua PALADIN
--
-- A second mode runs the CLICK-CAST board, which the sorted run cannot reach:
-- whether the rows are secure is decided once at login and never again, so it
-- needs its own process rather than a section:
--     luajit partyframes_banner_smoke.lua MAGE clickcast
-- It reuses this whole mock and exits after the secure-board section, so the
-- sorted run above is untouched by it.
-- Verification for the 4.2.0
-- banner utilities: the split drink/eat consume button, inventory counters,
-- the mana gem control, the portals/teleports popout, and the all-class
-- bandage button (use, lockout, opening First Aid). Mock modeled on
-- Commander_Production/Harness.
-- 4.3.0 adds the druid HOT layer: the per-row hot strip (own sweeps,
-- Lifebloom stacks, ours-only sourcing), the state ladder including the two
-- removal schools, and the upkeep banner (form, known-only cooldowns).
-- 5.4.0 adds the paladin BLESS layer, and specifically the two things no
-- other layer can exercise: the Forbearance lockout (EXPOSED with nothing up,
-- FADING under an expiring Hand, plain REFRESH once it clears) and the
-- one-blessing-per-target rule. Plus the Hand strip on the same machinery the
-- hots ride, and the aura/seal/known-only-cooldown banner.

local ADDONS = "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"

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

-- --- Units -----------------------------------------------------------------
local CLASS = (arg and arg[1]) or "MAGE"
local SECURE = (arg and arg[2]) == "clickcast"
local playerClass = CLASS
local targetUnit = nil          -- nil = no target
local targetFriendly = true
function UnitClass(unit) return playerClass, playerClass end
function UnitGUID(unit) return unit == "player" and "player-guid" or (targetUnit and "target-guid") end
function UnitName(unit) return unit == "player" and "Tester" or "Ally" end
function UnitExists(unit)
    if unit == "player" then return true end
    if unit == "pet" then return petOut end
    if unit == "target" then return targetUnit ~= nil end
    return false
end
function UnitIsFriend(a, b) return targetFriendly end
function UnitIsDeadOrGhost() return false end
function UnitIsPlayer() return true end
function UnitIsUnit(a, b) return a == b end
-- Full by default, so the mage and priest runs are unchanged; the druid run
-- moves it to drive the hot board's health-gated READY state
playerHealth = 100
function UnitHealth() return playerHealth end
function UnitHealthMax() return 100 end
function UnitPower() return 100 end
function UnitPowerMax() return 100 end
function UnitPowerType() return 0 end
function UnitIsConnected() return true end
function UnitIsVisible() return true end
function UnitInRange() return true, true end
function UnitAffectingCombat() return false end
function UnitLevel() return 70 end
function UnitRace() return "Human", "Human" end
function UnitCastingInfo() return nil end
function UnitChannelInfo() return nil end
inCombat = false
function InCombatLockdown() return inCombat end
function IsInRaid() return false end
function IsInGroup() return false end
-- Where we are. The battleground marks reserve their row slots from this
-- rather than from the setting alone, so the section that exercises them has
-- to be able to zone.
instanceKind = "none"
function IsInInstance() return instanceKind ~= "none", instanceKind end
function GetNumGroupMembers() return 0 end
function GetNumSubgroupMembers() return 0 end
function GetRaidTargetIndex() return nil end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function IsAltKeyDown() return false end
function GetSpellBonusDamage() return 0 end
function GetSpellBonusHealing() return 0 end

RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
CLASS_ICON_TCOORDS = setmetatable({}, { __index = function() return { 0, 1, 0, 1 } end })
LOCALIZED_CLASS_NAMES_MALE = setmetatable({}, { __index = function(_, k) return k end })
NUM_PET_ACTION_SLOTS = 10
petOut = false
freezeStart, freezeDur = 0, 0
NUM_PET_ACTION_SLOTS = 10
function GetPetActionInfo(i) return (petOut and i == 3) and "Freeze" or nil end
function GetPetActionCooldown() return freezeStart, freezeDur end
function HasPetUI() return false end

-- --- Spells ----------------------------------------------------------------
-- Only what the banner needs: the mage's conjures/teleports/gems, plus the
-- names the engine resolves at login.
local SPELLS = {
    [57724] = "Sated", [57723] = "Exhaustion",
    [17] = "Power Word: Shield", [6788] = "Weakened Soul", [139] = "Renew",
    [1459] = "Arcane Intellect", [23028] = "Arcane Brilliance",
    [5504] = "Conjure Water", [587] = "Conjure Food",
    [11196] = "Recently Bandaged", [3273] = "First Aid",
    [31687] = "Summon Water Elemental", [33395] = "Freeze",
    -- Mana gems (Emerald not trained, so the best known is Ruby)
    [27101] = "Conjure Mana Emerald", [10054] = "Conjure Mana Ruby",
    [10053] = "Conjure Mana Citrine", [3552] = "Conjure Mana Jade",
    [759] = "Conjure Mana Agate",
    -- Alliance travel (Horde spells stay unknown)
    [3561] = "Teleport: Stormwind", [3562] = "Teleport: Ironforge",
    [3565] = "Teleport: Darnassus", [32271] = "Teleport: Exodar",
    [33690] = "Teleport: Shattrath",
    [10059] = "Portal: Stormwind", [11416] = "Portal: Ironforge",
    [11419] = "Portal: Darnassus", [32266] = "Portal: Exodar",
    [33691] = "Portal: Shattrath",
    -- Horde equivalents (present in the book, never known here)
    [3567] = "Teleport: Orgrimmar", [3563] = "Teleport: Undercity",
    [3566] = "Teleport: Thunder Bluff", [32272] = "Teleport: Silvermoon",
    [35715] = "Teleport: Shattrath (H)", [11417] = "Portal: Orgrimmar",
    [11418] = "Portal: Undercity", [11420] = "Portal: Thunder Bluff",
    [32267] = "Portal: Silvermoon", [35717] = "Portal: Shattrath (H)",
    -- Water Elemental and its Freeze
    [31687] = "Summon Water Elemental", [33395] = "Freeze",
    -- Armor lines
    [30482] = "Molten Armor", [27125] = "Mage Armor", [27124] = "Ice Armor",
    [7301] = "Frost Armor",
    -- Self-shield base IDs: without these ResolveTrackedSpells resolves no
    -- names, so the My Shields rows never exist and the personal block is
    -- never exercised
    [11426] = "Ice Barrier", [1463] = "Mana Shield",
    -- Druid layer: the hots, the ally buff pair, the banner cooldowns and the
    -- forms. Rebirth is deliberately left UNTRAINED below, so the banner's
    -- known-only filter has something to actually filter out.
    [774] = "Rejuvenation", [8936] = "Regrowth", [33763] = "Lifebloom",
    [1126] = "Mark of the Wild", [21849] = "Gift of the Wild", [467] = "Thorns",
    -- Ally-buff registry: the priest's three and the mage's other two. Dampen
    -- Magic is deliberately LEFT OUT of the book below, so the known-spell
    -- gate has an untrained buff to prove it drops.
    [1243] = "Power Word: Fortitude", [21562] = "Prayer of Fortitude",
    [33076] = "Prayer of Mending",
    [14752] = "Divine Spirit", [27681] = "Prayer of Spirit",
    [976] = "Shadow Protection", [27683] = "Prayer of Shadow Protection",
    [1008] = "Amplify Magic", [604] = "Dampen Magic",
    [29166] = "Innervate", [17116] = "Nature's Swiftness",
    [20484] = "Rebirth", [22812] = "Barkskin",
    [5487] = "Bear Form", [9634] = "Dire Bear Form", [768] = "Cat Form",
    [783] = "Travel Form", [1066] = "Aquatic Form", [33943] = "Flight Form",
    [40120] = "Swift Flight Form", [24858] = "Moonkin Form",
    [33891] = "Tree of Life",
    -- Paladin layer: the blessings (single and Greater), the three Hands,
    -- the banner cooldowns, and one aura and one seal. Repentance is
    -- deliberately left UNTRAINED below so the banner's known-only filter has
    -- something to filter out, exactly as Rebirth does for the druid.
    [20217] = "Blessing of Kings", [25898] = "Greater Blessing of Kings",
    [19740] = "Blessing of Might", [25782] = "Greater Blessing of Might",
    [19742] = "Blessing of Wisdom", [25894] = "Greater Blessing of Wisdom",
    [1038] = "Blessing of Salvation", [25895] = "Greater Blessing of Salvation",
    [20911] = "Blessing of Sanctuary", [25899] = "Greater Blessing of Sanctuary",
    [19977] = "Blessing of Light", [25890] = "Greater Blessing of Light",
    [1044] = "Blessing of Freedom", [1022] = "Blessing of Protection",
    [6940] = "Blessing of Sacrifice", [25771] = "Forbearance",
    [633] = "Lay on Hands", [642] = "Divine Shield", [498] = "Divine Protection",
    [20216] = "Divine Favor", [31884] = "Avenging Wrath",
    [853] = "Hammer of Justice", [31842] = "Divine Illumination",
    [20066] = "Repentance",
    [27149] = "Devotion Aura", [19746] = "Concentration Aura",
    [32223] = "Crusader Aura", [27151] = "Shadow Resistance Aura",
    [20375] = "Seal of Command", [20165] = "Seal of Light",
    [20164] = "Seal of Justice",
    [19750] = "Flash of Light", [4987] = "Cleanse",
    -- Priest layer: Inner Fire and the banner cooldowns. Shadowfiend is
    -- deliberately left UNTRAINED below, the way Rebirth and Repentance are
    -- for the other two, so the known-only filter has something to drop.
    [25431] = "Inner Fire", [33206] = "Pain Suppression",
    [10060] = "Power Infusion", [8122] = "Psychic Scream",
    [15487] = "Silence", [14751] = "Inner Focus",
    [34433] = "Shadowfiend", [32375] = "Mass Dispel",
    [19236] = "Desperate Prayer",
    -- Mage banner cooldowns. Combustion is deliberately left UNTRAINED below
    -- (this mock mage is frost), so the known-only filter has something to
    -- drop here too.
    [45438] = "Ice Block", [11958] = "Cold Snap", [12051] = "Evocation",
    [2139] = "Counterspell", [12472] = "Icy Veins", [12043] = "Presence of Mind",
    [12042] = "Arcane Power", [11129] = "Combustion", [66] = "Invisibility",
    [122] = "Frost Nova",
    -- Battleground marks: never learned by anybody, read straight out of the
    -- client's spell data (see util.ResolveBGBook)
    [23333] = "Warsong Flag", [23335] = "Silverwing Flag",
    [34976] = "Netherstorm Flag",
    [23505] = "Berserking", [23493] = "Restoration", [23451] = "Speed",
}
local knownIds = {}
local function Learn(...) for _, id in ipairs({ ... }) do knownIds[id] = true end end
Learn(17, 6788, 139, 1459, 23028, 5504, 587, 3273,
    10054, 10053, 3552, 759,                       -- gems up to Ruby
    3561, 3562, 3565, 32271, 33690,                -- Alliance teleports
    10059, 11416, 11419, 32266, 33691,             -- Alliance portals
    27125, 27124,
    11426, 1463,                                   -- Ice Barrier, Mana Shield
    1008,                                          -- Amplify Magic (Dampen untrained)
    45438, 11958, 12051, 2139, 12472, 66, 122,     -- mage banner (no Combustion)
    1243, 21562, 14752, 27681, 976, 33076,         -- the priest's ally buffs + Mending
    25431, 33206, 10060, 6346, 8122, 15487, 14751, 32375, 19236)  -- priest banner (no Shadowfiend)
-- Druid book: the whole hot kit and three of the four banner cooldowns.
-- Rebirth stays untrained on purpose (see the SPELLS note above).
Learn(774, 8936, 33763, 1126, 21849, 467,
    29166, 17116, 22812,
    5487, 768, 33891)
-- Paladin book: every blessing single, the Greater versions of Kings and
-- Might only (so the "Greater satisfies the slot" path and the single-only
-- path are both exercised), all three Hands, one aura, one seal, and the
-- banner cooldowns bar Repentance (see the SPELLS note above).
Learn(20217, 25898, 19740, 25782, 19742, 1038, 19977,
    1044, 1022, 6940,
    633, 642, 498, 20216, 31884, 853, 31842,
    27149, 19746, 32223, 20375, 20165, 20164, 19750, 4987)
-- Shadow Resistance Aura is deliberately NOT trained, so the switcher has an
-- untrained line to leave out of its popout.

function GetSpellInfo(id)
    if type(id) == "string" then return id, nil, "Interface\\Icons\\Spell_" .. id end
    local n = SPELLS[id]
    if not n then return nil end
    return n, nil, "Interface\\Icons\\Spell_" .. id, 0, 0, 0, id
end
function IsSpellKnown(id) return knownIds[id] or false end
function GetSpellCooldown() return 0, 0, 1 end

-- Spellbook walk (RefreshKnownSpells): every learned spell, one tab
function GetNumSpellTabs() return 1 end
local function BookOrder()
    local order = {}
    for id in pairs(knownIds) do order[#order + 1] = id end
    table.sort(order)
    return order
end
function GetSpellTabInfo() return "General", "tex", 0, #BookOrder() end
function GetSpellBookItemName(slot) local id = BookOrder()[slot]; return id and SPELLS[id], "" end
function GetSpellBookItemInfo(slot) return "SPELL", BookOrder()[slot] end

-- --- Items -----------------------------------------------------------------
local bags = {}     -- itemID -> count
C_Item = {
    GetItemCount = function(id) return bags[id] or 0 end,
    GetItemIconByID = function(id) return "Interface\\Icons\\Item_" .. id end,
}
function GetItemCount(id) return bags[id] or 0 end
function GetItemIcon(id) return "Interface\\Icons\\Item_" .. id end
function GetItemInfo(id) return "Item" .. id end
C_Container = {
    GetContainerNumSlots = function() return 0 end,
    GetContainerItemID = function() return nil end,
}

-- --- Combat log ------------------------------------------------------------
local clogEvent = {}
function CombatLogGetCurrentEventInfo() return unpack(clogEvent) end
-- Shared checks below the class gate need to drive the log too
function _G.__setClog(t) clogEvent = t end

-- --- Auras -----------------------------------------------------------------
local playerBuffs, unitDebuffs = {}, {}   -- unitDebuffs[unit] = { {name=,expirationTime=} }
local unitBuffs = {}                      -- unit -> { {name=,icon=,expirationTime=,duration=} }
function _G.__setUnitBuffs(unit, list) unitBuffs[unit] = list end
C_UnitAuras = {
    GetBuffDataByIndex = function(unit, i)
        local list = unitBuffs[unit]
        if list then return list[i] end
        return unit == "player" and playerBuffs[i] or nil
    end,
    GetDebuffDataByIndex = function(unit, i)
        local list = unitDebuffs[unit]
        return list and list[i] or nil
    end,
    GetAuraDataByIndex = function() return nil end,
}
AuraUtil = { UnpackAuraData = function(a) return a and a.name end }
C_NamePlate = { GetNamePlates = function() return {} end }

local castByName = {}
function CastSpellByName(name) castByName[#castByName + 1] = name end

-- ===========================================================================
-- Load the real framework + addon
-- ===========================================================================

local function Load(path) assert(loadfile(path))() end

local function Fire(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    local snap = {}
    for i, f in ipairs(list) do snap[i] = f end
    for _, frame in ipairs(snap) do
        local handler = frame.__scripts.OnEvent
        if handler then
            local ok, err = pcall(handler, frame, event, ...)
            if not ok then caughtErrors[#caughtErrors + 1] = event .. ": " .. tostring(err) end
        end
    end
end

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")

_G.CommanderPartyFramesDB = {}
Load(ADDONS .. "/Commander_PartyFrames/CommanderPartyFramesDB.lua")
Fire("ADDON_LOADED", "Commander_PartyFrames")
Load(ADDONS .. "/Commander_PartyFrames/CommanderPartyFrames.lua")

-- The engine's shield-capacity read is live from the first UNIT_AURA, and
-- this mock's widgets auto-generate every Set*/Get*/Is* method — so
-- scanTip:SetUnitBuff exists, satisfies the engine's guard, and then NumLines
-- (which matches no prefix) does not, and the whole aura pass dies on the
-- first real PW:S. Give it a baseline of NO tooltip lines, which is exactly
-- what an ally the client cannot address looks like: capacity falls back to
-- the rank table, the way it does in the client. The forecast section far
-- below replaces this with lines of its own.
if _G.CommanderPartyFramesScanTip then
    _G.CommanderPartyFramesScanTip.NumLines = function() return 0 end
end

-- Stock the bags before login so the first bind pass sees them
bags[30703] = 20      -- Conjured Mana Biscuit? (best water rank in the book)
bags[8079] = 12       -- a lower water rank too
bags[22019] = 8       -- best food
bags[8008] = 3        -- Mana Ruby
bags[21991] = 5       -- Heavy Netherweave Bandage
bags[21990] = 2       -- Netherweave Bandage

-- Blizzard's own party frame container. On this client that is ONE
-- retail-style PartyFrame holding pooled member frames — the old
-- PartyMemberFrame1..4 globals do not exist. Created before login so the
-- hide toggle can install its OnShow guard.
_G.PartyFrame = NewWidget("Frame", "PartyFrame")
-- The raid-style party frame: a CHILD of PartyFrame, built lazily by
-- CompactPartyFrame_Generate and shipped hidden. Nothing we do may ever put
-- it on screen — showing it conjures raid frames for someone who never asked.
_G.CompactPartyFrame = NewWidget("Frame", "CompactPartyFrame")
_G.CompactPartyFrame.__shown = false
-- Blizzard's raid frames: CompactRaidFrameContainer sits on UIParent on its
-- own (NOT under PartyFrame), and Blizzard decides its visibility from the
-- group state and the manager tab's Show/Hide toggle through
-- CompactRaidFrameManager_UpdateContainerVisibility(). The mock starts it
-- shown (as if in a raid) and lets the test move the "should show" answer.
_G.CompactRaidFrameContainer = NewWidget("Frame", "CompactRaidFrameContainer")
_G.CompactRaidFrameManager = NewWidget("Frame", "CompactRaidFrameManager")
_G.CompactRaidFrameManager.container = _G.CompactRaidFrameContainer
raidFramesWanted = true
function CompactRaidFrameManager_UpdateContainerVisibility()
    if raidFramesWanted then
        _G.CompactRaidFrameContainer:Show()
    else
        _G.CompactRaidFrameContainer:Hide()
    end
end

-- Set BEFORE login and after defaults: whether the rows are secure is read
-- once, in the login handler, and nothing re-reads it (the settings page says
-- as much — the option asks for a /reload). So the clickcast run has to
-- arrive at login already asking for it.
if SECURE then CommanderPartyFramesDB.ClickCast = true end

Fire("PLAYER_LOGIN")
Fire("BAG_UPDATE_DELAYED")

CHECK(#caughtErrors == 0, "login runs clean", caughtErrors[1])

-- ===========================================================================
-- The CLICK-CAST board (second mode: `clickcast`)
-- ===========================================================================
-- Whether a row is a secure unit button is decided once, at login, from the
-- setting — so this whole board is unreachable from the sorted run and had no
-- coverage at all until now. Which matters more than a gap usually does: it
-- is the mode anyone playing off @mouseover macros is in, and the promise it
-- makes is that the row's `unit` attribute is set and stays set. A tooltip
-- script cannot touch an attribute, but "cannot" is what a test is for.
if SECURE then
    -- Two allies, so the roster produces real tokens rather than just ours
    local rE, rG = UnitExists, UnitGUID
    UnitExists = function(u) return u == "party1" or u == "party2" or rE(u) end
    UnitGUID = function(u)
        if u == "party1" or u == "party2" then return u .. "-guid" end
        return rG(u)
    end
    IsInGroup = function() return true end
    GetNumGroupMembers = function() return 3 end
    Fire("GROUP_ROSTER_UPDATE")

    local row = _G.CommanderPartyFramesRow1
    CHECK(row ~= nil, "the click-cast board builds named secure rows")
    if row then
        CHECK(row.__kind == "Button", "each row is a Button, not a Frame", row.__kind)
        CHECK(row.__secureTemplate == true and row.__protected == true,
            "built from a secure template, so the client will honour its clicks")
        CHECK(row.__clicks ~= nil, "and registered for clicks")
    end

    -- The row carrying us: the one whose token a @mouseover macro resolves.
    local selfRow
    for i = 1, 8 do
        local r = _G["CommanderPartyFramesRow" .. i]
        if r and r.unitToken == "player" then selfRow = r end
    end
    CHECK(selfRow ~= nil, "one row carries the player's own raw token")
    if not selfRow then
        io.write(string.format("[%s clickcast] %d checks, %d failures\n", CLASS, checks, fails))
        os.exit(fails == 0 and 0 or 1)
    end
    CHECK(selfRow:GetAttribute("unit") == "player",
        "the unit ATTRIBUTE is the raw token — this is what makes @mouseover work",
        tostring(selfRow:GetAttribute("unit")))

    -- --- The row tooltip ---------------------------------------------------
    -- Instrumented here rather than in the mock proper: only this board has a
    -- row tooltip, so only this run has any reason to record one.
    local tipLines, tipUnit, tipShown = {}, nil, false
    local tip = _G.GameTooltip
    tip.SetOwner = function() end
    tip.ClearLines = function() tipLines, tipUnit = {}, nil end
    tip.SetUnit = function(_, u) tipUnit = u; tipLines[#tipLines + 1] = "UNIT:" .. tostring(u) end
    tip.AddLine = function(_, text) tipLines[#tipLines + 1] = tostring(text) end
    tip.AddDoubleLine = function(_, l, r2) tipLines[#tipLines + 1] = tostring(l) .. "|" .. tostring(r2) end
    tip.NumLines = function() return #tipLines end
    tip.Show = function() tipShown = true end
    tip.Hide = function() tipShown = false end

    local function Hover()
        tipLines, tipUnit, tipShown = {}, nil, false
        local fn = selfRow.__scripts.OnEnter
        if fn then fn(selfRow) end
    end

    local db = CommanderPartyFramesDB
    db.Forecast, db.ForecastTooltip = "BAR", true
    db.ForecastWindow, db.ForecastMinPct = 0, 0
    db.ForecastDots, db.ForecastHots, db.ForecastCasts = true, true, true

    -- Something for the board to actually have notes ABOUT
    local function Clog(sub, spell, amount)
        __setClog({ now, sub, false, "player-guid", "Tester", 0, 0,
                    "player-guid", "Tester", 0, 0, 99101, spell, 32, amount,
                    0, 32, 0, 0, 0, false })
        Fire("COMBAT_LOG_EVENT_UNFILTERED")
    end
    Clog("SPELL_PERIODIC_DAMAGE", "Smoke Dot", 40)
    unitDebuffs.player = { { name = "Smoke Dot", expirationTime = now + 12, duration = 12 } }
    Fire("UNIT_AURA", "player")

    db.RowTooltip = "FULL"
    Hover()
    CHECK(tipShown == true and tipUnit == "player",
        "Unit + Board Notes shows the game's own unit tooltip", tostring(tipUnit))
    CHECK(#tipLines > 1, "with the board's notes under it", #tipLines)
    CHECK(tipLines[2] == " ",
        "separated from the unit block by a spacer", tostring(tipLines[2]))

    db.RowTooltip = "EXTRAS"
    Hover()
    CHECK(tipShown == true and tipUnit == nil,
        "Board Notes Only drops the unit half", tostring(tipUnit))
    CHECK(tipLines[1] == "Pending",
        "...and opens straight on the notes, with no leading blank line",
        tostring(tipLines[1]))

    -- A row with nothing to add must show nothing, not an empty grey box
    unitDebuffs.player = {}
    Fire("UNIT_AURA", "player")
    Hover()
    CHECK(tipShown == false and #tipLines == 0,
        "a quiet row shows no tooltip at all in notes-only mode", #tipLines)

    db.RowTooltip = "OFF"
    unitDebuffs.player = { { name = "Smoke Dot", expirationTime = now + 12, duration = 12 } }
    Fire("UNIT_AURA", "player")
    Hover()
    CHECK(tipShown == false and #tipLines == 0,
        "Off shows nothing even with notes to show", #tipLines)

    -- The promise. Every mode above must leave the attribute exactly alone,
    -- because that is the whole of what a mouseover macro reads.
    CHECK(selfRow:GetAttribute("unit") == "player",
        "and no tooltip setting has touched the unit attribute",
        tostring(selfRow:GetAttribute("unit")))
    db.RowTooltip = "EXTRAS"
    Hover()
    CHECK(selfRow:GetAttribute("unit") == "player",
        "...still, after hovering in every mode",
        tostring(selfRow:GetAttribute("unit")))

    -- --- Nearby Raid on secure rows ---------------------------------------
    -- The hard case for the whole feature. Secure attributes may not be
    -- rewritten in combat, so a re-pick landed mid-fight cannot take effect —
    -- and the thing that must NOT happen is that it half-takes effect, or
    -- silently vanishes. It is made, parked, and applied when the fight ends.
    local raidUp, raidYards = {}, {}
    for i = 1, 6 do raidUp["raid" .. i] = true; raidYards["raid" .. i] = i * 10 end
    local nE, nG = UnitExists, UnitGUID
    UnitExists = function(u)
        if u and u:find("^raid") then return raidUp[u] == true end
        return nE(u)
    end
    UnitGUID = function(u)
        if u and u:find("^raid") then return u .. "-guid" end
        return nG(u)
    end
    IsInRaid = function() return true end
    UnitPosition = function(u)
        if u == "player" then return 0, 0, 0, 1 end
        local d = raidYards[u]
        if not d then return nil end
        return 0, d, 0, 1
    end

    inCombat = false
    db.NearMode = true
    db.NearCount = 4
    Fire("GROUP_ROSTER_UPDATE")
    local function TokenOf(i)
        local r = _G["CommanderPartyFramesRow" .. i]
        return r and r:GetAttribute("unit") or nil
    end
    CHECK(TokenOf(1) == "player" and TokenOf(2) == "raid1"
        and TokenOf(3) == "raid2" and TokenOf(4) == "raid3",
        "the nearby pick binds RAW tokens, closest first, so @mouseover still works",
        table.concat({ tostring(TokenOf(1)), tostring(TokenOf(2)),
                       tostring(TokenOf(3)), tostring(TokenOf(4)) }, " "))

    -- A re-pick mid-fight: made, but not applied, and nothing protected touched
    inCombat = true
    blockedCalls = {}
    raidYards.raid6 = 1
    local moved = CommanderPartyFrames_NearRefresh(false)
    CHECK(moved == true, "a re-pick in combat still happens")
    CHECK(#blockedCalls == 0,
        "without a single protected call", blockedCalls[1])
    CHECK(TokenOf(2) == "raid1",
        "and without rewriting a bound token mid-fight", tostring(TokenOf(2)))

    -- ...and lands the moment the fight ends, off the same deferral every
    -- other secure change on this board already uses
    inCombat = false
    Fire("PLAYER_REGEN_ENABLED")
    CHECK(TokenOf(2) == "raid6",
        "the parked pick lands when combat drops", tostring(TokenOf(2)))

    db.NearMode = false
    IsInRaid = function() return false end
    UnitPosition = nil
    UnitExists, UnitGUID = nE, nG
    Fire("GROUP_ROSTER_UPDATE")

    CHECK(#caughtErrors == 0, "no errors on the click-cast board", caughtErrors[1])
    io.write(string.format("[%s clickcast] %d checks, %d failures\n", CLASS, checks, fails))
    os.exit(fails == 0 and 0 or 1)
end

-- ===========================================================================
-- Buttons and bindings
-- ===========================================================================

local consume = _G.CommanderPartyFramesConsume
local conjure = _G.CommanderPartyFramesConjure
local gem = _G.CommanderPartyFramesGem
local portal = _G.CommanderPartyFramesPortal
local bandage = _G.CommanderPartyFramesBandage

-- ===========================================================================
-- Header chrome: the settings cog
-- ===========================================================================
-- It is drawn from quads, never loaded from an art path. The cog used to be
-- Interface\WorldMap\Gear_64Grey — Cataclysm world-map art this client's
-- retail-style framework no longer ships — and an unresolvable texture path
-- draws NOTHING while the button stays present, placed and clickable. That
-- failure is invisible to every assertion about shown/anchor/size, so the
-- guard has to be about where the pixels come from.
do
    local cog
    for _, f in ipairs(allFrames) do
        if f.cog and f.hub then cog = f end
    end
    CHECK(cog ~= nil, "the header carries a settings cog")
    if cog then
        CHECK(#cog.cog == 4 and cog.hub ~= nil and cog.bore ~= nil,
            "its glyph is four crossed bars, a body and a bore",
            cog.cog and #cog.cog)
        -- SetColorTexture leaves __texture nil; a file path would set it.
        local fromFile = cog.hub.__texture or (cog.bore and cog.bore.__texture)
        for _, t in ipairs(cog.cog) do fromFile = fromFile or t.__texture end
        CHECK(fromFile == nil,
            "...drawn with SetColorTexture, so no art path can go stale", fromFile)
        -- What makes it a cog rather than an asterisk: the middle is DARKER
        -- than the body, so it reads as a hole instead of a bright hub. The
        -- first version had them the same grey and eight spokes radiating out
        -- of a blob.
        local body = cog.hub.__color or {}
        local bore = cog.bore and cog.bore.__color or {}
        CHECK(bore[1] and body[1] and bore[1] < body[1],
            "the bore is punched darker than the body it sits in",
            tostring(bore[1]) .. " vs " .. tostring(body[1]))
        -- ...and it has to be smaller than the body, or there is no body left
        CHECK((cog.bore.__w or 0) < (cog.hub.__w or 0),
            "and smaller than it, so the body survives around it",
            tostring(cog.bore.__w) .. " vs " .. tostring(cog.hub.__w))
        local p = cog.__points[#cog.__points]
        CHECK(p and p.point == "TOPRIGHT", "and it sits in the right-edge chrome", p and p.point)
    end
end

-- ===========================================================================
-- Bar overflow: a fill may never outrun its own track
-- ===========================================================================
-- Chassis, so this runs on every layer. The client does NOT promise
-- hp <= hpMax: a group member it has not finished syncing reports a
-- placeholder maximum alongside real current health, and the honest-looking
-- division then yields a fraction in the thousands. Nothing clips a texture
-- to its parent, so unclamped that is not a slightly-wrong bar — it is the
-- last row's health drawn clean across the monitor.
do
    local function Tick()
        now = now + 1
        for _, f in ipairs(allFrames) do
            local u = f.__scripts.OnUpdate
            PumpFrame(f, 10)
        end
    end
    local function SomeRow()
        for _, f in ipairs(allFrames) do
            if f.bar and f.barBG and f.stripe then return f end
        end
    end
    Tick()
    local row = SomeRow()
    CHECK(row ~= nil, "the board draws a row to measure")
    if row then
        local track = row._barW or 0
        CHECK(track > 0, "the row reports its track width", track)
        playerHealth = 3129                 -- against the mock's max of 100
        Fire("UNIT_AURA", "player")
        Tick()
        CHECK((row.bar.__w or 0) <= track + 0.01,
            "health above the reported maximum cannot overrun the track",
            string.format("%.1f vs track %.1f", row.bar.__w or -1, track))
        -- Every other fill on the row shares the rule
        CHECK((row.wsBar.__w or 0) <= track + 0.01, "nor can the lockout drain")
        CHECK((row.healthBar.__w or 0) <= track + 0.01, "nor the mana strip")
        local segTotal = row.bar.__w or 0
        for i = 1, 5 do
            local s = row.shieldSegs[i]
            if s.__shown then segTotal = segTotal + (s.__w or 0) end
        end
        CHECK(segTotal <= track + 0.01,
            "and the shield segments chained off the fill stay inside it too",
            string.format("%.1f vs track %.1f", segTotal, track))
        playerHealth = 100
        Fire("UNIT_AURA", "player")
        Tick()
    end
end

-- Bandage is chassis: every supported class gets it
CHECK(bandage ~= nil, "bandage button exists")
CHECK(bandage:GetAttribute("macrotext1") ~= nil, "bandage is bound")

-- ...and it must be LEFT-anchored on every layer, not left on the provisional
-- top-right anchor mkBtn hands out. Four of the five cluster buttons are
-- mage-only, so the layout walk used to run over a sparse array with ipairs
-- and stop at index 1 on any other class — the bandage button then kept its
-- placeholder anchor and sat underneath the settings gear (both TOPRIGHT,
-- one pixel apart). Header convention: class stuff left, Commander chrome
-- right, and nothing may straddle the two.
do
    local p = bandage.__points[#bandage.__points]
    CHECK(p ~= nil and p.point ~= "TOPRIGHT",
        "the bandage button is not parked on the right-edge chrome",
        p and p.point)
    -- Either it leads the cluster off root's left edge, or it is chained to
    -- the button before it — never anchored to root's right.
    local leadsLeft = p and p.point == "TOPLEFT" and p.rel == _G.CommanderPartyFramesFrame
    local chained = p and p.point == "LEFT" and p.rel ~= _G.CommanderPartyFramesFrame
    CHECK(leadsLeft or chained,
        "...it either leads the left cluster or chains onto the button before it",
        p and (tostring(p.point) .. "/" .. tostring(p.rel)))
end

-- ===========================================================================
-- Default party frames: the header toggle. Class-independent, so both the
-- mage run and the early-exiting non-mage run call it.
-- ===========================================================================
-- ===========================================================================
-- Every dropdown on this page actually says something
-- ===========================================================================
-- Chassis, not a layer, and a shared check BOTH exit paths run — the way
-- CheckBlizzToggle is — because the non-mage classes leave before the tail.
--
-- A dropdown is the one control that can be wired completely wrongly and
-- still LOOK built. The frame appears, the arrow works, the menu opens — and
-- the face and every line in it are blank, with no error at any point. That
-- is exactly what an options table keyed `label` instead of `text` produces,
-- and `label` is what every OTHER control in the settings file calls its own
-- caption, so it is the natural thing to write. It shipped that way, because
-- every dropdown function in this mock was a no-op and nothing was looking.
function CheckDropdowns()
    local seen, blankFace, blankEntry = 0, nil, nil
    for i = 1, 400 do
        local dd = _G["CommanderUIDropDown" .. i]
        if dd then
            seen = seen + 1
            if not dd.__ddText or dd.__ddText == "" then blankFace = blankFace or i end
            for _, info in ipairs(dd.__ddEntries or {}) do
                if not info.text or info.text == "" then blankEntry = blankEntry or i end
            end
        end
    end
    CHECK(seen > 0, "the page built dropdowns to check", tostring(seen))
    CHECK(blankFace == nil, "every dropdown shows its current value",
        blankFace and ("CommanderUIDropDown" .. blankFace) or "")
    CHECK(blankEntry == nil, "...and every entry in every menu is captioned",
        blankEntry and ("CommanderUIDropDown" .. blankEntry) or "")
end

function CheckBlizzToggle()
    local pf = _G.PartyFrame
    local toggleBtn
    for _, f in ipairs(allFrames) do
        if f.bars and f.slash then toggleBtn = f end
    end

    CHECK(toggleBtn ~= nil, "the header carries a default-party-frames button")
    if not toggleBtn then return end
    CHECK(#toggleBtn.bars == 3, "its glyph is three stacked rows", #toggleBtn.bars)
    CHECK(pf.__shown == true, "default party frames start shown")
    CHECK(CommanderPartyFramesDB.HideBlizzardParty == false, "the hide setting defaults off")
    CHECK(type(pf.__scripts.OnShow) == "function", "an OnShow guard is installed on PartyFrame")
    CHECK(toggleBtn.slash.__shown == false, "the glyph is unstruck while they are shown")
    local rf = _G.CompactRaidFrameContainer
    CHECK(rf.__shown == true, "default raid frames start shown")
    CHECK(type(rf.__scripts.OnShow) == "function", "an OnShow guard is installed on the raid container too")

    toggleBtn.__scripts.OnClick()
    CHECK(CommanderPartyFramesDB.HideBlizzardParty == true, "clicking sets the hide flag")
    CHECK(pf.__shown == false, "clicking hides the default party frames")
    CHECK(rf.__shown == false, "...and the default raid frames with them")
    CHECK(toggleBtn.slash.__shown == true, "the glyph is struck through while they are hidden")

    -- Blizzard re-shows the container on its own (roster changes, leaving
    -- Edit Mode); the guard has to put it straight back down
    pf:Show()
    pf.__scripts.OnShow(pf)
    CHECK(pf.__shown == false, "a Blizzard-side Show() is undone by the guard")
    -- The raid container comes back through Blizzard's own updater on every
    -- roster change; same answer
    CompactRaidFrameManager_UpdateContainerVisibility()
    rf.__scripts.OnShow(rf)
    CHECK(rf.__shown == false, "a Blizzard-side raid-frame Show() is undone by the guard")

    -- Raised mid-fight, the guard must not touch it: it stays up, and the
    -- deferred re-apply takes it down when combat drops
    inCombat = true
    rf:Show()
    rf.__scripts.OnShow(rf)
    CHECK(rf.__shown == true, "a container Blizzard raises in combat is left alone")
    inCombat = false
    Fire("PLAYER_REGEN_ENABLED")
    CHECK(rf.__shown == false, "...and dropped again once combat ends")

    toggleBtn.__scripts.OnClick()
    CHECK(CommanderPartyFramesDB.HideBlizzardParty == false, "clicking again clears the flag")
    CHECK(pf.__shown == true, "the default party frames come back")
    CHECK(rf.__shown == true, "the default raid frames come back")

    -- Restoring the raid container asks Blizzard whether it should be up,
    -- rather than showing blindly: hidden in a raid, given back after the
    -- raid was left, it must stay down
    toggleBtn.__scripts.OnClick()
    CHECK(rf.__shown == false, "raid frames hidden again for the restore check")
    raidFramesWanted = false
    toggleBtn.__scripts.OnClick()
    CHECK(rf.__shown == false, "restore defers to Blizzard when the raid frames are no longer wanted")
    CHECK(pf.__shown == true, "...while the party frames are shown as before")
    raidFramesWanted = true

    -- ...and the guard must not fight a legitimate show once the flag is off
    pf.__scripts.OnShow(pf)
    CHECK(pf.__shown == true, "the guard leaves them alone when the flag is off")

    -- Combat: refuse outright rather than risk a protected call
    inCombat = true
    CommanderPartyFrames_ToggleBlizzardParty()
    CHECK(CommanderPartyFramesDB.HideBlizzardParty == false, "the toggle refuses in combat")
    CHECK(pf.__shown == true, "nothing moves in combat")

    -- A change made from the settings page mid-fight defers to REGEN_ENABLED
    CommanderPartyFramesDB.HideBlizzardParty = true
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    CHECK(pf.__shown == true, "an in-combat settings change is deferred, not applied")
    inCombat = false
    Fire("PLAYER_REGEN_ENABLED")
    CHECK(pf.__shown == false, "the deferred change lands when combat drops")

    -- Switching the module off has to give the default frames back, or the
    -- player is left with no party frames at all
    CommanderPartyFramesDB.EnableShield = false
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    CHECK(pf.__shown == true, "disabling the module restores the default frames")
    CHECK(CommanderPartyFramesDB.HideBlizzardParty == true, "...without discarding the setting")
    CommanderPartyFramesDB.EnableShield = true
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    CHECK(pf.__shown == false, "re-enabling hides them again")

    CommanderPartyFramesDB.HideBlizzardParty = false
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    CHECK(pf.__shown == true, "and the board leaves them shown once the flag is cleared")

    -- Regression, in-game report: the restore branch used to Show() every
    -- frame it knew about, unconditionally. CompactPartyFrame ships hidden
    -- and is only shown when raid-style party frames are switched on, so that
    -- put raid frames on screen for someone who never enabled them.
    CHECK(_G.CompactPartyFrame.__shown == false,
        "the raid-style party frame is never conjured into view")

    -- The same rule for the container: a frame hidden by something else
    -- (Edit Mode, another addon) is not ours to reveal on restore
    pf:Hide()
    CommanderPartyFramesDB.HideBlizzardParty = true
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    CommanderPartyFramesDB.HideBlizzardParty = false
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    CHECK(pf.__shown == false, "a frame we did not hide is left alone on restore")

    -- ...but one the guard took down while the toggle was on IS given back
    pf:Show()
    CommanderPartyFramesDB.HideBlizzardParty = true
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    CHECK(pf.__shown == false, "hiding still works after that")
    pf:Show()
    pf.__scripts.OnShow(pf)
    CHECK(pf.__shown == false, "the guard still catches a Blizzard-side Show()")
    CommanderPartyFramesDB.HideBlizzardParty = false
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    CHECK(pf.__shown == true, "a frame the guard took down is handed back")
end

-- ===========================================================================
-- Druid hot board (HOT layer)
-- ===========================================================================
-- The group mock has no party, so the board is the player's own row — which
-- is all this needs: hots are read off a unit's auras with sourceUnit ==
-- player, and the player is a unit like any other.
if CLASS == "DRUID" then
    local segs = _G.CommanderPartyFramesFrame.hdrSegs
    CHECK(segs ~= nil, "the druid banner built the shared segment pool")
    CHECK(_G.CommanderPartyFramesFrame.armorCd == nil,
        "and NOT the mage banner's armor radial")

    local function HotRow()
        for _, f in ipairs(allFrames) do
            if f.strip and f.stripe and not f.scratch then return f end
        end
    end
    -- The shared DrawOnce lives further down (it is part of the mage run), so
    -- this block carries its own: advance the clock, re-scan, repaint.
    local function Refresh()
        Fire("UNIT_AURA", "player")
        now = now + 1
        for _, f in ipairs(allFrames) do
            local u = f.__scripts.OnUpdate
            PumpFrame(f, 10)
        end
    end
    local function SegTexts()
        local out = {}
        for i = 1, #segs do
            if segs[i].icon.__shown then
                out[#out + 1] = (segs[i].icon.__texture or "?") .. "=" .. tostring(segs[i].text.__text or "")
            end
        end
        return out
    end
    local function SegCount()
        local n = 0
        for i = 1, #segs do if segs[i].icon.__shown then n = n + 1 end end
        return n
    end

    CommanderPartyFramesDB.ShowHeader = true
    CommanderPartyFramesDB.ShowSpellIcon = true
    playerBuffs = {}
    Refresh()
    local row = HotRow()
    CHECK(row ~= nil, "the board draws an ally row with a hot strip")

    -- --- The strip ---------------------------------------------------------
    -- Three hots of ours: every slot lit, each sweep scaled to its OWN aura
    -- duration, and the stack count only on the one that stacks
    playerBuffs = {
        { name = "Mark of the Wild", expirationTime = now + 1500, duration = 1800,
          icon = "Interface\\Icons\\Spell_1126", sourceUnit = "player" },
        { name = "Rejuvenation", expirationTime = now + 9, duration = 12,
          icon = "Interface\\Icons\\Spell_774", sourceUnit = "player" },
        { name = "Regrowth", expirationTime = now + 17, duration = 21,
          icon = "Interface\\Icons\\Spell_8936", sourceUnit = "player" },
        { name = "Lifebloom", expirationTime = now + 6, duration = 7,
          icon = "Interface\\Icons\\Spell_33763", sourceUnit = "player", applications = 3 },
    }
    Refresh()
    -- Every slot is ALWAYS occupied now — a missing hot is a dark placeholder
    -- of itself, not a hole — so "lit" is the live count, not the shown count
    local function LitHots()
        local n = 0
        for i = 1, 3 do
            local h = row.strip[i]
            if h.icon.__shown and h.icon.__desat == false then n = n + 1 end
        end
        return n
    end
    local lit = LitHots()
    CHECK(lit == 3, "all three hots light their own slot", lit)
    CHECK(row.strip[1].cd.__cdDur == 12, "each sweep runs its own hot's duration", row.strip[1].cd.__cdDur)
    CHECK(row.strip[2].cd.__cdDur == 21, "...Regrowth's 21s, not a shared constant", row.strip[2].cd.__cdDur)
    CHECK(row.strip[3].cd.__cdDur == 7, "...and Lifebloom's 7s", row.strip[3].cd.__cdDur)
    -- Lifebloom is a ROLL now: the sweep gives way to a clock, and the stack
    -- digit to three pips. The sweep is still STAMPED with the right duration
    -- (turning the Lifebloom instruments off has to put it straight back),
    -- it is simply not what the slot shows.
    CHECK(row.strip[3].cd.__shown == false,
        "the roll's radial sweep gives way to its clock")
    CHECK(row.strip[3].clock.__shown == true,
        "Lifebloom carries a readable countdown instead")
    CHECK(row.strip[3].count.__shown == false,
        "and its stack digit gives way to the pips")
    CHECK(row.strip[3].pips[1].__shown and row.strip[3].pips[3].__shown,
        "all three stack pips are drawn")
    CHECK(row.strip[1].count.__shown == false,
        "a hot that does not stack carries no digit")
    CHECK(row.strip[1].clock.__shown == false and row.strip[1].pips[1].__shown == false,
        "and a hot that is not the roll gets neither clock nor pips")
    -- Lifebloom (7s) is the soonest of the three, so it owns the number.
    -- Refresh advances the clock a tick, hence 5 rather than the 6 it was set to.
    CHECK(row.left.__text == "5s", "the row's number is the hot that falls off FIRST", row.left.__text)

    -- Another druid's hot is not ours: it does not gate our next global.
    -- Rejuvenation is playerBuffs[2], so slot ONE is the one that must go
    -- dark — and it must go dark in place, without sliding Regrowth left.
    playerBuffs[2].sourceUnit = "party1"
    Refresh()
    CHECK(LitHots() == 2, "a hot cast by someone else stays off our strip", LitHots())
    CHECK(row.strip[1].icon.__shown == true and row.strip[1].icon.__desat == true,
        "...leaving a dark placeholder in Rejuvenation's own slot")
    local g = row.strip[1].icon.__color or {}
    CHECK(g[1] and g[1] < 0.5, "...tinted dark, not merely faded", tostring(g[1]))
    CHECK(row.strip[1].cd.__shown == false, "...and running no sweep")
    CHECK(row.strip[2].icon.__desat == false and row.strip[2].cd.__cdDur == 21,
        "...while Regrowth stays put in slot two rather than sliding left",
        tostring(row.strip[2].cd.__cdDur))
    playerBuffs[2].sourceUnit = "player"
    Refresh()

    -- --- The state ladder --------------------------------------------------
    -- REFRESH: a hot inside the refresh window bubbles the row up
    local function Stripe()
        local c = row.stripe.__color or {}
        return string.format("%.2f,%.2f,%.2f", c[1] or -1, c[2] or -1, c[3] or -1)
    end
    -- Clocks are re-stamped against the CURRENT now each time: several ticks
    -- have passed getting here, and a stale expiry would decay the other two
    -- hots into the refresh window and mask what is being tested.
    local function SetHots(rejuv, regrowth, lifebloom)
        playerBuffs[2].expirationTime = now + rejuv
        playerBuffs[3].expirationTime = now + regrowth
        playerBuffs[4].expirationTime = now + lifebloom
        Refresh()
    end
    SetHots(30, 30, 3)      -- Lifebloom about to bloom
    CHECK(Stripe() == "0.35,0.85,1.00", "a hot inside the refresh window turns the row cyan", Stripe())

    -- --- The roll ----------------------------------------------------------
    -- Everything Lifebloom got that the other two hots did not. The failure
    -- this exists to catch is the one that prompted it: a seven-second buff
    -- wearing the same amber as a twenty-one-second one, for most of its
    -- life, until the amber stopped meaning anything and it fell off.
    local db = CommanderPartyFramesDB
    db.LBDisplay, db.LBStackPips = "BOTH", true
    db.LBRefreshAt, db.LBLateAt = 3, 1.5
    db.LBPriority, db.LBAlert, db.LBAlertSound = false, false, false
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)

    local lb = 3            -- the Lifebloom slot; Rejuv and Regrowth are 1 and 2
    -- Deliberately does NOT advance the clock, unlike Refresh: these assert
    -- on exact remaining times, and on a row flash that lasts nine tenths of
    -- a second and would have burned down inside a one-second tick.
    local function Roll(left, stacks)
        playerBuffs[4].expirationTime = now + left
        playerBuffs[4].applications = stacks or 3
        playerBuffs[2].expirationTime = now + 30
        playerBuffs[3].expirationTime = now + 30
        Fire("UNIT_AURA", "player")
    end
    local function ClockColor()
        local c = row.strip[lb].clock.__color or {}
        return string.format("%.2f,%.2f,%.2f", c[1] or -1, c[2] or -1, c[3] or -1)
    end

    -- Whole seconds while there is time, TENTHS once there is not: the last
    -- three seconds are where a tenth decides between a refresh and a bloom,
    -- and they are exactly the part of a radial sweep nobody can read.
    Roll(6, 3)
    CHECK(row.strip[lb].clock.__text == "6",
        "the roll's clock counts whole seconds while there is time",
        tostring(row.strip[lb].clock.__text))
    CHECK(ClockColor() == "0.35,0.85,0.45",
        "and reads green outside its window", ClockColor())
    Roll(2.4, 3)
    CHECK(row.strip[lb].clock.__text == "2.4",
        "and switches to tenths inside the last three seconds",
        tostring(row.strip[lb].clock.__text))

    -- Its OWN window. Four seconds left is inside the shared hot window and
    -- outside Lifebloom's, which is the whole point of separating them.
    Roll(5, 3)
    CHECK(ClockColor() == "0.35,0.85,0.45",
        "four seconds of a seven-second buff is not urgent", ClockColor())
    Roll(2.5, 3)
    CHECK(ClockColor() == "0.75,0.55,1.00",
        "at three stacks the window is a bloom decision, not a reminder", ClockColor())
    Roll(2.5, 1)
    CHECK(ClockColor() == "1.00,0.72,0.20",
        "below three stacks the same window is a plain refresh", ClockColor())
    Roll(1.2, 3)
    CHECK(ClockColor() == "1.00,0.25,0.22",
        "and under Late At everything turns red", ClockColor())

    -- The pips ARE the stack count, and they light from the left
    Roll(6, 2)
    CHECK(row.strip[lb].pips[2].__shown and row.strip[lb].pips[3].__shown,
        "all three pips are drawn whatever the stack count")
    local litPip = row.strip[lb].pips[2].__color or {}
    local darkPip = row.strip[lb].pips[3].__color or {}
    CHECK((litPip[2] or 0) > (darkPip[2] or 1),
        "two stacks lights two pips and leaves the third dark")

    -- The roll bar: the drain strip the druid board has never had a use for
    CHECK(row.wsBar.__shown == true, "the roll takes the row's empty drain strip")
    local barW = row._barW or 100
    CHECK(math.abs((row.wsBar.__w or 0) - barW * (6 / 7)) < 0.51,
        "and empties over the roll's own seven seconds",
        tostring(row.wsBar.__w) .. " of " .. tostring(barW))
    local wc = row.wsBar.__color or {}
    CHECK((wc[2] or 0) > (wc[1] or 1), "green while there is time")
    Roll(1.2, 3)
    wc = row.wsBar.__color or {}
    CHECK((wc[1] or 0) > (wc[2] or 1), "red once you are late")

    -- The row state follows the SLOTS' own windows, not one shared number.
    -- Three and a half seconds is inside the hot strip's four and outside the
    -- roll's three, and a row that turned cyan while the Lifebloom slot was
    -- still green would be the board contradicting itself in two places a
    -- druid reads at the same time.
    db.HotRefreshAt = 4
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Roll(3.5, 3)
    CHECK(ClockColor() == "0.35,0.85,0.45" and Stripe() ~= "0.35,0.85,1.00",
        "the roll's own window governs the row, not the hot strip's",
        ClockColor() .. " / " .. Stripe())
    Roll(2.5, 3)
    CHECK(Stripe() == "0.35,0.85,1.00",
        "...and inside it the row turns cyan with the slot", Stripe())

    -- Bar Only and Clock Only each drop the other half
    db.LBDisplay = "BAR"
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Roll(6, 3)
    CHECK(row.wsBar.__shown == true and row.strip[lb].clock.__shown == false,
        "Bar Only keeps the drain and drops the clock")
    CHECK(row.strip[lb].count.__shown == true and row.strip[lb].count.__text == 3,
        "...and the stack count falls back to the plain digit",
        tostring(row.strip[lb].count.__text))
    db.LBDisplay = "CLOCK"
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Roll(6, 3)
    CHECK(row.strip[lb].clock.__shown == true and row.wsBar.__shown == false,
        "Clock Only keeps the clock and drops the drain")

    -- Off puts Lifebloom back on the shared strip exactly as it was
    db.LBDisplay = "OFF"
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Roll(6, 3)
    CHECK(row.strip[lb].clock.__shown == false and row.wsBar.__shown == false
        and row.strip[lb].pips[1].__shown == false,
        "Off takes every roll instrument away")
    CHECK(row.strip[lb].cd.__shown == true and row.strip[lb].cd.__cdDur == 7,
        "...and gives the radial sweep back", tostring(row.strip[lb].cd.__cdDur))
    CHECK(row.strip[lb].count.__shown == true and row.strip[lb].count.__text == 3,
        "...along with the stack digit", tostring(row.strip[lb].count.__text))
    -- ...and the shared window with them. Off has to mean OFF: a board still
    -- running Lifebloom's private three-second window while the page says
    -- "plain hot slot" is worse than not having the feature at all.
    db.HotRefreshAt = 4
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Roll(3.5, 3)        -- inside the shared 4s window, outside the roll's 3s
    CHECK(Stripe() == "0.35,0.85,1.00",
        "...and the shared refresh window governs it again", Stripe())

    -- The late warning fires ONCE per cycle, on the edge. A roll enters its
    -- refresh window every five seconds by design; an alarm on that would be
    -- a metronome, so this is tied to Late At and re-arms on a refresh.
    db.LBDisplay, db.LBAlert = "BOTH", true
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Roll(6, 3)
    CHECK(row.flash.__shown == false, "a healthy roll raises no alarm")
    Roll(1.2, 3)
    CHECK(row.flash.__shown == true, "going late flashes the row")
    now = now + 2       -- past the flash; the roll is still late, with no new edge
    Roll(1.2, 3)
    CHECK(row.flash.__shown == false, "holding it late does not strobe")
    Roll(6, 3)          -- refreshed: the edge re-arms
    Roll(1.2, 3)
    CHECK(row.flash.__shown == true, "and a refresh re-arms it for the next cycle")

    -- Sort First only weights the roll; it must not fire without the setting
    db.LBAlert = false
    db.LBDisplay = "BOTH"
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    playerBuffs[4].applications = 3
    SetHots(30, 30, 30)

    -- Rolling again -> green
    SetHots(30, 30, 30)
    CHECK(Stripe() == "0.35,0.85,0.40", "rolling hots read as the quiet healthy state", Stripe())

    -- No hots on a HURT ally -> yellow READY. Full health stays quiet, which
    -- is the whole point of the health gate.
    playerBuffs = { { name = "Mark of the Wild", expirationTime = now + 1500, duration = 1800,
        icon = "Interface\\Icons\\Spell_1126", sourceUnit = "player" } }
    playerHealth = 100
    Refresh()
    CHECK(Stripe() == "0.55,0.60,0.78", "a hotless ally at full health stays quiet", Stripe())
    playerHealth = 60
    Refresh()
    CHECK(Stripe() == "1.00,0.90,0.25", "...and turns yellow once they are actually hurt", Stripe())
    CHECK(row.left.__text == "HOT", "the yellow row says what to cast", row.left.__text)

    -- The two schools a druid removes have to be tellable apart, and both
    -- outrank the hot state underneath them
    unitDebuffs.player = { { name = "Test Curse", dispelName = "Curse",
        expirationTime = now + 18, duration = 30, icon = "Interface\\Icons\\Curse" } }
    Refresh()
    CHECK(Stripe() == "0.65,0.30,0.95", "a removable Curse turns the row purple", Stripe())
    CHECK(row.left.__text == "CURSED", "and says so", row.left.__text)
    unitDebuffs.player = { { name = "Test Poison", dispelName = "Poison",
        expirationTime = now + 11, duration = 20, icon = "Interface\\Icons\\Poison" } }
    Refresh()
    CHECK(Stripe() == "0.25,0.85,0.35", "a removable Poison turns it GREEN, not purple", Stripe())
    CHECK(row.left.__text == "POISON", "and names the other school", row.left.__text)
    unitDebuffs.player = {}
    Refresh()

    -- The strip with Show All on: Sated and Exhaustion never take a slot,
    -- whatever else is on the row. Ten minutes on every row after a lust
    -- would otherwise crowd out the one debuff that matters.
    do
        local wasShow, wasAll = CommanderPartyFramesDB.ShowDispels, CommanderPartyFramesDB.DispelShowAll
        CommanderPartyFramesDB.ShowDispels = true
        CommanderPartyFramesDB.DispelShowAll = true
        unitDebuffs.player = {
            { name = "Sated", expirationTime = now + 600, duration = 600, icon = "Interface\\Icons\\Sated" },
            { name = "Exhaustion", expirationTime = now + 600, duration = 600, icon = "Interface\\Icons\\Exhaustion" },
            { name = "Smoke Dot", expirationTime = now + 12, duration = 12, icon = "Interface\\Icons\\Smoke" },
        }
        Refresh()
        local shown = {}
        for n = 1, #row.dispels do
            if row.dispels[n].icon.__shown then shown[#shown + 1] = row.dispels[n].icon.__texture end
        end
        CHECK(#shown == 1, "Sated and Exhaustion take no slot on the strip", table.concat(shown, ","))
        CHECK(shown[1] == "Interface\\Icons\\Smoke", "the real debuff is the one shown", shown[1])
        unitDebuffs.player = {}
        Refresh()
        CommanderPartyFramesDB.ShowDispels, CommanderPartyFramesDB.DispelShowAll = wasShow, wasAll
    end

    -- --- The two upkeep slots ----------------------------------------------
    -- Mark of the Wild and Thorns are PERMANENT slots, read the way the hots
    -- beside them are: the icon never leaves, and while the buff is up its
    -- remaining time is legible on the icon. A thirty-minute radial sweep
    -- barely moves, so the number is the part that has to be right.
    -- Mark takes buff slot one and Thorns slot two, both on by default in the
    -- registry. The advisor is parked for now — its own block tests the red.
    CommanderPartyFramesDB.BuffTrack = {}
    CommanderPartyFramesDB.BuffAdvisor = false
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    playerBuffs = {
        { name = "Mark of the Wild", expirationTime = now + 1500, duration = 1800,
          icon = "Interface\\Icons\\Spell_1126", sourceUnit = "player" },
        { name = "Thorns", expirationTime = now + 480, duration = 600,
          icon = "Interface\\Icons\\Spell_467", sourceUnit = "party1" },
    }
    Refresh()
    local mark, thorn = row.buffs[1], row.buffs[2]
    CHECK(mark.icon.__shown == true, "a healthy Mark keeps its slot")
    CHECK(mark.icon.__desat == false, "...lit, not ghosted")
    CHECK(mark.cd.__shown == true and mark.cd.__cdDur == 1800,
        "and its duration rides the sweep, exactly like a hot's",
        tostring(mark.cd.__cdDur))
    CHECK(thorn.icon.__shown == true and thorn.cd.__cdDur == 600,
        "Thorns gets the same treatment on the second slot",
        tostring(thorn.cd.__cdDur))
    -- Any druid's Thorns counts as covered, exactly like Mark: the sourceUnit
    -- above is a teammate, and it still reads as up
    CHECK(thorn.icon.__desat == false, "another druid's Thorns still counts as covered")

    -- Inside the rebuff window the icon goes amber. No digits anywhere on the
    -- strip: the sweep is the clock, and a row of numbers is what this board
    -- deliberately does not do.
    playerBuffs[2].expirationTime = now + 40
    Refresh()
    local dueColor = thorn.icon.__color or {}
    CHECK(dueColor[1] == 1 and dueColor[2] and dueColor[2] < 0.8,
        "the icon goes amber inside the rebuff window", tostring(dueColor[2]))

    -- Missing is the dark placeholder, holding the slot, running no sweep
    playerBuffs = {}
    Refresh()
    CHECK(mark.icon.__shown == true, "a missing Mark keeps its slot")
    CHECK(mark.icon.__desat == true, "...desaturated")
    local mg = mark.icon.__color or {}
    CHECK(mg[1] and mg[1] < 0.5, "...and tinted dark", tostring(mg[1]))
    CHECK(mark.cd.__shown == false, "...with no sweep left to run")
    CHECK(thorn.icon.__shown == true and thorn.icon.__desat == true,
        "missing Thorns holds its slot the same way")

    -- Bear form cannot cast any of this, and the banner is already showing a
    -- red form segment saying so. Reddening every buff on every row on top of
    -- that is the same complaint six more times.
    CommanderPartyFramesDB.BuffAdvisor = true     -- parked above; this is its test
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    playerBuffs = {}
    Refresh()
    local bare = mark.icon.__color or {}
    CHECK(bare[1] and bare[1] > 0.5, "in caster form a missing Mark is red",
        tostring(bare[1]))
    playerBuffs = { { name = "Bear Form", expirationTime = 0, duration = 0,
        icon = "Interface\\Icons\\Spell_5487", sourceUnit = "player" } }
    Refresh()
    local shifted = mark.icon.__color or {}
    CHECK(shifted[1] and shifted[1] < 0.5,
        "shifted out, it goes quiet — you would have to leave form first",
        tostring(shifted[1]))
    playerBuffs = {}
    CommanderPartyFramesDB.BuffAdvisor = false
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Refresh()

    -- "Permanent" stops at a corpse. A dark Mark on a dead ally still reads
    -- as "cast this", and the answer there is a battle rez — so both slots go
    -- down with the hot strip rather than nagging over a body.
    local liveDead = UnitIsDeadOrGhost
    function UnitIsDeadOrGhost() return true end
    Refresh()
    CHECK(mark.icon.__shown == false and thorn.icon.__shown == false,
        "a dead ally is not a buff target: both upkeep slots go down")
    UnitIsDeadOrGhost = liveDead
    Refresh()

    -- Untracked, the slot does not sit there dark: it gives the width back
    CommanderPartyFramesDB.BuffTrack = { ["HOT:THORNS"] = false }
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Refresh()
    CHECK(row.buffs[2].icon.__shown == false,
        "untracking Thorns retires its slot entirely")
    CommanderPartyFramesDB.BuffTrack = {}
    CommanderPartyFramesDB.BuffAdvisor = true
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Refresh()

    -- --- The banner --------------------------------------------------------
    -- Caster form says nothing worth a slot
    local casterSegs = SegCount()
    local formShown = false
    for _, s in ipairs(SegTexts()) do
        if s:find("Spell_5487", 1, true) or s:find("Spell_33891", 1, true) then formShown = true end
    end
    CHECK(not formShown, "caster form spends no banner slot", table.concat(SegTexts(), " "))

    -- Bear blocks healing: the segment appears, red and dimmed
    playerBuffs = { { name = "Bear Form", expirationTime = 0, duration = 0,
        icon = "Interface\\Icons\\Spell_5487", sourceUnit = "player" } }
    Refresh()
    CHECK(SegCount() == casterSegs + 1, "a form takes a banner slot", SegCount())
    CHECK(segs[1].icon.__desat == true, "a form that blocks healing is dimmed")
    local ft = segs[1].icon.__color or {}
    CHECK(ft[1] == 1 and ft[2] and ft[2] < 0.4, "...and red", tostring(ft[2]))

    -- Tree of Life is a resto druid's home, not a warning
    playerBuffs = { { name = "Tree of Life", expirationTime = 0, duration = 0,
        icon = "Interface\\Icons\\Spell_33891", sourceUnit = "player" } }
    Refresh()
    CHECK(segs[1].icon.__desat == false, "Tree of Life is shown plain — it casts the hot kit")
    local tt = segs[1].icon.__color
    CHECK(tt == nil or (tt[1] == 1 and tt[2] == 1), "...and untinted", tt and tostring(tt[2]))

    -- Banner cooldowns: only what this druid actually trained. Rebirth was
    -- left out of the book, so it must not claim a slot.
    local txt = table.concat(SegTexts(), " ")
    CHECK(txt:find("Spell_29166", 1, true) ~= nil, "Innervate rides the banner", txt)
    CHECK(txt:find("Spell_17116", 1, true) ~= nil, "Nature's Swiftness too", txt)
    CHECK(txt:find("Spell_22812", 1, true) ~= nil, "and Barkskin", txt)
    CHECK(txt:find("Spell_20484", 1, true) == nil,
        "an untrained Rebirth claims no slot", txt)

    -- ...and they can be switched off wholesale
    CommanderPartyFramesDB.HotBannerCooldowns = false
    Refresh()
    CHECK((table.concat(SegTexts(), " ")):find("Spell_29166", 1, true) == nil,
        "Banner Cooldowns off drops them all")
    CommanderPartyFramesDB.HotBannerCooldowns = true
    Refresh()

    -- The strip is sizeable, and the slots are RESERVED: dropping the cap
    -- must actually take the third slot away
    playerBuffs = {
        { name = "Rejuvenation", expirationTime = now + 9, duration = 12,
          icon = "Interface\\Icons\\Spell_774", sourceUnit = "player" },
        { name = "Regrowth", expirationTime = now + 17, duration = 21,
          icon = "Interface\\Icons\\Spell_8936", sourceUnit = "player" },
        { name = "Lifebloom", expirationTime = now + 6, duration = 7,
          icon = "Interface\\Icons\\Spell_33763", sourceUnit = "player", applications = 2 },
    }
    Refresh()
    -- Hots are toggled one at a time now, exactly like the ally buffs: there
    -- is no "how many icons" slider, because with a fixed slot per hot that
    -- setting was only ever "which hots", said badly.
    CommanderPartyFramesDB.BuffTrack = { ["HOT:LIFEBLOOM"] = false }
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Refresh()
    lit = 0
    for i = 1, 3 do if row.strip[i].icon.__shown then lit = lit + 1 end end
    CHECK(lit == 2, "untracking one hot retires its slot", lit)

    -- ...and an UNTRAINED hot never gets a slot at all, however it is
    -- toggled. This is the bug that shipped: a druid with no Lifebloom was
    -- shown a Lifebloom slot to stare at.
    CommanderPartyFramesDB.BuffTrack = {}
    knownIds[33763] = nil
    Fire("SPELLS_CHANGED")
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Refresh()
    lit = 0
    for i = 1, 3 do if row.strip[i].icon.__shown then lit = lit + 1 end end
    CHECK(lit == 2, "an untrained hot takes no slot even when tracked", lit)
    knownIds[33763] = true
    Fire("SPELLS_CHANGED")
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Refresh()
    lit = 0
    for i = 1, 3 do if row.strip[i].icon.__shown then lit = lit + 1 end end
    CHECK(lit == 3, "...and training it puts the slot back without a reload", lit)
    CommanderPartyFramesDB.HotMaxIcons = 3
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Refresh()

    -- Click-cast keeps its OWN keys: the DB is account-wide, so a druid must
    -- never inherit the priest defaults
    CHECK(CommanderPartyFramesDB.DruidClickLeft == 774, "druid left-click defaults to Rejuvenation")
    CHECK(CommanderPartyFramesDB.ClickLeft == 17, "...and the priest binding is untouched")

    playerHealth = 100
    playerBuffs = {}
    unitDebuffs.player = {}
    Refresh()
    CHECK(#caughtErrors == 0, "no errors across the hot board", caughtErrors[1])
end

-- ===========================================================================
-- Paladin blessing board (BLESS layer)
-- ===========================================================================
-- Same shape as the druid block above and for the same reason: the group mock
-- has no party, so the board is the player's own row, and that is enough —
-- Hands are read off a unit's auras with sourceUnit == player, and the player
-- is a unit like any other. What is unique here is the lockout half of the
-- grammar (Forbearance) and the one-blessing-per-target rule, neither of
-- which any other layer exercises.
if CLASS == "PALADIN" then
    local segs = _G.CommanderPartyFramesFrame.hdrSegs
    CHECK(segs ~= nil, "the paladin banner built the shared segment pool")
    CHECK(_G.CommanderPartyFramesFrame.armorCd == nil,
        "and NOT the mage banner's armor radial")

    local function HandRow()
        for _, f in ipairs(allFrames) do
            if f.strip and f.stripe and not f.scratch then return f end
        end
    end
    local function Refresh()
        Fire("UNIT_AURA", "player")
        now = now + 1
        for _, f in ipairs(allFrames) do
            local u = f.__scripts.OnUpdate
            PumpFrame(f, 10)
        end
    end
    local function SegCount()
        local n = 0
        for i = 1, #segs do if segs[i].icon.__shown then n = n + 1 end end
        return n
    end
    local function SegTextures()
        local out = {}
        for i = 1, #segs do
            if segs[i].icon.__shown then out[#out + 1] = segs[i].icon.__texture or "?" end
        end
        return out
    end

    CommanderPartyFramesDB.ShowHeader = true
    CommanderPartyFramesDB.ShowSpellIcon = true
    playerBuffs = {}
    unitDebuffs.player = {}
    Refresh()
    local row = HandRow()
    CHECK(row ~= nil, "the board draws an ally row with a Hand strip")

    -- --- The Hand strip ----------------------------------------------------
    -- All three of ours: every slot lit, each sweep scaled to its OWN aura
    -- duration rather than a shared constant.
    playerBuffs = {
        { name = "Blessing of Kings", expirationTime = now + 1500, duration = 1800,
          icon = "Interface\\Icons\\Spell_20217", sourceUnit = "player" },
        { name = "Blessing of Freedom", expirationTime = now + 8, duration = 10,
          icon = "Interface\\Icons\\Spell_1044", sourceUnit = "player" },
        { name = "Blessing of Protection", expirationTime = now + 9, duration = 10,
          icon = "Interface\\Icons\\Spell_1022", sourceUnit = "player" },
        { name = "Blessing of Sacrifice", expirationTime = now + 25, duration = 30,
          icon = "Interface\\Icons\\Spell_6940", sourceUnit = "player" },
    }
    Refresh()
    local lit = 0
    for i = 1, 3 do
        local h = row.strip[i]
        if h.icon.__shown and h.icon.__desat == false then lit = lit + 1 end
    end
    CHECK(lit == 3, "all three Hands light their own slot", lit)
    CHECK(row.strip[1].cd.__cdDur == 10, "Freedom's sweep runs 10s", row.strip[1].cd.__cdDur)
    CHECK(row.strip[3].cd.__cdDur == 30, "...and Sacrifice's 30s", row.strip[3].cd.__cdDur)

    -- Ours-only: another paladin's Freedom does not spend our cooldown, so it
    -- must not fill our slot either
    playerBuffs = {
        { name = "Blessing of Freedom", expirationTime = now + 8, duration = 10,
          icon = "Interface\\Icons\\Spell_1044", sourceUnit = "party1" },
    }
    Refresh()
    CHECK(row.strip[1].icon.__desat == true,
        "another paladin's Freedom leaves our slot dark")

    -- --- Forbearance: the lockout half of the grammar -----------------------
    -- Nothing of ours up and Forbearance ticking is EXPOSED, with the minute
    -- as the drain. The stripe carries the state colour, so it is what the
    -- assertion reads.
    local EXPOSED = { 0.95, 0.25, 0.25 }
    local FADING  = { 1.00, 0.55, 0.15 }
    local function StripeIs(want)
        local c = row.stripe.__color
        if not c then return false end
        for i = 1, 3 do
            if math.abs((c[i] or 0) - want[i]) > 0.01 then return false end
        end
        return true
    end
    playerHealth = 40
    playerBuffs = {}
    unitDebuffs.player = { { name = "Forbearance", expirationTime = now + 41, duration = 60 } }
    Refresh()
    CHECK(StripeIs(EXPOSED), "locked out with nothing up reads EXPOSED")
    CHECK(row.wsBar.__shown == true, "...and the Forbearance minute draws the drain")

    -- A Hand falling off while locked is FADING, not REFRESH: you can see it
    -- going and you cannot replace it.
    playerBuffs = {
        { name = "Blessing of Protection", expirationTime = now + 2, duration = 10,
          icon = "Interface\\Icons\\Spell_1022", sourceUnit = "player" },
    }
    Refresh()
    CHECK(StripeIs(FADING), "a Hand expiring under Forbearance reads FADING")

    -- The same Hand expiring with the lockout GONE is the ordinary REFRESH
    unitDebuffs.player = {}
    Refresh()
    CHECK(not StripeIs(FADING), "...and plain REFRESH once the lockout is gone")

    -- --- Blessings: one per target -----------------------------------------
    -- The registry's `oneOf`: an ally carrying Kings is not MISSING Might, so
    -- the advisor must not redden the Might slot.
    local book = CommanderPartyFrames_GetBuffBook("BLESS")
    CHECK(book ~= nil and #book == 6, "the blessing registry has six entries",
        book and #book)
    local byKey = {}
    if book then for _, d in ipairs(book) do byKey[d.key] = d end end
    CHECK(byKey.KINGS and byKey.KINGS.known == true, "Kings resolved from the book")
    CHECK(byKey.SANCTUARY and byKey.SANCTUARY.known == false,
        "Sanctuary is untrained here, so it can never take a slot")
    CHECK(byKey.MIGHT and byKey.MIGHT.targets == "MELEE",
        "Might only applies to allies who swing something")

    -- Greater satisfies the single's slot (the Prayer of Fortitude pattern)
    playerHealth = 100
    playerBuffs = {
        { name = "Greater Blessing of Kings", expirationTime = now + 1700, duration = 1800,
          icon = "Interface\\Icons\\Spell_25898", sourceUnit = "player" },
    }
    unitDebuffs.player = {}
    Refresh()
    CHECK(row.buffs[1].icon.__desat == false,
        "Greater Blessing of Kings fills the Kings slot")

    -- --- The combined blessing slot ----------------------------------------
    -- The board's default shape: six mutually exclusive blessings collapse
    -- into ONE slot per ally, carrying whatever that ally is assigned. Three
    -- things have to hold, and none of them is testable on any other layer:
    --
    --   1. one slot, not six, whatever is tracked in the buff grid
    --   2. the slot follows the ASSIGNMENT, and a different blessing of yours
    --      reads as missing rather than as cover
    --   3. another paladin's blessing is not yours and never counts
    CHECK(CommanderPartyFramesDB.BlessCombine ~= false,
        "the blessing family is combined out of the box")

    local function BuffSlots()
        local n = 0
        for i = 1, 6 do
            if row.buffs[i] and row.buffs[i].icon.__shown then n = n + 1 end
        end
        return n
    end

    -- Every blessing tracked, and the strip is still one slot wide: what the
    -- buff grid tracks stops deciding the family's width entirely.
    CommanderPartyFramesDB.BuffTrack = {}
    for _, d in ipairs(book or {}) do CommanderPartyFramesDB.BuffTrack[d.dbKey] = true end
    CommanderPartyFramesDB.BlessAssign = {}
    CommanderPartyFramesDB.BlessClass = {}
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    playerBuffs = {
        { name = "Blessing of Kings", expirationTime = now + 500, duration = 600,
          icon = "Interface\\Icons\\Spell_20217", sourceUnit = "player" },
    }
    Refresh()
    CHECK(BuffSlots() == 1, "six blessings collapse into one slot", BuffSlots())
    CHECK(row.buffs[1].icon.__desat == false,
        "the assigned blessing being up lights the slot")

    -- Assign Wisdom (the mock paladin is a mana user, so it applies) and the
    -- SAME Kings aura must now read as missing: covered is not the question,
    -- covered with what you decided is.
    CommanderPartyFramesDB.BlessClass = { PALADIN = "WISDOM" }
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Refresh()
    CHECK(BuffSlots() == 1, "reassigning does not change the strip's width", BuffSlots())
    CHECK(row.buffs[1].icon.__desat == true,
        "a different blessing of yours reads as MISSING against the assignment")

    playerBuffs = {
        { name = "Blessing of Wisdom", expirationTime = now + 500, duration = 600,
          icon = "Interface\\Icons\\Spell_19742", sourceUnit = "player" },
    }
    Refresh()
    CHECK(row.buffs[1].icon.__desat == false, "...and the assigned one lights it")

    -- A per-player override beats the class default. The mock's player is
    -- "Tester", which is the name the row resolves and the key an override is
    -- stored under. Proved the only way it can be: the class still says
    -- Wisdom, the aura on the target is KINGS, and the slot lights — which
    -- can only happen if the override actually won.
    playerBuffs = {
        { name = "Blessing of Kings", expirationTime = now + 500, duration = 600,
          icon = "Interface\\Icons\\Spell_20217", sourceUnit = "player" },
    }
    Refresh()
    CHECK(row.buffs[1].icon.__desat == true,
        "with the class on Wisdom, a Kings aura leaves the slot dark")
    CommanderPartyFramesDB.BlessAssign = { Tester = "KINGS" }
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Refresh()
    CHECK(row.buffs[1].icon.__desat == false,
        "a per-player override outranks the class default")

    -- ...and NONE means the slot has nothing to say at all
    CommanderPartyFramesDB.BlessAssign = { Tester = "NONE" }
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Refresh()
    CHECK(BuffSlots() == 0, "an ally assigned NONE spends no slot", BuffSlots())

    -- --- Only mine ---------------------------------------------------------
    -- The reason this rework exists. Two paladins may each hold a DIFFERENT
    -- blessing on one target, so another paladin's Kings sitting in the aura
    -- list says nothing about whether yours is on them.
    CommanderPartyFramesDB.BlessAssign = {}
    CommanderPartyFramesDB.BlessClass = { PALADIN = "KINGS" }
    CommanderPartyFramesDB.BlessMineOnly = true
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    playerBuffs = {
        { name = "Blessing of Kings", expirationTime = now + 500, duration = 600,
          icon = "Interface\\Icons\\Spell_20217", sourceUnit = "party1" },
    }
    Refresh()
    CHECK(row.buffs[1].icon.__desat == true,
        "another paladin's Kings does NOT satisfy your slot")

    playerBuffs[1].sourceUnit = "player"
    Refresh()
    CHECK(row.buffs[1].icon.__desat == false, "...and your own does")

    -- With the strict read off it goes back to the registry's any-caster rule,
    -- which is the behaviour someone who is the only paladin might want back
    CommanderPartyFramesDB.BlessMineOnly = false
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    playerBuffs[1].sourceUnit = "party1"
    Refresh()
    CHECK(row.buffs[1].icon.__desat == false,
        "Only Mine off lets another paladin's blessing count again")
    CommanderPartyFramesDB.BlessMineOnly = true

    -- --- Sanctuary is tracked once it is trained ---------------------------
    -- It is a 31-point Protection talent, so `known` is the only gate that
    -- should matter — it must not ALSO need finding in the buff grid.
    CHECK(byKey.SANCTUARY and byKey.SANCTUARY.default == true,
        "Sanctuary is tracked by default, gated only by having trained it")
    local opts = CommanderPartyFrames_BlessOptions("PALADIN")
    local sancOffered = false
    for _, d in ipairs(opts) do if d.key == "SANCTUARY" then sancOffered = true end end
    CHECK(sancOffered == false,
        "an untrained Sanctuary is not offered as an assignment")

    CommanderPartyFramesDB.BuffTrack = {}
    CommanderPartyFramesDB.BlessAssign = {}
    CommanderPartyFramesDB.BlessClass = {}
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)

    -- --- The banner --------------------------------------------------------
    -- No aura and no seal: both segments present and both red, because a
    -- paladin running neither is always a mistake
    playerBuffs = {}
    Refresh()
    local bare = SegTextures()
    CHECK(#bare >= 2, "the banner draws an aura and a seal segment even when naked", #bare)
    CHECK(segs[1].icon.__desat == true, "the aura segment is dark when there is no aura")
    CHECK(segs[2].icon.__desat == true, "...and so is the seal segment")

    playerBuffs = {
        { name = "Devotion Aura", expirationTime = 0, duration = 0,
          icon = "Interface\\Icons\\Spell_27149", sourceUnit = "player" },
        { name = "Seal of Command", expirationTime = now + 18, duration = 30,
          icon = "Interface\\Icons\\Spell_20375", sourceUnit = "player" },
    }
    Refresh()
    CHECK(segs[1].icon.__desat == false, "a running aura lights its segment")
    -- Refresh() advances the clock a second past the scan, so the paint sees 17
    CHECK(segs[2].icon.__desat == false and segs[2].text.__text == "17",
        "the seal segment counts its own seconds down", segs[2].text.__text)

    -- Banner cooldowns are known-only: Repentance was never trained, so it
    -- must not have a segment even though it is in the book
    CommanderPartyFramesDB.BlessBannerCooldowns = true
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Refresh()
    local withCds = SegCount()
    CommanderPartyFramesDB.BlessBannerCooldowns = false
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Refresh()
    local withoutCds = SegCount()
    CHECK(withCds > withoutCds, "the banner cooldown segments answer their toggle",
        withCds .. "/" .. withoutCds)
    CommanderPartyFramesDB.BlessBannerCooldowns = true
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Refresh()
    -- How MANY fit is width-bounded (TruncSegs), so the assertion that
    -- matters is the filter: a trained cooldown is drawn, an untrained one is
    -- not, however many happen to fit.
    local drawn = {}
    for _, t in ipairs(SegTextures()) do drawn[t] = true end
    CHECK(drawn["Interface\\Icons\\Spell_633"] == true,
        "Lay on Hands, which this paladin knows, gets a segment")
    CHECK(drawn["Interface\\Icons\\Spell_20066"] ~= true,
        "Repentance, which they do not, never does")

    -- --- The banner outgrowing its segment pool ---------------------------
    -- The pool used to be eight segments, fixed. This paladin has ten trained
    -- banner cooldowns on top of an aura and a seal, so on a board wide
    -- enough to show them the banner walks straight off the end of the pool —
    -- which is a live error every draw, seventy-five of them in one session.
    -- The default frame width truncates before it gets there, which is
    -- exactly why nothing caught it, so this widens the board on purpose.
    local keepWidth = CommanderPartyFramesDB.FrameWidth
    CommanderPartyFramesDB.FrameWidth = 600
    CommanderPartyFramesDB.TrackUptime = true
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Refresh()
    CHECK(#caughtErrors == 0, "a banner wider than the segment pool draws clean",
        caughtErrors[1])
    CHECK(SegCount() > 8, "...and actually shows more than the old fixed eight",
        SegCount())
    CommanderPartyFramesDB.FrameWidth = keepWidth
    CommanderPartyFramesDB.TrackUptime = false
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Refresh()

    -- --- The aura and seal switchers ---------------------------------------
    -- Two on one banner, which is the case the mage's single armor switcher
    -- never exercised. Each hangs under its OWN segment and offers only the
    -- lines this paladin has trained.
    playerBuffs = {
        { name = "Devotion Aura", expirationTime = 0, duration = 0,
          icon = "Interface\\Icons\\Spell_27149", sourceUnit = "player" },
        { name = "Seal of Command", expirationTime = now + 25, duration = 30,
          icon = "Interface\\Icons\\Spell_20375", sourceUnit = "player" },
    }
    Refresh()
    local sw = CommanderPartyFrames_GetSwitchers and CommanderPartyFrames_GetSwitchers()
    CHECK(sw and #sw == 2, "the paladin banner built two switchers", sw and #sw)
    if sw and #sw == 2 then
        CHECK(sw[1].def.key == "AURA" and sw[2].def.key == "SEAL",
            "...an aura one and a seal one, in banner order")
        -- Three auras known, one of them untrained, so the popout offers the
        -- three and not the fourth
        CHECK(sw[1].known == 3, "the aura popout offers every trained aura", sw[1].known)
        CHECK(sw[2].known == 3, "and the seal popout every trained seal", sw[2].known)
        local casts = {}
        for i = 1, sw[1].known do
            casts[#casts + 1] = sw[1].buttons[i].__attr
                and sw[1].buttons[i].__attr.spell
        end
        CHECK(casts[1] == "Devotion Aura",
            "a switcher button casts by NAME, so it takes your best rank",
            tostring(casts[1]))
        -- Each popout sits under the segment it belongs to, not on top of the
        -- other one
        CHECK(sw[1]._x and sw[2]._x and sw[2]._x > sw[1]._x,
            "the seal popout hangs to the right of the aura one",
            tostring(sw[1]._x) .. " vs " .. tostring(sw[2]._x))
        -- The toggle is a real click target over the segment
        CHECK(sw[1].btn ~= nil and sw[1].btn.__shown == true,
            "the aura segment carries a toggle")
        sw[1].btn.__scripts.OnClick(sw[1].btn)
        CHECK(sw[1].pop.__shown == true, "clicking it opens the popout")
        sw[1].btn.__scripts.OnClick(sw[1].btn)
        CHECK(sw[1].pop.__shown == false, "...and clicking again closes it")
    end

    -- Click-cast keeps its own defaults, like every other layer
    CHECK(CommanderPartyFrames_GetBind("1") == 19750,
        "paladin left-click defaults to Flash of Light",
        CommanderPartyFrames_GetBind("1"))
    CHECK(CommanderPartyFramesDB.ClickLeft == 17, "...and the priest binding is untouched")

    playerHealth = 100
    playerBuffs = {}
    unitDebuffs.player = {}
    Refresh()
    CHECK(#caughtErrors == 0, "no errors across the blessing board", caughtErrors[1])
end

-- ===========================================================================
-- Priest own-aura strip (PWS layer)
-- ===========================================================================
-- Renew used to be a lone icon bolted to the row's right edge with its own
-- setting, its own flash and its own refresh window — a second vocabulary for
-- what the strip already says on every other layer. It is a strip entry now,
-- alongside Prayer of Mending, which never had a slot at all.
--
-- The priest is the one strip layer whose ROW STATE is not read from the
-- strip: its bar is the absorb and its lockout is Weakened Soul. So the
-- per-slot refresh cue is load-bearing here in a way it is not elsewhere —
-- it is the only thing that can say a Renew is about to drop.
if CLASS == "PRIEST" then
    -- --- The upkeep banner -------------------------------------------------
    -- The priest board carried a one-line string ("PW:S CD Ready ~1265")
    -- while the other three layers grew segment banners, so this is the
    -- newest of the four and gets the same three questions asked of it.
    do
        local segs = _G.CommanderPartyFramesFrame.hdrSegs
        CHECK(segs ~= nil, "the priest banner built the shared segment pool")
        local function Beat()
            Fire("UNIT_AURA", "player")
            now = now + 1
            for _, f in ipairs(allFrames) do
                local u = f.__scripts.OnUpdate
                PumpFrame(f, 10)
            end
        end
        local function SegTextures()
            local out = {}
            for i = 1, #segs do
                if segs[i].icon.__shown then out[#out + 1] = segs[i].icon.__texture or "?" end
            end
            return out
        end
        CommanderPartyFramesDB.ShowHeader = true
        CommanderPartyFramesDB.PriestBannerCooldowns = true
        Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
        playerBuffs = {}
        Beat()
        CHECK(_G.CommanderPartyFramesFrame.header.__shown == false,
            "the old text header is gone")
        CHECK(segs[1].icon.__desat == true,
            "no Inner Fire leaves the first segment dark red")

        playerBuffs = {
            { name = "Inner Fire", expirationTime = now + 500, duration = 600,
              icon = "Interface\\Icons\\Spell_25431", sourceUnit = "player" },
        }
        Beat()
        CHECK(segs[1].icon.__desat == false, "Inner Fire up lights it")

        local drawn = {}
        for _, t in ipairs(SegTextures()) do drawn[t] = true end
        CHECK(drawn["Interface\\Icons\\Spell_33206"] == true,
            "Pain Suppression, which this priest knows, gets a segment")
        CHECK(drawn["Interface\\Icons\\Spell_34433"] ~= true,
            "Shadowfiend, which they do not, never does")

        CommanderPartyFramesDB.PriestBannerCooldowns = false
        Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
        Beat()
        local off = {}
        for _, t in ipairs(SegTextures()) do off[t] = true end
        CHECK(off["Interface\\Icons\\Spell_33206"] ~= true,
            "the banner cooldowns answer their toggle")
        CommanderPartyFramesDB.PriestBannerCooldowns = true
        Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
        playerBuffs = {}
        Beat()
    end

    local function Tick()
        Fire("UNIT_AURA", "player")
        now = now + 1
        for _, f in ipairs(allFrames) do
            PumpFrame(f, 10)
        end
    end
    local function Row()
        for _, f in ipairs(allFrames) do
            if f.strip and f.stripe and not f.scratch then return f end
        end
    end

    CommanderPartyFramesDB.BuffTrack = CommanderPartyFramesDB.BuffTrack or {}
    CommanderPartyFramesDB.BuffTrack["PWS:RENEW"] = true
    CommanderPartyFramesDB.BuffTrack["PWS:POM"] = true
    CommanderPartyFramesDB.RenewFlash = true
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    playerBuffs = {}
    Tick()
    local row = Row()
    CHECK(row ~= nil, "the priest board draws a row with an own-aura strip")

    -- The priest board keeps its OWN state grammar: the strip is a readout,
    -- and a shieldless ally is still READY however many hots are on them
    CHECK(row.spellIcon.__shown == true,
        "...without giving up the Power Word: Shield slot")

    -- Missing: the board-wide dark placeholder, no sweep. Not a faded icon —
    -- desaturated AND sunk dark, the same look every missing tracker wears.
    CHECK(row.strip[1].cd.__shown == false, "a missing Renew runs no sweep")
    CHECK(row.strip[1].icon.__desat == true, "...and ghosts the icon")
    local ghost = row.strip[1].icon.__color or {}
    CHECK(ghost[1] and ghost[1] < 0.5 and ghost[2] and ghost[2] < 0.5,
        "...tinted dark, not merely faded", tostring(ghost[1]))
    CHECK(row.strip[1].icon.__shown == true, "...and still holding its slot")

    -- Ticking: bright, swept against Renew's own 15s
    playerBuffs = { { name = "Renew", expirationTime = now + 12, duration = 15,
        icon = "Interface\\Icons\\Spell_139", sourceUnit = "player" } }
    Tick()
    CHECK(row.strip[1].cd.__shown == true, "a live Renew runs the sweep")
    CHECK(row.strip[1].cd.__cdDur == 15, "scaled to Renew's 15s", row.strip[1].cd.__cdDur)
    CHECK(row.strip[1].icon.__desat == false, "and the icon lights up")
    local lit = row.strip[1].icon.__color or {}
    CHECK(lit[1] == 1 and lit[2] == 1 and lit[3] == 1, "healthy Renew is untinted")

    -- Prayer of Mending owns the second slot and carries its stack count,
    -- the way Lifebloom does on the druid board
    playerBuffs[#playerBuffs + 1] = { name = "Prayer of Mending",
        expirationTime = now + 25, duration = 30, applications = 4,
        icon = "Interface\\Icons\\Spell_33076", sourceUnit = "player" }
    Tick()
    CHECK(row.strip[2].icon.__desat == false, "Prayer of Mending fills the second slot")
    -- The charge count is a row of five lights now, not a digit: it only ever
    -- goes down, so what you want off it is how much is LEFT, and four-of-five
    -- is a shape rather than a number to read.
    -- Pips AND the number: the lights answer "how much is left" as a shape at
    -- a glance, the digit answers "how much exactly" when you look. Two
    -- readings of one fact, and on a five-charge object both earn their pixels.
    CHECK(row.strip[2].count.__shown == true and row.strip[2].count.__text == 4,
        "...carrying the charge number alongside the pips",
        tostring(row.strip[2].count.__text))
    local litPips = 0
    for k = 1, 5 do
        local pip = row.strip[2].pips[k]
        if pip and pip.__shown then
            litPips = litPips + 1
            local c = pip.__color or {}
            -- The unspent ones are the dark placeholder; the lit ones carry
            -- the charge tint, which is warm and bright
            if k <= 4 then
                CHECK(c[1] and c[1] > 0.9, "charge pip " .. k .. " is lit", tostring(c[1]))
            else
                CHECK(c[1] and c[1] < 0.4, "the spent fifth pip is dark", tostring(c[1]))
            end
        end
    end
    CHECK(litPips == 5, "all five charge slots are laid out", tostring(litPips))
    CommanderPartyFramesDB.PoMPips = false
    Tick()
    CHECK(row.strip[2].count.__shown == true and row.strip[2].count.__text == 4,
        "...and with pips off the plain digit comes back",
        tostring(row.strip[2].count.__text))
    CHECK(row.strip[2].pips[1].__shown ~= true, "...with the lights stood down")
    CommanderPartyFramesDB.PoMPips = true
    Tick()

    -- Someone else's Renew is not yours to maintain
    playerBuffs[1].sourceUnit = "party1"
    Tick()
    CHECK(row.strip[1].icon.__desat == true, "another priest's Renew does not count as yours")
    playerBuffs[1].sourceUnit = "player"
    Tick()

    -- About to drop: inside the refresh window the SLOT tints and pulses.
    -- Re-stamped against the CURRENT now before each look, since Tick()
    -- advances the clock and a 2s Renew would otherwise expire between them.
    local function Expiring()
        playerBuffs[1].expirationTime = now + 2
        Tick()
    end
    Expiring()
    local warn = row.strip[1].icon.__color or {}
    CHECK(warn[1] == 1 and warn[2] and warn[2] < 0.6,
        "an expiring Renew tints red", tostring(warn[2]))
    CHECK(warn[4] and warn[4] < 1, "and pulses while the flash is on", tostring(warn[4]))
    CommanderPartyFramesDB.RenewFlash = false
    Expiring()
    local steady = row.strip[1].icon.__color or {}
    CHECK(steady[4] == 1, "with the flash off it tints amber without pulsing",
        tostring(steady[4]))
    CHECK(steady[2] and steady[2] > 0.5, "...amber, not the pulse's red", tostring(steady[2]))
    CommanderPartyFramesDB.RenewFlash = true

    -- Expiry prunes it back to the ghost
    playerBuffs = {}
    Tick()
    CHECK(row.strip[1].cd.__shown == false, "a Renew that fell off clears its sweep")
    CHECK(row.strip[1].icon.__desat == true, "...and goes back to the ghost")

    -- Untracking gives the width back
    local withStrip = row._barW
    CommanderPartyFramesDB.BuffTrack["PWS:RENEW"] = false
    CommanderPartyFramesDB.BuffTrack["PWS:POM"] = false
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Tick()
    CHECK(row._barW > withStrip, "dropping both slots hands the width back to the bar",
        string.format("%s -> %s", tostring(withStrip), tostring(row._barW)))
    CommanderPartyFramesDB.BuffTrack["PWS:RENEW"] = nil
    CommanderPartyFramesDB.BuffTrack["PWS:POM"] = nil
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Tick()
    CHECK(#caughtErrors == 0, "no errors across the priest strip", caughtErrors[1])

    -- =====================================================================
    -- The health bar's colour reads HEALTH, not the bar's fill ratio.
    --
    -- On this board the fill is compressed to leave room for the shield
    -- segments chained off it, so a full-health ally carrying a shield has a
    -- ratio well under one. Colouring from that ratio meant shielding a
    -- healthy teammate visibly darkened their bar toward amber — the board
    -- reporting them as hurt because you had just protected them.
    -- =====================================================================
    playerBuffs = {}
    playerHealth = 100
    Tick()
    local bare = row.bar.__color or {}
    CHECK(bare[2] and bare[2] > 0.7 and bare[1] and bare[1] < 0.3,
        "a full-health ally is green",
        string.format("%.2f %.2f", bare[1] or -1, bare[2] or -1))

    playerBuffs = { { name = "Power Word: Shield", spellId = 17,
        expirationTime = now + 25, duration = 30, applications = 0,
        icon = "Interface\\Icons\\Spell_Holy_PowerWordShield", sourceUnit = "player" } }
    Tick()
    local shielded = row.bar.__color or {}
    CHECK((row.bar.__w or 0) < (row._barW or 0) - 0.5,
        "the shield compresses the fill to make room for its segment",
        string.format("%.1f of %.1f", row.bar.__w or -1, row._barW or -1))
    CHECK(math.abs((shielded[1] or 0) - (bare[1] or 0)) < 0.01
        and math.abs((shielded[2] or 0) - (bare[2] or 0)) < 0.01,
        "...and shielding a full-health ally does not darken them",
        string.format("%.2f %.2f vs %.2f %.2f", shielded[1] or -1, shielded[2] or -1,
            bare[1] or -1, bare[2] or -1))
    playerBuffs = {}

    -- ...and the ramp itself reaches red sooner than it used to. Two-thirds
    -- health in an arena is one connect from dead, and the old linear ramp
    -- still painted it a calm yellow-green (r 0.69, g 0.64).
    playerHealth = 65
    Tick()
    local amber = row.bar.__color or {}
    CHECK(amber[1] and amber[1] > 0.95, "two-thirds health is full amber, not yellow-green",
        string.format("%.2f %.2f", amber[1] or -1, amber[2] or -1))
    playerHealth = 25
    Tick()
    local red = row.bar.__color or {}
    CHECK(red[1] and red[1] > 0.95 and red[2] and red[2] < 0.3,
        "and a quarter health is properly red",
        string.format("%.2f %.2f", red[1] or -1, red[2] or -1))
    CHECK(red[2] < amber[2] and amber[2] < bare[2],
        "the ramp is monotone from green through amber to red")
    playerHealth = 100
    Tick()

    -- =====================================================================
    -- A shieldless ally: the state still does its work, the WORD is gone.
    -- =====================================================================
    playerBuffs, unitDebuffs = {}, {}
    playerHealth = 100
    Tick()
    CHECK(row.left.__text ~= "READY", "a shieldable ally is not labelled READY",
        tostring(row.left.__text))
    -- The slot is not left blank: the board already falls back to WHOSE bar
    -- this is when a row has nothing to say there, so dropping the word hands
    -- that span to the ally's name rather than to nothing.
    CHECK(row.left.__text == "Tester", "...the span goes back to their name",
        tostring(row.left.__text))
    CHECK(row.stripe.__alpha ~= nil and row.stripe.__alpha < 1,
        "...and the state still pulses the stripe", tostring(row.stripe.__alpha))

    -- The other state words are untouched: EXPOSED still says EXPOSED,
    -- because a Weakened Soul you cannot shield through is worth a word.
    unitDebuffs["player"] = { { name = "Weakened Soul", expirationTime = now + 12,
        duration = 15, icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain" } }
    Tick()
    CHECK(row.left.__text == "EXPOSED", "a Weakened Soul ally still reads EXPOSED",
        tostring(row.left.__text))
    unitDebuffs["player"] = {}
    Tick()

    -- =====================================================================
    -- The low-health ring: they want a Renew and have none of ours.
    -- =====================================================================
    local function NeedRing(f)
        local n, a = 0, 0
        for i = 1, 4 do
            if f.needGlow[i].__shown then
                n = n + 1
                local c = f.needGlow[i].__color or {}
                a = c[4] or 0
            end
        end
        return n, a
    end
    CommanderPartyFramesDB.RenewNeedRing = true
    CommanderPartyFramesDB.RenewNeedAt = 85
    playerHealth = 100
    Tick()
    CHECK(NeedRing(row) == 0, "a healthy ally wears no low-health ring")

    playerHealth = 70
    Tick()
    local segs, faint = NeedRing(row)
    CHECK(segs == 4, "a low ally with nothing rolling on them rings", tostring(segs))
    CHECK(faint > 0 and faint < 0.5, "...faintly", tostring(faint))

    playerHealth = 30
    Tick()
    local _, deep = NeedRing(row)
    CHECK(deep > faint, "...and it deepens as they fall",
        string.format("%.2f -> %.2f", faint, deep))

    -- A Renew of ours answers it, whether or not Renew has a slot on the
    -- strip: hiding the icon is a display choice, not a healing decision.
    CommanderPartyFramesDB.BuffTrack["PWS:RENEW"] = false
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    playerBuffs = { { name = "Renew", expirationTime = now + 14, duration = 15,
        icon = "Interface\\Icons\\Spell_Holy_Renew", sourceUnit = "player" } }
    Tick()
    CHECK(NeedRing(row) == 0, "our Renew answers it, even with the slot untracked")

    -- ...and another priest's does not. The question is what YOU have on them.
    playerBuffs[1].sourceUnit = "party1"
    Tick()
    CHECK(NeedRing(row) == 4, "another priest's Renew is not yours and does not")
    playerBuffs = {}
    CommanderPartyFramesDB.BuffTrack["PWS:RENEW"] = nil
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)

    CommanderPartyFramesDB.RenewNeedAt = 25
    Tick()
    CHECK(NeedRing(row) == 0, "and the threshold is the threshold")
    CommanderPartyFramesDB.RenewNeedAt = 85
    Tick()
    CommanderPartyFramesDB.RenewNeedRing = false
    Tick()
    CHECK(NeedRing(row) == 0, "...and Off draws no low-health ring")
    CommanderPartyFramesDB.RenewNeedRing = true
    playerHealth = 100
    Tick()

    -- =====================================================================
    -- The border rings: a second timer on an icon that already has one,
    -- drawn around its own edge so it costs the row no width at all.
    -- =====================================================================
    -- Perimeter actually drawn, in pixels. Segments 2 and 4 are the vertical
    -- sides, so their length is their height; the other three are horizontal.
    local function RingLen(o)
        local total = 0
        for i = 1, 5 do
            local t = o[i]
            if t.__shown then
                total = total + ((i == 2 or i == 4) and (t.__h or 0) or (t.__w or 0))
            end
        end
        return total
    end
    local function RingSegs(o)
        local n = 0
        for i = 1, 5 do if o[i].__shown then n = n + 1 end end
        return n
    end

    playerBuffs, unitDebuffs = {}, {}
    playerHealth = 100
    Tick()
    CHECK(RingSegs(row.lockRing) == 0, "a shieldable ally wears no reshield ring",
        tostring(RingSegs(row.lockRing)))

    -- A fresh Weakened Soul is the whole border; it drains from there.
    local ringSize = row._ringSize or 18
    -- Stamped a second long, because Tick() scans at `now` and then advances
    -- the clock before the row paints: the paint has to land on a full
    -- fifteen, not on the fourteen a bare `now + 15` would leave it.
    unitDebuffs["player"] = { { name = "Weakened Soul", expirationTime = now + 16,
        duration = 15, icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain" } }
    Tick()
    local full = RingLen(row.lockRing)
    CHECK(RingSegs(row.lockRing) == 5, "a fresh Weakened Soul closes the whole ring",
        tostring(RingSegs(row.lockRing)))
    CHECK(math.abs(full - ringSize * 4) < 1.0,
        "...and the whole ring is the icon's whole perimeter",
        string.format("%.1f vs %.1f", full, ringSize * 4))

    unitDebuffs["player"][1].expirationTime = now + 8.5
    Tick()
    local half = RingLen(row.lockRing)
    CHECK(math.abs(half - ringSize * 2) < 1.5,
        "half a lockout is half a ring — it DRAINS, like every other lockout here",
        string.format("%.1f vs %.1f", half, ringSize * 2))

    CommanderPartyFramesDB.ShieldLockRing = false
    Tick()
    CHECK(RingSegs(row.lockRing) == 0, "...and the setting stands it down")
    CommanderPartyFramesDB.ShieldLockRing = true
    unitDebuffs["player"] = {}
    Tick()
    CHECK(RingSegs(row.lockRing) == 0, "a lockout that expired takes its ring with it")

    -- Mending's ring is the SPELL's cooldown, and it is drawn on every row's
    -- slot: one travelling object, one answer to "can I cast it here".
    CommanderPartyFramesDB.BuffTrack["PWS:POM"] = true
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    local baseCd = GetSpellCooldown
    Tick()
    CHECK(RingSegs(row.strip[2].ring) == 0, "an off-cooldown Mending wears no ring")

    -- Name-aware, because that is the shape of the truth: Mending has a real
    -- ten-second cooldown and Power Word: Shield has none at all. A mock that
    -- hands both spells the same window is describing a global, and the ring
    -- is right to ignore it.
    local function CdBook(book)
        GetSpellCooldown = function(name)
            local e = book[name]
            if not e then return 0, 0, 1 end
            return e[1], e[2], 1
        end
    end
    CdBook({ ["Prayer of Mending"] = { now, 10 } })
    Tick()
    CHECK(RingSegs(row.strip[2].ring) > 0, "a Mending on cooldown closes its ring",
        tostring(RingSegs(row.strip[2].ring)))
    -- The slot is DARK here — nobody in this mock is carrying it — which is
    -- exactly the case the ring exists for: a dark slot with a ring is on
    -- cooldown, a dark slot without one is castable this instant.
    CHECK(row.strip[2].icon.__desat == true, "...even on a row not carrying it")

    -- The global cooldown is not a cooldown. Every cast puts 1.5s on every
    -- spell you own, and a ring that closed after every global would be a
    -- strobe saying "you just cast something".
    function GetSpellCooldown() return now, 1.5, 1 end
    Tick()
    CHECK(RingSegs(row.strip[2].ring) == 0, "the global cooldown draws no ring")

    -- ...and it is IDENTITY that rules it out, not the 1.5s bound. Two
    -- different spells cannot coincidentally share a cooldown window, so a
    -- window both of them report belongs to neither — which holds even when
    -- it is longer than any global we would have thought to hard-code.
    function GetSpellCooldown() return now, 20, 1 end
    unitDebuffs["player"] = { { name = "Weakened Soul", expirationTime = now + 6,
        duration = 15, icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain" } }
    Tick()
    CHECK(RingSegs(row.strip[2].ring) == 0,
        "two spells sharing one window is the global, whatever its length",
        tostring(RingSegs(row.strip[2].ring)))
    local wsOnly = RingLen(row.lockRing)
    CHECK(math.abs(wsOnly - ringSize * 4 * (5 / 15)) < 1.5,
        "...and the reshield ring still reads Weakened Soul, not that window",
        string.format("%.1f vs %.1f", wsOnly, ringSize * 4 * (5 / 15)))
    unitDebuffs["player"] = {}

    -- A genuine cooldown on one spell while the other only has the global:
    -- the two windows differ, so the real one is real and gets its ring.
    CdBook({ ["Prayer of Mending"] = { now, 10 },
             ["Power Word: Shield"] = { now, 1.5 } })
    Tick()
    CHECK(RingSegs(row.strip[2].ring) > 0,
        "a real cooldown running under a global is still a real cooldown",
        tostring(RingSegs(row.strip[2].ring)))

    CdBook({ ["Prayer of Mending"] = { now, 10 } })
    CommanderPartyFramesDB.PoMCooldownRing = false
    Tick()
    CHECK(RingSegs(row.strip[2].ring) == 0, "...and the setting stands that one down too")
    CommanderPartyFramesDB.PoMCooldownRing = true
    GetSpellCooldown = baseCd
    Tick()

    -- =====================================================================
    -- The Mending tracker.
    --
    -- Everything below is driven through the COMBAT LOG rather than the aura
    -- scan, on purpose: the object moves between allies the mock does not
    -- have, and the log is the channel that carries a hop. What is asserted
    -- is the user-visible contract and nothing else — when a sound happens,
    -- when a row flashes, and what colour it is — because "it does not fire
    -- on a bounce" is a statement about what you HEAR, not about internals.
    -- =====================================================================
    CommanderPartyFramesDB.BuffTrack["PWS:POM"] = true
    CommanderPartyFramesDB.PoMAlert = true
    CommanderPartyFramesDB.PoMAlertSound = true
    CommanderPartyFramesDB.PoMTrail = true
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    playerBuffs = {}
    Tick()

    -- CombatLogGetCurrentEventInfo's shape: eleven header fields, then
    -- spellId, spellName, school, and the payload. A dispel is the odd one —
    -- the caster is the ENEMY and the buff they took is the extra spell.
    local function PoM(subevent, destGUID)
        local e = { now, subevent, false, "player-guid", "Tester", 0, 0,
                    destGUID, "Ally", 0, 0, 33076, "Prayer of Mending", 2 }
        if subevent == "SPELL_DISPEL" or subevent == "SPELL_STOLEN" then
            e[4], e[13] = "enemy-guid", "Dispel Magic"
            e[15], e[16] = 33076, "Prayer of Mending"
        end
        __setClog(e)
        Fire("COMBAT_LOG_EVENT_UNFILTERED")
    end
    -- Advances the clock and draws WITHOUT firing UNIT_AURA, so the aura
    -- scan (which on this mock can only ever see the player, and would report
    -- every off-player holder as missing) stays out of the way.
    local function Advance(dt)
        now = now + dt
        for _, f in ipairs(allFrames) do PumpFrame(f, 10) end
    end
    -- One full hop, log-accurate: the charge fires, the aura leaves, and the
    -- object turns up on the next ally a fraction later.
    local function Hop(from, to, gap)
        PoM("SPELL_HEAL", from)
        PoM("SPELL_AURA_REMOVED", from)
        Advance(gap or 0.2)
        PoM("SPELL_AURA_APPLIED", to)
    end

    __clearSounds()
    PoM("SPELL_AURA_APPLIED", "ally-1")
    Advance(2)
    CHECK(#__sounds == 0, "casting Mending is not an alert", tostring(#__sounds))

    -- The one that matters. A bounce IS a charge firing and the aura leaving
    -- an ally — the exact shape of a loss — and it must stay silent through
    -- the whole of it, mid-flight included.
    PoM("SPELL_HEAL", "ally-1")
    PoM("SPELL_AURA_REMOVED", "ally-1")
    Advance(0.3)
    CHECK(#__sounds == 0, "a Mending in mid-hop says nothing yet", tostring(#__sounds))
    PoM("SPELL_AURA_APPLIED", "ally-2")
    Advance(2)
    CHECK(#__sounds == 0, "and a completed bounce never alerts", tostring(#__sounds))

    -- Four of them, which is what a full cast actually does. An alert hung
    -- off "the aura left this row" would have made four noises by here.
    Hop("ally-2", "ally-3")
    Advance(1)
    Hop("ally-3", "ally-1")
    Advance(1)
    Hop("ally-1", "player-guid")
    Advance(1)
    CHECK(#__sounds == 0, "four hops in and still silent", tostring(#__sounds))

    -- The fifth charge has nowhere to go. Identical log to a bounce right up
    -- until the grace lapses with nothing having re-applied.
    PoM("SPELL_HEAL", "player-guid")
    PoM("SPELL_AURA_REMOVED", "player-guid")
    Advance(0.4)
    CHECK(#__sounds == 0, "the last charge waits out the grace like any other",
        tostring(#__sounds))
    Advance(0.6)
    CHECK(#__sounds == 1, "a spent Mending alerts, once", tostring(#__sounds))
    local spentSound = __sounds[1]
    CHECK(row.flash.__shown == true, "and flashes the ally who was holding it")
    local ft = row.flash.__color or {}
    CHECK(ft[2] and ft[2] > 0.8 and ft[1] and ft[1] < 0.8,
        "...green, because a spent Mending did its job", tostring(ft[1]))
    Advance(2)
    CHECK(#__sounds == 1, "and it does not repeat itself", tostring(#__sounds))

    -- Timed out with no removal ever arriving: the holder walked out of the
    -- combat log with it on them, and thirty seconds is still thirty seconds.
    __clearSounds()
    PoM("SPELL_AURA_APPLIED", "player-guid")
    Advance(5)
    CHECK(#__sounds == 0, "a live Mending is quiet", tostring(#__sounds))
    Advance(26)
    CHECK(#__sounds == 1, "one that timed out of log range still alerts",
        tostring(#__sounds))
    local et = row.flash.__color or {}
    CHECK(et[1] and et[1] > 0.9 and et[2] and et[2] > 0.6 and et[3] and et[3] < 0.4,
        "...amber for expired", tostring(et[3]))

    -- A recast onto the ally who already had it restarts the clock. Getting
    -- this wrong is a LIVE Mending reported as expired a second later.
    __clearSounds()
    PoM("SPELL_AURA_APPLIED", "player-guid")
    Advance(29)
    PoM("SPELL_AURA_REFRESH", "player-guid")
    Advance(3)
    CHECK(#__sounds == 0, "a refreshed Mending is not an expired one",
        tostring(#__sounds))

    -- Moving it yourself is not losing it.
    PoM("SPELL_AURA_APPLIED", "ally-9")
    Advance(2)
    CHECK(#__sounds == 0, "recasting it onto someone else is silent",
        tostring(#__sounds))

    -- Taken off you: same removal, a different instruction, a different colour
    __clearSounds()
    PoM("SPELL_AURA_APPLIED", "player-guid")
    Advance(2)
    PoM("SPELL_DISPEL", "player-guid")
    PoM("SPELL_AURA_REMOVED", "player-guid")
    Advance(1)
    CHECK(#__sounds == 1, "a dispelled Mending alerts", tostring(#__sounds))
    -- Mending's own voice: one instrument, two pitches. Spent and lost have
    -- to be distinguishable without looking at the board, which is the entire
    -- reason the alert exists — and neither may be the stock raid warning the
    -- shield-break alert (and half the client's other addons) already uses.
    local lostSound = __sounds[1]
    CHECK(spentSound ~= nil and lostSound ~= nil, "both Mending ends make a sound")
    CHECK(spentSound ~= lostSound, "...and spent does not sound like lost",
        tostring(spentSound) .. " vs " .. tostring(lostSound))
    CHECK(spentSound ~= 8959 and lostSound ~= 8959,
        "...neither borrows the raid warning")
    local dt = row.flash.__color or {}
    CHECK(dt[3] and dt[3] > 0.9 and dt[2] and dt[2] < 0.7,
        "...violet, so you can tell it was stolen rather than spent",
        tostring(dt[3]))

    -- The holder dying takes it with them
    __clearSounds()
    PoM("SPELL_AURA_APPLIED", "player-guid")
    Advance(2)
    PoM("UNIT_DIED", "player-guid")
    PoM("SPELL_AURA_REMOVED", "player-guid")
    Advance(1)
    CHECK(#__sounds == 1, "a Mending that died with its holder alerts",
        tostring(#__sounds))

    -- Both halves switch off independently
    CommanderPartyFramesDB.PoMAlertSound = false
    __clearSounds()
    PoM("SPELL_AURA_APPLIED", "player-guid")
    Advance(2)
    PoM("SPELL_HEAL", "player-guid")
    PoM("SPELL_AURA_REMOVED", "player-guid")
    Advance(1)
    CHECK(#__sounds == 0, "End Sound off silences the alert", tostring(#__sounds))
    CHECK(row.flash.__shown == true, "...and leaves the flash")

    CommanderPartyFramesDB.PoMAlert = false
    __clearSounds()
    PoM("SPELL_AURA_APPLIED", "player-guid")
    Advance(2)
    PoM("SPELL_HEAL", "player-guid")
    PoM("SPELL_AURA_REMOVED", "player-guid")
    Advance(3)
    CHECK(#__sounds == 0, "End Alert off silences both", tostring(#__sounds))
    CHECK(row.flash.__shown ~= true, "...including the flash")
    CommanderPartyFramesDB.PoMAlert = true
    CommanderPartyFramesDB.PoMAlertSound = true

    -- The hop's own cue: the row it LANDS on flares. (The row it leaves gets
    -- the fading ghost, which this mock's single ally cannot hold both ends
    -- of at once.)
    playerBuffs = { { name = "Prayer of Mending", expirationTime = now + 28,
        duration = 30, applications = 3, icon = "Interface\\Icons\\Spell_33076",
        sourceUnit = "player" } }
    PoM("SPELL_AURA_APPLIED", "ally-1")
    Advance(1)
    Hop("ally-1", "player-guid")
    -- Deliberately NOT Tick(), which would advance a full second and land
    -- after the flare has already decayed: the cue is half a second long
    -- because a hop is worth exactly one glance.
    Fire("UNIT_AURA", "player")
    Advance(0.1)
    CHECK(row.strip[2].flare.__shown == true, "the row a Mending lands on flares")
    CommanderPartyFramesDB.PoMTrail = false
    Advance(0.05)
    CHECK(row.strip[2].flare.__shown ~= true, "...and Show the Hop off stands it down")
    CommanderPartyFramesDB.PoMTrail = true
    Advance(0.6)
    CHECK(row.strip[2].flare.__shown ~= true, "...and the flare puts itself away")

    -- The sound each alert plays is a setting, and the alert honours it.
    CommanderPartyFramesDB.SoundPoMSpent = "NONE"
    __clearSounds()
    PoM("SPELL_AURA_APPLIED", "player-guid")
    Advance(2)
    PoM("SPELL_HEAL", "player-guid")
    PoM("SPELL_AURA_REMOVED", "player-guid")
    Advance(1)
    CHECK(#__sounds == 0, "a Mending line set to Silent plays nothing",
        tostring(#__sounds))
    CHECK(row.flash.__shown == true, "...but still flashes — Silent is a sound, not a mute")
    CommanderPartyFramesDB.SoundPoMSpent = "READY"
    __clearSounds()
    PoM("SPELL_AURA_APPLIED", "player-guid")
    Advance(2)
    PoM("SPELL_HEAL", "player-guid")
    PoM("SPELL_AURA_REMOVED", "player-guid")
    Advance(1)
    CHECK(#__sounds == 1 and __sounds[1] ~= spentSound,
        "...and a different pick makes a different noise", tostring(__sounds[1]))
    CommanderPartyFramesDB.SoundPoMSpent = "TOLL_HI"

    -- The master switch. One feature, one gate: with it off the tracker does
    -- no work, so nothing sounds, nothing flashes and nothing flares — and,
    -- the part worth a check of its own, an object that was in flight when it
    -- was switched off must not resolve into an alert when it comes back on.
    playerBuffs = {}
    CommanderPartyFramesDB.PoMTrack = false
    __clearSounds()
    PoM("SPELL_AURA_APPLIED", "player-guid")
    Advance(2)
    PoM("SPELL_HEAL", "player-guid")
    PoM("SPELL_AURA_REMOVED", "player-guid")
    Advance(3)
    CHECK(#__sounds == 0, "Track Mending off makes no sound", tostring(#__sounds))
    CHECK(row.flash.__shown ~= true, "...and no flash")
    CommanderPartyFramesDB.PoMTrack = true
    Advance(3)
    CHECK(#__sounds == 0, "...and switching it back on does not fire what it missed",
        tostring(#__sounds))

    -- Live at the moment it is switched off: the session is dropped, not
    -- parked, so it cannot resolve late either.
    __clearSounds()
    PoM("SPELL_AURA_APPLIED", "player-guid")
    Advance(2)
    CommanderPartyFramesDB.PoMTrack = false
    Advance(1)
    CommanderPartyFramesDB.PoMTrack = true
    PoM("SPELL_AURA_REMOVED", "player-guid")
    Advance(3)
    CHECK(#__sounds == 0, "a session dropped by the switch never resolves",
        tostring(#__sounds))

    -- ...and it works again straight afterwards, from a clean cast
    PoM("SPELL_AURA_APPLIED", "player-guid")
    Advance(2)
    PoM("SPELL_HEAL", "player-guid")
    PoM("SPELL_AURA_REMOVED", "player-guid")
    Advance(1)
    CHECK(#__sounds == 1, "and the very next cast tracks normally", tostring(#__sounds))

    playerBuffs = {}
    CommanderPartyFramesDB.BuffTrack["PWS:POM"] = nil
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Tick()
    CHECK(#caughtErrors == 0, "no errors across the Mending tracker", caughtErrors[1])
end

-- ===========================================================================
-- Include Pets: an ally's pet is an ally row
-- ===========================================================================
-- Chassis, not a layer — every board that exists gets this — so it is a
-- shared check both exit paths run, the way CheckBlizzToggle is.
--
-- The whole point of the option is reach: a healer should be able to buff and
-- heal someone else's pet with the same click they use on the player standing
-- next to it. So the pet has to arrive as a REAL ally row — health, identity,
-- its own token — while staying out of the two things it has no business in:
-- the class ability book (a pet has no class cooldowns of its own) and the
-- top of the sort (a pet is never the row that decides the fight).
--
-- Everything it reaches into is restored on the way out: this runs mid-file
-- on the mage path, and the sections after it assume the plain unit mock.
-- ===========================================================================
-- The ally-buff strip: permanent slots, and the urgency read
-- ===========================================================================
-- The rule the whole board now obeys: a tracker never disappears when the
-- thing it tracks is gone — it goes dark in place. A slot that empties is a
-- hole exactly where the answer should be, and it makes every icon to its
-- right shuffle. Checked on the mage board here because Arcane Intellect used
-- to be the loudest exception: it hid itself whenever the buff was healthy.
local function CheckBuffStrip()
    if CLASS ~= "MAGE" then return end
    local keepIcon = CommanderPartyFramesDB.ShowSpellIcon
    CommanderPartyFramesDB.ShowSpellIcon = true
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    local function Pump()
        now = now + 1
        for _, f in ipairs(allFrames) do
            local u = f.__scripts.OnUpdate
            PumpFrame(f, 10)
        end
    end
    local function IntRow()
        for _, f in ipairs(allFrames) do
            if f.bar and f.spellIcon and f.stripe and f.__shown and f.__h ~= 11 then return f end
        end
    end

    playerBuffs = { { name = "Arcane Intellect", expirationTime = now + 1500,
        duration = 1800, icon = "Interface\\Icons\\Spell_1459", sourceUnit = "player" } }
    Fire("UNIT_AURA", "player"); Pump()
    local row = IntRow()
    CHECK(row ~= nil, "an ally row is on the mage board")
    if row then
        local ai = row.buffs[1]
        CHECK(ai.icon.__shown == true and ai.icon.__desat == false,
            "a healthy Arcane Intellect keeps its slot, lit")
        CHECK(ai.cd.__shown == true and ai.cd.__cdDur == 1800,
            "...with its duration on the sweep", tostring(ai.cd.__cdDur))
        playerBuffs = {}
        Fire("UNIT_AURA", "player"); Pump()
        CHECK(ai.icon.__shown == true and ai.icon.__desat == true,
            "a missing one goes dark in place rather than vanishing")
        CHECK(ai.cd.__shown == false, "...and running no sweep")

        -- ---- The urgency read ------------------------------------------
        -- Arcane Intellect's rule is ALWAYS: there is no fight where you
        -- would rather your caster did not have it, so missing IS urgent and
        -- the slot earns red rather than the neutral dark.
        local red = ai.icon.__color or {}
        CHECK(red[1] and red[1] > 0.5 and red[2] and red[2] < 0.3,
            "an always-worth-it buff turns dark RED when it is missing",
            tostring(red[1]) .. "," .. tostring(red[2]))

        -- Out of range: not a decision you are failing to make. Red there is
        -- a slot complaining about physics, and it teaches you to ignore red.
        -- Has to be an ALLY, not the player: you are always in range of
        -- yourself, and the resolver skips the check on your own row.
        do
            local baseExists, baseGUID, baseRange = UnitExists, UnitGUID, UnitInRange
            -- Only the ally on the board, so there is no guessing which
            -- pooled row the sort handed out second
            local keepSelf = CommanderPartyFramesDB.IncludeSelf
            CommanderPartyFramesDB.IncludeSelf = false
            partyUp = { party1 = true }
            function UnitExists(unit)
                if unit and unit:find("^party") then return partyUp[unit] == true end
                return baseExists(unit)
            end
            function UnitGUID(unit)
                if unit and unit:find("^party") then return unit .. "-guid" end
                return baseGUID(unit)
            end
            Fire("GROUP_ROSTER_UPDATE"); Pump()
            -- The ally's row is the second one the pool hands out
            local allyRow
            for _, f in ipairs(allFrames) do
                if f.buffs and f.bar and f.stripe and f.__shown and f.__h ~= 11 then
                    allyRow = f break
                end
            end
            CHECK(allyRow ~= nil, "an ally row is on the board to range-check")
            if allyRow then
                local slot = allyRow.buffs[1]
                local near = slot.icon.__color or {}
                CHECK(near[1] and near[1] > 0.5,
                    "in range, a missing always-worth-it buff is red", tostring(near[1]))
                function UnitInRange() return false, true end
                Fire("GROUP_ROSTER_UPDATE"); Pump()
                local far = slot.icon.__color or {}
                CHECK(far[1] and far[1] < 0.5,
                    "out of range it is dark, not red — you cannot act on it",
                    tostring(far[1]))
                CHECK(slot.icon.__shown == true, "...but the slot is still there")
            end
            UnitExists, UnitGUID, UnitInRange = baseExists, baseGUID, baseRange
            CommanderPartyFramesDB.IncludeSelf = keepSelf
            partyUp = {}
            Fire("GROUP_ROSTER_UPDATE"); Pump()
        end

        -- A REAL cooldown on the spell itself means the same thing: report the
        -- absence, demand nothing. The global cooldown must NOT count, or every
        -- slot on the board would blink dark twice a second while you play.
        local baseCd = GetSpellCooldown
        function GetSpellCooldown() return now - 1, 1.5, 1 end     -- a GCD
        Fire("UNIT_AURA", "player"); Pump()
        local gcd = ai.icon.__color or {}
        CHECK(gcd[1] and gcd[1] > 0.5,
            "the global cooldown does not silence the advisor", tostring(gcd[1]))
        function GetSpellCooldown() return now, 30, 1 end          -- a real one
        Fire("UNIT_AURA", "player"); Pump()
        local cooling = ai.icon.__color or {}
        CHECK(cooling[1] and cooling[1] < 0.5,
            "a real cooldown does — you cannot cast it right now",
            tostring(cooling[1]))
        GetSpellCooldown = baseCd
        Fire("UNIT_AURA", "player"); Pump()

        -- Master switch off: the slot still tracks, it just stops judging
        CommanderPartyFramesDB.BuffAdvisor = false
        Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
        Fire("UNIT_AURA", "player"); Pump()
        local neutral = ai.icon.__color or {}
        CHECK(ai.icon.__shown == true, "with the advisor off the slot is still there")
        CHECK(neutral[1] and neutral[1] < 0.5 and neutral[2] and neutral[2] < 0.5,
            "...but back to neutral dark, not red",
            tostring(neutral[1]) .. "," .. tostring(neutral[2]))
        CommanderPartyFramesDB.BuffAdvisor = true

        -- Per-buff switch: one slot can be told to stop judging on its own
        CommanderPartyFramesDB.BuffAdvise = { ["INT:AI"] = false }
        Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
        Fire("UNIT_AURA", "player"); Pump()
        local hushed = ai.icon.__color or {}
        CHECK(hushed[1] and hushed[1] < 0.5,
            "a single slot can be hushed without touching the others",
            tostring(hushed[1]))
        CommanderPartyFramesDB.BuffAdvise = {}
        Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)

        -- ---- The situational rules never guess ---------------------------
        -- Amplify Magic is only free healing against a team that deals no
        -- magic damage. With nothing known about the other side, the honest
        -- answer is silence — "we have not looked" must never read as "safe".
        CommanderPartyFramesDB.BuffTrack = { ["INT:AMP"] = true }
        Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
        Fire("UNIT_AURA", "player"); Pump()
        local amp = row.buffs[2]
        CHECK(amp.icon.__shown == true, "Amplify takes a slot once it is tracked")
        local q = amp.icon.__color or {}
        CHECK(q[1] and q[1] < 0.5,
            "...and stays neutral while the enemy team is unknown", tostring(q[1]))

        -- Now put a visible all-physical team on the field. Amplify becomes
        -- the free global it is against melee, and the slot says so.
        local baseClass, baseExists = UnitClass, UnitExists
        function UnitClass(unit)
            if unit == "arena1" then return "Warrior", "WARRIOR" end
            if unit == "arena2" then return "Rogue", "ROGUE" end
            return baseClass(unit)
        end
        function UnitExists(unit)
            if unit == "arena1" or unit == "arena2" then return true end
            return baseExists(unit)
        end
        now = now + 1                       -- clear the quarter-second throttle
        Fire("UNIT_AURA", "player"); Pump()
        local hot2 = amp.icon.__color or {}
        CHECK(hot2[1] and hot2[1] > 0.5 and hot2[2] and hot2[2] < 0.3,
            "against an all-physical team the Amplify slot goes red",
            tostring(hot2[1]) .. "," .. tostring(hot2[2]))

        -- Swap one of them for a mage and the same slot goes quiet again:
        -- Amplify into casters is handing them your throat.
        function UnitClass(unit)
            if unit == "arena1" then return "Mage", "MAGE" end
            if unit == "arena2" then return "Rogue", "ROGUE" end
            return baseClass(unit)
        end
        now = now + 1
        Fire("UNIT_AURA", "player"); Pump()
        local quiet = amp.icon.__color or {}
        CHECK(quiet[1] and quiet[1] < 0.5,
            "one enemy caster is enough to take the Amplify advice back",
            tostring(quiet[1]))

        -- ---- The sibling rule -------------------------------------------
        -- Amplify and Dampen overwrite each other on the target, so whichever
        -- is up makes the other's absence CORRECT. Neither may nag while its
        -- sibling is doing the job — two contradictory red slots on one row is
        -- worse advice than none.
        function UnitClass(unit)
            if unit == "arena1" then return "Warrior", "WARRIOR" end
            if unit == "arena2" then return "Rogue", "ROGUE" end
            return baseClass(unit)
        end
        playerBuffs = { { name = "Dampen Magic", expirationTime = now + 500,
            duration = 600, icon = "Interface\\Icons\\Spell_604", sourceUnit = "player" } }
        now = now + 1
        Fire("UNIT_AURA", "player"); Pump()
        local sib = amp.icon.__color or {}
        CHECK(sib[1] and sib[1] < 0.5,
            "Amplify stays quiet while Dampen is up — they are one decision",
            tostring(sib[1]))

        UnitClass, UnitExists = baseClass, baseExists
        playerBuffs = {}

        -- ---- The known-spell gate ---------------------------------------
        -- Dampen Magic is deliberately untrained in this mage's book. Tracking
        -- it must still produce nothing: a permanent dark reminder of a spell
        -- that is not in the spellbook is the emptiest pixel on the board.
        CommanderPartyFramesDB.BuffTrack = { ["INT:DAMPEN"] = true, ["INT:AMP"] = false }
        Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
        now = now + 1
        Fire("UNIT_AURA", "player"); Pump()
        local slots = 0
        for i = 1, 3 do if row.buffs[i].icon.__shown then slots = slots + 1 end end
        CHECK(slots == 1,
            "an untrained buff takes no slot however hard you track it", slots)

        CommanderPartyFramesDB.BuffTrack = {}
        Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
        now = now + 1
        Fire("UNIT_AURA", "player"); Pump()
    end
    CommanderPartyFramesDB.ShowSpellIcon = keepIcon
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Pump()
end

-- A buff nobody would cast here earns NO slot — not a dark one, not a red one.
-- Intellect and Divine Spirit do nothing for a rogue, and a permanent dark
-- reminder of a spell that would be wasted is worse than no slot at all. This
-- runs on every layer because the rule lives in the shared registry, and each
-- board has its own mana-only entries (Spirit on the priest's, Intellect on
-- the mage's) or none at all (the druid buffs everybody).
-- Shadow Protection's rule is the one that cannot be answered by reading
-- classes: a warlock is shadow by definition, but a shadow priest looks
-- exactly like a healer until they cast, and the buff is for both. So the
-- witness is the combat log — shadow-school damage actually landing, from
-- somebody who is not on our team.
-- The settings grid: the icon IS the switch. Worth testing because the whole
-- point of it is that "what am I watching" should be readable at a glance —
-- which means the lit/drained/struck-through states have to actually track
-- the DB, and an untrained spell has to refuse the click rather than writing
-- a setting that can never take effect.
-- Press a grid cell the way a mouse would
local function Press(cell, button)
    local fn = cell.__scripts and cell.__scripts.OnClick
    if fn then pcall(fn, cell, button) end
end

local function BuffTrackedForTest(def)
    local t = CommanderPartyFramesDB.BuffTrack
    local v = t and t[def.dbKey]
    if v == nil then return def.default and true or false end
    return v
end

-- The click matrix. Everything here is the kind of wrong that saves fine and
-- then silently never fires in game, which is exactly what a test is for.
-- "Mine only": the narrowest the ability bar goes without switching it off.
-- The settings framework sizes a section row off its wrapped subtext. It used
-- to assume two lines flat, so a longer note drew straight over the next
-- control — which is what put a checkbox on top of a paragraph on this very
-- page. Tested against the real framework, not a stand-in.
-- A row shorter than its own contents draws over whatever comes next. That is
-- not a subtle failure — it is a checkbox sitting on top of a paragraph, which
-- is exactly what shipped. The framework's own section rows are covered by
-- CheckSectionSizing; this holds the CUSTOM rows on this page to the same rule,
-- because those are hand-sized and there is nothing to catch a wrong constant.
local function CheckRowFit()
    local checked = 0
    for _, row in ipairs(allFrames) do
        -- Tagged rows: every child has to end above the row's bottom edge
        if row.probeChildren then
            local h = row.__h or 0
            for _, child in ipairs(row.probeChildren) do
                checked = checked + 1
                local ch = child.__h or 0
                CHECK(ch <= h,
                    "a custom settings row is tall enough for what is in it",
                    string.format("child %d in row %d", ch, h))
            end
        end
        -- The buff grid states the reach of its own last label
        if row.probeReach then
            checked = checked + 1
            CHECK((row.__h or 0) >= row.probeReach,
                "the ally-buff grid reserves room for the labels under its icons",
                string.format("%s < %s", tostring(row.__h), tostring(row.probeReach)))
        end
    end
    CHECK(checked > 0, "there were custom rows to measure", checked)
end

local function CheckSectionSizing()
    local panel = Commander.UI.NewPanel({
        key = "PFSectionSizingProbe",
        title = "Probe",
        addonName = "Commander_PartyFrames",
        description = "probe",
        -- The plain heading's own sizing is what this probes; a folding
        -- page measures its notes the foldout's way instead
        foldSections = false,
    })
    CHECK(panel ~= nil, "the settings framework builds a panel to probe")
    if not panel then return end

    local shortRow = panel:AddSection("Short", "One line.")
    local before = panel._contentHeight
    local longRow = panel:AddSection("Long", string.rep(
        "A section note long enough to wrap several times over. ", 8))
    local charged = panel._contentHeight - before

    CHECK(shortRow:GetHeight() == 40 and longRow:GetHeight() == 40,
        "both rows start at the framework's flat two-line guess")
    CHECK(charged == 40 + 14, "...and the panel is charged that much up front",
        charged)

    panel:Refresh()
    CHECK(shortRow:GetHeight() == 40,
        "a note that really does fit stays at two lines", shortRow:GetHeight())
    CHECK(longRow:GetHeight() > 40,
        "a note that does not fit grows its row instead of overlapping what follows",
        longRow:GetHeight())
    CHECK(panel._contentHeight > before + 40 + 14,
        "...and the growth is charged to the panel, so a scroll child sized"
        .. " from it does not clip the last rows")

    local grown = longRow:GetHeight()
    panel:Refresh()
    CHECK(longRow:GetHeight() == grown,
        "measuring is idempotent — repeated refreshes do not keep growing it",
        longRow:GetHeight() .. " vs " .. grown)
end

local function CheckAbilityScope()
    local keep = {
        CommanderPartyFramesDB.ShowAbilityBar, CommanderPartyFramesDB.AbilityBarSelf,
        CommanderPartyFramesDB.AbilityBarOnlySelf, CommanderPartyFramesDB.IncludeSelf,
    }
    local baseExists, baseGUID = UnitExists, UnitGUID
    partyUp = { party1 = true }
    function UnitExists(unit)
        if unit and unit:find("^party") then return partyUp[unit] == true end
        return baseExists(unit)
    end
    function UnitGUID(unit)
        if unit and unit:find("^party") then return unit .. "-guid" end
        return baseGUID(unit)
    end
    CommanderPartyFramesDB.ShowAbilityBar = true
    CommanderPartyFramesDB.AbilityBarSelf = true
    CommanderPartyFramesDB.AbilityBarOnlySelf = false
    CommanderPartyFramesDB.IncludeSelf = true
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)

    local function Pump()
        now = now + 1
        for _, f in ipairs(allFrames) do
            local u = f.__scripts.OnUpdate
            PumpFrame(f, 10)
        end
    end
    -- The parent row matters as much as the cell: pooled strips keep the cell
    -- visibility from whichever row last used them, so a cell can read shown
    -- inside a row the board has since hidden.
    local function Strips()
        local n = 0
        for _, f in ipairs(allFrames) do
            if f.cells and f.__shown and f.cells[1] and f.cells[1].frame
                and f.cells[1].frame.__shown then
                n = n + 1
            end
        end
        return n
    end
    Fire("GROUP_ROSTER_UPDATE"); Pump()
    local both = Strips()
    CHECK(both >= 2, "with two rows on the board, two strips are drawn", both)

    CommanderPartyFramesDB.AbilityBarOnlySelf = true
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Fire("GROUP_ROSTER_UPDATE"); Pump()
    CHECK(Strips() == 1, "Mine Only leaves exactly one — your own", Strips())

    -- ...and it is genuinely YOUR row that survived, not just the first one
    CommanderPartyFramesDB.IncludeSelf = false
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Fire("GROUP_ROSTER_UPDATE"); Pump()
    CHECK(Strips() == 0, "...so with your own row off the board, none are drawn",
        Strips())

    UnitExists, UnitGUID = baseExists, baseGUID
    partyUp = {}
    CommanderPartyFramesDB.ShowAbilityBar, CommanderPartyFramesDB.AbilityBarSelf,
        CommanderPartyFramesDB.AbilityBarOnlySelf, CommanderPartyFramesDB.IncludeSelf =
        keep[1], keep[2], keep[3], keep[4]
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Fire("GROUP_ROSTER_UPDATE"); Pump()
end

local function CheckClickMatrix()
    local mods = CommanderPartyFrames_GetClickMods()
    local btns = CommanderPartyFrames_GetClickButtons()
    CHECK(#mods == 8, "every modifier combination is offered, not just one", #mods)
    CHECK(#btns >= 3, "left, right and middle at minimum", #btns)

    -- Blizzard's secure code assembles its prefix as alt, then ctrl, then
    -- shift. Any other spelling produces an attribute name the client never
    -- looks up: the binding saves, and the click does nothing forever.
    local seen = {}
    for _, m in ipairs(mods) do seen[m.key] = true end
    CHECK(seen[""] and seen["shift-"] and seen["ctrl-"] and seen["alt-"],
        "the four single modifiers are there")
    CHECK(seen["alt-ctrl-shift-"], "...and the three-key combination")
    CHECK(seen["ctrl-shift-"] and seen["alt-shift-"] and seen["alt-ctrl-"],
        "...and each pair, in alt-ctrl-shift order")
    CHECK(not seen["shift-ctrl-"] and not seen["shift-alt-"],
        "no reversed spellings, which the client would never resolve")

    -- The picker only offers what this character has actually trained
    local byGroup, groups = CommanderPartyFrames_GetBindables()
    CHECK(#groups > 0, "the picker has something to offer", #groups)
    local offered = {}
    for _, g in ipairs(groups) do
        for _, sp in ipairs(byGroup[g]) do offered[sp.id] = true end
    end
    if CLASS == "MAGE" then
        CHECK(offered[1459] == true, "a trained spell is offered")
        CHECK(offered[604] == nil,
            "an untrained one is not — a binding to it could never fire")
    end

    -- Round-tripping a binding, including the cleared case, which is the one
    -- that used to leak: clearing has to beat the layer default rather than
    -- falling back through it
    local keepBinds = CommanderPartyFramesDB.ClickBinds
    CommanderPartyFramesDB.ClickBinds = {}
    local profile = CommanderPartyFrames_ActiveProfile()
    CHECK(type(profile) == "string" and profile ~= "",
        "there is an active binding profile", tostring(profile))
    local before = CommanderPartyFrames_GetBind("1")
    CHECK(before ~= nil, "an untouched profile still answers with the layer default",
        tostring(before))
    CommanderPartyFrames_SetBind("alt-ctrl-shift-3", 17)
    CHECK(CommanderPartyFrames_GetBind("alt-ctrl-shift-3") == 17,
        "a three-modifier middle-click round-trips")
    CommanderPartyFrames_SetBind("1", nil)
    CHECK(CommanderPartyFrames_GetBind("1") == nil,
        "clearing a cell means cleared, not back to the default",
        tostring(CommanderPartyFrames_GetBind("1")))

    -- Profiles are per talent build: a different build is a different set
    local other = "OTHERBUILD"
    CommanderPartyFramesDB.ClickProfileMode = "FIXED"
    CommanderPartyFramesDB.ClickProfileFixed = other
    CHECK(CommanderPartyFrames_ActiveProfile() == other,
        "a fixed profile overrides the talent read")
    CHECK(CommanderPartyFrames_GetBind("alt-ctrl-shift-3") == nil,
        "...and carries none of the other profile's bindings")
    CommanderPartyFramesDB.ClickProfileMode = "TALENT"
    CommanderPartyFramesDB.ClickProfileFixed = ""
    CHECK(CommanderPartyFrames_GetBind("alt-ctrl-shift-3") == 17,
        "switching back finds the first profile's bindings intact")

    -- A binding to something unknown is flagged rather than drawn as normal
    local _, label, missing = CommanderPartyFrames_BindDisplay(604)
    if CLASS == "MAGE" then
        CHECK(missing == true, "a binding this character cannot cast is flagged",
            tostring(label))
    end
    local icon2, label2 = CommanderPartyFrames_BindDisplay("TARGETTARGET")
    CHECK(icon2 ~= nil and label2:find("Assist") ~= nil,
        "the non-spell actions carry an icon and a readable label", tostring(label2))
    local _, label3 = CommanderPartyFrames_BindDisplay(nil)
    CHECK(label3 == "Unbound", "an empty cell says so", tostring(label3))

    -- ---- Profiles are manageable, not just switchable --------------------
    -- A profile you cannot copy or reset is one you will hand-rebuild
    -- twenty-four cells at a time after every respec.
    -- "alt-2" on purpose: no layer ships a default there, so the assertions
    -- below test the profile rather than accidentally matching a default
    CommanderPartyFramesDB.ClickBinds = {}
    CommanderPartyFrames_SetBind("alt-2", 2006)
    CommanderPartyFrames_SetBind("1", nil)                -- deliberately cleared
    local src = CommanderPartyFrames_ActiveProfile()

    CommanderPartyFramesDB.ClickProfileMode = "FIXED"
    CommanderPartyFramesDB.ClickProfileFixed = "COPYTARGET"
    CHECK(CommanderPartyFrames_GetBind("alt-2") == nil,
        "a fresh profile does not inherit another's bindings",
        tostring(CommanderPartyFrames_GetBind("alt-2")))
    CHECK(CommanderPartyFrames_GetBind("1") ~= nil,
        "...and still answers with its own layer default")

    local list = CommanderPartyFrames_ListProfiles({})
    CHECK(#list >= 2, "both profiles are listed for the copy menu", #list)

    CHECK(CommanderPartyFrames_CopyProfile(src, "COPYTARGET") == true,
        "copying between profiles reports success")
    CHECK(CommanderPartyFrames_GetBind("alt-2") == 2006,
        "...and brings the bindings across")
    CHECK(CommanderPartyFrames_GetBind("1") == nil,
        "...including the cells the source deliberately cleared, which must not"
        .. " reappear as defaults in the copy")

    CommanderPartyFrames_ResetProfile()
    CHECK(CommanderPartyFrames_GetBind("alt-2") == nil,
        "resetting drops the profile back to the class defaults")
    CHECK(CommanderPartyFrames_GetBind("1") ~= nil, "...defaults and all")
    CommanderPartyFramesDB.ClickProfileMode = "TALENT"
    CommanderPartyFramesDB.ClickProfileFixed = ""
    CHECK(CommanderPartyFrames_GetBind("alt-2") == 2006,
        "...and leaves every other profile alone")

    -- A profile key is unreadable on purpose (locale-proof); the settings page
    -- has to be able to turn it back into something a player recognises
    local label = CommanderPartyFrames_ProfileLabel(src)
    CHECK(type(label) == "string" and label ~= "" and label ~= src,
        "a profile key renders as a readable name", tostring(label))

    -- ---- The picker can reach the whole book -----------------------------
    -- The curated groups answer nineteen times in twenty; the book is the
    -- twentieth, and it has to be deduped by NAME because that is what the
    -- secure attribute actually stores.
    local book = CommanderPartyFrames_GetSpellBook()
    CHECK(#book > 0, "the spellbook list is populated", #book)
    local names, dupes = {}, 0
    local sorted = true
    for i, sp in ipairs(book) do
        if names[sp.name] then dupes = dupes + 1 end
        names[sp.name] = true
        if i > 1 and book[i - 1].name > sp.name then sorted = false end
    end
    CHECK(dupes == 0, "ranks collapse to one entry per spell", dupes)
    CHECK(sorted, "...and the list is alphabetical, so the buckets mean something")

    CommanderPartyFramesDB.ClickBinds = keepBinds or {}
end

local function CheckBuffGrid()
    local grid
    for _, f in ipairs(allFrames) do
        if f.buffCells and f.buffCells[1] then grid = f break end
    end
    CHECK(grid ~= nil, "the settings page built an ally-buff grid")
    if not grid then return end

    local byKey = {}
    for _, cell in ipairs(grid.buffCells) do byKey[cell.def.key] = cell end
    if CLASS == "DRUID" then
        CHECK(byKey.MOTW and byKey.THORNS and byKey.REJUV and byKey.LIFEBLOOM,
            "the druid grid carries the ally buffs AND the hots — one place for everything")
    elseif CLASS == "MAGE" then
        CHECK(byKey.AI and byKey.AMP and byKey.DAMPEN,
            "the mage grid carries every buff the class puts on somebody else")
    elseif CLASS == "PALADIN" then
        CHECK(byKey.KINGS and byKey.MIGHT and byKey.WISDOM and byKey.FREEDOM and byKey.BOP,
            "the paladin grid carries the blessings AND the Hands — one place for everything")
    else
        CHECK(byKey.FORT and byKey.SPIRIT and byKey.SHADOWPROT,
            "the priest grid carries every buff the class puts on somebody else")
    end

    local refresh = grid.buffCells[1].owner
    CHECK(refresh and refresh.Refresh ~= nil, "the grid registered a refresher")
    if refresh then refresh:Refresh() end

    -- The paladin's blessings share ONE assigned slot by default, which makes
    -- their per-buff track switches decide nothing. A switch that silently
    -- does nothing is the bug; a switch that says so and refuses the click is
    -- the fix, so that is asserted here before the generic toggle machinery
    -- below is exercised with the family expanded again.
    local keepCombine = CommanderPartyFramesDB.BlessCombine
    if CLASS == "PALADIN" and byKey.KINGS then
        CommanderPartyFramesDB.BlessCombine = true
        Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
        if refresh then refresh:Refresh() end
        CHECK(byKey.KINGS.icon.__desat == true,
            "a blessing cell is drawn inert while the family shares one slot")
        CHECK(byKey.KINGS.slash.__shown ~= true,
            "...as inert, NOT as untrained — the spellbook claim has to stay true")
        local before = CommanderPartyFramesDB.BuffTrack
            and CommanderPartyFramesDB.BuffTrack["BLESS:KINGS"]
        Press(byKey.KINGS, "LeftButton")
        local after = CommanderPartyFramesDB.BuffTrack
            and CommanderPartyFramesDB.BuffTrack["BLESS:KINGS"]
        CHECK(before == after, "...and refuses the click rather than writing a dead setting")
        -- A Hand is not a blessing and never shared that slot, so its switch
        -- has to keep working right beside them
        CHECK(byKey.FREEDOM and byKey.FREEDOM.icon.__desat ~= nil,
            "the Hands beside them are untouched by any of this")
        -- Expanded, the same cell goes live again: the toggles below are the
        -- generic grid machinery, and the paladin has to reach it too.
        CommanderPartyFramesDB.BlessCombine = false
        Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
        if refresh then refresh:Refresh() end
    end

    -- The untrained case, which is the bug that started this: Dampen Magic is
    -- deliberately absent from the mage's mock spellbook.
    if CLASS == "MAGE" and byKey.DAMPEN then
        CHECK(byKey.DAMPEN.slash.__shown == true,
            "an untrained spell is struck through in the grid")
        local before = CommanderPartyFramesDB.BuffTrack
            and CommanderPartyFramesDB.BuffTrack["INT:DAMPEN"]
        Press(byKey.DAMPEN, "LeftButton")
        local after = CommanderPartyFramesDB.BuffTrack
            and CommanderPartyFramesDB.BuffTrack["INT:DAMPEN"]
        CHECK(before == after, "...and refuses the click rather than writing a dead setting")
    end

    -- A trained one toggles, and the toggle reaches the board
    local live = byKey.MOTW or byKey.AI or byKey.KINGS or byKey.FORT
    CHECK(live ~= nil, "the grid has a trained buff to toggle")
    if live then
        CHECK(live.slash.__shown ~= true, "a trained spell is not struck through")
        local was = live.icon.__desat
        Press(live, "LeftButton")
        if refresh then refresh:Refresh() end
        CHECK(live.icon.__desat ~= was,
            "clicking the icon flips it between lit and drained")
        CHECK(CommanderPartyFramesDB.BuffTrack[live.def.dbKey] ~= nil,
            "...and writes the override behind it")
        Press(live, "LeftButton")
        if refresh then refresh:Refresh() end
        CHECK(CommanderPartyFramesDB.BuffTrack[live.def.dbKey] == nil,
            "toggling back to the default clears the override rather than storing it")
    end

    -- Right-click is the advisor switch, and only where there is a rule
    local advisable
    for _, cell in ipairs(grid.buffCells) do
        if cell.def.known and cell.def.advise and BuffTrackedForTest(cell.def) then
            advisable = cell break
        end
    end
    if advisable then
        if refresh then refresh:Refresh() end
        CHECK(advisable.pip.__shown == true,
            "a slot that is allowed to judge wears the gold pip")
        Press(advisable, "RightButton")
        if refresh then refresh:Refresh() end
        CHECK(advisable.pip.__shown == false, "right-click hushes it")
        Press(advisable, "RightButton")
        if refresh then refresh:Refresh() end
    end

    CommanderPartyFramesDB.BlessCombine = keepCombine
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    if refresh then refresh:Refresh() end
end

-- The paladin settings page's assignment grids: a cell per class, a cell per
-- known player. What matters is that a cell you have never touched still shows
-- what the board is ACTUALLY going to do — an inherited answer drawn dimmed
-- rather than an empty square — because the whole point of the grid is to be
-- able to read your comp's blessings off one screen.
local function CheckBlessAssign()
    if CLASS ~= "PALADIN" then return end
    local cells, roster = {}, {}
    for _, f in ipairs(allFrames) do
        if f.assignKey and f.field == "BlessClass" then cells[f.assignKey] = f end
        if f.field == "BlessAssign" then roster[#roster + 1] = f end
    end
    CHECK(cells.MAGE ~= nil and cells.WARRIOR ~= nil,
        "the settings page built a per-class assignment cell")
    CHECK(cells.PET ~= nil, "...including one for pets, which have no class of their own")
    CHECK(#roster > 0, "...and a per-player list beside it")
    if not cells.MAGE then return end

    local keepClass = CommanderPartyFramesDB.BlessClass
    local keepAssign = CommanderPartyFramesDB.BlessAssign
    CommanderPartyFramesDB.BlessClass = {}
    CommanderPartyFramesDB.BlessAssign = {}
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    local panel = cells.MAGE.owner
    if panel then panel:Refresh() end

    -- Untouched: the built-in answer, drawn as inherited rather than as chosen
    CHECK(cells.MAGE.showDef ~= nil,
        "an untouched class cell still shows what the board will do")
    CHECK(cells.MAGE.stored ~= true, "...marked as inherited, not as your choice")
    CHECK(cells.MAGE.border.__shown ~= true, "...so it wears no chosen-border")

    -- Wisdom is mana-only, so it must not even be offered on a warrior
    local warOpts = CommanderPartyFrames_BlessOptions("WARRIOR")
    local sawWisdom = false
    for _, d in ipairs(warOpts) do if d.key == "WISDOM" then sawWisdom = true end end
    CHECK(sawWisdom == false, "Wisdom is not offered as a warrior's blessing")
    local mageOpts = CommanderPartyFrames_BlessOptions("MAGE")
    local sawMight = false
    for _, d in ipairs(mageOpts) do if d.key == "MIGHT" then sawMight = true end end
    CHECK(sawMight == false, "...nor Might as a mage's")

    -- Choosing marks the cell as yours; clearing hands it back to the default
    CommanderPartyFrames_BlessSet("BlessClass", "MAGE", "SALVATION")
    if panel then panel:Refresh() end
    CHECK(cells.MAGE.stored == true and cells.MAGE.showDef
        and cells.MAGE.showDef.key == "SALVATION",
        "a chosen class blessing shows as chosen")
    CHECK(cells.MAGE.border.__shown == true, "...and wears the border that says so")
    CommanderPartyFrames_BlessSet("BlessClass", "MAGE", nil)
    if panel then panel:Refresh() end
    CHECK(cells.MAGE.stored ~= true, "clearing hands the cell back to the default")

    -- NONE is a real answer, not an absence: the cell has to read as
    -- "deliberately unblessed" rather than as "not loaded"
    CommanderPartyFrames_BlessSet("BlessClass", "MAGE", CommanderPartyFrames_BlessNone())
    if panel then panel:Refresh() end
    CHECK(cells.MAGE.showDef == nil and cells.MAGE.empty.__shown == true,
        "a class set to NONE draws the deliberate-blank mark")

    CommanderPartyFramesDB.BlessClass = keepClass or {}
    CommanderPartyFramesDB.BlessAssign = keepAssign or {}
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    if panel then panel:Refresh() end
end

local function CheckShadowRead()
    if CLASS ~= "PRIEST" then return end
    local keepTrack = CommanderPartyFramesDB.BuffTrack
    CommanderPartyFramesDB.BuffTrack = { ["PWS:SHADOWPROT"] = true, ["PWS:FORT"] = false,
        ["PWS:SPIRIT"] = false }
    CommanderPartyFramesDB.BuffAdvisor = true
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    local function Pump()
        now = now + 1
        for _, f in ipairs(allFrames) do
            local u = f.__scripts.OnUpdate
            PumpFrame(f, 10)
        end
    end
    local function Row()
        for _, f in ipairs(allFrames) do
            if f.buffs and f.bar and f.stripe and f.__shown then return f end
        end
    end
    playerBuffs = {}
    Fire("UNIT_AURA", "player"); Pump()
    local row = Row()
    CHECK(row ~= nil, "a row is on the priest board")
    if not row then CommanderPartyFramesDB.BuffTrack = keepTrack; return end

    local sp = row.buffs[1]
    CHECK(sp.icon.__shown == true, "Shadow Protection takes its slot once tracked")
    local quiet = sp.icon.__color or {}
    CHECK(quiet[1] and quiet[1] < 0.5,
        "...and stays neutral with no shadow damage seen", tostring(quiet[1]))

    -- A stranger lands shadow-school damage (school mask 32)
    _G.__setClog({ now, "SPELL_DAMAGE", false, "enemy-guid", "Them", 0, 0,
        "player-guid", "Tester", 0, 0, 589, "Shadow Word: Pain", 32, 300 })
    Fire("COMBAT_LOG_EVENT_UNFILTERED")
    Fire("UNIT_AURA", "player"); Pump()
    local red = sp.icon.__color or {}
    CHECK(red[1] and red[1] > 0.5 and red[2] and red[2] < 0.3,
        "shadow damage off the team turns the Shadow Protection slot red",
        tostring(red[1]) .. "," .. tostring(red[2]))

    -- Zoning is a new enemy team, so the memory does not travel
    Fire("PLAYER_ENTERING_WORLD")
    Fire("UNIT_AURA", "player"); Pump()
    local zoned = sp.icon.__color or {}
    CHECK(zoned[1] and zoned[1] < 0.5,
        "the shadow read does not survive into the next arena", tostring(zoned[1]))

    -- ...and our OWN shadow damage proves nothing about the other side
    _G.__setClog({ now, "SPELL_DAMAGE", false, "player-guid", "Tester", 0, 0,
        "enemy-guid", "Them", 0, 0, 589, "Shadow Word: Pain", 32, 300 })
    Fire("COMBAT_LOG_EVENT_UNFILTERED")
    Fire("UNIT_AURA", "player"); Pump()
    local mine = sp.icon.__color or {}
    CHECK(mine[1] and mine[1] < 0.5,
        "our own shadow damage is not evidence about the enemy", tostring(mine[1]))

    CommanderPartyFramesDB.BuffTrack = keepTrack or {}
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Pump()
end

local function CheckBuffTargets()
    local book = CommanderPartyFrames_GetBuffBook(CLASS == "MAGE" and "INT"
        or CLASS == "DRUID" and "HOT" or CLASS == "PALADIN" and "BLESS" or "PWS")
    CHECK(book ~= nil and #book > 0, "this class has ally buffs in the registry")
    if not book then return end

    local manaOnly, always
    for _, def in ipairs(book) do
        if def.targets == "MANA" and not manaOnly then manaOnly = def end
        if def.targets == "ALL" and def.default and not always then always = def end
    end

    -- Silence everything first: with the registry grown to five or six buffs
    -- a class, "whatever happens to default on" is not a countable baseline.
    -- The paladin's blessings normally collapse into ONE assigned slot, which
    -- is a different mechanism with its own block below; what is under test
    -- here is the per-buff `targets` filter, so the family is expanded for the
    -- duration and put back after.
    local keepCombine = CommanderPartyFramesDB.BlessCombine
    CommanderPartyFramesDB.BlessCombine = false
    local keepTrack = CommanderPartyFramesDB.BuffTrack
    CommanderPartyFramesDB.BuffTrack = {}
    for _, def in ipairs(book) do CommanderPartyFramesDB.BuffTrack[def.dbKey] = false end
    for _, def in ipairs({ "HOT:REJUV", "HOT:REGROWTH", "HOT:LIFEBLOOM",
                           "HAND:FREEDOM", "HAND:BOP", "HAND:SACRIFICE" }) do
        CommanderPartyFramesDB.BuffTrack[def] = false
    end
    if manaOnly then CommanderPartyFramesDB.BuffTrack[manaOnly.dbKey] = true end
    if always then CommanderPartyFramesDB.BuffTrack[always.dbKey] = true end
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)

    local basePower = UnitPowerType
    local function Pump()
        now = now + 1
        for _, f in ipairs(allFrames) do
            local u = f.__scripts.OnUpdate
            PumpFrame(f, 10)
        end
    end
    local function Row()
        for _, f in ipairs(allFrames) do
            if f.buffs and f.bar and f.stripe and f.__shown then return f end
        end
    end

    playerBuffs = {}
    Fire("UNIT_AURA", "player"); Pump()
    local row = Row()
    CHECK(row ~= nil, "a row is on the board to read the strip off")
    if row and manaOnly and always then
        -- The mock's player is a mana class, so both slots apply here
        local slots = 0
        for i = 1, 3 do if row.buffs[i].icon.__shown then slots = slots + 1 end end
        CHECK(slots == 2, "a mana user gets both the universal and the mana-only slot",
            slots)
    elseif row and always then
        CHECK(row.buffs[1].icon.__shown == true,
            "the universal buff takes its slot")
    end

    CommanderPartyFramesDB.BuffTrack = keepTrack or {}
    CommanderPartyFramesDB.BlessCombine = keepCombine
    UnitPowerType = basePower
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Pump()
end

local function CheckPets()
    local keepDisplay, keepSelf, keepAlerts, keepMax, keepPets =
        CommanderPartyFramesDB.UnitDisplay, CommanderPartyFramesDB.IncludeSelf,
        CommanderPartyFramesDB.OnlyAlerts, CommanderPartyFramesDB.MaxRows,
        CommanderPartyFramesDB.IncludePets
    local baseExists, baseGUID = UnitExists, UnitGUID
    local baseHealth, baseName = UnitHealth, UnitName
    local basePortrait = SetPortraitTexture
    -- The pet is the HURT one, so the sort tiebreak is load-bearing: without
    -- it the lower-health pet would sort above its own owner.
    -- "Equally urgent" has to actually BE true for the tiebreak to be what
    -- is under test, and the BLESS layer's READY bar sits at 50% rather than
    -- the others' 90%, so its owner has to be under that bar too.
    local petHealth = { partypet1 = 30, party1 = (CLASS == "PALADIN") and 40 or 90 }
    partyUp = { party1 = true, partypet1 = true }
    petOut = false                  -- no elemental: this is about ALLIES' pets
    function UnitExists(unit)
        if unit and unit:find("^party") then return partyUp[unit] == true end
        return baseExists(unit)
    end
    function UnitGUID(unit)
        if unit and unit:find("^party") then return unit .. "-guid" end
        -- The base mock answers only player/target; your own pet is a unit
        -- like any other here, and a row keyed by nothing is no row at all
        if unit == "pet" then return "pet-guid" end
        return baseGUID(unit)
    end
    function UnitHealth(unit) return petHealth[unit] or baseHealth(unit) end
    function UnitName(unit)
        if unit == "party1" then return "Mate" end
        if unit == "partypet1" then return "Minion" end
        if unit == "pet" then return "Mine" end
        return baseName(unit)
    end
    function SetPortraitTexture(tex, unit) tex:SetTexture("portrait:" .. tostring(unit)) end

    local function Pump()
        now = now + 1
        for _, f in ipairs(allFrames) do
            local u = f.__scripts.OnUpdate
            PumpFrame(f, 10)
        end
    end
    -- Ally rows only: the personal block (elemental / My Shields) is half-height
    local function ShownRows()
        local byName, order = {}, {}
        for _, f in ipairs(allFrames) do
            if f.bar and f.spellIcon and f.__shown and f.__h ~= 11 then
                local nm = f.name and f.name.__text or ""
                order[#order + 1] = nm
                byName[nm] = f
            end
        end
        return byName, order
    end
    -- Ability strips actually carrying icons
    local function StripCount()
        local n = 0
        for _, f in ipairs(allFrames) do
            if f.cells and f.__shown and f.cells[1] and f.cells[1].frame.__shown then n = n + 1 end
        end
        return n
    end

    CommanderPartyFramesDB.UnitDisplay = "ICON_NAME"   -- so rows are nameable
    CommanderPartyFramesDB.IncludeSelf = true
    CommanderPartyFramesDB.OnlyAlerts = false
    CommanderPartyFramesDB.MaxRows = 6
    CommanderPartyFramesDB.IncludePets = true
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Fire("GROUP_ROSTER_UPDATE"); Pump()
    local rows, order = ShownRows()
    local stripsWith, rowsWith = StripCount(), #order
    CHECK(rows["Minion"] ~= nil, "an ally's pet gets its own row")
    CHECK(rows["Mate"] ~= nil, "...alongside its owner")
    if rows["Minion"] then
        -- A pet has no class icon of its own, and its owner's alone cannot
        -- tell two warlocks' minions apart — so the one identity slot is its
        -- portrait, the same answer the elemental row already gives
        CHECK(rows["Minion"].unitIcon.__texture == "portrait:partypet1",
            "the pet's single identity slot is its portrait",
            tostring(rows["Minion"].unitIcon.__texture))
        CHECK(rows["Mate"] == nil or rows["Mate"].unitIcon.__texture ~= "portrait:party1",
            "...while a player keeps their class icon")
        CHECK(rows["Minion"].bar.__shown == true and rows["Minion"].barBG.__shown == true,
            "and it is a real row: a health bar, not a label")
    end

    local iMate, iMinion
    for i, nm in ipairs(order) do
        if nm == "Mate" then iMate = i elseif nm == "Minion" then iMinion = i end
    end
    CHECK(iMate and iMinion and iMate < iMinion,
        "an equally urgent player outranks the pet, even when the pet is the hurt one",
        tostring(iMate) .. " vs " .. tostring(iMinion))

    -- An aura landing on someone's pet has to reach the board like any ally's
    Fire("UNIT_AURA", "partypet1")
    CHECK(ShownRows()["Minion"] ~= nil, "a pet's aura event keeps its row on the board")

    CommanderPartyFramesDB.IncludePets = false
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Fire("GROUP_ROSTER_UPDATE"); Pump()
    local offRows, offOrder = ShownRows()
    CHECK(offRows["Minion"] == nil, "switching Include Pets off takes the row back off")
    CHECK(#offOrder == rowsWith - 1, "and costs the board exactly one row",
        rowsWith .. " -> " .. #offOrder)
    CHECK(StripCount() == stripsWith,
        "the pet row carried no ability strip — the book is a class's cooldowns",
        stripsWith .. " with pets vs " .. StripCount() .. " without")

    -- Your OWN pet on the mage layer stays off the ally board: the elemental
    -- already has the richer personal row down there, and two rows for one
    -- unit is noise. Every other layer treats it as the ally it is.
    CommanderPartyFramesDB.IncludePets = true
    petOut = true
    Fire("UNIT_PET", "player"); Pump()
    local own = ShownRows()
    if CLASS == "MAGE" then
        CHECK(own["Mine"] == nil,
            "your elemental stays off the ALLY board — its personal row is the better one")
    else
        CHECK(own["Mine"] ~= nil, "your own pet is an ally row like anyone else's")
    end

    petOut = false
    partyUp = {}
    UnitExists, UnitGUID = baseExists, baseGUID
    UnitHealth, UnitName, SetPortraitTexture = baseHealth, baseName, basePortrait
    CommanderPartyFramesDB.UnitDisplay, CommanderPartyFramesDB.IncludeSelf,
        CommanderPartyFramesDB.OnlyAlerts, CommanderPartyFramesDB.MaxRows,
        CommanderPartyFramesDB.IncludePets =
        keepDisplay, keepSelf, keepAlerts, keepMax, keepPets
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Fire("GROUP_ROSTER_UPDATE"); Pump()
end

-- Both sections below run on EVERY layer, which is the point: the priest
-- board never had a power strip at all, and the forecast is chassis. They
-- sit above the non-mage exit so both class paths reach them, and carry
-- their own pump because DrawOnce is defined past that exit.
local function FcPump()
    now = now + 1
    for _, f in ipairs(allFrames) do PumpFrame(f, 10) end
end

-- ===========================================================================
-- The power strip: every class, not just the mana users
-- ===========================================================================
-- The strip under the health bar used to be a MANA strip on three of the four
-- boards, which left a rogue's energy and a warrior's rage — the two
-- resources an arena actually plans around — with nowhere to be shown at all,
-- and gave the priest board no strip on anybody. It is now the unit's LIVE
-- power, on every board, which is why these read UnitPowerType rather than
-- the class: a druid that shifts has to change strip mid-fight.
local function CheckPowerStrip()
    local realType, realPower, realMax = UnitPowerType, UnitPower, UnitPowerMax
    local ptype, ptoken, pcur, pmax = 0, "MANA", 30, 100
    UnitPowerType = function() return ptype, ptoken end
    UnitPower = function() return pcur end
    UnitPowerMax = function() return pmax end

    local db = CommanderPartyFramesDB
    db.EnableShield, db.CombatOnly, db.AlwaysShow = true, false, true
    db.IncludeSelf, db.OnlyAlerts = true, false
    db.PowerBar, db.PowerBarColor, db.PowerBarHeight = "ALL", "TYPE", 6
    db.Forecast = "OFF"
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Fire("UNIT_AURA", "player"); FcPump()

    -- The player's own ally row: the one row this mock's roster produces
    local function SelfRowWidget()
        for _, f in ipairs(allFrames) do
            if f.fcHot and f.healthBar and f.__shown and f.bar and f.bar.__shown then
                return f
            end
        end
    end

    local row = SelfRowWidget()
    CHECK(row ~= nil, "the board draws a row to hang a power strip on")
    if not row then
        UnitPowerType, UnitPower, UnitPowerMax = realType, realPower, realMax
        return
    end
    local barW = row._barW or 100

    CHECK(row.healthBar.__shown == true, "a mana user takes the strip")
    CHECK(math.abs((row.healthBar.__w or 0) - barW * 0.3) < 0.51,
        "and it is as wide as the resource is full",
        tostring(row.healthBar.__w) .. " of " .. tostring(barW))
    local c = row.healthBar.__color or {}
    CHECK(c[3] and c[3] > c[1], "mana is blue", table.concat({ c[1] or 0, c[2] or 0, c[3] or 0 }, ","))

    -- The whole point of the change: rage and energy, which the mana strip
    -- could never show whatever the setting said.
    ptype, ptoken, pcur = 1, "RAGE", 45
    Fire("UNIT_AURA", "player"); FcPump()
    CHECK(row.healthBar.__shown == true, "a rage user takes the strip too")
    CHECK(math.abs((row.healthBar.__w or 0) - barW * 0.45) < 0.51,
        "at their own fill", tostring(row.healthBar.__w))
    c = row.healthBar.__color or {}
    CHECK(c[1] and c[1] > (c[3] or 0), "and rage is red, not the mana blue",
        table.concat({ c[1] or 0, c[2] or 0, c[3] or 0 }, ","))

    ptype, ptoken, pcur = 3, "ENERGY", 80
    Fire("UNIT_AURA", "player"); FcPump()
    c = row.healthBar.__color or {}
    CHECK(c[1] and c[2] and c[1] > 0.7 and c[2] > 0.7 and (c[3] or 1) < 0.5,
        "energy is yellow", table.concat({ c[1] or 0, c[2] or 0, c[3] or 0 }, ","))

    -- Classic Blue paints every resource the one blue the strip always wore
    db.PowerBarColor = "BLUE"
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Fire("UNIT_AURA", "player"); FcPump()
    c = row.healthBar.__color or {}
    CHECK(c[3] and c[3] > (c[1] or 1), "Classic Blue paints energy blue as well")
    db.PowerBarColor = "TYPE"

    -- Mana Users Only is the old board, and it has to still BE the old board
    db.PowerBar = "MANA"
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Fire("UNIT_AURA", "player"); FcPump()
    CHECK(row.healthBar.__shown == false,
        "Mana Users Only leaves an energy user with no strip")
    ptype, ptoken, pcur = 0, "MANA", 30
    Fire("UNIT_AURA", "player"); FcPump()
    CHECK(row.healthBar.__shown == true, "and still gives a caster theirs")

    db.PowerBar = "OFF"
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Fire("UNIT_AURA", "player"); FcPump()
    CHECK(row.healthBar.__shown == false, "Off takes the strip off everyone")

    -- Height is clamped to what is left of the row: an unclamped strip pushes
    -- the bars up out of their own row and into the one above it.
    db.PowerBar, db.PowerBarHeight = "ALL", 7
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Fire("UNIT_AURA", "player"); FcPump()
    local tall = row.healthBar.__h
    db.PowerBarHeight = 2
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Fire("UNIT_AURA", "player"); FcPump()
    CHECK(tall and row.healthBar.__h and tall > row.healthBar.__h,
        "the height slider actually moves the strip",
        tostring(tall) .. " vs " .. tostring(row.healthBar.__h))
    CHECK((row.__h or 22) >= (row.bar.__h or 0) + (row.healthBar.__h or 0),
        "and the row still contains its own bars")

    db.PowerBarHeight = 6
    UnitPowerType, UnitPower, UnitPowerMax = realType, realPower, realMax
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
end

-- ===========================================================================
-- Inbound-heal prediction: rank, bursts, and the caster's own spell power
-- ===========================================================================
-- The hot half of the forecast reads well because a tick is a tick. The CAST
-- half had three ways to be wrong, and all three make the prediction look
-- like a spell-power bug from the outside — the number comes out near the
-- spell's base value:
--   * downranking      every rank of a heal answers to ONE name, and TBC
--                      healers downrank constantly. Averaged together, a
--                      rank-2 filler drags the rank-7 prediction down.
--   * multi-target     Chain Heal and Prayer of Healing land several events
--                      per cast, each smaller than the last; blending all of
--                      them teaches well under what the primary receives.
--   * nothing learned  a heal nobody has watched land has no number at all,
--                      which is the whole first fight of a session.
local function CheckHealPredict()
    local db = CommanderPartyFramesDB
    db.EnableShield, db.CombatOnly, db.AlwaysShow = true, false, true
    db.IncludeSelf, db.OnlyAlerts = true, false
    db.Forecast, db.ForecastNet = "BAR", false
    db.ForecastDots, db.ForecastHots, db.ForecastCasts = true, true, true
    db.ForecastWindow, db.ForecastMinPct = 0, 0
    db.OverhealGlow = false
    playerHealth = 20           -- room on the bar for a big heal to draw in
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)

    local function Heal(spellId, name, amount)
        local e = { now, "SPELL_HEAL", false, "player-guid", "Tester", 0, 0,
                    "player-guid", "Tester", 0, 0, spellId, name, 2,
                    amount, 0, 0, false }
        __setClog(e)
        Fire("COMBAT_LOG_EVENT_UNFILTERED")
    end
    local function Row()
        for _, f in ipairs(allFrames) do
            if f.fcCast and f.bar and f.bar.__shown and f.__shown then return f end
        end
    end
    local row = Row()
    CHECK(row ~= nil, "the board draws a row for an inbound heal")
    if not row then playerHealth = 100; return end
    local barW, hpMax = row._barW or 100, 100
    -- What the drawn ghost says the heal is worth, in health points. Scans
    -- every row rather than the player's, because the client will not say who
    -- another player is casting at and the engine resolves that the way the
    -- game does — a healer with no friendly target heals themselves, so their
    -- ghost lands on THEIR row. One cast is in the air at a time here.
    local function Predicted()
        for _, f in ipairs(allFrames) do
            if f.fcCast and f.fcCast.__shown then
                return (f.fcCast.__w or 0) / (f._barW or barW) * hpMax
            end
        end
        return 0
    end

    local realCasting = UnitCastingInfo
    local casting = "Smoke Mend"
    UnitCastingInfo = function()
        return casting, nil, "Interface\\Icons\\Smoke", now * 1000, (now + 2) * 1000,
            false, nil, false, nil
    end

    -- --- Downranking -------------------------------------------------------
    -- The same NAME at two ranks. Averaged, the prediction for the big one
    -- would come out near 12; keyed by rank it is the rank that is in the air.
    Heal(9001, "Smoke Mend", 4)         -- the downranked filler, spammed
    now = now + 1; Heal(9001, "Smoke Mend", 4)
    now = now + 1; Heal(9001, "Smoke Mend", 4)
    now = now + 1; Heal(9002, "Smoke Mend", 20)  -- the real one
    now = now + 1
    Fire("UNIT_SPELLCAST_START", "player", nil, 9002)
    CHECK(math.abs(Predicted() - 20) < 0.6,
        "the rank in the air is the rank predicted, not an average of them all",
        Predicted())
    Fire("UNIT_SPELLCAST_START", "player", nil, 9001)
    CHECK(math.abs(Predicted() - 4) < 0.6,
        "...and the downranked filler predicts its own small number",
        Predicted())
    Fire("UNIT_SPELLCAST_SUCCEEDED", "player")

    -- --- Multi-target bursts -----------------------------------------------
    -- One cast, three events, descending. The primary target is what an
    -- inbound-heal forecast is about, so the largest is the measurement.
    casting = "Smoke Chain"
    Heal(9003, "Smoke Chain", 30)
    Heal(9003, "Smoke Chain", 20)       -- same breath: the second jump
    Heal(9003, "Smoke Chain", 10)       -- ...and the third
    now = now + 2                       -- the breath passes; the burst commits
    Fire("UNIT_SPELLCAST_START", "player", nil, 9003)
    CHECK(math.abs(Predicted() - 30) < 0.6,
        "a multi-target cast is measured at its primary, not averaged down",
        Predicted())
    Fire("UNIT_SPELLCAST_SUCCEEDED", "player")

    -- --- The caster's own spell power --------------------------------------
    -- For OUR heals the tooltip is authoritative: it is the spell's real
    -- value with our spell power, talents and any proc up right now, and it
    -- is right on the first cast of a session rather than after the first
    -- one lands. This is the half that was missing.
    local scanTip = _G.CommanderPartyFramesScanTip
    CHECK(scanTip ~= nil, "the engine built its scanning tooltip")
    local tipBook, tipLines = {}, {}
    if scanTip then
        for i = 1, 8 do
            local n = i
            _G["CommanderPartyFramesScanTipTextLeft" .. n] = {
                GetText = function() return tipLines[n] end,
            }
        end
        scanTip.SetSpellByID = function(_, id)
            tipLines = tipBook[id] or {}
        end
        scanTip.NumLines = function() return 8 end
    end

    -- A heal the log has only ever seen land small, whose tooltip says
    -- otherwise: the tooltip wins, because it is the one that knows our gear.
    casting = "Smoke Light"
    Heal(9004, "Smoke Light", 5)
    now = now + 2
    tipBook[9004] = { "Smoke Light", "300 Mana", "2.5 sec cast",
        "Heals a friendly target for 40 to 60." }
    Fire("UNIT_SPELLCAST_START", "player", nil, 9004)
    CHECK(math.abs(Predicted() - 50) < 0.6,
        "our own heal is predicted from the tooltip, spell power and all",
        Predicted())

    -- A hot line is not a heal range: ascending pairs only, so "1060 over 12
    -- sec" is rejected and the learned number stands.
    tipBook[9004] = { "Smoke Light", "300 Mana", "2.5 sec cast",
        "Heals the target for 30 over 12 sec." }
    Fire("UNIT_SPELLCAST_START", "player", nil, 9004)
    CHECK(math.abs(Predicted() - 5) < 0.6,
        "a hot's tooltip line is not mistaken for a heal range",
        Predicted())

    -- Regrowth's shape: a range AND a hot on one line. The range comes first
    -- and it is the half a cast forecast is about.
    tipBook[9004] = { "Smoke Light", "300 Mana", "2.5 sec cast",
        "Heals a friendly target for 40 to 60 and another 70 over 21 sec." }
    Fire("UNIT_SPELLCAST_START", "player", nil, 9004)
    CHECK(math.abs(Predicted() - 50) < 0.6,
        "...and a spell carrying both takes the range, not the hot",
        Predicted())
    Fire("UNIT_SPELLCAST_SUCCEEDED", "player")

    -- Someone else's heal has no tooltip we could read — their gear is not
    -- ours — so the learned number is all there is, and it must still work.
    -- A tooltip IS stocked for it, deliberately: reading someone else's spell
    -- off our own client would be a plausible-looking answer computed from
    -- the wrong character's gear, and it must not happen.
    tipBook[9005] = { "Smoke Word", "300 Mana", "2.5 sec cast",
        "Heals a friendly target for 900 to 900." }
    casting = "Smoke Word"
    local e = { now, "SPELL_HEAL", false, "party1-guid", "Ally", 0, 0,
                "player-guid", "Tester", 0, 0, 9005, "Smoke Word", 2, 25, 0, 0, false }
    __setClog(e); Fire("COMBAT_LOG_EVENT_UNFILTERED")
    now = now + 2
    -- Stood up locally rather than leaning on the party overrides further
    -- down the file: this block runs at two different points depending on the
    -- class, and only one of them is past them.
    local rE, rG, rIn = UnitExists, UnitGUID, IsInGroup
    -- EXACT token, not a prefix: "party1target" also starts with "party1",
    -- and answering yes to it would hand the engine a target GUID no row
    -- belongs to — the cast would be recorded and then drawn nowhere.
    UnitExists = function(u) return u == "party1" or rE(u) end
    UnitGUID = function(u) return u == "party1" and "party1-guid" or rG(u) end
    IsInGroup = function() return true end
    Fire("GROUP_ROSTER_UPDATE")
    Fire("UNIT_SPELLCAST_START", "party1", nil, 9005)
    CHECK(math.abs(Predicted() - 25) < 0.6,
        "another caster's heal is predicted from what theirs has landed for",
        Predicted())
    Fire("UNIT_SPELLCAST_SUCCEEDED", "party1")
    UnitExists, UnitGUID, IsInGroup = rE, rG, rIn
    Fire("GROUP_ROSTER_UPDATE")

    UnitCastingInfo = realCasting
    if scanTip then scanTip.SetSpellByID = function() tipLines = {} end end
    Fire("UNIT_SPELLCAST_SUCCEEDED", "player")
    db.Forecast, db.OverhealGlow = "BAR", true
    playerHealth = 100
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
end

-- ===========================================================================
-- The overheal ring
-- ===========================================================================
-- The one half of the healing accounting the combat log reports outright, so
-- unlike the forecast there is nothing to learn and nothing to guess — which
-- makes the failures here all about the GATES: whose heals count, how much
-- has to spill before it counts, and whether the ring ever lets go.
local function CheckOverheal()
    local db = CommanderPartyFramesDB
    db.EnableShield, db.CombatOnly, db.AlwaysShow = true, false, true
    db.IncludeSelf, db.OnlyAlerts = true, false
    db.Forecast = "OFF"
    db.OverhealGlow, db.OverhealMine = true, true
    db.OverhealPct, db.OverhealHold = 50, 1
    playerHealth = 80
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)

    -- amount is the heal's full size, overhealing the part of it that spilled
    local function Heal(src, amount, over, periodic)
        local e = { now, periodic and "SPELL_PERIODIC_HEAL" or "SPELL_HEAL", false,
                    src, "Healer", 0, 0, "player-guid", "Tester", 0, 0,
                    99002, "Smoke Mend", 2, amount, over, 0, false }
        __setClog(e)
        Fire("COMBAT_LOG_EVENT_UNFILTERED")
        Fire("UNIT_AURA", "player")
    end
    local function Row()
        for _, f in ipairs(allFrames) do
            if f.ohGlow and f.strip and f.__shown and f.bar and f.bar.__shown then return f end
        end
    end
    local function RingOn(row)
        for i = 1, 4 do if not row.ohGlow[i].__shown then return false end end
        return true
    end
    local function RingAlpha(row)
        local c = row.ohGlow[1].__color or {}
        return c[4] or 0
    end

    local row = Row()
    CHECK(row ~= nil, "the board draws a row to ring")
    if not row then playerHealth = 100; return end

    CHECK(RingOn(row) == false, "a quiet row wears no ring")

    -- A heal that landed everything it had is not overhealing
    Heal("player-guid", 1000, 0)
    CHECK(RingOn(row) == false, "a heal that spilled nothing raises no ring")

    -- ...and one under the threshold is still not worth saying
    Heal("player-guid", 1000, 300)
    CHECK(RingOn(row) == false, "a spill under Overheal At stays quiet")

    Heal("player-guid", 1000, 600)
    CHECK(RingOn(row) == true, "past it, all four edges light")
    local partial = RingAlpha(row)

    -- Brightness rides the SHARE wasted: a heal that did nothing at all has
    -- to read louder than one that did half its job.
    Heal("player-guid", 1000, 1000)
    CHECK(RingAlpha(row) > partial,
        "and a heal that did nothing at all rings brighter",
        RingAlpha(row) .. " vs " .. partial)

    -- Whose waste it is. Another healer's spill means the target is capped,
    -- which is worth knowing — but it is not YOUR global being thrown away.
    now = now + 3
    Fire("UNIT_AURA", "player")
    CHECK(RingOn(row) == false, "the ring lets go once the hold runs out")
    Heal("party1-guid", 1000, 1000)
    CHECK(RingOn(row) == false, "another healer's waste is not yours by default")
    db.OverhealMine = false
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Heal("party1-guid", 1000, 1000)
    CHECK(RingOn(row) == true, "...and counts once you ask for everyone's")
    db.OverhealMine = true

    -- A hot ticking into a capped ally is pure waste every tick, and each
    -- tick refreshes the hold before the last has faded: a steady ring, which
    -- is exactly the thing worth seeing.
    now = now + 3
    Fire("UNIT_AURA", "player")
    Heal("player-guid", 120, 120, true)
    local first = RingAlpha(row)
    now = now + 0.5
    Heal("player-guid", 120, 120, true)
    CHECK(RingOn(row) == true and math.abs(RingAlpha(row) - first) < 0.01,
        "a hot spilling every tick holds the ring steady",
        RingAlpha(row) .. " vs " .. first)

    -- It fades rather than blinking off, so a one-off waste reads as a pulse
    now = now + 0.6
    Fire("UNIT_AURA", "player")
    CHECK(RingOn(row) == true and RingAlpha(row) < first,
        "and a spill nobody repeats fades out instead of blinking off",
        RingAlpha(row) .. " vs " .. first)

    -- The stripe is a channel of its own: the ring must never start on top
    -- of it, or the row trades its state colour for its waste colour.
    local p = row.ohGlow[1].__points and row.ohGlow[1].__points[1]
    CHECK(p and p.x and p.x > 3,      -- the engine's STRIPE_W
        "the ring starts clear of the state stripe", p and p.x)

    db.OverhealGlow = false
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Heal("player-guid", 1000, 1000)
    CHECK(RingOn(row) == false, "and Off draws no ring at all")

    db.OverhealGlow = true
    playerHealth = 100
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
end

-- ===========================================================================
-- The forecast: pending dot damage, rolling hot healing, an inbound cast
-- ===========================================================================
-- All three are LEARNED from the combat log, because TBC exposes none of
-- them. These drive the log directly and then assert on what the bar does,
-- which is the only way to catch the two failures that matter: a forecast
-- that counts ticks that will never happen, and one that quietly counts
-- nothing at all because the learning never fired.
local function CheckForecast()
    local db = CommanderPartyFramesDB
    db.EnableShield, db.CombatOnly, db.AlwaysShow = true, false, true
    db.IncludeSelf, db.OnlyAlerts = true, false
    db.PowerBar = "ALL"
    db.Forecast, db.ForecastNet = "BAR", false
    db.ForecastDots, db.ForecastHots, db.ForecastCasts = true, true, true
    db.ForecastWindow, db.ForecastMinPct = 0, 0
    db.ForecastTooltip = true
    playerHealth = 80                       -- against the mock's max of 100
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)

    local function Clog(subevent, spell, amount, crit)
        -- CombatLogGetCurrentEventInfo's shape: eleven header fields, then
        -- spellId, spellName, school, and the payload. Damage carries the
        -- crit flag seventh into the payload; a heal, fourth.
        local e = { now, subevent, false, "player-guid", "Tester", 0, 0,
                    "player-guid", "Tester", 0, 0, 99001, spell, 32, amount }
        if subevent == "SPELL_PERIODIC_DAMAGE" then
            e[16], e[17], e[18], e[19], e[20], e[21] = 0, 32, 0, 0, 0, crit or false
        else
            e[16], e[17], e[18] = 0, 0, crit or false
        end
        __setClog(e)
        Fire("COMBAT_LOG_EVENT_UNFILTERED")
    end

    local function SelfRowWidget()
        for _, f in ipairs(allFrames) do
            if f.fcHot and f.healthBar and f.__shown and f.bar and f.bar.__shown then
                return f
            end
        end
    end

    -- A dot nobody has watched tick is worth NOTHING, not a guess: a wrong
    -- number here is worse than a missing one.
    unitDebuffs.player = { { name = "Smoke Dot", expirationTime = now + 12, duration = 12 } }
    Fire("UNIT_AURA", "player"); FcPump()
    local row = SelfRowWidget()
    CHECK(row ~= nil, "the forecast has a row to draw on")
    if not row then unitDebuffs.player = {}; playerHealth = 100; return end
    local barW = row._barW or 100
    CHECK(row.fcDot.__shown == false,
        "an unmeasured dot forecasts nothing rather than guessing")

    -- One tick on the log and the same dot is worth four of them
    Clog("SPELL_PERIODIC_DAMAGE", "Smoke Dot", 5)
    unitDebuffs.player = { { name = "Smoke Dot", expirationTime = now + 12, duration = 12 } }
    Fire("UNIT_AURA", "player"); FcPump()
    CHECK(row.fcDot.__shown == true, "one tick on the log teaches the whole dot")
    -- 12s left at a 3s tick = 4 ticks x 5 = 20 of a 100 max = a fifth of the bar
    CHECK(math.abs((row.fcDot.__w or 0) - barW * 0.2) < 0.51,
        "and it shades back exactly what is queued",
        tostring(row.fcDot.__w) .. " of " .. tostring(barW))

    -- Look Ahead is the setting that makes this usable rather than merely
    -- true: three seconds of a twelve-second dot is one tick, not four.
    db.ForecastWindow = 3
    Fire("UNIT_AURA", "player"); FcPump()
    CHECK(math.abs((row.fcDot.__w or 0) - barW * 0.05) < 0.51,
        "Look Ahead counts only the ticks inside the window",
        tostring(row.fcDot.__w))
    db.ForecastWindow = 0

    -- A hot, from the other side of the log, chaining PAST the fill
    Clog("SPELL_PERIODIC_HEAL", "Smoke Hot", 10)
    playerBuffs = { { name = "Smoke Hot", expirationTime = now + 6, duration = 6,
                      icon = "Interface\\Icons\\Smoke" } }
    Fire("UNIT_AURA", "player"); FcPump()
    CHECK(row.fcHot.__shown == true, "a hot on the log forecasts its remaining ticks")
    CHECK(math.abs((row.fcHot.__w or 0) - barW * 0.2) < 0.51,
        "two ticks of ten on a hundred-point ally is a fifth of the bar",
        tostring(row.fcHot.__w))

    -- The noise floor is a SHARE of their own health, so it has to scale with
    -- the target rather than being a flat number
    db.ForecastMinPct = 50
    Fire("UNIT_AURA", "player"); FcPump()
    CHECK(row.fcHot.__shown == false and row.fcDot.__shown == false,
        "the noise floor drops a forecast under it")
    db.ForecastMinPct = 0
    Fire("UNIT_AURA", "player"); FcPump()
    CHECK(row.fcHot.__shown == true, "and lowering it brings the forecast back")

    -- Net folds the two into whichever way the ally is actually heading
    db.ForecastNet = true
    Fire("UNIT_AURA", "player"); FcPump()
    CHECK(row.fcDot.__shown == false and row.fcHot.__shown == false,
        "equal healing and damage net to nothing at all")
    db.ForecastNet = false

    -- Re-applied rather than reused: every DrawOnce above moved the clock, and
    -- the forecast is supposed to shrink with it. The mode checks below are
    -- about SHAPE, so they get a fresh pair to measure.
    local function Reapply()
        unitDebuffs.player = { { name = "Smoke Dot", expirationTime = now + 12, duration = 12 } }
        playerBuffs = { { name = "Smoke Hot", expirationTime = now + 6, duration = 6,
                          icon = "Interface\\Icons\\Smoke" } }
        Fire("UNIT_AURA", "player")
    end

    -- Numbers, for a board that would rather read than estimate
    db.Forecast = "TEXT"
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Reapply()
    CHECK(row.fcText.__shown == true and (row.fcText.__text or ""):find("%+20"),
        "Numbers spells the healing out", tostring(row.fcText.__text))
    CHECK((row.fcText.__text or ""):find("%-20"),
        "and the damage beside it", tostring(row.fcText.__text))
    CHECK(row.fcDot.__shown == false, "and draws no overlay of its own")

    -- Ticks: the projection as hairlines, with the bar's own colors left alone
    db.Forecast = "TICK"
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Reapply()
    CHECK(row.fcTickH.__shown == true and row.fcTickD.__shown == true,
        "Ticks marks both projections")
    CHECK(row.fcHot.__shown == false and row.fcDot.__shown == false,
        "and fills neither")

    db.Forecast = "BAR"
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)

    -- An inbound cast heal. The client will not say who another player is
    -- casting AT, so the target resolves the way the game itself resolves
    -- one — no friendly target means the caster heals themselves.
    local realCasting = UnitCastingInfo
    Clog("SPELL_HEAL", "Smoke Heal", 30)
    UnitCastingInfo = function() return "Smoke Heal", nil, "Interface\\Icons\\Smoke",
        now * 1000, (now + 2) * 1000 end
    -- Cleared AND rescanned: the hot above already projects this ally to full,
    -- and a ghost may never outrun its own track — so with it still counted
    -- there is genuinely no room left to draw an inbound heal in. That is the
    -- right answer, and it is asserted here before it is cleared away.
    Fire("UNIT_SPELLCAST_START", "player"); FcPump()
    CHECK(row.fcHot.__shown == true and row.fcCast.__shown == false,
        "a bar already projected to full leaves an inbound heal nothing to fill")
    playerBuffs = {}
    unitDebuffs.player = {}
    Fire("UNIT_AURA", "player")
    Fire("UNIT_SPELLCAST_START", "player"); FcPump()
    CHECK(row.fcCast.__shown == true, "a heal in the air forecasts its size")
    -- At 80% health a thirty-point heal is mostly overheal, and a ghost may
    -- never outrun its own track: it fills the empty fifth and stops.
    CHECK(math.abs((row.fcCast.__w or 0) - barW * 0.2) < 0.51,
        "clamped to the room the bar actually has left",
        tostring(row.fcCast.__w) .. " of " .. tostring(barW))

    playerHealth = 40
    Fire("UNIT_SPELLCAST_START", "player"); FcPump()
    CHECK(math.abs((row.fcCast.__w or 0) - barW * 0.3) < 0.51,
        "and on a bar with room for it, at what that caster's heal really lands for",
        tostring(row.fcCast.__w))
    playerHealth = 80

    Fire("UNIT_SPELLCAST_SUCCEEDED", "player"); FcPump()
    CHECK(row.fcCast.__shown == false,
        "and it stops being inbound the moment the cast completes")

    -- A cast that is dropped without an event still has to expire on its own:
    -- a lost UNIT_SPELLCAST_STOP must not strand a phantom heal on the board.
    Fire("UNIT_SPELLCAST_START", "player"); FcPump()
    now = now + 5
    Fire("UNIT_AURA", "player"); FcPump()
    CHECK(row.fcCast.__shown == false, "a cast nobody closed expires by its own clock")

    UnitCastingInfo = realCasting
    db.Forecast = "OFF"
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Fire("UNIT_AURA", "player"); FcPump()
    CHECK(row.fcDot.__shown == false and row.fcHot.__shown == false
        and row.fcText.__shown == false, "Off draws none of it")

    unitDebuffs.player = {}
    playerBuffs = {}
    playerHealth = 100
    db.Forecast = "BAR"
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
end
-- ===========================================================================
-- Nearby Raid
--
-- The feature's whole claim is that a forty-person roster can be reduced to
-- the handful of allies standing next to you. So this exercises the two halves
-- separately: who gets picked (distance, the count, offline members, the
-- fallback when the client will not report positions) and when the pick is
-- allowed to move (never on its own, on the timer once auto is on, on demand
-- from the button — every one of those SORTING, which is the bug this section
-- grew a case for: an auto-refresh that only swapped membership left a board
-- that looked frozen while all four allies on it were moving).
-- ===========================================================================
function CheckNearby()
    local realExists, realGUID, realName = UnitExists, UnitGUID, UnitName
    local realRaid, realConn = IsInRaid, UnitIsConnected
    local raidUp, raidYards, offline = {}, {}, {}
    for i = 1, 12 do raidUp["raid" .. i] = true end
    -- Straight line east, so the distance IS the x coordinate
    local D = { 50, 10, 30, 5, 20, 40, 15, 25, 60, 70, 80, 90 }
    for i = 1, 12 do raidYards["raid" .. i] = D[i] end

    function UnitExists(unit)
        if unit and unit:find("^raid") then return raidUp[unit] == true end
        return realExists(unit)
    end
    function UnitGUID(unit)
        if unit and unit:find("^raid") then return unit .. "-guid" end
        return realGUID(unit)
    end
    function UnitName(unit)
        if unit and unit:find("^raid") then return unit end
        return realName(unit)
    end
    function UnitIsConnected(unit) return not offline[unit] end
    function IsInRaid() return true end
    function UnitPosition(unit)
        if unit == "player" then return 0, 0, 0, 1 end
        local d = raidYards[unit]
        if not d then return nil end
        return 0, d, 0, 1
    end

    -- DrawOnce is declared further down the file than the non-MAGE runs get
    -- to, so this pumps the frames itself. Same two lines, same reason: the
    -- clock has to advance or the throttled re-scans never fire twice.
    local function DrawOnce()
        now = now + 1
        for _, f in ipairs(allFrames) do PumpFrame(f, 10) end
    end

    local function Pick()
        local out = CommanderPartyFrames_NearPick({})
        return table.concat(out, " ")
    end
    local function ShownRows()
        local n = 0
        for _, f in ipairs(allFrames) do
            if f.strip and f.dispels and f.swipe and f.__shown and not f.personal then
                n = n + 1
            end
        end
        return n
    end

    -- --- Off is off ------------------------------------------------------
    CommanderPartyFramesDB.NearMode = false
    Fire("GROUP_ROSTER_UPDATE"); DrawOnce()
    CHECK(select(3, CommanderPartyFrames_NearPick({})) == false,
        "the flag off leaves the feature inert even inside a raid")
    CHECK(CommanderPartyFramesDB.Scope == "PARTY",
        "and it does not reach over and rewrite Watch")

    -- --- The pick ---------------------------------------------------------
    CommanderPartyFramesDB.NearMode = true
    CommanderPartyFramesDB.NearCount = 5
    CommanderPartyFramesDB.IncludeSelf = true
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    DrawOnce()
    CHECK(Pick() == "raid4 raid2 raid7 raid5",
        "five people means you plus the four closest, nearest first", Pick())
    CHECK(select(2, CommanderPartyFrames_NearPick({})) == true,
        "and the distances behind them are real yards, not bands")
    CHECK(ShownRows() == 5, "the board draws exactly those five rows", ShownRows())
    CHECK(CommanderPartyFramesDB.Scope == "PARTY",
        "with Watch still on Party — nearby mode does not need it switched over")

    -- --- Ten people, past what Max Rows would ever allow -------------------
    CommanderPartyFramesDB.NearCount = 10
    CommanderPartyFramesDB.MaxRows = 6
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    DrawOnce()
    CHECK(ShownRows() == 10,
        "ten people fit, because the count bounds the board and Max Rows does not clip it",
        ShownRows())
    -- Fifteen asks for more than this 12-ally raid holds, so the whole raid
    -- plus you is the board: nothing clips it at the old ten
    CommanderPartyFramesDB.NearCount = 15
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    DrawOnce()
    CHECK(ShownRows() == 13,
        "fifteen is allowed: every one of twelve allies plus you, past the old cap of ten",
        ShownRows())
    CommanderPartyFramesDB.NearCount = 5
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    DrawOnce()
    CommanderPartyFrames_NearRefresh(false)
    CHECK(Pick() == "raid4 raid2 raid7 raid5", "and coming back down re-picks the four", Pick())

    -- --- Nothing moves on its own -----------------------------------------
    CommanderPartyFramesDB.NearAuto = false
    raidYards.raid1 = 1
    DrawOnce(); DrawOnce()
    CHECK(Pick() == "raid4 raid2 raid7 raid5",
        "an ally running up beside you does NOT rearrange the board by itself", Pick())

    -- --- The button re-picks and sorts ------------------------------------
    CommanderPartyFrames_NearRefresh(false)
    CHECK(Pick() == "raid1 raid4 raid2 raid7",
        "pressing refresh takes the new collection, sorted by distance", Pick())

    -- --- Auto refresh RE-SORTS --------------------------------------------
    -- The regression this exists for: auto used to hold everyone on the row
    -- they already had, so the four closest allies could all move and the
    -- board would not visibly change. Membership rarely turns over; order
    -- does, constantly, and order is what you can see.
    CommanderPartyFramesDB.NearAuto = true
    CommanderPartyFramesDB.NearInterval = 3
    raidYards.raid4 = 18      -- still in the set, now the FURTHEST of the four
    DrawOnce()
    CHECK(Pick() == "raid1 raid2 raid7 raid4",
        "the same four in a new order re-sort on the timer, with nobody swapped",
        Pick())
    raidYards.raid7 = 60      -- out
    raidYards.raid3 = 12      -- in
    DrawOnce()
    CHECK(Pick() == "raid1 raid2 raid3 raid4",
        "and a member leaving is replaced in distance order, not in their old slot",
        Pick())

    -- --- Hysteresis, and only on membership --------------------------------
    -- Two allies drifting either side of the cutoff must not trade the last
    -- place every tick. A newcomer has to be meaningfully closer, not equal —
    -- but this must never reach the ORDER, which is what the case above
    -- already proves stays live.
    raidYards.raid5 = 15      -- inside raid4's 18, but not by the 5y margin
    DrawOnce()
    CHECK(Pick():find("raid4", 1, true) ~= nil and Pick():find("raid5", 1, true) == nil,
        "a marginally closer outsider does not evict an incumbent on the timer", Pick())
    raidYards.raid5 = 2
    DrawOnce()
    CHECK(Pick():find("raid5", 1, true) ~= nil,
        "but a decisively closer one does", Pick())
    -- Asked by hand, there is no credit at all: pure distance
    raidYards.raid5 = 15
    raidYards.raid4 = 18
    CommanderPartyFrames_NearRefresh(false)
    CHECK(Pick():find("raid5", 1, true) ~= nil,
        "and pressing the button gives no head start — a fresh collection is fresh",
        Pick())

    -- --- Offline allies are not candidates --------------------------------
    CommanderPartyFrames_NearRefresh(false)
    local was = Pick()
    offline.raid1 = true
    CommanderPartyFrames_NearRefresh(false)
    CHECK(Pick():find("raid1", 1, true) == nil,
        "a disconnected ally does not take a slot from someone you can act on",
        was .. " -> " .. Pick())
    offline.raid1 = nil

    -- --- No positions: the one remaining rung ------------------------------
    --
    -- This block used to mock CheckInteractDistance and prove a three-rung
    -- ladder. That function is PROTECTED on this client: every call from addon
    -- code is blocked and returns nothing, so the ladder never ranked anybody
    -- in game -- it fell straight through to UnitInRange while raising
    -- ADDON_ACTION_BLOCKED out of the picker's refresh. Mocking it here was
    -- proving a path the client will not run, which is why the harness stayed
    -- green through eighteen live errors a session.
    --
    -- What is left is one rung: in UnitInRange, or not. So the thing worth
    -- asserting changes shape. It is no longer "the closest rung sorts above
    -- the rest" -- there is no closest rung -- it is that everyone reachable
    -- ties, the unreachable are excluded, and the tie still breaks the same
    -- way every pick so the board does not reshuffle under the cursor.
    local realPos, realRange = UnitPosition, UnitInRange
    UnitPosition = nil
    function UnitInRange(unit)
        local d = raidYards[unit]
        if not d then return false, true end
        return d <= 40, true
    end
    CommanderPartyFrames_NearRefresh(false)
    CHECK(select(2, CommanderPartyFrames_NearPick({})) == false,
        "with no positions to read, the pick reports itself as banded, not measured")
    CHECK(#CommanderPartyFrames_NearPick({}) == 4,
        "and still fills the board", #CommanderPartyFrames_NearPick({}))
    local banded = Pick()
    CHECK(banded:find("raid7", 1, true) == nil and banded:find("raid9", 1, true) == nil,
        "nothing out of range takes a slot", banded)
    CommanderPartyFrames_NearRefresh(false)
    CHECK(Pick() == banded, "a banded pick is repeatable, not a coin toss", Pick())
    UnitPosition, UnitInRange = realPos, realRange

    -- --- The header control -----------------------------------------------
    local btn
    for _, f in ipairs(allFrames) do if f.glyph then btn = f end end
    CHECK(btn ~= nil, "the refresh control exists on the header")
    DrawOnce()
    CHECK(btn and btn.__shown == true, "and shows while nearby mode is live")
    -- Right-click is the auto toggle, and the tint is how the board reports it
    local autoWas = CommanderPartyFramesDB.NearAuto
    btn.__scripts.OnClick(btn, "RightButton")
    CHECK(CommanderPartyFramesDB.NearAuto ~= autoWas,
        "right-clicking it toggles auto-refresh")
    local lit = btn.glyph[1].__color
    btn.__scripts.OnClick(btn, "RightButton")
    CHECK(CommanderPartyFramesDB.NearAuto == autoWas, "and toggles it back")
    CHECK(lit and btn.glyph[1].__color and
        (lit[1] ~= btn.glyph[1].__color[1] or lit[2] ~= btn.glyph[1].__color[2]),
        "with the tint saying which state it is in")
    -- Left-click is the refresh itself
    raidYards.raid12 = 1
    btn.__scripts.OnClick(btn, "LeftButton")
    CHECK(Pick():find("raid12", 1, true) ~= nil,
        "left-clicking it takes a fresh pick", Pick())
    raidYards.raid12 = 90

    -- Out of a raid it is chrome with nothing to do, so it goes away
    function IsInRaid() return false end
    DrawOnce()
    CHECK(btn and btn.__shown == false, "and it goes away when there is no raid to pick from")
    CHECK(select(3, CommanderPartyFrames_NearPick({})) == false,
        "the feature switching itself off outside a raid, flag or no flag")
    function IsInRaid() return true end

    -- --- Row order is a choice --------------------------------------------
    CommanderPartyFramesDB.NearSort = "URGENCY"
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    DrawOnce()
    CHECK(#caughtErrors == 0, "the urgency order draws without erroring", caughtErrors[1])

    -- --- Class, then distance ---------------------------------------------
    -- The third order reads the pick as a class list in the suite's canon
    -- order, each class's members closest-first. The pick is still the four
    -- closest (raid4 5y, raid2 10y, raid7 15y, raid5 20y); the class list
    -- then puts the warrior first, the priest next, and the mages together
    -- with the nearer one leading. You are a mage on this run at zero yards,
    -- so you head the mage group rather than the board.
    local function RowNames()
        local out = {}
        for _, f in ipairs(allFrames) do
            if f.strip and f.dispels and f.swipe and f.__shown and not f.personal then
                out[#out + 1] = tostring(f.name and f.name.__text or "?")
            end
        end
        return table.concat(out, " ")
    end
    local realClass = UnitClass
    local displayWas = CommanderPartyFramesDB.UnitDisplay
    CommanderPartyFramesDB.UnitDisplay = "ICON_NAME"   -- so rows are nameable
    local raidClass = { raid4 = "MAGE", raid2 = "PRIEST", raid7 = "MAGE", raid5 = "WARRIOR" }
    function UnitClass(unit)
        local c = raidClass[unit]
        if c then return c, c end
        return realClass(unit)
    end
    playerClass = "MAGE"
    -- The sections above walked people around; put the line back and take a
    -- fresh pick so the four closest are the four this block reasons about
    for i = 1, 12 do raidYards["raid" .. i] = D[i] end
    CommanderPartyFramesDB.NearCount = 5
    CommanderPartyFramesDB.NearSort = "CLASS"
    CommanderPartyFramesDB.SelfFirst = false
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    CommanderPartyFrames_NearRefresh(false)
    DrawOnce(); DrawOnce()
    CHECK(Pick() == "raid4 raid2 raid7 raid5", "the pick under test is the four closest", Pick())
    CHECK(RowNames() == "raid5 raid2 Tester raid4 raid7",
        "class order groups the pick by class, each class closest-first", RowNames())
    CHECK(#caughtErrors == 0, "and draws without erroring", caughtErrors[1])
    -- Distance is live, not the snapshot: the far mage walking in swaps the
    -- two mages without a re-pick
    raidYards.raid7 = 2
    DrawOnce()
    CHECK(RowNames() == "raid5 raid2 Tester raid7 raid4",
        "the sub-sort follows people as they move", RowNames())
    raidYards.raid7 = 15
    -- Self First still lifts your row out of its class group
    CommanderPartyFramesDB.SelfFirst = true
    DrawOnce()
    CHECK(RowNames() == "Tester raid5 raid2 raid4 raid7",
        "Self First still pins you above the class list", RowNames())
    CommanderPartyFramesDB.SelfFirst = false
    -- No positions to read: everyone in range ties, and the tie is the name,
    -- so the board does not reshuffle under the cursor
    local posWas = UnitPosition
    UnitPosition = nil
    DrawOnce()
    local banded = RowNames()
    DrawOnce()
    CHECK(banded == RowNames() and banded:find("^raid5 raid2 Tester"),
        "without positions the class groups hold and the tie is stable", banded)
    UnitPosition = posWas
    UnitClass = realClass
    playerClass = CLASS
    CommanderPartyFramesDB.NearSort = "DISTANCE"

    -- The same order on the party board, where it is Sort Rows rather than
    -- the pick's Row Order: a five-man with a pet, grouped by class with
    -- the pet under its owner's class after the players, then urgency back
    -- as the default the moment the setting is cleared
    CommanderPartyFramesDB.NearMode = false
    function IsInRaid() return false end
    local partyClass = { party1 = "PRIEST", party2 = "WARRIOR", party3 = "PRIEST", party4 = "HUNTER" }
    local partyYards = { party1 = 30, party2 = 8, party3 = 12, party4 = 25, partypet4 = 3, player = 0 }
    function UnitExists(unit)
        if partyClass[unit] or unit == "partypet4" then return true end
        if unit and unit:find("^raid") then return false end
        return realExists(unit)
    end
    function UnitGUID(unit)
        if partyClass[unit] or unit == "partypet4" then return unit .. "-guid" end
        return realGUID(unit)
    end
    function UnitName(unit)
        if partyClass[unit] or unit == "partypet4" then return unit end
        return realName(unit)
    end
    function UnitClass(unit)
        local c = partyClass[unit]
        if c then return c, c end
        return realClass(unit)
    end
    function UnitPosition(unit)
        local d = partyYards[unit]
        if not d then return nil end
        return 0, d, 0, 1
    end
    playerClass = "MAGE"
    CommanderPartyFramesDB.IncludePets = true
    CommanderPartyFramesDB.RowOrder = "CLASS"
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Fire("GROUP_ROSTER_UPDATE"); DrawOnce(); DrawOnce()
    CHECK(RowNames() == "party2 party4 partyp party3 party1 Tester",
        "Sort Rows groups the party by class, closest-first, the pet under its owner's class",
        RowNames())
    CommanderPartyFramesDB.RowOrder = "URGENCY"
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    DrawOnce()
    CHECK(RowNames() ~= "party2 party4 partyp party3 party1 Tester",
        "and Urgency hands the board back to its own sort", RowNames())
    CHECK(#caughtErrors == 0, "the party board's class order draws without erroring", caughtErrors[1])
    UnitClass = realClass
    playerClass = CLASS
    CommanderPartyFramesDB.UnitDisplay = displayWas
    function IsInRaid() return true end

    -- --- Put the world back -----------------------------------------------
    CommanderPartyFramesDB.NearMode = false
    CommanderPartyFramesDB.NearAuto = false
    CommanderPartyFramesDB.NearCount = 5
    CommanderPartyFramesDB.MaxRows = 6
    UnitExists, UnitGUID, UnitName = realExists, realGUID, realName
    IsInRaid, UnitIsConnected = realRaid, realConn
    UnitPosition = nil
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Fire("GROUP_ROSTER_UPDATE"); DrawOnce()
end

-- ===========================================================================
-- Combat marks
-- ===========================================================================
-- The crossed blades at a row's right edge, and the rule they live by: they
-- are a POSITIVE claim only. An ally the client is not tracking reports no
-- combat at all, so a lit mark has to mean "this one is fighting" and a dark
-- slot has to mean "nothing seen" — never "safe to sap this one".
--
-- The rest is what the mark is FOR. You read it to find combat you can take
-- off someone (one heal on an ally already fighting puts you in combat too,
-- and a Sap does not open on a target in combat), so a fighter you cannot
-- reach is dimmed: the mark is still true, but it is not one you can act on.
local SDATA_COMBAT_TEXTURE = "Interface\\CharacterFrame\\UI-StateIcon"
local function CheckCombatMarks()
    local baseExists, baseGUID, baseRange = UnitExists, UnitGUID, UnitInRange
    local baseCombat = UnitAffectingCombat
    local keepSelf = CommanderPartyFramesDB.IncludeSelf
    local keepFade = CommanderPartyFramesDB.RangeFade
    -- These are the SIDE BY SIDE layout's width rules (one seat per mark);
    -- the stacked seat has its own section below
    local keepLayout = CommanderPartyFramesDB.MarkLayout
    CommanderPartyFramesDB.MarkLayout = "ROW"
    local function Pump()
        now = now + 1
        for _, f in ipairs(allFrames) do PumpFrame(f, 10) end
    end
    -- One ally and no self row, so there is no guessing which pooled row the
    -- sort handed out second
    CommanderPartyFramesDB.IncludeSelf = false
    partyUp = { party1 = true }
    function UnitExists(unit)
        if unit and unit:find("^party") then return partyUp[unit] == true end
        return baseExists(unit)
    end
    function UnitGUID(unit)
        if unit and unit:find("^party") then return unit .. "-guid" end
        return baseGUID(unit)
    end
    local fighting, faraway = {}, {}
    function UnitAffectingCombat(unit) return fighting[unit] == true end
    function UnitInRange(unit) return not faraway[unit], true end
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Fire("GROUP_ROSTER_UPDATE"); Pump()

    local function AllyRow()
        for _, f in ipairs(allFrames) do
            if f.combatMark and f.buffs and f.bar and f.stripe and f.__shown and f.__h ~= 11 then
                return f
            end
        end
    end
    local function Blades()
        local row = AllyRow()
        local q = row and row.combatMark
        if not q then return nil end
        return q.__shown, (q.__color or {})[4]
    end

    CHECK(AllyRow() ~= nil, "an ally row is on the board to mark")
    if not AllyRow() then return end
    CHECK(Blades() == false, "a quiet board wears no blades")
    -- The art is the CLIENT'S combat icon, not one of ours: the glyph the
    -- stock player portrait lights on every pull, so nobody has to learn it
    CHECK(AllyRow().combatMark.__texture == SDATA_COMBAT_TEXTURE,
        "the mark wears the client's own combat swords",
        AllyRow().combatMark.__texture)

    fighting.party1 = true
    Pump()
    local lit, alpha = Blades()
    CHECK(lit == true, "an ally in combat wears them")
    CHECK(alpha == 1, "...solid, because that is combat you can reach and take", alpha)

    -- Fighting somewhere you cannot cast: still true, still drawn, but not an
    -- answer you can act on
    faraway.party1 = true
    Pump()
    local litFar, alphaFar = Blades()
    CHECK(litFar == true, "out of range and fighting is still fighting")
    CHECK(alphaFar == 0.4, "...but the mark dims to say you cannot reach it", alphaFar)

    -- Range Fade takes the whole ROW to 0.4 on the same forty-yard answer.
    -- Dimming again on top of that is 0.16 alpha: a mark nobody can see.
    CommanderPartyFramesDB.RangeFade = true
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Pump()
    local _, alphaFade = Blades()
    CHECK(alphaFade == 1, "with Range Fade carrying the news, they are not dimmed twice",
        alphaFade)
    local function near(a, b) return a and math.abs(a - b) < 1e-6 end
    CHECK(near(AllyRow().__alpha, 0.4), "the default strength leaves the faded row at 0.4",
        AllyRow().__alpha)
    local keepStrength = CommanderPartyFramesDB.RangeFadeStrength
    CommanderPartyFramesDB.RangeFadeStrength = 0.8
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Pump()
    CHECK(near(AllyRow().__alpha, 0.2), "Range Fade Strength 80% takes the row to 0.2",
        AllyRow().__alpha)
    CommanderPartyFramesDB.RangeFadeStrength = keepStrength
    CommanderPartyFramesDB.RangeFade = keepFade
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    faraway.party1 = nil
    Pump()

    fighting.party1 = nil
    Pump()
    CHECK(Blades() == false, "combat drops and the blades go with it")

    -- The slot is reserved from the SETTING, not from what is up: the health
    -- bar may not grow and shrink under the player every time a pull starts.
    fighting.party1 = true
    Pump()
    local withMark = AllyRow()._barW
    CommanderPartyFramesDB.ShowCombat = false
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Pump()
    CHECK(Blades() == false, "switched off, an ally in combat is unmarked")
    CHECK(AllyRow()._barW > withMark, "...and the health bar gets the reserved width back",
        tostring(withMark) .. " -> " .. tostring(AllyRow()._barW))

    CommanderPartyFramesDB.ShowCombat = true
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Pump()
    CHECK(AllyRow()._barW == withMark, "and switching it back on costs that width again")

    CommanderPartyFramesDB.MarkLayout = keepLayout
    CommanderPartyFramesDB.IncludeSelf = keepSelf
    UnitExists, UnitGUID, UnitInRange = baseExists, baseGUID, baseRange
    UnitAffectingCombat = baseCombat
    partyUp = {}
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Fire("GROUP_ROSTER_UPDATE"); Pump()
end

-- ===========================================================================
-- Battleground marks: the flag and the ground powerups, beside the blades
-- ===========================================================================
-- Three things separate these from every other mark on the row and each of
-- them is a way to get this wrong: the slots are reserved from the ZONE
-- rather than from the setting, the flag outranks a powerup for the one slot
-- that can only hold one of them, and the flag has no expiry — so the ONLY
-- thing that takes it off a row is a scan that could actually see the unit.
local function CheckBGMarks()
    local baseExists, baseGUID, baseRange = UnitExists, UnitGUID, UnitInRange
    local baseVisible = UnitIsVisible
    local keepSelf = CommanderPartyFramesDB.IncludeSelf
    local keepZone = instanceKind
    local keepLayout = CommanderPartyFramesDB.MarkLayout
    CommanderPartyFramesDB.MarkLayout = "ROW"
    local function Pump()
        now = now + 1
        for _, f in ipairs(allFrames) do PumpFrame(f, 10) end
    end
    CommanderPartyFramesDB.IncludeSelf = false
    partyUp = { party1 = true }
    function UnitExists(unit)
        if unit and unit:find("^party") then return partyUp[unit] == true end
        return baseExists(unit)
    end
    function UnitGUID(unit)
        if unit and unit:find("^party") then return unit .. "-guid" end
        return baseGUID(unit)
    end
    local faraway, unseen = {}, {}
    function UnitInRange(unit) return not faraway[unit], true end
    function UnitIsVisible(unit) return not unseen[unit] end

    local FLAG = { name = "Warsong Flag", icon = "flag-art" }
    local ZERK = { name = "Berserking", icon = "zerk-art",
                   expirationTime = 0, duration = 10 }
    local SPEED = { name = "Speed", icon = "speed-art",
                    expirationTime = 0, duration = 10 }
    local function Wear(...)
        local list = {}
        for i = 1, select("#", ...) do
            local a = select(i, ...)
            -- Fresh copies each time: the durations are relative to `now`,
            -- which every Pump moves
            local c = { name = a.name, icon = a.icon, duration = a.duration }
            if a.duration then c.expirationTime = now + a.duration end
            list[#list + 1] = c
        end
        __setUnitBuffs("party1", list)
    end
    Wear()

    local function AllyRow()
        for _, f in ipairs(allFrames) do
            if f.bgMarks and f.buffs and f.bar and f.stripe and f.__shown and f.__h ~= 11 then
                return f
            end
        end
    end
    -- What the row is actually WEARING: the textures in order, shown only
    local function Marks()
        local row, out = AllyRow(), {}
        if not row then return out end
        for i = 1, #row.bgMarks do
            local t = row.bgMarks[i]
            if t.__shown then out[#out + 1] = t.__texture end
        end
        return out
    end
    local function Alpha(i)
        local row = AllyRow()
        local t = row and row.bgMarks[i]
        return t and (t.__color or {})[4]
    end

    instanceKind = "pvp"
    Fire("PLAYER_ENTERING_WORLD")
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Fire("GROUP_ROSTER_UPDATE"); Pump()

    CHECK(AllyRow() ~= nil, "an ally row is on the battleground board")
    if not AllyRow() then return end
    CHECK(#Marks() == 0, "an ally carrying nothing wears no marks")

    -- The flag. One mark, and the art is the client's own banner icon rather
    -- than anything this addon drew
    Wear(FLAG)
    Fire("UNIT_AURA", "party1"); Pump()
    local m = Marks()
    CHECK(#m == 1, "the flag carrier wears exactly one mark", #m)
    CHECK(m[1] == "flag-art", "...and it is the flag's own art", m[1])
    CHECK(Alpha(1) == 1, "...at full strength, because they are in range", Alpha(1))

    -- Flag AND a powerup: both slots, flag first. This is the whole reason
    -- the entries carry a priority — a carrier with Berserking up is still,
    -- first, the carrier, whatever order the aura list happened to be in.
    __setUnitBuffs("party1", nil)
    local list = {
        { name = "Berserking", icon = "zerk-art", duration = 10, expirationTime = now + 10 },
        { name = "Warsong Flag", icon = "flag-art" },
    }
    __setUnitBuffs("party1", list)
    Fire("UNIT_AURA", "party1"); Pump()
    m = Marks()
    CHECK(#m == 2, "flag plus a powerup fills both slots", #m)
    CHECK(m[1] == "flag-art", "...the flag first, whatever order the auras came in", m[1])
    CHECK(m[2] == "zerk-art", "...and the powerup second", m[2])

    -- Three at once is one more than there are slots, and the one that loses
    -- is the least useful of them
    __setUnitBuffs("party1", {
        { name = "Speed", icon = "speed-art", duration = 10, expirationTime = now + 10 },
        { name = "Warsong Flag", icon = "flag-art" },
        { name = "Berserking", icon = "zerk-art", duration = 10, expirationTime = now + 10 },
    })
    Fire("UNIT_AURA", "party1"); Pump()
    m = Marks()
    CHECK(#m == 2, "a third mark does not grow the row", #m)
    CHECK(m[1] == "flag-art" and m[2] == "zerk-art",
        "...and Speed is the one that loses its slot to Berserking",
        (m[1] or "-") .. "," .. (m[2] or "-"))

    -- Out of casting range: still carrying, still drawn, dimmed — the same
    -- rule the blades follow, and for the same reason
    Wear(FLAG)
    Fire("UNIT_AURA", "party1"); Pump()
    faraway.party1 = true
    Pump()
    CHECK(#Marks() == 1, "out of range they are still carrying")
    CHECK(Alpha(1) == 0.4, "...and the mark dims to say you cannot reach it", Alpha(1))
    faraway.party1 = nil
    Pump()

    -- The load-bearing one. A carrier who runs out of sight reports NO auras
    -- at all, and reading that as "they dropped it" would blank the flag
    -- every time they crossed the map — which is exactly when it matters.
    unseen.party1 = true
    __setUnitBuffs("party1", {})
    Fire("UNIT_AURA", "party1"); Pump()
    CHECK(#Marks() == 1, "a carrier the client cannot see keeps the flag", #Marks())
    -- ...and a scan that CAN see them is the whole truth
    unseen.party1 = nil
    Fire("UNIT_AURA", "party1"); Pump()
    CHECK(#Marks() == 0, "a scan that can see them and finds nothing takes it off",
        #Marks())

    -- A powerup carries its own clock, so out of sight it still runs out.
    -- (The flag has no expiry, which is what the check above rests on.)
    Wear(ZERK)
    Fire("UNIT_AURA", "party1"); Pump()
    CHECK(#Marks() == 1, "the powerup is on")
    unseen.party1 = true
    __setUnitBuffs("party1", {})
    -- Pumped rather than jumped: the clock this whole file shares is also
    -- Nearby Raid's re-pick timer, and a twelve-second leap out of one
    -- section lands in the next one's ranking.
    for _ = 1, 12 do Pump() end
    CHECK(#Marks() == 0, "and it expires on its own clock even unseen", #Marks())
    unseen.party1 = nil

    -- The slots are reserved from the ZONE. This is the one place these marks
    -- differ from every other slot on the row, and the reason is width: an
    -- arena row must not carry a 32-pixel hole for a mark that cannot light.
    Wear(FLAG)
    Fire("UNIT_AURA", "party1"); Pump()
    local inBG = AllyRow()._barW
    CHECK(#Marks() == 1, "carrying, in a battleground")
    instanceKind = "arena"
    Fire("PLAYER_ENTERING_WORLD"); Pump()
    local inArena = AllyRow()._barW
    CHECK(#Marks() == 0, "an arena draws none of them", #Marks())
    CHECK(inArena > inBG, "...and the health bar gets that width back",
        tostring(inBG) .. " -> " .. tostring(inArena))

    -- ...and the setting still switches them off inside one
    instanceKind = "pvp"
    Fire("PLAYER_ENTERING_WORLD")
    Wear(FLAG)
    Fire("UNIT_AURA", "party1"); Pump()
    CHECK(#Marks() == 1, "back in a battleground, carrying again")
    CommanderPartyFramesDB.ShowBGBuffs = false
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Fire("UNIT_AURA", "party1"); Pump()
    CHECK(#Marks() == 0, "switched off, a flag carrier is unmarked", #Marks())
    CHECK(AllyRow()._barW == inArena,
        "...and the bar is exactly as wide as it is outside a battleground",
        tostring(AllyRow()._barW) .. " vs " .. tostring(inArena))
    CommanderPartyFramesDB.ShowBGBuffs = true
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Fire("UNIT_AURA", "party1"); Pump()
    CHECK(#Marks() == 1, "and switching it back on restores the mark")

    -- Leaving the battleground ends the carry. Nothing else can: the flag has
    -- no expiry, and the ally who had it is no longer scannable.
    instanceKind = "none"
    Fire("PLAYER_ENTERING_WORLD"); Pump()
    instanceKind = "pvp"
    __setUnitBuffs("party1", {})
    Fire("PLAYER_ENTERING_WORLD"); Pump()
    CHECK(#Marks() == 0, "zoning out drops what the last battleground was carrying",
        #Marks())

    __setUnitBuffs("party1", nil)
    instanceKind = keepZone
    CommanderPartyFramesDB.MarkLayout = keepLayout
    CommanderPartyFramesDB.IncludeSelf = keepSelf
    UnitExists, UnitGUID, UnitInRange = baseExists, baseGUID, baseRange
    UnitIsVisible = baseVisible
    partyUp = {}
    Fire("PLAYER_ENTERING_WORLD")
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Fire("GROUP_ROSTER_UPDATE"); Pump()
end

-- ===========================================================================
-- The stacked mark seat (Mark Layout = GRID, the default): every mark in one
-- two-by-two block with a FIXED cell per meaning, so four at once still read
-- ===========================================================================
local function CheckMarkGrid()
    local baseExists, baseGUID, baseRange = UnitExists, UnitGUID, UnitInRange
    local baseCombat, baseVisible = UnitAffectingCombat, UnitIsVisible
    local keepSelf, keepZone = CommanderPartyFramesDB.IncludeSelf, instanceKind
    local keepLayout = CommanderPartyFramesDB.MarkLayout
    local function Pump()
        now = now + 1
        for _, f in ipairs(allFrames) do PumpFrame(f, 10) end
    end
    CommanderPartyFramesDB.IncludeSelf = false
    CommanderPartyFramesDB.MarkLayout = "GRID"
    CommanderPartyFramesDB.ShowTargetMarks = true
    CommanderPartyFramesDB.ShowCombat = true
    CommanderPartyFramesDB.ShowBGBuffs = true
    partyUp = { party1 = true }
    function UnitExists(unit)
        if unit and unit:find("^party") then return partyUp[unit] == true end
        return baseExists(unit)
    end
    function UnitGUID(unit)
        if unit and unit:find("^party") then return unit .. "-guid" end
        return baseGUID(unit)
    end
    local fighting = {}
    function UnitInRange() return true, true end
    function UnitIsVisible() return true end
    function UnitAffectingCombat(unit) return fighting[unit] == true end
    local FLAG = { name = "Warsong Flag", icon = "flag-art" }
    local ZERK = { name = "Berserking", icon = "zerk-art", duration = 10 }
    local function Wear(...)
        local list = {}
        for i = 1, select("#", ...) do
            local a = select(i, ...)
            local c = { name = a.name, icon = a.icon, duration = a.duration }
            if a.duration then c.expirationTime = now + a.duration end
            list[#list + 1] = c
        end
        __setUnitBuffs("party1", list)
    end
    local function AllyRow()
        for _, f in ipairs(allFrames) do
            if f.bgMarks and f.buffs and f.bar and f.stripe and f.__shown and f.__h ~= 11 and not f.scratch then
                return f
            end
        end
    end
    local function Point(tex)
        local p = tex.__points and tex.__points[1]
        return p and p.x, p and p.y
    end

    instanceKind = "pvp"
    Fire("PLAYER_ENTERING_WORLD")
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Wear(); Fire("UNIT_AURA", "party1"); Pump()
    local row = AllyRow()
    CHECK(row ~= nil, "grid: an ally row")
    if not row then return end
    local seatBarW = row._barW
    -- All four cells, each in its own corner
    local tx, ty = Point(row.raidMark)
    local cx, cy = Point(row.combatMark)
    local fx, fy = Point(row.bgMarks[1])
    local px, py = Point(row.bgMarks[2])
    CHECK(tx and cx and tx < cx and ty == cy and ty > 0, "grid: target mark top-left, combat top-right",
        string.format("t(%s,%s) c(%s,%s)", tostring(tx), tostring(ty), tostring(cx), tostring(cy)))
    CHECK(fx and px and fx < px and fy == py and fy < 0, "grid: flag bottom-left, powerup bottom-right",
        string.format("f(%s,%s) p(%s,%s)", tostring(fx), tostring(fy), tostring(px), tostring(py)))
    CHECK(tx == fx and cx == px, "grid: the columns line up")
    CHECK(row.raidMark.__w == 10 and row.combatMark.__w == 10 and row.bgMarks[1].__w == 10, "grid: ten-pixel cells")

    -- The flag goes to the flag cell even when it is not first in the list,
    -- and the powerup to its own; wearing both lights both
    Wear(ZERK, FLAG); Fire("UNIT_AURA", "party1"); Pump()
    CHECK(row.bgMarks[1].__shown == true and row.bgMarks[1].__texture == "flag-art", "grid: flag in the flag cell", row.bgMarks[1].__texture)
    CHECK(row.bgMarks[2].__shown == true and row.bgMarks[2].__texture == "zerk-art", "grid: powerup in the powerup cell", row.bgMarks[2].__texture)
    Wear(ZERK); Fire("UNIT_AURA", "party1"); Pump()
    CHECK(row.bgMarks[1].__shown == false and row.bgMarks[2].__shown == true, "grid: a powerup alone leaves the flag cell dark rather than sliding left")
    fighting.party1 = true
    Pump()
    CHECK(row.combatMark.__shown == true, "grid: ...with the blades lit beside it -- three marks, three cells")
    fighting.party1 = nil
    Wear(); Fire("UNIT_AURA", "party1"); Pump()

    -- The seat is one block: switching one mark off does not move the bar,
    -- switching all three off gives the whole seat back
    CommanderPartyFramesDB.ShowCombat = false
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE); Pump()
    CHECK(AllyRow()._barW == seatBarW, "grid: one mark off -> the bar does not move (the seat is spent as a block)",
        tostring(seatBarW) .. " -> " .. tostring(AllyRow()._barW))
    CommanderPartyFramesDB.ShowTargetMarks = false
    CommanderPartyFramesDB.ShowBGBuffs = false
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE); Pump()
    CHECK(AllyRow()._barW == seatBarW + 24, "grid: all three off -> the 21px seat and its gap come back to the bar",
        tostring(seatBarW) .. " -> " .. tostring(AllyRow()._barW))
    -- Outside a battleground the seat is the same width: nothing zone-dependent
    CommanderPartyFramesDB.ShowTargetMarks = true
    CommanderPartyFramesDB.ShowCombat = true
    CommanderPartyFramesDB.ShowBGBuffs = true
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE); Pump()
    instanceKind = "arena"
    Fire("PLAYER_ENTERING_WORLD"); Pump()
    CHECK(AllyRow()._barW == seatBarW, "grid: an arena row keeps the same seat (no zone relayout)",
        tostring(AllyRow()._barW) .. " vs " .. tostring(seatBarW))
    -- Versus the old layout, the seat is a third of the width
    CommanderPartyFramesDB.MarkLayout = "ROW"
    instanceKind = "pvp"
    Fire("PLAYER_ENTERING_WORLD")
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE); Pump()
    CHECK(AllyRow()._barW < seatBarW, "grid: the stacked seat leaves the bar wider than a row of seats in a battleground",
        tostring(AllyRow()._barW) .. " vs " .. tostring(seatBarW))

    -- The blueprint describes the seat
    CommanderPartyFramesDB.MarkLayout = "GRID"
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE); Pump()
    local bp = CommanderPartyFrames_RowBlueprint()
    CHECK(bp and bp.grid == true and bp.seat == 21 and bp.cell == 10, "grid: blueprint reports the seat")

    __setUnitBuffs("party1", nil)
    instanceKind = keepZone
    CommanderPartyFramesDB.MarkLayout = keepLayout
    CommanderPartyFramesDB.IncludeSelf = keepSelf
    UnitExists, UnitGUID, UnitInRange = baseExists, baseGUID, baseRange
    UnitAffectingCombat, UnitIsVisible = baseCombat, baseVisible
    partyUp = {}
    Fire("PLAYER_ENTERING_WORLD")
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    Fire("GROUP_ROSTER_UPDATE"); Pump()
end

-- ===========================================================================
-- Nearby Raid: a released ghost is infinitely far; an unreleased corpse is not
-- ===========================================================================
local function CheckGhosts()
    local near = CommanderPartyFrames_NearYards
    if not near then
        CHECK(false, "ghosts: CommanderPartyFrames_NearYards is exported")
        return
    end
    local baseGhost, basePos = UnitIsGhost, UnitPosition
    function UnitPosition(unit)
        if unit == "player" then return 0, 0, 0, 1 end
        return 30, 40, 0, 1     -- 50 yards away
    end
    local ghosts = {}
    function UnitIsGhost(unit) return ghosts[unit] == true end
    local keep = CommanderPartyFramesDB.NearGhostsFar
    CommanderPartyFramesDB.NearGhostsFar = true
    local y = near("raid3")
    CHECK(math.abs(y - 50) < 0.01, "ghosts: a living ally is measured", y)
    ghosts.raid3 = true
    y = near("raid3")
    CHECK(y >= 400, "ghosts: a released ghost is further than anything measurable", y)
    CommanderPartyFramesDB.NearGhostsFar = false
    y = near("raid3")
    CHECK(math.abs(y - 50) < 0.01, "ghosts: ...unless the option is off", y)
    CommanderPartyFramesDB.NearGhostsFar = keep
    UnitIsGhost, UnitPosition = baseGhost, basePos
end

-- ===========================================================================
-- Production in Header (5.28.0)
-- ===========================================================================
-- Commander_Production's queue standing in for the class cooldown run. It is
-- mocked here as the one function the embed reads — the module itself never
-- loads in this harness — so what is under test is the banner's half of the
-- contract: the run's slot is taken, the class cooldowns are gone, the rest
-- of the readout is untouched, and every way the queue can be absent hands
-- the slot back.
local function CheckProductionEmbed()
    local rootF = _G.CommanderPartyFramesFrame
    local db = CommanderPartyFramesDB
    local function Redraw()
        Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
        now = now + 1
        for _, f in ipairs(allFrames) do PumpFrame(f, 10) end
    end
    local function Shown()
        local out, segs = {}, rootF.hdrSegs or {}
        for i = 1, #segs do
            if segs[i].icon.__shown then out[#out + 1] = segs[i] end
        end
        return out
    end
    local function Textures()
        local out = {}
        for _, s in ipairs(Shown()) do out[s.icon.__texture or "?"] = true end
        return out
    end
    -- One cooldown each layer's mock spellbook knows, so the swap is
    -- visible on every class this runs on
    local CLASS_CD = {
        MAGE = "Interface\\Icons\\Spell_45438",     -- Ice Block
        PRIEST = "Interface\\Icons\\Spell_33206",   -- Pain Suppression
        DRUID = "Interface\\Icons\\Spell_29166",    -- Innervate
        PALADIN = "Interface\\Icons\\Spell_633",    -- Lay on Hands
    }
    local classCd = CLASS_CD[CLASS]
    local PROD_A = "Interface\\Icons\\INV_Misc_PocketWatch_01"
    local PROD_B = "Interface\\Icons\\INV_Misc_PocketWatch_02"

    db.ShowHeader = true
    db.HeaderProduction = false
    for _, k in ipairs({ "MageBannerCooldowns", "PriestBannerCooldowns",
        "HotBannerCooldowns", "BlessBannerCooldowns" }) do db[k] = true end
    _G.CommanderProduction_Queue = nil
    Redraw()
    local before = Textures()
    CHECK(classCd and before[classCd] == true,
        "embed: the class cooldown run draws with the option off", classCd)
    local baseline = #Shown()
    local lead = Shown()[1] and Shown()[1].icon.__texture

    -- The mock queue: one pending entry ten seconds out, one lingering
    -- READY entry half faded, in the order Production sorts them
    local queue = {
        -- Redraw steps the clock by one before it draws, so this is ten
        -- seconds out as the banner sees it
        { name = "A", entry = { texture = PROD_A, start = now - 19, duration = 30, spellID = 1 } },
        { name = "B", entry = { texture = PROD_B, start = now - 60, duration = 30, readyAt = now },
          ready = true, alpha = 0.5 },
    }
    local enabled = true
    function _G.CommanderProduction_Queue()
        if not enabled then return nil end
        return queue, #queue
    end

    -- Option on, Production present: the queue takes the run's slot
    db.HeaderProduction = true
    Redraw()
    local drawn = Textures()
    CHECK(drawn[PROD_A] == true and drawn[PROD_B] == true,
        "embed: both queue entries get a segment")
    CHECK(drawn[classCd] ~= true,
        "embed: ...and the class cooldown run is gone", classCd)
    local segA, segB
    for _, sg in ipairs(Shown()) do
        if sg.icon.__texture == PROD_A then segA = sg end
        if sg.icon.__texture == PROD_B then segB = sg end
    end
    CHECK(segA and segA.icon.__desat == true and segA.text.__text == "10",
        "embed: a pending entry is dimmed with its seconds left, computed live",
        segA and tostring(segA.text.__text))
    CHECK(segB and segB.icon.__desat == false and (segB.text.__text or "") == ""
        and segB.icon.__alpha == 0.5,
        "embed: a READY entry is lit, bare, and carries Production's fade",
        segB and tostring(segB.icon.__alpha))
    -- Same grammar as the class run for a long wait
    queue[1].entry.start = now
    queue[1].entry.duration = 600
    Redraw()
    for _, sg in ipairs(Shown()) do
        if sg.icon.__texture == PROD_A then segA = sg end
    end
    CHECK(segA and segA.text.__text == "10m",
        "embed: minutes read as the class run writes them", segA and segA.text.__text)
    -- The segments AHEAD of the run keep their slots: whatever led the
    -- banner before (armor / aura / Inner Fire) still leads it. A druid in
    -- caster form spends no slot on the form, so there the run itself led
    -- and the queue rightly takes its place.
    local first = Shown()[1]
    if lead and lead ~= classCd then
        CHECK(first and first.icon.__texture == lead,
            "embed: the layer's leading segment still leads", first and first.icon.__texture)
    else
        CHECK(first and first.icon.__texture == PROD_A,
            "embed: with nothing ahead of the run, the queue leads", first and first.icon.__texture)
    end
    -- Gear and rows toggle are untouched by the swap
    local gear, rows
    for _, f in ipairs(allFrames) do
        if f.cog and f.hub then gear = f end
    end
    CHECK(gear == nil or gear.__shown ~= false, "embed: the settings gear is still on the header")

    -- An entry that ran out while Production's frame was closed is not drawn
    -- on a stale `remaining`: the time left is computed here
    queue[1].entry.start = now - 100
    queue[1].entry.duration = 30
    Redraw()
    CHECK(Textures()[PROD_A] ~= true, "embed: an expired pending entry is skipped, not drawn at zero")
    queue[1].entry.start = now
    -- Queue emptied: nothing from Production, and the class run stays gone
    -- (the option is on and the module is up — an empty queue is the truth)
    local keepA, keepB = queue[1], queue[2]
    queue[1], queue[2] = nil, nil
    Redraw()
    drawn = Textures()
    CHECK(drawn[PROD_A] ~= true and drawn[classCd] ~= true,
        "embed: an empty queue draws nothing in the slot, and no class fallback")
    queue[1], queue[2] = keepA, keepB

    -- Production disabled at its own master switch: the class run comes back
    enabled = false
    Redraw()
    drawn = Textures()
    CHECK(drawn[classCd] == true and drawn[PROD_A] ~= true,
        "embed: Production switched off hands the slot back to the class run")
    enabled = true

    -- Option off: the class run comes back, and the queue is gone
    db.HeaderProduction = false
    Redraw()
    drawn = Textures()
    CHECK(drawn[classCd] == true and drawn[PROD_A] ~= true and drawn[PROD_B] ~= true,
        "embed: the option off restores the class run")
    CHECK(#Shown() == baseline, "embed: ...to exactly the segments it had",
        string.format("%d vs %d", #Shown(), baseline))

    -- Production not loaded at all: the option is inert, not an error
    db.HeaderProduction = true
    _G.CommanderProduction_Queue = nil
    Redraw()
    drawn = Textures()
    CHECK(drawn[classCd] == true, "embed: no Production loaded, class run untouched")
    db.HeaderProduction = false
    Redraw()
end

-- ===========================================================================
-- Header presentation
-- ===========================================================================
-- The Header section makes eleven things about the banner adjustable, and the
-- first promise it makes is that none of them move until you move them: every
-- default is the number the header used to hard-code. So this checks the
-- defaults as EXACT numbers, then takes each control somewhere extreme and
-- checks the banner actually followed it there.
--
-- Runs on every class layer because the banner is chassis: the four layers
-- differ in what the readout says, never in how it is drawn.
local function CheckHeaderStyle()
    local rootF = _G.CommanderPartyFramesFrame
    local db = CommanderPartyFramesDB
    -- Its own pump rather than the file-level DrawOnce: this runs on both
    -- sides of the non-mage early exit, and that helper is declared below it.
    local function Redraw()
        Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
        now = now + 1
        for _, f in ipairs(allFrames) do PumpFrame(f, 10) end
    end
    local function Anchor(w)
        return w.__points and w.__points[#w.__points]
    end
    local gear
    for _, f in ipairs(allFrames) do
        if f.cog and f.hub then gear = f end
    end

    db.ShowHeader = true
    db.HeaderBackdrop = true
    Redraw()
    local segs = rootF.hdrSegs
    CHECK(segs and segs[1] and segs[1].icon.__w == 12,
        "a banner nobody has configured draws 12px segment icons",
        segs and segs[1] and tostring(segs[1].icon.__w))
    CHECK(rootF.headerBG and rootF.headerBG.__h == 15,
        "...in a 15px strip", rootF.headerBG and tostring(rootF.headerBG.__h))
    local bg = rootF.headerBG and rootF.headerBG.__color or {}
    CHECK(bg[1] == 0 and bg[2] == 0 and bg[3] == 0 and bg[4] == 0.55,
        "...on the black-at-55% panel it always had",
        table.concat({ tostring(bg[1]), tostring(bg[4]) }, "/"))
    CHECK(rootF.headerRule == nil or rootF.headerRule.__shown ~= true,
        "...and no divider line, which is the new thing and so is off")

    -- Height and icon size together: everything on the strip centres itself
    -- in whatever height it is given, so these two are only correct RELATIVE
    -- to each other and a test that pinned one without the other would pass
    -- on a banner drawn hard against the top edge.
    db.HeaderHeight, db.HeaderIconSize = 31, 21
    db.HeaderSegmentGap, db.HeaderInset = 2, 11
    Redraw()
    CHECK(rootF.headerBG.__h == 31, "the strip takes the height it is given",
        tostring(rootF.headerBG.__h))
    CHECK(segs[1].icon.__w == 21 and segs[1].icon.__h == 21,
        "and the icons the size they are given", tostring(segs[1].icon.__w))
    local first = Anchor(segs[1].icon)
    CHECK(first and first.y == -5, "a 21px icon centres in a 31px strip",
        first and tostring(first.y))
    local second = Anchor(segs[2].icon)
    CHECK(second and second.rel == segs[1].text and second.x == 2,
        "and the next segment follows at the gap it was given",
        second and tostring(second.x))
    CHECK((rootF._segX or 0) >= 3 + 11,
        "the readout starts past the stripe plus the inset",
        tostring(rootF._segX))

    -- Growing a pool that is already built is the case this gets wrong if
    -- EnsureSegs and RestyleHeader disagree about who owns the size: a
    -- segment created AFTER the settings changed must match its siblings.
    for i = 2, #segs do
        CHECK(segs[i].icon.__w == 21,
            "every segment in the pool carries the new size, not just the first",
            i .. ":" .. tostring(segs[i].icon.__w))
    end

    -- A strip SHORTER than its contents hangs them from the top rather than
    -- pushing them above the board, which is the one case where centring has
    -- to give up rather than go negative.
    db.HeaderHeight, db.HeaderIconSize = 10, 20
    Redraw()
    first = Anchor(segs[1].icon)
    CHECK(first and first.y == 0,
        "an icon taller than its strip is pinned to the top, never above it",
        first and tostring(first.y))

    -- Font
    db.HeaderHeight, db.HeaderIconSize = 15, 12
    db.HeaderFont, db.HeaderFontSize, db.HeaderFontOutline = "NARROW", 16, "THICK"
    Redraw()
    local font = segs[1].text.__font or {}
    CHECK(font[1] == "Fonts\\ARIALN.TTF" and font[2] == 16 and font[3] == "THICKOUTLINE",
        "face, size and outline all reach the readout",
        table.concat({ tostring(font[1]), tostring(font[2]), tostring(font[3]) }, " "))

    -- Chrome: scaled, not resized, and the anchor offsets are divided back
    -- out of the scale -- a button at 2x asked for -6 lands twelve of root's
    -- pixels from the edge, which is the bug this pins.
    if gear then
        db.HeaderChromeScale = 1
        Redraw()
        local plain = Anchor(gear)
        db.HeaderChromeScale = 2
        Redraw()
        CHECK(gear.__scale == 2, "the control size scales the gear",
            tostring(gear.__scale))
        local big = Anchor(gear)
        CHECK(plain and big and math.abs(big.x - plain.x / 2) < 0.001,
            "and its offset is divided back out, so it stays on the edge",
            plain and big and (tostring(plain.x) .. " -> " .. tostring(big.x)))
        db.HeaderChromeScale = 1
        Redraw()
    end

    -- Tint and opacity
    db.HeaderBackdropTint, db.HeaderBackdropAlpha = "BLOOD", 0.9
    Redraw()
    local tint = rootF.headerBG.__color or {}
    CHECK(tint[1] > tint[2] and tint[1] > tint[3] and tint[4] == 0.9,
        "a red tint reaches the panel at the opacity asked for",
        table.concat({ tostring(tint[1]), tostring(tint[4]) }, "/"))
    db.HeaderBackdropTint = "CLASS"
    Redraw()
    tint = rootF.headerBG.__color or {}
    CHECK(tint[1] <= 0.35 and tint[2] <= 0.35 and tint[3] <= 0.35,
        "and a class colour is mixed DOWN to backdrop weight, not used raw",
        table.concat({ tostring(tint[1]), tostring(tint[2]), tostring(tint[3]) }, "/"))

    -- The divider is deliberately independent of the panel: switching the
    -- backdrop off and the line on is the whole point of having both.
    db.HeaderBackdropTint, db.HeaderBackdropAlpha = "BLACK", 0.55
    db.HeaderBackdrop, db.HeaderRule = false, true
    Redraw()
    CHECK(rootF.headerBG.__shown == false, "the panel goes when it is switched off")
    CHECK(rootF.headerRule and rootF.headerRule.__shown == true,
        "and the divider line stands on its own without it")
    local rule = Anchor(rootF.headerRule)
    CHECK(rule and rule.y == -15, "drawn along the strip's bottom edge",
        rule and tostring(rule.y))
    local rc = rootF.headerRule.__color or {}
    CHECK(rc[1] and rc[1] > 0,
        "in a LIFTED tint -- black on black is not a line", tostring(rc[1]))

    -- Header off takes the whole thing, new pieces included
    db.ShowHeader = false
    Redraw()
    CHECK(rootF.headerRule.__shown == false,
        "and Show Header still takes everything on the strip down with it")

    db.ShowHeader, db.HeaderBackdrop, db.HeaderRule = true, true, false
    db.HeaderFont, db.HeaderFontSize, db.HeaderFontOutline = "DEFAULT", 10, "NONE"
    db.HeaderSegmentGap, db.HeaderInset = 8, 4
    Redraw()
end
if CLASS ~= "MAGE" then
    CheckSectionSizing()
    CheckRowFit()
    CheckBuffStrip()
    CheckAbilityScope()
    CheckClickMatrix()
    CheckBuffGrid()
    CheckBlessAssign()
    CheckShadowRead()
    CheckBuffTargets()
    CheckPets()
    CheckPowerStrip()
    CheckForecast()
    CheckHealPredict()
    CheckOverheal()
    CheckCombatMarks()
    CheckBGMarks()
    -- Nearby Raid is chassis, not a class layer, so it is verified on every
    -- board rather than only the one this file happens to start on
    CheckNearby()
    CheckBlizzToggle()
    CheckDropdowns()
    -- The mage layer's controls must NOT appear on another class's banner
    CHECK(consume == nil, "no consume button off the mage layer")
    CHECK(conjure == nil, "no conjure button off the mage layer")
    CHECK(gem == nil, "no gem button off the mage layer")
    CHECK(portal == nil, "no portal button off the mage layer")
    local bandMacroP = bandage:GetAttribute("macrotext1")
    CHECK(bandMacroP:find("[help,nodead][@player] item:21991", 1, true) ~= nil,
        "bandage binds the same way on every class", bandMacroP)
    CommanderPartyFramesDB.ShowHeader = true
    for _, f in ipairs(allFrames) do
        local u = f.__scripts.OnUpdate
        PumpFrame(f, 10)
    end
    -- The other half of the same bug: with the cluster walk broken,
    -- ClusterWidth reported 0, so the banner's own content started hard left
    -- and ran straight over the bandage button. Whatever this layer draws in
    -- that block — plain text on the priest board, icon segments on the
    -- druid's — has to begin past the button.
    do
        local rootF = _G.CommanderPartyFramesFrame
        local content = rootF.header
        if rootF.hdrSegs and rootF.hdrSegs[1].icon.__shown then
            content = rootF.hdrSegs[1].icon
        end
        local p = content and content.__points[#content.__points]
        CHECK(p ~= nil and p.x and p.x >= 6 + 13,
            "banner content starts clear of the bandage button", p and p.x)
    end
    CheckHeaderStyle()
    CheckProductionEmbed()
    CHECK(#caughtErrors == 0, "no errors on the non-mage banner", caughtErrors[1])
    io.write(string.format("[%s] %d checks, %d failures\n", CLASS, checks, fails))
    os.exit(fails == 0 and 0 or 1)
end

CHECK(consume ~= nil, "consume button exists")
CHECK(conjure ~= nil, "conjure button exists")
CHECK(gem ~= nil, "gem button exists")
CHECK(portal ~= nil, "portal button exists")

-- Consume: left drinks, right eats (the old build fired both on left)
local drink = consume:GetAttribute("macrotext1")
local eat = consume:GetAttribute("macrotext2")
CHECK(drink:find("item:30703", 1, true) ~= nil, "left-click drinks the best water", drink)
CHECK(drink:find("item:22019", 1, true) == nil, "left-click does NOT eat", drink)
-- The Manna Biscuit is food AND drink, so it heads both lists: pressing
-- left and right together on a biscuit-only mage must still do both
CHECK(eat:find("item:30703", 1, true) ~= nil,
    "right-click eats the best food rank held — the dual-purpose biscuit", eat)
CHECK(eat:find("item:8079", 1, true) == nil, "right-click does NOT reach for water-only ranks", eat)
-- One item per click. Food and drink share no cooldown, so every /use line
-- landed and a cascade swallowed one of EVERY rank held on a single press.
CHECK(drink:find("item:8079", 1, true) == nil,
    "drink stops at the best rank instead of downing the whole cascade", drink)
CHECK(select(2, drink:gsub("/use", "")) == 1, "left-click is exactly one /use", drink)
CHECK(select(2, eat:gsub("/use", "")) == 1, "right-click is exactly one /use", eat)
-- ...and the cap costs nothing, because the bind re-aims at the next rank the
-- moment the best one runs dry. Biscuits gone: drink and eat split apart.
local savedBiscuits = bags[30703]
bags[30703] = nil
Fire("BAG_UPDATE_DELAYED")
CHECK(consume:GetAttribute("macrotext1") == "/use item:8079",
    "drink falls to the next water rank once the best is gone",
    consume:GetAttribute("macrotext1"))
CHECK(consume:GetAttribute("macrotext2") == "/use item:22019",
    "eat falls to the next food rank once the best is gone",
    consume:GetAttribute("macrotext2"))
bags[30703] = savedBiscuits
Fire("BAG_UPDATE_DELAYED")

-- Conjure unchanged: left water, right food
CHECK(conjure:GetAttribute("spell1") == "Conjure Water", "conjure left = water")
CHECK(conjure:GetAttribute("spell2") == "Conjure Food", "conjure right = food")

-- Gem: the hand-written macro's shape — [mod] steps the conjure sequence,
-- [nomod] uses, right-click steps the same sequence
local gemUse = gem:GetAttribute("macrotext1")
local gemSeq = "reset=10 Conjure Mana Ruby, Conjure Mana Citrine, Conjure Mana Jade, Conjure Mana Agate"
CHECK(gemUse:find("/castsequence [mod] " .. gemSeq, 1, true) ~= nil,
    "gem: modifier walks the sequence over the KNOWN ranks (Emerald untrained)", gemUse)
CHECK(gemUse:find("/use [nomod] item:8008", 1, true) ~= nil, "gem: plain click uses the gem held", gemUse)
CHECK(gem:GetAttribute("macrotext2") == "/castsequence " .. gemSeq,
    "gem: right-click walks the same sequence", gem:GetAttribute("macrotext2"))
-- Identical sequence text on both lines: the client keys a castsequence's
-- position on that text, so left+modifier and right-click stay in step
CHECK(gemUse:find(gemSeq, 1, true) ~= nil
    and gem:GetAttribute("macrotext2"):find(gemSeq, 1, true) ~= nil,
    "gem: both clicks share one sequence definition")

-- Bandage: friendly target else self, best rank first
local bandMacro = bandage:GetAttribute("macrotext1")
CHECK(bandMacro:find("[help,nodead][@player] item:21991", 1, true) ~= nil,
    "bandage targets a friendly ally, else you", bandMacro)
CHECK(bandMacro:find("item:21990", 1, true) ~= nil, "bandage falls through to the next rank", bandMacro)

-- ===========================================================================
-- Portals popout: known destinations only, two rows
-- ===========================================================================
local portalBtns, hordeShown = {}, false
for i = 1, 30 do
    local b = _G["CommanderPartyFramesPortalBtn" .. i]
    if not b then break end
    if b.__shown then
        portalBtns[#portalBtns + 1] = b
        if (b.__attr.spell or ""):find("Orgrimmar") then hordeShown = true end
    end
end
CHECK(#portalBtns == 10, "popout shows the 10 known Alliance destinations", #portalBtns)
CHECK(not hordeShown, "the other faction's teleports stay out")
-- Row split: teleports on top (y offset -3), portals below (-24)
local topRow, bottomRow = 0, 0
for _, b in ipairs(portalBtns) do
    local p = b.__points[#b.__points]
    if p.y == -3 then topRow = topRow + 1 elseif p.y == -24 then bottomRow = bottomRow + 1 end
end
CHECK(topRow == 5, "teleports fill the top row", topRow)
CHECK(bottomRow == 5, "portals fill the bottom row", bottomRow)

-- ===========================================================================
-- Counters
-- ===========================================================================
-- Advance the clock each draw: the engine re-scans the bandage target at
-- 4 Hz, so a frozen clock would never let a second scan through
local function DrawOnce()
    now = now + 1
    for _, f in ipairs(allFrames) do
        local u = f.__scripts.OnUpdate
        PumpFrame(f, 10)
    end
end
CommanderPartyFramesDB.ShowHeader = true
DrawOnce()

local function CountText(fs) return fs and fs.__shown and fs.__text or nil end
-- One tally per button: water on Conjure, food on Consume — together on the
-- 16px Consume button they overlapped into an unreadable smear
CHECK(CountText(conjure.count) == "32", "water counter rides Conjure, summing every rank (20+12)",
    CountText(conjure.count))
CHECK(CountText(consume.count) == "28", "food counter rides Consume, biscuits included (20+8)",
    CountText(consume.count))
CHECK(consume.countL == nil and consume.countR == nil,
    "Consume no longer carries both counters")
CHECK(CountText(gem.count) == "3", "gem counter over the icon", CountText(gem.count))
CHECK(CountText(bandage.count) == "7", "bandage counter (5+2)", CountText(bandage.count))

-- Counters are optional
CommanderPartyFramesDB.ShowUtilityCounts = false
DrawOnce()
CHECK(CountText(consume.count) == nil, "counters hide when the option is off")
CHECK(CountText(bandage.count) == nil, "bandage counter hides too")
CommanderPartyFramesDB.ShowUtilityCounts = true

-- Counters keep updating while the binds are frozen in combat
bags[8008] = 1
Fire("BAG_UPDATE_DELAYED")
DrawOnce()
CHECK(CountText(gem.count) == "1", "counter follows the bags", CountText(gem.count))

-- ===========================================================================
-- Bandage lockout
-- ===========================================================================
unitDebuffs.player = { { name = "Recently Bandaged", expirationTime = now + 42 } }
DrawOnce()
CHECK(bandage.cd.__shown == true, "lockout shows the countdown sweep")
CHECK(bandage.cd.__cdDur == 60, "sweep runs the 60s Recently Bandaged window", bandage.cd.__cdDur)
CHECK((bandage.tip1 or ""):find("Recently Bandaged", 1, true) ~= nil,
    "tooltip names the lockout", bandage.tip1)

-- A friendly target is who the bandage would land on
targetUnit, targetFriendly = "ally", true
unitDebuffs.target = {}
DrawOnce()
CHECK(bandage.cd.__shown == false, "a clean friendly target clears the lockout state")
CHECK((bandage.tip1 or ""):find("Ally", 1, true) ~= nil, "tooltip names the target", bandage.tip1)
unitDebuffs.target = { { name = "Recently Bandaged", expirationTime = now + 30 } }
DrawOnce()
CHECK(bandage.cd.__shown == true, "target's own lockout is what blocks the cast")
targetUnit = nil

-- ===========================================================================
-- One click, one action
-- ===========================================================================
-- The client delivers a click once per REGISTERED edge. With both edges
-- registered every tap ran the handler twice: the secure buttons double-cast,
-- and the popout toggles opened then shut again — or stuck open when the
-- mouse drifted off the button and only the press landed.
local function Tap(btn, which)
    local post = btn.__scripts.PostClick
    if not post then return end
    for _, edge in ipairs(btn.__clicks or { "AnyUp" }) do
        post(btn, which or "LeftButton", edge:find("Down") ~= nil)
    end
end
for _, b in ipairs({ consume, conjure, gem, portal, bandage }) do
    CHECK(b.__clicks and #b.__clicks == 1 and b.__clicks[1] == "AnyUp",
        "banner buttons fire on one edge only", b.__name .. ": "
        .. table.concat(b.__clicks or { "?" }, "+"))
end

local portalPop = _G.CommanderPartyFramesPortalBtn1.__parent
portalPop:Hide()
Tap(portal)
CHECK(portalPop:IsShown() == true, "one tap opens the portals popout")
Tap(portal)
CHECK(portalPop:IsShown() == false, "the next tap closes it")
Tap(portal)
CHECK(portalPop:IsShown() == true, "and it opens again — no stuck state")

-- ===========================================================================
-- First Aid: middle-click opens the window itself
-- ===========================================================================
-- There is no craft popout any more: the tradeskill list can only be read
-- while First Aid is already open, so the popout's only offer was to open it.
local before = #castByName
Tap(bandage, "MiddleButton")
CHECK(#castByName == before + 1, "middle-click acts exactly once", #castByName - before)
CHECK(castByName[#castByName] == "First Aid", "middle-click opens First Aid",
    castByName[#castByName])
CHECK(portalPop:IsShown() == false, "opening First Aid tidies the portals popout away")

-- Left-click stays the bandage cast, untouched by the middle-click path
before = #castByName
Tap(bandage, "LeftButton")
CHECK(#castByName == before, "a plain click casts nothing by name", #castByName - before)

-- In combat the trade window may not be opened at all
inCombat = true
before = #castByName
Tap(bandage, "MiddleButton")
CHECK(#castByName == before, "combat blocks the First Aid window", #castByName - before)
inCombat = false

-- ===========================================================================
-- Armor segment: a radial, no text
-- ===========================================================================
-- The banner used to spell out "18m" / "OFF" next to the icon. The ring says
-- it now, so the segment is icon-only and the colour carries the alarm.
-- The segment pool is shared by every banner layer now (hdrSegs); the armor
-- radial is the mage banner's own extra, hung off its first segment.
local hdr = _G.CommanderPartyFramesFrame.hdrSegs
local armorCd = _G.CommanderPartyFramesFrame.armorCd
CHECK(hdr ~= nil and armorCd ~= nil, "the mage banner built its armor radial")

-- The banner reads armor off the player's own aura scan, which UNIT_AURA drives
local function ArmorNow()
    Fire("UNIT_AURA", "player")
    DrawOnce()
end
playerBuffs = { { name = "Ice Armor", expirationTime = now + 1500, duration = 1800,
    icon = "Interface\\Icons\\Spell_27124" } }
ArmorNow()
CHECK((hdr[1].text.__text or "") == "", "armor segment carries no text", hdr[1].text.__text)
CHECK(armorCd.__shown == true, "the radial runs while armor is up")
CHECK(armorCd.__cdDur == 1800, "the ring is scaled to the buff's own duration", armorCd.__cdDur)
CHECK(armorCd.__cdStart == playerBuffs[1].expirationTime - 1800, "ring starts when the buff did",
    armorCd.__cdStart)
CHECK(hdr[1].icon.__color == nil or hdr[1].icon.__color[1] == 1 and hdr[1].icon.__color[2] == 1,
    "a healthy armor icon stays untinted")

-- Inside the last five minutes the icon goes amber — the old amber text
playerBuffs[1].expirationTime = now + 200
ArmorNow()
local tint = hdr[1].icon.__color or {}
CHECK(tint[1] == 1 and tint[2] and tint[2] < 0.8 and tint[3] and tint[3] < 0.5,
    "armor about to lapse tints amber", table.concat({ tostring(tint[1]), tostring(tint[2]),
        tostring(tint[3]) }, ","))

-- Naked: the dim red icon replaces the old OFF text, and the ring clears
playerBuffs = {}
ArmorNow()
CHECK((hdr[1].text.__text or "") == "", "no armor, still no text", hdr[1].text.__text)
CHECK(armorCd.__shown == false, "no armor, no ring")

-- --- Banner cooldowns --------------------------------------------------
-- The mage banner was the last of the four without them: armor, uptime and
-- alerts, and no way to see your own Ice Block.
do
    local function Textures()
        local out = {}
        for i = 1, #hdr do
            if hdr[i].icon.__shown then out[hdr[i].icon.__texture or "?"] = true end
        end
        return out
    end
    CommanderPartyFramesDB.MageBannerCooldowns = true
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    ArmorNow()
    local drawn = Textures()
    CHECK(drawn["Interface\\Icons\\Spell_45438"] == true,
        "Ice Block, which this mage knows, gets a segment")
    CHECK(drawn["Interface\\Icons\\Spell_11129"] ~= true,
        "Combustion, which they do not, never does")
    CHECK(drawn["Interface\\Icons\\Spell_11958"] == true,
        "Cold Snap does too — Block's answer reads next to Block")
    -- The banner is Block and Cold Snap and nothing else. Everything a mage
    -- PRESSES already wears a cooldown swipe on the action bar, three times
    -- this size, exactly where the eyes go to press it again; repeating it in
    -- 12px up here bought nothing and spent the width the readout needs.
    for id, what in pairs({
        [12051] = "Evocation", [2139] = "Counterspell", [12472] = "Icy Veins",
        [12043] = "Presence of Mind", [12042] = "Arcane Power",
        [66] = "Invisibility", [122] = "Frost Nova",
    }) do
        CHECK(drawn["Interface\\Icons\\Spell_" .. id] ~= true,
            what .. " is off the banner: the action bar already says it")
    end
    -- Both live on their own rows below the board; repeating them here would
    -- be width spent twice
    CHECK(drawn["Interface\\Icons\\Spell_11426"] ~= true,
        "Ice Barrier stays on its My Shields row, not the banner")
    CHECK(drawn["Interface\\Icons\\Spell_31687"] ~= true,
        "...and the Water Elemental stays on its own row")

    CommanderPartyFramesDB.MageBannerCooldowns = false
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    ArmorNow()
    CHECK(Textures()["Interface\\Icons\\Spell_45438"] ~= true,
        "the banner cooldowns answer their toggle")
    CommanderPartyFramesDB.MageBannerCooldowns = true
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    ArmorNow()
end
CHECK(hdr[1].icon.__desat == true, "the naked-mage icon is desaturated")
tint = hdr[1].icon.__color or {}
CHECK(tint[1] == 1 and tint[2] and tint[2] < 0.4, "and red", tostring(tint[2]))

-- ===========================================================================
-- Water Elemental: the Freeze planner tick
-- ===========================================================================
-- The tick answers whichever question is still open. Freeze ready: the gold
-- spend-by deadline, at 25s of life left, past which a cast leaves no room
-- for a second. Freeze spent: the frost-blue moment it comes back up.
petOut = true
clogEvent = { now, "SPELL_SUMMON", false, "player-guid", "Tester", 0, 0,
    "pet-guid", "Elemental", 0, 0, 31687 }
Fire("COMBAT_LOG_EVENT_UNFILTERED")
local summoned = now
DrawOnce()

-- The elemental row is the only row that carries a planner tick
local function Tick()
    for _, f in ipairs(allFrames) do
        if f.markTick and f.markTick.__shown then return f.markTick, f end
    end
end
local function TickX()
    local t = Tick()
    local p = t and t.__points[#t.__points]
    return p and p.x
end
local tick, eleRow = Tick()
CHECK(tick ~= nil, "the elemental row shows a Freeze planner tick")
local barW = eleRow and eleRow._barW or 0
CHECK(barW > 0, "row bar width known", barW)

-- Freeze ready: gold, parked at the double-cast deadline
local function Near(a, b) return a and b and math.abs(a - b) < 0.51 end
CHECK(Near(TickX(), barW * 25 / 45), "ready: the tick marks the 25s spend-by deadline",
    string.format("%.1f vs %.1f", TickX() or -1, barW * 25 / 45))
CHECK(tick.__color and tick.__color[1] == 1 and tick.__color[2] > 0.8 and tick.__color[3] < 0.5,
    "ready: the deadline tick is gold")

-- Freeze cast at 5s of life spent: 25s cooldown, 40s of elemental left.
-- The tick must jump to where the drain will be when Freeze is back: 15s.
now = summoned + 5
freezeStart, freezeDur = now, 25
DrawOnce()
CHECK(Near(TickX(), barW * 15 / 45), "spent: the tick moves to the next Freeze window",
    string.format("%.1f vs %.1f", TickX() or -1, barW * 15 / 45))
tick = Tick()
CHECK(tick.__color and tick.__color[1] < 0.6 and tick.__color[3] == 1,
    "spent: the next-window tick is frost blue")

-- It is a moment in the elemental's life, not a countdown: as the cooldown
-- and the lifespan drain together, the tick stays put and the bar comes to it
now = now + 8
DrawOnce()
CHECK(Near(TickX(), barW * 15 / 45), "the mark holds still while both clocks run",
    string.format("%.1f vs %.1f", TickX() or -1, barW * 15 / 45))

-- Freeze back up with 32s of life left: the gold deadline returns
freezeStart, freezeDur = 0, 0
DrawOnce()
tick = Tick()
CHECK(Near(TickX(), barW * 25 / 45), "ready again: back to the spend-by deadline",
    string.format("%.1f vs %.1f", TickX() or -1, barW * 25 / 45))
CHECK(tick.__color and tick.__color[2] > 0.8 and tick.__color[3] < 0.5, "and gold again")

-- Cast so late that the cooldown outlasts the elemental: nothing left to plan
now = summoned + 30
freezeStart, freezeDur = now, 25
DrawOnce()
CHECK(Tick() == nil, "no second Freeze coming — the tick clears")
petOut = false
DrawOnce()

-- ===========================================================================
-- Layout: turning a button off closes the gap
-- ===========================================================================
local function AnchorChain()
    local chain = {}
    for _, b in ipairs({ consume, conjure, gem, portal, bandage }) do
        if b.__shown then
            local p = b.__points[#b.__points]
            chain[#chain + 1] = { btn = b, rel = p and p.rel }
        end
    end
    return chain
end
-- Conjure, Consume, Mana Gem and Portals are all between-games convenience,
-- and on this banner they sit in FRONT of the readout. Off by default, as a
-- group. Bandage is not in the group: it is the one you press mid-fight.
local chain = AnchorChain()
CHECK(#chain == 1 and chain[1].btn == bandage,
    "only Bandage on the cluster by default", #chain)
local bandAnchor = bandage.__points[#bandage.__points]
CHECK(bandAnchor.rel == _G.CommanderPartyFramesFrame and bandAnchor.point == "TOPLEFT",
    "...and it takes the left edge on its own", tostring(bandAnchor.point))

CommanderPartyFramesDB.MageUtilityButtons = true
Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
chain = AnchorChain()
CHECK(#chain == 5, "all five once the utility cluster is switched on", #chain)

CommanderPartyFramesDB.ShowGemButton = false
Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
CHECK(gem.__shown == false, "gem button hides when switched off")
local afterGem
for _, b in ipairs({ portal, bandage }) do
    local p = b.__points[#b.__points]
    if p and p.rel == gem then afterGem = b end
end
CHECK(afterGem == nil, "no button is left anchored to the hidden gem (no gap)")

CommanderPartyFramesDB.ShowBandageButton = false
Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
CHECK(bandage.__shown == false, "bandage button hides when switched off")
CommanderPartyFramesDB.ShowGemButton = true
CommanderPartyFramesDB.ShowBandageButton = true
Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
CHECK(gem.__shown and bandage.__shown, "both come back")

-- The group flag outranks the per-button ones: switching the cluster off
-- takes the gem and the portals with it and leaves the bandage alone.
CommanderPartyFramesDB.MageUtilityButtons = false
Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
CHECK(gem.__shown == false and conjure.__shown == false and consume.__shown == false,
    "the cluster flag takes conjure, consume and the gem with it")
CHECK(bandage.__shown == true, "...and leaves the bandage, which is not in the group")
CommanderPartyFramesDB.MageUtilityButtons = true
Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)

-- A mage with no teleports trained gets no portal button
for _, id in ipairs({ 3561, 3562, 3565, 32271, 33690, 10059, 11416, 11419, 32266, 33691 }) do
    knownIds[id] = nil
end
Fire("SPELLS_CHANGED")
CHECK(portal.__shown == false, "portal button hides when nothing is trained")

-- ===========================================================================
-- Header alignment and the personal block (mage layer)
-- ===========================================================================
local STRIPE_W_TEST = 3 + 4   -- STRIPE_W + the default Left Inset
local chromeBtn
for _, f in ipairs(allFrames) do
    if f.bars and f.slash then chromeBtn = f end
end

-- Header convention: class content left, Commander chrome right. The cluster
-- used to chain off the gear, which is how anything added to that corner
-- ended up underneath it.
local rootFrame = _G.CommanderPartyFramesFrame
local consumeAnchor = consume.__points[#consume.__points]
CHECK(consumeAnchor.rel == rootFrame and consumeAnchor.point == "TOPLEFT",
    "the class cluster leads the header's LEFT edge",
    tostring(consumeAnchor.point))
CHECK(consumeAnchor.rel ~= settingsBtn and consumeAnchor.rel ~= chromeBtn,
    "...and no longer chains off the Commander chrome")
local chromeAnchor = chromeBtn.__points[#chromeBtn.__points]
CHECK(chromeAnchor.point == "TOPRIGHT", "Commander chrome stays right-aligned",
    tostring(chromeAnchor.point))
-- Secure buttons own the fixed left anchor; the insecure readout flows after
CHECK((rootFrame._segX or 0) > STRIPE_W_TEST,
    "the banner readout starts after the cluster, not at the frame edge",
    tostring(rootFrame._segX))

-- Rows carry both a bar and a spell icon; height tells the two pools apart.
-- Only rows SHOWN this pass count — pooled leftovers keep stale anchors.
local allyTop, compactTop, allyH, compactH
for _, f in ipairs(allFrames) do
    if f.bar and f.spellIcon and f.__shown and f.__points and #f.__points > 0 then
        local y = f.__points[#f.__points].y
        if f.__h == 11 then
            compactH = f.__h
            if not compactTop or y > compactTop then compactTop = y end
        elseif f.__h == 22 then
            allyH = f.__h
            if not allyTop or y > allyTop then allyTop = y end
        end
    end
end
CHECK(compactH ~= nil, "personal rows lay out at the compact height")
CHECK(allyH ~= nil, "ally rows stay full height")
CHECK(compactH and allyH and compactH * 2 == allyH,
    "a personal row is exactly half an ally row",
    tostring(compactH) .. " vs " .. tostring(allyH))

-- Growing DOWN, offsets run negative from the top: the personal block leads,
-- so the topmost personal row sits at the SMALLER magnitude
CHECK(compactTop and allyTop and compactTop > allyTop,
    "the personal block renders before the party rows",
    tostring(compactTop) .. " vs " .. tostring(allyTop))

-- ===========================================================================
-- Personal rows carry their own label and the elemental's Freeze slot
-- ===========================================================================
-- A compact row is icon + label + bar, whatever UnitDisplay says: the ally
-- modes decide between a class icon and a name, and a personal row has no
-- class icon to offer. Reading the ally setting here reserved the label's
-- width and then drew nothing in it — a hole in front of every bar.
petOut = true
clogEvent = { now, "SPELL_SUMMON", false, "player-guid", "Tester", 0, 0,
    "pet-guid", "Elemental", 0, 0, 31687 }
Fire("COMBAT_LOG_EVENT_UNFILTERED")
freezeStart, freezeDur = 0, 0
DrawOnce()

CHECK(CommanderPartyFramesDB.UnitDisplay == nil
    or CommanderPartyFramesDB.UnitDisplay == "CLASS_ICON",
    "this runs on the icon-mode default, where the bug lived")
local compactRows, eleCompact = {}, nil
for _, f in ipairs(allFrames) do
    if f.bar and f.spellIcon and f.__shown and f.__h == 11 then
        compactRows[#compactRows + 1] = f
        if f.markTick and f.markTick.__shown then eleCompact = f end
    end
end
CHECK(#compactRows > 0, "the personal block is on screen", #compactRows)
for _, row in ipairs(compactRows) do
    CHECK(row.name.__shown == true and (row.name.__text or "") ~= "",
        "a personal row fills the label slot its layout reserved",
        tostring(row.name.__text))
end
CHECK(eleCompact ~= nil, "the elemental row is one of them")
if eleCompact then
    CHECK(eleCompact.inShield.__shown == true,
        "the elemental's Freeze icon is drawn")
    CHECK(eleCompact.inShield.__points and #eleCompact.inShield.__points > 0,
        "...in a slot the compact layout actually reserved for it")
    -- This slot is shared with Thorns and the incoming-shield tracker, which
    -- are DURATIONS and run reversed. Freeze is a cooldown, so the elemental
    -- row has to flip it back every paint or the sweep reads inside out.
    CHECK(eleCompact.inShieldCd.__reverse == false,
        "Freeze is a cooldown, so its sweep fills rather than drains",
        tostring(eleCompact.inShieldCd.__reverse))
    CHECK(eleCompact.inShield.__w == 10,
        "sized to the compact row, not the ally row", tostring(eleCompact.inShield.__w))
    -- The planner tick overhangs whatever strip it rides; on an 11px row the
    -- ally strip's height would have it poking into the bar above
    CHECK(eleCompact.markTick.__h == 2 + 4,
        "the planner tick is scaled to the compact lockout strip",
        tostring(eleCompact.markTick.__h))
end
petOut = false
DrawOnce()

-- ===========================================================================
-- Protected frames: a fight makes no blocked call
-- ===========================================================================
-- The utility container is a plain Frame that PARENTS secure buttons, so the
-- engine treats it as protected — Show() on it mid-fight is the blocked call
-- the client reported. Same for root, which holds the whole lot.
local mageUtilFrame = consume.__parent
CHECK(mageUtilFrame:IsProtected() == true,
    "the utility container is protected by its secure children")
CHECK(mageUtilFrame.__secureTemplate ~= true,
    "...without being built from a secure template of its own")
-- And the container is a SIBLING of the board, so it keeps that protection to
-- itself: root stays a plain frame that can still resize and hide mid-fight
CHECK(mageUtilFrame.__parent == UIParent, "the container hangs off UIParent, not the board")
CHECK(rootFrame:IsProtected() ~= true, "so the board root is NOT protected")

blockedCalls = {}
inCombat = true
DrawOnce(); DrawOnce(); DrawOnce()
CHECK(#blockedCalls == 0, "a draw in combat makes no protected call",
    blockedCalls[1])
CHECK(mageUtilFrame:IsShown() == true, "the cluster stays up through the fight")
inCombat = false

-- Frozen in the wrong state: the header is off when the fight starts, so the
-- cluster CANNOT come back up mid-fight. The readout has to measure what is
-- on screen — reserving the cluster's width for a cluster nobody can see is
-- the blank left margin.
CommanderPartyFramesDB.ShowHeader = false
DrawOnce()
CHECK(mageUtilFrame:IsShown() == false, "the header going down takes the cluster with it")
inCombat = true
CommanderPartyFramesDB.ShowHeader = true
blockedCalls = {}
DrawOnce()
CHECK(#blockedCalls == 0, "and it does not force it back up mid-fight", blockedCalls[1])
CHECK(mageUtilFrame:IsShown() == false, "the cluster stays down until the fight ends")
-- Where the readout ACTUALLY sits, not where the cache says: the popout's
-- deferral used to leave the segment's stamp unwritten, and the stale stamp
-- then matched the restored offset and skipped the move back
local function SegX()
    local p = hdr[1].icon.__points
    return p and #p > 0 and p[#p].x or nil
end
CHECK(SegX() == STRIPE_W_TEST,
    "the readout takes the whole left block while the cluster is missing",
    tostring(SegX()))

inCombat = false
Fire("PLAYER_REGEN_ENABLED")
CHECK(mageUtilFrame:IsShown() == true, "combat drops and the cluster comes back")
CHECK((SegX() or 0) > STRIPE_W_TEST,
    "and the readout stands aside for it again", tostring(SegX()))

-- ===========================================================================
-- The board never outgrows its own frame
-- ===========================================================================
-- A member arriving mid-fight moves the rows. The frame has to follow them,
-- or the bottom row hangs outside the border it is supposed to sit in — which
-- is exactly what a protected root could not do, and what put the secure
-- buttons on UIParent.
partyUp = {}
local realExists, realGUID = UnitExists, UnitGUID
function UnitExists(unit)
    if unit and unit:find("^party") then return partyUp[unit] == true end
    return realExists(unit)
end
function UnitGUID(unit)
    if unit and unit:find("^party") then return unit .. "-guid" end
    return realGUID(unit)
end

-- How far the lowest drawn row reaches below root's top edge
local function RowExtent()
    local low = 0
    for _, f in ipairs(allFrames) do
        if f.bar and f.spellIcon and f.__shown and f.__points and #f.__points > 0 then
            local p = f.__points[#f.__points]
            if p.rel == rootFrame and p.y then
                low = math.max(low, -p.y + (f.__h or 22))
            end
        end
    end
    return low
end

partyUp.party1, partyUp.party2 = true, true
inCombat = false
Fire("GROUP_ROSTER_UPDATE"); DrawOnce()
CHECK(RowExtent() > 0 and rootFrame.__h >= RowExtent(),
    "out of combat the frame contains the rows",
    RowExtent() .. " vs " .. tostring(rootFrame.__h))

inCombat = true
partyUp.party3 = true
blockedCalls = {}
Fire("GROUP_ROSTER_UPDATE"); DrawOnce()
CHECK(#blockedCalls == 0, "a member arriving mid-fight makes no protected call",
    blockedCalls[1])
CHECK(rootFrame.__h >= RowExtent(),
    "and the frame grows with them instead of leaving one hanging outside",
    RowExtent() .. " vs " .. tostring(rootFrame.__h))

-- Combat Only needs the board to come UP at the start of a fight: the one
-- transition a protected root could never make
inCombat = false
CommanderPartyFramesDB.CombatOnly = true
CommanderPartyFramesDB.HudLocked = true
DrawOnce()
CHECK(rootFrame:IsShown() == false, "Combat Only keeps the board down out of combat")
-- A sibling does not hide with its neighbour: the banner has to be told, or a
-- hidden board leaves its button cluster floating on screen
CHECK(mageUtilFrame:IsShown() == false, "the banner goes down with the board")
inCombat = true
blockedCalls = {}
DrawOnce()
CHECK(rootFrame:IsShown() == true, "and puts it up when the fight starts")
CHECK(#blockedCalls == 0, "without a protected call", blockedCalls[1])
-- The board is root's to raise; the button cluster is not. It holds secure
-- buttons, so its own Show is the one call combat still forbids — under
-- Combat Only the rows and the readout arrive with the fight and the buttons
-- follow when it ends. Better than the whole board staying down, which is
-- what a protected root gave.
CHECK(mageUtilFrame:IsShown() == false,
    "the button cluster cannot raise itself mid-fight — and does not try")
inCombat = false
Fire("PLAYER_REGEN_ENABLED")
CommanderPartyFramesDB.CombatOnly = false
CommanderPartyFramesDB.HudLocked = nil
inCombat = false
partyUp = {}
Fire("GROUP_ROSTER_UPDATE"); DrawOnce()

-- ===========================================================================
-- Bar texture: the Blizzard unit-frame look, swappable live
-- ===========================================================================
local FLAT_TEX = "Interface\\Buttons\\WHITE8X8"
local BLIZZ_TEX = "Interface\\TargetingFrame\\UI-StatusBar"
local function AnyRow()
    for _, f in ipairs(allFrames) do
        if f.bar and f.spellIcon and f.__shown then return f end
    end
end
CommanderPartyFramesDB.BarTexture = "FLAT"
Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
DrawOnce()
local texRow = AnyRow()
CHECK(texRow ~= nil, "a row is on the board to texture")
if texRow then
    CHECK(texRow.bar.__texture == FLAT_TEX, "flat is the solid block", texRow.bar.__texture)
    local barW = texRow._barW
    CommanderPartyFramesDB.BarTexture = "BLIZZARD"
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    DrawOnce()
    -- It rides the layout signature, so one setting change re-textures every
    -- pooled row rather than only the ones that happen to redraw
    CHECK(texRow.bar.__texture == BLIZZ_TEX, "switching re-textures the fill live",
        texRow.bar.__texture)
    CHECK(texRow.barBG.__texture == BLIZZ_TEX and texRow.wsBar.__texture == BLIZZ_TEX
        and texRow.healthBar.__texture == BLIZZ_TEX,
        "...with the track, the lockout drain and the mana strip")
    CHECK(texRow.shieldSegs[1].__texture == BLIZZ_TEX,
        "...and the shield segments riding the fill")
    CHECK(texRow.stripe.__texture == FLAT_TEX,
        "the state stripe stays flat — it is an accent, not a bar")
    CHECK(texRow._barW == barW, "and the swap costs the row no geometry",
        tostring(texRow._barW) .. " vs " .. tostring(barW))
    -- The board's own art: every style is a distinct file, and each one grooves
    -- the empty track instead of washing it flat black
    local seenArt = {}
    for _, style in ipairs({ "GLOSS", "BEVEL", "RIDGE", "GLASS" }) do
        CommanderPartyFramesDB.BarTexture = style
        Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
        DrawOnce()
        local art = texRow.bar.__texture
        CHECK(art ~= nil and art:find("Commander_PartyFrames", 1, true) ~= nil
            and seenArt[art] == nil, "bar style " .. style .. " has art of its own", art)
        seenArt[art] = style
        CHECK(texRow.barBG.__texture ~= art and texRow.barBG.__texture:find("BarSocket", 1, true),
            "...and an empty track cut for it, not the fill washed black",
            texRow.barBG.__texture)
        CHECK(texRow.healthBar.__texture == art and texRow.shieldSegs[1].__texture == art,
            "...worn by the mana strip and the shield segments too")
        CHECK(texRow.stripe.__texture == FLAT_TEX, "...while the state stripe stays flat")
        CHECK(texRow._barW == barW, "...and none of it costs the row geometry")
    end

    CommanderPartyFramesDB.BarTexture = "FLAT"
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    DrawOnce()
    CHECK(texRow.bar.__texture == FLAT_TEX, "and back again")
    CHECK(texRow.barBG.__texture == FLAT_TEX,
        "...track included: the plain styles keep the black wash they always had")

    -- Icon shading. Drawn by Commander_Events so a board icon and an icon on
    -- any other Commander board are cut the same way at the same setting.
    local shade = texRow.unitIcon.commanderDeboss
    CHECK(shade ~= nil, "row icons are shaded through the shared helper")
    if shade then
        CHECK(shade.__texture:find("Commander_Events", 1, true) ~= nil,
            "...from the suite's shared art, not a copy in this addon", shade.__texture)
        CHECK(shade.__texture:find("Soft", 1, true) ~= nil and shade.__shown == true,
            "...a shallow press by default, which is what a 14px icon wants",
            shade.__texture)

        CommanderPartyFramesDB.IconRecess = "CARVED"
        Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
        DrawOnce()
        CHECK(shade.__texture:find("Carved", 1, true) ~= nil,
            "changing the style swaps the art live", shade.__texture)

        -- The icons that matter here are built once in a constructor that never
        -- runs again, so the sweep -- not the row redraw -- is what reaches them
        local dispel = texRow.dispels[1].icon
        CHECK(dispel.commanderDeboss ~= nil
            and dispel.commanderDeboss.__texture == shade.__texture,
            "...including the ones no redraw would touch")

        -- An empty dispel slot is a HIDDEN icon, and shading has to go with it.
        -- Shipped without this and the board grew five lit rectangles hanging
        -- off the right of every row (2026-08-05).
        dispel:Hide()
        CHECK(dispel.commanderDeboss.__shown == false,
            "hiding an icon takes its shading down with it")
        dispel:Show()
        CHECK(dispel.commanderDeboss.__shown == true, "and showing it brings it back")
        dispel:SetShown(false)
        CHECK(dispel.commanderDeboss.__shown == false, "SetShown counts too")
        dispel:Show()

        -- ...and a style applied while an icon is hidden must not light it up
        dispel:Hide()
        CommanderPartyFramesDB.IconRecess = "DEEP"
        Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
        DrawOnce()
        CHECK(dispel.commanderDeboss.__shown == false,
            "restyling a hidden icon leaves it hidden")
        dispel:Show()

        CommanderPartyFramesDB.IconRecess = "OFF"
        Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
        DrawOnce()
        CHECK(shade.__shown == false, "Flat takes the shading back off")
        CommanderPartyFramesDB.IconRecess = "SOFT"
        Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
        DrawOnce()
        CHECK(shade.__shown == true, "and picking a style again brings it back")

        -- Manual mode, for icons an addon does NOT own (Blizzard's action
        -- button art): no visibility wrapping, because Blizzard's own code
        -- running an addon closure is how an action button gets tainted. The
        -- caller owns the returned texture instead.
        local blizzLike = texRow:CreateTexture(nil, "ARTWORK")
        local rawHide = blizzLike.Hide
        local manual = Commander.DebossIcon(blizzLike, "SOFT", false, true)
        CHECK(manual ~= nil, "manual mode still builds the shading")
        CHECK(blizzLike.Hide == rawHide,
            "...but leaves the icon's own methods alone")
        blizzLike:Hide()
        CHECK(manual.__shown == true,
            "...so hiding the icon does not touch it: the caller owns that")
    end
end

-- ===========================================================================
-- Sweep edge: the spark rides durations, never cooldowns
-- ===========================================================================
-- The frames this option touches are built in the row constructor, which runs
-- once per pooled row and never again. So the question worth asking is not
-- whether the flag gets set, but whether it reaches rows that already exist
-- AND rows built after the toggle — the two halves a constructor-only setting
-- gets wrong in opposite directions.
do
    -- row.swipe and row.inShieldCd joined this family when the ally-buff
    -- trackers took those two slots: Mark of the Wild, Thorns and Arcane
    -- Intellect are aura durations like any hot, so they follow the same rule.
    local function AuraSweeps(row)
        local out = { row.swipe, row.inShieldCd }
        for i = 1, #row.strip do out[#out + 1] = row.strip[i].cd end
        for i = 1, #row.dispels do out[#out + 1] = row.dispels[i].cd end
        return out
    end
    local function AllRows()
        local out = {}
        for _, f in ipairs(allFrames) do
            if f.strip and f.dispels and f.swipe then out[#out + 1] = f end
        end
        return out
    end
    local function EdgeOn(row, want)
        for _, cd in ipairs(AuraSweeps(row)) do
            if cd.__drawEdge ~= want then return false end
        end
        return true
    end

    local rows = AllRows()
    CHECK(#rows > 0, "the board has pooled rows to check", #rows)
    local function EverySweep(want)
        for _, row in ipairs(rows) do
            if not EdgeOn(row, want) then return false end
        end
        return true
    end
    CHECK(EverySweep(false), "the spark ships off")

    CommanderPartyFramesDB.SweepEdge = true
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    DrawOnce()
    CHECK(EverySweep(true), "turning it on reaches every pooled row's aura timers")

    -- The ability strip is the line this option is drawn against: its sweeps
    -- are cooldowns, and a spark chasing six of them under every row is motion
    -- where the only question is ready or not
    local abilityCd
    for _, f in ipairs(allFrames) do
        if f.cells and f.cells[1] then abilityCd = f.cells[1].cd break end
    end
    CHECK(abilityCd ~= nil, "an ability strip exists to leave alone")
    CHECK(abilityCd and abilityCd.__drawEdge == false,
        "...and its cooldowns stay plain", abilityCd and tostring(abilityCd.__drawEdge))
    -- Direction is the other half of the same distinction, and the one that
    -- is invisible until you watch a buff run out: a DURATION drains (lit art
    -- is what is left), a COOLDOWN fills (lit art means ready). Stock Blizzard
    -- shading does the cooldown one, so every duration on this board has to
    -- ask for the reverse — otherwise a buff is at its brightest the instant
    -- before it falls off.
    for _, cd in ipairs(AuraSweeps(rows[1])) do
        CHECK(cd.__reverse == true,
            "every aura timer drains rather than fills", tostring(cd.__reverse))
    end
    CHECK(abilityCd and abilityCd.__reverse ~= true,
        "...and a real cooldown keeps the stock direction",
        abilityCd and tostring(abilityCd.__reverse))

    -- A row acquired after the toggle: built by a constructor that has no idea
    -- a setting ever changed, so it has to read the current one
    local known = {}
    for _, row in ipairs(rows) do known[row] = true end
    partyUp.party1, partyUp.party2, partyUp.party3, partyUp.party4 = true, true, true, true
    Fire("GROUP_ROSTER_UPDATE"); DrawOnce()
    local fresh
    for _, row in ipairs(AllRows()) do if not known[row] then fresh = row end end
    CHECK(fresh ~= nil, "a fifth teammate forces a row nothing had built yet")
    CHECK(fresh and EdgeOn(fresh, true), "and it is born wearing the spark")

    CommanderPartyFramesDB.SweepEdge = false
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    DrawOnce()
    CHECK(EverySweep(false) and (not fresh or EdgeOn(fresh, false)),
        "and turning it back off takes it off both")
    partyUp = {}
    Fire("GROUP_ROSTER_UPDATE"); DrawOnce()
end

CheckSectionSizing()
CheckRowFit()
CheckBuffStrip()
CheckAbilityScope()
CheckClickMatrix()
CheckBuffGrid()
CheckBlessAssign()
CheckShadowRead()
CheckBuffTargets()
CheckPets()
CheckPowerStrip()
CheckForecast()
CheckHealPredict()
CheckOverheal()
CheckCombatMarks()
CheckBGMarks()
CheckMarkGrid()
CheckGhosts()


CheckNearby()
CheckBlizzToggle()
CheckDropdowns()
CheckHeaderStyle()

-- The settings-page anatomy diagram reads a blueprint laid out by the SAME
-- LayoutRow the live rows use. If the two ever disagree, the diagram lies
-- about where the width goes -- the one thing it exists to explain.
local function CheckBlueprint()
    local bp = CommanderPartyFrames_RowBlueprint and CommanderPartyFrames_RowBlueprint()
    CHECK(bp ~= nil, "blueprint: the scratch row lays out")
    if not bp then return end
    local live = _G.CommanderPartyFramesRow1
    if live and live._blueprint then
        CHECK(math.abs((live._barW or 0) - bp.barW) < 0.01, "blueprint: bar width matches the live row",
            string.format("%.1f vs %.1f", bp.barW, live._barW or -1))
        CHECK(#live._blueprint.slots == #bp.slots, "blueprint: same slot count as the live row",
            string.format("%d vs %d", #bp.slots, #live._blueprint.slots))
    end
    local leftEnd = bp.barX
    local lastSlot = bp.slots[#bp.slots]
    if lastSlot then
        CHECK(lastSlot.x + lastSlot.w <= leftEnd + 0.01, "blueprint: every left slot ends before the bar starts",
            string.format("%.1f > %.1f", lastSlot.x + lastSlot.w, leftEnd))
    end
    CHECK(bp.barX + bp.barW + bp.pad + bp.marks + bp.combat + bp.bg <= bp.width + 0.01,
        "blueprint: bar + reserved seats fit inside the frame",
        string.format("%.1f + %.1f + %d + %d + %d + %d vs %d", bp.barX, bp.barW, bp.pad, bp.marks, bp.combat, bp.bg, bp.width))
    -- The seats follow their settings
    local marksWas, combatWas = CommanderPartyFramesDB.ShowTargetMarks, CommanderPartyFramesDB.ShowCombat
    CommanderPartyFramesDB.ShowTargetMarks = false
    CommanderPartyFramesDB.ShowCombat = false
    local bare = CommanderPartyFrames_RowBlueprint()
    CHECK(bare.marks == 0 and bare.combat == 0, "blueprint: marks off -> no seats reserved")
    CHECK(bare.barW > bp.barW or (bp.marks + bp.combat == 0), "blueprint: ...and the bar takes the width",
        string.format("%.1f vs %.1f", bare.barW, bp.barW))
    CommanderPartyFramesDB.ShowTargetMarks, CommanderPartyFramesDB.ShowCombat = marksWas, combatWas
    CommanderPartyFrames_RowBlueprint()
    -- A scratch row never joins the board
    CHECK(_G.CommanderPartyFramesFrame ~= nil, "blueprint: the board frame still exists")
end
CheckBlueprint()
CheckProductionEmbed()

CHECK(#caughtErrors == 0, "no errors across the run", caughtErrors[1])

io.write(string.format("[%s] %d checks, %d failures\n", CLASS, checks, fails))
os.exit(fails == 0 and 0 or 1)
