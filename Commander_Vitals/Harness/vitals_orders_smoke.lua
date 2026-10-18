-- Commander Vitals + the REAL Commander Orders (luajit).
--
--     /opt/homebrew/bin/luajit Commander_Vitals/Harness/vitals_orders_smoke.lua
--     VITALS_RUNTIME=/tmp/mutant.lua luajit ...      (a mutated CommanderVitals.lua)
--
-- Vitals 2.2.0 (Commander Orders 3.1): a worn slot's tooltip names the nearest
-- repairer, and /cvitals repair asks Orders for the waypoint. This boots the
-- real Orders over the client mock its own harnesses share
-- (Commander_Orders/Harness/orders_mock.lua, the real Commander_Events
-- framework) and Vitals' two files after it, as the client does. There is no
-- Questie here, so the repairers come from a townsfolk resolver registered
-- the way Commander Logistics registers its learned repair book.
--   A  loads clean; the wireframe shows for a worn slot
--   B  a worn slot's tooltip: its condition, then the nearest repairer by
--      name with its zone and coordinates, then how to go (/cvitals repair)
--   C  a slot above the warning line: just its condition
--   D  nobody to name (no Questie, no resolver) or Orders switched off: just
--      the condition, nothing errors
--   E  /cvitals repair: ONE waypoint (Vitals, repair), the arrow on the
--      nearest repairer, Orders' "Waypoint set" line once; again, the same

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then HERE = (os.getenv("PWD") or ".") .. "/" .. HERE end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local M = dofile(ADDONS .. "/Commander_Orders/Harness/orders_mock.lua")

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail ~= nil and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end
local function EQ(got, want, label)
    CHECK(got == want, label, "got " .. tostring(got) .. ", want " .. tostring(want))
end
local function Section(name, fn)
    local ok, err = pcall(fn)
    CHECK(ok, name .. ": ran to the end", err)
end

local SKIP = { CommanderOrdersPins = true, CommanderOrdersUI = true }
local GOLDSHIRE = { 1429, 0.42, 0.655 }

-- The repairers a learned book knows: Smith Argus is the nearest to Goldshire
local REPAIR = {
    { map = 1429, x = 0.418, y = 0.671, title = "Smith Argus", npc = 514 },
    { map = 1429, x = 0.240, y = 0.740, title = "Far Smith", npc = 9002 },
}
-- slot id -> { cur, max }
local durability = {}

