-- Commander Dossier engine fixture harness (luajit).
-- The engine is pure Lua — no mock needed. Drives canned crowd-control
-- streams and combat histories through the real engine calls and asserts
-- the diminishing-return ladder, the fade-starts-the-clock rule, the PvE
-- exemptions, the immunity edge, the board filters, the persistent records,
-- the kill attribution window, pruning, and the spec inference.
--
--   /opt/homebrew/bin/luajit dossier_harness.lua

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

assert(loadfile(ADDONS .. "/Commander_Dossier/CommanderDossierData.lua"))()
assert(loadfile(ADDONS .. "/Commander_Dossier/CommanderDossierEngine.lua"))()
local D = CommanderDossierData
local E = CommanderDossierEngine

local db = { RecordIntel = true }
local file = {}
E.Init(db, file, D)

-- ===========================================================================
-- The data file itself: the TBC canon, asserted so a careless edit is caught
-- ===========================================================================

CHECK(D.RESET_TIME == 20, "D: reset window is 20s")
CHECK(#D.DIMINISH == 3, "D: three diminished steps before immunity")
CHECK(D.DIMINISH[1] == 1 and D.DIMINISH[2] == 0.5 and D.DIMINISH[3] == 0.25,
    "D: 100 / 50 / 25 progression")
CHECK(D.CategoryByKey.silence == nil, "D: TBC has NO silence DR category")
CHECK(D.SpellCategory[2094] == "disorient", "D: Blind is disorient, not fear")
CHECK(D.SpellCategory[33786] == "disorient", "D: Cyclone shares disorient with Blind")
CHECK(D.SpellCategory[408] == "kidney_shot", "D: Kidney Shot is its own category")
CHECK(D.SpellCategory[1833] == "stun", "D: Cheap Shot is a normal stun")
CHECK(D.SpellCategory[8122] == "fear", "D: Psychic Scream is fear")
CHECK(D.SpellCategory[118] == "incapacitate", "D: Polymorph is incapacitate")
CHECK(D.SpellCategory[122] == "root", "D: Frost Nova is a controlled root")
CHECK(D.SpellCategory[12494] == "random_root", "D: Frostbite is a proc root")
CHECK(D.SpellCategory[15269] == "random_stun", "D: Blackout is a proc stun")
CHECK(D.PvECategories.stun and D.PvECategories.random_stun and D.PvECategories.kidney_shot,
    "D: the three PvE-diminishing categories")
CHECK(D.PvECategories.fear == nil and D.PvECategories.incapacitate == nil,
    "D: fear and incapacitate do not diminish on creatures")
do
    local unknown = 0
    for _, cat in pairs(D.SpellCategory) do
        if not D.CategoryByKey[cat] then unknown = unknown + 1 end
    end
    CHECK(unknown == 0, "D: every mapped spell names a real category", unknown)
    local seedMiss = 0
    for _, id in ipairs(D.NameSeeds) do
        if not D.SpellCategory[id] then seedMiss = seedMiss + 1 end
    end
    CHECK(seedMiss == 0, "D: every name seed is itself categorised", seedMiss)
    for _, entry in ipairs(D.Categories) do
        CHECK(D.CategoryHelp[entry.key] ~= nil, "D: category documented: " .. entry.key)
    end
end

-- ===========================================================================
-- Categorisation
-- ===========================================================================

CHECK(E.Categorize(853) == "stun", "E: categorises by spell id")
CHECK(E.Categorize(999999) == nil, "E: unknown id is not categorised")
E.SetNameIndex({ ["Hammer of Justice"] = "stun" })
CHECK(E.Categorize(999999, "Hammer of Justice") == "stun",
    "E: unlisted rank falls back to the name index")
CHECK(E.Categorize(999999, "Fireball") == nil, "E: a non-CC name stays uncategorised")
CHECK(E.Categorize(853, "Fireball") == "stun", "E: the id wins over the name")

CHECK(E.Diminishes("fear", true) == true, "E: fear diminishes on players")
CHECK(E.Diminishes("fear", false) == false, "E: fear does not diminish on creatures")
CHECK(E.Diminishes("stun", false) == true, "E: stuns diminish on creatures")
CHECK(E.Diminishes("kidney_shot", false) == true, "E: kidney shot diminishes on creatures")
CHECK(E.Diminishes(nil, true) == false, "E: nil category never diminishes")

CHECK(E.NextFraction(0) == 1.0, "E: a fresh category lands full")
CHECK(E.NextFraction(1) == 0.5, "E: second application is half")
CHECK(E.NextFraction(2) == 0.25, "E: third application is a quarter")
CHECK(E.NextFraction(3) == 0, "E: fourth application is an immunity")

-- ===========================================================================
-- The diminishing ladder and its clock
-- ===========================================================================

local T = 1000
E.NoteUnit("g-vexa", "Vexa", "ROGUE", true, true, T)

CHECK(E.Apply("g-vexa", "stun", T, "Cheap Shot") == 1, "E: first stun sets level 1")
local level, left, active = E.Level("g-vexa", "stun", T)
CHECK(level == 1 and active, "E: the effect reads as still up")
CHECK(left == 0, "E: an active effect has no countdown — the window has not started")

-- The reset clock starts at the FADE, not at the application
E.Fade("g-vexa", "stun", T + 4)
level, left, active = E.Level("g-vexa", "stun", T + 4)
CHECK(level == 1 and not active, "E: fade clears the active flag")
CHECK(math.abs(left - 20) < 0.01, "E: the countdown is a full window from the fade", left)
level, left = E.Level("g-vexa", "stun", T + 14)
CHECK(math.abs(left - 10) < 0.01, "E: the countdown runs down", left)

CHECK(E.Apply("g-vexa", "stun", T + 15, "Kidney") == 2, "E: a second stun inside the window")
E.Fade("g-vexa", "stun", T + 16)
CHECK(E.Apply("g-vexa", "stun", T + 17) == 3, "E: a third stun reaches immunity")
CHECK(E.NextFraction(select(1, E.Level("g-vexa", "stun", T + 17))) == 0,
    "E: the fourth would be immune")
E.Fade("g-vexa", "stun", T + 18)
CHECK(E.Apply("g-vexa", "stun", T + 19) == 3, "E: the level never climbs past immune")

-- ...and it resets once the window truly lapses
E.Fade("g-vexa", "stun", T + 20)
level = E.Level("g-vexa", "stun", T + 39.9)
CHECK(level == 3, "E: still immune a moment before the reset")
level, left = E.Level("g-vexa", "stun", T + 40.1)
CHECK(level == 0 and left == 0, "E: the window resets to full after 20s clear")
CHECK(E.Apply("g-vexa", "stun", T + 41) == 1, "E: the ladder starts over")

-- Categories are independent of one another
E.Apply("g-vexa", "fear", T + 41)
CHECK(select(1, E.Level("g-vexa", "fear", T + 41)) == 1, "E: fear has its own window")
CHECK(select(1, E.Level("g-vexa", "stun", T + 41)) == 1, "E: stun is unaffected by fear")
CHECK(select(1, E.Level("g-vexa", "root", T + 41)) == 0, "E: an untouched category is level 0")

-- A CC we never saw fade must not pin its window open forever
E.Reset()
E.NoteUnit("g-lost", "Faraway", "MAGE", true, true, T)
E.Apply("g-lost", "incapacitate", T, "Polymorph")
CHECK(select(3, E.Level("g-lost", "incapacitate", T + 10)) == true,
    "E: still considered up inside the guard")
level, left, active = E.Level("g-lost", "incapacitate", T + D.MAX_ACTIVE + 1)
CHECK(not active, "E: the guard releases a fade we never witnessed")
CHECK(level == 1 and left > 0, "E: and starts the window from the guard, not from nothing")
CHECK(select(1, E.Level("g-lost", "incapacitate", T + D.MAX_ACTIVE + D.RESET_TIME + 1)) == 0,
    "E: which then resets normally")

-- A pair that does not diminish never opens a window at all
E.Reset()
E.NoteUnit("g-mob", "Fel Reaver", nil, false, true, T)
CHECK(E.Apply("g-mob", "fear", T, "Fear") == nil, "E: fear on a creature opens no window")
CHECK(select(1, E.Level("g-mob", "fear", T)) == 0, "E: and reads as level 0 forever")
CHECK(E.Apply("g-mob", "stun", T) == 1, "E: a stun on a creature does diminish")

-- Fading something that was never applied is a no-op, not an error
E.Fade("g-mob", "root", T)
E.Fade("g-nobody", "root", T)
CHECK(select(1, E.Level("g-nobody", "root", T)) == 0, "E: fade on an unknown unit is safe")
CHECK(E.Apply("g-nobody", "stun", T) == nil, "E: apply on an untracked unit is refused")

-- ===========================================================================
-- The immunity edge
-- ===========================================================================

E.Reset()
E.NoteUnit("g-imm", "Target", "PRIEST", true, true, T)
local fired = {}
local function Drain()
    local out = {}
    E.DrainAlerts(function(kind, guid, cat)
        out[#out + 1] = kind
        fired[#fired + 1] = { kind = kind, guid = guid, cat = cat }
    end)
    return out
end

E.Apply("g-imm", "stun", T); E.Fade("g-imm", "stun", T + 1)
CHECK(#Drain() == 0, "E: no alert at level 1")
E.Apply("g-imm", "stun", T + 2); E.Fade("g-imm", "stun", T + 3)
CHECK(#Drain() == 0, "E: no alert at level 2")
E.Apply("g-imm", "stun", T + 4)
local drained = Drain()
CHECK(#drained == 1 and drained[1] == "IMMUNE", "E: the immunity edge fires once")
local lastAlert = fired[#fired] or {}
CHECK(lastAlert.cat == "stun" and lastAlert.guid == "g-imm",
    "E: the alert names the unit and the category")
E.Fade("g-imm", "stun", T + 4.5)
E.Apply("g-imm", "stun", T + 5)
CHECK(#Drain() == 0, "E: a re-application inside the gap does not re-alarm")
E.Fade("g-imm", "stun", T + 6)
E.Apply("g-imm", "stun", T + 12)
CHECK(#Drain() == 1, "E: past the gap it may alarm again")

-- ===========================================================================
-- The board: filters, ordering, sweep
-- ===========================================================================

E.Reset()
E.NoteUnit("g-e1", "Enemy One", "WARRIOR", true, true, T)
E.NoteUnit("g-e2", "Enemy Two", "MAGE", true, true, T)
E.NoteUnit("g-a1", "Ally One", "PRIEST", true, false, T)
E.Apply("g-e1", "stun", T)
E.Apply("g-e1", "fear", T)
E.Apply("g-e2", "root", T)
E.Apply("g-a1", "fear", T)

local board, n = E.Board(T, "ENEMIES")
CHECK(n == 2, "E: enemies-only board shows two rows", n)
CHECK(board[1].guid == "g-e1", "E: the busiest row sorts first")
board, n = E.Board(T, "ALLIES")
CHECK(n == 1 and board[1].guid == "g-a1", "E: allies-only board shows the ally")
board, n = E.Board(T, "BOTH")
CHECK(n == 3, "E: both shows everyone", n)

E.NoteUnit("g-quiet", "Nobody", "DRUID", true, true, T)
board, n = E.Board(T, "ENEMIES")
CHECK(n == 2, "E: a unit with no live window earns no row")

-- The scratch array must never keep a stale tail. This is sharper than it
-- looks: the busiest unit is the one that lapses, so a truncation that
-- happened after the sort would leave it sitting in row one.
E.Fade("g-e1", "stun", T)
E.Fade("g-e1", "fear", T)
board, n = E.Board(T + 25, "ENEMIES")
CHECK(n == 1, "E: only the unit with a live window earns a row", n)
CHECK(board[1].guid == "g-e2", "E: and it is the RIGHT unit, not a stale busier one",
    board[1] and board[1].guid)
CHECK(board[2] == nil, "E: the board array is dense after a window lapses")

-- Counted on a fresh unit: reading a window SETTLES it, so a query is only
-- ever meaningful moving forward in time.
E.NoteUnit("g-count", "Counter", "MAGE", true, true, T)
E.Apply("g-count", "stun", T)
E.Apply("g-count", "fear", T)
CHECK(E.LiveCategories("g-count", T) == 2, "E: live category count")
CHECK(E.LiveCategories("g-count", T + 200) == 0, "E: everything lapses eventually")

local before = E.UnitCount()
E.Sweep(T + 500)
CHECK(E.UnitCount() < before, "E: the sweep forgets quiet units")
CHECK(E.Unit("g-e1") == nil, "E: swept units are gone")

-- A unit with something still running survives the sweep
E.NoteUnit("g-live", "Busy", "ROGUE", true, true, T + 500)
E.Apply("g-live", "stun", T + 500)
E.Sweep(T + 560)
CHECK(E.Unit("g-live") ~= nil, "E: a live window pins its unit against the sweep")

-- ===========================================================================
-- The file: records, encounters, kills and deaths
-- ===========================================================================

local EPOCH = 1700000000

local rec = E.Observe("Vexa-Blackrock", { name = "Vexa", realm = "Blackrock",
    class = "ROGUE", race = "Undead", level = 70, guild = "Nightfall" }, EPOCH)
CHECK(rec ~= nil, "F: a record is created")
CHECK(rec.met == 1, "F: the first sighting is one meeting")
CHECK(rec.class == "ROGUE" and rec.guild == "Nightfall", "F: identity stored")
CHECK(rec.first == EPOCH and rec.last == EPOCH, "F: both stamps set")

E.Observe("Vexa-Blackrock", nil, EPOCH + 30)
CHECK(rec.met == 1, "F: the same fight is still one meeting")
CHECK(rec.last == EPOCH + 30, "F: but the last-seen stamp advances")
E.Observe("Vexa-Blackrock", nil, EPOCH + 4000)
CHECK(rec.met == 2, "F: a fresh sighting after the gap is a new meeting")

-- A nil field never overwrites something already learned
E.Observe("Vexa-Blackrock", { name = "Vexa", class = nil, level = 0 }, EPOCH + 4001)
CHECK(rec.class == "ROGUE", "F: nil does not erase a known class")
CHECK(rec.level == 70, "F: a zero level does not erase a known level")

CHECK(E.RecordCount() == 1, "F: one record on file")
CHECK(E.Record("Nobody-Nowhere") == nil, "F: an unknown key has no record")

E.WitnessSpell("Vexa-Blackrock", "Hemorrhage", EPOCH)
E.WitnessSpell("Vexa-Blackrock", "Hemorrhage", EPOCH)
E.WitnessSpell("Vexa-Blackrock", "Shadowstep", EPOCH)
CHECK(rec.spells["Hemorrhage"] == 2, "F: witnessed casts are counted")
CHECK(rec.spellsSeen == 3, "F: the evidence counter tracks every witness")
E.WitnessSpell("Ghost-Nowhere", "Fireball", EPOCH)
CHECK(E.Record("Ghost-Nowhere") == nil, "F: witnessing does not conjure a record")

E.CreditKill("Vexa-Blackrock", EPOCH)
CHECK(rec.kills == 1, "F: a kill is credited")

E.NoteIncoming("Vexa-Blackrock", T)
CHECK(E.NoteMyDeath(T + 3, EPOCH) == "Vexa-Blackrock", "F: a recent attacker takes the death")
CHECK(rec.deaths == 1, "F: the death is on their record")
CHECK(E.NoteMyDeath(T + 4, EPOCH) == nil, "F: the culprit is consumed, not reused")
E.NoteIncoming("Vexa-Blackrock", T)
CHECK(E.NoteMyDeath(T + 60, EPOCH) == nil, "F: a stale attacker is not blamed")
CHECK(rec.deaths == 1, "F: and the record is unchanged")

-- Recording can be switched off entirely
db.RecordIntel = false
CHECK(E.Observe("Newcomer-Realm", { name = "Newcomer" }, EPOCH) == nil,
    "F: recording off writes nothing")
CHECK(E.Record("Newcomer-Realm") == nil, "F: and creates no record")
db.RecordIntel = true

-- ===========================================================================
-- Spec inference against a Commander_Talents-shaped index
-- ===========================================================================

CHECK(E.SpecOf(rec) == nil, "S: no index means no verdict")
CHECK(E.HasTalentIndex() == false, "S: and the module knows it")

E.SetTalentIndex({
    ROGUE = {
        ["Hemorrhage"]     = { tree = 3, treeName = "Subtlety", row = 5 },
        ["Shadowstep"]     = { tree = 3, treeName = "Subtlety", row = 9 },
        ["Blade Flurry"]   = { tree = 2, treeName = "Combat", row = 5 },
        ["Adrenaline Rush"] = { tree = 2, treeName = "Combat", row = 7 },
        ["Surprise Attacks"] = { tree = 2, treeName = "Combat", row = 9 },
        ["Improved Eviscerate"] = { tree = 1, treeName = "Assassination", row = 1 },
    },
})
CHECK(E.HasTalentIndex() == true, "S: the index registers")

local spec = E.SpecOf(rec)
CHECK(spec ~= nil, "S: a verdict is reached")
CHECK(spec.label == "Subtlety", "S: the deepest-scoring tree wins", spec and spec.label)
CHECK(spec.deepest == "Shadowstep" and spec.deepestRow == 9,
    "S: the strongest tell is the deepest talent")
CHECK(spec.confidence == 1, "S: unanimous evidence reads as full confidence")

-- Evidence for another tree dilutes, and depth outweighs count
E.WitnessSpell("Vexa-Blackrock", "Blade Flurry", EPOCH)
spec = E.SpecOf(rec)
CHECK(spec.label == "Subtlety", "S: one shallow rival talent does not flip the verdict")
CHECK(spec.confidence < 1, "S: but it does cost confidence")
CHECK(spec.total == 19, "S: total weight is the sum of talent rows", spec.total)

-- Repetition is not evidence: a spammed talent must not outvote a deep one
for i = 1, 20 do E.WitnessSpell("Vexa-Blackrock", "Blade Flurry", EPOCH) end
spec = E.SpecOf(rec)
CHECK(spec.label == "Subtlety", "S: twenty repeats of one talent do not flip it")
CHECK(spec.total == 19, "S: and add no weight", spec.total)

-- New DISTINCT evidence must invalidate the cached verdict and can flip it
E.WitnessSpell("Vexa-Blackrock", "Adrenaline Rush", EPOCH)
E.WitnessSpell("Vexa-Blackrock", "Surprise Attacks", EPOCH)
spec = E.SpecOf(rec)
CHECK(spec.label == "Combat", "S: enough deep rival evidence flips it", spec.label)
CHECK(spec.deepest == "Shadowstep" or spec.deepest == "Surprise Attacks",
    "S: the strongest tell is still a row-9 talent")

-- Thin evidence is refused rather than guessed
local thin = E.Observe("Thin-Realm", { name = "Thin", class = "ROGUE" }, EPOCH)
E.WitnessSpell("Thin-Realm", "Improved Eviscerate", EPOCH)
CHECK(E.SpecOf(thin) == nil, "S: one row-1 talent is not enough to name a spec")
E.WitnessSpell("Thin-Realm", "Hemorrhage", EPOCH)
CHECK(E.SpecOf(thin) ~= nil, "S: real evidence clears the bar")

-- Unknowable cases stay silent instead of guessing
local noClass = E.Observe("Mystery-Realm", { name = "Mystery" }, EPOCH)
E.WitnessSpell("Mystery-Realm", "Shadowstep", EPOCH)
CHECK(E.SpecOf(noClass) == nil, "S: no class means no verdict")
local otherClass = E.Observe("Mage-Realm", { name = "Mage", class = "MAGE" }, EPOCH)
E.WitnessSpell("Mage-Realm", "Shadowstep", EPOCH)
CHECK(E.SpecOf(otherClass) == nil, "S: a class absent from the index is silent")
CHECK(E.SpecOf(nil) == nil, "S: a nil record is safe")

-- Casts of untalented, baseline abilities are simply not evidence
local base = E.Observe("Base-Realm", { name = "Base", class = "ROGUE" }, EPOCH)
for i = 1, 30 do E.WitnessSpell("Base-Realm", "Sinister Strike", EPOCH) end
CHECK(E.SpecOf(base) == nil, "S: thirty baseline casts prove nothing")

-- ===========================================================================
-- Sorting, summary, pruning
-- ===========================================================================

local sorted, count = E.Sorted("NAME")
CHECK(count == E.RecordCount(), "R: sorting returns every record", count)
local names = {}
for i = 1, count do names[i] = sorted[i].name or "" end
local ordered = true
for i = 2, count do if names[i] < names[i - 1] then ordered = false end end
CHECK(ordered, "R: name sort is alphabetical")

sorted, count = E.Sorted("NAME", function(r) return r.class == "ROGUE" end)
CHECK(count == 3, "R: a filter narrows the list", count)

E.CreditKill("Base-Realm", EPOCH)
E.CreditKill("Base-Realm", EPOCH)
sorted = E.Sorted("KILLS")
CHECK(sorted[1].name == "Base", "R: kill sort puts your best victim first")

local summary = E.Summary()
CHECK(summary.total == E.RecordCount(), "R: the summary counts every record")
CHECK(summary.kills == 3 and summary.deaths == 1, "R: the summary totals the record",
    summary.kills .. "/" .. summary.deaths)
CHECK(summary.nemesis and summary.nemesis.name == "Vexa", "R: the nemesis is who kills you most")
CHECK(summary.nemesisDeaths == 1, "R: and the summary says how many times")
do
    -- An even rival who has killed you ten times outranks a one-off ganker
    local rival = E.Observe("Rival-Realm", { name = "Rival" }, EPOCH)
    rival.deaths, rival.kills = 10, 10
    local ganker = E.Observe("Ganker-Realm", { name = "Ganker" }, EPOCH)
    ganker.deaths, ganker.kills = 2, 0
    local s2 = E.Summary()
    CHECK(s2.nemesis and s2.nemesis.name == "Rival",
        "R: the nemesis is picked on their kills, not on net score",
        s2.nemesis and s2.nemesis.name)
    E.Forget("Rival-Realm")
    E.Forget("Ganker-Realm")
end

-- Pruning: age out the stale, keep the annotated
local old = E.Observe("Ancient-Realm", { name = "Ancient" }, EPOCH - 86400 * 400)
local kept = E.Observe("Remembered-Realm", { name = "Remembered" }, EPOCH - 86400 * 400)
kept.note = "opens with a sap every time"
local dropped = E.Prune(EPOCH, 180, 0)
CHECK(dropped >= 1, "P: stale records are pruned", dropped)
CHECK(E.Record("Ancient-Realm") == nil, "P: the stale record is gone")
CHECK(E.Record("Remembered-Realm") ~= nil, "P: an annotated record survives its age")
CHECK(E.Record("Vexa-Blackrock") ~= nil, "P: a recent record is untouched")

CHECK(E.Prune(EPOCH, 0, 0) == 0, "P: keepDays 0 keeps everything")

-- The ceiling drops the oldest first, and still spares notes
for i = 1, 12 do
    E.Observe("Filler" .. i .. "-Realm", { name = "Filler" .. i }, EPOCH - i * 100)
end
local total = E.RecordCount()
E.Prune(EPOCH, 0, 6)
CHECK(E.RecordCount() == 6, "P: the ceiling trims to size", E.RecordCount())
CHECK(total > 6, "P: (and there was something to trim)")
CHECK(E.Record("Remembered-Realm") ~= nil, "P: the ceiling spares annotated records")

E.Forget("Remembered-Realm")
CHECK(E.Record("Remembered-Realm") == nil, "P: forget removes one record")
E.Wipe()
CHECK(E.RecordCount() == 0, "P: wipe empties the file")

-- Wiping must not disturb the live board
E.NoteUnit("g-after", "Still Here", "MAGE", true, true, T)
E.Apply("g-after", "root", T)
CHECK(select(1, E.Level("g-after", "root", T)) == 1, "P: the live board survives a wipe")

io.write(format and "" or "")
io.write(string.format("\n%s  %d checks, %d failures\n",
    fails == 0 and "PASS" or "FAIL", checks, fails))
os.exit(fails == 0 and 0 or 1)
