-- Commander Bags + the REAL Commander Orders (luajit).
--
--     /opt/homebrew/bin/luajit Commander_Bags/Harness/bags_orders_smoke.lua
--
-- bags_harness.lua checks Go to Vendor / Go to Repair against a recording
-- stand-in for Orders. This boots the real Orders over the client mock its own
-- harnesses share (Commander_Orders/Harness/orders_mock.lua) and the Bags files
-- after it, as the client does. There is no Questie here, so the "nearest"
-- lists come from a townsfolk resolver registered the way Commander Logistics
-- registers its learned repair book (Orders' locator merges resolvers with
-- Questie's lists, and answers from them alone without Questie):
--   A  loads clean beside Orders
--   B  Go to Vendor: ONE waypoint (Bags, vendor) whose alternatives are every
--      vendor on your landmass, the arrow on the nearest, Orders' "Waypoint
--      set" line once; Go to Repair its own (Bags, repair); the lit "Going"
--   C  /cb vendor and /cb repair move the same records
--   D  nothing to ask (no Questie, no resolver): Orders' ONE refusal line,
--      in its words; Orders switched off: greyed with the reason

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

-- Elwynn's merchants and repairers, as a learned book would hand them over
local BOOK = {
    Vendor = {
        { map = 1429, x = 0.43, y = 0.66, title = "Innkeeper Farley", npc = 295 },
        { map = 1429, x = 0.41, y = 0.65, title = "Brog Hamfist", npc = 1735 },
        { map = 1429, x = 0.24, y = 0.74, title = "Far Vendor", npc = 9001 },
    },
    Repair = {
        { map = 1429, x = 0.418, y = 0.671, title = "Smith Argus", npc = 514 },
    },
}

local function Boot(opts)
    opts = opts or {}
    M.Boot({
        player = GOLDSHIRE,
        skipFiles = SKIP,
        -- Blizzard's container layout function, which Bags hooks at load
        before = function() rawset(_G, "UpdateContainerFrameAnchors", function() end) end,
        addons = { "Commander_Bags" },
        afterFiles = function()
            if opts.book ~= false then
                CommanderOrders.RegisterResolver("townsfolk", function(kind) return BOOK[kind] end)
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
local function Go(label)
    local found
    for _, w in ipairs(M.W.widgets) do
        if rawget(w, "_goLabel") == label then found = w end
    end
    return found
end
local function Click(b) b.__scripts.OnClick(b, "LeftButton", false) end

-- ===========================================================================
Section("A", function()
    Boot()
    NoErrors("A")
    CHECK(Go("Go to Vendor") ~= nil and Go("Go to Repair") ~= nil, "A: the two Go buttons are on the settings page")
end)

-- ===========================================================================
Section("B", function()
    Boot()
    local gv = Go("Go to Vendor")
    M.ClearLog()
    Click(gv)
    M.Frame()
    local wp = O().R.Store():ByKey("Bags", "vendor")
    CHECK(wp ~= nil, "B: Go to Vendor is a waypoint (Bags, vendor)")
    EQ(wp and wp.icon, "VENDOR", "B: ...in the vendor tint")
    EQ(wp and wp.alternatives and #wp.alternatives, 3, "B: ...with every vendor on your landmass as its choices")
    EQ(O().Active() and O().Active().uid, wp and wp.uid, "B: the arrow on it")
    local active = O().Active()
    CHECK(active and math.abs(active.x - 0.43) < 1e-9 and math.abs(active.y - 0.66) < 1e-9,
        "B: ...pointing at the nearest vendor", active and (active.x .. "," .. active.y))
    EQ(Count("Waypoint set: Nearest vendor"), 1, "B: Orders' own \"Waypoint set\" line, once, naming the list")
    EQ(wp and wp.title, "Nearest vendor", "B: the waypoint is titled with the list's words")
    for i = #M.tooltip, 1, -1 do M.tooltip[i] = nil end
    M.Hover(gv)
    local tip = table.concat(M.tooltip, "\n")
    CHECK(tip:find("Go to: Nearest vendor - Elwynn Forest 43.0, 66.0", 1, true) ~= nil,
        "B: the button's tooltip names where it goes", tip)
    EQ(Count("Commander Bags"), 0, "B: ...and none of Bags'")
    gv:Refresh()
    EQ(gv.__text, "Going to Vendor", "B: lit while the arrow goes there")
    local gr = Go("Go to Repair")
    Click(gr)
    M.Frame()
    local rp = O().R.Store():ByKey("Bags", "repair")
    CHECK(rp and rp.map == 1429 and math.abs(rp.x - 0.418) < 1e-9, "B: Go to Repair, its own waypoint at the repairer")
    gv:Refresh()
    EQ(gv.__text, "Go to Vendor", "B: the vendor button goes back to its words")
    NoErrors("B")
end)

-- ===========================================================================
Section("C", function()
    Boot()
    local slash = SlashCmdList["COMMANDERUI_BAGS"]
    slash("vendor")
    M.Frame()
    local first = O().R.Store():ByKey("Bags", "vendor")
    CHECK(first ~= nil, "C: /cb vendor makes the vendor waypoint")
    Click(Go("Go to Vendor"))
    EQ(#O().List({ source = "Bags" }), 1, "C: the button finds the same record")
    slash("repair")
    EQ(#O().List({ source = "Bags" }), 2, "C: /cb repair its own")
    NoErrors("C")
end)

-- ===========================================================================
Section("D", function()
    Boot({ book = false })
    M.ClearLog()
    Click(Go("Go to Vendor"))
    EQ(#M.prints, 1, "D: nothing to ask: ONE line", table.concat(M.prints, " / "))
    CHECK((M.prints[1] or ""):find(O().Reason("noquestie"), 1, true) ~= nil, "D: ...in Orders' words", M.prints[1])
    EQ(#O().List({ source = "Bags" }), 0, "D: ...and nothing made")
    Boot()
    CommanderOrdersDB.EnableOrders = false
    local gv = Go("Go to Vendor")
    gv:Refresh()
    CHECK(not gv:IsEnabled(), "D: Orders off: greyed")
    EQ(gv._goReason, "disabled", "D: ...with the reason")
    CommanderOrdersDB.EnableOrders = true
    NoErrors("D")
end)

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
