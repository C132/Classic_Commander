-- Commander Orders: a QuestieDB + Questie shaped fixture for the locator's
-- harness (orders_locate_smoke.lua; critic D9).
--
-- Questie and QuestieDB are not tracked in git and the real-boot tooling
-- lives in a session scratchpad, so the locator's offline checks run against
-- this committed copy of the SURFACE CommanderOrdersLocate.lua reads:
--
--   LibQuestieDB (contract 2): RequireContract, Npc / Object / Item entities
--     with Get(id, key) (table fields handed out as fresh copies, as the real
--     reader does), IdsByName (a lazily built exact-name index), GetAllIds,
--     the named getters; the NpcDB / ObjectDB / ItemDB globals; Support.Get(
--     "ZoneDB").private with areaIdToUiMapId / subZoneToParentZone as
--     "return {...}" STRINGS (QuestieDB's provider format) and `dungeons`.
--   Questie: Questie.API (isReady, RegisterOnReady: called at once when
--     ready, else queued), Questie.db.char.vendorList (Stage 3), and
--     QuestieLoader._modules: Townsfolk (the Stage 1 lists), ZoneDB
--     (GetUiMapIdByAreaId / GetParentZoneId / GetDungeonLocation, colon
--     calls, raising before its Initialize as the real one does),
--     QuestieCorrections.questNPCBlacklist, QuestieDB.npcFlags.
--
-- Every NPC, object and item row below is REAL: copied from Questie 12.0.3 /
-- QuestieDB 1.0.4 (TBC) booted under luajit with the session's realdata
-- tooling on 2026-10-05 (spawns are 0..100 on the areaId's map, {-1, -1}
-- inside an instance). Spirit Healer 6491's 154 points are cut to the first
-- point of six of its areas. The lists are subsets of Questie's lists, in
-- Questie's own shapes. Four SYNTHETIC rows (ids 900001+) are marked: edge
-- cases no real row shows on its own (bad coordinates, a mixed open-world and
-- instance NPC, an empty spawn table, a spawn keyed by a subzone).
--
--     local F = dofile(".../fake_questiedb.lua")
--     F.Install({ ... })      -- from orders_mock's Boot `before` hook
--   opts (all optional):
--     questieDB = false        no LibQuestieDB at all
--     questie = false          QuestieDB alone (no Questie, no QuestieLoader)
--     contract = 3             the installed QuestieDB's contract (min = it):
--                              RequireContract(2) then answers false
--     stage = 0 | 1 | 3        0: Townsfolk lists still empty and ZoneDB not
--                              initialised; 1 (default): lists built; 3:
--                              vendor lists built and Questie.API.isReady
--     faction = "Horde"        whose vendor lists Stage 3 builds
--     support = false          no Support.Get (the no-Questie zone bridge)
--     blacklist = { [id] = true }
--     brokenTownsfolk = true   Townsfolk.townsfolk is not a table
--   F.Stage1()                 build the Townsfolk lists and initialise ZoneDB
--                              (a Stage 0 install catching up)
--   F.Stage3()                 build the vendor lists, set isReady, run the
--                              ready callbacks (as QuestieInit's Stage 3)
--   F.calls                    entity Get calls so far ({ Npc = n, ... })
--   F.nameBuilds               name-index builds ({ Npc = n, ... })
--   F.raise = { spawns = true }  make Get(id, "spawns") raise

local F = {}

-- ---------------------------------------------------------------------------
-- The rows (real unless marked)
-- ---------------------------------------------------------------------------
F.NPCS = {
    -- Elwynn Forest / Stormwind (Alliance)
    [295] = { name = "Innkeeper Farley", subName = "Innkeeper", friendlyToFaction = "A", npcFlags = 66179, spawns = { [12] = { { 43.77, 65.8 } } } },
    [54] = { name = "Corina Steele", subName = "Weaponsmith", friendlyToFaction = "A", npcFlags = 4224, spawns = { [12] = { { 41.53, 65.88 } } } },
    [352] = { name = "Dungar Longdrink", subName = "Gryphon Master", friendlyToFaction = "A", npcFlags = 8195, spawns = { [1519] = { { 66.27, 62.13 } } } },
    [2455] = { name = "Olivia Burnside", subName = "Banker", friendlyToFaction = "A", npcFlags = 131073, spawns = { [1519] = { { 57.66, 72.78 } } } },
    [925] = { name = "Brother Sammuel", subName = "Paladin Trainer", friendlyToFaction = "A", npcFlags = 19, spawns = { [12] = { { 50.43, 42.12 } } } },
    [6749] = { name = "Erma", subName = "Stable Master", friendlyToFaction = "A", npcFlags = 4194304, spawns = { [12] = { { 42.85, 65.95 } } } },
    [340] = { name = "Kendor Kabonka", subName = "Master of Cooking Recipes", friendlyToFaction = "A", npcFlags = 128, spawns = { [1519] = { { 74.69, 36.51 } } } },
    -- Hellfire Peninsula: Thrallmar (Horde), Honor Hold (Alliance), Falcon Watch
    [16583] = { name = "Rohok", subName = "Master Blacksmithing Trainer", friendlyToFaction = "H", npcFlags = 4243, spawns = { [3483] = { { 53.13, 38.16 } } } },
    [16823] = { name = "Humphry", subName = "Master Blacksmithing Trainer", friendlyToFaction = "A", npcFlags = 4241, spawns = { [3483] = { { 56.73, 63.58 } } } },
    [22225] = { name = "Reagan Mancuso", subName = "Gem Vendor", friendlyToFaction = "H", npcFlags = 4224, spawns = { [3483] = { { 56.81, 37.79 } } } },
    [16587] = { name = "Barley", subName = "Wind Rider Master", friendlyToFaction = "H", npcFlags = 8193, spawns = { [3483] = { { 56.29, 36.24 } } } },
    [16822] = { name = "Flightmaster Krill Bitterhue", subName = "Gryphon Master", friendlyToFaction = "A", npcFlags = 8193, spawns = { [3483] = { { 54.68, 62.35 } } } },
    [16602] = { name = "Floyd Pinkus", subName = "Innkeeper", friendlyToFaction = "H", npcFlags = 66433, spawns = { [3483] = { { 56.71, 37.47 } } } },
    [16826] = { name = "Sid Limbardi", subName = "Innkeeper", friendlyToFaction = "A", npcFlags = 65667, spawns = { [3483] = { { 54.22, 63.6 } } } },
    [18905] = { name = "Innkeeper Bazil Olof'tazun", subName = "Innkeeper", friendlyToFaction = "H", npcFlags = 66177, spawns = { [3483] = { { 26.88, 59.53 } } } },
    [16585] = { name = "Cookie One-Eye", subName = "Food & Drink", friendlyToFaction = "H", npcFlags = 640, spawns = { [3483] = { { 54.61, 41.21 } } } },
    [18753] = { name = "Felannia", subName = "Master Enchanting Trainer", friendlyToFaction = "H", npcFlags = 209, spawns = { [3483] = { { 52.34, 35.98 } } } },
    [18773] = { name = "Johan Barnes", subName = "Master Enchanting Trainer", friendlyToFaction = "A", npcFlags = 145, spawns = { [3483] = { { 53.63, 66.14 } } } },
    [18991] = { name = "Aresella", subName = "Medic", friendlyToFaction = "H", npcFlags = 208, spawns = { [3483] = { { 26.18, 62.05 } } } },
    [18990] = { name = "Burko", subName = "Medic", friendlyToFaction = "A", npcFlags = 208, spawns = { [3483] = { { 22.33, 39.42 } } } },
    -- Orgrimmar, Undercity, Eversong (Horde)
    [3335] = { name = "Hagrus", subName = "Reagents", friendlyToFaction = "H", npcFlags = 2176, spawns = { [1637] = { { 45.99, 45.68 } } } },
    [2704] = { name = "Hanashi", subName = "Weapon Master", friendlyToFaction = "H", npcFlags = 19, spawns = { [1637] = { { 81.53, 19.63 } } } },
    [5958] = { name = "Thuul", subName = "Portal Trainer", friendlyToFaction = "H", npcFlags = 19, spawns = { [1637] = { { 38.68, 85.41 } } } },
    [15280] = { name = "Jesthenis Sunstriker", subName = "Paladin Trainer", friendlyToFaction = "H", npcFlags = 19, spawns = { [3430] = { { 39.47, 20.56 } } } },
    [347] = { name = "Grizzle Halfmane", subName = "Alterac Valley Battlemaster", friendlyToFaction = "H", npcFlags = 1048577, spawns = { [1497] = { { 56.13, 85.3 } } } },
    [989] = { name = "Banalash", subName = "Trade Supplies", friendlyToFaction = "H", npcFlags = 128, spawns = { [8] = { { 44.77, 56.63 } } } },
    -- Both factions
    [6491] = { name = "Spirit Healer", friendlyToFaction = "AH", npcFlags = 16385,
               spawns = { [12] = { { 39.48, 60.55 } }, [3483] = { { 27.66, 63.27 } }, [14] = { { 57.22, 73.26 } },
                          [1] = { { 47.31, 54.61 } }, [3521] = { { 47.54, 50.33 } }, [440] = { { 53.9, 28.8 } } } },
    [18251] = { name = "Caregiver Abidaar", subName = "Innkeeper", friendlyToFaction = "A", npcFlags = 66177, spawns = { [3521] = { { 67.17, 49.32 } } } },
    [17904] = { name = "Fedryen Swiftspear", subName = "Cenarion Expedition Quartermaster", friendlyToFaction = "AH", npcFlags = 4224, spawns = { [3521] = { { 79.26, 63.67 } } } },
    [20194] = { name = "Dealer Dunar", subName = "General Provisioner", friendlyToFaction = "AH", npcFlags = 1409, spawns = { [3523] = { { 46.73, 56.64 } } } },
    [20989] = { name = "Dealer Sadaqat", subName = "Potent Potables", friendlyToFaction = "AH", npcFlags = 128, spawns = { [3523] = { { 43.24, 34.99 } } } },
    [14847] = { name = "Professor Thaddeus Paleo", subName = "Darkmoon Faire Cards & Exotic Goods", friendlyToFaction = "AH", npcFlags = 0,
                spawns = { [12] = { { 41.25, 70.05 } }, [215] = { { 36.43, 38.13 } }, [3519] = { { 34.27, 34.41 } } } },
    [24409] = { name = "Kyren", subName = "Reagents", friendlyToFaction = "AH", npcFlags = 2176 },                  -- no spawns
    [26304] = { name = "General Goods Vendor", friendlyToFaction = "AH", npcFlags = 4224 },                       -- no spawns
    -- Inside instances ({-1, -1} on the instance's areaId)
    [17257] = { name = "Magtheridon", npcFlags = 0, spawns = { [3836] = { { -1, -1 } } } },
    [15687] = { name = "Moroes", subName = "Tower Steward", npcFlags = 0, spawns = { [3457] = { { -1, -1 } } } },
    [644] = { name = "Rhahk'Zor", subName = "The Foreman", npcFlags = 0, spawns = { [1581] = { { -1, -1 } } } },
    -- One name, two NPCs (Alterac Mountains, Arathi Highlands)
    [2241] = { name = "Syndicate Thief", npcFlags = 0, spawns = { [36] = { { 48.74, 82.99 }, { 57.6, 68.54 }, { 58.17, 68.44 } } } },
    [24477] = { name = "Syndicate Thief", npcFlags = 0, spawns = { [45] = { { 29.82, 61.33 }, { 26.55, 65.78 } } } },
    -- SYNTHETIC: a spawn off the map, a non-table and a real one beside them
    [900001] = { name = "Synthetic Wanderer", friendlyToFaction = "AH", npcFlags = 0,
                 spawns = { [12] = { { 120, 50 }, "junk", { 48.0, 42.0 } }, [99999] = { { 50, 50 } } } },
    -- SYNTHETIC: open world and inside an instance (the open world wins)
    [900002] = { name = "Synthetic Traveller", friendlyToFaction = "AH", npcFlags = 0,
                 spawns = { [3483] = { { 50.0, 50.0 } }, [3836] = { { -1, -1 } } } },
    -- SYNTHETIC: an empty spawn table
    [900003] = { name = "Synthetic Ghost", friendlyToFaction = "AH", npcFlags = 0, spawns = {} },
    -- SYNTHETIC: a spawn keyed by a SUBZONE (Goldshire 87, no map of its own:
    -- its parent Elwynn Forest 12 lends one)
    [900004] = { name = "Synthetic Villager", friendlyToFaction = "AH", npcFlags = 0, spawns = { [87] = { { 42.0, 65.0 } } } },
}

F.OBJECTS = {
    [759] = { name = "The Holy Spring", factionID = 0, spawns = { [33] = { { 28.96, 61.93 } } } },
    [143981] = { name = "Mailbox", factionID = 29, spawns = { [14] = { { 51.9, 42.15 } } } },
    [143982] = { name = "Mailbox", factionID = 29, spawns = { [17] = { { 52.03, 30.43 } } } },
    [32349] = { name = "Mailbox", factionID = 55, spawns = { [1537] = { { 20.96, 52.41 } } } },
    [178824] = { name = "Meeting Stone", factionID = 0, spawns = { [17] = { { 45.16, 88.61 } } } },
}

F.ITEMS = {
    -- 86 vendors in QuestieDB; these are the ones the fixture carries
    [6217] = { name = "Copper Rod", vendors = { 989, 18753, 18773 } },
    [22829] = { name = "Super Healing Potion", vendors = { 14847, 20989, 24409, 26304 } },
    [728] = { name = "Recipe: Westfall Stew", vendors = { 340 } },
    [737] = { name = "Holy Spring Water", objectDrops = { 759 } },
    [872] = { name = "Rockslicer", npcDrops = { 644 } },
}

-- Questie's areaIdToUiMapId / subZoneToParentZone rows these spawns need
F.AREAS = {
    [1] = 1426, [4] = 1419, [8] = 1435, [12] = 1429, [14] = 1411, [17] = 1413, [33] = 1434, [36] = 1416,
    [40] = 1436, [41] = 1430, [45] = 1417, [215] = 1412, [440] = 1446, [1497] = 1458, [1519] = 1453,
    [1537] = 1455, [1581] = 291, [1637] = 1454, [3430] = 1941, [3457] = 350, [3483] = 1944, [3518] = 1951,
    [3519] = 1952, [3521] = 1946, [3523] = 1953, [3703] = 1955, [3836] = 331,
}
F.PARENTS = { [87] = 12 }

-- Questie's dungeons.lua rows (one, in its shape) for the no-table fallback
F.DUNGEONS = {
    [3562] = { "Hellfire Ramparts", nil, 3483, { { 3483, 47.7, 53.6 } } },
}

-- The Townsfolk lists (Stage 1), Questie's keys and shapes
local function TownsfolkLists()
    return {
        townsfolk = {
            Repair = { 16583, 16823, 22225, 54, 17904 },
            Innkeeper = { 295, 16602, 16826, 18905, 18251 },
            Banker = { 2455 },
            Auctioneer = {},
            Battlemaster = { 347 },
            ["Flight Master"] = { 352, 16587, 16822 },
            ["Weapon Master"] = { 2704 },
            ["Meeting Stones"] = { 178824 },
        },
        professionTrainers = {
            [333] = { 18753, 18773 }, [129] = { 18991, 18990 }, [164] = { 16583, 16823 },
        },
        classSpecificTownsfolk = {
            PALADIN = { ["Class Trainer"] = { 925, 15280 } },
            HUNTER = { ["Class Trainer"] = {}, ["Stable Master"] = { 6749 } },
            MAGE = { ["Class Trainer"] = {}, ["Portal Trainer"] = { 5958 } },
        },
        factionSpecificTownsfolk = {
            Horde = { Mailbox = { 143981, 143982 }, ["Spirit Healer"] = { 6491 } },
            Alliance = { Mailbox = { 32349 }, ["Spirit Healer"] = { 6491 } },
            Neutral = {},
        },
    }
end

-- The vendor lists Townsfolk.PostBoot builds (Stage 3): already the
-- player's faction's, as Questie's PopulateVendors filters them
local VENDOR_LISTS = {
    Horde = { Reagents = { 3335 }, Food = { 16585 }, Drink = { 16585 }, ["Trade Goods"] = { 989, 20194 },
              Ammo = { 20194 }, Bags = {}, Potions = { 20989 }, Poisons = {} },
    Alliance = { Reagents = {}, Food = { 16826 }, Drink = { 16826 }, ["Trade Goods"] = { 20194 },
                 Ammo = { 20194 }, Bags = {}, Potions = { 20989 }, Poisons = {} },
}

-- ---------------------------------------------------------------------------
-- The surface
-- ---------------------------------------------------------------------------
local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = DeepCopy(x) end
    return out
end

local function Serialise(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = string.format("[%d] = %d", k, t[k]) end
    return "return { " .. table.concat(parts, ", ") .. " }"
end

local FIELDS = {
    Npc = { "name", "subName", "friendlyToFaction", "npcFlags", "spawns", "zoneID", "factionID" },
    Object = { "name", "factionID", "spawns" },
    Item = { "name", "vendors", "npcDrops", "objectDrops" },
}

local function Entity(kindName, rows)
    local e = {}
    local nameIndex
    function e.Get(id, key)
        F.calls[kindName] = (F.calls[kindName] or 0) + 1
        if F.raise and F.raise[key] then error("fake QuestieDB: " .. kindName .. "." .. tostring(key) .. " raised") end
        local row = rows[id]
        if not row then return nil end
        local v = row[key]
        if key == "npcFlags" and v == nil then return 0 end
        return DeepCopy(v)
    end
    function e.Exists(id) return rows[id] ~= nil end
    function e.GetAllIds()
        local ids = {}
        for id in pairs(rows) do ids[#ids + 1] = id end
        table.sort(ids)
        return ids
    end
    function e.BuildNameIndex()
        if nameIndex then return end
        F.nameBuilds[kindName] = (F.nameBuilds[kindName] or 0) + 1
        nameIndex = {}
        for _, id in ipairs(e.GetAllIds()) do
            local n = rows[id].name
            if n then
                nameIndex[n] = nameIndex[n] or {}
                local b = nameIndex[n]
                b[#b + 1] = id
            end
        end
    end
    function e.IdsByName(name)
        if type(name) ~= "string" then return nil end
        e.BuildNameIndex()
        return nameIndex[name]
    end
    for _, f in ipairs(FIELDS[kindName]) do
        e[f] = function(id) return e.Get(id, f) end
    end
    return e
end

function F.Install(opts)
    opts = opts or {}
    F.calls, F.nameBuilds, F.raise = {}, {}, nil
    F.readyCallbacks = {}
    F.opts = opts
    local stage = opts.stage or 1
    if opts.questieDB ~= false then
        local contract = opts.contract or 2
        local lib = {
            contractVersion = contract, minSupportedContract = opts.contract and contract or 1,
            readMode = "baked",
        }
        function lib.RequireContract(required)
            if type(required) == "number" and required >= lib.minSupportedContract and required <= lib.contractVersion then
                return true
            end
            return false, "QuestieDB contract mismatch: this consumer needs version " .. tostring(required)
        end
        lib.Npc, lib.Object, lib.Item = Entity("Npc", F.NPCS), Entity("Object", F.OBJECTS), Entity("Item", F.ITEMS)
        if opts.support ~= false then
            local zone = { private = {
                areaIdToUiMapId = Serialise(F.AREAS),
                areaIdToUiMapIdOverride = "return { [2257] = 0 }",
                subZoneToParentZone = Serialise(F.PARENTS),
                subZoneToParentZoneOverride = "return {}",
                dungeons = DeepCopy(F.DUNGEONS),
            } }
            lib.Support = { Get = function(name) if name == "ZoneDB" then return zone end return nil end }
        end
        rawset(_G, "LibQuestieDB", lib)
        rawset(_G, "NpcDB", lib.Npc)
        rawset(_G, "ObjectDB", lib.Object)
        rawset(_G, "ItemDB", lib.Item)
    end
    if opts.questie == false then return F end

    local lists = TownsfolkLists()
    local T = {
        townsfolk = {}, professionTrainers = {}, classSpecificTownsfolk = {}, factionSpecificTownsfolk = {},
        petFoodVendorTypes = {},
    }
    if stage >= 1 then
        for k, v in pairs(lists) do T[k] = v end
    end
    if opts.brokenTownsfolk then T.townsfolk = "broken" end
    F.initialised = stage >= 1
    local Z = {}
    function Z:GetUiMapIdByAreaId(areaId)
        if not F.initialised then error("attempt to index upvalue 'areaIdToUiMapId' (a nil value)") end
        local v = F.AREAS[areaId]
        if v == nil and F.onMissingArea then F.onMissingArea(areaId) end
        return v
    end
    function Z:GetParentZoneId(areaId) return F.PARENTS[areaId] end
    function Z:GetDungeonLocation(areaId)
        local d = F.DUNGEONS[areaId]
        return d and DeepCopy(d[4]) or nil
    end
    local corrections = { questNPCBlacklist = opts.blacklist or {} }
    rawset(_G, "QuestieLoader", { _modules = {
        Townsfolk = T, ZoneDB = Z, QuestieCorrections = corrections,
        QuestieDB = { npcFlags = { VENDOR = 128, REPAIR = 4096 } },
    } })
    local api = { isReady = false }
    function api.RegisterOnReady(fn)
        if type(fn) ~= "function" then error("callback must be a function") end
        if api.isReady then
            local ok, err = pcall(fn)
            if not ok then F.readyErrors = (F.readyErrors or 0) + 1 end
            return
        end
        F.readyCallbacks[#F.readyCallbacks + 1] = fn
    end
    rawset(_G, "Questie", { API = api, db = { char = { townsfolk = {}, vendorList = {} } } })
    F.T, F.Z = T, Z
    if stage >= 3 then F.Stage3(true) end
    return F
end

-- QuestieInit's Stage 1: ZoneDB initialised, the Townsfolk lists built
function F.Stage1()
    for k, v in pairs(TownsfolkLists()) do F.T[k] = v end
    F.initialised = true
end

-- Townsfolk.PostBoot and the end of QuestieInit's Stage 3
function F.Stage3(quiet)
    local faction = (F.opts and F.opts.faction) or (UnitFactionGroup and UnitFactionGroup("player")) or "Horde"
    Questie.db.char.vendorList = DeepCopy(VENDOR_LISTS[faction] or VENDOR_LISTS.Horde)
    Questie.API.isReady = true
    local list = F.readyCallbacks or {}
    F.readyCallbacks = {}
    for _, fn in ipairs(list) do
        local ok = pcall(fn)
        if not ok then F.readyErrors = (F.readyErrors or 0) + 1 end
    end
    return quiet
end

return F
