-- A fake Questie + QuestieDB for the Commander Quest Log harnesses (luajit).
--
-- The Zones tab and the world-map drawer read Questie through ONE file,
-- CommanderQuestLogQuestie.lua. Three harnesses drive that file -- the adapter
-- smoke, the window harness and the map harness -- and all three need the same
-- thing underneath it: a Questie that answers the way the real one does,
-- including the ways the real one bites. This file is that Questie. It is
-- self-contained (no WoW mock of its own beyond a handful of optional client
-- stubs) and loads with plain dofile:
--
--   local Fake = dofile(ADDONS .. "/Commander_QuestLog/Harness/fake_questie.lua")
--   local world = Fake.DefaultWorld()     -- a fresh deep copy every call; edit freely
--   world.player.level = 64               -- ...script the scenario...
--   local fake = Fake.Install(world)      -- sets Questie, QuestieLoader (and the modules)
--   Fake.InstallClient(world)             -- optional: C_Map / C_QuestLog / faction stubs,
--                                         -- each installed only where the harness has none
--   fake.SetReady()                       -- when the world said ready = false
--   ...
--   assert(#fake.forbidden == 0)          -- nothing called what the adapter must never call
--
-- THE GOTCHAS IT REPRODUCES (each one a real Questie behaviour, cited in the
-- research under scratchpad/understand/):
--
--   * QuestieLoader:ImportModule silently CREATES an empty { private = {} }
--     module for a name it does not know. The adapter must look in
--     QuestieLoader._modules instead; fake.ModulesCreated() lists any module an
--     import conjured up.
--   * ZoneDB:GetAreaIdByUiMapId THROWS for a uiMap it cannot match (continents,
--     unknown maps) -- the real one ends in error(). Outland's 1945 answers 0.
--   * QuestieDB.IsDoableVerbose returns "", false, AVAILABLE unless returnText
--     is truthy: every early return in the real function is written as
--     `if returnText and returnBrief ... elseif returnText ... end`, with no
--     else, so a call without returnText falls all the way through.
--   * Unset numeric quest fields read 0, never nil. Empty table fields read nil,
--     except startedBy / finishedBy / objectives, which always read a table for
--     a known quest. A {0, 0} requiredSkill / requiredMinRep / requiredMaxRep
--     reads nil. Every table field is a FRESH DEEP COPY on every read. An
--     unknown id reads nil for every field and QueryQuest answers nil.
--   * QuestieJourney.zoneMap carries junk: Questie's spawn-branch bug stores
--     NPC ids (array indices, in fact) as if they were quest ids. The fake puts
--     world.junkId (default 77777, not a quest) into zoneMap for each of
--     world.junkZones (default Hellfire 3483 and Eversong 3430, where it is the
--     only entry -- so Journey's zone list carries Eversong, as the real one
--     would); only a QuestPointers guard keeps it out.
--   * Questie.db.char.complete is REASSIGNED at runtime (fake.ReassignComplete),
--     and so is QuestiePlayer.currentQuestlog (every fake.SetInLog). Code that
--     cached either table goes stale.
--   * Calls that write Questie state, mutate shared tables or are heavy RAISE
--     and are recorded in fake.forbidden (the adapter pcalls everything, so a
--     raise alone would be swallowed -- the record is what the harness reads):
--     QuestieDB.IsDoable, QuestieDB.IsComplete, QuestieQuest:HideQuest /
--     :UnhideQuest, ZoneDB.GetZonesWithQuests,
--     AvailableQuests.IsLevelRequirementsFulfilled.
--   * Call style is enforced: a dot function called with a module as its first
--     argument, or a colon function called without its module as self, raises
--     and is recorded in fake.styleErrors. (QuestieDB.Query*, IsDoableVerbose,
--     QuestiePlayer.GetPlayerLevel, QuestieEvent.IsEventQuest, ZoneDB.IsDungeonZone
--     are dot; ZoneDB:GetAreaIdByUiMapId / :GetUiMapIdByAreaId / :GetParentZoneId /
--     :GetDungeonLocation / :GetLocalizedDungeonName, QuestiePlayer:GetCurrentZoneId,
--     QuestieProfessions:GetPlayerProfessions / :GetSortIdByProfessionId /
--     :GetProfessionName are colon.)
--   * Questie.API.RegisterOnReady runs the callback at once when already ready,
--     otherwise queues it until fake.SetReady() -- which runs the queue
--     synchronously, the way Questie's init coroutine does.
--   * exclusiveTo is ONE-WAY, as in the real IsDoableVerbose: a quest is
--     answered EXCLUSIVE_COMPLETED / EXCLUSIVE_IN_QUEST_LOG only from its OWN
--     list. The default world's trio is deliberately not a clique (9013 names
--     9014, 9014 names nothing), the shape most of the real data has.
--
-- THE WORLD DESCRIPTION (everything optional except quests; Fake.DefaultWorld()
-- is a complete example):
--
--   world = {
--     ready = true,                -- Questie.API.isReady at install time
--     player = {
--       level = 62, class = "PALADIN", classId = 2, raceId = 1,   -- race/class FLAGS = 2^(id-1)
--       faction = "Alliance", uiMapId = 1944, x = 50, y = 60,     -- where C_Map puts the player (0..100)
--       professions = { [186] = { "Mining", 250 } },              -- skillId -> { name, rank }
--     },
--     zones = {                    -- by AREA id (Questie's id space)
--       [3483] = { name = "Hellfire Peninsula", uiMapId = 1944, category = 3 },
--       [3536] = { name = "Thrallmar", parent = 3483 },            -- ZoneDB:GetParentZoneId
--       [3562] = { name = "Hellfire Ramparts", uiMapId = 347, category = 9,
--                  entrances = { { 3483, 47.7, 53.6 } } },          -- ZoneDB:GetDungeonLocation
--       [3714] = { ..., noAreaInfo = true },                       -- C_Map.GetAreaInfo answers nil
--     },
--     uiMaps = {                   -- by UI MAP id (the world map's id space)
--       [1944] = { name = "Hellfire Peninsula", mapType = 3, parent = 1945, areaId = 3483,
--                  rect = { 0.40, 0.60, 0.50, 0.70 } },             -- GetMapRectOnMap(1944, parent)
--       [1945] = { name = "Outland", mapType = 2, parent = 946, areaId = 0, children = { 1944 } },
--     },                           -- a uiMap with no areaId makes GetAreaIdByUiMapId throw
--     continents = { [1] = "Eastern Kingdoms", [3] = "Outland", ... },   -- QuestieJourney.continents
--     factions = { [932] = "The Aldor" },                          -- GetFactionInfoByID names
--     reps = { [932] = 3500 },                                     -- barValue
--     npcs = { [20001] = { name = "...", spawns = { [3483] = { { 87.4, 50.7 } } } } },
--     objects = { [50001] = { name = "...", spawns = { ... } } },
--     items = { [30001] = { name = "..." } },
--     quests = {                   -- Questie's own key names, read through the normalising
--       [9001] = {                 -- reader above; plus the fake-only keys below
--         name = "...", questLevel = 60, requiredLevel = 58, zoneOrSort = 3483,
--         startedBy = { { 20001 } },              -- { npcIds, objectIds, itemIds }
--         finishedBy = { { 20002 } },             -- { npcIds, objectIds }
--         preQuestSingle = { ... }, preQuestGroup = { ... }, nextQuestInChain = 0,
--         exclusiveTo = { ... }, breadcrumbForQuestId = 0, parentQuest = 0,
--         requiredMinRep = { 932, 3000 }, requiredMaxRep = ..., requiredSkill = { 186, 300 },
--         specialFlags = 1, questFlags = 4096, requiredRaces = 690, requiredClasses = 2,
--         objectivesText = { "..." }, reputationReward = { { 946, 250 } },
--         -- fake-only:
--         state = "LEVEL_TOO_LOW",                -- IsDoableVerbose's verdict when not complete/in log
--         hidden = true | "HIDE_ON_MAP",          -- QuestieCorrections.hiddenQuests
--         event = "Midsummer", eventActive = false,   -- QuestieEvent; inactive => hidden = true
--         oneWayRep = true,                       -- questsOnlyAvailableUntilReputationValue
--       },
--     },
--     complete = { [9001] = true },               -- Questie.db.char.complete
--     log = { [9003] = true },                    -- C_QuestLog.IsOnQuest / currentQuestlog
--     logComplete = { [9003] = 1 },               -- GetQuestLogTitle's isComplete (1 ready, -1 failed)
--     logCollapsed = true,                        -- the client's one heading is collapsed: its quests
--                                                 -- leave the index space (GetQuestLogIndexByID answers 0);
--                                                 -- IsQuestComplete(questID) still answers by id
--     available = { [9005] = true },              -- AvailableQuests.__availableQuests (Questie draws it)
--     filler = 0,                                  -- extra pointer-only quests 50001.. (chunking tests)
--     junkId = 77777,                              -- the zoneMap junk entry (false to omit)
--     junkZones = { 3483, 3430 },                  -- where it is planted
--     omitModules = { AvailableQuests = true },    -- modules Questie "does not have"
--   }
--
-- THE HANDLE Fake.Install returns:
--
--   fake.world            the world table (live: edits to player/reps/log/... are seen)
--   fake.modules          QuestieLoader._modules (break a module here to script a BROKEN Questie)
--   fake.calls[name]      call counts (QueryQuest, IsDoableVerbose, GetAreaIdByUiMapId, ImportModule...)
--   fake.forbidden        names of forbidden calls attempted (must stay empty)
--   fake.styleErrors      dot/colon misuse (must stay empty)
--   fake.returnTextMissing  IsDoableVerbose calls without returnText (must stay 0)
--   fake.callbackErrors   errors raised inside ready / update callbacks
--   fake.SetReady()                       flip Questie.API.isReady, run the queued ready callbacks
--   fake.PendingReadyCallbacks()          how many are queued
--   fake.FireQuestUpdate(questId, reason, objectiveIndex)   RegisterForQuestUpdates callbacks
--   fake.UpdateCallbackCount()
--   fake.Complete(id[, false])            mark (or unmark) a quest turned in
--   fake.ReassignComplete()               replace Questie.db.char.complete with a copy
--   fake.SetInLog(id, bool)               log membership (reassigns QuestiePlayer.currentQuestlog)
--   fake.SetState(id, name|nil)           script IsDoableVerbose's verdict
--   fake.SetRep(factionId, value)         GetFactionInfoByID's bar value
--   fake.SetAvailable(id, bool)           AvailableQuests.__availableQuests (Questie draws it)
--   fake.ModulesCreated()                 modules ImportModule conjured (must stay empty)
--   fake.Uninstall()                      remove the Questie / QuestieLoader globals
--
-- THE DEFAULT WORLD AT A GLANCE (what the real engine makes of it, default
-- settings; the adapter smoke's section O asserts these):
--
--   Hellfire (area 3483, uiMap 1944): 25 entries, 21 filed here (one via the
--     orphan subzone 3535) + 4 that start here (dungeon 9016 / 9017, class
--     9025, profession 9026). 13 count, 2 done: "2 / 13", 15%. Buckets: DONE 2,
--     LOG 1 (9003), AVAILABLE 9, LOCKED 2 (9004 chain, 9007 level + chain),
--     MISSED 3 (9009 rep cap, 9020 breadcrumb, 9021 outlevelled), RIVAL 1
--     (9011 Scryers), REPEATABLE 1 (9008), SEASONAL 1 (9019), OPTIONAL 1
--     (9018), EXTRA 4. The exclusive pair 9012 / 9013 is one slot (9012
--     counts). Questie draws 9005 and 9006 itself (world.available); the
--     locked givers it never draws are 9004 (56.6, 66.4) and 9007 (78.0, 34.0).
--   Terokkar (3519, 1952): 9014 + 9032 count (0 / 2); Auchindoun's 9029 / 9030
--     start there (EXTRA). Zangarmarsh (3521, 1946) has no quests of its own,
--     only the Underbog's 9031 starting at its entrance. Eversong (3430, uiMap
--     1941) has nothing but zoneMap junk: a "no quests here" zone.
--   Outland (uiMap 1945) lists Hellfire and Terokkar; dungeon maps: Ramparts
--     347 / Blood Furnace 261 -> group 3563, Mana-Tombs 272 -> group 3917,
--     Underbog 262 -> 3716. Unknown uiMap 9999 makes ZoneDB throw.
--
-- zoneMap is BUILT the way ZoneDB.GetZonesWithQuests builds it: hidden quests
-- dropped unless HIDE_ON_MAP or an event quest; race/class filtered against the
-- player; a required (non-riding) skill files the quest under its profession
-- sort key; a positive zoneOrSort is lifted to its parent; a sort key stays a
-- sort key; anything else is skipped. QuestieJourney.zones lists, per world
-- zone category, the zones that ended up with members.

local Fake = {}

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = DeepCopy(v) end
    return out
end
Fake.DeepCopy = DeepCopy

-- The real values, QuestieDB.lua:88-121
Fake.DOABLE = {
    AVAILABLE = 0, COMPLETED = 1, QUEST_LOG = 2, BLACKLISTED = 3, EXCEED_REPUTATION = 4,
    PARENT_ACTIVE = 5, WRONG_RACE = 6, NO_PREQUESTSINGLE = 7, WRONG_CLASS = 8,
    MISSING_REPUTATION = 9, PROFESSION_SKILL = 10, NO_PREQUESTGROUP = 11, PARENT_INACTIVE = 12,
    NEXTQUESTINCHAIN_ACTIVE_OR_COMPLETED = 13, EXCLUSIVE_COMPLETED = 14,
    EXCLUSIVE_IN_QUEST_LOG = 15, MISSING_DAILY = 16, PROFESSION_SPECIALIZATION = 17,
    SPELL_MISSING = 18, SPELL_KNOWN = 19, MISSING_ACHIEVEMENT = 20, BREADCRUMB_FOLLOWUP = 21,
    EVENT_INACTIVE = 22, BREADCRUMB_ACTIVE = 23, INACTIVE_DAILY = 24, LEVEL_TOO_HIGH = 25,
    LEVEL_TOO_LOW = 26, DISABLING_QUEST_COMPLETED = 27, ENABLING_QUEST_MISSING = 28,
    PROFESSION_MISSING = 29, PROFESSION_RANK = 30, DISABLED_BY = 31, ARENA_RATING = 32,
}

-- The 36 provider quest keys (QuestieDB/src/meta/questMeta.lua). A key not in
-- this list reads nil, exactly like the real Get.
local QUEST_KEY_TYPES = {
    name = "string", startedBy = "table", finishedBy = "table", requiredLevel = "number",
    questLevel = "number", requiredRaces = "number", requiredClasses = "number",
    objectivesText = "table", triggerEnd = "table", objectives = "table", sourceItemId = "number",
    preQuestGroup = "table", preQuestSingle = "table", childQuests = "table", inGroupWith = "table",
    exclusiveTo = "table", zoneOrSort = "number", requiredSkill = "table", requiredMinRep = "table",
    requiredMaxRep = "table", requiredSourceItems = "table", nextQuestInChain = "number",
    questFlags = "number", specialFlags = "number", parentQuest = "number",
    reputationReward = "table", breadcrumbForQuestId = "number", breadcrumbs = "table",
    extraObjectives = "table", requiredSpell = "number", requiredSpecialization = "number",
    requiredMaxLevel = "number", availableUntilCompleted = "number",
    availableStartingWith = "number", requiredRanks = "table", disabledByQuest = "number",
}
local NEVER_NIL = { startedBy = true, finishedBy = true, objectives = true }
local ZERO_PAIR_NIL = { requiredSkill = true, requiredMinRep = true, requiredMaxRep = true }
local NPC_KEY_TYPES = {
    name = "string", minLevelHealth = "number", maxLevelHealth = "number", minLevel = "number",
    maxLevel = "number", rank = "number", spawns = "table", waypoints = "table", zoneID = "number",
    questStarts = "table", questEnds = "table", factionID = "number", friendlyToFaction = "string",
    subName = "string", npcFlags = "number",
}
local OBJECT_KEY_TYPES = {
    name = "string", questStarts = "table", questEnds = "table", spawns = "table",
    zoneID = "number", factionID = "number", waypoints = "table",
}
local ITEM_KEY_TYPES = {
    name = "string", npcDrops = "table", objectDrops = "table", itemDrops = "table",
    vendors = "table", startQuest = "number", class = "number", subClass = "number",
}

-- Profession sort keys (QuestieProfessions.lua sortIds) and class sort keys
-- (Database/Constants.lua), the subset the fake files quests under
local PROFESSION_SORT = {
    [129] = -324, [164] = -121, [165] = -182, [171] = -181, [182] = -24, [185] = -304,
    [186] = -501, [197] = -264, [202] = -201, [333] = -502, [356] = -101, [393] = -500,
    [755] = -373, [773] = -371,
}
local RIDING = 762
local SORT_KEYS = {
    EPIC = -1, SEASONAL = -22, BATTLEGROUNDS = -25, WARLOCK = -61, WARRIOR = -81, SHAMAN = -82,
    FISHING = -101, BLACKSMITHING = -121, PALADIN = -141, MAGE = -161, ROGUE = -162,
    ALCHEMY = -181, LEATHERWORKING = -182, ENGINEERING = -201, HUNTER = -261, PRIEST = -262,
    DRUID = -263, TAILORING = -264, SPECIAL = -284, COOKING = -304, FIRST_AID = -324,
    DARKMOON_FAIRE = -364, MIDSUMMER = -369, JEWELCRAFTING = -373, SPECIALTEMP = -1000,
}
local CATEGORY_NAMES = {
    [-1] = "Epic", [-22] = "Seasonal", [-25] = "Battlegrounds", [-61] = "Warlock",
    [-81] = "Warrior", [-82] = "Shaman", [-101] = "Fishing", [-121] = "Blacksmithing",
    [-141] = "Paladin", [-161] = "Mage", [-162] = "Rogue", [-181] = "Alchemy",
    [-182] = "Leatherworking", [-201] = "Engineering", [-261] = "Hunter", [-262] = "Priest",
    [-263] = "Druid", [-264] = "Tailoring", [-284] = "Special", [-304] = "Cooking",
    [-324] = "First Aid", [-364] = "Darkmoon Faire", [-369] = "Midsummer",
    [-501] = "Mining", [-502] = "Enchanting", [-500] = "Skinning",
}

-- ---------------------------------------------------------------------------
-- The default world: a small Hellfire Peninsula (areaId 3483 / uiMap 1944)
-- with a Terokkar Forest (3519 / 1952) neighbour under Outland (uiMap 1945),
-- for a level-62 human paladin who sided with the Aldor. Every quest's role is
-- in its comment; the adapter smoke's end-to-end section counts on these.
-- ---------------------------------------------------------------------------

local DEFAULT_WORLD = {
    ready = true,
    player = {
        level = 62, class = "PALADIN", classId = 2, raceId = 1, faction = "Alliance",
        uiMapId = 1944, x = 50, y = 60,
        professions = { [186] = { "Mining", 250 } },
    },
    zones = {
        [3483] = { name = "Hellfire Peninsula", uiMapId = 1944, category = 3 },
        [3519] = { name = "Terokkar Forest", uiMapId = 1952, category = 3 },
        [3521] = { name = "Zangarmarsh", uiMapId = 1946, category = 3 },
        [3536] = { name = "Thrallmar", parent = 3483 },
        [3535] = { name = "Hellfire Citadel" },                       -- the orphan subzone (no parent)
        [3563] = { name = "Hellfire Citadel", category = 9 },          -- the dungeon GROUP key
        [3562] = { name = "Hellfire Ramparts", uiMapId = 347, category = 9,
                   entrances = { { 3483, 47.7, 53.6 } } },
        [3713] = { name = "The Blood Furnace", uiMapId = 261, category = 9,
                   entrances = { { 3483, 46.0, 51.8 } } },
        [3714] = { name = "The Shattered Halls", uiMapId = 246, category = 9, noAreaInfo = true,
                   entrances = { { 3483, 47.7, 52.0 } } },
        [3917] = { name = "Auchindoun", category = 9 },                -- group key
        [3792] = { name = "Mana-Tombs", uiMapId = 272, category = 9,
                   entrances = { { 3519, 39.6, 65.5 } } },
        [3716] = { name = "The Underbog", uiMapId = 262, category = 9,
                   entrances = { { 3521, 50.4, 40.9 } } },
        [1941] = { name = "Caverns of Time", category = 9 },           -- AREA 1941 (uiMap 1941 is Eversong!)
        [12] = { name = "Elwynn Forest", uiMapId = 1429, category = 1 },
        [3430] = { name = "Eversong Woods", uiMapId = 1941, category = 1 },
        [3524] = { name = "Azuremyst Isle", uiMapId = 1943, category = 2 },
    },
    uiMaps = {
        [946] = { name = "Cosmic", mapType = 0, children = { 947, 1945 } },
        [947] = { name = "Azeroth", mapType = 1, parent = 946, areaId = 10089, children = { 1414, 1415 } },
        [1414] = { name = "Kalimdor", mapType = 2, parent = 947, areaId = 10073, children = { 1943 } },
        [1415] = { name = "Eastern Kingdoms", mapType = 2, parent = 947, areaId = 10074, children = { 1429, 1941 } },
        [1945] = { name = "Outland", mapType = 2, parent = 946, areaId = 0, children = { 1944, 1946, 1952 } },
        [1944] = { name = "Hellfire Peninsula", mapType = 3, parent = 1945, areaId = 3483,
                   rect = { 0.55, 0.75, 0.45, 0.65 } },
        [1946] = { name = "Zangarmarsh", mapType = 3, parent = 1945, areaId = 3521,
                   rect = { 0.20, 0.40, 0.35, 0.55 } },
        [1952] = { name = "Terokkar Forest", mapType = 3, parent = 1945, areaId = 3519,
                   rect = { 0.40, 0.60, 0.65, 0.85 } },
        [347] = { name = "Hellfire Ramparts", mapType = 4, parent = 1944, areaId = 3562 },
        [261] = { name = "The Blood Furnace", mapType = 4, parent = 1944, areaId = 3713 },
        -- areaId 3713 (The Blood Furnace), NOT 3714: the real Questie's
        -- override table (QuestieDB/support/Zones/uiMapIdToAreaId.lua:15,
        -- `[246] = 3713`) is applied over its correct base row (:217) by
        -- ZoneDB.Initialize, so GetAreaIdByUiMapId(246) answers the Blood
        -- Furnace although uiMap 246 is The Shattered Halls on this build
        [246] = { name = "The Shattered Halls", mapType = 4, parent = 1944, areaId = 3713 },
        [272] = { name = "Mana-Tombs", mapType = 4, parent = 1952, areaId = 3792 },
        [262] = { name = "The Underbog", mapType = 4, parent = 1946, areaId = 3716 },
        [1429] = { name = "Elwynn Forest", mapType = 3, parent = 1415, areaId = 12,
                   rect = { 0.40, 0.50, 0.75, 0.85 } },
        [1941] = { name = "Eversong Woods", mapType = 3, parent = 1415, areaId = 3430,
                   rect = { 0.55, 0.65, 0.05, 0.15 } },
        [1943] = { name = "Azuremyst Isle", mapType = 3, parent = 1414, areaId = 3524,
                   rect = { 0.10, 0.20, 0.20, 0.30 } },
        [9536] = { name = "Thrallmar", mapType = 5, parent = 1944, areaId = 3536 },   -- subzone map
        [9535] = { name = "Hellfire Citadel", mapType = 5, parent = 1944, areaId = 3535 },
        [9999] = { name = "Nowhere", mapType = 3, parent = 1945 },                   -- no areaId: throws
    },
    continents = {
        [1] = "Eastern Kingdoms", [2] = "Kalimdor", [3] = "Outland", [9] = "Dungeons",
        [10] = "Battlegrounds", [11] = "Class", [12] = "Professions", [13] = "Events",
    },
    factions = {
        [932] = "The Aldor", [934] = "The Scryers", [946] = "Honor Hold", [942] = "Cenarion Expedition",
    },
    reps = { [932] = 3500, [934] = -3500, [946] = 4000, [942] = 9500 },
    l10nZones = { [3999] = "Fallback Vale" },     -- known only to l10n.zoneLookup
    npcs = {
        [20001] = { name = "Watch Commander Relthorn", spawns = { [3483] = { { 87.4, 50.7 } } } },
        [20002] = { name = "Force Commander Danath", spawns = { [3483] = { { 56.6, 66.4 } } } },
        [20003] = { name = "Sergeant Altumus", spawns = { [3483] = { { 61.8, 60.6 } } } },
        [20004] = { name = "Gryphon Master Ivran", spawns = { [3483] = { { 61.9, 60.8 } } } },  -- 0.22 from 20003
        [20005] = { name = "Field Marshal Brock", spawns = { [3483] = { { 62.4, 60.6 } } } },   -- 0.6 from 20003
        [20006] = { name = "Scout Ranger Ilsa", spawns = { [3536] = { { 58.0, 40.0 } } } },    -- subzone spawn
        [20007] = { name = "Wing Commander Dabir", spawns = { [3483] = { { 78.0, 34.0 } } } },
        [20008] = { name = "Quartermaster Urgronn", spawns = { [3483] = { { 54.0, 63.0 } } } },
        [20009] = { name = "Scryer Envoy", spawns = { [3483] = { { 60.0, 70.0 } } } },
        [20010] = { name = "Gunny", spawns = { [3483] = { { 56.7, 62.5 } } } },
        [20011] = { name = "Caza'rez", spawns = { [3713] = { { -1, -1 } } } },               -- dungeon sentinel
        [20012] = { name = "Hidden Errand Giver", spawns = { [3483] = { { 30.0, 30.0 } } } },
        [20013] = { name = "Festival Keeper", spawns = { [3483] = { { 64.0, 70.0 } } } },
        [20014] = { name = "Paladin Trainer", spawns = { [3483] = { { 57.0, 63.0 } } } },
        [20015] = { name = "Mining Supplier", spawns = { [3483] = { { 55.0, 64.0 } } } },
        [20016] = { name = "Patrol Sentry", spawns = { [3483] = {
            { 20, 20 }, { 25, 25 }, { 30, 20 }, { 35, 25 }, { 40, 20 }, { 45, 25 }, { 50, 20 }, { 55, 25 },
        } } },
        [20020] = { name = "Terokkar Exile", spawns = { [3519] = { { 40.0, 30.0 } } } },
        [20021] = { name = "Allerian Peacekeeper", spawns = { [3519] = { { 57.0, 55.0 } } } },
        [20022] = { name = "Auchindoun Scout", spawns = { [3519] = { { 35.0, 65.0 } } } },
        [20023] = { name = "Gzhun'tt", spawns = { [3716] = { { -1, -1 } } } },
        [20024] = { name = "Terokkar Greeter", spawns = { [3519] = { { 44.0, 45.0 } } } },
        [20025] = { name = "Marshal Dughan", spawns = { [12] = { { 42.0, 65.0 } } } },
        [20026] = { name = "Azuremyst Guide", spawns = { [3524] = { { 48.0, 50.0 } } } },
        [20027] = { name = "Horde Envoy", spawns = { [3483] = { { 50.0, 50.0 } } } },
    },
    objects = {
        [50001] = { name = "Wanted Poster", spawns = { [3483] = { { 56.5, 65.5 } } } },
    },
    items = {
        [30001] = { name = "Glowing Fel Orb" },
    },
    quests = {
        -- A chain of four: done, done, in the log, locked behind the one in the log
        [9001] = { name = "Arrival in Outland", questLevel = 58, requiredLevel = 58, zoneOrSort = 3483,
                   startedBy = { { 20001 } }, finishedBy = { { 20002 } }, nextQuestInChain = 9002 },
        [9002] = { name = "Journey to Honor Hold", questLevel = 59, requiredLevel = 58, zoneOrSort = 3483,
                   startedBy = { { 20002 } }, finishedBy = { { 20002 } }, preQuestSingle = { 9001 },
                   nextQuestInChain = 9003 },
        [9003] = { name = "Force Commander Danath", questLevel = 60, requiredLevel = 58, zoneOrSort = 3483,
                   startedBy = { { 20002 } }, finishedBy = { { 20002 } }, preQuestSingle = { 9002 },
                   nextQuestInChain = 9004, objectivesText = { "Report to Force Commander Danath." } },
        [9004] = { name = "The Legion Reborn", questLevel = 62, requiredLevel = 61, zoneOrSort = 3483,
                   startedBy = { { 20002 } }, finishedBy = { { 20002 } }, preQuestSingle = { 9003 },
                   state = "NO_PREQUESTSINGLE" },
        -- Two quests from one NPC (one pin), and a third from an NPC 0.22% away (merged)
        [9005] = { name = "Know Your Enemy", questLevel = 61, requiredLevel = 59, zoneOrSort = 3483,
                   startedBy = { { 20003 } }, finishedBy = { { 20003 } },
                   reputationReward = { { 946, 250 } }, objectivesText = { "Scout the Legion front." } },
        [9006] = { name = "The Path of Anguish", questLevel = 61, requiredLevel = 59, zoneOrSort = 3483,
                   startedBy = { { 20003 } }, finishedBy = { { 20003 } } },
        -- Locked twice over: level first (Questie's verdict), and 9005 not yet done
        [9007] = { name = "Wanted: Worg Master Kruush", questLevel = 64, requiredLevel = 63, zoneOrSort = 3483,
                   startedBy = { { 20007 } }, finishedBy = { { 20007 } }, preQuestSingle = { 9005 },
                   state = "LEVEL_TOO_LOW" },
        -- A daily (questFlags bit 4096) that is also repeatable (specialFlags bit 1)
        [9008] = { name = "Fel Orc Scavengers", questLevel = 62, requiredLevel = 60, zoneOrSort = 3483,
                   startedBy = { { 20008 } }, finishedBy = { { 20008 } }, questFlags = 4096 + 8,
                   specialFlags = 1 },
        -- Past a one-way reputation cap: missed for good
        [9009] = { name = "Ill Omens", questLevel = 61, requiredLevel = 58, zoneOrSort = 3483,
                   startedBy = { { 20008 } }, finishedBy = { { 20008 } },
                   requiredMaxRep = { 942, 9000 }, oneWayRep = true, state = "EXCEED_REPUTATION" },
        -- The Aldor / Scryer pair: the player sided with the Aldor
        [9010] = { name = "The Aldor Champion", questLevel = 62, requiredLevel = 60, zoneOrSort = 3483,
                   startedBy = { { 20004 } }, finishedBy = { { 20004 } }, requiredMinRep = { 932, 3000 } },
        [9011] = { name = "The Scryer Champion", questLevel = 62, requiredLevel = 60, zoneOrSort = 3483,
                   startedBy = { { 20009 } }, finishedBy = { { 20009 } }, requiredMinRep = { 934, 3000 },
                   state = "MISSING_REPUTATION" },
        -- An exclusive trio spanning Hellfire (9012, 9013) and Terokkar (9014).
        -- 9012 and 9013 name each other (a slot); 9013 also names 9014, which
        -- names nothing: one-way, so doing 9013 leaves 9014 doable (Questie's
        -- rule), while doing 9014 rules 9013 out.
        [9012] = { name = "Choose: the Blade", questLevel = 62, requiredLevel = 60, zoneOrSort = 3483,
                   startedBy = { { 20005 } }, finishedBy = { { 20005 } }, exclusiveTo = { 9013 } },
        [9013] = { name = "Choose: the Shield", questLevel = 62, requiredLevel = 60, zoneOrSort = 3483,
                   startedBy = { { 20005 } }, finishedBy = { { 20005 } }, exclusiveTo = { 9012, 9014 } },
        [9014] = { name = "Choose: the Staff", questLevel = 62, requiredLevel = 60, zoneOrSort = 3519,
                   startedBy = { { 20021 } }, finishedBy = { { 20021 } } },
        -- Filed under the orphan subzone 3535; its giver stands in the Thrallmar subzone
        [9015] = { name = "Wanted: Citadel Scouts", questLevel = 62, requiredLevel = 60, zoneOrSort = 3535,
                   startedBy = { { 20006 } }, finishedBy = { { 20006 } } },
        -- Dungeon quests filed under the Hellfire Citadel group key: one giver in
        -- Hellfire proper, one inside the Blood Furnace (the {-1,-1} sentinel)
        [9016] = { name = "Weaken the Ramparts", questLevel = 63, requiredLevel = 60, zoneOrSort = 3563,
                   startedBy = { { 20010 } }, finishedBy = { { 20010 } } },
        [9017] = { name = "Heart of Rage", questLevel = 64, requiredLevel = 63, zoneOrSort = 3563,
                   startedBy = { { 20011 } }, finishedBy = { { 20011 } }, state = "LEVEL_TOO_LOW" },
        -- Kept off the map by Questie (HIDE_ON_MAP), still listed
        [9018] = { name = "A Hidden Errand", questLevel = 60, requiredLevel = 58, zoneOrSort = 3483,
                   startedBy = { { 20012 } }, finishedBy = { { 20012 } }, hidden = "HIDE_ON_MAP" },
        -- An event quest while the event is closed
        [9019] = { name = "Midsummer Bonfire", questLevel = 60, requiredLevel = 1, zoneOrSort = 3483,
                   startedBy = { { 20013 } }, finishedBy = { { 20013 } }, event = "Midsummer",
                   eventActive = false },
        -- A breadcrumb whose target (9003) is already in the log; started from an object
        [9020] = { name = "Report to the Front", questLevel = 58, requiredLevel = 58, zoneOrSort = 3483,
                   startedBy = { nil, { 50001 } }, finishedBy = { { 20002 } },
                   breadcrumbForQuestId = 9003, state = "BREADCRUMB_FOLLOWUP" },
        -- Outlevelled
        [9021] = { name = "Outlevelled Errand", questLevel = 59, requiredLevel = 58, requiredMaxLevel = 60,
                   zoneOrSort = 3483, startedBy = { { 20007 } }, finishedBy = { { 20007 } },
                   state = "LEVEL_TOO_HIGH" },
        -- Started by an item: no coordinates
        [9022] = { name = "Fel Spirits", questLevel = 62, requiredLevel = 60, zoneOrSort = 3483,
                   startedBy = { nil, nil, { 30001 } }, finishedBy = { { 20002 } } },
        -- Filed in Hellfire, but the giver stands in Terokkar
        [9023] = { name = "Exiled to Terokkar", questLevel = 62, requiredLevel = 60, zoneOrSort = 3483,
                   startedBy = { { 20020 } }, finishedBy = { { 20020 } } },
        -- Horde only: never reaches zoneMap for this character
        [9024] = { name = "Horde Envoy", questLevel = 60, requiredLevel = 58, zoneOrSort = 3483,
                   startedBy = { { 20027 } }, finishedBy = { { 20027 } }, requiredRaces = 690 },
        -- A paladin class quest (class sort key -141) whose giver stands in Hellfire
        [9025] = { name = "Paladin Trial", questLevel = 62, requiredLevel = 60, zoneOrSort = -141,
                   requiredClasses = 2, startedBy = { { 20014 } }, finishedBy = { { 20014 } } },
        -- A mining quest: filed under the profession key, giver in Hellfire, skill too low
        [9026] = { name = "Smelt This", questLevel = 62, requiredLevel = 60, zoneOrSort = 3483,
                   requiredSkill = { 186, 300 }, startedBy = { { 20015 } }, finishedBy = { { 20015 } },
                   state = "PROFESSION_SKILL" },
        [9027] = { name = "Elwynn Errand", questLevel = 10, requiredLevel = 8, zoneOrSort = 12,
                   startedBy = { { 20025 } }, finishedBy = { { 20025 } } },
        [9028] = { name = "Azuremyst Errand", questLevel = 10, requiredLevel = 8, zoneOrSort = 3524,
                   startedBy = { { 20026 } }, finishedBy = { { 20026 } } },
        -- Auchindoun: one quest under an instance key, one under the group key
        [9029] = { name = "Mana-Tombs Errand", questLevel = 64, requiredLevel = 62, zoneOrSort = 3792,
                   startedBy = { { 20022 } }, finishedBy = { { 20022 } } },
        [9030] = { name = "Auchindoun Errand", questLevel = 65, requiredLevel = 63, zoneOrSort = 3917,
                   startedBy = { { 20022 } }, finishedBy = { { 20022 } }, state = "LEVEL_TOO_LOW" },
        -- Coilfang: Questie files this under the Underbog's own key
        [9031] = { name = "Underbog Errand", questLevel = 63, requiredLevel = 61, zoneOrSort = 3716,
                   startedBy = { { 20023 } }, finishedBy = { { 20023 } } },
        [9032] = { name = "Terokkar Welcome", questLevel = 62, requiredLevel = 60, zoneOrSort = 3519,
                   startedBy = { { 20024 } }, finishedBy = { { 20024 } } },
        -- One giver, eight spawns: pins cap at five per quest
        [9033] = { name = "Sentry Duty", questLevel = 61, requiredLevel = 58, zoneOrSort = 3483,
                   startedBy = { { 20016 } }, finishedBy = { { 20016 } } },
    },
    complete = { [9001] = true, [9002] = true, [9027] = true },
    log = { [9003] = true },
    available = { [9005] = true, [9006] = true },     -- Questie draws these two itself
    filler = 0,
    junkId = 77777,
}

function Fake.DefaultWorld()
    return DeepCopy(DEFAULT_WORLD)
end

-- ---------------------------------------------------------------------------
-- Install
-- ---------------------------------------------------------------------------

function Fake.Install(world, opts)
    opts = opts or {}
    local W = world or Fake.DefaultWorld()
    W.player = W.player or {}
    W.zones = W.zones or {}
    W.uiMaps = W.uiMaps or {}
    W.continents = W.continents or {}
    W.factions = W.factions or {}
    W.reps = W.reps or {}
    W.npcs = W.npcs or {}
    W.objects = W.objects or {}
    W.items = W.items or {}
    W.quests = W.quests or {}
    W.complete = W.complete or {}
    W.log = W.log or {}
    W.available = W.available or {}
    W.omitModules = W.omitModules or {}

    local fake = {
        world = W, calls = {}, forbidden = {}, styleErrors = {}, returnTextMissing = 0,
        callbackErrors = {},
    }
    local function Count(name) fake.calls[name] = (fake.calls[name] or 0) + 1 end

    local modules = {}
    local created = {}
    local function NewModule(name)
        local m = { private = {} }
        modules[name] = m
        return m
    end
    local function Module(name)
        if W.omitModules[name] then return {} end   -- a scratch table nobody registers
        return NewModule(name)
    end

    local function Forbidden(name)
        return function()
            fake.forbidden[#fake.forbidden + 1] = name
            error("fake Questie: forbidden call " .. name, 2)
        end
    end

    -- Call-style guards. A dot function handed a module table as its first
    -- argument was called with a colon; a colon function whose self is not its
    -- module was called with a dot.
    local function Dot(name, fn)
        return function(first, ...)
            if type(first) == "table" and first.private then
                fake.styleErrors[#fake.styleErrors + 1] = name .. " called with ':'"
                error("fake Questie: " .. name .. " is a dot function", 2)
            end
            return fn(first, ...)
        end
    end
    local function Colon(module, name, fn)
        return function(self, ...)
            if self ~= module then
                fake.styleErrors[#fake.styleErrors + 1] = name .. " called with '.'"
                error("fake Questie: " .. name .. " is a colon function", 2)
            end
            return fn(...)
        end
    end

    local raceFlag = 2 ^ ((W.player.raceId or 1) - 1)
    local classFlag = 2 ^ ((W.player.classId or 2) - 1)
    local function HasRace(mask) return (not mask) or mask == 0 or (mask % (2 * raceFlag)) >= raceFlag end
    local function HasClass(mask) return (not mask) or mask == 0 or (mask % (2 * classFlag)) >= classFlag end

    -- Filler quests: pointer-only rows for chunking tests
    for i = 1, (W.filler or 0) do
        local id = 50000 + i
        if not W.quests[id] then W.quests[id] = { name = "Filler " .. i, filler = true } end
    end

    -- Event quests that are not running are blacklisted with true, the way
    -- QuestieEvent leaves them until the calendar opens them
    for _, q in pairs(W.quests) do
        if q.event and not q.eventActive and q.hidden == nil then q.hidden = true end
    end

    -- ---- QuestieQuestBlacklist / QuestieCorrections ----------------------------
    local Blacklist = Module("QuestieQuestBlacklist")
    Blacklist.HIDE_ON_MAP = "HIDE_ON_MAP"
    local Corrections = Module("QuestieCorrections")
    Corrections.hiddenQuests = {}
    for id, q in pairs(W.quests) do
        if q.hidden then Corrections.hiddenQuests[id] = q.hidden end
    end

    -- ---- the readers ------------------------------------------------------------
    local function Normalise(types, key, value, known)
        local kind = types[key]
        if not kind then return nil end
        if kind == "table" then
            if value == nil or (type(value) == "table" and next(value) == nil) then
                if NEVER_NIL[key] and known then return {} end
                return nil
            end
            if ZERO_PAIR_NIL[key] and value[1] == 0 and value[2] == 0 then return nil end
            return DeepCopy(value)
        elseif kind == "number" then
            if value == nil then return known and 0 or nil end
            return value
        end
        return value
    end
    local function QuestGet(id, key)
        local q = type(id) == "number" and W.quests[id] or nil
        if not q then return nil end
        if type(key) ~= "string" then return nil end
        return Normalise(QUEST_KEY_TYPES, key, q[key], true)
    end
    local function EntityGet(store, types)
        return function(id, key)
            local row = type(id) == "number" and store[id] or nil
            if not row then return nil end
            return Normalise(types, key, row[key], true)
        end
    end
    local function GetAll(store, getter)
        return function(id, keys)
            if type(id) ~= "number" or not store[id] then return nil end
            local out = { n = #keys }
            for i = 1, #keys do out[i] = getter(id, keys[i]) end
            return out
        end
    end

    -- ---- QuestieDB ---------------------------------------------------------------
    local DB = Module("QuestieDB")
    DB.DoableStates = DeepCopy(Fake.DOABLE)
    DB.sortKeys = DeepCopy(SORT_KEYS)
    DB.activeChildQuests = {}
    DB.autoBlacklist = {}
    DB.QuestPointers = {}
    for id in pairs(W.quests) do DB.QuestPointers[id] = true end
    DB.NPCPointers, DB.ObjectPointers, DB.ItemPointers = {}, {}, {}
    for id in pairs(W.npcs) do DB.NPCPointers[id] = true end
    for id in pairs(W.objects) do DB.ObjectPointers[id] = true end
    for id in pairs(W.items) do DB.ItemPointers[id] = true end
    DB.questsOnlyAvailableUntilReputationValue = {}
    for id, q in pairs(W.quests) do
        if q.oneWayRep then DB.questsOnlyAvailableUntilReputationValue[id] = true end
    end

    local npcGet = EntityGet(W.npcs, NPC_KEY_TYPES)
    local objectGet = EntityGet(W.objects, OBJECT_KEY_TYPES)
    local itemGet = EntityGet(W.items, ITEM_KEY_TYPES)
    DB.QueryQuestSingle = Dot("QueryQuestSingle", function(id, key) Count("QueryQuestSingle"); return QuestGet(id, key) end)
    DB.QueryNPCSingle = Dot("QueryNPCSingle", function(id, key) Count("QueryNPCSingle"); return npcGet(id, key) end)
    DB.QueryObjectSingle = Dot("QueryObjectSingle", function(id, key) Count("QueryObjectSingle"); return objectGet(id, key) end)
    DB.QueryItemSingle = Dot("QueryItemSingle", function(id, key) Count("QueryItemSingle"); return itemGet(id, key) end)
    local questAll = GetAll(W.quests, QuestGet)
    DB.QueryQuest = Dot("QueryQuest", function(id, keys) Count("QueryQuest"); return questAll(id, keys) end)
    DB.QueryNPC = Dot("QueryNPC", GetAll(W.npcs, npcGet))
    DB.QueryObject = Dot("QueryObject", GetAll(W.objects, objectGet))
    DB.QueryItem = Dot("QueryItem", GetAll(W.items, itemGet))

    DB.IsRepeatable = Dot("IsRepeatable", function(id)
        local f = QuestGet(id, "specialFlags")
        return f and (f % 2) == 1
    end)
    DB.IsDailyQuest = Dot("IsDailyQuest", function(id)
        local f = QuestGet(id, "questFlags")
        return f and (f % 8192) >= 4096
    end)
    DB.IsDoable = Forbidden("QuestieDB.IsDoable")
    DB.IsComplete = Forbidden("QuestieDB.IsComplete")
    DB.GetQuest = Dot("GetQuest", function(id) Count("GetQuest"); return nil end)

    local Event, Player   -- forward (both modules are built below)
    DB.IsDoableVerbose = Dot("IsDoableVerbose", function(questId, debugPrint, returnText, returnBrief)
        Count("IsDoableVerbose")
        local S = DB.DoableStates
        if not returnText then
            -- The real gotcha: no branch returns without returnText
            fake.returnTextMissing = fake.returnTextMissing + 1
            return "", false, S.AVAILABLE
        end
        local q = W.quests[questId]
        local complete = Questie and Questie.db and Questie.db.char and Questie.db.char.complete
        if complete and complete[questId] then return "complete", false, S.COMPLETED end
        if W.log[questId] then return "active", false, S.QUEST_LOG end
        local hidden = Corrections.hiddenQuests[questId]
        if hidden and hidden ~= Blacklist.HIDE_ON_MAP then
            if q and q.event and not q.eventActive then return "event", true, S.EVENT_INACTIVE end
            return "blacklisted", true, S.BLACKLISTED
        end
        if not q then return "available", false, S.AVAILABLE end
        if not HasRace(q.requiredRaces) then return "race", true, S.WRONG_RACE end
        if not HasClass(q.requiredClasses) then return "class", true, S.WRONG_CLASS end
        -- The real exclusive check (QuestieDB.lua:1262-1281): the quest's OWN
        -- exclusiveTo only, done before in the log, per entry. A quest that is
        -- merely NAMED by a done one is untouched -- exclusiveTo is one-way.
        for _, other in pairs(q.exclusiveTo or {}) do
            if complete and complete[other] then return "exclusive done", true, S.EXCLUSIVE_COMPLETED end
            if Player.currentQuestlog[other] then return "exclusive in log", true, S.EXCLUSIVE_IN_QUEST_LOG end
        end
        if q.state then
            local value = S[q.state]
            if value == nil then value = q.state end   -- a number scripted directly
            return q.state .. "", true, value
        end
        return "available", false, S.AVAILABLE
    end)

    -- ---- zoneMap, the way ZoneDB.GetZonesWithQuests builds it -------------------
    local sortSet = {}
    for _, v in pairs(SORT_KEYS) do sortSet[v] = true end
    for _, v in pairs(PROFESSION_SORT) do sortSet[v] = true end
    local zoneMap = {}
    for id, q in pairs(W.quests) do
        local hidden = Corrections.hiddenQuests[id]
        if (not q.filler) and ((not hidden) or hidden == "HIDE_ON_MAP" or q.event) then
            if HasRace(q.requiredRaces) and HasClass(q.requiredClasses) then
                local zoneOrSort = q.zoneOrSort or 0
                local skill = q.requiredSkill
                local key
                if skill and skill[1] and skill[1] ~= RIDING and not (skill[1] == 0 and skill[2] == 0) then
                    key = PROFESSION_SORT[skill[1]]
                elseif zoneOrSort > 0 then
                    local zone = W.zones[zoneOrSort]
                    key = (zone and zone.parent) or zoneOrSort
                elseif sortSet[zoneOrSort] then
                    key = zoneOrSort
                end
                if key then
                    zoneMap[key] = zoneMap[key] or {}
                    zoneMap[key][id] = true
                end
            end
        end
    end
    -- The junk goes into a zone with quests AND into one with none (Eversong
    -- for this paladin), where it is the zone's only entry: without a
    -- QuestPointers guard that zone would look like it has quests
    if W.junkId ~= false then
        for _, areaId in ipairs(W.junkZones or { 3483, 3430 }) do
            zoneMap[areaId] = zoneMap[areaId] or {}
            zoneMap[areaId][W.junkId or 77777] = true
        end
    end

    -- ---- ZoneDB --------------------------------------------------------------------
    local Zone = Module("ZoneDB")
    Zone.zoneIDs = {}
    Zone.instanceIdToAreaId = {}
    Zone.GetAreaIdByUiMapId = Colon(Zone, "ZoneDB:GetAreaIdByUiMapId", function(uiMapId)
        Count("GetAreaIdByUiMapId")
        local map = W.uiMaps[uiMapId]
        if map and map.areaId then return map.areaId end
        error("No AreaId found for UiMapId: " .. tostring(uiMapId))
    end)
    Zone.GetUiMapIdByAreaId = Colon(Zone, "ZoneDB:GetUiMapIdByAreaId", function(areaId)
        Count("GetUiMapIdByAreaId")
        local zone = W.zones[areaId]
        return zone and zone.uiMapId or nil
    end)
    Zone.GetParentZoneId = Colon(Zone, "ZoneDB:GetParentZoneId", function(areaId)
        local zone = W.zones[areaId]
        return zone and zone.parent or nil
    end)
    Zone.GetDungeonLocation = Colon(Zone, "ZoneDB:GetDungeonLocation", function(areaId)
        local zone = W.zones[areaId]
        return zone and zone.entrances and DeepCopy(zone.entrances) or nil
    end)
    Zone.GetLocalizedDungeonName = Colon(Zone, "ZoneDB:GetLocalizedDungeonName", function(areaId)
        -- The real one prefers Blizzard's name and falls back to its own
        local zone = W.zones[areaId]
        if not (zone and zone.entrances) then return nil end
        local blizzard = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaId)
        return blizzard or zone.name
    end)
    Zone.IsDungeonZone = Dot("ZoneDB.IsDungeonZone", function(areaId)
        local zone = W.zones[areaId]
        return (zone and zone.entrances) and true or false
    end)
    Zone.GetDungeons = Colon(Zone, "ZoneDB:GetDungeons", function()
        local out = {}
        for areaId, zone in pairs(W.zones) do
            if zone.entrances then out[areaId] = { zone.name, nil, zone.entrances[1][1], DeepCopy(zone.entrances) } end
        end
        return out
    end)
    Zone.GetAreaIdByName = Colon(Zone, "ZoneDB:GetAreaIdByName", function(name)
        local best
        for areaId, zone in pairs(W.zones) do
            if zone.name == name and ((not best) or areaId < best) then best = areaId end
        end
        return best
    end)
    Zone.GetZonesWithQuests = Forbidden("ZoneDB.GetZonesWithQuests")

    -- ---- QuestiePlayer ---------------------------------------------------------------
    Player = Module("QuestiePlayer")
    Player.currentQuestlog = {}
    for id in pairs(W.log) do Player.currentQuestlog[id] = { Id = id } end
    Player.faction = W.player.faction
    Player.GetPlayerLevel = Dot("QuestiePlayer.GetPlayerLevel", function()
        local live = (UnitLevel and UnitLevel("player")) or 0
        return math.max(W.player.level or 1, live)
    end)
    Player.HasRequiredRace = Dot("QuestiePlayer.HasRequiredRace", HasRace)
    Player.HasRequiredClass = Dot("QuestiePlayer.HasRequiredClass", HasClass)
    Player.GetCurrentZoneId = Colon(Player, "QuestiePlayer:GetCurrentZoneId", function()
        -- Unguarded, like the real one: it can throw
        Count("GetCurrentZoneId")
        if W.player.zoneIdOverride then return W.player.zoneIdOverride end
        local uiMapId = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        if uiMapId then return Zone:GetAreaIdByUiMapId(uiMapId) end
        return nil
    end)

    -- ---- QuestieLib --------------------------------------------------------------------
    local Lib = Module("QuestieLib")
    Lib.GetEffectiveQuestLevel = Dot("QuestieLib.GetEffectiveQuestLevel", function(questId, playerLevel)
        local level, required = QuestGet(questId, "questLevel"), QuestGet(questId, "requiredLevel")
        if level == -1 then
            local pl = playerLevel or Player.GetPlayerLevel()
            if required > pl then level = required else level = pl; required = pl end
        end
        return level, required, QuestGet(questId, "requiredMaxLevel")
    end)

    -- ---- QuestieJourney ------------------------------------------------------------------
    local Journey = Module("QuestieJourney")
    Journey.zoneMap = zoneMap
    Journey.questCategoryKeys = {
        EASTERN_KINGDOMS = 1, KALIMDOR = 2, OUTLAND = 3, DUNGEONS = 9, BATTLEGROUNDS = 10,
        CLASS = 11, PROFESSIONS = 12, EVENTS = 13,
    }
    Journey.continents = DeepCopy(W.continents)
    local className = CATEGORY_NAMES[SORT_KEYS[W.player.class or ""] or 0]
    if className then Journey.continents[11] = className end
    Journey.zones = {}
    for areaId, zone in pairs(W.zones) do
        if zone.category and zoneMap[areaId] then
            Journey.zones[zone.category] = Journey.zones[zone.category] or {}
            Journey.zones[zone.category][areaId] = zone.name
        end
    end
    -- Class keys land in category 11 and profession keys in 12, as
    -- l10n.zoneCategoryLookup files them
    for key in pairs(zoneMap) do
        if type(key) == "number" and key < 0 and CATEGORY_NAMES[key] then
            local cat = 11
            for _, sortId in pairs(PROFESSION_SORT) do if sortId == key then cat = 12 end end
            Journey.zones[cat] = Journey.zones[cat] or {}
            Journey.zones[cat][key] = CATEGORY_NAMES[key]
        end
    end

    -- ---- QuestieEvent --------------------------------------------------------------------------
    Event = Module("QuestieEvent")
    Event.activeQuests = {}
    for id, q in pairs(W.quests) do
        if q.event and q.eventActive then Event.activeQuests[id] = true end
    end
    Event.IsEventQuest = Dot("QuestieEvent.IsEventQuest", function(id)
        local q = W.quests[id]
        return (q and q.event ~= nil) and true or false
    end)
    Event.IsEventActiveForQuest = Dot("QuestieEvent.IsEventActiveForQuest", function(id)
        return Event.activeQuests[id] == true
    end)
    Event.GetEventNameFor = Dot("QuestieEvent.GetEventNameFor", function(id)
        local q = W.quests[id]
        return q and q.event or ""
    end)

    -- ---- QuestieReputation / QuestieProfessions ----------------------------------------------
    local Reputation = Module("QuestieReputation")
    Reputation.GetPlayerReputations = Colon(Reputation, "QuestieReputation:GetPlayerReputations", function()
        local out = {}
        for id, value in pairs(W.reps) do out[id] = { 4, value } end
        return out
    end)
    local Professions = Module("QuestieProfessions")
    Professions.professionKeys = { MINING = 186, ENCHANTING = 333, RIDING = RIDING, FIRST_AID = 129 }
    Professions.GetPlayerProfessions = Colon(Professions, "QuestieProfessions:GetPlayerProfessions", function()
        return W.player.professions or {}
    end)
    Professions.GetSortIdByProfessionId = Colon(Professions, "QuestieProfessions:GetSortIdByProfessionId", function(id)
        return PROFESSION_SORT[id]
    end)
    -- English names by skill-line id, like QuestieProfessions.lua's professionNames
    local PROFESSION_NAMES = { [129] = "First Aid", [171] = "Alchemy", [186] = "Mining", [333] = "Enchanting",
        [762] = "Riding" }
    Professions.GetProfessionName = Colon(Professions, "QuestieProfessions:GetProfessionName", function(id)
        return PROFESSION_NAMES[id]
    end)

    -- ---- AvailableQuests / QuestieQuest --------------------------------------------------------
    local Available = Module("AvailableQuests")
    Available.__availableQuests = W.available
    Available.IsLevelRequirementsFulfilled = Forbidden("AvailableQuests.IsLevelRequirementsFulfilled")
    Available.CalculateAndDrawAll = function() Count("CalculateAndDrawAll") end
    local Quest = Module("QuestieQuest")
    Quest.HideQuest = Forbidden("QuestieQuest:HideQuest")
    Quest.UnhideQuest = Forbidden("QuestieQuest:UnhideQuest")

    -- ---- l10n (callable through a metatable, like the real one) --------------------------------
    local L = Module("l10n")
    L.zoneLookup = { [0] = {}, [1] = {}, [530] = {} }
    for areaId, zone in pairs(W.zones) do
        local cont = (zone.category == 1 and 0) or (zone.category == 2 and 1) or 530
        L.zoneLookup[cont][areaId] = zone.name
    end
    for areaId, name in pairs(W.l10nZones or {}) do L.zoneLookup[530][areaId] = name end
    L.questCategoryLookup = DeepCopy(CATEGORY_NAMES)
    L.continentLookup = DeepCopy(W.continents)
    setmetatable(L, { __call = function(_, key) return key end })

    -- ---- Questie and the loader ------------------------------------------------------------------
    local readyCallbacks = {}
    local updateCallbacks = {}
    Questie = {
        started = W.ready ~= false,
        db = {
            char = { complete = DeepCopy(W.complete), hidden = {} },
            profile = { debugEnabled = false },
            global = { unavailableQuestsDeterminedByTalking = {} },
        },
        API = { isReady = W.ready ~= false },
    }
    Questie.API.Enums = {
        QuestUpdateTriggerReason = { QUEST_ACCEPTED = 1, QUEST_UPDATED = 2, QUEST_TURNED_IN = 3, QUEST_ABANDONED = 4 },
    }
    function Questie.API.RegisterOnReady(callback)
        if type(callback) ~= "function" then error("RegisterOnReady: callback must be a function") end
        Count("RegisterOnReady")
        if Questie.API.isReady then
            local ok, err = pcall(callback)
            if not ok then fake.callbackErrors[#fake.callbackErrors + 1] = err end
            return
        end
        readyCallbacks[#readyCallbacks + 1] = callback
    end
    function Questie.API.RegisterForQuestUpdates(callback)
        if type(callback) ~= "function" then error("RegisterForQuestUpdates: callback must be a function") end
        Count("RegisterForQuestUpdates")
        updateCallbacks[#updateCallbacks + 1] = callback
    end

    QuestieLoader = { _modules = modules }
    function QuestieLoader:ImportModule(name)
        Count("ImportModule")
        if not modules[name] then
            created[#created + 1] = name
            modules[name] = { private = {} }
        end
        return modules[name]
    end
    QuestieLoader.CreateModule = QuestieLoader.ImportModule

    -- ---- the harness handle ----------------------------------------------------------------------
    fake.modules = modules
    function fake.ModulesCreated() return created end
    function fake.SetReady()
        Questie.API.isReady = true
        Questie.started = true
        local queue = readyCallbacks
        readyCallbacks = {}
        for _, cb in ipairs(queue) do
            local ok, err = pcall(cb)
            if not ok then fake.callbackErrors[#fake.callbackErrors + 1] = err end
        end
    end
    function fake.PendingReadyCallbacks() return #readyCallbacks end
    function fake.FireQuestUpdate(questId, reason, objectiveIndex)
        for _, cb in ipairs(updateCallbacks) do
            local ok, err = pcall(cb, questId, objectiveIndex, reason or 2)
            if not ok then fake.callbackErrors[#fake.callbackErrors + 1] = err end
        end
    end
    function fake.UpdateCallbackCount() return #updateCallbacks end
    function fake.Complete(id, done)
        if done == false then
            Questie.db.char.complete[id] = nil
            W.complete[id] = nil
        else
            Questie.db.char.complete[id] = true
            W.complete[id] = true
        end
    end
    -- Questie rebuilds the table on SmoothReset; a cached reference goes stale
    function fake.ReassignComplete()
        Questie.db.char.complete = DeepCopy(Questie.db.char.complete)
    end
    function fake.SetInLog(id, inLog)
        W.log[id] = inLog and true or nil
        local fresh = {}
        for qid in pairs(W.log) do fresh[qid] = { Id = qid } end
        Player.currentQuestlog = fresh
    end
    function fake.SetState(id, name) if W.quests[id] then W.quests[id].state = name end end
    function fake.SetRep(factionId, value) W.reps[factionId] = value end
    function fake.SetAvailable(id, on) W.available[id] = on and true or nil end
    function fake.Uninstall()
        Questie = nil
        QuestieLoader = nil
    end
    return fake
end

-- ---------------------------------------------------------------------------
-- Client stubs. Each is installed only when the harness has not defined it
-- (opts.force overwrites), so a harness with its own C_Map keeps it.
-- ---------------------------------------------------------------------------

function Fake.InstallClient(world, opts)
    opts = opts or {}
    local W = world
    local force = opts.force
    local function Set(tbl, key, value)
        if force or tbl[key] == nil then tbl[key] = value end
    end
    _G.Enum = _G.Enum or {}
    Set(_G.Enum, "UIMapType", { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 })
    _G.C_QuestLog = _G.C_QuestLog or {}
    Set(_G.C_QuestLog, "IsOnQuest", function(id) return W.log[id] == true end)
    _G.C_Map = _G.C_Map or {}
    Set(_G.C_Map, "GetAreaInfo", function(areaId)
        local zone = W.zones[areaId]
        if zone and not zone.noAreaInfo then return zone.name end
        return nil
    end)
    Set(_G.C_Map, "GetMapInfo", function(uiMapId)
        local map = W.uiMaps[uiMapId]
        if not map then return nil end
        return { mapID = uiMapId, name = map.name, mapType = map.mapType, parentMapID = map.parent or 0 }
    end)
    Set(_G.C_Map, "GetBestMapForUnit", function(unit)
        if unit == "player" then return W.player.uiMapId end
        return nil
    end)
    Set(_G.C_Map, "GetPlayerMapPosition", function(uiMapId, unit)
        if unit ~= "player" or uiMapId ~= W.player.uiMapId or not W.player.x then return nil end
        local v = { x = W.player.x / 100, y = W.player.y / 100 }
        function v:GetXY() return self.x, self.y end
        return v
    end)
    Set(_G.C_Map, "GetMapChildrenInfo", function(uiMapId, mapType)
        local map = W.uiMaps[uiMapId]
        local out = {}
        for _, child in ipairs(map and map.children or {}) do
            local c = W.uiMaps[child]
            if c and (mapType == nil or c.mapType == mapType) then
                out[#out + 1] = { mapID = child, name = c.name, mapType = c.mapType, parentMapID = uiMapId }
            end
        end
        return out
    end)
    Set(_G.C_Map, "GetMapRectOnMap", function(uiMapId, topUiMapId)
        local map = W.uiMaps[uiMapId]
        if not (map and map.rect and map.parent == topUiMapId) then return nil end
        return map.rect[1], map.rect[2], map.rect[3], map.rect[4]
    end)
    Set(_G, "GetFactionInfoByID", function(factionId)
        local name = W.factions[factionId]
        if not name then return nil end
        local value = W.reps[factionId] or 0
        local standing = 4
        local thresholds = { -42000, -6000, -3000, 0, 3000, 9000, 21000, 42000 }
        for i = #thresholds, 1, -1 do
            if value >= thresholds[i] then standing = i; break end
        end
        return name, "", standing, 0, 0, value, false, false, false, false, false, false, false, factionId
    end)
    -- The client's quest log, as the era's two calls see it: one heading,
    -- then the quests of world.log in id order. Installed as a PAIR, and only
    -- where the harness has neither -- a harness with its own mutable log
    -- keeps its own index space.
    if force or (_G.GetQuestLogTitle == nil and _G.GetQuestLogIndexByID == nil) then
        local function LogIds()
            local ids = {}
            for id, on in pairs(W.log) do if on then ids[#ids + 1] = id end end
            table.sort(ids)
            return ids
        end
        -- A collapsed heading takes its quests out of the index space, as
        -- in the client (D3)
        _G.GetQuestLogIndexByID = function(questId)
            if W.logCollapsed then return 0 end
            for position, id in ipairs(LogIds()) do
                if id == questId then return position + 1 end
            end
            return 0
        end
        _G.GetQuestLogTitle = function(index)
            if index == 1 then return "Hellfire Peninsula", 0, nil, true, W.logCollapsed and true or false, nil, nil, 0 end
            if W.logCollapsed then return nil end
            local id = LogIds()[(index or 0) - 1]
            local q = id and W.quests[id]
            if not q then return nil end
            return q.name, q.questLevel or 0, nil, false, false, (W.logComplete or {})[id], 1, id
        end
        -- By questID, whatever the headings (Blizzard's quest map provider
        -- calls it so); a boolean, like the modern client's
        _G.IsQuestComplete = function(questId)
            return (W.log[questId] and (W.logComplete or {})[questId] == 1) and true or false
        end
    end
    Set(_G, "UnitClassBase", function(unit) if unit == "player" then return W.player.class end end)
    Set(_G, "UnitLevel", function() return W.player.level end)
    Set(_G, "GetRealZoneText", function()
        local map = W.uiMaps[W.player.uiMapId]
        return map and map.name or ""
    end)
end

return Fake
