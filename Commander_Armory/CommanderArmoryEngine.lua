-- Commander Armory: the decision layer — pure Lua, zero frames, zero WoW API.
-- Everything that has to be EXACT lives here: item identity, what a saved set
-- means, which items may legally reach a slot, and the ordered plan that turns
-- what you are wearing into what the set says. The host gathers a snapshot of
-- the world, hands it in, gets a plan back, executes actions against the real
-- client, and reports the outcome. Nothing below reads a unit, draws a pixel,
-- or knows what a frame is — which is why a headless harness can drive a
-- fifteen-slot bank-to-body swap through it in a millisecond with no mock at
-- all. The only foreign table it touches is CommanderArmoryData.
--
-- The one design constraint that shaped this file: **refuse before mutating.**
-- Every competitor on this client, Blizzard's own manager included, starts the
-- swap and discovers the problem halfway through, leaving you in four pieces of
-- one set and eleven of another. So the planner is a two-phase machine — it
-- resolves the entire set against the world first, and if any part of it cannot
-- run it returns ok=false with LITERALLY ZERO actions and a reason list precise
-- enough to act on. "It's in your bank" is a different answer from "it's gone",
-- and that distinction is the whole product.
--
-- Two invariants, stated once and defended everywhere:
--   IGNORED is not EMPTY. Ignored means do not touch the slot; empty means
--   strip it; a slot with no entry, or a corrupt one, is ignored. Blizzard's
--   API conflates the two and it is the most-complained-about bug in the
--   feature.
--   A plan is a HYPOTHESIS, not a script. The host re-snapshots and re-plans
--   between passes; idempotent re-planning from live state, not clever
--   ordering, is what makes this survive contact with the client.

CommanderArmoryEngine = {}
local E = CommanderArmoryEngine
local D = CommanderArmoryData

local floor    = math.floor
local max      = math.max
local abs      = math.abs
local format   = string.format
local lower    = string.lower
local strfind  = string.find
local strsub   = string.sub
local strmatch = string.match
local sort     = table.sort
local insert   = table.insert
local tonumber, tostring, type = tonumber, tostring, type
local pairs, ipairs = pairs, ipairs

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

-- ItemRack carries the same watchdog and it is not a safety net for a rare
-- case — it is a NORMAL completion path. ITEM_LOCK_CHANGED is documented not
-- to fire when the source or destination is an empty slot, so a run made
-- entirely of equips into bare slots would otherwise sit in WAITING forever.
local RUN_TIMEOUT = 5

-- A transient failure is worth re-offering the same action, but only a few
-- times — an item that reports LOCKED four passes running is not going to
-- unlock, and spinning on it is how a run becomes an infinite loop.
local MAX_RETRIES = 3

local ITEM, IGNORED, EMPTY = "ITEM", "IGNORED", "EMPTY"

local NO_ROWS = {}   -- shared immutable stand-in for a missing snapshot table

-- ---------------------------------------------------------------------------
-- Item identity (§2.1 / §2.1a)
-- ---------------------------------------------------------------------------
--
-- A real link written by THIS client looks like
--     |cff1eff00|Hitem:25059::::::-36:1830748181:60::::::::::|h[...]|h|r
-- Nineteen fields, empty ones emitted as EMPTY STRINGS rather than zeros, a
-- NEGATIVE suffixID, and ten always-blank retail fields on the end. The layout
-- that matters is the legacy one:
--     item:itemID:enchant:gem1:gem2:gem3:gem4:suffixID:uniqueID:linkLevel
--
-- KEEP itemID and suffixID. The suffix is the "of the Bear" roll; a set that
-- asks for the +stamina axe must never be satisfied by the +spirit one, and
-- they share an itemID.
-- KEEP enchant and the four gem ids. A player holding an enchanted and an
-- unenchanted copy means the enchanted one. These are the *decoration* half.
-- DROP uniqueID, and do not let a future reader "restore it so we can tell two
-- copies apart". It cannot do that. Its low sixteen bits are a deterministic
-- function of the itemID (the suffix factor) and its high sixteen bits are
-- random noise: zero identity either way. Two identical unenchanted rings
-- produce BYTE-IDENTICAL links on this client, and that is correct — they are
-- interchangeable. Telling copies apart is an ALLOCATION problem, solved by the
-- planner's reservation ledger, not an identity problem (see Resolve).
-- DROP linkLevel and everything after it: that field is the *viewer's* level.

local keyFields = {}

-- Splits on ":" while PRESERVING empty fields, which is the entire point. This
-- client writes "25059::::::-36:..." and the enchant and four gem slots must
-- land in positions 2..6, not be silently compacted away. A gmatch-based split
-- drops them and shifts suffixID into a gem position, which is a key that
-- matches nothing and a bug nobody can see by reading it.
local function SplitFields(body)
    for i = #keyFields, 1, -1 do keyFields[i] = nil end
    local n, pos = 0, 1
    while true do
        local at = strfind(body, ":", pos, true)
        n = n + 1
        if at then
            keyFields[n] = strsub(body, pos, at - 1)
            pos = at + 1
        else
            keyFields[n] = strsub(body, pos)
            break
        end
    end
    return n
end

local function Field(index)
    local v = keyFields[index]
    if v == nil or v == "" then return 0 end
    return tonumber(v) or 0
end

-- Returns key, itemID, baseKey. The third return is additive to the published
-- signature: §2.1a says to store both halves, and computing the base key twice
-- at every call site is how they drift apart.
function E.ItemKey(itemLink)
    local kind = type(itemLink)
    if kind == "number" then
        -- A bare itemID is a legitimate input: the bank cache and any
        -- host-side fallback that only has an id can still produce a key that
        -- loose-matches a real link. It can never produce an exact match to a
        -- decorated item, which is correct.
        if itemLink <= 0 then return nil end
        local base = format("%d:0", itemLink)
        return base .. ":0:0:0:0:0", itemLink, base
    elseif kind ~= "string" then
        return nil
    end
    -- The character class admits "-" because suffixIDs are negative on this
    -- client, and stops at the first character outside [0-9-:] — which is the
    -- "|" that begins the name, or the end of a bare "item:..." string with no
    -- |Hitem: wrapper at all. Both forms occur in the wild.
    local body = strmatch(itemLink, "item:([%d%-:]*)")
    if not body or body == "" then return nil end
    SplitFields(body)
    local itemID = Field(1)
    if itemID <= 0 then return nil end
    local baseKey = format("%d:%d", itemID, Field(7))
    return format("%s:%d:%d:%d:%d:%d", baseKey, Field(2), Field(3), Field(4), Field(5), Field(6)),
        itemID, baseKey
end

-- The base key is a prefix of the full key by construction, so this is a
-- pattern match rather than a re-parse — the two can never disagree.
function E.BaseKey(key)
    if type(key) ~= "string" then return nil end
    return strmatch(key, "^(%-?%d+:%-?%d+)")
end

-- exact and loose are MUTUALLY EXCLUSIVE. "Loose" is not "matches at all", it
-- is specifically "same item, different decoration" — the UI wants to say
-- "equipped an unenchanted copy" and it can only do that if a loose result
-- means the copy really was different.
function E.KeyMatches(savedKey, candidateKey)
    if type(savedKey) ~= "string" or type(candidateKey) ~= "string" then return false, false end
    if savedKey == candidateKey then return true, false end
    local a, b = E.BaseKey(savedKey), E.BaseKey(candidateKey)
    if a and b and a == b then return false, true end
    return false, false
end

-- ---------------------------------------------------------------------------
-- Legality: can this item reach this slot (§2.4 rules 4 and 5)
-- ---------------------------------------------------------------------------

local function RelicSubclassFor(snapshot)
    if snapshot.relicSubclass then return snapshot.relicSubclass end
    return D.RelicSubclass[snapshot.playerClass or ""]
end

-- Used by BOTH the flyout and the planner, on purpose. If the two disagreed
-- the flyout would offer a swap the planner then refuses, which reads to the
-- player as the addon being broken rather than the item being wrong.
local function SlotAccepts(snapshot, row, slotID)
    if not row or slotID == D.AMMO_SLOT then return false end
    local loc = row.equipLoc
    -- Ammo is outside the set model entirely (§2.5 rule 6). It is a depleting
    -- consumable; "restore exactly this" is the wrong verb for it. It is also
    -- the one slot whose lock events never arrive.
    if not loc or loc == "INVTYPE_AMMO" then return false end
    local slots = D.EquipLocSlots[loc]
    if not slots then return false end
    local listed = false
    for i = 1, #slots do
        if slots[i] == slotID then listed = true; break end
    end
    if not listed then return false end

    if slotID == 17 then
        -- Shields and holdables go off-hand for anybody. A one-hand WEAPON
        -- there is a dual-wield question, and TBC answers it per character,
        -- not per class — a warrior without the skill trained cannot.
        if D.OffHandNonWeaponEquipLocs[loc] then return true end
        if loc == "INVTYPE_WEAPON" then return snapshot.canDualWield == true end
        return true
    end

    if slotID == 18 then
        -- One slot id, three faces. When the relic face is showing, a bow is
        -- not merely unusable there, it is not offerable — and a paladin's
        -- list must not contain idols, which is why the subclass is checked
        -- and not just the equip location.
        if snapshot.hasRelicSlot then
            if not D.RelicEquipLocs[loc] then return false end
            local want = RelicSubclassFor(snapshot)
            if want and row.subClassID and row.subClassID ~= want then return false end
            return true
        end
        return D.RangedEquipLocs[loc] == true
    end

    return true
