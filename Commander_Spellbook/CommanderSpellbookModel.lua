-- Commander Spellbook: the model.
--
-- The stock book lists every rank of a spell as a separate button (Flash
-- Heal 1 through 9 is nine buttons over two pages) and files them under
-- tabs. This file reads the same book into FAMILIES: one entry per spell,
-- carrying all of its ranks — the ones you know, and from the generated
-- class data (CommanderSpellbookData.lua) the ones you have not trained yet,
-- with the level and the gold each comes at. The window draws families; the
-- Training view and the badges read the ranks.
--
-- Why the class data and not just the book: with the client's "Show all
-- spell ranks" box unticked the book reports only the highest rank of each
-- spell, so the lower ones would simply not exist here. The rank chains in
-- the data (SkillLineAbility's SupercedesSpell links) know every rank, and
-- IsPlayerSpell answers for each one whether this character has it. A rank's
-- NUMBER comes from its place in the chain, so nothing waits on the client's
-- asynchronous subtext (Rank Check's whole bug, see its harness README); a
-- spell the data does not know (a racial, a profession) falls back to the
-- subtext, loaded when it is not yet in hand.
--
-- Nothing here draws. Everything reads the client fresh on each Scan; the
-- one thing kept across scans is the rank index built from the data.

CommanderSpellbook = CommanderSpellbook or {}
local S = CommanderSpellbook

local BOOK = "spell"
local PETBOOK = "pet"

-- ---------------------------------------------------------------------------
-- Groups
-- ---------------------------------------------------------------------------

-- The role view's foldouts, in the order they are listed. The class trees
-- come from the generated data's role per rank chain; Racial, Professions and
-- General are the stock book's General tab, split by what the spell is.
S.ROLE_ORDER = {
    "HEAL", "DAMAGE", "CONTROL", "DEFENSE", "BUFF", "FORM", "UTILITY", "TRAVEL", "PET",
    "PETBOOK", "RACIAL", "PROFESSION", "GENERAL", "OTHER", "PASSIVE", "UNLEARNED",
}

local ROLE_LABEL = {
    HEAL = "Healing",
    DAMAGE = "Damage",
    CONTROL = "Crowd Control",
    DEFENSE = "Defensive",
    BUFF = "Buffs",
    FORM = "Stances & Forms",
    UTILITY = "Utility",
    TRAVEL = "Travel",
    PET = "Pet",
    PETBOOK = "Pet Abilities",
    RACIAL = "Racial",
    PROFESSION = "Professions",
    GENERAL = "General",
    OTHER = "Other",
    PASSIVE = "Passives",
    UNLEARNED = "Not Learned Yet",
}

-- "Stances & Forms" says it for every class at once; each class has one word
-- for its own
local FORM_LABEL = {
    WARRIOR = "Stances", PALADIN = "Auras", HUNTER = "Aspects", DRUID = "Forms",
    PRIEST = "Forms", SHAMAN = "Forms", ROGUE = "Stealth", WARLOCK = "Forms", MAGE = "Forms",
}

-- What each role foldout holds, for its header tooltip
local ROLE_TIP = {
    HEAL = "Heals, heals over time and the shields you put on others.",
    DAMAGE = "Direct damage, damage over time and weapon strikes.",
    CONTROL = "Stuns, fears, roots, silences, interrupts, snares and the rest of the toolkit that stops someone acting.",
    DEFENSE = "Immunities, damage reduction, escapes and threat drops.",
    BUFF = "Long buffs on yourself and your group.",
    FORM = "The stance, form, aura or aspect you stand in.",
    UTILITY = "Dispels, resurrection, conjuring, tracking and the rest.",
    TRAVEL = "Teleports, portals and the mounts you summon.",
    PET = "Summoning and looking after your pet.",
    PETBOOK = "Your pet's own spellbook. Right-click an autocast ability to turn its autocast on or off.",
    RACIAL = "Your race's own abilities.",
    PROFESSION = "Your professions and their gathering and helper spells.",
    GENERAL = "Attack, ranged attacks and the rest of the stock book's General tab.",
    OTHER = "Spells the role data does not know.",
    PASSIVE = "Passive spells: nothing to press, listed so the book is complete.",
    UNLEARNED = "Class spells you have not learned yet. The talent trees are the stock book's own tabs, and a spell you have never had is on none of them.",
}

local function PlayerClass()
    local _, class = UnitClass("player")
    return class
end

function S.GroupLabel(key, book)
    if key == "FORM" then return FORM_LABEL[PlayerClass() or ""] or ROLE_LABEL.FORM end
    if key == "PETBOOK" and book and book.petLabel then return book.petLabel end
    local tab = type(key) == "string" and key:match("^tab(%d+)$")
    if tab and book and book.tabs and book.tabs[tonumber(tab)] then
        return book.tabs[tonumber(tab)].name
    end
    return ROLE_LABEL[key] or key
end

function S.GroupTip(key)
    return ROLE_TIP[key]
end

-- ---------------------------------------------------------------------------
-- The class data's index
--
-- Built once per class: every rank's chain and place in it. The data is a
-- plain table so the harness can hand in a fixture; Reindex drops the cache.
-- ---------------------------------------------------------------------------

local index

function S.Reindex() index = nil end

function S.ClassData()
    local data = CommanderSpellbookData
    local class = PlayerClass()
    return data and data.classes and class and data.classes[class] or nil
end

local function Index()
    if index then return index end
    index = { rankOf = {}, chains = {}, train = {}, general = {}, weapons = {} }
    local data = CommanderSpellbookData
    if type(data) == "table" then
        index.general = type(data.general) == "table" and data.general or {}
        index.weapons = type(data.weapons) == "table" and data.weapons or {}
    end
    local class = S.ClassData()
    if type(class) ~= "table" then return index end
    index.train = type(class.train) == "table" and class.train or {}
    for _, chain in ipairs(class.chains or {}) do
        if type(chain.ranks) == "table" and chain.ranks[1] then
            index.chains[#index.chains + 1] = chain
            local first = chain.first or 1
            for position, id in ipairs(chain.ranks) do
                index.rankOf[id] = { chain = chain, position = position, rank = first + position - 1 }
            end
        end
    end
    return index
end

S.Index = Index

-- The race bit the data's masks use: 2^(raceID - 1)
local function RaceBit()
    local _, _, raceID = UnitRace("player")
    if not raceID then return nil end
    return 2 ^ (raceID - 1)
end

local function HasBit(mask, bit)
    if not (mask and bit) then return true end
    return math.floor(mask / bit) % 2 == 1
end

S.HasBit = HasBit

-- Whether this character's race may learn a trainer row (nil mask = anyone)
function S.RaceAllows(mask)
    if not mask then return true end
    return HasBit(mask, RaceBit())
end

-- ---------------------------------------------------------------------------
-- Spell facts
-- ---------------------------------------------------------------------------

-- Known: the character has this exact spell. C_SpellBook.IsSpellKnown is
-- the one that answers for a lower rank the book is not listing (Show all
-- spell ranks unticked); IsSpellInSpellBook for what the book lists. The
-- old IsPlayerSpell / IsSpellKnown globals are only wrappers over these in
-- Blizzard_DeprecatedSpellBook, defined only while the loadDeprecationFallbacks
-- CVar is on, so they are the fallback, never the first ask.
function S.IsKnown(id)
    if not id then return false end
    local spellBook = C_SpellBook
    if spellBook then
        if spellBook.IsSpellKnown and spellBook.IsSpellKnown(id) then return true end
        if spellBook.IsSpellInSpellBook and spellBook.IsSpellInSpellBook(id) then return true end
    end
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if IsSpellKnown and IsSpellKnown(id) then return true end
    return false
end

-- Learned: known, or behind a rank that is. Several warrior and rogue ranks
-- REPLACE the one before (the lower rank leaves the book), so "is rank 3
-- known" can be false for someone holding rank 5 — and nobody can train it
-- again. Training asks this, not IsKnown.
function S.IsLearned(id)
    if S.IsKnown(id) then return true end
    local info = Index().rankOf[id]
    if not info then return false end
    local ranks = info.chain.ranks
    for position = info.position + 1, #ranks do
        if S.IsKnown(ranks[position]) then return true end
    end
    return false
end

function S.SpellName(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellName then
        local name = C_Spell.GetSpellName(id)
        if name and name ~= "" then return name end
    end
    if GetSpellInfo then
        local name = GetSpellInfo(id)
        if name and name ~= "" then return name end
    end
    return nil
end

function S.SpellIcon(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellTexture then
        local icon = C_Spell.GetSpellTexture(id)
        if icon then return icon end
    end
    if GetSpellTexture then
        local ok, icon = pcall(GetSpellTexture, id)
        if ok and icon then return icon end
    end
    return nil
end

-- The subtext, for a spell the class data does not chain. Empty until the
-- client has the spell's text; a load is asked for once per spell and the
-- window repaints when it lands (S.onTextLoaded).
local textAsked = {}

local function Subtext(id)
    if not id then return nil end
    local text
    if C_Spell and C_Spell.GetSpellSubtext then text = C_Spell.GetSpellSubtext(id) end
    if (not text or text == "") and GetSpellSubtext then text = GetSpellSubtext(id) end
    if text and text ~= "" then return text end
    if not textAsked[id] and Spell and Spell.CreateFromSpellID then
        textAsked[id] = true
        local spell = Spell:CreateFromSpellID(id)
        if spell and not spell:IsSpellEmpty() then
            spell:ContinueOnSpellLoad(function()
                if S.onTextLoaded then S.onTextLoaded(id) end
            end)
        end
    end
    return nil
end

local function RankFromText(text)
    return text and tonumber(tostring(text):match("(%d+)")) or nil
end

-- The rank number of a spell: its place in the data's chain, else the
-- subtext. nil for a spell with no ranks (Blink) or one whose text has not
-- arrived.
function S.RankOf(id)
    local info = Index().rankOf[id]
    if info then
        if #info.chain.ranks > 1 or (info.chain.first or 1) > 1 then return info.rank end
        return nil
    end
    return RankFromText(Subtext(id))
end

-- ---------------------------------------------------------------------------
-- Scanning the book
-- ---------------------------------------------------------------------------

local function NewRank(id, rank)
    return { id = id, rank = rank }
end

-- A family's every rank from the chain, filled with what the character has
-- and what the trainer asks for each
local function FillChain(family, chain)
    local idx = Index()
    local first = chain.first or 1
    local byId = {}
    for _, entry in ipairs(family.ranks) do byId[entry.id] = entry end
    local ranks = {}
    for position, id in ipairs(chain.ranks) do
        local entry = byId[id] or NewRank(id)
        entry.rank = (#chain.ranks > 1 or first > 1) and (first + position - 1) or nil
        local train = idx.train[id]
        if train then
            entry.level, entry.cost, entry.raceMask = train[1], train[2], train[3]
        end
        ranks[#ranks + 1] = entry
    end
    -- A rank the book listed that the chain does not know (a data gap) keeps
    -- its place at the end rather than vanishing
    local inChain = {}
    for _, id in ipairs(chain.ranks) do inChain[id] = true end
    for _, entry in ipairs(family.ranks) do
        if not inChain[entry.id] then ranks[#ranks + 1] = entry end
    end
    family.ranks = ranks
end

-- Known / learned / trainable for every rank, and the family's summary:
-- the highest rank in hand, the next one to train and how many can be
-- trained right now
local function Assess(family, level)
    family.highest, family.nextRank = nil, nil
    family.trainableNow, family.learnedCount = 0, 0
    local available = true
    for _, entry in ipairs(family.ranks) do
        entry.known = entry.slot ~= nil or S.IsKnown(entry.id)
        entry.learned = entry.known or S.IsLearned(entry.id)
        if entry.known then family.highest = entry end
        if entry.learned then
            family.learnedCount = family.learnedCount + 1
        else
            local allowed = S.RaceAllows(entry.raceMask)
            entry.allowed = allowed
            if allowed and entry.level then
                -- Trainable now: the level is reached and every rank before
                -- it is learned or trainable now too (a trainer teaches rank
                -- 4 and then rank 5 in the same visit)
                entry.now = available and entry.level <= level
                if entry.now then family.trainableNow = family.trainableNow + 1 end
                if not family.nextRank then family.nextRank = entry end
            end
            if not entry.now then available = false end
        end
    end
    family.total = #family.ranks
    family.learned = family.learnedCount > 0
end

function S.Assess(family)
    Assess(family, UnitLevel("player") or 1)
end

-- The general category of a General-tab spell: the data's word for it, else
-- GENERAL
local function GeneralOf(id)
    local general = Index().general
    return (id and general[id]) or "GENERAL"
end

-- A chain by its spell's name, for a book spell whose id the data does not
-- chain but whose name it knows: the paladin's starting Seal of
-- Righteousness (20154) is replaced at level 4 by the 21084 the chain starts
-- from, and is the same spell to the player. Built on first use per class.
local function ChainByName(name)
    local idx = Index()
    if not idx.byName then
        idx.byName = {}
        for _, chain in ipairs(idx.chains) do
            local chainName = S.SpellName(chain.ranks[1])
            if chainName and not idx.byName[chainName] then idx.byName[chainName] = chain end
        end
    end
    return idx.byName[name]
end

local PET_COMMANDS = {
    "PET_ACTION_ATTACK", "PET_ACTION_FOLLOW", "PET_ACTION_WAIT", "PET_ACTION_MOVE_TO",
    "PET_MODE_AGGRESSIVE", "PET_MODE_DEFENSIVE", "PET_MODE_PASSIVE", "PET_MODE_ASSIST",
}

local function AddBookEntry(book, families, tab, slot, bookType)
    local slotType, itemID = GetSpellBookItemInfo(slot, bookType)
    if slotType == "FUTURESPELL" then return end
    local name, _, spellID = GetSpellBookItemName(slot, bookType)
    spellID = spellID or itemID
    if not name or name == "" then return end
    local passive = IsPassiveSpell and IsPassiveSpell(slot, bookType) and true or false
    local info = spellID and Index().rankOf[spellID]
    if not info and bookType == BOOK and tab ~= 1 then
        local chain = ChainByName(name)
        if chain then info = { chain = chain } end
    end
    local key
    if bookType == PETBOOK then
        key = "pet:" .. name
    elseif info then
        key = info.chain.ranks[1]
    else
        key = "n:" .. name
    end
    local family = families[key]
    if not family then
        family = {
            key = key, name = name, ranks = {}, bookType = bookType,
            tab = tab, passive = passive, chain = info and info.chain or nil,
        }
        families[key] = family
        book.list[#book.list + 1] = family
    end
    -- The highest rank's icon and passive flag speak for the family
    family.icon = (GetSpellTexture and GetSpellTexture(slot, bookType)) or family.icon
    family.passive = family.passive and passive
    local entry
    for _, existing in ipairs(family.ranks) do
        if existing.id == spellID then entry = existing break end
    end
    if not entry then
        entry = NewRank(spellID)
        family.ranks[#family.ranks + 1] = entry
    end
    entry.slot = slot
    -- The pet book can hold its commands (Attack, Follow, Stay, the
    -- stances): not spells, nothing a cast-by-name could do. They drag from
    -- their slot like the rest and get no cast button.
    if bookType == PETBOOK then
        for _, key in ipairs(PET_COMMANDS) do
            if _G[key] and _G[key] == name then entry.command = true end
        end
    end
    if bookType == PETBOOK and GetSpellAutocast then
        local allowed, enabled = GetSpellAutocast(slot, bookType)
        entry.autocast = allowed and true or false
        entry.autocastOn = enabled and true or false
    end
end

-- Roles: the chain's role from the data; a passive spell outside the General
-- tab files under PASSIVE whatever its chain says (the role view's last
-- foldout), a General-tab spell under the data's general word
local function Classify(family)
    if family.bookType == PETBOOK then
        family.role = "PETBOOK"
        return
    end
    if family.tab == 1 then
        local id = family.ranks[1] and family.ranks[1].id
        family.role = GeneralOf(id)
        return
    end
    if family.passive then
        family.role = "PASSIVE"
        return
    end
    family.role = (family.chain and family.chain.role) or "OTHER"
    if family.role == "PASSIVE" and not family.passive then family.role = "OTHER" end
end

-- A spell's chain as a family the book does not list (never learned): for
-- the Training view, a search, and Show Unlearned. tab is the tree the
-- role lookups need nothing from, so it stays nil.
local function UnlearnedFamily(chain)
    local first = chain.ranks[1]
    local family = {
        key = first, name = S.SpellName(first) or ("Spell " .. first), ranks = {},
        bookType = BOOK, chain = chain, unlearnedFamily = true,
        icon = S.SpellIcon(first), passive = chain.role == "PASSIVE",
    }
    family.role = chain.role or "OTHER"
    return family
end

-- Read the whole book.
--   book.list      every family, the book's and (opts.unlearned) the class
--                  data's chains the character has never touched
--   book.families  key -> family (the chain's first rank id, "n:<name>" for a
--                  spell the data does not chain, "pet:<name>" for the pet)
--   book.tabs      the stock book's tabs { name, texture } (1 = General)
--   book.petLabel  "Demon Abilities" etc. when a pet with a book is out
function S.Scan(opts)
    opts = opts or {}
    local level = UnitLevel("player") or 1
    local book = { list = {}, families = {}, tabs = {}, level = level }
    local families = book.families

    local numTabs = GetNumSpellTabs and GetNumSpellTabs() or 0
    for tab = 1, numTabs do
        local name, texture, offset, numSlots = GetSpellTabInfo(tab)
        book.tabs[tab] = { name = name or ("Tab " .. tab), texture = texture }
        if offset and numSlots then
            for slot = offset + 1, offset + numSlots do
                AddBookEntry(book, families, tab, slot, BOOK)
            end
        end
    end

    local numPet, petToken = 0, nil
    if HasPetSpells then numPet, petToken = HasPetSpells() end
    numPet = tonumber(numPet) or 0
    if numPet > 0 and (not PetHasSpellbook or PetHasSpellbook()) then
        local petType = petToken and _G["PET_TYPE_" .. petToken]
        book.petLabel = petType and (petType .. " Abilities") or "Pet Abilities"
        for slot = 1, numPet do
            AddBookEntry(book, families, nil, slot, PETBOOK)
        end
    end

    if opts.unlearned then
        for _, chain in ipairs(Index().chains) do
            local key = chain.ranks[1]
            if not families[key] then
                local family = UnlearnedFamily(chain)
                families[key] = family
                book.list[#book.list + 1] = family
            end
        end
    end

    for _, family in ipairs(book.list) do
        if family.chain then FillChain(family, family.chain) end
        Assess(family, level)
        if family.unlearnedFamily then
            -- A chain whose rank 1 a quest or a talent gives, or one the
            -- character's race never gets, is not something to list as
            -- "unlearned" in the book: Training says what it needs
            family.unlearned = not family.learned
        else
            Classify(family)
        end
        -- Rank numbers for a spell the data does not chain
        if not family.chain then
            for _, entry in ipairs(family.ranks) do
                entry.rank = entry.rank or RankFromText(Subtext(entry.id))
            end
            table.sort(family.ranks, function(a, b) return (a.rank or 0) < (b.rank or 0) end)
            family.highest = nil
            for _, entry in ipairs(family.ranks) do
                if entry.known then family.highest = entry end
            end
        end
    end
    return book
end

-- A family's chain, built on its own when the book does not list it — for
-- a trainer row that names a spell nobody has learned yet
function S.FamilyFor(book, id)
    local info = Index().rankOf[id]
    local key = info and info.chain.ranks[1] or nil
    if key and book.families[key] then return book.families[key] end
    if not info then return nil end
    local family = UnlearnedFamily(info.chain)
    FillChain(family, info.chain)
    Assess(family, book.level or UnitLevel("player") or 1)
    family.unlearned = not family.learned
    book.families[key] = family
    return family
end

-- ---------------------------------------------------------------------------
-- The Spells view's rows
-- ---------------------------------------------------------------------------

local function Lower(text) return (text or ""):lower() end

local function Matches(family, query, groupLabel)
    if query == "" then return true end
    if Lower(family.name):find(query, 1, true) then return true end
    return groupLabel and Lower(groupLabel):find(query, 1, true) and true or false
end

local function GroupKey(family, groupBy)
    if groupBy == "TREE" then
        if family.bookType == PETBOOK then return "PETBOOK" end
        if family.tab then return "tab" .. family.tab end
        return "UNLEARNED"
    end
    return family.role or "OTHER"
end

-- Foldouts that start shut until the player opens them: nothing to press
-- in Passives, and the far end of the Training list. A stored false is an
-- explicit "open", which is why the table holds booleans, not just trues.
S.DEFAULT_FOLDED = {
    ["ROLE:PASSIVE"] = true,
    ["TRAIN:LATER"] = true,
    ["TRAIN:TALENT"] = true,
    ["TRAIN:IGNORED"] = true,
    ["CHECK:CURRENT"] = true,
}

function S.IsFolded(collapsed, foldKey)
    local value = collapsed and collapsed[foldKey]
    if value == nil then return S.DEFAULT_FOLDED[foldKey] or false end
    return value and true or false
end

-- Header/item rows for the navigator.
--   opts.search      text typed (any case)
--   opts.groupBy     "ROLE" | "TREE"
--   opts.collapsed   "<view>:<group>" -> true
--   opts.passives    list passive spells
--   opts.unlearned   list families the character has not learned
-- Returns rows, shown (families listed), total (families known).
function S.BuildBookRows(book, opts)
    opts = opts or {}
    local groupBy = opts.groupBy == "TREE" and "TREE" or "ROLE"
    local query = Lower(opts.search):gsub("^%s+", ""):gsub("%s+$", "")
    local collapsed = opts.collapsed or {}
    local searching = query ~= ""

    local groups, order = {}, {}
    local total = 0
    for _, family in ipairs(book.list) do
        if not family.unlearnedFamily then total = total + 1 end
        local show = true
        if family.passive and not opts.passives then show = false end
        if family.unlearnedFamily then
            -- An unlearned spell is listed when asked for, or named by a
            -- search, and never when the character's race cannot have it
            local first = family.ranks[1]
            if not (family.unlearned and (opts.unlearned or searching)) then show = false end
            if first and first.allowed == false then show = false end
        end
        if show then
            local key = GroupKey(family, groupBy)
            local label = S.GroupLabel(key, book)
            if Matches(family, query, label) then
                local group = groups[key]
                if not group then
                    group = { key = key, label = label, items = {}, known = 0 }
                    groups[key] = group
                    order[#order + 1] = group
                end
                group.items[#group.items + 1] = family
                if not family.unlearnedFamily then group.known = group.known + 1 end
            end
        end
    end

    -- Groups in the role order, or the stock book's tab order
    local rank = {}
    if groupBy == "TREE" then
        for tab = 1, #(book.tabs or {}) do rank["tab" .. tab] = tab end
        rank.PETBOOK = 100
    end
    for position, key in ipairs(S.ROLE_ORDER) do
        rank[key] = rank[key] or (200 + position)
    end
    table.sort(order, function(a, b)
        local ra, rb = rank[a.key] or 999, rank[b.key] or 999
        if ra ~= rb then return ra < rb end
        return a.label < b.label
    end)

    local rows, shown = {}, 0
    local view = groupBy
    for _, group in ipairs(order) do
        table.sort(group.items, function(a, b)
            -- Learned first, then by name: an unlearned spell sits under
            -- the ones you have rather than among them
            if (a.unlearnedFamily or false) ~= (b.unlearnedFamily or false) then
                return not a.unlearnedFamily
            end
            return a.name < b.name
        end)
        local foldKey = view .. ":" .. group.key
        -- A search opens every group it found something in: a match
        -- hidden in a folded group is no match
        local isCollapsed = S.IsFolded(collapsed, foldKey) and not searching
        rows[#rows + 1] = { header = group, foldKey = foldKey, collapsed = isCollapsed }
        if not isCollapsed then
            for _, family in ipairs(group.items) do
                rows[#rows + 1] = { family = family }
            end
        end
        shown = shown + #group.items
    end
    return rows, shown, total
end

-- The first family the rows list, for a selection that has gone
function S.FirstFamily(rows)
    for _, row in ipairs(rows) do
        if row.family then return row.family end
    end
    return nil
end
