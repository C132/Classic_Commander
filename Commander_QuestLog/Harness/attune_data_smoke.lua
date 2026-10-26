-- Commander Quest Log: attunement data smoke (luajit).
--
-- Loads the GENERATED CommanderQuestLogAttuneData.lua alone into a SEALED
-- environment -- reading any global but its own table raises, and the only
-- global it may write is that table -- so the run itself is the proof that the
-- file is pure data. Then it walks the table the way the engine
-- (CommanderQuestLogAttune.lua) and the tab (CommanderQuestLogAttunements.lua)
-- read it and holds the generator to DESIGN.md section 3 and 9.1, check by
-- check, D1 to D34:
--
--   D1  build stamp          D2  five phases            D3  five full RULES rows
--   D4  EVIDENCE ids         D5  six categories         D6  the guide roster, keys unique
--   D7  guide record shape   D8  step keys unique       D9  the nine kinds
--   D10 QUEST ids            D11 REP ids and standing   D12 ITEM ids, never itemId
--   D13 phase windows        D14 places                 D15 alternatives resolve
--   D16 consumedBy/impliedBy D17 splits whole           D18 RULES vs the REP pairs
--   D19 the corrections landed                          D20 no underscore or client prefix drawn
--   D21 the BADGES merge     D22 KILL_MAPS              D23 INSTANCES, all 25
--   D24 unlock proofs        D25 prerequisites          D26 accountWide on the five gates
--   D27 minLevel             D28 MANUAL auto            D29 REP factionName
--   D30 TK chains, no TK consumption                    D31 dailies outside BADGES
--   D32 accept steps, Karazhan siblings                 D33 Shadow Labyrinth groups
--   D34 the mount ids
--
-- A rule that holds for every row (every step, every place...) is one check,
-- reporting how many rows broke it and the first, so the count below does not
-- move when the generator is re-run on new research.
--
--   /opt/homebrew/bin/luajit Commander_QuestLog/Harness/attune_data_smoke.lua
--
-- Mutation hook (the copy lives anywhere; the live file is never touched):
--   CQL_ATTUNE_DATA=/path/copy.lua luajit .../attune_data_smoke.lua

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local DATA = os.getenv("CQL_ATTUNE_DATA") or (ADDONS .. "/Commander_QuestLog/CommanderQuestLogAttuneData.lua")

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

-- One check per rule however many rows: fails with the count and the first offender.
local function Batch(label)
    local bad, first = 0, nil
    return function(cond, where)
        if not cond then
            bad = bad + 1
            if not first then first = where end
        end
    end, function()
        CHECK(bad == 0, label, bad > 0 and (bad .. " rows, first " .. tostring(first)) or nil)
    end
end

