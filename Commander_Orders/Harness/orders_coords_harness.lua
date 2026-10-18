-- Commander Orders: the coordinates harness (luajit).
--
--     luajit Commander_Orders/Harness/orders_coords_harness.lua
--     ORDERS_COORDS=/tmp/mutant.lua luajit Commander_Orders/Harness/orders_coords_harness.lua
--     MINIMAP_FILE=/tmp/mutant.lua  luajit Commander_Orders/Harness/orders_coords_harness.lua
--
-- Drives CommanderOrdersCoords.lua (3.1, SPEC 4 COORDS) over orders_mock.lua:
-- the real settings framework and HUD chrome (Commander_Events), the real
-- runtime, Geo, Store and pins, and, in sections G and H, the REAL
-- Commander_Minimap/CommanderMinimap.lua, loaded before Orders as the client
-- loads it (alphabetical; it lists no dependency on Orders). The manager,
-- the chat links and the locator are left out: this harness answers for the
-- coordinates alone (the runtime harness boots every TOC file).
--
--   A  load: CommanderOrders.Coords, the block built at login, unnamed, no
--      new global, a quiet login, the HUD chrome (Solid plate under the
--      minimap), the click surface under the drag overlay; a login in
--      combat waits to chrome and refuses nothing
--   B  reading: zone numbers from UnitPosition with no Vector2D (no map
--      position asked in ten seconds, two world probes per map, kept), a
--      cave's map climbs to its zone, "--" without a position, the
--      battleground hedge, the taxi (no movement event), the 0.2 s
--      throttle and write-on-change, CoordDecimals 0..2
--   C  the block's words and size: subzone over zone, the zone alone, the
--      unlocked (the chrome's drag label alone), zone events, D11
--   D  gestures on the block: click (a waypoint where you stand, named for a
--      creature you target), Shift (into the chat box, else your group's
--      chat or /say, never a link), Ctrl (the /way copy box), Right (the
--      menu and every entry), the tooltip, no position, Orders off
--   E  settings and chrome: Coordinate Block, the master switch, style,
--      scale, position, unlock and the overlay's right-click lock, combat
--      changes nothing and refuses nothing
--   F  /corder coords: toggle, on/off, lock/unlock, reset, 0/1/2, where,
--      usage, through the real slash wrapper
--   G  Commander_Minimap's label: under the zone name, Orders' numbers,
--      written on change only, Minimap Coordinates / Orders off hide it,
--      "--", its click surface over the text only, the gestures, the tidy
--   H  Ctrl+Right-click on the minimap: no ping (the wrapper), every other
--      click pings as before, the placement round trip against
--      Geo.MinimapPlace (north up, rotated, zoom, indoors, a 1.37 scale),
--      the square's corners, outside the face, past the zone's edge (the
--      zone beside it; Eversong to Ghostlands in 530), inside an instance,
--      Minimap Click / Orders off

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local M = dofile(HERE .. "/orders_mock.lua")
local ADDONS = M.ADDONS
local COORDS_PATH = os.getenv("ORDERS_COORDS") or (M.ORDERS .. "/CommanderOrdersCoords.lua")
local MINIMAP_PATH = os.getenv("MINIMAP_FILE") or (ADDONS .. "/Commander_Minimap/CommanderMinimap.lua")

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
local function Section(name, fn)
    local ok, err = pcall(fn)
    CHECK(ok, name .. ": ran to the end", err)
end

-- ---------------------------------------------------------------------------
-- The client this file reads beyond the mock: zone words, the cursor, the
-- target, the chat box; Commander_Minimap's frames (sections G, H)
-- ---------------------------------------------------------------------------
local CLIENT

local function LoadFile(path, label)
    local chunk, err = loadfile(path)
    if not chunk then
        M.loadErrors[#M.loadErrors + 1] = label .. ": " .. tostring(err)
        return false
    end
    local ok, runErr = pcall(chunk)
    if not ok then M.loadErrors[#M.loadErrors + 1] = label .. ": " .. tostring(runErr) end
    return ok
end

local function InstallClient(m, w)
    CLIENT = { zone = "Elwynn Forest", sub = "Goldshire", cx = 0, cy = 0, target = nil, targetIsPlayer = false,
               chatBox = nil, inserted = {}, pings = 0, minimapZone = "Goldshire" }
    rawset(_G, "GetZoneText", function() return CLIENT.zone end)
    rawset(_G, "GetRealZoneText", function() return CLIENT.zone end)
    rawset(_G, "GetSubZoneText", function() return CLIENT.sub end)
    rawset(_G, "GetMinimapZoneText", function() return CLIENT.minimapZone end)
    rawset(_G, "GetCursorPosition", function() return CLIENT.cx, CLIENT.cy end)
    local unitName, unitExists = UnitName, UnitExists
    rawset(_G, "UnitName", function(unit)
        if unit == "target" then return CLIENT.target end
        return unitName(unit)
    end)
    rawset(_G, "UnitExists", function(unit)
        if unit == "target" then return CLIENT.target ~= nil end
        return unitExists(unit)
    end)
    rawset(_G, "UnitIsPlayer", function(unit)
        if unit == "target" then return CLIENT.targetIsPlayer end
        return unit == "player"
    end)
    -- ChatFrameUtil.GetActiveWindow / InsertLink (Shared/ChatFrameUtil.lua:421,
    -- Classic/ChatFrameUtilOverrides.lua)
    local util = ChatFrameUtil
    util.GetActiveWindow = function() return CLIENT.chatBox end
    util.InsertLink = function(text)
        if not CLIENT.chatBox then return false end
        CLIENT.inserted[#CLIENT.inserted + 1] = text
        return true
    end
    -- Blizzard's Minimap_OnClick, the handler the wrapper must keep: a ping
    -- for any button (Classic/Minimap.lua:130-141)
    w.minimap.__scripts.OnMouseUp = function() CLIENT.pings = CLIENT.pings + 1 end
    -- a screen point for the minimap's centre (its own units)
    rawset(w.minimap, "GetCenter", function() return 1500, 900 end)
end

-- The stock frames Commander_Minimap hides or moves (pins harness K's set)
local function MinimapStubs(m)
    rawset(_G, "MinimapCluster", { BorderTop = m.NewWidget("Frame", nil, nil) })
    for _, name in ipairs({ "MinimapZoomOut", "MinimapZoomIn", "MinimapToggleButton", "MinimapNorthTag",
            "MinimapBorder", "GameTimeFrame", "MinimapZoneTextButton" }) do
        rawset(_G, name, m.NewWidget("Button", nil, nil))
    end
    rawset(_G, "COMMANDER_MINIMAP_EVENTS", { COMMANDER_MINIMAP = "COMMANDER_MINIMAP" })
    rawset(_G, "CommanderMinimapDB", { TidyAddonButtons = true, TidyFadedOpacity = 0, BoardStyle = "NONE",
                                       MinimapScale = 1.37, LockMinimap = false })
end

local SKIP = { CommanderOrdersCoords = true, CommanderOrdersUI = true, CommanderOrdersChat = true,
               CommanderOrdersLocate = true }

-- opts.minimap: Commander_Minimap's file runs before any Orders file (the
-- client's alphabetical order), its ADDON_LOADED after Orders' login
local function Prepare(opts)
    opts = opts or {}
    opts.skipFiles = SKIP
    local userBefore, userAfter = opts.before, opts.afterFiles
    local minimap = opts.minimap
    opts.before = function(m, w)
        InstallClient(m, w)
        if minimap then
            MinimapStubs(m)
            w.phase = "minimap"
            LoadFile(MINIMAP_PATH, "CommanderMinimap.lua")
            w.phase = "boot"
        end
        if userBefore then userBefore(m, w) end
    end
    opts.afterFiles = function(m, w)
        LoadFile(COORDS_PATH, "CommanderOrdersCoords.lua")
        if userAfter then userAfter(m, w) end
    end
    return opts
end

-- The block is opt-in (CoordsBlock off by default, the lead's decision:
-- D39); every section but A's default checks boots as a player who turned
-- it on (opts.defaultBlock: leave the default alone)
local function Boot(opts)
    opts = opts or {}
    local minimap = opts.minimap
    if not opts.defaultBlock then
        -- a saved 3.1 settings table with the block turned on, as the
        -- player's own after /corder coords
        opts.saved = opts.saved or {}
        local db = opts.saved.CommanderOrdersDB or { DBVersion = 3, EnableOrders = true }
        if db.CoordsBlock == nil then db.CoordsBlock = true end
        opts.saved.CommanderOrdersDB = db
    end
    local w = M.Boot(Prepare(opts))
    if minimap then
        M.Fire("ADDON_LOADED", "Commander_Minimap")
        M.Fire("PLAYER_ENTERING_WORLD", false, false)
    end
    return w
end

local function O() return CommanderOrders end
local function C() return CommanderOrders.Coords end
local function I() return CommanderOrders.Coords._Internals() end
local function B() return I().B end
local function R() return CommanderOrders.R end
local function Store() return CommanderOrders.R.Store() end
local function DB() return CommanderOrdersDB end
local function Notify() Commander.Notify(COMMANDER_ORDERS_EVENTS.UPDATE) end
local function Corder(msg) SlashCmdList.COMMANDERUI_ORDERS(msg) end
local function Shown(region) return region and region.__shown and true or false end
local function LastPoint(frame)
    local pts = frame and frame.__points
    return pts and pts[#pts] or nil
end
local function Tip() return table.concat(M.tooltip, "\n") end
local function Last(list) return list[#list] end

local GOLDSHIRE = { 1429, 0.42, 0.655 }
local OUTDOOR = { 1400 / 3, 1400 / 3 / (7 / 6), 1400 / 3 / 1.4, 1400 / 3 / 1.75, 1400 / 3 / (7 / 3), 1400 / 3 / 3.5 }
local ALLOWED = {
    CommanderOrders = true, CommanderOrdersDB = true, CommanderOrdersChar = true, COMMANDER_ORDERS_EVENTS = true,
    CommanderOrders_IssueOrder = true, CommanderOrders_ClearOrder = true, CommanderOrders_RallySet = true,
    CommanderOrders_RallyGo = true, CommanderOrders_RallyList = true, CommanderOrdersArrow = true,
    CommanderOrdersMenu = true, TomTom = true, BINDING_HEADER_COMMANDERORDERS = true,
    SLASH_COMMANDERUI_ORDERS1 = true, CommanderUIScrollOrders = true,
}

-- The waypoint the arrow is pinned to, as a world point
local function PinnedWorld()
    local wp = Store():Pinned()
    if not wp then return nil end
    return wp, M.World(wp.map, wp.x, wp.y)
end

-- ===========================================================================
-- A: load
-- ===========================================================================
Section("A", function()
    local W = Boot({ player = GOLDSHIRE, defaultBlock = true })
    NOERR("A login")
    EQ(#M.prints, 0, "A: a quiet login")
    local c = C()
    EQ(type(c), "table", "A: CommanderOrders.Coords")
    for _, name in ipairs({ "Read", "Text", "Here", "Gesture", "Tooltip", "Waypoint", "Share", "Copy", "Menu",
            "MinimapText", "WantsMinimapClick", "MinimapPoint", "MinimapClick", "Command" }) do
        EQ(type(c[name]), "function", "A: Coords." .. name)
    end
    local bad = {}
    for _, name in ipairs(M.OrdersWrites()) do
        local ok = ALLOWED[name] or name:match("^BINDING_NAME_COMMANDERORDERS_%u+$")
            or name:match("^SLASH_COMMANDERORDERS_%u+%d$") or name:match("^CommanderUIDropDown%d+$")
        if not ok then bad[#bad + 1] = name end
    end
    EQ(#bad, 0, "A: no global beyond the documented ones", table.concat(bad, " "))

    local b = B()
    local root = b.root
    CHECK(root ~= nil, "A: the block is built at login")
    EQ(root:GetName(), nil, "A: unnamed (no global; the minimap tidy collects by name)")
    EQ(root.__parent, UIParent, "A: on UIParent (hidden with the interface)")
    EQ(root.__strata, "LOW", "A: LOW strata (under dialogs and menus)")
    -- the lead's decision (D39): the block is opt-in; the minimap's label
    -- is the default surface
    EQ(DB().CoordsBlock, false, "A: CoordsBlock defaults OFF")
    CHECK(not Shown(root), "A: ...so a fresh login shows no block")
    EQ(DB().MinimapCoords, true, "A: ...while the minimap's coordinates default on")
    M.ClearLog()
    C().Gesture("RightButton", { surface = "minimap", anchor = "cursor" })
    HAS(table.concat(M.MenuTexts(), "|"), "Show the coordinate block", "A: the minimap's menu offers the block")
    M.ClickMenu("Show the coordinate block")
    EQ(DB().CoordsBlock, true, "A: ...which turns it on")
    CHECK(Shown(root), "A: ...and shows it")
    C().Gesture("RightButton", { surface = "minimap", anchor = "cursor" })
    CHECK(not table.concat(M.MenuTexts(), "|"):find("Show the coordinate block", 1, true),
        "A: ...and is not offered again while it shows")
    local pt = LastPoint(root)
    CHECK(pt and pt.point == "TOP" and pt.rel == UIParent and pt.relPoint == "TOP" and pt.x == 240
        and pt.y == -504, "A: under the Orders arrow's default box (TOP +240, -504), clear of the quest tracker",
        pt and (pt.point .. " " .. tostring(pt.x) .. " " .. tostring(pt.y)))
    -- review (render): 2.5.6 manages QuestWatchFrame in a right-aligned
    -- column from 192 down (RIGHT_CONTAINER_OFFSET_Y), up to about 290
    -- wide; the block's default rectangle stays out of it, and below the
    -- arrow's default box (TOP +240, -340, 190 x 158)
    local AR = O().Data.ARROW
    local uiW = UIParent:GetWidth() or 1024
    local left = uiW / 2 + pt.x - 150 / 2
    local right = left + 150
    CHECK(right < uiW - 290 or -pt.y + 62 < 192, "A: ...outside the tracker's right column", right)
    CHECK(-pt.y >= -AR.DEFAULT_POINT.y + AR.HEIGHT, "A: ...and below the arrow's box", pt.y)
    EQ(root.__w, 150, "A: 150 wide")
    EQ(b.chromeReady, true, "A: chromed at login")
    EQ(DB().CoordsStyle, "SOLID", "A: (the Solid plate by default)")
    CHECK(root._hudBackdrop and Shown(root._hudBackdrop), "A: the plate is drawn")
    CHECK(root.__passThrough and root.__passThrough[1] == "LeftButton", "A: the chrome's pass-through ran (out of combat)")
    EQ(#M.blocked, 0, "A: no protected call refused")
    local hit = b.hit
    CHECK(hit ~= nil and hit.__parent == root, "A: the click surface is a child of the block")
    EQ(hit.__allPoints, root, "A: ...covering it")
    EQ(hit.__mouse, true, "A: ...and mouse-enabled")
    EQ(table.concat(hit.__clicks or {}, ","), "LeftButtonUp,RightButtonUp", "A: left and right clicks")
    EQ(hit:GetFrameLevel(), root:GetFrameLevel() + 5, "A: five levels up")
    CHECK(hit:GetFrameLevel() < root._hudDragOverlay:GetFrameLevel(), "A: under the chrome's drag overlay")
    EQ(hit:GetName(), nil, "A: unnamed too")
    M.Advance(0.3)
    EQ(b.coords.__text, "42.0, 65.5", "A: your coordinates")
    NOERR("A end")

    -- A login in combat waits to chrome
    W = Boot({ player = GOLDSHIRE, combat = true })
    b = B()
    EQ(DB().CoordsBlock, true, "A: a saved CoordsBlock = true is kept (a default change, no migration)")
    EQ(b.chromeReady, false, "A: combat login: no chrome yet")
    EQ(b.chromePending, true, "A: ...pending")
    EQ(b.root.__passThrough, nil, "A: SetPassThroughButtons not even tried in combat")
    EQ(#M.blocked, 0, "A: nothing refused")
    CHECK(Shown(b.root), "A: shown all the same")
    pt = LastPoint(b.root)
    CHECK(pt and pt.point == "TOP" and pt.x == 240, "A: at its default point")
    M.Advance(0.3)
    EQ(b.coords.__text, "42.0, 65.5", "A: and reading in combat")
    M.SetCombat(false)
    EQ(b.chromeReady, true, "A: chromed when combat ends")
    CHECK(b.root.__passThrough and b.root.__passThrough[1] == "LeftButton", "A: the pass-through set out of combat")
    EQ(#M.blocked, 0, "A: still nothing refused")
    NOERR("A combat login")
end)

-- ===========================================================================
-- B: reading where you stand
-- ===========================================================================
Section("B", function()
    Boot({ player = GOLDSHIRE })
    local b = B()
    M.Advance(0.3)
    local map, x, y = C().Read()
    EQ(map, 1429, "B: Elwynn Forest")
    NEAR(x, 0.42, 1e-9, "B: x from UnitPosition through the zone's rectangle")
    NEAR(y, 0.655, 1e-9, "B: y")
    EQ(C().Text(), "42.0, 65.5", "B: one decimal by default")
    EQ(C().Text(0), "42, 66", "B: no decimals")
    EQ(C().Text(2), "42.00, 65.50", "B: two decimals")

    -- no Vector2D five times a second: the map position is never asked, the
    -- world rectangle is probed once per map
    local calls = { pos = 0, world = 0 }
    local gpmp, gwpf = C_Map.GetPlayerMapPosition, C_Map.GetWorldPosFromMapPos
    C_Map.GetPlayerMapPosition = function(...) calls.pos = calls.pos + 1 return gpmp(...) end
    C_Map.GetWorldPosFromMapPos = function(...) calls.world = calls.world + 1 return gwpf(...) end
    local reads = I().S.reads
    M.Advance(10)
    EQ(calls.pos, 0, "B: ten seconds of readings: no map position asked (no Vector2D)")
    EQ(calls.world, 0, "B: ...and no world probe once the zone is known")
    -- (0.2 s on 1/30 s frames: every seventh frame, 43 in ten seconds)
    CHECK(I().S.reads - reads >= 40 and I().S.reads - reads <= 52, "B: about five readings a second",
        I().S.reads - reads)
    M.SetPlayer(1436, 0.5, 0.5)
    M.Advance(0.3)
    EQ(calls.world, 2, "B: a new zone: two probes for its rectangle")
    EQ(b.coords.__text, "50.0, 50.0", "B: Westfall's numbers")
    M.SetPlayer(1429, 0.42, 0.655)
    M.Advance(0.3)
    EQ(calls.world, 2, "B: back in Elwynn: kept, no probe")
    C_Map.GetPlayerMapPosition, C_Map.GetWorldPosFromMapPos = gpmp, gwpf

    -- a cave's own map climbs to its zone (the numbers the world map and
    -- every /way line use)
    local inst, n, w = M.World(1429, 0.42, 0.655)
    M.MAPS[9001] = { "Fargodeep Mine", 5, 1429 }
    M.ROWS[9001] = { { 0, n - 100, w - 100, n + 100, w + 100, 0, 0, 1, 1 } }
    M.SetPlayerWorld(inst, n, w, 9001)
    M.Advance(0.3)
    map, x, y = C().Read()
    EQ(map, 1429, "B: in a cave (a micro map): the zone's numbers")
    EQ(b.coords.__text, "42.0, 65.5", "B: ...on the block")
    M.MAPS[9001], M.ROWS[9001] = nil, nil
    -- a map in another world instance never answers for this one, however
    -- its numbers line up (Arathi Basin, 529, over Hillsbrad's, 0)
    M.SetPlayerWorld(0, 350, 500, 1461)
    M.Frame()
    EQ(C().Read(), nil, "B: a best map of another instance: no numbers from it")
    M.SetPlayer(1429, 0.42, 0.655)

    -- the taxi: no movement event, the numbers move anyway (critic 1.6)
    local writes = b.writes
    M.Advance(1)
    EQ(b.writes, writes, "B: standing still: nothing written")
    M.SetTaxi(true)
    M.SetPlayer(1429, 0.45, 0.66)
    M.Frame(0.05)
    EQ(b.coords.__text, "42.0, 65.5", "B: within 0.2 s it waits")
    M.Advance(0.2)
    EQ(b.coords.__text, "45.0, 66.0", "B: on a taxi, with no movement event: it follows")
    EQ(b.writes, writes + 1, "B: one write for one change")
    M.SetPlayer(1429, 0.4504, 0.66)
    M.Advance(0.25)
    EQ(b.writes, writes + 1, "B: a move inside the last decimal writes nothing")
    M.SetTaxi(false)

    -- no position: "--"
    M.SetNoPosition(true)
    M.Advance(0.25)
    EQ(b.coords.__text, "--", "B: no position: --")
    EQ(C().Text(), "--", "B: ...Text says so")
    local spec, why = C().Here()
    EQ(spec, nil, "B: ...nothing to point at")
    EQ(why, "no position", "B: ...in the open: no position")
    M.SetInstance("party")
    spec, why = C().Here()
    EQ(why, "instance", "B: in a dungeon: the instance reason")
    M.SetInstance(nil)
    M.SetNoPosition(false)
    M.Advance(0.25)
    EQ(b.coords.__text, "45.0, 66.0", "B: back")

    -- the battleground hedge (D6): no UnitPosition, the map position places you
    M.SetPlayer(1461, 0.40, 0.40)
    M.SetInstance("pvp")
    local real = UnitPosition
    rawset(_G, "UnitPosition", function(unit) if unit == "player" then return nil end return real(unit) end)
    M.Advance(0.3)
    EQ(b.coords.__text, "40.0, 40.0", "B: a battleground with no UnitPosition: the hedge's numbers")
    rawset(_G, "UnitPosition", nil)
    M.SetInstance(nil)
    M.SetPlayer(1429, 0.42, 0.655)

    -- decimals follow the setting
    DB().CoordDecimals = 2
    Notify()
    M.Advance(0.25)
    EQ(b.coords.__text, "42.00, 65.50", "B: Coordinate Decimals 2")
    DB().CoordDecimals = 0
    Notify()
    M.Advance(0.25)
    EQ(b.coords.__text, "42, 66", "B: Coordinate Decimals 0")
    DB().CoordDecimals = 1
    Notify()
    NOERR("B end")
end)

-- ===========================================================================
-- C: the block's words and size
-- ===========================================================================
Section("C", function()
    Boot({ player = GOLDSHIRE })
    local b = B()
    M.Advance(0.3)
    EQ(b.sub.__text, "Goldshire", "C: the subzone, gold")
    EQ(b.sub.__font, "GameFontNormalSmall", "C: (GameFontNormalSmall)")
    EQ(b.zone.__text, "Elwynn Forest", "C: the zone under it")
    CHECK(Shown(b.zone), "C: ...shown")
    EQ(b.root.__h, 50, "C: three lines: 50 tall")
    EQ(b.coords.__font, "GameFontHighlightLarge", "C: the numbers in the large font")
    EQ(b.sub.__wordWrap, false, "C: place lines never wrap (cut to the block's width)")
    EQ(b.sub.__w, 142, "C: ...142 wide inside the 150 block")

    CLIENT.sub = ""
    M.Fire("ZONE_CHANGED")
    M.Advance(0.25)
    EQ(b.sub.__text, "Elwynn Forest", "C: no subzone: the zone, in gold")
    CHECK(not Shown(b.zone), "C: ...and no third line")
    EQ(b.root.__h, 38, "C: two lines: 38 tall")
    CLIENT.sub = "Elwynn Forest"
    M.Fire("ZONE_CHANGED_INDOORS")
    M.Advance(0.25)
    EQ(b.sub.__text, "Elwynn Forest", "C: a subzone named as its zone: said once")
    CHECK(not Shown(b.zone), "C: ...two lines")
    CLIENT.sub, CLIENT.zone = "Light's Hope Chapel", "Eastern Plaguelands"
    M.Fire("ZONE_CHANGED_NEW_AREA")
    M.Advance(0.25)
    EQ(b.sub.__text, "Light's Hope Chapel", "C: a zone event: the new subzone")
    EQ(b.zone.__text, "Eastern Plaguelands", "C: ...and zone")
    EQ(b.root.__h, 50, "C: three lines again")
    CLIENT.sub, CLIENT.zone = "Goldshire", "Elwynn Forest"
    M.Fire("PLAYER_ENTERING_WORLD", false, false)
    M.Advance(0.25)
    EQ(b.sub.__text, "Goldshire", "C: a loading screen: read again")
    -- the words wait for a zone event (they are not read five times a second)
    CLIENT.sub = "Somewhere else"
    M.Advance(1)
    EQ(b.sub.__text, "Goldshire", "C: no zone event: the place words stay")
    M.Fire("ZONE_CHANGED")
    M.Advance(0.25)
    EQ(b.sub.__text, "Somewhere else", "C: ...until one comes")
    CLIENT.sub = "Goldshire"
    M.Fire("ZONE_CHANGED")

    -- in a dungeon: "--" over the instance's name
    CLIENT.zone, CLIENT.sub = "The Deadmines", ""
    M.SetInstance("party")
    M.SetNoPosition(true)
    M.Fire("ZONE_CHANGED_NEW_AREA")
    M.Advance(0.25)
    EQ(b.coords.__text, "--", "C: in a dungeon: --")
    EQ(b.sub.__text, "The Deadmines", "C: ...over the instance's name")
    CHECK(Shown(b.root), "C: ...and the block stays")
    M.SetInstance(nil)
    M.SetNoPosition(false)
    CLIENT.zone, CLIENT.sub = "Elwynn Forest", "Goldshire"
    M.Fire("ZONE_CHANGED_NEW_AREA")

    -- unlocked: how to put it down
    Corder("coords unlock")
    M.Advance(0.25)
    EQ(b.sub.__text, "", "C: unlocked: the place lines step aside for the chrome's drag label")
    EQ(b.zone.__text, "", "C: ...both")
    EQ(b.root.__h, 62, "C: ...62 tall, the numbers over the chrome's centred label")
    CHECK(Shown(b.root._hudDragOverlay), "C: ...(the chrome's drag overlay is up)")
    EQ(b.coords.__text, "42.0, 65.5", "C: ...the numbers still live")
    Corder("coords lock")
    M.Advance(0.25)
    EQ(b.sub.__text, "Goldshire", "C: locked: the place again")
    EQ(b.root.__h, 50, "C: ...at its own height")
    for _, key in ipairs({ "coords", "sub", "zone" }) do
        CHECK(not tostring(b[key].__text or ""):find("[\128-\255]"), "C: " .. key .. ": plain ASCII (D11)")
    end
    NOERR("C end")
end)

-- ===========================================================================
-- D: the gestures on the block
-- ===========================================================================
Section("D", function()
    local W = Boot({ player = GOLDSHIRE })
    local b = B()
    local hit = b.hit
    M.Advance(0.3)

    -- click: a waypoint where you stand, the arrow on it
    M.ClearLog()
    CHECK(M.Click(hit, "LeftButton"), "D: the block takes a click")
    local wp = Store():Pinned()
    CHECK(wp ~= nil, "D: click: a waypoint, the arrow on it")
    EQ(wp and wp.map, 1429, "D: ...on the zone")
    NEAR(wp and wp.x, 0.42, 1e-9, "D: ...where you stand (x)")
    NEAR(wp and wp.y, 0.655, 1e-9, "D: ...(y)")
    EQ(wp and wp.source, "user", "D: ...yours")
    EQ(wp and wp.title, nil, "D: ...untitled (Orders names it Zone x, y)")
    CHECK(M.Has(M.prints, "waypoint set: Elwynn Forest 42.0, 65.5"), "D: ...announced", M.prints[1])
    M.Advance(0.5)
    CHECK(Store():Get(wp.uid) ~= nil, "D: born where you stand, it does not arrive at once")
    O().Remove(wp.uid)

    -- a creature targeted names it (TomTom's habit); a player does not
    CLIENT.target = "Hogger"
    M.Click(hit, "LeftButton")
    wp = Store():Pinned()
    EQ(wp and wp.title, "Hogger", "D: a creature targeted: named after it")
    O().Remove(wp.uid)
    CLIENT.targetIsPlayer = true
    CLIENT.target = "Bob"
    M.Click(hit, "LeftButton")
    wp = Store():Pinned()
    EQ(wp and wp.title, nil, "D: a player targeted: not named after them")
    O().Remove(wp.uid)
    CLIENT.target, CLIENT.targetIsPlayer = nil, false

    -- Shift: into the chat box being typed in, the readable line
    local line = O().ChatText(1429, 0.42, 0.655)
    HAS(line, "Elwynn Forest 42.0, 65.5 (/way #1429 42.00 65.50)", "D: (the readable line)")
    CLIENT.chatBox = {}
    M.ClearLog()
    M.SetModifier("SHIFT", true)
    M.Click(hit, "LeftButton")
    M.SetModifier("SHIFT", false)
    EQ(Last(CLIENT.inserted), line, "D: Shift with a chat box open: the readable line goes into it")
    CHECK(not tostring(Last(CLIENT.inserted)):find("|H", 1, true), "D: ...never a link (links are local only)")
    EQ(#M.chat, 0, "D: ...nothing sent")
    EQ(Store():Pinned(), nil, "D: ...and no waypoint")
    CLIENT.chatBox = nil
    -- no chat box: your group's chat, else /say (Orders' Share, as GoButton)
    M.SetModifier("SHIFT", true)
    M.Click(hit, "LeftButton")
    M.SetModifier("SHIFT", false)
    local sent = Last(M.chat)
    EQ(sent and sent.text, line, "D: Shift, solo: the readable line")
    EQ(sent and sent.chatType, "SAY", "D: ...in /say")
    EQ(sent and sent.api, "C_ChatInfo", "D: ...through C_ChatInfo.SendChatMessage")
    M.SetGroup("party", { "Bob" })
    M.SetModifier("SHIFT", true)
    M.Click(hit, "LeftButton")
    M.SetModifier("SHIFT", false)
    sent = Last(M.chat)
    EQ(sent and sent.chatType, "PARTY", "D: Shift in a group: party chat")

    -- Ctrl: the /way line in the copy box
    M.ClearLog()
    M.SetModifier("CTRL", true)
    M.Click(hit, "LeftButton")
    M.SetModifier("CTRL", false)
    local pop = Last(M.popups)
    EQ(pop and pop.which, "COMMANDER_ORDERS_COPY", "D: Ctrl: the copy box")
    EQ(pop and pop.dialog.editBox.__text, "/way #1429 42.00 65.50", "D: ...with the /way line (two decimals)")
    EQ(pop and pop.dialog.editBox.__maxLetters, 255, "D: ...255 letters")
    EQ(Store():Pinned(), nil, "D: ...and no waypoint")

    -- Right: the menu
    M.Click(hit, "RightButton")
    local texts = table.concat(M.MenuTexts(), "|")
    EQ(M.menu[1] and M.menu[1].text, "Goldshire - Elwynn Forest", "D: the menu's title: where you are")
    EQ(M.menu[1] and M.menu[1].isTitle, true, "D: ...a title")
    for _, want in ipairs({ "Waypoint here", "Share in chat", "Send to your group", "Copy /way line",
            "0 decimals (45, 66)", "1 decimal (45.2, 66.8)", "2 decimals (45.25, 66.80)", "Unlock to move",
            "Hide this block", "Open the manager" }) do
        HAS(texts, want, "D: menu: " .. want)
    end
    for _, e in ipairs(M.menu) do
        if e.text == "1 decimal (45.2, 66.8)" then EQ(e.disabled, true, "D: menu: the current precision is greyed") end
        if e.text == "2 decimals (45.25, 66.80)" then CHECK(not e.disabled, "D: menu: the others are not") end
    end
    CHECK(not texts:find("[\128-\255]"), "D: menu: plain ASCII (D11)")
    CHECK(M.ClickMenu("Waypoint here"), "D: menu: Waypoint here")
    wp = Store():Pinned()
    CHECK(wp and wp.map == 1429 and math.abs(wp.x - 0.42) < 1e-9, "D: ...a waypoint where you stand")
    O().Remove(wp and wp.uid)
    M.Click(hit, "RightButton")
    M.ClearLog()
    CHECK(M.ClickMenu("Send to your group"), "D: menu: Send to your group")
    EQ(#M.sent, 1, "D: ...one addon message to the group (Commander and TomTom users get an offer)")
    M.Click(hit, "RightButton")
    M.ClickMenu("Copy /way line")
    EQ(Last(M.popups).dialog.editBox.__text, "/way #1429 42.00 65.50", "D: menu: Copy /way line")
    M.Click(hit, "RightButton")
    M.ClearLog()
    M.ClickMenu("Share in chat")
    EQ(Last(M.chat) and Last(M.chat).text, line, "D: menu: Share in chat")
    M.Click(hit, "RightButton")
    M.ClickMenu("2 decimals (45.25, 66.80)")
    EQ(DB().CoordDecimals, 2, "D: menu: precision")
    M.Advance(0.25)
    EQ(b.coords.__text, "42.00, 65.50", "D: ...the block follows at once")
    M.Click(hit, "RightButton")
    M.ClickMenu("1 decimal (45.2, 66.8)")
    M.Click(hit, "RightButton")
    M.ClickMenu("Unlock to move")
    EQ(DB().CoordsLocked, false, "D: menu: unlock")
    CHECK(Shown(b.root._hudDragOverlay), "D: ...the drag overlay is up")
    M.Click(hit, "RightButton")
    HAS(table.concat(M.MenuTexts(), "|"), "Lock in place", "D: unlocked: the menu offers the lock")
    M.ClickMenu("Lock in place")
    EQ(DB().CoordsLocked, true, "D: menu: lock")
    M.Click(hit, "RightButton")
    M.ClickMenu("Hide this block")
    EQ(DB().CoordsBlock, false, "D: menu: hide")
    CHECK(not Shown(b.root), "D: ...hidden")
    HAS(Last(M.prints), "/corder coords brings it back", "D: ...saying how to bring it back")
    Corder("coords")
    CHECK(Shown(b.root), "D: /corder coords: back")
    M.SetGroup(nil)

    -- the tooltip
    M.Hover(hit)
    EQ(M.tooltip[1], "Goldshire - Elwynn Forest", "D: tooltip: where you are")
    EQ(M.tooltip[2], "Elwynn Forest 42.0, 65.5", "D: tooltip: the zone's numbers")
    HAS(Tip(), "Click: a waypoint where you stand", "D: tooltip: click")
    HAS(Tip(), "Shift-click: share in chat. Ctrl-click: copy a /way line.", "D: tooltip: Shift and Ctrl (GoButton's words)")
    HAS(Tip(), "Right-click: menu", "D: tooltip: right-click")
    CHECK(not Tip():find("[\128-\255]"), "D: tooltip: plain ASCII (D11)")
    hit.__scripts.OnLeave(hit)
    EQ(GameTooltip.__owner, nil, "D: leaving hides it")

    -- no position: nothing made up, the reason said
    M.SetNoPosition(true)
    M.Advance(0.25)
    M.ClearLog()
    M.Click(hit, "LeftButton")
    EQ(Store():Pinned(), nil, "D: no position: no waypoint")
    HAS(Last(M.prints), "No map position here", "D: ...the reason, in Orders' words")
    M.Click(hit, "RightButton")
    for _, e in ipairs(M.menu) do
        if e.text == "Waypoint here" or e.text == "Copy /way line" or e.text == "Share in chat" then
            EQ(e.disabled, true, "D: no position: " .. e.text .. " greyed")
        end
    end
    M.Hover(hit)
    HAS(Tip(), "No map position here", "D: no position: the tooltip says why")
    M.SetInstance("party")
    M.Hover(hit)
    HAS(Tip(), "No position inside instances", "D: in a dungeon: the instance words")
    M.SetInstance(nil)
    M.SetNoPosition(false)

    -- Orders off: hidden, and a gesture says so
    DB().EnableOrders = false
    Notify()
    CHECK(not Shown(b.root), "D: Orders off: the block is hidden")
    M.ClearLog()
    C().Gesture("LeftButton", {})
    HAS(Last(M.prints), "Commander Orders is turned off (/corder)", "D: Orders off: a gesture says so")
    DB().EnableOrders = true
    Notify()
    CHECK(Shown(b.root), "D: on again: shown")
    EQ(#W.map.writes, 0, "D: nothing assigned to WorldMapFrame")
    NOERR("D end")
end)

-- ===========================================================================
-- E: settings and chrome
-- ===========================================================================
Section("E", function()
    Boot({ player = GOLDSHIRE })
    local b = B()
    local root = b.root
    DB().CoordsBlock = false
    Notify()
    CHECK(not Shown(root), "E: Coordinate Block off: hidden")
    local acc = b.acc
    M.Advance(1)
    EQ(b.acc, acc, "E: hidden: no reading (OnUpdate stops with the frame)")
    DB().CoordsBlock = true
    Notify()
    CHECK(Shown(root), "E: on: shown")
    DB().CoordsStyle = "NONE"
    Notify()
    CHECK(not Shown(root._hudBackdrop), "E: style None: no plate")
    DB().CoordsStyle = "DARK"
    Notify()
    CHECK(Shown(root._hudBackdrop), "E: style Dark: a plate")
    DB().CoordsStyle = "SOLID"
    DB().CoordsScale = 1.3
    Notify()
    EQ(root.__scale, 1.3, "E: Frame Scale")
    DB().CoordsPos = { point = "CENTER", x = 13, y = 26 }
    Notify()
    local pt = LastPoint(root)
    CHECK(pt and pt.point == "CENTER" and math.abs(pt.x - 10) < 1e-9 and math.abs(pt.y - 20) < 1e-9,
        "E: a saved position (screen units over the scale)", pt and (pt.point .. " " .. pt.x .. " " .. pt.y))
    Corder("coords reset")
    pt = LastPoint(root)
    CHECK(pt and pt.point == "TOP" and pt.x == 240, "E: /corder coords reset: back under the arrow")
    DB().CoordsScale = 1

    -- unlocked: shown even with the block off (a frame to drag), the
    -- overlay's right-click locks it and the block follows
    DB().CoordsBlock = false
    DB().CoordsLocked = false
    Notify()
    CHECK(Shown(root), "E: unlocked: shown even with the block off (something to drag)")
    CHECK(Shown(root._hudDragOverlay), "E: ...the drag overlay")
    root._hudDragOverlay.__scripts.OnMouseUp(root._hudDragOverlay, "RightButton")
    EQ(DB().CoordsLocked, true, "E: the overlay's right-click locks")
    CHECK(not Shown(root), "E: ...and the block, still off, goes")
    DB().CoordsBlock = true
    Notify()

    -- combat: the layout does not change, nothing protected is tried
    M.SetCombat(true)
    M.Advance(0.3)
    CHECK(Shown(root), "E: in combat: still shown (combat layout unchanged)")
    DB().CoordsStyle = "DARK"
    Notify()
    M.Click(b.hit, "LeftButton")
    CHECK(Store():Pinned() ~= nil, "E: a click in combat still makes a waypoint (nothing protected)")
    M.SetCombat(false)
    EQ(#M.blocked, 0, "E: nothing refused in combat")
    NOERR("E end")
end)

-- ===========================================================================
-- F: /corder coords
-- ===========================================================================
Section("F", function()
    Boot({ player = GOLDSHIRE })
    local b = B()
    M.Advance(0.3)
    M.ClearLog()
    Corder("coords")
    EQ(DB().CoordsBlock, false, "F: /corder coords toggles it off")
    CHECK(not Shown(b.root), "F: ...hidden")
    Corder("coords")
    EQ(DB().CoordsBlock, true, "F: ...and on")
    CHECK(Shown(b.root), "F: ...shown")
    Corder("coords off")
    EQ(DB().CoordsBlock, false, "F: off")
    Corder("coords ON")
    EQ(DB().CoordsBlock, true, "F: ON (any case)")
    Corder("coords hide")
    EQ(DB().CoordsBlock, false, "F: hide")
    Corder("coords show")
    EQ(DB().CoordsBlock, true, "F: show")
    Corder("coords unlock")
    EQ(DB().CoordsLocked, false, "F: unlock")
    HAS(Last(M.prints), "drag it into place", "F: ...says how")
    Corder("coords lock")
    EQ(DB().CoordsLocked, true, "F: lock")
    Corder("coords off")
    Corder("coords unlock")
    EQ(DB().CoordsBlock, true, "F: unlocking a hidden block shows it")
    Corder("coords lock")
    Corder("coords 2")
    EQ(DB().CoordDecimals, 2, "F: /corder coords 2")
    Corder("coords 0")
    EQ(DB().CoordDecimals, 0, "F: /corder coords 0")
    Corder("coords 1")
    EQ(DB().CoordDecimals, 1, "F: /corder coords 1")
    M.ClearLog()
    Corder("coords where")
    HAS(Last(M.prints), "you are at Elwynn Forest 42.0, 65.5", "F: where: the place")
    HAS(Last(M.prints), "|Haddon:CommanderOrders:w:1429:0.4200:0.6550:|h[Go]|h", "F: ...with its [Go] link")
    Corder("coords sideways")
    HAS(Last(M.prints), "/corder coords [on | off | lock | unlock | reset | 0 | 1 | 2 | where]", "F: anything else: usage")
    -- straight to the API too
    O().Command("coords", "off")
    EQ(DB().CoordsBlock, false, "F: CommanderOrders.Command(\"coords\", \"off\")")
    O().Command("coords", "on")
    NOERR("F end")
end)

-- ===========================================================================
-- G: Commander_Minimap's label
-- ===========================================================================
local function MinimapParts()
    local zoneText, coordText, hit, driver
    for _, child in ipairs(Minimap.__children) do
        local pt = child.__points and child.__points[1]
        if child.__kind == "FontString" then
            if pt and pt.rel == Minimap and pt.point == "TOP" then zoneText = child end
            if pt and type(pt.rel) == "table" and pt.rel.__kind == "FontString" then coordText = child end
        end
    end
    for _, child in ipairs(Minimap.__children) do
        local pt = child.__points and child.__points[1]
        if child.__kind == "Button" and pt and pt.rel == coordText then hit = child end
        if child.__kind == "Frame" and child.__scripts.OnUpdate and child ~= CommanderOrders.Pins._Internals().Mini.driver
            and not child.__points then
            driver = driver or child
        end
    end
    return zoneText, coordText, hit, driver
end

Section("G", function()
    local W = Boot({ player = GOLDSHIRE, minimap = true })
    NOERR("G boot")
    EQ(GetMinimapShape and GetMinimapShape(), "SQUARE", "G: (Commander_Minimap is in: the square mask)")
    local zoneText, coordText, hit, driver = MinimapParts()
    CHECK(zoneText ~= nil, "G: (its zone name)")
    CHECK(coordText ~= nil, "G: the coordinate label")
    local pt = coordText and coordText.__points[1]
    CHECK(pt and pt.point == "TOP" and pt.rel == zoneText and pt.relPoint == "BOTTOM", "G: under the zone name")
    EQ(coordText and coordText.__font, GameFontHighlightSmall, "G: GameFontHighlightSmall")
    M.Advance(0.3)
    EQ(coordText.__text, "42.0, 65.5", "G: Orders' numbers")
    CHECK(Shown(coordText), "G: shown (Minimap Coordinates on by default)")
    EQ(DB().MinimapCoords, true, "G: (MinimapCoords defaults on)")
    CHECK(hit ~= nil, "G: a click surface over the text")
    EQ(hit and hit.__parent, Minimap, "G: ...a child of the Minimap")
    EQ(hit and hit:GetName(), nil, "G: ...unnamed (the tidy collects by name)")
    EQ(hit and #hit.__points, 2, "G: ...anchored to the text's two corners only")
    CHECK(Shown(hit), "G: ...shown with the label")
    CHECK(driver ~= nil and driver:GetName() == nil, "G: an unnamed driver on the Minimap")

    -- written only on change
    local sets = 0
    local base = coordText.SetText
    rawset(coordText, "SetText", function(self, text) sets = sets + 1 return base(self, text) end)
    M.Advance(2)
    EQ(sets, 0, "G: standing still: nothing written")
    M.SetPlayer(1429, 0.43, 0.655)
    M.Advance(0.25)
    EQ(coordText.__text, "43.0, 65.5", "G: moving: it follows (no event needed)")
    EQ(sets, 1, "G: ...one write")
    DB().CoordDecimals = 2
    Notify()
    M.Advance(0.25)
    EQ(coordText.__text, "43.00, 65.50", "G: Coordinate Decimals")
    DB().CoordDecimals = 1
    Notify()

    -- five times a second, not every frame
    local asks = 0
    local text = CommanderOrders.Coords.MinimapText
    CommanderOrders.Coords.MinimapText = function(...) asks = asks + 1 return text(...) end
    M.Advance(1)
    CommanderOrders.Coords.MinimapText = text
    CHECK(asks >= 4 and asks <= 6, "G: the label asks about five times a second", asks)

    -- the settings and the master switch
    DB().MinimapCoords = false
    Notify()
    M.Advance(0.25)
    CHECK(not Shown(coordText) and not Shown(hit), "G: Minimap Coordinates off: the label and its surface go")
    DB().MinimapCoords = true
    Notify()
    M.Advance(0.25)
    CHECK(Shown(coordText) and Shown(hit), "G: on again")
    DB().EnableOrders = false
    Notify()
    M.Advance(0.25)
    CHECK(not Shown(coordText), "G: Orders off: no label")
    DB().EnableOrders = true
    Notify()
    M.Advance(0.25)
    M.SetNoPosition(true)
    M.Advance(0.25)
    EQ(coordText.__text, "--", "G: no position: --")
    M.SetNoPosition(false)
    M.SetPlayer(1429, 0.42, 0.655)
    M.Advance(0.25)

    -- the gestures (Orders' one rule)
    M.ClearLog()
    CHECK(M.Click(hit, "LeftButton"), "G: the label takes a click")
    local wp = Store():Pinned()
    CHECK(wp and wp.map == 1429 and math.abs(wp.x - 0.42) < 1e-9, "G: click: a waypoint where you stand")
    EQ(CLIENT.pings, 0, "G: ...and no ping (the label's own surface)")
    O().Remove(wp and wp.uid)
    M.SetModifier("CTRL", true)
    M.Click(hit, "LeftButton")
    M.SetModifier("CTRL", false)
    EQ(Last(M.popups) and Last(M.popups).which, "COMMANDER_ORDERS_COPY", "G: Ctrl-click: the copy box")
    M.Click(hit, "RightButton")
    local texts = table.concat(M.MenuTexts(), "|")
    HAS(texts, "Hide the minimap coordinates", "G: right-click: the menu, with its own hide")
    CHECK(not texts:find("Hide this block", 1, true), "G: ...not the block's")
    CHECK(not texts:find("Unlock", 1, true), "G: ...nor the block's lock")
    M.ClickMenu("Hide the minimap coordinates")
    EQ(DB().MinimapCoords, false, "G: ...which turns the setting off")
    M.Advance(0.25)
    CHECK(not Shown(coordText), "G: ...and the label goes")
    DB().MinimapCoords = true
    Notify()
    M.Advance(0.25)
    M.Hover(hit)
    EQ(M.tooltip[1], "Goldshire - Elwynn Forest", "G: hover: Orders' card")
    HAS(Tip(), "Click: a waypoint where you stand", "G: ...with the hints")

    -- the tidy never fades any of it
    M.Fire("PLAYER_ENTERING_WORLD", false, false)
    M.Advance(0.3)
    CHECK(coordText.__alpha == nil and hit.__alpha == nil and driver.__alpha == nil,
        "G: the button tidy never fades the label, its surface or its driver")
    -- written by Commander_Minimap: nothing but the shape function
    for _, w in ipairs(M.writes) do
        if w.phase == "minimap" then CHECK(false, "G: Commander_Minimap's file writes no global at load", w.name) end
    end
    NOERR("G end")
end)

-- ===========================================================================
-- H: Ctrl+Right-click on the minimap
-- ===========================================================================
-- The cursor at a point `px, py` Minimap units from its centre (screen
-- pixels: the minimap's effective scale times its own units)
local function CursorAt(px, py)
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = Minimap:GetCenter()
    CLIENT.cx, CLIENT.cy = (cx + px) * scale, (cy + py) * scale
end

local function MinimapUp(button)
    Minimap.__scripts.OnMouseUp(Minimap, button or "RightButton")
end

local function CtrlRight()
    M.SetModifier("CTRL", true)
    MinimapUp("RightButton")
    M.SetModifier("CTRL", false)
end

-- Place a click where Geo would draw a pin dN north and dW west of you, and
-- check the waypoint lands there (yards)
local function RoundTrip(dN, dW, label, opts)
    opts = opts or {}
    local G = CommanderOrders.Geo
    local p = M.W.player
    local zoom = M.W.zoom or 0
    local indoors = G.MinimapIndoors(zoom, M.W.cvars.minimapZoom, M.W.cvars.minimapInsideZoom, M.W.indoors)
    local radius = G.MinimapRadius(zoom, indoors)
    local rotate = M.W.cvars.rotateMinimap == "1"
    local px, py, edge = G.MinimapPlace(dN, dW, radius, M.W.facing, rotate, "SQUARE", 70, 70)
    CHECK(not edge, label .. ": (inside the map's face)")
    CursorAt(px, py)
    local before = CLIENT.pings
    local had = Store():Pinned()
    CtrlRight()
    local wp, inst, n, w = PinnedWorld()
    CHECK(wp ~= nil and wp ~= had, label .. ": a waypoint", wp and wp.uid)
    EQ(CLIENT.pings, before, label .. ": no ping")
    if wp then
        EQ(inst, p.inst, label .. ": same instance")
        NEAR(n, p.north + dN, opts.eps or 0.05, label .. ": north")
        NEAR(w, p.west + dW, opts.eps or 0.05, label .. ": west")
        if opts.map then EQ(wp.map, opts.map, label .. ": on " .. tostring(opts.map)) end
        O().Remove(wp.uid)
    end
    return wp
end

Section("H", function()
    local W = Boot({ player = GOLDSHIRE, minimap = true })
    EQ(Minimap:GetEffectiveScale(), 1.37, "H: (Commander_Minimap's 1.37 scale)")
    -- the wrapper keeps whatever was there for every other click
    EQ(CLIENT.pings, 0, "H: (no ping yet)")
    CursorAt(10, 10)
    MinimapUp("RightButton")
    EQ(CLIENT.pings, 1, "H: a plain right-click pings, as before")
    MinimapUp("LeftButton")
    EQ(CLIENT.pings, 2, "H: a left-click pings, as before")
    M.SetModifier("CTRL", true)
    MinimapUp("LeftButton")
    M.SetModifier("CTRL", false)
    EQ(CLIENT.pings, 3, "H: Ctrl+Left pings (only Ctrl+Right is ours)")
    EQ(Store():Pinned(), nil, "H: ...and makes nothing")
    M.SetModifier("CTRL", true)
    M.SetModifier("SHIFT", true)
    MinimapUp("RightButton")
    M.SetModifier("SHIFT", false)
    M.SetModifier("CTRL", false)
    EQ(CLIENT.pings, 4, "H: Ctrl+Shift+Right pings (Ctrl alone is ours)")
    EQ(Store():Pinned(), nil, "H: ...and makes nothing")

    -- Ctrl+Right-click: the waypoint, no ping
    M.ClearLog()
    RoundTrip(60, -40, "H: north-east, north up")
    CHECK(M.Has(M.prints, "waypoint set:"), "H: ...announced like a map click", M.prints[1])
    RoundTrip(-100, 150, "H: south-west")
    RoundTrip(0, 0, "H: on you")
    -- a 1.37 scale or none: the cursor is divided out
    rawset(Minimap, "GetEffectiveScale", function() return 1 end)
    RoundTrip(80, 80, "H: at scale 1")
    rawset(Minimap, "GetEffectiveScale", nil)
    -- zoom levels and indoors
    M.SetZoom(3)
    W.cvars.minimapZoom = "3"
    RoundTrip(40, -30, "H: zoom 3 (the outdoor table)")
    W.cvars.minimapZoom = "0"
    W.cvars.minimapInsideZoom = "3"
    RoundTrip(20, 10, "H: zoom 3 indoors (the indoor table)")
    W.cvars.minimapInsideZoom = "0"
    M.SetZoom(0)
    -- rotating minimap: turned back by your facing (the inverse of Geo's turn)
    W.cvars.rotateMinimap = "1"
    M.SetFacing(0.6)
    RoundTrip(90, 40, "H: rotated, facing 0.6")
    M.SetFacing(2.5)
    RoundTrip(-50, -120, "H: rotated, facing 2.5")
    M.SetFacing(nil)
    CursorAt(10, 10)
    M.ClearLog()
    CtrlRight()
    EQ(Store():Pinned(), nil, "H: rotated with no heading: nothing guessed")
    HAS(Last(M.prints), "no waypoint there", "H: ...said")
    M.SetFacing(0)
    W.cvars.rotateMinimap = "0"

    -- the square's corners are the map (Blizzard's circle test is not ours)
    local radius = CommanderOrders.Geo.MinimapRadius(0, false)
    CursorAt(66, 66)
    CtrlRight()
    local wp, inst, n, w = PinnedWorld()
    CHECK(wp ~= nil, "H: a square map's corner takes a waypoint")
    if wp then
        local p = M.W.player
        NEAR(n, p.north + 66 / 70 * radius, 0.05, "H: ...that far north")
        NEAR(w, p.west - 66 / 70 * radius, 0.05, "H: ...and east")
        O().Remove(wp.uid)
    end
    CursorAt(72, 0)
    M.ClearLog()
    local pings = CLIENT.pings
    CtrlRight()
    EQ(Store():Pinned(), nil, "H: past the face: nothing")
    EQ(#M.prints, 0, "H: ...and nothing said")
    EQ(CLIENT.pings, pings, "H: ...and no ping")
    -- a round minimap (another addon's shape): the corners are not the map
    local square = GetMinimapShape
    rawset(_G, "GetMinimapShape", function() return "ROUND" end)
    CursorAt(66, 66)
    CtrlRight()
    EQ(Store():Pinned(), nil, "H: round: a corner is off the map")
    CursorAt(40, 40)
    CtrlRight()
    CHECK(Store():Pinned() ~= nil, "H: round: inside the rim it is")
    if Store():Pinned() then O().Remove(Store():Pinned().uid) end
    rawset(_G, "GetMinimapShape", square)

    -- past the zone's edge: the zone beside it
    M.SetPlayer(1429, 0.5, 0.985)
    RoundTrip(-200, 0, "H: south of Elwynn's edge: Duskwood", { map = 1431 })
    M.SetPlayer(1941, 0.5, 0.98)
    RoundTrip(-200, 0, "H: south of Eversong (530): Ghostlands, not the 0 frame", { map = 1942 })
    RoundTrip(150, 0, "H: back inside Eversong", { map = 1941 })
    M.SetPlayer(1429, 0.42, 0.655)

    -- inside an instance: said, no ping
    M.SetInstance("party")
    M.SetNoPosition(true)
    CursorAt(10, 10)
    M.ClearLog()
    pings = CLIENT.pings
    CtrlRight()
    EQ(Store():Pinned(), nil, "H: in a dungeon: no waypoint")
    HAS(Last(M.prints), "no waypoint there: No position inside instances", "H: ...said in Orders' words")
    EQ(CLIENT.pings, pings, "H: ...and still no ping")
    M.SetInstance(nil)
    M.SetNoPosition(false)

    -- the setting and the master switch hand the click back to the ping
    DB().MinimapClick = false
    Notify()
    pings = CLIENT.pings
    CtrlRight()
    EQ(CLIENT.pings, pings + 1, "H: Ctrl+Right-Click the Minimap off: it pings")
    EQ(Store():Pinned(), nil, "H: ...and makes nothing")
    DB().MinimapClick = true
    DB().EnableOrders = false
    Notify()
    CtrlRight()
    EQ(CLIENT.pings, pings + 2, "H: Orders off: it pings")
    DB().EnableOrders = true
    Notify()
    -- an error inside Orders never reaches the minimap
    local real = CommanderOrders.Coords.MinimapClick
    CommanderOrders.Coords.MinimapClick = function() error("boom") end
    pings = CLIENT.pings
    CtrlRight()
    EQ(CLIENT.pings, pings, "H: an Orders error: still no ping")
    CommanderOrders.Coords.MinimapClick = real
    EQ(#M.errors, 0, "H: ...and nothing raised (pcall'd)")
    -- in combat: the same (nothing protected)
    M.SetCombat(true)
    RoundTrip(30, 30, "H: in combat")
    M.SetCombat(false)
    EQ(#M.blocked, 0, "H: nothing refused")
    NOERR("H end")
end)

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
