-- Commander Armory engine fixture harness (luajit).
-- The engine is pure Lua, so there is NO mock here at all: only the real
-- CommanderArmoryData.lua and CommanderArmoryEngine.lua, loaded with loadfile.
-- A failure below is therefore always a real logic bug, never a mock artefact.
--
-- It drives hand-written world snapshots through the real engine and asserts
-- item identity against links this client actually writes, the three-state
-- entry model (the IGNORED-is-not-EMPTY invariant), the flyout's contents and
-- ordering, every refusal path in the planner, the complete TBC unique-equipped
-- conflict model, free-bag-slot accounting by formula, the multi-pass run state
-- machine, and the stat totals.
--
--   /opt/homebrew/bin/luajit armory_harness.lua

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end

assert(loadfile(ADDONS .. "/Commander_Armory/CommanderArmoryData.lua"))()
assert(loadfile(ADDONS .. "/Commander_Armory/CommanderArmoryEngine.lua"))()
local D = CommanderArmoryData
local E = CommanderArmoryEngine

-- ===========================================================================
-- Fixture helpers
-- ===========================================================================

-- Builds a link in this client's own shape: nineteen fields, empties written as
-- empty strings rather than zeros.
local function Link(o)
    return string.format("|cffa335ee|Hitem:%s:%s:%s:%s:%s:%s:%s:%s:%s::::::::::|h[%s]|h|r",
        tostring(o.id),
        o.enchant and tostring(o.enchant) or "",
        o.g1 and tostring(o.g1) or "", o.g2 and tostring(o.g2) or "",
        o.g3 and tostring(o.g3) or "", o.g4 and tostring(o.g4) or "",
        o.suffix and tostring(o.suffix) or "",
        o.uniq and tostring(o.uniq) or "",
        o.level and tostring(o.level) or "",
        o.name or "Item")
end

local nextUniq = 1000
local function Row(o)
    nextUniq = nextUniq + 7
    o.uniq = o.uniq or nextUniq
    o.link = Link(o)
    local key, itemID, baseKey = E.ItemKey(o.link)
    o.key, o.itemID, o.baseKey = key, itemID, baseKey
    o.quality = o.quality or 4
    o.ilvl = o.ilvl or 100
    return o
end

-- A second physical copy of the same item: a different uniqueID, and therefore
-- a byte-different link that MUST still produce the same key.
local function Copy(row, over)
    local o = {}
    for k, v in pairs(row) do o[k] = v end
    o.uniq = nil
    o.link, o.key, o.baseKey = nil, nil, nil
    for k, v in pairs(over or {}) do o[k] = v end
    return Row(o)
end

local function Snap(o)
    o = o or {}
    o.now = o.now or 0
    o.equipped = o.equipped or {}
    o.inventory = o.inventory or {}
    o.freeBagSlots = o.freeBagSlots or 10
    o.playerClass = o.playerClass or "WARRIOR"
    return o
end

local function Bag(row, bag, slot)
    row.where, row.bag, row.slot = "BAGS", bag or 0, slot or 1
    return row
end

local function Bank(row, bag, slot)
    row.where, row.bag, row.slot, row.stale = "BANK", bag or -1, slot or 1, true
    return row
end

local function Entry(spec)
    if spec == "EMPTY" then return { state = "EMPTY" } end
    if spec == "IGNORED" then return { state = "IGNORED" } end
    if type(spec) == "table" and spec.state then return spec end
    return {
        state = "ITEM", key = spec.key, baseKey = spec.baseKey,
        itemID = spec.itemID, name = spec.name, icon = spec.icon,
    }
end

local function Set(entries)
    local set = E.NewSet("Fixture", "icon")
    for slotKey, spec in pairs(entries or {}) do
        set.entries[slotKey] = Entry(spec)
    end
    return set
end

local function ReasonWith(plan, code)
    for i = 1, #plan.reasons do
        if plan.reasons[i].code == code then return plan.reasons[i] end
    end
    return nil
end

local function CountOp(plan, op)
    local n = 0
    for i = 1, #plan.actions do
        if plan.actions[i].op == op then n = n + 1 end
    end
    return n
end

local function ActionFor(plan, op, invSlot)
    for i = 1, #plan.actions do
        local a = plan.actions[i]
        if a.op == op and (invSlot == nil or a.invSlot == invSlot) then return a, i end
    end
    return nil
end

local function RowFor(diff, slotKey)
    for i = 1, diff.n do
        if diff.changes[i].slotKey == slotKey then return diff.changes[i] end
    end
    return nil
end

local function EveryActionHasDestination(plan)
    for i = 1, #plan.actions do
        local a = plan.actions[i]
        if a.invSlot == nil then return false, a.op end
    end
    return true
end

-- Shared item fixtures -------------------------------------------------------

local ARMOR, WEAPON = D.CLASS_ARMOR, D.CLASS_WEAPON

local headPlate  = Row{ id = 29011, name = "Plate Helm",  equipLoc = "INVTYPE_HEAD",  classID = ARMOR, subClassID = 4, ilvl = 120 }
local headPlate2 = Row{ id = 29012, name = "Better Helm", equipLoc = "INVTYPE_HEAD",  classID = ARMOR, subClassID = 4, ilvl = 141 }
local headCloth  = Row{ id = 29013, name = "Cloth Hood",  equipLoc = "INVTYPE_HEAD",  classID = ARMOR, subClassID = 1, ilvl = 115, quality = 3 }
local chestPlate = Row{ id = 29020, name = "Plate Chest", equipLoc = "INVTYPE_CHEST", classID = ARMOR, subClassID = 4, ilvl = 125 }
local robe       = Row{ id = 29021, name = "Silk Robe",   equipLoc = "INVTYPE_ROBE",  classID = ARMOR, subClassID = 1, ilvl = 110 }
local cloak2     = Row{ id = 29031, name = "Better Cloak", equipLoc = "INVTYPE_CLOAK", classID = ARMOR, subClassID = 0, ilvl = 128 }
local cloak      = Row{ id = 29030, name = "Cloak",       equipLoc = "INVTYPE_CLOAK", classID = ARMOR, subClassID = 0, ilvl = 115 }
local shirt      = Row{ id = 29040, name = "Shirt",       equipLoc = "INVTYPE_BODY",  classID = ARMOR, subClassID = 0, ilvl = 1, quality = 1 }
local tabard     = Row{ id = 29041, name = "Tabard",      equipLoc = "INVTYPE_TABARD",classID = ARMOR, subClassID = 0, ilvl = 1, quality = 1 }

local ringA = Row{ id = 30000, name = "Ring A", equipLoc = "INVTYPE_FINGER", classID = ARMOR, subClassID = 0, ilvl = 115 }
local ringB = Row{ id = 30001, name = "Ring B", equipLoc = "INVTYPE_FINGER", classID = ARMOR, subClassID = 0, ilvl = 120 }
local ringUnique = Row{ id = 30002, name = "Unique Ring", equipLoc = "INVTYPE_FINGER", classID = ARMOR, subClassID = 0, ilvl = 130, unique = true }

local trinketA = Row{ id = 31000, name = "Trinket A", equipLoc = "INVTYPE_TRINKET", classID = ARMOR, subClassID = 0, ilvl = 125 }
local trinketB = Row{ id = 31001, name = "Trinket B", equipLoc = "INVTYPE_TRINKET", classID = ARMOR, subClassID = 0, ilvl = 128 }

local sword     = Row{ id = 32000, name = "Sword",     equipLoc = "INVTYPE_WEAPON",         classID = WEAPON, subClassID = 7, ilvl = 130 }
local dagger    = Row{ id = 32003, name = "Dagger",    equipLoc = "INVTYPE_WEAPON",         classID = WEAPON, subClassID = 15, ilvl = 128 }
local shield    = Row{ id = 32001, name = "Shield",    equipLoc = "INVTYPE_SHIELD",         classID = ARMOR,  subClassID = 6, ilvl = 120 }
local holdable  = Row{ id = 32004, name = "Tome",      equipLoc = "INVTYPE_HOLDABLE",       classID = ARMOR,  subClassID = 0, ilvl = 115 }
local offhander = Row{ id = 32005, name = "Off-hander", equipLoc = "INVTYPE_WEAPONOFFHAND", classID = WEAPON, subClassID = 7, ilvl = 118 }
local twoHander = Row{ id = 32002, name = "Great Axe", equipLoc = "INVTYPE_2HWEAPON",       classID = WEAPON, subClassID = 1, ilvl = 140 }

local bow    = Row{ id = 33000, name = "Bow",    equipLoc = "INVTYPE_RANGED", classID = WEAPON, subClassID = 2, ilvl = 120 }
local libram = Row{ id = 33001, name = "Libram", equipLoc = "INVTYPE_RELIC",  classID = ARMOR,  subClassID = D.ArmorSubclass.LIBRAM, ilvl = 110 }
local idol   = Row{ id = 33002, name = "Idol",   equipLoc = "INVTYPE_RELIC",  classID = ARMOR,  subClassID = D.ArmorSubclass.IDOL,   ilvl = 110 }
local arrows = Row{ id = 34000, name = "Arrows", equipLoc = "INVTYPE_AMMO",   classID = 6,      subClassID = 2, ilvl = 1, quality = 1 }

-- The three real TBC limit-category families.
local violet1 = Row{ id = 29276, name = "Violet Signet",   equipLoc = "INVTYPE_FINGER", classID = ARMOR, subClassID = 0, ilvl = 115 }
local violet2 = Row{ id = 29277, name = "Violet Signet II", equipLoc = "INVTYPE_FINGER", classID = ARMOR, subClassID = 0, ilvl = 128 }
local eternity = Row{ id = 29294, name = "Band of Eternity", equipLoc = "INVTYPE_FINGER", classID = ARMOR, subClassID = 0, ilvl = 141 }
local bronze  = Row{ id = 21196, name = "Bronze Signet",   equipLoc = "INVTYPE_FINGER", classID = ARMOR, subClassID = 0, ilvl = 90 }

-- Two pieces cut with the same gem, and two ungemmed controls.
local gemHead  = Row{ id = 29050, name = "Gemmed Helm",  equipLoc = "INVTYPE_HEAD",  classID = ARMOR, subClassID = 4, g1 = 32409, ilvl = 141 }
local gemChest = Row{ id = 29051, name = "Gemmed Chest", equipLoc = "INVTYPE_CHEST", classID = ARMOR, subClassID = 4, g1 = 32409, ilvl = 141 }

-- ===========================================================================
-- A: item identity — the key format, against links this client really writes
-- ===========================================================================

CHECK(E.ItemKey(nil) == nil, "A: a nil link yields no key rather than erroring")
CHECK(E.ItemKey(false) == nil, "A: a boolean link yields no key")
CHECK(E.ItemKey({}) == nil, "A: a table link yields no key")
CHECK(E.ItemKey("") == nil, "A: an empty string yields no key")
CHECK(E.ItemKey("Hello there") == nil, "A: a string with no item payload yields no key")
CHECK(E.ItemKey("item:") == nil, "A: an item prefix with no id yields no key")
CHECK(E.ItemKey("item:0") == nil, "A: item id zero is not an item")
CHECK(E.ItemKey("item:abc") == nil, "A: a non-numeric item id yields no key")
CHECK(E.ItemKey(0) == nil, "A: a bare item id of zero yields no key")
CHECK(E.ItemKey(-5) == nil, "A: a negative bare item id yields no key")

do
    -- Verbatim shape of a link written by this install.
    local real = "|cff1eff00|Hitem:25059::::::-36:1830748181:60::::::::::|h[Test]|h|r"
    local key, itemID, baseKey = E.ItemKey(real)
    CHECK(key == "25059:-36:0:0:0:0:0", "A: 19-field link with empty payload fields parses", key)
    CHECK(itemID == 25059, "A: item id survives a link full of empty fields", itemID)
    CHECK(baseKey == "25059:-36", "A: a negative suffix id lands in the base key", baseKey)
    CHECK(E.BaseKey(key) == baseKey, "A: base key is a prefix of the full key")

    local bare = "item:25059::::::-36:1830748181:60::::::::::"
    CHECK(E.ItemKey(bare) == key, "A: a bare item string with no |Hitem wrapper parses identically")

    local legacy = "item:29918:2564:0:0:0:0:0:0:70"
    local lkey, lid, lbase = E.ItemKey(legacy)
    CHECK(lkey == "29918:0:2564:0:0:0:0", "A: a legacy 10-field string parses with enchant in place", lkey)
    CHECK(lid == 29918 and lbase == "29918:0", "A: legacy string base key")
end

