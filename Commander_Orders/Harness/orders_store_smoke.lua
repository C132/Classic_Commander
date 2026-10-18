-- Commander Orders store smoke (luajit)
--
--     /opt/homebrew/bin/luajit Commander_Orders/Harness/orders_store_smoke.lua
--
-- The model with no client attached. CommanderOrdersStore.lua is loaded into
-- a SEALED environment: reading any global outside the Lua standard set, or
-- writing any global but CommanderOrders, raises, so a client call that
-- creeps into the "pure" file fails here, on any code path the checks reach.
-- The world is a fake: a handful of maps with a yard origin and size each
-- and a landmass tag, so distances are plain Pythagoras and "same landmass"
-- is a tag compare (map 20 deliberately overlaps map 10's coordinates on
-- another landmass: the Eversong / Hellfire trap of instance 530). Geo is
-- NOT loaded: the store only ever sees the functions its ctx hands it.
-- CO_STORE=/path/to/copy.lua runs every check against a copy of the store
-- (mutation testing: break a rule in the copy, a check must fail). Each
-- section runs under pcall, so a broken store reports FAILs, not a crash.
--
-- Sections:
--   A  construction, validation, defaults, normalising
--   B  dedup: same place, (source, key) moves, corpse and unit identity
--   C  Find (tolerance), Get, Remove, RemoveBy, List, Clear, Update, onRemove
--   D  targeting precedence: corpse > pinned > route > closest; temporary;
--      the dismissed arrow
--   E  closest: landmass, eligibility, tiers, hysteresis, the rescan throttle
--   F  nearest-of-N alternatives with hysteresis
--   G  routes: ordered, nearest, landmass grouping, next/prev/reverse/
--      optimise, add stop, replace by key, removal bookkeeping
--   H  the arrival machine: NEAR/ARRIVED/DONE timing, exit margin, taxi,
--      the fresh-born rule, re-entry, clearOnArrive false, route advance and
--      completion, a target that loses the arrow mid-hold
--   I  distance bands (the TomTom shim's callbacks)
--   J  Serialize / Load: plain data only, 16-digit round trip, counters,
--      tolerant matching afterwards, garbage in
--   K  the sealed environment saw nothing it should not have

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local STORE_FILE = os.getenv("CO_STORE") or (ADDONS .. "/Commander_Orders/CommanderOrdersStore.lua")

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail ~= nil and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end
local function EQ(got, want, label)
    CHECK(got == want, label, string.format("got %s want %s", tostring(got), tostring(want)))
end
local function NEAR(got, want, label, eps)
    CHECK(type(got) == "number" and math.abs(got - want) <= (eps or 1e-9), label,
        string.format("got %s want %s", tostring(got), tostring(want)))
end
-- Each section runs protected: a store regression that makes a section
-- index a nil reports as one FAIL with the error, and the rest still run.
local sectionNo = 0
local function Section(fn)
    sectionNo = sectionNo + 1
    local ok, err = pcall(fn)
    CHECK(ok, "section " .. sectionNo .. " ran to the end", err)
end

-- ===========================================================================
-- The sealed environment
-- ===========================================================================
local ALLOWED = {
    type = type, pairs = pairs, ipairs = ipairs, next = next, pcall = pcall, select = select,
    tostring = tostring, tonumber = tonumber, setmetatable = setmetatable, getmetatable = getmetatable,
    rawget = rawget, rawset = rawset, error = error, assert = assert, unpack = unpack,
    math = math, table = table, string = string,
}
local strayReads, strayWrites = {}, {}
local SEALED = setmetatable({}, {
    __index = function(_, k)
        if ALLOWED[k] ~= nil then return ALLOWED[k] end
        if k == "CommanderOrders" then return nil end      -- the shared table, before anyone made it
        strayReads[#strayReads + 1] = tostring(k)
        error("sealed env: read of global " .. tostring(k), 2)
    end,
    __newindex = function(t, k, v)
        if k ~= "CommanderOrders" then
            strayWrites[#strayWrites + 1] = tostring(k)
            error("sealed env: write of global " .. tostring(k), 2)
        end
        rawset(t, k, v)
    end,
})
local chunk = assert(loadfile(STORE_FILE))
setfenv(chunk, SEALED)
local okLoad, errLoad = pcall(chunk)
CHECK(okLoad, "K: the store loads in the sealed environment", errLoad)
if not okLoad then
    io.write(string.format("%d checks, %d failures\n", checks, fails))
    os.exit(1)
end
local S = rawget(SEALED, "CommanderOrders").Store
CHECK(type(S) == "table" and type(S.New) == "function", "A: CommanderOrders.Store is the module")

-- ===========================================================================
-- The fake world
-- ===========================================================================
-- map -> yard origin (north-ish ox, west-ish oy), size and landmass. One map
-- unit on the 1000-yard maps is 1000 yd, so 0.001 = 1 yd.
local MAPS = {
    [10] = { ox = 0, oy = 0, w = 1000, h = 1000, land = "EK" },
    [11] = { ox = 1000, oy = 0, w = 1000, h = 1000, land = "EK" },
    [12] = { ox = 0, oy = 1000, w = 1000, h = 1000, land = "EK" },
    [20] = { ox = 0, oy = 0, w = 1000, h = 1000, land = "OUT" },   -- overlaps 10, other landmass
    [21] = { ox = 1000, oy = 0, w = 1000, h = 1000, land = "OUT" },
    [30] = { ox = 0, oy = 0, w = 1000, h = 1000, land = "KAL" },
}
local distCalls = 0
local function World(p)
    local m = MAPS[p.map]
    if not m then return nil end
    return m.ox + p.x * m.w, m.oy + p.y * m.h, m.land
end
local function Dist(a, b)
    distCalls = distCalls + 1
    local ax, ay, al = World(a)
    local bx, by, bl = World(b)
    if not ax or not bx or al ~= bl then return nil end
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end
local function SameLandmass(a, b)
    return MAPS[a] ~= nil and MAPS[b] ~= nil and MAPS[a].land == MAPS[b].land
end

local T = 100            -- monotonic clock (GetTime)
local E = 1700000000     -- wall clock (time)
local function clock() return T end
local function epoch() return E end

local function Ctx(map, x, y, extra)
    local c = {
        player = map and { map = map, x = x, y = y } or nil,
        distance = Dist, sameLandmass = SameLandmass, now = T,
    }
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
end

-- yards east/south of a base on a 1000-yard map
local function At(map, bx, by, dxYards, dyYards)
    return { map = map, x = bx + (dxYards or 0) / 1000, y = by + (dyYards or 0) / 1000 }
end

local function Types(events)
    local t = {}
    for i, e in ipairs(events) do t[i] = e.type end
    return table.concat(t, ",")
end
local function Event(events, kind)
    for _, e in ipairs(events) do
        if e.type == kind then return e end
    end
    return nil
end
local function CountEvents(events, kind)
    local n = 0
    for _, e in ipairs(events) do
        if e.type == kind then n = n + 1 end
    end
    return n
end
local function Uids(list)
    local t = {}
    for i, wp in ipairs(list) do t[i] = type(wp) == "table" and wp.uid or tostring(wp) end
    return table.concat(t, ",")
end
local function NaN() return 0 / 0 end

-- ===========================================================================
-- A: construction, validation, defaults
-- ===========================================================================
Section(function()
    local st = S.New(clock, epoch)
    EQ(st.version, 0, "A: a new store is at version 0")
    EQ(#st:List(), 0, "A: a new store is empty")
    EQ(st:ActiveTarget(nil), nil, "A: ActiveTarget(nil) on an empty store is nil, no error")

    local wp, err, status = st:Add({ map = 1944, x = 0.452, y = 0.668, title = "Nazgrel" })
    CHECK(wp ~= nil, "A: a valid add returns the record", err)
    EQ(status, "added", "A: status says added")
    EQ(wp.uid, "w1", "A: the first uid is w1")
    EQ(wp.map, 1944, "A: map kept")
    EQ(wp.x, 0.452, "A: x stored exactly")
    EQ(wp.y, 0.668, "A: y stored exactly")
    EQ(wp.title, "Nazgrel", "A: title kept")
    EQ(wp.source, "user", "A: source defaults to user")
    EQ(wp.kind, "point", "A: kind defaults to point")
    EQ(wp.persistent, true, "A: persistent by default")
    EQ(wp.clearOnArrive, true, "A: clears on arrival by default")
    EQ(wp.temporary, false, "A: not temporary by default")
    EQ(wp.arrive, nil, "A: no own radius unless given (the setting applies)")
    EQ(wp.created, E, "A: created is stamped from the epoch clock")
    EQ(wp.callbacks, nil, "A: no callbacks unless given")
    EQ(st.version, 1, "A: an add bumps the version")
    EQ(st:Get("w1"), wp, "A: Get returns the record")

    local bad = {
        { {}, "no position", "an empty spec" },
        { { x = 0.5, y = 0.5 }, "invalid map", "no map" },
        { { map = "1944", x = 0.5, y = 0.5 }, "invalid map", "a string map" },
        { { map = 0, x = 0.5, y = 0.5 }, "invalid map", "map 0" },
        { { map = -3, x = 0.5, y = 0.5 }, "invalid map", "a negative map" },
        { { map = 1.5, x = 0.5, y = 0.5 }, "invalid map", "a fractional map" },
        { { map = NaN(), x = 0.5, y = 0.5 }, "invalid map", "a NaN map" },
        { { map = 10, x = NaN(), y = 0.5 }, "invalid x", "a NaN x" },
        { { map = 10, x = 1.0001, y = 0.5 }, "invalid x", "x over 1" },
        { { map = 10, x = -0.0001, y = 0.5 }, "invalid x", "x under 0" },
        { { map = 10, x = math.huge, y = 0.5 }, "invalid x", "an infinite x" },
        { { map = 10, x = "0.5", y = 0.5 }, "invalid x", "a string x" },
        { { map = 10, x = 0.5, y = NaN() }, "invalid y", "a NaN y" },
        { { map = 10, x = 0.5, y = 45.2 }, "invalid y", "0..100 coordinates (the caller forgot /100)" },
        { { map = 10, x = 0.5 }, "invalid y", "a missing y" },
        { { kind = "unit", map = 10, x = 0.5, y = 0.5 }, "invalid unit", "a unit follow without a unit" },
    }
    for _, case in ipairs(bad) do
        local r, e = st:Add(case[1])
        CHECK(r == nil and e == case[2], "A: rejects " .. case[3], tostring(e))
    end
    local r, e = st:Add(nil)
    CHECK(r == nil and e == "no spec", "A: rejects a nil spec")
    r, e = st:Add("way 45 66")
    CHECK(r == nil and e == "no spec", "A: rejects a string spec")
    EQ(st.version, 1, "A: refusals do not bump the version")
    local w2 = st:Add({ map = 10, x = 0, y = 1 })
    EQ(w2 and w2.uid, "w2", "A: refusals do not consume uids")
    CHECK(w2 and w2.x == 0 and w2.y == 1, "A: 0 and 1 are valid coordinates")

    CHECK(S.ValidPosition(10, 0.5, 0.5) == true, "A: ValidPosition accepts a good position")
    local ok, why = S.ValidPosition(10, 0.5, 2)
    CHECK(ok == false and why == "invalid y", "A: ValidPosition names the bad field")

    -- titles
    EQ(st:Add({ map = 10, x = 0.1, y = 0.1, title = 42 }).title, "42", "A: a number title becomes a string")
    EQ(st:Add({ map = 10, x = 0.1, y = 0.2, title = {} }).title, nil, "A: a table title is no title")
    local long = string.rep("a", 254) .. "\195\169" .. "tail"
    local lw = st:Add({ map = 10, x = 0.1, y = 0.3, title = long })
    EQ(#lw.title, 254, "A: a long title is cut back to a UTF-8 boundary (no half glyph)")
    EQ(lw.title:sub(-1), "a", "A: ...and ends on a whole character")
    local exact = string.rep("b", 255)
    EQ(#st:Add({ map = 10, x = 0.1, y = 0.4, title = exact .. "c" }).title, 255, "A: ASCII cuts at 255 bytes")
    local again = st:Add({ map = 10, x = 0.1, y = 0.3, title = long })
    EQ(again, lw, "A: dedup compares the cut title both ways")

    -- defaults per source / kind / arrive
    local place = st:Add({ map = 10, x = 0.2, y = 0.2, source = "place" })
    EQ(place.clearOnArrive, false, "A: a saved place does not clear on arrival by default")
    EQ(st:Add({ map = 10, x = 0.2, y = 0.3, source = "place", clearOnArrive = true }).clearOnArrive, true,
        "A: an explicit clearOnArrive wins")
    EQ(st:Add({ map = 10, x = 0.2, y = 0.4, clearOnArrive = false }).clearOnArrive, false,
        "A: clearOnArrive false is honoured")
    EQ(st:Add({ map = 10, x = 0.2, y = 0.5, kind = "stop" }).kind, "point", "A: kind stop outside a route is a point")
    EQ(st:Add({ map = 10, x = 0.2, y = 0.6, kind = "wobble" }).kind, "point", "A: an unknown kind is a point")
    EQ(st:Add({ map = 10, x = 0.2, y = 0.7, arrive = -5 }).arrive, nil, "A: a negative radius is ignored")
    EQ(st:Add({ map = 10, x = 0.2, y = 0.8, arrive = 0 }).arrive, nil, "A: a zero radius is ignored")
    EQ(st:Add({ map = 10, x = 0.2, y = 0.9, arrive = 12 }).arrive, 12, "A: an own radius is kept")
    EQ(st:Add({ map = 10, x = 0.3, y = 0.1, persistent = false }).persistent, false, "A: session-only is kept")
    EQ(st:Add({ map = 10, x = 0.3, y = 0.2, temporary = 1 }).temporary, false, "A: temporary must be exactly true")
    EQ(st:Add({ map = 10, x = 0.3, y = 0.3, source = "" }).source, "user", "A: an empty source is the user")
    EQ(st:Add({ map = 10, x = 0.3, y = 0.4, key = {} }).key, nil, "A: a table key is no key")
    local unit = st:Add({ kind = "unit", unit = "party1", title = "Bob" })
    CHECK(unit and unit.kind == "unit" and unit.map == nil, "A: a unit follow needs no position")
    EQ(st:Add({ map = 10, x = 0.3, y = 0.5, unit = "party2" }).unit, nil, "A: unit is only kept on unit follows")

    -- the caller's spec is never touched
    local cbs = { distance = { [10] = function() end } }
    local alts = { { 10, 0.5, 0.5 }, { map = 10, x = 0.6, y = 0.6 } }
    local spec = { map = 10, x = 0.4, y = 0.4, title = "T", callbacks = cbs, alternatives = alts, setArrow = true }
    st:Add(spec)
    CHECK(spec.callbacks == cbs and spec.alternatives == alts and spec.map == 10 and spec.setArrow == true
        and spec.uid == nil and spec.source == nil, "A: Add never mutates the caller's spec")
    CHECK(#alts == 2 and alts[1][1] == 10 and cbs.distance[10] ~= nil and next(cbs, next(cbs)) == nil,
        "A: ...nor its alternatives or callbacks tables")

    -- alternatives
    local a1 = st:Add({ map = 10, x = 0.5, y = 0.1, alternatives = {
        { map = 10, x = 0.7, y = 0.1 }, { 10, 0.5, 0.1 }, { map = 10, x = 2, y = 0 }, "junk", { 11, 0.2, 0.2 },
    } })
    CHECK(a1.alternatives and #a1.alternatives == 3, "A: alternatives keep the valid, fold the duplicate primary",
        a1.alternatives and #a1.alternatives)
    CHECK(a1.alternatives[1].map == 10 and a1.alternatives[1].x == 0.5 and a1.alternatives[1].y == 0.1,
        "A: the primary is alternative 1")
    EQ(a1.alternatives[3].map, 11, "A: array-shaped alternatives are read")
    local a2 = st:Add({ alternatives = { "junk", { map = 12, x = 0.25, y = 0.75 }, { map = 12, x = 0.3, y = 0.7 } } })
    CHECK(a2 and a2.map == 12 and a2.x == 0.25 and a2.y == 0.75, "A: no position of its own: the first usable alternative")
    local a3 = st:Add({ map = 10, x = 0.6, y = 0.1, alternatives = { { 10, 0.6, 0.1 } } })
    EQ(a3.alternatives, nil, "A: a list that folds to the primary alone is dropped")
    local many = {}
    for i = 1, 400 do many[i] = { map = 10, x = (i % 20) / 20, y = math.floor(i / 20) / 40 } end
    local a4 = st:Add({ map = 10, x = 0.99, y = 0.99, alternatives = many })
    EQ(#a4.alternatives, S.MAX_ALTERNATIVES, "A: alternatives are capped")
    CHECK(select(2, st:Add({ alternatives = { "x", { 10, 5, 5 } } })) == "no position",
        "A: alternatives with nothing usable are no position")
end)

-- ===========================================================================
-- B: dedup and identity
-- ===========================================================================
Section(function()
    local st = S.New(clock, epoch)
    local a = st:Add({ map = 10, x = 0.25, y = 0.75, title = "Goldshire" })
    local v = st.version
    local b, _, status = st:Add({ map = 10, x = 0.25, y = 0.75, title = "Goldshire" })
    EQ(b, a, "B: the same place and title returns the same record")
    EQ(status, "existing", "B: ...status existing")
    EQ(st.version, v, "B: ...and changes nothing")
    EQ(st:Add({ map = 10, x = 0.25 + 5e-7, y = 0.75 - 5e-7, title = "Goldshire" }), a, "B: within 1e-6 is the same place")
    CHECK(st:Add({ map = 10, x = 0.25 + 2e-6, y = 0.75, title = "Goldshire" }) ~= a, "B: 2e-6 away is another place")
    CHECK(st:Add({ map = 10, x = 0.25, y = 0.75, title = "Elsewhere" }) ~= a, "B: another title is another waypoint")
    CHECK(st:Add({ map = 11, x = 0.25, y = 0.75, title = "Goldshire" }) ~= a, "B: another map is another waypoint")
    local n1 = st:Add({ map = 10, x = 0.5, y = 0.5 })
    local n2 = st:Add({ map = 10, x = 0.5, y = 0.5, title = "nil" })
    CHECK(n1 ~= n2, "B: a nil title is not the string 'nil'")
    EQ(st:Add({ map = 10, x = 0.5, y = 0.5 }), n1, "B: nil title matches nil title")

    -- (source, key) moves
    local q = st:Add({ map = 10, x = 0.1, y = 0.1, title = "Old giver", source = "QuestLog", key = "quest:1" })
    local count = #st:List()
    v = st.version
    local q2, _, st2 = st:Add({ map = 11, x = 0.9, y = 0.8, title = "New giver", source = "QuestLog", key = "quest:1" })
    EQ(q2, q, "B: re-adding a (source, key) keeps the record")
    EQ(st2, "moved", "B: ...status moved")
    CHECK(q.uid == q2.uid and q.map == 11 and q.x == 0.9 and q.y == 0.8 and q.title == "New giver",
        "B: ...and moves it to the new place and title")
    EQ(#st:List(), count, "B: ...without a second record")
    CHECK(st.version > v, "B: a move bumps the version")
    EQ(st:ByKey("QuestLog", "quest:1"), q, "B: ByKey finds the consumer's record")
    EQ(st:ByKey("QuestLog", "quest:2"), nil, "B: ByKey misses an unknown key")
    CHECK(st:Add({ map = 10, x = 0.1, y = 0.1, source = "Tradecraft", key = "quest:1" }) ~= q,
        "B: the same key under another source is another record")
    local k1 = st:Add({ map = 10, x = 0.7, y = 0.7, source = "Formulary", key = 1 })
    local k2 = st:Add({ map = 10, x = 0.7, y = 0.71, source = "Formulary", key = "1" })
    CHECK(k1 ~= k2, "B: key 1 and key '1' are different keys")
    -- a moved record with options
    local q3 = st:Add({ map = 11, x = 0.5, y = 0.5, source = "QuestLog", key = "quest:1", temporary = true,
        clearOnArrive = false, icon = "QUEST" })
    CHECK(q3 == q and q.temporary == true and q.clearOnArrive == false and q.icon == "QUEST",
        "B: a move replaces the options too")

    -- promotion on re-add
    local c = st:Add({ map = 12, x = 0.3, y = 0.3, title = "Vendor", source = "Formulary", persistent = false, temporary = true })
    local u = st:Add({ map = 12, x = 0.3, y = 0.3, title = "Vendor" })
    CHECK(u == c and c.persistent == true and c.temporary == false,
        "B: a user re-add of a consumer's session-only mark makes it stay")
    c.reached = E
    st:Add({ map = 12, x = 0.3, y = 0.3, title = "Vendor" })
    EQ(c.reached, nil, "B: asking for a reached place again un-reaches it")

    -- corpse and unit identity
    local corpse = st:Add({ kind = "corpse", map = 10, x = 0.4, y = 0.4, title = "Corpse", source = "corpse" })
    local corpse2, _, cs = st:Add({ kind = "corpse", map = 11, x = 0.6, y = 0.6, title = "Corpse", source = "Recovery" })
    CHECK(corpse2 == corpse and cs == "moved" and corpse.map == 11, "B: there is only ever one corpse record")
    EQ(st:Count({ kind = "corpse" }), 1, "B: ...exactly one")
    EQ(st:Corpse(), corpse, "B: Corpse() finds it")
    local f1 = st:Add({ kind = "unit", unit = "party1", title = "Bob" })
    local f2, _, fs = st:Add({ kind = "unit", unit = "party1", title = "Bob" })
    CHECK(f1 == f2 and fs == "existing", "B: the same unit follow twice is one record")
    CHECK(st:Add({ kind = "unit", unit = "party2", title = "Bob" }) ~= f1, "B: another unit token is another follow")
    -- a user /way exactly on the corpse is its own waypoint
    CHECK(st:Add({ map = 11, x = 0.6, y = 0.6, title = "Corpse" }) ~= corpse,
        "B: a plain waypoint never merges into the corpse")
end)

-- ===========================================================================
-- C: Find, Get, Remove, RemoveBy, List, Clear, Update, onRemove
-- ===========================================================================
Section(function()
    local st = S.New(clock, epoch)
    local removed = {}
    st.onRemove = function(wp, reason) removed[#removed + 1] = wp.uid .. ":" .. reason end
    local a = st:Add({ map = 10, x = 0.382096171379089, y = 0.5, title = "Rally 1" })
    local b = st:Add({ map = 10, x = 0.6, y = 0.6, source = "QuestLog", key = "q1" })
    local c = st:Add({ map = 11, x = 0.6, y = 0.6, source = "QuestLog", key = "q2", kind = "point" })
    local d = st:Add({ map = 11, x = 0.1, y = 0.1, source = "Tradecraft", temporary = true })

    EQ(st:Find(10, 0.382096171379089, 0.5, "Rally 1"), a, "C: Find exact")
    EQ(st:Find(10, 0.3820961713790894, 0.5, "Rally 1"), a, "C: Find through 16/17-digit printing noise")
    EQ(st:Find(10, 0.3820965, 0.5, "Rally 1"), a, "C: Find within 1e-6")
    EQ(st:Find(10, 0.38211, 0.5, "Rally 1"), nil, "C: Find misses beyond the tolerance")
    EQ(st:Find(10, 0.38211, 0.5, "Rally 1", 0.001), a, "C: Find takes a wider tolerance")
    EQ(st:Find(10, 0.382096171379089, 0.5, "Rally 2"), nil, "C: Find needs the title")
    EQ(st:Find(10, 0.382096171379089, 0.5, nil), nil, "C: a nil title matches only nil titles")
    EQ(st:Find(10, 0.382096171379089, 0.5, S.ANY), a, "C: S.ANY matches any title")
    EQ(st:Find(10, 0.6, 0.6, nil), b, "C: Find a keyed record")
    EQ(st:Find(nil, 0.5, 0.5, nil), nil, "C: Find with a nil map is nil, not an error")
    EQ(st:Find(10, NaN(), 0.5, nil), nil, "C: Find with NaN is nil")

    -- List
    EQ(Uids(st:List()), "w1,w2,w3,w4", "C: List is in creation order")
    EQ(Uids(st:List({ source = "QuestLog" })), "w2,w3", "C: List by source")
    EQ(Uids(st:List({ map = 11 })), "w3,w4", "C: List by map")
    EQ(Uids(st:List({ temporary = true })), "w4", "C: List temporaries")
    EQ(Uids(st:List({ temporary = false })), "w1,w2,w3", "C: List non-temporaries")
    EQ(Uids(st:List({ kind = "point", source = "QuestLog", map = 11 })), "w3", "C: filters combine")
    EQ(Uids(st:List({ routeId = false })), "w1,w2,w3,w4", "C: routeId=false lists standalone records")
    EQ(st:Count({ source = "nobody" }), 0, "C: Count of nothing is 0")

    -- Update
    local v = st.version
    local up, uerr = st:Update(a.uid, { title = "Rally One", colour = "GOLD", icon = "PLACE", note = "by the bank" })
    CHECK(up == a and a.title == "Rally One" and a.colour == "GOLD" and a.icon == "PLACE" and a.note == "by the bank",
        "C: Update renames and recolours", uerr)
    CHECK(st.version > v, "C: an update bumps the version")
    v = st.version
    st:Update(a.uid, { title = "Rally One" })
    EQ(st.version, v, "C: an update that changes nothing does not bump")
    local nu, nerr = st:Update(a.uid, { x = 1.5 })
    CHECK(nu == nil and nerr == "invalid x" and a.x == 0.382096171379089, "C: an invalid move is refused, record untouched")
    st:Update(a.uid, { map = 11, x = 0.2 })
    CHECK(a.map == 11 and a.x == 0.2 and a.y == 0.5, "C: a partial move keeps the other coordinates")
    st:Update(a.uid, { title = false, colour = false, arrive = 15 })
    CHECK(a.title == nil and a.colour == nil and a.arrive == 15, "C: false clears a field; arrive sets the radius")
    st:Update(a.uid, { arrive = -1 })
    EQ(a.arrive, 15, "C: an invalid radius leaves the old one")
    st:Update(a.uid, { arrive = false, clearOnArrive = false, persistent = false, temporary = true })
    CHECK(a.arrive == nil and a.clearOnArrive == false and a.persistent == false and a.temporary == true,
        "C: flags update")
    CHECK(select(2, st:Update("w99", { title = "x" })) == "unknown", "C: Update of an unknown uid says so")
    CHECK(select(2, st:Update(a.uid, nil)) == "no fields", "C: Update without fields says so")
    st:Update(a.uid, { uid = "w77", source = "evil", key = "k", kind = "corpse" })
    CHECK(a.uid == "w1" and a.source == "user" and a.key == nil and a.kind == "point", "C: identity fields are fixed")
    -- moving a record with alternatives replaces candidate 1
    local alt = st:Add({ map = 10, x = 0.1, y = 0.1, alternatives = { { 10, 0.9, 0.9 } } })
    st:Update(alt.uid, { x = 0.2, y = 0.2 })
    CHECK(#alt.alternatives == 2 and alt.alternatives[1].x == 0.2 and alt.alternatives[2].x == 0.9,
        "C: a move swaps the primary candidate, keeps the others")
    st:Update(alt.uid, { alternatives = false })
    EQ(alt.alternatives, nil, "C: alternatives=false drops them")

    -- Remove / RemoveBy
    v = st.version
    EQ(st:Remove("w404"), false, "C: removing an unknown uid is false")
    EQ(st.version, v, "C: ...and no bump")
    EQ(st:Remove(d.uid), true, "C: Remove is true")
    EQ(st:Get(d.uid), nil, "C: ...the record is gone")
    CHECK(st.version > v, "C: ...and the version moved")
    EQ(removed[#removed], "w4:remove", "C: onRemove hears about it with the reason")
    EQ(st:RemoveBy("QuestLog", {}), 0, "C: RemoveBy with an impossible key removes nothing (never the whole source)")
    EQ(st:RemoveBy(nil), 0, "C: RemoveBy without a source removes nothing")
    EQ(st:RemoveBy("QuestLog", "q1"), 1, "C: RemoveBy source+key")
    EQ(st:Get(b.uid), nil, "C: ...that record went")
    EQ(st:Get(c.uid), c, "C: ...the other key stayed")
    EQ(st:ByKey("QuestLog", "q1"), nil, "C: ...and the key is free")
    st:Add({ map = 10, x = 0.33, y = 0.33, source = "QuestLog", key = "q3" })
    EQ(st:RemoveBy("QuestLog"), 2, "C: RemoveBy a whole source")
    EQ(st:Count({ source = "QuestLog" }), 0, "C: ...none left")

    -- a hook that errors cannot break the store
    st.onRemove = function() error("consumer bug") end
    local okR = pcall(st.Remove, st, alt.uid)
    CHECK(okR and st:Get(alt.uid) == nil, "C: an erroring onRemove is contained")
    st.onRemove = function(wp, reason) removed[#removed + 1] = wp.uid .. ":" .. reason end

    -- Clear
    st:Add({ map = 10, x = 0.5, y = 0.5, source = "Ping", temporary = true })
    st:Add({ map = 10, x = 0.6, y = 0.5, source = "Ping", temporary = true })
    EQ(st:Clear({ source = "Ping" }), 2, "C: Clear by filter counts")
    st:SetPinned(a.uid)
    local before = #st:List()
    EQ(st:Clear(), before, "C: Clear() removes everything")
    EQ(#st:List(), 0, "C: ...nothing left")
    EQ(st:Pinned(), nil, "C: ...no pin")
    EQ(removed[#removed]:match(":(.*)$"), "clear", "C: ...onRemove says clear")
    local bumped = st.version
    EQ(st:Clear(), 0, "C: clearing an empty store is 0")
    CHECK(st.version > bumped, "C: ...but Clear() still announces itself (pin and dismissal reset)")

    -- Claim: a keyless standalone record changes owner (the user re-adding a
    -- spot a TomTom-shim caller put there); a keyed one never does
    local cs = S.New(clock, epoch)
    local tt = cs:Add({ map = 10, x = 0.4, y = 0.4, title = "Nazgrel", source = "TomTom:Questie" })
    local cv = cs.version
    EQ(cs:Claim(tt.uid, "user"), true, "C: Claim hands a keyless record to a new owner")
    CHECK(tt.source == "user" and cs.version > cv, "C: ...its source changes and the store bumps")
    EQ(cs:Claim(tt.uid, "user"), false, "C: ...claiming what it already owns changes nothing")
    local keyed = cs:Add({ map = 10, x = 0.41, y = 0.4, title = "Giver", source = "QuestLog", key = "quest:9" })
    EQ(cs:Claim(keyed.uid, "user"), false, "C: a keyed record keeps its owner")
    EQ(cs:ByKey("QuestLog", "quest:9"), keyed, "C: ...and its key")
    local cr = cs:AddRoute({ title = "R", start = false, stops = { { map = 10, x = 0.2, y = 0.2 } } })
    EQ(cs:Claim(cr.stops[1], "user"), false, "C: a route stop keeps its owner")
    EQ(cs:Claim("w404", "user"), false, "C: an unknown uid is false")
end)

-- ===========================================================================
-- D: targeting precedence
-- ===========================================================================
Section(function()
    local st = S.New(clock, epoch)
    st.rescanInterval = 0
    local ctx = Ctx(10, 0.5, 0.5)
    local near = st:Add({ map = 10, x = 0.55, y = 0.5, title = "Near" })                 -- 50 yd
    local far = st:Add({ map = 10, x = 0.8, y = 0.5, title = "Far", setArrow = true })   -- 300 yd, pinned
    local route = st:AddRoute({ title = "Trip", source = "Tradecraft", start = false, stops = {
        { map = 10, x = 0.9, y = 0.9, title = "Stop 1" }, { map = 10, x = 0.95, y = 0.95, title = "Stop 2" },
    } })
    local corpse = st:Add({ kind = "corpse", map = 11, x = 0.5, y = 0.5, title = "Corpse" })

    local wp, why = st:ActiveTarget(ctx)
    CHECK(wp == far and why == "PINNED", "D: a pinned waypoint beats the closest", why)
    wp, why = st:ActiveTarget(Ctx(10, 0.5, 0.5, { ghost = true }))
    CHECK(wp == corpse and why == "CORPSE", "D: a ghost follows the corpse over the pin", why)
    wp = st:ActiveTarget(Ctx(10, 0.5, 0.5, { ghost = true, corpseArrow = false }))
    EQ(wp, far, "D: CorpseArrow off: the corpse does not take over")
    wp = st:ActiveTarget(Ctx(10, 0.5, 0.5, { dead = true }))
    EQ(wp, far, "D: dead but not released: no corpse arrow (you are on it)")
    st:RouteStart(route.id)
    wp, why = st:ActiveTarget(ctx)
    CHECK(wp and wp.title == "Stop 1" and why == "ROUTE", "D: starting a route takes the arrow from the pin", why)
    EQ(st:Pinned(), nil, "D: ...the pin is released")
    st:SetPinned(far.uid)
    EQ(st:ActiveTarget(ctx), far, "D: pinning again beats the route")
    st:ClearPinned()
    wp, why = st:ActiveTarget(ctx)
    CHECK(wp and wp.title == "Stop 1" and why == "ROUTE", "D: unpinned: the active route's stop")
    st:RemoveRoute(route.id)
    wp, why = st:ActiveTarget(ctx)
    CHECK(wp == near and why == "CLOSEST", "D: no pin, no route: the closest", why)
    EQ(st:ActiveTarget(Ctx(10, 0.5, 0.5, { autoClosest = false })), nil, "D: AutoClosest off: nothing")
    EQ(st:ActiveTarget(Ctx(nil)), nil, "D: no player position: no closest")
    st:SetPinned(far.uid)
    EQ(st:ActiveTarget(Ctx(nil)), far, "D: no player position: the pin still resolves")
    EQ(st:ActiveTarget(nil), far, "D: a nil ctx still resolves the pin")
    EQ(select(2, st:SetPinned("w404")), "unknown", "D: pinning an unknown uid says so")

    -- temporary waypoints never steal a user pin
    local temp = st:Add({ map = 10, x = 0.51, y = 0.5, title = "Oracle node", source = "Oracle", temporary = true, setArrow = true })
    EQ(st:Pinned(), far, "D: a temporary setArrow leaves the user's pin alone")
    st:ClearPinned()
    local temp2 = st:Add({ map = 10, x = 0.52, y = 0.5, title = "Ping", source = "Ping", temporary = true, setArrow = true })
    EQ(st:Pinned(), temp2, "D: with no pin, a temporary setArrow pins")
    local temp3 = st:Add({ map = 10, x = 0.53, y = 0.5, title = "Ping 2", source = "Ping", temporary = true, setArrow = true })
    EQ(st:Pinned(), temp3, "D: a temporary replaces a temporary pin")
    st:Add({ map = 10, x = 0.7, y = 0.7, title = "Mine", setArrow = true })
    EQ(st:Pinned().title, "Mine", "D: a user setArrow replaces a temporary pin")
    st:SetPinned(temp.uid)
    EQ(st:Pinned(), temp, "D: an explicit SetPinned always wins, temporary or not")
    -- re-pin through the existing path
    st:ClearPinned()
    st:Add({ map = 10, x = 0.8, y = 0.5, title = "Far", setArrow = true })
    EQ(st:Pinned(), far, "D: re-adding an existing waypoint with setArrow re-pins it")

    -- the dismissed arrow
    st:ClearPinned(true)
    CHECK(st:Suppressed(), "D: ClearPinned(true) dismisses the arrow")
    EQ(st:ActiveTarget(ctx), nil, "D: dismissed: the closest does not jump back in")
    EQ(st:ActiveTarget(Ctx(10, 0.5, 0.5, { ghost = true })), corpse, "D: dismissed: the corpse still wins for a ghost")
    st:Add({ map = 10, x = 0.45, y = 0.5, title = "Quiet add" })
    EQ(st:ActiveTarget(ctx), nil, "D: a plain add does not undo the dismissal")
    st:SetPinned(near.uid)
    CHECK(not st:Suppressed() and st:ActiveTarget(ctx) == near, "D: a pin ends the dismissal")
    st:ClearPinned(true)
    st:Add({ map = 10, x = 0.46, y = 0.5, title = "Go here", setArrow = true })
    CHECK(not st:Suppressed() and st:ActiveTarget(ctx).title == "Go here", "D: an Add with setArrow ends it")
    st:ClearPinned(true)
    local r2 = st:AddRoute({ title = "R", stops = { { map = 10, x = 0.1, y = 0.1 }, { map = 10, x = 0.2, y = 0.2 } } })
    CHECK(not st:Suppressed() and st:ActiveTarget(ctx).routeId == r2.id, "D: a route start ends it")
    st:ClearPinned(true)
    st:RouteNext()
    CHECK(not st:Suppressed() and st:ActiveTarget(ctx).routeIndex == 2, "D: a route step ends it")

    -- pinning a route stop jumps the route
    local r3 = st:AddRoute({ title = "Jump", start = false, stops = {
        { map = 10, x = 0.3, y = 0.3, title = "J1" }, { map = 10, x = 0.31, y = 0.3, title = "J2" },
        { map = 10, x = 0.32, y = 0.3, title = "J3" },
    } })
    local j3 = st:Get(r3.stops[3])
    EQ(st:SetPinned(j3.uid), true, "D: a route stop can be chosen")
    wp, why = st:ActiveTarget(ctx)
    CHECK(wp == j3 and why == "ROUTE", "D: ...it becomes the route's current stop", why)
    CHECK(st:Pinned() == nil and st:ActiveRoute() == r3 and r3.index == 3, "D: ...through the route, not the pin")

    -- a running route holds the arrow with NO pin (StartRoute lets it go),
    -- and a temporary offer must not take it: Adjutant's repair offer and an
    -- automatic group ping did before this rule (review: runtime)
    local rs = S.New(clock, epoch)
    rs.rescanInterval = 0
    local rc = Ctx(10, 0.5, 0.5)
    rs:AddRoute({ title = "Trip", source = "Tradecraft", key = "trip", stops = {
        { map = 10, x = 0.6, y = 0.5, title = "Stop A" }, { map = 10, x = 0.7, y = 0.5, title = "Stop B" },
    } })
    local rw, rwhy = rs:ActiveTarget(rc)
    CHECK(rw and rw.title == "Stop A" and rwhy == "ROUTE" and rs:Pinned() == nil, "D: a route holds the arrow, unpinned")
    rs:Add({ map = 10, x = 0.52, y = 0.5, title = "Repair: Smith", source = "Logistics", key = "repair",
             temporary = true, setArrow = true })
    EQ(rs:Pinned(), nil, "D: a temporary setArrow does not pin over a running route")
    rw, rwhy = rs:ActiveTarget(rc)
    CHECK(rw and rw.title == "Stop A" and rwhy == "ROUTE", "D: ...the route keeps the arrow", rwhy)
    rs:Add({ map = 10, x = 0.53, y = 0.5, title = "Repair: Smith", source = "Logistics", key = "repair",
             temporary = true, setArrow = true })
    EQ(rs:Pinned(), nil, "D: ...nor when the same offer moves (source, key)")
    rs:Add({ map = 10, x = 0.54, y = 0.5, title = "Bob's ping", source = "Ping", key = "ping", temporary = true,
             setArrow = true })
    EQ(rs:Pinned(), nil, "D: ...nor an automatic group ping")
    rs:Add({ map = 10, x = 0.55, y = 0.5, title = "Mine", setArrow = true })
    EQ(rs:Pinned() and rs:Pinned().title, "Mine", "D: the user's own setArrow still takes it from the route")
    rs:ClearPinned(true)
    rs:Add({ map = 10, x = 0.56, y = 0.5, title = "Bob's ping", source = "Ping", key = "ping", temporary = true,
             setArrow = true })
    EQ(rs:Pinned() and rs:Pinned().title, "Bob's ping",
        "D: a dismissed arrow is not a route holding it: a temporary pins as before")

    -- Mark arrived on a kept mark: stamped reached, so the closest moves on
    local ms = S.New(clock, epoch)
    ms.rescanInterval = 0
    local mine = ms:Add({ map = 10, x = 0.55, y = 0.5, title = "Mine", clearOnArrive = false, setArrow = true })
    local other = ms:Add({ map = 10, x = 0.8, y = 0.5, title = "Other" })
    local mv = ms.version
    EQ(ms:MarkReached(mine.uid), true, "D: MarkReached")
    CHECK(mine.reached ~= nil and ms:Pinned() == nil and ms.version > mv and ms:Get(mine.uid) == mine,
        "D: ...stamps reached, lets the pin go, keeps the record, bumps")
    local mw, mwhy = ms:ActiveTarget(Ctx(10, 0.5, 0.5))
    CHECK(mw == other and mwhy == "CLOSEST", "D: ...and the closest leaves it out (the arrow moves on)", mw and mw.title)
    EQ(ms:MarkReached("w404"), false, "D: MarkReached on an unknown uid is false")
end)

-- ===========================================================================
-- E: closest, hysteresis, the rescan throttle
-- ===========================================================================
Section(function()
    local st = S.New(clock, epoch)
    st.rescanInterval = 0
    local A = st:Add({ map = 10, x = 0.6, y = 0.5, title = "A" })
    local B = st:Add({ map = 10, x = 0.3, y = 0.5, title = "B" })
    EQ(st:ActiveTarget(Ctx(10, 0.5, 0.5)), A, "E1: A 100 vs B 200: A")
    EQ(st:ActiveTarget(Ctx(10, 0.44, 0.5)), A, "E1: A 160 vs B 140 (12%, 20 yd): A holds")
    EQ(st:ActiveTarget(Ctx(10, 0.435, 0.5)), A, "E1: A 165 vs B 135 (18%, 30 yd): A holds (the ratio bar)")
    EQ(st:ActiveTarget(Ctx(10, 0.43, 0.5)), B, "E1: A 170 vs B 130 (23%, 40 yd): B")
    EQ(st:ActiveTarget(Ctx(10, 0.46, 0.5)), B, "E1: A 140 vs B 160 (12%, 20 yd): B holds")
    EQ(st:ActiveTarget(Ctx(10, 0.5, 0.5)), A, "E1: A 100 vs B 200 (50%, 100 yd): A")
end)

Section(function()
    -- the ratio bar alone and the yard bar alone are not enough
    local st = S.New(clock, epoch)
    st.rescanInterval = 0
    local A = st:Add({ map = 10, x = 0.55, y = 0.5, title = "A" })    -- 50 yd
    local B = st:Add({ map = 10, x = 0.40, y = 0.5, title = "B" })    -- 100 yd
    EQ(st:ActiveTarget(Ctx(10, 0.5, 0.5)), A, "E2: start on A")
    -- at 0.465: A 85, B 65 -> 23.5% nearer but only 20 yd
    EQ(st:ActiveTarget(Ctx(10, 0.465, 0.5)), A, "E2: 23% nearer but only 20 yd: A holds (both bars needed)")
    EQ(st:ActiveTarget(Ctx(10, 0.43, 0.5)), B, "E2: A 120 vs B 30: B")
    local st2 = S.New(clock, epoch)
    st2.rescanInterval = 0
    local C = st2:Add({ map = 10, x = 0.0, y = 0.5, title = "C" })   -- world 0
    local D = st2:Add({ map = 11, x = 0.0, y = 0.5, title = "D" })   -- world 1000, the next zone east
    -- player on map 10 at x = 0.45 (world 450): C 450, D 550
    EQ(st2:ActiveTarget(Ctx(10, 0.45, 0.5)), C, "E2: C 450 vs D 550: C")
    -- x = 0.53 (530): C 530, D 470 -> 11%, 60 yd: hold
    EQ(st2:ActiveTarget(Ctx(10, 0.53, 0.5)), C, "E2: 60 yd but only 11% nearer: C holds")
    -- x = 0.58: C 580, D 420 -> 27.6%, 160 yd: switch
    EQ(st2:ActiveTarget(Ctx(10, 0.58, 0.5)), D, "E2: 27% and 160 yd nearer, across a zone line: D")
end)

Section(function()
    local st = S.New(clock, epoch)
    st.rescanInterval = 0
    -- the 530 trap: map 20 shares map 10's coordinates on another landmass
    local trap = st:Add({ map = 20, x = 0.5, y = 0.5, title = "Hellfire" })
    local far = st:Add({ map = 10, x = 0.9, y = 0.9, title = "Elwynn far" })
    EQ(st:ActiveTarget(Ctx(10, 0.5, 0.5)), far, "E3: a point on another landmass at the 'same' coordinates is never closest")
    EQ(st:Distance(trap, Ctx(10, 0.5, 0.5)), nil, "E3: ...and has no distance")
    NEAR(st:Distance(far, Ctx(10, 0.5, 0.5)), math.sqrt(2) * 400, "E3: Distance measures through ctx", 1e-6)
    EQ(st:ActiveTarget(Ctx(20, 0.1, 0.1)), trap, "E3: from Outland, the Outland point")
    EQ(st:ActiveTarget(Ctx(30, 0.5, 0.5)), nil, "E3: on a landmass with nothing: nothing")
    local wp, d = st:Closest(Ctx(10, 0.5, 0.5))
    CHECK(wp == far and d and math.abs(d - math.sqrt(2) * 400) < 1e-6, "E3: Closest returns the record and its yards")

    -- eligibility
    local st2 = S.New(clock, epoch)
    st2.rescanInterval = 0
    local real = st2:Add({ map = 10, x = 0.9, y = 0.5, title = "Real" })   -- 400 yd
    st2:Add({ kind = "corpse", map = 10, x = 0.51, y = 0.5 })
    st2:Add({ kind = "unit", unit = "party1", map = 10, x = 0.52, y = 0.5 })
    local done = st2:Add({ map = 10, x = 0.53, y = 0.5, clearOnArrive = false })
    done.reached = E
    st2:AddRoute({ title = "R", start = false, stops = { { map = 10, x = 0.54, y = 0.5 } } })
    EQ(st2:ActiveTarget(Ctx(10, 0.5, 0.5)), real,
        "E4: never a corpse, a unit follow, a reached mark or a route stop")

    -- tiers: non-temporary before temporary
    local st3 = S.New(clock, epoch)
    st3.rescanInterval = 0
    local tmp = st3:Add({ map = 10, x = 0.51, y = 0.5, temporary = true, title = "tmp" })
    EQ(st3:ActiveTarget(Ctx(10, 0.5, 0.5)), tmp, "E5: only temporaries: the nearest temporary")
    local user = st3:Add({ map = 10, x = 0.9, y = 0.5, title = "user" })
    EQ(st3:ActiveTarget(Ctx(10, 0.5, 0.5)), user, "E5: a non-temporary appears: it wins at once, nearer temp or not")
    st3:Remove(user.uid)
    EQ(st3:ActiveTarget(Ctx(10, 0.5, 0.5)), tmp, "E5: it goes: back to the temporary")

    -- the current choice leaves the landmass
    local st4 = S.New(clock, epoch)
    st4.rescanInterval = 0
    local e1 = st4:Add({ map = 10, x = 0.5, y = 0.5, title = "EK" })
    local o1 = st4:Add({ map = 21, x = 0.5, y = 0.5, title = "Outland" })
    EQ(st4:ActiveTarget(Ctx(10, 0.4, 0.5)), e1, "E6: in EK: the EK mark")
    EQ(st4:ActiveTarget(Ctx(20, 0.4, 0.5)), o1, "E6: through the portal: dropped at once for the Outland one")
end)

Section(function()
    -- the throttle: rescans at most every rescanInterval per version
    local st = S.New(clock, epoch)
    st.rescanInterval = 0.5
    for i = 1, 10 do st:Add({ map = 10, x = i / 20, y = 0.5 }) end
    T = 200
    local ctx = Ctx(10, 0.0, 0.5)
    distCalls = 0
    local first = st:ActiveTarget(ctx)
    CHECK(first ~= nil and distCalls >= 10, "E7: the first call scans", distCalls)
    distCalls = 0
    st:ActiveTarget(ctx)
    EQ(distCalls, 0, "E7: within the interval and the same version: no rescan")
    T = 200.6
    ctx = Ctx(10, 0.0, 0.5)
    st:ActiveTarget(ctx)
    CHECK(distCalls >= 10, "E7: after the interval: a rescan", distCalls)
    distCalls = 0
    st:Add({ map = 10, x = 0.001, y = 0.5, title = "new" })
    local picked = st:ActiveTarget(ctx)
    CHECK(distCalls >= 10, "E7: a mutation forces a rescan", distCalls)
    EQ(picked and picked.title, "new", "E7: ...which sees the new record")
    EQ(st:ActiveTarget(Ctx(30, 0.5, 0.5, { now = T })), nil, "E7: a cached pick off the landmass is dropped at once")
    T = 100
end)

-- ===========================================================================
-- F: nearest-of-N alternatives
-- ===========================================================================
Section(function()
    local st = S.New(clock, epoch)
    st.rescanInterval = 0
    -- primary 300 yd east, alt 2 100 yd west, alt 3 on Outland at the player's raw coordinates
    local g = st:Add({ map = 10, x = 0.8, y = 0.5, title = "Giver", setArrow = true,
        alternatives = { { map = 10, x = 0.4, y = 0.5 }, { map = 20, x = 0.5, y = 0.5 } } })
    EQ(#g.alternatives, 3, "F: three candidates")
    local pos, idx = st:Position(g, Ctx(10, 0.5, 0.5))
    CHECK(idx == 2 and pos.x == 0.4, "F: the nearest candidate on the landmass", idx)
    EQ(st:ChosenAlternative(g.uid), 2, "F: ChosenAlternative reports it")
    NEAR(st:Distance(g, Ctx(10, 0.5, 0.5)), 100, "F: distance is to the chosen candidate", 1e-6)
    -- drift east: primary 220, alt2 180 -> no switch; primary 150, alt2 250 -> 40%, 100 yd: switch
    st:Position(g, Ctx(10, 0.58, 0.5))
    EQ(st:ChosenAlternative(g.uid), 2, "F: 220 vs 180: holds alt 2")
    st:Position(g, Ctx(10, 0.62, 0.5))
    EQ(st:ChosenAlternative(g.uid), 2, "F: 180 vs 220 (18%): still holds")
    st:Position(g, Ctx(10, 0.65, 0.5))
    EQ(st:ChosenAlternative(g.uid), 1, "F: 150 vs 250: switches to the primary")
    st:Position(g, Ctx(20, 0.5, 0.5))
    EQ(st:ChosenAlternative(g.uid), 3, "F: on the other landmass: its candidate, at once")
    st:Position(g, Ctx(30, 0.5, 0.5))
    EQ(st:ChosenAlternative(g.uid), 3, "F: on a landmass with none: the choice stands")
    local p2 = st:Position(g, nil)
    EQ(p2 and p2.map, 20, "F: without a player: the last choice")
    local h = st:Add({ map = 10, x = 0.1, y = 0.1, alternatives = { { 10, 0.2, 0.2 } } })
    local p3, i3 = st:Position(h, nil)
    CHECK(i3 == 1 and p3.x == 0.1, "F: never chosen, no player: the primary")
    -- a plain record is its own position; a unit follows ctx.unitPosition
    local plain = st:Add({ map = 10, x = 0.3, y = 0.3 })
    EQ(st:Position(plain, nil), plain, "F: a plain record is its own position")
    local unit = st:Add({ kind = "unit", unit = "party1", title = "Bob", map = 10, x = 0.0, y = 0.0 })
    local up = st:Position(unit, Ctx(10, 0.5, 0.5, { unitPosition = function(u)
        if u == "party1" then return { map = 10, x = 0.55, y = 0.5 } end
    end }))
    CHECK(up and up.x == 0.55, "F: a unit follow is where ctx.unitPosition says")
    -- review-r2 orders: the runtime hands one reused table a unit; a copy a
    -- call churned 1.6 KB/s and missed its world-position cache every frame
    local live = { map = 10, x = 0.55, y = 0.5 }
    EQ(st:Position(unit, Ctx(10, 0.5, 0.5, { unitPosition = function() return live end })), live,
        "F: a keyed unit position is handed on as given, not copied (review-r2)")
    local listed = st:Position(unit, Ctx(10, 0.5, 0.5, { unitPosition = function() return { 10, 0.6, 0.5 } end }))
    CHECK(listed and listed.map == 10 and listed.x == 0.6 and listed.y == 0.5, "F: ...a positional {map, x, y} is still read")
    local wild = { map = 10, x = 1.5, y = 0.5 }
    EQ(st:Position(unit, Ctx(10, 0.5, 0.5, { unitPosition = function() return wild end })), unit,
        "F: ...an out-of-range one is never handed on (the last known position instead)")
    local lost =st:Position(unit, Ctx(10, 0.5, 0.5, { unitPosition = function() return nil end }))
    EQ(lost, unit, "F: a unit out of sight falls back to its last known position")
    local blind = st:Add({ kind = "unit", unit = "party3", title = "Far" })
    EQ(st:Position(blind, Ctx(10, 0.5, 0.5, { unitPosition = function() error("boom") end })), nil,
        "F: no position and an erroring lookup: nil, no error")
    -- the arrow uses the chosen candidate
    st:ClearPinned()
    st:SetPinned(g.uid)
    local ctx = Ctx(10, 0.5, 0.5)
    st._alt[g.uid] = nil
    local ev = st:Tick(ctx, nil, T)
    EQ(Event(ev, "TARGET") and Event(ev, "TARGET").uid, g.uid, "F: the alternatives record is the target")
    EQ(st:ChosenAlternative(g.uid), 2, "F: ...measured to its nearest candidate")
end)

-- ===========================================================================
-- G: routes
-- ===========================================================================
Section(function()
    local st = S.New(clock, epoch)
    local removed = {}
    st.onRemove = function(wp, reason) removed[#removed + 1] = wp.uid .. ":" .. reason end
    local mine = st:Add({ map = 10, x = 0.1, y = 0.1, title = "Bank", setArrow = true })
    local r, err, skipped = st:AddRoute({ title = "Tradecraft: Shattrath trip", source = "Tradecraft", key = "trip:shatt",
        stops = {
            { map = 10, x = 0.1, y = 0.1, title = "Bank" },
            { map = 10, x = 0.5, y = 0.5, title = "Vendor", key = "v1" },
            { map = 10, x = 2, y = 0.5, title = "Broken" },
            { map = 11, x = 0.5, y = 0.5, title = "Trainer", source = "Formulary" },
        } })
    CHECK(r ~= nil, "G: AddRoute returns the route", err)
    EQ(r.id, "r1", "G: the first route is r1")
    EQ(skipped, 1, "G: an invalid stop is skipped and counted")
    EQ(#r.stops, 3, "G: three stops")
    EQ(r.mode, "ORDERED", "G: ORDERED by default")
    EQ(r.index, 1, "G: starts at stop 1")
    EQ(st:ActiveRoute(), r, "G: a new route is active")
    EQ(st:Pinned(), nil, "G: ...and took the arrow from the pin")
    local s1, s2, s3 = st:Get(r.stops[1]), st:Get(r.stops[2]), st:Get(r.stops[3])
    CHECK(s1 ~= mine, "G: a stop never merges with a standalone waypoint at the same place")
    CHECK(s1.kind == "stop" and s2.kind == "stop", "G: stops are kind stop")
    CHECK(s1.routeId == r.id and s1.routeIndex == 1 and s3.routeIndex == 3, "G: stops know their route and place")
    EQ(s1.source, "Tradecraft", "G: a stop inherits the route's source")
    EQ(s3.source, "Formulary", "G: ...unless it names its own")
    EQ(st:ByKey("Tradecraft", "v1"), nil, "G: stop keys are not in the standalone key index")
    local sa = st:Add({ map = 12, x = 0.5, y = 0.5, source = "Tradecraft", key = "v1" })
    CHECK(sa and sa.routeId == nil, "G: so a standalone add with that key is its own record")
    EQ(st:Find(10, 0.5, 0.5, "Vendor"), s2, "G: Find sees route stops")
    EQ(Uids(st:List({ routeId = r.id })), table.concat(r.stops, ","), "G: List by route")

    CHECK(select(2, st:AddRoute({ title = "x" })) == "no stops", "G: no stops list is refused")
    CHECK(select(2, st:AddRoute({ stops = { { map = 0 }, "junk" } })) == "no valid stops", "G: no valid stops is refused")
    EQ(st:GetRoute("r2"), nil, "G: ...and consumed no route id")

    -- next / prev / ends
    local n = st:RouteNext()
    CHECK(n == s2 and r.index == 2, "G: RouteNext steps")
    n = st:RouteNext()
    CHECK(n == s3 and r.index == 3, "G: RouteNext again")
    local none, why = st:RouteNext()
    CHECK(none == nil and why == "last stop" and r.index == 3, "G: RouteNext stops at the last stop of an open route")
    local p = st:RoutePrev()
    CHECK(p == s2 and r.index == 2, "G: RoutePrev steps back")
    st:RoutePrev()
    none, why = st:RoutePrev()
    CHECK(none == nil and why == "first stop" and r.index == 1, "G: RoutePrev stops at the first stop")
    EQ(select(2, S.New(clock, epoch):RouteNext()), "no route", "G: stepping with no route says so")

    -- reverse keeps the current stop current
    st:RouteNext()
    EQ(st:RouteReverse(), true, "G: RouteReverse")
    CHECK(r.stops[1] == s3.uid and r.stops[3] == s1.uid and r.index == 2 and st:Get(r.stops[r.index]) == s2,
        "G: reversed, the current stop is still current")
    CHECK(s3.routeIndex == 1 and s1.routeIndex == 3, "G: routeIndex follows the reversal")

    -- removal bookkeeping
    st:RouteNext()                            -- index 3 (s1)
    st:Remove(s3.uid)                         -- before the current stop
    CHECK(r.index == 2 and st:Get(r.stops[r.index]) == s1, "G: removing an earlier stop keeps the current one")
    st:Remove(s1.uid)                         -- the current (last) stop
    CHECK(r.index == 1 and st:Get(r.stops[1]) == s2, "G: removing the current last stop falls back to the one before")
    st:Remove(s2.uid)
    EQ(st:GetRoute(r.id), nil, "G: removing the last stop removes the route")
    EQ(st:ActiveRoute(), nil, "G: ...and it is no longer active")

    -- start=false, replace by key, RemoveRoute, RemoveBy
    st:SetPinned(mine.uid)
    local q = st:AddRoute({ title = "Quiet", source = "QuestLog", key = "zone:12", start = false,
        stops = { { map = 12, x = 0.1, y = 0.1 }, { map = 12, x = 0.2, y = 0.2 } } })
    CHECK(st:ActiveRoute() == nil and st:Pinned() == mine, "G: start=false neither activates nor unpins")
    st:RouteStart(q.id)
    local old1 = q.stops[1]
    local q2 = st:AddRoute({ title = "Quiet v2", source = "QuestLog", key = "zone:12", start = false,
        stops = { { map = 12, x = 0.5, y = 0.5 } } })
    CHECK(q2.id == q.id and q2.title == "Quiet v2" and #q2.stops == 1, "G: the same (source, key) replaces the route, same id")
    EQ(st:Get(old1), nil, "G: ...its old stops are gone")
    EQ(removed[#removed]:match(":(.*)$"), "replace", "G: ...onRemove says replace")
    EQ(st:ActiveRoute(), q2, "G: ...a replaced active route stays active")
    EQ(#st:Routes(), 1, "G: one route listed")
    local stopUid = q2.stops[1]
    EQ(st:RemoveRoute(q2.id), true, "G: RemoveRoute")
    CHECK(st:Get(stopUid) == nil and st:ActiveRoute() == nil, "G: ...takes its stops and the active flag")
    EQ(st:RemoveRoute("r99"), false, "G: RemoveRoute of an unknown id is false")
    st:AddRoute({ title = "A", source = "Formulary", key = "a", stops = { { map = 10, x = 0.1, y = 0.2 } } })
    st:AddRoute({ title = "B", source = "Formulary", key = "b", stops = { { map = 10, x = 0.1, y = 0.3 }, { map = 10, x = 0.1, y = 0.4 } } })
    st:Add({ map = 10, x = 0.1, y = 0.5, source = "Formulary" })
    EQ(st:RemoveBy("Formulary", "b"), 2, "G: RemoveBy source+key takes that route's stops")
    EQ(st:RemoveBy("Formulary"), 2, "G: RemoveBy source takes routes and standalone records")
    EQ(#st:Routes(), 0, "G: ...no routes left")
    local lc = st:AddRoute({ title = "case", mode = "nearest", stops = { { map = 10, x = 0.1, y = 0.1 } } })
    EQ(lc.mode, "NEAREST", "G: the mode is read case-insensitively")
    EQ(st:AddRoute({ title = "odd", mode = "ZIGZAG", stops = { { map = 10, x = 0.1, y = 0.1 } } }).mode, "ORDERED",
        "G: an unknown mode is ORDERED")
end)

Section(function()
    -- NEAREST ordering, landmass grouping, optimise, add stop
    local st = S.New(clock, epoch)
    local ctx = Ctx(10, 0.0, 0.0)
    local r = st:AddRoute({ title = "N", mode = "NEAREST", stops = {
        { map = 20, x = 0.5, y = 0.5, title = "O1" },    -- Outland, listed first
        { map = 10, x = 0.9, y = 0.0, title = "E3" },
        { map = 30, x = 0.1, y = 0.1, title = "K1" },
        { map = 10, x = 0.1, y = 0.0, title = "E1" },
        { map = 21, x = 0.1, y = 0.5, title = "O2" },    -- world 1100 east: far from O1
        { map = 11, x = 0.5, y = 0.0, title = "E4" },    -- world 1500
        { map = 10, x = 0.5, y = 0.0, title = "E2" },
        { map = 20, x = 0.4, y = 0.5, title = "O0" },
    } }, ctx)
    local titles = {}
    for i, uid in ipairs(r.stops) do titles[i] = st:Get(uid).title end
    EQ(table.concat(titles, " "), "E1 E2 E3 E4 O1 O0 O2 K1",
        "G2: the player's landmass first, nearest-neighbour from the player; then landmasses in order of first stop")
    EQ(st:Get(r.stops[1]).routeIndex, 1, "G2: routeIndex follows the new order")
end)

Section(function()
    local st2 = S.New(clock, epoch)
    local geo = { distance = Dist, sameLandmass = SameLandmass }
    local r2 = st2:AddRoute({ title = "N2", mode = "NEAREST", stops = {
        { map = 10, x = 0.5, y = 0.5, title = "mid" }, { map = 10, x = 0.9, y = 0.5, title = "east" },
        { map = 10, x = 0.6, y = 0.5, title = "near-mid" },
    } }, geo)
    local t = {}
    for i, uid in ipairs(r2.stops) do t[i] = st2:Get(uid).title end
    EQ(table.concat(t, " "), "mid near-mid east", "G3: no player, a geo: chained nearest-neighbour from stop 1")
    local r3 = st2:AddRoute({ title = "plain", mode = "NEAREST", stops = {
        { map = 10, x = 0.9, y = 0.5, title = "a" }, { map = 10, x = 0.1, y = 0.5, title = "b" },
        { map = 10, x = 0.8, y = 0.5, title = "c" },
    } })
    t = {}
    for i, uid in ipairs(r3.stops) do t[i] = st2:Get(uid).title end
    EQ(table.concat(t, " "), "a b c", "G3: no geo at all: the given order")

    -- optimise an ORDERED route; stops behind the current one stay put
    local st = S.New(clock, epoch)
    local r = st:AddRoute({ title = "O", stops = {
        { map = 10, x = 0.0, y = 0.0, title = "done" }, { map = 10, x = 0.9, y = 0.0, title = "far" },
        { map = 10, x = 0.2, y = 0.0, title = "near" }, { map = 10, x = 0.5, y = 0.0, title = "mid" },
    } })
    st:RouteNext()
    local v = st.version
    EQ(st:RouteOptimize({ map = 10, x = 0.1, y = 0.0 }, geo), true, "G3: RouteOptimize")
    t = {}
    for i, uid in ipairs(r.stops) do t[i] = st:Get(uid).title end
    EQ(table.concat(t, " "), "done near mid far", "G3: only the stops ahead are re-ordered, from the player")
    CHECK(st.version > v, "G3: optimise bumps the version")
    EQ(r.mode, "ORDERED", "G3: an optimised ORDERED route stays ORDERED")
    local okO, whyO = st:RouteOptimize({ map = 10, x = 0, y = 0 }, nil)
    CHECK(okO == false and whyO == "no distance", "G3: no geo: refused")
    CHECK(select(2, S.New(clock, epoch):RouteOptimize(nil, geo)) == "no route", "G3: no route: refused")

    -- add a stop
    local s4 = st:AddStop(r.id, { map = 10, x = 0.15, y = 0.0, title = "appended" })
    CHECK(s4 and r.stops[#r.stops] == s4.uid and s4.routeIndex == #r.stops, "G3: AddStop appends on an ORDERED route")
    EQ(s4.kind, "stop", "G3: ...as a stop")
    local rn = st:AddRoute({ title = "NN", mode = "NEAREST", stops = {
        { map = 10, x = 0.1, y = 0.0, title = "n1" }, { map = 10, x = 0.9, y = 0.0, title = "n3" },
    } }, Ctx(10, 0.0, 0.0))
    st:AddStop(rn.id, { map = 10, x = 0.5, y = 0.0, title = "n2" }, Ctx(10, 0.0, 0.0))
    t = {}
    for i, uid in ipairs(rn.stops) do t[i] = st:Get(uid).title end
    EQ(table.concat(t, " "), "n1 n2 n3", "G3: AddStop on a NEAREST route re-orders what is ahead")
    CHECK(select(2, st:AddStop("r99", { map = 10, x = 0.1, y = 0.1 })) == "unknown route", "G3: AddStop to no route")
    CHECK(select(2, st:AddStop(rn.id, { map = 10, x = 7, y = 0.1 })) == "invalid x", "G3: AddStop validates")
    -- RouteStart on NEAREST re-orders from the player
    st:RouteStart(rn.id, Ctx(10, 1.0, 0.0))
    t = {}
    for i, uid in ipairs(rn.stops) do t[i] = st:Get(uid).title end
    EQ(table.concat(t, " "), "n3 n2 n1", "G3: RouteStart re-orders a NEAREST route from where the player stands")
    EQ(st:ActiveRoute(), rn, "G3: ...and makes it active")
    -- loop stepping
    local lp = st:AddRoute({ title = "Patrol", loop = true, stops = {
        { map = 10, x = 0.1, y = 0.1 }, { map = 10, x = 0.2, y = 0.1 },
    } })
    st:RouteNext()
    local w = st:RouteNext()
    CHECK(lp.index == 1 and w and w.uid == lp.stops[1], "G3: RouteNext wraps a loop")
    st:RoutePrev()
    EQ(lp.index, 2, "G3: RoutePrev wraps a loop backwards")
end)

-- ===========================================================================
-- H: the arrival machine
-- ===========================================================================
local function Run(st, ctx, d, now)
    return st:Tick(ctx, d, now)
end

Section(function()
    local st = S.New(clock, epoch)
    local removed = {}
    st.onRemove = function(wp, reason) removed[#removed + 1] = wp.uid .. ":" .. reason end
    local wp = st:Add({ map = 10, x = 0.5, y = 0.5, title = "Target", setArrow = true })
    local ctx = Ctx(10, 0.4, 0.5, { autoClosest = false })     -- 100 yd
    -- a tick has to pass before the record stops being "fresh"
    local ev = Run(st, ctx, nil, 10)
    local tgt = Event(ev, "TARGET")
    CHECK(tgt and tgt.uid == wp.uid and tgt.previous == nil and tgt.why == "PINNED", "H: TARGET on the first tick")
    EQ((st:State() or {}).state, "NAVIGATING", "H: navigating at 100 yd")
    ev = Run(st, Ctx(10, 0.475, 0.5, { autoClosest = false }), nil, 10.1)    -- 25 yd
    EQ(Types(ev), "NEAR", "H: within 3x the radius: NEAR")
    ev = Run(st, Ctx(10, 0.468, 0.5, { autoClosest = false }), nil, 10.2)    -- 32 yd
    EQ(Types(ev), "", "H: 32 yd (between 3x and 3.3x): still NEAR, no flapping")
    ev = Run(st, Ctx(10, 0.466, 0.5, { autoClosest = false }), nil, 10.3)    -- 34 yd
    EQ(Types(ev), "NAVIGATING", "H: beyond 3.3x: back to NAVIGATING")
    ev = Run(st, Ctx(10, 0.475, 0.5, { autoClosest = false }), nil, 10.4)
    EQ(Types(ev), "NEAR", "H: walking back in: NEAR again (re-entry)")
    ev = Run(st, Ctx(10, 0.492, 0.5, { autoClosest = false }), nil, 11)       -- 8 yd
    local arr = Event(ev, "ARRIVED")
    CHECK(arr and arr.uid == wp.uid and arr.title == "Target", "H: within the radius: ARRIVED")
    EQ((st:State() or {}).state, "ARRIVED", "H: ...held")
    ev = Run(st, Ctx(10, 0.495, 0.5, { autoClosest = false }), nil, 12)
    EQ(Types(ev), "", "H: one second later: no second ARRIVED, no DONE yet")
    ev = Run(st, Ctx(10, 0.3, 0.5, { autoClosest = false }), nil, 13.4)
    EQ(Types(ev), "", "H: walking off mid-hold changes nothing (arrived is arrived)")
    CHECK(st:NeedsTick(ctx), "H: the driver must keep ticking through the hold")
    ev = Run(st, Ctx(10, 0.3, 0.5, { autoClosest = false }), nil, 13.5)
    local done = Event(ev, "DONE")
    CHECK(done and done.uid == wp.uid and done.cleared == true, "H: 2.5 s after ARRIVED: DONE, cleared")
    EQ(st:Get(wp.uid), nil, "H: ...the record is gone")
    EQ(removed[#removed], wp.uid .. ":arrived", "H: ...onRemove says arrived")
    local t2 = Event(ev, "TARGET")
    CHECK(t2 and t2.uid == nil and t2.previous == wp.uid, "H: ...and the arrow is handed on (to nothing)")
    EQ(st:State(), nil, "H: no target, no state")
    CHECK(not st:NeedsTick(ctx), "H: nothing left: the driver may sleep")
    -- nothing had the arrow and nothing has it: an idle tick is silent (the
    -- runtime would otherwise hear "no target" ten times a second)
    ev = Run(st, Ctx(10, 0.3, 0.5, { autoClosest = false }), nil, 13.6)
    EQ(Types(ev), "", "H: an idle tick with no target emits nothing (no TARGET nil -> nil)")
    ev = Run(st, Ctx(10, 0.3, 0.5, { autoClosest = false }), nil, 13.7)
    EQ(Types(ev), "", "H: ...and neither does the next one")
    EQ(ev, S.NO_EVENTS, "H: a tick with nothing to say hands back the shared empty list")
    CHECK(not pcall(function() ev[1] = "x" end) and #S.NO_EVENTS == 0, "H: ...which is read only")
    EQ(st:ArrivalState(), nil, "H: ArrivalState with no target is nil")

    -- the 10 Hz pass allocates nothing on a quiet tick (review: runtime,
    -- 64 B a tick for the events array, 160 B for State's copy)
    local qs = S.New(clock, epoch)
    local qw = qs:Add({ map = 10, x = 0.5, y = 0.5, title = "Far", setArrow = true })
    local qc = Ctx(10, 0.4, 0.5, { autoClosest = false })
    local first = Run(qs, qc, 100, 20)
    CHECK(first ~= S.NO_EVENTS and Event(first, "TARGET") ~= nil, "H: the first event makes a fresh list")
    local quiet = Run(qs, qc, 100, 20.1)
    EQ(quiet, S.NO_EVENTS, "H: steady navigating: the shared empty list")
    CHECK(Event(first, "TARGET") ~= nil, "H: ...an earlier tick's list is untouched by the next")
    local au, as = qs:ArrivalState()
    CHECK(au == qw.uid and as == "NAVIGATING", "H: ArrivalState is uid, state", tostring(au) .. " " .. tostring(as))
    collectgarbage("collect")
    collectgarbage("stop")
    local kb0 = collectgarbage("count")
    for i = 1, 2000 do
        Run(qs, qc, 100, 20.1 + i * 0.1)
        qs:ArrivalState()
    end
    local grown = collectgarbage("count") - kb0
    collectgarbage("restart")
    CHECK(grown < 16, "H: 2000 quiet ticks and arrival reads allocate (next to) nothing", string.format("%.1f KB", grown))

    -- review-r2 orders: following a member on another landmass, the runtime
    -- cannot measure (nil distance) and the Store asks unitPosition every
    -- tick; its one reused table must not be copied (160 B a tick before)
    local fs = S.New(clock, epoch)
    local followed = { map = 20, x = 0.5, y = 0.5 }
    local fc = Ctx(10, 0.4, 0.5, { autoClosest = false, unitPosition = function() return followed end })
    local fw = fs:Add({ kind = "unit", unit = "party1", title = "Bob", setArrow = true })
    Run(fs, fc, nil, 30)
    EQ(fs:Pinned(), fw, "H: (following Bob, on another landmass)")
    EQ(fs:Distance(fw, fc), nil, "H: ...who cannot be measured from here")
    Run(fs, fc, nil, 30.1)
    -- interpreted: LuaJIT's trace recorder allocates 10-25 KB of its own
    -- across this loop, as much as the 160 B a tick being looked for
    local jit = rawget(_G, "jit")
    if jit then jit.flush() jit.off() end
    collectgarbage("collect")
    collectgarbage("stop")
    kb0 = collectgarbage("count")
    for i = 1, 2000 do
        Run(fs, fc, nil, 30.1 + i * 0.1)
    end
    grown = collectgarbage("count") - kb0
    collectgarbage("restart")
    if jit then jit.on() end
    CHECK(grown < 16, "H: 2000 ticks following a member on another landmass allocate (next to) nothing (review-r2)",
        string.format("%.1f KB", grown))
end)

Section(function()
    -- the radius: record, then setting, then 10
    local st = S.New(clock, epoch)
    local a = st:Add({ map = 10, x = 0.5, y = 0.5, setArrow = true })
    Run(st, Ctx(10, 0.3, 0.5), nil, 1)
    local ev = Run(st, Ctx(10, 0.485, 0.5, { arriveYards = 20 }), nil, 2)   -- 15 yd
    CHECK(Event(ev, "ARRIVED") ~= nil, "H2: ArriveYards 20 arrives at 15 yd")
    local st2 = S.New(clock, epoch)
    st2:Add({ map = 10, x = 0.5, y = 0.5, setArrow = true, arrive = 5 })
    Run(st2, Ctx(10, 0.3, 0.5), nil, 1)
    ev = Run(st2, Ctx(10, 0.493, 0.5, { arriveYards = 20 }), nil, 2)        -- 7 yd
    CHECK(Event(ev, "ARRIVED") == nil, "H2: a record's own 5 yd beats the setting")
    ev = Run(st2, Ctx(10, 0.497, 0.5, { arriveYards = 20 }), nil, 3)        -- 3 yd
    CHECK(Event(ev, "ARRIVED") ~= nil, "H2: ...and arrives inside it")
    -- the runtime's own distance is used when given
    local st3 = S.New(clock, epoch)
    st3:Add({ map = 10, x = 0.5, y = 0.5, setArrow = true })
    Run(st3, Ctx(10, 0.1, 0.5), nil, 1)
    ev = Run(st3, Ctx(10, 0.1, 0.5), 4, 2)
    CHECK(Event(ev, "ARRIVED") ~= nil, "H2: the distance passed in wins over ctx")
    -- no distance at all: nothing moves
    local st4 = S.New(clock, epoch)
    st4:Add({ map = 20, x = 0.5, y = 0.5, setArrow = true })
    ev = Run(st4, Ctx(10, 0.5, 0.5), nil, 1)
    EQ(Types(ev), "TARGET", "H2: off the landmass: only TARGET (no measuring across 530)")
    ev = Run(st4, Ctx(10, 0.5, 0.5), nil, 2)
    EQ(Types(ev), "", "H2: ...and nothing after")
    EQ((st4:State() or {}).state, "NAVIGATING", "H2: ...navigating, never arriving")
end)

Section(function()
    -- taxi
    local st = S.New(clock, epoch)
    local wp = st:Add({ map = 10, x = 0.5, y = 0.5, setArrow = true })
    Run(st, Ctx(10, 0.2, 0.5, { onTaxi = true }), nil, 1)
    local ev = Run(st, Ctx(10, 0.48, 0.5, { onTaxi = true }), nil, 2)       -- 20 yd
    EQ(Types(ev), "", "H3: on a taxi within 3x: no NEAR")
    ev = Run(st, Ctx(10, 0.5, 0.5, { onTaxi = true }), nil, 3)
    EQ(Types(ev), "", "H3: on a taxi right over it: no ARRIVED")
    EQ((st:State() or {}).state, "NAVIGATING", "H3: ...still navigating")
    ev = Run(st, Ctx(10, 0.6, 0.5, { onTaxi = true }), nil, 4)
    ev = Run(st, Ctx(10, 0.505, 0.5, { onTaxi = false }), nil, 5)
    CHECK(Event(ev, "ARRIVED") ~= nil, "H3: landing on it arrives")
    -- NEAR then taxi drops back to NAVIGATING
    local st2 = S.New(clock, epoch)
    st2:Add({ map = 10, x = 0.5, y = 0.5, setArrow = true })
    Run(st2, Ctx(10, 0.2, 0.5), nil, 1)
    Run(st2, Ctx(10, 0.48, 0.5), nil, 2)
    ev = Run(st2, Ctx(10, 0.48, 0.5, { onTaxi = true }), nil, 3)
    EQ(Types(ev), "NAVIGATING", "H3: taking a taxi from NEAR: NAVIGATING")
    CHECK(wp ~= nil, "H3: (record existed)")
end)

Section(function()
    -- the fresh-born rule
    local st = S.New(clock, epoch)
    local here = st:Add({ map = 10, x = 0.5, y = 0.5, title = "Here", setArrow = true })   -- /wayb
    local ctx = Ctx(10, 0.5, 0.5)
    local ev = Run(st, ctx, nil, 1)
    CHECK(Event(ev, "ARRIVED") == nil and Event(ev, "NEAR") ~= nil, "H4: created under the player: NEAR, never ARRIVED")
    EQ((st:State() or {}).armed, false, "H4: ...unarmed")
    for i = 2, 5 do ev = Run(st, ctx, nil, i) end
    EQ(Types(ev), "", "H4: standing on it for seconds: nothing")
    CHECK(st:Get(here.uid) ~= nil, "H4: /wayb does not clear itself")
    ev = Run(st, Ctx(10, 0.515, 0.5), nil, 6)      -- 15 yd: armed
    EQ((st:State() or {}).armed, true, "H4: leaving the radius arms it")
    ev = Run(st, Ctx(10, 0.505, 0.5), nil, 7)
    CHECK(Event(ev, "ARRIVED") ~= nil, "H4: coming back arrives")

    -- an old record pinned while standing on it arrives at once
    local st2 = S.New(clock, epoch)
    local old = st2:Add({ map = 10, x = 0.5, y = 0.5, title = "Old" })
    st2:Add({ map = 10, x = 0.9, y = 0.9, title = "Other", setArrow = true })
    Run(st2, ctx, nil, 1)
    Run(st2, ctx, nil, 2)
    st2:SetPinned(old.uid)
    ev = Run(st2, ctx, nil, 3)
    CHECK(Event(ev, "TARGET") and Event(ev, "ARRIVED"), "H4: a record made long ago and chosen on the spot arrives", Types(ev))

    -- route stops standing next to each other are not "fresh"
    local st3 = S.New(clock, epoch)
    local r = st3:AddRoute({ title = "Givers", stops = {
        { map = 10, x = 0.3, y = 0.5, title = "G1" }, { map = 10, x = 0.304, y = 0.5, title = "G2" },
    } })
    Run(st3, Ctx(10, 0.1, 0.5), nil, 1)
    ev = Run(st3, Ctx(10, 0.3, 0.5), nil, 2)
    CHECK(Event(ev, "ARRIVED") and Event(ev, "ARRIVED").uid == r.stops[1], "H4: route stop 1 arrives")
    ev = Run(st3, Ctx(10, 0.301, 0.5), nil, 4.6)
    CHECK(Event(ev, "DONE") and Event(ev, "ADVANCE") and Event(ev, "TARGET"), "H4: DONE, ADVANCE, TARGET", Types(ev))
    EQ(Event(ev, "ADVANCE").index, 1, "H4: the cleared stop left: index 1 is now G2")
    ev = Run(st3, Ctx(10, 0.301, 0.5), nil, 4.7)
    CHECK(Event(ev, "ARRIVED") ~= nil, "H4: G2, 3 yd away and created long ago, arrives without a step out")

    -- a loaded store: the first tick is fresh for everything
    local st4 = S.Load(S.New(clock, epoch):Serialize(), clock, epoch)
    st4:Add({ map = 10, x = 0.5, y = 0.5, setArrow = true })
    local st5 = S.Load(st4:Serialize(), clock, epoch)
    ev = Run(st5, ctx, nil, 1)
    CHECK(Event(ev, "ARRIVED") == nil, "H4: after a /reload on top of a mark: no instant arrival")
end)

Section(function()
    -- clearOnArrive false: reached, unpinned, skipped by closest, re-armable
    local st = S.New(clock, epoch)
    st.rescanInterval = 0
    local place = st:Add({ map = 10, x = 0.5, y = 0.5, title = "Rally 1", source = "place", setArrow = true })
    local other = st:Add({ map = 10, x = 0.9, y = 0.5, title = "Other" })
    Run(st, Ctx(10, 0.2, 0.5), nil, 1)
    local ev = Run(st, Ctx(10, 0.5, 0.5), nil, 2)
    CHECK(Event(ev, "ARRIVED") ~= nil, "H5: a place arrives")
    ev = Run(st, Ctx(10, 0.5, 0.5), nil, 4.5)
    local done = Event(ev, "DONE")
    CHECK(done and done.cleared == false, "H5: DONE, not cleared")
    CHECK(st:Get(place.uid) == place and place.reached == E, "H5: the place stays, marked reached")
    EQ(st:Pinned(), nil, "H5: ...and lets go of the arrow")
    local t = Event(ev, "TARGET")
    CHECK(t and t.uid == other.uid and t.why == "CLOSEST", "H5: the arrow moves on to the next closest, not back to it")
    EQ(st:Count({ reached = true }), 1, "H5: List can find reached marks (Clear completed)")
    st:SetPinned(place.uid)
    EQ(place.reached, nil, "H5: choosing it again un-reaches it")
    ev = Run(st, Ctx(10, 0.5, 0.5), nil, 5)
    CHECK(Event(ev, "ARRIVED") ~= nil, "H5: ...and standing on it, it arrives again")
end)

Section(function()
    -- a target that loses the arrow mid-hold still gets its DONE
    local st = S.New(clock, epoch)
    local a = st:Add({ map = 10, x = 0.5, y = 0.5, title = "A", setArrow = true })
    Run(st, Ctx(10, 0.2, 0.5), nil, 1)
    Run(st, Ctx(10, 0.5, 0.5), nil, 2)
    local b = st:Add({ map = 10, x = 0.9, y = 0.9, title = "B", setArrow = true })
    local ev = Run(st, Ctx(10, 0.5, 0.5), nil, 3)
    CHECK(Event(ev, "TARGET") and Event(ev, "TARGET").uid == b.uid and Event(ev, "TARGET").previous == a.uid,
        "H6: the user picks B mid-hold: TARGET B")
    CHECK(st:NeedsTick(nil), "H6: the parked arrival keeps the driver awake")
    ev = Run(st, Ctx(10, 0.5, 0.5), nil, 4.6)
    local done = Event(ev, "DONE")
    CHECK(done and done.uid == a.uid and st:Get(a.uid) == nil, "H6: A still finishes and clears")
    EQ(st:Pinned(), b, "H6: ...without touching B's pin")
    -- the arrow leaves mid-hold and comes straight back: the hold resumes
    local st3 = S.New(clock, epoch)
    local h1 = st3:Add({ map = 10, x = 0.5, y = 0.5, title = "H1", setArrow = true })
    local h2 = st3:Add({ map = 10, x = 0.9, y = 0.9, title = "H2" })
    Run(st3, Ctx(10, 0.2, 0.5), nil, 1)
    Run(st3, Ctx(10, 0.5, 0.5), nil, 2)                  -- ARRIVED at 2
    st3:SetPinned(h2.uid)
    Run(st3, Ctx(10, 0.5, 0.5), nil, 2.5)
    st3:SetPinned(h1.uid)
    local back = Run(st3, Ctx(10, 0.5, 0.5), nil, 3)
    CHECK(Event(back, "TARGET") and Event(back, "ARRIVED") == nil, "H6: back on a record mid-hold: no second ARRIVED")
    EQ((st3:State() or {}).state, "ARRIVED", "H6: ...its hold resumes")
    local fin = Run(st3, Ctx(10, 0.5, 0.5), nil, 4.5)
    CHECK(CountEvents(fin, "DONE") == 1 and st3:Get(h1.uid) == nil, "H6: ...one DONE, at the original time")
    -- removed mid-hold: no DONE, no error
    local st2 = S.New(clock, epoch)
    local c = st2:Add({ map = 10, x = 0.5, y = 0.5, setArrow = true })
    Run(st2, Ctx(10, 0.2, 0.5), nil, 1)
    Run(st2, Ctx(10, 0.5, 0.5), nil, 2)
    st2:Remove(c.uid)
    local ok, ev2 = pcall(st2.Tick, st2, Ctx(10, 0.5, 0.5), nil, 5)
    CHECK(ok and Event(ev2, "DONE") == nil and Event(ev2, "TARGET") ~= nil, "H6: removed mid-hold: no DONE, TARGET nil")
end)

Section(function()
    -- a kept corpse stays the target after DONE: it must be left before it arrives again
    local st = S.New(clock, epoch)
    st:Add({ kind = "corpse", map = 10, x = 0.5, y = 0.5, clearOnArrive = false })
    local g = { ghost = true }
    Run(st, Ctx(10, 0.2, 0.5, g), nil, 1)
    Run(st, Ctx(10, 0.5, 0.5, g), nil, 2)
    local ev = Run(st, Ctx(10, 0.5, 0.5, g), nil, 4.5)
    CHECK(Event(ev, "DONE") and Event(ev, "NEAR") and not Event(ev, "TARGET"), "H7: DONE, same target, back to NEAR", Types(ev))
    ev = Run(st, Ctx(10, 0.5, 0.5, g), nil, 5)
    EQ(Types(ev), "", "H7: standing there: no second ARRIVED")
    Run(st, Ctx(10, 0.52, 0.5, g), nil, 6)
    ev = Run(st, Ctx(10, 0.5, 0.5, g), nil, 7)
    CHECK(Event(ev, "ARRIVED") ~= nil, "H7: out and back: arrives again")
end)

Section(function()
    -- a route all the way through
    local st = S.New(clock, epoch)
    local completed
    local r = st:AddRoute({ title = "Tradecraft: Shattrath trip", source = "Tradecraft", key = "trip", stops = {
        { map = 10, x = 0.2, y = 0.5, title = "S1" },
        { map = 10, x = 0.4, y = 0.5, title = "S2", clearOnArrive = false },
        { map = 10, x = 0.6, y = 0.5, title = "S3" },
    } })
    local s1, s2, s3 = r.stops[1], r.stops[2], r.stops[3]
    local now = 1
    -- walk up to a stop: 100 yd short (seen, armed), onto it (ARRIVED), then
    -- wait out the hold (DONE); returns every event on the way
    local function Visit(store, x)
        local all = {}
        local function At(px, dt)
            now = now + dt
            for _, e in ipairs(Run(store, Ctx(10, px, 0.5), nil, now)) do all[#all + 1] = e end
        end
        At(x - 0.1, 0.2)
        At(x, 0.2)
        At(x, 3.0)
        return all
    end
    local ev = Visit(st, 0.2)
    CHECK(Event(ev, "ARRIVED") and Event(ev, "ARRIVED").uid == s1, "H8: stop 1 arrives")
    CHECK(Event(ev, "DONE") and Event(ev, "DONE").cleared == true and st:Get(s1) == nil, "H8: ...cleared")
    CHECK(Event(ev, "ADVANCE") and Event(ev, "ADVANCE").uid == s2, "H8: ...ADVANCE to stop 2")
    ev = Visit(st, 0.4)
    CHECK(Event(ev, "DONE") and Event(ev, "DONE").cleared == false, "H8: stop 2 keeps (clearOnArrive false)")
    CHECK(st:Get(s2) and st:Get(s2).reached ~= nil, "H8: ...marked reached")
    CHECK(Event(ev, "ADVANCE") and Event(ev, "ADVANCE").uid == s3 and r.index == 2, "H8: ...ADVANCE to stop 3")
    ev = Visit(st, 0.6)
    completed = Event(ev, "ROUTE_COMPLETE")
    CHECK(completed and completed.title == "Tradecraft: Shattrath trip" and completed.source == "Tradecraft"
        and completed.key == "trip", "H8: the last stop: ROUTE_COMPLETE with the title for the toast")
    CHECK(st:GetRoute(r.id) == nil and st:Get(s2) == nil and st:Get(s3) == nil, "H8: ...the route and its kept stops are gone")
    EQ(Event(ev, "ADVANCE"), nil, "H8: ...no ADVANCE past the end")
    -- a loop wraps and never clears
    local st2 = S.New(clock, epoch)
    local lp = st2:AddRoute({ title = "Patrol", loop = true, stops = {
        { map = 10, x = 0.2, y = 0.5 }, { map = 10, x = 0.6, y = 0.5 },
    } })
    ev = Visit(st2, 0.2)
    CHECK(Event(ev, "DONE") and Event(ev, "DONE").cleared == false and #lp.stops == 2, "H8: a loop never clears its stops")
    ev = Visit(st2, 0.6)
    CHECK(Event(ev, "ADVANCE") and Event(ev, "ADVANCE").index == 1, "H8: the last stop of a loop wraps to 1")
    CHECK(st2:Get(lp.stops[1]).reached == nil and st2:Get(lp.stops[2]).reached == nil, "H8: ...clearing the reached marks")
    EQ(Event(ev, "ROUTE_COMPLETE"), nil, "H8: a loop never completes")
end)

-- ===========================================================================
-- I: distance bands (the TomTom shim)
-- ===========================================================================
Section(function()
    local st = S.New(clock, epoch)
    local calls = {}
    local HANDLE = { 10, 0.5, 0.5, title = "Shim", from = "Questie" }
    local cbs = { distance = {
        [10] = function(ev, uid, range, d, last) calls[#calls + 1] = { ev, uid, range, d, last } end,
        [15] = function(ev, uid, range, d, last) calls[#calls + 1] = { ev, uid, range, d, last } end,
        [0] = "not a function", banana = function() end,
    } }
    local wp = st:Add({ map = 10, x = 0.5, y = 0.5, title = "Shim", source = "TomTom:Questie",
        callbacks = cbs, handle = HANDLE })
    CHECK(wp.callbacks and #wp.callbacks.bands == 2 and wp.callbacks.bands[1] == 10 and wp.callbacks.bands[2] == 15,
        "I: band radii are sorted; non-function and non-number entries dropped")
    CHECK(wp.callbacks.distance ~= cbs.distance, "I: the caller's callbacks table is copied, not kept")
    CHECK(st:NeedsTick(Ctx(10, 0.4, 0.5, { autoClosest = false })), "I: callbacks keep the driver awake without a target")
    local function at(x) return Ctx(10, x, 0.5, { autoClosest = false }) end
    st:Tick(at(0.488), nil, 1)                                   -- 12 yd
    EQ(#calls, 1, "I: first tick inside the 15 band: one call")
    local c = calls[1]
    CHECK(c and c[1] == "distance" and c[2] == HANDLE and c[3] == 15 and math.abs(c[4] - 12) < 1e-6 and c[5] == nil,
        "I: ...innermost band, the handle, lastDistance nil (TomTom parity)")
    st:Tick(at(0.489), nil, 2)                                   -- 11
    EQ(#calls, 1, "I: same band: nothing")
    st:Tick(at(0.491), nil, 3)                                   -- 9
    EQ(#calls, 2, "I: crossing 10 inward: one call")
    CHECK(calls[2] and calls[2][3] == 10 and math.abs(calls[2][5] - 11) < 1e-6,
        "I: ...range 10, lastDistance the previous tick's")
    st:Tick(at(0.488), nil, 4)                                   -- 12, outward
    st:Tick(at(0.48), nil, 5)                                    -- 20, outside
    EQ(#calls, 2, "I: outward crossings fire nothing (no ping on the way out)")
    st:Tick(at(0.495), nil, 6)                                   -- 5, from outside
    EQ(#calls, 4, "I: outside straight to the inner band: both bands fire")
    CHECK(calls[4] and calls[3][3] == 15 and calls[4][3] == 10, "I: ...outermost first")
    CHECK(calls[4] and math.abs(calls[3][5] - 20) < 1e-6 and math.abs(calls[4][5] - 20) < 1e-6,
        "I: ...both with lastDistance 20")
    st:Tick(Ctx(20, 0.4, 0.5, { autoClosest = false }), nil, 7)  -- other landmass: unmeasurable
    st:Tick(at(0.48), nil, 8)                                    -- 20
    st:Tick(at(0.485), nil, 9)                                   -- 15: on the line counts as inside
    EQ(#calls, 5, "I: off the landmass and back is not a first tick again; the 15 band fires on its line")
    CHECK(calls[5] and math.abs(calls[5][5] - 20) < 1e-6, "I: ...lastDistance from before")

    -- outside on the first tick: nothing; the handle defaults to the uid
    local st2 = S.New(clock, epoch)
    local got = {}
    local w2 = st2:Add({ map = 10, x = 0.5, y = 0.5, callbacks = { distance = { [10] = function(_, uid, range, d, last)
        got[#got + 1] = { uid, range, last }
    end } } })
    st2:Tick(Ctx(10, 0.3, 0.5), nil, 1)
    EQ(#got, 0, "I2: first tick outside every band: nothing")
    st2:Tick(Ctx(10, 0.495, 0.5), nil, 2)
    CHECK(#got == 1 and got[1][1] == w2.uid and got[1][2] == 10, "I2: no handle given: the record's uid")
    -- the target's passed distance is used for its bands
    local st3 = S.New(clock, epoch)
    local hits = 0
    st3:Add({ map = 10, x = 0.5, y = 0.5, setArrow = true, callbacks = { distance = { [10] = function() hits = hits + 1 end } } })
    st3:Tick(Ctx(10, 0.1, 0.5), 50, 1)
    st3:Tick(Ctx(10, 0.1, 0.5), 5, 2)
    EQ(hits, 1, "I2: the target's bands use the distance the runtime passed")
    -- bands fire on a taxi (the callback decides, as in TomTom)
    local st4 = S.New(clock, epoch)
    local taxiHits = 0
    st4:Add({ map = 10, x = 0.5, y = 0.5, callbacks = { distance = { [10] = function() taxiHits = taxiHits + 1 end } } })
    st4:Tick(Ctx(10, 0.3, 0.5, { onTaxi = true }), nil, 1)
    st4:Tick(Ctx(10, 0.5, 0.5, { onTaxi = true }), nil, 2)
    EQ(taxiHits, 1, "I2: bands fire on a taxi")
end)

Section(function()
    -- errors, re-entrancy, a move resets the band state
    local st = S.New(clock, epoch)
    local order = {}
    local bad = st:Add({ map = 10, x = 0.5, y = 0.5, title = "bad", callbacks = { distance = {
        [10] = function() error("third-party bug") end,
        [15] = function() order[#order + 1] = "bad15" end,
    } } })
    local selfRemove
    selfRemove = st:Add({ map = 10, x = 0.5, y = 0.51, title = "self", callbacks = { distance = {
        [15] = function() order[#order + 1] = "self15" st:Remove(selfRemove.uid) end,
        [10] = function() order[#order + 1] = "self10" end,
    } } })
    local spawned
    st:Add({ map = 10, x = 0.5, y = 0.52, title = "spawner", callbacks = { distance = {
        [30] = function() spawned = st:Add({ map = 10, x = 0.6, y = 0.6, title = "spawned" }) end,
    } } })
    st:Tick(Ctx(10, 0.3, 0.5), nil, 1)          -- everyone outside
    local ok, ev = pcall(st.Tick, st, Ctx(10, 0.5, 0.505), nil, 2)   -- 5 yd from bad and self
    CHECK(ok, "I3: a callback error does not escape Tick", ev)
    local e = ok and Event(ev, "CALLBACK_ERROR")
    CHECK(e and e.uid == bad.uid and e.range == 10 and tostring(e.err):find("third-party bug", 1, true),
        "I3: ...it comes back as CALLBACK_ERROR")
    CHECK(order[1] == "bad15", "I3: ...the outer band of the same record still fired first")
    CHECK(order[2] == "self15" and order[3] == nil, "I3: a callback that removes its record stops that record's bands")
    EQ(st:Get(selfRemove.uid), nil, "I3: ...and the removal stuck")
    CHECK(spawned ~= nil, "I3: a callback may add a waypoint mid-tick")
    -- a record a callback adds mid-tick counts as born in the NEXT tick, so
    -- the fresh rule covers it exactly as it covers one added between ticks
    if spawned then
        st:SetPinned(spawned.uid)
        local ev2 = st:Tick(Ctx(10, 0.6, 0.6), nil, 3)
        CHECK(Event(ev2, "ARRIVED") == nil, "I3: a record added mid-tick is fresh on the next tick")
    end
    -- a move resets the band state: the next tick is a first tick again
    local st2 = S.New(clock, epoch)
    local seen = {}
    local m = st2:Add({ map = 10, x = 0.5, y = 0.5, callbacks = { distance = { [10] = function(_, _, _, _, last)
        seen[#seen + 1] = last == nil and "first" or "crossed"
    end } } })
    st2:Tick(Ctx(10, 0.3, 0.5), nil, 1)
    st2:Update(m.uid, { x = 0.3 })
    st2:Tick(Ctx(10, 0.3, 0.5), nil, 2)
    EQ(seen[1], "first", "I3: after a move the record is new to the bands (lastDistance nil)")
    EQ(st2:Serialize().Waypoints[1].callbacks, nil, "I3: callbacks never reach the saved variables")
end)

-- ===========================================================================
-- J: Serialize / Load
-- ===========================================================================
local function Walk(v, path, seen, problems)
    local t = type(v)
    if t == "table" then
        if seen[v] then problems[#problems + 1] = "shared or cyclic table at " .. path return end
        seen[v] = true
        if getmetatable(v) then problems[#problems + 1] = "metatable at " .. path end
        for k, val in pairs(v) do
            local kt = type(k)
            if kt ~= "string" and kt ~= "number" then problems[#problems + 1] = kt .. " key at " .. path end
            Walk(val, path .. "." .. tostring(k), seen, problems)
        end
    elseif t ~= "string" and t ~= "number" and t ~= "boolean" then
        problems[#problems + 1] = t .. " at " .. path
    elseif t == "number" and v ~= v then
        problems[#problems + 1] = "NaN at " .. path
    end
end

-- The client's SV writer, as far as this matters: numbers at N significant
-- digits, strings quoted, tables in full, nothing else allowed.
local function Write(v, fmt)
    local t = type(v)
    if t == "number" then return string.format(fmt, v) end
    if t == "string" then return string.format("%q", v) end
    if t == "boolean" then return tostring(v) end
    if t == "table" then
        local parts = {}
        for k, val in pairs(v) do parts[#parts + 1] = "[" .. Write(k, fmt) .. "]=" .. Write(val, fmt) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    error("cannot write a " .. t)
end
local function RoundTrip(plain, fmt)
    return assert(loadstring("return " .. Write(plain, fmt or "%.16g")))()
end

Section(function()
    local st = S.New(clock, epoch)
    local hook = 0
    st.onRemove = function() hook = hook + 1 end
    local a = st:Add({ map = 1944, x = 0.3820961713790894, y = 0.6684517860412598, title = "Nazgrel",
        source = "QuestLog", key = "quest:9", icon = "QUEST", colour = "GOLD", note = "turn in",
        alternatives = { { 1944, 0.1, 0.2 }, { 1944, 0.7, 0.8 } }, arrive = 12, setArrow = true,
        callbacks = { distance = { [10] = function() end } }, handle = { 1944, 0.38, 0.66 } })
    local session = st:Add({ map = 10, x = 0.5, y = 0.5, title = "session only", persistent = false })
    local unit = st:Add({ kind = "unit", unit = "party1", title = "Bob" })
    local corpse = st:Add({ kind = "corpse", map = 10, x = 0.11, y = 0.22 })
    local place = st:Add({ map = 10, x = 0.33, y = 0.44, title = "Rally 1", source = "place" })
    place.reached = E - 5
    local r = st:AddRoute({ title = "Trip", source = "Tradecraft", key = "trip", mode = "ORDERED", stops = {
        { map = 11, x = 0.1, y = 0.1, title = "T1" }, { map = 11, x = 0.2, y = 0.2, title = "T2" },
        { map = 11, x = 0.3, y = 0.3, title = "T3" },
    } })
    st:RouteNext()
    local gone = st:AddRoute({ title = "Gone", persistent = false, start = false, stops = { { map = 12, x = 0.5, y = 0.5 } } })
    st:SetPinned(a.uid)
    local nextBefore = st.nextUid

    local plain = st:Serialize()
    local problems = {}
    Walk(plain, "Store", {}, problems)
    CHECK(#problems == 0, "J: Serialize is plain data (no functions, userdata, metatables, shared tables)", problems[1])
    EQ(plain.Schema, S.SCHEMA, "J: versioned")
    EQ(#plain.Waypoints, 7, "J: session-only records and non-persistent routes stay out")
    for _, w in ipairs(plain.Waypoints) do
        CHECK(w.uid ~= session.uid and w.uid ~= gone.stops[1], "J: ..." .. tostring(w.uid) .. " is a persistent record")
        EQ(w.callbacks, nil, "J: ...no callbacks on " .. tostring(w.uid))
    end
    EQ(#plain.Routes, 1, "J: one persistent route")
    EQ(plain.Pinned, a.uid, "J: the pin is saved")
    EQ(plain.ActiveRoute, r.id, "J: the active route is saved")
    EQ(plain.NextUid, nextBefore, "J: the uid counter is saved")
    EQ(plain.Routes[1].index, 2, "J: the route's place is saved")
    EQ(type(plain.Waypoints[1].alternatives[1]), "table", "J: alternatives saved")
    EQ(plain.Waypoints[1].alternatives[1][1], 1944, "J: ...compactly, as {map, x, y}")

    for _, fmt in ipairs({ "%.16g", "%.17g", "%.14g" }) do
        local back = RoundTrip(plain, fmt)
        local ld = S.Load(back, clock, epoch)
        local tag = " (" .. fmt .. ")"
        EQ(#ld:List(), 7, "J: Load restores every record" .. tag)
        local la = ld:Get(a.uid)
        CHECK(la and la.title == "Nazgrel" and la.source == "QuestLog" and la.key == "quest:9" and la.icon == "QUEST"
            and la.colour == "GOLD" and la.note == "turn in" and la.arrive == 12, "J: fields survive" .. tag)
        NEAR(la and la.x, 0.3820961713790894, "J: x survives within 1e-6" .. tag, 1e-6)
        NEAR(la and la.y, 0.6684517860412598, "J: y survives within 1e-6" .. tag, 1e-6)
        CHECK(la and #la.alternatives == 3, "J: alternatives survive" .. tag)
        EQ(la and la.callbacks, nil, "J: callbacks do not" .. tag)
        EQ(ld:ByKey("QuestLog", "quest:9"), la, "J: the key index is rebuilt" .. tag)
        EQ(ld:Find(1944, 0.3820961713790894, 0.6684517860412598, "Nazgrel"), la,
            "J: the original numbers find the restored record (the stale-uid case)" .. tag)
        local again, _, status = ld:Add({ map = 1944, x = 0.3820961713790894, y = 0.6684517860412598, title = "Nazgrel" })
        CHECK(again == la and status == "existing", "J: re-adding the original numbers is not a twin" .. tag)
        EQ(ld:Pinned(), la, "J: the pin is back" .. tag)
        local lr = ld:ActiveRoute()
        CHECK(lr and lr.id == r.id and lr.index == 2 and #lr.stops == 3 and lr.key == "trip", "J: the route is back, in place" .. tag)
        CHECK(lr and ld:Get(lr.stops[2]).routeIndex == 2 and ld:Get(lr.stops[2]).kind == "stop", "J: stops are stops" .. tag)
        EQ(ld:Get(unit.uid).unit, "party1", "J: a unit follow survives" .. tag)
        EQ(ld:Corpse() and ld:Corpse().uid, corpse.uid, "J: the corpse survives" .. tag)
        EQ(ld:Get(place.uid).reached, E - 5, "J: reached survives" .. tag)
        EQ(ld:Get(place.uid).clearOnArrive, false, "J: clearOnArrive false survives" .. tag)
        local fresh = ld:Add({ map = 12, x = 0.9, y = 0.9 })
        EQ(fresh.uid, "w" .. nextBefore, "J: the uid counter continues" .. tag)
        EQ(ld.version, 1 + 1, "J: a loaded store starts at version 1" .. tag)
        local second = ld:Serialize()
        local p2 = {}
        Walk(second, "again", {}, p2)
        CHECK(#p2 == 0 and #second.Waypoints == 8, "J: a loaded store serializes again" .. tag)
    end
    EQ(hook, 0, "J: serializing removes nothing")

    -- the counter continues even when nothing was persisted
    local st2 = S.New(clock, epoch)
    for i = 1, 5 do st2:Add({ map = 10, x = i / 10, y = 0.5, persistent = false }) end
    local p2 = RoundTrip(st2:Serialize())
    EQ(#p2.Waypoints, 0, "J: nothing persistent, nothing saved")
    EQ(S.Load(p2, clock, epoch):Add({ map = 10, x = 0.5, y = 0.5 }).uid, "w6",
        "J: ...but uids never come back meaning another place")
    local stR = S.New(clock, epoch)
    stR:AddRoute({ title = "x", persistent = false, stops = { { map = 10, x = 0.1, y = 0.1 } } })
    local lR = S.Load(RoundTrip(stR:Serialize()), clock, epoch)
    EQ(lR:AddRoute({ title = "y", stops = { { map = 10, x = 0.2, y = 0.2 } } }).id, "r2", "J: route ids continue too")

    -- garbage in
    local okG = true
    for _, junk in ipairs({ nil, "x", 42, {}, { Waypoints = "no" }, { Waypoints = { "x", 5, {} }, Routes = 7 } }) do
        local okJ, ld = pcall(S.Load, junk, clock, epoch)
        okG = okG and okJ and ld and #ld:List() == 0
    end
    CHECK(okG, "J: Load of junk is an empty store, never an error")
    local messy = {
        Schema = 99, NextUid = 3, NextRoute = "x", Pinned = "w8", ActiveRoute = "r5", Suppressed = true,
        Waypoints = {
            { uid = "w1", map = 10, x = 0.1, y = 0.1, title = "ok" },
            { uid = "w1", map = 10, x = 0.2, y = 0.2, title = "duplicate uid" },
            { uid = "x9", map = 10, x = 0.3, y = 0.3, title = "bad uid" },
            { uid = "w4", map = 10, x = 0 / 0, y = 0.3, title = "NaN" },
            { uid = "w5", map = 10, x = 0.5, y = 0.5, kind = "stop", routeId = "r5", title = "stop of a dead route" },
            { uid = "w6", kind = "corpse", map = 10, x = 0.6, y = 0.6 },
            { uid = "w7", kind = "corpse", map = 10, x = 0.7, y = 0.7 },
            { uid = "w8", map = 10, x = 0.8, y = 0.8, source = "QL", key = "k", title = "first key" },
            { uid = "w9", map = 10, x = 0.9, y = 0.9, source = "QL", key = "k", title = "second key" },
            { uid = "w12", map = 11, x = 0.1, y = 0.1, kind = "stop", routeId = "r2", title = "R2a" },
            { uid = "w13", map = 11, x = 0.2, y = 0.2, kind = "stop", routeId = "r2", title = "R2b", callbacks = {} },
        },
        Routes = {
            { id = "r2", title = "Two", stops = { "w12", "w404", "w13", "w12" }, index = 3, mode = "BOGUS" },
            { id = "r3", title = "Empty", stops = { "w404" } },
            { id = "r5", title = "Dead" },
            { id = "bad", stops = { "w1" } },
        },
    }
    local okM, lm = pcall(S.Load, messy, clock, epoch)
    CHECK(okM, "J: a messy save loads", lm)
    if okM then
        EQ(lm:Get("w1").title, "ok", "J: the first of two equal uids wins")
        EQ(lm:Get("x9"), nil, "J: a malformed uid is dropped")
        EQ(lm:Get("w4"), nil, "J: a NaN coordinate is dropped")
        CHECK(lm:Get("w5") and lm:Get("w5").routeId == nil and lm:Get("w5").kind == "point",
            "J: a stop whose route is gone becomes a plain waypoint")
        EQ(lm:Count({ kind = "corpse" }), 1, "J: one corpse at most")
        EQ(lm:ByKey("QL", "k").uid, "w8", "J: a duplicated (source, key) keeps the first")
        EQ(lm:Get("w9"), nil, "J: ...and drops the twin")
        local r2 = lm:GetRoute("r2")
        CHECK(r2 and #r2.stops == 2 and r2.stops[1] == "w12" and r2.stops[2] == "w13", "J: a route keeps its real stops once")
        EQ(r2 and r2.index, 2, "J: ...its place maps onto what is left")
        EQ(r2 and r2.mode, "ORDERED", "J: ...an unknown mode reads as ORDERED")
        EQ(lm:GetRoute("r3"), nil, "J: a route with no real stops is dropped")
        EQ(lm:GetRoute("r5"), nil, "J: a route with no stops list is dropped")
        EQ(lm:ActiveRoute(), nil, "J: an active route that did not survive is not active")
        EQ(lm:Pinned() and lm:Pinned().uid, "w8", "J: the pin survives when its record does")
        EQ(lm:Suppressed(), true, "J: the dismissed arrow survives")
        EQ(lm:Get("w13").callbacks, nil, "J: a saved callbacks field is never restored")
        EQ(lm:Add({ map = 12, x = 0.5, y = 0.5 }).uid, "w14", "J: the counter is past the highest uid seen")
        EQ(lm:AddRoute({ title = "n", stops = { { map = 12, x = 0.6, y = 0.6 } } }).id, "r6",
            "J: the route counter is past the highest route id seen")
    end

    -- Copy: a detached plain copy for the public API
    local cp = S.Copy(a)
    CHECK(cp ~= a and cp.uid == a.uid and cp.callbacks == nil and cp.alternatives[2].map == 1944,
        "J: S.Copy is detached, plain, alternatives keyed")
    cp.title = "changed"
    EQ(a.title, "Nazgrel", "J: ...changing the copy changes nothing")
    EQ(S.Copy(nil), nil, "J: S.Copy(nil) is nil")
end)

-- ===========================================================================
-- L: 3.1 (SPEC 2): the pinned consumer record and the active route are
-- saved (D5); Follow the Closest's zone scope and ownership (S3); Retarget
-- ===========================================================================
Section(function()
    -- D5: what Serialize keeps
    local st = S.New(clock, epoch)
    local go = st:Add({ map = 10, x = 0.5, y = 0.5, title = "Go", source = "QuestLog", key = "quest:1",
        persistent = false, setArrow = true })
    local other = st:Add({ map = 10, x = 0.6, y = 0.5, title = "Other", source = "QuestLog", key = "quest:2",
        persistent = false })
    local plain = RoundTrip(st:Serialize())
    EQ(#plain.Waypoints, 1, "L: the pinned session-only record is saved, the other is not (D5)")
    EQ(plain.Waypoints[1] and plain.Waypoints[1].uid, go.uid, "L: ...the pinned one")
    EQ(plain.Pinned, go.uid, "L: ...and the pin with it")
    local ld = S.Load(plain, clock, epoch)
    EQ(ld:Pinned() and ld:Pinned().uid, go.uid, "L: after a load the arrow is on it again")
    EQ(ld:Get(go.uid).persistent, false, "L: ...still session-only")
    ld:ClearPinned(true)
    EQ(#RoundTrip(ld:Serialize()).Waypoints, 0, "L: let go of, it is no longer saved")
    -- a pinned temporary offer or unit follow is not
    local st2 = S.New(clock, epoch)
    st2:Add({ map = 10, x = 0.5, y = 0.5, title = "Ping", source = "Ping", key = "ping", persistent = false,
        temporary = true, setArrow = true })
    EQ(#RoundTrip(st2:Serialize()).Waypoints, 0, "L: a pinned temporary offer is not saved")
    local st3 = S.New(clock, epoch)
    local u = st3:Add({ kind = "unit", unit = "party1", title = "Bob", persistent = false, setArrow = true })
    EQ(st3:Pinned(), u, "L: (a unit follow pinned)")
    EQ(#RoundTrip(st3:Serialize()).Waypoints, 0, "L: ...is not saved")
    -- the active route, session-only, with its stops
    local st4 = S.New(clock, epoch)
    local r = st4:AddRoute({ title = "Trip", source = "Tradecraft", key = "trip", persistent = false,
        stops = { { map = 10, x = 0.1, y = 0.1 }, { map = 10, x = 0.2, y = 0.1 } } })
    st4:AddRoute({ title = "Idle", source = "Tradecraft", key = "idle", persistent = false, start = false,
        stops = { { map = 10, x = 0.3, y = 0.1 } } })
    local p4 = RoundTrip(st4:Serialize())
    EQ(#p4.Routes, 1, "L: the active route is saved, the idle one is not")
    EQ(#p4.Waypoints, 2, "L: ...with its stops")
    EQ(p4.Routes[1].persistent, false, "L: ...marked session-only")
    EQ(p4.ActiveRoute, r.id, "L: ...and still the active one")
    local l4 = S.Load(p4, clock, epoch)
    EQ(l4:GetRoute(r.id) and l4:GetRoute(r.id).persistent, false, "L: loaded, it stays session-only")
    EQ(l4:ActiveRoute() and l4:ActiveRoute().id, r.id, "L: ...and running")
    l4:RemoveRoute(r.id)
    -- review (core): a pinned "Guide me" hop keeps the record it names in
    -- guideFor, session-only or not, and the link itself
    local sg = S.New(clock, epoch)
    local tgt = sg:Add({ map = 11, x = 0.5, y = 0.5, title = "Bank", source = "Armory", key = "bank",
        persistent = false, setArrow = true })
    local hop = sg:Add({ map = 10, x = 0.2, y = 0.2, title = "To Outland", source = "guide", key = "hop",
        persistent = false, setArrow = true, guideFor = tgt.uid })
    EQ(hop.guideFor, tgt.uid, "L: a hop records guideFor")
    EQ(sg:Pinned(), hop, "L: (the hop holds the arrow)")
    local pg = RoundTrip(sg:Serialize())
    EQ(#pg.Waypoints, 2, "L: the pinned hop AND the session-only record it leads to are saved")
    local lg = S.Load(pg, clock, epoch)
    EQ(lg:Pinned() and lg:Pinned().guideFor, tgt.uid, "L: ...the link loads with the hop")
    CHECK(lg:Get(tgt.uid) ~= nil and lg:Get(tgt.uid).persistent == false, "L: ...the target loads, still session-only")
    lg:Remove(hop.uid)
    EQ(#RoundTrip(lg:Serialize()).Waypoints, 0, "L: with the hop gone, neither is kept")
    local sg2 = S.New(clock, epoch)
    local ut = sg2:Add({ kind = "unit", unit = "party1", title = "Bob", persistent = false })
    sg2:Add({ map = 10, x = 0.2, y = 0.2, title = "To Bob", source = "guide", key = "hop", persistent = false,
        setArrow = true, guideFor = ut.uid })
    EQ(#RoundTrip(sg2:Serialize()).Waypoints, 1, "L: ...but never a unit follow (D33's exclusion)")
    EQ(sg2:Add({ map = 10, x = 0.3, y = 0.3, guideFor = "nonsense" }).guideFor, nil, "L: guideFor must be a uid")
    -- a 3.0 save (persistent = true on every route) still loads persistent
    local old = { Schema = 1, NextUid = 3, NextRoute = 2, Waypoints = { { uid = "w1", map = 10, x = 0.1, y = 0.1,
        kind = "stop", routeId = "r1", routeIndex = 1, source = "user" } },
        Routes = { { id = "r1", title = "Old", source = "user", stops = { "w1" }, index = 1, persistent = true } } }
    EQ(S.Load(old, clock, epoch):GetRoute("r1").persistent, true, "L: a 3.0 route loads persistent")

    -- S3: the zone scope through ctx.sameZone, and ownership
    local zone = { [10] = "A", [11] = "B", [12] = "A" }
    local function SameZone(a, b) return zone[a] ~= nil and zone[a] == zone[b] end
    local sc = S.New(clock, epoch)
    sc.rescanInterval = 0
    local far = sc:Add({ map = 11, x = 0.05, y = 0.05, title = "Next zone" })
    local mine = sc:Add({ map = 12, x = 0.9, y = 0.9, title = "My zone, farther" })
    local ctxL = Ctx(10, 0.95, 0.05)
    EQ(sc:ActiveTarget(ctxL), far, "L: landmass-wide: the nearest anywhere")
    local ctxZ = Ctx(10, 0.95, 0.05, { closestScope = "ZONE", sameZone = SameZone })
    EQ(sc:ActiveTarget(ctxZ), mine, "L: ZONE: the nearest in my zone")
    EQ(sc:Closest(ctxZ), mine, "L: Closest keeps the scope too")
    sc:Remove(mine.uid)
    EQ(sc:ActiveTarget(ctxZ), nil, "L: ZONE with nothing in my zone: nothing")
    EQ(sc:ActiveTarget(Ctx(10, 0.95, 0.05, { closestScope = "ZONE" })), far, "L: no sameZone given: landmass-wide")
    local sk = S.New(clock, epoch)
    local kfar = sk:Add({ map = 11, x = 0.05, y = 0.05, title = "Next zone" })
    local kmine = sk:Add({ map = 12, x = 0.9, y = 0.9, title = "Mine" })
    EQ(sk:ActiveTarget(Ctx(10, 0.95, 0.05)), kfar, "L: (landmass-wide, remembered: the next zone's)")
    EQ(sk:ActiveTarget(Ctx(10, 0.95, 0.05, { closestScope = "ZONE", sameZone = SameZone })), kmine,
        "L: switched to ZONE, a remembered pick out of scope is dropped at once")
    local tt = sc:Add({ map = 10, x = 0.9, y = 0.05, title = "Questie's", source = "TomTom:Questie" })
    local ctxM = Ctx(10, 0.95, 0.05, { closestMine = true })
    EQ(sc:ActiveTarget(ctxM), far, "L: ClosestMineOnly leaves the TomTom bridge's out")
    EQ(sc:Closest(ctxM), far, "L: ...in Closest too")
    EQ(sc:Closest(ctxM, true), tt, "L: ...unless the bridge asks for its callers (anyOwner)")
    EQ(sc:ActiveTarget(Ctx(10, 0.95, 0.05)), tt, "L: ownership off: it is the nearest")
    sc:SetPinned(tt.uid)
    EQ(sc:ActiveTarget(ctxM), tt, "L: a pin is never filtered")

    -- Retarget: a follow moves to the member's new token
    local rt = S.New(clock, epoch)
    local f = rt:Add({ kind = "unit", unit = "party2", title = "Bob", source = "PartyFrames", key = "follow" })
    local v = rt.version
    EQ(rt:Retarget(f.uid, "party1"), true, "L: Retarget")
    EQ(f.unit, "party1", "L: ...the token moved")
    CHECK(rt.version > v, "L: ...a change")
    EQ(rt:ByKey("PartyFrames", "follow"), f, "L: ...the same record by its key")
    EQ(rt:Retarget(f.uid, "party1"), true, "L: the same token again is no change")
    local p = rt:Add({ map = 10, x = 0.5, y = 0.5 })
    EQ(rt:Retarget(p.uid, "party1"), false, "L: a place is not a follow")
    EQ(rt:Retarget("w999", "party1"), false, "L: nor an unknown uid")
    EQ(rt:Retarget(f.uid, ""), false, "L: nor an empty token")
end)

-- ===========================================================================
-- K: the sealed environment
-- ===========================================================================
EQ(#strayReads, 0, "K: the store read no global outside the standard set" ..
    (strayReads[1] and (" (" .. strayReads[1] .. ")") or ""))
EQ(#strayWrites, 0, "K: the store wrote no global but CommanderOrders" ..
    (strayWrites[1] and (" (" .. strayWrites[1] .. ")") or ""))
local globals = {}
for k in pairs(SEALED) do globals[#globals + 1] = tostring(k) end
EQ(table.concat(globals, ","), "CommanderOrders", "K: CommanderOrders is the only global it left behind")
local O = rawget(SEALED, "CommanderOrders")
local keys = {}
for k in pairs(O) do keys[#keys + 1] = tostring(k) end
EQ(table.concat(keys, ","), "Store", "K: it added only O.Store to the shared table")

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
