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

local SKIP = { CommanderOrdersPins = true, CommanderOrdersUI = true }
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
    HAS(LastPrint(), "the arrow points to Goldshire Smith", "D: one line says so")
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
    HAS(LastPrint(), "Commander Orders is switched off", "D: ...in words")
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
    -- only over a pinned waypoint (Store PinFromAdd), so an offer that asked
    -- re-pinned the arrow away from a running route (StartRoute clears the
    -- pin), from a waypoint of yours followed as the closest, and out of a
    -- Clear. Each case: drop the gear, the offer lands, the arrow stays put.
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
    HAS(LastPrint(), "marked Goldshire Smith", "E: ...and says it was marked, not that it took the arrow")
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
    -- Commander_Guide: the engine's own spec, Karazhan's two doors. Guide is
    -- not committed yet, so its half of this contract runs only where its
    -- files are on disk (the live AddOns folder); a checkout without it
    -- skips those checks and says so. The Entrance accessor, Spoils and
    -- PartyFrames checks below run either way.
    local guideFile = io.open(ADDONS .. "/Commander_Guide/CommanderGuideData.lua", "r")
    if guideFile then guideFile:close() end
    local hasGuide = guideFile ~= nil
    if not hasGuide then
        io.write("SKIP  G: Commander_Guide is not on disk; its entrance checks are skipped\n")
    end
    local _, D, E, kara, pn, pw, dn, dw
    local uid, why, view
    if hasGuide then
        LoadAddonFile(ADDONS .. "/Commander_Guide/CommanderGuideData.lua")
        LoadAddonFile(ADDONS .. "/Commander_Guide/CommanderGuideEngine.lua")
        CHECK(#loadErrors == 0, "G: Guide's data and engine load beside Orders", loadErrors[1])
        D, E = CommanderGuide_Data, CommanderGuide_Engine
        kara = D and D.RAIDS[1]
        local spec = E and kara and E.EntranceSpec(D, kara, nil)
        CHECK(spec ~= nil, "G: Guide builds Karazhan's spec")
        M.SetPlayer(1430, 0.47, 0.76)              -- Deadwind Pass, by the southern door
        uid, why = O().Add(spec)
        CHECK(uid ~= nil, "G: the real Orders takes Guide's entrance spec", why)
        local wp = uid and O().Get(uid)
        EQ(wp and wp.alternatives and #wp.alternatives, 2, "G: ...with both doors as alternatives")
        EQ(wp and wp.source, "Guide", "G: ...owned by the Guide")
        EQ(O().Active() and O().Active().uid, uid, "G: ...and it has the arrow")
        Pass(6)
        view = O().R.View()
        EQ(view.mode, "NAV", "G: the arrow navigates to the entrance")
        _, pn, pw = M.World(1430, 0.47, 0.76)
        _, dn, dw = M.World(1430, 0.469, 0.747)
        NEAR(view.distance, math.sqrt((pn - dn) ^ 2 + (pw - dw) ^ 2), 1.0,
            "G: ...to the NEARER door (Orders picks among the alternatives)")
        local again = O().Add(E.EntranceSpec(D, kara, nil))
        EQ(again, uid, "G: a second press is the same waypoint")
        O().Remove(uid)
    end

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
    if hasGuide then
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
    end

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

CHECK(#loadErrors == 0, "no load errors anywhere", loadErrors[1])
io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
