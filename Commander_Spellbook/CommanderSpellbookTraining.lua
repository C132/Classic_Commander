-- Commander Spellbook: what the trainer will teach you.
--
-- The suite's own "What's Training?". Every row a class trainer teaches this
-- class (CommanderSpellbookData's train table, from the CMaNGOS trainer
-- lists), filed by what stands between the character and it:
--
--   NOW      the level is reached and every rank before it is learned or
--            trainable in the same visit — the trip's shopping list
--   WEAPON   weapon skills a weapon master would teach this class now
--   SOON     within the next few levels (the SoonLevels setting)
--   NEEDS    the level is reached but an earlier rank is not to be had from
--            a trainer (a quest gives it, or it was never trained)
--   TALENT   the spell's first rank is a talent the character does not have
--   LATER    further off
--   IGNORED  the player told the list to leave it out
--
-- Learned means learned or replaced: a warrior with Heroic Strike 9 has no
-- Heroic Strike 8 in the book and is not about to train it (S.IsLearned).
-- A row the character's race cannot learn is never listed. Prices are the
-- trainer's base price: a trainer of a faction you are Honored or better
-- with asks less, which the cost tooltip says rather than guessing at.

CommanderSpellbook = CommanderSpellbook or {}
local S = CommanderSpellbook

S.TRAIN_ORDER = { "NOW", "WEAPON", "SOON", "NEEDS", "TALENT", "LATER", "IGNORED" }

local TRAIN_LABEL = {
    NOW = "Train Now",
    WEAPON = "Weapon Skills",
    SOON = "Coming Up",
    NEEDS = "Needs an Earlier Rank",
    TALENT = "Needs a Talent",
    LATER = "Later",
    IGNORED = "Ignored",
}

local TRAIN_TIP = {
    NOW = "Everything your class trainer will teach you on this visit, with what it costs together.",
    WEAPON = "Weapon skills a weapon master will teach your class now.",
    SOON = "What the trainer teaches in your next few levels.",
    NEEDS = "You are high enough, but an earlier rank has to come first and no trainer teaches it: it comes from a quest or a book, or it was skipped.",
    TALENT = "Higher ranks of a talent you have not taken. They appear in Train Now once the talent is yours.",
    LATER = "Everything further off.",
    IGNORED = "Spells you told this list to leave out. Select one and press Unignore to bring it back.",
}

function S.TrainLabel(key) return TRAIN_LABEL[key] or key end
function S.TrainTip(key) return TRAIN_TIP[key] end

local function CharDB()
    if S.EnsureCharDB then return S.EnsureCharDB() end
    return { Ignored = {} }
end

function S.IsIgnored(id)
    return id and CharDB().Ignored[id] and true or false
end

function S.SetIgnored(id, ignored)
    if not id then return end
    CharDB().Ignored[id] = ignored and true or nil
end

-- Copper as gold/silver/copper with the coin icons, the way the trainer
-- window writes it
function S.Money(copper)
    copper = math.floor(tonumber(copper) or 0)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper / 100) % 100
    local rest = copper % 100
    if gold > 0 then return string.format("%dg %ds %dc", gold, silver, rest) end
    if silver > 0 then return string.format("%ds %dc", silver, rest) end
    return string.format("%dc", rest)
end

local function ClassBit()
    local _, _, classID = UnitClass("player")
    if not classID then return nil end
    return 2 ^ (classID - 1)
end

-- A weapon skill is not a ranked spell: it gets a family of one, built here
local function WeaponFamily(id, weapon)
    return {
        key = "w:" .. id, name = S.SpellName(id) or ("Weapon skill " .. id),
        icon = S.SpellIcon(id), weapon = weapon, role = "WEAPON", bookType = "spell",
        ranks = { { id = id, level = weapon.level or 1, cost = weapon.cost or 0 } },
        unlearnedFamily = true, unlearned = true,
    }
end

local function LooseFamily(id, row)
    local family = {
        key = "t:" .. id, name = S.SpellName(id) or ("Spell " .. id), icon = S.SpellIcon(id),
        bookType = "spell", unlearnedFamily = true,
        ranks = { { id = id, level = row[1], cost = row[2], raceMask = row[3] } },
    }
    S.Assess(family)
    family.unlearned = not family.learned
    return family
end

local function EntryFor(family, id)
    for _, entry in ipairs(family.ranks) do
        if entry.id == id then return entry end
    end
    return nil
end

