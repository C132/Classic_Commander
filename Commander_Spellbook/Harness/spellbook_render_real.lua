-- Commander Spellbook: a picture of a real class's book (luajit).
--
--   CLASS=PRIEST LEVEL=70 OUT=/tmp/real.json \
--     /opt/homebrew/bin/luajit Commander_Spellbook/Harness/spellbook_render_real.lua
--   python3 Commander_Spellbook/Harness/render_svg.py /tmp/real.json /tmp/real.svg
--
-- The shipped CommanderSpellbookData.lua, a character of CLASS at LEVEL who
-- has trained every rank due (their race's own, a human or an orc, plus every
-- talent and quest first rank), the book listing the highest rank of each,
-- with the client's own tab for each chain approximated by role. What is
-- real is how many rows, foldouts and ranks a full book makes, and how the
-- window holds them. With SPELLS=<lua> (make_render_spells.py) the names,
-- ranks, cast times and costs are the client's own; without, "Chain N".
-- BRIEF=<name> briefs that spell; VIEW=TRAIN draws the Training view;
-- TRAINED=<level> stops the training there.

local ADDONS = "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local HERE = ADDONS .. "/Commander_Spellbook/Harness"
local M = dofile(HERE .. "/spellbook_mock.lua")
dofile(ADDONS .. "/Commander_Spellbook/CommanderSpellbookData.lua")

local CLASS = os.getenv("CLASS") or "PRIEST"
local LEVEL = tonumber(os.getenv("LEVEL") or "70")
local OUT = os.getenv("OUT") or "/tmp/real.json"
local IDS = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }
local ALLIANCE = { PALADIN = true, PRIEST = true, MAGE = true, WARRIOR = true, ROGUE = true, WARLOCK = true }
local raceID = ALLIANCE[CLASS] and 1 or 2
if CLASS == "DRUID" then raceID = 4 end
if CLASS == "SHAMAN" then raceID = 2 end

function UnitClass() return CLASS, CLASS, IDS[CLASS] end
function UnitRace() return "Race", "Race", raceID end
function UnitLevel() return LEVEL end
function UnitFactionGroup() return raceID == 1 or raceID == 4 and "Alliance" or "Horde" end
function UnitName() return "Render" end
function GetMoney() return 5000000 end
BOOKTYPE_PET = "pet"
C_Map = { GetMapInfo = function() return { name = "Zone" } end }

local D = CommanderSpellbookData.classes[CLASS]
local bit = 2 ^ (raceID - 1)
local function Allowed(mask) return not mask or math.floor(mask / bit) % 2 == 1 end
-- TRAINED=<level>: the last visit to the trainer was at that level, so
-- the Training view has a trip's worth on it (default: everything due)
local TRAINED = tonumber(os.getenv("TRAINED") or "") or LEVEL
local known = {}
for id, row in pairs(D.train) do
    if row[1] <= TRAINED and Allowed(row[3]) then known[id] = true end
end
for _, chain in ipairs(D.chains) do
    if chain.src ~= "T" then known[chain.ranks[1]] = true end
end

local NAMES = {}
local REAL = os.getenv("SPELLS") and dofile(os.getenv("SPELLS")) or {}
local function Name(id) return (REAL[id] and REAL[id][1]) or NAMES[id] or ("Spell " .. id) end
local function Subtext(id) return REAL[id] and REAL[id][2] or "" end
local tabs = { { name = "General", ids = { 6603 } }, { name = "Tree One", ids = {} }, { name = "Tree Two", ids = {} }, { name = "Tree Three", ids = {} } }
NAMES[6603] = "Attack"
local which = { HEAL = 2, BUFF = 2, DEFENSE = 2, CONTROL = 4, DAMAGE = 3, FORM = 4, UTILITY = 2, PET = 4, PASSIVE = 3 }
for i, chain in ipairs(D.chains) do
    local best
    for position, id in ipairs(chain.ranks) do
        if known[id] then best = id end
        NAMES[id] = "Chain " .. i
    end
    if best then table.insert(tabs[which[chain.role] or 2].ids, best) end
end
local function SlotSpell(slot)
    local offset = 0
    for _, tab in ipairs(tabs) do
        if slot <= offset + #tab.ids then return tab.ids[slot - offset] end
        offset = offset + #tab.ids
    end