do
    local plain = Row{ id = 28000, name = "Plain" }
    local twin  = Copy(plain)
    CHECK(plain.link ~= twin.link, "A: two copies really do produce different links")
    -- uniqueID is dropped on purpose. Its low bits are a function of the item
    -- id and its high bits are noise; keeping it would make nothing ever match.
    CHECK(plain.key == twin.key, "A: two copies with different uniqueIDs share one key")

    local deeper = Copy(plain, { level = 1 })
    CHECK(deeper.key == plain.key, "A: the viewer's link level never reaches the key")

    local enchanted = Copy(plain, { enchant = 2564 })
    CHECK(enchanted.key ~= plain.key, "A: an enchanted copy is a different key")
    CHECK(enchanted.baseKey == plain.baseKey, "A: an enchanted copy shares the base key")

    local gemmed = Copy(plain, { g1 = 32409 })
    CHECK(gemmed.key ~= plain.key, "A: a gemmed copy is a different key")
    CHECK(gemmed.baseKey == plain.baseKey, "A: a gemmed copy shares the base key")
    local gemmed4 = Copy(plain, { g4 = 32409 })
    CHECK(gemmed4.key ~= gemmed.key, "A: which socket a gem sits in changes the key")

    local suffixed = Copy(plain, { suffix = 1805 })
    CHECK(suffixed.key ~= plain.key, "A: an 'of the Bear' suffix is a different key")
    CHECK(suffixed.baseKey ~= plain.baseKey,
        "A: a suffix roll is a different ITEM, so the base key differs too")

    local exact, loose = E.KeyMatches(plain.key, twin.key)
    CHECK(exact and not loose, "A: identical keys report exact and NOT loose")
    exact, loose = E.KeyMatches(plain.key, enchanted.key)
    CHECK((not exact) and loose, "A: same item, different decoration reports loose")
    exact, loose = E.KeyMatches(plain.key, suffixed.key)
    CHECK((not exact) and (not loose), "A: a different suffix roll matches neither way")
    exact, loose = E.KeyMatches(plain.key, headPlate.key)
    CHECK((not exact) and (not loose), "A: unrelated items match neither way")
    exact, loose = E.KeyMatches(nil, plain.key)
    CHECK((not exact) and (not loose), "A: a nil saved key matches nothing")
    exact, loose = E.KeyMatches(plain.key, nil)
    CHECK((not exact) and (not loose), "A: a nil candidate key matches nothing")

    local n = 0
    for _ in plain.key:gmatch("[^:]+") do n = n + 1 end
    CHECK(n == 7, "A: the key is exactly seven fields", plain.key)

    local byID, idOut, baseOut = E.ItemKey(28000)
    CHECK(byID == "28000:0:0:0:0:0:0" and idOut == 28000 and baseOut == "28000:0",
        "A: a bare item id produces an undecorated key")
    CHECK(E.KeyMatches(plain.key, byID) == true,
        "A: an undecorated link and an id-only key are the same key")
    CHECK(select(2, E.KeyMatches(enchanted.key, byID)) == true,
        "A: an id-only key loose-matches a decorated link for the same item")
    CHECK(E.BaseKey(nil) == nil, "A: BaseKey of nil is nil")
    CHECK(E.BaseKey(42) == nil, "A: BaseKey of a number is nil")
end

-- ===========================================================================
-- B: capture — what a saved set records, and what it deliberately does not
-- ===========================================================================

