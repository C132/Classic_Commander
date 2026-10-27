-- Commander Spellbook data smoke (luajit).
--
--   /opt/homebrew/bin/luajit Commander_Spellbook/Harness/data_smoke.lua
--
-- The generated CommanderSpellbookData.lua, checked for the shape the model
-- reads and for the facts every class's book depends on, then run through
-- the real model and training code once per class: a fresh level 1
-- character, a level 40 one who knows every rank due by then, and a level 70
-- one who knows everything. spellbook_harness.lua proves the logic on a
-- fixture; this proves the shipped data drives it without a gap.

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

dofile(ADDONS .. "/Commander_Spellbook/CommanderSpellbookData.lua")
local D = CommanderSpellbookData

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------

local ROLES = { HEAL = true, DAMAGE = true, CONTROL = true, DEFENSE = true, BUFF = true, FORM = true,
    UTILITY = true, TRAVEL = true, PET = true, PASSIVE = true }
local SRC = { T = true, L = true, Q = true, O = true }
local GENERAL = { PROFESSION = true, RACIAL = true, GENERAL = true }
local CLASSES = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }

CHECK(type(D) == "table" and type(D.build) == "string", "S1 the file defines CommanderSpellbookData with a build")
for class in pairs(CLASSES) do
    local c = D.classes and D.classes[class]
    CHECK(type(c) == "table" and type(c.chains) == "table" and type(c.train) == "table", "S2 " .. class .. " has chains and train")
    if c then
        local seenRank, badRole, badSrc, dupes = {}, 0, 0, 0
        for _, chain in ipairs(c.chains) do
            if not ROLES[chain.role] then badRole = badRole + 1 end
            if not SRC[chain.src] then badSrc = badSrc + 1 end
            for _, id in ipairs(chain.ranks or {}) do
                if seenRank[id] then dupes = dupes + 1 end
                seenRank[id] = true
            end
        end
        CHECK(badRole == 0, "S3 " .. class .. " every chain has a known role", badRole)
        CHECK(badSrc == 0, "S3 " .. class .. " every chain has a known source", badSrc)
        CHECK(dupes == 0, "S4 " .. class .. " no rank belongs to two chains", dupes)
        local trainRows, unchained, badRow = 0, 0, 0
        for id, row in pairs(c.train) do
            trainRows = trainRows + 1
            if not seenRank[id] then unchained = unchained + 1 end
            if type(row[1]) ~= "number" or type(row[2]) ~= "number" or row[1] < 1 or row[1] > 70 then badRow = badRow + 1 end
        end
        CHECK(trainRows > 50, "S5 " .. class .. " has a trainer list", trainRows)
        CHECK(badRow == 0, "S5 " .. class .. " every trainer row has a level and a price", badRow)
        -- A few trainer rows are not spells of the book: armour proficiencies
        -- (Plate Mail, Mail) and the rogue's poison recipes. Training lists
        -- them as families of one; more than a handful means a chain gap.
        CHECK(unchained <= 30, "S6 " .. class .. " trainer rows outside every rank chain stay few", unchained)
    end
end
local badGeneral = 0
for id, word in pairs(D.general or {}) do
    if type(id) ~= "number" or not GENERAL[word] then badGeneral = badGeneral + 1 end
end
CHECK(badGeneral == 0, "S7 general words are PROFESSION, RACIAL or GENERAL", badGeneral)
local weapons, badWeapon = 0, 0
for id, w in pairs(D.weapons or {}) do
    weapons = weapons + 1
    if type(w.classMask) ~= "number" or type(w.cost) ~= "number" or type(w.trainers) ~= "table" then badWeapon = badWeapon + 1 end
    for _, side in ipairs({ "Alliance", "Horde" }) do
        for _, t in ipairs((w.trainers or {})[side] or {}) do
            if not (t.name and t.map and t.x and t.y and t.x >= 0 and t.x <= 1 and t.y >= 0 and t.y <= 1) then
                badWeapon = badWeapon + 1
            end
        end
    end
end
CHECK(weapons >= 10, "S8 weapon skills listed", weapons)
CHECK(badWeapon == 0, "S8 every weapon skill and trainer is well formed", badWeapon)

