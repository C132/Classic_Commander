-- Commander Recruit — the engine.
--
-- Pure: no client API is touched here, so the harness runs it under plain
-- luajit. Three things live here:
--
-- 1. THE BOOK of who has been seen online, and when. The client feeds it
--    from everything that can only be true of someone logged in right now --
--    a /who result, a group finder listing, a line in a chat channel, the
--    guild roster's online flag, an online friend, a friendly player under
--    the cursor -- and the board shows only who was seen inside the
--    freshness window. A /who, a guild roster or a friends list that says
--    someone is NOT online takes them off at once (E.Gone).
--
-- 2. THE BOARD: everyone fresh, with a rating in a bracket, ranked within
--    that bracket highest first. Three lists, one per bracket, never merged:
--    a 2200 in 2v2 and a 1500 in 3v3 are two different answers to "who
--    could I play X with".
--
-- 3. THE SWEEP: the only way to ask the game who is online at all is /who,
--    which answers at most 50 names a query and which an addon may send only
--    from a click or a key press (SendWho has restrictions on this client).
--    So a sweep is a plan of queries walked one press at a time. With
--    Commander Ladder's roster of the realm's rated players it is STEERED
--    (R20): each press asks where the rated players not yet seen most likely
--    are -- the arena zones, their guilds, their class/race pairs. Without it,
--    the fixed plan: every class at level 70; a class that hits the 50 cap is
--    split by race; a race that still hits it is reported as partial rather
--    than pretended complete.

CommanderRecruit_Engine = CommanderRecruit_Engine or {}
local E = CommanderRecruit_Engine

E.BRACKETS = { 2, 3, 5 }
E.WHO_CAP = 50              -- the most names one /who answers with
E.LEVEL = 70                -- arena is a level-70 queue in TBC

-- Which source a sighting came from, best first: a /who or a roster is the
-- server saying "online"; a chat line or a listing is the player acting
E.SOURCES = { "who", "probe", "guild", "friend", "lfg", "chat", "seen" }
E.SOURCE_LABEL = {
    who = "/who", probe = "ladder probe", guild = "guild", friend = "friend", lfg = "group finder",
    chat = "chat", seen = "seen",
}

-- ---------------------------------------------------------------------------
-- Names
-- ---------------------------------------------------------------------------

-- "Name-Realm" with the realm's spaces dropped, our realm when there is none.
-- Returns key, name, realm, bare (true when no realm was given: the realm is
-- our guess, see Commander_Ladder L8).
function E.Key(fullName, homeRealm)
    if type(fullName) ~= "string" or fullName == "" then return nil end
    local name, realm = fullName:match("^([^%-]+)%-(.+)$")
    if name then
        realm = realm:gsub("%s", "")
        return name .. "-" .. realm, name, realm, false
    end
    if type(homeRealm) ~= "string" or homeRealm == "" then return fullName, fullName, nil, true end
    homeRealm = homeRealm:gsub("%s", "")
    return fullName .. "-" .. homeRealm, fullName, homeRealm, true
end

-- ---------------------------------------------------------------------------
-- The book
-- ---------------------------------------------------------------------------

function E.NewBook()
    return { players = {} }
end

-- A sighting. `s` carries any of: fullName (required), class (token), level,
-- guild, zone, race (token), sex ("M"/"F"). Later sightings refresh the time
-- and fill what earlier ones left blank; a fact never goes from known to
-- unknown.
function E.Note(book, s, now, source, homeRealm)
    if type(s) ~= "table" then return nil end
    local key, name, realm, bare = E.Key(s.fullName, homeRealm)
    if not key then return nil end
    local p = book.players[key]
    if not p then
        p = { key = key, name = name, realm = realm, bare = bare }
        book.players[key] = p
    elseif not bare then
        -- A written realm settles a guess made earlier
        p.bare = false
    end
    p.at = now
    p.source = source or p.source
    if s.class and s.class ~= "" then p.class = s.class end
    if s.race and s.race ~= "" then p.race = s.race end
    if s.sex == "M" or s.sex == "F" then p.sex = s.sex end
    local level = tonumber(s.level)
    if level and level > 0 then p.level = level end
    if s.guild ~= nil then p.guild = s.guild ~= "" and s.guild or nil end
    if s.zone and s.zone ~= "" then p.zone = s.zone end
    if s.guid then p.guid = s.guid end
    return p
end

