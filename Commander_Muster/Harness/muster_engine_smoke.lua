-- Commander Muster engine smoke harness (luajit).
-- The engine is pure Lua — no mock needed. Scores known TBC items and whole
-- kits through the real engine and asserts the TacoTip-compatible numbers,
-- the monotonic T4 -> T5 -> T6 ordering the original GearScore got wrong,
-- the hunter weapon rule, the colour bands, the arena formatting and the
-- session book.
--
--   /opt/homebrew/bin/luajit muster_engine_smoke.lua

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

assert(loadfile(ADDONS .. "/Commander_Muster/CommanderMusterData.lua"))()
assert(loadfile(ADDONS .. "/Commander_Muster/CommanderMusterEngine.lua"))()
local D = CommanderMusterData
local E = CommanderMusterEngine
E.Init(D)

-- ===========================================================================
-- Single items: numbers TacoTip prints for the same links
-- ===========================================================================

CHECK(E.ItemScore(4, 146, "INVTYPE_CHEST") == 186, "T6 chest (epic 146) scores 186", E.ItemScore(4, 146, "INVTYPE_CHEST"))
CHECK(E.ItemScore(4, 120, "INVTYPE_HEAD") == 145, "T4 helm (epic 120) scores 145", E.ItemScore(4, 120, "INVTYPE_HEAD"))
CHECK(E.ItemScore(4, 133, "INVTYPE_HEAD") == 166, "T5 helm (epic 133) scores 166", E.ItemScore(4, 133, "INVTYPE_HEAD"))
CHECK(E.ItemScore(3, 115, "INVTYPE_WRIST") == 66, "heroic blue bracers (rare 115) score 66", E.ItemScore(3, 115, "INVTYPE_WRIST"))
CHECK(E.ItemScore(4, 156, "INVTYPE_2HWEAPON") == 403, "Sunwell two-hander counts both hands", E.ItemScore(4, 156, "INVTYPE_2HWEAPON"))
CHECK(E.ItemScore(5, 156, "INVTYPE_2HWEAPON") == 524, "legendary is an epic and 30% more", E.ItemScore(5, 156, "INVTYPE_2HWEAPON"))
CHECK(E.ItemScore(4, 95, "INVTYPE_LEGS") == 108, "sub-100 epic takes the C curve", E.ItemScore(4, 95, "INVTYPE_LEGS"))
CHECK(E.ItemScore(2, 100, "INVTYPE_FEET") == 64, "level-70 green boots score 64", E.ItemScore(2, 100, "INVTYPE_FEET"))
CHECK(E.ItemScore(1, 60, "INVTYPE_CHEST") == 0, "a white shirt-grade chest scores nothing")
CHECK(E.ItemScore(4, 146, "INVTYPE_BODY") == nil, "shirt slot does not count (nil, not 0)")
CHECK(E.ItemScore(4, 146, "INVTYPE_TABARD") == nil, "tabard slot does not count")
CHECK(E.ItemScore(4, 146, nil) == nil, "unknown equip location is nil")
CHECK(E.ItemScore(nil, 146, "INVTYPE_HEAD") == nil, "missing quality is nil")
CHECK(E.ItemScore(3, 0, "INVTYPE_HEAD") == 0, "a score never goes negative")

-- The whole point of the TBC curve choice: tier order is preserved
do
    local t4 = E.ItemScore(4, 120, "INVTYPE_CHEST")
    local t5 = E.ItemScore(4, 133, "INVTYPE_CHEST")
    local t6 = E.ItemScore(4, 146, "INVTYPE_CHEST")
    local swp = E.ItemScore(4, 159, "INVTYPE_CHEST")
    CHECK(t4 < t5 and t5 < t6 and t6 < swp, "T4 < T5 < T6 < Sunwell, no cliff at 120",
        table.concat({ t4, t5, t6, swp }, " < "))
    -- monotonic across every level TBC drops, per quality
    for quality = 2, 4 do
        local last = -1
        local ok = true
        for ilvl = 1, 170 do
            local s = E.ItemScore(quality, ilvl, "INVTYPE_CHEST")
            if s < last then ok = false break end
            last = s
        end
        CHECK(ok, "quality " .. quality .. " is monotonic in item level from 1 to 170")
    end
    -- and at equal level an epic beats a rare beats a green
    for _, ilvl in ipairs({ 100, 115, 120, 128, 141, 154 }) do
        CHECK(E.ItemScore(4, ilvl, "INVTYPE_HEAD") > E.ItemScore(3, ilvl, "INVTYPE_HEAD")
            and E.ItemScore(3, ilvl, "INVTYPE_HEAD") > E.ItemScore(2, ilvl, "INVTYPE_HEAD"),
            "epic > rare > uncommon at ilvl " .. ilvl)
    end
