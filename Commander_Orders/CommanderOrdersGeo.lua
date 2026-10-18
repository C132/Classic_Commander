-- Commander Orders: the geometry.
--
-- Everything about WHERE things are that can be decided without a client is
-- decided here: distances and bearings in world yards, which maps share a
-- landmass, how a point on one map lands on another, where a pin sits on the
-- minimap, how the arrow's angle and the ETA are smoothed, how numbers are
-- written, and what a /way line means. The runtime builds a small `env` of
-- client functions and hands it in; the harness hands in tables instead. No
-- WoW API is read here, and Harness/orders_geo_smoke.lua proves it by loading
-- this file into a sealed environment in which reading any other global is
-- an error.
--
-- ---------------------------------------------------------------------------
-- The traps this file exists to keep shut
-- ---------------------------------------------------------------------------
-- 1. WHICH NUMBER IS NORTH (the old module's D1). `UnitPosition("player")`
--    returns north first and west second; `C_Map.GetWorldPosFromMapPos`
--    returns a vector whose .x is north and .y is west. The wiki writes the
--    first pair as "posY, posX" (named after the MAP axis each one drives),
--    and pairing "y" with the vector's .y is exactly how Orders 2.1 came to
--    subtract a west coordinate from a north one: 12,952 yd shown for a
--    582 yd walk from Goldshire to Northshire, and an arrow that never
--    arrives. Every variable here is called north or west, never x or y,
--    and the harness keeps that Elwynn walk as a regression.
-- 2. DEGREES. On this client the GLOBAL sin/cos/atan2 take and return
--    degrees (Blizzard's own vector code re-aliases math.*). Only the
--    math.* functions are used, captured as locals below.
-- 3. ONE INSTANCE, TWO LANDMASSES. Instance 530 holds Outland AND the blood
--    elf and draenei starting zones, so "same instance" is not "an arrow can
--    point there": Eversong to Hellfire is 530 to 530 across the Twisting
--    Nether. The landmass of a map is its first ancestor whose mapType is
--    Continent (Eversong, Ghostlands, Silvermoon and Quel'Danas sit under
--    Eastern Kingdoms 1415; Azuremyst, Bloodmyst and the Exodar under
--    Kalimdor 1414; Outland's zones under 1945), and two points share a
--    landmass only when that continent AND the world instance both match.
--    The second half matters too: Ghostlands (530) and Eastern Plaguelands
--    (0) are one continent but two coordinate frames, and a straight vector
--    between them is meaningless.
-- 4. CONTINENT MAPS HOLD TWO FRAMES. The EK and Kalimdor continent maps each
--    carry a main row (instance 0 or 1) and a 530 sub-rectangle; which one
--    GetWorldPosFromMapPos answers inside the overlap is not knowable
--    offline. So clicks on continent and world maps are resolved to the
--    zone under the cursor first (G.ZoneAt) and stored in zone coordinates,
--    and map-to-map work stays in MAP space (GetMapRectOnMap lerps), which
--    is exact by construction. HereBeDragons' fixed 530 offsets are NOT used:
--    on this build they are off by 263-371 yd across Eversong.
-- 5. THE CLIENT MAY RETURN NOTHING, OR THROW. GetWorldPosFromMapPos,
--    GetMapRectOnMap and GetMapInfoAtPosition are all MayReturnNothing, and
--    a bad id can raise. Every env call is pcall'd and every result is
--    checked for a finite number before use.
-- 6. THE MINIMAP HAS NO RADIUS API HERE. C_Minimap.GetViewRadius does not
--    exist on 2.5.6, so the radius is the game's per-zoom diameter table
--    halved. HereBeDragons-Pins ships the fourth outdoor value as
--    "266 + 2/6" (266.33), a slip for 266 + 2/3: the series is 466.67
--    divided by 1, 7/6, 1.4, 1.75, 7/3 and 3.5, and 466.67 / 1.75 = 266.67.
--    The correct value is used below. GetMinimapShape is an addon
--    convention, not a client function; the shape names (ROUND, SQUARE,
--    CORNER-*, SIDE-*, TRICORNER-*) are that ecosystem contract.
-- 7. /way PARSING (TomTom bugs not repeated). B12: zone text is folded
--    (G.FoldName strips every punctuation character) and compared with plain
--    finds, never used as a Lua pattern, so "(", "%", "[" or "-" in the input
--    cannot error or mis-match. B13: a lone "45,66" is the pair 45, 66,
--    not the decimal 45.66 (a decimal comma is read only when a second
--    number follows). B18: a line is accepted with or without its "/way"
--    word, so pasted guide text and bare coordinates both work. Values must
--    lie in 0..100; a missing "reset" target asks for usage instead of
--    silently doing nothing (B23); an ambiguous zone lists its candidates
--    with their "/way #id" lines and never guesses.
--
-- ---------------------------------------------------------------------------
-- The env the runtime passes in (every field optional; a missing one makes
-- the functions that need it answer nil)
-- ---------------------------------------------------------------------------
--   env.mapInfo(id)              -> { mapID, name, mapType, parentMapID } | nil
--                                   (C_Map.GetMapInfo)
--   env.worldPos(map, x, y)      -> instance, north, west
--                                -- or instance, vector with vector.x = north,
--                                   vector.y = west (C_Map.GetWorldPosFromMapPos
--                                   with CreateVector2D(x, y) passes straight in)
--   env.rectOnMap(child, top)    -> left, right, top, bottom | nil
--                                   (C_Map.GetMapRectOnMap: minX, maxX, minY, maxY)
--   env.mapInfoAtPosition(map, x, y) -> info | nil (C_Map.GetMapInfoAtPosition)
--   env.mapChildren(id)          -> array of info, DIRECT children only
--                                   (C_Map.GetMapChildrenInfo(id)); used by
--                                   G.ZoneIndex only
-- Results that depend only on the map tree (continent, instance, landmass)
-- are cached per env table; G.ClearCache(env) forgets them.
--
-- ---------------------------------------------------------------------------
-- G.ParseWay(text, resolver) -> cmd        (SPEC 7.2; for the runtime)
-- ---------------------------------------------------------------------------
-- `text` is what follows "/way" (the slash handler's msg), or a whole pasted
-- line with or without a leading "/way", "/tway" or "/tomtomway".
-- `resolver(zoneText) -> map | nil, candidates` turns a zone name into a
-- uiMapID; G.MakeResolver(G.ZoneIndex(env, aliases)) builds the standard one.
-- candidates may hold numbers or { map = id, name = "..." } tables. It is
-- pcall'd; a nil resolver makes every named zone unknown. "#<id>" zones never
-- reach the resolver: the runtime checks that map exists (env.mapInfo).
--
-- cmd.kind is one of:
--   "ADD"    { map = uiMapID | nil, x = 0..1, y = 0..1, title = string | nil,
--              zone = text typed for the zone | nil, byId = true | nil }
--            map == nil means the player's current map ("/way 45 66"): the
--            runtime fills it in. byId marks the "#1944" form.
--   "LOCAL"  {}                                  list waypoints on this map
--   "LIST"   {}                                  list every waypoint
--   "ARROW"  {}                                  report the arrow's state
--   "RESET"  { scope = "ALL" | "AWAY" | "ZONE" | "NOT_ZONE",
--              map = uiMapID (ZONE, NOT_ZONE), zone = text, byId = true|nil }
--            AWAY = every waypoint not on the player's current map.
--   "USAGE"  { topic = nil | "reset" }           print G.WayUsage(topic)
--   "ERROR"  { reason = code, message = one chat line, zone = text | nil,
--              x, y, title (when the coordinates were read),
--              candidates = { { map, name, line }, ... } | nil }
--            reason: "COORDS" (missing or unreadable numbers), "RANGE" (a
--            value outside 0..100), "ZONE_UNKNOWN", "ZONE_AMBIGUOUS" (each
--            candidate carries a ready line: "/way #id x y title" for an add,
--            "/way reset [not ]#id" for a reset), "NOT_WAY" (a pasted line
--            that is some other slash command, such as /cway).
-- Every cmd also carries `text`, the input as given.
--
-- Number grammar: "45 66", "45.2 66.8", "45.2, 66.8", "45, 66", a lone
-- "45,66" or "45.2,66.8" pair, and decimal commas when two numbers follow
-- each other ("45,2 66,8" and "45,2, 66,8" are 45.2, 66.8). A zone is every
-- word before the first number; the title is everything after the second.
-- The one reading that stays ambiguous by nature: "45,66 12 rats" is 45.66,
-- 12 (a number follows the comma pair), as the rule above says.
--
-- ---------------------------------------------------------------------------
-- Beyond the SPEC's list (for the Store, Pins and runtime)
-- ---------------------------------------------------------------------------
--   G.SameLandmass(env, a, b, instA, instB)  optional instances override the
--        per-map probe (the player's from UnitPosition); G.Landmass(env, map,
--        instance) is the key it compares, G.Instance(env, map) the probe.
--   G.MapDistance(env, mapA, xA, yA, mapB, xB, yB) -> yards | nil (no line)
--   G.CheckPosition(map, x, y) -> true | nil, "map" | "x" | "y"
--   G.FormatDistance(yards, units, metric): `metric` decides what AUTO means.
--   G.MinimapRadius(zoom, indoors), G.MinimapIndoors(zoom, cvarZoom,
--        cvarInsideZoom, isIndoors): the radius without C_Minimap.
--   G.EtaReset(state); the ETA state resets itself when state.target changes.
--   G.ZoneIndex(env, aliases), G.MatchZone(index, text), G.MakeResolver(index),
--        G.WayUsage(topic): the /way resolver and its usage lines.
--   G.Normalize(a), G.IsFinite(v), G.MAP_TYPE, G.COSMIC_MAP, G.ClearCache(env).
--
-- Added in 3.1 (SPEC 1-2):
--   env.islands = { [uiMap] = "name" } (optional): a map at or under one of
--        these is an island of its continent's frame, and G.Landmass appends
--        ":name" to its key ("1414:1:teldrassil"), so no straight line is
--        drawn across the sea to it (deferred H2). The runtime passes
--        Data.ISLANDS; without the field every key is as before.
--   G.Zone(env, map) -> the Zone-type map at or above map (a dungeon, micro
--        or orphan map climbs to its zone; World and Continent maps have
--        none): Follow the Closest's "my zone" scope compares these.
--   G.PlainText(s): a string with every UI escape gone (colours, links keep
--        their text, textures, atlases) and no | or control character left.
--   G.ChatText(map, x01, y01, title, zoneName, decimals): the readable line
--        a player without addons can use, "Title - Hellfire Peninsula 45.2,
--        66.8 (/way #1944 45.20 66.80)", never starting with "/" (a pasted
--        line starting with /way runs locally instead of being sent) and at
--        most 255 bytes (the chat limit; the title is cut first).
--   G.ChatLink(map, x01, y01, title, text) -> the local chat link
--        "|cff71d5ff|Haddon:CommanderOrders:w:<map>:<x %.4f>:<y %.4f>:<title
--        %XX-escaped>|h[<text or Go>]|h|r"; G.ParseChatLink(link) reads the
--        whole link or just its "addon:..." payload back into map, x, y,
--        title. G.LinkEscape / G.LinkUnescape are the %XX escaping (%, :, |,
--        [, ] and control characters). G.LINK_PREFIX = "addon:CommanderOrders:".

CommanderOrders = CommanderOrders or {}
local O = CommanderOrders
O.Geo = O.Geo or {}
local G = O.Geo

local sqrt, atan2, sin, cos, exp = math.sqrt, math.atan2, math.sin, math.cos, math.exp
local floor, ceil, abs, max, min = math.floor, math.ceil, math.abs, math.max, math.min
local PI = math.pi
local TWO_PI = 2 * math.pi
local HUGE = math.huge
local format, strlower, strsub, strfind = string.format, string.lower, string.sub, string.find
local type, pairs, ipairs, pcall, tonumber, tostring = type, pairs, ipairs, pcall, tonumber, tostring
local setmetatable = setmetatable
local tconcat, tsort = table.concat, table.sort

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------
-- Enum.UIMapType on 2.5.6 (MapConstantsDocumentation), spelled out so this
-- file loads with nothing attached
G.MAP_TYPE = { COSMIC = 0, WORLD = 1, CONTINENT = 2, ZONE = 3, DUNGEON = 4, MICRO = 5, ORPHAN = 6 }
local MAP_COSMIC, MAP_WORLD, MAP_CONTINENT, MAP_ZONE = 0, 1, 2, 3
G.COSMIC_MAP = 946                  -- the root every zone is reachable from
local MAX_DEPTH = 16                -- map-tree walks stop here (cycle guard)
local EDGE_FRACTION = 0.9           -- minimap pins ride a rim at 90% of the radius
local INSIDE_EPSILON = 1e-9         -- tolerance for "inside a map's 0..1 square"
local YARD_IN_METRES = 0.9144

-- Minimap diameter in yards per zoom level (index = Minimap:GetZoom() + 1).
-- Game data; see trap 6 for the corrected fourth outdoor value.
G.MINIMAP_DIAMETERS = {
    indoor = { 300, 240, 180, 120, 80, 50 },
    outdoor = { 1400 / 3, 400, 1000 / 3, 800 / 3, 200, 400 / 3 },
}

-- Which quadrants of each GetMinimapShape() answer keep the round rim, in
-- the order upper-left, lower-left, upper-right, lower-right. A quadrant
-- that is not round clamps to the square. Unknown names are fully round.
local SHAPE_ROUND = {
    ROUND = { true, true, true, true },
    SQUARE = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { true, false, false, false },
    ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"] = { false, false, false, true },
    ["SIDE-LEFT"] = { true, true, false, false },
    ["SIDE-RIGHT"] = { false, false, true, true },
    ["SIDE-TOP"] = { true, false, true, false },
    ["SIDE-BOTTOM"] = { false, true, false, true },
    ["TRICORNER-TOPLEFT"] = { true, true, true, false },
    ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { false, true, true, true },
}

-- ETA filter tuning
local ETA_TAU = 1.0                 -- seconds: speed and closing-rate smoothing
local ETA_MIN_SPEED = 0.5           -- yd/s: slower than this is standing still
local ETA_CLOSING_FRACTION = 0.15   -- closing slower than 15% of speed = not heading there
local ETA_JUMP_YARDS = 100          -- a distance step this far beyond any travel = new target
local ETA_MAX_SPEED = 60            -- yd/s: faster than any mount or taxi on this client

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------
local function IsFinite(v)
    return type(v) == "number" and v == v and v ~= HUGE and v ~= -HUGE
end
G.IsFinite = IsFinite

-- Into (-pi, pi]
local function Normalize(a)
    a = a - TWO_PI * ceil((a - PI) / TWO_PI)
    if a <= -PI then a = a + TWO_PI elseif a > PI then a = a - TWO_PI end
    return a
end

local function Trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- pcall an env function and pass its results through; nil on error
local function Pass(ok, ...)
    if ok then return ... end
    return nil
end
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    return Pass(pcall(fn, ...))
end

local function MapInfo(env, id)
    if type(env) ~= "table" or type(id) ~= "number" then return nil end
    local info = Call(env.mapInfo, id)
    if type(info) ~= "table" or type(info.mapType) ~= "number" then return nil end
    return info
end

-- Per-env caches, keyed weakly so a discarded env takes its cache with it
local CACHES = setmetatable({}, { __mode = "k" })
local function Cache(env)
    local c = CACHES[env]
    if not c then
        c = { continent = {}, root = {}, instance = {}, zone = {}, island = {} }
        CACHES[env] = c
    end
    return c
end

function G.ClearCache(env)
    if env ~= nil then CACHES[env] = nil end
end

-- ---------------------------------------------------------------------------
-- Distance, bearing, relative angle
-- ---------------------------------------------------------------------------
function G.Distance(n1, w1, n2, w2)
    if not (IsFinite(n1) and IsFinite(w1) and IsFinite(n2) and IsFinite(w2)) then return nil end
    local dn, dw = n2 - n1, w2 - w1
    return sqrt(dn * dn + dw * dw)
end

-- Radians in [0, 2pi), counter-clockwise from north: the convention of
-- GetPlayerFacing(), so (bearing - facing) is the arrow's screen rotation.
function G.Bearing(nP, wP, nT, wT)
    if not (IsFinite(nP) and IsFinite(wP) and IsFinite(nT) and IsFinite(wT)) then return nil end
    local b = atan2(wT - wP, nT - nP)
    if b < 0 then b = b + TWO_PI end
    if b >= TWO_PI then b = b - TWO_PI end
    return b
end

function G.Normalize(a)
    if not IsFinite(a) then return nil end
    return Normalize(a)
end

-- (-pi, pi]: positive = the target is to the left (counter-clockwise), which
-- is also the sense of Texture:SetRotation on an up-pointing arrow
function G.Relative(bearing, facing)
    if not (IsFinite(bearing) and IsFinite(facing)) then return nil end
    return Normalize(bearing - facing)
end

-- 1 = dead ahead, 0.5 = square to the side, 0 = directly behind
function G.Alignment(rel)
    if not IsFinite(rel) then return nil end
    local a = 1 - abs(Normalize(rel)) / PI
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    return a
end

-- ---------------------------------------------------------------------------
-- Positions
-- ---------------------------------------------------------------------------
-- A waypoint position is { map = uiMapID, x = 0..1, y = 0..1 }. Returns true,
-- or nil and a reason word the Store and the API can hand back.
function G.CheckPosition(map, x, y)
    if type(map) ~= "number" or not IsFinite(map) or map <= 0 or map ~= floor(map) then
        return nil, "map"
    end
    if not IsFinite(x) or x < 0 or x > 1 then return nil, "x" end
    if not IsFinite(y) or y < 0 or y > 1 then return nil, "y" end
    return true
end

-- Map coordinates to world yards: instance, north, west, or nil when the map
-- has no world data at that point (Cosmic, ocean on Azeroth, the duplicate
-- raid maps) or the client call fails.
function G.ToWorld(env, map, x, y)
    if type(env) ~= "table" or type(map) ~= "number" or not IsFinite(x) or not IsFinite(y) then
        return nil
    end
    local instance, a, b = Call(env.worldPos, map, x, y)
    local north, west = a, b
    if type(a) == "table" then
        north, west = a.x, a.y
    elseif type(a) == "userdata" then
        north = Pass(pcall(function() return a.x end))
        west = Pass(pcall(function() return a.y end))
    end
    if not (IsFinite(instance) and IsFinite(north) and IsFinite(west)) then return nil end
    return instance, north, west
end

-- Yards between two map positions, or nil when no straight line exists
-- (different instance or landmass, or no world data)
function G.MapDistance(env, mapA, xA, yA, mapB, xB, yB)
    local iA, nA, wA = G.ToWorld(env, mapA, xA, yA)
    if not iA then return nil end
    local iB, nB, wB = G.ToWorld(env, mapB, xB, yB)
    if not iB or iA ~= iB then return nil end
    if not G.SameLandmass(env, mapA, mapB, iA, iB) then return nil end
    return G.Distance(nA, wA, nB, wB)
end

-- ---------------------------------------------------------------------------
-- The map tree: continent, instance, landmass
-- ---------------------------------------------------------------------------
-- One walk answers both: the first Continent-type ancestor (self included),
-- and, failing that, the top-most ancestor that is not World or Cosmic (a
-- battleground map hangs straight off Azeroth and is its own landmass).
local function Walk(env, map)
    local id, depth, top = map, 0, nil
    while type(id) == "number" and id > 0 and depth < MAX_DEPTH do
        local info = MapInfo(env, id)
        if not info then break end
        local t = info.mapType
        if t == MAP_CONTINENT then return id, id end
        if t ~= MAP_COSMIC and t ~= MAP_WORLD then top = id end
        id = info.parentMapID
        depth = depth + 1
    end
    return nil, top
end

local function Roots(env, map)
    local c = Cache(env)
    local cont = c.continent[map]
    if cont == nil then
        local continent, root = Walk(env, map)
        c.continent[map] = continent or false
        c.root[map] = root or false
        cont = continent or false
    end
    return cont or nil, c.root[map] or nil
end

function G.Continent(env, map)
    if type(env) ~= "table" or type(map) ~= "number" then return nil end
    local continent = Roots(env, map)
    return continent
end

-- The world instance a map's coordinates live in, probed at a few points
-- (Azeroth's centre is ocean). Continent maps answer their main frame.
local PROBES = { { 0.5, 0.5 }, { 0.25, 0.25 }, { 0.75, 0.75 }, { 0.25, 0.75 }, { 0.75, 0.25 } }
function G.Instance(env, map)
    if type(env) ~= "table" or type(map) ~= "number" then return nil end
    local c = Cache(env)
    local known = c.instance[map]
    if known == nil then
        known = false
        for _, p in ipairs(PROBES) do
            local instance = G.ToWorld(env, map, p[1], p[2])
            if instance then known = instance; break end
        end
        c.instance[map] = known
    end
    return known or nil
end

-- A string key: equal keys = an arrow can point from one to the other.
-- `instance` overrides the probe (the runtime knows the player's from
-- UnitPosition and a waypoint's from G.ToWorld). With no worldPos in the env
-- at all, the continent alone decides (so a pure Store harness can group by
-- landmass); with worldPos present but no answer, the map has no world data
-- and there is no landmass.
-- The island a map lies on (env.islands, 3.1), self first, up to its
-- continent: a name, or nil. Cached per env like the other tree answers.
local function IslandOf(env, map)
    local islands = env.islands
    if type(islands) ~= "table" then return nil end
    local c = Cache(env)
    local known = c.island[map]
    if known == nil then
        known = false
        local id, depth = map, 0
        while type(id) == "number" and id > 0 and depth < MAX_DEPTH do
            local name = islands[id]
            if type(name) == "string" and name ~= "" then known = name break end
            local info = MapInfo(env, id)
            if not info or info.mapType <= MAP_CONTINENT then break end
            id = info.parentMapID
            depth = depth + 1
        end
        c.island[map] = known
    end
    return known or nil
end

function G.Landmass(env, map, instance)
    if type(env) ~= "table" or type(map) ~= "number" then return nil end
    local continent, root = Roots(env, map)
    local base = continent or root
    if not base then return nil end
    local island = IslandOf(env, map)
    local tail = island and (":" .. island) or ""
    if instance == nil then
        if type(env.worldPos) ~= "function" then return tostring(base) .. ":?" .. tail end
        instance = G.Instance(env, map)
        if instance == nil then return nil end
    end
    return tostring(base) .. ":" .. tostring(instance) .. tail
end

-- The zone a map belongs to (3.1): itself when it is a Zone map, else the
-- first Zone-type ancestor of a dungeon, micro or orphan map; nil for the
-- World, Continent and Cosmic maps and for anything unknown.
function G.Zone(env, map)
    if type(env) ~= "table" or type(map) ~= "number" then return nil end
    local c = Cache(env)
    local known = c.zone[map]
    if known == nil then
        known = false
        local id, depth = map, 0
        while type(id) == "number" and id > 0 and depth < MAX_DEPTH do
            local info = MapInfo(env, id)
            if not info then break end
            if info.mapType == MAP_ZONE then known = id break end
            if info.mapType <= MAP_CONTINENT then break end
            id = info.parentMapID
            depth = depth + 1
        end
        c.zone[map] = known
    end
    return known or nil
end

function G.SameLandmass(env, mapA, mapB, instA, instB)
    local a = G.Landmass(env, mapA, instA)
    if not a then return false end
    local b = G.Landmass(env, mapB, instB)
    return a == b
end

-- ---------------------------------------------------------------------------
-- Map-space projection (GetMapRectOnMap lerps)
-- ---------------------------------------------------------------------------
-- The chain from a map up to the root, self first, plus its index set
local function Ancestors(env, map)
    local list, set = {}, {}
    local id, depth = map, 0
    while type(id) == "number" and id > 0 and not set[id] and depth < MAX_DEPTH do
        list[#list + 1] = id
        set[id] = #list
        local info = MapInfo(env, id)
        if not info then break end
        id = info.parentMapID
        depth = depth + 1
    end
    return list, set
end

local function GoodRect(l, r, t, b)
    return IsFinite(l) and IsFinite(r) and IsFinite(t) and IsFinite(b) and r ~= l and b ~= t
end

-- The rect of `child` on its ancestor `top`: asked directly, else composed
-- one parent step at a time (the client answers any ancestor; the fallback
-- covers a step it refuses)
local function RectOn(env, child, top, chain)
    if child == top then return 0, 1, 0, 1 end
    local l, r, t, b = Call(env.rectOnMap, child, top)
    if GoodRect(l, r, t, b) then return l, r, t, b end
    chain = chain or Ancestors(env, child)
    l, r, t, b = 0, 1, 0, 1
    for i = 1, #chain - 1 do
        local l2, r2, t2, b2 = Call(env.rectOnMap, chain[i], chain[i + 1])
        if not GoodRect(l2, r2, t2, b2) then return nil end
        local w, h = r2 - l2, b2 - t2
        l, r, t, b = l2 + l * w, l2 + r * w, t2 + t * h, t2 + b * h
        if chain[i + 1] == top then return l, r, t, b end
    end
    return nil
end

local function Inside(x, y)
    return x >= -INSIDE_EPSILON and x <= 1 + INSIDE_EPSILON and y >= -INSIDE_EPSILON and y <= 1 + INSIDE_EPSILON
end

-- A point on `map` expressed on `targetMap`. Up to an ancestor: always (the
-- answer may fall a little outside 0..1 where a zone overhangs its parent).
-- Down to a descendant, or across through the common ancestor: only when
-- the point lies inside the target, else nil.
function G.ProjectToMap(env, map, x, y, targetMap)
    if type(env) ~= "table" or type(map) ~= "number" or type(targetMap) ~= "number" then return nil end
    if not IsFinite(x) or not IsFinite(y) then return nil end
    if map == targetMap then return x, y end
    local up, upSet = Ancestors(env, map)
    local common
    if upSet[targetMap] then
        common = targetMap
    else
        local down = Ancestors(env, targetMap)
        for _, id in ipairs(down) do
            if upSet[id] then common = id; break end
        end
    end
    if not common then return nil end
    local cx, cy = x, y
    if common ~= map then
        local l, r, t, b = RectOn(env, map, common, up)
        if not l then return nil end
        cx, cy = l + x * (r - l), t + y * (b - t)
    end
    if common == targetMap then return cx, cy end
    local l, r, t, b = RectOn(env, targetMap, common)
    if not l then return nil end
    local tx, ty = (cx - l) / (r - l), (cy - t) / (b - t)
    if not Inside(tx, ty) then return nil end
    return tx, ty
end

-- A click on a world or continent map, resolved to the zone under it:
-- childMap, cx, cy in that zone's coordinates, or nil when no zone is there
-- (ocean, or a map the client has no hit data for). A zone, dungeon or any
-- deeper map is already as deep as a waypoint goes and answers itself; a
-- descent never enters a dungeon or micro map, which would be another
-- instance.
--
-- GetMapInfoAtPosition only names the map under the cursor; the zone's
-- coordinates always come from the zone's OWN rectangle on the map the user
-- clicked (what the client draws there), and that rectangle must contain
-- the click. That matters on Azeroth (947): the DB2 places the 530 starting
-- zones on it through their own sub-rectangle, which does not line up with
-- the Eastern Kingdoms rectangle, so lerping the click into EK first and
-- then into the zone would land Quel'Thalas clicks somewhere else. A click
-- whose chain disagrees with the zone's own rectangle is refused, never
-- guessed.
function G.ZoneAt(env, map, x, y)
    if type(env) ~= "table" or type(map) ~= "number" or not IsFinite(x) or not IsFinite(y) then return nil end
    local info = MapInfo(env, map)
    if not info then return nil end
    if info.mapType >= MAP_ZONE then return map, x, y end
    local cur, cx, cy = map, x, y
    for _ = 1, 4 do
        local child = Call(env.mapInfoAtPosition, cur, cx, cy)
        if type(child) ~= "table" or type(child.mapID) ~= "number" or child.mapID == cur then return nil end
        local t = child.mapType
        if t == MAP_ZONE then
            local l, r, tp, b = RectOn(env, child.mapID, map)
            if not l then return nil end
            local zx, zy = (x - l) / (r - l), (y - tp) / (b - tp)
            if not Inside(zx, zy) then return nil end
            return child.mapID, min(max(zx, 0), 1), min(max(zy, 0), 1)
        end
        if t ~= MAP_WORLD and t ~= MAP_CONTINENT then return nil end
        local l, r, tp, b = RectOn(env, child.mapID, cur)
        if not l then return nil end
        local nx, ny = (cx - l) / (r - l), (cy - tp) / (b - tp)
        if not Inside(nx, ny) then return nil end
        cur, cx, cy = child.mapID, nx, ny
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Minimap
-- ---------------------------------------------------------------------------
-- Radius in yards for a zoom level (0..5) and mode
function G.MinimapRadius(zoom, indoors)
    local z = floor(tonumber(zoom) or 0)
    if z < 0 then z = 0 elseif z > 5 then z = 5 end
    local tbl = indoors and G.MINIMAP_DIAMETERS.indoor or G.MINIMAP_DIAMETERS.outdoor
    return tbl[z + 1] / 2
end

-- Indoors or out, without nudging Minimap:SetZoom: the minimap keeps one
-- zoom per mode in the CVars minimapZoom (outdoor) and minimapInsideZoom
-- (indoor), so the current zoom names the mode unless both CVars hold the
-- same value, when IsIndoors() breaks the tie.
function G.MinimapIndoors(zoom, cvarZoom, cvarInsideZoom, isIndoors)
    local z, outdoor, inside = tonumber(zoom), tonumber(cvarZoom), tonumber(cvarInsideZoom)
    if z ~= nil and outdoor ~= nil and inside ~= nil and outdoor ~= inside then
        if z == outdoor then return false end
        if z == inside then return true end
    end
    return isIndoors and true or false
end

-- dN = targetN - playerN, dW = targetW - playerW (yards). Returns pixel
-- offsets from the minimap centre (screen right and up positive, for
-- SetPoint("CENTER", Minimap, "CENTER", px, py)), whether the pin was
-- clamped onto the rim, and the screen angle of the direction
-- (counter-clockwise from up: SetRotation for an up-pointing edge chevron).
-- rotate = the rotateMinimap CVar: the player's facing is then screen up.
-- shape = GetMinimapShape() or nil (round). halfW/halfH = half the minimap's
-- width and height in its own units (default 70, the stock 140 px map;
-- halfH defaults to halfW); Minimap's scale is inherited by its children.
function G.MinimapPlace(dN, dW, radiusYards, facing, rotate, shape, halfW, halfH)
    if not (IsFinite(dN) and IsFinite(dW) and IsFinite(radiusYards)) or radiusYards <= 0 then return nil end
    if not IsFinite(halfW) or halfW <= 0 then halfW = 70 end
    if not IsFinite(halfH) or halfH <= 0 then halfH = halfW end
    local right, up = -dW, dN               -- east is screen right, north is screen up
    if rotate then
        if not IsFinite(facing) then return nil end
        local c, s = cos(facing), sin(facing)
        right, up = right * c + up * s, up * c - right * s
    end
    local nx, ny = right / radiusYards, up / radiusYards
    local quadrants = SHAPE_ROUND[shape or "ROUND"] or SHAPE_ROUND.ROUND
    local round = true
    if nx ~= 0 and ny ~= 0 then
        local index = (nx < 0) and 1 or 3       -- left column, right column
        if ny < 0 then index = index + 1 end    -- lower row
        round = quadrants[index]
    end
    local d
    if round then d = nx * nx + ny * ny else d = max(nx * nx, ny * ny) end
    d = d / (EDGE_FRACTION * EDGE_FRACTION)
    local onEdge = d > 1
    if onEdge then
        local k = 1 / sqrt(d)
        nx, ny = nx * k, ny * k
    end
    return nx * halfW, ny * halfH, onEdge, atan2(-nx, ny)
end

-- ---------------------------------------------------------------------------
-- Filters
-- ---------------------------------------------------------------------------
-- A critically damped follower on the circle. The error is always taken the
-- short way round (Normalize), so crossing +-pi never swings the arrow the
-- long way; the step is the exact solution of the critically damped spring
-- over dt (x(t) = (x0 + (v0 + w x0) t) e^-wt, w = 2 / tau), so it is stable
-- at any frame time and lands on the target after a long hitch, and it never
-- overshoots the target it was chasing this frame. tau is the smoothing time
-- in seconds (about 0.1 for an arrow); tau <= 0 or a first call snaps. A nil
-- target (no heading) resets and answers nil.
function G.AngleFilter(state, target, dt, tau)
    if type(state) ~= "table" then return IsFinite(target) and Normalize(target) or nil end
    if not IsFinite(target) then
        state.value, state.velocity = nil, 0
        return nil
    end
    target = Normalize(target)
    local value = state.value
    if value == nil or not IsFinite(tau) or tau <= 0 then
        state.value, state.velocity = target, 0
        return target
    end
    dt = tonumber(dt) or 0
    if dt <= 0 then return value end
    local err = Normalize(target - value)
    local goal = value + err
    local w = 2 / tau
    local x0 = value - goal
    local v0 = state.velocity or 0
    local e = exp(-w * dt)
    local c = v0 + w * x0
    local out = goal + (x0 + c * dt) * e
    local v = (v0 - w * c * dt) * e
    if (goal - value > 0) == (out > goal) then
        out, v = goal, 0
    end
    state.value, state.velocity = Normalize(out), v
    return state.value
end

function G.EtaReset(state)
    if type(state) ~= "table" then return end
    state.lastDist, state.speed, state.closing, state.eta = nil, nil, nil, nil
end

-- Seconds to arrival, or nil when there is no honest answer (standing
-- still, walking away or square to the target, no distance). The speed is
-- the player's own ground speed (GetUnitSpeed, passed as speedHint) smoothed
-- over about a second; the first call is seeded from it so the ETA appears
-- at once. A closing-rate average decides whether the player is heading
-- there at all. Without a speedHint the closing rate is the speed. The
-- filter resets itself when the caller changes state.target (write the
-- waypoint's uid there) and when the distance jumps further than any mount
-- could travel in dt (a teleport, or the target moved).
function G.EtaFilter(state, distance, dt, speedHint)
    if type(state) ~= "table" then return nil end
    if state.target ~= state.etaTarget then
        G.EtaReset(state)
        state.etaTarget = state.target
    end
    if not IsFinite(distance) or distance < 0 then
        G.EtaReset(state)
        return nil
    end
    local hint = (IsFinite(speedHint) and speedHint >= 0) and speedHint or nil
    dt = tonumber(dt) or 0
    local last = state.lastDist
    if last ~= nil and dt > 0 and abs(distance - last) > ETA_JUMP_YARDS + ETA_MAX_SPEED * dt then
        G.EtaReset(state)
        last = nil
    end
    if last == nil then
        state.lastDist, state.speed, state.closing = distance, hint, nil
        if hint and hint >= ETA_MIN_SPEED then
            state.eta = distance / hint
        else
            state.eta = nil
        end
        return state.eta
    end
    if dt <= 0 then return state.eta end
    local a = 1 - exp(-dt / ETA_TAU)
    local rate = (last - distance) / dt
    state.closing = state.closing and (state.closing + (rate - state.closing) * a) or rate
    if hint then
        state.speed = state.speed and (state.speed + (hint - state.speed) * a) or hint
    else
        state.speed = nil
    end
    state.lastDist = distance
    local speed = state.speed or state.closing
    if (hint and hint < ETA_MIN_SPEED) or not speed or speed < ETA_MIN_SPEED
        or state.closing < ETA_CLOSING_FRACTION * speed then
        state.eta = nil
        return nil
    end
    state.eta = distance / speed
    return state.eta
end

-- ---------------------------------------------------------------------------
-- Formatting
-- ---------------------------------------------------------------------------
local function Separate(n)
    local s = tostring(n)
    local k
    repeat
        s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    until k == 0
    return s
end

-- units: "YARDS" | "METRES" | "AUTO". AUTO is the game's own unit (yards)
-- unless the optional `metric` is true: the runtime decides that from the
-- region or locale (TomTom's rule: metres outside the US region).
function G.FormatDistance(yards, units, metric)
    if not IsFinite(yards) or yards < 0 then return nil end
    if units == "METRES" or (units == "AUTO" and metric) then
        local m = yards * YARD_IN_METRES
        if m < 999.5 then return format("%d m", floor(m + 0.5)) end
        local km = m / 1000
        if km < 99.95 then return format("%.1f km", km) end
        return format("%s km", Separate(floor(km + 0.5)))
    end
    return format("%s yd", Separate(floor(yards + 0.5)))
end

-- "45s", "3m 05s", "1h 12m"; nil for nothing, negative, or over 99 hours
function G.FormatEta(seconds)
    if not IsFinite(seconds) or seconds < 0 then return nil end
    local s = floor(seconds + 0.5)
    if s >= 99 * 3600 then return nil end
    if s < 60 then return format("%ds", s) end
    if s < 3600 then return format("%dm %02ds", floor(s / 60), s % 60) end
    return format("%dh %02dm", floor(s / 3600), floor((s % 3600) / 60))
end

-- "45.2, 66.8" from 0..1 coordinates; decimals 0..3 (default 1)
function G.FormatCoords(x01, y01, decimals)
    if not IsFinite(x01) or not IsFinite(y01) then return nil end
    local d = floor(tonumber(decimals) or 1)
    if d < 0 then d = 0 elseif d > 3 then d = 3 end
    local f = "%." .. d .. "f"
    return format(f .. ", " .. f, x01 * 100, y01 * 100)
end

local function CleanTitle(title)
    if type(title) ~= "string" then return nil end
    title = Trim(title:gsub("[%c]+", " "))
    if title == "" then return nil end
    return title
end

-- "/way #1944 45.20 66.80 Title" (no "#id" when map is nil: the current-zone form)
function G.WayLine(map, x01, y01, title)
    if not IsFinite(x01) or not IsFinite(y01) then return nil end
    local line
    if type(map) == "number" and IsFinite(map) then
        line = format("/way #%d %.2f %.2f", map, x01 * 100, y01 * 100)
    else
        line = format("/way %.2f %.2f", x01 * 100, y01 * 100)
    end
    title = CleanTitle(title)
    if title then line = line .. " " .. title end
    return line
end

-- ---------------------------------------------------------------------------
-- Words for chat (3.1): the readable line, the local link
-- ---------------------------------------------------------------------------
G.LINK_PREFIX = "addon:CommanderOrders:"
local LINK_COLOUR = "ff71d5ff"          -- Commander_Ping's link colour
local CHAT_MAX = 255                    -- bytes a chat message may carry
local LINK_TITLE_MAX = 120              -- bytes of title in a link (the share wire's cap)

-- Cut to n bytes on a UTF-8 boundary (no "..." here: a title in a line or a
-- payload is cut, not elided)
local function CutBytes(s, n)
    if #s <= n then return s end
    local cut = n
    while cut > 0 do
        local b = s:byte(cut + 1)
        if not b or b < 0x80 or b >= 0xC0 then break end
        cut = cut - 1
    end
    return s:sub(1, cut)
end

-- Every UI escape out of a string: a colour goes, a link keeps its text, a
-- texture, atlas or kstring goes whole, |n is a space, and any | or control
-- character left over is dropped (a | in a chat message is refused by the
-- server; one on screen starts an escape)
function G.PlainText(s)
    if type(s) == "number" then s = tostring(s) end
    if type(s) ~= "string" then return "" end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|K.-|k", "")
    s = s:gsub("|n", " ")
    s = s:gsub("[|%c]", " ")
    return Trim((s:gsub("%s%s+", " ")))
end

function G.LinkEscape(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("[%%:|%[%]%c]", function(ch) return format("%%%02X", ch:byte()) end))
end

function G.LinkUnescape(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

local function ValidPlace(map, x01, y01)
    return IsFinite(map) and map > 0 and map == floor(map)
        and IsFinite(x01) and x01 >= 0 and x01 <= 1 and IsFinite(y01) and y01 >= 0 and y01 <= 1
end

-- "Title - Hellfire Peninsula 45.2, 66.8 (/way #1944 45.20 66.80)". zoneName
-- may be nil (then just the numbers), title may be nil (then the zone
-- leads). decimals is the readable pair's precision (the /way part is
-- always 2 dp). Never starts with "/", never longer than 255 bytes.
function G.ChatText(map, x01, y01, title, zoneName, decimals)
    if not ValidPlace(map, x01, y01) then return nil end
    local coords = G.FormatCoords(x01, y01, decimals or 1)
    local way = format("(/way #%d %.2f %.2f)", map, x01 * 100, y01 * 100)
    local zone = G.PlainText(zoneName)
    local place = (zone ~= "" and (zone .. " ") or "") .. coords
    local t = G.PlainText(title):gsub("^[/%s]+", "")
    local tail = place .. " " .. way
    if t == "" then return CutBytes(tail, CHAT_MAX) end
    local room = CHAT_MAX - #tail - 3
    if room < 1 then return CutBytes(tail, CHAT_MAX) end
    t = Trim(CutBytes(t, room))
    if t == "" then return tail end
    return t .. " - " .. tail
end

-- The local link. Links never leave this client (Blizzard's addon link
-- handler: "local links only"); what is sent is ChatText.
function G.ChatLink(map, x01, y01, title, text)
    if not ValidPlace(map, x01, y01) then return nil end
    local t = CutBytes(G.PlainText(title), LINK_TITLE_MAX)
    local shown = G.PlainText(text):gsub("[%[%]]", "")
    if shown == "" then shown = "Go" end
    return format("|c%s|H%sw:%d:%.4f:%.4f:%s|h[%s]|h|r", LINK_COLOUR, G.LINK_PREFIX, map, x01, y01,
        G.LinkEscape(t), shown)
end

-- map, x01, y01, title (nil when it had none) from a ChatLink or from the
-- "addon:CommanderOrders:w:..." payload SetItemRef hands over; nil for
-- anything else
function G.ParseChatLink(link)
    if type(link) ~= "string" then return nil end
    local payload = link
    if strfind(link, "|H", 1, true) then payload = link:match("|H(.-)|h") end
    if type(payload) ~= "string" then return nil end
    local m, xs, ys, rest = payload:match("^addon:CommanderOrders:w:(%d+):([%d%.]+):([%d%.]+):?(.*)$")
    local map, x, y = tonumber(m), tonumber(xs), tonumber(ys)
    if not (map and ValidPlace(map, x, y)) then return nil end
    local title = G.LinkUnescape(rest or "")
    if title == "" then title = nil end
    return map, x, y, title
end

-- ---------------------------------------------------------------------------
-- Zone names
-- ---------------------------------------------------------------------------
-- Lowercase; drop spaces, punctuation and typographic apostrophes, so
-- "Quel'Danas", "quel danas" and the same name typed with a U+2019 apostrophe
-- all fold to "queldanas". Only ASCII letters change case (the client locale is enUS; a localized name
-- folds the same way on both sides, accents and all).
function G.FoldName(s)
    if type(s) ~= "string" then return "" end
    s = strlower(s)
    s = s:gsub("\226\128[\152\153]", "")
    s = s:gsub("[%s%p]", "")
    return s
end

-- The name index /way resolves against: every Zone and Continent map
-- reachable from Cosmic (946) through env.mapChildren. Dungeon, micro and
-- orphan maps stay out (they are reachable by "#id" only), and so do the
-- legacy parentless continent duplicates (987, 1463, 1464), which the walk
-- never reaches. `aliases` = { [alias] = uiMapID } (keys folded here; a
-- string value is looked up as an exact zone name). `names` records every
-- visited map's name, dungeons included, for "#id" messages.
function G.ZoneIndex(env, aliases, root)
    local index = { entries = {}, byFolded = {}, aliases = {}, names = {} }
    local seen = {}
    local function Add(info)
        local folded = G.FoldName(info.name)
        if folded == "" then return end
        local entry = { map = info.mapID, name = info.name, folded = folded, mapType = info.mapType }
        index.entries[#index.entries + 1] = entry
        local list = index.byFolded[folded]
        if not list then
            list = {}
            index.byFolded[folded] = list
        end
        list[#list + 1] = entry
    end
    local function Visit(id, depth)
        if depth > MAX_DEPTH or seen[id] then return end
        seen[id] = true
        local kids = type(env) == "table" and Call(env.mapChildren, id)
        if type(kids) ~= "table" then return end
        for _, info in ipairs(kids) do
            if type(info) == "table" and type(info.mapID) == "number" and not seen[info.mapID] then
                local t = info.mapType
                if type(info.name) == "string" then index.names[info.mapID] = info.name end
                if (t == MAP_ZONE or t == MAP_CONTINENT) and type(info.name) == "string" then
                    Add(info)
                end
                if t == MAP_WORLD or t == MAP_CONTINENT or t == MAP_ZONE then
                    Visit(info.mapID, depth + 1)
                end
            end
        end
    end
    Visit(root or G.COSMIC_MAP, 0)
    tsort(index.entries, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.map < b.map
    end)
    for alias, value in pairs(aliases or {}) do
        local key = G.FoldName(alias)
        if key ~= "" then
            if type(value) == "number" then
                index.aliases[key] = value
            elseif type(value) == "string" then
                local hits = index.byFolded[G.FoldName(value)]
                if hits and #hits == 1 then index.aliases[key] = hits[1].map end
            end
        end
    end
    return index
end

local function Candidates(list)
    local out = {}
    for i, e in ipairs(list) do out[i] = { map = e.map, name = e.name } end
    return out
end

-- exact name > alias > prefix > substring (3+ characters), all on folded
-- text with plain finds. One hit in the first tier that has any wins; two or
-- more is ambiguous and comes back as candidates (sorted by name).
function G.MatchZone(index, text)
    if type(index) ~= "table" or type(text) ~= "string" then return nil, {} end
    local q = G.FoldName(text)
    if q == "" then return nil, {} end
    local exact = index.byFolded and index.byFolded[q]
    if exact then
        if #exact == 1 then return exact[1].map, {} end
        return nil, Candidates(exact)
    end
    local alias = index.aliases and index.aliases[q]
    if alias then return alias, {} end
    local entries = index.entries or {}
    local hits = {}
    local n = #q
    for _, e in ipairs(entries) do
        if strsub(e.folded, 1, n) == q then hits[#hits + 1] = e end
    end
    if #hits == 0 and n >= 3 then
        for _, e in ipairs(entries) do
            if strfind(e.folded, q, 1, true) then hits[#hits + 1] = e end
        end
    end
    if #hits == 1 then return hits[1].map, {} end
    if #hits > 1 then return nil, Candidates(hits) end
    return nil, {}
end

function G.MakeResolver(index)
    return function(text) return G.MatchZone(index, text) end
end

-- ---------------------------------------------------------------------------
-- The /way grammar (shape documented at the top of this file)
-- ---------------------------------------------------------------------------
local WAY_WORDS = { way = true, tway = true, tomtomway = true }
local MAX_LISTED = 8

-- Tokens with their positions in `body`, so a title keeps its own spacing
local function Tokens(body)
    local out, pos = {}, 1
    while true do
        local s, e = strfind(body, "%S+", pos)
        if not s then break end
        out[#out + 1] = { text = strsub(body, s, e), s = s, e = e }
        pos = e + 1
    end
    return out
end

-- What a token is as a number: "ONE" (n1), "COMMA" (two whole numbers
-- joined by a comma: n1, n2, or the decimal `dec`), "PAIR" (n1, n2), or nil.
-- One trailing "," or ";" is a separator and is dropped first.
local function Classify(tok)
    if type(tok) ~= "string" then return nil end
    local core = tok:gsub("[,;]$", "")
    if core:match("^%-?%d+%.?%d*$") or core:match("^%-?%.%d+$") then
        return { kind = "ONE", n1 = tonumber(core) }
    end
    local a, b = core:match("^(%d+),(%d+)$")
    if a then
        return { kind = "COMMA", n1 = tonumber(a), n2 = tonumber(b), dec = tonumber(a .. "." .. b) }
    end
    local p, q = core:match("^(%d*%.?%d+)[,;](%d*%.?%d+)$")
    if p and tonumber(p) and tonumber(q) then
        return { kind = "PAIR", n1 = tonumber(p), n2 = tonumber(q) }
    end
    return nil
end

-- x, y and the index of the first title token, or nil and an error code
local function ReadCoords(tokens, i)
    local a = Classify(tokens[i] and tokens[i].text)
    if not a then return nil end
    local nextTok = tokens[i + 1] and Classify(tokens[i + 1].text)
    if a.kind == "PAIR" then return a.n1, a.n2, i + 1 end
    if a.kind == "COMMA" then
        if nextTok and nextTok.kind == "ONE" then return a.dec, nextTok.n1, i + 2 end
        if nextTok and nextTok.kind == "COMMA" then return a.dec, nextTok.dec, i + 2 end
        return a.n1, a.n2, i + 1
    end
    if not nextTok then return nil end
    if nextTok.kind == "ONE" then return a.n1, nextTok.n1, i + 2 end
    if nextTok.kind == "COMMA" then return a.n1, nextTok.dec, i + 2 end
    return nil
end

local function Fail(cmd, reason, message)
    cmd.kind, cmd.reason, cmd.message = "ERROR", reason, message
    return cmd
end

local function Number(v)
    if v == floor(v) then return format("%d", v) end
    return (format("%.2f", v):gsub("0+$", ""):gsub("%.$", ""))
end

-- Resolve a zone text: "#id" directly, else through the resolver.
-- Returns map, byId  or  nil, candidates (normalised { map, name }).
local function ResolveZone(zoneText, resolver)
    local id = zoneText:match("^#(%d+)$")
    if id then return tonumber(id), true end
    if type(resolver) ~= "function" then return nil, {} end
    local ok, map, list = pcall(resolver, zoneText)
    if ok and type(map) == "number" then return map, false end
    local out = {}
    if ok and type(list) == "table" then
        for _, c in ipairs(list) do
            if type(c) == "number" then
                out[#out + 1] = { map = c, name = "#" .. c }
            elseif type(c) == "table" and type(c.map) == "number" then
                out[#out + 1] = { map = c.map, name = type(c.name) == "string" and c.name or ("#" .. c.map) }
            end
        end
    end
    return nil, out
end

-- linePrefix: "/way reset " or "/way reset not " for a reset; nil for an add
local function ZoneFail(cmd, zoneText, candidates, linePrefix)
    cmd.zone = zoneText
    if #candidates == 0 then
        return Fail(cmd, "ZONE_UNKNOWN", format('No zone called "%s". Try a longer name, or %s#<map id>%s.',
            zoneText, linePrefix or "/way ", linePrefix and "" or " x y"))
    end
    local names = {}
    for i, c in ipairs(candidates) do
        if linePrefix then
            c.line = linePrefix .. "#" .. c.map
        elseif cmd.x then
            c.line = G.WayLine(c.map, cmd.x, cmd.y, cmd.title)
        else
            c.line = "/way #" .. c.map
        end
        if i <= MAX_LISTED then names[#names + 1] = c.name end
    end
    local more = #candidates > MAX_LISTED and format(" and %d more", #candidates - MAX_LISTED) or ""
    cmd.candidates = candidates
    return Fail(cmd, "ZONE_AMBIGUOUS",
        format('"%s" could be %s%s. Use one of the /way #id lines.', zoneText, tconcat(names, ", "), more))
end

local function ParseReset(cmd, body, tokens, resolver)
    local second = tokens[2] and strlower(tokens[2].text)
    if not second then
        cmd.kind, cmd.topic = "USAGE", "reset"
        return cmd
    end
    cmd.kind = "RESET"
    if second == "all" then cmd.scope = "ALL"; return cmd end
    if second == "away" then cmd.scope = "AWAY"; return cmd end
    local from = 2
    cmd.scope = "ZONE"
    if second == "not" then
        if not tokens[3] then
            cmd.kind, cmd.scope, cmd.topic = "USAGE", nil, "reset"
            return cmd
        end
        cmd.scope, from = "NOT_ZONE", 3
    end
    local zoneText = Trim(strsub(body, tokens[from].s))
    cmd.zone = zoneText
    local map, extra = ResolveZone(zoneText, resolver)
    if not map then
        local prefix = cmd.scope == "NOT_ZONE" and "/way reset not " or "/way reset "
        cmd.scope = nil
        return ZoneFail(cmd, zoneText, extra, prefix)
    end
    cmd.map = map
    if extra == true then cmd.byId = true end
    return cmd
end

function G.ParseWay(text, resolver)
    local cmd = { text = text }
    if type(text) ~= "string" then
        cmd.kind = "USAGE"
        return cmd
    end
    local body = Trim(text)
    local word, rest = body:match("^/(%S*)%s*(.*)$")
    if word then
        if not WAY_WORDS[strlower(word)] then
            return Fail(cmd, "NOT_WAY", format("Not a /way line: %s", body))
        end
        body = rest
    end
    local tokens = Tokens(body)
    if #tokens == 0 then
        cmd.kind = "USAGE"
        return cmd
    end
    local first = strlower(tokens[1].text)
    if first == "local" then cmd.kind = "LOCAL"; return cmd end
    if first == "list" then cmd.kind = "LIST"; return cmd end
    if first == "arrow" then cmd.kind = "ARROW"; return cmd end
    if first == "help" or first == "?" then cmd.kind = "USAGE"; return cmd end
    if first == "reset" then return ParseReset(cmd, body, tokens, resolver) end

    local at
    for i = 1, #tokens do
        if Classify(tokens[i].text) then at = i; break end
    end
    if at and at > 1 then cmd.zone = Trim(strsub(body, tokens[1].s, tokens[at - 1].e)) end
    if not at then
        cmd.zone = body
        return Fail(cmd, "COORDS", "Could not read the coordinates. Use /way [zone] x y [title], x and y from 0 to 100.")
    end
    local x, y, titleAt = ReadCoords(tokens, at)
    if not x then
        return Fail(cmd, "COORDS", "Could not read the coordinates. Use /way [zone] x y [title], x and y from 0 to 100.")
    end
    if x < 0 or x > 100 or y < 0 or y > 100 then
        return Fail(cmd, "RANGE", format("Coordinates run from 0 to 100; got %s, %s.", Number(x), Number(y)))
    end
    cmd.x, cmd.y = x / 100, y / 100
    if tokens[titleAt] then cmd.title = CleanTitle(strsub(body, tokens[titleAt].s)) end
    if cmd.zone then
        local map, extra = ResolveZone(cmd.zone, resolver)
        if not map then return ZoneFail(cmd, cmd.zone, extra) end
        cmd.map = map
        if extra == true then cmd.byId = true end
    end
    cmd.kind = "ADD"
    return cmd
end

-- The usage lines the runtime prints for a "USAGE" cmd (plain text, no
-- shape glyphs)
function G.WayUsage(topic)
    if topic == "reset" then
        return {
            "/way reset all - remove every waypoint",
            "/way reset away - remove the waypoints not on your current map",
            "/way reset <zone> - remove the waypoints in a zone",
            "/way reset not <zone> - remove every waypoint outside a zone",
        }
    end
    return {
        "/way [zone] x y [title] - add a waypoint; x and y run from 0 to 100",
        "/way #<map id> x y [title] - a map by its id (dungeon maps too)",
        "/way list - every waypoint; /way local - this map's waypoints",
        "/way arrow - what the arrow is doing; /way reset - see /way reset",
    }
end
