-- Commander Who engine fixture harness (luajit).
--
-- No mock at all. CommanderWhoEngine is pure Lua, so this loads only that one
-- file and drives hand-written /who result sets through the real calls. A
-- failure here is always a real logic bug.
--
-- It covers the two things the 2.1 build got wrong, in the exact shapes that
-- produced the reported symptoms:
--
--   * selection keyed by player rather than by row, so a scroll (which is just
--     a change of offset over the same seventeen widgets) cannot move a tick
--     onto a different player;
--   * one plan, built from that selection, deciding who is messaged -- with
--     the cap and the skip-yourself rule counted rather than swallowed.
--
--   /opt/homebrew/bin/luajit who_harness.lua

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

assert(loadfile(ADDONS .. "/Commander_Who/CommanderWhoEngine.lua"))()
local E = CommanderWhoEngine

-- ===========================================================================
-- Fixtures
-- ===========================================================================

-- The shape C_FriendList.GetWhoInfo actually returns on 2.5.5: classStr for
-- the localised class, filename for the token, area for the zone,
-- fullGuildName for the guild. The 2.1 build read className, which is not a
-- field here -- hence a blank class column on every row.
local function Who(name, level, class, token, zone, guild, race)
    return {
        fullName = name,
        level = level,
        classStr = class,
        filename = token,
        area = zone,
        fullGuildName = guild or "",
        raceStr = race or "Human",
        gender = 2,
    }
end

local ROSTER = {
    Who("Alaric",   70, "Paladin", "PALADIN", "Shattrath City", "Vanguard"),
    Who("Brenna",   68, "Mage",    "MAGE",    "Nagrand"),
    Who("Corwin",   70, "Rogue",   "ROGUE",   "Terokkar Forest", "Vanguard"),
    Who("Dagny",    64, "Shaman",  "SHAMAN",  "Zangarmarsh"),
    Who("Eirik",    70, "Warrior", "WARRIOR", "Shadowmoon Valley"),
    Who("Fenna",    70, "Priest",  "PRIEST",  "Shattrath City"),
    Who("Gorrim",   61, "Hunter",  "HUNTER",  "Hellfire Peninsula"),
    Who("Halvard",  70, "Warlock", "WARLOCK", "Netherstorm", "Vanguard"),
    Who("Ingrid",   70, "Druid",   "DRUID",   "Blade's Edge Mountains"),
    Who("Jorund",   58, "Warrior", "WARRIOR", "Blasted Lands"),
}

local function Fetcher(list)
    return #list, function(i) return list[i] end
end

local function BuildFrom(list)
    return E.BuildRecords(Fetcher(list))
end

local function KeyOf(name) return E.Key(name) end

-- ===========================================================================
-- Identity
-- ===========================================================================

CHECK(E.Key("Alaric") == "alaric", "Key folds case")
CHECK(E.Key("  Alaric  ") == "alaric", "Key trims")
CHECK(E.Key("Alaric") == E.Key("ALARIC"), "Key is stable across capitalisation")
CHECK(E.Key("") == nil, "Key rejects empty")
CHECK(E.Key(nil) == nil, "Key rejects nil")
CHECK(E.Key(42) == nil, "Key rejects non-strings")

do
    local name, realm = E.SplitName("Alaric-Whitemane")
    CHECK(name == "Alaric" and realm == "Whitemane", "SplitName splits on the realm hyphen")
    local plain, none = E.SplitName("Alaric")
    CHECK(plain == "Alaric" and none == nil, "SplitName leaves a bare name alone")
    CHECK(E.Key("Alaric-Whitemane") ~= E.Key("Alaric-Doomhammer"),
        "Two realms are two different players")
end

-- ===========================================================================
-- Normalisation
-- ===========================================================================

do
    local r = E.Normalize(ROSTER[1], 1)
    CHECK(r.key == "alaric", "Normalize keys off the full name")
    CHECK(r.name == "Alaric", "Normalize keeps display capitalisation")
    CHECK(r.level == 70, "Normalize reads level")
    CHECK(r.classText == "Paladin", "Normalize reads classStr, the field this client sends")
    CHECK(r.classToken == "PALADIN", "Normalize resolves the class token from filename")
    CHECK(r.zone == "Shattrath City", "Normalize reads area as the zone")
    CHECK(r.guild == "Vanguard", "Normalize reads fullGuildName")
    CHECK(r.index == 1, "Normalize carries the list position")
end

