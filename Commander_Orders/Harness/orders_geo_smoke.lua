-- Commander Orders: geometry smoke test (luajit).
--
--     luajit Commander_Orders/Harness/orders_geo_smoke.lua
--     ORDERS_GEO=/tmp/mutant.lua luajit Commander_Orders/Harness/orders_geo_smoke.lua
--
-- Loads CommanderOrdersGeo.lua ALONE into a SEALED environment: the only
-- globals it can read are Lua's own (math, string, table and a few base
-- functions) and its own CommanderOrders table; reading anything else raises,
-- and so does writing any global other than CommanderOrders. Every check
-- below runs through that sealed copy, so a client call slipped into a code
-- path would fail the run, not merely a grep.
--
-- The world it is driven against is real data: the map tree and the world
-- rectangles below are this build's UiMap and UiMapAssignment DB2 rows
-- (wago.tools, build 2.5.6.69795; every Cosmic/World/Continent/Zone map plus
-- the dungeon and orphan maps the rules name), and the env functions model
-- GetWorldPosFromMapPos, GetMapRectOnMap and GetMapInfoAtPosition on them.
--
-- Sections:
--   A  purity: the sealed load, the published API, nothing else written
--   B  distance and bearing in all four quadrants and the four diagonals
--   C  the D1 regression: Goldshire to Northshire on Elwynn's real rectangle
--      is ~582 yd at ~339 deg (the transposed pairing gives ~12,952 yd)
--   D  relative angle and alignment: wrap at +-pi, multiples of 2pi
--   E  landmass: continent walk, caching, the 530 traps (Eversong vs
--      Hellfire, Ghostlands vs Eastern Plaguelands), dungeons, battlegrounds
--   F  ToWorld: vector and number envs, throwing envs, no world data
--   G  projection: round trips up and down, across siblings, world-exact
--   H  ZoneAt: continent and world clicks, ocean, self, refusals, and a grid
--      proving every answer lands on the same world point as the click
--   I  minimap: the diameter table, radius, indoor rule, placement round
--      and square, rotation, the 0.9 rim, edge angles, corner shapes
--   J  filters: the angle follower (no wrap jump, no overshoot) and the ETA
--   K  formats: distance, ETA, coordinates, /way lines, folded names
--   L  the zone index and matcher: tiers, aliases, what is left out
--   M  the /way grammar table, incl. TomTom B12, B13, B18 and B23 fixed
--   N  round trips: WayLine -> ParseWay, and plain-ASCII text everywhere

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
-- ORDERS_GEO=/path/to/copy.lua runs the checks against a mutated copy
local GEO_FILE = os.getenv("ORDERS_GEO") or (ADDONS .. "/Commander_Orders/CommanderOrdersGeo.lua")

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
local function NEAR(actual, expected, eps, label)
    CHECK(type(actual) == "number" and math.abs(actual - expected) <= eps, label,
        "got " .. tostring(actual) .. ", want " .. tostring(expected) .. " +- " .. tostring(eps))
end
-- Call fn and answer its first result, or the string "RAISED" if it threw:
-- a Geo that lets a client error escape fails a check instead of the run
local function SAFE(fn, ...)
    local ok, a = pcall(fn, ...)
    if not ok then return "RAISED" end
    return a
end
local function Has(s, needle)
    return type(s) == "string" and s:find(needle, 1, true) ~= nil
end
local function Finish()
    io.write(string.format("%d checks, %d failures\n", checks, fails))
    os.exit(fails == 0 and 0 or 1)
end

local PI = math.pi
local DEG = 180 / PI

