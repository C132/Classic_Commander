-- Commander Tradecraft: the engine.
--
-- Pure Lua. Takes the guide (CommanderTradecraftData), what the client says
-- about the character (a `world` table of plain values and lookups), and the
-- character's own choices, and answers every question the window asks:
-- which step you are on, how many more crafts that is, what to buy, whether
-- a trainer is waiting. Nothing in here touches a frame or a WoW API, which
-- is what lets Harness/tradecraft_engine_smoke.lua prove it against a fixed
-- set of characters at fixed skill levels.
--
-- The world table:
--   rank, maxRank     the skill line's current and maximum rank (0, 0 when
--                     the profession is not known)
--   known(spell)      true when the character can cast this recipe
--   count(item, bank) how many the character holds; bank=true includes the
--                     bank, false is bags only
--   faction           "Alliance" | "Horde" | nil
--   standing(faction) reputation standing index with a faction id, or nil
--                     when unknown
--
-- The skill-up model is the one every leveling guide is built on: below the
-- yellow threshold a craft always skills up; between yellow and grey the
-- chance is (grey - rank) / (grey - yellow). Expected crafts from one rank
-- to another is the sum of the reciprocals, which is what the "about N more"
-- figure on the window is. The guide's own counts run roughly ten percent
-- over this, which is a sensible shopping margin and the default one.

CommanderTradecraft_Engine = {}
local E = CommanderTradecraft_Engine

local D = CommanderTradecraft_Data

E.DEFAULT_MARGIN = 0.10

-- ---------------------------------------------------------------------------
-- The skill-up model
-- ---------------------------------------------------------------------------

function E.SkillUpChance(recipe, rank)
    if rank < recipe.yellow then return 1 end
    if rank >= recipe.grey then return 0 end
    return (recipe.grey - rank) / (recipe.grey - recipe.yellow)
end

-- "orange" | "yellow" | "green" | "grey" — the colour the craft list shows
-- this recipe at this rank.
function E.Colour(recipe, rank)
    if rank >= recipe.grey then return "grey" end
    if rank >= recipe.green then return "green" end
    if rank >= recipe.yellow then return "yellow" end
    return "orange"
end

-- Expected number of crafts to take the skill from `from` to `to`, and as a
-- second value how many of those are certain (orange). math.huge when some
-- rank in between is grey (the recipe cannot get you there).
function E.ExpectedCrafts(recipe, from, to)
    if to <= from then return 0, 0 end
    local n, certain = 0, 0
    for rank = from, to - 1 do
        local p = E.SkillUpChance(recipe, rank)
        if p <= 0 then return math.huge, certain end
        n = n + 1 / p
        if p >= 1 then certain = certain + 1 end
    end
    return n, certain
end

-- The number to actually shop for. Orange crafts are certain and get no
-- margin — a one-craft rod step must plan one rod, not two — and the
-- margin goes on the yellow and green part, which is the only part luck
-- touches. Rounded up, never below one while any skill remains.
function E.PlannedCrafts(recipe, from, to, margin)
    local expected, certain = E.ExpectedCrafts(recipe, from, to)
    if expected == 0 then return 0 end
    if expected == math.huge then return math.huge end
    local uncertain = expected - certain
    local planned = certain + math.ceil(uncertain * (1 + (margin or E.DEFAULT_MARGIN)) - 1e-9)
    if planned < 1 then planned = 1 end
    return planned
end

-- What to plan for what is left of a step: the model with its margin, but
-- never fewer than the guide's own count for that stretch (pro rata by
-- skill points). The guide's figures are the ones people have levelled on;
-- the model is only allowed to raise them (a mid-route start, a bigger
-- margin), never to shave them.
function E.PlannedFor(recipe, lo, hi, margin, def)
    local planned = E.PlannedCrafts(recipe, lo, hi, margin)
    if def and def.count and planned ~= math.huge and hi > lo then
        local span = def.to - def.from
        local floor_ = (span > 0) and math.ceil(def.count * (hi - lo) / span - 1e-9) or def.count
        if floor_ > planned then planned = floor_ end
    end
    return planned
end

-- ---------------------------------------------------------------------------
-- Choices
-- ---------------------------------------------------------------------------

-- The path a character is taking through a segment: their choice if it
-- names a path the segment has, the first (recommended) path otherwise.
function E.PathFor(segment, choices)
    local want = choices and choices[segment.key]
    if want then
        for _, path in ipairs(segment.paths) do
            if path.key == want then return path end
        end
    end
    return segment.paths[1]
end

-- ---------------------------------------------------------------------------
-- Building the plan
-- ---------------------------------------------------------------------------

