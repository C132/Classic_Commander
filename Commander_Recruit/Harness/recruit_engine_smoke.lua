-- Commander Recruit engine smoke (luajit). No WoW mock: the engine is pure.
--
--   /opt/homebrew/bin/luajit recruit_engine_smoke.lua
--
--   A  names: keys, realms, the bare-name flag
--   B  the book: sightings merge, freshness, Gone, pruning
--   C  the board: brackets apart, highest first, ties, filters, unrated
--   D  the sweep: one query per class, the race split at the cap, partials
--   E  the steered sweep (R20): the roster in, queries by expected finds,
--      answers counted, offline proved, arena zones on a timer, the fallback
--   F  a simulated peak hour: steered against the fixed plan
--   G  race and talent-tree icons (R22): atlases, sex, trees, the book keeps them
--   J  name fragments (R26): pieces, coverage until n- is known, the start-only
--      fallback; the sweep's own depth
--   H  fewer queries (R23): the stop at 2, odds and asked queries remembered across
--      sweeps and fading back, the forecast of presses left
--   K  another realm (R27): written realms, bare group finder names placed by the
--      feed, other sources settling them as ours, the board's skip

local ADDONS = "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail ~= nil and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end
local function EQ(got, want, label)
    CHECK(got == want, label, string.format("got %s want %s", tostring(got), tostring(want)))
end

assert(loadfile(ADDONS .. "/Commander_Recruit/CommanderRecruitEngine.lua"))()
local E = CommanderRecruit_Engine

-- === A: names ===============================================================
do
    local key, name, realm, bare = E.Key("Stabby-Nightslayer", "Dreamscythe")
    CHECK(key == "Stabby-Nightslayer" and name == "Stabby" and realm == "Nightslayer" and bare == false,
        "A a written realm is kept and is not a guess")
    key, name, realm, bare = E.Key("Stabby", "Dreamscythe")
    CHECK(key == "Stabby-Dreamscythe" and realm == "Dreamscythe" and bare == true,
        "A a bare name is filed on our realm, flagged as a guess")
    EQ(E.Key("Kel-Living Flame"), "Kel-LivingFlame", "A a realm loses its spaces")
    EQ(E.Key(""), nil, "A no name, no key")
    EQ(E.Key(nil), nil, "A nil, no key")
end

-- === B: the book ============================================================
do
    local book = E.NewBook()
    local p = E.Note(book, { fullName = "Stabby", class = "ROGUE", level = 70, zone = "Shattrath City" },
        100, "lfg", "Dreamscythe")
    CHECK(p and p.class == "ROGUE" and p.level == 70 and p.source == "lfg" and p.at == 100, "B a sighting is filed")
    E.Note(book, { fullName = "Stabby-Dreamscythe", guild = "Lords" }, 160, "who", "Dreamscythe")
    p = book.players["Stabby-Dreamscythe"]
    CHECK(p.at == 160 and p.source == "who" and p.guild == "Lords", "B a later sighting refreshes the time and source")
    CHECK(p.class == "ROGUE" and p.zone == "Shattrath City", "B ...and never forgets what it knew")
    CHECK(p.bare == false, "B a written realm settles an earlier guess")
    E.Note(book, { fullName = "Stabby-Dreamscythe", guild = "" }, 170, "who", "Dreamscythe")
    CHECK(book.players["Stabby-Dreamscythe"].guild == nil, "B a /who that says no guild clears the guild")

    E.Note(book, { fullName = "Old-Dreamscythe" }, 10, "chat", "Dreamscythe")
    E.Note(book, { fullName = "Ancient-Dreamscythe" }, -5000, "chat", "Dreamscythe")
    local fresh = E.Fresh(book, 200, 120, 3600)
    local seen = {}
    for _, f in ipairs(fresh) do seen[f.key] = true end
    CHECK(seen["Stabby-Dreamscythe"] and not seen["Old-Dreamscythe"], "B only the fresh are on the board")
    CHECK(book.players["Old-Dreamscythe"] ~= nil, "B ...the stale are kept a while")
    CHECK(book.players["Ancient-Dreamscythe"] == nil, "B ...and the long gone are pruned")
    E.Gone(book, "Stabby", "Dreamscythe")
    CHECK(book.players["Stabby-Dreamscythe"] == nil, "B gone offline: off at once")
    CHECK(E.Note(book, {}, 1, "who") == nil and E.Note(book, nil, 1, "who") == nil, "B a sighting with no name is ignored")
end

