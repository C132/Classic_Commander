-- Commander Buffs: the priority engine — pure Lua, zero frames, zero Unit*
-- calls. The UI scans the player's auras and hands this engine plain
-- tables; the engine owns everything that must be exact and testable: which
-- rule claims an aura, what that aura scores, and which one wins the
-- portrait.
--
-- The model is an ORDERED policy, not a bag of filters. For each aura the
-- FIRST rule whose matcher accepts it claims that aura and sets its base
-- score; later rules never see it. That is what makes the editor's list
-- readable top-to-bottom, and what makes a HIDE rule a one-line veto
-- instead of a separate blacklist system.
--
-- Final score = base + expiring bonus + per-stack bonus. Ties break on
-- LEAST time remaining (the thing about to matter wins), then on rule
-- order, then on spell id so the order is fully deterministic — a portrait
-- icon that flickers between two equal auras is worse than either.

CommanderBuffsEngine = {}
local E = CommanderBuffsEngine

local floor = math.floor
local sort = table.sort

E.VERSION = 1

-- Every dispel school this client can put on the player, plus the NONE
-- pseudo-school so "undispellable debuff" is expressible in a matcher.
E.DISPEL_SCHOOLS = { "Magic", "Curse", "Disease", "Poison", "NONE" }

-- ---------------------------------------------------------------------------
-- Curated spell id sets used by the shipped rules. Ids are BASE ids: every
-- rank of a spell shares its base id in the aura data on this client, so an
-- id list stays both rank-proof and locale-proof (a name list is neither).
-- ---------------------------------------------------------------------------

-- Loss of control: stuns, fears, incapacitates, silences. These are the
-- auras where knowing instantly changes what you press next.
E.CC_IDS = {
    118,    -- Polymorph
    3355,   -- Freezing Trap Effect
    122,    -- Frost Nova
    339,    -- Entangling Roots
    2637,   -- Hibernate
    33786,  -- Cyclone
    5211,   -- Bash
    9005,   -- Pounce
    22570,  -- Maim
    5782,   -- Fear
    5484,   -- Howl of Terror
    6358,   -- Seduction
    6789,   -- Death Coil
    8122,   -- Psychic Scream
    605,    -- Mind Control
    15487,  -- Silence
    453,    -- Mind Soothe (harmless, but it is a control aura)
    853,    -- Hammer of Justice
    20066,  -- Repentance
    2094,   -- Blind
    1776,   -- Gouge
    6770,   -- Sap
    408,    -- Kidney Shot
    1833,   -- Cheap Shot
    1330,   -- Garrote - Silence
    5246,   -- Intimidating Shout
    7922,   -- Charge Stun
    20253,  -- Intercept Stun
    12809,  -- Concussion Blow
    12355,  -- Impact (stun)
    15269,  -- Blackout
    19503,  -- Scatter Shot
    19386,  -- Wyvern Sting
    19577,  -- Intimidation
    30283,  -- Shadowfury
    24259,  -- Spell Lock (silence)
    18469,  -- Counterspell - Silenced
    34490,  -- Silencing Shot
    28730,  -- Arcane Torrent (silence)
    710,    -- Banish
    9484,   -- Shackle Undead
    2878,   -- Turn Undead
}

