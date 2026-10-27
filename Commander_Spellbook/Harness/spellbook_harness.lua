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
C_Spell = {
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
CHECK(table.concat(tkeys, ",") == "NOW+,WEAPON+,SOON+,TALENT-,LATER-", "C7 Training foldouts, the far end folded", table.concat(tkeys, ","))

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
    for _, row in ipairs(S._NavRows()) do
        if row:IsShown() and row.family and row.family.name == "Flash Heal" then M.RunScript(row, "OnClick", "LeftButton") end
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