local function Has(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then return true end
    end
    return false
end

local function Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function Keys(t)
    local out = {}
    for k in pairs(t or {}) do out[#out + 1] = k end
    table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
    return out
end

-- ===========================================================================
-- Load: sealed environment, one global in, one global out
-- ===========================================================================

local chunk, err = loadfile(DATA)
CHECK(chunk ~= nil, "D1 the data file parses", err)
if not chunk then
    io.write(checks .. " checks, " .. fails .. " failed\n")
    os.exit(1)
end
local sandbox = {}
local written = {}
setmetatable(sandbox, {
    __index = function(_, k)
        if k == "CommanderQuestLogAttuneData" then return rawget(sandbox, k) end
        error("the data file read global " .. tostring(k), 2)
    end,
    __newindex = function(t, k, v)
        written[#written + 1] = k
        rawset(t, k, v)
    end,
})
setfenv(chunk, sandbox)
local ok, loadErr = pcall(chunk)
CHECK(ok, "D1 the data file runs as pure data (no global read but its own)", loadErr)
local D = rawget(sandbox, "CommanderQuestLogAttuneData")
CHECK(type(D) == "table" and #written == 1 and written[1] == "CommanderQuestLogAttuneData",
    "D1 exactly one global written: CommanderQuestLogAttuneData", table.concat(written, ","))
if type(D) ~= "table" then
    io.write(checks .. " checks, " .. fails .. " failed\n")
    os.exit(1)
end
CHECK(type(D.BUILD) == "string" and D.BUILD:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil, "D1 build stamp present", D.BUILD)
CHECK(type(D.SOURCE) == "string" and D.SOURCE:find("make_attunements.py", 1, true) ~= nil, "D1 SOURCE names the generator", D.SOURCE)

local G = D.guides or {}
local by = {}
for _, g in ipairs(G) do by[g.key] = g end
local function Step(gkey, skey)
    local g = by[gkey]
    for _, s in ipairs(g and g.steps or {}) do
        if s.key == skey then return s end
    end
    return nil
end
local function Steps(gkey)
    local g = by[gkey]
    return g and g.steps or {}
end

-- every (guide, step) pair, for the batched rules
local function EachStep(fn)
    for _, g in ipairs(G) do
        for _, s in ipairs(g.steps or {}) do
            fn(g, s, g.key .. ":" .. tostring(s.key))
        end
    end
end

-- ===========================================================================
-- D2 to D5: the top tables
-- ===========================================================================

do
    local P = D.PHASES or {}
    EQ(#P, 5, "D2 five phases")
    local ascending, shape = true, true
    for i = 1, 4 do
        if type(P[i].since) ~= "number" or type(P[i + 1].since) == "number" and P[i].since >= P[i + 1].since then
            ascending = false
        end
    end
    for i, p in ipairs(P) do
        if p.n ~= i or type(p.short) ~= "string" or type(p.name) ~= "string" or type(p.blizzard) ~= "string"
            or type(p.notes) ~= "string" or #p.notes == 0 then
            shape = false
        end
    end
    CHECK(ascending, "D2 epochs ascending through Phase 4")
    CHECK(P[5] and P[5].since == false, "D2 Phase 5 since is false (unannounced)", P[5] and tostring(P[5].since))
    CHECK(shape, "D2 every phase carries n, short, name, blizzard and notes")
    EQ(P[1] and P[1].raidsOpen, 1771542000, "D2 Phase 1 raidsOpen epoch")
    EQ(P[4] and P[4].blizzard, "Phase 3.5", "D2 Phase 4 is Blizzard's Phase 3.5")
end

local GATES = { "KARAZHAN", "SSC", "TK", "HYJAL", "BT" }
do
    local R = D.RULES or {}
    EQ(Count(R), 5, "D3 five RULES rows")
    local want = { 7, 7, 7, 6, 6 }
    local standings, gates, shape = true, true, true
    local required = { -- 3.3: rows 1 and 2 all true; row 3 KARAZHAN, HYJAL, BT; rows 4 and 5 KARAZHAN only
        [1] = { KARAZHAN = true, SSC = true, TK = true, HYJAL = true, BT = true },
        [2] = { KARAZHAN = true, SSC = true, TK = true, HYJAL = true, BT = true },
        [3] = { KARAZHAN = true, SSC = false, TK = false, HYJAL = true, BT = true },
        [4] = { KARAZHAN = true, SSC = false, TK = false, HYJAL = false, BT = false },
        [5] = { KARAZHAN = true, SSC = false, TK = false, HYJAL = false, BT = false },
    }
    local gateValues = true
    for p = 1, 5 do
        local r = R[p]
        if not r then
            shape = false
        else
            if r.heroicKeyStanding ~= want[p] then standings = false end
            for _, k in ipairs(GATES) do
                if type((r.attunementRequired or {})[k]) ~= "boolean" then gates = false end
                if (r.attunementRequired or {})[k] ~= required[p][k] then gateValues = false end
            end
            if type(r.communalPouches) ~= "boolean" or type(r.heroicTuning) ~= "string" or type(r.vendorStock) ~= "string"
                or type(r.raidsOpen) ~= "table" or type(r.badgeSources) ~= "table" or type(r.live) ~= "table"
                or type(r.assumed) ~= "table" or type(r.sentences) ~= "table" or #r.sentences == 0 then
                shape = false
            end
        end
    end
    CHECK(standings, "D3 heroicKeyStanding 7, 7, 7, 6, 6")
    CHECK(gates, "D3 every gate key present on every row")
    CHECK(gateValues, "D3 attunementRequired per phase as 3.3 lists it")
    CHECK(shape, "D3 every row is FULL: pouches, tuning, stock, raidsOpen, badgeSources, live, assumed, sentences")
    CHECK(R[1] and R[1].communalPouches == false and R[2] and R[2].communalPouches == true, "D3 communal pouches false in 1, true from 2")
    CHECK(R[5] and Has(R[5].assumed, "heroicKeyStanding") and Has(R[5].assumed, "badgeSources.HYJAL_BT"), "D3 row 5 names its assumed keys")
    CHECK(R[4] and R[4].badgeSources.KARAZHAN == true and R[1] and R[1].badgeSources.KARAZHAN == false, "D3 Karazhan badges from Phase 4 only")
end

do
    local E = D.EVIDENCE or {}
    local L = E.lockouts or {}
    CHECK(L[568] == 4 and L[580] == 5 and L[585] == 5 and Count(L) == 3, "D4 EVIDENCE lockouts 568/580/585")
    local want = { [11130] = 4, [11132] = 4, [11166] = 4, [11171] = 4, [11163] = 4, [11178] = 4, [11481] = 5, [11482] = 5, [11488] = 5 }
    local okq = Count(E.quests or {}) == 9
    for id, p in pairs(want) do
        if (E.quests or {})[id] ~= p then okq = false end
    end
    CHECK(okq, "D4 EVIDENCE nine quests with their phases")
end

do
    local C = D.CATEGORIES or {}
    local want = { "RAID", "HEROIC", "DUNGEON", "UNLOCK", "FLYING", "BADGES" }
    local labels = { RAID = "Raid attunements", HEROIC = "Heroic keys", DUNGEON = "Dungeon keys", UNLOCK = "Reputation hubs",
        FLYING = "Flying", BADGES = "Badges of Justice" }
    local order, named = #C == 6, true
    for i, c in ipairs(C) do
        if c.key ~= want[i] then order = false end
        if c.label ~= labels[c.key] then named = false end
    end
    CHECK(order, "D5 six categories in order")
    CHECK(named, "D5 category labels as 3.1 words them")
end

-- ===========================================================================
-- D6 to D9: guides and steps, shape
-- ===========================================================================

do
    -- 26, not 24: DESIGN.md 3.1's own roster (RAID 9, HEROIC 6, DUNGEON 4, UNLOCK 5, FLYING 1, BADGES 1) sums to 26.
    EQ(#G, 26, "D6 26 guides (the roster of 3.1)")
    local seen, unique = {}, true
    for _, g in ipairs(G) do
        if seen[g.key] then unique = false end
        seen[g.key] = true
    end
    CHECK(unique, "D6 guide keys unique")
    local perCat = {}
    for _, g in ipairs(G) do perCat[g.category] = (perCat[g.category] or 0) + 1 end
    CHECK(perCat.RAID == 9 and perCat.HEROIC == 6 and perCat.DUNGEON == 4 and perCat.UNLOCK == 5 and perCat.FLYING == 1
        and perCat.BADGES == 1, "D6 roster per module: 9, 6, 4, 5, 1, 1")
    for _, k in ipairs({ "KARAZHAN_ATTUNEMENT", "NIGHTBANE_SUMMON", "GRUUL_MAGTHERIDON", "SSC_ATTUNEMENT", "TK_ATTUNEMENT",
        "HYJAL_ATTUNEMENT", "BLACK_TEMPLE_ATTUNEMENT", "ZUL_AMAN", "SUNWELL_PLATEAU", "HEROIC_HELLFIRE", "HEROIC_COILFANG",
        "HEROIC_AUCHINDOUN", "HEROIC_TEMPEST_KEEP", "HEROIC_CAVERNS_OF_TIME", "HEROIC_MAGISTERS_TERRACE",
        "CAVERNS_OF_TIME_ACCESS", "SHADOW_LABYRINTH_KEY", "SHATTERED_HALLS_KEY", "ARCATRAZ_KEY", "ALDOR_SCRYER_CHOICE",
        "OGRILA_UNLOCK", "SKYGUARD_SKETTIS", "NETHERWING_DAILIES", "SHATTERED_SUN_OFFENSIVE", "FLYING", "BADGES" }) do
        CHECK(by[k] ~= nil, "D6 guide present: " .. k)
    end
    CHECK(by.FLYING_BASIC == nil and by.FLYING_EPIC == nil and by.BADGE_VENDORS == nil and by.BADGES_PHASE_1 == nil
        and by.PHASES == nil, "D6 the merged and dropped research guides are not emitted")
end

do
    local catKnown = {}
    for _, c in ipairs(D.CATEGORIES or {}) do catKnown[c.key] = true end
    local b, done = Batch("D7 every guide: name <= 24, title, known category, order, faction, phase")
    local b2, done2 = Batch("D7 every guide: phase.requiredUntil number or false, phase.note, summary, unlocks, booleans")
    local lastOrder = {}
    for _, g in ipairs(G) do
        b(type(g.name) == "string" and #g.name <= 24 and type(g.title) == "string" and catKnown[g.category]
            and type(g.order) == "number" and (g.faction == "BOTH" or g.faction == "A" or g.faction == "H")
            and type(g.phase) == "table" and type(g.phase.introduced) == "number" and g.phase.introduced >= 1
            and g.phase.introduced <= 5, g.key)
        local ru = g.phase and g.phase.requiredUntil
        b2((type(ru) == "number" or ru == false) and type(g.phase.note) == "string" and #g.phase.note > 0
            and type(g.summary) == "string" and type(g.unlocks) == "string" and type(g.accountWide) == "boolean"
            and type(g.recurring) == "boolean" and type(g.prerequisites) == "table" and type(g.steps) == "table"
            and #g.steps > 0, g.key)
        -- order climbs by 10 within a module
        lastOrder[g.category] = (lastOrder[g.category] or 0) + 10
        if g.order ~= lastOrder[g.category] then b(false, g.key .. " order " .. tostring(g.order)) end
    end
    done(); done2()
    CHECK(by.BADGES and by.BADGES.recurring == true, "D7 BADGES is the recurring guide")
    local others = true
    for _, g in ipairs(G) do
        if g.key ~= "BADGES" and g.recurring then others = false end
    end
    CHECK(others, "D7 no other guide is recurring")
    CHECK(by.HEROIC_HELLFIRE and by.HEROIC_HELLFIRE.name == "Heroic Hellfire" and by.HEROIC_HELLFIRE.instance == 540
        and by.HEROIC_HELLFIRE.gate == nil, "D7 Heroic Hellfire reads as the 3.9 example")
    CHECK(by.KARAZHAN_ATTUNEMENT and by.KARAZHAN_ATTUNEMENT.gate == "KARAZHAN" and by.SSC_ATTUNEMENT.gate == "SSC"
        and by.TK_ATTUNEMENT.gate == "TK" and by.HYJAL_ATTUNEMENT.gate == "HYJAL" and by.BLACK_TEMPLE_ATTUNEMENT.gate == "BT",
        "D7 the five gate keys sit on the five raid attunements")
    local gated = 0
    for _, g in ipairs(G) do
        if g.gate ~= nil then gated = gated + 1 end
    end
    EQ(gated, 5, "D7 no other guide carries a gate")
end

do
    local b, done = Batch("D8 step keys unique per guide")
    for _, g in ipairs(G) do
        local seen = {}
        for _, s in ipairs(g.steps) do
            if type(s.key) ~= "string" or seen[s.key] then b(false, g.key .. ":" .. tostring(s.key)) end
            seen[s.key] = true
        end
    end
    done()
end

local KINDS = { QUEST = true, ITEM = true, REP = true, KILL = true, LEVEL = true, SKILL = true, SPELL = true, TALK = true, MANUAL = true }
do
    local b, done = Batch("D9 every step kind is one of the nine")
    local b2, done2 = Batch("D9 every step has a title of 60 or fewer characters and a detail or detailByPhase")
    EachStep(function(g, s, tag)
        b(KINDS[s.kind] == true, tag .. " " .. tostring(s.kind))
        b2(type(s.title) == "string" and #s.title <= 60 and #s.title > 0
            and (type(s.detail) == "string" or type(s.detailByPhase) == "table"), tag)
    end)
    done(); done2()
end

-- ===========================================================================
-- D10 to D14: ids and places
-- ===========================================================================

do
    local b, done = Batch("D10 QUEST steps have questId or questIds")
    local b2, done2 = Batch("D10 questMode only beside questIds, one of ANY, ALL, CHAIN")
    EachStep(function(g, s, tag)
        if s.kind == "QUEST" then
            b(s.questId ~= nil or type(s.questIds) == "table", tag)
        end
        if s.questMode ~= nil then
            b2(type(s.questIds) == "table" and (s.questMode == "ANY" or s.questMode == "ALL" or s.questMode == "CHAIN"), tag)
        elseif type(s.questIds) == "table" then
            b2(false, tag .. " questIds without questMode")
        end
    end)
    done(); done2()
end

do
    local b, done = Batch("D11 REP steps have factionId and standing 1..8")
    EachStep(function(g, s, tag)
        if s.kind == "REP" then
            local fid = s.factionId
            local okId = type(fid) == "number" or (type(fid) == "table" and type(fid.A) == "number" and type(fid.H) == "number")
            b(okId and type(s.standing) == "number" and s.standing >= 1 and s.standing <= 8, tag)
        end
    end)
    done()
end

do
    local b, done = Batch("D12 ITEM steps have item.id or item.anyOf, never itemId")
    EachStep(function(g, s, tag)
        if s.kind == "ITEM" then
            local it = s.item
            b(type(it) == "table" and (it.id ~= nil or it.anyOf ~= nil) and s.itemId == nil and it.itemId == nil, tag)
        end
    end)
    done()
    local hf = Step("HEROIC_HELLFIRE", "buy_key")
    CHECK(hf and type(hf.item.id) == "table" and hf.item.id.A == 30622 and hf.item.id.H == 30637 and hf.item.name == "Flamewrought Key"
        and hf.item.count == 1, "D12 Flamewrought Key item split, never beside itemId")
    CHECK(hf and type(hf.item.anyOf) == "table" and Has(hf.item.anyOf.A, 265830) and Has(hf.item.anyOf.H, 265826)
        and Has(hf.item.anyOf.A, 30622) and Has(hf.item.anyOf.H, 30637), "D12 buy_key anyOf names the key and its Communal twin (3.9)")
    local ck = Step("HEROIC_HELLFIRE", "communal_key")
    CHECK(ck and type(ck.pouch) == "table" and type(ck.pouch.item) == "table" and ck.pouch.item.A == 265842 and ck.pouch.item.H == 265829
        and ck.pouch.standing == 7 and ck.pouch.cost == "80 gold", "D12 communal_key pouch split with standing 7")
end

do
    local b, done = Batch("D13 every step has a phases window: from 1..5, to false or from <= to <= 5")
    EachStep(function(g, s, tag)
        local ph = s.phases
        local okw = type(ph) == "table" and type(ph.from) == "number" and ph.from >= 1 and ph.from <= 5
            and (ph.to == false or (type(ph.to) == "number" and ph.to >= ph.from and ph.to <= 5))
        b(okw, tag)
    end)
    done()
    local rr, rh = Step("HEROIC_HELLFIRE", "rep_revered"), Step("HEROIC_HELLFIRE", "rep_honored")
    CHECK(rr and rr.phases.from == 1 and rr.phases.to == 3 and rh and rh.phases.from == 4 and rh.phases.to == false,
        "D13 Hellfire REP pair windows 1..3 and 4..open")
end

do
    local mapIds = {}
    for _, id in pairs(D.MAPS or {}) do mapIds[id] = true end
    EQ(Count(D.MAPS or {}), 13, "D14 MAPS holds the thirteen zones")
    CHECK((D.MAPS or {})["Shattrath City"] == 1955 and (D.MAPS or {})["Hellfire Peninsula"] == 1944
        and (D.MAPS or {})["Alterac Mountains"] == 1416 and (D.MAPS or {})["Isle of Quel'Danas"] == 1957, "D14 MAPS ids as A74 lists them")
    local roles = { start = true, turnin = true, vendor = true, trainer = true, kill = true, spot = true, door = true, inside = true, object = true }
    local b, done = Batch("D14 every place has map+x+y or instance or item; map in MAPS; role known")
    local b2, done2 = Batch("D14 every outdoor place carries a name; coordinates 0..100")
    local function Row(r, tag)
        local coords = type(r.map) == "number" and type(r.x) == "number" and type(r.y) == "number"
        b((coords or r.instance ~= nil or r.item ~= nil) and (not coords or mapIds[r.map]) and roles[r.role] == true, tag)
        if coords then
            b2(type(r.name) == "string" and r.x >= 0 and r.x <= 100 and r.y >= 0 and r.y <= 100, tag)
        end
    end
    EachStep(function(g, s, tag)
        for i, p in ipairs(s.places or {}) do
            if p.role == nil then
                for k, r in pairs(p) do
                    if type(r) == "table" then Row(r, tag .. ":" .. i .. "." .. tostring(k)) else b(false, tag .. ":" .. i) end
                end
            else
                Row(p, tag .. ":" .. i)
            end
        end
    end)
    done(); done2()
    local pk = Step("SHATTERED_HALLS_KEY", "entry_into_citadel")
    local startItem = pk and pk.places and pk.places[1]
    CHECK(startItem and type(startItem.A) == "table" and startItem.A.role == "start" and startItem.A.item == 31239
        and startItem.H.item == 31241, "D14 Entry Into the Citadel starts from the Primed Key Mold (item start row, split)")
    local mt = Step("SHATTERED_SUN_OFFENSIVE", "magisters_terrace_chain")
    local inside585 = false
    for _, p in ipairs(mt and mt.places or {}) do
        if p.role == "turnin" and p.npc == 24822 and p.instance == 585 and p.map == nil then inside585 = true end
    end
    CHECK(inside585, "D14 an inside row carries instance and no map (Tyrith in 585)")
end

-- ===========================================================================
-- D15 to D18: alternatives, implication, splits, the RULES invariant
-- ===========================================================================

do
    local b, done = Batch("D15 every alternatives step key exists on its guide")
    for _, g in ipairs(G) do
        if g.alternatives then
            local keys = {}
            for _, s in ipairs(g.steps) do keys[s.key] = true end
            for goal, spec in pairs(g.alternatives) do
                b(type(spec.groups) == "table" and #spec.groups >= 2 and type(spec.prefer) == "table", g.key .. ":" .. goal)
                for _, grp in ipairs(spec.groups or {}) do
                    for _, sk in ipairs(grp) do
                        b(keys[sk] == true, g.key .. ":" .. goal .. ":" .. tostring(sk))
                    end
                end
            end
        end
    end
    done()
    local fl = by.FLYING and by.FLYING.alternatives or {}
    CHECK(fl.flight60 and fl.flight60.prefer.DRUID == 2 and fl.flight280 and fl.flight280.prefer.DRUID == 2,
        "D15 FLYING prefers group 2 for druids on both goals")
    CHECK(fl.flight60 and #fl.flight60.groups == 2 and fl.flight60.groups[1][1] == "expert_riding" and fl.flight60.groups[1][2] == "flying_mount"
        and fl.flight60.groups[2][1] == "flight_form", "D15 flight60 groups: riding and mount, or Flight Form")
    CHECK(fl.flight280 and fl.flight280.groups[1][1] == "artisan_riding" and fl.flight280.groups[1][2] == "epic_flying_mount"
        and fl.flight280.groups[2][1] == "artisan_riding" and fl.flight280.groups[2][2] == "swift_flight_form",
        "D15 flight280 groups both carry artisan_riding")
    local arc = by.ARCATRAZ_KEY and by.ARCATRAZ_KEY.alternatives
    CHECK(arc and arc.door and #arc.door.groups == 2 and arc.door.groups[2][1] == "lockpick_alt"
        and Has(arc.door.groups[1], "kill_warp_splinter") and Has(arc.door.groups[1], "arcatraz_key"), "D15 Arcatraz door: the key chain or Lockpicking")
    local withAlts = 0
    for _, g in ipairs(G) do
        if g.alternatives then withAlts = withAlts + 1 end
    end
    EQ(withAlts, 3, "D15 alternatives on exactly three guides (Shadow Labyrinth, Arcatraz, Flying)")
end

do
    local function QuestIds(s)
        local out = {}
        local function add(v)
            if type(v) == "number" then out[#out + 1] = v
            elseif type(v) == "table" then for _, x in pairs(v) do add(x) end end
        end
        add(s.questId); add(s.altQuestIds); add(s.questIds)
        return out
    end
    local b, done = Batch("D16 every consumedBy names a step of the guide; every impliedBy id a quest of the guide")
    for _, g in ipairs(G) do
        local keys, ids = {}, {}
        for _, s in ipairs(g.steps) do
            keys[s.key] = true
            for _, q in ipairs(QuestIds(s)) do ids[q] = true end
        end
        for _, s in ipairs(g.steps) do
            if s.consumedBy ~= nil then b(keys[s.consumedBy] == true, g.key .. ":" .. s.key) end
            for _, q in ipairs(s.impliedBy or {}) do b(ids[q] == true, g.key .. ":" .. s.key .. " " .. tostring(q)) end
        end
    end
    done()
    CHECK(Step("KARAZHAN_ATTUNEMENT", "second_fragment_steamvault") and Step("KARAZHAN_ATTUNEMENT", "second_fragment_steamvault").consumedBy == "the_second_and_third_fragments"
        and Step("KARAZHAN_ATTUNEMENT", "third_fragment_arcatraz").consumedBy == "the_second_and_third_fragments",
        "D16 the Karazhan fragments are consumed by The Second and Third Fragments")
    CHECK(Step("SSC_ATTUNEMENT", "earthen_signet") and Step("SSC_ATTUNEMENT", "earthen_signet").consumedBy == "turn_in_cudgel"
        and Step("SSC_ATTUNEMENT", "blazing_signet").consumedBy == "turn_in_cudgel", "D16 the signets are consumed by the Cudgel turn-in")
    CHECK(Step("HYJAL_ATTUNEMENT", "vashj_remnant") and Step("HYJAL_ATTUNEMENT", "vashj_remnant").consumedBy == "turn_in_vials"
        and Step("HYJAL_ATTUNEMENT", "kael_remnant").consumedBy == "turn_in_vials", "D16 the vial remnants are consumed by the Vials turn-in")
    CHECK(Step("SHATTERED_HALLS_KEY", "primed_key_mold") and Step("SHATTERED_HALLS_KEY", "primed_key_mold").consumedBy == "entry_into_citadel",
        "D16 the Primed Key Mold is consumed by Entry Into the Citadel")
    local implied = {}
    for _, g in ipairs(G) do
        for _, s in ipairs(g.steps) do
            if s.impliedBy then implied[g.key] = true end
        end
    end
    local want = { KARAZHAN_ATTUNEMENT = true, CAVERNS_OF_TIME_ACCESS = true, NIGHTBANE_SUMMON = true, SHATTERED_HALLS_KEY = true,
        ALDOR_SCRYER_CHOICE = true, HEROIC_MAGISTERS_TERRACE = true }  -- the five linear chains plus the corrected breadcrumb
    local only = true
    for k in pairs(implied) do
        if not want[k] then only = false end
    end
    CHECK(only and implied.KARAZHAN_ATTUNEMENT and implied.CAVERNS_OF_TIME_ACCESS and implied.NIGHTBANE_SUMMON
        and implied.SHATTERED_HALLS_KEY and implied.ALDOR_SCRYER_CHOICE,
        "D16 impliedBy only on the five linear guides and the Magisters' Terrace breadcrumb", table.concat(Keys(implied), ","))
    CHECK(not implied.TK_ATTUNEMENT and not implied.BLACK_TEMPLE_ATTUNEMENT and not implied.NETHERWING_DAILIES,
        "D16 no implication on Tempest Keep, the Black Temple or Netherwing")
end

do
    local b, done = Batch("D17 every faction split has exactly A and H; every side split exactly ALDOR and SCRYER; never SCRYERS")
    local function Walk(v, where)
        if type(v) ~= "table" then return end
        local hasA, hasH, hasAl, hasSc, hasScs, n = v.A ~= nil, v.H ~= nil, v.ALDOR ~= nil, v.SCRYER ~= nil, v.SCRYERS ~= nil, Count(v)
        if hasA or hasH then b(hasA and hasH and n == 2, where) end
        if hasAl or hasSc or hasScs then b(hasAl and hasSc and not hasScs and n == 2, where) end
        for k, x in pairs(v) do Walk(x, where .. "." .. tostring(k)) end
    end
    EachStep(function(g, s, tag) Walk(s, tag) end)
    done()
    local hg = Step("TK_ATTUNEMENT", "hand_of_guldan")
    CHECK(hg and type(hg.questId) == "table" and hg.questId.A == 10680 and hg.questId.H == 10681 and hg.places and hg.places[1].A
        and hg.places[1].A.npc == 21937 and hg.places[1].H.npc == 21938, "D17 The Hand of Gul'dan: quest and giver split A/H")
    local tb = Step("BLACK_TEMPLE_ATTUNEMENT", "tablets_of_baari")
    CHECK(tb and type(tb.questId) == "table" and tb.questId.ALDOR == 10568 and tb.questId.SCRYER == 10683 and tb.places and tb.places[1].ALDOR
        and tb.places[1].ALDOR.npc == 21402 and tb.places[1].SCRYER.npc == 21955, "D17 Tablets of Baa'ri: quest and giver split by side")
end

do
    local b, done = Batch("D18 RULES[p].heroicKeyStanding equals the standing of the one REP step whose window holds p")
    local pairsSeen = 0
    for _, g in ipairs(G) do
        if g.category == "HEROIC" then
            local reps = {}
            for _, s in ipairs(g.steps) do
                if s.kind == "REP" then reps[#reps + 1] = s end
            end
            if #reps > 0 then
                pairsSeen = pairsSeen + 1
                for p = 1, 5 do
                    local holders = {}
                    for _, s in ipairs(reps) do
                        if s.phases.from <= p and (s.phases.to == false or p <= s.phases.to) then holders[#holders + 1] = s end
                    end
                    b(#holders == 1 and holders[1].standing == D.RULES[p].heroicKeyStanding, g.key .. " phase " .. p)
                end
            end
        end
    end
    done()
    EQ(pairsSeen, 5, "D18 five heroic key guides carry a REP pair (Magisters' Terrace has none)")
end

-- ===========================================================================
-- D19: the corrections landed
-- ===========================================================================

do
    local sl = Step("KARAZHAN_ATTUNEMENT", "shadow_lab_key_access")
    CHECK(sl and sl.inside and #sl.inside.npcs == 1 and sl.inside.npcs[1] == 18473 and sl.inside.instance == 556, "D19 Talon King Ikiss 18473 only (not Syth)")
    local coffer = false
    for _, p in ipairs(sl and sl.places or {}) do
        if p.role == "object" and p.object == 187372 and p.instance == 556 then coffer = true end
    end
    CHECK(coffer, "D19 the Talon King's Coffer 187372 is an object place inside Sethekk Halls")
    CHECK(sl and sl.optional == true and Step("KARAZHAN_ATTUNEMENT", "arcatraz_key_access").optional == true,
        "D19 the two Karazhan access steps are optional")
    for _, k in ipairs({ "HEROIC_TEMPEST_KEEP", "HEROIC_CAVERNS_OF_TIME", "HEROIC_HELLFIRE", "HEROIC_COILFANG", "HEROIC_AUCHINDOUN" }) do
        local c = Step(k, "communal_key")
        CHECK(c and c.phases.from == 2 and c.optional == true, "D19 " .. k .. " communal_key from Phase 2, optional")
    end
    local dumphry = 0
    for _, sk in ipairs({ "grand_master_smith", "smiths_request", "hotter_than_hell" }) do
        local s = Step("SHATTERED_HALLS_KEY", sk)
        local hit = false
        for _, p in ipairs(s and s.places or {}) do
            local a = p.A
            if type(a) == "table" and a.npc == 21209 and a.x == 51.1 and a.y == 60.3 then hit = true end
        end
        if hit then dumphry = dumphry + 1 end
    end
    EQ(dumphry, 3, "D19 Dumphry 21209 at 51.1, 60.3 on three Shattered Halls steps")
    local humphry = false
    EachStep(function(g, s, tag)
        for _, p in ipairs(s.places or {}) do
            for _, r in pairs(p.role and { p } or p) do
                if type(r) == "table" and r.npc == 16823 then humphry = true end
            end
        end
    end)
    CHECK(not humphry, "D19 Humphry 16823 appears nowhere")
    local ss = Step("HEROIC_MAGISTERS_TERRACE", "sunwell_summons")
    CHECK(ss and ss.optional == true and Has(ss.altQuestIds, 11482) and Has(ss.impliedBy, 11488) and Has(ss.impliedBy, 11490)
        and Has(ss.impliedBy, 11492), "D19 the Magisters' Terrace breadcrumb is optional with its twin and implications")
    -- research-3 #9 and #10: the raid rows the research listed are recommendations; the Black Temple's
    -- one hard row is the pledge (D25), so the raid rows are tested by name here
    local soft, raidRows = true, 0
    local raid = { SSC_ATTUNEMENT = true, TK_ATTUNEMENT = true, HYJAL_ATTUNEMENT = true }
    for _, k in ipairs({ "HYJAL_ATTUNEMENT", "BLACK_TEMPLE_ATTUNEMENT" }) do
        for _, p in ipairs(by[k] and by[k].prerequisites or {}) do
            if raid[p.guide] then
                raidRows = raidRows + 1
                if p.hard ~= false then soft = false end
            end
        end
    end
    CHECK(soft and raidRows == 5 and #by.HYJAL_ATTUNEMENT.prerequisites == 2, "D19 Hyjal and Black Temple raid prerequisites are recommendations (two and three)")
    local spendN, spend = 0, nil
    for _, s in ipairs(Steps("BADGES")) do
        if s.key:match("^spend_p%d$") then spendN = spendN + 1 end
        if s.key == "spend" then spend = s end
    end
    CHECK(spendN == 0 and spend ~= nil and type(spend.detailByPhase) == "table" and spend.note == true and spend.detail == nil,
        "D19 BADGES has no spend_pN, one spend note with detailByPhase and no detail")
    local phasesOk = spend ~= nil
    for n = 1, 5 do
        if not (spend and type(spend.detailByPhase[n]) == "string" and #spend.detailByPhase[n] > 0) then phasesOk = false end
    end
    CHECK(phasesOk, "D19 spend.detailByPhase 1..5 present")
    local za = Step("BADGES", "za_quests")
    CHECK(za and za.related and Has(za.related.quests, 11130) and Has(za.related.quests, 11132) and Has(za.related.quests, 11166),
        "D19 za_quests chain ids 11130, 11132, 11166 (Promises, Promises, not A Troll Among Trolls)")
    CHECK(za and (za.detail or ""):find("Promises, Promises", 1, true) ~= nil and (za.detail or ""):find("A Troll Among Trolls (11165)", 1, true) == nil,
        "D19 za_quests detail names Promises, Promises as the prerequisite")
    local sso = Step("BADGES", "sso_supplies")
    CHECK(sso and Has(sso.questIds, 11516) and Has(sso.questIds, 11877) and #sso.questIds == 6, "D19 sso_supplies includes 11516 and 11877")
    local ltf = Step("FLYING", "learning_to_fly")
    CHECK(ltf and ltf.phases.from == 4 and ltf.optional == true, "D19 learning_to_fly from Phase 4, optional")
    CHECK(ltf and (ltf.detail or ""):find("launch. It points", 1, true) ~= nil, "D19 learning_to_fly detail re-joined after the correction")
    local arcus, illidan = Step("NETHERWING_DAILIES", "commander_arcus"), Step("NETHERWING_DAILIES", "lord_illidan")
    CHECK(arcus and arcus.questId == 11100 and Has(arcus.altQuestIds, 11095) and arcus.questName and arcus.questName.ALDOR == "Commander Arcus"
        and arcus.questName.SCRYER == "Commander Hobb", "D19 Netherwing has Commander Arcus 11100 with Hobb 11095")
    CHECK(illidan and illidan.questId == 11108, "D19 Netherwing has Lord Illidan Stormrage 11108")
    local kta, dt, cd, egg = Step("NETHERWING_DAILIES", "kill_them_all"), Step("NETHERWING_DAILIES", "deadliest_trap_daily"),
        Step("NETHERWING_DAILIES", "choose_drake"), Step("NETHERWING_DAILIES", "egg_hunt")
    CHECK(kta and kta.questId == 11099 and Has(kta.altQuestIds, 11094), "D19 Kill Them All 11099 with Scryer twin 11094")
    CHECK(dt and dt.questId == 11101 and Has(dt.altQuestIds, 11097) and dt.daily == true, "D19 The Deadliest Trap 11101 with twin 11097, daily")
    CHECK(cd and cd.questId == 11109 and #cd.altQuestIds == 5 and Has(cd.altQuestIds, 11110) and Has(cd.altQuestIds, 11114),
        "D19 the drake choice 11109 with twins 11110 to 11114")
    CHECK(egg and egg.questId == 11049 and egg.daily == nil, "D19 The Great Netherwing Egg Hunt is not a daily")
    local sc, hk = Step("SHATTERED_SUN_OFFENSIVE", "scryers_scryer"), Step("SHATTERED_SUN_OFFENSIVE", "hard_to_kill")
    CHECK(sc and sc.questId == 11490 and hk and hk.questId == 11492, "D19 SSO has The Scryer's Scryer 11490 and Hard to Kill 11492")
    local mt = Step("SHATTERED_SUN_OFFENSIVE", "magisters_terrace_chain")
    local tyrith = false
    for _, p in ipairs(mt and mt.places or {}) do
        if p.role == "turnin" and p.npc == 24822 then tyrith = true end
    end
    CHECK(mt and mt.questId == 11488 and tyrith, "D19 Magisters' Terrace 11488 is handed in to Tyrith 24822")
    local intro = Step("SHATTERED_SUN_OFFENSIVE", "intro_shattrath")
    CHECK(intro and intro.questId == 11481 and Has(intro.altQuestIds, 11482) and intro.places and intro.places[1].ALDOR
        and intro.places[1].ALDOR.npc == 18537 and intro.places[1].SCRYER.npc == 18594, "D19 Crisis at the Sunwell 11481 with Duty Calls 11482, side-split givers")
    local kal = Step("NIGHTBANE_SUMMON", "kalynnas_request")
    CHECK(kal and kal.inside and #kal.inside.npcs == 1 and kal.inside.npcs[1] == 16807, "D19 Kalynna's Request keeps 16807 only")
    local fx = Step("ARCATRAZ_KEY", "full_triangle")
    CHECK(fx and fx.needs and fx.needs.id == 29026 and fx.needs.anyOf == nil, "D19 Full Triangle needs 29026 only")
    local sd = Step("ARCATRAZ_KEY", "special_delivery")
    CHECK(sd and sd.provided and sd.provided.id == 29106 and sd.provided.name == "Ata'mal Crystal", "D19 Special Delivery provides the Ata'mal Crystal 29106")
    local gates = true
    for _, sk in ipairs({ "kill_warp_splinter", "kill_pathaleon", "break_into_arcatraz" }) do
        local s = Step("ARCATRAZ_KEY", sk)
        if not (s and s.level == 70) then gates = false end
    end
    CHECK(gates, "D19 the three How to Break Into the Arcatraz steps lock at level 70")
    local st = Step("BADGES", "stasis_quest")
    CHECK(st and st.inside and st.inside.boss == nil and st.inside.npcs == nil and (st.detail or ""):find("Pax'ivi", 1, true) ~= nil
        and (st.detail or ""):find("kill Yor", 1, true) == nil, "D19 stasis_quest frees Pax'ivi at the front chamber, no boss")
    local nb = Step("NIGHTBANE_SUMMON", "nightbane")
    CHECK(nb and (nb.detail or ""):find("side entrance", 1, true) ~= nil and (nb.detail or ""):find("masters_terrace", 1, true) == nil,
        "D19 the urn step routes by the side entrance and names no step key")
    local sp1 = by.BADGES and spend and spend.detailByPhase[1] or ""
    CHECK(sp1:find("Brooch of Deftness", 1, true) == nil and sp1:find("Voodoo Shaker", 1, true) == nil
        and sp1:find("Fetish of the Primal Gods", 1, true) == nil, "D19 the Phase 1 spend list lost the three Phase 4 items")
    local sp4 = spend and spend.detailByPhase[4] or ""
    CHECK(sp4:find("Hauberk of the Furious Elements, Vestments of Hibernation", 1, true) ~= nil, "D19 Vestments of Hibernation sits in the chest list")
    local ebt = Step("BLACK_TEMPLE_ATTUNEMENT", "entry_into_black_temple")
    CHECK(ebt and (ebt.detail or ""):find("150 Ashtongue Deathsworn and 150 Sha'tar", 1, true) ~= nil, "D19 Entry Into the Black Temple pays 150 and 150")
end

-- ===========================================================================
-- D20: the drawn strings
-- ===========================================================================

do
    local b, done = Batch("D20 no title, name, sentence, detail or note contains an underscore or a client prefix")
    local function Text(v, where)
        if type(v) == "string" then
            b(v:find("_", 1, true) == nil and v:find("C_", 1, true) == nil, where)
        elseif type(v) == "table" then
            for k, x in pairs(v) do Text(x, where .. "." .. tostring(k)) end
        end
    end
    for _, g in ipairs(G) do
        Text(g.title, g.key .. ".title"); Text(g.name, g.key .. ".name"); Text(g.summary, g.key .. ".summary")
        Text(g.unlocks, g.key .. ".unlocks"); Text(g.phase.note, g.key .. ".phase.note")
        for _, s in ipairs(g.steps) do
            local tag = g.key .. ":" .. s.key
            Text(s.title, tag .. ".title"); Text(s.detail, tag .. ".detail"); Text(s.detailByPhase, tag .. ".detailByPhase")
            Text(s.questName, tag .. ".questName"); Text(s.cost, tag .. ".cost")
            if s.item then Text(s.item.name, tag .. ".item.name") end
            if s.needs then Text(s.needs.name, tag .. ".needs.name") end
            if s.provided then Text(s.provided.name, tag .. ".provided.name") end
            if s.pouch then Text(s.pouch.name, tag .. ".pouch.name") end
            if s.inside then Text(s.inside.boss, tag .. ".inside.boss") end
            Text(s.factionName, tag .. ".factionName")
            for i, p in ipairs(s.places or {}) do
                for _, r in pairs(p.role and { p } or p) do
                    if type(r) == "table" then Text(r.name, tag .. ".places" .. i .. ".name"); Text(r.zone, tag .. ".places" .. i .. ".zone") end
                end
            end
            for _, row in ipairs(s.list or {}) do Text(row.name, tag .. ".list.name"); Text(row.bonus, tag .. ".list.bonus") end
            for _, row in ipairs(s.choice or {}) do Text(row.name, tag .. ".choice.name") end
        end
    end
    for p = 1, 5 do
        Text(D.RULES[p].sentences, "RULES[" .. p .. "].sentences")
        Text(D.PHASES[p].notes, "PHASES[" .. p .. "].notes"); Text(D.PHASES[p].name, "PHASES[" .. p .. "].name")
    end
    for _, c in ipairs(D.CATEGORIES) do Text(c.label, "CATEGORIES." .. c.key) end
    for id, name in pairs(D.INSTANCES or {}) do Text(name, "INSTANCES[" .. id .. "]") end
    done()
    local b2, done2 = Batch("D20 no drawn prose shouts a word in capitals (NOT, FRONT, SIDE ENTRANCE) or carries a plus sign before a number")
    EachStep(function(g, s, tag)
        local d = s.detail or ""
        b2(d:find(" NOT ", 1, true) == nil and d:find("FRONT", 1, true) == nil and d:find("SIDE ENTRANCE", 1, true) == nil
            and d:find("%+%d") == nil, tag)
    end)
    done2()

    -- the player's prose: no research source or note, no database id in brackets, no doubled stop
    local banned = { "RXP", "Wowhead", "CMaNGOS", "AtlasLoot", "Questie", "wiki", "Wiki", "database", "in the data",
        "task brief", "unverified", "requiredMaxRep", "Magister's", "Thrallmar-free", "Sunsail" }
    local function Clean(v)
        for _, w in ipairs(banned) do
            if v:find(w, 1, true) then return false, w end
        end
        if v:find("%f[%a]%l+%u") then return false, "camelCase" end
        if v:find("%f[%a]mold%f[%A]") then return false, "mold" end
        if v:find("[!?]%.%s") or v:find("[!?]%.$") then return false, "!." end
        local at = 1
        while true do
            local i = v:find("%. %l", at)
            if not i then break end
            if v:sub(i - 3, i - 1) ~= "..." then return false, ". lower" end
            at = i + 1
        end
        if v:find("%(%d%d%d%d+[,):]") or v:find(", %d%d%d%d%d%d?%)") then return false, "bare id" end
        for _, label in ipairs({ "instance", "map", "npc", "object" }) do
            if v:find("%(" .. label .. " %d") then return false, label .. " id" end
        end
        if v:find("%.%.%.%.") and not v:find("Don't Stop Now....", 1, true) then return false, "...." end
        return true
    end
    local b3, done3 = Batch("D20 no drawn prose names a research source, carries a database id in brackets, a camelCase word or a doubled stop")
    local function Prose(v, where)
        if type(v) == "string" then
            local ok, why = Clean(v)
            b3(ok, where .. " " .. tostring(why))
        elseif type(v) == "table" then
            for k, x in pairs(v) do Prose(x, where .. "." .. tostring(k)) end
        end
    end
    for _, g in ipairs(G) do
        Prose(g.summary, g.key .. ".summary"); Prose(g.unlocks, g.key .. ".unlocks"); Prose(g.phase.note, g.key .. ".phase.note")
        for _, s in ipairs(g.steps) do
            local tag = g.key .. ":" .. s.key
            Prose(s.title, tag .. ".title"); Prose(s.detail, tag .. ".detail"); Prose(s.detailByPhase, tag .. ".detailByPhase")
        end
    end
    done3()
    local b4, done4 = Batch("D20 no questName carries an aside in brackets (Grim(oire) Business is the game's own)")
    EachStep(function(g, s, tag)
        local qn = s.questName
        for _, v in pairs(type(qn) == "table" and qn or { qn }) do
            if type(v) == "string" and v ~= "Grim(oire) Business" then b4(v:find("(", 1, true) == nil, tag) end
        end
    end)
    done4()
    local b5, done5 = Batch("D20 needsStanding sits on ITEM steps only (3.8.3), and no start row is named by a sentence")
    EachStep(function(g, s, tag)
        if s.needsStanding ~= nil then b5(s.kind == "ITEM", tag) end
        for _, p in ipairs(s.places or {}) do
            for _, r in pairs(p.role and { p } or p) do
                if type(r) == "table" and type(r.name) == "string" then b5(r.name:find("^Started by") == nil, tag) end
            end
        end
    end)
    done5()
    local tv = Step("HYJAL_ATTUNEMENT", "turn_in_vials")
    CHECK(tv and tv.needsStanding == nil, "D20 The Vials of Eternity needs no Scale of the Sands standing")
    local ov = Step("HEROIC_COILFANG", "orders_from_lady_vashj")
    local ostart
    for _, p in ipairs(ov and ov.places or {}) do if p.role == "start" then ostart = p end end
    CHECK(ostart and ostart.item == 24367 and ostart.instance == nil and ostart.name == "Orders from Lady Vashj",
        "D20 Orders from Lady Vashj starts from its item (24367), no door on the start row")
    local function Count(text, plain)
        local n, at = 0, 1
        while true do
            local i = (text or ""):find(plain, at, true)
            if not i then return n end
            n, at = n + 1, i + 1
        end
    end
    local ap, ab = Step("BLACK_TEMPLE_ATTUNEMENT", "akamas_promise"), Step("SKYGUARD_SKETTIS", "adversarial_blood")
    CHECK(ap and not ap.detail:find("10708", 1, true) and Has(ap.altQuestIds, 10708), "D20 Akama's medallion: the twin id lives in altQuestIds, not the prose")
    CHECK(ab and Count(ab.detail, "Tokens of the Descendants") == 1, "D20 adversarial_blood names Tokens of the Descendants once")
    local ac, l65 = Step("ARCATRAZ_KEY", "assisting_consortium"), Step("SHADOW_LABYRINTH_KEY", "level_65")
    CHECK(ac and Count(ac.detail, "talk to Khay'ji directly") == 1, "D20 assisting_consortium says talk to Khay'ji directly once")
    CHECK(l65 and Count(l65.detail, "68 or later") == 1 and not l65.detail:find("68 to 70", 1, true), "D20 level_65 gives one tuning and one plan")
    local wf = Step("OGRILA_UNLOCK", "friendly")
    CHECK(wf and wf.detail:find("A Special Thank You", 1, true) and not wf.detail:find("unverified", 1, true), "D20 Ogri'la Friendly reads as one clean sentence")
    local cd, hd2 = Step("NETHERWING_DAILIES", "choose_drake"), Step("BADGES", "heroic_daily")
    CHECK(cd and cd.questName == "Jorus the Cobalt Netherwing Drake" and hd2 and hd2.questName == "Wanted",
        "D20 the drake and heroic daily quest names are names, not asides")
    local b6, done6 = Batch("D20 the Shattered Sun stage steps are titled as the dailies they are")
    for _, s in ipairs(Steps("SHATTERED_SUN_OFFENSIVE")) do
        if s.daily and s.key:find("^stage") then b6(s.title:find("^Daily: ") ~= nil, s.key) end
    end
    done6()
    local fm2, em2 = Step("FLYING", "flying_mount"), Step("FLYING", "epic_flying_mount")
    CHECK(fm2 and em2 and not fm2.item.name:find("Gryphon") and not em2.item.name:find("Gryphon")
        and not by.FLYING.summary:find("Netherwing Ledge refuses", 1, true),
        "D20 the FLYING mounts are named for both factions and the summary puts Artisan Riding on the Blood Oath")
    local hk = Step("SHATTERED_HALLS_KEY", "hotter_than_hell")
    CHECK(hk and hk.title == "Fire the mould in a dead Fel Reaver" and hk.needs.name == "Charred Key Mold" and hk.provided.name == "Unfired Key Mold",
        "D20 mould in prose, the in-game Key Mold item names kept")
end

-- ===========================================================================
-- D21 to D23: the BADGES merge, KILL_MAPS, INSTANCES
-- ===========================================================================

do
    local B = Steps("BADGES")
    EQ(#B, 28, "D21 BADGES: 21 route steps plus the seven vendor notes")
    local function W(k) local s = Step("BADGES", k); return s and s.phases end
    local function Is(k, f, t) local w = W(k); return w ~= nil and w.from == f and w.to == t end
    CHECK(Is("bank_for_p4", 3, 3), "D21 bank_for_p4 window 3..3")
    CHECK(Is("no_new_sources", 2, 2), "D21 no_new_sources window 2..2")
    CHECK(Is("heroic_mechanar", 1, 1) and Is("heroic_botanica", 1, 1) and Is("heroic_shattered_halls", 1, 1), "D21 the three Phase 1 heroics 1..1")
    CHECK(Is("heroic_daily", 1, 5), "D21 heroic_daily window 1..5 (the union of five routes)")
    CHECK(Is("karazhan", 4, 5) and Is("zulaman", 4, 5), "D21 karazhan and zulaman 4..5")
    CHECK(Is("stasis_quest", 1, 3), "D21 stasis_quest 1..3 (three routes)")
    local hd = Step("BADGES", "heroic_daily")
    CHECK(hd and hd.questIds and #hd.questIds == 16 and Has(hd.questIds, 11499) and hd.daily == true and hd.questMode == "ANY"
        and hd.optional == false, "D21 heroic_daily: 16 ids incl. 11499, daily, ANY, counted copy wins")
    local ss = Step("BADGES", "sso_supplies")
    CHECK(ss and ss.daily == true and ss.questMode == "ANY", "D21 sso_supplies daily, ANY")
    local kz, za = Step("BADGES", "karazhan"), Step("BADGES", "zulaman")
    CHECK(kz and kz.kind == "KILL" and kz.inside and kz.inside.full == true and kz.inside.instance == 532 and kz.weekly == true
        and type(kz.inside.encounters) == "table" and #kz.inside.encounters == 11, "D21 karazhan full clear, weekly, eleven encounters")
    CHECK(za and za.inside and za.inside.full == true and za.inside.instance == 568 and za.weekly == true
        and #za.inside.encounters == 6, "D21 zulaman full clear, weekly, six encounters")
    local zq = Step("BADGES", "za_quests")
    CHECK(zq and zq.questMode == "ALL" and zq.questId == 11171 and Has(zq.questIds, 11171) and Has(zq.questIds, 11163) and #zq.questIds == 2,
        "D21 za_quests questMode ALL over 11171 and 11163")
    local notes, b, done = { no_new_sources = true, bank_for_p4 = true, spend = true, heroics_overview = true },
        Batch("D21 every BADGES step: a window, KILL steps weekly, TALK and advice steps are notes under SPEND")
    local vendors = 0
    for _, s in ipairs(B) do
        b(type(s.phases) == "table", s.key)
        if s.kind == "KILL" then b(s.weekly == true, s.key .. " weekly") end
        if s.kind == "TALK" then
            vendors = vendors + 1
            b(s.note == true and s.section == "SPEND" and s.places and #s.places == 1 and s.places[1].role == "vendor", s.key)
        end
        if notes[s.key] then b(s.note == true, s.key .. " note") end
        if s.key ~= "spend" and s.kind ~= "TALK" then b(s.section == nil, s.key .. " section") end
    end
    done()
    EQ(vendors, 7, "D21 seven vendor notes")
    local ho = Step("BADGES", "heroics_overview")
    CHECK(ho and ho.kind == "MANUAL" and ho.note == true and type(ho.list) == "table" and #ho.list >= 15
        and type(ho.list[1].name) == "string" and type(ho.list[1].instance) == "number" and type(ho.list[1].badges) == "number",
        "D21 the heroics overview is a note with a list of rows")
    local mgt, early = nil, 0
    for _, row in ipairs(ho and ho.list or {}) do
        if row.instance == 585 then mgt = row end
        if row.from == nil then early = early + 1 end
    end
    CHECK(mgt and mgt.badges == 4 and mgt.from == 5 and early == 15, "D21 the heroics list adds Magisters' Terrace (4) from Phase 5 to the fifteen")
    local hbp = ho and ho.detailByPhase or {}
    CHECK(ho and ho.detail == nil and type(hbp[1]) == "string" and type(hbp[5]) == "string"
        and hbp[5]:find("Magisters' Terrace", 1, true) and not hbp[1]:find("Magisters' Terrace", 1, true),
        "D21 the heroics overview words each phase's lap (detailByPhase only)")
    CHECK(by.BADGES.phase.introduced == 1 and by.BADGES.phase.requiredUntil == false and by.BADGES.minLevel == 70, "D21 BADGES guide: introduced 1, never dropped, level 70")
end

do
    local K = D.KILL_MAPS or {}
    local b, done = Batch("D22 KILL_MAPS covers every inside.instance of a KILL step")
    EachStep(function(g, s, tag)
        if s.kind == "KILL" and s.inside then b(K[s.inside.instance] == true, tag) end
    end)
    done()
    CHECK(K[530] == true, "D22 KILL_MAPS holds Outland 530")
    local extra = true
    local named = { [530] = true }
    -- the bosses a KILL row lists from another raid (the generator's NPC_MAP): Tempest Keep: The
    -- Eye and Hyjal Summit are armed through their bosses, not through an inside.instance
    local NPC_MAP = { [19622] = 550, [19514] = 550, [17968] = 534, [17767] = 534 }
    EachStep(function(g, s)
        if s.kind == "KILL" and s.inside then
            named[s.inside.instance] = true
            for _, npc in ipairs(s.inside.npcs or {}) do
                if NPC_MAP[npc] then named[NPC_MAP[npc]] = true end
            end
        end
    end)
    CHECK(K[550] == true and K[534] == true, "D22 KILL_MAPS arms Tempest Keep: The Eye (550) and Hyjal Summit (534) for Kael'thas and Archimonde")
    for id in pairs(K) do
        if not named[id] then extra = false end
    end
    CHECK(extra, "D22 KILL_MAPS names nothing a KILL step does not")
end

do
    local I = D.INSTANCES or {}
    local want = { 532, 565, 544, 548, 550, 534, 564, 568, 580, 543, 542, 540, 547, 546, 545, 557, 558, 556, 555, 554, 553, 552, 560, 269, 585 }
    local all = true
    for _, id in ipairs(want) do
        if type(I[id]) ~= "string" then all = false end
    end
    CHECK(all, "D23 INSTANCES has all 25")
    CHECK(I[530] == "Outland" and Count(I) == 26, "D23 plus Outland 530, nothing else")
    CHECK(I[550] == "Tempest Keep: The Eye" and I[585] == "Magisters' Terrace" and I[269] == "The Black Morass", "D23 display names")
    local b, done = Batch("D23 every instance a step or place names is in INSTANCES")
    EachStep(function(g, s, tag)
        if s.inside then b(I[s.inside.instance] ~= nil, tag) end
        if s.auto and s.auto.enteredInstance then b(I[s.auto.enteredInstance] ~= nil, tag .. " auto") end
        for i, p in ipairs(s.places or {}) do
            for _, r in pairs(p.role and { p } or p) do
                if type(r) == "table" and r.instance then b(I[r.instance] ~= nil, tag .. ":" .. i) end
            end
        end
        for _, row in ipairs(s.list or {}) do b(I[row.instance] ~= nil, tag .. " list") end
    end)
    for _, g in ipairs(G) do
        if g.instance then b(I[g.instance] ~= nil, g.key .. ".instance") end
    end
    done()
end

-- ===========================================================================
-- D24 to D29: unlock, prerequisites, accountWide, minLevel, auto, factionName
-- ===========================================================================

do
    local u = by.KARAZHAN_ATTUNEMENT.unlock
    CHECK(u and u.quest == 9837 and u.items and u.items[1] == 24490, "D24 Karazhan unlock: quest 9837 or The Master's Key")
    local heroics = { HEROIC_HELLFIRE = { 30622, 30637, 265830, 265826 }, HEROIC_COILFANG = { 30623, 265843 }, HEROIC_AUCHINDOUN = { 30633, 265845 },
        HEROIC_TEMPEST_KEEP = { 30634, 265847 }, HEROIC_CAVERNS_OF_TIME = { 30635, 265849 } }
    for k, ids in pairs(heroics) do
        local x = by[k].unlock
        local okIds = x and x.items and #x.items == #ids and x.quest == nil
        for _, id in ipairs(ids) do
            if not Has(x and x.items, id) then okIds = false end
        end
        CHECK(okIds, "D24 " .. k .. " unlock items (key and Communal key)")
    end
    local mgt = by.HEROIC_MAGISTERS_TERRACE.unlock
    CHECK(mgt and mgt.quest == 11492 and mgt.items == nil, "D24 Magisters' Terrace unlock: Hard to Kill 11492")
    CHECK(by.SHADOW_LABYRINTH_KEY.unlock and by.SHADOW_LABYRINTH_KEY.unlock.items[1] == 27991, "D24 Shadow Labyrinth unlock 27991")
    CHECK(by.SHATTERED_HALLS_KEY.unlock and by.SHATTERED_HALLS_KEY.unlock.items[1] == 28395, "D24 Shattered Halls unlock 28395")
    CHECK(by.ARCATRAZ_KEY.unlock and by.ARCATRAZ_KEY.unlock.items[1] == 31084, "D24 Arcatraz unlock 31084")
    CHECK(by.CAVERNS_OF_TIME_ACCESS.unlock and by.CAVERNS_OF_TIME_ACCESS.unlock.quest == 10285, "D24 Caverns of Time access unlock 10285")
    local n = 0
    for _, g in ipairs(G) do
        if g.unlock ~= nil then n = n + 1 end
    end
    EQ(n, 11, "D24 eleven unlock proofs, no others")
end

do
    local b, done = Batch("D25 every prerequisite names an emitted guide, never itself, with a boolean hard")
    for _, g in ipairs(G) do
        for _, p in ipairs(g.prerequisites) do
            b(by[p.guide] ~= nil and p.guide ~= g.key and type(p.hard) == "boolean", g.key .. " -> " .. tostring(p.guide))
        end
    end
    done()
    local function Names(k, target)
        for _, p in ipairs(by[k].prerequisites) do
            if p.guide == target then return true end
        end
        return false
    end
    CHECK(Names("ARCATRAZ_KEY", "FLYING") and Names("OGRILA_UNLOCK", "FLYING") and Names("SKYGUARD_SKETTIS", "FLYING")
        and Names("NETHERWING_DAILIES", "FLYING"), "D25 Arcatraz, Ogri'la, Skyguard and Netherwing name FLYING")
    local stale = false
    for _, g in ipairs(G) do
        for _, p in ipairs(g.prerequisites) do
            if p.guide == "FLYING_BASIC" or p.guide == "FLYING_EPIC" or p.guide:match("^BADGES_PHASE") or p.guide == "BADGE_VENDORS" then stale = true end
        end
    end
    CHECK(not stale, "D25 no prerequisite names a merged research key")
    CHECK(Names("KARAZHAN_ATTUNEMENT", "CAVERNS_OF_TIME_ACCESS") and Names("NIGHTBANE_SUMMON", "KARAZHAN_ATTUNEMENT"), "D25 Karazhan needs Caverns of Time access; Nightbane needs Karazhan")
    CHECK(Names("SHATTERED_SUN_OFFENSIVE", "ALDOR_SCRYER_CHOICE") and #by.SHATTERED_SUN_OFFENSIVE.prerequisites == 1,
        "D25 the Shattered Sun needs the pledge and nothing else")
    CHECK(Names("BLACK_TEMPLE_ATTUNEMENT", "HYJAL_ATTUNEMENT") and Names("BLACK_TEMPLE_ATTUNEMENT", "SSC_ATTUNEMENT")
        and Names("BLACK_TEMPLE_ATTUNEMENT", "TK_ATTUNEMENT") and #by.BLACK_TEMPLE_ATTUNEMENT.prerequisites == 4,
        "D25 the Black Temple names the three raid attunements (as recommendations) and the pledge, nothing else")
    -- research-3 #10: "Hard requirements: level 70 plus an Aldor or Scryer pledge". The research rows
    -- come first in research order, the PREREQS hand row last, hard; level 70 is the guide's minLevel.
    local bt = by.BLACK_TEMPLE_ATTUNEMENT.prerequisites
    CHECK(bt[1] and bt[1].guide == "HYJAL_ATTUNEMENT" and bt[2] and bt[2].guide == "SSC_ATTUNEMENT" and bt[3] and bt[3].guide == "TK_ATTUNEMENT"
        and bt[4] and bt[4].guide == "ALDOR_SCRYER_CHOICE" and bt[4].hard == true and by.BLACK_TEMPLE_ATTUNEMENT.minLevel == 70,
        "D25 the Black Temple needs the Aldor or Scryers pledge (hard, last row) and level 70, research-3 #10")
    CHECK(Names("BLACK_TEMPLE_ATTUNEMENT", "ALDOR_SCRYER_CHOICE") and not Names("HYJAL_ATTUNEMENT", "ALDOR_SCRYER_CHOICE"),
        "D25 the pledge is a prerequisite of the Black Temple only, never of Hyjal (research-3 #9)")
end

do
    local want = { KARAZHAN_ATTUNEMENT = true, SSC_ATTUNEMENT = true, TK_ATTUNEMENT = true, HYJAL_ATTUNEMENT = true, BLACK_TEMPLE_ATTUNEMENT = true }
    local exact = true
    for _, g in ipairs(G) do
        if (want[g.key] == true) ~= (g.accountWide == true) then exact = false end
    end
    CHECK(exact, "D26 exactly the five raid gates carry accountWide = true")
end

do
    local b, done = Batch("D27 every guide has a numeric minLevel between 60 and 70")
    for _, g in ipairs(G) do
        b(type(g.minLevel) == "number" and g.minLevel >= 60 and g.minLevel <= 70, g.key)
    end
    done()
    EQ(by.NIGHTBANE_SUMMON.minLevel, 70, "D27 Nightbane 70")
    EQ(by.ALDOR_SCRYER_CHOICE.minLevel, 60, "D27 Aldor or Scryers 60 (from A'dal's quest level)")
    EQ(by.FLYING.minLevel, 68, "D27 FLYING 68 (the druid value)")
    EQ(by.KARAZHAN_ATTUNEMENT.minLevel, 68, "D27 Karazhan 68 from its LEVEL step")
    EQ(by.SHADOW_LABYRINTH_KEY.minLevel, 65, "D27 Shadow Labyrinth 65")
    EQ(by.ARCATRAZ_KEY.minLevel, 67, "D27 Arcatraz 67")
    EQ(by.CAVERNS_OF_TIME_ACCESS.minLevel, 66, "D27 Caverns of Time 66")
    local adal = nil
    for _, s in ipairs(Steps("ALDOR_SCRYER_CHOICE")) do
        if s.kind == "QUEST" and s.level == 60 then adal = s end
    end
    CHECK(adal ~= nil, "D27 A'dal's quest step carries level 60 (a lock, not a goal)")
end

do
    local b, done = Batch("D28 every MANUAL step that is not a note carries auto")
    EachStep(function(g, s, tag)
        if s.kind == "MANUAL" and not s.note then
            local a = s.auto
            b(type(a) == "table" and ((type(a.enteredInstance) == "number" and type(a.heroic) == "boolean") or a.dungeonDifficulty == 2), tag)
        end
    end)
    done()
    local gd = Step("GRUUL_MAGTHERIDON", "gruul_door")
    CHECK(gd and gd.auto and gd.auto.enteredInstance == 565, "D28 gruul_door enters 565")
    local md = Step("GRUUL_MAGTHERIDON", "magtheridon_door")
    CHECK(md and md.auto and md.auto.enteredInstance == 544, "D28 magtheridon_door enters 544")
    local ez = Step("ZUL_AMAN", "enter_zulaman")
    CHECK(ez and ez.auto and ez.auto.enteredInstance == 568, "D28 enter_zulaman enters 568")
    local og = Step("SHADOW_LABYRINTH_KEY", "open_gate")
    CHECK(og and og.auto and og.auto.enteredInstance == 555, "D28 open_gate enters 555 (from the guide's instance)")
    local heroics = 0
    for _, g in ipairs(G) do
        if g.category == "HEROIC" then
            local sh = Step(g.key, "set_heroic")
            if sh and sh.auto and sh.auto.dungeonDifficulty == 2 and sh.kind == "MANUAL" then heroics = heroics + 1 end
        end
    end
    EQ(heroics, 6, "D28 set_heroic reads the dungeon difficulty on all six heroic guides")
    local es = Step("SUNWELL_PLATEAU", "enter_sunwell")
    CHECK(es and es.auto and es.auto.enteredInstance == 580, "D28 enter_sunwell enters 580")
end

do
    local b, done = Batch("D29 every REP step has factionName (string, or split with both sides)")
    local names = { [946] = "Honor Hold", [947] = "Thrallmar", [942] = "Cenarion Expedition", [1011] = "Lower City", [935] = "The Sha'tar",
        [989] = "Keepers of Time", [933] = "The Consortium", [1077] = "Shattered Sun Offensive", [1015] = "Netherwing", [1038] = "Ogri'la",
        [1031] = "Sha'tari Skyguard", [967] = "The Violet Eye", [1012] = "Ashtongue Deathsworn", [990] = "The Scale of the Sands",
        [932] = "The Aldor", [934] = "The Scryers" }
    local b2, done2 = Batch("D29 factionName matches Faction.db2 for the id")
    EachStep(function(g, s, tag)
        if s.kind == "REP" then
            local fn = s.factionName
            if type(s.factionId) == "table" then
                b(type(fn) == "table" and type(fn.A) == "string" and type(fn.H) == "string", tag)
                b2(type(fn) == "table" and fn.A == names[s.factionId.A] and fn.H == names[s.factionId.H], tag)
            else
                b(type(fn) == "string" and #fn > 0, tag)
                b2(fn == names[s.factionId], tag)
            end
        end
    end)
    done(); done2()
end

-- ===========================================================================
-- D30 to D34
-- ===========================================================================

do
    local chains = { enraged_spirits = 10481, oronok_lessons = 10519, gromtor_charge = 10523, artor_charge = 10541, borak_charge = 10579 }
    local okc, n = true, 0
    for k, last in pairs(chains) do
        local s = Step("TK_ATTUNEMENT", k)
        if s and s.questMode == "CHAIN" and s.questId == last and s.questIds[#s.questIds] == last then n = n + 1 else okc = false end
    end
    CHECK(okc and n == 5, "D30 the five TK CHAIN steps end with their questId")
    local tkc = false
    for _, s in ipairs(Steps("TK_ATTUNEMENT")) do
        if s.consumedBy then tkc = true end
    end
    CHECK(not tkc, "D30 no consumedBy on Tempest Keep")
    local b, done = Batch("D30 no ITEM or KILL step with questId carries consumedBy")
    EachStep(function(g, s, tag)
        if (s.kind == "ITEM" or s.kind == "KILL") and s.questId ~= nil then b(s.consumedBy == nil, tag) end
    end)
    done()
    local tm = Step("TK_ATTUNEMENT", "trial_mercy")
    CHECK(tm and tm.kind == "ITEM" and tm.questId == 10884 and tm.item and tm.item.id == 31716, "D30 Trial of Mercy: ITEM with questId 10884 and the axe")
    local tg = Step("TK_ATTUNEMENT", "trial_magtheridon")
    CHECK(tg and tg.kind == "KILL" and tg.questId == 10888 and tg.item and tg.item.id == 31704 and tg.inside and tg.inside.instance == 544,
        "D30 Trial of Magtheridon: KILL with questId 10888 and The Tempest Key")
    local ws, pa = Step("ARCATRAZ_KEY", "kill_warp_splinter"), Step("ARCATRAZ_KEY", "kill_pathaleon")
    CHECK(ws and ws.kind == "KILL" and ws.questId == 10704 and ws.needs and ws.needs.id == 31085 and ws.inside.instance == 553
        and pa and pa.questId == 10704 and pa.needs.id == 31086 and pa.inside.instance == 554, "D30 the Arcatraz shard kills carry questId 10704 and needs")
    local chainCount, allCount, anyCount = 0, 0, 0
    EachStep(function(g, s)
        if s.questMode == "CHAIN" then chainCount = chainCount + 1 end
        if s.questMode == "ALL" then allCount = allCount + 1 end
        if s.questMode == "ANY" then anyCount = anyCount + 1 end
    end)
    CHECK(chainCount == 5 and allCount == 1 and anyCount >= 3, "D30 five CHAIN, one ALL, the ANY pools")
end

do
    -- 4.10: counted = not optional, not note, not daily outside the recurring guide; a hub daily keeps
    -- optional = false (its line shows the live word) and is excluded from n/m by that rule.
    local b, done = Batch("D31 every daily step outside BADGES is a QUEST with ids the engine can read live")
    local hubs = { OGRILA_UNLOCK = 0, SKYGUARD_SKETTIS = 0, NETHERWING_DAILIES = 0, SHATTERED_SUN_OFFENSIVE = 0 }
    EachStep(function(g, s, tag)
        if s.daily and g.key ~= "BADGES" then
            b(s.kind == "QUEST" and (s.questId ~= nil or type(s.questIds) == "table") and s.accept == nil and s.consumedBy == nil, tag)
            if hubs[g.key] then hubs[g.key] = hubs[g.key] + 1 end
        end
    end)
    done()
    CHECK(hubs.OGRILA_UNLOCK > 0 and hubs.SKYGUARD_SKETTIS > 0 and hubs.NETHERWING_DAILIES > 0 and hubs.SHATTERED_SUN_OFFENSIVE > 0,
        "D31 Ogri'la, Skyguard, Netherwing and SSO dailies are daily = true")
    local fd = Step("HEROIC_HELLFIRE", "fortifications_daily")
    CHECK(fd and fd.daily == true and fd.optional == true, "D31 Hellfire Fortifications is a daily and optional (3.9)")
    local function Counted(g, s)
        return not s.optional and not s.note and not (s.daily and g.key ~= "BADGES") and s.kind ~= "TALK"
    end
    local nw = 0
    for _, s in ipairs(Steps("NETHERWING_DAILIES")) do
        if Counted(by.NETHERWING_DAILIES, s) then nw = nw + 1 end
    end
    EQ(nw, 29, "D31 Netherwing counts 29 of 34 (dailies and optional steps out)")
    local b2, done2 = Batch("D31 the engine's counted set holds no daily outside BADGES")
    EachStep(function(g, s, tag)
        if Counted(g, s) and g.key ~= "BADGES" then b2(s.daily == nil, tag) end
    end)
    done2()
end

do
    local ac, tc = Step("SSC_ATTUNEMENT", "accept_cudgel"), Step("SSC_ATTUNEMENT", "turn_in_cudgel")
    CHECK(ac and ac.accept == true and ac.questId == 10901 and tc and tc.accept == nil and tc.questId == 10901, "D32 SSC accept_cudgel accepts 10901, turn_in_cudgel hands it in")
    local av, tv = Step("HYJAL_ATTUNEMENT", "accept_vials"), Step("HYJAL_ATTUNEMENT", "turn_in_vials")
    CHECK(av and av.accept == true and av.questId == 10445 and tv and tv.accept == nil and tv.questId == 10445, "D32 Hyjal accept_vials accepts 10445, turn_in_vials hands it in")
    local accepts = 0
    EachStep(function(g, s) if s.accept then accepts = accepts + 1 end end)
    EQ(accepts, 2, "D32 exactly two accept steps")
    local ad = Step("KARAZHAN_ATTUNEMENT", "arcane_disturbances")
    CHECK(ad and not Has(ad.impliedBy, 9825) and Has(ad.impliedBy, 9826) and Has(ad.impliedBy, 9837), "D32 arcane_disturbances.impliedBy excludes 9825 and includes 9826")
    local ra = Step("KARAZHAN_ATTUNEMENT", "restless_activity")
    CHECK(ra and not Has(ra.impliedBy, 9824) and Has(ra.impliedBy, 9826), "D32 restless_activity.impliedBy excludes 9824 and includes 9826")
    local b, done = Batch("D32 an accept step never carries impliedBy and its quest appears on a later step")
    for _, g in ipairs(G) do
        for i, s in ipairs(g.steps) do
            if s.accept then
                local later = false
                for j = i + 1, #g.steps do
                    if g.steps[j].questId == s.questId then later = true end
                end
                b(s.impliedBy == nil and later, g.key .. ":" .. s.key)
            end
        end
    end
    done()
    EQ(#Steps("KARAZHAN_ATTUNEMENT"), 16, "D32 Karazhan has 16 steps")
    EQ(#Steps("BLACK_TEMPLE_ATTUNEMENT"), 17, "D32 Black Temple has 17 steps")
    EQ(#Steps("NETHERWING_DAILIES"), 34, "D32 Netherwing has 34 steps")
    EQ(#Steps("FLYING"), 9, "D32 FLYING has 9 steps")
end

do
    local sl = by.SHADOW_LABYRINTH_KEY
    local door = sl.alternatives and sl.alternatives.door
    CHECK(door and #door.groups == 2 and #door.groups[1] == 2 and door.groups[1][1] == "kill_ikiss" and door.groups[1][2] == "loot_key",
        "D33 SHADOW_LABYRINTH_KEY door group 1 = kill_ikiss, loot_key")
    CHECK(door and #door.groups[2] == 1 and door.groups[2][1] == "lockpick_alt", "D33 door group 2 = lockpick_alt")
    local lp = Step("SHADOW_LABYRINTH_KEY", "lockpick_alt")
    CHECK(lp and lp.kind == "SKILL" and lp.classes and lp.classes[1] == "ROGUE" and lp.skill and lp.skill.name == "Lockpicking"
        and lp.skill.rank == 350 and lp.skill.line == 633 and lp.optional == false, "D33 lockpick_alt: rogue only, Lockpicking 350, counted")
    local ki = Step("SHADOW_LABYRINTH_KEY", "kill_ikiss")
    CHECK(ki and ki.kind == "KILL" and ki.inside and ki.inside.instance == 556 and ki.inside.heroic == false and Has(ki.inside.npcs, 18473)
        and ki.inside.last == true and ki.optional == false, "D33 kill_ikiss: normal Sethekk Halls, Ikiss 18473, end boss, counted")
    local lk = Step("SHADOW_LABYRINTH_KEY", "loot_key")
    CHECK(lk and lk.kind == "ITEM" and lk.item and lk.item.id == 27991, "D33 loot_key is the Shadow Labyrinth Key 27991")
    local sh = Step("SHATTERED_HALLS_KEY", "lockpick_alt")
    CHECK(sh and sh.optional == true and by.SHATTERED_HALLS_KEY.alternatives == nil, "D33 the Shattered Halls rogue line stays optional advice, no groups")
end

do
    local function HasAll(list, ids)
        for _, id in ipairs(ids) do
            if not Has(list, id) then return false end
        end
        return true
    end
    local epic = { 32857, 32858, 32859, 32860, 32861, 32862, 32314, 32316, 32317, 32318, 32319, 33999, 32458, 34061 }
    local em = Step("FLYING", "epic_flying_mount")
    local any = em and em.item and em.item.anyOf
    CHECK(any and HasAll(any.A, epic) and HasAll(any.H, epic), "D34 epic_flying_mount anyOf holds the drakes, nether rays and the three A80 ids on both sides")
    CHECK(any and HasAll(any.A, { 25473, 25527, 25528, 25529 }) and HasAll(any.H, { 25477, 25531, 25532, 25533 })
        and not Has(any.A, 25477) and not Has(any.H, 25473), "D34 epic_flying_mount vendor mounts by faction")
    CHECK(em and em.item.id == nil and em.level == 70 and em.optional == false, "D34 epic_flying_mount: anyOf only, level 70, counted")
    local fm = Step("FLYING", "flying_mount")
    local fany = fm and fm.item and fm.item.anyOf
    CHECK(fany and HasAll(fany.A, epic) and HasAll(fany.H, epic), "D34 flying_mount anyOf holds every 280 id too")
    CHECK(fany and HasAll(fany.A, { 25470, 25471, 25472, 34060 }) and HasAll(fany.H, { 25474, 25475, 25476, 34060 }), "D34 flying_mount anyOf holds the 60 percent ids")
    CHECK(fm and fm.optional == false and fm.item.id == nil and fm.level == nil, "D34 flying_mount is counted (FLYING_BASIC's copy wins), no level lock")
    local ar, er = Step("FLYING", "artisan_riding"), Step("FLYING", "expert_riding")
    CHECK(ar and ar.level == 70 and ar.kind == "SKILL" and ar.skill.rank == 300 and ar.spellId == 34091, "D34 artisan_riding level 70, Riding 300, spell 34091")
    CHECK(er and er.level == nil and er.kind == "SKILL" and er.skill.rank == 225 and er.skill.line == 762 and er.spellId == 34090, "D34 expert_riding Riding 225, spell 34090")
    local ff, sff = Step("FLYING", "flight_form"), Step("FLYING", "swift_flight_form")
    CHECK(ff and ff.kind == "SPELL" and ff.spellId == 33943 and ff.classes[1] == "DRUID" and ff.level == nil, "D34 flight_form: druid, spell 33943")
    CHECK(sff and sff.kind == "SPELL" and sff.spellId == 40120 and sff.classes[1] == "DRUID" and sff.level == 70 and sff.phases.from == 2,
        "D34 swift_flight_form: druid, spell 40120, level 70, from Phase 2")
    local lv = Step("FLYING", "level_70")
    CHECK(lv and lv.kind == "LEVEL" and lv.level == 70 and lv.levelByClass and lv.levelByClass.DRUID == 68
        and lv.title == "Reach level 70, or 68 as a druid", "D34 level_70 reads 70, or 68 as a druid")
    CHECK(fm and fm.title == "Buy a 60 percent flying mount, or better" and em and em.title == "Buy a 280 percent flying mount", "D34 the mount titles")
    local order = {}
    for i, s in ipairs(Steps("FLYING")) do order[i] = s.key end
    CHECK(table.concat(order, ",") == "level_70,learning_to_fly,expert_riding,flying_mount,flight_form,artisan_riding,epic_flying_mount,swift_flight_form,reach_tempest_keep",
        "D34 FLYING step order as 3.8.5 lists it", table.concat(order, ","))
    local rt = Step("FLYING", "reach_tempest_keep")
    CHECK(rt and rt.kind == "MANUAL" and rt.note == true and rt.places and rt.places[1].role == "spot" and rt.places[1].map == 1953,
        "D34 reach_tempest_keep is a note with its spot")
end

if fails == 0 then
    io.write(checks .. " checks passed\n")
    os.exit(0)
end
io.write(checks .. " checks, " .. fails .. " failed\n")
os.exit(1)
