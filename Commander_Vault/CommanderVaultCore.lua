-- Commander Vault: the model layer.
--
-- Everything above this file (search, the advisor, the sort, the window) reads
-- the bank through the one snapshot built here, so there is exactly one place
-- that knows what a bank slot is and exactly one place that has to be right
-- about the container IDs.
--
-- Two facts shape the whole module:
--
--   1. The container API answers for bank containers ONLY between
--      BANKFRAME_OPENED and BANKFRAME_CLOSED. Away from the bank every read
--      comes back empty, which is why the snapshot is written through to a
--      SavedVariable cache: a vault you can only look at while standing in it
--      is the window Blizzard already shipped.
--
--   2. Bank bags are NUM_BAG_SLOTS+1 .. NUM_BAG_SLOTS+NUM_BANKBAGSLOTS — 5..11
--      on this client. NEVER Enum.BagIndex.BankBag_1: that enum is the
--      mainline one, where a reagent bag at 5 shifts the first bank bag to 6,
--      and reading bag 6 as the first bank bag silently caches the wrong
--      containers. (Same trap Commander_Armory documents.)

CommanderVault = CommanderVault or {}
local V = CommanderVault

local BANK = BANK_CONTAINER or -1
local BAG_BACKPACK = 0

-- ---------------------------------------------------------------------------
-- Container identity
-- ---------------------------------------------------------------------------

function V.BankBagRange()
    local first = (NUM_BAG_SLOTS or 4) + 1
    return first, first + (NUM_BANKBAGSLOTS or 7) - 1
end

