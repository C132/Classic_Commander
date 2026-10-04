-- Commander Quest Log: the Questie adapter.
--
-- The Zones tab and the world-map drawer show every quest a character can ever
-- do in a zone, and only Questie knows that list. This file is the ONE place
-- in the module that names Questie, QuestieLoader, Commander Orders' API
-- (CommanderOrders.Add / AddRoute / RegisterResolver), C_QuestLog.IsOnQuest
-- or C_Map zone resolution.
-- It reads Questie's data, turns it into the plain `fact` and `char` tables the
-- pure engine (CommanderQuestLogCompletion.lua) classifies, and caches the
-- engine's answer per zone. Nothing outside this file ever touches a Questie
-- table, so when Questie changes shape the damage is one file wide -- and
-- every read here is feature-detected and pcall'd, so the damage is a Zones
-- tab that says "unavailable", never a Lua error in the log window.
--
-- Questie publishes almost nothing on purpose. Questie.API is the only blessed
-- surface and it carries a ready signal and an update callback, no data. The
-- data lives in internal modules behind the global QuestieLoader, reachable and
-- working but with no contract. The traps, each of them paid for in the
-- research behind this file:
--
--   * QuestieLoader:ImportModule SILENTLY CREATES an empty module for a name it
--     does not know, so a misspelling or a module Questie dropped would
--     register a phantom that later Questie code trips over. This file never
--     imports: it looks in QuestieLoader._modules and treats a miss as absent.
--   * The ready callback runs INSIDE Questie's init coroutine, under xpcall.
--     Doing real work there stalls Questie's own start-up and an error would
--     be blamed on Questie; the callback sets a flag and the work happens one
--     frame later.
--   * IsDoableVerbose answers "", false, AVAILABLE unless its third argument
--     (returnText) is true: every early return in it is written as
--     `if returnText and returnBrief ... elseif returnText ... end` with no
--     else. It is called (id, false, true, false) and only the third return,
--     the DoableStates NUMBER, is used -- translated back to a name through a
--     map built from QuestieDB.DoableStates at ready time.
--   * Several Questie calls look like reads and are not. IsDoable writes
--     autoBlacklist; IsComplete scans every bag slot; HideQuest writes the
--     player's hidden list and redraws the map; ZoneDB.GetZonesWithQuests
--     mutates the zone map Questie itself uses and yields;
--     AvailableQuests.IsLevelRequirementsFulfilled caches by quest id alone
--     and would poison Questie's map filter for the session. None of them is
--     ever called from here.
--   * Questie REASSIGNS its tables at runtime (Questie.db.char.complete,
--     QuestiePlayer.currentQuestlog, QuestieDB.QuestPointers,
--     QuestieCorrections.hiddenQuests). Every read goes through the module
--     table, every time; no reference to one of them is ever kept.
--   * Two id spaces. Questie's zones are AreaTable areaIds; the world map
--     speaks uiMapIDs. AREA 1941 is the Caverns of Time and UI MAP 1941 is
--     Eversong Woods. Every variable here says which it holds, and the only
--     bridge is ZoneDB -- whose GetAreaIdByUiMapId ends in error() for a map
--     it cannot match (every continent, and then some), so it is pcall'd.
--   * QuestieDB's reader answers 0, not nil, for an unset number, nil for an
--     empty list, and a fresh deep copy of every table field on every read
--     (a CBOR decode each time). Each quest is read once per pass with
--     QueryQuest and the copy is kept.
--   * QuestieJourney.zoneMap -- Questie's own "quests by zone" index, built
--     once at login, race/class/blacklist filtered -- also holds junk: a bug
--     in its spawn branch stores NPC ids as if they were quest ids. Every id
--     read from it is checked against QuestPointers.
--   * Dungeon quests are filed under quest-log GROUP keys (Hellfire Citadel
--     3563, Auchindoun 3917, Tempest Keep 3845, Caverns of Time 1941) but
--     also, for some wings, under the instance's own key (Mana-Tombs 3792
--     files five). A group's view therefore reads its member instances too,
--     the same way Hellfire's reads the orphan subzone 3535.
--
-- Recompute discipline: everything is cached per zone against a GENERATION
-- number. Questie's update callback, our own quest/faction/skill/level events,
-- an Ignore toggle and a settings change all Bump; bumps within 0.25 s
-- collapse into one generation step and one listener call, which also lets
-- Questie's own QUEST_TURNED_IN handler update `complete` before anything is
-- rebuilt. Full engine views are kept for the last three zones only; the
-- three numbers a percentage needs are kept for every zone ever computed.

CommanderQuestLog = CommanderQuestLog or {}
local Q = CommanderQuestLog

local A = {}
Q.Questie = A

-- Bumped once per debounced burst; every cache below is keyed by it
A.generation = 0

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local REVERSE_CHUNK = 400            -- quest ids read per frame by the exclusive-choice sweep
local DEBOUNCE_SECONDS = 0.25
-- Questie refreshes the reputation and profession caches IsDoableVerbose reads
-- on a 2 s bucket of chat events (EventHandler.lua:112-120) and tells no one,
-- so a reputation or skill change is asked about again once that has run
local QUESTIE_BUCKET_SECONDS = 2.2
local LATE_BUMP_SLACK = 0.1         -- an event this close to the arming one is already covered
local SUMMARY_TICK_SECONDS = 0.05    -- one zone summary per tick in the background
local VIEW_CACHE_SIZE = 3
local MAX_SPAWNS_PER_GIVER = 8       -- what a fact carries; spawns in the viewed zone first
local MAX_FINISHER_SPAWNS = 32       -- a turn-in waypoint's nearest-of-N candidates
local MAX_PIN_SPAWNS_PER_QUEST = 5
local PIN_MERGE_PERCENT = 0.5        -- givers this close (in map percent) share one pin
local READY_POLL_SECONDS, READY_POLL_TRIES = 1, 120
local CONTINENT_MAP_TYPE = 2         -- Enum.UIMapType.Continent; Cosmic 0 and World 1 sit below it
local ZONE_MAP_TYPE = 3
local DUNGEON_MAP_TYPE = 4           -- Enum.UIMapType.Dungeon: the maps an entrance is asked for

-- One QueryQuest per quest per pass, in this order
local FACT_KEYS = {
    "name", "questLevel", "requiredLevel", "requiredMaxLevel", "preQuestSingle", "preQuestGroup",
    "nextQuestInChain", "exclusiveTo", "breadcrumbForQuestId", "parentQuest", "requiredMinRep",
    "requiredMaxRep", "requiredSkill", "specialFlags", "questFlags", "startedBy", "finishedBy",
    "objectivesText", "zoneOrSort", "requiredRaces", "requiredClasses",
}
local F = {}
for index, key in ipairs(FACT_KEYS) do F[key] = index end

-- Maps a uiMap can never resolve below: Cosmic, Azeroth, the three continents
-- and the parentless duplicates the client also carries
local CONTINENT_MAPS = {
    [946] = true, [947] = true, [1414] = true, [1415] = true, [1945] = true,
    [113] = true, [987] = true, [1463] = true, [1464] = true,
}

-- The orphan subzone Questie never re-parents (five "Wanted:" quests)
local SUBZONE_FOLD = { [3535] = 3483 }

-- TBC instance areaIds -> the quest-log group key Questie files the bulk of
-- their quests under. The Coilfang wings are deliberately absent: Questie
-- files their quests under each wing's own key (Steamvault, Underbog, Slave
-- Pens, Serpentshrine), and 3905's handful already sit in Zangarmarsh.
local INSTANCE_GROUP = {
    [3562] = 3563, [3713] = 3563, [3714] = 3563,                    -- Hellfire Citadel
    [3789] = 3917, [3790] = 3917, [3791] = 3917, [3792] = 3917,     -- Auchindoun
    [3847] = 3845, [3848] = 3845, [3849] = 3845,                    -- Tempest Keep
    [2366] = 1941, [2367] = 1941, [3606] = 1941,                    -- Caverns of Time
}
local DUNGEON_GROUPS = { [3563] = true, [3917] = true, [3845] = true, [1941] = true }
local RAID_AREAS = {
    [3457] = true, [3606] = true, [3607] = true, [3805] = true, [3836] = true,
    [3923] = true, [3959] = true, [4075] = true,
}
local PVP_SORT = -25

