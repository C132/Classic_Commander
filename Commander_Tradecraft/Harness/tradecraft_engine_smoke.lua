-- Commander Tradecraft engine smoke (luajit).
--
--   /opt/homebrew/bin/luajit tradecraft_engine_smoke.lua
--
-- No mock at all: the data and engine files are pure Lua. Fixed characters
-- at fixed skill levels are pushed through Build and the answers are checked
-- against the guide and against arithmetic done by hand. Silent on success,
-- exits non-zero on the first failure.

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then HERE = (os.getenv("PWD") or ".") .. "/" .. HERE end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ROOT = HERE:match("^(.*)/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns/Commander_Tradecraft"

dofile(ROOT .. "/CommanderTradecraftData.lua")
dofile(ROOT .. "/CommanderTradecraftEngine.lua")

local D = CommanderTradecraft_Data
local E = CommanderTradecraft_Engine
local GUIDE = D.GUIDES.ENCHANTING

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end
local function near(a, b, tol) return math.abs(a - b) <= (tol or 0.5) end

-- A character: rank/maxRank, a set of known spells, a bag/bank table
local function World(rank, maxRank, known, bags, bank, faction)
    bags, bank, known = bags or {}, bank or {}, known or {}
    return {
        rank = rank, maxRank = maxRank, faction = faction,
        known = function(spell) return known[spell] == true end,
        count = function(item, includeBank)
            return (bags[item] or 0) + (includeBank and (bank[item] or 0) or 0)
        end,
        standing = function() return nil end,
    }
end

-- ===========================================================================
-- A. Data integrity
-- ===========================================================================

-- A1 every route step points at a recipe / formula that exists, and every
-- reagent and vendor it names is described
for _, segment in ipairs(GUIDE.segments) do
    for _, path in ipairs(segment.paths) do
        CHECK(#path.steps > 0, "A1 path has steps", segment.key)
        local lastTo = segment.from
        for _, def in ipairs(path.steps) do
            if def.kind == "craft" then
                local rec = D.RECIPES[def.spell]
                CHECK(rec ~= nil, "A1 recipe exists", def.spell)
                if rec then
                    CHECK(def.from == lastTo, "A1 craft steps are contiguous", segment.key .. " " .. def.from .. "/" .. lastTo)
                    lastTo = def.to
                    CHECK(rec.yellow < rec.grey, "A1 yellow < grey", rec.name)
                    CHECK(rec.green >= rec.yellow and rec.green <= rec.grey, "A1 green between", rec.name)
                    for _, pair in ipairs(rec.reagents) do
                        CHECK(D.ITEMS[pair[1]] ~= nil, "A1 reagent described", rec.name .. " " .. pair[1])
                        CHECK(pair[2] > 0, "A1 reagent count", rec.name)
                    end
                    CHECK(rec.target ~= nil or rec.creates ~= nil, "A1 recipe targets gear or makes something", rec.name)
                    -- A recipe reached by the route must not be grey before
                    -- the step ends
                    CHECK(def.to - 1 < rec.grey, "A1 step ends before grey", rec.name .. " to " .. def.to)
                    -- Formula-taught recipes name a formula that teaches them
                    if rec.formula then
                        CHECK(D.FORMULAS[rec.formula] and D.FORMULAS[rec.formula].learns == def.spell,
                            "A1 formula teaches its recipe", rec.name)
                    else
                        CHECK(rec.learn ~= nil, "A1 trainer recipe has a learn rank", rec.name)
                    end
                end
            elseif def.kind == "buy" then
                local f = D.FORMULAS[def.item]
                CHECK(f ~= nil, "A1 formula exists", def.item)
                CHECK(D.ITEMS[def.item] and D.ITEMS[def.item].formula, "A1 formula item described", def.item)
                if f then
                    for _, npc in ipairs(f.vendors) do
                        CHECK(D.VENDORS[npc] ~= nil, "A1 vendor described", npc)
                    end
                    CHECK(#f.vendors > 0, "A1 formula has a vendor", def.item)
                    -- A buy step precedes a craft step that uses what it teaches
                    local used = false
                    for _, seg2 in ipairs(GUIDE.segments) do
                        for _, p2 in ipairs(seg2.paths) do
                            for _, d2 in ipairs(p2.steps) do
                                if d2.kind == "craft" and d2.spell == f.learns then used = true end
                            end
                        end
                    end
                    CHECK(used, "A1 bought formula is crafted with", def.item)
                end
            else
                CHECK(false, "A1 unknown step kind", tostring(def.kind))
            end
        end
        CHECK(lastTo == segment.to, "A1 path reaches segment end", segment.key .. " " .. path.key)
    end
end

-- A2 segments are contiguous 1 -> 375
do
    local last = 1
    for _, segment in ipairs(GUIDE.segments) do
        CHECK(segment.from == last, "A2 segments contiguous", segment.key)
        last = segment.to
    end
    CHECK(last == 375, "A2 route ends at 375", last)
end

-- A3 every formula's vendor set includes someone each faction can use
for item, f in pairs(D.FORMULAS) do
    local alliance, horde = false, false
    for _, npc in ipairs(f.vendors) do
        local v = D.VENDORS[npc]
        if not v.faction or v.faction == "Alliance" then alliance = true end
        if not v.faction or v.faction == "Horde" then horde = true end
    end
    CHECK(alliance and horde, "A3 both factions can buy", D.ITEMS[item].name)
end

-- A4 the trainer ladder is sane and Master needs 275
do
    local ranks = D.PROFESSIONS.ENCHANTING.ranks
    for i = 2, #ranks do
        CHECK(ranks[i].cap > ranks[i - 1].cap, "A4 caps rise")
        CHECK(ranks[i].at < ranks[i - 1].cap, "A4 next rank trainable before the cap", ranks[i].name)
    end
    CHECK(ranks[#ranks].at == 275 and ranks[#ranks].cap == 375, "A4 Master at 275")
end

-- ===========================================================================
-- B. The skill-up model against the guide's own numbers
-- ===========================================================================

-- B1 Minor Health 2-90: 68 orange + 40*(H40 - H20) yellow ~= 95; guide 100
do
    local rec = D.RECIPES[7418]
    local expected = E.ExpectedCrafts(rec, 2, 90)
    CHECK(near(expected, 95.2, 1), "B1 Minor Health expectation", expected)
    -- 68 certain + ceil(27.2 * 1.1) = 98 planned against the guide's 100
    CHECK(E.PlannedCrafts(rec, 2, 90, 0.10) == 98, "B1 planned", E.PlannedCrafts(rec, 2, 90, 0.10))
end

-- B2 all-orange steps are exact
CHECK(E.ExpectedCrafts(D.RECIPES[7457], 90, 100) == 10, "B2 Minor Stamina exact 10")
CHECK(E.ExpectedCrafts(D.RECIPES[13501], 135, 155) == 20, "B2 Lesser Stamina exact 20")
CHECK(E.ExpectedCrafts(D.RECIPES[20015], 285, 299) == 14, "B2 Superior Defense exact 14")
CHECK(E.ExpectedCrafts(D.RECIPES[20017], 265, 285) == 20, "B2 Shield Greater Stamina exact 20")

-- B3 the model lands within 20% of the guide's count on every step. It is
-- usually under (the guide pads) and twice a hair over: Lesser Strength
-- 156-185 models at 36.2 against the guide's 35 and Bracer - Strength
-- 201-220 at 26.2 against 25, so the guide is the one being generous with
-- itself there.
for _, segment in ipairs(GUIDE.segments) do
    for _, def in ipairs(segment.paths[1].steps) do
        if def.kind == "craft" and def.count then
            local rec = D.RECIPES[def.spell]
            local expected = E.ExpectedCrafts(rec, def.from, def.to)
            CHECK(expected <= def.count * 1.2, "B3 model within 20% over guide", rec.name .. " " .. expected .. " vs " .. def.count)
            CHECK(expected >= def.count * 0.8, "B3 model within 20% under guide", rec.name .. " " .. expected .. " vs " .. def.count)
        end
    end
end

-- B3a the guide's count is a floor on the plan, pro rata for what is left
do
    local rec, def = D.RECIPES[20015], { count = 14, from = 285, to = 299 }
    CHECK(E.PlannedFor(rec, 285, 299, 0, def) == 14, "B3a whole step floors at the guide")
    CHECK(E.PlannedFor(rec, 292, 299, 0, def) == 7, "B3a half left floors at half")
    local big = D.RECIPES[13536]
    -- Lesser Strength models above its guide count (36.2 vs 35): the model wins
    CHECK(E.PlannedFor(big, 156, 185, 0, { count = 35, from = 156, to = 185 }) == 37, "B3a model above guide keeps the model", E.PlannedFor(big, 156, 185, 0, { count = 35, from = 156, to = 185 }))
end

-- B3b a single orange craft plans exactly one whatever the margin
CHECK(E.PlannedCrafts(D.RECIPES[7421], 1, 2, 0.5) == 1, "B3b one rod is one rod")
CHECK(E.PlannedCrafts(D.RECIPES[7457], 90, 100, 0.3) == 10, "B3b orange run gets no margin")

-- B4 chance and colour edges
do
    local rec = D.RECIPES[7418] -- 70 / 90 / 110
    CHECK(E.SkillUpChance(rec, 69) == 1, "B4 orange is certain")
    CHECK(near(E.SkillUpChance(rec, 70), 1, 0.001), "B4 yellow edge")
    CHECK(near(E.SkillUpChance(rec, 90), 0.5, 0.001), "B4 green midpoint is half")
    CHECK(E.SkillUpChance(rec, 110) == 0, "B4 grey is zero")
    CHECK(E.Colour(rec, 1) == "orange" and E.Colour(rec, 70) == "yellow"
        and E.Colour(rec, 90) == "green" and E.Colour(rec, 110) == "grey", "B4 colours")
    CHECK(E.ExpectedCrafts(rec, 100, 111) == math.huge, "B4 cannot cross grey")
    CHECK(E.ExpectedCrafts(rec, 50, 50) == 0, "B4 nothing to do is zero")
end

-- ===========================================================================
-- C. Building plans for characters
-- ===========================================================================

-- C1 a brand-new enchanter with nothing
do
    local plan = E.Build(GUIDE, World(1, 75, { [7421] = true, [7418] = true }, {}, {}, "Alliance"))
    CHECK(plan.hasProfession and not plan.finished, "C1 has profession")
    CHECK(plan.current and plan.current.kind == "craft" and plan.current.spell == 7421, "C1 first step is the copper rod")
    CHECK(plan.current.remaining == 1 and plan.current.planned == 1, "C1 one rod")
    CHECK(plan.current.known, "C1 rod recipe known")
    CHECK(plan.train == nil, "C1 no trainer yet at rank 1")
    -- Shopping covers the whole route, so Strange Dust is the copper rod's
    -- 1 + Minor Health + Minor Stamina 30 + silver rod 6
    local dust
    for _, row in ipairs(plan.shopping) do if row.id == 10940 then dust = row end end
    CHECK(dust ~= nil, "C1 strange dust on list")
    CHECK(dust and dust.need >= 130 and dust.need <= 145, "C1 strange dust ~137", dust and dust.need)
    CHECK(dust and dust.buy == dust.need, "C1 nothing held so buy everything")
    -- Runed rods never appear on the shopping list
    for _, row in ipairs(plan.shopping) do
        CHECK(not (D.ITEMS[row.id] and D.ITEMS[row.id].made), "C1 made rods not shopped", row.id)
    end
end

-- C2 the trainer banner appears at 50 and turns urgent at the cap
do
    local plan = E.Build(GUIDE, World(50, 75, { [7418] = true }))
    CHECK(plan.train and plan.train.rank.name == "Journeyman" and not plan.train.urgent, "C2 journeyman trainable at 50")
    plan = E.Build(GUIDE, World(75, 75, { [7418] = true }))
    CHECK(plan.train and plan.train.urgent, "C2 urgent at cap")
    CHECK(plan.current and plan.current.capped, "C2 current step flagged capped")
    plan = E.Build(GUIDE, World(75, 150, { [7418] = true }))
    CHECK(plan.train == nil, "C2 no banner once trained")
    plan = E.Build(GUIDE, World(0, 0, {}))
    CHECK(not plan.hasProfession and plan.train and plan.train.rank.name == "Apprentice" and plan.train.urgent, "C2 learn the profession first")
    plan = E.Build(GUIDE, World(280, 300, {}))
    CHECK(plan.train and plan.train.rank.name == "Master", "C2 master offered at 275+")
end

-- C3 a mid-route character: rank 146 with the cloak formula never bought
do
    local w = World(146, 150, { [13501] = true }, { [11083] = 10 }, { [11083] = 30 }, "Horde")
    local plan = E.Build(GUIDE, w)
    CHECK(plan.current and plan.current.spell == 13501, "C3 on Lesser Stamina", plan.current and plan.current.key)
    CHECK(plan.current.remaining == 9, "C3 nine more (all orange)", plan.current.remaining)
    CHECK(plan.current.guideCount == 9, "C3 guide count scaled", plan.current.guideCount)
    local dust = plan.current.reagents[1]
    CHECK(dust.id == 11083 and dust.have == 10 and dust.bank == 30, "C3 have/bank split")
    CHECK(dust.need == 2 * plan.current.planned, "C3 need is per * planned")
    -- The 110-135 buy step is behind us: not current, and not pending
    for _, step in ipairs(plan.steps) do
        if step.kind == "buy" and step.item == 11039 then
            CHECK(step.status == "done", "C3 passed formula is done", step.status)
        end
    end
    -- Train banner: Expert at 125+
    CHECK(plan.train and plan.train.rank.name == "Expert" and not plan.train.urgent, "C3 expert offered")
    -- Horde sees Kulwia, not Dalria, on the Lesser Strength buy step
    for _, step in ipairs(plan.steps) do
        if step.kind == "buy" and step.item == 11101 then
            CHECK(#step.vendors == 1 and step.vendors[1].name == "Kulwia", "C3 faction vendor filter", step.vendors[1] and step.vendors[1].name)
        end
    end
end

-- C4 buy step is current at the segment start, and holding the formula is
-- reported; learning it moves on
do
    local w = World(110, 150, { [7457] = true, [14807] = true })
    local plan = E.Build(GUIDE, w)
    CHECK(plan.current and plan.current.kind == "buy" and plan.current.item == 11039, "C4 buy step current at 110", plan.current and plan.current.key)
    CHECK(not plan.current.holding, "C4 not holding")
    w = World(110, 150, { [7457] = true }, { [11039] = 1 })
    plan = E.Build(GUIDE, w)
    CHECK(plan.current.holding, "C4 holding the formula")
    w = World(110, 150, { [13419] = true })
    plan = E.Build(GUIDE, w)
    CHECK(plan.current and plan.current.kind == "craft" and plan.current.spell == 13419, "C4 learned -> craft step")
    CHECK(plan.current.remaining == 25, "C4 25 minor agility", plan.current.remaining)
end

-- C5 alternatives: choosing the shield path drops the vendor trip
do
    local w = World(110, 150, { [13378] = true })
    local plan = E.Build(GUIDE, w, { choices = { ["110-135"] = "alt" } })
    CHECK(plan.current and plan.current.spell == 13378, "C5 alt path current", plan.current and plan.current.key)
    local sawBuy = false
    for _, step in ipairs(plan.steps) do
        if step.kind == "buy" and step.item == 11039 then sawBuy = true end
    end
    CHECK(not sawBuy, "C5 main path's buy step gone")
    CHECK(plan.current.alternatives, "C5 step knows it has alternatives")
    -- Shield - Minor Stamina turns yellow at 130, so 110-135 costs more
    CHECK(plan.current.remaining > 25, "C5 alt needs more crafts", plan.current.remaining)
    -- An unknown choice key falls back to the recommendation
    plan = E.Build(GUIDE, World(110, 150, {}), { choices = { ["110-135"] = "nonsense" } })
    CHECK(plan.current.kind == "buy", "C5 bad choice -> main path")
end

-- C6 skipping a step moves the current marker past it
do
    local w = World(110, 150, {})
    local plan = E.Build(GUIDE, w, { skipped = { ["110-135:main:1"] = true } })
    CHECK(plan.current and plan.current.kind == "craft" and plan.current.spell == 13419, "C6 skipped buy -> craft", plan.current and plan.current.key)
    CHECK(plan.steps[plan.current.index - 1].status == "skipped", "C6 skipped status kept")
    CHECK(plan.current.needsFormula == 11039, "C6 unknown formula recipe flagged")
end

-- C7 the Moonglade case: rank 299 with the Arcanite formula not learned is
-- still a buy step, not skipped as behind
do
    local w = World(299, 300, { [20015] = true })
    local plan = E.Build(GUIDE, w)
    CHECK(plan.current and plan.current.kind == "buy" and plan.current.item == 16243, "C7 arcanite formula still wanted at 299", plan.current and plan.current.key)
    -- and the Superior Defense formula's buy step, which IS behind, is done
    for _, step in ipairs(plan.steps) do
        if step.kind == "buy" and step.item == 16224 then
            CHECK(step.status == "done", "C7 superior defense formula done", step.status)
        end
    end
end

-- C7b at 285 with Superior Defense learned but the Arcanite formula not,
-- the craft step is current (the formula needs 290) and the buy step is
-- still ahead in the preview; at 290 it becomes current
do
    local w = World(285, 300, { [20015] = true })
    local plan = E.Build(GUIDE, w)
    CHECK(plan.current and plan.current.kind == "craft" and plan.current.spell == 20015, "C7b unlearnable formula does not block", plan.current and plan.current.key)
    local up = E.Upcoming(plan, 3)
    CHECK(up[1] and up[1].kind == "buy" and up[1].item == 16243, "C7b formula still previewed", up[1] and up[1].key)
    plan = E.Build(GUIDE, World(290, 300, { [20015] = true }))
    CHECK(plan.current and plan.current.kind == "buy" and plan.current.item == 16243, "C7b current once learnable", plan.current and plan.current.key)
    -- and with nothing else left, an unlearnable formula is still shown
    plan = E.Build(GUIDE, World(360, 375, { [33995] = true }, {}, {}, nil))
    CHECK(plan.current ~= nil, "C7b never without a current step while pending steps exist")
end

-- C8 a trainer-taught recipe you do not know yet says so
do
    local w = World(90, 150, {})
    local plan = E.Build(GUIDE, w)
    CHECK(plan.current.spell == 7457 and plan.current.needsTrainer == 50, "C8 Minor Stamina needs the trainer", plan.current.needsTrainer)
end

-- C9 the runed rod warning
do
    local w = World(100, 150, { [7795] = true }, { [6338] = 1, [10940] = 6, [10939] = 3 })
    local plan = E.Build(GUIDE, w)
    CHECK(plan.current.spell == 7795, "C9 silver rod step")
    CHECK(#plan.warnings == 1 and plan.warnings[1]:find("Runed Copper Rod"), "C9 missing copper rod warned", plan.warnings[1])
    w = World(100, 150, { [7795] = true }, { [6218] = 1 })
    plan = E.Build(GUIDE, w)
    CHECK(#plan.warnings == 0, "C9 holding it -> no warning")
end

-- C10 shopping subtracts bags and (by option) bank; sorted biggest buy first
do
    local w = World(300, 375, {}, { [22445] = 50 }, { [22445] = 100 })
    local plan = E.Build(GUIDE, w, nil, { bank = true })
    local arcane
    for _, row in ipairs(plan.shopping) do if row.id == 22445 then arcane = row end end
    CHECK(arcane and arcane.have == 50 and arcane.bank == 100, "C10 counts split")
    CHECK(arcane and arcane.buy == math.max(0, arcane.need - 150), "C10 bank counted")
    plan = E.Build(GUIDE, w, nil, { bank = false })
    for _, row in ipairs(plan.shopping) do if row.id == 22445 then arcane = row end end
    CHECK(arcane and arcane.buy == math.max(0, arcane.need - 50), "C10 bank ignored on option")
    for i = 2, #plan.shopping do
        CHECK(plan.shopping[i - 1].buy >= plan.shopping[i].buy, "C10 sorted by buy")
    end
    -- At 300 with nothing known the current step is the Superior Defense
    -- formula: the 301-317 step still needs it, so the Moonglade buy is
    -- not behind you just because 285-299 is
    CHECK(plan.current.kind == "buy" and plan.current.item == 16224, "C10 formula still wanted for 301-317", plan.current.key)
    -- Margin option changes planned counts on a yellow step
    local w2 = World(305, 375, { [20015] = true, [32664] = true })
    local a = E.Build(GUIDE, w2, nil, { margin = 0 }).current.planned
    local b = E.Build(GUIDE, w2, nil, { margin = 0.3 }).current.planned
    CHECK(b > a, "C10 margin raises planned", a .. " " .. b)
end

-- C11 finished
do
    local plan = E.Build(GUIDE, World(375, 375, {}))
    CHECK(plan.finished and plan.current == nil, "C11 finished has no current step")
    CHECK(#plan.shopping == 0, "C11 nothing to buy")
    CHECK(plan.doneSteps == plan.totalSteps, "C11 all steps done")
end

-- C12 upcoming preview skips done steps and stops at n
do
    local plan = E.Build(GUIDE, World(2, 75, { [7418] = true }))
    local up = E.Upcoming(plan, 2)
    CHECK(#up == 2 and up[1].spell == 7457 and up[2].spell == 7795, "C12 upcoming two", up[1] and up[1].key)
end

-- C13 the shopping total matches the guide's own list within its margin,
-- for a fresh character on the recommended route (the guide's list already
-- carries a margin, so the model at 10% should land close)
do
    local plan = E.Build(GUIDE, World(1, 75, { [7421] = true, [7418] = true }))
    local byId = {}
    for _, row in ipairs(plan.shopping) do byId[row.id] = row.need end
    local guide = {
        [10940] = 137, [11083] = 112, [11137] = 195, [11176] = 251, [16204] = 322,
        [22445] = 309, [22446] = 102, [22449] = 32, [10998] = 25, [8831] = 34, [8925] = 17,
        [22792] = 15, [18256] = 15, [4470] = 9, [10939] = 12, [16203] = 8, [14344] = 8,
    }
    for id, count in pairs(guide) do
        local got = byId[id] or 0
        CHECK(got >= count * 0.85 and got <= count * 1.15, "C13 shopping near guide", (D.ITEMS[id].name) .. " " .. got .. " vs " .. count)
    end
end

-- C15 brackets: one per trainer rank, steps tagged by where they start,
-- reagents split at the boundary, held stock allocated earliest first
do
    local plan = E.Build(GUIDE, World(1, 75, { [7421] = true, [7418] = true }, { [10940] = 50 }))
    CHECK(#plan.brackets == 5, "C15 five brackets", #plan.brackets)
    CHECK(plan.brackets[1].from == 1 and plan.brackets[1].to == 75 and plan.brackets[1].name == "Apprentice", "C15 first bracket")
    CHECK(plan.brackets[5].from == 300 and plan.brackets[5].to == 375, "C15 last bracket")
    CHECK(plan.bracket == plan.brackets[1] and plan.brackets[1].current, "C15 current bracket at rank 1")
    -- Minor Health 2-90 starts in bracket 1 and is listed there once
    local listed = 0
    for _, b in ipairs(plan.brackets) do
        for _, step in ipairs(b.steps) do if step.spell == 7418 then listed = listed + 1 end end
    end
    CHECK(listed == 1 and plan.steps[2].bracket == plan.brackets[1], "C15 straddling step listed once, where it starts")
    -- but its dust is split by model share of the step's planned 100 (the
    -- guide's floor): bracket 1 gets 1 (rod) + ceil(100 * 73.3/95.2) = 77,
    -- bracket 2 the yellow tail's share plus Minor Stamina and the silver rod
    local b1, b2 = plan.brackets[1].need[10940], plan.brackets[2].need[10940]
    CHECK(b1 == 78, "C15 bracket 1 strange dust", b1)
    CHECK(b2 and b2 > 30 + 6 and b2 < 74, "C15 bracket 2 strange dust", b2)
    -- The 50 held go to bracket 1 first; bracket 2 buys everything
    local function row(b, id) for _, r in ipairs(b.shopping) do if r.id == id then return r end end end
    local r1, r2 = row(plan.brackets[1], 10940), row(plan.brackets[2], 10940)
    CHECK(r1 and r1.covered == 50 and r1.buy == 28, "C15 held stock covers bracket 1 first", r1 and r1.buy)
    CHECK(r2 and r2.covered == 0 and r2.buy == r2.need, "C15 nothing left for bracket 2")
    -- Bracket sums equal the whole-route need (the split is exact for orange
    -- runs, and never under)
    local whole
    for _, r in ipairs(plan.shopping) do if r.id == 10940 then whole = r.need end end
    local sum = 0
    for _, b in ipairs(plan.brackets) do sum = sum + (b.need[10940] or 0) end
    CHECK(sum >= whole and sum <= whole + 5, "C15 bracket needs add up to the route", sum .. " vs " .. whole)
    -- A buy step lands in the bracket of its skill requirement
    for _, step in ipairs(plan.steps) do
        if step.kind == "buy" and step.item == 11039 then
            CHECK(step.bracket == plan.brackets[2], "C15 formula at 110 in 75-150")
        end
    end
    CHECK(plan.brackets[2].formulaCost == 800 + 2500, "C15 bracket formula cost", plan.brackets[2].formulaCost)
    -- Done brackets
    plan = E.Build(GUIDE, World(200, 225, {}))
    CHECK(plan.brackets[1].done and plan.brackets[2].done and not plan.brackets[3].done, "C15 done flags")
    CHECK(plan.bracket == plan.brackets[3], "C15 current bracket 150-225 at 200")
    CHECK(next(plan.brackets[1].need) == nil, "C15 nothing needed for a done bracket")
    plan = E.Build(GUIDE, World(375, 375, {}))
    CHECK(plan.bracket == plan.brackets[5], "C15 375 sits in the last bracket")
end

-- C14 helpers
CHECK(E.FormatMoney(0) == "0c" and E.FormatMoney(800) == "8s" and E.FormatMoney(100000) == "10g"
    and E.FormatMoney(12000) == "1g 20s" and E.FormatMoney(124) == "1s 24c", "C14 money", E.FormatMoney(12000))
do
    local plan = E.Build(GUIDE, World(1, 75, {}))
    local total = E.FormulaCosts(plan)
    -- Recommended route buys 11039 11101 20754 16217 16224 16243 22563 25848 22536
    CHECK(total == 800 + 2500 + 10000 + 12000 + 20000 + 22000 + 70000 + 100000 + 100000, "C14 formula total", total)
end

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