end

E.SlotAccepts = SlotAccepts

-- Proficiency answers "will this dim in the list", never "will this be hidden".
-- A warrior levelling in mail is making a legitimate choice and an addon that
-- hides the option is telling him he is wrong (§2.4 rule 7).
local function IsUsable(snapshot, row)
    if not row or row.classID ~= D.CLASS_ARMOR then return true end
    local sub = row.subClassID
    if not sub or sub < D.ArmorSubclass.CLOTH or sub > D.ArmorSubclass.PLATE then return true end
    local prof = D.ArmorProficiency[snapshot.playerClass or ""]
    if not prof then return true end
    return prof[sub] == true
end

E.IsUsable = IsUsable

-- Unique-Equipped. On TBC this is EXACTLY three cases, not the sprawling
-- hand-curated mess the ecosystem implies, because this client's own
-- ItemLimitCategory table is thirteen rows of which only three limit what may
-- be EQUIPPED (D.LimitCategories). So the model below is complete, needs no
-- cache, no API call and no maintenance:
--
--   1. The same unique-equipped item twice. 2.3.0 converted a pile of dropped
--      rings, trinkets and one-handers from Unique to Unique-Equipped, so "the
--      same ring in both fingers" is a set a player can save and never wear —
--      and it must be refused even when two copies really are sitting in bags.
--   2. Two members of one of the three ring families (Bronze Dragonflight,
--      Violet Signet, Band of Eternity). Named precisely, from D data.
--   3. Two target items socketed with the same unique-equipped GEM. Our
--      identity key already carries the four gem ids, so finding a repeated
--      non-zero gem id across two targets is free — but a repeat is only a
--      CONFLICT when that gem is genuinely unique-equipped, which is why the
--      rule is gated on snapshot.uniqueGems.
--
--      The gate is the whole point, and it was added after the unfiltered rule
--      was written and found to be wrong. Gemming three pieces with the same
--      Living Ruby or Great Dawnstone is not an edge case in TBC, it is how
--      people gem; flagging every repeat would refuse a large fraction of
--      perfectly legal sets. "Refuse before mutating" means never START what
--      you cannot FINISH — it does not license refusing things that would have
--      worked. A false pre-flight refusal blocks a working set with no
--      recourse, whereas an unforeseen server rejection costs one recoverable
--      action and the host surfaces the client's own ERR_ITEM_UNIQUE_EQUIPPABLE
--      for it. So the safe direction for an UNPROVEN conflict is to let it run.
--
--      Hence: unknown gem, or no uniqueGems table at all, means DO NOT FLAG.
--      snapshot.uniqueGems is populated lazily and best-effort by the host from
--      C_Item.GetItemUniquenessByID; the engine never requires it.
--
-- Cases 1 and 2 cannot both fire: the per-item unique-equipped bit and the
-- limit-category set are verified disjoint in this build.
--
-- row.uniqueFamily remains honoured as a host-supplied supplement, but it is no
-- longer the mechanism — D.LimitCategoryFor is.

-- Keys are always produced by E.ItemKey and therefore always have exactly seven
-- numeric fields, so a fixed pattern is both safe and the cheapest thing here.
local function GemFields(key)
    if type(key) ~= "string" then return nil end
    return strmatch(key, "^%-?%d+:%-?%d+:%-?%d+:(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+)$")
end

-- Returns the shared gem's id ONLY when that gem is known to be
-- unique-equipped. No table, or a gem that is not in it, returns nil — see the
-- argument above for why unknown must mean "let it run" rather than "refuse".
local function SharedGem(a, b, uniqueGems)
    if not uniqueGems then return nil end
    local a1, a2, a3, a4 = GemFields(a.key)
    if not a1 then return nil end
    local b1, b2, b3, b4 = GemFields(b.key)
    if not b1 then return nil end
    local left = { a1, a2, a3, a4 }
    local right = { b1, b2, b3, b4 }
    for i = 1, 4 do
        local gem = left[i]
        -- "0" means no gem in that socket. Two bare items are not a conflict,
        -- and this guard is the obvious way to write the rule wrong.
        if gem ~= "0" then
            local id = tonumber(gem)
            -- Numeric key first, since the host builds this from item ids; the
            -- string fallback costs nothing and survives a hand-written table.
            if (id and uniqueGems[id]) or uniqueGems[gem] then
                for j = 1, 4 do
                    if right[j] == gem then return gem end
                end
            end
        end
    end
    return nil
end

local function Conflicts(a, b, uniqueGems)
    if not a or not b or a == b then return false end
    -- Case 2 first: it produces the most specific message.
    local catA = a.itemID and D.LimitCategoryFor(a.itemID)
    if catA then
        local catB = b.itemID and D.LimitCategoryFor(b.itemID)
        if catA == catB then
            local info = D.LimitCategories[catA]
            return true, format("only one %s may be worn", (info and info.name) or "ring of that family")
        end
    end
    -- Case 1.
    if a.unique and b.unique and a.itemID and a.itemID == b.itemID then
        return true, "it is unique-equipped"
    end
    -- Host-supplied supplement, kept because it costs nothing and covers
    -- anything a future patch adds before we notice.
    if a.uniqueFamily and b.uniqueFamily and a.uniqueFamily == b.uniqueFamily then
        return true, "they share a limit category"
    end
    -- Case 3, and only for a gem the host has PROVEN unique-equipped.
    if SharedGem(a, b, uniqueGems) then
        return true, "they carry the same unique-equipped gem"
    end
    return false
end

E.Conflicts = Conflicts

-- ---------------------------------------------------------------------------
-- Sets (§2.3)
-- ---------------------------------------------------------------------------

function E.NewSet(name, icon)
    return { name = name or "", icon = icon, order = 0, entries = {} }
end

-- A brand-new set specifies NOTHING WORN AT ALL.
--
-- The old "new set" was E.NewSet on its own -- a bare table with no entries --
-- and since a slot with no entry reads as IGNORED, that set touched nothing.
-- The UI papered over it by capturing the player's gear the instant the set was
-- made, which meant "New" silently meant "save what I have on" and there was no
-- way to start from nothing at all.
--
-- So a new set is now NAKED: every canon slot EMPTY, meaning "this slot should
-- be bare", so equipping it strips you. That is a real, expressible intent
-- rather than the absence of one.
--
-- Shirt and tabard are the exception, and for D5's reason applied at creation
-- instead of at capture: they carry no stats, and nobody wants a gear set
-- yanking their guild tabard. They are IGNORED -- hands off -- which is a
-- different statement from EMPTY and is the whole point of having three states.
function E.NakedEntries(out)
    local entries = out or {}
    for i = 1, #D.Slots do
        local slot = D.Slots[i]
        entries[slot.key] = { state = (slot.cosmetic and IGNORED) or EMPTY }
    end
    -- D.Slots has no ammo row, so ammo cannot be nakedly stripped either (D4).
    return entries
end

function E.NakedSet(name, icon)
    local set = E.NewSet(name, icon)
    set.entries = E.NakedEntries()
    return set
end

-- One authored slot, built from a CANDIDATE ROW.
--
-- Candidate rows are POOLED scratch -- the same tables, refilled from the top on
-- the next E.Candidates call -- so anything that stores one is holding a promise
-- the engine never made. This returns a FRESH table every time, copying exactly
-- the fields E.CaptureSet writes, so an authored entry and a captured one are
-- indistinguishable to the planner. In particular `baseKey` is carried: an entry
-- without it silently loses loose matching, and the failure is invisible until
-- the player re-enchants the sword.
function E.AuthorEntry(row)
    if type(row) ~= "table" or type(row.key) ~= "string" then return nil end
    return {
        state   = ITEM,
        key     = row.key,
        baseKey = row.baseKey or E.BaseKey(row.key),
        itemID  = row.itemID,
        name    = row.name,
        icon    = row.icon,
        link    = row.link,
    }
end

-- "Leave this slot bare" -- EMPTY, never a missing entry, because a missing
-- entry means IGNORED and those are opposite instructions (D3).
function E.EmptyEntry()
    return { state = EMPTY }
end

-- Three explicit strings, and anything else is IGNORED.
--
-- This is not defensive paranoia, it is the fix for an entire bug class.
-- ItemRack's most-reported cursor-stuck bug reduces to 0, "0" and nil all being
-- used to mean "this slot should be empty", so a corrupt or half-migrated entry
-- silently became "strip it". Our unknown case resolves in the SAFE direction:
-- leave the slot alone. A set that does slightly less than you meant is a
-- nuisance; a set that takes your gear off because a saved variable got mangled
-- is a support ticket.
local function EntryState(entry)
    if type(entry) ~= "table" then return IGNORED end
    local state = entry.state
    if state == EMPTY then return EMPTY end
    if state == ITEM and type(entry.key) == "string" then return ITEM end
    if state == IGNORED then return IGNORED end
    return IGNORED
