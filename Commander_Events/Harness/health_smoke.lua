-- Commander.Health estimator smoke (luajit)
--
--     luajit Commander_Events/Harness/health_smoke.lua
--
-- The book is pure: percent readings in, damage and healing in, a maximum
-- out. These are the claims a healer would make about it by hand.

local HERE = arg and arg[0] and arg[0]:match("^(.*)[/\\]") or "."
local ROOT = HERE .. "/.."

-- A sliver of client: frames that remember their handler and events, a
-- combat log we can write, and unit tokens we can describe
local frames = {}
function CreateFrame()
    local f = { events = {} }
    f.RegisterEvent = function(self, e) self.events[e] = true end
    f.UnregisterEvent = function(self, e) self.events[e] = nil end
    f.SetScript = function(self, _, fn) self.handler = fn end
    frames[#frames + 1] = f
    return f
end
local clock = 0
function GetTime() return clock end
function time() return 1700000000 + clock end
bit = bit or require("bit")
COMBATLOG_OBJECT_TYPE_PET = 0x1000
local units = {}      -- token -> { guid, player, max, cur, dead }
function UnitExists(u) return units[u] ~= nil end
function UnitGUID(u) return units[u] and units[u].guid end
function UnitIsPlayer(u) return units[u] and units[u].player or false end
function UnitPlayerControlled(u) return units[u] and units[u].player or false end
function UnitHealthMax(u) return units[u] and units[u].max or 0 end
function UnitHealth(u) return units[u] and units[u].cur or 0 end
function UnitIsDeadOrGhost(u) return units[u] and units[u].dead or false end
local cleu = {}
function CombatLogGetCurrentEventInfo() return unpack(cleu, 1, 25) end

dofile(ROOT .. "/CommanderHealth.lua")
local H = Commander.Health
local function Fire(event, ...)
    for _, f in ipairs(frames) do
        if f.handler and f.events[event] then f.handler(f, event, ...) end
    end
end

local pass, fail = 0, 0
local function check(cond, label, detail)
    if cond then pass = pass + 1 else fail = fail + 1; print("  FAIL  " .. label .. (detail and ("  [" .. tostring(detail) .. "]") or "")) end
end
local function near(a, b, tol) return a and b and math.abs(a - b) <= (tol or 0.5) end

print("A. one clean drop")
do
    local b = H.NewBook()
    b:Percent("Player-1", 100, 0)
    b:Damage("Player-1", 900, 1)
    check(b:Max("Player-1") == nil, "no estimate before the percent moves")
    b:Percent("Player-1", 90, 1)
    local max, q, span = b:Max("Player-1")
    check(near(max, 9000, 1), "900 damage for 10 points -> 9000", max)
    check(q == "ROUGH" and span == 10, "ten points is a rough ruler", q)
    check(b:Current("Player-1", 90) == 8100, "current from percent and estimate", b:Current("Player-1", 90))
    -- A finer reading later replaces it
    b:Damage("Player-1", 4500, 2)
    b:Percent("Player-1", 40, 2)
    max, q, span = b:Max("Player-1")
    check(near(max, 9000, 1) and span == 60 and q == "GOOD", "sixty points is a good ruler (" .. tostring(max) .. ", " .. tostring(q) .. ")")
end

print("B. quantisation and the short-span guard")
do
    local b = H.NewBook()
    b:Percent("Player-2", 100, 0)
    b:Damage("Player-2", 150, 1)
    b:Percent("Player-2", 98, 1)
    check(b:Max("Player-2") == nil, "a two-point drop is below MIN_SPAN: no estimate")
    b:Damage("Player-2", 250, 2)
    b:Percent("Player-2", 95, 2)
    local max = b:Max("Player-2")
    check(near(max, 8000, 1), "five points over 400 damage -> 8000", max)
end

print("C. healing")
do
    local b = H.NewBook()
    b:Percent("Player-3", 100, 0)
    b:Damage("Player-3", 3000, 1)
    b:Heal("Player-3", 1000, 2)
    b:Percent("Player-3", 80, 2)
    local max = b:Max("Player-3")
    check(near(max, 10000, 1), "net 2000 for 20 points -> 10000", max)
    -- Overheal is the caller's job to subtract; a heal larger than the loss
    -- means the ruler is broken and re-anchors
    b:Heal("Player-3", 5000, 3)
    b:Percent("Player-3", 100, 3)
    check(near(b:Max("Player-3"), 10000, 1), "a wash keeps the earlier estimate")
    b:Damage("Player-3", 2000, 4)
    b:Percent("Player-3", 80, 4)
    check(near(b:Max("Player-3"), 10000, 1), "and the new anchor measures cleanly again", b:Max("Player-3"))
end

print("D. an unseen heal drops the ruler instead of inflating it")
do
    local b = H.NewBook()
    b:Percent("Player-4", 100, 0)
    b:Damage("Player-4", 2000, 1)
    b:Percent("Player-4", 80, 1)             -- 10000, rough
    b:Percent("Player-4", 95, 2)             -- rose, no heal in the log
    b:Damage("Player-4", 500, 3)
    b:Percent("Player-4", 90, 3)
    local max, _, span = b:Max("Player-4")
    check(near(max, 10000, 1), "the earlier estimate stands", max)
    check(span == 20, "...the post-rise five-point ruler did not replace the twenty-point one", span)
    -- Had the rise been trusted, net would be 2500 over 10 points = 25000
    b:Damage("Player-4", 4000, 4)
    b:Percent("Player-4", 50, 4)
    max, _, span = b:Max("Player-4")
    check(near(max, 10000, 1) and span == 45, "the new anchor (95) measures 4500 over 45 points", tostring(max) .. "/" .. tostring(span))
end

print("E. death is the best anchor")
do
    local b = H.NewBook()
    b:Percent("Player-5", 100, 0)
    b:Damage("Player-5", 7200, 1)
    b:Died("Player-5", 1)
    local max, q, span = b:Max("Player-5")
    check(near(max, 7200, 1) and span == 100 and q == "GOOD", "everything since full was the whole bar", max)
    check(b:Current("Player-5") == 0, "and current reads zero")
    -- Overkill is subtracted by the caller (amount - overkill); a death from
    -- a partial anchor scales
    local c = H.NewBook()
    c:Percent("Player-6", 50, 0)
    c:Damage("Player-6", 3000, 1)
    c:Died("Player-6", 1)
    check(near(c:Max("Player-6"), 6000, 1), "half a bar was 3000 -> 6000", c:Max("Player-6"))
end

print("F. exact readings win, then persist")
do
    local b = H.NewBook()
    b:Percent("Player-7", 100, 0)
    b:Damage("Player-7", 1000, 1)
    b:Percent("Player-7", 90, 1)
    b:Exact("Player-7", 6500, 8000, 2)
    local max, q = b:Max("Player-7")
    check(max == 8000 and q == "EXACT", "a group member's real maximum replaces the estimate")
    b:Damage("Player-7", 4000, 3)
    b:Percent("Player-7", 30, 3)
    check(b:Max("Player-7") == 8000, "...and later percent readings cannot dislodge it")

    local saved = b:Export(1000)
    check(saved["Player-7"] and saved["Player-7"].est == 8000 and saved["Player-7"].span == 100, "exported with its span")
    local d = H.NewBook()
    local n = d:Import(saved, 1000)
    check(n == 1, "imported one")
    local imax, iq, ispan = d:Max("Player-7")
    check(imax == 8000 and iq == "GOOD" and ispan == 99, "carried over as a wide ruler, not as exact (" .. tostring(iq) .. ", " .. tostring(ispan) .. ")")
    d:Percent("Player-7", 100, 0)
    d:Damage("Player-7", 9000, 1)
    d:Died("Player-7", 1)
    check(d:Max("Player-7") == 9000, "a fresh death (span 100) beats the imported ruler (99)")
    -- Age and cap
    local old = { ["Player-8"] = { est = 5000, span = 50, t = 0 }, ["Player-9"] = { est = 5000, span = 50, t = 999 } }
    local e = H.NewBook()
    check(e:Import(old, 1000, 500) == 1 and e:Max("Player-9") == 5000 and e:Max("Player-8") == nil, "stale entries are dropped")
    local many = {}
    for i = 1, 20 do many["Player-" .. i] = { est = 1000 + i, span = 50, t = i } end
    local f = H.NewBook()
    check(f:Import(many, 100, 1000, 5) == 5 and f:Max("Player-20") ~= nil and f:Max("Player-1") == nil, "the cap keeps the newest")
end

print("G. pruning and forgetting")
do
    local b = H.NewBook()
    b:Percent("Player-10", 100, 0)
    b:Percent("Player-11", 100, 1000)
    b:Prune(1500, 600)
    check(b.units["Player-10"] == nil and b.units["Player-11"] ~= nil, "prune drops the unseen")
    b:Forget("Player-11")
    check(b:Count() == 0, "forget")
    check(b:Max(nil) == nil and b:Current(nil) == nil, "nil-safe")
    b:Damage(nil, 5, 0); b:Heal("x", -5, 0); b:Percent("x", nil, 0)
    check(b:Count() == 0, "garbage in, nothing recorded")
end

print("H. formatting")
do
    check(H.Abbreviate(950) == "950" and H.Abbreviate(7300) == "7.3k" and H.Abbreviate(12400) == "12k" and H.Abbreviate(1500000) == "1.5m", "abbreviations")
    check(H.Abbreviate(nil) == "?", "nil")
end

print("I. the wiring: combat log in, numbers out")
do
    Fire("ADDON_LOADED", "Commander_Events")
    check(not H.IsWatching(), "nothing is watched until a consumer asks")
    units.target = { guid = "Player-A1", player = true, max = 100, cur = 100 }
    H.Watch()
    check(H.IsWatching(), "Watch registers")
    check(H.IsPercentOnly("target") == true, "a max of 100 on a player is percent-only")
    check(H.Current("target") == nil, "no estimate yet")
    -- 1200 of a spell hits, 200 of it absorbed (never touched the bar), no overkill
    clock = 1
    cleu = { clock, "SPELL_DAMAGE", false, "Player-ME", "Me", 0x511, 0, "Player-A1", "Them", 0x548, 0,
             116, "Frostbolt", 16, 1200, 0, 16, 0, 0, 200, false, false, false }
    Fire("COMBAT_LOG_EVENT_UNFILTERED")
    units.target.cur = 85
    Fire("UNIT_HEALTH", "target")
    local cur, max, q = H.Current("target")
    check(near(max, 8000, 1) and near(cur, 6800, 1), "1200 for 15 points -> 8000, current 6800 (" .. tostring(cur) .. "/" .. tostring(max) .. ")")
    check(q == "ROUGH", "rough at fifteen points", q)
    -- A swing with overkill on the killing blow, then the death
    clock = 2
    cleu = { clock, "SWING_DAMAGE", false, "Player-ME", "Me", 0x511, 0, "Player-A1", "Them", 0x548, 0,
             7300, 500, 1, 0, 0, 0, false, false, false }
    Fire("COMBAT_LOG_EVENT_UNFILTERED")
    cleu = { clock, "UNIT_DIED", false, nil, nil, 0, 0, "Player-A1", "Them", 0x548, 0 }
    Fire("COMBAT_LOG_EVENT_UNFILTERED")
    local emax, eq = H.Max("Player-A1")
    check(near(emax, 8000, 1) and eq == "GOOD", "the death from full pins it: 1200 + 6800 = 8000, good (" .. tostring(emax) .. ")")
    -- A mob is ignored
    cleu = { clock, "SPELL_DAMAGE", false, "Player-ME", "Me", 0x511, 0, "Creature-0-1-2-3-4-5", "Boar", 0xa48, 0,
             116, "Frostbolt", 16, 500, 0, 16, 0, 0, 0, false, false, false }
    Fire("COMBAT_LOG_EVENT_UNFILTERED")
    check(H.Max("Creature-0-1-2-3-4-5") == nil, "mobs stay out of the book")
    -- A party member's real numbers are exact
    units.party1 = { guid = "Player-B2", player = true, max = 6400, cur = 3200 }
    Fire("UNIT_HEALTH", "party1")
    local pc, pm, pq = H.Current("party1")
    check(pc == 3200 and pm == 6400 and pq == "EXACT", "real values pass straight through")
    -- Persistence round trip
    H.Save()
    check(CommanderHealthDB.Book["Player-A1"] and CommanderHealthDB.Book["Player-A1"].est == 8000, "saved at logout")
    check(H.Load() >= 0, "and loads back without error")
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
