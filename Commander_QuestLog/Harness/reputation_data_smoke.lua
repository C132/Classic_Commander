-- Commander Quest Log: reputation data smoke (luajit).
--
-- Loads the GENERATED CommanderQuestLogReputationData.lua alone into a SEALED
-- environment -- reading any global raises, and the only global it may write
-- is its own table -- so the run itself is the proof that the file is pure
-- data: a stray call to anything would be a read of a global, and an error.
-- Then it walks the table the way the rules engine (CommanderQuestLogStanding)
-- and the adapter will read it, and holds the generator to what it claimed:
--
--   A  the file is data: one global, no functions, no metatables
--   B  the scalars: build, bottom, cap, the eight rank thresholds, the rules
--   C  every faction: a name, a slot, a base row per fit, a known parent;
--      spill edges that land on real factions at sane rates; the starting
--      standings the design leans on, fitted here the way the client fits them
--   D  the picker groups: order, membership, no faction twice, no header
--   E  the localized names: only TBC factions, only where they differ
--   F  rewardCap: every RewMaxRepValue row (critic W1's fifteen quests) + 10871
--   G  derived: the spillover written into rows (10326, 9266, 4766) and not
--      the header coincidences (281, 7642)
--   H  repeatCost, I rotating, J conditional
--   K  overrides: every row cites its page; none was refused
--   L  the reconciliation the generator recorded: zero template mismatches
--
-- Rules that hold for every row (every faction, every override...) are one
-- check each, reporting how many rows broke them and the first; so the count
-- below does not move when the generator is re-run on new data.
--
--   /opt/homebrew/bin/luajit Commander_QuestLog/Harness/reputation_data_smoke.lua
--
-- Mutation hook (the copy lives anywhere; the live file is never touched):
--   CQL_REPDATA=/path/copy.lua luajit .../reputation_data_smoke.lua

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local DATA = os.getenv("CQL_REPDATA") or (ADDONS .. "/Commander_QuestLog/CommanderQuestLogReputationData.lua")

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

-- Per-row checks are batched: one check per rule however many rows the
-- data has, failing with the count and the first offender. The total then
-- stays the same when the generator is re-run on new data (the audit adding
-- overrides, a new dump), so the README count means something.
local function Batch(labels)
    local bad = {}
    for _, label in ipairs(labels) do bad[label] = { n = 0 } end
    local function ok(label, cond, who)
        local b = bad[label]
        if not b then error("unknown batch label " .. tostring(label), 2) end
        if not cond then
            b.n = b.n + 1
            if b.first == nil then b.first = tostring(who) end
        end
    end
    local function done()
        for _, label in ipairs(labels) do
            local b = bad[label]
            CHECK(b.n == 0, label, b.n > 0 and (b.n .. " offender(s), first " .. b.first) or nil)
        end
    end
    return ok, done
end

local function IsInt(v)
    return type(v) == "number" and v == math.floor(v)
end

local function Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function SetOf(list)
    local s = {}
    for _, v in ipairs(list or {}) do s[v] = true end
    return s
end

local function SameSet(list, want)
    if type(list) ~= "table" or #list ~= #want then return false end
    local s = SetOf(list)
    for _, v in ipairs(want) do
        if not s[v] then return false end
    end
    return true
end

-- ===========================================================================
-- A. Load into a sealed environment
-- ===========================================================================

local written = {}
local sealed = setmetatable({}, {
    __index = function(_, name)
        error("data read the global '" .. tostring(name) .. "'", 2)
    end,
    __newindex = function(_, name, value)
        written[#written + 1] = name
        rawset(written, name, value)
    end,
})

local chunk, loadErr = loadfile(DATA)
CHECK(chunk ~= nil, "A1 the data file compiles", loadErr)
if not chunk then
    io.write(string.format("%d checks, %d failures\n", checks, fails))
    os.exit(1)
end
setfenv(chunk, sealed)
local okRun, runErr = pcall(chunk)
CHECK(okRun, "A2 the main chunk runs with no globals to read", runErr)
EQ(#written, 1, "A3 it writes exactly one global")
EQ(written[1], "CommanderQuestLogReputationData", "A3 ...and that global is CommanderQuestLogReputationData")
local D = rawget(written, "CommanderQuestLogReputationData")
CHECK(type(D) == "table", "A4 the global is a table")
if type(D) ~= "table" then
    io.write(string.format("%d checks, %d failures\n", checks, fails))
    os.exit(1)
end

local badValues, metatables = {}, 0
local function Walk(t, path, seen)
    if seen[t] then return end
    seen[t] = true
    if getmetatable(t) ~= nil then metatables = metatables + 1 end
    for k, v in pairs(t) do
        local tk, tv = type(k), type(v)
        if tk ~= "string" and tk ~= "number" then badValues[#badValues + 1] = path .. " key " .. tk end
        if tv == "table" then
            Walk(v, path .. "." .. tostring(k), seen)
        elseif tv ~= "string" and tv ~= "number" and tv ~= "boolean" then
            badValues[#badValues + 1] = path .. "." .. tostring(k) .. " is a " .. tv
        end
    end
end
Walk(D, "D", {})
EQ(#badValues, 0, "A5 nothing in the tree but strings, numbers, booleans and tables")
EQ(metatables, 0, "A6 no table carries a metatable")

-- ===========================================================================
-- B. Scalars
-- ===========================================================================

EQ(D.build, "2.5.6.69795", "B1 build is the installed client's")
EQ(D.bottom, -42000, "B2 bottom")
EQ(D.cap, 42999, "B3 cap")
local WANT_T = { -42000, -6000, -3000, 0, 3000, 9000, 21000, 42000 }
CHECK(type(D.thresholds) == "table" and #D.thresholds == 8, "B4 eight thresholds", D.thresholds and #D.thresholds)
for i = 1, 8 do
    EQ(D.thresholds and D.thresholds[i], WANT_T[i], "B4 threshold of rank " .. (i - 1))
end
for i = 2, 8 do
    CHECK(D.thresholds[i] > D.thresholds[i - 1], "B5 thresholds rise", i)
end
EQ(D.cap - D.thresholds[8] + 1, 1000, "B6 Exalted is 1000 wide (42000..42999)")
CHECK(type(D.rules) == "table", "B7 rules present")
EQ(D.rules.lowLevelQuestPenalty, false, "B7 no low-level quest penalty in TBC")
EQ(D.rules.diplomacy, 20599, "B7 Diplomacy spell")
EQ(D.rules.wickerman, 24705, "B7 Invocation of the Wickerman aura")
EQ(D.rules.spillClamp, "capTop", "B7 spill clamps at the top of maxRankIn")
EQ(D.phaseHidden, nil, "B8 phaseHidden is computed at run time, never shipped")

-- ===========================================================================
-- C. Factions
-- ===========================================================================

local F = D.factions or {}
EQ(Count(F), 75, "C1 all 75 factions with a reputation slot")
local slots, parentsOf = {}, {}
local cOk, cDone = Batch({
    "C2 id is a positive integer", "C2 name non-empty and trimmed", "C2 slot 0..127", "C2 slot unique",
    "C3 parent is a faction", "C3 side is Alliance, Horde or none", "C3 header exactly when some faction names it parent",
    "C4 one to four base rows", "C4 base row is four integers", "C4 base value within the standing range",
    "C4 no empty row survives (an empty row fits everyone)",
    "C5 spill edge is { target, rate, maxRankIn }", "C5 spill target is another faction",
    "C5 spill rate non-zero, |rate| <= 1.1", "C5 maxRankIn is a rank", "C6 rate has quest, kill and spell",
})
for id, f in pairs(F) do
    local label = "faction " .. tostring(id)
    cOk("C2 id is a positive integer", IsInt(id) and id > 0, label)
    cOk("C2 name non-empty and trimmed",
        type(f.name) == "string" and f.name ~= "" and f.name == f.name:match("^%s*(.-)%s*$"), label)
    cOk("C2 slot 0..127", IsInt(f.idx) and f.idx >= 0 and f.idx < 128, label)
    cOk("C2 slot unique", not slots[f.idx], label .. " idx " .. tostring(f.idx))
    slots[f.idx] = id
    if f.parent ~= nil then
        cOk("C3 parent is a faction", F[f.parent] ~= nil, label)
        parentsOf[f.parent] = true
    end
    cOk("C3 side is Alliance, Horde or none", f.side == nil or f.side == "Alliance" or f.side == "Horde", label)
    cOk("C4 one to four base rows", type(f.base) == "table" and #f.base >= 1 and #f.base <= 4, label)
    for k, row in ipairs(type(f.base) == "table" and f.base or {}) do
        local rl = label .. " row " .. k
        local four = type(row) == "table" and #row == 4 and IsInt(row[1]) and IsInt(row[2]) and IsInt(row[3])
            and IsInt(row[4])
        cOk("C4 base row is four integers", four, rl)
        cOk("C4 base value within the standing range", four and row[3] >= D.bottom and row[3] <= D.cap, rl)
        cOk("C4 no empty row survives (an empty row fits everyone)",
            not (four and row[1] == 0 and row[2] == 0 and row[3] == 0 and row[4] == 0), rl)
    end
    for k, e in ipairs(type(f.spill) == "table" and f.spill or {}) do
        local el = label .. " edge " .. k
        cOk("C5 spill edge is { target, rate, maxRankIn }", type(e) == "table" and #e == 3, el)
        cOk("C5 spill target is another faction", type(e) == "table" and F[e[1]] ~= nil and e[1] ~= id, el)
        cOk("C5 spill rate non-zero, |rate| <= 1.1",
            type(e) == "table" and type(e[2]) == "number" and e[2] ~= 0 and math.abs(e[2]) <= 1.1, el)
        cOk("C5 maxRankIn is a rank", type(e) == "table" and IsInt(e[3]) and e[3] >= 0 and e[3] <= 7, el)
    end
    if f.rate ~= nil then
        cOk("C6 rate has quest, kill and spell", type(f.rate) == "table" and type(f.rate.quest) == "number"
            and type(f.rate.kill) == "number" and type(f.rate.spell) == "number", label)
    end
end
for id, f in pairs(F) do
    cOk("C3 header exactly when some faction names it parent", (f.header == true) == (parentsOf[id] == true),
        "faction " .. tostring(id))
end
cDone()

-- Spill edges as the design leans on them
local function Edge(src, dst)
    for _, e in ipairs((F[src] or {}).spill or {}) do
        if e[1] == dst then return e end
    end
end
local function EdgeIs(src, dst, rate, maxRank, label)
    local e = Edge(src, dst)
    CHECK(e ~= nil and math.abs(e[2] - rate) < 1e-6 and e[3] == maxRank, label,
        e and (e[2] .. "/" .. e[3]) or "no edge")
end
EdgeIs(932, 934, -1.1, 7, "C7 Aldor -> Scryers -110%, any rank")
EdgeIs(932, 935, 0.5, 4, "C7 Aldor -> Sha'tar +50% while Friendly or lower")
EdgeIs(934, 932, -1.1, 7, "C7 Scryers -> Aldor -110%")
EdgeIs(934, 935, 0.5, 4, "C7 Scryers -> Sha'tar +50% while Friendly or lower")
EQ(#(F[932].spill or {}), 2, "C7 Aldor spills to exactly two")
-- critic W4: a header passes on at each CHILD's rate in, not a flat 100%
EdgeIs(936, 932, -1.1, 7, "C8 Shattrath City (header) -> Aldor at the child's rate in")
EdgeIs(936, 935, 0.5, 4, "C8 Shattrath City (header) -> Sha'tar at the child's rate in")
CHECK(Edge(936, 1011) == nil, "C8 ...and not to Lower City (rate in 0)")
for _, cap in ipairs({ 47, 54, 69, 72, 930 }) do
    EdgeIs(469, cap, 1, 7, "C8 Alliance (header) -> capital " .. cap .. " at 100%")
end
for _, cap in ipairs({ 68, 76, 81, 530, 911 }) do
    EdgeIs(67, cap, 1, 7, "C8 Horde (header) -> capital " .. cap .. " at 100%")
end
-- capitals: 25% to each other capital on the same side, uncapped in 2.5.6
local ALLIANCE_CAPS, HORDE_CAPS = { 47, 54, 69, 72, 930 }, { 68, 76, 81, 530, 911 }
for _, side in ipairs({ ALLIANCE_CAPS, HORDE_CAPS }) do
    for _, a in ipairs(side) do
        EQ(#(F[a].spill or {}), 4, "C9 capital " .. a .. " spills to four")
        for _, b in ipairs(side) do
            if a ~= b then EdgeIs(a, b, 0.25, 7, "C9 capital " .. a .. " -> " .. b .. " 25% to Exalted") end
        end
    end
end
for _, a in ipairs({ 21, 369, 470, 577 }) do
    for _, b in ipairs({ 21, 369, 470, 577 }) do
        if a ~= b then EdgeIs(a, b, 0.5, 7, "C9 goblin town " .. a .. " -> " .. b .. " 50%") end
    end
end
-- No Outland, Shattrath or other TBC faction spills, bar Aldor and Scryers
-- (and the two new capitals, which spill as capitals)
for _, id in ipairs({ 922, 933, 935, 941, 942, 946, 947, 967, 970, 978, 989, 990, 1011, 1012, 1015, 1031, 1038, 1077 }) do
    CHECK(F[id].spill == nil, "C10 no spill from " .. F[id].name)
end
-- the reward rates (reputation_reward_rate): exactly the three Classic x2 factions
local rated = {}
for id, f in pairs(F) do
    if f.rate then rated[#rated + 1] = id end
end
CHECK(SameSet(rated, { 529, 576, 609 }), "C11 rate rows only on Argent Dawn, Timbermaw, Cenarion Circle", #rated)
for _, id in ipairs({ 529, 576, 609 }) do
    EQ(F[id].rate and F[id].rate.quest, 2, "C11 quest rate x2: " .. id)
    EQ(F[id].rate and F[id].rate.kill, 1, "C11 kill rate x1: " .. id)
end

-- Starting standing, fitted the way the client fits it (FactionEntry::GetIndexFitTo):
-- the first row whose race and class masks both admit the character
local function Fit(id, raceId, classId)
    local rm, cm = 2 ^ (raceId - 1), 2 ^ (classId - 1)
    local function Has(mask, bit) return mask ~= 0 and math.floor(mask / bit) % 2 == 1 end
    for _, row in ipairs(F[id].base) do
        if (row[1] == 0 or Has(row[1], rm)) and (row[2] == 0 or Has(row[2], cm)) then
            return row[3]
        end
    end
    return 0
end
local HUMAN, ORC, DWARF, NE, UNDEAD, TAUREN, GNOME, TROLL, BE, DRAENEI = 1, 2, 3, 4, 5, 6, 7, 8, 10, 11
local WARRIOR, DRUID = 1, 11
for _, race in ipairs({ HUMAN, ORC, NE, UNDEAD, TAUREN, GNOME, TROLL, BE, DRAENEI, DWARF }) do
    EQ(Fit(970, race, WARRIOR), -2500, "C12 Sporeggar -2500 for race " .. race)
    EQ(Fit(1015, race, WARRIOR), -42000, "C12 Netherwing -42000 for race " .. race)
    EQ(Fit(942, race, WARRIOR), 0, "C12 Cenarion Expedition 0 for race " .. race)
end
for _, race in ipairs({ HUMAN, DWARF, NE, GNOME, DRAENEI }) do
    EQ(Fit(978, race, WARRIOR), -1200, "C12 Kurenai -1200 for Alliance race " .. race)
    EQ(Fit(941, race, WARRIOR), -42000, "C12 Mag'har -42000 for Alliance race " .. race)
    EQ(Fit(946, race, WARRIOR), 0, "C12 Honor Hold 0 for Alliance race " .. race)
    EQ(Fit(947, race, WARRIOR), -42000, "C12 Thrallmar -42000 for Alliance race " .. race)
end
for _, race in ipairs({ ORC, UNDEAD, TAUREN, TROLL, BE }) do
    EQ(Fit(941, race, WARRIOR), -500, "C12 Mag'har -500 for Horde race " .. race)
    EQ(Fit(978, race, WARRIOR), -42000, "C12 Kurenai -42000 for Horde race " .. race)
    EQ(Fit(947, race, WARRIOR), 0, "C12 Thrallmar 0 for Horde race " .. race)
    EQ(Fit(946, race, WARRIOR), -42000, "C12 Honor Hold -42000 for Horde race " .. race)
    EQ(Fit(930, race, WARRIOR), -42000, "C12 Exodar -42000 for Horde race " .. race)
end
EQ(Fit(932, DRAENEI, WARRIOR), 3500, "C13 Aldor +3500 for a Draenei")
EQ(Fit(934, DRAENEI, WARRIOR), -3500, "C13 Scryers -3500 for a Draenei")
EQ(Fit(932, BE, WARRIOR), -3500, "C13 Aldor -3500 for a Blood Elf")
EQ(Fit(934, BE, WARRIOR), 3500, "C13 Scryers +3500 for a Blood Elf")
EQ(Fit(932, HUMAN, WARRIOR), 0, "C13 Aldor 0 for a Human")
EQ(Fit(934, ORC, WARRIOR), 0, "C13 Scryers 0 for an Orc")
EQ(Fit(911, ORC, WARRIOR), 400, "C13 Silvermoon 400 for an Orc")
EQ(Fit(911, TAUREN, WARRIOR), 400, "C13 Silvermoon 400 for a Tauren")
EQ(Fit(911, UNDEAD, WARRIOR), 3100, "C13 Silvermoon 3100 for the Forsaken")
EQ(Fit(911, BE, WARRIOR), 4000, "C13 Silvermoon 4000 for a Blood Elf")
EQ(Fit(930, HUMAN, WARRIOR), 3000, "C13 Exodar 3000 for a Human")
EQ(Fit(930, DRAENEI, WARRIOR), 4000, "C13 Exodar 4000 for a Draenei")
EQ(Fit(609, NE, DRUID), 2000, "C13 Cenarion Circle 2000 for a Night Elf druid")
EQ(Fit(609, NE, WARRIOR), 0, "C13 Cenarion Circle 0 for a Night Elf warrior")
EQ(Fit(576, HUMAN, WARRIOR), -3500, "C13 Timbermaw -3500")
EQ(Fit(87, HUMAN, WARRIOR), -6500, "C13 Bloodsail -6500")
EQ(Fit(910, HUMAN, WARRIOR), -42000, "C13 Brood of Nozdormu -42000")
EQ(Fit(70, HUMAN, WARRIOR), -10000, "C13 Syndicate -10000")
-- Side comes from the -42000 rule, not from flags (critic W9); Exodar's
-- Horde row also names race 9, which a naive "all Horde bits" test misses
local SIDES = { [946] = "Alliance", [978] = "Alliance", [930] = "Alliance", [469] = "Alliance", [72] = "Alliance",
    [947] = "Horde", [941] = "Horde", [911] = "Horde", [922] = "Horde", [67] = "Horde", [76] = "Horde" }
for id, side in pairs(SIDES) do
    EQ(F[id].side, side, "C14 side of " .. F[id].name)
end
for _, id in ipairs({ 932, 934, 935, 933, 942, 970, 1015, 1011, 989, 910 }) do
    EQ(F[id].side, nil, "C14 no side for " .. F[id].name)
end
EQ(F[980].name, "Outland", "C15 980 is \"Outland\" in this build (critic W8)")
EQ(F[1077].idx, 80, "C15 Shattered Sun Offensive sits in slot 80")

-- ===========================================================================
-- D. Picker groups
-- ===========================================================================

local G = D.groups or {}
local WANT_KEYS = { "OUTLAND", "SHATTRATH", "TBC_OTHER", "ALLIANCE", "HORDE", "STEAMWHEEDLE", "CLASSIC_OTHER" }
EQ(#G, #WANT_KEYS, "D1 seven groups")
for i, key in ipairs(WANT_KEYS) do
    EQ(G[i] and G[i].key, key, "D1 group " .. i .. " is " .. key)
end
local placed, tbcPlaced = {}, {}
local dOk, dDone = Batch({
    "D2 title", "D2 non-empty", "D2 tbc flag only on the first three", "D2 header names a header faction",
    "D3 member is a faction", "D3 no faction in two groups", "D3 no header in the picker",
    "D3 a side group's members are on that side", "D3 goblin towns sit under Steamwheedle",
})
for i, g in ipairs(G) do
    local gl = "group " .. tostring(g.key)
    dOk("D2 title", type(g.title) == "string" and g.title ~= "", gl)
    dOk("D2 non-empty", type(g.ids) == "table" and #g.ids > 0, gl)
    dOk("D2 tbc flag only on the first three", (g.tbc == true) == (i <= 3), gl)
    if g.header ~= nil then
        dOk("D2 header names a header faction", F[g.header] ~= nil and F[g.header].header == true, gl)
    end
    for _, id in ipairs(type(g.ids) == "table" and g.ids or {}) do
        local ml = gl .. " " .. tostring(id)
        dOk("D3 member is a faction", F[id] ~= nil, ml)
        dOk("D3 no faction in two groups", not placed[id], ml)
        dOk("D3 no header in the picker", F[id] ~= nil and not F[id].header, ml)
        if g.side then dOk("D3 a side group's members are on that side", F[id] and F[id].side == g.side, ml) end
        if g.key == "STEAMWHEEDLE" then dOk("D3 goblin towns sit under Steamwheedle", F[id] and F[id].parent == 169, ml) end
        placed[id] = g.key
        if g.tbc then tbcPlaced[id] = true end
    end
end
dDone()
local TBC = { 911, 922, 930, 932, 933, 934, 935, 941, 942, 946, 947, 967, 970, 978, 989, 990, 1011, 1012, 1015,
    1031, 1038, 1077 }
for _, id in ipairs(TBC) do
    CHECK(tbcPlaced[id], "D4 TBC faction in a TBC group: " .. F[id].name)
end
EQ(Count(tbcPlaced), #TBC, "D4 the TBC groups hold exactly the 22 TBC factions")
for _, id in ipairs({ 942, 946, 947, 933, 970, 978, 941, 1012, 1015, 1038 }) do
    EQ(placed[id], "OUTLAND", "D5 Outland child in OUTLAND: " .. id)
end
for _, id in ipairs({ 932, 934, 935, 1011, 1031, 1077 }) do
    EQ(placed[id], "SHATTRATH", "D5 Shattrath child in SHATTRATH: " .. id)
end
for _, id in ipairs({ 529, 609, 576, 59, 909, 270 }) do
    EQ(placed[id], "CLASSIC_OTHER", "D5 classic faction in CLASSIC_OTHER: " .. id)
end
for _, id in ipairs({ 86, 46, 574, 1005, 471 }) do
    EQ(placed[id], nil, "D5 hidden or questless faction left out: " .. id)
end

-- ===========================================================================
-- E. Localized names
-- ===========================================================================

local N = D.names or {}
CHECK(type(D.names) == "table", "E1 names table present")
EQ(N.enUS, nil, "E1 no enUS table (factions[id].name is enUS)")
EQ(N.itIT, nil, "E1 no itIT table (identical to enUS in this build)")
local eOk, eDone = Batch({ "E2 locale key is xxYY", "E3 a TBC faction", "E3 non-empty and not the enUS name" })
for loc, t in pairs(N) do
    eOk("E2 locale key is xxYY", type(loc) == "string" and loc:match("^%l%l%u%u$") ~= nil, loc)
    for id, s in pairs(type(t) == "table" and t or {}) do
        local nl = tostring(loc) .. " " .. tostring(id)
        eOk("E3 a TBC faction", F[id] ~= nil and tbcPlaced[id], nl)
        eOk("E3 non-empty and not the enUS name", type(s) == "string" and s ~= "" and s ~= (F[id] and F[id].name), nl)
    end
end
eDone()
CHECK(Count(N) >= 8, "E4 names for the shipped locales (deDE, esES, esMX, frFR, koKR, ptBR, ruRU, zhCN, zhTW)", Count(N))
EQ(N.deDE and N.deDE[942], "Expedition des Cenarius", "E4 deDE Cenarion Expedition")
EQ(N.frFR and N.frFR[1015], "Aile-du-Néant", "E4 frFR Netherwing")
EQ(N.deDE and N.deDE[947], nil, "E4 deDE Thrallmar is the enUS word, so not stored")

-- ===========================================================================
-- F. Reward clamps (RewMaxRepValue)
-- ===========================================================================

local RC = D.rewardCap or {}
local capRows = 0
local fOk, fDone = Batch({ "F1 quest id", "F1 faction exists", "F1 a clamp below the ceiling" })
for q, t in pairs(RC) do
    fOk("F1 quest id", IsInt(q) and q > 0, q)
    for f, v in pairs(type(t) == "table" and t or {}) do
        capRows = capRows + 1
        fOk("F1 faction exists", F[f] ~= nil, tostring(q) .. "/" .. tostring(f))
        fOk("F1 a clamp below the ceiling", IsInt(v) and v >= 0 and v < D.cap, tostring(q) .. "/" .. tostring(f))
    end
end
fDone()
EQ(Count(RC), 16, "F2 fifteen quests from the world DB (critic W1) plus the Human 10871")
EQ(capRows, D.reconciliation and D.reconciliation.rewardCapRows, "F2 row count matches the reconciliation")
EQ(RC[10326] and RC[10326][932], 8999, "F3 10326 Aldor stops at 8999")
EQ(RC[10326] and RC[10326][935], 8999, "F3 10326 Sha'tar stops at 8999")
EQ(RC[10327] and RC[10327][932], 8999, "F3 10327 Aldor stops at 8999")
EQ(RC[10414] and RC[10414][934], 8999, "F3 10414 Scryers stops at 8999")
EQ(RC[10415] and RC[10415][934], 8999, "F3 10415 Scryers stops at 8999")
for _, q in ipairs({ 10419, 10421, 10654, 10655, 10658, 10659, 10822, 10823, 10827, 10828 }) do
    EQ(RC[q] and RC[q][935], 8999, "F4 Sha'tar row capped at 8999 on " .. q)
    EQ(RC[q] and Count(RC[q]), 1, "F4 ...and only the Sha'tar row on " .. q)
end
EQ(RC[10870] and RC[10870][1015], 0, "F5 Ally of the Netherwing lands on exactly 0")
EQ(RC[10871] and RC[10871][1015], 0, "F5 ...and so does the Human copy 10871")

-- ===========================================================================
-- G. Derived rows
-- ===========================================================================

local DV = D.derived or {}
local shatarDerived = 0
local gOk, gDone = Batch({ "G1 { factionId, ... } per quest", "G1 derived faction exists" })
for q, list in pairs(DV) do
    gOk("G1 { factionId, ... } per quest", IsInt(q) and type(list) == "table" and #list > 0, q)
    for _, f in ipairs(type(list) == "table" and list or {}) do
        gOk("G1 derived faction exists", F[f] ~= nil, tostring(q) .. "/" .. tostring(f))
        if f == 935 then shatarDerived = shatarDerived + 1 end
    end
end
gDone()
EQ(Count(DV), D.reconciliation and D.reconciliation.derivedQuests, "G2 quest count matches the reconciliation")
CHECK(shatarDerived >= 80, "G2 the stored Sha'tar halves (85 in both databases)", shatarDerived)
CHECK(SetOf(DV[10326])[935], "G3 10326: the stored Sha'tar 125 is spillover")
CHECK(SetOf(DV[10421])[935], "G3 10421: the stored Sha'tar 175 is spillover")
CHECK(SameSet(DV[9266], { 21, 369, 470 }), "G3 9266: the three goblin towns at 250 are spillover of Everlook 500")
CHECK(SameSet(DV[9268], { 21, 470, 577 }), "G3 9268: the three goblin towns at 250 are spillover of Gadgetzan 500")
CHECK(SameSet(DV[4766], { 930 }), "G3 4766: Exodar 2 is spillover of Stormwind 10")
EQ(DV[281], nil, "G4 281: Alliance 10 beside Gnomeregan 10 is not evidence (rate-1 header edge)")
EQ(DV[7642], nil, "G4 7642: Alliance 75 beside Darnassus 75 is not evidence")
EQ(DV[10886], nil, "G4 10886: a Sha'tar-only quest has nothing to derive from")

-- ===========================================================================
-- H. Repeatable costs
-- ===========================================================================

local RCOST = D.repeatCost or {}
local hOk, hDone = Batch({ "H1 { itemId, count, ... }", "H1 positive integers" })
for q, t in pairs(RCOST) do
    hOk("H1 { itemId, count, ... }", IsInt(q) and type(t) == "table" and #t >= 2 and #t % 2 == 0, q)
    for i = 1, type(t) == "table" and #t or 0 do
        hOk("H1 positive integers", IsInt(t[i]) and t[i] > 0, tostring(q) .. "[" .. i .. "]")
    end
end
hDone()
EQ(Count(RCOST), D.reconciliation and D.reconciliation.repeatCost, "H2 count matches the reconciliation")
CHECK(Count(RCOST) >= 90, "H2 every TBC repeatable with a cost is there (and the classic ones)", Count(RCOST))
CHECK(RCOST[10326] and RCOST[10326][1] == 29425 and RCOST[10326][2] == 10, "H3 More Marks of Kil'jaeden: 10 marks")
CHECK(RCOST[10327] and RCOST[10327][1] == 29425 and RCOST[10327][2] == 1, "H3 Single Mark of Kil'jaeden: 1 mark")
CHECK(RCOST[9742] and RCOST[9742][2] == 10, "H3 More Spore Sacs: 10 sacs")
CHECK(RCOST[11074] and #RCOST[11074] == 8, "H3 Tokens of the Descendants takes the four talisman items",
    RCOST[11074] and #RCOST[11074])
EQ(RCOST[11008], nil, "H4 Fires Over Skettis: the charges are handed to you, not a cost")
EQ(RCOST[10106], nil, "H4 Hellfire Fortifications takes no item")
EQ(RCOST[10870], nil, "H4 a one-time quest has no repeat cost")

-- ===========================================================================
-- I. Rotating, J. conditional
-- ===========================================================================

local RO = D.rotating or {}
local normal, heroic = 0, 0
local iOk, iDone = Batch({ "I1 a Wanted daily", "I1 NORMAL or HEROIC" })
for q, kind in pairs(RO) do
    iOk("I1 a Wanted daily", IsInt(q) and ((q >= 11354 and q <= 11389) or q == 11499 or q == 11500), q)
    iOk("I1 NORMAL or HEROIC", kind == "NORMAL" or kind == "HEROIC", q)
    if kind == "NORMAL" then normal = normal + 1 elseif kind == "HEROIC" then heroic = heroic + 1 end
end
iDone()
EQ(normal, 8, "I2 eight normal Wanted dailies (Nether-Stalker Mah'duun)")
EQ(heroic, 16, "I2 sixteen heroic Wanted dailies (Wind Trader Zhareem)")
EQ(RO[11354], "HEROIC", "I3 Nazan's Riding Crop is heroic")
EQ(RO[11364], "NORMAL", "I3 Shattered Hand Centurions is normal")
EQ(RO[11499], "HEROIC", "I3 Signet Ring of Prince Kael'thas is heroic")
EQ(RO[11500], "NORMAL", "I3 Sisters of Torment is normal")
EQ(RO[11377], nil, "I3 the Rokk's cooking dailies are not Wanted dailies")
EQ(D.reconciliation and D.reconciliation.rotating, Count(RO), "I4 count matches the reconciliation")
local CO = D.conditional or {}
EQ(CO[11502], "HALAA", "J1 In Defense of Halaa needs Halaa")
EQ(CO[11503], "HALAA", "J1 Enemies, Old and New needs Halaa")
EQ(Count(CO), 2, "J1 nothing else is conditional")

-- ===========================================================================
-- K. Overrides
-- ===========================================================================

local OV = D.overrides
CHECK(type(OV) == "table", "K1 overrides table present (empty until the audit writes one)")
local kOk, kDone = Batch({ "K2 quest id", "K2 cites a Wowhead page", "K2 ...the page of this quest",
    "K3 faction exists", "K3 a raw value", "K3 at least one faction row" })
for q, t in pairs(type(OV) == "table" and OV or {}) do
    local ql = "override " .. tostring(q)
    t = type(t) == "table" and t or {}
    kOk("K2 quest id", IsInt(q) and q > 0, ql)
    kOk("K2 cites a Wowhead page",
        type(t.src) == "string" and t.src:match("^https://") ~= nil and t.src:find("wowhead%.com") ~= nil, ql)
    kOk("K2 ...the page of this quest", type(t.src) == "string" and t.src:find(tostring(q), 1, true) ~= nil, ql)
    local rowsHere = 0
    for k, v in pairs(t) do
        if k ~= "src" then
            rowsHere = rowsHere + 1
            kOk("K3 faction exists", IsInt(k) and F[k] ~= nil, ql .. "/" .. tostring(k))
            kOk("K3 a raw value", IsInt(v) and v >= D.bottom and v <= 42000, ql .. "/" .. tostring(k))
        end
    end
    kOk("K3 at least one faction row", rowsHere > 0, ql)
end
kDone()
EQ(Count(OV), D.reconciliation and D.reconciliation.overrides, "K4 count matches the reconciliation")
EQ(D.reconciliation and D.reconciliation.overridesRefused, 0, "K4 the generator refused no override row")
-- The audit's "Wowhead (TBC) and CMaNGOS agree against Questie" corrections
-- (D38, applied 2026-10-04): each is the quest's complete row set, so every
-- Questie row it drops is written as 0
do
    local nine = {
        [4267] = { [47] = 0, [54] = 0, [69] = 0, [369] = 0, [930] = 0 },
        [5096] = { [68] = 250, [76] = 0, [81] = 0, [530] = 0, [911] = 0 },
        [6804] = { [67] = 250, [68] = 0, [76] = 0, [81] = 0, [530] = 0, [911] = 0 },
        [7639] = { [47] = 0, [69] = 0, [72] = 75, [930] = 0 },
        [7640] = { [47] = 0, [69] = 0, [72] = 250, [930] = 0 },
        [7781] = { [47] = 500, [54] = 500, [69] = 500, [72] = 500, [930] = 500 },
        [7782] = { [47] = 500, [54] = 500, [69] = 500, [72] = 500, [930] = 500 },
        [10016] = { [47] = 0, [54] = 0, [69] = 0, [72] = 0, [930] = 0 },
        [11211] = { [68] = 0, [76] = 0, [81] = 0, [369] = 10, [530] = 0, [911] = 0 },
    }
    local wrong = {}
    for questId, rows in pairs(nine) do
        local t = type(OV) == "table" and OV[questId]
        local same = type(t) == "table"
        if same then
            for factionId, value in pairs(rows) do
                if t[factionId] ~= value then same = false end
            end
            for key in pairs(t) do
                if key ~= "src" and rows[key] == nil then same = false end
            end
        end
        if not same then wrong[#wrong + 1] = questId end
    end
    table.sort(wrong)
    EQ(#wrong, 0, "K5 the nine corrections where Wowhead and CMaNGOS agree are emitted whole: " .. table.concat(wrong, ","))
end

-- ===========================================================================
-- L. The reconciliation the generator recorded
-- ===========================================================================

local R = D.reconciliation or {}
CHECK(type(D.reconciliation) == "table", "L1 reconciliation recorded")
EQ(R.spillMismatches, 0, "L2 DB2 spill edges match the server's template: zero mismatches")
EQ(R.spillTemplateRows, 16, "L2 all sixteen template rows were compared")
EQ(R.droppedRows, 0, "L3 no quest row names a faction without a reputation slot")
local templated = 0
for _, id in ipairs({ 21, 369, 470, 577, 47, 54, 69, 72, 930, 68, 76, 81, 530, 911, 932, 934 }) do
    if F[id].spill then templated = templated + 1 end
end
EQ(templated, 16, "L4 every templated source carries its spill")
local sources = 0
for _, f in pairs(F) do
    if f.spill then sources = sources + 1 end
end
EQ(sources, 20, "L4 twenty spill sources: the sixteen templated + the four headers")

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
