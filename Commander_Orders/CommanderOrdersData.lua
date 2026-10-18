-- Commander Orders: the tables.
--
-- Pure data, loaded first. Nothing here is read from the client and nothing
-- here runs; the runtime (CommanderOrders.lua), the pins and the manager read
-- it. Kept in one place so the numbers have one home and one citation each.
--
-- What lives here, and why each table is shaped the way it is:
--
--   TEXTURES     our own art (Harness/make_art.py). Referenced WITH the .png
--                extension, as the suite's other PNGs are; a new texture file
--                needs a full client restart before the game will load it.
--   SOUNDS       two cues and never the same one (the old module played
--                IG_QUEST_LOG_OPEN for both "issued" and "arrived", orders.md
--                D15). Both kits are ones Blizzard's own TBC UI plays
--                (SoundKitConstants.lua: MAP_PING = 3175 on a minimap ping,
--                IG_QUEST_LIST_COMPLETE = 878 from the quest dialogs), so they
--                exist in this client's data.
--   PALETTE      the arrow's colours. Every texture is white with grey
--                shading in it, so SetVertexColor carries the hue and the
--                dark outline stays dark under any tint.
--   ZONE_ALIASES the short names people type after /way ("sw", "shatt",
--                "epl"). Keys are folded by Geo (lowercase, no spaces or
--                punctuation) when the index is built, so "Thunder Bluff",
--                "thunderbluff" and "tb" all land on 1456. Values are this
--                build's uiMapIDs (UiMap DB2, 2.5.6.69795).
--   CONNECTIONS  how to get from one landmass to another, for the arrow's
--                OTHER LANDMASS state ("In Outland: via the Dark Portal") and
--                its "Guide me" action. Kept SMALL on purpose, and every
--                coordinate is cited from installed data (QuestieDB spawns,
--                read with the realdata tooling in the session scratchpad).
--                A connection with no citable spot is text only: the arrow
--                names it but offers no "Guide me". Coordinates are 0..1 on
--                the uiMap named; Questie stores them per areaId on the zone
--                map that areaId opens, which is the same frame.
--   LANDMASS_NAMES  the words for the keys Geo.Landmass returns
--                ("<continent uiMapID>:<world instance>", or with an
--                island's name after it: ISLANDS).
--   ISLANDS      uiMaps that are an island of their continent's frame
--                (3.1, deferred H2): Teldrassil and Darnassus share
--                Kalimdor's key 1414:1, so a straight arrow from Darkshore
--                pointed across the sea. Geo.Landmass appends the island's
--                name, so the arrow names the crossing instead.
--   FOLLOW_UNITS the unit tokens a "follow this group member" target may use.
--   REASONS      the ONE refusal vocabulary (3.1): a reason code -> the
--                sentence every module says (CommanderOrders.Reason).
--
-- D11: no shape glyphs in any string here. ARIALN draws them as boxes.

CommanderOrders = CommanderOrders or {}
local O = CommanderOrders
O.Data = O.Data or {}
local D = O.Data

-- ---------------------------------------------------------------------------
-- Art
-- ---------------------------------------------------------------------------
local TEXTURE_PATH = "Interface\\AddOns\\Commander_Orders\\Textures\\"
D.TEXTURE_PATH = TEXTURE_PATH
D.TEXTURES = {
    ARROW = TEXTURE_PATH .. "Arrow.png",          -- 256, points up at rotation 0
    SHADOW = TEXTURE_PATH .. "ArrowShadow.png",   -- 256, white: tint it black
    ARRIVED = TEXTURE_PATH .. "Arrived.png",      -- 256, ring and tick
    RING = TEXTURE_PATH .. "Ring.png",            -- 256, ring radius 0.39 of the quad
    PIN = TEXTURE_PATH .. "Pin.png",              -- 64
    PIN_EDGE = TEXTURE_PATH .. "PinEdge.png",     -- 64, chevron pointing up
    BADGE = TEXTURE_PATH .. "Badge.png",          -- 64, route numbers
    CORPSE = TEXTURE_PATH .. "Corpse.png",        -- 64
}

-- The arrow HUD's geometry. The arrow art is 0.66 of its quad tip to tail
-- (make_art.py), so an 84 px quad draws a 55 px arrow; the rest of the quad
-- is the transparent margin that keeps it whole at every rotation.
D.ARROW = {
    WIDTH = 190,              -- the root frame: title, quad, three text lines
    HEIGHT = 158,
    QUAD = 84,
    TITLE_MAX = 28,           -- characters before the title is cut with "..."
    SHADOW_OFFSET_X = 1,      -- screen pixels, never texture space
    SHADOW_OFFSET_Y = -2,
    SHADOW_ALPHA = 0.6,
    TEXT_INTERVAL = 0.1,      -- seconds: distance, ETA, arrival and text at 10 Hz
    SMOOTH_TAU = 0.1,         -- seconds: the angle filter's time constant
    TURN_AROUND = 150,        -- degrees off course before "Turn around"
    DEAD_AHEAD = 4,           -- degrees either side that count as dead ahead
    PULSE_PERIOD = 1.4,       -- seconds per NEAR pulse
    -- Under the top-centre band (about 110..330 px from the top) where the
    -- suite's toasts (Objectives, Adjutant, Impact, Production, Promotion),
    -- Momentum's plate, Blizzard's zone text and the raid warnings all draw;
    -- above Diminish (CENTER -160) and Kicks (CENTER -220). 3.0's -140 sat
    -- inside it (review: render). Shifted 240 right of the centre column so
    -- the arrow and its text lines sit beside the character, not on it (the
    -- column between the toast band and the head is too short for its box).
    DEFAULT_POINT = { point = "TOP", x = 240, y = -340 },
}

D.PALETTE = {
    GOOD = { 0.30, 1.00, 0.36 },      -- on course
    MID = { 1.00, 0.84, 0.16 },       -- square to the side
    BAD = { 1.00, 0.26, 0.20 },       -- behind
    AHEAD = { 0.40, 1.00, 0.86 },     -- dead ahead: a cooler green, so it reads as "locked on"
    IDLE = { 0.62, 0.66, 0.72 },      -- placeholder and unknown states
    ARRIVED = { 0.30, 1.00, 0.36 },
    CORPSE = { 0.78, 0.86, 1.00 },    -- the art's own suggestion for the tombstone
    SHADOW = { 0, 0, 0 },
    HINT = { 0.80, 0.84, 0.90 },
    STATUS = { 1.00, 0.82, 0.30 },
}

-- Pin and row tints by a waypoint's icon (or its source, when it has none)
D.ICON_COLOURS = {
    USER = { 1.00, 0.82, 0.30 },
    QUEST = { 1.00, 0.90, 0.20 },
    VENDOR = { 0.55, 0.85, 1.00 },
    TRAINER = { 0.70, 0.55, 1.00 },
    CORPSE = { 0.78, 0.86, 1.00 },
    PLACE = { 0.45, 0.95, 0.60 },
    SHARE = { 1.00, 0.55, 0.85 },
    ROUTE = { 0.40, 0.80, 1.00 },
    TOMTOM = { 0.85, 0.85, 0.85 },
    -- 3.1: the Go-to consumers that are none of the above
    PVP = { 1.00, 0.45, 0.25 },       -- Oracle's battleground nodes and flags
    NOTE = { 0.95, 0.75, 0.45 },      -- Notebook
    FARM = { 0.70, 0.90, 0.35 },      -- Spoils
    UNIT = { 0.35, 0.90, 0.95 },      -- a group member (PartyFrames, Contacts)
    BANK = { 0.95, 0.85, 0.55 },      -- Armory and Vault's "Go to bank"
}

-- Who set a waypoint: the tint its pin and its row wear when it names no
-- icon of its own, and the words for it ("Set by Quest Log"). One table for
-- the pins and the manager, so a source never wears two colours. Consumers
-- that know better pass icon themselves (QuestLog QUEST, Tradecraft VENDOR /
-- TRAINER / QUEST, Formulary VENDOR); share:<name> and TomTom:<addon> are
-- matched by prefix where these are read.
-- 3.1 adds a row for every module with a Go-to (SPEC 5): the TopBar,
-- Oracle, Notebook, Spoils, PartyFrames and Quartermaster, which had none,
-- and the modules this round wires in (Contacts, Armory, Vault, Bags,
-- Vitals, Objectives, Promotion).
D.SOURCE_ICONS = {
    user = "USER", legacy = "USER", place = "PLACE", corpse = "CORPSE", guide = "ROUTE",
    QuestLog = "QUEST", Tradecraft = "TRAINER", Formulary = "VENDOR", Recovery = "CORPSE",
    Logistics = "VENDOR", Adjutant = "VENDOR", Ping = "SHARE", Comms = "SHARE", Guide = "ROUTE",
    TopBar = "USER", Oracle = "PVP", Notebook = "NOTE", Spoils = "FARM", PartyFrames = "UNIT",
    Quartermaster = "VENDOR", Contacts = "UNIT", Armory = "BANK", Vault = "BANK", Bags = "VENDOR",
    Vitals = "VENDOR", Objectives = "QUEST", Promotion = "TRAINER",
}
D.SOURCE_WORDS = {
    user = "You", legacy = "You", place = "Place", corpse = "Corpse", guide = "Guide me",
    QuestLog = "Quest Log", Tradecraft = "Tradecraft", Formulary = "Formulary", Recovery = "Recovery",
    TopBar = "Top Bar", Oracle = "Oracle", Notebook = "Notebook", Ping = "Ping", Comms = "Comms",
    Guide = "Raid Guide", Spoils = "Spoils", PartyFrames = "Party Frames", Logistics = "Logistics",
    Adjutant = "Adjutant", Quartermaster = "Quartermaster", Contacts = "Contacts", Armory = "Armory",
    Vault = "Vault", Bags = "Bags", Vitals = "Vitals", Objectives = "Objectives", Promotion = "Promotion",
}

-- ---------------------------------------------------------------------------
-- Sound
-- ---------------------------------------------------------------------------
-- kit is the SOUNDKIT key, id the number behind it (used when the key is
-- missing); both verified in Blizzard_SharedXML/TBC/SoundKitConstants.lua
D.SOUNDS = {
    SET = { kit = "MAP_PING", id = 3175 },                    -- set, shared, received
    ARRIVE = { kit = "IG_QUEST_LIST_COMPLETE", id = 878 },    -- arrived
}
D.SOUND_CHANNELS = {
    { text = "Sound effects", value = "SFX" },
    { text = "Master", value = "Master" },
}

-- ---------------------------------------------------------------------------
-- /way zone aliases (keys folded by Geo; values are uiMapIDs of this build)
-- ---------------------------------------------------------------------------
D.ZONE_ALIASES = {
    -- capitals
    sw = 1453, stormwind = 1453, ["sw city"] = 1453,
    ["if"] = 1455, ironforge = 1455,
    darn = 1457, darnassus = 1457,
    exo = 1947, exodar = 1947,
    org = 1454, og = 1454, orgrimmar = 1454,
    uc = 1458, undercity = 1458,
    tb = 1456, ["thunder bluff"] = 1456,
    smc = 1954, silvermoon = 1954,
    shatt = 1955, shattrath = 1955,
    -- Eastern Kingdoms
    am = 1416, ah = 1417, bl = 1419, blasted = 1419, spf = 1421, silverpine = 1421,
    wpl = 1422, epl = 1423, hb = 1424, hillsbrad = 1424, hinterlands = 1425,
    sg = 1427, searing = 1427, bs = 1428, burning = 1428, elwynn = 1429,
    dwp = 1430, deadwind = 1430, lm = 1432, loch = 1432, rrm = 1433, redridge = 1433,
    stv = 1434, stranglethorn = 1434, sos = 1435, swamp = 1435,
    eversong = 1941, ew = 1941, ghostlands = 1942, gl = 1942,
    iqd = 1957, qd = 1957, ["quel'danas"] = 1957,
    -- Kalimdor
    barrens = 1413, tn = 1441, needles = 1441, stm = 1442, stonetalon = 1442,
    dwm = 1445, dustwallow = 1445, ungoro = 1449, ["un'goro"] = 1449,
    ws = 1452, azuremyst = 1943, bloodmyst = 1950, bmi = 1950,
    -- Outland
    hfp = 1944, hellfire = 1944, zm = 1946, zang = 1946,
    sv = 1948, smv = 1948, shadowmoon = 1948,
    bem = 1949, bladesedge = 1949, ["blade's edge"] = 1949,
    ns = 1953, terokkar = 1952, tf = 1952, nagrand = 1951,
    -- battlegrounds
    av = 1459, wsg = 1460, ab = 1461, eots = 1956,
}

-- ---------------------------------------------------------------------------
-- Landmasses
-- ---------------------------------------------------------------------------
-- Geo.Landmass keys: "<first Continent ancestor>:<world instance>". The 530
-- halves of the two old continents are their own landmasses: a straight line
-- from Eversong to the Plaguelands crosses a frame boundary, and one from
-- Eversong to Hellfire crosses the Twisting Nether.
D.LANDMASS_NAMES = {
    ["1415:0"] = "the Eastern Kingdoms",
    ["1415:530"] = "Quel'Thalas",
    ["1414:1"] = "Kalimdor",
    ["1414:530"] = "the Azuremyst Isles",
    ["1945:530"] = "Outland",
    ["1414:1:teldrassil"] = "Teldrassil",
}

-- Islands inside one continent frame (deferred H2). uiMap -> the name Geo
-- puts after the landmass key, for the map and every map under it. Only
-- islands with a CITED crossing are listed: Teldrassil (the Auberdine boat,
-- object 176365; the Rut'theran hippogryph master, npc 3838). The Isle of
-- Quel'Danas is left on Quel'Thalas: its crossings are the Shattrath portal
-- and a taxi, neither citable from the installed data (the Shattered Sun
-- Staging Area taxi node 213 is a flight, not a departure point), and an
-- island with no way off it named would say "No known way there" to a
-- player who simply flies.
D.ISLANDS = {
    [1438] = "teldrassil",      -- Teldrassil
    [1457] = "teldrassil",      -- Darnassus
}

-- A capital is a Zone-type map whose parent is the CONTINENT (UiMap.csv,
-- build 69795: Stormwind City 1453 and Elwynn Forest 1429 both hang off the
-- Eastern Kingdoms 1415), so Geo.Zone keeps them apart. Follow the
-- Closest's "my zone" scope (D35) folds each capital into the zone around
-- it through this table, and only there: the coordinate block and chat keep
-- reading Geo.Zone, whose coordinate frame a capital really is.
D.CITY_ZONES = {
    [1453] = 1429,      -- Stormwind City -> Elwynn Forest
    [1454] = 1411,      -- Orgrimmar -> Durotar
    [1455] = 1426,      -- Ironforge -> Dun Morogh
    [1456] = 1412,      -- Thunder Bluff -> Mulgore
    [1457] = 1438,      -- Darnassus -> Teldrassil
    [1458] = 1420,      -- Undercity -> Tirisfal Glades
    [1947] = 1943,      -- The Exodar -> Azuremyst Isle
    [1954] = 1941,      -- Silvermoon City -> Eversong Woods
    [1955] = 1952,      -- Shattrath City -> Terokkar Forest
}

-- One entry per direction. from / to are landmass keys; name finishes the
-- sentence "via ..."; map, x, y is where "Guide me" pins the departure (no
-- map = text only); faction limits it to one side ("Alliance" | "Horde").
-- note adds a second way the arrow can mention.
--
-- Sources (QuestieDB_TBC spawns; areaId -> uiMap: 4 -> 1419, 3483 -> 1944,
-- 1497 -> 1458, 3487 -> 1954, 85 -> 1420, 14 -> 1411, 11 -> 1437,
-- 148 -> 1439, 17 -> 1413, 3524 -> 1943):
--   Dark Portal, Blasted Lands: npc 19254 Warlord Dar'toon (H) 58.10,56.00 and
--     npc 16841 Watch Commander Relthorn Netherwane (A) 58.32,55.90
--   Dark Portal, Hellfire Peninsula: npc 19229 Commander Duron (A) 87.34,50.75
--     and npc 19253 Lieutenant General Orion (H) 87.35,49.78
--   Orb of Translocation: object 184503 Undercity 54.65,11.26; object 184502
--     Silvermoon City 49.49,15.04
--   Zeppelin towers: npc 9566 Zapetta and npc 3150 Hin Denburg, Tirisfal
--     60.74,58.87 / 61.78,59.18; npc 9564 Frezza and npc 12136 Snurk
--     Bucksquick, Durotar 50.82,13.54 / 50.69,12.89
--   Boats: object 176369/176370 "Boat to Theramore"/"Boat to Auberdine",
--     Wetlands 8.28,59.08; object 176364 "Boat to Menethil" and 184084 "Boat
--     to Azuremyst", Darkshore 32.71,41.78; object 165549 "Maiden's Fancy -
--     Round trips to Booty Bay", The Barrens 63.00,37.99; object 181986 "Boat
--     to Auberdine", Azuremyst Isle 24.40,52.85
-- Added in 3.1 (SPEC 2 S7; read from QuestieDB_TBC with the realdata
-- tooling, areaId -> uiMap: 33 -> 1434, 15 -> 1445, 141 -> 1438):
--   Grom'gol: npc 3149 Nez'raz, the zeppelin master to Orgrimmar,
--     Stranglethorn Vale 31.43,29.91 (npc 12137 Squibby Overspeck, to
--     Undercity, stands beside him at 31.54,29.36; npc 12136 Snurk
--     Bucksquick at the Durotar tower 50.69,12.89 flies the other way, the
--     existing Orgrimmar leg). TaxiNodes row 47 "Transport, Grom'gol" agrees
--     (world -12418.8, 235.4 on instance 0).
--   Theramore: no "Boat to Menethil" object is spawned on the Dustwallow
--     side (TaxiNodes row 89 "Transport, Theramore" is all zeros). The spot
--     is npc 12716 Decedra Willham, the one NPC standing on the Theramore
--     pier, Dustwallow Marsh 71.28,56.29 (INFERRED to be the dock: she is
--     on it, the data does not say the boat lands there).
--   Teldrassil: object 176365 "Boat to Teldrassil", Darkshore 32.71,41.78;
--     the way back is npc 3838 Vesprystus, the hippogryph master of
--     Rut'theran Village, Teldrassil 58.40,94.02 (object 181985 "Boat to
--     Auberdine" on the Teldrassil side has no spawn).
--   Shattrath City's portals (to every capital, by faction) are not in the
--     installed data (QuestieDB has no "Portal to <capital>" object, and the
--     AreaTrigger rows in the city are not teleports): text only, so the
--     arrow names them and offers no Guide me. The Exodar <-> Darnassus leg
--     the SPEC asked about has no citable object either and is not listed.
-- Equal-length paths: the runtime picks the first hop whose departure is
-- nearest the player (H3), and a text-only hop only when nothing with a
-- place ties with it, so the order below no longer decides that.
D.CONNECTIONS = {
    { from = "1415:0", to = "1945:530", name = "the Dark Portal in the Blasted Lands",
      map = 1419, x = 0.5821, y = 0.5595 },
    { from = "1945:530", to = "1415:0", name = "the Dark Portal in Hellfire Peninsula",
      map = 1944, x = 0.8735, y = 0.5027, note = "or a portal in Shattrath City" },
    { from = "1415:0", to = "1415:530", name = "the Orb of Translocation in Undercity",
      map = 1458, x = 0.5465, y = 0.1126, faction = "Horde" },
    { from = "1415:0", to = "1415:530", name = "the Thalassian Pass, from the Eastern Plaguelands" },
    { from = "1415:530", to = "1415:0", name = "the Orb of Translocation in Silvermoon City",
      map = 1954, x = 0.4949, y = 0.1504, faction = "Horde" },
    { from = "1415:530", to = "1415:0", name = "the Thalassian Pass, south of the Ghostlands" },
    { from = "1415:0", to = "1414:1", name = "the zeppelin tower in Tirisfal Glades",
      map = 1420, x = 0.6074, y = 0.5887, faction = "Horde" },
    { from = "1414:1", to = "1415:0", name = "the zeppelin tower outside Orgrimmar",
      map = 1411, x = 0.5082, y = 0.1354, faction = "Horde" },
    { from = "1415:0", to = "1414:1", name = "the boat at Menethil Harbor",
      map = 1437, x = 0.0828, y = 0.5908, faction = "Alliance" },
    { from = "1414:1", to = "1415:0", name = "the boat to Menethil at Auberdine",
      map = 1439, x = 0.3271, y = 0.4178, faction = "Alliance" },
    { from = "1414:1", to = "1415:0", name = "the boat to Booty Bay at Ratchet",
      map = 1413, x = 0.6300, y = 0.3799 },
    { from = "1415:0", to = "1414:1", name = "the boat to Ratchet at Booty Bay" },
    { from = "1414:1", to = "1414:530", name = "the boat to Azuremyst at Auberdine",
      map = 1439, x = 0.3271, y = 0.4177, faction = "Alliance" },
    { from = "1414:530", to = "1414:1", name = "the boat to Auberdine on Azuremyst Isle",
      map = 1943, x = 0.2440, y = 0.5285, faction = "Alliance" },
    -- 3.1 (S7)
    { from = "1415:0", to = "1414:1", name = "the zeppelin tower at Grom'gol",
      map = 1434, x = 0.3143, y = 0.2991, faction = "Horde" },
    { from = "1414:1", to = "1415:0", name = "the boat to Menethil at Theramore",
      map = 1445, x = 0.7128, y = 0.5629, faction = "Alliance" },
    { from = "1414:1", to = "1414:1:teldrassil", name = "the boat to Teldrassil at Auberdine",
      map = 1439, x = 0.3271, y = 0.4178, faction = "Alliance" },
    { from = "1414:1:teldrassil", to = "1414:1", name = "the hippogryph master at Rut'theran Village",
      map = 1438, x = 0.5840, y = 0.9402, faction = "Alliance",
      note = "or the boat to Auberdine from the village's pier" },
    { from = "1945:530", to = "1415:0", name = "the portal to Stormwind or Ironforge in Shattrath City",
      faction = "Alliance" },
    { from = "1945:530", to = "1415:0", name = "the portal to Undercity in Shattrath City", faction = "Horde" },
    { from = "1945:530", to = "1414:1", name = "the portal to Orgrimmar or Thunder Bluff in Shattrath City",
      faction = "Horde" },
    { from = "1945:530", to = "1414:1:teldrassil", name = "the portal to Darnassus in Shattrath City",
      faction = "Alliance" },
    { from = "1945:530", to = "1414:530", name = "the portal to the Exodar in Shattrath City", faction = "Alliance" },
    { from = "1945:530", to = "1415:530", name = "the portal to Silvermoon City in Shattrath City",
      faction = "Horde" },
}

-- ---------------------------------------------------------------------------
-- Units, sharing, commands
-- ---------------------------------------------------------------------------
local units = { party1 = true, party2 = true, party3 = true, party4 = true }
for i = 1, 40 do units["raid" .. i] = true end
D.FOLLOW_UNITS = units

D.SHARE = {
    PREFIX = "CmdrOrders",        -- <= 16 characters
    VERSION = 1,
    TOMTOM_PREFIX = "TOMTOM4",    -- TomTom's wire: "map:x:y:title"
    MAX_TITLE = 120,              -- bytes of title before escaping
    BURST = 3,                    -- shares accepted per sender ...
    WINDOW = 10,                  -- ... in this many seconds
}

D.SHARE_ACCEPT = {
    { text = "Ask me", value = "ASK" },
    { text = "Add from my group", value = "GROUP_AUTO_ADD" },
    { text = "Off", value = "OFF" },
}

D.UNITS = {
    { text = "Automatic", value = "AUTO" },
    { text = "Yards", value = "YARDS" },
    { text = "Metres", value = "METRES" },
}

D.MODIFIERS = {
    { text = "Shift", value = "SHIFT" },
    { text = "Ctrl", value = "CTRL" },
    { text = "Alt", value = "ALT" },
}

D.MAP_MODIFIERS = {
    { text = "Ctrl", value = "CTRL" },
    { text = "Alt", value = "ALT" },
    { text = "Shift", value = "SHIFT" },
    { text = "Off", value = "OFF" },
}

-- Sources whose waypoints are the player's own (persistent by default, the
-- Announce setting applies, Keep my own marks applies)
D.USER_SOURCES = { user = true, place = true, legacy = true }

-- 3.1 settings
D.CLOSEST_SCOPES = {
    { text = "My zone", value = "ZONE" },
    { text = "My landmass", value = "LANDMASS" },
}
D.MAP_COORDS = {
    { text = "Automatic", value = "AUTO" },
    { text = "Always", value = "ON" },
    { text = "Off", value = "OFF" },
}

-- ---------------------------------------------------------------------------
-- The one refusal vocabulary (3.1, SPEC 1: CommanderOrders.Reason)
-- ---------------------------------------------------------------------------
-- A reason code (what the API answers as `nil, reason`) -> the sentence
-- every module says. The short codes are the 3.1 vocabulary; the longer
-- ones are the words the 3.0 API already answered with, kept as codes so no
-- consumer's comparison breaks. Reason() of an unknown code says the code
-- itself, capitalised: never nothing, never "nil". No full stop at the end:
-- callers put the sentence in a line of their own.
D.REASONS = {
    disabled = "Commander Orders is turned off (/corder)",
    loading = "Commander Orders is still loading",
    nowhere = "No known location",
    nomap = "No map for that place",
    nocoords = "No coordinates for that place",
    instance = "No position inside instances",
    otherside = "Only the other faction has one",
    elsewhere = "None on your landmass",
    noquestie = "Needs Questie to look that up",
    notready = "Questie is still loading",
    needsorders = "Needs Commander Orders",
    noquery = "Nothing to look up",
    unknown = "Commander Orders cannot look that up",
    error = "Something went wrong (see your error log)",
    -- the 3.0 words
    ["no world position"] = "That map has no world coordinates",
    ["no position"] = "No map position here",
    ["no spec"] = "Nothing to go to",
    ["invalid unit"] = "Only a party or raid member can be followed",
    ["invalid position"] = "Not a place on the map",
    ["invalid map"] = "No such map",
    ["invalid x"] = "Not a place on the map",
    ["invalid y"] = "Not a place on the map",
    ["unknown waypoint"] = "That waypoint is gone",
    ["not in a group"] = "You are not in a group",
    ["no chat"] = "Chat is not available",
    ["no addon messages"] = "Addon messages are not available",
    ["chat is locked down"] = "Chat is locked down",
    ["no guide"] = "Nothing to guide you to from here",
    ["unknown place"] = "No place by that name",
    ["no stops"] = "That route has no stops",
    ["no fields"] = "Nothing to change",
}
