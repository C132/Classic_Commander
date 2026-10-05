-- Commander Contacts scout smoke (luajit).
--
-- No mock. CommanderContactsScout is pure Lua: this feeds it hand-built
-- scoreboards, titles and ratings and checks who it suggests and why.
--
--   /opt/homebrew/bin/luajit contacts_scout_smoke.lua

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ROOT = HERE:match("^(.*)/Harness$") or HERE

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

local now = 1786000000
function time() return now end

assert(loadfile(ROOT .. "/CommanderContactsScout.lua"))()
local T = CommanderContactsScout

local db = { Performers = { Junk = "x", Old = { games = "3" } }, Dismissed = 5 }
T.Attach(db)
EQ(db.Performers.Junk, nil, "A1 junk record dropped")
EQ(db.Performers.Old.games, 3, "A1 numeric fields coerced")
EQ(db.Performers.Old.name, "Old", "A1 name filled from the key")
CHECK(type(db.Dismissed) == "table", "A1 dismissed table stood up")
db.Performers.Old = nil

local ctx = { own = "Me", ownRealm = "TestRealm", ownFaction = "HORDE", map = "Arathi Basin", now = now }

local function Row(name, faction, class, dmg, heal, kb)
    return { name = name, faction = faction, class = class, dmg = dmg, heal = heal, kb = kb }
end

-- Game 1: Bob tops damage of the whole match, Ann tops healing, an enemy
-- tops kills, a cross-realm teammate is second on damage, and I am third.
local game1 = {
    Row("Bob", "HORDE", "MAGE", 400000, 0, 12),
    Row("Ann", "HORDE", "PRIEST", 5000, 250000, 1),
    Row("Enemy", "ALLIANCE", "ROGUE", 350000, 0, 20),
    Row("Zed-Otherrealm", "HORDE", "WARLOCK", 380000, 0, 15),
    Row("Me", "HORDE", "PRIEST", 300000, 100000, 3),
    Row("Cal", "HORDE", "WARRIOR", 0, 0, 0),
    Row("Bob-TestRealm", "ALLIANCE", "MAGE", 1, 1, 1),
}
EQ(T.RecordMatch(game1, ctx), 3, "B1 three same-side same-realm strangers recorded (Bob, Ann, Cal)")
local bob = T.Record("Bob")
CHECK(bob ~= nil, "B2 Bob recorded")
EQ(bob.dmgTop, 1, "B2 Bob was top damage of the match")
EQ(bob.bestDmg, 400000, "B2 best damage kept")
EQ(bob.bestDmgMap, "Arathi Basin", "B2 with the map")
EQ(bob.kbTop3, 1, "B2 Bob was third on kills (enemy first, Zed second)")
EQ(bob.class, "MAGE", "B2 class")
local ann = T.Record("Ann")
EQ(ann.healTop, 1, "B3 Ann was top healer")
EQ(T.Record("Zed-Otherrealm"), nil, "B4 a cross-realm teammate is not recorded")
EQ(T.Record("Enemy"), nil, "B4 the other faction is not recorded")
EQ(T.Record("Me"), nil, "B4 I am not recorded")
CHECK(T.Record("Cal") ~= nil and T.Record("Cal").dmgTop == 0, "B5 a zero row is seen but earns no rank")
EQ(T.Record("Bob").games, 1, "B6 the Alliance Bob-TestRealm row did not double-count the Horde Bob")

-- Game 2, next day: Bob tops damage again in Warsong; Ann is only third on healing
now = now + 86400
ctx.now, ctx.map = now, "Warsong Gulch"
T.RecordMatch({
    Row("Bob", "HORDE", "MAGE", 210000, 0, 9),
    Row("Ann", "HORDE", "PRIEST", 0, 90000, 0),
    Row("H1", "ALLIANCE", "PRIEST", 0, 120000, 0),
    Row("H2", "ALLIANCE", "PALADIN", 0, 100000, 0),
    Row("Me", "HORDE", "PRIEST", 100000, 50000, 2),
}, ctx)
EQ(bob.games, 2, "C1 two games")
EQ(bob.dmgTop, 2, "C1 top damage twice")
EQ(bob.bestDmg, 400000, "C1 best damage is still the AB number")
EQ(bob.lastMap, "Warsong Gulch", "C1 last map moves on")
EQ(ann.healTop3, 1, "C2 Ann third this time")

-- Scores and sentences
local bobScore, bobArena, bobBG = T.Score(bob)
EQ(bobArena, 0, "D1 Bob has no arena evidence")
EQ(bobBG, 2 * 30 + 10 + 20, "D1 Bob's battleground points: two tops on damage, a top-3 and a top on kills")
local headline, detail = T.Reason(bob, now)
EQ(headline, "Top damage in all 2 games (best 400k in Arathi Basin)", "D2 Bob's sentence")
EQ(detail, "seen in 2 battlegrounds · last Warsong Gulch, just now", "D2 Bob's detail")
local annHead = T.Reason(ann, now)
EQ(annHead, "Top healer in 1 of 2 games (best 250k in Arathi Basin)", "D3 Ann's sentence")

