-- CommanderArmoryData.lua
--
-- The slot canon. Static tables only: no frames, no state, no WoW API calls at
-- file scope. Everything here is a fact about how TBC's paperdoll is shaped,
-- verified against Blizzard's own 2.5.6 source (see ASSUMPTIONS.md for the
-- handful that are inference rather than quotation).
--
-- The one design constraint that shaped this file: a slot is identified by its
-- NUMERIC id everywhere in the module, never by name. Blizzard's own naming is
-- inconsistent enough to guarantee bugs if you map by string arithmetic --
-- the character-panel buttons are zero-based (CharacterFinger0Slot,
-- CharacterTrinket0Slot) while the constants are one-based (INVSLOT_FINGER1,
-- INVSLOT_TRINKET1), the shirt slot is called BODY, and the off-hand button is
-- called SecondaryHand. Every one of those pairings is spelled out below so it
-- is written down exactly once.

CommanderArmoryData = {}
local D = CommanderArmoryData

-- Blizzard's localized slot labels, with a readable fallback for the headless
-- harness (and for a client that ever drops one of these globals). Resolved
-- lazily via D.SlotLabel so the harness does not need the globals at load.
local FALLBACK_LABEL = {
    [0]  = "Ammo",
    [1]  = "Head",       [2]  = "Neck",        [3]  = "Shoulder",
    [4]  = "Shirt",      [5]  = "Chest",       [6]  = "Waist",
    [7]  = "Legs",       [8]  = "Feet",        [9]  = "Wrist",
    [10] = "Hands",      [11] = "Ring 1",      [12] = "Ring 2",
    [13] = "Trinket 1",  [14] = "Trinket 2",   [15] = "Back",
    [16] = "Main Hand",  [17] = "Off Hand",    [18] = "Ranged",
    [19] = "Tabard",
}

-- The global string each slot's label comes from on a live client. Note
-- FINGER0SLOT/TRINKET0SLOT: Blizzard's STRING globals follow the zero-based
-- button naming even though the slot ids are one-based.
local LABEL_GLOBAL = {
    [0]  = "AMMOSLOT",       [1]  = "HEADSLOT",      [2]  = "NECKSLOT",
    [3]  = "SHOULDERSLOT",   [4]  = "SHIRTSLOT",     [5]  = "CHESTSLOT",
    [6]  = "WAISTSLOT",      [7]  = "LEGSSLOT",      [8]  = "FEETSLOT",
    [9]  = "WRISTSLOT",      [10] = "HANDSSLOT",     [11] = "FINGER0SLOT",
    [12] = "FINGER1SLOT",    [13] = "TRINKET0SLOT",  [14] = "TRINKET1SLOT",
    [15] = "BACKSLOT",       [16] = "MAINHANDSLOT",  [17] = "SECONDARYHANDSLOT",
    [18] = "RANGEDSLOT",     [19] = "TABARDSLOT",
}

-- ---------------------------------------------------------------------------
-- The slots
-- ---------------------------------------------------------------------------
-- id       the INVSLOT_* number. The only identifier that matters.
-- key      our stable string key for saved data. NEVER renumber or rename
--          these: they are written into the player's saved sets.
-- button   the character-panel button's global name, for hooking and anchoring.
--          GetInventorySlotInfo() wants this with the 9-char "Character"
--          prefix removed, which is what D.SlotInfoName() returns.
-- cosmetic true for slots that carry no stats. Sets exclude these by default
--          (D5) because a player who saves a PvP set does not mean "and also
--          put my guild tabard back on".
-- row/col  layout hints for our own panel; the paperdoll's own two columns.

D.Slots = {
    { id = 1,  key = "head",      button = "CharacterHeadSlot" },
    { id = 2,  key = "neck",      button = "CharacterNeckSlot" },
    { id = 3,  key = "shoulder",  button = "CharacterShoulderSlot" },
    { id = 15, key = "back",      button = "CharacterBackSlot" },
    { id = 5,  key = "chest",     button = "CharacterChestSlot" },
    { id = 4,  key = "shirt",     button = "CharacterShirtSlot",  cosmetic = true },
    { id = 19, key = "tabard",    button = "CharacterTabardSlot", cosmetic = true },
    { id = 9,  key = "wrist",     button = "CharacterWristSlot" },
    { id = 10, key = "hands",     button = "CharacterHandsSlot" },
    { id = 6,  key = "waist",     button = "CharacterWaistSlot" },
    { id = 7,  key = "legs",      button = "CharacterLegsSlot" },
    { id = 8,  key = "feet",      button = "CharacterFeetSlot" },
    { id = 11, key = "finger1",   button = "CharacterFinger0Slot" },
    { id = 12, key = "finger2",   button = "CharacterFinger1Slot" },
    { id = 13, key = "trinket1",  button = "CharacterTrinket0Slot" },
    { id = 14, key = "trinket2",  button = "CharacterTrinket1Slot" },
    { id = 16, key = "mainhand",  button = "CharacterMainHandSlot" },
    { id = 17, key = "offhand",   button = "CharacterSecondaryHandSlot" },
    { id = 18, key = "ranged",    button = "CharacterRangedSlot" },
}