do
    -- A client that spells the fields the other way must still work.
    local r = E.Normalize({ name = "Zeb", level = 70, className = "Mage",
                            classFileName = "MAGE", zone = "Karazhan", guild = "Kult" }, 3)
    CHECK(r and r.classText == "Mage", "Normalize accepts the className alias")
    CHECK(r.classToken == "MAGE", "Normalize accepts the classFileName alias")
    CHECK(r.zone == "Karazhan", "Normalize accepts the zone alias")
    CHECK(r.guild == "Kult", "Normalize accepts the guild alias")
end

do
    CHECK(E.Normalize(nil, 1) == nil, "Normalize rejects nil")
    CHECK(E.Normalize({}, 1) == nil, "Normalize rejects a record with no name")
    local r = E.Normalize({ fullName = "Nomad" }, 1)
    CHECK(r ~= nil, "A name is the only field Normalize requires")
    CHECK(r.level == 0 and r.classText == "" and r.zone == "",
        "Missing fields normalise to empty, never to a guess")
    CHECK(r.classToken == nil, "An unresolvable class is nil, not a default")
end

do
    -- The 2.1 fallback painted everything warrior-brown when the class field
    -- was missing. White is the honest answer.
    local rr, gg, bb = E.ClassColor(nil)
    CHECK(rr == 1 and gg == 1 and bb == 1, "Unknown class colours white")
    local pr = { E.ClassColor("PALADIN") }
    CHECK(pr[1] > 0.9 and pr[2] > 0.5, "Paladin is pink, not brown")
    CHECK(E.ClassHex("MAGE") == "69ccf0", "ClassHex matches the client's mage blue",
        E.ClassHex("MAGE"))
end

do
    E.SetClassNameMap({ Magier = "MAGE", Schurke = "ROGUE" })
    CHECK(E.ClassToken(nil, "Magier") == "MAGE", "A localised class name resolves through the map")
    CHECK(E.ClassToken(nil, "magier") == "MAGE", "The map is case-insensitive")
    CHECK(E.ClassToken("PRIEST", "Magier") == "PRIEST", "The token field wins over the localised name")
    CHECK(E.ClassToken(nil, "Rogue") == "ROGUE", "English still resolves with no map entry")
    CHECK(E.ClassToken(nil, "Death Knight") == nil, "A class this client cannot have stays unresolved")
    E.SetClassNameMap(nil)
    CHECK(E.ClassToken(nil, "Magier") == nil, "Clearing the map clears the localised lookup")
end

-- ===========================================================================
-- BuildRecords
-- ===========================================================================

