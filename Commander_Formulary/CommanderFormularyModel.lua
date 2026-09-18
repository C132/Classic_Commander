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

CommanderFormulary_Model = {}
local M = CommanderFormulary_Model

M.FILTERS = { "ALL", "KNOWN", "UNKNOWN", "LEARNABLE" }
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

-- The rank ladder: the next rank up, and whether it is trainable now
function M.NextRank(data, view)
    for _, r in ipairs(data.ranks) do
        if r.cap > view.maxRank then
            return r, (view.maxRank == 0) or (view.rank >= r.at)
        end
    end
    return nil
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
            out[#out + 1] = { kind = "trainer", text = "Learned with Apprentice Enchanting itself." }
        else
            out[#out + 1] = { kind = "trainer", skill = rec.trainer.skill, cost = rec.trainer.cost, outland = rec.trainer.outland,
                text = ("Taught by %s trainers at %d skill%s."):format(
                    rec.trainer.outland and "Outland" or "Enchanting", rec.trainer.skill,
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
