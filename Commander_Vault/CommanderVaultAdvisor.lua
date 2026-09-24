-- Commander Vault: the advisor.
--
-- The bank is the one place in the game where the interface has nothing to say
-- to you. It shows you 28 icons and leaves the reading to you, which is why
-- everyone's bank ends up holding four partial stacks of the same herb, a
-- quest chain's worth of grey drops, and a set of mail shoulders on a mage.
--
-- This file is the part that reads it back. Each rule returns a finding with a
-- severity, a sentence of plain English, the rows it is talking about, and —
-- crucially — a search string, so the finding is not advice you then have to
-- go and act on by hand: clicking it filters the vault to exactly the items it
-- named.
--
-- Rules never mutate anything. Everything here is a read.

CommanderVault = CommanderVault or {}
local V = CommanderVault

local SEV_INFO, SEV_NOTE, SEV_WARN = 1, 2, 3
V.SEVERITY = { INFO = SEV_INFO, NOTE = SEV_NOTE, WARN = SEV_WARN }

-- ---------------------------------------------------------------------------
-- Small shared lookups
-- ---------------------------------------------------------------------------

-- Which paperdoll slots an equip location competes with. Two-slot locations
-- list both, because a ring is only outclassed when it loses to BOTH rings.
local EQUIP_SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
    INVTYPE_BODY = { 4 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
    INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
    INVTYPE_TABARD = { 19 },
}

local scanTip

-- A tooltip nobody looks at, used for the two questions only a tooltip can
-- answer: whether a recipe is already known, and whether a bind-on-equip item
-- has in fact bound. Created lazily so the harness can run the rules without
-- one.
local function ScanTooltip()
    if scanTip then return scanTip end
    if not CreateFrame then return nil end
    scanTip = CreateFrame("GameTooltip", "CommanderVaultScanTooltip", nil, "GameTooltipTemplate")
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    return scanTip
end

local knownCache = {}

-- True when the client's own tooltip says this recipe is already trained.
-- Memoized per itemID: learning a recipe removes it from the bank anyway, so
-- a stale "false" cannot survive the next scan.
local function RecipeIsKnown(row)
    if row.classID ~= 9 then return false end
    local cached = knownCache[row.itemID]
    if cached ~= nil then return cached end
    local tip = ScanTooltip()
    if not tip or not row.bag then return false end
    tip:ClearLines()
    local ok = pcall(tip.SetBagItem, tip, row.bag, row.slot)
    if not ok then return false end
    local wanted = ITEM_SPELL_KNOWN or "Already known"
    local known = false
    for line = 1, (tip:NumLines() or 0) do
        local fs = _G["CommanderVaultScanTooltipTextLeft" .. line]
        local text = fs and fs:GetText()
        if text and text == wanted then
            known = true
            break
        end
    end
    knownCache[row.itemID] = known
    return known
end

function V.ForgetKnownRecipes()
    knownCache = {}
end

local function EquippedLevel(equipLoc)
    local slots = EQUIP_SLOTS[equipLoc]
    if not slots then return nil end
    local best
    for _, slotID in ipairs(slots) do
        local link = GetInventoryItemLink and GetInventoryItemLink("player", slotID)
        if link then
            local _, _, _, ilvl = C_Item.GetItemInfo(link)
            if ilvl and (not best or ilvl < best) then
                -- The WORST of the two competing slots is the bar to clear:
                -- a ring only has to beat the weaker ring to be worth keeping
                best = ilvl
            end
        else
            -- An empty competing slot means anything wearable is an upgrade
            return nil
        end
    end
    return best
end

-- ---------------------------------------------------------------------------
-- Findings
-- ---------------------------------------------------------------------------

