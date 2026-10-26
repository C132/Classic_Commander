-- Commander Quest Log: the Attunements engine.
--
-- The tab (CommanderQuestLogAttunements.lua) draws guides and steps; this
-- file decides what every one of them says. It reads the generated data
-- (CommanderQuestLogAttuneData: the guides, their steps, the phase calendar
-- and the rules per phase) and the client (quest flags, the keyring and bags,
-- standings, spells, skill ranks, saved lockouts, where the character is),
-- and answers in the shared vocabulary: a status key, a reason sentence and
-- a progress pair per step; a status, a word and a ratio per guide; the
-- content phase and why it was chosen; where a step's Go should point.
--
-- Nothing here is a widget. The engine never reads the kit, never calls
-- Q.Refresh or Q.QueueRefresh: it bumps a generation per client domain and
-- tells its listeners which one moved, and the tab queues one pass.
--
-- The traps this file exists to contain:
--
--   * Client reads are grouped in domains (quests, items, reps, char, spells,
--     skills, locks, world, store, phase), each with its own generation. A
--     domain's slice of the facts table is rebuilt lazily after its bump and
--     never before; a step's answer is memoised against the generations of
--     the domains it actually read. GetQuestsCompleted is never called: the
--     completed flag is read per quest id and cached until the next bump.
--   * The completed flag can lag QUEST_TURNED_IN by seconds. A turned-in id
--     is remembered per character ("seen") and counts as done for ten
--     seconds, with rechecks at one and eleven seconds.
--   * Skill headers are never expanded: a rank under a collapsed header is
--     simply absent and the riding spell answers instead.
--   * Boss names from the client are localised: a KILL step matches the
--     authored English name first, then DungeonEncounter ids, then the last
--     boss by index, then kills this frame saw fall in the combat log.
--   * A detected Done beats every lock, mark and waiver; a mark never
--     changes a detected Done's reason; the account ledger is written by
--     detection only, so a mis-click on an alt cannot become a permanent
--     account-wide fact.
--   * "Current" is a pointer, not a status: a level-locked first step stays
--     Locked even when it is the one the card points at.
--
-- Lua 5.1: detectors live in DETECT, collectors in COLLECT, templates in
-- HOW; every section is a do block so the main chunk stays well under the
-- 200-local ceiling and no closure nears 60 upvalues.

CommanderQuestLog = CommanderQuestLog or {}
local Q = CommanderQuestLog

local A = {}
Q.Attune = A

local floor, max = math.floor, math.max
local format = string.format
local tsort, tconcat = table.sort, table.concat

local GRACE = 10                 -- seconds a turned-in quest counts as done before the flag catches up
local RAID_INFO_THROTTLE = 30    -- seconds between RequestRaidInfo calls
local DAY, WEEK = 86400, 7 * 86400
local LOCKOUT_SPAN = { [568] = 3 * DAY }   -- Zul'Aman resets every three days; every other raid weekly
local BADGE_ITEM = 29434

local EMPTY = {}
local EMPTY_RULES = { attunementRequired = EMPTY, raidsOpen = EMPTY, badgeSources = EMPTY, live = EMPTY,
    assumed = EMPTY, sentences = EMPTY }
local SUBTABLES = { "marks", "seen", "touched", "kills", "talked", "entered", "phaseEvidence" }

A.generation = 0
A.byKey = {}

-- Engine state shared by the sections (one table, so no closure carries
-- dozens of upvalues of its own)
local E = {
    gen = {}, fresh = {}, slice = {}, memo = {}, listeners = {}, readStack = {},
    guideCache = {}, allCache = nil, logIndex = {}, logSignature = "",
    lastRaidInfo = -1e9, index = nil, hooked = false, tickStarted = false,
    cleuFrame = nil, cleuArmed = false,
    placeData = setmetatable({}, { __mode = "k" }),
    labels = nil,
}

-- ---------------------------------------------------------------------------
-- Small utilities: clocks, dates, the saved tables, the data and its index
-- ---------------------------------------------------------------------------

local function Now()
    if GetServerTime then
        local ok, t = pcall(GetServerTime)
        if ok and type(t) == "number" then return t end
    end
    if time then return time() end
    return os.time()
end

local function Clock()
    if GetTime then
        local ok, t = pcall(GetTime)
        if ok and type(t) == "number" then return t end
    end
    return Now()
end

-- "12 Oct" or "22 Oct 2026": date('%d %b %Y') with the leading zero stripped.
-- utc for the calendar's phase starts (announced Pacific afternoons, whose
-- authored day holds in UTC); local time for the player's own stamps
local function DateWord(t, withYear, utc)
    t = tonumber(t)
    if not t then return "" end
    local fn = date or (os and os.date)
    if not fn then return tostring(t) end
    local ok, s = pcall(fn, (utc and "!" or "") .. (withYear and "%d %b %Y" or "%d %b"), t)
    if not ok or type(s) ~= "string" then return tostring(t) end
    return (s:gsub("^0", ""))
end

local function DB()
    local db = CommanderQuestLogDB
    if type(db) == "table" then return db end
    return nil
end

-- An account-wide table of ours (AttuneAccount, AttunePhaseSeen), made whole;
-- nil before the saved variables exist
local function AccountTable(name)
    local db = DB()
    if not db then return nil end
    if type(db[name]) ~= "table" then db[name] = {} end
    return db[name]
end

-- CommanderQuestLogChar.Attune, made whole (DB's EnsureCharDB first when it
-- is there; the sub-tables guarded here as well)
local function Char()
    if Q.EnsureCharDB then pcall(Q.EnsureCharDB) end
    if type(CommanderQuestLogChar) ~= "table" then CommanderQuestLogChar = {} end
    local c = CommanderQuestLogChar
    if type(c.Attune) ~= "table" then c.Attune = {} end
    local at = c.Attune
    for _, k in ipairs(SUBTABLES) do
        if type(at[k]) ~= "table" then at[k] = {} end
    end
    return at
end

local function Data()
    local D = CommanderQuestLogAttuneData
    if type(D) == "table" and type(D.guides) == "table" then return D end
    return nil
end

