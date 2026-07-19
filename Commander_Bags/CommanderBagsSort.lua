-- Commander Bags: auto-sort engine.
--
-- Sorts the general-purpose bags (backpack + bags whose bag family is 0)
-- into the order selected in settings. Special bags (quivers, soul bags,
-- profession bags) are left untouched — their slot restrictions make blind
-- moves unsafe. Items are compacted to the front (backpack first), empty
-- slots collect at the end.
--
-- Item moves use C_Container.PickupContainerItem swaps driven by a slow
-- ticker: one swap per tick, locked slots respected, so the server's item
-- locks are never raced. The sort runs only out of combat with an empty
-- cursor.

local GENERAL_BAGS = { 0, 1, 2, 3, 4 }
local TICK_INTERVAL = 0.1
local MAX_STEPS = 300

local sortTicker
local stepsTaken = 0

local function StopSort(message)
    if sortTicker then
        sortTicker:Cancel()
        sortTicker = nil
    end
    if message then
        print("Commander Bags: " .. message)
    end
end

-- A bag participates when it exists and holds anything (family 0)
local function IsSortableBag(bag)
    local slots = C_Container.GetContainerNumSlots(bag)
    if not slots or slots == 0 then return false end
    if bag == 0 then return true end
    local _, family = C_Container.GetContainerNumFreeSlots(bag)
    return family == 0
end

-- Ordered list of every slot the sort may touch
local function CollectSlots()
    local slots = {}
    for _, bag in ipairs(GENERAL_BAGS) do
        if IsSortableBag(bag) then
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                slots[#slots + 1] = { bag = bag, slot = slot }
            end
        end
    end
    return slots
end

local function ReadSlot(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or not info.itemID then return nil end
    local entry = {
        itemID = info.itemID,
        count = info.stackCount or 1,
        locked = info.isLocked or false,
        quality = info.quality or -1,
        name = "", ilvl = 0, classID = 99, subClassID = 99,
    }
    local name, _, quality, ilvl = C_Item.GetItemInfo(info.itemID)
    if name then
        entry.name = name
        entry.quality = quality or entry.quality
        entry.ilvl = ilvl or 0
    end
    local classID, subClassID = select(6, C_Item.GetItemInfoInstant(info.itemID))
    entry.classID = classID or 99
    entry.subClassID = subClassID or 99
    return entry
end

-- Comparators: each returns true when a should come before b.
-- Every comparator MUST be a total order on slot CONTENT (itemID + count):
-- table.sort is unstable, and a plan recomputed each tick under a partial
-- order flips between tied arrangements, making the executor ping-pong two
-- equal-item stacks forever. The itemID+count tail guarantees ties only
-- between literally identical stacks, which the executor treats as already
-- in place.
local function ContentTiebreak(a, b)
    if a.itemID ~= b.itemID then return a.itemID < b.itemID end
    return a.count > b.count
end

local Comparators = {
    QUALITY = function(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
        if a.name ~= b.name then return a.name < b.name end
        return ContentTiebreak(a, b)
    end,
    ILVL = function(a, b)
        if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
        if a.quality ~= b.quality then return a.quality > b.quality end
        if a.name ~= b.name then return a.name < b.name end
        return ContentTiebreak(a, b)
    end,
    CATEGORY = function(a, b)
        if a.classID ~= b.classID then return a.classID < b.classID end
        if a.subClassID ~= b.subClassID then return a.subClassID < b.subClassID end
        if a.quality ~= b.quality then return a.quality > b.quality end
        if a.name ~= b.name then return a.name < b.name end
        return ContentTiebreak(a, b)
    end,
    NAME = function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return ContentTiebreak(a, b)
    end,
}

-- The desired arrangement, computed fresh each step so player-made changes
-- mid-sort never corrupt the plan: sorted items fill the slot list front to
-- back; nil means the slot should end up empty. Works from the current[]
-- snapshot Step already read — the old version re-read every slot a second
-- time per tick (GetItemInfo per slot, doubled).
local function ComputePlan(slots, current)
    local items = {}
    for i = 1, #slots do
        local entry = current[i]
        if entry then
            items[#items + 1] = entry
        end
    end
    local compare = Comparators[CommanderBagsDB.SortOrder] or Comparators.QUALITY
    table.sort(items, compare)
    local desired = {}
    for i = 1, #slots do
        desired[i] = items[i]
    end
    return desired
end

local function SameContent(entry, desired)
    if entry == nil and desired == nil then return true end
    if entry == nil or desired == nil then return false end
    return entry.itemID == desired.itemID and entry.count == desired.count
end

-- One swap per tick: find the first out-of-place slot, find a mismatched
-- source slot holding what belongs there, and swap. Every swap fixes at
-- least one position, so the sort always converges.
local ticksTaken = 0

local function Step()
    if InCombatLockdown() then
        StopSort("sorting paused by combat — click sort again after the fight")
        return
    end
    -- SpellIsTargeting: a spell awaiting an item target (Disenchant,
    -- Prospecting, enchants) is DELIVERED by PickupContainerItem — sorting
    -- through it would cast the spell on an arbitrary item
    if CursorHasItem() or SpellIsTargeting() then
        StopSort("sorting stopped — hands full (item or spell on the cursor)")
        return
    end
    -- Hard safety cap on total ticks (covers pathological lock churn);
    -- the swap budget below is what normally bounds the sort
    ticksTaken = ticksTaken + 1
    if ticksTaken > MAX_STEPS * 3 then
        StopSort("sorting stopped after too many moves")
        return
    end

    local slots = CollectSlots()
    local current = {}
    local anyLocked = false
    for i, s in ipairs(slots) do
        current[i] = ReadSlot(s.bag, s.slot)
        if current[i] and current[i].locked then
            anyLocked = true
        end
    end
    local desired = ComputePlan(slots, current)

    local target
    for i = 1, #slots do
        if not SameContent(current[i], desired[i]) then
            target = i
            break
        end
    end
    if not target then
        StopSort("bags sorted")
        return
    end

    -- Wait out server item locks rather than racing them
    if anyLocked then return end

    local source
    for j = 1, #slots do
        if j ~= target and not SameContent(current[j], desired[j])
            and SameContent(current[j], desired[target]) then
            source = j
            break
        end
    end
    if not source then
        -- Desired content not found (player moved/used it mid-sort); the
        -- fresh plan next tick will account for it
        return
    end

    -- Only ticks that actually issue a swap consume the move budget;
    -- lock-wait ticks (a few per swap at normal latency) are free
    stepsTaken = stepsTaken + 1
    if stepsTaken > MAX_STEPS then
        StopSort("sorting stopped after too many moves")
        return
    end

    local s, t = slots[source], slots[target]
    C_Container.PickupContainerItem(s.bag, s.slot)
    C_Container.PickupContainerItem(t.bag, t.slot)
    if CursorHasItem() then
        -- The target was occupied: its old content is on the cursor; put it
        -- where the source was, completing the swap
        C_Container.PickupContainerItem(s.bag, s.slot)
    end
end

-- Shared with the settings panel, the /cb sort subcommand, and the bag
-- portrait click handler in CommanderBags.lua
function CommanderBags_SortBags()
    if sortTicker then
        return -- already sorting
    end
    if InCombatLockdown() then
        print("Commander Bags: cannot sort during combat")
        return
    end
    if CursorHasItem() or SpellIsTargeting() then
        print("Commander Bags: finish what's on your cursor first")
        return
    end
    stepsTaken = 0
    ticksTaken = 0
    sortTicker = C_Timer.NewTicker(TICK_INTERVAL, Step)
end