-- view key -> the extra zoneMap keys it also reads
local FOLDED_INTO = {}
do
    local function Fold(member, group)
        FOLDED_INTO[group] = FOLDED_INTO[group] or {}
        local list = FOLDED_INTO[group]
        list[#list + 1] = member
    end
    for member, group in pairs(SUBZONE_FOLD) do Fold(member, group) end
    for member, group in pairs(INSTANCE_GROUP) do Fold(member, group) end
    for _, list in pairs(FOLDED_INTO) do table.sort(list) end
end

-- Aldor and Scryers: the one TBC pair where standing with one costs the other
local RIVALS = { [932] = 934, [934] = 932 }

-- Quests offered only below a reputation that never falls back in normal
-- play, which Questie's questsOnlyAvailableUntilReputationValue leaves out
-- (it carries them commented out, "TO DO CHECK THIS"). Without them a player
-- who passed the cap first is told the quest is locked, and the zone can
-- never reach 100%.
local ONE_WAY_REP_EXTRA = {
    [9808] = true,      -- Glowcap Mushrooms: Sporeggar below Friendly
}

-- Questie's verdicts that are final: a prerequisite in one of these is gone,
-- and so is every quest that needs it (the engine's PREREQ_GONE)
local GONE_STATES = {
    EXCLUSIVE_COMPLETED = true, NEXTQUESTINCHAIN_ACTIVE_OR_COMPLETED = true, BREADCRUMB_FOLLOWUP = true,
    LEVEL_TOO_HIGH = true, BLACKLISTED = true, DISABLING_QUEST_COMPLETED = true,
    WRONG_RACE = true, WRONG_CLASS = true,
}

local MENU_CATEGORIES = { 1, 2, 3, 9 }
local CLASS_CATEGORY = 11
local CATEGORY_NAMES = {
    [1] = "Eastern Kingdoms", [2] = "Kalimdor", [3] = "Outland", [9] = "Dungeons", [11] = "Class",
}
-- When the client has no children API answer for a continent map. Cosmic
-- (946) is where zooming out of Outland lands; its direct children are a
-- world and a continent, never a zone, so without a row here it always read
-- "no quest zones".
local CONTINENT_CATEGORIES = {
    [1415] = { 1 }, [1414] = { 2 }, [1945] = { 3 }, [947] = { 1, 2 }, [946] = { 1, 2, 3 },
}

-- All present in this binary; each registered in its own pcall all the same
local BUMP_EVENTS = {
    "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "UPDATE_FACTION",
    "SKILL_LINES_CHANGED", "PLAYER_LEVEL_UP",
}

-- What must exist before anything is trusted. The first list holds from file
-- load; the second only once Questie's login stages have run.
local REQUIRED = {
    { "QuestieDB", "IsDoableVerbose", "function" },
    { "QuestieDB", "DoableStates", "table" },
    { "QuestieDB", "QueryQuest", "function" },
    { "QuestieDB", "QueryQuestSingle", "function" },
    { "QuestieDB", "QueryNPCSingle", "function" },
    { "QuestieDB", "QueryObjectSingle", "function" },
    { "ZoneDB", "GetAreaIdByUiMapId", "function" },
    { "ZoneDB", "GetUiMapIdByAreaId", "function" },
    { "ZoneDB", "GetParentZoneId", "function" },
    { "QuestiePlayer" },
    { "QuestieJourney" },
    { "QuestieCorrections" },
}
local REQUIRED_READY = {
    { "QuestieDB", "QuestPointers", "table" },
    { "QuestieJourney", "zoneMap", "table" },
    { "QuestieCorrections", "hiddenQuests", "table" },
}

local EMPTY = {}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local initialised, attached = false, false
local ready = false                  -- our post-ready setup has run
local broken = nil                   -- why Questie was judged unusable, once it was
local stateNames = {}                -- DoableStates number -> NAME
local reverse, reverseDone, reverseJob = {}, false, nil
local forwardCache, peerCache = {}, {}
local dirty, pending, reasons, lastReasons = false, false, {}, ""
local listeners = {}
local views, viewOrder, summaries = {}, {}, {}
local summaryJobs, summaryTickPending = {}, false
local logIndex, logSignature = {}, nil
local extraIndex, extraSignature = nil, nil
local zoneNames, questNames, uiMapCache = {}, {}, {}
local goneCache, goneGeneration = {}, nil
local lateBumpPending, lateBumpAgain, lateBumpAt = false, false, nil
local lastError = nil

-- ---------------------------------------------------------------------------
-- Reaching Questie
-- ---------------------------------------------------------------------------

-- A module Questie registered, or nil. Never ImportModule: an unknown name
-- would be created on the spot (and the profiler stamps every import).
local function Module(name)
    local loader = QuestieLoader
    local modules = type(loader) == "table" and loader._modules or nil
    local module = type(modules) == "table" and modules[name] or nil
    if type(module) == "table" then return module end
    return nil
end

-- Questie proper, not just its database: a second Questie copy replaces the
-- global with {} (no API), and QuestieDB alone has no blacklist or character
-- state, so completion figures from it would be wrong
local function Detected()
    return type(Questie) == "table" and type(Questie.API) == "table"
        and type(QuestieLoader) == "table" and type(QuestieLoader._modules) == "table"
end

local function NoteError(where, err)
    lastError = where .. ": " .. tostring(err)
end

-- pcall that answers nil on failure and keeps the last error for /cql status
local function Try(where, fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then
        NoteError(where, a)
        return nil
    end
    return a, b, c
end

local function List(value)
    if type(value) == "table" then return value end
    return EMPTY
end

local function QuestDB()
    return Module("QuestieDB")
end

local function QuestPointers()
    local db = QuestDB()
    local pointers = db and db.QuestPointers
    if type(pointers) == "table" then return pointers end
    return nil
end

local function Exists(questId)
    local pointers = QuestPointers()
    return (type(questId) == "number" and pointers and pointers[questId]) and true or false
end

local function QueryQuestSingle(questId, key)
    local db = QuestDB()
    if not db then return nil end
    return (Try("QueryQuestSingle", db.QueryQuestSingle, questId, key))
end

local function CompleteTable()
    local questie = Questie
    local db = type(questie) == "table" and questie.db or nil
    local char = type(db) == "table" and db.char or nil
    local complete = type(char) == "table" and char.complete or nil
    if type(complete) == "table" then return complete end
    return nil
end

local function Missing(list)
    for _, requirement in ipairs(list) do
        local module = Module(requirement[1])
        if not module then return "module " .. requirement[1] .. " is missing" end
        if requirement[2] and type(module[requirement[2]]) ~= requirement[3] then
            return requirement[1] .. "." .. requirement[2] .. " is missing"
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Zones: the two id spaces and the one bridge between them
-- ---------------------------------------------------------------------------

local function ParentOf(areaId)
    local zoneDB = Module("ZoneDB")
    if not (zoneDB and type(areaId) == "number") then return nil end
    local parent = Try("GetParentZoneId", zoneDB.GetParentZoneId, zoneDB, areaId)
    if type(parent) == "number" and parent > 0 and parent ~= areaId then return parent end
    return nil
end

-- areaId -> uiMapId straight from ZoneDB, remembered (the tables are static,
-- and a miss prints a CRITICAL debug line when Questie's debug is on)
local function RawUiMap(areaId)
    if type(areaId) ~= "number" then return nil end
    local cached = uiMapCache[areaId]
    if cached ~= nil then return cached or nil end
    local zoneDB = Module("ZoneDB")
    if not zoneDB then return nil end
    local ok, uiMapId = pcall(zoneDB.GetUiMapIdByAreaId, zoneDB, areaId)
    if not ok then
        NoteError("GetUiMapIdByAreaId", uiMapId)
        return nil
    end
    if type(uiMapId) ~= "number" or uiMapId <= 0 then uiMapId = nil end
    uiMapCache[areaId] = uiMapId or false
    return uiMapId
end

-- The map a spawn's coordinates are drawn on. A subzone with no map of its
-- own lends its parent's, as Questie's own draw does (QuestieMap.lua:648-665;
-- Questie's first try there, C_Map.GetMapInfo(areaId), hands an AREA id to a
-- UI-MAP API and is not copied). Returns uiMapId, the areaId it belongs to.
local function UiMapForSpawn(areaId)
    local uiMapId = RawUiMap(areaId)
    if uiMapId then return uiMapId, areaId end
    local parent = ParentOf(areaId)
    if parent then
        uiMapId = RawUiMap(parent)
        if uiMapId then return uiMapId, parent end
    end
    return nil, areaId
end

local function DungeonEntrances(areaId)
    local zoneDB = Module("ZoneDB")
    if not zoneDB then return nil end
    local location = Try("GetDungeonLocation", zoneDB.GetDungeonLocation, zoneDB, areaId)
    if type(location) == "table" then return location end
    return nil
end

local function IsDungeonArea(areaId)
    if type(areaId) ~= "number" then return false end
    if DUNGEON_GROUPS[areaId] or INSTANCE_GROUP[areaId] or RAID_AREAS[areaId] then return true end
    local zoneDB = Module("ZoneDB")
    if zoneDB and Try("IsDungeonZone", zoneDB.IsDungeonZone, areaId) then return true end
    local journey = Module("QuestieJourney")
    local dungeons = journey and type(journey.zones) == "table" and journey.zones[9] or nil
    return type(dungeons) == "table" and dungeons[areaId] ~= nil
end

-- Any areaId -> the key a zone view is built for: the parent zone of a
-- subzone (and the main id of a dungeon floor), the orphan subzone folded,
-- an instance mapped to its quest-log group
local function NormalizeArea(areaId)
    if type(areaId) ~= "number" or areaId <= 0 then return nil end
    areaId = ParentOf(areaId) or areaId
    areaId = SUBZONE_FOLD[areaId] or areaId
    return INSTANCE_GROUP[areaId] or areaId
end

local function KindOf(areaId)
    if IsDungeonArea(areaId) then return "DUNGEON" end
    return "ZONE"
end

local function Localise(text)
    if type(text) ~= "string" then return nil end
    local l10n = Module("l10n")
    if l10n then
        local ok, out = pcall(l10n, text)    -- callable through its metatable
        if ok and type(out) == "string" and out ~= "" then return out end
    end
    return text
end

local function SortName(sortId)
    local l10n = Module("l10n")
    local lookup = l10n and type(l10n.questCategoryLookup) == "table" and l10n.questCategoryLookup or nil
    local text = lookup and lookup[sortId]
    if type(text) == "string" then return Localise(text) end
    return nil
end

local function L10nZoneName(areaId)
    local l10n = Module("l10n")
    local lookup = l10n and type(l10n.zoneLookup) == "table" and l10n.zoneLookup or nil
    if not lookup then return nil end
    for _, continent in pairs(lookup) do
        if type(continent) == "table" and type(continent[areaId]) == "string" then
            return Localise(continent[areaId])
        end
    end
    return nil
end

local function Named(text)
    return type(text) == "string" and text ~= ""
end

-- Blizzard's name, then Questie's dungeon name, then Questie's lookup -- the
-- chain TrackerUtils:GetZoneNameByID uses. Negative ids are quest-log sorts.
function A.ZoneName(areaId)
    if type(areaId) ~= "number" then return "Unknown zone" end
    local cached = zoneNames[areaId]
    if cached then return cached end
    local name
    if areaId < 0 then
        name = SortName(areaId)
    else
        if C_Map and C_Map.GetAreaInfo then name = Try("GetAreaInfo", C_Map.GetAreaInfo, areaId) end
        if not Named(name) then
            local zoneDB = Module("ZoneDB")
            if zoneDB then
                name = Try("GetLocalizedDungeonName", zoneDB.GetLocalizedDungeonName, zoneDB, areaId)
            end
        end
        if not Named(name) then name = L10nZoneName(areaId) end
    end
    if not Named(name) then return "Zone " .. areaId end    -- not remembered: Questie may come up later
    zoneNames[areaId] = name
    return name
end

-- uiMapId -> areaId, kind. kind is "ZONE", "DUNGEON" or "CONTINENT" (no
-- areaId: a continent's view is its zones'), nil when nothing resolves.
function A.ZoneForMap(uiMapId)
    if type(uiMapId) ~= "number" then return nil, nil end
    if CONTINENT_MAPS[uiMapId] then return nil, "CONTINENT" end
    if C_Map and C_Map.GetMapInfo then
        local info = Try("GetMapInfo", C_Map.GetMapInfo, uiMapId)
        local continentType = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or CONTINENT_MAP_TYPE
        if type(info) == "table" and type(info.mapType) == "number" and info.mapType <= continentType then
            return nil, "CONTINENT"
        end
    end
    if not Detected() then return nil, nil end
    local zoneDB = Module("ZoneDB")
    if not zoneDB then return nil, nil end
    -- It THROWS for a map it cannot match; that is an answer, not an error
    local ok, areaId = pcall(zoneDB.GetAreaIdByUiMapId, zoneDB, uiMapId)
    if not ok or type(areaId) ~= "number" or areaId <= 0 then return nil, nil end
    areaId = NormalizeArea(areaId)
    return areaId, KindOf(areaId)
end

-- areaId -> uiMapId, nil allowed. A dungeon group key has no map of its own;
-- it answers its first wing's, which resolves straight back to the group.
function A.UiMapForArea(areaId)
    local uiMapId = RawUiMap(areaId)
    if uiMapId then return uiMapId end
    for _, member in ipairs(FOLDED_INTO[areaId] or EMPTY) do
        if INSTANCE_GROUP[member] then
            uiMapId = RawUiMap(member)
            if uiMapId then return uiMapId end
        end
    end
    return nil
end

function A.ZoneForPlayer()
    local areaId
    if C_Map and C_Map.GetBestMapForUnit then
        local uiMapId = Try("GetBestMapForUnit", C_Map.GetBestMapForUnit, "player")
        if uiMapId then areaId = (A.ZoneForMap(uiMapId)) end
    end
    -- Caves and entrances report the continent; Questie reads the zone text.
    -- Its GetCurrentZoneId calls GetAreaIdByUiMapId unguarded, so it can throw.
    if not areaId and Detected() then
        local player = Module("QuestiePlayer")
        if player then
            local ok, raw = pcall(player.GetCurrentZoneId, player)
            if ok and type(raw) == "number" and raw > 0 then areaId = NormalizeArea(raw) end
        end
    end
    if not areaId then return nil, nil end
    return areaId, A.ZoneName(areaId)
end

-- ---------------------------------------------------------------------------
-- Membership
--
-- The core of a zone is Questie's own zoneMap entry (plus whatever is folded
-- into it). The EXTRA layer is quests Questie files elsewhere -- under a
-- dungeon, the player's class or one of the player's professions -- whose
-- giver stands in the zone. Those are looked up through one index over just
-- those buckets, built on first use and rebuilt only when the bucket set
-- changes (a new profession).
-- ---------------------------------------------------------------------------

local function ZoneMap()
    local journey = Module("QuestieJourney")
    local zoneMap = journey and journey.zoneMap
    if type(zoneMap) == "table" then return zoneMap end
    return nil
end

local function CoreMembers(areaId)
    local out, seen = {}, {}
    local zoneMap, pointers = ZoneMap(), QuestPointers()
    if not (zoneMap and pointers and type(areaId) == "number") then return out, seen end
    local keys = { areaId }
    for _, member in ipairs(FOLDED_INTO[areaId] or EMPTY) do keys[#keys + 1] = member end
    for _, key in ipairs(keys) do
        local set = zoneMap[key]
        if type(set) == "table" then
            for questId in pairs(set) do
                -- zoneMap also holds NPC ids from Questie's spawn-branch bug
                if type(questId) == "number" and pointers[questId] and not seen[questId] then
                    seen[questId] = true
                    out[#out + 1] = questId
                end
            end
        end
    end
    table.sort(out)
    return out, seen
end

local function HasMembers(areaId)
    local core = CoreMembers(areaId)
    return #core > 0
end

-- One giver's spawns as records { kind, id, name, areaId, x, y, uiMapId, zone }.
-- areaId is the area whose MAP the coordinates are on; zone is the view key the
-- spot belongs to (NormalizeArea). A dungeon's {-1, -1} sentinel becomes its
-- entrance(s) outside, the way Questie draws it (AvailableQuests.lua:813-819).
local function GiverRecords(kind, id, name, spawns, prefer, cap)
    local records = {}
    if type(spawns) ~= "table" then
        records[1] = { kind = kind, id = id, name = name }
        return records
    end
    local zones, seen = {}, {}
    for zone in pairs(spawns) do
        if type(zone) == "number" then zones[#zones + 1] = zone end
    end
    table.sort(zones)
    local function Add(areaId, x, y, dungeonAreaId)
        if type(areaId) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then return end
        local key = areaId .. ":" .. x .. ":" .. y
        if seen[key] then return end
        seen[key] = true
        local uiMapId, mapAreaId = UiMapForSpawn(areaId)
        records[#records + 1] = {
            kind = kind, id = id, name = name, areaId = mapAreaId, x = x, y = y, uiMapId = uiMapId,
            rawAreaId = (mapAreaId ~= areaId) and areaId or nil, dungeonAreaId = dungeonAreaId,
            zone = NormalizeArea(areaId),
        }
    end
    for _, zone in ipairs(zones) do
        for _, coords in ipairs(List(spawns[zone])) do
            local x, y = List(coords)[1], List(coords)[2]
            if x == -1 or y == -1 then
                for _, entrance in ipairs(List(DungeonEntrances(zone))) do
                    entrance = List(entrance)
                    Add(entrance[1], entrance[2], entrance[3], zone)
                end
            else
                Add(zone, x, y, nil)
            end
        end
    end
    if #records == 0 then
        records[1] = { kind = kind, id = id, name = name }
        return records
    end
    -- Spawns in the viewed zone first (order otherwise kept), then the cap
    if prefer then
        local here, there = {}, {}
        for _, record in ipairs(records) do
            if record.zone and prefer[record.zone] then here[#here + 1] = record else there[#there + 1] = record end
        end
        for _, record in ipairs(there) do here[#here + 1] = record end
        records = here
    end
    cap = cap or MAX_SPAWNS_PER_GIVER
    for index = #records, cap + 1, -1 do records[index] = nil end
    return records
end

-- startedBy / finishedBy, { npcIds, objectIds, itemIds }, as giver records.
-- Item starters carry a name and no coordinates.
local function ReadGivers(givers, prefer, cap)
    local out = {}
    local db = QuestDB()
    if type(givers) ~= "table" or not db then return out end
    for _, npcId in ipairs(List(givers[1])) do
        local name = Try("QueryNPCSingle", db.QueryNPCSingle, npcId, "name")
        local spawns = Try("QueryNPCSingle", db.QueryNPCSingle, npcId, "spawns")
        for _, record in ipairs(GiverRecords("npc", npcId, name, spawns, prefer, cap)) do out[#out + 1] = record end
    end
    for _, objectId in ipairs(List(givers[2])) do
        local name = Try("QueryObjectSingle", db.QueryObjectSingle, objectId, "name")
        local spawns = Try("QueryObjectSingle", db.QueryObjectSingle, objectId, "spawns")
        for _, record in ipairs(GiverRecords("object", objectId, name, spawns, prefer, cap)) do out[#out + 1] = record end
    end
    for _, itemId in ipairs(List(givers[3])) do
        out[#out + 1] = { kind = "item", id = itemId, name = Try("QueryItemSingle", db.QueryItemSingle, itemId, "name") }
    end
    return out
end

local function PlayerClassKey()
    local db = QuestDB()
    local sortKeys = db and type(db.sortKeys) == "table" and db.sortKeys or nil
    if not sortKeys then return nil end
    local token
    if UnitClassBase then token = Try("UnitClassBase", UnitClassBase, "player") end
    if not token and UnitClass then
        local _, classToken = Try("UnitClass", UnitClass, "player")
        token = classToken
    end
    local key = token and sortKeys[token]
    if type(key) == "number" then return key end
    return nil
end

local function PlayerProfessionKeys()
    local out = {}
    local professions = Module("QuestieProfessions")
    if not professions then return out end
    local known = Try("GetPlayerProfessions", professions.GetPlayerProfessions, professions)
    for skillId in pairs(List(known)) do
        local key = Try("GetSortIdByProfessionId", professions.GetSortIdByProfessionId, professions, skillId)
        if type(key) == "number" then out[#out + 1] = key end
    end
    table.sort(out)
    return out
end

local function ExtraIndex()
    local zoneMap, pointers, db = ZoneMap(), QuestPointers(), QuestDB()
    if not (zoneMap and pointers and db) then return EMPTY end
    local keys = {}
    for key in pairs(zoneMap) do
        if type(key) == "number" and key > 0 and IsDungeonArea(key) then keys[#keys + 1] = key end
    end
    local classKey = PlayerClassKey()
    if classKey and zoneMap[classKey] then keys[#keys + 1] = classKey end
    for _, key in ipairs(PlayerProfessionKeys()) do
        if zoneMap[key] then keys[#keys + 1] = key end
    end
    table.sort(keys)
    local signature = table.concat(keys, ",")
    if extraIndex and signature == extraSignature then return extraIndex end
    local index = {}
    for _, key in ipairs(keys) do
        for questId in pairs(List(zoneMap[key])) do
            if type(questId) == "number" and pointers[questId] then
                local startedBy = Try("QueryQuestSingle", db.QueryQuestSingle, questId, "startedBy")
                for _, giver in ipairs(ReadGivers(startedBy, nil, math.huge)) do
                    if giver.zone then
                        index[giver.zone] = index[giver.zone] or {}
                        index[giver.zone][questId] = true
                    end
                end
            end
        end
    end
    extraIndex, extraSignature = index, signature
    return index
end

local function ExtraMembers(areaId, coreSeen)
    local out = {}
    for questId in pairs(List(ExtraIndex()[areaId])) do
        if not coreSeen[questId] then out[#out + 1] = questId end
    end
    table.sort(out)
    return out
end

-- ---------------------------------------------------------------------------
-- Facts: one plain table per quest for the engine
-- ---------------------------------------------------------------------------

local function HideOnMapValue()
    local blacklist = Module("QuestieQuestBlacklist")
    local value = blacklist and blacklist.HIDE_ON_MAP
    if type(value) == "string" then return value end
    return "HIDE_ON_MAP"
end

-- Display only. From where Questie files the quest, never from the client's
-- tag API: GetQuestTagInfo answers nil on first ask and Questie then schedules
-- a retry timer per quest.
local function TagFor(zoneOrSort)
    if type(zoneOrSort) ~= "number" then return nil end
    if zoneOrSort == PVP_SORT then return "PVP" end
    if zoneOrSort <= 0 then return nil end
    local area = NormalizeArea(zoneOrSort)
    if RAID_AREAS[zoneOrSort] or RAID_AREAS[area] then return "RAID" end
    if IsDungeonArea(area) then return "DUNGEON" end
    return nil
end

local function Pair(value)
    if type(value) == "table" and type(value[1]) == "number" and type(value[2]) == "number" then
        if value[1] == 0 and value[2] == 0 then return nil end
        return value
    end
    return nil
end

local function IdList(value)
    if type(value) == "table" and #value > 0 then return value end
    return nil
end

local function Number(value)
    return tonumber(value) or 0
end

-- Questie's verdict as a DoableStates NAME. returnText MUST be true: without
-- it the function answers AVAILABLE for everything.
local function ReadState(db, questId)
    if not ready then return nil end
    local ok, text, _, reason = pcall(db.IsDoableVerbose, questId, false, true, false)
    if not ok then
        NoteError("IsDoableVerbose", text)
        return nil
    end
    return stateNames[reason]
end

-- summaryOnly leaves the givers out: a background summary needs the verdict
-- and the counting fields, and the NPC name and spawn reads behind every
-- starter and finisher are most of what a fact costs. The engine's totals
-- never read them; only a full view (the window, the drawer, the pins) does.
local function BuildFact(db, questId, layer, prefer, summaryOnly)
    local v = Try("QueryQuest", db.QueryQuest, questId, FACT_KEYS)
    if type(v) ~= "table" then return nil end
    local corrections = Module("QuestieCorrections")
    local hidden = corrections and type(corrections.hiddenQuests) == "table" and corrections.hiddenQuests[questId] or nil
    local event = Module("QuestieEvent")
    local oneWay = db.questsOnlyAvailableUntilReputationValue
    local specialFlags, questFlags = Number(v[F.specialFlags]), Number(v[F.questFlags])
    local zoneOrSort = v[F.zoneOrSort]
    local exclusiveTo = IdList(v[F.exclusiveTo])
    local fact = {
        id = questId,
        name = v[F.name],
        questLevel = Number(v[F.questLevel]),
        requiredLevel = Number(v[F.requiredLevel]),
        requiredMaxLevel = Number(v[F.requiredMaxLevel]),
        state = ReadState(db, questId),
        preSingle = IdList(v[F.preQuestSingle]),
        preGroup = IdList(v[F.preQuestGroup]),
        nextInChain = Number(v[F.nextQuestInChain]),
        exclusiveTo = exclusiveTo,
        breadcrumbFor = Number(v[F.breadcrumbForQuestId]),
        parent = Number(v[F.parentQuest]),
        minRep = Pair(v[F.requiredMinRep]),
        maxRep = Pair(v[F.requiredMaxRep]),
        skill = Pair(v[F.requiredSkill]),
        -- specialFlags bit 1 = repeatable, questFlags bit 4096 = daily; plain
        -- arithmetic, no bit library assumed
        repeatable = math.floor(specialFlags % 2) == 1,
        daily = math.floor(questFlags / 4096) % 2 == 1,
        event = (event and Try("IsEventQuest", event.IsEventQuest, questId)) and true or false,
        hiddenOnMap = (hidden ~= nil and hidden == HideOnMapValue()) and true or false,
        oneWayRep = ((type(oneWay) == "table" and oneWay[questId]) or ONE_WAY_REP_EXTRA[questId]) and true or false,
        layer = layer,
        objectivesText = IdList(v[F.objectivesText]),
        zoneOrSort = zoneOrSort,
        tag = TagFor(zoneOrSort),
    }
    forwardCache[questId] = exclusiveTo or false
    if summaryOnly then
        fact.starters, fact.finishers, fact.startsHere = {}, {}, true
        return fact
    end
    fact.starters = ReadGivers(v[F.startedBy], prefer)
    fact.finishers = ReadGivers(v[F.finishedBy], prefer)
    fact.startsHere = false
    for _, starter in ipairs(fact.starters) do
        if starter.zone and prefer[starter.zone] then fact.startsHere = true end
    end
    if not fact.startsHere then
        for _, starter in ipairs(fact.starters) do
            if starter.zone then
                fact.startZoneName = A.ZoneName(starter.zone)
                break
            end
        end
    end
    return fact
end

local function BuildFacts(areaId, summaryOnly)
    local db = QuestDB()
    local facts = {}
    if not db then return facts, 0 end
    local core, coreSeen = CoreMembers(areaId)
    local extras = ExtraMembers(areaId, coreSeen)
    -- Starter records carry normalized zones, so the view key alone covers
    -- its subzones and folded wings
    local prefer = { [areaId] = true }
    for _, questId in ipairs(core) do
        local fact = BuildFact(db, questId, "ZONE", prefer, summaryOnly)
        if fact then facts[#facts + 1] = fact end
    end
    for _, questId in ipairs(extras) do
        local fact = BuildFact(db, questId, "EXTRA", prefer, summaryOnly)
        if fact then facts[#facts + 1] = fact end
    end
    return facts, #core + #extras
end

-- ---------------------------------------------------------------------------
-- The character
-- ---------------------------------------------------------------------------

local function PlayerLevel()
    local player = Module("QuestiePlayer")
    local level = player and Try("GetPlayerLevel", player.GetPlayerLevel) or nil
    if type(level) ~= "number" or level < 1 then
        level = (UnitLevel and UnitLevel("player")) or 1
    end
    return level
end

-- Read fresh on every call: Questie reassigns the table. Non-daily
-- repeatables are stored as false, so this is a truth test.
local function IsComplete(questId)
    local complete = CompleteTable()
    return (complete and complete[questId]) and true or false
end

local function IsInLog(questId)
    if C_QuestLog and C_QuestLog.IsOnQuest then
        local ok, onQuest = pcall(C_QuestLog.IsOnQuest, questId)
        if ok then return onQuest and true or false end
    end
    local player = Module("QuestiePlayer")
    local log = player and player.currentQuestlog
    return (type(log) == "table" and log[questId] ~= nil) and true or false
end

-- Ready / failed for a quest in the log, read off the client where it can
-- be: the window's scan (logIndex) only exists while the window is open, and
-- the map drawer asks with it closed -- the normal case while questing -- so
-- a quest whose objectives filled with the window shut would read "log" and
-- send its waypoint to the giver instead of the turn-in. isComplete is the
-- era's tri-state (1 done, -1 failed). GetQuestLogIndexByID answers 0 for a
-- quest under a collapsed heading, and the scan does NOT cover that: it
-- expands every heading first (D3), so it never sees one collapsed later in
-- the stock log, or before the window's first open. IsQuestComplete asks by
-- questID whatever the headings (Blizzard's own quest map provider calls it
-- so); its answer is believed only when it says complete -- its signature on
-- this client is unverified (A35), and "not complete" or failed still needs
-- the indexed read or the scan. Never Questie's QuestLogCache.GetQuest: it
-- prints an error for a quest not in its cache.
local function LogInfo(questId)
    if type(questId) ~= "number" then return nil end
    if GetQuestLogIndexByID and GetQuestLogTitle then
        local ok, index = pcall(GetQuestLogIndexByID, questId)
        if ok and type(index) == "number" and index > 0 then
            local read, title, _, _, isHeader, _, isComplete = pcall(GetQuestLogTitle, index)
            if read and title and not isHeader then
                return { complete = (isComplete == 1) or (isComplete == true), failed = isComplete == -1 }
            end
        end
    end
    if IsQuestComplete and IsInLog(questId) then
        local ok, complete = pcall(IsQuestComplete, questId)
        if ok and (complete == true or complete == 1) then return { complete = true, failed = false } end
    end
    return logIndex[questId]
end

local function ForwardPeers(questId)
    local cached = forwardCache[questId]
    if cached ~= nil then return cached or EMPTY end
    -- Once the sweep has read every quest, an id it left unrecorded has none
    if reverseDone then return EMPTY end
    local list = QueryQuestSingle(questId, "exclusiveTo")
    if type(list) ~= "table" or #list == 0 then list = false end
    forwardCache[questId] = list
    return list or EMPTY
end

-- The engine's char.exclusiveTo: the quest's OWN list, the only one Questie
-- (and so the engine) decides by
local function ExclusiveTo(questId)
    return ForwardPeers(questId)
end

-- exclusiveTo forward, plus every quest that lists this one, for NAMING a
-- choice only: exclusiveTo is one-way in Questie, so a quest that merely
-- names this one decides nothing about it. Until the sweep finishes,
-- forward only. The lists returned are shared: read-only.
local function ExclusivePeers(questId)
    local cached = peerCache[questId]
    if cached then return cached end
    local out, seen = {}, { [questId] = true }
    for _, peer in ipairs(ForwardPeers(questId)) do
        if type(peer) == "number" and not seen[peer] then
            seen[peer] = true
            out[#out + 1] = peer
        end
    end
    for _, peer in ipairs(reverse[questId] or EMPTY) do
        if not seen[peer] then
            seen[peer] = true
            out[#out + 1] = peer
        end
    end
    peerCache[questId] = out
    return out
end

-- The engine's char.isGone: Questie's verdict on a quest OUTSIDE the view is
-- final (GONE_STATES). One IsDoableVerbose per asked id per generation;
-- the engine asks only about prerequisites of locked quests.
local function IsGone(questId)
    if type(questId) ~= "number" then return false end
    if goneGeneration ~= A.generation then
        goneCache, goneGeneration = {}, A.generation
    end
    local cached = goneCache[questId]
    if cached ~= nil then return cached end
    local db = QuestDB()
    local state = db and Exists(questId) and ReadState(db, questId) or nil
    local gone = (state ~= nil and GONE_STATES[state]) and true or false
    goneCache[questId] = gone
    return gone
end

local function QuestName(questId)
    local cached = questNames[questId]
    if cached then return cached end
    local name = QueryQuestSingle(questId, "name")
    if type(name) ~= "string" then return nil end
    questNames[questId] = name
    return name
end

local function QuestZoneName(questId)
    local zoneOrSort = QueryQuestSingle(questId, "zoneOrSort")
    if type(zoneOrSort) ~= "number" or zoneOrSort == 0 then return nil end
    if zoneOrSort < 0 then return SortName(zoneOrSort) end
    local area = NormalizeArea(zoneOrSort)
    return area and A.ZoneName(area) or nil
end

-- name, barValue. Asked for the sixth return directly: `f and f(x)` would
-- truncate to one value.
local function FactionInfo(factionId)
    if not (GetFactionInfoByID and type(factionId) == "number") then return nil end
    local ok, name, _, _, _, _, barValue = pcall(GetFactionInfoByID, factionId)
    if not ok or type(name) ~= "string" then return nil end
    return name, barValue
end

local function RepValue(factionId)
    local name, value = FactionInfo(factionId)
    if name and type(value) == "number" then return value end
    return nil
end

local function FactionName(factionId)
    return (FactionInfo(factionId))
end

-- A profession's name for "Needs 300 Alchemy." Questie keys its professions
-- by skill-line id, the same id requiredSkill carries; without an answer the
-- engine says "profession skill 300" instead.
local function SkillName(skillId)
    local professions = Module("QuestieProfessions")
    if not (professions and type(skillId) == "number") then return nil end
    local name = Try("GetProfessionName", professions.GetProfessionName, professions, skillId)
    if Named(name) then return Localise(name) end
    return nil
end

local function IgnoredSet()
    local charDB = CommanderQuestLogChar
    local ignored = type(charDB) == "table" and charDB.Ignored or nil
    if type(ignored) == "table" then return ignored end
    return {}
end

-- The engine's `char` (SPEC 2.3), built from live state on every pass
function A.Character()
    local db = type(CommanderQuestLogDB) == "table" and CommanderQuestLogDB or EMPTY
    return {
        level = PlayerLevel(),
        isComplete = IsComplete,
        isInLog = IsInLog,
        logInfo = LogInfo,
        exclusiveTo = ExclusiveTo,
        exclusivePeers = ExclusivePeers,
        isGone = IsGone,
        questName = QuestName,
        questZoneName = QuestZoneName,
        repValue = RepValue,
        factionName = FactionName,
        skillName = SkillName,
        rivals ={ [932] = RIVALS[932], [934] = RIVALS[934] },
        ignored = IgnoredSet(),
        opts = {
            countOptional = db.CountOptional == true,
            countRival = db.CountRival == true,
            countExtras = db.CountExtras == true,
        },
    }
end

-- The window's latest Q.Scan() entries. Whether a quest in the log is ready
-- or failed changes the guide order, so a change in that set is a Bump.
function A.SetLogEntries(entries)
    local index, parts = {}, {}
    for _, entry in ipairs(List(entries)) do
        if type(entry) == "table" and not entry.isHeader and type(entry.questID) == "number" and entry.questID > 0 then
            local complete, failed = entry.isComplete and true or false, entry.isFailed and true or false
            index[entry.questID] = { complete = complete, failed = failed }
            parts[#parts + 1] = entry.questID .. (complete and "c" or "") .. (failed and "f" or "")
        end
    end
    table.sort(parts)
    local signature = table.concat(parts, ",")
    logIndex = index
    if signature ~= logSignature and next(views) then A.Bump("log") end
    logSignature = signature
end

-- ---------------------------------------------------------------------------
-- Generations: one step and one listener call per burst
-- ---------------------------------------------------------------------------

local ScheduleSummaryTick    -- forward

local function Flush()
    pending = false
    if not dirty then return end
    dirty = false
    A.generation = A.generation + 1
    lastReasons = table.concat(reasons, ", ")
    reasons = {}
    -- Cached views are keyed by generation and go stale on their own. A
    -- background summary job is NOT rewound: it carries on and works the
    -- zones it has left out against the new generation. Rewinding every job
    -- on every step kept a zone-menu job (whose menu had long closed)
    -- rebuilding whole zones twenty times a second through a dungeon's worth
    -- of reputation kills. The drawer re-asks for whatever is not current on
    -- its own redraw, and a menu reads the last known figure until it next
    -- opens.
    if #summaryJobs > 0 then ScheduleSummaryTick() end
    for _, listener in ipairs(listeners) do
        local ok, err = pcall(listener, A.generation)
        if not ok then
            NoteError("listener", err)
            if geterrorhandler then geterrorhandler()(err) end
        end
    end
end

function A.Bump(reason)
    if not Detected() then return end
    dirty = true
    reason = tostring(reason or "?")
    local known = false
    for _, seen in ipairs(reasons) do if seen == reason then known = true end end
    if not known then reasons[#reasons + 1] = reason end
    if pending then return end
    pending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(DEBOUNCE_SECONDS, Flush)
    else
        Flush()
    end
end

function A.AddListener(fn)
    if type(fn) ~= "function" then return end
    for _, existing in ipairs(listeners) do
        if existing == fn then return end
    end
    listeners[#listeners + 1] = fn
end

-- ---------------------------------------------------------------------------
-- The reverse exclusive index
--
-- exclusiveTo is not symmetric in Questie's data: a quest can be named by a
-- quest that it does not list itself. Questie treats that as ONE-WAY (a
-- quest is blocked only by its own list), and so does the engine, so the
-- reverse half of this index only ever NAMES a choice. What the sweep is
-- worth is its forward half: it reads every quest's exclusiveTo once --
-- about 6,700 reads -- into the forward cache, so char.exclusiveTo never
-- needs a query of its own afterwards. It runs REVERSE_CHUNK per frame after
-- ready, and the generation steps when it is done.
-- ---------------------------------------------------------------------------

local function ReverseStep()
    local job = reverseJob
    if not job then return end
    local db = QuestDB()
    if not (db and type(db.QueryQuestSingle) == "function") then
        reverseJob = nil
        return
    end
    local last = math.min(job.at + REVERSE_CHUNK - 1, #job.ids)
    for i = job.at, last do
        local questId = job.ids[i]
        local ok, list = pcall(db.QueryQuestSingle, questId, "exclusiveTo")
        if ok and type(list) == "table" and #list > 0 then
            forwardCache[questId] = list
            job.listed = job.listed + 1
            for _, peer in ipairs(list) do
                if type(peer) == "number" then
                    job.reverse[peer] = job.reverse[peer] or {}
                    local bucket = job.reverse[peer]
                    bucket[#bucket + 1] = questId
                end
            end
        end
    end
    job.at = last + 1
    job.ticks = job.ticks + 1
    if job.at > #job.ids then
        reverse = job.reverse
        reverseDone = true
        reverseJob = nil
        A.reverseStats = { quests = #job.ids, listed = job.listed, ticks = job.ticks }
        peerCache = {}
        A.Bump("exclusive index")
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0, ReverseStep)
    else
        ReverseStep()
    end
end

local function StartReverseIndex()
    local pointers = QuestPointers()
    if not pointers then
        reverseDone = true
        return
    end
    local ids = {}
    for questId in pairs(pointers) do
        if type(questId) == "number" then ids[#ids + 1] = questId end
    end
    table.sort(ids)
    reverseJob = { ids = ids, at = 1, reverse = {}, listed = 0, ticks = 0 }
    if C_Timer and C_Timer.After then
        C_Timer.After(0, ReverseStep)
    else
        ReverseStep()
    end
end

-- ---------------------------------------------------------------------------
-- Readiness and state
-- ---------------------------------------------------------------------------

local function OnQuestieReady()
    if ready or broken then return end
    local db = QuestDB()
    local states = db and db.DoableStates
    if type(states) ~= "table" then
        broken = "QuestieDB.DoableStates is missing"
        return
    end
    local names = {}
    for name, value in pairs(states) do
        if type(name) == "string" and type(value) == "number" then names[value] = name end
    end
    stateNames = names
    local missing = Missing(REQUIRED) or Missing(REQUIRED_READY)
    if not missing and not CompleteTable() then missing = "Questie.db.char.complete is missing" end
    if missing then
        broken = missing
        return
    end
    ready = true
    StartReverseIndex()
    A.Bump("ready")
end

-- Runs inside Questie's init coroutine (QuestieInit.lua:342-343) under
-- xpcall: note it and leave, the work happens a frame later
local function OnReadyCallback()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, OnQuestieReady)
    else
        OnQuestieReady()
    end
end

local function PollReady(tries)
    if not Detected() then return end
    if Questie.API.isReady then
        OnReadyCallback()
    elseif tries < READY_POLL_TRIES and C_Timer and C_Timer.After then
        C_Timer.After(READY_POLL_SECONDS, function() PollReady(tries + 1) end)
    else
        broken = "Questie never reported ready"
    end
end

local function OnQuestieUpdate()
    A.Bump("questie update")
end

local function Attach()
    if attached or not Detected() then return end
    attached = true
    local api = Questie.API
    if type(api.RegisterForQuestUpdates) == "function" then
        local ok, err = pcall(api.RegisterForQuestUpdates, OnQuestieUpdate)
        if not ok then NoteError("RegisterForQuestUpdates", err) end
    end
    if type(api.RegisterOnReady) == "function" then
        local ok, err = pcall(api.RegisterOnReady, OnReadyCallback)
        if not ok then broken = "Questie.API.RegisterOnReady failed: " .. tostring(err) end
    else
        PollReady(0)
    end
end

-- "ABSENT" | "LOADING" | "READY" | "BROKEN", reason
function A.State()
    if not Detected() then return "ABSENT", "Questie is not loaded" end
    Attach()
    if broken then return "BROKEN", broken end
    local missing = Missing(REQUIRED)
    if missing then return "BROKEN", missing end
    if not (Questie.API.isReady and ready) then return "LOADING", "Questie is still loading" end
    missing = Missing(REQUIRED_READY)
    if not missing and not CompleteTable() then missing = "Questie.db.char.complete is missing" end
    if missing then return "BROKEN", missing end
    return "READY", nil
end

local function OnSettingsChanged()
    A.Bump("settings")
end

-- Called by the window at PLAYER_LOGIN; also runs on its own at
-- PLAYER_LOGIN below, so calling it twice is fine. Commander Orders loads
-- first (OptionalDeps), so its resolver table is there by now.
function A.Init()
    if not initialised then
        initialised = true
        if Commander and Commander.AddListener and COMMANDER_QUESTLOG_EVENTS and COMMANDER_QUESTLOG_EVENTS.UPDATE then
            local ok, err = pcall(Commander.AddListener, COMMANDER_QUESTLOG_EVENTS.UPDATE, OnSettingsChanged)
            if not ok then NoteError("AddListener", err) end
        end
    end
    if A.RegisterResolvers then A.RegisterResolvers() end
    Attach()
end

-- ---------------------------------------------------------------------------
-- Zone views and summaries
-- ---------------------------------------------------------------------------

local function Engine()
    local engine = Q.Completion
    if type(engine) == "table" and type(engine.BuildZone) == "function" then return engine end
    return nil
end

local function SummaryOf(view)
    local engine = Engine()
    if engine and type(engine.Summary) == "function" then
        local ok, summary = pcall(engine.Summary, view)
        if ok and type(summary) == "table" then
            return { counted = summary.counted or 0, done = summary.done or 0, pct = summary.pct }
        end
    end
    local totals = type(view) == "table" and type(view.totals) == "table" and view.totals or EMPTY
    local counted, done = totals.counted or 0, totals.done or 0
    return { counted = counted, done = done, pct = (counted > 0) and (done / counted) or nil }
end

-- A view straight from the engine, cache untouched. nil, err when none:
-- the state name, "ENGINE" (engine missing), "NO_ZONE", "NO_QUESTS" (Questie
-- files nothing here and no giver stands here), "ENGINE_ERROR" or
-- "ADAPTER_ERROR" (Questie answered in a shape this file did not expect).
local function BuildView(areaId, summaryOnly)
    local state = A.State()
    if state ~= "READY" then return nil, state end
    local engine = Engine()
    if not engine then return nil, "ENGINE" end
    if type(areaId) ~= "number" then return nil, "NO_ZONE" end
    local built, facts, members = pcall(BuildFacts, areaId, summaryOnly)
    if not built then
        NoteError("BuildFacts", facts)
        return nil, "ADAPTER_ERROR"
    end
    if members == 0 then return nil, "NO_QUESTS" end
    local ok, view = pcall(engine.BuildZone, facts, A.Character(), { areaId = areaId, name = A.ZoneName(areaId) })
    if not ok then
        NoteError("BuildZone", view)
        return nil, "ENGINE_ERROR"
    end
    if type(view) ~= "table" then return nil, "ENGINE_ERROR" end
    return view
end

local function RecordSummary(areaId, view)
    local summary = view and SummaryOf(view) or { counted = 0, done = 0 }
    summary.generation = A.generation
    summary.areaId = areaId
    summaries[areaId] = summary
    return summary
end

local function TouchView(areaId)
    for i = #viewOrder, 1, -1 do
        if viewOrder[i] == areaId then table.remove(viewOrder, i) end
    end
    viewOrder[#viewOrder + 1] = areaId
    while #viewOrder > VIEW_CACHE_SIZE do
        views[table.remove(viewOrder, 1)] = nil
    end
end

function A.ZoneView(areaId)
    local slot = views[areaId]
    if slot and slot.generation == A.generation then
        TouchView(areaId)
        return slot.view
    end
    local view, err = BuildView(areaId)
    if not view then
        if err == "NO_QUESTS" then RecordSummary(areaId, nil) end
        return nil, err
    end
    views[areaId] = { view = view, generation = A.generation }
    TouchView(areaId)
    RecordSummary(areaId, view)
    return view
end

-- { counted, done, pct, generation } or nil when not computed this
-- generation. allowStale (an addition to the spec) answers the last known
-- figure instead, for a label that should not blink while it recomputes.
function A.ZoneSummary(areaId, allowStale)
    local summary = summaries[areaId]
    if summary and (allowStale or summary.generation == A.generation) then return summary end
    return nil
end

-- A summary is built from facts without their givers (BuildFact's
-- summaryOnly), and the view it came from is not kept: the counts are the
-- same, and it costs a fraction of a full view
local function ComputeSummary(areaId)
    local slot = views[areaId]
    if slot and slot.generation == A.generation then return RecordSummary(areaId, slot.view) end
    local view, err = BuildView(areaId, true)
    if view or err == "NO_QUESTS" then return RecordSummary(areaId, view) end
    return nil
end

local function SummaryTick()
    summaryTickPending = false
    if A.State() ~= "READY" then
        summaryJobs = {}
        return
    end
    local job = summaryJobs[1]
    while job and job.at > #job.ids do
        table.remove(summaryJobs, 1)
        job = summaryJobs[1]
    end
    if not job then return end
    -- Zones already current are reported without costing the tick; one real
    -- computation per tick
    while job.at <= #job.ids do
        local areaId = job.ids[job.at]
        job.at = job.at + 1
        local summary = A.ZoneSummary(areaId)
        local computed = false
        if not summary then
            summary = ComputeSummary(areaId)
            computed = true
        end
        if summary and job.onEach then
            local ok, err = pcall(job.onEach, areaId, summary)
            if not ok then NoteError("summary callback", err) end
        end
        if computed then break end
    end
    -- By identity: a callback may have queued or replaced jobs meanwhile
    if job.at > #job.ids then
        for i = #summaryJobs, 1, -1 do
            if summaryJobs[i] == job then table.remove(summaryJobs, i) end
        end
    end
    if #summaryJobs > 0 then ScheduleSummaryTick() end
end

function ScheduleSummaryTick()
    if summaryTickPending then return end
    if not (C_Timer and C_Timer.After) then return end
    summaryTickPending = true
    C_Timer.After(SUMMARY_TICK_SECONDS, SummaryTick)
end

-- Background job: one zone per tick, skipping zones already current,
-- calling onEach(areaId, summary) as each lands. A second request with the
-- same onEach replaces the first rather than queueing behind it.
function A.RequestSummaries(areaIds, onEach)
    if type(areaIds) ~= "table" then return end
    local job
    for _, existing in ipairs(summaryJobs) do
        if onEach and existing.onEach == onEach then job = existing end
    end
    if not job then
        job = { onEach = onEach }
        summaryJobs[#summaryJobs + 1] = job
    end
    job.ids = {}
    for _, areaId in ipairs(areaIds) do
        if type(areaId) == "number" then job.ids[#job.ids + 1] = areaId end
    end
    job.at = 1
    ScheduleSummaryTick()
end

-- ---------------------------------------------------------------------------
-- Zone lists
-- ---------------------------------------------------------------------------

local function ByName(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.areaId < b.areaId
end

-- One Journey category's zones that hold quests, minus keys folded into
-- another view (a wing is listed as its group). The Dungeons category also
-- takes the raid keys Questie files quests under but leaves out of its own
-- Journey list (Serpentshrine Cavern 3607, Magtheridon's Lair 3836), or
-- their quests would have a counted zone view nothing could open.
local DUNGEON_CATEGORY = 9

local function CategoryZones(category)
    local out = {}
    local journey = Module("QuestieJourney")
    local list = journey and type(journey.zones) == "table" and journey.zones[category] or nil
    if type(list) ~= "table" then return out end
    for areaId, journeyName in pairs(list) do
        if type(areaId) == "number" and areaId > 0 and not SUBZONE_FOLD[areaId]
            and not INSTANCE_GROUP[areaId] and HasMembers(areaId) then
            local name = A.ZoneName(areaId)
            if name == "Zone " .. areaId and Named(journeyName) then name = journeyName end
            out[#out + 1] = { areaId = areaId, name = name }
        end
    end
    if category == DUNGEON_CATEGORY then
        for areaId in pairs(RAID_AREAS) do
            if list[areaId] == nil and not INSTANCE_GROUP[areaId] and HasMembers(areaId) then
                out[#out + 1] = { areaId = areaId, name = A.ZoneName(areaId) }
            end
        end
    end
    table.sort(out, ByName)
    return out
end

-- { { key = 1, text = "Eastern Kingdoms", zones = { { areaId, name }, ... } }, ... }
-- Eastern Kingdoms, Kalimdor, Outland, Dungeons, then the player's class.
function A.ZoneMenu()
    local menu = {}
    if A.State() ~= "READY" then return menu end
    local journey = Module("QuestieJourney")
    local continents = journey and type(journey.continents) == "table" and journey.continents or EMPTY
    for _, category in ipairs(MENU_CATEGORIES) do
        local zones = CategoryZones(category)
        if #zones > 0 then
            menu[#menu + 1] = {
                key = category,
                text = Named(continents[category]) and continents[category] or CATEGORY_NAMES[category],
                zones = zones,
            }
        end
    end
    local classKey = PlayerClassKey()
    if classKey and HasMembers(classKey) then
        local className = A.ZoneName(classKey)
        menu[#menu + 1] = {
            key = CLASS_CATEGORY,
            text = Named(continents[CLASS_CATEGORY]) and continents[CLASS_CATEGORY] or CATEGORY_NAMES[CLASS_CATEGORY],
            zones = { { areaId = classKey, name = className } },
        }
    end
    return menu
end

-- The zone children of a continent map that hold quests
function A.ContinentZones(uiMapId)
    local out, seen = {}, {}
    if A.State() ~= "READY" or type(uiMapId) ~= "number" then return out end
    local function Add(areaId, childUiMapId)
        if areaId and not seen[areaId] and HasMembers(areaId) then
            seen[areaId] = true
            out[#out + 1] = {
                areaId = areaId, uiMapId = childUiMapId or A.UiMapForArea(areaId), name = A.ZoneName(areaId),
            }
        end
    end
    if C_Map and C_Map.GetMapChildrenInfo then
        local zoneType = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or ZONE_MAP_TYPE
        local children = Try("GetMapChildrenInfo", C_Map.GetMapChildrenInfo, uiMapId, zoneType)
        for _, child in ipairs(List(children)) do
            if type(child) == "table" and type(child.mapID) == "number" then
                local areaId, kind = A.ZoneForMap(child.mapID)
                if kind == "ZONE" then Add(areaId, child.mapID) end
            end
        end
    end
    if #out == 0 then
        for _, category in ipairs(CONTINENT_CATEGORIES[uiMapId] or EMPTY) do
            for _, zone in ipairs(CategoryZones(category)) do Add(zone.areaId, nil) end
        end
    end
    table.sort(out, ByName)
    return out
end

-- {x, y} in 0..100 on that zone's map, or nil when the player is not on it
function A.PlayerPos(areaId)
    local uiMapId = A.UiMapForArea(areaId)
    if not (uiMapId and C_Map and C_Map.GetPlayerMapPosition) then return nil end
    local position = Try("GetPlayerMapPosition", C_Map.GetPlayerMapPosition, uiMapId, "player")
    if type(position) ~= "table" then return nil end
    local x, y = position.x, position.y
    if (type(x) ~= "number" or type(y) ~= "number") and type(position.GetXY) == "function" then
        x, y = Try("GetXY", position.GetXY, position)
    end
    if type(x) ~= "number" or type(y) ~= "number" or (x == 0 and y == 0) then return nil end
    return { x = x * 100, y = y * 100 }
end

-- ---------------------------------------------------------------------------
-- One quest: detail, finisher, best starter
-- ---------------------------------------------------------------------------

local function CachedEntry(areaId, questId)
    local slot = areaId and views[areaId]
    if not (slot and slot.generation == A.generation) then return nil end
    local byId = slot.view.byId
    return type(byId) == "table" and byId[questId] or nil
end

local function QuestRef(questId)
    return { id = questId, name = QuestName(questId), done = IsComplete(questId), zoneName = QuestZoneName(questId) }
end

local function EffectiveLevels(fact)
    local engine = Q.Completion
    if type(engine) == "table" and type(engine.EffectiveLevel) == "function" then
        local ok, level, required = pcall(engine.EffectiveLevel, fact, A.Character())
        if ok and level then return level, required end
    end
    local playerLevel = PlayerLevel()
    local level = fact.questLevel == -1 and playerLevel or fact.questLevel
    local required = fact.requiredLevel == -1 and playerLevel or fact.requiredLevel
    return level, required
end

-- Everything the briefing shows for one quest, read lazily. Every field is
-- named: { id, name, level, requiredLevel, objectivesText, starters,
-- finishers, prereqs = { { id, name, done, zoneName } }, followups = {...},
-- repRewards = { { factionName, value, factionId } }, tag, zoneName }
function A.QuestDetail(questId, viewAreaId)
    if A.State() ~= "READY" or not Exists(questId) then return nil end
    local db = QuestDB()
    local entry = CachedEntry(viewAreaId, questId)
    local fact = entry and entry.fact
    if type(fact) ~= "table" then
        fact = BuildFact(db, questId, "ZONE", viewAreaId and { [viewAreaId] = true } or {})
    end
    if not fact then return nil end
    local level, requiredLevel = EffectiveLevels(fact)
    local detail = {
        id = questId, name = fact.name or QuestName(questId), level = level, requiredLevel = requiredLevel,
        objectivesText = fact.objectivesText or {}, starters = fact.starters or {}, finishers = fact.finishers or {},
        prereqs = {}, followups = {}, repRewards = {}, tag = fact.tag, zoneName = QuestZoneName(questId),
    }
    local seen = {}
    for _, id in ipairs(List(fact.preSingle)) do
        if type(id) == "number" and not seen[id] then seen[id] = true; detail.prereqs[#detail.prereqs + 1] = QuestRef(id) end
    end
    for _, id in ipairs(List(fact.preGroup)) do
        id = type(id) == "number" and math.abs(id) or nil
        if id and not seen[id] then seen[id] = true; detail.prereqs[#detail.prereqs + 1] = QuestRef(id) end
    end
    -- Follow-ups: Questie has no reverse index, so the forward pointers plus
    -- whatever in the viewed zone names this quest as a prerequisite
    seen = { [questId] = true }
    local function Follow(id)
        if type(id) == "number" and id > 0 and not seen[id] and Exists(id) then
            seen[id] = true
            detail.followups[#detail.followups + 1] = QuestRef(id)
        end
    end
    Follow(fact.nextInChain)
    Follow(fact.breadcrumbFor)
    local slot = viewAreaId and views[viewAreaId]
    if slot and slot.generation == A.generation then
        for _, other in ipairs(List(slot.view.entries)) do
            local otherFact = type(other) == "table" and other.fact
            if type(otherFact) == "table" then
                for _, id in ipairs(List(otherFact.preSingle)) do if id == questId then Follow(otherFact.id) end end
                for _, id in ipairs(List(otherFact.preGroup)) do
                    if id == questId or id == -questId then Follow(otherFact.id) end
                end
            end
        end
    end
    for _, reward in ipairs(List(QueryQuestSingle(questId, "reputationReward"))) do
        if type(reward) == "table" and type(reward[1]) == "number" then
            detail.repRewards[#detail.repRewards + 1] = {
                factionId = reward[1], value = reward[2],
                factionName = FactionName(reward[1]) or ("Faction " .. reward[1]),
            }
        end
    end
    return detail
end

-- Every placed spawn of one giver in a list of giver records (one record per
-- spawn, as ReadGivers makes them), as { uiMapId, x, y } with x, y in 0..100:
-- the nearest-of-N candidates a waypoint carries, so the arrow goes to the
-- spawn nearest the player rather than the first one Questie lists. nil for
-- a giver with fewer than two (one spawn is just the waypoint itself).
function A.SpawnsOf(records, giver)
    if type(records) ~= "table" or type(giver) ~= "table" then return nil end
    local out = {}
    for _, record in ipairs(records) do
        if type(record) == "table" and record.kind == giver.kind and record.id == giver.id
            and (record.id ~= nil or record.name == giver.name)
            and type(record.x) == "number" and type(record.y) == "number" then
            local uiMapId = record.uiMapId or (UiMapForSpawn(record.areaId))
            if uiMapId then out[#out + 1] = { uiMapId = uiMapId, x = record.x, y = record.y } end
        end
    end
    if #out < 2 then return nil end
    return out
end

local function PackGiver(giver, records)
    return {
        name = giver.name, areaId = giver.areaId, x = giver.x, y = giver.y, uiMapId = giver.uiMapId,
        kind = giver.kind, id = giver.id, zoneName = giver.areaId and A.ZoneName(giver.areaId) or nil,
        spawns = A.SpawnsOf(records, giver),
    }
end

-- Where to hand the quest in: { name, areaId, zoneName, x, y, uiMapId, spawns }
-- with a spawn in the player's zone preferred. Coordinates are nil when Questie
-- knows the finisher but not where it stands. spawns is every placed spawn of
-- that finisher (up to MAX_FINISHER_SPAWNS), for the waypoint's nearest-of-N.
function A.Finisher(questId)
    if A.State() ~= "READY" or not Exists(questId) then return nil end
    local here = A.ZoneForPlayer()
    local givers = ReadGivers(QueryQuestSingle(questId, "finishedBy"), here and { [here] = true } or nil,
        MAX_FINISHER_SPAWNS)
    local best
    for _, giver in ipairs(givers) do
        if giver.x and here and giver.zone == here then best = giver; break end
    end
    if not best then
        for _, giver in ipairs(givers) do
            if giver.x then best = giver; break end
        end
    end
    best = best or givers[1]
    if not best then return nil end
    return PackGiver(best, givers)
end

-- The first placed starter record in the viewed zone, else the first
-- anywhere (the raw record and the list it came from)
local function PlacedStarter(item, viewAreaId)
    if type(item) ~= "table" then return nil end
    local starters = item.starters
    if type(starters) ~= "table" and type(item.fact) == "table" then starters = item.fact.starters end
    if type(starters) ~= "table" then return nil end
    if viewAreaId then
        for _, starter in ipairs(starters) do
            local zone = starter.zone or NormalizeArea(starter.areaId)
            if starter.x and starter.y and zone == viewAreaId then return starter, starters end
        end
    end
    for _, starter in ipairs(starters) do
        if starter.x and starter.y then return starter, starters end
    end
    return nil
end

-- The first starter spawn in the viewed zone, else the first anywhere
function A.BestStarter(item, viewAreaId)
    local starter, starters = PlacedStarter(item, viewAreaId)
    if not starter then return nil end
    return PackGiver(starter, starters)
end

-- Questie draws its own "!" for quests it considers available now; the map
-- pins skip those so the two never stack
function A.IsQuestieDrawing(questId)
    local available = Module("AvailableQuests")
    local set = available and available.__availableQuests
    return (type(set) == "table" and set[questId] == true) and true or false
end

-- Giver pins for one zone view on one map: { { x = 0..1, y = 0..1, quests = { entries } } }.
-- NPC and object starters whose spawn is on this uiMap (a subzone spawn
-- counts on its parent's map), givers within PIN_MERGE_PERCENT of each other
-- sharing a pin, at most MAX_PIN_SPAWNS_PER_QUEST spawns per quest.
function A.PinsFor(areaId, uiMapId)
    local pins = {}
    local view = A.ZoneView(areaId)
    if not view then return pins end
    uiMapId = uiMapId or A.UiMapForArea(areaId)
    if not uiMapId then return pins end
    for _, entry in ipairs(List(view.entries)) do
        local used, joined = 0, {}
        for _, starter in ipairs(List(entry.starters)) do
            if used >= MAX_PIN_SPAWNS_PER_QUEST then break end
            if (starter.kind == "npc" or starter.kind == "object") and starter.x and starter.y
                and (starter.uiMapId or UiMapForSpawn(starter.areaId)) == uiMapId then
                used = used + 1
                local pin
                for _, existing in ipairs(pins) do
                    local dx, dy = existing.px - starter.x, existing.py - starter.y
                    if dx * dx + dy * dy <= PIN_MERGE_PERCENT * PIN_MERGE_PERCENT then pin = existing; break end
                end
                if not pin then
                    pin = { x = starter.x / 100, y = starter.y / 100, px = starter.x, py = starter.y,
                            name = starter.name, quests = {} }
                    pins[#pins + 1] = pin
                end
                if not joined[pin] then
                    joined[pin] = true
                    pin.quests[#pin.quests + 1] = entry
                end
            end
        end
    end
    return pins
end

-- ---------------------------------------------------------------------------
-- Waypoints: the Commander Orders arrow, else a /way line in the chat frame
--
-- Orders is the suite's navigation (it replaced TomTom), and this is the one
-- place in the module that calls it -- through its public table, looked up at
-- call time, because Orders may be absent or turned off. A quest's waypoint
-- is OWNED: source "QuestLog", key "quest:<id>", so pressing Waypoint again
-- on the same quest moves its one waypoint (from the giver to the turn-in,
-- say) instead of stacking a second. It carries every placed spawn of its
-- giver as alternatives, so the arrow walks to the nearest spawn and re-picks
-- as the player moves, where TomTom was handed whichever spawn Questie listed
-- first (D35). A refusal -- Orders absent, turned off, or a map with no world
-- position -- prints the place and the /way line, because a Waypoint button
-- that does nothing is worse than one that says where to go (D27).
--
-- The same table answers Orders' "entrance" question for dungeon maps from
-- Questie's own dungeon data, so a quest giver inside a dungeon, or a ghost
-- whose corpse lies in one, is pointed at the way in rather than at a map the
-- open world has no arrow for.
-- ---------------------------------------------------------------------------

local function Orders()
    local api = CommanderOrders
    if type(api) == "table" and type(api.Add) == "function" then return api end
    return nil
end

-- The API when it will take a waypoint now; nil, "ABSENT" | "OFF" when not
local function OrdersReady()
    local api = Orders()
    if not api then return nil, "ABSENT" end
    if type(api.IsAvailable) == "function" then
        local ok, available = pcall(api.IsAvailable)
        if ok and not available then return nil, "OFF" end
    end
    return api
end

-- "ORDERS" | "ORDERS_OFF" | "PRINT": where a Waypoint press goes, so the
-- tooltips can say it before it is pressed
function A.WaypointPath()
    local api, why = OrdersReady()
    if api then return "ORDERS" end
    if why == "OFF" then return "ORDERS_OFF" end
    return "PRINT"
end

-- A.SpawnsOf's { uiMapId, x, y } in 0..100 -> Orders' alternatives in 0..1
local function Alternatives(spawns)
    if type(spawns) ~= "table" then return nil end
    local out = {}
    for _, spawn in ipairs(spawns) do
        local x, y = tonumber(spawn.x), tonumber(spawn.y)
        if type(spawn.uiMapId) == "number" and x and y then
            out[#out + 1] = { map = spawn.uiMapId, x = x / 100, y = y / 100 }
        end
    end
    if #out < 2 then return nil end
    return out
end

-- The command that puts a place on anybody's arrow (Orders' and TomTom's
-- /way both read it), x and y in 0..100
local function WayLine(uiMapId, x, y, title)
    return string.format("/way #%d %.2f %.2f %s", uiMapId, x, y, title)
end

-- target = { title, areaId, x, y } with x, y in 0..100; optional uiMapId,
-- zoneName, questId (the waypoint's key) and spawns (A.SpawnsOf's list).
-- Returns "ORDERS" or "PRINT" (nil for no target).
function A.Waypoint(target)
    if type(target) ~= "table" then return nil end
    local title = target.title or target.name or "Waypoint"
    local x, y = tonumber(target.x), tonumber(target.y)
    local uiMapId = target.uiMapId or (target.areaId and A.UiMapForArea(target.areaId)) or nil
    if x and y and uiMapId then
        local api = OrdersReady()
        if api then
            local questId = tonumber(target.questId)
            -- Orders answers nil and a reason (turned off, no world
            -- position) rather than raising; the pcall is for a stranger
            local ok, uid = pcall(api.Add, {
                map = uiMapId, x = x / 100, y = y / 100, title = title,
                source = "QuestLog", key = questId and ("quest:" .. questId) or nil,
                alternatives = Alternatives(target.spawns), icon = "QUEST", setArrow = true,
            })
            if ok and uid then return "ORDERS" end
        end
    end
    local zone = target.zoneName or (target.areaId and A.ZoneName(target.areaId)) or nil
    local where = zone and (" \226\128\148 " .. zone) or ""
    if x and y and uiMapId then
        print(string.format("Commander Quest Log: |cffffd100%s|r%s %.1f, %.1f   %s", title, where, x, y,
            WayLine(uiMapId, x, y, title)))
    elseif x and y then
        print(string.format("Commander Quest Log: |cffffd100%s|r%s %.1f, %.1f", title, where, x, y))
    else
        print(string.format("Commander Quest Log: |cffffd100%s|r%s", title, where))
    end
    return "PRINT"
end

-- "Route open quests here": one stop per quest giver of the zone's OPEN
-- quests -- bucket AVAILABLE, the drawer's "Open" group, so not the ignored,
-- daily, seasonal or optional ones -- at the giver's spawn in the zone when it
-- has one, with its other spawns as alternatives. A giver with several open
-- quests is ONE stop, titled with the first and how many more. Item starters
-- and givers Questie cannot place are left out. Pure over the zone view: the
-- Zones tab asks it to light its Route button, RouteOpen hands it to Orders.
-- Each stop: { title, giver, uiMapId, x, y (0..100), spawns, quests }.
function A.RouteStops(areaId)
    local stops = {}
    local view = A.ZoneView(areaId)
    if type(view) ~= "table" then return stops end
    local byGiver = {}
    for _, entry in ipairs(List(view.entries)) do
        if type(entry) == "table" and entry.status == "AVAILABLE" then
            local giver, records = PlacedStarter(entry, areaId)
            local uiMapId = giver and (giver.uiMapId or (UiMapForSpawn(giver.areaId)))
            if uiMapId and (giver.kind == "npc" or giver.kind == "object") then
                local key = giver.kind .. ":" .. tostring(giver.id or giver.name)
                local stop = byGiver[key]
                if not stop then
                    stop = { giver = giver.name, uiMapId = uiMapId, x = giver.x, y = giver.y,
                             spawns = A.SpawnsOf(records, giver), quests = {} }
                    byGiver[key] = stop
                    stops[#stops + 1] = stop
                end
                stop.quests[#stop.quests + 1] = entry.title or ("Quest " .. tostring(entry.id))
            end
        end
    end
    for _, stop in ipairs(stops) do
        local more = #stop.quests - 1
        stop.title = (Named(stop.giver) and (stop.giver .. ": ") or "") .. stop.quests[1]
            .. (more > 0 and string.format(" (+%d)", more) or "")
    end
    return stops
end

-- Hand the zone's open-quest givers to Orders as ONE nearest-first route,
-- owned as (QuestLog, "open:<areaId>") so asking again replaces it rather
-- than stacking a second. Says what happened in chat either way. Returns
-- "ORDERS", stops | nil, "NO_ORDERS" | "ORDERS_OFF" | "NOTHING" | "REFUSED".
function A.RouteOpen(areaId)
    local zone = (type(areaId) == "number" and A.ZoneName(areaId)) or "this zone"
    local api, why = OrdersReady()
    if not (api and type(api.AddRoute) == "function") then
        if why == "OFF" then
            print("Commander Quest Log: Commander Orders is turned off (/corder), so there is no arrow to route.")
            return nil, "ORDERS_OFF"
        end
        print("Commander Quest Log: a route needs Commander Orders, which is not loaded.")
        return nil, "NO_ORDERS"
    end
    local stops = A.RouteStops(areaId)
    if #stops == 0 then
        print("Commander Quest Log: no open quest in " .. zone .. " has a giver Questie can place.")
        return nil, "NOTHING"
    end
    local specs = {}
    for i, stop in ipairs(stops) do
        specs[i] = { map = stop.uiMapId, x = stop.x / 100, y = stop.y / 100, title = stop.title,
                     alternatives = Alternatives(stop.spawns), icon = "QUEST" }
    end
    local ok, id = pcall(api.AddRoute, {
        title = "Open quests: " .. zone, source = "QuestLog", key = "open:" .. areaId,
        mode = "NEAREST", stops = specs, start = true,
    })
    if not (ok and id) then
        print("Commander Quest Log: Commander Orders would not take that route.")
        return nil, "REFUSED"
    end
    print(string.format("Commander Quest Log: routed %d quest giver%s in %s, nearest first. Follow the arrow.",
        #stops, #stops == 1 and "" or "s", zone))
    return "ORDERS", #stops
end

-- Orders' "entrance" resolver: a DUNGEON uiMap -> its way in, outside, from
-- Questie's dungeon table (ZoneDB:GetDungeonLocation, the entrances
-- GiverRecords puts in place of a dungeon's -1,-1 sentinel). A floor map with
-- no areaId of its own is tried through its dungeon-map parents. Only dungeon
-- maps are asked about: Questie's uiMap -> areaId bridge falls back to a name
-- match over every area it knows for a map it has no row for, which is no
-- price to pay for a zone. Answers are cached per map once Questie is ready
-- (its tables are static), and handed out as copies (Orders keeps a world
-- position cache on the table it is given).
--
-- Two corrections over Questie (2026-10-04 review):
--   * ENTRANCE_AREA_FIX. Questie's OVERRIDE table maps uiMap 246 to 3713,
--     The Blood Furnace (QuestieDB/support/Zones/uiMapIdToAreaId.lua:15),
--     and the override wins over its own correct base row (:217, 246 ->
--     3714). On this build's UiMap DB2 246 IS The Shattered Halls
--     (UiMapAssignment ties instance 540, area 3714, to it; the Blood
--     Furnace is 261), so without this every question about 246 got the
--     Blood Furnace's door, across the citadel. Known-bad rows only.
--   * Orphan maps. This build types The Black Morass (273), Old Hillsbrad
--     Foothills (274), Hyjal Summit (329), Zul'Aman (333), Zul'Farrak
--     (219), Zul'Gurub (233, 337), Dire Maul (234) and the Ruins of
--     Ahn'Qiraj (247) as Orphan (6), not Dungeon (4). The map ASKED about
--     may be an Orphan when Questie's explicit row turns it into an area with
--     a dungeon location (every one of the nine has such a row, so the name
--     fallback never runs for them); the parent walk stays on Dungeon maps,
--     because an Orphan's parent is a zone.
-- { map = uiMapId, x, y (0..1), title } | nil
local entranceCache = {}
local ENTRANCE_AREA_FIX = { [246] = 3714 }    -- uiMap -> the area Questie should have answered
local ORPHAN_MAP_TYPE = 6                     -- Enum.UIMapType.Orphan

function A.Entrance(uiMapId)
    if type(uiMapId) ~= "number" then return nil end
    local found = entranceCache[uiMapId]
    if found == nil then
        if A.State() ~= "READY" then return nil end
        local zoneDB = Module("ZoneDB")
        local getMapInfo = C_Map and C_Map.GetMapInfo
        if not (zoneDB and getMapInfo) then return nil end
        found = false
        local map = uiMapId
        for _ = 1, 4 do
            local info = Try("GetMapInfo", getMapInfo, map)
            if type(info) ~= "table" then break end
            local orphan = map == uiMapId and info.mapType == ORPHAN_MAP_TYPE
            if info.mapType ~= DUNGEON_MAP_TYPE and not orphan then break end
            -- Throws for a map it cannot match: an answer, not an error
            local ok, areaId = true, ENTRANCE_AREA_FIX[map]
            if not areaId then ok, areaId = pcall(zoneDB.GetAreaIdByUiMapId, zoneDB, map) end
            if ok and type(areaId) == "number" and areaId > 0 then
                for _, entrance in ipairs(List(DungeonEntrances(areaId))) do
                    entrance = List(entrance)
                    local x, y = tonumber(entrance[2]), tonumber(entrance[3])
                    local outside = UiMapForSpawn(entrance[1])
                    if outside and x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
                        local name = Try("GetLocalizedDungeonName", zoneDB.GetLocalizedDungeonName, zoneDB, areaId)
                        found = { map = outside, x = x / 100, y = y / 100,
                                  title = (Named(name) and name or info.name or "Dungeon") .. " entrance" }
                        break
                    end
                end
            end
            if found then break end
            map = info.parentMapID
        end
        entranceCache[uiMapId] = found
    end
    if not found then return nil end
    return { map = found.map, x = found.x, y = found.y, title = found.title }
end

-- Registered once, by A.Init (and again on a later Init if Orders was not
-- there yet). The resolver is one stable function: Orders keeps one copy.
local function EntranceResolver(uiMapId)
    return A.Entrance(uiMapId)
end

local resolverRegistered = false

function A.RegisterResolvers()
    if resolverRegistered then return true end
    local api = Orders()
    if not (api and type(api.RegisterResolver) == "function") then return false end
    local ok, done = pcall(api.RegisterResolver, "entrance", EntranceResolver)
    resolverRegistered = (ok and done) and true or false
    return resolverRegistered
end

-- ---------------------------------------------------------------------------
-- /cql status
-- ---------------------------------------------------------------------------

local PATH_WORDS = {
    ORDERS = "the Commander Orders arrow",
    ORDERS_OFF = "the chat frame (Commander Orders is turned off)",
    PRINT = "the chat frame (Commander Orders is not loaded)",
}

function A.StatusLines()
    local lines = {}
    local state, reason = A.State()
    -- The namespaced call where the client has it, the era's global where not
    local version
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        version = Try("GetAddOnMetadata", C_AddOns.GetAddOnMetadata, "Questie", "Version")
    elseif GetAddOnMetadata then
        version = Try("GetAddOnMetadata", GetAddOnMetadata, "Questie", "Version")
    end
    lines[#lines + 1] = "Questie: " .. state .. (reason and (" \226\128\148 " .. reason) or "")
        .. (Named(version) and (" (version " .. version .. ")") or "")
    lines[#lines + 1] = "Completion engine: " .. (Engine() and "loaded" or "missing")
    if reverseDone then
        local stats = A.reverseStats or EMPTY
        lines[#lines + 1] = string.format("Exclusive-choice index: complete (%d quests read, %d list a choice)",
            stats.quests or 0, stats.listed or 0)
    elseif reverseJob then
        lines[#lines + 1] = string.format("Exclusive-choice index: building, %d of %d",
            reverseJob.at - 1, #reverseJob.ids)
    else
        lines[#lines + 1] = "Exclusive-choice index: not started"
    end
    lines[#lines + 1] = "Generation: " .. A.generation .. (lastReasons ~= "" and (" (last: " .. lastReasons .. ")") or "")
    local areaId, name = A.ZoneForPlayer()
    if areaId then
        local uiMapId = A.UiMapForArea(areaId)
        lines[#lines + 1] = string.format("Your zone: %s (area %d%s)", name or "?", areaId,
            uiMapId and (", map " .. uiMapId) or "")
    else
        lines[#lines + 1] = "Your zone: not resolved"
    end
    local summaryCount = 0
    for _ in pairs(summaries) do summaryCount = summaryCount + 1 end
    lines[#lines + 1] = string.format("Cached: %d zone view%s, %d zone summar%s", #viewOrder,
        #viewOrder == 1 and "" or "s", summaryCount, summaryCount == 1 and "y" or "ies")
    lines[#lines + 1] = "Waypoints go to " .. PATH_WORDS[A.WaypointPath()]
    if Orders() then
        lines[#lines + 1] = "Dungeon entrances for Commander Orders: "
            .. (resolverRegistered and "answered from Questie" or "not registered")
    end
    if lastError then lines[#lines + 1] = "Last error: " .. lastError end
    return lines
end

-- ---------------------------------------------------------------------------
-- The public entry points degrade, they never raise
--
-- Every Questie call above is already pcall'd, but the code AROUND those calls
-- still trusts the answers to have the documented shape. Should a Questie
-- update hand back something else, the window's refresh or the map drawer
-- must lose a section, not throw: each entry point that walks Questie data
-- runs under pcall, answers its empty value on failure, and leaves the error
-- for /cql status.
-- ---------------------------------------------------------------------------

do
    local function EmptyList() return {} end
    local function NoView() return nil, "ADAPTER_ERROR" end
    local function NoStatus() return { "Questie adapter error: " .. tostring(lastError) } end
    local GUARDED = {
        ZoneView = NoView, ZoneMenu = EmptyList, ContinentZones = EmptyList, PinsFor = EmptyList,
        QuestDetail = false, Finisher = false, BestStarter = false, ZoneForMap = false,
        ZoneForPlayer = false, PlayerPos = false, Waypoint = false, RequestSummaries = false,
        SetLogEntries = false, StatusLines = NoStatus, SpawnsOf = false, RouteStops = EmptyList,
        RouteOpen = false, Entrance = false, RegisterResolvers = false,
    }
    for name, fallback in pairs(GUARDED) do
        local inner = A[name]
        A[name] = function(...)
            local results = { pcall(inner, ...) }
            if results[1] then return unpack(results, 2, table.maxn(results)) end
            NoteError(name, results[2])
            if fallback then return fallback() end
            return nil
        end
    end
end

-- ---------------------------------------------------------------------------
-- Harness accessors
-- ---------------------------------------------------------------------------

function A._Facts(areaId)
    if A.State() ~= "READY" then return nil end
    return (BuildFacts(areaId))
end

function A._ReverseProgress()
    if reverseJob then return reverseJob.at - 1, #reverseJob.ids, reverseJob.ticks, false end
    local stats = A.reverseStats or EMPTY
    return stats.quests or 0, stats.quests or 0, stats.ticks or 0, reverseDone
end

function A._CacheInfo()
    local order = {}
    for i, areaId in ipairs(viewOrder) do order[i] = areaId end
    return { views = #viewOrder, order = order, jobs = #summaryJobs }
end

function A._LastError()
    return lastError
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

-- The client's clock, or nil (the late bump then re-arms for any event in
-- its window rather than only the ones it does not already cover)
local function ClockNow()
    if not GetTime then return nil end
    local ok, now = pcall(GetTime)
    return (ok and type(now) == "number") and now or nil
end

-- The late look after Questie's bucket; bumps when it fires, and once more a
-- bucket later if an event it did not cover arrived in the meantime
local function ArmLateBump(event)
    lateBumpPending, lateBumpAgain = true, false
    local now = ClockNow()
    lateBumpAt = now and (now + QUESTIE_BUCKET_SECONDS) or nil
    C_Timer.After(QUESTIE_BUCKET_SECONDS, function()
        A.Bump(event .. " (Questie cache)")
        if lateBumpAgain then
            ArmLateBump(event)
        else
            lateBumpPending, lateBumpAt = false, nil
        end
    end)
end

if CreateFrame then
    local ok, frame = pcall(CreateFrame, "Frame")
    if ok and frame then
        pcall(frame.RegisterEvent, frame, "PLAYER_LOGIN")
        for _, event in ipairs(BUMP_EVENTS) do pcall(frame.RegisterEvent, frame, event) end
        frame:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_LOGIN" then
                A.Init()
                return
            end
            A.Bump(event)
            -- This bump lands before Questie has refreshed the caches its
            -- verdicts read (a threshold inside a standing tier, a skill-up,
            -- a new profession), and nothing tells us when it has: ask again
            -- once Questie's own 2 s bucket has run. Trailing edge: an event
            -- that arrives while that look is pending, and later than it
            -- covers, gets one of its own after it, so every such event is
            -- followed by a bump at least a bucket later.
            if (event == "UPDATE_FACTION" or event == "SKILL_LINES_CHANGED") and C_Timer and C_Timer.After then
                if not lateBumpPending then
                    ArmLateBump(event)
                else
                    local now = ClockNow()
                    if not (now and lateBumpAt and now + QUESTIE_BUCKET_SECONDS <= lateBumpAt + LATE_BUMP_SLACK) then
                        lateBumpAgain = true
                    end
                end
            end
        end)
    end
end
