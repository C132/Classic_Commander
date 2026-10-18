-- Commander Oracle + the REAL Commander Orders (luajit).
--
--     /opt/homebrew/bin/luajit Commander_Oracle/Harness/oracle_orders_smoke.lua
--     ORACLE_RUNTIME=/tmp/mutant.lua luajit ...      (a mutated CommanderOracle.lua)
--
-- oracle_ui_smoke.lua section W drives the flag pips against a recording
-- stand-in for Orders. This boots the real Orders over the client mock its
-- own harnesses share (Commander_Orders/Harness/orders_mock.lua: this build's
-- map rows, the battleground maps included) and loads the Oracle's five
-- files after it, as the client does. The battleground is the mock's: the
-- instance, the area POIs, the flags, and UnitPosition answering NOTHING for
-- the player, which is the case Orders' battleground hedge (D6) exists for.
--   A  loads clean beside Orders
--   B  Arathi Basin: a pip click is ONE waypoint (Oracle, node) where the
--      map's POI puts the flag, in the PVP tint, temporary, pinned, Orders'
--      "Waypoint set" line once and none of the Oracle's; the arrow walks to
--      it with no UnitPosition (D6); another flag moves the same record
--   C  Warsong Gulch, Go to the Flag: our flag first, else theirs, else the
--      one flag; the waypoint (Oracle, flag) follows the carrier about once
--      a second and goes when the flag leaves the map
--   D  /coracle nodes in the Eye of the Storm: every place the map names,
--      each with Orders' [Go] link; a click is the Oracle's one node waypoint
--   E  outside a battleground: Go to the Flag and the list say so, ask nothing
--   F  Orders switched off: Orders' ONE refusal line, the Oracle adds none
--   G  leaving the battleground takes the Oracle's waypoints with it
--   H  the key binding and the slash words
--   I  the flag art as a FileDataID (2.5.6's map provider hands the third
--      answer straight to SetTexture): matched against the two flag
--      textures' file ids, so ours still comes first; art naming neither
--      side with two flags out is never a guess at index 1: both are listed
--      ("Flag 1", "Flag 2"), each [Go] the Oracle's flag waypoint that
--      follows that carrier; no GetFileIDFromPath at all: the same listing

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
local function NEAR(got, want, eps, label)
    CHECK(type(got) == "number" and math.abs(got - want) <= eps, label,
        "got " .. tostring(got) .. ", want " .. tostring(want))
end
local function Section(name, fn)
    local ok, err = pcall(fn)
    CHECK(ok, name .. ": ran to the end", err)
end

local SKIP = { CommanderOrdersPins = true, CommanderOrdersUI = true }

-- The battleground the mock client is in
local BGS = {
    AB = { name = "Arathi Basin", instance = 529, map = 1461 },
    WSG = { name = "Warsong Gulch", instance = 489, map = 1460 },
    EOTS = { name = "Eye of the Storm", instance = 566, map = 1956 },
}
local bg                            -- one of BGS, or nil
local pois = {}                     -- [map] = { { id, name, x, y }, ... }
local flags = {}                    -- { { x, y, art }, ... } (GetBattlefieldFlagPosition)
-- GetFileIDFromPath: the two flag textures' file ids (made-up numbers: the
-- harness only needs the lookup to agree with the art), nil = not a client API
local FILE_IDS = {
    ["Interface\\WorldStateFrame\\AllianceFlag"] = 900101,
    ["Interface\\WorldStateFrame\\HordeFlag"] = 900102,
}
local fileIDLookup = true

