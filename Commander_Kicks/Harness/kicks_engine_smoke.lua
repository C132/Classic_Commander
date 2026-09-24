-- Commander Kicks engine smoke (luajit). No WoW mock is needed or wanted:
-- everything under test is a pure function of what it was told and what time
-- it is, which is the reason the engine was split out at all.
--
--   luajit Commander_Kicks/Harness/kicks_engine_smoke.lua
--
-- Sections:
--   A  the book: every entry's numbers agree with Arena Frames' generated copy
--   B  matching: ids, ranks by name, the shocks, the pet's Spell Lock
--   C  the ledger: spend, remaining, the restamp window
--   D  rows for a roster: fixed order, ready vs. down, the lockout stretch
--   E  the back-up flash and the classic (ready-hidden) bar
--   F  strangers: only what they spent, in first-seen order
--   G  forgetting people
--   H  formatting

local ADDONS = "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"

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
local function NEAR(got, want, label, tol)
    CHECK(type(got) == "number" and math.abs(got - want) <= (tol or 0.001), label,
          string.format("got %s want %s", tostring(got), tostring(want)))
end

assert(loadfile(ADDONS .. "/Commander_Kicks/CommanderKicksData.lua"))()
assert(loadfile(ADDONS .. "/Commander_Kicks/CommanderKicksEngine.lua"))()
local DATA, E = CommanderKicks_Data, CommanderKicks_Engine