-- Titles and ratings
CHECK(T.NoteTitle("Dee-TestRealm", "Merciless Gladiator", { own = "Me", ownRealm = "TestRealm", class = "ROGUE", now = now }), "E1 a title records a new person")
local dee = T.Record("Dee")
EQ(dee.title, "Merciless Gladiator", "E1 title kept")
EQ(dee.class, "ROGUE", "E1 class from the context")
CHECK(not T.NoteTitle("Dee", "Merciless Gladiator", ctx), "E1 the same title again is a no-op")
CHECK(not T.NoteTitle("Dee", "", ctx), "E1 an empty title changes nothing")
local _, deeArena = T.Score(dee)
EQ(deeArena, 100, "E2 a seasonal Gladiator title scores as Gladiator")
EQ((T.Reason(dee, now)), "Wears the Merciless Gladiator title", "E2 sentence")
EQ(select(2, T.Reason(dee, now)), "last seen just now", "E2 detail without battlegrounds")

CHECK(T.NoteRatings("Eve", { [2] = 1900, [3] = 2050 }, ctx), "F1 ratings recorded")
local eve = T.Record("Eve")
EQ(eve.ratings[3], 2050, "F1 3v3 rating")
CHECK(not T.NoteRatings("Eve", { [3] = 1800 }, ctx), "F2 a lower rating does not replace a higher one")
EQ(eve.ratings[3], 2050, "F2 kept")
CHECK(T.NoteRatings("Eve", { [5] = 2300 }, ctx), "F3 a new bracket is added")
local _, eveArena = T.Score(eve)
EQ(eveArena, 100, "F4 2300 is Gladiator range")
EQ((T.Reason(eve, now)), "2300 arena rating in 5v5 (Gladiator range)", "F4 sentence")
CHECK(not T.NoteRatings("Me", { [2] = 2500 }, ctx), "F5 my own rating is not a suggestion")
CHECK(not T.NoteRatings("Far-Elsewhere", { [2] = 2500 }, ctx), "F5 nor a cross-realm player's")

-- A title AND ratings: only the stronger counts, both appear in the sentence
T.NoteTitle("Eve", "Rival", ctx)
local _, eveArena2 = T.Score(eve)
EQ(eveArena2, 100, "G1 title and rating are one argument; the stronger wins")
CHECK((T.Reason(eve, now)):find("Wears the Rival title · 2300 arena rating", 1, true) ~= nil, "G1 both in the sentence", (T.Reason(eve, now)))

-- Arena plus battleground evidence adds up, and the sentence leads with the stronger
T.RecordMatch({ Row("Eve", "HORDE", "SHAMAN", 500000, 0, 30), Row("Me", "HORDE", "PRIEST", 1, 1, 1) }, ctx)
local eveScore = T.Score(eve)
EQ(eveScore, 100 + 30 + 20, "H1 arena + battleground")
CHECK((T.Reason(eve, now)):sub(1, 15) == "Wears the Rival", "H1 arena leads when it is the stronger half")
T.RecordMatch({ Row("Bob", "HORDE", "MAGE", 500000, 0, 30), Row("Me", "HORDE", "PRIEST", 1, 1, 1) }, ctx)
T.NoteTitle("Bob", "Challenger", ctx)
CHECK((T.Reason(bob, now)):sub(1, 10) == "Top damage", "H2 battleground leads when it is the stronger half", (T.Reason(bob, now)))

-- The list
local list = T.Suggestions(10, { friends = {}, now = now })
EQ(list[1].name, "Bob", "I1 Bob first: three top-damage games and a title outscore one Gladiator-range rating")
EQ(list[2].name, "Eve", "I1 Eve second")
CHECK(list[#list].name ~= "Cal", "I2 a zero-score record is not suggested")
local names = {}
for _, entry in ipairs(list) do names[entry.name] = true end
CHECK(not names.Cal, "I2 Cal absent")
local two = T.Suggestions(2, { friends = {} })
EQ(#two, 2, "I3 limit respected")
local withFriend = T.Suggestions(10, { friends = { Bob = true } })
EQ(withFriend[1].name, "Eve", "I4 a friend drops out")
CHECK(list[1].reason ~= "" and list[1].detail ~= "", "I5 entries carry reason and detail")

-- Dismiss is for good
CHECK(T.Dismiss("Bob"), "J1 dismiss")
EQ(T.Record("Bob"), nil, "J1 record gone")
T.RecordMatch(game1, ctx)
EQ(T.Record("Bob"), nil, "J1 a dismissed player is never recorded again")
CHECK(T.Record("Ann") ~= nil, "J1 others still are")
CHECK(T.Forget("Ann"), "J2 forget one")
CHECK(not T.Forget("Ann"), "J2 twice is a no-op")

-- Prune by last-seen
T.RecordMatch(game1, ctx)
T.Record("Ann").last = now - 100 * 86400
EQ(T.Prune(60, now), 1, "K1 one stale record pruned")
EQ(T.Record("Ann"), nil, "K1 Ann gone")
EQ(T.Prune(0, now), 0, "K1 zero keeps all")
local before = T.Count()
EQ(T.ForgetAll(), before, "K2 forget all reports the count")
EQ(T.Count(), 0, "K2 empty")

EQ(T.ShortNumber(412345), "412k", "L1 short numbers")
EQ(T.ShortNumber(1260000), "1.3M", "L1 millions")
EQ(T.ShortNumber(950), "950", "L1 small")

if fails > 0 then
    io.write(string.format("contacts scout smoke: %d/%d checks FAILED\n", fails, checks))
    os.exit(1)
end
io.write(string.format("contacts scout smoke: %d checks passed\n", checks))
