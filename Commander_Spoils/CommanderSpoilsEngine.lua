-- Commander Spoils — the engine. Models only; this file creates no visible
-- frames and knows nothing about layout.
--
-- Two ledgers, one reconciler (DECISIONS D6). Chat is the event stream and
-- carries attribution; bags are the balance sheet and are the only thing that
-- sees removals. Neither is discarded in favour of the other.

CommanderSpoilsEngine = {}
local E = CommanderSpoilsEngine

local EV = COMMANDER_SPOILS_EVENTS

local floor, min, max, format = math.floor, math.min, math.max, string.format
local tinsert, tremove, wipe = table.insert, table.remove, table.wipe or function(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

local function Now() return time() end

-- ===========================================================================
-- 1. Item classification
--
-- Buckets key off the (classID, subClassID) INTEGER pair, never the type
-- string (D8). Armor/Cloth is 4/1 and Tradegoods/Cloth is 7/5, and both
-- report the string "Cloth" — a name-keyed classifier files robes as
-- crafting materials and the bug is invisible until someone farms humanoids.
-- ===========================================================================

-- Display order is the order these appear in the BAGS and HAUL panes.
E.Buckets = {
    { key = "JUNK",        label = "Junk" },
    { key = "CLOTH",       label = "Cloth" },
    { key = "LEATHER",     label = "Leather" },
    { key = "ORE",         label = "Metal & Stone" },
    { key = "HERB",        label = "Herbs" },
    { key = "ELEMENTAL",   label = "Elemental" },
    { key = "ENCHANTING",  label = "Enchanting" },
    { key = "GEM",         label = "Gems" },
    { key = "TRADEGOOD",   label = "Trade Goods" },
    { key = "CONSUMABLE",  label = "Consumables" },
    { key = "REAGENT",     label = "Reagents" },
    { key = "RECIPE",      label = "Recipes" },
    { key = "GEAR",        label = "Equipment" },
    { key = "PROJECTILE",  label = "Ammunition" },
    { key = "CONTAINER",   label = "Containers" },
    { key = "QUEST",       label = "Quest" },
    { key = "KEY",         label = "Keys" },
    { key = "OTHER",       label = "Other" },
}
E.BucketIndex = {}
for i, entry in ipairs(E.Buckets) do
    E.BucketIndex[entry.key] = i
    entry.index = i
end

-- Trade goods subclasses. This client ships no Enum.ItemTradegoodsSubclass,
-- so the mapping is spelled out. `/cspoils size` prints the client's own
-- names for these ids so the table can be checked in one login.
local TRADE_BUCKET = {
    [1]  = "TRADEGOOD",   -- Parts
    [2]  = "TRADEGOOD",   -- Explosives
    [3]  = "TRADEGOOD",   -- Devices
    [4]  = "GEM",         -- Jewelcrafting
    [5]  = "CLOTH",
    [6]  = "LEATHER",
    [7]  = "ORE",         -- Metal & Stone
    [8]  = "TRADEGOOD",   -- Meat
    [9]  = "HERB",
    [10] = "ELEMENTAL",   -- Motes AND Primals; no honest way to split them
    [12] = "ENCHANTING",
}

function E.BucketOf(classID, subClassID, quality)
    if classID == 15 then
        if subClassID == 0 then return "JUNK" end
        if subClassID == 1 then return "REAGENT" end
        return "OTHER"
    elseif classID == 7 then
        return TRADE_BUCKET[subClassID] or "TRADEGOOD"
    elseif classID == 0 then
        return "CONSUMABLE"
    elseif classID == 2 or classID == 4 then
        return "GEAR"
    elseif classID == 3 then
        return "GEM"
    elseif classID == 5 then
        return "REAGENT"
    elseif classID == 6 then
        return "PROJECTILE"
    elseif classID == 8 then
        return "ENCHANTING"     -- item enhancement (permanent enchants)
    elseif classID == 9 then
        return "RECIPE"
    elseif classID == 1 or classID == 11 then
        return "CONTAINER"
    elseif classID == 12 then
        return "QUEST"
    elseif classID == 13 then
        return "KEY"
    end
    if quality == 0 then return "JUNK" end
    return "OTHER"
end

-- Armor proficiency. Named honestly: this answers "does this armor match my
-- class's armor type", not "can I use this", because weapon usability is not
-- cleanly derivable here and a filter that overclaims is worse than one that
-- states its limit.
local ARMOR_BY_CLASS = {
    WARRIOR = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [6] = true },
    PALADIN = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [6] = true, [7] = true },
    HUNTER  = { [0] = true, [1] = true, [2] = true, [3] = true },
    ROGUE   = { [0] = true, [1] = true, [2] = true },
    PRIEST  = { [0] = true, [1] = true },
    SHAMAN  = { [0] = true, [1] = true, [2] = true, [3] = true, [6] = true, [9] = true },
    MAGE    = { [0] = true, [1] = true },
    WARLOCK = { [0] = true, [1] = true },
    DRUID   = { [0] = true, [1] = true, [2] = true, [8] = true },
}

local playerClass
function E.IsMyArmor(classID, subClassID)
    if classID ~= 4 then return false end
    if not playerClass then
        local _, token = UnitClass("player")
        playerClass = token or "UNKNOWN"
    end
    local set = ARMOR_BY_CLASS[playerClass]
    return set and set[subClassID] or false
end

-- ---------------------------------------------------------------------------
-- Item metadata cache. GetItemInfoInstant is synchronous and never nil for a
-- real itemID; GetItemInfo is async and its sellPrice arrives later. nil and 0
-- are DIFFERENT facts — nil means retry, 0 means genuinely unsellable — and
-- conflating them silently zeroes every value total.
-- ---------------------------------------------------------------------------
local meta = {}          -- [itemID] = { name, icon, classID, subClassID, quality,
                         --              sellPrice (nil = unknown), stack, bind, bucket, link }
local pendingInfo = {}   -- [itemID] = true while we are waiting on the server

local function ItemInfoInstant(itemID)
    if C_Item and C_Item.GetItemInfoInstant then return C_Item.GetItemInfoInstant(itemID) end
    if _G.GetItemInfoInstant then return _G.GetItemInfoInstant(itemID) end
end

local function ItemInfo(itemID)
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(itemID) end
    if _G.GetItemInfo then return _G.GetItemInfo(itemID) end
end

