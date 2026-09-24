-- Commander Vault: the mover.
--
-- Two jobs, both of them "touch the player's items", both of them therefore
-- built the paranoid way: one action per tick off a slow ticker, a fresh read
-- of the world every tick, a hard budget, and an immediate stop the moment the
-- cursor, combat, or a targeting spell says the player is doing something else.
--
--   Sort      arranges the vault. Two phases: merge partial stacks back
--             together (which is what actually gives slots back), then swap
--             the remaining stacks into the chosen order.
--
--   Transfer  moves items between bags and bank. Deliberately NOT a swap
--             dance: with the bank frame open the client's own
--             UseContainerItem already means "put this where it belongs", and
--             borrowing that is both shorter and safer than reimplementing it.
--             It is gated on the bank frame genuinely being open, because the
--             exact same call with the bank closed eats the potion.

CommanderVault = CommanderVault or {}
local V = CommanderVault

local TICK = 0.12
local MAX_MOVES = 400

local ticker, movesTaken, ticksTaken
local currentJob

local function Stop(message)
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    currentJob = nil
    if message then
        print("Commander Vault: " .. message)
    end
    if COMMANDER_VAULT_EVENTS then
        Commander.Notify(COMMANDER_VAULT_EVENTS.UPDATE)
    end
end

V.StopMover = Stop

function V.IsMoving()
    return ticker ~= nil
end

-- The one gate both jobs run through every single tick. A sort that keeps
-- going while a Disenchant is waiting for a target does not sort your bank, it
-- disenchants whatever the plan touches next.
local function Blocked()
    if InCombatLockdown() then return "paused by combat" end
    if CursorHasItem() then return "stopped — something is on your cursor" end
    if SpellIsTargeting() then return "stopped — a spell is waiting for a target" end
    return nil
end

-- ---------------------------------------------------------------------------
-- Which containers a sort may touch
-- ---------------------------------------------------------------------------

-- A container with a family is a quiver, a soul bag, a herb bag: its slots
-- accept only some items, so a blind swap into it fails silently and leaves
-- the plan permanently unsatisfiable. Those are never touched.
local function IsGeneralContainer(bag)
    local slots = C_Container.GetContainerNumSlots(bag) or 0
    if slots == 0 then return false end
    if bag == (BANK_CONTAINER or -1) or bag == 0 then return true end
    local _, family = C_Container.GetContainerNumFreeSlots(bag)
    return (family or 0) == 0
end

V.IsGeneralContainer = IsGeneralContainer