-- Every container the vault owns, base slots first so the grid reads in the
-- same order the stock window does
function V.BankContainers()
    local list = { BANK }
    local first, last = V.BankBagRange()
    for bag = first, last do
        list[#list + 1] = bag
    end
    return list
end

function V.CarriedContainers()
    local list = {}
    for bag = BAG_BACKPACK, (NUM_BAG_SLOTS or 4) do
        list[#list + 1] = bag
    end
    return list
end

-- What to call a container out loud. The base vault is not "bag -1", and a
-- bank bag's number to the player is its position in the rack, not its
-- container id.
function V.ContainerName(bag)
    if bag == BANK then return ITEMSLOTTEXT or "the vault's own slots" end
    local first, last = V.BankBagRange()
    if bag >= first and bag <= last then
        return string.format("%s %d", BANK_BAG or "Bank Bag", bag - first + 1)
    end
    if bag == BAG_BACKPACK then return BACKPACK_TOOLTIP or "Backpack" end
    if bag >= 1 and bag <= (NUM_BAG_SLOTS or 4) then
        return string.format("%s %d", BAGSLOTTEXT or "Bag", bag)
    end
    return "container " .. tostring(bag)
end

function V.IsBankContainer(bag)
    if bag == BANK then return true end
    local first, last = V.BankBagRange()
    return bag >= first and bag <= last
end

-- ---------------------------------------------------------------------------
-- Live/cached state
--
-- bankOpen is driven by the events rather than by BankFrame:IsShown(), because
-- the module hides that frame when it takes the window over and a hidden frame
-- would otherwise read as "not at the bank".
-- ---------------------------------------------------------------------------

local bankOpen = false

function V.SetBankOpen(value)
    bankOpen = value and true or false
end

function V.IsBankOpen()
    return bankOpen
end

-- ---------------------------------------------------------------------------
-- Sections
--
-- The broad taxonomy the grid groups by. Order is the order they are drawn:
-- what you came to the bank for at the top, what you meant to deal with at the
-- bottom.
-- ---------------------------------------------------------------------------

V.SECTIONS = {
    { key = "EQUIPMENT",  title = "Equipment" },
    { key = "CONSUMABLE", title = "Consumables" },
    { key = "TRADE",      title = "Trade Goods" },
    { key = "RECIPE",     title = "Recipes" },
    { key = "QUEST",      title = "Quest" },
    { key = "CONTAINER",  title = "Containers" },
    { key = "AMMO",       title = "Ammunition" },
    { key = "KEY",        title = "Keys" },
    { key = "MISC",       title = "Miscellaneous" },
    { key = "JUNK",       title = "Junk" },
}

V.SECTION_TITLE = {}
V.SECTION_ORDER = {}
for index, section in ipairs(V.SECTIONS) do
    V.SECTION_TITLE[section.key] = section.title
    V.SECTION_ORDER[section.key] = index
end

-- TBC item class IDs. Named rather than inlined because two of them (5 Reagent
-- and 8 Generic) are near-dead in this expansion and a bare number in a branch
-- would read like a typo.
local CLASS_CONSUMABLE, CLASS_CONTAINER, CLASS_WEAPON = 0, 1, 2
local CLASS_GEM, CLASS_ARMOR, CLASS_REAGENT = 3, 4, 5
local CLASS_PROJECTILE, CLASS_TRADEGOODS, CLASS_RECIPE = 6, 7, 9
local CLASS_QUIVER, CLASS_QUEST, CLASS_KEY = 11, 12, 13

local SECTION_BY_CLASS = {
    [CLASS_CONSUMABLE] = "CONSUMABLE",
    [CLASS_CONTAINER]  = "CONTAINER",
    [CLASS_WEAPON]     = "EQUIPMENT",
    [CLASS_GEM]        = "TRADE",
    [CLASS_ARMOR]      = "EQUIPMENT",
    [CLASS_REAGENT]    = "TRADE",
    [CLASS_PROJECTILE] = "AMMO",
    [CLASS_TRADEGOODS] = "TRADE",
    [CLASS_RECIPE]     = "RECIPE",
    [CLASS_QUIVER]     = "CONTAINER",
    [CLASS_QUEST]      = "QUEST",
    [CLASS_KEY]        = "KEY",
}

-- ---------------------------------------------------------------------------
-- Sections the player authored
--
-- The item class is a decent guess and a poor filing system: "Raid
-- Consumables" is not a thing the client can infer, and it is exactly how
-- people actually think about a bank. An assignment is per itemID and beats
-- every rule below it, greys included — an override is somebody saying they
-- know better, which about their own bank they do.
--
-- Both tables live OUTSIDE DefaultSettings on purpose (the Quartermaster
-- watchlist precedent): Restore Defaults resets options, and this is authored
-- data, not an option.
-- ---------------------------------------------------------------------------

local USER_PREFIX = "USER:"

local function ItemSections()
    CommanderVaultDB = CommanderVaultDB or {}
    CommanderVaultDB.ItemSection = CommanderVaultDB.ItemSection or {}
    return CommanderVaultDB.ItemSection
end

local function SectionOrder()
    CommanderVaultDB = CommanderVaultDB or {}
    CommanderVaultDB.SectionOrder = CommanderVaultDB.SectionOrder or {}
    return CommanderVaultDB.SectionOrder
end

function V.UserSectionOf(itemID)
    return ItemSections()[itemID]
end

-- name = nil clears the assignment. A section is created by being used and
-- disappears when its last item leaves, so there is no separate list to keep
-- in step and no way to end up with an empty section nobody can get rid of.
function V.SetItemSection(itemID, name)
    local assignments = ItemSections()
    if name == nil or name == "" then
        assignments[itemID] = nil
        return
    end
    assignments[itemID] = name
    local order = SectionOrder()
    for _, existing in ipairs(order) do
        if existing == name then return end
    end
    order[#order + 1] = name
end

function V.ClearUserSection(name)
    local assignments = ItemSections()
    local cleared = 0
    for itemID, assigned in pairs(assignments) do
        if assigned == name then
            assignments[itemID] = nil
            cleared = cleared + 1
        end
    end
    local order = SectionOrder()
    for index = #order, 1, -1 do
        if order[index] == name then table.remove(order, index) end
    end
    return cleared
end

-- The authored sections that currently hold something, in the order they were
-- first created
function V.UserSectionList()
    local assignments, live = ItemSections(), {}
    for _, name in pairs(assignments) do live[name] = true end
    local out = {}
    for _, name in ipairs(SectionOrder()) do
        if live[name] then out[#out + 1] = name end
    end
    return out
end

-- Every section key the grid may draw, authored ones first because they are
-- the deliberate ones
function V.OrderedSections()
    local list = {}
    for _, name in ipairs(V.UserSectionList()) do
        list[#list + 1] = { key = USER_PREFIX .. name, title = name, user = true }
    end
    for _, section in ipairs(V.SECTIONS) do
        list[#list + 1] = { key = section.key, title = section.title }
    end
    return list
end

function V.IsUserSection(key)
    return type(key) == "string" and key:sub(1, #USER_PREFIX) == USER_PREFIX
end

function V.UserSectionName(key)
    if not V.IsUserSection(key) then return nil end
    return key:sub(#USER_PREFIX + 1)
end

-- Works for both kinds of key, which is what lets search and the grid stay
-- ignorant of the difference
function V.SectionTitle(key)
    return V.UserSectionName(key) or V.SECTION_TITLE[key] or key
end

-- Sort rank. Authored sections come before every built-in one, in their own
-- order; anything unknown sorts last.
function V.SectionRank(key)
    if V.IsUserSection(key) then
        local name = V.UserSectionName(key)
        for index, existing in ipairs(SectionOrder()) do
            if existing == name then return -1000 + index end
        end
        return -1
    end
    return V.SECTION_ORDER[key] or 99
end

-- Gray is a verdict, not a category: a gray sword is not equipment you are
-- choosing between, it is money you have not collected yet. Quest items are
-- likewise filed by what they are for rather than by their item class, since
-- plenty of them ship as consumables or trinkets. An authored assignment beats
-- both, because it is the one filing rule that came from a person.
function V.SectionOf(row)
    local assigned = V.UserSectionOf(row.itemID)
    if assigned then return USER_PREFIX .. assigned end
    if row.quality == 0 then return "JUNK" end
    if row.isQuest then return "QUEST" end
    return SECTION_BY_CLASS[row.classID] or "MISC"
end

-- The finer label inside a section, used when Grouping is set to Detailed.
-- Equipment groups by the slot it goes in — the question you actually ask of
-- bank gear — and everything else by its own localized subtype, so the labels
-- stay correct in any client language without a translation table.
function V.SubgroupOf(row)
    -- An authored section IS the grouping the player asked for; splitting it
    -- again by subtype would be the module overruling them
    if V.IsUserSection(row.section) then return nil end
    if row.section == "EQUIPMENT" and row.equipLoc and row.equipLoc ~= "" then
        return _G[row.equipLoc] or row.subType or "Equipment"
    end
    if row.section == "JUNK" then return nil end
    return row.subType or row.itemType
end

-- ---------------------------------------------------------------------------
-- Reading a slot
-- ---------------------------------------------------------------------------

local instantCache = {}

-- GetItemInfoInstant is synchronous and never fails for a cached-by-the-client
-- item, so the fast half of an item's identity is always available; the slow
-- half (name, item level, sell price, bind type) may not be, and callers must
-- treat a nil name as "ask again later" rather than as a blank name.
local function InstantOf(itemID)
    local cached = instantCache[itemID]
    if cached then return cached end
    local id, itemType, subType, equipLoc, icon, classID, subClassID =
        C_Item.GetItemInfoInstant(itemID)
    if not id then return nil end
    local entry = {
        itemType = itemType, subType = subType, equipLoc = equipLoc or "",
        icon = icon, classID = classID or 15, subClassID = subClassID or 0,
    }
    instantCache[itemID] = entry
    return entry
end

V.InstantOf = InstantOf

-- Builds one model row from a container slot, or nil for an empty slot.
-- `full` is false when the client has not finished loading the item yet: the
-- row is still usable (icon, count, quality all come from the container) but
-- the caller must come back for it, which is what the GET_ITEM_INFO_RECEIVED
-- refresh is for.
function V.ReadSlot(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or not info.itemID then return nil end
    local itemID = info.itemID
    local row = {
        bag = bag, slot = slot, itemID = itemID,
        count = info.stackCount or 1,
        quality = info.quality or 1,
        icon = info.iconFileID,
        link = info.hyperlink,
        locked = info.isLocked or false,
        bound = info.isBound,
        noValue = info.hasNoValue or false,
        name = nil, ilvl = 0, sellPrice = 0, maxStack = 1, bindType = 0,
        itemType = nil, subType = nil, equipLoc = "", classID = 15, subClassID = 0,
        full = false,
    }

    local instant = InstantOf(itemID)
    if instant then
        row.itemType = instant.itemType
        row.subType = instant.subType
        row.equipLoc = instant.equipLoc
        row.classID = instant.classID
        row.subClassID = instant.subClassID
        row.icon = row.icon or instant.icon
    end

    local name, _, quality, ilvl, minLevel, itemType, subType, maxStack,
        equipLoc, _, sellPrice, classID, subClassID, bindType =
        C_Item.GetItemInfo(row.link or itemID)
    if name then
        row.full = true
        row.name = name
        row.quality = quality or row.quality
        row.ilvl = ilvl or 0
        row.minLevel = minLevel or 0
        row.itemType = itemType or row.itemType
        row.subType = subType or row.subType
        row.maxStack = maxStack or 1
        row.equipLoc = equipLoc or row.equipLoc
        row.sellPrice = sellPrice or 0
        row.classID = classID or row.classID
        row.subClassID = subClassID or row.subClassID
        row.bindType = bindType or 0
    end

    row.isQuest = (row.classID == CLASS_QUEST)
    row.section = V.SectionOf(row)
    return row
end

-- ---------------------------------------------------------------------------
-- The snapshot
--
-- One flat table with no metatables and no closures, so the harness can write
-- one by hand and every consumer can be tested without a bank.
--
--   slots  ordered { bag, slot } for every slot the vault owns, empty included
--   rows   parallel array, nil where the slot is empty
--   items  the non-nil rows, in slot order
--   free / total  slot accounting
--   pending  true while any row is not `full` yet
-- ---------------------------------------------------------------------------

local function BlankSnapshot(scope)
    return { scope = scope, slots = {}, rows = {}, items = {},
             free = 0, total = 0, pending = false, at = 0 }
end

local function ScanContainers(containers, scope)
    local snap = BlankSnapshot(scope)
    for _, bag in ipairs(containers) do
        local count = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, count do
            local index = #snap.slots + 1
            snap.slots[index] = { bag = bag, slot = slot }
            local row = V.ReadSlot(bag, slot)
            snap.rows[index] = row
            snap.total = snap.total + 1
            if row then
                snap.items[#snap.items + 1] = row
                if not row.full then snap.pending = true end
            else
                snap.free = snap.free + 1
            end
        end
    end
    snap.at = time()
    return snap
end

V.bank = BlankSnapshot("BANK")
V.bags = BlankSnapshot("BAGS")

function V.ScanBags()
    V.bags = ScanContainers(V.CarriedContainers(), "BAGS")
    return V.bags
end

-- The bank scan is only meaningful with the bank open; called anywhere else it
-- would replace a good snapshot with an empty one, which is exactly the bug
-- that makes "in your bank" and "gone" the same answer.
function V.ScanBank()
    if not bankOpen then return V.bank end
    V.bank = ScanContainers(V.BankContainers(), "BANK")
    V.bank.live = true
    V.WriteCache(V.bank)
    V.TouchHistory(V.bank)
    return V.bank
end

-- ---------------------------------------------------------------------------
-- The cache
--
-- Written on every live bank scan, read back to populate the window when the
-- player is nowhere near a bank. Rows are stored compactly (one small table
-- per stack, no derived fields) because this is a SavedVariable that grows
-- with every alt, and everything derived is cheap to recompute at read time.
-- ---------------------------------------------------------------------------

function V.CharKey()
    local name = UnitName("player") or "?"
    local realm = GetRealmName() or "?"
    return name, realm
end

local function CacheRoot()
    CommanderVaultCache = CommanderVaultCache or {}
    CommanderVaultCache.chars = CommanderVaultCache.chars or {}
    return CommanderVaultCache
end

function V.CharRecord(create)
    local name, realm = V.CharKey()
    local root = CacheRoot()
    local key = realm .. "|" .. name
    local record = root.chars[key]
    if not record and create then
        record = { name = name, realm = realm }
        root.chars[key] = record
    end
    return record, key
end

function V.WriteCache(snap)
    if not CommanderVaultDB or CommanderVaultDB.RememberBank == false then return end
    local record = V.CharRecord(true)
    local _, class = UnitClass("player")
    record.class = class
    record.level = UnitLevel("player")
    record.money = GetMoney and GetMoney() or record.money
    record.at = snap.at
    record.free = snap.free
    record.total = snap.total
    record.bankSlots = C_Container.GetContainerNumSlots(BANK) or 0
    local items = {}
    for _, row in ipairs(snap.items) do
        items[#items + 1] = {
            id = row.itemID, n = row.count, q = row.quality,
            b = row.bag, s = row.slot, l = row.link,
        }
    end
    record.items = items
    V.InvalidateRoster()
end

-- Rebuilds a full snapshot out of the cache so the window can draw a bank the
-- player is nowhere near. Slot geometry comes from the cached container sizes
-- when they were recorded, so a cached vault keeps its shape.
function V.CachedSnapshot()
    local record = V.CharRecord(false)
    local snap = BlankSnapshot("BANK")
    if not record or not record.items then return snap end
    snap.at = record.at or 0
    snap.cached = true
    for _, entry in ipairs(record.items) do
        local row = {
            bag = entry.b, slot = entry.s, itemID = entry.id,
            count = entry.n or 1, quality = entry.q or 1, link = entry.l,
            name = nil, ilvl = 0, sellPrice = 0, maxStack = 1, bindType = 0,
            equipLoc = "", classID = 15, subClassID = 0, full = false,
            cached = true,
        }
        local instant = InstantOf(entry.id)
        if instant then
            row.itemType = instant.itemType
            row.subType = instant.subType
            row.equipLoc = instant.equipLoc
            row.classID = instant.classID
            row.subClassID = instant.subClassID
            row.icon = instant.icon
        end
        local name, _, quality, ilvl, minLevel, itemType, subType, maxStack,
            equipLoc, _, sellPrice, classID, subClassID, bindType =
            C_Item.GetItemInfo(row.link or entry.id)
        if name then
            row.full = true
            row.name = name
            row.quality = quality or row.quality
            row.ilvl = ilvl or 0
            row.minLevel = minLevel or 0
            row.itemType = itemType or row.itemType
            row.subType = subType or row.subType
            row.maxStack = maxStack or 1
            row.equipLoc = equipLoc or row.equipLoc
            row.sellPrice = sellPrice or 0
            row.classID = classID or row.classID
            row.subClassID = subClassID or row.subClassID
            row.bindType = bindType or 0
        else
            snap.pending = true
        end
        row.isQuest = (row.classID == CLASS_QUEST)
        row.section = V.SectionOf(row)
        local index = #snap.slots + 1
        snap.slots[index] = { bag = row.bag, slot = row.slot }
        snap.rows[index] = row
        snap.items[#snap.items + 1] = row
    end
    snap.total = record.total or #snap.items
    snap.free = record.free or 0
    return snap
end

-- The snapshot the window should be drawing: live while the bank is open,
-- the last cached one everywhere else.
function V.CurrentBank()
    if bankOpen and V.bank.live then return V.bank end
    return V.CachedSnapshot()
end

-- ---------------------------------------------------------------------------
-- The roster
--
-- The cache is account-wide, so the moment a second character has stood at a
-- banker the module can answer "where did I put it" rather than only "is it
-- here". Alts are read from the cache and only from the cache; the played
-- character is always read live, because the client will answer for its own
-- bank even with the bank shut.
-- ---------------------------------------------------------------------------

-- Every remembered character, this one included, newest snapshot first.
-- Memoized: the tooltip layer asks for this on every mouseover, and the answer
-- only changes when a bank is scanned or a character is forgotten.
local rosterCache, rosterGen, rosterBuiltGen = nil, 0, -1

function V.InvalidateRoster()
    rosterGen = rosterGen + 1
end

function V.AllRecords()
    if rosterCache and rosterBuiltGen == rosterGen then return rosterCache end
    local root = CacheRoot()
    local list = {}
    local _, myKey = V.CharRecord(false)
    for key, record in pairs(root.chars) do
        if type(record) == "table" then
            record.key = key
            record.isPlayer = (key == myKey)
            list[#list + 1] = record
        end
    end
    table.sort(list, function(a, b)
        -- The played character first, then by how fresh the snapshot is: a
        -- roster sorted by name buries the one you are standing in
        if a.isPlayer ~= b.isPlayer then return a.isPlayer end
        if (a.at or 0) ~= (b.at or 0) then return (a.at or 0) > (b.at or 0) end
        return (a.name or "") < (b.name or "")
    end)
    rosterCache, rosterBuiltGen = list, rosterGen
    return list
end

function V.ForgetCharacter(key)
    local root = CacheRoot()
    if root.chars[key] then
        root.chars[key] = nil
        V.InvalidateRoster()
        return true
    end
    return false
end

local function CachedCount(record, itemID)
    local total = 0
    if not record or not record.items then return 0 end
    for _, entry in ipairs(record.items) do
        if entry.id == itemID then total = total + (entry.n or 1) end
    end
    return total
end

-- Where this item is, across the whole account. Returns:
--   carried  in the played character's bags
--   vault    in the played character's bank
--   others   the total across every other remembered character
--   where    { {name, realm, class, count}, ... } for those others, biggest first
--   guild    what your guild bank is holding, from its cache
--
-- The played character's two numbers come from GetItemCount, which knows the
-- bank even when the bank is shut — the cache would answer the same question
-- with a snapshot that could be a week old, and it is only ever the right
-- source for somebody who is not logged in.
function V.CountsFor(itemID)
    local carried, vault = 0, 0
    if C_Item and C_Item.GetItemCount then
        carried = C_Item.GetItemCount(itemID, false) or 0
        local withBank = C_Item.GetItemCount(itemID, true) or 0
        vault = math.max(withBank - carried, 0)
    end
    local others, where = 0, {}
    local _, myKey = V.CharRecord(false)
    local onlyRealm = CommanderVaultDB and CommanderVaultDB.RosterCurrentRealmOnly
    local myRealm = select(2, V.CharKey())
    for _, record in ipairs(V.AllRecords()) do
        if record.key ~= myKey and not (onlyRealm and record.realm ~= myRealm) then
            local count = CachedCount(record, itemID)
            if count > 0 then
                others = others + count
                where[#where + 1] = {
                    name = record.name, realm = record.realm,
                    class = record.class, count = count, at = record.at,
                }
            end
        end
    end
    table.sort(where, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return (a.name or "") < (b.name or "")
    end)
    local guild = V.GuildCountFor and V.GuildCountFor(itemID) or 0
    return carried, vault, others, where, guild
end

-- A whole remembered vault rebuilt as model rows, for the roster view. Same
-- shape ReadSlot produces, so search and the section grouping work on an alt's
-- vault exactly as they do on your own.
function V.RecordSnapshot(record)
    local snap = BlankSnapshot("ROSTER")
    if not record or not record.items then return snap end
    snap.cached = true
    snap.at = record.at or 0
    snap.owner = record
    for _, entry in ipairs(record.items) do
        local row = {
            bag = entry.b, slot = entry.s, itemID = entry.id,
            count = entry.n or 1, quality = entry.q or 1, link = entry.l,
            ilvl = 0, sellPrice = 0, maxStack = 1, bindType = 0,
            equipLoc = "", classID = 15, subClassID = 0, full = false,
            cached = true, foreign = true,
        }
        local instant = InstantOf(entry.id)
        if instant then
            row.itemType, row.subType = instant.itemType, instant.subType
            row.equipLoc, row.classID, row.subClassID =
                instant.equipLoc, instant.classID, instant.subClassID
            row.icon = instant.icon
        end
        local name, _, quality, ilvl, minLevel, itemType, subType, maxStack,
            equipLoc, _, sellPrice, classID, subClassID, bindType =
            C_Item.GetItemInfo(row.link or entry.id)
        if name then
            row.full, row.name = true, name
            row.quality = quality or row.quality
            row.ilvl, row.minLevel = ilvl or 0, minLevel or 0
            row.itemType, row.subType = itemType or row.itemType, subType or row.subType
            row.maxStack, row.equipLoc = maxStack or 1, equipLoc or row.equipLoc
            row.sellPrice = sellPrice or 0
            row.classID, row.subClassID = classID or row.classID, subClassID or row.subClassID
            row.bindType = bindType or 0
        else
            snap.pending = true
        end
        row.isQuest = (row.classID == 12)
        row.section = V.SectionOf(row)
        local index = #snap.slots + 1
        snap.slots[index] = { bag = row.bag, slot = row.slot }
        snap.rows[index] = row
        snap.items[#snap.items + 1] = row
    end
    snap.total = record.total or #snap.items
    snap.free = record.free or 0
    return snap
end

-- ---------------------------------------------------------------------------
-- Dwell history
--
-- "How long has this been sitting here" is the question that makes a bank
-- clean-up possible at all, and nothing in the client answers it. One epoch
-- stamp per itemID per character, set the first time the item is seen in the
-- bank and cleared when it leaves, so a withdrawn-and-redeposited item starts
-- its clock again rather than reading as ancient.
-- ---------------------------------------------------------------------------

function V.TouchHistory(snap)
    if not CommanderVaultDB or CommanderVaultDB.TrackDwell == false then return end
    local record = V.CharRecord(true)
    local seen = record.seen or {}
    local now = time()
    local present = {}
    for _, row in ipairs(snap.items) do
        present[row.itemID] = true
        if not seen[row.itemID] then
            seen[row.itemID] = now
        end
    end
    for itemID in pairs(seen) do
        if not present[itemID] then
            seen[itemID] = nil
        end
    end
    record.seen = seen
end

-- Days this itemID has been sitting in the bank, or nil when unknown
function V.DwellDays(itemID)
    local record = V.CharRecord(false)
    local since = record and record.seen and record.seen[itemID]
    if not since then return nil end
    return math.floor((time() - since) / 86400)
end

-- ---------------------------------------------------------------------------
-- Saved gear sets
--
-- A bank full of gear the advisor calls "outclassed" is, more often than not,
-- a PvP set — kept on purpose, worn on Tuesdays, and the single worst thing
-- this module could ever tell you to disenchant. Commander_Armory owns that
-- answer, so the vault asks it rather than guessing.
--
-- One-directional and entirely optional: with Armory absent, membership is
-- empty and every rule behaves as it did before.
-- ---------------------------------------------------------------------------

local setMembership, setMembershipAt = {}, -1

function V.RefreshSetMembership()
    local reader = _G.CommanderArmory_SetItemIDs
    if type(reader) ~= "function" then
        setMembership = {}
        setMembershipAt = time()
        return setMembership
    end
    local ok, wanted = pcall(reader)
    setMembership = (ok and type(wanted) == "table") and wanted or {}
    setMembershipAt = time()
    return setMembership
end

-- Which saved set wants this item, or nil. Refreshed at most once a second:
-- the grid asks per painted button, and a set the player just edited should
-- still show up without a reload.
function V.SetWanting(itemID)
    if setMembershipAt ~= time() then
        V.RefreshSetMembership()
    end
    return setMembership[itemID]
end

-- ---------------------------------------------------------------------------
-- Aggregation helpers shared by the advisor and the window footer
-- ---------------------------------------------------------------------------

-- Total vendor value of a row (0 for anything the vendor will not take)
function V.RowValue(row)
    if row.noValue then return 0 end
    return (row.sellPrice or 0) * (row.count or 1)
end

function V.TotalValue(rows)
    local total = 0
    for _, row in ipairs(rows) do
        total = total + V.RowValue(row)
    end
    return total
end

-- itemID -> { count, stacks, rows } across a snapshot
function V.Tally(snap)
    local tally = {}
    for _, row in ipairs(snap.items) do
        local entry = tally[row.itemID]
        if not entry then
            entry = { count = 0, stacks = 0, rows = {}, row = row }
            tally[row.itemID] = entry
        end
        entry.count = entry.count + (row.count or 1)
        entry.stacks = entry.stacks + 1
        entry.rows[#entry.rows + 1] = row
    end
    return tally
end

-- Coin string in the suite's compact form: "12g 30s", never a bare copper
-- count, and never three segments where two carry the meaning
function V.Money(copper)
    copper = math.floor(copper or 0)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local bronze = copper % 100
    if gold > 0 then
        return string.format("|cffffd700%d|rg |cffc7c7cf%d|rs", gold, silver)
    elseif silver > 0 then
        return string.format("|cffc7c7cf%d|rs |cffeda55f%d|rc", silver, bronze)
    end
    return string.format("|cffeda55f%d|rc", bronze)
end
