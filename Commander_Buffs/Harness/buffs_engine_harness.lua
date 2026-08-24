-- Commander Buffs engine fixture harness (luajit).
-- Pure Lua: loads CommanderBuffsEngine.lua on its own (it touches no WoW API)
-- and drives the whole policy — matching, scoring, claim order, HIDE vetoes,
-- fallbacks, tie-breaks, and the editor's list operations.
--
--   /opt/homebrew/bin/luajit buffs_engine_harness.lua

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local ADDON = here .. "../"

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end

assert(loadfile(ADDON .. "CommanderBuffsEngine.lua"))()
local E = CommanderBuffsEngine
CHECK(E ~= nil, "engine global exists")

local NOW = 10000

-- Aura fixture: the exact shape CommanderBuffs.lua builds from C_UnitAuras.
local function Aura(t)
    return {
        name = t.name or "Aura",
        icon = t.icon or 0,
        spellId = t.spellId or 1,
        stacks = t.stacks or 0,
        duration = t.duration or 0,
        expirationTime = t.expirationTime or (t.duration and t.duration > 0 and (NOW + (t.left or t.duration)) or 0),
        isHarmful = t.isHarmful or false,
        dispelName = t.dispelName,
        mine = t.mine or false,
        isBossAura = t.isBossAura or false,
        isStealable = t.isStealable or false,
        index = t.index or 1,
    }
end

-- Rule fixture: NewRule's shape with the fields under test overlaid, then
-- normalized exactly as SavedVariables content would be.
local function Rule(t)
    local rule = E.NewRule({}, t.name)
    rule.action = t.action or "SHOW"
    rule.score = t.score or 50
    rule.expiringUnder = t.expiringUnder or 0
    rule.expiringBonus = t.expiringBonus or 0
    rule.stackBonus = t.stackBonus or 0
    for k, v in pairs(t.match or {}) do rule.match[k] = v end
    E.NormalizeRule(rule, {})
    return rule
end

-- ===========================================================================
-- Defaults
-- ===========================================================================