-- Somebody a server answer says is not online (a friend gone offline, a
-- guildmate logged out): off the board now, not in fifteen minutes
function E.Gone(book, fullName, homeRealm)
    local key = E.Key(fullName, homeRealm)
    if key then book.players[key] = nil end
end

-- Everyone seen inside `window` seconds, and the book pruned of anyone seen
-- before `keep` seconds ago (nil keeps everything)
function E.Fresh(book, now, window, keep)
    local out = {}
    for key, p in pairs(book.players) do
        local age = now - (p.at or 0)
        if keep and age > keep then
            book.players[key] = nil
        elseif age <= window then
            out[#out + 1] = p
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- The board
-- ---------------------------------------------------------------------------

-- `ratingsFor(p)` answers Muster's shape: { [2|3|5] = { rating, wins,
-- played, at, source, best } } or nil. Returns
--   { [2] = { rows }, [3] = { rows }, [5] = { rows }, unrated = n, online = n }
-- where a row is { player, rating, wins, lost, best, ratedAt }, highest
-- rating first; ties go to the more recently seen, then the name.
-- opts.minRating hides anyone below it in that bracket; opts.classes, when
-- given, is a set of class tokens to keep.
function E.Board(players, ratingsFor, opts)
    opts = opts or {}
    local minRating = tonumber(opts.minRating) or 0
    local board = { unrated = 0, online = 0 }
    for _, size in ipairs(E.BRACKETS) do board[size] = {} end
    for _, p in ipairs(players) do
        if not (opts.classes and p.class and not opts.classes[p.class]) then
            board.online = board.online + 1
            local ratings = ratingsFor(p)
            local any = false
            for _, size in ipairs(E.BRACKETS) do
                local b = type(ratings) == "table" and ratings[size]
                local rating = b and tonumber(b.rating) or 0
                if rating > 0 then
                    any = true
                    if rating >= minRating then
                        local played = tonumber(b.played) or 0
                        local wins = tonumber(b.wins) or 0
                        local list = board[size]
                        list[#list + 1] = {
                            player = p, rating = rating, wins = wins,
                            lost = math.max(played - wins, 0),
                            best = tonumber(b.best) or rating, ratedAt = tonumber(b.at),
                        }
                    end
                end
            end
            if not any then board.unrated = board.unrated + 1 end
        end
    end
    for _, size in ipairs(E.BRACKETS) do
        table.sort(board[size], function(a, b)
            if a.rating ~= b.rating then return a.rating > b.rating end
            local at, bt = a.player.at or 0, b.player.at or 0
            if at ~= bt then return at > bt end
            return a.player.key < b.player.key
        end)
    end
    return board
end

-- ---------------------------------------------------------------------------
-- Race and talent-tree icons (R21)
-- ---------------------------------------------------------------------------

-- The client's race atlases (UiTextureAtlasMember, build 2.5.6.70006):
-- "raceicon-<race>-<male|female>"; Blizzard's GetRaceAtlas spells Scourge "undead"
local RACE_ATLAS = { Human = "human", Orc = "orc", Dwarf = "dwarf", NightElf = "nightelf", Scourge = "undead",
    Tauren = "tauren", Gnome = "gnome", Troll = "troll", BloodElf = "bloodelf", Draenei = "draenei" }

-- The atlas for a race token and sex ("M"/"F"; unknown draws the male one), or nil
function E.RaceAtlas(race, sex)
    local name = race and RACE_ATLAS[race]
    if not name then return nil end
    return string.format("raceicon-%s-%s", name, sex == "F" and "female" or "male")
end

-- "Unit sex" numbers (UnitSex, GetPlayerInfoByGUID): 2 male, 3 female
function E.Sex(n)
    n = tonumber(n)
    if n == 2 then return "M" elseif n == 3 then return "F" end
    return nil
end