-- ===========================================================================
-- A: load Geo into a sealed environment
-- ===========================================================================
local ALLOWED = {
    pairs = pairs, ipairs = ipairs, next = next, type = type, select = select,
    tonumber = tonumber, tostring = tostring, pcall = pcall, setmetatable = setmetatable,
    math = math, string = string, table = table,
}
local sealed = {}
for name, value in pairs(ALLOWED) do sealed[name] = value end
local reads, writes = {}, {}
setmetatable(sealed, {
    __index = function(_, name)
        if name == "CommanderOrders" then return nil end
        reads[#reads + 1] = name
        error("Geo read the global '" .. tostring(name) .. "'", 2)
    end,
    __newindex = function(t, name, value)
        if name ~= "CommanderOrders" then
            writes[#writes + 1] = name
            error("Geo wrote the global '" .. tostring(name) .. "'", 2)
        end
        rawset(t, name, value)
    end,
})

local chunk, loadErr = loadfile(GEO_FILE)
CHECK(chunk ~= nil, "A: Geo file loads", loadErr)
if not chunk then Finish() end
setfenv(chunk, sealed)
local okLoad, runErr = pcall(chunk)
CHECK(okLoad, "A: Geo main chunk runs with no WoW globals", runErr)
EQ(#reads, 0, "A: no unknown global read at load")
EQ(#writes, 0, "A: no global written but CommanderOrders")
local O = rawget(sealed, "CommanderOrders")
CHECK(type(O) == "table", "A: Geo creates the CommanderOrders table")
local G = O and O.Geo
CHECK(type(G) == "table", "A: Geo publishes CommanderOrders.Geo")
if type(G) ~= "table" then Finish() end

local SPEC_API = {
    "Distance", "Bearing", "Relative", "Continent", "SameLandmass", "ToWorld", "ProjectToMap",
    "ZoneAt", "MinimapPlace", "AngleFilter", "EtaFilter", "FormatDistance", "FormatEta",
    "FormatCoords", "WayLine", "ParseWay", "FoldName", "Alignment",
}
for _, name in ipairs(SPEC_API) do
    EQ(type(G[name]), "function", "A: SPEC function G." .. name)
end
EQ(type(G.MINIMAP_DIAMETERS), "table", "A: SPEC table G.MINIMAP_DIAMETERS")
for _, name in ipairs({ "Normalize", "CheckPosition", "MapDistance", "Instance", "Landmass", "ClearCache",
        "MinimapRadius", "MinimapIndoors", "EtaReset", "ZoneIndex", "MatchZone", "MakeResolver", "WayUsage" }) do
    EQ(type(G[name]), "function", "A: helper G." .. name)
end

-- Re-running the chunk keeps the same Geo table (a second TOC load is harmless)
local sameG = G
local okAgain = pcall(chunk)
CHECK(okAgain and rawget(sealed, "CommanderOrders").Geo == sameG, "A: a second load keeps the Geo table")

-- ===========================================================================
-- The world: UiMap + UiMapAssignment rows of build 2.5.6.69795
-- ===========================================================================
-- MAPS: id = { name, Enum.UIMapType, parentUiMapID }
local MAPS = {
    [233] = { "Zul'Gurub", 6, 1434 },
    [234] = { "Dire Maul", 6, 1444 },
    [235] = { "Dire Maul", 4, 1444 },
    [274] = { "Old Hillsbrad Foothills", 6, 1446 },
    [332] = { "Serpentshrine Cavern", 4, 1946 },
    [334] = { "Tempest Keep", 4, 1953 },
    [337] = { "Zul'Gurub", 6, 1434 },
    [347] = { "Hellfire Ramparts", 4, 1944 },
    [350] = { "Karazhan", 4, 1430 },
    [946] = { "Cosmic", 0, 0 },
    [947] = { "Azeroth", 1, 946 },
    [987] = { "Outland", 2, 0 },
    [1411] = { "Durotar", 3, 1414 },
    [1412] = { "Mulgore", 3, 1414 },
    [1413] = { "The Barrens", 3, 1414 },
    [1414] = { "Kalimdor", 2, 947 },
    [1415] = { "Eastern Kingdoms", 2, 947 },
    [1416] = { "Alterac Mountains", 3, 1415 },
    [1417] = { "Arathi Highlands", 3, 1415 },
    [1418] = { "Badlands", 3, 1415 },
    [1419] = { "Blasted Lands", 3, 1415 },
    [1420] = { "Tirisfal Glades", 3, 1415 },
    [1421] = { "Silverpine Forest", 3, 1415 },
    [1422] = { "Western Plaguelands", 3, 1415 },
    [1423] = { "Eastern Plaguelands", 3, 1415 },
    [1424] = { "Hillsbrad Foothills", 3, 1415 },
    [1425] = { "The Hinterlands", 3, 1415 },
    [1426] = { "Dun Morogh", 3, 1415 },
    [1427] = { "Searing Gorge", 3, 1415 },
    [1428] = { "Burning Steppes", 3, 1415 },
    [1429] = { "Elwynn Forest", 3, 1415 },
    [1430] = { "Deadwind Pass", 3, 1415 },
    [1431] = { "Duskwood", 3, 1415 },
    [1432] = { "Loch Modan", 3, 1415 },
    [1433] = { "Redridge Mountains", 3, 1415 },
    [1434] = { "Stranglethorn Vale", 3, 1415 },
    [1435] = { "Swamp of Sorrows", 3, 1415 },
    [1436] = { "Westfall", 3, 1415 },
    [1437] = { "Wetlands", 3, 1415 },
    [1438] = { "Teldrassil", 3, 1414 },
    [1439] = { "Darkshore", 3, 1414 },
    [1440] = { "Ashenvale", 3, 1414 },
    [1441] = { "Thousand Needles", 3, 1414 },
    [1442] = { "Stonetalon Mountains", 3, 1414 },
    [1443] = { "Desolace", 3, 1414 },
    [1444] = { "Feralas", 3, 1414 },
    [1445] = { "Dustwallow Marsh", 3, 1414 },
    [1446] = { "Tanaris", 3, 1414 },
    [1447] = { "Azshara", 3, 1414 },
    [1448] = { "Felwood", 3, 1414 },
    [1449] = { "Un'Goro Crater", 3, 1414 },
    [1450] = { "Moonglade", 3, 1414 },
    [1451] = { "Silithus", 3, 1414 },
    [1452] = { "Winterspring", 3, 1414 },
    [1453] = { "Stormwind City", 3, 1415 },
    [1454] = { "Orgrimmar", 3, 1414 },
    [1455] = { "Ironforge", 3, 1415 },
    [1456] = { "Thunder Bluff", 3, 1414 },
    [1457] = { "Darnassus", 3, 1414 },
    [1458] = { "Undercity", 3, 1415 },
    [1459] = { "Alterac Valley", 3, 947 },
    [1460] = { "Warsong Gulch", 3, 947 },
    [1461] = { "Arathi Basin", 3, 947 },
    [1463] = { "Eastern Kingdoms", 2, 0 },
    [1464] = { "Kalimdor", 2, 0 },
    [1554] = { "Serpentshrine Cavern", 4, 1946 },
    [1555] = { "Tempest Keep", 4, 1953 },
    [1941] = { "Eversong Woods", 3, 1415 },
    [1942] = { "Ghostlands", 3, 1415 },
    [1943] = { "Azuremyst Isle", 3, 1414 },
    [1944] = { "Hellfire Peninsula", 3, 1945 },
    [1945] = { "Outland", 2, 946 },
    [1946] = { "Zangarmarsh", 3, 1945 },
    [1947] = { "The Exodar", 3, 1414 },
    [1948] = { "Shadowmoon Valley", 3, 1945 },
    [1949] = { "Blade's Edge Mountains", 3, 1945 },
    [1950] = { "Bloodmyst Isle", 3, 1414 },
    [1951] = { "Nagrand", 3, 1945 },
    [1952] = { "Terokkar Forest", 3, 1945 },
    [1953] = { "Netherstorm", 3, 1945 },
    [1954] = { "Silvermoon City", 3, 1415 },
    [1955] = { "Shattrath City", 3, 1945 },
    [1956] = { "Eye of the Storm", 3, 1953 },
    [1957] = { "Isle of Quel'Danas", 3, 1415 },
}
-- uiMap = { { instance, Nmin, Wmin, Nmax, Wmax, u0, v0, u1, v1 }, ... } in OrderIndex order
local ROWS = {
    [233] = { { 309, -12560.416, -2570.833, -11308.333, -693.75, 0, 0, 1, 1 } },
    [234] = { { 429, 0, 0, 0, 0, 0, 0, 1, 1 } },
    [235] = { { 429, 200, -387.5, 1050, 887.5, 0, 0, 1, 1 } },
    [274] = { { 560, 1572.917, -477.083, 3127.083, 1854.167, 0, 0, 1, 1 } },
    [332] = { { 548, -400, -1362.5, 650.002, 212.502, 0, 0, 1, 1 } },
    [334] = { { 550, -100, -787.5, 950, 787.5, 0, 0, 1, 1 } },
    [347] = { { 543, -1492.48, 1294.72, -1029.44, 1989.28, 0, 0, 1, 1 } },
    [350] = { { 532, -11189.6, -2225.024, -10822.9, -1674.976, 0, 0, 1, 1 } },
    [947] = { { 1, -12800, -9600, 12266.7, 6933.3, 0.0399, 0.0855, 0.4083, 0.9234 }, { 0, -16000, -7466.7, 6933.3, 8000, 0.5523, 0.1526, 0.8984, 0.9224 }, { 530, -6933.3, -15466.7, 533.3, -9066.7, 0.0502, 0.3398, 0.1422, 0.4756 }, { 530, 4800, -11200, 13866.7, -4266.7, 0.8714, 0.2439, 0.983, 0.4251 } },
    [987] = { { 530, -5867, -1600, 6400, 10670, 0, 0, 1, 1 } },
    [1411] = { { 1, -1716.667, -7250, 1808.333, -1962.5, 0, 0, 1, 1 } },
    [1412] = { { 1, -3697.917, -3089.583, -272.917, 2047.917, 0, 0, 1, 1 } },
    [1413] = { { 1, -5143.75, -7510.417, 1612.5, 2622.917, 0, 0, 1, 1 } },
    [1414] = { { 1, -11733.3, -19733.211, 12799.9, 17066.6, 0, 0, 1, 1 }, { 530, -6933.33, -16000, 533.33, -8000, 0.202898, 0.08, 0.42029, 0.39 } },
    [1415] = { { 0, -15973.344, -22569.211, 11176.344, 18171.971, 0, 0, 1, 1 }, { 530, 4800, -10133.3, 16000, -2666.67, 0.45258, -0.08927, 0.6385, 0.323258 } },
    [1416] = { { 0, -366.667, -2016.667, 1500, 783.333, 0, 0, 1, 1 } },
    [1417] = { { 0, -2533.333, -4466.667, -133.333, -866.667, 0, 0, 1, 1 } },
    [1418] = { { 0, -7547.917, -4566.667, -5889.583, -2079.167, 0, 0, 1, 1 } },
    [1419] = { { 0, -12800, -4591.667, -10566.666, -1241.667, 0, 0, 1, 1 } },
    [1420] = { { 0, 825, -1485.417, 3837.5, 3033.333, 0, 0, 1, 1 } },
    [1421] = { { 0, -1133.333, -750, 1666.667, 3450, 0, 0, 1, 1 } },
    [1422] = { { 0, 500, -3883.333, 3366.667, 416.667, 0, 0, 1, 1 } },
    [1423] = { { 0, 1218.75, -6056.25, 3800, -2185.417, 0, 0, 1, 1 } },
    [1424] = { { 0, -1733.333, -2133.333, 400, 1066.667, 0, 0, 1, 1 } },
    [1425] = { { 0, -1100, -5425, 1466.667, -1575, 0, 0, 1, 1 } },
    [1426] = { { 0, -7160.417, -3122.917, -3877.083, 1802.083, 0, 0, 1, 1 } },
    [1427] = { { 0, -7587.5, -2554.167, -6100, -322.917, 0, 0, 1, 1 } },
    [1428] = { { 0, -8983.333, -3195.833, -7031.25, -266.667, 0, 0, 1, 1 } },
    [1429] = { { 0, -10254.166, -1935.417, -7939.583, 1535.417, 0, 0, 1, 1 } },
    [1430] = { { 0, -11533.333, -3333.333, -9866.666, -833.333, 0, 0, 1, 1 } },
    [1431] = { { 0, -11516.666, -1866.667, -9716.666, 833.333, 0, 0, 1, 1 } },
    [1432] = { { 0, -6327.083, -4752.083, -4487.5, -1993.75, 0, 0, 1, 1 } },
    [1433] = { { 0, -10022.916, -3741.667, -8575, -1570.833, 0, 0, 1, 1 } },
    [1434] = { { 0, -15422.916, -4160.417, -11168.75, 2220.833, 0, 0, 1, 1 } },
    [1435] = { { 0, -11150, -4516.667, -9620.833, -2222.917, 0, 0, 1, 1 } },
    [1436] = { { 0, -11733.333, -483.333, -9400, 3016.667, 0, 0, 1, 1 } },
    [1437] = { { 0, -4904.167, -4525, -2147.917, -389.583, 0, 0, 1, 1 } },
    [1438] = { { 1, 8437.5, -1277.083, 11831.25, 3814.583, 0, 0, 1, 1 } },
    [1439] = { { 1, 3966.667, -3608.333, 8333.333, 2941.667, 0, 0, 1, 1 } },
    [1440] = { { 1, 829.167, -4066.667, 4672.917, 1700, 0, 0, 1, 1 } },
    [1441] = { { 1, -6900, -4833.333, -3966.667, -433.333, 0, 0, 1, 1 } },
    [1442] = { { 1, -339.583, -1637.5, 2916.667, 3245.833, 0, 0, 1, 1 } },
    [1443] = { { 1, -2545.833, -262.5, 452.083, 4233.333, 0, 0, 1, 1 } },
    [1444] = { { 1, -7000, -1508.333, -2366.667, 5441.667, 0, 0, 1, 1 } },
    [1445] = { { 1, -5533.333, -6225, -2033.333, -975, 0, 0, 1, 1 } },
    [1446] = { { 1, -10475, -7118.75, -5875, -218.75, 0, 0, 1, 1 } },
    [1447] = { { 1, 1960.417, -8347.916, 5341.667, -3277.083, 0, 0, 1, 1 } },
    [1448] = { { 1, 3300, -4108.333, 7133.333, 1641.667, 0, 0, 1, 1 } },
    [1449] = { { 1, -8433.333, -3166.667, -5966.667, 533.333, 0, 0, 1, 1 } },
    [1450] = { { 1, 6952.083, -3689.583, 8491.666, -1381.25, 0, 0, 1, 1 } },
    [1451] = { { 1, -8281.25, -945.834, -5958.334, 2537.5, 0, 0, 1, 1 } },
    [1452] = { { 1, 3800, -7416.667, 8533.333, -316.667, 0, 0, 1, 1 } },
    [1453] = { { 0, -9175.205, 36.701, -8278.851, 1380.971, 0, 0, 1, 1 } },
    [1454] = { { 1, 1338.461, -5083.206, 2273.877, -3680.601, 0, 0, 1, 1 } },
    [1455] = { { 0, -5096.846, -1504.216, -4569.241, -713.591, 0, 0, 1, 1 } },
    [1456] = { { 1, -1545.833, -527.083, -850, 516.667, 0, 0, 1, 1 } },
    [1457] = { { 1, 9532.587, 1880.03, 10238.316, 2938.363, 0, 0, 1, 1 } },
    [1458] = { { 0, 1237.841, -86.182, 1877.945, 873.193, 0, 0, 1, 1 } },
    [1459] = { { 30, -1739.583, -2456.25, 1085.417, 1781.25, 0, 0, 1, 1 } },
    [1460] = { { 489, 862.5, 895.833, 1627.083, 2041.667, 0, 0, 1, 1 } },
    [1461] = { { 529, 337.5, 102.083, 1508.333, 1858.333, 0, 0, 1, 1 } },
    [1463] = { { 0, -16530, -16530, 12270, 12270, 0, 0, 1, 1 }, { 530, 4800, -11200, 13866.7, -4266.7, 0.4962, 0.0304, 0.7234, 0.3486 } },
    [1464] = { { 1, -11870, -13370, 12470, 10970, 0, 0, 1, 1 }, { 530, -6933.3, -15466.7, 533.3, -9066.7, 0.1002, 0.0838, 0.3667, 0.3768 } },
    [1941] = { { 530, 7758.333, -9412.5, 11041.666, -4487.5, 0, 0, 1, 1 } },
    [1942] = { { 530, 6066.667, -8583.333, 8266.666, -5283.333, 0, 0, 1, 1 } },
    [1943] = { { 530, -5508.333, -14570.833, -2793.75, -10500, 0, 0, 1, 1 } },
    [1944] = { { 530, -1962.5, 375, 1481.25, 5539.583, 0, 0, 1, 1 } },
    [1945] = { { 530, -5821.359, -4468.039, 5821.359, 12996.039, 0, 0, 1, 1 } },
    [1946] = { { 530, -1416.667, 4447.917, 1935.417, 9475, 0, 0, 1, 1 } },
    [1947] = { { 530, -4314.371, -12123.138, -3609.683, -11066.367, 0, 0, 1, 1 } },
    [1948] = { { 530, -5614.583, -1275, -1947.917, 4225, 0, 0, 1, 1 } },
    [1949] = { { 530, 791.667, 3420.833, 4408.333, 8845.833, 0, 0, 1, 1 } },
    [1950] = { { 530, -2933.333, -13337.499, -758.333, -10075, 0, 0, 1, 1 } },
    [1951] = { { 530, -3641.667, 4770.833, 41.667, 10295.833, 0, 0, 1, 1 } },
    [1952] = { { 530, -4600, 1683.333, -1000, 7083.333, 0, 0, 1, 1 } },
    [1953] = { { 530, 1739.583, -91.667, 5456.25, 5483.333, 0, 0, 1, 1 } },
    [1954] = { { 530, 9346.938, -7612.208, 10153.709, -6400.75, 0, 0, 1, 1 } },
    [1955] = { { 530, -2344.788, 4829.009, -1473.954, 6135.259, 0, 0, 1, 1 } },
    [1956] = { { 566, 1404.167, 389.583, 2918.75, 2660.417, 0, 0, 1, 1 } },
    [1957] = { { 530, 11350, -8629.166, 13568.749, -5302.083, 0, 0, 1, 1 } },
}

local function MapInfoOf(id)
    local m = MAPS[id]
    if not m then return nil end
    return { mapID = id, name = m[1], mapType = m[2], parentMapID = m[3] }
end

local function IsAncestor(top, child)
    local id, depth = child, 0
    while id and id ~= 0 and depth < 20 do
        if id == top then return true end
        id = MAPS[id] and MAPS[id][3]
        depth = depth + 1
    end
    return false
end

-- A row is { instance, Nmin, Wmin, Nmax, Wmax, u0, v0, u1, v1 }: world X
-- grows north and Y grows west, map x runs with -west and map y with -north.
local function RowWorld(row, x, y)
    local north = row[4] - (y - row[7]) / (row[9] - row[7]) * (row[4] - row[2])
    local west = row[5] - (x - row[6]) / (row[8] - row[6]) * (row[5] - row[3])
    return row[1], north, west
end
local function RowUI(row, north, west)
    return row[6] + (row[5] - west) / (row[5] - row[3]) * (row[8] - row[6]),
        row[7] + (row[4] - north) / (row[4] - row[2]) * (row[9] - row[7])
end
local function InUI(row, x, y)
    return x >= row[6] and x <= row[8] and y >= row[7] and y <= row[9]
end
local function InWorld(row, inst, north, west)
    return row[1] == inst and north >= row[2] and north <= row[4] and west >= row[3] and west <= row[5]
end

-- GetWorldPosFromMapPos: the last row (highest OrderIndex) whose UI square holds the point
local function FixtureWorld(map, x, y)
    local rows = ROWS[map]
    if not rows then return nil end
    for i = #rows, 1, -1 do
        if InUI(rows[i], x, y) then return RowWorld(rows[i], x, y) end
    end
    return nil
end

-- GetMapRectOnMap: the child's main row, through the ancestor's row of the same instance
local function FixtureRect(child, top)
    if not IsAncestor(top, child) or child == top then return nil end
    local crow = ROWS[child] and ROWS[child][1]
    local trows = ROWS[top]
    if not crow or not trows then return nil end
    local cn, cw = (crow[2] + crow[4]) / 2, (crow[3] + crow[5]) / 2
    for i = #trows, 1, -1 do
        local t = trows[i]
        if InWorld(t, crow[1], cn, cw) then
            local left, topY = RowUI(t, crow[4], crow[5])
            local right, bottom = RowUI(t, crow[2], crow[3])
            return left, right, topY, bottom
        end
    end
    return nil
end

-- GetMapInfoAtPosition: the smallest direct child whose world region holds the point
local function FixtureInfoAt(map, x, y)
    local inst, n, w = FixtureWorld(map, x, y)
    if not inst then return nil end
    local best, bestArea
    for id, m in pairs(MAPS) do
        if m[3] == map and m[2] >= 1 and m[2] <= 3 and ROWS[id] then
            for _, row in ipairs(ROWS[id]) do
                if InWorld(row, inst, n, w) then
                    local area = (row[4] - row[2]) * (row[5] - row[3])
                    if not best or area < bestArea then best, bestArea = id, area end
                end
            end
        end
    end
    return best and MapInfoOf(best) or nil
end

local function FixtureChildren(id)
    local kids = {}
    for kid, m in pairs(MAPS) do
        if m[3] == id then kids[#kids + 1] = MapInfoOf(kid) end
    end
    table.sort(kids, function(a, b) return a.mapID < b.mapID end)
    return kids
end

-- The env the runtime would build, on the fixture. worldPos answers the way
-- C_Map.GetWorldPosFromMapPos does: instance, then a vector (.x = north).
local function NewEnv()
    local calls = { mapInfo = 0, worldPos = 0, rectOnMap = 0, mapInfoAtPosition = 0, mapChildren = 0 }
    local env = { calls = calls }
    env.mapInfo = function(id) calls.mapInfo = calls.mapInfo + 1; return MapInfoOf(id) end
    env.worldPos = function(map, x, y)
        calls.worldPos = calls.worldPos + 1
        local inst, n, w = FixtureWorld(map, x, y)
        if not inst then return nil end
        return inst, { x = n, y = w }
    end
    env.rectOnMap = function(child, top) calls.rectOnMap = calls.rectOnMap + 1; return FixtureRect(child, top) end
    env.mapInfoAtPosition = function(map, x, y)
        calls.mapInfoAtPosition = calls.mapInfoAtPosition + 1
        return FixtureInfoAt(map, x, y)
    end
    env.mapChildren = function(id) calls.mapChildren = calls.mapChildren + 1; return FixtureChildren(id) end
    return env
end
local env = NewEnv()

-- An env whose every function throws, and one with nothing in it
local function Boom() error("client said no") end
local boomEnv = { mapInfo = Boom, worldPos = Boom, rectOnMap = Boom, mapInfoAtPosition = Boom, mapChildren = Boom }
local emptyEnv = {}

-- Fixture sanity (so a failure below is about Geo, not the data)
CHECK(MAPS[1429] and MAPS[1429][1] == "Elwynn Forest" and ROWS[1429], "fixture: Elwynn is present")
CHECK(ROWS[1554] == nil and ROWS[946] == nil, "fixture: SSC 1554 and Cosmic have no world data")
EQ(#ROWS[1415], 2, "fixture: Eastern Kingdoms holds two frames (0 and the 530 sub-rectangle)")

-- Each section below runs in its own do-block: a main chunk is held to 200
-- locals (luajit and the client alike). These are what the sections hand on.
local gN, gW, tN, tW, ekx, eky, evx, evy, index, resolver

-- ===========================================================================
-- B: distance and bearing
-- ===========================================================================
do
NEAR(G.Distance(0, 0, 3, 4), 5, 1e-12, "B: 3-4-5")
NEAR(G.Distance(100, -50, 100, -50), 0, 1e-12, "B: same point is 0")
NEAR(G.Distance(10, 20, -30, 50), G.Distance(-30, 50, 10, 20), 1e-12, "B: distance is symmetric")
EQ(G.Distance(nil, 0, 1, 1), nil, "B: nil input gives nil")
EQ(G.Distance(0 / 0, 0, 1, 1), nil, "B: NaN input gives nil")
EQ(G.Distance(math.huge, 0, 1, 1), nil, "B: infinite input gives nil")

local BEARINGS = {
    -- dNorth, dWest, expected radians (counter-clockwise from north), label
    { 100, 0, 0, "due north" },
    { 0, 100, PI / 2, "due west" },
    { -100, 0, PI, "due south" },
    { 0, -100, 3 * PI / 2, "due east" },
    { 100, 100, PI / 4, "north-west" },
    { -100, 100, 3 * PI / 4, "south-west" },
    { -100, -100, 5 * PI / 4, "south-east" },
    { 100, -100, 7 * PI / 4, "north-east" },
}
for _, b in ipairs(BEARINGS) do
    NEAR(G.Bearing(500, -200, 500 + b[1], -200 + b[2]), b[3], 1e-12, "B: bearing " .. b[4])
end
local inRange = true
for i = 0, 71 do
    local a = i * 5 / DEG
    local bb = G.Bearing(0, 0, math.cos(a) * 50, math.sin(a) * 50)
    if not (bb and bb >= 0 and bb < 2 * PI and math.abs(bb - a) < 1e-9) then inRange = false end
end
CHECK(inRange, "B: bearing sweeps 0..355 deg in [0, 2pi) and matches the angle")
EQ(G.Bearing(1, 1, 1, 1), 0, "B: coincident points bear 0, not NaN")
EQ(G.Bearing(nil, 1, 1, 1), nil, "B: nil bearing input gives nil")

end

-- ===========================================================================
-- C: the D1 regression, Goldshire -> Northshire on Elwynn's real rectangle
-- ===========================================================================
do
-- Elwynn (uiMap 1429): north -10254.17..-7939.58, west -1935.42..1535.42
-- (UiMapAssignment 64400). A synthetic env that answers with numbers, not a
-- vector, so both env shapes are exercised.
local ELWYNN = ROWS[1429][1]
local elwynnEnv = {
    worldPos = function(map, x, y)
        if map ~= 1429 then return nil end
        return RowWorld(ELWYNN, x, y)
    end,
}
local gi
gi, gN, gW = G.ToWorld(elwynnEnv, 1429, 0.42, 0.655)
local ni, nN, nW = G.ToWorld(elwynnEnv, 1429, 0.48, 0.42)
EQ(gi, 0, "C: Goldshire is on instance 0")
NEAR(gN, -9455.6, 0.5, "C: Goldshire north (server X) is -9455.6")
NEAR(gW, 77.7, 0.5, "C: Goldshire west (server Y) is 77.7")
NEAR(nN, -8911.7, 0.5, "C: Northshire north is -8911.7")
NEAR(nW, -130.6, 0.5, "C: Northshire west is -130.6")
local d1 = G.Distance(gN, gW, nN, nW)
NEAR(d1, 582.4, 1, "C: Goldshire to Northshire is ~582 yd")
local b1 = G.Bearing(gN, gW, nN, nW)
NEAR(b1 * DEG, 339.0, 0.5, "C: Northshire bears ~339 deg (21 deg east of north)")
-- What Orders 2.1 computed: UnitPosition read as (py, px), so worldX - px paired
-- a north coordinate with a west one
local py, px = gN, gW
local bad = math.sqrt((nN - px) ^ 2 + (nW - py) ^ 2)
NEAR(bad, 12952, 5, "C: the transposed pairing gives the reported 12,952 yd")
CHECK(math.abs(bad - d1) > 10000, "C: the regression distinguishes the two pairings")
local rel1 = G.Relative(b1, 0)
NEAR(rel1 * DEG, -21.0, 0.5, "C: facing north, the arrow turns 21 deg clockwise (right)")
NEAR(G.Distance(gN, gW, gN, gW), 0, 1e-9, "C: standing on the target reads 0 yd")
-- the same walk through the full fixture env (vector-returning worldPos)
local fi, fN, fW = G.ToWorld(env, 1429, 0.42, 0.655)
CHECK(fi == 0 and math.abs(fN - gN) < 1e-9 and math.abs(fW - gW) < 1e-9, "C: vector env agrees with number env")
NEAR(G.MapDistance(env, 1429, 0.42, 0.655, 1429, 0.48, 0.42), 582.4, 1, "C: MapDistance gives the same 582 yd")

end

-- ===========================================================================
-- D: relative angle and alignment
-- ===========================================================================
do
NEAR(G.Relative(0.1, 2 * PI - 0.1), 0.2, 1e-12, "D: across north: 0.1 vs 359.9 deg is +0.2 rad")
NEAR(G.Relative(2 * PI - 0.1, 0.1), -0.2, 1e-12, "D: and the other way is -0.2 rad")
EQ(G.Relative(PI, 0), PI, "D: directly behind is +pi")
EQ(G.Relative(0, PI), PI, "D: -pi folds to +pi (range is (-pi, pi])")
NEAR(G.Relative(3 * PI, 0), PI, 1e-9, "D: 3pi folds to pi")
NEAR(G.Relative(-3 * PI, 0), PI, 1e-9, "D: -3pi folds to pi")
NEAR(G.Relative(20 * PI + 0.5, 0), 0.5, 1e-9, "D: ten turns plus 0.5 is 0.5")
NEAR(G.Relative(-20 * PI - 0.5, 0), -0.5, 1e-9, "D: minus ten turns minus 0.5 is -0.5")
NEAR(G.Relative(PI / 2, 0), PI / 2, 1e-12, "D: due west while facing north is +pi/2 (left)")
NEAR(G.Relative(3 * PI / 2, 0), -PI / 2, 1e-12, "D: due east while facing north is -pi/2 (right)")
NEAR(G.Relative(0, 3 * PI / 2), PI / 2, 1e-12, "D: north while facing east is +pi/2 (left)")
EQ(G.Relative(1, nil), nil, "D: no facing gives nil, never facing 0")
EQ(G.Relative(nil, 1), nil, "D: no bearing gives nil")
local relOK = true
for i = -50, 50 do
    local r = G.Relative(i * 0.37, -i * 0.11)
    if not (r and r > -PI and r <= PI) then relOK = false end
end
CHECK(relOK, "D: 101 relative angles all land in (-pi, pi]")
EQ(G.Normalize(nil), nil, "D: Normalize(nil) is nil")
NEAR(G.Normalize(7 * PI / 2), -PI / 2, 1e-9, "D: Normalize(7pi/2) is -pi/2")
EQ(G.Alignment(0), 1, "D: alignment dead ahead is 1")
EQ(G.Alignment(PI), 0, "D: alignment behind is 0")
NEAR(G.Alignment(PI / 2), 0.5, 1e-12, "D: alignment square left is 0.5")
NEAR(G.Alignment(-PI / 2), 0.5, 1e-12, "D: alignment square right is 0.5")
NEAR(G.Alignment(2 * PI), 1, 1e-12, "D: alignment of a full turn is 1")
NEAR(G.Alignment(4 / DEG), 1 - 4 / 180, 1e-12, "D: alignment 4 deg off is 0.978")
EQ(G.Alignment(nil), nil, "D: alignment of nil is nil")

end

-- ===========================================================================
-- E: landmass
-- ===========================================================================
do
EQ(G.Continent(env, 1429), 1415, "E: Elwynn is on Eastern Kingdoms")
EQ(G.Continent(env, 1941), 1415, "E: Eversong (instance 530) is on Eastern Kingdoms")
EQ(G.Continent(env, 1957), 1415, "E: Isle of Quel'Danas is on Eastern Kingdoms")
EQ(G.Continent(env, 1943), 1414, "E: Azuremyst is on Kalimdor")
EQ(G.Continent(env, 1947), 1414, "E: the Exodar is on Kalimdor")
EQ(G.Continent(env, 1944), 1945, "E: Hellfire Peninsula is on Outland")
EQ(G.Continent(env, 1956), 1945, "E: Eye of the Storm (under Netherstorm) is on Outland")
EQ(G.Continent(env, 1415), 1415, "E: a continent is its own continent")
EQ(G.Continent(env, 350), 1415, "E: Karazhan (dungeon under Deadwind Pass) walks to EK")
EQ(G.Continent(env, 347), 1945, "E: Hellfire Ramparts walks to Outland")
EQ(G.Continent(env, 1459), nil, "E: Alterac Valley hangs off Azeroth: no continent")
EQ(G.Continent(env, 947), nil, "E: Azeroth has no continent")
EQ(G.Continent(env, 946), nil, "E: Cosmic has no continent")
EQ(G.Continent(env, 987), 987, "E: the legacy Outland 987 is a continent of its own")
EQ(G.Continent(env, 424242), nil, "E: an unknown map has no continent")
EQ(G.Continent(env, nil), nil, "E: nil map has no continent")
EQ(SAFE(G.Continent, boomEnv, 1429), nil, "E: a throwing mapInfo gives nil, not an error")

-- caching: a second ask makes no client call; ClearCache forgets
local cacheEnv = NewEnv()
G.Continent(cacheEnv, 1941)
local before = cacheEnv.calls.mapInfo
CHECK(before > 0, "E: the first walk asks the client")
G.Continent(cacheEnv, 1941)
EQ(cacheEnv.calls.mapInfo, before, "E: the second walk is cached")
G.ClearCache(cacheEnv)
G.Continent(cacheEnv, 1941)
CHECK(cacheEnv.calls.mapInfo > before, "E: ClearCache forgets")

-- a cycle in the map tree terminates
local cycleEnv = { mapInfo = function(id)
    if id == 1 then return { mapID = 1, name = "A", mapType = 3, parentMapID = 2 } end
    if id == 2 then return { mapID = 2, name = "B", mapType = 3, parentMapID = 1 } end
end }
EQ(G.Continent(cycleEnv, 1), nil, "E: a parent cycle ends with no continent")

EQ(G.Instance(env, 1941), 530, "E: Eversong lives on instance 530")
EQ(G.Instance(env, 1423), 0, "E: Eastern Plaguelands lives on instance 0")
EQ(G.Instance(env, 1415), 0, "E: the EK continent's main frame is instance 0")
EQ(G.Instance(env, 350), 532, "E: Karazhan is its own instance (532)")
EQ(G.Instance(env, 1554), nil, "E: SSC 1554 has no world data")
EQ(G.Instance(env, 947), 1, "E: Azeroth's centre is ocean; a further probe finds Kalimdor's frame")
EQ(G.Instance(env, 946), nil, "E: Cosmic has no world data")

EQ(G.Landmass(env, 1941), "1415:530", "E: Eversong's landmass key")
EQ(G.Landmass(env, 1944), "1945:530", "E: Hellfire's landmass key")
EQ(G.Landmass(env, 1459), "1459:30", "E: Alterac Valley is its own landmass")
EQ(G.Landmass(env, 947), nil, "E: Azeroth has no landmass")
EQ(G.Landmass(env, 1554), nil, "E: a map with no world data has no landmass")

local LANDMASS = {
    { 1941, 1944, false, "Eversong vs Hellfire (same instance 530, different continent)" },
    { 1941, 1942, true, "Eversong vs Ghostlands" },
    { 1941, 1954, true, "Eversong vs Silvermoon City" },
    { 1942, 1423, false, "Ghostlands (530) vs Eastern Plaguelands (0): the seam" },
    { 1429, 1436, true, "Elwynn vs Westfall" },
    { 1429, 1453, true, "Elwynn vs Stormwind City" },
    { 1429, 1411, false, "Elwynn vs Durotar" },
    { 1943, 1950, true, "Azuremyst vs Bloodmyst" },
    { 1943, 1439, false, "Azuremyst (530) vs Darkshore (1)" },
    { 1943, 1944, false, "Azuremyst vs Hellfire (both 530)" },
    { 1944, 1955, true, "Hellfire vs Shattrath" },
    { 1944, 347, false, "Hellfire vs Hellfire Ramparts (instance 543)" },
    { 1430, 350, false, "Deadwind Pass vs Karazhan" },
    { 1953, 1956, false, "Netherstorm vs Eye of the Storm (instance 566)" },
    { 1459, 1459, true, "Alterac Valley vs itself" },
    { 1459, 1416, false, "Alterac Valley vs Alterac Mountains" },
    { 1946, 1554, false, "Zangarmarsh vs SSC 1554 (no world data)" },
    { 947, 947, false, "Azeroth vs itself (no landmass)" },
}
for _, row in ipairs(LANDMASS) do
    EQ(G.SameLandmass(env, row[1], row[2]), row[3], "E: SameLandmass " .. row[4])
end
EQ(G.SameLandmass(env, 1941, 1942, 530, 530), true, "E: explicit instances that match")
EQ(G.SameLandmass(env, 1941, 1942, 530, 0), false, "E: explicit instances that differ")
local treeOnly = { mapInfo = env.mapInfo }
EQ(G.SameLandmass(treeOnly, 1942, 1423), true, "E: with no worldPos, the continent alone decides")
EQ(G.SameLandmass(treeOnly, 1941, 1944), false, "E: with no worldPos, continents still differ")
EQ(SAFE(G.SameLandmass, boomEnv, 1429, 1429), false, "E: a throwing env never says same")
EQ(G.Landmass(treeOnly, 1941), "1415:?", "E: with no worldPos the key carries no instance")

end

-- ===========================================================================
-- F: ToWorld
-- ===========================================================================
do
local ti
ti, tN, tW = G.ToWorld(env, 1941, 0.5, 0.5)
EQ(ti, 530, "F: Eversong centre is on 530")
CHECK(tN and tN > 7758 and tN < 11042 and tW > -9413 and tW < -4487, "F: Eversong centre inside its world region")
EQ(G.ToWorld(env, 947, 0.45, 0.5), nil, "F: ocean between the continents on Azeroth has no world data")
EQ(G.ToWorld(env, 946, 0.5, 0.5), nil, "F: Cosmic has no world data")
EQ(SAFE(G.ToWorld, boomEnv, 1429, 0.5, 0.5), nil, "F: a throwing worldPos gives nil")
EQ(G.ToWorld(emptyEnv, 1429, 0.5, 0.5), nil, "F: no worldPos gives nil")
EQ(G.ToWorld(env, 1429, nil, 0.5), nil, "F: nil x gives nil")
EQ(G.ToWorld(env, "1429", 0.5, 0.5), nil, "F: a string map gives nil")
EQ(G.ToWorld(nil, 1429, 0.5, 0.5), nil, "F: no env gives nil")
EQ(G.ToWorld({ worldPos = function() return 0, { x = 0 / 0, y = 1 } end }, 1, 0.5, 0.5), nil,
    "F: a NaN coordinate gives nil")
EQ(G.ToWorld({ worldPos = function() return nil, { x = 1, y = 1 } end }, 1, 0.5, 0.5), nil,
    "F: a missing instance gives nil")
local proxy = newproxy(true)
getmetatable(proxy).__index = function(_, k) return ({ x = 12, y = -34 })[k] end
local pi_, pN, pW = G.ToWorld({ worldPos = function() return 1, proxy end }, 1, 0.5, 0.5)
CHECK(pi_ == 1 and pN == 12 and pW == -34, "F: a userdata vector is read by .x (north) and .y (west)")
EQ(G.CheckPosition(1944, 0.452, 0.668), true, "F: CheckPosition accepts a valid position")
EQ(select(2, G.CheckPosition(1944, 1.2, 0.5)), "x", "F: CheckPosition rejects x > 1")
EQ(select(2, G.CheckPosition(1944, 0.5, 0 / 0)), "y", "F: CheckPosition rejects NaN y")
EQ(select(2, G.CheckPosition(0, 0.5, 0.5)), "map", "F: CheckPosition rejects map 0")
EQ(select(2, G.CheckPosition(19.5, 0.5, 0.5)), "map", "F: CheckPosition rejects a fractional map")
EQ(G.CheckPosition(1, 0, 1), true, "F: CheckPosition accepts the edges 0 and 1")
EQ(G.MapDistance(env, 1941, 0.5, 0.5, 1944, 0.5, 0.5), nil, "F: MapDistance Eversong to Hellfire is nil")
EQ(G.MapDistance(env, 1942, 0.5, 0.5, 1423, 0.5, 0.5), nil, "F: MapDistance across the 530 seam is nil")

end

-- ===========================================================================
-- G: projection
-- ===========================================================================
do
local function RoundTrip(map, x, y, target, label)
    local ux, uy = G.ProjectToMap(env, map, x, y, target)
    CHECK(ux ~= nil, "G: " .. label .. " projects up")
    if not ux then return end
    local bx, by = G.ProjectToMap(env, target, ux, uy, map)
    CHECK(bx and math.abs(bx - x) < 1e-9 and math.abs(by - y) < 1e-9, "G: " .. label .. " comes back exactly",
        tostring(bx) .. "," .. tostring(by))
    return ux, uy
end
ekx, eky = RoundTrip(1429, 0.42, 0.655, 1415, "Goldshire on EK")
RoundTrip(1429, 0.42, 0.655, 947, "Goldshire on Azeroth")
RoundTrip(1941, 0.5, 0.5, 1415, "Eversong centre on EK")
RoundTrip(1941, 0.3, 0.7, 947, "Eversong on Azeroth")
RoundTrip(1944, 0.55, 0.62, 1945, "Hellfire on Outland")
RoundTrip(1943, 0.45, 0.45, 1414, "Azuremyst on Kalimdor")
RoundTrip(1411, 0.5, 0.5, 947, "Durotar on Azeroth")
-- exact in world terms: the EK point is the same world spot as the zone point
local wi, wN, wW = G.ToWorld(env, 1415, ekx, eky)
CHECK(wi == 0 and math.abs(wN - gN) < 1e-6 and math.abs(wW - gW) < 1e-6,
    "G: Goldshire projected on EK is the same world point")
evx, evy = G.ProjectToMap(env, 1941, 0.5, 0.5, 1415)
local ei, eN, eW = G.ToWorld(env, 1415, evx, evy)
CHECK(ei == 530 and math.abs(eN - tN) < 1e-6 and math.abs(eW - tW) < 1e-6,
    "G: Eversong projected on EK lands in EK's 530 frame at the same world point")
local sx, sy = G.ProjectToMap(env, 1429, 0.42, 0.655, 1429)
CHECK(sx == 0.42 and sy == 0.655, "G: projecting onto the same map is the identity")
EQ(G.ProjectToMap(env, 1944, 0.5, 0.5, 947), nil, "G: Outland never projects onto Azeroth")
-- (zone rectangles overlap: Goldshire, at north -9455, is inside Westfall's box, which runs to -9400)
EQ(G.ProjectToMap(env, 1429, 0.48, 0.42, 1436), nil, "G: Northshire is not on the Westfall map")
-- a point inside both Elwynn's and Westfall's rectangles lands on the same world spot
local l1, r1, t1, b1 = FixtureRect(1429, 1415)
local l2, r2, t2, b2 = FixtureRect(1436, 1415)
local ox, oy = (math.max(l1, l2) + math.min(r1, r2)) / 2, (math.max(t1, t2) + math.min(b1, b2)) / 2
local zx, zy = (ox - l1) / (r1 - l1), (oy - t1) / (b1 - t1)
local wx, wy = G.ProjectToMap(env, 1429, zx, zy, 1436)
CHECK(wx and wx >= 0 and wx <= 1 and wy >= 0 and wy <= 1, "G: a shared border point projects across siblings")
if wx then
    local i1, n1, w1 = G.ToWorld(env, 1429, zx, zy)
    local i2, n2, w2 = G.ToWorld(env, 1436, wx, wy)
    CHECK(i1 == i2 and math.abs(n1 - n2) < 1e-6 and math.abs(w1 - w2) < 1e-6,
        "G: sibling projection keeps the world point")
end
local dx, dy = G.ProjectToMap(env, 1415, ekx, eky, 1429)
CHECK(dx and math.abs(dx - 0.42) < 1e-9 and math.abs(dy - 0.655) < 1e-9, "G: down from EK into Elwynn")
EQ(G.ProjectToMap(env, 1415, 0.02, 0.02, 1429), nil, "G: an EK point outside Elwynn does not project into it")
EQ(SAFE(G.ProjectToMap, boomEnv, 1429, 0.5, 0.5, 1415), nil, "G: a throwing env gives nil")
EQ(G.ProjectToMap(env, 1429, nil, 0.5, 1415), nil, "G: nil x gives nil")
EQ(G.ProjectToMap(env, 424242, 0.5, 0.5, 1415), nil, "G: an unknown map gives nil")
-- a client that refuses the direct grandparent rect is composed one step at a time
local stepEnv = NewEnv()
stepEnv.rectOnMap = function(child, top)
    if MAPS[child] and MAPS[child][3] ~= top then return nil end
    return FixtureRect(child, top)
end
local cx1, cy1 = G.ProjectToMap(env, 1429, 0.3, 0.6, 947)
local cx2, cy2 = G.ProjectToMap(stepEnv, 1429, 0.3, 0.6, 947)
CHECK(cx2 and math.abs(cx1 - cx2) < 1e-9 and math.abs(cy1 - cy2) < 1e-9,
    "G: composing parent steps equals the direct grandparent rect")

end

-- ===========================================================================
-- H: ZoneAt
-- ===========================================================================
do
local zm, zzx, zzy = G.ZoneAt(env, 1415, ekx, eky)
EQ(zm, 1429, "H: an EK click on Goldshire resolves to Elwynn")
CHECK(zzx and math.abs(zzx - 0.42) < 1e-9 and math.abs(zzy - 0.655) < 1e-9, "H: with Goldshire's zone coordinates")
local azx, azy = G.ProjectToMap(env, 1429, 0.42, 0.655, 947)
local am, amx, amy = G.ZoneAt(env, 947, azx, azy)
EQ(am, 1429, "H: an Azeroth click on Goldshire resolves through EK to Elwynn")
CHECK(amx and math.abs(amx - 0.42) < 1e-9 and math.abs(amy - 0.655) < 1e-9, "H: with the same coordinates")
EQ(G.ZoneAt(env, 1415, 0.02, 0.02), nil, "H: open sea on the EK map is no zone")
EQ(G.ZoneAt(env, 947, 0.45, 0.5), nil, "H: the ocean between continents is no zone")
local selfM, selfX, selfY = G.ZoneAt(env, 1944, 0.3, 0.4)
CHECK(selfM == 1944 and selfX == 0.3 and selfY == 0.4, "H: a zone click is already a zone")
EQ((G.ZoneAt(env, 350, 0.5, 0.5)), 350, "H: a dungeon map answers itself")
EQ((G.ZoneAt(env, 1953, 0.5, 0.5)), 1953, "H: Netherstorm never descends into Eye of the Storm")
local selfEnv = NewEnv()
selfEnv.mapInfoAtPosition = function(map) return MapInfoOf(map) end
EQ(G.ZoneAt(selfEnv, 1415, ekx, eky), nil, "H: a client that answers the continent itself gives nil")
local dungeonEnv = NewEnv()
dungeonEnv.mapInfoAtPosition = function() return MapInfoOf(350) end
EQ(G.ZoneAt(dungeonEnv, 1415, ekx, eky), nil, "H: a descent never enters a dungeon map")
local liarEnv = NewEnv()
liarEnv.mapInfoAtPosition = function() return MapInfoOf(1411) end
EQ(G.ZoneAt(liarEnv, 1415, ekx, eky), nil, "H: a zone whose own rectangle misses the click is refused")
local noHitEnv = NewEnv()
noHitEnv.mapInfoAtPosition = nil
EQ(G.ZoneAt(noHitEnv, 1415, ekx, eky), nil, "H: no GetMapInfoAtPosition: continent clicks give nil")
EQ(SAFE(G.ZoneAt, boomEnv, 1415, 0.5, 0.5), nil, "H: a throwing env gives nil")
EQ(G.ZoneAt(env, 1415, nil, 0.5), nil, "H: nil x gives nil")
local evMap, evX, evY = G.ZoneAt(env, 1415, evx, evy)
CHECK(evMap == 1941 or evMap == 1954, "H: an EK click in Quel'Thalas resolves to a 530 zone", evMap)
if evMap then
    local ri, rN, rW = G.ToWorld(env, evMap, evX, evY)
    CHECK(ri == 530 and math.abs(rN - tN) < 1e-6 and math.abs(rW - tW) < 1e-6,
        "H: the Quel'Thalas click keeps its world point")
end

-- The grid: every answer, on every continent and on Azeroth, is the same
-- world point as the click itself (zone coordinates from the zone's own
-- rectangle on the clicked map), and every answer is a Zone
for _, gridMap in ipairs({ 1415, 1414, 1945, 947 }) do
    local hits, consistent, zonesOnly, errors = 0, true, true, 0
    for i = 1, 24 do
        for j = 1, 24 do
            local x, y = (i - 0.5) / 24, (j - 0.5) / 24
            local ok, m, mx, my = pcall(G.ZoneAt, env, gridMap, x, y)
            if not ok then
                errors = errors + 1
            elseif m then
                hits = hits + 1
                if MAPS[m][2] ~= 3 then zonesOnly = false end
                local ci, cN, cW = FixtureWorld(gridMap, x, y)
                local zi, zN, zW = G.ToWorld(env, m, mx, my)
                if not (ci and zi == ci and math.abs(zN - cN) < 1e-3 and math.abs(zW - cW) < 1e-3) then
                    consistent = false
                end
            end
        end
    end
    EQ(errors, 0, "H: grid on " .. gridMap .. " raises nothing")
    CHECK(hits > 20, "H: grid on " .. gridMap .. " finds zones", hits)
    CHECK(zonesOnly, "H: grid on " .. gridMap .. " answers Zone maps only")
    CHECK(consistent, "H: grid on " .. gridMap .. " keeps every world point")
end

end

-- ===========================================================================
-- I: minimap
-- ===========================================================================
do
local MD = G.MINIMAP_DIAMETERS
EQ(#MD.indoor, 6, "I: six indoor zoom levels")
EQ(#MD.outdoor, 6, "I: six outdoor zoom levels")
local IND = { 300, 240, 180, 120, 80, 50 }
local OUT = { 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
for i = 1, 6 do
    NEAR(MD.indoor[i], IND[i], 1e-9, "I: indoor diameter at zoom " .. (i - 1))
    NEAR(MD.outdoor[i], OUT[i], 1e-9, "I: outdoor diameter at zoom " .. (i - 1))
end
CHECK(math.abs(MD.outdoor[4] - (266 + 2 / 6)) > 0.3, "I: the fourth outdoor value is 266.67, not HBD's 266.33")
NEAR(MD.outdoor[1] / MD.outdoor[4], 1.75, 1e-9, "I: outdoor zoom 3 is 1.75x zoom 0")
NEAR(G.MinimapRadius(0, false), 233.333, 1e-3, "I: outdoor radius at zoom 0")
NEAR(G.MinimapRadius(5, true), 25, 1e-9, "I: indoor radius at zoom 5")
NEAR(G.MinimapRadius(-1, false), G.MinimapRadius(0, false), 1e-9, "I: a zoom below 0 clamps to 0")
NEAR(G.MinimapRadius(9, true), 25, 1e-9, "I: a zoom above 5 clamps to 5")
NEAR(G.MinimapRadius(nil, nil), G.MinimapRadius(0, false), 1e-9, "I: nil zoom is outdoor zoom 0")
EQ(G.MinimapIndoors(2, "2", "4", true), false, "I: zoom equal to minimapZoom is outdoors")
EQ(G.MinimapIndoors(4, "2", "4", false), true, "I: zoom equal to minimapInsideZoom is indoors")
EQ(G.MinimapIndoors(3, "3", "3", true), true, "I: equal CVars: IsIndoors breaks the tie (in)")
EQ(G.MinimapIndoors(3, "3", "3", false), false, "I: equal CVars: IsIndoors breaks the tie (out)")
EQ(G.MinimapIndoors(1, "2", "4", true), true, "I: neither CVar matches: IsIndoors decides")
EQ(G.MinimapIndoors(nil, nil, nil, nil), false, "I: nothing known: outdoors")

local function P(dN, dW, facing, rotate, shape, hw, hh)
    return G.MinimapPlace(dN, dW, 100, facing, rotate, shape, hw or 70, hh)
end
local px, pyy, edge, ang = P(50, 0)
CHECK(math.abs(px) < 1e-12 and math.abs(pyy - 35) < 1e-12 and edge == false, "I: 50 yd north is straight up")
NEAR(ang, 0, 1e-12, "I: north edge angle is 0")
px, pyy, edge, ang = P(0, -50)
CHECK(math.abs(px - 35) < 1e-12 and math.abs(pyy) < 1e-12 and not edge, "I: 50 yd east is to the right")
NEAR(ang, -PI / 2, 1e-12, "I: east edge angle is -pi/2 (clockwise)")
px, pyy, edge, ang = P(0, 50)
CHECK(math.abs(px + 35) < 1e-12 and math.abs(pyy) < 1e-12, "I: 50 yd west is to the left")
NEAR(ang, PI / 2, 1e-12, "I: west edge angle is +pi/2")
px, pyy, edge, ang = P(-50, 0)
CHECK(math.abs(px) < 1e-12 and math.abs(pyy + 35) < 1e-12, "I: 50 yd south is straight down")
NEAR(math.abs(ang), PI, 1e-12, "I: south edge angle is pi")
px, pyy, edge = P(1000, 0)
CHECK(edge == true and math.abs(pyy - 63) < 1e-9 and math.abs(px) < 1e-9, "I: far north rides the rim at 0.9")
px, pyy, edge = P(1000, -1000, nil, false, "ROUND")
CHECK(edge and math.abs(px - 63 / math.sqrt(2)) < 1e-9 and math.abs(pyy - 63 / math.sqrt(2)) < 1e-9,
    "I: far north-east on a round map sits on the circle")
px, pyy, edge = P(1000, -1000, nil, false, "SQUARE")
CHECK(edge and math.abs(px - 63) < 1e-9 and math.abs(pyy - 63) < 1e-9, "I: on a square map it sits in the corner")
px, pyy, edge = P(80, -80, nil, false, "ROUND")
CHECK(edge == true, "I: 113 yd diagonal is off a round map of radius 100")
px, pyy, edge = P(80, -80, nil, false, "SQUARE")
CHECK(edge == false and math.abs(px - 56) < 1e-9 and math.abs(pyy - 56) < 1e-9,
    "I: but on the square map's corner terrain, unclamped")
px, pyy, edge = P(1000, 0, nil, false, "SQUARE")
CHECK(edge and math.abs(pyy - 63) < 1e-9, "I: on an axis the square and round rims agree")
px, pyy, edge = P(1000, -1000, nil, false, "CORNER-TOPRIGHT")
CHECK(edge and math.abs(px - 63 / math.sqrt(2)) < 1e-9, "I: CORNER-TOPRIGHT keeps the upper-right quadrant round")
px, pyy, edge = P(1000, 1000, nil, false, "CORNER-TOPRIGHT")
CHECK(edge and math.abs(px + 63) < 1e-9 and math.abs(pyy - 63) < 1e-9, "I: and squares the upper-left one")
px, pyy, edge = P(-1000, -1000, nil, false, "SIDE-BOTTOM")
CHECK(edge and math.abs(px - 63 / math.sqrt(2)) < 1e-9, "I: SIDE-BOTTOM keeps the lower-right round")
px, pyy, edge = P(1000, -1000, nil, false, "BLOB")
CHECK(edge and math.abs(px - 63 / math.sqrt(2)) < 1e-9, "I: an unknown shape is round")
px, pyy = P(1000, -1000, nil, false, nil)
CHECK(math.abs(px - 63 / math.sqrt(2)) < 1e-9, "I: no shape is round")
-- rotation: the player's facing is screen up
px, pyy = P(0, 50, PI / 2, true)
CHECK(math.abs(px) < 1e-9 and math.abs(pyy - 35) < 1e-9, "I: rotating, facing west, a west target is up")
px, pyy = P(0, -50, 3 * PI / 2, true)
CHECK(math.abs(px) < 1e-9 and math.abs(pyy - 35) < 1e-9, "I: rotating, facing east, an east target is up")
px, pyy = P(50, 0, PI, true)
CHECK(math.abs(px) < 1e-9 and math.abs(pyy + 35) < 1e-9, "I: rotating, facing south, a north target is down")
px, pyy = P(50, 0, PI / 2, true)
CHECK(math.abs(px - 35) < 1e-9 and math.abs(pyy) < 1e-9, "I: rotating, facing west, a north target is right")
local rx, ry = P(30, -40, 0, true)
local ux2, uy2 = P(30, -40, nil, false)
CHECK(math.abs(rx - ux2) < 1e-12 and math.abs(ry - uy2) < 1e-12, "I: rotating while facing north changes nothing")
local fx2, fy2 = P(30, -40, 1.0, false)
CHECK(math.abs(fx2 - ux2) < 1e-12 and math.abs(fy2 - uy2) < 1e-12, "I: facing is ignored when not rotating")
EQ(P(50, 0, nil, true), nil, "I: rotating with no heading cannot place")
px, pyy = P(50, 0, nil, false, nil, 70, 50)
CHECK(math.abs(pyy - 25) < 1e-12, "I: half-height scales the vertical offset")
EQ(G.MinimapPlace(50, 0, 0, nil, false), nil, "I: a zero radius gives nil")
EQ(G.MinimapPlace(nil, 0, 100, nil, false), nil, "I: nil dN gives nil")
px, pyy, edge, ang = P(-300, 300, 2.0, true, "SQUARE")
local back = math.atan2(-px, pyy)
NEAR(ang, back, 1e-12, "I: the edge angle points at the clamped pin")

end

-- ===========================================================================
-- J: filters
-- ===========================================================================
do
local st = {}
EQ(G.AngleFilter(st, 1.0, 0.016, 0.1), 1.0, "J: the first call snaps to the target")
NEAR(G.AngleFilter(st, 1.0, 0, 0.1), 1.0, 1e-12, "J: dt 0 holds the value")
local snap = {}
G.AngleFilter(snap, 0.5, 0.016, 0.1)
EQ(G.AngleFilter(snap, 2.0, 0.016, 0), 2.0, "J: tau 0 snaps")
EQ(G.AngleFilter(snap, nil, 0.016, 0.1), nil, "J: no heading answers nil")
EQ(snap.value, nil, "J: and resets the follower")
EQ(G.AngleFilter(nil, 7, 0.016, 0.1), G.Normalize(7), "J: no state answers the normalised target")
-- a step from rest: monotonic, never past the target, settled in a second
local step = {}
G.AngleFilter(step, 0, 0.016, 0.1)
local monotonic, overshoot, last = true, false, 0
local v
for _ = 1, 60 do
    v = G.AngleFilter(step, PI / 2, 1 / 60, 0.1)
    if v < last - 1e-12 then monotonic = false end
    if v > PI / 2 + 1e-12 then overshoot = true end
    last = v
end
CHECK(monotonic, "J: a step from rest rises monotonically")
CHECK(not overshoot, "J: and never overshoots")
NEAR(v, PI / 2, 1e-3, "J: and settles within a second (tau 0.1)")
local mid = {}
G.AngleFilter(mid, 0, 0.016, 0.1)
local early = G.AngleFilter(mid, PI / 2, 1 / 60, 0.1)
CHECK(early > 0 and early < 0.5, "J: one frame in it is partway, not snapped", early)
-- crossing +-pi: from 3.0 to -3.0 goes the short way through pi
local wrap = {}
G.AngleFilter(wrap, 3.0, 0.016, 0.1)
local shortWay, wv = true, nil
for _ = 1, 90 do
    wv = G.AngleFilter(wrap, -3.0, 1 / 60, 0.1)
    if math.abs(wv) < 2.99 then shortWay = false end
end
CHECK(shortWay, "J: 3.0 to -3.0 rad goes through pi, never through 0")
NEAR(wv, -3.0, 1e-3, "J: and arrives at -3.0")
local wrap2 = {}
G.AngleFilter(wrap2, -3.1, 0.016, 0.1)
local short2 = true
for _ = 1, 90 do
    local w = G.AngleFilter(wrap2, 3.1, 1 / 60, 0.1)
    if math.abs(w) < 3.09 then short2 = false end
end
CHECK(short2, "J: -3.1 to 3.1 rad also goes the short way")
-- a target sweeping round and round: bounded lag, no frame jump at the seam
local sweep = {}
local target, maxLag, maxJump, prev = 0, 0, 0, nil
G.AngleFilter(sweep, 0, 1 / 60, 0.1)
for _ = 1, 600 do
    target = target + 2 / 60
    local out = G.AngleFilter(sweep, target, 1 / 60, 0.1)
    maxLag = math.max(maxLag, math.abs(G.Normalize(target - out)))
    if prev then maxJump = math.max(maxJump, math.abs(G.Normalize(out - prev))) end
    prev = out
end
CHECK(maxLag < 0.5, "J: a 2 rad/s turn lags under 0.5 rad", maxLag)
CHECK(maxJump < 0.1, "J: and never jumps more than 0.1 rad in a frame (no wrap jump)", maxJump)
-- a follower already moving fast, handed a target just ahead, stops on it
local fast = {}
G.AngleFilter(fast, 0, 0.016, 0.1)
local fv
for _ = 1, 5 do fv = G.AngleFilter(fast, PI / 2, 1 / 60, 0.1) end
CHECK((fast.velocity or 0) > 5, "J: five frames in, the follower is moving fast", fast.velocity)
local stopAt = fv + 0.01
NEAR(G.AngleFilter(fast, stopAt, 1 / 60, 0.1), stopAt, 1e-12, "J: a fast follower stops on a target just ahead, not past it")
EQ(fast.velocity, 0, "J: and its velocity is spent")
local hitch = {}
G.AngleFilter(hitch, 0, 0.016, 0.1)
NEAR(G.AngleFilter(hitch, 1.2, 5, 0.1), 1.2, 1e-6, "J: a 5 s hitch lands on the target")

-- ETA
local eta = { target = "w1" }
NEAR(G.EtaFilter(eta, 700, 0, 7), 100, 1e-9, "J: ETA is seeded from the ground speed at once")
local d, e = 700, nil
for _ = 1, 50 do
    d = d - 0.7
    e = G.EtaFilter(eta, d, 0.1, 7)
end
NEAR(e, d / 7, d / 7 * 0.01, "J: walking straight at 7 yd/s: ETA = distance / 7")
NEAR(G.EtaFilter(eta, d, 0, 7), e, 1e-12, "J: dt 0 repeats the last ETA")
for _ = 1, 50 do
    d = d - 1.4
    e = G.EtaFilter(eta, d, 0.1, 14)
end
NEAR(e, d / 14, d / 14 * 0.02, "J: mounting up (14 yd/s) brings the ETA down to distance / 14")
local away = { target = "w1" }
G.EtaFilter(away, 300, 0, 7)
for _ = 1, 30 do
    d = 300
    e = G.EtaFilter(away, 300 + _ * 0.7, 0.1, 7)
end
EQ(e, nil, "J: walking away gives no ETA")
local circle = { target = "w1" }
G.EtaFilter(circle, 300, 0, 7)
for _ = 1, 30 do e = G.EtaFilter(circle, 300, 0.1, 7) end
EQ(e, nil, "J: circling at a constant distance gives no ETA")
local still = { target = "w1" }
G.EtaFilter(still, 300, 0, 7)
EQ(G.EtaFilter(still, 300, 0.1, 0), nil, "J: standing still gives no ETA")
EQ(G.EtaFilter({ target = "x" }, 300, 0, 0), nil, "J: a first sample at rest gives no ETA")
-- target change resets
local sw = { target = "w1" }
G.EtaFilter(sw, 700, 0, 7)
for _ = 1, 10 do G.EtaFilter(sw, 700 - _ * 0.7, 0.1, 7) end
sw.target = "w2"
NEAR(G.EtaFilter(sw, 140, 0.1, 7), 20, 1e-9, "J: a new target restarts from its own distance (no stale state)")
EQ(sw.closing, nil, "J: and drops the old closing rate")
-- and when the new target is about as far as the old one (no jump to give it
-- away), the old closing rate must still be dropped: the player was walking
-- towards w1, and w2 is 20 yd further, behind them
local near = { target = "w1" }
G.EtaFilter(near, 300, 0, 7)
for _ = 1, 10 do G.EtaFilter(near, 300 - _ * 0.7, 0.1, 7) end
near.target = "w2"
NEAR(G.EtaFilter(near, 313, 0.1, 7), 313 / 7, 1e-9, "J: a new target 20 yd off still restarts, not 'walking away'")
EQ(near.closing, nil, "J: with no closing rate carried over")
-- a teleport resets
local tp = { target = "w1" }
G.EtaFilter(tp, 700, 0, 7)
G.EtaFilter(tp, 699.3, 0.1, 7)
NEAR(G.EtaFilter(tp, 70, 0.1, 7), 10, 1e-9, "J: a 600 yd jump in 0.1 s re-seeds")
local tpAway = { target = "w1" }
G.EtaFilter(tpAway, 700, 0, 7)
G.EtaFilter(tpAway, 699.3, 0.1, 7)
NEAR(G.EtaFilter(tpAway, 1300, 0.1, 7), 1300 / 7, 1e-9,
    "J: a 600 yd jump away re-seeds instead of reading as walking away")
-- no speed hint: the closing rate is the speed
local noHint = { target = "w1" }
EQ(G.EtaFilter(noHint, 700, 0, nil), nil, "J: no hint, first sample: no ETA yet")
d = 700
for _ = 1, 40 do
    d = d - 0.7
    e = G.EtaFilter(noHint, d, 0.1, nil)
end
NEAR(e, d / 7, d / 7 * 0.05, "J: no hint: closing at 7 yd/s gives distance / 7")
EQ(G.EtaFilter(noHint, nil, 0.1, 7), nil, "J: no distance gives nil")
EQ(noHint.lastDist, nil, "J: and resets")
G.EtaReset(eta)
CHECK(eta.lastDist == nil and eta.speed == nil and eta.eta == nil, "J: EtaReset clears the state")
EQ(G.EtaFilter(nil, 100, 0.1, 7), nil, "J: no state table gives nil")

end

-- ===========================================================================
-- K: formats
-- ===========================================================================
do
local FD = {
    { 125, "YARDS", nil, "125 yd" },
    { 0.4, "YARDS", nil, "0 yd" },
    { 999.6, "YARDS", nil, "1,000 yd" },
    { 12952.4, "YARDS", nil, "12,952 yd" },
    { 582.43, "AUTO", nil, "582 yd" },
    { 582.43, "AUTO", true, "533 m" },
    { 125, "METRES", nil, "114 m" },
    { 1312, "METRES", nil, "1.2 km" },
    { 2000, "METRES", nil, "1.8 km" },
    { 1093.6, "METRES", nil, "1.0 km" },
    { 200000, "METRES", nil, "183 km" },
    { 125, nil, nil, "125 yd" },
    { 125, "FURLONGS", nil, "125 yd" },
}
for _, row in ipairs(FD) do
    EQ(G.FormatDistance(row[1], row[2], row[3]), row[4],
        "K: FormatDistance(" .. row[1] .. ", " .. tostring(row[2]) .. ")")
end
EQ(G.FormatDistance(nil, "YARDS"), nil, "K: FormatDistance(nil) is nil")
EQ(G.FormatDistance(-1, "YARDS"), nil, "K: FormatDistance(-1) is nil")
EQ(G.FormatDistance(0 / 0, "YARDS"), nil, "K: FormatDistance(NaN) is nil")
local FE = {
    { 45, "45s" }, { 0, "0s" }, { 59.4, "59s" }, { 59.6, "1m 00s" }, { 185, "3m 05s" },
    { 3599.4, "59m 59s" }, { 3599.6, "1h 00m" }, { 4320, "1h 12m" }, { 98 * 3600 + 59 * 60, "98h 59m" },
}
for _, row in ipairs(FE) do
    EQ(G.FormatEta(row[1]), row[2], "K: FormatEta(" .. row[1] .. ")")
end
EQ(G.FormatEta(nil), nil, "K: FormatEta(nil) is nil")
EQ(G.FormatEta(-3), nil, "K: FormatEta(-3) is nil")
EQ(G.FormatEta(0 / 0), nil, "K: FormatEta(NaN) is nil")
EQ(G.FormatEta(math.huge), nil, "K: FormatEta(inf) is nil")
EQ(G.FormatEta(100 * 3600), nil, "K: FormatEta past 99 hours is nil")
EQ(G.FormatCoords(0.452, 0.668), "45.2, 66.8", "K: FormatCoords default one decimal")
EQ(G.FormatCoords(0.452, 0.668, 2), "45.20, 66.80", "K: FormatCoords two decimals")
EQ(G.FormatCoords(0.452, 0.668, 0), "45, 67", "K: FormatCoords no decimals")
EQ(G.FormatCoords(0.452, 0.668, 9), "45.200, 66.800", "K: FormatCoords clamps to three decimals")
EQ(G.FormatCoords(0, 1), "0.0, 100.0", "K: FormatCoords at the edges")
EQ(G.FormatCoords(nil, 0.5), nil, "K: FormatCoords(nil) is nil")
EQ(G.WayLine(1944, 0.452, 0.668, "Nazgrel"), "/way #1944 45.20 66.80 Nazgrel", "K: WayLine")
EQ(G.WayLine(1944, 0.452, 0.668), "/way #1944 45.20 66.80", "K: WayLine with no title (B18)")
EQ(G.WayLine(1944, 0.452, 0.668, "   "), "/way #1944 45.20 66.80", "K: WayLine with a blank title")
EQ(G.WayLine(1944, 0.452, 0.668, "Line one\nLine two"), "/way #1944 45.20 66.80 Line one Line two",
    "K: WayLine folds control characters to spaces")
EQ(G.WayLine(nil, 0.452, 0.668, "Here"), "/way 45.20 66.80 Here", "K: WayLine without a map")
EQ(G.WayLine(1944, nil, 0.5), nil, "K: WayLine with no x is nil")
local FN = {
    { "Quel'Danas", "queldanas" },
    { "Isle of Quel'Danas", "isleofqueldanas" },
    { "Quel\226\128\153Danas", "queldanas" },
    { "Blade's Edge Mountains", "bladesedgemountains" },
    { "  Elwynn   Forest ", "elwynnforest" },
    { "Un'Goro-Crater", "ungorocrater" },
    { "STORMWIND", "stormwind" },
    { "(%[.-*", "" },
    { "#1944", "1944" },
}
for _, row in ipairs(FN) do
    EQ(G.FoldName(row[1]), row[2], "K: FoldName(" .. row[1] .. ")")
end
EQ(G.FoldName(nil), "", "K: FoldName(nil) is empty")

end

-- ===========================================================================
-- L: the zone index and matcher
-- ===========================================================================
do
-- A Data-style alias table: alias = uiMapID (the runtime's lives in Data)
local ALIASES = {
    sw = 1453, stormwind = 1453, ["if"] = 1455, ironforge = 1455, darn = 1457, org = 1454,
    uc = 1458, tb = 1456, shatt = 1955, stv = 1434, epl = 1423, wpl = 1422, hfp = 1944,
    hellfire = 1944, smv = 1948, bem = 1949, ns = 1953, zm = 1946, smc = 1954, exo = 1947,
    iqd = 1957, ["quel'danas"] = 1957,
    ["Goldshire Town"] = "Elwynn Forest",    -- a string value resolves by exact name
    nowhereville = "No Such Zone",           -- and is dropped when it does not
    westfall = 1429,                         -- shadowed by the real Westfall (exact name wins)
}
local idxEnv = NewEnv()
index = G.ZoneIndex(idxEnv, ALIASES)
local function Indexed(id)
    for _, e in ipairs(index.entries) do if e.map == id then return true end end
    return false
end
CHECK(#index.entries >= 60, "L: the index holds the reachable zones and continents", #index.entries)
CHECK(Indexed(1429) and Indexed(1944) and Indexed(1941), "L: zones on all three continents are in")
CHECK(Indexed(1414) and Indexed(1415) and Indexed(1945), "L: the three continents are in")
CHECK(Indexed(1459) and Indexed(1956), "L: battleground zone maps are in (AV, EotS)")
CHECK(not Indexed(987) and not Indexed(1463) and not Indexed(1464), "L: the parentless continent duplicates are out")
CHECK(not Indexed(347) and not Indexed(350) and not Indexed(274) and not Indexed(233), "L: dungeons and orphans are out")
CHECK(not Indexed(947) and not Indexed(946), "L: World and Cosmic are out")
EQ(index.names[347], "Hellfire Ramparts", "L: dungeon names are recorded for #id messages")
EQ(index.aliases.goldshiretown, 1429, "L: a string alias resolves through the exact name")
EQ(index.aliases.nowhereville, nil, "L: an alias to an unknown name is dropped")
EQ(index.aliases.queldanas, 1957, "L: alias keys are folded")
local sorted = true
for i = 2, #index.entries do
    if index.entries[i - 1].name > index.entries[i].name then sorted = false end
end
CHECK(sorted, "L: entries are sorted by name")

local function M(text)
    local map, list = G.MatchZone(index, text)
    return map, list
end
EQ((M("Elwynn Forest")), 1429, "L: exact name")
EQ((M("elwynnforest")), 1429, "L: exact folded name")
EQ((M("Westfall")), 1436, "L: an exact name beats an alias of the same text")
EQ((M("sw")), 1453, "L: alias sw")
EQ((M("IF")), 1455, "L: alias IF (folded)")
EQ((M("elwynn")), 1429, "L: prefix")
EQ((M("storm")), 1453, "L: prefix beats substring (Netherstorm, Eye of the Storm)")
EQ((M("Quel'Danas")), 1957, "L: alias quel'danas")
EQ((M("queld")), 1957, "L: 'queld' has no prefix hit, so the substring tier finds Quel'Danas")
EQ((M("danas")), 1957, "L: substring (3+ characters)")
EQ((M("hillsbrad")), 1424, "L: hillsbrad is the zone (Old Hillsbrad is a dungeon, by #id only)")
EQ((M("Eye of the Storm")), 1956, "L: exact battleground name")
EQ((M("kalimdor")), 1414, "L: the reachable Kalimdor, not 1464")
local am1, al1 = M("alterac")
CHECK(am1 == nil and #al1 == 2, "L: alterac is ambiguous between two maps")
CHECK(al1[1] and al1[1].map == 1416 and al1[2].map == 1459, "L: Alterac Mountains then Alterac Valley (by name)")
local am2, al2 = M("arathi")
CHECK(am2 == nil and #al2 == 2, "L: arathi is ambiguous (Highlands, Basin)")
local am3, al3 = M("eastern")
CHECK(am3 == nil and #al3 == 2, "L: eastern is ambiguous (the continent and the Plaguelands)")
local am4, al4 = M("wood")
CHECK(am4 == nil and #al4 >= 2, "L: wood is ambiguous by substring (Duskwood, Eversong Woods)")
EQ((M("ms")), nil, "L: two characters never substring-search")
local nm, nl = M("narnia")
CHECK(nm == nil and #nl == 0, "L: an unknown name gives nil and no candidates")
local pm = M("w.stfall")
EQ(pm, nil, "L: w.stfall is not a pattern that matches Westfall (TomTom B12)")
local okPat = pcall(M, "%[(")
CHECK(okPat, "L: pattern characters never raise")
EQ((M("")), nil, "L: empty text gives nil")
EQ((G.MatchZone(nil, "elwynn")), nil, "L: no index gives nil")
resolver = G.MakeResolver(index)
EQ((resolver("elwynn")), 1429, "L: MakeResolver wraps MatchZone")
local emptyIndex = G.ZoneIndex(emptyEnv)
EQ(#emptyIndex.entries, 0, "L: an env with no mapChildren gives an empty index")
local okBoom, boomIndex = pcall(G.ZoneIndex, boomEnv)
EQ(okBoom and #boomIndex.entries, 0, "L: a throwing mapChildren gives an empty index")

end

-- ===========================================================================
-- M: the /way grammar
-- ===========================================================================
do
-- Each row: input, expected fields. x and y are compared to 1e-9.
local GRAMMAR = {
    -- usage and keywords
    { "", { kind = "USAGE" } },
    { "   ", { kind = "USAGE" } },
    { "help", { kind = "USAGE" } },
    { "?", { kind = "USAGE" } },
    { "list", { kind = "LIST" } },
    { "LIST", { kind = "LIST" } },
    { "local", { kind = "LOCAL" } },
    { "arrow", { kind = "ARROW" } },
    -- coordinates in the current zone
    { "45 66", { kind = "ADD", map = "nil", x = 0.45, y = 0.66, title = "nil", zone = "nil" } },
    { "45.2 66.8", { kind = "ADD", x = 0.452, y = 0.668 } },
    { "45.2, 66.8", { kind = "ADD", x = 0.452, y = 0.668 } },
    { "45, 66", { kind = "ADD", x = 0.45, y = 0.66 } },
    { "45,66", { kind = "ADD", x = 0.45, y = 0.66, title = "nil" } },              -- B13
    { "45,66 Bank", { kind = "ADD", x = 0.45, y = 0.66, title = "Bank" } },
    { "45.2,66.8 Bank", { kind = "ADD", x = 0.452, y = 0.668, title = "Bank" } },
    { "45;66", { kind = "ADD", x = 0.45, y = 0.66 } },
    { "45,2 66,8", { kind = "ADD", x = 0.452, y = 0.668 } },                        -- decimal commas
    { "45,2, 66,8 Title", { kind = "ADD", x = 0.452, y = 0.668, title = "Title" } },
    { "45 66,8", { kind = "ADD", x = 0.45, y = 0.668 } },
    { "45,66 12 rats", { kind = "ADD", x = 0.4566, y = 0.12, title = "rats" } },   -- a number follows: decimal
    { ".5 .5", { kind = "ADD", x = 0.005, y = 0.005 } },
    { "0 0", { kind = "ADD", x = 0, y = 0 } },
    { "100 100", { kind = "ADD", x = 1, y = 1 } },
    { "45 66 Nazgrel the Warchief", { kind = "ADD", title = "Nazgrel the Warchief" } },
    { "45 66   Two  spaces  ", { kind = "ADD", title = "Two  spaces" } },
    { "45 66 Inn\tKeeper", { kind = "ADD", title = "Inn Keeper" } },                -- control characters fold
    { "45 66 70", { kind = "ADD", x = 0.45, y = 0.66, title = "70" } },
    -- zones
    { "Elwynn Forest 42 65.5 Goldshire", { kind = "ADD", map = 1429, x = 0.42, y = 0.655, title = "Goldshire",
        zone = "Elwynn Forest" } },
    { "elwynn 42 65.5", { kind = "ADD", map = 1429, title = "nil" } },
    { "#1944 45.2 66.8 Nazgrel", { kind = "ADD", map = 1944, byId = true, title = "Nazgrel" } },
    { "#347 50 50", { kind = "ADD", map = 347, byId = true } },                     -- a dungeon, by id
    { "sw 50 50", { kind = "ADD", map = 1453 } },
    { "Stormwind 50 50", { kind = "ADD", map = 1453 } },
    { "hellfire 50 50", { kind = "ADD", map = 1944 } },
    { "Quel'Danas 50 50", { kind = "ADD", map = 1957 } },
    { "Isle of Quel'Danas 50 50", { kind = "ADD", map = 1957 } },
    { "Eye of the Storm 50 50", { kind = "ADD", map = 1956 } },
    { "hillsbrad 50 50", { kind = "ADD", map = 1424 } },
    { "Blade's Edge Mountains 50, 50", { kind = "ADD", map = 1949 } },
    { "alterac 50 50", { kind = "ERROR", reason = "ZONE_AMBIGUOUS", zone = "alterac" } },
    { "arathi 50 50 Farm", { kind = "ERROR", reason = "ZONE_AMBIGUOUS", title = "Farm" } },
    { "Eastern 50 50", { kind = "ERROR", reason = "ZONE_AMBIGUOUS" } },
    { "Nowhere Land 50 50", { kind = "ERROR", reason = "ZONE_UNKNOWN", zone = "Nowhere Land" } },
    { "w.stfall 50 50", { kind = "ERROR", reason = "ZONE_UNKNOWN" } },              -- B12
    { "[ 50 50", { kind = "ERROR", reason = "ZONE_UNKNOWN" } },                    -- B12
    { "%a(( 50 50", { kind = "ERROR", reason = "ZONE_AMBIGUOUS" } },               -- B12: folds to "a"
    { "#abc 50 50", { kind = "ERROR", reason = "ZONE_UNKNOWN" } },
    -- bad numbers
    { "150 50", { kind = "ERROR", reason = "RANGE" } },
    { "50 -5", { kind = "ERROR", reason = "RANGE" } },
    { "100.5 50", { kind = "ERROR", reason = "RANGE" } },
    { "50", { kind = "ERROR", reason = "COORDS" } },
    { "Elwynn Forest", { kind = "ERROR", reason = "COORDS", zone = "Elwynn Forest" } },
    { "45 abc", { kind = "ERROR", reason = "COORDS" } },
    { "Elwynn 45", { kind = "ERROR", reason = "COORDS", zone = "Elwynn" } },
    { "45 66.2,3", { kind = "ERROR", reason = "COORDS" } },
    -- reset (B23: a bare reset asks for usage)
    { "reset", { kind = "USAGE", topic = "reset" } },
    { "reset all", { kind = "RESET", scope = "ALL" } },
    { "Reset ALL", { kind = "RESET", scope = "ALL" } },
    { "reset away", { kind = "RESET", scope = "AWAY" } },
    { "reset elwynn forest", { kind = "RESET", scope = "ZONE", map = 1429, zone = "elwynn forest" } },
    { "reset not elwynn", { kind = "RESET", scope = "NOT_ZONE", map = 1429 } },
    { "reset not", { kind = "USAGE", topic = "reset" } },
    { "reset #1944", { kind = "RESET", scope = "ZONE", map = 1944, byId = true } },
    { "reset alterac", { kind = "ERROR", reason = "ZONE_AMBIGUOUS" } },
    { "reset narnia", { kind = "ERROR", reason = "ZONE_UNKNOWN" } },
    -- pasted lines (B18: with or without the /way word)
    { "/way 45 66", { kind = "ADD", x = 0.45, y = 0.66 } },
    { "/WAY #1944 45.20 66.80 Nazgrel", { kind = "ADD", map = 1944, x = 0.452, y = 0.668, title = "Nazgrel" } },
    { "/tway 45 66", { kind = "ADD", x = 0.45, y = 0.66 } },
    { "/tomtomway 45 66", { kind = "ADD", x = 0.45, y = 0.66 } },
    { "  /way   45 66  Title  ", { kind = "ADD", title = "Title" } },
    { "/way", { kind = "USAGE" } },
    { "/way list", { kind = "LIST" } },
    { "/cway", { kind = "ERROR", reason = "NOT_WAY" } },
    { "/wayb Home", { kind = "ERROR", reason = "NOT_WAY" } },
}
local function Show(v) if v == nil then return "nil" end return tostring(v) end
for _, row in ipairs(GRAMMAR) do
    local ok, cmd = pcall(G.ParseWay, row[1], resolver)
    CHECK(ok and type(cmd) == "table", "M: ParseWay(" .. row[1] .. ") returns a table", cmd)
    if ok and type(cmd) == "table" then
        local good, why = true, {}
        for k, want in pairs(row[2]) do
            local got = cmd[k]
            local same
            if want == "nil" then
                same = got == nil
            elseif type(want) == "number" and type(got) == "number" then
                same = math.abs(got - want) < 1e-9
            else
                same = got == want
            end
            if not same then
                good = false
                why[#why + 1] = k .. "=" .. Show(got) .. " want " .. Show(want)
            end
        end
        CHECK(good, "M: /way " .. row[1], table.concat(why, "; "))
        EQ(cmd.text, row[1], "M: ParseWay(" .. row[1] .. ") echoes its text")
    end
end
EQ(G.ParseWay(nil, resolver).kind, "USAGE", "M: nil text is usage")
-- the ambiguous candidates carry ready lines, coordinates and title included
local amb = G.ParseWay("arathi 50 50 Farm", resolver)
CHECK(amb.candidates and #amb.candidates == 2, "M: arathi lists two candidates")
amb.candidates = amb.candidates or { {}, {} }
EQ(amb.candidates[1].line, "/way #1461 50.00 50.00 Farm", "M: candidate line for Arathi Basin")
EQ(amb.candidates[2].line, "/way #1417 50.00 50.00 Farm", "M: candidate line for Arathi Highlands")
CHECK(Has(amb.message, "Arathi Basin") and Has(amb.message, "Arathi Highlands"),
    "M: the message names both candidates")
local ramb = G.ParseWay("reset not alterac", resolver)
EQ(ramb.candidates and ramb.candidates[1].line, "/way reset not #1416", "M: reset candidates carry reset lines")
local rnone = G.ParseWay("reset narnia", resolver)
CHECK(Has(rnone.message, "/way reset #<map id>"), "M: an unknown reset zone suggests the reset #id form")
local many = G.ParseWay("s 50 50", resolver)
CHECK(many.reason == "ZONE_AMBIGUOUS" and #(many.candidates or {}) > 8 and Has(many.message, "more"),
    "M: a long candidate list is summarised in the message")
-- resolvers that misbehave
EQ(G.ParseWay("45 66", nil).kind, "ADD", "M: no resolver: coordinates alone still work")
EQ(G.ParseWay("Elwynn 45 66", nil).reason, "ZONE_UNKNOWN", "M: no resolver: a named zone is unknown")
EQ(G.ParseWay("#1429 45 66", nil).map, 1429, "M: no resolver: #id still works")
EQ((SAFE(G.ParseWay, "Elwynn 45 66", Boom) or {}).reason, "ZONE_UNKNOWN", "M: a throwing resolver is caught")
local numRes = function() return nil, { 1416, 1459 } end
local numCmd = G.ParseWay("alterac 45 66", numRes)
CHECK(numCmd.reason == "ZONE_AMBIGUOUS" and (numCmd.candidates or {{}})[1].name == "#1416", "M: number candidates get #id names")
local oneRes = function() return 1429 end
EQ(G.ParseWay("whatever 45 66", oneRes).map, 1429, "M: a resolver answer is used as is")
EQ((SAFE(G.ParseWay, "45 66 Title", Boom) or {}).title, "Title", "M: the resolver is not called without a zone")
local range = G.ParseWay("150 50", resolver)
CHECK(Has(range.message, "150"), "M: the range message quotes the bad value")

end

-- ===========================================================================
-- N: round trips and plain text
-- ===========================================================================
do
local TRIPS = {
    { 1944, 0.452, 0.668, "Nazgrel" },
    { 1429, 0.42, 0.655, "Goldshire Inn" },
    { 1957, 0.0, 1.0, nil },
    { 350, 0.1234, 0.9876, "Moroes, (the steward)" },
    { 1453, 0.5, 0.5, "45 66" },
}
for _, t in ipairs(TRIPS) do
    local line = G.WayLine(t[1], t[2], t[3], t[4])
    local cmd = G.ParseWay(line, resolver)
    CHECK(cmd.kind == "ADD" and cmd.map == t[1], "N: " .. line .. " parses back to its map")
    CHECK(cmd.x and math.abs(cmd.x - t[2]) <= 5e-5 and math.abs(cmd.y - t[3]) <= 5e-5,
        "N: " .. line .. " keeps its coordinates to the printed precision")
    EQ(cmd.title, t[4], "N: " .. line .. " keeps its title")
end
local function PlainAscii(s)
    return type(s) == "string" and not s:find("[^\32-\126]")
end
local plain = true
for _, topic in ipairs({ "nil", "reset" }) do
    for _, line in ipairs(G.WayUsage(topic ~= "nil" and topic or nil)) do
        if not PlainAscii(line) then plain = false end
    end
end
CHECK(plain, "N: usage lines are plain ASCII (no shape glyphs, D11)")
EQ(#G.WayUsage(), 4, "N: four usage lines")
EQ(#G.WayUsage("reset"), 4, "N: four reset usage lines")
local msgs = true
for _, input in ipairs({ "alterac 1 2", "narnia 1 2", "150 1", "50", "/cway", "reset narnia", "s 1 2" }) do
    local cmd = G.ParseWay(input, resolver)
    if not PlainAscii(cmd.message) then msgs = false end
end
CHECK(msgs, "N: every error message is plain ASCII")
local fmts = PlainAscii(G.FormatDistance(12952, "YARDS")) and PlainAscii(G.FormatDistance(1312, "METRES"))
    and PlainAscii(G.FormatEta(4320)) and PlainAscii(G.FormatCoords(0.5, 0.5))
CHECK(fmts, "N: formatted text is plain ASCII")

-- Nothing in all of the above reached for a global
EQ(#reads, 0, "N: no unknown global was read during the run")
EQ(#writes, 0, "N: no global was written during the run")

end

Finish()