-- The defensive and burst cooldowns that decide a fight while they are up.
-- Class-agnostic on purpose: you only ever have your own class's auras, so
-- one list costs nothing and needs no class detection to stay correct.
E.MAJOR_IDS = {
    45438,  -- Ice Block
    642,    -- Divine Shield
    498,    -- Divine Protection
    1022,   -- Blessing of Protection
    31224,  -- Cloak of Shadows
    5277,   -- Evasion
    871,    -- Shield Wall
    12975,  -- Last Stand
    22812,  -- Barkskin
    33206,  -- Pain Suppression
    10060,  -- Power Infusion
    2565,   -- Shield Block
    1719,   -- Recklessness
    20230,  -- Retaliation
    19263,  -- Deterrence
    8178,   -- Grounding Totem Effect
    30823,  -- Shamanistic Rage
    16188,  -- Nature's Swiftness
    29166,  -- Innervate
    3045,   -- Rapid Fire
    19574,  -- Bestial Wrath
    2825,   -- Bloodlust
    32182,  -- Heroism
    11129,  -- Combustion
    12043,  -- Presence of Mind
    12042,  -- Arcane Power
    12472,  -- Icy Veins
    1856,   -- Vanish
    11305,  -- Sprint
    5384,   -- Feign Death
    6346,   -- Fear Ward
    1044,   -- Blessing of Freedom
}

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local function CopyValue(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = CopyValue(v) end
    return out
end
E.CopyValue = CopyValue

local function IdSet(list)
    local set = {}
    for _, id in ipairs(list) do set[id] = true end
    return set
end

local function ListCopy(list)
    local out = {}
    for i = 1, #list do out[i] = list[i] end
    return out
end

-- Remaining seconds, or nil for an aura that never expires. `now` is passed
-- in (GetTime() in the client, a fixture clock in the harness) so nothing in
-- here reads a clock of its own.
function E.Remaining(aura, now)
    if not aura then return nil end
    local expires = aura.expirationTime
    if not expires or expires == 0 then return nil end
    local left = expires - (now or 0)
    if left < 0 then left = 0 end
    return left
end

function E.IsPermanent(aura)
    return not aura or not aura.duration or aura.duration == 0
end

-- "Magic" / "Curse" / "Disease" / "Poison", or "NONE" for undispellable.
-- The client hands back "" as often as nil, so both collapse here.
function E.SchoolOf(aura)
    local school = aura and aura.dispelName
    if school == nil or school == "" then return "NONE" end
    return school
end

-- ---------------------------------------------------------------------------
-- Rules
-- ---------------------------------------------------------------------------

local nextId = 1
local function ClaimId(rules)
    local highest = 0
    for _, rule in ipairs(rules or {}) do
        local id = tonumber(rule.id) or 0
        if id > highest then highest = id end
    end
    if highest >= nextId then nextId = highest + 1 end
    local id = nextId
    nextId = nextId + 1
    return id
end
E.ClaimId = ClaimId

function E.NewRule(rules, name)
    return {
        id = ClaimId(rules),
        name = name or "New rule",
        enabled = true,
        action = "SHOW",
        match = {
            auraType = "ANY",
            source = "ANY",
            spellIds = {},
            namePart = "",
            dispel = nil,
            minStacks = 0,
            minDuration = nil,
            maxDuration = nil,
            bossOnly = false,
            stealableOnly = false,
            permanentOnly = false,
        },
        score = 50,
        expiringUnder = 0,
        expiringBonus = 0,
        stackBonus = 0,
        color = nil,
    }
end

-- The shipped policy. Nine rules, each demonstrating a different matcher so
-- the default list doubles as documentation for the editor.
function E.DefaultRules()
    local rules = {}
    local function add(rule) rules[#rules + 1] = rule end

    add({
        id = 1, name = "Silence & incapacitate", enabled = true, action = "SHOW",
        match = { auraType = "ANY", source = "ANY", spellIds = ListCopy(E.CC_IDS),
                  namePart = "", minStacks = 0, bossOnly = false,
                  stealableOnly = false, permanentOnly = false },
        score = 100, expiringUnder = 0, expiringBonus = 0, stackBonus = 0,
        color = "RED",
    })
    add({
        id = 2, name = "Boss debuffs", enabled = true, action = "SHOW",
        match = { auraType = "DEBUFF", source = "ANY", spellIds = {}, namePart = "",
                  minStacks = 0, bossOnly = true, stealableOnly = false,
                  permanentOnly = false },
        score = 95, expiringUnder = 5, expiringBonus = 20, stackBonus = 2,
        color = "RED",
    })
    add({
        id = 3, name = "My defensives & burst", enabled = true, action = "SHOW",
        match = { auraType = "BUFF", source = "ANY", spellIds = ListCopy(E.MAJOR_IDS),
                  namePart = "", minStacks = 0, bossOnly = false,
                  stealableOnly = false, permanentOnly = false },
        score = 92, expiringUnder = 3, expiringBonus = 25, stackBonus = 0,
        color = "GOLD",
    })
    add({
        id = 4, name = "Dispellable on me", enabled = true, action = "SHOW",
        match = { auraType = "DEBUFF", source = "ANY", spellIds = {}, namePart = "",
                  dispel = { Magic = true, Curse = true, Disease = true, Poison = true },
                  minStacks = 0, bossOnly = false, stealableOnly = false,
                  permanentOnly = false },
        score = 80, expiringUnder = 0, expiringBonus = 0, stackBonus = 3,
    })
    add({
        id = 5, name = "Any other debuff", enabled = true, action = "SHOW",
        match = { auraType = "DEBUFF", source = "ANY", spellIds = {}, namePart = "",
                  minStacks = 0, bossOnly = false, stealableOnly = false,
                  permanentOnly = false },
        score = 60, expiringUnder = 0, expiringBonus = 0, stackBonus = 3,
    })
    add({
        id = 6, name = "Hide raid buffs", enabled = true, action = "HIDE",
        match = { auraType = "BUFF", source = "ANY", spellIds = {}, namePart = "",
                  minStacks = 0, minDuration = 600, bossOnly = false,
                  stealableOnly = false, permanentOnly = false },
        score = 0, expiringUnder = 0, expiringBonus = 0, stackBonus = 0,
    })
    add({
        id = 7, name = "Hide auras with no timer", enabled = true, action = "HIDE",
        match = { auraType = "BUFF", source = "ANY", spellIds = {}, namePart = "",
                  minStacks = 0, bossOnly = false, stealableOnly = false,
                  permanentOnly = true },
        score = 0, expiringUnder = 0, expiringBonus = 0, stackBonus = 0,
    })
    add({
        id = 8, name = "My short buffs", enabled = true, action = "SHOW",
        match = { auraType = "BUFF", source = "MINE", spellIds = {}, namePart = "",
                  minStacks = 0, maxDuration = 60, bossOnly = false,
                  stealableOnly = false, permanentOnly = false },
        score = 45, expiringUnder = 3, expiringBonus = 15, stackBonus = 1,
    })
    add({
        id = 9, name = "Any other buff", enabled = true, action = "SHOW",
        match = { auraType = "BUFF", source = "ANY", spellIds = {}, namePart = "",
                  minStacks = 0, bossOnly = false, stealableOnly = false,
                  permanentOnly = false },
        score = 20, expiringUnder = 0, expiringBonus = 0, stackBonus = 0,
    })

    nextId = 10
    return rules
end

-- Repair whatever came back from SavedVariables: a hand-edited or
-- partially-written rule must never be able to error the evaluator. Returns
-- the same table (repaired in place) so callers can assign it back safely.
local VALID_TYPE = { ANY = true, BUFF = true, DEBUFF = true }
local VALID_SOURCE = { ANY = true, MINE = true, OTHER = true }
local VALID_ACTION = { SHOW = true, HIDE = true }

function E.NormalizeRule(rule, rules)
    if type(rule) ~= "table" then return nil end
    rule.id = tonumber(rule.id) or ClaimId(rules)
    rule.name = type(rule.name) == "string" and rule.name or "Rule"
    rule.enabled = rule.enabled ~= false
    rule.action = VALID_ACTION[rule.action] and rule.action or "SHOW"
    rule.score = tonumber(rule.score) or 0
    rule.expiringUnder = tonumber(rule.expiringUnder) or 0
    rule.expiringBonus = tonumber(rule.expiringBonus) or 0
    rule.stackBonus = tonumber(rule.stackBonus) or 0
    if rule.color ~= nil and type(rule.color) ~= "string" then rule.color = nil end

    local m = type(rule.match) == "table" and rule.match or {}
    rule.match = m
    m.auraType = VALID_TYPE[m.auraType] and m.auraType or "ANY"
    m.source = VALID_SOURCE[m.source] and m.source or "ANY"
    if type(m.spellIds) ~= "table" then m.spellIds = {} end
    for i = #m.spellIds, 1, -1 do
        local id = tonumber(m.spellIds[i])
        if id then m.spellIds[i] = id else table.remove(m.spellIds, i) end
    end
    m.namePart = type(m.namePart) == "string" and m.namePart or ""
    if type(m.dispel) == "table" then
        local any = false
        for _, school in ipairs(E.DISPEL_SCHOOLS) do
            if m.dispel[school] then any = true else m.dispel[school] = nil end
        end
        if not any then m.dispel = nil end
    else
        m.dispel = nil
    end
    m.minStacks = tonumber(m.minStacks) or 0
    m.minDuration = tonumber(m.minDuration) or nil
    m.maxDuration = tonumber(m.maxDuration) or nil
    m.bossOnly = m.bossOnly == true
    m.stealableOnly = m.stealableOnly == true
    m.permanentOnly = m.permanentOnly == true

    E.IndexMatch(m)
    return rule
end

-- Derived lookups (the spell-id set, the lowercased name fragment) are built
-- once per edit and parked in a WEAK side table — never on the rule itself,
-- because the rule table IS the SavedVariables record and every field we put
-- on it gets written to disk forever.
local matchCache = setmetatable({}, { __mode = "k" })

function E.IndexMatch(m)
    local set = {}
    for _, id in ipairs(m.spellIds or {}) do set[id] = true end
    local entry = matchCache[m] or {}
    entry.idSet = set
    entry.hasIds = next(set) ~= nil
    entry.nameLower = (m.namePart and m.namePart ~= "") and m.namePart:lower() or nil
    matchCache[m] = entry
    return entry
end

local function MatchIndex(m)
    return matchCache[m] or E.IndexMatch(m)
end

function E.NormalizeRules(rules)
    if type(rules) ~= "table" then return {} end
    for i = #rules, 1, -1 do
        if not E.NormalizeRule(rules[i], rules) then table.remove(rules, i) end
    end
    -- Re-seed the id counter above everything loaded, so a fresh rule can
    -- never collide with a saved one.
    ClaimId(rules)
    return rules
end

-- Editor operations. They live here (not in the window) so the harness can
-- prove reordering and deletion without building a single frame.
function E.MoveRule(rules, index, delta)
    local target = index + delta
    if not rules[index] or not rules[target] then return false end
    rules[index], rules[target] = rules[target], rules[index]
    return true
end

function E.DeleteRule(rules, index)
    if not rules[index] then return false end
    table.remove(rules, index)
    return true
end

function E.DuplicateRule(rules, index)
    local source = rules[index]
    if not source then return nil end
    local copy = CopyValue(source)
    copy.id = ClaimId(rules)
    copy.name = (source.name or "Rule") .. " copy"
    E.NormalizeRule(copy, rules)
    table.insert(rules, index + 1, copy)
    return copy
end

-- "118, 12824 33786" -> { 118, 12824, 33786 }. Deliberately forgiving about
-- separators: the editor's spell-id box is the one field users paste into.
function E.ParseSpellIds(text)
    local out = {}
    if type(text) ~= "string" then return out end
    local seen = {}
    for token in text:gmatch("%d+") do
        local id = tonumber(token)
        if id and not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    return out
end

function E.FormatSpellIds(ids)
    if type(ids) ~= "table" or #ids == 0 then return "" end
    local parts = {}
    for i = 1, #ids do parts[i] = tostring(ids[i]) end
    return table.concat(parts, ", ")
end

-- ---------------------------------------------------------------------------
-- Matching and scoring
-- ---------------------------------------------------------------------------

function E.MatchRule(rule, aura, now)
    if not rule or not rule.enabled or not aura then return false end
    local m = rule.match
    if not m then return false end

    if m.auraType == "BUFF" and aura.isHarmful then return false end
    if m.auraType == "DEBUFF" and not aura.isHarmful then return false end

    if m.source == "MINE" and not aura.mine then return false end
    if m.source == "OTHER" and aura.mine then return false end

    -- A spell-id list is an allow-list: present means the aura MUST be in it.
    local index = MatchIndex(m)
    if index.hasIds and not index.idSet[aura.spellId] then return false end

    local nameLower = index.nameLower
    if nameLower then
        local name = aura.name
        if type(name) ~= "string" or not name:lower():find(nameLower, 1, true) then
            return false
        end
    end

    if m.dispel then
        if not m.dispel[E.SchoolOf(aura)] then return false end
    end

    if (m.minStacks or 0) > 0 and (aura.stacks or 0) < m.minStacks then return false end

    local permanent = E.IsPermanent(aura)
    if m.permanentOnly and not permanent then return false end
    -- A duration window describes a TIMED aura. A permanent one has no
    -- duration to compare against, so a window never matches it — that is
    -- what keeps "hide long buffs" and "hide untimed auras" two distinct,
    -- both-reachable rules instead of the first swallowing the second.
    if m.minDuration or m.maxDuration then
        if permanent then return false end
        if m.minDuration and (aura.duration or 0) < m.minDuration then return false end
        if m.maxDuration and (aura.duration or 0) > m.maxDuration then return false end
    end

    if m.bossOnly and not aura.isBossAura then return false end
    if m.stealableOnly and not aura.isStealable then return false end

    return true
end

function E.ScoreFor(rule, aura, now)
    local score = rule.score or 0
    local remaining = E.Remaining(aura, now)
    if (rule.expiringUnder or 0) > 0 and remaining and remaining <= rule.expiringUnder then
        score = score + (rule.expiringBonus or 0)
    end
    if (rule.stackBonus or 0) ~= 0 then
        local stacks = aura.stacks or 0
        if stacks > 1 then score = score + (stacks - 1) * rule.stackBonus end
    end
    return score
end

-- The first enabled rule that accepts the aura, plus its index.
function E.Claim(rules, aura, now)
    for index = 1, #rules do
        local rule = rules[index]
        if E.MatchRule(rule, aura, now) then return rule, index end
    end
    return nil, nil
end

local FALLBACK_SCORE = { IGNORE = nil, DEBUFFS = 10, ALL = 5 }

-- Results are pooled: Evaluate runs on every aura change and, in the
-- editor's live trace, on every keystroke.
local resultPool = {}

local function ReleaseResults(list)
    for i = #list, 1, -1 do
        resultPool[#resultPool + 1] = list[i]
        list[i] = nil
    end
end
E.ReleaseResults = ReleaseResults

local function AcquireResult()
    local n = #resultPool
    if n > 0 then
        local entry = resultPool[n]
        resultPool[n] = nil
        return entry
    end
    return {}
end

local function CompareResults(a, b)
    if a.score ~= b.score then return a.score > b.score end
    -- Least time remaining first: the thing about to matter wins a tie.
    local ar = a.remaining or math.huge
    local br = b.remaining or math.huge
    if ar ~= br then return ar < br end
    if a.ruleIndex ~= b.ruleIndex then return a.ruleIndex < b.ruleIndex end
    return (a.aura.spellId or 0) < (b.aura.spellId or 0)
end

-- Rank the whole stack. `out` is reused by the caller across calls; it comes
-- back sorted, highest score first, HIDE rules and un-scored fallbacks
-- already dropped.
--
--   opts.fallback = "IGNORE" | "DEBUFFS" | "ALL"
--   opts.minScore = number   (results below it are dropped)
function E.Evaluate(auras, rules, opts, now, out)
    out = out or {}
    ReleaseResults(out)
    if type(auras) ~= "table" or type(rules) ~= "table" then return out end
    opts = opts or {}
    local fallbackScore = FALLBACK_SCORE[opts.fallback or "IGNORE"]
    local fallbackDebuffsOnly = (opts.fallback == "DEBUFFS")
    local minScore = opts.minScore or 0

    for i = 1, #auras do
        local aura = auras[i]
        if aura then
            local rule, ruleIndex = E.Claim(rules, aura, now)
            local score, keep
            if rule then
                if rule.action ~= "HIDE" then
                    score = E.ScoreFor(rule, aura, now)
                    keep = true
                end
            elseif fallbackScore then
                if not fallbackDebuffsOnly or aura.isHarmful then
                    score = fallbackScore
                    ruleIndex = #rules + 1
                    keep = true
                end
            end
            if keep and score >= minScore then
                local entry = AcquireResult()
                entry.aura = aura
                entry.rule = rule
                entry.ruleIndex = ruleIndex or (#rules + 1)
                entry.score = score
                entry.remaining = E.Remaining(aura, now)
                entry.color = rule and rule.color or nil
                out[#out + 1] = entry
            end
        end
    end

    sort(out, CompareResults)
    return out
end

-- The one aura the portrait shows (slot 1), or nil.
function E.Winner(auras, rules, opts, now, out)
    local ranked = E.Evaluate(auras, rules, opts, now, out)
    return ranked[1], ranked
end

-- A short, honest label for a duration — the sentinel and the trace both
-- need "1.5m" / "45" / "4.2" without dragging a formatting module along.
function E.FormatTime(seconds)
    if not seconds then return "" end
    if seconds >= 3600 then return floor(seconds / 3600 + 0.5) .. "h" end
    if seconds >= 60 then
        local minutes = seconds / 60
        if minutes >= 10 then return floor(minutes + 0.5) .. "m" end
        return string.format("%.1fm", minutes)
    end
    if seconds >= 10 then return tostring(floor(seconds + 0.5)) end
    if seconds <= 0 then return "0" end
    return string.format("%.1f", seconds)
end