-- The talent trees, keyed by class and by the feed's tree token (the en_US
-- name's letters in capitals, Ladder L10): the name to show and the
-- talent-tab icon -- the same icons as Commander PartyFrames' spec display
E.SPECS = {
    WARRIOR = { ARMS = { "Arms", "Ability_Warrior_SavageBlow" }, FURY = { "Fury", "Ability_Warrior_InnerRage" },
        PROTECTION = { "Protection", "Ability_Warrior_DefensiveStance" } },
    PALADIN = { HOLY = { "Holy", "Spell_Holy_HolyBolt" }, PROTECTION = { "Protection", "Spell_Holy_DevotionAura" },
        RETRIBUTION = { "Retribution", "Spell_Holy_AuraOfLight" } },
    HUNTER = { BEASTMASTERY = { "Beast Mastery", "Ability_Hunter_BeastTaming" },
        MARKSMANSHIP = { "Marksmanship", "Ability_Marksmanship" }, SURVIVAL = { "Survival", "Ability_Hunter_SwiftStrike" } },
    ROGUE = { ASSASSINATION = { "Assassination", "Ability_Rogue_Eviscerate" }, COMBAT = { "Combat", "Ability_BackStab" },
        SUBTLETY = { "Subtlety", "Ability_Stealth" } },
    PRIEST = { DISCIPLINE = { "Discipline", "Spell_Holy_WordFortitude" }, HOLY = { "Holy", "Spell_Holy_HolyBolt" },
        SHADOW = { "Shadow", "Spell_Shadow_ShadowWordPain" } },
    SHAMAN = { ELEMENTAL = { "Elemental", "Spell_Nature_Lightning" },
        ENHANCEMENT = { "Enhancement", "Spell_Nature_LightningShield" },
        RESTORATION = { "Restoration", "Spell_Nature_MagicImmunity" } },
    MAGE = { ARCANE = { "Arcane", "Spell_Holy_MagicalSentry" }, FIRE = { "Fire", "Spell_Fire_FireBolt02" },
        FROST = { "Frost", "Spell_Frost_FrostBolt02" } },
    WARLOCK = { AFFLICTION = { "Affliction", "Spell_Shadow_DeathCoil" },
        DEMONOLOGY = { "Demonology", "Spell_Shadow_Metamorphosis" },
        DESTRUCTION = { "Destruction", "Spell_Shadow_RainOfFire" } },
    DRUID = { BALANCE = { "Balance", "Spell_Nature_StarFall" }, FERALCOMBAT = { "Feral Combat", "Ability_Racial_BearForm" },
        RESTORATION = { "Restoration", "Spell_Nature_HealingTouch" } },
}

-- A tree's name and icon path for a class, or nil
function E.Spec(class, spec)
    local t = class and spec and E.SPECS[class] and E.SPECS[class][spec]
    if not t then return nil end
    return t[1], "Interface\\Icons\\" .. t[2]
end

-- ---------------------------------------------------------------------------
-- The sweep
-- ---------------------------------------------------------------------------

-- Which races can be which class in TBC, per faction. A /who split by race
-- only asks the combinations that exist.
E.RACES = {
    Alliance = { "Human", "Dwarf", "NightElf", "Gnome", "Draenei" },
    Horde = { "Orc", "Scourge", "Tauren", "Troll", "BloodElf" },
}
E.CLASS_RACES = {
    WARRIOR = { Human = true, Dwarf = true, NightElf = true, Gnome = true, Draenei = true,
                Orc = true, Scourge = true, Tauren = true, Troll = true },
    PALADIN = { Human = true, Dwarf = true, Draenei = true, BloodElf = true },
    HUNTER  = { Dwarf = true, NightElf = true, Draenei = true,
                Orc = true, Tauren = true, Troll = true, BloodElf = true },
    ROGUE   = { Human = true, Dwarf = true, NightElf = true, Gnome = true,
                Orc = true, Scourge = true, Troll = true, BloodElf = true },
    PRIEST  = { Human = true, Dwarf = true, NightElf = true, Draenei = true,
                Scourge = true, Troll = true, BloodElf = true },
    SHAMAN  = { Draenei = true, Orc = true, Tauren = true, Troll = true },
    MAGE    = { Human = true, Gnome = true, Draenei = true, Scourge = true, Troll = true, BloodElf = true },
    WARLOCK = { Human = true, Gnome = true, Orc = true, Scourge = true, BloodElf = true },
    DRUID   = { NightElf = true, Tauren = true },
}
E.CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

