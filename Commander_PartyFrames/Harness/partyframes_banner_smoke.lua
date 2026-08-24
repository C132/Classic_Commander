-- Commander Party Frames banner smoke (luajit) — run per SUPPORTED class
-- (a class with no layer has no board and no banner, so there is nothing
-- here to assert against):
--     luajit partyframes_banner_smoke.lua MAGE
--     luajit partyframes_banner_smoke.lua PRIEST
--     luajit partyframes_banner_smoke.lua DRUID
--     luajit partyframes_banner_smoke.lua PALADIN
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
function PlaySound() end
function PlaySoundFile() end
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

function UIDropDownMenu_Initialize() end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton() end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetSelectedValue() end
function UIDropDownMenu_SetText() end
function UIDropDownMenu_EnableDropDown() end
function UIDropDownMenu_DisableDropDown() end
function UIDropDownMenu_Refresh() end
function ToggleDropDownMenu() end
SlashCmdList = {}

-- --- Units -----------------------------------------------------------------
local CLASS = (arg and arg[1]) or "MAGE"
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
C_UnitAuras = {
    GetBuffDataByIndex = function(unit, i) return unit == "player" and playerBuffs[i] or nil end,
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

Fire("PLAYER_LOGIN")
Fire("BAG_UPDATE_DELAYED")

CHECK(#caughtErrors == 0, "login runs clean", caughtErrors[1])

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

    toggleBtn.__scripts.OnClick()
    CHECK(CommanderPartyFramesDB.HideBlizzardParty == true, "clicking sets the hide flag")
    CHECK(pf.__shown == false, "clicking hides the default party frames")
    CHECK(toggleBtn.slash.__shown == true, "the glyph is struck through while they are hidden")

    -- Blizzard re-shows the container on its own (roster changes, leaving
    -- Edit Mode); the guard has to put it straight back down
    pf:Show()
    pf.__scripts.OnShow(pf)
    CHECK(pf.__shown == false, "a Blizzard-side Show() is undone by the guard")

    toggleBtn.__scripts.OnClick()
    CHECK(CommanderPartyFramesDB.HideBlizzardParty == false, "clicking again clears the flag")
    CHECK(pf.__shown == true, "the default party frames come back")

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
            if f.strip and f.stripe then return f end
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
    CHECK(row.strip[3].count.__shown == true and row.strip[3].count.__text == 3,
        "Lifebloom carries its stack count", tostring(row.strip[3].count.__text))
    CHECK(row.strip[1].count.__shown == false,
        "a hot that does not stack carries no digit")
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
            if f.strip and f.stripe then return f end
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
            if f.strip and f.stripe then return f end
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
    CHECK(row.strip[2].count.__shown == true and row.strip[2].count.__text == 4,
        "...and carries its charge count", tostring(row.strip[2].count.__text))

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
    CheckBlizzToggle()
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
local chain = AnchorChain()
CHECK(#chain == 5, "all five buttons on the cluster by default", #chain)

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

-- A mage with no teleports trained gets no portal button
for _, id in ipairs({ 3561, 3562, 3565, 32271, 33690, 10059, 11416, 11419, 32266, 33691 }) do
    knownIds[id] = nil
end
Fire("SPELLS_CHANGED")
CHECK(portal.__shown == false, "portal button hides when nothing is trained")

-- ===========================================================================
-- Header alignment and the personal block (mage layer)
-- ===========================================================================
local STRIPE_W_TEST = 3 + 4   -- the engine's bare left inset (STRIPE_W + 4)
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

CheckBlizzToggle()

CHECK(#caughtErrors == 0, "no errors across the run", caughtErrors[1])

io.write(string.format("[%s] %d checks, %d failures\n", CLASS, checks, fails))
os.exit(fails == 0 and 0 or 1)
