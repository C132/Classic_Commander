-- Commander Quest Log: completion engine smoke test (luajit).
--
-- Loads CommanderQuestLogCompletion.lua ALONE, with no WoW mock and no fake
-- Questie, into a SEALED environment: reading any global the engine was not
-- given raises. That is the proof the engine is pure -- not a grep for API
-- names, but a run in which touching one would be an error -- and every
-- check below then runs through that sealed copy.
--
--   luajit completion_engine_smoke.lua
--
-- What it walks, in order: the constants; every row of Questie's DoableStates
-- mapping (all 33 names) plus the refined rows; the raw classifier; multi-
-- reason locks; prerequisite rules (any-of singles, all-of groups, exclusive
-- substitution, negative ids); the rival rule both ways, through both
-- requiredMinRep and requiredMaxRep, with and without "count both sides";
-- bucket precedence; exclusive slots (choice made here, made elsewhere, in
-- the log, not yet made, and the denominator before and after); chains
-- (topological order, level tie-break, cycles, standalone, external
-- prerequisites); totals and the floored percentage; the navigator groupings
-- with their fixed titles and header counts; distance ordering; filters; the
-- state words and reason sentences; and no shape glyphs anywhere.
--
-- Last, and only after all of that, the REAL CommanderQuestLogModel.lua is
-- loaded into a separate environment to prove a zone entry is a valid
-- Q.BuildList entry: search walks its objectives, Q.Progress answers 0,
-- folds hide a group's rows, and a flat list survives a fold made in the
-- Guide. The engine never sees that environment.

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local ENGINE = ADDONS .. "/Commander_QuestLog/CommanderQuestLogCompletion.lua"
local MODEL = ADDONS .. "/Commander_QuestLog/CommanderQuestLogModel.lua"

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end

local function EQ(actual, expected, label)
    CHECK(actual == expected, label, "got " .. tostring(actual) .. ", want " .. tostring(expected))
end

-- ===========================================================================
-- Load the engine into a sealed environment
-- ===========================================================================