local function StepKey(segment, path, i)
    return segment.key .. ":" .. path.key .. ":" .. i
end

-- Every reagent line of a craft step, sized for `crafts` more casts.
local function ReagentLines(recipe, crafts, world, useBank)
    local lines = {}
    for _, pair in ipairs(recipe.reagents) do
        local id, per = pair[1], pair[2]
        local bags = world.count(id, false) or 0
        local total = world.count(id, true) or bags
        if total < bags then total = bags end
        local need = (crafts == math.huge) and math.huge or per * crafts
        lines[#lines + 1] = {
            id = id, per = per, need = need,
            have = bags, bank = total - bags,
            reachable = useBank and total or bags,
        }
    end
    return lines
end

-- Whether a buy step's formula is behind the character already: the recipe
-- is known, or the skill has passed every step that crafts with it so it no
-- longer matters. `usedUntil` is the highest `to` of any craft step on the
-- chosen route that uses the recipe — the Moonglade trip buys the Arcanite
-- rod's formula in the 285-299 segment for a step in the next one, so the
-- segment's own end is not the right test.
local function BuyDone(formula, segment, world, usedUntil)
    if world.known(formula.learns) then return true end
    local until_ = usedUntil[formula.learns] or segment.to
    if world.rank >= until_ then return true end
    return false
end

