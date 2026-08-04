-- Commander Party Frames banner smoke (luajit) — run per class:
--     luajit partyframes_banner_smoke.lua MAGE
--     luajit partyframes_banner_smoke.lua PRIEST
-- Verification for the 4.2.0
-- banner utilities: the split drink/eat consume button, inventory counters,
-- the mana gem control, the portals/teleports popout, and the all-class
-- bandage button (use, lockout, opening First Aid). Mock modeled on
-- Commander_Production/Harness.

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

local WidgetMT = {}
WidgetMT.__index = function(self, key)
    if type(key) ~= "string" then return nil end
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
        local fn = function(s, w, h) s.__w, s.__h = w, h end
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
    if key == "SetCooldown" then
        local fn = function(s, start, dur) s.__cdStart, s.__cdDur = start, dur end
        rawset(self, key, fn); return fn
    end
    if key == "SetVertexColor" then
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
        local fn = function(s) s.__shown = true end
        rawset(self, key, fn); return fn
    end
    if key == "Hide" then
        local fn = function(s) s.__shown = false end
        rawset(self, key, fn); return fn
    end
    if key == "SetShown" then
        local fn = function(s, shown) s.__shown = not not shown end
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
        local fn = function(s) local t = NewWidget("Texture"); t.__parent = s; return t end
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
function UnitHealth() return 100 end
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
}
local knownIds = {}
local function Learn(...) for _, id in ipairs({ ... }) do knownIds[id] = true end end
Learn(17, 6788, 139, 1459, 23028, 5504, 587, 3273,
    10054, 10053, 3552, 759,                       -- gems up to Ruby
    3561, 3562, 3565, 32271, 33690,                -- Alliance teleports
    10059, 11416, 11419, 32266, 33691,             -- Alliance portals
    27125, 27124)

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

-- Bandage is chassis: every supported class gets it
CHECK(bandage ~= nil, "bandage button exists")
CHECK(bandage:GetAttribute("macrotext1") ~= nil, "bandage is bound")

if CLASS ~= "MAGE" then
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
        if u then pcall(u, f, 10) end
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
CHECK(eat:find("item:22019", 1, true) ~= nil, "right-click eats food", eat)
CHECK(eat:find("item:8079", 1, true) == nil, "right-click does NOT reach for water-only ranks", eat)
-- The Manna Biscuit is food AND drink, so it heads both lists: pressing
-- left and right together on a biscuit-only mage must still do both
CHECK(drink:find("item:30703", 1, true) ~= nil and eat:find("item:30703", 1, true) ~= nil,
    "the dual-purpose biscuit is reachable from both clicks")
-- Lower ranks ride along so a click still works when the best runs dry
CHECK(drink:find("item:8079", 1, true) ~= nil, "drink falls through to the next water rank", drink)

-- Conjure unchanged: left water, right food
CHECK(conjure:GetAttribute("spell1") == "Conjure Water", "conjure left = water")
CHECK(conjure:GetAttribute("spell2") == "Conjure Food", "conjure right = food")

-- Gem: the macro's shape — [mod] conjures, [nomod] uses, right-click conjures
local gemUse = gem:GetAttribute("macrotext1")
CHECK(gemUse:find("[mod] Conjure Mana Ruby", 1, true) ~= nil,
    "gem: modifier conjures the best KNOWN rank (Emerald untrained)", gemUse)
CHECK(gemUse:find("/use [nomod] item:8008", 1, true) ~= nil, "gem: plain click uses the gem held", gemUse)
CHECK(gem:GetAttribute("macrotext2") == "/cast Conjure Mana Ruby", "gem: right-click conjures",
    gem:GetAttribute("macrotext2"))

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
        if u then pcall(u, f, 10) end
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
local hdr = _G.CommanderPartyFramesFrame.mageHdr
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

CHECK(#caughtErrors == 0, "no errors across the run", caughtErrors[1])

io.write(string.format("[%s] %d checks, %d failures\n", CLASS, checks, fails))
os.exit(fails == 0 and 0 or 1)