-- The ammo slot is deliberately NOT in D.Slots. It is slot 0, it sits outside
-- INVSLOT_FIRST_EQUIPPED..INVSLOT_LAST_EQUIPPED, its character-panel button
-- does not inherit PaperDollItemSlotButtonTemplate (so none of the
-- PaperDollItemSlotButton_* hooks reach it), and Blizzard hides it outright for
-- classes with a relic slot. It is handled as a special case or not at all --
-- see DECISIONS D4.
D.AMMO_SLOT = 0

D.FIRST_SLOT = 1
D.LAST_SLOT  = 19

-- Slots the SERVER permits swapping while UnitAffectingCombat("player") is
-- true. Mirrors INVSLOTS_EQUIPABLE_IN_COMBAT from Blizzard's
-- Constants.lua:194-198. Declared with our own literal rather than read from
-- the global so the engine stays pure Lua and the harness can fixture it; the
-- runtime cross-checks the global when one is present.
D.EquipableInCombat = {
    [16] = true,   -- main hand
    [17] = true,   -- off hand
    [18] = true,   -- ranged
}

-- ---------------------------------------------------------------------------
-- Which slots an item can go into
-- ---------------------------------------------------------------------------
-- Keyed by the itemEquipLoc string that C_Item.GetItemInfoInstant returns as
-- its 4th value. That call is SYNCHRONOUS and never nil for a real itemID,
-- which is the whole reason candidate lists can be built in one pass without
-- waiting on GET_ITEM_INFO_RECEIVED.
--
-- Order matters: the first entry is the slot the item goes to when the player
-- has expressed no preference. Rings and trinkets list both, and the engine
-- picks by "the slot it is already in, else the first free one, else slot 1".
D.EquipLocSlots = {
    INVTYPE_HEAD             = { 1 },
    INVTYPE_NECK             = { 2 },
    INVTYPE_SHOULDER         = { 3 },
    INVTYPE_BODY             = { 4 },      -- shirt
    INVTYPE_CHEST            = { 5 },
    INVTYPE_ROBE             = { 5 },      -- cloth chest pieces report ROBE
    INVTYPE_WAIST            = { 6 },
    INVTYPE_LEGS             = { 7 },
    INVTYPE_FEET             = { 8 },
    INVTYPE_WRIST            = { 9 },
    INVTYPE_HAND             = { 10 },
    INVTYPE_FINGER           = { 11, 12 },
    INVTYPE_TRINKET          = { 13, 14 },
    INVTYPE_CLOAK            = { 15 },
    INVTYPE_WEAPON           = { 16, 17 }, -- one-hand; off-hand only if the
                                           -- player can dual wield, which the
                                           -- engine resolves at runtime
    INVTYPE_2HWEAPON         = { 16 },
    INVTYPE_WEAPONMAINHAND   = { 16 },
    INVTYPE_WEAPONOFFHAND    = { 17 },
    INVTYPE_SHIELD           = { 17 },
    INVTYPE_HOLDABLE         = { 17 },     -- off-hand frills, tomes, orbs
    INVTYPE_RANGED           = { 18 },     -- bows, crossbows
    INVTYPE_RANGEDRIGHT      = { 18 },     -- guns, wands
    INVTYPE_THROWN           = { 18 },
    INVTYPE_RELIC            = { 18 },     -- libram / idol / totem
    INVTYPE_TABARD           = { 19 },
    INVTYPE_AMMO             = { 0 },
    -- INVTYPE_BAG and INVTYPE_QUIVER are container slots, not equipment.
    -- Absent on purpose: an entry here would put bags in the flyout.
}

