-- Commander Armory: the host. Everything in this module that touches the live
-- client lives here -- the world snapshot, the item metadata cache, the bank
-- cache, the swap runner, the combat queue and the one secure button. The
-- engine decides; this file only observes and executes.
--
-- What it deliberately does NOT own: any decision. No sorting, no candidate
-- filtering, no plan ordering, no "can this run" verdict. Those all live in
-- CommanderArmoryEngine so a headless harness can test the sequencer -- the
-- part most likely to carry subtle bugs -- with no mock at all. It also owns
-- no frames except the secure container: CommanderArmoryUI.lua draws every
-- pixel and reads the surface exported near the bottom of this file. And it
-- persists NOTHING transient: run state, the queue and the cursor guard are
-- file-locals, because ItemRack once shipped a release whose only job was
-- deleting in-flight swap state that had been saved and was resurrected on
-- login, wedging the addon before the player touched anything.
--
-- The one constraint that shaped it: there are TWO equip channels and they are
-- not interchangeable. PickupInventoryItem and C_Container.PickupContainerItem
-- are restricted and cannot be called under InCombatLockdown() for ANY slot,
-- weapons included, and C_Item.EquipItemByName in combat picks the item up
-- instead of equipping it -- a 3.3.0 anti-poison-swap change this client
-- inherits, and the mechanical origin of the stuck-cursor class of bug. So out
-- of combat we drive a cursor state machine one action per tick, and in combat
-- the only thing that can move a weapon is a SecureActionButtonTemplate
-- carrying macrotext, fired by a hardware keypress. Everything else queues.

local D = CommanderArmoryData
local E = CommanderArmoryEngine     -- rebound at login; the TOC loads it first
local db

local format = string.format
local tremove = table.remove
local wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

local PREFIX = "|cff66ccffCommander Armory|r: "

-- Key binding labels. Bindings.xml is auto-loaded from the folder and carries
-- only the binding names; these globals are what the Key Bindings panel shows.
-- The CLICK entry has to go through _G because its name is not a valid Lua
-- identifier -- that colon is part of the binding name, not a typo.
BINDING_HEADER_COMMANDERARMORY = "Commander Armory"
BINDING_NAME_COMMANDERARMORY_TOGGLE = "Open the Armory"
_G["BINDING_NAME_CLICK CommanderArmoryEquipWeapons:LeftButton"] =
    "Equip the selected set's weapons (works in combat)"

-- One action per tick. The Bags sorter settled on this cadence for the same
-- reason: items lock in flight, and a faster loop only burns CPU re-reading
-- containers that have not changed yet.
local TICK = 0.1
-- After an action, wait a tick before the next one. ItemRack's own comment
-- calls the equivalent delay the thing that "prevents the 'Internal bag error'
-- from rapid swaps".
local SETTLE_ACTION = 0.1
-- ITEM_LOCK_CHANGED debounce. Several locks change per move, and reacting to
-- each one re-enters the sequencer mid-flight; ItemRack runs a 0.2s timer for
-- exactly this and we match it.
local SETTLE_LOCK = 0.2
-- The watchdog. Treat this as a NORMAL completion path, not a rare safety net:
-- empty slots do not lock at all, so a run made entirely of equips into bare
-- slots produces no lock events whatsoever and finishes on the clock.
local RUN_WATCHDOG = 5
-- GetItemInfo is async. Hammering it for an item the server has not sent yet
-- buys nothing; the real refresh arrives on GET_ITEM_INFO_RECEIVED.
local INFO_BACKOFF = 0.5
-- How long the expensive half of the snapshot (the bag and paperdoll scan) may
-- be reused. The cheap half -- combat, casting, cursor -- is re-read on every
-- call, because the engine's gates hang off exactly those and a half-second-old
-- "not in combat" is a wrong answer.
local SNAPSHOT_TTL = 0.5

local WEAPON_SLOTS = { 16, 17, 18 }

-- ---------------------------------------------------------------------------
-- Theme
--
-- Chrome colours are theme. Data colours are not: item quality is identity and
-- the three paperdoll overlay states carry meaning, so they own their colours
-- and the accent never reaches them.
-- ---------------------------------------------------------------------------

local THEME = {
    font = "Fonts\\ARIALN.TTF",     -- condensed, uniform digit widths

    bg      = { 0.045, 0.055, 0.065, 0.92 },
    chrome  = { 0.09, 0.11, 0.13, 1 },
    edge    = { 0.22, 0.27, 0.31, 1 },
    accent  = { 1.0, 0.72, 0.10 },
    text    = { 0.92, 0.94, 0.95 },
    textDim = { 0.52, 0.58, 0.62 },
    neutral = { 0.6, 0.65, 0.7 },

    -- The three states Blizzard itself distinguishes on a slot, and which the
    -- community complains are conflated. Ignored is an overlay, never
    -- desaturation; desaturation is reserved for locked; broken is the red
    -- tint Blizzard uses (0.9/0/0) and nothing else may wear it.
    ignored = { 0.55, 0.45, 0.85 },
    locked  = { 0.45, 0.45, 0.45 },
    broken  = { 0.90, 0.00, 0.00 },

    -- Provenance and verdict. "In your bank" is the whole product thesis, so
    -- it gets a colour of its own rather than sharing red with "missing".
    bank    = { 0.30, 0.60, 0.95 },
    missing = { 0.90, 0.28, 0.24 },
    ready   = { 0.40, 0.85, 0.45 },
    queued  = { 1.00, 0.82, 0.20 },
}

local ACCENTS = {
    AMBER = { 1.0, 0.72, 0.10 },
    CYAN  = { 0.25, 0.85, 0.95 },
    GREEN = { 0.35, 0.90, 0.40 },
    RED   = { 0.95, 0.35, 0.30 },
    WHITE = { 0.95, 0.95, 0.95 },
}

-- The TopBar soft-fail: Console owns CommanderConsole_Colors, so we read it
-- through ipairs(x or {}) and fall back to our own five keys. A missing
-- Console degrades the accent list, never the module.
local function AccentByKey(key)
    if key == "CLASS" then
        local info = Commander.GetClassInfo and Commander.GetClassInfo()
        if info and info.color then
            -- Copy, never alias: GetClassInfo memoizes that table suite-wide
            return { info.color[1], info.color[2], info.color[3] }
        end
    end
    if ACCENTS[key] then return ACCENTS[key] end
    for _, color in ipairs(CommanderConsole_Colors or {}) do
        if color.value == key and color.r then
            return { color.r, color.g, color.b }
        end
    end
    return ACCENTS.AMBER
end

-- Accent is baked at login. The setter in the DB prints a /reload notice
-- instead of repainting, which is the suite's standing trade: one cold cost
-- against a per-paint colour lookup in every module.
local function ResolveThemeOverrides()
    THEME.accent = AccentByKey(db and db.AccentColor)
end

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local function Say(text)
    print(PREFIX .. text)
end

local function Warn(text)
    print(PREFIX .. "|cffff4433" .. text .. "|r")
end

-- Every db read goes through here. The settings file owns the defaults; this
-- exists so a load-order accident degrades to "the module behaves as if the
-- option were at its default" rather than erroring on a nil index.
local function DB(key, fallback)
    if db == nil then return fallback end
    local value = db[key]
    if value == nil then return fallback end
    return value
end

local function HaveEngine()
    if E and E.PlanSet then return true end
    E = E or CommanderArmoryEngine
    return (E and E.PlanSet) and true or false
end

-- pcall that also reports HOW MANY values came back. Needed because several of
-- this client's item calls are documented MayReturnNothing: on a cache miss
-- they return zero values rather than nil, and `x == nil` cannot tell "the
-- server has not told us yet" from "the answer is no". Counting the returns is
-- the only way to keep those two facts apart.
local function CountedCall(fn, ...)
    local function capture(ok, ...)
        return ok, select("#", ...), ...
    end
    return capture(pcall(fn, ...))
end

-- The per-character store lives in the DB file: CommanderArmory_CharStore()
-- returns { sets = {}, bank = { items = {}, at = 0 }, hidden = {} } with each
-- sub-table repaired independently, so all three are always safe to index. The
-- in-memory twin below is for the case where that file failed entirely -- the
-- module is then merely forgetful rather than broken, which is the suite's rule
-- that a failure costs function and never stability.
local memoryStore
local function CharStore()
    if CommanderArmory_CharStore then
        local ok, store = pcall(CommanderArmory_CharStore)
        if ok and type(store) == "table" then return store end
    end
    memoryStore = memoryStore or {
        sets = {}, hidden = {}, bank = { items = {}, at = 0 }, volatile = true,
    }
    return memoryStore
end

local function MerchantOpen()
    -- A swap with a vendor window open can sell items -- the gear equivalent of
    -- a mis-click on Sell All. We refuse rather than defend (D12).
    return (MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown()) and true or false
end

-- ONE combat predicate, everywhere: InCombatLockdown(). ItemRack used
-- UnitAffectingCombat("player") when enqueuing and InCombatLockdown() when
-- draining, the two disagreed at the edges, and the result was swaps that
-- silently vanished -- fixed in their v4.33. UnitAffectingCombat appears
-- nowhere in this file on purpose, even though the SERVER rule about slots
-- 16/17/18 is phrased in those terms: the client-side restriction on the
-- cursor functions is the tighter of the two and is the one that stops us.
local function InCombat()
    return InCombatLockdown() and true or false
end

-- Bag family. Blizzard only ever spills into family-0 containers, and in TBC
-- that exclusion is load-bearing rather than pedantic: arrows are 1, bullets 2,
-- soul shards 3, and a hunter with two quivers or a warlock with a soul bag has
-- far less usable spill space than the bag count suggests. Counting those slots
-- makes the pre-flight promise a swap it cannot finish -- exactly the failure
-- the whole design exists to prevent -- and putting a displaced item there is
-- ItemRack's oldest bug, fixed in 2005 and still load-bearing.
--
-- GetContainerNumFreeSlots's second return is the authority (it has carried
-- itemFamily since 2.4.0). GetItemFamily on the bag's own inventory item is the
-- fallback for the one case the count call cannot answer.
local function BagFamily(bag)
    local _, family = C_Container.GetContainerNumFreeSlots(bag)
    if family then return family end
    if _G.GetItemFamily and C_Container.ContainerIDToInventoryID and bag > 0 then
        local invID = C_Container.ContainerIDToInventoryID(bag)
        local link = invID and GetInventoryItemLink("player", invID)
        if link then
            local ok, value = pcall(_G.GetItemFamily, link)
            if ok and value then return value end
        end
    end
    return 0
end

local function IsNormalBag(bag)
    return BagFamily(bag) == 0
end

-- ---------------------------------------------------------------------------
-- Item metadata
--
-- Two caches, because the client answers in two speeds. GetItemInfoInstant is
-- synchronous and never nil for a real itemID -- it is what makes a candidate
-- list buildable in one pass with no waiting. GetItemInfo is async, and nil
-- and 0 are DIFFERENT facts: nil means the server has not answered yet and we
-- retry, 0 means the answer is genuinely zero. Conflating them is how you get
-- an item level column that silently reads zero forever.
-- (Pattern lifted from Commander_Spoils/CommanderSpoilsEngine.lua:133-185.)
--
-- Always C_Item.*, never the bare globals: Deprecated_ItemScript.lua defines
-- GetItemInfo and friends only when the loadDeprecationFallbacks CVar is set,
-- so the bare names are a coin flip on this client. And nothing here is ever
-- derived from tooltip text or a fixed tooltip line: ItemRack's PlayerCanWear
-- and IsSoulbound did that and broke on a Blizzard tooltip reformat, quite
-- apart from being unusable in any locale but English.
-- ---------------------------------------------------------------------------

local instant = {}     -- [itemID] = { equipLoc, classID, subClassID, icon, unique... }
local detail = {}      -- [key]    = { name, quality, ilvl, bindOnEquip, stats, ... }
local pendingInfo = {} -- [itemID] = true while the server owes us an answer

