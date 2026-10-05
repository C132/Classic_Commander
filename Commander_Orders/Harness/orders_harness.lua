-- Commander Orders: the runtime harness (luajit).
--
--     luajit Commander_Orders/Harness/orders_harness.lua
--     ORDERS_RUNTIME=/tmp/mutant.lua luajit Commander_Orders/Harness/orders_harness.lua
--
-- The geometry and the model have pure harnesses of their own. This one
-- drives the RUNTIME end to end over orders_mock.lua: a WoW client whose map
-- world is this build's DB2 rows, with the REAL settings framework and HUD
-- chrome loaded (Commander_Events), and every Orders file loaded in TOC order
-- (the pins and the manager are left out here; their harnesses load them).
-- Each section boots a fresh client, so nothing leaks from one into the next.
--
--   A  boot: quiet login, the public API, the globals written, TOC, bindings,
--      defaults, the arrow built and chromed out of combat, asleep with nothing
--   B  the D1 regression through the real UnitPosition axis order (Goldshire
--      to Northshire: 582 yd at 339 deg, not 12,952), colours, turn around,
--      smoothing, every-frame rotation, the ETA, text written only on change
--   C  arrival: NEAR pulse, ARRIVED (ring, text, one chime), DONE clears,
--      in flight never arrives, /wayb never clears under your feet
--   D  states: OTHER LANDMASS with its hints and Guide me, the 530 traps,
--      dungeon targets and entrances, NO POSITION, no heading, group members,
--      the auto-hide options, combat layout unchanged by default
--   E  the mouse: click-through when locked, the modifier, the menu, unlock,
--      a login in combat that waits to chrome
--   F  the API: refusals while disabled, nil-safety, copies, defaults, the
--      CHANGED event debounced, continent clicks become zone positions
--   G  the legacy wrappers: IssueOrder, ClearOrder, Rally*
--   H  the TomTom shim: install rules, Questie's exact call patterns incl. a
--      stale uid after a reload, WhatsTraining, callbacks, tier 2, refusals
--   I  /way end to end, /wayb, /cway, /corder way with its case kept
--   J  sharing: send, channels, results, receive, prompt, self-echo,
--      auto-add, throttle, TomTom's prefix, garbage
--   K  the v2 -> v3 migration; Restore Defaults keeps places
--   L  persistence across a simulated reload
--   M  the corpse run: release, reload as a ghost, resurrection, Feign Death,
--      battlegrounds, dungeon deaths, arrival
--   N  the settings page on the real framework
--   O  the driver sleeps; places, paste/export, routes, bindings
--   P  every TOC file that exists loads with the runtime (Pins, UI when present)
--   Q  what the consumers asked for: Entrance (a copy, resolvers first),
--      Status (the arrow's own words), SharePoint (shared, never added or
--      pinned; one send path with Share), OpenPaste(text); and the arrow's
--      distance font on a client without GameFontNormalLargeOutline
--   R  the review's fixes: the shim never removes what it does not own
--      (either order) and finds a continent uid after a reload; received
--      titles lose their UI escapes; every dialog over the maximized map;
--      shares added quietly stay behind your own waypoints; Mark arrived on
--      a kept mark; temporary offers and a running route; Guide me hands
--      back on any crossing; a unit follow allocates no map positions; the
--      status line wraps; a closed window stays closed; readouts at the
--      chosen spawn; paste errors by the box's own line numbers

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local M = dofile(HERE .. "/orders_mock.lua")
local ADDONS = M.ADDONS
local P = M.realPrint

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
        "got " .. tostring(got) .. ", want " .. tostring(want) .. " +- " .. tostring(eps))
end
local function HAS(s, needle, label)
    CHECK(type(s) == "string" and s:find(needle, 1, true) ~= nil, label, "got " .. tostring(s))