-- Every number inside a value, however it is split or nested
local function Numbers(v, out)
    out = out or {}
    if type(v) == "table" then
        for _, x in pairs(v) do Numbers(x, out) end
    elseif tonumber(v) then
        out[#out + 1] = tonumber(v)
    end
    return out
end

-- Every quest id a step can stand for (both halves of a split included)
local function AllQuestIds(step, out)
    out = out or {}
    Numbers(step.questId, out); Numbers(step.altQuestIds, out); Numbers(step.questIds, out)
    return out
end

-- Every item id an ITEM step can stand for
local function AllItemIds(item)
    local out = {}
    if type(item) == "table" then Numbers(item.id, out); Numbers(item.anyOf, out) end
    return out
end

-- The guide's ITEM step whose own id (either half) is this item, or nil:
-- how the communal key's step lends its name to the key that lists it
local function ItemStepById(guide, id)
    local steps = type(guide) == "table" and type(guide.steps) == "table" and guide.steps or {}
    for _, s in ipairs(steps) do
        if s.kind == "ITEM" and type(s.item) == "table" and type(s.item.name) == "string" then
            for _, v in ipairs(Numbers(s.item.id)) do
                if v == id then return s end
            end
        end
    end
    return nil
end

-- byKey, per-guide step maps, the kill set and the quest -> steps map, built
-- on first use and rebuilt if the data global is swapped
local function Index()
    local D = Data()
    if E.index and E.index.source == D then return E.index end
    local idx = { source = D, byKey = {}, steps = {}, killSet = {}, encounterNpcs = {}, questSteps = {}, order = {} }
    if D then
        for _, g in ipairs(D.guides) do
            if type(g) == "table" and g.key then
                idx.byKey[g.key] = g
                idx.order[#idx.order + 1] = g
                local byStep = {}
                idx.steps[g.key] = byStep
                for _, s in ipairs(type(g.steps) == "table" and g.steps or EMPTY) do
                    if type(s) == "table" and s.key then
                        byStep[s.key] = s
                        if s.kind == "KILL" and type(s.inside) == "table" then
                            local npcs = type(s.inside.npcs) == "table" and s.inside.npcs or EMPTY
                            for _, npc in ipairs(npcs) do idx.killSet[npc] = true end
                            -- a full clear's encounter stands for its own creature
                            -- only (one to one) or for none (the Opera's several),
                            -- never for the whole raid
                            local encs = type(s.inside.encounters) == "table" and s.inside.encounters or EMPTY
                            for i, enc in ipairs(encs) do
                                local list = idx.encounterNpcs[enc] or {}
                                idx.encounterNpcs[enc] = list
                                if not s.inside.full then
                                    for _, npc in ipairs(npcs) do list[#list + 1] = npc end
                                elseif #npcs == #encs then
                                    list[#list + 1] = npcs[i]
                                end
                            end
                        end
                        for _, id in ipairs(AllQuestIds(s)) do
                            local list = idx.questSteps[id] or {}
                            idx.questSteps[id] = list
                            list[#list + 1] = { guide = g, step = s }
                        end
                    end
                end
            end
        end
    end
    A.byKey = idx.byKey
    E.index = idx
    return idx
end

local function StepOf(guide, stepKey)
    if type(guide) ~= "table" or not stepKey then return nil end
    local map = Index().steps[guide.key]
    return map and map[stepKey] or nil
end

local function InstanceName(id)
    local D = Data()
    local name = D and type(D.INSTANCES) == "table" and D.INSTANCES[id]
    if type(name) == "string" then return name end
    return "instance " .. tostring(id)
end

local function PhaseRow(n)
    local D = Data()
    if not (D and type(D.PHASES) == "table") then return nil end
    for _, p in ipairs(D.PHASES) do
        if type(p) == "table" and p.n == n then return p end
    end
    return D.PHASES[n]
end

local function ShortOf(n)
    local row = PhaseRow(n)
    if row and type(row.short) == "string" then return row.short end
    return "Phase " .. tostring(n)
end

-- ---------------------------------------------------------------------------
-- Generations, listeners, the facts table
--
-- `ctx` is one table whose fields are served by name through a metatable:
-- every read names a domain, the domain's slice is rebuilt if its generation
-- moved since it was last built, and the read is recorded on every open
-- detection so the step's memo knows which generations it depends on.
-- ---------------------------------------------------------------------------

-- The quiet half: the generations move and nobody is told. For writes made
-- inside the window's own pass (the log index, the ledger), where a listener
-- call would only queue a second pass over nothing new.
local function Bump(domain)
    E.gen[domain] = (E.gen[domain] or 0) + 1
    E.fresh[domain] = false
    A.generation = A.generation + 1
end

function A.Invalidate(domain)
    if type(domain) ~= "string" then return end
    Bump(domain)
    for _, fn in ipairs(E.listeners) do pcall(fn, domain) end
end

function A.AddListener(fn)
    if type(fn) ~= "function" then return end
    for _, f in ipairs(E.listeners) do
        if f == fn then return end
    end
    E.listeners[#E.listeners + 1] = fn
end

local NAME_DOMAIN = {
    quests = "quests", completed = "quests", onQuest = "quests", logState = "quests",
    items = "items", keyring = "items", count = "items", badges = "items",
    reps = "reps", rep = "reps",
    char = "char", level = "char", class = "char", faction = "char", race = "char",
    spells = "spells", known = "spells",
    skills = "skills",
    locks = "locks",
    world = "world", instanceId = "world", instanceDifficulty = "world", dungeonDifficulty = "world",
    instanceType = "world",
    store = "store", marks = "store", seen = "store", kills = "store", talked = "store", entered = "store",
    touched = "store", guide = "store", side = "store", account = "store",
    phase = "phase",
}

local BUILD = {}

local function Record(domain)
    local stack = E.readStack
    for i = 1, #stack do stack[i][domain] = true end
end

local function Slice(domain)
    if not E.fresh[domain] then
        E.slice[domain] = BUILD[domain]()
        E.fresh[domain] = true
    end
    return E.slice[domain]
end

local ctx = setmetatable({}, {
    __index = function(_, name)
        local domain = NAME_DOMAIN[name]
        if not domain then return nil end
        Record(domain)
        local slice = Slice(domain)
        if name == domain then return slice end
        return slice[name]
    end,
    __newindex = function() end,
})

function A.Context() return ctx end

-- A table that computes a value per key on first read and keeps it (false
-- for "nothing")
local function LazyMap(compute)
    return setmetatable({}, {
        __index = function(t, id)
            local v = compute(id)
            if v == nil then v = false end
            rawset(t, id, v)
            return v
        end,
    })
end

do
    local function Flagged(id)
        id = tonumber(id)
        if not (id and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) then return false end
        local ok, v = pcall(C_QuestLog.IsQuestFlaggedCompleted, id)
        return ok and v == true
    end

    local function OnQuest(id)
        id = tonumber(id)
        if not id then return false end
        if C_QuestLog and C_QuestLog.IsOnQuest then
            local ok, v = pcall(C_QuestLog.IsOnQuest, id)
            if ok and v then return true end
        end
        if GetQuestLogIndexByID then
            local ok, i = pcall(GetQuestLogIndexByID, id)
            if ok and tonumber(i) and i > 0 then return true end
        end
        return E.logIndex["id:" .. id] ~= nil
    end

    local function HaveNeed(text)
        if type(text) ~= "string" then return nil end
        local have, need = text:match("(%d+)%s*/%s*(%d+)")
        return tonumber(have), tonumber(need)
    end

    local function LogState(id)
        id = tonumber(id)
        if not id then return false end
        local entry = E.logIndex["id:" .. id]
        local ready, failed, objectives = false, false, nil
        local index
        if GetQuestLogIndexByID then
            local ok, i = pcall(GetQuestLogIndexByID, id)
            if ok and tonumber(i) and i > 0 then index = i end
        end
        if index and GetQuestLogTitle then
            local ok, _, _, _, _, _, isComplete = pcall(GetQuestLogTitle, index)
            if ok then
                if isComplete == 1 or isComplete == true then ready = true end
                if isComplete == -1 then failed = true end
            end
        elseif IsQuestComplete then
            local ok, v = pcall(IsQuestComplete, id)
            if ok and v then ready = true end
        end
        if C_QuestLog and C_QuestLog.GetQuestObjectives then
            local ok, list = pcall(C_QuestLog.GetQuestObjectives, id)
            if ok and type(list) == "table" and #list > 0 then
                objectives = {}
                for _, o in ipairs(list) do
                    if type(o) == "table" then
                        local have, need = tonumber(o.numFulfilled), tonumber(o.numRequired)
                        if not (have and need) then have, need = HaveNeed(o.text) end
                        objectives[#objectives + 1] = { text = o.text, finished = o.finished and true or false, have = have, need = need }
                    end
                end
            end
        end
        if not objectives and type(entry) == "table" and type(entry.objectives) == "table" then
            objectives = {}
            for _, o in ipairs(entry.objectives) do
                if type(o) == "table" then
                    local have, need = tonumber(o.have), tonumber(o.need)
                    if not (have and need) then have, need = HaveNeed(o.text) end
                    objectives[#objectives + 1] = { text = o.text, finished = o.finished and true or false, have = have, need = need }
                end
            end
        end
        if not index and type(entry) == "table" then
            if entry.isComplete then ready = true end
            if entry.isFailed then failed = true end
        end
        if not index and not entry and not OnQuest(id) then return false end
        return { ready = ready, failed = failed, objectives = objectives or {} }
    end

    BUILD.quests = function()
        return { completed = LazyMap(Flagged), onQuest = LazyMap(OnQuest), logState = LazyMap(LogState) }
    end

    BUILD.items = function()
        local keyring = {}
        if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID then
            local ok, n = pcall(C_Container.GetContainerNumSlots, -2)
            if ok and tonumber(n) then
                for slot = 1, n do
                    local ok2, id = pcall(C_Container.GetContainerItemID, -2, slot)
                    if ok2 and tonumber(id) then keyring[id] = true end
                end
            end
        end
        local getCount = (C_Item and C_Item.GetItemCount) or GetItemCount
        local cache = {}
        local function count(id)
            id = tonumber(id)
            if not id then return 0 end
            local c = cache[id]
            if c == nil then
                c = 0
                if getCount then
                    local ok, v = pcall(getCount, id, true)
                    if ok and tonumber(v) then c = v end
                end
                if keyring[id] and c < 1 then c = 1 end
                cache[id] = c
            end
            return c
        end
        return { keyring = keyring, count = count, badges = count(BADGE_ITEM) }
    end

    BUILD.reps = function()
        return {
            rep = LazyMap(function(fid)
                fid = tonumber(fid)
                if not (fid and GetFactionInfoByID) then return false end
                local ok, name, _, standingID, barMin, barMax, barValue = pcall(GetFactionInfoByID, fid)
                if not ok or type(name) ~= "string" or name == "" then return false end
                return { name = name, standingID = tonumber(standingID) or 4, barMin = tonumber(barMin) or 0,
                    barMax = tonumber(barMax) or 0, barValue = tonumber(barValue) or 0 }
            end),
        }
    end

    BUILD.char = function()
        local level, class, faction, race = 1, "UNKNOWN", "A", nil
        if UnitLevel then
            local ok, v = pcall(UnitLevel, "player")
            if ok and tonumber(v) then level = v end
        end
        if UnitClass then
            local ok, _, file = pcall(UnitClass, "player")
            if ok and type(file) == "string" then class = file end
        end
        if UnitFactionGroup then
            local ok, tag = pcall(UnitFactionGroup, "player")
            if ok and tag == "Horde" then faction = "H" end
        end
        if UnitRace then
            local ok, _, file = pcall(UnitRace, "player")
            if ok and type(file) == "string" then race = file end
        end
        return { level = level, class = class, faction = faction, race = race }
    end

    BUILD.spells = function()
        local cache = {}
        local function known(id)
            id = tonumber(id)
            if not id then return false end
            local v = cache[id]
            if v == nil then
                v = false
                if C_SpellBook and C_SpellBook.IsSpellKnown then
                    local ok, r = pcall(C_SpellBook.IsSpellKnown, id)
                    v = ok and r == true
                else
                    if IsPlayerSpell then
                        local ok, r = pcall(IsPlayerSpell, id)
                        if ok and r then v = true end
                    end
                    if not v and IsSpellKnown then
                        local ok, r = pcall(IsSpellKnown, id)
                        if ok and r then v = true end
                    end
                end
                cache[id] = v
            end
            return v
        end
        return { known = known }
    end

    -- The skill pane walked once, headers skipped, never expanded
    BUILD.skills = function()
        local skills = {}
        if GetNumSkillLines and GetSkillLineInfo then
            local ok, n = pcall(GetNumSkillLines)
            if ok and tonumber(n) then
                for i = 1, n do
                    local ok2, name, isHeader, _, rank = pcall(GetSkillLineInfo, i)
                    if ok2 and type(name) == "string" and not isHeader then skills[name] = tonumber(rank) or 0 end
                end
            end
        end
        return skills
    end

    BUILD.locks = function()
        local locks = {}
        if GetNumSavedInstances and GetSavedInstanceInfo then
            local ok, n = pcall(GetNumSavedInstances)
            if ok and tonumber(n) then
                for i = 1, n do
                    local ok2, name, _, reset, difficultyID, locked, _, _, _, _, _, encountersTotal, encountersCompleted, _, mapID =
                        pcall(GetSavedInstanceInfo, i)
                    mapID = tonumber(mapID)
                    if ok2 and mapID then
                        local row = { name = name, difficultyID = tonumber(difficultyID), reset = tonumber(reset),
                            encountersTotal = tonumber(encountersTotal) or 0, encountersCompleted = tonumber(encountersCompleted) or 0,
                            bosses = {}, bossList = {}, locked = locked and true or false }
                        if GetSavedInstanceEncounterInfo then
                            local limit = row.encountersTotal > 0 and row.encountersTotal or 20
                            for j = 1, limit do
                                local ok3, bossName, _, isKilled = pcall(GetSavedInstanceEncounterInfo, i, j)
                                if not ok3 or type(bossName) ~= "string" then break end
                                row.bossList[#row.bossList + 1] = bossName
                                row.bosses[bossName] = isKilled and true or false
                            end
                        end
                        local existing = locks[mapID]
                        if not existing or (not existing.locked and row.locked) then locks[mapID] = row end
                    end
                end
            end
        end
        return locks
    end

    BUILD.world = function()
        local instanceId, instanceDifficulty, instanceType
        if GetInstanceInfo then
            local ok, _, kind, difficultyID, _, _, _, _, id = pcall(GetInstanceInfo)
            if ok then
                instanceType = kind
                instanceDifficulty = tonumber(difficultyID)
                instanceId = tonumber(id)
            end
        end
        local dd
        if GetDungeonDifficultyID then
            local ok, v = pcall(GetDungeonDifficultyID)
            if ok then dd = tonumber(v) end
        end
        return { instanceId = instanceId, instanceDifficulty = instanceDifficulty, dungeonDifficulty = dd,
            instanceType = instanceType }
    end

    BUILD.store = function()
        local at = Char()
        local db = DB()
        local account = db and type(db.AttuneAccount) == "table" and db.AttuneAccount or EMPTY
        return { marks = at.marks, seen = at.seen, kills = at.kills, talked = at.talked, entered = at.entered,
            touched = at.touched, guide = at.guide, side = at.side, account = account }
    end
end

-- ---------------------------------------------------------------------------
-- Faction, side, class: Pick
-- ---------------------------------------------------------------------------

local function NormSide(s)
    if s == "SCRYERS" then return "SCRYER" end
    return s
end

-- -> "ALDOR"|"SCRYER"|nil, why. The bars first: the pledge flag is permanent
-- and a side swap is done by item turn-ins, so a flag-first rule would call
-- a now-Scryers character Aldor for ever. `c` is the engine's ctx unless a
-- caller hands in a context of its own (A.Detect is pure over the one given).
local function SideOf(c)
    c = c or ctx
    local reps = c.rep or EMPTY
    local aldor, scryer = reps[932], reps[934]
    if aldor and scryer then
        if aldor.standingID >= 5 and scryer.standingID <= 3 then return "ALDOR", "standings" end
        if scryer.standingID >= 5 and aldor.standingID <= 3 then return "SCRYER", "standings" end
    end
    local completed, seen = c.completed or EMPTY, c.seen or EMPTY
    if completed[10551] or seen[10551] then return "ALDOR", "pledged" end
    if completed[10552] or seen[10552] then return "SCRYER", "pledged" end
    local chosen = NormSide(c.side)
    if chosen == "ALDOR" or chosen == "SCRYER" then return chosen, "chosen by you" end
    return nil
end

local function Pick(v, c)
    if type(v) ~= "table" then return v end
    c = c or ctx
    if v.A ~= nil or v.H ~= nil then return v[c.faction] end
    if v.ALDOR ~= nil or v.SCRYER ~= nil or v.SCRYERS ~= nil then
        local side = SideOf(c)
        if not side then return nil, "undecided" end
        if side == "SCRYER" then
            if v.SCRYER ~= nil then return v.SCRYER end
            return v.SCRYERS
        end
        return v.ALDOR
    end
    return v
end

function A.Faction() return ctx.faction end
function A.Class() return ctx.class end
function A.Level() return ctx.level end
function A.Side() return SideOf() end

-- ---------------------------------------------------------------------------
-- Phase resolution and evidence
-- ---------------------------------------------------------------------------

local EVIDENCE_RANK = { lockout = 3, quest = 2, instance = 1 }

local function EvidenceSentence(row)
    local d = tostring(row.detail or "")
    if row.kind == "lockout" then return "you hold a " .. d end
    if row.kind == "instance" then return "you have been " .. d end
    local id = d:match("quest (%d+)") or ""
    if d:find("flagged", 1, true) then return "quest " .. id .. " is flagged complete" end
    return "quest " .. id .. " is in your log"
end

-- Strongest row per phase, sorted by n
function A.Evidence()
    local best = {}
    local db = DB()
    local seen = db and db.AttunePhaseSeen
    if type(seen) == "table" then
        for _, row in pairs(seen) do
            local n = type(row) == "table" and tonumber(row.n)
            if n then
                local old = best[n]
                if not old or (EVIDENCE_RANK[row.kind] or 0) > (EVIDENCE_RANK[old.kind] or 0) then
                    best[n] = { n = n, kind = row.kind, detail = row.detail, when = row.when }
                end
            end
        end
    end
    local out = {}
    for _, row in pairs(best) do out[#out + 1] = row end
    tsort(out, function(a, b) return a.n < b.n end)
    return out
end

-- Write-only: a row per phase, the strongest kept; the per-character mirror
-- written at the same time; never lowers anything
local function WriteEvidence(n, kind, detail)
    n = tonumber(n)
    if not n then return end
    local rank = EVIDENCE_RANK[kind] or 0
    local when = Now()
    local wrote = false
    local acc = AccountTable("AttunePhaseSeen")
    if acc then
        local old = acc[n]
        if type(old) ~= "table" or (EVIDENCE_RANK[old.kind] or 0) < rank then
            acc[n] = { n = n, kind = kind, detail = detail, when = when }
            wrote = true
        end
    end
    local mine = Char().phaseEvidence
    local old = mine[n]
    if type(old) ~= "table" or (EVIDENCE_RANK[old.kind] or 0) < rank then
        mine[n] = { n = n, kind = kind, detail = detail, when = when }
        wrote = true
    end
    if wrote then A.Invalidate("phase") end
end

do
    local function CalendarPhase(now)
        local D = Data()
        local best = 1
        if D and type(D.PHASES) == "table" then
            for _, p in ipairs(D.PHASES) do
                if type(p) == "table" and type(p.since) == "number" and p.since <= now and (tonumber(p.n) or 0) > best then
                    best = p.n
                end
            end
        end
        return best
    end

    local function QuestiePhase()
        if type(QuestieLoader) ~= "table" or type(QuestieLoader._modules) ~= "table" then return nil end
        local ok, v = pcall(function() return QuestieLoader._modules.ContentPhases.activePhases.TBC end)
        v = ok and tonumber(v) or nil
        if v and v >= 1 and v <= 5 then return floor(v) end
        return nil
    end

    local function Setting()
        local db = DB()
        local v = db and db.AttunePhase
        local n = tonumber(v)
        if n and n >= 1 and n <= 5 then return floor(n) end
        return "AUTO"
    end

    BUILD.phase = function()
        local now = Now()
        local calendar = CalendarPhase(now)
        local questie = QuestiePhase()
        local evidence, evidenceWhy
        for _, row in ipairs(A.Evidence()) do
            if not evidence or row.n > evidence then evidence, evidenceWhy = row.n, EvidenceSentence(row) end
        end
        local auto, source = calendar, "calendar"
        if evidence and evidence > auto then auto, source = evidence, "evidence" end
        if questie and questie > auto then auto, source = questie, "questie" end
        local setting = Setting()
        local n, why
        if setting ~= "AUTO" then
            n, source = setting, "setting"
            why = format("Phase %d, set by you; the calendar says Phase %d.", n, calendar)
        else
            n = auto
            if source == "calendar" then
                local row = PhaseRow(n)
                if row and type(row.since) == "number" then
                    why = format("Phase %d since %s, from the calendar.", n, DateWord(row.since, true, true))
                else
                    why = format("Phase %d, from the calendar.", n)
                end
            elseif source == "evidence" then
                why = format("Phase %d: %s.", n, evidenceWhy)
            else
                why = format("Phase %d: Questie says so.", n)
            end
        end
        local row = PhaseRow(n)
        return { n = n, source = source, since = row and row.since or false, why = why,
            votes = { calendar = calendar, questie = questie, evidence = evidence, evidenceWhy = evidenceWhy, setting = setting } }
    end

    function A.Phase()
        local p = ctx.phase
        return p.n, p.source, p.since, p.why, p.votes
    end

    function A.PhaseName(n)
        local row = PhaseRow(n)
        if row then return row.short or ("Phase " .. tostring(n)), row.name or "", row.blizzard or "" end
        return "Phase " .. tostring(n), "", ""
    end

    function A.Rules(n)
        local D = Data()
        n = n or ctx.phase.n
        local row = D and type(D.RULES) == "table" and D.RULES[n]
        if type(row) == "table" then return row end
        return EMPTY_RULES
    end

    -- Words for the rule keys that may rest on inference (identifiers never
    -- reach the sheet)
    local GATE_WORDS = { KARAZHAN = "Karazhan", SSC = "Serpentshrine Cavern", TK = "Tempest Keep", HYJAL = "Mount Hyjal",
        BT = "the Black Temple", HEROIC = "heroic dungeons", DAILY_HEROIC = "the heroic daily", GRUUL_MAG = "Gruul's and Magtheridon's Lairs",
        SSC_TK = "Serpentshrine Cavern and Tempest Keep", ZA = "Zul'Aman", ZA_QUESTS = "the Zul'Aman quests", WORLD_BOSS = "the world bosses",
        HYJAL_BT = "Mount Hyjal and the Black Temple", SUNWELL = "Sunwell Plateau", MGT = "Magisters' Terrace", ISLE = "the Isle of Quel'Danas",
        OGRILA = "Ogri'la", SKYGUARD = "the Skyguard", NETHERWING = "Netherwing" }
    local RULE_WORDS = { heroicKeyStanding = "the standing the heroic keys cost", communalPouches = "the communal pouches",
        heroicTuning = "the heroic tuning", vendorStock = "the badge vendor's stock", raidsOpen = "which raids are open" }
    local function AssumedWords(key)
        key = tostring(key)
        if RULE_WORDS[key] then return RULE_WORDS[key] end
        local head, tail = key:match("^(%w+)%.(.+)$")
        if head then
            local what = GATE_WORDS[tail] or tail:lower():gsub("_", " ")
            if head == "attunementRequired" then return "whether " .. what .. " needs attunement" end
            if head == "badgeSources" then return "whether badges drop in " .. what end
            if head == "live" then return "whether " .. what .. " is live" end
            return what
        end
        return (key:lower():gsub("[_%.]", " "))
    end

    function A.PhaseSentences(n)
        local rules = A.Rules(n)
        local out = {}
        for _, s in ipairs(type(rules.sentences) == "table" and rules.sentences or EMPTY) do out[#out + 1] = s end
        if type(rules.assumed) == "table" and #rules.assumed > 0 then
            local words = {}
            for _, k in ipairs(rules.assumed) do words[#words + 1] = AssumedWords(k) end
            out[#out + 1] = "Some of this phase's rules rest on inference: " .. tconcat(words, ", ") .. "."
        end
        return out
    end

    function A.SetPhase(value)
        local db = DB()
        if not db then return end
        local n = tonumber(value)
        if n and n >= 1 and n <= 5 then db.AttunePhase = floor(n) else db.AttunePhase = "AUTO" end
        A.Invalidate("phase")
    end
end

-- ---------------------------------------------------------------------------
-- Standing words (the Reputations tab's Labels pattern) and RepLine
-- ---------------------------------------------------------------------------

local function Labels()
    if E.labels then return E.labels end
    local out, sex = {}, nil
    if UnitSex then
        local ok, value = pcall(UnitSex, "player")
        if ok then sex = value end
    end
    for n = 1, 8 do
        local text
        if GetText then
            local ok, value = pcall(GetText, "FACTION_STANDING_LABEL" .. n, sex)
            if ok then text = value end
        end
        if type(text) ~= "string" or text == "" then text = _G["FACTION_STANDING_LABEL" .. n] end
        if type(text) == "string" and text ~= "" then out[n] = text end
    end
    E.labels = out
    return out
end

local ENGLISH = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }

local function StandingWord(rank, labels)
    local R = Q.Standing
    if R and R.StandingWord then
        local w = R.StandingWord(rank, labels)
        if w then return w end
    end
    rank = tonumber(rank) or 3
    return (labels and labels[rank + 1]) or ENGLISH[rank + 1] or "Neutral"
end

local function FormatNumber(n)
    local R = Q.Standing
    if R and R.FormatNumber then
        local s = R.FormatNumber(n)
        if s then return s end
    end
    return tostring(floor(tonumber(n) or 0))
end

-- "Honored 4,250 of 12,000": the one rendering of a standing's quantity
local function RepLine(entry, labels)
    return StandingWord(entry.standingID - 1, labels) .. " " .. FormatNumber(entry.barValue - entry.barMin) .. " of "
        .. FormatNumber(entry.barMax - entry.barMin)
end

-- ---------------------------------------------------------------------------
-- Detectors: DETECT[kind](step, guide) -> status, reason, progress
-- ---------------------------------------------------------------------------

local DETECT = {}
local Detected   -- the memoised worker, assigned below

-- Reads over a context that may be hand-built (A.Detect is pure over the one
-- it is given): a field that is not there is nothing
local function Field(c, name, id)
    local t = c[name]
    if type(t) ~= "table" or id == nil then return false end
    local v = t[id]
    if v == nil or v == false then return false end
    return v
end

local function Count(c, id)
    id = tonumber(id)
    if not id then return 0 end
    local f = c.count
    if type(f) == "function" then
        local ok, v = pcall(f, id)
        return ok and tonumber(v) or 0
    end
    if type(f) == "table" then return tonumber(f[id]) or 0 end
    return 0
end

local function Known(c, id)
    id = tonumber(id)
    if not id then return false end
    local f = c.known
    if type(f) == "function" then
        local ok, v = pcall(f, id)
        return ok and v == true
    end
    if type(f) == "table" then return f[id] == true end
    return false
end

local function Table(c, name)
    local t = c[name]
    if type(t) == "table" then return t end
    return EMPTY
end

local function QuestCandidates(step, c)
    local ids = {}
    local function add(v)
        v = tonumber(v)
        if not v then return end
        for _, e in ipairs(ids) do
            if e == v then return end
        end
        ids[#ids + 1] = v
    end
    local q, why = Pick(step.questId, c)
    if q == nil and why == "undecided" and type(step.questId) == "table" then
        add(step.questId.ALDOR); add(step.questId.SCRYER); add(step.questId.SCRYERS)
    else
        add(q)
    end
    local alts = Pick(step.altQuestIds, c)
    if type(alts) == "table" then
        for _, v in ipairs(alts) do add(v) end
    end
    if step.questMode == "ANY" and type(step.questIds) == "table" then
        for _, v in ipairs(step.questIds) do add(v) end
    end
    return ids
end

local function ItemIds(item, c)
    local ids = {}
    if type(item) ~= "table" then return ids end
    local id = Pick(item.id, c)
    if tonumber(id) then ids[#ids + 1] = tonumber(id) end
    local any = Pick(item.anyOf, c)
    if type(any) == "table" then
        for _, v in ipairs(any) do
            if tonumber(v) then ids[#ids + 1] = tonumber(v) end
        end
    end
    return ids
end

do
    local function ObjectiveProgress(state)
        if type(state) ~= "table" or type(state.objectives) ~= "table" then return nil end
        for _, o in ipairs(state.objectives) do
            if not o.finished then
                if o.have and o.need then return { have = o.have, need = o.need } end
                return nil
            end
        end
        return nil
    end

    local function LogAnswer(c, id)
        local st = Field(c, "logState", id)
        if st and st.failed then return "FAILED", "Failed in your log" end
        if st and st.ready then return "READY", "Complete in your log: hand it in" end
        return "LOG", "In your log", ObjectiveProgress(st)
    end

    -- The flag, or a turn-in seen within the grace window standing in for it
    local function Flagged(c, id, now)
        if Field(c, "completed", id) then return true end
        local t = tonumber(Field(c, "seen", id))
        if t and now - t <= GRACE then return "seen" end
        return false
    end

    local function OnQuest(c, id)
        return Field(c, "onQuest", id) and true or false
    end

    DETECT.LEVEL = function(step, _, c)
        local need = (type(step.levelByClass) == "table" and tonumber(step.levelByClass[c.class])) or tonumber(step.level) or 1
        local have = tonumber(c.level) or 1
        if have >= need then return "DONE", format("You are level %d", have) end
        return "LOCKED", format("Level %d of %d", have, need), { have = have, need = need }
    end

    DETECT.QUEST = function(step, _, c)
        local ids = QuestCandidates(step, c)
        local daily = step.daily == true
        local now = Now()
        local list = type(step.questIds) == "table" and step.questIds or nil
        if step.accept then
            for _, id in ipairs(ids) do
                if Flagged(c, id, now) or OnQuest(c, id) then return "DONE", "Accepted" end
            end
        end
        if list and step.questMode == "ALL" then
            local n, flagged = #list, 0
            for _, id in ipairs(list) do
                if Flagged(c, id, now) then flagged = flagged + 1 end
            end
            if n > 0 and flagged >= n then return "DONE", "Flagged complete" end
            if flagged > 0 then return "PARTIAL", format("%d of %d quests done", flagged, n), { have = flagged, need = n } end
            for _, id in ipairs(list) do
                if OnQuest(c, id) then return LogAnswer(c, id) end
            end
            return "OPEN", daily and "Available today" or "Not started"
        end
        local justSeen = false
        for _, id in ipairs(ids) do
            local f = Flagged(c, id, now)
            if f == true then return "DONE", daily and "Handed in today" or "Flagged complete" end
            if f == "seen" then justSeen = true end
        end
        for _, id in ipairs(type(step.impliedBy) == "table" and step.impliedBy or EMPTY) do
            if Field(c, "completed", id) then return "DONE", "Implied: a later quest is complete" end
        end
        if justSeen then return "DONE", "Just handed in" end
        if list and step.questMode == "CHAIN" then
            local n, flagged = #list, 0
            for _, id in ipairs(list) do
                if Flagged(c, id, now) then flagged = flagged + 1 end
            end
            for _, id in ipairs(list) do
                if OnQuest(c, id) then
                    local status, reason = LogAnswer(c, id)
                    return status, format("%s; %d of %d quests done", reason, flagged, n), { have = flagged, need = n }
                end
            end
            if flagged > 0 then return "PARTIAL", format("%d of %d quests done", flagged, n), { have = flagged, need = n } end
            return "OPEN", daily and "Available today" or "Not started"
        end
        for _, id in ipairs(ids) do
            if OnQuest(c, id) then return LogAnswer(c, id) end
        end
        return "OPEN", daily and "Available today" or "Not started"
    end

    -- ITEM or KILL carrying a questId (the Tempest Keep trials, the Arcatraz
    -- shards): the quest decides first. -> status, reason | nil, suffix
    local function WithQuest(step, c)
        local qid = tonumber(Pick(step.questId, c))
        if not qid then return nil end
        -- the same rule as the QUEST detector: the flag, or a turn-in inside the grace
        local f = Flagged(c, qid, Now())
        if f == true then return "DONE", "Flagged complete" end
        if f == "seen" then return "DONE", "Just handed in" end
        local inLog = OnQuest(c, qid)
        if inLog then
            local st = Field(c, "logState", qid)
            if st and type(st.objectives) == "table" then
                local names = {}
                if type(step.item) == "table" and type(step.item.name) == "string" then names[#names + 1] = step.item.name:lower() end
                if type(step.needs) == "table" and type(step.needs.name) == "string" then names[#names + 1] = step.needs.name:lower() end
                local matched
                for _, o in ipairs(st.objectives) do
                    local text = type(o.text) == "string" and o.text:lower() or ""
                    for _, nm in ipairs(names) do
                        if nm ~= "" and text:find(nm, 1, true) then matched = o end
                    end
                    if matched then break end
                end
                if not matched then
                    for _, o in ipairs(st.objectives) do
                        if not o.finished then matched = o; break end
                    end
                end
                if matched and matched.finished then return "DONE", "Objective complete" end
            end
        end
        local have = 0
        for _, id in ipairs(ItemIds(step.item, c)) do have = max(have, Count(c, id)) end
        if type(step.needs) == "table" then
            if tonumber(step.needs.id) then have = max(have, Count(c, step.needs.id)) end
            local any = Pick(step.needs.anyOf, c)
            if type(any) == "table" then
                for _, id in ipairs(any) do have = max(have, Count(c, id)) end
            end
        end
        if have > 0 then return "DONE", "In your bags" end
        return nil, inLog and "; the quest is in your log" or ""
    end

    DETECT.ITEM = function(step, guide, c)
        local suffix = ""
        if step.questId then
            local status, reason = WithQuest(step, c)
            if status then return status, reason end
            suffix = reason or ""
        end
        local item = type(step.item) == "table" and step.item or EMPTY
        local need = tonumber(item.count) or 1
        if need < 1 then need = 1 end
        local have, found = 0, nil
        for _, id in ipairs(ItemIds(item, c)) do
            local n = Count(c, id)
            if n > have then have, found = n, id end
        end
        if have >= need then
            if found and Field(c, "keyring", found) then return "DONE", "In your keyring" end
            return "DONE", "In your bags or bank"
        end
        if have > 0 then
            return "PARTIAL", format("%d of %d %s", have, need, item.name or "needed"), { have = have, need = need }
        end
        if step.consumedBy then
            local other = StepOf(guide, step.consumedBy)
            if other then
                local status
                if c == ctx then status = Detected(guide, other) else status = A.Detect(other, guide, c) end
                if status == "DONE" then return "DONE", "Handed in with " .. (other.title or tostring(step.consumedBy)) end
            end
        end
        return "OPEN", "Not in your bags" .. suffix
    end

    DETECT.REP = function(step, _, c)
        local fid = tonumber(Pick(step.factionId, c))
        local entry = fid and Field(c, "rep", fid) or false
        if type(entry) ~= "table" then entry = false end
        local authored = Pick(step.factionName, c)
        local name = (entry and entry.name) or (type(authored) == "string" and authored) or "this faction"
        if not entry then return "OPEN", format("Not met yet: no %s standing on this character", name) end
        local labels = Labels()
        local line = RepLine(entry, labels)
        local need = tonumber(step.standing) or 8
        if entry.standingID >= need then return "DONE", line end
        return "STANDING", format("%s; %s needed", line, StandingWord(need - 1, labels)),
            { have = entry.barValue - entry.barMin, need = entry.barMax - entry.barMin }
    end

    DETECT.KILL = function(step, _, c)
        local suffix = ""
        if step.questId then
            local status, reason = WithQuest(step, c)
            if status then return status, reason end
            suffix = reason or ""
        end
        local inside = type(step.inside) == "table" and step.inside or EMPTY
        local L = inside.instance and Field(c, "locks", inside.instance) or nil
        if type(L) ~= "table" then L = nil end
        if L and inside.heroic and L.difficultyID ~= 2 then L = nil end
        -- an expired row lingering in the list is no lockout for a weekly or full step
        if L and (step.weekly or inside.full) and (L.locked == false or (tonumber(L.reset) or 1) <= 0) then L = nil end
        if L and not inside.full then
            local bosses = type(L.bosses) == "table" and L.bosses or EMPTY
            local bossList = type(L.bossList) == "table" and L.bossList or EMPTY
            if inside.boss and bosses[inside.boss] then return "DONE", "Killed this lockout" .. suffix end
            if type(inside.encounters) == "table" and C_RaidLocks and C_RaidLocks.IsEncounterComplete then
                for _, enc in ipairs(inside.encounters) do
                    local ok, v = pcall(C_RaidLocks.IsEncounterComplete, inside.instance, enc)
                    if ok and v then return "DONE", "Killed this lockout" .. suffix end
                end
            end
            if inside.last and #bossList > 0 and bosses[bossList[#bossList]] then
                return "DONE", "Killed this lockout" .. suffix
            end
        end
        local now = Now()
        local cutoff
        if step.weekly then
            local span = LOCKOUT_SPAN[inside.instance] or WEEK
            local untilReset = L and tonumber(L.reset)
            if untilReset then
                cutoff = now + untilReset - span
            else
                if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
                    local ok, v = pcall(C_DateAndTime.GetSecondsUntilWeeklyReset)
                    if ok then untilReset = tonumber(v) end
                end
                cutoff = now + (untilReset or 0) - WEEK
                if span < WEEK then cutoff = max(cutoff, now - span) end
            end
        end
        local kills = Table(c, "kills")
        -- a kill this lockout: a weekly kill carrying its lockout's end counts
        -- until then; one without falls back to the cutoff
        local function When(k)
            local when = type(k) == "table" and tonumber(k.when) or tonumber(k)
            if not when then return nil end
            if step.weekly then
                local till = type(k) == "table" and tonumber(k["until"]) or nil
                if till then return (till > now) and when or nil end
            end
            if cutoff and when < cutoff then return nil end
            return when
        end
        local npcs = type(inside.npcs) == "table" and inside.npcs or EMPTY
        if inside.full then
            -- encounters, never one npc: the saved row's count, or the
            -- encounters stamped this lockout (ENCOUNTER_END, or the combat
            -- log where one creature stands for one encounter); the larger
            local encs = type(inside.encounters) == "table" and inside.encounters or EMPTY
            local total = #encs > 0 and #encs or #npcs
            local lockDone = 0
            if L then
                if (tonumber(L.encountersTotal) or 0) > 0 then total = tonumber(L.encountersTotal) end
                lockDone = tonumber(L.encountersCompleted) or 0
            end
            local positional = #npcs == #encs
            local n = 0
            for i, enc in ipairs(encs) do
                if When(kills["enc" .. tostring(enc)]) or (positional and When(kills[npcs[i]])) then n = n + 1 end
            end
            if not positional then
                -- several creatures to one encounter (the Opera): a count
                -- of creatures is only ever progress, never the whole clear
                local stamped = 0
                for _, npc in ipairs(npcs) do
                    if When(kills[npc]) then stamped = stamped + 1 end
                end
                n = max(n, math.min(stamped, total - 1))
            end
            local have = max(lockDone, n)
            if total > 0 and have >= total then return "DONE", format("%d of %d bosses this lockout", total, total) end
            if have > 0 then
                return "PARTIAL", format("%d of %d bosses this lockout", have, total), { have = have, need = total }
            end
        else
            for _, npc in ipairs(npcs) do
                local when = When(kills[npc])
                if when then return "DONE", "Seen fall on " .. DateWord(when) .. suffix end
            end
        end
        if step.weekly then return "OPEN", "Not this lockout" .. suffix end
        return "UNKNOWN", "No lockout shows it: mark it done if you have" .. suffix
    end

    DETECT.SPELL = function(step, _, c)
        if step.spellId and Known(c, step.spellId) then return "DONE", "Known" end
        for _, id in ipairs(type(step.anySpell) == "table" and step.anySpell or EMPTY) do
            if Known(c, id) then return "DONE", "Known" end
        end
        return "OPEN", "Not known"
    end

    DETECT.SKILL = function(step, _, c)
        local sk = type(step.skill) == "table" and step.skill or EMPTY
        local name, rank = sk.name, tonumber(sk.rank) or 0
        local have = type(name) == "string" and tonumber(Table(c, "skills")[name]) or nil
        if have then
            if have >= rank then return "DONE", format("%s %d", name, have) end
            return "PARTIAL", format("%s %d; %d needed", name, have, rank), { have = have, need = rank }
        end
        if step.spellId and Known(c, step.spellId) then return "DONE", "Known" end
        for _, id in ipairs(type(step.anySpell) == "table" and step.anySpell or EMPTY) do
            if Known(c, id) then return "DONE", "Known" end
        end
        return "UNKNOWN", "The skill line was not found, under a collapsed header or in another language: mark it done if you have it"
    end

    DETECT.TALK = function(step, _, c)
        local talked = Table(c, "talked")
        for _, raw in ipairs(type(step.places) == "table" and step.places or EMPTY) do
            local row = Pick(raw, c)
            if type(row) == "table" and row.npc and talked[row.npc] then return "DONE", "Visited" end
        end
        return "OPEN", "Not visited yet"
    end

    DETECT.MANUAL = function(step, _, c)
        local auto = type(step.auto) == "table" and step.auto or nil
        if auto and auto.enteredInstance then
            local _ = c.instanceId   -- the world domain is read so a zone change re-runs this step
            local id = auto.enteredInstance
            local e = Field(c, "entered", id)
            local been = false
            if type(e) == "table" then been = (not auto.heroic) or e.difficulty == 2 end
            if not been then
                local L = Field(c, "locks", id)
                if type(L) == "table" and ((not auto.heroic) or L.difficultyID == 2) then been = true end
            end
            if been then return "DONE", "You have been inside" end
            if step.note then return "NOTE", "" end
            return "OPEN", "Not been inside yet"
        end
        if auto and auto.dungeonDifficulty then
            if c.dungeonDifficulty == 2 then return "SET", "Heroic is selected" end
            return "UNSET", "Normal is selected"
        end
        if step.note then return "NOTE", "" end
        return "UNKNOWN", "Nothing the client can check: mark it done"
    end

    -- Pure over the context given (the engine's own when none is): the
    -- detector's answer, nothing else applied
    function A.Detect(step, guide, c)
        if type(step) ~= "table" then return "UNKNOWN", "No step" end
        if type(c) ~= "table" then c = ctx end
        local fn = DETECT[step.kind]
        if not fn then return "UNKNOWN", "Nothing the client can check: mark it done" end
        local ok, status, reason, progress = pcall(fn, step, guide, c)
        if not ok then
            if geterrorhandler then pcall(geterrorhandler(), status) end
            return "UNKNOWN", "The check failed: mark it done if you have"
        end
        return status, reason or "", progress
    end

    -- Memoised against the generations of the domains the detector read
    Detected = function(guide, step)
        local key = tostring(guide.key) .. ":" .. tostring(step.key)
        local m = E.memo[key]
        if m and m.index == E.index then
            local valid = true
            for domain, g in pairs(m.gens) do
                if (E.gen[domain] or 0) ~= g then valid = false; break end
            end
            if valid then
                for domain in pairs(m.gens) do Record(domain) end
                return m.status, m.reason, m.progress
            end
        end
        local reads = {}
        local stack = E.readStack
        stack[#stack + 1] = reads
        local status, reason, progress = A.Detect(step, guide, ctx)
        stack[#stack] = nil
        local gens = {}
        for domain in pairs(reads) do gens[domain] = E.gen[domain] or 0 end
        E.memo[key] = { gens = gens, status = status, reason = reason, progress = progress, index = E.index }
        return status, reason, progress
    end
end

-- ---------------------------------------------------------------------------
-- Words, tones, the "How the tab knows" templates
-- ---------------------------------------------------------------------------

local WORD = { DONE = "Done", READY = "Ready", LOG = "In log", NEXT = "Next", OPEN = "To do", LOCKED = "Locked",
    SET = "Set", UNSET = "Not set", FAILED = "Failed", OPTIONAL = "Optional", WAIVED = "Not needed",
    UNKNOWN = "Unchecked", NOTE = "" }
local TONE = { DONE = "good", READY = "good", LOG = "log", NEXT = "open", OPEN = "secondary", PARTIAL = "open",
    STANDING = "open", LOCKED = "warn", SET = "log", UNSET = "secondary", FAILED = "bad", OPTIONAL = "faint",
    WAIVED = "faint", LATER = "faint", PAST = "faint", UNKNOWN = "faint", NOTE = "faint" }
local KIND_WORD = { QUEST = "Quest", ITEM = "Item", REP = "Reputation", KILL = "Kill", LEVEL = "Level", SKILL = "Skill",
    SPELL = "Spell", TALK = "Visit", MANUAL = "Visit" }
local ROLE_WORD = { start = "Starts", turnin = "Turn in", vendor = "Vendor", trainer = "Trainer", kill = "Kill",
    spot = "Spot", door = "Door", inside = "Inside", object = "Object" }
local CLASS_WORDS = { DRUID = "druids", ROGUE = "rogues", MAGE = "mages", PRIEST = "priests", WARRIOR = "warriors",
    PALADIN = "paladins", HUNTER = "hunters", SHAMAN = "shamans", WARLOCK = "warlocks" }

local HOW = {}

do
    local function QuestName(step)
        local name = Pick(step.questName)
        if type(name) == "string" and name ~= "" then return name end
        return step.title or "this quest"
    end

    local function SpellName(step)
        local id = tonumber(step.spellId)
        if id and GetSpellInfo then
            local ok, name = pcall(GetSpellInfo, id)
            if ok and type(name) == "string" and name ~= "" then return name end
        end
        return step.title or "its spell"
    end

    HOW.QUEST = function(step, guide)
        local name = QuestName(step)
        if step.accept then
            local later = "a later step"
            local mine = AllQuestIds(step)
            local seen = false
            for _, other in ipairs(type(guide.steps) == "table" and guide.steps or EMPTY) do
                if other == step then seen = true
                elseif seen and other.kind == "QUEST" and not other.accept then
                    for _, id in ipairs(AllQuestIds(other)) do
                        for _, m in ipairs(mine) do
                            if id == m and later == "a later step" then later = other.title or later end
                        end
                    end
                end
            end
            return format("Done once %s is in your log or complete; handing it in is the later step %s.", name, later)
        end
        if step.daily then
            return format("Done when quest %s was handed in since the last daily reset; a daily never counts toward the guide.", name)
        end
        local n = type(step.questIds) == "table" and #step.questIds or 0
        if step.questMode == "CHAIN" and n > 0 then
            return format("Done when %s, the last of %d quests, is flagged complete; the earlier ones show as progress.", name, n)
        end
        if step.questMode == "ALL" and n > 0 then
            return format("Done when all %d quests are flagged complete.", n)
        end
        return format("Done when quest %s is flagged complete on this character (or any of its twins).", name)
    end

    HOW.ITEM = function(step, guide)
        local item = type(step.item) == "table" and step.item or EMPTY
        local name = item.name or step.title or "the item"
        if step.questId then
            return format("Done when quest %s is flagged complete, its objective is met in your log, or %s is in your bags.",
                QuestName(step), name)
        end
        -- the alternatives that tick it too: named from the guide's own ITEM
        -- steps when one or two are; counted otherwise (never a client
        -- lookup, so the sentence is the same on every pass)
        local own, alts, seen = {}, {}, {}
        for _, v in ipairs(Numbers(item.id)) do own[v] = true end
        local picked = Pick(item.anyOf)
        if type(picked) ~= "table" then picked = item.anyOf end
        for _, v in ipairs(Numbers(picked)) do
            if not own[v] and not seen[v] then seen[v] = true; alts[#alts + 1] = v end
        end
        local names, nameSeen, unnamed = {}, {}, false
        for _, v in ipairs(alts) do
            local other = ItemStepById(guide, v)
            local alt = other and other.item.name
            if not alt then unnamed = true
            elseif alt ~= name and not nameSeen[alt] then nameSeen[alt] = true; names[#names + 1] = alt end
        end
        local things = (guide and guide.category == "FLYING") and "mounts" or "items"
        local s
        if #alts == 0 then
            s = format("Done when %s is in your keyring, bags or bank", name)
        elseif item.id == nil and (unnamed or #names > 2) then
            s = format("Done when any of the %d accepted %s is in your bags or bank", #alts, things)
        elseif unnamed or #names > 2 then
            s = format("Done when %s (or any of %d other accepted %s) is in your keyring, bags or bank", name, #alts, things)
        elseif #names > 0 then
            s = format("Done when %s (or %s) is in your keyring, bags or bank", name, tconcat(names, " or "))
        else
            s = format("Done when %s is in your keyring, bags or bank", name)
        end
        if step.consumedBy then
            local other = StepOf(guide, step.consumedBy)
            s = s .. ", or once " .. ((other and other.title) or tostring(step.consumedBy)) .. " is complete"
        end
        return s .. "."
    end

    HOW.REP = function(step)
        local name = Pick(step.factionName)
        if type(name) ~= "string" then name = "this faction's" else name = name end
        return format("Done when your %s standing reaches %s.", name, StandingWord((tonumber(step.standing) or 8) - 1, Labels()))
    end

    HOW.KILL = function(step)
        local inside = type(step.inside) == "table" and step.inside or EMPTY
        local where = inside.instance and InstanceName(inside.instance) or "the instance"
        local boss = inside.boss or "the boss"
        if step.questId then
            return format("Done when quest %s is flagged complete, its objective is met in your log, or %s falls.", QuestName(step), boss)
        end
        if inside.full then
            return format("Done when your saved lockout for %s shows every boss killed; the line counts them until then.", where)
        end
        if step.weekly then
            return format("Done when your saved lockout for %s shows %s killed this lockout, or the tab sees %s die while you are inside; it resets with the instance.",
                where, boss, boss)
        end
        return format("Done when your saved lockout for %s shows %s killed, or the tab sees %s die while you are inside.", where, boss, boss)
    end

    HOW.LEVEL = function(step)
        local s = format("Done at level %d", tonumber(step.level) or 1)
        if type(step.levelByClass) == "table" then
            local parts = {}
            for class, lvl in pairs(step.levelByClass) do
                parts[#parts + 1] = format("level %d for %s", tonumber(lvl) or 0, CLASS_WORDS[class] or tostring(class):lower())
            end
            tsort(parts)
            if #parts > 0 then s = s .. ", or " .. tconcat(parts, ", or ") end
        end
        return s .. "."
    end

    HOW.SKILL = function(step)
        local sk = type(step.skill) == "table" and step.skill or EMPTY
        return format("Done when your %s skill reads %d or more, or you know %s.", sk.name or "riding", tonumber(sk.rank) or 0, SpellName(step))
    end

    HOW.SPELL = function(step)
        return format("Done when you know %s.", SpellName(step))
    end

    HOW.TALK = function()
        return "Ticked when you open this vendor's window."
    end

    HOW.MANUAL = function(step)
        local auto = type(step.auto) == "table" and step.auto or nil
        if auto and auto.enteredInstance then return format("Done once you have been inside %s.", InstanceName(auto.enteredInstance)) end
        if auto and auto.dungeonDifficulty then return "Reads the dungeon difficulty you have selected right now." end
        if step.note then return "A reference line: nothing here is ticked or counted." end
        return "The client cannot see this one: mark it done yourself."
    end
end

local function HowOf(step, guide, markedAt)
    local fn = HOW[step.kind]
    local s = fn and fn(step, guide) or "The client cannot see this one: mark it done yourself."
    if markedAt then s = s .. " Marked by you on " .. DateWord(markedAt) .. "." end
    return s
end

-- ---------------------------------------------------------------------------
-- Places and targets (4.9)
-- ---------------------------------------------------------------------------

local function OrdersGo()
    if type(CommanderOrders) == "table" and type(CommanderOrders.GoTo) == "function" then return CommanderOrders end
    return nil
end

-- The data's rows after Pick; a side-split row with the side undecided is
-- listed once per side, both under its own places[] index
local function RowsOf(step)
    local out = {}
    for i, raw in ipairs(type(step.places) == "table" and step.places or EMPTY) do
        if type(raw) == "table" then
            local row, why = Pick(raw)
            if row == nil and why == "undecided" then
                local a = raw.ALDOR
                local s = raw.SCRYER
                if s == nil then s = raw.SCRYERS end
                if type(a) == "table" then out[#out + 1] = { row = a, i = i, prefix = "Aldor: " } end
                if type(s) == "table" then out[#out + 1] = { row = s, i = i, prefix = "Scryers: " } end
            elseif type(row) == "table" then
                out[#out + 1] = { row = row, i = i }
            end
        end
    end
    return out
end

-- One row -> target, with the door rule: an instance row is a query while
-- Orders has GoTo and only then; the authored coordinates fill the spec in
-- Orders' absence. The test is made here, on every call, never cached.
local function TargetFor(guide, step, questId, row, i, name)
    if row.item and row.role == "start" then return nil, "Starts from an item" end
    local t = { questId = questId, title = name, note = step.title }
    local map, x, y = tonumber(row.map), tonumber(row.x), tonumber(row.y)
    local coords = (map and x and y) and { map = map, x = x / 100, y = y / 100, title = name } or nil
    if row.instance then
        t.query = { entrance = { instance = row.instance } }
        if coords then
            t.fallback = coords
            if not OrdersGo() then t.spec = coords end
        end
    elseif coords then
        t.spec = coords
        t.fallback = coords
    elseif row.npc then
        t.query = { npc = row.npc }
    else
        return nil, "Nowhere to go"
    end
    if step.kind == "QUEST" and (row.role == "start" or row.role == "turnin") and questId then
        t.key = "quest:" .. questId
    else
        t.key = format("attune:%s:%s:%d", tostring(guide.key), tostring(step.key), i)
    end
    return t
end

-- The step view's places, with the data behind each kept aside for PlaceFor
local function PlacesOf(guide, step, questId)
    local out = {}
    local rows = RowsOf(step)
    local hasStart = false
    for _, r in ipairs(rows) do
        if r.row.role == "start" then hasStart = true end
    end
    if step.kind == "QUEST" and not hasStart and questId and Q.Questie and Q.Questie.Starter then
        local ok, st = pcall(Q.Questie.Starter, questId)
        if ok and type(st) == "table" and tonumber(st.uiMapId) and tonumber(st.x) and tonumber(st.y) then
            rows[#rows + 1] = { row = { role = "start", name = st.name or "Quest giver", zone = st.zoneName, map = st.uiMapId, x = st.x, y = st.y },
                i = #rows + 1 }
        end
    end
    for _, r in ipairs(rows) do
        local row = r.row
        local name = (r.prefix or "") .. (row.name or (row.instance and InstanceName(row.instance)) or "")
        local place = {
            role = row.role, roleWord = ROLE_WORD[row.role] or "Spot", name = name,
            zoneName = row.zone or (row.instance and InstanceName(row.instance)) or nil,
            target = (TargetFor(guide, step, questId, row, r.i, name)),
        }
        E.placeData[place] = { guide = guide, step = step, questId = questId, row = row, i = r.i, name = name }
        out[#out + 1] = place
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Marks (4.6)
-- ---------------------------------------------------------------------------

local function MarkKey(guideKey, stepKey)
    if stepKey then return tostring(guideKey) .. ":" .. tostring(stepKey) end
    return tostring(guideKey)
end

-- -> epoch|nil; a weekly mark past its until is nil
local function MarkOf(guideKey, stepKey)
    local m = ctx.marks[MarkKey(guideKey, stepKey)]
    if type(m) == "table" then
        local till = tonumber(m["until"])
        if till and Now() >= till then return nil end
        return tonumber(m.at)
    end
    return tonumber(m)
end

function A.IsMarked(guideKey, stepKey) return MarkOf(guideKey, stepKey) end

function A.Touch(guideKey)
    if not guideKey then return end
    local at = Char()
    at.guide = guideKey
    at.touched[guideKey] = Now()
    A.Invalidate("store")
end

function A.Mark(guideKey, stepKey, done)
    if not (guideKey and stepKey) then return end
    local at = Char()
    local key = MarkKey(guideKey, stepKey)
    if done then
        local now = Now()
        local step = StepOf(Index().byKey[guideKey], stepKey)
        if step and step.weekly then
            local inst = type(step.inside) == "table" and step.inside.instance
            local L = inst and ctx.locks[inst]
            local reset = L and tonumber(L.reset) or nil
            if not reset and C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
                local ok, v = pcall(C_DateAndTime.GetSecondsUntilWeeklyReset)
                if ok then reset = tonumber(v) end
            end
            at.marks[key] = { at = now, ["until"] = now + (reset or WEEK) }
        else
            at.marks[key] = now
        end
    else
        at.marks[key] = nil
    end
    A.Touch(guideKey)
end

function A.MarkGuide(guideKey, done)
    if not guideKey then return end
    local at = Char()
    if done then at.marks[MarkKey(guideKey)] = Now() else at.marks[MarkKey(guideKey)] = nil end
    A.Touch(guideKey)
end

function A.ClearMarks()
    local at = Char()
    for k in pairs(at.marks) do at.marks[k] = nil end
    A.Invalidate("store")
end

function A.AccountDone(guideKey)
    local row = ctx.account[guideKey]
    if type(row) == "table" then return { char = row.char, at = row.at } end
    return nil
end

-- ---------------------------------------------------------------------------
-- One guide, evaluated: the step views, the counting, the status (4.5, 4.10)
-- ---------------------------------------------------------------------------

local Evaluate   -- (guide, otherPhases) -> ev; assigned below

do
    local function Hidden(step)
        if step.faction and step.faction ~= "BOTH" and step.faction ~= ctx.faction then return true end
        if step.side then
            local side = SideOf()
            if side and NormSide(step.side) ~= side then return true end
        end
        if type(step.classes) == "table" and #step.classes > 0 then
            local class = ctx.class
            for _, c in ipairs(step.classes) do
                if c == class then return false end
            end
            return true
        end
        return false
    end

    -- nil | "LATER" | "PAST" against the resolved phase
    local function Window(step, n)
        local ph = step.phases
        if type(ph) ~= "table" then return nil end
        local from, to = tonumber(ph.from), tonumber(ph.to)
        if from and from > n then return "LATER" end
        if to and to < n then return "PAST" end
        return nil
    end

    local function LockLevel(step)
        local byClass = type(step.levelByClass) == "table" and tonumber(step.levelByClass[ctx.class]) or nil
        return byClass or tonumber(step.level)
    end

    -- A step that would count: not optional, not a note, not a daily outside
    -- the recurring guide, not a difficulty setting, not a visit
    local function Countable(step, guide)
        if step.optional or step.note then return false end
        if step.daily and not guide.recurring then return false end
        if step.kind == "TALK" then return false end
        if step.kind == "MANUAL" and type(step.auto) == "table" and step.auto.dungeonDifficulty then return false end
        return true
    end

    -- The waiver names the held item: the step whose own id it is first (the
    -- communal key's step says "a Communal Flamewrought Key"), then any step
    -- listing it among its alternatives
    local function ItemWords(guide, id)
        local steps = type(guide.steps) == "table" and guide.steps or EMPTY
        local function Words(s)
            local article = s.item.name:find("^Communal") and "a " or "the "
            return "you already hold " .. article .. s.item.name, s.item.name
        end
        local own = ItemStepById(guide, id)
        if own then return Words(own) end
        for _, s in ipairs(steps) do
            if s.kind == "ITEM" and type(s.item) == "table" and type(s.item.name) == "string" then
                for _, v in ipairs(AllItemIds(s.item)) do
                    if v == id then return Words(s) end
                end
            end
        end
        return "you already hold the key", "the key"
    end

    local function QuestWords(guide, id)
        for _, s in ipairs(type(guide.steps) == "table" and guide.steps or EMPTY) do
            if s.kind == "QUEST" then
                for _, q in ipairs(AllQuestIds(s)) do
                    if q == id then
                        local name = Pick(s.questName)
                        if type(name) ~= "string" then name = s.title or ("quest " .. id) end
                        return "the quest " .. name .. " is complete", name
                    end
                end
            end
        end
        return "the final quest is complete", "the final quest"
    end

    -- -> held, waiver words, proof name, "quest"|"item"
    local function UnlockProof(guide)
        local u = guide.unlock
        if type(u) ~= "table" then return false end
        if u.quest and ctx.completed[u.quest] then
            local words, name = QuestWords(guide, u.quest)
            return true, words, name, "quest"
        end
        for _, id in ipairs(type(u.items) == "table" and u.items or EMPTY) do
            if ctx.count(id) > 0 then
                local words, name = ItemWords(guide, id)
                return true, words, name, "item"
            end
        end
        return false
    end

    -- The key the notice names: the first ITEM step whose ids meet the
    -- unlock items (buy_key before communal_key, so a communal holder still
    -- reads "the Flamewrought Key")
    local function ProofItemName(guide)
        local u = type(guide.unlock) == "table" and guide.unlock or EMPTY
        local wanted = {}
        for _, id in ipairs(type(u.items) == "table" and u.items or EMPTY) do wanted[id] = true end
        for _, s in ipairs(type(guide.steps) == "table" and guide.steps or EMPTY) do
            if s.kind == "ITEM" and type(s.item) == "table" and type(s.item.name) == "string" then
                for _, id in ipairs(AllItemIds(s.item)) do
                    if wanted[id] then return s.item.name end
                end
            end
        end
        return nil
    end

    -- "heroic Hellfire Citadel" / "Karazhan": the place the proof opens.
    -- A heroic key opens the whole citadel, while guide.instance names the
    -- one wing the research picked (540 The Shattered Halls), so a HEROIC
    -- guide takes its place from the title ("Heroic Hellfire Citadel: the
    -- Flamewrought Key") with the leading Heroic lower-cased (3.6, 5.4 item 4)
    local function OpenWords(guide)
        if guide.category == "HEROIC" and type(guide.title) == "string" then
            local place = guide.title:match("^(.-)%s*:")
            if place and place ~= "" then
                return (place:gsub("^Heroic ", "heroic "))
            end
        end
        local D = Data()
        local name = D and type(D.INSTANCES) == "table" and guide.instance and D.INSTANCES[guide.instance]
        if type(name) ~= "string" then name = guide.name or tostring(guide.key) end
        if guide.category == "HEROIC" then name = "heroic " .. (name:gsub("^[Tt]he ", "")) end
        return name
    end

    local function NotCountedPrefix(guide, alt, best)
        if guide.key == "FLYING" then
            if type(alt.prefer) == "table" and alt.prefer[ctx.class] == best then
                return "Not counted: the Flight Form route is preferred for druids"
            end
            return "Not counted: another route is preferred"
        end
        if best == 1 then return "Not counted: the key route is preferred" end
        return "Not counted: another route is preferred"
    end

    local function GateDropped(guide, n)
        local D = Data()
        if not (guide.gate and D and type(D.RULES) == "table") then return nil end
        for p = 1, n do
            local row = D.RULES[p]
            if type(row) == "table" and type(row.attunementRequired) == "table" and row.attunementRequired[guide.gate] == false then
                return p
            end
        end
        return nil
    end

    Evaluate = function(guide, otherPhases)
        local cacheKey = tostring(guide.key) .. (otherPhases and ":1" or ":0")
        local cached = E.guideCache[cacheKey]
        if cached and cached.gen == A.generation and cached.index == E.index then return cached.ev end

        local n = ctx.phase.n
        local rules = A.Rules(n)
        local level = ctx.level
        local views, byKey, raw, det, unlockWaived, notCounted = {}, {}, {}, {}, {}, {}
        local held, heldWords, heldName, heldKind = UnlockProof(guide)
        local guideMark = MarkOf(guide.key, nil)
        local hiddenOther, sideSplit = 0, false
        local undecided = SideOf() == nil

        for _, step in ipairs(type(guide.steps) == "table" and guide.steps or EMPTY) do
            if type(step) == "table" and step.key and not Hidden(step) then
                local w = Window(step, n)
                if w then hiddenOther = hiddenOther + 1 end
                if not w or otherPhases then
                    local v = { key = step.key, kind = step.kind, title = step.title or step.key, counted = false, isCurrent = false,
                        visible = true, optional = step.optional == true, note = step.note == true, daily = step.daily == true,
                        accept = step.accept == true, level = LockLevel(step), section = step.section }
                    v.kindWord = (v.note and "Note") or (v.daily and "Daily") or KIND_WORD[step.kind] or "Note"
                    v.detail = step.detail or (type(step.detailByPhase) == "table" and step.detailByPhase[n]) or nil
                    if step.kind == "QUEST" then
                        local ids = QuestCandidates(step)
                        v.questId = ids[1]
                        v.inLog = false
                        for _, id in ipairs(ids) do
                            if ctx.onQuest[id] then v.inLog = true end
                        end
                    elseif step.questId then
                        v.questId = tonumber(Pick(step.questId))
                        v.inLog = v.questId and ctx.onQuest[v.questId] or false
                    else
                        v.inLog = false
                    end
                    v.logKey = v.questId and ("id:" .. v.questId) or nil
                    v.markedAt = MarkOf(guide.key, step.key)
                    if w then
                        v.status = w
                        if w == "LATER" then
                            v.word = ShortOf(step.phases.from)
                            v.reason = "Opens in " .. v.word
                        else
                            v.word = "Until " .. ShortOf(step.phases.to)
                            v.reason = "Needed until " .. ShortOf(step.phases.to)
                        end
                        v.phaseWord = v.word
                    else
                        local status, reason, progress = Detected(guide, step)
                        v.status, v.reason, v.progress = status, reason, progress
                        if status == "DONE" then det[v] = true end
                        if status ~= "DONE" then
                            local countable = Countable(step, guide)
                            if held and countable and step.kind ~= "LEVEL" then
                                v.status, v.reason, v.progress = "WAIVED", "Not needed: " .. heldWords, nil
                                unlockWaived[v] = true
                            elseif guideMark and countable then
                                v.status, v.reason, v.progress = "DONE", "Marked for the whole guide", nil
                            elseif v.markedAt and status ~= "NOTE" and status ~= "SET" and status ~= "UNSET" then
                                v.status, v.reason, v.progress = "DONE", "Marked by you on " .. DateWord(v.markedAt), nil
                            end
                        end
                    end
                    if step.side and undecided then sideSplit = true end
                    views[#views + 1] = v
                    byKey[step.key] = v
                    raw[v] = step
                end
            end
        end

        local function DoneLike(v) return v.status == "DONE" or unlockWaived[v] == true end

        -- Alternative groups: the best group counts, the others are waived
        -- once any group is satisfied and "not counted" before that
        if type(guide.alternatives) == "table" then
            for _, alt in pairs(guide.alternatives) do
                local groups = type(alt) == "table" and type(alt.groups) == "table" and alt.groups or EMPTY
                local info, anySatisfied = {}, false
                for gi, grp in ipairs(groups) do
                    local done, allVisible, allDone = 0, true, #grp > 0
                    for _, sk in ipairs(grp) do
                        local v = byKey[sk]
                        if not v or v.status == "LATER" or v.status == "PAST" then
                            allVisible, allDone = false, false
                        elseif DoneLike(v) then
                            done = done + 1
                        else
                            allDone = false
                        end
                    end
                    info[gi] = { done = done, allVisible = allVisible, satisfied = allDone and allVisible }
                    if info[gi].satisfied then anySatisfied = true end
                end
                local best
                if #groups > 0 then
                    local top = -1
                    for gi, inf in ipairs(info) do
                        local score = inf.done + (inf.satisfied and 1000 or 0)
                        if score > top then top = score end
                    end
                    local pref = type(alt.prefer) == "table" and alt.prefer[ctx.class] or nil
                    for gi, inf in ipairs(info) do
                        if inf.done + (inf.satisfied and 1000 or 0) == top then
                            if pref == gi then best = gi; break end
                            if not best and inf.allVisible then best = gi end
                        end
                    end
                    if not best then
                        for gi, inf in ipairs(info) do
                            if inf.done + (inf.satisfied and 1000 or 0) == top then best = gi; break end
                        end
                    end
                end
                -- a step the best group shares with another (Artisan Riding
                -- in both flight280 groups) stays counted
                local inBest = {}
                if best then
                    for _, sk in ipairs(groups[best]) do inBest[sk] = true end
                end
                for gi, grp in ipairs(groups) do
                    if gi ~= best then
                        for _, sk in ipairs(grp) do
                            local v = (not inBest[sk]) and byKey[sk] or nil
                            if v and not DoneLike(v) and v.status ~= "LATER" and v.status ~= "PAST" then
                                if anySatisfied then
                                    if v.status ~= "WAIVED" then
                                        v.status, v.reason, v.progress = "WAIVED", "Not needed: another route to this goal is complete", nil
                                    end
                                else
                                    notCounted[v] = NotCountedPrefix(guide, alt, best)
                                end
                            elseif v then
                                notCounted[v] = notCounted[v] or false
                            end
                        end
                    end
                end
            end
        end

        -- Counting, the current step
        local counted, done, total = {}, 0, 0
        for _, v in ipairs(views) do
            local step = raw[v]
            if v.status ~= "LATER" and v.status ~= "PAST" and Countable(step, guide) and notCounted[v] == nil
                and (v.status ~= "WAIVED" or unlockWaived[v]) then
                v.counted = true
                counted[#counted + 1] = v
                total = total + 1
                if DoneLike(v) then done = done + 1 end
            end
        end
        local current
        for _, v in ipairs(counted) do
            if v.status == "READY" then current = v; break end
        end
        if not current then
            for _, v in ipairs(counted) do
                if not DoneLike(v) then current = v; break end
            end
        end

        -- Final words per step: the lock, the NEXT word, optional and note
        -- lines, the prefix of a non-best route, the how sentence, the places
        for i, v in ipairs(views) do
            local step = raw[v]
            v.index = i
            local st = v.status
            if st ~= "DONE" and st ~= "WAIVED" and st ~= "LATER" and st ~= "PAST" and st ~= "NOTE" and st ~= "SET" and st ~= "UNSET"
                and step.kind ~= "LEVEL" then
                local need = LockLevel(step)
                if need and level < need then
                    v.status, v.reason, v.progress = "LOCKED", format("Level %d of %d", level, need), { have = level, need = need }
                end
            end
            if v == current then
                v.isCurrent = true
                if v.status == "OPEN" or v.status == "UNKNOWN" then v.status = "NEXT" end
            end
            if notCounted[v] and not DoneLike(v) then
                v.reason = notCounted[v] .. ((v.reason and v.reason ~= "") and ("; " .. v.reason) or "")
            end
            if v.optional and not v.daily and not DoneLike(v) and v.status ~= "NOTE" and v.status ~= "SET" and v.status ~= "UNSET"
                and v.status ~= "LATER" and v.status ~= "PAST" and v.status ~= "WAIVED" then
                v.status = "OPTIONAL"
            end
            -- an out-of-window note keeps its phase word (LATER/PAST)
            if v.note and v.status ~= "DONE" and v.status ~= "LATER" and v.status ~= "PAST" then v.status = "NOTE" end
            st = v.status
            if st == "PARTIAL" then
                v.word = v.progress and (tostring(v.progress.have) .. "/" .. tostring(v.progress.need)) or "Partial"
            elseif st == "STANDING" then
                local fid = tonumber(Pick(step.factionId))
                local entry = fid and ctx.rep[fid] or nil
                v.word = entry and StandingWord(entry.standingID - 1, Labels()) or "Below"
            elseif st ~= "LATER" and st ~= "PAST" then
                v.word = WORD[st] or st
            end
            v.tone = TONE[st] or "secondary"
            v.how = HowOf(step, guide, v.markedAt)
            v.places = PlacesOf(guide, step, v.questId)
        end

        -- The guide
        local introduced = tonumber(type(guide.phase) == "table" and guide.phase.introduced) or 1
        local released = introduced <= n
        local needed = released and (guide.gate == nil or (type(rules.attunementRequired) == "table"
            and rules.attunementRequired[guide.gate] ~= false))
        local levelStep
        for _, v in ipairs(counted) do
            if raw[v].kind == "LEVEL" then levelStep = v; break end
        end
        local levelOk = (not levelStep) or levelStep.status == "DONE"
        local allDone = total > 0 and done >= total
        local account = guide.accountWide and ctx.account[guide.key] or nil
        if type(account) ~= "table" then account = nil end
        local byDetection = held and levelOk
        if not byDetection and allDone then
            byDetection = true
            for _, v in ipairs(counted) do
                if not (det[v] or unlockWaived[v]) then byDetection = false end
            end
        end
        local status
        if guide.recurring then status = "RECURRING"
        elseif (held and levelOk) or allDone or account then status = "DONE"
        elseif not released then status = "LATER"
        elseif not needed then status = "NOTNEEDED"
        else status = "PROGRESS" end

        local pct = done / max(total, 1)
        local word, tone, strip
        if status == "DONE" then word, tone, strip = "Done", "good", "good"
        elseif status == "PROGRESS" then word, tone, strip = done .. "/" .. total, "secondary", (done > 0) and "open" or "faint"
        elseif status == "NOTNEEDED" then word, tone, strip = "Not needed", "faint", "faint"
        elseif status == "LATER" then word, tone, strip = ShortOf(introduced), "warn", "warn"
        else
            local b = ctx.badges or 0
            word, tone, strip = b .. (b == 1 and " badge" or " badges"), "open", "open"
        end
        local bucket = (status == "DONE") and "DONE" or ((status == "NOTNEEDED" or status == "LATER") and "OTHER") or "NEEDED"
        local minLevel = tonumber(guide.minLevel) or 0

        -- Notices: the tooltip form and the page form, by priority
        local short, long
        if status == "LATER" then
            local row = PhaseRow(introduced)
            local since = row and type(row.since) == "number" and DateWord(row.since, true, true) or nil
            short = since and format("Opens in %s on %s.", ShortOf(introduced), since)
                or format("Opens in %s, no date announced.", ShortOf(introduced))
            long = since and format("Opens in %s (%s) on %s.", ShortOf(introduced), row and row.name or "", since)
                or format("Opens in %s (%s), no date announced. Read ahead; nothing here can be started yet.",
                    ShortOf(introduced), row and row.name or "")
        elseif status == "NOTNEEDED" then
            local p = GateDropped(guide, n) or n
            local row = PhaseRow(p)
            local when = row and type(row.since) == "number" and (" (" .. DateWord(row.since, true, true) .. ")") or ""
            local note = type(guide.phase) == "table" and guide.phase.note or nil
            -- The phase note already opens with the clause on every gated
            -- guide, so it is the whole notice; else the clause leads it
            -- (4.10 and 5.3 word the sentence once)
            if type(note) == "string" and note:find("^Not needed since") then
                short = note
            else
                short = format("Not needed since %s%s%s", ShortOf(p), when,
                    (type(note) == "string" and note ~= "") and (": " .. note) or ".")
            end
            long = short
        elseif held then
            local subject
            if heldKind == "quest" then
                subject = "You have completed " .. heldName
            else
                local itemName = ProofItemName(guide) or heldName
                local article = itemName:lower():find("^the ") and "" or "the "
                subject = "You hold " .. article .. itemName
            end
            local place = OpenWords(guide)
            if levelOk then
                short = format("%s: %s is open to you.", subject, place)
            else
                short = format("%s; %s opens at level %d.", subject, place,
                    (levelStep and levelStep.progress and levelStep.progress.need) or minLevel)
            end
            long = short
        elseif account then
            short = format("Done by %s, %s", tostring(account.char), DateWord(account.at))
            long = format("Done by %s on %s (account ledger).", tostring(account.char), DateWord(account.at))
        elseif guide.accountWide and status ~= "DONE" then
            short = "Account-wide on Anniversary: if another character finished this, the raid is open to you too, but this client cannot see that. Shift-click Mark Done to tick the whole guide."
            long = short
        elseif sideSplit then
            short = "Pick a side in the Aldor or Scryers guide to settle the side-specific steps here."
            long = short
        elseif level < minLevel then
            short = format("Your level is %d; this guide begins at %d.", level, minLevel)
            long = short
        end

        local item = {
            kind = "guide", key = guide.key, name = guide.name or guide.key, title = guide.title or guide.name or guide.key,
            category = guide.category, status = status, word = word, tone = tone, strip = strip, done = done, total = total,
            pct = pct, current = current and current.key or nil, currentTitle = current and current.title or nil,
            currentLocked = (current and current.status == "LOCKED") and true or false, minLevel = minLevel,
            underLevel = level < minLevel, bucket = bucket, notice = short,
            account = account and { char = account.char, at = account.at } or nil,
        }
        local summary = {
            done = done, total = total, pct = pct, current = current and current.key or nil, status = status, word = word,
            tone = tone, notice = long, unlockHeld = held and true or false, hiddenOtherPhases = hiddenOther,
            doneHidden = 0,
        }
        for _, v in ipairs(views) do
            if v.status == "DONE" then summary.doneHidden = summary.doneHidden + 1 end
        end

        local ev = { guide = guide, views = views, summary = summary, item = item, current = current, byDetection = byDetection }
        E.guideCache[cacheKey] = { gen = A.generation, index = E.index, ev = ev }
        return ev
    end
end

-- The account ledger: written by detection only (4.6). -> true when a row
-- was written
local function WriteLedger(ev)
    local guide = ev.guide
    if not (guide.accountWide and ev.item.status == "DONE" and ev.byDetection) then return false end
    local acc = AccountTable("AttuneAccount")
    if not acc or type(acc[guide.key]) == "table" then return false end
    local name = "?"
    if UnitName then
        local ok, v = pcall(UnitName, "player")
        if ok and type(v) == "string" and v ~= "" then name = v end
    end
    local realm = "?"
    if GetRealmName then
        local ok, v = pcall(GetRealmName)
        if ok and type(v) == "string" and v ~= "" then realm = v end
    end
    acc[guide.key] = { char = name .. "-" .. realm, at = Now() }
    return true
end

-- One guide evaluated, the ledger written if it earned a row (the store
-- generation moves quietly so the next pass reads the row back)
local function Eval(guide, otherPhases)
    local ev = Evaluate(guide, otherPhases)
    if WriteLedger(ev) then Bump("store") end
    return ev
end

-- The guide record behind a key, or nil for the other faction's guide
local function Visible(key)
    local g = key and Index().byKey[key] or nil
    if type(g) ~= "table" then return nil end
    if g.faction and g.faction ~= "BOTH" and g.faction ~= ctx.faction then return nil end
    return g
end

-- Every guide for this faction, evaluated in data order (cached per
-- generation); the ledger rows earned this pass written once at the end
local function AllGuides()
    local cached = E.allCache
    if cached and cached.gen == A.generation and cached.index == E.index then return cached.list end
    local list = {}
    local faction = ctx.faction
    for _, g in ipairs(Index().order) do
        if not (g.faction and g.faction ~= "BOTH" and g.faction ~= faction) then
            list[#list + 1] = Evaluate(g, false)
        end
    end
    local wrote = false
    for _, ev in ipairs(list) do
        if WriteLedger(ev) then wrote = true end
    end
    if wrote then Bump("store") end
    E.allCache = { gen = A.generation, index = E.index, list = list }
    return list
end

local function RaidInfo()
    if not RequestRaidInfo then return end
    local t = Clock()
    if t - E.lastRaidInfo < RAID_INFO_THROTTLE then return end
    E.lastRaidInfo = t
    pcall(RequestRaidInfo)
end

-- The throttled sender, for the tab when it becomes active (4.2)
A.RequestRaidInfo = RaidInfo

-- ---------------------------------------------------------------------------
-- The catalogue: guides and steps as the tab lists them, the current step,
-- continue, find (4.10)
-- ---------------------------------------------------------------------------

do
    local BUCKET_RANK = { NEEDED = 1, DONE = 2, OTHER = 3 }
    local OTHER_RANK = { NOTNEEDED = 1, LATER = 2 }

    local function Categories()
        local D = Data()
        if D and type(D.CATEGORIES) == "table" then return D.CATEGORIES end
        return EMPTY
    end

    local function CategoryRank()
        local rank = {}
        for i, c in ipairs(Categories()) do
            if type(c) == "table" and c.key then rank[c.key] = i end
        end
        return rank
    end

    -- Catalogue order: module, then `order`, then data position
    local function ByCatalogue(rank)
        return function(a, b)
            local ga, gb = a.guide, b.guide
            local ca, cb = rank[ga.category] or 99, rank[gb.category] or 99
            if ca ~= cb then return ca < cb end
            local oa, ob = tonumber(ga.order) or 0, tonumber(gb.order) or 0
            if oa ~= ob then return oa < ob end
            return a.pos < b.pos
        end
    end

    -- The raw records for this faction in catalogue order (no evaluation;
    -- per index)
    local function Records()
        local idx = Index()
        local cached = E.recordsCache
        if cached and cached.index == idx and cached.faction == ctx.faction then return cached.list end
        local rows = {}
        for i, g in ipairs(idx.order) do
            if not (g.faction and g.faction ~= "BOTH" and g.faction ~= ctx.faction) then
                rows[#rows + 1] = { guide = g, pos = i }
            end
        end
        tsort(rows, ByCatalogue(CategoryRank()))
        local list = {}
        for i, r in ipairs(rows) do list[i] = r.guide end
        E.recordsCache = { index = idx, faction = ctx.faction, list = list }
        return list
    end

    -- Every visible guide evaluated, in catalogue order (per generation)
    local function Ordered()
        local evs = AllGuides()
        local cached = E.orderedCache
        if cached and cached.gen == A.generation and cached.index == E.index then return cached.list end
        local rows = {}
        for i, ev in ipairs(evs) do rows[#rows + 1] = { ev = ev, guide = ev.guide, pos = i } end
        tsort(rows, ByCatalogue(CategoryRank()))
        E.orderedCache = { gen = A.generation, index = E.index, list = rows }
        return rows
    end

    -- The navigator's order: module, then NEEDED, DONE, OTHER (Not needed
    -- before Later), each in `order`
    local function Sorted()
        local rows = Ordered()
        local cached = E.sortedCache
        if cached and cached.gen == A.generation and cached.index == E.index then return cached.list end
        local list = {}
        for i, r in ipairs(rows) do list[i] = r end
        local rank = CategoryRank()
        tsort(list, function(a, b)
            local ca, cb = rank[a.guide.category] or 99, rank[b.guide.category] or 99
            if ca ~= cb then return ca < cb end
            local ia, ib = a.ev.item, b.ev.item
            local ba, bb = BUCKET_RANK[ia.bucket] or 9, BUCKET_RANK[ib.bucket] or 9
            if ba ~= bb then return ba < bb end
            if ba == 3 then
                local xa, xb = OTHER_RANK[ia.status] or 9, OTHER_RANK[ib.status] or 9
                if xa ~= xb then return xa < xb end
            end
            local oa, ob = tonumber(a.guide.order) or 0, tonumber(b.guide.order) or 0
            if oa ~= ob then return oa < ob end
            return a.pos < b.pos
        end)
        E.sortedCache = { gen = A.generation, index = E.index, list = list }
        return list
    end

    local function Passes(item, filter)
        if filter == "TODO" then return item.bucket == "NEEDED" end
        if filter == "DONE" then return item.bucket == "DONE" end
        if filter == "OTHER" then return item.bucket == "OTHER" end
        return true
    end

    local function Has(s, needle)
        return type(s) == "string" and s:lower():find(needle, 1, true) ~= nil
    end

    -- Search: the guide's name and title, and any step title
    local function Matches(guide, needle)
        if needle == "" then return true end
        if Has(guide.name, needle) or Has(guide.title, needle) then return true end
        for _, s in ipairs(type(guide.steps) == "table" and guide.steps or EMPTY) do
            if type(s) == "table" and Has(s.title, needle) then return true end
        end
        return false
    end

    function A.Guides(view)
        if type(view) ~= "table" then view = EMPTY end
        local filter = view.filter or "ALL"
        local needle = type(view.search) == "string" and view.search:lower() or ""
        needle = (needle:gsub("^%s+", ""):gsub("%s+$", ""))
        local collapsed = type(view.collapsed) == "table" and view.collapsed or EMPTY
        local sorted = Sorted()

        -- Totals over every visible guide, whatever the filter; the recurring
        -- guide is never a count
        local totals = { guides = 0, done = 0, todo = 0, notNeeded = 0, later = 0, pct = 0, needed = 0 }
        for _, r in ipairs(sorted) do
            local it = r.ev.item
            if it.status ~= "RECURRING" then
                totals.guides = totals.guides + 1
                if it.status == "DONE" then totals.done = totals.done + 1
                elseif it.status == "NOTNEEDED" then totals.notNeeded = totals.notNeeded + 1
                elseif it.status == "LATER" then totals.later = totals.later + 1
                else totals.todo = totals.todo + 1 end
            end
        end
        totals.needed = totals.done + totals.todo
        totals.pct = totals.done / max(totals.needed, 1)

        local items = {}
        for _, cat in ipairs(Categories()) do
            if type(cat) == "table" and cat.key then
                local header = { kind = "header", category = cat.key, label = cat.label or tostring(cat.key), done = 0, total = 0,
                    collapsed = collapsed[cat.key] and true or false, shown = 0 }
                local rows = {}
                for _, r in ipairs(sorted) do
                    local it = r.ev.item
                    if it.category == cat.key then
                        if it.status ~= "RECURRING" then
                            if it.bucket == "DONE" then
                                header.done, header.total = header.done + 1, header.total + 1
                            elseif it.bucket == "NEEDED" then
                                header.total = header.total + 1
                            end
                        end
                        if Passes(it, filter) and Matches(r.guide, needle) then rows[#rows + 1] = it end
                    end
                end
                header.shown = #rows
                if #rows > 0 then
                    items[#items + 1] = header
                    if not header.collapsed then
                        for _, it in ipairs(rows) do items[#items + 1] = it end
                    end
                end
            end
        end
        return items, totals
    end

    function A.Guide(key)
        local g = Visible(key)
        if not g then return nil end
        return Eval(g, false).item
    end

    function A.Steps(guideKey, opts)
        local g = Visible(guideKey)
        if not g then return {}, nil end
        local ev = Eval(g, type(opts) == "table" and opts.otherPhases == true)
        return ev.views, ev.summary
    end

    function A.Current(guideKey)
        local g = Visible(guideKey)
        if not g then return nil end
        local cur = Eval(g, false).current
        return cur and cur.key or nil
    end

    function A.CurrentStep(guideKey)
        local g = Visible(guideKey)
        if not g then return nil end
        return Eval(g, false).current
    end

    -- Rule (4): the level reached, every hard prerequisite done, a current
    -- step that is not level-locked
    local function Startable(ev, byKey, level)
        local g = ev.guide
        if level < (tonumber(g.minLevel) or 0) then return false end
        if not ev.current or ev.current.status == "LOCKED" then return false end
        for _, pre in ipairs(type(g.prerequisites) == "table" and g.prerequisites or EMPTY) do
            if type(pre) == "table" and pre.hard ~= false and pre.guide then
                local other = byKey[pre.guide]
                if other and other.item.status ~= "DONE" then return false end
            end
        end
        return true
    end

    function A.Continue()
        local rows = Ordered()
        if #rows == 0 then return nil, nil, "none" end
        local byKey = {}
        for _, r in ipairs(rows) do byKey[r.guide.key] = r.ev end
        local at = Char()
        -- not OTHER and not DONE (a ledger or held Done keeps its current step
        -- for the page, but is never the one to continue)
        local function Live(ev)
            return ev ~= nil and ev.item.bucket ~= "OTHER" and ev.item.status ~= "DONE" and ev.current ~= nil
        end
        -- (1) the guide opened last
        local opened = at.guide and byKey[at.guide] or nil
        if Live(opened) then return at.guide, opened.current.key, "opened" end
        -- (2) the latest touch
        local bestKey, bestAt
        for key, t in pairs(at.touched) do
            t = tonumber(t)
            if t and Live(byKey[key]) and (not bestAt or t > bestAt) then bestKey, bestAt = key, t end
        end
        if bestKey then return bestKey, byKey[bestKey].current.key, "progressed" end
        -- (3) the first needed guide with progress
        for _, r in ipairs(rows) do
            local it = r.ev.item
            if it.bucket == "NEEDED" and it.status ~= "RECURRING" and (it.done or 0) > 0 and r.ev.current then
                return r.guide.key, r.ev.current.key, "started"
            end
        end
        -- (4) the first needed guide this character can begin
        local level = ctx.level
        for _, r in ipairs(rows) do
            local it = r.ev.item
            if it.bucket == "NEEDED" and it.status ~= "RECURRING" and Startable(r.ev, byKey, level) then
                return r.guide.key, r.ev.current.key, "first"
            end
        end
        -- (5) nothing: everything needed is done, or nothing can be begun
        for _, r in ipairs(rows) do
            local it = r.ev.item
            if it.bucket == "NEEDED" and it.status ~= "RECURRING" then return nil, nil, "none" end
        end
        return nil, nil, "done"
    end

    local function Norm(s)
        if type(s) ~= "string" then return "" end
        return (s:lower():gsub("_", " "))
    end

    -- Lowercase; exact name, then a prefix of the name, then a substring of
    -- name, title or key (underscores as spaces); ties to catalogue order
    function A.Find(text)
        if type(text) ~= "string" then return nil end
        local q = (Norm(text):gsub("^%s+", ""):gsub("%s+$", ""))
        if q == "" then return nil end
        local records = Records()
        for _, g in ipairs(records) do
            if Norm(g.name) == q then return g.key, g.name end
        end
        for _, g in ipairs(records) do
            if Norm(g.name):find(q, 1, true) == 1 then return g.key, g.name end
        end
        for _, g in ipairs(records) do
            if Norm(g.name):find(q, 1, true) or Norm(g.title):find(q, 1, true) or Norm(g.key):find(q, 1, true) then
                return g.key, g.name
            end
        end
        return nil
    end
end

-- ---------------------------------------------------------------------------
-- Go: the default place, the target, the press (4.9)
-- ---------------------------------------------------------------------------

do
    local DEFAULT_ROLES = { ITEM = { "vendor", "inside" }, SKILL = { "trainer" }, SPELL = { "trainer" },
        KILL = { "inside", "door" }, MANUAL = { "inside", "door" }, TALK = { "vendor" } }
    local QUEST_OPEN, QUEST_LOG = { "start", "turnin" }, { "turnin", "start" }

    -- The target behind one of the step view's places, made fresh on every
    -- call so the door rule reads Orders' presence now
    local function Resolve(place)
        local d = E.placeData[place]
        if not d then return nil, "Nowhere to go", nil end
        local t, why = TargetFor(d.guide, d.step, d.questId, d.row, d.i, d.name)
        return t, why, d.i
    end

    function A.PlaceFor(view, i)
        if type(view) ~= "table" then return nil, "Nothing to go to", nil end
        local places = type(view.places) == "table" and view.places or EMPTY
        if i ~= nil then
            local place = places[tonumber(i)]
            if not place then return nil, "Nowhere to go", nil end
            return Resolve(place)
        end
        if view.kind == "LEVEL" or view.kind == "REP" then return nil, "Nothing to go to", nil end
        if #places == 0 then return nil, "Nowhere to go", nil end
        local roles
        if view.kind == "QUEST" then
            local inLog = view.inLog or view.status == "LOG" or view.status == "READY" or view.status == "FAILED"
            roles = inLog and QUEST_LOG or QUEST_OPEN
        else
            roles = DEFAULT_ROLES[view.kind] or EMPTY
        end
        for _, role in ipairs(roles) do
            for _, place in ipairs(places) do
                if place.role == role then
                    local t, why, idx = Resolve(place)
                    if t then return t, why, idx end
                end
            end
        end
        -- no place of the preferred role: the first one with somewhere to go
        local firstWhy
        for _, place in ipairs(places) do
            local t, why, idx = Resolve(place)
            if t then return t, why, idx end
            firstWhy = firstWhy or why
        end
        return nil, firstWhy or "Nowhere to go", nil
    end

    local function WayLine(coords, title)
        return format("/way #%d %.2f %.2f %s", coords.map, (coords.x or 0) * 100, (coords.y or 0) * 100, title or "")
    end

    -- -> "ORDERS"|"PRINT"|nil
    function A.Go(target)
        if type(target) ~= "table" then return nil end
        local key = target.key
        local coords = target.spec or target.fallback
        if type(coords) ~= "table" or not coords.map then coords = nil end
        -- quest keys share the Log's path (works without Questie when the spec carries a map)
        if type(key) == "string" and key:find("^quest:") and coords and Q.Questie and type(Q.Questie.GoOrPrint) == "function" then
            local ok, result = pcall(Q.Questie.GoOrPrint, target.spec or coords, key, target.questId, target.note)
            if ok then return result end
        end
        local O = OrdersGo()
        if O then
            local ok, uid = pcall(O.GoTo, target.query or target.spec, { source = "QuestLog", key = key, title = target.title, icon = "QUEST" })
            if ok and uid then
                -- a landing Go drops the quest's other keys (D45), as the Log's own
                -- Go does; this waypoint carries no note, so none is remembered
                if type(key) == "string" and key:find("^quest:") and Q.Questie and type(Q.Questie.NoteGo) == "function" then
                    pcall(Q.Questie.NoteGo, target.questId, key, nil)
                end
                return "ORDERS"
            end
            return nil
        end
        if coords then
            print(WayLine(coords, target.title))
            return "PRINT"
        end
        local inst = type(target.query) == "table" and type(target.query.entrance) == "table" and target.query.entrance.instance
        print("Commander Quest Log: " .. tostring(target.title or "This place") .. " is inside "
            .. (inst and InstanceName(inst) or "an instance") .. "; Commander Orders is needed to point at its door.")
        return nil
    end
end

-- ---------------------------------------------------------------------------
-- The log index and the status lines (4.1, 6.5)
-- ---------------------------------------------------------------------------

do
    -- Q.Scan's entries by "id:<questID>": the fallback for objectives, ready
    -- and failed. The quests generation moves quietly when the picture
    -- changed (this is called inside the window's own pass).
    function A.SetLogEntries(entries)
        local index, sig = {}, {}
        for _, e in ipairs(type(entries) == "table" and entries or EMPTY) do
            if type(e) == "table" and not e.isHeader then
                local id = tonumber(e.questID)
                if id and id > 0 then
                    index["id:" .. id] = e
                    local parts = { tostring(id), e.isComplete and "r" or "", e.isFailed and "f" or "" }
                    for _, o in ipairs(type(e.objectives) == "table" and e.objectives or EMPTY) do
                        if type(o) == "table" then
                            parts[#parts + 1] = (o.finished and "x" or "") .. tostring(o.have or "") .. "/" .. tostring(o.need or "")
                        end
                    end
                    sig[#sig + 1] = tconcat(parts, ":")
                end
            end
        end
        tsort(sig)
        local signature = tconcat(sig, ",")
        E.logIndex = index
        if signature ~= E.logSignature then
            E.logSignature = signature
            Bump("quests")
        end
    end

    local SOURCE_WORDS = { calendar = "from the calendar", questie = "from Questie", evidence = "from what this account has seen in game",
        setting = "set by you" }
    local CONTINUE_WHY = { opened = "you opened it last", progressed = "you made progress here most recently",
        started = "the first guide you have started", first = "the first guide you can start" }

    local function Plural(n, one, many)
        return tostring(n) .. " " .. (n == 1 and one or many)
    end

    function A.StatusLines()
        local out = {}
        local ok, err = pcall(function()
            local n, source, since, _, votes = A.Phase()
            local short, name = A.PhaseName(n)
            votes = type(votes) == "table" and votes or EMPTY
            out[#out + 1] = format("Attunements: %s, %s, %s; %s. Votes: calendar %s, Questie %s, evidence %s, setting %s.",
                short, (name ~= "" and name) or "unnamed", since and ("since " .. DateWord(since, true, true)) or "no date announced",
                SOURCE_WORDS[source] or tostring(source), tostring(votes.calendar or "none"),
                votes.questie and tostring(votes.questie) or "none", votes.evidence and tostring(votes.evidence) or "none",
                (votes.setting == nil or votes.setting == "AUTO") and "automatic" or tostring(votes.setting))

            local _, totals = A.Guides(EMPTY)
            local badges = ctx.badges or 0
            out[#out + 1] = format("Attunements: %d of %d guides done, %d to do, %d not needed this phase, %d open later; %s.",
                totals.done, totals.needed, totals.todo, totals.notNeeded, totals.later,
                Plural(badges, "Badge of Justice", "Badges of Justice"))

            local gk, sk, reason = A.Continue()
            if gk then
                local g = Index().byKey[gk]
                local step = StepOf(g, sk)
                out[#out + 1] = format("Attunements: continue %s, %s (%s).", (g and g.name) or tostring(gk),
                    (step and step.title) or tostring(sk), CONTINUE_WHY[reason] or tostring(reason))
            elseif reason == "done" then
                out[#out + 1] = "Attunements: everything needed this phase is done."
            else
                out[#out + 1] = "Attunements: nothing to continue yet; pick a guide to begin."
            end

            local steps, guides = 0, 0
            for k in pairs(Char().marks) do
                if tostring(k):find(":", 1, true) then steps = steps + 1 else guides = guides + 1 end
            end
            local ledger = {}
            for key, row in pairs(ctx.account) do
                if type(row) == "table" then
                    local g = Index().byKey[key]
                    ledger[#ledger + 1] = ((g and g.name) or tostring(key)) .. " done by " .. tostring(row.char)
                end
            end
            tsort(ledger)
            out[#out + 1] = format("Attunements: %s and %s marked by hand on this character; account ledger: %s.",
                Plural(steps, "step", "steps"), Plural(guides, "guide", "guides"),
                #ledger > 0 and tconcat(ledger, ", ") or "empty")

            local state
            if Q.Questie and type(Q.Questie.State) == "function" then
                local ok2, s = pcall(Q.Questie.State)
                if ok2 then state = s end
            end
            local questie
            if votes.questie then questie = format("Questie ready (phase vote %d)", votes.questie)
            elseif state == "READY" then questie = "Questie ready (phase vote missing)"
            elseif state == "LOADING" then questie = "Questie loading (phase vote missing)"
            elseif state == "BROKEN" then questie = "Questie broken (phase vote missing)"
            else questie = "Questie not loaded (phase vote missing)" end
            local orders = "Commander Orders not loaded"
            local O = OrdersGo()
            if O then
                orders = "Commander Orders ready"
                if type(O.IsAvailable) == "function" then
                    local ok3, available = pcall(O.IsAvailable)
                    if ok3 and available == false then orders = "Commander Orders off" end
                end
            end
            out[#out + 1] = format("Attunements: %s; %s.", questie, orders)
        end)
        if not ok then out[#out + 1] = "Attunements: the status could not be read: " .. tostring(err) end
        return out
    end
end

-- ---------------------------------------------------------------------------
-- The event frame: one domain per event, the collectors, CLEU arming, the
-- login duties and the calendar tick (4.7)
-- ---------------------------------------------------------------------------

do
    local DOMAIN = { QUEST_TURNED_IN = "quests", QUEST_ACCEPTED = "quests", QUEST_REMOVED = "quests", QUEST_LOG_UPDATE = "quests",
        BAG_UPDATE_DELAYED = "items", UPDATE_FACTION = "reps", PLAYER_LEVEL_UP = "char", SPELLS_CHANGED = "spells",
        LEARNED_SPELL_IN_SKILL_LINE = "spells", SKILL_LINES_CHANGED = "skills", UPDATE_INSTANCE_INFO = "locks",
        PLAYER_ENTERING_WORLD = "world", ZONE_CHANGED_NEW_AREA = "world", PLAYER_DIFFICULTY_CHANGED = "world",
        GOSSIP_SHOW = "store", MERCHANT_SHOW = "store", ENCOUNTER_END = "store", BOSS_KILL = "store", PLAYER_LOGIN = "phase" }
    local COLLECT = {}
    local CREATURE = "Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)"

    local function After(delay, fn)
        if C_Timer and C_Timer.After then pcall(C_Timer.After, delay, fn) end
    end

    local function Recheck() A.Invalidate("quests") end

    -- The calendar term re-read every minute, so a phase boundary flips
    -- without a reload (self-rescheduling After, never NewTicker)
    local function Tick()
        A.Invalidate("phase")
        After(60, Tick)
    end

    -- Restore Defaults rewrites AttunePhase without A.SetPhase and notifies
    -- UPDATE; the memoised phase and store slices must hear it first
    local function OnSettingsUpdate()
        A.Invalidate("phase")
        A.Invalidate("store")
    end

    local function OnQuestie() A.Invalidate("phase") end

    local function EvidenceQuests()
        local D = Data()
        local t = D and type(D.EVIDENCE) == "table" and D.EVIDENCE.quests
        if type(t) == "table" then return t end
        return EMPTY
    end

    local function EvidenceLockouts()
        local D = Data()
        local t = D and type(D.EVIDENCE) == "table" and D.EVIDENCE.lockouts
        if type(t) == "table" then return t end
        return EMPTY
    end

    -- -> instance map id, instance type, difficulty id | nil
    local function CurrentInstance()
        if not GetInstanceInfo then return nil end
        local ok, _, kind, difficulty, _, _, _, _, id = pcall(GetInstanceInfo)
        if not ok or not tonumber(id) then return nil end
        return tonumber(id), kind, tonumber(difficulty)
    end

    -- D45's cleanup for a quest id: the shared quest key and the attune key
    -- of every place of every step carrying it
    local function RemoveKeys(id)
        local O = CommanderOrders
        if not (type(O) == "table" and type(O.RemoveBy) == "function") then return end
        local list = Index().questSteps[id]
        if not list then return end
        pcall(O.RemoveBy, "QuestLog", "quest:" .. id)
        for _, e in ipairs(list) do
            for i in ipairs(type(e.step.places) == "table" and e.step.places or EMPTY) do
                pcall(O.RemoveBy, "QuestLog", format("attune:%s:%s:%d", tostring(e.guide.key), tostring(e.step.key), i))
            end
        end
    end

    COLLECT.QUEST_TURNED_IN = function(id)
        id = tonumber(id)
        if not id then return end
        Char().seen[id] = Now()
        After(1, Recheck)
        After(GRACE + 1, Recheck)
        RemoveKeys(id)
        local n = EvidenceQuests()[id]
        if n then WriteEvidence(n, "quest", "quest " .. id .. " flagged") end
    end

    COLLECT.QUEST_REMOVED = function(id)
        id = tonumber(id)
        if id then RemoveKeys(id) end
    end

    -- QUEST_ACCEPTED(questIndex, questID): the id is the second argument on this client
    COLLECT.QUEST_ACCEPTED = function(_, id)
        id = tonumber(id)
        local n = id and EvidenceQuests()[id]
        if n then WriteEvidence(n, "quest", "quest " .. id .. " in your log") end
    end

    COLLECT.UPDATE_INSTANCE_INFO = function()
        local map = EvidenceLockouts()
        if not (GetNumSavedInstances and GetSavedInstanceInfo) then return end
        local ok, n = pcall(GetNumSavedInstances)
        if not (ok and tonumber(n)) then return end
        for i = 1, n do
            local r = { pcall(GetSavedInstanceInfo, i) }
            local mapID = r[1] and tonumber(r[15])   -- the 14th return, after pcall's own
            if mapID and map[mapID] then WriteEvidence(map[mapID], "lockout", InstanceName(mapID) .. " lockout") end
        end
        -- a recent kill stamped before its saved row arrived takes that row's end
        local fresh, now = BUILD.locks(), Now()
        for _, k in pairs(Char().kills) do
            if type(k) == "table" and k["until"] == nil and k.map and tonumber(k.when) and now - tonumber(k.when) <= 3600 then
                local L = fresh[k.map]
                local reset = type(L) == "table" and L.locked ~= false and tonumber(L.reset) or nil
                if reset and reset > 0 then k["until"] = now + reset end
            end
        end
    end

    -- Inside a dungeon or raid: remembered for the MANUAL auto ticks, and as
    -- phase evidence when the instance is one the calendar cannot see
    local function Entered()
        local id, kind, difficulty = CurrentInstance()
        if not id or not (kind == "party" or kind == "raid") then return end
        Char().entered[id] = { when = Now(), difficulty = difficulty }
        local n = EvidenceLockouts()[id]
        if n then WriteEvidence(n, "instance", "inside " .. InstanceName(id)) end
    end

    COLLECT.PLAYER_ENTERING_WORLD = function()
        RaidInfo()
        Entered()
    end
    COLLECT.ZONE_CHANGED_NEW_AREA = Entered

    local function Talked()
        if not UnitGUID then return end
        local ok, guid = pcall(UnitGUID, "npc")
        local id = ok and type(guid) == "string" and tonumber(guid:match(CREATURE)) or nil
        if id then Char().talked[id] = Now() end
    end
    COLLECT.GOSSIP_SHOW, COLLECT.MERCHANT_SHOW = Talked, Talked

    -- A kill row: when, where, and the end of the lockout it belongs to when
    -- the saved row is known (filled in later by UPDATE_INSTANCE_INFO if not)
    local function KillRow(map)
        local row = { when = Now(), map = map, difficulty = ctx.instanceDifficulty }
        local L = map and ctx.locks[map] or nil
        local reset = type(L) == "table" and L.locked ~= false and tonumber(L.reset) or nil
        if reset and reset > 0 then row["until"] = row.when + reset end
        return row
    end

    local function KillByEncounter(enc)
        enc = tonumber(enc)
        local list = enc and Index().encounterNpcs[enc] or nil
        if not list then return end
        local kills, map = Char().kills, ctx.instanceId
        kills["enc" .. tostring(enc)] = KillRow(map)
        for _, npc in ipairs(list) do kills[npc] = KillRow(map) end
        RaidInfo()   -- the saved row catches up with the kill (throttled)
    end
    COLLECT.ENCOUNTER_END = function(a1, _, _, _, a5)
        if tonumber(a5) == 1 then KillByEncounter(a1) end
    end
    COLLECT.BOSS_KILL = function(a1) KillByEncounter(a1) end

    COLLECT.PLAYER_LOGIN = function()
        local at, now = Char(), Now()
        for id, t in pairs(at.seen) do
            if not tonumber(t) or now - tonumber(t) > DAY then at.seen[id] = nil end
        end
        for k, m in pairs(at.marks) do
            if type(m) == "table" then
                local till = tonumber(m["until"])
                if till and now >= till then at.marks[k] = nil end
            end
        end
        for k, row in pairs(at.kills) do
            local till = type(row) == "table" and tonumber(row["until"]) or nil
            if till and now >= till then at.kills[k] = nil end
        end
        RaidInfo()
        for id, n in pairs(EvidenceQuests()) do
            if ctx.completed[id] then WriteEvidence(n, "quest", "quest " .. id .. " flagged")
            elseif ctx.onQuest[id] then WriteEvidence(n, "quest", "quest " .. id .. " in your log") end
        end
        if not E.questieHooked and Q.Questie and type(Q.Questie.AddListener) == "function" then
            E.questieHooked = true
            pcall(Q.Questie.AddListener, OnQuestie)
        end
        if not E.updateHooked and type(Commander) == "table" and type(Commander.AddListener) == "function"
            and type(COMMANDER_QUESTLOG_EVENTS) == "table" and COMMANDER_QUESTLOG_EVENTS.UPDATE then
            E.updateHooked = true
            pcall(Commander.AddListener, COMMANDER_QUESTLOG_EVENTS.UPDATE, OnSettingsUpdate)
        end
        if not E.tickStarted then
            E.tickStarted = true
            After(60, Tick)
        end
    end

    -- A creature of a KILL step dying while this frame listens
    local function OnCleu()
        if not CombatLogGetCurrentEventInfo then return end
        local ok, _, sub, _, _, _, _, _, destGUID = pcall(CombatLogGetCurrentEventInfo)
        if not ok or sub ~= "UNIT_DIED" then return end
        local id = type(destGUID) == "string" and tonumber(destGUID:match(CREATURE)) or nil
        if not (id and Index().killSet[id]) then return end
        Char().kills[id] = KillRow(ctx.instanceId)
        RaidInfo()   -- the saved row catches up with the kill (throttled)
        A.Invalidate("store")
    end

    -- COMBAT_LOG_EVENT_UNFILTERED on a second frame, only inside a KILL map
    function A.ArmCleu()
        local D = Data()
        local maps = D and type(D.KILL_MAPS) == "table" and D.KILL_MAPS or EMPTY
        local id = ctx.instanceId
        local want = id ~= nil and maps[id] and true or false
        if want and not E.cleuArmed then
            if not E.cleuFrame and CreateFrame then
                local ok, f = pcall(CreateFrame, "Frame")
                if ok and f then
                    E.cleuFrame = f
                    pcall(f.SetScript, f, "OnEvent", OnCleu)
                end
            end
            if E.cleuFrame then
                local ok = pcall(E.cleuFrame.RegisterEvent, E.cleuFrame, "COMBAT_LOG_EVENT_UNFILTERED")
                E.cleuArmed = ok and true or false
            end
        elseif not want and E.cleuArmed then
            pcall(E.cleuFrame.UnregisterEvent, E.cleuFrame, "COMBAT_LOG_EVENT_UNFILTERED")
            E.cleuArmed = false
        end
    end

    local frame = CreateFrame and CreateFrame("Frame") or nil
    if frame then
        for event in pairs(DOMAIN) do pcall(frame.RegisterEvent, frame, event) end   -- ENCOUNTER_END / BOSS_KILL are a bonus (A68)
        frame:SetScript("OnEvent", function(_, event, a1, a2, a3, a4, a5)
            if event == "QUEST_LOG_UPDATE" and Q.IsExpanding and Q.IsExpanding() then return end   -- UI 2611-2615's guard
            local collect = COLLECT[event]
            if collect then
                local ok, err = pcall(collect, a1, a2, a3, a4, a5)
                if not ok and geterrorhandler then pcall(geterrorhandler(), err) end
            end
            A.Invalidate(DOMAIN[event])
            if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then A.ArmCleu() end
        end)
        E.frame = frame
    end
end

-- byKey and the step indexes at load (the data file loads before this one;
-- the index rebuilds by itself if the data global is swapped later)
Index()