local function Instant(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    local entry = instant[itemID]
    if entry then return entry end
    if not (C_Item and C_Item.GetItemInfoInstant) then return nil end
    local _, _, _, equipLoc, icon, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    if not classID then return nil end
    entry = {
        equipLoc = equipLoc, icon = icon,
        classID = classID, subClassID = subClassID,
    }
    instant[itemID] = entry
    return entry
end

-- Unique-equipped, best effort. GetItemUniquenessByID needs the item CACHED, so
-- at login it can simply return nothing -- which is why this retries instead of
-- latching the first answer, and why the pre-flight is backed at runtime by
-- watching UI_ERROR_MESSAGE for ERR_ITEM_UNIQUE_EQUIPPABLE. A curated conflict
-- table would always lag: ItemRack shipped six missing TBC honor gems that
-- silently reintroduced the bug, and TBC's real conflicts are largely gem-driven.
local function ProbeUniqueness(entry, itemID)
    if entry.uniqueKnown then return end
    if not (C_Item and C_Item.GetItemUniquenessByID) then
        entry.uniqueKnown = true
        return
    end
    -- Counted, not nil-tested: GetItemUniquenessByID is MayReturnNothing and a
    -- cache miss comes back with zero values. Latching that as "not unique"
    -- would mark the whole session safe on the first cold read.
    local ok, count, isUnique, _, limitCount, limitID =
        CountedCall(C_Item.GetItemUniquenessByID, itemID)
    if not ok then entry.uniqueKnown = true; return end
    if count == 0 then return end                  -- not cached yet; ask again later
    entry.unique = (isUnique and isUnique ~= 0) and true or false
    entry.uniqueFamily = tonumber(limitID)
    entry.uniqueLimit = tonumber(limitCount)
    entry.uniqueKnown = true
end

-- The durable identity of an item, from the engine. Falling back to a bare
-- itemID when the engine is absent keeps the snapshot shaped correctly even in
-- a broken load; matching then degrades to "same base item", which is exactly
-- what a loose match already means.
local function KeyOf(link)
    if not link then return nil, nil end
    if E and E.ItemKey then
        local ok, key, itemID = pcall(E.ItemKey, link)
        if ok and key then return key, itemID end
    end
    local id = tonumber(link:match("item:(%d+)"))
    return id and tostring(id) or nil, id
end

-- The contract fixes the key layout (itemID:suffixID:enchant:g1:g2:g3:g4) and
-- says to store the base key too, but exposes no accessor for it -- so we cut
-- it off the front of the key rather than re-parsing the link twice. Suffix
-- ids run negative across half the "of the Bear" range, hence the %-? .
local function BaseKeyOf(key, itemID)
    if not key then return nil end
    if E and E.BaseKey then
        local ok, base = pcall(E.BaseKey, key)
        if ok and base then return base end
    end
    return key:match("^(%d+:%-?%d+)") or (itemID and tostring(itemID)) or key
end

-- ---------------------------------------------------------------------------
-- Unique-equipped gems
--
-- The engine can spot two target items socketed with the same gem straight out
-- of the identity key, with no gem table at all -- but on its own that flags
-- EVERY repeat, and in TBC putting the same Living Ruby or Great Dawnstone in
-- four pieces is simply how people gem. Refusing a large slice of legal sets to
-- catch a rare conflict is the wrong trade, so the engine only flags a repeat
-- when the gem id appears in snapshot.uniqueGems, and treats absent or unknown
-- as "let it run".
--
-- isUnique is the signal, not the limit-category fields: TBC's unique-equipped
-- gems (the Ornate PvP series, the Unstable series, the jewelcrafter-only cuts)
-- are flagged per item, and the shared "Jeweler's Gems (3)" category is a WotLK
-- invention that does not exist on this client.
--
-- Best effort by design. An unknown gem is never flagged, and the runtime
-- ERR_ITEM_UNIQUE_EQUIPPABLE watcher is the backstop -- which is the entire
-- reason that watcher exists.
-- ---------------------------------------------------------------------------

local uniqueGems = {}   -- [gemItemID] = true -- the snapshot field; ONLY the yes answers
local gemState = {}     -- [gemItemID] = { known = bool, at = number }
local gemPending = {}   -- [gemItemID] = true while a definite answer is still owed
local keyGems = {}      -- [itemKey] = false | { gemID, ... }, so a key is split once

-- Gems are fields 4..7 of the key -- itemID:suffixID:enchant:g1:g2:g3:g4 per the
-- key contract. Only ever asked about gems actually socketed in gear this
-- character owns, which is a handful rather than the whole gem table.
local function RegisterGems(key)
    if key == nil or keyGems[key] ~= nil then return end
    local fields, n = {}, 0
    for field in (key .. ":"):gmatch("([^:]*):") do
        n = n + 1
        fields[n] = field
    end
    if n < 7 then keyGems[key] = false; return end
    local list
    for i = 4, 7 do
        local gemID = tonumber(fields[i])
        if gemID and gemID > 0 then
            list = list or {}
            list[#list + 1] = gemID
            local state = gemState[gemID]
            if not (state and state.known) then gemPending[gemID] = true end
        end
    end
    keyGems[key] = list or false
end

-- Returns true once the answer is settled and the id can leave the pending set.
local function ProbeGem(gemID)
    local state = gemState[gemID]
    if state and state.known then return true end
    if not (C_Item and C_Item.GetItemUniquenessByID) then
        gemState[gemID] = { known = true }
        return true
    end
    local now = GetTime and GetTime() or 0
    if state and (now - (state.at or 0)) < INFO_BACKOFF then return false end
    state = state or {}
    state.at = now
    gemState[gemID] = state

    -- MayReturnNothing: a cache miss yields ZERO values, not nil. Counting the
    -- returns is what keeps "not cached yet" apart from "not unique" -- latching
    -- the first empty answer would permanently mark every gem as safe, which is
    -- the same retry-rather-than-latch rule ProbeUniqueness follows.
    local ok, count, isUnique = CountedCall(C_Item.GetItemUniquenessByID, gemID)
    if not ok then
        state.known = true
        return true
    end
    if count == 0 then
        if C_Item.RequestLoadItemDataByID then
            pcall(C_Item.RequestLoadItemDataByID, gemID)
        end
        return false
    end
    state.known = true
    if isUnique and isUnique ~= 0 then uniqueGems[gemID] = true end
    return true
end

local function DrainGemProbes()
    -- Clearing the current key inside pairs is legal, and the set is tiny: it
    -- only ever holds gems seen in this character's own gear.
    for gemID in pairs(gemPending) do
        if ProbeGem(gemID) then gemPending[gemID] = nil end
    end
end

-- Async half. Only ever called with a real link, because a suffixed item's
-- name, quality and item level all differ from the base item's and looking
-- them up by id would quietly report the wrong ones.
local function Detail(key, link, itemID)
    if not key then return nil end
    local entry = detail[key]
    if not entry then
        entry = { link = link, itemID = itemID }
        detail[key] = entry
    end
    entry.link = entry.link or link

    local fast = itemID and instant[itemID]
    if entry.name and entry.statsDone and (not fast or fast.uniqueKnown) then return entry end

    local now = GetTime and GetTime() or 0
    if entry.probedAt and (now - entry.probedAt) < INFO_BACKOFF then return entry end
    entry.probedAt = now

    if fast then ProbeUniqueness(fast, itemID) end

    if C_Item and C_Item.GetItemInfo then
        local name, _, quality, ilvl, _, _, _, _, _, _, _, _, _, bindType =
            C_Item.GetItemInfo(link or itemID)
        if name then
            entry.name, entry.quality = name, quality
            entry.ilvl = ilvl
            -- bindType 2 is Bind on Equip, and it is the only reason a run
            -- ever stops to ask a question (EQUIP_BIND_CONFIRM).
            entry.bindOnEquip = (bindType == 2)
            if itemID then pendingInfo[itemID] = nil end
        elseif itemID and not pendingInfo[itemID] then
            pendingInfo[itemID] = true
            if C_Item.RequestLoadItemDataByID then
                pcall(C_Item.RequestLoadItemDataByID, itemID)
            end
        end
    end

    -- The precise item level. GetItemInfo's 4th return is the base item's,
    -- which is wrong for anything suffixed; GetDetailedItemLevelInfo takes the
    -- link. C_Item.GetCurrentItemLevel would also do it but needs a live
    -- ItemLocation, and half our rows are cached bank entries with no location
    -- to build -- so this is the one that works for every row we have.
    if link and C_Item and C_Item.GetDetailedItemLevelInfo then
        local ok, actual = pcall(C_Item.GetDetailedItemLevelInfo, link)
        if ok and actual and actual > 0 then entry.ilvl = actual end
    end

    -- GetItemStats is the ONLY stat primitive on this client -- there is no
    -- C_Item version on any flavor and no comparison helper. Memoized by key
    -- and never recomputed, because it allocates a fresh table per call and
    -- the engine reads it once per diff. Callers must treat it as read-only.
    --
    -- statsDone rather than a nil check on stats: a shirt or a tabard answers
    -- with an EMPTY table, which is a real answer, and testing the result alone
    -- would re-ask for every stat-less item on every probe forever.
    if not entry.statsDone and link and _G.GetItemStats then
        local ok, stats = pcall(_G.GetItemStats, link)
        if ok and type(stats) == "table" then
            entry.statsDone = true
            if next(stats) then entry.stats = stats end
        end
    end
    return entry
end

-- Everything the snapshot and the UI need about one item, in one call.
local function ItemMeta(link)
    if not link then return nil end
    local key, itemID = KeyOf(link)
    if not itemID then return nil end
    local fast = Instant(itemID)
    if not fast then return nil end
    -- Warmed here rather than in MakeRow so the bank-cache filter pass, which
    -- calls ItemMeta and builds no row, still teaches us its gems.
    RegisterGems(key)
    local slow = Detail(key, link, itemID)
    return key, itemID, fast, slow
end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------

-- Fresh table per row, deliberately. Rows escape into the engine (as diff.found
-- and as the candidate the flyout hands back to EquipSingle) and into the UI,
-- and a pooled table would change identity under a holder between two paints.
local function MakeRow(link, where, bag, slot, stale)
    local key, itemID, fast, slow = ItemMeta(link)
    if not fast then return nil end
    return {
        key = key,
        baseKey = BaseKeyOf(key, itemID),
        itemID = itemID,
        link = link,
        name = slow and slow.name,
        icon = fast.icon,
        quality = slow and slow.quality,
        ilvl = slow and slow.ilvl,
        equipLoc = fast.equipLoc,
        classID = fast.classID,
        subClassID = fast.subClassID,
        unique = fast.unique,
        uniqueFamily = fast.uniqueFamily,
        bindOnEquip = slow and slow.bindOnEquip,
        stats = slow and slow.stats,
        where = where,
        bag = bag,
        slot = slot,
        stale = stale or nil,
    }
end

-- Could this item ever occupy an equipment slot we model? Anything with no
-- equip-loc mapping (bags, quivers, consumables) is not inventory as far as
-- this module is concerned, and ammo is excluded by name because slot 0 sits
-- outside the whole set model.
local function IsEquippable(equipLoc)
    if not equipLoc or equipLoc == "" then return false end
    if equipLoc == "INVTYPE_AMMO" then return false end
    local slots = D.EquipLocSlots[equipLoc]
    return slots ~= nil and slots[1] ~= nil and slots[1] ~= 0
end

-- ---------------------------------------------------------------------------
-- The bank cache
--
-- The API returns nothing for bank containers once BANKFRAME_CLOSED fires, so
-- without a cache "in your bank" and "gone" are the same answer -- which is
-- precisely Blizzard's red set name, and precisely the hole this module exists
-- to fill. We snapshot on BANKFRAME_OPENED and keep it.
--
-- NEVER Enum.BagIndex.BankBag_1: the shared enum is the mainline one, where
-- ReagentBag = 5 pushes BankBag_1 to 6, and reading bag 6 as the first bank bag
-- silently caches the wrong containers. Bank bags are NUM_BAG_SLOTS+1 ..
-- NUM_BAG_SLOTS+NUM_BANKBAGSLOTS, which is 5..11 here.
--
-- This module WITHDRAWS and never deposits. ItemRack's documented default --
-- clicking a set with the bank open deposits the whole set -- is one of its
-- most complained-about behaviours, patched later with a shift-click override.
-- Here a click with the bank open equips, with no modifier, and there is no
-- code path anywhere in this file that puts an item into a bank container.
-- ---------------------------------------------------------------------------

local bankOpen = false

local function ScanBankContainer(bagID, rows)
    local n = C_Container.GetContainerNumSlots(bagID) or 0
    for slot = 1, n do
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        local link = info and info.hyperlink
        if link then
            local _, _, fast = ItemMeta(link)
            -- Filtered at cache time, not at read time: the bank holds mostly
            -- reagents and the SavedVariable would be an order of magnitude
            -- bigger for rows the module can never act on. GetItemInfoInstant
            -- is synchronous, so this costs nothing and cannot mis-file an
            -- item that had not loaded yet.
            if fast and IsEquippable(fast.equipLoc) then
                rows[#rows + 1] = { link = link, bag = bagID, slot = slot }
            end
        end
    end
end

local function BankContainers()
    local first = (NUM_BAG_SLOTS or 4) + 1
    return first, first + (NUM_BANKBAGSLOTS or 7) - 1
end

local function ScanAllBankContainers(rows)
    ScanBankContainer(BANK_CONTAINER or -1, rows)
    local first, last = BankContainers()
    for bag = first, last do ScanBankContainer(bag, rows) end
    return rows
end

local function CacheBank()
    local store = CharStore()
    store.bank = store.bank or { items = {}, at = 0 }
    store.bank.items = ScanAllBankContainers({})
    store.bank.at = time()
end

-- ---------------------------------------------------------------------------
-- The snapshot
--
-- One flat, plain table -- no metatables, no closures -- so the harness can
-- write one by hand. Rebuilt in two halves at two speeds: the paperdoll and
-- bag scan is expensive and only changes on an event, while combat, casting
-- and the cursor are the engine's gates and a half-second-stale answer there
-- is a wrong answer.
-- ---------------------------------------------------------------------------

local snapshot = {
    equipped = {},
    inventory = {},
    freeSlots = {},
    uniqueGems = uniqueGems,
}
local heavyAt, heavyDirty = 0, true
local playerClass

local function Invalidate()
    heavyDirty = true
end

local function ScanFreeBagSlots(list)
    wipe(list)
    local total = 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local free, family = C_Container.GetContainerNumFreeSlots(bag)
        -- Second return, not a bag-type table of our own. Only family 0 counts.
        if free and free > 0 and (family or BagFamily(bag)) == 0 then
            total = total + free
            local ok, slots = pcall(C_Container.GetContainerFreeSlots, bag)
            if ok and type(slots) == "table" then
                for _, s in ipairs(slots) do
                    list[#list + 1] = { bag = bag, slot = s }
                end
            else
                local n = C_Container.GetContainerNumSlots(bag) or 0
                for s = 1, n do
                    if not C_Container.GetContainerItemInfo(bag, s) then
                        list[#list + 1] = { bag = bag, slot = s }
                    end
                end
            end
        end
    end
    return total
end

-- Live, not from the cached snapshot: a plan's destination can be consumed by
-- an earlier action in the same run, and reusing a stale coordinate drops the
-- item into an occupied slot, which the client refuses silently.
local function FirstFreeBagSlot()
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local free = C_Container.GetContainerNumFreeSlots(bag)
        if free and free > 0 and IsNormalBag(bag) then
            local n = C_Container.GetContainerNumSlots(bag) or 0
            for s = 1, n do
                if not C_Container.GetContainerItemInfo(bag, s) then return bag, s end
            end
        end
    end
    return nil, nil
end

local function ScanEquipped(into)
    wipe(into)
    -- 1..19. Slot 0 is ammo and never appears: it is a depleting consumable,
    -- PickupInventoryItem(0) does not work, and "restore exactly this" is the
    -- wrong verb for it. (The paperdoll display reads it through AmmoInfo.)
    for slotID = D.FIRST_SLOT, D.LAST_SLOT do
        local link = GetInventoryItemLink("player", slotID)
        if link then
            local row = MakeRow(link, nil, nil, nil, nil)
            if row then
                row.slotID = slotID
                row.locked = IsInventoryItemLocked(slotID) and true or false
                row.broken = GetInventoryItemBroken("player", slotID) and true or false
                into[slotID] = row
            end
        end
    end
end

local function ScanBags(into)
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local n = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local link = info and info.hyperlink
            if link then
                local _, _, fast = ItemMeta(link)
                if fast and IsEquippable(fast.equipLoc) then
                    local row = MakeRow(link, "BAGS", bag, slot, nil)
                    if row then
                        row.locked = info.isLocked and true or false
                        -- Broken gear can still be equipped -- it just gives no
                        -- stats -- so this is a warning flag, never a filter.
                        local dur, maxDur = C_Container.GetContainerItemDurability(bag, slot)
                        row.broken = (maxDur and maxDur > 0 and dur == 0) and true or false
                        into[#into + 1] = row
                    end
                end
            end
        end
    end
end

-- Bank rows. Live while the bank is open, cached otherwise -- and cached rows
-- are flagged stale, because the engine is allowed to REPORT from them ("it is
-- in your bank") but never to PLAN from them.
local function ScanBankRows(into)
    if bankOpen then
        for _, entry in ipairs(ScanAllBankContainers({})) do
            local row = MakeRow(entry.link, "BANK", entry.bag, entry.slot, nil)
            if row then
                local info = C_Container.GetContainerItemInfo(entry.bag, entry.slot)
                row.locked = (info and info.isLocked) and true or false
                into[#into + 1] = row
            end
        end
        return
    end
    local bank = CharStore().bank
    for _, entry in ipairs((bank and bank.items) or {}) do
        local row = MakeRow(entry.link, "BANK", entry.bag, entry.slot, true)
        if row then into[#into + 1] = row end
    end
end

local function RebuildHeavy()
    if not playerClass then
        local _, token = UnitClass("player")
        playerClass = token or "UNKNOWN"
    end
    snapshot.playerClass = playerClass

    -- CanDualWield is not exercised by any TBC-loaded FrameXML file, so it is
    -- probed rather than trusted. The fallback asks the question a different
    -- way: OffhandHasWeapon is confirmed live here, and a weapon already worn
    -- in slot 17 is proof of the skill. A class that can learn it but has not
    -- yet reads false, which merely hides an option it could not use anyway.
    local canDW
    if _G.CanDualWield then
        local ok, value = pcall(_G.CanDualWield)
        if ok then canDW = value and true or false end
    end
    if canDW == nil and C_PaperDollInfo and C_PaperDollInfo.OffhandHasWeapon then
        local ok, value = pcall(C_PaperDollInfo.OffhandHasWeapon)
        if ok then canDW = value and true or false end
    end
    snapshot.canDualWield = canDW and true or false

    -- Slot 18 wears three faces and has one id. UnitHasRelicSlot is the fact;
    -- the class table only names WHICH relic subclass, so a paladin's flyout
    -- never offers idols.
    local hasRelic = false
    if _G.UnitHasRelicSlot then
        local ok, value = pcall(_G.UnitHasRelicSlot, "player")
        if ok then hasRelic = value and true or false end
    end
    snapshot.hasRelicSlot = hasRelic
    snapshot.relicSubclass = hasRelic and D.RelicSubclass[playerClass] or nil

    ScanEquipped(snapshot.equipped)
    wipe(snapshot.inventory)
    ScanBags(snapshot.inventory)
    -- Unconditional, and FlyoutShowBank deliberately does not reach here.
    -- That option is about what the flyout LISTS; the snapshot is what the
    -- planner and the pre-flight resolve against, so gating the scan on it
    -- turned "it is in your bank" back into "missing" -- the one dead end this
    -- module exists to convert into an instruction (D9). The display filters
    -- live where display decisions belong: Candidates() below, and the UI's own.
    ScanBankRows(snapshot.inventory)
    snapshot.freeBagSlots = ScanFreeBagSlots(snapshot.freeSlots)

    -- Every row above has registered its gems by now, so this asks about
    -- exactly the ones that are socketed in gear this character owns. The table
    -- is shared by reference and only ever grows -- it holds the YES answers,
    -- so an id that is absent is either not unique or not yet known, and the
    -- engine treats both the same way: do not flag it.
    DrainGemProbes()
    snapshot.uniqueGems = uniqueGems
end

local function RefreshVolatile(now)
    snapshot.now = now
    snapshot.inCombat = InCombat()
    snapshot.casting = (UnitCastingInfo and UnitCastingInfo("player")) ~= nil
    snapshot.dead = (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) and true or false
    snapshot.atBank = bankOpen
    snapshot.merchant = MerchantOpen()
    snapshot.cursorBusy = (CursorHasItem() or (SpellIsTargeting and SpellIsTargeting()))
        and true or false
end

local function Snapshot()
    local now = GetTime()
    if heavyDirty or (now - heavyAt) > SNAPSHOT_TTL then
        RebuildHeavy()
        heavyAt, heavyDirty = now, false
    end
    RefreshVolatile(now)
    return snapshot
end

-- The conditions under which nothing scripted can move an item. Kept in one
-- place because the queue, the pre-flight and the executor all need the same
-- answer, and a drift between them is a run that half-starts.
local function Blocked(snap)
    return snap.inCombat or snap.casting or snap.dead
end

-- The cursor is a poison pill. An item left on it blocks every future swap, and
-- that is the mechanism behind the incumbent's most-reported "swap stopped"
-- reports. Sweeping is safe -- ClearCursor returns the item where it came from
-- -- and Blizzard's own equip sequence opens with it. Only ever swept while we
-- are about to act, never idly, so a player mid-drag is left alone.
local function SweepCursor()
    if InCombat() then return false end
    if CursorHasItem() then ClearCursor() end
    return not CursorHasItem()
end

-- ---------------------------------------------------------------------------
-- Item location, resolved late
--
-- ItemRack issue #317 -- "Item does not go in that slot", reproducible by
-- re-sorting your bags -- is exactly this bug: the addon kept the bag and slot
-- it saw at plan time and later tried to equip from a position that no longer
-- held what it believed. A plan can be seconds old and a run spans several
-- passes, so every source coordinate is re-verified against the item KEY
-- immediately before the cursor touches it, and re-found when it has moved.
-- ---------------------------------------------------------------------------

local function MatchesAt(bag, slot, key, itemID)
    local info = bag and slot and C_Container.GetContainerItemInfo(bag, slot)
    local link = info and info.hyperlink
    if not link then return false end
    local rowKey, rowID = KeyOf(link)
    if key then return rowKey == key end
    return itemID ~= nil and rowID == itemID
end

local function SearchContainers(first, last, key, itemID, loose)
    for bag = first, last do
        local n = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local link = info and info.hyperlink
            if link then
                local rowKey, rowID = KeyOf(link)
                if (not loose and key and rowKey == key)
                    or (loose and itemID and rowID == itemID) then
                    return bag, slot
                end
            end
        end
    end
end

-- Bags first at the exact key, then bags at the base item id -- an
-- identically-decorated copy is a legitimate substitute and the engine already
-- reports which kind of match it used.
local function ResolveBagSource(bag, slot, key, itemID)
    if MatchesAt(bag, slot, key, itemID) then return bag, slot end
    local last = NUM_BAG_SLOTS or 4
    local b, s = SearchContainers(0, last, key, itemID, false)
    if b then return b, s end
    return SearchContainers(0, last, key, itemID, true)
end

local function ResolveBankSource(bag, slot, key, itemID)
    if not bankOpen then return nil end
    if MatchesAt(bag, slot, key, itemID) then return bag, slot end
    local first, last = BankContainers()
    local b, s = SearchContainers(BANK_CONTAINER or -1, BANK_CONTAINER or -1, key, itemID, false)
    if b then return b, s end
    b, s = SearchContainers(first, last, key, itemID, false)
    if b then return b, s end
    b, s = SearchContainers(BANK_CONTAINER or -1, BANK_CONTAINER or -1, key, itemID, true)
    if b then return b, s end
    return SearchContainers(first, last, key, itemID, true)
end

-- ---------------------------------------------------------------------------
-- Pawn (OptionalDep)
--
-- We ship no stat weights of our own -- TBC theorycrafting is contentious
-- enough that we would be wrong for half the specs. Pawn already carries the
-- argument, so when it is present we borrow its number and offer a SCORE sort;
-- when it is not, the option simply is not there.
-- ---------------------------------------------------------------------------

local function PawnScorer()
    if not _G.PawnGetItemData then return nil end
    return function(row)
        if not row or not row.link then return nil end
        local ok, item = pcall(_G.PawnGetItemData, row.link)
        if not ok or type(item) ~= "table" then return nil end
        local values = item.Values
        -- Values are absent on a cold read, and on the Classic flavors Pawn
        -- deliberately hands back an item whose values it has not computed yet.
        -- PawnRecalculateItemValuesIfNecessary is the documented way to finish
        -- the job and takes the item table we already hold; PawnGetAllItemValues
        -- does NOT -- its first parameter is the STATS table, so calling it with
        -- the item scores every row against nothing and silently returns none.
        if not values and _G.PawnRecalculateItemValuesIfNecessary then
            local vok, computed = pcall(_G.PawnRecalculateItemValuesIfNecessary, item)
            values = vok and computed or nil
        end
        if not values and _G.PawnGetAllItemValues then
            local vok, computed = pcall(_G.PawnGetAllItemValues, item.Stats, item.Level,
                item.SocketBonusStats, item.UnenchantedStats, item.UnenchantedSocketBonusStats)
            values = vok and computed or nil
        end
        if type(values) ~= "table" then return nil end
        -- entry = { scaleName, enchantedValue, unenchantedValue, localizedName }.
        -- The enchanted value is the one to sort on: the row is a real item the
        -- player owns, enchant and all, and that is what the flyout is comparing.
        local best
        for _, entry in ipairs(values) do
            local scaleName, value = entry[1], entry[2]
            if type(value) == "number" then
                -- Pawn already omits disabled scales, so this is belt and
                -- braces against a future build that does not.
                local visible = true
                if _G.PawnIsScaleVisible then
                    local vok, isVisible = pcall(_G.PawnIsScaleVisible, scaleName)
                    visible = (not vok) or (isVisible and true or false)
                end
                if visible and (not best or value > best) then best = value end
            end
        end
        return best
    end
end

-- ---------------------------------------------------------------------------
-- Sets, selection, and the ignore scratchpad
-- ---------------------------------------------------------------------------

local selectedIndex = 0
local ignoreScratch = {}    -- [slotKey] = true, the live editing state
local ignoreTouched = false -- ignore can change while a set is fully equipped,
                            -- which is the one case that must re-enable Save

local function Sets()
    return CharStore().sets
end

local function SelectedSet()
    return Sets()[selectedIndex]
end

-- Selecting a set loads its flags into the scratchpad. A slot with no entry at
-- all counts as IGNORED, which is what makes a half-authored set safe by
-- default and means adding a slot to the canon later cannot retroactively
-- strip anybody's gear.
local function LoadIgnoreScratch(set)
    wipe(ignoreScratch)
    ignoreTouched = false
    if not set then return end
    -- A set with NO entries at all is not a half-authored set, and the
    -- no-entry-means-IGNORED rule reads the wrong way round for it: every slot
    -- came back ignored, so the first Save captured a set that touches nothing
    -- and /cgear save <newname> produced a set that did precisely nothing.
    -- The rule protects entries somebody wrote; there are none here.
    --
    -- A NEW set no longer takes this path: E.NakedSet writes nineteen real
    -- entries, so the loop below runs and reports exactly what the naked set
    -- says -- shirt and tabard hands-off, and nothing else. The guard stays for
    -- an entryless set from an older saved file, where it is still the only
    -- honest reading.
    if not set.entries or next(set.entries) == nil then return end
    for _, slot in ipairs(D.Slots) do
        local entry = set.entries[slot.key]
        if not entry or entry.state == "IGNORED" then
            ignoreScratch[slot.key] = true
        end
    end
end

-- The scratchpad belongs to the SELECTED set and to no other. Handing it to a
-- plan for a different set applies one kit's exclusions to another's: select a
-- two-slot hit-swap (seventeen slots ignored), type /cgear equip pve, and the
-- fifteen-piece set plans two slots, announces success, and leaves thirteen
-- pieces of the wrong kit on. Every other set already carries its exclusions in
-- its own IGNORED entries, which is what the engine reads when opts.ignore is
-- absent -- so the honest answer for anything unselected is to say nothing.
local function PlanOpts(set)
    if set and set == SelectedSet() then return { ignore = ignoreScratch } end
    return nil
end

-- Capture needs the same rule and cannot express it the same way. CaptureSet
-- reads NOTHING out of the set it is filling -- opts.ignore is the only thing
-- deciding which slots stay IGNORED -- so "pass nil and let the set speak for
-- itself" would quietly strip an unselected set's exclusions every time it was
-- saved. Its flags are read back out of its own entries instead.
local ignoreFromSet = {}
local function IgnoreForCapture(set)
    if set and set == SelectedSet() then return ignoreScratch end
    local entries = set and set.entries
    if not entries or next(entries) == nil then return nil end
    wipe(ignoreFromSet)
    for _, slot in ipairs(D.Slots) do
        local entry = entries[slot.key]
        if not entry or entry.state == "IGNORED" then ignoreFromSet[slot.key] = true end
    end
    return ignoreFromSet
end

-- The DATA moved. That is a different verb from "a setting moved", and the UI
-- file draws the same distinction at its own Refresh/Apply pair -- so this
-- calls Refresh directly instead of firing the suite event, which is what the
-- DB file fires when a SETTING changes and what the UI therefore answers with a
-- full Apply. Routing data through the bus conflated the two, and a fifteen-slot
-- swap then paid for fifteen restyles, tab rebuilds and paperdoll/bag/bank
-- rescans while the run was still mid-flight.
local function Notify()
    if CommanderArmoryUI and CommanderArmoryUI.Refresh then
        pcall(CommanderArmoryUI.Refresh)
        return
    end
    -- No interface file: fall back to the bus so a broken load still gets the
    -- word out to anything else listening.
    if Commander and Commander.Notify and COMMANDER_ARMORY_EVENTS then
        Commander.Notify(COMMANDER_ARMORY_EVENTS.UPDATE)
    end
end

-- ---------------------------------------------------------------------------
-- The secure channel
--
-- Protection propagates UPWARD: any frame CONTAINING a SecureActionButton is
-- itself protected, and Show/Hide/SetSize on it are then blocked in combat even
-- with no secure template in sight. So the button lives in a container parented
-- to UIParent and pinned to the UI's panel as a SIBLING, never a child -- the
-- price being that scale and frame level no longer inherit and have to be
-- mirrored per draw. The Party Frames board paid for this rule once already:
-- as a child, a member joining mid-fight made the rows outgrow a frame that
-- could not follow them.
-- ---------------------------------------------------------------------------

local secureHost, secureButton
local secureDirty = true
local lastSecureClick = 0

local function MacroIdentifierFor(entry)
    -- The macro parser matches on name; an item string is the fallback for the
    -- window before GetItemInfo has answered. Suffix variants share a name and
    -- the macro cannot tell them apart -- an acceptable loss for the one path
    -- that works at all in combat.
    if entry.name and entry.name ~= "" then return entry.name end
    if entry.itemID then return "item:" .. entry.itemID end
    return nil
end

-- Attributes may only be written out of combat, so the macrotext is compiled
-- whenever the selection or its weapon entries change -- never at click time,
-- when it is already too late.
local function UpdateSecure()
    if not secureButton then return end
    if InCombat() then secureDirty = true; return end
    secureDirty = false

    local set = SelectedSet()
    local lines = {}
    if set and set.entries then
        for _, slotID in ipairs(WEAPON_SLOTS) do
            local slot = D.SlotByID[slotID]
            local entry = slot and set.entries[slot.key]
            if entry and entry.state == "ITEM" then
                local ident = MacroIdentifierFor(entry)
                if ident then
                    -- /equipslot exists on this client; /equipset does not.
                    -- The [combat] conditional makes the macro a no-op out of
                    -- combat on purpose: out there PostClick runs the whole set
                    -- through the cursor path, so one key means "wear this set"
                    -- everywhere it can mean anything at all.
                    lines[#lines + 1] = format("/equipslot [combat] %d %s", slotID, ident)
                end
            end
        end
    end
    secureButton:SetAttribute("macrotext", table.concat(lines, "\n"))
    secureButton.armorySet = set and set.name or nil
end

-- Deliberately NOT mirrored onto the UI's panel, and this is the second half of
-- the rule the section header states rather than an omission. Protection
-- propagates upward, so secureHost is itself protected: ClearAllPoints,
-- SetAllPoints, SetFrameStrata, SetFrameLevel and SetScale on it are all
-- blocked under InCombatLockdown(). Any re-anchor helper is therefore a
-- combat-taint bug waiting for a caller -- and the caller was going to be
-- Apply(), which runs off PLAYER_EQUIPMENT_CHANGED, i.e. exactly the event an
-- in-combat weapon swap fires. Every such swap would have thrown
-- ADDON_ACTION_BLOCKED. The off-screen park below needs none of it: the button
-- is fired by a hardware keypress through a CLICK binding and is never drawn,
-- so where it sits and what it inherits are questions with no consequences.

local EquipSet   -- forward: PostClick runs the out-of-combat path

local function BuildSecure()
    secureHost = CreateFrame("Frame", "CommanderArmorySecureHost", UIParent)
    secureHost:SetSize(1, 1)
    -- Parked OFF-SCREEN, not at CENTER. This button exists to be fired by a
    -- hardware keypress through a CLICK binding and is never meant to be
    -- clicked directly, so a 1px hit target sitting at the exact middle of the
    -- screen is pure downside: it would silently swallow a click on whatever is
    -- behind it. It stays SHOWN because that is the state ItemRack's equivalent
    -- buttons are in on this same client and the in-combat weapon swap is the
    -- one path with no fallback -- not the place to economise on a guess.
    -- It is anchored here once, at login, and never moved again; see above.
    secureHost:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -512, -512)

    secureButton = CreateFrame("Button", "CommanderArmoryEquipWeapons", secureHost,
        "SecureActionButtonTemplate")
    secureButton:SetSize(1, 1)
    secureButton:SetPoint("CENTER", secureHost, "CENTER", 0, 0)
    -- Belt and braces with the off-screen park: a binding-driven Click() does
    -- not need mouse input enabled, so refusing the mouse costs nothing and
    -- removes the last way this can intercept something.
    secureButton:EnableMouse(false)
    secureButton:SetAttribute("type", "macro")
    secureButton:SetAttribute("macrotext", "")
    -- BOTH phases. The ActionButtonUseKeyDown CVar decides which edge a bound
    -- key delivers, and registering one of them means the swap is silently
    -- ignored for half the playerbase -- ItemRack-Anniversary shipped a fix
    -- reading exactly that. The out-of-combat path below de-duplicates the
    -- doubled PostClick that this costs us.
    secureButton:RegisterForClicks("AnyDown", "AnyUp")
    secureButton:SetScript("PostClick", function()
        -- In combat the macro did the work and insecure code must not touch a
        -- frame; just mark the world dirty so the next paint is honest.
        Invalidate()
        if InCombat() then return end
        local now = GetTime()
        if now - lastSecureClick < 0.3 then return end
        lastSecureClick = now
        local set = SelectedSet()
        if set and EquipSet then EquipSet(set) end
    end)
end

-- ---------------------------------------------------------------------------
-- The combat queue
--
-- Converting TBC's most common failure -- "nothing happened" -- into a
-- scheduled action is the cheapest big win available. A queued swap is
-- announced, is readable from the UI, and can be cancelled. It lives in a
-- file-local and is never written to a SavedVariable: a persisted queue that
-- survives a client restart is the incumbent's wedged-on-login bug.
--
-- Keyed by slot rather than a flat list, so pressing the same slot twice
-- replaces the intent instead of stacking two contradictory ones; a whole-set
-- request supersedes every per-slot request, because it already speaks for them.
-- ---------------------------------------------------------------------------

local queue = { set = nil, slots = {} }

-- Counted, never accumulated. The count used to be a field that every mutation
-- site had to maintain by hand, and one of them -- the slot swap that replaces a
-- queued whole-set -- cleared the set without decrementing. After that the count
-- never reached zero again: the ticker re-entered the drain every 0.1s and built
-- a complete paperdoll-plus-bag-plus-bank snapshot for an empty loop, IsQueued()
-- reported true forever, and the pane showed a queued swap that did not exist.
-- Nineteen slots plus a set is not a table worth risking that to avoid walking.
local function QueueCount()
    local n = queue.set and 1 or 0
    for _ in pairs(queue.slots) do n = n + 1 end
    return n
end

local function QueueEmpty()
    return queue.set == nil and next(queue.slots) == nil
end

local function QueueClear()
    queue.set = nil
    wipe(queue.slots)
end

local function QueueDescribe()
    if queue.set then return format("set \"%s\"", queue.set.name or "?") end
    local n = QueueCount()
    if n == 1 then
        for slotID in pairs(queue.slots) do return D.SlotLabel(slotID) end
    end
    if n > 1 then return format("%d slots", n) end
    return nil
end

-- ---------------------------------------------------------------------------
-- Candidate references
--
-- E.Candidates hands back POOLED rows -- candPool[index], rewritten in place on
-- every call, which the engine documents as scratch. Anything the host keeps
-- past the current frame therefore keeps IDENTITY, not the row: a queued swap
-- can sit through a whole fight, and opening one more flyout in the meantime
-- would otherwise re-point the entry at whatever landed at the same pool index.
-- Two rings in two flyouts is the quiet version of that bug -- the queue drains
-- and equips the other ring, with no error anywhere.
-- ---------------------------------------------------------------------------

local function CandidateRef(row)
    if not row then return nil end
    return {
        key = row.key, baseKey = row.baseKey, itemID = row.itemID,
        name = row.name, where = row.where, fromSlot = row.fromSlot,
        bag = row.bag, slot = row.slot,
    }
end

-- The live row for a reference, out of a fresh snapshot. Exact key first, then
-- the base item -- the same exact-then-loose rule the planner uses, so a
-- re-enchanted copy is still a legitimate substitute and nothing else is.
-- Returns nil when the item is gone, which callers must NOT read as "the player
-- asked for an empty slot": that is the difference between dropping a stale
-- swap and stripping a slot nobody asked to strip.
local function ResolveRef(ref, snap)
    if not ref then return nil end
    if ref.where == "EQUIPPED" then
        local worn = ref.fromSlot and snap.equipped[ref.fromSlot]
        if not worn then return nil end
        if ref.key and worn.key ~= ref.key then return nil end
        -- PlanSingle reads `where`/`fromSlot`/`source` off a candidate and the
        -- snapshot's own equipped row carries none of them. Writing them INTO
        -- that row would teach every other reader that a worn item lives
        -- somewhere else, so the wrapper is ours and the snapshot stays clean.
        local wrap = { where = "EQUIPPED", fromSlot = ref.fromSlot, source = worn }
        for field, value in pairs(worn) do
            if wrap[field] == nil then wrap[field] = value end
        end
        return wrap
    end
    local loose
    for _, row in ipairs(snap.inventory) do
        if ref.key and row.key == ref.key then return row end
        if not loose and ref.baseKey and row.baseKey == ref.baseKey then loose = row end
    end
    return loose
end

local function WeaponsOnly(set)
    if not set or not set.entries then return false end
    for _, slot in ipairs(D.Slots) do
        local entry = set.entries[slot.key]
        if entry and entry.state ~= "IGNORED" and not D.IsEquipableInCombat(slot.id) then
            return false
        end
    end
    return true
end

local function AnnounceQueued(snap)
    local what = QueueDescribe()
    if not what then return end
    local why = snap.dead and "you are dead"
        or (snap.inCombat and "you are in combat")
        or (snap.casting and "you are casting")
        -- A vendor window is a refusal, not a wait (D12) -- but once the swap is
        -- already queued it is honest to name it, because the queue does drain
        -- when the window closes.
        or (snap.merchant and "a vendor window is open")
        or "the client will not allow it yet"
    Say(format("queued %s -- %s. It goes on the moment that changes (/cgear to cancel).",
        what, why))
    if queue.set and WeaponsOnly(queue.set) and snap.inCombat then
        Say("|cff777777That set is weapons only, so a key bound to the Armory swap button can do it now.|r")
    end
end

-- ---------------------------------------------------------------------------
-- The runner
--
-- One action per tick against the real API, with the engine deciding what the
-- next action is after every result. Multi-pass is the normal path, not the
-- exception: a fifteen-slot swap cannot complete in one pass because items lock
-- while in flight.
--
-- The CLOCK is the ticker, not ITEM_LOCK_CHANGED. Empty slots do not lock at
-- all and the event does not fire during ammo pickups, so a run of equips into
-- bare slots emits no lock events whatsoever -- gating progress on observing
-- one would hang it forever. The lock event is an optimisation that tells us
-- when to stop waiting; PLAYER_EQUIPMENT_CHANGED and BAG_UPDATE feed the same
-- role, and the watchdog closes the case where none of the three arrive.
-- ---------------------------------------------------------------------------

local run
local settleUntil = 0
local runState = {
    active = false,
    status = "IDLE",
    kind = nil, label = nil,
    total = 0, done = 0, failed = 0,
    wait = nil, paused = nil,
    reasons = nil,
    lastError = nil, lastErrorID = nil, uniqueConflict = nil,
    startedAt = 0, progressAt = 0,
}

-- What the run is FOR, kept apart from what it is DOING. Enough to re-plan it
-- from a fresh snapshot (D16: re-planning, not the watchdog, is the robustness
-- mechanism) and enough to hand the remainder to the combat queue if the world
-- stops allowing it half way through.
local runCtx = { kind = nil, set = nil, slotID = nil, ref = nil }
local runWithdrew = false
local runPass = 1
-- Two passes is the bank case (withdraw, then equip); a third is slack for a
-- lock that pushed one action into a pass of its own. Beyond that something is
-- wrong that another pass will not fix, and an unbounded re-plan loop on a
-- ticker is a client freeze rather than a bug report.
local MAX_PASSES = 3

local ReportRefusal   -- forward: a blocked second pass has to say why

-- A queued swap is a SCHEDULED action, not a failed one, and the run state has
-- to say so in the same vocabulary the chat line uses -- otherwise the pane
-- keeps showing whatever the last run ended as while the module is quietly
-- promising to do something later. wait carries why it is waiting, because
-- "queued" without "you are in combat" is half an answer.
local function MarkQueued(snap, label)
    runState.active = false
    runState.status = "QUEUED"
    runState.paused = nil
    runState.label = label or runState.label
    runState.wait = snap.dead and "DEAD"
        or (snap.inCombat and "IN_COMBAT")
        or (snap.casting and "CASTING")
        or (snap.merchant and "MERCHANT_OPEN")
        or "LOCKED"
end

-- Only the reasons a WAIT can end on its own belong to the watchdog. The rest
-- are the combat queue's job -- the run is parked, not killed, and re-planned
-- when the block lifts.
local DEFER_TO_QUEUE = {
    IN_COMBAT = true, CASTING = true, DEAD = true, MERCHANT_OPEN = true,
}

local BIND_POPUPS = {
    EQUIP_BIND_CONFIRM = "EQUIP_BIND",
    EQUIP_BIND_REFUNDABLE_CONFIRM = "EQUIP_BIND_REFUNDABLE",
    EQUIP_BIND_TRADEABLE_CONFIRM = "EQUIP_BIND_TRADEABLE",
}

-- The server's own word on a unique-equipped collision, which no curated table
-- can keep up with. ITEM_LIMIT_CATEGORY errors carry the readable form ("You
-- can only equip 3 items in the Jeweler's Gems category") and are the reason a
-- swap can otherwise skip an item in complete silence.
local UNIQUE_ERRORS = {
    ERR_ITEM_UNIQUE_EQUIPPABLE = true,
    ERR_ITEM_UNIQUE_EQUIPPABLE_SOCKETED = true,
    ERR_ITEM_MAX_COUNT = true,
    ERR_ITEM_MAX_LIMIT_CATEGORY_COUNT_EXCEEDED_IS = true,
    ERR_ITEM_MAX_COUNT_EQUIPPED_SOCKETED = true,
}

local function BindPopupUp()
    if not StaticPopup_Visible then return false end
    for _, popup in pairs(BIND_POPUPS) do
        if StaticPopup_Visible(popup) then return true end
    end
    return false
end

-- Blizzard's own canonical swap, plus the post-check Blizzard omits and
-- ItemRack does not. Order: pick up the source, validate the destination will
-- take it, confirm the destination is not locked, then complete. If the cursor
-- still holds the item afterwards, the destination refused it -- ClearCursor
-- puts it back where it came from and the action is a clean failure rather
-- than an item left hanging on the pointer blocking every later swap.
local function EquipFromBag(action)
    local bag, slot = ResolveBagSource(action.bag, action.slot, action.key, action.itemID)
    if not bag then return false, "MISSING" end
    ClearCursor()
    C_Container.PickupContainerItem(bag, slot)
    if not CursorHasItem() then return false, "LOCKED" end
    if not CursorCanGoInSlot(action.invSlot) then ClearCursor(); return false, "REFUSED" end
    if IsInventoryItemLocked(action.invSlot) then ClearCursor(); return false, "LOCKED" end
    PickupInventoryItem(action.invSlot)
    if CursorHasItem() then ClearCursor(); return false, "REFUSED" end
    return true, "OK"
end

-- The worn item is the one source a plan cannot re-find. An inventory slot has
-- exactly one occupant and there is nowhere else to look, so this is a VERIFY
-- where the bag paths get a resolve -- and its failure is deliberately
-- non-transient. The case it exists for: a run is parked on a lock, the player
-- reaches over and equips their on-use trinket into the slot the plan means to
-- strip, and the run wakes up and bags the item they just deliberately put on.
-- Retrying would only do that a tick later, so the action fails outright and the
-- next pass re-plans against what is actually worn.
local function WornMatches(slotID, key, itemID)
    -- No identity attached means the planner had none to give; there is nothing
    -- to check and refusing here would break plans the engine builds correctly.
    if not key and not itemID then return true end
    local link = slotID and GetInventoryItemLink("player", slotID)
    if not link then return false end
    local wornKey, wornID = KeyOf(link)
    if key then return wornKey == key end
    return wornID == itemID
end

local function MoveToBag(action)
    if not WornMatches(action.invSlot, action.key, action.itemID) then
        return false, "SLOT_CHANGED"
    end
    local bag, slot = action.bag, action.slot
    -- The destination may have been consumed by an earlier action in this same
    -- run, so it is verified and re-resolved rather than trusted -- and the
    -- replacement is family-0 only, because a displaced weapon landing in a
    -- quiver is the oldest bug in this genre.
    if not (bag and slot) or C_Container.GetContainerItemInfo(bag, slot) or not IsNormalBag(bag) then
        bag, slot = FirstFreeBagSlot()
    end
    if not bag then return false, "BAGS_FULL" end
    ClearCursor()
    if IsInventoryItemLocked(action.invSlot) then return false, "LOCKED" end
    PickupInventoryItem(action.invSlot)
    if not CursorHasItem() then return false, "LOCKED" end
    C_Container.PickupContainerItem(bag, slot)
    if CursorHasItem() then ClearCursor(); return false, "BAGS_FULL" end
    return true, "OK"
end

-- Ring 1 <-> ring 2 and main hand <-> off hand. Collapsing these into one move
-- is not an optimisation: routing them through a bag drops an item whenever the
-- second half of the pair fails, which is the classic ring-swap bug.
local function SwapEquipped(action)
    -- Same verify as MoveToBag, against the slot the item is coming OUT of --
    -- action.key is the planner's word on what it saw in fromSlot. Without it a
    -- ring the player moved themselves mid-run gets shuffled somewhere nobody
    -- asked for, and the two-item exchange means a wrong pickup misplaces both.
    if not WornMatches(action.fromSlot, action.key, action.itemID) then
        return false, "SLOT_CHANGED"
    end
    ClearCursor()
    if IsInventoryItemLocked(action.fromSlot) or IsInventoryItemLocked(action.toSlot) then
        return false, "LOCKED"
    end
    PickupInventoryItem(action.fromSlot)
    if not CursorHasItem() then return false, "LOCKED" end
    if not CursorCanGoInSlot(action.toSlot) then ClearCursor(); return false, "REFUSED" end
    PickupInventoryItem(action.toSlot)
    if CursorHasItem() then ClearCursor(); return false, "REFUSED" end
    return true, "OK"
end

-- You cannot equip straight out of the bank. Bank to body is two stages: pull
-- it into a free bag slot now, equip from bags on a later pass. This is the
-- only direction that exists -- nothing here ever puts an item back.
local function Withdraw(action)
    local from, fromSlot = ResolveBankSource(action.bag, action.slot, action.key, action.itemID)
    if not from then return false, "MISSING" end
    local bag, slot = action.toBag, action.toSlot
    if not (bag and slot) or C_Container.GetContainerItemInfo(bag, slot) or not IsNormalBag(bag) then
        bag, slot = FirstFreeBagSlot()
    end
    if not bag then return false, "BAGS_FULL" end
    ClearCursor()
    C_Container.PickupContainerItem(from, fromSlot)
    if not CursorHasItem() then return false, "LOCKED" end
    C_Container.PickupContainerItem(bag, slot)
    if CursorHasItem() then ClearCursor(); return false, "BAGS_FULL" end
    return true, "OK"
end

local function Execute(action, snap)
    -- Leaf guards, re-tested here and not merely at plan time. A deferred
    -- continuation firing after combat has started and calling a restricted
    -- function is ItemRack issues #26, #42 and #189 -- ADDON_ACTION_BLOCKED on
    -- PickupInventoryItem, every time.
    if snap.inCombat then return false, "IN_COMBAT" end
    if snap.dead then return false, "DEAD" end
    if snap.merchant then return false, "MERCHANT_OPEN" end
    if not SweepCursor() then return false, "CURSOR_BUSY" end
    if SpellIsTargeting and SpellIsTargeting() then return false, "CURSOR_BUSY" end

    local op = action.op
    if op == "EQUIP_FROM_BAG" then return EquipFromBag(action) end
    if op == "MOVE_TO_BAG" then return MoveToBag(action) end
    if op == "SWAP_EQUIPPED" then return SwapEquipped(action) end
    if op == "WITHDRAW" then return Withdraw(action) end
    return false, "UNKNOWN_OP"
end

local function RunStatus()
    if not run or not E or not E.RunStatus then return "IDLE" end
    local ok, status = pcall(E.RunStatus, run)
    return (ok and status) or "IDLE"
end

local function RunSummary()
    if not run or not E or not E.RunSummary then return nil end
    local ok, summary = pcall(E.RunSummary, run)
    return ok and summary or nil
end

local function FinishRun(status)
    local summary = RunSummary()
    run = nil
    runState.active = false
    runState.status = status
    runState.wait = nil
    runState.paused = nil
    if summary then
        runState.done = (summary.equipped or 0) + (summary.removed or 0)
        runState.failed = summary.failed or 0
    end
    Invalidate()

    if status == "DONE" then
        if DB("AnnounceSwaps", true) then
            Say(format("%s equipped.", runState.label or "set"))
        end
    elseif status == "PARKED" then
        -- Silent on purpose: the run is not over, it moved to the queue, and
        -- ParkRun says so in the queue's own vocabulary. A failure line here
        -- would contradict the promise the very next message makes.
    elseif status == "TIMEOUT" then
        -- The honest message. A stuck swap used to look identical to a finished
        -- one, which is the failure mode this whole module exists to end.
        Warn(format("%s stopped: the client stopped answering mid-swap. %d of %d moves went through -- run it again to finish.",
            runState.label or "swap", runState.done or 0, runState.total or 0))
    elseif status == "PARTIAL" then
        -- Stage one of a bank swap went through and stage two cannot follow. The
        -- items are in your bags, so "equipped" would be a lie and "the client
        -- stopped answering" would blame the wrong thing -- the reasons were
        -- printed by the caller, this is the one line that says where you stand.
        Warn(format("%s is half applied: %d moves went through and the rest cannot run yet. Your bank items are in your bags -- run it again.",
            runState.label or "swap", runState.done or 0))
    else
        local detailText = runState.uniqueConflict or runState.lastError
        Warn(format("%s did not finish: %d of %d moves failed%s.",
            runState.label or "swap", runState.failed or 0, runState.total or 0,
            detailText and (" -- " .. detailText) or ""))
    end
    -- The macro is compiled from the SELECTED set, and equipping one is the
    -- most likely moment for that to have changed.
    UpdateSecure()
    Notify()
end

local function PlanWithdraws(plan)
    for _, action in ipairs((plan and plan.actions) or {}) do
        if action.op == "WITHDRAW" then return true end
    end
    return false
end

-- The plan this run is for, rebuilt against live state. A run outlives the world
-- it was planned in, which is the whole reason ReplanRun exists.
local function Replan(snap)
    if not HaveEngine() then return nil end
    if runCtx.kind == "SET" then
        if not runCtx.set then return nil end
        local ok, plan = pcall(E.PlanSet, runCtx.set, snap, PlanOpts(runCtx.set))
        return ok and plan or nil
    end
    if runCtx.kind == "SINGLE" then
        -- A reference that no longer resolves is NOT a removal. PlanSingle with
        -- nil means "put what is there in my bags", so handing it a failed
        -- lookup would strip the slot the player was trying to fill.
        local row
        if runCtx.ref then
            row = ResolveRef(runCtx.ref, snap)
            if not row then return nil end
        end
        local ok, plan = pcall(E.PlanSingle, runCtx.slotID, row, snap)
        return ok and plan or nil
    end
    return nil
end

-- A WITHDRAW moves bank -> bags and nothing else; the equip is a SECOND pass,
-- planned from a snapshot that has seen the item land (ARCHITECTURE 2.5 rule 5,
-- D16). Without this the action list simply ran out, the run reported DONE, and
-- the player was told "Arena equipped" while wearing nothing new and carrying a
-- bagful of PvP gear -- ReplanRun was documented, correct, and called from
-- nowhere.
local function ContinueAfterWithdraw()
    Invalidate()
    local snap = Snapshot()
    -- Blocked between the two stages: the queue takes the remainder, exactly as
    -- it would have taken it mid-pass. Announcing DONE here is the lie the whole
    -- fix exists to remove, so this is not a place to shrug and finish.
    local why = snap.dead and "DEAD"
        or (snap.inCombat and "IN_COMBAT")
        or (snap.casting and "CASTING")
        or (snap.merchant and "MERCHANT_OPEN")
        or nil
    if why then return "PARK", why, snap end

    local plan = Replan(snap)
    -- No plan at all means there is nothing left to ask for -- the reference is
    -- gone, or the set has no owner any more. Genuinely finished.
    if not plan then return "DONE" end
    if not plan.ok then
        runState.reasons = plan.reasons
        ReportRefusal(plan, runState.label or "that swap")
        return "PARTIAL"
    end
    if not plan.actions or #plan.actions == 0 then return "DONE" end
    -- Planned BEFORE the cap is tested, so the cap only ever stops a run that
    -- still had work -- a run that finished on its last pass must not be
    -- accused of looping.
    if runPass >= MAX_PASSES then
        Warn(format("%s still is not finished after %d passes, so it stopped rather than loop. Run it again.",
            runState.label or "the swap", runPass))
        return "PARTIAL"
    end

    runPass = runPass + 1
    runWithdrew = PlanWithdraws(plan)
    runState.total = (runState.total or 0) + #plan.actions
    runState.reasons = plan.reasons
    E.ReplanRun(run, plan)
    settleUntil = GetTime() + SETTLE_ACTION
    runState.progressAt = GetTime()
    return "GO"
end

-- The remainder is not ours to run any more, but it is still the player's
-- intent. Hand it to the queue rather than reporting a fault: the client was
-- never broken, the player got pulled -- and UX.md's whole point about the queue
-- is that "nothing happened" is the failure worth converting into a promise.
local function ParkRun(reason, snap)
    local set, slotID, ref, kind = runCtx.set, runCtx.slotID, runCtx.ref, runCtx.kind
    local label = runState.label
    local done, total = runState.done or 0, runState.total or 0
    local queueable = DB("CombatQueue", true)
        and ((kind == "SET" and set) or (kind == "SINGLE" and slotID))
    FinishRun("PARKED")
    if not queueable then
        Warn(format("%s stopped after %d of %d moves -- %s. Run it again when you can.",
            label or "swap", done, total, reason == "DEAD" and "you are dead"
                or (reason == "CASTING" and "you were casting"
                    or (reason == "MERCHANT_OPEN" and "a vendor window is open"
                        or "you are in combat"))))
        return
    end
    QueueClear()
    if kind == "SET" then
        -- The SET, not the remaining actions. Those coordinates are already
        -- stale and the queue's own flush re-plans from scratch, which is what
        -- makes the second half arrive correct rather than merely arrive.
        queue.set = set
    else
        queue.slots[slotID] = { ref = ref, removal = (ref == nil) }
    end
    MarkQueued(snap, label)
    Say(format("%s got as far as %d of %d moves before %s.", label or "the swap", done, total,
        reason == "DEAD" and "you died" or (reason == "CASTING" and "you started casting"
            or (reason == "MERCHANT_OPEN" and "a vendor window opened" or "you were pulled into combat"))))
    AnnounceQueued(snap)
    Notify()
end

local function StepRun()
    if not run then return end
    local now = GetTime()
    if now < settleUntil then return end
    local snap = Snapshot()

    -- A bind confirmation is a pause, not an error: the player owns the answer
    -- and the run waits for it without the watchdog ticking underneath.
    if runState.paused then
        if BindPopupUp() then return end
        runState.paused = nil
        runState.progressAt = snap.now
    end

    local action, waitReason = E.NextAction(run, snap)
    if not action then
        local status = RunStatus()
        if status == "DONE" and runWithdrew then
            local verdict, why, fresh = ContinueAfterWithdraw()
            if verdict == "GO" then return end
            if verdict == "PARK" then ParkRun(why, fresh); return end
            if verdict == "PARTIAL" then FinishRun("PARTIAL"); return end
        end
        if status == "DONE" or status == "FAILED" then FinishRun(status); return end
        -- The real reason, not merely "waiting": the UI is the only thing that
        -- can tell the player why their swap is sitting still.
        runState.wait = waitReason or status
        if DEFER_TO_QUEUE[waitReason or ""] then ParkRun(waitReason, snap); return end
        -- The watchdog answers for LOCKED and nothing else. It used to fire on
        -- every wait, so being pulled three actions into a twelve-slot swap
        -- reported "the client stopped answering mid-swap" -- blaming the client
        -- for combat, and dropping the other nine actions on the floor with the
        -- queue never hearing about them.
        if status == "TIMEOUT"
            or (waitReason == "LOCKED" and (snap.now - runState.progressAt) > RUN_WATCHDOG) then
            FinishRun("TIMEOUT")
        end
        return
    end

    runState.wait = nil
    local ok, code = Execute(action, snap)
    E.ReportResult(run, action, ok, code)
    runState.progressAt = GetTime()
    settleUntil = runState.progressAt + SETTLE_ACTION
    Invalidate()

    local summary = RunSummary()
    if summary then
        runState.done = (summary.equipped or 0) + (summary.removed or 0)
        runState.failed = summary.failed or 0
    end

    local status = RunStatus()
    -- A finished action list with a WITHDRAW in it is not a finished job, and
    -- this is also the wrong FRAME to decide: the container read that would feed
    -- the next plan is the same frame as the pickup that filled it. So the run
    -- is held open and the next tick re-plans it, one settle interval later.
    if status == "DONE" and runWithdrew then return end
    if status == "DONE" or status == "FAILED" then FinishRun(status) end
end

-- Pre-flight. The plan comes back with zero actions when anything is missing,
-- banked-while-away, or the bags are too full -- which is the line this module
-- defends hardest. Never half-apply a set. (C_EquipmentSet.UseEquipmentSet
-- produces no error messages at all when it fails, which is why we do our own.)
function ReportRefusal(plan, label)
    local reasons = plan and plan.reasons
    local blockers = 0
    for _, reason in ipairs(reasons or {}) do
        if not reason.warning then blockers = blockers + 1 end
    end
    if blockers == 0 then
        Warn(format("%s cannot be equipped right now.", label))
        return
    end
    Warn(format("%s cannot be equipped:", label))
    for _, reason in ipairs(reasons) do
        -- Warnings are skipped here and printed on the SUCCESS path instead: a
        -- warning is not why the plan was refused, and listing it among the
        -- blockers tells the player to fix something that was never in the way.
        if not reason.warning then
            local where = reason.slotKey and D.SlotByKey[reason.slotKey]
            local slotText = where and (D.SlotLabel(where.id) .. ": ") or ""
            print("   " .. slotText .. (reason.text or reason.code or "?"))
        end
    end
end

-- The other half of that rule. A reason carrying warning = true rides along with
-- ok = true and a full action list -- the two-hander that displaces an off-hand
-- the set never mentioned is the first of them -- so it is information delivered
-- BEFORE the swap, in the same voice as the broken-item note, and never anything
-- the player has to read as a failure.
local function ReportWarnings(plan)
    for _, reason in ipairs((plan and plan.reasons) or {}) do
        if reason.warning then
            local where = reason.slotKey and D.SlotByKey[reason.slotKey]
            local slotText = where and (D.SlotLabel(where.id) .. ": ") or ""
            Say(format("|cffff8844%s%s|r", slotText, reason.text or reason.code or "?"))
        end
    end
end

-- kind/set/slotID/ref describe what was ASKED for, which the run itself does not
-- carry: an action list is a route, and a route cannot be recalculated.
local function StartRun(plan, kind, label, set, slotID, ref)
    if not plan then return false, "NOTHING_TO_DO" end
    runState.reasons = plan.reasons
    runState.lastError, runState.lastErrorID, runState.uniqueConflict = nil, nil, nil
    runCtx.kind, runCtx.set, runCtx.slotID, runCtx.ref = kind, set, slotID, ref

    -- Three different questions, and only `verdict` answers "is anything
    -- wrong". `ok` answers "should the host start a run" and comes back FALSE
    -- for the most ordinary outcome there is -- you are already wearing it --
    -- so branching on it alone painted that red and left the run BLOCKED. And
    -- the reason list answers neither: reasons may carry warning = true
    -- alongside ok = true and a full action list, so a non-empty table must
    -- never be read as a refusal either. That trade -- a silent bug for a false
    -- refusal -- is the wrong way round.
    local blocked = plan.verdict == "BLOCKED"
    if blocked or not plan.ok or not plan.actions or #plan.actions == 0 then
        runState.active = false
        runState.status = blocked and "BLOCKED" or "DONE"
        runState.label = label
        if blocked then
            ReportRefusal(plan, label)
        elseif DB("AnnounceSwaps", true) then
            Say(format("%s is already on.", label))
        end
        Notify()
        return false, blocked and "BLOCKED" or "NOTHING_TO_DO"
    end

    if DB("WarnBroken", true) then
        for _, action in ipairs(plan.actions) do
            if action.broken then
                Say(format("|cffff8844%s is broken -- it will equip, but it gives no stats until repaired.|r",
                    action.name or "an item"))
            end
        end
    end
    ReportWarnings(plan)

    run = E.NewRun(plan)
    runPass = 1
    runWithdrew = PlanWithdraws(plan)
    settleUntil = 0
    runState.active = true
    runState.status = "RUNNING"
    runState.kind = kind
    runState.label = label
    runState.total = #plan.actions
    runState.done, runState.failed = 0, 0
    runState.wait, runState.paused = nil, nil
    runState.startedAt = GetTime()
    runState.progressAt = runState.startedAt
    if DB("AnnounceSwaps", true) then
        Say(format("equipping %s (%d moves)...", label, runState.total))
    end
    Notify()
    -- Start immediately rather than waiting a tick: the first action is legal
    -- by construction and the delay is visible as lag on a one-slot swap.
    StepRun()
    return true, "OK"
end

-- ---------------------------------------------------------------------------
-- Requests -- the layer the UI and the slash commands actually call
-- ---------------------------------------------------------------------------

local function Refuse(reason)
    if reason == "MERCHANT_OPEN" then
        Warn("not while a vendor window is open -- a swap with a merchant frame up can sell your gear. Close it and try again.")
    elseif reason == "NO_ENGINE" then
        Warn("the engine did not load, so nothing can be equipped. Try /reload.")
    elseif reason == "BUSY" then
        -- Never silent. A click that does nothing and says nothing is precisely
        -- the failure this module exists to end, and "already busy" was the one
        -- refusal that still shipped it.
        Warn(format("%s is still going (%d of %d moves) -- wait for it to finish, or /cgear again once it has.",
            runState.label or "a swap", runState.done or 0, runState.total or 0))
    end
    return false, reason
end

local function CanStart(snap)
    if not HaveEngine() then return false, "NO_ENGINE" end
    if snap.merchant then return false, "MERCHANT_OPEN" end
    if run then return false, "BUSY" end
    return true
end

function EquipSet(set)
    set = set or SelectedSet()
    if not set then Warn("no set is selected."); return false, "NOTHING_TO_DO" end
    local snap = Snapshot()
    local ok, reason = CanStart(snap)
    if not ok then return Refuse(reason) end
    -- Cursor first: a stuck item makes every later swap fail in a way that
    -- looks like our bug, so it is swept before the world is judged.
    if snap.cursorBusy and not snap.inCombat then
        SweepCursor()
        RefreshVolatile(GetTime())
    end
    if Blocked(snap) or snap.cursorBusy then
        if not DB("CombatQueue", true) then
            Warn(format("cannot equip %s while %s.", set.name or "that set",
                snap.dead and "dead" or (snap.inCombat and "in combat"
                    or (snap.casting and "casting" or "an item is on your cursor"))))
            return false, "IN_COMBAT"
        end
        QueueClear()
        queue.set = set
        MarkQueued(snap, format("\"%s\"", set.name or "set"))
        AnnounceQueued(snap)
        Notify()
        return false, "QUEUED"
    end
    local plan = E.PlanSet(set, snap, PlanOpts(set))
    return StartRun(plan, "SET", format("\"%s\"", set.name or "set"), set)
end

local function EquipSingle(slotID, candidateRow)
    local snap = Snapshot()
    local ok, reason = CanStart(snap)
    if not ok then return Refuse(reason) end
    if snap.cursorBusy and not snap.inCombat then
        SweepCursor()
        RefreshVolatile(GetTime())
    end
    -- Taken before anything can defer: the row is engine scratch and the moment
    -- this call returns, the next flyout the player opens rewrites it.
    local ref = CandidateRef(candidateRow)
    if Blocked(snap) or snap.cursorBusy then
        if not DB("CombatQueue", true) then return false, "IN_COMBAT" end
        if queue.set then
            -- A whole-set request speaks for every slot, so it cannot simply be
            -- dropped on the floor when one slot is asked for afterwards -- the
            -- player asked for that set and would otherwise never learn it was
            -- gone. (It used to be cleared here without adjusting the count,
            -- which wedged the queue permanently.)
            Say(format("dropping the queued set \"%s\" -- %s takes its place.",
                queue.set.name or "?", D.SlotLabel(slotID)))
            queue.set = nil
        end
        queue.slots[slotID] = { ref = ref, removal = (candidateRow == nil) }
        MarkQueued(snap, (candidateRow and candidateRow.name) or D.SlotLabel(slotID))
        AnnounceQueued(snap)
        Notify()
        return false, "QUEUED"
    end
    -- PlanSingle with no candidate is the removal case: the contract gives one
    -- entry point for "make this slot look like X", and X may be nothing.
    local plan = E.PlanSingle(slotID, candidateRow, snap)
    local label = (candidateRow and candidateRow.name) or D.SlotLabel(slotID)
    return StartRun(plan, "SINGLE", label, nil, slotID, ref)
end

local function RemoveSlot(slotID)
    return EquipSingle(slotID, nil)
end

-- Flushed on PLAYER_REGEN_ENABLED, but also polled: the block may have been
-- casting, being dead, or a stuck cursor, and none of those end with a regen
-- event. The drain test is InCombatLockdown, exactly as the enqueue test was.
local function TryFlushQueue()
    if QueueEmpty() or run then return end
    local snap = Snapshot()
    if Blocked(snap) or snap.merchant then return end
    if snap.cursorBusy then
        SweepCursor()
        return
    end
    if not HaveEngine() then return end

    if queue.set then
        local set = queue.set
        QueueClear()
        Notify()
        EquipSet(set)
        return
    end
    -- One slot per flush. The rest ride the next tick, which is the same
    -- multi-pass discipline the runner itself uses.
    for slotID, entry in pairs(queue.slots) do
        queue.slots[slotID] = nil
        Notify()
        if entry.removal then
            EquipSingle(slotID, nil)
        else
            -- Re-found here, not remembered from the click. The queue holds an
            -- identity because the engine's candidate rows are pooled scratch,
            -- and by now the fight it waited out has had every chance to move
            -- the item -- or to consume it.
            local row = ResolveRef(entry.ref, snap)
            if row then
                EquipSingle(slotID, row)
            else
                -- Emphatically NOT a fall-through to the removal path: nil means
                -- "empty this slot" to PlanSingle, so a vanished item would take
                -- the worn one off instead of replacing it.
                Warn(format("%s is not where it was, so the queued %s swap was dropped.",
                    (entry.ref and entry.ref.name) or "that item", D.SlotLabel(slotID)))
                Notify()
            end
        end
        return
    end
end

-- ---------------------------------------------------------------------------
-- Set management
-- ---------------------------------------------------------------------------

local function SaveSet(set, ignoreTable)
    if not HaveEngine() then return Refuse("NO_ENGINE") end
    set = set or SelectedSet()
    if not set then return false end
    set.entries = E.CaptureSet(Snapshot(), {
        ignore = ignoreTable or IgnoreForCapture(set),
        includeCosmetic = DB("CaptureCosmetic", false),
    })
    ignoreTouched = false
    UpdateSecure()
    Notify()
    Say(format("saved \"%s\".", set.name or "set"))
    return true
end

-- A new set starts NAKED: every slot EMPTY, shirt and tabard IGNORED. It is
-- stored and selected immediately, and nothing captures the player's gear into
-- it -- "New" means "a set that specifies nothing worn", and the way to fill it
-- is either Save (replace it with what you have on) or the pane's slot grid,
-- which authors one slot at a time without wearing anything.
local function NewSet(name, icon)
    if not HaveEngine() then return nil end
    local sets = Sets()
    local set = (E.NakedSet and E.NakedSet(name, icon)) or E.NewSet(name, icon)
    set.order = #sets + 1
    sets[#sets + 1] = set
    selectedIndex = #sets
    CharStore().selected = selectedIndex
    LoadIgnoreScratch(set)
    UpdateSecure()
    return set
end

-- Authoring: write ONE slot of a set directly, with nothing equipped.
--
-- This is the second way to fill a set and the only one that does not require
-- wearing the gear first. `row` is a candidate row (pooled scratch -- the entry
-- is a fresh copy, made by the engine) or nil, which means "leave this slot
-- bare" and writes EMPTY rather than deleting the entry, because a deleted
-- entry means IGNORED and that is the opposite instruction (D3).
--
-- The write is immediate and persistent. It is an explicit edit, not a staged
-- one: there is no second confirmation step, and Save is not it -- Save means
-- "replace this set with what I am wearing" and will overwrite authored entries,
-- which is why its tooltip now says so in those words.
local function AuthorSlot(set, slotKey, row)
    if not HaveEngine() then return false end
    set = set or SelectedSet()
    local slot = slotKey and D.SlotByKey[slotKey]
    if not set or not slot then return false end
    local entry
    if row == nil then
        entry = E.EmptyEntry()
    else
        entry = E.AuthorEntry(row)
        if not entry then return false end
    end
    if type(set.entries) ~= "table" then set.entries = {} end
    set.entries[slotKey] = entry
    -- Authoring a slot is a statement that the set speaks for it, so the
    -- hands-off flag comes off with it. Leaving it on would let the very next
    -- Save write IGNORED straight back over the entry that was just authored --
    -- the edit would appear to take and then silently undo itself.
    if set == SelectedSet() and ignoreScratch[slotKey] then
        ignoreScratch[slotKey] = nil
        ignoreTouched = true
    end
    UpdateSecure()
    Notify()
    return true
end

local function DeleteSet(set)
    local sets = Sets()
    for i, candidate in ipairs(sets) do
        if candidate == set then
            tremove(sets, i)
            for j = i, #sets do sets[j].order = j end
            if selectedIndex >= i then
                selectedIndex = math.min(selectedIndex, #sets)
            end
            CharStore().selected = selectedIndex
            LoadIgnoreScratch(SelectedSet())
            UpdateSecure()
            Notify()
            Say(format("deleted \"%s\".", set.name or "set"))
            return true
        end
    end
    return false
end

-- Returns ok, reason. The reason is a finished sentence rather than a code,
-- because both callers -- the name dialog and the pane's inline editor -- want
-- to show the same words, and a refusal that says nothing is indistinguishable
-- from a control that does not work.
--
-- The duplicate scan is written out here rather than calling FindSetByName,
-- which is declared BELOW this function: a local referenced before its
-- declaration compiles to a global read and returns nil at runtime with no
-- warning at all, which is the exact bug globals_lint exists to catch.
local function RenameSet(set, name, icon)
    if not set then return false, "no set is selected." end
    if name ~= nil then
        local trimmed = name:match("^%s*(.-)%s*$") or ""
        if trimmed == "" then
            return false, "a set needs a name."
        end
        local needle = trimmed:lower()
        for _, other in ipairs(Sets()) do
            if other ~= set and (other.name or ""):lower() == needle then
                return false, format("you already have a set called \"%s\".", other.name or trimmed)
            end
        end
        set.name = trimmed
    end
    if icon then set.icon = icon end
    UpdateSecure()
    Notify()
    return true
end

local function SelectSet(index)
    local sets = Sets()
    if index and index ~= 0 and not sets[index] then return false end
    selectedIndex = index or 0
    CharStore().selected = selectedIndex
    LoadIgnoreScratch(SelectedSet())
    UpdateSecure()
    Notify()
    return true
end

-- Slash arguments arrive lowercased and trimmed, so both sides are folded here
-- and a set called "Arena Kit" is found by typing "arena kit".
local function FindSetByName(name)
    if not name or name == "" then return nil end
    local needle = name:lower()
    for index, set in ipairs(Sets()) do
        if (set.name or ""):lower() == needle then return set, index end
    end
    -- Prefix match second, so "arena" finds "Arena 2v2" but an exact name can
    -- never be shadowed by a longer one that happens to start the same way.
    for index, set in ipairs(Sets()) do
        if (set.name or ""):lower():find(needle, 1, true) == 1 then return set, index end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Runtime probes
--
-- Two questions the source tree cannot settle, recorded once at login so a
-- single in-game session answers them for ASSUMPTIONS.md. Nothing depends on
-- either result: we own our storage and we keep our own bank cache regardless.
-- ---------------------------------------------------------------------------

local probes = {}

local function ProbeEquipmentSets()
    if not C_EquipmentSet then
        probes.equipmentSets = "namespace absent"
        return
    end
    local can
    if C_EquipmentSet.CanUseEquipmentSets then
        local ok, value = pcall(C_EquipmentSet.CanUseEquipmentSets)
        can = ok and value or false
    end
    local count
    if C_EquipmentSet.GetNumEquipmentSets then
        local ok, value = pcall(C_EquipmentSet.GetNumEquipmentSets)
        count = ok and value or nil
    end
    probes.equipmentSets = format("CanUseEquipmentSets=%s, GetNumEquipmentSets=%s",
        tostring(can), tostring(count))
end

-- Blizzard's own comment says GetInventoryItemsForSlot sorts as "inventory,
-- backpack, bags, bank, and bank bags". If it still returns bank locations with
-- the bank shut, our cache is redundant -- but it is not exercised by any
-- TBC-loaded file, so it is probed and the code tolerates either answer.
local function ProbeInventoryItemsForSlot()
    if not _G.GetInventoryItemsForSlot then
        probes.itemsForSlot = "absent"
        return
    end
    local scratch = {}
    local ok = pcall(_G.GetInventoryItemsForSlot, D.FIRST_SLOT, scratch)
    if not ok then
        probes.itemsForSlot = "call errored"
        return
    end
    local total, banked = 0, 0
    local band = bit and bit.band
    for location in pairs(scratch) do
        total = total + 1
        if band and type(location) == "number" and band(location, D.LOC_BANK) ~= 0 then
            banked = banked + 1
        end
    end
    probes.itemsForSlot = format("%d locations for slot 1, %d flagged bank (bank %s)",
        total, banked, bankOpen and "open" or "shut")
    probes.itemsForSlotSeesBank = banked > 0
end

function CommanderArmory_Probe()
    ProbeEquipmentSets()
    ProbeInventoryItemsForSlot()
    Say("runtime probes")
    print("   C_EquipmentSet: " .. tostring(probes.equipmentSets))
    print("   GetInventoryItemsForSlot: " .. tostring(probes.itemsForSlot))
    local bank = CharStore().bank
    print(format("   bank cache: %d equippable items, %s",
        #((bank and bank.items) or {}),
        (bank and bank.at and bank.at > 0)
            and (format("last seen %d minutes ago", math.floor((time() - bank.at) / 60)))
            or "never seen"))
    print(format("   free bag slots (family 0 only): %d", Snapshot().freeBagSlots or 0))
    local gemsKnown, gemsUnique, gemsWaiting = 0, 0, 0
    for _, state in pairs(gemState) do
        if state.known then gemsKnown = gemsKnown + 1 end
    end
    for _ in pairs(uniqueGems) do gemsUnique = gemsUnique + 1 end
    for _ in pairs(gemPending) do gemsWaiting = gemsWaiting + 1 end
    print(format("   gems: %d answered, %d unique-equipped, %d still uncached",
        gemsKnown, gemsUnique, gemsWaiting))
end

-- ---------------------------------------------------------------------------
-- The exported surface
--
-- CommanderArmoryUI.lua reads this and nothing else; the DB file calls the
-- CommanderArmory_* globals below it. Everything here is safe to call before
-- the UI exists and safe to call in combat -- the combat consequences are
-- handled inside, not at the call site.
-- ---------------------------------------------------------------------------

CommanderArmory = {}

CommanderArmory.THEME = THEME

function CommanderArmory.Snapshot() return Snapshot() end
function CommanderArmory.Sets() return Sets() end
function CommanderArmory.SelectedSet() return SelectedSet() end
function CommanderArmory.SelectedIndex() return selectedIndex end
function CommanderArmory.SelectSet(index) return SelectSet(index) end
function CommanderArmory.NewSet(name, icon) return NewSet(name, icon) end
function CommanderArmory.SaveSet(set, ignoreTable) return SaveSet(set, ignoreTable) end
function CommanderArmory.DeleteSet(set) return DeleteSet(set) end
function CommanderArmory.RenameSet(set, name, icon) return RenameSet(set, name, icon) end

-- Author one slot of a set without wearing anything. `row` is a candidate row,
-- or nil for "leave this slot bare" (EMPTY).
function CommanderArmory.AuthorSlot(set, slotKey, row) return AuthorSlot(set, slotKey, row) end
function CommanderArmory.FindSet(name) return FindSetByName(name) end

function CommanderArmory.EquipSet(set) return EquipSet(set) end
function CommanderArmory.EquipSingle(slotID, row) return EquipSingle(slotID, row) end
function CommanderArmory.RemoveSlot(slotID) return RemoveSlot(slotID) end

function CommanderArmory.IgnoreScratch() return ignoreScratch end

function CommanderArmory.ToggleIgnore(slotKey)
    if not slotKey or not D.SlotByKey[slotKey] then return false end
    ignoreScratch[slotKey] = (not ignoreScratch[slotKey]) or nil
    -- Ignore state can change while a set is fully equipped, which is the one
    -- case where Save must come back to life with nothing else dirty.
    ignoreTouched = true
    Notify()
    return ignoreScratch[slotKey] and true or false
end

-- Is the selection different from what is on the body, or has its ignore map
-- been edited? Two independent facts, and the UI needs them as one answer.
function CommanderArmory.SelectionDirty()
    if ignoreTouched then return true end
    local set = SelectedSet()
    if not set or not HaveEngine() or not E.SetIsDirty then return false end
    local ok, dirty = pcall(E.SetIsDirty, set, Snapshot())
    return (ok and dirty) and true or false
end

function CommanderArmory.RunState() return runState end

function CommanderArmory.IsQueued()
    if QueueEmpty() then return false end
    return true, QueueDescribe()
end

function CommanderArmory.CancelQueue()
    if QueueEmpty() then return false end
    local what = QueueDescribe()
    QueueClear()
    Say(format("cancelled the queued %s.", what or "swap"))
    Notify()
    return true
end

-- Pre-flight without touching anything: what would happen, and why not.
function CommanderArmory.Preflight(set)
    set = set or SelectedSet()
    if not set or not HaveEngine() then return nil end
    -- Same rule as EquipSet: the scratchpad is the SELECTED set's editing
    -- state, so a pre-flight for any other set has to read that set's own
    -- IGNORED entries or it would preview a swap nobody is going to run.
    local ok, plan = pcall(E.PlanSet, set, Snapshot(), PlanOpts(set))
    return ok and plan or nil
end

function CommanderArmory.Diff(set)
    set = set or SelectedSet()
    if not set or not HaveEngine() then return nil end
    -- The fourth argument is the same scratchpad rule again, and it matters
    -- because this and Preflight are read side by side: the row summary saying
    -- "changes 6" while the banner describes a two-slot swap would be the module
    -- disagreeing with itself over an ignore toggle the player just flipped.
    local ignore = (set == SelectedSet()) and ignoreScratch or nil
    local ok, diff = pcall(E.DiffSet, set, Snapshot(), nil, ignore)
    return ok and diff or nil
end

function CommanderArmory.Stats(set)
    set = set or SelectedSet()
    if not set or not HaveEngine() or not E.SetStats then return nil end
    local ok, stats, total, average = pcall(E.SetStats, set, Snapshot())
    if not ok then return nil end
    return stats, total, average
end

-- The flyout's candidate list, with the settings and Pawn folded in so the UI
-- never has to know either exists.
--
-- The rows are the ENGINE'S POOL and are rewritten by the next call. Paint from
-- them, hand one straight back to EquipSingle, and then let go: anything kept
-- past the current frame has to keep the identity instead (CandidateRef), which
-- is what the combat queue does and why it does it.
function CommanderArmory.Candidates(slotID, opts)
    if not HaveEngine() then return {} end
    opts = opts or {}
    local minQuality = opts.minQuality or DB("FlyoutMinQuality", 0)
    if minQuality == 0 then minQuality = nil end
    local sort = opts.sort or DB("FlyoutSort", "ILVL")
    local score
    if sort == "SCORE" then
        score = PawnScorer()
        -- Pawn gone since the option was set: fall back rather than sort by nil
        if not score then sort = "ILVL" end
    end
    local ok, rows = pcall(E.Candidates, Snapshot(), slotID, {
        search = opts.search,
        minQuality = minQuality,
        hidden = CharStore().hidden,
        showHidden = opts.showHidden,
        sort = sort,
        score = score,
    })
    if not ok or type(rows) ~= "table" then return {} end
    if DB("FlyoutShowBank", true) then return rows end
    local filtered = {}
    for _, row in ipairs(rows) do
        if row.where ~= "BANK" then filtered[#filtered + 1] = row end
    end
    return filtered
end

function CommanderArmory.HasPawn() return PawnScorer() ~= nil end

-- The alt-click hide list. It lives in the per-character store rather than the
-- settings file because it is hand-authored state, and Restore Defaults must
-- never be able to eat it.
function CommanderArmory.Hidden() return CharStore().hidden end

function CommanderArmory.ToggleHidden(key)
    if not key then return false end
    local hidden = CharStore().hidden
    hidden[key] = (not hidden[key]) or nil
    Notify()
    return hidden[key] and true or false
end

function CommanderArmory.AtBank() return bankOpen end

function CommanderArmory.BankAge()
    local bank = CharStore().bank
    return bank and bank.at or 0
end

function CommanderArmory.ItemMeta(link) return ItemMeta(link) end
function CommanderArmory.Probes() return probes end

-- Read-only. Membership means "this gem is unique-equipped"; absence means
-- either not unique or not yet answered, and both mean do not flag it.
function CommanderArmory.UniqueGems() return uniqueGems end

-- Ammo, for the paperdoll display only -- it stays out of sets. Read through
-- the item id because GetInventoryItemLink("player", 0) returns nil for slot 0,
-- which is the trap that makes ammo look permanently empty.
function CommanderArmory.AmmoInfo()
    local itemID = GetInventoryItemID and GetInventoryItemID("player", 0)
    if not itemID then return nil end
    local name, link, quality
    if C_Item and C_Item.GetItemInfo then
        name, link, quality = C_Item.GetItemInfo(itemID)
    end
    local count = GetInventoryItemCount and GetInventoryItemCount("player", 0) or 0
    local fast = Instant(itemID)
    return itemID, name, link, quality, count, fast and fast.icon
end

-- The secure container. Read-only handles: the UI must never re-parent this
-- into its own hierarchy, and must never move, scale or re-strata it -- the
-- container is protected and every one of those calls is blocked in combat.
-- It is parked off-screen at login and stays there (see BuildSecure).
function CommanderArmory.SecureHost() return secureHost end
function CommanderArmory.SecureButton() return secureButton end

-- ---------------------------------------------------------------------------
-- Public entry points (slash commands, keybinds, other modules)
-- ---------------------------------------------------------------------------

-- Defensive on purpose: a load-order problem in the UI file should cost the
-- panel, not throw an error into every /cgear the player types.
function CommanderArmory_Toggle()
    if CommanderArmoryUI and CommanderArmoryUI.Toggle then
        CommanderArmoryUI.Toggle()
        return
    end
    Warn("the Armory panel is not available -- the interface file did not load. /reload may fix it.")
end

function CommanderArmory_EquipSetByName(name)
    local set = FindSetByName(name)
    if not set then
        Warn(format("no set called \"%s\". /cgear list shows what you have.", tostring(name)))
        return false
    end
    return EquipSet(set)
end

function CommanderArmory_SaveSetByName(name)
    if not name or name == "" then
        Warn("saving needs a name: /cgear save <name>")
        return false
    end
    local set = FindSetByName(name)
    if not set then
        set = NewSet(name, nil)
        if not set then return Refuse("NO_ENGINE") end
    end
    -- No ignore table on purpose. This used to stamp the SELECTED set's live
    -- editing flags onto whatever set the name found, so /cgear save pve while a
    -- two-slot hit-swap was selected saved a "pve" set that ignores seventeen
    -- slots. SaveSet asks the set itself unless it is the one being edited.
    return SaveSet(set)
end

function CommanderArmory_ListSets()
    local sets = Sets()
    if #sets == 0 then
        Say("no sets saved on this character yet. Wear what you want and /cgear save <name>.")
        return
    end
    Say(format("%d set%s on this character:", #sets, #sets == 1 and "" or "s"))
    local snap = Snapshot()
    for index, set in ipairs(sets) do
        local note = ""
        if HaveEngine() and E.DiffSet then
            local ok, diff = pcall(E.DiffSet, set, snap)
            if ok and diff then
                if diff.isEquipped then
                    note = " |cff66dd66(worn)|r"
                elseif (diff.missing or 0) > 0 then
                    note = format(" |cffdd5544(%d missing)|r", diff.missing)
                elseif (diff.inBank or 0) > 0 then
                    -- The distinction the whole module exists for: banked is an
                    -- instruction, missing is a dead end.
                    note = format(" |cff4d99f0(%d in your bank)|r", diff.inBank)
                else
                    note = format(" |cff777777(%d slots to change)|r", diff.touched or 0)
                end
            end
        end
        print(format("   %d. %s%s%s", index, set.name or "?",
            index == selectedIndex and " |cffffd100*|r" or "", note))
    end
end

-- Unconditional: the DB file owns StaticPopupDialogs["COMMANDER_ARMORY_WIPE"]
-- and this is what its OnAccept calls. A second confirmation here would be a
-- double prompt, and registering our own key would race the DB's.
function CommanderArmory_WipeSets()
    local store = CharStore()
    wipe(store.sets)
    -- The bank cache and the hide list go too, because the dialog says they do.
    -- They are per-character state of exactly the same kind, and leaving a bank
    -- cache behind after a wipe means the module still claims to know where
    -- gear is for sets that no longer exist. Rebuilt on the next bank visit.
    store.bank = { items = {}, at = 0 }
    wipe(store.hidden)
    selectedIndex = 0
    store.selected = 0
    wipe(ignoreScratch)
    ignoreTouched = false
    UpdateSecure()
    Notify()
    Say("every gear set on this character has been deleted.")
    return true
end

-- ---------------------------------------------------------------------------
-- Apply, tick, events
-- ---------------------------------------------------------------------------

-- A SETTING changed. Nothing here touches the secure container's geometry --
-- see the note above BuildSecure -- and nothing here is the response to data
-- moving; that is Notify's job.
local function Apply()
    ResolveThemeOverrides()
    Invalidate()
    UpdateSecure()
end

local function Tick()
    -- Idle cost is a nil test and a next() on an empty table: nothing here polls
    -- the world unless a run or a queued swap is actually outstanding. That
    -- guard is load-bearing rather than tidy -- TryFlushQueue's first act is a
    -- full snapshot, so an entry the queue cannot get rid of costs a complete
    -- paperdoll, bag and bank rescan ten times a second, forever. This ticker,
    -- not any event, is what advances a run -- see the runner's header.
    if run then StepRun() end
    if not QueueEmpty() then TryFlushQueue() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")

local function OnEvent(_, event, arg1, arg2)
    if event == "PLAYER_LOGIN" then
        db = CommanderArmoryDB
        E = E or CommanderArmoryEngine
        ResolveThemeOverrides()

        local store = CharStore()
        selectedIndex = tonumber(store.selected) or 0
        if not store.sets[selectedIndex] then selectedIndex = 0 end
        LoadIgnoreScratch(SelectedSet())

        BuildSecure()

        events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        events:RegisterEvent("UNIT_INVENTORY_CHANGED")
        events:RegisterEvent("BAG_UPDATE")
        events:RegisterEvent("BAG_UPDATE_DELAYED")
        events:RegisterEvent("ITEM_LOCK_CHANGED")
        events:RegisterEvent("CURSOR_CHANGED")
        events:RegisterEvent("BANKFRAME_OPENED")
        events:RegisterEvent("BANKFRAME_CLOSED")
        events:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
        events:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED")
        events:RegisterEvent("MERCHANT_SHOW")
        events:RegisterEvent("MERCHANT_CLOSED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
        events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        events:RegisterEvent("UI_ERROR_MESSAGE")
        -- The bind-confirm family is guarded rather than assumed: IsEventValid
        -- is the client's own answer, and RegisterEvent on a name this build
        -- does not know is an error rather than a no-op.
        for name in pairs(BIND_POPUPS) do
            local valid = true
            if C_EventUtils and C_EventUtils.IsEventValid then
                local ok, result = pcall(C_EventUtils.IsEventValid, name)
                valid = (not ok) or result
            end
            if valid then pcall(events.RegisterEvent, events, name) end
        end

        ProbeEquipmentSets()
        ProbeInventoryItemsForSlot()

        C_Timer.NewTicker(TICK, Tick)
        Commander.AddListener(COMMANDER_ARMORY_EVENTS.UPDATE, Apply)
        Apply()
        return
    end

    if event == "GET_ITEM_INFO_RECEIVED" then
        local itemID = tonumber(arg1)
        if itemID then pendingInfo[itemID] = nil end
        -- Everything cached under this item is now answerable; clearing the
        -- backoff stamps is cheaper than tracking which keys map to which id.
        for _, entry in pairs(detail) do
            if entry.itemID == itemID then entry.probedAt = nil end
        end
        Invalidate()
        if secureDirty then UpdateSecure() end
        return
    end

    if event == "BANKFRAME_OPENED" then
        bankOpen = true
        CacheBank()
        Invalidate()
        Notify()
        return
    end

    if event == "BANKFRAME_CLOSED" then
        -- Refresh on the way out too: the player almost certainly moved
        -- something while it was open, and a cache one visit stale is worse
        -- than no cache because it still reads as authoritative.
        CacheBank()
        bankOpen = false
        Invalidate()
        Notify()
        return
    end

    if event == "PLAYERBANKSLOTS_CHANGED" or event == "PLAYERBANKBAGSLOTS_CHANGED" then
        if bankOpen then CacheBank() end
        Invalidate()
        return
    end

    if BIND_POPUPS[event] then
        local slot = tonumber(arg1)
        if not slot then return end
        if DB("AutoConfirmBoE", false) then
            -- Order is load-bearing. The dialog's OnHide calls
            -- CancelPendingEquip, so hiding first silently cancels the equip
            -- and strands the run with no error anywhere.
            EquipPendingItem(slot)
            StaticPopup_Hide(BIND_POPUPS[event])
        elseif run then
            runState.paused = "BIND_CONFIRM"
            runState.status = "WAITING"
            Say(format("waiting on you: %s will bind to you. Answer the prompt and the swap carries on.",
                D.SlotLabel(slot)))
            Notify()
        end
        return
    end

    if event == "UI_ERROR_MESSAGE" then
        -- Attribution. The client's own text is the most precise thing anyone
        -- can say about a refused move, and a unique-equipped collision is the
        -- one the server knows about and no curated table ever will.
        local id
        if _G.GetGameMessageInfo and arg1 then
            local ok, value = pcall(_G.GetGameMessageInfo, arg1)
            if ok then id = value end
        end
        if id and UNIQUE_ERRORS[id] then
            runState.uniqueConflict = arg2
            Warn(arg2 or "you cannot equip more than one of those.")
        end
        if run then
            runState.lastError = arg2
            runState.lastErrorID = id
        end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        Invalidate()
        UpdateSecure()
        TryFlushQueue()
        Notify()
        return
    end

    if event == "MERCHANT_SHOW" or event == "MERCHANT_CLOSED" then
        Invalidate()
        Notify()
        return
    end

    if event == "ITEM_LOCK_CHANGED" then
        -- Debounced, not acted on. Several locks change per move and reacting
        -- per-event re-enters the sequencer mid-flight, so this only says "the
        -- world moved, let it settle" -- the ticker takes it from there against
        -- a fresh snapshot.
        Invalidate()
        if run then settleUntil = GetTime() + SETTLE_LOCK end
        return
    end

    -- PLAYER_EQUIPMENT_CHANGED, UNIT_INVENTORY_CHANGED, BAG_UPDATE(_DELAYED),
    -- CURSOR_CHANGED, PLAYER_REGEN_DISABLED. BAG_UPDATE matters even though the
    -- ticker drives the run: a bag re-sort moves items under a plan, and the
    -- next snapshot has to see it before any coordinate is reused.
    Invalidate()
    if event == "PLAYER_EQUIPMENT_CHANGED" or event == "BAG_UPDATE_DELAYED" then
        Notify()
    end
end

events:SetScript("OnEvent", OnEvent)