-- Slot 18 has three faces on TBC and only one id. Which face is showing is a
-- runtime question (C_PaperDollInfo.IsRangedSlotShown / UnitHasRelicSlot), but
-- the equip-loc set for each face is static.
D.RangedEquipLocs = {
    INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true,
}
D.RelicEquipLocs = {
    INVTYPE_RELIC = true,
}

-- Two-handers occupy the main hand and forbid an off-hand. Titan's Grip does
-- not exist in TBC, so this is unconditional here -- which is exactly why the
-- sequencer can treat "target main hand is 2H" as "off-hand must be emptied
-- first" with no class check (DECISIONS D7).
D.TwoHandEquipLocs = {
    INVTYPE_2HWEAPON = true,
}

-- Off-hand things that are not weapons. Needed because a shield or a holdable
-- can be equipped by any class regardless of dual-wield skill, while
-- INVTYPE_WEAPON in slot 17 cannot.
D.OffHandNonWeaponEquipLocs = {
    INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true,
}

-- ---------------------------------------------------------------------------
-- Item class/subclass canon
-- ---------------------------------------------------------------------------
-- Classification is keyed on the (classID, subClassID) INTEGER pair, never the
-- localized type string. Armor/Cloth is 4/1 and Tradegoods/Cloth is 7/5 and
-- both stringify as "Cloth" -- the Spoils precedent, where a name-keyed
-- classifier filed robes as crafting materials and nobody noticed until
-- someone farmed humanoids.
D.CLASS_ARMOR  = 4
D.CLASS_WEAPON = 2

D.ArmorSubclass = {
    MISC    = 0,   -- cloaks, rings, necks, trinkets all report Miscellaneous
    CLOTH   = 1,
    LEATHER = 2,
    MAIL    = 3,
    PLATE   = 4,
    SHIELD  = 6,
    LIBRAM  = 7,
    IDOL    = 8,
    TOTEM   = 9,
}

-- Armor classes a player can wear proficiently, by class token. Used only to
-- sort and dim the flyout -- never to hide an item, because a warrior levelling
-- in mail is making a legitimate choice and an addon that hides it is wrong.
D.ArmorProficiency = {
    WARRIOR = { [4] = true, [3] = true, [2] = true, [1] = true },
    PALADIN = { [4] = true, [3] = true, [2] = true, [1] = true },
    HUNTER  = { [3] = true, [2] = true, [1] = true },
    SHAMAN  = { [3] = true, [2] = true, [1] = true },
    ROGUE   = { [2] = true, [1] = true },
    DRUID   = { [2] = true, [1] = true },
    PRIEST  = { [1] = true },
    MAGE    = { [1] = true },
    WARLOCK = { [1] = true },
}

-- The relic subclass each class uses, for the slot-18 face. A paladin's
-- flyout should not offer idols.
D.RelicSubclass = {
    PALADIN = 7,   -- Libram
    DRUID   = 8,   -- Idol
    SHAMAN  = 9,   -- Totem
}

-- ---------------------------------------------------------------------------
-- Unique-equipped conflicts
-- ---------------------------------------------------------------------------
-- Read straight out of this client's own ItemLimitCategory table (build
-- 2.5.6.69110). The whole table is THIRTEEN rows, and only three of them
-- describe a limit on what may be EQUIPPED at once -- the rest cap what you may
-- hold. So the cross-item conflict problem in TBC is not the sprawling mess the
-- ecosystem's hand-curated tables imply; it is three families of reputation
-- rings, and it can be stated exactly rather than approximated.
--
-- The flag semantics come from the DBC enum: 0 caps how many you may HOLD,
-- 1 caps how many you may have EQUIPPED (sockets included). Only mode 1 can
-- make a gear swap fail, so only mode 1 is here. Dungeon keys, healthstones and
-- the Argent Dawn trinket pair are all mode 0 and irrelevant to us.
--
-- Verified disjoint from the per-item unique-equipped flag: of 30,128 item rows
-- in this build, 415 carry the unique-equipped bit and 60 carry a limit
-- category, and the two sets do not intersect. So a conflict is EITHER
-- "the same item twice" OR "two members of one of the three families below",
-- never both.
D.LimitCategories = {
    [475] = { name = "Signet Ring of the Bronze Dragonflight", max = 1 },
    [495] = { name = "Violet Signet",                          max = 1 },
    [497] = { name = "Band of Eternity",                       max = 1 },
}

