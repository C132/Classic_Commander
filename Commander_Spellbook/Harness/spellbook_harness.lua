-- Commander Spellbook harness (luajit).
--
--   /opt/homebrew/bin/luajit Commander_Spellbook/Harness/spellbook_harness.lua
--
-- Loads the REAL shared framework (CommanderSettingsUI, CommanderGoButton,
-- CommanderEvents), the real Commander Rank Check and every Commander
-- Spellbook file over spellbook_mock.lua, on a fixtured level 40 human
-- priest whose class data is a hand-built slice of CommanderSpellbookData
-- (so these checks do not move when the generator does; data_smoke.lua
-- checks the generated file). Then drives: login, the takeover of the
-- stock book and its keys, the model's families and ranks, both groupings,
-- search, the Training view and Ignore, the window's rows and briefing, the
-- cast buttons — placed over what is on screen, clipped to the viewport,
-- never inside the window, withdrawn for combat — the Rank Check view with
-- Update and Keep, and the pet's abilities.
--
-- RENDER=<path.json> writes the painted window's rectangles for
-- render_svg.py (see README).

local ADDONS = "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local HERE = ADDONS .. "/Commander_Spellbook/Harness"

local M = dofile(HERE .. "/spellbook_mock.lua")

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end

-- ===========================================================================
-- The character: a level 40 human priest, Alliance, 30 gold
-- ===========================================================================

local me = { level = 40, money = 300000, faction = "Alliance" }
function UnitClass(unit) return "Priest", "PRIEST", 5 end
function UnitRace(unit) return "Human", "Human", 1 end
function UnitLevel(unit) return me.level end
function UnitFactionGroup(unit) return me.faction end
function UnitName(unit) return "Cptnbubbles" end
function UnitGUID(unit) return "Player-1-0001" end
function GetMoney() return me.money end
BOOKTYPE_SPELL, BOOKTYPE_PET = "spell", "pet"
PET_TYPE_DEMON = "Demon"
C_Map = { GetMapInfo = function(id) return { name = ({ [1453] = "Stormwind City", [1455] = "Ironforge" })[id] or "Zone" } end }