local function CollectSlots(containers)
    local slots = {}
    for _, bag in ipairs(containers) do
        if IsGeneralContainer(bag) then
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                slots[#slots + 1] = { bag = bag, slot = slot }
            end
        end
    end
    return slots
end

-- ---------------------------------------------------------------------------
-- Comparators
--
-- Every comparator MUST be a total order on slot CONTENT. table.sort is
-- unstable, and this plan is recomputed from scratch every tick: under a
-- partial order two tied stacks flip between arrangements and the executor
-- ping-pongs them forever. The itemID+count tail guarantees that ties happen
-- only between literally identical stacks, which the executor reads as already
-- in place. (Learned the hard way in Commander_Bags; do not remove it.)
-- ---------------------------------------------------------------------------

local function Tiebreak(a, b)
    if a.itemID ~= b.itemID then return a.itemID < b.itemID end
    return (a.count or 1) > (b.count or 1)
end

local function ByName(a, b)
    local an, bn = a.name or "", b.name or ""
    if an ~= bn then return an < bn end
    return Tiebreak(a, b)
end

V.Comparators = {
    QUALITY = function(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        if (a.ilvl or 0) ~= (b.ilvl or 0) then return (a.ilvl or 0) > (b.ilvl or 0) end
        return ByName(a, b)
    end,
    ILVL = function(a, b)
        if (a.ilvl or 0) ~= (b.ilvl or 0) then return (a.ilvl or 0) > (b.ilvl or 0) end
        if a.quality ~= b.quality then return a.quality > b.quality end
        return ByName(a, b)
    end,
    -- The vault's own taxonomy rather than the raw class ID, so the sorted
    -- order and the grouped display agree with each other
    CATEGORY = function(a, b)
        local ao = V.SectionRank(a.section)
        local bo = V.SectionRank(b.section)
        if ao ~= bo then return ao < bo end
        if (a.classID or 0) ~= (b.classID or 0) then return (a.classID or 0) < (b.classID or 0) end
        if (a.subClassID or 0) ~= (b.subClassID or 0) then return (a.subClassID or 0) < (b.subClassID or 0) end
        if a.quality ~= b.quality then return a.quality > b.quality end
        return ByName(a, b)
    end,
    NAME = ByName,
    VALUE = function(a, b)
        local av, bv = V.RowValue(a), V.RowValue(b)
        if av ~= bv then return av > bv end
        return ByName(a, b)
    end,
}

-- ---------------------------------------------------------------------------
-- Phase one: merge partial stacks
--
-- Split exactly the amount the destination can take and drop it there, rather
-- than picking up a whole stack and hoping the remainder lands somewhere sane.
-- The cursor is empty again at the end of every merge, which is what lets the
-- Blocked() cursor check stay strict.
-- ---------------------------------------------------------------------------

local function FindMerge(slots)
    local partials = {}
    for index, position in ipairs(slots) do
        local row = V.ReadSlot(position.bag, position.slot)
        if row and (row.maxStack or 1) > 1 and row.count < row.maxStack then
            if row.locked then return nil, true end
            local bucket = partials[row.itemID]
            if bucket then
                -- Move from the smaller stack into the larger one: fewer
                -- moves, and the leftover stack is the one that empties
                local from, to = row, bucket
                local fromIndex, toIndex = index, bucket._index
                if from.count > to.count then
                    from, to = to, from
                    fromIndex, toIndex = toIndex, index
                end
                local room = (to.maxStack or 1) - to.count
                local amount = math.min(room, from.count)
                if amount > 0 then
                    return {
                        from = slots[fromIndex], to = slots[toIndex], amount = amount,
                    }
                end
            else
                row._index = index
                partials[row.itemID] = row
            end
        end
    end
    return nil, false
end

-- ---------------------------------------------------------------------------
-- Phase two: arrange
-- ---------------------------------------------------------------------------

local function ComputePlan(slots, current, order)
    local items = {}
    for index = 1, #slots do
        if current[index] then items[#items + 1] = current[index] end
    end
    local compare = V.Comparators[order] or V.Comparators.QUALITY
    table.sort(items, compare)
    local desired = {}
    for index = 1, #slots do desired[index] = items[index] end
    return desired
end

local function SameContent(a, b)
    if a == nil and b == nil then return true end
    if a == nil or b == nil then return false end
    return a.itemID == b.itemID and a.count == b.count
end

local function SortStep(job)
    local slots = CollectSlots(job.containers)
    if #slots == 0 then
        Stop("nothing here to sort")
        return
    end

    if not job.merged then
        local merge, locked = FindMerge(slots)
        if locked then return end
        if merge then
            movesTaken = movesTaken + 1
            if movesTaken > MAX_MOVES then
                Stop("stopped after too many moves")
                return
            end
            C_Container.SplitContainerItem(merge.from.bag, merge.from.slot, merge.amount)
            C_Container.PickupContainerItem(merge.to.bag, merge.to.slot)
            -- A merge that could not be delivered (the destination filled up
            -- between the read and the drop) must not leave the stack on the
            -- cursor for the next tick's Blocked() check to trip over
            if CursorHasItem() then
                C_Container.PickupContainerItem(merge.from.bag, merge.from.slot)
            end
            return
        end
        job.merged = true
    end

    local current, anyLocked = {}, false
    for index, position in ipairs(slots) do
        local row = V.ReadSlot(position.bag, position.slot)
        current[index] = row
        if row and row.locked then anyLocked = true end
    end
    local desired = ComputePlan(slots, current, job.order)

    local target
    for index = 1, #slots do
        if not SameContent(current[index], desired[index]) then
            target = index
            break
        end
    end
    if not target then
        Stop(job.doneMessage)
        return
    end
    if anyLocked then return end

    local source
    for index = 1, #slots do
        if index ~= target and not SameContent(current[index], desired[index])
            and SameContent(current[index], desired[target]) then
            source = index
            break
        end
    end
    if not source then
        -- The plan named content that is no longer there (the player moved or
        -- used it); next tick's fresh plan accounts for it
        return
    end

    movesTaken = movesTaken + 1
    if movesTaken > MAX_MOVES then
        Stop("stopped after too many moves")
        return
    end
    local from, to = slots[source], slots[target]
    C_Container.PickupContainerItem(from.bag, from.slot)
    C_Container.PickupContainerItem(to.bag, to.slot)
    if CursorHasItem() then
        -- The target was occupied; its old contents are on the cursor and go
        -- where the source was, completing the swap
        C_Container.PickupContainerItem(from.bag, from.slot)
    end
end

-- ---------------------------------------------------------------------------
-- Transfers
-- ---------------------------------------------------------------------------

-- The bank frame genuinely being open is what makes UseContainerItem mean
-- "move this", so this is checked on every tick and not merely at the start.
local function BankIsUsable()
    return V.IsBankOpen() and BankFrame and BankFrame:IsShown()
end

local function TransferStep(job)
    if not BankIsUsable() then
        Stop("transfer stopped — the bank closed")
        return
    end
    local moved = false
    for _, bag in ipairs(job.containers) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local row = V.ReadSlot(bag, slot)
            if row and not row.locked and job.wants(row) then
                movesTaken = movesTaken + 1
                if movesTaken > MAX_MOVES then
                    Stop("stopped after too many moves")
                    return
                end
                C_Container.UseContainerItem(bag, slot)
                moved = true
                break
            end
        end
        if moved then break end
    end
    if not moved then
        Stop(string.format(job.doneMessage, movesTaken))
    end
end

-- ---------------------------------------------------------------------------
-- Driving
-- ---------------------------------------------------------------------------

local function Run(job)
    if ticker then
        print("Commander Vault: already working — let it finish")
        return false
    end
    local blocked = Blocked()
    if blocked then
        print("Commander Vault: " .. blocked)
        return false
    end
    movesTaken, ticksTaken = 0, 0
    currentJob = job
    ticker = C_Timer.NewTicker(TICK, function()
        local reason = Blocked()
        if reason then
            Stop(reason)
            return
        end
        ticksTaken = ticksTaken + 1
        if ticksTaken > MAX_MOVES * 3 then
            Stop("stopped after too many moves")
            return
        end
        local ok, err = pcall(job.step, job)
        if not ok then
            Stop("stopped after an error")
            geterrorhandler()(err)
        end
    end)
    return true
end

function CommanderVault_SortBank()
    if not V.IsBankOpen() then
        print("Commander Vault: open the bank first")
        return
    end
    return Run({
        step = SortStep,
        containers = V.BankContainers(),
        order = (CommanderVaultDB and CommanderVaultDB.SortOrder) or "CATEGORY",
        doneMessage = "vault sorted",
    })
end

function CommanderVault_SortBags()
    return Run({
        step = SortStep,
        containers = V.CarriedContainers(),
        order = (CommanderVaultDB and CommanderVaultDB.SortOrder) or "CATEGORY",
        doneMessage = "bags sorted",
    })
end

-- wants(row) decides what moves. Kept as a predicate rather than a category
-- list so the window can hand it the current search: "deposit everything I am
-- looking at" is the transfer people actually want.
function CommanderVault_Deposit(wants, label)
    if not BankIsUsable() then
        print("Commander Vault: open the bank first")
        return false
    end
    return Run({
        step = TransferStep,
        containers = V.CarriedContainers(),
        wants = wants,
        doneMessage = (label or "deposited") .. " (%d moved)",
    })
end

function CommanderVault_Withdraw(wants, label)
    if not BankIsUsable() then
        print("Commander Vault: open the bank first")
        return false
    end
    return Run({
        step = TransferStep,
        containers = V.BankContainers(),
        wants = wants,
        doneMessage = (label or "withdrew") .. " (%d moved)",
    })
end

-- The named deposits the window's button offers. Each is just a predicate;
-- quest items are excluded from every one of them, because a quest item in the
-- bank is a quest you cannot hand in.
-- A rule offers either a plain `wants` predicate or a `build` that returns one,
-- for the rules whose answer depends on a snapshot worth taking exactly once.
function V.DepositPredicate(rule)
    if type(rule.build) == "function" then return rule.build() end
    return rule.wants
end

-- What counts as a profession material. Item class 7 (Trade Goods) is the
-- bulk of it and class 3 (Gem) the rest; class 5 (Reagent) is deliberately
-- NOT here — on this expansion that class is spell reagents, the candles and
-- ankhs and symbols a caster is consuming, which belong in the bag they are
-- cast from. Two Trade Goods subclasses are finished goods rather than
-- materials: Explosives are the sapper charges a PvPer carries on purpose,
-- and Devices are the engineer's tools (and the jeweler's kit and grinder,
-- which the client files there too).
local CLASS_GEM, CLASS_TRADEGOODS = 3, 7
local SUB_EXPLOSIVES, SUB_DEVICES = 2, 3

-- Tools that live in the Trade Goods class among the mats they work on: the
-- enchanting rods (subclass Enchanting), the Arclight Spanner (Parts) and
-- Flint and Tinder (Other). Depositing any of these would be the module
-- taking the enchanter's rod out of their hands. Rods are read from the
-- Formulary's recipe data when it is loaded, so a rod added there is
-- protected here without a second list; this is the floor.
local PROFESSION_TOOLS = {
    [6218] = true, [6339] = true, [11130] = true, [11145] = true,       -- copper .. truesilver rod
    [16207] = true, [22461] = true, [22462] = true, [22463] = true,     -- arcanite, fel iron, adamantite, eternium rod
    [6219] = true,      -- Arclight Spanner
    [4471] = true,      -- Flint and Tinder
    [6265] = true,      -- Soul Shard: a reagent whatever class the client gives it
}

-- Built per deposit rather than cached: the Formulary can load after this
-- module, and a few hundred recipes once per click costs nothing
function V.ProfessionTools()
    local tools = {}
    for id in pairs(PROFESSION_TOOLS) do tools[id] = true end
    local data = _G.CommanderFormulary_Data
    if type(data) == "table" then
        for _, profession in pairs(data) do
            for _, recipe in ipairs(type(profession) == "table" and profession.recipes or {}) do
                if recipe.category == "RODS" and recipe.creates then
                    tools[recipe.creates] = true
                end
            end
        end
    end
    return tools
end

-- tools is the set from V.ProfessionTools(); the deposit rule builds it once
-- and hands it in, a lone caller may leave it out
function V.IsMaterial(row, tools)
    if row.isQuest or row.quality == 0 then return false end
    if (tools or V.ProfessionTools())[row.itemID] then return false end
    if row.classID == CLASS_GEM then return true end
    if row.classID ~= CLASS_TRADEGOODS then return false end
    local sub = row.subClassID or 0
    return sub ~= SUB_EXPLOSIVES and sub ~= SUB_DEVICES
end

V.DEPOSIT_RULES = {
    TRADE = {
        label = "Trade Goods",
        tooltip = "Deposit every trade good, gem and reagent in your bags.",
        wants = function(row) return row.section == "TRADE" and not row.isQuest end,
    },
    KNOWN = {
        label = "Anything Already Here",
        tooltip = "Deposit stacks of items the vault already holds — the ones you have already decided live here.",
        -- Built as a closure over a set taken ONCE, rather than re-reading the
        -- vault per row per tick: the predicate is called for every bag slot on
        -- every tick of the transfer, and V.CurrentBank() rebuilds a whole
        -- snapshot whenever the bank is not open.
        build = function()
            local held = {}
            for _, banked in ipairs(V.CurrentBank().items) do
                held[banked.itemID] = true
            end
            return function(row)
                if row.isQuest or row.quality == 0 then return false end
                return held[row.itemID] == true
            end
        end,
    },
    -- "Put my mats away": every profession material, told apart from the
    -- things that merely share an item class with them. Keyed on the class
    -- rather than the section so a stack filed under a section of the
    -- player's own ("Enchanting", say) still counts as a mat, which the
    -- Trade Goods rule above cannot promise.
    MATS = {
        label = "Profession Materials",
        tooltip = "Deposit every crafting material in your bags — enchanting dust, essences and shards, cloth, leather, ore and bars, herbs, motes and primals, gems, meat and parts — and nothing that only looks like one: your runed rod and spanner stay, so do the bombs, devices and spell reagents, and anything the Quartermaster's loadout says to carry.",
        build = function()
            local carry, tools = V.LoadoutItems(), V.ProfessionTools()
            return function(row)
                return V.IsMaterial(row, tools) and not carry[row.itemID]
            end
        end,
    },
    GEAR = {
        label = "Spare Gear",
        tooltip = "Deposit every equippable item in your bags that you are not wearing.",
        wants = function(row)
            return row.equipLoc ~= nil and row.equipLoc ~= "" and row.quality > 0 and not row.isQuest
        end,
    },
}