local ALLOWED = {
    pairs = pairs, ipairs = ipairs, next = next, type = type, select = select,
    tonumber = tonumber, tostring = tostring,
    math = math, string = string, table = table,
}
local sealed = {}
for name, value in pairs(ALLOWED) do sealed[name] = value end
local touched = {}
setmetatable(sealed, {
    __index = function(_, name)
        if name == "CommanderQuestLog" then return nil end
        touched[#touched + 1] = name
        error("engine read the global '" .. tostring(name) .. "'", 2)
    end,
})

local chunk, loadErr = loadfile(ENGINE)
CHECK(chunk ~= nil, "engine file loads", loadErr)
if not chunk then
    io.write(string.format("%d checks, %d failures\n", checks, fails))
    os.exit(1)
end
setfenv(chunk, sealed)
local okLoad, runErr = pcall(chunk)
CHECK(okLoad, "engine main chunk runs with no WoW globals", runErr)

local Q = rawget(sealed, "CommanderQuestLog")
CHECK(type(Q) == "table", "engine creates CommanderQuestLog")
local C = Q and Q.Completion
CHECK(type(C) == "table", "engine publishes Q.Completion")
if not C then
    io.write(string.format("%d checks, %d failures\n", checks, fails))
    os.exit(1)
end

local newGlobals = {}
for name in pairs(sealed) do
    if not ALLOWED[name] then newGlobals[#newGlobals + 1] = name end
end
CHECK(#newGlobals == 1 and newGlobals[1] == "CommanderQuestLog",
    "the only global the engine writes is CommanderQuestLog", table.concat(newGlobals, ","))

-- ===========================================================================
-- Fixtures
-- ===========================================================================

local ALDOR, SCRYERS = 932, 934

-- A char built from plain sets. Every function is the shape the adapter
-- supplies; the sets are captured so a test can mutate them between passes.
--
-- `excl` is each quest's OWN exclusiveTo list (char.exclusiveTo, the only
-- one the engine decides by); `peers` is the adapter's forward-plus-reverse
-- answer (char.exclusivePeers, for naming). Most fixtures are symmetric
-- groups, where the two are the same, so `excl` defaults to `peers`; the
-- one-way fixtures in H pass both. `gone` is char.isGone, the adapter's
-- "Questie's verdict on this outside quest is permanent".
local function Char(t)
    t = t or {}
    local done, log, rep = t.done or {}, t.log or {}, t.rep or {}
    local peers, names, zones = t.peers or {}, t.names or {}, t.zones or {}
    local excl, gone = t.excl or peers, t.gone or {}
    return {
        level = t.level or 64,
        isComplete = function(id) return done[id] and true or false end,
        isInLog = function(id) return log[id] and true or false end,
        logInfo = t.logInfo and function(id) return t.logInfo[id] end or nil,
        exclusivePeers = function(id) return peers[id] end,
        exclusiveTo = function(id) return excl[id] end,
        isGone = function(id) return gone[id] and true or false end,
        questName = function(id) return names[id] end,
        questZoneName = function(id) return zones[id] end,
        repValue = function(factionId) return rep[factionId] end,
        factionName = function(factionId)
            if factionId == ALDOR then return "The Aldor" end
            if factionId == SCRYERS then return "The Scryers" end
            return nil
        end,
        skillName = t.skillName,
        rivals = { [ALDOR] = SCRYERS, [SCRYERS] = ALDOR },
        ignored = t.ignored or {},
        opts = t.opts or {},
        _done = done, _log = log, _rep = rep,
    }
end

local function Fact(t)
    t.name = t.name or ("Quest " .. t.id)
    t.questLevel = t.questLevel or 62
    t.requiredLevel = t.requiredLevel or 60
    t.layer = t.layer or "ZONE"
    if t.startsHere == nil then t.startsHere = true end
    t.starters = t.starters or {}
    t.finishers = t.finishers or {}
    return t
end

-- Every word and sentence the engine returns goes through here: plain ASCII
-- plus the two multi-byte characters the suite's fonts are known to carry.
local glyphFails = {}
local function GlyphSafe(text, label)
    local stripped = (text or ""):gsub("\194\183", ""):gsub("\226\128\148", "")
    if stripped:find("[\128-\255]") then glyphFails[#glyphFails + 1] = label .. ": " .. tostring(text) end
    return text
end

local function Word(entry)
    local word, colour = C.StateWord(entry)
    GlyphSafe(word, "word")
    return word, colour
end

local function Reason(entry, char, view)
    return GlyphSafe(C.Reason(entry, char, view), "reason")
end

local function Ids(list)
    local out = {}
    for _, entry in ipairs(list) do out[#out + 1] = entry.isHeader and ("[" .. entry.title .. "]") or tostring(entry.id) end
    return table.concat(out, " ")
end

local function Titles(list)
    local out = {}
    for _, entry in ipairs(list) do
        if entry.isHeader then out[#out + 1] = entry.title end
    end
    return out
end

local function Same(a, b)
    if #a ~= #b then return false end
    for index = 1, #a do if a[index] ~= b[index] then return false end end
    return true
end

local function Has(list, value)
    for _, v in ipairs(list or {}) do if v == value then return true end end
    return false
end

-- ===========================================================================
-- A. Constants
-- ===========================================================================

do
    local statuses = { "DONE", "LOG", "AVAILABLE", "LOCKED", "MISSED", "RIVAL", "REPEATABLE",
        "SEASONAL", "OPTIONAL", "IGNORED", "EXTRA" }
    local n = 0
    for _ in pairs(C.STATUS) do n = n + 1 end
    EQ(n, 11, "A: STATUS has eleven buckets")
    for _, s in ipairs(statuses) do EQ(C.STATUS[s], s, "A: STATUS." .. s) end
    for _, k in ipairs({ "LEVEL", "PREREQ", "REP", "PROFESSION", "CHOICE", "OTHER" }) do
        EQ(C.LOCK[k], k, "A: LOCK." .. k)
    end
    CHECK(Same(C.GROUPS, { "GUIDE", "STATUS", "CHAIN", "LEVEL", "NAME" }), "A: GROUPS order")
    for _, g in ipairs(C.GROUPS) do CHECK(type(C.GROUP_LABELS[g]) == "string", "A: GROUP_LABELS." .. g) end
    local labels = { ALL = "All", OPEN = "Open", LOCKED = "Locked", DONE = "Done", MISSED = "Missed" }
    for key, label in pairs(labels) do
        EQ(C.FILTERS[key] and C.FILTERS[key].label, label, "A: FILTERS." .. key .. " label")
        CHECK(type(C.FILTERS[key] and C.FILTERS[key].tooltip) == "string", "A: FILTERS." .. key .. " tooltip")
    end
    CHECK(Same(C.FILTER_ORDER, { "ALL", "OPEN", "LOCKED", "DONE", "MISSED" }), "A: FILTER_ORDER")
    local rows = 0
    for _ in pairs(C.STATE_MAP) do rows = rows + 1 end
    EQ(rows, 33, "A: STATE_MAP covers all 33 DoableStates names")
    CHECK(C.IsCountedBucket("LOCKED") and not C.IsCountedBucket("MISSED"), "A: IsCountedBucket")
end

-- ===========================================================================
-- B. Questie's verdicts: every row of the mapping table
-- ===========================================================================

do
    -- A level-64 character with nothing done; the fact is a plain level-62
    -- quest needing 60, so no extra reason creeps into the row under test.
    local rows = {
        { "COMPLETED", "DONE", "DONE", nil, "DONE", true },
        { "QUEST_LOG", "LOG", "LOG", nil, "IN_LOG", true },
        { "AVAILABLE", "AVAILABLE", "AVAILABLE", nil, "AVAILABLE", true },
        { "PARENT_ACTIVE", "AVAILABLE", "AVAILABLE", nil, "PARENT_ACTIVE", true },
        { "LEVEL_TOO_LOW", "LOCKED", "LOCKED", "LEVEL", "LEVEL", true },
        { "NO_PREQUESTSINGLE", "LOCKED", "LOCKED", "PREREQ", "PREREQ", true },
        { "NO_PREQUESTGROUP", "LOCKED", "LOCKED", "PREREQ", "PREREQ", true },
        { "BREADCRUMB_ACTIVE", "LOCKED", "LOCKED", "PREREQ", "BREADCRUMB_ACTIVE", true },
        { "ENABLING_QUEST_MISSING", "LOCKED", "LOCKED", "PREREQ", "ENABLING_QUEST", true },
        { "PARENT_INACTIVE", "LOCKED", "LOCKED", "PREREQ", "PARENT_INACTIVE", true },
        { "MISSING_REPUTATION", "LOCKED", "LOCKED", "REP", "REP", true },
        { "EXCEED_REPUTATION", "LOCKED", "LOCKED", "REP", "REP_HIGH", true },
        { "PROFESSION_SKILL", "LOCKED", "LOCKED", "PROFESSION", "SKILL", true },
        { "PROFESSION_RANK", "LOCKED", "LOCKED", "PROFESSION", "RANK", true },
        { "EXCLUSIVE_COMPLETED", "MISSED", "MISSED", nil, "CHOSE_OTHER", false },
        { "EXCLUSIVE_IN_QUEST_LOG", "LOCKED", "LOCKED", "CHOICE", "ON_OTHER", true },
        { "NEXTQUESTINCHAIN_ACTIVE_OR_COMPLETED", "MISSED", "MISSED", nil, "PAST_IN_CHAIN", false },
        { "BREADCRUMB_FOLLOWUP", "MISSED", "MISSED", nil, "SKIPPED_BREADCRUMB", false },
        { "LEVEL_TOO_HIGH", "MISSED", "MISSED", nil, "OUTLEVELED", false },
        { "PROFESSION_SPECIALIZATION", "MISSED", "MISSED", nil, "PROFESSION", false },
        { "PROFESSION_MISSING", "MISSED", "MISSED", nil, "PROFESSION", false },
        { "SPELL_KNOWN", "MISSED", "MISSED", nil, "NO_LONGER_OFFERED", false },
        { "DISABLING_QUEST_COMPLETED", "MISSED", "MISSED", nil, "NO_LONGER_OFFERED", false },
        { "BLACKLISTED", "MISSED", "MISSED", nil, "REMOVED", false },
        { "SPELL_MISSING", "LOCKED", "LOCKED", "OTHER", "SPELL", true },
        { "MISSING_ACHIEVEMENT", "LOCKED", "LOCKED", "OTHER", "ACHIEVEMENT", true },
        { "DISABLED_BY", "LOCKED", "LOCKED", "OTHER", "DISABLED_BY", true },
        { "ARENA_RATING", "LOCKED", "LOCKED", "OTHER", "ARENA_RATING", true },
        { "MISSING_DAILY", "AVAILABLE", "REPEATABLE", nil, "NOT_TODAY", false },
        { "INACTIVE_DAILY", "AVAILABLE", "REPEATABLE", nil, "NOT_TODAY", false },
        { "EVENT_INACTIVE", "LOCKED", "SEASONAL", "OTHER", "EVENT_CLOSED", false },
    }
    local char = Char({ level = 64 })
    for _, row in ipairs(rows) do
        local state, base, bucket, kind, reason, counted = row[1], row[2], row[3], row[4], row[5], row[6]
        local info = C.Classify(Fact({ id = 100, state = state }), char)
        CHECK(info ~= nil, "B: " .. state .. " is shown")
        if info then
            EQ(info.base, base, "B: " .. state .. " base")
            EQ(info.status, bucket, "B: " .. state .. " bucket")
            EQ(info.lockKind, kind, "B: " .. state .. " lockKind")
            EQ(info.reasonKey, reason, "B: " .. state .. " reasonKey")
            EQ(info.counted, counted, "B: " .. state .. " counted")
            EQ(info.state, state, "B: " .. state .. " carries the state name")
            if base == "LOCKED" then CHECK(type(info.lock) == "table", "B: " .. state .. " has a lock table") end
        end
    end
    EQ(C.Classify(Fact({ id = 100, state = "WRONG_RACE" }), char), nil, "B: WRONG_RACE is not shown")
    EQ(C.Classify(Fact({ id = 100, state = "WRONG_CLASS" }), char), nil, "B: WRONG_CLASS is not shown")

    -- LEVEL_TOO_LOW always names a level, even when Questie's UnitLevel lagged
    local lagged = C.Classify(Fact({ id = 101, state = "LEVEL_TOO_LOW", requiredLevel = 64 }), Char({ level = 64 }))
    EQ(lagged.lock.level, 64, "B: LEVEL_TOO_LOW keeps a level when char.level already reached it")

    -- QUEST_LOG carries the window's live complete / failed flags
    local live = { [110] = { complete = true }, [111] = { failed = true } }
    local logChar = Char({ logInfo = live })
    local ready = C.Classify(Fact({ id = 110, state = "QUEST_LOG" }), logChar)
    local failed = C.Classify(Fact({ id = 111, state = "QUEST_LOG" }), logChar)
    local plain = C.Classify(Fact({ id = 112, state = "QUEST_LOG" }), Char())
    CHECK(ready.ready == true and ready.failed == false, "B: QUEST_LOG ready from logInfo")
    CHECK(failed.failed == true and failed.ready == false, "B: QUEST_LOG failed from logInfo")
    CHECK(plain.ready == false and plain.failed == false, "B: QUEST_LOG without logInfo is neither")

    -- PARENT_INACTIVE: missed when the parent is already done
    local parentDone = C.Classify(Fact({ id = 120, state = "PARENT_INACTIVE", parent = 119 }), Char({ done = { [119] = true } }))
    EQ(parentDone.base, "MISSED", "B: PARENT_INACTIVE with the parent done is MISSED")
    EQ(parentDone.reasonKey, "PARENT_DONE", "B: PARENT_INACTIVE with the parent done says PARENT_DONE")
    local parentOpen = C.Classify(Fact({ id = 120, state = "PARENT_INACTIVE", parent = 119 }), Char())
    EQ(parentOpen.lockKind, "PREREQ", "B: PARENT_INACTIVE with the parent not done is a PREREQ lock")

    -- EXCEED_REPUTATION: one-way factions are gone, two-way ones are locked
    local oneWay = C.Classify(Fact({ id = 130, state = "EXCEED_REPUTATION", oneWayRep = true, maxRep = { 970, 9000 } }),
        Char({ rep = { [970] = 9500 } }))
    EQ(oneWay.base, "MISSED", "B: EXCEED_REPUTATION one-way is MISSED")
    EQ(oneWay.reasonKey, "REP_PAST", "B: EXCEED_REPUTATION one-way says REP_PAST")
    local twoWay = C.Classify(Fact({ id = 131, state = "EXCEED_REPUTATION", maxRep = { 970, 9000 } }),
        Char({ rep = { [970] = 9500 } }))
    EQ(twoWay.base, "LOCKED", "B: EXCEED_REPUTATION two-way is LOCKED")
    CHECK(twoWay.lock.repMax and twoWay.lock.repMax[1] == 970 and twoWay.lock.repMax[2] == 9000,
        "B: EXCEED_REPUTATION records the maximum")

    -- EXCLUSIVE verdicts name the peer
    local chose = C.Classify(Fact({ id = 140, state = "EXCLUSIVE_COMPLETED", exclusiveTo = { 141, 142 } }),
        Char({ done = { [142] = true } }))
    EQ(chose.chosen, 142, "B: EXCLUSIVE_COMPLETED names the done peer")
    local onOther = C.Classify(Fact({ id = 143, state = "EXCLUSIVE_IN_QUEST_LOG" }),
        Char({ log = { [144] = true }, peers = { [143] = { 144 } } }))
    EQ(onOther.chosen, 144, "B: EXCLUSIVE_IN_QUEST_LOG names the in-log peer (its own list, from char.exclusiveTo)")
    EQ(onOther.lock.choice, 144, "B: EXCLUSIVE_IN_QUEST_LOG lock.choice")

    -- An unknown state falls back to the raw classifier
    local unknown = C.Classify(Fact({ id = 150, state = "SOMETHING_NEW", requiredLevel = 66 }), Char({ level = 64 }))
    EQ(unknown.base, "LOCKED", "B: unknown state uses the raw classifier (level)")
    EQ(unknown.lockKind, "LEVEL", "B: unknown state raw lockKind")

    -- Missing beats locking: permanent reasons hidden behind Questie's first answer
    local crumb = C.Classify(Fact({ id = 160, state = "LEVEL_TOO_LOW", requiredLevel = 66, breadcrumbFor = 161 }),
        Char({ done = { [161] = true } }))
    EQ(crumb.base, "MISSED", "B: level-locked breadcrumb whose target is done is MISSED")
    EQ(crumb.reasonKey, "SKIPPED_BREADCRUMB", "B: ...as SKIPPED_BREADCRUMB")
    local past = C.Classify(Fact({ id = 162, state = "NO_PREQUESTSINGLE", preSingle = { 1 }, nextInChain = 163 }),
        Char({ log = { [163] = true } }))
    EQ(past.reasonKey, "PAST_IN_CHAIN", "B: prereq-locked quest whose follow-up is in the log is PAST_IN_CHAIN")
    local calendar = C.Classify(Fact({ id = 164, state = "EVENT_INACTIVE", nextInChain = 165 }),
        Char({ done = { [165] = true } }))
    EQ(calendar.reasonKey, "EVENT_CLOSED", "B: calendar rows keep their own reason")
end

-- ===========================================================================
-- C. The raw classifier (no Questie verdict)
-- ===========================================================================

do
    local function Raw(fact, char) return C.Classify(Fact(fact), char or Char()) end
    EQ(Raw({ id = 200 }, Char({ done = { [200] = true } })).base, "DONE", "C: complete is DONE")
    EQ(Raw({ id = 200 }, Char({ log = { [200] = true } })).base, "LOG", "C: in the log is LOG")
    local level = Raw({ id = 201, requiredLevel = 66 })
    CHECK(level.base == "LOCKED" and level.lockKind == "LEVEL" and level.lock.level == 66, "C: required level above is LOCKED LEVEL")
    local pre = Raw({ id = 202, preSingle = { 199 } })
    CHECK(pre.base == "LOCKED" and pre.lockKind == "PREREQ", "C: unmet prerequisite is LOCKED PREREQ")
    local rep = Raw({ id = 203, minRep = { 970, 3000 } }, Char({ rep = { [970] = 500 } }))
    CHECK(rep.base == "LOCKED" and rep.lockKind == "REP", "C: reputation below is LOCKED REP")
    EQ(Raw({ id = 204, minRep = { 970, 3000 } }).base, "AVAILABLE", "C: unknown reputation never locks")
    EQ(Raw({ id = 205 }).base, "AVAILABLE", "C: otherwise AVAILABLE")
    EQ(Raw({ id = 206, requiredMaxLevel = 63 }).reasonKey, "OUTLEVELED", "C: above requiredMaxLevel is OUTLEVELED")
    EQ(Raw({ id = 207, nextInChain = 208 }, Char({ done = { [208] = true } })).reasonKey, "PAST_IN_CHAIN", "C: next in chain done")
    EQ(Raw({ id = 209, breadcrumbFor = 210 }, Char({ log = { [210] = true } })).reasonKey, "SKIPPED_BREADCRUMB", "C: breadcrumb target in log")
    EQ(Raw({ id = 211, parent = 212 }).reasonKey, "PARENT_INACTIVE", "C: parent not in the log locks")
    EQ(Raw({ id = 211, parent = 212 }, Char({ log = { [212] = true } })).base, "AVAILABLE", "C: parent in the log opens")
    EQ(Raw({ id = 211, parent = 212 }, Char({ done = { [212] = true } })).reasonKey, "PARENT_DONE", "C: parent done is PARENT_DONE")
    EQ(Raw({ id = 213, maxRep = { 970, 9000 } }, Char({ rep = { [970] = 9000 } })).reasonKey, "REP_HIGH", "C: at the maximum is REP_HIGH")
    EQ(Raw({ id = 214, maxRep = { 970, 9000 }, oneWayRep = true }, Char({ rep = { [970] = 9000 } })).reasonKey, "REP_PAST", "C: one-way past the maximum")
    EQ(Raw({ id = 215, maxRep = { 970, 9000 } }, Char({ rep = { [970] = 8999 } })).base, "AVAILABLE", "C: below the maximum is fine")
    EQ(Raw({ id = 216, minRep = { 970, 3000 } }, Char({ rep = { [970] = 3000 } })).base, "AVAILABLE", "C: exactly at the minimum is met")
end

-- ===========================================================================
-- D. Multi-reason locks
-- ===========================================================================

do
    local char = Char({ level = 64, rep = { [970] = 0 } })
    local fact = Fact({ id = 300, name = "Triple Lock", requiredLevel = 66, preSingle = { 299 }, minRep = { 970, 3000 } })
    local raw = C.Classify(fact, char)
    EQ(raw.lockKind, "LEVEL", "D: raw classifier leads with LEVEL")
    EQ(raw.lock.level, 66, "D: lock.level")
    CHECK(Has(raw.lock.prereq, 299), "D: lock.prereq lists the unmet quest")
    CHECK(raw.lock.rep and raw.lock.rep[1] == 970 and raw.lock.rep[2] == 3000, "D: lock.rep")

    local verdict = C.Classify(Fact({ id = 301, state = "NO_PREQUESTSINGLE", requiredLevel = 66, preSingle = { 299 } }), char)
    EQ(verdict.lockKind, "PREREQ", "D: Questie's verdict leads")
    EQ(verdict.lock.level, 66, "D: ...and the level reason is still recorded")

    local skill = C.Classify(Fact({ id = 302, state = "PROFESSION_SKILL", requiredLevel = 66, skill = { 171, 300 } }), char)
    EQ(skill.lockKind, "PROFESSION", "D: profession verdict leads")
    CHECK(skill.lock.skill and skill.lock.skill[2] == 300 and skill.lock.level == 66, "D: skill and level both recorded")

    local nothing = C.Classify(Fact({ id = 303, state = "AVAILABLE", requiredLevel = 66 }), char)
    EQ(nothing.lock, nil, "D: a non-locked quest carries no lock")
end

-- ===========================================================================
-- E. Prerequisite rules (mirror of IsPreQuestSingle/GroupFulfilled)
-- ===========================================================================

do
    local function Unmet(fact, char)
        local info = C.Classify(Fact(fact), char)
        return info.lock and info.lock.prereq or {}, info
    end
    local peers = { [402] = { 403 } }
    local u = Unmet({ id = 400, preGroup = { 401, 402 } }, Char({ done = { [401] = true }, peers = peers }))
    CHECK(#u == 1 and u[1] == 402, "E: preGroup lists only the unmet member", table.concat(u, ","))
    local _, sub = Unmet({ id = 400, preGroup = { 401, 402 } }, Char({ done = { [401] = true, [403] = true }, peers = peers }))
    EQ(sub.base, "AVAILABLE", "E: a positive group id is satisfied by an exclusive peer")
    local neg = Unmet({ id = 400, preGroup = { 401, -402 } }, Char({ done = { [401] = true, [403] = true }, peers = peers }))
    CHECK(#neg == 1 and neg[1] == 402, "E: a negative group id ignores exclusive peers")
    local _, negDone = Unmet({ id = 400, preGroup = { -402 } }, Char({ done = { [402] = true } }))
    EQ(negDone.base, "AVAILABLE", "E: a negative group id is met by exactly that quest")
    local any, anyInfo = Unmet({ id = 404, preSingle = { 405, 406 } }, Char())
    CHECK(#any == 2 and Has(anyInfo.lock.prereqAny, 405) and Has(anyInfo.lock.prereqAny, 406), "E: preSingle unmet lists every option")
    local _, anyMet = Unmet({ id = 404, preSingle = { 405, 406 } }, Char({ done = { [406] = true } }))
    EQ(anyMet.base, "AVAILABLE", "E: preSingle is met by ANY one")
    EQ(C.Classify(Fact({ id = 407, preSingle = {} }), Char()).base, "AVAILABLE", "E: an empty preSingle is satisfied")
    EQ(C.Classify(Fact({ id = 407, preGroup = {} }), Char()).base, "AVAILABLE", "E: an empty preGroup is satisfied")
    local _, setShaped = Unmet({ id = 408, preGroup = { 402 } }, Char({ done = { [403] = true }, peers = { [402] = { [403] = true } } }))
    EQ(setShaped.base, "AVAILABLE", "E: a set-shaped exclusiveTo answer works too")
    local both = Unmet({ id = 409, preSingle = { 410, 411 }, preGroup = { 412 } }, Char())
    EQ(#both, 3, "E: single and group are both checked (Questie checks the group even with a single)")
end

-- ===========================================================================
-- F. The rival rule
-- ===========================================================================

do
    local scryer = { [ALDOR] = -3500, [SCRYERS] = 5000 }
    local aldor = { [ALDOR] = 5000, [SCRYERS] = -3500 }
    local aldorQuest = Fact({ id = 500, state = "MISSING_REPUTATION", minRep = { ALDOR, 3000 } })
    local scryerQuest = Fact({ id = 501, state = "MISSING_REPUTATION", minRep = { SCRYERS, 3000 } })

    local a = C.Classify(aldorQuest, Char({ rep = scryer }))
    EQ(a.base, "RIVAL", "F: a Scryer looking at an Aldor quest sees RIVAL")
    EQ(a.status, "RIVAL", "F: ...in the Other faction bucket")
    EQ(a.counted, false, "F: ...not counted")
    EQ(a.rival, true, "F: ...flagged rival")
    local b = C.Classify(scryerQuest, Char({ rep = aldor }))
    EQ(b.base, "RIVAL", "F: and the other way round")
    local own = C.Classify(Fact({ id = 502, state = "MISSING_REPUTATION", minRep = { ALDOR, 9000 } }), Char({ rep = aldor }))
    EQ(own.base, "LOCKED", "F: your own side's higher tier is a plain REP lock")
    local unknown = C.Classify(aldorQuest, Char({ rep = { [ALDOR] = -3500 } }))
    EQ(unknown.base, "LOCKED", "F: an unknown rival standing is not RIVAL")

    local counted = C.Classify(aldorQuest, Char({ rep = scryer, opts = { countRival = true } }))
    EQ(counted.status, "LOCKED", "F: countRival puts it in LOCKED")
    EQ(counted.lockKind, "REP", "F: ...lockKind REP")
    EQ(counted.counted, true, "F: ...counted")
    EQ(counted.rival, true, "F: ...still flagged rival")
    EQ(counted.base, "RIVAL", "F: ...base stays RIVAL")

    -- A rival quest above the player's level reads LEVEL_TOO_LOW in Questie
    local above = C.Classify(Fact({ id = 503, state = "LEVEL_TOO_LOW", requiredLevel = 66, minRep = { ALDOR, 3000 } }),
        Char({ level = 64, rep = scryer }))
    EQ(above.base, "RIVAL", "F: a level-locked rival quest is RIVAL, so the ding does not shrink the total")

    -- The pre-pledge mirror: offered only while BELOW Neutral with a side
    local prePledge = Fact({ id = 504, state = "EXCEED_REPUTATION", maxRep = { ALDOR, 0 } })
    EQ(C.Classify(prePledge, Char({ rep = aldor })).base, "RIVAL", "F: an Aldor sees the anti-Aldor pre-pledge quest as RIVAL")
    EQ(C.Classify(Fact({ id = 505, state = "EXCEED_REPUTATION", maxRep = { 970, 9000 } }), Char({ rep = { [970] = 9500 } })).base,
        "LOCKED", "F: a maximum on a faction with no rival stays a REP lock")

    local raw = C.Classify(Fact({ id = 506, minRep = { ALDOR, 3000 } }), Char({ rep = scryer }))
    EQ(raw.base, "RIVAL", "F: the raw classifier applies the rival rule too")
end

-- ===========================================================================
-- G. Bucket precedence and effective level
-- ===========================================================================

do
    local function Bucket(flags, opts, ignored)
        local fact = Fact({ id = 600, state = "AVAILABLE", event = flags.event, repeatable = flags.repeatable,
            daily = flags.daily, hiddenOnMap = flags.hidden, layer = flags.extra and "EXTRA" or "ZONE" })
        return C.Classify(fact, Char({ opts = opts, ignored = ignored and { [600] = true } or nil }))
    end
    local all = { event = true, repeatable = true, hidden = true, extra = true }
    EQ(Bucket(all, nil, true).status, "IGNORED", "G: ignored beats everything")
    EQ(Bucket(all).status, "SEASONAL", "G: seasonal beats repeatable")
    EQ(Bucket({ repeatable = true, hidden = true, extra = true }).status, "REPEATABLE", "G: repeatable beats optional")
    EQ(Bucket({ daily = true, hidden = true }).status, "REPEATABLE", "G: daily is repeatable")
    EQ(Bucket({ hidden = true, extra = true }).status, "OPTIONAL", "G: optional beats extra")
    EQ(Bucket({ hidden = true, extra = true }, { countOptional = true }).status, "EXTRA", "G: countOptional lets extra through")
    EQ(Bucket({ extra = true }).status, "EXTRA", "G: extra")
    EQ(Bucket({ extra = true }, { countExtras = true }).status, "AVAILABLE", "G: countExtras shows the base")
    EQ(Bucket({ hidden = true }, { countOptional = true }).counted, true, "G: countOptional counts it")
    EQ(Bucket({ hidden = true }).counted, false, "G: optional is not counted")
    local ignoredRival = C.Classify(Fact({ id = 601, minRep = { ALDOR, 3000 } }),
        Char({ rep = { [ALDOR] = -3500, [SCRYERS] = 5000 }, opts = { countRival = true }, ignored = { [601] = true } }))
    EQ(ignoredRival.status, "IGNORED", "G: ignored beats countRival")
    local forced = C.Classify(Fact({ id = 602, state = "MISSING_DAILY", event = true }), Char())
    EQ(forced.status, "SEASONAL", "G: an event daily is seasonal first")

    local l1, r1 = C.EffectiveLevel(Fact({ id = 603, questLevel = -1, requiredLevel = -1 }), Char({ level = 67 }))
    CHECK(l1 == 67 and r1 == 67, "G: -1 levels scale to the player")
    local l2, r2 = C.EffectiveLevel(Fact({ id = 604, questLevel = 0, requiredLevel = 58 }), Char())
    CHECK(l2 == 58 and r2 == 58, "G: a level-0 quest borrows its required level")
    local l3, r3 = C.EffectiveLevel(Fact({ id = 605, questLevel = 63, requiredLevel = 61 }), Char())
    CHECK(l3 == 63 and r3 == 61, "G: plain levels pass through")
    local scaled = C.Classify(Fact({ id = 606, questLevel = -1, requiredLevel = -1 }), Char({ level = 67 }))
    CHECK(scaled.base == "AVAILABLE" and scaled.level == 67, "G: a scaling quest is never level-locked")
end

-- ===========================================================================
-- H. Exclusive-choice slots
-- ===========================================================================

local function Trio(states, extra)
    local facts = {
        Fact({ id = 701, name = "Choice A", requiredLevel = 62, state = states[1] }),
        Fact({ id = 702, name = "Choice B", requiredLevel = 61, state = states[2] }),
        Fact({ id = 703, name = "Choice C", requiredLevel = 60, state = states[3] }),
        Fact({ id = 710, name = "Plain One", state = states[4] or "AVAILABLE" }),
        Fact({ id = 711, name = "Plain Two", state = states[5] or "AVAILABLE" }),
    }
    for _, f in ipairs(extra or {}) do facts[#facts + 1] = f end
    return facts
end

local TRIO_PEERS = {
    [701] = { 702, 703, 709 }, [702] = { 701, 703, 709 }, [703] = { 701, 702, 709 }, [709] = { 701, 702, 703 },
}

do
    -- Not chosen yet: one slot. C (lowest required level) holds it.
    local char = Char({ peers = TRIO_PEERS, names = { [709] = "Choice Elsewhere" } })
    local view = C.BuildZone(Trio({ "AVAILABLE", "AVAILABLE", "AVAILABLE" }), char, { areaId = 3483, name = "Hellfire" })
    local A, B, Cc = view.byId[701], view.byId[702], view.byId[703]
    local countedTrio = (A.counted and 1 or 0) + (B.counted and 1 or 0) + (Cc.counted and 1 or 0)
    EQ(countedTrio, 1, "H: an unmade choice counts once")
    EQ(Cc.counted, true, "H: ...the lowest required level holds the slot")
    CHECK(A.choiceOf == 3 and B.choiceOf == 3 and Cc.choiceOf == nil, "H: the others say one of 3")
    CHECK(A.status == "AVAILABLE" and B.status == "AVAILABLE", "H: ...and keep their bucket")
    EQ(Cc.slotSize, 3, "H: slotSize on the holder")
    EQ(view.totals.counted, 3, "H: denominator before the choice (slot + two plain)")
    local before = view.totals.counted

    -- AVAILABLE beats LOCKED for the slot
    local mixed = C.BuildZone(Trio({ "AVAILABLE", "AVAILABLE", "LEVEL_TOO_LOW" }), char, {})
    EQ(mixed.byId[702].counted, true, "H: an available member beats a lower-level locked one")
    -- tie on level -> lowest id
    local tie = C.BuildZone({
        Fact({ id = 721, requiredLevel = 60, state = "AVAILABLE" }), Fact({ id = 720, requiredLevel = 60, state = "AVAILABLE" }),
    }, Char({ peers = { [720] = { 721 }, [721] = { 720 } } }), {})
    EQ(tie.byId[720].counted, true, "H: level tie goes to the lowest id")

    -- Chosen here (Questie: COMPLETED + EXCLUSIVE_COMPLETED)
    char._done[702] = true
    local chosen = C.BuildZone(Trio({ "EXCLUSIVE_COMPLETED", "COMPLETED", "EXCLUSIVE_COMPLETED" }), char, {})
    EQ(chosen.byId[702].status, "DONE", "H: the chosen member is DONE")
    EQ(chosen.byId[701].status, "MISSED", "H: the others are MISSED")
    EQ(chosen.byId[701].reasonKey, "CHOSE_OTHER", "H: ...CHOSE_OTHER")
    EQ(chosen.byId[703].chosen, 702, "H: ...naming the chosen quest")
    EQ(chosen.byId[703].chosenName, "Choice B", "H: ...by its title")
    EQ(chosen.totals.counted, before, "H: denominator unchanged after the choice")
    EQ(chosen.totals.done, 1, "H: the choice is one done")

    -- Same choice, raw classifier (no Questie): the slot logic does it alone
    local rawChosen = C.BuildZone(Trio({}), char, {})
    EQ(rawChosen.byId[701].status, "MISSED", "H: raw: the others become MISSED")
    EQ(rawChosen.byId[701].chosen, 702, "H: raw: chosen")
    EQ(rawChosen.totals.counted, before, "H: raw: denominator unchanged")
    char._done[702] = nil

    -- Chosen in another zone
    char._done[709] = true
    local away = C.BuildZone(Trio({}), char, {})
    CHECK(away.byId[701].status == "MISSED" and away.byId[702].status == "MISSED" and away.byId[703].status == "MISSED",
        "H: a choice made in another zone misses every member here")
    EQ(away.byId[702].chosen, 709, "H: ...chosen is the outside quest")
    EQ(away.byId[702].chosenName, "Choice Elsewhere", "H: ...named through char.questName")
    EQ(away.totals.counted, before - 1, "H: ...and the slot belongs to the other zone")
    char._done[709] = nil

    -- In the log (here)
    char._log[701] = true
    local inLog = C.BuildZone(Trio({ "QUEST_LOG", "EXCLUSIVE_IN_QUEST_LOG", "EXCLUSIVE_IN_QUEST_LOG" }), char, {})
    EQ(inLog.byId[701].status, "LOG", "H: the in-log member stays LOG")
    EQ(inLog.byId[701].counted, true, "H: ...counted")
    CHECK(inLog.byId[702].status == "LOCKED" and inLog.byId[702].lockKind == "CHOICE", "H: the others are LOCKED CHOICE")
    EQ(inLog.byId[703].reasonKey, "ON_OTHER", "H: ...ON_OTHER")
    EQ(inLog.byId[703].counted, false, "H: ...not counted")
    EQ(inLog.byId[703].chosen, 701, "H: ...chosen is the in-log quest")
    EQ(inLog.totals.counted, before, "H: denominator unchanged while one is in the log")
    local rawLog = C.BuildZone(Trio({}), char, {})
    EQ(rawLog.byId[702].lockKind, "CHOICE", "H: raw: in-log choice locks the others")
    char._log[701] = nil

    -- In the log (another zone)
    char._log[709] = true
    local awayLog = C.BuildZone(Trio({}), char, {})
    CHECK(awayLog.byId[701].lockKind == "CHOICE" and awayLog.byId[701].chosen == 709, "H: an outside in-log choice locks every member")
    char._log[709] = nil

    -- Size-1 component with no peers is untouched
    local lone = C.BuildZone({ Fact({ id = 730, state = "AVAILABLE" }) }, Char(), {})
    CHECK(lone.byId[730].counted and lone.byId[730].choiceOf == nil and lone.byId[730].slotSize == nil, "H: a quest without peers is untouched")
    -- ...but a lone member whose peer lives elsewhere still learns of the choice
    local loneAway = C.BuildZone({ Fact({ id = 731, exclusiveTo = { 732 } }) }, Char({ done = { [732] = true } }), {})
    EQ(loneAway.byId[731].reasonKey, "CHOSE_OTHER", "H: a lone member with a done outside peer is missed")

    -- A peer here but uncounted (ignored) still counts as the choice
    local ignoredPeer = C.BuildZone({ Fact({ id = 740 }), Fact({ id = 741 }) },
        Char({ peers = { [740] = { 741 }, [741] = { 740 } }, done = { [741] = true }, ignored = { [741] = true } }), {})
    EQ(ignoredPeer.byId[740].reasonKey, "CHOSE_OTHER", "H: an ignored but done peer is still the choice")

    -- Data quirk: a member is done AND another is in the log -> the log one stays
    local quirk = C.BuildZone({ Fact({ id = 750 }), Fact({ id = 751 }), Fact({ id = 752 }) },
        Char({ peers = { [750] = { 751, 752 }, [751] = { 750, 752 }, [752] = { 750, 751 } },
            done = { [750] = true }, log = { [751] = true } }), {})
    CHECK(quirk.byId[751].status == "LOG" and quirk.byId[752].status == "MISSED", "H: a quest in the log is never called missed")

    -- 100% is reachable: everything plain done plus one of the trio
    local finish = Char({ peers = TRIO_PEERS, done = { [703] = true, [710] = true, [711] = true } })
    local full = C.BuildZone(Trio({ nil, nil, nil, "COMPLETED", "COMPLETED" }), finish, {})
    EQ(full.totals.pct, 1, "H: one choice plus the rest is 100%")
    EQ(C.PercentText(full.totals.pct), "100%", "H: ...and reads 100%")
end

-- exclusiveTo is ONE-WAY in Questie (IsDoableVerbose reads the quest's own
-- list, nothing else). The fixtures above are symmetric groups, which hid
-- that the engine used to read the relation both ways; the real TBC data has
-- 192 one-way pairs. "Journey to the Crossroads" (854) lists "Plainstrider
-- Menace" (844) and 844 lists nothing: doing 854 leaves 844 doable.
do
    local crumb = Fact({ id = 760, name = "Journey to the Crossroads", state = "COMPLETED", exclusiveTo = { 761 } })
    local target = Fact({ id = 761, name = "Plainstrider Menace", state = "AVAILABLE" })
    -- The adapter's reverse index knows 761 is named by 760; that must not count
    local oneWay = Char({ excl = { [760] = { 761 } }, peers = { [760] = { 761 }, [761] = { 760 } },
        done = { [760] = true } })
    local view = C.BuildZone({ crumb, target }, oneWay, {})
    local t = view.byId[761]
    CHECK(t.status == "AVAILABLE" and t.counted == true and t.reasonKey == "AVAILABLE",
        "H1: a quest that is only NAMED by a done quest stays available and counted (Questie's rule)",
        t.status .. " " .. tostring(t.reasonKey))
    EQ(view.totals.counted, 2, "H1: ...both count, the one-way pair is not a slot")
    local raw = C.BuildZone({ Fact({ id = 760, exclusiveTo = { 761 } }), Fact({ id = 761 }) }, oneWay, {})
    EQ(raw.byId[761].base, "AVAILABLE", "H1: raw classifier too: the reverse peer decides nothing")
    -- The other way round, the quest's OWN list decides: 761 done misses 760
    local back = C.BuildZone({ Fact({ id = 760, exclusiveTo = { 761 } }), Fact({ id = 761, state = "COMPLETED" }) },
        Char({ excl = { [760] = { 761 } }, peers = { [760] = { 761 }, [761] = { 760 } }, done = { [761] = true } }), {})
    CHECK(back.byId[760].status == "MISSED" and back.byId[760].reasonKey == "CHOSE_OTHER"
        and back.byId[760].chosen == 761, "H1: a quest whose own list names a done quest is missed")
    -- In the log: same direction rule
    local logged = C.BuildZone({ Fact({ id = 760, exclusiveTo = { 761 } }), Fact({ id = 761, state = "AVAILABLE" }) },
        Char({ excl = { [760] = { 761 } }, peers = { [760] = { 761 }, [761] = { 760 } }, log = { [760] = true } }), {})
    CHECK(logged.byId[761].status == "AVAILABLE" and logged.byId[761].counted,
        "H1: a quest named by one in the log is not locked as a choice")
    -- Bloodmyst: 9760 lists 9759, 9759 lists nothing. Before either, both count
    local pair = C.BuildZone({ Fact({ id = 762, exclusiveTo = { 763 } }), Fact({ id = 763 }) },
        Char({ excl = { [762] = { 763 } }, peers = { [762] = { 763 }, [763] = { 762 } } }), {})
    CHECK(pair.byId[762].counted and pair.byId[763].counted and pair.byId[762].choiceOf == nil,
        "H1: a one-way pair is not one slot")

    -- preGroup substitution is through the prerequisite's OWN list only
    -- (IsPreQuestGroupFulfilled): 771 names 770, but 770 lists nothing, so
    -- 771 done does not stand in for 770
    local sub = C.Classify(Fact({ id = 772, preGroup = { 770 } }),
        Char({ excl = { [771] = { 770 } }, peers = { [770] = { 771 }, [771] = { 770 } }, done = { [771] = true } }))
    CHECK(sub.base == "LOCKED" and Has(sub.lock.prereq, 770),
        "H1: a reverse-only peer does not satisfy a preGroup member", sub.base)
    local fwd = C.Classify(Fact({ id = 772, preGroup = { 770 } }),
        Char({ excl = { [770] = { 771 } }, done = { [771] = true } }))
    EQ(fwd.base, "AVAILABLE", "H1: a peer in the member's own list does")
end

-- Tiered lines: the Caverns of Time rings. Four lines (pledges 780-783, a
-- clique), three later tiers each; every later tier lists the OTHER lines'
-- pledges. The pledges are one slot, each tier follows the pledge its list
-- leaves out, and the denominator is one line's length before and after.
local function Rings(states)
    local facts, excl = {}, {}
    local pledges = { 780, 781, 782, 783 }
    for i, pledge in ipairs(pledges) do
        local others = {}
        for j, other in ipairs(pledges) do if j ~= i then others[#others + 1] = other end end
        excl[pledge] = others
        facts[#facts + 1] = Fact({ id = pledge, name = "Pledge " .. i, requiredLevel = 70, questLevel = 70,
            state = states[pledge], exclusiveTo = others })
        local previous = pledge
        for tier = 1, 3 do
            local id = 800 + i * 10 + tier
            excl[id] = others
            facts[#facts + 1] = Fact({ id = id, name = "Line " .. i .. " tier " .. tier, requiredLevel = 70,
                questLevel = 70, state = states[id], exclusiveTo = others, preSingle = { previous } })
            previous = id
        end
    end
    return facts, excl
end

do
    local facts, excl = Rings({})
    local char = Char({ excl = excl, level = 70 })
    local before = C.BuildZone(facts, char, {})
    EQ(before.totals.counted, 4, "H2: before any pledge, one line counts: the pledge and its three tiers")
    CHECK(before.byId[780].counted and before.byId[811].counted and before.byId[813].counted,
        "H2: ...the slot holder's own line")
    CHECK(not before.byId[781].counted and before.byId[781].choiceOf == 4, "H2: the other pledges are choices")
    CHECK(not before.byId[821].counted and before.byId[821].choiceOf == 4 and before.byId[821].follows == 781,
        "H2: another line's tier follows its own pledge and does not count")
    EQ(Reason(before.byId[822], char, before), "Follows \"Pledge 2\", one of 4 choices; only one line counts.",
        "H2: ...and says which line it is on")
    EQ(before.byId[811].follows, 780, "H2: the counted line's tiers know their head too")

    -- Pledge 2 turned in: the other pledges and the other lines' tiers are
    -- missed by their own lists (raw classifier: no verdicts at all)
    char._done[781] = true
    local after = C.BuildZone(Rings({}), char, {})
    EQ(after.totals.counted, 4, "H2: after the pledge, still one line: the denominator did not move")
    EQ(after.totals.done, 1, "H2: ...with the pledge done")
    CHECK(after.byId[821].counted and after.byId[823].counted, "H2: the chosen line's tiers count")
    CHECK(after.byId[811].status == "MISSED" and after.byId[811].chosen == 781, "H2: the other lines' tiers are missed")
    char._done[781] = nil
    -- With Questie's verdicts the same
    local verdicts = {}
    for _, id in ipairs({ 780, 782, 783, 811, 812, 813, 831, 832, 833, 841, 842, 843 }) do verdicts[id] = "EXCLUSIVE_COMPLETED" end
    verdicts[781] = "COMPLETED"
    verdicts[821], verdicts[822], verdicts[823] = "AVAILABLE", "NO_PREQUESTSINGLE", "NO_PREQUESTSINGLE"
    local vf = Rings(verdicts)
    local viaQuestie = C.BuildZone(vf, Char({ excl = excl, level = 70, done = { [781] = true } }), {})
    EQ(viaQuestie.totals.counted, 4, "H2: with Questie's verdicts the denominator is the same 4")

    -- A pledge in the log: its line counts, the others are choices locked out
    local pending = C.BuildZone(Rings({}), Char({ excl = excl, level = 70, log = { [782] = true } }), {})
    EQ(pending.totals.counted, 4, "H2: a pledge in the log keeps the denominator")
    CHECK(pending.byId[811].lockKind == "CHOICE" and not pending.byId[811].counted,
        "H2: another line's tier is locked as a choice")

    -- (review 2026-10-04, round 2) A follower in the log or done is never
    -- uncounted: its line is the one the player is on, so its head takes the
    -- slot, and the other pledges are the choices
    local onTier = C.BuildZone(Rings({}), Char({ excl = excl, level = 70, log = { [822] = true } }), {})
    local t822 = onTier.byId[822]
    CHECK(t822.status == "LOG" and t822.counted and t822.choiceOf == nil,
        "H2: a follower in the log stays LOG and counted", t822.status .. " " .. tostring(t822.counted))
    EQ(Reason(t822, char, onTier), "In your quest log.", "H2: ...and reads as in the log, not as one of 4 choices")
    CHECK(onTier.byId[781].counted and onTier.byId[781].choiceOf == nil, "H2: ...its head holds the slot")
    CHECK(not onTier.byId[780].counted and onTier.byId[780].choiceOf == 4, "H2: ...the old holder is one of the choices")
    CHECK(not onTier.byId[811].counted and onTier.byId[821].counted, "H2: ...and the lines swap with it")
    EQ(onTier.totals.counted, 4, "H2: ...the denominator is still one line")
    local doneTier = C.BuildZone(Rings({}), Char({ excl = excl, level = 70, done = { [821] = true } }), {})
    CHECK(doneTier.byId[821].status == "DONE" and doneTier.byId[821].counted, "H2: a done follower stays DONE and counted")
    CHECK(doneTier.byId[781].counted and doneTier.byId[822].counted and not doneTier.byId[780].counted,
        "H2: ...its line holds the slot")
    CHECK(doneTier.totals.counted == 4 and doneTier.totals.done == 1, "H2: ...four counted, one of them done",
        doneTier.totals.counted .. "/" .. doneTier.totals.done)

    -- Ignoring one pledge, the first one the other lines name or another:
    -- every tier still follows its own line and the total stays one line
    for _, ignoredPledge in ipairs({ 780, 782 }) do
        local ignoreChar = Char({ excl = excl, level = 70, ignored = { [ignoredPledge] = true } })
        local ig = C.BuildZone(Rings({}), ignoreChar, {})
        EQ(ig.totals.counted, 4, "H2: ignoring pledge " .. ignoredPledge .. " keeps the total at one line")
        local tier = 800 + (ignoredPledge - 779) * 10 + 1
        CHECK(ig.byId[tier].follows == ignoredPledge and not ig.byId[tier].counted,
            "H2: ...its own tiers still follow it and do not count", tostring(ig.byId[tier].follows))
        EQ(ig.byId[ignoredPledge].status, "IGNORED", "H2: ...and the pledge itself stays ignored")
    end

    -- A breadcrumb into one choice (Muren Stormpike into Vejrek) follows it.
    -- Picking the breadcrumb up starts that line, which then holds the slot.
    local classPeers = { [901] = { 902, 903, 904 }, [902] = { 901, 903, 904 }, [903] = { 901, 902, 904 },
        [904] = { 901, 902, 903 }, [905] = { 901, 903, 904 } }
    local function Crumb(t)
        t.excl, t.level = classPeers, 12
        local facts = {}
        for id = 901, 904 do facts[#facts + 1] = Fact({ id = id, name = "Class " .. id, requiredLevel = 10, questLevel = 10 }) end
        facts[5] = Fact({ id = 905, name = "Muren Stormpike", requiredLevel = 10, questLevel = 10, breadcrumbFor = 902 })
        return C.BuildZone(facts, Char(t), {})
    end
    local fresh = Crumb({})
    CHECK(fresh.byId[901].counted and not fresh.byId[905].counted and fresh.byId[905].follows == 902,
        "H2: a breadcrumb into a choice follows it and does not count before it is taken")
    EQ(fresh.totals.counted, 1, "H2: ...one class quest counts")
    local carried = Crumb({ log = { [905] = true } })
    CHECK(carried.byId[905].status == "LOG" and carried.byId[905].counted, "H2: the breadcrumb in the log counts")
    CHECK(carried.byId[902].counted and not carried.byId[901].counted and carried.byId[901].choiceOf == 4,
        "H2: ...and the quest it leads to holds the slot")
    local handed = Crumb({ done = { [905] = true } })
    CHECK(handed.byId[905].status == "DONE" and handed.byId[905].counted and handed.byId[902].counted,
        "H2: turned in, the breadcrumb is done and counted, its target holds the slot")
    CHECK(handed.totals.counted == 2 and handed.totals.done == 1, "H2: ...two counted, one done",
        handed.totals.counted .. "/" .. handed.totals.done)
    local finished = Crumb({ done = { [905] = true, [902] = true } })
    CHECK(finished.totals.counted == 2 and finished.totals.done == 2, "H2: ...and the line finished is 100%",
        finished.totals.counted .. "/" .. finished.totals.done)
end

-- ===========================================================================
-- I. Chains
-- ===========================================================================

local CHAIN_FACTS
do
    CHAIN_FACTS = {
        Fact({ id = 800, name = "The Breadcrumb", questLevel = 60, breadcrumbFor = 801 }),
        Fact({ id = 801, name = "Chain One", questLevel = 60, nextInChain = 802 }),
        Fact({ id = 802, name = "Chain Two", questLevel = 61 }),
        Fact({ id = 803, name = "Chain Three", questLevel = 61, preSingle = { 802 } }),
        Fact({ id = 804, name = "Chain Four", questLevel = 63, preGroup = { 803, -850 } }),
        Fact({ id = 810, name = "Fork Root", questLevel = 60 }),
        Fact({ id = 811, name = "Fork High", questLevel = 62, preSingle = { 810 } }),
        Fact({ id = 812, name = "Fork Low", questLevel = 61, preSingle = { 810 } }),
        Fact({ id = 813, name = "Fork Same", questLevel = 61, preSingle = { 810 } }),
        Fact({ id = 820, name = "Loop A", questLevel = 62, preSingle = { 821 } }),
        Fact({ id = 821, name = "Loop B", questLevel = 61, preSingle = { 820 } }),
        Fact({ id = 822, name = "After Loop", questLevel = 60, preSingle = { 821 } }),
        Fact({ id = 830, name = "Loner", questLevel = 62 }),
        Fact({ id = 840, name = "Daily Off Chain", questLevel = 64, preSingle = { 801 }, daily = true }),
        Fact({ id = 841, name = "Needs Elsewhere", questLevel = 62, preSingle = { 860 } }),
    }
    local char = Char({ done = { [800] = true, [801] = true, [850] = true } })
    local view = C.BuildZone(CHAIN_FACTS, char, { areaId = 3483 })
    local chainOf = {}
    for _, chain in ipairs(view.chains) do chainOf[chain.id] = chain end

    local main = chainOf[800]
    CHECK(main ~= nil, "I: the breadcrumb roots the main chain")
    if main then
        CHECK(Same(main.members, { 800, 801, 802, 803, 804 }), "I: topological order", table.concat(main.members, ","))
        EQ(main.title, "The Breadcrumb", "I: chain title is the root's name")
        EQ(main.total, 5, "I: chain total counts counted members")
        EQ(main.done, 2, "I: chain done")
    end
    EQ(view.byId[803].chain, 800, "I: members carry the chain id")
    EQ(view.byId[803].chainPos, 4, "I: ...and their position")
    CHECK(Same(view.byId[804].externalPrereqs or {}, { 850 }), "I: externalPrereqs lists the out-of-zone quest (negative id folded)")
    EQ(view.byId[803].externalPrereqs, nil, "I: an in-zone prerequisite is not external")

    local fork = chainOf[810]
    CHECK(fork and Same(fork.members, { 810, 812, 813, 811 }), "I: level then id breaks ties", fork and table.concat(fork.members, ","))

    local loopChain
    for _, chain in ipairs(view.chains) do
        if Has(chain.members, 821) then loopChain = chain end
    end
    CHECK(loopChain and #loopChain.members == 3, "I: cycle members and their dependant are all kept")
    CHECK(loopChain and loopChain.id == loopChain.members[1] and loopChain.title == "After Loop",
        "I: a cycle's chain is rooted at its first member in order")
    CHECK(loopChain and Same(loopChain.members, { 822, 821, 820 }), "I: cycle remainder ordered by level, then id",
        loopChain and table.concat(loopChain.members, ","))

    EQ(view.byId[830].chain, nil, "I: a quest with no links is standalone")
    EQ(view.byId[830].chainPos, nil, "I: ...with no position")
    EQ(view.byId[840].chain, nil, "I: dailies are not chain members")
    EQ(view.byId[840].externalPrereqs, nil, "I: a daily's in-zone prerequisite is not external")
    CHECK(Same(view.byId[841].externalPrereqs or {}, { 860 }), "I: a standalone quest still records its external prerequisite")
    EQ(view.byId[841].chain, nil, "I: an external prerequisite does not make a chain")

    -- An ignored member stays in the chain but out of its count
    local ign = Char({ done = { [800] = true }, ignored = { [802] = true } })
    local ignView = C.BuildZone(CHAIN_FACTS, ign, {})
    local ignMain
    for _, chain in ipairs(ignView.chains) do if chain.id == 800 then ignMain = chain end end
    CHECK(ignMain and #ignMain.members == 5 and ignMain.total == 4, "I: an ignored member is listed but not counted")

    -- Chains are ordered by root level, then title
    EQ(#view.chains, 3, "I: three chains (main, fork, loop)")
    local sorted = true
    for index = 2, #view.chains do
        local a, b = view.chains[index - 1], view.chains[index]
        local la, lb = view.byId[a.id].level, view.byId[b.id].level
        if la > lb or (la == lb and a.title:lower() > b.title:lower()) then sorted = false end
    end
    CHECK(sorted, "I: chains sorted by root level, then title")
    EQ(view.chains[1].title, "After Loop", "I: ...so the level-60 'After Loop' chain leads")
end

-- ===========================================================================
-- J. The zone view: entries, totals, percentage
-- ===========================================================================

do
    local empty = C.BuildZone({}, Char(), { areaId = 1, name = "Nowhere" })
    EQ(empty.totals.counted, 0, "J: an empty zone counts nothing")
    EQ(empty.totals.pct, nil, "J: ...and has no percentage")
    EQ(C.PercentText(empty.totals.pct), "--", "J: ...which reads --")
    EQ(empty.name, "Nowhere", "J: meta name passes through")
    EQ(empty.areaId, 1, "J: meta areaId passes through")

    local allMissed = C.BuildZone({ Fact({ id = 900, state = "LEVEL_TOO_HIGH" }) }, Char(), {})
    EQ(allMissed.totals.pct, nil, "J: a zone with only missed quests has no percentage")

    local facts = {
        Fact({ id = 901, state = "COMPLETED", questLevel = 61 }),
        Fact({ id = 902, state = "QUEST_LOG", questLevel = 62 }),
        Fact({ id = 903, state = "AVAILABLE", questLevel = 63, name = nil }),
        Fact({ id = 904, state = "LEVEL_TOO_LOW", questLevel = 66, requiredLevel = 66 }),
        Fact({ id = 905, state = "LEVEL_TOO_HIGH" }),
        Fact({ id = 906, state = "WRONG_RACE" }),
        Fact({ id = 907, state = "AVAILABLE", daily = true }),
        Fact({ id = 908, state = "AVAILABLE", hiddenOnMap = true }),
        Fact({ id = 909, state = "AVAILABLE", layer = "EXTRA" }),
        Fact({ id = 909, state = "COMPLETED", layer = "ZONE", name = "Zone Copy" }),
    }
    facts[3].name = nil
    local view = C.BuildZone(facts, Char(), { areaId = 3483 })
    EQ(view.totals.counted, 5, "J: counted = DONE + LOG + AVAILABLE + LOCKED (+ the ZONE copy of a duplicate)")
    EQ(view.totals.done, 2, "J: done counts counted DONE")
    CHECK(math.abs(view.totals.pct - 0.4) < 1e-9, "J: pct = done / counted")
    EQ(view.byId[906], nil, "J: WRONG_RACE is not an entry")
    EQ(view.byId[909].title, "Zone Copy", "J: a quest in both layers keeps its ZONE copy")
    EQ(view.byId[903].title, "Quest 903", "J: an unnamed quest gets a placeholder title")
    local byStatus = view.totals.byStatus
    local n = 0
    for _ in pairs(byStatus) do n = n + 1 end
    EQ(n, 11, "J: byStatus has every bucket")
    CHECK(byStatus.DONE == 2 and byStatus.MISSED == 1 and byStatus.REPEATABLE == 1 and byStatus.OPTIONAL == 1 and byStatus.EXTRA == 0,
        "J: byStatus counts buckets")
    local cbs = view.totals.countedByStatus
    EQ(cbs.DONE + cbs.LOG + cbs.AVAILABLE + cbs.LOCKED, view.totals.counted, "J: countedByStatus adds up to counted")

    local summary = C.Summary(view)
    CHECK(summary.counted == 5 and summary.done == 2 and summary.pct == view.totals.pct, "J: Summary copies the totals")
    CHECK(summary ~= view.totals, "J: ...as a new table")
    EQ(C.Summary(nil).counted, 0, "J: Summary of nothing")

    local allValid = true
    for _, entry in ipairs(view.entries) do
        if not (entry.isHeader == false and type(entry.objectives) == "table" and #entry.objectives == 0
            and entry.key == "id:" .. entry.id and entry.questID == entry.id and entry.numObjectives == 0
            and entry.fact and type(entry.title) == "string" and type(entry.level) == "number"
            and type(entry.starters) == "table" and type(entry.finishers) == "table") then
            allValid = false
        end
    end
    CHECK(allValid, "J: every entry is BuildList-shaped with objectives = {}")
    EQ(#view.entries, 8, "J: one entry per shown quest")
    local ordered = true
    for index = 2, #view.entries do
        if view.entries[index - 1].level > view.entries[index].level then ordered = false end
    end
    CHECK(ordered, "J: entries are in level order")

    EQ(C.PercentText(199 / 200), "99%", "J: percentages floor (199/200 is 99%)")
    EQ(C.PercentText(2 / 3), "66%", "J: 2/3 is 66%")
    EQ(C.PercentText(0.69), "69%", "J: 0.69 is 69%, not 68%")
    EQ(C.PercentText(0), "0%", "J: 0%")
    EQ(C.TotalsText({ counted = 90, done = 62, pct = 62 / 90 }), "62 / 90  \194\183  68%", "J: TotalsText")
    EQ(C.TotalsText({ counted = 90, done = 62, pct = 62 / 90 }, true), "62/90 \194\183 68%", "J: TotalsText compact")
    GlyphSafe(C.TotalsText({ counted = 1, done = 0, pct = 0 }), "totals")
end

-- ===========================================================================
-- K. Grouping
-- ===========================================================================

local RICH_FACTS = {
    Fact({ id = 1001, name = "Ready Quest", state = "QUEST_LOG", questLevel = 62 }),
    Fact({ id = 1002, name = "Working Quest", state = "QUEST_LOG", questLevel = 61 }),
    Fact({ id = 1003, name = "Far Quest", state = "AVAILABLE", questLevel = 60,
        starters = { { kind = "npc", id = 1, name = "Far Giver", areaId = 3483, x = 90, y = 90 } } }),
    Fact({ id = 1004, name = "Near Quest", state = "AVAILABLE", questLevel = 63,
        starters = { { kind = "npc", id = 2, name = "Near Giver", areaId = 3483, x = 52, y = 50 } } }),
    Fact({ id = 1005, name = "Elsewhere Quest", state = "AVAILABLE", questLevel = 59, startsHere = false,
        startZoneName = "Shattrath City", starters = { { kind = "npc", id = 3, name = "City Giver", areaId = 3703, x = 50, y = 50 } } }),
    Fact({ id = 1006, name = "Other Map Spawn", state = "AVAILABLE", questLevel = 59,
        starters = { { kind = "npc", id = 4, name = "Sub Giver", areaId = 3545, x = 50, y = 50 } } }),
    Fact({ id = 1010, name = "Level Late", state = "LEVEL_TOO_LOW", requiredLevel = 68, questLevel = 68 }),
    Fact({ id = 1011, name = "Level Soon", state = "LEVEL_TOO_LOW", requiredLevel = 66, questLevel = 66 }),
    Fact({ id = 1020, name = "Chain Root", state = "COMPLETED", questLevel = 60 }),
    Fact({ id = 1021, name = "Chain Next", state = "NO_PREQUESTSINGLE", preSingle = { 1022 }, questLevel = 60 }),
    Fact({ id = 1022, name = "Chain Mid", state = "AVAILABLE", preSingle = { 1020 }, questLevel = 60 }),
    Fact({ id = 1030, name = "Needs Rep", state = "MISSING_REPUTATION", minRep = { 970, 3000 } }),
    Fact({ id = 1031, name = "Needs Skill", state = "PROFESSION_SKILL", skill = { 171, 300 } }),
    Fact({ id = 1040, name = "Done Quest", state = "COMPLETED", questLevel = 58 }),
    Fact({ id = 1050, name = "Missed Quest", state = "LEVEL_TOO_HIGH" }),
    Fact({ id = 1051, name = "Rival Quest", state = "MISSING_REPUTATION", minRep = { ALDOR, 3000 } }),
    Fact({ id = 1052, name = "Daily Quest", state = "AVAILABLE", daily = true }),
    Fact({ id = 1053, name = "Event Quest", state = "EVENT_INACTIVE", event = true }),
    Fact({ id = 1054, name = "Hidden Quest", state = "AVAILABLE", hiddenOnMap = true }),
    Fact({ id = 1055, name = "Dungeon Quest", state = "AVAILABLE", layer = "EXTRA" }),
    Fact({ id = 1056, name = "Ignored Quest", state = "AVAILABLE" }),
}

local function RichChar(opts)
    return Char({
        level = 64,
        logInfo = { [1001] = { complete = true } },
        rep = { [970] = 0, [ALDOR] = -3500, [SCRYERS] = 5000 },
        done = { [1020] = true, [1040] = true },
        ignored = { [1056] = true },
        opts = opts,
    })
end

do
    local view = C.BuildZone(RICH_FACTS, RichChar(), { areaId = 3483, name = "Hellfire Peninsula" })
    local guide = C.Group(view, "GUIDE", {})
    local expected = { "Turn in", "In progress", "Pick up now", "Unlocks with level", "After another quest",
        "Needs reputation or skill", "Done", "Missed", "Other faction", "Dailies and repeatables", "Seasonal",
        "Optional", "Also starting here", "Ignored" }
    CHECK(Same(Titles(guide), expected), "K: GUIDE titles and order", table.concat(Titles(guide), " | "))

    -- Every quest appears once, right under its header, with header set
    local seen, under, headerOk, countsOk = {}, nil, true, true
    local tally = {}
    for _, row in ipairs(guide) do
        if row.isHeader then
            under = row
            tally[row] = 0
            if row.countMode ~= "COUNT" then countsOk = false end
        else
            seen[row.id] = (seen[row.id] or 0) + 1
            if row.header ~= (under and under.title) then headerOk = false end
            tally[under] = tally[under] + 1
        end
    end
    for header, n in pairs(tally) do if header.quests ~= n then countsOk = false end end
    local once = true
    for _, entry in ipairs(view.entries) do if seen[entry.id] ~= 1 then once = false end end
    CHECK(once, "K: GUIDE lists every quest exactly once")
    CHECK(headerOk, "K: GUIDE sets entry.header to its group title")
    CHECK(countsOk, "K: GUIDE headers are COUNT with quests = rows under them")
    local doneHeader
    for _, row in ipairs(guide) do if row.isHeader and row.title == "Done" then doneHeader = row end end
    EQ(doneHeader and doneHeader.complete, 2, "K: a header's complete counts its done quests")
    EQ(doneHeader and doneHeader.group, "DONE", "K: header group key")

    local function Section(list, title)
        local out, inside = {}, false
        for _, row in ipairs(list) do
            if row.isHeader then inside = (row.title == title)
            elseif inside then out[#out + 1] = row.id end
        end
        return out
    end
    CHECK(Same(Section(guide, "Turn in"), { 1001 }), "K: Turn in holds the ready log quest")
    CHECK(Same(Section(guide, "In progress"), { 1002 }), "K: In progress holds the rest of the log")
    CHECK(Same(Section(guide, "Unlocks with level"), { 1011, 1010 }), "K: Unlocks with level by required level")
    CHECK(Same(Section(guide, "After another quest"), { 1021 }), "K: After another quest")
    CHECK(Same(Section(guide, "Needs reputation or skill"), { 1030, 1031 }), "K: Needs reputation or skill")
    CHECK(Same(Section(guide, "Other faction"), { 1051 }), "K: Other faction holds the uncounted rival")
    CHECK(Same(Section(guide, "Ignored"), { 1056 }), "K: Ignored last")

    -- Pick up now: level order without a position, distance with one
    CHECK(Same(Section(guide, "Pick up now"), { 1005, 1006, 1022, 1003, 1004 }), "K: Pick up now without a position is level, name",
        table.concat(Section(guide, "Pick up now"), ","))
    local near = C.Group(view, "GUIDE", { playerPos = { x = 50, y = 50 } })
    CHECK(Same(Section(near, "Pick up now"), { 1004, 1003, 1005, 1006, 1022 }),
        "K: Pick up now by distance; starters elsewhere or on another map sort after", table.concat(Section(near, "Pick up now"), ","))
    local far = C.Group(view, "GUIDE", { playerPos = { x = 95, y = 95 } })
    EQ(Section(far, "Pick up now")[1], 1003, "K: standing by the far giver puts it first")

    -- Counted rival goes to Needs reputation or skill
    local countRival = C.BuildZone(RICH_FACTS, RichChar({ countRival = true }), {})
    local cr = C.Group(countRival, "GUIDE", {})
    CHECK(Has(Section(cr, "Needs reputation or skill"), 1051), "K: a counted rival sits with the reputation locks")
    local crTitles = Titles(cr)
    CHECK(not Has(crTitles, "Other faction"), "K: empty groups are omitted")

    -- STATUS
    local status = C.Group(view, "STATUS", {})
    CHECK(Same(Titles(status), { "In your log", "Available", "Locked", "Done", "Missed", "Other faction",
        "Dailies and repeatables", "Seasonal", "Optional", "Also starting here", "Ignored" }),
        "K: STATUS titles and order", table.concat(Titles(status), " | "))
    EQ(Section(status, "In your log")[1], 1001, "K: STATUS puts ready log quests first")
    CHECK(Same(Section(status, "Locked"), { 1021, 1030, 1031, 1011, 1010 }), "K: STATUS Locked in level order",
        table.concat(Section(status, "Locked"), ","))

    -- CHAIN
    local chain = C.Group(view, "CHAIN", {})
    local chainHeader = chain[1]
    CHECK(chainHeader.isHeader and chainHeader.countMode == "RATIO", "K: CHAIN headers are RATIO")
    EQ(chainHeader.title, "Chain Root", "K: CHAIN header title is the chain title")
    EQ(chainHeader.quests, 3, "K: CHAIN header quests = chain total")
    EQ(chainHeader.complete, 1, "K: CHAIN header complete = chain done")
    EQ(chainHeader.chainId, 1020, "K: CHAIN header carries the chain id")
    CHECK(Same(Section(chain, "Chain Root"), { 1020, 1022, 1021 }), "K: CHAIN members in chain order")
    local chainTitles = Titles(chain)
    EQ(chainTitles[2], "Standalone quests", "K: Standalone quests follow the chains")
    EQ(chainTitles[3], "Missed", "K: then the uncounted groups")
    CHECK(not Has(Section(chain, "Standalone quests"), 1020), "K: chain members are not standalone")
    local seenChain = {}
    for _, row in ipairs(chain) do if not row.isHeader then seenChain[row.id] = (seenChain[row.id] or 0) + 1 end end
    local chainOnce = true
    for _, entry in ipairs(view.entries) do if seenChain[entry.id] ~= 1 then chainOnce = false end end
    CHECK(chainOnce, "K: CHAIN lists every quest exactly once")

    -- LEVEL / NAME: flat, no headers, header cleared
    local level = C.Group(view, "LEVEL", {})
    local name = C.Group(view, "NAME", {})
    EQ(#Titles(level), 0, "K: LEVEL has no headers")
    EQ(#Titles(name), 0, "K: NAME has no headers")
    EQ(#level, #view.entries, "K: LEVEL lists every quest")
    local cleared, levelOrdered, nameOrdered = true, true, true
    for index, entry in ipairs(level) do
        if entry.header ~= nil then cleared = false end
        if index > 1 and level[index - 1].level > entry.level then levelOrdered = false end
    end
    for index = 2, #name do
        if name[index - 1].title:lower() > name[index].title:lower() then nameOrdered = false end
    end
    CHECK(cleared, "K: flat modes clear the header a grouped mode set")
    CHECK(levelOrdered, "K: LEVEL ascending")
    CHECK(nameOrdered, "K: NAME alphabetical")
    EQ(#C.Group(nil, "GUIDE"), 0, "K: no view, empty list")

    -- NextUp: the Guide's to-do order, never Done or uncounted, no header writes
    local before = {}
    for _, entry in ipairs(view.entries) do before[entry.id] = entry.header end
    local nextUp = C.NextUp(view, 6, {})
    local nextIds = {}
    for _, entry in ipairs(nextUp) do nextIds[#nextIds + 1] = entry.id end
    CHECK(Same(nextIds, { 1001, 1002, 1005, 1006, 1022, 1003 }), "K: NextUp follows the Guide", table.concat(nextIds, ","))
    local untouched = true
    for _, entry in ipairs(view.entries) do if entry.header ~= before[entry.id] then untouched = false end end
    CHECK(untouched, "K: NextUp leaves entry.header alone")
    local allUp = C.NextUp(view, 100, {})
    local clean = true
    for _, entry in ipairs(allUp) do
        if entry.status == "DONE" or not C.IsCountedBucket(entry.status) then clean = false end
    end
    CHECK(clean and #allUp == 12, "K: NextUp never lists Done or uncounted quests", #allUp)
    EQ(C.NextUp(view, 2, { playerPos = { x = 95, y = 95 } })[2].id, 1002, "K: NextUp honours the count")
    EQ(#C.NextUp(nil), 0, "K: NextUp of nothing")
    CHECK(Same(Titles(C.Group(view, "BOGUS", {})), expected), "K: an unknown mode is the Guide")
end

do
    -- Chain titles are fold keys: collisions get distinct titles
    local facts = {
        Fact({ id = 1101, name = "Done", questLevel = 60 }), Fact({ id = 1102, name = "Next", preSingle = { 1101 } }),
        Fact({ id = 1111, name = "Same Name", questLevel = 61 }), Fact({ id = 1112, name = "X", preSingle = { 1111 } }),
        Fact({ id = 1121, name = "Same Name", questLevel = 62 }), Fact({ id = 1122, name = "Y", preSingle = { 1121 } }),
        Fact({ id = 1131, name = "All Extra", layer = "EXTRA" }), Fact({ id = 1132, name = "Z", layer = "EXTRA", preSingle = { 1131 } }),
    }
    local view = C.BuildZone(facts, Char(), {})
    local titles = Titles(C.Group(view, "CHAIN", {}))
    local uniq, dup = {}, false
    for _, t in ipairs(titles) do
        if uniq[t] then dup = true end
        uniq[t] = true
    end
    CHECK(not dup, "K: CHAIN header titles are unique", table.concat(titles, " | "))
    CHECK(Has(titles, "Done (1101)"), "K: a chain titled like a fixed group is renamed")
    CHECK(Has(titles, "Same Name") and Has(titles, "Same Name (1121)"), "K: a second chain with the same title is renamed")
    CHECK(not Has(titles, "All Extra"), "K: a chain with nothing counted gets no header")
    CHECK(Has(titles, "Also starting here"), "K: ...its quests fall to their own group")
end

-- ===========================================================================
-- L. Filters
-- ===========================================================================

do
    local function E(base, status) return { isHeader = false, base = base, status = status or base } end
    local cases = {
        { "ALL", E("MISSED"), true }, { "ALL", E("DONE"), true },
        { "OPEN", E("LOG"), true }, { "OPEN", E("AVAILABLE"), true }, { "OPEN", E("AVAILABLE", "IGNORED"), true },
        { "OPEN", E("AVAILABLE", "REPEATABLE"), true }, { "OPEN", E("LOCKED"), false }, { "OPEN", E("DONE"), false },
        { "LOCKED", E("LOCKED"), true }, { "LOCKED", E("RIVAL"), true }, { "LOCKED", E("RIVAL", "LOCKED"), true },
        { "LOCKED", E("AVAILABLE"), false },
        { "DONE", E("DONE"), true }, { "DONE", E("DONE", "OPTIONAL"), true }, { "DONE", E("LOG"), false },
        { "MISSED", E("MISSED"), true }, { "MISSED", E("LOCKED"), false },
        { "SOMETHING", E("MISSED"), true },
    }
    for _, case in ipairs(cases) do
        EQ(C.PassesFilter(case[2], case[1]), case[3],
            "L: " .. case[1] .. " on base " .. case[2].base .. "/" .. case[2].status)
    end
    EQ(C.PassesFilter({ isHeader = true }, "DONE"), true, "L: headers pass")
end

-- ===========================================================================
-- M. State words
-- ===========================================================================

do
    local char = Char({ level = 64, logInfo = { [1201] = { complete = true }, [1202] = { failed = true } } })
    local function W(fact, c) return Word(C.BuildZone({ Fact(fact) }, c or char, {}).entries[1]) end
    local cases = {
        { { id = 1200, state = "COMPLETED" }, "done", "good" },
        { { id = 1201, state = "QUEST_LOG" }, "ready", "good" },
        { { id = 1202, state = "QUEST_LOG" }, "failed", "bad" },
        { { id = 1203, state = "QUEST_LOG" }, "log", "open" },
        { { id = 1204, state = "AVAILABLE" }, "open", "open" },
        { { id = 1205, state = "LEVEL_TOO_LOW", requiredLevel = 66 }, "lv 66", "warn" },
        { { id = 1206, state = "NO_PREQUESTSINGLE", preSingle = { 1 } }, "chain", "warn" },
        { { id = 1207, state = "MISSING_REPUTATION", minRep = { 970, 3000 } }, "rep", "warn" },
        { { id = 1208, state = "PROFESSION_SKILL" }, "skill", "warn" },
        { { id = 1209, state = "EXCLUSIVE_IN_QUEST_LOG" }, "choice", "faint" },
        { { id = 1210, state = "SPELL_MISSING" }, "locked", "warn" },
        { { id = 1211, state = "LEVEL_TOO_HIGH" }, "missed", "bad" },
        { { id = 1213, state = "MISSING_DAILY", daily = true }, "daily", "faint" },
        { { id = 1214, state = "AVAILABLE", daily = true }, "today", "open" },
        { { id = 1215, state = "EVENT_INACTIVE", event = true }, "event", "faint" },
        { { id = 1216, state = "AVAILABLE", event = true }, "event", "open" },
        { { id = 1217, state = "AVAILABLE", hiddenOnMap = true }, "open", "open" },
        { { id = 1218, state = "LEVEL_TOO_LOW", requiredLevel = 67, layer = "EXTRA" }, "lv 67", "warn" },
        { { id = 1219, state = "QUEST_LOG", daily = true }, "log", "open" },
    }
    for _, case in ipairs(cases) do
        local word, colour = W(case[1])
        EQ(word, case[2], "M: word for " .. case[1].state .. " (" .. case[1].id .. ")")
        EQ(colour, case[3], "M: colour for " .. case[1].state .. " (" .. case[1].id .. ")")
        CHECK(#word <= 6, "M: '" .. word .. "' fits the 46px column")
    end
    local rivalWord = W({ id = 1212, state = "MISSING_REPUTATION", minRep = { ALDOR, 3000 } },
        Char({ rep = { [ALDOR] = -3500, [SCRYERS] = 5000 } }))
    EQ(rivalWord, "rival", "M: word for RIVAL")
    local ignoredWord, ignoredColour = W({ id = 1220, state = "COMPLETED" }, Char({ ignored = { [1220] = true } }))
    CHECK(ignoredWord == "done" and ignoredColour == "faint", "M: IGNORED shows the base word, faint")
    EQ((C.StateWord(nil)), "", "M: no entry, no word")
end

-- ===========================================================================
-- N. Reason sentences
-- ===========================================================================

do
    local names = {
        [1300] = "Report to Nazgrel", [1301] = "The Path of Glory", [1302] = "Allegiance to the Scryers",
        [1303] = "X", [1310] = "First Thing", [1311] = "Second Thing", [1312] = "Third Thing", [1313] = "Fourth Thing",
        [1314] = "Fifth Thing",
    }
    local zones = { [1300] = "Hellfire Peninsula", [1301] = "Terokkar Forest", [1310] = "Nagrand" }
    local function Z(facts, extra)
        extra = extra or {}
        extra.names = names
        extra.zones = zones
        extra.level = extra.level or 64
        local char = Char(extra)
        local view = C.BuildZone(facts, char, {})
        return view, char
    end
    local function R(fact, extra)
        local view, char = Z({ Fact(fact) }, extra)
        return Reason(view.byId[fact.id], char, view)
    end

    EQ(R({ id = 1400, state = "AVAILABLE" }), "Available now.", "N: available")
    EQ(R({ id = 1401, state = "AVAILABLE", startsHere = false, startZoneName = "Shattrath City" }),
        "Available now; it starts in Shattrath City.", "N: available, giver elsewhere")
    EQ(R({ id = 1402, state = "LEVEL_TOO_LOW", requiredLevel = 66 }, { level = 64 }), "Needs level 66.", "N: level only")
    EQ(R({ id = 1403, requiredLevel = 66, preSingle = { 1300 } }, { level = 64 }),
        "Needs level 66 and \"Report to Nazgrel\" (Hellfire Peninsula).", "N: level and an external prerequisite")
    local view, char = Z({ Fact({ id = 1300, name = "Report to Nazgrel", questLevel = 60 }),
        Fact({ id = 1404, requiredLevel = 66, preSingle = { 1300 } }) }, { level = 64 })
    EQ(Reason(view.byId[1404], char, view), "Needs level 66 and \"Report to Nazgrel\".", "N: level and an in-zone prerequisite")
    EQ(R({ id = 1405, state = "NO_PREQUESTSINGLE", preSingle = { 1301 } }),
        "Complete \"The Path of Glory\" first (Terokkar Forest).", "N: one external prerequisite")
    EQ(R({ id = 1406, preSingle = { 1310, 1311 } }), "Complete \"First Thing\" (Nagrand) or \"Second Thing\" first.", "N: any-of prerequisites")
    EQ(R({ id = 1407, preGroup = { 1310, 1311 } }), "Complete \"First Thing\" (Nagrand) and \"Second Thing\" first.", "N: all-of prerequisites")
    EQ(R({ id = 1408, preGroup = { 1310, 1311, 1312, 1313, 1314 } }),
        "Complete \"First Thing\" (Nagrand), \"Second Thing\", \"Third Thing\" and 2 more first.", "N: long lists are capped")
    EQ(R({ id = 1409, preGroup = { 1311 }, preSingle = { 1312, 1313 } }),
        "Complete \"Second Thing\" and one of \"Third Thing\" or \"Fourth Thing\" first.", "N: all-of plus any-of")
    EQ(R({ id = 1410, preSingle = { 1399 } }), "Complete \"quest 1399\" first.", "N: an unnamed prerequisite")
    EQ(R({ id = 1411, state = "MISSING_REPUTATION", minRep = { ALDOR, 3000 } }, { rep = { [ALDOR] = 500, [SCRYERS] = -500 } }),
        "Needs Friendly with The Aldor.", "N: reputation")
    EQ(R({ id = 1412, state = "MISSING_REPUTATION", minRep = { 999, 9000 } }), "Needs Honored with faction 999.", "N: unnamed faction")
    EQ(R({ id = 1413, state = "EXCEED_REPUTATION", maxRep = { 970, 3000 } }, { rep = { [970] = 4000 } }),
        "Only offered below Friendly with faction 970.", "N: reputation too high")
    EQ(R({ id = 1414, state = "PROFESSION_SKILL", skill = { 171, 300 } }, { skillName = function() return "Alchemy" end }),
        "Needs 300 Alchemy.", "N: profession skill with a name")
    EQ(R({ id = 1415, state = "PROFESSION_SKILL", skill = { 171, 300 } }), "Needs profession skill 300.", "N: profession skill, no name")
    EQ(R({ id = 1416, state = "PROFESSION_RANK" }), "Needs a higher profession rank.", "N: profession rank")
    EQ(R({ id = 1417, state = "PROFESSION_SKILL", skill = { 171, 300 }, requiredLevel = 66 }, { level = 64 }),
        "Needs profession skill 300 and level 66.", "N: profession leads, level follows")
    EQ(R({ id = 1418, state = "EXCLUSIVE_COMPLETED", exclusiveTo = { 1302 } }, { done = { [1302] = true } }),
        "You chose \"Allegiance to the Scryers\".", "N: chose the other")
    EQ(R({ id = 1419, state = "EXCLUSIVE_IN_QUEST_LOG", exclusiveTo = { 1302 } }, { log = { [1302] = true } }),
        "You are on \"Allegiance to the Scryers\"; only one of these can be taken.", "N: the other is in the log")
    EQ(R({ id = 1420, state = "NEXTQUESTINCHAIN_ACTIVE_OR_COMPLETED" }), "You are past this point in the chain.", "N: past in chain")
    EQ(R({ id = 1421, state = "BREADCRUMB_FOLLOWUP", breadcrumbFor = 1303 }), "You went straight to \"X\"; the breadcrumb is gone.", "N: breadcrumb")
    EQ(R({ id = 1422, state = "LEVEL_TOO_HIGH" }), "You have outlevelled it.", "N: outlevelled")
    EQ(R({ id = 1423, state = "MISSING_DAILY", daily = true }), "Not offered today.", "N: not today")
    EQ(R({ id = 1424, state = "EVENT_INACTIVE", event = true }), "Seasonal; the event is closed.", "N: event closed")
    EQ(R({ id = 1425, state = "AVAILABLE", event = true }), "Seasonal; the event is on now.", "N: event open")
    EQ(R({ id = 1426, state = "MISSING_REPUTATION", minRep = { ALDOR, 3000 } }, { rep = { [ALDOR] = -3500, [SCRYERS] = 5000 } }),
        "Gated on the faction you did not side with.", "N: rival")
    EQ(R({ id = 1426, state = "MISSING_REPUTATION", minRep = { ALDOR, 3000 } },
        { rep = { [ALDOR] = -3500, [SCRYERS] = 5000 }, opts = { countRival = true } }),
        "Gated on the faction you did not side with.", "N: counted rival")
    EQ(R({ id = 1427, state = "AVAILABLE" }, { ignored = { [1427] = true } }), "Ignored; not part of your 100%.", "N: ignored")
    EQ(R({ id = 1428, state = "COMPLETED" }), "Done.", "N: done")
    EQ(R({ id = 1429, state = "QUEST_LOG" }, { logInfo = { [1429] = { complete = true } } }), "Ready to turn in.", "N: ready")
    EQ(R({ id = 1430, state = "QUEST_LOG" }, { logInfo = { [1430] = { failed = true } } }), "Failed; abandon it and pick it up again.", "N: failed")
    EQ(R({ id = 1431, state = "QUEST_LOG" }), "In your quest log.", "N: in the log")
    EQ(R({ id = 1432, state = "BREADCRUMB_ACTIVE" }), "A breadcrumb to it is in your log; turn that in first.", "N: breadcrumb active")
    EQ(R({ id = 1433, state = "SPELL_MISSING" }), "Needs a spell you have not learned.", "N: spell")
    EQ(R({ id = 1434, state = "ARENA_RATING" }), "Needs a higher arena rating.", "N: arena rating")
    EQ(R({ id = 1435, state = "BLACKLISTED" }), "Removed from the game.", "N: removed")
    EQ(R({ id = 1436, state = "PARENT_INACTIVE", parent = 1437 }, { done = { [1437] = true } }),
        "Its parent quest is already done, so it is no longer offered.", "N: parent done")
    EQ(R({ id = 1438, state = "AVAILABLE", daily = true }), "Daily; not part of your 100%.", "N: daily offered")
    EQ(R({ id = 1439, state = "AVAILABLE", repeatable = true }), "Repeatable; not part of your 100%.", "N: repeatable")
    EQ(R({ id = 1440, state = "AVAILABLE", hiddenOnMap = true }), "Available now. Optional; not part of your 100%.", "N: optional")
    EQ(R({ id = 1441, state = "AVAILABLE", layer = "EXTRA" }),
        "Available now. Filed under another heading; not part of your 100%.", "N: extra")
    EQ(R({ id = 1442, state = "PROFESSION_MISSING" }), "Needs a profession or specialisation you do not have.", "N: profession missing")
    EQ(R({ id = 1443, state = "EXCEED_REPUTATION", oneWayRep = true, maxRep = { 970, 9000 } }),
        "Your reputation is past the point where it is offered.", "N: one-way rep past")

    -- One of N
    local trio = C.BuildZone(Trio({ "AVAILABLE", "AVAILABLE", "AVAILABLE" }), Char({ peers = TRIO_PEERS }), {})
    EQ(Reason(trio.byId[701], Char(), trio), "One of 3 choices; only one counts.", "N: one of three")
    EQ(Reason(trio.byId[703], Char(), trio), "Available now.", "N: the slot holder reads normally")
    EQ(C.Reason(nil), "", "N: no entry, no sentence")
end

-- ===========================================================================
-- Q. Gone prerequisites, Riding, the unpledged tie, same-title twins
-- ===========================================================================

do
    -- Netherstorm: "Assist Exarch Orelis" (outside, 795) is the only way into
    -- a chain here, and Questie's own verdict on it is permanent
    -- (EXCLUSIVE_COMPLETED). Questie reports the chain as NO_PREQUESTSINGLE,
    -- a temporary verdict; the engine must call the whole chain missed.
    local names = { [795] = "Assist Exarch Orelis" }
    local zones = { [795] = "Shattrath City" }
    local function Chain(gone)
        return C.BuildZone({
            Fact({ id = 790, name = "Distraction at Manaforge B'naar", state = "NO_PREQUESTSINGLE", preSingle = { 795 } }),
            Fact({ id = 791, name = "Measuring Warp Energies", state = "NO_PREQUESTSINGLE", preSingle = { 790 } }),
            Fact({ id = 792, name = "Naaru Technology", state = "NO_PREQUESTSINGLE", preSingle = { 791 } }),
            Fact({ id = 793, name = "Plain One", state = "AVAILABLE" }),
        }, Char({ names = names, zones = zones, gone = gone }), { name = "Netherstorm" })
    end
    local alive = Chain({})
    EQ(alive.totals.counted, 4, "Q: with the way in still open, the chain counts and is locked")
    local lost = Chain({ [795] = true })
    local head = lost.byId[790]
    CHECK(head.status == "MISSED" and head.reasonKey == "PREREQ_GONE" and head.counted == false,
        "Q: a quest whose only prerequisite is gone for good is missed", head.status)
    CHECK(lost.byId[791].status == "MISSED" and lost.byId[792].status == "MISSED",
        "Q: ...and the walk takes the whole chain behind it")
    EQ(lost.totals.counted, 1, "Q: so the zone can still reach 100%")
    EQ(Reason(head, Char({ names = names, zones = zones }), lost),
        "Needs \"Assist Exarch Orelis\" (Shattrath City), which you can no longer get.",
        "Q: the briefing names what was lost, and where")
    EQ(Reason(lost.byId[791], Char(), lost), "Needs \"Distraction at Manaforge B'naar\", which you can no longer get.",
        "Q: a follow-up names the missed quest in front of it")
    -- In view: Bloodmyst's 9761 needs 9760, which a choice made missed
    local inView = C.BuildZone({
        Fact({ id = 796, name = "Vindicator's Rest", state = "EXCLUSIVE_COMPLETED", exclusiveTo = { 797 } }),
        Fact({ id = 797, name = "Ending Their World", state = "COMPLETED" }),
        Fact({ id = 798, name = "Clearing the Way", state = "NO_PREQUESTSINGLE", preSingle = { 796 } }),
    }, Char({ done = { [797] = true } }), {})
    CHECK(inView.byId[798].reasonKey == "PREREQ_GONE" and not inView.byId[798].counted,
        "Q: a prerequisite missed in this very view counts as gone")
    EQ(inView.totals.pct, 1, "Q: ...and Bloodmyst's last quest no longer holds it at 98%")
    -- Any-of: one live option keeps it locked
    local anyOf = C.Classify(Fact({ id = 799, state = "NO_PREQUESTSINGLE", preSingle = { 795, 794 } }), Char())
    local anyView = C.BuildZone({ Fact({ id = 799, state = "NO_PREQUESTSINGLE", preSingle = { 795, 794 } }) },
        Char({ gone = { [795] = true } }), {})
    CHECK(anyOf.base == "LOCKED" and anyView.byId[799].status == "LOCKED" and anyView.byId[799].counted,
        "Q: an any-of prerequisite with one option still open stays locked")
    -- preGroup: a gone member that an exclusive alternative could still stand in for is not gone
    local stand = C.BuildZone({ Fact({ id = 789, state = "NO_PREQUESTGROUP", preGroup = { 795 } }) },
        Char({ gone = { [795] = true }, excl = { [795] = { 788 } } }), {})
    EQ(stand.byId[789].status, "LOCKED", "Q: a preGroup member with an exclusive stand-in is not called gone")
    local hard = C.BuildZone({ Fact({ id = 789, state = "NO_PREQUESTGROUP", preGroup = { 795 } }) },
        Char({ gone = { [795] = true } }), {})
    EQ(hard.byId[789].reasonKey, "PREREQ_GONE", "Q: ...without one it is")
end

do
    -- Riding is a skill every character can train; Questie keeps these quests
    -- in their zone. No skill line yet is a LOCK (counted), not a miss.
    local riding = C.Classify(Fact({ id = 1500, state = "PROFESSION_MISSING", skill = { 762, 225 }, requiredLevel = 70 }),
        Char({ level = 64 }))
    CHECK(riding.base == "LOCKED" and riding.lockKind == "PROFESSION" and riding.counted,
        "Q: a Riding quest without the skill is locked and counted", riding.base)
    CHECK(riding.lock.skill and riding.lock.skill[1] == 762 and riding.lock.skill[2] == 225 and riding.lock.level == 70,
        "Q: ...naming the skill and the level")
    local view = C.BuildZone({ Fact({ id = 1500, state = "PROFESSION_MISSING", skill = { 762, 225 }, requiredLevel = 70 }) },
        Char({ level = 64, skillName = function(id) return id == 762 and "Riding" or nil end }), {})
    EQ(Reason(view.byId[1500], Char({ level = 64, skillName = function(id) return id == 762 and "Riding" or nil end }), view),
        "Needs 225 Riding and level 70.", "Q: ...in words")
    local mining = C.Classify(Fact({ id = 1501, state = "PROFESSION_MISSING", skill = { 186, 300 } }), Char())
    EQ(mining.base, "MISSED", "Q: any other missing profession is still missed")

    -- Before the pledge both standings are level: the Aldor side counts, the
    -- Scryer side is the rival, so the pledge cannot pull a side out of the count
    local level = { [ALDOR] = 0, [SCRYERS] = 0 }
    local scryer = C.Classify(Fact({ id = 1510, state = "MISSING_REPUTATION", minRep = { SCRYERS, 3000 } }),
        Char({ rep = level }))
    local aldor = C.Classify(Fact({ id = 1511, state = "MISSING_REPUTATION", minRep = { ALDOR, 3000 } }),
        Char({ rep = level }))
    CHECK(scryer.base == "RIVAL" and scryer.rivalTie == true and not scryer.counted,
        "Q: unpledged, a Scryer-gated quest is the rival side", scryer.base)
    CHECK(aldor.base == "LOCKED" and aldor.counted and not aldor.rival, "Q: ...and an Aldor-gated one counts")
    local tieView = C.BuildZone({ Fact({ id = 1510, state = "MISSING_REPUTATION", minRep = { SCRYERS, 3000 } }) },
        Char({ rep = level }), {})
    EQ(Reason(tieView.byId[1510], Char(), tieView),
        "Until you side with the Aldor or the Scryers only one side's quests count, and this is the other side's.",
        "Q: ...and says why without claiming a side was taken")
    local pledgedAldor = C.Classify(Fact({ id = 1511, state = "MISSING_REPUTATION", minRep = { ALDOR, 3000 } }),
        Char({ rep = { [ALDOR] = 500, [SCRYERS] = -500 } }))
    CHECK(pledgedAldor.base == "LOCKED" and pledgedAldor.counted, "Q: after an Aldor pledge the same quest still counts")

    -- (review 2026-10-04, round 2) The tie holds for gates already MET at it:
    -- a {Scryers, Neutral} minimum (Synthesis of Power, open at 0/0) and a
    -- maximum on the Aldor (Strained Supplies) are the Scryer side's too, so
    -- an Aldor pledge moves nothing at all
    local function Tie(rep, states, opts)
        states = states or {}
        return C.BuildZone({
            Fact({ id = 1530, name = "Synthesis of Power", state = states[1530] or "AVAILABLE", minRep = { SCRYERS, 0 } }),
            Fact({ id = 1531, name = "A Cleansing Light", state = states[1531] or "AVAILABLE", minRep = { ALDOR, 0 } }),
            Fact({ id = 1532, name = "Strained Supplies", state = states[1532] or "EXCEED_REPUTATION", maxRep = { ALDOR, 0 } }),
            Fact({ id = 1533, name = "Voren'thal's Visions", state = states[1533] or "EXCEED_REPUTATION", maxRep = { SCRYERS, 0 } }),
            Fact({ id = 1534, name = "Firewing Signets", state = states[1534] or "NO_PREQUESTSINGLE", preSingle = { 1539 },
                minRep = { SCRYERS, 0 } }),
        }, Char({ rep = rep, opts = opts }), {})
    end
    local tie = Tie(level)
    CHECK(tie.byId[1530].base == "RIVAL" and tie.byId[1530].rivalTie and not tie.byId[1530].counted,
        "Q: at the tie an open Scryer Neutral quest is the other side's", tie.byId[1530].base)
    CHECK(tie.byId[1534].base == "RIVAL" and tie.byId[1534].rivalTie, "Q: ...and one waiting on the pledge too")
    CHECK(tie.byId[1531].base == "AVAILABLE" and tie.byId[1531].counted, "Q: ...an Aldor Neutral quest counts")
    CHECK(tie.byId[1532].base == "RIVAL" and tie.byId[1532].rivalTie, "Q: ...the maximum on the Aldor is the Scryers' quest")
    CHECK(tie.byId[1533].base == "LOCKED" and tie.byId[1533].counted, "Q: ...the maximum on the Scryers counts, locked")
    EQ(tie.totals.counted, 2, "Q: two count at the tie")
    local aldorStates = { [1530] = "MISSING_REPUTATION", [1531] = "AVAILABLE", [1532] = "EXCEED_REPUTATION",
        [1533] = "AVAILABLE", [1534] = "NO_PREQUESTSINGLE" }
    local afterAldor = Tie({ [ALDOR] = 3500, [SCRYERS] = -3850 }, aldorStates)
    EQ(afterAldor.totals.counted, tie.totals.counted, "Q: an Aldor pledge moves nothing")
    CHECK(afterAldor.byId[1530].base == "RIVAL" and not afterAldor.byId[1530].rivalTie,
        "Q: ...and the Scryer quest is now plainly the other side's")
    local scryerStates = { [1530] = "AVAILABLE", [1531] = "MISSING_REPUTATION", [1532] = "AVAILABLE",
        [1533] = "EXCEED_REPUTATION", [1534] = "NO_PREQUESTSINGLE" }
    local afterScryer = Tie({ [ALDOR] = -3850, [SCRYERS] = 3500 }, scryerStates)
    CHECK(afterScryer.byId[1530].counted and afterScryer.byId[1532].counted and afterScryer.byId[1534].counted
        and not afterScryer.byId[1531].counted and not afterScryer.byId[1533].counted,
        "Q: a Scryer pledge swaps the sets")
    local both = Tie(level, nil, { countRival = true })
    CHECK(both.byId[1530].base == "AVAILABLE" and both.byId[1530].status == "AVAILABLE" and both.byId[1530].counted,
        "Q: with both sides counted an open quest stays open, not a lock", both.byId[1530].status)
    EQ(both.totals.counted, 5, "Q: ...and all five count")

    -- A rival quest behind a prerequisite gone for good is missed, not the
    -- other side's: a standing can be ground back, a lost pledge cannot
    local scryerRep = { [ALDOR] = -3850, [SCRYERS] = 3500 }
    local function Zahlia(opts, gone)
        return C.BuildZone({
            Fact({ id = 1540, name = "A Cure for Zahlia", state = "MISSING_REPUTATION", minRep = { ALDOR, 3000 },
                preSingle = { 1541 } }),
            Fact({ id = 1542, name = "Restoring the Light", state = "NO_PREQUESTSINGLE", minRep = { ALDOR, 0 },
                preSingle = { 1540 } }),
        }, Char({ rep = scryerRep, opts = opts, gone = gone, names = { [1541] = "Allegiance to the Aldor" } }), {})
    end
    local open = Zahlia(nil, {})
    EQ(open.byId[1540].status, "RIVAL", "Q: with the pledge still to be had, it is the other side's")
    local lostPledge = Zahlia(nil, { [1541] = true })
    local zahlia = lostPledge.byId[1540]
    CHECK(zahlia.status == "MISSED" and zahlia.reasonKey == "PREREQ_GONE" and not zahlia.rival and not zahlia.counted,
        "Q: a rival quest behind a lost pledge is missed", zahlia.status)
    EQ(Reason(zahlia, Char({ names = { [1541] = "Allegiance to the Aldor" } }), lostPledge),
        "Needs \"Allegiance to the Aldor\", which you can no longer get.", "Q: ...and says why, not 'the faction you did not side with'")
    EQ(lostPledge.byId[1542].reasonKey, "PREREQ_GONE", "Q: ...and the chain behind it falls with it")
    local countBoth = Zahlia({ countRival = true }, { [1541] = true })
    CHECK(countBoth.byId[1540].status == "MISSED" and countBoth.byId[1542].status == "MISSED" and countBoth.totals.counted == 0,
        "Q: with both sides counted it is not counted for ever", countBoth.totals.counted)
    local countOpen = Zahlia({ countRival = true }, {})
    CHECK(countOpen.byId[1540].status == "LOCKED" and countOpen.byId[1540].counted,
        "Q: ...while the pledge can still be had it counts, locked")

    -- Twins: race or faction versions of one quest share a title
    local twin = C.BuildZone({ Fact({ id = 1520, name = "Oronu the Elder", state = "EXCLUSIVE_COMPLETED", exclusiveTo = { 1521 } }) },
        Char({ done = { [1521] = true }, names = { [1521] = "Oronu the Elder" }, zones = { [1521] = "Shattrath City" } }),
        { name = "Terokkar Forest" })
    EQ(Reason(twin.byId[1520], Char({ zones = { [1521] = "Shattrath City" } }), twin),
        "You did another version of this quest (Shattrath City).", "Q: a same-title choice is not named after itself")
    local twinHere = C.BuildZone({
        Fact({ id = 1522, name = "Call of Air", state = "EXCLUSIVE_COMPLETED", exclusiveTo = { 1523 } }),
        Fact({ id = 1523, name = "Call of Air", state = "COMPLETED" }) }, Char({ done = { [1523] = true } }), { name = "Bloodmyst" })
    EQ(Reason(twinHere.byId[1522], Char(), twinHere), "You did another version of this quest.",
        "Q: ...and needs no zone when the other version is here")
    local twinLog = C.BuildZone({ Fact({ id = 1524, name = "Sunfury Signets", state = "EXCLUSIVE_IN_QUEST_LOG", exclusiveTo = { 1525 } }) },
        Char({ log = { [1525] = true }, names = { [1525] = "Sunfury Signets" }, zones = { [1525] = "Netherstorm" } }),
        { name = "Shattrath City" })
    EQ(Reason(twinLog.byId[1524], Char({ zones = { [1525] = "Netherstorm" } }), twinLog),
        "Another version of this quest is in your log (Netherstorm); only one can be taken.",
        "Q: the in-log version says so too")
end

-- ===========================================================================
-- O. Standings
-- ===========================================================================

do
    local cases = {
        { -50000, "Hated" }, { -42000, "Hated" }, { -6001, "Hated" }, { -6000, "Hostile" }, { -3001, "Hostile" },
        { -3000, "Unfriendly" }, { -1, "Unfriendly" }, { 0, "Neutral" }, { 2999, "Neutral" }, { 3000, "Friendly" },
        { 8999, "Friendly" }, { 9000, "Honored" }, { 21000, "Revered" }, { 41999, "Revered" }, { 42000, "Exalted" },
    }
    for _, case in ipairs(cases) do EQ(C.StandingWord(case[1]), case[2], "O: standing at " .. case[1]) end
end

-- ===========================================================================
-- P. Glyphs and purity
-- ===========================================================================

CHECK(#glyphFails == 0, "P: no shape glyphs in any word or sentence", table.concat(glyphFails, " / "))
CHECK(#touched == 0, "P: the engine never read a global it was not given", table.concat(touched, ","))

do
    local handle = io.open(ENGINE, "r")
    local source = handle and handle:read("*a") or ""
    if handle then handle:close() end
    local code = {}
    for line in (source .. "\n"):gmatch("([^\n]*)\n") do
        code[#code + 1] = (line:gsub("%-%-.*$", ""))
    end
    code = table.concat(code, "\n")
    local banned = {
        { "C_Timer", "C_Timer" }, { "print%s*%(", "print" }, { "UnitLevel", "UnitLevel" },
        { "CreateFrame", "CreateFrame" }, { "QuestieDB", "QuestieDB" }, { "QuestieLoader", "QuestieLoader" },
        { "GetTime", "GetTime" }, { "%f[%w_]_G%f[^%w_]", "_G" },
    }
    for _, pair in ipairs(banned) do
        CHECK(not code:find(pair[1]), "P: engine code does not name " .. pair[2])
    end
    -- the 200-locals / 60-upvalues limits are enforced by luajit at load,
    -- which already happened above; this is the same check from the shell
end

-- ===========================================================================
-- Z. The real Q.BuildList / Q.Progress accept zone entries
-- ===========================================================================

do
    local modelEnv = setmetatable({ CommanderQuestLog = {} }, { __index = _G })
    local modelChunk, modelErr = loadfile(MODEL)
    CHECK(modelChunk ~= nil, "Z: CommanderQuestLogModel.lua loads", modelErr)
    local M
    if modelChunk then
        setfenv(modelChunk, modelEnv)
        local ok, err = pcall(modelChunk)
        CHECK(ok, "Z: the Model main chunk runs without the client", err)
        M = modelEnv.CommanderQuestLog
    end
    if M and M.BuildList and M.Progress then
        local view = C.BuildZone(RICH_FACTS, RichChar(), { areaId = 3483 })
        local guide = C.Group(view, "GUIDE", {})
        local okBuild, rows, shown = pcall(M.BuildList, guide, { sort = "LOG", collapsed = { ["Done"] = true } })
        CHECK(okBuild, "Z: BuildList takes a GUIDE list", rows)
        if okBuild then
            EQ(shown, #view.entries, "Z: BuildList counts every zone quest")
            local doneHeaderRow, doneRows = nil, 0
            for _, row in ipairs(rows) do
                if row.header and row.header.title == "Done" then doneHeaderRow = row end
                if row.entry and row.entry.header == "Done" then doneRows = doneRows + 1 end
            end
            CHECK(doneHeaderRow and doneHeaderRow.collapsed == true and doneHeaderRow.shownCount == 2,
                "Z: a folded group keeps its header row")
            EQ(doneRows, 0, "Z: ...and hides its quests")
        end
        local okSearch, searched, found = pcall(M.BuildList, guide, { sort = "LOG", search = "near" })
        CHECK(okSearch and found == 1, "Z: search walks zone entries (objectives = {})", found)
        local okHeaderSearch, _, foundByHeader = pcall(M.BuildList, guide, { sort = "LOG", search = "turn in" })
        CHECK(okHeaderSearch and foundByHeader == 1, "Z: by default search matches the header, as the Log's zone")
        -- ...which on the Zones tab is a status group, so the tab turns it off:
        -- "turn in" names no quest, and must not list the Turn in group
        local okNoHeader, _, foundNoHeader = pcall(M.BuildList, guide,
            { sort = "LOG", search = "turn in", matchHeader = false })
        CHECK(okNoHeader and foundNoHeader == 0, "Z: matchHeader = false keeps the search on the quests' own words",
            foundNoHeader)
        local okSort, _, sortedShown = pcall(M.BuildList, guide, { sort = "PROGRESS" })
        CHECK(okSort and sortedShown == #view.entries, "Z: the PROGRESS sort survives zone entries")
        local allZero = true
        for _, entry in ipairs(view.entries) do
            local okP, p = pcall(M.Progress, entry)
            if not (okP and p == 0) then allZero = false end
        end
        CHECK(allZero, "Z: Q.Progress answers 0 for every zone entry")
        if M.KeyFor then EQ(M.KeyFor(view.entries[1]), view.entries[1].key, "Z: Q.KeyFor agrees with entry.key") end
        -- A fold made in the Guide must not swallow rows in a flat list
        local flat = C.Group(view, "LEVEL", {})
        local okFlat, flatRows = pcall(M.BuildList, flat, { sort = "LOG", collapsed = { ["Done"] = true, ["Missed"] = true } })
        CHECK(okFlat and #flatRows == #view.entries, "Z: a flat list ignores Guide folds", okFlat and #flatRows or flatRows)
    end
end

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
