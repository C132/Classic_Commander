-- Commander Guide — engine
--
-- The reasoning, with no client attached: which boss a pull is, which
-- callout an event earns, what the voice should say and in what order, and
-- how a boss page reads out loud. No WoW API is touched here; the runtime
-- (CommanderGuide.lua) turns client events into the plain tables this file
-- reads, and the harness (Harness/guide_engine_smoke.lua) drives it directly.
--
-- Event shape handed to E.Feed:
--   { kind = "AURA_APPLIED" | "AURA_REMOVED" | "DOSE" | "CAST_START"
--          | "CAST_SUCCESS" | "DAMAGE" | "SUMMON" | "UNIT_DIED"
--          | "HEALTH" | "YELL",
--     spell = id, spellName = "...",
--     srcNpc = id|nil, dstNpc = id|nil,        -- creature ids from GUIDs
--     dstIsMe = bool, dstIsFriendly = bool,    -- a friendly PLAYER (you too)
--     dstName = "Name-Realm"|nil, srcName = ...,
--     stacks = n (DOSE), pct = 0..100 (HEALTH, with npc), npc = id (UNIT_DIED,
--     HEALTH), text = "..." (YELL) }

CommanderGuide_Engine = CommanderGuide_Engine or {}
local E = CommanderGuide_Engine

E.STALE = 6                 -- a queued line older than this is no longer true
E.DEFAULT_COOLDOWN = 4
E.WORDS_PER_SECOND = 2.7    -- rate 0 on the client's voices, measured loosely
E.CLEAR_ON_URGENT = true    -- priority 1 empties the queue of priority 2

-- ---------------------------------------------------------------------------
-- small helpers
-- ---------------------------------------------------------------------------

-- "Creature-0-4379-532-19862-15687-00002B6E9A" -> 15687 (also Vehicle/Pet)
function E.NpcFromGUID(guid)
    if type(guid) ~= "string" then return nil end
    local kind, npc = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if kind == "Creature" or kind == "Vehicle" then return tonumber(npc) end
    return nil
end

function E.ShortName(name)
    if type(name) ~= "string" then return "" end
    return (name:match("^([^%-]+)") or name)
end

local function Words(text)
    local n = 0
    for _ in tostring(text or ""):gmatch("%S+") do n = n + 1 end
    return n
end

-- Seconds a line takes to say. `rate` is the client's -10..10 speech rate.
function E.Estimate(text, rate)
    local factor = 1 + (tonumber(rate) or 0) * 0.06
    if factor < 0.4 then factor = 0.4 end
    return Words(text) / (E.WORDS_PER_SECOND * factor) + 0.5
end

-- %t -> the target's first name, or "you"
function E.Format(say, ev)
    if type(say) ~= "string" then return "" end
    local who = "them"
    if ev then
        if ev.dstIsMe then who = "you"
        elseif ev.dstName and ev.dstName ~= "" then who = E.ShortName(ev.dstName) end
    end
    return (say:gsub("%%t", who))
end

-- ---------------------------------------------------------------------------
-- resolution
-- ---------------------------------------------------------------------------

function E.BossForEncounter(data, encounterID)
    return data and data.BY_ENCOUNTER and data.BY_ENCOUNTER[tonumber(encounterID) or -1] or nil
end

function E.BossForNpc(data, npc)
    return data and data.BY_NPC and data.BY_NPC[tonumber(npc) or -1] or nil
end

function E.BossByKey(data, raidKey, bossKey)
    return data and data.BY_KEY and data.BY_KEY[tostring(raidKey) .. ":" .. tostring(bossKey)] or nil
end

function E.Role(boss, roleKey)
    return boss and boss.roles and boss.roles[roleKey or "HEALER"] or nil
end

-- ---------------------------------------------------------------------------
-- session
-- ---------------------------------------------------------------------------

function E.NewSession(data, roleKey)
    return {
        data = data, role = roleKey or "HEALER",
        boss = nil, inCombat = false, pulls = 0, source = nil,
        fired = {}, lastAt = {}, seen = {}, queue = {}, delayed = {},
    }
end