end

E.EntryState = EntryState

function E.CaptureSet(snapshot, opts)
    local entries = {}
    if not snapshot then return entries end
    local equipped = snapshot.equipped or NO_ROWS
    local ignore = opts and opts.ignore
    local includeCosmetic = opts and opts.includeCosmetic

    for i = 1, #D.Slots do
        local slot = D.Slots[i]
        local key = slot.key
        if (ignore and ignore[key]) or (slot.cosmetic and not includeCosmetic) then
            -- Cosmetics default OUT, not in. Retail's canonical complaint is a
            -- set that silently strips your guild tabard every time you swap
            -- because you happened not to be wearing one when you saved.
            entries[key] = { state = IGNORED }
        else
            local worn = equipped[slot.id]
            if worn then
                entries[key] = {
                    state   = ITEM,
                    key     = worn.key,
                    baseKey = worn.baseKey or E.BaseKey(worn.key),
                    itemID  = worn.itemID,
                    name    = worn.name,
                    icon    = worn.icon,
                    link    = worn.link,
                }
            else
                entries[key] = { state = EMPTY }
            end
        end
    end
    -- D.Slots has no ammo row, so ammo cannot be captured even by accident.
    return entries
end

-- ---------------------------------------------------------------------------
-- Resolution: what each slot wants and which PHYSICAL OBJECT satisfies it
-- ---------------------------------------------------------------------------
--
-- Shared core of DiffSet, PlanSet and SetStats.
--
-- The reservation ledger is the important part. Two identical unenchanted rings
-- have byte-identical links and therefore identical keys — deliberately, since
-- they are interchangeable. So a set naming that ring in BOTH fingers cannot be
-- resolved by identity; it has to be resolved by allocation. Every square this
-- pass has spoken for goes into `reserved`, keyed by physical location
-- (where + bag + slot) as well as by object, and the next slot asking for the
-- same key skips it and takes the next copy. ItemRack calls its equivalent
-- LockList; it is entirely separate from the game's item locks. Cleared at the
-- start of every pass.
--
-- Without it, a set with two identical rings plans both fingers onto one
-- physical ring, the first action succeeds, the second fails, and the player is
-- left half-changed — the exact outcome this module exists to prevent.
--
-- The other subtlety is PASS ORDER. Items already worn in the right place are
-- claimed FIRST, across all slots, before anything goes looking. Otherwise
-- finger1 steals the ring finger2 is already correctly wearing and the plan
-- shuffles two rings to no purpose.

local reserved = {}

local function LocationKey(row)
    if not row or not row.bag or not row.slot then return nil end
    return (row.where or "BAGS") .. "\001" .. tostring(row.bag) .. "\001" .. tostring(row.slot)
end

local function IsReserved(row)
    if reserved[row] then return true end
    local loc = LocationKey(row)
    return loc ~= nil and reserved[loc] == true
end

local function ReserveRow(row)
    reserved[row] = true
    local loc = LocationKey(row)
    if loc then reserved[loc] = true end
end

local function ClearReservations()
    for key in pairs(reserved) do reserved[key] = nil end
end

local function ResetRow(rows, index)
    local r = rows[index]
    if not r then r = {}; rows[index] = r end
    r.slotID, r.slotKey, r.from, r.to = nil, nil, nil, nil
    r.action, r.found, r.status, r.matched = nil, nil, nil, nil
    r.foundWhere, r.foundSlot, r.state, r.blockedUsable = nil, nil, nil, nil
    return r
end

-- Try the item already in this slot. exactOnly on the first sweep so that a
-- perfectly-correct slot is never disturbed by a merely-similar one elsewhere.
local function TryWorn(snapshot, r, exactOnly)
    local worn = (snapshot.equipped or NO_ROWS)[r.slotID]
    if not worn or IsReserved(worn) then return false end
    local exact, loose = E.KeyMatches(r.to.key, worn.key)
    if exact or (loose and not exactOnly) then
        ReserveRow(worn)
        r.action  = "NONE"
        r.matched = exact and "EXACT" or "LOOSE"
        r.status  = exact and "OK" or "LOOSE"
        r.found, r.foundWhere, r.foundSlot = worn, "WORN", r.slotID
        return true
    end
    return false
end

local function SearchBags(snapshot, r, wantExact, where)
    local inv = snapshot.inventory or NO_ROWS
    for i = 1, #inv do
        local row = inv[i]
        if row.where == where and not IsReserved(row) then
            local exact, loose = E.KeyMatches(r.to.key, row.key)
            if (wantExact and exact) or ((not wantExact) and loose) then
                if SlotAccepts(snapshot, row, r.slotID) then return row end
                -- Found the item, but it cannot legally go there — a relic in
                -- a hunter's ranged slot, a second sword without dual wield.
                -- Remember it so the verdict says NOT_USABLE rather than the
                -- flatly wrong MISSING.
                r.blockedUsable = true
            end
        end
    end
    return nil
end

-- Iterated in canon order, never with pairs — a plan whose action list changes
-- order between two identical snapshots is untestable and looks like a race.
local function SearchEquipped(snapshot, r, wantExact)
    local equipped = snapshot.equipped or NO_ROWS
    for i = 1, #D.SlotOrder do
        local slotID = D.SlotOrder[i]
        local row = equipped[slotID]
        if row and slotID ~= r.slotID and not IsReserved(row) then
            local exact, loose = E.KeyMatches(r.to.key, row.key)
            if (wantExact and exact) or ((not wantExact) and loose) then
                if SlotAccepts(snapshot, row, r.slotID) then return row, slotID end
                r.blockedUsable = true
            end
        end
    end
    return nil
end

local function Land(r, row, where, slotID, matched)
    ReserveRow(row)
    r.found, r.foundWhere, r.foundSlot = row, where, slotID
    r.matched = matched
    r.action  = "EQUIP"
    if where == "BANK" then
        r.status = "IN_BANK"
    elseif row.locked then
        r.status = "LOCKED"
    else
        r.status = (matched == "EXACT") and "OK" or "LOOSE"
    end
end

-- `ignore` is the live editing scratchpad — the slots the player has toggled
-- off in the flyout but not yet saved into the set. It overlays the stored
-- entries so the pre-flight preview describes what the player is looking at
-- rather than what is on disk. Omitting it degrades to the set's own IGNORED
-- entries, which is correct but a pass behind the UI.
local function Resolve(set, snapshot, rows, ignore)
    ClearReservations()
    -- No snapshot means we can see nothing of the world, and the only honest
    -- answer about a world you cannot see is "nothing to do". Returning an
    -- empty result rather than indexing a nil is not politeness: the UI wraps
    -- these calls in pcall, so an error here degrades to a blank pane with no
    -- explanation — a soft-fail into silence, which is the failure mode this
    -- module is built to not have.
    if not snapshot then
        for i = #rows, 1, -1 do rows[i] = nil end
        return 0
    end
    local equipped = snapshot.equipped or NO_ROWS
    local entries = set and set.entries or nil
    local n = 0

    for i = 1, #D.Slots do
        local slot = D.Slots[i]
        local state = EntryState(entries and entries[slot.key])
        if ignore and ignore[slot.key] then state = IGNORED end
        if state ~= IGNORED then
            n = n + 1
            local r = ResetRow(rows, n)
            r.slotID, r.slotKey, r.state = slot.id, slot.key, state
            r.to   = entries[slot.key]
            r.from = equipped[slot.id]
            if state == EMPTY then
                -- EMPTY is an instruction, not an absence: take that off.
                if r.from then
                    r.action = "REMOVE"
                    r.status = r.from.locked and "LOCKED" or "OK"
                else
                    r.action, r.status = "NONE", "OK"
                end
            end
        end
    end
    -- Clear the tail unconditionally. A leftover row from a longer previous set
    -- is invisible to #rows-based loops but not to ipairs, and a stale entry
    -- taking part in a later sort is a bug this suite has already paid for.
    for i = n + 1, #rows do rows[i] = nil end

    -- Sweep 1: exact, already worn where it belongs. Reserve it and leave it.
    for i = 1, n do
        local r = rows[i]
        if r.state == ITEM and not r.action then TryWorn(snapshot, r, true) end
    end
    -- Sweep 2: worn, right item, different decoration. Also leave it — swapping
    -- an unenchanted copy for another unenchanted copy is churn, not a fix.
    for i = 1, n do
        local r = rows[i]
        if r.state == ITEM and not r.action then TryWorn(snapshot, r, false) end
    end
    -- Sweep 3: the exact item, somewhere reachable. Bags before other equipped
    -- slots: pulling from a bag is one action and costs no bag space, whereas
    -- taking an item off another slot may strand whatever was there.
    for i = 1, n do
        local r = rows[i]
        if r.state == ITEM and not r.action then
            local row = SearchBags(snapshot, r, true, "BAGS")
            if row then
                Land(r, row, "BAGS", nil, "EXACT")
            else
                local worn, slotID = SearchEquipped(snapshot, r, true)
                if worn then Land(r, worn, "EQUIPPED", slotID, "EXACT") end
            end
        end
    end
    -- Sweep 4: a differently-decorated copy, reachable. Deliberately ahead of
    -- the bank sweep: a plan that can run beats a plan that sends you across
    -- the city, and the LOOSE status tells the player exactly what happened.
    for i = 1, n do
        local r = rows[i]
        if r.state == ITEM and not r.action then
            local row = SearchBags(snapshot, r, false, "BAGS")
            if row then
                Land(r, row, "BAGS", nil, "LOOSE")
            else
                local worn, slotID = SearchEquipped(snapshot, r, false)
                if worn then Land(r, worn, "EQUIPPED", slotID, "LOOSE") end
            end
        end
    end
    -- Sweep 5: the bank. Reached from the cache even when the player is nowhere
    -- near it, because "it's in your bank" is the answer the whole module
    -- exists to be able to give. Whether we can ACT on it is a later question.
    for i = 1, n do
        local r = rows[i]
        if r.state == ITEM and not r.action then
            local row = SearchBags(snapshot, r, true, "BANK")
            if row then
                Land(r, row, "BANK", nil, "EXACT")
            else
                row = SearchBags(snapshot, r, false, "BANK")
                if row then Land(r, row, "BANK", nil, "LOOSE") end
            end
        end
    end
    -- Whatever is left really is not anywhere we can see. Note that the second
    -- of two slots asking for the same key lands here when only one copy
    -- exists — an honest MISSING before anything moves, rather than two actions
    -- pointed at one ring.
    for i = 1, n do
        local r = rows[i]
        if r.state == ITEM and not r.action then
            r.action = "EQUIP"
            r.status = r.blockedUsable and "NOT_USABLE" or "MISSING"
        end
    end
    return n