-- === A: the book agrees with the generated cooldown book ===================
-- Arena Frames' ENEMY_BOOK / RACIAL_BOOK came out of the client's own
-- SpellCooldowns for the same build. Every interrupt here that it also
-- lists has to carry the same id and cooldown, or one of the two is wrong
-- and this is the cheapest place to find out which.
do
    local ok = pcall(function()
        assert(loadfile(ADDONS .. "/Commander_ArenaFrames/CommanderArenaFramesData.lua"))()
    end)
    if not ok or not CommanderArenaFrames_Data then
        io.write("note  Commander_ArenaFrames not present -- book parity unchecked\n")
    else
        local theirs = {}
        for _, entries in pairs(CommanderArenaFrames_Data.ENEMY_BOOK or {}) do
            for _, entry in ipairs(entries) do theirs[entry.name] = entry end
        end
        for _, entries in pairs(CommanderArenaFrames_Data.RACIAL_BOOK or {}) do
            for _, entry in ipairs(entries) do theirs[entry.name] = entry end
        end
        local compared = 0
        for _, mine in ipairs(DATA.BOOK) do
            local other = theirs[mine.name]
            if other then
                compared = compared + 1
                EQ(mine.id, other.id, "A: " .. mine.name .. " id agrees with Arena Frames")
                EQ(mine.cd, other.cd, "A: " .. mine.name .. " cooldown agrees with Arena Frames")
            end
        end
        CHECK(compared >= 8, "A: most of the book is cross-checked", compared)
    end
    EQ(#DATA.BOOK, 10, "A: ten interrupts in TBC")
    for _, entry in ipairs(DATA.BOOK) do
        CHECK(entry.id and entry.name and entry.cd and entry.lock, "A: " .. tostring(entry.name) .. " is complete")
        CHECK((entry.class and not entry.race) or (entry.race and not entry.class),
            "A: " .. tostring(entry.name) .. " belongs to exactly one of class/race")
    end
end

-- === B: matching ============================================================
do
    EQ(E.Entry(38768, "Kick").name, "Kick", "B: top-rank id matches")
    EQ(E.Entry(1766, "Kick").name, "Kick", "B: rank 1 id is unknown, the name carries it")
    EQ(E.Entry(999999, "Counterspell").name, "Counterspell", "B: any id, known name")
    EQ(E.Entry(8056, "Frost Shock").name, "Earth Shock", "B: Frost Shock spends the Earth Shock cooldown")
    EQ(E.Entry(nil, "Flame Shock").name, "Earth Shock", "B: so does Flame Shock")
    EQ(E.Entry(19244, "Spell Lock").name, "Spell Lock", "B: rank-1 Spell Lock by name")
    CHECK(E.Entry(19647, "Spell Lock").pet, "B: Spell Lock is the pet's")
    EQ(E.Entry(25046, "Arcane Torrent").name, "Arcane Torrent", "B: the energy Torrent is the same Torrent")
    EQ(E.Entry(116, "Frostbolt"), nil, "B: a non-interrupt is nothing")
    EQ(E.Entry(nil, nil), nil, "B: nothing is nothing")

    local rogue = E.BookFor("ROGUE", "BloodElf")
    EQ(#rogue, 2, "B: a blood-elf rogue carries Kick and Arcane Torrent")
    EQ(rogue[1].name, "Kick", "B: ...class first")
    EQ(rogue[2].name, "Arcane Torrent", "B: ...racial after")
    local warrior = E.BookFor("WARRIOR", "Orc")
    EQ(#warrior, 2, "B: a warrior carries Pummel and Shield Bash")
    EQ(#E.BookFor(nil, nil), 0, "B: an unknown enemy carries nothing")
    EQ(#E.BookFor("PALADIN", "Human"), 0, "B: a paladin has no interrupt in TBC")
end

-- === C: the ledger ==========================================================
do
    local bar = E.NewBar()
    local kick = E.Entry(nil, "Kick")
    local entry, fresh = bar:Used("rogue", kick, 100)
    EQ(entry, kick, "C: Used returns the entry")
    CHECK(fresh, "C: the first press is fresh")
    local left = bar:Remaining("rogue", "Kick", 104)
    NEAR(left, 6, "C: ten-second Kick, four seconds in, six to go")
    local ready, seen = bar:Remaining("rogue", "Kick", 111)
    CHECK(ready == nil and seen == true, "C: back after ten seconds, and remembered as seen")
    local never, everSeen = bar:Remaining("rogue", "Pummel", 111)
    CHECK(never == nil and everSeen == false, "C: never pressed is nil and unseen")

    -- The restamp window: the same press arriving twice is one press
    local _, again = bar:Used("rogue", kick, 100.2)
    CHECK(not again, "C: a restamp inside the window is not fresh")
    NEAR(bar:Remaining("rogue", "Kick", 104), 6, "C: ...and does not move the clock")
    local _, later = bar:Used("rogue", kick, 111)
    CHECK(later, "C: a second press after the cooldown is fresh")
    NEAR(bar:Remaining("rogue", "Kick", 112), 9, "C: ...and restarts the clock")

    CHECK(bar:Knows("rogue") and not bar:Knows("mage"), "C: Knows answers per owner")
    EQ(bar:Count(), 1, "C: one person tracked")
    CHECK(not bar:Used(nil, kick, 1), "C: no owner, no entry")
    CHECK(not bar:Used("x", nil, 1), "C: no entry, no entry")
end

-- === D: rows for a roster ===================================================
do
    local bar = E.NewBar()
    local roster = {
        { key = "mage", name = "Frostpath", class = "MAGE", race = "Human", seat = 1 },
        { key = "rogue", name = "Shivspine", class = "ROGUE", race = "BloodElf", seat = 2 },
        { key = "sham", name = "Zaldrek", class = "SHAMAN", race = "Troll", seat = 3 },
    }
    local rows = bar:Rows(100, roster, true, 1.5)
    EQ(#rows, 4, "D: the roster's whole book from the gates: CS, Kick, Torrent, Earth Shock")
    EQ(rows[1].entry.name, "Counterspell", "D: seat 1 first")
    EQ(rows[2].entry.name, "Kick", "D: seat 2's class interrupt")
    EQ(rows[3].entry.name, "Arcane Torrent", "D: ...then their racial")
    EQ(rows[4].entry.name, "Earth Shock", "D: seat 3")
    CHECK(rows[1].ready and rows[2].ready and rows[3].ready and rows[4].ready, "D: all ready, nothing pressed")
    EQ(rows[2].info.seat, 2, "D: a row carries its owner's record")

    bar:Used("mage", E.Entry(nil, "Counterspell"), 100)
    bar:Used("sham", E.Entry(nil, "Frost Shock"), 101)
    rows = bar:Rows(103, roster, true, 1.5)
    EQ(#rows, 4, "D: same shape after presses -- fixed order is the point")
    EQ(rows[1].entry.name, "Counterspell", "D: CS still first")
    CHECK(not rows[1].ready, "D: CS is down")
    NEAR(rows[1].remaining, 21, "D: 24s CS, 3s in")
    CHECK(rows[1].locked, "D: 3s into an 8s lockout: still locking")
    CHECK(not rows[4].ready, "D: a Frost Shock spent the Earth Shock")
    NEAR(rows[4].remaining, 4, "D: 6s shock, 2s in")
    CHECK(rows[4].locked == false, "D: 2s in, the 2s lockout is over")
    CHECK(rows[2].ready and rows[3].ready, "D: the rogue untouched")

    rows = bar:Rows(109, roster, true, 1.5)
    CHECK(not rows[1].locked, "D: 9s in, the CS lockout is over")
    NEAR(rows[1].remaining, 15, "D: ...with 15 to go")
    CHECK(rows[4].ready, "D: the shock is back")
    CHECK(not rows[4].justReady, "D: ...and back long enough not to flash")

    -- Rows are reused: the same table comes back, with stale tail removed
    local scratch = {}
    local first = bar:Rows(103, roster, true, 1.5, scratch)
    CHECK(first == scratch, "D: the scratch table is the one returned")
    -- Later, with only the mage on the roster: the shaman, now a stranger
    -- with nothing running, contributes nothing, and the old tail is gone
    local second = bar:Rows(130, { roster[1] }, true, 1.5, scratch)
    EQ(#second, 1, "D: a shorter answer trims the tail")
end

-- === E: the back-up flash, and the classic bar =============================
do
    local bar = E.NewBar()
    local roster = { { key = "rogue", name = "Shivspine", class = "ROGUE", race = "Human", seat = 1 } }
    bar:Used("rogue", E.Entry(nil, "Kick"), 100)

    local rows = bar:Rows(110.5, roster, true, 1.5)
    CHECK(rows[1].ready and rows[1].justReady, "E: half a second after coming back: flashing")
    EQ(rows[1].at, 100, "E: the row still knows when it was pressed")
    rows = bar:Rows(112, roster, true, 1.5)
    CHECK(rows[1].ready and not rows[1].justReady, "E: two seconds after: flash over")

    -- Ready icons hidden: only what is down is drawn, plus the flash tail
    rows = bar:Rows(105, roster, false, 1.5)
    EQ(#rows, 1, "E: classic bar: the spent Kick is drawn")
    CHECK(not rows[1].ready, "E: ...as down")
    rows = bar:Rows(110.5, roster, false, 1.5)
    EQ(#rows, 1, "E: classic bar: the icon lingers to flash 'back up'")
    CHECK(rows[1].justReady, "E: ...flashing")
    rows = bar:Rows(112, roster, false, 1.5)
    EQ(#rows, 0, "E: classic bar: then it leaves")
    rows = bar:Rows(105, roster, false, 0)
    EQ(#rows, 1, "E: flash off: down icons still draw")
    rows = bar:Rows(110.1, roster, false, 0)
    EQ(#rows, 0, "E: flash off: back means gone")
end

-- === F: strangers ============================================================
do
    local bar = E.NewBar()
    local roster = { { key = "mage", name = "Frostpath", class = "MAGE", seat = 1 } }
    -- Two people seen only in the log, in this order
    bar:Used("lock-pet", E.Entry(nil, "Spell Lock"), 100)
    bar:Used("hunter", E.Entry(nil, "Silencing Shot"), 101)
    bar:Describe("hunter", { name = "Deadeye", class = "HUNTER" })

    local rows = bar:Rows(102, roster, true, 1.5)
    EQ(#rows, 3, "F: the seat's book, then the strangers' spent kicks")
    EQ(rows[1].entry.name, "Counterspell", "F: the roster comes first")
    EQ(rows[2].entry.name, "Spell Lock", "F: strangers in first-seen order")
    EQ(rows[3].entry.name, "Silencing Shot", "F: ...second seen second")
    EQ(rows[3].info and rows[3].info.name, "Deadeye", "F: a described stranger is named")
    EQ(rows[2].info, nil, "F: an undescribed one is not")

    -- A stranger's READY kick is not drawn, even with ready icons on: a
    -- stranger has no book, only a history
    rows = bar:Rows(130, roster, true, 1.5)
    EQ(#rows, 1, "F: strangers vanish once their cooldowns are back")

    -- A seat's spent kick that its book does not list is still drawn
    bar:Used("mage", E.Entry(nil, "Arcane Torrent"), 100)   -- race unknown
    rows = bar:Rows(102, roster, true, 1.5)
    EQ(rows[2].entry.name, "Arcane Torrent", "F: a seen cooldown off the book is drawn after it")
    EQ(rows[2].owner, "mage", "F: ...on its owner")
end

-- === G: forgetting people ===================================================
do
    local bar = E.NewBar()
    bar:Used("a", E.Entry(nil, "Kick"), 100)          -- back at 110
    bar:Used("b", E.Entry(nil, "Counterspell"), 100)  -- back at 124
    bar:Prune(120, 15)
    CHECK(bar:Knows("a") and bar:Knows("b"), "G: inside the grace, both kept")
    bar:Prune(126, 15)
    CHECK(not bar:Knows("a"), "G: a's Kick has been back 16s: forgotten")
    CHECK(bar:Knows("b"), "G: b's CS has been back 2s: kept")
    bar:Wipe()
    EQ(bar:Count(), 0, "G: wipe empties it")
    bar:Used("c", E.Entry(nil, "Kick"), 1)
    bar:Clear("c")
    CHECK(not bar:Knows("c"), "G: clear drops one")
end

-- === H: formatting ==========================================================
do
    EQ(E.FormatTime(nil), "", "H: nil is blank")
    EQ(E.FormatTime(0), "", "H: zero is blank")
    EQ(E.FormatTime(4.26), "4.3", "H: under ten, tenths")
    EQ(E.FormatTime(23.6), "24", "H: over ten, whole seconds")
    EQ(E.FormatTime(80), "1:20", "H: over a minute, minutes and seconds")
    EQ(E.FormatTime(120), "2:00", "H: exactly two minutes")
end

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
