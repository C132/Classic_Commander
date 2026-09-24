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
dofile(ROOT .. "/CommanderFormularyData_FirstAid.lua")
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

local function World(rank, maxRank, known, bags, bank, faction, standings, data)
    bags, bank, known, standings, data = bags or {}, bank or {}, known or {}, standings or {}, data or D
    return {
        rank = rank, maxRank = maxRank, faction = faction,
        known = function(spell) return known[spell] == true end,
        count = function(item, includeBank) return (bags[item] or 0) + (includeBank and (bank[item] or 0) or 0) end,
        standing = function(f) return standings[f] end,
        name = function(item) return data.items[item] end,
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

-- B5 the CRAFTABLE filter, the vendor shopping figure, and formula verdicts
do
    local w = World(146, 150, { [13501] = true, [7418] = true }, { [11083] = 20 }, {}, "Alliance", {})
    local v = M.Build(D, w)
    local rows, n = M.Rows(v, { filter = "CRAFTABLE" }, w)
    CHECK(n == 1 and rows[2].entry.spell == 13501, "B5 craftable = known with reagents", n)
    local count, cost = M.VendorShopping(D, v, w)
    CHECK(count >= 1 and cost >= 800, "B5 vendor shopping counts Minor Agility (8s) at least", count .. " " .. cost)
    local verdict = M.FormulaVerdict(D, 11039, w)
    CHECK(verdict and not verdict.known and verdict.atSkill and verdict.skill == 110, "B5 verdict: learnable now")
    verdict = M.FormulaVerdict(D, 22559, w)
    CHECK(verdict and not verdict.atSkill and verdict.skill == 375, "B5 verdict: needs skill")
    verdict = M.FormulaVerdict(D, 6217, w)
    CHECK(verdict == nil, "B5 a copper rod is not a formula")
    w = World(146, 150, { [13419] = true }, {}, {}, "Alliance", {})
    verdict = M.FormulaVerdict(D, 11039, w)
    CHECK(verdict and verdict.known, "B5 verdict: already known")
end

-- B6 economics: cast cost, profit, formula price, the PROFITABLE filter
do
    local PRICES = { [22445] = 2000, [22446] = 15000, [22450] = 40000, [22449] = 30000, [22792] = 500, [22522] = 9000,
        [10939] = 1500, [11288] = 4000, [11039] = 5000 }
    local w = World(360, 375, { [28019] = true, [45765] = true, [14807] = true }, {}, {}, "Alliance", {})
    w.price = function(item) return PRICES[item] end
    local v = M.Build(D, w)
    -- Superior Wizard Oil: 3 dust (60s) + vine (5s) + imbued vial (vendor 2g) = 2g 65s; sells 90s -> a loss
    local oil = v.entries[28019]
    CHECK(oil.castCost == 6000 + 500 + 20000 and oil.castPriced, "B6 oil cast cost uses the vendor vial", oil.castCost)
    CHECK(oil.profit == 9000 - 26500, "B6 oil profit (a loss)", oil.profit)
    -- Void Shatter: one Void Crystal (4g) -> TWO Large Prismatic Shards (3g each) = +2g
    local vs = v.entries[45765]
    CHECK(vs.profit == 60000 - 40000 and vs.productValue == 60000, "B6 Void Shatter makes two", vs.profit)
    -- Greater Magic Wand: Simple Wood (vendor 38c) + GME 15s -> 40s wand = +24s 62c
    local wand = v.entries[14807]
    CHECK(wand.profit == 4000 - 38 - 1500, "B6 wand profit", wand.profit)
    local rows, n = M.Rows(v, { filter = "PROFITABLE" }, w)
    CHECK(n == 2, "B6 profitable filter: shatter and wand", n)
    -- Formula price: the cheapest usable vendor, else the AH for BoE
    CHECK(v.entries[13419].formulaPrice == 800, "B6 vendor formula priced at the vendor", v.entries[13419].formulaPrice)
    -- unpriced reagent -> no profit figure
    CHECK(v.entries[20015].castPriced == false and v.entries[20015].profit == nil, "B6 unpriced stays nil")
end

-- B7 disenchanting: brackets and value
do
    local res, bracket = M.Disenchant(D, 2, 4, 60)
    CHECK(res ~= nil and bracket.min <= 60 and bracket.max >= 60, "B7 green armour ilvl 60 has a bracket")
    local top = res[1]
    CHECK(top[1] == 16204 and top[2] >= 70, "B7 green armour 56-60 is mostly Illusion Dust", top[1] .. " " .. top[2])
    res = M.Disenchant(D, 2, 2, 60)
    CHECK(res[1][1] == 16203, "B7 green WEAPON 56-60 is mostly Greater Eternal Essence", res[1][1])
    res = M.Disenchant(D, 3, 4, 115)
    CHECK(res[1][1] == 22449, "B7 blue armour 115 is a Large Prismatic Shard", res[1][1])
    res = M.Disenchant(D, 4, 4, 120)
    CHECK(res[1][1] == 22450, "B7 epic 120 is a Void Crystal", res[1][1])
    -- The empty 66-78 stretch belongs to Outland: Arcane Dust, not Illusion
    res = M.Disenchant(D, 2, 4, 70)
    CHECK(res and res[1][1] == 22445, "B7 green armour 70 -> Arcane Dust", res and res[1][1])
    res = M.Disenchant(D, 2, 4, 65)
    CHECK(res and res[1][1] == 16204, "B7 green armour 65 -> Illusion Dust", res and res[1][1])
    CHECK(M.Disenchant(D, 1, 4, 60) == nil, "B7 a white item is not disenchantable")
    CHECK(M.Disenchant(D, 2, 7, 60) == nil, "B7 a trade good is not")
    local w = World(300, 375, {}, {}, {}, "Alliance", {})
    w.price = function(item) return ({ [16204] = 5000, [16203] = 12000, [14344] = 36000 })[item] end
    local value, priced = M.DisenchantValue(M.Disenchant(D, 2, 4, 60), w)
    CHECK(priced and value > 5000 and value < 15000, "B7 expected value in a sane range", value)
    local best = M.DisposalVerdict(value, 3000, 6000)
    CHECK(best == "disenchant", "B7 verdict: disenchant beats vendor and auction", best)
    CHECK(M.DisposalVerdict(nil, 3000, 6000) == "auction", "B7 no DE price -> auction")
    CHECK(M.DisposalVerdict(nil, 3000, nil) == "vendor", "B7 only vendor known")
end

-- B8 trips: unknown vendor formulas by zone
do
    local w = World(300, 375, {}, {}, {}, "Horde", { [989] = 6, [933] = 5 })
    local v = M.Build(D, w)
    local trips = M.Trips(v, w)
    CHECK(#trips >= 5, "B8 several zones", #trips)
    local moonglade, ashenvale
    for _, z in ipairs(trips) do
        if z.zone == "Moonglade" then moonglade = z end
        if z.zone == "Ashenvale" then ashenvale = z end
    end
    CHECK(moonglade and moonglade.count >= 2 and moonglade.stops[1].name == "Lorelae Wintersong", "B8 Moonglade is one stop with both formulas", moonglade and moonglade.count)
    CHECK(moonglade.cost >= 22000 + 20000, "B8 zone cost totals", moonglade.cost)
    CHECK(ashenvale == nil, "B8 Horde does not see Dalria's Ashenvale")
    -- Keepers of Time at Honored (6): the Tanaris trip is ready; Consortium at Friendly: Netherstorm listed but short
    local tanaris, nether
    for _, z in ipairs(trips) do
        if z.zone == "Tanaris" then tanaris = z end
        if z.zone == "Netherstorm" then nether = z end
    end
    local function anyShort(z, want)
        for _, stop in ipairs(z.stops) do
            for _, f in ipairs(stop.formulas) do if (f.repShort and true or false) == want then return true end end
        end
        return false
    end
    CHECK(tanaris and anyShort(tanaris, false), "B8 something at Alurmi is ready at Honored")
    CHECK(nether and anyShort(nether, true), "B8 Netherstorm listed with something short of Consortium standing")
    CHECK(trips[1].count >= trips[#trips].count, "B8 sorted most formulas first")
    -- a known formula is no longer part of the trip
    local before = moonglade.count
    w = World(300, 375, { [20015] = true, [20051] = true }, {}, {}, "Horde", {})
    v = M.Build(D, w)
    trips = M.Trips(v, w)
    local after = 0
    for _, z in ipairs(trips) do if z.zone == "Moonglade" then after = z.count end end
    CHECK(after == before - 2, "B8 known formulas drop out of the trip", before .. " -> " .. after)
end

-- ===========================================================================
-- C. First Aid: the same shape, generated the same way
-- ===========================================================================

local FA = CommanderFormulary_Data.FIRSTAID
do
    CHECK(FA and FA.key == "FIRSTAID" and FA.frame == "TRADESKILL" and FA.skillLine == 129, "C1 First Aid is a trade-skill profession")
    local keys = {}
    for _, c in ipairs(FA.categories) do keys[c.key] = true end
    local faSpell = {}
    CHECK(#FA.recipes == 15, "C1 fifteen obtainable recipes (Crystal Infused Bandage was never added)", #FA.recipes)
    for _, rec in ipairs(FA.recipes) do
        faSpell[rec.spell] = rec
        CHECK(keys[rec.category], "C1 category known", rec.name)
        CHECK(rec.yellow < rec.grey and rec.creates, "C1 thresholds and a product", rec.name)
        CHECK(rec.trainer or (rec.formulas and #rec.formulas > 0), "C1 has a teacher", rec.name)
        for _, pair in ipairs(rec.reagents) do CHECK(FA.items[pair[1]] ~= nil, "C1 reagent named", rec.name) end
        for _, item in ipairs(rec.formulas or {}) do
            CHECK(FA.formulas[item] and FA.formulas[item].learns == rec.spell and FA.items[item], "C1 manual resolves back", rec.name)
        end
    end
    for item, f in pairs(FA.formulas) do
        CHECK(faSpell[f.learns] ~= nil, "C2 manual teaches a listed recipe", item)
        local sourced = (f.vendors and #f.vendors > 0) or f.worldDrop or (f.drops and #f.drops > 0)
        CHECK(sourced, "C2 manual has a source", FA.items[item])
        for _, v in ipairs(f.vendors or {}) do
            CHECK(FA.npcs[v.npc] and FA.npcs[v.npc].zone, "C2 vendor placed", item .. " " .. v.npc)
        end
    end
    -- The facts the route is built on, from the client's own tables
    CHECK(faSpell[3275].trainer and faSpell[3275].trainer.withRank, "C3 Linen Bandage comes with the rank")
    CHECK(faSpell[3276].yellow == 50 and faSpell[3276].grey == 100 and faSpell[3276].trainer.skill == 40, "C3 Heavy Linen thresholds and trainer skill")
    CHECK(faSpell[7929].formulas[1] == 16112 and FA.formulas[16112].skill == 180, "C3 Heavy Silk Bandage is a manual at 180")
    CHECK(faSpell[10841].trainer and faSpell[10841].trainer.skill == 240, "C3 Heavy Mageweave is trainer-taught at 240")
    CHECK(faSpell[18630].trainer and faSpell[18630].trainer.skill == 290, "C3 Heavy Runecloth is trainer-taught at 290")
    CHECK(faSpell[27032].formulas[1] == 21992 and faSpell[27033].formulas[1] == 21993, "C3 the Netherweave manuals")
    CHECK(faSpell[7934].makes == 3 and faSpell[7934].category == "ANTIVENOM", "C3 Anti-Venom makes three")
    CHECK(FA.formulas[6454].worldDrop and FA.formulas[6454].worldDrop.mobs > 300, "C3 Strong Anti-Venom's manual is a world drop")
    CHECK(FA.formulas[19442].rep and FA.formulas[19442].rep.faction == 529 and FA.formulas[19442].rep.standing == 5 and FA.formulas[19442].bop,
        "C3 Powerful Anti-Venom needs Argent Dawn Honored and binds")
    -- The two vendors of the classic manuals and the Expert book, placed
    -- where the published guide puts them (Stromgarde; Brackenwall)
    local deneb, balai = FA.npcs[2805], FA.npcs[13476]
    CHECK(deneb and deneb.zone == "Arathi Highlands" and math.abs(deneb.x - 27.0) < 1 and math.abs(deneb.y - 58.8) < 1, "C4 Deneb Walker at Stromgarde", deneb and (deneb.zone .. " " .. deneb.x .. "," .. deneb.y))
    CHECK(balai and balai.zone == "Dustwallow Marsh" and math.abs(balai.x - 36.5) < 1 and math.abs(balai.y - 30.4) < 1, "C4 Balai Lok'Wein at Brackenwall", balai and (balai.zone .. " " .. balai.x .. "," .. balai.y))
    CHECK(deneb.faction == "Alliance" and balai.faction == "Horde", "C4 one per faction")
    -- The rank ladder: two trainer ranks, a book, a quest, a book
    local r = FA.ranks
    CHECK(#r == 5 and not r[1].book and not r[2].book, "C5 Apprentice and Journeyman from a trainer")
    CHECK(r[3].book and r[3].book.item == 16084 and r[3].book.skill == 125 and #r[3].book.vendors == 2, "C5 Expert is a book from two vendors")
    CHECK(r[4].quests and #r[4].quests == 2 and r[4].quests[1].name == "Triage" and r[4].at == 225, "C5 Artisan is the Triage quest at 225")
    CHECK(r[5].book and r[5].book.item == 22012 and r[5].book.skill == 300 and r[5].outland, "C5 Master is a book at 300, in Outland")
    for _, q in ipairs(r[4].quests) do
        CHECK(FA.npcs[q.npc] and FA.npcs[q.npc].x, "C5 quest giver placed", q.npc)
    end
    CHECK(not M.MasterFromTrainer(FA) and M.MasterFromTrainer(D), "C5 no First Aid trainer teaches Master; an Enchanting one does")

    -- C6 the view for a First Aider at 200 with Expert, Alliance
    local known = { [3275] = true, [3276] = true, [3277] = true, [3278] = true, [7928] = true, [7929] = true }
    local w = World(200, 225, known, { [4306] = 30, [16113] = 1 }, {}, "Alliance", {}, FA)
    local v = M.Build(FA, w)
    CHECK(v.total == 15 and v.known == 6, "C6 totals", v.known .. "/" .. v.total)
    CHECK(v.entries[7929].known and v.entries[7929].colour == "yellow", "C6 Heavy Silk yellow at 200", v.entries[7929].colour)
    CHECK(v.entries[7929].craftable == 15, "C6 fifteen heavy silk from thirty silk", v.entries[7929].craftable)
    CHECK(v.entries[10840].learnable == "held-soon", "C6 the Mageweave manual in the bags, ten skill early", v.entries[10840].learnable)
    CHECK(v.entries[10841].learnable == nil and v.entries[10841].sourceWord == "Trainer", "C6 Heavy Mageweave waits for 240", v.entries[10841].sourceWord)
    -- A world drop with a few notable droppers reads as Drop, the same as
    -- an Enchanting formula in that position (the notable ones are named)
    CHECK(v.entries[7935].sourceKind == "DROP" and M.Sources(FA, v.entries[7935].rec).WORLD, "C6 Strong Anti-Venom drops, and is a world drop", v.entries[7935].sourceKind)
    local nextRank, within = M.NextRank(FA, v)
    CHECK(nextRank and nextRank.name == "Artisan" and not within, "C6 next rank Artisan, not yet at 225")
    local route = M.RankRoute(FA, nextRank, w)
    CHECK(#route == 1 and route[1].kind == "quest" and route[1].text:find("Triage") and route[1].text:find("VanHowzen") and not route[1].text:find("Victor"),
        "C6 the Alliance doctor only", route[1] and route[1].text)
    local expert = M.RankRoute(FA, FA.ranks[3], w)
    CHECK(#expert == 2 and expert[1].kind == "book" and expert[2].kind == "vendor" and expert[2].text:find("Deneb"), "C6 Expert: the book and the Alliance vendor", expert[2] and expert[2].text)
    local master = M.RankRoute(FA, FA.ranks[5], w)
    CHECK(#master == 2 and master[2].text:find("Burko"), "C6 Master: Burko for the Alliance", master[2] and master[2].text)
    local ench = M.RankRoute(D, D.ranks[5], w)
    CHECK(#ench == 1 and ench[1].kind == "trainer" and ench[1].outland, "C6 Master Enchanting is an Outland trainer")
    -- how to learn, in the profession's own words
    local lines = M.HowToLearn(FA, v.entries[3275], w)
    CHECK(lines[1].text:find("Apprentice First Aid itself"), "C6 Linen Bandage comes with Apprentice First Aid", lines[1].text)
    lines = M.HowToLearn(FA, v.entries[10841], w)
    CHECK(lines[1].text:find("First Aid trainers at 240"), "C6 trainer line names the profession", lines[1].text)
    -- the trips filter finds the Burko trip
    local trips = M.Trips(v, w)
    local hellfire
    for _, z in ipairs(trips) do if z.zone == "Hellfire Peninsula" then hellfire = z end end
    CHECK(hellfire and hellfire.count == 2, "C6 one Hellfire trip for both Netherweave manuals", hellfire and hellfire.count)
end

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
