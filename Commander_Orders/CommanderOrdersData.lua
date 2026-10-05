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
--                ("<continent uiMapID>:<world instance>").
--   FOLLOW_UNITS the unit tokens a "follow this group member" target may use.
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
}

-- Who set a waypoint: the tint its pin and its row wear when it names no
-- icon of its own, and the words for it ("Set by Quest Log"). One table for
-- the pins and the manager, so a source never wears two colours. Consumers
-- that know better pass icon themselves (QuestLog QUEST, Tradecraft VENDOR /
-- TRAINER / QUEST, Formulary VENDOR); share:<name> and TomTom:<addon> are
-- matched by prefix where these are read.
D.SOURCE_ICONS = {
    user = "USER", legacy = "USER", place = "PLACE", corpse = "CORPSE", guide = "ROUTE",
    QuestLog = "QUEST", Tradecraft = "TRAINER", Formulary = "VENDOR", Recovery = "CORPSE",
    Logistics = "VENDOR", Adjutant = "VENDOR", Ping = "SHARE", Comms = "SHARE", Guide = "ROUTE",
}
D.SOURCE_WORDS = {
    user = "You", legacy = "You", place = "Place", corpse = "Corpse", guide = "Guide me",
    QuestLog = "Quest Log", Tradecraft = "Tradecraft", Formulary = "Formulary", Recovery = "Recovery",
    TopBar = "Top Bar", Oracle = "Oracle", Notebook = "Notebook", Ping = "Ping", Comms = "Comms",
    Guide = "Raid Guide", Spoils = "Spoils", PartyFrames = "Party Frames", Logistics = "Logistics",
    Adjutant = "Adjutant", Quartermaster = "Quartermaster",
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