local function ClientStubs()
    rawset(_G, "GetInstanceInfo", function()
        if bg then return bg.name, "pvp", 0, "", 40, 0, false, bg.instance end
        return "Eastern Kingdoms", "none", 0, "", 5, 0, false, 0
    end)
    rawset(_G, "C_AreaPoiInfo", {
        GetAreaPOIForMap = function(map)
            local out = {}
            for _, p in ipairs(pois[map] or {}) do out[#out + 1] = p.id end
            return out
        end,
        GetAreaPOIInfo = function(map, id)
            for _, p in ipairs(pois[map] or {}) do
                if p.id == id then return { areaPoiID = id, name = p.name, position = { x = p.x, y = p.y } } end
            end
            return nil
        end,
    })
    rawset(_G, "GetNumBattlefieldFlagPositions", function() return #flags end)
    rawset(_G, "GetBattlefieldFlagPosition", function(i)
        local f = flags[i]
        if not f then return nil end
        return f.x, f.y, f.art
    end)
    rawset(_G, "UnitIsUnit", function(a, b) return a == b end)
    if fileIDLookup then
        rawset(_G, "GetFileIDFromPath", function(path) return FILE_IDS[path] end)
    end
end

-- No UnitPosition for the player (a battleground, Orders' D6)
local function Blind()
    local real = UnitPosition
    rawset(_G, "UnitPosition", function(unit)
        if unit == "player" then return nil end
        return real(unit)
    end)
end

local function Boot(where, opts)
    opts = opts or {}
    bg = where
    flags = {}
    local files = { "CommanderOracleData.lua", "CommanderOracleEngine.lua", "CommanderOracleRoster.lua",
        "CommanderOracleDB.lua" }
    local mutant = os.getenv("ORACLE_RUNTIME")
    if not mutant then files[#files + 1] = "CommanderOracle.lua" end
    M.Boot({
        player = opts.player or (where and { where.map, 0.40, 0.40 }) or { 1429, 0.42, 0.655 },
        faction = opts.faction or "Horde",
        skipFiles = SKIP,
        files = opts.noOrders and {} or nil,
        before = function() ClientStubs() end,
        addons = { { name = "Commander_Oracle", files = files } },
        afterFiles = function()
            if mutant then
                local chunk, err = loadfile(mutant)
                if not chunk then M.loadErrors[#M.loadErrors + 1] = tostring(err) else
                    local ok, runErr = pcall(chunk)
                    if not ok then M.loadErrors[#M.loadErrors + 1] = tostring(runErr) end
                end
            end
        end,
    })
    if where then
        M.SetInstance("pvp")
        Blind()
    end
    M.Fire("PLAYER_ENTERING_WORLD", false, false)
    M.Advance(1.5)
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
local function Oracle(key)
    return O().R.Store():ByKey("Oracle", key)
end

-- Arathi's board: every node uncontrolled, each at its own spot
local AB_AT = { { 0.373, 0.291 }, { 0.404, 0.558 }, { 0.464, 0.452 }, { 0.575, 0.309 }, { 0.560, 0.599 } }
local function ArathiPOIs()
    local list = {}
    for i, node in ipairs(CommanderOracle_AB.nodes) do
        list[#list + 1] = { id = node.poi.none, name = node.name, x = AB_AT[i][1], y = AB_AT[i][2] }
    end
    pois[1461] = list
end

-- ===========================================================================
Section("A", function()
    Boot(nil)
    NoErrors("A")
    EQ(type(CommanderOracle_GoToFlag), "function", "A: Go to the Flag is there")
    EQ(type(CommanderOracle_Nodes), "function", "A: ...and the list of places")
end)

-- ===========================================================================
Section("B", function()
    ArathiPOIs()
    Boot(BGS.AB)
    NoErrors("B: boot")
    EQ(select(2, UnitPosition("player")), nil, "B: (no UnitPosition for the player here)")
    local pips = CommanderOracle_Sections.nodes.pips
    M.ClearLog()
    pips[3].__scripts.OnMouseUp(pips[3], "LeftButton")
    M.Frame()
    local wp = Oracle("node")
    CHECK(wp ~= nil, "B: a pip click is a waypoint (Oracle, node)")
    if not wp then return end
    EQ(wp.map, 1461, "B: on the Arathi Basin map")
    NEAR(wp.x, 0.464, 1e-9, "B: where the map's POI puts the Blacksmith (x)")
    NEAR(wp.y, 0.452, 1e-9, "B: ...(y)")
    EQ(wp.title, "Blacksmith", "B: titled with the flag")
    EQ(wp.icon, "PVP", "B: in the battleground tint")
    CHECK(wp.temporary == true and wp.persistent == false, "B: temporary and session-only")
    EQ(O().Active() and O().Active().uid, wp.uid, "B: pinned: the click asked for the arrow")
    EQ(Count("Waypoint set: Blacksmith"), 1, "B: Orders' own \"Waypoint set\" line, once")
    EQ(Count("Commander Oracle"), 0, "B: ...and none of the Oracle's")
    M.Advance(0.5)
    EQ(O().R.View().mode, "NAV", "B: the arrow walks to it with no UnitPosition (Orders' D6)")
    CHECK((O().R.View().distance or 0) > 0, "B: ...with a distance", O().R.View().distance)
    pips[1].__scripts.OnMouseUp(pips[1], "LeftButton")
    M.Frame()
    local again = Oracle("node")
    EQ(again and again.uid, wp.uid, "B: another flag moves the same record")
    EQ(again and again.title, "Stables", "B: ...to the Stables")
    EQ(#O().List({ source = "Oracle" }), 1, "B: still one Oracle waypoint")
    NoErrors("B")
end)

-- ===========================================================================
Section("C", function()
    Boot(BGS.WSG)
    NoErrors("C: boot")
    -- Their flag only (our carrier has it)
    flags = { { x = 0.30, y = 0.40, art = "Interface\\WorldStateFrame\\AllianceFlag" } }
    M.ClearLog()
    local uid = CommanderOracle_GoToFlag()
    M.Frame()
    local wp = Oracle("flag")
    CHECK(wp ~= nil and wp.uid == uid, "C: Go to the Flag is a waypoint (Oracle, flag)")
    if not wp then return end
    EQ(wp.map, 1460, "C: on the Warsong Gulch map")
    EQ(wp.title, "Their flag", "C: the Alliance flag, to a Horde player, is theirs")
    NEAR(wp.x, 0.30, 1e-9, "C: where the map shows it")
    EQ(O().Active() and O().Active().uid, wp.uid, "C: pinned")
    EQ(Count("Waypoint set: Their flag"), 1, "C: Orders says Waypoint set, once")
    -- Both flags out: ours first
    flags = { { x = 0.30, y = 0.40, art = "Interface\\WorldStateFrame\\AllianceFlag" },
              { x = 0.70, y = 0.20, art = "Interface\\WorldStateFrame\\HordeFlag" } }
    CommanderOracle_GoToFlag()
    M.Frame()
    wp = Oracle("flag")
    EQ(wp and wp.title, "Our flag", "C: with both out, our own flag first (an enemy carries it)")
    NEAR(wp and wp.x, 0.70, 1e-9, "C: ...where the map shows it")
    EQ(#O().List({ source = "Oracle" }), 1, "C: one flag waypoint, moved")
    -- The carrier runs: the waypoint follows, about once a second
    flags[2].x, flags[2].y = 0.62, 0.28
    M.Advance(1.5)
    wp = Oracle("flag")
    NEAR(wp and wp.x, 0.62, 1e-9, "C: the waypoint follows the carrier (x)")
    NEAR(wp and wp.y, 0.28, 1e-9, "C: ...(y)")
    EQ(O().Active() and O().Active().uid, wp and wp.uid, "C: ...and keeps the arrow")
    -- A tiny shuffle is not worth a move
    local before = wp.x
    flags[2].x = 0.6205
    M.Advance(1.5)
    NEAR(Oracle("flag") and Oracle("flag").x, before, 1e-12, "C: a shuffle under the threshold leaves it")
    -- Captured or returned: off the map, the waypoint goes
    flags = { { x = 0.30, y = 0.40, art = "Interface\\WorldStateFrame\\AllianceFlag" } }
    flags[2] = nil
    M.Advance(1.5)
    -- index 2 is gone from the map: the followed flag left
    EQ(Oracle("flag"), nil, "C: the flag off the map takes the waypoint away")
    -- The Eye's one flag (art naming no faction)
    flags = { { x = 0.50, y = 0.50, art = "Interface\\WorldStateFrame\\NeutralFlag" } }
    CommanderOracle_GoToFlag()
    EQ(Oracle("flag") and Oracle("flag").title, "The flag", "C: a flag of no faction is \"The flag\"")
    -- No flag on the map at all
    flags = {}
    M.ClearLog()
    EQ(CommanderOracle_GoToFlag(), nil, "C: no flag on the map: nothing asked")
    CHECK(M.Has(M.prints, "no flag is on the map"), "C: ...and it says so", M.prints[1])
    NoErrors("C")
end)

-- ===========================================================================
Section("D", function()
    pois[1956] = {
        { id = 9001, name = "Mage Tower", x = 0.62, y = 0.37 },
        { id = 9002, name = "Fel Reaver Ruins", x = 0.38, y = 0.36 },
    }
    Boot(BGS.EOTS)
    flags = { { x = 0.50, y = 0.50, art = "Interface\\WorldStateFrame\\NeutralFlag" } }
    M.ClearLog()
    EQ(CommanderOracle_Nodes(), 3, "D: two places the map names, and the flag")
    local lines = {}
    for _, line in ipairs(M.prints) do lines[#lines + 1] = line end
    CHECK(lines[1] and lines[1]:find("click [Go]", 1, true) ~= nil, "D: a header saying what to do", lines[1])
    local mage
    for _, line in ipairs(lines) do
        if line:find("Mage Tower", 1, true) then mage = line end
    end
    CHECK(mage and mage:find("|h[Go]|h", 1, true) ~= nil, "D: each place with Orders' [Go] link", mage)
    M.ClearLog()
    M.ClickLink(mage)
    M.Frame()
    local wp = Oracle("node")
    CHECK(wp ~= nil, "D: a click is the Oracle's one node waypoint (its claim, not a waypoint of yours)")
    EQ(wp and wp.map, 1956, "D: on the Eye's map")
    EQ(wp and wp.title, "Mage Tower", "D: titled with the place")
    NEAR(wp and wp.x, 0.62, 1e-4, "D: at the place")
    EQ(#O().List({ source = "user" }), 0, "D: nothing of yours made")
    EQ(O().Active() and O().Active().uid, wp and wp.uid, "D: the arrow on it")
    NoErrors("D")
end)

-- ===========================================================================
Section("E", function()
    Boot(nil)
    M.ClearLog()
    EQ(CommanderOracle_GoToFlag(), nil, "E: outside a battleground, Go to the Flag asks nothing")
    CHECK(M.Has(M.prints, "inside a battleground"), "E: ...and says where it works", M.prints[1])
    M.ClearLog()
    EQ(CommanderOracle_Nodes(), 0, "E: the list asks nothing either")
    CHECK(M.Has(M.prints, "from inside one"), "E: ...and says so", M.prints[1])
    EQ(#O().List({ source = "Oracle" }), 0, "E: no Oracle waypoint")
end)

-- ===========================================================================
Section("F", function()
    ArathiPOIs()
    Boot(BGS.AB)
    CommanderOrdersDB.EnableOrders = false
    local pips = CommanderOracle_Sections.nodes.pips
    M.ClearLog()
    pips[3].__scripts.OnMouseUp(pips[3], "LeftButton")
    EQ(#M.prints, 1, "F: Orders off: ONE line", table.concat(M.prints, " / "))
    local line = M.prints[1] or ""
    CHECK(line:find(O().Reason("disabled"), 1, true) and line:find("Blacksmith", 1, true),
        "F: ...Orders' refusal, naming the flag", line)
    EQ(Count("Commander Oracle"), 0, "F: ...and none of the Oracle's")
    EQ(#O().List({ source = "Oracle" }), 0, "F: nothing made")
    CommanderOrdersDB.EnableOrders = true
    NoErrors("F")
end)

-- ===========================================================================
Section("G", function()
    Boot(BGS.WSG)
    flags = { { x = 0.30, y = 0.40, art = "Interface\\WorldStateFrame\\HordeFlag" } }
    local mine = O().Add({ map = 1460, x = 0.9, y = 0.9, title = "Mine" })
    M.Frame()
    CommanderOracle_GoToFlag()
    M.Frame()
    CHECK(Oracle("flag") ~= nil, "G: (a flag waypoint in Warsong Gulch)")
    -- The match ends: out of the battleground, past the exit grace
    bg = nil
    M.SetInstance(nil)
    M.SetPlayer(1429, 0.42, 0.655)
    flags = {}
    M.Fire("PLAYER_ENTERING_WORLD", false, false)
    M.Advance(12)
    EQ(#O().List({ source = "Oracle" }), 0, "G: leaving takes the Oracle's waypoints with it")
    CHECK(O().Get(mine) ~= nil, "G: ...and leaves yours")
    -- A place from /coracle nodes has no carrier to follow: the match's end
    -- is what takes it (and hands back the pin it took)
    pois[1956] = { { id = 9001, name = "Mage Tower", x = 0.62, y = 0.37 } }
    Boot(BGS.EOTS)
    local yours = O().Add({ map = 1956, x = 0.1, y = 0.1, title = "Yours" })
    M.Frame()
    M.ClearLog()
    CommanderOracle_Nodes()
    local line
    for _, l in ipairs(M.prints) do if l:find("Mage Tower", 1, true) then line = l end end
    M.ClickLink(line)
    M.Frame()
    CHECK(Oracle("node") ~= nil, "G: (a node waypoint in the Eye)")
    bg = nil
    M.SetInstance(nil)
    M.SetPlayer(1429, 0.42, 0.655)
    M.Fire("PLAYER_ENTERING_WORLD", false, false)
    M.Advance(12)
    EQ(Oracle("node"), nil, "G: leaving the Eye takes the node waypoint too")
    EQ(O().Active() and O().Active().uid, yours, "G: ...and the arrow goes back to the pin it took")
    NoErrors("G")
end)

-- ===========================================================================
Section("H", function()
    local f = io.open(ADDONS .. "/Commander_Oracle/Bindings.xml", "r")
    local xml = f and f:read("*a") or ""
    if f then f:close() end
    CHECK(xml:find('name="COMMANDERORACLE_FLAG"', 1, true) and xml:find("CommanderOracle_GoToFlag()", 1, true),
        "H: Bindings.xml binds Go to the Flag")
    CHECK(not xml:find("<!%-%-.-%-%-.-%-%->"), "H: no '--' inside an XML comment")
    Boot(nil)
    EQ(BINDING_NAME_COMMANDERORACLE_FLAG, "Go to the Flag", "H: the binding's words (Go to <Thing>)")
    local db = io.open(ADDONS .. "/Commander_Oracle/CommanderOracleDB.lua"):read("*a")
    CHECK(db:find("flag = function()", 1, true) and db:find("nodes = function()", 1, true),
        "H: /coracle flag and /coracle nodes")
    local src = io.open(os.getenv("ORACLE_RUNTIME") or (ADDONS .. "/Commander_Oracle/CommanderOracle.lua")):read("*a")
    CHECK(src:find("/corder to turn it on", 1, true) == nil, "H: the Oracle keeps no refusal words of its own")
    local block = src:sub(src:find("local BG = {", 1, true) or 1, src:find("local function NodeTooltip", 1, true) or 1)
    CHECK(not block:find("[\128-\255]"), "H: the battleground Go-to code is plain ASCII (D11)")
end)

-- ===========================================================================
Section("I", function()
    Boot(BGS.WSG)
    NoErrors("I: boot")
    -- The art as a FileDataID: both flags out, ours first all the same
    flags = { { x = 0.30, y = 0.40, art = 900101 }, { x = 0.70, y = 0.20, art = 900102 } }
    M.ClearLog()
    CommanderOracle_GoToFlag()
    M.Frame()
    local wp = Oracle("flag")
    EQ(wp and wp.title, "Our flag", "I: a numeric art is matched by file id: our flag first")
    NEAR(wp and wp.x, 0.70, 1e-9, "I: ...where the map shows it")
    flags = { { x = 0.30, y = 0.40, art = 900101 } }
    CommanderOracle_GoToFlag()
    EQ(Oracle("flag") and Oracle("flag").title, "Their flag", "I: the Alliance flag's file id, to a Horde player, is theirs")
    flags = { { x = 0.30, y = 0.40, art = "900102" } }
    CommanderOracle_GoToFlag()
    EQ(Oracle("flag") and Oracle("flag").title, "Our flag", "I: a file id as a string reads the same")
    O().RemoveBy("Oracle")
    M.Frame()

    -- Art naming neither side, two flags out: never index 1 on a guess
    flags = { { x = 0.30, y = 0.40, art = 123 }, { x = 0.70, y = 0.20, art = 456 } }
    M.ClearLog()
    EQ(CommanderOracle_GoToFlag(), nil, "I: whose flag is whose unknown: nothing asked")
    EQ(#O().List({ source = "Oracle" }), 0, "I: ...no flag waypoint on a guess")
    CHECK(M.Has(M.prints, "does not say whose flag is whose"), "I: ...it says so", M.prints[1])
    local one, two
    for _, line in ipairs(M.prints) do
        if line:find("Flag 1 ", 1, true) then one = line end
        if line:find("Flag 2 ", 1, true) then two = line end
    end
    CHECK(one and one:find("|h[Go]|h", 1, true), "I: ...and lists Flag 1 with a [Go]", one)
    CHECK(two and two:find("|h[Go]|h", 1, true), "I: ...and Flag 2 with a [Go]", two)
    EQ(Count("Waypoint set"), 0, "I: ...and sets nothing")
    -- The carrier of Flag 2 has run since the list was printed
    flags[2].x, flags[2].y = 0.66, 0.25
    M.ClearLog()
    M.ClickLink(two)
    M.Frame()
    wp = Oracle("flag")
    CHECK(wp ~= nil, "I: Flag 2's [Go] is the Oracle's flag waypoint (its claim, not one of yours)")
    EQ(#O().List({ source = "user" }), 0, "I: ...nothing of yours made")
    EQ(wp and wp.title, "Flag 2", "I: ...titled Flag 2")
    NEAR(wp and wp.x, 0.66, 1e-9, "I: ...where the flag is NOW (x)")
    EQ(O().Active() and O().Active().uid, wp and wp.uid, "I: ...with the arrow on it")
    flags[2].x, flags[2].y = 0.60, 0.30
    M.Advance(1.5)
    NEAR(Oracle("flag") and Oracle("flag").x, 0.60, 1e-9, "I: ...and it follows that carrier")
    -- /coracle nodes: two flags that read differently
    pois[1460] = {}
    M.ClearLog()
    EQ(CommanderOracle_Nodes(), 2, "I: /coracle nodes lists both flags")
    CHECK(M.Has(M.prints, "  Flag 1 ") and M.Has(M.prints, "  Flag 2 "), "I: ...as Flag 1 and Flag 2, never two alike",
        table.concat(M.prints, " / "))
    -- A flag gone from the map by the time its [Go] is clicked
    flags = { { x = 0.30, y = 0.40, art = 123 }, { x = 0.70, y = 0.20, art = 456 } }
    O().RemoveBy("Oracle")
    M.ClearLog()
    CommanderOracle_GoToFlag()
    for _, line in ipairs(M.prints) do
        if line:find("Flag 2 ", 1, true) then two = line end
    end
    flags[2] = nil
    M.ClearLog()
    M.ClickLink(two)
    EQ(Oracle("flag"), nil, "I: a flag gone from the map: no waypoint from its old [Go]")
    CHECK(M.Has(M.prints, "no longer on the map"), "I: ...and it says so", M.prints[1])
    -- One flag of no known side is still simply the flag
    flags = { { x = 0.50, y = 0.50, art = 789 } }
    CommanderOracle_GoToFlag()
    EQ(Oracle("flag") and Oracle("flag").title, "The flag", "I: one flag of no known side is \"The flag\"")
    NoErrors("I")

    -- No GetFileIDFromPath in the client: a numeric art names no side, and
    -- two flags are listed rather than guessed
    fileIDLookup = false
    Boot(BGS.WSG)
    fileIDLookup = true
    EQ(rawget(_G, "GetFileIDFromPath"), nil, "I: (no GetFileIDFromPath)")
    flags = { { x = 0.30, y = 0.40, art = 900101 }, { x = 0.70, y = 0.20, art = 900102 } }
    M.ClearLog()
    EQ(CommanderOracle_GoToFlag(), nil, "I: without the file-id lookup: nothing guessed")
    CHECK(M.Has(M.prints, "does not say whose flag is whose"), "I: ...the two flags listed", M.prints[1])
    NoErrors("I: no lookup")
end)

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
