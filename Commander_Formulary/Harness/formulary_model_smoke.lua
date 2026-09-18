-- Commander Formulary model smoke (luajit).
--
--   /opt/homebrew/bin/luajit formulary_model_smoke.lua
--
-- No mock: the generated data and the model are pure Lua. Proves the data
-- is well formed (every recipe has a teacher, every reference resolves) and
-- drives fixed characters through Build / Rows / HowToLearn. Silent on
-- success, exits non-zero on the first failure.

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then HERE = (os.getenv("PWD") or ".") .. "/" .. HERE end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ROOT = HERE:match("^(.*)/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns/Commander_Formulary"

dofile(ROOT .. "/CommanderFormularyData_Enchanting.lua")
dofile(ROOT .. "/CommanderFormularyModel.lua")

local D = CommanderFormulary_Data.ENCHANTING
local M = CommanderFormulary_Model

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end

local function World(rank, maxRank, known, bags, bank, faction, standings)
    bags, bank, known, standings = bags or {}, bank or {}, known or {}, standings or {}
    return {
        rank = rank, maxRank = maxRank, faction = faction,
        known = function(spell) return known[spell] == true end,
        count = function(item, includeBank) return (bags[item] or 0) + (includeBank and (bank[item] or 0) or 0) end,
        standing = function(f) return standings[f] end,
        name = function(item) return D.items[item] end,
        spellName = function(spell) return nil end,
    }
end

-- ===========================================================================
-- A. Data
-- ===========================================================================

local byKey = {}
for _, c in ipairs(D.categories) do byKey[c.key] = true end
local bySpell = {}
CHECK(#D.recipes >= 200, "A1 a full recipe list", #D.recipes)
for _, rec in ipairs(D.recipes) do
    bySpell[rec.spell] = rec
    CHECK(byKey[rec.category], "A1 category known", rec.name .. " " .. tostring(rec.category))
    CHECK(rec.yellow < rec.grey, "A1 yellow < grey", rec.name)
    CHECK(rec.creates or rec.enchant, "A1 makes something", rec.name)
    CHECK(rec.trainer or (rec.formulas and #rec.formulas > 0), "A1 has a teacher", rec.name)
    for _, pair in ipairs(rec.reagents) do
        CHECK(D.items[pair[1]] ~= nil, "A1 reagent named", rec.name .. " " .. pair[1])
    end
    for _, item in ipairs(rec.formulas or {}) do
        local f = D.formulas[item]
        CHECK(f ~= nil and f.learns == rec.spell, "A1 formula resolves back", rec.name .. " " .. item)
        CHECK(D.items[item] ~= nil, "A1 formula named", item)
    end
end
for item, f in pairs(D.formulas) do
    CHECK(bySpell[f.learns] ~= nil, "A2 formula teaches a listed recipe", item)
    local sourced = (f.vendors and #f.vendors > 0) or (f.drops and #f.drops > 0) or (f.zones and #f.zones > 0)
        or f.worldDrop or (f.quests and #f.quests > 0) or (f.objects and #f.objects > 0) or (f.containers and #f.containers > 0) or f.note
    CHECK(sourced, "A2 formula has a source", D.items[item])
    for _, v in ipairs(f.vendors or {}) do
        CHECK(D.npcs[v.npc] ~= nil and D.npcs[v.npc].zone ~= nil, "A2 vendor placed", item .. " " .. v.npc)
    end
    for _, d in ipairs(f.drops or {}) do
        CHECK(D.npcs[d.npc] ~= nil, "A2 dropper named", item .. " " .. d.npc)
    end
end
CHECK(#D.trainers >= 15, "A3 trainers listed", #D.trainers)
for _, t in ipairs(D.trainers) do
    CHECK(t.x and t.y and t.zone, "A3 trainer placed", t.name)
end
-- The route recipes of Commander_Tradecraft are all here with matching thresholds
CHECK(bySpell[7418] and bySpell[7418].yellow == 70 and bySpell[7418].grey == 110, "A4 Minor Health thresholds")
CHECK(bySpell[27924] and bySpell[27924].category == "FINGER", "A4 ring enchant categorised")
CHECK(bySpell[27984] and bySpell[27984].category == "WEAPON", "A4 Mongoose is a weapon enchant")
CHECK(bySpell[27977] and bySpell[27977].category == "TWOHAND", "A4 2H Major Agility is two-hand")
CHECK(bySpell[20017] and bySpell[20017].category == "SHIELD", "A4 shield enchant categorised")
CHECK(bySpell[7421] and bySpell[7421].category == "RODS" and bySpell[7421].trainer and bySpell[7421].trainer.withRank, "A4 copper rod comes with the rank")
CHECK(D.formulas[22559] and D.formulas[22559].drops[1].npc == 15687, "A4 Mongoose from Moroes")
CHECK(D.formulas[11039] and #D.formulas[11039].vendors >= 2, "A4 Minor Agility has its two vendors")
CHECK(D.formulas[22536] and D.formulas[22536].rep and D.formulas[22536].rep.standing == 5, "A4 Ring Spellpower needs Honored (ItemSparse 5)")

-- ===========================================================================
-- B. The view
-- ===========================================================================

-- B1 a mid-level enchanter
do
    local known = { [7418] = true, [7421] = true, [7457] = true, [13501] = true }
    local w = World(146, 150, known, { [11083] = 20, [11039] = 1 }, {}, "Horde", { [989] = 5 })
    local v = M.Build(D, w)
    CHECK(v.total == #D.recipes and v.known == 4, "B1 totals", v.known .. "/" .. v.total)
    local e = v.entries[13501]
    CHECK(e.known and e.colour == "orange", "B1 Lesser Stamina orange at 146", e.colour)
    CHECK(e.craftable == 10, "B1 craftable from 20 soul dust", e.craftable)
    local cloak = v.entries[13419]
    CHECK(not cloak.known and cloak.learnable == "held", "B1 formula in bags -> held", cloak.learnable)
    local stam = v.entries[7457]
    CHECK(stam.known, "B1 known")
    -- a trainer recipe at skill: learnable at the trainer
    local rod = v.entries[7795]
    CHECK(rod.learnable == "trainer" and rod.sourceWord == "Trainer", "B1 silver rod learnable at the trainer", rod.learnable)
    -- Ring - Spellpower: Keepers of Time Honored (item 5 -> client 6); standing 5 is Friendly, short
    local ring = v.entries[27924]
    CHECK(ring.learnable == nil, "B1 ring formula not buyable at Friendly")
    CHECK(ring.sourceKind == "REP", "B1 source word is Reputation", ring.sourceKind)
    -- a Horde character does not see Dalria as usable
    local f = D.formulas[11101]
    CHECK(M.VendorUsable(D, f, 12043, w) and not M.VendorUsable(D, f, 3954, w), "B1 faction vendor usability")
    local cat = v.byKey["WRIST"]
    CHECK(cat.known == 3 and cat.total >= 30, "B1 bracer category counts", cat.known .. "/" .. cat.total)
end

-- B2 filters, search and sort
do
    local w = World(146, 150, { [7418] = true, [13501] = true }, {}, {}, "Alliance")
    local v = M.Build(D, w)
    local rows, n = M.Rows(v, { filter = "ALL" }, w)
    CHECK(n == v.total, "B2 ALL shows everything", n)
    rows, n = M.Rows(v, { filter = "KNOWN" }, w)
    CHECK(n == 2, "B2 KNOWN shows two", n)
    rows, n = M.Rows(v, { filter = "UNKNOWN" }, w)
    CHECK(n == v.total - 2, "B2 UNKNOWN the rest", n)
    rows, n = M.Rows(v, { filter = "LEARNABLE" }, w)
    CHECK(n == v.learnable and n > 5, "B2 LEARNABLE matches the count", n)
    rows, n = M.Rows(v, { search = "mongoose" }, w)
    CHECK(n == 1 and rows[2].entry.spell == 27984, "B2 search by name", n)
    rows, n = M.Rows(v, { search = "moroes" }, w)
    CHECK(n >= 1, "B2 search by dropper", n)
    rows, n = M.Rows(v, { search = "soul dust" }, w)
    CHECK(n >= 5, "B2 search by reagent", n)
    rows, n = M.Rows(v, { search = "keepers of time" }, w)
    CHECK(n >= 1, "B2 search by faction", n)
    rows, n = M.Rows(v, { collapsed = { WRIST = true } }, w)
    local wristRows = 0
    for _, r in ipairs(rows) do if r.kind == "recipe" and r.entry.category == "WRIST" then wristRows = wristRows + 1 end end
    CHECK(wristRows == 0, "B2 collapsed category hides its rows")
    rows = M.Rows(v, { sort = "NAME", category = "WEAPON" }, w)
    local last
    local ok = true
    for _, r in ipairs(rows) do
        if r.kind == "recipe" then
            if last and last > r.entry.name then ok = false end
            last = r.entry.name
        end
    end
    CHECK(ok, "B2 sorted by name")
    rows = M.Rows(v, { sort = "SKILL", category = "WEAPON" }, w)
    local lastSkill = -1
    ok = true
    for _, r in ipairs(rows) do
        if r.kind == "recipe" then
            if r.entry.learnSkill < lastSkill then ok = false end
            lastSkill = r.entry.learnSkill
        end
    end
    CHECK(ok, "B2 sorted by skill")
end

-- B3 how to learn
do
    local w = World(300, 375, {}, { [22559] = 1 }, { [16224] = 1 }, "Horde", {})
    local v = M.Build(D, w)
    local lines = M.HowToLearn(D, v.entries[27984], w)
    CHECK(lines[1].kind == "formula" and lines[1].held, "B3 Mongoose formula held", lines[1].text)
    local sawDrop = false
    for _, l in ipairs(lines) do if l.kind == "drop" and l.npc == 15687 then sawDrop = true end end
    CHECK(sawDrop, "B3 Moroes listed")
    lines = M.HowToLearn(D, v.entries[20015], w)
    CHECK(lines[1].kind == "formula" and lines[1].banked, "B3 Superior Defense formula in the bank")
    local sawVendor = false
    for _, l in ipairs(lines) do if l.kind == "vendor" and l.npc == 12022 then sawVendor = true end end
    CHECK(sawVendor, "B3 Lorelae listed")
    lines = M.HowToLearn(D, v.entries[7457], w)
    CHECK(lines[1].kind == "trainer" and lines[1].skill == 50, "B3 trainer line", lines[1].text)
    lines = M.HowToLearn(D, v.entries[7421], w)
    CHECK(lines[1].text:find("Apprentice"), "B3 auto-learned line")
    CHECK(M.StandingName(5) == "Honored" and M.StandingName(6) == "Revered" and M.StandingName(7) == "Exalted", "B3 standing names")
    local nextRank, trainable = M.NextRank(D, v)
    CHECK(nextRank == nil, "B3 no next rank at 375 cap")
    v = M.Build(D, World(280, 300, {}))
    nextRank, trainable = M.NextRank(D, v)
    CHECK(nextRank.name == "Master" and trainable, "B3 master trainable at 280")
end

-- B4 a per-vendor reputation gate (Lokhtos, Thorium Brotherhood) is read
-- from the vendor row and compared with the client's off-by-one index
do
    local f = D.formulas[19448]
    CHECK(f and f.vendors[1].rep and f.vendors[1].rep.faction == 59 and f.vendors[1].rep.standing == 5, "B4 Mighty Spirit gated Honored on the vendor row", f and f.vendors[1].rep and f.vendors[1].rep.standing)
    local friendly = World(300, 300, {}, {}, {}, "Alliance", { [59] = 5 })
    local honored = World(300, 300, {}, {}, {}, "Alliance", { [59] = 6 })
    CHECK(not M.VendorUsable(D, f, 12944, friendly, f.vendors[1]), "B4 Friendly cannot buy")
    CHECK(M.VendorUsable(D, f, 12944, honored, f.vendors[1]), "B4 Honored can")
    local v = M.Build(D, honored)
    CHECK(v.entries[23803].learnable == "vendor" and v.entries[23803].sourceKind == "REP", "B4 learnable at Honored, word Reputation", v.entries[23803].learnable)
    local lines = M.HowToLearn(D, v.entries[23803], friendly)
    local saw = false
    for _, l in ipairs(lines) do if l.kind == "vendor" and l.text:find("Honored with Thorium Brotherhood") then saw = l end end
    CHECK(saw and not saw.usable, "B4 vendor line names the gate and is marked short", saw and saw.text)
end

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