end

-- ===========================================================================
-- Whole characters
-- ===========================================================================

local LOC = {
    [1] = "INVTYPE_HEAD", [2] = "INVTYPE_NECK", [3] = "INVTYPE_SHOULDER", [5] = "INVTYPE_CHEST",
    [6] = "INVTYPE_WAIST", [7] = "INVTYPE_LEGS", [8] = "INVTYPE_FEET", [9] = "INVTYPE_WRIST",
    [10] = "INVTYPE_HAND", [11] = "INVTYPE_FINGER", [12] = "INVTYPE_FINGER", [13] = "INVTYPE_TRINKET",
    [14] = "INVTYPE_TRINKET", [15] = "INVTYPE_CLOAK", [16] = "INVTYPE_WEAPONMAINHAND",
    [17] = "INVTYPE_SHIELD", [18] = "INVTYPE_RANGED",
}

local function Kit(quality, ilvl, overrides)
    local items = {}
    for slot, loc in pairs(LOC) do
        items[slot] = { name = "Item " .. slot, link = "link" .. slot, quality = quality, ilvl = ilvl, equipLoc = loc, loaded = true }
    end
    -- false removes a slot (nil in a constructor would be no entry at all)
    for slot, entry in pairs(overrides or {}) do items[slot] = entry or nil end
    return items
end

do
    local full = E.Score(Kit(4, 146), "WARRIOR")
    -- 17 slots; total slot weight 12.3039 x 186.18 per unit, floored per item first
    CHECK(full.count == 17, "full T6 kit counts 17 pieces", full.count)
    CHECK(full.ilvl == 146, "average item level of a uniform kit is that level", full.ilvl)
    CHECK(full.complete == true, "a fully cached kit is complete")
    -- 186 x 5 (head, chest, legs, main hand, shield) + 139 x 4 (0.75 slots)
    -- + 104 x 7 (0.5625 slots) + 58 (ranged), every piece floored on its own
    CHECK(full.score == 2272, "full T6 kit is 2272", full.score)
    local _, _, _, band = E.BandColor(full.score)
    CHECK(band == "Legendary", "full T6 reads in the top band on the TBC bracket", band)

    local t4 = E.Score(Kit(4, 120), "WARRIOR")
    CHECK(t4.score >= 1780 and t4.score <= 1800, "full T4 kit lands around 1790", t4.score)
    local _, _, _, band4 = E.BandColor(t4.score)
    CHECK(band4 == "Epic", "full T4 reads Epic", band4)

    local blues = E.Score(Kit(3, 110), "WARRIOR")
    CHECK(blues.score == 1377, "pre-raid blues are 1377", blues.score)
    local _, _, _, band3 = E.BandColor(blues.score)
    CHECK(band3 == "Superior", "pre-raid blues read Superior", band3)

    local greens = E.Score(Kit(2, 95), "WARRIOR")
    CHECK(greens.score == 980, "fresh-70 greens are 980", greens.score)
    local _, _, _, band2 = E.BandColor(greens.score)
    CHECK(band2 == "Uncommon", "fresh-70 greens read Uncommon", band2)
end

-- Two-hander: main hand counts double, off hand empty, ilvl mean unaffected by the empty slot
do
    local items = Kit(4, 146, {
        [16] = { name = "Big Axe", quality = 4, ilvl = 146, equipLoc = "INVTYPE_2HWEAPON", loaded = true },
        [17] = false,
    })
    local r = E.Score(items, "WARRIOR")
    local oneHanded = E.Score(Kit(4, 146), "WARRIOR")
    CHECK(r.count == 16, "two-hander kit counts 16 pieces", r.count)
    CHECK(r.score == oneHanded.score, "a two-hander is worth exactly main hand + off hand", r.score .. " vs " .. oneHanded.score)
    CHECK(r.ilvl == 146, "empty off hand does not drag the average down", r.ilvl)
