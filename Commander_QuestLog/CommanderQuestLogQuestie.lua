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
--
-- Reputation (1.6.0) is the block before the guarded entry points, with its
-- own header: the faction index, faction views on their own cache, and the
-- one reputation number every surface shows for a quest -- worked out by the
-- rules engine (CommanderQuestLogStanding.lua), never by Questie's own
-- GetReputationReward.

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
    "objectivesText", "zoneOrSort", "requiredRaces", "requiredClasses", "reputationReward",
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
-- Faction views and their summaries: a cache of their own, because faction
-- ids collide with area ids (47 is Ironforge and The Hinterlands). One table,
-- not three locals: this chunk is within forty of Lua's 200. The reputation
-- block below fills in the hooks (Annotate, ComputeSummary, Pending) the
-- shared code here calls. waypointNotes[questId] is the reputation note
-- A.Waypoint last wrote on that quest's Orders waypoint (kept current there).
local repCache = { views = {}, order = {}, summaries = {}, waypointNotes = {} }

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
        -- Questie's raw signed points, { {factionId, value}, ... } or nil;
        -- what they are worth is the rules engine's (repEffects, set on a
        -- full view by the reputation block)
        repRows = IdList(v[F.reputationReward]),
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
    if signature ~= logSignature and (next(views) or next(repCache.views)) then A.Bump("log") end
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

-- A view straight from the engine over one set of quests, cache untouched:
-- the zone views and the faction views share it, and keep separate caches.
-- collect(key, summaryOnly) -> facts, members, meta[, char[, extra]]; a
-- meta-less answer is a zone's. nil, err when none: the state name, "ENGINE"
-- (engine missing), `missing` (a key that is not a number), "NO_QUESTS"
-- (nothing here), "ENGINE_ERROR" or "ADAPTER_ERROR" (Questie answered in a
-- shape this file did not expect). A full view's facts get their reputation
-- effects (repCache.Annotate); a summary's do not need them.
local function BuildViewOver(key, collect, summaryOnly, missing)
    local state = A.State()
    if state ~= "READY" then return nil, state end
    local engine = Engine()
    if not engine then return nil, "ENGINE" end
    if type(key) ~= "number" then return nil, missing end
    local built, facts, members, meta, char, extra = pcall(collect, key, summaryOnly)
    if not built then
        NoteError("BuildFacts", facts)
        return nil, "ADAPTER_ERROR"
    end
    if members == 0 then return nil, "NO_QUESTS" end
    meta = meta or { areaId = key, name = A.ZoneName(key) }
    local ok, view = pcall(engine.BuildZone, facts, char or A.Character(), meta)
    if not ok then
        NoteError("BuildZone", view)
        return nil, "ENGINE_ERROR"
    end
    if type(view) ~= "table" then return nil, "ENGINE_ERROR" end
    if not summaryOnly and repCache.Annotate then
        local annotated, err = pcall(repCache.Annotate, view)
        if not annotated then NoteError("reputation effects", err) end
    end
    return view, nil, extra
end

local function BuildView(areaId, summaryOnly)
    return BuildViewOver(areaId, BuildFacts, summaryOnly, "NO_ZONE")
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
    -- A faction job waits while the faction index is still being read (it
    -- steps the generation when done, and the job carries on from there)
    local faction = job.kind == "FACTION"
    if faction and repCache.Pending and repCache.Pending() then
        ScheduleSummaryTick()
        return
    end
    -- Zones already current are reported without costing the tick; one real
    -- computation per tick
    while job.at <= #job.ids do
        local key = job.ids[job.at]
        job.at = job.at + 1
        local summary
        if faction then summary = A.FactionSummary and A.FactionSummary(key) else summary = A.ZoneSummary(key) end
        local computed = false
        if not summary then
            if faction then
                if repCache.ComputeSummary then
                    local ok, computedSummary = pcall(repCache.ComputeSummary, key)
                    if ok then summary = computedSummary else NoteError("faction summary", computedSummary) end
                end
            else
                summary = ComputeSummary(key)
            end
            computed = true
        end
        if summary and job.onEach then
            local ok, err = pcall(job.onEach, key, summary)
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
-- same onEach replaces the first rather than queueing behind it. kind
-- "FACTION" makes the ids faction ids, answered by A.FactionSummary from the
-- faction cache (never the zones': the two id spaces collide).
function A.RequestSummaries(areaIds, onEach, kind)
    if type(areaIds) ~= "table" then return end
    local job
    for _, existing in ipairs(summaryJobs) do
        if onEach and existing.onEach == onEach then job = existing end
    end
    if not job then
        job = { onEach = onEach }
        summaryJobs[#summaryJobs + 1] = job
    end
    job.kind = (kind == "FACTION" or kind == "faction") and "FACTION" or nil
    -- a faction job needs the faction index: start reading it now
    if job.kind and repCache.Pending then repCache.Pending() end
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

local function CachedEntry(areaId, questId, cache)
    local slot = areaId and (cache or views)[areaId]
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
-- repRewards = { { factionName, value, factionId } } (Questie's raw rows,
-- kept for what they are), repEffects and repLine (what the quest is worth
-- to this character now: the rules engine's one number, A.RepEffects /
-- A.RepLine; nil without the rules), tag, zoneName }. viewKind "FACTION"
-- makes viewAreaId a faction id, read from the faction cache: the two id
-- spaces collide.
function A.QuestDetail(questId, viewAreaId, viewKind)
    if A.State() ~= "READY" or not Exists(questId) then return nil end
    local db = QuestDB()
    local faction = viewKind == "FACTION"
    local cache = faction and repCache.views or views
    local entry = CachedEntry(viewAreaId, questId, cache)
    local fact = entry and entry.fact
    if type(fact) ~= "table" then
        fact = BuildFact(db, questId, "ZONE", (viewAreaId and not faction) and { [viewAreaId] = true } or {})
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
    local slot = viewAreaId and cache[viewAreaId]
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
    -- The one number (guarded entry points, cached per generation)
    if A.RepEffects then
        detail.repEffects = A.RepEffects(questId)
        if detail.repEffects then detail.repLine = A.RepLine(questId) end
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
-- zoneName, questId (the waypoint's key), spawns (A.SpawnsOf's list) and
-- note (Orders shows it in the waypoint's tooltip). A quest's waypoint is
-- noted with what the quest is worth (A.RepLine, "No reputation" included)
-- unless the target brings its own note, note = false, or the
-- ShowRepEverywhere setting is off; that note is kept current while the
-- waypoint lives (the reputation block's RefreshWaypointNotes). Returns
-- "ORDERS" or "PRINT" (nil for no target).
function A.Waypoint(target)
    if type(target) ~= "table" then return nil end
    local title = target.title or target.name or "Waypoint"
    local x, y = tonumber(target.x), tonumber(target.y)
    local uiMapId = target.uiMapId or (target.areaId and A.UiMapForArea(target.areaId)) or nil
    if x and y and uiMapId then
        local api = OrdersReady()
        if api then
            local questId = tonumber(target.questId)
            local note, ours = target.note, false
            if note == nil and questId and A.RepLine
                and not (type(CommanderQuestLogDB) == "table" and CommanderQuestLogDB.ShowRepEverywhere == false) then
                note, ours = A.RepLine(questId), true
            end
            -- Orders answers nil and a reason (turned off, no world
            -- position) rather than raising; the pcall is for a stranger
            local ok, uid = pcall(api.Add, {
                map = uiMapId, x = x / 100, y = y / 100, title = title, note = Named(note) and note or nil,
                source = "QuestLog", key = questId and ("quest:" .. questId) or nil,
                alternatives = Alternatives(target.spawns), icon = "QUEST", setArrow = true,
            })
            if ok and uid then
                if questId then repCache.waypointNotes[questId] = (ours and Named(note)) and note or nil end
                return "ORDERS"
            end
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
-- Reputation: one number per quest, the faction index, faction views
--
-- The Reputations tab lists every quest that pays a faction, and every
-- surface that shows a quest -- the Log's briefing, the Zones and
-- Reputations tabs, the map drawer, a waypoint's note, the NPC's own dialog
-- -- says what it is worth to this character now. One number, from one
-- place: the rules engine (Q.Standing, CommanderQuestLogStanding.lua) over
-- the generated data (CommanderQuestLogReputationData), fed Questie's raw
-- rows, the character's standings and the multiplier read at the moment of
-- asking. Never QuestieReputation.GetReputationReward: it never rounds, takes
-- a Human's rival loss from the raw value, has no reward clamp, boosts the
-- stored Sha'tar half and shows a Human +46200 for Ally of the Netherwing.
-- Questie supplies what only Questie knows: who can do a quest (its race-,
-- class- and blacklist-filtered zoneMap), what it holds back for a later
-- content phase, and which of today's rotating dailies the NPCs did not
-- offer.
--
-- The traps:
--
--   * Faction ids collide with area ids (47 is Ironforge and The
--     Hinterlands), so faction views live in repCache -- two of them, by
--     generation -- and never in the zone LRU the map drawer leans on.
--     A.QuestDetail takes viewKind "FACTION" to read from it, and a summary
--     job takes kind "FACTION".
--   * Membership is a DIRECT row: Questie's rows minus the generator's
--     `derived` (stored spillover: the Sha'tar's half on 85 Aldor and Scryers
--     quests is the server's spill, not a reward), with the audited
--     `overrides` on top. DirectRows mirrors the engine's own preparation,
--     and the adapter smoke holds the two together. A quest that reaches a
--     faction only through spillover is summarised, not listed -- except the
--     Sha'tar's window on the Aldor and Scryers quests (until Honored), which
--     a faction view lists in its EXTRA layer with fact.repVia = the source.
--   * The index reads every quest's rows once (some 6,700 reads, a decode
--     each in the real Questie), 400 a frame, started the first time a
--     faction is asked about rather than at login; it steps the generation
--     when it is done.
--   * A faction the character has not met may answer nil from
--     GetFactionInfoByID (A21). Its standing is then its Faction.db2 base for
--     this race and class (Netherwing -42000, Sporeggar -2500), never
--     "Neutral". The engine's char.repValue keeps its old meaning (unknown
--     never locks); char.standing is the new reading.
--   * The multiplier is read, never stored: Diplomacy by race file (every
--     locale answers it in English), the Wickerman by aura. A change in it
--     is a Bump, so a per-generation cache never outlives it.
--   * One quest can pay both sides' factions (the audited Hellfire Wanted
--     dailies pay Honor Hold AND Thrallmar): the engine is told the side.
--   * Questie's record of today's rotating dailies
--     (Questie.db.global.unavailableQuestsDeterminedByTalking[realm]) is read,
--     never written and never kept: Questie replaces it at the reset.
--   * "Not in this phase yet" counts the hidden quests that would pay the
--     faction and that Questie's own phase list names
--     (ContentPhases.BlacklistTbcQuestsByPhase, a pure function that fills
--     the table it is handed); without that list, every hidden one.
--   * Calibration. A turn-in's moves are found by a snapshot of every
--     standing, diffed on UPDATE_FACTION, with the chat line as a second
--     source. On an emulator the moves arrive BEFORE QUEST_TURNED_IN, so the
--     window runs both ways. Two turn-ins close enough to share a faction, or
--     a faction that moved twice in the window (a kill and the quest), make
--     that faction's sample ambiguous and it is set aside: a wrong sample
--     overrides the data, a lost one costs nothing. So is a move several of
--     the quest's own rows made between them (Orgrimmar on a quest that also
--     pays the Darkspear Trolls): it is a sum, and read back as one value it
--     was paid again on every share (R.MixedSources, 2026-10-04 review).
--
-- Lua 5.1 allows 200 locals in a function and this chunk is within forty of
-- that, so the block is one function, run once, with locals of its own. What
-- it publishes is on A; the hooks the shared code above calls are on
-- repCache.
-- ---------------------------------------------------------------------------