do
    local records = BuildFrom(ROSTER)
    CHECK(#records == 10, "BuildRecords keeps every result")
    CHECK(records[1].key == "alaric" and records[10].key == "jorund",
        "BuildRecords preserves the server's order")
    for i = 1, #records do
        CHECK(records[i].index == i, "Record index matches its position", i)
    end
end

do
    local dupes = { Who("Alaric", 70, "Paladin", "PALADIN", "Shattrath City"),
                    Who("alaric", 70, "Paladin", "PALADIN", "Shattrath City"),
                    Who("Brenna", 68, "Mage", "MAGE", "Nagrand") }
    local records = BuildFrom(dupes)
    CHECK(#records == 2, "A duplicate key is dropped, not merged")
    CHECK(records[2].index == 2, "Indices stay contiguous after a drop")
end

do
    local ragged = { Who("Alaric", 70, "Paladin", "PALADIN", "Shattrath"), nil, {}, false }
    local records = E.BuildRecords(4, function(i) return ragged[i] end)
    CHECK(#records == 1, "Unusable entries are skipped without breaking the list")
end

-- ===========================================================================
-- Selection
-- ===========================================================================

do
    local sel = E.NewSelection()
    CHECK(sel:Count() == 0, "A new selection is empty")
    CHECK(sel:Get("alaric") == false, "Get on an unknown key is false, never nil")
    CHECK(sel:Get(nil) == false, "Get tolerates nil")

    CHECK(sel:Set("alaric", true) == true, "Set reports the change")
    CHECK(sel:Set("alaric", true) == false, "Setting the same value again reports no change")
    CHECK(sel:Count() == 1, "Count tracks Set")
    CHECK(sel:Set("alaric", false) == true, "Unsetting reports the change")
    CHECK(sel:Count() == 0, "Count tracks the unset")
    CHECK(sel:Set(nil, true) == false, "Set tolerates nil")

    CHECK(sel:Toggle("brenna") == true, "Toggle turns on")
    CHECK(sel:Toggle("brenna") == false, "Toggle turns off")
    CHECK(sel:Count() == 0, "Toggle keeps the count honest")
end

do
    local records = BuildFrom(ROSTER)
    local sel = E.NewSelection()
    sel:SetRecords(records, true)
    CHECK(sel:Count() == 10, "SetRecords selects everything")
    CHECK(sel:CountIn(records) == 10, "CountIn agrees")
    sel:InvertRecords(records)
    CHECK(sel:Count() == 0, "Invert of a full selection is empty")
    sel:InvertRecords(records)
    CHECK(sel:Count() == 10, "Invert of an empty selection is full")

    sel:Set(KeyOf("Corwin"), false)
    CHECK(sel:CountIn(records) == 9, "One unticked leaves nine")
    sel:InvertRecords(records)
    CHECK(sel:Count() == 1 and sel:Get(KeyOf("Corwin")), "Invert flips each row independently")
end

-- The reported bug, reproduced against the model that replaced the broken one.
-- Scrolling is nothing but a change of offset over a fixed row pool; if the
-- checked state is read from the selection by key on every paint, a scroll
-- cannot move a tick.
do
    local records = BuildFrom(ROSTER)
    local sel = E.NewSelection()
    sel:Set(KeyOf("Alaric"), true)
    sel:Set(KeyOf("Fenna"), true)

    local ROWS = 4   -- a deliberately tiny pool, so every scroll recycles
    local function Paint(offset)
        local painted = {}
        for i = 1, ROWS do
            local record = records[offset + i]
            painted[i] = record and { key = record.key, checked = sel:Get(record.key) } or false
        end
        return painted
    end

    local top = Paint(0)
    CHECK(top[1].checked == true and top[2].checked == false, "Row 1 is Alaric and is ticked")

    local scrolled = Paint(4)
    CHECK(scrolled[1].key == "eirik" and scrolled[1].checked == false,
        "After scrolling, row 1 holds Eirik and is NOT wearing Alaric's tick")
    CHECK(scrolled[2].key == "fenna" and scrolled[2].checked == true,
        "Fenna keeps her own tick wherever she lands")

    local back = Paint(0)
    CHECK(back[1].checked == true, "Scrolling back restores Alaric's tick")
    CHECK(sel:Count() == 2, "Scrolling never changes the selection itself")

    -- And scrolling past the end must not invent rows.
    local past = Paint(8)
    CHECK(past[3] == false and past[4] == false, "Rows past the end of the list are blank")
end

-- Prune: a re-search keeps the ticks of everyone still present and drops the
-- rest, so the count can never promise a send it cannot make.
do
    local records = BuildFrom(ROSTER)
    local sel = E.NewSelection()
    sel:SetRecords(records, true)
    CHECK(sel:Count() == 10, "Ten ticked")

    local narrower = BuildFrom({ ROSTER[1], ROSTER[6], ROSTER[9] })
    local changed = sel:Prune(E.KeySet(narrower))
    CHECK(changed == true, "Prune reports it dropped keys")
    CHECK(sel:Count() == 3, "Only the survivors keep their tick")
    CHECK(sel:Get(KeyOf("Alaric")) and sel:Get(KeyOf("Fenna")) and sel:Get(KeyOf("Ingrid")),
        "The survivors are the right three")
    CHECK(sel:Prune(E.KeySet(narrower)) == false, "Pruning twice is a no-op")
    CHECK(sel:CountIn(narrower) == 3, "CountIn matches after a prune")
end

-- ===========================================================================
-- Range selection
-- ===========================================================================

do
    local records = BuildFrom(ROSTER)
    local keys = E.RangeKeys(records, 3, 6)
    CHECK(#keys == 4, "A 3..6 range is four keys")
    CHECK(keys[1] == "corwin" and keys[4] == "fenna", "The range is inclusive at both ends")

    local reversed = E.RangeKeys(records, 6, 3)
    CHECK(#reversed == 4 and reversed[1] == "corwin",
        "Dragging upward selects the same range as dragging downward")

    CHECK(#E.RangeKeys(records, nil, 4) == 0, "No anchor means no range")
    CHECK(#E.RangeKeys(records, 9, 40) == 2, "A range past the end stops at the end")
    CHECK(#E.RangeKeys(records, 5, 5) == 1, "A range of one is one key")
end

-- ===========================================================================
-- The whisper plan -- the fix for "mass whisper ignores the check marks"
-- ===========================================================================

do
    local records = BuildFrom(ROSTER)
    local sel = E.NewSelection()
    sel:Set(KeyOf("Brenna"), true)
    sel:Set(KeyOf("Halvard"), true)
    sel:Set(KeyOf("Corwin"), true)

    local plan = E.PlanWhispers(records, sel, {})
    CHECK(plan.ok == true, "Three ticked is a runnable plan")
    CHECK(plan.count == 3, "Exactly the ticked players are targeted")
    CHECK(plan.selected == 3, "selected counts the ticks")
    CHECK(plan.overCap == 0 and plan.skippedSelf == 0, "Nothing was dropped")
    CHECK(plan.targets[1].name == "Brenna", "Targets follow list order, not tick order")
    CHECK(plan.targets[2].name == "Corwin", "Targets follow list order (2)")
    CHECK(plan.targets[3].name == "Halvard", "Targets follow list order (3)")

    for i = 1, #plan.targets do
        CHECK(sel:Get(plan.targets[i].key), "Every target was actually ticked", i)
    end
end

do
    -- The 2.1 behaviour: everything got a message. Assert we do not.
    local records = BuildFrom(ROSTER)
    local sel = E.NewSelection()
    sel:Set(KeyOf("Dagny"), true)
    local plan = E.PlanWhispers(records, sel, {})
    CHECK(plan.count == 1, "One tick sends one whisper, not ten")
    CHECK(plan.targets[1].fullName == "Dagny", "And it goes to the player who was ticked")
end

do
    local records = BuildFrom(ROSTER)
    local sel = E.NewSelection()
    local plan = E.PlanWhispers(records, sel, {})
    CHECK(plan.ok == false, "No ticks is not a runnable plan")
    CHECK(plan.count == 0, "and targets nobody")
    CHECK(plan.reason and plan.reason:find("Nothing is selected"),
        "and says why", plan.reason)
end

do
    -- The cap counts what it refuses instead of truncating in silence.
    local records = BuildFrom(ROSTER)
    local sel = E.NewSelection()
    sel:SetRecords(records, true)
    local plan = E.PlanWhispers(records, sel, { maxTargets = 4 })
    CHECK(plan.count == 4, "The cap is respected")
    CHECK(plan.selected == 10, "The full selection is still reported")
    CHECK(plan.overCap == 6, "and the six it will not send are counted")
    CHECK(plan.targets[4].name == "Dagny", "The cap keeps the first N in list order")
    CHECK(E.DescribePlan(plan):find("6 over the 4 cap"),
        "The summary names the shortfall", E.DescribePlan(plan))
end

do
    local records = BuildFrom(ROSTER)
    local sel = E.NewSelection()
    sel:SetRecords(records, true)
    local plan = E.PlanWhispers(records, sel, { excludeKey = KeyOf("Eirik") })
    CHECK(plan.count == 9, "You are not one of your own recipients")
    CHECK(plan.skippedSelf == 1, "and the skip is counted")
    for i = 1, #plan.targets do
        CHECK(plan.targets[i].key ~= "eirik", "Eirik never appears in the targets", i)
    end
    CHECK(E.DescribePlan(plan):find("you were skipped"), "The summary says so")
end

do
    local records = BuildFrom(ROSTER)
    local sel = E.NewSelection()
    sel:Set(KeyOf("Eirik"), true)
    local plan = E.PlanWhispers(records, sel, { excludeKey = KeyOf("Eirik") })
    CHECK(plan.ok == false, "Ticking only yourself is not a runnable plan")
    CHECK(plan.reason:find("yourself"), "and says so", plan.reason)
end

do
    -- Selection is keyed, so a tick for someone who has dropped out of the
    -- results cannot smuggle them into a plan.
    local records = BuildFrom(ROSTER)
    local sel = E.NewSelection()
    sel:Set("ghost", true)
    sel:Set(KeyOf("Fenna"), true)
    local plan = E.PlanWhispers(records, sel, {})
    CHECK(plan.count == 1, "A key with no record contributes no target")
    CHECK(plan.targets[1].key == "fenna", "and the real one still goes")
end

do
    CHECK(E.DescribePlan(E.PlanWhispers(BuildFrom(ROSTER), E.NewSelection(), {})):find("Nothing is selected"),
        "DescribePlan reports a refusal verbatim")
    local sel = E.NewSelection()
    sel:Set(KeyOf("Alaric"), true)
    local one = E.DescribePlan(E.PlanWhispers(BuildFrom(ROSTER), sel, {}))
    CHECK(one == "Whispering 1 player.", "One recipient reads in the singular", one)
end

-- ===========================================================================
-- Message validation
-- ===========================================================================

do
    local text, err = E.ValidateMessage("  Recruiting for Karazhan  ")
    CHECK(text == "Recruiting for Karazhan", "A message is trimmed")
    CHECK(err == nil, "and accepted")

    CHECK(select(1, E.ValidateMessage("")) == nil, "Empty is refused")
    CHECK(select(2, E.ValidateMessage("   ")):find("Type a message"), "Whitespace-only is refused with a reason")
    CHECK(select(1, E.ValidateMessage(nil)) == nil, "nil is refused")

    local long = string.rep("x", E.MAX_WHISPER_LENGTH + 7)
    local ok, why = E.ValidateMessage(long)
    CHECK(ok == nil, "An over-length message is refused rather than truncated")
    CHECK(why:find("7 characters over"), "and says by how much", why)

    local exact = string.rep("y", E.MAX_WHISPER_LENGTH)
    CHECK(E.ValidateMessage(exact) == exact, "Exactly at the limit is accepted")
end

-- ===========================================================================
-- The run
-- ===========================================================================

do
    local records = BuildFrom(ROSTER)
    local sel = E.NewSelection()
    sel:Set(KeyOf("Alaric"), true)
    sel:Set(KeyOf("Brenna"), true)
    sel:Set(KeyOf("Corwin"), true)
    local plan = E.PlanWhispers(records, sel, {})
    local run = E.NewRun(plan, "hello")

    CHECK(run:IsActive(), "A fresh run is active")
    CHECK(run.total == 3, "and knows its size")
    CHECK(run:Progress() == "Sending 0 / 3", "Progress before the first send", run:Progress())

    local sent = {}
    for i = 1, 3 do
        local target, n, total = run:Next()
        CHECK(target ~= nil, "Next yields a target", i)
        CHECK(n == i and total == 3, "Next reports position and size", i)
        sent[#sent + 1] = target.fullName
    end
    CHECK(table.concat(sent, ",") == "Alaric,Brenna,Corwin", "Sent in list order", table.concat(sent, ","))

    -- The 2.1 ticker cancelled itself on the last iteration and only wrote
    -- "complete" on the iteration after, which therefore never ran.
    CHECK(run:Next() == nil, "The run yields nothing after the last target")
    CHECK(run.done == true, "and marks itself done")
    CHECK(run:IsActive() == false, "and is no longer active")
    CHECK(run:Progress() == "Sent 3 whispers.", "and says it finished", run:Progress())
    CHECK(run:Next() == nil, "Asking a finished run again is still nil")
    CHECK(run.sent == 3, "and does not inflate the count")
end

do
    local records = BuildFrom(ROSTER)
    local sel = E.NewSelection()
    sel:SetRecords(records, true)
    local run = E.NewRun(E.PlanWhispers(records, sel, {}), "hi")
    run:Next(); run:Next()
    run:Cancel()
    CHECK(run:IsActive() == false, "A cancelled run is not active")
    CHECK(run:Next() == nil, "and yields nothing more")
    CHECK(run.sent == 2, "and remembers how far it got")
    CHECK(run:Progress() == "Stopped after 2 of 10.", "and says so", run:Progress())
end

do
    local sel = E.NewSelection()
    sel:Set(KeyOf("Alaric"), true)
    local run = E.NewRun(E.PlanWhispers(BuildFrom(ROSTER), sel, {}), "hi")
    run:Next()
    run:Next()
    CHECK(run:Progress() == "Sent 1 whisper.", "One send reads in the singular", run:Progress())
end

do
    CHECK(E.EstimateSeconds(0, 1) == 0, "No recipients take no time")
    CHECK(E.EstimateSeconds(1, 1) == 0, "One recipient is immediate")
    CHECK(E.EstimateSeconds(10, 1) == 9, "Ten at a second apart is nine seconds of waiting")
    CHECK(math.abs(E.EstimateSeconds(25, 0.5) - 12) < 1e-9, "and scales with the delay")
end

-- ===========================================================================

if fails > 0 then
    io.write(string.format("\n%d/%d checks FAILED\n", fails, checks))
    os.exit(1)
end
io.write(string.format("who_harness: %d checks passed\n", checks))
