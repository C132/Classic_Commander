-- Commander Vault: the search language.
--
-- A bank search that only matches names is a search you stop using the second
-- time you cannot remember whether the shoulder enchant was a "Greater
-- Inscription" or an "Inscription of the Knight". So the box takes a small
-- query language instead:
--
--   frostweave            free text, matched against name, type, subtype and
--                         the localized slot name
--   "greater inscription" a quoted phrase, matched as one token
--   -tailoring            a leading minus excludes
--   q:epic  q:>=rare      quality, by name or by threshold
--   t:consumable          item type or subtype
--   s:head                equip slot
--   ilvl:>115             item level, with > >= < <= = or a bare number
--   n:>1                  stack count
--   boe / bop / bound      bind state
--   usable                items this character can actually equip
--   new / old:30           dwell time in the bank, in days
--
-- Every term is ANDed. That is deliberate: bank searches are narrowing
-- searches, and an OR would make the second word widen the result set, which
-- is the opposite of what typing a second word feels like it should do.

CommanderVault = CommanderVault or {}
local V = CommanderVault

local QUALITY_NAMES = {
    poor = 0, junk = 0, gray = 0, grey = 0,
    common = 1, white = 1,
    uncommon = 2, green = 2,
    rare = 3, blue = 3,
    epic = 4, purple = 4,
    legendary = 5, orange = 5,
    artifact = 6,
}

-- Long form first so "ilvl" is never parsed as "il" with a leftover "vl"
local FIELD_ALIASES = {
    quality = "quality", q = "quality", rarity = "quality",
    ilvl = "ilvl", il = "ilvl", level = "ilvl", lvl = "ilvl",
    type = "type", t = "type", class = "type",
    slot = "slot", s = "slot",
    count = "count", n = "count", stack = "count",
    old = "old", age = "old", days = "old",
    req = "req", rl = "req",
    bag = "bag",
}

local FLAG_WORDS = {
    boe = "boe", bop = "bop", bound = "bound", soulbound = "bound",
    usable = "usable", equippable = "equippable", gear = "equippable",
    junk = "junk", quest = "quest", new = "new",
    stackable = "stackable", partial = "partial",
    set = "set", sets = "set", kit = "set",
}

