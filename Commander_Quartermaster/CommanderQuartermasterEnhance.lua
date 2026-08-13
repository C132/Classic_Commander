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

-- Which shelf a gem belongs on. TBC's two-colour gems have no colour of
-- their own in the data — they are simply red AND yellow — but a player
-- shopping for gems thinks in seven groups, not four bits.
local GEM_GROUPS = {
    { key = "META", name = "Meta", colors = { META = true } },
    { key = "RED", name = "Red", colors = { RED = true } },
    { key = "YELLOW", name = "Yellow", colors = { YELLOW = true } },
    { key = "BLUE", name = "Blue", colors = { BLUE = true } },
    { key = "ORANGE", name = "Orange", colors = { RED = true, YELLOW = true } },
    { key = "PURPLE", name = "Purple", colors = { RED = true, BLUE = true } },
    { key = "GREEN", name = "Green", colors = { YELLOW = true, BLUE = true } },
    -- Void Sphere and Prismatic Sphere are red AND yellow AND blue: they fit
    -- any socket that is not a meta, and they get their own shelf because
    -- nothing else in TBC behaves like them.
    { key = "PRISMATIC", name = "Prismatic",
      colors = { RED = true, YELLOW = true, BLUE = true } },
}
M.GemGroups = GEM_GROUPS

function M.GemGroup(entry)
    if not (entry and entry.kind == "GEM") then return nil end
    local colors = entry.colors or (entry.color and { entry.color }) or {}
    local have = {}
    for _, color in ipairs(colors) do have[color] = true end
    for _, group in ipairs(GEM_GROUPS) do
        local match = true
        for color in pairs(group.colors) do
            if not have[color] then match = false break end
        end
        for color in pairs(have) do
            if not group.colors[color] then match = false break end
        end
        if match then return group.key end
    end
    return "OTHER"
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

local SOCKET_ORDER = { "META", "RED", "YELLOW", "BLUE", "PRISMATIC" }
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

-- Lua 5.1 has no bitwise operators; the client ships the bit library and so
-- does luajit, but never assume — a missing library must not take the audit
-- down with it.
local band = bit and bit.band
local function MaskHas(mask, index)
    if not mask or mask == 0 then return true end   -- no mask = no restriction
    if band then return band(mask, 2 ^ index) ~= 0 end
    return math.floor(mask / (2 ^ index)) % 2 == 1
end

-- Can this enhancement land on this item? The equip location alone cannot
-- say: a wand and a gun share INVTYPE_RANGEDRIGHT and only one takes a
-- scope, and a fishing pole and a staff are both two-handers but only one
-- takes a lure. The client answers with an item class and a subclass mask,
-- which the generator carries onto every entry.
function M.Accepts(entry, classID, subclassID)
    if not entry or not entry.cls then return true end
    -- Class 0 is Consumable, which nothing equips: reading it back off an
    -- equipped item means the client did not answer, and an unanswered
    -- question must not become a "no".
    if not classID or classID == 0 then return true end
    if entry.cls ~= classID then return false end
    return MaskHas(entry.sub, subclassID or 0)
end

local function ItemClass(link)
    local getter = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not getter then return nil, nil end
    local ok, _, _, _, _, _, classID, subclassID = pcall(getter, link)
    if not ok then return nil, nil end
    return classID, subclassID
end
M.ItemClass = ItemClass

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

-- Which of our slots a link's item belongs to, or nil when nothing can be
-- applied to it. Answered from the item's equip location, so a held-in-
-- off-hand and a sword — both slot 17 — get different answers.
function M.SlotOfLink(link)
    local slot = SLOT_OF_EQUIPLOC[EquipLoc(link) or ""]
    if not (slot and bySlot[slot]) then return nil end
    -- And at least one enhancement for that slot has to accept this actual
    -- item, or the slot is not enhanceable for it.
    local classID, subclassID = ItemClass(link)
    if classID and classID ~= 0 then
        local any = false
        for _, entry in ipairs(bySlot[slot]) do
            if not entry.unobtainable and M.Accepts(entry, classID, subclassID) then
                any = true
                break
            end
        end
        if not any then return nil end
    end
    return slot
