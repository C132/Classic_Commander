-- Commander_Talents offline harness (luajit). Engine unit tests on a
-- synthetic class, then integration checks over every generated class data
-- file present: builds apply cleanly to exactly 61 points, serialization
-- round-trips, and the preset keys cover the Quartermaster spec list.
--
--   /opt/homebrew/bin/luajit Harness/talents_harness.lua
--
-- Run from the Commander_Talents directory (or pass its path as arg 1).

local root = (...) or "."
if root:sub(-1) == "/" then root = root:sub(1, -2) end

local checks, failures = 0, {}
local function ok(cond, label)
    checks = checks + 1
    if not cond then
        failures[#failures + 1] = ("#%d %s"):format(checks, label)
    end
end

local function fileExists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

-- ---------------------------------------------------------------- load
dofile(root .. "/CommanderTalentsData.lua")
dofile(root .. "/CommanderTalentsEngine.lua")
local Data = CommanderTalentsData
local E = CommanderTalentsEngine

local EXPECTED_SPECS = {
    WARRIOR = { "ARMS", "FURY", "PROTECTION" },
    PALADIN = { "HOLY", "PROTECTION", "RETRIBUTION" },
    HUNTER = { "BEAST_MASTERY", "MARKSMANSHIP", "SURVIVAL" },
    ROGUE = { "ASSASSINATION", "COMBAT" },
    PRIEST = { "DISCIPLINE", "HOLY", "SHADOW" },
    SHAMAN = { "ELEMENTAL", "ENHANCEMENT", "RESTORATION" },
    MAGE = { "ARCANE", "FIRE", "FROST" },
    WARLOCK = { "AFFLICTION", "DEMONOLOGY", "DESTRUCTION" },
    DRUID = { "BALANCE", "FERAL_CAT", "FERAL_BEAR", "RESTORATION" },
}
local CLASS_FILES = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter",
    ROGUE = "Rogue", PRIEST = "Priest", SHAMAN = "Shaman",
    MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}