-- itemID -> limit category id. Contiguous runs, written out so a reader can see
-- there is no guesswork: AQ40's Brood of Nozdormu rings, Karazhan's Violet Eye
-- rings, and Hyjal's Scale of the Sands rings.
D.LimitCategoryByItem = {}
do
    local RUNS = {
        { first = 21196, last = 21210, category = 475 },
        { first = 29276, last = 29291, category = 495 },
        { first = 29294, last = 29309, category = 497 },
    }
    for _, run in ipairs(RUNS) do
        for itemID = run.first, run.last do
            D.LimitCategoryByItem[itemID] = run.category
        end
    end
end

-- The "Jeweler's Gems (3)" shared category that every WotLK-era guide mentions
-- DOES NOT EXIST on TBC -- row 2 is "Prismatic Gems, quantity 1" here and is
-- referenced by exactly one dead test item. TBC's jewelcrafter-only gems and the
-- Ornate/Unstable PvP gems are plain per-item unique-equipped instead, with no
-- category at all.
--
-- That still leaves one real conflict our planner must catch: two DIFFERENT
-- pieces of gear each socketed with the same unique-equipped gem cannot both be
-- worn. We can detect it without any gem table, because the identity key
-- already carries gem ids in fields 3-6 -- a repeated gem id across two target
-- items is the conflict, whatever the gem happens to be. That is strictly
-- better than the ecosystem's curated lists, which have twice shipped with
-- entries missing and silently reintroduced the bug.

function D.LimitCategoryFor(itemID)
    local id = itemID and D.LimitCategoryByItem[itemID]
    if not id then return nil end
    return id, D.LimitCategories[id]
end

-- ---------------------------------------------------------------------------
-- Location packing
-- ---------------------------------------------------------------------------
-- GetInventoryItemsForSlot and C_EquipmentSet.GetItemLocations both hand back
-- packed integers rather than ItemLocation objects. The bit layout is
-- Blizzard's (Constants.lua:166-169); the unpacker lives in the engine so it
-- can be tested, but the constants belong with the rest of the canon.
D.LOC_PLAYER         = 0x00100000
D.LOC_BANK           = 0x00400000
D.LOC_BAGS           = 0x00200000
D.LOC_BAG_BIT_OFFSET = 8

-- ---------------------------------------------------------------------------
-- Helpers over the canon (pure; safe to call from the harness)
-- ---------------------------------------------------------------------------

-- id -> the D.Slots entry
D.SlotByID = {}
-- our saved key -> the D.Slots entry
D.SlotByKey = {}
-- the character-panel button global name -> the D.Slots entry
D.SlotByButton = {}
-- display order, as the entries are listed above
D.SlotOrder = {}

for index, slot in ipairs(D.Slots) do
    slot.order = index
    D.SlotByID[slot.id]         = slot
    D.SlotByKey[slot.key]       = slot
    D.SlotByButton[slot.button] = slot
    D.SlotOrder[index]          = slot.id
end

-- GetInventorySlotInfo() takes the button name with the 9-character
-- "Character" prefix stripped -- "HeadSlot", "MainHandSlot". Blizzard does this
-- with strsub(slotName, 10) in PaperDollItemSlotButton_OnLoad; we spell it out
-- rather than repeat the magic number at every call site.
function D.SlotInfoName(slotID)
    local slot = D.SlotByID[slotID]
    if not slot then return nil end
    return slot.button:sub(10)
end

function D.SlotLabel(slotID)
    local name = LABEL_GLOBAL[slotID]
    local value = name and rawget(_G or {}, name)
    if type(value) == "string" and value ~= "" then return value end
    return FALLBACK_LABEL[slotID] or ("Slot " .. tostring(slotID))
end

-- Which slots this item could occupy. Returns a NEW array every call because
-- callers filter it in place; the canon table must never be handed out.
function D.SlotsForEquipLoc(equipLoc)
    local slots = equipLoc and D.EquipLocSlots[equipLoc]
    if not slots then return {} end
    local out = {}
    for i = 1, #slots do out[i] = slots[i] end
    return out
end

function D.IsTwoHand(equipLoc)
    return D.TwoHandEquipLocs[equipLoc] == true
end

function D.IsCosmeticSlot(slotID)
    local slot = D.SlotByID[slotID]
    return slot ~= nil and slot.cosmetic == true
end

function D.IsEquipableInCombat(slotID)
    return D.EquipableInCombat[slotID] == true
end