-- === C: the board ===========================================================
do
    local players = {
        { key = "A-R", class = "ROGUE", at = 10 },
        { key = "B-R", class = "MAGE", at = 20 },
        { key = "C-R", class = "PRIEST", at = 30 },
        { key = "D-R", class = "WARRIOR", at = 40 },
        { key = "E-R", class = "MAGE", at = 50 },
    }
    local ratings = {
        ["A-R"] = { [2] = { rating = 2100, wins = 60, played = 100, best = 2200 }, [3] = { rating = 1500, wins = 5, played = 9 } },
        ["B-R"] = { [3] = { rating = 2300, wins = 80, played = 120 } },
        ["C-R"] = { [2] = { rating = 1800, wins = 10, played = 20 }, [5] = { rating = 1900, wins = 3, played = 5 } },
        ["D-R"] = nil,
        ["E-R"] = { [2] = { rating = 1800, wins = 1, played = 1 } },
    }
    local function For(p) return ratings[p.key] end
    local board = E.Board(players, For)
    EQ(#board[2], 3, "C three rated in 2v2")
    EQ(#board[3], 2, "C two in 3v3")
    EQ(#board[5], 1, "C one in 5v5")
    EQ(board[2][1].player.key, "A-R", "C highest rating first")
    EQ(board[2][1].lost, 40, "C losses are played less wins")
    EQ(board[2][1].best, 2200, "C the season best rides along")
    EQ(board[2][2].player.key, "E-R", "C a tie goes to the one seen more recently")
    EQ(board[3][1].player.key, "B-R", "C each bracket has its own order")
    EQ(board.unrated, 1, "C the warrior with no rating is counted, not listed")
    EQ(board.online, 5, "C everyone online is counted")
    local A = 0
    for _, size in ipairs(E.BRACKETS) do for _, row in ipairs(board[size]) do if row.player.key == "A-R" then A = A + 1 end end end
    EQ(A, 2, "C one player can stand on two brackets")

    board = E.Board(players, For, { minRating = 1900 })
    EQ(#board[2], 1, "C a minimum rating hides the rest of 2v2")
    EQ(#board[5], 1, "C ...per bracket")
    EQ(board.unrated, 1, "C ...without calling them unrated")
    board = E.Board(players, For, { classes = { MAGE = true } })
    CHECK(#board[2] == 1 and board[2][1].player.key == "E-R" and board.online == 2, "C a class filter keeps the class")
    board = E.Board({}, For)
    CHECK(#board[2] == 0 and board.online == 0 and board.unrated == 0, "C nobody online is an empty board")
end

-- === D: the sweep ===========================================================
do
    local names = { WARRIOR = "Warrior", NightElf = "Night Elf", Scourge = "Undead", DRUID = "Druid" }
    local sweep = E.NewSweep("Alliance", names)
    EQ(sweep.total, 9, "D Alliance: a query for each of the nine classes it can be")
    local q = E.SweepNext(sweep)
    EQ(q.text, '70-70 c-"Warrior"', "D level 70, the class quoted")
    E.SweepResult(sweep, 12, 12)
    EQ(sweep.done, 1, "D an answer under the cap is one step")
    EQ(E.SweepNext(sweep).class, "PALADIN", "D ...and the next class is next")
    E.SweepResult(sweep, 50, 120)
    local done, total = E.SweepProgress(sweep)
    CHECK(done == 2 and total == 12, "D a capped class adds its three races", done .. "/" .. total)
    q = E.SweepNext(sweep)
    CHECK(q.class == "PALADIN" and q.race == "Human" and q.text:find('r-"Human"'), "D ...asked straight away", q.text)
    E.SweepResult(sweep, 50, 50)
    EQ(#sweep.partial, 1, "D a race at the cap is partial, not split again")
    E.SweepResult(sweep, 3, 3)
    E.SweepResult(sweep, 0, 0, true)
    EQ(E.SweepNext(sweep).class, "HUNTER", "D the class finishes before the next begins")
    CHECK(#sweep.unanswered == 1 and sweep.unanswered[1]:find('r-"Draenei"'),
        "D a query that got no answer is recorded and the plan moves on", sweep.unanswered[1])
    for _ = 1, 30 do if not E.SweepFinished(sweep) then E.SweepResult(sweep, 1, 1) end end
    CHECK(E.SweepFinished(sweep), "D the plan runs out")
    E.SweepResult(sweep, 1, 1)
    CHECK(E.SweepFinished(sweep), "D an answer after the end is ignored")

    local horde = E.NewSweep("Horde", names)
    EQ(horde.total, 9, "D Horde: nine classes too (paladins and shamans both exist on both sides in TBC)")
    local druid
    for _, qq in ipairs(horde.queue) do if qq.class == "DRUID" then druid = qq end end
    while E.SweepNext(horde) ~= druid do E.SweepResult(horde, 1, 1) end
    E.SweepResult(horde, 50, 99)
    local q2 = E.SweepNext(horde)
    CHECK(q2.race == "Tauren" and q2.class == "DRUID", "D a Horde druid splits into Tauren only")
    E.SweepResult(horde, 10, 10)
    CHECK(E.SweepFinished(horde), "D ...and that was the last of it")

    -- Every class/race pair the split can ask for is real for that faction
    local bad = 0
    for faction, races in pairs(E.RACES) do
        for class, ok in pairs(E.CLASS_RACES) do
            local any = false
            for _, race in ipairs(races) do if ok[race] then any = true end end
            if not any then bad = bad + 1 end
        end
    end
    EQ(bad, 0, "D every class is playable on both factions in TBC")
    EQ(E.Query("NightElf", nil, names):find('c-"Night Elf"') ~= nil, true, "D a two-word name is quoted whole")
    EQ(E.Query("WARRIOR", "Scourge", names), '70-70 c-"Warrior" r-"Undead"', "D a race token is asked by its /who name")
    EQ(E.Query("WARRIOR", nil, {}, 60), '60-60 c-"WARRIOR"', "D an unnamed token falls back to itself")
end

-- === E: the steered sweep (R20) ============================================
do
    -- these fixtures are sized for the stop at 1 (R20); R23's stop is checked on its own
    local stopWas = E.MIN_EXPECT
    E.MIN_EXPECT = 1.0
    local fragmentsWere = E.NAME_FRAGMENTS
    E.NAME_FRAGMENTS = false -- class and guild logic only (R26 has its own section)
    local NOW = 1792300000
    local DAY = 86400
    EQ(E.Activity(NOW - 3600, NOW), 1.0, "E logged in today counts fully")
    EQ(E.Activity(NOW - 5 * DAY, NOW), 0.45, "E ...five days ago, less")
    EQ(E.Activity(NOW - 90 * DAY, NOW), E.ACTIVITY_OLD, "E ...three months ago, hardly")
    EQ(E.Activity(nil, NOW), E.ACTIVITY_UNKNOWN, "E an unknown login counts a little")

    local names = { ROGUE = "Rogue", MAGE = "Mage", PRIEST = "Priest", WARRIOR = "Warrior",
        BloodElf = "Blood Elf", Scourge = "Undead", Troll = "Troll", Human = "Human" }
    local function P(key, class, race, guild, daysAgo, best, faction)
        return { key = key .. "-Dreamscythe", name = key, faction = faction or "H", class = class, race = race,
            guild = guild, last = daysAgo and NOW - daysAgo * DAY or nil, best = best or 1800 }
    end
    local roster = {
        P("Ga1", "ROGUE", "BloodElf", "Gank Squad", 0), P("Ga2", "MAGE", "Troll", "Gank Squad", 0),
        P("Ga3", "PRIEST", "Scourge", "Gank Squad", 0), P("Ga4", "ROGUE", "Scourge", "Gank Squad", 1),
        P("Ga5", "WARRIOR", "Troll", "Gank Squad", 0), P("Ga6", "MAGE", "Scourge", "Gank Squad", 2),
        P("Lo1", "ROGUE", "BloodElf", nil, 0), P("Lo2", "ROGUE", "BloodElf", nil, 0),
        P("Lo3", "ROGUE", "BloodElf", nil, 0), P("Lo4", "ROGUE", "BloodElf", "Tiny", 0),
        P("Old", "MAGE", "Troll", "Ghosts", 200),
        P("Low", "PRIEST", "Troll", nil, 0, 1500),
        P("Ally", "PRIEST", "Human", "Lions", 0, 2400, "A"),
        P("Bad", "PALADIN", "Troll", nil, 0),            -- no troll paladins in TBC
        { key = "Odd-Dreamscythe", faction = "H" },     -- an entry with nothing in it
    }
    CHECK(E.NewSteeredSweep(nil, { faction = "Horde" }) == nil, "E no roster: no steered sweep (the fixed plan instead)")
    CHECK(E.NewSteeredSweep({}, { faction = "Horde" }) == nil, "E an empty roster: the same")
    CHECK(E.NewSteeredSweep({ roster[13] }, { faction = "Horde" }) == nil, "E nobody of our faction: the same")
    CHECK(E.NewSteeredSweep(roster, { faction = "Neutral" }) == nil, "E no faction: the same")

    local function Steer(learned, minRating)
        return E.NewSteeredSweep(roster, { faction = "Horde", names = names, now = NOW, learned = learned or E.NewLearned(),
            minRating = minRating or 1600 })
    end
    local function ByText(list)
        local t = {}
        for _, c in ipairs(list) do t[c.text] = c end
        return t
    end
    local function Near(a, b) return a and b and math.abs(a - b) < 1e-9 end
    local learned = E.NewLearned()
    local sweep = Steer(learned)
    CHECK(sweep and sweep.mode == "steered", "E a roster with our faction steers")
    EQ(sweep.rated, 11, "E our faction's real class/race pairs at or above the lowest rating shown")
    CHECK(sweep.byKey["Ally-Dreamscythe"] == nil and sweep.byKey["Bad-Dreamscythe"] == nil
        and sweep.byKey["Low-Dreamscythe"] == nil, "E the other faction, an impossible pair and a 1500 are left out")
    EQ(sweep.guildCount, 3, "E three guilds hold them")
    CHECK(Near(sweep.byKey["Ga6-Dreamscythe"].odds, 0.7 * E.ONLINE_SHARE), "E a player's odds of being on start from their last login")

    local list = E.SteerCandidates(sweep, {}, NOW)
    local by = ByText(list)
    local gank = by['70-70 g-"Gank Squad"']
    CHECK(gank and Near(gank.expect, (1 + 1 + 1 + 1 + 1 + 0.7) * E.ONLINE_SHARE),
        "E a guild expects its players' odds", gank and gank.expect)
    local belf = by['70-70 c-"Rogue" r-"Blood Elf"']
    CHECK(belf and Near(belf.expect, 5 * E.ONLINE_SHARE), "E a class/race pair the same", belf and belf.expect)
    local rogues = by['70-70 c-"Rogue"']
    CHECK(rogues and Near(rogues.expect, 6 * E.ONLINE_SHARE), "E a whole class expected under 50 is offered, all its pairs in one")
    CHECK(by['70-70 g-"Ghosts"'] == nil, "E a guild of the long gone is not worth a press")
    CHECK(list[1].kind == "arena" and list[1].text == '70-70 z-"Arena"' and list[1].expect == E.ARENAS[1].prior,
        "E first: the arena zones, at their prior", list[1].text)
    CHECK(by['70-70 z-"Ruins of Lordaeron"'] ~= nil, "E the Ruins of Lordaeron too")

    -- Never a class that caps: one that gave more than 50 lately, or whose pairs did between them
    local l2 = E.NewLearned()
    l2.totals['70-70 c-"Rogue"'] = { total = 120, at = NOW - 60 }
    CHECK(ByText(E.SteerCandidates(Steer(l2), {}, NOW))['70-70 c-"Rogue"'] == nil,
        "E a class that gave more than 50 lately is never asked")
    local l3 = E.NewLearned()
    l3.totals['70-70 c-"Rogue" r-"Blood Elf"'] = { total = 40, at = NOW - 60 }
    l3.totals['70-70 c-"Rogue" r-"Undead"'] = { total = 20, at = NOW - 60 }
    local by3 = ByText(E.SteerCandidates(Steer(l3), {}, NOW))
    CHECK(by3['70-70 c-"Rogue"'] == nil, "E nor one whose pairs matched more than 50 between them")
    CHECK(by3['70-70 c-"Rogue" r-"Blood Elf"'] and Near(by3['70-70 c-"Rogue" r-"Blood Elf"'].expect, 5 * E.ONLINE_SHARE),
        "E ...its pairs are asked instead, each under 50")
    local l4 = E.NewLearned()
    l4.totals['70-70 c-"Rogue"'] = { total = 120, at = NOW - E.TOTAL_KEEP - 1 }
    CHECK(ByText(E.SteerCandidates(Steer(l4), {}, NOW))['70-70 c-"Rogue"'] ~= nil, "E a total half an hour old is not trusted")
    local l5 = E.NewLearned()
    l5.perRated.class = 40
    CHECK(ByText(E.SteerCandidates(Steer(l5), {}, NOW))['70-70 c-"Rogue"'] == nil,
        "E nor a class /who has lately listed many others for each rated player")

    -- Seen players stop counting; a query whose rated players are all on the board goes
    local seen = { ["Lo1-Dreamscythe"] = true, ["Lo2-Dreamscythe"] = true, ["Lo3-Dreamscythe"] = true,
        ["Lo4-Dreamscythe"] = true, ["Ga1-Dreamscythe"] = true }
    local after = ByText(E.SteerCandidates(sweep, seen, NOW))
    CHECK(after['70-70 c-"Rogue" r-"Blood Elf"'] == nil, "E a pair whose rated players are all on the board is not asked")
    CHECK(after['70-70 g-"Tiny"'] == nil, "E nor a guild")

    -- A press: the arena first; its timer starts when sent
    local q = E.SweepNext(sweep, {}, NOW)
    EQ(q.text, '70-70 z-"Arena"', "E the next query is the best one")
    local done, total = E.SweepProgress(sweep)
    CHECK(done == 0 and total == #list, "E the count is what is worth asking", done .. "/" .. total)
    E.SweepSent(sweep, q, NOW, {})
    -- In the arena: one rated player of ours, one unrated, one from the other realm
    E.SweepResult(sweep, 3, 3, nil, { ["Ga5-Dreamscythe"] = true, ["Nobody-Dreamscythe"] = true, ["X-Nightslayer"] = true })
    EQ(sweep.found, 1, "E finds are rated players of ours not on the board when asked")
    EQ(learned.arenas.arena.est, (E.ARENAS[1].prior + 1) / 2, "E the arena's estimate moves halfway to what it found")
    CHECK(Near(sweep.byKey["Ga1-Dreamscythe"].odds, E.ONLINE_SHARE), "E not being in an arena says nothing about being on")
    CHECK(ByText(E.SteerCandidates(sweep, {}, NOW + 60))['70-70 z-"Arena"'] == nil, "E the arena is not asked again a minute later")
    local again = ByText(E.SteerCandidates(sweep, {}, NOW + E.ARENA_REPEAT))['70-70 z-"Arena"']
    CHECK(again and again.expect == (E.ARENAS[1].prior + 1) / 2, "E ...but is after a few minutes, at its new estimate")

    -- The guild, answered under the cap: three of its six there, the rest offline
    local onBoard = { ["Ga5-Dreamscythe"] = true }
    q = { kind = "guild", guild = "Gank Squad", text = '70-70 g-"Gank Squad"', expect = 1 }
    E.SweepSent(sweep, q, NOW + 5, onBoard)
    local gone = E.SweepResult(sweep, 9, 9, nil, { ["Ga1-Dreamscythe"] = true, ["Ga2-Dreamscythe"] = true,
        ["Ga5-Dreamscythe"] = true })
    EQ(sweep.found, 3, "E two new finds (the one already seen is not counted twice)")
    CHECK(sweep.byKey["Ga3-Dreamscythe"].odds == 0 and sweep.byKey["Ga4-Dreamscythe"].odds == 0
        and sweep.byKey["Ga6-Dreamscythe"].odds == 0 and sweep.byKey["Ga1-Dreamscythe"].odds > 0,
        "E the guildmates it did not list are offline for this sweep")
    CHECK(gone and #gone == 0, "E a guild answer drops nobody from the board (a guild can be left)")
    local seen2 = { ["Ga1-Dreamscythe"] = true, ["Ga2-Dreamscythe"] = true, ["Ga5-Dreamscythe"] = true }
    local rest = ByText(E.SteerCandidates(sweep, seen2, NOW + 10))
    CHECK(rest['70-70 g-"Gank Squad"'] == nil, "E a guild is asked once a sweep")
    CHECK(rest['70-70 c-"Priest" r-"Undead"'] == nil and rest['70-70 c-"Priest"'] == nil,
        "E a pair or class whose only rated players were proved offline is not asked")

    -- The rogues as a class, under the cap: the unlisted rogue is offline and returned, and the pairs are settled
    q = { kind = "class", class = "ROGUE", text = '70-70 c-"Rogue"', expect = 1 }
    E.SweepSent(sweep, q, NOW + 10, seen2)
    gone = E.SweepResult(sweep, 4, 4, nil, { ["Ga1-Dreamscythe"] = true, ["Lo1-Dreamscythe"] = true,
        ["Lo2-Dreamscythe"] = true, ["Lo4-Dreamscythe"] = true })
    local goneSet = {}
    for _, key in ipairs(gone or {}) do goneSet[key] = true end
    CHECK(gone and #gone == 2 and goneSet["Lo3-Dreamscythe"] and goneSet["Ga4-Dreamscythe"],
        "E a class answer proves every rated player of it it did not list offline, for the board", gone and #gone)
    CHECK(sweep.asked['70-70 c-"Rogue" r-"Blood Elf"'] and sweep.asked['70-70 c-"Rogue" r-"Undead"'],
        "E ...and its pairs need no asking")
    q = E.SweepNext(sweep, seen2, NOW + 10)
    E.SweepSent(sweep, q, NOW + 10, seen2)
    E.SweepResult(sweep, 0, 0, true)
    CHECK(#sweep.unanswered == 1 and sweep.unanswered[1] == q.text, "E a query with no answer is recorded and the plan moves on")

    -- Capped: partial, nobody proved offline, the rest less likely on; next sweep counts its share of 50
    local s2 = Steer(E.NewLearned(), 1600)
    local qq = { kind = "pair", pair = "ROGUE:BloodElf", class = "ROGUE", race = "BloodElf",
        text = '70-70 c-"Rogue" r-"Blood Elf"', expect = 1 }
    E.SweepSent(s2, qq, NOW, {})
    gone = E.SweepResult(s2, 50, 60, nil, { ["Lo1-Dreamscythe"] = true })
    CHECK(gone == nil and next(s2.offline) == nil and s2.partial[#s2.partial] == qq.text,
        "E a capped answer is partial and proves nobody offline")
    local f, o = 50 / 60, E.ONLINE_SHARE
    CHECK(Near(s2.byKey["Lo2-Dreamscythe"].odds, o * (1 - f) / (1 - o * f)),
        "E ...but those it might have listed and did not are less likely on (Bayes)", s2.byKey["Lo2-Dreamscythe"].odds)
    local l3only = E.NewLearned()
    l3only.totals = s2.learned.totals -- only what /who said of the totals, not who it found (R23)
    local c3 = ByText(E.SteerCandidates(Steer(l3only), {}, NOW))[qq.text]
    CHECK(c3 and Near(c3.expect, 5 * E.ONLINE_SHARE * 50 / 60), "E a pair that capped counts for its share of 50 next time",
        c3 and c3.expect)
    local s6 = Steer(E.NewLearned())
    local cls = { kind = "class", class = "ROGUE", text = '70-70 c-"Rogue"', expect = 1 }
    E.SweepSent(s6, cls, NOW, {})
    E.SweepResult(s6, 50, 90, nil, {})
    CHECK(#s6.partial == 0 and not s6.asked['70-70 c-"Rogue" r-"Blood Elf"'],
        "E a class that capped is not partial: its pairs are still to come")
    CHECK(s6.learned.perRated.class > E.PER_RATED.class, "E ...and /who listing many per rated player is learned",
        s6.learned.perRated.class)

    -- Done: nothing left is the end, for good, even when an arena comes due again
    local solo = E.NewSteeredSweep({ P("Solo", "MAGE", "Troll", nil, 0) }, { faction = "Horde", names = names, now = NOW,
        learned = E.NewLearned() })
    local soloAsks = {}
    for _, c in ipairs(E.SteerCandidates(solo, {}, NOW)) do soloAsks[#soloAsks + 1] = c.kind end
    CHECK(#soloAsks == 2 and soloAsks[1] == "arena", "E one rated player alone is not worth a press of their own",
        table.concat(soloAsks, ","))
    local s4 = E.NewSteeredSweep({ P("M1", "MAGE", "Troll", nil, 0), P("M2", "MAGE", "Scourge", nil, 0),
        P("M3", "MAGE", "BloodElf", nil, 0), P("M4", "MAGE", "Troll", nil, 0), P("M5", "MAGE", "Scourge", nil, 0) },
        { faction = "Horde", names = names, now = NOW, learned = E.NewLearned() })
    local asked = {}
    while true do
        local n = E.SweepNext(s4, {}, NOW)
        if not n then break end
        asked[#asked + 1] = n.text
        E.SweepSent(s4, n, NOW, {})
        E.SweepResult(s4, 0, 0, false, {})
    end
    EQ(#asked, 3, "E five mages: the two arena zones, then the class (no pair alone is worth a press; one answer under 50 settles them)")
    CHECK(E.SweepFinished(s4), "E then the sweep is done")
    CHECK(E.SweepNext(s4, {}, NOW + 3600) == nil, "E ...and stays done though the arena is due again")
    local d, t = E.SweepProgress(s4)
    CHECK(d == 3 and t == 3, "E the count ends full", d .. "/" .. t)
    -- An arena that keeps finding nobody fades, then is tried now and then, last
    local l7 = E.NewLearned()
    l7.arenas.arena = { est = 0.1, at = NOW }
    local s7 = Steer(l7)
    local arena7
    for _, c in ipairs(E.SteerCandidates(s7, {}, NOW + E.ARENA_REPEAT)) do if c.arena == "arena" then arena7 = c end end
    CHECK(arena7 == nil, "E an arena zone that stopped finding anyone is not asked every few minutes")
    for _, c in ipairs(E.SteerCandidates(s7, {}, NOW + E.ARENA_RETRY)) do if c.arena == "arena" then arena7 = c end end
    CHECK(arena7 and arena7.expect == E.MIN_EXPECT, "E ...but is tried again after a while, as the last thing worth asking")
    EQ(E.GuildQuery("Gank Squad"), '70-70 g-"Gank Squad"', "E a guild query quotes the whole name")
    EQ(E.ZoneQuery("Arena", 60), '60-60 z-"Arena"', "E a zone query")
    -- The fixed plan's queries name themselves for the bar
    local fixed = E.NewSweep("Horde", names)
    EQ(fixed.queue[1].label, "Warrior", "E the fixed plan's query has a label")
    E.SweepResult(fixed, 50, 90)
    EQ(E.SweepNext(fixed).label, "Orc Warrior", "E ...and a race split says the race")
    E.MIN_EXPECT = stopWas
    E.NAME_FRAGMENTS = fragmentsWere
end

-- === G: race and talent-tree icons (R22) ===================================
do
    EQ(E.RaceAtlas("Scourge", "F"), "raceicon-undead-female", "G Scourge is the undead atlas")
    EQ(E.RaceAtlas("NightElf", "M"), "raceicon-nightelf-male", "G a two-word race, run together")
    EQ(E.RaceAtlas("BloodElf"), "raceicon-bloodelf-male", "G sex unknown: the male icon")
    EQ(E.RaceAtlas("Worgen", "M"), nil, "G not a TBC race: nothing")
    EQ(E.RaceAtlas(nil, "F"), nil, "G no race: nothing")
    EQ(E.Sex(2), "M", "G UnitSex 2 is male")
    EQ(E.Sex(3), "F", "G 3 female")
    EQ(E.Sex(1), nil, "G 1 unknown")
    local name, icon = E.Spec("DRUID", "FERALCOMBAT")
    CHECK(name == "Feral Combat" and icon == "Interface\\Icons\\Ability_Racial_BearForm", "G the feed's tree token names a tree and its icon", icon)
    EQ(E.Spec("ROGUE", "FERALCOMBAT"), nil, "G a tree of another class is nothing")
    EQ(E.Spec(nil, "ARMS"), nil, "G no class: nothing")
    local trees = 0
    for _, classTrees in pairs(E.SPECS) do for _ in pairs(classTrees) do trees = trees + 1 end end
    EQ(trees, 27, "G nine classes, three trees each")
    local book = E.NewBook()
    E.Note(book, { fullName = "Sly", race = "Gnome", sex = "F" }, 100, "chat", "Dreamscythe")
    E.Note(book, { fullName = "Sly", race = "", sex = nil }, 200, "who", "Dreamscythe")
    local p = book.players["Sly-Dreamscythe"]
    CHECK(p.race == "Gnome" and p.sex == "F", "G a sighting keeps race and sex; a later one without them forgets neither")
    E.Note(book, { fullName = "Sly", sex = "X" }, 300, "who", "Dreamscythe")
    EQ(p.sex, "F", "G only M or F is a sex")
end

-- === I: under 70 is never asked about (R24) ===============================
do
    local asked = {}
    local function For(p) asked[#asked + 1] = p.key; return { [2] = { rating = 1500, wins = 1, played = 2 } } end
    local players = {
        { key = "Low-R", level = 42, at = 1 }, { key = "Cap-R", level = 70, at = 1 }, { key = "Unknown-R", at = 1 },
    }
    local board = E.Board(players, For, { ratedLevel = E.LEVEL })
    CHECK(#asked == 2 and asked[1] ~= "Low-R" and asked[2] ~= "Low-R",
        "I a player known to be under 70 is never asked about (arena is a level 70 queue)", table.concat(asked, ","))
    CHECK(board.online == 3 and board.low == 1 and #board[2] == 2 and board.unrated == 0,
        "I ...still counted online, not as unrated; level 70 and unknown are asked")
    asked = {}
    E.Board(players, For, {})
    EQ(#asked, 3, "I without ratedLevel everyone is asked, as before")
end

-- === J: name fragments and sweep depth (R26) =================================
do
    local NOW = 1792300000
    EQ(table.concat(E.Fragments("Pallypwr"), ","), "pal,all,lly,lyp,ypw,pwr", "J a name's three-letter pieces, lower case, once each")
    EQ(table.concat(E.Fragments("Abbé"), ","), "abb", "J only plain letters make a piece")
    EQ(#E.Fragments("Ox"), 0, "J too short: none")
    EQ(E.NameQuery("ell"), '70-70 n-"ell"', "J the query")
    -- Twelve rated players with "ell" in their names, spread over classes, no guilds
    local roster, classes = {}, { "MAGE", "PRIEST", "ROGUE", "WARLOCK" }
    local names = { "Bellar", "Kellin", "Shelly", "Wellsy", "Dellan", "Ellwyn", "Nellie", "Tellus", "Mellow", "Jellybean", "Zellgar", "Ellana" }
    for i, n in ipairs(names) do
        roster[i] = { key = n .. "-Dreamscythe", faction = "H", class = classes[(i % 4) + 1], race = "Scourge",
            last = NOW - 3600, best = 1800 }
    end
    local learned = E.NewLearned()
    learned.arenas.arena, learned.arenas.ruins = { est = 0, at = NOW }, { est = 0, at = NOW }
    local function New(opts)
        opts = opts or {}
        opts.faction, opts.names, opts.now, opts.learned = "Horde", {}, NOW, opts.learned or learned
        return E.NewSteeredSweep(roster, opts)
    end
    local sweep = New()
    CHECK(sweep.fragments.ell and #sweep.fragments.ell == 12, "J a piece twelve of them share is a query", sweep.fragments.ell and #sweep.fragments.ell)
    local nameQ
    for _, c in ipairs(E.SteerCandidates(sweep, {}, NOW)) do if c.kind == "name" and c.frag == "ell" then nameQ = c end end
    CHECK(nameQ and nameQ.text == '70-70 n-"ell"' and nameQ.label == 'names with "ell"' and math.abs(nameQ.expect - 3) < 1e-9,
        "J offered: twelve at 0.25 worth three finds", nameQ and nameQ.expect)
    -- An answer whose names all START with "ell": n- may match the start only, so the others are not taken for offline
    E.SweepSent(sweep, nameQ, NOW, {})
    E.SweepResult(sweep, 2, 2, nil, { ["Ellwyn-Dreamscythe"] = true, ["Ellana-Dreamscythe"] = true })
    CHECK(learned.nameMatch == nil, "J no name with it inside: not yet known to match anywhere")
    CHECK(sweep.byKey["Bellar-Dreamscythe"].odds > 0, "J so Bellar (ell inside) is not proved offline")
    -- A second sweep's answer with "ell" inside a name settles it
    local s2 = New()
    local q2 = { kind = "name", frag = "ell", text = '70-70 n-"ell"', expect = 3, matches = 20 }
    E.SweepSent(s2, q2, NOW, {})
    E.SweepResult(s2, 2, 2, nil, { ["Bellar-Dreamscythe"] = true, ["Shelly-Dreamscythe"] = true })
    EQ(learned.nameMatch, "anywhere", "J a listed name with it inside: n- matches anywhere")
    CHECK(s2.byKey["Kellin-Dreamscythe"].odds == 0, "J then every unlisted one is offline")
    -- Start only: two answers listing a few names, none with it inside -> name fragments off for the session
    local l3 = E.NewLearned()
    l3.arenas.arena, l3.arenas.ruins = { est = 0, at = NOW }, { est = 0, at = NOW }
    for _ = 1, 2 do
        local s3 = New({ learned = l3 })
        local q3 = { kind = "name", frag = "ell", text = '70-70 n-"ell"', expect = 3, matches = 20 }
        E.SweepSent(s3, q3, NOW, {})
        E.SweepResult(s3, 3, 3, nil, { ["Ellwyn-Dreamscythe"] = true, ["Ellana-Dreamscythe"] = true, ["Ellbow-Dreamscythe"] = true })
    end
    CHECK(l3.namesOff, "J two answers with names but none with it inside: n- matches the start only, fragments off")
    local anyName = false
    for _, c in ipairs(E.SteerCandidates(New({ learned = l3 }), {}, NOW)) do if c.kind == "name" then anyName = true end end
    CHECK(not anyName, "J ...and no name query is offered again")
    -- Depth: the stop is the sweep's own
    local function Count(minExpect)
        local l = E.NewLearned()
        l.arenas.arena, l.arenas.ruins = { est = 0, at = NOW }, { est = 0, at = NOW }
        return #E.SteerCandidates(New({ learned = l, minExpect = minExpect }), {}, NOW)
    end
    CHECK(Count(0.5) > Count(2), "J a deeper sweep has more worth a press", Count(0.5) .. " vs " .. Count(2))
    local live = New({ minExpect = 2 })
    E.SteerOptions(live, { minExpect = 0.5 })
    EQ(live.minExpect, 0.5, "J the depth applies to a sweep under way")
end

-- === H: fewer queries (R23): the stop at 2, memory across sweeps, the forecast ===
do
    local NOW = 1792300000
    EQ(E.MIN_EXPECT, 2.0, "H a query must be worth two rated players to be asked")
    -- What an answer taught fades back to the login's odds
    EQ(E.Relax(0.25, nil, NOW), 0.25, "H nothing learned: the login's odds")
    EQ(E.Relax(0.25, { odds = 0, at = NOW }, NOW), 0, "H proved offline just now: no odds")
    CHECK(math.abs(E.Relax(0.25, { odds = 0, at = NOW }, NOW + E.RELAX) - 0.25 * (1 - math.exp(-1))) < 1e-9,
        "H ...most of the way back after the relax time")
    CHECK(math.abs(E.Relax(0.25, { odds = 1, at = NOW }, NOW + 6 * E.RELAX) - 0.25) < 0.01, "H found long ago: back to the login's")

    local names = { MAGE = "Mage", Troll = "Troll", Scourge = "Undead", BloodElf = "Blood Elf" }
    local roster = {}
    for i = 1, 12 do
        roster[i] = { key = "M" .. i .. "-Dreamscythe", faction = "H", class = "MAGE",
            race = i <= 8 and "Troll" or "Scourge", last = NOW - 3600, best = 1900 }
    end
    local learned = E.NewLearned()
    learned.arenas.arena = { est = 0, at = NOW }   -- the arenas out of the way
    learned.arenas.ruins = { est = 0, at = NOW }
    local function New(at) return E.NewSteeredSweep(roster, { faction = "Horde", names = names, now = at, learned = learned }) end
    local s1 = New(NOW)
    local q = E.SweepNext(s1, {}, NOW)
    EQ(q and q.text, '70-70 c-"Mage"', "H the mages, asked whole (12 x 0.25 = 3 worth)")
    -- The forecast plays the sweep forward without touching it
    local before = s1.byKey["M1-Dreamscythe"].odds
    local presses, finds = E.SteerForecast(s1, {}, NOW)
    CHECK(presses == 1 and math.abs(finds - 3) < 1e-9, "H forecast: one press for ~3 (one answer under 50 settles the pairs)",
        presses .. "/" .. finds)
    CHECK(s1.byKey["M1-Dreamscythe"].odds == before and not s1.asked['70-70 c-"Mage"'] and s1.forecastArenas == nil,
        "H ...and leaves the sweep as it was")
    CHECK(s1.forecast and s1.forecast.presses == 1, "H ...kept for the bar")
    local d, t = E.SweepProgress(s1)
    CHECK(d == 0 and t == 1, "H the bar's count is the forecast, not the queries worth a press now", d .. "/" .. t)
    E.SweepSent(s1, q, NOW, {})
    CHECK(s1.forecast == nil, "H a send makes the forecast old")
    -- Three mages on, the other nine offline: remembered
    E.SweepResult(s1, 3, 3, nil, { ["M1-Dreamscythe"] = true, ["M2-Dreamscythe"] = true, ["M9-Dreamscythe"] = true })
    EQ(learned.players["M1-Dreamscythe"].odds, 1, "H a find is remembered as on")
    EQ(learned.players["M3-Dreamscythe"].odds, 0, "H a player proved offline is remembered as off")
    EQ(learned.askedAt['70-70 c-"Mage"'], NOW, "H and when the query went out")
    -- A new sweep a minute later: nothing worth a press, the board or not
    local s2 = New(NOW + 60)
    CHECK(E.SweepNext(s2, {}, NOW + 60) == nil, "H a sweep right after asks nothing: the class was just asked, its players just proved off")
    -- Ten minutes on the class may be asked again, but nine players proved off are still mostly off
    local s3 = New(NOW + E.REASK + 1)
    local seen = { ["M1-Dreamscythe"] = true, ["M2-Dreamscythe"] = true, ["M9-Dreamscythe"] = true }
    CHECK(E.SweepNext(s3, seen, NOW + E.REASK + 1) == nil, "H ten minutes later, nine proved off are not yet worth two finds")
    -- An hour on, they are anyone again
    local s4 = New(NOW + 3600)
    local q4 = E.SweepNext(s4, seen, NOW + 3600)
    EQ(q4 and q4.text, '70-70 c-"Mage"', "H an hour later the class is worth asking again")
    -- The stop: one Troll pair of three active is under two, not asked
    local small = {}
    for i = 1, 3 do small[i] = { key = "S" .. i .. "-Dreamscythe", faction = "H", class = "MAGE", race = "Troll", last = NOW, best = 1900 } end
    local l5 = E.NewLearned()
    l5.arenas.arena, l5.arenas.ruins = { est = 0, at = NOW }, { est = 0, at = NOW }
    local s5 = E.NewSteeredSweep(small, { faction = "Horde", names = names, now = NOW, learned = l5 })
    CHECK(E.SweepNext(s5, {}, NOW) == nil and E.SweepFinished(s5), "H three active players (0.75 worth) are not worth a press")
    local p5, f5 = E.SteerForecast(s5, {}, NOW)
    CHECK(p5 == 0 and f5 == 0, "H a finished sweep forecasts nothing")
end

-- === F: a simulated peak hour ==============================================
-- Not the game: a model of one, to show the steering works end to end and is
-- worth it. 800 rated Horde on the realm (logins spread over a month, guilds
-- skewed big to small), about a fifth on, some in arena; 600 unrated level
-- 70s on, spread over the pairs and partly into the same guilds. /who is
-- answered from it with the 50 cap, its 50 in a fixed order that is not
-- "rated first". Both sweeps run until they say done.
do
    local seed = 2
    local function rand(n) seed = (seed * 1103515245 + 12345) % 2147483648 return seed % n end
    local NOW = 1792300000
    local pairsList = {}
    for _, class in ipairs(E.CLASS_ORDER) do
        for _, race in ipairs(E.RACES.Horde) do
            if E.CLASS_RACES[class][race] then pairsList[#pairsList + 1] = { class, race } end
        end
    end
    local roster, online = {}, {}
    local guilds = {}
    for g = 1, 60 do guilds[g] = "Guild" .. g end
    for i = 1, 800 do
        local pr = pairsList[1 + math.min(rand(#pairsList), rand(#pairsList))]
        local daysAgo = ({ 0, 0, 0, 1, 2, 4, 6, 10, 20, 40 })[1 + rand(10)]
        local guild = rand(5) > 0 and guilds[1 + math.min(rand(60), rand(60))] or nil
        local p = { key = "R" .. i .. "-Dreamscythe", faction = "H", class = pr[1], race = pr[2], guild = guild,
            last = NOW - daysAgo * 86400 - rand(3600), best = 1600 + rand(800) }
        roster[i] = p
        local chance = daysAgo <= 1 and 35 or daysAgo <= 6 and 12 or 2
        if rand(100) < chance then
            online[#online + 1] = { key = p.key, class = p.class, race = p.race, guild = guild, rated = true,
                zone = rand(100) < 12 and "Nagrand Arena" or "Shattrath City" }
        end
    end
    for i = 1, 600 do
        local pr = pairsList[1 + math.min(rand(#pairsList), rand(#pairsList))]
        online[#online + 1] = { key = "U" .. i .. "-Dreamscythe", class = pr[1], race = pr[2],
            guild = rand(4) == 0 and guilds[1 + math.min(rand(60), rand(60))] or nil, zone = "Orgrimmar" }
    end
    for i = #online, 2, -1 do local j = 1 + rand(i); online[i], online[j] = online[j], online[i] end
    local ratedOnline = 0
    for _, o in ipairs(online) do if o.rated then ratedOnline = ratedOnline + 1 end end

    local function Answer(q)
        local hits = {}
        for _, o in ipairs(online) do
            local ok
            if q.kind == "arena" then ok = q.arena == "arena" and o.zone:find("Arena", 1, true) ~= nil
            elseif q.kind == "guild" then ok = o.guild == q.guild
            else ok = o.class == q.class and (not q.race or o.race == q.race) end
            if ok then hits[#hits + 1] = o end
        end
        local keys = {}
        for i = 1, math.min(#hits, E.WHO_CAP) do keys[hits[i].key] = true end
        return math.min(#hits, E.WHO_CAP), #hits, keys
    end

    -- Rated players found after each press
    local function Run(sweep)
        local seen, curve, t = {}, {}, NOW
        while #curve < 200 do
            local q = E.SweepNext(sweep, seen, t)
            if not q then break end
            E.SweepSent(sweep, q, t, seen)
            local shown, total, keys = Answer(q)
            E.SweepResult(sweep, shown, total, nil, keys)
            for key in pairs(keys) do seen[key] = true end
            local found = 0
            for _, o in ipairs(online) do if o.rated and seen[o.key] then found = found + 1 end end
            curve[#curve + 1], t = found, t + 5
        end
        return curve
    end
    local fixed = Run(E.NewSweep("Horde", {}))
    local steered = E.NewSteeredSweep(roster, { faction = "Horde", names = {}, now = NOW, learned = E.NewLearned() })
    local steer = Run(steered)
    local fixedAll, steerAll = fixed[#fixed], steer[#steer]
    local matched
    for i, n in ipairs(steer) do if n >= fixedAll then matched = i break end end
    CHECK(E.SweepFinished(steered), "F the steered sweep ends by itself")
    CHECK(steerAll > fixedAll, "F it finds more rated players online than the fixed plan", steerAll .. " vs " .. fixedAll)
    CHECK(#steer <= #fixed, "F in no more presses", #steer .. " vs " .. #fixed)
    CHECK(matched and matched <= #fixed * 0.7, "F and has the fixed plan's whole haul by 70% of its presses",
        tostring(matched) .. " of " .. #fixed)
    CHECK(steer[10] > fixed[10] * 1.3, "F ten presses in, a third more found", steer[10] .. " vs " .. fixed[10])
    io.write(string.format("F  model: %d rated on; fixed plan %d presses found %d (%d after 10); steered %d presses found %d (%d after 10, the fixed plan's %d by press %d)\n",
        ratedOnline, #fixed, fixedAll, fixed[10], #steer, steerAll, steer[10], fixedAll, matched or -1))
end

-- === O: the player's search order (R21) =====================================
do
    -- these fixtures are sized for the stop at 1 (R20); R23's stop is checked on its own
    local stopWas = E.MIN_EXPECT
    E.MIN_EXPECT = 1.0
    local fragmentsWere = E.NAME_FRAGMENTS
    E.NAME_FRAGMENTS = false -- class and guild logic only (R26 has its own section)
    EQ(table.concat(E.ClassOrder(nil), ","), table.concat(E.CLASS_ORDER, ","), "O no saved order: the default")
    local o = E.ClassOrder({ "ROGUE", "BOGUS", "PRIEST", "ROGUE" })
    EQ(o[1] .. "," .. o[2] .. "," .. o[3], "ROGUE,PRIEST,WARRIOR", "O a saved order first, unknowns and repeats dropped")
    EQ(#o, 9, "O ...and every class still in it")
    local moved = E.MoveClass(nil, 9, 1)
    EQ(moved[1] .. "," .. moved[2], "DRUID,WARRIOR", "O a class moved to the top")
    moved = E.MoveClass(nil, 1, 3)
    EQ(moved[1] .. "," .. moved[3], "PALADIN,WARRIOR", "O a class moved down")
    EQ(#E.MoveClass(nil, 12, 1), 9, "O a move from nowhere changes nothing")
    local ranks = E.ClassRanks({ "ROGUE", "PRIEST" }, { PRIEST = true })
    EQ(ranks.ROGUE, 1, "O ranks: the first searched is 1")
    EQ(ranks.PRIEST, nil, "O ranks: a class switched off has none")
    EQ(ranks.WARRIOR, 2, "O ranks: ...and the next takes its place")
    local fixed = E.NewSweep("Alliance", {}, nil, { order = { "PRIEST" }, off = { WARRIOR = true } })
    EQ(fixed.queue[1].class, "PRIEST", "O the fixed plan asks in the player's order")
    local hasWarrior = false
    for _, q in ipairs(fixed.queue) do if q.class == "WARRIOR" then hasWarrior = true end end
    CHECK(not hasWarrior and #fixed.queue == 8, "O ...and never a class switched off")

    -- A steered sweep: 12 paladins with no guild, 6 priests and 4 rogues in one
    local now = 2000000000
    local roster = {}
    local function Add(name, class, guild)
        roster[#roster + 1] = { key = name .. "-R", faction = "A", class = class, race = "Human",
            guild = guild, last = now - 3600, best = 2000 }
    end
    for i = 1, 12 do Add("Pal" .. i, "PALADIN") end
    for i = 1, 6 do Add("Pri" .. i, "PRIEST", "G") end
    for i = 1, 4 do Add("Rog" .. i, "ROGUE", "G") end
    local function Texts(sweep)
        local out = {}
        for _, q in ipairs(E.SteerCandidates(sweep, {}, now)) do out[#out + 1] = q.kind .. ":" .. (q.class or q.guild or q.arena) end
        return table.concat(out, " ")
    end
    local base = E.NewSteeredSweep(roster, { faction = "Alliance", names = {}, now = now })
    EQ(Texts(base), "arena:arena arena:ruins class:PALADIN pair:PALADIN guild:G class:PRIEST pair:PRIEST class:ROGUE pair:ROGUE",
        "O best first, as before, with nothing set")
    local noPal = E.NewSteeredSweep(roster, { faction = "Alliance", names = {}, now = now, off = { PALADIN = true } })
    -- (the Ruins, worth 5 x 10/22 now, falls behind the guild's 2.5)
    EQ(Texts(noPal), "arena:arena guild:G arena:ruins class:PRIEST pair:PRIEST class:ROGUE pair:ROGUE",
        "O a class switched off: none of its queries")
    local arena = E.SteerCandidates(noPal, {}, now)[1]
    CHECK(math.abs(arena.expect - 10 * 10 / 22) < 0.001, "O ...and an arena zone is worth only the share still searched",
        arena.expect)
    local noRogue = E.NewSteeredSweep(roster, { faction = "Alliance", names = {}, now = now, off = { ROGUE = true } })
    local guild
    for _, q in ipairs(E.SteerCandidates(noRogue, {}, now)) do if q.kind == "guild" then guild = q end end
    CHECK(guild and math.abs(guild.expect - 1.5) < 0.001, "O a guild is worth only its searched players", guild and guild.expect)
    local ordered = E.NewSteeredSweep(roster, { faction = "Alliance", names = {}, now = now,
        order = { "ROGUE", "PRIEST" }, inOrder = true })
    EQ(Texts(ordered), "arena:arena arena:ruins guild:G class:ROGUE pair:ROGUE class:PRIEST pair:PRIEST class:PALADIN pair:PALADIN",
        "O in order: the arenas, then everything for the first class (its guild first), then the next")
    local list = E.SteerCandidates(ordered, {}, now)
    EQ(E.QueryClass(ordered, list[3]), "ROGUE", "O the guild asked for rogues says so")
    EQ(E.QueryClass(ordered, list[1]), nil, "O an arena zone is for every class")
    EQ(E.QueryClass(base, list[3]), nil, "O best first, a guild is for everyone")
    E.SteerOptions(base, { order = { "PRIEST" }, inOrder = true })
    EQ(E.SteerCandidates(base, {}, now)[3].class, nil, "O options apply to a sweep under way (the guild, for its priests)")
    EQ(E.SteerCandidates(base, {}, now)[4].class, "PRIEST", "O ...then the priests' own queries")
    E.MIN_EXPECT = stopWas
    E.NAME_FRAGMENTS = fragmentsWere
end

-- === K: another realm (R27) ==================================================
do
    local book = E.NewBook()
    local home = "Dreamscythe"
    local function Elsewhere(name) return name == "Visitor" or name == "Settled" end
    local written = E.Note(book, { fullName = "Talker-Nightslayer" }, 100, "chat", home)
    CHECK(E.OtherRealm(written, home, Elsewhere), "K a name written with another realm is another realm's")
    local ours = E.Note(book, { fullName = "Mate-Dreamscythe" }, 100, "guild", home)
    CHECK(not E.OtherRealm(ours, home, Elsewhere), "K a name written with ours is ours")
    local visitor = E.Note(book, { fullName = "Visitor" }, 100, "lfg", home)
    CHECK(visitor.finderOnly == true, "K a bare group finder name is the finder's alone")
    CHECK(E.OtherRealm(visitor, home, Elsewhere), "K ...and another realm's when the feed has it only elsewhere")
    CHECK(not E.OtherRealm(visitor, home, nil), "K ...but nobody able to tell keeps them")
    local stranger = E.Note(book, { fullName = "Stranger" }, 100, "lfg", home)
    CHECK(not E.OtherRealm(stranger, home, Elsewhere), "K a finder name the feed cannot place stays")
    local settled = E.Note(book, { fullName = "Settled" }, 100, "lfg", home)
    E.Note(book, { fullName = "Settled" }, 110, "who", home)
    CHECK(settled.finderOnly == false and not E.OtherRealm(settled, home, Elsewhere),
        "K any other source giving the bare name settles it as ours, whatever the feed says")
    E.Note(book, { fullName = "Settled" }, 120, "lfg", home)
    CHECK(settled.finderOnly == false, "K ...and a later finder listing does not unsettle it")
    local bareWho = E.Note(book, { fullName = "Visitor2" }, 100, "who", home)
    CHECK(not E.OtherRealm(bareWho, home, function() return true end), "K a bare /who name is ours")
    CHECK(not E.OtherRealm(nil, home, Elsewhere), "K no player is no realm")

    local asked = {}
    local function For(p)
        asked[#asked + 1] = p.key
        return { [2] = { rating = 2000, wins = 1, played = 2 } }
    end
    local players = { written, ours, visitor, stranger }
    local function Skip(p) return E.OtherRealm(p, home, Elsewhere) end
    local board = E.Board(players, For, { skip = Skip })
    EQ(#board[2], 2, "K skipped players are off the board")
    EQ(board.away, 2, "K ...counted as away")
    EQ(board.online, 2, "K ...and not as online")
    EQ(#asked, 2, "K ...and never asked about, so the feed is handed no names")
    board = E.Board(players, For)
    CHECK(#board[2] == 4 and board.away == 0, "K without skip everyone stays")
end

io.write(string.format("%d checks, %d failed\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