end
function GetNumSpellTabs() return #tabs end
function GetSpellTabInfo(t)
    local offset = 0
    for i = 1, t - 1 do offset = offset + #tabs[i].ids end
    return tabs[t].name, 1, offset, #tabs[t].ids
end
function GetSpellBookItemInfo(slot) local id = SlotSpell(slot) if id then return "SPELL", id end end
function GetSpellBookItemName(slot) local id = SlotSpell(slot) if id then return Name(id), Subtext(id), id end end
function IsPassiveSpell(slot)
    local id = SlotSpell(slot)
    for _, chain in ipairs(D.chains) do
        for _, rid in ipairs(chain.ranks) do if rid == id then return chain.role == "PASSIVE" end end
    end
    return false
end
function GetSpellTexture(a) return "Interface\\Icons\\S" .. tostring(a) end
function HasPetSpells() return nil end
function IsPlayerSpell(id) return known[id] == true end
function IsSpellKnown(id) return known[id] == true end
function GetSpellInfo(id) return Name(id), nil, "Interface\\Icons\\S" .. id end
C_Spell = { GetSpellName = function(id) return Name(id) end, GetSpellTexture = function(id) return "Interface\\Icons\\S" .. id end,
    GetSpellSubtext = function(id) return Subtext(id) end, IsSpellDataCached = function() return true end,
    GetSpellInfo = function(id)
        local real = REAL[id]
        return { name = Name(id), iconID = 1, originalIconID = 1, castTime = real and real[3] or 0, minRange = 0, maxRange = 0, spellID = id }
    end,
    GetSpellPowerCost = function(id)
        local real = REAL[id]
        if not real or real[4] == 0 then return nil end
        return { { type = 0, name = real[5], cost = real[4], minCost = real[4], costPercent = 0, costPerSec = 0 } }
    end,
}
C_SpellBook = { IsSpellKnown = function(id) return known[id] == true end, IsSpellInSpellBook = function(id) return known[id] == true end }
local SpellMixin = {}
SpellMixin.__index = SpellMixin
function SpellMixin:IsSpellEmpty() return false end
function SpellMixin:IsSpellDataCached() return true end
function SpellMixin:ContinueOnSpellLoad(cb) cb() end
Spell = { CreateFromSpellID = function(_, id) return setmetatable({ spellID = id }, SpellMixin) end }
function GetBindingKey() return nil end
function SetOverrideBinding() end
function ClearOverrideBindings() end
function GetActionInfo() return nil end
function GetMacroInfo() return nil end
SpellBookFrame = CreateFrame("Frame", "SpellBookFrame", UIParent)

local function Load(path) assert(loadfile(path))() end
Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderGoButton.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
for _, f in ipairs({ "DB", "Model", "Training", "Trainer", "Secure", "UI" }) do
    Load(ADDONS .. "/Commander_Spellbook/CommanderSpellbook" .. f .. ".lua")
end
M.Fire("ADDON_LOADED", "Commander_Spellbook")
M.Fire("PLAYER_LOGIN")
CommanderSpellbookDB.Filter = os.getenv("VIEW") or "BOOK"
CommanderSpellbook_Show()
M.Flush(1)
if os.getenv("BRIEF") then
    for _, row in ipairs(CommanderSpellbook._NavRows()) do
        if row:IsShown() and row.family and row.family.name == os.getenv("BRIEF") then
            M.RunScript(row, "OnClick", "LeftButton")
            break
        end
    end
    M.Flush(1)
end
local rows = CommanderSpellbook._Rows()
local families, headers = 0, {}
for _, row in ipairs(rows) do
    if row.family then families = families + 1 end
    if row.header then headers[#headers + 1] = row.header.label .. " " .. (row.count or #row.header.items) end
end
io.write(CLASS, " level ", LEVEL, ": ", families, " rows; ", table.concat(headers, ", "), "\n")
-- DUMP=1 lists every row under its foldout, for reading the grouping
if os.getenv("DUMP") then
    for _, row in ipairs(rows) do
        if row.header then io.write("\n  ", row.header.label, ": ")
        elseif row.family then io.write(CommanderSpellbook.DisplayName(row.family), "; ")
        elseif row.train then io.write(row.train.family.name, " ", row.train.entry.rank or "", "; ") end
    end
    io.write("\n")
end
dofile(HERE .. "/spellbook_render.lua")(M, CommanderSpellbookFrame, OUT)
