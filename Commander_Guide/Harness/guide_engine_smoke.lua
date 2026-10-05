-- Commander Guide engine smoke (luajit)
--
--     /opt/homebrew/bin/luajit Commander_Guide/Harness/guide_engine_smoke.lua
--
-- The guide and the reasoning with no client attached: the data validates,
-- a pull resolves by encounter id and by creature id, events earn the lines
-- they should and no others, cooldowns and once-per-pull hold, the speech
-- queue drops stale lines and lets urgent ones through, and a page reads
-- out loud.
--
-- Sections:
--   A  the data validates; every Karazhan boss has a healer page
--   B  resolution: encounter id, creature id, GUID parsing
--   C  Moroes: START, Garrote on a friend and on you, Vanish, Blind
--      interrupts, the enrage threshold fires once, death line
--   D  cooldowns, once, and events outside the pull are silent
--   E  the queue: stale drop, urgent to the front, delayed lines
--   F  Aran: Flame Wreath on you vs on a friend, first sightings
--   G  the brief and the page
--   H  formatting and estimates
--   I  the raid entrances: every door is Questie's point over 100 on the
--      zone the DB2 puts the raid in; the Add spec (resolver first, then the
--      table with every door an alternative); the /way line; the validator

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then HERE = (os.getenv("PWD") or ".") .. "/" .. HERE end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end
local function EQ(got, want, label)
    CHECK(got == want, label, string.format("got %s want %s", tostring(got), tostring(want)))
end

local function Load(path) assert(loadfile(path))() end
Load(ADDONS .. "/Commander_Guide/CommanderGuideData.lua")
Load(ADDONS .. "/Commander_Guide/CommanderGuideEngine.lua")
local D, E = CommanderGuide_Data, CommanderGuide_Engine