local missing = {}
for _, token in ipairs(Data.ClassOrder) do
    local path = ("%s/CommanderTalentsData_%s.lua"):format(root, CLASS_FILES[token])
    if fileExists(path) then
        dofile(path)
    else
        missing[#missing + 1] = token
    end
end

-- ---------------------------------------------------------------- synthetic engine tests
local function T(name, icon, row, col, max, req)
    local ranks = {}
    for r = 1, max do ranks[r] = ("synthetic rank %d text for %s"):format(r, name) end
    return { name = name, icon = icon or "inv_misc_questionmark", row = row, col = col,
             max = max, req = req, ranks = ranks }
end

local synth = {
    trees = {
        { name = "Alpha", bg = "WarriorArms", talents = {
            T("A", nil, 1, 1, 5), T("B", nil, 1, 2, 5),
            T("C", nil, 2, 1, 1, "A"), T("D", nil, 2, 2, 5),
            T("F", nil, 2, 3, 3), T("R", nil, 2, 4, 1, "F"),
            T("E", nil, 3, 2, 2, "D"), T("G", nil, 9, 1, 1),
        } },
        { name = "Beta", bg = "WarriorFury", talents = {
            T("H", nil, 1, 1, 5), T("I", nil, 1, 2, 5), T("J", nil, 1, 3, 5),
            T("K", nil, 2, 1, 5), T("L", nil, 2, 2, 5),
        } },
        { name = "Gamma", bg = "WarriorProtection", talents = {
            T("M", nil, 1, 1, 5), T("N", nil, 1, 2, 5), T("Q", nil, 1, 3, 5),
            T("O", nil, 2, 1, 5), T("P", nil, 2, 2, 5),
        } },
    },
}

local function idxOf(state, t, name)
    return state.class._idx[t].byName[name]
end

local s = E.NewState(synth)
ok(E.TotalSpent(s) == 0, "fresh state empty")
ok(E.Signature(s) == "0/0/0", "fresh signature")
ok(E.RequiredLevel(s) == 0, "fresh level 0")

local iA, iB, iC, iD, iE, iF, iG, iR =
    idxOf(s, 1, "A"), idxOf(s, 1, "B"), idxOf(s, 1, "C"), idxOf(s, 1, "D"),
    idxOf(s, 1, "E"), idxOf(s, 1, "F"), idxOf(s, 1, "G"), idxOf(s, 1, "R")

ok(E.AddBlock(s, 1, iC).type == "TIER", "row2 blocked at 0 points")
ok(E.CanAdd(s, 1, iA), "row1 open")
for _ = 1, 5 do E.Add(s, 1, iA) end
ok(E.Rank(s, 1, iA) == 5, "A at 5")
ok(E.AddBlock(s, 1, iA).type == "MAX", "A maxed blocks")
ok(E.CanAdd(s, 1, iC), "C open after tier+req satisfied")
E.Add(s, 1, iC)
ok(E.AddBlock(s, 1, iE) ~= nil, "E blocked (tier or req)")
for _ = 1, 4 do E.Add(s, 1, iB) end
ok(E.PointsAboveRow(s, 1, 3) == 10, "10 points above row 3")
ok(E.AddBlock(s, 1, iE).type == "REQ", "E blocked by unmaxed D")
for _ = 1, 5 do E.Add(s, 1, iD) end
ok(E.CanAdd(s, 1, iE), "E open after D maxed")
E.Add(s, 1, iE); E.Add(s, 1, iE)
ok(E.Signature(s) == "17/0/0", "signature 17/0/0")
ok(E.RequiredLevel(s) == 26, "17 points = level 26")

ok(E.RemoveBlock(s, 1, iA).type == "REQ", "A locked by dependent C")
ok(E.RemoveBlock(s, 1, iB) == nil, "B removable")
E.Remove(s, 1, iB)
ok(E.Rank(s, 1, iB) == 3, "B down to 3")
ok(E.RemoveBlock(s, 1, iD).type == "REQ", "D locked by dependent E")
E.Remove(s, 1, iE); E.Remove(s, 1, iE)
ok(E.RemoveBlock(s, 1, iD) == nil, "D removable once E empty")
ok(E.AddBlock(s, 1, iG).type == "TIER", "row9 needs 40")

-- Tier-support removal lock: exactly 5 above a row-2 talent
local s2 = E.NewState(synth)
for _ = 1, 5 do E.Add(s2, 1, idxOf(s2, 1, "A")) end
E.Add(s2, 1, idxOf(s2, 1, "F"))
ok(E.RemoveBlock(s2, 1, idxOf(s2, 1, "A")).type == "SUPPORT", "tier support locks removal")
E.Remove(s2, 1, idxOf(s2, 1, "F"))
ok(E.RemoveBlock(s2, 1, idxOf(s2, 1, "A")) == nil, "support released")

-- Cap
local s3 = E.NewState(synth)
local function fill(t, name, n)
    for _ = 1, n do E.Add(s3, t, idxOf(s3, t, name)) end
end
fill(1, "A", 5); fill(1, "B", 5); fill(1, "C", 1); fill(1, "D", 5); fill(1, "F", 3); fill(1, "R", 1); fill(1, "E", 2)
fill(2, "H", 5); fill(2, "I", 5); fill(2, "J", 5); fill(2, "K", 5); fill(2, "L", 5)
fill(3, "M", 5); fill(3, "N", 5); fill(3, "Q", 5); fill(3, "O", 4)
ok(E.TotalSpent(s3) == 61, "cap fill lands on 61 (" .. E.TotalSpent(s3) .. ")")
ok(E.AddBlock(s3, 3, idxOf(s3, 3, "O")).type == "CAP", "62nd point refused")
ok(E.RequiredLevel(s3) == 70, "61 points = level 70")

-- Export / import
local s4 = E.NewState(synth)
for _ = 1, 5 do E.Add(s4, 1, iA) end
for _ = 1, 4 do E.Add(s4, 1, iB) end
E.Add(s4, 1, iC)
for _ = 1, 5 do E.Add(s4, 1, iD) end
for _ = 1, 2 do E.Add(s4, 1, iE) end
-- Row-major digits: A5 B4 | C1 D5 F0 R0 | E2 | G0 -> "54150020" -> trimmed
ok(E.Export(s4) == "5415002", "export digit string (" .. E.Export(s4) .. ")")
local s5 = E.NewState(synth)
local okImp = E.Import(s5, "5415002")
ok(okImp, "import parses")
ok(E.Export(s5) == "5415002", "roundtrip stable")
ok(E.Signature(s5) == "17/0/0", "imported signature")
local s6 = E.NewState(synth)
ok(E.Import(s6, "https://www.wowhead.com/tbc/talent-calc/warrior/5415002"), "URL import")
ok(E.Export(s6) == "5415002", "URL roundtrip")
-- Multi-tree strings: the hyphen split must not shift trees
local sm = E.NewState(synth)
E.Add(sm, 1, iA); E.Add(sm, 1, iA)
E.Add(sm, 2, idxOf(sm, 2, "H")); E.Add(sm, 2, idxOf(sm, 2, "H")); E.Add(sm, 2, idxOf(sm, 2, "H"))
E.Add(sm, 3, idxOf(sm, 3, "M"))
ok(E.Export(sm) == "2-3-1", "multi-tree export (" .. E.Export(sm) .. ")")
local sm2 = E.NewState(synth)
ok(E.Import(sm2, "2-3-1"), "multi-tree import")
ok(E.Rank(sm2, 2, idxOf(sm2, 2, "H")) == 3, "tree 2 lands in tree 2")
ok(E.Rank(sm2, 3, idxOf(sm2, 3, "M")) == 1, "tree 3 lands in tree 3")
local sm3 = E.NewState(synth)
ok(E.Import(sm3, "2--1"), "empty middle tree import")
ok(E.Spent(sm3, 2) == 0 and E.Rank(sm3, 3, idxOf(sm3, 3, "M")) == 1, "empty middle tree respected")

local badOk, badErr = E.Import(E.NewState(synth), "9415002")
ok(not badOk and badErr ~= nil, "over-max digit refused")
ok(not E.Import(E.NewState(synth), "abc"), "garbage refused")
local emptyOk = E.Import(E.NewState(synth), "   ")
ok(not emptyOk, "blank refused")

-- Horizontal prerequisite convergence (R req F, same row)
local s7 = E.NewState(synth)
local applied, problems = E.ApplyBuild(s7, { points = { [1] = { A = 5, R = 1, F = 3 } } })
ok(#problems == 0, "horizontal prereq build applies clean")
ok(E.Rank(s7, 1, idxOf(s7, 1, "R")) == 1, "dependent landed")
ok(applied == 9, "applied count")

-- ApplyBuild problem reporting
local s8 = E.NewState(synth)
local _, probs8 = E.ApplyBuild(s8, { points = { [1] = { Zzz = 3 } } })
ok(#probs8 == 1 and probs8[1]:find("Zzz"), "unknown talent reported")
local s9 = E.NewState(synth)
local _, probs9 = E.ApplyBuild(s9, { points = { [1] = { C = 1 } } })
ok(#probs9 == 1 and probs9[1]:find("stuck"), "untierable point reported stuck")

-- Raw apply + serialize roundtrip
local s10 = E.NewState(synth)
local unknown = E.ApplyRaw(s10, { [1] = { A = 3, Zzz = 2 }, [2] = { H = 9 } })
ok(#unknown == 1 and unknown[1] == "Zzz", "raw apply reports unknown")
ok(E.Rank(s10, 2, idxOf(s10, 2, "H")) == 5, "raw apply clamps to max")
local ser = E.SerializePoints(s4)
local s11 = E.NewState(synth)
local _, serProbs = E.ApplyBuild(s11, { points = ser })
ok(#serProbs == 0, "serialized build re-applies")
ok(E.Signature(s11) == E.Signature(s4), "serialize roundtrip signature")

-- ---------------------------------------------------------------- real data
local census = {}
for _, token in ipairs(Data.ClassOrder) do
    local class = Data.Classes[token]
    if class then
        local expected = EXPECTED_SPECS[token]
        local st = E.NewState(class)
        ok(#class.trees == 3, token .. " has 3 trees")

        local have = {}
        for _, build in ipairs(class.builds or {}) do
            have[build.key] = true
            local _, bProbs = E.ApplyBuild(st, build)
            ok(#bProbs == 0, ("%s %s applies clean (%s)"):format(
                token, build.key, bProbs[1] or ""))
            ok(E.TotalSpent(st) == 61, ("%s %s totals 61 (got %d)"):format(
                token, build.key, E.TotalSpent(st)))
            local exported = E.Export(st)
            local st2 = E.NewState(class)
            local impOk = E.Import(st2, exported)
            ok(impOk and E.Export(st2) == exported,
                ("%s %s export/import roundtrip"):format(token, build.key))
            ok(type(build.stats) == "table" and #build.stats >= 3,
                ("%s %s has stat priorities"):format(token, build.key))
            census[#census + 1] = ("  %s %-14s %s"):format(token, build.key, E.Signature(st))
        end
        for _, key in ipairs(expected) do
            ok(have[key], ("%s covers Quartermaster spec %s"):format(token, key))
        end
    end
end

-- ---------------------------------------------------------------- verdict
print(("Commander_Talents harness — %d checks"):format(checks))
if #census > 0 then
    print("Preset builds:")
    for _, line in ipairs(census) do print(line) end
end
if #missing > 0 then
    print("NOTE: class data not yet present: " .. table.concat(missing, ", "))
end
if #failures > 0 then
    print(("%d FAILURE(S):"):format(#failures))
    for _, f in ipairs(failures) do print("  " .. f) end
    os.exit(1)
end
print("ALL CHECKS GREEN")