-- Spells: id -> { name, rank, icon }. Ranks are the subtext Rank Check reads.
local SPELLS = {}
local function Def(name, ids, first)
    for i, id in ipairs(ids) do
        SPELLS[id] = { name = name, rank = (#ids > 1) and ((first or 1) + i - 1) or nil, icon = "Interface\\Icons\\" .. name:gsub("[^%a]", "") }
    end
    return ids
end

local LESSER_HEAL = Def("Lesser Heal", { 2050, 2052, 2053 })
local FLASH_HEAL = Def("Flash Heal", { 2061, 9472, 9473, 9474, 10915, 10916, 10917, 25233, 25235 })
local SHIELD = Def("Power Word: Shield", { 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901, 25217, 25218 })
local FORT = Def("Power Word: Fortitude", { 1243, 1244, 1245, 2791, 10937, 10938, 25389 })
local SCREAM = Def("Psychic Scream", { 8122, 8124, 10888, 10890 })
local FADE = Def("Fade", { 586, 9578, 9579, 9592, 10941, 10942, 25429 })
local FLAY = Def("Mind Flay", { 15407, 17311, 17312, 17313, 17314, 18807, 25387 })
local PRAYER = Def("Desperate Prayer", { 13908, 19236, 19238, 19240 })
local STARSHARDS = Def("Starshards", { 10797, 19296, 19299 })
local SHADOWFORM = Def("Shadowform", { 15473 })
local SPIRIT_TAP = Def("Spirit Tap", { 15270 })
Def("Attack", { 6603 })
Def("Enchanting", { 7411 })
Def("Diplomacy", { 20599 })
Def("Daggers", { 1180 })
Def("Staves", { 227 })
Def("Firebolt", { 3110, 7799 })
Def("Blood Pact", { 6307 })

local function Train(ids, levels, costs, mask, from)
    local rows = {}
    for i = from or 1, #ids do rows[ids[i]] = { levels[i], costs[i], mask } end
    return rows
end

local function Merge(...)
    local out = {}
    for _, t in ipairs({ ... }) do for k, v in pairs(t) do out[k] = v end end
    return out
end

CommanderSpellbookData = {
    build = "fixture",
    classes = {
        PRIEST = {
            chains = {
                { role = "HEAL", src = "T", ranks = LESSER_HEAL },
                { role = "HEAL", src = "T", ranks = FLASH_HEAL },
                { role = "HEAL", src = "T", ranks = SHIELD },
                { role = "BUFF", src = "T", ranks = FORT },
                { role = "CONTROL", src = "T", ranks = SCREAM },
                { role = "DEFENSE", src = "T", ranks = FADE },
                { role = "DAMAGE", src = "L", ranks = FLAY },
                { role = "HEAL", src = "T", ranks = PRAYER },
                { role = "DAMAGE", src = "T", ranks = STARSHARDS },
                { role = "FORM", src = "L", ranks = SHADOWFORM },
                { role = "PASSIVE", src = "L", ranks = SPIRIT_TAP },
            },
            train = Merge(
                Train(LESSER_HEAL, { 1, 4, 10 }, { 10, 100, 300 }),
                Train(FLASH_HEAL, { 20, 26, 32, 38, 44, 50, 56, 61, 67 }, { 3000, 6000, 9000, 11000, 18000, 24000, 30000, 50000, 70000 }),
                Train(SHIELD, { 6, 12, 18, 24, 30, 36, 42, 48, 54, 60, 65, 70 }, { 100, 800, 2000, 4000, 8000, 10000, 16000, 22000, 28000, 34000, 40000, 50000 }),
                Train(FORT, { 1, 12, 24, 36, 48, 60, 70 }, { 10, 800, 4000, 10000, 22000, 34000, 50000 }),
                Train(SCREAM, { 14, 28, 36, 42 }, { 1200, 7000, 10000, 16000 }),
                Train(FADE, { 8, 16, 24, 32, 40, 48, 60 }, { 200, 1600, 4000, 9000, 14000, 22000, 34000 }),
                Train(FLAY, { 20, 28, 36, 44, 52, 60, 68 }, { 0, 6000, 10000, 18000, 26000, 34000, 46000 }, nil, 2),
                Train(PRAYER, { 10, 18, 26, 34 }, { 100, 2000, 6000, 9000 }, 1 + 4),
                Train(STARSHARDS, { 10, 18, 26 }, { 100, 2000, 6000 }, 8)
            ),
        },
    },
    general = { [6603] = "GENERAL", [7411] = "PROFESSION", [20599] = "RACIAL" },
    weapons = {
        [1180] = { level = 1, cost = 1000, classMask = 1 + 8 + 16 + 64 + 128 + 256,
            trainers = { Alliance = { { npc = 11867, name = "Woo Ping", map = 1453, x = 0.572, y = 0.571 },
                                      { npc = 11865, name = "Buliwyf Stonehand", map = 1455, x = 0.613, y = 0.892 } },
                         Horde = {} } },
        [227] = { level = 1, cost = 1000, classMask = 16 + 64 + 128 + 256 + 1024, trainers = { Alliance = {}, Horde = {} } },
    },
}

-- What this priest knows. Lower ranks are known (IsPlayerSpell), but with
-- "Show all spell ranks" unticked the book lists only the highest.
local known = {}
local function Know(ids, upto) for i = 1, upto do known[ids[i]] = true end end
Know(LESSER_HEAL, 3)
Know(FLASH_HEAL, 2)
Know(SHIELD, 6)
Know(FORT, 3)
Know(SCREAM, 2)
Know(FADE, 4)
Know(PRAYER, 1)
Know(SPIRIT_TAP, 1)
known[6603], known[7411], known[20599], known[227] = true, true, true, true

local PASSIVE = { [20599] = true, [15270] = true }

-- The book: tabs of (id) in order, highest ranks only
local function Highest(ids)
    local best
    for _, id in ipairs(ids) do if known[id] then best = id end end
    return best
end

local TABS
local function BuildBook()
    TABS = {
        { name = "General", ids = { 6603, 7411, 20599 } },
        { name = "Discipline", ids = { Highest(SHIELD), Highest(FORT) } },
        { name = "Holy", ids = { Highest(LESSER_HEAL), Highest(FLASH_HEAL), Highest(PRAYER) } },
        { name = "Shadow", ids = { Highest(SCREAM), Highest(FADE), Highest(SPIRIT_TAP) } },
    }
    for _, ids in ipairs({ FLAY }) do
        local h = Highest(ids)
        if h then table.insert(TABS[4].ids, h) end
    end
end
BuildBook()

local function SlotSpell(slot)
    local offset = 0
    for _, tab in ipairs(TABS) do
        if slot <= offset + #tab.ids then return tab.ids[slot - offset] end
        offset = offset + #tab.ids
    end
    return nil
end

function GetNumSpellTabs() return #TABS end
function GetSpellTabInfo(tab)
    local offset = 0
    for i = 1, tab - 1 do offset = offset + #TABS[i].ids end
    return TABS[tab].name, "Interface\\Icons\\Tab" .. tab, offset, #TABS[tab].ids
end

local pet = { spells = {} }
function HasPetSpells()
    if #pet.spells == 0 then return nil end
    return #pet.spells, "DEMON"
end
function PetHasSpellbook() return #pet.spells > 0 end

function GetSpellBookItemInfo(slot, book)
    local id = (book == "pet") and pet.spells[slot] or SlotSpell(slot)
    if not id then return nil end
    return (book == "pet") and "PETACTION" or "SPELL", id
end
function GetSpellBookItemName(slot, book)
    local id = (book == "pet") and pet.spells[slot] or SlotSpell(slot)
    if not id then return nil end
    return SPELLS[id].name, "", id
end
function IsPassiveSpell(slot, book)
    local id = (book == "pet") and pet.spells[slot] or SlotSpell(slot)
    return id and PASSIVE[id] or false
end
function GetSpellTexture(a, book)
    local id = a
    if book then id = (book == "pet") and pet.spells[a] or SlotSpell(a) end
    return id and SPELLS[id] and SPELLS[id].icon or nil
end
function GetSpellAutocast(slot, book)
    if book == "pet" and pet.spells[slot] == 3110 then return true, true end
    return false, false
end
-- Only the C_SpellBook calls: IsPlayerSpell and IsSpellKnown are
-- deprecation shims on this client, absent unless loadDeprecationFallbacks
C_SpellBook = {
    IsSpellKnown = function(id) return known[id] == true end,
    IsSpellInSpellBook = function(id) return known[id] == true end,
}
IsPlayerSpell, IsSpellKnown = nil, nil
local links = {}
function ChatEdit_InsertLink(link) links[#links + 1] = link return true end
PET_ACTION_FOLLOW = "Follow"
local goes = {}
CommanderOrders = {
    GoTo = function(target, opts) goes[#goes + 1] = { target = target, opts = opts } return 1 end,
    IsAvailable = function() return true end,
    IsGoing = function() return false end,
    Reason = function(why) return tostring(why) end,
    PlaceFor = function(target) return target end,
}
function GetSpellInfo(id)
    local s = SPELLS[id]
    if not s then return nil end
    return s.name, nil, s.icon, 0, 0, 0, id
end
function GetSpellLink(id) return SPELLS[id] and ("|cff71d5ff|Hspell:" .. id .. "|h[" .. SPELLS[id].name .. "]|h|r") end
-- Cooldowns by id: { start, duration }; none unless a check puts one there
local cooldowns = {}
-- What each rank costs and how long it casts (ms), where the fixture says
local powerCosts, castTimes = {}, {}
C_Spell = {
    GetSpellPowerCost = function(id)
        local c = powerCosts[id]
        if not c then return nil end
        return { { type = 0, name = c.name or "MANA", cost = c.cost or 0, minCost = c.cost or 0,
            costPercent = c.percent or 0, costPerSec = 0, requiredAuraID = 0, hasRequiredAura = false } }
    end,
    GetSpellInfo = function(id)
        if not SPELLS[id] and not castTimes[id] then return nil end
        return { name = SPELLS[id] and SPELLS[id].name or "?", iconID = 1, originalIconID = 1,
            castTime = castTimes[id] or 0, minRange = 0, maxRange = 40, spellID = id }
    end,
    GetSpellCooldown = function(id)
        local c = cooldowns[id]
        if c then return { startTime = c[1], duration = c[2], isEnabled = true, modRate = 1 } end
        return { startTime = 0, duration = 0, isEnabled = true, modRate = 1 }
    end,
    GetSpellName = function(id) return SPELLS[id] and SPELLS[id].name end,
    GetSpellTexture = function(id) return SPELLS[id] and SPELLS[id].icon end,
    GetSpellSubtext = function(id)
        local s = SPELLS[id]
        if not s or not s.rank then return "" end
        return "Rank " .. s.rank
    end,
    IsSpellDataCached = function() return true end,
}
local SpellMixin = {}
SpellMixin.__index = SpellMixin
function SpellMixin:IsSpellEmpty() return self.spellID == nil end
function SpellMixin:IsSpellDataCached() return true end
function SpellMixin:ContinueOnSpellLoad(cb) cb() end
Spell = { CreateFromSpellID = function(_, id) return setmetatable({ spellID = id }, SpellMixin) end }

-- Bars, macros, cursor
local bars = { [1] = 2061, [2] = 6066, [3] = 586, [4] = 9472 }
function GetActionInfo(slot) if bars[slot] then return "spell", bars[slot], "spell" end return nil end
local macros = { [1] = { name = "Heal", body = "/cast [@mouseover] Lesser Heal(Rank 1)" } }
MAX_ACCOUNT_MACROS, MAX_CHARACTER_MACROS = 120, 18
function GetMacroInfo(i) local m = macros[i] if m then return m.name, "icon", m.body end end
function GetMacroIndexByName(name) for i, m in pairs(macros) do if m.name == name then return i end end return 0 end
function EditMacro(i, name, icon, body) macros[i] = { name = name, body = body } end
local cursor
local pickups = {}
function GetCursorInfo() if cursor then return cursor[1], cursor[2], nil, cursor[2] end return nil end
function ClearCursor() cursor = nil end
function PickupSpell(id) pickups[#pickups + 1] = "spell:" .. id cursor = { "spell", id } end
function PickupSpellBookItem(slot, book) pickups[#pickups + 1] = book .. ":" .. slot cursor = { "spell", slot } end
function PlaceAction(slot) local old = bars[slot] bars[slot] = cursor and cursor[2] cursor = old and { "spell", old } or nil end

-- Bindings
local bindings = { TOGGLESPELLBOOK = { "P" }, TOGGLEPETBOOK = { "SHIFT-P" } }
function GetBindingKey(command) return unpack(bindings[command] or {}) end
local overrides = {}
function SetOverrideBinding(owner, priority, key, command) overrides[key] = command end
function ClearOverrideBindings(owner) overrides = {} end

-- The stock spellbook, enough of it to be shown and handed over
SpellBookFrame = CreateFrame("Frame", "SpellBookFrame", UIParent)
SpellBookFrame:Hide()
SpellBookFrame.bookType = "spell"
local hiddenPanels = {}
function HideUIPanel(f) hiddenPanels[#hiddenPanels + 1] = f f:Hide() end
-- Confirmation popups: recorded, accepted by hand
StaticPopupDialogs = {}
local popups = {}
local hiddenPopups = {}
function StaticPopup_Show(name, a1, a2, data) popups[#popups + 1] = { name = name, text = a1, data = data } end
function StaticPopup_Hide(name) hiddenPopups[#hiddenPopups + 1] = name end
function ShowUIPanel(f) f:Show() end

-- ===========================================================================
-- Load
-- ===========================================================================

local function Load(path)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    chunk()
end

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderGoButton.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
Load(ADDONS .. "/Commander_RankCheck/CommanderRankCheckDB.lua")
Load(ADDONS .. "/Commander_RankCheck/CommanderRankCheck.lua")
Load(ADDONS .. "/Commander_Spellbook/CommanderSpellbookDB.lua")
Load(ADDONS .. "/Commander_Spellbook/CommanderSpellbookModel.lua")
Load(ADDONS .. "/Commander_Spellbook/CommanderSpellbookTraining.lua")
Load(ADDONS .. "/Commander_Spellbook/CommanderSpellbookTrainer.lua")
Load(ADDONS .. "/Commander_Spellbook/CommanderSpellbookSecure.lua")
Load(ADDONS .. "/Commander_Spellbook/CommanderSpellbookUI.lua")

local S = CommanderSpellbook
local R = CommanderRankCheck

M.Fire("ADDON_LOADED", "Commander_RankCheck")
M.Fire("ADDON_LOADED", "Commander_Spellbook")
CommanderRankCheckDB.RunOnLogin = false
M.Fire("PLAYER_LOGIN")
M.Flush(1)

-- ===========================================================================
-- A. Login: the settings page, the takeover, the keys
-- ===========================================================================

local page
for _, cat in ipairs(M.categories) do if cat.__title == "Spellbook" then page = cat end end
CHECK(page ~= nil, "A1 the Spellbook settings page is registered")
CHECK(overrides["P"] == "COMMANDERSPELLBOOK_TOGGLE", "A2 the spellbook key opens this window", overrides["P"])
CHECK(overrides["SHIFT-P"] == "COMMANDERSPELLBOOK_PETBOOK", "A2 the pet book key opens the pet's foldout", overrides["SHIFT-P"])
CHECK(SlashCmdList and (SlashCmdList.COMMANDERUI_SPELLBOOK ~= nil), "A3 /csb is registered")
CHECK(not (CommanderRankCheckButton and CommanderRankCheckButton:IsShown()),
    "A4 Rank Check's button in Blizzard's book stands down while this book takes over")

-- ===========================================================================
-- B. The model
-- ===========================================================================

local book = S.Scan()
local function Family(name)
    for _, f in ipairs(book.list) do if f.name == name then return f end end
    return nil
end

local flash = Family("Flash Heal")
CHECK(flash and #flash.ranks == 9, "B1 one family per spell carries every rank of its chain", flash and #flash.ranks)
CHECK(flash and flash.highest and flash.highest.id == 9472 and flash.highest.rank == 2,
    "B1 the highest known rank and its number come from the chain", flash and flash.highest and flash.highest.rank)
CHECK(flash and flash.ranks[1].known and not flash.ranks[3].known, "B2 lower ranks the book does not list are known by IsPlayerSpell")
CHECK(flash and flash.trainableNow == 2, "B3 ranks 3 and 4 both trainable now (one visit teaches both)", flash and flash.trainableNow)
CHECK(flash and flash.nextRank and flash.nextRank.id == 9473, "B3 the next rank to train is rank 3")
local fade = Family("Fade")
CHECK(fade and fade.trainableNow == 1 and fade.ranks[5].now and not fade.ranks[6].now,
    "B4 a rank above your level is not trainable now", fade and fade.trainableNow)
local prayer = Family("Desperate Prayer")
CHECK(prayer and prayer.ranks[2].now, "B5 a race-masked rank this race may learn is trainable")
CHECK(Family("Starshards") == nil, "B5 another race's spell is not in the book")
CHECK(Family("Attack").role == "GENERAL" and Family("Enchanting").role == "PROFESSION"
    and Family("Diplomacy").role == "RACIAL", "B6 the General tab splits into General, Professions and Racial")
CHECK(Family("Spirit Tap").role == "PASSIVE", "B6 a passive class spell files under Passives")
CHECK(Family("Psychic Scream").role == "CONTROL" and Family("Power Word: Fortitude").role == "BUFF",
    "B6 the class trees file by role")

-- A book spell the data does not chain, named like a chain (the paladin's
-- starting Seal of Righteousness, 20154, before the 21084 its chain starts
-- from) files with that chain, not as an "Other" spell of its own
SPELLS[20154] = { name = "Power Word: Shield", rank = 1, icon = "Interface\\Icons\\PowerWordShield" }
table.insert(TABS[2].ids, 20154)
local aliased = S.Scan()
local shields = 0
for _, f in ipairs(aliased.list) do if f.name == "Power Word: Shield" then shields = shields + 1 end end
CHECK(shields == 1 and aliased.families[17] and aliased.families[17].role == "HEAL",
    "B6 a spell the data does not chain joins the chain of its name", shields)
table.remove(TABS[2].ids)
SPELLS[20154] = nil

local rows, shown, total = S.BuildBookRows(book, { groupBy = "ROLE", passives = true, collapsed = {} })
local order = {}
for _, row in ipairs(rows) do if row.header then order[#order + 1] = row.header.key end end
CHECK(table.concat(order, ",") == "HEAL,CONTROL,DEFENSE,BUFF,RACIAL,PROFESSION,GENERAL,PASSIVE",
    "B7 role foldouts in role order", table.concat(order, ","))
CHECK(total == #book.list, "B7 every family is counted", total)
local passiveOpen = false
for i, row in ipairs(rows) do
    if row.header and row.header.key == "PASSIVE" then passiveOpen = not row.collapsed end
end
CHECK(not passiveOpen, "B8 Passives starts folded")

rows = S.BuildBookRows(book, { groupBy = "TREE", passives = true, collapsed = {} })
order = {}
for _, row in ipairs(rows) do if row.header then order[#order + 1] = row.header.label end end
CHECK(table.concat(order, ",") == "General,Discipline,Holy,Shadow", "B9 talent-tree grouping is the stock book's tabs",
    table.concat(order, ","))

local unbook = S.Scan({ unlearned = true })
rows = S.BuildBookRows(unbook, { groupBy = "ROLE", passives = true, search = "mind", collapsed = { ["ROLE:DAMAGE"] = true } })
local found
for _, row in ipairs(rows) do if row.family and row.family.name == "Mind Flay" then found = row.family end end
CHECK(found and found.unlearned, "B10 a search finds a spell not learned yet, and opens its folded group")
rows = S.BuildBookRows(unbook, { groupBy = "ROLE", passives = true, search = "star", collapsed = {} })
local starshards = false
for _, row in ipairs(rows) do if row.family and row.family.name == "Starshards" then starshards = true end end
CHECK(not starshards, "B10 a search never offers another race's spell")
rows = S.BuildBookRows(book, { groupBy = "ROLE", passives = true, search = "heal", collapsed = {} })
local names = {}
for _, row in ipairs(rows) do if row.family then names[#names + 1] = row.family.name end end
CHECK(#names == 4, "B11 a search matching a group's name lists the group", table.concat(names, ","))

-- ===========================================================================
-- C. Training (our What's Training?)
-- ===========================================================================

local training = S.Training(S.Scan(), { soon = 2 })
local function Ids(key)
    local out = {}
    for _, item in ipairs((training.groups[key] or {}).items or {}) do out[#out + 1] = item.id end
    table.sort(out)
    return table.concat(out, ",")
end
CHECK(Ids("NOW") == "2791,9473,9474,10888,10941,19236,19238,19240", "C1 Train Now: every rank due, chained ranks included", Ids("NOW"))
CHECK(training.nowCost == 10000 + 9000 + 11000 + 10000 + 14000 + 2000 + 6000 + 9000, "C1 the Train Now total", training.nowCost)
CHECK(Ids("WEAPON") == "1180", "C2 a weapon skill the class can learn and does not know", Ids("WEAPON"))
CHECK(Ids("SOON") == "10890,10898", "C3 Coming Up is the next two levels", Ids("SOON"))
CHECK(Ids("TALENT"):find("17311") and not Ids("NOW"):find("17311"), "C4 ranks of an untaken talent wait under Needs a Talent")
CHECK(not Ids("LATER"):find("10797") and not Ids("NOW"):find("19296"), "C5 another race's ranks are never listed")
S.SetIgnored(9474, true)
training = S.Training(S.Scan(), { soon = 2 })
CHECK(Ids("IGNORED") == "9474" and not Ids("NOW"):find("9474"), "C6 Ignore moves a rank out of Train Now", Ids("IGNORED"))
S.SetIgnored(9474, false)
local trows = S.BuildTrainRows(S.Training(S.Scan(), { soon = 2 }), { collapsed = {} })
local tkeys = {}
for _, row in ipairs(trows) do if row.header then tkeys[#tkeys + 1] = row.header.key .. (row.collapsed and "-" or "+") end end
CHECK(table.concat(tkeys, ",") == "NOW+,WEAPON-,SOON+,TALENT-,LATER-",
    "C7 Training foldouts, Weapon Skills and the far end folded (D18)", table.concat(tkeys, ","))

-- ===========================================================================
-- D. The window
-- ===========================================================================

CommanderSpellbookDB.Filter = "BOOK"
CommanderSpellbook_Toggle()
M.Flush(1)
local frame = CommanderSpellbookFrame
CHECK(frame and frame:IsShown(), "D1 the window opens")
CHECK(not frame:IsProtected(), "D1 the window is never protected (cast buttons are siblings)")
local navRows = S._NavRows()
local painted = 0
for _, row in ipairs(navRows) do if row:IsShown() then painted = painted + 1 end end
CHECK(painted >= 10, "D2 rows painted", painted)
local selected = S._Selected()
CHECK(selected and selected.name == "Desperate Prayer", "D3 the first spell is selected", selected and selected.name)
for _, row in ipairs(navRows) do
    if row:IsShown() and row.family and row.family.name == "Flash Heal" then M.RunScript(row, "OnClick", "LeftButton") end
end
M.Flush(1)
selected = S._Selected()
CHECK(selected and selected.name == "Flash Heal", "D3 a click selects a spell", selected and selected.name)

local castPool = S.Cast._Pool()
local placed = S.Cast.Shown()
CHECK(placed > 0, "D4 cast buttons placed over the icons on screen", placed)
local navScroll = CommanderSpellbookNavScroll
local scrollRect = M.Resolve(navScroll)
local outside = 0
for _, b in ipairs(castPool) do
    if b:IsShown() then
        CHECK(b:GetParent() == UIParent, "D5 a cast button is parented to UIParent")
        local t = b.target
        if t and t.clip == navScroll then
            local r = M.Resolve(t.region)
            if r.b + r.h > scrollRect.b + scrollRect.h + 0.5 or r.b < scrollRect.b - 0.5 then outside = outside + 1 end
        end
    end
end
CHECK(outside == 0, "D5 no cast button over a row scrolled out of view", outside)
local flashButton
for _, b in ipairs(castPool) do
    if b:IsShown() and b:GetAttribute("spell") == 9472 then flashButton = b end
end
CHECK(flashButton ~= nil, "D6 Flash Heal's icon casts the highest rank you know, by id")
CHECK(flashButton and flashButton:GetAttribute("useOnKeyDown") == false, "D6 casts on the mouse's up stroke (a drag never casts)")
CHECK(flashButton and flashButton:GetAttribute("type2") == "", "D6 right-click on a player spell casts nothing")
local spiritTap = false
for _, b in ipairs(castPool) do
    if b:IsShown() and b:GetAttribute("spell") == 15270 then spiritTap = true end
end
CHECK(not spiritTap, "D7 a passive spell gets no cast button")

-- The ladder: one line per rank, the known chips cast their own rank
local ladderCasts = {}
for _, b in ipairs(castPool) do
    if b:IsShown() and b.target and b.target.clip == CommanderSpellbookDetailScroll then
        ladderCasts[#ladderCasts + 1] = b:GetAttribute("spell")
    end
end
table.sort(ladderCasts)
CHECK(table.concat(ladderCasts, ",") == "2061,9472,9472", "D8 the briefing casts each known rank (chips and the big icon)",
    table.concat(ladderCasts, ","))

-- The Cast button: the secure button pinned over it casts the briefed rank
local castOverButton
for _, b in ipairs(castPool) do
    if b:IsShown() and b.target and b.target.region == frame.castBtn then castOverButton = b end
end
CHECK(castOverButton and castOverButton:GetAttribute("spell") == 9472, "D11 the Cast button casts the briefed rank",
    castOverButton and castOverButton:GetAttribute("spell"))
CHECK(castOverButton and castOverButton:GetAttribute("shift-type1") == "", "D12 shift-click casts nothing...")
M.shift = true
if castOverButton then M.RunScript(castOverButton, "OnClick", "LeftButton") end
M.shift = false
CHECK(links[#links] and links[#links]:find("Hspell:9472"), "D12 ...and links the rank instead", links[#links])

-- Folding the group the selection is in keeps the briefing on it
for _, row in ipairs(navRows) do
    if row:IsShown() and row.foldKey == "ROLE:HEAL" then M.RunScript(row, "OnClick", "LeftButton") end
end
CHECK(S._Selected() and S._Selected().name == "Flash Heal", "D13 folding its group does not move the selection",
    S._Selected() and S._Selected().name)
for _, row in ipairs(S._NavRows()) do
    if row:IsShown() and row.foldKey == "ROLE:HEAL" then M.RunScript(row, "OnClick", "LeftButton") end
end

-- Dragging a row puts the highest rank on the cursor; a ladder line its own
pickups, cursor = {}, nil
for _, row in ipairs(navRows) do
    if row.family and row.family.name == "Flash Heal" then M.RunScript(row, "OnDragStart") end
end
CHECK(pickups[1] == "spell:9472", "D9 dragging a row picks up the highest rank", pickups[1])
cursor = nil

-- Scrolling re-places the buttons for what is now on screen: the rows that
-- went up out of view lose theirs, and none is left over the toolbar
local before = S.Cast.Shown()
navScroll:SetVerticalScroll(120)
local after = S.Cast.Shown()
outside = 0
for _, b in ipairs(castPool) do
    local t = b:IsShown() and b.target
    if t and t.clip == navScroll then
        local r = M.Resolve(t.region)
        if r.b + r.h > scrollRect.b + scrollRect.h + 0.5 or r.b < scrollRect.b - 0.5 then outside = outside + 1 end
        local pinned = M.Resolve(b)
        if math.abs(pinned.l - r.l) > 0.01 or math.abs((pinned.b + pinned.h) - (r.b + r.h)) > 0.01 then
            outside = outside + 1
        end
    end
end
CHECK(after < before and outside == 0, "D10 a scroll re-places the cast buttons over what is still in view",
    before .. " -> " .. after .. ", " .. outside .. " misplaced")
navScroll:SetVerticalScroll(0)

-- ===========================================================================
-- E. Combat
-- ===========================================================================

M.blockedCalls = {}
M.Fire("PLAYER_REGEN_DISABLED")
M.combat = true
CHECK(S.Cast.Shown() == 0, "E1 the cast buttons are put away as combat starts")
S._SetSearch("fade")
navScroll:SetVerticalScroll(40)
S.Refresh()
CommanderSpellbook_Toggle()
CommanderSpellbook_Toggle()
M.Flush(1)
CHECK(#M.blockedCalls == 0, "E2 search, scroll, repaint, close and reopen in combat touch nothing protected", M.blockedCalls[1])
CHECK(frame.castBtn.__enabled == false, "E3 the Cast button greys out in combat")
local dragRow
for _, row in ipairs(navRows) do if row:IsShown() and row.family and row.family.name == "Fade" then dragRow = row end end
pickups = {}
if dragRow then M.RunScript(dragRow, "OnDragStart") end
CHECK(pickups[1] == "spell:9592", "E4 dragging still works in combat", pickups[1])
cursor = nil
M.combat = false
M.Fire("PLAYER_REGEN_ENABLED")
M.Flush(1)
CHECK(S.Cast.Shown() > 0, "E5 the cast buttons come back after combat")
S._SetSearch("")

-- ===========================================================================
-- F. The stock book handed over
-- ===========================================================================

CommanderSpellbook_Hide()
hiddenPanels = {}
SpellBookFrame:Show()
CHECK(hiddenPanels[1] == SpellBookFrame and not SpellBookFrame:IsShown() and frame:IsShown(),
    "F1 the stock book is put away and this one opened")
-- A second micro-button click (the stock book shown again) closes it
SpellBookFrame:Show()
CHECK(not frame:IsShown() and not SpellBookFrame:IsShown(), "F1 the micro button toggles this window shut")
CommanderSpellbook_Hide()
M.combat = true
hiddenPanels = {}
SpellBookFrame:Hide()
SpellBookFrame:Show()
CHECK(#hiddenPanels == 0 and SpellBookFrame:IsShown(), "F2 in combat the stock book is left alone")
M.combat = false
SpellBookFrame:Hide()
CommanderSpellbookDB.TakeOverSpellbook = false
S.ApplyBindings()
CHECK(overrides["P"] == nil, "F3 takeover off gives the keys back")
SpellBookFrame:Show()
CHECK(SpellBookFrame:IsShown() and not frame:IsShown(), "F3 ...and the stock book stays")
SpellBookFrame:Hide()
CommanderSpellbookDB.TakeOverSpellbook = true
S.ApplyBindings()
CHECK(overrides["P"] == "COMMANDERSPELLBOOK_TOGGLE", "F4 back on, the keys come back")
bindings.TOGGLESPELLBOOK = { "P", "K" }
M.Fire("UPDATE_BINDINGS")
CHECK(overrides["K"] == "COMMANDERSPELLBOOK_TOGGLE", "F5 a rebind follows the player's keys")

-- ===========================================================================
-- G. Rank Check in the book
-- ===========================================================================

CommanderSpellbook_Open("CHECK")
M.Flush(2)
local result = S._Check()
CHECK(result and #result.issues == 3, "G1 the Rank Check view has the scan", result and #result.issues)
rows = S._Rows()
local groups = {}
for _, row in ipairs(rows) do if row.header then groups[#groups + 1] = row.header.key end end
CHECK(table.concat(groups, ",") == "STALE,CURRENT", "G2 out of date first, up to date below", table.concat(groups, ","))
local currentFolded = false
for _, row in ipairs(rows) do if row.header and row.header.key == "CURRENT" then currentFolded = row.collapsed end end
CHECK(currentFolded, "G2 Up to Date starts folded")
local _, _, ref = S._Selected()
CHECK(ref and ref.stale and ref.name, "G3 the first out-of-date reference is selected", ref and ref.key)
-- Update the Flash Heal slot from its row
for _, row in ipairs(S._Rows()) do
    if row.ref and row.ref.key == "bar:1" then ref = row.ref end
end
CHECK(R.Fix(ref) and bars[1] == 9472, "G4 Update puts Flash Heal rank 2 in slot 1", bars[1])
-- Keep the Fade slot: a down-ranked Fade on purpose
local fadeRef
S.RequestCheck()
M.Flush(2)
for _, r in ipairs(S._Check().refs) do if r.key == "bar:3" then fadeRef = r end end
R.Keep(fadeRef, true)
S.RequestCheck()
M.Flush(2)
groups = {}
for _, row in ipairs(S._Rows()) do if row.header then groups[#groups + 1] = row.header.key end end
CHECK(table.concat(groups, ",") == "STALE,KEPT,CURRENT", "G5 a kept reference has its own foldout", table.concat(groups, ","))
CHECK(#S._Check().issues == 1, "G5 one issue left (the macro)", #S._Check().issues)
-- The macro, through the Update All button
frame.fixAllBtn:Click()
M.Flush(2)
CHECK(macros[1].body == "/cast [@mouseover] Lesser Heal(Rank 3)", "G6 Update All rewrites the macro", macros[1].body)
CHECK(#S._Check().issues == 0, "G6 nothing left out of date")
CHECK((frame.footer.value.__text or ""):find("PASS"), "G7 the footer says PASS", frame.footer.value.__text)

-- The badges on the Spells view
CommanderSpellbook_Open("BOOK")
M.Flush(1)
local flashRow
for _, row in ipairs(S._NavRows()) do if row:IsShown() and row.family and row.family.name == "Flash Heal" then flashRow = row end end
CHECK(flashRow and (flashRow.badge.__text or ""):find("%+2"), "G8 a row shows how many ranks to train now",
    flashRow and flashRow.badge.__text)
bars[1] = 2061
S.RequestCheck()
M.Flush(2)
for _, row in ipairs(S._NavRows()) do if row:IsShown() and row.family and row.family.name == "Flash Heal" then flashRow = row end end
CHECK(flashRow and (flashRow.badge.__text or ""):find("!"), "G9 a row marks a bar still on an old rank",
    flashRow and flashRow.badge.__text)

-- ===========================================================================
-- H. The Training view in the window
-- ===========================================================================

CommanderSpellbook_Open("TRAIN")
M.Flush(1)
local _, item = S._Selected()
CHECK(item and item.status == "NOW", "H1 Training opens on the first thing to train", item and item.status)
CHECK((frame.countFS.__text or ""):find("8 now"), "H2 the toolbar counts Train Now", frame.countFS.__text)
CHECK(frame.ignoreBtn:IsShown() and frame.goBtn:IsShown(), "H3 Ignore and Go to Trainer are offered")
frame.ignoreBtn:Click()
CHECK(S.IsIgnored(item.id), "H4 Ignore ignores the selected rank")
local _, still = S._Selected()
CHECK(still and still.id == item.id and frame.ignoreBtn.__text == "Unignore",
    "H4 the ignored rank stays selected, so Unignore is one press away", frame.ignoreBtn.__text)
frame.ignoreBtn:Click()
CHECK(not S.IsIgnored(item.id), "H4 Unignore brings it back")
-- Weapon Skills starts folded (D18): unfold it as a player would
local weaponHeader, weaponListed = nil, false
for _, row in ipairs(S._NavRows()) do if row:IsShown() and row.foldKey == "TRAIN:WEAPON" then weaponHeader = row end end
for _, r in ipairs(S._Rows()) do if r.train and r.train.weapon then weaponListed = true end end
CHECK(weaponHeader ~= nil and not weaponListed, "H5 Weapon Skills starts folded, its header still there")
if weaponHeader then M.RunScript(weaponHeader, "OnClick", "LeftButton") end
local weaponRow
for _, row in ipairs(S._NavRows()) do if row:IsShown() and row.item and row.item.weapon then weaponRow = row end end
if weaponRow then M.RunScript(weaponRow, "OnClick", "LeftButton") end
local wfam = S._Selected()
CHECK(wfam and wfam.weapon and frame.goBtn._goLabel == "Go to Weapon Master", "H5 a weapon skill goes to a weapon master",
    frame.goBtn._goLabel)
M.ctrl = true
if weaponRow then M.RunScript(weaponRow, "OnClick", "RightButton") end
M.ctrl = false
CHECK(goes[1] and goes[1].target.alternatives and #goes[1].target.alternatives == 2 and goes[1].opts.source == "Spellbook",
    "H6 Ctrl+Right-click on a row goes straight to Orders (not the Go button's copy gesture)")
local spec = frame.goBtn._goOpts.spec(frame.goBtn)
CHECK(spec and spec.map == 1453 and #spec.alternatives == 2, "H5 ...every one of your faction, nearest chosen by Orders",
    spec and #spec.alternatives)

-- ===========================================================================
-- J. Cooldowns and the keyboard
-- ===========================================================================

CommanderSpellbook_Open("BOOK")
CommanderSpellbookDB.GroupBy = "ROLE"
S._SetSearch("")
M.Flush(1)
local function BookRow(name)
    for _, row in ipairs(S._NavRows()) do
        if row:IsShown() and row.family and not row.item and not row.ref and row.family.name == name then return row end
    end
end
-- Every rank of a spell shares its cooldown, as in game
for _, id in ipairs(FADE) do cooldowns[id] = { M.now - 5, 30 } end
cooldowns[Highest(FLASH_HEAL)] = { M.now - 0.5, 1.5 }
S.Refresh()
local fadeRow, flashRow = BookRow("Fade"), BookRow("Flash Heal")
local fadeCd = fadeRow and fadeRow.iconFrame.cooldown
CHECK(fadeCd and fadeCd:IsShown() and fadeCd.__cdDuration == 30 and fadeCd.__cdNoNumbers == true,
    "J1 a spell on its cooldown wears the swipe on its row, without numbers", fadeCd and fadeCd.__cdDuration)
local flashCd = flashRow and flashRow.iconFrame.cooldown
CHECK(not (flashCd and flashCd:IsShown()), "J2 the global cooldown alone draws nothing")
M.RunScript(fadeRow, "OnClick", "LeftButton")
local big = S._BigIcon()
CHECK(big and big.cooldown and big.cooldown:IsShown() and big.cooldown.__cdNoNumbers == false,
    "J3 the big icon wears it too, with its numbers")
local chips = 0
for _, target in ipairs(S._CastTargets()) do
    local region = target.region
    if region and region ~= big and region.cooldown and region.cooldown:IsShown() and region ~= BookRow("Fade").iconFrame
        and region ~= frame.castBtn then
        chips = chips + 1
    end
end
CHECK(chips == 4, "J3 ...and the chip of every rank you know (4 of Fade's 7), not the ones to train", chips)
M.Flush(1)
local realScan, scans = S.Scan, 0
S.Scan = function(...) scans = scans + 1 return realScan(...) end
for _, id in ipairs(FADE) do cooldowns[id] = nil end
cooldowns[Highest(FLASH_HEAL)] = nil
M.Fire("SPELL_UPDATE_COOLDOWN")
M.Flush(1)
S.Scan = realScan
fadeCd = BookRow("Fade").iconFrame.cooldown
CHECK(not fadeCd:IsShown() and not big.cooldown:IsShown(), "J4 the swipe goes when the cooldown ends")
CHECK(scans == 0, "J4 ...repainted without rescanning the book", scans)

-- The keyboard: Down and Up in the search box walk the list
CommanderSpellbookDB.ShowUnlearned = true
S.Refresh()
navScroll:SetVerticalScroll(0)
local box = CommanderSpellbookSearchBox
local function Press(key) M.RunScript(box, "OnArrowPressed", key) end
local order = {}
for _, item in ipairs(S._Rows()) do if item.family then order[#order + 1] = item.family.key end end
M.RunScript(BookRow(S._Rows()[2].family.name), "OnClick", "LeftButton")
CHECK(S._Selected().key == order[1], "J5 (the first spell selected)", S._Selected().key)
Press("DOWN")
CHECK(S._Selected().key == order[2], "J5 Down in the search box selects the next spell", S._Selected().key)
Press("UP")
CHECK(S._Selected().key == order[1], "J5 Up goes back", S._Selected().key)
Press("UP")
CHECK(S._Selected().key == order[1], "J5 Up on the first stays there", S._Selected().key)
Press("LEFT")
CHECK(S._Selected().key == order[1], "J5 Left and Right are the box's own (the caret)")
for _ = 1, #order + 3 do Press("DOWN") end
CHECK(S._Selected().key == order[#order], "J6 Down on the last stays there", S._Selected().key)
local selRow
for _, row in ipairs(S._NavRows()) do
    if row:IsShown() and row.family and row.family.key == order[#order] then selRow = row end
end
local rr, vr = M.Resolve(selRow), M.Resolve(navScroll)
CHECK(rawget(navScroll, "__child"):GetHeight() > vr.h, "J6 (the list is longer than its pane)", rawget(navScroll, "__child"):GetHeight() .. " vs " .. vr.h)
CHECK(navScroll:GetVerticalScroll() > 0 and rr.b >= vr.b - 0.5 and rr.b + rr.h <= vr.b + vr.h + 0.5,
    "J6 the list scrolls to keep the selection in view", navScroll:GetVerticalScroll())
for _ = 1, #order + 3 do Press("UP") end
rr = M.Resolve(BookRow(S._Rows()[2].family.name))
CHECK(S._Selected().key == order[1] and rr.b + rr.h <= vr.b + vr.h + 0.5 and rr.b >= vr.b - 0.5,
    "J6 ...back up as well", navScroll:GetVerticalScroll())
local placedOk = 0
for _, b in ipairs(castPool) do
    local t = b:IsShown() and b.target
    if t and t.clip == navScroll then
        local r = M.Resolve(t.region)
        local pinned = M.Resolve(b)
        if math.abs(pinned.l - r.l) > 0.01 or math.abs((pinned.b + pinned.h) - (r.b + r.h)) > 0.01 then
            placedOk = placedOk + 1
        end
    end
end
CHECK(placedOk == 0, "J6 the cast buttons follow the scroll the keys made", placedOk)
CommanderSpellbookDB.ShowUnlearned = false

-- On the Training view the keys walk the ranks to train
CommanderSpellbook_Open("TRAIN")
M.Flush(1)
local trainIds = {}
for _, item in ipairs(S._Rows()) do if item.train then trainIds[#trainIds + 1] = item.train.id end end
local function TrainIndex()
    local _, item = S._Selected()
    for i, id in ipairs(trainIds) do if item and item.id == id then return i end end
end
local startAt = TrainIndex()
Press("DOWN")
CHECK(startAt and TrainIndex() == math.min(startAt + 1, #trainIds), "J7 on Training, Down steps to the next rank",
    tostring(startAt) .. " -> " .. tostring(TrainIndex()))
CommanderSpellbook_Open("BOOK")
M.Flush(1)

-- ===========================================================================
-- L. What each rank costs and how long it casts
-- ===========================================================================

do
    for i, id in ipairs(LESSER_HEAL) do
        powerCosts[id] = { cost = ({ 30, 45, 75 })[i] }
        castTimes[id] = ({ 1500, 2000, 2500 })[i]
    end
    for i, id in ipairs(FADE) do powerCosts[id] = { cost = 45 + 15 * i } end
    CommanderSpellbook_Open("BOOK")
    S._SetSearch("")
    M.Flush(1)
    local function Brief(name)
        for _, row in ipairs(S._NavRows()) do
            if row:IsShown() and row.family and not row.item and row.family.name == name then
                M.RunScript(row, "OnClick", "LeftButton")
            end
        end
        M.Flush(1)
        local cost, cast = {}, {}
        for _, line in ipairs(S._Ladder()) do
            cost[#cost + 1] = line.costFS.__text or ""
            cast[#cast + 1] = line.castFS.__text or ""
        end
        return table.concat(cost, ","), table.concat(cast, ",")
    end
    local cost, cast = Brief("Lesser Heal")
    CHECK(cost == "30 mana,45 mana,75 mana", "L1 the ladder gives each rank's own cost", cost)
    CHECK(cast == "1.5 sec,2 sec,2.5 sec", "L2 ...and its own cast time", cast)
    cost, cast = Brief("Fade")
    CHECK(cost == "60 mana,75 mana,90 mana,105 mana,120 mana,135 mana,150 mana" and cast == ",,,,,,",
        "L3 an instant shows no cast time (a channel reads 0 too, and is not instant)", cost .. " / " .. cast)
    cost = Brief("Power Word: Shield")
    CHECK(cost:gsub(",", "") == "", "L4 a rank the client has no cost for leaves the column empty", cost)
    powerCosts[999001] = { name = "RAGE", cost = 15 }
    powerCosts[999002] = { name = "MANA", cost = 0, percent = 8 }
    powerCosts[999003] = { name = "ENERGY", cost = 40 }
    CHECK(S.CostText(999001) == "15 rage" and S.CostText(999002) == "8% mana" and S.CostText(999003) == "40 energy"
        and S.CostText(999004) == nil, "L5 rage, energy and a share of base mana read as such",
        tostring(S.CostText(999001)) .. "/" .. tostring(S.CostText(999002)))
    castTimes[999005] = 3000
    CHECK(S.CastText(999005) == "3 sec" and S.CastText(999004) == nil, "L5 whole seconds lose the .0")
    for id in pairs(powerCosts) do powerCosts[id] = nil end
    for id in pairs(castTimes) do castTimes[id] = nil end
end

-- ===========================================================================
-- M. Two spells of one name
-- ===========================================================================

do
    local SUB = { [990272] = "Rank 1: Pig", [990271] = "Rank 1: Turtle", [990401] = "Summon", [990402] = "Summon" }
    local realSub = C_Spell.GetSpellSubtext
    C_Spell.GetSpellSubtext = function(id) return SUB[id] or realSub(id) end
    local POLY = Def("Polymorph", { 990118, 990119 })
    Def("Polymorph", { 990272 })
    Def("Polymorph", { 990271 })
    Def("Summon Charger", { 990401 })
    Def("Summon Charger", { 990402 })
    local chains = CommanderSpellbookData.classes.PRIEST.chains
    local before = #chains
    for _, chain in ipairs({
        { role = "CONTROL", src = "T", ranks = POLY },
        { role = "CONTROL", src = "Q", ranks = { 990272 } },
        { role = "CONTROL", src = "Q", ranks = { 990271 } },
        { role = "TRAVEL", src = "Q", ranks = { 990401 } },
        { role = "TRAVEL", src = "Q", ranks = { 990402 } },
    }) do chains[#chains + 1] = chain end
    S.Reindex()
    local ids = { 990118, 990119, 990272, 990271, 990401, 990402 }
    for _, id in ipairs(ids) do known[id] = true end
    BuildBook()
    for _, id in ipairs({ 990271, 990119, 990402, 990272, 990401 }) do table.insert(TABS[4].ids, id) end
    CommanderSpellbook_Open("BOOK")
    S._SetSearch("")
    M.Flush(1)
    local function Titles()
        local out = {}
        for _, row in ipairs(S._NavRows()) do
            if row:IsShown() and row.family and not row.item
                and (row.family.name == "Polymorph" or row.family.name == "Summon Charger") then
                out[#out + 1] = row.title.__text
            end
        end
        return table.concat(out, ",")
    end
    CHECK(Titles() == "Polymorph,Polymorph (Pig),Polymorph (Turtle),Summon Charger,Summon Charger",
        "M1 namesakes are told apart by their rank text, the plain one first; a suffix all would share is left off",
        Titles())
    S._SetSearch("pig")
    CHECK(Titles() == "Polymorph (Pig)", "M2 a search finds the variant by its suffix", Titles())
    local pig
    for _, row in ipairs(S._NavRows()) do if row:IsShown() and row.family and row.family.display then pig = row.family end end
    CHECK(pig and pig.name == "Polymorph", "M3 the client's own name stays what Rank Check and the trainer match on",
        pig and pig.name)
    S._SetSearch("")

    for _ = 1, #chains - before do table.remove(chains) end
    S.Reindex()
    for _, id in ipairs(ids) do known[id] = nil end
    BuildBook()
    C_Spell.GetSpellSubtext = realSub
    S.Refresh()
    M.Flush(1)
end

-- ===========================================================================
-- K. At the trainer
-- ===========================================================================

do
    local savedKnown = {}
    for id, v in pairs(known) do savedKnown[id] = v end
    local savedMoney = me.money
    local TRAIN = CommanderSpellbookData.classes.PRIEST.train
    local trainer
    -- A class trainer's list for this level 40 priest: what Train Now holds
    -- (chained ranks listed unavailable until the one before is bought), a
    -- rank further off, and a line no Training row is. Prices are 90% of
    -- the data's: a trainer of a friendly faction.
    local function Line(id, kind)
        local row = TRAIN[id]
        return { id = id, name = SPELLS[id].name, rank = SPELLS[id].rank, kind = kind,
            cost = math.floor(row[2] * 0.9), level = row[1] }
    end
    local function ClassTrainer()
        trainer = { available = true, folded = false, bought = {}, pending = 0, overlap = 0, bad = 0, lines = {
            { header = true, name = "Priest" },
            Line(19236, "available"), Line(19238, "unavailable"), Line(19240, "unavailable"),
            Line(2791, "available"),
            Line(9473, "available"), Line(9474, "unavailable"), Line(10915, "unavailable"),
            Line(10888, "available"),
            Line(10941, "available"),
            { id = 0, name = "Mystery Rite", kind = "available", cost = 500, level = 1 },
        } }
    end
    local function Listed()
        local out = {}
        for _, line in ipairs(trainer.lines) do
            if line.header then
                out[#out + 1] = line
                if trainer.folded then break end
            elseif line.kind ~= "used" and (line.kind ~= "available" or trainer.available) then
                out[#out + 1] = line
            end
        end
        return out
    end
    local function Later(fn) C_Timer.After(0.05, fn) end
    function GetNumTrainerServices() return #Listed() end
    function GetTrainerServiceInfo(i)
        local line = Listed()[i]
        if not line then return nil end
        if line.header then return line.name, nil, "header", not trainer.folded end
        return line.name, line.rank and ("Rank " .. line.rank) or "", line.kind, nil
    end
    function GetTrainerServiceCost(i) local line = Listed()[i] return line and line.cost or 0, false end
    function IsTradeskillTrainer() return false end
    function GetTrainerServiceTypeFilter(kind) if kind == "available" then return trainer.available end return true end
    function SetTrainerServiceTypeFilter(kind, on)
        if kind == "available" then trainer.available = on and true or false end
        Later(function() M.Fire("TRAINER_UPDATE") end)
    end
    function ExpandTrainerSkillLine(i)
        trainer.folded, trainer.expanded = false, true
        Later(function() M.Fire("TRAINER_UPDATE") end)
    end
    -- A purchase is answered 0.1 s later; `early` sends a stray update
    -- first (before the purchase lands), `silent` never answers
    function BuyTrainerService(i)
        local line = Listed()[i]
        if trainer.pending > 0 then trainer.overlap = trainer.overlap + 1 end
        if not line or line.header or line.kind ~= "available" then trainer.bad = trainer.bad + 1 return end
        trainer.bought[#trainer.bought + 1] = line.id
        if trainer.silent then return end
        trainer.pending = trainer.pending + 1
        if trainer.early then C_Timer.After(0.02, function() M.Fire("TRAINER_UPDATE") end) end
        C_Timer.After(0.1, function()
            trainer.pending = trainer.pending - 1
            me.money = me.money - line.cost
            line.kind = "used"
            if line.id > 0 then known[line.id] = true end
            for _, other in ipairs(trainer.lines) do
                if not other.header and other.name == line.name and other.rank == (line.rank or 0) + 1
                    and other.kind == "unavailable" and other.level <= me.level then
                    other.kind = "available"
                end
            end
            BuildBook()
            M.Fire("TRAINER_UPDATE")
            M.Fire("LEARNED_SPELL_IN_SKILL_LINE", line.id)
        end)
    end
    -- Time in small steps, so a stray update can come between a purchase
    -- and its answer
    local function Fine(seconds)
        for _ = 1, math.ceil((seconds or 1) / 0.2) do M.Flush(0.01) end
    end
    local function Accept()
        local popup = popups[#popups]
        StaticPopupDialogs.COMMANDER_SPELLBOOK_TRAIN_ALL.OnAccept(nil, popup and popup.data)
    end
    local function Bought() return table.concat(trainer.bought, ",") end
    local function SelectTrain(id)
        for _, row in ipairs(S._NavRows()) do
            if row:IsShown() and row.item and row.item.id == id then M.RunScript(row, "OnClick", "LeftButton") return row end
        end
    end

    ClassTrainer()
    CommanderSpellbook_Hide()
    CommanderSpellbookDB.OpenAtTrainer = true
    S.SetIgnored(10888, true)
    M.Fire("TRAINER_SHOW")
    M.Flush(1)
    CHECK(S.IsShown() and CommanderSpellbookDB.Filter == "TRAIN", "K1 speaking to a class trainer opens the Training view")
    CHECK((frame.countFS.__text or ""):find("7 to train here") and (frame.countFS.__text or ""):find(S.Money(54900), 1, true),
        "K2 the toolbar counts Train Now at this trainer's own prices", frame.countFS.__text)
    SelectTrain(19236)
    local _, first = S._Selected()
    CHECK(first and first.id == 19236 and frame.trainBtn:IsShown() and frame.trainAllBtn:IsShown(),
        "K3 Train (the selected rank) and Train All are offered", first and first.id)
    CHECK(not frame.goBtn:IsShown(), "K3 ...and no Go to the trainer you are speaking to")
    local nowHeader, prayerRow
    for _, r in ipairs(S._NavRows()) do
        if r:IsShown() and r.headerGroup == "NOW" then nowHeader = r end
        if r:IsShown() and r.item and r.item.id == 19236 then prayerRow = r end
    end
    CHECK(nowHeader and nowHeader.right.__text == S.Money(54900) and prayerRow and prayerRow.right.__text == S.Money(1800),
        "K3 the rows and Train Now's total wear this trainer's prices", (nowHeader and nowHeader.right.__text) .. " / "
        .. (prayerRow and prayerRow.right.__text))
    local row = SelectTrain(9474)
    CHECK(not frame.trainBtn:IsShown() and frame.trainAllBtn:IsShown(),
        "K4 no Train for a rank this trainer will not teach yet (the one before first)")
    M.RunScript(row, "OnEnter")
    local said = table.concat(GameTooltip.__lines or {}, "|")
    CHECK(said:find("lists it, but not for you yet", 1, true), "K4 ...its tooltip says why", said)
    M.RunScript(SelectTrain(19236), "OnEnter")
    said = table.concat(GameTooltip.__lines or {}, "|")
    CHECK(said:find("This trainer teaches it now", 1, true), "K4 a rank on offer says so in its tooltip", said)

    if os.getenv("RENDER_TRAINER") then
        SelectTrain(19236)
        M.Flush(1)
        dofile(HERE .. "/spellbook_render.lua")(M, CommanderSpellbookFrame, os.getenv("RENDER_TRAINER"))
    end

    popups = {}
    frame.trainAllBtn:Click()
    CHECK(#popups == 1 and popups[1].name == "COMMANDER_SPELLBOOK_TRAIN_ALL"
        and (popups[1].text or ""):find("7 ranks for " .. S.Money(54900), 1, true) and #trainer.bought == 0,
        "K5 Train All asks first, naming the count and the trainer's price", popups[1] and popups[1].text)
    M.printLog = {}
    Accept()
    CHECK(S.Trainer.Running() and frame.trainAllBtn.__text == "Training...", "K6 the button says it is working",
        frame.trainAllBtn.__text)
    M.Flush(1)
    CHECK(Bought() == "19236,19238,9473,19240,2791,9474,10941",
        "K6 accepted, it buys all of Train Now in level order, each chained rank once the one before is in", Bought())
    CHECK(trainer.overlap == 0 and trainer.bad == 0, "K7 one purchase at a time, never a line not on offer",
        trainer.overlap .. " overlapping, " .. trainer.bad .. " refused")
    CHECK(not Bought():find("10888") and not Bought():find("^0,") and not Bought():find(",0,") and not Bought():find(",0$")
        and not Bought():find("10915"),
        "K7 never an ignored rank, a rank further off, or a line no Training row is")
    CHECK(me.money == savedMoney - 54900, "K8 it spent the trainer's prices", savedMoney - me.money)
    local log = table.concat(M.printLog, "|")
    CHECK(log:find("trained 7 ranks for " .. S.Money(54900), 1, true), "K8 ...and says what it did", log)
    CHECK(not S.Trainer.Running() and not frame.trainAllBtn:IsShown(), "K8 done, nothing left to offer")
    M.Fire("TRAINER_CLOSED")
    M.Flush(1)
    CHECK(not S.IsShown(), "K9 leaving the trainer closes the view it opened")
    CHECK(CommanderSpellbookDB.Filter == "BOOK", "K9 ...and the window goes back to the view it was left on",
        CommanderSpellbookDB.Filter)

    -- A list hiding its lines (a folded header, Available unticked) is opened
    -- up by Train All before it asks
    for id, v in pairs(savedKnown) do known[id] = v end
    for id in pairs(known) do if not savedKnown[id] then known[id] = nil end end
    BuildBook()
    me.money = savedMoney
    ClassTrainer()
    trainer.folded, trainer.available = true, false
    CommanderSpellbook_Open("TRAIN")
    M.Fire("TRAINER_SHOW")
    M.Flush(1)
    CHECK(frame.trainAllBtn:IsShown(), "K10 a list hiding its lines still offers Train All")
    popups = {}
    frame.trainAllBtn:Click()
    CHECK(#popups == 0 and trainer.expanded and trainer.available, "K10 ...which unfolds it and ticks Available first")
    M.Flush(1)
    CHECK(#popups == 1 and (popups[1].text or ""):find("7 ranks", 1, true) and #trainer.bought == 0,
        "K10 ...then asks, with the whole list in view", popups[1] and popups[1].text)

    -- Train buys the one selected
    SelectTrain(2791)
    frame.trainBtn:Click()
    M.Flush(1)
    CHECK(Bought() == "2791", "K11 Train buys the selected rank only", Bought())

    -- Short of money: it stops there and says so
    me.money = 2000
    M.printLog = {}
    frame.trainAllBtn:Click()
    Accept()
    M.Flush(1)
    log = table.concat(M.printLog, "|")
    CHECK(Bought() == "2791,19236" and log:find("not enough money", 1, true) and not S.Trainer.Running(),
        "K12 out of money, Train All stops and says so", Bought() .. " / " .. log)

    -- The trainer closing mid-way stops it
    me.money = savedMoney
    frame.trainAllBtn:Click()
    Accept()
    M.Fire("TRAINER_CLOSED")
    M.Flush(1)
    CHECK(Bought() == "2791,19236,19238" and not S.Trainer.Running(), "K13 leaving the trainer mid-way stops it", Bought())
    CHECK(S.IsShown(), "K13 a view the player opened stays open when the trainer closes")
    CHECK(hiddenPopups[#hiddenPopups] == "COMMANDER_SPELLBOOK_TRAIN_ALL",
        "K13 ...and a confirmation still up for it is put away")

    local function Restore()
        for id in pairs(known) do known[id] = nil end
        for id, v in pairs(savedKnown) do known[id] = v end
        BuildBook()
        me.money = savedMoney
    end

    -- A confirmation answered after the list changed buys nothing
    Restore()
    ClassTrainer()
    M.Fire("TRAINER_SHOW")
    M.Flush(1)
    popups = {}
    frame.trainAllBtn:Click()
    S.SetIgnored(10888, false)
    M.printLog = {}
    Accept()
    M.Flush(1)
    log = table.concat(M.printLog, "|")
    CHECK(#trainer.bought == 0 and log:find("the list changed", 1, true),
        "K16 a confirmation answered after the list changed buys nothing", Bought() .. " / " .. log)
    S.SetIgnored(10888, true)
    M.Fire("TRAINER_CLOSED")

    -- A trainer that lists only part of Train Now is offered only that part
    Restore()
    ClassTrainer()
    for index = #trainer.lines, 1, -1 do
        local line = trainer.lines[index]
        if line.id == 10941 or line.id == 2791 then table.remove(trainer.lines, index) end
    end
    CommanderSpellbook_Open("TRAIN")
    M.Fire("TRAINER_SHOW")
    M.Flush(1)
    CHECK((frame.countFS.__text or ""):find("5 to train here", 1, true) and (frame.countFS.__text or ""):find(S.Money(33300), 1, true),
        "K17 a rank the trainer does not list is neither counted nor priced", frame.countFS.__text)
    popups = {}
    frame.trainAllBtn:Click()
    CHECK(popups[1] and (popups[1].text or ""):find("5 ranks for " .. S.Money(33300), 1, true),
        "K17 ...nor named in the question", popups[1] and popups[1].text)
    M.Fire("TRAINER_CLOSED")

    -- A stray update before a purchase lands is not its answer
    Restore()
    ClassTrainer()
    trainer.early = true
    M.Fire("TRAINER_SHOW")
    M.Flush(1)
    popups = {}
    frame.trainAllBtn:Click()
    M.printLog = {}
    Accept()
    Fine(4)
    log = table.concat(M.printLog, "|")
    CHECK(Bought() == "19236,19238,9473,19240,2791,9474,10941" and trainer.overlap == 0,
        "K18 a stray update between a purchase and its answer starts nothing", Bought() .. ", " .. trainer.overlap .. " overlapping")
    CHECK(log:find("trained 7 ranks", 1, true), "K18 ...and the run still finishes", log)
    M.Fire("TRAINER_CLOSED")

    -- A purchase never answered is not reported as bought
    Restore()
    ClassTrainer()
    trainer.silent = true
    M.Fire("TRAINER_SHOW")
    M.Flush(1)
    popups = {}
    frame.trainAllBtn:Click()
    M.printLog = {}
    Accept()
    Fine(4)
    log = table.concat(M.printLog, "|")
    CHECK(#trainer.bought == 1 and not log:find("trained", 1, true) and log:find("did not answer", 1, true)
        and not S.Trainer.Running(),
        "K19 a purchase the trainer never answers is not counted, and the run stops saying so", log)
    M.Fire("TRAINER_CLOSED")
    M.Flush(1)

    -- A weapon master with Available unticked offers no Train All either,
    -- when a line still in view says what it is (with nothing in view there
    -- is no telling; Train All then opens the list and says it found nothing)
    Restore()
    trainer = { available = false, folded = false, bought = {}, pending = 0, overlap = 0, bad = 0, lines = {
        { header = true, name = "Weapons" },
        { id = 1180, name = "Daggers", kind = "unavailable", cost = 900, level = 1 },
    } }
    M.Fire("TRAINER_SHOW")
    M.Flush(1)
    CHECK(not frame.trainAllBtn:IsShown(), "K15 a weapon master hiding lines still offers no Train All")
    M.Fire("TRAINER_CLOSED")
    M.Flush(1)

    -- Off, the trainer opens nothing; a weapon master is not a class trainer
    CommanderSpellbook_Hide()
    CommanderSpellbookDB.OpenAtTrainer = false
    ClassTrainer()
    M.Fire("TRAINER_SHOW")
    M.Flush(1)
    CHECK(not S.IsShown(), "K14 with Open at the Trainer off, the trainer opens nothing")
    M.Fire("TRAINER_CLOSED")
    CommanderSpellbookDB.OpenAtTrainer = true
    trainer = { available = true, folded = false, bought = {}, pending = 0, overlap = 0, bad = 0, lines = {
        { header = true, name = "Weapons" },
        { id = 1180, name = "Daggers", kind = "available", cost = 900, level = 1 },
    } }
    M.Fire("TRAINER_SHOW")
    M.Flush(1)
    CHECK(not S.IsShown(), "K15 a weapon master does not open the Training view")
    CommanderSpellbook_Open("TRAIN")
    M.Flush(1)
    CHECK(not frame.trainAllBtn:IsShown(), "K15 ...nor offer Train All")
    local dagger
    for _, r in ipairs(S._NavRows()) do if r:IsShown() and r.item and r.item.id == 1180 then dagger = r end end
    if dagger then M.RunScript(dagger, "OnClick", "LeftButton") end
    CHECK(dagger and frame.trainBtn:IsShown(), "K15 ...but Train buys the weapon skill it teaches")
    M.Fire("TRAINER_CLOSED")
    M.Flush(1)

    for id in pairs(known) do known[id] = nil end
    for id, v in pairs(savedKnown) do known[id] = v end
    BuildBook()
    me.money = savedMoney
    S.SetIgnored(10888, false)
    CommanderSpellbook_Open("BOOK")
    M.Flush(1)
end

-- ===========================================================================
-- I. The pet's abilities
-- ===========================================================================

Def("Follow", { 9999 })
pet.spells = { 3110, 6307, 9999 }
SPELLS[3110].rank = 2
PASSIVE[6307] = true
CommanderSpellbook_Hide()
CommanderSpellbook_TogglePet()
M.Flush(1)
local petRow, petButton
for _, row in ipairs(S._NavRows()) do
    if row:IsShown() and row.family and row.family.bookType == "pet" and row.family.name == "Firebolt" then petRow = row end
end
for _, b in ipairs(castPool) do
    if b:IsShown() and b:GetAttribute("spell") == "Firebolt" then petButton = b end
end
CHECK(petRow ~= nil, "I1 the pet book key opens on the pet's abilities")
local followButton = false
for _, b in ipairs(castPool) do
    if b:IsShown() and b:GetAttribute("spell") == "Follow" then followButton = true end
end
CHECK(not followButton, "I4 a pet command gets no cast button (it is no spell to cast by name)")
CHECK(petButton and petButton:GetAttribute("macrotext2") == "/petautocasttoggle Firebolt",
    "I2 right-click toggles an autocast ability's autocast")
pickups = {}
if petRow then M.RunScript(petRow, "OnDragStart") end
CHECK(pickups[1] == "pet:1", "I3 a pet ability drags from its pet book slot", pickups[1])

-- ===========================================================================

CHECK(#M.errors == 0, "Z no errors through the error handler", M.errors[1])

if os.getenv("RENDER") then
    CommanderSpellbookDB.Filter = "BOOK"
    pet.spells = {}
    CommanderSpellbook_Hide()
    CommanderSpellbook_Show()
    M.Flush(1)
    navScroll:SetVerticalScroll(0)
    -- Fade on its cooldown, to show the swipe; its ranks' costs, and a long
    -- cast time, to show the ladder's columns full
    cooldowns[Highest(FADE)] = { M.now - 5, 30 }
    for i, id in ipairs(FADE) do powerCosts[id] = { cost = 45 + 150 * i } castTimes[id] = 2500 end
    for _, row in ipairs(S._NavRows()) do
        if row:IsShown() and row.family and row.family.name == "Fade" then M.RunScript(row, "OnClick", "LeftButton") end
    end
    M.Flush(1)
    dofile(HERE .. "/spellbook_render.lua")(M, CommanderSpellbookFrame, os.getenv("RENDER"))
    if os.getenv("RENDER_TRAIN") then
        CommanderSpellbook_Open("TRAIN")
        M.Flush(1)
        dofile(HERE .. "/spellbook_render.lua")(M, CommanderSpellbookFrame, os.getenv("RENDER_TRAIN"))
    end
end

io.write(string.format("\n%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
