-- Commander Quest Log: reputation rules engine smoke test (luajit).
--
-- Loads CommanderQuestLogStanding.lua ALONE into a SEALED environment, as the
-- completion smoke does: reading any global the engine was not given raises,
-- so the run itself is the proof that the engine is pure. The generated data
-- file (CommanderQuestLogReputationData.lua) is loaded into an environment of
-- its own -- it must write exactly its one global and read none -- and is
-- handed to the engine as an argument, never as a global it could reach.
--
--   luajit standing_smoke.lua
--
-- Two kinds of check, kept apart on purpose:
--
--   * ENGINE checks run on the real factions table (bases, spill edges and
--     rates from the DB2) with a FIXTURE of quest tables (reward caps,
--     derived rows, overrides, item costs, rotating and conditional dailies)
--     written down here. They prove the rules -- truncation, the quest rate,
--     clamp-then-spill, the Sha'tar window, the rival loss, the ordered
--     projection -- whatever the generator emits for a given quest.
--   * DATA CONTRACT checks (section Q) run the same scenarios on the
--     generated quest tables and hold them to the facts the research
--     verified (critic W1's fifteen reward caps, the derived rows on 10326,
--     9266 and 4766, every override cited). A data file without those tables
--     (the scratch prototype) prints SKIPPED for Q and runs the rest.
--
-- Mutation hooks (the live files are never touched):
--
--   CQL_STANDING=/path/copy.lua  luajit .../standing_smoke.lua   # a mutated engine
--   CQL_REPDATA=/path/data.lua   luajit .../standing_smoke.lua   # another data file

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local ENGINE = os.getenv("CQL_STANDING") or (ADDONS .. "/Commander_QuestLog/CommanderQuestLogStanding.lua")
local DATAFILE = os.getenv("CQL_REPDATA") or (ADDONS .. "/Commander_QuestLog/CommanderQuestLogReputationData.lua")

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

local function Finish()
    io.write(string.format("%d checks, %d failures\n", checks, fails))
    os.exit(fails == 0 and 0 or 1)
end