local function Reset(ctx)
    ctx.fired, ctx.lastAt, ctx.seen, ctx.queue, ctx.delayed = {}, {}, {}, {}, {}
end

local function Callouts(ctx)
    local role = E.Role(ctx.boss, ctx.role)
    return role and role.callouts or nil
end

-- Which player-side test a callout wants. Aura and damage kinds default to
-- "friend" (a friendly player, you included); everything else to "any".
local FRIEND_DEFAULT = { AURA_APPLIED = true, AURA_REMOVED = true, DOSE = true, DAMAGE = true }

function E.Whom(callout)
    if callout.whom then return callout.whom end
    return FRIEND_DEFAULT[callout.on] and "friend" or "any"
end

function E.Matches(callout, ev)
    if callout.on ~= ev.kind then return false end
    local kind = ev.kind
    if kind == "START" or kind == "END" then return true end
    if kind == "YELL" then
        local m = callout.match
        return type(m) == "string" and type(ev.text) == "string"
            and ev.text:lower():find(m:lower(), 1, true) ~= nil
    end
    if kind == "FIRST_SEEN" or kind == "UNIT_DIED" then
        return callout.npc ~= nil and callout.npc == ev.npc
    end
    if kind == "HEALTH" then
        if callout.npc ~= nil and callout.npc ~= ev.npc then return false end
        return type(callout.below) == "number" and type(ev.pct) == "number" and ev.pct <= callout.below
    end
    if kind == "SUMMON" then
        if callout.npc ~= nil then return callout.npc == ev.dstNpc end
        return callout.spell ~= nil and callout.spell == ev.spell
    end
    -- spell kinds
    if callout.spell ~= nil and callout.spell ~= ev.spell then return false end
    if callout.spell == nil then return false end
    if kind == "DOSE" then
        local want = callout.stacks or 1
        if (tonumber(ev.stacks) or 0) < want then return false end
    end
    local whom = E.Whom(callout)
    if whom == "me" then return ev.dstIsMe == true end
    if whom == "friend" then return ev.dstIsFriendly == true or ev.dstIsMe == true end
    return true
end

local function Emit(ctx, callout, ev, now, out)
    local id = callout.id or callout
    local cooldown = callout.cooldown or E.DEFAULT_COOLDOWN
    if callout.once and ctx.fired[id] then return end
    -- a HEALTH threshold only ever fires once per pull, once is implied
    if ev.kind == "HEALTH" and ctx.fired[id] then return end
    -- the cooldown is per PERSON for lines about a person: Garrote on you
    -- and Garrote on Thrall two seconds apart are two different facts
    local key = id
    if E.Whom(callout) ~= "any" and ev.dstName and ev.dstName ~= "" then
        ctx.lastAt[id] = ctx.lastAt[id] or {}
        key = ev.dstName
        local last = ctx.lastAt[id][key]
        if last and (now - last) < cooldown then return end
        ctx.lastAt[id][key] = now
    else
        local last = ctx.lastAt[id]
        if type(last) == "number" and (now - last) < cooldown then return end
        ctx.lastAt[id] = now
    end
    ctx.fired[id] = true
    local say = callout.say
    if ev.dstIsMe and callout.sayMe then say = callout.sayMe end
    local spoken = E.Format(say, ev)
    local text = callout.text and E.Format(callout.text, ev) or spoken
    out[#out + 1] = {
        say = spoken, text = text,
        priority = callout.priority or 2,
        delay = callout.delay or 0,
        at = now, callout = callout, kind = ev.kind,
    }
end

local function Run(ctx, ev, now, out)
    local list = Callouts(ctx)
    if not list then return end
    for _, callout in ipairs(list) do
        if E.Matches(callout, ev) then Emit(ctx, callout, ev, now, out) end
    end
end

-- Start a pull on a boss. source: "encounter" | "npc" | "manual"
function E.Begin(ctx, boss, now, source)
    local out = {}
    if not boss then return out end
    if ctx.boss ~= boss then
        ctx.boss = boss
        ctx.source = source or "manual"
        ctx.pulls = ctx.pulls + 1
        Reset(ctx)
        Run(ctx, { kind = "START" }, now, out)
    end
    return out
