-- Commander Logistics + Adjutant over the REAL Commander Orders (luajit).
--
--     /opt/homebrew/bin/luajit Commander_Logistics/Harness/logistics_orders_smoke.lua
--
-- Repair vendors are learned by Logistics, offered by Adjutant's durability
-- alert and pointed at by Commander Orders, so the only honest test of the
-- feature is all three together. This harness boots the client mock Orders'
-- own harnesses use (Commander_Orders/Harness/orders_mock.lua: this build's
-- UiMap DB2 rows as the world, the REAL Commander_Events settings framework,
-- every Orders file), then loads Logistics and Adjutant on top, the way the
-- client loads addons in one session, and drives merchants, durability and
-- combat through it.
--
-- Section G is the consumer contract for the other modules wired in with
-- Logistics in Orders 3.0: the exact spec shapes Commander_Guide,
-- Commander_Spoils and Commander_PartyFrames hand CommanderOrders.Add, fed to
-- the real API. Their own harnesses use a recording stub; this is where the
-- real Orders says yes.
--
--   A  boot: everything loads clean, both settings pages, the globals written
--   B  learning: a repair merchant is remembered (map, world, landmass), a
--      plain merchant is not, nor one inside an instance; the switches; a
--      revisit updates; the per-faction cap drops the oldest
--   C  nearest: by real yards, never across a landmass (Eversong vs Hellfire,
--      both instance 530), per faction, refusals in words
--   D  the waypoint on the real Orders: keyed, takes the arrow, the arrow
--      navigates to it, a repair merchant takes it down, disabled and absent
--   E  Adjutant: the banner names the vendor, the offer is temporary and
--      never asks for the arrow (so never steals a pin, a running route, a
--      closest mark of yours or a Clear), never placed in combat, withdrawn
--      when mended
--   F  the settings pages and /clog repair
--   G  the consumer contract: Guide's entrance (both Karazhan doors, with or
--      without a resolver's one-door answer; CommanderOrders.Entrance),
--      Spoils' farm, PartyFrames' unit follow, against the real Orders
--   H  one pass with every Orders file loaded (its pins and manager too)
--   I  supply lines through Orders' locator (2.3.0): the learned book as a
--      "townsfolk" resolver merged with another source, the nearest of all
--      on the landmass, the waypoint through GoTo and worded by Orders, the
--      vendor line and its merchant clear, the vendor's own spawn stored,
--      Adjutant's full-bags offer, /clog vendor

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then HERE = (os.getenv("PWD") or ".") .. "/" .. HERE end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local M = dofile(ADDONS .. "/Commander_Orders/Harness/orders_mock.lua")

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
local function LastPrint() return M.prints[#M.prints] or "" end

-- ---------------------------------------------------------------------------
-- The extra client the two modules touch (merchant, durability, bags,
-- battlefield queue), served beside the mock's own
-- ---------------------------------------------------------------------------
local world = {}
local function ExtraClient(m, w)
    world = {
        merchant = false, canRepair = false, npc = nil, durability = 1,
        repairs = 0, faction = nil,
    }
    local baseName, baseGUID, baseFaction = UnitName, UnitGUID, UnitFactionGroup
    rawset(_G, "UnitName", function(unit)
        if unit == "npc" then return world.npc and world.npc.name end
        return baseName(unit)
    end)
    rawset(_G, "UnitGUID", function(unit)
        if unit == "npc" then return world.npc and world.npc.guid end
        return baseGUID(unit)
    end)
    rawset(_G, "UnitFactionGroup", function(unit)
        if world.faction then return world.faction, world.faction end
        return baseFaction(unit)
    end)
    rawset(_G, "CanMerchantRepair", function() return world.merchant and world.canRepair end)
    rawset(_G, "GetRepairAllCost", function() return 0, false end)
    rawset(_G, "RepairAllItems", function() world.repairs = world.repairs + 1 end)
    rawset(_G, "GetMoney", function() return 1000000 end)
    rawset(_G, "MerchantFrame", { IsShown = function() return world.merchant end })
    rawset(_G, "C_Container", {
        GetContainerNumSlots = function() return 0 end,
        GetContainerNumFreeSlots = function() return 0 end,
        GetContainerItemInfo = function() return nil end,
        UseContainerItem = function() end,
    })
    rawset(_G, "C_Item", { GetItemInfo = function() return nil end })
    rawset(_G, "GetInventoryItemDurability", function(slot)
        if slot == 5 then return math.floor(world.durability * 100 + 0.5), 100 end
        return nil
    end)
    rawset(_G, "UnitHealth", function() return 100 end)
    rawset(_G, "UnitHealthMax", function() return 100 end)
    rawset(_G, "GetBattlefieldStatus", function() return "none" end)
    rawset(_G, "GetMaxBattlefieldID", function() return 3 end)
end

local loadErrors = {}
local function LoadAddonFile(path)
    local chunk, err = loadfile(path)
    if not chunk then loadErrors[#loadErrors + 1] = path .. ": " .. tostring(err) return end
    local ok, runErr = pcall(chunk)
    if not ok then loadErrors[#loadErrors + 1] = path .. ": " .. tostring(runErr) end
end

local CONSUMER_FILES = {
    "Commander_Logistics/CommanderLogisticsDB.lua",
    "Commander_Logistics/CommanderLogistics.lua",
    "Commander_Adjutant/CommanderAdjutantDB.lua",
    "Commander_Adjutant/CommanderAdjutant.lua",
}

-- The locator (3.1) is left out too: its shipped door table answers the
-- entrances section G expects to be unknown; section I boots it
local SKIP = { CommanderOrdersPins = true, CommanderOrdersUI = true, CommanderOrdersLocate = true }
local function Boot(opts)
    opts = opts or {}
    opts.skipFiles = opts.skipFiles or SKIP
    local userBefore = opts.before
    opts.before = function(m, w)
        ExtraClient(m, w)
        if userBefore then userBefore(m, w) end
    end
    opts.afterFiles = function(m, w)
        w.phase = "consumers"
        if not opts.noConsumers then
            for _, f in ipairs(CONSUMER_FILES) do LoadAddonFile(ADDONS .. "/" .. f) end
            M.Fire("ADDON_LOADED", "Commander_Logistics")
            M.Fire("ADDON_LOADED", "Commander_Adjutant")
        end
        w.phase = "orders"
    end
    return M.Boot(opts)
end

local function O() return CommanderOrders end
local function Pass(n) M.Advance((n or 1) * 0.1 + 0.02) end

-- Stand at a vendor and open their window
local function OpenMerchant(npc, canRepair, map, x, y)
    if map then M.SetPlayer(map, x, y) end
    world.npc = npc
    world.merchant, world.canRepair = true, canRepair ~= false
    M.Fire("MERCHANT_SHOW")
end
local function CloseMerchant()
    world.merchant = false
    M.Fire("MERCHANT_CLOSED")
    world.npc = nil
end
local function Book()
    local db = CommanderLogisticsDB
    return db and db.RepairVendors and db.RepairVendors[(UnitFactionGroup("player"))]
end
local function Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

-- Fixtures: made-up vendors at real places. The ids are fixture ids (9xxxx),
-- not claims about which creature stands there.
local SMITH_GOLDSHIRE = { name = "Goldshire Smith", guid = "Creature-0-4379-0-11-90001-00002B6E9A" }
local SMITH_STORMWIND = { name = "Stormwind Smith", guid = "Creature-0-4379-0-11-90002-00002B6E9B" }
local SMITH_HELLFIRE  = { name = "Thrallmar Smith", guid = "Creature-0-4379-530-11-90003-00002B6E9C" }
local SMITH_EVERSONG  = { name = "Falconwing Smith", guid = "Creature-0-4379-530-11-90004-00002B6E9D" }
local GROCER          = { name = "A Grocer", guid = "Creature-0-4379-0-11-90005-00002B6E9E" }

local function BannerText()
    local banner = _G.CommanderAdjutantBanner
    for _, c in ipairs(banner and banner.__children or {}) do
        if c.__kind == "FontString" then return c.__text end
    end
    return nil
end

-- ===========================================================================
-- A  boot
-- ===========================================================================
do
    -- The globals Orders alone writes, to tell the consumers' own apart
    Boot({ noConsumers = true })
    local base = {}
    for _, w in ipairs(M.writes) do base[w.name] = true end

    Boot()
    CHECK(#loadErrors == 0, "A: Logistics and Adjutant load clean", loadErrors[1])
    CHECK(#M.loadErrors == 0, "A: Orders loads clean", M.loadErrors[1])
    CHECK(#M.errors == 0, "A: a quiet login", M.errors[1])
    CHECK(type(CommanderLogistics_NearestRepair) == "function", "A: Logistics' nearest-repair API is there")
    EQ(CommanderLogisticsDB.LearnRepairVendors, true, "A: Remember Repair Vendors defaults on")
    EQ(CommanderAdjutantDB.RepairWaypoint, true, "A: Mark the Nearest Repair defaults on")
    EQ(CommanderLogisticsDB.RepairVendors, nil, "A: the vendor book is data, not a default")
    local ALLOWED = {
        CommanderLogisticsDB = true, COMMANDER_LOGISTICS_EVENTS = true,
        CommanderAdjutantDB = true, COMMANDER_ADJUTANT_EVENTS = true,
        CommanderAdjutant_TestAlert = true, CommanderAdjutant_TestQueueTimer = true,
        CommanderAdjutantBanner = true,
    }
    local strays = {}
    for _, w in ipairs(M.writes) do
        local n = w.name
        -- their own namespaces (Adjutant's named frames: the banner, the port
        -- bar, the queue timer and its Enter button), and what the settings
        -- framework names for their pages
        if not base[n] and not ALLOWED[n] and not n:match("^CommanderLogistics_")
            and not n:match("^CommanderAdjutant") and not n:match("^SLASH_COMMANDERUI_")
            and not n:match("^CommanderUIScroll") and not n:match("^CommanderUIDropDown%d+$") then
            strays[#strays + 1] = n
        end
    end
    CHECK(#strays == 0, "A: the two modules write only their documented globals", table.concat(strays, " "))
end

-- ===========================================================================
-- B  learning
-- ===========================================================================
do
    Boot()
    -- A repair merchant in Goldshire
    OpenMerchant(SMITH_GOLDSHIRE, true, 1429, 0.4165, 0.6551)
    CloseMerchant()
    local book = Book()
    EQ(Count(book), 1, "B: a repair merchant is remembered")
    local v = book and book["90001"]
    CHECK(v ~= nil, "B: ...keyed by its creature id")
    if v then
        EQ(v.name, "Goldshire Smith", "B: ...with its name")
        EQ(v.map, 1429, "B: ...on the map the player stands on")
        NEAR(v.x, 0.4165, 1e-9, "B: ...at the player's map x")
        NEAR(v.y, 0.6551, 1e-9, "B: ...and y")
        local inst, n, w = M.World(1429, 0.4165, 0.6551)
        EQ(v.inst, inst, "B: ...in the player's world instance")
        NEAR(v.north, n, 1e-6, "B: ...north from UnitPosition's first value")
        NEAR(v.west, w, 1e-6, "B: ...west from its second (never crossed: Orders D1)")
        EQ(v.land, 1415, "B: ...on the Eastern Kingdoms landmass")
        CHECK(type(v.seen) == "number" and v.seen > 0, "B: ...stamped with when")
    end
    EQ(world.repairs, 0, "B: (nothing needed repair)")

    -- A merchant who does not repair is not a repair vendor
    OpenMerchant(GROCER, false, 1429, 0.43, 0.66)
    CloseMerchant()
    EQ(Count(Book()), 1, "B: a merchant who cannot repair is not remembered")

    -- Inside an instance there is no position: nothing to remember
    M.SetNoPosition(true)
    OpenMerchant(SMITH_STORMWIND, true)
    CloseMerchant()
    M.SetNoPosition(false)
    EQ(Count(Book()), 1, "B: a repair vendor met with no position is not remembered")

    -- The switches
    CommanderLogisticsDB.LearnRepairVendors = false
    OpenMerchant(SMITH_STORMWIND, true, 1453, 0.6, 0.7)
    CloseMerchant()
    EQ(Count(Book()), 1, "B: Remember Repair Vendors off: not remembered")
    CommanderLogisticsDB.LearnRepairVendors = true
    CommanderLogisticsDB.EnableLogistics = false
    OpenMerchant(SMITH_STORMWIND, true, 1453, 0.6, 0.7)
    CloseMerchant()
    EQ(Count(Book()), 1, "B: Logistics switched off: not remembered")
    CommanderLogisticsDB.EnableLogistics = true

    -- A second vendor, then a revisit that moves the first
    OpenMerchant(SMITH_STORMWIND, true, 1453, 0.6, 0.7)
    CloseMerchant()
    EQ(Count(Book()), 2, "B: a second repair vendor")
    OpenMerchant(SMITH_GOLDSHIRE, true, 1429, 0.42, 0.66)
    CloseMerchant()
    EQ(Count(Book()), 2, "B: a revisit is the same vendor, not a twin")
    NEAR(Book()["90001"].x, 0.42, 1e-9, "B: ...where they stand now")
    EQ(CommanderLogistics_RepairVendorCount(), 2, "B: the count")

    -- The cap: the vendor seen longest ago goes first
    local db = Book()
    for i = 1, 398 do
        db["fake" .. i] = { name = "F" .. i, map = 1429, x = 0.5, y = 0.5, north = 0, west = 0,
                            inst = 0, land = 1415, seen = 1000 + i }
    end
    EQ(Count(Book()), 400, "B: (a full book)")
    OpenMerchant({ name = "Newcomer", guid = "Creature-0-4379-0-11-90009-00002B6E9F" }, true, 1429, 0.5, 0.5)
    CloseMerchant()
    EQ(Count(Book()), 400, "B: a full book stays at the cap")
    EQ(Book()["fake1"], nil, "B: ...by dropping the oldest sighting")
    CHECK(Book()["90009"] ~= nil, "B: ...and keeping the newcomer")
    for i = 2, 398 do db["fake" .. i] = nil end
    db["90009"] = nil
    CHECK(#M.errors == 0, "B: no errors", M.errors[1])
end

-- ===========================================================================
-- C  nearest
-- ===========================================================================
do
    -- Book: Goldshire and Stormwind (instance 0, EK), Thrallmar (530, Outland)
    OpenMerchant(SMITH_HELLFIRE, true, 1944, 0.567, 0.375)
    CloseMerchant()

    -- From Elwynn: Goldshire, by real yards
    M.SetPlayer(1429, 0.47, 0.60)
    local v, why = CommanderLogistics_NearestRepair()
    CHECK(v and v.name == "Goldshire Smith", "C: from Elwynn the nearest is Goldshire", v and v.name or why)
    if v then
        local _, pn, pw = M.World(1429, 0.47, 0.60)
        local _, vn, vw = M.World(1429, 0.42, 0.66)
        NEAR(v.yards, math.sqrt((pn - vn) ^ 2 + (pw - vw) ^ 2), 0.01, "C: ...by straight-line yards")
        EQ(v.zone, "Elwynn Forest", "C: ...named with its zone")
        EQ(v.map, 1429, "C: ...a copy carrying the map position")
    end
    -- Stand in Stormwind: Stormwind wins
    M.SetPlayer(1453, 0.6, 0.69)
    v = CommanderLogistics_NearestRepair()
    CHECK(v and v.name == "Stormwind Smith", "C: in Stormwind the nearest is Stormwind's", v and v.name)

    -- Eversong is instance 530 like Hellfire, on another landmass: the
    -- Thrallmar smith is NOT near, and the EK ones are another instance
    M.SetPlayer(1941, 0.5, 0.5)
    v, why = CommanderLogistics_NearestRepair()
    EQ(v, nil, "C: from Eversong neither Outland's smith nor instance 0's is near")
    EQ(why, "elsewhere", "C: ...and it says why")
    OpenMerchant(SMITH_EVERSONG, true, 1941, 0.44, 0.71)
    CloseMerchant()
    M.SetPlayer(1941, 0.5, 0.5)
    v = CommanderLogistics_NearestRepair()
    CHECK(v and v.name == "Falconwing Smith", "C: an Eversong smith is near from Eversong", v and v.name)
    -- ...and from Hellfire, the Thrallmar smith, never the Eversong one
    M.SetPlayer(1944, 0.55, 0.40)
    v = CommanderLogistics_NearestRepair()
    CHECK(v and v.name == "Thrallmar Smith", "C: from Hellfire, Thrallmar (same 530, other landmass ignored)", v and v.name)

    -- No position, another faction, nothing at all
    M.SetNoPosition(true)
    v, why = CommanderLogistics_NearestRepair()
    EQ(why, "noposition", "C: inside an instance there is no nearest")
    M.SetNoPosition(false)
    world.faction = "Alliance"
    v, why = CommanderLogistics_NearestRepair()
    EQ(why, "none", "C: an Alliance character has its own (empty) book")
    CommanderLogistics_RepairWaypoint()
    HAS(LastPrint(), "no repair vendor learned yet", "C: ...and says so in words")
    world.faction = nil
    CHECK(#M.errors == 0, "C: no errors", M.errors[1])
end

-- ===========================================================================
-- D  the waypoint on the real Orders
-- ===========================================================================
do
    M.SetPlayer(1429, 0.47, 0.60)
    local ok, uid, vendor = CommanderLogistics_RepairWaypoint()
    EQ(ok, true, "D: the real Orders takes the repair waypoint")
    local wp = O().Get(uid)
    CHECK(wp ~= nil, "D: ...and holds it")
    if wp then
        EQ(wp.title, "Repair: Goldshire Smith", "D: titled with the vendor")
        EQ(wp.source, "Logistics", "D: owned by Logistics")
        EQ(wp.key, "repair", "D: one key")
        EQ(wp.map, 1429, "D: on Elwynn")
        NEAR(wp.x, 0.42, 1e-9, "D: at the vendor's x")
        EQ(wp.temporary, false, "D: asked for, so not temporary")
        EQ(wp.persistent, false, "D: a consumer mark, session only")
    end
    HAS(LastPrint(), "Waypoint set: Repair: Goldshire Smith", "D: one line says so")
    local active = O().Active()
    EQ(active and active.uid, uid, "D: it has the arrow")
    Pass(3)
    local view = O().R.View()
    EQ(view.mode, "NAV", "D: the arrow navigates to it")
    NEAR(view.distance, vendor.yards, 1.0, "D: ...and the arrow's distance is Logistics' distance")

    -- Asked again: the same record, moved, never a twin
    local ok2, uid2 = CommanderLogistics_RepairWaypoint()
    EQ(uid2, uid, "D: asking again is the same waypoint")
    EQ(#O().List({ source = "Logistics" }), 1, "D: ...one of them")

    -- Opening ANY repair merchant takes it down: you are at one
    OpenMerchant(SMITH_STORMWIND, true, 1453, 0.6, 0.7)
    CloseMerchant()
    Pass(1)
    EQ(O().Get(uid), nil, "D: a repair merchant takes the waypoint down")
    -- ...but a grocer does not
    M.SetPlayer(1429, 0.47, 0.60)
    ok, uid = CommanderLogistics_RepairWaypoint()
    OpenMerchant(GROCER, false)
    CloseMerchant()
    CHECK(O().Get(uid) ~= nil, "D: a merchant who cannot repair leaves it")

    -- Orders switched off, and Orders absent: words and the /way line
    CommanderOrdersDB.EnableOrders = false
    local okOff, why = CommanderLogistics_RepairWaypoint()
    EQ(okOff, false, "D: Orders switched off refuses")
    EQ(why, "disabled", "D: ...with Orders' reason")
    HAS(LastPrint(), "Commander Orders is turned off", "D: ...in words")
    HAS(LastPrint(), "/way #1429 42.00 66.00 Repair: Goldshire Smith", "D: ...with the line to paste")
    CommanderOrdersDB.EnableOrders = true
    local keep = CommanderOrders
    rawset(_G, "CommanderOrders", nil)
    local okAbsent, whyAbsent = CommanderLogistics_RepairWaypoint()
    EQ(whyAbsent, "absent", "D: no Orders, no waypoint")
    HAS(LastPrint(), "nearest repair is Goldshire Smith", "D: ...but the vendor and the line")
    HAS(LastPrint(), "/way #1429 42.00 66.00", "D: ...the /way line")
    EQ(CommanderLogistics_ClearRepairWaypoint(), 0, "D: clearing without Orders is a quiet no-op")
    rawset(_G, "CommanderOrders", keep)
    EQ(CommanderLogistics_ClearRepairWaypoint(), 1, "D: clearing with Orders removes the one waypoint")
    CHECK(#M.errors == 0, "D: no errors", M.errors[1])
end

-- ===========================================================================
-- E  Adjutant's offer
-- ===========================================================================
do
    M.SetPlayer(1429, 0.47, 0.60)
    -- The player has chosen somewhere to go
    local mine = O().Add({ map = 1429, x = 0.30, y = 0.30, title = "My spot", source = "user" })
    CHECK(mine ~= nil, "E: a waypoint of the player's own")
    world.durability = 0.1
    M.Fire("UPDATE_INVENTORY_DURABILITY")
    HAS(BannerText(), "Units require repair: Goldshire Smith, ", "E: the banner names the nearest repair")
    HAS(BannerText(), " yd", "E: ...with its distance")
    Pass(1)
    local marks = O().List({ source = "Logistics" })
    EQ(#marks, 1, "E: ...and marks it")
    EQ(marks[1] and marks[1].temporary, true, "E: ...as a temporary offer")
    EQ(O().Active() and O().Active().uid, mine, "E: the offer never takes the arrow from the player's own")
    -- The player's own waypoint goes: the offer is what is left
    O().Remove(mine)
    Pass(1)
    local active = O().Active()
    EQ(active and active.source, "Logistics", "E: with nothing of the player's, the offer has the arrow")
    -- Mended: the offer is withdrawn
    world.durability = 1
    M.Fire("UPDATE_INVENTORY_DURABILITY")
    Pass(1)
    EQ(#O().List({ source = "Logistics" }), 0, "E: mended gear takes the offer down")

    -- In combat: named on the banner, marked only when the fight ends
    M.SetCombat(true)
    world.durability = 0.1
    M.Fire("UPDATE_INVENTORY_DURABILITY")
    HAS(BannerText(), "Goldshire Smith", "E: in combat the banner still names it")
    Pass(1)
    EQ(#O().List({ source = "Logistics" }), 0, "E: ...but nothing appears mid-fight")
    M.SetCombat(false)
    Pass(1)
    EQ(#O().List({ source = "Logistics" }), 1, "E: the mark lands when combat ends")
    world.durability = 1
    M.Fire("UPDATE_INVENTORY_DURABILITY")
    Pass(1)
    EQ(#O().List({ source = "Logistics" }), 0, "E: (mended)")
    -- Switched off: named, not marked
    CommanderAdjutantDB.RepairWaypoint = false
    world.durability = 0.1
    M.Fire("UPDATE_INVENTORY_DURABILITY")
    Pass(1)
    HAS(BannerText(), "Goldshire Smith", "E: Mark the Nearest Repair off still names it")
    EQ(#O().List({ source = "Logistics" }), 0, "E: ...but marks nothing")
    world.durability = 1
    M.Fire("UPDATE_INVENTORY_DURABILITY")
    CommanderAdjutantDB.RepairWaypoint = true

    -- The offer never ASKS for the arrow. Orders refuses a temporary pin
    -- over a pinned waypoint and over a running route (Store PinFromAdd),
    -- but an offer that asked would still re-pin the arrow away from a
    -- waypoint of yours followed as the closest, and out of a Clear. Each
    -- case: drop the gear, the offer lands, the arrow stays put.
    local function Offer()
        world.durability = 0.1
        M.Fire("UPDATE_INVENTORY_DURABILITY")
        Pass(1)
        EQ(#O().List({ source = "Logistics" }), 1, "E: (the offer is on the map)")
    end
    local function Mend()
        world.durability = 1
        M.Fire("UPDATE_INVENTORY_DURABILITY")
        Pass(1)
    end
    -- A route running (a Quest Log Route Zone, a Tradecraft trip)
    local routeId = O().AddRoute({
        title = "Open quests: Elwynn", source = "QuestLog", key = "open:12", mode = "ORDERED",
        stops = {
            { map = 1429, x = 0.40, y = 0.50, title = "Giver A" },
            { map = 1429, x = 0.50, y = 0.40, title = "Giver B" },
        },
    })
    CHECK(routeId ~= nil, "E: a route is running")
    Pass(1)
    local before = O().Active()
    EQ(before and before.why, "ROUTE", "E: (the arrow follows the route)")
    Offer()
    local after = O().Active()
    EQ(after and after.why, "ROUTE", "E: the offer never takes the arrow from a running route")
    EQ(after and after.title, "Giver A", "E: ...it stays on the route's stop")
    Mend()
    O().RemoveRoute(routeId)
    -- A waypoint of yours the arrow follows as the closest (not pinned)
    local spot = O().Add({ map = 1429, x = 0.60, y = 0.60, title = "My spot", source = "user", setArrow = false })
    Pass(1)
    before = O().Active()
    EQ(before and before.uid, spot, "E: (the arrow follows your mark as the closest)")
    EQ(before and before.why, "CLOSEST", "E: (as the closest, not pinned)")
    Offer()
    after = O().Active()
    EQ(after and after.uid, spot, "E: the offer never takes the arrow from your closest mark")
    EQ(after and after.why, "CLOSEST", "E: ...and pins nothing")
    Mend()
    -- A Clear: the arrow was dismissed, and an offer does not bring it back
    O().ClearArrow()
    Pass(1)
    EQ(O().Active(), nil, "E: (the arrow was cleared)")
    Offer()
    EQ(O().Active(), nil, "E: the offer never undoes a Clear")
    Mend()
    O().Remove(spot)
    -- Nothing of yours at all, and the arrow not cleared: the offer is followed
    O().SetArrow(O().Add({ map = 1429, x = 0.33, y = 0.33, title = "Scratch", source = "user" }))
    O().Remove(O().Active().uid)
    Offer()
    after = O().Active()
    EQ(after and after.source, "Logistics", "E: with nothing of yours, the arrow follows the offer")
    EQ(after and after.why, "CLOSEST", "E: ...as the closest, never pinned")
    Mend()
    -- A temporary offer that is not quiet says "marked", never that the arrow points there
    local okT = CommanderLogistics_RepairWaypoint({ temporary = true })
    EQ(okT, true, "E: a loud temporary offer is placed")
    HAS(LastPrint(), "Waypoint set: Repair: Goldshire Smith", "E: ...and says it was marked, not that it took the arrow")
    CommanderLogistics_ClearRepairWaypoint()

    -- The offer and a request share (Logistics, repair): one record. An
    -- offer you then ask for yourself is yours, so the offer's withdrawal
    -- (mended by a repair bot, a guildmate) leaves it; a repair merchant
    -- still takes it down (review 2026-10-05)
    Offer()
    local okMine, uidMine = CommanderLogistics_RepairWaypoint()
    EQ(okMine, true, "E: asking for the nearest repair over the offer")
    local rec = uidMine and O().Get(uidMine)
    CHECK(rec and not rec.temporary, "E: ...makes the record yours, no longer an offer", rec and tostring(rec.temporary))
    Mend()
    EQ(#O().List({ source = "Logistics" }), 1, "E: mended gear leaves a repair waypoint you asked for")
    OpenMerchant(SMITH_GOLDSHIRE, true, 1429, 0.42, 0.66)
    CloseMerchant()
    Pass(1)
    EQ(#O().List({ source = "Logistics" }), 0, "E: ...a repair merchant takes it down")
    -- The other order: yours first, then the alert. The offer is refused
    -- and your waypoint is left exactly as it was
    okMine, uidMine = CommanderLogistics_RepairWaypoint()
    world.durability = 0.1
    M.Fire("UPDATE_INVENTORY_DURABILITY")
    Pass(1)
    rec = uidMine and O().Get(uidMine)
    CHECK(rec and not rec.temporary, "E: an alert over your own repair waypoint leaves it yours", rec and tostring(rec.temporary))
    EQ(#O().List({ source = "Logistics" }), 1, "E: ...one record still")
    local refusedOk, refusedWhy = CommanderLogistics_RepairWaypoint({ temporary = true, quiet = true })
    CHECK(refusedOk == false and refusedWhy == "yours", "E: ...the offer is refused as yours", tostring(refusedWhy))
    Mend()
    EQ(#O().List({ source = "Logistics" }), 1, "E: ...and mending does not take it down")
    CommanderLogistics_ClearRepairWaypoint()
    CHECK(#M.errors == 0, "E: no errors", M.errors[1])
end

-- ===========================================================================
-- F  the settings pages and /clog repair
-- ===========================================================================
do
    local function FindRow(panel, needle)
        local found
        local function Walk(w)
            for _, c in ipairs(w.__children or {}) do
                if (c.__text and tostring(c.__text):find(needle, 1, true))
                    or (c._keywords and c._keywords:find(needle:lower(), 1, true)) then found = c end
                Walk(c)
            end
        end
        Walk(panel)
        return found
    end
    local logistics, adjutant
    for _, w in ipairs(M.W.widgets) do
        if rawget(w, "_key") == "Logistics" then logistics = w end
        if rawget(w, "_key") == "Adjutant" then adjutant = w end
    end
    CHECK(logistics ~= nil, "F: the Logistics settings page exists")
    CHECK(adjutant ~= nil, "F: the Adjutant settings page exists")
    if logistics then
        CHECK(FindRow(logistics, "Remember Repair Vendors") ~= nil, "F: Logistics offers Remember Repair Vendors")
        local nearest = FindRow(logistics, "Nearest Repair")
        CHECK(nearest ~= nil, "F: ...and a Nearest Repair button")
        CHECK(FindRow(logistics, "Forget Repair Vendors") ~= nil, "F: ...and Forget Repair Vendors")
    end
    if adjutant then
        CHECK(FindRow(adjutant, "Mark the Nearest Repair") ~= nil, "F: Adjutant offers Mark the Nearest Repair")
    end
    -- The settings page's Go buttons are the suite's Commander.UI.GoButton
    -- (Orders D31, review 2026-10-05: they were plain buttons, so Shift- and
    -- Ctrl-click only set a waypoint, never lit "Going", never greyed out)
    local goRepair, goVendor
    local function WalkGo(w)
        for _, c in ipairs(w.__children or {}) do
            local o = rawget(c, "_goOpts")
            if o and o.key == "repair" then goRepair = c end
            if o and o.key == "vendor" then goVendor = c end
            WalkGo(c)
        end
    end
    if logistics then WalkGo(logistics) end
    CHECK(goRepair ~= nil and goVendor ~= nil, "F: Go to Nearest Repair and Go to Nearest Vendor are GoButtons")
    if goRepair and goVendor then
        EQ(goRepair._goOpts.source == "Logistics" and goVendor._goOpts.source, "Logistics", "F: ...owned by Logistics")
        M.SetPlayer(1429, 0.47, 0.60)
        goRepair:Refresh()
        EQ(goRepair:IsEnabled(), true, "F: with a repair vendor known the button is lit")
        M.ClearLog()
        goRepair.__scripts.OnClick(goRepair, "LeftButton")
        local list = O().List({ source = "Logistics" })
        CHECK(#list == 1 and list[1].key == "repair" and not list[1].temporary and list[1].title == "Repair: Goldshire Smith",
            "F: a click is the request /clog repair makes: (Logistics, repair), yours", list[1] and list[1].title)
        EQ(O().Active() and O().Active().uid, list[1] and list[1].uid, "F: ...the arrow on it")
        HAS(LastPrint(), "Waypoint set: Repair: Goldshire Smith", "F: ...worded once by Orders")
        Pass(1)
        goRepair:Refresh()
        EQ(goRepair.__text, "Going to Nearest Repair", "F: ...and the button reads Going while the arrow is there")
        M.SetModifier("CTRL", true)
        goRepair.__scripts.OnClick(goRepair, "LeftButton")
        M.SetModifier("CTRL", false)
        local pop = M.popups[#M.popups]
        EQ(pop and pop.which, "COMMANDER_ORDERS_COPY", "F: Ctrl-click opens Orders' copy box")
        HAS(pop and pop.dialog.editBox.__text, "/way #1429 ", "F: ...with the vendor's /way line")
        local chats = #M.chat
        M.SetModifier("SHIFT", true)
        goVendor.__scripts.OnClick(goVendor, "LeftButton")
        M.SetModifier("SHIFT", false)
        CHECK(#M.chat == chats + 1 and M.chat[#M.chat].text:find("Vendor: ", 1, true),
            "F: Shift-click shares the nearest vendor in chat", M.chat[#M.chat] and M.chat[#M.chat].text)
        EQ(#O().List({ source = "Logistics" }), 1, "F: ...neither gesture sets a waypoint")
        CommanderLogistics_ClearRepairWaypoint()
        -- Nowhere to go from Durotar (no repair learned on Kalimdor): greyed,
        -- the line's own sentence in red
        M.SetPlayer(1411, 0.5, 0.5)
        goRepair:Refresh()
        EQ(goRepair:IsEnabled(), false, "F: with no repair on this continent the button is greyed")
        M.Hover(goRepair)
        HAS(table.concat(M.tooltip, "\n"), "o repair vendor learned on this continent yet", "F: ...its tooltip says why, in Logistics' words")
        M.SetPlayer(1429, 0.47, 0.60)
        goRepair:Refresh()
    end
    M.SetPlayer(1429, 0.47, 0.60)
    local slash = SlashCmdList.COMMANDERUI_LOGISTICS
    CHECK(type(slash) == "function", "F: /clog is registered")
    if slash then
        slash("repair")
        EQ(#O().List({ source = "Logistics" }), 1, "F: /clog repair sets the waypoint")
        CommanderLogistics_ClearRepairWaypoint()
    end
    local n = CommanderLogistics_ForgetRepairVendors()
    CHECK(n >= 4, "F: Forget reports what it forgot", n)
    EQ(CommanderLogistics_RepairVendorCount(), 0, "F: ...and the book is empty")
    HAS(LastPrint(), "forgot", "F: ...and says so")
    CHECK(#M.errors == 0, "F: no errors", M.errors[1])
end

-- ===========================================================================
-- G  the consumer contract: the specs the other modules send, on the real API
-- ===========================================================================
do
    -- Commander_Guide: the engine's own spec, Karazhan's two doors
    LoadAddonFile(ADDONS .. "/Commander_Guide/CommanderGuideData.lua")
    LoadAddonFile(ADDONS .. "/Commander_Guide/CommanderGuideEngine.lua")
    CHECK(#loadErrors == 0, "G: Guide's data and engine load beside Orders", loadErrors[1])
    local D, E = CommanderGuide_Data, CommanderGuide_Engine
    local kara = D and D.RAIDS[1]
    local spec = E and kara and E.EntranceSpec(D, kara, nil)
    CHECK(spec ~= nil, "G: Guide builds Karazhan's spec")
    M.SetPlayer(1430, 0.47, 0.76)              -- Deadwind Pass, by the southern door
    local uid, why = O().Add(spec)
    CHECK(uid ~= nil, "G: the real Orders takes Guide's entrance spec", why)
    local wp = uid and O().Get(uid)
    EQ(wp and wp.alternatives and #wp.alternatives, 2, "G: ...with both doors as alternatives")
    EQ(wp and wp.source, "Guide", "G: ...owned by the Guide")
    EQ(O().Active() and O().Active().uid, uid, "G: ...and it has the arrow")
    Pass(6)
    local view = O().R.View()
    EQ(view.mode, "NAV", "G: the arrow navigates to the entrance")
    local _, pn, pw = M.World(1430, 0.47, 0.76)
    local _, dn, dw = M.World(1430, 0.469, 0.747)
    NEAR(view.distance, math.sqrt((pn - dn) ^ 2 + (pw - dw) ^ 2), 1.0,
        "G: ...to the NEARER door (Orders picks among the alternatives)")
    local again = O().Add(E.EntranceSpec(D, kara, nil))
    EQ(again, uid, "G: a second press is the same waypoint")
    O().Remove(uid)

    -- CommanderOrders.Entrance (the accessor Commander_Guide asks first)
    CHECK(type(O().Entrance) == "function", "G: CommanderOrders.Entrance exists")
    EQ(O().Entrance(350), nil, "G: with no resolver and no client list it answers nil")
    M.SetEntrances(1430, { { name = "Karazhan", position = { x = 0.47, y = 0.75 } } })
    local e = O().Entrance(350)
    CHECK(e and e.map == 1430 and math.abs(e.x - 0.47) < 1e-9, "G: the client's dungeon-entrance list answers",
        e and (tostring(e.map) .. " " .. tostring(e.x)))
    -- One shared answer table, as a resolver backed by static data would hand out
    local door = { map = 1430, x = 0.468, y = 0.73, title = "Karazhan (resolver)" }
    O().RegisterResolver("entrance", function(map)
        if map == 350 then return door end
    end)
    e = O().Entrance(350)
    CHECK(e and math.abs(e.x - 0.468) < 1e-9, "G: a registered resolver answers first")
    e.map = 1
    CHECK(O().Entrance(350).map == 1430 and door.map == 1430, "G: what it hands out is a copy, never the resolver's table")
    EQ(O().Entrance("junk"), nil, "G: nil-safe")
    local s2, via = E.EntranceSpec(D, kara, O().Entrance(350))
    EQ(via, "resolver", "G: Guide takes the resolver's answer")
    CHECK(O().Add(s2) ~= nil, "G: ...and the real Orders takes that spec too")
    -- The suite's normal setup: the Quest Log's resolver answers Questie's
    -- FIRST Karazhan door only (it stops after one). Guide must still hand
    -- Orders both doors, so the arrow takes the nearer one from the south
    door.x, door.y, door.title = 0.467, 0.702, "Karazhan entrance"
    M.SetPlayer(1430, 0.47, 0.76)
    local s3, via3 = E.EntranceSpec(D, kara, O().Entrance(350))
    EQ(via3, "resolver", "G: Questie's first door through the resolver")
    EQ(s3 and s3.alternatives and #s3.alternatives, 2, "G: ...still carries both doors")
    local kuid = O().Add(s3)
    Pass(6)
    view = O().R.View()
    EQ(O().Active() and O().Active().uid, kuid, "G: (the resolver's Karazhan spec has the arrow)")
    NEAR(view.distance, math.sqrt((pn - dn) ^ 2 + (pw - dw) ^ 2), 1.0,
        "G: ...and with the resolver too, the arrow takes the NEARER door")
    O().Remove(kuid)

    -- Commander_Spoils: Back to the farm
    M.SetPlayer(1951, 0.5, 0.5)
    uid, why = O().Add({ map = 1951, x = 0.42, y = 0.31, title = "Farm: Nagrand",
                         source = "Spoils", key = "farm", setArrow = true })
    CHECK(uid ~= nil, "G: the real Orders takes Spoils' farm spec", why)
    EQ(O().Active() and O().Active().uid, uid, "G: ...and points at it")
    EQ(O().Add({ map = 1951, x = 0.40, y = 0.30, title = "Farm: Nagrand",
                 source = "Spoils", key = "farm", setArrow = true }), uid, "G: a new farm moves the same waypoint")

    -- Commander_PartyFrames: Arrow to them (kind "unit")
    M.SetPlayer(1429, 0.47, 0.60)
    M.SetGroup("party", { "Alice", "Bob" })
    M.SetUnit("party1", 1429, 0.50, 0.50)
    M.SetUnit("party2", 1429, 0.44, 0.62)
    uid, why = O().Add({ kind = "unit", unit = "party1", title = "Alice",
                         source = "PartyFrames", key = "follow", setArrow = true })
    CHECK(uid ~= nil, "G: the real Orders takes PartyFrames' follow spec", why)
    EQ(O().Active() and O().Active().uid, uid, "G: ...and the arrow follows")
    Pass(3)
    view = O().R.View()
    EQ(view.mode, "NAV", "G: the arrow navigates to the ally")
    local _, an, aw = M.World(1429, 0.50, 0.50)
    local _, mn, mw = M.World(1429, 0.47, 0.60)
    NEAR(view.distance, math.sqrt((an - mn) ^ 2 + (aw - mw) ^ 2), 1.0, "G: ...at the ally's live distance")
    -- The roster reshuffle path: the same key re-pointed, the arrow not re-taken
    local other = O().Add({ map = 1429, x = 0.3, y = 0.3, title = "Elsewhere", source = "user" })
    local moved = O().Add({ kind = "unit", unit = "party2", title = "Alice",
                            source = "PartyFrames", key = "follow", setArrow = false })
    EQ(moved, uid, "G: a re-pointed follow is the same waypoint")
    EQ(O().Get(uid).unit, "party2", "G: ...on the new token")
    EQ(O().Active() and O().Active().uid, other, "G: ...without taking the arrow back")
    -- Why PartyFrames never asks for a pet or for you
    local refused, reason = O().Add({ kind = "unit", unit = "partypet1", title = "Pet", source = "PartyFrames", key = "follow" })
    EQ(refused, nil, "G: Orders refuses a pet token")
    EQ(reason, "invalid unit", "G: ...as an invalid unit, which PartyFrames filters first")
    refused = O().Add({ kind = "unit", unit = "player", title = "Me", source = "PartyFrames", key = "follow" })
    EQ(refused, nil, "G: ...and the player")
    CHECK(#M.errors == 0, "G: no errors", M.errors[1])
end

-- ===========================================================================
-- H  the whole of Orders: the same flow with its pins and manager loaded
-- ===========================================================================
-- A through G leave Orders' map pins and manager window out, as Orders' own
-- runtime harness does, so a fault in those files cannot hide behind this
-- module's checks. The client loads every file, so one pass with all of them.
do
    Boot({ skipFiles = {} })
    CHECK(#M.loadErrors == 0, "H: every Orders file loads beside Logistics and Adjutant", M.loadErrors[1])
    OpenMerchant(SMITH_GOLDSHIRE, true, 1429, 0.42, 0.66)
    CloseMerchant()
    M.SetPlayer(1429, 0.47, 0.60)
    world.durability = 0.1
    M.Fire("UPDATE_INVENTORY_DURABILITY")
    Pass(3)
    HAS(BannerText(), "Goldshire Smith", "H: the alert names the vendor")
    EQ(#O().List({ source = "Logistics" }), 1, "H: ...and the offer is on the map and the arrow")
    world.durability = 1
    M.Fire("UPDATE_INVENTORY_DURABILITY")
    Pass(1)
    EQ(#O().List({ source = "Logistics" }), 0, "H: ...and gone once mended")
    CHECK(#M.errors == 0, "H: no errors", M.errors[1])
end

-- ===========================================================================
-- I  supply lines through Orders' locator (2.3.0, Orders 3.1)
-- ===========================================================================
-- The locator (CommanderOrdersLocate.lua) loaded: Logistics' learned book is
-- a "townsfolk" resolver for Repair and Vendor, merged with what else answers
-- (here a harness resolver stands in for Questie's lists), the nearest on the
-- landmass wins, the vendor's own spawn is stored instead of the player's
-- spot, and Adjutant's full-bags alert offers the nearest vendor.
do
    Boot({ skipFiles = { CommanderOrdersPins = true, CommanderOrdersUI = true } })
    CHECK(#M.loadErrors == 0, "I: Orders with its locator loads beside Logistics", M.loadErrors[1])
    CHECK(type(O().Locate) == "function", "I: (the locator is in)")
    world.free = 3
    rawset(_G, "C_Container", {
        GetContainerNumSlots = function(bag) return bag == 0 and 16 or 0 end,
        GetContainerNumFreeSlots = function(bag) return bag == 0 and world.free or 0 end,
        GetContainerItemInfo = function() return nil end,
        UseContainerItem = function() end,
    })
    OpenMerchant(SMITH_GOLDSHIRE, true, 1429, 0.42, 0.66)
    CloseMerchant()
    OpenMerchant(SMITH_HELLFIRE, true, 1944, 0.567, 0.375)
    CloseMerchant()

    -- The learned book answers the locator
    local places, why = O().Locate({ townsfolk = "Repair" })
    EQ(type(places) == "table" and #places, 2, "I: the locator's Repair list is the learned book (no Questie here)")
    local goldshire
    for _, p in ipairs(places or {}) do
        if p.title == "Goldshire Smith" then goldshire = p end
    end
    CHECK(goldshire and goldshire.learned == true and goldshire.npc == 90001 and goldshire.map == 1429,
        "I: ...each place named, its npc, learned", goldshire and goldshire.title)
    places = O().Locate({ townsfolk = "Vendor" })
    EQ(type(places) == "table" and #places, 2, "I: a repair vendor is a vendor too")
    places, why = O().Locate({ townsfolk = "Innkeeper" })
    EQ(places, nil, "I: other kinds are not the book's")
    EQ(why, "noquestie", "I: ...and the locator says why")
    CommanderLogisticsDB.EnableLogistics = false
    places = O().Locate({ townsfolk = "Repair" })
    EQ(places, nil, "I: Logistics switched off lends nothing")
    CommanderLogisticsDB.EnableLogistics = true

    -- A second source (Questie's place in the client): merged, nearest wins
    O().RegisterResolver("townsfolk", function(kind)
        if kind == "Repair" or kind == "Vendor" then
            local out = {
                { map = 1429, x = 0.46, y = 0.61, title = "Questie Smith", npc = 90100 },
                { map = 1944, x = 0.40, y = 0.40, title = "Far Smith", npc = 90101 },
            }
            if kind == "Vendor" then out[#out + 1] = { map = 1429, x = 0.47, y = 0.605, title = "Questie Grocer", npc = 90102 } end
            return out
        end
    end)
    M.SetPlayer(1429, 0.47, 0.60)
    local v = CommanderLogistics_NearestRepair()
    EQ(v and v.name, "Questie Smith", "I: the nearest of every known repair, not only the learned ones")
    if v then
        local _, pn, pw = M.World(1429, 0.47, 0.60)
        local _, vn, vw = M.World(1429, 0.46, 0.61)
        NEAR(v.yards, math.sqrt((pn - vn) ^ 2 + (pw - vw) ^ 2), 0.01, "I: ...by straight-line yards")
        EQ(v.zone, "Elwynn Forest", "I: ...named with its zone")
    end
    M.SetPlayer(1944, 0.55, 0.40)
    v = CommanderLogistics_NearestRepair()
    CHECK(v and v.name == "Thrallmar Smith", "I: in Hellfire the Outland ones only", v and v.name)
    M.SetPlayer(1941, 0.5, 0.5)
    v, why = CommanderLogistics_NearestRepair()
    EQ(why, "elsewhere", "I: from Eversong none is near (530, another landmass)")

    -- The waypoint is Orders' GoTo, worded by Orders
    M.SetPlayer(1429, 0.47, 0.60)
    M.ClearLog()
    local ok, uid = CommanderLogistics_RepairWaypoint()
    EQ(ok, true, "I: the repair waypoint is set")
    local wp = uid and O().Get(uid)
    EQ(wp and wp.title, "Repair: Questie Smith", "I: ...at the nearest of all")
    NEAR(wp and wp.x, 0.46, 1e-9, "I: ...where it stands")
    EQ(wp and wp.key, "repair", "I: ...on Logistics' one repair key")
    HAS(LastPrint(), "Waypoint set: Repair: Questie Smith (Elwynn Forest", "I: Orders words it once")

    -- The vendor line: its own key, cleared by any merchant
    local okV, uidV = CommanderLogistics_SupplyWaypoint("Vendor")
    EQ(okV, true, "I: the vendor waypoint is set")
    local wv = uidV and O().Get(uidV)
    EQ(wv and wv.title, "Vendor: Questie Grocer", "I: ...at the nearest vendor of any kind")
    EQ(wv and wv.key, "vendor", "I: ...on its own key")
    CHECK(uidV ~= uid, "I: ...a second waypoint, not the repair one moved")
    v = CommanderLogistics_Nearest("Vendor")
    EQ(v and v.name, "Questie Grocer", "I: CommanderLogistics_Nearest('Vendor') agrees")
    OpenMerchant(GROCER, false)
    CloseMerchant()
    Pass(1)
    EQ(O().Get(uidV), nil, "I: any merchant takes the vendor waypoint down")
    CHECK(O().Get(uid) ~= nil, "I: ...and leaves the repair one to a repair merchant")
    CommanderLogistics_ClearRepairWaypoint()

    -- Learning stores the VENDOR'S spawn when the locator knows it near you
    O().RegisterResolver("npc", function(id)
        if id == 90001 then return { { map = 1429, x = 0.4172, y = 0.6560 } } end
        if id == 90002 then return { { map = 1429, x = 0.30, y = 0.30 } } end
    end)
    OpenMerchant(SMITH_GOLDSHIRE, true, 1429, 0.4165, 0.6551)
    CloseMerchant()
    local rec = Book()["90001"]
    NEAR(rec and rec.x, 0.4172, 1e-9, "I: a learned vendor is stored where its spawn stands")
    NEAR(rec and rec.y, 0.6560, 1e-9, "I: ...x and y")
    EQ(rec and rec.spawn, true, "I: ...and marked as the spawn")
    if rec then
        local _, sn, sw = M.World(1429, 0.4172, 0.6560)
        NEAR(rec.north, sn, 1e-6, "I: ...its world north is the spawn's")
        NEAR(rec.west, sw, 1e-6, "I: ...and its west")
    end
    OpenMerchant(SMITH_STORMWIND, true, 1453, 0.6, 0.7)
    CloseMerchant()
    rec = Book()["90002"]
    NEAR(rec and rec.x, 0.6, 1e-9, "I: a spawn far from you is not this vendor: your spot is kept")
    EQ(rec and rec.spawn, nil, "I: ...unmarked")

    -- Adjutant: full bags name and offer the nearest vendor
    M.SetPlayer(1429, 0.47, 0.60)
    world.free = 0
    M.Fire("BAG_UPDATE_DELAYED")
    Pass(1)
    HAS(BannerText(), "Storage at full capacity: Questie Grocer, ", "I: full bags name the nearest vendor")
    local marks = O().List({ source = "Logistics" })
    EQ(#marks, 1, "I: ...and offer it")
    EQ(marks[1] and marks[1].key, "vendor", "I: ...on the vendor key")
    EQ(marks[1] and marks[1].temporary, true, "I: ...as a temporary offer")
    world.free = 2
    M.Fire("BAG_UPDATE_DELAYED")
    Pass(1)
    EQ(#O().List({ source = "Logistics" }), 0, "I: a free slot takes the offer down")
    M.SetCombat(true)
    world.free = 0
    M.Fire("BAG_UPDATE_DELAYED")
    Pass(1)
    EQ(#O().List({ source = "Logistics" }), 0, "I: in combat nothing is marked")
    M.SetCombat(false)
    Pass(1)
    EQ(#O().List({ source = "Logistics" }), 1, "I: ...it lands when combat ends")
    OpenMerchant(GROCER, false)
    CloseMerchant()
    Pass(1)
    EQ(#O().List({ source = "Logistics" }), 0, "I: opening a merchant takes it down")
    world.free = 2
    M.Fire("BAG_UPDATE_DELAYED")
    CommanderAdjutantDB.VendorWaypoint = false
    world.free = 0
    M.Fire("BAG_UPDATE_DELAYED")
    Pass(1)
    HAS(BannerText(), "Questie Grocer", "I: Mark the Nearest Vendor off still names it")
    EQ(#O().List({ source = "Logistics" }), 0, "I: ...but marks nothing")
    CommanderAdjutantDB.VendorWaypoint = true
    world.free = 2
    M.Fire("BAG_UPDATE_DELAYED")

    -- /clog vendor
    local slash = SlashCmdList.COMMANDERUI_LOGISTICS
    if slash then
        slash("vendor")
        local list = O().List({ source = "Logistics" })
        EQ(#list == 1 and list[1].key, "vendor", "I: /clog vendor sets the vendor waypoint")

        -- The full-bags offer and /clog vendor share (Logistics, vendor):
        -- one record. Yours first, then full bags: the offer is refused and
        -- your waypoint left as it was; a freed slot does not take it down
        -- (review 2026-10-05: it did, from under the arrow)
        local uidMine = list[1] and list[1].uid
        world.free = 0
        M.Fire("BAG_UPDATE_DELAYED")
        Pass(1)
        HAS(BannerText(), "Storage at full capacity: ", "I: (full bags over your own vendor waypoint)")
        local rec = uidMine and O().Get(uidMine)
        CHECK(rec and not rec.temporary, "I: ...your waypoint stays yours, not an offer", rec and tostring(rec.temporary))
        world.free = 2
        M.Fire("BAG_UPDATE_DELAYED")
        Pass(1)
        CHECK(uidMine and O().Get(uidMine) ~= nil, "I: ...and a freed slot leaves it")
        CommanderLogistics_ClearSupplyWaypoint("Vendor")
        -- The offer first, then you ask: the record is yours, the arrow on
        -- it, and a slot freed on the way there leaves it under the arrow
        world.free = 0
        M.Fire("BAG_UPDATE_DELAYED")
        Pass(1)
        list = O().List({ source = "Logistics" })
        EQ(#list == 1 and list[1].temporary, true, "I: (the full-bags offer is on the map)")
        slash("vendor")
        Pass(1)
        list = O().List({ source = "Logistics" })
        CHECK(#list == 1 and not list[1].temporary, "I: /clog vendor over the offer makes it yours", #list)
        uidMine = list[1] and list[1].uid
        EQ(O().Active() and O().Active().uid, uidMine, "I: ...the arrow on it")
        world.free = 1
        M.Fire("BAG_UPDATE_DELAYED")
        Pass(1)
        CHECK(uidMine and O().Get(uidMine) ~= nil, "I: a slot freed on the way leaves the waypoint you asked for")
        EQ(O().Active() and O().Active().uid, uidMine, "I: ...under the arrow")
        OpenMerchant(GROCER, false)
        CloseMerchant()
        Pass(1)
        EQ(#O().List({ source = "Logistics" }), 0, "I: ...and a merchant takes it down")
        -- An offer nobody took over is still withdrawn by a free slot
        world.free = 0
        M.Fire("BAG_UPDATE_DELAYED")
        Pass(1)
        EQ(#O().List({ source = "Logistics" }), 1, "I: (a fresh offer)")
        world.free = 2
        M.Fire("BAG_UPDATE_DELAYED")
        Pass(1)
        EQ(#O().List({ source = "Logistics" }), 0, "I: ...still withdrawn by a free slot")
    end
    CHECK(#M.errors == 0, "I: no errors", M.errors[1])
end

CHECK(#loadErrors == 0, "no load errors anywhere", loadErrors[1])
io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