-- ---------------------------------------------------------------------------
-- Facts the book leans on (the user's classes most of all)
-- ---------------------------------------------------------------------------

local function Chain(class, first)
    for _, chain in ipairs(D.classes[class].chains) do
        if chain.ranks[1] == first then return chain end
    end
    return nil
end
local lesser = Chain("PRIEST", 2050)
CHECK(lesser and table.concat(lesser.ranks, ",") == "2050,2052,2053" and lesser.role == "HEAL", "F1 Lesser Heal is 2050, 2052, 2053, Healing")
local flash = Chain("PRIEST", 2061)
CHECK(flash and #flash.ranks == 9, "F2 Flash Heal has nine ranks", flash and #flash.ranks)
local flay = Chain("PRIEST", 15407)
CHECK(flay and flay.src == "L" and D.classes.PRIEST.train[flay.ranks[2]] ~= nil, "F3 Mind Flay: a talent first, its later ranks trained")
local poly = Chain("MAGE", 118)
CHECK(poly and poly.role == "CONTROL", "F4 Polymorph is Crowd Control", poly and poly.role)
local tele = D.classes.MAGE.train[3561]
CHECK(tele and tele[3] and tele[3] % 2 == 1 and tele[3] % 4 < 2 + 1, "F5 Teleport: Stormwind is for the Alliance's races", tele and tele[3])
local scream = Chain("PRIEST", 8122)
CHECK(scream and scream.role == "CONTROL", "F6 Psychic Scream is Crowd Control")
local sor = Chain("PALADIN", 21084) or Chain("PALADIN", 20154)
CHECK(sor ~= nil and #sor.ranks >= 8, "F7 Seal of Righteousness chain", sor and #sor.ranks)
local hawk = Chain("HUNTER", 13165)
CHECK(hawk and hawk.role == "FORM", "F8 Aspect of the Hawk is a FORM", hawk and hawk.role)
local battle = Chain("WARRIOR", 2457)
CHECK(battle and battle.role == "FORM", "F9 Battle Stance is a FORM", battle and battle.role)
local bear = Chain("DRUID", 5487)
CHECK(bear and bear.role == "FORM" and bear.src == "Q", "F10 Bear Form: a FORM from a quest", bear and (bear.role .. bear.src))
local tp = Chain("MAGE", 3561)
CHECK(tp and tp.role == "TRAVEL", "F12 Teleport: Stormwind is Travel", tp and tp.role)
local void = Chain("WARLOCK", 697)
CHECK(void and void.role == "PET" and void.src == "Q", "F11 Summon Voidwalker: a PET from a quest", void and (void.role .. void.src))

-- ---------------------------------------------------------------------------
-- The real model on the real data, every class
-- ---------------------------------------------------------------------------

local ADDON = ADDONS .. "/Commander_Spellbook/"
CommanderSpellbookDB = { SoonLevels = 2 }
CommanderSpellbookChar = { Ignored = {} }
dofile(ADDON .. "CommanderSpellbookModel.lua")
dofile(ADDON .. "CommanderSpellbookTraining.lua")
local S = CommanderSpellbook
S.EnsureCharDB = function() return CommanderSpellbookChar end

local me = {}
function UnitClass() return me.class, me.class, CLASSES[me.class] end
function UnitRace() return me.race, me.race, me.raceID end
function UnitLevel() return me.level end
local known = {}
C_SpellBook = { IsSpellKnown = function(id) return known[id] == true end }
IsPlayerSpell, IsSpellKnown = nil, nil
function GetNumSpellTabs() return 0 end
function HasPetSpells() return nil end
C_Spell = { GetSpellName = function(id) return "Spell" .. id end, GetSpellTexture = function() return 1 end,
    GetSpellSubtext = function() return "" end }
function GetSpellInfo(id) return "Spell" .. id end

local RACE_OF = { WARRIOR = 1, PALADIN = 1, HUNTER = 2, ROGUE = 5, PRIEST = 1, SHAMAN = 2, MAGE = 1, WARLOCK = 5, DRUID = 4 }
for class in pairs(CLASSES) do
    me.class, me.raceID, me.race = class, RACE_OF[class], "Race"
    S.Reindex()
    known = {}
    me.level = 1
    local ok, training = pcall(S.Training, S.Scan({ unlearned = true }), { soon = 2 })
    CHECK(ok, "M1 " .. class .. " level 1 training builds", training)
    local now1 = ok and training.nowCount or 0
    CHECK(ok and now1 >= 1, "M1 " .. class .. " has something to train at level 1", now1)
    -- Level 40, every rank due by then learned (the race's own only)
    me.level = 40
    for id, row in pairs(D.classes[class].train) do
        if row[1] <= 40 and S.RaceAllows(row[3]) then known[id] = true end
    end
    for _, chain in ipairs(D.classes[class].chains) do
        if chain.src ~= "T" then known[chain.ranks[1]] = true end
    end
    ok, training = pcall(S.Training, S.Scan({ unlearned = true }), { soon = 2 })
    CHECK(ok and training.nowCount == 0, "M2 " .. class .. " at 40 with everything due learned has nothing to train now",
        ok and training.nowCount)
    CHECK(ok and training.groups.SOON and #training.groups.SOON.items > 0, "M2 " .. class .. " has something coming up at 41-42")
    -- Level 70, everything
    me.level = 70
    for id in pairs(D.classes[class].train) do known[id] = true end
    ok, training = pcall(S.Training, S.Scan({ unlearned = true }), { soon = 2 })
    local left = 0
    for key, group in pairs(ok and training.groups or {}) do
        if key ~= "WEAPON" then left = left + #group.items end
    end
    CHECK(ok and left == 0, "M3 " .. class .. " at 70 knowing everything has nothing left", left)
end

io.write(string.format("\n%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
