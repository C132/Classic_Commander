-- Commander Formulary: the model.
--
-- Pure Lua. Takes a profession's generated data (CommanderFormulary_Data.X)
-- and a `world` table of plain lookups, and answers what the window asks:
-- which recipes are known, which could be learned right now and how, what
-- each one would cost to craft against the bags, how complete each slot is,
-- and the filtered, searched, sorted list of rows to paint. Nothing here
-- touches a frame or a WoW API, which is what lets the harness prove it.
--
-- The world table:
--   rank, maxRank          the skill line (0, 0 when not known)
--   known(spell)           the character can cast this recipe
--   count(item, bank)      how many of an item is held (bank=true includes it)
--   faction                "Alliance" | "Horde" | nil
--   standing(factionId)    reputation standing index, or nil
--   name(item)             localised item name, or nil
--   spellName(spell)       localised spell name, or nil
--   price(item)            optional: auction price in copper, or nil
--   vendorSell(item)       optional: what a vendor pays for one, or nil

CommanderFormulary_Model = {}
local M = CommanderFormulary_Model

M.FILTERS = { "ALL", "KNOWN", "CRAFTABLE", "PROFITABLE", "UNKNOWN", "LEARNABLE", "TRIPS" }
M.SORTS = { "SKILL", "NAME" }

-- ---------------------------------------------------------------------------
-- Colour
-- ---------------------------------------------------------------------------

function M.Colour(rec, rank)
    if rank >= rec.grey then return "grey" end
    local green = math.floor((rec.yellow + rec.grey) / 2)
    if rank >= green then return "green" end
    if rank >= rec.yellow then return "yellow" end
    return "orange"
end

-- ---------------------------------------------------------------------------
-- Learning
-- ---------------------------------------------------------------------------

-- The lowest skill at which the recipe can be learned by any route
function M.LearnSkill(data, rec)
    local best
    if rec.trainer then best = rec.trainer.skill end
    for _, item in ipairs(rec.formulas or {}) do
        local f = data.formulas[item]
        if f and (not best or f.skill < best) then best = f.skill end
    end
    return best or 0
end