local function Boot(opts)
    opts = opts or {}
    local mutant = os.getenv("VITALS_RUNTIME")
    local files = { "CommanderVitalsDB.lua" }
    if not mutant then files[2] = "CommanderVitals.lua" end
    M.Boot({
        player = GOLDSHIRE,
        skipFiles = SKIP,
        before = function()
            rawset(_G, "GetInventoryItemDurability", function(slot)
                local d = durability[slot]
                if d then return d[1], d[2] end
                return nil
            end)
            rawset(_G, "GetInventoryItemTexture", function() return "Interface\\Icons\\INV_Chest_Plate01" end)
        end,
        addons = { { name = "Commander_Vitals", files = files } },
        afterFiles = function()
            if mutant then
                local chunk, err = loadfile(mutant)
                if not chunk then M.loadErrors[#M.loadErrors + 1] = tostring(err) else
                    local ok, runErr = pcall(chunk)
                    if not ok then M.loadErrors[#M.loadErrors + 1] = tostring(runErr) end
                end
            end
            if opts.book ~= false then
                CommanderOrders.RegisterResolver("townsfolk", function(kind)
                    if kind == "Repair" then return REPAIR end
                end)
            end
        end,
    })
end

local function O() return rawget(_G, "CommanderOrders") end
local function NoErrors(label)
    CHECK(#M.errors == 0, label .. ": no errors", M.errors[1])
    CHECK(#M.loadErrors == 0, label .. ": no load errors", M.loadErrors[1])
end
local function Count(needle)
    local n = 0
    for _, line in ipairs(M.prints) do
        if tostring(line):find(needle, 1, true) then n = n + 1 end
    end
    return n
end
-- The wireframe row for an inventory slot, and what hovering it says
local function Row(slot)
    for _, w in ipairs(M.W.widgets) do
        if rawget(w, "slotID") == slot then return w end
    end
    return nil
end
local function Hover(slot)
    for i = #M.tooltip, 1, -1 do M.tooltip[i] = nil end
    local row = Row(slot)
    if row and row.__scripts.OnEnter then row.__scripts.OnEnter(row) end
    return table.concat(M.tooltip, "\n")
end

-- ===========================================================================
Section("A", function()
    durability = { [5] = { 20, 100 }, [7] = { 90, 100 } }
    Boot()
    NoErrors("A")
    CHECK(CommanderVitalsFrame and CommanderVitalsFrame:IsShown(), "A: the wireframe shows for a worn slot")
    CHECK(Row(5) ~= nil, "A: (the chest row)")
end)

-- ===========================================================================
Section("B", function()
    durability = { [5] = { 20, 100 }, [7] = { 90, 100 } }
    Boot()
    local tip = Hover(5)
    CHECK(tip:find("Condition: 20 / 100 (20%)", 1, true) ~= nil, "B: the slot's condition", tip)
    CHECK(tip:find("Nearest repair: Smith Argus (Elwynn Forest 41.8, 67.1)", 1, true) ~= nil,
        "B: the nearest repairer by name, zone and coordinates", tip)
    CHECK(tip:find("/cvitals repair: Go to Repair", 1, true) ~= nil, "B: ...and how to go there", tip)
    CommanderOrdersDB.CoordDecimals = 2
    tip = Hover(5)
    CHECK(tip:find("Elwynn Forest 41.80, 67.10", 1, true) ~= nil, "B: the coordinates follow Coordinate Decimals", tip)
    CommanderOrdersDB.CoordDecimals = 1
    NoErrors("B")
end)

-- ===========================================================================
Section("C", function()
    durability = { [5] = { 20, 100 }, [7] = { 90, 100 } }
    Boot()
    local tip = Hover(7)
    CHECK(tip:find("Condition: 90 / 100", 1, true) ~= nil, "C: a sound slot: its condition", tip)
    CHECK(tip:find("Nearest repair", 1, true) == nil, "C: ...and nothing about repairing", tip)
end)

-- ===========================================================================
Section("D", function()
    durability = { [5] = { 20, 100 } }
    Boot({ book = false })
    local tip = Hover(5)
    CHECK(tip:find("Condition: 20 / 100", 1, true) ~= nil and tip:find("Nearest repair", 1, true) == nil,
        "D: nobody to name: just the condition", tip)
    Boot()
    CommanderOrdersDB.EnableOrders = false
    tip = Hover(5)
    CHECK(tip:find("Nearest repair", 1, true) == nil, "D: Orders switched off: just the condition", tip)
    CommanderOrdersDB.EnableOrders = true
    NoErrors("D")
end)

-- ===========================================================================
Section("E", function()
    durability = { [5] = { 20, 100 } }
    Boot()
    M.ClearLog()
    SlashCmdList["COMMANDERUI_VITALS"]("repair")
    M.Frame()
    local wp = O().R.Store():ByKey("Vitals", "repair")
    CHECK(wp ~= nil, "E: /cvitals repair is a waypoint (Vitals, repair)")
    EQ(wp and wp.icon, "VENDOR", "E: ...in the vendor tint")
    local active = O().Active()
    EQ(active and active.uid, wp and wp.uid, "E: the arrow on it")
    CHECK(active and math.abs(active.x - 0.418) < 1e-9, "E: ...pointing at the nearest repairer")
    EQ(Count("Waypoint set"), 1, "E: Orders' own \"Waypoint set\" line, once")
    SlashCmdList["COMMANDERUI_VITALS"]("repair")
    EQ(#O().List({ source = "Vitals" }), 1, "E: again: the same waypoint")
    NoErrors("E")
end)

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