do
    local function InstallReputation()
        local INDEX_CHUNK = 400              -- quests whose rows the faction index reads per frame
        local FACTION_VIEW_CACHE_SIZE = 2
        local OBSERVE_BEFORE, OBSERVE_AFTER = 1.0, 2.0     -- seconds either side of a turn-in
        local MOVE_KEEP_SECONDS = 10
        local AURA_SETTLE_SECONDS = 0.5
        local DAILY_CAP = 25                 -- PLAYER_MAX_DAILY_QUESTS, when the client does not say
        local MAX_RANK = 7
        local WICKERMAN = 24705              -- Invocation of the Wickerman (Hallow's End), +10%
        local SEP = "  \194\183  "
        local FLOOR = math.floor
        -- The bases a quest is out of the running in, for the projections
        local GONE = { DONE = true, MISSED = true, RIVAL = true }
        -- The bases a daily earns in today (a locked one does not yet)
        local DAILY_OPEN = { AVAILABLE = true, LOG = true, DONE = true }

        -- ---- the rules and the data -----------------------------------------

        -- The engine and the generated data, or nil: without either there is
        -- no number to give, and every entry point says so quietly
        local function Rules()
            local R, D = Q.Standing, CommanderQuestLogReputationData
            if type(R) == "table" and type(R.Effects) == "function" and type(D) == "table"
                and type(D.factions) == "table" then
                return R, D
            end
            return nil
        end

        local function FactionRow(D, factionId)
            local row = D and factionId and D.factions[factionId]
            if type(row) == "table" then return row end
            return nil
        end

        -- ---- the character --------------------------------------------------

        -- Race, class and side, read until the client answers the race
        local player = {}
        local function Player()
            if player.read then return player end
            if UnitRace then
                local ok, _, raceFile, raceId = pcall(UnitRace, "player")
                if ok and tonumber(raceId) then
                    player.raceFile, player.raceId, player.read = raceFile, tonumber(raceId), true
                end
            end
            if UnitClass then
                local ok, _, _, classId = pcall(UnitClass, "player")
                if ok and tonumber(classId) then player.classId = tonumber(classId) end
            end
            if UnitFactionGroup then
                local ok, side = pcall(UnitFactionGroup, "player")
                if ok and (side == "Alliance" or side == "Horde") then player.side = side end
            end
            return player
        end

        -- R.Bit(raceId), R.Bit(classId): Faction.db2's masks
        local function Bits(R)
            local p = Player()
            return p.raceId and R.Bit(p.raceId) or nil, p.classId and R.Bit(p.classId) or nil
        end

        -- "Alliance" | "Horde": the client's word, else the data's reading of the race
        local function Side(R, D)
            local p = Player()
            if p.side then return p.side end
            if not p.read then return nil end
            if p.dataSide == nil then
                local raceBit = Bits(R)
                p.dataSide = (raceBit and R.Side(D, raceBit)) or false
            end
            return p.dataSide or nil
        end

        -- Is this aura on the player? By spell id through C_UnitAuras where the
        -- client has it, else a buff scan by spell id (UnitBuff exists on this
        -- client only behind the deprecation fallbacks)
        local function HasAura(spellId)
            local auras = C_UnitAuras
            if type(auras) == "table" and type(auras.GetPlayerAuraBySpellID) == "function" then
                local ok, aura = pcall(auras.GetPlayerAuraBySpellID, spellId)
                if ok then return aura ~= nil end
            end
            if type(auras) == "table" and type(auras.GetBuffDataByIndex) == "function" then
                for i = 1, 40 do
                    local ok, aura = pcall(auras.GetBuffDataByIndex, "player", i, "HELPFUL")
                    if not (ok and type(aura) == "table") then break end
                    if aura.spellId == spellId then return true end
                end
                return false
            end
            if UnitBuff then
                for i = 1, 40 do
                    -- name, icon, count, debuffType, duration, expirationTime,
                    -- source, isStealable, nameplateShowPersonal, spellId
                    local ok, name, _, _, _, _, _, _, _, _, id = pcall(UnitBuff, "player", i)
                    if not (ok and name) then break end
                    if id == spellId then return true end
                end
            end
            return false
        end

        -- Diplomacy by race file (English in every locale), the Wickerman by aura
        local function Mods(D)
            local spell = tonumber(type(D.rules) == "table" and D.rules.wickerman) or WICKERMAN
            return { human = Player().raceFile == "Human", wickerman = HasAura(spell) }
        end

        -- The multiplier, read once per generation (a change in it is a Bump)
        local pctValue, pctMods, pctGeneration = nil, nil, nil
        local function Pct(R, D)
            if pctGeneration ~= A.generation then
                pctMods = Mods(D)
                pctValue, pctGeneration = R.Multiplier(pctMods), A.generation
            end
            return pctValue, pctMods
        end

        local function Met(factionId)
            return FactionInfo(factionId) ~= nil
        end

        -- value, met: the bar value, or the Faction.db2 base for this race and
        -- class while the client has nothing for the faction (not met yet)
        local function CurrentStanding(R, D, factionId)
            local name, value = FactionInfo(factionId)
            if name and type(value) == "number" then return value, true end
            local raceBit, classBit = Bits(R)
            return R.Base(D, factionId, raceBit, classBit), false
        end

        local standings, standingGeneration = {}, nil
        local function StandingOf(factionId)
            local R, D = Rules()
            if not (R and type(factionId) == "number") then return nil, false end
            if standingGeneration ~= A.generation then standings, standingGeneration = {}, A.generation end
            local cached = standings[factionId]
            if not cached then
                local value, met = CurrentStanding(R, D, factionId)
                cached = { value, met }
                standings[factionId] = cached
            end
            return cached[1], cached[2]
        end

        -- char.standing: one value, the base for a faction not met
        local function StandingValue(factionId)
            return (StandingOf(tonumber(factionId)))
        end

        -- ---- names and words ------------------------------------------------

        local function LocaleCode()
            if not GetLocale then return nil end
            local ok, locale = pcall(GetLocale)
            if ok and type(locale) == "string" then return locale end
            return nil
        end

        -- The client's name (localised) once it has one, else this locale's
        -- name from the data (a faction not met yet), else the English one
        local clientNames = {}
        local function FactionDisplayName(factionId)
            factionId = tonumber(factionId)
            if not factionId then return nil end
            local cached = clientNames[factionId]
            if cached then return cached end
            local name = FactionInfo(factionId)
            if Named(name) then
                clientNames[factionId] = name
                return name
            end
            local _, D = Rules()
            local names = D and type(D.names) == "table" and D.names[LocaleCode() or ""] or nil
            local localised = type(names) == "table" and names[factionId] or nil
            if Named(localised) then return localised end
            local row = FactionRow(D, factionId)
            if row and Named(row.name) then return row.name end
            return "Faction " .. factionId
        end

        -- The client's standing labels, by standingID, for this character's
        -- sex (GetText picks the _FEMALE form); English fills any gap
        local labels
        local function Labels()
            if labels then return labels end
            local out, sex = {}, nil
            if UnitSex then
                local ok, value = pcall(UnitSex, "player")
                if ok then sex = value end
            end
            for n = 1, 8 do
                local token, text = "FACTION_STANDING_LABEL" .. n, nil
                if GetText then
                    local ok, value = pcall(GetText, token, sex)
                    if ok then text = value end
                end
                if not Named(text) then text = _G[token] end
                if Named(text) then out[n] = text end
            end
            labels = out
            return out
        end

        local function ItemName(itemId)
            if GetItemInfo then
                local ok, name = pcall(GetItemInfo, itemId)
                if ok and Named(name) then return name end
            end
            local db = QuestDB()
            local name = db and Try("QueryItemSingle", db.QueryItemSingle, itemId, "name") or nil
            if Named(name) then return name end
            return nil
        end

        local function DailyCap()
            if GetMaxDailyQuests then
                local ok, cap = pcall(GetMaxDailyQuests)
                if ok and tonumber(cap) and tonumber(cap) > 0 then return tonumber(cap) end
            end
            return DAILY_CAP
        end

        -- The calibration store, CommanderQuestLogChar.RepObserved (per
        -- character): made on the first sample, never before
        local function Store(create)
            local charDB = CommanderQuestLogChar
            if type(charDB) ~= "table" then return nil end
            local store = charDB.RepObserved
            if type(store) ~= "table" then
                if not create then return nil end
                store = {}
                charDB.RepObserved = store
            end
            return store
        end

        -- ---- what Questie knows ---------------------------------------------

        local function Rows(questId)
            local rows = QueryQuestSingle(questId, "reputationReward")
            if type(rows) == "table" then return rows end
            return EMPTY
        end

        -- Held back by Questie (a later phase, a removed quest), not merely
        -- kept off the map
        local function IsHidden(questId)
            local corrections = Module("QuestieCorrections")
            local hidden = corrections and type(corrections.hiddenQuests) == "table" and corrections.hiddenQuests[questId]
            return (hidden and hidden ~= HideOnMapValue()) and true or false
        end

        -- Questie's own list of the quests a later content phase holds back,
        -- or nil where it has none (not TBC, or a Questie that changed shape)
        local phaseSet, phaseRead = nil, false
        local function PhaseSet()
            if phaseRead then return phaseSet end
            if A.State() ~= "READY" then return nil end
            phaseRead = true
            local phases = Module("ContentPhases")
            local active = phases and type(phases.activePhases) == "table" and tonumber(phases.activePhases.TBC)
            local fill = phases and phases.BlacklistTbcQuestsByPhase
            if type(Questie) == "table" and Questie.IsTBC and active and type(fill) == "function" then
                local ok, set = pcall(fill, {}, active)
                if ok and type(set) == "table" then
                    phaseSet = set
                elseif not ok then
                    NoteError("BlacklistTbcQuestsByPhase", set)
                end
            end
            return phaseSet
        end

        -- The rotating dailies an NPC did not offer today, as Questie wrote
        -- them down -- read, never written, never kept
        local function Unavailable()
            local questie = Questie
            local db = type(questie) == "table" and questie.db
            local global = type(db) == "table" and db.global
            local byRealm = type(global) == "table" and global.unavailableQuestsDeterminedByTalking
            if type(byRealm) == "table" and GetRealmName then
                local ok, realm = pcall(GetRealmName)
                local list = ok and realm and byRealm[realm]
                if type(list) == "table" then return list end
            end
            local available = Module("AvailableQuests")
            local list = available and available.__unavailableQuestsDeterminedByTalking
            if type(list) == "table" then return list end
            return EMPTY
        end

        -- Never a candidate for today: a quest Questie holds back (the
        -- Magisters' Terrace pair) or does not know at all
        local function NeverOffered(questId)
            return not Exists(questId) or IsHidden(questId)
        end

        -- Server time now, and the daily reset just gone (from the client's
        -- countdown to the next); nil where the client cannot say
        local function ServerNow()
            if not GetServerTime then return nil end
            local ok, now = pcall(GetServerTime)
            return ok and tonumber(now) or nil
        end
        local function LastReset()
            local now = ServerNow()
            if not (now and GetQuestResetTime) then return nil end
            local ok, left = pcall(GetQuestResetTime)
            left = ok and tonumber(left) or nil
            if not (left and left > 0 and left <= 86400) then return nil end
            return now + left - 86400
        end

        -- When this session began (PLAYER_LOGIN), and the rotating dailies
        -- seen turned in during it, by server time
        local session = { start = nil, rotatingDone = {} }

        -- Today's Wanted dailies { NORMAL = questId, HEROIC = questId }, each
        -- only when it can be told: one in the log or done today settles its
        -- kind; otherwise Questie's record has to leave one candidate.
        -- "Done today": Questie's done list is rebuilt at login and never
        -- cleared at the reset (only its "not offered" record is), so in a
        -- session that has run through a reset yesterday's Wanted still reads
        -- done -- it counts only when the session began after the last reset
        -- or the turn-in was seen since (2026-10-04 review). A client that
        -- cannot say when the reset was keeps the plain reading.
        local function RotatingToday(R, D)
            local offered = {}
            local lastReset = LastReset()
            local fresh = not (lastReset and session.start) or session.start >= lastReset
            for questId in pairs(type(D.rotating) == "table" and D.rotating or EMPTY) do
                if type(questId) == "number" then
                    local seenAt = session.rotatingDone[questId]
                    local doneToday = IsComplete(questId)
                        and (fresh or (seenAt ~= nil and lastReset ~= nil and seenAt >= lastReset))
                    if IsInLog(questId) or doneToday then offered[questId] = true end
                end
            end
            return R.TodaysRotating(D, Unavailable(), { exclude = NeverOffered, offered = offered })
        end

        -- ---- one number per quest -------------------------------------------

        local function Effects(R, D, questId, rows, standingsOf, pct, store)
            return R.Effects(D, questId, rows, standingsOf, pct, { side = Side(R, D), store = store, labels = Labels() })
        end

        -- This generation's effects of one quest, worked out once and shared:
        -- read-only for every caller
        local effectsCache, effectsGeneration = {}, nil
        local function CachedEffects(R, D, questId)
            if effectsGeneration ~= A.generation then effectsCache, effectsGeneration = {}, A.generation end
            local effects = effectsCache[questId]
            if not effects then
                effects = Effects(R, D, questId, Rows(questId), StandingOf, (Pct(R, D)), Store(false))
                effectsCache[questId] = effects
            end
            return effects
        end

        -- A calibration sample that stands for the faction's OWN listed value
        -- on this quest (a done quest's estimate, a projection's raw), or nil:
        -- never a spill share, never a move several of its rows made (D40)
        local function OwnSample(R, D, store, questId, factionId, rows)
            if not store then return nil end
            if type(R.ObservedFor) ~= "function" then return R.Observed(store, questId, factionId) end
            return R.ObservedFor(D, store, questId, factionId, rows, Side(R, D))
        end

        -- What one quest does to every faction it moves, now: the rules
        -- engine's effects ({ {factionId, delta, kind = "DIRECT"|"SPILL"|
        -- "RIVAL", capped, capNote, observed, ...}, ... }, DIRECT first),
        -- shared and read-only. nil, why without an answer: "NO_RULES", the
        -- Questie state, "NO_QUEST", "UNKNOWN_QUEST". opts (never cached):
        -- rows (Questie's shape, for a quest Questie does not know), standings
        -- (a function or a table), pct, store (false: the data alone).
        function A.RepEffects(questId, opts)
            local R, D = Rules()
            if not R then return nil, "NO_RULES" end
            questId = tonumber(questId)
            if not questId then return nil, "NO_QUEST" end
            opts = (type(opts) == "table" and next(opts) ~= nil) and opts or nil
            local rows = opts and type(opts.rows) == "table" and opts.rows or nil
            if not rows then
                local state = A.State()
                if state ~= "READY" then return nil, state end
                if not Exists(questId) then return nil, "UNKNOWN_QUEST" end
            end
            if not opts then return CachedEffects(R, D, questId) end
            local store = Store(false)
            if opts.store ~= nil then store = opts.store or nil end
            return Effects(R, D, questId, rows or Rows(questId), opts.standings or StandingOf,
                tonumber(opts.pct) or (Pct(R, D)), store)
        end

        -- The same in words: "+275 Honor Hold", "+275 The Aldor  -302 The
        -- Scryers  +137 The Sha'tar", "No reputation"; nil without an answer.
        -- opts are R.Line's (compact, max, marks, none, abbrev), plus effects
        -- (words for these instead of asking). Also returns the effects.
        function A.RepLine(questId, opts)
            local R = Rules()
            if not R then return nil end
            opts = type(opts) == "table" and opts or {}
            local effects = type(opts.effects) == "table" and opts.effects or A.RepEffects(questId)
            if type(effects) ~= "table" then return nil end
            return R.Line(effects, FactionDisplayName, opts), effects
        end

        A.FactionName = FactionDisplayName

        -- The multiplier a listed value is paid at now (100; 110 for a Human;
        -- 10 more under the Wickerman), and the mods behind it
        function A.RepMultiplier()
            local R, D = Rules()
            if not R then return nil end
            local mods = Mods(D)
            return R.Multiplier(mods), mods
        end

        function A.RotatingToday()
            local R, D = Rules()
            if not R or A.State() ~= "READY" then return {} end
            return RotatingToday(R, D)
        end

        -- Every full view's facts carry their effects (BuildViewOver calls this)
        repCache.Annotate = function(view)
            local R, D = Rules()
            if not R then return end
            for _, entry in ipairs(List(view.entries)) do
                local fact = type(entry) == "table" and entry.fact
                if type(fact) == "table" and type(fact.id) == "number" then
                    fact.repEffects = CachedEffects(R, D, fact.id)
                end
            end
        end

        -- ---- the faction index ----------------------------------------------

        -- One quest's DIRECT rows as the rules engine reads them: Questie's
        -- rows minus the generator's derived (stored spillover) rows, rows for
        -- a faction with no standing slot dropped, the audited overrides on
        -- top (0 removes a row). { [factionId] = raw }. A mirror of the
        -- engine's own preparation, for membership.
        local function DirectRows(D, questId, rows)
            local out, derived = {}, {}
            local listed = type(D.derived) == "table" and D.derived[questId]
            if type(listed) == "table" then
                for key, value in pairs(listed) do
                    if type(key) == "number" and tonumber(value) then
                        derived[tonumber(value)] = true
                    elseif tonumber(key) and value == true then
                        derived[tonumber(key)] = true
                    end
                end
            end
            local known = next(D.factions) ~= nil
            for _, row in ipairs(List(rows)) do
                local factionId = type(row) == "table" and tonumber(row[1]) or nil
                local raw = type(row) == "table" and tonumber(row[2]) or nil
                if factionId and raw and raw ~= 0 and not derived[factionId] and out[factionId] == nil
                    and not (known and not D.factions[factionId]) then
                    out[factionId] = raw
                end
            end
            local overrides = type(D.overrides) == "table" and D.overrides[questId]
            if type(overrides) == "table" then
                for key, value in pairs(overrides) do
                    local factionId, raw = tonumber(key), tonumber(value)
                    if factionId and raw then out[factionId] = (raw ~= 0) and raw or nil end
                end
            end
            return out
        end

        -- byFaction[factionId][questId] = raw, over every quest Questie has
        local index = { state = "NONE" }

        local function IndexStep()
            local job = index
            if job.state ~= "BUILDING" then return end
            local R, D = Rules()
            local db = QuestDB()
            if not (R and db and type(db.QueryQuestSingle) == "function") then
                index = { state = "NONE" }
                return
            end
            local last = math.min(job.at + INDEX_CHUNK - 1, #job.ids)
            for i = job.at, last do
                local questId = job.ids[i]
                local ok, rows = pcall(db.QueryQuestSingle, questId, "reputationReward")
                local any = false
                for factionId, raw in pairs(DirectRows(D, questId, ok and rows or nil)) do
                    local list = job.byFaction[factionId]
                    if not list then
                        list = {}
                        job.byFaction[factionId] = list
                        job.factions = job.factions + 1
                    end
                    list[questId] = raw
                    any = true
                end
                if any then job.paying = job.paying + 1 end
            end
            job.at, job.ticks = last + 1, job.ticks + 1
            if job.at > #job.ids then
                job.state, job.quests, job.ids = "READY", #job.ids, nil
                A.Bump("faction index")
            elseif C_Timer and C_Timer.After then
                C_Timer.After(0, IndexStep)
            else
                IndexStep()
            end
        end

        -- Started the first time a faction is asked about, never at login: a
        -- character who never opens the Reputations tab never pays for it.
        -- Returns the index's state.
        local function StartIndex()
            if index.state ~= "NONE" then return index.state end
            if A.State() ~= "READY" or not Rules() then return index.state end
            local pointers = QuestPointers()
            if not pointers then return index.state end
            local ids = {}
            for questId in pairs(pointers) do
                if type(questId) == "number" then ids[#ids + 1] = questId end
            end
            table.sort(ids)
            index = { state = "BUILDING", ids = ids, at = 1, byFaction = {}, paying = 0, factions = 0, ticks = 0 }
            if C_Timer and C_Timer.After then
                C_Timer.After(0, IndexStep)
            else
                IndexStep()
            end
            return index.state
        end

        -- A faction summary job waits while this is true
        repCache.Pending = function()
            return StartIndex() == "BUILDING"
        end

        -- "NONE" | "BUILDING" | "READY", quests read so far, quests in all
        function A.FactionIndexState()
            if index.state == "BUILDING" then return "BUILDING", index.at - 1, #index.ids end
            if index.state == "READY" then return "READY", index.quests, index.quests end
            return "NONE", 0, 0
        end

        -- Every quest Questie would show this character: the union of its
        -- race-, class- and blacklist-filtered zoneMap, junk ids guarded out.
        -- Rebuilt once per generation; it is cheap.
        local visible, visibleGeneration = nil, nil
        local function VisibleSet()
            if visible and visibleGeneration == A.generation then return visible end
            local set = {}
            local zoneMap, pointers = ZoneMap(), QuestPointers()
            if zoneMap and pointers then
                for _, members in pairs(zoneMap) do
                    if type(members) == "table" then
                        for questId in pairs(members) do
                            if type(questId) == "number" and pointers[questId] then set[questId] = true end
                        end
                    end
                end
            end
            visible, visibleGeneration = set, A.generation
            return set
        end

        local function MaskHas(mask, id)
            mask = tonumber(mask) or 0
            if mask <= 0 or not id then return true end
            local bit = 2 ^ (id - 1)
            return FLOOR(mask / bit) % 2 == 1
        end

        -- A quest Questie holds back is out of its zoneMap, so its race and
        -- class are asked here
        local function ForThisCharacter(questId)
            local p = Player()
            return MaskHas(QueryQuestSingle(questId, "requiredRaces"), p.raceId)
                and MaskHas(QueryQuestSingle(questId, "requiredClasses"), p.classId)
        end

        local function PhaseHeld(questId, phases)
            return IsHidden(questId) and (not phases or phases[questId] and true or false) and ForThisCharacter(questId)
        end

        -- The spill edges INTO a faction: { {source, rate, maxRankIn}, ... }
        local edgesInto, edgesData = nil, nil
        local function EdgesInto(D, factionId)
            if edgesData ~= D then
                edgesInto, edgesData = {}, D
                for source, row in pairs(D.factions) do
                    for _, edge in ipairs(type(row) == "table" and type(row.spill) == "table" and row.spill or EMPTY) do
                        local target = type(edge) == "table" and tonumber(edge[1]) or nil
                        local rate = type(edge) == "table" and tonumber(edge[2]) or nil
                        if target and rate and rate ~= 0 then
                            edgesInto[target] = edgesInto[target] or {}
                            local list = edgesInto[target]
                            list[#list + 1] = { source = source, rate = rate, maxRankIn = tonumber(edge[3]) or MAX_RANK }
                        end
                    end
                end
                for _, list in pairs(edgesInto) do
                    table.sort(list, function(a, b) return a.source < b.source end)
                end
            end
            return edgesInto[factionId] or EMPTY
        end

        -- The quests that touch faction F, for this character:
        --   direct   visible quests with a DIRECT row for F (the view's rows)
        --   window   visible quests that pay F only through a spill window
        --            still open (the Sha'tar from the Aldor and the Scryers
        --            until Honored), with windowSource[questId] = the source
        --   shares   spill with no window (the capitals' quarter): counted
        --            and summed, never listed
        --   costs    quests that lower F: the rival's (a negative spill edge)
        --            and F's own negative rows, each with its estimated loss
        --   hidden   quests Questie holds back that would pay F, for this
        --            race and class
        local function Members(R, D, F)
            local byFaction = index.byFaction or EMPTY
            local mine = byFaction[F] or EMPTY
            local shown = VisibleSet()
            local rank = R.Rank(StandingOf(F) or 0)
            local pct = Pct(R, D)
            local phases = PhaseSet()
            local out = { direct = {}, window = {}, windowSource = {}, windowEdges = {}, shares = {}, costs = {}, hidden = {} }
            for questId, raw in pairs(mine) do
                if shown[questId] then
                    out.direct[#out.direct + 1] = questId
                    if raw < 0 then
                        out.costs[#out.costs + 1] = { questId = questId, source = F, raw = raw,
                            delta = R.RawGain(D, F, raw, pct), done = IsComplete(questId) }
                    end
                elseif PhaseHeld(questId, phases) then
                    out.hidden[#out.hidden + 1] = questId
                end
            end
            for _, edge in ipairs(EdgesInto(D, F)) do
                local from = byFaction[edge.source] or EMPTY
                if edge.rate > 0 and edge.maxRankIn < MAX_RANK then
                    local open = rank <= edge.maxRankIn
                    out.windowEdges[#out.windowEdges + 1] = { source = edge.source, rate = edge.rate,
                        maxRankIn = edge.maxRankIn, top = R.RankTop(edge.maxRankIn), open = open }
                    if open then
                        for questId, raw in pairs(from) do
                            if raw > 0 and shown[questId] and not mine[questId] and not out.windowSource[questId] then
                                out.windowSource[questId] = edge.source
                                out.window[#out.window + 1] = questId
                            end
                        end
                    end
                elseif edge.rate > 0 then
                    local share = { source = edge.source, rate = edge.rate, quests = 0, total = 0 }
                    for questId, raw in pairs(from) do
                        if raw > 0 and shown[questId] and not mine[questId] and not IsComplete(questId) then
                            share.quests = share.quests + 1
                            share.total = share.total + R.Trunc(R.RawGain(D, edge.source, raw, pct) * edge.rate)
                        end
                    end
                    if share.quests > 0 then out.shares[#out.shares + 1] = share end
                else
                    for questId, raw in pairs(from) do
                        if raw > 0 and shown[questId] then
                            out.costs[#out.costs + 1] = { questId = questId, source = edge.source, raw = raw,
                                delta = R.Trunc(R.RawGain(D, edge.source, raw, pct) * edge.rate),
                                done = IsComplete(questId) }
                        end
                    end
                end
            end
            table.sort(out.direct)
            table.sort(out.window)
            table.sort(out.hidden)
            table.sort(out.costs, function(a, b)
                if a.questId ~= b.questId then return a.questId < b.questId end
                return a.source < b.source
            end)
            return out
        end

        -- How many visible quests pay F directly, and how many Questie holds back
        local counts, countsGeneration = {}, nil
        local function CountFor(F)
            if countsGeneration ~= A.generation then counts, countsGeneration = {}, A.generation end
            local cached = counts[F]
            if cached then return cached[1], cached[2] end
            local shown, phases = VisibleSet(), PhaseSet()
            local quests, hidden = 0, 0
            for questId in pairs((index.byFaction or EMPTY)[F] or EMPTY) do
                if shown[questId] then
                    quests = quests + 1
                elseif PhaseHeld(questId, phases) then
                    hidden = hidden + 1
                end
            end
            counts[F] = { quests, hidden }
            return quests, hidden
        end

        -- ---- faction views --------------------------------------------------

        -- collect for BuildViewOver: the faction's quests as facts. Window
        -- quests are listed, never counted, whatever CountExtras says.
        local function FactionFacts(F, summaryOnly)
            local R, D = Rules()
            local db = QuestDB()
            if not (R and db) then return {}, 0 end
            local members = Members(R, D, F)
            local facts, prefer = {}, {}
            for _, questId in ipairs(members.direct) do
                local fact = BuildFact(db, questId, "ZONE", prefer, summaryOnly)
                if fact then facts[#facts + 1] = fact end
            end
            for _, questId in ipairs(members.window) do
                local fact = BuildFact(db, questId, "EXTRA", prefer, summaryOnly)
                if fact then
                    fact.repVia = members.windowSource[questId]
                    facts[#facts + 1] = fact
                end
            end
            local char = A.Character()
            char.opts = type(char.opts) == "table" and char.opts or {}
            char.opts.countExtras = false
            return facts, #facts + #members.hidden, { name = FactionDisplayName(F), factionId = F }, char, members
        end

        -- A gate on F itself, from Questie's pair: offered while F < gateMax,
        -- once F >= gateMin
        local function Gates(fact, F)
            local maxRep, minRep = fact.maxRep, fact.minRep
            local gateMax = type(maxRep) == "table" and maxRep[1] == F and tonumber(maxRep[2]) or nil
            local gateMin = type(minRep) == "table" and minRep[1] == F and tonumber(minRep[2]) or nil
            return gateMax, gateMin
        end

        -- A spill window lands a source quest only if the source's own gate
        -- lets it be done: the Scryers' Shadowmoon quests need Friendly with
        -- the Scryers, and an unpledged character's Sha'tar gets nothing from
        -- them until it is. Drops from plan.spillFrom every quest its
        -- source's projection (sourceProjection(source): R.Project's result,
        -- or nil for no source to hold it to) leaves unreached or locks out.
        -- -> how many were dropped (2026-10-05 review)
        local function GateSpill(plan, sourceProjection)
            local spill = plan.spillFrom
            if type(spill) ~= "table" or #spill == 0 then return 0 end
            local shutBy, kept, dropped = {}, {}, 0
            for _, item in ipairs(spill) do
                local source = item.source
                local shut = source ~= nil and shutBy[source]
                if source ~= nil and shut == nil then
                    local projection = sourceProjection(source)
                    shut = false
                    if type(projection) == "table" then
                        shut = {}
                        for _, questId in ipairs(List(projection.unreached)) do shut[questId] = true end
                        for _, questId in ipairs(List(projection.lockedOut)) do shut[questId] = true end
                    end
                    shutBy[source] = shut
                end
                if shut and shut[item.questId] then
                    dropped = dropped + 1
                else
                    kept[#kept + 1] = item
                end
            end
            plan.spillFrom = kept
            return dropped
        end

        -- view.rep: the faction's standing, every number its overview shows,
        -- and how far its quests can take it (R.Project: an ordered, capped
        -- simulation, never a plain sum)
        local function RepBlock(R, D, F, view, members)
            local value, met = StandingOf(F)
            value = value or 0
            local raceBit, classBit = Bits(R)
            local pct, mods = Pct(R, D)
            local words = Labels()
            local store = Store(false)
            local rank = R.Rank(value)
            local byFaction = index.byFaction or EMPTY
            local mine = byFaction[F] or EMPTY
            local rep = {
                factionId = F, name = FactionDisplayName(F), value = value, met = met,
                base = R.Base(D, F, raceBit, classBit), rank = rank, word = R.StandingWord(rank, words),
                progress = R.FormatProgress(value, words), toNext = R.ToNext(value), toExalted = R.ToExalted(value),
                pct = pct, mods = mods, side = (FactionRow(D, F) or EMPTY).side,
                direct = {}, repeatables = {}, dailyQuests = {},
                spill = { windows = members.windowEdges, members = {}, shares = members.shares },
                costs = members.costs, phaseHidden = #members.hidden, phaseHiddenIds = members.hidden,
                phaseKnown = PhaseSet() ~= nil,
                totals = { doneOnce = 0, doneCount = 0, leftCount = 0 }, observed = 0,
            }
            local plan = { factionId = F, once = {}, spillFrom = {}, repeatables = {}, labels = words }
            local dailies = {}
            for _, entry in ipairs(List(view.entries)) do
                local fact = type(entry) == "table" and type(entry.fact) == "table" and entry.fact or EMPTY
                local questId = entry.id
                local source = fact.repVia
                local effect = type(fact.repEffects) == "table" and R.For(fact.repEffects, F) or nil
                entry.repEffect = effect
                if source then
                    local raw = (byFaction[source] or EMPTY)[questId]
                    rep.spill.members[#rep.spill.members + 1] = { questId = questId, source = source, raw = raw,
                        delta = effect and effect.delta or nil, status = entry.status, base = entry.base }
                    if raw and raw > 0 and not GONE[entry.base] and not fact.repeatable and not fact.daily then
                        plan.spillFrom[#plan.spillFrom + 1] = { questId = questId, raw = raw, source = source, name = entry.title }
                    end
                else
                    local seen = OwnSample(R, D, store, questId, F, fact.repRows)
                    local raw = seen or mine[questId]
                    if raw then
                        local gateMax, gateMin = Gates(fact, F)
                        if seen then rep.observed = rep.observed + 1 end
                        rep.direct[#rep.direct + 1] = { questId = questId, raw = raw, observed = seen ~= nil,
                            delta = effect and effect.delta or nil, capped = effect and effect.capped or nil,
                            status = entry.status, base = entry.base, counted = entry.counted,
                            repeatable = fact.repeatable, daily = fact.daily }
                        if fact.daily then
                            rep.dailyQuests[#rep.dailyQuests + 1] = { questId = questId, raw = raw, status = entry.status,
                                base = entry.base, rotating = type(D.rotating) == "table" and D.rotating[questId] or nil }
                            if raw > 0 and DAILY_OPEN[entry.base] then dailies[#dailies + 1] = { questId = questId, raw = raw } end
                        elseif fact.repeatable then
                            local info = R.Repeatable(D, questId, raw, value, pct, { max = gateMax, min = gateMin }, F)
                            info.name, info.status, info.base = entry.title, entry.status, entry.base
                            for _, cost in ipairs(info.costs or EMPTY) do cost.name = ItemName(cost[1]) end
                            if info.costItem then info.costName = ItemName(info.costItem) end
                            rep.repeatables[#rep.repeatables + 1] = info
                            if raw > 0 and not GONE[entry.base] then
                                plan.repeatables[#plan.repeatables + 1] = { questId = questId, raw = raw,
                                    gateMax = gateMax, gateMin = gateMin }
                            end
                        elseif raw > 0 then
                            if entry.base == "DONE" then
                                rep.totals.doneOnce = rep.totals.doneOnce + R.RawGain(D, F, raw, pct)
                                rep.totals.doneCount = rep.totals.doneCount + 1
                            elseif entry.counted then
                                rep.totals.leftCount = rep.totals.leftCount + 1
                                plan.once[#plan.once + 1] = { questId = questId, raw = raw, gateMax = gateMax,
                                    gateMin = gateMin, name = entry.title }
                            end
                        end
                    end
                end
            end
            local today = RotatingToday(R, D)
            rep.rotatingToday = today
            rep.dailies = R.DailyIncome(D, dailies, pct, { factionId = F, today = today, max = DailyCap(), value = value })
            -- each source's own once-only climb over the quests listed here
            -- that pay it (its window quests, and any that pay F too): what
            -- that climb never reaches spills nothing
            GateSpill(plan, function(source)
                local own = byFaction[source] or EMPTY
                local sourcePlan = { factionId = source, once = {}, spillFrom = {}, repeatables = {}, labels = words }
                for _, entry in ipairs(List(view.entries)) do
                    local fact = type(entry) == "table" and type(entry.fact) == "table" and entry.fact or EMPTY
                    if own[entry.id] and not GONE[entry.base] and not fact.repeatable and not fact.daily then
                        local raw = OwnSample(R, D, store, entry.id, source, fact.repRows) or own[entry.id]
                        if raw > 0 then
                            local gateMax, gateMin = Gates(fact, source)
                            sourcePlan.once[#sourcePlan.once + 1] = { questId = entry.id, raw = raw,
                                gateMax = gateMax, gateMin = gateMin, name = entry.title }
                        end
                    end
                end
                return R.Project(D, sourcePlan, StandingOf(source) or 0, pct)
            end)
            rep.projection = R.Project(D, plan, value, pct)
            rep.totals.leftOnce = rep.projection.left
            return rep
        end

        local function TouchFaction(factionId)
            local order = repCache.order
            for i = #order, 1, -1 do
                if order[i] == factionId then table.remove(order, i) end
            end
            order[#order + 1] = factionId
            while #order > FACTION_VIEW_CACHE_SIZE do
                repCache.views[table.remove(order, 1)] = nil
            end
        end

        -- { counted, done, pct, generation, factionId, value, rank, word,
        --   reach, reachRank, left, phaseHidden, quests }
        local function RecordFactionSummary(F, view)
            local summary = view and SummaryOf(view) or { counted = 0, done = 0 }
            summary.generation, summary.factionId = A.generation, F
            local rep = view and view.rep
            if rep then
                summary.value, summary.rank, summary.word = rep.value, rep.rank, rep.word
                summary.reach, summary.reachRank, summary.left = rep.projection.reach, rep.projection.rank, rep.projection.left
                summary.phaseHidden, summary.quests = rep.phaseHidden, #rep.direct
            end
            repCache.summaries[F] = summary
            return summary
        end

        local function BuildFactionView(F, summaryOnly)
            local R, D = Rules()
            local view, err, members = BuildViewOver(F, FactionFacts, summaryOnly, "NO_FACTION")
            if not view then return nil, err end
            view.factionId = F
            view.rep = RepBlock(R, D, F, view, members)
            return view
        end

        -- nil when a faction view can be built now, else why not. The other
        -- side's faction has nothing to show (its quests are the other side's,
        -- and the menu never offers it).
        local function FactionBlocked(factionId)
            local state = A.State()
            if state ~= "READY" then return state end
            local R, D = Rules()
            if not R then return "NO_RULES" end
            local row = FactionRow(D, factionId)
            if not row then return "NO_FACTION" end
            local side = Side(R, D)
            if side and row.side and row.side ~= side then return "OTHER_SIDE" end
            if StartIndex() ~= "READY" then return "INDEXING" end
            return nil
        end

        -- The engine's view of every quest that pays faction F -- the Zones
        -- tab's machinery over another set of ids -- with view.factionId,
        -- view.rep (RepBlock) and, on each entry, entry.repEffect (the
        -- engine's effect on F: the row's badge; a window quest's is its
        -- spill). nil, err: the Questie state, "NO_RULES", "NO_FACTION",
        -- "OTHER_SIDE", "INDEXING" (the index is being read; it steps the
        -- generation when done), "NO_QUESTS", "ENGINE", "ENGINE_ERROR",
        -- "ADAPTER_ERROR".
        function A.FactionView(factionId)
            factionId = tonumber(factionId)
            local slot = factionId and repCache.views[factionId]
            if slot and slot.generation == A.generation then
                TouchFaction(factionId)
                return slot.view
            end
            local why = FactionBlocked(factionId)
            if why then return nil, why end
            local view, err = BuildFactionView(factionId, false)
            if not view then
                if err == "NO_QUESTS" then RecordFactionSummary(factionId, nil) end
                return nil, err
            end
            repCache.views[factionId] = { view = view, generation = A.generation }
            TouchFaction(factionId)
            RecordFactionSummary(factionId, view)
            return view
        end

        -- The last summary of a faction, this generation's (or any, with
        -- allowStale); A.RequestSummaries(ids, onEach, "FACTION") fills them
        function A.FactionSummary(factionId, allowStale)
            local summary = repCache.summaries[tonumber(factionId) or false]
            if summary and (allowStale or summary.generation == A.generation) then return summary end
            return nil
        end

        repCache.ComputeSummary = function(factionId)
            local slot = repCache.views[factionId]
            if slot and slot.generation == A.generation then return RecordFactionSummary(factionId, slot.view) end
            if FactionBlocked(factionId) then return nil end
            local view, err = BuildFactionView(factionId, true)
            if view or err == "NO_QUESTS" then return RecordFactionSummary(factionId, view) end
            return nil
        end

        -- A faction's standing now, without a view: { factionId, name, value,
        -- met, base, rank, word, progress, toNext, toExalted, side }
        function A.FactionStanding(factionId)
            local R, D = Rules()
            factionId = tonumber(factionId)
            local row = R and FactionRow(D, factionId)
            if not row then return nil end
            local value, met = StandingOf(factionId)
            local words = Labels()
            local raceBit, classBit = Bits(R)
            local rank = value and R.Rank(value) or nil
            return {
                factionId = factionId, name = FactionDisplayName(factionId), value = value, met = met,
                base = R.Base(D, factionId, raceBit, classBit), rank = rank, word = R.StandingWord(rank, words),
                progress = value and R.FormatProgress(value, words) or nil,
                toNext = value and R.ToNext(value) or nil, toExalted = value and R.ToExalted(value) or nil,
                side = row.side,
            }
        end

        local function GroupTitle(group)
            if group.header then
                local name = FactionInfo(group.header)
                if Named(name) then return name end
            end
            return Named(group.title) and group.title or tostring(group.key)
        end

        local function MenuNote(word, quests, hidden)
            local parts = { word }
            if quests then parts[#parts + 1] = quests == 1 and "1 quest" or (quests .. " quests") end
            if hidden and hidden > 0 then parts[#parts + 1] = hidden .. " not in this phase yet" end
            return table.concat(parts, SEP)
        end

        -- The picker: the generated groups in order -- Outland, Shattrath,
        -- the other TBC factions, then the classic groups unless
        -- RepIncludeClassic is off -- with the other side's factions left
        -- out. A TBC faction is listed met or not; a classic one only once it
        -- has a quest for this character (or while the index is still read).
        -- { { key, text, tbc, items = { { factionId, name, value, met, rank,
        -- word, quests, phaseHidden, note } } } }; quests is nil while the
        -- index is read.
        function A.FactionMenu()
            local menu = {}
            if A.State() ~= "READY" then return menu end
            local R, D = Rules()
            if not R then return menu end
            local ready = StartIndex() == "READY"
            local side = Side(R, D)
            local settings = type(CommanderQuestLogDB) == "table" and CommanderQuestLogDB or EMPTY
            local classic = settings.RepIncludeClassic ~= false
            local words = Labels()
            for _, group in ipairs(List(D.groups)) do
                if type(group) == "table" and (group.tbc or classic) and not (side and group.side and group.side ~= side) then
                    local items = {}
                    for _, factionId in ipairs(List(group.ids)) do
                        local row = FactionRow(D, factionId)
                        if row and not (side and row.side and row.side ~= side) then
                            local quests, hidden
                            if ready then quests, hidden = CountFor(factionId) end
                            if group.tbc or not ready or quests > 0 or hidden > 0 then
                                local value, met = StandingOf(factionId)
                                local rank = value and R.Rank(value) or nil
                                local word = R.StandingWord(rank, words)
                                items[#items + 1] = {
                                    factionId = factionId, name = FactionDisplayName(factionId), value = value,
                                    met = met, rank = rank, word = word, quests = quests, phaseHidden = hidden,
                                    note = MenuNote(word, quests, hidden),
                                }
                            end
                        end
                    end
                    if #items > 0 then
                        menu[#menu + 1] = { key = group.key, text = GroupTitle(group), tbc = group.tbc and true or false,
                            items = items }
                    end
                end
            end
            return menu
        end

        -- The zone's once-only quests its reputation still counts on: what
        -- its 100% counts, plus two that only bookkeeping keeps out of it --
        -- a dungeon quest that starts here (the EXTRA layer, whatever
        -- CountExtras says: its reputation is as real, and the Reputations
        -- tab counts it) and another member of an undecided exclusive choice
        -- (the choice is per FACTION: the Scryers' pledge is the Scryers' to
        -- make while the zone counts the Aldor's). Never a quest that is
        -- missed, the rival's, ignored, optional or seasonal. Done ones are
        -- members too: "done" and "left" read the same set.
        -- -> counts, "EXTRA" | nil
        local function RepMember(entry, fact)
            if fact.repeatable or fact.daily then return false end
            if entry.base ~= "DONE" and GONE[entry.base] then return false end
            if entry.counted then return true end
            if entry.status == "EXTRA" then return true, "EXTRA" end
            return entry.slotSize ~= nil and entry.choiceOf ~= nil and entry.follows == nil
        end

        -- The key an undecided choice's members share: the lowest id among
        -- the entry and the members its own list names (10551 and 10552 both
        -- answer 10551); nil outside a slot
        local function SlotKey(entry, fact, inSlot)
            if entry.slotSize == nil then return nil end
            local key = entry.id
            for _, peer in ipairs(List(fact.exclusiveTo)) do
                if inSlot[peer] and peer < key then key = peer end
            end
            return key
        end

        -- Per faction, what one zone's quests are worth to this character,
        -- for the Zones overview: { { factionId, name, value, met, rank, word,
        -- remainingOnce (the once-only gain still to come, in the best order),
        -- doneOnce (an estimate: standing cannot be split by source),
        -- doneCount, leftCount (an exclusive choice is one), extraLeft /
        -- extraCount (how much of that is dungeon quests starting here that
        -- the zone's 100% leaves out: 0 with Count Extras on),
        -- repeatables = { {questId, perTurnIn, daily, rotating, conditional,
        -- open} }, repeatablesPerTurnIn (the best OPEN one, else the best),
        -- steadyCount / steadyPerTurnIn / rotatingCount (the same without the
        -- Wanted pools and Halaa), viaSpill (what the spill window LANDS:
        -- the chosen source, held to the window's top, 0 once it is shut,
        -- only from the source quests its own projection here reaches),
        -- unreachedCount (quests waiting on a standing the once-only quests
        -- do not reach), repeatReach (how far the zone's non-daily
        -- repeatables carry it after them), projection, reach, reachRank,
        -- reachesNext, reachesExalted }, ... }, the biggest remainder first.
        -- Only factions a quest here pays directly, of this character's side.
        -- Every per-turn-in figure is what a turn-in pays from the standing
        -- NOW (0 at the cap), the same number the quest's row shows.
        -- Membership and the done/left split: RepMember (2026-10-04 review).
        function A.ZoneRepTotals(areaId)
            local out = {}
            local R, D = Rules()
            if not R then return out end
            local view = A.ZoneView(areaId)
            if type(view) ~= "table" then return out end
            local pct = Pct(R, D)
            local side = Side(R, D)
            local store = Store(false)
            local words = Labels()
            local rotating = type(D.rotating) == "table" and D.rotating or EMPTY
            local conditional = type(D.conditional) == "table" and D.conditional or EMPTY
            local byFaction, directOf, inSlot = {}, {}, {}
            for _, entry in ipairs(List(view.entries)) do
                if type(entry) == "table" and entry.slotSize ~= nil and entry.id then inSlot[entry.id] = true end
            end
            local function Totals(F)
                local t = byFaction[F]
                if not t then
                    t = { factionId = F, doneOnce = 0, doneCount = 0, leftCount = 0, repeatables = {},
                          repeatablesPerTurnIn = 0, viaSpill = 0, extraCount = 0, extraLeft = 0,
                          steadyCount = 0, steadyPerTurnIn = 0, rotatingCount = 0, unreachedCount = 0,
                          plan = { factionId = F, once = {}, spillFrom = {}, repeatables = {}, labels = words },
                          slots = {}, extras = {}, bestOpen = nil, bestAny = 0 }
                    byFaction[F] = t
                    out[#out + 1] = t
                end
                return t
            end
            for _, entry in ipairs(List(view.entries)) do
                local fact = type(entry) == "table" and type(entry.fact) == "table" and entry.fact or EMPTY
                local direct = DirectRows(D, entry.id, fact.repRows)
                directOf[entry] = direct
                local member, layer = RepMember(entry, fact)
                local slot = member and SlotKey(entry, fact, inSlot) or nil
                for F, listed in pairs(direct) do
                    local row = FactionRow(D, F)
                    local raw = OwnSample(R, D, store, entry.id, F, fact.repRows) or listed
                    if raw > 0 and not (side and row and row.side and row.side ~= side) then
                        local gateMax, gateMin = Gates(fact, F)
                        if fact.repeatable or fact.daily then
                            if not GONE[entry.base] then
                                local t = Totals(F)
                                local per = R.QuestGain(D, entry.id, F, raw, StandingOf(F) or 0, pct)
                                local item = { questId = entry.id, perTurnIn = per, daily = fact.daily and true or false,
                                    rotating = rotating[entry.id], conditional = conditional[entry.id],
                                    open = entry.base ~= "LOCKED" }
                                t.repeatables[#t.repeatables + 1] = item
                                if per > t.bestAny then t.bestAny = per end
                                if item.open and per > (t.bestOpen or -1) then t.bestOpen = per end
                                if item.rotating or item.conditional then
                                    t.rotatingCount = t.rotatingCount + (item.rotating and 1 or 0)
                                else
                                    t.steadyCount = t.steadyCount + 1
                                    if item.open and per > t.steadyPerTurnIn then t.steadyPerTurnIn = per end
                                    if not fact.daily then
                                        t.plan.repeatables[#t.plan.repeatables + 1] = { questId = entry.id, raw = raw,
                                            gateMax = gateMax, gateMin = gateMin }
                                    end
                                end
                            end
                        elseif entry.base == "DONE" then
                            if member then
                                local t = Totals(F)
                                t.doneOnce = t.doneOnce + R.RawGain(D, F, raw, pct)
                                t.doneCount = t.doneCount + 1
                            end
                        elseif member then
                            local t = Totals(F)
                            if slot == nil or not t.slots[slot] then
                                t.leftCount = t.leftCount + 1
                                if slot ~= nil then t.slots[slot] = true end
                            end
                            if layer == "EXTRA" then
                                t.extraCount = t.extraCount + 1
                                t.extras[#t.extras + 1] = entry.id
                            end
                            t.plan.once[#t.plan.once + 1] = { questId = entry.id, raw = raw, gateMax = gateMax,
                                gateMin = gateMin, name = entry.title, slot = slot }
                        end
                    end
                end
            end
            -- a spill window into a faction already listed: the Sha'tar from
            -- the zone's Aldor quests, until Honored; both sides of a pledge
            -- are one choice (a shared slot), the projection picks the source
            for _, entry in ipairs(List(view.entries)) do
                local fact = type(entry) == "table" and type(entry.fact) == "table" and entry.fact or EMPTY
                if entry.base ~= "DONE" and RepMember(entry, fact) then
                    local slot = SlotKey(entry, fact, inSlot)
                    for source, raw in pairs(directOf[entry] or EMPTY) do
                        local row = FactionRow(D, source)
                        for _, edge in ipairs(row and type(row.spill) == "table" and row.spill or EMPTY) do
                            local target, rate = tonumber(edge[1]), tonumber(edge[2])
                            local maxRankIn = tonumber(edge[3]) or MAX_RANK
                            local t = target and byFaction[target]
                            if t and rate and rate > 0 and raw > 0 and maxRankIn < MAX_RANK then
                                t.plan.spillFrom[#t.plan.spillFrom + 1] = { questId = entry.id, raw = raw,
                                    source = source, name = entry.title, slot = slot }
                            end
                        end
                    end
                end
            end
            -- a source is projected before the factions it spills into: what
            -- its own climb here never reaches spills nothing (an unpledged
            -- character's Scryers quests in Shadowmoon need Friendly with the
            -- Scryers). A cycle, which the data has none of, is held to nothing.
            local projections, visiting = {}, {}
            local function ProjectionOf(F)
                local t = byFaction[F]
                if not t then return nil end
                if projections[F] then return projections[F] end
                if visiting[F] then return nil end
                visiting[F] = true
                GateSpill(t.plan, ProjectionOf)
                local projection = R.Project(D, t.plan, StandingOf(F) or 0, pct)
                visiting[F] = nil
                projections[F] = projection
                return projection
            end
            for _, t in ipairs(out) do ProjectionOf(t.factionId) end
            for _, t in ipairs(out) do
                local value, met = StandingOf(t.factionId)
                value = value or 0
                local projection = projections[t.factionId]
                t.plan, t.slots = nil, nil
                t.name, t.value, t.met = FactionDisplayName(t.factionId), value, met
                t.rank = R.Rank(value)
                t.word = R.StandingWord(t.rank, words)
                t.projection, t.remainingOnce = projection, projection.left
                t.reach, t.reachRank = projection.reach, projection.rank
                t.reachesNext = projection.rank > t.rank
                t.reachesExalted = projection.reach >= R.EXALTED
                -- what the window lands, not what every source would offer
                local window = projection.spillWindow
                t.viaSpill = window and window.landed or 0
                t.unreachedCount = #(projection.unreached or EMPTY)
                t.repeatReach = projection.repeatReach
                local gains = projection.gains or EMPTY
                for _, questId in ipairs(t.extras) do t.extraLeft = t.extraLeft + (gains[questId] or 0) end
                t.extras = nil
                t.repeatablesPerTurnIn = t.bestOpen or t.bestAny
                t.bestOpen, t.bestAny = nil, nil
            end
            table.sort(out, function(a, b)
                if a.remainingOnce ~= b.remainingOnce then return a.remainingOnce > b.remainingOnce end
                if a.doneOnce ~= b.doneOnce then return a.doneOnce > b.doneOnce end
                return a.factionId < b.factionId
            end)
            return out
        end

        -- The character the engine is handed, plus what reputation needs:
        -- repPct (the multiplier now), standing(factionId) (the bar value, or
        -- the base for a faction not met) and repSide
        local baseCharacter = A.Character
        function A.Character()
            local char = baseCharacter()
            local R, D = Rules()
            if R then
                local ok, pct = pcall(Pct, R, D)
                char.repPct = ok and pct or nil
                char.standing = StandingValue
                local sided, side = pcall(Side, R, D)
                char.repSide = sided and side or nil
            end
            return char
        end

        -- ---- calibration ----------------------------------------------------

        local observer = { snap = nil, moves = {}, turnIns = {}, readPending = false, readAt = nil,
                           samples = 0, dropped = 0, why = {} }

        local function Now()
            if not GetTime then return nil end
            local ok, now = pcall(GetTime)
            return (ok and type(now) == "number") and now or nil
        end

        local function SetAside(why)
            observer.dropped = observer.dropped + 1
            observer.why[why] = (observer.why[why] or 0) + 1
        end

        local function Prune(now)
            if not now then return end
            local keep = {}
            for _, move in ipairs(observer.moves) do
                if move.t >= now - MOVE_KEEP_SECONDS then keep[#keep + 1] = move end
            end
            observer.moves = keep
            keep = {}
            for _, turnIn in ipairs(observer.turnIns) do
                if not turnIn.done or turnIn.t >= now - MOVE_KEEP_SECONDS then keep[#keep + 1] = turnIn end
            end
            observer.turnIns = keep
        end

        -- Every faction's standing now, the base for one not met: a first
        -- gain with a faction is a move from its base, as the server counts it
        local function ReadSnapshot()
            observer.readPending = false
            local R, D = Rules()
            if not R then return end
            local at = observer.readAt or Now()
            observer.readAt = nil
            local fresh = {}
            for factionId in pairs(D.factions) do
                fresh[factionId] = (CurrentStanding(R, D, factionId))
            end
            local old = observer.snap
            if old and at then
                for factionId, value in pairs(fresh) do
                    local before = old[factionId]
                    if type(value) == "number" and type(before) == "number" and value ~= before then
                        observer.moves[#observer.moves + 1] = { t = at, factionId = factionId, delta = value - before,
                            after = value, source = "SNAP" }
                    end
                end
            end
            observer.snap = fresh
            Prune(at)
        end

        -- One read a frame, stamped with the time of the event that asked
        local function QueueSnapshot()
            if observer.readPending then return end
            observer.readPending, observer.readAt = true, Now()
            if C_Timer and C_Timer.After then
                C_Timer.After(0, ReadSnapshot)
            else
                ReadSnapshot()
            end
        end

        -- A GlobalStrings format as an anchored pattern, and the kinds of its
        -- captures in the order they appear (a locale may put the number
        -- first: "%2$d ... %1$s")
        local function Escape(text)
            return (text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
        end
        local function Pattern(format)
            if not Named(format) then return nil end
            local pieces, kinds, last = {}, {}, 1
            for start, kind, stop in format:gmatch("()%%[%d%$%.%-]*([sdif%%])()") do
                pieces[#pieces + 1] = Escape(format:sub(last, start - 1))
                if kind == "%" then
                    pieces[#pieces + 1] = "%%"
                elseif kind == "s" then
                    pieces[#pieces + 1] = "(.-)"
                    kinds[#kinds + 1] = "s"
                elseif kind == "f" then
                    pieces[#pieces + 1] = "([%d%.,]+)"
                    kinds[#kinds + 1] = "f"
                else
                    pieces[#pieces + 1] = "(%d+)"
                    kinds[#kinds + 1] = "d"
                end
                last = stop
            end
            pieces[#pieces + 1] = Escape(format:sub(last))
            return "^" .. table.concat(pieces) .. "$", kinds
        end

        -- The bonus form first: the plain one would not match its tail anyway
        local CHAT_FORMATS = {
            { "FACTION_STANDING_INCREASED_ACH_BONUS", 1 }, { "FACTION_STANDING_INCREASED", 1 },
            { "FACTION_STANDING_DECREASED", -1 },
        }
        local patterns
        local function Patterns()
            if patterns then return patterns end
            local built = {}
            for _, spec in ipairs(CHAT_FORMATS) do
                local pattern, kinds = Pattern(_G[spec[1]])
                if pattern then built[#built + 1] = { pattern = pattern, kinds = kinds, sign = spec[2] } end
            end
            if #built > 0 then patterns = built end
            return built
        end

        -- Every name a faction goes by here -- English, this locale's from
        -- the data, the client's -- to its id. Rebuilt on a miss, once per
        -- generation (a faction met for the first time brings its name).
        local byName, byNameGeneration = nil, nil
        local function FactionByName(name)
            local R, D = Rules()
            if not (R and Named(name)) then return nil end
            if not byName or (byName[name] == nil and byNameGeneration ~= A.generation) then
                local map = {}
                local names = type(D.names) == "table" and D.names[LocaleCode() or ""] or nil
                for factionId, row in pairs(D.factions) do
                    if type(row) == "table" and Named(row.name) then map[row.name] = factionId end
                    local localised = type(names) == "table" and names[factionId] or nil
                    if Named(localised) then map[localised] = factionId end
                    local client = FactionInfo(factionId)
                    if Named(client) then map[client] = factionId end
                end
                byName, byNameGeneration = map, A.generation
            end
            return byName[name]
        end

        -- "Reputation with The Sha'tar increased by 137." -> 935, 137
        local function ParseChat(text)
            if type(text) ~= "string" then return nil end
            for _, p in ipairs(Patterns()) do
                local captures = { text:match(p.pattern) }
                if captures[1] ~= nil then
                    local name, amount
                    for i, kind in ipairs(p.kinds) do
                        if kind == "s" and not name then
                            name = captures[i]
                        elseif kind == "d" and not amount then
                            amount = tonumber(captures[i])
                        end
                    end
                    local factionId = FactionByName(name)
                    if factionId and amount then return factionId, p.sign * amount end
                    return nil
                end
            end
            return nil
        end

        local function OnChat(text)
            local factionId, delta = ParseChat(text)
            local at = Now()
            if factionId and at then
                observer.moves[#observer.moves + 1] = { t = at, factionId = factionId, delta = delta, source = "CHAT" }
            end
        end

        -- The factions a turn-in may move: its rows (a stored spillover row
        -- names a spill target too) and every spill target of its DIRECT rows
        local function PredictedSet(D, questId, rows)
            local set = {}
            for _, row in ipairs(List(rows)) do
                local factionId = type(row) == "table" and tonumber(row[1]) or nil
                if factionId and D.factions[factionId] then set[factionId] = true end
            end
            for factionId in pairs(DirectRows(D, questId, rows)) do
                set[factionId] = true
                local row = FactionRow(D, factionId)
                for _, edge in ipairs(row and type(row.spill) == "table" and row.spill or EMPTY) do
                    local target = type(edge) == "table" and tonumber(edge[1]) or nil
                    if target then set[target] = true end
                end
            end
            return set
        end

        -- After the window: each faction the quest may move that moved once,
        -- by the snapshot (the chat line when the snapshot saw nothing), is a
        -- sample; a DIRECT row that did not move at all while the rest of the
        -- quest did is a sample of 0 (the server paid it nothing). Kinds and
        -- clamps come from the data's own prediction from where the bars
        -- stood; R.Observe normalises by the multiplier of the moment and
        -- throws out what hit a ceiling, the bottom, a reward clamp or a
        -- spill window's top.
        local function CloseWindow(turnIn)
            turnIn.done = true
            local R, D = Rules()
            if not R then return end
            if A.State() ~= "READY" or not Exists(turnIn.questId) then
                SetAside("unknown quest")
                return
            end
            local rows = Rows(turnIn.questId)
            local set = PredictedSet(D, turnIn.questId, rows)
            turnIn.set = set
            if not next(set) then return end
            local shared = {}
            for _, other in ipairs(observer.turnIns) do
                if other ~= turnIn and math.abs(other.t - turnIn.t) < OBSERVE_BEFORE + OBSERVE_AFTER then
                    other.set = other.set or PredictedSet(D, other.questId, Rows(other.questId))
                    for factionId in pairs(set) do
                        if other.set[factionId] then shared[factionId] = true end
                    end
                end
            end
            local lo, hi = turnIn.t - OBSERVE_BEFORE, turnIn.t + OBSERVE_AFTER
            local snaps, chats = {}, {}
            for _, move in ipairs(observer.moves) do
                if move.t >= lo and move.t <= hi and set[move.factionId] then
                    local into = move.source == "SNAP" and snaps or chats
                    local list = into[move.factionId]
                    if not list then
                        list = {}
                        into[move.factionId] = list
                    end
                    list[#list + 1] = move
                end
            end
            -- seen[f]: its one move, or false when it moved more than once;
            -- clean: some faction moved exactly once, so the turn-in's own
            -- moves were caught (what a zero sample needs)
            local seen, moved, clean = {}, false, false
            for factionId in pairs(set) do
                local list = snaps[factionId] or chats[factionId]
                if list and #list == 1 then
                    local move = list[1]
                    seen[factionId] = { delta = move.delta, after = move.after or (CurrentStanding(R, D, factionId)) }
                    clean = true
                elseif list then
                    seen[factionId] = false
                end
                if list then moved = true end
            end
            if not moved then
                SetAside("no move seen")
                return
            end
            local before = {}
            for factionId in pairs(set) do
                local move = seen[factionId]
                if move then
                    before[factionId] = move.after - move.delta
                else
                    before[factionId] = (CurrentStanding(R, D, factionId))
                end
            end
            local effects = R.Effects(D, turnIn.questId, rows, before, turnIn.pct, { side = Side(R, D), labels = Labels() })
            local store = Store(true)
            if not store then
                SetAside("no saved variables")
                return
            end
            -- A spill is a share of its source's gain: when a clamp cut that
            -- gain, the share says nothing about the quest either
            local sourceCut = false
            for _, entry in ipairs(effects) do
                if entry.kind == "DIRECT" and entry.capped then sourceCut = true end
            end
            -- A move several of the quest's own rows made between them (the
            -- Darkspear Trolls' 250 plus Orgrimmar's spill) is a sum no one
            -- listed value explains: stored, it would be paid again on every
            -- share. Set aside, and a sample an older build kept for it is
            -- dropped (the engine never reads one either).
            local mixed = type(R.MixedSources) == "function"
                and R.MixedSources(D, turnIn.questId, rows, Side(R, D)) or EMPTY
            local kept = store[turnIn.questId]
            local stored = 0
            for _, entry in ipairs(effects) do
                local factionId = entry.factionId
                local move = seen[factionId]
                if mixed[factionId] then
                    SetAside("mixed")
                    if type(kept) == "table" then kept[factionId] = nil end
                elseif shared[factionId] or move == false then
                    SetAside("ambiguous")
                elseif entry.kind ~= "DIRECT" and sourceCut and move then
                    SetAside("source capped")
                elseif move or (clean and entry.kind == "DIRECT" and not entry.capped and Met(factionId)) then
                    local row = FactionRow(D, factionId)
                    local rate = row and type(row.rate) == "table" and tonumber(row.rate.quest) or nil
                    local ok, why = R.Observe(store, turnIn.questId, factionId, move and move.delta or 0, turnIn.pct, {
                        kind = entry.kind, rate = rate, after = move and move.after or before[factionId],
                        cap = R.RewardCap(D, turnIn.questId, factionId), capped = entry.capped,
                        spillCap = (entry.kind ~= "DIRECT" and entry.capped) or nil,
                    })
                    if ok then stored = stored + 1 else SetAside(why or "dropped") end
                end
            end
            if type(kept) == "table" and next(kept) == nil and store[turnIn.questId] == kept then
                store[turnIn.questId] = nil
            end
            if stored > 0 then
                observer.samples = observer.samples + stored
                observer.lastQuest = turnIn.questId
                A.Bump("calibration")
            end
        end

        local function OnTurnIn(questId)
            questId = tonumber(questId)
            local R, D = Rules()
            -- a rotating daily turned in now is today's, whatever the reset did
            if questId and D and type(D.rotating) == "table" and D.rotating[questId] then
                session.rotatingDone[questId] = ServerNow()
            end
            local at = Now()
            if not (questId and R and at and C_Timer and C_Timer.After) then return end
            local turnIn = { questId = questId, t = at, pct = R.Multiplier(Mods(D)) }
            observer.turnIns[#observer.turnIns + 1] = turnIn
            QueueSnapshot()
            C_Timer.After(OBSERVE_AFTER + 0.1, function()
                local ok, err = pcall(CloseWindow, turnIn)
                if not ok then NoteError("reputation calibration", err) end
            end)
        end

        -- A change of multiplier (the Wickerman taken or lost) is a Bump
        local auraPending, lastPct = false, nil
        local function CheckAura()
            auraPending = false
            local R, D = Rules()
            if not R then return end
            local pct = R.Multiplier(Mods(D))
            if lastPct and pct ~= lastPct then A.Bump("reputation multiplier") end
            lastPct = pct
        end

        local function OnEvent(event, arg1)
            if event == "PLAYER_LOGIN" then
                labels = nil
                session.start = ServerNow()
                if Rules() then
                    QueueSnapshot()      -- the baseline every later move is measured from
                    CheckAura()
                end
            elseif event == "UPDATE_FACTION" then
                if Rules() then QueueSnapshot() end
            elseif event == "QUEST_TURNED_IN" then
                OnTurnIn(arg1)
            elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
                if Rules() then OnChat(arg1) end
            elseif event == "UNIT_AURA" then
                if arg1 == "player" and not auraPending and C_Timer and C_Timer.After then
                    auraPending = true
                    C_Timer.After(AURA_SETTLE_SECONDS, CheckAura)
                end
            end
        end

        if CreateFrame then
            local ok, frame = pcall(CreateFrame, "Frame")
            if ok and frame then
                for _, event in ipairs({ "PLAYER_LOGIN", "QUEST_TURNED_IN", "UPDATE_FACTION",
                                         "CHAT_MSG_COMBAT_FACTION_CHANGE" }) do
                    pcall(frame.RegisterEvent, frame, event)
                end
                -- the player's own auras only, where the client can say so
                if type(frame.RegisterUnitEvent) == "function" then
                    pcall(frame.RegisterUnitEvent, frame, "UNIT_AURA", "player")
                else
                    pcall(frame.RegisterEvent, frame, "UNIT_AURA")
                end
                frame:SetScript("OnEvent", function(_, event, arg1)
                    local handled, err = pcall(OnEvent, event, arg1)
                    if not handled then NoteError("reputation " .. tostring(event), err) end
                end)
            end
        end

        -- ---- waypoint notes -------------------------------------------------

        -- A quest's waypoint note is what the quest was worth when it was
        -- set. When the numbers move -- a standing, the Wickerman, a
        -- calibration sample, the cap -- every note this adapter wrote that
        -- Orders still holds unchanged is written again through Orders' own
        -- Update: never re-added (a waypoint the player removed stays
        -- removed) and never over a note someone else changed. Once a
        -- generation, and only where the words differ.
        local function RefreshWaypointNotes()
            local notes = repCache.waypointNotes
            if next(notes) == nil then return end
            local api = Orders()
            if not (api and type(api.List) == "function" and type(api.Update) == "function") then return end
            if type(CommanderQuestLogDB) == "table" and CommanderQuestLogDB.ShowRepEverywhere == false then return end
            local ok, list = pcall(api.List, { source = "QuestLog" })
            if not (ok and type(list) == "table") then return end
            local live = {}
            for _, wp in ipairs(list) do
                local key = type(wp) == "table" and wp.key
                local questId = type(key) == "string" and tonumber(key:match("^quest:(%d+)$")) or nil
                local written = questId and notes[questId]
                if written then
                    live[questId] = true
                    local fresh = wp.note == written and A.RepLine(questId) or nil
                    if Named(fresh) and fresh ~= written then
                        local updated, copy = pcall(api.Update, wp.uid, { note = fresh })
                        if updated and copy then notes[questId] = fresh end
                    end
                end
            end
            for questId in pairs(notes) do
                if not live[questId] then notes[questId] = nil end
            end
        end

        A.AddListener(function()
            local ok, err = pcall(RefreshWaypointNotes)
            if not ok then NoteError("waypoint notes", err) end
        end)

        -- ---- /cql status ----------------------------------------------------

        local function Plural(n, one, many)
            if n == 1 then return one end
            return many
        end

        local function QuestTitle(questId)
            if not questId then return "not known yet" end
            return QuestName(questId) or ("quest " .. questId)
        end

        local function AppendStatus(lines)
            local R, D = Rules()
            if not R then
                lines[#lines + 1] = "Reputation rules: "
                    .. (type(Q.Standing) == "table" and "the reputation data did not load" or "the rules engine did not load")
                return
            end
            lines[#lines + 1] = "Reputation rules: loaded (data for " .. tostring(D.build or "?") .. ")"
            local state, done, total = A.FactionIndexState()
            if state == "READY" then
                lines[#lines + 1] = string.format("Faction index: complete (%d quests read, %d pay reputation, %d factions)",
                    total, index.paying or 0, index.factions or 0)
            elseif state == "BUILDING" then
                lines[#lines + 1] = string.format("Faction index: building, %d of %d", done, total)
            else
                lines[#lines + 1] = "Faction index: not read yet (it is, the first time a faction is asked about)"
            end
            local mods = Mods(D)
            local named = {}
            if mods.human then named[#named + 1] = "Diplomacy" end
            if mods.wickerman then named[#named + 1] = "Invocation of the Wickerman" end
            lines[#lines + 1] = string.format("Reputation multiplier: %d%%%s", R.Multiplier(mods),
                #named > 0 and (" (" .. table.concat(named, ", ") .. ")") or "")
            local quests, samples = R.ObservedCount(Store(false))
            lines[#lines + 1] = string.format("Reputation seen in game: %d quest%s, %d sample%s%s", quests,
                Plural(quests, "", "s"), samples, Plural(samples, "", "s"),
                observer.dropped > 0 and string.format(" (%d set aside this session)", observer.dropped) or "")
            local summaryCount = 0
            for _ in pairs(repCache.summaries) do summaryCount = summaryCount + 1 end
            lines[#lines + 1] = string.format("Cached: %d faction view%s, %d faction summar%s", #repCache.order,
                Plural(#repCache.order, "", "s"), summaryCount, Plural(summaryCount, "y", "ies"))
            if A.State() == "READY" then
                local today = RotatingToday(R, D)
                lines[#lines + 1] = string.format("Wanted dailies today: normal %s, heroic %s",
                    QuestTitle(today.NORMAL), QuestTitle(today.HEROIC))
            end
        end

        local statusLines = A.StatusLines
        function A.StatusLines()
            local lines = statusLines()
            local ok, err = pcall(AppendStatus, lines)
            if not ok then NoteError("reputation status", err) end
            return lines
        end

        -- ---- harness accessors ----------------------------------------------

        function A._FactionIndex()
            return { state = index.state, quests = index.quests, paying = index.paying, factions = index.factions,
                     ticks = index.ticks, byFaction = index.byFaction }
        end

        function A._RepObserver()
            return observer
        end

        function A._DirectRows(questId)
            local R, D = Rules()
            if not R then return nil end
            return DirectRows(D, questId, Rows(questId))
        end

        function A._ParseRepChat(text)
            return ParseChat(text)
        end

        function A._RepCacheInfo()
            local order = {}
            for i, factionId in ipairs(repCache.order) do order[i] = factionId end
            local summaries = 0
            for _ in pairs(repCache.summaries) do summaries = summaries + 1 end
            return { views = #repCache.order, order = order, summaries = summaries }
        end
    end
    InstallReputation()
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
        -- reputation (1.6.0)
        FactionView = NoView, FactionMenu = EmptyList, FactionSummary = false, FactionStanding = false,
        FactionName = false, FactionIndexState = false, RepEffects = false, RepLine = false,
        ZoneRepTotals = EmptyList, RotatingToday = EmptyList, RepMultiplier = false,
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