-- The status of one trainer row for this character, or nil when it is not
-- a thing to list (learned, or not this race's)
local function Status(family, entry, level, soon)
    if entry.learned then return nil end
    if entry.allowed == false then return nil end
    if S.IsIgnored(entry.id) then return "IGNORED" end
    local chain = family.chain
    if chain and chain.src == "L" and not S.IsLearned(chain.ranks[1]) then return "TALENT" end
    if entry.now then return "NOW" end
    local need = entry.level or 1
    if need > level then
        if need <= level + soon then return "SOON" end
        return "LATER"
    end
    return "NEEDS"
end

-- The earlier rank that blocks a NEEDS row, for its note
local function Blocker(family, entry)
    local previous
    for _, other in ipairs(family.ranks) do
        if other == entry then break end
        if not other.learned then previous = previous or other end
    end
    return previous
end

-- Everything the Training view lists.
--   training.groups   key -> { key, label, items, cost }
--   training.nowCost  the Train Now gold (weapon skills not included)
--   training.nowCount
--   item = { id, family, entry, level, cost, status, weapon, note }
function S.Training(book, opts)
    opts = opts or {}
    local level = book.level or UnitLevel("player") or 1
    local soon = tonumber(opts.soon) or 2
    local idx = S.Index()
    local training = { groups = {}, nowCost = 0, nowCount = 0, weaponCost = 0 }

    local function Add(status, item)
        local group = training.groups[status]
        if not group then
            group = { key = status, label = S.TrainLabel(status), items = {}, cost = 0 }
            training.groups[status] = group
        end
        item.status = status
        group.items[#group.items + 1] = item
        group.cost = group.cost + (item.cost or 0)
    end

    for id, row in pairs(idx.train) do
        -- A trainer row the class data has no chain for (a gap in the
        -- generated tables) still gets listed, as a family of one
        local family = S.FamilyFor(book, id) or LooseFamily(id, row)
        local entry = family and EntryFor(family, id)
        if entry then
            local status = Status(family, entry, level, soon)
            if status then
                local item = {
                    id = id, family = family, entry = entry,
                    level = entry.level or 1, cost = entry.cost or 0,
                }
                if status == "NEEDS" then
                    local blocker = Blocker(family, entry)
                    if blocker and blocker.rank then
                        item.note = string.format("Needs rank %d first", blocker.rank)
                    end
                elseif status == "TALENT" then
                    item.note = "Needs the talent"
                end
                Add(status, item)
            end
        end
    end

    local classBit = ClassBit()
    for id, weapon in pairs(idx.weapons) do
        if type(weapon) == "table" and S.HasBit(weapon.classMask, classBit) and not S.IsKnown(id) then
            local family = WeaponFamily(id, weapon)
            local need = weapon.level or 1
            local status
            if S.IsIgnored(id) then
                status = "IGNORED"
            elseif need <= level then
                status = "WEAPON"
            elseif need <= level + soon then
                status = "SOON"
            else
                status = "LATER"
            end
            Add(status, { id = id, family = family, entry = family.ranks[1],
                level = need, cost = weapon.cost or 0, weapon = weapon })
        end
    end

    for _, group in pairs(training.groups) do
        table.sort(group.items, function(a, b)
            if a.level ~= b.level then return a.level < b.level end
            local na, nb = a.family.name or "", b.family.name or ""
            if na ~= nb then return na < nb end
            return (a.entry.rank or 0) < (b.entry.rank or 0)
        end)
    end
    local now = training.groups.NOW
    training.nowCost = now and now.cost or 0
    training.nowCount = now and #now.items or 0
    local weapons = training.groups.WEAPON
    training.weaponCost = weapons and weapons.cost or 0
    return training
end

-- The Training view's rows: a header per status in TRAIN_ORDER, then its
-- items (a search keeps matching items and opens their group)
function S.BuildTrainRows(training, opts)
    opts = opts or {}
    local query = (opts.search or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local searching = query ~= ""
    local collapsed = opts.collapsed or {}
    local rows, shown = {}, 0
    for _, key in ipairs(S.TRAIN_ORDER) do
        local group = training.groups[key]
        if group then
            local items = {}
            for _, item in ipairs(group.items) do
                if not searching or (item.family.name or ""):lower():find(query, 1, true) then
                    items[#items + 1] = item
                end
            end
            if #items > 0 then
                local foldKey = "TRAIN:" .. key
                local isCollapsed = S.IsFolded(collapsed, foldKey) and not searching
                rows[#rows + 1] = { header = group, foldKey = foldKey, collapsed = isCollapsed, count = #items }
                if not isCollapsed then
                    for _, item in ipairs(items) do rows[#rows + 1] = { train = item } end
                end
                shown = shown + #items
            end
        end
    end
    return rows, shown
end

-- A family's "what the trainer says" in a line: nil when nothing is left
function S.NextRankWords(family, level)
    local entry = family and family.nextRank
    if not entry then return nil end
    level = level or UnitLevel("player") or 1
    if entry.now then
        return string.format("Rank %s trainable now", entry.rank or "?")
    end
    return string.format("Rank %s at level %d", entry.rank or "?", entry.level or 0)
end