-- The player's search order (R21): a saved list of class tokens made whole --
-- unknown tokens and repeats dropped, any class it lacks added at the end in
-- the default order -- so an old or hand-edited list never loses a class
function E.ClassOrder(saved)
    local out, have = {}, {}
    for _, class in ipairs(type(saved) == "table" and saved or {}) do
        if E.CLASS_RACES[class] and not have[class] then
            have[class] = true
            out[#out + 1] = class
        end
    end
    for _, class in ipairs(E.CLASS_ORDER) do
        if not have[class] then out[#out + 1] = class end
    end
    return out
end

-- Each searched class's place in the order, 1 first; a switched-off class
-- (`off[class]` true) has none
function E.ClassRanks(order, off)
    local ranks, n = {}, 0
    for _, class in ipairs(E.ClassOrder(order)) do
        if not (off and off[class]) then
            n = n + 1
            ranks[class] = n
        end
    end
    return ranks
end

-- `order` moved: the class at `from` dropped into place `to` (both 1-based
-- in the whole order). A new list; the old one is left alone.
function E.MoveClass(order, from, to)
    local out = E.ClassOrder(order)
    from, to = tonumber(from), tonumber(to)
    if not (from and to and out[from]) then return out end
    to = math.max(1, math.min(#out, to))
    local class = table.remove(out, from)
    table.insert(out, to, class)
    return out
end

-- The text of one query. `names` maps class and race tokens to the names
-- /who understands (localized on the client); quoted, so "Night Elf" holds.
function E.Query(classToken, raceToken, names, level)
    level = level or E.LEVEL
    local text = string.format('%d-%d c-"%s"', level, level, names[classToken] or classToken)
    if raceToken then
        text = text .. string.format(' r-"%s"', names[raceToken] or raceToken)
    end
    return text
end

-- What the bar calls a query: "Warrior", "Night Elf Druid"
function E.PairLabel(classToken, raceToken, names)
    local class = names[classToken] or classToken
    if not raceToken then return class end
    return (names[raceToken] or raceToken) .. " " .. class
end

-- A fresh plan for `faction`: one query per class that faction can be, in
-- the player's order (R21) and without the classes switched off.
-- opts: order (class tokens), off ({ [class] = true })
function E.NewSweep(faction, names, level, opts)
    opts = opts or {}
    local races = E.RACES[faction] or {}
    local sweep = { queue = {}, done = 0, partial = {}, unanswered = {}, faction = faction,
        names = names or {}, level = level }
    local off = opts.off or {}
    for _, class in ipairs(E.ClassOrder(opts.order)) do
        local possible = false
        for _, race in ipairs(races) do
            if E.CLASS_RACES[class][race] then possible = true break end
        end
        if possible and not off[class] then
            sweep.queue[#sweep.queue + 1] = { kind = "class", class = class,
                text = E.Query(class, nil, sweep.names, level), label = E.PairLabel(class, nil, sweep.names) }
        end
    end
    sweep.total = #sweep.queue
    return sweep
end

-- The next query, without taking it. The fixed plan's is the front of its
-- queue; a steered sweep's is chosen now (`seen`: the keys on the board,
-- `now`: epoch seconds), and none left finishes it for good.
function E.SweepNext(sweep, seen, now)
    if not sweep then return nil end
    if sweep.mode == "steered" then return E.SteerNext(sweep, seen, now) end
    return sweep.queue[1]
end

function E.SweepFinished(sweep)
    if not sweep then return true end
    if sweep.mode == "steered" then return sweep.finished == true end
    return #sweep.queue == 0
end

-- The query just sent. The fixed plan needs nothing (its answer pops the
-- front); a steered sweep remembers what it asked and who was on the board
-- then, so the answer can count new finds.
function E.SweepSent(sweep, q, now, seen)
    if sweep and q and sweep.mode == "steered" then E.SteerSent(sweep, q, now, seen) end
end

-- The answer to the query at the front: how many names it gave and how many
-- matched in all. At the cap, a class query is split by race and the race
-- queries go to the front, so the sweep finishes one class before the next;
-- a race query at the cap is recorded as partial. `unanswered`: no answer
-- came at all (a /who with no matches may send none) -- the plan moves on
-- rather than asking the same thing for ever, and the query is recorded.
-- `answer` (steered only): the keys /who listed. A steered answer returns
-- the keys it proved offline (see E.SteerResult).
function E.SweepResult(sweep, shown, total, unanswered, answer)
    if not sweep then return nil end
    if sweep.mode == "steered" then return E.SteerResult(sweep, shown, total, unanswered, answer) end
    local q = table.remove(sweep.queue, 1)
    if not q then return end
    sweep.done = sweep.done + 1
    if unanswered then
        sweep.unanswered[#sweep.unanswered + 1] = q.text
        return
    end
    local capped = (tonumber(total) or 0) > (tonumber(shown) or 0) or (tonumber(shown) or 0) >= E.WHO_CAP
    if not capped then return end
    if q.race then
        sweep.partial[#sweep.partial + 1] = q.text
        return
    end
    local split = {}
    for _, race in ipairs(E.RACES[sweep.faction] or {}) do
        if E.CLASS_RACES[q.class][race] then
            split[#split + 1] = { kind = "class", class = q.class, race = race,
                text = E.Query(q.class, race, sweep.names, sweep.level),
                label = E.PairLabel(q.class, race, sweep.names) }
        end
    end
    for i = #split, 1, -1 do table.insert(sweep.queue, 1, split[i]) end
    sweep.total = sweep.total + #split
end

-- "4 of 12" for the bar, counting the splits added so far. A steered
-- sweep's total is what it has asked plus what is still worth asking at the
-- last look, so it moves as players turn up.
function E.SweepProgress(sweep)
    if not sweep then return 0, 0 end
    if sweep.mode == "steered" then
        return sweep.done, sweep.done + (sweep.finished and 0 or (sweep.remaining or 0))
    end
    return sweep.done, sweep.total
end

-- ---------------------------------------------------------------------------
-- The steered sweep (R20)
--
-- Commander Ladder's roster says who the realm's rated players are: faction,
-- class, race, guild and last login. So instead of asking about everyone,
-- each press asks where the rated players of our faction NOT yet on the
-- board are most likely to be, by expected new finds:
--   * the arena zones -- z-"Arena" (Nagrand's and Blade's Edge's) and the
--     Ruins of Lordaeron -- every few minutes, judged by what they found the
--     last time they were asked
--   * a guild holding such players: g-"Guild" lists all of its online level
--     70s in one answer
--   * a class/race pair still holding such players
--   * a whole class, but only while it should come in under /who's 50: the
--     class queries that cap at peak are never asked
-- Each rated player starts with odds of being on from how lately they
-- logged in (E.Activity). Every answer that could have listed them and did
-- not lowers those odds by how much of its matches it showed: an answer
-- under the cap showed all of them, so it proves the rest offline. A
-- query's expected finds are the odds of its players not yet on the board,
-- times the share of its answer that fits in 50: from the total /who gave
-- for it lately, or else estimated from the rated players likely on and
-- how many others /who has been listing per rated player (learned from every
-- answer). Each query is asked once a sweep.
-- ---------------------------------------------------------------------------

E.FACTION_LETTER = { Alliance = "A", Horde = "H" }
E.ONLINE_SHARE = 0.25       -- of the recently active, roughly how many are on at a busy hour
E.MIN_EXPECT = 1.0          -- a query expected to find fewer new rated players is not asked
E.ARENA_REPEAT = 180        -- seconds before an arena zone is asked again
E.ARENA_RETRY = 900         -- ...or, once it has stopped finding anyone, this long
E.TOTAL_KEEP = 1800         -- a total /who gave is trusted this long
-- Everyone a /who lists per rated player of ours in it, before any answer
-- has said: a class or pair is mostly unrated players; a guild less so
E.PER_RATED = { class = 6, guild = 3 }
-- English zone names (no UiMap to localize them from); z- matches a part of
-- the zone's name, so "Arena" is both Nagrand Arena and Blade's Edge Arena.
-- If /who shows a match as its zone, one answer is all rated players: worth
-- asking first (A26); if it does not, two empty answers halve it twice.
E.ARENAS = {
    { kind = "arena", zone = "Arena", prior = 10, label = "arena matches" },
    { kind = "ruins", zone = "Ruins of Lordaeron", prior = 5, label = "Ruins of Lordaeron" },
}
-- How much a rated player counts, by days since their last login
E.ACTIVITY = { { 1, 1.0 }, { 3, 0.7 }, { 7, 0.45 }, { 14, 0.2 }, { 30, 0.08 } }
E.ACTIVITY_OLD, E.ACTIVITY_UNKNOWN = 0.02, 0.3
local KIND_ORDER = { arena = 1, class = 2, guild = 3, pair = 4 }
local TIER_REST = 99        -- in order: a query no single searched class makes worth a press

function E.Activity(last, now)
    last = tonumber(last)
    if not last or last <= 0 then return E.ACTIVITY_UNKNOWN end
    local days = ((tonumber(now) or 0) - last) / 86400
    for _, step in ipairs(E.ACTIVITY) do
        if days <= step[1] then return step[2] end
    end
    return E.ACTIVITY_OLD
end

-- What the session has learned, kept across sweeps: per arena zone its
-- estimate and when it was last asked; per query text the last total /who
-- gave and when; how many /who lists per rated player of ours, per kind
function E.NewLearned()
    return { arenas = {}, totals = {}, perRated = { class = E.PER_RATED.class, guild = E.PER_RATED.guild } }
end

function E.ZoneQuery(zone, level)
    level = level or E.LEVEL
    return string.format('%d-%d z-"%s"', level, level, zone)
end

function E.GuildQuery(guild, level)
    level = level or E.LEVEL
    return string.format('%d-%d g-"%s"', level, level, guild)
end

local function Add(map, key, p)
    local list = map[key]
    if not list then
        list = {}
        map[key] = list
    end
    list[#list + 1] = p
    return list
end

-- A steered plan, or nil when the roster holds nobody of `faction` it can
-- use (no ladder data, or written before the feed described players): the
-- caller then falls back to E.NewSweep. `roster`: CommanderLadder.Roster().
-- opts: faction, names, level, minRating (players below it in every bracket
-- are not looked for), now (epoch), learned (E.NewLearned, the session's),
-- and the player's search order (E.SteerOptions: order, off, inOrder).
function E.NewSteeredSweep(roster, opts)
    opts = opts or {}
    local letter = E.FACTION_LETTER[opts.faction]
    if not letter or type(roster) ~= "table" then return nil end
    local races = {}
    for _, race in ipairs(E.RACES[opts.faction]) do races[race] = true end
    local now, minRating = tonumber(opts.now) or 0, tonumber(opts.minRating) or 0
    local sweep = { mode = "steered", done = 0, found = 0, partial = {}, unanswered = {},
        faction = opts.faction, names = opts.names or {}, level = opts.level,
        learned = opts.learned or E.NewLearned(),
        byKey = {}, guilds = {}, pairs = {}, classes = {}, asked = {}, offline = {}, foundKeys = {},
        rated = 0, guildCount = 0 }
    local any = false
    for _, r in ipairs(roster) do
        if type(r) == "table" and r.key and r.faction == letter and races[r.race]
            and E.CLASS_RACES[r.class] and E.CLASS_RACES[r.class][r.race] then
            any = true
            if (tonumber(r.best) or 0) >= minRating then
                local p = { key = r.key, class = r.class, race = r.race, guild = r.guild,
                    w = E.Activity(r.last, now) }
                p.odds = math.min(0.95, p.w * E.ONLINE_SHARE)
                sweep.byKey[p.key] = p
                sweep.rated = sweep.rated + 1
                if p.guild then
                    if not sweep.guilds[p.guild] then sweep.guildCount = sweep.guildCount + 1 end
                    Add(sweep.guilds, p.guild, p)
                end
                Add(sweep.pairs, p.class .. ":" .. p.race, p)
                Add(sweep.classes, p.class, p)
            end
        end
    end
    if not any then return nil end
    E.SteerOptions(sweep, opts)
    return sweep
end

-- The player's search order (R21), live: read at every choice, so a change
-- in the window takes effect on the next press without a new sweep.
-- opts.off: classes not searched -- their players are not looked for, their
-- class and pair queries never asked, and they add nothing to a guild's
-- worth. opts.inOrder: ask down the order -- every query worth a press for
-- the first class before any for the second (see E.SteerCandidates);
-- otherwise the most expected finds first, as before, the order unused.
function E.SteerOptions(sweep, opts)
    if not sweep then return end
    opts = opts or {}
    sweep.off = opts.off or {}
    sweep.ranks = E.ClassRanks(opts.order, sweep.off)
    sweep.inOrder = opts.inOrder and true or false
end

-- A list's players: the odds of those not on the board (expected new finds
-- before the cap), how many rated players of it are likely on in all (the
-- board's for certain), how many unfound could still be on, and the
-- unfound odds by class. A class switched off (`off`) is not looked for, so
-- adds nothing to the finds -- but its players still take up /who's 50.
local function Weigh(list, seen, off)
    local unfound, on, n, byClass = 0, 0, 0, {}
    for _, p in ipairs(list) do
        if seen[p.key] then
            on = on + 1
        elseif p.odds > 0 then
            on = on + p.odds
            if not (off and off[p.class]) then
                unfound, n = unfound + p.odds, n + 1
                byClass[p.class] = (byClass[p.class] or 0) + p.odds
            end
        end
    end
    return unfound, on, n, byClass
end

-- A total /who gave for a query lately, or nil
local function KnownTotal(learned, text, now)
    local known = learned.totals[text]
    if known and now - known.at < E.TOTAL_KEEP then return known.total end
    return nil
end

-- How many a query should match in all: the total it gave lately, else the
-- rated players likely on times everyone /who lists per rated player.
-- `atLeast`: a floor known some other way (a class's pairs' totals).
local function Matches(learned, text, on, perRated, now, atLeast)
    return math.max(KnownTotal(learned, text, now) or on * perRated, atLeast or 0)
end

-- Every query worth a press now, the most expected new finds first. Each is
-- { kind = "arena"|"class"|"guild"|"pair", text, label, expect, ... }.
--
-- In order (sweep.inOrder, R21), each query also gets a tier: the place of
-- the first searched class whose own unfound players make it worth a press
-- (0 for the arena zones, which list every class at once; TIER_REST when no
-- one class does), and they are asked tier by tier, each tier by that
-- class's expected finds. So the order is followed strictly, and still no
-- press is spent on a query not worth one.
function E.SteerCandidates(sweep, seen, now)
    seen, now = seen or {}, tonumber(now) or 0
    local out, learned, level, names = {}, sweep.learned, sweep.level, sweep.names
    local off, ranks, inOrder = sweep.off or {}, sweep.ranks or {}, sweep.inOrder
    -- An arena zone's worth is in rated players of every class: only the
    -- share of them still searched counts
    local share, all = 0, 0
    for class, list in pairs(sweep.classes) do
        all = all + #list
        if not off[class] then share = share + #list end
    end
    share = all > 0 and share / all or 0
    for _, a in ipairs(E.ARENAS) do
        local st = learned.arenas[a.kind]
        local est = st and st.est or a.prior
        local since = st and st.at and now - st.at or math.huge
        local expect
        if est >= E.MIN_EXPECT then
            if since >= E.ARENA_REPEAT then expect = est end
        elseif since >= E.ARENA_RETRY then
            expect = E.MIN_EXPECT -- quiet lately: tried now and then, last of all
        end
        if expect and share > 0 then
            out[#out + 1] = { kind = "arena", arena = a.kind, text = E.ZoneQuery(a.zone, level),
                label = a.label, expect = expect * share, tier = 0, tierExpect = expect * share }
        end
    end
    -- A query's expected finds: its unfound players' odds times the share of
    -- its matches that fits in 50. A class expected past 50 is not offered.
    local function Offer(q, list, perRated, atLeast)
        if sweep.asked[q.text] or (q.class and off[q.class]) then return end
        local unfound, on, n, byClass = Weigh(list, seen, off)
        local matches = Matches(learned, q.text, on, perRated, now, atLeast)
        if q.kind == "class" and matches > E.WHO_CAP then return end
        local fit = math.min(1, E.WHO_CAP / math.max(matches, 1))
        q.expect = unfound * fit
        q.targets = n
        if q.expect < E.MIN_EXPECT then return end
        q.tier, q.tierExpect = TIER_REST, q.expect
        for class, odds in pairs(byClass) do
            local rank = ranks[class]
            if rank and rank < q.tier and odds * fit >= E.MIN_EXPECT then
                q.tier, q.tierExpect = rank, odds * fit
            end
        end
        out[#out + 1] = q
    end
    local perClass, perGuild = learned.perRated.class, learned.perRated.guild
    -- What its pairs matched lately is a floor under a class's matches
    local pairTotals = {}
    for pairKey in pairs(sweep.pairs) do
        local class, race = pairKey:match("^(.-):(.+)$")
        pairTotals[class] = (pairTotals[class] or 0)
            + (KnownTotal(learned, E.Query(class, race, names, level), now) or 0)
    end
    for class, list in pairs(sweep.classes) do
        Offer({ kind = "class", class = class, text = E.Query(class, nil, names, level),
            label = E.PairLabel(class, nil, names) }, list, perClass, pairTotals[class])
    end
    for pairKey, list in pairs(sweep.pairs) do
        local class, race = pairKey:match("^(.-):(.+)$")
        Offer({ kind = "pair", pair = pairKey, class = class, race = race, text = E.Query(class, race, names, level),
            label = E.PairLabel(class, race, names) }, list, perClass)
    end
    for guild, list in pairs(sweep.guilds) do
        Offer({ kind = "guild", guild = guild, text = E.GuildQuery(guild, level), label = "<" .. guild .. ">" },
            list, perGuild)
    end
    table.sort(out, function(a, b)
        if inOrder then
            if a.tier ~= b.tier then return a.tier < b.tier end
            if a.tierExpect ~= b.tierExpect then return a.tierExpect > b.tierExpect end
        end
        if a.expect ~= b.expect then return a.expect > b.expect end
        if a.kind ~= b.kind then return KIND_ORDER[a.kind] < KIND_ORDER[b.kind] end
        return a.text < b.text
    end)
    return out
end

-- The class a query is searching for, for the window's list: its own class,
-- or in order the class of its tier; nil for an arena zone or a guild asked
-- for everyone
function E.QueryClass(sweep, q)
    if not q then return nil end
    if q.class then return q.class end
    if sweep and sweep.inOrder and q.tier and q.tier > 0 and q.tier ~= TIER_REST then
        for class, rank in pairs(sweep.ranks or {}) do
            if rank == q.tier then return class end
        end
    end
    return nil
end

function E.SteerNext(sweep, seen, now)
    if sweep.finished then return nil end
    local list = E.SteerCandidates(sweep, seen, now)
    sweep.remaining = #list
    if not list[1] then sweep.finished = true end
    return list[1]
end

function E.SteerSent(sweep, q, now, seen)
    sweep.inflight = q
    q.seen = seen or {}
    q.sentAt = tonumber(now) or 0
    if q.kind == "arena" then
        local st = sweep.learned.arenas[q.arena]
        if not st then
            st = { est = q.expect }
            sweep.learned.arenas[q.arena] = st
        end
        st.at = q.sentAt
    else
        sweep.asked[q.text] = true
    end
end

-- The rated players of ours a query would list
local function Members(sweep, q)
    if q.kind == "class" then return sweep.classes[q.class] or {} end
    if q.kind == "guild" then return sweep.guilds[q.guild] or {} end
    if q.kind == "pair" then return sweep.pairs[q.pair] or {} end
    return {}
end

-- The answer to the query in flight. New rated finds are counted (rated
-- players of ours it listed who were not on the board when it was sent); an
-- arena zone's estimate moves halfway to what it found; the total and how
-- many it listed per rated player are learned. Its players it did not list
-- (and were not on the board) have their odds lowered by the share of its
-- matches it showed (Bayes: odds(1 - f) / (1 - odds f)); under the cap that
-- share is all, so they are offline for this sweep, and an uncapped class
-- settles its pairs too. A capped pair or guild is partial (a capped class
-- is not: its pairs are still to come). Those an uncapped class or pair
-- proved offline (class and race do not change, a guild can) are returned
-- so the board can drop them.
function E.SteerResult(sweep, shown, total, unanswered, answer)
    local q = sweep.inflight
    if not q then return nil end
    sweep.inflight = nil
    sweep.done = sweep.done + 1
    shown, total = tonumber(shown) or 0, tonumber(total) or 0
    answer = answer or {}
    local learned = sweep.learned
    local finds, ratedListed = 0, 0
    if unanswered then
        sweep.unanswered[#sweep.unanswered + 1] = q.text
    else
        for key in pairs(answer) do
            if sweep.byKey[key] then
                ratedListed = ratedListed + 1
                if not q.seen[key] and not sweep.foundKeys[key] then
                    sweep.foundKeys[key] = true
                    finds = finds + 1
                end
            end
        end
        sweep.found = sweep.found + finds
        learned.totals[q.text] = { total = math.max(total, shown), at = q.sentAt or 0 }
        if q.kind ~= "arena" then
            local kind = q.kind == "guild" and "guild" or "class"
            learned.perRated[kind] = (learned.perRated[kind] + (shown + 1) / (ratedListed + 1)) / 2
        end
    end
    if q.kind == "arena" then
        local st = learned.arenas[q.arena]
        if st then st.est = (st.est + finds) / 2 end
        return nil
    end
    if unanswered then return nil end
    local capped = total > shown or shown >= E.WHO_CAP
    local f = capped and shown / math.max(total, shown, 1) or 1
    if capped and total <= shown then f = 0.5 end -- exactly 50 and no total: half, a guess
    local gone = {}
    for _, p in ipairs(Members(sweep, q)) do
        if not answer[p.key] then
            if f >= 1 then
                -- on the board a minute ago or not: not on now
                p.odds = 0
                sweep.offline[p.key] = true
                if q.kind ~= "guild" then gone[#gone + 1] = p.key end
            elseif not q.seen[p.key] and p.odds > 0 then
                p.odds = p.odds * (1 - f) / (1 - p.odds * f)
            end
        end
    end
    if capped then
        if q.kind ~= "class" then sweep.partial[#sweep.partial + 1] = q.text end
        return nil
    end
    if q.kind == "class" then
        for pairKey in pairs(sweep.pairs) do
            local class, race = pairKey:match("^(.-):(.+)$")
            if class == q.class then sweep.asked[E.Query(class, race, sweep.names, sweep.level)] = true end
        end
    end
    return gone
end