local defaults = E.DefaultRules()
CHECK(#defaults == 12, "twelve shipped rules", #defaults)
for i, rule in ipairs(defaults) do
    CHECK(E.NormalizeRule(rule, defaults) ~= nil, "default rule " .. i .. " normalizes")
    CHECK(type(rule.name) == "string" and rule.name ~= "", "default rule " .. i .. " named")
end
do
    local ids = {}
    for _, rule in ipairs(defaults) do
        CHECK(not ids[rule.id], "default rule ids unique", rule.id)
        ids[rule.id] = true
    end
end
CHECK(#E.CC_IDS > 30, "cc list is substantial", #E.CC_IDS)
CHECK(#E.MAJOR_IDS > 20, "major list is substantial", #E.MAJOR_IDS)

-- ===========================================================================
-- Loss of control: the categories, the map, and the matcher
-- ===========================================================================

do
    CHECK(#E.LOC_CATEGORIES == 7, "seven control categories", #E.LOC_CATEGORIES)
    local seen = {}
    for _, category in ipairs(E.LOC_CATEGORIES) do
        CHECK(not seen[category.key], "category keys are unique", category.key)
        seen[category.key] = true
        CHECK(type(category.label) == "string" and category.label ~= "",
            "category " .. category.key .. " has a label")
        CHECK(type(category.color) == "table" and #category.color == 3,
            "category " .. category.key .. " has an rgb color")
        CHECK(E.LOC_INFO[category.key] == category,
            "category " .. category.key .. " is reachable by key")
    end

    -- The flat list the rest of the suite reads must be exactly the union of
    -- the categories, or the two descriptions of "what is CC" have drifted.
    local flat = 0
    for _, id in ipairs(E.CC_IDS) do
        CHECK(E.LOC_IDS[id] ~= nil, "every flat id is categorized", id)
        flat = flat + 1
    end
    local mapped = 0
    for _ in pairs(E.LOC_IDS) do mapped = mapped + 1 end
    CHECK(flat == mapped, "the flat list and the map are the same set", flat .. " vs " .. mapped)

    CHECK(E.LocCategory(Aura({ spellId = 408 })) == "STUN", "Kidney Shot is a stun")
    CHECK(E.LocCategory(Aura({ spellId = 118 })) == "INCAP", "Polymorph is an incapacitate")
    CHECK(E.LocCategory(Aura({ spellId = 5782 })) == "FEAR", "Fear is a fear")
    CHECK(E.LocCategory(Aura({ spellId = 605 })) == "CHARM", "Mind Control is a charm")
    CHECK(E.LocCategory(Aura({ spellId = 15487 })) == "SILENCE", "Silence is a silence")
    CHECK(E.LocCategory(Aura({ spellId = 122 })) == "ROOT", "Frost Nova is a root")
    CHECK(E.LocCategory(Aura({ spellId = 676 })) == "DISARM", "Disarm is a disarm")
    CHECK(E.LocCategory(Aura({ spellId = 10157 })) == nil, "Arcane Intellect is not control")
    CHECK(E.LocCategory(nil) == nil, "a nil aura has no category")
    CHECK(E.LocInfo(nil) == nil, "a nil category has no info")
    CHECK(E.LocInfo("NOPE") == nil, "an unknown category has no info")

    -- The retired flat list carried Mind Soothe, which is cast on mobs and
    -- could never land on the player. It must not have survived the split.
    CHECK(E.LOC_IDS[453] == nil, "Mind Soothe is gone from the control set")

    local locRule = Rule({ name = "stuns", match = { loc = { STUN = true } } })
    CHECK(E.MatchRule(locRule, Aura({ spellId = 408 }), NOW), "a loc matcher claims its category")
    CHECK(not E.MatchRule(locRule, Aura({ spellId = 118 }), NOW),
        "a loc matcher rejects a different category")
    CHECK(not E.MatchRule(locRule, Aura({ spellId = 10157 }), NOW),
        "a loc matcher rejects an aura that is not control at all")

    local multi = Rule({ name = "both", match = { loc = { STUN = true, ROOT = true } } })
    CHECK(E.MatchRule(multi, Aura({ spellId = 408 }), NOW), "a multi-category matcher takes the first")
    CHECK(E.MatchRule(multi, Aura({ spellId = 122 }), NOW), "a multi-category matcher takes the second")

    -- An empty set means "does not care", exactly like the dispel row.
    local empty = Rule({ name = "empty", match = { loc = {} } })
    E.NormalizeRule(empty, {})
    CHECK(empty.match.loc == nil, "an empty control set normalizes away")
    CHECK(E.MatchRule(empty, Aura({ spellId = 10157 }), NOW),
        "a rule with no control set still matches ordinary auras")

    local junk = Rule({ name = "junk", match = { loc = { NOPE = true, STUN = true } } })
    E.NormalizeRule(junk, {})
    CHECK(junk.match.loc and junk.match.loc.NOPE == nil, "unknown categories are dropped")
    CHECK(junk.match.loc and junk.match.loc.STUN == true, "known categories survive")
end

-- ===========================================================================
-- ALERT: SHOW that the minimum-score gate cannot reach
-- ===========================================================================

do
    local rules = {
        Rule({ name = "alarm", action = "ALERT", score = 10, match = { spellIds = { 408 } } }),
        Rule({ name = "quiet", action = "SHOW", score = 10, match = {} }),
    }
    local stack = { Aura({ spellId = 408, name = "Kidney Shot", isHarmful = true }),
                    Aura({ spellId = 999, name = "Something" }) }
    local out = E.Evaluate(stack, rules, { minScore = 500 }, NOW)
    CHECK(#out == 1, "a floor above every score keeps only the ALERT", #out)
    CHECK(out[1] and out[1].aura.spellId == 408, "and it is the alerting aura")
    CHECK(out[1] and out[1].alert == true, "the result is flagged as an alert")
    CHECK(out[1] and out[1].loc == "STUN", "the result carries its control category")

    -- ALERT still loses to a higher score: it buys exemption from the floor,
    -- not the top of the list.
    local ranked = E.Evaluate(stack, {
        Rule({ name = "alarm", action = "ALERT", score = 10, match = { spellIds = { 408 } } }),
        Rule({ name = "loud", action = "SHOW", score = 99, match = {} }),
    }, {}, NOW)
    CHECK(ranked[1] and ranked[1].aura.spellId == 999, "ALERT does not outrank a higher score")

    -- A HIDE rule is still a veto even when a later rule would alert.
    local vetoed = E.Evaluate({ Aura({ spellId = 408 }) }, {
        Rule({ name = "veto", action = "HIDE", match = { spellIds = { 408 } } }),
        Rule({ name = "alarm", action = "ALERT", score = 130, match = {} }),
    }, {}, NOW)
    CHECK(#vetoed == 0, "an earlier HIDE still beats a later ALERT", #vetoed)

    local plain = E.Evaluate({ Aura({ spellId = 999 }) },
        { Rule({ name = "s", action = "SHOW", score = 10, match = {} }) },
        { minScore = 500 }, NOW)
    CHECK(#plain == 0, "a plain SHOW is still gated by the floor", #plain)
end

-- ===========================================================================
-- The shipped policy actually focuses on loss of control
-- ===========================================================================

do
    local shipped = E.NormalizeRules(E.DefaultRules())
    local FLOOR = { minScore = 90 }   -- the shipped Minimum Score

    local function winner(stack)
        local ranked = E.Evaluate(stack, shipped, FLOOR, NOW)
        return ranked[1]
    end

    -- The noise the sentinel used to carry must no longer reach it.
    CHECK(winner({ Aura({ spellId = 3409, name = "Crippling Poison", duration = 12,
        left = 4, isHarmful = true, dispelName = "Poison" }) }) == nil,
        "a dispellable debuff no longer occupies the portrait")
    CHECK(winner({ Aura({ spellId = 7386, name = "Sunder Armor", duration = 30,
        left = 22, isHarmful = true, stacks = 5 }) }) == nil,
        "an ordinary stacking debuff no longer occupies the portrait")
    CHECK(winner({ Aura({ spellId = 139, name = "Renew", duration = 15, left = 9,
        mine = true }) }) == nil, "a short buff of mine no longer occupies the portrait")
    CHECK(winner({ Aura({ spellId = 10157, name = "Arcane Intellect", duration = 1800,
        left = 1400 }) }) == nil, "a raid buff never did and still does not")

    -- The emergencies still do.
    local boss = winner({ Aura({ spellId = 40604, name = "Fel Rage", duration = 30,
        left = 20, isHarmful = true, isBossAura = true }) })
    CHECK(boss ~= nil, "a boss debuff still reaches the portrait")
    local defensive = winner({ Aura({ spellId = 45438, name = "Ice Block",
        duration = 10, left = 8, mine = true }) })
    CHECK(defensive ~= nil, "my own defensive still reaches the portrait")

    -- And control beats all of it, from every category.
    for _, case in ipairs({
        { id = 408, category = "STUN" }, { id = 118, category = "INCAP" },
        { id = 5782, category = "FEAR" }, { id = 605, category = "CHARM" },
        { id = 15487, category = "SILENCE" }, { id = 122, category = "ROOT" },
        { id = 676, category = "DISARM" },
    }) do
        local top = winner({
            Aura({ spellId = case.id, name = case.category, duration = 8, left = 5,
                isHarmful = true }),
            Aura({ spellId = 40604, name = "Fel Rage", duration = 30, left = 20,
                isHarmful = true, isBossAura = true }),
            Aura({ spellId = 45438, name = "Ice Block", duration = 10, left = 8,
                mine = true }),
        })
        CHECK(top and top.loc == case.category,
            case.category .. " takes the portrait over a boss debuff and a defensive",
            top and tostring(top.loc))
    end

    -- Even with the dial pushed past every score in the policy.
    local silenced = E.Evaluate({ Aura({ spellId = 15487, duration = 5, left = 3,
        isHarmful = true }) }, shipped, { minScore = 999 }, NOW)
    CHECK(#silenced == 1, "no floor can hide a silence", #silenced)
end

-- ===========================================================================
-- The untouched-rule-set test that guards the migration
-- ===========================================================================

do
    CHECK(E.IsUntouchedRuleSet(E.DefaultRules()), "the shipped set is recognized as untouched")
    local legacy = {}
    for _, name in ipairs({ "Silence & incapacitate", "Boss debuffs",
        "My defensives & burst", "Dispellable on me", "Any other debuff",
        "Hide raid buffs", "Hide auras with no timer", "My short buffs",
        "Any other buff" }) do
        legacy[#legacy + 1] = { name = name }
    end
    CHECK(E.IsUntouchedRuleSet(legacy), "the previous shipped set is recognized too")

    local edited = E.DefaultRules()
    edited[1].name = "Mine"
    CHECK(not E.IsUntouchedRuleSet(edited), "a renamed rule makes the set touched")

    local trimmed = E.DefaultRules()
    table.remove(trimmed, 1)
    CHECK(not E.IsUntouchedRuleSet(trimmed), "a deleted rule makes the set touched")

    local extended = E.DefaultRules()
    extended[#extended + 1] = { name = "Extra" }
    CHECK(not E.IsUntouchedRuleSet(extended), "an added rule makes the set touched")

    CHECK(not E.IsUntouchedRuleSet(nil), "a missing rule list is not untouched")
    CHECK(not E.IsUntouchedRuleSet({}), "an empty rule list is not untouched")
end

-- Derived lookups must NEVER live on the rule: the rule table is the
-- SavedVariables record.
E.NormalizeRules(defaults)
for _, rule in ipairs(defaults) do
    CHECK(rule.match._idSet == nil, "no id set written onto the saved rule")
    CHECK(rule.match._nameLower == nil, "no name cache written onto the saved rule")
end

-- ===========================================================================
-- Matchers
-- ===========================================================================

local buff = Aura({ name = "Arcane Intellect", spellId = 10157, duration = 1800 })
local debuff = Aura({ name = "Corruption", spellId = 172, duration = 18, isHarmful = true,
    dispelName = "Magic" })

CHECK(E.MatchRule(Rule({ match = { auraType = "BUFF" } }), buff, NOW), "BUFF matches a buff")
CHECK(not E.MatchRule(Rule({ match = { auraType = "BUFF" } }), debuff, NOW), "BUFF rejects a debuff")
CHECK(E.MatchRule(Rule({ match = { auraType = "DEBUFF" } }), debuff, NOW), "DEBUFF matches a debuff")
CHECK(E.MatchRule(Rule({ match = { auraType = "ANY" } }), debuff, NOW), "ANY matches either")

local mine = Aura({ name = "Renew", spellId = 139, duration = 15, mine = true })
CHECK(E.MatchRule(Rule({ match = { source = "MINE" } }), mine, NOW), "MINE matches my aura")
CHECK(not E.MatchRule(Rule({ match = { source = "MINE" } }), buff, NOW), "MINE rejects a foreign aura")
CHECK(E.MatchRule(Rule({ match = { source = "OTHER" } }), buff, NOW), "OTHER matches a foreign aura")
CHECK(not E.MatchRule(Rule({ match = { source = "OTHER" } }), mine, NOW), "OTHER rejects my aura")

local idRule = Rule({ match = { spellIds = { 118, 33786 } } })
CHECK(E.MatchRule(idRule, Aura({ spellId = 118, duration = 10, isHarmful = true }), NOW),
    "spell id allow-list matches")
CHECK(not E.MatchRule(idRule, debuff, NOW), "spell id allow-list rejects everything else")

local nameRule = Rule({ match = { namePart = "corrup" } })
CHECK(E.MatchRule(nameRule, debuff, NOW), "name fragment matches case-insensitively")
CHECK(not E.MatchRule(nameRule, buff, NOW), "name fragment rejects a miss")

local dispelRule = Rule({ match = { dispel = { Magic = true } } })
CHECK(E.MatchRule(dispelRule, debuff, NOW), "dispel school matches")
CHECK(not E.MatchRule(dispelRule, Aura({ isHarmful = true, duration = 10, dispelName = "Curse" }), NOW),
    "dispel school rejects another school")
local noneRule = Rule({ match = { dispel = { NONE = true } } })
CHECK(E.MatchRule(noneRule, Aura({ isHarmful = true, duration = 10 }), NOW),
    "NONE school matches an undispellable debuff")
CHECK(E.MatchRule(noneRule, Aura({ isHarmful = true, duration = 10, dispelName = "" }), NOW),
    "empty-string school collapses to NONE")
CHECK(not E.MatchRule(noneRule, debuff, NOW), "NONE school rejects a dispellable debuff")

local stackRule = Rule({ match = { minStacks = 3 } })
CHECK(E.MatchRule(stackRule, Aura({ stacks = 5, duration = 10 }), NOW), "stack floor matches")
CHECK(not E.MatchRule(stackRule, Aura({ stacks = 2, duration = 10 }), NOW), "stack floor rejects")

local windowRule = Rule({ match = { minDuration = 10, maxDuration = 60 } })
CHECK(E.MatchRule(windowRule, Aura({ duration = 30 }), NOW), "duration window matches inside")
CHECK(not E.MatchRule(windowRule, Aura({ duration = 5 }), NOW), "duration window rejects short")
CHECK(not E.MatchRule(windowRule, Aura({ duration = 600 }), NOW), "duration window rejects long")
CHECK(not E.MatchRule(windowRule, Aura({ duration = 0 }), NOW),
    "duration window never matches a permanent aura")

local permRule = Rule({ match = { permanentOnly = true } })
CHECK(E.MatchRule(permRule, Aura({ duration = 0 }), NOW), "permanentOnly matches an untimed aura")
CHECK(not E.MatchRule(permRule, buff, NOW), "permanentOnly rejects a timed aura")

CHECK(E.MatchRule(Rule({ match = { bossOnly = true } }),
    Aura({ isHarmful = true, duration = 20, isBossAura = true }), NOW), "bossOnly matches")
CHECK(not E.MatchRule(Rule({ match = { bossOnly = true } }), debuff, NOW), "bossOnly rejects")
CHECK(E.MatchRule(Rule({ match = { stealableOnly = true } }),
    Aura({ duration = 20, isStealable = true }), NOW), "stealableOnly matches")

local disabled = Rule({})
disabled.enabled = false
CHECK(not E.MatchRule(disabled, buff, NOW), "a disabled rule never matches")

-- ===========================================================================
-- Scoring
-- ===========================================================================

local expiring = Rule({ score = 50, expiringUnder = 5, expiringBonus = 40 })
CHECK(E.ScoreFor(expiring, Aura({ duration = 20, left = 20 }), NOW) == 50, "no bonus while far out")
CHECK(E.ScoreFor(expiring, Aura({ duration = 20, left = 3 }), NOW) == 90, "expiring bonus applies")
CHECK(E.ScoreFor(expiring, Aura({ duration = 0 }), NOW) == 50, "permanent aura never expires")

local stacking = Rule({ score = 10, stackBonus = 5 })
CHECK(E.ScoreFor(stacking, Aura({ stacks = 1, duration = 10 }), NOW) == 10, "one stack is the base")
CHECK(E.ScoreFor(stacking, Aura({ stacks = 5, duration = 10 }), NOW) == 30, "stack bonus counts extras")
CHECK(E.ScoreFor(stacking, Aura({ stacks = 0, duration = 10 }), NOW) == 10, "zero stacks is the base")

CHECK(E.Remaining(Aura({ duration = 20, left = 8 }), NOW) == 8, "remaining reads the clock")
CHECK(E.Remaining(Aura({ duration = 0 }), NOW) == nil, "permanent aura has no remaining")
CHECK(E.Remaining(Aura({ duration = 20, expirationTime = NOW - 5 }), NOW) == 0, "expired clamps to zero")

-- ===========================================================================
-- Claim order and evaluation
-- ===========================================================================

local rules = {
    Rule({ name = "first", score = 90, match = { spellIds = { 172 } } }),
    Rule({ name = "second", score = 10, match = { auraType = "DEBUFF" } }),
}
local claimed, claimedIndex = E.Claim(rules, debuff, NOW)
CHECK(claimed and claimed.name == "first", "first matching rule claims the aura")
CHECK(claimedIndex == 1, "claim reports the rule index")

local hideRules = {
    Rule({ name = "veto", action = "HIDE", match = { spellIds = { 172 } } }),
    Rule({ name = "catch", score = 99, match = { auraType = "DEBUFF" } }),
}
local ranked = E.Evaluate({ debuff }, hideRules, {}, NOW)
CHECK(#ranked == 0, "a HIDE rule claims the aura and drops it", #ranked)

local stack = {
    buff,
    debuff,
    Aura({ name = "Ice Block", spellId = 45438, duration = 10, left = 2, mine = true }),
    Aura({ name = "Sunder Armor", spellId = 7386, duration = 30, stacks = 5, isHarmful = true }),
}
ranked = E.Evaluate(stack, defaults, { fallback = "IGNORE" }, NOW)
CHECK(#ranked > 0, "the default policy ranks a real stack")
CHECK(ranked[1].aura.spellId == 45438, "Ice Block about to drop wins the portrait",
    ranked[1] and ranked[1].aura.name)
do
    local sawIntellect = false
    for _, entry in ipairs(ranked) do
        if entry.aura.spellId == 10157 then sawIntellect = true end
    end
    CHECK(not sawIntellect, "the raid-buff HIDE rule keeps Arcane Intellect out")
end
do
    local descending = true
    for i = 2, #ranked do
        if ranked[i].score > ranked[i - 1].score then descending = false end
    end
    CHECK(descending, "results come back sorted by score")
end

-- Rule 7 (untimed auras) must still be reachable with rule 6 above it.
do
    local aura = Aura({ name = "Mounted", spellId = 999, duration = 0 })
    local rule = select(1, E.Claim(defaults, aura, NOW))
    CHECK(rule and rule.name == "Hide auras with no timer",
        "an untimed buff falls to the untimed rule, not the raid-buff rule",
        rule and rule.name)
end

-- Fallbacks
local emptyRules = {}
CHECK(#E.Evaluate(stack, emptyRules, { fallback = "IGNORE" }, NOW) == 0, "IGNORE drops unclaimed auras")
local dbg = E.Evaluate(stack, emptyRules, { fallback = "DEBUFFS" }, NOW)
CHECK(#dbg == 2, "DEBUFFS keeps only harmful auras", #dbg)
CHECK(#E.Evaluate(stack, emptyRules, { fallback = "ALL" }, NOW) == 4, "ALL keeps everything")

-- minScore gate
CHECK(#E.Evaluate(stack, defaults, { minScore = 1000 }, NOW) == 0, "minScore can silence the sentinel")

-- Tie-break: equal scores resolve to the aura closest to expiry, and the
-- order must be stable across repeated evaluations.
do
    local tieRules = { Rule({ name = "flat", score = 50, match = { auraType = "DEBUFF" } }) }
    local a = Aura({ name = "A", spellId = 2, duration = 30, left = 20, isHarmful = true })
    local b = Aura({ name = "B", spellId = 3, duration = 30, left = 4, isHarmful = true })
    local out = E.Evaluate({ a, b }, tieRules, {}, NOW)
    CHECK(out[1].aura.name == "B", "the aura about to expire wins a score tie")
    local again = E.Evaluate({ b, a }, tieRules, {}, NOW)
    CHECK(again[1].aura.name == "B", "tie-break is order-independent")
end

-- Winner
do
    local winner = E.Winner(stack, defaults, {}, NOW)
    CHECK(winner and winner.aura.spellId == 45438, "Winner returns the top entry")
end

-- Result pooling: evaluating into the same table must not grow it forever.
do
    local out = {}
    for _ = 1, 5 do E.Evaluate(stack, defaults, {}, NOW, out) end
    local first = #out
    E.Evaluate({}, defaults, {}, NOW, out)
    CHECK(#out == 0, "reusing the out table clears it", first)
end

-- ===========================================================================
-- Editor operations
-- ===========================================================================

local list = E.DefaultRules()
E.NormalizeRules(list)
local firstName = list[1].name
CHECK(E.MoveRule(list, 1, 1), "move down succeeds")
CHECK(list[2].name == firstName, "move down swaps")
CHECK(not E.MoveRule(list, 1, -1), "move above the top is refused")
CHECK(not E.MoveRule(list, #list, 1), "move below the end is refused")

local before = #list
local copy = E.DuplicateRule(list, 1)
CHECK(copy ~= nil and #list == before + 1, "duplicate inserts after the source")
CHECK(copy.id ~= list[1].id, "the duplicate gets a fresh id")
CHECK(copy.name:find("copy"), "the duplicate is named as one", copy and copy.name)
CHECK(copy.match ~= list[1].match, "the duplicate deep-copies its matcher")

CHECK(E.DeleteRule(list, #list), "delete succeeds")
CHECK(not E.DeleteRule(list, 999), "deleting a missing index is refused")

local fresh = E.NewRule(list)
local usedIds = {}
for _, rule in ipairs(list) do usedIds[rule.id] = true end
CHECK(not usedIds[fresh.id], "a new rule never reuses a live id", fresh.id)

-- Spell id parsing
CHECK(#E.ParseSpellIds("118, 12824 33786") == 3, "spell ids parse from mixed separators")
CHECK(E.ParseSpellIds("118,118")[2] == nil, "spell id parsing dedupes")
CHECK(#E.ParseSpellIds("") == 0, "empty spell id text parses to nothing")
CHECK(#E.ParseSpellIds(nil) == 0, "nil spell id text is survivable")
CHECK(E.FormatSpellIds({ 1, 2 }) == "1, 2", "spell ids format back")
CHECK(E.FormatSpellIds({}) == "", "empty spell id list formats to empty")

-- Normalization repairs whatever SavedVariables hands back
do
    local junk = {
        { name = 42, action = "EXPLODE", score = "70", match = "nope" },
        "not a rule",
        { name = "ok", match = { auraType = "SIDEWAYS", source = "?", spellIds = { "118", "x" },
            dispel = {}, minStacks = "3" } },
    }
    E.NormalizeRules(junk)
    CHECK(#junk == 2, "non-table rules are dropped", #junk)
    CHECK(junk[1].action == "SHOW", "an unknown action falls back to SHOW")
    CHECK(junk[1].score == 70, "a stringy score becomes a number")
    CHECK(type(junk[1].match) == "table", "a broken matcher is rebuilt")
    CHECK(junk[2].match.auraType == "ANY", "an unknown aura type falls back to ANY")
    CHECK(junk[2].match.source == "ANY", "an unknown source falls back to ANY")
    CHECK(#junk[2].match.spellIds == 1 and junk[2].match.spellIds[1] == 118,
        "stringy spell ids convert and junk ones drop")
    CHECK(junk[2].match.dispel == nil, "an all-false dispel set collapses to nil")
    CHECK(junk[2].match.minStacks == 3, "a stringy stack floor becomes a number")
    CHECK(E.MatchRule(junk[2], Aura({ spellId = 118, stacks = 4, duration = 10 }), NOW),
        "a repaired rule still evaluates")
    CHECK(not E.MatchRule(junk[2], Aura({ spellId = 118, stacks = 1, duration = 10 }), NOW),
        "a repaired rule still enforces its stack floor")
end

-- Editing a matcher must take effect on the next evaluation (the editor
-- relies on this for its live trace).
do
    local rule = Rule({ score = 50, match = { spellIds = { 1 } } })
    local aura = Aura({ spellId = 2, duration = 10 })
    CHECK(not E.MatchRule(rule, aura, NOW), "id filter rejects before the edit")
    rule.match.spellIds = { 2 }
    E.NormalizeRule(rule, {})
    CHECK(E.MatchRule(rule, aura, NOW), "id filter re-indexes after the edit")
    rule.match.namePart = "zzz"
    E.NormalizeRule(rule, {})
    CHECK(not E.MatchRule(rule, aura, NOW), "name filter re-indexes after the edit")
end

-- ===========================================================================
-- Formatting
-- ===========================================================================

CHECK(E.FormatTime(nil) == "", "nil time formats to empty")
CHECK(E.FormatTime(0) == "0", "zero formats to 0")
CHECK(E.FormatTime(4.24) == "4.2", "sub-ten seconds keep a decimal")
CHECK(E.FormatTime(45) == "45", "seconds round to whole")
CHECK(E.FormatTime(90) == "1.5m", "minutes get a decimal")
CHECK(E.FormatTime(1800) == "30m", "long minutes round")
CHECK(E.FormatTime(7200) == "2h", "hours collapse")

io.write(string.format("\n%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
