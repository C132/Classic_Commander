-- Commander Quartermaster — the enhancement engine.
-- Reads CommanderQuartermasterEnhanceData (generated) and answers two
-- questions the supply ledger could not: what enhancement is ON my gear, and
-- what could be.
--
-- The audit deliberately prefers the CLIENT to the database. An equipped
-- item's link carries the enchant id and the gem item ids the server actually
-- applied, and GetItemStats counts the sockets the item actually has — so
-- "this slot is bare" is a fact, not a lookup. The generated database is only
-- consulted to NAME what it finds and to say what else could go there.

local Data = CommanderQuartermasterEnhanceData
if not Data then return end

CommanderQuartermasterEnhance = {}
local M = CommanderQuartermasterEnhance

-- ---------------------------------------------------------------------------
-- Index
-- ---------------------------------------------------------------------------

local byEnchant = {}      -- enchant effect id -> { entry, ... }
local byItem = {}         -- carrier item id   -> entry
local bySlot = {}         -- slot key          -> { entry, ... }

local function BuildIndex()
    for _, entry in ipairs(Data.Entries) do
        local list = byEnchant[entry.ench]
        if not list then
            list = {}
            byEnchant[entry.ench] = list
        end
        list[#list + 1] = entry
        if entry.item and not byItem[entry.item] then
            byItem[entry.item] = entry
        end
        for _, slot in ipairs(entry.slots) do
            bySlot[slot] = bySlot[slot] or {}
            local into = bySlot[slot]
            into[#into + 1] = entry
        end
    end
end
BuildIndex()

-- Every id in the database, carrier items and the reagents/recipes that lead
-- to them, so the ledger can count what you are holding for a slot you have
-- not enhanced yet.
local ledgerItems = {}
do
    for _, entry in ipairs(Data.Entries) do
        if entry.item then ledgerItems[entry.item] = true end
    end
end

function M.IsEnhancement(itemID)
    return itemID and ledgerItems[itemID] or false
end

function M.EntryForEnchant(enchantID)
    local list = enchantID and byEnchant[enchantID]
    return list and list[1] or nil
end

-- Every entry that shares an enchant id — the same +4 Stats can arrive as a
-- scroll, a vendor glyph or a craft, and the browser wants to say so.
function M.EntriesForEnchant(enchantID)
    return enchantID and byEnchant[enchantID] or nil
end

function M.EntryForItem(itemID)
    return itemID and byItem[itemID] or nil
end

function M.EntriesForSlot(slotKey)
    return bySlot[slotKey]
end

-- ---------------------------------------------------------------------------
-- Equipment
-- ---------------------------------------------------------------------------

-- Only the slots TBC lets you enhance at all. Waist, neck, trinkets, shirt,
-- tabard, relics and ammo take nothing — reporting them as "missing" would be
-- reporting the rules of the game as a failing of the player.
local SLOT_OF_EQUIPLOC = {
    INVTYPE_HEAD = "HEAD",
    INVTYPE_SHOULDER = "SHOULDER",
    INVTYPE_CLOAK = "CLOAK",
    INVTYPE_CHEST = "CHEST",
    INVTYPE_ROBE = "CHEST",
    INVTYPE_WRIST = "BRACER",
    INVTYPE_HAND = "GLOVES",
    INVTYPE_LEGS = "LEGS",
    INVTYPE_FEET = "BOOTS",
    INVTYPE_FINGER = "RING",
    INVTYPE_WEAPON = "WEAPON",
    INVTYPE_WEAPONMAINHAND = "WEAPON",
    INVTYPE_WEAPONOFFHAND = "WEAPON",
    INVTYPE_2HWEAPON = "TWOHAND",
    INVTYPE_SHIELD = "SHIELD",
    INVTYPE_RANGED = "RANGED",
    INVTYPE_RANGEDRIGHT = "RANGED",
    INVTYPE_THROWN = "RANGED",
}

-- The equipment slots we walk, in the order a player reads their character
-- sheet. Held-in-off-hand (INVTYPE_HOLDABLE) sits in slot 17 and takes no
-- enchant; the equip location, not the slot number, decides.
local SLOTS = {
    { id = 1, name = "Head" }, { id = 3, name = "Shoulder" },
    { id = 15, name = "Back" }, { id = 5, name = "Chest" },
    { id = 9, name = "Wrist" }, { id = 10, name = "Hands" },
    { id = 6, name = "Waist" }, { id = 7, name = "Legs" },
    { id = 8, name = "Feet" }, { id = 11, name = "Finger 1" },
    { id = 12, name = "Finger 2" }, { id = 16, name = "Main Hand" },
    { id = 17, name = "Off Hand" }, { id = 18, name = "Ranged" },
}
M.Slots = SLOTS

local SOCKET_STATS = {
    EMPTY_SOCKET_RED = "RED", EMPTY_SOCKET_YELLOW = "YELLOW",
    EMPTY_SOCKET_BLUE = "BLUE", EMPTY_SOCKET_META = "META",
    EMPTY_SOCKET_PRISMATIC = "PRISMATIC",
}

-- item:ID:enchant:gem1:gem2:gem3:gem4:...
local function ParseLink(link)
    if not link then return nil end
    local payload = link:match("|Hitem:([%-%d:]+)|h") or link:match("^item:([%-%d:]+)$")
    if not payload then return nil end
    local f = {}
    for part in (payload .. ":"):gmatch("([%-%d]*):") do
        f[#f + 1] = tonumber(part) or 0
    end
    return {
        id = f[1], enchant = f[2] or 0,
        gems = { f[3] or 0, f[4] or 0, f[5] or 0, f[6] or 0 },
    }
end
M.ParseLink = ParseLink

local function ItemStats(link)
    local stats
    if C_Item and C_Item.GetItemStats then
        local ok, res = pcall(C_Item.GetItemStats, link)
        if ok then stats = res end
    end
    if not stats and GetItemStats then
        local ok, res = pcall(GetItemStats, link)
        if ok then stats = res end
    end
    return stats
end

local function EquipLoc(link)
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, _, _, _, equipLoc = pcall(C_Item.GetItemInfoInstant, link)
        if ok then return equipLoc end
    end
    if GetItemInfoInstant then
        local ok, _, _, _, equipLoc = pcall(GetItemInfoInstant, link)
        if ok then return equipLoc end
    end
    return nil
end

-- Do you have the profession that would let you enchant your own rings, or
-- socket a jeweller-only gem? Ring enchants are the only TBC enhancement no
-- vendor and no friend can give you, so a non-enchanter is not "missing" one.
local function SkillRank(name)
    if not (GetNumSkillLines and GetSkillLineInfo) then return nil end
    for i = 1, (GetNumSkillLines() or 0) do
        local ok, skillName, isHeader, _, rank = pcall(GetSkillLineInfo, i)
        if ok and not isHeader and skillName == name then return rank or 0 end
    end
    return nil
end
M.SkillRank = SkillRank

-- ---------------------------------------------------------------------------
-- The audit
-- ---------------------------------------------------------------------------

-- One row per equipped slot:
--   slot      our slot key (HEAD, WEAPON, ...) or nil when nothing fits here
--   link,name,quality  the equipped item
--   ench      the enchant effect id the link carries (0 = bare)
--   entry     the database entry naming that enchant, when it knows it
--   sockets   { "RED", "META", ... } every socket the item has
--   gems      { itemID, ... } what is in them, 0 for empty
--   bare      true when the slot takes an enchant and has none
--   empty     how many sockets are unfilled
function M.ScanGear(unit)
    unit = unit or "player"
    local rows, bare, empty, enchantable = {}, 0, 0, 0
    local enchanter = SkillRank("Enchanting")
    for _, slot in ipairs(SLOTS) do
        local link = GetInventoryItemLink and GetInventoryItemLink(unit, slot.id)
        local row = { invSlot = slot.id, label = slot.name, link = link }
        if link then
            local parsed = ParseLink(link)
            row.id = parsed and parsed.id
            row.ench = parsed and parsed.enchant or 0
            row.entry = M.EntryForEnchant(row.ench ~= 0 and row.ench or nil)
            row.slot = SLOT_OF_EQUIPLOC[EquipLoc(link) or ""] or nil

            -- Off-hand: a weapon takes an enchant, a held-in-off-hand does
            -- not, and both live in slot 17.
            local takesEnchant = row.slot ~= nil and bySlot[row.slot] ~= nil
            -- A ring is only actionable for an enchanter; say so rather than
            -- nagging.
            if row.slot == "RING" and not enchanter then
                takesEnchant = false
                row.needsProfession = "Enchanting"
            end
            row.takesEnchant = takesEnchant or nil

            local stats = ItemStats(link)
            if stats then
                for stat, color in pairs(SOCKET_STATS) do
                    for _ = 1, (stats[stat] or 0) do
                        row.sockets = row.sockets or {}
                        row.sockets[#row.sockets + 1] = color
                    end
                end
            end
            if parsed then
                row.gems = {}
                for i = 1, 4 do
                    if parsed.gems[i] and parsed.gems[i] ~= 0 then
                        row.gems[#row.gems + 1] = parsed.gems[i]
                    end
                end
            end
            local socketCount = row.sockets and #row.sockets or 0
            local gemCount = row.gems and #row.gems or 0
            row.empty = math.max(0, socketCount - gemCount)

            if takesEnchant then
                enchantable = enchantable + 1
                if row.ench == 0 then
                    row.bare = true
                    bare = bare + 1
                end
            end
            empty = empty + row.empty
        end
        rows[#rows + 1] = row
    end
    return {
        rows = rows, bare = bare, empty = empty, enchantable = enchantable,
        enchanter = enchanter,
    }
end

-- ---------------------------------------------------------------------------
-- Reporting
-- ---------------------------------------------------------------------------

local function EnchantName(row)
    if row.ench == 0 then return nil end
    local entry = row.entry
    if entry then
        return entry.short or entry.name
    end
    return ("enchant #%d"):format(row.ench)
end
M.EnchantName = EnchantName

-- One line per problem, and silence when there is none.
function M.Problems(report)
    local out = {}
    for _, row in ipairs(report.rows) do
        if row.link then
            if row.bare then
                out[#out + 1] = { row = row, kind = "BARE",
                                  text = ("%s is not enchanted"):format(row.label) }
            end
            if (row.empty or 0) > 0 then
                out[#out + 1] = { row = row, kind = "SOCKET",
                                  text = ("%s has %d empty socket%s"):format(
                                      row.label, row.empty, row.empty == 1 and "" or "s") }
            end
        end
    end
    return out
end

-- The best thing you ALREADY OWN for a bare slot. Takes the ledger's counting
-- function so the engine stays ignorant of the ledger: pass anything shaped
-- like CountsFor(itemID) -> bags, bank, mail, alts, total.
function M.BestHeld(slotKey, countsFor)
    local list = slotKey and bySlot[slotKey]
    if not (list and countsFor) then return nil end
    local best
    for _, entry in ipairs(list) do
        if entry.item and not entry.unobtainable then
            local bags, bank = countsFor(entry.item)
            local held = (bags or 0) + (bank or 0)
            if held > 0 then
                -- higher quality first, then the deeper enchant: a rare glyph
                -- beats an uncommon one, and among equals the one that asks
                -- more of a profession is the better item
                local score = (entry.quality or 0) * 1000 + (entry.prof and entry.prof.rank or 0)
                if not best or score > best.score then
                    best = { entry = entry, name = entry.name, count = held, score = score }
                end
            end
        end
    end
    return best
end

function M.Print(prefix)
    local report = M.ScanGear("player")
    prefix = prefix or "|cff33ff99Quartermaster|r"
    local problems = M.Problems(report)
    if #problems == 0 then
        print(("%s: every enhanceable slot is enhanced (%d slots, %d gems set)."):format(
            prefix, report.enchantable, report.empty == 0 and 0 or report.empty))
        return report
    end
    print(("%s: %d enchant%s missing, %d socket%s empty."):format(
        prefix, report.bare, report.bare == 1 and "" or "s",
        report.empty, report.empty == 1 and "" or "s"))
    for _, problem in ipairs(problems) do
        print("  |cffff8040-|r " .. problem.text)
    end
    return report
end

return M