local function Finding(list, finding)
    if finding and finding.rows and #finding.rows > 0 then
        list[#list + 1] = finding
    elseif finding and finding.always then
        list[#list + 1] = finding
    end
    return finding
end

local function Plural(count, one, many)
    return count == 1 and one or many
end

-- 1. Grey items. The simplest finding in the file and reliably the one that
-- pays for the most bag space.
local function RuleJunk(snap)
    local rows, value = {}, 0
    for _, row in ipairs(snap.items) do
        if row.quality == 0 then
            rows[#rows + 1] = row
            value = value + V.RowValue(row)
        end
    end
    if #rows == 0 then return nil end
    return {
        key = "JUNK", severity = SEV_WARN, rows = rows, value = value,
        title = string.format("%d grey %s in the vault", #rows, Plural(#rows, "item", "items")),
        -- Junk in the bank is stuck there: the auto-seller works on your bags.
        -- Carrying it is the one missing step, so the finding offers it.
        detail = value > 0
            and ("Worth " .. V.Money(value)
                .. ". Withdraw it and it sells itself at the next vendor.")
            or "Nothing grey has ever been needed later.",
        search = "junk",
        action = "WITHDRAW_JUNK",
    }
end

-- 2. Partial stacks. Two half-stacks of the same thing is a slot you are
-- paying for and getting nothing back from — and the sort already knows how to
-- fix it, so this finding is one click from being resolved.
local function RulePartialStacks(snap)
    local tally = V.Tally(snap)
    local rows, reclaimable = {}, 0
    for _, entry in pairs(tally) do
        local row = entry.row
        local maxStack = row.maxStack or 1
        if maxStack > 1 and entry.stacks > 1 then
            local ideal = math.ceil(entry.count / maxStack)
            if ideal < entry.stacks then
                reclaimable = reclaimable + (entry.stacks - ideal)
                for _, r in ipairs(entry.rows) do rows[#rows + 1] = r end
            end
        end
    end
    if reclaimable <= 0 then return nil end
    return {
        key = "STACKS", severity = SEV_NOTE, rows = rows, reclaim = reclaimable,
        title = string.format("%d %s wasted on split stacks", reclaimable,
            Plural(reclaimable, "slot", "slots")),
        detail = "Sorting the vault merges them back together.",
        search = "partial",
        action = "SORT",
    }
end

-- 3. Gear this character cannot wear. Bank archaeology at its purest: the mail
-- set a hunter alt mailed over, the plate a paladin outgrew before the mail
-- arrived. Only ever reported for BOUND items — an unbound piece is stock,
-- not clutter.
local function RuleUnusable(snap)
    local rows = {}
    for _, row in ipairs(snap.items) do
        if row.full and row.equipLoc ~= "" and row.quality > 0 then
            local bound = row.bound == true or row.bindType == 1
            -- A piece somebody deliberately put in a saved set is never
            -- clutter, whatever the armour table thinks of it
            if bound and V.RowUsable(row) == false and not V.SetWanting(row.itemID) then
                rows[#rows + 1] = row
            end
        end
    end
    if #rows == 0 then return nil end
    return {
        key = "UNUSABLE", severity = SEV_WARN, rows = rows,
        value = V.TotalValue(rows),
        title = string.format("%d bound %s you cannot use", #rows,
            Plural(#rows, "piece", "pieces")),
        detail = "Soulbound, and the wrong armour type or above your level for good. Vendor or disenchant.",
        search = "-usable bound equippable",
    }
end

-- 4. Gear beaten by what you are already wearing. The check is deliberately
-- conservative: bound only, and it has to lose to the WEAKER of two competing
-- slots, so a second trinket kept for a fight is never called clutter.
local function RuleOutclassed(snap)
    local rows = {}
    for _, row in ipairs(snap.items) do
        if row.full and row.equipLoc ~= "" and row.quality > 0
            and (row.bound == true or row.bindType == 1)
            and V.RowUsable(row) ~= false
            -- The single worst thing this module could tell you to disenchant
            -- is the PvP set you keep in the bank on purpose
            and not V.SetWanting(row.itemID) then
            local bar = EquippedLevel(row.equipLoc)
            if bar and (row.ilvl or 0) > 0 and row.ilvl < bar - 5 then
                rows[#rows + 1] = row
            end
        end
    end
    if #rows == 0 then return nil end
    return {
        key = "OUTCLASSED", severity = SEV_NOTE, rows = rows,
        value = V.TotalValue(rows),
        title = string.format("%d bound %s below what you wear", #rows,
            Plural(#rows, "piece", "pieces")),
        detail = "Every one of these loses to the item already in that slot by more than five item levels.",
        search = "bound equippable",
    }
end

-- 5. Recipes already trained. The tooltip is the only thing in the client that
-- knows, and it is worth asking: a known recipe in the bank is pure dead
-- weight that looks exactly like a valuable one.
local function RuleKnownRecipes(snap)
    if not snap.live then return nil end
    local rows = {}
    for _, row in ipairs(snap.items) do
        if row.classID == 9 and RecipeIsKnown(row) then
            rows[#rows + 1] = row
        end
    end
    if #rows == 0 then return nil end
    return {
        key = "RECIPES", severity = SEV_NOTE, rows = rows,
        value = V.TotalValue(rows),
        title = string.format("%d %s you already know", #rows,
            Plural(#rows, "recipe", "recipes")),
        detail = "The tooltip says already known. Sell them or pass them on.",
        search = "t:recipe",
    }
end

-- 6. Unbound rares and better. The opposite finding to the clutter rules: not
-- "get rid of this" but "you are sitting on money you have forgotten about".
local function RuleTradeable(snap)
    local rows, value = {}, 0
    for _, row in ipairs(snap.items) do
        if row.full and (row.quality or 0) >= 3
            and (row.bindType == 2 or row.bindType == 3) and row.bound ~= true
            and not V.SetWanting(row.itemID) then
            rows[#rows + 1] = row
            value = value + V.RowValue(row)
        end
    end
    if #rows == 0 then return nil end
    return {
        key = "TRADEABLE", severity = SEV_INFO, rows = rows, value = value,
        title = string.format("%d unbound rare%s still tradeable", #rows,
            #rows == 1 and "" or "s"),
        detail = "Still bind-on-equip, so the auction house is still an option.",
        search = "boe q:>=rare",
    }
end

-- 7. Long-dwelling items. Nothing in the client tracks this, so the module
-- does; anything that has sat untouched through a whole raid tier is worth
-- being asked about once.
local function RuleStale(snap)
    local threshold = (CommanderVaultDB and CommanderVaultDB.StaleDays) or 60
    if threshold <= 0 then return nil end
    local rows, oldest = {}, 0
    for _, row in ipairs(snap.items) do
        local days = V.DwellDays(row.itemID)
        if days and days >= threshold and row.quality ~= 0
            and not V.SetWanting(row.itemID) then
            rows[#rows + 1] = row
            if days > oldest then oldest = days end
        end
    end
    if #rows == 0 then return nil end
    return {
        key = "STALE", severity = SEV_INFO, rows = rows,
        title = string.format("%d %s untouched for %d+ days", #rows,
            Plural(#rows, "item", "items"), threshold),
        detail = string.format("The oldest has been sitting here %d days.", oldest),
        search = "old:" .. threshold,
    }
end

-- 8. Things in your bags that have a home here. Matching an existing bank
-- stack is the strongest possible signal: you already decided this item lives
-- in the vault.
local function RuleDeposit(snap, bags)
    if not bags then return nil end
    local bankHas = {}
    for _, row in ipairs(snap.items) do bankHas[row.itemID] = true end
    local rows = {}
    for _, row in ipairs(bags.items) do
        if bankHas[row.itemID] and row.quality ~= 0 and not row.isQuest then
            rows[#rows + 1] = row
        end
    end
    if #rows == 0 then return nil end
    return {
        key = "DEPOSIT", severity = SEV_NOTE, rows = rows, scope = "BAGS",
        title = string.format("%d %s in your bags already live here", #rows,
            Plural(#rows, "stack", "stacks")),
        detail = "Depositing them frees the bag slots and merges the stacks in one move.",
        action = "DEPOSIT",
    }
end

-- 9. Space. Reported as a finding rather than only as a footer number, because
-- a nearly-full bank is the thing that turns a five-second deposit into a
-- ten-minute triage session.
local function RuleSpace(snap)
    if (snap.total or 0) == 0 then return nil end
    local free = snap.free or 0
    local ratio = free / snap.total
    if ratio > 0.15 then return nil end
    local purchased = 0
    local firstBag, lastBag = V.BankBagRange()
    for bag = firstBag, lastBag do
        if (C_Container.GetContainerNumSlots(bag) or 0) > 0 then
            purchased = purchased + 1
        end
    end
    local unbought = (NUM_BANKBAGSLOTS or 7) - purchased
    local detail = string.format("%d of %d slots left.", free, snap.total)
    if unbought > 0 and snap.live then
        detail = detail .. string.format(" %d bank bag %s still unfilled.",
            unbought, Plural(unbought, "slot is", "slots are"))
    end
    return {
        key = "SPACE", severity = free == 0 and SEV_WARN or SEV_NOTE, always = true, rows = {},
        title = free == 0 and "The vault is full" or string.format("%d free %s left",
            free, Plural(free, "slot", "slots")),
        detail = detail,
    }
end

-- The itemIDs the Quartermaster is grading as owned-but-not-carried, plus the
-- loadout slot each one fills. BANKED is that module's word for "you own one
-- but it is not in your bags", which is precisely the gap a bank window can
-- close: CARRIED is already handled, MISSING is a shopping trip, and ELSEWHERE
-- is on an alt.
--
-- Shared between the report's finding and the window's Withdraw button, so
-- "take out what I am short of" is one click rather than a list read off the
-- report by hand. Two empty tables with Quartermaster absent.
function V.LoadoutWanted()
    local readiness = _G.CommanderQuartermaster_LoadoutState
    if type(readiness) ~= "function" then return {}, {} end
    local ok, state = pcall(readiness)
    if not ok or type(state) ~= "table" or type(state.slots) ~= "table" then return {}, {} end
    local wanted, slotNames = {}, {}
    for _, slot in ipairs(state.slots) do
        if slot.state == "BANKED" and slot.entry and slot.entry.id then
            wanted[slot.entry.id] = true
            slotNames[slot.entry.id] = slot.name
        end
    end
    return wanted, slotNames
end

-- Everything the loadout names, whatever state it is in. The deposit rules
-- use this the other way round: an item the Quartermaster wants on your belt
-- is never one a bulk deposit should quietly put away.
function V.LoadoutItems()
    local readiness = _G.CommanderQuartermaster_LoadoutState
    if type(readiness) ~= "function" then return {} end
    local ok, state = pcall(readiness)
    if not ok or type(state) ~= "table" or type(state.slots) ~= "table" then return {} end
    local items = {}
    for _, slot in ipairs(state.slots) do
        if slot.entry and slot.entry.id then items[slot.entry.id] = true end
    end
    return items
end

-- 10. Consumables the Quartermaster says you should be carrying, sitting here
-- instead. The integration is one-directional and entirely optional: with the
-- module absent, the rule simply does not fire.
local function RuleLoadout(snap)
    local wanted, slotNames = V.LoadoutWanted()
    if not next(wanted) then return nil end
    local rows, named = {}, {}
    for _, row in ipairs(snap.items) do
        if wanted[row.itemID] then
            rows[#rows + 1] = row
            named[#named + 1] = slotNames[row.itemID] or (row.name or "?")
        end
    end
    if #rows == 0 then return nil end
    return {
        key = "LOADOUT", severity = SEV_WARN, rows = rows,
        title = string.format("%d loadout %s here, not on you", #rows,
            Plural(#rows, "consumable is", "consumables are")),
        detail = "The Quartermaster is grading these as unready: " ..
            table.concat(named, ", ") .. ". Withdraw before you queue.",
    }
end

-- 11. Gear held for a saved set. Not a complaint — the opposite. Every rule
-- above steps around these, and saying so out loud is what makes their absence
-- from the clutter findings legible rather than mysterious.
local function RuleSets(snap)
    if type(_G.CommanderArmory_SetItemIDs) ~= "function" then return nil end
    local rows, names, seen = {}, {}, {}
    for _, row in ipairs(snap.items) do
        local setName = V.SetWanting(row.itemID)
        if setName then
            rows[#rows + 1] = row
            if not seen[setName] then
                seen[setName] = true
                names[#names + 1] = setName
            end
        end
    end
    if #rows == 0 then return nil end
    table.sort(names)
    return {
        key = "SETS", severity = SEV_INFO, rows = rows,
        title = string.format("%d %s held for a saved set", #rows,
            Plural(#rows, "piece", "pieces")),
        detail = "Kept on purpose for " .. table.concat(names, ", ")
            .. ". Nothing above is counting these as clutter.",
        search = "set",
    }
end

-- ---------------------------------------------------------------------------
-- The report
-- ---------------------------------------------------------------------------

local RULES = {
    RuleSpace, RuleJunk, RuleUnusable, RuleLoadout, RulePartialStacks,
    RuleOutclassed, RuleKnownRecipes, RuleDeposit, RuleStale, RuleTradeable,
    RuleSets,
}

-- Sorted worst-first, and stable inside a severity so the list does not
-- reshuffle itself under the cursor between two identical scans.
function V.BuildReport(snap, bags)
    snap = snap or V.CurrentBank()
    -- Read the saved sets once for the whole report: every clutter rule below
    -- consults them, and a set edited between two rules would make the report
    -- disagree with itself
    V.RefreshSetMembership()
    local findings = {}
    for _, rule in ipairs(RULES) do
        if type(rule) == "function" then
            local ok, finding = pcall(rule, snap, bags)
            if ok then Finding(findings, finding) end
        end
    end
    for index, finding in ipairs(findings) do finding._order = index end
    table.sort(findings, function(a, b)
        if a.severity ~= b.severity then return a.severity > b.severity end
        return a._order < b._order
    end)
    return findings
end

-- The one-line summary the window's header carries: what is in here, what it
-- is worth, and how much room is left.
function V.Summary(snap)
    snap = snap or V.CurrentBank()
    local value, junk = 0, 0
    for _, row in ipairs(snap.items) do
        local rowValue = V.RowValue(row)
        value = value + rowValue
        if row.quality == 0 then junk = junk + rowValue end
    end
    return {
        items = #snap.items,
        free = snap.free or 0,
        total = snap.total or 0,
        value = value,
        junkValue = junk,
        at = snap.at or 0,
        cached = snap.cached or false,
    }
end