end

function E.Finish(ctx, now, success)
    local out = {}
    if ctx.boss then
        Run(ctx, { kind = "END", success = success }, now, out)
    end
    ctx.boss = nil
    ctx.source = nil
    Reset(ctx)
    return out
end

-- One client event in, zero or more lines out. Lines carry `delay`; the
-- caller holds those. Also resolves the boss from creature ids when no
-- ENCOUNTER_START named it (ASSUMPTIONS A2).
function E.Feed(ctx, ev, now)
    local out = {}
    if type(ev) ~= "table" or not ev.kind then return out end
    local npcs = { ev.srcNpc, ev.dstNpc, ev.npc }
    if not ctx.boss and ctx.inCombat then
        for _, npc in ipairs(npcs) do
            local boss = E.BossForNpc(ctx.data, npc)
            if boss then
                for _, item in ipairs(E.Begin(ctx, boss, now, "npc")) do out[#out + 1] = item end
                break
            end
        end
    end
    if not ctx.boss then return out end
    -- first sighting of a creature id during this pull
    for _, npc in ipairs(npcs) do
        if npc and not ctx.seen[npc] then
            ctx.seen[npc] = true
            Run(ctx, { kind = "FIRST_SEEN", npc = npc }, now, out)
        end
    end
    if ev.kind == "UNIT_DIED" and not ev.npc then ev.npc = ev.dstNpc end
    Run(ctx, ev, now, out)
    return out
end

-- ---------------------------------------------------------------------------
-- the speech queue
-- ---------------------------------------------------------------------------

-- Push lines. Priority 1 goes to the front and (by default) empties the
-- priority-2 lines behind it: an urgent instruction makes a pending routine
-- one wrong. Returns true when the caller should interrupt current speech.
function E.Enqueue(ctx, items, now)
    local interrupt = false
    for _, item in ipairs(items or {}) do
        if item.delay and item.delay > 0 then
            ctx.delayed[#ctx.delayed + 1] = { due = now + item.delay, item = item }
        elseif item.priority == 1 then
            if E.CLEAR_ON_URGENT then
                local kept = {}
                for _, q in ipairs(ctx.queue) do if q.priority == 1 then kept[#kept + 1] = q end end
                ctx.queue = kept
            end
            table.insert(ctx.queue, 1, item)
            interrupt = true
        else
            ctx.queue[#ctx.queue + 1] = item
        end
    end
    return interrupt
end

-- Move delayed lines whose time has come onto the queue.
function E.Tick(ctx, now)
    if #ctx.delayed == 0 then return false end
    local ready, rest = {}, {}
    for _, d in ipairs(ctx.delayed) do
        if d.due <= now then d.item.at = now; d.item.delay = nil; ready[#ready + 1] = d.item else rest[#rest + 1] = d end
    end
    ctx.delayed = rest
    return E.Enqueue(ctx, ready, now)
end

-- The next line worth saying, dropping ones that went stale in the queue.
function E.Next(ctx, now)
    while #ctx.queue > 0 do
        local item = table.remove(ctx.queue, 1)
        if (now - (item.at or now)) <= E.STALE then return item end
    end
    return nil
end

function E.Clear(ctx)
    ctx.queue, ctx.delayed = {}, {}
end

-- ---------------------------------------------------------------------------
-- reading a page out loud, and laying it out
-- ---------------------------------------------------------------------------

local function Join(list, sep)
    local parts = {}
    for _, s in ipairs(list or {}) do parts[#parts + 1] = tostring(s) end
    return table.concat(parts, sep or " ")
end

-- The spoken brief: title, the one-liner, then the job bullets; with
-- opts.full, the phases too. Each sentence already ends in a period, so the
-- joiner is a pause, not more punctuation.
function E.Brief(boss, roleKey, opts)
    local role = E.Role(boss, roleKey)
    if not role then return nil end
    local parts = { boss.title .. ".", role.oneLiner }
    if role.job and #role.job > 0 then
        parts[#parts + 1] = "Your job."
        for _, line in ipairs(role.job) do parts[#parts + 1] = line end
    end
    if opts and opts.full and role.phases then
        for _, phase in ipairs(role.phases) do
            parts[#parts + 1] = phase.title .. "."
            for _, line in ipairs(phase.lines or {}) do parts[#parts + 1] = line end
        end
    end
    return Join(parts, " ")
end

local KIND_LABEL = {
    MAGIC = "Magic, dispel", CURSE = "Curse, decurse", POISON = "Poison, cleanse",
    DISEASE = "Disease, cure", BLEED = "Bleed", STUN = "Stun", SILENCE = "Silence",
    FEAR = "Fear", NONE = "",
}
E.KIND_LABEL = KIND_LABEL

-- A human sentence for when a callout fires (the window's callout list).
function E.When(callout)
    local on = callout.on
    local who = E.Whom(callout)
    local target = (who == "me") and "on you" or (who == "friend") and "on a player" or ""
    local name = callout.spellName or (callout.spell and ("spell " .. callout.spell)) or ""
    if on == "START" then return "On the pull" end
    if on == "END" then return "When the fight ends" end
    if on == "AURA_APPLIED" then return ("When %s lands %s"):format(name, target) end
    if on == "AURA_REMOVED" then return ("When %s fades %s"):format(name, target) end
    if on == "DOSE" then return ("At %d stacks of %s %s"):format(callout.stacks or 1, name, target) end
    if on == "CAST_START" then return ("When %s starts casting"):format(name) end
    if on == "CAST_SUCCESS" then return ("When %s is cast"):format(name) end
    if on == "DAMAGE" then return ("When %s hits %s"):format(name, target) end
    if on == "SUMMON" then return "On the summon" end
    if on == "UNIT_DIED" then return ("When %s dies"):format(callout.npcName or ("creature " .. tostring(callout.npc))) end
    if on == "FIRST_SEEN" then return ("When %s appears"):format(callout.npcName or ("creature " .. tostring(callout.npc))) end
    if on == "HEALTH" then return ("When %s is under %d percent"):format(callout.npcName or "the boss", callout.below or 0) end
    if on == "YELL" then return ("When he yells \"%s\""):format(callout.match or "") end
    return on
end

-- Ordered sections for the window. kind: "lead" | "bullets" | "phases" |
-- "watch" | "callouts"
function E.Page(boss, roleKey)
    local role = E.Role(boss, roleKey)
    if not role then return nil end
    local page = {}
    page[#page + 1] = { kind = "lead", title = "The fight in one line", text = role.oneLiner }
    page[#page + 1] = { kind = "bullets", title = "Your job", lines = role.job or {} }
    if role.phases and #role.phases > 0 then
        page[#page + 1] = { kind = "phases", title = "Phase by phase", phases = role.phases }
    end
    if role.watch and #role.watch > 0 then
        page[#page + 1] = { kind = "watch", title = "Watch list", rows = role.watch }
    end
    if role.callouts and #role.callouts > 0 then
        page[#page + 1] = { kind = "callouts", title = "What the voice will say", rows = role.callouts }
    end
    return page
end

-- ---------------------------------------------------------------------------
-- the way to the door (DECISIONS D11)
-- ---------------------------------------------------------------------------
-- Getting to the raid is the one part of a raid night the guide could not
-- help with. These two build what the runtime hands an Orders without the 3.1
-- GoTo, what it falls back on when Orders cannot look the door up, and what
-- it prints without Orders (DECISIONS D12): no client call here either.

-- A uiMap position the client could ever answer for: a map id and 0..1 x, y
-- (NaN fails every comparison, so it fails here too)
function E.ValidPosition(map, x, y)
    return type(map) == "number" and map > 0 and type(x) == "number" and type(y) == "number"
        and x >= 0 and x <= 1 and y >= 0 and y <= 1
end

-- The CommanderOrders.Add spec for a raid's entrance, and where it came from
-- ("resolver" | "table"), or nil when nothing is known. `resolved` is what
-- Orders' own entrance resolvers answered for the raid's uiMap (a { map, x,
-- y, title } or nil): a usable answer wins, because a resolver is fed by live
-- data (Questie's) and the table below is a frozen copy of the same source.
-- Otherwise the cited table, with every door as an alternative so the arrow
-- takes the nearer one.
--
-- A resolver answers ONE point: the Quest Log's, the one installed beside
-- Questie in the suite's normal setup, stops at Questie's first door, so for
-- Karazhan it always said the north door (46.7, 70.2) and the nearer-door
-- promise above held only without it. So when the resolver's point IS one of
-- the table's doors (same map, within DOOR_MATCH), the other doors ride
-- along as alternatives. A point the table does not know is live data the
-- table has not caught up with, and is used as it is.
local DOOR_MATCH = 0.002     -- 0..1 map units: Questie's two-decimal percent, with room for float noise

local function Alternatives(points)
    if type(points) ~= "table" or #points < 2 then return nil end
    local out = {}
    for _, p in ipairs(points) do
        if type(p) == "table" and E.ValidPosition(p.map, p.x, p.y) then
            out[#out + 1] = { map = p.map, x = p.x, y = p.y }
        end
    end
    if #out < 2 then return nil end
    return out
end

local function IsDoor(points, map, x, y)
    for _, p in ipairs(type(points) == "table" and points or {}) do
        if type(p) == "table" and p.map == map and type(p.x) == "number" and type(p.y) == "number"
            and math.abs(p.x - x) <= DOOR_MATCH and math.abs(p.y - y) <= DOOR_MATCH then
            return true
        end
    end
    return false
end

function E.EntranceSpec(data, raid, resolved)
    if type(raid) ~= "table" then return nil end
    local spec = {
        title = (raid.title or "Raid") .. " entrance",
        source = "Guide", key = "entrance:" .. tostring(raid.key),
        setArrow = true,
    }
    local row = data and data.ENTRANCES and data.ENTRANCES[raid.instanceMapID]
    local points = row and row.points
    if type(resolved) == "table" and E.ValidPosition(resolved.map, resolved.x, resolved.y) then
        spec.map, spec.x, spec.y = resolved.map, resolved.x, resolved.y
        if IsDoor(points, resolved.map, resolved.x, resolved.y) then
            spec.alternatives = Alternatives(points)
        end
        return spec, "resolver"
    end
    if type(points) ~= "table" or not points[1] then return nil end
    local first = points[1]
    if not E.ValidPosition(first.map, first.x, first.y) then return nil end
    spec.map, spec.x, spec.y = first.map, first.x, first.y
    spec.alternatives = Alternatives(points)
    return spec, "table"
end

-- "/way #1430 46.70 70.20 Karazhan entrance": Commander Orders' own /way
-- grammar, so the line pastes straight back into /way, or into chat for a
-- friend
function E.WayLine(spec)
    if type(spec) ~= "table" or not E.ValidPosition(spec.map, spec.x, spec.y) then return nil end
    local line = ("/way #%d %.2f %.2f"):format(spec.map, spec.x * 100, spec.y * 100)
    if type(spec.title) == "string" and spec.title ~= "" then line = line .. " " .. spec.title end
    return line
end

-- ---------------------------------------------------------------------------
-- validation (the harness runs it; /cguide validate prints it)
-- ---------------------------------------------------------------------------

function E.Validate(data)
    local problems = {}
    local function bad(fmt, ...) problems[#problems + 1] = fmt:format(...) end
    if type(data) ~= "table" or type(data.RAIDS) ~= "table" then
        bad("no RAIDS table"); return problems
    end
    local encounters, keys = {}, {}
    for _, raid in ipairs(data.RAIDS) do
        if type(raid.key) ~= "string" or type(raid.title) ~= "string" then bad("raid without key/title") end
        for _, boss in ipairs(raid.bosses or {}) do
            local where = (raid.key or "?") .. ":" .. tostring(boss.key)
            if keys[where] then bad("%s: duplicate boss key", where) end
            keys[where] = true
            if type(boss.title) ~= "string" then bad("%s: no title", where) end
            if type(boss.encounterID) ~= "number" then bad("%s: no encounterID", where)
            elseif encounters[boss.encounterID] then bad("%s: encounterID %d reused", where, boss.encounterID)
            else encounters[boss.encounterID] = true end
            if type(boss.npcs) ~= "table" or #boss.npcs == 0 then bad("%s: no npcs", where) end
            for _, npc in ipairs(boss.npcs or {}) do
                if type(npc) ~= "number" then bad("%s: npc %s not a number", where, tostring(npc)) end
            end
            for roleKey, role in pairs(boss.roles or {}) do
                local rw = where .. "/" .. roleKey
                if type(role.oneLiner) ~= "string" or #role.oneLiner < 20 then bad("%s: oneLiner missing or short", rw) end
                if type(role.job) ~= "table" or #role.job == 0 then bad("%s: no job bullets", rw) end
                for i, w in ipairs(role.watch or {}) do
                    if type(w.spell) ~= "number" then bad("%s: watch %d has no spell id", rw, i) end
                    if type(w.name) ~= "string" then bad("%s: watch %d has no name", rw, i) end
                    if not data.WATCH_KINDS[w.kind or "NONE"] then bad("%s: watch %d kind %s unknown", rw, i, tostring(w.kind)) end
                end
                local starts = 0
                for i, c in ipairs(role.callouts or {}) do
                    local cw = ("%s callout %d (%s)"):format(rw, i, tostring(c.on))
                    if not data.KINDS[c.on or ""] then bad("%s: kind unknown", cw) end
                    if type(c.say) ~= "string" or #c.say == 0 then bad("%s: no say", cw) end
                    if c.say and Words(c.say) > 14 and c.on ~= "START" then bad("%s: say is %d words, keep combat lines short", cw, Words(c.say)) end
                    if c.on == "START" then starts = starts + 1 end
                    local spellKinds = { AURA_APPLIED = 1, AURA_REMOVED = 1, DOSE = 1, CAST_START = 1, CAST_SUCCESS = 1, DAMAGE = 1 }
                    if spellKinds[c.on] and type(c.spell) ~= "number" then bad("%s: needs a spell id", cw) end
                    if (c.on == "FIRST_SEEN" or c.on == "UNIT_DIED") and type(c.npc) ~= "number" then bad("%s: needs an npc id", cw) end
                    if c.on == "HEALTH" and (type(c.below) ~= "number" or type(c.npc) ~= "number") then bad("%s: needs npc and below", cw) end
                    if c.on == "YELL" and type(c.match) ~= "string" then bad("%s: needs match", cw) end
                    if c.on == "DOSE" and type(c.stacks) ~= "number" then bad("%s: needs stacks", cw) end
                    if c.whom and c.whom ~= "me" and c.whom ~= "friend" and c.whom ~= "any" then bad("%s: whom %s unknown", cw, tostring(c.whom)) end
                    if c.say and c.say:find("%%t") and E.Whom(c) == "any" and c.on ~= "CAST_START" and c.on ~= "DAMAGE" then
                        bad("%s: %%t with whom=any", cw)
                    end
                    if c.priority and c.priority ~= 1 and c.priority ~= 2 then bad("%s: priority %s", cw, tostring(c.priority)) end
                    if c.sayMe and E.Whom(c) == "me" then bad("%s: sayMe is redundant with whom=me", cw) end
                end
                if starts > 1 then bad("%s: %d START callouts", rw, starts) end
            end
        end
        if data.ENTRANCES and not data.ENTRANCES[raid.instanceMapID] then
            bad("%s: no entrance for instance %s", tostring(raid.key), tostring(raid.instanceMapID))
        end
    end
    for id, row in pairs(data.ENTRANCES or {}) do
        local where = "entrance " .. tostring(id)
        if type(row.raidMap) ~= "number" then bad("%s: no raidMap", where) end
        if type(row.zone) ~= "string" then bad("%s: no zone name", where) end
        if type(row.points) ~= "table" or #row.points == 0 then bad("%s: no points", where) end
        for i, p in ipairs(row.points or {}) do
            if not E.ValidPosition(p.map, p.x, p.y) then bad("%s: point %d is not a map position", where, i) end
        end
    end
    return problems
end
