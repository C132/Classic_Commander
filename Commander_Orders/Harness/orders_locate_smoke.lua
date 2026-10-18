-- Commander Orders: the locator's harness (luajit).
--
--     luajit Commander_Orders/Harness/orders_locate_smoke.lua
--     COMMANDER_DB2=<dir> luajit ...        (also re-runs make_entrances.py --check)
--     ORDERS_REALDATA_BOOT=<boot.lua> luajit ...   (the real-Questie section's boot)
--     ORDERS_LOCATE=/tmp/mutant.lua luajit ...      (a locator mutant in its place)
--
-- CommanderOrdersLocate.lua and the generated door table
-- (CommanderOrdersEntrances.lua) over orders_mock.lua's client, with the
-- committed QuestieDB / Questie fixture (fake_questiedb.lua: real rows, the
-- real surface) installed before the files load. Every section boots a fresh
-- client.
--
--   A  boot: the real Locate replaces the stand-in, the hooks, no globals,
--      the full TOC beside it, and a client with no Questie at all
--   B  the door table: shape, every spot valid and on a zone, the keys,
--      spot checks against the generator's sources, the generator's --check
--   C  doors: R.DoorLookup by uiMap / instance / areaId, approaches,
--      several doors, the world-position fallback, Entrance()'s order, the
--      arrow's dungeon hint now answered offline
--   D  npc and object queries: id, numeric string, exact name (one index
--      build), id lists, instance-only NPCs -> doors, bad rows, copies
--   E  townsfolk: every kind, aliases, faction filter, blacklist, otherside,
--      class and profession trainers, the vendor lists and the vendor union,
--      caching, a new list from Questie rebuilds
--   F  states: Stage 0 / 1 / 3, QuestieDB alone, nothing installed, a
--      contract mismatch, a broken Townsfolk, the ready hook and the
--      pre-warm (never in combat)
--   G  items: itemVendor, itemSource (vendors, drops, containers, doors)
--   H  registered resolvers: townsfolk merge and dedupe, npc first answer,
--      a raising resolver, the runtime's kinds untouched
--   I  GoTo / PlaceFor / IsGoing / GoButton with a query, refusal lines
--   J  robustness: bad queries, raising reads, the pcall boundary, hover cost
--   K  the 3.1 review's fixes: "nearest" from inside an instance (its door
--      stands in for you, sorted before the 256 cap), the island beside your
--      landmass (Darnassus from Auberdine), PlaceFor's "elsewhere", the
--      corpse's every door, what a nearest-of-300 hover costs; review-r2:
--      Magisters' Terrace, with no uiMap, found by its instance id (a Go
--      from inside, and the corpse run)
--   R  the REAL Questie 12.0.3 / QuestieDB 1.0.4, booted inside the mock in
--      a child process (Horde and Alliance): counts for every kind, and the
--      Isle's smith and vendor kept from inside Magisters' Terrace; SKIPS
--      cleanly when the session's boot tooling is absent

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local SELF = HERE .. "/orders_locate_smoke.lua"
local REAL_BOOT = os.getenv("ORDERS_REALDATA_BOOT") or
    "/private/tmp/claude-501/-Applications-World-of-Warcraft--anniversary--Interface-AddOns/55a8f750-a6ec-4038-8f0a-3ed7c436fd1f/scratchpad/wp/review/tomtomshim/boot.lua"

local function Exists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail ~= nil and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end
local function EQ(got, want, label)
    CHECK(got == want, label, "got " .. tostring(got) .. ", want " .. tostring(want))
end
local function NEAR(got, want, eps, label)
    CHECK(type(got) == "number" and math.abs(got - want) <= eps, label,
        "got " .. tostring(got) .. ", want " .. tostring(want) .. " +- " .. tostring(eps))
end
local function HAS(s, needle, label)
    CHECK(type(s) == "string" and s:find(needle, 1, true) ~= nil, label, "got " .. tostring(s))
end