end

-- Sockets the item has, minus gems the link says are in them.
function M.EmptySockets(link, parsed)
    local stats = ItemStats(link)
    if not stats then return nil end
    local sockets = 0
    for stat in pairs(SOCKET_STATS) do
        sockets = sockets + (stats[stat] or 0)
    end
    if sockets == 0 then return 0 end
    parsed = parsed or ParseLink(link)
    local filled = 0
    for i = 1, 4 do
        if parsed and parsed.gems[i] and parsed.gems[i] ~= 0 then filled = filled + 1 end
    end
    return math.max(0, sockets - filled)
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
-- Sockets
-- ---------------------------------------------------------------------------

-- A TBC gem's colour is a SET, not a value: an orange gem is red and yellow
-- at once and satisfies either socket. Everything below treats it that way,
-- which is the only way the socket bonus and the meta requirement come out
-- right for anyone gemming orange, purple or green.
local function GemColors(itemID)
    local entry = itemID and byItem[itemID]
    if not (entry and entry.kind == "GEM") then return nil end
    return entry.colors or (entry.color and { entry.color }) or nil
end
M.GemColors = GemColors

local function Fits(colors, socket)
    if socket == "PRISMATIC" then return true end
    if not colors then return false end
    for _, color in ipairs(colors) do
        if color == socket then return true end
    end
    return false
end
M.Fits = Fits

-- Largest set of sockets that can be satisfied at once, and which gem went
-- where. A greedy pass is not enough: a red gem in a red socket may have to
-- move to the orange one so a red-only gem can take its place. Kuhn's
-- augmenting path, over at most four sockets, which is free.
--
-- Returns the count and the assignment (socket index -> gem index). The
-- assignment is what the tooltip reads: the client tells us WHICH COLOURS an
-- item has sockets for and WHICH GEMS are in it, but never which gem sits in
-- which socket — so the honest display is the one the matching computes,
-- not gem[i] paired with socket[i].
local function MaxMatch(sockets, gems)
    local gemColors = {}
    for i, id in ipairs(gems) do gemColors[i] = GemColors(id) end
    local takenBy = {}          -- socket index -> gem index
    local function try(gem, seen)
        for s, socket in ipairs(sockets) do
            if not seen[s] and Fits(gemColors[gem], socket) then
                seen[s] = true
                if not takenBy[s] or try(takenBy[s], seen) then
                    takenBy[s] = gem
                    return true
                end
            end
        end
        return false
    end
    local matched = 0
    for gem = 1, #gems do
        if try(gem, {}) then matched = matched + 1 end
    end
    return matched, takenBy
end
M.MaxMatch = MaxMatch