end

-- ---------------------------------------------------------------------------
-- DiffSet / SetIsDirty (§2.3)
-- ---------------------------------------------------------------------------

local diffScratch = { changes = {} }
local dirtyScratch = {}

-- `out` is additive to the published signature and exists for exactly one
-- reason: the shared scratch is reused per call, so a caller that wants two
-- diffs alive at once (the editor comparing sets) must own the second one.
function E.DiffSet(set, snapshot, out, ignore)
    local diff = out or diffScratch
    diff.changes = diff.changes or {}
    local rows = diff.changes
    local n = Resolve(set, snapshot, rows, ignore)

    local touched, missing, inBank = 0, 0, 0
    for i = 1, n do
        local r = rows[i]
        if r.action ~= "NONE" then touched = touched + 1 end
        if r.status == "MISSING" then missing = missing + 1 end
        if r.status == "IN_BANK" then inBank = inBank + 1 end
    end

    diff.n = n
    diff.touched = touched
    -- Every canon slot the set does not speak for. Reported so the UI can say
    -- "touches 2 slots, leaves 17 alone" — the sentence that sells hit-cap
    -- swapping, which is the single best argument for slot ignoring.
    diff.ignored = #D.Slots - n
    diff.missing = missing
    diff.inBank = inBank
    -- True when every NON-IGNORED entry already matches what is worn. An
    -- ignored slot holding something completely different does not make the
    -- set "not equipped" — that is the entire meaning of ignoring it.
    diff.isEquipped = (touched == 0)
    return diff
end

function E.SetIsDirty(set, snapshot)
    local diff = E.DiffSet(set, snapshot)
    for i = #dirtyScratch, 1, -1 do dirtyScratch[i] = nil end
    local n = 0
    for i = 1, diff.n do
        local r = diff.changes[i]
        if r.action ~= "NONE" then
            n = n + 1
            dirtyScratch[n] = r.slotKey
        end
    end
    return n > 0, dirtyScratch
end

-- ---------------------------------------------------------------------------
-- Candidates — the flyout (§2.4)
-- ---------------------------------------------------------------------------

local candRows, candPool = {}, {}

local COPY_FIELDS = {
    "key", "baseKey", "itemID", "link", "name", "icon", "quality", "ilvl",
    "equipLoc", "classID", "subClassID", "locked", "broken", "unique",
    "uniqueFamily", "bindOnEquip", "bag", "slot", "stale", "stats",
}

local function EmitCandidate(index, source, where, fromSlot, snapshot)
    local row = candPool[index]
    if not row then row = {}; candPool[index] = row end
    for i = 1, #COPY_FIELDS do
        local field = COPY_FIELDS[i]
        row[field] = source[field]
    end
    row.where = where
    row.fromSlot = fromSlot
    row.usable = IsUsable(snapshot, source)
    row.hidden = nil
    row.score = nil
    -- The pooled row is a copy so the flyout can annotate it without writing
    -- into the host's snapshot; `source` is the way back to the real object,
    -- which PlanSingle needs for reservation and unique-conflict identity.
    row.source = source
    return row
end

local function Num(v) return v or 0 end
local function Str(v) return v or "" end

local function CmpILVL(a, b)
    if Num(a.ilvl) ~= Num(b.ilvl) then return Num(a.ilvl) > Num(b.ilvl) end
    if Num(a.quality) ~= Num(b.quality) then return Num(a.quality) > Num(b.quality) end
    if Str(a.name) ~= Str(b.name) then return Str(a.name) < Str(b.name) end
    return Str(a.key) < Str(b.key)
end

local function CmpQuality(a, b)
    if Num(a.quality) ~= Num(b.quality) then return Num(a.quality) > Num(b.quality) end
    return CmpILVL(a, b)
end

local function CmpName(a, b)
    if Str(a.name) ~= Str(b.name) then return Str(a.name) < Str(b.name) end
    return CmpILVL(a, b)
end

local function CmpScore(a, b)
    if Num(a.score) ~= Num(b.score) then return Num(a.score) > Num(b.score) end
    return CmpILVL(a, b)
end

local COMPARATORS = { ILVL = CmpILVL, QUALITY = CmpQuality, NAME = CmpName, SCORE = CmpScore }

function E.Candidates(snapshot, slotID, opts)
    -- Cleared BEFORE anything is added and therefore before the sort. A
    -- leftover tail entry from a longer previous flyout taking part in a sort
    -- is the exact bug the suite has already paid for once.
    for i = #candRows, 1, -1 do candRows[i] = nil end
    if not snapshot or not slotID or slotID == D.AMMO_SLOT then return candRows end

    opts = opts or NO_ROWS
    local equipped = snapshot.equipped or NO_ROWS
    local inv = snapshot.inventory or NO_ROWS
    local current = equipped[slotID]
    local search = opts.search
    if search and search ~= "" then search = lower(search) else search = nil end
    local minQuality = opts.minQuality
    local hidden = opts.hidden
    local showHidden = opts.showHidden
    local n = 0

    -- Rule 1: everything in bags and bank whose equip location reaches here.
    for i = 1, #inv do
        local row = inv[i]
        if SlotAccepts(snapshot, row, slotID) then
            local isHidden = hidden and row.key and hidden[row.key]
            local passQuality = (not minQuality) or Num(row.quality) >= minQuality
            local passSearch = (not search) or (row.name and strfind(lower(row.name), search, 1, true))
            if (showHidden or not isHidden) and passQuality and passSearch then
                n = n + 1
                local out = EmitCandidate(n, row, row.where or "BAGS", nil, snapshot)
                out.hidden = isHidden and true or nil
                candRows[n] = out
            end
        end
    end

    -- Rule 2: other equipped items that could legally move here, so ring1 <->
    -- ring2 and main hand <-> off hand are one click rather than two bag
    -- round-trips. Rule 3 is the `id ~= slotID` guard: the item already in this
    -- slot is not a candidate for this slot.
    -- Deliberately exempt from the quality and hidden filters — an item you are
    -- currently wearing must always be reachable, or a minimum-quality filter
    -- can trap you out of undoing your own swap.
    for i = 1, #D.SlotOrder do
        local id = D.SlotOrder[i]
        local row = equipped[id]
        if row and id ~= slotID and row ~= current and SlotAccepts(snapshot, row, slotID) then
            local passSearch = (not search) or (row.name and strfind(lower(row.name), search, 1, true))
            if passSearch then
                n = n + 1
                candRows[n] = EmitCandidate(n, row, "EQUIPPED", id, snapshot)
            end
        end
    end

    if opts.score then
        for i = 1, n do candRows[i].score = opts.score(candRows[i]) end
    end

    -- Rule 6: item level descending by default, then quality, then name. NEVER
    -- by location. Blizzard sorts its flyout by physical memory location —
    -- "inventory, backpack, bags, bank, bank bags" — which is meaningless to a
    -- player and is the single worst property of the built-in list.
    sort(candRows, COMPARATORS[opts.sort or "ILVL"] or CmpILVL)
    return candRows
end

-- ---------------------------------------------------------------------------
-- The planner (§2.5)
-- ---------------------------------------------------------------------------

local resolvedScratch = {}
local singleScratch = {}
local rowBySlot = {}
local finalRow = {}
local preStrip = {}
local swapPartner = {}
local consumed = {}