end
local function NOERR(label)
    CHECK(#M.errors == 0, label .. ": no errors", M.errors[1])
    CHECK(#M.loadErrors == 0, label .. ": no load errors", M.loadErrors[1])
end

local PI = math.pi
local function Norm(a)
    a = a % (2 * PI)
    if a > PI then a = a - 2 * PI end
    return a
end

local SKIP = { CommanderOrdersPins = true, CommanderOrdersUI = true }
local function Boot(opts)
    opts = opts or {}
    if opts.skipFiles == nil then opts.skipFiles = SKIP end
    return M.Boot(opts)
end
local function Reload(opts)
    opts = opts or {}
    if opts.skipFiles == nil then opts.skipFiles = SKIP end
    return M.Reload(opts)
end

local function O() return CommanderOrders end
local function R() return CommanderOrders.R end
local function A() return CommanderOrders.R.ArrowState() end
local function Store() return CommanderOrders.R.Store() end
local function DB() return CommanderOrdersDB end
local function Notify() Commander.Notify(COMMANDER_ORDERS_EVENTS.UPDATE) end
local function Way(msg) SlashCmdList.COMMANDERORDERS_WAY(msg) end
local function Corder(msg) SlashCmdList.COMMANDERUI_ORDERS(msg) end
local function Text(key) return A().text[key] end
local function Pass(n) M.Advance((n or 1) * 0.1 + 0.02) end

-- The player's world point and the straight line to another
local function WorldOf(map, x, y) return M.World(map, x, y) end
local function Teleport(map, x, y) M.SetPlayer(map, x, y) end
-- Stand `yards` short of a world point, on the line from where you are
local function StandShort(n2, w2, yards)
    local p = M.W.player
    local dn, dw = n2 - p.north, w2 - p.west
    local d = math.sqrt(dn * dn + dw * dw)
    local k = (d - yards) / d
    M.SetPlayerWorld(p.inst, p.north + dn * k, p.west + dw * k)
end
local function Walk(n2, w2, speed, seconds)
    M.SetSpeed(speed)
    for _ = 1, math.floor(seconds * 30 + 0.5) do
        local p = M.W.player
        local dn, dw = n2 - p.north, w2 - p.west
        local d = math.sqrt(dn * dn + dw * dw)
        local step = speed / 30
        if d <= step then
            M.SetPlayerWorld(p.inst, n2, w2)
        else
            M.SetPlayerWorld(p.inst, p.north + dn / d * step, p.west + dw / d * step)
        end
        M.Frame(1 / 30)
    end
    M.SetSpeed(0)
end

local function CountSounds(id)
    local n = 0
    for _, s in ipairs(M.sounds) do if s.id == id then n = n + 1 end end
    return n
end

local function Section(name, fn)
    local ok, err = pcall(fn)
    CHECK(ok, name .. ": ran to the end", err)
end

local GOLDSHIRE = { 1429, 0.42, 0.655 }
local NORTHSHIRE = { 1429, 0.48, 0.42 }

-- ===========================================================================
-- A: boot
-- ===========================================================================
Section("A", function()
    local W = Boot()
    NOERR("A login")
    EQ(#M.prints, 0, "A: a quiet login (no chat lines)")
    local o = O()
    for _, name in ipairs({ "Add", "AddRoute", "Remove", "RemoveBy", "Clear", "SetArrow", "ClearArrow", "Get",
            "List", "Distance", "Active", "IsAvailable", "Describe", "Here", "Share", "WayLine",
            "RegisterResolver", "OpenManager", "OpenPaste", "Command", "Binding", "MarkPlace", "GoPlace",
            "Places", "Import", "Export", "Routes", "RouteNext", "RoutePrev", "Update", "Guide",
            "CorpseArrow", "SetCorpseArrow", "MarkArrived", "ToggleManager" }) do
        EQ(type(o[name]), "function", "A: CommanderOrders." .. name)
    end
    for _, name in ipairs({ "CommanderOrders_IssueOrder", "CommanderOrders_ClearOrder", "CommanderOrders_RallySet",
            "CommanderOrders_RallyGo", "CommanderOrders_RallyList" }) do
        EQ(type(_G[name]), "function", "A: legacy " .. name)
    end
    EQ(type(o.Geo), "table", "A: O.Geo")
    EQ(type(o.Store), "table", "A: O.Store")
    EQ(type(o.Data), "table", "A: O.Data")
    EQ(type(o.R), "table", "A: O.R for the pins and the manager")
    EQ(COMMANDER_ORDERS_EVENTS.UPDATE, "COMMANDER_ORDERS_UPDATE", "A: the settings event")
    EQ(COMMANDER_ORDERS_EVENTS.CHANGED, "COMMANDER_ORDERS_CHANGED", "A: the CHANGED event")
    EQ(o.Describe(), "Commander Orders arrow", "A: Describe")
    local ok = o.IsAvailable()
    EQ(ok, true, "A: available after login")

    -- Globals: only the documented ones
    local allowed = {
        CommanderOrders = true, CommanderOrdersDB = true, CommanderOrdersChar = true, COMMANDER_ORDERS_EVENTS = true,
        CommanderOrders_IssueOrder = true, CommanderOrders_ClearOrder = true, CommanderOrders_RallySet = true,
        CommanderOrders_RallyGo = true, CommanderOrders_RallyList = true, CommanderOrdersArrow = true,
        CommanderOrdersMenu = true, TomTom = true, BINDING_HEADER_COMMANDERORDERS = true,
        SLASH_COMMANDERUI_ORDERS1 = true, CommanderUIScrollOrders = true,
    }
    local bad = {}
    for _, name in ipairs(M.OrdersWrites()) do
        local ok2 = allowed[name] or name:match("^BINDING_NAME_COMMANDERORDERS_%u+$")
            or name:match("^SLASH_COMMANDERORDERS_%u+%d$") or name:match("^CommanderUIDropDown%d+$")
        if not ok2 then bad[#bad + 1] = name end
    end
    EQ(#bad, 0, "A: no undocumented global written", table.concat(bad, " "))
    EQ(rawget(_G, "TomTom"), o.TomTomShim, "A: the shim is installed (no TomTom loaded)")

    -- TOC
    local toc = io.open(ADDONS .. "/Commander_Orders/Commander_Orders.toc"):read("*a")
    HAS(toc, "## Version: 3.0.0", "A: TOC version 3.0.0")
    HAS(toc, "## SavedVariables: CommanderOrdersDB", "A: TOC account SV")
    HAS(toc, "## SavedVariablesPerCharacter: CommanderOrdersChar", "A: TOC per-character SV")
    HAS(toc, "## RequiredDeps: Commander_Events", "A: TOC requires the hub")
    HAS(toc, "## OptionalDeps: TomTom, Commander_Console", "A: TOC optional deps")
    local files = M.TocFiles()
    EQ(table.concat(files, ","), "CommanderOrdersData,CommanderOrdersGeo,CommanderOrdersStore,CommanderOrdersDB,"
        .. "CommanderOrders,CommanderOrdersPins,CommanderOrdersUI", "A: TOC load order")
    CHECK(not toc:find("Bindings.xml", 1, true), "A: Bindings.xml is not in the TOC")
    -- Bindings
    local xml = io.open(ADDONS .. "/Commander_Orders/Bindings.xml"):read("*a")
    local n = 0
    for name, body in xml:gmatch('<Binding name="([%w_]+)"[^>]*>%s*(.-)%s*</Binding>') do
        n = n + 1
        CHECK(type(_G["BINDING_NAME_" .. name]) == "string", "A: binding name string for " .. name)
        local action = body:match('^CommanderOrders%.Binding%("(%u+)"%)$')
        CHECK(action ~= nil, "A: binding body calls CommanderOrders.Binding: " .. name, body)
    end
    EQ(n, 8, "A: eight key bindings")
    HAS(xml, 'header="COMMANDERORDERS"', "A: bindings header")
    EQ(BINDING_HEADER_COMMANDERORDERS, "Commander Orders", "A: header text")
    for comment in xml:gmatch("<!%-%-(.-)%-%->") do
        CHECK(not comment:find("--", 1, true), "A: no -- inside an XML comment")
    end

    -- Defaults
    local db = DB()
    EQ(db.DBVersion, 3, "A: DBVersion 3 on a fresh install")
    EQ(db.EnableOrders, true, "A: EnableOrders default")
    EQ(db.ArrowStyle, "NONE", "A: the arrow floats (style NONE)")
    EQ(db.ArrowLocked, true, "A: locked by default")
    EQ(db.Units, "AUTO", "A: Units AUTO")
    EQ(db.HideNoTarget, true, "A: HideNoTarget on")
    EQ(db.HideInCombat, false, "A: HideInCombat off")
    EQ(db.MapClickModifier, "CTRL", "A: map click Ctrl")
    EQ(db.ShareAccept, "ASK", "A: shares ask")
    EQ(db.TomTomShim, true, "A: shim on")
    EQ(type(db.Places), "table", "A: Places table")
    EQ(type(db.PastePages), "table", "A: PastePages table")
    EQ(type(CommanderOrdersChar), "table", "A: per-character table")

    -- The arrow, built and chromed at login, out of combat
    local a = A()
    EQ(a.built, true, "A: arrow built at login")
    EQ(a.chromeReady, true, "A: chrome applied at login")
    local root = _G.CommanderOrdersArrow
    EQ(root, a.root, "A: the arrow root is CommanderOrdersArrow")
    local p = root.__points and root.__points[#root.__points]
    CHECK(p and p.point == "TOP" and p.relPoint == "TOP" and p.x == 240 and p.y == -340,
        "A: default point TOP 240 -340", p and (p.point .. " " .. p.x .. " " .. p.y))
    -- the top-centre band (about 110..330 px from the top) is the suite's
    -- toasts, Momentum's plate, the zone text and the raid warnings: the
    -- arrow's whole box sits under it (review: render; 3.0 used -140)
    local AR = CommanderOrders.Data.ARROW
    CHECK(AR.DEFAULT_POINT.point == "TOP" and -AR.DEFAULT_POINT.y >= 330,
        "A: the arrow's default box starts under the top-centre toast band", AR.DEFAULT_POINT.y)
    CHECK(root.__passThrough and root.__passThrough[1] == "LeftButton", "A: the chrome's pass-through ran (out of combat)")
    EQ(#M.blocked, 0, "A: no protected call refused")
    EQ(root.__mouse, false, "A: locked root is click-through")
    EQ(a.hit.__mouse, false, "A: the hit surface is off without the modifier")
    EQ(root.__shown, false, "A: hidden with nothing to point at")
    EQ(a.arrow.__texture, "Interface\\AddOns\\Commander_Orders\\Textures\\Arrow.png", "A: our own arrow art")
    EQ(a.shadow.__texture, "Interface\\AddOns\\Commander_Orders\\Textures\\ArrowShadow.png", "A: shadow art")
    CHECK(a.shadow.__vertex and a.shadow.__vertex[1] == 0 and a.shadow.__alpha == 0.6, "A: the shadow is tinted black at 0.6")
    local sp = a.shadow.__points[1]
    CHECK(sp.x == 1 and sp.y == -2, "A: the shadow offset is in screen space (+1, -2)")
    M.Advance(0.5)
    EQ(R().Driver().__shown, false, "A: the driver sleeps with no waypoint")
    NOERR("A end")
end)

-- ===========================================================================
-- B: the D1 regression and navigation
-- ===========================================================================
Section("B", function()
    Boot({ player = GOLDSHIRE })
    M.SetFacing(0)
    Way("#1429 48 42 Northshire")
    Pass(2)
    local a = A()
    local pi_, pn, pw = WorldOf(GOLDSHIRE[1], GOLDSHIRE[2], GOLDSHIRE[3])
    local ti, tn, tw = WorldOf(NORTHSHIRE[1], NORTHSHIRE[2], NORTHSHIRE[3])
    local truth = math.sqrt((tn - pn) ^ 2 + (tw - pw) ^ 2)
    local bearing = math.atan2(tw - pw, tn - pn) % (2 * PI)
    NEAR(truth, 582.4, 1, "B: the walk is ~582 yd")
    NEAR(bearing * 180 / PI, 339.0, 0.5, "B: at ~339 degrees")
    -- what the old pairing (UnitPosition's first return as "y") would read
    local wrong = math.sqrt((tn - pw) ^ 2 + (tw - pn) ^ 2)
    CHECK(wrong > 10000, "B: the transposed pairing would be thousands of yards", wrong)
    EQ(Text("dist"), "582 yd", "B: the arrow reads 582 yd (D1 fixed)")
    EQ(Text("title"), "Northshire", "B: title")
    local wp = O().Active()
    NEAR(O().Distance(wp.uid), truth, 0.5, "B: API Distance matches")
    NEAR(a.arrow.__rotation, Norm(bearing), 0.01, "B: rotation = bearing - facing (facing 0)")
    NEAR(a.shadow.__rotation, a.arrow.__rotation, 1e-9, "B: the shadow turns with the arrow")
    EQ(a.view.mode, "NAV", "B: navigating")
    EQ(_G.CommanderOrdersArrow.__shown, true, "B: the arrow is shown")
    local c = a.arrow.__vertex
    CHECK(c and c[1] < 0.5 and c[2] > 0.9, "B: mostly on course is green", c and (c[1] .. "," .. c[2]))
    EQ(CountSounds(3175), 1, "B: MAP_PING when the waypoint was set")
    CHECK(M.Has(M.prints, "waypoint set: Northshire (Elwynn Forest 48.0, 42.0)"), "B: a short announce line", M.prints[1])

    -- Facing the target: dead ahead, the distinct tint
    M.SetFacing(bearing)
    M.Frame(1 / 30)
    M.Advance(1)
    NEAR(a.arrow.__rotation, 0, 0.01, "B: facing it, the arrow points up")
    c = a.arrow.__vertex
    local AHEAD = CommanderOrders.Data.PALETTE.AHEAD
    CHECK(c and math.abs(c[1] - AHEAD[1]) < 0.01 and math.abs(c[3] - AHEAD[3]) < 0.01, "B: dead ahead has its own tint")

    -- Behind: turn around
    M.SetFacing(bearing + PI)
    M.Advance(1.2)
    EQ(Text("status"), "Turn around", "B: TURN AROUND")
    NEAR(math.abs(a.arrow.__rotation), PI, 0.02, "B: the arrow points back")
    c = a.arrow.__vertex
    CHECK(c and c[1] > 0.95 and c[2] < 0.35, "B: behind is red")

    -- Square to the side: yellow
    M.SetFacing(bearing + PI / 2)
    M.Advance(1.2)
    c = a.arrow.__vertex
    CHECK(c and c[1] > 0.95 and c[2] > 0.8, "B: square to the side is yellow")
    EQ(Text("status"), "", "B: no turn-around at 90 degrees")

    -- Smoothing: a 90 degree snap of the facing eases in
    M.SetFacing(bearing)
    M.Advance(1)
    M.SetFacing(bearing - PI / 2)
    M.Frame(1 / 30)
    local first = a.arrow.__rotation
    CHECK(first > 0.05 and first < 1.0, "B: smoothed: one frame later the arrow is on its way", first)
    M.Advance(1)
    NEAR(a.arrow.__rotation, PI / 2, 0.01, "B: and settles within a second")
    -- Every frame, not 10 Hz
    M.SetFacing(bearing)
    M.Frame(1 / 60)
    local r1 = a.arrow.__rotation
    M.Frame(1 / 60)
    CHECK(a.arrow.__rotation ~= r1, "B: the arrow turns on every frame")
    -- Smoothing off: snaps
    DB().SmoothArrow = false
    Notify()
    M.SetFacing(bearing + 1.0)
    M.Frame(1 / 60)
    NEAR(a.arrow.__rotation, -1.0, 1e-6, "B: SmoothArrow off snaps")
    DB().SmoothArrow = true
    Notify()

    -- Text is written only when it changes
    M.SetFacing(bearing)
    M.Advance(0.5)
    local calls = 0
    local dist = a.dist
    local orig = dist.SetText
    dist.SetText = function(s, t) calls = calls + 1; return orig(s, t) end
    M.Advance(2)
    EQ(calls, 0, "B: standing still, the distance text is not rewritten")
    dist.SetText = orig

    -- The ETA, from the player's own speed, while walking at it
    Walk(tn, tw, 7, 3)
    local eta = Text("eta")
    local m, s = (eta or ""):match("^(%d+)m (%d+)s$")
    local secs = m and (tonumber(m) * 60 + tonumber(s))
    local left = math.sqrt((tn - M.W.player.north) ^ 2 + (tw - M.W.player.west) ^ 2)
    CHECK(secs and math.abs(secs - left / 7) < 4, "B: ETA ~ distance / speed", eta .. " vs " .. tostring(left / 7))
    M.Advance(2)
    EQ(Text("eta"), "", "B: standing still, no ETA")
    DB().ShowEta = false
    Notify()
    Walk(tn, tw, 7, 1)
    EQ(Text("eta"), "", "B: ShowEta off")
    DB().ShowEta = true
    Notify()
    -- Units
    DB().Units = "METRES"
    Notify()
    Pass(2)
    CHECK(Text("dist"):match("^%d+ m$"), "B: metres", Text("dist"))
    DB().Units = "AUTO"
    Notify()
    NOERR("B")
end)

-- ===========================================================================
-- C: arrival
-- ===========================================================================
Section("C", function()
    Boot({ player = GOLDSHIRE })
    local changed = 0
    Commander.AddListener(COMMANDER_ORDERS_EVENTS.CHANGED, function() changed = changed + 1 end)
    local uid = O().Add({ map = 1429, x = 0.48, y = 0.42, title = "Northshire" })
    Pass(2)
    local a = A()
    local _, tn, tw = WorldOf(1429, 0.48, 0.42)
    StandShort(tn, tw, 25)
    Pass(2)
    EQ(a.view.near, true, "C: NEAR within 3x the radius")
    EQ(a.ring.__shown, true, "C: the ring pulses")
    local alpha1 = a.ring.__alpha
    M.Advance(0.4)
    CHECK(a.ring.__alpha ~= alpha1, "C: the pulse moves")
    StandShort(tn, tw, 50)
    Pass(2)
    EQ(a.view.near, false, "C: back out beyond 3.3x: navigating")
    EQ(a.ring.__shown, false, "C: no ring")
    -- In flight: over the mark on a taxi is not reaching it
    M.SetTaxi(true)
    StandShort(tn, tw, 2)
    Pass(5)
    EQ(Text("status"), "In flight", "C: IN FLIGHT")
    EQ(Text("eta"), "", "C: no ETA on a taxi")
    CHECK(O().Get(uid) ~= nil, "C: no arrival while flying")
    EQ(CountSounds(878), 0, "C: no chime in flight")
    StandShort(tn, tw, 300)
    Walk(tn, tw, 30, 2)
    EQ(Text("eta"), "", "C: no ETA on a taxi even when moving fast")
    M.SetTaxi(false)
    StandShort(tn, tw, 60)
    Pass(2)
    StandShort(tn, tw, 5)
    Pass(2)
    EQ(a.view.mode, "ARRIVED", "C: ARRIVED")
    EQ(Text("dist"), "Arrived", "C: says Arrived")
    EQ(a.arrived.__shown, true, "C: the arrived art")
    EQ(a.arrow.__shown, false, "C: the arrow gives way to it")
    EQ(CountSounds(878), 1, "C: one arrival chime (a different sound from set)")
    CHECK(O().Get(uid) ~= nil, "C: held for a moment")
    M.Advance(3)
    EQ(O().Get(uid), nil, "C: then cleared")
    EQ(CountSounds(878), 1, "C: still one chime")
    CHECK(changed > 0, "C: CHANGED fired")
    EQ(_G.CommanderOrdersArrow.__shown, false, "C: nothing left: hidden")
    -- /wayb at your feet must not clear itself
    SlashCmdList.COMMANDERORDERS_WAYBACK("Camp")
    M.Advance(4)
    local here = O().List({ source = "user" })
    EQ(#here, 1, "C: /wayb Camp is still there after standing on it")
    EQ(here[1] and here[1].title, "Camp", "C: with its title, case kept")
    NOERR("C")
end)

-- ===========================================================================
-- D: states
-- ===========================================================================
Section("D", function()
    -- The 530 trap: Eversong to Hellfire, same instance, other landmass
    Boot({ player = { 1941, 0.5, 0.5 } })
    O().Add({ map = 1944, x = 0.5, y = 0.5, title = "Thrallmar" })
    Pass(2)
    local a = A()
    EQ(a.view.mode, "OTHER", "D: Eversong -> Hellfire is OTHER LANDMASS (both instance 530)")
    EQ(Text("dist"), "In Outland", "D: says where")
    EQ(Text("status"), "via the Orb of Translocation in Silvermoon City", "D: the Horde way out of Quel'Thalas")
    EQ(a.arrow.__shown, false, "D: no fake arrow")
    CHECK(not (Text("dist") or ""):find("yd"), "D: never a straight-line distance across the Nether")

    Boot({ player = { 1941, 0.5, 0.5 }, faction = "Alliance" })
    O().Add({ map = 1944, x = 0.5, y = 0.5, title = "Honor Hold" })
    Pass(2)
    EQ(Text("status"), "via the Thalassian Pass, south of the Ghostlands", "D: Alliance has the pass")
    M.SetModifier("SHIFT", true)
    M.Click(A().hit, "RightButton")
    local texts = table.concat(M.MenuTexts(), "|")
    CHECK(not texts:find("Guide me", 1, true), "D: a text-only connection offers no Guide me", texts)
    M.SetModifier("SHIFT", false)

    -- Ghostlands (530) to the Plaguelands (0): one continent, two frames
    Boot({ player = { 1942, 0.5, 0.5 } })
    O().Add({ map = 1423, x = 0.5, y = 0.5, title = "Light's Hope" })
    Pass(2)
    EQ(A().view.mode, "OTHER", "D: Ghostlands -> EPL is OTHER (530 vs 0)")
    EQ(Text("dist"), "In the Eastern Kingdoms", "D: named")

    -- Durotar to Outland: the first hop of two
    Boot({ player = { 1411, 0.5, 0.5 } })
    O().Add({ map = 1944, x = 0.5, y = 0.5 })
    Pass(2)
    EQ(Text("status"), "via the zeppelin tower outside Orgrimmar", "D: Kalimdor -> Outland starts at the zeppelin")

    -- Blasted Lands: Guide me pins the portal, and hands back the target
    Boot({ player = { 1419, 0.5, 0.5 } })
    local target = O().Add({ map = 1944, x = 0.5, y = 0.5, title = "Thrallmar" })
    Pass(2)
    EQ(Text("status"), "via the Dark Portal in the Blasted Lands", "D: EK -> Outland via the Dark Portal")
    M.SetModifier("SHIFT", true)
    M.Click(A().hit, "RightButton")
    CHECK(M.ClickMenu("Guide me: the Dark Portal in the Blasted Lands"), "D: the menu offers Guide me",
        table.concat(M.MenuTexts(), "|"))
    M.SetModifier("SHIFT", false)
    Pass(2)
    local guide = O().Active()
    CHECK(guide and guide.map == 1419 and math.abs(guide.x - 0.5821) < 1e-6, "D: Guide me pins the portal spot")
    EQ(guide and guide.title, "To Outland", "D: titled for where it leads")
    EQ(A().view.mode, "NAV", "D: and the arrow points at it")
    local _, gn, gw = WorldOf(1419, 0.5821, 0.5595)
    StandShort(gn, gw, 3)
    M.Advance(3.5)
    EQ(Store():Pinned() and Store():Pinned().uid, target, "D: arriving at the portal hands the arrow back")

    -- A dungeon target: inside another instance
    Boot({ player = { 1944, 0.45, 0.55 } })
    O().Add({ map = 347, x = 0.5, y = 0.5, title = "Ramparts quest" })
    Pass(2)
    EQ(A().view.mode, "OTHER", "D: a dungeon map is its own landmass")
    EQ(Text("dist"), "In Hellfire Ramparts", "D: named by the dungeon")
    EQ(Text("status"), "No known way there", "D: honest with no entrance known")
    O().RegisterResolver("entrance", function(map)
        if map == 347 then return { map = 1944, x = 0.477, y = 0.536, title = "Ramparts" } end
    end)
    Pass(2)
    EQ(Text("status"), "via the entrance of Hellfire Ramparts", "D: a registered entrance resolver")
    CHECK(O().Guide() ~= nil, "D: Guide me to the entrance")
    local e = O().Active()
    CHECK(e and e.map == 1944 and math.abs(e.x - 0.477) < 1e-9, "D: pinned at the entrance")
    -- the client's own entrance list, when it has one
    Boot({ player = { 1944, 0.45, 0.55 }, entrances = {} })
    M.SetEntrances(1944, { { name = "Hellfire Ramparts", position = CreateVector2D(0.47, 0.53), areaPoiID = 1 } })
    O().Add({ map = 347, x = 0.5, y = 0.5 })
    Pass(2)
    EQ(Text("status"), "via the entrance of Hellfire Ramparts", "D: C_EncounterJournal entrances as a fallback")

    -- NO POSITION
    Boot({ player = GOLDSHIRE })
    O().Add({ map = 1429, x = 0.48, y = 0.42 })
    M.SetNoPosition(true)
    Pass(2)
    EQ(A().view.mode, "NOPOS", "D: NO POSITION")
    EQ(Text("dist"), "No position here", "D: says so")
    EQ(Text("status"), "No position inside instances", "D: and why")
    EQ(A().arrow.__shown, false, "D: no arrow")
    EQ(_G.CommanderOrdersArrow.__shown, true, "D: but still shown (HideInInstances off)")
    M.SetInstance("party")
    DB().HideInInstances = true
    Notify()
    EQ(_G.CommanderOrdersArrow.__shown, false, "D: HideInInstances hides it")
    DB().HideInInstances = false
    Notify()
    M.SetInstance(nil)
    M.SetNoPosition(false)
    Pass(2)
    EQ(A().view.mode, "NAV", "D: back to navigating")
    -- No heading: never a fake north
    M.SetFacing(nil)
    Pass(2)
    EQ(Text("status"), "No heading", "D: no heading")
    EQ(A().arrow.__shown, false, "D: no arrow without a heading")
    M.SetFacing(0)
    Pass(2)
    EQ(A().arrow.__shown, true, "D: heading back, arrow back")

    -- A group member
    Boot({ player = GOLDSHIRE })
    M.SetGroup("party", { "Tank" })
    local uid, err = O().Add({ kind = "unit", unit = "party1" })
    CHECK(uid ~= nil, "D: a unit follow", err)
    local bad, why = O().Add({ kind = "unit", unit = "target" })
    CHECK(bad == nil and why == "invalid unit", "D: only group units can be followed", why)
    Pass(2)
    EQ(A().view.mode, "UNIT_LOST", "D: member not visible")
    EQ(Text("status"), "Party member not visible", "D: says so")
    EQ(Text("title"), "Tank", "D: titled by the member's name")
    M.SetUnit("party1", 1429, 0.45, 0.6)
    Pass(2)
    EQ(A().view.mode, "NAV", "D: member visible: navigating")
    CHECK((Text("dist") or ""):match("^%d+ yd$"), "D: with a distance", Text("dist"))

    -- Auto-hide and the combat layout
    Boot({ player = GOLDSHIRE })
    O().Add({ map = 1429, x = 0.48, y = 0.42 })
    Pass(2)
    local root = _G.CommanderOrdersArrow
    local before = root.__points[#root.__points]
    M.SetCombat(true)
    Pass(2)
    EQ(root.__shown, true, "D: in combat by default: still shown")
    local during = root.__points[#root.__points]
    CHECK(before.point == during.point and before.x == during.x and before.y == during.y,
        "D: combat layout unchanged by default")
    DB().HideInCombat = true
    Notify()
    EQ(root.__shown, false, "D: HideInCombat hides it in combat")
    M.SetCombat(false)
    EQ(root.__shown, true, "D: and back after")
    DB().HideInCombat = false
    DB().HideWithMap = true
    Notify()
    M.ShowMap(1429)
    EQ(root.__shown, false, "D: HideWithMap with the map open")
    M.HideMap()
    EQ(root.__shown, true, "D: map closed, arrow back")
    DB().HideWithMap = false
    DB().HideNoTarget = false
    Notify()
    O().Clear()
    Pass(2)
    EQ(root.__shown, true, "D: HideNoTarget off: shown with nothing")
    EQ(Text("dist"), "No waypoint", "D: saying so")
    NOERR("D")
end)

-- ===========================================================================
-- E: the mouse
-- ===========================================================================
Section("E", function()
    Boot({ player = GOLDSHIRE })
    local opened = {}
    CommanderOrders.UI = { Open = function(uid) opened[#opened + 1] = uid or "nil" end }
    local uid = O().Add({ map = 1429, x = 0.48, y = 0.42, title = "Northshire" })
    Pass(2)
    local a = A()
    local root = _G.CommanderOrdersArrow
    EQ(root.__mouse, false, "E: locked: the root never takes the mouse")
    EQ(a.hit.__mouse, false, "E: nor the hit surface")
    EQ(M.Click(a.hit, "LeftButton"), false, "E: a click passes straight through (D9)")
    EQ(#opened, 0, "E: nothing opened, nothing cancelled")
    CHECK(O().Get(uid) ~= nil, "E: the waypoint survives clicks")
    M.SetModifier("SHIFT", true)
    EQ(a.hit.__mouse, true, "E: Shift held: the arrow takes the mouse")
    EQ(root.__mouse, false, "E: (the root still does not)")
    EQ(M.Click(a.hit, "LeftButton"), true, "E: Shift-click delivered")
    EQ(opened[1], uid, "E: Shift-click opens the manager on the target")
    M.Click(a.hit, "RightButton")
    local texts = table.concat(M.MenuTexts(), "|")
    for _, want in ipairs({ "Northshire", "Mark arrived", "Clear arrow", "Remove waypoint", "Copy /way line",
            "Open manager", "Unlock arrow" }) do
        HAS(texts, want, "E: menu has " .. want)
    end
    CHECK(not texts:find("Share with group", 1, true), "E: no share entry when not grouped")
    M.Hover(a.hit)
    CHECK(M.Has(M.tooltip, "Right-click: menu"), "E: a tooltip says what clicks do")
    M.SetModifier("SHIFT", false)
    EQ(a.hit.__mouse, false, "E: released: click-through again")
    -- Mark arrived from the menu
    M.SetModifier("SHIFT", true)
    M.Click(a.hit, "RightButton")
    CHECK(M.ClickMenu("Mark arrived"), "E: Mark arrived")
    M.SetModifier("SHIFT", false)
    EQ(O().Get(uid), nil, "E: marked arrived: gone")
    -- Another modifier
    O().Add({ map = 1429, x = 0.48, y = 0.42 })
    Pass(2)
    DB().ArrowModifier = "CTRL"
    Notify()
    M.SetModifier("SHIFT", true)
    EQ(a.hit.__mouse, false, "E: Shift does nothing when Ctrl is chosen")
    M.SetModifier("SHIFT", false)
    M.SetModifier("CTRL", true)
    EQ(a.hit.__mouse, true, "E: Ctrl does")
    M.SetModifier("CTRL", false)
    DB().ArrowModifier = "SHIFT"
    Notify()
    -- In combat the modifier still works (unprotected frame) and nothing is refused
    M.SetCombat(true)
    M.SetModifier("SHIFT", true)
    EQ(a.hit.__mouse, true, "E: in combat too")
    M.SetModifier("SHIFT", false)
    M.SetCombat(false)
    EQ(#M.blocked, 0, "E: no protected call refused")

    -- Unlock, drag placeholder, lock with a right-click
    Corder("unlock")
    EQ(DB().ArrowLocked, false, "E: /corder unlock")
    EQ(root.__shown, true, "E: unlocked: shown")
    EQ(root._hudDragOverlay.__shown, true, "E: the chrome's drag overlay")
    EQ(Text("status"), "Drag to move; right-click to lock", "E: placeholder text")
    M.SetModifier("SHIFT", true)
    EQ(a.hit.__mouse, false, "E: unlocked, the overlay has the mouse, not the hit surface")
    M.SetModifier("SHIFT", false)
    root._hudDragOverlay.__scripts.OnMouseUp(root._hudDragOverlay, "RightButton")
    EQ(DB().ArrowLocked, true, "E: right-click on the overlay locks")
    M.Advance(0.3)
    CHECK(Text("status") ~= "Drag to move; right-click to lock", "E: the placeholder goes with the lock")
    EQ(root.__mouse, false, "E: locked again: click-through")
    Corder("lock")
    EQ(DB().ArrowLocked, true, "E: /corder lock")
    NOERR("E")

    -- A login in combat waits to chrome
    Boot({ player = GOLDSHIRE, combat = true })
    local r2 = _G.CommanderOrdersArrow
    EQ(A().chromeReady, false, "E: combat login: no chrome yet")
    EQ(A().chromePending, true, "E: pending")
    EQ(r2.__passThrough, nil, "E: SetPassThroughButtons not even tried in combat")
    EQ(#M.blocked, 0, "E: nothing refused")
    local p = r2.__points[#r2.__points]
    CHECK(p and p.point == "TOP" and p.x == 240 and p.y == -340, "E: still placed at the default point")
    O().Add({ map = 1429, x = 0.48, y = 0.42 })
    Pass(2)
    EQ(r2.__shown, true, "E: and working in combat")
    M.SetCombat(false)
    EQ(A().chromeReady, true, "E: chromed when combat ends")
    CHECK(r2.__passThrough and r2.__passThrough[1] == "LeftButton", "E: the pass-through set out of combat")
    EQ(r2.__mouse, false, "E: and click-through")
    NOERR("E combat login")
end)

-- ===========================================================================
-- F: the API
-- ===========================================================================
Section("F", function()
    Boot({ player = GOLDSHIRE })
    local o = O()
    DB().EnableOrders = false
    Notify()
    local uid, why = o.Add({ map = 1429, x = 0.5, y = 0.5 })
    CHECK(uid == nil and why == "disabled", "F: Add refuses while disabled (D7)", why)
    local rid, why2 = o.AddRoute({ stops = { { map = 1429, x = 0.5, y = 0.5 } } })
    CHECK(rid == nil and why2 == "disabled", "F: AddRoute refuses", why2)
    local h, why3 = o.Here()
    CHECK(h == nil and why3 == "disabled", "F: Here refuses", why3)
    EQ(CommanderOrders_IssueOrder(1429, 0.5, 0.5), false, "F: IssueOrder returns false when off")
    EQ(CommanderOrders.TomTomShim:AddWaypoint(1429, 0.5, 0.5, { title = "x" }), nil, "F: the shim adds nothing when off")
    -- and is not there to be found: Questie's and WhatsTraining's waypoint
    -- buttons look for the TomTom global alone (review: questie-shim)
    EQ(rawget(_G, "TomTom"), nil, "F: Orders off: no TomTom global for Questie to offer buttons on")
    local avail, reason = o.IsAvailable()
    CHECK(avail == false and reason == "disabled", "F: IsAvailable says why", reason)
    Way("50 50")
    CHECK(M.Has(M.prints, "turned off"), "F: /way says Orders is off")
    EQ(#o.List(), 0, "F: nothing was added")
    DB().EnableOrders = true
    Notify()
    uid = o.Add({ map = 1429, x = 0.5, y = 0.5 })
    CHECK(uid ~= nil, "F: on again: adds")
    EQ(rawget(_G, "TomTom"), CommanderOrders.TomTomShim, "F: on again: the shim is back")

    -- Never raises
    M.ClearLog()
    local function Safe(label, fn, ...)
        local ok, a, b = pcall(fn, ...)
        CHECK(ok, "F: " .. label .. " never raises", a)
        return a, b
    end
    local a1, b1 = Safe("Add(nil)", o.Add, nil)
    CHECK(a1 == nil and b1 == "no spec", "F: Add(nil) -> nil, no spec", b1)
    a1, b1 = Safe("Add bad map", o.Add, { map = "x", x = 0.5, y = 0.5 })
    CHECK(a1 == nil and type(b1) == "string", "F: a bad map is refused", b1)
    a1, b1 = Safe("Add x out of range", o.Add, { map = 1429, x = 2, y = 0.5 })
    CHECK(a1 == nil and b1 == "invalid x", "F: x out of range", b1)
    a1, b1 = Safe("Add NaN", o.Add, { map = 1429, x = 0 / 0, y = 0.5 })
    CHECK(a1 == nil, "F: NaN refused")
    a1, b1 = Safe("Add cosmic", o.Add, { map = 946, x = 0.5, y = 0.5 })
    CHECK(a1 == nil and b1 == "no world position", "F: a map with no world data is refused", b1)
    Safe("Remove(nil)", o.Remove, nil)
    Safe("Get(nope)", o.Get, "nope")
    Safe("Share(nil)", o.Share, nil)
    Safe("WayLine(nil)", o.WayLine, nil)
    Safe("Distance(nope)", o.Distance, "nope")
    a1, b1 = Safe("SetArrow(nope)", o.SetArrow, "nope")
    CHECK(a1 == nil and b1 == "unknown", "F: SetArrow on an unknown uid", b1)
    Safe("RemoveBy(nil)", o.RemoveBy, nil)
    Safe("Clear('x')", o.Clear, "x")
    Safe("Update(nope)", o.Update, "nope", { title = "x" })
    Safe("Command(nil)", o.Command, nil)
    Safe("RegisterResolver bad", o.RegisterResolver, "nope", 1)
    EQ(#M.errors, 0, "F: nothing reported to the error handler")

    -- Copies
    o.Clear()
    uid = o.Add({ map = 1429, x = 0.48, y = 0.42, title = "Original" })
    local copy = o.Get(uid)
    EQ(copy.zone, "Elwynn Forest", "F: Get carries the zone name")
    copy.title = "Hacked"
    copy.x = 0.9
    EQ(o.Get(uid).title, "Original", "F: Get hands out copies")
    EQ(o.Get(uid).callbacks, nil, "F: no callbacks in a copy")
    -- Defaults by source
    local q = o.Add({ map = 1429, x = 0.3, y = 0.3, source = "QuestLog", key = "quest:1", setArrow = false })
    EQ(o.Get(q).persistent, false, "F: a consumer's waypoint is session-only unless it says")
    local qp = o.Add({ map = 1429, x = 0.31, y = 0.3, source = "QuestLog", key = "quest:2", persistent = true })
    EQ(o.Get(qp).persistent, true, "F: unless it asks to persist")
    EQ(o.Get(uid).persistent, true, "F: the user's persist")
    EQ(o.Active().uid, qp, "F: setArrow defaults to true")
    -- Re-adding with the same (source, key) moves it
    local q2, _, status = o.Add({ map = 1429, x = 0.32, y = 0.33, source = "QuestLog", key = "quest:1", setArrow = false })
    EQ(q2, q, "F: same (source, key): same uid")
    EQ(status, "moved", "F: moved")
    EQ(o.Get(q).x, 0.32, "F: to the new place")
    -- Temporary never steals
    o.SetArrow(uid)
    local t = o.Add({ map = 1429, x = 0.6, y = 0.6, source = "Oracle", temporary = true })
    EQ(o.Active().uid, uid, "F: a temporary waypoint never steals the user's arrow")
    CHECK(t ~= nil, "F: but it is added")
    -- KeepMyMarks
    DB().KeepMyMarks = true
    local keep = o.Add({ map = 1429, x = 0.7, y = 0.7 })
    EQ(o.Get(keep).clearOnArrive, false, "F: Keep My Own Marks keeps user marks")
    local cons = o.Add({ map = 1429, x = 0.71, y = 0.7, source = "Tradecraft" })
    EQ(o.Get(cons).clearOnArrive, true, "F: not consumer ones")
    DB().KeepMyMarks = false
    -- A continent click lands in the zone under it
    local ci, cn, cw = WorldOf(1429, 0.5, 0.5)
    local cx, cy = M.MapPos(1415, ci, cn, cw)
    local cont = o.Add({ map = 1415, x = cx, y = cy, title = "From the continent" })
    local cc = o.Get(cont)
    EQ(cc.map, 1429, "F: a continent point is stored on its zone")
    NEAR(cc.x, 0.5, 1e-6, "F: zone x")
    NEAR(cc.y, 0.5, 1e-6, "F: zone y")
    -- CHANGED is debounced: one per frame
    local fired = 0
    Commander.AddListener(COMMANDER_ORDERS_EVENTS.CHANGED, function() fired = fired + 1 end)
    M.Frame()
    fired = 0
    o.Add({ map = 1429, x = 0.11, y = 0.1 })
    o.Add({ map = 1429, x = 0.12, y = 0.1 })
    o.Add({ map = 1429, x = 0.13, y = 0.1 })
    EQ(fired, 0, "F: not mid-frame")
    M.Frame()
    EQ(fired, 1, "F: once on the next frame for three adds")
    CHECK(type(CommanderOrdersChar.Store) == "table" and #CommanderOrdersChar.Store.Waypoints > 0,
        "F: the store is saved on change")
    -- Remove, RemoveBy, Clear
    EQ(o.RemoveBy("QuestLog"), 2, "F: RemoveBy source")
    EQ(o.Get(q), nil, "F: gone")
    EQ(o.Remove(uid), true, "F: Remove")
    EQ(o.Remove(uid), false, "F: Remove twice")
    CHECK(o.Clear() > 0, "F: Clear")
    EQ(#o.List(), 0, "F: empty")
    -- A zone resolver for names the index lacks
    o.RegisterResolver("zone", function(name) if name:lower() == "farmland" then return 1429 end end)
    Way("farmland 10 20 Field")
    local f = o.List()[1]
    CHECK(f and f.map == 1429 and f.title == "Field", "F: a registered zone resolver answers /way")
    NOERR("F")
end)

-- ===========================================================================
-- G: legacy wrappers
-- ===========================================================================
Section("G", function()
    Boot({ player = GOLDSHIRE })
    EQ(CommanderOrders_IssueOrder(1429, 0.5, 0.5), true, "G: IssueOrder -> true")
    local first = O().Active()
    EQ(first and first.source, "legacy", "G: source legacy")
    EQ(first and first.why, "PINNED", "G: takes the arrow")
    EQ(CommanderOrders_IssueOrder(1429, 0.6, 0.6), true, "G: again")
    EQ(#O().List({ source = "legacy" }), 1, "G: one legacy order, moved (the old single slot)")
    EQ(O().Active().uid, first.uid, "G: same record")
    EQ(CommanderOrders_IssueOrder(946, 0.5, 0.5), false, "G: no world data -> false")
    M.ClearLog()
    CommanderOrders_ClearOrder(true)
    EQ(#O().List({ source = "legacy" }), 0, "G: ClearOrder removes it")
    CHECK(M.Has(M.prints, "order cleared"), "G: and says so")
    M.ClearLog()
    CommanderOrders_ClearOrder(true)
    EQ(#M.prints, 0, "G: an empty clear says nothing (D18)")
    -- Rally slots are places now
    M.SetPlayer(1429, 0.30, 0.70)
    CommanderOrders_RallySet(1)
    local places = O().Places()
    EQ(places[1] and places[1].title, "Rally 1", "G: RallySet(1) marks place Rally 1")
    EQ(places[1] and places[1].faction, "Horde", "G: tagged with the faction")
    M.SetPlayer(1429, 0.5, 0.5)
    CommanderOrders_RallySet(1)
    EQ(#O().Places(), 1, "G: marking slot 1 again moves it")
    M.ClearLog()
    CommanderOrders_RallyGo(1)
    local go = O().Active()
    EQ(go and go.title, "Rally 1", "G: RallyGo(1) sets the arrow")
    EQ(go and go.source, "place", "G: as a place waypoint")
    CommanderOrders_RallyGo(3)
    CHECK(M.Has(M.prints, "no rally point marked in slot 3"), "G: an empty slot says so")
    CommanderOrders_RallySet(5)
    EQ(#O().Places(), 1, "G: slot 5 does nothing")
    M.ClearLog()
    CommanderOrders_RallyList()
    CHECK(M.Has(M.prints, "Rally 1"), "G: RallyList lists")
    Corder("set 2")
    EQ(#O().Places(), 2, "G: /corder set 2")
    Corder("go 2")
    EQ(O().Active().title, "Rally 2", "G: /corder go 2")
    NOERR("G")
end)

-- ===========================================================================
-- H: the TomTom shim
-- ===========================================================================
local function Walk2(t)
    -- every value plain: no function, table or userdata anywhere in a uid
    for k, v in pairs(t) do
        local tv = type(v)
        if tv == "table" or tv == "function" or tv == "userdata" then return false, k end
    end
    return true
end

Section("H", function()
    Boot({ player = GOLDSHIRE })
    local TT = TomTom
    EQ(TT, CommanderOrders.TomTomShim, "H: installed")
    EQ(TT.isCommanderShim, true, "H: tagged")
    EQ(TT.version, "Commander_Orders", "H: a string version")
    EQ(getmetatable(TT), nil, "H: no catch-all metatable")
    for _, absent in ipairs({ "db", "profile", "waydb", "ClearAllWaypoints", "HijackCrazyArrow",
            "ReleaseCrazyArrow", "SetWaypoint", "ClearWaypoint" }) do
        EQ(TT[absent], nil, "H: tier 3 absent: " .. absent)
    end
    local q = 0
    -- Questie's TrackerUtils:SetTomTomTarget, exactly
    local stored
    local function SetTomTomTarget(title, uiMapId, x, y)
        if TomTom and TomTom.AddWaypoint then
            if stored and TomTom.RemoveWaypoint then TomTom:RemoveWaypoint(stored) end
            stored = TomTom:AddWaypoint(uiMapId, x / 100, y / 100, { title = title, crazy = true, from = "Questie" })
        end
    end
    SetTomTomTarget("Marshal McBride", 1429, 48.2, 41.4)
    EQ(type(stored), "table", "H: AddWaypoint returns a table uid")
    EQ(stored[1], 1429, "H: uid[1] map")
    EQ(stored[2], 48.2 / 100, "H: uid[2] exactly as passed")
    EQ(stored[3], 41.4 / 100, "H: uid[3] exactly as passed")
    EQ(stored.title, "Marshal McBride", "H: uid.title")
    EQ(stored.from, "Questie", "H: uid.from")
    EQ(stored.crazy, true, "H: scalar opts copied in")
    CHECK(Walk2(stored), "H: the uid is plain data (safe in Questie's SV)")
    local act = O().Active()
    EQ(act and act.title, "Marshal McBride", "H: crazy=true takes the arrow")
    EQ(act and act.source, "TomTom:Questie", "H: source TomTom:<from>")
    SetTomTomTarget("Goldtooth", 1429, 40, 60)
    EQ(#O().List({ source = "TomTom:Questie" }), 1, "H: Questie's remove-then-add keeps one waypoint")
    EQ(O().Active().title, "Goldtooth", "H: on the new target")

    -- QuestieFrame's Ctrl-click toggle, exactly
    local waypoint
    local function Toggle(uiMapId, x, y, title)
        if waypoint then TomTom:RemoveWaypoint(waypoint) end
        local add = (not waypoint) or (waypoint[1] ~= uiMapId or waypoint[2] ~= x or waypoint[3] ~= y
            or waypoint.title ~= title or waypoint.from ~= "Questie")
        waypoint = add and TomTom:AddWaypoint(uiMapId, x, y, { title = title, crazy = true, from = "Questie" })
    end
    local before = #O().List()
    Toggle(1429, 0.25, 0.25, "Pin")
    EQ(#O().List(), before + 1, "H: toggle on")
    Toggle(1429, 0.25, 0.25, "Pin")
    EQ(waypoint, false, "H: toggle off stores false")
    EQ(#O().List(), before, "H: and removed it")
    Toggle(1429, 0.25, 0.25, "Pin")
    EQ(#O().List(), before + 1, "H: on again")

    -- opts are never mutated; duplicates return the same table
    local opts = { title = "Trainer", from = "WhatsTraining", persistent = false, minimap = true, world = true, crazy = true }
    local snapshot = {}
    for k, v in pairs(opts) do snapshot[k] = v end
    local u1 = TT:AddWaypoint(1429, 0.3, 0.4, opts)
    local u2 = TT:AddWaypoint(1429, 0.3, 0.4, opts)
    local u3 = TT:AddWaypoint(1429, 0.3, 0.4, opts)
    EQ(u1, u2, "H: a duplicate returns the same uid table")
    EQ(u2, u3, "H: (WhatsTraining clicked three times)")
    O().SetArrow(O().List({ source = "TomTom:Questie" })[1].uid)
    TT:AddWaypoint(1429, 0.3, 0.4, opts)
    EQ(O().Active().title, "Trainer", "H: asking again points the arrow there (TomTom B16 fixed)")
    EQ(#O().List({ source = "TomTom:WhatsTraining" }), 1, "H: one waypoint")
    local same = true
    for k, v in pairs(opts) do if snapshot[k] ~= v then same = false end end
    for k in pairs(snapshot) do if opts[k] == nil then same = false end end
    EQ(same, true, "H: the caller's opts untouched")
    EQ(opts.callbacks, nil, "H: no callbacks injected into opts")

    -- Refusals never error
    M.ClearLog()
    EQ(TT:AddWaypoint(nil, 0.5, 0.5, {}), nil, "H: a nil map (Questie's unknown zone) -> nil")
    EQ(TT:AddWaypoint(1429, 0 / 0, 0.5), nil, "H: NaN -> nil")
    TT:RemoveWaypoint("x")
    TT:RemoveWaypoint(42)
    TT:RemoveWaypoint({})
    TT:RemoveWaypoint(nil)
    TT:RemoveWaypoint({ 1944, 0.5, 0.5, title = "Real TomTom", from = "TomTom/wm" })
    EQ(#M.errors, 0, "H: unknown and stale uids are silent no-ops")

    -- Distance callbacks, pcall'd
    local calls = {}
    local cb = TT:DefaultCallbacks()
    CHECK(type(cb.distance) == "table" and type(cb.minimap) == "table", "H: DefaultCallbacks shape")
    cb.distance[15] = function(event, uid, range, distance, last)
        calls[#calls + 1] = { event = event, uid = uid, range = range, distance = distance, last = last }
    end
    cb.distance[40] = function() error("third-party bug") end
    local cu = TT:AddWaypoint(1429, 0.48, 0.42, { title = "Bands", callbacks = cb, crazy = true, from = "Test" })
    CHECK(Walk2(cu), "H: callbacks stay out of the uid (kept in a side table)")
    EQ(cu.callbacks, nil, "H: no callbacks field on the uid")
    Pass(2)
    local _, tn, tw = WorldOf(1429, 0.48, 0.42)
    StandShort(tn, tw, 30)
    Pass(2)
    CHECK(M.Has(M.errors, "third-party bug"), "H: a raising callback is reported, not raised")
    local errorsAfter = #M.errors
    StandShort(tn, tw, 12)
    Pass(2)
    CHECK(#calls >= 1, "H: the 15 yd band fired walking in")
    local last = calls[#calls]
    CHECK(last and last.event == "distance" and last.uid == cu and last.range == 15 and last.distance < 15,
        "H: with TomTom's arguments (event, uid table, range, distance, last)")
    M.Advance(1)
    EQ(#M.errors, errorsAfter, "H: and the arrow kept running")

    -- Tier 2
    EQ(TT:IsValidWaypoint(cu), true, "H: IsValidWaypoint")
    EQ(TT:IsValidWaypoint({ 1, 0.1, 0.1 }), false, "H: IsValidWaypoint on a stranger")
    EQ(TT:WaypointExists(1429, 0.48, 0.42, "Bands"), true, "H: WaypointExists")
    EQ(TT:GetKeyArgs(1, 0.5, 0.25, "t"), "1:500000000:250000000:t", "H: GetKeyArgs in TomTom's format")
    EQ(TT:GetKey(cu), TT:GetKeyArgs(1429, 0.48, 0.42, "Bands"), "H: GetKey")
    CHECK(type(TT:GetDistanceToWaypoint(cu)) == "number", "H: GetDistanceToWaypoint")
    CHECK(type(TT:GetDirectionToWaypoint(cu)) == "number", "H: GetDirectionToWaypoint")
    local m, x, y = TT:GetCurrentPlayerPosition()
    CHECK(m == 1429 and x and y, "H: GetCurrentPlayerPosition")
    EQ(TT:IsCrazyArrowEmpty(), false, "H: IsCrazyArrowEmpty")
    local custom = TT:SetCustomWaypoint(1429, 0.2, 0.2, { title = "Custom", from = "Test" })
    EQ(custom.persistent, false, "H: SetCustomWaypoint is session-only")
    local cz = TT:AddWaypointToCurrentZone(50, 50, "Middle")
    CHECK(cz and cz[1] == 1429 and cz[2] == 0.5, "H: AddWaypointToCurrentZone takes 0..100")
    TT:SetCrazyArrow(custom)
    EQ(O().Active().title, "Custom", "H: SetCrazyArrow")
    local closest = TT:GetClosestWaypoint()
    EQ(type(closest), "table", "H: GetClosestWaypoint returns a uid table")
    CHECK(TT:SetClosestWaypoint() ~= nil, "H: SetClosestWaypoint")
    -- Removed by Orders: the side tables forget it, a re-add is new
    local gone = TT:AddWaypoint(1429, 0.66, 0.66, { title = "Doomed", from = "Test" })
    O().Remove(O().Active() and Store():Find(1429, 0.66, 0.66, "Doomed").uid)
    EQ(TT:IsValidWaypoint(gone), false, "H: removed in Orders: no longer valid")
    local again = TT:AddWaypoint(1429, 0.66, 0.66, { title = "Doomed", from = "Test" })
    CHECK(again ~= gone, "H: a re-add after removal is a new uid, not a dead one")

    -- Questie's stale uid after a /reload (16 printed digits)
    SetTomTomTarget("Stale", 1429, 33.3333333333333, 66.6666666666667)
    local keep = stored
    local W2 = Reload({ extraSaved = { questie = keep } })
    local copy = W2.restored.questie
    CHECK(copy ~= keep and copy[1] == 1429, "H: the copy came back through the SV writer")
    local restored = Store():Find(1429, keep[2], keep[3], "Stale", 1e-6)
    CHECK(restored ~= nil, "H: Questie's waypoint persisted (TomTom's default)")
    EQ(#O().List({ source = "TomTom:WhatsTraining" }), 0, "H: WhatsTraining's persistent=false did not")
    -- a copy one bit off, as a 17-digit double printed with 16 can be
    local off = { copy[1], copy[2] * (1 + 2e-16), copy[3], title = copy.title, from = copy.from }
    TomTom:RemoveWaypoint(off)
    EQ(Store():Find(1429, keep[2], keep[3], "Stale", 1e-6), nil, "H: RemoveWaypoint(stale copy) removes the restored one")
    -- Questie's toggle across a reload
    SetTomTomTarget("Toggle", 1429, 20, 20)
    waypoint = stored
    local W3 = Reload({ extraSaved = { questie = stored } })
    waypoint = W3.restored.questie
    local function Toggle2(uiMapId, x, y, title)
        if waypoint then TomTom:RemoveWaypoint(waypoint) end
        local add = (not waypoint) or (waypoint[1] ~= uiMapId or waypoint[2] ~= x or waypoint[3] ~= y
            or waypoint.title ~= title or waypoint.from ~= "Questie")
        waypoint = add and TomTom:AddWaypoint(uiMapId, x, y, { title = title, crazy = true, from = "Questie" })
    end
    Toggle2(1429, 0.2, 0.2, "Toggle")
    EQ(waypoint, false, "H: a toggle after reload turns it off")
    EQ(Store():Find(1429, 0.2, 0.2, "Toggle", 1e-6), nil, "H: and nothing is left behind")
    NOERR("H")

    -- Install rules
    Boot({ player = GOLDSHIRE, loaded = { TomTom = true } })
    EQ(rawget(_G, "TomTom"), nil, "H: TomTom loaded: no shim")
    EQ(SLASH_COMMANDERORDERS_WAY1, nil, "H: and /way is left to it")
    Corder("way 40 40 Namespaced")
    EQ(O().Active() and O().Active().title, "Namespaced", "H: /corder way works alongside TomTom")
    local fake = { fake = true }
    Boot({ player = GOLDSHIRE, before = function() rawset(_G, "TomTom", fake) end })
    EQ(rawget(_G, "TomTom"), fake, "H: an existing TomTom global is never replaced")
    Boot({ player = GOLDSHIRE })
    DB().TomTomShim = false
    Notify()
    EQ(rawget(_G, "TomTom"), nil, "H: setting off removes the shim")
    DB().TomTomShim = true
    Notify()
    EQ(rawget(_G, "TomTom"), CommanderOrders.TomTomShim, "H: and on puts it back")
    NOERR("H install")
end)

-- ===========================================================================
-- I: /way end to end
-- ===========================================================================
Section("I", function()
    Boot({ player = GOLDSHIRE })
    EQ(SLASH_COMMANDERORDERS_WAY1, "/way", "I: /way claimed")
    EQ(SLASH_COMMANDERORDERS_WAY2, "/tway", "I: /tway")
    EQ(SLASH_COMMANDERORDERS_WAYBACK1, "/wayb", "I: /wayb")
    EQ(SLASH_COMMANDERORDERS_WAYBACK2, "/wayback", "I: /wayback")
    EQ(SLASH_COMMANDERORDERS_CWAY1, "/cway", "I: /cway")
    EQ(SLASH_COMMANDERORDERS_CWAY2, "/closestway", "I: /closestway")
    EQ(SlashCmdList.TOMTOM_WAY, nil, "I: never TOMTOM_WAY")
    Way("45 66 Mixed Case")
    local a = O().Active()
    CHECK(a and a.map == 1429 and math.abs(a.x - 0.45) < 1e-9 and a.title == "Mixed Case", "I: /way x y title on this map")
    Way("hellfire 45.2, 66.8 Nazgrel")
    a = O().Active()
    CHECK(a and a.map == 1944 and math.abs(a.x - 0.452) < 1e-9 and math.abs(a.y - 0.668) < 1e-9, "I: zone by name")
    EQ(a.title, "Nazgrel", "I: title")
    Way("hfp 50 50")
    EQ(O().Active().map, 1944, "I: alias hfp")
    Way("shatt 50 50 Aldor")
    EQ(O().Active().map, 1955, "I: alias shatt")
    Way("#1944 30,40")
    a = O().Active()
    CHECK(a and a.x == 0.3 and a.y == 0.4, "I: a lone 30,40 is a pair (TomTom B13)")
    M.ClearLog()
    local n = #O().List()
    Way("alterac 50 50")
    EQ(#O().List(), n, "I: ambiguous adds nothing")
    CHECK(M.Has(M.prints, "/way #1416 50.00 50.00") and M.Has(M.prints, "/way #1459 50.00 50.00"),
        "I: ambiguous lists the candidates with their /way #id lines", table.concat(M.prints, " / "))
    M.ClearLog()
    Way("atlantis 50 50")
    CHECK(M.Has(M.prints, "No zone called"), "I: unknown zone")
    Way("150 20")
    CHECK(M.Has(M.prints, "0 to 100"), "I: out of range")
    Way("(50 50")
    EQ(#M.errors, 0, "I: pattern characters never error (B12)")
    M.ClearLog()
    Way("")
    CHECK(M.Has(M.prints, "/way [zone] x y [title]"), "I: bare /way prints usage")
    M.ClearLog()
    Way("reset")
    CHECK(M.Has(M.prints, "/way reset all"), "I: bare reset prints its usage (B23)")
    Way("#99999 50 50")
    CHECK(M.Has(M.prints, "no map #99999"), "I: an unknown map id")
    M.ClearLog()
    Way("#946 50 50")
    CHECK(M.Has(M.prints, "no world coordinates"), "I: a map with no world data")
    M.ClearLog()
    Way("list")
    CHECK(#M.prints >= 2 and M.Has(M.prints, "Nazgrel"), "I: /way list")
    M.ClearLog()
    Way("local")
    CHECK(M.Has(M.prints, "Mixed Case") and not M.Has(M.prints, "Nazgrel"), "I: /way local is this map only")
    M.ClearLog()
    Way("arrow")
    CHECK(M.Has(M.prints, "arrow"), "I: /way arrow reports")
    -- reset scopes
    local total = #O().List()
    local elwynn = #O().List({ map = 1429 })
    Way("reset not elwynn")
    EQ(#O().List(), elwynn, "I: reset not <zone>")
    Way("hellfire 10 10 Back")
    Way("reset away")
    EQ(#O().List(), elwynn, "I: reset away keeps this map")
    Way("reset elwynn")
    EQ(#O().List(), 0, "I: reset <zone>")
    CHECK(total > elwynn, "I: (there was something else to remove)")
    Way("10 10 One")
    Way("20 20 Two")
    Way("reset all")
    EQ(M.popups[#M.popups].which, "COMMANDER_ORDERS_CLEAR_ALL", "I: reset all asks first")
    EQ(#O().List(), 2, "I: not before the answer")
    M.ClickPopup("COMMANDER_ORDERS_CLEAR_ALL", 1)
    EQ(#O().List(), 0, "I: then removes everything")
    -- /wayb and /cway
    SlashCmdList.COMMANDERORDERS_WAYBACK("Camp Site")
    EQ(O().Active().title, "Camp Site", "I: /wayb title")
    O().ClearArrow()
    O().Add({ map = 1429, x = 0.9, y = 0.9, title = "Far", setArrow = false })
    SlashCmdList.COMMANDERORDERS_CWAY("")
    EQ(O().Active().title, "Camp Site", "I: /cway pins the closest")
    -- /corder way keeps its case; the framework's words still work
    Corder("way 10 20 Keep The Case")
    EQ(O().Active().title, "Keep The Case", "I: /corder way keeps the case (the wrap)")
    Corder("clear")
    EQ(Store():Find(1429, 0.1, 0.2, "Keep The Case"), nil, "I: /corder clear removes the active one")
    M.ClearLog()
    Corder("bogus")
    CHECK(M.Has(M.prints, "Usage: /corder"), "I: unknown words get the framework's usage line")
    local opened = #M.settingsOpened
    Corder("")
    EQ(#M.settingsOpened, opened + 1, "I: bare /corder opens the page")
    NOERR("I")
end)

-- ===========================================================================
-- J: sharing
-- ===========================================================================
Section("J", function()
    Boot({ player = GOLDSHIRE })
    EQ(M.W.prefixes.CmdrOrders, true, "J: prefix registered once at login")
    EQ(M.W.prefixes.TOMTOM4, nil, "J: TomTom's prefix only when listening")
    local uid = O().Add({ map = 1429, x = 0.48, y = 0.42, title = "Mill: Gate | 100%" })
    local ok, why = O().Share(uid)
    CHECK(ok == nil and why == "not in a group", "J: not grouped: refused", why)
    EQ(#M.sent, 0, "J: nothing sent")
    M.SetGroup("party", { "Healer" })
    ok = O().Share(uid)
    EQ(ok, true, "J: shared with the party")
    local msg = M.sent[#M.sent]
    EQ(msg.prefix, "CmdrOrders", "J: our prefix")
    EQ(msg.channel, "PARTY", "J: PARTY")
    EQ(msg.text, "1:1429:0.48000:0.42000:Mill%3A Gate %7C 100%25", "J: versioned, escaped payload")
    CHECK(#msg.text <= 255, "J: fits an addon message")
    M.SetGroup("raid", { "Healer" })
    O().Share(uid)
    EQ(M.sent[#M.sent].channel, "RAID", "J: RAID")
    M.SetGroup("instance", { "Healer" })
    O().Share(uid)
    EQ(M.sent[#M.sent].channel, "INSTANCE_CHAT", "J: INSTANCE_CHAT in an instance group")
    M.W.sendResult = 3
    ok, why = O().Share(uid)
    CHECK(ok == nil and why == "too many messages, try again", "J: the result enum is checked (3 is truthy)", why)
    M.W.sendResult = 0
    M.SetGroup("party", { "Healer" })
    O().Share(uid, "CHAT")
    local chat = M.chat[#M.chat]
    CHECK(chat and chat.chatType == "PARTY" and chat.text:find("^/way #1429 48.00 42.00"), "J: CHAT posts the /way line",
        chat and chat.text)
    -- Receiving: a prompt, never the arrow
    local mine = Store():Pinned()
    M.Receive("CmdrOrders", "1:1429:0.30000:0.40000:Mill%3A Gate", "PARTY", "Healer-Dreamscythe")
    local pop = M.popups[#M.popups]
    EQ(pop and pop.which, "COMMANDER_ORDERS_SHARE", "J: ASK: a prompt")
    EQ(pop and pop.a1, "Healer", "J: from Healer (realm folded)")
    HAS(pop and pop.a2, "Mill: Gate (Elwynn Forest 30.0, 40.0)", "J: what and where, title unescaped")
    EQ(Store():Pinned(), mine, "J: the arrow is not stolen by a share")
    EQ(CountSounds(3175) > 0, true, "J: a ping on receive")
    M.ClickPopup("COMMANDER_ORDERS_SHARE", 1)
    local got = Store():Find(1429, 0.3, 0.4, "Mill: Gate")
    CHECK(got and got.source == "share:Healer", "J: Add adds it as share:Healer")
    EQ(Store():Pinned(), mine, "J: Add does not take the arrow")
    M.Receive("CmdrOrders", "1:1429:0.31000:0.41000:Second", "PARTY", "Healer-Dreamscythe")
    M.ClickPopup("COMMANDER_ORDERS_SHARE", 3)
    EQ(Store():Pinned() and Store():Pinned().title, "Second", "J: Add and go takes it")
    M.Receive("CmdrOrders", "1:1429:0.32000:0.42000:Third", "PARTY", "Healer-Dreamscythe")
    M.ClickPopup("COMMANDER_ORDERS_SHARE", 2)
    EQ(Store():Find(1429, 0.32, 0.42, "Third"), nil, "J: Ignore adds nothing")
    -- Self-echo
    local pops = #M.popups
    M.Receive("CmdrOrders", "1:1429:0.5:0.5:Me", "PARTY", "Cptnbubbles-Dreamscythe")
    M.Receive("CmdrOrders", "1:1429:0.5:0.5:Me", "PARTY", "Cptnbubbles")
    EQ(#M.popups, pops, "J: our own echo is ignored")
    -- Throttle
    for i = 1, 4 do M.Receive("CmdrOrders", "1:1429:0.6:0." .. i .. ":Spam", "PARTY", "Spammer-Other") end
    EQ(#M.popups, pops + 3, "J: three per sender per window")
    -- Garbage
    local errs = #M.errors
    for _, junk in ipairs({ "hello", "2:1429:0.5:0.5:future", "1:99999:0.5:0.5:x", "1:1429:5:5:x", "", "1:abc" }) do
        M.Receive("CmdrOrders", junk, "PARTY", "Junk-Other")
    end
    EQ(#M.popups, pops + 3, "J: garbage is ignored")
    EQ(#M.errors, errs, "J: without errors")
    -- Auto-add from the group (past the throttle window Healer used up)
    M.Advance(11)
    DB().ShareAccept = "GROUP_AUTO_ADD"
    Notify()
    M.Receive("CmdrOrders", "1:1429:0.7:0.7:Auto", "PARTY", "Healer-Dreamscythe")
    EQ(#M.popups, pops + 3, "J: GROUP_AUTO_ADD: no prompt from a member")
    CHECK(Store():Find(1429, 0.7, 0.7, "Auto") ~= nil, "J: added")
    CHECK(Store():Pinned().title ~= "Auto", "J: arrow untouched")
    M.Receive("CmdrOrders", "1:1429:0.71:0.7:Stranger", "GUILD", "Guildie-Dreamscythe")
    EQ(#M.popups, pops + 4, "J: a non-member still asks")
    DB().ShareAccept = "OFF"
    Notify()
    M.Receive("CmdrOrders", "1:1429:0.72:0.7:Off", "PARTY", "Healer-Dreamscythe")
    EQ(#M.popups, pops + 4, "J: OFF ignores")
    EQ(Store():Find(1429, 0.72, 0.7, "Off"), nil, "J: OFF adds nothing")
    DB().ShareAccept = "ASK"
    Notify()
    -- TomTom's wire, only when listening
    M.Receive("TOMTOM4", "1429:0.400000:0.500000:From TomTom", "PARTY", "Tommy-Dreamscythe")
    EQ(#M.popups, pops + 4, "J: TOMTOM4 ignored by default")
    DB().ListenTomTom = true
    Notify()
    EQ(M.W.prefixes.TOMTOM4, true, "J: listening registers TomTom's prefix")
    M.Receive("TOMTOM4", "1429:0.400000:0.500000:From TomTom", "PARTY", "Tommy-Dreamscythe")
    EQ(#M.popups, pops + 5, "J: and prompts for it")
    HAS(M.popups[#M.popups].a2, "From TomTom", "J: TomTom's title")
    -- Copy as /way line
    CommanderOrders.R.CopyLine(O().WayLine(uid))
    local copyPop = M.popups[#M.popups]
    EQ(copyPop.which, "COMMANDER_ORDERS_COPY", "J: the copy box")
    HAS(copyPop.dialog.editBox.__text, "/way #1429 48.00 42.00", "J: holds the /way line")
    NOERR("J")
end)

-- ===========================================================================
-- K: migration
-- ===========================================================================
Section("K", function()
    local v2 = {
        EnableOrders = false, OrderSound = false,
        Waypoint = { mapID = 1429, x = 0.5, y = 0.5, worldX = -9000, worldY = 0, instance = 0 },
        RallyPoints = {
            [1] = { mapID = 1944, x = 0.55, y = 0.66, zone = "Hellfire Peninsula" },
            [3] = { mapID = 1429, x = 0.42, y = 0.65, zone = "Elwynn Forest" },
            [4] = { mapID = "bad" },
        },
    }
    Boot({ player = GOLDSHIRE, saved = { CommanderOrdersDB = v2 } })
    local db = DB()
    EQ(db.DBVersion, 3, "K: stamped 3")
    EQ(db.Waypoint, nil, "K: the account-wide Waypoint dropped")
    EQ(db.RallyPoints, nil, "K: RallyPoints moved out")
    EQ(#db.Places, 2, "K: two valid rally points became places")
    EQ(db.Places[1].title, "Rally 1", "K: titled by slot")
    EQ(db.Places[1].map, 1944, "K: with their map")
    EQ(db.Places[2].title, "Rally 3", "K: slot 3")
    EQ(db.Sounds, false, "K: OrderSound carried to Sounds")
    EQ(db.OrderSound, nil, "K: and dropped")
    EQ(db.EnableOrders, false, "K: the user's EnableOrders kept")
    EQ(db.ShowArrow, true, "K: new defaults filled")
    NOERR("K migrate")
    db.EnableOrders = true
    Notify()
    CommanderOrders_RallyGo(3)
    EQ(O().Active() and O().Active().title, "Rally 3", "K: a migrated rally point works")
    -- Restore Defaults keeps places and the version
    db.ShowArrow = false
    CommanderOrders.DB.Reset()
    EQ(db.ShowArrow, true, "K: reset restores settings")
    EQ(#db.Places, 2, "K: and keeps places")
    EQ(db.DBVersion, 3, "K: and the version")
    -- A v3 DB is left alone
    Boot({ player = GOLDSHIRE, saved = { CommanderOrdersDB = { DBVersion = 3, EnableOrders = true,
        Places = { { title = "Kept", map = 1429, x = 0.5, y = 0.5 } } } } })
    EQ(#DB().Places, 1, "K: v3 untouched")
    EQ(DB().Places[1].title, "Kept", "K: same place")
    NOERR("K")
end)

-- ===========================================================================
-- L: persistence across a reload
-- ===========================================================================
Section("L", function()
    Boot({ player = GOLDSHIRE })
    local a = O().Add({ map = 1429, x = 0.3820961713790894, y = 0.6123456789012345, title = "Mine" })
    local b = O().Add({ map = 1429, x = 0.2, y = 0.2, source = "QuestLog", key = "q", setArrow = false })
    local c = O().Add({ map = 1429, x = 0.21, y = 0.2, source = "Tradecraft", key = "t", persistent = true, setArrow = false })
    local rid = O().AddRoute({ title = "Trip", stops = { { map = 1429, x = 0.1, y = 0.1 }, { map = 1429, x = 0.15, y = 0.1 } }, start = false })
    O().SetArrow(a)
    M.Frame()
    EQ(CommanderOrdersDB.Waypoint, nil, "L: nothing about this character's waypoints is account-wide")
    Reload()
    NOERR("L reload")
    CHECK(O().Get(a) ~= nil, "L: the user's waypoint survived")
    NEAR(O().Get(a).x, 0.3820961713790894, 1e-12, "L: its coordinates through 16 printed digits")
    EQ(O().Get(b), nil, "L: the consumer's session-only one did not")
    CHECK(O().Get(c) ~= nil, "L: the consumer's persistent one did")
    CHECK(O().GetRoute(rid) ~= nil and #O().GetRoute(rid).stops == 2, "L: the route survived")
    Pass(2)
    EQ(O().Active() and O().Active().uid, a, "L: the arrow is back on the pinned waypoint")
    local d = O().Add({ map = 1429, x = 0.9, y = 0.9 })
    local num = function(u) return tonumber(u:match("%d+")) end
    CHECK(num(d) > num(c) and num(d) > num(a), "L: the uid counter continues (never reuses)", d)
    -- re-adding the same numbers after the reload finds the restored record
    local again, _, status = O().Add({ map = 1429, x = 0.3820961713790894, y = 0.6123456789012345, title = "Mine" })
    EQ(again, a, "L: the same place and title is the same waypoint")
    EQ(status, "existing", "L: existing")
    NOERR("L")
end)

-- ===========================================================================
-- M: the corpse run
-- ===========================================================================
Section("M", function()
    Boot({ player = GOLDSHIRE })
    local mine = O().Add({ map = 1429, x = 0.48, y = 0.42, title = "My mark" })
    Pass(2)
    -- Feign Death is no death
    M.SetLife("FEIGN")
    M.Fire("PLAYER_DEAD")
    EQ(CommanderOrdersChar.Corpse, nil, "M: Feign Death records nothing")
    M.SetLife("ALIVE")
    -- A real death
    M.SetLife("DEAD")
    M.Fire("PLAYER_DEAD")
    EQ(CommanderOrdersChar.Corpse and CommanderOrdersChar.Corpse.map, 1429, "M: the death is remembered per character")
    EQ(Store():Corpse(), nil, "M: no corpse arrow before release")
    -- Release: a ghost at the graveyard, the corpse back at Goldshire
    M.SetCorpse(GOLDSHIRE[1], GOLDSHIRE[2], GOLDSHIRE[3])
    M.SetPlayer(1429, 0.30, 0.75)
    M.SetLife("GHOST")
    M.Fire("PLAYER_ALIVE")
    M.Fire("CORPSE_POSITION_UPDATE")
    Pass(2)
    local corpse = Store():Corpse()
    CHECK(corpse ~= nil, "M: released: a corpse waypoint")
    NEAR(corpse and corpse.x, GOLDSHIRE[2], 1e-6, "M: where the client says the corpse is")
    EQ(Text("title"), "Your corpse", "M: the arrow says so")
    EQ(A().view.why, "CORPSE", "M: the corpse has the arrow")
    EQ(Store():Pinned() and Store():Pinned().uid, mine, "M: your own pin is untouched")
    CHECK((Text("dist") or ""):match("yd$"), "M: with a distance")
    -- Reload while a ghost (Recovery R1)
    Reload()
    Pass(2)
    CHECK(Store():Corpse() ~= nil, "M: after a reload as a ghost the corpse arrow is back")
    EQ(A().view.why, "CORPSE", "M: and leads")
    -- Resurrection
    M.SetLife("ALIVE")
    M.Fire("PLAYER_UNGHOST")
    Pass(2)
    EQ(Store():Corpse(), nil, "M: alive: the corpse waypoint is gone")
    EQ(CommanderOrdersChar.Corpse, nil, "M: and the death forgotten")
    EQ(O().Active() and O().Active().uid, mine, "M: the arrow is back on your mark")
    -- A ghost two zones away: the corpse is only on the continent map, and
    -- is stored on the zone under it
    M.SetLife("DEAD")
    M.Fire("PLAYER_DEAD")
    M.SetCorpse(NORTHSHIRE[1], NORTHSHIRE[2], NORTHSHIRE[3])
    M.SetPlayer(1431, 0.5, 0.5)
    M.SetLife("GHOST")
    M.Fire("PLAYER_ALIVE")
    corpse = Store():Corpse()
    CHECK(corpse and corpse.map == 1429, "M: a corpse found on the continent map lands on its zone", corpse and corpse.map)
    NEAR(corpse and corpse.x, NORTHSHIRE[2], 1e-6, "M: at the corpse's zone x")
    M.SetLife("ALIVE")
    M.Fire("PLAYER_UNGHOST")
    M.SetCorpse(GOLDSHIRE[1], GOLDSHIRE[2], GOLDSHIRE[3])
    M.SetPlayer(1429, 0.30, 0.75)
    -- Corpse arrival
    M.SetLife("DEAD")
    M.Fire("PLAYER_DEAD")
    M.SetLife("GHOST")
    M.Fire("PLAYER_ALIVE")
    Pass(2)
    local _, cn, cw = WorldOf(GOLDSHIRE[1], GOLDSHIRE[2], GOLDSHIRE[3])
    StandShort(cn, cw, 40)
    Pass(2)
    StandShort(cn, cw, 3)
    M.Advance(3.5)
    EQ(Store():Corpse(), nil, "M: reached the corpse: cleared")
    M.Fire("CORPSE_POSITION_UPDATE")
    Pass(2)
    EQ(Store():Corpse(), nil, "M: and not put back for this death")
    M.SetLife("ALIVE")
    M.Fire("PLAYER_UNGHOST")
    -- Battlegrounds: no corpse arrow (Recovery R3)
    M.SetInstance("pvp")
    M.SetLife("DEAD")
    M.Fire("PLAYER_DEAD")
    M.SetLife("GHOST")
    M.Fire("PLAYER_ALIVE")
    M.Fire("CORPSE_POSITION_UPDATE")
    EQ(Store():Corpse(), nil, "M: none in a battleground")
    M.SetLife("ALIVE")
    M.Fire("PLAYER_UNGHOST")
    M.SetInstance(nil)
    -- Corpse Arrow off (through the API, as Commander_Recovery will)
    EQ(O().CorpseArrow(), true, "M: CorpseArrow() on by default")
    EQ(O().SetCorpseArrow(false), false, "M: SetCorpseArrow(false)")
    EQ(DB().CorpseArrow, false, "M: written to the setting")
    M.SetLife("DEAD")
    M.Fire("PLAYER_DEAD")
    M.SetLife("GHOST")
    M.Fire("PLAYER_ALIVE")
    EQ(Store():Corpse(), nil, "M: none with Corpse Arrow off")
    M.SetLife("ALIVE")
    M.Fire("PLAYER_UNGHOST")
    O().SetCorpseArrow(true)
    -- A death in a dungeon points at its entrance (Recovery R4)
    O().RegisterResolver("entrance", function(map)
        if map == 347 then return { map = 1944, x = 0.477, y = 0.536 } end
    end)
    M.SetPlayer(347, 0.5, 0.5)
    M.SetInstance("party")
    M.SetCorpse(347, 0.5, 0.5)
    M.SetLife("DEAD")
    M.Fire("PLAYER_DEAD")
    EQ(CommanderOrdersChar.Corpse.map, 347, "M: died in Hellfire Ramparts")
    M.SetInstance(nil)
    M.SetPlayer(1944, 0.45, 0.55)
    M.SetLife("GHOST")
    M.Fire("PLAYER_ALIVE")
    Pass(2)
    corpse = Store():Corpse()
    CHECK(corpse and corpse.map == 1944 and math.abs(corpse.x - 0.477) < 1e-9, "M: the corpse arrow points at the entrance")
    HAS(corpse and corpse.title, "Hellfire Ramparts entrance", "M: and says so")
    EQ(A().view.mode, "NAV", "M: a straight arrow to it")
    NOERR("M")
end)

-- ===========================================================================
-- N: the settings page
-- ===========================================================================
Section("N", function()
    Boot({ player = GOLDSHIRE })
    local panel = CommanderOrders.DB.Panel
    CHECK(panel ~= nil, "N: the page was built")
    local found
    for _, info in ipairs(Commander.GetModules()) do if info.key == "Orders" then found = info end end
    CHECK(found and found.slash == "/corder" and found.title == "Orders", "N: registered as Orders with /corder")
    EQ(found and found.version, "3.0.0", "N: version from the TOC")
    local titles = {}
    for _, fold in ipairs(panel._folds or {}) do titles[#titles + 1] = fold.title end
    EQ(table.concat(titles, ","), "Arrow,Behaviour,Map & Minimap,Sharing,Compatibility,Places", "N: the sections")
    CHECK(panel._searchBox ~= nil, "N: long enough for a search box")
    local dd = 0
    for i = 1, 40 do
        local f = rawget(_G, "CommanderUIDropDown" .. i)
        if f then
            dd = dd + 1
            CHECK(#(f.__ddEntries or {}) > 0, "N: dropdown " .. i .. " has entries")
            CHECK(f.__ddText ~= nil and f.__ddText ~= "", "N: dropdown " .. i .. " shows its value", f.__ddText)
        end
    end
    EQ(dd, 6, "N: six dropdowns (units, modifier, frame style, sound channel, map click, shares)")
    local text = {}
    for _, row in ipairs(panel._rows or {}) do text[#text + 1] = row.row._keywords or "" end
    local all = table.concat(text, " ")
    HAS(all, "answer tomtom requests from questie and other addons", "N: the compatibility row")
    HAS(all, "claim /way", "N: Claim /way")
    HAS(all, "triple right-click", "N: the page says why triple right-click does not reach the arrow")
    -- A checkbox flips the arrow
    O().Add({ map = 1429, x = 0.48, y = 0.42 })
    Pass(2)
    EQ(_G.CommanderOrdersArrow.__shown, true, "N: shown")
    DB().ShowArrow = false
    Notify()
    EQ(_G.CommanderOrdersArrow.__shown, false, "N: Show the Arrow off hides it")
    DB().ShowArrow = true
    Notify()
    EQ(_G.CommanderOrdersArrow.__shown, true, "N: on again")
    panel:Refresh()
    NOERR("N")
end)

-- ===========================================================================
-- O: the driver, places, paste, routes, bindings
-- ===========================================================================
Section("O", function()
    Boot({ player = GOLDSHIRE })
    local driver = CommanderOrders.R.Driver()
    M.Advance(0.5)
    EQ(driver.__shown, false, "O: asleep with nothing (D17)")
    local uid = O().Add({ map = 1429, x = 0.48, y = 0.42 })
    M.Frame()
    EQ(driver.__shown, true, "O: an add wakes it")
    O().Remove(uid)
    M.Advance(0.5)
    EQ(driver.__shown, false, "O: asleep again when it is gone")
    local churn, awake = 0, 0
    Commander.AddListener(COMMANDER_ORDERS_EVENTS.CHANGED, function() churn = churn + 1 end)
    for _ = 1, 30 do
        M.Frame(1 / 30)
        if driver.__shown then awake = awake + 1 end
    end
    EQ(churn, 0, "O: idle: no CHANGED events")
    EQ(awake, 0, "O: idle: the driver stays asleep frame after frame")
    O().Add({ map = 1944, x = 0.5, y = 0.5, setArrow = false })
    M.Advance(0.5)
    EQ(driver.__shown, false, "O: a waypoint on another landmass, not pinned: nothing to tick")

    -- Places
    local i1 = O().MarkPlace("Farm Spot")
    EQ(type(i1), "number", "O: MarkPlace")
    EQ(O().Places()[i1].faction, "Horde", "O: tagged with the faction")
    O().GoPlace("farm spot")
    local g = O().Active()
    EQ(g and g.title, "Farm Spot", "O: GoPlace by name, any case")
    local g2 = O().GoPlace(i1)
    EQ(g2, g.uid, "O: going again is the same waypoint")
    Corder("mark Mixed Name Place")
    EQ(O().Places()[2] and O().Places()[2].title, "Mixed Name Place", "O: /corder mark keeps the case")
    Corder("go Mixed Name Place")
    EQ(O().Active().title, "Mixed Name Place", "O: /corder go <name>")
    EQ(O().RenamePlace(2, "Renamed"), true, "O: RenamePlace")
    EQ(O().RemovePlace("Renamed"), true, "O: RemovePlace")
    EQ(#O().Places(), 1, "O: one left")

    -- Paste and export
    O().Clear()
    local added, errors = O().Import("/way #1429 40 40 A\n45 50 B\nbogus line here\n/cway\n\n")
    EQ(added, 2, "O: two /way lines imported (with and without /way)")
    EQ(#errors, 2, "O: two lines reported")
    EQ(errors[1] and errors[1].line, 3, "O: by line number")
    EQ(O().Active().title, "A", "O: the first takes the arrow")
    local lines = O().Export()
    EQ(#lines, 2, "O: export writes them back")
    HAS(lines[1], "/way #1429 40.00 40.00 A", "O: as /way lines")
    local n, _, rid = O().Import("10 10 S1\n20 20 S2\n30 30 S3", { route = true, mode = "NEAREST", title = "Paste trip" })
    EQ(n, 3, "O: imported as a route")
    local route = O().GetRoute(rid)
    EQ(route and route.mode, "NEAREST", "O: nearest-first")
    EQ(#O().Export(rid), 3, "O: a route exports in order")
    EQ(O().SavePastePage("Trip", "10 10 S1"), true, "O: save a paste page")
    EQ(O().PastePages()[1].name, "Trip", "O: listed")
    EQ(O().DeletePastePage("trip"), true, "O: deleted")

    -- Routes on the arrow
    O().Clear()
    local r = O().AddRoute({ title = "Trip", source = "Tradecraft", key = "trip", stops = {
        { map = 1429, x = 0.48, y = 0.42, title = "First" },
        { map = 1429, x = 0.50, y = 0.40, title = "Second" },
        { map = 1429, x = 0.52, y = 0.38, title = "Third" } } })
    Pass(2)
    EQ(Text("title"), "First", "O: the route's first stop")
    EQ(Text("status"), "Stop 1 of 3", "O: progress")
    M.SetModifier("SHIFT", true)
    M.Click(A().hit, "RightButton")
    CHECK(M.ClickMenu("Next stop"), "O: Next stop in the menu")
    M.SetModifier("SHIFT", false)
    Pass(2)
    EQ(Text("title"), "Second", "O: next")
    O().RoutePrev()
    Pass(2)
    EQ(Text("title"), "First", "O: previous")
    -- arrive at each in turn
    for _, stop in ipairs({ { 0.48, 0.42 }, { 0.50, 0.40 }, { 0.52, 0.38 } }) do
        local _, sn, sw = WorldOf(1429, stop[1], stop[2])
        StandShort(sn, sw, 40)
        Pass(2)
        StandShort(sn, sw, 2)
        M.Advance(3)
    end
    EQ(O().GetRoute(r), nil, "O: the finished route is removed")
    CHECK(M.Has(M.prints, "route complete: Trip"), "O: Route complete")

    -- Bindings
    DB().ShowArrow = true
    CommanderOrders.Binding("ARROW")
    EQ(DB().ShowArrow, false, "O: binding ARROW toggles the arrow")
    CommanderOrders.Binding("ARROW")
    CommanderOrders.Binding("HERE")
    local here = O().Active()
    CHECK(here and here.map == 1429, "O: binding HERE")
    CommanderOrders.Binding("CLEAR")
    EQ(O().Get(here.uid), nil, "O: binding CLEAR removes the active waypoint")
    local opened = 0
    CommanderOrders.UI = { Toggle = function() opened = opened + 1 end }
    CommanderOrders.Binding("MANAGER")
    EQ(opened, 1, "O: binding MANAGER toggles the manager")
    NOERR("O")
end)

-- ===========================================================================
-- P: with every file the TOC lists that exists
-- ===========================================================================
Section("P", function()
    M.Boot({ player = GOLDSHIRE })
    NOERR("P full TOC boot")
    O().Add({ map = 1429, x = 0.48, y = 0.42 })
    M.Advance(1)
    NOERR("P full TOC run")
end)

-- ===========================================================================
-- Q: what the consumers asked for (Entrance, Status, SharePoint,
-- OpenPaste(text)) and the arrow's outlined distance font
-- ===========================================================================
Section("Q", function()
    Boot({ player = GOLDSHIRE })
    -- Entrance: resolvers first, a COPY handed out, nil when nobody knows
    EQ(O().Entrance(347), nil, "Q: Entrance: nil when no resolver and no client entry knows")
    local door = { map = 1944, x = 0.477, y = 0.536, title = "Ramparts" }
    O().RegisterResolver("entrance", function(map) if map == 347 then return door end end)
    local e = O().Entrance(347)
    CHECK(e and e.map == 1944 and e.x == 0.477 and e.y == 0.536 and e.title == "Ramparts", "Q: Entrance: the resolver's door")
    CHECK(e ~= door, "Q: Entrance: a copy, never the resolver's table")
    e.x = 0.1
    EQ(door.x, 0.477, "Q: Entrance: editing the copy leaves the resolver's table alone")
    O().RegisterResolver("entrance", function() error("boom") end)
    CHECK(O().Entrance(347) ~= nil, "Q: Entrance: a resolver that raises is passed over")
    EQ(O().Entrance("x"), nil, "Q: Entrance: nil-safe")

    -- Status: the arrow's own words, nil without a target
    EQ(O().Status(), nil, "Q: Status: nil with no target")
    local uid = O().Add({ map = NORTHSHIRE[1], x = NORTHSHIRE[2], y = NORTHSHIRE[3], title = "Northshire" })
    Pass(2)
    local st = O().Status()
    CHECK(st and st.uid == uid and st.mode == "NAV" and st.title == "Northshire", "Q: Status: navigating to it",
        st and st.mode)
    EQ(st and st.zone, "Elwynn Forest", "Q: Status: the zone")
    EQ(st and st.distanceText, A().text.dist, "Q: Status: the distance exactly as the arrow words it")
    NEAR(st and st.distance, 582, 3, "Q: Status: 582 yd (the D1 walk)")
    st.title = "edited"
    EQ(Store():Get(uid).title, "Northshire", "Q: Status: a copy")
    O().Remove(uid)
    EQ(O().Status(), nil, "Q: Status: a removed target is never described, even before the next pass")
    uid = O().Add({ map = NORTHSHIRE[1], x = NORTHSHIRE[2], y = NORTHSHIRE[3], title = "Northshire" })
    Pass(2)
    DB().EnableOrders = false
    Notify()
    EQ(O().Status(), nil, "Q: Status: nil while Orders is off")
    DB().EnableOrders = true
    Notify()

    -- SharePoint: shared, never added, never pinned
    local count, pinned = Store():Count(), Store():Pinned()
    local ok, why = O().SharePoint({ map = 1429, x = 0.5, y = 0.5, title = "Rally" })
    CHECK(ok == nil and why == "not in a group", "Q: SharePoint: solo refused", why)
    M.SetGroup("party", { "Healer" })
    M.ClearLog()
    ok = O().SharePoint({ map = 1429, x = 0.5, y = 0.5, title = "Rally" })
    EQ(ok, true, "Q: SharePoint: sent")
    local msg = M.sent[#M.sent]
    EQ(msg and msg.text, "1:1429:0.50000:0.50000:Rally", "Q: SharePoint: Share's own wire")
    EQ(msg and msg.channel, "PARTY", "Q: SharePoint: the group's channel")
    EQ(Store():Count(), count, "Q: SharePoint: no waypoint added")
    EQ(Store():Pinned(), pinned, "Q: SharePoint: the arrow untouched")
    CHECK(M.Has(M.prints, "shared"), "Q: SharePoint: announced")
    M.ClearLog()
    O().SharePoint({ map = 1429, x = 0.5, y = 0.5, title = "Rally", silent = true })
    CHECK(not M.Has(M.prints, "shared"), "Q: SharePoint: silent says nothing")
    ok, why = O().SharePoint({ map = 1429, x = 1.5, y = 0.5 })
    CHECK(ok == nil and why == "invalid position", "Q: SharePoint: an impossible spot refused", why)
    ok, why = O().SharePoint({ map = 999999, x = 0.5, y = 0.5 })
    CHECK(ok == nil and why == "invalid position", "Q: SharePoint: an unknown map refused", why)
    O().SharePoint({ map = 1429, x = 0.5, y = 0.5, title = "Rally" }, "CHAT")
    local chat = M.chat[#M.chat]
    CHECK(chat and chat.chatType == "PARTY" and chat.text == "/way #1429 50.00 50.00 Rally",
        "Q: SharePoint: CHAT posts the /way line", chat and chat.text)
    -- Share and SharePoint are one send path: Share still answers the same
    M.W.sendResult = 3
    ok, why = O().Share(uid)
    CHECK(ok == nil and why == "too many messages, try again", "Q: Share: result words through the shared path", why)
    ok, why = O().SharePoint({ map = 1429, x = 0.5, y = 0.5 })
    CHECK(ok == nil and why == "too many messages, try again", "Q: SharePoint: the same result words", why)
    M.W.sendResult = 0

    -- OpenPaste(text) reaches the manager's paste box
    local got, calls = nil, 0
    CommanderOrders.UI = { OpenPaste = function(text) got, calls = text, calls + 1 end }
    O().OpenPaste("/way 45 66 Camp")
    EQ(got, "/way 45 66 Camp", "Q: OpenPaste(text) hands the text to the manager")
    O().OpenPaste()
    CHECK(calls == 2 and got == nil, "Q: OpenPaste() with no text hands none")
    NOERR("Q")

    -- A client without GameFontNormalLargeOutline: the arrow's distance
    -- falls back to GameFontNormalLarge with an outline, and SetText works
    -- (the mock serves fonts through _G's __index: a raw false hides one)
    Boot({ player = GOLDSHIRE, before = function() rawset(_G, "GameFontNormalLargeOutline", false) end })
    local dist = A().dist
    EQ(dist.__fontFlags, "OUTLINE", "Q: a missing outlined font: the stock one, outlined")
    O().Add({ map = NORTHSHIRE[1], x = NORTHSHIRE[2], y = NORTHSHIRE[3], title = "Northshire" })
    Pass(2)
    HAS(Text("dist"), "yd", "Q: ...and the distance is written")
    NOERR("Q fallback font")
end)

-- ===========================================================================
-- R: the review's fixes (each check names the lens that found it)
-- ===========================================================================
local function QuestieTracker()
    -- Questie's TrackerUtils:SetTomTomTarget, exactly (as in section H)
    local t = {}
    function t.Set(title, uiMapId, x, y)
        if TomTom and TomTom.AddWaypoint then
            if t.stored and TomTom.RemoveWaypoint then TomTom:RemoveWaypoint(t.stored) end
            t.stored = TomTom:AddWaypoint(uiMapId, x / 100, y / 100, { title = title, crazy = true, from = "Questie" })
        end
    end
    return t
end

Section("R", function()
    -- questie-shim: Questie moving on never removes a waypoint it does not
    -- own, whichever came first
    Boot({ player = GOLDSHIRE })
    local q = QuestieTracker()
    Way("37 71 Nazgrel")
    local mine = Store():Find(1429, 0.37, 0.71, "Nazgrel")
    CHECK(mine and mine.source == "user", "R: (the user's own /way)")
    q.Set("Nazgrel", 1429, 37, 71)
    EQ(Store():Count(), 1, "R: Questie's target on the same spot and title is the same record")
    q.Set("Rohok", 1429, 40, 60)
    CHECK(Store():Get(mine.uid) ~= nil and mine.source == "user",
        "R: Questie moving on leaves the user's own /way there (questie-shim)")
    EQ(#O().List({ source = "TomTom:Questie" }), 1, "R: ...and its new target is its only one")
    q.Set("Nazgrel", 1429, 37, 71)
    q.Set("Rohok", 1429, 40, 60)
    CHECK(Store():Get(mine.uid) ~= nil, "R: ...however often it comes back and goes")

    -- a group member's share, accepted before Questie targeted the spot
    Boot({ player = GOLDSHIRE })
    q = QuestieTracker()
    M.SetGroup("party", { "Partyguy" })
    M.Receive("CmdrOrders", "1:1429:0.37000:0.71000:Nazgrel", "PARTY", "Partyguy-Dreamscythe")
    M.ClickPopup("COMMANDER_ORDERS_SHARE", 1)
    local shared = Store():Find(1429, 0.37, 0.71, "Nazgrel")
    CHECK(shared and shared.source == "share:Partyguy", "R: (the accepted share)")
    q.Set("Nazgrel", 1429, 37, 71)
    q.Set("Rohok", 1429, 40, 60)
    CHECK(Store():Get(shared.uid) ~= nil and shared.source == "share:Partyguy",
        "R: Questie moving on leaves an accepted share there (questie-shim)")

    -- the other order: Questie first, then the user re-adds the same line
    Boot({ player = GOLDSHIRE })
    q = QuestieTracker()
    q.Set("Nazgrel", 1429, 37, 71)
    local theirs = Store():Find(1429, 0.37, 0.71, "Nazgrel")
    EQ(theirs and theirs.source, "TomTom:Questie", "R: (Questie's waypoint)")
    Way("37 71 Nazgrel")
    EQ(theirs.source, "user", "R: the user re-adding it makes it the user's")
    EQ(theirs.persistent, true, "R: ...kept across sessions, as the user's own are")
    q.Set("Rohok", 1429, 40, 60)
    CHECK(Store():Get(theirs.uid) ~= nil, "R: ...and Questie moving on leaves it (questie-shim)")
    -- a consumer's re-add does not claim it: only the user's own sources do
    q.Set("Goldtooth", 1429, 41, 61)
    local gt = Store():Find(1429, 0.41, 0.61, "Goldtooth")
    O().Add({ map = 1429, x = 0.41, y = 0.61, title = "Goldtooth", source = "Tradecraft", setArrow = false })
    EQ(gt.source, "TomTom:Questie", "R: another addon's re-add leaves it Questie's")
    q.Set("Rohok", 1429, 40, 60)
    EQ(Store():Get(gt.uid), nil, "R: ...and Questie removes its own as before")
    NOERR("R shim owners")

    -- questie-shim: a target on a continent map (Blackrock Mountain sits on
    -- 1415) is stored on the zone under it; after a reload Questie's stale
    -- uid still finds it
    Boot({ player = GOLDSHIRE })
    q = QuestieTracker()
    q.Set("Overmaster Pyron", 1415, 46.818, 67.705)
    local pyron = O().List({ source = "TomTom:Questie" })[1]
    CHECK(pyron and pyron.map ~= 1415, "R: (stored on the zone under the continent point)", pyron and pyron.map)
    local W2 = Reload({ extraSaved = { questie = q.stored } })
    q.stored = W2.restored.questie
    CHECK(q.stored and q.stored[1] == 1415, "R: (Questie's saved uid names the continent)")
    q.Set("Somebody", 1429, 50, 50)
    local left = O().List({ source = "TomTom:Questie" })
    CHECK(#left == 1 and left[1].title == "Somebody",
        "R: after a reload Questie's continent uid still removes its waypoint (questie-shim)", #left)
    NOERR("R shim continent")

    -- blizzard: a received title's UI escapes are dropped, on both wires
    Boot({ player = GOLDSHIRE })
    M.SetGroup("party", { "Prankster" })
    M.Receive("CmdrOrders", "1:1429:0.30000:0.40000:%7CTInterface%5CIcons%5CINV_Misc_QuestionMark%3A400%7Ct Look",
        "PARTY", "Prankster-Dreamscythe")
    local pop = M.popups[#M.popups]
    CHECK(pop and not tostring(pop.a2):find("|", 1, true), "R: no escape reaches the share dialog (blizzard)", pop and pop.a2)
    HAS(pop and pop.a2, "Look (Elwynn Forest 30.0, 40.0)", "R: ...the words stay, the texture goes whole")
    M.ClickPopup("COMMANDER_ORDERS_SHARE", 1)
    local got
    for _, wp in ipairs(O().List()) do if wp.source == "share:Prankster" then got = wp end end
    CHECK(got and got.title and not got.title:find("|", 1, true), "R: ...nor the stored title", got and got.title)
    DB().ListenTomTom = true
    Notify()
    M.Receive("TOMTOM4", "1429:0.400000:0.500000:|cffff0000Red|r |Hitem:19019|h[Thunderfury]|h", "PARTY",
        "Prankster-Dreamscythe")
    pop = M.popups[#M.popups]
    CHECK(pop and not tostring(pop.a2):find("|", 1, true), "R: TomTom's raw wire too", pop and pop.a2)
    HAS(pop and pop.a2, "Red [Thunderfury] (", "R: ...a colour goes, a link keeps its words")

    -- blizzard: every Orders dialog draws over the maximized world map
    M.ShowMap(1429)
    M.SetMapMaximized(true)
    local mapStrata = WorldMapFrame:GetFrameStrata()
    EQ(mapStrata, "FULLSCREEN", "R: (the maximized map is FULLSCREEN, over UIParent's DIALOG)")
    CHECK(pop and M.StrataOver(pop.dialog:GetFrameStrata(), mapStrata), "R: the share dialog over it (blizzard)",
        pop and pop.dialog:GetFrameStrata())
    CommanderOrders.R.CopyLine("/way #1429 30.00 40.00 Look")
    pop = M.popups[#M.popups]
    CHECK(pop.which == "COMMANDER_ORDERS_COPY" and M.StrataOver(pop.dialog:GetFrameStrata(), mapStrata),
        "R: the copy box over it")
    O().Command("clearall")
    pop = M.popups[#M.popups]
    CHECK(pop.which == "COMMANDER_ORDERS_CLEAR_ALL" and M.StrataOver(pop.dialog:GetFrameStrata(), mapStrata),
        "R: the clear-all question over it")
    M.SetMapMaximized(false)
    M.HideMap()
    NOERR("R escapes and dialogs")

    -- review-runtime: "Add" on a share never moves the arrow off your own
    -- waypoint, even through Follow the Closest; "Add and go" does
    Boot({ player = GOLDSHIRE })
    M.SetGroup("party", { "Bob" })
    O().Add({ map = 1429, x = 0.48, y = 0.42, title = "Quest giver", source = "QuestLog", key = "q", setArrow = false })
    Pass(6)
    local act = O().Active()
    CHECK(act and act.title == "Quest giver" and act.why == "CLOSEST", "R: (the closest of your own)")
    M.Receive("CmdrOrders", "1:1429:0.42300:0.65000:Over here", "PARTY", "Bob-Dreamscythe")
    M.ClickPopup("COMMANDER_ORDERS_SHARE", 1)
    Pass(6)
    EQ(O().Active() and O().Active().title, "Quest giver", "R: an added share leaves the arrow on yours (review-runtime)")
    DB().ShareAccept = "GROUP_AUTO_ADD"
    Notify()
    M.Receive("CmdrOrders", "1:1429:0.42400:0.65100:Over there", "PARTY", "Bob-Dreamscythe")
    Pass(6)
    CHECK(Store():Find(1429, 0.424, 0.651, "Over there") ~= nil, "R: (auto-added from the group)")
    EQ(O().Active() and O().Active().title, "Quest giver", "R: ...as does one added quietly from the group")
    O().RemoveBy("QuestLog", "q")
    Pass(6)
    act = O().Active()
    CHECK(act and act.source == "share:Bob" and act.why == "CLOSEST",
        "R: with nothing of your own left, Follow the Closest can point at a share", act and act.title)
    M.Advance(11)
    M.Receive("CmdrOrders", "1:1429:0.43000:0.66000:Go here", "GUILD", "Guildie-Dreamscythe")
    M.ClickPopup("COMMANDER_ORDERS_SHARE", 3)
    EQ(Store():Pinned() and Store():Pinned().title, "Go here", "R: Add and go pins it")
    EQ(Store():Pinned().temporary, false, "R: ...as a waypoint of your own")
    NOERR("R shares")

    -- review-runtime: Mark arrived on a kept mark moves the arrow on
    Boot({ player = GOLDSHIRE })
    DB().KeepMyMarks = true
    Notify()
    local kept = O().Add({ map = 1429, x = 0.48, y = 0.42, title = "Mine" })
    O().Add({ map = 1429, x = 0.5, y = 0.5, title = "Other", setArrow = false })
    Pass(3)
    EQ(O().Active().title, "Mine", "R: (the kept mark has the arrow)")
    O().MarkArrived(kept)
    Pass(3)
    CHECK(O().Get(kept) and O().Get(kept).reached ~= nil, "R: Mark arrived stamps a kept mark reached (review-runtime)")
    EQ(O().Active() and O().Active().title, "Other", "R: ...and the arrow moves on, not back to it")

    -- review-runtime: a temporary offer leaves a running route alone
    Boot({ player = GOLDSHIRE })
    O().AddRoute({ title = "My trip", source = "Tradecraft", key = "trip", stops = {
        { map = 1429, x = 0.48, y = 0.42, title = "Stop A" }, { map = 1429, x = 0.50, y = 0.40, title = "Stop B" } } })
    Pass(3)
    O().Add({ map = 1429, x = 0.40, y = 0.60, title = "Repair: Smith", source = "Logistics", key = "repair",
              setArrow = true, temporary = true })
    Pass(3)
    act = O().Active()
    CHECK(act and act.title == "Stop A" and act.why == "ROUTE",
        "R: Adjutant's repair offer leaves the route on the arrow (review-runtime)", act and act.title)

    -- review-runtime: Guide me hands the arrow back when the crossing is made
    -- anywhere but on the hop's own spot (portal, hearthstone, the far end)
    local function GuideBoot()
        Boot({ player = { 1419, 0.58, 0.50 } })
        local t = O().Add({ map = 1955, x = 0.5, y = 0.5, title = "Shattrath bank" })
        Pass(3)
        local h = O().Guide()
        Pass(3)
        return t, h
    end
    local target, hop = GuideBoot()
    EQ(Store():Pinned() and Store():Pinned().uid, hop, "R: (Guide me pins the hop)")
    M.SetPlayer(1944, 0.8735, 0.5027)
    M.Fire("PLAYER_ENTERING_WORLD")
    M.Fire("ZONE_CHANGED_NEW_AREA")
    M.Advance(1)
    EQ(O().Get(hop), nil, "R: through the portal off the hop's spot: the hop goes (review-runtime)")
    EQ(Store():Pinned() and Store():Pinned().uid, target, "R: ...the target is pinned again")
    EQ(A().view.mode, "NAV", "R: ...and the arrow points at it, not back through the portal")
    target, hop = GuideBoot()
    O().Remove(hop)
    Pass(2)
    EQ(Store():Pinned() and Store():Pinned().uid, target, "R: removing the hop by hand hands the arrow back")
    target, hop = GuideBoot()
    O().MarkArrived(hop)
    Pass(2)
    EQ(Store():Pinned() and Store():Pinned().uid, target, "R: so does Mark arrived on it")
    target, hop = GuideBoot()
    local elsewhere = O().Add({ map = 1419, x = 0.45, y = 0.45, title = "Elsewhere" })
    Pass(2)
    O().Remove(hop)
    Pass(2)
    EQ(Store():Pinned() and Store():Pinned().uid, elsewhere, "R: once you picked something else, the guide lets go")
    NOERR("R guide")

    -- review-runtime: following a group member costs no map positions (each
    -- one a Vector2D) beyond the player's own, once a second
    Boot({ player = GOLDSHIRE })
    M.SetGroup("party", { "Bob" })
    M.SetUnit("party1", 1429, 0.45, 0.60)
    local bob = O().Add({ kind = "unit", unit = "party1", title = "Bob", source = "PartyFrames", key = "follow" })
    Pass(5)
    EQ(A().view.mode, "NAV", "R: (following Bob)")
    local calls = { pos = 0, world = 0, state = 0 }
    local gpmp, gwpf = C_Map.GetPlayerMapPosition, C_Map.GetWorldPosFromMapPos
    C_Map.GetPlayerMapPosition = function(...) calls.pos = calls.pos + 1 return gpmp(...) end
    C_Map.GetWorldPosFromMapPos = function(...) calls.world = calls.world + 1 return gwpf(...) end
    local st = Store()
    local stateFn = st.State
    st.State = function(...) calls.state = calls.state + 1 return stateFn(...) end
    M.Advance(10)
    C_Map.GetPlayerMapPosition, C_Map.GetWorldPosFromMapPos, st.State = gpmp, gwpf, nil
    CHECK(calls.pos <= 12, "R: 10 s following: about one map position a second, the player's (review-runtime)", calls.pos)
    CHECK(calls.world <= 2, "R: ...and no world-position lookups", calls.world)
    EQ(calls.state, 0, "R: the 10 Hz pass reads the arrival state without a copy")
    local _, bn, bw = M.World(1429, 0.45, 0.60)
    local pp = M.W.player
    local want = math.sqrt((pp.north - bn) ^ 2 + (pp.west - bw) ^ 2)
    NEAR(A().view.distance, want, 0.01, "R: ...the distance is still the member's")
    M.SetUnit("party1", 1944, 0.5, 0.5)
    Pass(3)
    EQ(A().view.mode, "OTHER", "R: a member on another landmass: OTHER")
    EQ(Text("dist"), "In Outland", "R: ...named")
    -- review-r2 orders: there the 10 Hz pass cannot measure, so the Store
    -- asks for the member's map position every tick; it hands on the
    -- runtime's one table a unit, never a copy (1.6 KB/s before)
    local bc = R().Ctx()
    local bp1 = Store():Position(bob, bc)
    local bp2 = Store():Position(bob, bc)
    CHECK(bp1 ~= nil and rawequal(bp1, bp2), "R: ...the member's position is one reused table, not a copy a tick (review-r2)")
    -- UnitPosition blind for the member, the map position kept: the arrow's
    -- frame reads the Store's position, and its world position stays cached
    -- (a fresh table a frame missed the cache: 17 lookups a second)
    M.SetUnit("party1", 1429, 0.45, 0.60)
    M.SetUnitNoWorld("party1", true)
    Pass(3)
    calls.world = 0
    C_Map.GetWorldPosFromMapPos = function(...) calls.world = calls.world + 1 return gwpf(...) end
    M.Advance(10)
    C_Map.GetWorldPosFromMapPos = gwpf
    CHECK(A().view.mode ~= "UNIT_LOST", "R: UnitPosition blind, the map position kept: still placed", A().view.mode)
    CHECK(calls.world <= 2, "R: ...and no world-position lookup a frame (review-r2)", calls.world)
    M.SetUnitNoWorld("party1", false)
    NOERR("R follow")

    -- render: the status line wraps inside the arrow's own width
    local AR = CommanderOrders.Data.ARROW
    EQ(A().status.__w, AR.WIDTH, "R: the status line is the arrow's width (render)")
    EQ(A().status.__wordWrap, true, "R: ...and wraps")
    EQ(A().status.__maxLines, 2, "R: ...to two lines at most")

    -- review-runtime: the Window style's close button is not undone ten
    -- times a second, and Reset Position still reopens it
    Boot({ player = GOLDSHIRE })
    O().Add({ map = 1429, x = 0.48, y = 0.42, title = "Northshire" })
    DB().ArrowStyle = "WINDOW"
    Notify()
    M.Advance(0.5)
    local root = O().R.Arrow()
    local win = root._hudWindow
    CHECK(win and win.CloseButton, "R: (the window has its close button)")
    local shows = 0
    root:HookScript("OnShow", function() shows = shows + 1 end)
    win.CloseButton.__scripts.OnClick(win.CloseButton)
    M.Advance(2)
    CHECK(shows <= 1, "R: a closed window is not re-shown every pass (review-runtime)", shows)
    EQ(root:IsShown(), false, "R: ...and stays closed")
    local reset
    for _, w in ipairs(M.W.widgets) do
        if w.__text == "Reset Position" and w.__scripts and w.__scripts.OnClick then reset = w end
    end
    CHECK(reset ~= nil, "R: (the page's Reset Position button)")
    if reset then reset.__scripts.OnClick(reset) end
    M.Advance(0.5)
    EQ(root:IsShown(), true, "R: Reset Position reopens it")
    NOERR("R window")

    -- review-runtime: the readouts, the copied line and a share say the
    -- spawn the arrow follows, not the primary one
    Boot({ player = GOLDSHIRE })
    M.SetGroup("party", { "Bob" })
    O().Add({ title = "Giver", source = "QuestLog", key = "quest:7", map = 1436, x = 0.5, y = 0.5,
              alternatives = { { map = 1436, x = 0.5, y = 0.5 }, { map = 1429, x = 0.43, y = 0.64 } } })
    Pass(3)
    local status = O().Status()
    CHECK(status and status.map == 1429 and math.abs(status.x - 0.43) < 1e-9, "R: Status names the spawn followed",
        status and (tostring(status.map) .. " " .. tostring(status.x)))
    EQ(status and status.zone, "Elwynn Forest", "R: ...in its zone")
    local line = O().WayLine(status and status.uid)
    HAS(line, "/way #1429 43.00 64.00 Giver", "R: the copied /way line too")
    O().Share(status and status.uid)
    EQ(M.sent[#M.sent].text, "1:1429:0.43000:0.64000:Giver", "R: and the share")
    Corder("arrow")
    HAS(M.prints[#M.prints], "Elwynn Forest 43.0, 64.0", "R: and /corder arrow")
    M.SetModifier("SHIFT", true)
    M.Hover(A().hit)
    M.SetModifier("SHIFT", false)
    CHECK(M.Has(M.tooltip, "Elwynn Forest 43.0, 64.0"), "R: and the arrow's tooltip")
    NOERR("R alternatives")

    -- review-surfaces: paste errors are numbered by the box's own lines
    Boot({ player = GOLDSHIRE })
    local added, errs = O().Import("/way 45 66 First\n\n/way Elwynn Forest 12 Second\n\n\n/way Nowhereland 50 50 Third")
    EQ(added, 1, "R: (one line added)")
    EQ(errs[1] and errs[1].line, 3, "R: a bad line after a blank one is line 3 (review-surfaces)")
    EQ(errs[2] and errs[2].line, 6, "R: ...after three blank ones, line 6")
    added, errs = O().Import("/way 45 66 A\r\n\r\nnot a line")
    EQ(errs[1] and errs[1].line, 3, "R: Windows line ends count the same")
    NOERR("R import")
end)

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