end

-- Hunter: melee weapons are stat sticks, the ranged slot is the weapon
do
    local warrior = E.Score(Kit(4, 146), "WARRIOR")
    local hunter = E.Score(Kit(4, 146), "HUNTER")
    -- 186 x 0.3164 x 2 melee + (186 x 0.3164 -> 58) x 5.3224 ranged vs 186 x 2 + 58
    CHECK(hunter.score < warrior.score, "hunter weighting changes the total", hunter.score .. " vs " .. warrior.score)
    local expectedDelta = math.floor(186 * 2 + 58) - math.floor(186 * 0.3164 * 2 + 58 * 5.3224)
    CHECK(math.abs((warrior.score - hunter.score) - expectedDelta) <= 1, "hunter delta is the weapon rule and nothing else",
        (warrior.score - hunter.score) .. " vs " .. expectedDelta)
end

-- Incomplete: an uncached piece is reported, not invented
do
    local items = Kit(4, 146, {
        [7] = { name = nil, link = "link7", loaded = false },
    })
    local r = E.Score(items, "WARRIOR")
    CHECK(r.complete == false, "an unloaded item marks the result incomplete")
    CHECK(r.count == 16, "the unloaded item is not counted", r.count)
    local pendingRow
    for _, row in ipairs(r.slots) do if row.pending then pendingRow = row end end
    CHECK(pendingRow and pendingRow.slot == 7, "the pending row names the slot")
end

-- Weakest link
do
    local items = Kit(4, 146, {
        [9] = { name = "Old Bracers", link = "l9", quality = 2, ilvl = 88, equipLoc = "INVTYPE_WRIST", loaded = true },
    })
    local r = E.Score(items, "WARRIOR")
    CHECK(r.weakest and r.weakest.slot == 9 and r.weakest.ilvl == 88, "weakest piece is the low bracers")
    CHECK(r.ilvl < 146, "one old piece lowers the average", r.ilvl)
end

-- Empty
do
    local r = E.Score({}, "MAGE")
    CHECK(r.score == 0 and r.ilvl == 0 and r.count == 0 and r.complete == true, "an empty kit is a zero, complete")
    CHECK(r.weakest == nil, "no weakest piece in an empty kit")
end

-- ===========================================================================
-- Colours
-- ===========================================================================

do
    local r, g, b, name = E.BandColor(0)
    CHECK(name == "Trash" and math.abs(r - 0.55) < 0.001, "zero is grey Trash")
    r, g, b, name = E.BandColor(400)
    CHECK(name == "Trash", "400 is still the first band (bands are (n*400, (n+1)*400])", name)
    r, g, b, name = E.BandColor(401)
    CHECK(name == "Common" and r > 0.99 and g == 1 and b > 0.99, "401 opens the white band at (nearly) pure white")
    r, g, b, name = E.BandColor(801)
    CHECK(name == "Uncommon" and math.abs(r - 0.12) < 0.01 and g > 0.99 and b < 0.01, "801 opens the green band at quality green")
    r, g, b, name = E.BandColor(1201)
    CHECK(name == "Superior" and r < 0.01 and math.abs(g - 0.5) < 0.01 and b > 0.99, "1201 opens the blue band at quality blue")
    r, g, b, name = E.BandColor(1601)
    CHECK(name == "Epic" and math.abs(r - 0.69) < 0.01 and math.abs(g - 0.28) < 0.01 and math.abs(b - 0.97) < 0.01, "1601 opens the purple band")
    r, g, b, name = E.BandColor(2001)
    CHECK(name == "Legendary" and math.abs(r - 0.94) < 0.01 and math.abs(g - 0.47) < 0.01 and b == 0, "2001 opens the orange band")
    r, g, b, name = E.BandColor(9000)
    CHECK(name == "Legendary" and r <= 1 and g >= 0, "past the cap stays in the top band, channels clamped")
    -- drift is applied
    local r1 = E.BandColor(1601)
    local r2 = E.BandColor(1999)
    CHECK(r2 > r1, "colour drifts across a band", r1 .. " -> " .. r2)
    CHECK(E.Hex(1, 0.5, 0) == "ffff8000", "hex encoding", E.Hex(1, 0.5, 0))
    CHECK(E.FormatScore(2043):match("^|cff%x%x%x%x%x%x2043|r$"), "FormatScore wraps in a colour code", E.FormatScore(2043))