local function Says(items)
    local out = {}
    for _, it in ipairs(items or {}) do out[#out + 1] = it.say end
    return table.concat(out, " || ")
end

-- A ------------------------------------------------------------------------
do
    local problems = E.Validate(D)
    EQ(#problems, 0, "A: data validates")
    for _, p in ipairs(problems) do io.write("      ", p, "\n") end
    EQ(#D.RAIDS, 1, "A: one raid")
    EQ(D.RAIDS[1].key, "KARAZHAN", "A: it is Karazhan")
    EQ(#D.RAIDS[1].bosses, 11, "A: eleven bosses")
    for _, boss in ipairs(D.RAIDS[1].bosses) do
        CHECK(boss.roles.HEALER ~= nil, "A: healer page for " .. boss.title)
        CHECK(boss.roles.HEALER and #boss.roles.HEALER.callouts >= 1, "A: callouts for " .. boss.title)
        CHECK(boss.raid == D.RAIDS[1], "A: boss.raid back-link " .. boss.title)
    end
    -- every callout with an npc got a name
    for _, boss in ipairs(D.RAIDS[1].bosses) do
        for _, c in ipairs(boss.roles.HEALER.callouts) do
            if c.npc then CHECK(c.npcName ~= nil, "A: npc name for " .. tostring(c.npc)) end
        end
    end
end

-- B ------------------------------------------------------------------------
do
    EQ(E.BossForEncounter(D, 653).key, "MOROES", "B: encounter 653 is Moroes")
    EQ(E.BossForEncounter(D, 662).key, "NIGHTBANE", "B: encounter 662 is Nightbane")
    EQ(E.BossForEncounter(D, 1), nil, "B: unknown encounter is nil")
    EQ(E.BossForNpc(D, 16151).key, "ATTUMEN", "B: Midnight names Attumen")
    EQ(E.BossForNpc(D, 17521).key, "OPERA", "B: the Wolf names the Opera")
    EQ(E.BossForNpc(D, 99999), nil, "B: unknown npc is nil")
    EQ(E.NpcFromGUID("Creature-0-4379-532-19862-15687-00002B6E9A"), 15687, "B: creature GUID parses")
    EQ(E.NpcFromGUID("Vehicle-0-4379-532-19862-16816-00002B6E9A"), 16816, "B: vehicle GUID parses")
    EQ(E.NpcFromGUID("Player-4379-0123ABCD"), nil, "B: player GUID is nil")
    EQ(E.NpcFromGUID(nil), nil, "B: nil GUID is nil")
    EQ(E.BossByKey(D, "KARAZHAN", "ARAN").title, "Shade of Aran", "B: by key")
end

-- C ------------------------------------------------------------------------
do
    local ctx = E.NewSession(D, "HEALER")
    local now = 100
    local moroes = E.BossForEncounter(D, 653)
    local start = E.Begin(ctx, moroes, now, "encounter")
    EQ(#start, 1, "C: one START line")
    CHECK(start[1].say:find("Moroes"), "C: START names the boss", start[1].say)
    EQ(ctx.pulls, 1, "C: one pull")

    local garrote = E.Feed(ctx, { kind = "AURA_APPLIED", spell = 37066, dstName = "Thrall-Whitemane", dstIsFriendly = true }, now + 5)
    EQ(#garrote, 1, "C: Garrote on a friend earns a line")
    EQ(garrote[1].say, "Garrote on Thrall. Keep a heal on them.", "C: friend's first name in the line")
    EQ(garrote[1].priority, 2, "C: routine priority")

    local mine = E.Feed(ctx, { kind = "AURA_APPLIED", spell = 37066, dstName = "Me", dstIsMe = true, dstIsFriendly = true }, now + 9)
    EQ(#mine, 1, "C: Garrote on you earns a line")
    EQ(mine[1].say, "Garrote on you. Heal yourself between casts.", "C: sayMe wins for you")

    local hostile = E.Feed(ctx, { kind = "AURA_APPLIED", spell = 37066, dstName = "Moroes", dstNpc = 15687 }, now + 14)
    EQ(#hostile, 0, "C: Garrote on a non-player is silent")

    local vanish = E.Feed(ctx, { kind = "CAST_SUCCESS", spell = 29448, srcNpc = 15687 }, now + 20)
    EQ(Says(vanish), "Vanish. Garrote coming. Top everyone up.", "C: Vanish line")

    local blind = E.Feed(ctx, { kind = "AURA_APPLIED", spell = 34694, dstIsMe = true, dstIsFriendly = true }, now + 25)
    EQ(blind[1] and blind[1].priority, 1, "C: Blind on you is urgent")
    EQ(blind[1] and blind[1].say, "You are blind. Others cover your targets.", "C: Blind on you text")

    local high = E.Feed(ctx, { kind = "HEALTH", npc = 15687, pct = 55 }, now + 30)
    EQ(#high, 0, "C: 55 percent is above the threshold")
    local low = E.Feed(ctx, { kind = "HEALTH", npc = 15687, pct = 31 }, now + 40)
    EQ(Says(low), "Moroes enraged. Everything on the tank.", "C: 31 percent fires the enrage line")
    local lower = E.Feed(ctx, { kind = "HEALTH", npc = 15687, pct = 20 }, now + 50)
    EQ(#lower, 0, "C: the threshold fires once")

    local died = E.Feed(ctx, { kind = "UNIT_DIED", dstNpc = 15687 }, now + 60)
    EQ(Says(died), "Moroes down. Garrotes fall off now.", "C: death line via dstNpc")

    local fin = E.Finish(ctx, now + 61, true)
    EQ(ctx.boss, nil, "C: finished clears the boss")
    EQ(#fin, 0, "C: no END lines written for Moroes")
end

-- D ------------------------------------------------------------------------
do
    local ctx = E.NewSession(D, "HEALER")
    local now = 0
    -- silent outside a pull, even for a matching spell
    local none = E.Feed(ctx, { kind = "AURA_APPLIED", spell = 37066, dstIsFriendly = true }, now)
    EQ(#none, 0, "D: no boss, no lines")
    -- creature id fallback resolves the boss only in combat
    ctx.inCombat = false
    local still = E.Feed(ctx, { kind = "CAST_START", spell = 29405, srcNpc = 15687 }, now)
    EQ(#still, 0, "D: out of combat the fallback stays quiet")
    ctx.inCombat = true
    local auto = E.Feed(ctx, { kind = "CAST_START", spell = 29405, srcNpc = 15687 }, now + 1)
    EQ(ctx.boss and ctx.boss.key, "MOROES", "D: a creature id in combat names the pull")
    EQ(ctx.source, "npc", "D: source is npc")
    EQ(#auto, 2, "D: START and the Mana Burn line both come out")
    CHECK(auto[1].say:find("Moroes"), "D: START first")
    CHECK(auto[2].say:find("Mana Burn"), "D: then the event's line")
    -- cooldown
    local again = E.Feed(ctx, { kind = "CAST_START", spell = 29405, srcNpc = 15687 }, now + 5)
    EQ(#again, 0, "D: Mana Burn inside its 15 s cooldown is silent")
    local later = E.Feed(ctx, { kind = "CAST_START", spell = 29405, srcNpc = 15687 }, now + 17)
    EQ(#later, 1, "D: after the cooldown it speaks again")
    -- the cooldown is per person for lines about a person
    local g1 = E.Feed(ctx, { kind = "AURA_APPLIED", spell = 37066, dstName = "A", dstIsFriendly = true }, now + 18)
    local g2 = E.Feed(ctx, { kind = "AURA_APPLIED", spell = 37066, dstName = "B", dstIsFriendly = true }, now + 18.5)
    local g3 = E.Feed(ctx, { kind = "AURA_APPLIED", spell = 37066, dstName = "A", dstIsFriendly = true }, now + 19)
    EQ(#g1 + #g2, 2, "D: Garrote on two people inside one cooldown speaks twice")
    EQ(#g3, 0, "D: the same person inside the cooldown is silent")
    -- a different boss's spell during this pull is silent
    local wrong = E.Feed(ctx, { kind = "AURA_APPLIED", spell = 29522, dstIsFriendly = true }, now + 20)
    EQ(#wrong, 0, "D: Maiden's Holy Fire during Moroes is silent")
    -- a second Begin of the same boss does not restart
    local rebegin = E.Begin(ctx, ctx.boss, now + 21, "encounter")
    EQ(#rebegin, 0, "D: Begin on the same boss is a no-op")
    EQ(ctx.pulls, 1, "D: still one pull")
end

-- E ------------------------------------------------------------------------
do
    local ctx = E.NewSession(D, "HEALER")
    local now = 0
    E.Begin(ctx, E.BossForEncounter(D, 653), now)
    E.Clear(ctx)
    -- routine lines queue in order
    E.Enqueue(ctx, { { say = "one", text = "one", priority = 2, at = now }, { say = "two", text = "two", priority = 2, at = now } }, now)
    EQ(#ctx.queue, 2, "E: two queued")
    -- urgent goes to the front and clears routine
    local interrupt = E.Enqueue(ctx, { { say = "urgent", text = "urgent", priority = 1, at = now } }, now)
    EQ(interrupt, true, "E: urgent asks to interrupt")
    EQ(#ctx.queue, 1, "E: routine lines dropped behind an urgent one")
    EQ(E.Next(ctx, now).say, "urgent", "E: urgent is next")
    EQ(E.Next(ctx, now), nil, "E: queue empty after")
    -- stale drop
    E.Enqueue(ctx, { { say = "old", text = "old", priority = 2, at = now } }, now)
    EQ(E.Next(ctx, now + E.STALE + 1), nil, "E: a stale line is dropped")
    E.Enqueue(ctx, { { say = "fresh", text = "fresh", priority = 2, at = now + 10 } }, now + 10)
    EQ(E.Next(ctx, now + 12).say, "fresh", "E: a fresh one is said")
    -- delayed lines wait for Tick
    E.Enqueue(ctx, { { say = "later", text = "later", priority = 2, delay = 3, at = now + 20 } }, now + 20)
    EQ(#ctx.queue, 0, "E: delayed line not queued yet")
    EQ(#ctx.delayed, 1, "E: it is held")
    E.Tick(ctx, now + 22)
    EQ(#ctx.queue, 0, "E: not due yet")
    E.Tick(ctx, now + 23)
    EQ(#ctx.queue, 1, "E: due, now queued")
    EQ(E.Next(ctx, now + 23).say, "later", "E: and said fresh")
    -- Clear empties both
    E.Enqueue(ctx, { { say = "x", text = "x", priority = 2, delay = 5, at = now }, { say = "y", text = "y", priority = 2, at = now } }, now)
    E.Clear(ctx)
    EQ(#ctx.queue + #ctx.delayed, 0, "E: Clear empties the queue and the held lines")
    -- Finish clears too
    E.Enqueue(ctx, { { say = "z", text = "z", priority = 2, at = now } }, now)
    E.Finish(ctx, now)
    EQ(#ctx.queue, 0, "E: Finish empties the queue")
end

-- F ------------------------------------------------------------------------
do
    local ctx = E.NewSession(D, "HEALER")
    local now = 0
    E.Begin(ctx, E.BossForEncounter(D, 658), now)
    local cast = E.Feed(ctx, { kind = "CAST_START", spell = 30004, srcNpc = 16524 }, now + 1)
    EQ(Says(cast), "Flame Wreath. Nobody moves.", "F: Flame Wreath cast line")
    EQ(cast[1].priority, 1, "F: it is urgent")
    local friend = E.Feed(ctx, { kind = "AURA_APPLIED", spell = 29946, dstName = "Jaina", dstIsFriendly = true }, now + 6)
    EQ(#friend, 0, "F: the wreath aura on a friend is silent (whom = me)")
    local me = E.Feed(ctx, { kind = "AURA_APPLIED", spell = 29946, dstIsMe = true, dstIsFriendly = true }, now + 6)
    EQ(Says(me), "Wreath on you. Stand still twenty seconds.", "F: on you it speaks")
    local gone = E.Feed(ctx, { kind = "AURA_REMOVED", spell = 29946, dstIsMe = true, dstIsFriendly = true }, now + 26)
    EQ(Says(gone), "Wreath gone. You can move.", "F: and again when it fades")
    -- first sighting: an elemental's first appearance in the log, once
    local ele = E.Feed(ctx, { kind = "CAST_START", spell = 31012, srcNpc = 17167 }, now + 40)
    EQ(Says(ele), "Water elementals. Ninety seconds. Heal their targets.", "F: first elemental sighting")
    local ele2 = E.Feed(ctx, { kind = "CAST_START", spell = 31012, srcNpc = 17167 }, now + 41)
    EQ(#ele2, 0, "F: the second sighting is silent")
    -- Netherspite stacks
    local ctx2 = E.NewSession(D, "HEALER")
    E.Begin(ctx2, E.BossForEncounter(D, 659), now)
    local low = E.Feed(ctx2, { kind = "DOSE", spell = 30422, stacks = 12, dstIsMe = true, dstIsFriendly = true }, now + 1)
    EQ(#low, 0, "F: 12 stacks of green is quiet")
    local hi = E.Feed(ctx2, { kind = "DOSE", spell = 30422, stacks = 20, dstIsMe = true, dstIsFriendly = true }, now + 2)
    EQ(Says(hi), "Twenty stacks. Swap out soon.", "F: 20 stacks speaks")
    -- yells
    local ctx3 = E.NewSession(D, "HEALER")
    E.Begin(ctx3, E.BossForEncounter(D, 662), now)
    local yell = E.Feed(ctx3, { kind = "YELL", text = "Miserable vermin. I shall exterminate you from the air!" }, now + 1)
    CHECK(yell[1] and yell[1].say:find("Taking off"), "F: Nightbane's takeoff yell matched", Says(yell))
    local other = E.Feed(ctx3, { kind = "YELL", text = "Something unrelated" }, now + 2)
    EQ(#other, 0, "F: an unrelated yell is silent")
end

-- G ------------------------------------------------------------------------
do
    local aran = E.BossForEncounter(D, 658)
    local brief = E.Brief(aran, "HEALER")
    CHECK(brief:sub(1, 14) == "Shade of Aran.", "G: brief opens with the title", brief:sub(1, 30))
    CHECK(brief:find("Your job.", 1, true), "G: brief has the job")
    CHECK(not brief:find("40 percent: Polymorph", 1, true), "G: short brief skips phases")
    local full = E.Brief(aran, "HEALER", { full = true })
    CHECK(full:find("40 percent: Polymorph", 1, true), "G: full brief has phases")
    CHECK(#full > #brief, "G: full is longer")
    EQ(E.Brief(aran, "TANK"), nil, "G: no tank page yet")
    local page = E.Page(aran, "HEALER")
    EQ(page[1].kind, "lead", "G: page opens with the lead")
    EQ(page[2].kind, "bullets", "G: then the job")
    EQ(page[3].kind, "phases", "G: then phases")
    EQ(page[4].kind, "watch", "G: then the watch list")
    EQ(page[5].kind, "callouts", "G: then the callouts")
    local chess = E.BossForEncounter(D, 660)
    local cpage = E.Page(chess, "HEALER")
    local kinds = {}
    for _, s in ipairs(cpage) do kinds[#kinds + 1] = s.kind end
    EQ(table.concat(kinds, ","), "lead,bullets,phases,callouts", "G: chess has no watch section")
    -- When() sentences
    EQ(E.When({ on = "AURA_APPLIED", spell = 37066, spellName = "Garrote" }), "When Garrote lands on a player", "G: When for an aura")
    EQ(E.When({ on = "AURA_APPLIED", spell = 29946, whom = "me", spellName = "Flame Wreath" }), "When Flame Wreath lands on you", "G: When for you")
    EQ(E.When({ on = "HEALTH", npc = 15687, npcName = "Moroes", below = 32 }), "When Moroes is under 32 percent", "G: When for health")
    EQ(E.When({ on = "START" }), "On the pull", "G: When for START")
    EQ(E.When({ on = "UNIT_DIED", npc = 17229, npcName = "Kil'rek" }), "When Kil'rek dies", "G: When for a death")
end

-- H ------------------------------------------------------------------------
do
    EQ(E.Format("Garrote on %t.", { dstName = "Thrall-Whitemane" }), "Garrote on Thrall.", "H: realm stripped")
    EQ(E.Format("Garrote on %t.", { dstIsMe = true, dstName = "Me" }), "Garrote on you.", "H: you")
    EQ(E.Format("Garrote on %t.", nil), "Garrote on them.", "H: no event")
    EQ(E.Format("No target here.", { dstName = "X" }), "No target here.", "H: nothing to replace")
    EQ(E.ShortName("Name-Realm"), "Name", "H: ShortName")
    EQ(E.ShortName(nil), "", "H: ShortName nil")
    local slow = E.Estimate("one two three four five six seven eight nine ten", 0)
    CHECK(slow > 3 and slow < 5, "H: ten words take three to five seconds", slow)
    CHECK(E.Estimate("one two three", 5) < E.Estimate("one two three", 0), "H: a faster rate is shorter")
    CHECK(E.Estimate("", 0) > 0, "H: an empty line still takes a beat")
    -- whom defaults
    EQ(E.Whom({ on = "AURA_APPLIED" }), "friend", "H: aura defaults to friend")
    EQ(E.Whom({ on = "CAST_START" }), "any", "H: cast defaults to any")
    EQ(E.Whom({ on = "DAMAGE", whom = "me" }), "me", "H: explicit wins")
end

-- I ------------------------------------------------------------------------
-- The raid entrances (1.1.0, DECISIONS D11). The table is a frozen copy of
-- installed data, so the check is against that data: Questie's TBC raid rows
-- (QuestieDB/support/Zones/dungeons.lua, 0..100) and the parent of each
-- raid's uiMap in this build's UiMap DB2, which must be the zone the door
-- stands in. A wrong division, a swapped x and y or a door filed on the
-- wrong zone fails here.
do
    local QUESTIE = {   -- instanceMapID -> { zone uiMap, { x, y } 0..100, ... } (dungeons.lua [4])
        [532] = { 1430, { 46.7, 70.2 }, { 46.9, 74.7 } },
        [565] = { 1949, { 68.7, 24.3 } },
        [544] = { 1944, { 46.6, 52.81 } },
        [548] = { 1946, { 50.4, 40.9 } },
        [550] = { 1953, { 73.7, 63.7 } },
        [534] = { 1446, { 65.7, 49.8 } },
        [564] = { 1948, { 71, 46.4 } },
        [568] = { 1942, { 82.25, 64.3 } },
        [580] = { 1957, { 44.3, 45.5 } },
    }
    local UIMAP_PARENT = {  -- UiMap.csv: raid uiMap -> ParentUiMapID
        [350] = 1430, [330] = 1949, [331] = 1944, [332] = 1946, [334] = 1953,
        [329] = 1446, [339] = 1948, [333] = 1942, [335] = 1957,
    }
    local n = 0
    for id, row in pairs(D.ENTRANCES) do
        n = n + 1
        local q = QUESTIE[id]
        CHECK(q ~= nil, "I: entrance " .. id .. " is a TBC raid Questie lists")
        if q then
            EQ(#row.points, #q - 1, "I: " .. row.title .. " has Questie's number of doors")
            for i, p in ipairs(row.points) do
                local want = q[i + 1]
                EQ(p.map, q[1], "I: " .. row.title .. " door " .. i .. " is on Questie's zone")
                CHECK(want and math.abs(p.x * 100 - want[1]) < 1e-9 and math.abs(p.y * 100 - want[2]) < 1e-9,
                    "I: " .. row.title .. " door " .. i .. " is Questie's point over 100",
                    string.format("%s, %s", tostring(p.x), tostring(p.y)))
            end
        end
        EQ(UIMAP_PARENT[row.raidMap], row.points[1].map,
            "I: " .. row.title .. "'s raid map sits on the door's zone in the DB2")
    end
    EQ(n, 9, "I: all nine TBC raids have a door")
    CHECK(D.ENTRANCES[D.RAIDS[1].instanceMapID] ~= nil, "I: every raid with pages has a door")

    -- The spec: the cited table, every door an alternative
    local kara = D.RAIDS[1]
    local spec, via = E.EntranceSpec(D, kara, nil)
    CHECK(spec ~= nil, "I: Karazhan has a spec")
    EQ(via, "table", "I: ...from the table when no resolver answered")
    EQ(spec.map, 1430, "I: on Deadwind Pass")
    EQ(spec.x, 0.467, "I: the first door's x")
    EQ(spec.title, "Karazhan entrance", "I: titled")
    EQ(spec.source, "Guide", "I: owned by the Guide")
    EQ(spec.key, "entrance:KARAZHAN", "I: one key per raid, so a second press moves it")
    EQ(spec.setArrow, true, "I: a button press takes the arrow")
    EQ(spec.alternatives and #spec.alternatives, 2, "I: both doors are alternatives")
    CHECK(spec.alternatives and spec.alternatives[2].y == 0.747, "I: the second door is the second alternative")
    CHECK(spec.alternatives and spec.alternatives[1] ~= D.ENTRANCES[532].points[1],
        "I: alternatives are copies, never the data's own tables")

    -- A resolver's answer wins when it is a position, and only then
    spec, via = E.EntranceSpec(D, kara, { map = 1430, x = 0.5, y = 0.75, title = "x" })
    EQ(via, "resolver", "I: a usable resolver answer wins")
    EQ(spec.x, 0.5, "I: ...with its own point")
    EQ(spec.alternatives, nil, "I: ...and no table alternatives mixed in")
    EQ(spec.title, "Karazhan entrance", "I: ...under the guide's own title")
    -- The Quest Log's resolver (beside Questie, the suite's normal setup)
    -- answers Questie's FIRST door only. A resolver point that IS one of the
    -- table's doors brings the other doors along, so the arrow still takes
    -- the nearer one
    spec, via = E.EntranceSpec(D, kara, { map = 1430, x = 46.7 / 100, y = 70.2 / 100, title = "Karazhan entrance" })
    EQ(via, "resolver", "I: Questie's first door through a resolver")
    EQ(spec.x, 46.7 / 100, "I: ...keeps the resolver's own point")
    EQ(spec.alternatives and #spec.alternatives, 2, "I: ...and carries both doors as alternatives")
    CHECK(spec.alternatives and spec.alternatives[2].y == 0.747, "I: ...the southern door among them")
    CHECK(spec.alternatives and spec.alternatives[1] ~= D.ENTRANCES[532].points[1],
        "I: ...as copies, never the data's own tables")
    spec = E.EntranceSpec(D, kara, { map = 1430, x = 0.469, y = 0.747 })
    EQ(spec.alternatives and #spec.alternatives, 2, "I: the second door through a resolver: both doors too")
    spec = E.EntranceSpec(D, kara, { map = 1431, x = 0.467, y = 0.702 })
    EQ(spec.alternatives, nil, "I: the same numbers on another map are not a door")
    spec = E.EntranceSpec(D, { key = "GRUUL", title = "Gruul's Lair", instanceMapID = 565 },
        { map = 1949, x = 0.687, y = 0.243 })
    EQ(spec.alternatives, nil, "I: a one-door raid's resolver answer gets no alternatives")
    for _, junk in ipairs({ { map = 1430, x = 2, y = 0.5 }, { map = "1430", x = 0.5, y = 0.5 },
                            { map = 1430, x = 0 / 0, y = 0.5 }, { x = 0.5, y = 0.5 }, "door" }) do
        spec, via = E.EntranceSpec(D, kara, junk)
        EQ(via, "table", "I: a junk resolver answer falls back to the table")
    end

    -- A single-door raid has no alternatives; a raid with no row has no spec
    local gruul = { key = "GRUUL", title = "Gruul's Lair", instanceMapID = 565 }
    spec = E.EntranceSpec(D, gruul, nil)
    CHECK(spec and spec.map == 1949 and spec.alternatives == nil, "I: one door, no alternatives")
    EQ(E.EntranceSpec(D, { key = "X", title = "Nowhere", instanceMapID = 1 }, nil), nil, "I: an unknown raid has no spec")
    EQ(E.EntranceSpec(D, nil, nil), nil, "I: no raid, no spec")

    -- The /way line, in Commander Orders' own grammar
    EQ(E.WayLine(E.EntranceSpec(D, kara, nil)), "/way #1430 46.70 70.20 Karazhan entrance", "I: the /way line")
    EQ(E.WayLine({ map = 1949, x = 0.687, y = 0.243 }), "/way #1949 68.70 24.30", "I: untitled line")
    EQ(E.WayLine({ map = 1949, x = 1.5, y = 0.2 }), nil, "I: no line for a non-position")

    -- The validator watches the table too
    local saved = D.ENTRANCES[532]
    D.ENTRANCES[532] = nil
    local problems = E.Validate(D)
    CHECK(#problems == 1 and problems[1]:find("no entrance", 1, true), "I: a raid without a door fails validation", problems[1])
    D.ENTRANCES[532] = { title = "Karazhan", raidMap = 350, zone = "Deadwind Pass", points = { { map = 1430, x = 70.2, y = 46.7 } } }
    problems = E.Validate(D)
    CHECK(#problems == 1 and problems[1]:find("not a map position", 1, true), "I: an undivided point fails validation", problems[1])
    D.ENTRANCES[532] = saved
    EQ(#E.Validate(D), 0, "I: restored, clean again")
end

io.write(string.format("%d checks, %d failed\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