do
    local snap = Snap{
        equipped = { [1] = headPlate, [5] = chestPlate, [11] = ringA, [16] = sword },
    }
    local entries = E.CaptureSet(snap)
    local n = 0
    for _ in pairs(entries) do n = n + 1 end
    CHECK(n == #D.Slots, "B: capture writes one entry per canon slot", n)
    CHECK(entries.ammo == nil, "B: ammo is never captured")
    CHECK(entries.head.state == "ITEM" and entries.head.key == headPlate.key,
        "B: a worn item is captured as ITEM with its key")
    CHECK(entries.head.itemID == headPlate.itemID and entries.head.name == "Plate Helm",
        "B: a captured entry carries id and name for offline display")
    CHECK(entries.head.baseKey == headPlate.baseKey, "B: a captured entry carries the base key")
    CHECK(entries.legs.state == "EMPTY", "B: a bare slot is captured as EMPTY, not ignored")
    CHECK(entries.shirt.state == "IGNORED", "B: the shirt defaults to IGNORED")
    CHECK(entries.tabard.state == "IGNORED", "B: the tabard defaults to IGNORED")

    local withCosmetic = E.CaptureSet(snap, { includeCosmetic = true })
    CHECK(withCosmetic.shirt.state == "EMPTY",
        "B: includeCosmetic makes an empty shirt slot a real EMPTY entry")

    local ignored = E.CaptureSet(snap, { ignore = { head = true, mainhand = true } })
    CHECK(ignored.head.state == "IGNORED", "B: an ignored slot is captured as IGNORED")
    CHECK(ignored.mainhand.state == "IGNORED", "B: ignoring works for weapon slots too")
    CHECK(ignored.chest.state == "ITEM", "B: ignoring one slot does not disturb the others")

    local set = E.NewSet("Arena", "Interface\\Icons\\X")
    CHECK(set.name == "Arena" and set.icon == "Interface\\Icons\\X", "B: NewSet keeps name and icon")
    CHECK(type(set.entries) == "table", "B: NewSet starts with an empty entry table")
    CHECK(next(set.entries) == nil, "B: a fresh set speaks for no slot at all")
    CHECK(E.CaptureSet(nil).head == nil, "B: capturing a nil snapshot is empty, not an error")
end

-- ===========================================================================
-- B2: a NEW set is naked — it specifies nothing worn at all
-- ===========================================================================
--
-- E.NewSet is still the bare constructor (the fixtures above depend on it and
-- so does a half-authored set). E.NakedSet is what "New" means to the player:
-- every slot EMPTY, so equipping it STRIPS you, with shirt and tabard hands-off
-- for D5's reason applied at creation instead of at capture.

do
    local naked = E.NakedSet("Fresh", "Interface\\Icons\\Y")
    CHECK(naked.name == "Fresh" and naked.icon == "Interface\\Icons\\Y",
        "B2: NakedSet keeps name and icon")

    local total, empty, ignored, item = 0, 0, 0, 0
    for _, entry in pairs(naked.entries) do
        total = total + 1
        local state = E.EntryState(entry)
        if state == "EMPTY" then empty = empty + 1
        elseif state == "IGNORED" then ignored = ignored + 1
        else item = item + 1 end
    end
    CHECK(total == #D.Slots, "B2: a new set writes one entry per canon slot", total)
    CHECK(empty == #D.Slots - 2, "B2: and every one of them is EMPTY but two", empty)
    CHECK(ignored == 2 and item == 0,
        "B2: exactly two are IGNORED and none names an item", ignored .. "/" .. item)
    CHECK(naked.entries.shirt.state == "IGNORED", "B2: the shirt is the first of them")
    CHECK(naked.entries.tabard.state == "IGNORED", "B2: and the tabard the second")
    CHECK(naked.entries.head.state == "EMPTY",
        "B2: EMPTY is the explicit string, never a missing entry", tostring(naked.entries.head.state))
    CHECK(naked.entries.ammo == nil, "B2: ammo is outside the model even when nothing is worn")

    -- The point of EMPTY rather than a missing entry: equipping a fresh set
    -- takes your gear OFF. A set of missing entries would read as nineteen
    -- IGNOREDs and do nothing at all, which is the bug this replaced.
    local snap = Snap{ equipped = { [1] = headPlate, [5] = chestPlate, [16] = sword },
        freeBagSlots = 10 }
    local plan = E.PlanSet(naked, snap)
    CHECK(plan.ok == true, "B2: a naked set is a plan that runs", plan.verdict)
    CHECK(#plan.actions == 3, "B2: with one action per worn slot", #plan.actions)
    local removals = 0
    for i = 1, #plan.actions do
        if plan.actions[i].op == "MOVE_TO_BAG" then removals = removals + 1 end
    end
    CHECK(removals == 3, "B2: and every one of them strips a slot to the bags", removals)
    CHECK(plan.needFree == 3, "B2: reserving a bag slot for each", plan.needFree)

    -- The cosmetics are the proof that IGNORED is not EMPTY here: a worn shirt
    -- and tabard are left alone by the same plan that strips everything else.
    local dressed = Snap{ equipped = { [1] = headPlate, [4] = shirt, [19] = tabard },
        freeBagSlots = 10 }
    local plan2 = E.PlanSet(naked, dressed)
    CHECK(#plan2.actions == 1 and plan2.actions[1].invSlot == 1,
        "B2: the shirt and tabard are hands-off, so only the head comes off", #plan2.actions)

    local diff = E.DiffSet(naked, Snap{ equipped = {} })
    CHECK(diff.isEquipped == true,
        "B2: a naked set is 'already worn' when you are wearing nothing")
end

-- ===========================================================================
-- B3: authoring one slot — an entry built from a candidate row
-- ===========================================================================
--
-- The pane writes a set slot by slot without equipping anything, and the entry
-- it writes has to be indistinguishable from a captured one. In particular it
-- must carry baseKey: an entry without one silently loses loose matching, and
-- nothing says so until the player re-enchants the item.

do
    local row = Bag(Copy(headPlate2), 1, 4)
    local entry = E.AuthorEntry(row)
    CHECK(entry.state == "ITEM", "B3: an authored entry is an ITEM")
    CHECK(entry.key == row.key, "B3: carrying the item key")
    CHECK(entry.baseKey == row.baseKey and entry.baseKey ~= nil,
        "B3: and the BASE key, without which loose matching silently stops working",
        tostring(entry.baseKey))
    CHECK(entry.itemID == row.itemID and entry.name == row.name and entry.icon == row.icon,
        "B3: plus the id, name and icon a set needs to draw itself offline")

    -- Field-for-field the same shape CaptureSet writes, so the planner cannot
    -- tell an authored slot from a captured one.
    local captured = E.CaptureSet(Snap{ equipped = { [1] = row } }).head
    for field in pairs(captured) do
        CHECK(entry[field] ~= nil or captured[field] == nil,
            "B3: an authored entry carries every field a captured one does", field)
    end

    -- Candidate rows are POOLED: the engine refills the same tables on the next
    -- call. An entry that aliased one would silently become a different item.
    local before = entry.key
    row.key, row.name, row.itemID = "999:0:0:0:0:0:0", "Something Else", 999
    CHECK(entry.key == before and entry.name ~= "Something Else",
        "B3: the entry is a COPY, so rewriting the pooled row cannot reach it")

    CHECK(E.AuthorEntry(nil) == nil, "B3: no row is no entry, not a half-built one")
    CHECK(E.AuthorEntry({ name = "keyless" }) == nil, "B3: and a row with no key is refused")

    CHECK(E.EmptyEntry().state == "EMPTY",
        "B3: 'leave this slot bare' is EMPTY, not a deleted entry")

    -- Authored into a real set, the planner treats it exactly as a capture.
    local target = E.NakedSet("Authored")
    target.entries.head = E.AuthorEntry(Bag(Copy(headPlate2), 1, 4))
    local snap = Snap{ equipped = {}, inventory = { Bag(Copy(headPlate2), 1, 4) } }
    local plan = E.PlanSet(target, snap)
    CHECK(plan.ok and #plan.actions == 1 and plan.actions[1].op == "EQUIP_FROM_BAG",
        "B3: a set authored without wearing anything plans a real equip")
end

-- ===========================================================================
-- C: the diff — IGNORED is not EMPTY, and everything that follows from it
-- ===========================================================================

do
    local snap = Snap{ equipped = { [1] = headPlate, [5] = chestPlate } }

    -- An ignored slot holding something entirely different must not make the
    -- set "not equipped" and must not appear in the change list at all.
    local set = Set{ head = headPlate, chest = "IGNORED" }
    local diff = E.DiffSet(set, snap)
    CHECK(diff.isEquipped, "C: an ignored slot differing does not make the set unequipped")
    CHECK(RowFor(diff, "chest") == nil, "C: an ignored slot is not in the change list")
    CHECK(diff.ignored == #D.Slots - 1, "C: everything the set does not speak for counts as ignored")
    CHECK(diff.touched == 0, "C: nothing to do when the one live slot already matches")

    -- A missing entry means ignored, so the chest is left alone.
    local sparse = Set{ head = headPlate }
    local d2 = E.DiffSet(sparse, snap)
    CHECK(d2.isEquipped, "C: a slot with NO entry behaves exactly like an ignored one")
    CHECK(d2.n == 1, "C: a one-slot set produces exactly one change row")

    -- EMPTY is the opposite instruction.
    local strip = Set{ head = headPlate, chest = "EMPTY" }
    local d3 = E.DiffSet(strip, snap)
    CHECK(RowFor(d3, "chest").action == "REMOVE", "C: an EMPTY entry over a worn item is a removal")
    CHECK(not d3.isEquipped, "C: a set with an unsatisfied EMPTY is not equipped")

    local strippedAlready = E.DiffSet(Set{ legs = "EMPTY" }, snap)
    CHECK(RowFor(strippedAlready, "legs").action == "NONE",
        "C: an EMPTY entry over an already-bare slot is no work")
    CHECK(strippedAlready.isEquipped, "C: an already-bare EMPTY slot counts as equipped")
end

do
    -- Corrupt entries must resolve in the SAFE direction. This is the whole
    -- reason the three states are explicit strings: ItemRack's most-reported
    -- cursor bug reduces to 0 / "0" / nil all having meant "empty".
    local snap = Snap{ equipped = { [1] = headPlate } }
    local cases = {
        { state = 0 }, { state = "0" }, { state = "empty" }, { state = "" },
        { state = "ITEM" },            -- ITEM with no key at all
        { state = true }, {},
    }
    for i = 1, #cases do
        local set = E.NewSet("Broken")
        set.entries.head = cases[i]
        local diff = E.DiffSet(set, snap)
        CHECK(diff.n == 0 and diff.isEquipped,
            "C: a malformed entry state leaves the slot untouched, never stripped", i)
        local plan = E.PlanSet(set, snap)
        CHECK(#plan.actions == 0 and ReasonWith(plan, "NOTHING_TO_DO") ~= nil,
            "C: a malformed entry produces no action of any kind", i)
    end
    local set = E.NewSet("Broken")
    set.entries.head = "not a table"
    CHECK(E.EntryState(set.entries.head) == "IGNORED", "C: a non-table entry reads as IGNORED")
    CHECK(E.EntryState(nil) == "IGNORED", "C: a nil entry reads as IGNORED")
    CHECK(E.EntryState({ state = "EMPTY" }) == "EMPTY", "C: EMPTY is honoured when spelled exactly")
end

do
    -- Where the item is, told apart precisely.
    local bagRing = Bag(Copy(ringB), 1, 3)
    local bankTrinket = Bank(Copy(trinketB), -1, 4)
    local snap = Snap{
        equipped = { [11] = ringA },
        inventory = { bagRing, bankTrinket },
    }
    local set = Set{ finger1 = ringB, trinket1 = trinketB, trinket2 = trinketA }
    local diff = E.DiffSet(set, snap)
    CHECK(RowFor(diff, "finger1").action == "EQUIP", "C: an item sitting in a bag is an equip")
    CHECK(RowFor(diff, "finger1").status == "OK", "C: a bagged exact match is status OK")
    CHECK(RowFor(diff, "trinket1").status == "IN_BANK", "C: a banked item reports IN_BANK")
    CHECK(RowFor(diff, "trinket1").status ~= "MISSING", "C: banked is never reported as missing")
    CHECK(RowFor(diff, "trinket2").status == "MISSING", "C: an item nowhere at all is MISSING")
    CHECK(diff.inBank == 1 and diff.missing == 1, "C: the diff counts banked and missing separately")
    CHECK(diff.touched == 3, "C: every unsatisfied slot counts as touched")
end

do
    -- Exact beats loose, and a loose result is labelled so the UI can say so.
    local enchanted = Bag(Copy(headPlate, { enchant = 2564 }), 1, 1)
    local plain = Bag(Copy(headPlate), 1, 2)
    local snap = Snap{ inventory = { plain, enchanted } }

    local wantEnchanted = Set{ head = enchanted }
    local d1 = E.DiffSet(wantEnchanted, snap)
    CHECK(RowFor(d1, "head").found == enchanted, "C: an exact match wins over a loose one")
    CHECK(RowFor(d1, "head").status == "OK", "C: an exact match is not reported as loose")

    local onlyPlain = Snap{ inventory = { plain } }
    local d2 = E.DiffSet(wantEnchanted, onlyPlain, {})
    CHECK(RowFor(d2, "head").found == plain, "C: a loose copy is used when the exact one is gone")
    CHECK(RowFor(d2, "head").status == "LOOSE", "C: a loose match is reported as LOOSE")
    CHECK(RowFor(d2, "head").matched == "LOOSE", "C: the loose match is labelled on the row")

    -- Wearing a differently-enchanted copy is left alone rather than churned.
    local worn = Snap{ equipped = { [1] = plain }, inventory = { Bag(Copy(headPlate), 2, 1) } }
    local d3 = E.DiffSet(wantEnchanted, worn, {})
    CHECK(RowFor(d3, "head").action == "NONE",
        "C: a worn loose copy is left in place rather than swapped for another loose copy")
    CHECK(RowFor(d3, "head").status == "LOOSE", "C: the worn loose copy is still labelled LOOSE")
end

do
    local snap = Snap{ equipped = { [1] = headPlate } }
    local dirty, keys = E.SetIsDirty(Set{ head = headPlate }, snap)
    CHECK(dirty == false and #keys == 0, "C: a set you are wearing is not dirty")
    dirty, keys = E.SetIsDirty(Set{ head = headPlate2, chest = "EMPTY" }, snap)
    CHECK(dirty == true, "C: a set that differs is dirty")
    CHECK(#keys == 1 and keys[1] == "head",
        "C: only slots that need work are named dirty (an already-bare EMPTY is not)")
end

-- ===========================================================================
-- D: the flyout
-- ===========================================================================

do
    local wornRing = ringA
    local bagRing = Bag(Copy(ringB), 1, 1)
    local otherWorn = Copy(ringB, { name = "Worn Ring 2", ilvl = 133 })
    local snap = Snap{
        equipped = { [11] = wornRing, [12] = otherWorn },
        inventory = { bagRing, Bag(Copy(headPlate), 1, 2) },
    }
    local rows = E.Candidates(snap, 11)
    local found = {}
    for i = 1, #rows do found[rows[i].name] = rows[i] end
    CHECK(found["Ring A"] == nil, "D: the item already in the slot is not a candidate for it")
    CHECK(found["Worn Ring 2"] ~= nil, "D: another equipped item that could move here is offered")
    CHECK(found["Worn Ring 2"].where == "EQUIPPED", "D: an equipped candidate is marked EQUIPPED")
    CHECK(found["Worn Ring 2"].fromSlot == 12, "D: an equipped candidate carries its source slot")
    CHECK(found["Ring B"] ~= nil, "D: a ring in a bag is offered")
    CHECK(found["Plate Helm"] == nil, "D: a helm is not offered for a finger slot")
    CHECK(#rows == 2, "D: exactly the two legal candidates", #rows)
    CHECK(rows[1].ilvl >= rows[2].ilvl, "D: the default sort is item level descending")
    CHECK(rows[1].source ~= nil, "D: each row points back at the real snapshot object")
end

do
    -- Sorting modes, and the tail-clearing that a pooled scratch demands.
    local a = Bag(Row{ id = 40001, name = "Alpha",  equipLoc = "INVTYPE_FINGER", classID = ARMOR, subClassID = 0, ilvl = 100, quality = 2 }, 1, 1)
    local b = Bag(Row{ id = 40002, name = "Bravo",  equipLoc = "INVTYPE_FINGER", classID = ARMOR, subClassID = 0, ilvl = 140, quality = 3 }, 1, 2)
    local c = Bag(Row{ id = 40003, name = "Charlie",equipLoc = "INVTYPE_FINGER", classID = ARMOR, subClassID = 0, ilvl = 120, quality = 5 }, 1, 3)
    local snap = Snap{ inventory = { a, b, c } }

    local rows = E.Candidates(snap, 11, { sort = "ILVL" })
    CHECK(rows[1].name == "Bravo" and rows[3].name == "Alpha", "D: ILVL sort orders by item level")
    rows = E.Candidates(snap, 11, { sort = "NAME" })
    CHECK(rows[1].name == "Alpha" and rows[3].name == "Charlie", "D: NAME sort is alphabetical")
    rows = E.Candidates(snap, 11, { sort = "QUALITY" })
    CHECK(rows[1].name == "Charlie", "D: QUALITY sort puts the epic first")
    rows = E.Candidates(snap, 11, { sort = "SCORE", score = function(row) return row.itemID end })
    CHECK(rows[1].name == "Charlie", "D: SCORE sort uses the supplied scorer, highest first")

    rows = E.Candidates(snap, 11, { minQuality = 4 })
    CHECK(#rows == 1 and rows[1].name == "Charlie", "D: a minimum quality filters bag rows")
    rows = E.Candidates(snap, 11, { search = "rav" })
    CHECK(#rows == 1 and rows[1].name == "Bravo", "D: search matches a name substring, case-insensitively")
    rows = E.Candidates(snap, 11, { hidden = { [b.key] = true } })
    CHECK(#rows == 2, "D: a hidden item is dropped from the list")
    rows = E.Candidates(snap, 11, { hidden = { [b.key] = true }, showHidden = true })
    CHECK(#rows == 3, "D: showHidden brings it back")
    local hiddenRow
    for i = 1, #rows do if rows[i].key == b.key then hiddenRow = rows[i] end end
    CHECK(hiddenRow and hiddenRow.hidden == true, "D: a revealed hidden row is marked hidden")

    -- The scratch is reused per call, so a shorter list must not inherit a tail.
    local short = E.Candidates(Snap{ inventory = { a } }, 11)
    CHECK(#short == 1, "D: a shorter flyout does not inherit rows from a longer one", #short)
end

do
    -- Off-hand rules.
    local snap = Snap{ inventory = {
        Bag(Copy(sword), 1, 1), Bag(Copy(shield), 1, 2),
        Bag(Copy(holdable), 1, 3), Bag(Copy(offhander), 1, 4),
    } }
    local names = {}
    local rows = E.Candidates(snap, 17)
    for i = 1, #rows do names[rows[i].name] = true end
    CHECK(names["Sword"] == nil, "D: a one-hand weapon is not offered off-hand without dual wield")
    CHECK(names["Shield"] and names["Tome"], "D: shields and holdables are always offered off-hand")
    CHECK(names["Off-hander"], "D: an off-hand-only weapon is offered regardless of dual wield")

    snap.canDualWield = true
    names = {}
    rows = E.Candidates(snap, 17)
    for i = 1, #rows do names[rows[i].name] = true end
    CHECK(names["Sword"] == true, "D: dual wield makes a one-hand weapon a legal off-hand")

    local mh = E.Candidates(Snap{ inventory = { Bag(Copy(sword), 1, 1), Bag(Copy(twoHander), 1, 2) } }, 16)
    CHECK(#mh == 2, "D: both one-hand and two-hand weapons reach the main hand")
end

do
    -- Slot 18 has three faces.
    local inv = { Bag(Copy(bow), 1, 1), Bag(Copy(libram), 1, 2), Bag(Copy(idol), 1, 3) }
    local hunter = Snap{ playerClass = "HUNTER", inventory = inv }
    local rows = E.Candidates(hunter, 18)
    CHECK(#rows == 1 and rows[1].name == "Bow", "D: a hunter's ranged slot offers bows and not relics")

    local paladin = Snap{ playerClass = "PALADIN", hasRelicSlot = true, inventory = inv }
    rows = E.Candidates(paladin, 18)
    CHECK(#rows == 1 and rows[1].name == "Libram", "D: a relic slot offers only that class's relics")

    local druid = Snap{ playerClass = "DRUID", hasRelicSlot = true, inventory = inv }
    rows = E.Candidates(druid, 18)
    CHECK(#rows == 1 and rows[1].name == "Idol", "D: a druid is offered idols, never librams")

    local unknownRelic = Snap{ playerClass = "WARRIOR", hasRelicSlot = true, inventory = inv }
    rows = E.Candidates(unknownRelic, 18)
    CHECK(#rows == 2, "D: a relic slot with no known subclass offers every relic rather than none")
end

do
    -- Usability marks, never filters.
    local snap = Snap{ playerClass = "MAGE", inventory = {
        Bag(Copy(headPlate), 1, 1), Bag(Copy(headCloth), 1, 2),
    } }
    local rows = E.Candidates(snap, 1)
    CHECK(#rows == 2, "D: an unusable item is still listed — hiding it would be an opinion")
    local byName = {}
    for i = 1, #rows do byName[rows[i].name] = rows[i] end
    CHECK(byName["Plate Helm"].usable == false, "D: plate is marked unusable for a mage")
    CHECK(byName["Cloth Hood"].usable == true, "D: cloth is usable by a mage")
    CHECK(E.Candidates(Snap{ inventory = { Bag(Copy(cloak), 1, 1) } }, 15)[1].usable == true,
        "D: a miscellaneous-subclass armour piece is never dimmed")
end

do
    -- Ammo is outside the model entirely.
    local snap = Snap{
        equipped = { [18] = bow },
        inventory = { Bag(Copy(arrows), 1, 1), Bag(Copy(bow), 1, 2) },
    }
    CHECK(#E.Candidates(snap, 0) == 0, "D: the ammo slot has no candidate list")
    local rows = E.Candidates(snap, 18)
    for i = 1, #rows do
        CHECK(rows[i].equipLoc ~= "INVTYPE_AMMO", "D: ammo never appears in a candidate list")
    end
    CHECK(#rows == 1, "D: only the bag bow is offered for the ranged slot", #rows)
    CHECK(#E.Candidates(snap, 1) == 0, "D: ammo does not leak into an unrelated slot's list")
    CHECK(#E.Candidates(nil, 1) == 0, "D: a nil snapshot yields an empty list, not an error")
end

-- ===========================================================================
-- E: the planner — refusals first, then order
-- ===========================================================================

do
    -- Missing: refuse, with zero actions.
    local snap = Snap{ equipped = { [1] = headPlate } }
    local plan = E.PlanSet(Set{ head = headPlate2 }, snap)
    CHECK(plan.ok == false, "E: a set needing a missing item does not run")
    CHECK(plan.verdict == "BLOCKED", "E: a missing item is a BLOCKED verdict")
    CHECK(#plan.actions == 0, "E: a refused plan carries ZERO actions, never a partial list")
    local reason = ReasonWith(plan, "MISSING")
    CHECK(reason ~= nil, "E: the refusal names MISSING")
    CHECK(reason and reason.slotKey == "head", "E: the refusal names the slot")
    CHECK(reason and reason.text:find("Better Helm", 1, true) ~= nil,
        "E: the refusal names the item the player must find")
    CHECK(ReasonWith(plan, "IN_BANK") == nil, "E: a genuinely absent item is not called banked")
end

do
    -- In the bank, away from the bank: a different answer, and the headline one.
    local banked = Bank(Copy(headPlate2), -1, 3)
    local snap = Snap{ equipped = { [1] = headPlate }, inventory = { banked } }
    local plan = E.PlanSet(Set{ head = headPlate2 }, snap)
    CHECK(plan.ok == false and #plan.actions == 0, "E: a banked item blocks the plan before it mutates")
    CHECK(ReasonWith(plan, "IN_BANK") ~= nil, "E: the refusal says IN_BANK")
    CHECK(ReasonWith(plan, "MISSING") == nil,
        "E: an item in the bank is NEVER reported as missing — the product's headline distinction")
    CHECK(plan.deferred[1] == "head", "E: a banked slot is deferred, because there is a later")

    -- At the bank, it becomes a two-stage operation.
    snap.atBank = true
    plan = E.PlanSet(Set{ head = headPlate2 }, snap)
    CHECK(plan.ok == true, "E: standing at the bank, the same set can run")
    CHECK(#plan.actions == 1 and plan.actions[1].op == "WITHDRAW",
        "E: bank to body is a withdrawal first, never a direct equip")
    CHECK(plan.actions[1].invSlot == 1, "E: even a withdrawal records where the item is destined")
    CHECK(plan.needFree == 1, "E: a withdrawal needs a bag slot to land in", plan.needFree)
end

do
    -- Ignored means untouched, in the plan as well as the diff.
    local snap = Snap{ equipped = { [1] = headPlate, [5] = chestPlate, [11] = ringA } }
    local set = Set{ head = headPlate, chest = "IGNORED", finger1 = "EMPTY" }
    local plan = E.PlanSet(set, snap)
    CHECK(plan.ok == true, "E: the plan runs")
    CHECK(CountOp(plan, "MOVE_TO_BAG") == 1, "E: exactly one slot is stripped")
    CHECK(ActionFor(plan, "MOVE_TO_BAG", 5) == nil,
        "E: an IGNORED slot is never stripped — this is the invariant")
    CHECK(ActionFor(plan, "MOVE_TO_BAG", 11) ~= nil, "E: an EMPTY slot IS stripped")
    CHECK(ActionFor(plan, "EQUIP_FROM_BAG", 5) == nil, "E: an IGNORED slot is never equipped into")
    for i = 1, #plan.actions do
        CHECK(plan.actions[i].invSlot ~= 5, "E: no action of any kind touches the ignored slot")
    end
    CHECK(EveryActionHasDestination(plan), "E: every emitted action carries an explicit destination")
end

do
    -- The ring exchange. Two bag round-trips here would drop an item.
    local snap = Snap{ equipped = { [11] = ringA, [12] = ringB } }
    local plan = E.PlanSet(Set{ finger1 = ringB, finger2 = ringA }, snap)
    CHECK(plan.ok == true, "E: a ring exchange is runnable")
    CHECK(#plan.actions == 1, "E: a mutual exchange collapses to ONE action", #plan.actions)
    CHECK(plan.actions[1].op == "SWAP_EQUIPPED", "E: the exchange is a SWAP_EQUIPPED")
    CHECK(CountOp(plan, "EQUIP_FROM_BAG") == 0, "E: an exchange never round-trips through a bag")
    CHECK(plan.needFree == 0, "E: a cross-slot exchange costs no bag space")
    local a = plan.actions[1]
    CHECK((a.fromSlot == 11 and a.toSlot == 12) or (a.fromSlot == 12 and a.toSlot == 11),
        "E: the swap names both finger slots")
    CHECK(a.invSlot ~= nil, "E: a swap still records an explicit destination slot")
end

do
    -- One-way move: an item worn elsewhere, wanted here.
    local snap = Snap{ equipped = { [12] = ringB } }
    local plan = E.PlanSet(Set{ finger1 = ringB }, snap)
    CHECK(#plan.actions == 1 and plan.actions[1].op == "SWAP_EQUIPPED",
        "E: moving a worn item to another slot is a swap, not a bag trip")
    CHECK(plan.actions[1].fromSlot == 12 and plan.actions[1].toSlot == 11,
        "E: the one-way move names source and destination")
end

do
    -- The two-hander, per the revised rule: it goes on FIRST and the client
    -- bags the off-hand itself.
    local snap = Snap{
        equipped = { [16] = sword, [17] = shield, [1] = headPlate },
        inventory = { Bag(Copy(twoHander), 1, 1), Bag(Copy(headPlate2), 1, 2) },
        freeBagSlots = 3,
    }
    local plan = E.PlanSet(Set{ mainhand = twoHander, head = headPlate2 }, snap)
    CHECK(plan.ok == true, "E: equipping a two-hander over a weapon and shield is runnable")
    CHECK(plan.actions[1].op == "EQUIP_FROM_BAG" and plan.actions[1].invSlot == 16,
        "E: the two-hander is action #1, ahead of everything else in the plan")
    CHECK(ActionFor(plan, "MOVE_TO_BAG", 17) == nil,
        "E: the off-hand is NOT explicitly unequipped — that is the thing that broke")
    CHECK(CountOp(plan, "MOVE_TO_BAG") == 0, "E: a two-hander swap emits no removals at all")
    CHECK(plan.needFree == 1, "E: exactly one bag slot is reserved for the displaced off-hand", plan.needFree)

    snap.freeBagSlots = 0
    plan = E.PlanSet(Set{ mainhand = twoHander, head = headPlate2 }, snap)
    CHECK(plan.ok == false and #plan.actions == 0, "E: with no room, the two-hander swap refuses outright")
    CHECK(ReasonWith(plan, "BAGS_FULL") ~= nil, "E: the refusal is BAGS_FULL")
    CHECK(plan.needFree == 1, "E: needFree survives the refusal so the UI can say how much room to make")

    -- Nothing in the off-hand: nothing to displace.
    local clear = Snap{
        equipped = { [16] = sword },
        inventory = { Bag(Copy(twoHander), 1, 1) },
        freeBagSlots = 0,
    }
    plan = E.PlanSet(Set{ mainhand = twoHander }, clear)
    CHECK(plan.ok == true and plan.needFree == 0,
        "E: with a bare off-hand a two-hander needs no free bag slot")
end

do
    -- A two-hander plus an off-hand entry is an impossible set, and we say so.
    local snap = Snap{
        equipped = { [16] = sword, [17] = shield },
        inventory = { Bag(Copy(twoHander), 1, 1), Bag(Copy(holdable), 1, 2) },
    }
    local plan = E.PlanSet(Set{ mainhand = twoHander, offhand = holdable }, snap)
    CHECK(plan.ok == false and #plan.actions == 0, "E: a two-hander plus an off-hand refuses")
    local reason = ReasonWith(plan, "NOT_USABLE")
    CHECK(reason ~= nil and reason.slotKey == "offhand",
        "E: the refusal points at the off-hand entry that cannot be honoured")

    -- Off-hand EMPTY is the normal captured shape and must still work.
    local ok = E.PlanSet(Set{ mainhand = twoHander, offhand = "EMPTY" }, snap)
    CHECK(ok.ok == true, "E: a two-hander with an explicitly EMPTY off-hand is a normal set")
    CHECK(ActionFor(ok, "MOVE_TO_BAG", 17) == nil,
        "E: the redundant off-hand strip is suppressed when the two-hander already displaced it")
    CHECK(ok.needFree == 1,
        "E: the displaced off-hand is counted once, not twice", ok.needFree)
    CHECK(ok.actions[1].invSlot == 16, "E: the two-hander is still action #1")
end

do
    -- Legality refusals.
    local snap = Snap{ playerClass = "PALADIN", hasRelicSlot = true,
        inventory = { Bag(Copy(idol), 1, 1) } }
    local plan = E.PlanSet(Set{ ranged = idol }, snap)
    CHECK(plan.ok == false, "E: a paladin cannot equip an idol")
    CHECK(ReasonWith(plan, "NOT_USABLE") ~= nil,
        "E: an item that exists but cannot go there says NOT_USABLE, not MISSING")
    CHECK(ReasonWith(plan, "MISSING") == nil, "E: a wrong-slot item is not called missing")

    local noDW = Snap{ inventory = { Bag(Copy(sword), 1, 1) } }
    plan = E.PlanSet(Set{ offhand = sword }, noDW)
    CHECK(ReasonWith(plan, "NOT_USABLE") ~= nil,
        "E: an off-hand sword without dual wield is refused as unusable")
    noDW.canDualWield = true
    plan = E.PlanSet(Set{ offhand = sword }, noDW)
    CHECK(plan.ok == true, "E: with dual wield the same set runs")
end

do
    -- The world gates. Every one is temporary, so every slot is deferred.
    local base = { equipped = { [1] = headPlate }, inventory = { Bag(Copy(headPlate2), 1, 1) } }
    local function Gate(field, code)
        local snap = Snap{ equipped = base.equipped, inventory = base.inventory }
        snap[field] = true
        local plan = E.PlanSet(Set{ head = headPlate2 }, snap)
        CHECK(plan.ok == false and #plan.actions == 0,
            "E: " .. field .. " refuses the whole plan before anything moves")
        CHECK(ReasonWith(plan, code) ~= nil, "E: " .. field .. " reports " .. code)
        CHECK(plan.deferred[1] == "head",
            "E: " .. field .. " defers the slot rather than failing it")
    end
    Gate("inCombat", "IN_COMBAT")
    Gate("casting", "CASTING")
    Gate("dead", "DEAD")
    Gate("merchant", "MERCHANT_OPEN")
    Gate("cursorBusy", "CURSOR_BUSY")
end

do
    -- Nothing to do is not a failure.
    local snap = Snap{ equipped = { [1] = headPlate } }
    local plan = E.PlanSet(Set{ head = headPlate }, snap)
    CHECK(plan.ok == false, "E: a set you already wear does not start a run")
    CHECK(plan.verdict == "OK", "E: ...but its verdict is OK, because nothing is wrong")
    CHECK(ReasonWith(plan, "NOTHING_TO_DO") ~= nil, "E: it says NOTHING_TO_DO")
    CHECK(#plan.actions == 0, "E: and emits no actions")

    local empty = E.PlanSet(E.NewSet("Blank"), snap)
    CHECK(empty.ok == false and ReasonWith(empty, "NOTHING_TO_DO") ~= nil,
        "E: a set that speaks for no slot does nothing")
end

do
    -- Locked items block pre-flight rather than being discovered mid-run.
    local locked = Bag(Copy(headPlate2), 1, 1)
    locked.locked = true
    local snap = Snap{ equipped = { [1] = headPlate }, inventory = { locked } }
    local plan = E.PlanSet(Set{ head = headPlate2 }, snap)
    CHECK(plan.ok == false and ReasonWith(plan, "LOCKED") ~= nil,
        "E: an item in flight blocks the plan")
    CHECK(plan.deferred[1] == "head", "E: a locked item is deferred, since locks clear")
end

do
    -- Ammo cannot enter a plan even if a saved file names it.
    local snap = Snap{ inventory = { Bag(Copy(arrows), 1, 1) } }
    local set = E.NewSet("Ammo")
    set.entries.ammo = Entry(arrows)
    local plan = E.PlanSet(set, snap)
    CHECK(#plan.actions == 0 and ReasonWith(plan, "NOTHING_TO_DO") ~= nil,
        "E: an ammo entry in a saved set is inert — slot 0 is outside the model")
end

do
    -- PlanSingle, the flyout's verb.
    local bagRing = Bag(Copy(ringB), 2, 4)
    local snap = Snap{ equipped = { [11] = ringA, [12] = trinketA }, inventory = { bagRing } }

    local plan = E.PlanSingle(11, bagRing, snap)
    CHECK(plan.ok and #plan.actions == 1 and plan.actions[1].op == "EQUIP_FROM_BAG",
        "E: picking a bag item from the flyout is one equip")
    CHECK(plan.actions[1].bag == 2 and plan.actions[1].slot == 4,
        "E: the equip points at the exact square the player clicked")
    CHECK(plan.actions[1].invSlot == 11, "E: and at the exact slot, never letting the client choose")

    local rows = E.Candidates(Snap{ equipped = { [11] = ringA, [12] = Copy(ringB) } }, 11)
    local wrapped = rows[1]
    local plan2 = E.PlanSingle(11, wrapped, Snap{ equipped = { [11] = ringA, [12] = wrapped.source } })
    CHECK(plan2.actions[1].op == "SWAP_EQUIPPED", "E: choosing an equipped candidate is a swap")

    local strip = E.PlanSingle(11, nil, snap)
    CHECK(strip.ok and strip.actions[1].op == "MOVE_TO_BAG" and strip.actions[1].invSlot == 11,
        "E: choosing nothing means put it in my bags")
    CHECK(strip.needFree == 1, "E: putting an item away needs a bag slot")

    local bare = E.PlanSingle(7, nil, snap)
    CHECK(bare.ok == false and ReasonWith(bare, "NOTHING_TO_DO") ~= nil,
        "E: emptying an already-bare slot is nothing to do")

    local bankRing = Bank(Copy(trinketB), -1, 2)
    local away = E.PlanSingle(13, bankRing, Snap{ inventory = { bankRing } })
    CHECK(away.ok == false and ReasonWith(away, "IN_BANK") ~= nil,
        "E: clicking a banked item away from the bank explains itself")

    local wrongSlot = E.PlanSingle(11, Bag(Copy(headPlate), 1, 1), snap)
    CHECK(wrongSlot.ok == false and ReasonWith(wrongSlot, "NOT_USABLE") ~= nil,
        "E: a helm cannot be forced into a finger slot")
end

-- ===========================================================================
-- F: the allocation ledger — identical items are told apart by LOCATION
-- ===========================================================================

do
    local copy1 = Bag(Copy(ringA), 1, 1)
    local copy2 = Bag(Copy(ringA), 3, 7)
    CHECK(copy1.key == copy2.key, "F: two identical unenchanted rings share one key, deliberately")

    local snap = Snap{ inventory = { copy1, copy2 } }
    local plan = E.PlanSet(Set{ finger1 = ringA, finger2 = ringA }, snap)
    CHECK(plan.ok == true, "F: two copies satisfy two slots")
    CHECK(#plan.actions == 2, "F: two equips are planned", #plan.actions)
    local a, b = plan.actions[1], plan.actions[2]
    CHECK(not (a.bag == b.bag and a.slot == b.slot),
        "F: the two equips point at two DIFFERENT physical squares")
    CHECK(a.invSlot ~= b.invSlot, "F: and at two different destination slots")

    -- One copy, two slots: refuse rather than plan both onto one ring.
    local onlyOne = Snap{ inventory = { Bag(Copy(ringA), 1, 1) } }
    local plan2 = E.PlanSet(Set{ finger1 = ringA, finger2 = ringA }, onlyOne)
    CHECK(plan2.ok == false and #plan2.actions == 0,
        "F: one ring cannot fill two fingers, and the plan refuses instead of half-applying")
    local reason = ReasonWith(plan2, "MISSING")
    CHECK(reason ~= nil and reason.slotKey == "finger2",
        "F: the refusal names the second finger precisely")

    -- One worn plus one in a bag: the worn one stays put, the bagged one moves.
    local mixed = Snap{ equipped = { [11] = Copy(ringA) }, inventory = { Bag(Copy(ringA), 4, 2) } }
    local plan3 = E.PlanSet(Set{ finger1 = ringA, finger2 = ringA }, mixed)
    CHECK(plan3.ok == true and #plan3.actions == 1,
        "F: the correctly-worn copy is left alone and only the second is equipped")
    CHECK(plan3.actions[1].invSlot == 12, "F: the bagged copy goes to the empty finger")
end

-- ===========================================================================
-- F2: unique-equipped — the complete three-case TBC model
-- ===========================================================================

do
    CHECK(D.LimitCategoryFor(29276) == 495, "F2: a Violet Signet is in category 495")
    CHECK(D.LimitCategoryFor(29294) == 497, "F2: a Band of Eternity is in category 497")
    CHECK(D.LimitCategoryFor(21196) == 475, "F2: a Bronze Dragonflight signet is in category 475")
    CHECK(D.LimitCategoryFor(30000) == nil, "F2: an ordinary ring is in no category")

    -- Case 1: the same unique-equipped item twice, even with two copies to hand.
    local snap = Snap{ inventory = { Bag(Copy(ringUnique), 1, 1), Bag(Copy(ringUnique), 1, 2) } }
    local plan = E.PlanSet(Set{ finger1 = ringUnique, finger2 = ringUnique }, snap)
    CHECK(plan.ok == false and #plan.actions == 0,
        "F2: a unique-equipped ring in both fingers refuses even when two copies exist")
    CHECK(ReasonWith(plan, "UNIQUE_CONFLICT") ~= nil, "F2: it reports UNIQUE_CONFLICT")
    CHECK(ReasonWith(plan, "UNIQUE_CONFLICT").text:find("unique%-equipped") ~= nil,
        "F2: and explains why in words")

    -- Case 2: two different members of one family.
    local family = Snap{ inventory = { Bag(Copy(violet1), 1, 1), Bag(Copy(violet2), 1, 2) } }
    plan = E.PlanSet(Set{ finger1 = violet1, finger2 = violet2 }, family)
    CHECK(plan.ok == false and #plan.actions == 0, "F2: two Violet Signets cannot be worn together")
    local reason = ReasonWith(plan, "UNIQUE_CONFLICT")
    CHECK(reason ~= nil and reason.text:find("Violet Signet", 1, true) ~= nil,
        "F2: the refusal names the family, which no API call is needed to know")

    -- Negative: two rings from two DIFFERENT families are fine.
    local mixed = Snap{ inventory = { Bag(Copy(violet1), 1, 1), Bag(Copy(eternity), 1, 2) } }
    plan = E.PlanSet(Set{ finger1 = violet1, finger2 = eternity }, mixed)
    CHECK(plan.ok == true, "F2: a Violet Signet and a Band of Eternity are two families, not one")
    CHECK(ReasonWith(plan, "UNIQUE_CONFLICT") == nil, "F2: and produce no conflict")

    local threeWay = Snap{ inventory = { Bag(Copy(bronze), 1, 1), Bag(Copy(eternity), 1, 2) } }
    plan = E.PlanSet(Set{ finger1 = bronze, finger2 = eternity }, threeWay)
    CHECK(plan.ok == true, "F2: bronze and eternity are likewise independent")

    -- Case 3: a shared gem — but ONLY one the host has proven unique-equipped.
    local gemSet = Set{ head = gemHead, chest = gemChest }
    local function GemSnap(uniqueGems)
        return Snap{
            uniqueGems = uniqueGems,
            inventory = { Bag(Copy(gemHead), 1, 1), Bag(Copy(gemChest), 1, 2) },
        }
    end

    plan = E.PlanSet(gemSet, GemSnap({ [32409] = true }))
    CHECK(plan.ok == false and #plan.actions == 0,
        "F2: two pieces cut with the same PROVEN unique gem are refused before the server does it")
    reason = ReasonWith(plan, "UNIQUE_CONFLICT")
    CHECK(reason ~= nil and reason.text:find("gem", 1, true) ~= nil, "F2: the reason names the gem")
    plan = E.PlanSet(gemSet, GemSnap({ ["32409"] = true }))
    CHECK(plan.ok == false, "F2: a string-keyed uniqueGems table works too")

    -- THE negatives. Gemming several pieces with the same Living Ruby is how
    -- people gem in TBC; an unfiltered "repeated gem id is a conflict" rule
    -- refuses a large fraction of perfectly legal sets, which is worse than the
    -- rare server rejection it prevents. Unknown must mean "let it run".
    plan = E.PlanSet(gemSet, GemSnap(nil))
    CHECK(plan.ok == true,
        "F2: with no uniqueGems table at all, a shared gem is NOT a conflict")
    CHECK(ReasonWith(plan, "UNIQUE_CONFLICT") == nil, "F2: and no conflict is reported")
    plan = E.PlanSet(gemSet, GemSnap({}))
    CHECK(plan.ok == true, "F2: an empty uniqueGems table flags nothing")
    plan = E.PlanSet(gemSet, GemSnap({ [24028] = true }))
    CHECK(plan.ok == true,
        "F2: a gem absent from uniqueGems is an ordinary gem, and two pieces may share it")

    -- The other obvious way to write this bug: two UNGEMMED items share four
    -- gem ids of zero and must not conflict, whatever the table says.
    local bare = Snap{ uniqueGems = { [0] = true, ["0"] = true },
        inventory = { Bag(Copy(headPlate), 1, 1), Bag(Copy(chestPlate), 1, 2) } }
    plan = E.PlanSet(Set{ head = headPlate, chest = chestPlate }, bare)
    CHECK(plan.ok == true, "F2: two ungemmed items never conflict on an empty socket")
    CHECK(ReasonWith(plan, "UNIQUE_CONFLICT") == nil, "F2: no phantom gem conflict")

    local oneGem = Snap{ uniqueGems = { [32409] = true },
        inventory = { Bag(Copy(gemHead), 1, 1), Bag(Copy(chestPlate), 1, 2) } }
    plan = E.PlanSet(Set{ head = gemHead, chest = chestPlate }, oneGem)
    CHECK(plan.ok == true, "F2: one gemmed and one bare piece do not conflict")

    local otherGem = Copy(gemChest, { g1 = 24028 })
    local differentGems = Snap{ uniqueGems = { [32409] = true, [24028] = true },
        inventory = { Bag(Copy(gemHead), 1, 1), Bag(otherGem, 1, 2) } }
    plan = E.PlanSet(Set{ head = gemHead, chest = otherGem }, differentGems)
    CHECK(plan.ok == true,
        "F2: two DIFFERENT unique gems in the two pieces are fine — the ids must match")

    CHECK(E.Conflicts(violet1, violet1) == false,
        "F2: an item never conflicts with itself, or every plan would refuse")
    CHECK(E.Conflicts(gemHead, gemChest) == false,
        "F2: Conflicts called with no gem table declines to flag a shared gem")
    CHECK(E.Conflicts(gemHead, gemChest, { [32409] = true }) == true,
        "F2: and flags it once the gem is proven unique")
    CHECK(E.Conflicts(violet1, violet2, nil) == true,
        "F2: the family rule needs no gem table — it is read from Data")
end

do
    -- A conflict against an IGNORED slot cannot be repaired, because the one
    -- repair is forbidden. Refuse.
    local snap = Snap{ equipped = { [11] = violet1 }, inventory = { Bag(Copy(violet2), 1, 1) } }
    local plan = E.PlanSet(Set{ finger2 = violet2 }, snap)
    CHECK(plan.ok == false and ReasonWith(plan, "UNIQUE_CONFLICT") ~= nil,
        "F2: a conflict with an ignored slot's worn item is unresolvable and refuses")
end

do
    -- The pre-strip: a worn conflicting item comes off BEFORE the new one goes
    -- on, even though its own slot is about to be re-equipped anyway.
    local snap = Snap{
        equipped = { [11] = violet1 },
        inventory = { Bag(Copy(ringA), 1, 1), Bag(Copy(violet2), 1, 2) },
        freeBagSlots = 4,
    }
    local plan = E.PlanSet(Set{ finger1 = ringA, finger2 = violet2 }, snap)
    CHECK(plan.ok == true, "F2: the conflict is resolvable because finger1 is changing anyway")
    CHECK(plan.actions[1].op == "MOVE_TO_BAG" and plan.actions[1].invSlot == 11,
        "F2: the conflicting worn ring is lifted out FIRST")
    local equipIndex
    for i = 1, #plan.actions do
        if plan.actions[i].op == "EQUIP_FROM_BAG" and plan.actions[i].invSlot == 12 then
            equipIndex = i
        end
    end
    CHECK(equipIndex ~= nil and equipIndex > 1,
        "F2: the new ring goes on only after the conflict is cleared")
    CHECK(plan.needFree == 1, "F2: lifting the conflicting item out costs one bag slot", plan.needFree)
end

-- ===========================================================================
-- G: free bag slots, by formula
-- ===========================================================================

do
    -- Five replacements out of bags into occupied slots: net ZERO. Counting
    -- removals would say five and refuse a swap that works perfectly.
    local snap = Snap{
        equipped = { [1] = headPlate, [5] = chestPlate, [11] = ringA, [13] = trinketA, [15] = cloak },
        inventory = {
            Bag(Copy(headPlate2), 1, 1), Bag(Copy(robe), 1, 2), Bag(Copy(ringB), 1, 3),
            Bag(Copy(trinketB), 1, 4), Bag(Copy(cloak2), 1, 5),
        },
        freeBagSlots = 0,
    }
    local plan = E.PlanSet(Set{
        head = headPlate2, chest = robe, finger1 = ringB, trinket1 = trinketB,
        back = cloak2,
    }, snap)
    CHECK(plan.ok == true, "G: five in-place replacements run with a completely full bag")
    CHECK(plan.needFree == 0, "G: a bag-to-body swap into an occupied slot is net zero", plan.needFree)
    CHECK(#plan.actions == 5, "G: and are five equips", #plan.actions)
end

do
    -- Only real removals cost anything.
    local snap = Snap{
        equipped = { [1] = headPlate, [5] = chestPlate, [11] = ringA, [13] = trinketA },
        inventory = { Bag(Copy(headPlate2), 1, 1) },
        freeBagSlots = 5,
    }
    local plan = E.PlanSet(Set{
        head = headPlate2, chest = "EMPTY", finger1 = "EMPTY", trinket1 = "IGNORED",
    }, snap)
    CHECK(plan.needFree == 2, "G: two strips need two bag slots", plan.needFree)
    CHECK(CountOp(plan, "MOVE_TO_BAG") == 2, "G: and two removal actions")
    CHECK(ActionFor(plan, "MOVE_TO_BAG", 13) == nil, "G: the ignored trinket is not among them")

    snap.freeBagSlots = 1
    plan = E.PlanSet(Set{ head = headPlate2, chest = "EMPTY", finger1 = "EMPTY" }, snap)
    CHECK(plan.ok == false and #plan.actions == 0, "G: one free slot is not enough for two strips")
    local reason = ReasonWith(plan, "BAGS_FULL")
    CHECK(reason ~= nil, "G: it says BAGS_FULL")
    CHECK(reason and reason.text:find("2 free bag slots", 1, true) ~= nil,
        "G: and says exactly how many are needed")
    CHECK(plan.needFree == 2, "G: needFree survives the refusal")

    -- A slot the set wants empty that is ALREADY empty costs nothing.
    local bare = Snap{ equipped = {}, freeBagSlots = 0 }
    local none = E.PlanSet(Set{ chest = "EMPTY", legs = "EMPTY" }, bare)
    CHECK(none.needFree == 0, "G: emptying an already-bare slot costs no room")
end

do
    -- Withdrawals each need a landing square.
    local snap = Snap{
        atBank = true, freeBagSlots = 1,
        inventory = { Bank(Copy(headPlate2), -1, 1), Bank(Copy(chestPlate), -1, 2) },
    }
    local plan = E.PlanSet(Set{ head = headPlate2, chest = chestPlate }, snap)
    CHECK(plan.needFree == 2, "G: two withdrawals need two bag slots", plan.needFree)
    CHECK(plan.ok == false and ReasonWith(plan, "BAGS_FULL") ~= nil,
        "G: one free slot refuses two withdrawals before anything leaves the bank")
    snap.freeBagSlots = 2
    plan = E.PlanSet(Set{ head = headPlate2, chest = chestPlate }, snap)
    CHECK(plan.ok == true and CountOp(plan, "WITHDRAW") == 2, "G: with room, both are withdrawn")
end

do
    -- Free-slot coordinates, when the host offers them, are never reused.
    local snap = Snap{
        equipped = { [1] = headPlate, [5] = chestPlate },
        freeSlots = { { bag = 1, slot = 9 }, { bag = 2, slot = 3 } },
        freeBagSlots = 2,
    }
    local plan = E.PlanSet(Set{ head = "EMPTY", chest = "EMPTY" }, snap)
    local a, b = plan.actions[1], plan.actions[2]
    CHECK(a.bag ~= nil and b.bag ~= nil, "G: destinations are filled in when the host supplies them")
    CHECK(not (a.bag == b.bag and a.slot == b.slot),
        "G: two removals never target the same empty square")

    local noHint = Snap{ equipped = { [1] = headPlate }, freeBagSlots = 2 }
    local p2 = E.PlanSet(Set{ head = "EMPTY" }, noHint)
    CHECK(p2.ok == true and p2.actions[1].bag == nil,
        "G: without a free-slot list the host picks the square at execution time")
end

-- ===========================================================================
-- H: the run state machine
-- ===========================================================================

do
    local snap = Snap{
        equipped = { [1] = headPlate },
        inventory = { Bag(Copy(headPlate2), 1, 1) },
    }
    local plan = E.PlanSet(Set{ head = headPlate2 }, snap)
    local run = E.NewRun(plan)
    CHECK(E.RunStatus(run) == "RUNNING", "H: a fresh run with work to do is RUNNING")
    CHECK(#run.actions == #plan.actions, "H: the run copies the plan's actions")
    run.actions[1] = nil
    CHECK(#plan.actions == 1, "H: and copies them, so a run cannot rewrite its own plan")

    local empty = E.NewRun(E.PlanSet(Set{ head = headPlate }, snap))
    CHECK(E.RunStatus(empty) == "DONE", "H: a run with no actions is DONE immediately")
    CHECK(select(2, E.NextAction(empty, snap)) == "DONE", "H: and says so when asked for work")
    CHECK(E.NextAction(nil, snap) == nil, "H: asking a nil run for work is not an error")
end

do
    -- The cursor is busy: wait, do not advance.
    local snap = Snap{
        now = 100, cursorBusy = true,
        equipped = { [1] = headPlate },
        inventory = { Bag(Copy(headPlate2), 1, 1) },
    }
    local plan = E.PlanSet(Set{ head = headPlate2 }, Snap{
        equipped = { [1] = headPlate }, inventory = { Bag(Copy(headPlate2), 1, 1) },
    })
    local run = E.NewRun(plan)
    local action, wait = E.NextAction(run, snap)
    CHECK(action == nil and wait == "LOCKED", "H: a busy cursor yields nil and LOCKED")
    CHECK(E.RunStatus(run) == "WAITING", "H: and the run reads as WAITING")
    CHECK(run.index == 1, "H: waiting never advances the queue")

    -- Five seconds with no progress is a TIMEOUT, not a permanent WAITING.
    snap.now = 104.9
    CHECK(select(2, E.NextAction(run, snap)) == "LOCKED", "H: just under five seconds still waits")
    snap.now = 105
    local a2, w2 = E.NextAction(run, snap)
    CHECK(a2 == nil and w2 == "TIMEOUT", "H: five seconds without progress is a TIMEOUT")
    CHECK(E.RunStatus(run) == "TIMEOUT", "H: the run records the timeout")
    CHECK(select(2, E.NextAction(run, snap)) == "TIMEOUT", "H: a timed-out run stays timed out")
    CHECK(#E.RunSummary(run).messages > 0, "H: and the summary says what happened")
end

do
    -- THE wedge case. ITEM_LOCK_CHANGED does not fire for empty slots, so a run
    -- made entirely of equips into bare slots gets no lock event at all and must
    -- still complete. Nothing here ever reports a lock.
    local snap = Snap{
        equipped = {},
        inventory = {
            Bag(Copy(headPlate), 1, 1), Bag(Copy(chestPlate), 1, 2), Bag(Copy(ringA), 1, 3),
        },
    }
    local plan = E.PlanSet(Set{ head = headPlate, chest = chestPlate, finger1 = ringA }, snap)
    CHECK(plan.ok and #plan.actions == 3, "H: three equips into three bare slots")
    local run = E.NewRun(plan)
    local guard, sawWait = 0, false
    while E.RunStatus(run) == "RUNNING" or E.RunStatus(run) == "WAITING" do
        guard = guard + 1
        if guard > 20 then break end
        snap.now = snap.now + 0.1
        local action, wait = E.NextAction(run, snap)
        if wait then sawWait = true; break end
        E.ReportResult(run, action, true)
    end
    CHECK(sawWait == false, "H: a run into empty slots never has to wait for a lock event")
    CHECK(E.RunStatus(run) == "DONE", "H: and it completes", E.RunStatus(run))
    local summary = E.RunSummary(run)
    CHECK(summary.equipped == 3 and summary.failed == 0, "H: three equips, no failures")
    CHECK(summary.removed == 0, "H: and nothing was removed")
    CHECK(#summary.messages == 3, "H: one message per completed action")
end

do
    -- A locked source really does hold the queue.
    local bagRow = Bag(Copy(headPlate2), 1, 1)
    local snap = Snap{ equipped = { [1] = headPlate }, inventory = { bagRow } }
    local run = E.NewRun(E.PlanSet(Set{ head = headPlate2 }, snap))
    bagRow.locked = true
    CHECK(select(2, E.NextAction(run, snap)) == "LOCKED", "H: a locked source square waits")
    bagRow.locked = false
    snap.equipped[1] = Copy(headPlate); snap.equipped[1].locked = true
    CHECK(select(2, E.NextAction(run, snap)) == "LOCKED", "H: a locked destination slot waits too")
    snap.equipped[1].locked = false
    CHECK(E.NextAction(run, snap) ~= nil, "H: once both are free the action is handed out")
end

do
    -- Failure handling: transient codes retry, real ones fail and move on.
    local snap = Snap{
        equipped = { [1] = headPlate, [5] = chestPlate },
        inventory = { Bag(Copy(headPlate2), 1, 1), Bag(Copy(robe), 1, 2) },
    }
    local plan = E.PlanSet(Set{ head = headPlate2, chest = robe }, snap)
    local run = E.NewRun(plan)
    local action = E.NextAction(run, snap)
    E.ReportResult(run, action, false, "LOCKED")
    CHECK(run.index == 1, "H: a transient failure re-offers the same action")
    E.ReportResult(run, action, false, "LOCKED")
    E.ReportResult(run, action, false, "LOCKED")
    CHECK(run.index == 1, "H: three retries still hold position")
    E.ReportResult(run, action, false, "LOCKED")
    CHECK(run.index == 2, "H: past the retry ceiling the action is abandoned")
    CHECK(run.failed == 1, "H: and counted as a failure")
    action = E.NextAction(run, snap)
    E.ReportResult(run, action, false, "ERR_CANT_EQUIP_SKILL")
    CHECK(run.failed == 2, "H: a non-transient failure never retries")
    CHECK(E.RunStatus(run) == "FAILED", "H: a run that failed anything ends FAILED")
    local summary = E.RunSummary(run)
    CHECK(summary.failed == 2, "H: the summary counts both failures")
    CHECK(summary.messages[1]:find("ERR_CANT_EQUIP_SKILL", 1, true) ~= nil or
        summary.messages[2]:find("ERR_CANT_EQUIP_SKILL", 1, true) ~= nil,
        "H: and quotes the client's own error code")
end

do
    -- Removals are counted as removals, not equips.
    local snap = Snap{ equipped = { [11] = ringA }, freeBagSlots = 3 }
    local run = E.NewRun(E.PlanSet(Set{ finger1 = "EMPTY" }, snap))
    E.ReportResult(run, E.NextAction(run, snap), true)
    local summary = E.RunSummary(run)
    CHECK(summary.removed == 1 and summary.equipped == 0, "H: a strip counts as removed")
    CHECK(E.RunStatus(run) == "DONE", "H: and finishes the run")
end

do
    -- Multi-pass, driven by re-planning from live state. This is the mechanism,
    -- not clever ordering.
    local banked = Bank(Copy(headPlate2), -1, 5)
    local snap = Snap{ atBank = true, freeBagSlots = 4,
        equipped = { [1] = headPlate }, inventory = { banked } }
    local set = Set{ head = headPlate2 }

    local plan1 = E.PlanSet(set, snap)
    CHECK(plan1.actions[1].op == "WITHDRAW", "H: pass one takes it out of the bank")
    local run = E.NewRun(plan1)
    E.ReportResult(run, E.NextAction(run, snap), true)
    CHECK(E.RunStatus(run) == "DONE", "H: pass one completes")

    -- The world moved. Re-snapshot, re-plan, keep the same run.
    banked.where, banked.bag, banked.slot, banked.stale = "BAGS", 1, 6, nil
    local plan2 = E.PlanSet(set, snap)
    CHECK(plan2.actions[1].op == "EQUIP_FROM_BAG", "H: pass two equips it out of the bag")
    E.ReplanRun(run, plan2)
    CHECK(E.RunStatus(run) == "RUNNING", "H: re-planning restarts the run rather than a new one")
    CHECK(run.index == 1, "H: the queue restarts at the head of the new plan")
    E.ReportResult(run, E.NextAction(run, snap), true)
    CHECK(E.RunStatus(run) == "DONE", "H: the multi-pass run completes")
    local summary = E.RunSummary(run)
    CHECK(summary.passes == 2, "H: and reports how many passes it took", summary.passes)
    CHECK(summary.equipped == 1, "H: counters survive the re-plan")

    snap.equipped[1] = banked
    snap.inventory = {}
    CHECK(E.DiffSet(set, snap).isEquipped == true,
        "H: and afterwards the set really is equipped")

    local finished = E.ReplanRun(E.NewRun(plan2), E.PlanSet(set, snap))
    CHECK(E.RunStatus(finished) == "DONE",
        "H: re-planning against a satisfied world ends the run rather than looping")
end

do
    -- Locks are per slot, so disjoint moves can go in one pass.
    local snap = Snap{
        equipped = { [1] = headPlate, [5] = chestPlate, [11] = ringA },
        freeBagSlots = 5,
    }
    local plan = E.PlanSet(Set{ head = "EMPTY", chest = "EMPTY", finger1 = "EMPTY" }, snap)
    local run = E.NewRun(plan)
    local ready, wait = E.ReadyActions(run, snap)
    CHECK(wait == nil and #ready == 3, "H: three disjoint removals are all ready at once", #ready)

    snap.equipped[1] = Copy(headPlate); snap.equipped[1].locked = true
    ready, wait = E.ReadyActions(run, snap)
    CHECK(#ready == 0 and wait == "LOCKED", "H: a locked head of queue yields nothing rather than reordering")

    snap.equipped[1].locked = false
    snap.cursorBusy = true
    ready, wait = E.ReadyActions(run, snap)
    CHECK(#ready == 0 and wait == "LOCKED", "H: a busy cursor stops the whole batch")
end

do
    -- The world can turn hostile mid-run.
    local snap = Snap{ equipped = { [1] = headPlate }, inventory = { Bag(Copy(headPlate2), 1, 1) } }
    local run = E.NewRun(E.PlanSet(Set{ head = headPlate2 }, snap))
    snap.inCombat = true
    CHECK(select(2, E.NextAction(run, snap)) == "IN_COMBAT", "H: combat pauses a run in flight")
    snap.inCombat, snap.dead = false, true
    CHECK(select(2, E.NextAction(run, snap)) == "DEAD", "H: so does dying")
    snap.dead, snap.merchant = false, true
    CHECK(select(2, E.NextAction(run, snap)) == "MERCHANT_OPEN", "H: so does opening a vendor")
    snap.merchant, snap.casting = false, true
    CHECK(select(2, E.NextAction(run, snap)) == "CASTING", "H: so does casting")
    snap.casting = false
    CHECK(E.NextAction(run, snap) ~= nil, "H: and it resumes when the world calms down")
end

-- ===========================================================================
-- I: stats
-- ===========================================================================

do
    local h = Row{ id = 41001, name = "Stat Helm", equipLoc = "INVTYPE_HEAD", classID = ARMOR,
        subClassID = 4, ilvl = 120, stats = { ITEM_MOD_STAMINA_SHORT = 30, ITEM_MOD_HIT_RATING_SHORT = 12 } }
    local h2 = Row{ id = 41002, name = "Other Helm", equipLoc = "INVTYPE_HEAD", classID = ARMOR,
        subClassID = 4, ilvl = 140, stats = { ITEM_MOD_STAMINA_SHORT = 45, ITEM_MOD_CRIT_RATING_SHORT = 20 } }
    local c = Row{ id = 41003, name = "Stat Chest", equipLoc = "INVTYPE_CHEST", classID = ARMOR,
        subClassID = 4, ilvl = 100, stats = { ITEM_MOD_STAMINA_SHORT = 20 } }

    local snap = Snap{ equipped = { [1] = h, [5] = c }, inventory = { Bag(Copy(h2), 1, 1) } }

    local worn, wornIlvl, wornAvg = E.EquippedStats(snap, {})
    CHECK(worn.ITEM_MOD_STAMINA_SHORT == 50, "I: worn stats add up across slots", worn.ITEM_MOD_STAMINA_SHORT)
    CHECK(wornIlvl == 220 and wornAvg == 110, "I: worn item level totals and averages")

    -- The ignored chest is still going to be on your body, so it counts.
    local setStats, setIlvl = E.SetStats(Set{ head = h2, chest = "IGNORED" }, snap, {})
    CHECK(setStats.ITEM_MOD_STAMINA_SHORT == 65,
        "I: an ignored slot's worn item counts toward the set total, because it stays on",
        setStats.ITEM_MOD_STAMINA_SHORT)
    CHECK(setStats.ITEM_MOD_CRIT_RATING_SHORT == 20, "I: the incoming item's stats are included")
    CHECK(setStats.ITEM_MOD_HIT_RATING_SHORT == nil, "I: the outgoing item's stats are gone")
    CHECK(setIlvl == 240, "I: the set's item level total uses the incoming piece", setIlvl)

    local stripped = E.SetStats(Set{ head = h2, chest = "EMPTY" }, snap, {})
    CHECK(stripped.ITEM_MOD_STAMINA_SHORT == 45, "I: an EMPTY slot contributes nothing")

    local missing = E.SetStats(Set{ head = headPlate2 }, Snap{ equipped = {} }, {})
    CHECK(next(missing) == nil, "I: an unfindable item contributes nothing rather than erroring")
    local _, zeroTotal, zeroAvg = E.SetStats(E.NewSet("x"), Snap{ equipped = {} }, {})
    CHECK(zeroTotal == 0 and zeroAvg == 0, "I: a naked character averages zero, not a division error")

    local delta = E.StatDelta(setStats, worn)
    local byKey = {}
    for i = 1, #delta do byKey[delta[i].key] = delta[i] end
    CHECK(byKey.ITEM_MOD_STAMINA_SHORT.delta == 15, "I: the stamina delta is the difference")
    CHECK(byKey.ITEM_MOD_STAMINA_SHORT.from == 50 and byKey.ITEM_MOD_STAMINA_SHORT.to == 65,
        "I: a delta row carries both endpoints")
    CHECK(byKey.ITEM_MOD_HIT_RATING_SHORT.delta == -12, "I: a stat you lose is a negative delta")
    CHECK(byKey.ITEM_MOD_CRIT_RATING_SHORT.delta == 20, "I: a stat you gain from nothing is a full gain")
    CHECK(#delta == 3, "I: only stats that actually move are listed", #delta)
    CHECK(math.abs(delta[1].delta) >= math.abs(delta[2].delta), "I: deltas sort by magnitude")
    CHECK(byKey.ITEM_MOD_STAMINA_SHORT.label == "Stamina", "I: delta rows carry a readable label")
    CHECK(E.StatLabel("ITEM_MOD_EXPERTISE_RATING_SHORT") == "Expertise Rating",
        "I: expertise, TBC's real dodge-reduction stat, has a label")
    CHECK(E.StatLabel("RESISTANCE2_NAME") == "Fire Resistance", "I: resistances have labels")
    CHECK(E.StatLabel("SOMETHING_NEW") == "SOMETHING_NEW",
        "I: an unknown stat key falls back to itself rather than vanishing")

    local same = E.StatDelta(worn, worn)
    CHECK(#same == 0, "I: comparing a set with itself lists nothing")
    CHECK(#E.StatDelta(nil, nil) == 0, "I: comparing nothing with nothing is empty, not an error")
    -- The scratch is reused, so a shorter comparison must not inherit a tail.
    CHECK(#E.StatDelta({ ITEM_MOD_STAMINA_SHORT = 1 }, {}) == 1,
        "I: a shorter delta list does not inherit rows from a longer one")
end

-- ===========================================================================
-- J: a whole realistic swap, end to end
-- ===========================================================================

do
    -- The PvE-to-PvP case: eight slots change, the shirt and tabard are left
    -- alone, one ring is exchanged with the other finger, one piece is a
    -- differently-enchanted copy, and the off-hand is emptied for a two-hander.
    local pvpHead  = Row{ id = 42001, name = "PvP Helm",   equipLoc = "INVTYPE_HEAD",  classID = ARMOR, subClassID = 4, ilvl = 133 }
    local pvpChest = Row{ id = 42002, name = "PvP Chest",  equipLoc = "INVTYPE_CHEST", classID = ARMOR, subClassID = 4, ilvl = 133 }
    local pvpCloak = Row{ id = 42003, name = "PvP Cloak",  equipLoc = "INVTYPE_CLOAK", classID = ARMOR, subClassID = 0, ilvl = 128 }
    local pvpTrink = Row{ id = 42004, name = "PvP Trinket",equipLoc = "INVTYPE_TRINKET",classID = ARMOR, subClassID = 0, ilvl = 133 }

    local wornShirt = Copy(shirt)
    local wornTabard = Copy(tabard)
    local snap = Snap{
        playerClass = "WARRIOR", freeBagSlots = 6,
        equipped = {
            [1] = headPlate, [4] = wornShirt, [5] = chestPlate, [11] = ringA, [12] = ringB,
            [13] = trinketA, [15] = cloak, [16] = sword, [17] = shield, [19] = wornTabard,
        },
        inventory = {
            Bag(Copy(pvpHead), 1, 1), Bag(Copy(pvpChest), 1, 2), Bag(Copy(pvpCloak), 1, 3),
            Bag(Copy(pvpTrink), 1, 4), Bag(Copy(twoHander), 1, 5),
        },
    }
    local set = Set{
        head = pvpHead, chest = pvpChest, back = pvpCloak, trinket1 = pvpTrink,
        finger1 = ringB, finger2 = ringA,
        mainhand = twoHander, offhand = "EMPTY",
        shirt = "IGNORED", tabard = "IGNORED",
    }

    local plan = E.PlanSet(set, snap)
    CHECK(plan.ok == true, "J: the full PvP swap is runnable")
    CHECK(plan.verdict == "OK", "J: with a clean verdict")
    CHECK(plan.actions[1].invSlot == 16 and plan.actions[1].op == "EQUIP_FROM_BAG",
        "J: the two-hander leads the plan")
    CHECK(ActionFor(plan, "MOVE_TO_BAG", 17) == nil,
        "J: and the off-hand is left to the client, not explicitly unequipped")
    CHECK(CountOp(plan, "SWAP_EQUIPPED") == 1, "J: the two rings collapse into one exchange")
    CHECK(CountOp(plan, "EQUIP_FROM_BAG") == 5, "J: five pieces come out of bags")
    CHECK(#plan.actions == 6, "J: six actions in total", #plan.actions)
    CHECK(plan.needFree == 1, "J: only the displaced off-hand needs room", plan.needFree)
    CHECK(EveryActionHasDestination(plan), "J: every action names its destination slot")
    for i = 1, #plan.actions do
        CHECK(plan.actions[i].invSlot ~= 4 and plan.actions[i].invSlot ~= 19,
            "J: neither cosmetic slot is touched")
    end

    local diff = E.DiffSet(set, snap, {})
    -- Eight slots need work but only six actions run: the two fingers collapse
    -- into one exchange, and the off-hand removal is the client's job once the
    -- two-hander lands.
    CHECK(diff.touched == 8, "J: eight slots need work", diff.touched)
    CHECK(diff.ignored == #D.Slots - 8, "J: everything else is left alone", diff.ignored)
    CHECK(diff.isEquipped == false, "J: and the set is not currently worn")

    -- Run it to completion, then confirm the world agrees.
    local run = E.NewRun(plan)
    local guard = 0
    while E.RunStatus(run) == "RUNNING" and guard < 30 do
        guard = guard + 1
        snap.now = snap.now + 0.2
        local action = E.NextAction(run, snap)
        if not action then break end
        E.ReportResult(run, action, true)
    end
    CHECK(E.RunStatus(run) == "DONE", "J: the run completes", E.RunStatus(run))
    local summary = E.RunSummary(run)
    CHECK(summary.equipped == 6 and summary.failed == 0, "J: six moves, none failed")

    local after = Snap{
        playerClass = "WARRIOR",
        equipped = {
            [1] = Copy(pvpHead), [4] = wornShirt, [5] = Copy(pvpChest),
            [11] = ringB, [12] = ringA, [13] = Copy(pvpTrink), [15] = Copy(pvpCloak),
            [16] = Copy(twoHander), [19] = wornTabard,
        },
    }
    local finalDiff = E.DiffSet(set, after, {})
    CHECK(finalDiff.isEquipped == true, "J: afterwards the set reads as equipped")
    CHECK(finalDiff.touched == 0, "J: with nothing left to do")
    local again = E.PlanSet(set, after)
    CHECK(again.ok == false and ReasonWith(again, "NOTHING_TO_DO") ~= nil,
        "J: and re-planning is a no-op rather than a second round of churn")
end

-- ===========================================================================
-- L: the announced exception — a two-hander bagging an IGNORED off-hand
-- ===========================================================================
--
-- The client displaces the off-hand whether or not the set ignores slot 17, so
-- the module cannot honour "do not touch this slot" here. It CAN refuse to do
-- it silently, and that is the whole of this section: unavoidable is not the
-- same as unannounced.

do
    -- The reviewer's exact trigger: a set that names a two-hander and ignores
    -- all eighteen other slots, worn over a one-hander and a shield.
    local snap = Snap{
        equipped = { [16] = sword, [17] = shield, [1] = headPlate },
        inventory = { Bag(Copy(twoHander), 1, 1) },
        freeBagSlots = 3,
    }
    local set = Set{ mainhand = twoHander }
    local plan = E.PlanSet(set, snap)

    CHECK(plan.ok == true, "L: a one-slot two-hander set still runs — this warns, it never refuses")
    CHECK(plan.verdict == "OK", "L: and the verdict stays OK")
    local warn = ReasonWith(plan, "IGNORE_OVERRIDDEN")
    CHECK(warn ~= nil, "L: bagging an ignored off-hand is announced BEFORE anything moves")
    CHECK(warn and warn.warning == true, "L: and is flagged as a warning, not a blocker")
    CHECK(warn and warn.slotKey == "offhand", "L: the warning names the slot it is about to break")
    CHECK(warn and warn.text:find("Shield", 1, true) ~= nil,
        "L: and names the item that is going to your bags")
    CHECK(warn and warn.text:find("Great Axe", 1, true) ~= nil,
        "L: and the two-hander that is causing it")
    CHECK(plan.needFree == 1, "L: the bag slot the client will use is still reserved")
    CHECK(plan.actions[1].invSlot == 16, "L: the two-hander is still action #1")
    CHECK(ActionFor(plan, "MOVE_TO_BAG", 17) == nil, "L: and we still do not strip 17 ourselves")

    -- A host must be able to tell a warning from a refusal without a code list.
    local blockers = 0
    for i = 1, #plan.reasons do
        if not plan.reasons[i].warning then blockers = blockers + 1 end
    end
    CHECK(blockers == 0, "L: a warning-only plan has no blocking reasons at all")
end

do
    -- It must NOT fire when there is nothing to displace.
    local bare = Snap{
        equipped = { [16] = sword },
        inventory = { Bag(Copy(twoHander), 1, 1) },
        freeBagSlots = 3,
    }
    local plan = E.PlanSet(Set{ mainhand = twoHander }, bare)
    CHECK(plan.ok == true and ReasonWith(plan, "IGNORE_OVERRIDDEN") == nil,
        "L: no warning when the off-hand is already empty — nothing is being taken")

    -- Nor when the set speaks for slot 17 itself: the player already told us.
    local targeted = Snap{
        equipped = { [16] = sword, [17] = shield },
        inventory = { Bag(Copy(twoHander), 1, 1) },
        freeBagSlots = 3,
    }
    plan = E.PlanSet(Set{ mainhand = twoHander, offhand = "EMPTY" }, targeted)
    CHECK(plan.ok == true and ReasonWith(plan, "IGNORE_OVERRIDDEN") == nil,
        "L: no warning when the set explicitly empties the off-hand — that is consent")

    -- An off-hand the set wants FILLED is still a hard refusal, not a warning.
    local conflicting = Snap{
        equipped = { [16] = sword, [17] = shield },
        inventory = { Bag(Copy(twoHander), 1, 1), Bag(Copy(holdable), 1, 2) },
        freeBagSlots = 3,
    }
    plan = E.PlanSet(Set{ mainhand = twoHander, offhand = holdable }, conflicting)
    CHECK(plan.ok == false, "L: a set wanting both a two-hander and an off-hand still refuses")
    CHECK(ReasonWith(plan, "IGNORE_OVERRIDDEN") == nil,
        "L: and is reported as impossible, not as a warning")

    -- A ONE-hander over an ignored off-hand displaces nothing.
    local oneHand = Snap{
        equipped = { [16] = dagger, [17] = shield },
        inventory = { Bag(Copy(sword), 1, 1) },
        freeBagSlots = 3,
    }
    plan = E.PlanSet(Set{ mainhand = sword }, oneHand)
    CHECK(plan.ok == true and ReasonWith(plan, "IGNORE_OVERRIDDEN") == nil,
        "L: swapping one one-hander for another leaves an ignored off-hand alone")
    CHECK(plan.needFree == 0, "L: and costs no bag space")
end

-- ===========================================================================
-- M: a snapshot we do not have
-- ===========================================================================
--
-- The UI wraps these in pcall, so throwing here does not surface an error —
-- it silently produces a blank pane. Soft-failing into silence is the exact
-- behaviour this module exists to not have, so every entry point answers
-- "nothing to do" for a world it cannot see.

do
    local set = Set{ head = headPlate, chest = "EMPTY" }

    local ok, diff = pcall(E.DiffSet, set, nil, {})
    CHECK(ok, "M: DiffSet against a nil snapshot does not throw", not ok and diff or nil)
    CHECK(ok and diff.n == 0 and diff.touched == 0, "M: it reports an empty diff")
    CHECK(ok and diff.ignored == #D.Slots, "M: with every slot untouched")
    CHECK(ok and #diff.changes == 0, "M: and no change rows to paint")

    local okPlan, plan = pcall(E.PlanSet, set, nil)
    CHECK(okPlan, "M: PlanSet against a nil snapshot does not throw", not okPlan and plan or nil)
    CHECK(okPlan and #plan.actions == 0,
        "M: and emits no actions — never guess at a world you cannot see")
    CHECK(okPlan and plan.ok == false and ReasonWith(plan, "NOTHING_TO_DO") ~= nil,
        "M: it says there is nothing to do")

    local okDirty, dirty = pcall(E.SetIsDirty, set, nil)
    CHECK(okDirty and dirty == false, "M: SetIsDirty against a nil snapshot is not dirty")

    local okStats, stats, total, avg = pcall(E.SetStats, set, nil, {})
    CHECK(okStats and next(stats) == nil and total == 0 and avg == 0,
        "M: SetStats against a nil snapshot is empty, not an error")

    local okWorn, worn = pcall(E.EquippedStats, nil, {})
    CHECK(okWorn and next(worn) == nil, "M: EquippedStats against a nil snapshot is empty")

    local okSingle, single = pcall(E.PlanSingle, 11, nil, nil)
    CHECK(okSingle and #single.actions == 0, "M: PlanSingle against a nil snapshot does nothing")

    local okCands, rows = pcall(E.Candidates, nil, 1)
    CHECK(okCands and #rows == 0, "M: Candidates against a nil snapshot is an empty list")

    local okNil = pcall(E.DiffSet, nil, nil, {})
    CHECK(okNil, "M: a nil set AND a nil snapshot is still not an error")
end

-- ===========================================================================
-- K: the host contract — what CommanderArmory.lua reads off an action
-- ===========================================================================

do
    -- Every action carries the item's identity, not just its coordinates. The
    -- host re-resolves (bag, slot) immediately before touching the cursor,
    -- because a bag re-sort mid-run makes a plan-time coordinate stale and the
    -- client answers a stale coordinate with "Item does not go in that slot".
    local bagged = Bag(Copy(headPlate2), 2, 6)
    bagged.broken = true
    local snap = Snap{
        equipped = { [1] = headPlate, [11] = ringA },
        inventory = { bagged },
        freeBagSlots = 4,
    }
    local plan = E.PlanSet(Set{ head = headPlate2, finger1 = "EMPTY" }, snap)
    local equip = ActionFor(plan, "EQUIP_FROM_BAG", 1)
    CHECK(equip.key == bagged.key, "K: an equip carries the key so the host can verify the square")
    CHECK(equip.itemID == headPlate2.itemID, "K: and the item id")
    CHECK(equip.name == "Better Helm", "K: and a name for the announcement")
    CHECK(equip.broken == true, "K: and the broken flag for the durability warning")
    CHECK(equip.bag == 2 and equip.slot == 6, "K: alongside the coordinates it must re-check")

    local strip = ActionFor(plan, "MOVE_TO_BAG", 11)
    CHECK(strip.key == ringA.key, "K: a removal identifies the item it is taking off")
    CHECK(strip.itemID == ringA.itemID, "K: with its item id")

    local bankSnap = Snap{ atBank = true, freeBagSlots = 3,
        inventory = { Bank(Copy(chestPlate), -1, 2) } }
    local bankPlan = E.PlanSet(Set{ chest = chestPlate }, bankSnap)
    local withdraw = bankPlan.actions[1]
    CHECK(withdraw.op == "WITHDRAW" and withdraw.key == chestPlate.key,
        "K: a withdrawal carries the key too — the bank re-sorts as readily as a bag")
    CHECK(withdraw.itemID == chestPlate.itemID, "K: and the item id")

    local swapSnap = Snap{ equipped = { [11] = ringA, [12] = ringB } }
    local swapPlan = E.PlanSet(Set{ finger1 = ringB, finger2 = ringA }, swapSnap)
    CHECK(swapPlan.actions[1].key == ringB.key, "K: even a swap names the item it is moving")
end

do
    -- PlanSingle with no candidate is the removal verb.
    local snap = Snap{ equipped = { [13] = trinketA }, freeBagSlots = 2 }
    local plan = E.PlanSingle(13, nil, snap)
    CHECK(plan.ok == true, "K: PlanSingle(slot, nil) is a legal request")
    CHECK(#plan.actions == 1 and plan.actions[1].op == "MOVE_TO_BAG",
        "K: and it means remove whatever is in this slot")
    CHECK(plan.actions[1].invSlot == 13, "K: from exactly that slot")
    CHECK(plan.actions[1].key == trinketA.key, "K: naming the item it will take off")

    snap.freeBagSlots = 0
    local blocked = E.PlanSingle(13, nil, snap)
    CHECK(blocked.ok == false and ReasonWith(blocked, "BAGS_FULL") ~= nil,
        "K: with no room, a removal refuses rather than jamming the cursor")
end

do
    -- BaseKey is the tolerant one. The host's own inline pattern requires a
    -- positive item id; ours must not, or a future negative id breaks it.
    CHECK(E.BaseKey("29918:0:2564:0:0:0:0") == "29918:0", "K: BaseKey trims to itemID:suffixID")
    CHECK(E.BaseKey("25059:-36:0:0:0:0:0") == "25059:-36", "K: BaseKey keeps a negative suffix")
    CHECK(E.BaseKey("-7:-36:0:0:0:0:0") == "-7:-36",
        "K: BaseKey tolerates a negative item id, which the host's own pattern would drop")
    CHECK(E.BaseKey("25059:-36") == "25059:-36", "K: BaseKey of a base key is itself")
    CHECK(E.BaseKey("garbage") == nil, "K: BaseKey of a non-key is nil")
end

do
    -- The live ignore scratchpad: slots the player has toggled off but not yet
    -- saved must be honoured in the pre-flight preview.
    local snap = Snap{
        equipped = { [1] = headPlate, [5] = chestPlate },
        inventory = { Bag(Copy(headPlate2), 1, 1), Bag(Copy(robe), 1, 2) },
    }
    local set = Set{ head = headPlate2, chest = robe }

    local full = E.PlanSet(set, snap)
    CHECK(#full.actions == 2, "K: without the scratchpad both slots are planned")

    local scratched = E.PlanSet(set, snap, { ignore = { chest = true } })
    CHECK(#scratched.actions == 1, "K: an in-progress ignore removes that slot from the plan")
    CHECK(scratched.actions[1].invSlot == 1, "K: leaving only the slot still in play")
    CHECK(ActionFor(scratched, "EQUIP_FROM_BAG", 5) == nil,
        "K: and nothing at all touches the scratched slot")

    local diff = E.DiffSet(set, snap, {}, { chest = true })
    CHECK(diff.touched == 1 and RowFor(diff, "chest") == nil,
        "K: the diff honours the scratchpad too, so the preview matches the plan")

    local allOff = E.PlanSet(set, snap, { ignore = { head = true, chest = true } })
    CHECK(allOff.ok == false and ReasonWith(allOff, "NOTHING_TO_DO") ~= nil,
        "K: ignoring everything is nothing to do, not an error")

    local captured = E.CaptureSet(snap, { ignore = { chest = true } })
    CHECK(captured.chest.state == "IGNORED" and captured.head.state == "ITEM",
        "K: CaptureSet reads the same scratchpad shape")
end

io.write(string.format("\n%s  %d checks, %d failures\n", fails == 0 and "PASS" or "FAIL", checks, fails))
os.exit(fails == 0 and 0 or 1)