-- One item's socket verdict. `bonus` is whether the item's socket bonus is
-- earned: every socket filled, and filled by a gem whose colour matches it.
function M.JudgeSockets(link, parsed)
    parsed = parsed or ParseLink(link)
    local stats = ItemStats(link)
    if not (parsed and stats) then return nil end
    -- Deterministic order. GetItemStats reports socket COUNTS by colour, and
    -- a pairs() walk over them would shuffle the list between calls — which
    -- is fine for counting and useless for anything that names them.
    local sockets = {}
    for _, color in ipairs(SOCKET_ORDER) do
        for _ = 1, (stats["EMPTY_SOCKET_" .. color] or 0) do
            sockets[#sockets + 1] = color
        end
    end
    if #sockets == 0 then return nil end
    local gems = {}
    for i = 1, 4 do
        if parsed.gems[i] and parsed.gems[i] ~= 0 then
            gems[#gems + 1] = parsed.gems[i]
        end
    end
    local matched, assign = MaxMatch(sockets, gems)
    return {
        sockets = sockets, gems = gems, assign = assign,
        empty = math.max(0, #sockets - #gems),
        matched = matched,
        -- Only claim the bonus when every socket is both filled and matched.
        -- An unknown gem (one the database has never seen) counts as filled
        -- but not matched, so the verdict degrades to "cannot tell" rather
        -- than to a confident no.
        bonus = (#gems >= #sockets) and (matched >= #sockets) or false,
        unknown = (function()
            for _, id in ipairs(gems) do
                if not GemColors(id) then return true end
            end
            return nil
        end)(),
    }
end

-- Meta gems are judged against EVERY gem you are wearing, not against the
-- item they sit in — which is why a helm's meta can switch off when you
-- change a glove. A multi-coloured gem counts for each of its colours, the
-- same way the client counts it.
local function CountGemColors(rows)
    local counts = { META = 0, RED = 0, YELLOW = 0, BLUE = 0 }
    for _, row in ipairs(rows) do
        for _, id in ipairs(row.gems or {}) do
            for _, color in ipairs(GemColors(id) or {}) do
                counts[color] = (counts[color] or 0) + 1
            end
        end
    end
    return counts
end
M.CountGemColors = CountGemColors

function M.MetaActive(entry, counts)
    if not (entry and entry.cond) then return nil end
    for _, clause in ipairs(entry.cond) do
        local left = counts[clause.lt] or 0
        local right = clause.rtColor and (counts[clause.rtColor] or 0) or (clause.rt or 0)
        local ok
        if clause.op == ">=" then ok = left >= right
        elseif clause.op == ">" then ok = left > right
        elseif clause.op == "<" then ok = left < right
        else ok = true end
        if not ok then return false end
    end
    return true
end

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
            row.slot = M.SlotOfLink(link)

            -- Off-hand: a weapon takes an enchant, a held-in-off-hand does
            -- not, and both live in slot 17. A wand and a gun share slot 18,
            -- and only one of them takes a scope — SlotOfLink settles both.
            local takesEnchant = row.slot ~= nil and bySlot[row.slot] ~= nil
            -- A ring is only actionable for an enchanter; say so rather than
            -- nagging.
            if row.slot == "RING" and not enchanter then
                takesEnchant = false
                row.needsProfession = "Enchanting"
            end
            row.takesEnchant = takesEnchant or nil

            local judged = M.JudgeSockets(link, parsed)
            if judged then
                row.sockets = judged.sockets
                row.gems = judged.gems
                row.empty = judged.empty
                row.matched = judged.matched
                row.bonus = judged.bonus
                row.unknownGems = judged.unknown
            else
                row.gems = {}
                row.empty = 0
            end

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
    -- Meta activation is a whole-character question — a helm's meta switches
    -- off when you change a glove — so it can only be answered once every
    -- slot has been read.
    local counts = CountGemColors(rows)
    local meta
    for _, row in ipairs(rows) do
        for _, id in ipairs(row.gems or {}) do
            local entry = byItem[id]
            if entry and entry.cond then
                meta = { entry = entry, row = row, active = M.MetaActive(entry, counts) }
            end
        end
    end
    return {
        rows = rows, bare = bare, empty = empty, enchantable = enchantable,
        enchanter = enchanter, gemCounts = counts, meta = meta,
    }
end

-- ---------------------------------------------------------------------------
-- Ranking for a role
-- ---------------------------------------------------------------------------
-- TBC-era stat weights, one column per role the loadout database already
-- assigns to a spec. They are deliberately coarse: the job is to sort a
-- slot's shelf so the right handful floats to the top, not to out-argue a
-- simulator. Spell damage and healing are separate stats in TBC, so a caster
-- weight and a healer weight genuinely differ; school-locked spell damage
-- pays for one school and is discounted accordingly; and anything situational
-- (undead-only attack power, fishing) scores zero rather than a small number,
-- because a small number still sorts above the enchant you actually want.
local WEIGHTS = {
    MELEE = {
        STR = 1.0, AGI = 1.0, STA = 0.4, AP = 0.5, CRIT = 0.9, HIT = 1.2,
        EXPERTISE = 1.1, HASTE = 0.9, WEAPONDMG = 1.3, ARPEN = 0.5,
        ARMOR = 0.05, DODGE = 0.1, DEF = 0.1, RESIL = 0.2,
    },
    RANGED = {
        AGI = 1.0, STA = 0.35, RAP = 0.5, AP = 0.5, CRIT = 0.9, HIT = 1.2,
        HASTE = 0.9, INT = 0.15, WEAPONDMG = 1.0, ARMOR = 0.05, RESIL = 0.2,
    },
    CASTER = {
        SP = 1.0, SP_FIRE = 0.45, SP_FROST = 0.45, SP_SHADOW = 0.45,
        SP_ARCANE = 0.45, SP_NATURE = 0.45, SP_HOLY = 0.45,
        SPELLHIT = 1.3, SPELLCRIT = 0.8, SPELLHASTE = 1.0, INT = 0.35,
        SPI = 0.15, STA = 0.3, MP5 = 0.4, SPELLPEN = 0.2, ARMOR = 0.03,
    },
    HEALER = {
        HEAL = 1.0, SP = 0.55, INT = 0.5, SPI = 0.45, MP5 = 1.6,
        SPELLCRIT = 0.5, SPELLHASTE = 0.7, STA = 0.3, ARMOR = 0.03,
    },
    TANK = {
        STA = 1.0, DEF = 1.2, DODGE = 1.0, PARRY = 0.9, BLOCK = 0.6,
        BLOCKVALUE = 0.35, ARMOR = 0.12, STR = 0.4, AGI = 0.6, HP = 0.08,
        THREAT = 0.8, AP = 0.2, CRIT = 0.3, HIT = 0.5, RESIL = 0.3,
        ALLRES = 0.2, FIRERES = 0.05, FROSTRES = 0.05, NATURERES = 0.05,
        SHADOWRES = 0.05, ARCANERES = 0.05,
    },
}
M.Weights = WEIGHTS

-- What one enhancement is worth to a role. nil when it grants no stats at
-- all — a proc enchant like Mongoose or Crusader cannot be scored this way,
-- and pretending otherwise would rank it below +12 Stamina.
function M.Score(entry, role)
    local weights = WEIGHTS[role]
    if not (weights and entry and entry.stats) then return nil end
    local total = 0
    for stat, amount in pairs(entry.stats) do
        total = total + amount * (weights[stat] or 0)
    end
    return total
end

-- A slot's shelf, best for this role first. Entries with no stats keep their
-- place at the end rather than being dropped: Mongoose is the best weapon
-- enchant in TBC and scores nil, because a proc is not a stat line. That is
-- also why nothing here is called "best" without the words "by stats".
--
-- `want` picks a half of the shelf: "PERM" for the enchant a slot keeps,
-- "TEMP" for the stone or oil you reapply. They are not alternatives to each
-- other — a weapon carries both — so ranking them in one list would be
-- comparing an enchant to a consumable.
function M.RankSlot(slotKey, role, filter, want)
    local list = bySlot[slotKey]
    if not list then return nil end
    local scored, unscored = {}, {}
    for _, entry in ipairs(list) do
        local isTemp = entry.kind == "TEMP"
        local wanted = (want == nil) or (want == "TEMP" and isTemp) or (want == "PERM" and not isTemp)
        if wanted and not entry.unobtainable and (not filter or filter(entry)) then
            local score = M.Score(entry, role)
            if score and score > 0 then
                scored[#scored + 1] = { entry = entry, score = score }
            else
                unscored[#unscored + 1] = { entry = entry }
            end
        end
    end
    table.sort(scored, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return (a.entry.name or "") < (b.entry.name or "")
    end)
    for _, row in ipairs(unscored) do
        scored[#scored + 1] = row
    end
    return scored
end

-- The best PERMANENT enhancement for a slot and role, ignoring what you own.
function M.BestFor(slotKey, role)
    local ranked = M.RankSlot(slotKey, role, nil, "PERM")
    local top = ranked and ranked[1]
    return top and top.score and top.entry or nil
end

-- ---------------------------------------------------------------------------
-- Rendering a source
-- ---------------------------------------------------------------------------

local function Money(copper)
    if not copper or copper <= 0 then return nil end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    if g > 0 then return s > 0 and ("%dg %ds"):format(g, s) or ("%dg"):format(g) end
    if s > 0 then return ("%ds"):format(s) end
    return ("%dc"):format(copper % 100)
end
M.Money = Money

local KIND_LABEL = {
    VENDOR = "Vendor", TRAINER = "Trainer", QUEST = "Quest", CRAFT = "Crafted",
    REP = "Reputation reward",
    RECIPE = "Recipe", DROP = "Drops", OBJECT = "Container", CONTAINER = "Inside",
    PROSPECT = "Prospecting", DISENCHANT = "Disenchanting", FISH = "Fishing",
    SKIN = "Skinning", PICKPOCKET = "Pickpocket", MAIL = "Mail",
}
M.KindLabel = KIND_LABEL

-- One source as a player would say it out loud. Everything the generator
-- captured gets a chance to appear: who, where, what it costs, what standing
-- it wants, how likely it is.
function M.SourceText(src)
    if not src then return "" end
    local out = KIND_LABEL[src.k] or src.k
    if src.k == "CRAFT" then
        if src.prof then
            out = ("%s (%s %s)"):format(out, src.prof.skill, tostring(src.prof.rank or "?"))
        end
        return out
    end
    if src.k == "REP" and src.faction then
        return ("%s: |cffffd200%s%s|r"):format(out, src.faction.name or "?",
            src.faction.standing and (" - " .. src.faction.standing) or "")
    end
    if src.name then out = out .. ": " .. src.name end
    if src.sub then out = out .. ", " .. src.sub end
    if src.zone then out = out .. " — " .. src.zone end
    if src.rank then out = out .. " (" .. src.rank .. ")" end
    if src.heroic then out = out .. " |cffff8040heroic|r" end
    if src.chance and src.chance > 0 and src.chance < 100 then
        out = out .. (" %.1f%%"):format(src.chance)
    end
    if src.faction and src.faction.name then
        out = out .. (" |cffffd200[%s%s]|r"):format(src.faction.name,
            src.faction.standing and (" - " .. src.faction.standing) or "")
    end
    if type(src.cost) == "table" and src.cost.tokens then
        for _, token in ipairs(src.cost.tokens) do
            out = out .. (" |cff00ccff%d× %s|r"):format(token.count, token.name or ("#" .. token.item))
        end
    end
    local price = Money(src.price)
    if price then out = out .. " |cffffffff" .. price .. "|r" end
    if src.stock then out = out .. (" |cff888888(%d in stock)|r"):format(src.stock) end
    return out
end

-- The whole acquisition story for one enhancement, flattened into lines:
-- the source, and under a craft, how the recipe itself is obtained.
function M.SourceLines(entry, max)
    local lines = {}
    if not entry then return lines end
    for _, src in ipairs(entry.src or {}) do
        lines[#lines + 1] = { depth = 0, text = M.SourceText(src) }
        if src.reagents then
            local parts = {}
            for _, r in ipairs(src.reagents) do
                parts[#parts + 1] = ("%d× %s"):format(r.count, r.name or ("#" .. r.item))
            end
            lines[#lines + 1] = { depth = 1, text = "|cff888888" .. table.concat(parts, ", ") .. "|r" }
        end
        for _, learn in ipairs(src.learn or {}) do
            lines[#lines + 1] = { depth = 1, text = M.SourceText(learn) }
            for _, deep in ipairs(learn.src or {}) do
                lines[#lines + 1] = { depth = 2, text = M.SourceText(deep) }
            end
        end
        if max and #lines >= max then break end
    end
    if #lines == 0 then
        lines[1] = { depth = 0, text = "|cff888888No known source in this build|r" }
    end
    return lines
end

-- A one-line summary for a list row: the best source, plus how many others.
function M.SourceSummary(entry)
    if not entry then return "" end
    local first = entry.src and entry.src[1]
    if not first then return "|cff888888No known source|r" end
    local text = M.SourceText(first)
    local extra = (#entry.src - 1) + (entry.more or 0)
    if extra > 0 then
        text = text .. (" |cff666666+%d more|r"):format(extra)
    end
    return text
end

-- ---------------------------------------------------------------------------
-- Full detail, for a tooltip
-- ---------------------------------------------------------------------------

-- The audit is wanted per tooltip and costs fourteen GetInventoryItemLink
-- calls, so it is cached for a moment. A second is short enough that a gem
-- socketed while a tooltip is up corrects itself before anyone reads it, and
-- long enough that hovering a bag of gems does not rescan the character
-- forty times.
local cachedReport, cachedAt
function M.Report()
    local now = GetTime and GetTime() or 0
    if cachedReport and cachedAt and (now - cachedAt) < 1 then
        return cachedReport
    end
    cachedReport = M.ScanGear("player")
    cachedAt = now
    return cachedReport
end

function M.InvalidateReport()
    cachedReport, cachedAt = nil, nil
end

local COLOR_TEXT = {
    META = "Meta", RED = "Red", YELLOW = "Yellow", BLUE = "Blue",
    PRISMATIC = "any",
}

-- Everything the database knows about one enhancement, as { depth, text }
-- lines. Nothing is truncated: this is what the player asked to see when they
-- put the pointer on it.
function M.DetailLines(entry)
    local out = {}
    if not entry then return out end
    local function add(depth, text)
        if text then out[#out + 1] = { depth = depth, text = text } end
    end

    local slots = {}
    for _, key in ipairs(entry.slots or {}) do
        slots[#slots + 1] = Data.SlotNames[key] or key
    end
    if entry.kind == "GEM" then
        local colors = {}
        for _, color in ipairs(entry.colors or {}) do
            colors[#colors + 1] = COLOR_TEXT[color] or color
        end
        add(0, ("|cff33ff99Fits:|r %s socket%s"):format(
            table.concat(colors, " or "), #colors == 1 and "" or "s"))
    elseif #slots > 0 then
        add(0, ("|cff33ff99Enhances:|r %s"):format(table.concat(slots, ", ")))
    end
    if entry.short then
        add(0, ("|cff33ff99Grants:|r %s"):format(entry.short))
    end
    if entry.recipe and entry.recipe ~= entry.name then
        add(0, ("|cff888888Enchant:|r %s"):format(entry.recipe))
    end

    -- Everything that gates it
    if entry.ilvl then
        add(0, ("|cff888888Needs an item of level %d or higher|r"):format(entry.ilvl))
    end
    if entry.reqSkill then
        add(0, ("|cffff8040Only usable by a %s%s|r"):format(entry.reqSkill.skill,
            entry.reqSkill.rank and (" (%d)"):format(entry.reqSkill.rank) or ""))
    end
    if entry.unique then
        local bits = {}
        if entry.unique.family then
            bits[#bits + 1] = ("%s (%d)"):format(entry.unique.family, entry.unique.max or 1)
        elseif entry.unique.equipped then
            bits[#bits + 1] = "unique-equipped"
        end
        if entry.unique.own then
            bits[#bits + 1] = ("you may own %d"):format(entry.unique.own)
        end
        if #bits > 0 then
            add(0, ("|cff888888Unique: %s|r"):format(table.concat(bits, ", ")))
        end
    end
    if entry.classes then
        add(0, ("|cff888888Only: %s|r"):format(table.concat(entry.classes, ", ")))
    end

    -- A meta gem's requirement, and whether YOUR gems currently meet it
    if entry.cond and entry.condText then
        local counts = M.Report().gemCounts
        local active = M.MetaActive(entry, counts or {})
        add(0, ("%s%s|r"):format(active and "|cff33ff99" or "|cffff4040", entry.condText))
        if counts then
            add(1, ("|cff888888you wear %d red, %d yellow, %d blue|r"):format(
                counts.RED or 0, counts.YELLOW or 0, counts.BLUE or 0))
        end
    end

    if entry.unobtainable then
        add(0, "|cffff4040No known source in this build|r")
        return out
    end

    add(0, "|cffffd200Sources|r")
    for _, src in ipairs(entry.src or {}) do
        add(1, M.SourceText(src))
        if src.reagents then
            local parts = {}
            for _, r in ipairs(src.reagents) do
                parts[#parts + 1] = ("%d× %s"):format(r.count, r.name or ("#" .. r.item))
            end
            add(2, ("|cff888888%s|r"):format(table.concat(parts, ", ")))
        end
        for _, learn in ipairs(src.learn or {}) do
            add(2, M.SourceText(learn))
            for _, deep in ipairs(learn.src or {}) do
                add(3, M.SourceText(deep))
            end
            if learn.more then
                add(3, ("|cff666666…and %d more|r"):format(learn.more))
            end
        end
    end
    if entry.more then
        add(1, ("|cff666666…and %d more|r"):format(entry.more))
    end
    return out
end

-- The verdict on a piece of GEAR: what is on it, what is missing, and what
-- belongs there. `role` is optional and only used to name a best pick.
function M.GearLines(link, role)
    local out = {}
    local function add(depth, text)
        if text then out[#out + 1] = { depth = depth, text = text } end
    end
    local parsed = ParseLink(link)
    if not parsed then return out end
    local slot = M.SlotOfLink(link)

    if slot then
        if parsed.enchant == 0 then
            if slot ~= "RING" or SkillRank("Enchanting") then
                add(0, "|cffff4040Not enchanted|r")
                local best = M.BestFor(slot, role)
                if best then
                    add(1, ("|cffffd200%s|r |cff888888%s|r"):format(
                        best.name, M.SourceSummary(best)))
                end
            else
                add(0, "|cff888888Enchantable only by an enchanter|r")
            end
        else
            local entry = M.EntryForEnchant(parsed.enchant)
            add(0, ("|cff33ff99%s|r"):format(
                entry and (entry.short or entry.name) or ("enchant #%d"):format(parsed.enchant)))
            if entry and entry.name and entry.short and entry.name ~= entry.short then
                add(1, ("|cff888888%s|r"):format(entry.name))
            end
        end
    end

    local judged = M.JudgeSockets(link, parsed)
    if judged then
        local placed = {}
        for socket, gem in pairs(judged.assign or {}) do
            placed[gem] = true
            local gemID = judged.gems[gem]
            local entry = byItem[gemID]
            add(0, ("|cff33ff99%s|r |cff888888in the %s socket|r"):format(
                entry and entry.name or ("gem #" .. tostring(gemID)),
                COLOR_TEXT[judged.sockets[socket]] or judged.sockets[socket]))
        end
        -- A gem that matched nothing is still socketed; it just earns nothing
        for i, gemID in ipairs(judged.gems) do
            if not placed[i] then
                local entry = byItem[gemID]
                add(0, ("|cffff8040%s|r |cff888888matches no socket on this item|r"):format(
                    entry and entry.name or ("gem #" .. tostring(gemID))))
            end
        end
        if judged.empty > 0 then
            add(0, ("|cffff4040%d empty socket%s|r"):format(
                judged.empty, judged.empty == 1 and "" or "s"))
        end
        if #judged.sockets > 0 and judged.empty == 0 and not judged.unknown then
            add(0, judged.bonus and "|cff33ff99Socket bonus earned|r"
                or "|cffff4040Socket bonus forfeited|r")
        end
    end

    -- If this item carries the meta, say whether the character activates it
    for _, gemID in ipairs(judged and judged.gems or {}) do
        local entry = byItem[gemID]
        if entry and entry.cond then
            local counts = M.Report().gemCounts or {}
            local active = M.MetaActive(entry, counts)
            add(0, ("%s%s is %s|r"):format(active and "|cff33ff99" or "|cffff4040",
                entry.name, active and "active" or "INACTIVE"))
            if not active then
                add(1, ("|cff888888%s — you wear %d red, %d yellow, %d blue|r"):format(
                    entry.condText or "", counts.RED or 0, counts.YELLOW or 0, counts.BLUE or 0))
            end
        end
    end
    return out
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
            elseif row.sockets and not row.bonus and not row.unknownGems then
                -- Filled, but not with matching colours: the socket bonus is
                -- being left on the table, which is a different mistake.
                out[#out + 1] = { row = row, kind = "BONUS",
                                  text = ("%s forfeits its socket bonus (%d of %d gems match)"):format(
                                      row.label, row.matched or 0, #row.sockets) }
            end
        end
    end
    -- The meta is one verdict for the whole character, so it is reported once
    -- rather than against the helm that happens to carry it.
    if report.meta and report.meta.active == false then
        out[#out + 1] = {
            row = report.meta.row, kind = "META",
            text = ("%s is inactive — %s"):format(report.meta.entry.name,
                report.meta.entry.condText or "its colour requirement is unmet"),
        }
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