-- Splits on whitespace, keeping "quoted phrases" whole. Returns raw tokens
-- with their leading negation already stripped.
local function Tokenize(text)
    local tokens = {}
    local index, length = 1, #text
    while index <= length do
        local char = text:sub(index, index)
        if char == " " or char == "\t" then
            index = index + 1
        elseif char == '"' then
            local close = text:find('"', index + 1, true)
            if close then
                tokens[#tokens + 1] = { raw = text:sub(index + 1, close - 1), phrase = true }
                index = close + 1
            else
                tokens[#tokens + 1] = { raw = text:sub(index + 1), phrase = true }
                index = length + 1
            end
        else
            local space = text:find("[ \t]", index)
            local stop = space and (space - 1) or length
            tokens[#tokens + 1] = { raw = text:sub(index, stop) }
            index = stop + 1
        end
    end
    return tokens
end

local function ParseComparison(value)
    local op, rest = value:match("^([<>=]=?)%s*(.+)$")
    if not op then return "=", value end
    return op, rest
end

local function CompareNumber(actual, op, wanted)
    if not actual then return false end
    if op == ">" then return actual > wanted end
    if op == ">=" then return actual >= wanted end
    if op == "<" then return actual < wanted end
    if op == "<=" then return actual <= wanted end
    return actual == wanted
end

-- Turns the box's text into a term list. Always returns a table; an empty one
-- means "everything matches", which is what an empty box should mean.
function V.ParseQuery(text)
    local query = { terms = {}, text = text or "" }
    if not text or text == "" then return query end
    for _, token in ipairs(Tokenize(text:lower())) do
        local raw = token.raw
        local negate = false
        if not token.phrase then
            local head = raw:sub(1, 1)
            if head == "-" or head == "!" then
                negate = true
                raw = raw:sub(2)
            end
        end
        if raw ~= "" then
            local term = { negate = negate }
            local field, value = raw:match("^([%a]+):(.*)$")
            local alias = field and FIELD_ALIASES[field]
            if alias and not token.phrase then
                term.field = alias
                term.value = value
                if alias == "quality" then
                    local op, rest = ParseComparison(value)
                    term.op = op
                    term.number = QUALITY_NAMES[rest] or tonumber(rest)
                    if not term.number then
                        -- An unreadable quality is a text search, not a
                        -- silently-empty result
                        term.field = nil
                        term.value = raw
                    end
                elseif alias == "ilvl" or alias == "count" or alias == "old"
                    or alias == "req" or alias == "bag" then
                    local op, rest = ParseComparison(value)
                    term.op = op
                    term.number = tonumber(rest)
                    if not term.number then
                        term.field = nil
                        term.value = raw
                    end
                end
            elseif not token.phrase and FLAG_WORDS[raw] then
                term.field = "flag"
                term.value = FLAG_WORDS[raw]
            else
                term.value = raw
            end
            query.terms[#query.terms + 1] = term
        end
    end
    return query
end

function V.QueryIsEmpty(query)
    return not query or #query.terms == 0
end

-- The haystack a free-text term is matched against, built once per row and
-- memoized on it. Rebuilt when the item finishes loading, since the name is
-- the half that arrives late and the half people actually type.
local function Haystack(row)
    if row._hay and row._hayFull == row.full then return row._hay end
    local parts = {}
    if row.name then parts[#parts + 1] = row.name end
    if row.itemType then parts[#parts + 1] = row.itemType end
    if row.subType then parts[#parts + 1] = row.subType end
    if row.equipLoc and row.equipLoc ~= "" then
        parts[#parts + 1] = _G[row.equipLoc] or row.equipLoc
    end
    local section = row.section and V.SectionTitle(row.section)
    if section then parts[#parts + 1] = section end
    row._hay = table.concat(parts, " "):lower()
    row._hayFull = row.full
    return row._hay
end

local ARMOR_CLASS = 4
local ARMOR_SUBCLASS_BY_CLASS = {
    WARRIOR = 4, PALADIN = 4, HUNTER = 3, SHAMAN = 3,
    ROGUE = 2, DRUID = 2, PRIEST = 1, MAGE = 1, WARLOCK = 1,
}

-- "Can this character wear this" — deliberately coarse. It answers the armor
-- class question (which is what a bank full of quest greens is really about)
-- and the level requirement, and leaves weapon skills alone rather than
-- pretending to know which ones the player has trained.
function V.RowUsable(row)
    if not row.full then return nil end
    if row.equipLoc == nil or row.equipLoc == "" then return nil end
    if (row.minLevel or 0) > (UnitLevel("player") or 70) then return false end
    if row.classID == ARMOR_CLASS and (row.subClassID or 0) >= 1 and (row.subClassID or 0) <= 4 then
        local _, class = UnitClass("player")
        local wanted = ARMOR_SUBCLASS_BY_CLASS[class or ""]
        -- Below the level where a class trains its final armor type, the
        -- lighter types are still legitimately worn
        if wanted and row.subClassID > wanted then return false end
    end
    return true
end

local function MatchFlag(row, flag)
    if flag == "boe" then
        return (row.bindType == 2 or row.bindType == 3) and row.bound ~= true
    elseif flag == "bop" then
        return row.bindType == 1
    elseif flag == "bound" then
        return row.bound == true or row.bindType == 1
    elseif flag == "usable" then
        return V.RowUsable(row) == true
    elseif flag == "equippable" then
        return row.equipLoc ~= nil and row.equipLoc ~= ""
    elseif flag == "junk" then
        return row.quality == 0
    elseif flag == "quest" then
        return row.isQuest == true
    elseif flag == "new" then
        local days = V.DwellDays(row.itemID)
        return days ~= nil and days < 1
    elseif flag == "stackable" then
        return (row.maxStack or 1) > 1
    elseif flag == "partial" then
        return (row.maxStack or 1) > 1 and (row.count or 1) < row.maxStack
    elseif flag == "set" then
        return V.SetWanting(row.itemID) ~= nil
    end
    return false
end

local function MatchTerm(row, term)
    if term.field == "quality" then
        return CompareNumber(row.quality, term.op, term.number)
    elseif term.field == "ilvl" then
        return CompareNumber(row.ilvl, term.op, term.number)
    elseif term.field == "count" then
        return CompareNumber(row.count, term.op, term.number)
    elseif term.field == "req" then
        return CompareNumber(row.minLevel, term.op, term.number)
    elseif term.field == "bag" then
        return CompareNumber(row.bag, term.op, term.number)
    elseif term.field == "old" then
        local days = V.DwellDays(row.itemID)
        if not days then return false end
        -- A bare "old:30" reads as "at least thirty days", which is how the
        -- word is used out loud; explicit operators still win
        local op = term.op == "=" and ">=" or term.op
        return CompareNumber(days, op, term.number)
    elseif term.field == "type" then
        local itemType = (row.itemType or ""):lower()
        local subType = (row.subType or ""):lower()
        local section = (V.SectionTitle(row.section) or ""):lower()
        return itemType:find(term.value, 1, true) ~= nil
            or subType:find(term.value, 1, true) ~= nil
            or section:find(term.value, 1, true) ~= nil
    elseif term.field == "slot" then
        local slotName = (row.equipLoc ~= "" and (_G[row.equipLoc] or row.equipLoc) or ""):lower()
        return slotName:find(term.value, 1, true) ~= nil
    elseif term.field == "flag" then
        return MatchFlag(row, term.value)
    end
    return Haystack(row):find(term.value, 1, true) ~= nil
end

function V.MatchRow(row, query)
    if V.QueryIsEmpty(query) then return true end
    for _, term in ipairs(query.terms) do
        local hit = MatchTerm(row, term) and true or false
        if term.negate then hit = not hit end
        if not hit then return false end
    end
    return true
end

-- Convenience for callers holding raw text rather than a parsed query
function V.Filter(rows, text)
    local query = V.ParseQuery(text)
    if V.QueryIsEmpty(query) then return rows end
    local out = {}
    for _, row in ipairs(rows) do
        if V.MatchRow(row, query) then out[#out + 1] = row end
    end
    return out
end