end

do
    local r, g, b = E.RatingColor(0)
    CHECK(r == 1 and g == 1 and b == 1, "unrated is white")
    r, g, b = E.RatingColor(1500)
    CHECK(g == 1 and r < 0.2, "1500 is green")
    r, g, b = E.RatingColor(1850)
    CHECK(b > 0.8 and r == 0, "1850 is blue")
    r, g, b = E.RatingColor(2000)
    CHECK(b > 0.9 and r > 0.6, "2000 is purple")
    r, g, b = E.RatingColor(2450)
    CHECK(r == 1 and g == 0.5, "2200+ is orange")
end

-- ===========================================================================
-- Arena formatting
-- ===========================================================================

do
    local line, state = E.FormatArena(nil)
    CHECK(line == nil and state == "pending", "no arena data is pending")
    line, state = E.FormatArena({ known = false })
    CHECK(line == nil and state == "pending", "unknown arena data is pending")
    line, state = E.FormatArena({ known = true })
    CHECK(line == nil and state == "unrated", "known and empty is unrated")
    line, state = E.FormatArena({ known = true, [2] = { rating = 0, played = 0 }, [3] = { rating = 0, played = 0 } })
    CHECK(line == nil and state == "unrated", "all-zero brackets are unrated")
    line, state = E.FormatArena({ known = true, [2] = { rating = 1850, played = 40, wins = 25 }, [3] = { rating = 1720, played = 10, wins = 4 } })
    CHECK(state == "rated" and line:find("2v2 ") and line:find("1850") and line:find("3v3 ") and line:find("1720"), "two brackets print in order", line)
    CHECK(not line:find("5v5"), "an absent bracket is not printed", line)
    line = E.FormatArena({ known = true, [5] = { rating = 0, played = 3, wins = 1 } })
    CHECK(line and line:find("5v5 ") and line:find(">0<") == nil, "played-but-zero-rated bracket still prints", line)
    local best, size = E.BestRating({ known = true, [2] = { rating = 1850 }, [3] = { rating = 1900 } })
    CHECK(best == 1900 and size == 3, "best rating picks the highest bracket", tostring(best) .. "/" .. tostring(size))
    CHECK(E.BestRating({ known = true }) == nil, "best rating of unrated is nil")
end

-- ===========================================================================
-- The book
-- ===========================================================================

do
    local book = E.NewBook(600, 3)
    book:Put("Player-A", { score = 1 }, 1000)
    book:Put("Player-B", { score = 2 }, 1100)
    local rec, fresh = book:Get("Player-A", 1500)
    CHECK(rec and rec.score == 1 and fresh == true, "a record inside its TTL is fresh")
    rec, fresh = book:Get("Player-A", 1601)
    CHECK(rec and fresh == false, "a record past its TTL is still returned, stale")
    rec, fresh = book:Get("Player-Z", 1000)
    CHECK(rec == nil and fresh == false, "an unknown GUID is nil")
    book:Put("Player-C", { score = 3 }, 1200)
    book:Put("Player-D", { score = 4 }, 1300)
    CHECK(book:Count() == 3, "the keep limit prunes to size", book:Count())
    CHECK(book:Get("Player-A", 1300) == nil, "the oldest record went first")
    CHECK(book:Get("Player-D", 1300) ~= nil, "the newest survived")
    book:Put("Player-D", { score = 5 }, 1400)
    CHECK(book:Count() == 3 and book:Get("Player-D", 1400).score == 5, "re-putting replaces in place")
    book:Forget("Player-D")
    CHECK(book:Count() == 2 and book:Get("Player-D", 1400) == nil, "forget drops one")
    book:Prune(5000)
    CHECK(book:Count() == 0, "prune past the TTL empties the book")
    book:Put(nil, { score = 1 }, 1)
    CHECK(book:Count() == 0, "a nil GUID is ignored")
end

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