-- The kinds of source a recipe has, as a set: TRAINER, VENDOR, DROP, QUEST,
-- WORLD, OBJECT, CONTAINER, REP (a vendor behind a reputation gate)
function M.Sources(data, rec)
    local kinds = {}
    if rec.trainer then kinds.TRAINER = true end
    for _, item in ipairs(rec.formulas or {}) do
        local f = data.formulas[item]
        if f then
            if f.vendors and #f.vendors > 0 then
                kinds.VENDOR = true
                if f.rep then kinds.REP = true end
                for _, v in ipairs(f.vendors) do
                    if v.rep then kinds.REP = true end
                end
            end
            if (f.drops and #f.drops > 0) or (f.zones and #f.zones > 0) then kinds.DROP = true end
            if f.worldDrop then kinds.WORLD = true end
            if f.quests and #f.quests > 0 then kinds.QUEST = true end
            if f.objects and #f.objects > 0 then kinds.OBJECT = true end
            if f.containers and #f.containers > 0 then kinds.CONTAINER = true end
            if f.note then kinds.NOTE = true end
        end
    end
    return kinds
end

-- One word for the list column
local SOURCE_WORD = { TRAINER = "Trainer", VENDOR = "Vendor", REP = "Reputation", DROP = "Drop", WORLD = "World drop",
    QUEST = "Quest", OBJECT = "Chest", CONTAINER = "Container", NOTE = "Special" }
local SOURCE_ORDER = { "TRAINER", "REP", "VENDOR", "QUEST", "DROP", "WORLD", "OBJECT", "CONTAINER", "NOTE" }

function M.SourceWord(kinds)
    for _, k in ipairs(SOURCE_ORDER) do
        if kinds[k] then return SOURCE_WORD[k], k end
    end
    return "Unknown", nil
end

-- The reputation gate on buying a formula from a vendor: the vendor row's
-- own (Lokhtos in Blackrock Depths gates per item), else the item's
function M.VendorGate(formula, vendor)
    if vendor and vendor.rep then return vendor.rep end
    return formula.rep
end

-- Whether a vendor can be used by this character (faction and standing)
function M.VendorUsable(data, formula, npc, world, vendor)
    local info = data.npcs[npc]
    if info and info.faction and world.faction and info.faction ~= world.faction then
        return false, "other faction"
    end
    local gate = M.VendorGate(formula, vendor)
    if gate and world.standing then
        local have = world.standing(gate.faction)
        -- ItemSparse counts standings from Hated = 0 (Honored 5); the client's
        -- index counts from Hated = 1 (Honored 6). Off by one, always.
        if have and have < gate.standing + 1 then
            return false, "reputation"
        end
    end
    return true
end

-- Why a recipe can be learned right now, or nil:
--   "trainer"  a trainer teaches it and the skill is there
--   "held"     the formula is in the bags (right-click it)
--   "vendor"   a usable vendor sells the formula and the skill is there
--   "bank"     the formula is in the bank
function M.LearnableNow(data, rec, world)
    if world.known(rec.spell) then return nil end
    local rank = world.rank or 0
    for _, item in ipairs(rec.formulas or {}) do
        local f = data.formulas[item]
        if f then
            local bags = world.count(item, false) or 0
            if bags > 0 then return (f.skill <= rank) and "held" or "held-soon" end
        end
    end
    if rec.trainer and rec.trainer.skill <= rank and (world.maxRank or 0) > 0 then
        return "trainer"
    end
    for _, item in ipairs(rec.formulas or {}) do
        local f = data.formulas[item]
        if f then
            local all = world.count(item, true) or 0
            if all > 0 then return "bank" end
            if f.skill <= rank then
                for _, v in ipairs(f.vendors or {}) do
                    if M.VendorUsable(data, f, v.npc, world, v) then return "vendor" end
                end
            end
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Crafting
-- ---------------------------------------------------------------------------

-- How many times the recipe could be cast from the bags (bank optional),
-- and the reagent lines behind that number
function M.Craftable(rec, world, useBank)
    local n
    local lines = {}
    for _, pair in ipairs(rec.reagents or {}) do
        local id, per = pair[1], pair[2]
        local bags = world.count(id, false) or 0
        local all = world.count(id, true) or bags
        if all < bags then all = bags end
        local have = useBank and all or bags
        local times = math.floor(have / per)
        if n == nil or times < n then n = times end
        lines[#lines + 1] = { id = id, per = per, have = bags, bank = all - bags, reachable = have }
    end
    return n or 0, lines
end

-- ---------------------------------------------------------------------------
-- Economics
-- ---------------------------------------------------------------------------

-- What one cast costs in reagents at today's prices, and whether every
-- reagent had a price. Vendor-sold reagents are priced at the vendor when
-- the data says what that is.
function M.CastCost(data, rec, world)
    if not world.price then return nil, false end
    local total, priced = 0, true
    for _, pair in ipairs(rec.reagents or {}) do
        local p = data.vendorBuy and data.vendorBuy[pair[1]] or world.price(pair[1])
        if p == nil then priced = false else total = total + p * pair[2] end
    end
    return total, priced
end

-- What a cast of an item-making recipe is worth, and the profit against the
-- cast cost; nil when either side has no price. `makes` casts make more
-- than one (Void Shatter).
function M.CastProfit(data, rec, world)
    if not (rec.creates and world.price) then return nil end
    local value = world.price(rec.creates)
    local cost, priced = M.CastCost(data, rec, world)
    if not value or not priced then return nil end
    local made = rec.makes or 1
    return value * made - cost, value * made, cost
end

-- The cheapest way to get the formula into your hands: a usable vendor's
-- price, else the auction price (BoE formulas), else nil
function M.FormulaPrice(data, rec, world)
    local best
    for _, item in ipairs(rec.formulas or {}) do
        local f = data.formulas[item]
        if f then
            for _, v in ipairs(f.vendors or {}) do
                if M.VendorUsable(data, f, v.npc, world, v) and v.cost > 0 and (not best or v.cost < best) then best = v.cost end
            end
            if not best and not f.bop and world.price then
                local p = world.price(item)
                if p and (not best or p < best) then best = p end
            end
        end
    end
    return best
end

-- ---------------------------------------------------------------------------
-- Disenchanting
-- ---------------------------------------------------------------------------

-- What disenchanting an item gives: the bracket for its quality, class and
-- item level, as { {item, chance, min, max}, ... }, or nil when the item is
-- not disenchantable (only uncommon+ weapons and armour are).
function M.Disenchant(data, quality, classID, itemLevel)
    if not (data.disenchant and quality and classID and itemLevel) then return nil end
    local table_ = data.disenchant[quality .. ":" .. classID]
    if not table_ then return nil end
    for _, bracket in ipairs(table_) do
        if itemLevel >= bracket.min and itemLevel <= bracket.max then
            return bracket.results, bracket
        end
    end
    return nil
end

-- The expected value of those results at today's prices: sum of chance ×
-- average count × price. `priced` is false when any result has no price.
function M.DisenchantValue(results, world)
    if not (results and world.price) then return nil, false end
    local total, priced = 0, true
    for _, r in ipairs(results) do
        local p = world.price(r[1])
        if p == nil then priced = false else total = total + (r[2] / 100) * ((r[3] + r[4]) / 2) * p end
    end
    return total, priced
end

-- The verdict on an item: disenchant, vendor, or sell, with the three
-- figures. Any figure may be nil.
function M.DisposalVerdict(deValue, vendorPrice, auctionPrice)
    local best, bestValue = nil, -1
    for _, pair in ipairs({ { "disenchant", deValue }, { "auction", auctionPrice }, { "vendor", vendorPrice } }) do
        if pair[2] and pair[2] > bestValue then best, bestValue = pair[1], pair[2] end
    end
    return best, bestValue
end

-- ---------------------------------------------------------------------------
-- The view
-- ---------------------------------------------------------------------------

-- Every recipe with its state, grouped by category; the totals the header
-- shows. opts: bank (count the bank as reachable)
function M.Build(data, world, opts)
    opts = opts or {}
    local rank = world.rank or 0
    local view = {
        data = data,
        rank = rank, maxRank = world.maxRank or 0,
        hasProfession = (world.maxRank or 0) > 0,
        categories = {},
        byKey = {},
        entries = {},
        known = 0, total = 0, learnable = 0,
    }
    for _, cat in ipairs(data.categories) do
        local c = { key = cat.key, label = cat.label, recipes = {}, known = 0, total = 0, learnable = 0 }
        view.categories[#view.categories + 1] = c
        view.byKey[cat.key] = c
    end
    for _, rec in ipairs(data.recipes) do
        local cat = view.byKey[rec.category]
        if cat then
            local known = world.known(rec.spell) and true or false
            local entry = {
                rec = rec, spell = rec.spell,
                name = world.spellName(rec.spell) or rec.name,
                category = rec.category,
                known = known,
                colour = known and M.Colour(rec, rank) or nil,
                learnSkill = M.LearnSkill(data, rec),
                sources = M.Sources(data, rec),
                learnable = M.LearnableNow(data, rec, world),
            }
            entry.sourceWord, entry.sourceKind = M.SourceWord(entry.sources)
            entry.craftable, entry.reagentLines = M.Craftable(rec, world, opts.bank ~= false)
            entry.castCost, entry.castPriced = M.CastCost(data, rec, world)
            entry.profit, entry.productValue = M.CastProfit(data, rec, world)
            if not known then entry.formulaPrice = M.FormulaPrice(data, rec, world) end
            cat.recipes[#cat.recipes + 1] = entry
            view.entries[rec.spell] = entry
            cat.total = cat.total + 1
            view.total = view.total + 1
            if known then
                cat.known = cat.known + 1
                view.known = view.known + 1
            elseif entry.learnable then
                cat.learnable = cat.learnable + 1
                view.learnable = view.learnable + 1
            end
        end
    end
    return view
end

-- The formulas a usable vendor sells at your skill for recipes you do not
-- know: how many, and what they cost together (the "go shopping" figure)
function M.VendorShopping(data, view, world)
    local count, cost = 0, 0
    for _, entry in pairs(view.entries) do
        if entry.learnable == "vendor" then
            local best
            for _, item in ipairs(entry.rec.formulas or {}) do
                local f = data.formulas[item]
                if f and f.skill <= view.rank then
                    for _, v in ipairs(f.vendors or {}) do
                        if M.VendorUsable(data, f, v.npc, world, v) and (not best or v.cost < best) then best = v.cost end
                    end
                end
            end
            if best then
                count = count + 1
                cost = cost + best
            end
        end
    end
    return count, cost
end

-- What a formula item means to this character, for its tooltip: nil when
-- the item is not a formula of this profession; else { known, learnable,
-- skill, recipeName, colour }
function M.FormulaVerdict(data, item, world)
    local f = data.formulas[item]
    if not f then return nil end
    local rec
    for _, r in ipairs(data.recipes) do
        if r.spell == f.learns then rec = r break end
    end
    if not rec then return nil end
    local known = world.known(rec.spell)
    return {
        known = known,
        skill = f.skill,
        recipe = rec,
        atSkill = (world.rank or 0) >= f.skill,
        hasProfession = (world.maxRank or 0) > 0,
    }
end

-- The rank ladder: the next rank up, and whether it is within reach now
function M.NextRank(data, view)
    for _, r in ipairs(data.ranks) do
        if r.cap > view.maxRank then
            return r, (view.maxRank == 0) or (view.rank >= r.at)
        end
    end
    return nil
end

-- Whether the profession's top rank comes from a trainer at all. First
-- Aid's Master is a book, so no First Aid trainer "teaches Master".
function M.MasterFromTrainer(data)
    local last = data.ranks[#data.ranks]
    return last and not last.book and not last.quests
end

-- How a rank is obtained, as lines: a trainer (the ordinary case), a book
-- with the vendors that sell it, or a quest with who gives it -- First Aid
-- has one of each. Vendors and givers are filtered to the character's
-- faction when the world knows it. The first line is the one-sentence
-- answer; the rest are the places.
function M.RankRoute(data, r, world)
    local out = {}
    local faction = world and world.faction
    if r.book then
        local name = (world and world.name and world.name(r.book.item)) or data.items[r.book.item] or ("item " .. r.book.item)
        out[#out + 1] = { kind = "book", item = r.book.item, skill = r.book.skill, cost = r.book.cost,
            text = ("%s %s comes from a book: %s (needs %d%s)."):format(r.name, data.name, name, r.book.skill,
                r.book.cost > 0 and (", " .. M.FormatMoney(r.book.cost)) or "") }
        for _, npc in ipairs(r.book.vendors or {}) do
            local n = data.npcs[npc]
            if n and (not n.faction or not faction or n.faction == faction) then
                out[#out + 1] = { kind = "vendor", npc = npc, place = n, text = ("%s — %s"):format(n.name, M.Place(n)) }
            end
        end
    elseif r.quests then
        for _, q in ipairs(r.quests) do
            if not q.faction or not faction or q.faction == faction then
                local n = data.npcs[q.npc]
                out[#out + 1] = { kind = "quest", quest = q.quest, npc = q.npc, place = n,
                    text = ("%s %s is the reward of the quest %s (needs %d)%s."):format(r.name, data.name, q.name, r.at,
                        n and (", from %s — %s"):format(n.name, M.Place(n)) or "") }
            end
        end
    else
        out[#out + 1] = { kind = "trainer", outland = r.outland,
            text = ("%s %s is taught by %s trainers (needs %d)."):format(r.name, data.name,
                r.outland and "Outland" or ("any " .. data.name), r.at) }
    end
    return out
end

-- ---------------------------------------------------------------------------
-- The list
-- ---------------------------------------------------------------------------

local function Matches(entry, needle, data, world)
    if needle == "" then return true end
    if entry.name:lower():find(needle, 1, true) then return true end
    for _, pair in ipairs(entry.rec.reagents or {}) do
        local name = world.name(pair[1]) or data.items[pair[1]]
        if name and name:lower():find(needle, 1, true) then return true end
    end
    if entry.sourceWord:lower():find(needle, 1, true) then return true end
    for _, item in ipairs(entry.rec.formulas or {}) do
        local f = data.formulas[item]
        if f then
            for _, v in ipairs(f.vendors or {}) do
                local npc = data.npcs[v.npc]
                if npc and (npc.name:lower():find(needle, 1, true) or (npc.zone and npc.zone:lower():find(needle, 1, true))) then return true end
            end
            for _, d in ipairs(f.drops or {}) do
                local npc = data.npcs[d.npc]
                if npc and (npc.name:lower():find(needle, 1, true) or (npc.zone and npc.zone:lower():find(needle, 1, true))) then return true end
            end
            if f.rep and f.rep.name and f.rep.name:lower():find(needle, 1, true) then return true end
        end
    end
    return false
end

local function Passes(entry, filter)
    if filter == "KNOWN" then return entry.known end
    if filter == "CRAFTABLE" then return entry.known and entry.craftable > 0 end
    if filter == "PROFITABLE" then return entry.known and entry.profit ~= nil and entry.profit > 0 end
    if filter == "UNKNOWN" then return not entry.known end
    if filter == "LEARNABLE" then return entry.learnable ~= nil end
    return true
end

-- opts: filter, search, sort, collapsed (set of category keys), category
-- (restrict to one key or nil)
-- Returns rows: { kind = "category", cat = c, shown = n, matched = n } and
-- { kind = "recipe", entry = e }
function M.Rows(view, opts, world)
    opts = opts or {}
    local needle = (opts.search or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local filter = opts.filter or "ALL"
    local sort = opts.sort or "SKILL"
    local collapsed = opts.collapsed or {}
    local rows = {}
    local shownTotal = 0
    for _, cat in ipairs(view.categories) do
        if not opts.category or opts.category == cat.key then
            local matched = {}
            for _, entry in ipairs(cat.recipes) do
                if Passes(entry, filter) and Matches(entry, needle, view.data, world) then
                    matched[#matched + 1] = entry
                end
            end
            if #matched > 0 or (needle == "" and filter == "ALL") then
                if sort == "NAME" then
                    table.sort(matched, function(a, b)
                        if a.name ~= b.name then return a.name < b.name end
                        return a.spell < b.spell
                    end)
                else
                    table.sort(matched, function(a, b)
                        if a.learnSkill ~= b.learnSkill then return a.learnSkill < b.learnSkill end
                        if a.name ~= b.name then return a.name < b.name end
                        return a.spell < b.spell
                    end)
                end
                rows[#rows + 1] = { kind = "category", cat = cat, matched = #matched,
                    collapsed = collapsed[cat.key] and true or false }
                if not collapsed[cat.key] then
                    for _, entry in ipairs(matched) do
                        rows[#rows + 1] = { kind = "recipe", entry = entry }
                        shownTotal = shownTotal + 1
                    end
                end
            end
        end
    end
    return rows, shownTotal
end

-- ---------------------------------------------------------------------------
-- Trips: the unknown formulas a usable vendor sells, by zone
-- ---------------------------------------------------------------------------

-- Returns zones, each { zone, map, stops = { {npc, name, x, y, formulas = {entries}} },
-- count, cost, atSkill }, most formulas first. A formula sold in several
-- zones is listed in each; the cheapest usable vendor in a zone is the stop.
function M.Trips(view, world)
    local data = view.data
    local zones = {}
    for _, entry in pairs(view.entries) do
        if not entry.known then
            for _, item in ipairs(entry.rec.formulas or {}) do
                local f = data.formulas[item]
                if f then
                    local seen = {}
                    for _, v in ipairs(f.vendors or {}) do
                        local npc = data.npcs[v.npc]
                        -- The other faction's vendors are no trip at all; a
                        -- reputation you have not earned yet is a trip you
                        -- can plan for, so it is listed and marked short
                        local usable, why = M.VendorUsable(data, f, v.npc, world, v)
                        local listed = usable or why == "reputation"
                        if npc and npc.zone and listed and not seen[npc.zone] then
                            seen[npc.zone] = true
                            local z = zones[npc.zone]
                            if not z then
                                z = { zone = npc.zone, map = npc.map, stops = {}, byNpc = {}, count = 0, cost = 0, atSkill = 0 }
                                zones[npc.zone] = z
                            end
                            local stop = z.byNpc[v.npc]
                            if not stop then
                                stop = { npc = v.npc, name = npc.name, x = npc.x, y = npc.y, zone = npc.zone, map = npc.map, formulas = {} }
                                z.byNpc[v.npc] = stop
                                z.stops[#z.stops + 1] = stop
                            end
                            stop.formulas[#stop.formulas + 1] = { entry = entry, item = item, cost = v.cost, skill = f.skill,
                                rep = M.VendorGate(f, v), repShort = not usable }
                            z.count = z.count + 1
                            z.cost = z.cost + (v.cost or 0)
                            if f.skill <= view.rank then z.atSkill = z.atSkill + 1 end
                        end
                    end
                end
            end
        end
    end
    local out = {}
    for _, z in pairs(zones) do
        for _, stop in ipairs(z.stops) do
            table.sort(stop.formulas, function(a, b)
                if a.skill ~= b.skill then return a.skill < b.skill end
                return a.entry.name < b.entry.name
            end)
        end
        table.sort(z.stops, function(a, b) return #a.formulas > #b.formulas end)
        out[#out + 1] = z
    end
    table.sort(out, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.zone < b.zone
    end)
    return out
end

-- ---------------------------------------------------------------------------
-- Detail
-- ---------------------------------------------------------------------------

-- Everything the detail pane says about how to learn a recipe, as ordered
-- lines of { kind, text, ... }. Pure text; the window adds links, tooltips
-- and buttons by kind.
function M.HowToLearn(data, entry, world)
    local rec = entry.rec
    local out = {}
    if rec.trainer then
        if rec.trainer.withRank then
            out[#out + 1] = { kind = "trainer", text = ("Learned with Apprentice %s itself."):format(data.name) }
        else
            out[#out + 1] = { kind = "trainer", skill = rec.trainer.skill, cost = rec.trainer.cost, outland = rec.trainer.outland,
                text = ("Taught by %s trainers at %d skill%s."):format(
                    rec.trainer.outland and "Outland" or data.name, rec.trainer.skill,
                    rec.trainer.cost > 0 and (" for " .. M.FormatMoney(rec.trainer.cost)) or "") }
        end
    end
    for _, item in ipairs(rec.formulas or {}) do
        local f = data.formulas[item]
        if f then
            local held = (world.count(item, false) or 0) > 0
            local banked = not held and (world.count(item, true) or 0) > 0
            out[#out + 1] = { kind = "formula", item = item, skill = f.skill, bop = f.bop, held = held, banked = banked,
                text = ("%s — needs %d skill%s%s"):format(world.name(item) or data.items[item] or ("item " .. item), f.skill,
                    f.bop and ", binds when picked up" or "", held and " — IN YOUR BAGS" or banked and " — in your bank" or "") }
            if f.rep then
                local have = world.standing and world.standing(f.rep.faction)
                out[#out + 1] = { kind = "rep", faction = f.rep.faction, standing = f.rep.standing, short = have and have < f.rep.standing + 1,
                    text = ("Requires %s with %s"):format(M.StandingName(f.rep.standing), f.rep.name or "?") }
            end
            for _, v in ipairs(f.vendors or {}) do
                local npc = data.npcs[v.npc]
                if npc then
                    local usable, why = M.VendorUsable(data, f, v.npc, world, v)
                    local gate = v.rep
                    out[#out + 1] = { kind = "vendor", npc = v.npc, cost = v.cost, usable = usable, why = why, limited = v.limited, place = npc,
                        text = ("%s — %s%s%s%s"):format(npc.name, M.Place(npc), v.cost > 0 and (", " .. M.FormatMoney(v.cost)) or "",
                            v.limited and " (limited stock)" or "",
                            gate and (" — %s with %s"):format(M.StandingName(gate.standing), gate.name or "?") or "") }
                end
            end
            if f.worldDrop then
                out[#out + 1] = { kind = "world", text = ("World drop from level %d–%d creatures (%d of them)."):format(f.worldDrop.minLevel, f.worldDrop.maxLevel, f.worldDrop.mobs) }
            end
            for _, z in ipairs(f.zones or {}) do
                out[#out + 1] = { kind = "zone", zone = z.zone, text = ("%s — trash (%d kinds, up to %s%%)"):format(z.zone, z.mobs, tostring(z.chance)) }
            end
            for _, d in ipairs(f.drops or {}) do
                local npc = data.npcs[d.npc]
                if npc then
                    out[#out + 1] = { kind = "drop", npc = d.npc, chance = d.chance, place = npc,
                        text = ("%s — %s%s, %s%%"):format(npc.name, M.Place(npc),
                            npc.level and (" (level %s)"):format(npc.level[1] == npc.level[2] and tostring(npc.level[1]) or (npc.level[1] .. "–" .. npc.level[2])) or "",
                            tostring(d.chance)) }
                end
            end
            for _, o in ipairs(f.objects or {}) do
                out[#out + 1] = { kind = "object", text = ("%s%s, %s%%"):format(o.name, o.zone and (" — " .. o.zone) or "", tostring(o.chance)) }
            end
            for _, c in ipairs(f.containers or {}) do
                out[#out + 1] = { kind = "container", item = c.item, text = ("Inside %s, %s%%"):format(c.name, tostring(c.chance)) }
            end
            for _, q in ipairs(f.quests or {}) do
                out[#out + 1] = { kind = "quest", quest = q.quest, text = ("Quest: %s%s (level %d)"):format(q.name, q.zone and (", " .. q.zone) or "", q.level) }
            end
            if f.note then
                out[#out + 1] = { kind = "note", text = f.note }
            end
        end
    end
    return out
end

function M.Place(npc)
    if not npc.zone then return "somewhere" end
    if npc.x then return ("%s (%.1f, %.1f)"):format(npc.zone, npc.x, npc.y) end
    return npc.zone
end

local STANDING = { [4] = "Neutral", [5] = "Friendly", [6] = "Honored", [7] = "Revered", [8] = "Exalted" }
-- ItemSparse counts standings from 0: 0 Hated … 4 Friendly, 5 Honored, 6 Revered, 7 Exalted.
-- The client's standing index counts from 1 (4 Neutral, 5 Friendly, 6 Honored, 7 Revered, 8 Exalted).
function M.StandingName(itemStanding)
    return STANDING[(itemStanding or 0) + 1] or "?"
end

function M.FormatMoney(copper)
    copper = math.floor(copper or 0)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end