local function NewPlan()
    return {
        ok = false, verdict = "OK", reasons = {}, actions = {},
        needFree = 0, deferred = {}, uniqueUncertain = false,
    }
end

-- Returns the row so a caller can mark it `warning = true`. Every reason is a
-- blocker unless it says otherwise, which keeps the common case unannotated.
local function Reason(plan, code, text, slotKey, itemName)
    local row = { code = code, text = text, slotKey = slotKey, itemName = itemName }
    plan.reasons[#plan.reasons + 1] = row
    return row
end

local function Defer(plan, slotKey)
    if not slotKey then return end
    for i = 1, #plan.deferred do
        if plan.deferred[i] == slotKey then return end
    end
    plan.deferred[#plan.deferred + 1] = slotKey
end

local function Act(plan, action)
    plan.actions[#plan.actions + 1] = action
    return action
end

-- The engine is given a COUNT of free bag slots, not their coordinates — that
-- keeps the snapshot small and cheap to rebuild on every BAG_UPDATE. A host
-- that wants destinations filled in may pass snapshot.freeSlots; otherwise
-- bag/slot come back nil and the host picks at execution time, which is a
-- one-line lookup it has to do anyway to survive a bag change mid-run.
-- Reservation applies here too: freeIndex only ever moves forward within a
-- pass, so two removals never target the same empty square.
local freeIndex = 0
local function TakeFree(snapshot)
    local list = snapshot.freeSlots
    if not list then return nil, nil end
    freeIndex = freeIndex + 1
    local free = list[freeIndex]
    if not free then return nil, nil end
    return free.bag, free.slot
end

local function ItemName(row)
    return (row and row.name) or (row and row.link) or "that item"
end

local function BuildPlan(rows, n, snapshot, opts)
    local plan = NewPlan()
    snapshot = snapshot or NO_ROWS
    local equipped = snapshot.equipped or NO_ROWS
    local blocked = false
    freeIndex = 0

    for id in pairs(rowBySlot) do rowBySlot[id] = nil end
    for id in pairs(finalRow) do finalRow[id] = nil end
    for id in pairs(preStrip) do preStrip[id] = nil end
    for id in pairs(swapPartner) do swapPartner[id] = nil end
    for id in pairs(consumed) do consumed[id] = nil end
    for i = 1, n do rowBySlot[rows[i].slotID] = rows[i] end

    -- -----------------------------------------------------------------------
    -- Gate 0: the world says no
    -- -----------------------------------------------------------------------
    -- Every one of these is temporary, so every touched slot is deferred rather
    -- than failed — the host's combat queue turns TBC's most common outcome
    -- ("nothing happened") into a scheduled action.
    local function StateGate(flag, code, text)
        if not flag then return end
        blocked = true
        Reason(plan, code, text)
        for i = 1, n do
            if rows[i].action ~= "NONE" then Defer(plan, rows[i].slotKey) end
        end
    end
    StateGate(snapshot.dead, "DEAD", "You are dead.")
    -- PickupInventoryItem and PickupContainerItem are blocked by the client
    -- under InCombatLockdown for EVERY slot, weapons included. The server rule
    -- is looser than the API; the API is what we have.
    StateGate(snapshot.inCombat, "IN_COMBAT", "You are in combat.")
    StateGate(snapshot.casting, "CASTING", "You are casting.")
    -- A gear swap with a vendor window open can sell what it displaces.
    StateGate(snapshot.merchant, "MERCHANT_OPEN", "Close the merchant window first.")
    StateGate(snapshot.cursorBusy, "CURSOR_BUSY", "Something is on your cursor.")

    -- -----------------------------------------------------------------------
    -- Gate 1: per-slot verdicts
    -- -----------------------------------------------------------------------
    local atBank = snapshot.atBank == true
    for i = 1, n do
        local r = rows[i]
        if r.action ~= "NONE" then
            local status = r.status
            if status == "MISSING" then
                blocked = true
                -- Not deferred. Deferring implies "later" and there is no
                -- later for an item that does not exist.
                Reason(plan, "MISSING",
                    format("%s is not in your bags, your bank, or on you.", ItemName(r.to)),
                    r.slotKey, r.to and r.to.name)
            elseif status == "NOT_USABLE" then
                blocked = true
                Reason(plan, "NOT_USABLE",
                    format("%s cannot go in your %s.", ItemName(r.to), D.SlotLabel(r.slotID)),
                    r.slotKey, r.to and r.to.name)
            elseif status == "IN_BANK" and not atBank then
                blocked = true
                -- The headline. Every competitor, Blizzard included, reports
                -- this as "missing" — a dead end instead of an instruction.
                Reason(plan, "IN_BANK",
                    format("%s is in your bank.", ItemName(r.found)),
                    r.slotKey, r.found and r.found.name)
                Defer(plan, r.slotKey)
            elseif status == "LOCKED" then
                blocked = true
                Reason(plan, "LOCKED",
                    format("%s is in use right now.", ItemName(r.found or r.from)),
                    r.slotKey, ItemName(r.found or r.from))
                Defer(plan, r.slotKey)
            end
            -- Vestigial escape hatch. The conflict model is complete for this
            -- build, so nothing sets this today; it exists so that a host which
            -- ever genuinely cannot classify an item can say "this may be
            -- refused by the server" rather than promise the plan will work.
            if r.found and r.found.uniqueFamilyKnown == false then
                plan.uniqueUncertain = true
            end
        end
    end

    -- -----------------------------------------------------------------------
    -- Gate 2: two-handers forbid an off-hand
    -- -----------------------------------------------------------------------
    local mainRow = rowBySlot[16]
    local twoHand = mainRow and mainRow.action == "EQUIP" and mainRow.found
        and mainRow.status ~= "IN_BANK" and D.IsTwoHand(mainRow.found.equipLoc)
    local offRow = rowBySlot[17]
    if twoHand and offRow and offRow.state == ITEM then
        blocked = true
        Reason(plan, "NOT_USABLE",
            format("%s is two-handed; it leaves no off-hand slot.", ItemName(mainRow.found)),
            offRow.slotKey, ItemName(mainRow.found))
    elseif twoHand and equipped[17] and not offRow then
        -- The one place the module knowingly breaks its own central invariant.
        -- A set that ignores the off-hand produces no row for slot 17 at all,
        -- yet a landing two-hander displaces whatever is there regardless —
        -- that is the client's behaviour and there is no planning around it
        -- (DECISIONS D3).
        --
        -- "Unavoidable" is not "unannounced". We promise that an ignored slot
        -- is not touched, so the one time we are about to touch one we say so
        -- BEFORE anything moves. A silent strip is exactly the Blizzard bug the
        -- whole module exists to avoid being.
        --
        -- This WARNS, it does not refuse: the swap is legal and the player
        -- asked for it. Hence ok stays true and the reason carries warning =
        -- true, so a host counting reasons cannot mistake it for a blocker.
        -- IGNORE_OVERRIDDEN is an addition to the ARCHITECTURE §2.5 code list,
        -- deliberately its own code rather than a reused NOT_USABLE — nothing
        -- here is unusable, and the UI wants to phrase this differently.
        local reason = Reason(plan, "IGNORE_OVERRIDDEN",
            format("%s will go to your bags: %s is two-handed and leaves no off-hand, " ..
                "even though this set ignores that slot.",
                ItemName(equipped[17]), ItemName(mainRow.found)),
            "offhand", ItemName(equipped[17]))
        reason.warning = true
    end

    -- -----------------------------------------------------------------------
    -- Gate 3: unique-equipped, in the FINAL state
    -- -----------------------------------------------------------------------
    -- What will actually be worn when the plan finishes, per slot. Ignored
    -- slots contribute whatever is worn now, because that is precisely what
    -- ignoring them means — and a conflict against an ignored slot is
    -- unresolvable, since the one repair (take it off) is forbidden.
    for i = 1, #D.SlotOrder do
        local id = D.SlotOrder[i]
        local r = rowBySlot[id]
        if r and r.action == "EQUIP" then
            finalRow[id] = r.found
        elseif r and r.action == "REMOVE" then
            finalRow[id] = nil
        else
            finalRow[id] = equipped[id]
        end
    end
    local uniqueGems = snapshot.uniqueGems
    for i = 1, #D.SlotOrder do
        for j = i + 1, #D.SlotOrder do
            local a, b = finalRow[D.SlotOrder[i]], finalRow[D.SlotOrder[j]]
            local clash, why = Conflicts(a, b, uniqueGems)
            if clash then
                blocked = true
                Reason(plan, "UNIQUE_CONFLICT",
                    format("%s and %s cannot be worn together: %s.", ItemName(a), ItemName(b), why),
                    nil, ItemName(a))
            end
        end
    end

    -- -----------------------------------------------------------------------
    -- Shape of the work: swaps, pre-strips
    -- -----------------------------------------------------------------------
    -- Mutual exchanges are recognised before anything is emitted, because a
    -- pair must not also appear as two independent equips (rule 3).
    for i = 1, n do
        local r = rows[i]
        if r.action == "EQUIP" and r.foundWhere == "EQUIPPED" then
            local other = rowBySlot[r.foundSlot]
            if other and other.action == "EQUIP" and other.foundWhere == "EQUIPPED"
                and other.foundSlot == r.slotID then
                swapPartner[r.slotID] = other.slotID
            end
        end
    end

    -- Rule 2: clear a unique conflict BEFORE creating it. If the item worn in
    -- some other slot shares a limit category with something we are about to
    -- equip, the server refuses the equip outright — so the worn one comes off
    -- first, even though that slot is about to be re-equipped anyway. The
    -- two-hander is exempt: it is always action #1 (see below), so a worn item
    -- conflicting with the incoming 2H cannot be sequenced around and falls to
    -- the final-state refusal instead.
    local preStripCount = 0
    for i = 1, n do
        local r = rows[i]
        if r.action == "EQUIP" and r.found and r.status ~= "IN_BANK" and not (twoHand and r.slotID == 16) then
            for j = 1, #D.SlotOrder do
                local id = D.SlotOrder[j]
                local worn = equipped[id]
                local other = rowBySlot[id]
                if worn and id ~= r.slotID and not preStrip[id]
                    and other and other.action == "EQUIP"
                    and not swapPartner[id] and r.foundSlot ~= id
                    and Conflicts(r.found, worn, uniqueGems) then
                    preStrip[id] = true
                    preStripCount = preStripCount + 1
                end
            end
        end
    end

    -- -----------------------------------------------------------------------
    -- Rule 7: free bag slots, by formula rather than by simulation
    -- -----------------------------------------------------------------------
    --   needFree = (slots whose target is EMPTY and that currently hold
    --               something)
    --            + (1 if a two-hander is going to slot 16, slot 17 is
    --               occupied, and slot 17 is not itself being emptied)
    --            + (1 per bank withdrawal)
    --            + (1 per unique pre-strip)
    --
    -- Derivation, because the naive count is both wrong and wrong in the
    -- direction that refuses swaps which would have worked. A bag->equip is net
    -- ZERO: the displaced item takes the bag square the incoming item just
    -- vacated. Replacing a two-hander with a main hand and an off-hand is net
    -- MINUS ONE. A cross-slot exchange is net ZERO. So "five slots are being
    -- replaced, therefore five free bag slots" over-refuses by five. Only
    -- emptying a slot with nothing coming back, parking the off-hand a
    -- two-hander displaces, pulling something out of the bank, and lifting a
    -- conflicting item out of the way actually consume a square.
    local emptyCost = 0
    for i = 1, n do
        if rows[i].action == "REMOVE" then emptyCost = emptyCost + 1 end
    end
    local twoHandCost = 0
    if twoHand and equipped[17] and not (offRow and offRow.action == "REMOVE") then
        twoHandCost = 1
    end
    local withdrawCost = 0
    if atBank then
        for i = 1, n do
            local r = rows[i]
            if r.action == "EQUIP" and r.status == "IN_BANK" and r.found then
                withdrawCost = withdrawCost + 1
            end
        end
    end
    plan.needFree = emptyCost + twoHandCost + withdrawCost + preStripCount

    local freeBags = snapshot.freeBagSlots or 0
    if plan.needFree > freeBags then
        blocked = true
        -- freeBagSlots counts bagType == 0 containers only. A hunter with two
        -- quivers has far less spill space than his bag count suggests, and
        -- Blizzard will not put a chestpiece in a quiver.
        Reason(plan, "BAGS_FULL",
            format("Needs %d free bag slot%s; you have %d.",
                plan.needFree, plan.needFree == 1 and "" or "s", freeBags))
        for i = 1, n do
            if rows[i].action ~= "NONE" then Defer(plan, rows[i].slotKey) end
        end
    end

    -- -----------------------------------------------------------------------
    -- Emission, in the order the client demands
    -- -----------------------------------------------------------------------

    -- Every action carries the item's KEY as well as its coordinates, and that
    -- is load-bearing rather than decorative. A (bag, slot) captured at plan
    -- time goes stale the moment anything re-sorts the bags mid-run, and the
    -- client's response to a stale coordinate is "Item does not go in that
    -- slot" — a reproducible failure in the incumbent addon. With the key on the
    -- action the host can verify the square still holds the right item and
    -- re-find it if not. `broken` rides along for the durability warning.
    local function EmitEquip(r)
        if consumed[r.slotID] then return end
        consumed[r.slotID] = true
        local found = r.found
        if r.foundWhere == "EQUIPPED" then
            local partner = swapPartner[r.slotID]
            if partner then consumed[partner] = true end
            Act(plan, {
                op = "SWAP_EQUIPPED", fromSlot = r.foundSlot, toSlot = r.slotID,
                invSlot = r.slotID, key = found.key, itemID = found.itemID,
                name = ItemName(found), broken = found.broken, slotKey = r.slotKey,
            })
        else
            Act(plan, {
                op = "EQUIP_FROM_BAG", bag = found.bag, slot = found.slot,
                invSlot = r.slotID, key = found.key, itemID = found.itemID,
                name = ItemName(found), broken = found.broken, slotKey = r.slotKey,
            })
        end
    end

    -- Rule 4, REVISED. The two-hander goes on FIRST — before every other action
    -- in the plan — and we do NOT emit a MOVE_TO_BAG for slot 17. Explicitly
    -- unequipping the off-hand first is the thing that broke: ItemRack's fix
    -- for its own two-hander bugs was to move 2H swapping to the top of the
    -- order and let the client bag the displaced off-hand itself. So we plan
    -- one action, and merely RESERVE the bag slot the client is about to use.
    if twoHand then EmitEquip(mainRow) end

    -- Rule 2, emission: lift conflicting worn items out of the way.
    for i = 1, #D.SlotOrder do
        local id = D.SlotOrder[i]
        if preStrip[id] then
            local bag, slot = TakeFree(snapshot)
            local other = rowBySlot[id]
            local worn = equipped[id]
            Act(plan, {
                op = "MOVE_TO_BAG", invSlot = id, bag = bag, slot = slot,
                key = worn and worn.key, itemID = worn and worn.itemID,
                name = ItemName(worn), broken = worn and worn.broken,
                slotKey = other and other.slotKey,
            })
        end
    end

    -- Every EMPTY entry is stripped before anything is equipped. EMPTY is the
    -- one state that produces a removal with nothing to put back, and it is the
    -- state IGNORED must never be confused with. Slot 17 is skipped when a
    -- two-hander has already displaced it — the client did that move for us and
    -- re-issuing it would pick up whatever the player just put there.
    for i = 1, #D.SlotOrder do
        local id = D.SlotOrder[i]
        local r = rowBySlot[id]
        if r and r.action == "REMOVE" and not preStrip[id]
            and not (twoHand and id == 17) then
            local bag, slot = TakeFree(snapshot)
            Act(plan, {
                op = "MOVE_TO_BAG", invSlot = id, bag = bag, slot = slot,
                key = r.from and r.from.key, itemID = r.from and r.from.itemID,
                name = ItemName(r.from), broken = r.from and r.from.broken,
                slotKey = r.slotKey,
            })
        end
    end

    -- Rule 3: cross-slot exchanges, collapsed. Emitted ahead of the bag equips
    -- because they need no bag space and because leaving a mutual pair to the
    -- generic loop is how one of the two rings ends up on the floor.
    for i = 1, #D.SlotOrder do
        local id = D.SlotOrder[i]
        local r = rowBySlot[id]
        if r and r.action == "EQUIP" and r.foundWhere == "EQUIPPED" and r.status ~= "IN_BANK" then
            EmitEquip(r)
        end
    end

    -- Everything else, in canon slot order.
    for i = 1, #D.SlotOrder do
        local id = D.SlotOrder[i]
        local r = rowBySlot[id]
        if r and r.action == "EQUIP" and r.found and r.status ~= "IN_BANK" then
            EmitEquip(r)
        end
    end

    -- Rule 5: bank withdrawals, and only when standing at the bank. You cannot
    -- equip out of a bank container, so this is stage one of two — the item
    -- lands in a bag and the NEXT pass, planned from a fresh snapshot, equips
    -- it. invSlot rides along even though the withdrawal does not equip
    -- anything: every action carries its eventual destination, because the
    -- documented wrong-slot hazard on this client is letting the client choose
    -- between Finger1/Finger2, Trinket1/Trinket2 and MainHand/OffHand.
    if atBank then
        for i = 1, #D.SlotOrder do
            local id = D.SlotOrder[i]
            local r = rowBySlot[id]
            if r and r.action == "EQUIP" and r.status == "IN_BANK" and r.found then
                local toBag, toSlot = TakeFree(snapshot)
                Act(plan, {
                    op = "WITHDRAW", bag = r.found.bag, slot = r.found.slot,
                    toBag = toBag, toSlot = toSlot, invSlot = id,
                    key = r.found.key, itemID = r.found.itemID,
                    name = ItemName(r.found), broken = r.found.broken,
                    slotKey = r.slotKey,
                })
            end
        end
    end

    -- -----------------------------------------------------------------------
    -- Rule 1: refuse before mutating
    -- -----------------------------------------------------------------------
    -- Not "stop early", not "do what we can" — ZERO actions. A half-applied set
    -- is worse than no swap at all, because the player now has to work out
    -- which half happened. needFree survives the wipe on purpose: "you need two
    -- free bag slots" is the most actionable sentence the module can print.
    if blocked then
        for i = #plan.actions, 1, -1 do plan.actions[i] = nil end
        plan.ok = false
        plan.verdict = "BLOCKED"
        return plan
    end

    if #plan.actions == 0 then
        -- verdict OK, ok false. `ok` answers "should the host start a run";
        -- `verdict` answers "is anything wrong". They are different questions
        -- and the UI needs both — you are already wearing it is not a failure.
        plan.ok = false
        plan.verdict = "OK"
        Reason(plan, "NOTHING_TO_DO", "You are already wearing this set.")
        return plan
    end

    plan.ok = true
    plan.verdict = "OK"
    return plan
end

function E.PlanSet(set, snapshot, opts)
    local n = Resolve(set, snapshot, resolvedScratch, opts and opts.ignore)
    return BuildPlan(resolvedScratch, n, snapshot, opts)
end

-- One slot, one explicitly-chosen row from the flyout. Passing nil for the
-- candidate means "put what is there in my bags", which is the flyout's
-- PLACEINBAGS verb and needs no separate entry point.
function E.PlanSingle(slotID, candidateRow, snapshot)
    snapshot = snapshot or NO_ROWS
    local equipped = snapshot.equipped or NO_ROWS
    local slot = D.SlotByID[slotID]
    local r = ResetRow(singleScratch, 1)
    for i = 2, #singleScratch do singleScratch[i] = nil end
    r.slotID, r.slotKey = slotID, slot and slot.key
    r.from = equipped[slotID]

    if not candidateRow then
        r.state, r.to = EMPTY, { state = EMPTY }
        if r.from then
            r.action = "REMOVE"
            r.status = r.from.locked and "LOCKED" or "OK"
        else
            r.action, r.status = "NONE", "OK"
        end
    else
        -- The player pointed at a specific object, so there is no searching to
        -- do and no allocation to worry about — resolution is a single question
        -- about legality and reachability.
        local source = candidateRow.source or candidateRow
        r.state = ITEM
        r.to = {
            state = ITEM, key = candidateRow.key, baseKey = candidateRow.baseKey,
            itemID = candidateRow.itemID, name = candidateRow.name, icon = candidateRow.icon,
        }
        r.matched = "EXACT"
        r.action = "EQUIP"
        r.found = source
        if not SlotAccepts(snapshot, candidateRow, slotID) then
            r.status, r.found = "NOT_USABLE", nil
        elseif candidateRow.where == "BANK" then
            r.status, r.foundWhere = "IN_BANK", "BANK"
        elseif candidateRow.where == "EQUIPPED" then
            r.status, r.foundWhere, r.foundSlot = "OK", "EQUIPPED", candidateRow.fromSlot
        else
            r.foundWhere = "BAGS"
            r.status = candidateRow.locked and "LOCKED" or "OK"
        end
    end
    return BuildPlan(singleScratch, 1, snapshot, nil)
end

-- ---------------------------------------------------------------------------
-- Execution feedback (§2.6)
-- ---------------------------------------------------------------------------
--
-- The run is a cursor over a plan, not a contract. Two client facts shape it:
--
-- 1. ITEM_LOCK_CHANGED does not fire for every move. Empty slots do not lock,
--    so an action whose source or destination is bare produces no event at all.
--    Progress therefore may never be made CONDITIONAL on having seen a lock
--    change — the run advances on ReportResult, and the watchdog is a normal
--    completion path, not an emergency.
-- 2. Locks are PER SLOT. Several disjoint moves can legitimately be ready in
--    the same pass, so ReadyActions exists alongside NextAction for a host that
--    wants to drain them rather than serialise to one per tick.
--
-- And the robustness mechanism is neither of those: it is re-planning. After a
-- pass, the host re-snapshots, calls PlanSet again, and hands the result to
-- ReplanRun. That is what makes the asymmetric cases nobody wrote a branch for
-- — a ring sitting in Finger2 while Finger2's target comes out of a bag —
-- resolve on pass two instead of wedging.

local function Message(run, text)
    run.messages[#run.messages + 1] = text
end

function E.NewRun(plan)
    local run = {
        plan = plan, actions = {}, index = 1, retries = 0, passes = 1,
        progress = 0, seenProgress = -1, progressAt = nil,
        status = "RUNNING", equipped = 0, removed = 0, failed = 0,
        messages = {}, summary = { messages = {} },
    }
    local actions = plan and plan.actions
    if actions then
        -- Copied, not aliased: a run outlives the plan that made it and the
        -- next PlanSet must not be able to rewrite an in-flight action list.
        for i = 1, #actions do run.actions[i] = actions[i] end
    end
    if #run.actions == 0 then run.status = "DONE" end
    return run
end

-- Re-derive the remaining work from live state. Counters and messages survive
-- so the summary still describes the whole operation; the action list does not,
-- because positions captured at plan time are exactly what goes stale.
function E.ReplanRun(run, plan)
    if not run then return nil end
    for i = #run.actions, 1, -1 do run.actions[i] = nil end
    local actions = plan and plan.actions
    if actions then
        for i = 1, #actions do run.actions[i] = actions[i] end
    end
    run.plan = plan
    run.index = 1
    run.retries = 0
    run.passes = (run.passes or 1) + 1
    -- A re-plan IS progress: it is the moment the world demonstrably changed.
    run.progress = run.progress + 1
    run.seenProgress = -1
    run.progressAt = nil
    if #run.actions == 0 then
        run.status = (run.failed > 0) and "FAILED" or "DONE"
    else
        run.status = "RUNNING"
    end
    return run
end

local function IsLocked(snapshot, action)
    local equipped = snapshot.equipped or NO_ROWS
    local a, b, c = action.invSlot, action.fromSlot, action.toSlot
    local worn = a and equipped[a]
    if worn and worn.locked then return true end
    worn = b and equipped[b]
    if worn and worn.locked then return true end
    worn = c and equipped[c]
    if worn and worn.locked then return true end
    if action.bag and action.slot then
        local inv = snapshot.inventory or NO_ROWS
        for i = 1, #inv do
            local row = inv[i]
            if row.bag == action.bag and row.slot == action.slot then
                return row.locked == true
            end
        end
    end
    -- No row means an empty square, and an empty square never reports locked.
    -- This is the case that must NOT be treated as "wait for an event": no
    -- event is coming.
    return false
end

local function WaitReason(snapshot)
    if snapshot.dead then return "DEAD" end
    if snapshot.inCombat then return "IN_COMBAT" end
    if snapshot.casting then return "CASTING" end
    if snapshot.merchant then return "MERCHANT_OPEN" end
    if snapshot.cursorBusy then return "LOCKED" end
    return nil
end

function E.NextAction(run, snapshot)
    if not run then return nil, nil end
    snapshot = snapshot or NO_ROWS
    local now = snapshot.now or 0

    if run.status == "DONE" or run.status == "FAILED" or run.status == "TIMEOUT" then
        return nil, run.status
    end

    -- The watchdog measures PROGRESS, not calls. ReportResult has no clock in
    -- its signature (deliberately — it is called straight out of an event
    -- handler), so it bumps a counter and the next NextAction stamps the time.
    if run.seenProgress ~= run.progress or not run.progressAt then
        run.seenProgress, run.progressAt = run.progress, now
    end

    if run.index > #run.actions then
        run.status = (run.failed > 0) and "FAILED" or "DONE"
        return nil, run.status
    end

    if (now - run.progressAt) >= RUN_TIMEOUT then
        run.status = "TIMEOUT"
        Message(run, "Gave up waiting for the last swap to finish.")
        return nil, "TIMEOUT"
    end

    local wait = WaitReason(snapshot)
    local action = run.actions[run.index]
    -- Source or destination locked means the previous move is still in flight.
    -- Handing the action out anyway is how you get the client's "Internal bag
    -- error" — multi-pass is the design, not a fallback.
    if not wait and IsLocked(snapshot, action) then wait = "LOCKED" end

    if wait then
        run.status = "WAITING"
        return nil, wait
    end
    run.status = "RUNNING"
    return action, nil
end

local readyScratch = {}
local readySlots = {}

-- Every action at the head of the queue that is ready and touches no slot an
-- earlier one in this batch touches. A prefix, never a filter: skipping past a
-- blocked action would reorder the plan, and the order is load-bearing.
function E.ReadyActions(run, snapshot, out)
    local list = out or readyScratch
    for i = #list, 1, -1 do list[i] = nil end
    for id in pairs(readySlots) do readySlots[id] = nil end
    if not run then return list, nil end
    snapshot = snapshot or NO_ROWS

    local wait = WaitReason(snapshot)
    if wait then return list, wait end

    local n = 0
    for i = run.index, #run.actions do
        local action = run.actions[i]
        local a, b, c = action.invSlot, action.fromSlot, action.toSlot
        local overlaps = (a and readySlots[a]) or (b and readySlots[b]) or (c and readySlots[c])
        if overlaps or IsLocked(snapshot, action) then
            if n == 0 then return list, "LOCKED" end
            break
        end
        if a then readySlots[a] = true end
        if b then readySlots[b] = true end
        if c then readySlots[c] = true end
        n = n + 1
        list[n] = action
    end
    return list, nil
end

local TRANSIENT = {
    LOCKED = true, CURSOR_BUSY = true, ITEM_LOCKED = true, BIND_CONFIRM = true,
}

function E.ReportResult(run, action, ok, code)
    if not run then return end
    run.progress = run.progress + 1
    local op = action and action.op

    if ok then
        run.retries = 0
        if op == "MOVE_TO_BAG" then
            run.removed = run.removed + 1
            Message(run, format("Put %s away.", action.name or "an item"))
        elseif op == "WITHDRAW" then
            Message(run, format("Took %s out of the bank.", action.name or "an item"))
        else
            run.equipped = run.equipped + 1
            Message(run, format("Equipped %s.", action.name or "an item"))
        end
        run.index = run.index + 1
    elseif TRANSIENT[code or ""] and run.retries < MAX_RETRIES then
        -- Same action, next tick. The index does not move, so the run cannot
        -- skip a step just because the client was busy for one frame.
        run.retries = run.retries + 1
    else
        run.retries = 0
        run.failed = run.failed + 1
        Message(run, format("Could not move %s (%s).", action and action.name or "an item",
            code or "unknown"))
        run.index = run.index + 1
    end

    if run.index > #run.actions then
        run.status = (run.failed > 0) and "FAILED" or "DONE"
    end
end

function E.RunStatus(run)
    return run and run.status or nil
end

function E.RunSummary(run)
    if not run then return nil end
    local summary = run.summary
    summary.equipped = run.equipped
    summary.removed = run.removed
    summary.failed = run.failed
    summary.status = run.status
    summary.passes = run.passes
    summary.messages = run.messages
    return summary
end

-- ---------------------------------------------------------------------------
-- Stats (§2.7)
-- ---------------------------------------------------------------------------
--
-- We ship NO stat weights of our own. TBC theorycrafting is contentious enough
-- that any table we picked would be wrong for half the specs and would quietly
-- become the addon's opinion. Totals and deltas are facts; weights are not.
-- If Pawn is installed the host passes its scorer in as opts.score and the
-- flyout gains a SCORE sort — someone else's opinion, clearly labelled.

local STAT_LABELS = {
    ITEM_MOD_STRENGTH_SHORT             = "Strength",
    ITEM_MOD_AGILITY_SHORT              = "Agility",
    ITEM_MOD_STAMINA_SHORT              = "Stamina",
    ITEM_MOD_INTELLECT_SHORT            = "Intellect",
    ITEM_MOD_SPIRIT_SHORT               = "Spirit",
    ITEM_MOD_ATTACK_POWER_SHORT         = "Attack Power",
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT  = "Ranged Attack Power",
    ITEM_MOD_SPELL_POWER_SHORT          = "Spell Power",
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT    = "Spell Damage",
    ITEM_MOD_SPELL_HEALING_DONE_SHORT   = "Healing",
    ITEM_MOD_SPELL_PENETRATION_SHORT    = "Spell Penetration",
    ITEM_MOD_CRIT_RATING_SHORT          = "Crit Rating",
    ITEM_MOD_CRIT_SPELL_RATING_SHORT    = "Spell Crit Rating",
    ITEM_MOD_HIT_RATING_SHORT           = "Hit Rating",
    ITEM_MOD_HIT_SPELL_RATING_SHORT     = "Spell Hit Rating",
    ITEM_MOD_HASTE_RATING_SHORT         = "Haste Rating",
    -- Expertise, not weapon skill, is TBC's dodge/parry-reduction stat.
    ITEM_MOD_EXPERTISE_RATING_SHORT     = "Expertise Rating",
    ITEM_MOD_RESILIENCE_RATING_SHORT    = "Resilience Rating",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "Defense Rating",
    ITEM_MOD_DODGE_RATING_SHORT         = "Dodge Rating",
    ITEM_MOD_PARRY_RATING_SHORT         = "Parry Rating",
    ITEM_MOD_BLOCK_RATING_SHORT         = "Block Rating",
    ITEM_MOD_BLOCK_VALUE_SHORT          = "Block Value",
    ITEM_MOD_MANA_REGENERATION_SHORT    = "Mana per 5 sec",
    ITEM_MOD_HEALTH_REGENERATION_SHORT  = "Health per 5 sec",
    ITEM_MOD_POWER_REGEN0_SHORT         = "Mana per 5 sec",
    RESISTANCE0_NAME                    = "Armor",
    RESISTANCE1_NAME                    = "Holy Resistance",
    RESISTANCE2_NAME                    = "Fire Resistance",
    RESISTANCE3_NAME                    = "Nature Resistance",
    RESISTANCE4_NAME                    = "Frost Resistance",
    RESISTANCE5_NAME                    = "Shadow Resistance",
    RESISTANCE6_NAME                    = "Arcane Resistance",
}

function E.StatLabel(key)
    return STAT_LABELS[key] or key
end

local statRows = {}
local statSpoken = {}
local setStatsScratch = {}
local wornStatsScratch = {}

local function Accumulate(stats, row)
    if not row or not row.stats then return end
    for key, value in pairs(row.stats) do
        if type(value) == "number" then
            stats[key] = (stats[key] or 0) + value
        end
    end
end

-- Sums what you would be WEARING if this set were applied, which is why the
-- currently-worn item in an ignored slot counts: the set leaves it on, so it is
-- part of the answer. An EMPTY slot contributes nothing, which is also the
-- honest answer. Anything the set names but we cannot find contributes nothing
-- either — DiffSet is the place that tells you it is missing.
function E.SetStats(set, snapshot, out)
    local stats = out or setStatsScratch
    for key in pairs(stats) do stats[key] = nil end
    for key in pairs(statSpoken) do statSpoken[key] = nil end
    local ilvlTotal, counted = 0, 0
    if not snapshot then return stats, 0, 0 end
    local equipped = snapshot.equipped or NO_ROWS

    local n = Resolve(set, snapshot, statRows)
    for i = 1, n do
        local r = statRows[i]
        statSpoken[r.slotID] = true
        local row = (r.action ~= "REMOVE") and r.found or nil
        if row then
            Accumulate(stats, row)
            if row.ilvl then ilvlTotal = ilvlTotal + row.ilvl; counted = counted + 1 end
        end
    end
    for i = 1, #D.SlotOrder do
        local id = D.SlotOrder[i]
        if not statSpoken[id] then
            local row = equipped[id]
            if row then
                Accumulate(stats, row)
                if row.ilvl then ilvlTotal = ilvlTotal + row.ilvl; counted = counted + 1 end
            end
        end
    end
    -- Averaged over items actually counted, not over a fixed sixteen. Blizzard
    -- divides by a constant and so reports a lower average for a character with
    -- an empty slot than for the same character with a grey in it, which is a
    -- number nobody asked for.
    return stats, ilvlTotal, counted > 0 and (ilvlTotal / counted) or 0
end

function E.EquippedStats(snapshot, out)
    local stats = out or wornStatsScratch
    for key in pairs(stats) do stats[key] = nil end
    local ilvlTotal, counted = 0, 0
    if not snapshot then return stats, 0, 0 end
    local equipped = snapshot.equipped or NO_ROWS
    for i = 1, #D.SlotOrder do
        local row = equipped[D.SlotOrder[i]]
        if row then
            Accumulate(stats, row)
            if row.ilvl then ilvlTotal = ilvlTotal + row.ilvl; counted = counted + 1 end
        end
    end
    return stats, ilvlTotal, counted > 0 and (ilvlTotal / counted) or 0
end

local deltaScratch = {}
local deltaSeen = {}

local function CmpDelta(a, b)
    if abs(a.delta) ~= abs(b.delta) then return abs(a.delta) > abs(b.delta) end
    return a.key < b.key
end

-- Only the stats that actually move. A delta list that includes forty rows of
-- "+0 Arcane Resistance" is a list nobody reads.
function E.StatDelta(setStats, currentStats)
    for i = #deltaScratch, 1, -1 do deltaScratch[i] = nil end
    for key in pairs(deltaSeen) do deltaSeen[key] = nil end
    local n = 0

    local function Push(key)
        if deltaSeen[key] then return end
        deltaSeen[key] = true
        local from = (currentStats and currentStats[key]) or 0
        local to = (setStats and setStats[key]) or 0
        if from ~= to then
            n = n + 1
            local row = deltaScratch[n]
            if not row then row = {}; deltaScratch[n] = row end
            row.key, row.label, row.from, row.to, row.delta = key, E.StatLabel(key), from, to, to - from
        end
    end

    for key in pairs(setStats or NO_ROWS) do Push(key) end
    for key in pairs(currentStats or NO_ROWS) do Push(key) end
    -- Cleared above and truncated here, so the sort can never see a leftover
    -- row from a longer previous comparison.
    for i = n + 1, #deltaScratch do deltaScratch[i] = nil end
    sort(deltaScratch, CmpDelta)
    return deltaScratch
end