-- opts: margin (fraction, default 10%), bank (count the bank as reachable)
function E.Build(guide, world, state, opts)
    opts = opts or {}
    state = state or {}
    local choices = state.choices or {}
    local skipped = state.skipped or {}
    local margin = opts.margin or E.DEFAULT_MARGIN
    local useBank = opts.bank ~= false

    local prof = D.PROFESSIONS[guide.profession]
    local rank, maxRank = world.rank or 0, world.maxRank or 0
    local target = guide.segments[#guide.segments].to

    local plan = {
        guide = guide,
        profession = prof,
        rank = rank, maxRank = maxRank, target = target,
        hasProfession = maxRank > 0,
        finished = rank >= target,
        steps = {},
        current = nil,
        train = nil,
        shopping = {},
        warnings = {},
    }

    -- Brackets: one per trainer rank, bounded by the caps (1-75, 75-150,
    -- ...). They are the natural shopping trips — you buy for a bracket,
    -- level it, train, buy for the next — so the route and the shopping
    -- list are both grouped by them. A step belongs to the bracket it
    -- starts in; its reagents are split between every bracket it crosses.
    local brackets = {}
    if prof then
        local prevCap = 1
        for i, r in ipairs(prof.ranks) do
            brackets[#brackets + 1] = {
                index = i, rank = r, name = r.name,
                from = prevCap, to = r.cap,
                steps = {}, need = {}, shopping = {}, formulaCost = 0,
                done = rank >= r.cap,
            }
            prevCap = r.cap
        end
    end
    local function BracketAt(value)
        for _, b in ipairs(brackets) do
            if value < b.to then return b end
        end
        return brackets[#brackets]
    end
    plan.brackets = brackets
    plan.bracket = BracketAt(rank)
    if plan.bracket then plan.bracket.current = true end

    -- The chosen path through every segment, and how far each recipe is
    -- used along it (for deciding when a formula stops mattering)
    local paths, usedUntil = {}, {}
    for segIndex, segment in ipairs(guide.segments) do
        local path = E.PathFor(segment, choices)
        paths[segIndex] = path
        for _, def in ipairs(path.steps) do
            if def.kind == "craft" and def.to > (usedUntil[def.spell] or 0) then
                usedUntil[def.spell] = def.to
            end
        end
    end

    -- Flatten the chosen path of every segment into one ordered list
    local need = {} -- item id -> total planned need across pending steps
    for segIndex, segment in ipairs(guide.segments) do
        local path = paths[segIndex]
        for i, def in ipairs(path.steps) do
            local step = {
                key = StepKey(segment, path, i),
                index = #plan.steps + 1,
                segment = segment, segIndex = segIndex, path = path,
                kind = def.kind,
                alternatives = #segment.paths > 1,
            }
            plan.steps[#plan.steps + 1] = step

            if def.kind == "craft" then
                local recipe = D.RECIPES[def.spell]
                step.recipe = recipe
                step.spell = def.spell
                step.from, step.to, step.count = def.from, def.to, def.count
                step.known = world.known(def.spell) and true or false
                step.colour = E.Colour(recipe, rank)
                if rank >= def.to then
                    step.status = "done"
                    step.remaining, step.planned = 0, 0
                else
                    step.status = "pending"
                    local from = math.max(def.from, rank)
                    step.effectiveFrom = from
                    step.expected = E.ExpectedCrafts(recipe, from, def.to)
                    step.remaining = (step.expected == math.huge) and math.huge
                        or math.ceil(step.expected - 1e-9)
                    step.planned = E.PlannedFor(recipe, from, def.to, margin, def)
                    -- The guide's own figure, scaled to what is left
                    if def.count then
                        local span = def.to - def.from
                        local left = def.to - from
                        step.guideCount = (span > 0)
                            and math.ceil(def.count * left / span - 1e-9) or def.count
                    end
                    step.reagents = ReagentLines(recipe, step.planned, world, useBank)
                    for _, line in ipairs(step.reagents) do
                        if line.need ~= math.huge then
                            need[line.id] = (need[line.id] or 0) + line.need
                        end
                    end
                    -- The same reagents, split at every bracket boundary
                    -- the remaining range crosses. The step's planned total
                    -- is shared out by each part's share of the model — the
                    -- yellow tail of a step costs more per point than its
                    -- orange start, and a straight pro-rata split would
                    -- hand the first bracket dust the second one needs.
                    if step.planned ~= math.huge then
                        local parts, modelSum = {}, 0
                        for _, b in ipairs(brackets) do
                            local lo, hi = math.max(from, b.from), math.min(def.to, b.to)
                            if lo < hi then
                                local m = E.ExpectedCrafts(recipe, lo, hi)
                                parts[#parts + 1] = { b = b, model = m }
                                modelSum = modelSum + m
                            end
                        end
                        for _, part in ipairs(parts) do
                            local crafts = (modelSum > 0)
                                and math.ceil(step.planned * part.model / modelSum - 1e-9)
                                or step.planned
                            for _, pair in ipairs(recipe.reagents) do
                                part.b.need[pair[1]] = (part.b.need[pair[1]] or 0) + pair[2] * crafts
                            end
                        end
                    end
                end
                step.bracket = BracketAt(def.from)
            elseif def.kind == "buy" then
                local formula = D.FORMULAS[def.item]
                step.item = def.item
                step.formula = formula
                step.learns = formula.learns
                step.recipe = D.RECIPES[formula.learns]
                step.at = formula.at
                step.cost = formula.cost
                step.rep = formula.rep
                step.holding = (world.count(def.item, false) or 0) > 0
                -- Vendors the character can actually trade with, own
                -- faction's first, neutrals after, the other side's dropped
                step.vendors = {}
                for _, npc in ipairs(formula.vendors) do
                    local v = D.VENDORS[npc]
                    if v and (not v.faction or not world.faction or v.faction == world.faction) then
                        step.vendors[#step.vendors + 1] = v
                    end
                end
                if formula.rep and world.standing then
                    local have = world.standing(formula.rep.faction)
                    if have and have < formula.rep.standing then
                        step.repShort = true
                    end
                end
                step.status = BuyDone(formula, segment, world, usedUntil) and "done" or "pending"
                step.bracket = BracketAt(formula.at or segment.from)
            end
            if step.bracket then
                step.bracket.steps[#step.bracket.steps + 1] = step
            end

            if step.status ~= "done" and skipped[step.key] then
                step.status = "skipped"
            end
        end
    end

    -- The current step is the first one still pending that can be acted
    -- on. A formula you cannot learn yet (its skill requirement is above
    -- you) must not stand in front of the crafting that gets you there: the
    -- Moonglade trip buys the Arcanite rod's formula (needs 290) at 285, and
    -- Superior Defense has to be crafted meanwhile. Such a step stays
    -- pending, shows in the preview, and becomes current at its rank.
    local fallback
    for _, step in ipairs(plan.steps) do
        if step.status == "pending" then
            fallback = fallback or step
            local eligible = step.kind ~= "buy" or rank >= (step.at or 0)
            if eligible then
                plan.current = step
                break
            end
        end
    end
    plan.current = plan.current or fallback
    if plan.current then plan.current.status = "current" end

    -- A craft step whose recipe you do not know yet needs a trainer (or the
    -- formula, which is its own step); a step past your cap needs a rank.
    local cur = plan.current
    if cur and cur.kind == "craft" then
        if rank >= maxRank and maxRank > 0 then
            cur.capped = true
        end
        if not cur.known then
            if cur.recipe.formula then
                cur.needsFormula = cur.recipe.formula
            else
                cur.needsTrainer = cur.recipe.learn or 0
            end
        end
    end

    -- Trainer banner: the next rank up the ladder, once it is within reach
    if prof then
        for _, r in ipairs(prof.ranks) do
            if r.cap > maxRank then
                if maxRank == 0 or rank >= r.at then
                    plan.train = { rank = r, urgent = (maxRank == 0) or (rank >= maxRank) }
                end
                break
            end
        end
    end

    -- Shopping: everything still needed, less what is in reach. Rods you
    -- make along the way are never bought, and a missing one is a warning
    -- rather than a purchase.
    local list = {}
    for id, total in pairs(need) do
        local info = D.ITEMS[id]
        if not (info and info.made) then
            local bags = world.count(id, false) or 0
            local all = world.count(id, true) or bags
            if all < bags then all = bags end
            local reachable = useBank and all or bags
            list[#list + 1] = {
                id = id, need = total, have = bags, bank = all - bags,
                buy = math.max(0, total - reachable),
                note = info and info.note, vendor = info and info.vendor,
            }
        end
    end
    -- Biggest purchases first, then by id so an unchanged list never
    -- reorders itself between two refreshes
    table.sort(list, function(a, b)
        if a.buy ~= b.buy then return a.buy > b.buy end
        if a.need ~= b.need then return a.need > b.need end
        return a.id < b.id
    end)
    plan.shopping = list

    -- The same, per bracket. What you hold goes to the earliest bracket
    -- that wants it, and only what is left flows on to the next, so the
    -- first trip is the one your bank pays for.
    local held = {}
    for _, b in ipairs(brackets) do
        local rows = {}
        for id, total in pairs(b.need) do
            local info = D.ITEMS[id]
            if not (info and info.made) then
                if held[id] == nil then
                    local bags = world.count(id, false) or 0
                    local all = world.count(id, true) or bags
                    if all < bags then all = bags end
                    held[id] = useBank and all or bags
                end
                local covered = math.min(held[id], total)
                held[id] = held[id] - covered
                rows[#rows + 1] = {
                    id = id, need = total, covered = covered,
                    buy = total - covered,
                    have = world.count(id, false) or 0,
                    note = info and info.note, vendor = info and info.vendor,
                }
            end
        end
        table.sort(rows, function(x, y)
            if x.buy ~= y.buy then return x.buy > y.buy end
            if x.need ~= y.need then return x.need > y.need end
            return x.id < y.id
        end)
        b.shopping = rows
        for _, step in ipairs(b.steps) do
            if step.kind == "buy" and step.status ~= "done" and step.status ~= "skipped" then
                b.formulaCost = b.formulaCost + (step.cost or 0)
            end
        end
    end

    -- Warnings: a runed rod that a later step needs and that you do not hold
    if cur and cur.kind == "craft" and cur.reagents then
        for _, line in ipairs(cur.reagents) do
            local info = D.ITEMS[line.id]
            if info and info.made and line.reachable < line.need then
                plan.warnings[#plan.warnings + 1] = ("You need your %s for this — it is a reagent, not just a tool."):format(info.name)
            end
        end
    end

    -- Progress bookkeeping for the header
    local doneSteps = 0
    for _, step in ipairs(plan.steps) do
        if step.status == "done" or step.status == "skipped" then doneSteps = doneSteps + 1 end
    end
    plan.doneSteps, plan.totalSteps = doneSteps, #plan.steps

    return plan
end

-- ---------------------------------------------------------------------------
-- Questions the window asks after Build
-- ---------------------------------------------------------------------------

-- The next few pending steps, for the preview lines. Route order, which
-- puts a deferred formula (pending, but earlier in the list than the
-- current craft step because it cannot be learned yet) first.
function E.Upcoming(plan, n)
    local out = {}
    if not plan.current or n <= 0 then return out end
    for _, step in ipairs(plan.steps) do
        if step.status == "pending" then
            out[#out + 1] = step
            if #out >= n then break end
        end
    end
    return out
end

-- Text for a step's title line, without the client (names come from data;
-- the window swaps in localised ones where it can).
function E.StepTitle(step)
    if step.kind == "craft" then
        return step.recipe.name
    elseif step.kind == "buy" then
        local info = D.ITEMS[step.item]
        return "Buy " .. (info and info.name or ("item " .. step.item))
    end
    return "?"
end

-- Money as the client prints it, without the client
function E.FormatMoney(copper)
    copper = math.floor(copper or 0)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    -- Only the denominations that carry anything: "10g", "8s", "1g 20s"
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

-- The whole-route shopping list as a table of rows suitable for the shopping
-- window, and also the total cost of every formula still to buy.
function E.FormulaCosts(plan)
    local total = 0
    for _, step in ipairs(plan.steps) do
        if step.kind == "buy" and (step.status == "current" or step.status == "pending") then
            total = total + (step.cost or 0)
        end
    end
    return total
end