-- Every string the engine produces passes through here: ASCII only, apart
-- from the middle dot and the em dash the module's prose allows (D11).
local glyphFails = {}
local function GlyphSafe(text, label)
    if type(text) ~= "string" then return text end
    local stripped = text:gsub("\194\183", ""):gsub("\226\128\148", "")
    if stripped:find("[\128-\255]") then glyphFails[#glyphFails + 1] = label .. ": " .. text end
    return text
end

-- ===========================================================================
-- A. Load the data and the engine, each into its own environment
-- ===========================================================================

local D
do
    local reads = {}
    local env = setmetatable({}, { __index = function(_, name) reads[#reads + 1] = name return nil end })
    local chunk, err = loadfile(DATAFILE)
    CHECK(chunk ~= nil, "A: the reputation data file loads", err)
    if not chunk then Finish() end
    setfenv(chunk, env)
    local ok, runErr = pcall(chunk)
    CHECK(ok, "A: the data main chunk runs with nothing but itself", runErr)
    D = rawget(env, "CommanderQuestLogReputationData")
    CHECK(type(D) == "table", "A: the data file defines CommanderQuestLogReputationData")
    local written = {}
    for name in pairs(env) do written[#written + 1] = name end
    CHECK(#written == 1, "A: ...and writes no other global", table.concat(written, ","))
    CHECK(#reads == 0, "A: ...and reads none (pure data, no code)", table.concat(reads, ","))
    if type(D) ~= "table" then Finish() end
end

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

local R
do
    local chunk, err = loadfile(ENGINE)
    CHECK(chunk ~= nil, "A: the Standing engine loads", err)
    if not chunk then Finish() end
    setfenv(chunk, sealed)
    local ok, runErr = pcall(chunk)
    CHECK(ok, "A: the engine main chunk runs with no WoW globals and no data global", runErr)
    local Q = rawget(sealed, "CommanderQuestLog")
    CHECK(type(Q) == "table", "A: the engine creates CommanderQuestLog")
    R = Q and Q.Standing
    CHECK(type(R) == "table", "A: the engine publishes Q.Standing")
    if type(R) ~= "table" then Finish() end
    local newGlobals = {}
    for name in pairs(sealed) do
        if not ALLOWED[name] then newGlobals[#newGlobals + 1] = name end
    end
    CHECK(#newGlobals == 1 and newGlobals[1] == "CommanderQuestLog",
        "A: the only global the engine writes is CommanderQuestLog", table.concat(newGlobals, ","))
    for _, name in ipairs({ "Rank", "Base", "Multiplier", "QuestGain", "Effects", "Line", "Primary", "Project",
        "Repeatable", "Observe", "Observed", "StandingWord", "FormatRep", "FormatProgress" }) do
        CHECK(type(R[name]) == "function", "A: SPEC function R." .. name .. " exists")
    end
end

-- The fixture quest tables the engine checks run on, over the REAL factions.
-- Ids in the 90000s are synthetic and exist only here.
local function Overlay(base, extra)
    local out = {}
    for k, v in pairs(base) do out[k] = v end
    for k, v in pairs(extra or {}) do out[k] = v end
    return out
end

local FIX = {
    rules = { lowLevelQuestPenalty = false, diplomacy = 20599, wickerman = 24705, spillClamp = "capTop" },
    rewardCap = {
        [10326] = { [932] = 8999, [935] = 8999 }, [10327] = { [932] = 8999, [935] = 8999 },
        [10414] = { [934] = 8999, [935] = 8999 }, [10415] = { [934] = 8999, [935] = 8999 },
        [10870] = { [1015] = 0 }, [10871] = { [1015] = 0 },
    },
    derived = {
        [10326] = { 935 }, [10327] = { 935 }, [10415] = { 935 }, [10017] = { 935 },
        [9266] = { 21, 369, 470 }, [4766] = { 930 },
    },
    overrides = {
        [11354] = { [933] = 350, [946] = 350, [947] = 350, src = "https://www.wowhead.com/tbc/quest=11354" },
        [10871] = { [1015] = 38182, src = "https://www.wowhead.com/tbc/quest=10871" },
        [90001] = { [970] = 0, src = "fixture" },
        [90003] = { [941] = 1000, src = "fixture" },
        [90004] = { [933] = 250, src = "fixture" },
    },
    repeatCost = { [9784] = { 24401, 10 }, [10326] = { 29425, 10 }, [90002] = { 111, 2, 222, 3 } },
    rotating = {
        [11354] = "HEROIC", [11362] = "HEROIC", [11363] = "HEROIC", [11499] = "HEROIC",
        [11364] = "NORMAL", [11371] = "NORMAL", [11376] = "NORMAL",
    },
    conditional = { [11502] = "HALAA", [11503] = "HALAA" },
}
local TD = Overlay(D, FIX)

local HUMAN, ORC, DWARF, NIGHTELF, UNDEAD, TAUREN, GNOME, TROLL, BLOODELF, DRAENEI = 1, 2, 3, 4, 5, 6, 7, 8, 10, 11
local ALDOR, SCRYERS, SHATAR, CONSORTIUM, HONOR, THRALL = 932, 934, 935, 933, 946, 947
local SPORE, KURENAI, MAGHAR, NETHER, CE, LOWER = 970, 978, 941, 1015, 942, 1011

local function Fx(questId, rows, standings, pct, opts, data)
    return R.Effects(data or TD, questId, rows, standings or {}, pct or 100, opts)
end
local function Delta(effects, factionId)
    local entry = R.For(effects, factionId)
    return entry and entry.delta
end
local function Kind(effects, factionId)
    local entry = R.For(effects, factionId)
    return entry and entry.kind
end
local function Line(effects, names, opts)
    return GlyphSafe(R.Line(effects, names, opts), "line")
end
local function Contains(list, value)
    for _, v in ipairs(list or {}) do if v == value then return true end end
    return false
end

-- ===========================================================================
-- B. The data, as the engine reads it
-- ===========================================================================

do
    CHECK(type(D.thresholds) == "table" and #D.thresholds == 8, "B: the data carries eight thresholds")
    for i = 1, 8 do
        EQ(D.thresholds and D.thresholds[i], R.THRESHOLDS[i], "B: data threshold " .. i .. " matches the engine's")
    end
    EQ(D.bottom, R.BOTTOM, "B: the data's bottom is the engine's (-42000)")
    EQ(D.cap, R.CAP, "B: the data's cap is the engine's (42999)")
    local count, unnamed, nobase, badTarget = 0, {}, {}, {}
    for id, f in pairs(D.factions or {}) do
        count = count + 1
        if type(f.name) ~= "string" or f.name == "" then unnamed[#unnamed + 1] = id end
        if type(f.base) ~= "table" or #f.base == 0 then nobase[#nobase + 1] = id end
        for _, edge in ipairs(f.spill or {}) do
            if not D.factions[edge[1]] then badTarget[#badTarget + 1] = id .. ">" .. tostring(edge[1]) end
        end
    end
    EQ(count, 75, "B: 75 factions with a standing slot")
    EQ(#unnamed, 0, "B: every faction has a name")
    EQ(#nobase, 0, "B: every faction has base rows")
    EQ(#badTarget, 0, "B: every spill target is a faction")
    local aldor = D.factions[ALDOR] or {}
    local edges = {}
    for _, edge in ipairs(aldor.spill or {}) do edges[edge[1]] = edge end
    CHECK(edges[SCRYERS] and edges[SCRYERS][2] == -1.1 and edges[SCRYERS][3] == 7, "B: the Aldor spill -110% to the Scryers, to Exalted")
    CHECK(edges[SHATAR] and edges[SHATAR][2] == 0.5 and edges[SHATAR][3] == 4, "B: ...and +50% to the Sha'tar while Friendly or below")
    EQ(table.concat(R.Rivals(D, ALDOR), ","), "934", "B: R.Rivals reads the Aldor's rival from the negative edge")
    EQ(#R.Rivals(D, CE), 0, "B: ...and the Cenarion Expedition has none")
end

-- ===========================================================================
-- C. Ranks
-- ===========================================================================

do
    local cases = {
        { -50000, 0, -42000, -6000 }, { -42000, 0, -42000, -6000 }, { -6001, 0 }, { -6000, 1, -6000, -3000 },
        { -3001, 1 }, { -3000, 2 }, { -1, 2, -3000, 0 }, { 0, 3, 0, 3000 }, { 2999, 3 }, { 3000, 4, 3000, 9000 },
        { 8999, 4 }, { 9000, 5, 9000, 21000 }, { 20999, 5 }, { 21000, 6, 21000, 42000 }, { 41999, 6 },
        { 42000, 7, 42000, 43000 }, { 42999, 7 }, { 50000, 7, 42000, 43000 },
    }
    for _, case in ipairs(cases) do
        local rank, lo, hi = R.Rank(case[1])
        EQ(rank, case[2], "C: rank at " .. case[1])
        if case[3] then
            CHECK(lo == case[3] and hi == case[4], "C: the bar at " .. case[1] .. " runs " .. case[3] .. " to " .. case[4],
                tostring(lo) .. ".." .. tostring(hi))
        end
    end
    EQ(R.Rank(nil), nil, "C: no value, no rank")
    EQ(R.Rank("abc"), nil, "C: a word is not a value")
    EQ(R.Rank(0 / 0), nil, "C: NaN is not a value")
    EQ(R.RankTop(4), 8999, "C: the top of Friendly is 8999")
    EQ(R.RankTop(7), 42999, "C: the top of Exalted is the 42999 ceiling")
    EQ(R.RankTop(0), -6001, "C: the top of Hated is -6001")
    EQ(R.ToNext(8999), 1, "C: one point from Friendly to Honored")
    EQ(R.ToNext(42000), nil, "C: Exalted has no next rank")
    EQ(R.ToExalted(41000), 1000, "C: Exalted starts at 42000, not at the ceiling")
    EQ(R.ToExalted(42999), 0, "C: nothing left at the ceiling")
end

-- ===========================================================================
-- D. Starting standing (the first base row that fits)
-- ===========================================================================

do
    local Bit = R.Bit
    EQ(Bit(1), 1, "D: Bit(1) is 1")
    EQ(Bit(11), 1024, "D: Bit(11) is 1024 (Draenei, Druid)")
    EQ(Bit(0), nil, "D: there is no race 0")
    local function Base(f, race, class) return (R.Base(D, f, Bit(race), class and Bit(class) or nil)) end
    local cases = {
        { SPORE, HUMAN, -2500, "Sporeggar starts Unfriendly for everyone (human)" },
        { SPORE, BLOODELF, -2500, "...and for a blood elf" },
        { KURENAI, HUMAN, -1200, "Kurenai -1200 for the Alliance" },
        { KURENAI, DRAENEI, -1200, "...Draenei included" },
        { KURENAI, NIGHTELF, -1200, "...and a night elf" },
        { KURENAI, ORC, -42000, "Kurenai is Hated by the Horde (other side)" },
        { MAGHAR, ORC, -500, "Mag'har -500 for the Horde" },
        { MAGHAR, BLOODELF, -500, "...blood elves too" },
        { MAGHAR, HUMAN, -42000, "Mag'har is the other side for a human" },
        { NETHER, HUMAN, -42000, "Netherwing starts at the bottom" },
        { NETHER, TAUREN, -42000, "...for everyone" },
        { ALDOR, HUMAN, 0, "Aldor 0 for a human" },
        { SCRYERS, HUMAN, 0, "Scryers 0 for a human" },
        { ALDOR, DRAENEI, 3500, "Aldor +3500 for a draenei" },
        { SCRYERS, DRAENEI, -3500, "Scryers -3500 for a draenei" },
        { ALDOR, BLOODELF, -3500, "Aldor -3500 for a blood elf" },
        { SCRYERS, BLOODELF, 3500, "Scryers +3500 for a blood elf" },
        { ALDOR, ORC, 0, "Aldor 0 for an orc" },
        { 911, BLOODELF, 4000, "Silvermoon 4000 for a blood elf" },
        { 911, UNDEAD, 3100, "Silvermoon 3100 for the undead" },
        { 911, ORC, 400, "Silvermoon 400 for an orc" },
        { 911, TAUREN, 400, "...a tauren" },
        { 911, TROLL, 400, "...a troll" },
        { 911, HUMAN, -42000, "Silvermoon is the other side for a human" },
        { 930, DRAENEI, 4000, "Exodar 4000 for a draenei" },
        { 930, HUMAN, 3000, "Exodar 3000 for a human" },
        { 930, DWARF, 3000, "...a dwarf" },
        { 930, GNOME, 3000, "...a gnome" },
        { 930, ORC, -42000, "Exodar is the other side for an orc" },
        { HONOR, HUMAN, 0, "Honor Hold 0 for a human" },
        { HONOR, BLOODELF, -42000, "Honor Hold is the other side for a blood elf" },
        { THRALL, HUMAN, -42000, "Thrallmar is the other side for a human" },
        { THRALL, ORC, 0, "Thrallmar 0 for an orc" },
        { 922, BLOODELF, 0, "Tranquillien 0 for a blood elf" },
        { 922, DRAENEI, -42000, "Tranquillien is the other side for a draenei" },
        { CE, GNOME, 0, "the Cenarion Expedition starts Neutral" },
    }
    for _, case in ipairs(cases) do EQ(Base(case[1], case[2]), case[3], "D: " .. case[4]) end
    EQ(Base(609, NIGHTELF, 11), 2000, "D: a night elf druid starts Friendly-ish with the Cenarion Circle (class row)")
    EQ(Base(609, NIGHTELF, 1), 0, "D: ...a night elf warrior does not")
    local _, flags = R.Base(D, NETHER, Bit(HUMAN), Bit(1))
    EQ(flags, 2, "D: the second answer is the row's default flags (Netherwing at war, 0x02)")
    EQ(R.Base(D, 123456, Bit(HUMAN)), nil, "D: an unknown faction has no base")
    EQ(R.Base(D, ALDOR, 3), nil, "D: a raw race id that is not a bit answers nothing")
    EQ(R.Base(D, SPORE, nil, nil), -2500, "D: no race and class filter reads the first row")
    EQ(R.Side(D, Bit(HUMAN)), "Alliance", "D: a human is Alliance, from the data alone")
    EQ(R.Side(D, Bit(DRAENEI)), "Alliance", "D: a draenei is Alliance")
    EQ(R.Side(D, Bit(ORC)), "Horde", "D: an orc is Horde")
    EQ(R.Side(D, Bit(BLOODELF)), "Horde", "D: a blood elf is Horde")
    EQ(R.Side(D, 3), nil, "D: no side for a non-bit")
    for _, case in ipairs({ { DWARF, "Alliance" }, { NIGHTELF, "Alliance" }, { GNOME, "Alliance" },
        { UNDEAD, "Horde" }, { TAUREN, "Horde" }, { TROLL, "Horde" } }) do
        EQ(R.Side(D, Bit(case[1])), case[2], "D: race " .. case[1] .. " is " .. case[2])
    end
    local outOfRange = {}
    for factionId in pairs(D.factions) do
        for _, race in ipairs({ HUMAN, ORC, DWARF, NIGHTELF, UNDEAD, TAUREN, GNOME, TROLL, BLOODELF, DRAENEI }) do
            for class = 1, 11 do
                local base = R.Base(D, factionId, Bit(race), Bit(class))
                if type(base) ~= "number" or base < R.BOTTOM or base > R.CAP then
                    outOfRange[#outOfRange + 1] = factionId .. "/" .. race .. "/" .. class
                end
            end
        end
    end
    EQ(#outOfRange, 0, "D: every faction has a base on the bar for every race and class", table.concat(outOfRange, " "))
end

-- ===========================================================================
-- E. The multiplier and one turn-in
-- ===========================================================================

do
    EQ(R.Multiplier(nil), 100, "E: no modifiers is 100")
    EQ(R.Multiplier({}), 100, "E: an empty set is 100")
    EQ(R.Multiplier({ human = true }), 110, "E: Diplomacy is +10")
    EQ(R.Multiplier({ wickerman = true }), 110, "E: the Wickerman is +10")
    EQ(R.Multiplier({ human = true, wickerman = true }), 120, "E: the two add")
    EQ(R.Multiplier({ extra = 5 }), 105, "E: an extra aura adds its own")

    local function G(questId, f, raw, current, pct) return (R.QuestGain(TD, questId, f, raw, current, pct)) end
    EQ(G(nil, HONOR, 250, 0, 110), 275, "E: QuestGain(250, human) == 275")
    EQ(G(nil, HONOR, 250, 0, 100), 250, "E: 250 at 100 is 250")
    EQ(G(nil, HONOR, 25, 0, 110), 27, "E: a human's 25 is 27, truncated, not 27.5")
    EQ(G(nil, HONOR, 75, 0, 110), 82, "E: 75 is 82 (82.5 truncated)")
    EQ(G(nil, HONOR, 37, 0, 110), 40, "E: 37 is 40 (40.7 truncated)")
    EQ(G(nil, HONOR, 350, 0, 120), 420, "E: Diplomacy and the Wickerman: 350 is 420")
    EQ(G(nil, HONOR, 25, 0, 120), 30, "E: ...and 25 is 30")
    EQ(G(nil, 87, -500, 0, 110), -450, "E: a human loses 10% LESS (-500 is -450)")
    EQ(G(nil, 87, -500, 0, 100), -500, "E: a loss at 100 is the loss")
    EQ(G(nil, 87, -250, 0, 120), -200, "E: two modifiers shrink a loss by 20%")
    EQ(G(nil, 529, 250, 0, 100), 500, "E: the Argent Dawn's quest rate doubles (250 is 500)")
    EQ(G(nil, 529, 250, 0, 110), 550, "E: ...on top of Diplomacy (550)")
    EQ(G(nil, 609, 75, 0, 110), 165, "E: the Cenarion Circle doubles too (75 is 165)")
    EQ(G(nil, 576, 25, 0, 100), 50, "E: ...and Timbermaw Hold")
    EQ(G(10326, ALDOR, 250, 8900, 100), 99, "E: the mark turn-in stops at 8999 (+99 from 8900)")
    EQ(G(10326, ALDOR, 250, 8999, 100), 0, "E: ...and is worth nothing at 8999")
    EQ(G(10326, ALDOR, 250, 9500, 100), 0, "E: ...or above")
    EQ(G(10326, ALDOR, 250, 0, 100), 250, "E: ...and the full 250 below the clamp")
    local gain, capped, limit = R.QuestGain(TD, 10326, ALDOR, 250, 8900, 100)
    CHECK(gain == 99 and capped == true and limit == 8999, "E: QuestGain says it was clamped, and where",
        tostring(capped) .. " " .. tostring(limit))
    EQ(G(10870, NETHER, 42000, -42000, 100), 42000, "E: Ally of the Netherwing from the bottom is +42000")
    EQ(G(10870, NETHER, 42000, -1000, 100), 1000, "E: ...from -1000 only +1000 (lands on 0)")
    EQ(G(10870, NETHER, 42000, 0, 100), 0, "E: ...nothing from Neutral")
    EQ(G(10870, NETHER, 42000, 500, 100), 0, "E: ...nor above it")
    EQ(G(nil, HONOR, 250, 42900, 100), 99, "E: the 42999 ceiling clamps a gain")
    EQ(G(nil, HONOR, 250, 42999, 100), 0, "E: ...to nothing at the ceiling")
    EQ(G(nil, 87, -500, 42999, 100), 0, "E: the server zeroes even a loss once at the clamp")
    EQ(G(nil, HONOR, 0, 0, 110), 0, "E: a zero row is zero")
    EQ(G(nil, HONOR, nil, 0, 110), 0, "E: a missing row is zero")
    EQ(G(nil, HONOR, 250, 0, nil), 250, "E: no multiplier reads as 100")
    local levels = { quest = 60, player = 70 }
    EQ(G(nil, HONOR, 250, 0, 100), (R.QuestGain(TD, nil, HONOR, 250, 0, 100, levels)),
        "E: no low-level penalty while the rules flag is off (TBC 2.0.1)")
    local penal = Overlay(TD, { rules = { lowLevelQuestPenalty = true, spillClamp = "capTop" } })
    EQ((R.QuestGain(penal, nil, HONOR, 250, 0, 100, levels)), 50, "E: with the flag on, ten levels over floors at 20%")
    EQ((R.QuestGain(penal, nil, HONOR, 250, 0, 100, { quest = 60, player = 66 })), 200, "E: ...and one level over takes 20%")
end

-- ===========================================================================
-- F. Effects: the Aldor, the Scryers and the Sha'tar
-- ===========================================================================

local HUMAN_10326
do
    local fx = Fx(10326, { { ALDOR, 250 }, { SHATAR, 125 } }, { [ALDOR] = 0, [SCRYERS] = 0, [SHATAR] = 0 }, 110)
    HUMAN_10326 = fx
    EQ(#fx, 3, "F: a human's mark turn-in moves three factions")
    EQ(Delta(fx, ALDOR), 275, "F: Aldor +275")
    EQ(Delta(fx, SCRYERS), -302, "F: Scryers -302 (from the BOOSTED gain, not Questie's -275)")
    EQ(Delta(fx, SHATAR), 137, "F: Sha'tar +137 (spillover, truncated)")
    EQ(Kind(fx, ALDOR), "DIRECT", "F: the Aldor is the direct reward")
    EQ(Kind(fx, SCRYERS), "RIVAL", "F: the Scryers are the rival loss")
    EQ(Kind(fx, SHATAR), "SPILL", "F: the Sha'tar is spillover, not the stored row")
    CHECK(fx[1].factionId == ALDOR and fx[2].factionId == SCRYERS and fx[3].factionId == SHATAR,
        "F: DIRECT first, then by size")
    CHECK(fx[1][1] == ALDOR and fx[1][2] == 275, "F: entries are {factionId, delta} positionally too")
    CHECK(Contains(fx.dropped, SHATAR), "F: the stored Sha'tar row was dropped as derived")
    EQ(fx[1].raw, 250, "F: the entry keeps the raw value it was paid from")

    local plain = Fx(10326, { { ALDOR, 250 }, { SHATAR, 125 } }, {}, 100)
    CHECK(Delta(plain, ALDOR) == 250 and Delta(plain, SCRYERS) == -275 and Delta(plain, SHATAR) == 125,
        "F: at 100: +250 / -275 / +125")
    local single = Fx(10327, { { ALDOR, 25 }, { SHATAR, 12 } }, {}, 110)
    CHECK(Delta(single, ALDOR) == 27 and Delta(single, SCRYERS) == -29 and Delta(single, SHATAR) == 13,
        "F: a human's single mark: +27 / -29 / +13", Line(single))
    local scry = Fx(10415, { { SCRYERS, 250 }, { SHATAR, 125 } }, {}, 110)
    CHECK(Delta(scry, SCRYERS) == 275 and Delta(scry, ALDOR) == -302 and Delta(scry, SHATAR) == 137,
        "F: the Scryers' signets mirror it")
    local orc = Fx(10326, { { ALDOR, 250 }, { SHATAR, 125 } }, { [ALDOR] = 8900 }, 100)
    EQ(Delta(orc, ALDOR), 99, "F: an orc at Aldor 8900: +99")
    EQ(Delta(orc, SCRYERS), -108, "F: ...the Scryers -108 (spill from the CLAMPED gain)")
    EQ(Delta(orc, SHATAR), 49, "F: ...the Sha'tar +49")
    CHECK(R.For(orc, ALDOR).capped == true, "F: ...the Aldor is marked capped")
    EQ(GlyphSafe(R.For(orc, ALDOR).capNote, "note"), "this quest stops at 8,999", "F: ...with the clamp in words")
    CHECK(not R.For(orc, SCRYERS).capped and not R.For(orc, SHATAR).capped, "F: ...and the spills are not capped")
    local pledge = Fx(10551, { { ALDOR, 3500 } }, {}, 100)
    CHECK(Delta(pledge, ALDOR) == 3500 and Delta(pledge, SCRYERS) == -3850 and Delta(pledge, SHATAR) == 1750,
        "F: the pledge: Aldor +3500, Scryers -3850, Sha'tar +1750 (critic 3.8)", Line(pledge))
    local undeclared = Fx(90010, { { ALDOR, 250 }, { SHATAR, 125 } }, {}, 100)
    EQ(Delta(undeclared, SHATAR), 250, "F: a stored half the data does NOT call derived is paid as listed (no ids here)")
    EQ(Kind(undeclared, SHATAR), "DIRECT", "F: ...and reads as a direct reward")
end

-- ===========================================================================
-- G. Effects: clamps, the Sha'tar window, the ceiling and the bottom
-- ===========================================================================

do
    local rows = { { ALDOR, 250 }, { SHATAR, 125 } }
    local near = Fx(10326, rows, { [SHATAR] = 8990 }, 110)
    EQ(Delta(near, SHATAR), 9, "G: Sha'tar at 8990 takes +9: capTop stops spillover at 8999")
    CHECK(R.For(near, SHATAR).capped, "G: ...and it is marked capped")
    EQ(R.For(near, SHATAR).capNote, "spillover stops at 8,999", "G: ...with the reason")
    EQ(R.For(near, SHATAR).uncapped, 137, "G: ...and what it would have been")
    local top = Fx(10326, rows, { [SHATAR] = 8999 }, 110)
    EQ(Delta(top, SHATAR), 0, "G: at 8999 the spill is spent")
    EQ(R.For(top, SHATAR).capNote, "spillover stops at 8,999", "G: ...still inside the window, so the cap is the reason")
    EQ(Line(top), "+275 The Aldor  -302 The Scryers", "G: ...and a spill that moves nothing is not in the line")
    local past = Fx(10326, rows, { [SHATAR] = 9000 }, 110)
    EQ(Delta(past, SHATAR), 0, "G: Honored with the Sha'tar: no spillover")
    EQ(R.For(past, SHATAR).capNote, "no spillover above Friendly", "G: ...the window is shut, and it says so")
    CHECK(R.For(past, SHATAR).capped, "G: ...marked capped")
    EQ(Delta(past, SCRYERS), -302, "G: ...the rival still loses (its window runs to Exalted)")
    local mangos = Overlay(TD, { rules = { spillClamp = "mangos" } })
    local over = Fx(10326, rows, { [SHATAR] = 8990 }, 110, nil, mangos)
    EQ(Delta(over, SHATAR), 137, "G: under \"mangos\" the last spill overshoots (8990 to 9127)")
    CHECK(not R.For(over, SHATAR).capped, "G: ...uncapped")

    local net = Fx(10870, { { NETHER, 42000 } }, { [NETHER] = -42000 }, 100)
    EQ(Delta(net, NETHER), 42000, "G: Ally of the Netherwing from -42000: +42000, landing on 0")
    local netNeutral = Fx(10870, { { NETHER, 42000 } }, { [NETHER] = 0 }, 100)
    EQ(Delta(netNeutral, NETHER), 0, "G: ...worth nothing from Neutral")
    EQ(R.For(netNeutral, NETHER).capNote, "this quest stops at 0", "G: ...because it stops at 0")
    EQ(Line(netNeutral), "0 Netherwing (capped)", "G: ...and the line says so rather than \"No reputation\"")
    local human = Fx(10871, { { NETHER, 42000 } }, { [NETHER] = -42000 }, 110)
    EQ(Delta(human, NETHER), 42000, "G: the human copy (38182 audited, x1.1) also lands on 0, not +46200")
    CHECK(R.For(human, NETHER).overridden, "G: ...and is marked overridden")

    local ceiling = Fx(90020, { { HONOR, 250 } }, { [HONOR] = 42900 }, 100)
    EQ(Delta(ceiling, HONOR), 99, "G: 99 short of the ceiling, +99")
    EQ(R.For(ceiling, HONOR).capNote, "at the Exalted cap", "G: ...at the Exalted cap")
    EQ(Delta(Fx(90020, { { HONOR, 250 } }, { [HONOR] = 42999 }, 100), HONOR), 0, "G: nothing at the ceiling")
    EQ(Delta(Fx(90021, { { 87, -500 } }, { [87] = 42999 }, 100), 87), 0, "G: a loss at the ceiling is zeroed (server rule)")
    local bottom = Fx(90021, { { 87, -500 } }, { [87] = -41800 }, 100)
    EQ(Delta(bottom, 87), -200, "G: a loss stops at the bottom (-41800 to -42000)")
    EQ(R.For(bottom, 87).capNote, "at the bottom of Hated", "G: ...and says where")
    EQ(Delta(Fx(90021, { { 87, -500 } }, {}, 110), 87), -450, "G: a human's direct loss is 10% smaller")
    EQ(Delta(Fx(90021, { { 87, -500 } }, {}, 120), 87), -400, "G: ...20% with the Wickerman")
    local city = Fx(90022, { { 72, 250 } }, { [47] = 42990 }, 100)
    EQ(Delta(city, 47), 9, "G: a capital's spill clamps at the ceiling (Ironforge +9)")
    EQ(R.For(city, 47).capNote, "at the Exalted cap", "G: ...and says so")
    local labelled = Fx(10326, rows, { [SHATAR] = 9000 }, 110, { labels = { [5] = "Freundlich" } })
    EQ(R.For(labelled, SHATAR).capNote, "no spillover above Freundlich", "G: the notes take the client's standing labels")
end

-- ===========================================================================
-- H. Effects: derived rows, overrides, headers, sides, unknowns, observations
-- ===========================================================================

do
    local goblin = { { 21, 250 }, { 87, -500 }, { 369, 250 }, { 470, 250 }, { 577, 500 } }
    local amends = Fx(9266, goblin, {}, 110)
    EQ(#amends, 5, "H: Making Amends moves five factions, not eight")
    EQ(Delta(amends, 577), 550, "H: Everlook +550 (the reward)")
    EQ(Delta(amends, 87), -450, "H: Bloodsail -450 (a direct loss, shrunk by Diplomacy)")
    CHECK(Delta(amends, 21) == 275 and Delta(amends, 369) == 275 and Delta(amends, 470) == 275,
        "H: the three towns +275 each, as spillover of the boosted 550")
    EQ(Kind(amends, 21), "SPILL", "H: ...and they read as spillover")
    EQ(#amends.dropped, 3, "H: the three stored halves were dropped")
    local undeduped = Fx(9266, goblin, {}, 110, nil, Overlay(TD, { derived = {} }))
    EQ(Delta(undeduped, 21), 824, "H: without the derived list Booty Bay is paid its stored half AND three spills (275 + 137 + 137 + 275)")
    local mayara = Fx(4766, { { 72, 10 }, { 930, 2 } }, {}, 100)
    EQ(Delta(mayara, 72), 10, "H: Mayara Brightwing: Stormwind +10")
    EQ(Delta(mayara, 930), 2, "H: ...the Exodar +2 once (spillover), not 2 + 2")
    EQ(Kind(mayara, 930), "SPILL", "H: ...as spillover")
    CHECK(Delta(mayara, 47) == 2 and Delta(mayara, 54) == 2 and Delta(mayara, 69) == 2, "H: ...and the other capitals +2")

    local header = Fx(90030, { { 469, 75 } }, {}, 100)
    EQ(#header, 6, "H: a reward to the Alliance header moves it and its five children")
    EQ(Delta(header, 469), 75, "H: the header itself +75")
    CHECK(Delta(header, 47) == 75 and Delta(header, 54) == 75 and Delta(header, 69) == 75 and Delta(header, 72) == 75
        and Delta(header, 930) == 75, "H: each capital +75 (the header cascade, at each child's rate 1)")
    EQ(Kind(header, 72), "SPILL", "H: ...as spillover")
    EQ(Line(Fx(90030, { { 469, 75 } }, {}, 100, { side = "Horde" })), "No reputation",
        "H: the other side's header pays a Horde character nothing")
    local city = Fx(90022, { { 72, 250 } }, {}, 110)
    EQ(Delta(city, 72), 275, "H: a human's Stormwind quest: +275")
    CHECK(Delta(city, 47) == 68 and Delta(city, 930) == 68, "H: ...25% to each other capital, uncapped in 2.5.6 (68)")
    EQ(Delta(Fx(90022, { { 72, 250 } }, {}, 100), 54), 62, "H: 25% of 250 is 62 (62.5 truncated)")

    local wanted = { { CONSORTIUM, 350 } }
    local ally = Fx(11354, wanted, {}, 100, { side = "Alliance" })
    CHECK(Delta(ally, CONSORTIUM) == 350 and Delta(ally, HONOR) == 350, "H: the audited Wanted daily pays Honor Hold too")
    EQ(R.For(ally, THRALL), nil, "H: ...and not Thrallmar, for the Alliance")
    CHECK(R.For(ally, HONOR).overridden, "H: ...the added row is marked overridden")
    local horde = Fx(11354, wanted, {}, 100, { side = "Horde" })
    CHECK(Delta(horde, THRALL) == 350 and R.For(horde, HONOR) == nil, "H: ...Thrallmar for the Horde, not Honor Hold")
    EQ(#Fx(11354, wanted, {}, 100), 3, "H: with no side given, all three rows stand")
    local byRace = Fx(11354, wanted, {}, 100, { raceBit = R.Bit(ORC) })
    CHECK(Delta(byRace, THRALL) == 350 and R.For(byRace, HONOR) == nil, "H: a race bit finds the side itself")
    EQ(Delta(Fx(90003, { { MAGHAR, 2000 } }, {}, 100), MAGHAR), 1000, "H: an override replaces a value")
    EQ(Line(Fx(90001, { { SPORE, 750 } }, {}, 100)), "No reputation", "H: an override of 0 removes the row")
    EQ(Delta(Fx(90004, nil, {}, 100), CONSORTIUM), 250, "H: an override can add a row Questie lacks")

    local unknown = Fx(90031, { { 99999, 250 } }, {}, 100)
    EQ(#unknown, 0, "H: a faction with no standing slot pays nothing (the server drops it)")
    CHECK(Contains(unknown.dropped, 99999), "H: ...and is reported dropped")
    EQ(#Fx(90032, { { HONOR, 0 } }, {}, 100), 0, "H: a zero row is no effect")
    local blind = R.Effects(TD, 90033, { { HONOR, 250 } }, nil, 100)
    CHECK(Delta(blind, HONOR) == 250 and R.For(blind, HONOR).unknown == true, "H: an unreadable standing reads 0 and says unknown")
    local asFunction = R.Effects(TD, 10326, { { ALDOR, 250 } }, function(id) return ({ [ALDOR] = 8900 })[id] end, 100)
    EQ(Delta(asFunction, ALDOR), 99, "H: standings may be a function as well as a table")
    local pair = Fx(90005, { { SHATAR, 350 }, { CONSORTIUM, 500 } }, {}, 100)
    CHECK(pair[1].factionId == CONSORTIUM and pair[2].factionId == SHATAR, "H: two direct rewards sort by size")
    local small = Fx(10327, { { ALDOR, 25 } }, {}, 110)
    EQ(small[1].factionId, ALDOR, "H: the direct +27 leads even though the rival -29 is bigger")
    local bare = R.Effects(nil, 90034, { { HONOR, 250 } }, {}, 110)
    CHECK(#bare == 1 and Delta(bare, HONOR) == 275, "H: no data at all still pays the row (no spill, no clamp)")
    EQ(#R.Effects(TD, 90035, nil, {}, 100), 0, "H: no rows, no effects")

    -- calibration samples override the data for display
    local store = { [10326] = { [ALDOR] = { raw = 250 }, [SHATAR] = { raw = 250 } } }
    local seen = Fx(10326, { { ALDOR, 250 }, { SHATAR, 125 } }, {}, 110, { store = store })
    CHECK(Delta(seen, ALDOR) == 275 and R.For(seen, ALDOR).observed, "H: an observed direct value is used, and flagged")
    EQ(Delta(seen, SHATAR), 275, "H: an observed Sha'tar double payment is shown as seen (+275)")
    CHECK(R.For(seen, SHATAR).observed, "H: ...flagged observed")
    EQ(Delta(Fx(10326, { { ALDOR, 250 } }, { [SHATAR] = 8990 }, 110, { store = store }), SHATAR), 9,
        "H: ...and still held to the spill window")
    local spores = Fx(9742, { { SPORE, 750 } }, {}, 110, { store = { [9742] = { [SPORE] = { raw = 250 } } } })
    EQ(Delta(spores, SPORE), 275, "H: Sporeggar seen at 250 (not the listed 750): a human gets 275")
    local extra = Fx(90006, { { CE, 250 } }, {}, 100, { store = { [90006] = { [LOWER] = { raw = 500 } } } })
    EQ(Delta(extra, LOWER), 500, "H: a faction seen moving that no row names is added")
    CHECK(R.For(extra, LOWER).extra and R.For(extra, LOWER).observed, "H: ...flagged extra and observed")
end

-- ===========================================================================
-- I. Primary and For
-- ===========================================================================

do
    local f, d = R.Primary(HUMAN_10326)
    CHECK(f == ALDOR and d == 275, "I: the primary of a mark turn-in is the Aldor +275")
    EQ(R.Primary({ { SHATAR, 10, factionId = SHATAR, delta = 10, kind = "SPILL" } }), nil, "I: spillover alone has no primary")
    EQ((R.Primary(Fx(9266, { { 577, 250 }, { 87, -500 } }, {}, 110))), 577, "I: a +275 gain beats a bigger -450 loss")
    local capped = Fx(10326, { { ALDOR, 250 }, { HONOR, 10 } }, { [ALDOR] = 8999 }, 100)
    f, d = R.Primary(capped)
    CHECK(f == HONOR and d == 10, "I: a capped-to-zero reward loses to a real +10")
    EQ(R.Primary(nil), nil, "I: no effects, no primary")
    EQ(R.For(HUMAN_10326, SCRYERS).delta, -302, "I: For finds a faction's entry")
    EQ(R.For(HUMAN_10326, 1), nil, "I: ...and nil for one not moved")
    EQ(R.For(nil, ALDOR), nil, "I: ...and nil with no effects")
end

-- ===========================================================================
-- J. The line
-- ===========================================================================

do
    EQ(Line(HUMAN_10326), "+275 The Aldor  -302 The Scryers  +137 The Sha'tar", "J: the full line")
    EQ(Line(HUMAN_10326, nil, { compact = true }), "+275 Aldor -302 Scryers +137 Sha'tar", "J: the compact line")
    local hh = Fx(90020, { { HONOR, 250 } }, {}, 100)
    EQ(Line(hh), "+250 Honor Hold", "J: one faction")
    EQ(Line(hh, nil, { compact = true }), "+250 HH", "J: ...compact")
    EQ(Line({}), "No reputation", "J: nothing reads \"No reputation\"")
    EQ(Line(nil), "No reputation", "J: ...so does no table")
    EQ(Line({}, nil, { none = "None" }), "None", "J: the empty text can be replaced")
    local orc = Fx(10326, { { ALDOR, 250 } }, { [ALDOR] = 8900 }, 100)
    EQ(Line(orc), "+99 The Aldor (capped)  -108 The Scryers  +49 The Sha'tar", "J: a clamped reward is marked")
    EQ(Line(orc, nil, { compact = true }), "+99 Aldor -108 Scryers +49 Sha'tar", "J: ...not in the compact form")
    EQ(Line(orc, nil, { marks = false }), "+99 The Aldor  -108 The Scryers  +49 The Sha'tar", "J: marks can be turned off")
    EQ(Line(Fx(10326, { { ALDOR, 250 } }, { [ALDOR] = 8999 }, 100)), "0 The Aldor (capped)",
        "J: a reward capped to nothing shows as 0, never as \"No reputation\"")
    EQ(Line(HUMAN_10326, nil, { max = 1 }), "+275 The Aldor  and 2 more", "J: max keeps the first and counts the rest")
    EQ(Line(HUMAN_10326, nil, { max = 2 }), "+275 The Aldor  -302 The Scryers  and 1 more", "J: ...max 2")
    EQ(Line(HUMAN_10326, nil, { max = 5 }), "+275 The Aldor  -302 The Scryers  +137 The Sha'tar", "J: ...room for all")
    local deDE = { [ALDOR] = "Die Aldor", [SCRYERS] = "Die Seher", [SHATAR] = "Die Sha'tar" }
    EQ(Line(HUMAN_10326, function(id) return deDE[id] end), "+275 Die Aldor  -302 Die Seher  +137 Die Sha'tar",
        "J: names come from the caller (a function)")
    EQ(Line(HUMAN_10326, { [ALDOR] = "Aldor" }), "+275 Aldor  -302 The Scryers  +137 The Sha'tar",
        "J: ...or a table, falling back to the data's name")
    EQ(Line(R.Effects(nil, 1, { { HONOR, 250 } }, {}, 100)), "+250 faction 946", "J: no name anywhere reads \"faction N\"")
    local amends = Line(Fx(9266, { { 577, 500 }, { 87, -500 } }, {}, 100), nil, { compact = true })
    local shorts, clash = {}, false
    for short in amends:gmatch("[%+%-]%d+ (%S+)") do
        if shorts[short] then clash = true end
        shorts[short] = true
    end
    CHECK(not clash, "J: a compact line never gives two factions one abbreviation", amends)
    CHECK(amends:find(" BB ") or amends:find(" BB$"), "J: ...Bloodsail Buccaneers keeps BB", amends)
    CHECK(amends:find(" Booty ") or amends:find(" Booty$"), "J: ...and Booty Bay takes its first word", amends)
    EQ(Line(hh, nil, { compact = true, abbrev = { [HONOR] = "Hold" } }), "+250 Hold", "J: an abbreviation table is used")
    EQ(Line(hh, nil, { compact = true, abbrev = function() return "H" end }), "+250 H", "J: ...or a function")
end

-- ===========================================================================
-- K. Abbreviations
-- ===========================================================================

local function ValidUtf8(text)
    local i, n = 1, #text
    while i <= n do
        local c = text:byte(i)
        local len = c < 0x80 and 1 or (c >= 0xF0 and 4) or (c >= 0xE0 and 3) or (c >= 0xC2 and 2) or 0
        if len == 0 or i + len - 1 > n then return false end
        for j = i + 1, i + len - 1 do
            local cc = text:byte(j)
            if cc < 0x80 or cc > 0xBF then return false end
        end
        i = i + len
    end
    return true
end

do
    local cases = {
        { "Honor Hold", "HH" }, { "Cenarion Expedition", "CE" }, { "Keepers of Time", "KoT" },
        { "The Scale of the Sands", "SotS" }, { "The Consortium", "Cons" }, { "Lower City", "LC" },
        { "The Sha'tar", "Sha'tar" }, { "Shattered Sun Offensive", "SSO" }, { "The Violet Eye", "VE" },
        { "Netherwing", "Neth" }, { "Sha'tari Skyguard", "SS" }, { "Ashtongue Deathsworn", "AD" },
        { "Ogri'la", "Ogri'la" }, { "Kurenai", "Kurenai" }, { "Thrallmar", "Thrall" }, { "Tranquillien", "Tranq" },
        { "The Aldor", "Aldor" }, { "The Scryers", "Scryers" }, { "Sporeggar", "Spore" }, { "The Mag'har", "Mag'har" },
        { "Silvermoon City", "SC" }, { "Exodar", "Exodar" }, { "Expedition des Cenarius", "EdC" },
    }
    for _, case in ipairs(cases) do EQ(R.Abbrev(case[1]), case[2], "K: " .. case[1] .. " is " .. case[2]) end
    EQ(R.Abbrev(nil), nil, "K: no name, no abbreviation")
    EQ(R.Abbrev(""), nil, "K: an empty name, none")
    local long = R.Abbrev("\195\132ltestenratsbund")
    CHECK(ValidUtf8(long) and long == "\195\132ltes", "K: a long word keeps five whole characters, never half of one", long)
    local korean = R.Abbrev("\236\149\140\235\143\132\235\165\180 \236\130\172\236\160\156\237\154\140")
    CHECK(ValidUtf8(korean) and korean == "\236\149\140\236\130\172", "K: initials of a two-word Korean name are whole characters")

    -- the whole table, in the picker's order (TBC first), is unique
    local names, order = {}, {}
    for id, f in pairs(D.factions) do names[id] = f.name end
    for _, group in ipairs(D.groups or {}) do
        for _, id in ipairs(group.ids or {}) do order[#order + 1] = id end
    end
    if #order == 0 then
        -- prototype data has no picker groups: the TBC factions, Outland and Shattrath first
        order = { 1012, 942, 933, 946, 978, 941, 1015, 1038, 970, 947, 932, 1011, 934, 935, 1031, 1077,
            930, 989, 990, 911, 922, 967 }
    end
    local table75 = R.AbbrevTable(names, order)
    local seen, dupes, count = {}, {}, 0
    for id, short in pairs(table75) do
        count = count + 1
        if seen[short] then dupes[#dupes + 1] = short .. "(" .. seen[short] .. "," .. id .. ")" end
        seen[short] = id
    end
    EQ(count, 75, "K: the table names every faction")
    EQ(#dupes, 0, "K: ...each with its own abbreviation", table.concat(dupes, " "))
    EQ(table75[1012], "AD", "K: Ashtongue (TBC, earlier in the picker) keeps AD")
    EQ(table75[529], "Argent", "K: ...the Argent Dawn takes its first word instead")
    EQ(table75[890], "Silver", "K: ...the Silverwing Sentinels six letters of theirs (the Skyguard keeps SS)")
    EQ(table75[1031], "SS", "K: the Skyguard keeps SS")
    local localesOk, localeFails = 0, {}
    for locale, list in pairs(D.names or {}) do
        local t = R.AbbrevTable(list)
        local used, bad = {}, false
        for _, short in pairs(t) do
            if used[short] or not ValidUtf8(short) then bad = true end
            used[short] = true
        end
        if bad then localeFails[#localeFails + 1] = locale else localesOk = localesOk + 1 end
    end
    EQ(#localeFails, 0, "K: every locale's names abbreviate uniquely into valid UTF-8", table.concat(localeFails, ","))
    CHECK(D.names == nil or localesOk > 0, "K: ...and there were locales to try")
end

-- ===========================================================================
-- L. Words and numbers
-- ===========================================================================

do
    local words = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
    for rank = 0, 7 do EQ(R.StandingWord(rank), words[rank + 1], "L: rank " .. rank .. " is " .. words[rank + 1]) end
    local female = { "Hassfrau", "Feindin", "Unfreundlich", "Neutral", "Freundlich", "Wohlwollend", "Respektvoll", "Ehrf\195\188rchtig" }
    EQ(R.StandingWord(7, female), "Ehrf\195\188rchtig", "L: localised labels by standingID (rank + 1)")
    EQ(R.StandingWord(4, { [1] = "x" }), "Friendly", "L: a missing label falls back to English")
    EQ(R.StandingWord(5, function(n) return "S" .. n end), "S6", "L: labels may be the client's GetText, as a function")
    EQ(R.StandingWord(8), nil, "L: no rank 8")
    EQ(R.StandingWord(-1), nil, "L: no rank -1")
    EQ(R.StandingWord(nil), nil, "L: an unknown standing has no word (never \"Neutral\")")
    EQ(R.WordFor(-1200), "Unfriendly", "L: an unmet Kurenai's base reads Unfriendly")
    EQ(R.WordFor(-42000), "Hated", "L: an unmet Netherwing's reads Hated")
    EQ(R.WordFor(nil), nil, "L: no value, no word")
    local numbers = {
        { 0, "0" }, { 999, "999" }, { 1000, "1,000" }, { 1250, "1,250" }, { 42000, "42,000" }, { 1000000, "1,000,000" },
        { -302, "-302" }, { -1250, "-1,250" }, { -42000, "-42,000" }, { 12.9, "12" },
    }
    for _, case in ipairs(numbers) do EQ(R.FormatNumber(case[1]), case[2], "L: FormatNumber(" .. case[1] .. ")") end
    EQ(R.FormatNumber(nil), nil, "L: FormatNumber(nil) is nil")
    local reps = { { 1250, "+1,250" }, { -302, "-302" }, { 0, "0" }, { 137.5, "+137" }, { -29.7, "-29" }, { 42000, "+42,000" } }
    for _, case in ipairs(reps) do EQ(R.FormatRep(case[1]), case[2], "L: FormatRep(" .. case[1] .. ")") end
    EQ(R.FormatRep(nil), nil, "L: FormatRep(nil) is nil")
    local progress = {
        { 4250, "Friendly 1,250 / 6,000" }, { 42999, "Exalted 999 / 1,000" }, { 50000, "Exalted 999 / 1,000" },
        { -42000, "Hated 0 / 36,000" }, { -2500, "Unfriendly 500 / 3,000" }, { 0, "Neutral 0 / 3,000" },
        { 8999, "Friendly 5,999 / 6,000" }, { 21000, "Revered 0 / 21,000" },
    }
    for _, case in ipairs(progress) do
        EQ(GlyphSafe(R.FormatProgress(case[1]), "progress"), case[2], "L: FormatProgress(" .. case[1] .. ")")
    end
    EQ(R.FormatProgress(nil), nil, "L: FormatProgress(nil) is nil")
    EQ(R.FormatProgress(4250, female), "Freundlich 1,250 / 6,000", "L: ...with the client's labels")
end

-- ===========================================================================
-- M. Repeatables
-- ===========================================================================

do
    local plant = R.Repeatable(TD, 9784, 250, 0, 100, 8999, CE)
    EQ(plant.perTurnIn, 250, "M: Identify Plant Parts: 250 a turn-in")
    EQ(plant.cap, 9000, "M: ...offered below 8999, so the last turn-in carries it to 9000 (Honored)")
    EQ(plant.toCap, 36, "M: ...36 turn-ins from Neutral 0")
    EQ(plant.toNext, 12, "M: ...12 to Friendly")
    CHECK(plant.next == 3000 and plant.nextRank == 4, "M: ...the next rank is Friendly at 3000")
    EQ(plant.toExalted, nil, "M: ...it cannot reach Exalted")
    CHECK(plant.costItem == 24401 and plant.costCount == 10, "M: ...10 Unidentified Plant Parts a turn-in")
    EQ(plant.costToCap, 360, "M: ...360 parts to its cap")
    EQ(plant.costToNext, 120, "M: ...120 to Friendly")
    CHECK(plant.open == true and plant.capped == false, "M: ...open and not capped")
    local late = R.Repeatable(TD, 9784, 250, 8800, 100, 8999, CE)
    CHECK(late.toCap == 1 and late.cap == 9050, "M: from 8800, one more turn-in, to 9050", late.cap)
    CHECK(late.toNext == 1 and late.nextRank == 5, "M: ...and that one makes Honored")
    local shut = R.Repeatable(TD, 9784, 250, 9000, 100, 8999, CE)
    CHECK(shut.open == false and shut.cap == 9000, "M: at 9000 it is no longer offered")
    local marks = R.Repeatable(TD, 10326, 250, 8900, 100, 9000, ALDOR)
    EQ(marks.nextGain, 99, "M: ten marks at 8900 give 99 (the reward clamp)")
    EQ(marks.perTurnIn, 250, "M: ...though a turn-in is 250")
    CHECK(marks.cap == 8999 and marks.toCap == 1, "M: ...and stop at 8999 after one")
    EQ(marks.toNext, nil, "M: ...Honored is out of their reach")
    EQ(marks.rewardCap, 8999, "M: ...the clamp is reported")
    local spent = R.Repeatable(TD, 10326, 250, 8999, 100, 9000, ALDOR)
    CHECK(spent.capped == true and spent.open == false and spent.nextGain == 0 and spent.toCap == 0,
        "M: at 8999 the marks are offered but worth nothing (capped)")
    local humanMarks = R.Repeatable(TD, 10326, 250, 0, 110, 9000, ALDOR)
    CHECK(humanMarks.perTurnIn == 275 and humanMarks.toNext == 11 and humanMarks.toCap == 33 and humanMarks.cap == 8999,
        "M: a human: 275 a turn-in, 11 to Friendly, 33 to the clamp")
    local armaments = R.Repeatable(TD, 9766, 75, 41000, 110, nil, CE)
    EQ(armaments.perTurnIn, 82, "M: Coilfang Armaments, a human: 82 a turn-in")
    CHECK(armaments.cap == 42999 and armaments.toCap == 25, "M: ...uncapped: 25 turn-ins to the ceiling from 41000")
    CHECK(armaments.toNext == 13 and armaments.toExalted == 13, "M: ...13 to Exalted")
    local crystals = R.Repeatable(TD, 9883, 250, 2900, 100, 3000, CONSORTIUM)
    CHECK(crystals.toCap == 1 and crystals.cap == 3150, "M: crystal fragments under 3000: one more, carrying to 3150")
    local catalogue = R.Repeatable(TD, 10972, 250, 5000, 100, { min = 9000 }, CONSORTIUM)
    EQ(catalogue.open, false, "M: a repeatable that needs Honored is shut at 5000")
    local opened = R.Repeatable(TD, 10972, 250, 9000, 100, { min = 9000 }, CONSORTIUM)
    CHECK(opened.open and opened.cap == 42999, "M: ...and open, to the ceiling, at 9000")
    EQ(R.Repeatable(TD, 90036, 25, 0, 100, nil, 529).perTurnIn, 50, "M: the Argent Dawn's rate doubles a repeatable")
    local multi = R.Repeatable(TD, 90002, 250, 0, 100, nil, CE)
    CHECK(multi.costs and #multi.costs == 2 and multi.costs[2][1] == 222 and multi.costs[2][2] == 3,
        "M: every item of a multi-item turn-in is reported")
    EQ(multi.costItem, 111, "M: ...the first is the headline")
    EQ(R.Repeatable(TD, 11354, 350, 0, 100, nil, CONSORTIUM).rotating, "HEROIC", "M: a rotating daily says which kind")
    EQ(R.Repeatable(TD, 11502, 500, 0, 100, nil, KURENAI).conditional, "HALAA", "M: a conditional one says so")
    local plain = R.Repeatable(TD, 9784, 250, 0, 100, 8999, CE)
    CHECK(plain.rotating == nil and plain.conditional == nil, "M: ...and an ordinary one is neither (nil, not false)")
    local loss = R.Repeatable(TD, 90037, -500, 0, 100, nil, 87)
    CHECK(loss.perTurnIn == -500 and loss.toCap == nil, "M: a loss is reported but never projected")
    EQ(R.Repeatable(TD, 9766, 75, 42500, 100, nil, CE).toExalted, 0, "M: nothing more to Exalted once there")
end

-- ===========================================================================
-- N. Rotating dailies and daily income
-- ===========================================================================

do
    local today = R.TodaysRotating(TD, { [11354] = true, [11362] = true })
    EQ(today.HEROIC, nil, "N: two heroic candidates left: today's is not known")
    today = R.TodaysRotating(TD, { [11354] = true, [11362] = true }, { exclude = { [11499] = true } })
    EQ(today.HEROIC, 11363, "N: with the phase-hidden one excluded, the last candidate is today's")
    today = R.TodaysRotating(TD, { [11364] = true, [11371] = true })
    EQ(today.NORMAL, 11376, "N: the normal pool settles the same way")
    local none = R.TodaysRotating(TD, {})
    CHECK(none.NORMAL == nil and none.HEROIC == nil, "N: nothing learned from an NPC, nothing known")
    EQ(R.TodaysRotating(TD, nil, { offered = { [11371] = true } }).NORMAL, 11371, "N: a daily seen offered settles it")
    EQ(R.TodaysRotating(TD, {}, { exclude = { [11354] = true, [11362] = true, [11499] = true } }).HEROIC, nil,
        "N: one candidate left by exclusion alone is not known: an NPC must have said no to something")
    EQ(R.TodaysRotating(TD, { [11354] = true, [11362] = true }, { exclude = function(id) return id == 11499 end }).HEROIC,
        11363, "N: exclude may be a function")

    local dailies = { { 11354, 350 }, { 11364, 250 }, { 11371, 250 }, { 11502, 500 }, { 90040, 250 } }
    local income = R.DailyIncome(TD, dailies, 100, { factionId = CONSORTIUM, today = { NORMAL = 11364 } })
    EQ(income.perDay, 500, "N: per day: the steady daily plus today's normal Wanted (250 + 250)")
    EQ(income.count, 2, "N: ...two dailies")
    CHECK(income.rotating.NORMAL and income.rotating.NORMAL.today == 11364, "N: ...today's normal pick is named")
    CHECK(income.rotating.HEROIC and income.rotating.HEROIC.known == false, "N: ...the heroic pick is unknown, so not counted")
    EQ(income.rotating.NORMAL.candidates, 2, "N: ...two normal candidates pay this faction")
    EQ(#income.conditional, 1, "N: the Halaa daily is listed as conditional")
    EQ(R.DailyIncome(TD, dailies, 110, { factionId = CONSORTIUM, today = { NORMAL = 11364 } }).perDay, 550,
        "N: a human's per-day income truncates each daily (275 + 275)")
    EQ(R.DailyIncome(TD, dailies, 100, { factionId = CONSORTIUM, today = { NORMAL = 11364 }, includeConditional = true }).perDay,
        1000, "N: counting the conditional one adds it")
    EQ(R.DailyIncome(TD, dailies, 100, { factionId = CONSORTIUM, today = { NORMAL = 11364 }, max = 1 }).perDay, 250,
        "N: the daily cap holds the total")
    local elsewhere = R.DailyIncome(TD, dailies, 100, { factionId = CONSORTIUM, today = { NORMAL = 11376 } })
    CHECK(elsewhere.perDay == 250 and elsewhere.rotating.NORMAL.elsewhere == true,
        "N: today's normal pays another faction: only the steady daily counts")
    EQ(R.DailyIncome(TD, dailies, 100, { factionId = CONSORTIUM }).perDay, 250,
        "N: rotating dailies are never summed as income when today's is unknown")

    -- from the standing now: the row's own clamp and the ceiling
    local fort = { { 90041, 150 } }
    EQ(R.DailyIncome(TD, fort, 110, { factionId = HONOR }).perDay, 165, "N: Hellfire Fortifications, a human: +165 a day")
    local capped = R.DailyIncome(TD, fort, 110, { factionId = HONOR, value = 42999 })
    CHECK(capped.perDay == 0 and capped.steady[1].gain == 0,
        "N: at Exalted 999 a daily pays nothing more, as its row says (was +165)", capped.perDay)
    EQ(R.DailyIncome(TD, fort, 110, { factionId = HONOR, value = 42900 }).perDay, 99, "N: ...99 short of the cap: +99")
    local two = R.DailyIncome(TD, { { 90041, 150 }, { 90042, 150 } }, 110, { factionId = HONOR, value = 42900 })
    EQ(two.perDay, 99, "N: ...and two of them still only fill the 99 left")
    local pool = R.DailyIncome(TD, dailies, 100, { factionId = CONSORTIUM, value = 42999 }).rotating.HEROIC
    EQ(pool and pool.best, 0, "N: a rotating pool's best turn-in at the cap is 0 too")
end

-- ===========================================================================
-- O. Projection: the best order, closing gates, the spill window, slots
-- ===========================================================================

local hintTexts = {}
local function Project(plan, start, pct, data)
    local res = R.Project(data or TD, plan, start, pct or 100)
    for _, text in ipairs(res.orderHints or {}) do hintTexts[#hintTexts + 1] = GlyphSafe(text, "hint") end
    return res
end

do
    local consortium = {
        factionId = CONSORTIUM,
        once = {
            { 9882, 250, 3000, name = "Stealing from Thieves" }, { 9914, 250, 2999, name = "A Head Full of Ivory" },
            { 90050, 1000 }, { 90051, 1500 }, { 90052, 250 },
        },
    }
    local p = Project(consortium, 0)
    EQ(p.reach, 3250, "O: the Consortium from 0: every quest counts (3250)")
    CHECK(p.order[1] == 9914 and p.order[2] == 9882, "O: ...the quests that close below 3000 go first, soonest first")
    EQ(#p.lockedOut, 0, "O: ...nothing locks out")
    EQ(#p.orderHints, 2, "O: ...two order hints")
    EQ(p.orderHints[1], 'Do "A Head Full of Ivory" before Friendly', "O: ...a gate under 2999 reads \"before Friendly\"")
    EQ(p.orderHints[2], 'Do "Stealing from Thieves" before Friendly', "O: ...and so does one under 3000")
    CHECK(p.rank == 4 and p.toExalted == 38750 and p.left == 3250, "O: rank, gap to Exalted and rep left are reported")
    local gained = 0
    for _, gain in pairs(p.gains or {}) do gained = gained + gain end
    CHECK(p.gains and p.gains[90051] == 1500 and p.gains[9914] == 250 and gained == p.left,
        "O: what each quest paid in that order is reported, and adds up to what is left")
    local mid = Project(consortium, 2000)
    CHECK(mid.reach == 5250 and #mid.lockedOut == 0, "O: from 2000 both gated quests still fit before the big ones (5250)")
    local late = Project(consortium, 2800)
    EQ(late.reach, 5800, "O: from 2800 one gated quest is lost (5800)")
    CHECK(#late.lockedOut == 1 and late.lockedOut[1] == 9882, "O: ...Stealing from Thieves closes behind the other")
    local gone = Project(consortium, 3100)
    CHECK(#gone.lockedOut == 2 and gone.reach == 5850, "O: from 3100 both are already gone")
    EQ(#gone.orderHints, 0, "O: ...and there is nothing left to warn about")

    local opening = Project({ factionId = CONSORTIUM, once = { { 90060, 500, nil, 3000 }, { 90061, 2500 }, { 90062, 100, nil, 20000 } } }, 1000)
    EQ(opening.reach, 4000, "O: a quest that needs Friendly counts once the others get there")
    CHECK(opening.order[1] == 90061 and opening.order[2] == 90060, "O: ...after them")
    CHECK(Contains(opening.unreached, 90062), "O: a quest needing Revered is out of reach and listed so")

    local window = { factionId = CONSORTIUM, once = { { 90070, 300, 9000, 3000 } } }
    for i = 0, 19 do window.once[#window.once + 1] = { 90100 + i, 500 } end
    local w = Project(window, 0)
    EQ(w.reach, 10300, "O: a quest open only between 3000 and 9000 is taken as soon as it opens")
    EQ(#w.lockedOut, 0, "O: ...not lost")
    EQ(w.orderHints[1], "Do quest 90070 before Honored", "O: ...and warned about (an unnamed quest reads by id)")
    local odd = Project({ factionId = CONSORTIUM, once = { { 90071, 100, 4500 }, { 90072, 9000 } } }, 0)
    EQ(odd.orderHints[1], "Do quest 90071 before Friendly 1,500", "O: a gate off a rank boundary names the point")

    -- the Sha'tar: spillover only while Friendly or below
    local function ShatarPlan(extra)
        local plan = {
            factionId = SHATAR,
            once = { { 90080, 500 }, { 90081, 1000 }, { 90082, 2500 }, { 90083, 4000 } },
            spillFrom = { { 10551, 3500, ALDOR } },
        }
        for i = 1, 10 do plan.spillFrom[#plan.spillFrom + 1] = { 90200 + i, 250, ALDOR } end
        for _, item in ipairs(extra or {}) do plan.spillFrom[#plan.spillFrom + 1] = item end
        return plan
    end
    local s = Project(ShatarPlan(), 0)
    EQ(s.reach, 11000, "O: the Sha'tar from 0: spillover first (3000), then 8000 direct = 11000, not 8999")
    CHECK(s.spillWindow and s.spillWindow.landed == 3000 and s.spillWindow.lost == 0, "O: ...all 3000 spill lands")
    CHECK(s.spillWindow and s.spillWindow.from == 0 and s.spillWindow["until"] == 8999, "O: ...the window runs 0 to 8999")
    EQ(s.spillWindow and s.spillWindow.source, ALDOR, "O: ...from the Aldor")
    local s7 = Project(ShatarPlan(), 7000)
    EQ(s7.reach, 16999, "O: from 7000 the spill stops at 8999 (16999)")
    CHECK(s7.spillWindow.landed == 1999 and s7.spillWindow.lost == 1001, "O: ...1999 lands, 1001 is lost")
    local overshoot = Project(ShatarPlan(), 7000, 100, Overlay(TD, { rules = { spillClamp = "mangos" } }))
    EQ(overshoot.reach, 18000, "O: under \"mangos\" the projection lets the last spill overshoot too (18000)")
    local s9 = Project(ShatarPlan(), 9000)
    CHECK(s9.reach == 17000 and s9.spillWindow.landed == 0, "O: Honored already: no spillover at all")
    local rivals = Project(ShatarPlan({ { 10552, 3500, SCRYERS } }), 0)
    CHECK(rivals.reach == 11000 and rivals.spillSource == ALDOR, "O: Aldor or Scryers is one choice: the better (Aldor) is projected")
    local scryers = Project({ factionId = SHATAR, once = {},
        spillFrom = { { 10551, 3500, ALDOR }, { 10552, 3500, SCRYERS }, { 90301, 1000, SCRYERS } } }, 0)
    CHECK(scryers.spillSource == SCRYERS and scryers.reach == 2250, "O: ...and the Scryers when they offer more (2250)")
    local pledges = Project({ factionId = SHATAR, once = {},
        spillFrom = { { 10551, 3500, ALDOR, slot = "pledge" }, { 10552, 3500, SCRYERS, slot = "pledge" },
            { 90301, 1000, SCRYERS } } }, 0)
    CHECK(pledges.spillSource == SCRYERS and pledges.reach == 2250 and pledges.spillWindow.landed == 2250,
        "O: the two pledges as one slot are weighed inside each side: the Scryers' own pledge counts for them (2250)",
        tostring(pledges.spillSource) .. " " .. tostring(pledges.reach))
    local lazy = Project({ factionId = SHATAR, once = { { 90090, 500, 9000 } }, spillFrom = { { 90400, 18000, ALDOR } } }, 0)
    EQ(lazy.reach, 9499, "O: a quest closing at 9000 waits until the spill has filled the window (9499, not 8999)")
    local chunks = { factionId = SHATAR, once = { { 90091, 500, 3000 } }, spillFrom = {} }
    for i = 1, 12 do chunks.spillFrom[i] = { 90500 + i, 500, ALDOR } end
    local c = Project(chunks, 0)
    CHECK(c.reach == 3500 and #c.lockedOut == 0, "O: a quest closing inside the window is slotted in before the spill shuts it")
    EQ(c.orderHints[1], "Do quest 90091 before Friendly", "O: ...and warned about")

    local slots = Project({ factionId = 967, once = { { 90600, 1000, slot = "ring" }, { 90601, 2000, slot = "ring" }, { 90602, 500 } } }, 0)
    EQ(slots.reach, 2500, "O: an exclusive choice counts once, the better member (2000 + 500)")
    CHECK(#slots.slotPeers == 1 and slots.slotPeers[1] == 90600, "O: ...the other member is reported as its peer")
    local positional = Project({ factionId = 967, once = { { 90603, 1000, nil, nil, "s" }, { 90604, 3000, nil, nil, "s" } } }, 0)
    EQ(positional.reach, 3000, "O: the slot can be given positionally too ({questId, raw, gateMax, gateMin, slot})")
    local closedBest = Project({ factionId = 967, once = { { 90610, 1000, slot = "s" }, { 90611, 2000, 100, slot = "s" } } }, 500)
    EQ(closedBest.reach, 1500, "O: when the better member is already shut, the open one is taken")
    local trunc = { factionId = HONOR, once = {} }
    for i = 1, 10 do trunc.once[i] = { 90700 + i, 25 } end
    EQ(Project(trunc, 0, 110).reach, 270, "O: ten 25s for a human are 270, truncated per turn-in, not 275")
    local nether = Project({ factionId = NETHER, once = { { 10870, 42000 }, { 90800, 5000 }, { 90801, 4325 } } }, -42000)
    EQ(nether.reach, 9325, "O: Netherwing from -42000: Ally lands on 0, the rest make 9325")
    EQ(nether.rank, 5, "O: ...Honored, not Exalted (critic W2)")
    EQ(nether.order[1], 10870, "O: ...the quest clamped at 0 goes first, or the others are wasted under it")
    local reps = Project({ factionId = CE, once = { { 90900, 2000 } }, repeatables = { { 9784, 250, 8999 } } }, 0)
    CHECK(reps.reach == 2000 and reps.repeatReach == 9000 and reps.repeatRank == 5,
        "O: repeatables carry on past the once-only quests (Identify Plant Parts to 9000)")
    local uncapped = Project({ factionId = CE, once = {}, repeatables = { { 9784, 250, 8999 }, { 9766, 75 } } }, 0)
    EQ(uncapped.repeatReach, 42999, "O: an uncapped repeatable reaches the ceiling")
    local chained = Project({ factionId = CONSORTIUM, once = {},
        repeatables = { { 10972, 250, nil, 9000 }, { 90950, 250, 9001 } } }, 5000)
    EQ(chained.repeatReach, 42999, "O: a repeatable that opens at Honored is reached through another one")
    local empty = Project({ factionId = HONOR }, 1234)
    CHECK(empty.reach == 1234 and empty.spillWindow == nil and #empty.lockedOut == 0 and empty.toExalted == 40766,
        "O: an empty plan stays where it started")
    local top = Project({ factionId = HONOR, once = { { 90960, 500 } } }, 42800)
    CHECK(top.reach == 42999 and top.toExalted == 0 and top.rank == 7, "O: the ceiling holds in a projection")
    EQ(Project({ factionId = HONOR, once = { { 90961, 250 }, { 90962, 250 } } }, 0, 110).reach, 550, "O: the multiplier applies per quest")
end

-- ===========================================================================
-- P. Calibration
-- ===========================================================================

do
    local store = {}
    local ok, raw = R.Observe(store, 10326, ALDOR, 275, 110, { kind = "DIRECT" })
    CHECK(ok == true and raw == 250, "P: a human's +275 is stored as the listed 250", tostring(raw))
    EQ(R.Observed(store, 10326, ALDOR), 250, "P: ...and read back")
    local _, shatar = R.Observe(store, 10326, SHATAR, 137, 110, { kind = "SPILL" })
    EQ(shatar, 125, "P: the Sha'tar's +137 normalises to 125 (a share of the boosted gain)")
    local _, rival = R.Observe(store, 10326, SCRYERS, -302, 110, { kind = "RIVAL" })
    EQ(rival, -275, "P: the Scryers' -302 normalises to -275")
    local cases = {
        { 27, 110, "DIRECT", 25 }, { 82, 110, "DIRECT", 75 }, { 40, 110, "DIRECT", 37 }, { -450, 110, "DIRECT", -500 },
        { 300, 120, "DIRECT", 250 }, { 250, 100, "DIRECT", 250 }, { -29, 110, "RIVAL", -27 }, { 13, 110, "SPILL", 12 },
    }
    for _, case in ipairs(cases) do
        local _, got = R.Observe({}, 1, 1, case[1], case[2], { kind = case[3] })
        EQ(got, case[4], "P: " .. case[3] .. " " .. case[1] .. " at " .. case[2] .. " normalises to " .. case[4])
    end
    local _, doubled = R.Observe({}, 1, 529, 550, 110, { kind = "DIRECT", rate = 2 })
    EQ(doubled, 250, "P: a doubled faction's sample is normalised by its rate too")

    local drops = {
        { { after = 42999 }, "ceiling", "the 42999 ceiling" }, { { ceiling = true }, "ceiling", "a ceiling flag" },
        { { after = -42000 }, "bottom", "the bottom" }, { { rewardClamp = true }, "reward clamp", "a reward clamp flag" },
        { { cap = 8999, after = 8999 }, "reward clamp", "landing on the quest's clamp" },
        { { spillCap = true }, "spill cap", "a spill cap" }, { { capped = true }, "capped", "any cap" },
    }
    for _, case in ipairs(drops) do
        local s = {}
        local okDrop, why = R.Observe(s, 10326, ALDOR, 99, 100, case[1])
        CHECK(okDrop == false and why == case[2], "P: a sample that hit " .. case[3] .. " is dropped", tostring(why))
        EQ(R.Observed(s, 10326, ALDOR), nil, "P: ...and nothing is stored for " .. case[3])
    end
    local okNil, whyNil = R.Observe({}, 10326, ALDOR, nil, 100)
    CHECK(okNil == false and whyNil == "incomplete", "P: no delta, no sample")
    local okStore = R.Observe(nil, 10326, ALDOR, 250, 100)
    EQ(okStore, false, "P: no store, no sample")
    local kept = R.Observe({}, 10326, ALDOR, 99, 100, { cap = 8999, after = 8000 })
    EQ(kept, true, "P: a sample under the clamp is kept")

    local s = {}
    R.Observe(s, 9742, SPORE, 250, 100)
    R.Observe(s, 9742, SPORE, 250, 100)
    CHECK(s[9742][SPORE].n == 2 and s[9742][SPORE].changed == nil, "P: agreeing samples count up")
    R.Observe(s, 9742, SPORE, 750, 100)
    CHECK(s[9742][SPORE].raw == 750 and s[9742][SPORE].changed == 1 and s[9742][SPORE].n == 3,
        "P: a different sample wins and is counted as a change")
    EQ(R.Observed(s, 1, 1), nil, "P: an unseen pair is nil")
    EQ(R.Observed(nil, 9742, SPORE), nil, "P: no store is nil")
    local quests, samples = R.ObservedCount(store)
    CHECK(quests == 1 and samples == 3, "P: the store counts one quest, three samples", quests .. "/" .. samples)

    -- normalising a computed delta gives back the listed value it came from
    local values = { 5, 10, 12, 15, 20, 25, 37, 60, 75, 125, 150, 175, 250, 350, 500, 1000, 3500 }
    for _, pct in ipairs({ 100, 110, 120 }) do
        local bad = {}
        for _, value in ipairs(values) do
            local delta = R.Trunc(value * pct / 100)
            local _, back = R.Observe({}, 1, 1, delta, pct, { kind = "DIRECT" })
            if back ~= value then bad[#bad + 1] = value .. ">" .. tostring(back) end
        end
        EQ(#bad, 0, "P: every listed value survives a round trip at " .. pct, table.concat(bad, " "))
    end
    -- and a store built from a turn-in reproduces that turn-in
    local learnt = {}
    for _, entry in ipairs(HUMAN_10326) do R.Observe(learnt, 10326, entry.factionId, entry.delta, 110, { kind = entry.kind }) end
    local again = Fx(10326, { { ALDOR, 250 }, { SHATAR, 125 } }, {}, 110, { store = learnt })
    CHECK(Delta(again, ALDOR) == 275 and Delta(again, SCRYERS) == -302 and Delta(again, SHATAR) == 137,
        "P: effects read from the samples a turn-in left are the same numbers")
    CHECK(R.For(again, ALDOR).observed and R.For(again, SCRYERS).observed and R.For(again, SHATAR).observed,
        "P: ...each flagged seen in game")
    local plainAgain = Fx(10326, { { ALDOR, 250 }, { SHATAR, 125 } }, {}, 100, { store = learnt })
    CHECK(Delta(plainAgain, ALDOR) == 250 and Delta(plainAgain, SCRYERS) == -275 and Delta(plainAgain, SHATAR) == 125,
        "P: ...and a sample taken with Diplomacy reads right without it")

    -- a move several of the quest's own rows made is a sum: never read
    -- back (2026-10-04 review: Durotar's quests doubled after one turn-in)
    local cutting = { { 76, 250 }, { 530, 250 } }
    local mixed = R.MixedSources(TD, 90990, cutting, "Horde")
    local ids = {}
    for factionId in pairs(mixed) do ids[#ids + 1] = factionId end
    table.sort(ids)
    EQ(table.concat(ids, ","), "68,76,81,530,911",
        "P: Orgrimmar and the Darkspear spill into each other; the other capitals are fed by both: all mixed")
    local predicted = Fx(90990, cutting, {}, 100, { side = "Horde" })
    CHECK(Delta(predicted, 76) == 312 and Delta(predicted, 530) == 312 and Delta(predicted, 68) == 124,
        "P: Orgrimmar +312 (its 250 and the Darkspear's 62), the Undercity +124 (62 from each)")
    local sums = {}
    for _, entry in ipairs(predicted) do R.Observe(sums, 90990, entry.factionId, entry.delta, 100, { kind = entry.kind }) end
    local reread = Fx(90990, cutting, {}, 100, { side = "Horde", store = sums })
    CHECK(Delta(reread, 76) == 312 and Delta(reread, 530) == 312 and Delta(reread, 68) == 124 and Delta(reread, 911) == 124,
        "P: the exact moves stored as samples read back as the same numbers, not doubled (624 / 248)",
        Delta(reread, 76) .. "/" .. Delta(reread, 68))
    CHECK(not R.For(reread, 76).observed and not R.For(reread, 68).observed, "P: ...and are not flagged seen in game")
    EQ(next(R.MixedSources(TD, 10326, { { ALDOR, 250 }, { SHATAR, 125 } })), nil,
        "P: one source (the Aldor; the stored Sha'tar half is derived): nothing mixed")
    local directKind = Fx(10326, { { ALDOR, 250 } }, {}, 110,
        { store = { [10326] = { [SHATAR] = { raw = 250, kind = "DIRECT" } } } })
    EQ(Delta(directKind, SHATAR), 137, "P: a spill never reads a sample stored as a DIRECT move")
    local own = { [10326] = { [ALDOR] = { raw = 250, kind = "DIRECT" }, [SHATAR] = { raw = 125, kind = "SPILL" } },
        [90990] = { [76] = { raw = 312, kind = "DIRECT" } } }
    EQ(R.ObservedFor(TD, own, 10326, ALDOR, { { ALDOR, 250 } }), 250, "P: ObservedFor: a direct sample is the faction's own")
    EQ(R.ObservedFor(TD, own, 10326, SHATAR, { { ALDOR, 250 } }), nil, "P: ...a spill share is not")
    EQ(R.ObservedFor(TD, own, 90990, 76, cutting, "Horde"), nil, "P: ...nor a mixed move")
end

-- ===========================================================================
-- Q. Data contract: the generated quest tables
-- ===========================================================================

local generated = type(D.rewardCap) == "table" and type(D.derived) == "table" and type(D.overrides) == "table"
    and type(D.repeatCost) == "table" and type(D.rotating) == "table" and type(D.conditional) == "table"
if not generated then
    io.write("Q SKIPPED: the data file carries no generated quest tables (prototype data)\n")
else
    local rules = D.rules or {}
    CHECK(rules.lowLevelQuestPenalty == false, "Q: no low-level quest penalty (TBC)")
    EQ(rules.diplomacy, 20599, "Q: Diplomacy is spell 20599")
    EQ(rules.wickerman, 24705, "Q: the Wickerman is aura 24705")
    EQ(rules.spillClamp, "capTop", "Q: spillover clamps at the top of its window")
    local caps = D.rewardCap
    CHECK(caps[10326] and caps[10326][ALDOR] == 8999 and caps[10326][SHATAR] == 8999, "Q: More Marks of Kil'jaeden stop at 8999")
    CHECK(caps[10327] and caps[10327][ALDOR] == 8999, "Q: ...the single mark too")
    CHECK(caps[10414] and caps[10414][SCRYERS] == 8999 and caps[10415] and caps[10415][SCRYERS] == 8999,
        "Q: the Firewing Signets stop at 8999")
    CHECK(caps[10870] and caps[10870][NETHER] == 0, "Q: Ally of the Netherwing stops at exactly 0")
    for _, id in ipairs({ 10419, 10421, 10654, 10655, 10827, 10828, 10658, 10659, 10822, 10823 }) do
        CHECK(caps[id] and caps[id][SHATAR] == 8999, "Q: " .. id .. " holds its Sha'tar row at 8999 (critic W1)")
    end
    local capQuests, badCap = 0, {}
    for questId, row in pairs(caps) do
        capQuests = capQuests + 1
        for factionId in pairs(row) do
            if not D.factions[factionId] then badCap[#badCap + 1] = questId .. ":" .. factionId end
        end
    end
    CHECK(capQuests >= 15, "Q: at least the fifteen reward-capped quests", capQuests)
    EQ(#badCap, 0, "Q: every capped faction exists")
    local function Has(list, value) return Contains(list, value) end
    CHECK(Has(D.derived[10326], SHATAR), "Q: 10326's stored Sha'tar row is derived")
    CHECK(Has(D.derived[10017], SHATAR), "Q: ...10017's too")
    CHECK(Has(D.derived[9266], 21) and Has(D.derived[9266], 369) and Has(D.derived[9266], 470) and #D.derived[9266] == 3,
        "Q: 9266's three goblin-town halves are derived")
    CHECK(Has(D.derived[4766], 930) and #D.derived[4766] == 1, "Q: 4766's Exodar 2 is derived")
    local badDerived = {}
    for questId, list in pairs(D.derived) do
        for _, factionId in ipairs(list) do
            if not D.factions[factionId] then badDerived[#badDerived + 1] = questId .. ":" .. factionId end
        end
    end
    EQ(#badDerived, 0, "Q: every derived faction exists")
    local uncited, badOverride, overrideCount = {}, {}, 0
    for questId, row in pairs(D.overrides) do
        overrideCount = overrideCount + 1
        if type(row.src) ~= "string" or not row.src:find("^https://") then uncited[#uncited + 1] = questId end
        for key in pairs(row) do
            if type(key) == "number" and not D.factions[key] then badOverride[#badOverride + 1] = questId .. ":" .. key end
        end
    end
    EQ(#uncited, 0, "Q: every override cites its page", table.concat(uncited, ","))
    EQ(#badOverride, 0, "Q: every overridden faction exists")
    CHECK(D.repeatCost[10326] and D.repeatCost[10326][1] == 29425 and D.repeatCost[10326][2] == 10,
        "Q: ten Marks of Kil'jaeden a turn-in")
    CHECK(D.repeatCost[10918] and D.repeatCost[10918][2] == 30, "Q: thirty Arakkoa Feathers")
    local oddCost = {}
    for questId, row in pairs(D.repeatCost) do
        if #row < 2 or #row % 2 ~= 0 then oddCost[#oddCost + 1] = questId end
    end
    EQ(#oddCost, 0, "Q: every cost is item/count pairs")
    local kinds, badKind = { NORMAL = 0, HEROIC = 0 }, 0
    for _, kind in pairs(D.rotating) do
        if kinds[kind] then kinds[kind] = kinds[kind] + 1 else badKind = badKind + 1 end
    end
    CHECK(badKind == 0 and kinds.NORMAL > 0 and kinds.HEROIC > 0, "Q: the rotating pools are NORMAL and HEROIC")
    EQ(D.rotating[11354], "HEROIC", "Q: Nazan's Riding Crop is a heroic Wanted")
    EQ(D.rotating[11364], "NORMAL", "Q: the Shattered Hand Centurions a normal one")
    CHECK(D.conditional[11502] == "HALAA" and D.conditional[11503] == "HALAA", "Q: the Halaa dailies are conditional")

    -- the same scenarios end to end on the generated tables
    local fx = R.Effects(D, 10326, { { ALDOR, 250 }, { SHATAR, 125 } }, {}, 110)
    EQ(Line(fx), "+275 The Aldor  -302 The Scryers  +137 The Sha'tar", "Q: a human's mark turn-in, end to end")
    local orc = R.Effects(D, 10326, { { ALDOR, 250 }, { SHATAR, 125 } }, { [ALDOR] = 8900 }, 100)
    CHECK(Delta(orc, ALDOR) == 99 and Delta(orc, SCRYERS) == -108 and Delta(orc, SHATAR) == 49, "Q: ...an orc at 8900: +99/-108/+49")
    EQ(Delta(R.Effects(D, 10326, { { ALDOR, 250 }, { SHATAR, 125 } }, { [SHATAR] = 8990 }, 110), SHATAR), 9,
        "Q: ...the Sha'tar stops at 8999")
    EQ(Delta(R.Effects(D, 10870, { { NETHER, 42000 } }, { [NETHER] = -42000 }, 100), NETHER), 42000,
        "Q: Ally of the Netherwing lands on 0")
    EQ(Delta(R.Effects(D, 10870, { { NETHER, 42000 } }, { [NETHER] = 0 }, 100), NETHER), 0, "Q: ...and is worth nothing after")
    EQ(Delta(R.Effects(D, 10871, { { NETHER, 42000 } }, { [NETHER] = -42000 }, 110), NETHER), 42000,
        "Q: the human copy lands on 0 too")
    local amends = R.Effects(D, 9266, { { 21, 250 }, { 87, -500 }, { 369, 250 }, { 470, 250 }, { 577, 500 } }, {}, 110)
    CHECK(Delta(amends, 21) == 275 and Delta(amends, 577) == 550 and #amends == 5, "Q: Making Amends pays each town once")
    EQ(Delta(R.Effects(D, 4766, { { 72, 10 }, { 930, 2 } }, {}, 100), 930), 2, "Q: Mayara Brightwing pays the Exodar once")
    local wanted = R.Effects(D, 11354, { { CONSORTIUM, 350 } }, {}, 100, { side = "Alliance" })
    CHECK(Delta(wanted, HONOR) == 350 and R.For(wanted, THRALL) == nil, "Q: the audited Wanted daily pays Honor Hold to the Alliance")
    -- Wowhead (TBC) and CMaNGOS agree against Questie (D38, 2026-10-04):
    -- on Questie's own rows the corrected numbers come out
    local five = { { 47, 250 }, { 54, 250 }, { 69, 250 }, { 72, 250 }, { 930, 250 } }
    EQ(Line(R.Effects(D, 10016, five, {}, 110, { side = "Alliance" })), "No reputation",
        "Q: Timber Worg Tails pays nothing (it showed +547 to each capital)")
    local horde = { { 68, 250 }, { 76, 250 }, { 81, 250 }, { 530, 250 }, { 911, 250 } }
    local water = R.Effects(D, 6804, horde, {}, 100, { side = "Horde" })
    CHECK(Delta(water, 67) == 250 and Delta(water, 76) == 250 and Delta(water, 911) == 250 and Kind(water, 76) == "SPILL",
        "Q: Poisoned Water: the Horde header's 250, passed on to each capital (it showed +498)")
    local mud = R.Effects(D, 11211, { { 68, 350 }, { 76, 350 }, { 81, 350 }, { 530, 350 }, { 911, 350 } }, {}, 100,
        { side = "Horde" })
    CHECK(Delta(mud, 369) == 10 and R.For(mud, 76) == nil and R.For(mud, 911) == nil,
        "Q: Help for Mudsprocket: Gadgetzan 10, no capital (it showed +698 each)")
    EQ(Line(R.Effects(D, 4267, { { 47, 350 }, { 54, 350 }, { 69, 350 }, { 369, 350 }, { 930, 350 } }, {}, 110,
        { side = "Alliance" })), "No reputation", "Q: Rise of the Silithid pays nothing")
    EQ(Delta(R.Effects(D, 5096, { { 68, 250 }, { 76, 75 }, { 81, 75 }, { 530, 75 }, { 911, 75 } }, {}, 100,
        { side = "Horde" }), 911), 62, "Q: Scarlet Diversions: Silvermoon +62 by spillover, not +191")
    local judgment = R.Effects(D, 7639, { { 47, 25 }, { 69, 25 }, { 72, 75 }, { 930, 25 } }, {}, 110, { side = "Alliance" })
    CHECK(Delta(judgment, 72) == 82 and Delta(judgment, 930) == 20, "Q: To Show Due Judgment: Stormwind +82, the Exodar +20")
    EQ(Delta(R.Effects(D, 7640, { { 47, 75 }, { 69, 75 }, { 72, 250 }, { 930, 75 } }, {}, 110, { side = "Alliance" }), 69),
        68, "Q: Exorcising Terrordale: Darnassus +68 by spillover, not +190")
    for _, id in ipairs({ 7781, 7782 }) do
        local lord = R.Effects(D, id, { { 47, 250 }, { 54, 500 }, { 69, 500 }, { 72, 500 } }, {}, 110, { side = "Alliance" })
        CHECK(#lord == 5 and Delta(lord, 930) == 1098 and Delta(lord, 47) == 1098,
            "Q: The Lord of Blackrock (" .. id .. "): five 500 rows, each 550 plus four 137 spills (the server's compounding)")
    end
    local badGroup = {}
    for _, group in ipairs(D.groups or {}) do
        for _, id in ipairs(group.ids or {}) do
            if not D.factions[id] then badGroup[#badGroup + 1] = id end
        end
    end
    CHECK(#(D.groups or {}) > 0 and #badGroup == 0, "Q: every picker group lists real factions")
end

-- ===========================================================================
-- Z. Glyphs, purity and code bans
-- ===========================================================================

do
    for _, entry in ipairs(HUMAN_10326) do GlyphSafe(entry.capNote, "note") end
    GlyphSafe(R.Line({}), "none")
    CHECK(#hintTexts > 0, "Z: the projection produced hints to inspect")
    CHECK(#glyphFails == 0, "Z: no shape glyphs in any line, note, hint or label", table.concat(glyphFails, " / "))
    CHECK(#touched == 0, "Z: the engine never read a global it was not given", table.concat(touched, ","))
    local handle = io.open(ENGINE, "r")
    local source = handle and handle:read("*a") or ""
    if handle then handle:close() end
    local code = {}
    for line in (source .. "\n"):gmatch("([^\n]*)\n") do
        code[#code + 1] = (line:gsub("%-%-.*$", ""))
    end
    code = table.concat(code, "\n")
    local banned = {
        { "C_Timer", "C_Timer" }, { "print%s*%(", "print" }, { "GetFactionInfo", "GetFactionInfo" },
        { "UnitRace", "UnitRace" }, { "UnitBuff", "UnitBuff" }, { "UnitAura", "UnitAura" }, { "UnitSex", "UnitSex" },
        { "GetText", "GetText" }, { "GetTime", "GetTime" }, { "CreateFrame", "CreateFrame" }, { "Questie", "Questie" },
        { "CommanderQuestLogReputationData", "the data global" }, { "%f[%w_]_G%f[^%w_]", "_G" },
        { "setmetatable", "setmetatable" }, { "pcall", "pcall" },
    }
    for _, pair in ipairs(banned) do
        CHECK(not code:find(pair[1]), "Z: engine code does not name " .. pair[2])
    end
end

Finish()