-- ===========================================================================
-- R (child process): the real Questie, booted inside the Orders mock
-- ===========================================================================
if arg and arg[1] == "--real" then
    local B = dofile(REAL_BOOT)
    local M = B.M
    local P = function(...) io.write(table.concat({ ... }, "\t"), "\n") end
    local faction = arg[2] or "Horde"
    local start = faction == "Alliance" and { 1944, 0.54, 0.636 } or { 1944, 0.5629, 0.3624 }
    -- the cold build of each kind, before the ready pre-warm
    B.Boot({ player = start, faction = faction })
    for _, e in ipairs(M.loadErrors) do CHECK(false, "R " .. faction .. ": no load errors", e) end
    local O = CommanderOrders
    local st = O.R.LocateState()
    EQ(st.questieDB, "OK", "R " .. faction .. ": LibQuestieDB contract 2 accepted")
    EQ(st.townsfolk, "READY", "R " .. faction .. ": Questie's Townsfolk lists found (REQUIRED probe)")
    local cold = {}
    for _, k in ipairs({ "Repair", "Innkeeper", "Flight Master", "Banker", "Spirit Healer", "Mailbox" }) do
        local t0 = os.clock()
        O.Locate({ townsfolk = k })
        cold[#cold + 1] = string.format("%s %.1f ms", k, (os.clock() - t0) * 1000)
    end
    P("REALINFO", faction, "cold builds (luajit): " .. table.concat(cold, ", "))
    -- Stage 3: the vendor lists, then Questie's ready signal
    local T = QuestieLoader._modules.Townsfolk
    local okPB = pcall(T.PostBoot)
    CHECK(okPB, "R " .. faction .. ": Townsfolk.PostBoot ran (vendor lists)")
    Questie.API.isReady = true
    QuestieLoader._modules.QuestieAPI.PropagateOnReady()
    M.Advance(3)
    st = O.R.LocateState()
    CHECK(st.ready and st.vendorLists and not st.warming, "R " .. faction .. ": ready, vendor lists read, pre-warm done")
    local MIN = {
        Repair = 200, Vendor = 400, Innkeeper = 40, Banker = 20, Auctioneer = 15, ["Flight Master"] = 50,
        Battlemaster = 30, ["Weapon Master"] = 4, ["Stable Master"] = 35, ["Spirit Healer"] = 150, Mailbox = 60,
        ["Meeting Stone"] = 30, ["Class Trainer"] = 5, ["Portal Trainer"] = 5, Reagents = 30, Poisons = 50,
        ["Trade Goods"] = 200, Bags = 40, Potions = 20, Food = 40, Drink = 35, Ammo = 60,
    }
    local order = { "Repair", "Vendor", "Innkeeper", "Banker", "Auctioneer", "Flight Master", "Battlemaster",
        "Weapon Master", "Stable Master", "Spirit Healer", "Mailbox", "Meeting Stone", "Class Trainer",
        "Portal Trainer", "Reagents", "Poisons", "Trade Goods", "Bags", "Potions", "Food", "Drink", "Ammo" }
    local mine = faction == "Alliance" and "A" or "H"
    for _, k in ipairs(order) do
        local places, why = O.Locate({ townsfolk = k })
        local n = places and #places or 0
        CHECK(n >= MIN[k], "R " .. faction .. ": " .. k .. " has its places", tostring(n) .. " " .. tostring(why))
        local ids, maps, bad = {}, {}, 0
        for _, p in ipairs(places or {}) do
            ids[p.npc or p.object or 0] = true
            maps[p.map] = true
            local f = p.npc and LibQuestieDB.Npc.Get(p.npc, "friendlyToFaction")
            if f and f ~= "AH" and f ~= mine and k ~= "Spirit Healer" then bad = bad + 1 end
        end
        EQ(bad, 0, "R " .. faction .. ": " .. k .. " only this faction's and everyone's")
        local ni, nm = 0, 0
        for _ in pairs(ids) do ni = ni + 1 end
        for _ in pairs(maps) do nm = nm + 1 end
        P("REALCOUNT", faction, k, n, ni, nm)
    end
    for _, prof in ipairs({ "First Aid", "Blacksmithing", "Leatherworking", "Alchemy", "Herbalism", "Cooking", "Mining",
            "Tailoring", "Engineering", "Enchanting", "Fishing", "Skinning", "Jewelcrafting" }) do
        local places = O.Locate({ townsfolk = prof .. " Trainer" })
        CHECK(places and #places >= 3, "R " .. faction .. ": " .. prof .. " trainers", places and #places)
        P("REALCOUNT", faction, prof .. " Trainer", places and #places or 0)
    end
    for _, cls in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
        local places = O.Locate({ townsfolk = "Class Trainer", class = cls })
        P("REALCOUNT", faction, cls .. " trainer", places and #places or 0)
    end
    -- the specific lookups
    local function One(label, q, want)
        local places, why = O.Locate(q)
        CHECK(places ~= nil and want(places), "R " .. faction .. ": " .. label, why)
        P("REALQUERY", faction, label, places and #places or ("nil " .. tostring(why)),
            places and places[1] and string.format("%s %d %.4f,%.4f %s", tostring(places[1].title), places[1].map,
                places[1].x, places[1].y, tostring(places[1].kind)) or "")
    end
    One("npc 16602 Floyd Pinkus (Thrallmar)", { npc = 16602 }, function(p) return p[1].map == 1944 end)
    One("npc 'Fedryen Swiftspear' by name", { npc = "Fedryen Swiftspear" }, function(p) return p[1].npc == 17904 end)
    One("npc 17257 Magtheridon -> door", { npc = 17257 }, function(p) return p[1].kind == "entrance" and p[1].map == 1944 end)
    One("npc 15687 Moroes -> Karazhan doors", { npc = 15687 }, function(p) return #p == 2 and p[1].map == 1430 end)
    One("object 'Anvil' by name", { object = "Anvil" }, function(p) return #p > 100 end)
    One("itemVendor 6217 Copper Rod", { itemVendor = 6217 }, function(p) return #p >= 20 end)
    One("itemVendor 27860 Purified Draenic Water", { itemVendor = 27860 }, function(p) return #p >= 10 end)
    One("itemSource 32898 Shattrath Flask", { itemSource = 32898 }, function(p) return #p >= 1 end)
    One("entrance areaId 3457 (Karazhan)", { entrance = { area = 3457 } }, function(p) return #p == 2 end)
    -- every Questie instance areaId the door table keys answers a door
    local missing = {}
    for area in pairs(CommanderOrders.Entrances.AREAS) do
        if not O.Locate({ entrance = { area = area } }) then missing[#missing + 1] = area end
    end
    EQ(#missing, 0, "R " .. faction .. ": every keyed areaId answers a door", table.concat(missing, ","))
    -- GoTo: one waypoint, the nearest friendly innkeeper first
    local uid = O.GoTo({ townsfolk = "Innkeeper" }, { source = "Test", key = "inn", silent = true })
    local wp = uid and O.Get(uid)
    local want = faction == "Alliance" and "Sid Limbardi" or "Floyd Pinkus"
    local near = O.Locate({ npc = want })
    CHECK(wp and near and math.abs(wp.x - near[1].x) < 1e-6, "R " .. faction .. ": GoTo innkeeper -> " .. want,
        wp and (wp.x .. "," .. wp.y))
    -- inside Magisters' Terrace (no uiMap on 2.5.6, so GetBestMapForUnit
    -- answers nil): measured from its door by the instance id, the Isle's
    -- smith and vendor stay among the places (review-r2: both were past the
    -- 256 cap in Questie's order and the arrow went to Elwynn)
    M.SetPlayer(1957, 0.6152, 0.3110)
    M.SetNoMap(true)
    M.SetNoPosition(true)
    M.SetInstance("party", 585)
    M.Advance(0.3)
    for _, row in ipairs({ { "Repair", "Smith Hauthaa" }, { "Vendor", "Sereth Duskbringer" } }) do
        local u = O.GoTo({ townsfolk = row[1] }, { source = "Test", key = "mgt:" .. row[1], silent = true })
        local w = u and O.Get(u)
        local who = O.Locate({ npc = row[2] })
        local spot = who and who[1]
        local kept = false
        local function Same(m, x, y)
            return spot and m == spot.map and math.abs(x - spot.x) < 1e-6 and math.abs(y - spot.y) < 1e-6
        end
        if w and spot then
            kept = Same(w.map, w.x, w.y) and true or false
            for _, a in ipairs(w.alternatives or {}) do
                if Same(a.map or a[1], a.x or a[2], a.y or a[3]) then kept = true end
            end
        end
        CHECK(kept, "R " .. faction .. ": inside Magisters' Terrace a " .. row[1] .. " Go keeps " .. row[2],
            w and string.format("%d %.4f,%.4f", w.map, w.x, w.y))
    end
    M.SetNoMap(false)
    M.SetNoPosition(false)
    M.SetInstance(nil)
    P("REALSUMMARY", checks, fails)
    os.exit(0)
end

-- ===========================================================================
-- The offline sections (the fixture)
-- ===========================================================================
local M = dofile(HERE .. "/orders_mock.lua")
local F = dofile(HERE .. "/fake_questiedb.lua")

local function NOERR(label)
    CHECK(#M.errors == 0, label .. ": no errors", M.errors[1])
    CHECK(#M.loadErrors == 0, label .. ": no load errors", M.loadErrors[1])
end

local function Section(name, fn)
    local ok, err = pcall(fn)
    CHECK(ok, name .. ": ran to the end", err)
end

local THRALLMAR = { 1944, 0.5629, 0.3624 }
local HONOR_HOLD = { 1944, 0.54, 0.636 }

-- fake: F.Install options (false: install nothing)
local function Boot(opts, fake)
    opts = opts or {}
    local user = opts.before
    opts.loaded = opts.loaded or { Questie = true, QuestieDB = true }
    opts.before = function(m, w)
        if fake ~= false then F.Install(fake or { stage = 3 }) end
        if user then user(m, w) end
    end
    if opts.skipFiles == nil then opts.skipFiles = { CommanderOrdersPins = true, CommanderOrdersUI = true } end
    -- ORDERS_LOCATE=<copy>: a mutant of the locator in its place (mutation runs)
    local mutant = os.getenv("ORDERS_LOCATE")
    if mutant then
        opts.skipFiles.CommanderOrdersLocate = true
        local userAfter = opts.afterFiles
        opts.afterFiles = function(m, w)
            local chunk, err = loadfile(mutant)
            if chunk then chunk() else error(err) end
            if userAfter then userAfter(m, w) end
        end
    end
    local W = M.Boot(opts)
    M.Advance(0.5)
    return W
end

local function O() return CommanderOrders end
local function R() return CommanderOrders.R end
local function E() return CommanderOrders.Entrances end
local function L(q) return CommanderOrders.Locate(q) end
local function Pass(n) M.Advance((n or 1) * 0.1 + 0.02) end
local function Text(key) return CommanderOrders.R.ArrowState().text[key] end

local function Count(places) return type(places) == "table" and #places or 0 end
local function Ids(places, key)
    local out = {}
    for _, p in ipairs(places or {}) do out[#out + 1] = p[key or "npc"] or p.object end
    table.sort(out)
    return table.concat(out, ",")
end

-- ===========================================================================
-- A: boot
-- ===========================================================================
Section("A", function()
    Boot({ player = THRALLMAR })
    NOERR("A boot")
    EQ(#M.prints, 0, "A: a quiet login")
    local places, why = L({ npc = 16602 })
    CHECK(places ~= nil, "A: the real Locate replaced the stand-in (no more \"loading\")", why)
    EQ(type(R().DoorLookup), "function", "A: R.DoorLookup is set (Orders' Entrance asks it)")
    EQ(type(R().LocateState), "function", "A: R.LocateState for diagnostics")
    EQ(type(O().RegisterResolver), "function", "A: RegisterResolver is still a function")
    local st = R().LocateState()
    EQ(st.questieDB, "OK", "A: QuestieDB contract 2 accepted")
    EQ(st.townsfolk, "READY", "A: Questie's Townsfolk lists found")
    EQ(st.vendorLists, true, "A: the vendor lists (Stage 3) read")
    EQ(st.hooked, true, "A: the ready hook registered at PLAYER_LOGIN")
    EQ(st.ready, true, "A: Questie was ready already: the callback ran at once")
    EQ(st.doors, 51, "A: 51 instances in the door table")
    EQ(st.doorBuild, "2.5.6.69795", "A: generated from this build's DB2")
    -- globals: only the runtime's documented ones (orders_harness A's list)
    local allowed = {
        CommanderOrders = true, CommanderOrdersDB = true, CommanderOrdersChar = true, COMMANDER_ORDERS_EVENTS = true,
        CommanderOrders_IssueOrder = true, CommanderOrders_ClearOrder = true, CommanderOrders_RallySet = true,
        CommanderOrders_RallyGo = true, CommanderOrders_RallyList = true, CommanderOrdersArrow = true,
        CommanderOrdersMenu = true, TomTom = true, BINDING_HEADER_COMMANDERORDERS = true,
        SLASH_COMMANDERUI_ORDERS1 = true, CommanderUIScrollOrders = true,
    }
    local bad = {}
    for _, name in ipairs(M.OrdersWrites()) do
        local ok = allowed[name] or name:match("^BINDING_NAME_COMMANDERORDERS_%u+$")
            or name:match("^SLASH_COMMANDERORDERS_%u+%d$") or name:match("^CommanderUIDropDown%d+$")
        if not ok then bad[#bad + 1] = name end
    end
    EQ(#bad, 0, "A: no undocumented global written", table.concat(bad, " "))
    -- every TOC file that exists (pins, coordinates, chat, manager) beside it
    Boot({ player = THRALLMAR, skipFiles = {} })
    NOERR("A full TOC")
    CHECK(L({ townsfolk = "Innkeeper" }) ~= nil, "A: the full TOC: the locator answers")
    -- the locator alone (no Questie at all) still loads and answers doors
    Boot({ player = THRALLMAR, loaded = {} }, false)
    NOERR("A bare")
    local p2, why2 = L({ npc = 16602 })
    CHECK(p2 == nil and why2 == "noquestie", "A: no Questie: an npc query says noquestie", why2)
    CHECK(L({ entrance = { instance = 543 } }) ~= nil, "A: ...and the door table still answers")
    EQ(R().LocateState().hooked, false, "A: ...with nothing to hook")
end)

-- ===========================================================================
-- B: the door table
-- ===========================================================================
Section("B", function()
    Boot({ player = THRALLMAR })
    local T = E()
    EQ(type(T), "table", "B: CommanderOrders.Entrances")
    EQ(type(T.DOORS), "table", "B: DOORS")
    local n, spots, badSpot, badZone, bareRow = 0, 0, {}, {}, {}
    for id, row in pairs(T.DOORS) do
        n = n + 1
        if type(row.name) ~= "string" or type(row.doors) ~= "table" or type(row.raid) ~= "boolean" then
            bareRow[#bareRow + 1] = id
        end
        if #row.doors == 0 and not (type(row.approach) == "table" and #row.approach > 0) then bareRow[#bareRow + 1] = id end
        for _, list in ipairs({ row.doors, row.approach or {} }) do
            for _, s in ipairs(list) do
                spots = spots + 1
                if not O().Store.ValidPosition(s[1], s[2], s[3]) then badSpot[#badSpot + 1] = id end
                local info = M.MAPS[s[1]]
                if not (info and info[2] == 3) then badZone[#badZone + 1] = id .. ":" .. tostring(s[1]) end
            end
        end
    end
    EQ(n, 51, "B: 51 instances")
    EQ(spots, 93, "B: 93 spots (65 doors, 28 approach points)")
    EQ(#bareRow, 0, "B: every row named, typed and with somewhere to go", table.concat(bareRow, ","))
    EQ(#badSpot, 0, "B: every spot is 0..1 on its map", table.concat(badSpot, ","))
    EQ(#badZone, 0, "B: every spot is on a ZONE map (never a dungeon or continent map)", table.concat(badZone, ","))
    local orphan = {}
    for ui, id in pairs(T.MAPS) do if not T.DOORS[id] then orphan[#orphan + 1] = ui end end
    for area, id in pairs(T.AREAS) do if not T.DOORS[id] then orphan[#orphan + 1] = "a" .. area end end
    EQ(#orphan, 0, "B: every uiMap and areaId key names a row", table.concat(orphan, ","))
    -- spot checks against the sources (AreaTrigger DB2 + areatrigger_teleport)
    local ramp = T.DOORS[543]
    CHECK(ramp and ramp.name == "Hellfire Ramparts" and ramp.raid == false, "B: 543 Hellfire Ramparts, a dungeon")
    CHECK(ramp and ramp.doors[1][1] == 1944 and math.abs(ramp.doors[1][2] - 0.4748) < 1e-9
        and math.abs(ramp.doors[1][3] - 0.5363) < 1e-9 and ramp.doors[1][4] == 4150,
        "B: ...trigger 4150 at Hellfire 47.48, 53.63 (sources 3.3: 47.5, 53.6)")
    EQ(ramp and ramp.approach, nil, "B: ...walked straight to, no approach")
    local kara = T.DOORS[532]
    CHECK(kara and #kara.doors == 2 and kara.doors[1][4] == 4131 and kara.doors[2][4] == 4135 and kara.raid,
        "B: Karazhan: the main and the servants' doors (4131, 4135), a raid")
    local bm = T.DOORS[269]
    CHECK(bm and bm.approach and bm.approach[1][1] == 1446 and math.abs(bm.approach[1][2] - 0.657) < 1e-9,
        "B: the Black Morass: the Caverns of Time mouth, Tanaris 65.7, 49.8")
    local brd = T.DOORS[230]
    CHECK(brd and brd.approach and #brd.approach == 2 and brd.approach[1][1] == 1427 and brd.approach[2][1] == 1428,
        "B: Blackrock Depths: the mountain's two gates (Searing Gorge, Burning Steppes)")
    local aq20 = T.DOORS[509]
    CHECK(aq20 and #aq20.doors == 0 and aq20.approach and aq20.approach[1][1] == 1451,
        "B: Ruins of Ahn'Qiraj: no door on any zone map, the Scarab Wall's gate")
    local bwl, brs = T.DOORS[469], T.DOORS[229]
    CHECK(bwl and brs and bwl.doors[1][4] == brs.doors[1][4], "B: Blackwing Lair takes Blackrock Spire's door")
    local coil = T.DOORS[547]
    CHECK(coil and coil.approach and math.abs(coil.approach[1][2] - 0.5036) < 1e-9,
        "B: the Slave Pens: AreaPOI 2021 Coilfang Reservoir (50.4, 40.8; Questie 50.4, 40.9)")
    EQ(T.DOORS[585] and T.DOORS[585].name, "Magisters' Terrace", "B: 585 named as the player knows it")
    EQ(T.MAPS[347], 543, "B: uiMap 347 -> 543")
    EQ(T.MAPS[274], 560, "B: the Orphan Old Hillsbrad map 274 -> 560")
    EQ(T.MAPS[337], 309, "B: unassigned Zul'Gurub 337 -> 309 (as 233)")
    EQ(T.MAPS[1554], 548, "B: unassigned Serpentshrine 1554 -> 548")
    EQ(T.AREAS[3836], 544, "B: areaId 3836 -> Magtheridon's Lair")
    EQ(T.AREAS[3457], 532, "B: areaId 3457 -> Karazhan")
    EQ(T.AREAS[10103], 532, "B: a Karazhan sub-area (Questie's alternatives) -> Karazhan")
    EQ(T.AREAS[209], 33, "B: AREA 209 is Shadowfang Keep (the instance 209 is Zul'Farrak)")
    -- the generator reproduces the file (when its inputs are on this machine)
    local db2 = os.getenv("COMMANDER_DB2")
    local cmd = "python3 '" .. HERE .. "/make_entrances.py' --check" .. (db2 and (" --db2 '" .. db2 .. "'") or "") .. " 2>&1"
    local pipe = io.popen(cmd .. "; echo EXIT=$?")
    local out = pipe and pipe:read("*a") or ""
    if pipe then pipe:close() end
    local code = tonumber(out:match("EXIT=(%d+)"))
    if code == 0 then
        HAS(out, "CHECK OK", "B: make_entrances.py --check: the shipped file is what the generator writes")
    elseif code == 1 then
        CHECK(false, "B: make_entrances.py --check: the shipped file is what the generator writes", out:sub(-300))
    else
        io.write("SKIP  B: make_entrances.py --check (inputs not on this machine; set COMMANDER_DB2)\n")
    end
end)

-- ===========================================================================
-- C: doors
-- ===========================================================================
Section("C", function()
    Boot({ player = THRALLMAR })
    local d = R().DoorLookup(347)
    CHECK(d and d.map == 1944 and math.abs(d.x - 0.4748) < 1e-9 and d.title == "Hellfire Ramparts entrance"
        and d.alternatives == nil, "C: uiMap 347 -> the Ramparts door")
    local d2 = R().DoorLookup({ instance = 543 })
    CHECK(d2 and d2.map == 1944 and d2.x == d.x, "C: { instance = 543 } -> the same door")
    local d3 = R().DoorLookup({ area = 3562 })
    CHECK(d3 and d3.x == d.x, "C: { area = 3562 } (Questie's areaId) -> the same door")
    CHECK(d ~= R().DoorLookup(347), "C: a fresh table each time")
    local k = R().DoorLookup(350)
    CHECK(k and k.alternatives and #k.alternatives == 2 and k.map == 1430 and math.abs(k.x - 0.4659) < 1e-9,
        "C: Karazhan: two doors as alternatives, the main one first")
    local oh = R().DoorLookup(274)
    CHECK(oh and oh.map == 1446 and math.abs(oh.x - 0.657) < 1e-9 and oh.title == "Old Hillsbrad Foothills entrance",
        "C: the Orphan map 274: the Caverns of Time mouth, never the portal under the rock")
    local brd = R().DoorLookup({ instance = 230 })
    CHECK(brd and brd.alternatives and #brd.alternatives == 2, "C: Blackrock Depths: either gate of the mountain")
    local aq = R().DoorLookup({ instance = 509 })
    CHECK(aq and aq.map == 1451 and aq.alternatives == nil, "C: the Ruins of Ahn'Qiraj: the gate, its one spot")
    EQ(R().DoorLookup(1429), nil, "C: a zone map is no dungeon")
    EQ(R().DoorLookup({ instance = 1 }), nil, "C: an unknown instance")
    EQ(R().DoorLookup("x"), nil, "C: nil-safe (string)")
    EQ(R().DoorLookup(nil), nil, "C: nil-safe (nil)")
    EQ(R().DoorLookup({ area = 12 }), nil, "C: an outdoor areaId has no door")
    -- a dungeon uiMap the table does not key: its world position names the instance
    local saved = E().MAPS[347]
    E().MAPS[347] = nil
    local wd = R().DoorLookup(347)
    E().MAPS[347] = saved
    CHECK(wd and wd.map == 1944 and math.abs(wd.x - 0.4748) < 1e-9,
        "C: an unkeyed dungeon map: C_Map.GetWorldPosFromMapPos's instance id finds the row")
    -- Orders' Entrance(): resolvers, then this table, then the client
    local e = O().Entrance(347)
    CHECK(e and e.map == 1944 and e.title == "Hellfire Ramparts entrance", "C: CommanderOrders.Entrance(347) answers offline")
    local ei = O().Entrance({ instance = 532 })
    CHECK(ei and ei.alternatives and #ei.alternatives == 2, "C: Entrance({ instance = 532 }) keeps both doors")
    -- the lead's decision (D37): the reviewed table wins for a mapped
    -- dungeon; a registered resolver (QuestLog's, from Questie) answers only
    -- what the table lacks
    O().RegisterResolver("entrance", function(map)
        if map == 347 or map == 999347 then return { map = 1944, x = 0.4, y = 0.5, title = "Resolver door" } end
    end)
    EQ(O().Entrance(347) and O().Entrance(347).title, "Hellfire Ramparts entrance",
        "C: the door table outranks a registered entrance resolver")
    EQ(O().Entrance(999347) and O().Entrance(999347).title, "Resolver door",
        "C: ...which still answers a map the table does not know")
    -- the arrow's dungeon hint, answered by the table (orders_harness D's
    -- "No known way there" case now has a door)
    Boot({ player = { 1944, 0.45, 0.55 } })
    O().Add({ map = 347, x = 0.5, y = 0.5, title = "Ramparts quest" })
    Pass(2)
    EQ(Text("dist"), "In Hellfire Ramparts", "C: a dungeon target is named by its dungeon")
    EQ(Text("status"), "via the entrance of Hellfire Ramparts", "C: ...and the door table offers its entrance")
    CHECK(O().Guide() ~= nil, "C: Guide me to it")
    local g = O().Active()
    CHECK(g and g.map == 1944 and math.abs(g.x - 0.4748) < 1e-6, "C: Guide me pins the Ramparts door")
    -- an Orphan instance map: the hint walks to the Caverns of Time mouth
    Boot({ player = { 1446, 0.5, 0.3 } })
    O().Add({ map = 274, x = 0.5, y = 0.5, title = "Thrall" })
    Pass(2)
    EQ(Text("status"), "via the entrance of Old Hillsbrad Foothills", "C: the Orphan map gets the hint")
    CHECK(O().Guide() ~= nil, "C: Guide me")
    local cot = O().Active()
    CHECK(cot and cot.map == 1446 and math.abs(cot.x - 0.657) < 1e-6, "C: ...to the cave mouth (65.7, 49.8)")
    NOERR("C")
end)

-- ===========================================================================
-- D: npc and object queries
-- ===========================================================================
Section("D", function()
    Boot({ player = THRALLMAR })
    local p = L({ npc = 16602 })
    CHECK(p and #p == 1, "D: npc 16602: one spawn")
    local f = p and p[1]
    CHECK(f and f.map == 1944 and math.abs(f.x - 0.5671) < 1e-9 and math.abs(f.y - 0.3747) < 1e-9,
        "D: ...Hellfire 56.71, 37.47 (areaId 3483 -> uiMap 1944, 0..100 -> 0..1)")
    CHECK(f and f.title == "Floyd Pinkus" and f.kind == "npc" and f.npc == 16602 and f.zoneName == "Hellfire Peninsula",
        "D: ...titled, typed, with its id and zone")
    EQ(p and p.title, "Floyd Pinkus", "D: the list is titled by the NPC")
    EQ(Count(L({ npc = "16602" })), 1, "D: a numeric string is an id")
    -- names: the exact-name index, built once
    local before = F.nameBuilds.Npc or 0
    local s = L({ npc = "Syndicate Thief" })
    EQ(Count(s), 5, "D: a name two NPCs share: every spawn of both")
    EQ(Ids(s), "2241,2241,2241,24477,24477", "D: ...both ids")
    EQ(s and s.title, "Syndicate Thief", "D: ...titled by the name")
    L({ npc = "Floyd Pinkus" })
    EQ((F.nameBuilds.Npc or 0) - before, 1, "D: QuestieDB's name index built once")
    EQ(Count(L({ npc = { 2241, 24477 } })), 5, "D: a list of ids")
    -- instance-only NPCs: the door
    local mag = L({ npc = 17257 })
    CHECK(mag and #mag == 1 and mag[1].kind == "entrance" and mag[1].map == 1944 and math.abs(mag[1].x - 0.4764) < 1e-9,
        "D: Magtheridon ({-1,-1} in areaId 3836): his lair's door")
    EQ(mag and mag[1].title, "Magtheridon (Magtheridon's Lair entrance)", "D: ...titled with both")
    EQ(mag and mag[1].npc, 17257, "D: ...keeping the npc id")
    EQ(Count(L({ npc = 15687 })), 2, "D: Moroes: Karazhan's two doors")
    local rz = L({ npc = 644 })
    CHECK(rz and #rz == 1 and rz[1].map == 1436 and math.abs(rz[1].x - 0.425) < 1e-9,
        "D: Rhahk'Zor (the Deadmines): the Moonbrook mine's mouth, not the portal in the tunnel")
    -- bad rows
    local w = L({ npc = 900001 })
    CHECK(w and #w == 1 and w[1].map == 1429 and math.abs(w[1].x - 0.48) < 1e-9,
        "D: a spawn off the map, a junk entry and an unmapped areaId are passed over")
    local t = L({ npc = 900002 })
    CHECK(t and #t == 1 and t[1].kind == "npc" and t[1].map == 1944, "D: open world AND an instance: the open world")
    local g, gw = L({ npc = 900003 })
    CHECK(g == nil and gw == "nowhere", "D: no spawns: nowhere", gw)
    local u, uw = L({ npc = 999999 })
    CHECK(u == nil and uw == "nowhere", "D: an unknown id: nowhere", uw)
    local nb, nbw = L({ npc = "Nobody At All" })
    CHECK(nb == nil and nbw == "nowhere", "D: an unknown name: nowhere", nbw)
    for _, bad in ipairs({ "", {}, true }) do
        local b, bw = L({ npc = bad })
        CHECK(b == nil and bw == "noquery", "D: npc = " .. tostring(bad) .. ": noquery", bw)
    end
    -- objects
    local hs = L({ object = 759 })
    CHECK(hs and #hs == 1 and hs[1].map == 1434 and hs[1].kind == "object" and hs[1].object == 759
        and hs[1].title == "The Holy Spring", "D: object 759: the Holy Spring in Stranglethorn")
    EQ(Count(L({ object = "Mailbox" })), 3, "D: an object by name: every mailbox (a specific object is not faction-filtered)")
    -- copies
    local c1 = L({ npc = 16602 })
    c1[1].x, c1.title = 0.1, "Hacked"
    local c2 = L({ npc = 16602 })
    CHECK(c2[1].x ~= 0.1 and c2.title == "Floyd Pinkus", "D: places are copies")
    -- spawns are read once
    F.raise = { spawns = true }
    EQ(Count(L({ npc = 16602 })), 1, "D: a known NPC's spawns are kept (no second read)")
    F.raise = nil
    NOERR("D")
end)

-- ===========================================================================
-- E: townsfolk
-- ===========================================================================
Section("E", function()
    Boot({ player = THRALLMAR })
    local inn = L({ townsfolk = "Innkeeper" })
    EQ(Ids(inn), "16602,18905", "E: Innkeeper as Horde: Thrallmar and Falcon Watch (the Alliance three left out)")
    EQ(inn and inn.title, "Nearest innkeeper", "E: the list's words")
    for _, alias in ipairs({ "inn", "INNKEEPER", "innkeepers", " Inn Keeper " }) do
        EQ(Count(L({ townsfolk = alias })), 2, "E: alias " .. alias)
    end
    EQ(Ids(L({ townsfolk = "Repair" })), "16583,17904,22225", "E: Repair: Horde and everyone's")
    local bk, bkw = L({ townsfolk = "Banker" })
    CHECK(bk == nil and bkw == "otherside", "E: Banker as Horde (only Olivia Burnside): otherside", bkw)
    local au, auw = L({ townsfolk = "Auctioneer" })
    CHECK(au == nil and auw == "nowhere", "E: an empty list: nowhere", auw)
    EQ(Ids(L({ townsfolk = "Flight Master" })), "16587", "E: Flight Master: Barley")
    EQ(Count(L({ townsfolk = "fp" })), 1, "E: ...as \"fp\"")
    EQ(Ids(L({ townsfolk = "Battlemaster" })), "347", "E: Battlemaster")
    EQ(Ids(L({ townsfolk = "Weapon Master" })), "2704", "E: Weapon Master")
    local sm, smw = L({ townsfolk = "Stable Master" })
    CHECK(sm == nil and smw == "otherside", "E: Stable Master as Horde (only Erma): otherside", smw)
    local sh = L({ townsfolk = "Spirit Healer" })
    CHECK(sh and #sh == 6 and sh[1].npc == 6491, "E: Spirit Healer: one NPC, every graveyard")
    local mb = L({ townsfolk = "Mailbox" })
    CHECK(mb and #mb == 2 and mb[1].kind == "object", "E: Mailbox: the Horde's own list, objects")
    EQ(Ids(mb), "143981,143982", "E: ...Durotar and the Barrens")
    EQ(Count(L({ townsfolk = "Meeting Stone" })), 1, "E: Meeting Stone (Questie's \"Meeting Stones\")")
    local ct = L({ townsfolk = "Class Trainer" })
    EQ(Ids(ct), "15280", "E: Class Trainer: the player's class (PALADIN), Horde's")
    EQ(ct and ct.title, "Nearest Paladin trainer", "E: ...named for the class")
    local mt, mtw = L({ townsfolk = "Class Trainer", class = "mage" })
    CHECK(mt == nil and mtw == "nowhere", "E: class = \"mage\": that class's list (empty here)", mtw)
    EQ(Ids(L({ townsfolk = "Portal Trainer" })), "5958", "E: Portal Trainer: Thuul")
    local en = L({ townsfolk = "Enchanting Trainer" })
    EQ(Ids(en), "18753", "E: \"Enchanting Trainer\": Felannia")
    EQ(en and en.title, "Nearest Enchanting trainer", "E: ...named for the profession")
    EQ(Ids(L({ townsfolk = "Profession Trainer", profession = 333 })), "18753", "E: profession = 333 (skill line id)")
    EQ(Ids(L({ townsfolk = "Profession Trainer", profession = "enchanting" })), "18753", "E: profession = \"enchanting\"")
    EQ(Ids(L({ townsfolk = "first aid trainer" })), "18991", "E: \"first aid trainer\": Aresella")
    local jc, jcw = L({ townsfolk = "Jewelcrafting Trainer" })
    CHECK(jc == nil and jcw == "nowhere", "E: a profession Questie has no list for: nowhere", jcw)
    for _, bad in ipairs({ "Profession Trainer", "Riding Trainer", "Barber", "" }) do
        local b, bw = L({ townsfolk = bad })
        CHECK(b == nil and bw == "unknown", "E: \"" .. bad .. "\": unknown", bw)
    end
    -- the vendor lists (Stage 3) and the vendor union
    EQ(Ids(L({ townsfolk = "Reagents" })), "3335", "E: Reagents")
    EQ(Ids(L({ townsfolk = "Food" })), "16585", "E: Food")
    EQ(Ids(L({ townsfolk = "water" })), "16585", "E: \"water\" is Drink")
    EQ(Ids(L({ townsfolk = "Trade Goods" })), "989,20194", "E: Trade Goods")
    EQ(Ids(L({ townsfolk = "trade supplies" })), "989,20194", "E: ...as \"trade supplies\"")
    EQ(Ids(L({ townsfolk = "Ammo" })), "20194", "E: Ammo")
    EQ(Ids(L({ townsfolk = "Potions" })), "20989", "E: Potions")
    local bg, bgw = L({ townsfolk = "Bags" })
    CHECK(bg == nil and bgw == "nowhere", "E: Bags (an empty list): nowhere", bgw)
    local v = L({ townsfolk = "Vendor" })
    EQ(Ids(v), "989,3335,16583,16585,17904,20194,20989,22225", "E: Vendor: repair vendors and every list, each once")
    EQ(v and v.title, "Nearest vendor", "E: ...\"Nearest vendor\"")
    -- cached: a second call reads nothing
    local calls = F.calls.Npc
    L({ townsfolk = "Innkeeper" })
    L({ townsfolk = "Vendor" })
    EQ(F.calls.Npc, calls, "E: a built list is kept (no QuestieDB reads on the next call)")
    -- Questie hands out a new list (a level-up): built again
    Questie.db.char.vendorList.Food = { 16585, 22225 }
    EQ(Ids(L({ townsfolk = "Food" })), "16585,22225", "E: a new list table from Questie is read again")
    -- copies
    local c1 = L({ townsfolk = "Innkeeper" })
    c1[1].map = 1
    EQ(L({ townsfolk = "Innkeeper" })[1].map, 1944, "E: the cached list is never handed out")
    -- the Alliance side
    Boot({ player = HONOR_HOLD, faction = "Alliance" }, { stage = 3, faction = "Alliance" })
    EQ(Ids(L({ townsfolk = "Innkeeper" })), "295,16826,18251", "E: Innkeeper as Alliance")
    EQ(Ids(L({ townsfolk = "Banker" })), "2455", "E: Banker as Alliance")
    EQ(Ids(L({ townsfolk = "Stable Master" })), "6749", "E: Stable Master as Alliance")
    EQ(Ids(L({ townsfolk = "Mailbox" })), "32349", "E: the Alliance's mailboxes")
    EQ(Ids(L({ townsfolk = "Class Trainer" })), "925", "E: the Alliance's Paladin trainer")
    -- Questie's NPC blacklist
    Boot({ player = THRALLMAR }, { stage = 3, blacklist = { [22225] = true } })
    EQ(Ids(L({ townsfolk = "Repair" })), "16583,17904", "E: Questie's questNPCBlacklist is honoured")
    -- the vendor union keeps only VENDOR-flagged NPCs
    local flags = F.NPCS[17904].npcFlags
    F.NPCS[17904].npcFlags = 4096
    Boot({ player = THRALLMAR })
    F.NPCS[17904].npcFlags = flags
    EQ(Ids(L({ townsfolk = "Vendor" })), "989,3335,16583,16585,20194,20989,22225", "E: a repairer who sells nothing is no vendor")
    EQ(Ids(L({ townsfolk = "Repair" })), "16583,17904,22225", "E: ...but still repairs")
    NOERR("E")
end)

-- ===========================================================================
-- F: states
-- ===========================================================================
Section("F", function()
    -- Stage 1: the lists, no vendor lists, not ready
    Boot({ player = THRALLMAR }, { stage = 1 })
    EQ(Count(L({ townsfolk = "Innkeeper" })), 2, "F: Stage 1: the Townsfolk lists answer")
    local r, rw = L({ townsfolk = "Reagents" })
    CHECK(r == nil and rw == "notready", "F: Stage 1: a vendor list is not ready yet", rw)
    EQ(Ids(L({ townsfolk = "Vendor" })), "16583,17904,22225", "F: Stage 1: Vendor is the repair vendors for now")
    local st = R().LocateState()
    CHECK(st.hooked and not st.ready and not st.vendorLists, "F: hooked, waiting for Questie")
    -- Stage 3 arrives: the callback, a frame later the caches go and the pre-warm runs
    F.Stage3()
    EQ(R().LocateState().ready, false, "F: the ready callback only schedules (it runs in Questie's coroutine)")
    M.Advance(0.05)
    EQ(R().LocateState().ready, true, "F: ...ready a frame later")
    CHECK(R().LocateState().warming, "F: ...and the pre-warm has started")
    M.Advance(2)
    EQ(R().LocateState().warming, false, "F: the pre-warm finished")
    local calls = F.calls.Npc
    L({ townsfolk = "Repair" })
    L({ townsfolk = "Mailbox" })
    L({ townsfolk = "Class Trainer" })
    EQ(F.calls.Npc, calls, "F: the warmed kinds answer without a read")
    EQ(Ids(L({ townsfolk = "Vendor" })), "989,3335,16583,16585,17904,20194,20989,22225", "F: Vendor now includes the lists")
    EQ(Ids(L({ townsfolk = "Reagents" })), "3335", "F: the vendor lists answer after ready")
    -- never in combat
    Boot({ player = THRALLMAR }, { stage = 1 })
    M.SetCombat(true)
    F.Stage3()
    M.Advance(2)
    CHECK(R().LocateState().warming, "F: in combat the pre-warm waits")
    M.SetCombat(false)
    M.Advance(2)
    EQ(R().LocateState().warming, false, "F: ...and finishes once combat ends")
    -- Stage 0: no lists yet, ZoneDB not initialised
    Boot({ player = THRALLMAR }, { stage = 0 })
    local s0, s0w = L({ townsfolk = "Innkeeper" })
    CHECK(s0 == nil and s0w == "notready", "F: Stage 0: notready", s0w)
    local n0 = L({ npc = 16602 })
    CHECK(n0 and n0[1].map == 1944, "F: Stage 0: an npc still resolves (QuestieDB's own zone strings)")
    local sub0 = L({ npc = 900004 })
    CHECK(sub0 and sub0[1].map == 1429, "F: Stage 0: a subzone's spawn lands on its parent's map (support strings)")
    -- Questie's Stage 1 corrections change a row read before them: ready drops it
    local saved = F.NPCS[16602].spawns
    F.NPCS[16602].spawns = { [3483] = { { 60.0, 40.0 } } }
    F.Stage1()
    EQ(Ids(L({ townsfolk = "Innkeeper" })), "16602,18905", "F: Stage 1 caught up: the lists answer")
    F.Stage3()
    M.Advance(3)
    local n1 = L({ npc = 16602 })
    CHECK(n1 and math.abs(n1[1].x - 0.60) < 1e-9, "F: what was read before Questie's corrections is read again at ready")
    local inn = L({ townsfolk = "Innkeeper" })
    CHECK(inn and math.abs(inn[1].x - 0.60) < 1e-9, "F: ...lists built before ready too")
    F.NPCS[16602].spawns = saved
    -- a subzone through Questie's live ZoneDB (GetParentZoneId)
    local sub1 = L({ npc = 900004 })
    CHECK(sub1 and sub1[1].map == 1429 and math.abs(sub1[1].x - 0.42) < 1e-9, "F: Questie's ZoneDB: a subzone's parent map")
    -- QuestieDB alone
    Boot({ player = THRALLMAR, loaded = { QuestieDB = true } }, { questie = false })
    local q1, q1w = L({ townsfolk = "Innkeeper" })
    CHECK(q1 == nil and q1w == "noquestie", "F: QuestieDB alone: townsfolk needs Questie", q1w)
    local q2 = L({ npc = 16602 })
    CHECK(q2 and q2[1].map == 1944 and math.abs(q2[1].x - 0.5671) < 1e-9, "F: QuestieDB alone: npc spawns via its support strings")
    local q3 = L({ npc = 6491 })
    EQ(Count(q3), 6, "F: ...every area of a many-zone NPC")
    EQ(Count(L({ itemVendor = 6217 })), 2, "F: ...and item vendors")
    local mag = L({ npc = 17257 })
    CHECK(mag and mag[1].kind == "entrance", "F: ...and an instance NPC's door")
    EQ(R().LocateState().townsfolk, "ABSENT", "F: LocateState: Townsfolk absent")
    -- QuestieDB alone, no support strings: nothing maps an areaId
    Boot({ player = THRALLMAR, loaded = { QuestieDB = true } }, { questie = false, support = false })
    local q4, q4w = L({ npc = 16602 })
    CHECK(q4 == nil and q4w == "nowhere", "F: no zone bridge at all: nowhere", q4w)
    -- nothing installed
    Boot({ player = THRALLMAR, loaded = {} }, false)
    for _, q in ipairs({ { townsfolk = "Repair" }, { npc = 1 }, { object = 1 }, { itemVendor = 1 }, { itemSource = 1 } }) do
        local a, aw = L(q)
        local k = next(q)
        CHECK(a == nil and aw == "noquestie", "F: no Questie: " .. k .. " -> noquestie", aw)
    end
    -- a contract this file was not written for
    Boot({ player = THRALLMAR }, { stage = 3, contract = 3 })
    local c, cw = L({ npc = 16602 })
    CHECK(c == nil and cw == "noquestie", "F: QuestieDB contract 3 only: noquestie", cw)
    EQ(R().LocateState().questieDB, "CONTRACT", "F: LocateState says why")
    HAS(R().LocateState().why, "contract", "F: ...in words")
    -- Questie changed shape
    Boot({ player = THRALLMAR }, { stage = 3, brokenTownsfolk = true })
    local b, bw = L({ townsfolk = "Innkeeper" })
    CHECK(b == nil and bw == "noquestie", "F: a Townsfolk table of the wrong shape: noquestie", bw)
    EQ(R().LocateState().townsfolk, "BROKEN", "F: LocateState: BROKEN")
    NOERR("F")
end)

-- ===========================================================================
-- G: items
-- ===========================================================================
Section("G", function()
    Boot({ player = THRALLMAR })
    local cr = L({ itemVendor = 6217 })
    EQ(Ids(cr), "989,18753", "G: Copper Rod: the Horde's vendors (Johan Barnes is Alliance)")
    EQ(cr and cr.title, "Copper Rod vendor", "G: ...titled")
    local sh = L({ itemVendor = 22829 })
    EQ(Count(sh), 4, "G: Super Healing Potion: four spawns of two vendors (two are spawned nowhere)")
    local ws, wsw = L({ itemVendor = 728 })
    CHECK(ws == nil and wsw == "otherside", "G: only an Alliance vendor: otherside", wsw)
    local un, unw = L({ itemVendor = 999 })
    CHECK(un == nil and unw == "nowhere", "G: an item nobody sells: nowhere", unw)
    local bq, bqw = L({ itemVendor = "x" })
    CHECK(bq == nil and bqw == "noquery", "G: itemVendor = \"x\": noquery", bqw)
    EQ(Ids(L({ itemSource = 6217 })), "989,18753", "G: itemSource: vendors first")
    local hs = L({ itemSource = 737 })
    CHECK(hs and #hs == 1 and hs[1].kind == "object" and hs[1].object == 759, "G: itemSource: an object that holds it")
    EQ(hs and hs.title, "Holy Spring Water source", "G: ...titled")
    local rs = L({ itemSource = 872 })
    CHECK(rs and #rs == 1 and rs[1].kind == "entrance" and rs[1].map == 1436, "G: a drop inside an instance: its door")
    EQ(rs and rs.title, "Rockslicer", "G: ...titled by the item")
    local o, ow = L({ itemSource = 728 })
    CHECK(o == nil and ow == "otherside", "G: itemSource sold only by the other faction: otherside", ow)
    Boot({ player = HONOR_HOLD, faction = "Alliance" }, { stage = 3, faction = "Alliance" })
    EQ(Ids(L({ itemVendor = 728 })), "340", "G: ...and the Alliance finds Kendor Kabonka")
    EQ(Ids(L({ itemVendor = 6217 })), "18773", "G: the Alliance's Copper Rod vendor")
    NOERR("G")
end)

-- ===========================================================================
-- H: registered resolvers
-- ===========================================================================
Section("H", function()
    Boot({ player = THRALLMAR })
    local asked
    local book = function(kind, query)
        asked = { kind = kind, query = query }
        if kind ~= "Repair" then return nil end
        return {
            { map = 1944, x = 0.5313, y = 0.3816, npc = 16583, title = "Rohok (learned)" },   -- Questie has him too
            { map = 1944, x = 0.5681, y = 0.3779, title = "Reagan, learned" },               -- same spot, no id
            { map = 1944, x = 0.60, y = 0.60, title = "Learned Smith" },                     -- Questie lacks
            { map = 1944, x = 2, y = 0.5 },                                                  -- invalid: dropped
        }
    end
    EQ(O().RegisterResolver("townsfolk", book), true, "H: RegisterResolver(\"townsfolk\", fn)")
    EQ(O().RegisterResolver("townsfolk", book), true, "H: ...twice is once")
    local rp = L({ townsfolk = "Repair" })
    EQ(asked and asked.kind, "Repair", "H: the resolver is asked with the canonical kind")
    EQ(Count(rp), 4, "H: merged: three learned, Questie's Rohok and Reagan folded in, Fedryen added")
    EQ(rp and rp[1].title, "Rohok (learned)", "H: learned places first")
    CHECK(rp and rp[1].learned == true, "H: ...marked learned")
    EQ(rp and rp[4] and rp[4].npc, 17904, "H: ...then what Questie has that the book lacks")
    EQ(Count(L({ townsfolk = "Innkeeper" })), 2, "H: a kind the book does not answer: Questie's")
    O().RegisterResolver("townsfolk", function() error("book on fire") end)
    EQ(Count(L({ townsfolk = "Repair" })), 4, "H: a resolver that raises is passed over")
    HAS(R().LocateState().why, "book on fire", "H: ...and noted for diagnostics")
    EQ(#M.errors, 0, "H: ...without a reported error (as Orders' own resolvers)")
    -- npc resolvers answer first
    O().RegisterResolver("npc", function(id) if id == 777 then return { map = 1944, x = 0.3, y = 0.3, title = "Seen" } end end)
    local seen = L({ npc = 777 })
    CHECK(seen and #seen == 1 and seen[1].title == "Seen" and seen.title == "Seen", "H: an npc resolver answers first")
    EQ(Count(L({ npc = 16602 })), 1, "H: ...and passes on what it does not know")
    -- the runtime's own kinds still go to the runtime
    EQ(O().RegisterResolver("zone", function() end), true, "H: \"zone\" still registers with the runtime")
    EQ(O().RegisterResolver("nope", function() end), false, "H: an unknown kind is refused")
    EQ(O().RegisterResolver("townsfolk", 1), false, "H: a non-function is refused")
    -- no Questie: the book alone
    Boot({ player = THRALLMAR, loaded = {} }, false)
    O().RegisterResolver("townsfolk", book)
    EQ(Count(L({ townsfolk = "Repair" })), 3, "H: no Questie: the learned book alone")
    local bb, bbw = L({ townsfolk = "Banker" })
    CHECK(bb == nil and bbw == "noquestie", "H: ...and a kind it lacks says noquestie", bbw)
    NOERR("H")
end)

-- ===========================================================================
-- I: GoTo, PlaceFor, IsGoing, GoButton
-- ===========================================================================
Section("I", function()
    Boot({ player = THRALLMAR })
    M.ClearLog()
    local uid, why = O().GoTo({ townsfolk = "Innkeeper" }, { source = "Test", key = "inn" })
    CHECK(uid ~= nil, "I: GoTo({ townsfolk = \"Innkeeper\" })", why)
    local wp = uid and O().Get(uid)
    EQ(wp and wp.title, "Nearest innkeeper", "I: ...one waypoint, titled for the list")
    CHECK(wp and wp.alternatives and #wp.alternatives == 2, "I: ...both innkeepers as alternatives")
    CHECK(wp and math.abs(wp.x - 0.5671) < 1e-9, "I: ...the nearest (Floyd Pinkus, Thrallmar) first")
    EQ(O().Active() and O().Active().uid, uid, "I: ...and the arrow follows it")
    EQ(O().IsGoing("Test", "inn"), true, "I: IsGoing(source, key)")
    HAS(M.prints[#M.prints], "Waypoint set: Nearest innkeeper", "I: the success line (Announce on)")
    local pf = O().PlaceFor({ townsfolk = "Repair" })
    CHECK(pf and math.abs(pf.x - 0.5681) < 1e-9, "I: PlaceFor: the nearest repair (Reagan Mancuso)", pf and pf.x)
    local mu = O().GoTo({ npc = 17257 }, { source = "Test", key = "mag", silent = true })
    local mw = mu and O().Get(mu)
    CHECK(mw and mw.map == 1944 and math.abs(mw.x - 0.4764) < 1e-9, "I: GoTo an instance boss: his lair's door")
    local ku = O().GoTo({ entrance = { instance = 532 } }, { silent = true })
    local kw = ku and O().Get(ku)
    CHECK(kw and kw.alternatives and #kw.alternatives == 2 and kw.title == "Karazhan entrance",
        "I: GoTo an entrance: both doors")
    M.ClearLog()
    local nb, nbw = O().GoTo({ townsfolk = "Banker" })
    CHECK(nb == nil and nbw == "otherside", "I: GoTo Banker as Horde: refused", nbw)
    HAS(M.prints[#M.prints], "Only the other faction has one", "I: ...in the one refusal vocabulary")
    local nk, nkw = O().GoTo({ townsfolk = "Barber" }, { silent = true })
    CHECK(nk == nil and nkw == "unknown", "I: an unknown kind: unknown", nkw)
    EQ(O().Reason("unknown"), "Commander Orders cannot look that up", "I: ...said as")
    -- a GoButton with a query (a fresh client: Orders would fold the same
    -- spot into the waypoint above)
    Boot({ player = THRALLMAR })
    local b = Commander.UI.GoButton(UIParent, { label = "Go to Inn", query = { townsfolk = "Innkeeper" },
                                                source = "Test", key = "button" })
    b:Show()
    M.Hover(b)
    local tip = table.concat(M.tooltip, "\n")
    HAS(tip, "Hellfire Peninsula 56.7, 37.5", "I: GoButton tooltip: the nearest place's zone and coordinates")
    M.Click(b, "LeftButton")
    EQ(O().IsGoing("Test", "button"), true, "I: GoButton click: the arrow goes")
    M.Frame()
    EQ(b.__text, "Going to Inn", "I: ...and the button lights")
    NOERR("I")
end)

-- ===========================================================================
-- J: robustness
-- ===========================================================================
Section("J", function()
    Boot({ player = THRALLMAR })
    for _, q in ipairs({ "x", 1, {}, { foo = 1 } }) do
        local a, aw = L(q)
        CHECK(a == nil and aw == "noquery", "J: Locate(" .. tostring(q) .. "): noquery", aw)
    end
    local a, aw = L(nil)
    CHECK(a == nil and aw == "noquery", "J: Locate(nil): noquery", aw)
    local e1, e1w = L({ entrance = "nowhere" })
    CHECK(e1 == nil and e1w == "noquery", "J: entrance = \"nowhere\": noquery", e1w)
    local e2, e2w = L({ entrance = 1429 })
    CHECK(e2 == nil and e2w == "nowhere", "J: entrance of a zone map: nowhere", e2w)
    -- a raising QuestieDB read is contained
    Boot({ player = THRALLMAR })
    F.raise = { spawns = true }
    local r1, r1w = L({ npc = 2241 })
    CHECK(r1 == nil and r1w == "nowhere", "J: spawns raise: nowhere, not an error", r1w)
    EQ(#M.errors, 0, "J: ...nothing reported")
    F.raise = nil
    -- an error inside the locator stops at the boundary
    rawset(_G, "UnitFactionGroup", function() error("faction boom") end)
    local x, xw = L({ townsfolk = "Innkeeper" })
    rawset(_G, "UnitFactionGroup", nil)
    CHECK(x == nil and xw == "error", "J: an error inside: nil, \"error\"", xw)
    EQ(#M.errors, 1, "J: ...reported once to the error handler")
    M.ClearLog()
    -- hovering a query button twice reads QuestieDB once
    Boot({ player = THRALLMAR })
    local b = Commander.UI.GoButton(UIParent, { label = "Go", query = { townsfolk = "Flight Master" } })
    b:Show()
    M.Hover(b)
    local calls = F.calls.Npc
    M.Hover(b)
    M.Hover(b)
    EQ(F.calls.Npc, calls, "J: a hovered query button builds its list once")
    NOERR("J")
end)

-- ===========================================================================
-- K: the 3.1 review's fixes
-- ===========================================================================
Section("K", function()
    -- a "Repair" book of 300 places in the locator's order: 259 in Elwynn,
    -- the 260th by the Coilfang approach (Zangarmarsh), 40 more in Hellfire
    local function Book(kind)
        if kind ~= "Repair" then return nil end
        local out = {}
        for i = 1, 259 do
            out[#out + 1] = { map = 1429, x = 0.10 + (i % 50) * 0.01, y = 0.10 + math.floor(i / 50) * 0.1,
                              title = "Elwynn smith " .. i }
        end
        out[#out + 1] = { map = 1946, x = 0.51, y = 0.40, title = "Coilfang smith" }
        for i = 1, 40 do out[#out + 1] = { map = 1944, x = 0.20 + i * 0.01, y = 0.80, title = "Hellfire smith " .. i } end
        return out
    end

    -- inside Serpentshrine Cavern the client gives no world position: the
    -- door stands in for you, and the list is sorted before it is cut
    -- (review: locator, core; Mortog Steamhead was index 260)
    Boot({ player = { 332, 0.5, 0.5 } })
    O().RegisterResolver("townsfolk", Book)
    M.SetNoPosition(true)
    M.SetInstance("raid")
    Pass(2)
    local list = L({ townsfolk = "Repair" })
    local at
    for i, p in ipairs(list or {}) do if p.title == "Coilfang smith" then at = i end end
    CHECK(at and at > 256, "K: (the smith by the door is past the 256 cap in the locator's order)", at)
    local uid = O().GoTo({ townsfolk = "Repair" }, { source = "Test", key = "ssc", silent = true })
    local wp = uid and O().Get(uid)
    CHECK(wp and wp.map == 1946 and math.abs(wp.x - 0.51) < 1e-9,
        "K: a Go inside Serpentshrine: the nearest to its door, not the list's first", wp and (wp.map .. " " .. wp.x))
    local foreign = 0
    for _, a in ipairs(wp and wp.alternatives or {}) do if a.map == 1429 then foreign = foreign + 1 end end
    EQ(foreign, 0, "K: ...its choices are on the door's landmass")
    local pf, pfw = O().PlaceFor({ townsfolk = "Repair" })
    CHECK(pf and pf.map == 1946 and math.abs(pf.x - 0.51) < 1e-9, "K: PlaceFor inside names the same smith", pfw)
    -- walked out of the door: the arrow is on him
    M.SetNoPosition(false)
    M.SetInstance(nil)
    M.SetPlayer(1946, 0.5036, 0.4081)
    Pass(3)
    local v = R().ArrowState().view
    EQ(v.mode, "NAV", "K: out of the door: a straight arrow")
    local _, sn, sw = M.World(1946, 0.51, 0.40)
    local pp = M.W.player
    NEAR(v.distance, math.sqrt((pp.north - sn) ^ 2 + (pp.west - sw) ^ 2), 0.5, "K: ...to the smith by the door")
    -- an instance whose door nobody knows, or no position at all: a
    -- "nearest" townsfolk is named nowhere rather than arbitrarily
    M.SetPlayer(1944, 0.5, 0.5)
    M.SetNoPosition(true)
    M.Frame()
    local np, npw = O().PlaceFor({ townsfolk = "Repair" })
    CHECK(np == nil and npw == "no position", "K: no position to measure from: no nearest named", npw)
    M.SetInstance("party")
    np, npw = O().PlaceFor({ townsfolk = "Repair" })
    CHECK(np == nil and npw == "instance", "K: ...inside an instance with no door: said so", npw)
    M.SetInstance(nil)
    M.SetNoPosition(false)
    NOERR("K inside")

    -- inside Magisters' Terrace the client has no uiMap at all (2.5.6: no
    -- UiMap row and no UiMapAssignment row for 585), so GetBestMapForUnit
    -- answers nil: the instance's own id (GetInstanceInfo's 8th) finds its
    -- door on the Isle (review-r2; the real list put Smith Hauthaa past the
    -- 256 cap and the arrow went to Elwynn)
    local function IsleBook(kind)
        if kind ~= "Repair" then return nil end
        local out = {}
        for i = 1, 259 do
            out[#out + 1] = { map = 1429, x = 0.10 + (i % 50) * 0.01, y = 0.10 + math.floor(i / 50) * 0.1,
                              title = "Elwynn smith " .. i }
        end
        out[#out + 1] = { map = 1957, x = 0.506, y = 0.408, title = "Isle smith" }
        for i = 1, 40 do out[#out + 1] = { map = 1944, x = 0.20 + i * 0.01, y = 0.80, title = "Hellfire smith " .. i } end
        return out
    end
    local MGT_DOOR = { 1957, 0.6152, 0.3110 }
    Boot({ player = MGT_DOOR, faction = "Alliance" })
    O().RegisterResolver("townsfolk", IsleBook)
    M.SetNoMap(true)
    M.SetNoPosition(true)
    M.SetInstance("party", 585)
    Pass(2)
    EQ(R().PlayerMap(), nil, "K MgT: (no uiMap in there: GetBestMapForUnit answers nil)")
    list = L({ townsfolk = "Repair" })
    at = nil
    for i, p in ipairs(list or {}) do if p.title == "Isle smith" then at = i end end
    CHECK(at and at > 256, "K MgT: (the Isle's smith is past the 256 cap in the locator's order)", at)
    local mu = O().GoTo({ townsfolk = "Repair" }, { source = "Test", key = "mgt", silent = true })
    local mw = mu and O().Get(mu)
    CHECK(mw and mw.map == 1957 and math.abs(mw.x - 0.506) < 1e-9,
        "K MgT: a Go inside Magisters' Terrace: the nearest to its door, found by the instance id",
        mw and (mw.map .. " " .. mw.x))
    foreign = 0
    for _, a in ipairs(mw and mw.alternatives or {}) do if a.map ~= 1957 then foreign = foreign + 1 end end
    EQ(foreign, 0, "K MgT: ...its choices are on the Isle's landmass")
    local mp = O().PlaceFor({ townsfolk = "Repair" })
    CHECK(mp and mp.map == 1957 and math.abs(mp.x - 0.506) < 1e-9, "K MgT: PlaceFor inside names the same smith")
    -- the id is what finds it: without one the old "unknown" answer
    M.SetInstance("party")
    local nm, nmw = O().PlaceFor({ townsfolk = "Repair" })
    CHECK(nm == nil and nmw == "instance", "K MgT: (with no instance id: no nearest named, as before)", nmw)
    M.SetInstance("party", 585)
    -- walked out of the door: a straight arrow to him
    M.SetNoMap(false)
    M.SetNoPosition(false)
    M.SetInstance(nil)
    M.SetPlayer(MGT_DOOR[1], MGT_DOOR[2], MGT_DOOR[3])
    Pass(3)
    local mv = R().ArrowState().view
    EQ(mv.mode, "NAV", "K MgT: out of the door: a straight arrow")
    local _, hn, hw = M.World(1957, 0.506, 0.408)
    pp = M.W.player
    NEAR(mv.distance, math.sqrt((pp.north - hn) ^ 2 + (pp.west - hw) ^ 2), 0.5, "K MgT: ...to the Isle's smith")
    NOERR("K MgT")

    -- a death in Magisters' Terrace: no map to remember, the instance id
    -- instead, and the ghost's arrow goes to its door
    Boot({ player = MGT_DOOR, faction = "Alliance" })
    M.SetNoMap(true)
    M.SetNoPosition(true)
    M.SetInstance("party", 585)
    M.SetLife("DEAD")
    M.Fire("PLAYER_DEAD")
    local death = CommanderOrdersChar and CommanderOrdersChar.Corpse
    CHECK(death and death.map == nil and death.instanceID == 585,
        "K MgT corpse: the death is remembered by its instance id", death and tostring(death.instanceID))
    M.SetNoMap(false)
    M.SetNoPosition(false)
    M.SetInstance(nil)
    M.SetPlayer(1957, 0.48, 0.35)
    M.SetLife("GHOST")
    M.Fire("PLAYER_ALIVE")
    Pass(2)
    local mc = R().Store():Corpse()
    CHECK(mc and mc.map == 1957 and math.abs(mc.x - 0.6152) < 1e-9 and math.abs(mc.y - 0.3110) < 1e-9,
        "K MgT corpse: the corpse arrow points at Magisters' Terrace's door", mc and (mc.map .. " " .. mc.x))
    EQ(mc and mc.title, "Your corpse: Magisters' Terrace entrance", "K MgT corpse: ...and says so")
    NOERR("K MgT corpse")

    -- ...and should the client answer the Isle's zone map in there (not an
    -- instance map, and no door of its own): the id still finds the door,
    -- for a Go and for the corpse, named by the door rather than the zone
    Boot({ player = MGT_DOOR, faction = "Alliance" })
    O().RegisterResolver("townsfolk", IsleBook)
    M.SetNoPosition(true)
    M.SetInstance("party", 585)
    Pass(2)
    EQ(R().PlayerMap(), 1957, "K MgT zone: (the client answers the Isle's map)")
    local zp = O().PlaceFor({ townsfolk = "Repair" })
    CHECK(zp and zp.map == 1957 and math.abs(zp.x - 0.506) < 1e-9, "K MgT zone: PlaceFor names the Isle's smith")
    M.SetLife("DEAD")
    M.Fire("PLAYER_DEAD")
    M.SetNoPosition(false)
    M.SetInstance(nil)
    M.SetPlayer(1957, 0.48, 0.35)
    M.SetLife("GHOST")
    M.Fire("PLAYER_ALIVE")
    Pass(2)
    mc = R().Store():Corpse()
    CHECK(mc and mc.map == 1957 and math.abs(mc.x - 0.6152) < 1e-9, "K MgT zone: the corpse arrow at its door",
        mc and (mc.map .. " " .. mc.x))
    EQ(mc and mc.title, "Your corpse: Magisters' Terrace entrance", "K MgT zone: ...named by the door, not the zone")
    NOERR("K MgT zone")

    -- the hover's cost (review: perf): every place's world position by
    -- arithmetic from its map's two probes, measured once (not again in
    -- PlaceFor), never two Vector2Ds a place
    Boot({ player = THRALLMAR })
    O().RegisterResolver("townsfolk", Book)
    L({ townsfolk = "Repair" })
    local calls, gwpf = 0, C_Map.GetWorldPosFromMapPos
    C_Map.GetWorldPosFromMapPos = function(...) calls = calls + 1 return gwpf(...) end
    O().PlaceFor({ townsfolk = "Repair" })
    local first = calls
    calls = 0
    -- each measuring pass samples your map position once (a Vector2D):
    -- a query's places are measured in Resolve, never again in PlaceFor
    local samples, gpmp = 0, C_Map.GetPlayerMapPosition
    C_Map.GetPlayerMapPosition = function(...) samples = samples + 1 return gpmp(...) end
    O().PlaceFor({ townsfolk = "Repair" })
    C_Map.GetPlayerMapPosition = gpmp
    local second = calls
    C_Map.GetWorldPosFromMapPos = gwpf
    CHECK(first <= 10, "K: a nearest-of-300 PlaceFor: two probes per map, not two lookups a place", first)
    EQ(second, 0, "K: ...and none the next time")
    EQ(samples, 1, "K: ...measured once, not again over the sorted list")
    NOERR("K cost")

    -- two places exactly as far away (mirror images about you): the list's
    -- order decides, never the last bits of the arithmetic
    Boot({ player = { 1429, 0.42, 0.655 } })
    O().RegisterResolver("townsfolk", function(kind)
        if kind == "Innkeeper" then
            return { { map = 1429, x = 0.43, y = 0.66, title = "East" }, { map = 1429, x = 0.41, y = 0.65, title = "West" } }
        elseif kind == "Banker" then
            return { { map = 1429, x = 0.41, y = 0.65, title = "West" }, { map = 1429, x = 0.43, y = 0.66, title = "East" } }
        end
    end)
    local tieA = O().PlaceFor({ townsfolk = "Innkeeper" })
    local tieB = O().PlaceFor({ townsfolk = "Banker" })
    CHECK(tieA and math.abs(tieA.x - 0.43) < 1e-9, "K: a tie keeps the list's first (East)", tieA and tieA.x)
    CHECK(tieB and math.abs(tieB.x - 0.41) < 1e-9, "K: ...either way round (West)", tieB and tieB.x)
    -- the Eastern Kingdoms map holds two frames (Quel'Thalas is 530): two
    -- spots on it, the 530 one first, are two landmasses, not one
    local two = O().PlaceFor({ alternatives = { { 1415, 0.50, 0.20 }, { 1415, 0.50, 0.60 } } })
    CHECK(two and two.elsewhere == nil, "K: a continent map's two frames are told apart (the 0 one is yours)",
        two and (two.map .. " " .. tostring(two.elsewhere)))
    NOERR("K tie")

    -- Auberdine: the nearest bank is Darnassus, one boat away on the
    -- Teldrassil island, not Everlook through Felwood (review: core)
    Boot({ player = { 1439, 0.37, 0.44 }, faction = "Alliance" })
    O().RegisterResolver("townsfolk", function(kind)
        if kind ~= "Banker" then return nil end
        return { { map = 1452, x = 0.615, y = 0.384, title = "Everlook bank" },
                 { map = 1457, x = 0.40, y = 0.42, title = "Darnassus bank" },
                 { map = 1457, x = 0.37, y = 0.39, title = "Darnassus bank, the far window" } }
    end)
    local bu = O().GoTo({ townsfolk = "Banker" }, { source = "Test", key = "bank", silent = true })
    local bw = bu and O().Get(bu)
    CHECK(bw and bw.map == 1457 and math.abs(bw.x - 0.40) < 1e-9, "K: Auberdine: Darnassus' bank, not Everlook's",
        bw and (bw.map .. " " .. bw.x))
    local mainland = 0
    for _, a in ipairs(bw and bw.alternatives or {}) do if a.map ~= 1457 then mainland = mainland + 1 end end
    EQ(mainland, 0, "K: ...its choices are the island's alone (the arrow keeps to the boat)")
    Pass(3)
    EQ(R().ArrowState().view.mode, "OTHER", "K: ...the arrow names the crossing")
    EQ(Text("status"), "via the boat to Teldrassil at Auberdine", "K: ...by boat from Auberdine")
    local pb = O().PlaceFor({ townsfolk = "Banker" })
    CHECK(pb and pb.map == 1457, "K: PlaceFor agrees", pb and pb.map)
    NOERR("K island")

    -- Honor Hold: no banker in Outland (the fixture's only one stands in
    -- Stormwind), so "the nearest banker" is nobody here (review: locator)
    Boot({ player = HONOR_HOLD, faction = "Alliance" })
    local nb, nbw = O().PlaceFor({ townsfolk = "Banker" })
    CHECK(nb == nil and nbw == "elsewhere", "K: PlaceFor names no banker from another landmass", nbw)
    EQ(O().Reason("elsewhere"), "None on your landmass", "K: ...said as")
    local gu = O().GoTo({ townsfolk = "Banker" }, { source = "Test", key = "far", silent = true })
    CHECK(gu ~= nil, "K: ...a Go still goes")
    Pass(3)
    EQ(R().ArrowState().view.mode, "OTHER", "K: ...and the arrow shows the crossing")
    local olivia = O().PlaceFor({ npc = 2455 })
    CHECK(olivia and olivia.map == 1453 and olivia.elsewhere == true,
        "K: a named NPC on another landmass is answered, flagged elsewhere")
    local here = O().PlaceFor({ townsfolk = "Repair" })
    CHECK(here and here.elsewhere == nil, "K: ...a place on your landmass is not flagged")
    NOERR("K elsewhere")

    -- a death in Karazhan: the corpse arrow carries both doors and takes
    -- the nearer (review: consistency)
    Boot({ player = { 1430, 0.47, 0.70 } })
    M.SetPlayer(350, 0.5, 0.5)
    M.SetInstance("raid")
    M.SetCorpse(350, 0.5, 0.5)
    M.SetLife("DEAD")
    M.Fire("PLAYER_DEAD")
    M.SetInstance(nil)
    M.SetPlayer(1430, 0.4647, 0.69)
    M.SetLife("GHOST")
    M.Fire("PLAYER_ALIVE")
    Pass(2)
    local corpse = R().Store():Corpse()
    CHECK(corpse and corpse.alternatives and #corpse.alternatives == 2, "K: the corpse arrow carries both Karazhan doors",
        corpse and corpse.alternatives and #corpse.alternatives)
    local _, dn, dw = M.World(1430, 0.4647, 0.7051)
    pp = M.W.player
    NEAR(R().ArrowState().view.distance, math.sqrt((pp.north - dn) ^ 2 + (pp.west - dw) ^ 2), 0.5,
        "K: ...and points at the nearer")
    NOERR("K corpse")
end)

-- ===========================================================================
-- R: the real Questie (a child process: its own mock, its own globals)
-- ===========================================================================
local function RealSection()
    local addons = HERE:match("^(.*)/Commander_Orders/Harness$") or ""
    if not (Exists(REAL_BOOT) and Exists(addons .. "/Questie/Questie_TBC.toc")
            and Exists(addons .. "/QuestieDB/QuestieDB_TBC.toc")) then
        io.write("SKIP  R: the real Questie boot is not on this machine (", REAL_BOOT, ")\n")
        return
    end
    local lua = (arg and arg[-1]) or "luajit"
    for _, faction in ipairs({ "Horde", "Alliance" }) do
        local pipe = io.popen(string.format("cd '%s' && '%s' '%s' --real %s 2>&1", addons, lua, SELF, faction))
        local out = pipe and pipe:read("*a") or ""
        if pipe then pipe:close() end
        local sc, sf = out:match("REALSUMMARY\t(%d+)\t(%d+)")
        if not sc then
            CHECK(false, "R " .. faction .. ": the real boot ran", out:sub(-400))
        else
            checks = checks + tonumber(sc)
            fails = fails + tonumber(sf)
            for line in out:gmatch("[^\n]+") do
                if line:match("^FAIL") then io.write(line, "\n") end
                if os.getenv("ORDERS_LOCATE_VERBOSE") and line:match("^REAL") then io.write(line, "\n") end
            end
        end
    end
end
RealSection()

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