function E.Meta(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    local entry = meta[itemID]
    if not entry then
        local _, _, _, equipLoc, icon, classID, subClassID = ItemInfoInstant(itemID)
        if not classID then return nil end
        entry = {
            icon = icon, classID = classID, subClassID = subClassID,
            equipLoc = equipLoc,
        }
        entry.bucket = E.BucketOf(classID, subClassID, nil)
        meta[itemID] = entry
    end
    -- Back off between retries: this runs per row per paint, and hammering
    -- GetItemInfo for an item the server has not sent yet buys nothing. The
    -- real refresh arrives on GET_ITEM_INFO_RECEIVED.
    local nowTick = GetTime and GetTime() or 0
    if (entry.sellPrice == nil or entry.name == nil)
        and (not entry.probedAt or (nowTick - entry.probedAt) > 0.5) then
        entry.probedAt = nowTick
        local name, link, quality, _, _, _, _, stack, _, _, sellPrice, _, _, bind = ItemInfo(itemID)
        if name then
            entry.name, entry.link, entry.quality = name, link, quality
            entry.stack, entry.sellPrice, entry.bind = stack or 1, sellPrice or 0, bind
            entry.bucket = E.BucketOf(entry.classID, entry.subClassID, quality)
            pendingInfo[itemID] = nil
        elseif not pendingInfo[itemID] then
            pendingInfo[itemID] = true
            if C_Item and C_Item.RequestLoadItemDataByID then
                pcall(C_Item.RequestLoadItemDataByID, itemID)
            end
        end
    end
    return entry
end

-- ===========================================================================
-- 2. Value — three tiers, never blended (D13)
-- ===========================================================================
local auctionCache = {}   -- [itemID] = { value, ageDays, at }
local AUCTION_TTL = 300
local auctionOK = nil     -- nil = unprobed, false = unavailable

-- Auctionator returns nil until its own database initializes, so a probe that
-- latched `false` on the first miss killed MARKET mode for the session (D13
-- specifies the re-arm). A failure now only backs off, and a DB update clears
-- the backoff outright.
local auctionRetryAt = 0
local AUCTION_BACKOFF = 60

local function AuctionAPI()
    local api = _G.Auctionator and _G.Auctionator.API and _G.Auctionator.API.v1
    if not api or not api.GetAuctionPriceByItemID then return nil end
    if auctionOK == false and (GetTime and GetTime() or 0) < auctionRetryAt then
        return nil
    end
    if not E.auctionHooked and api.RegisterForDBUpdate then
        E.auctionHooked = true
        pcall(api.RegisterForDBUpdate, "Commander_Spoils", function()
            auctionOK, auctionRetryAt = nil, 0
            wipe(auctionCache)
            E.foldSerial = E.foldSerial + 1
        end)
    end
    return api
end

local function AuctionMissed()
    auctionOK = false
    auctionRetryAt = (GetTime and GetTime() or 0) + AUCTION_BACKOFF
end

-- Auctionator error()s on a bad caller id and returns nil until its own
-- database initializes, so every call is pcall'd and the probe is lazy rather
-- than one-shot at login.
function E.MarketValue(itemID)
    local api = AuctionAPI()
    if not api then return nil end
    local cached = auctionCache[itemID]
    local now = GetTime and GetTime() or 0
    if cached and (now - cached.at) < AUCTION_TTL then
        return cached.value, cached.ageDays
    end
    local ok, value = pcall(api.GetAuctionPriceByItemID, "Commander_Spoils", itemID)
    if not ok then
        AuctionMissed()
        return nil
    end
    if value == nil then AuctionMissed() end
    local age
    if value and api.GetAuctionAgeByItemID then
        local okAge, days = pcall(api.GetAuctionAgeByItemID, "Commander_Spoils", itemID)
        if okAge then age = days end
    end
    auctionCache[itemID] = { value = value, ageDays = age, at = now }
    return value, age
end

-- Returns copper, tier ("VENDOR"|"MARKET"), staleDays. A nil value is an
-- em-dash on screen, never a zero.
function E.UnitValue(itemID)
    local entry = E.Meta(itemID)
    local vendor = entry and entry.sellPrice
    if CommanderSpoilsDB.ValueMode == "MARKET" then
        local market, age = E.MarketValue(itemID)
        if market and market > 0 then
            -- An item worth less on the auction house than at a vendor is
            -- worth its vendor price.
            if vendor and vendor > market then return vendor, "VENDOR", nil end
            return market, "MARKET", age
        end
    end
    if vendor and vendor > 0 then return vendor, "VENDOR", nil end
    if vendor == 0 then return 0, "VENDOR", nil end
    return nil, nil, nil
end

-- ===========================================================================
-- 3. Chat format strings → Lua patterns
--
-- Specifiers are marked with a sentinel BEFORE magic characters are escaped,
-- which is what makes the |HlootHistory:%d|h[Loot]|h: prefix and the
-- positional %1$s forms used by deDE/frFR/ruRU both work.
-- ===========================================================================
local SENTINEL = "\1"

local function ToPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local kinds = {}
    local marked = fmt:gsub("%%(%d?)%$?([sd])", function(index, kind)
        kinds[#kinds + 1] = { kind = kind, index = tonumber(index) }
        return SENTINEL
    end)
    marked = marked:gsub("([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1")
    local i = 0
    local pattern = marked:gsub(SENTINEL, function()
        i = i + 1
        return kinds[i].kind == "d" and "(%-?%d+)" or "(.-)"
    end)
    return "^" .. pattern .. "$", kinds
end
E.ToPattern = ToPattern

-- Matchers are tried longest-format-first: LOOT_ITEM_SELF_MULTIPLE must beat
-- LOOT_ITEM_SELF, or the shorter pattern swallows the longer message.
local function BuildMatchers(specs)
    local built = {}
    for _, spec in ipairs(specs) do
        local fmt = _G[spec.global]
        local pattern, kinds = ToPattern(fmt)
        if pattern then
            built[#built + 1] = {
                pattern = pattern, kinds = kinds, len = #fmt,
                fields = spec.fields, kind = spec.kind, self = spec.self,
                type = spec.type,
            }
        end
    end
    table.sort(built, function(a, b) return a.len > b.len end)
    return built
end

-- fields lists what each capture MEANS, in the order the captures appear.
local LOOT_SPECS = {
    { global = "LOOT_ITEM_SELF_MULTIPLE",        fields = { "item", "count" }, kind = "loot",    self = true },
    { global = "LOOT_ITEM_SELF",                 fields = { "item" },          kind = "loot",    self = true },
    { global = "LOOT_ITEM_PUSHED_SELF_MULTIPLE", fields = { "item", "count" }, kind = "pushed",  self = true },
    { global = "LOOT_ITEM_PUSHED_SELF",          fields = { "item" },          kind = "pushed",  self = true },
    { global = "LOOT_ITEM_CREATED_SELF_MULTIPLE",fields = { "item", "count" }, kind = "created", self = true },
    { global = "LOOT_ITEM_CREATED_SELF",         fields = { "item" },          kind = "created", self = true },
    { global = "LOOT_ITEM_MULTIPLE",             fields = { "who", "item", "count" }, kind = "loot" },
    { global = "LOOT_ITEM",                      fields = { "who", "item" },   kind = "loot" },
    { global = "LOOT_ITEM_PUSHED_MULTIPLE",      fields = { "who", "item", "count" }, kind = "pushed" },
    { global = "LOOT_ITEM_PUSHED",               fields = { "who", "item" },   kind = "pushed" },
    { global = "CREATED_ITEM_MULTIPLE",          fields = { "who", "item", "count" }, kind = "created" },
    { global = "CREATED_ITEM",                   fields = { "who", "item" },   kind = "created" },
}

local MONEY_SPECS = {
    { global = "LOOT_MONEY_SPLIT_GUILD", fields = { "money", "guild" }, kind = "split" },
    { global = "LOOT_MONEY_SPLIT",       fields = { "money" },          kind = "split" },
    { global = "YOU_LOOT_MONEY_GUILD",   fields = { "money", "guild" }, kind = "solo"  },
    { global = "YOU_LOOT_MONEY",         fields = { "money" },          kind = "solo"  },
}

local CURRENCY_SPECS = {
    { global = "CURRENCY_GAINED_MULTIPLE_BONUS", fields = { "item", "count" }, kind = "currency", self = true },
    { global = "CURRENCY_GAINED_MULTIPLE",       fields = { "item", "count" }, kind = "currency", self = true },
    { global = "CURRENCY_GAINED",                fields = { "item" },          kind = "currency", self = true },
}

-- Roll chat is the shadow ledger behind C_LootHistory (D:§2.5): the server
-- expires history entries, and because our chat filter only stops DISPLAY, the
-- events still reach us for free.
local ROLL_SPECS = {
    { global = "LOOT_ROLL_ROLLED_NEED",  fields = { "hist", "roll", "item", "who" }, kind = "rolled", type = 1 },
    { global = "LOOT_ROLL_ROLLED_GREED", fields = { "hist", "roll", "item", "who" }, kind = "rolled", type = 2 },
    { global = "LOOT_ROLL_YOU_WON",      fields = { "hist", "item" },                kind = "won", self = true },
    { global = "LOOT_ROLL_WON",          fields = { "hist", "who", "item" },         kind = "won" },
    { global = "LOOT_ROLL_ALL_PASSED",   fields = { "hist", "item" },                kind = "allpassed" },
    { global = "LOOT_ROLL_PASSED_SELF",  fields = { "hist", "item" },                kind = "choice", type = 0, self = true },
    { global = "LOOT_ROLL_PASSED",       fields = { "hist", "who", "item" },         kind = "choice", type = 0 },
    { global = "LOOT_ROLL_NEED_SELF",    fields = { "hist", "item" },                kind = "choice", type = 1, self = true },
    { global = "LOOT_ROLL_NEED",         fields = { "hist", "who", "item" },         kind = "choice", type = 1 },
    { global = "LOOT_ROLL_GREED_SELF",   fields = { "hist", "item" },                kind = "choice", type = 2, self = true },
    { global = "LOOT_ROLL_GREED",        fields = { "hist", "who", "item" },         kind = "choice", type = 2 },
}

local lootMatchers, moneyMatchers, currencyMatchers, rollMatchers

-- Also recycled, and also exported (E.Match): a caller must read the captures
-- before calling Match again. Every call site in this file does.
local scratchCaps = {}
local function Match(matchers, message)
    for _, m in ipairs(matchers) do
        local a, b, c, d = message:match(m.pattern)
        if a ~= nil then
            wipe(scratchCaps)
            local caps = { a, b, c, d }
            for i, field in ipairs(m.fields) do
                scratchCaps[field] = caps[i]
            end
            return m, scratchCaps
        end
    end
    return nil
end
E.Match = Match

-- Coin text ("1 Gold 20 Silver 5 Copper") → copper.
local goldPat, silverPat, copperPat
local function AmountPattern(fmt, fallback)
    local s = (type(fmt) == "string") and fmt or fallback
    s = s:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    s = s:gsub("%%d", "(%%d+)")
    return s
end

function E.ParseMoney(text)
    if type(text) ~= "string" then return 0 end
    goldPat   = goldPat   or AmountPattern(_G.GOLD_AMOUNT,   "%d Gold")
    silverPat = silverPat or AmountPattern(_G.SILVER_AMOUNT, "%d Silver")
    copperPat = copperPat or AmountPattern(_G.COPPER_AMOUNT, "%d Copper")
    local gold   = tonumber(text:match(goldPat))   or 0
    local silver = tonumber(text:match(silverPat)) or 0
    local copper = tonumber(text:match(copperPat)) or 0
    return gold * 10000 + silver * 100 + copper
end

-- ===========================================================================
-- 4. Persistence — positional rows (D12)
--
-- SavedVariables is serialized as Lua source, so key names are repeated on
-- every row and dominate the file. A named row costs ~200 bytes; the same row
-- positional costs ~55. Field order is fixed by this comment and nothing else:
--
--   events[i] = { t, itemID, count, quality, bucketIdx, unitValue,
--                 srcKind, srcID, mapID, segID }
--
-- srcKind: 1 looted · 2 pushed · 3 created · 4 other/reconciled · 5 currency
-- ===========================================================================
local DATA_VERSION = 1
local LIMITS = {
    events   = 2000,
    segments = 200,
    rolls    = 400,
    rollFull = 100,    -- newest N rolls keep their per-player detail
    lifetime = 1200,
    money    = 400,
    sources  = 300,
}
E.Limits = LIMITS

local SRC_LOOTED, SRC_PUSHED, SRC_CREATED, SRC_OTHER, SRC_CURRENCY = 1, 2, 3, 4, 5
E.SrcKind = { LOOTED = SRC_LOOTED, PUSHED = SRC_PUSHED, CREATED = SRC_CREATED,
              OTHER = SRC_OTHER, CURRENCY = SRC_CURRENCY }

local Data

-- Declared here rather than in §5 because E.Wipe below has to reset them, and
-- a local declared after a function body is not in that function's scope — it
-- would silently resolve to a nil global instead.
local segments = {}    -- live: [scope] = { id, kind, label, startEpoch, fromIdx, mapID }
E.Segments = segments

local function FreshData()
    return {
        v = DATA_VERSION,
        events = {}, segments = {}, rolls = {}, lifetime = {},
        names = {}, zones = {}, drops = {}, kills = {},
        money = { looted = 0, log = {} },
        nextSeg = 1,
    }
end

function E.Wipe(quiet)
    CommanderSpoilsData = FreshData()
    Data = CommanderSpoilsData
    E.Data = Data          -- the UI reads through E.Data; a stale pointer here
                           -- would show the old log while new rows go elsewhere
    E.foldSerial = E.foldSerial + 1
    for _, seg in pairs(segments) do
        seg.fromIdx, seg.toIdx = 1, nil
    end
    -- The persisted ranges have to move too, or a /reload inside the resume
    -- window (or a relog with a farm running) folds an empty log from index 21.
    for _, key in ipairs({ "Session", "Farm" }) do
        local block = CommanderSpoilsDB[key]
        if type(block) == "table" and block.fromIdx then block.fromIdx = 1 end
    end
    for name in pairs(E.Party) do E.Party[name] = nil end
    for i = #E.Feed, 1, -1 do E.Feed[i] = nil end
    -- The trailing-rate ring outlives the ledger otherwise, and the status line
    -- reports income per hour over an empty log. (Defined below this function,
    -- so it is reached through E rather than as an upvalue.)
    if E.ResetRates then E.ResetRates() end
    if not quiet then
        print("|cff66ccffCommander Spoils|r: history wiped (settings untouched)")
    end
    Commander.Notify(EV.UPDATE)
end

-- Migration policy is deliberate: stamp the version and wipe on mismatch.
-- Writing migration code for a personal addon's telemetry buys a bug surface
-- against data that is not precious enough to justify it (D12).
local function LoadData()
    Data = CommanderSpoilsData
    if type(Data) ~= "table" or Data.v ~= DATA_VERSION then
        local had = type(Data) == "table" and Data.events and #Data.events or 0
        CommanderSpoilsData = FreshData()
        Data = CommanderSpoilsData
        if had > 0 then
            print("|cff66ccffCommander Spoils|r: history format changed — previous entries cleared")
        end
    end
    for key, value in pairs(FreshData()) do
        if Data[key] == nil then Data[key] = value end
    end
    E.Data = Data
end

local function RingPush(list, row, limit)
    list[#list + 1] = row
    local over = #list - limit
    if over > 0 then
        for _ = 1, over do tremove(list, 1) end
        return over
    end
    return 0
end

-- Prune runs at login (before anything reads) and at logout (so the file
-- written to disk is already trimmed). Never on a ticker.
--
-- Front-truncating the event log MOVES every index, so anything holding an
-- index range has to move with it — including the farm block, which is
-- deliberately persisted outside the session and can outlive a client restart.
-- Returns the number of events shed from the front.
local function TrimFront(list, drop)
    if drop <= 0 then return 0 end
    if drop >= #list then
        local n = #list
        for i = n, 1, -1 do list[i] = nil end
        return n
    end
    -- One compacting pass: repeated tremove(list, 1) is quadratic, and a
    -- logout that trims 1500 of 2000 rows would move a million elements.
    local n = #list
    for i = 1, n - drop do list[i] = list[i + drop] end
    for i = n - drop + 1, n do list[i] = nil end
    return drop
end

local function AgeDrop(list, cutoff, stamp)
    local drop = 0
    for i = 1, #list do
        if (stamp(list[i]) or 0) >= cutoff then break end
        drop = i
    end
    return drop
end

function E.Prune()
    if not Data then return 0 end
    local cutoff = Now() - (CommanderSpoilsDB.HistoryDays or 60) * 86400

    local shed = TrimFront(Data.events, AgeDrop(Data.events, cutoff, function(row) return row[1] end))
    shed = shed + TrimFront(Data.events, math.max(0, #Data.events - LIMITS.events))
    TrimFront(Data.segments, AgeDrop(Data.segments, cutoff, function(row) return row.t end))
    TrimFront(Data.segments, math.max(0, #Data.segments - LIMITS.segments))
    TrimFront(Data.rolls, AgeDrop(Data.rolls, cutoff, function(row) return row.t end))
    TrimFront(Data.rolls, math.max(0, #Data.rolls - LIMITS.rolls))
    TrimFront(Data.money.log, AgeDrop(Data.money.log, cutoff, function(row) return row[1] end))
    TrimFront(Data.money.log, math.max(0, #Data.money.log - LIMITS.money))

    if shed > 0 then E.RebaseIndices(shed) end

    -- Per-player roll detail is the expensive part; only the newest keep it.
    for i = 1, #Data.rolls - LIMITS.rollFull do
        if Data.rolls[i] then Data.rolls[i].p = nil end
    end

    local function CapMap(map, limit)
        local count = 0
        for _ in pairs(map) do count = count + 1 end
        if count <= limit then return end
        -- Evict the least-seen by doubling the threshold rather than sorting
        -- the whole table.
        local excess, threshold = count - limit, 1
        while excess > 0 and threshold < 1e6 do
            for key, row in pairs(map) do
                local weight = type(row) == "table" and (row[1] or 0) or row
                if weight <= threshold and excess > 0 then
                    map[key] = nil
                    excess = excess - 1
                end
            end
            threshold = threshold * 2
        end
    end
    CapMap(Data.lifetime, LIMITS.lifetime)
    CapMap(Data.kills, LIMITS.sources)
    -- drops/names are keyed by the same creature ids as kills, so they follow it.
    for creatureID in pairs(Data.drops) do
        if not Data.kills[creatureID] then Data.drops[creatureID] = nil end
    end
    for creatureID in pairs(Data.names) do
        if not Data.kills[creatureID] then Data.names[creatureID] = nil end
    end
    return shed
end

-- Every live and persisted index range moves with the log.
function E.RebaseIndices(shed)
    for _, seg in pairs(E.Segments) do
        if seg.fromIdx then seg.fromIdx = math.max(1, seg.fromIdx - shed) end
        if seg.toIdx then seg.toIdx = math.max(0, seg.toIdx - shed) end
    end
    local farm = CommanderSpoilsDB.Farm
    if type(farm) == "table" and farm.fromIdx then
        farm.fromIdx = math.max(1, farm.fromIdx - shed)
    end
    local sess = CommanderSpoilsDB.Session
    if type(sess) == "table" and sess.fromIdx then
        sess.fromIdx = math.max(1, sess.fromIdx - shed)
    end
    E.foldSerial = E.foldSerial + 1
end

-- ===========================================================================
-- 5. Segments — index ranges over one log, never parallel counters (D14)
-- ===========================================================================
local session          -- Commander.RestoreSession block (segments is declared above)

local RUN_EXIT_GRACE = 180   -- Commander_Economy's rule (CommanderEconomy.lua:649),
                             -- duplicated with intent until Economy publishes its
                             -- segment on the bus.

local function NewSegment(kind, label, mapID)
    local id = Data.nextSeg or 1
    Data.nextSeg = id + 1
    return {
        id = id, kind = kind, label = label, mapID = mapID,
        startEpoch = Now(), fromIdx = #Data.events + 1,
    }
end

local function CloseSegment(seg)
    if not seg then return end
    seg.endEpoch = Now()
    seg.toIdx = #Data.events
    if seg.toIdx >= seg.fromIdx then
        local stats = E.Fold(seg)
        RingPush(Data.segments, {
            t = seg.startEpoch, dur = seg.endEpoch - seg.startEpoch,
            kind = seg.kind, label = seg.label, mapID = seg.mapID,
            items = stats.items, value = stats.value, gold = stats.gold,
            best = stats.bestItemID, bestQ = stats.bestQuality,
        }, LIMITS.segments)
        Commander.Notify(EV.SEGMENT, seg)
    end
end

function E.StartFarm(label)
    if segments.FARM then CloseSegment(segments.FARM) end
    segments.FARM = NewSegment("farm", label or "Farm", E.MapID())
    -- The farm block lives outside db.Session on purpose: a farm can span a
    -- client restart and must not die to the 600s session resume window.
    CommanderSpoilsDB.Farm = {
        id = segments.FARM.id, startEpoch = segments.FARM.startEpoch,
        fromIdx = segments.FARM.fromIdx, label = segments.FARM.label,
        mapID = segments.FARM.mapID,
    }
    Commander.Notify(EV.UPDATE)
end

function E.StopFarm()
    if segments.FARM then CloseSegment(segments.FARM) end
    segments.FARM = nil
    CommanderSpoilsDB.Farm = false
    Commander.Notify(EV.UPDATE)
end

function E.FarmActive() return segments.FARM ~= nil end

function E.MapID()
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
        if ok then return id end
    end
    return nil
end

local function ZoneName()
    return (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or "?"
end

-- The instance run segment. An instance key change closes the old run; leaving
-- and returning inside the grace window resumes it rather than splitting the
-- night into fragments.
local runKey, runLeftAt
local function UpdateRun()
    local inInstance, instanceType = IsInInstance()
    local key = false
    if inInstance and instanceType ~= "none" then
        key = ZoneName()
    end
    if key then
        if segments.RUN and runKey == key then
            runLeftAt = nil
            return
        end
        if segments.RUN and runKey ~= key then CloseSegment(segments.RUN) end
        runKey = key
        runLeftAt = nil
        segments.RUN = NewSegment("run", key, E.MapID())
    elseif segments.RUN then
        if not runLeftAt then
            runLeftAt = Now()
        elseif (Now() - runLeftAt) > RUN_EXIT_GRACE then
            CloseSegment(segments.RUN)
            segments.RUN = nil
            runKey, runLeftAt = nil, nil
        end
    end
end

function E.SegmentFor(scope)
    if scope == "RUN" then return segments.RUN end
    if scope == "FARM" then return segments.FARM end
    if scope == "HOUR" then
        -- A synthetic segment: the last hour of the log. Reused rather than
        -- rebuilt so the fold cache can key off it, and its boundary is
        -- recomputed at most once a second — SegmentFor is called more than
        -- once per paint and the scan walks the log.
        local cutoff = Now() - 3600
        local tick = GetTime and GetTime() or 0
        if E.hourSegment and E.hourProbedAt and (tick - E.hourProbedAt) < 1
            and E.hourSegment.toIdx == #Data.events then
            return E.hourSegment
        end
        E.hourProbedAt = tick
        local from = #Data.events + 1
        for i = #Data.events, 1, -1 do
            if Data.events[i][1] < cutoff then break end
            from = i
        end
        local hour = E.hourSegment
        if not hour then
            hour = { id = -1, kind = "hour", label = "Last hour" }
            E.hourSegment = hour
        end
        hour.fromIdx, hour.toIdx, hour.startEpoch = from, #Data.events, cutoff
        return hour
    end
    return segments.SESSION
end

-- ---------------------------------------------------------------------------
-- Fold: every segment statistic is computed here, in one pass, and cached.
-- Zero duplicated counters means there is no counter-sync bug to have.
-- ---------------------------------------------------------------------------
-- Every segment statistic is computed here, in one pass, and cached. Zero
-- duplicated counters means there is no counter-sync bug to have.
--
-- The sub-tables are recycled explicitly rather than through `x = x or {}`
-- after a wipe — wipe() nils them, so the `or` could never hit and the
-- "cache" allocated three fresh tables plus one per bucket and one per item on
-- every 0.5s repaint.
local foldCache = setmetatable({}, { __mode = "k" })
E.foldSerial = 0

local function FoldGold(seg)
    local from = seg.startEpoch or 0
    local to = seg.endEpoch
    local total = 0
    local log = Data.money.log
    for i = #log, 1, -1 do
        local stamp = log[i][1]
        if stamp < from then break end
        if not to or stamp <= to then total = total + log[i][2] end
    end
    return total
end

function E.Fold(seg)
    if not seg then return E.EmptyFold end
    local from = seg.fromIdx or 1
    local to = seg.toIdx or #Data.events
    local stats = foldCache[seg]
    if stats and stats.serial == E.foldSerial and stats.to == to and stats.from == from then
        return stats
    end
    if not stats then
        stats = { byQuality = {}, byBucket = {}, byItem = {},
                  itemRows = {}, bucketRows = {} }
        foldCache[seg] = stats
    end
    wipe(stats.byBucket)
    wipe(stats.byItem)
    stats.serial, stats.from, stats.to = E.foldSerial, from, to
    stats.items, stats.value, stats.otherValue = 0, 0, 0
    for q = 0, 5 do stats.byQuality[q] = 0 end
    stats.bestQuality, stats.bestItemID, stats.bestValue = -1, nil, 0

    local itemRows, bucketRows = stats.itemRows, stats.bucketRows
    local events = Data.events

    for i = from, to do
        local row = events[i]
        if row then
            local itemID, count, quality = row[2], row[3], row[4]
            local bucketIdx, unit, srcKind = row[5], row[6], row[7]
            local rowValue = (unit or 0) * count
            -- Reconciled acquisitions are logged and browsable, but they are
            -- not income and must never inflate the headline or the rate.
            local income = srcKind ~= SRC_OTHER
            if income then
                stats.items = stats.items + count
                stats.value = stats.value + rowValue
                if quality and quality >= 0 and quality <= 5 then
                    stats.byQuality[quality] = stats.byQuality[quality] + count
                end
            else
                stats.otherValue = stats.otherValue + rowValue
            end

            local bucket = stats.byBucket[bucketIdx]
            if not bucket then
                bucket = bucketRows[bucketIdx]
                if not bucket then bucket = {}; bucketRows[bucketIdx] = bucket end
                bucket.stacks, bucket.items, bucket.value, bucket.bucket = 0, 0, 0, bucketIdx
                stats.byBucket[bucketIdx] = bucket
            end
            bucket.stacks = bucket.stacks + 1
            bucket.items = bucket.items + count
            bucket.value = bucket.value + rowValue

            local item = stats.byItem[itemID]
            if not item then
                item = itemRows[itemID]
                if not item then item = {}; itemRows[itemID] = item end
                item.itemID, item.count, item.value = itemID, 0, 0
                item.quality, item.bucket = quality, bucketIdx
                item.other, item.mixed = not income, false
                stats.byItem[itemID] = item
            end
            item.count = item.count + count
            item.value = item.value + rowValue
            -- An item can arrive both ways. `other` means "none of this was
            -- income"; anything mixed is shown as income and flagged.
            if item.other and income then item.other, item.mixed = false, true
            elseif not item.other and not income then item.mixed = true end
            if quality and (item.quality == nil or quality > item.quality) then
                item.quality = quality
            end

            if income and ((quality or 0) > stats.bestQuality
                or ((quality or 0) == stats.bestQuality and rowValue > stats.bestValue)) then
                stats.bestQuality, stats.bestItemID, stats.bestValue = quality or 0, itemID, rowValue
            end
        end
    end
    stats.gold = FoldGold(seg)
    -- Market coverage: the share of value we could actually price at market.
    -- D13 calls this the entire credibility of the MARKET number, and a bare
    -- "MARKET 312g" over a 60%-priced haul is the lie it exists to prevent.
    -- Coverage walks every distinct item and pcalls into Auctionator for each,
    -- while a loot burst refolds on every record. Recompute at most 1 Hz.
    local tick = GetTime and GetTime() or 0
    if CommanderSpoilsDB.ValueMode ~= "MARKET" then
        stats.coverage, stats.stalestDays, stats.coverageAt = nil, nil, nil
    elseif stats.coverageAt and (tick - stats.coverageAt) < 1 then
        -- keep the cached coverage
    else
        stats.coverageAt = tick
        local priced, total, stalest = 0, 0, nil
        for itemID, item in pairs(stats.byItem) do
            -- By VALUE, and over the same population the headline uses:
            -- reconciled arrivals are excluded from both.
            if not item.other then
                total = total + item.value
                local _, tier, age = E.UnitValue(itemID)
                if tier == "MARKET" then
                    priced = priced + item.value
                    if age and (not stalest or age > stalest) then stalest = age end
                end
            end
        end
        stats.coverage = total > 0 and (priced / total) or nil
        stats.stalestDays = stalest
    end
    return stats
end
E.EmptyFold = { items = 0, value = 0, gold = 0, otherValue = 0,
                byQuality = { [0]=0,[1]=0,[2]=0,[3]=0,[4]=0,[5]=0 },
                byBucket = {}, byItem = {}, bestQuality = -1 }

-- ---------------------------------------------------------------------------
-- Live rate: a 5-minute trailing window off a 60-slot per-minute ring.
-- "Since session start" lags reality badly forty minutes in, and the gap
-- between the trailing rate and the session average is itself information.
-- ---------------------------------------------------------------------------
local rateRing = {}
for i = 1, 60 do rateRing[i] = { minute = -1, value = 0, items = 0 } end

function E.ResetRates()
    for i = 1, 60 do
        rateRing[i].minute, rateRing[i].value, rateRing[i].items = -1, 0, 0
    end
end

local function RateSlot()
    local minute = floor(Now() / 60)
    local slot = rateRing[(minute % 60) + 1]
    if slot.minute ~= minute then
        slot.minute, slot.value, slot.items = minute, 0, 0
    end
    return slot
end

function E.TrailingRate(minutes)
    minutes = minutes or 5
    local nowMinute = floor(Now() / 60)
    local value, items, counted = 0, 0, 0
    for i = 1, 60 do
        local slot = rateRing[i]
        if slot.minute >= 0 and (nowMinute - slot.minute) < minutes then
            value = value + slot.value
            items = items + slot.items
            counted = counted + 1
        end
    end
    local span = max(1, min(minutes, counted))
    return value * 60 / span, items * 60 / span
end

-- ===========================================================================
-- 6. The loot stream
-- ===========================================================================
-- Reconciler context lives up here because §6 writes it and §7 reads it, and a
-- local declared after a function body is a nil global to that body.
local context = { merchant = false, trade = false, mail = false, bank = false }
E.context = context
local questTurnedIn, createdThisTick = false, false
E.Feed = {}          -- newest first; display objects, capped
local FEED_MAX = 300
local feedSerial = 0

-- The published entry table is POOLED AND RECYCLED. Commander.Notify is a
-- synchronous in-process fanout, so a subscriber may read this inside its
-- callback but MUST NOT retain it. Three modules subscribe to this event; a
-- shared mutable table across a pcall'd fanout is exactly the bug that takes a
-- week to find.
-- Two slots, alternating: E.Record is reachable from inside a Notify fanout
-- (a subscriber that triggers a settle re-enters it), and a single shared table
-- would be wiped underneath the outer dispatch's remaining subscribers.
local publishPool = { {}, {} }
local publishSlot = 0
local function NextPublishEntry()
    publishSlot = publishSlot % #publishPool + 1
    return wipe(publishPool[publishSlot])
end

local currentSource = nil   -- { name, guid, fishing } while a corpse is open
local slotSources = {}      -- [slotIndex] = guid, when GetLootSourceInfo answers
local slotCredited = {}     -- [sourceGUID] = creatureID already counted as a kill
local sourceInfoOK = nil    -- nil = unprobed

-- Only ever memoize a POSITIVE. Probing an already-autolooted corpse (the
-- common case) returns nothing, and latching that would disable per-slot
-- attribution for the rest of the session.
local function ProbeSourceInfo(hasSlots)
    if sourceInfoOK then return true end
    if sourceInfoOK == false then return false end
    if type(_G.GetLootSourceInfo) ~= "function" then
        sourceInfoOK = false
        return false
    end
    if not hasSlots then return false end
    local ok, first = pcall(_G.GetLootSourceInfo, 1)
    if ok and type(first) == "string" then
        sourceInfoOK = true
        return true
    end
    return false
end

local function CreatureIDFromGUID(guid)
    if type(guid) ~= "string" then return nil end
    local id = select(6, strsplit("-", guid))
    return tonumber(id)
end

local function InternName(id, name)
    if id and name and not Data.names[id] then Data.names[id] = name end
end

local function InternZone(mapID, name)
    if mapID and name and not Data.zones[mapID] then Data.zones[mapID] = name end
end

local function FeedPush(row)
    feedSerial = feedSerial + 1
    row.serial = feedSerial
    tinsert(E.Feed, 1, row)
    while #E.Feed > FEED_MAX do tremove(E.Feed) end
end

-- The one place an acquisition is recorded. Everything upstream — chat,
-- reconciler, currency — funnels here.
function E.Record(itemID, count, srcKind, sourceID, sourceName, link)
    itemID = tonumber(itemID)
    if not itemID or not Data then return end
    count = tonumber(count) or 1
    local entry = E.Meta(itemID)
    local quality = entry and entry.quality
    local bucketIdx = E.BucketIndex[(entry and entry.bucket) or "OTHER"] or E.BucketIndex.OTHER
    local unit = E.UnitValue(itemID) or 0
    local mapID = E.MapID()
    InternZone(mapID, ZoneName())
    InternName(sourceID, sourceName)

    local seg = segments.SESSION
    local row = { Now(), itemID, count, quality or 1, bucketIdx, unit,
                  srcKind or SRC_LOOTED, sourceID, mapID, seg and seg.id }
    local shed = RingPush(Data.events, row,
        CommanderSpoilsDB.TrackHistory and LIMITS.events or 400)
    if shed > 0 then E.RebaseIndices(shed) end
    E.foldSerial = E.foldSerial + 1
    E.foldSerial = E.foldSerial + 1

    -- Lifetime counts what you LOOTED. A vendor purchase entering the ledger
    -- must not inflate "lifetime: 400" for an item you bought.
    if srcKind ~= SRC_OTHER then
        local lifetime = Data.lifetime[itemID]
        if not lifetime then
            lifetime = { 0, 0, 0 }
            Data.lifetime[itemID] = lifetime
        end
        lifetime[1] = lifetime[1] + count
        lifetime[2] = lifetime[2] + unit * count
        lifetime[3] = Now()
    end

    if sourceID then
        local drops = Data.drops[sourceID]
        if not drops then drops = {}; Data.drops[sourceID] = drops end
        drops[itemID] = (drops[itemID] or 0) + count
    end

    -- Reconciled acquisitions (a vendor purchase, mail, a quest reward) are
    -- still ours and still belong in the ledger, but they are not INCOME:
    -- counting them would make buying reagents read as a profitable hour.
    if srcKind ~= SRC_OTHER then
        local slot = RateSlot()
        slot.value = slot.value + unit * count
        slot.items = slot.items + count
    end

    FeedPush({
        kind = "item", itemID = itemID, count = count, quality = quality,
        link = link or (entry and entry.link), icon = entry and entry.icon,
        name = entry and entry.name, t = Now(), mine = true,
        srcKind = srcKind or SRC_LOOTED, sourceID = sourceID, sourceName = sourceName,
        value = unit * count, bucket = bucketIdx,
    })

    local publishEntry = NextPublishEntry()
    publishEntry.itemID, publishEntry.count, publishEntry.quality = itemID, count, quality
    publishEntry.link, publishEntry.classID = link, entry and entry.classID
    publishEntry.subClassID = entry and entry.subClassID
    publishEntry.bucket = (entry and entry.bucket) or "OTHER"
    publishEntry.unitValue, publishEntry.source = unit, srcKind or SRC_LOOTED
    publishEntry.sourceID, publishEntry.mapID, publishEntry.t = sourceID, mapID, Now()
    Commander.Notify(EV.LOOT, publishEntry)
    return row
end

-- A group member's pickup. Recorded for the PARTY pane only — it never enters
-- our own ledger, because it is not ours.
-- Keyed to the current group, not to the login. A raider swapping out mid-run
-- must not nuke the pane, but a whole new group is a whole new ledger — the
-- roster signature only changes when the membership actually does.
E.Party = {}   -- [name] = { items, bestItemID, bestQuality, need, greed, pass, won }
E.partyKey = nil

local rosterScratch = {}
local function RosterSignature()
    if not IsInGroup or not IsInGroup() then return "solo" end
    for i = #rosterScratch, 1, -1 do rosterScratch[i] = nil end
    local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    -- GetNumGroupMembers returns the RAID size in a raid, so probing party1..N-1
    -- there means 35 nil probes and a signature covering only your own subgroup.
    local raid = IsInRaid and IsInRaid()
    for i = 1, raid and count or (count - 1) do
        local name = UnitName((raid and "raid" or "party") .. i)
        if name then rosterScratch[#rosterScratch + 1] = name end
    end
    table.sort(rosterScratch)
    return table.concat(rosterScratch, "|")
end

function E.CheckParty()
    local key = RosterSignature()
    if key == E.partyKey then return end
    E.partyKey = key
    for name in pairs(E.Party) do E.Party[name] = nil end
    E.partyChangedAt = Now()
end

local function PartyRow(name)
    local row = E.Party[name]
    if not row then
        row = { name = name, items = 0, bestQuality = -1, need = 0, greed = 0, pass = 0, won = 0 }
        E.Party[name] = row
    end
    return row
end

function E.RecordOther(who, itemID, count, link)
    local row = PartyRow(who)
    count = tonumber(count) or 1
    row.items = row.items + count
    local entry = E.Meta(itemID)
    local quality = entry and entry.quality or 1
    if quality > row.bestQuality then
        row.bestQuality, row.bestItemID, row.bestLink = quality, itemID, link
    end
    FeedPush({
        kind = "item", itemID = itemID, count = count, quality = quality,
        link = link, icon = entry and entry.icon, name = entry and entry.name,
        t = Now(), mine = false, who = who, srcKind = SRC_LOOTED,
        sourceName = currentSource and currentSource.name,
    })
end

local function LinkItemID(link)
    if type(link) ~= "string" then return nil end
    local id = link:match("|Hitem:(%d+)")
    return tonumber(id)
end
E.LinkItemID = LinkItemID

local playerName

-- The single authoritative loot-chat parser for the whole suite (D21).
function E.OnLootMessage(message)
    if type(message) ~= "string" or not Data then return end
    lootMatchers = lootMatchers or BuildMatchers(LOOT_SPECS)
    local matcher, caps = Match(lootMatchers, message)
    if not matcher then return end
    local link = caps.item
    local itemID = LinkItemID(link)
    if not itemID then return end
    local count = tonumber(caps.count) or 1

    if matcher.self then
        local srcKind = (matcher.kind == "created" and SRC_CREATED)
            or (matcher.kind == "pushed" and SRC_PUSHED)
            or SRC_LOOTED
        -- Arms the reconciler's CRAFTED attribution: the reagents this craft
        -- consumed will show up as a negative residual on the same settle.
        if srcKind == SRC_CREATED then createdThisTick = true end
        local sourceID, sourceName
        if srcKind == SRC_LOOTED and currentSource then
            sourceID, sourceName = currentSource.id, currentSource.name
        end
        E.Record(itemID, count, srcKind, sourceID, sourceName, link)
        E.expected[itemID] = (E.expected[itemID] or 0) + count
        E.ArmSettle()
    else
        local who = caps.who
        playerName = playerName or UnitName("player")
        if who and who ~= playerName then
            E.RecordOther(who, itemID, count, link)
        end
    end
end

function E.OnMoneyMessage(message)
    if type(message) ~= "string" or not Data then return end
    moneyMatchers = moneyMatchers or BuildMatchers(MONEY_SPECS)
    local matcher, caps = Match(moneyMatchers, message)
    if not matcher then return end
    local copper = E.ParseMoney(caps.money)
    if copper <= 0 then return end
    local coinSlot = RateSlot()
    coinSlot.value = coinSlot.value + copper
    -- Coin rows go in the log too, so every scope can fold their gold from the
    -- same index range every other number comes from. Without this HOUR had no
    -- coin at all and a /reload zeroed the session total while items survived.
    RingPush(Data.money.log, { Now(), copper },
        CommanderSpoilsDB.TrackHistory and LIMITS.money or 60)
    -- No per-segment gold counter: every scope folds coin out of this log by
    -- timestamp, which is the same range every other number comes from and
    -- survives a /reload for free.
    E.foldSerial = E.foldSerial + 1
    FeedPush({
        kind = "money", copper = copper, split = matcher.kind == "split",
        t = Now(), mine = true, sourceName = currentSource and currentSource.name,
    })
    Commander.Notify(EV.MONEY, copper, matcher.kind == "split")
end

function E.OnCurrencyMessage(message)
    if type(message) ~= "string" or not Data then return end
    currencyMatchers = currencyMatchers or BuildMatchers(CURRENCY_SPECS)
    local matcher, caps = Match(currencyMatchers, message)
    if not matcher then return end
    local link = caps.item
    local itemID = LinkItemID(link)
    if itemID then
        local count = tonumber(caps.count) or 1
        E.Record(itemID, count, SRC_CURRENCY, nil, nil, link)
        -- Badges and marks are real bag items; without this the settle pass
        -- reads them as an unexplained gain and records them a second time.
        E.expected[itemID] = (E.expected[itemID] or 0) + count
        E.ArmSettle()
    else
        FeedPush({ kind = "currency", label = link, count = tonumber(caps.count) or 1,
                   t = Now(), mine = true })
    end
end

-- ===========================================================================
-- 7. Bag census and the reconciler (D6, D7)
-- ===========================================================================
E.counts = {}       -- [itemID] = n, current bags
E.expected = {}     -- [itemID] = n, deltas chat already explained
E.census = nil
E.censusDirty = true

-- context / questTurnedIn / createdThisTick are the §6 upvalues; re-declaring
-- them here would shadow the writes §6 makes to them.

local function ContainerInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        return C_Container.GetContainerItemInfo(bag, slot)
    end
    return nil
end

local function ContainerSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag) or 0
    end
    return 0
end

local function ContainerFree(bag)
    if C_Container and C_Container.GetContainerNumFreeSlots then
        return C_Container.GetContainerNumFreeSlots(bag)
    end
    return 0
end

local scanCounts = {}

-- Keyed itemID -> count, never a slot map: slot-keyed diffing emits phantom
-- move events on every bag sort, and Commander_Bags ships a sort engine.
local function ScanBags()
    wipe(scanCounts)
    local used, total = 0, 0
    for bag = 0, 4 do
        local slots = ContainerSlots(bag)
        total = total + slots
        for slot = 1, slots do
            local info = ContainerInfo(bag, slot)
            if info and info.itemID then
                used = used + 1
                scanCounts[info.itemID] = (scanCounts[info.itemID] or 0) + (info.stackCount or 1)
            end
        end
    end
    return scanCounts, used, total
end

local OUTFLOW_REASON = {
    merchant = "VENDORED", trade = "TRADED", mail = "MAILED",
    quest = "QUEST", crafted = "CRAFTED", other = "USED",
}

local function Reconcile(fresh)
    -- The bank is only readable while it is open, so to a bags-only census a
    -- deposit is indistinguishable from destroying the item. Same for an
    -- equipment change in the same tick. Suppress rather than guess.
    if context.bank or context.equipment then
        context.equipment = false
        return
    end
    local reason = (context.merchant and "merchant")
        or (context.trade and "trade")
        or (context.mail and "mail")
        or (questTurnedIn and "quest")
        or (createdThisTick and "crafted")
        or "other"

    local seen = {}
    for itemID, count in pairs(fresh) do
        seen[itemID] = true
        local delta = count - (E.counts[itemID] or 0)
        local explained = E.expected[itemID] or 0
        local residual = delta - explained
        if residual > 0 then
            -- Entered our possession off a non-loot path: mail, vendor
            -- purchase, trade, quest reward. It is still ours.
            E.Record(itemID, residual, SRC_OTHER, nil, nil, nil)
        elseif residual < 0 then
            E.RecordOutflow(itemID, -residual, OUTFLOW_REASON[reason])
        end
    end
    for itemID, count in pairs(E.counts) do
        if not seen[itemID] then
            local explained = E.expected[itemID] or 0
            local residual = -count - explained
            if residual < 0 then
                E.RecordOutflow(itemID, -residual, OUTFLOW_REASON[reason])
            end
        end
    end
end

local outflowPool = { {}, {} }
local outflowSlot = 0
function E.RecordOutflow(itemID, count, reason)
    local entry = E.Meta(itemID)
    FeedPush({
        kind = "outflow", itemID = itemID, count = count, reason = reason,
        quality = entry and entry.quality, icon = entry and entry.icon,
        name = entry and entry.name, t = Now(), mine = true,
    })
    outflowSlot = outflowSlot % #outflowPool + 1
    local outflowEntry = wipe(outflowPool[outflowSlot])
    outflowEntry.itemID, outflowEntry.count, outflowEntry.reason = itemID, count, reason
    Commander.Notify(EV.OUTFLOW, outflowEntry, reason)
end

-- One debounced settle for both jobs. BAG_UPDATE_DELAYED can beat the chat
-- line for the same loot, so the timer re-arms on every loot line and is hard
-- capped so a long autoloot burst still settles.
local settlePending, settleAt, settleDeadline = false, 0, 0
local SETTLE_DELAY, SETTLE_CAP = 0.3, 1.5

local function Settle()
    settlePending = false
    if not Data then return end
    local fresh, used, total = ScanBags()
    -- The first scan of a session is a BASELINE, not a diff. Without this the
    -- reconciler reads the player's entire inventory as freshly acquired.
    if E.baselined then
        Reconcile(fresh)
    elseif total > 0 then
        E.baselined = true
    end
    -- An empty scan is NOT a baseline: containers may not be populated yet at
    -- PLAYER_LOGIN, and baselining as empty would make the next settle record
    -- the player's entire inventory as freshly acquired.
    wipe(E.counts)
    for itemID, count in pairs(fresh) do E.counts[itemID] = count end
    wipe(E.expected)
    questTurnedIn, createdThisTick = false, false
    E.censusDirty = true
    Commander.Notify(EV.CENSUS, E.Census())
end

-- Trailing edge, not leading. Settling 0.3s after the FIRST line of a burst
-- means a chat line landing just before the timer adds to E.expected that the
-- container API has not caught up with yet: the reconciler then reads it as a
-- consumption (a phantom "you used 5 cloth") and counts the same loot again as
-- an unexplained gain on the next pass. Both ledgers corrupt in one burst.
local function SettleTick()
    if not settlePending then return end
    local now = GetTime and GetTime() or 0
    if now >= settleAt then
        Settle()
        return
    end
    C_Timer.After(math.max(0.05, settleAt - now), SettleTick)
end

function E.ArmSettle()
    local now = GetTime and GetTime() or 0
    if not settlePending then
        settlePending = true
        settleDeadline = now + SETTLE_CAP
        settleAt = now + SETTLE_DELAY
        C_Timer.After(SETTLE_DELAY, SettleTick)
        return
    end
    -- Push the deadline out, but never past the hard cap: a long autoloot
    -- burst must still settle.
    settleAt = math.min(now + SETTLE_DELAY, settleDeadline)
end

-- Aggregation is a pure function of counts + memoized meta, computed behind a
-- dirty flag: a player with the window closed pays only for the count map.
function E.Census()
    if E.census and not E.censusDirty then return E.census end
    local census = E.census or {}
    E.census = census
    E.censusDirty = false
    census.bags = census.bags or {}
    census.byQuality = census.byQuality or {}
    census.byBucket = census.byBucket or {}
    census.hogs = census.hogs or {}
    wipe(census.byQuality)
    wipe(census.byBucket)
    wipe(census.hogs)
    for q = 0, 5 do census.byQuality[q] = { stacks = 0, items = 0, value = 0 } end

    local slotsTotal, slotsFree = 0, 0
    for bag = 0, 4 do
        local slots = ContainerSlots(bag)
        local free = ContainerFree(bag) or 0
        slotsTotal = slotsTotal + slots
        slotsFree = slotsFree + free
        census.bags[bag] = census.bags[bag] or {}
        local record = census.bags[bag]
        record.size, record.free = slots, free
    end
    census.slotsTotal, census.slotsFree = slotsTotal, slotsFree
    census.slotsUsed = slotsTotal - slotsFree

    local junkStacks, junkItems, junkValue, junkWorst, junkWorstValue = 0, 0, 0, nil, 0
    local totalValue = 0
    local partialSlots, reclaimable = 0, 0
    local stacksByItem = {}

    for bag = 0, 4 do
        local slots = ContainerSlots(bag)
        for slot = 1, slots do
            local info = ContainerInfo(bag, slot)
            if info and info.itemID then
                local itemID = info.itemID
                local count = info.stackCount or 1
                local entry = E.Meta(itemID)
                -- ContainerItemInfo.quality is Nilable and Blizzard does not
                -- guard it either; ITEM_QUALITY_COLORS[nil] errors.
                local quality = info.quality or (entry and entry.quality) or 1
                local bucket = (entry and entry.bucket) or "OTHER"
                local unit = (entry and entry.sellPrice) or 0
                local value = unit * count

                local qRow = census.byQuality[quality] or census.byQuality[1]
                qRow.stacks = qRow.stacks + 1
                qRow.items = qRow.items + count
                qRow.value = qRow.value + value

                local bIdx = E.BucketIndex[bucket]
                local bRow = census.byBucket[bIdx]
                if not bRow then
                    bRow = { stacks = 0, items = 0, value = 0, bucket = bIdx }
                    census.byBucket[bIdx] = bRow
                end
                bRow.stacks = bRow.stacks + 1
                bRow.items = bRow.items + count
                bRow.value = bRow.value + value
                totalValue = totalValue + value

                -- Junk is quality 0 with a real sell price. Not hasNoValue:
                -- that is only accurate while a merchant window is open, which
                -- is Commander_Logistics' context and not ours.
                if quality == 0 and unit > 0 then
                    junkStacks = junkStacks + 1
                    junkItems = junkItems + count
                    junkValue = junkValue + value
                    if value > junkWorstValue then junkWorst, junkWorstValue = itemID, value end
                end

                local maxStack = (entry and entry.stack) or 1
                if maxStack > 1 and count < maxStack then
                    partialSlots = partialSlots + 1
                    local acc = stacksByItem[itemID]
                    if not acc then acc = { slots = 0, items = 0, max = maxStack }; stacksByItem[itemID] = acc end
                    acc.slots = acc.slots + 1
                    acc.items = acc.items + count
                end

                local hog = census.hogs[itemID]
                if not hog then
                    hog = { itemID = itemID, slots = 0, items = 0, value = 0, quality = quality }
                    census.hogs[itemID] = hog
                end
                hog.slots = hog.slots + 1
                hog.items = hog.items + count
                hog.value = hog.value + value
            end
        end
    end

    for _, acc in pairs(stacksByItem) do
        local needed = math.ceil(acc.items / acc.max)
        if acc.slots > needed then reclaimable = reclaimable + (acc.slots - needed) end
    end

    census.junk = census.junk or {}
    census.junk.stacks, census.junk.items = junkStacks, junkItems
    census.junk.value, census.junk.worst = junkValue, junkWorst
    census.totalValue = totalValue
    census.partialSlots, census.reclaimable = partialSlots, reclaimable
    census.at = Now()

    -- Bags-full projection comes from the census delta, not the loot stream:
    -- looting into a partial stack costs zero slots, so a loot-stream estimate
    -- is wrong in exactly the case that matters.
    local usedNow = census.slotsUsed
    if E.lastCensusUsed and E.lastCensusAt then
        local elapsed = census.at - E.lastCensusAt
        if elapsed >= 30 then
            local rate = (usedNow - E.lastCensusUsed) / (elapsed / 60)
            E.slotRate = (E.slotRate and (E.slotRate * 0.6 + rate * 0.4)) or rate
            E.lastCensusUsed, E.lastCensusAt = usedNow, census.at
        end
    else
        E.lastCensusUsed, E.lastCensusAt = usedNow, census.at
    end
    if E.slotRate and E.slotRate > 0.05 then
        census.minutesToFull = census.slotsFree / E.slotRate
    else
        census.minutesToFull = nil
    end

    return census
end

-- ===========================================================================
-- 8. Rolls
-- ===========================================================================
E.rolls = {}        -- ordered, oldest first; live and recently-resolved
E.rollByID = {}
local historyIndexByRollID = {}

local ROLL_HOLD = 6      -- seconds a resolved row stays before it collapses

local function RollTimeLeft(rollID)
    if type(_G.GetLootRollTimeLeft) ~= "function" then return nil end
    local ok, ms = pcall(_G.GetLootRollTimeLeft, rollID)
    return ok and ms or nil
end

local function RollItemInfo(rollID)
    if type(_G.GetLootRollItemInfo) ~= "function" then return nil end
    return _G.GetLootRollItemInfo(rollID)
end

function E.AddRoll(rollID, rollTime)
    if E.rollByID[rollID] then return E.rollByID[rollID] end
    local texture, name, count, quality, bop, canNeed, canGreed,
          _, reasonNeed, reasonGreed = RollItemInfo(rollID)
    local link = type(_G.GetLootRollItemLink) == "function" and _G.GetLootRollItemLink(rollID) or nil
    local itemID = LinkItemID(link)
    local roll = {
        id = rollID, icon = texture, name = name, count = count or 1,
        quality = quality, bop = bop, canNeed = canNeed, canGreed = canGreed,
        reasonNeed = reasonNeed, reasonGreed = reasonGreed,
        link = link, itemID = itemID,
        rollTime = rollTime, startedAt = GetTime and GetTime() or 0,
        guardUntil = (GetTime and GetTime() or 0) + (CommanderSpoilsDB.RollGuardMs or 300) / 1000,
        rollers = {},
    }
    if itemID then
        -- The row must be live before the name arrives: the timer is already
        -- running and you have to be able to Need something you cannot yet read.
        E.Meta(itemID)
    end
    E.rolls[#E.rolls + 1] = roll
    E.rollByID[rollID] = roll
    Commander.Notify(EV.ROLL, roll, "start")
    return roll
end

function E.Roll(rollID, rollType)
    local roll = E.rollByID[rollID]
    if not roll or roll.resolved then return end
    if (GetTime and GetTime() or 0) < (roll.guardUntil or 0) then return end
    if rollType == 1 and not roll.canNeed then return end
    if rollType == 2 and not roll.canGreed then return end
    -- Provisional until the server accepts it. A bind-on-pickup roll comes
    -- back as CONFIRM_LOOT_ROLL and is NOT cast until ConfirmLootRoll.
    roll.my = rollType
    roll.provisional = true
    if type(_G.RollOnLoot) == "function" then pcall(_G.RollOnLoot, rollID, rollType) end
    Commander.Notify(EV.ROLL, roll, "update")
end

function E.PassAll()
    for _, roll in ipairs(E.rolls) do
        if not roll.resolved and roll.my == nil then E.Roll(roll.id, 0) end
    end
end

local ROLL_TYPE_NAME = { [0] = "PASS", [1] = "NEED", [2] = "GREED" }
E.RollTypeName = ROLL_TYPE_NAME

-- Per-player roll detail is stored as PACKED STRINGS, not nested tables. A
-- nested table costs 45-60 bytes of braces and key names on top of the payload;
-- for a 25-player roll that is 1.4 KB against 600 bytes.
local function PackRollers(roll)
    local packed = {}
    for _, entry in ipairs(roll.rollers) do
        packed[#packed + 1] = format("%s:%s:%s:%s",
            entry.name or "?", entry.class or "?",
            entry.rollType or "", entry.roll or "")
    end
    return #packed > 0 and packed or nil
end

function E.ResolveRoll(rollID, winner, winnerClass, winnerType, winnerRoll)
    local roll = E.rollByID[rollID]
    if not roll or roll.resolved then return end
    roll.resolved = true
    roll.resolvedAt = GetTime and GetTime() or 0
    roll.winner, roll.winnerClass = winner, winnerClass
    roll.winnerType, roll.winnerRoll = winnerType, winnerRoll
    playerName = playerName or UnitName("player")
    roll.won = winner ~= nil and winner == playerName

    -- An expired unactioned roll IS the honest half of "never miss a roll" —
    -- but only when there was something to act on. A mage marked MISSED for
    -- every plate drop in Karazhan turns the one metric the player cares about
    -- into noise.
    if roll.my == nil and not roll.auto and winner ~= nil
        and (roll.canNeed or roll.canGreed) then
        roll.missed = true
    end

    if Data and CommanderSpoilsDB.TrackHistory then
        RingPush(Data.rolls, {
            t = Now(), id = roll.itemID, q = roll.quality, n = roll.count,
            map = E.MapID(), src = roll.sourceName,
            my = roll.missed and -1 or roll.my,
            myRoll = roll.myRoll,
            w = winner, wc = winnerClass, wt = winnerType, wr = winnerRoll,
            p = PackRollers(roll),
        }, LIMITS.rolls)
    end

    if roll.won then
        local row = PartyRow(playerName)
        row.won = row.won + 1
    elseif winner then
        PartyRow(winner).won = PartyRow(winner).won + 1
    end
    Commander.Notify(EV.ROLL, roll, "resolved")
end

-- CONFIRM_LOOT_ROLL's third argument is a server-supplied FORMAT string with
-- no pinned arguments. Never hand one to format() unguarded: a mismatched
-- specifier throws inside an event handler at the exact moment the player is
-- trying to take an epic.
function E.FormatConfirm(reason, itemName)
    if type(reason) ~= "string" then return nil end
    if reason:find("%%%d?%$?[sd]") then
        local ok, formatted = pcall(format, reason, itemName or "")
        if ok then return formatted end
    end
    return reason
end

function E.ConfirmRoll(rollID, rollType)
    if type(_G.ConfirmLootRoll) == "function" then pcall(_G.ConfirmLootRoll, rollID, rollType) end
    local roll = E.rollByID[rollID]
    if roll then
        roll.confirm = nil
        roll.my, roll.provisional = rollType, nil
        Commander.Notify(EV.ROLL, roll, "update")
    end
end

-- Declining the bind confirm un-casts the roll. Without this the row claims a
-- Need that never happened and the missed-roll counter stays silent about it.
function E.DeclineRoll(rollID)
    local roll = E.rollByID[rollID]
    if not roll then return end
    roll.confirm, roll.my, roll.provisional = nil, nil, nil
    Commander.Notify(EV.ROLL, roll, "update")
end

function E.CancelRoll(rollID)
    -- Withdrawn, not missed. Mislabelling this destroys the credibility of the
    -- missed-roll counter.
    local roll = E.rollByID[rollID]
    if not roll then return end
    roll.resolved, roll.cancelled = true, true
    roll.resolvedAt = GetTime and GetTime() or 0
    Commander.Notify(EV.ROLL, roll, "resolved")
end

local ROLL_ORPHAN_GRACE = 20   -- seconds past expiry before we give up

function E.PruneRolls()
    local now = GetTime and GetTime() or 0
    for i = #E.rolls, 1, -1 do
        local roll = E.rolls[i]
        if not roll.resolved then
            -- The server can stop talking about a roll. Without a timeout the
            -- row stays "live" forever and the urgency glow never lets go.
            local left = RollTimeLeft(roll.id)
            local age = now - (roll.startedAt or now)
            local span = (roll.rollTime and roll.rollTime / 1000) or 60
            if (not left or left <= 0) and age > span + ROLL_ORPHAN_GRACE then
                roll.orphaned = true
                E.ResolveRoll(roll.id, nil, nil, nil, nil)
            end
        end
        if roll.resolved and (now - (roll.resolvedAt or 0)) > ROLL_HOLD then
            E.rollByID[roll.id] = nil
            historyIndexByRollID[roll.id] = nil
            tremove(E.rolls, i)
        end
    end
end

function E.PendingRolls()
    local count, soonest = 0, nil
    for _, roll in ipairs(E.rolls) do
        if not roll.resolved then
            local live = (roll.canNeed or roll.canGreed) and roll.my == nil
            if live then
                count = count + 1
                local left = RollTimeLeft(roll.id)
                if left and (not soonest or left < soonest) then soonest = left end
            end
        end
    end
    return count, soonest
end

-- C_LootHistory is the authoritative source for who rolled what — not chat.
-- Chat is the shadow ledger for entries the server has already expired.
local function SyncHistoryIndex()
    if not (C_LootHistory and C_LootHistory.GetNumItems) then return end
    wipe(historyIndexByRollID)
    local ok, total = pcall(C_LootHistory.GetNumItems)
    if not ok or not total then return end
    for i = 1, total do
        local okItem, rollID = pcall(C_LootHistory.GetItem, i)
        if okItem and rollID then historyIndexByRollID[rollID] = i end
    end
end

local function RefreshRollers(roll)
    if not (C_LootHistory and C_LootHistory.GetItem) then return end
    local index = historyIndexByRollID[roll.id]
    if not index then return end
    local ok, _, _, numPlayers, isDone, winnerIdx = pcall(C_LootHistory.GetItem, index)
    if not ok then return end
    wipe(roll.rollers)
    for playerIdx = 1, (numPlayers or 0) do
        local okPlayer, name, class, rollType, rollValue, isWinner, isMe =
            pcall(C_LootHistory.GetPlayerInfo, index, playerIdx)
        if okPlayer and name then
            roll.rollers[#roll.rollers + 1] = {
                name = name, class = class, rollType = rollType,
                roll = rollValue, winner = isWinner, me = isMe,
            }
            if isMe and rollValue then roll.myRoll = rollValue end
            -- RefreshRollers runs once per player decision AND once per roll on
            -- every full update, so crediting unconditionally multiplied every
            -- tally by the number of refreshes. Credit a name once per roll,
            -- and only when its choice changes.
            if name and rollType ~= nil then
                roll.counted = roll.counted or {}
                if roll.counted[name] == nil then
                    roll.counted[name] = rollType
                    local row = PartyRow(name)
                    if rollType == 1 then row.need = row.need + 1
                    elseif rollType == 2 then row.greed = row.greed + 1
                    elseif rollType == 0 then row.pass = row.pass + 1 end
                end
            end
        end
    end
    roll.decided = #roll.rollers
    if isDone and winnerIdx and roll.rollers[winnerIdx] then
        local win = roll.rollers[winnerIdx]
        E.ResolveRoll(roll.id, win.name, win.class, win.rollType, win.roll)
    end
end
E.RefreshRollers = RefreshRollers

function E.OnRollChat(message)
    if type(message) ~= "string" then return end
    rollMatchers = rollMatchers or BuildMatchers(ROLL_SPECS)
    local matcher, caps = Match(rollMatchers, message)
    if not matcher then return end
    playerName = playerName or UnitName("player")
    if matcher.kind == "won" then
        local who = matcher.self and playerName or caps.who
        local itemID = LinkItemID(caps.item)
        -- Resolve by loot-history index first. Two identical BoEs in flight is
        -- the normal case in a wave pull, and matching on itemID lands the
        -- verdict on whichever row happened to come first.
        local index = tonumber(caps.hist)
        if index then
            for rollID, historyIndex in pairs(historyIndexByRollID) do
                if historyIndex == index and E.rollByID[rollID]
                    and not E.rollByID[rollID].resolved then
                    E.ResolveRoll(rollID, who, nil, nil, nil)
                    return
                end
            end
        end
        for _, roll in ipairs(E.rolls) do
            if not roll.resolved and roll.itemID == itemID then
                E.ResolveRoll(roll.id, who, nil, nil, nil)
                return
            end
        end
        FeedPush({ kind = "roll", label = "WON", who = who, link = caps.item,
                   itemID = itemID, t = Now(), mine = matcher.self })
    elseif matcher.kind == "allpassed" then
        local itemID = LinkItemID(caps.item)
        for _, roll in ipairs(E.rolls) do
            if not roll.resolved and roll.itemID == itemID then
                roll.allPassed = true
                E.ResolveRoll(roll.id, nil, nil, nil, nil)
                return
            end
        end
    elseif matcher.kind == "rolled" then
        -- Chat is the FALLBACK, not a second source: if loot history already
        -- covers this roll, its tally is authoritative and adding here would
        -- double it (D9).
        local index = tonumber(caps.hist)
        local covered = false
        for rollID, historyIndex in pairs(historyIndexByRollID) do
            if historyIndex == index then covered = true break end
        end
        local who = caps.who
        if not covered and who and who ~= playerName then
            local row = PartyRow(who)
            if matcher.type == 1 then row.need = row.need + 1
            elseif matcher.type == 2 then row.greed = row.greed + 1 end
        end
    end
end

-- ===========================================================================
-- 9. Loot slots (the Salvage model)
-- ===========================================================================
E.slots = {}
E.lootOpen = false
E.autoLoot = false

function E.RebuildSlots()
    wipe(E.slots)
    if type(_G.GetNumLootItems) ~= "function" then return E.slots end
    local total = _G.GetNumLootItems() or 0
    local sourceProbe = ProbeSourceInfo(total > 0)
    for slot = 1, total do
        local has = _G.LootSlotHasItem and _G.LootSlotHasItem(slot)
        if has ~= false then
            local texture, name, quantity, currencyID, quality, locked = _G.GetLootSlotInfo(slot)
            local slotType = _G.GetLootSlotType and _G.GetLootSlotType(slot) or 1
            local link = _G.GetLootSlotLink and _G.GetLootSlotLink(slot) or nil
            local itemID = LinkItemID(link)
            -- Quality (return 5) can be nil for an uncached item, and
            -- ITEM_QUALITY_COLORS[nil] errors. Fall back through the link.
            if quality == nil and itemID then
                local entry = E.Meta(itemID)
                quality = entry and entry.quality
            end
            if sourceProbe then
                local ok, guid = pcall(_G.GetLootSourceInfo, slot)
                if ok and type(guid) == "string" then
                    slotSources[slot] = guid
                    -- Exact per-slot attribution. The target heuristic gets
                    -- this wrong on every AoE-looted pile, which is exactly
                    -- where per-source drop counts matter.
                    -- Credit the CORPSE once, not once per slot: a four-item
                    -- corpse counting four kills makes every per-source drop
                    -- rate wrong by the average slot count.
                    local creatureID = CreatureIDFromGUID(guid)
                    if creatureID and not slotCredited[guid] then
                        slotCredited[guid] = creatureID
                        Data.kills[creatureID] = (Data.kills[creatureID] or 0) + 1
                        -- Only label it when the target IS this creature; in an
                        -- AoE pile the current target is somebody else.
                        local targetID = CreatureIDFromGUID(UnitGUID and UnitGUID("target"))
                        if targetID == creatureID then
                            InternName(creatureID, UnitName("target"))
                        end
                    end
                end
            end
            E.slots[#E.slots + 1] = {
                slot = slot, icon = texture, name = name, count = quantity or 1,
                quality = quality, locked = locked, slotType = slotType,
                currencyID = (slotType == 3) and currencyID or nil,
                link = link, itemID = itemID,
                cached = name ~= nil,
            }
        end
    end
    return E.slots
end

function E.TakeSlot(slot)
    if type(_G.LootSlot) == "function" then pcall(_G.LootSlot, slot) end
end

function E.ConfirmSlot(slot)
    if type(_G.ConfirmLootSlot) == "function" then pcall(_G.ConfirmLootSlot, slot) end
end

-- Candidate indices are SPARSE, and the index passed to GiveMasterLoot is the
-- RAW PROBE INDEX, never a position in the sorted display list. That is the
-- single most likely bug in this module.
function E.MasterCandidates(slot)
    local list = {}
    if type(_G.GetMasterLootCandidate) ~= "function" then return list end
    local limit = _G.MAX_RAID_MEMBERS or 40
    for i = 1, limit do
        local ok, name = pcall(_G.GetMasterLootCandidate, slot, i)
        if ok and name then
            local class = select(2, UnitClass(name))
            list[#list + 1] = {
                name = name, index = i, class = class,
                online = UnitIsConnected(name) ~= false,
                dead = UnitIsDeadOrGhost(name) == true,
            }
        end
    end
    return list
end

function E.IsMasterLooter()
    if type(_G.IsMasterLooter) == "function" then
        local ok, value = pcall(_G.IsMasterLooter)
        if ok then return value end
    end
    return false
end

function E.LootMethod()
    if C_PartyInfo and C_PartyInfo.GetLootMethod then
        local ok, method = pcall(C_PartyInfo.GetLootMethod)
        if ok then return method end
    end
    return nil
end

local THRESHOLD_LABEL = { [2] = "UNCOMMON", [3] = "RARE", [4] = "EPIC", [5] = "LEGENDARY" }
local METHOD_LABEL = {
    [0] = "FREE FOR ALL", [1] = "ROUND ROBIN", [2] = "MASTER LOOTER",
    [3] = "GROUP LOOT", [4] = "NEED BEFORE GREED", [5] = "PERSONAL",
}

function E.LootMethodText()
    if not IsInGroup or not IsInGroup() then return "SOLO" end
    local method = E.LootMethod()
    local label = METHOD_LABEL[method] or "GROUP LOOT"
    local threshold = _G.GetLootThreshold and _G.GetLootThreshold()
    if threshold and THRESHOLD_LABEL[threshold] then
        return label .. " · THRESHOLD " .. THRESHOLD_LABEL[threshold]
    end
    return label
end

-- ===========================================================================
-- 10. The interest model (D16)
-- ===========================================================================
function E.IsNotable(itemID, quality, bop)
    local db = CommanderSpoilsDB
    local pin = db.PinnedItems and db.PinnedItems[itemID]
    if pin ~= nil then return pin end
    local entry = E.Meta(itemID)
    if entry then
        local classID, subClassID = entry.classID, entry.subClassID
        if db.FilterArmor and E.IsMyArmor(classID, subClassID) then return true end
        if db.FilterRecipes and classID == 9 then return true end
        if db.FilterTradeGoods and classID == 7 then return true end
        if db.FilterConsumables and classID == 0 then return true end
        if db.FilterQuest and classID == 12 then return true end
        if db.FilterBoP and (bop or entry.bind == 1) then return true end
    end
    return (quality or 0) >= (db.MinQuality or 3)
end

function E.Pin(itemID, value)
    CommanderSpoilsDB.PinnedItems = CommanderSpoilsDB.PinnedItems or {}
    CommanderSpoilsDB.PinnedItems[itemID] = value
    Commander.Notify(EV.UPDATE)
end

-- ===========================================================================
-- 11. Init and event wiring
-- ===========================================================================
local events = CreateFrame("Frame")

local function OnEvent(self, event, a, b, c, d)
    if event == "PLAYER_LOGOUT" then
        -- Runs even when the module is switched off: this is the only place
        -- the file written to disk gets compacted.
        E.Prune()
        return
    end
    if not CommanderSpoilsDB.EnableSpoils then return end
    if event == "CHAT_MSG_LOOT" then
        E.OnLootMessage(a)
        E.OnRollChat(a)
    elseif event == "CHAT_MSG_MONEY" then
        E.OnMoneyMessage(a)
    elseif event == "CHAT_MSG_CURRENCY" then
        E.OnCurrencyMessage(a)
    elseif event == "BAG_UPDATE_DELAYED" then
        E.ArmSettle()
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        -- (no census notify here: a corpse opening changes no bag)
        E.autoLoot = a and true or false
        if not currentSource then
            local name = UnitName("target")
            local guid = UnitGUID and UnitGUID("target")
            -- Only a corpse we are actually standing over is a credible
            -- source; a live retargeted mob is not, and crediting it puts the
            -- drop on the wrong creature.
            local dead = UnitIsDead and UnitIsDead("target")
            currentSource = {
                name = dead and name or nil,
                id = dead and CreatureIDFromGUID(guid) or nil,
                fishing = _G.IsFishingLoot and _G.IsFishingLoot() or false,
            }
            -- The kill is credited per slot when GetLootSourceInfo answers;
            -- this is the fallback for when it does not.
            if currentSource.id and not sourceInfoOK then
                Data.kills[currentSource.id] = (Data.kills[currentSource.id] or 0) + 1
                InternName(currentSource.id, currentSource.name)
            end
        end
        E.lootOpen = true
        E.RebuildSlots()
        if E.OnSalvageDirty then E.OnSalvageDirty() end
    elseif event == "LOOT_SLOT_CLEARED" or event == "LOOT_SLOT_CHANGED" then
        E.RebuildSlots()
    elseif event == "OPEN_MASTER_LOOT_LIST" or event == "UPDATE_MASTER_LOOT_LIST" then
        -- Candidates are per-slot and the server revises the list; a one-shot
        -- probe at click time goes stale (FINDINGS §7 gotcha 7).
        if E.OnSalvageDirty then E.OnSalvageDirty() end
    elseif event == "LOOT_CLOSED" then
        E.lootOpen = false
        currentSource = nil
        E.bindSlot = nil     -- else the next corpse inherits a stale confirm row
        wipe(slotSources)
        wipe(slotCredited)
        wipe(E.slots)
    elseif event == "START_LOOT_ROLL" then
        local roll = E.AddRoll(a, b)
        if roll and currentSource then roll.sourceName = currentSource.name end
    elseif event == "CANCEL_LOOT_ROLL" then
        E.CancelRoll(a)
    elseif event == "LOOT_ITEM_ROLL_WON" then
        -- (itemLink, rollQuantity, rollType, roll, upgraded). This is the
        -- fastest path to "you won" and carries your own roll number.
        playerName = playerName or UnitName("player")
        local itemID = LinkItemID(a)
        for _, roll in ipairs(E.rolls) do
            if not roll.resolved and roll.itemID == itemID then
                roll.myRoll = tonumber(d) or roll.myRoll
                E.ResolveRoll(roll.id, playerName, select(2, UnitClass("player")),
                    tonumber(c), tonumber(d))
                break
            end
        end
    elseif event == "LOOT_BIND_CONFIRM" then
        -- Replace the centre-screen dialog with an inline confirm on the
        -- item's own row, so the player can still see what else is on the
        -- corpse while deciding.
        if CommanderSpoilsDB.SuppressBindConfirm and CommanderSpoilsDB.SuppressLootWindow then
            if _G.StaticPopup_Hide then pcall(_G.StaticPopup_Hide, "LOOT_BIND") end
            E.bindSlot = a
            E.RebuildSlots()
            -- Repaint the CORPSE, not the window. Routing this through the
            -- census notify only repainted the main window, so the inline
            -- confirm never drew and the item could not be looted at all.
            if E.OnSalvageDirty then E.OnSalvageDirty() end
        end
    elseif event == "CONFIRM_LOOT_ROLL" then
        if CommanderSpoilsDB.SuppressBindConfirm then
            if _G.StaticPopup_Hide then pcall(_G.StaticPopup_Hide, "CONFIRM_LOOT_ROLL") end
            local roll = E.rollByID[a]
            if roll then
                -- Not cast yet: clear the provisional choice so the row does
                -- not claim a roll the server is still asking about.
                if roll.provisional then roll.my = nil end
                roll.confirm = { rollType = b, reason = E.FormatConfirm(c, roll.name) }
                Commander.Notify(EV.ROLL, roll, "update")
            end
        end
    elseif event == "LOOT_HISTORY_FULL_UPDATE" then
        SyncHistoryIndex()
        for _, roll in ipairs(E.rolls) do RefreshRollers(roll) end
    elseif event == "LOOT_HISTORY_ROLL_CHANGED" or event == "LOOT_HISTORY_ROLL_COMPLETE" then
        for _, roll in ipairs(E.rolls) do
            if not roll.resolved then RefreshRollers(roll) end
        end
    elseif event == "MERCHANT_SHOW" then context.merchant = true
    elseif event == "MERCHANT_CLOSED" then context.merchant = false
    elseif event == "TRADE_SHOW" then context.trade = true
    elseif event == "TRADE_CLOSED" then context.trade = false
    elseif event == "MAIL_SHOW" then context.mail = true
    elseif event == "MAIL_CLOSED" then context.mail = false
    elseif event == "BANKFRAME_OPENED" then context.bank = true
    elseif event == "BANKFRAME_CLOSED" then context.bank = false
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then context.equipment = true
    elseif event == "QUEST_TURNED_IN" then questTurnedIn = true
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if pendingInfo[a] then
            pendingInfo[a] = nil
            meta[a] = nil
            local entry = E.Meta(a)
            -- The first time an item is ever seen it is uncached, so its row
            -- was written with a guessed quality and no value. Backfill, or
            -- the first epic you ever loot is logged forever as a worthless
            -- common and never shows up as the best find.
            if entry and entry.quality then
                local unit = E.UnitValue(a) or 0
                local bucketIdx = E.BucketIndex[entry.bucket] or E.BucketIndex.OTHER
                local events = Data.events
                for i = #events, max(1, #events - 200), -1 do
                    local row = events[i]
                    if row and row[2] == a then
                        row[4], row[5], row[6] = entry.quality, bucketIdx, unit
                    end
                end
            end
            E.foldSerial = E.foldSerial + 1
            -- FINDINGS §7.1 says to refresh here, and nothing downstream was
            -- listening: a corpse row stayed "Loading…" and a feed row stayed
            -- a white "?" until some unrelated event happened to repaint.
            if E.lootOpen and E.OnSalvageDirty then E.OnSalvageDirty() end
            if E.OnDataDirty then E.OnDataDirty() end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateRun()
        -- A roll must never be lost to a UI reload.
        if type(_G.GetActiveLootRollIDs) == "function" then
            local ok, active = pcall(_G.GetActiveLootRollIDs)
            if ok and type(active) == "table" then
                for _, rollID in ipairs(active) do
                    local roll = E.AddRoll(rollID, RollTimeLeft(rollID))
                    if roll and not roll.rollTime then roll.unknownDuration = true end
                end
            end
        end
        E.ArmSettle()
    elseif event == "GROUP_ROSTER_UPDATE" then
        E.CheckParty()
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        UpdateRun()
    end
    -- (PLAYER_LOGOUT is handled above. The session segment is deliberately NOT
    -- closed there: RestoreSession resumes the same block after a /reload, so
    -- closing would write one summary per reload for a session that never
    -- ended. Run and farm segments close on their own real boundaries.)
end

-- The FEED is the chat-frame replacement, and D2 R2's promise is that the
-- information moved rather than being deleted. An in-memory-only feed broke
-- that on every /reload, which is exactly when a raider goes looking for it.
function E.RehydrateFeed(limit)
    limit = limit or 120
    local events = Data.events
    -- Coin is interleaved by timestamp so the restored feed reads in the order
    -- it happened and agrees with the header's own gold total.
    local coin = Data.money.log
    local coinIndex = max(1, #coin - limit + 1)
    local from = max(1, #events - limit + 1)
    for i = from, #events do
        local row = events[i]
        if row then
            while coin[coinIndex] and coin[coinIndex][1] <= row[1] do
                FeedPush({ kind = "money", copper = coin[coinIndex][2],
                           t = coin[coinIndex][1], mine = true, restored = true })
                coinIndex = coinIndex + 1
            end
            local itemID, count, quality, srcKind = row[2], row[3], row[4], row[7]
            local entry = E.Meta(itemID)
            FeedPush({
                kind = "item", itemID = itemID, count = count, quality = quality,
                icon = entry and entry.icon, name = entry and entry.name,
                link = entry and entry.link, t = row[1], mine = true,
                srcKind = srcKind, sourceID = row[8],
                sourceName = row[8] and Data.names[row[8]] or nil,
                value = (row[6] or 0) * count, bucket = row[5],
                restored = true,
            })
        end
    end
    while coin[coinIndex] do
        FeedPush({ kind = "money", copper = coin[coinIndex][2],
                   t = coin[coinIndex][1], mine = true, restored = true })
        coinIndex = coinIndex + 1
    end
end

function E.Init()
    LoadData()
    E.Prune()

    session = Commander.RestoreSession(CommanderSpoilsDB, { startedAt = Now() })
    segments.SESSION = {
        id = 0, kind = "session", label = "Session",
        startEpoch = session.startedAt or Now(),
        fromIdx = session.fromIdx or (#Data.events + 1),
    }
    session.fromIdx = segments.SESSION.fromIdx
    session.startedAt = segments.SESSION.startEpoch

    local farm = CommanderSpoilsDB.Farm
    if type(farm) == "table" and farm.fromIdx then
        segments.FARM = {
            id = farm.id, kind = "farm", label = farm.label or "Farm",
            startEpoch = farm.startEpoch, fromIdx = farm.fromIdx, mapID = farm.mapID,
        }
    end

    for _, event in ipairs({
        "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "CHAT_MSG_CURRENCY",
        "BAG_UPDATE_DELAYED", "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED",
        "LOOT_SLOT_CLEARED", "LOOT_SLOT_CHANGED",
        "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "LOOT_ITEM_ROLL_WON",
        "LOOT_BIND_CONFIRM", "CONFIRM_LOOT_ROLL",
        "OPEN_MASTER_LOOT_LIST", "UPDATE_MASTER_LOOT_LIST",
        "LOOT_HISTORY_FULL_UPDATE", "LOOT_HISTORY_ROLL_CHANGED",
        "LOOT_HISTORY_ROLL_COMPLETE",
        "MERCHANT_SHOW", "MERCHANT_CLOSED", "TRADE_SHOW", "TRADE_CLOSED",
        "MAIL_SHOW", "MAIL_CLOSED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
        "PLAYER_EQUIPMENT_CHANGED", "QUEST_TURNED_IN",
        "GET_ITEM_INFO_RECEIVED", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE",
        "ZONE_CHANGED_NEW_AREA", "PLAYER_LOGOUT",
    }) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", OnEvent)

    UpdateRun()
    E.CheckParty()
    E.RehydrateFeed(120)
    Settle()
    E.ready = true
end

E.OnEvent = OnEvent
