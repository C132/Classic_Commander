-- Commander Orders: the pins harness (luajit).
--
--     luajit Commander_Orders/Harness/orders_pins_harness.lua
--     ORDERS_PINS=/tmp/mutant.lua luajit Commander_Orders/Harness/orders_pins_harness.lua
--
-- Drives CommanderOrdersPins.lua over orders_mock.lua: the real settings
-- framework and HUD chrome (Commander_Events), the real runtime, Geo and
-- Store, a map world made of this build's UiMap / UiMapAssignment rows, a
-- WorldMapFrame proxy that records every field written to it, and Blizzard's
-- AcquirePin order with its mouse wiring. Each section boots a fresh client.
-- CommanderOrdersUI.lua (the manager) is left out so this harness answers
-- for the pins alone; the runtime harness's section P boots every TOC file.
--
--   A  load: the hooks, no new global, nothing assigned to WorldMapFrame,
--      the pool and provider, the overlay with its pass-through set once
--   B  minimap: a pin for every waypoint on the player's landmass and none
--      for the rest (the 530 traps, a followed unit), unnamed, over Radar
--   C  minimap placement: round, square, rotated, edge clamp and edge angle,
--      zoom levels, indoor/outdoor, Minimap size, per-frame movement only
--      while pins are visible, MinimapEdge / MinimapPins off
--   D  minimap pins: tooltip, Shift-click, plain click, right-click menu,
--      the arrow's target ringed
--   E  world map: zone, continent, Azeroth and Outland projection, levels
--      above Questie's, clickable wiring, alternatives, corpse, reached,
--      refresh while open, WorldPins / EnableOrders off
--   F  routes: numbered badges, lines between stops, a passed leg dimmed,
--      a loop, legs across landmasses left out, RouteLines off, no CreateLine
--   G  world-pin clicks: click, right-click menu, Shift-drag on a zone and on
--      a continent, a press that never moves, the ocean
--   H  the map click overlay: modifier show/hide, exact modifiers, zone,
--      continent, ocean, Cosmic and dungeon clicks, ALT / OFF, a login in
--      combat, the pass-through never set again
--   I  coordinates: both lines for the viewed map, the throttle, windowed
--      mode, Questie's own coordinates, MapCoords off, the level
--   J  reload: pins come back with the waypoints; disabling hides everything
--   K  the real Commander_Minimap: GetMinimapShape is SQUARE with its mask,
--      its button tidy never fades an Orders pin, pins clamp to the square
--      (the top rim under its zone name)
--   L  Commander_QuestLog's drawer (the target alone over it, the running
--      route's other badges under it, the coordinates one under it),
--      refusals said on the map, two-digit minimap badges, the copy box
--      over the maximized map

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local M = dofile(HERE .. "/orders_mock.lua")
local ADDONS = M.ADDONS
local PINS_PATH = os.getenv("ORDERS_PINS") or (M.ORDERS .. "/CommanderOrdersPins.lua")

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
-- Widget additions the mock does not record: Line endpoints and thickness,
-- Minimap:GetChildren (for Commander_Minimap's tidy), and a count of every
-- SetPassThroughButtons call (it is protected; it must happen once)
-- ---------------------------------------------------------------------------
local WMT = getmetatable(M.NewWidget("Texture", nil, nil))
local baseIndex = WMT.__index
local basePass = baseIndex({}, "SetPassThroughButtons")
local passCalls = {}
local NO_LINES = false
local BROKEN_LINES = false      -- Line regions that refuse SetColorTexture
local EXTRA = {
    SetStartPoint = function(s, point, rel, x, y) s.__start = { point = point, rel = rel, x = x, y = y } end,
    SetEndPoint = function(s, point, rel, x, y) s.__end = { point = point, rel = rel, x = x, y = y } end,
    SetThickness = function(s, t) s.__thickness = t end,
    GetChildren = function(s) return unpack(s.__children or {}) end,
    SetPassThroughButtons = function(s, ...)
        passCalls[#passCalls + 1] = s
        return basePass(s, ...)
    end,
}
WMT.__index = function(self, key)
    if key == "CreateLine" and NO_LINES then return nil end
    if key == "SetColorTexture" and BROKEN_LINES and rawget(self, "__kind") == "Line" then
        return function() error("Line: SetColorTexture refused (harness)") end
    end
    local fn = EXTRA[key]
    if fn then return fn end
    return baseIndex(self, key)
end

-- ---------------------------------------------------------------------------
-- Boot: every TOC file but the manager; the pins load from PINS_PATH in their
-- TOC place (after the runtime, before ADDON_LOADED)
-- ---------------------------------------------------------------------------
local function LoadPins()
    local chunk, err = loadfile(PINS_PATH)
    if not chunk then
        M.loadErrors[#M.loadErrors + 1] = "CommanderOrdersPins.lua: " .. tostring(err)
        return
    end
    local ok, runErr = pcall(chunk)
    if not ok then M.loadErrors[#M.loadErrors + 1] = "CommanderOrdersPins.lua: " .. tostring(runErr) end
end

local function Prepare(opts)
    opts = opts or {}
    opts.skipFiles = { CommanderOrdersPins = true, CommanderOrdersUI = true }
    local userAfter = opts.afterFiles
    opts.afterFiles = function(m, w)
        LoadPins()
        if userAfter then userAfter(m, w) end
    end
    local userBefore = opts.before
    opts.before = function(m, w)
        for i = #passCalls, 1, -1 do passCalls[i] = nil end
        -- Commander_Radar's overlay: a LOW strata child of the Minimap
        local radar = CreateFrame("Frame", "CommanderRadarOverlay", Minimap)
        radar:SetFrameLevel(9)
        if userBefore then userBefore(m, w) end
    end
    return opts
end
local function Boot(opts) return M.Boot(Prepare(opts)) end
local function Reload(opts) return M.Reload(Prepare(opts)) end

local function O() return CommanderOrders end
local function R() return CommanderOrders.R end
local function Store() return CommanderOrders.R.Store() end
local function DB() return CommanderOrdersDB end
local function I() return CommanderOrders.Pins._Internals() end
local function Notify() Commander.Notify(COMMANDER_ORDERS_EVENTS.UPDATE) end
local function Settle(s) M.Advance(s or 0.25) end

local function WorldPins()
    return M.PoolPins(WorldMapFrame.pinPools[I().TEMPLATE])
end
local function PinsFor(uid)
    local out = {}
    for _, p in ipairs(WorldPins()) do
        if p.data and p.data.uid == uid then out[#out + 1] = p end
    end
    return out
end
local function MiniCount() return I().Mini.count end
local function MiniPinFor(uid)
    local mini = I().Mini
    for i = 1, mini.count do
        if mini.entries[i].uid == uid then return mini.pins[i] end
    end
    return nil
end
local function LastPoint(frame)
    local pts = frame and frame.__points
    return pts and pts[#pts] or nil
end
local function Shown(region) return region and region.__shown and true or false end
-- SetPassThroughButtons calls on the map-click overlay (the arrow's HUD
-- chrome makes its own, once, at login)
local function OverlayPass()
    local ov, n = I().Overlay.frame, 0
    for _, f in ipairs(passCalls) do if f == ov then n = n + 1 end end
    return n
end

-- The player's world point, and a waypoint `dN` yards north and `dW` west of it
local function PlayerWorld()
    local p = M.W.player
    return p.inst, p.north, p.west
end
local function AddOffset(dN, dW, title, map)
    map = map or M.W.player.map
    local inst, n, w = PlayerWorld()
    local x, y = M.MapPos(map, inst, n + dN, w + dW)
    assert(x, "AddOffset: no map position")
    return O().Add({ map = map, x = x, y = y, title = title, source = "user", setArrow = false })
end

-- The SPEC's placement (critic 3.2), written out again here: right is east
-- (-west), up is north; rotate by facing; clamp at 0.9 of the rim
local function Expect(dN, dW, radius, facing, rotate, square, halfW, halfH)
    local right, up = -dW, dN
    if rotate then
        local c, s = math.cos(facing), math.sin(facing)
        right, up = right * c + up * s, up * c - right * s
    end
    local nx, ny = right / radius, up / radius
    local d = square and math.max(nx * nx, ny * ny) or (nx * nx + ny * ny)
    d = d / 0.81
    local edge = d > 1
    if edge then
        local k = 1 / math.sqrt(d)
        nx, ny = nx * k, ny * k
    end
    return nx * halfW, ny * (halfH or halfW), edge, math.atan2(-nx, ny)
end

local GOLDSHIRE = { 1429, 0.42, 0.655 }
local OUTDOOR0 = 1400 / 3 / 2
local ALLOWED = {
    CommanderOrders = true, CommanderOrdersDB = true, CommanderOrdersChar = true, COMMANDER_ORDERS_EVENTS = true,
    CommanderOrders_IssueOrder = true, CommanderOrders_ClearOrder = true, CommanderOrders_RallySet = true,
    CommanderOrders_RallyGo = true, CommanderOrders_RallyList = true, CommanderOrdersArrow = true,
    CommanderOrdersMenu = true, TomTom = true, BINDING_HEADER_COMMANDERORDERS = true,
    SLASH_COMMANDERUI_ORDERS1 = true, CommanderUIScrollOrders = true,
}

-- ===========================================================================
-- A: load
-- ===========================================================================
Section("A", function()
    local W = Boot({ player = GOLDSHIRE })
    NOERR("A login")
    EQ(#M.prints, 0, "A: a quiet login")
    local P = O().Pins
    EQ(type(P), "table", "A: CommanderOrders.Pins")
    EQ(type(P.Refresh), "function", "A: Pins.Refresh (the runtime calls it after every change)")
    EQ(type(P.OnTarget), "function", "A: Pins.OnTarget (the runtime calls it when the arrow changes hands)")
    EQ(type(P.PlaceOnMap), "function", "A: Pins.PlaceOnMap")

    local bad = {}
    for _, name in ipairs(M.OrdersWrites()) do
        local ok = ALLOWED[name] or name:match("^BINDING_NAME_COMMANDERORDERS_%u+$")
            or name:match("^SLASH_COMMANDERORDERS_%u+%d$") or name:match("^CommanderUIDropDown%d+$")
        if not ok then bad[#bad + 1] = name end
    end
    EQ(#bad, 0, "A: no global beyond the documented ones", table.concat(bad, " "))
    for _, w in ipairs(M.writes) do
        CHECK(w.name ~= "GetMinimapShape", "A: Orders never defines GetMinimapShape (Commander_Minimap does)")
    end
    EQ(#W.map.writes, 0, "A: no WorldMapFrame field assigned", table.concat(W.map.writes, " "))
    local pool = WorldMapFrame.pinPools[I().TEMPLATE]
    CHECK(pool ~= nil, "A: our pool sits under WorldMapFrame.pinPools")
    EQ(I().TEMPLATE, "CommanderOrdersPinTemplate", "A: the pool key")
    EQ(#W.map.providers, 1, "A: one data provider added")
    EQ(W.map.providers[1], I().World.provider, "A: it is ours")
    EQ(type(pool.GetTemplate), "function", "A: an unsecured region pool (not the secure CreateFramePool proxy)")

    local ov = I().Overlay.frame
    CHECK(ov ~= nil, "A: the map-click overlay is built at login")
    EQ(ov.__parent, W.map.container, "A: the overlay is a child of the ScrollContainer")
    CHECK(not Shown(ov), "A: the overlay is hidden")
    EQ(OverlayPass(), 1, "A: SetPassThroughButtons called once on the overlay, at login")
    EQ(I().Overlay.passCalls, 1, "A: the module counted one call too")
    EQ(table.concat(ov.__passThrough or {}, ","), "LeftButton,MiddleButton,Button4,Button5",
        "A: left, middle, 4 and 5 pass through; only the right button is taken")
    EQ(ov:GetFrameLevel(), W.map.container:GetFrameLevel() + 3, "A: the overlay a few levels over the container")
    CHECK(ov:GetFrameLevel() < M.PIN_LEVELS.PIN_FRAME_LEVEL_AREA_POI, "A: the overlay under every map pin")
    EQ(ov.__scripts.OnEnter, nil, "A: the overlay has no tooltip of its own")

    local coords = I().Coords.frame
    CHECK(coords ~= nil, "A: the coordinates readout is built")
    EQ(coords:GetParent(), WorldMapFrame, "A: coordinates parented to WorldMapFrame (not BorderFrame)")
    local pt = coords.__points[1]
    EQ(pt and pt.rel, W.map.container, "A: anchored to the ScrollContainer")
    EQ(pt and pt.point, "BOTTOMLEFT", "A: at its bottom-left (clear of QuestLog's drawer on the right)")

    local driver = I().Mini.driver
    CHECK(driver ~= nil, "A: the minimap driver exists")
    EQ(driver:GetName(), nil, "A: the driver is unnamed")
    EQ(driver.__parent, Minimap, "A: the driver is a child of the Minimap")
    CHECK(not Shown(driver), "A: the driver sleeps with no waypoint")
    local places = I().Mini.places
    M.Advance(1)
    EQ(I().Mini.places, places, "A: no per-frame work with nothing to show")
    EQ(W.zoomNudges, nil, "A: Minimap:SetZoom never nudged")
    NOERR("A end")
end)

-- ===========================================================================
-- B: minimap, which waypoints get a pin
-- ===========================================================================
Section("B", function()
    Boot({ player = GOLDSHIRE })
    local ids = {}
    ids.north = O().Add({ map = 1429, x = 0.48, y = 0.42, title = "Northshire" })
    ids.westfall = O().Add({ map = 1436, x = 0.5, y = 0.5, title = "Westfall", setArrow = false })
    ids.sw = O().Add({ map = 1453, x = 0.5, y = 0.5, title = "Stormwind", setArrow = false })
    ids.eversong = O().Add({ map = 1941, x = 0.5, y = 0.5, title = "Eversong", setArrow = false })
    ids.ghost = O().Add({ map = 1942, x = 0.5, y = 0.5, title = "Ghostlands", setArrow = false })
    ids.durotar = O().Add({ map = 1411, x = 0.5, y = 0.5, title = "Durotar", setArrow = false })
    ids.hellfire = O().Add({ map = 1944, x = 0.5, y = 0.5, title = "Hellfire", setArrow = false })
    M.SetGroup("party", { "Bob" })
    M.SetUnit("party1", 1429, 0.43, 0.66)
    ids.unit = O().Add({ kind = "unit", unit = "party1", title = "Bob", setArrow = false })
    CHECK(ids.unit ~= nil, "B: the follow waypoint exists")
    Settle()
    NOERR("B adds")
    EQ(MiniCount(), 3, "B: Elwynn: pins for Northshire, Westfall and Stormwind only")
    CHECK(MiniPinFor(ids.north) and MiniPinFor(ids.westfall) and MiniPinFor(ids.sw), "B: the three EK:0 ones")
    EQ(MiniPinFor(ids.eversong), nil, "B: Eversong (530 under EK) is another landmass")
    EQ(MiniPinFor(ids.hellfire), nil, "B: Hellfire (530) is another landmass")
    EQ(MiniPinFor(ids.durotar), nil, "B: Kalimdor is another landmass")
    EQ(MiniPinFor(ids.unit), nil, "B: a followed group member has no pin (the client draws the member)")
    local radarLevel = CommanderRadarOverlay:GetFrameLevel()
    for i = 1, MiniCount() do
        local pin = I().Mini.pins[i]
        EQ(pin:GetName(), nil, "B: pin " .. i .. " is unnamed (Commander_Minimap's tidy never takes it)")
        EQ(pin.__parent, Minimap, "B: pin " .. i .. " is a child of the Minimap")
        CHECK(pin:GetFrameLevel() > radarLevel, "B: pin " .. i .. " over Commander_Radar's overlay",
            pin:GetFrameLevel())
    end
    CHECK(Shown(I().Mini.driver), "B: the driver runs with pins up")

    -- across a loading screen: the other landmasses
    M.SetPlayer(1941, 0.5, 0.4)
    M.Fire("ZONE_CHANGED_NEW_AREA")
    Settle()
    EQ(MiniCount(), 2, "B: Quel'Thalas: Eversong and Ghostlands")
    CHECK(MiniPinFor(ids.eversong) and MiniPinFor(ids.ghost), "B: the two 530 EK zones")
    -- a portal with no zone event yet: the very next frame must not place
    -- Quel'Thalas pins against Outland coordinates
    M.SetPlayer(1944, 0.4, 0.4)
    M.Frame()
    EQ(MiniCount(), 1, "B: Eversong to Hellfire (both 530): the landmass change is caught the same frame")
    CHECK(MiniPinFor(ids.eversong) == nil, "B: no stale Eversong pin on the Outland minimap")
    M.Advance(1.1)
    EQ(MiniCount(), 1, "B: Outland: Hellfire only, found without an event")
    CHECK(MiniPinFor(ids.hellfire) ~= nil, "B: Hellfire")
    M.SetPlayer(1411, 0.4, 0.4)
    M.Frame()
    EQ(MiniCount(), 1, "B: Hellfire to Durotar (530 to 1): caught the same frame too")
    CHECK(MiniPinFor(ids.durotar) ~= nil, "B: Kalimdor: Durotar")
    M.Fire("PLAYER_ENTERING_WORLD", false, false)
    Settle()
    EQ(MiniCount(), 1, "B: Kalimdor: Durotar only")

    -- no position (inside an instance)
    M.SetNoPosition(true)
    M.Advance(1.2)
    EQ(MiniCount(), 0, "B: no position: no pins")
    CHECK(not Shown(I().Mini.driver), "B: the driver sleeps")
    for _, pin in ipairs(I().Mini.pins) do CHECK(not Shown(pin), "B: every pin hidden") end
    M.SetNoPosition(false)
    M.Fire("PLAYER_ENTERING_WORLD", false, false)
    Settle()
    EQ(MiniCount(), 1, "B: position back: the pin is back")

    -- removed waypoints lose their pins
    M.SetPlayer(1429, 0.42, 0.655)
    M.Fire("ZONE_CHANGED_NEW_AREA")
    Settle()
    EQ(MiniCount(), 3, "B: back in Elwynn")
    O().Remove(ids.westfall)
    Settle()
    EQ(MiniCount(), 2, "B: a removed waypoint loses its pin at once")
    local hidden = 0
    for _, pin in ipairs(I().Mini.pins) do if not Shown(pin) then hidden = hidden + 1 end end
    CHECK(hidden >= 1, "B: the spare pin is hidden")

    -- another instance at the very same coordinates (an instance's own frame
    -- can overlap the world's): no jump, so the instance alone must say so
    local here = M.W.player
    M.SetPlayerWorld(1, here.north, here.west, 1411)
    M.Frame()
    EQ(MiniCount(), 1, "B: another instance, same coordinates: caught the same frame")
    CHECK(MiniPinFor(ids.durotar) ~= nil and MiniPinFor(ids.north) == nil, "B: the Kalimdor pin, not Elwynn's")
    NOERR("B end")
end)

-- ===========================================================================
-- C: minimap placement
-- ===========================================================================
Section("C", function()
    local W = Boot({ player = GOLDSHIRE })
    local near = AddOffset(50, 30, "Near")
    local far = AddOffset(400, 0, "Far north")
    local diag = AddOffset(400, -400, "Far north-east")
    Settle()
    EQ(MiniCount(), 3, "C: three pins")
    local pNear, pFar, pDiag = MiniPinFor(near), MiniPinFor(far), MiniPinFor(diag)

    -- round, not rotated, zoom 0 outdoor: radius 233.3 yd, the stock 140 px map
    NEAR(I().Mini.radius, OUTDOOR0, 1e-6, "C: zoom 0 outdoors is a 233.3 yd radius")
    local pt = LastPoint(pNear)
    EQ(pt and pt.point, "CENTER", "C: anchored by its centre")
    EQ(pt and pt.rel, Minimap, "C: to the Minimap")
    NEAR(pt and pt.x, -30 / OUTDOOR0 * 70, 0.06, "C: 30 yd west is 9.0 px left")
    NEAR(pt and pt.y, 50 / OUTDOOR0 * 70, 0.06, "C: 50 yd north is 15.0 px up")
    NEAR(pt and pt.x, -9.0, 0.06, "C: by hand: -9.0")
    CHECK(Shown(pNear) and Shown(pNear.icon) and not Shown(pNear.edge), "C: inside the rim: the dot, no chevron")

    pt = LastPoint(pFar)
    NEAR(pt and pt.x, 0, 0.06, "C: due north on the rim: x 0")
    NEAR(pt and pt.y, 63, 0.06, "C: clamped at 0.9 of the 70 px radius")
    CHECK(Shown(pFar.edge) and not Shown(pFar.icon), "C: off the map: the edge chevron, not the dot")
    NEAR(pFar.edge.__rotation, 0, 1e-6, "C: the chevron points straight up")
    pt = LastPoint(pDiag)
    NEAR(pt and pt.x, 63 / math.sqrt(2), 0.06, "C: round rim, north-east: 44.5 px right")
    NEAR(pt and pt.y, 63 / math.sqrt(2), 0.06, "C: and 44.5 px up")
    NEAR(pDiag.edge.__rotation, -math.pi / 4, 1e-6, "C: the chevron leans 45 degrees clockwise")

    -- square (GetMinimapShape)
    M.SetMinimapShape("SQUARE")
    M.Fire("MINIMAP_UPDATE_ZOOM")
    pt = LastPoint(pDiag)
    NEAR(pt and pt.x, 63, 0.06, "C: square: the corner, 63 px right")
    -- the top rim of a square map rides under Commander_Minimap's zone
    -- name (GameFontNormal at TOP -2: 70 - 22 = 48; review: render)
    NEAR(pt and pt.y, 48, 0.06, "C: square: under the zone-name strip at the top (48 px up)")
    NEAR(pDiag.edge.__rotation, -math.pi / 4, 1e-6, "C: square: the chevron keeps its angle")
    pt = LastPoint(pFar)
    NEAR(pt and pt.y, 48, 0.06, "C: square: due north 48 px, clear of the zone name")
    local south = AddOffset(-400, 0, "Far south")
    M.Advance(1.1)
    pt = LastPoint(MiniPinFor(south))
    NEAR(pt and pt.y, -63, 0.06, "C: square: the bottom rim is untouched (-63)")
    O().Remove(south)
    M.Advance(1.1)
    M.SetMinimapShape("CORNER-TOPRIGHT")
    M.Fire("MINIMAP_UPDATE_ZOOM")
    pt = LastPoint(pDiag)
    NEAR(pt and pt.x, 63 / math.sqrt(2), 0.06, "C: CORNER-TOPRIGHT keeps that quadrant round")
    M.SetMinimapShape(nil)
    M.Fire("MINIMAP_UPDATE_ZOOM")
    pt = LastPoint(pDiag)
    NEAR(pt and pt.x, 63 / math.sqrt(2), 0.06, "C: no GetMinimapShape: round")

    -- per frame: walking moves the pins with no event
    local inst, n0, w0 = PlayerWorld()
    M.SetPlayerWorld(inst, n0 + 10, w0)
    M.Frame()
    pt = LastPoint(pNear)
    NEAR(pt and pt.y, 40 / OUTDOOR0 * 70, 0.06, "C: ten yards north: the pin slides down the same frame")
    local pointsTable = pNear.__points
    M.Frame()
    EQ(pNear.__points, pointsTable, "C: standing still: no new SetPoint")
    M.SetPlayerWorld(inst, n0, w0)
    M.Frame()

    -- rotating minimap
    W.cvars.rotateMinimap = "1"
    M.SetFacing(0.6)
    M.Fire("CVAR_UPDATE", "rotateMinimap", "1")
    local ex, ey = Expect(50, 30, OUTDOOR0, 0.6, true, false, 70)
    pt = LastPoint(pNear)
    NEAR(pt and pt.x, ex, 0.06, "C: rotated: x")
    NEAR(pt and pt.y, ey, 0.06, "C: rotated: y")
    CHECK(ex > 0, "C: facing left of north, a target north-west shows right of up", ex)
    local _, _, _, eAngle = Expect(400, 0, OUTDOOR0, 0.6, true, false, 70)
    NEAR(pFar.edge.__rotation, eAngle, 1e-6, "C: rotated: the chevron turns with the map")
    NEAR(eAngle, -0.6, 1e-9, "C: by hand: north at facing 0.6 is 0.6 clockwise")
    M.SetFacing(1.2)
    M.Frame()
    ex, ey = Expect(50, 30, OUTDOOR0, 1.2, true, false, 70)
    pt = LastPoint(pNear)
    NEAR(pt and pt.x, ex, 0.06, "C: turning: the pins swing the same frame")
    M.SetFacing(nil)
    M.Frame()
    CHECK(not Shown(pNear), "C: rotating map with no heading: pins hidden, not guessed")
    M.SetFacing(0)
    W.cvars.rotateMinimap = "0"
    M.Fire("CVAR_UPDATE", "rotateMinimap", "0")
    CHECK(Shown(pNear), "C: heading back: pins back")

    -- zoom levels, indoors and out
    M.SetZoom(3)
    M.Fire("MINIMAP_UPDATE_ZOOM")
    NEAR(I().Mini.radius, 800 / 3 / 2, 1e-6, "C: outdoor zoom 3: 133.3 yd (266.67 diameter, not HBD's 266.33)")
    pt = LastPoint(pNear)
    NEAR(pt and pt.x, -30 / (400 / 3) * 70, 0.06, "C: zoomed in: further out")
    W.cvars.minimapZoom, W.cvars.minimapInsideZoom = "0", "2"
    M.SetZoom(2)
    M.Fire("MINIMAP_UPDATE_ZOOM")
    EQ(I().Mini.indoors, true, "C: zoom equals the inside CVar: indoors")
    NEAR(I().Mini.radius, 90, 1e-6, "C: indoor zoom 2: 90 yd")
    M.SetZoom(0)
    M.Fire("MINIMAP_UPDATE_ZOOM")
    EQ(I().Mini.indoors, false, "C: zoom equals the outdoor CVar: outdoors")
    W.cvars.minimapZoom, W.cvars.minimapInsideZoom = "1", "1"
    M.SetZoom(1)
    M.SetIndoors(true)
    M.Fire("ZONE_CHANGED_INDOORS")
    EQ(I().Mini.indoors, true, "C: equal CVars: IsIndoors breaks the tie (in)")
    NEAR(I().Mini.radius, 120, 1e-6, "C: indoor zoom 1: 120 yd")
    M.SetIndoors(false)
    M.Fire("ZONE_CHANGED_INDOORS")
    NEAR(I().Mini.radius, 200, 1e-6, "C: outdoor zoom 1: 200 yd")
    EQ(W.zoomNudges, nil, "C: the zoom was read, never nudged")
    M.SetZoom(0)
    W.cvars.minimapZoom, W.cvars.minimapInsideZoom = "0", "0"
    M.Fire("MINIMAP_UPDATE_ZOOM")

    -- a bigger minimap: half its own size
    Minimap.__w, Minimap.__h = 200, 160
    M.Advance(0.6)
    pt = LastPoint(pNear)
    NEAR(pt and pt.x, -30 / OUTDOOR0 * 100, 0.06, "C: a 200 px map: x scales with half the width")
    NEAR(pt and pt.y, 50 / OUTDOOR0 * 80, 0.06, "C: a 160 px tall map: y with half the height")
    Minimap.__w, Minimap.__h = 140, 140
    M.Advance(0.6)

    -- a taxi at full speed is not a teleport: placed, not rebuilt
    local rebuilds = 0
    local realRebuild = I().Mini.Rebuild
    I().Mini.Rebuild = function(...) rebuilds = rebuilds + 1 return realRebuild(...) end
    I().Mini.rebuildAcc = 0           -- half a second: short of the periodic rebuild
    M.SetTaxi(true)
    for _ = 1, 15 do
        local p = M.W.player
        M.SetPlayerWorld(p.inst, p.north + 2, p.west)    -- 60 yd/s
        M.Frame(1 / 30)
    end
    M.SetTaxi(false)
    I().Mini.Rebuild = realRebuild
    EQ(rebuilds, 0, "C: flying at 60 yd/s: no teleport rebuild")
    M.SetPlayerWorld(inst, n0, w0)
    M.Advance(1.1)

    -- the per-frame work stops with the minimap hidden
    local places = I().Mini.places
    M.Advance(0.5)
    CHECK(I().Mini.places > places + 10, "C: pins placed every frame while shown", I().Mini.places - places)
    Minimap:Hide()
    places = I().Mini.places
    M.Advance(0.5)
    EQ(I().Mini.places, places, "C: hidden minimap: no per-frame work")
    Minimap:Show()
    M.Advance(0.1)
    CHECK(I().Mini.places > places, "C: shown again: placing again")

    -- MinimapEdge off: off-map pins go, near ones stay
    DB().MinimapEdge = false
    Notify()
    Settle()
    CHECK(not Shown(pFar) and not Shown(pDiag), "C: edge off: off-map pins hidden")
    CHECK(Shown(MiniPinFor(near)), "C: edge off: the near pin stays")
    DB().MinimapEdge = true
    Notify()
    Settle()
    CHECK(Shown(MiniPinFor(far)), "C: edge on again")

    -- MinimapPins off: nothing, no driver
    DB().MinimapPins = false
    Notify()
    Settle()
    EQ(MiniCount(), 0, "C: minimap pins off: none")
    CHECK(not Shown(I().Mini.driver), "C: and no per-frame driver")
    DB().MinimapPins = true
    Notify()
    Settle()
    EQ(MiniCount(), 3, "C: back on")
    NOERR("C end")
end)

-- ===========================================================================
-- D: minimap pins: hover, clicks, the arrow's target
-- ===========================================================================
Section("D", function()
    Boot({ player = GOLDSHIRE })
    local a = AddOffset(60, 20, "Camp")
    local b = AddOffset(-40, -50, "Mine")
    O().SetArrow(a)
    Settle()
    local pa, pb = MiniPinFor(a), MiniPinFor(b)
    CHECK(pa and pb, "D: two pins")
    CHECK(Shown(pa.ring), "D: the arrow's target is ringed")
    CHECK(not Shown(pb.ring), "D: the other is not")

    M.Hover(pa)
    local tip = table.concat(M.tooltip, "\n")
    HAS(tip, "Camp", "D: tooltip: the title")
    HAS(tip, "Elwynn Forest", "D: tooltip: the zone")
    HAS(tip, " yd", "D: tooltip: the distance")
    HAS(tip, "Set by you", "D: tooltip: who set it")
    HAS(tip, "The arrow points here", "D: tooltip: it is the arrow's target")
    HAS(tip, "Shift-click", "D: tooltip: how to use it")
    CHECK(not tip:find("[\128-\255]"), "D: tooltip text is plain ASCII (D11)")
    M.Hover(pb)
    tip = table.concat(M.tooltip, "\n")
    CHECK(not tip:find("The arrow points here", 1, true), "D: tooltip: the other is not the target")

    M.ClearLog()
    M.Click(pb, "LeftButton")
    EQ(Store():Pinned().uid, a, "D: a plain click does not take the arrow")
    M.SetModifier("SHIFT", true)
    M.Click(pb, "LeftButton")
    M.SetModifier("SHIFT", false)
    EQ(Store():Pinned().uid, b, "D: Shift-click points the arrow there")
    Settle()
    CHECK(Shown(MiniPinFor(b).ring) and not Shown(MiniPinFor(a).ring), "D: the ring follows the arrow")

    -- walking at the target: the arrow's ETA is in its pin's tooltip
    O().SetArrow(a)
    Settle()
    local inst, n0, w0 = PlayerWorld()
    M.SetSpeed(7)
    for _ = 1, 30 do
        local p = M.W.player
        M.SetPlayerWorld(inst, p.north + 7 * 60 / 63.25 / 30, p.west + 7 * 20 / 63.25 / 30)
        M.Frame(1 / 30)
    end
    M.Hover(MiniPinFor(a))
    HAS(table.concat(M.tooltip, "\n"), ", about ", "D: tooltip: the arrow's arrival time")
    M.Hover(MiniPinFor(b))
    CHECK(not table.concat(M.tooltip, "\n"):find(", about ", 1, true), "D: tooltip: no guessed time for the others")
    M.SetSpeed(0)
    M.SetPlayerWorld(inst, n0, w0)
    local corpse = Store():Add({ kind = "corpse", source = "corpse", map = 1429, x = 0.43, y = 0.64,
        title = "Your corpse", icon = "CORPSE", setArrow = false })
    O().Pins.Refresh()
    local cp = MiniPinFor(corpse.uid)
    EQ(cp and cp.icon.__texture, "Interface\\AddOns\\Commander_Orders\\Textures\\Corpse.png", "D: the corpse art on the minimap")
    EQ(cp and cp.__w, 14, "D: a 14 px tombstone")
    Store():Remove(corpse.uid)
    O().Pins.Refresh()

    M.Click(MiniPinFor(a), "RightButton")
    local texts = table.concat(M.MenuTexts(), "|")
    HAS(texts, "Set as arrow", "D: menu: Set as arrow")
    HAS(texts, "Copy /way line", "D: menu: Copy /way line")
    HAS(texts, "Remove", "D: menu: Remove")
    CHECK(not texts:find("Share with group", 1, true), "D: menu: no Share outside a group")
    M.SetGroup("party", { "Bob" })
    M.Click(MiniPinFor(a), "RightButton")
    HAS(table.concat(M.MenuTexts(), "|"), "Share with group", "D: menu: Share in a group")
    M.ClickMenu("Remove")
    Settle()
    EQ(O().Get(a), nil, "D: menu Remove removes it")
    EQ(MiniCount(), 1, "D: and its pin")
    NOERR("D end")
end)

-- ===========================================================================
-- E: world-map pins
-- ===========================================================================
Section("E", function()
    local W = Boot({ player = GOLDSHIRE })
    local ids = {}
    ids.north = O().Add({ map = 1429, x = 0.48, y = 0.42, title = "Northshire" })
    ids.westfall = O().Add({ map = 1436, x = 0.5, y = 0.5, title = "Westfall", setArrow = false })
    ids.eversong = O().Add({ map = 1941, x = 0.5, y = 0.5, title = "Eversong", setArrow = false })
    ids.durotar = O().Add({ map = 1411, x = 0.5, y = 0.5, title = "Durotar", setArrow = false })
    ids.hellfire = O().Add({ map = 1944, x = 0.5, y = 0.5, title = "Hellfire", setArrow = false })
    Settle()
    M.ShowMap(1429)
    Settle()
    NOERR("E show")
    local pins = PinsFor(ids.north)
    EQ(#pins, 1, "E: Elwynn: the Northshire pin")
    local p = pins[1]
    NEAR(p and p.__x, 0.48, 1e-9, "E: at its own x")
    NEAR(p and p.__y, 0.42, 1e-9, "E: at its own y")
    EQ(#PinsFor(ids.durotar) + #PinsFor(ids.hellfire) + #PinsFor(ids.eversong), 0,
        "E: Elwynn: nothing from other landmasses")
    EQ(p and p.pinFrameLevelType, "PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST", "E: our level type")
    EQ(p and p:GetFrameLevel(), M.PIN_LEVELS.PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST + 1,
        "E: the arrow's target one level over the others")
    CHECK(p and p:GetFrameLevel() > M.PIN_LEVELS.PIN_FRAME_LEVEL_AREA_POI, "E: above Questie's icons (2016+)")
    CHECK(p and p:GetFrameLevel() < M.PIN_LEVELS.PIN_FRAME_LEVEL_GROUP_MEMBER, "E: under the party dots")
    CHECK(p and p.__click and p.__motion, "E: clickable and hoverable from creation")
    CHECK(p and p.__scripts.OnMouseUp ~= nil and p.__scripts.OnEnter ~= nil,
        "E: AcquirePin wired the mouse (and its OnEnter assert held)")
    CHECK(p and p.__scripts.OnMouseDown ~= nil and p.__scripts.OnMouseDown == p.OnMouseDown,
        "E: AcquirePin's OnMouseDown is the mixin's own (the Shift-drag starts there)")
    CHECK(p and Shown(p.ring), "E: the arrow's target is ringed")
    EQ(p and p.icon.__texture, "Interface\\AddOns\\Commander_Orders\\Textures\\Pin.png", "E: our own pin art")
    local user = CommanderOrders.Data.ICON_COLOURS.USER
    NEAR(p and p.icon.__vertex[1], user[1], 1e-9, "E: tinted as the user's own")
    EQ(p and p.__w, 18, "E: an 18 px pin")
    CHECK(p and p.__scaling and p.__scaling[1] == 1, "E: scaling limits keep it the same size on screen")
    EQ(W.map.canvasErrors, 0, "E: Blizzard's canvas pass runs over our pins without error")

    -- the continent: projected, the other landmasses only where they belong
    M.SetMapID(1415)
    Settle()
    local inst, n, w = M.World(1429, 0.48, 0.42)
    local ex, ey = M.MapPos(1415, inst, n, w)
    p = PinsFor(ids.north)[1]
    NEAR(p and p.__x, ex, 1e-6, "E: Eastern Kingdoms: Northshire projected (x)")
    NEAR(p and p.__y, ey, 1e-6, "E: Eastern Kingdoms: Northshire projected (y)")
    EQ(#PinsFor(ids.westfall), 1, "E: Eastern Kingdoms: Westfall")
    EQ(#PinsFor(ids.eversong), 1, "E: Eastern Kingdoms: Eversong too (the 530 sub-rectangle)")
    inst, n, w = M.World(1941, 0.5, 0.5)
    ex, ey = M.MapPos(1415, inst, n, w)
    p = PinsFor(ids.eversong)[1]
    NEAR(p and p.__x, ex, 1e-4, "E: Eversong at the client's own rectangle (x)")
    NEAR(p and p.__y, ey, 1e-4, "E: Eversong at the client's own rectangle (y)")
    EQ(#PinsFor(ids.durotar), 0, "E: Eastern Kingdoms: no Durotar")
    EQ(#PinsFor(ids.hellfire), 0, "E: Eastern Kingdoms: no Hellfire")

    M.SetMapID(947)
    Settle()
    EQ(#PinsFor(ids.north), 1, "E: Azeroth: Northshire")
    EQ(#PinsFor(ids.durotar), 1, "E: Azeroth: Durotar")
    EQ(#PinsFor(ids.hellfire), 0, "E: Azeroth: Outland is not on it")
    M.SetMapID(1945)
    Settle()
    EQ(#WorldPins(), 1, "E: Outland: Hellfire only")
    EQ(#PinsFor(ids.hellfire), 1, "E: Outland: the Hellfire pin")
    M.SetMapID(1411)
    Settle()
    EQ(#PinsFor(ids.durotar), 1, "E: Durotar's own map")
    EQ(#PinsFor(ids.north), 0, "E: Durotar: nothing from EK")
    M.SetMapID(1429)
    Settle()

    -- refreshed while open
    local added = O().Add({ map = 1429, x = 0.3, y = 0.7, title = "Late", setArrow = false })
    Settle()
    EQ(#PinsFor(added), 1, "E: a waypoint added with the map open appears")
    O().Remove(added)
    Settle()
    EQ(#PinsFor(added), 0, "E: and goes when removed")
    -- a source that names no icon: Data.SOURCE_ICONS' tint, the manager's too
    local smith = O().Add({ map = 1429, x = 0.31, y = 0.71, title = "Smith", source = "Logistics", key = "t:rep",
        setArrow = false })
    Settle()
    local vendor = CommanderOrders.Data.ICON_COLOURS.VENDOR
    local sp0 = PinsFor(smith)[1]
    CHECK(sp0 and math.abs(sp0.icon.__vertex[1] - vendor[1]) < 1e-9 and math.abs(sp0.icon.__vertex[3] - vendor[3]) < 1e-9,
        "E: Logistics, no icon: the vendor tint from Data.SOURCE_ICONS")
    O().Remove(smith)
    Settle()

    -- alternatives: every spawn, the chosen one full size
    local spawns = O().Add({ map = 1429, x = 0.3, y = 0.3, title = "Spawns", source = "QuestLog", key = "q1",
        alternatives = { { 1429, 0.3, 0.3 }, { 1429, 0.6, 0.6 }, { 1429, 0.7, 0.2 } }, setArrow = false })
    Settle()
    local sp = PinsFor(spawns)
    EQ(#sp, 3, "E: alternatives: a pin per spawn")
    local full, small = 0, 0
    local chosen = Store():ChosenAlternative(spawns)
    for _, pin in ipairs(sp) do
        if pin.data.alt then
            small = small + 1
            EQ(pin.__w, 10, "E: alternatives: the others are small")
            NEAR(pin.icon.__alpha, 0.7, 1e-9, "E: alternatives: and faint")
        else
            full = full + 1
            local alt = Store():Get(spawns).alternatives[chosen]
            NEAR(pin.__x, alt.x, 1e-9, "E: alternatives: the full pin is the chosen spawn")
        end
    end
    EQ(full, 1, "E: alternatives: one full pin")
    EQ(small, 2, "E: alternatives: two small ones")
    local quest = CommanderOrders.Data.ICON_COLOURS.QUEST
    NEAR(sp[1].icon.__vertex[2], quest[2], 1e-9, "E: QuestLog waypoints wear the quest tint")
    M.Hover(sp[1])
    HAS(table.concat(M.tooltip, "\n"), "The nearest of 3 places", "E: alternatives: the tooltip says so")
    HAS(table.concat(M.tooltip, "\n"), "From Quest Log", "E: tooltip: the source, in the words the manager uses")
    CHECK(not sp[1].data.draggable, "E: alternatives cannot be dragged")

    -- a corpse, a reached mark, a followed unit
    local corpse = Store():Add({ kind = "corpse", source = "corpse", map = 1429, x = 0.45, y = 0.6,
        title = "Your corpse", icon = "CORPSE", setArrow = false })
    CHECK(corpse ~= nil, "E: corpse record")
    local mark = O().Add({ map = 1429, x = 0.55, y = 0.65, title = "Done here", setArrow = false })
    Store():Get(mark).reached = 1
    M.SetGroup("party", { "Bob" })
    M.SetUnit("party1", 1429, 0.43, 0.66)
    -- a follow with a last known place (map, x, y) still gets no pin
    local unit = O().Add({ kind = "unit", unit = "party1", map = 1429, x = 0.43, y = 0.66, setArrow = false })
    CHECK(unit ~= nil and O().Get(unit).map == 1429, "E: a unit follow with a last known place")
    O().Pins.Refresh()
    local cp = PinsFor(corpse.uid)[1]
    EQ(cp and cp.icon.__texture, "Interface\\AddOns\\Commander_Orders\\Textures\\Corpse.png", "E: the corpse art")
    local cc = CommanderOrders.Data.ICON_COLOURS.CORPSE
    NEAR(cp and cp.icon.__vertex[3], cc[3], 1e-9, "E: tinted ghost blue")
    CHECK(cp and not cp.data.draggable, "E: the corpse cannot be dragged")
    local mp = PinsFor(mark)[1]
    NEAR(mp and mp.icon.__alpha, 0.45, 1e-9, "E: a reached mark is drawn faint")
    EQ(#PinsFor(unit), 0, "E: a followed unit has no pin of ours")
    M.Hover(mp)
    HAS(table.concat(M.tooltip, "\n"), "Reached", "E: tooltip: reached")

    -- settings and the master switch
    DB().WorldPins = false
    Notify()
    Settle()
    EQ(#WorldPins(), 0, "E: world pins off: none")
    DB().WorldPins = true
    Notify()
    Settle()
    CHECK(#WorldPins() > 0, "E: world pins on again")
    DB().EnableOrders = false
    Notify()
    Settle()
    EQ(#WorldPins(), 0, "E: Orders off: none")
    EQ(MiniCount(), 0, "E: Orders off: no minimap pins either")
    DB().EnableOrders = true
    Notify()
    Settle()
    CHECK(#WorldPins() > 0, "E: Orders on: back")
    M.HideMap()
    Settle()
    EQ(#W.map.writes, 0, "E: still nothing assigned to WorldMapFrame")
    EQ(W.map.canvasErrors, 0, "E: no canvas errors")
    NOERR("E end")
end)

-- ===========================================================================
-- F: routes: badges and lines
-- ===========================================================================
Section("F", function()
    local W = Boot({ player = GOLDSHIRE })
    local stops = { { map = 1429, x = 0.4, y = 0.6 }, { map = 1429, x = 0.5, y = 0.5 }, { map = 1429, x = 0.6, y = 0.4 } }
    local rid = O().AddRoute({ title = "Elwynn walk", mode = "ORDERED", stops = stops })
    CHECK(rid ~= nil, "F: route added")
    Settle()
    M.ShowMap(1429)
    Settle()
    local route = Store():GetRoute(rid)
    local badges = {}
    for i, uid in ipairs(route.stops) do
        local p = PinsFor(uid)[1]
        badges[i] = p
        EQ(p and p.icon.__texture, "Interface\\AddOns\\Commander_Orders\\Textures\\Badge.png", "F: stop " .. i .. " is a badge")
        EQ(p and p.number.__text, tostring(i), "F: stop " .. i .. " is numbered " .. i)
        CHECK(p and Shown(p.number), "F: stop " .. i .. " shows its number")
        EQ(p and p.__w, 22, "F: badges are 22 px")
    end
    for i, uid in ipairs(route.stops) do
        local mp = MiniPinFor(uid)
        EQ(mp and mp.number.__text, tostring(i), "F: minimap badge " .. i .. " numbered")
        EQ(mp and mp.icon.__texture, "Interface\\AddOns\\Commander_Orders\\Textures\\Badge.png", "F: minimap badge " .. i .. " art")
    end
    local World = I().World
    EQ(World.linesUsed, 2, "F: two legs, two lines")
    local host = World.host
    CHECK(host ~= nil, "F: the line host exists")
    EQ(host.__parent, W.map.canvas, "F: the host is a child of the canvas")
    EQ(host.__allPoints, W.map.canvas, "F: and covers it")
    CHECK(host:GetFrameLevel() < M.PIN_LEVELS.PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST, "F: lines under the pins")
    local l1 = World.lines[1]
    EQ(l1.__kind, "Line", "F: a Line region (canvas:CreateLine exists on 2.5.6)")
    EQ(l1.__start and l1.__start.rel, host, "F: anchored to the host")
    NEAR(l1.__start and l1.__start.x, 0.4 * 900, 1e-6, "F: leg 1 starts at stop 1 (x)")
    NEAR(l1.__start and l1.__start.y, -0.6 * 600, 1e-6, "F: leg 1 starts at stop 1 (y)")
    NEAR(l1.__end and l1.__end.x, 0.5 * 900, 1e-6, "F: leg 1 ends at stop 2 (x)")
    NEAR(l1.__end and l1.__end.y, -0.5 * 600, 1e-6, "F: leg 1 ends at stop 2 (y)")
    NEAR(World.lines[2].__end and World.lines[2].__end.x, 0.6 * 900, 1e-6, "F: leg 2 ends at stop 3")
    EQ(l1.__thickness, 3, "F: three pixels thick")
    local rc = CommanderOrders.Data.ICON_COLOURS.ROUTE
    NEAR(l1.__color and l1.__color[1], rc[1], 1e-9, "F: the route colour")
    NEAR(l1.__color and l1.__color[4], 0.85, 1e-9, "F: legs ahead are bright")
    CHECK(Shown(l1), "F: shown")

    -- a passed leg dims
    O().RouteNext(rid)
    Settle()
    NEAR(World.lines[1].__color[4], 0.3, 1e-9, "F: the leg already walked is faint")
    NEAR(World.lines[2].__color[4], 0.85, 1e-9, "F: the leg ahead is not")
    local cur = Store():GetRoute(rid).stops[2]
    CHECK(Shown(PinsFor(cur)[1].ring), "F: the current stop is ringed")

    -- on the continent the lines follow the projection
    M.SetMapID(1415)
    Settle()
    EQ(World.linesUsed, 2, "F: continent: two lines")
    local inst, n, w = M.World(1429, 0.4, 0.6)
    local ex, ey = M.MapPos(1415, inst, n, w)
    NEAR(World.lines[1].__start.x, ex * 900, 1e-3, "F: continent: projected start (x)")
    NEAR(World.lines[1].__start.y, -ey * 600, 1e-3, "F: continent: projected start (y)")
    M.SetMapID(1411)
    Settle()
    EQ(World.linesUsed, 0, "F: a map the stops are not on: no lines")
    EQ(#WorldPins(), 0, "F: and no pins")
    M.SetMapID(1429)
    Settle()

    -- RouteLines off: badges stay
    DB().RouteLines = false
    Notify()
    Settle()
    EQ(World.linesUsed, 0, "F: route lines off: none")
    CHECK(not Shown(World.lines[1]), "F: the old line hidden")
    EQ(#WorldPins(), 3, "F: the badges stay")
    DB().RouteLines = true
    Notify()
    Settle()
    EQ(World.linesUsed, 2, "F: lines back")

    -- a loop closes the ring
    O().RemoveRoute(rid)
    local loop = O().AddRoute({ title = "Loop", mode = "ORDERED", stops = stops, loop = true })
    Settle()
    CHECK(Store():GetRoute(loop) and Store():GetRoute(loop).loop, "F: a loop route")
    EQ(World.linesUsed, 3, "F: a loop of three: three legs")
    NEAR(World.lines[3].__end.x, 0.4 * 900, 1e-6, "F: the last leg returns to stop 1")
    O().RemoveRoute(loop)
    Settle()
    EQ(World.linesUsed, 0, "F: route removed: no lines")
    EQ(#WorldPins(), 0, "F: and no badges")

    -- a leg across landmasses has no line
    local cross = O().AddRoute({ title = "North", mode = "ORDERED", stops = {
        { map = 1429, x = 0.5, y = 0.5 }, { map = 1941, x = 0.5, y = 0.5 } } })
    M.SetMapID(1415)
    Settle()
    EQ(#WorldPins(), 2, "F: across landmasses: both badges on the continent")
    EQ(World.linesUsed, 0, "F: but no straight line from Elwynn to Eversong")
    O().RemoveRoute(cross)
    Settle()
    M.HideMap()
    NOERR("F end")

    -- a client without CreateLine: badges only, no error
    NO_LINES = true
    Boot({ player = GOLDSHIRE })
    O().AddRoute({ title = "Elwynn walk", mode = "ORDERED", stops = stops })
    Settle()
    M.ShowMap(1429)
    Settle()
    EQ(#WorldPins(), 3, "F: no CreateLine: the badges")
    EQ(I().World.linesUsed, 0, "F: no CreateLine: no lines")
    NOERR("F no CreateLine")
    NO_LINES = false

    -- a Line that refuses its colour: one report, lines off, badges stay
    BROKEN_LINES = true
    Boot({ player = GOLDSHIRE })
    O().AddRoute({ title = "Elwynn walk", mode = "ORDERED", stops = stops })
    Settle()
    M.ShowMap(1429)
    Settle()
    EQ(#WorldPins(), 3, "F: a broken Line: the badges still draw")
    EQ(I().World.linesUsed, 0, "F: a broken Line: no lines left up")
    EQ(I().World.linesBroken, true, "F: a broken Line: lines off for the session")
    EQ(#M.errors, 1, "F: a broken Line: reported once", M.errors[2])
    O().RouteNext()
    Settle()
    EQ(#M.errors, 1, "F: a broken Line: not again on the next redraw")
    BROKEN_LINES = false
    for i = #M.errors, 1, -1 do M.errors[i] = nil end
end)

-- ===========================================================================
-- G: world-pin clicks and drags
-- ===========================================================================
-- Blizzard's OnPinMouseUp: pin:OnMouseUp(button), then OnClick when the
-- release is inside. The mock's AcquirePin wires exactly that, so a release
-- inside the pin is its OnMouseUp script with upInside true.
local function PinUp(pin, button)
    pin.__scripts.OnMouseUp(pin, button, true)
end

Section("G", function()
    local W = Boot({ player = GOLDSHIRE })
    local a = O().Add({ map = 1429, x = 0.48, y = 0.42, title = "Northshire" })
    local b = O().Add({ map = 1429, x = 0.3, y = 0.7, title = "Farm", setArrow = false })
    Settle()
    M.ShowMap(1429)
    Settle()
    M.ClearLog()
    PinUp(PinsFor(b)[1], "LeftButton")
    EQ(Store():Pinned() and Store():Pinned().uid, b, "G: a click points the arrow there")
    CHECK(#M.sounds > 0 and M.sounds[1].id == 3175, "G: with the set cue")
    Settle()
    CHECK(Shown(PinsFor(b)[1].ring) and not Shown(PinsFor(a)[1].ring), "G: the ring moves")
    M.Hover(PinsFor(b)[1])
    HAS(table.concat(M.tooltip, "\n"), "Shift-drag", "G: tooltip: it can be dragged")

    PinUp(PinsFor(a)[1], "RightButton")
    local texts = table.concat(M.MenuTexts(), "|")
    HAS(texts, "Set as arrow", "G: right-click: the menu")
    HAS(texts, "Remove", "G: right-click: Remove in it")
    EQ(Store():Pinned().uid, b, "G: a right-click does not take the arrow")
    M.ClickMenu("Set as arrow")
    EQ(Store():Pinned().uid, a, "G: menu Set as arrow")

    -- Shift-drag on the zone map
    M.SetModifier("SHIFT", true)
    local pin = PinsFor(b)[1]
    M.SetMapCursor(0.3, 0.7)
    pin:OnMouseDown("LeftButton")
    CHECK(pin.drag ~= nil, "G: Shift+press on a pin starts a drag")
    M.SetMapCursor(0.35, 0.65)
    M.Frame()
    NEAR(pin.__x, 0.35, 1e-9, "G: the pin follows the cursor")
    local late = O().Add({ map = 1429, x = 0.2, y = 0.2, title = "Mid-drag", setArrow = false })
    M.Frame()
    M.Frame()
    CHECK(pin.drag ~= nil, "G: a change mid-drag does not cancel the drag")
    EQ(I().World.pending, true, "G: the redraw waits for the drop")
    EQ(#PinsFor(late), 0, "G: (so the new waypoint is not drawn yet)")
    PinUp(pin, "LeftButton")
    M.SetModifier("SHIFT", false)
    Settle()
    local moved = O().Get(b)
    EQ(moved.map, 1429, "G: dropped on Elwynn")
    NEAR(moved.x, 0.35, 1e-9, "G: at the drop x")
    NEAR(moved.y, 0.65, 1e-9, "G: at the drop y")
    EQ(Store():Pinned().uid, a, "G: a drag is not a click (the arrow stays)")
    NEAR(PinsFor(b)[1].__x, 0.35, 1e-9, "G: redrawn where it was dropped")
    EQ(#PinsFor(late), 1, "G: the deferred redraw ran after the drop")
    EQ(I().World.pending, nil, "G: nothing left waiting")
    O().Remove(late)
    Settle()

    -- a Shift press that never travels is a click
    M.SetModifier("SHIFT", true)
    pin = PinsFor(b)[1]
    M.SetMapCursor(0.35, 0.65)
    pin:OnMouseDown("LeftButton")
    PinUp(pin, "LeftButton")
    M.SetModifier("SHIFT", false)
    EQ(Store():Pinned().uid, b, "G: a press without travel is a click")
    NEAR(O().Get(b).x, 0.35, 1e-9, "G: and moves nothing")
    -- without Shift there is no drag
    pin = PinsFor(b)[1]
    pin:OnMouseDown("LeftButton")
    EQ(pin.drag, nil, "G: no Shift, no drag")

    -- Shift-drag on the continent: dropped into the zone under the cursor
    M.SetMapID(1415)
    Settle()
    local inst, n, w = M.World(1429, 0.6, 0.6)
    local cx, cy = M.MapPos(1415, inst, n, w)
    M.SetModifier("SHIFT", true)
    pin = PinsFor(b)[1]
    M.SetMapCursor(pin.__x, pin.__y)
    pin:OnMouseDown("LeftButton")
    M.SetMapCursor(cx, cy)
    PinUp(pin, "LeftButton")
    M.SetModifier("SHIFT", false)
    Settle()
    moved = O().Get(b)
    EQ(moved.map, 1429, "G: a continent drop lands in the zone (Elwynn)")
    NEAR(moved.x, 0.6, 1e-6, "G: in zone coordinates (x)")
    NEAR(moved.y, 0.6, 1e-6, "G: in zone coordinates (y)")

    -- into the ocean: told to zoom in, nothing moves
    O().SetArrow(b)
    M.ClearLog()
    M.SetMapID(947)
    Settle()
    M.SetModifier("SHIFT", true)
    pin = PinsFor(b)[1]
    M.SetMapCursor(pin.__x, pin.__y)
    pin:OnMouseDown("LeftButton")
    M.SetMapCursor(0.48, 0.5)
    PinUp(pin, "LeftButton")
    M.SetModifier("SHIFT", false)
    Settle()
    CHECK(M.Has(M.prints, "Zoom in to move an order"), "G: an ocean drop says zoom in", M.prints[1])
    NEAR(O().Get(b).x, 0.6, 1e-6, "G: and the waypoint stays")
    EQ(Store():Pinned().uid, b, "G: a refused drop is not a click on some other pin either")
    local cues = 0
    for _, snd in ipairs(M.sounds) do if snd.id == 3175 then cues = cues + 1 end end
    EQ(cues, 0, "G: a refused drop is no click at all (no set cue)")
    local back = PinsFor(b)[1]
    CHECK(back and math.abs(back.__x - pin.__x) < 1 and back.data.uid == b, "G: the pin is redrawn")
    local inst947, n947, w947 = M.World(1429, 0.6, 0.6)
    local bx, by = M.MapPos(947, inst947, n947, w947)
    NEAR(back and back.__x, bx, 1e-4, "G: back where the waypoint is")
    M.HideMap()
    EQ(#W.map.writes, 0, "G: nothing assigned to WorldMapFrame")
    NOERR("G end")
end)

-- ===========================================================================
-- H: the map-click overlay
-- ===========================================================================
Section("H", function()
    local W = Boot({ player = GOLDSHIRE })
    local ov = I().Overlay.frame
    M.SetModifier("CTRL", true)
    CHECK(not M.Visible(ov), "H: map closed: Ctrl shows nothing")
    M.SetModifier("CTRL", false)
    M.ShowMap(1429)
    CHECK(not M.Visible(ov), "H: map open, no modifier: hidden")
    M.SetModifier("CTRL", true)
    CHECK(M.Visible(ov), "H: map open, Ctrl held: shown")
    M.SetModifier("SHIFT", true)
    CHECK(not M.Visible(ov), "H: Ctrl+Shift is not the modifier: hidden")
    M.SetModifier("SHIFT", false)
    CHECK(M.Visible(ov), "H: Ctrl alone again: shown")

    -- a right-click on the zone map
    M.ClearLog()
    local before = #O().List()
    M.SetMapCursor(0.3, 0.4)
    CHECK(M.Click(ov, "RightButton"), "H: the overlay takes the right-click")
    Settle()
    local list = O().List()
    EQ(#list, before + 1, "H: a waypoint added")
    local wp = list[#list]
    EQ(wp.map, 1429, "H: on the viewed zone")
    NEAR(wp.x, 0.3, 1e-12, "H: at the cursor x")
    NEAR(wp.y, 0.4, 1e-12, "H: at the cursor y")
    EQ(wp.source, "user", "H: the user's own")
    EQ(Store():Pinned() and Store():Pinned().uid, wp.uid, "H: and the arrow points there")
    CHECK(M.Has(M.prints, "waypoint set"), "H: announced as the user's action", M.prints[1])
    CHECK(#PinsFor(wp.uid) == 1, "H: its pin appears on the open map")

    -- the continent: the zone under the cursor, in zone coordinates
    M.SetMapID(1415)
    local inst, n, w = M.World(1429, 0.45, 0.55)
    local cx, cy = M.MapPos(1415, inst, n, w)
    M.SetMapCursor(cx, cy)
    M.Click(ov, "RightButton")
    Settle()
    list = O().List()
    wp = list[#list]
    EQ(wp.map, 1429, "H: a continent click is stored on Elwynn")
    NEAR(wp.x, 0.45, 1e-6, "H: zone x")
    NEAR(wp.y, 0.55, 1e-6, "H: zone y")
    local i2, n2, w2 = M.World(wp.map, wp.x, wp.y)
    CHECK(i2 == inst and math.abs(n2 - n) < 0.5 and math.abs(w2 - w) < 0.5, "H: the same world point")

    -- the ocean, the Cosmic map: zoom in
    M.ClearLog()
    local count = #O().List()
    M.SetMapCursor(0.02, 0.5)
    M.Click(ov, "RightButton")
    Settle()
    CHECK(M.Has(M.prints, "Zoom in to place an order"), "H: ocean on the continent: zoom in", M.prints[1])
    EQ(#O().List(), count, "H: nothing added")
    M.ClearLog()
    M.SetMapID(947)
    M.SetMapCursor(0.48, 0.5)
    M.Click(ov, "RightButton")
    CHECK(M.Has(M.prints, "Zoom in to place an order"), "H: Azeroth's ocean: zoom in")
    M.ClearLog()
    M.SetMapID(946)
    M.SetMapCursor(0.5, 0.5)
    M.Click(ov, "RightButton")
    Settle()
    CHECK(M.Has(M.prints, "Zoom in to place an order"), "H: Cosmic: zoom in")
    EQ(#O().List(), count, "H: still nothing added")

    -- dungeon maps answer for themselves
    M.ClearLog()
    M.SetMapID(234)
    M.SetMapCursor(0.5, 0.5)
    M.Click(ov, "RightButton")
    Settle()
    CHECK(not M.Has(M.prints, "Zoom in"), "H: a dungeon map is never told to zoom in")
    CHECK(M.Has(M.prints, "no positions"), "H: it says it has no positions", M.prints[1])
    M.ClearLog()
    M.SetMapID(347)
    M.SetMapCursor(0.5, 0.5)
    M.Click(ov, "RightButton")
    Settle()
    list = O().List()
    EQ(list[#list].map, 347, "H: a dungeon map with positions takes the waypoint")

    -- a pin over the overlay keeps its click
    M.SetMapID(1429)
    Settle()
    local pin = WorldPins()[1]
    CHECK(pin and pin:GetFrameLevel() > ov:GetFrameLevel(), "H: pins sit over the overlay (Shift+Right is the pin's)")

    -- ALT, OFF
    M.SetModifier("CTRL", false)
    DB().MapClickModifier = "ALT"
    Notify()
    M.SetModifier("CTRL", true)
    CHECK(not M.Visible(ov), "H: ALT chosen: Ctrl shows nothing")
    M.SetModifier("CTRL", false)
    M.SetModifier("ALT", true)
    CHECK(M.Visible(ov), "H: ALT chosen: Alt shows it")
    DB().MapClickModifier = "OFF"
    Notify()
    CHECK(not M.Visible(ov), "H: OFF: never")
    M.SetModifier("ALT", false)
    M.SetModifier("ALT", true)
    CHECK(not M.Visible(ov), "H: OFF: still never")
    M.SetModifier("ALT", false)
    DB().MapClickModifier = "SHIFT"
    Notify()
    M.SetModifier("SHIFT", true)
    CHECK(M.Visible(ov), "H: SHIFT chosen: Shift shows it")
    M.SetModifier("SHIFT", false)
    DB().MapClickModifier = "CTRL"
    Notify()

    -- map closed with the key held
    M.SetModifier("CTRL", true)
    CHECK(M.Visible(ov), "H: shown")
    M.HideMap()
    CHECK(not Shown(ov), "H: closing the map hides it")
    M.SetModifier("CTRL", false)

    -- Orders off
    DB().EnableOrders = false
    Notify()
    M.ShowMap(1429)
    M.SetModifier("CTRL", true)
    CHECK(not M.Visible(ov), "H: Orders off: no overlay")
    M.SetModifier("CTRL", false)
    DB().EnableOrders = true
    Notify()
    EQ(OverlayPass(), 1, "H: after all that, SetPassThroughButtons was still called once")
    NOERR("H end")

    -- a login in combat: nothing protected until it ends
    Boot({ player = GOLDSHIRE, combat = true })
    ov = I().Overlay.frame
    EQ(OverlayPass(), 0, "H: combat login: pass-through not attempted")
    EQ(ov.__passThrough, nil, "H: combat login: not set")
    M.ShowMap(1429)
    M.SetModifier("CTRL", true)
    CHECK(not M.Visible(ov), "H: combat login: the overlay waits (it would eat left clicks)")
    M.SetCombat(false)
    EQ(OverlayPass(), 1, "H: combat over: set once")
    EQ(table.concat(ov.__passThrough or {}, ","), "LeftButton,MiddleButton,Button4,Button5", "H: combat over: the buttons")
    CHECK(M.Visible(ov), "H: and the held key shows it")
    M.SetModifier("CTRL", false)
    M.SetCombat(true)
    local blocked = #M.blocked
    M.SetModifier("CTRL", true)
    CHECK(M.Visible(ov), "H: in combat: the overlay still shows (an unprotected frame)")
    M.SetModifier("CTRL", false)
    CHECK(not M.Visible(ov), "H: in combat: and hides")
    EQ(#M.blocked, blocked, "H: in combat: no protected call attempted")
    EQ(OverlayPass(), 1, "H: in combat: pass-through never set again")
    M.SetCombat(false)
    NOERR("H combat")
end)

-- ===========================================================================
-- I: coordinates
-- ===========================================================================
Section("I", function()
    local W = Boot({ player = GOLDSHIRE })
    local C = I().Coords
    local f = C.frame
    CHECK(not M.Visible(f), "I: hidden with the map closed")
    M.ShowMap(1429)
    M.Advance(0.15)
    CHECK(M.Visible(f), "I: shown with the map")
    HAS(f.text.__text, "Player  42.0, 65.5", "I: the player's coordinates on the zone")
    HAS(f.text.__text, "Cursor  --", "I: no cursor off the map")
    W.map.container.__mouseOver = true
    M.SetMapCursor(0.123, 0.456)
    M.Advance(0.12)
    HAS(f.text.__text, "Cursor  12.3, 45.6", "I: the cursor on the map")

    -- throttled to 0.1 s and written only on change
    local writes = C.writes
    M.Frame(0.02)
    M.Frame(0.02)
    EQ(C.writes, writes, "I: nothing new, nothing written")
    M.SetMapCursor(0.2, 0.2)
    M.Frame(0.02)
    HAS(f.text.__text, "Cursor  12.3, 45.6", "I: within 0.1 s the text waits")
    M.Advance(0.1)
    HAS(f.text.__text, "Cursor  20.0, 20.0", "I: then it follows")
    EQ(C.writes, writes + 1, "I: one write for one change")

    -- the map on screen, not the player's zone
    M.SetMapID(1415)
    M.Advance(0.12)
    local inst, n, w = PlayerWorld()
    local px, py = M.MapPos(1415, inst, n, w)
    HAS(f.text.__text, string.format("Player  %.1f, %.1f", px * 100, py * 100), "I: the continent's own numbers")
    M.SetMapID(1945)
    M.Advance(0.12)
    HAS(f.text.__text, "Player  --", "I: Outland: the player is not on it")
    M.SetMapID(1429)
    CHECK(not f.text.__text:find("[\128-\255]"), "I: plain ASCII (D11)")

    -- windowed mode hides BorderFrame; the readout is not on it
    WorldMapFrame.BorderFrame:Hide()
    M.Advance(0.12)
    CHECK(M.Visible(f) and Shown(f.text), "I: windowed mode: still shown")
    WorldMapFrame.BorderFrame:Show()

    -- level over the pins
    CHECK(f:GetFrameLevel() > M.PIN_LEVELS.PIN_FRAME_LEVEL_TOPMOST, "I: over every map pin", f:GetFrameLevel())
    CHECK(f:GetFrameLevel() <= 9000, "I: under the frame-level ceiling")
    EQ(f.__mouse, false, "I: never takes the mouse")

    -- Questie's own coordinates
    rawset(_G, "Questie", { db = { profile = { mapCoordinatesEnabled = true } } })
    M.Advance(0.12)
    CHECK(not Shown(f.text) and not Shown(f.bg), "I: Questie shows coordinates: ours step aside")
    Questie.db.profile.mapCoordinatesEnabled = false
    M.Advance(0.12)
    CHECK(Shown(f.text) and Shown(f.bg), "I: Questie's off: ours are back")
    EQ(Questie.db.profile.mapCoordinatesEnabled, false, "I: Questie's option never written")
    rawset(_G, "Questie", nil)

    -- the setting
    DB().MapCoords = false
    Notify()
    CHECK(not M.Visible(f), "I: MapCoords off: hidden")
    DB().MapCoords = true
    Notify()
    M.Advance(0.12)
    CHECK(M.Visible(f), "I: MapCoords on: shown")
    M.HideMap()
    CHECK(not M.Visible(f), "I: hidden with the map")
    EQ(#W.map.writes, 0, "I: nothing assigned to WorldMapFrame")
    NOERR("I end")
end)

-- ===========================================================================
-- J: reload, and the master switch
-- ===========================================================================
Section("J", function()
    Boot({ player = GOLDSHIRE })
    local a = AddOffset(80, 10, "Kept")
    O().Add({ map = 1941, x = 0.5, y = 0.5, title = "Far away", setArrow = false })
    Settle()
    EQ(MiniCount(), 1, "J: one pin before")
    local W = Reload({})
    NOERR("J reload")
    Settle()
    EQ(MiniCount(), 1, "J: after a reload the pin is back")
    CHECK(MiniPinFor(a) ~= nil, "J: the same waypoint")
    M.ShowMap(1429)
    Settle()
    EQ(#PinsFor(a), 1, "J: and on the world map")
    EQ(OverlayPass(), 1, "J: the new session set pass-through once")
    DB().EnableOrders = false
    Notify()
    Settle()
    EQ(MiniCount(), 0, "J: Orders off: no minimap pins")
    EQ(#WorldPins(), 0, "J: Orders off: no map pins")
    CHECK(not M.Visible(I().Coords.frame), "J: Orders off: no coordinates")
    DB().EnableOrders = true
    Notify()
    Settle()
    EQ(MiniCount(), 1, "J: on again")
    EQ(#W.map.writes, 0, "J: nothing assigned to WorldMapFrame")
    NOERR("J end")
end)

-- ===========================================================================
-- K: the real Commander_Minimap
-- ===========================================================================
Section("K", function()
    local W = Boot({ player = GOLDSHIRE, before = function(m)
        rawset(_G, "MinimapCluster", { BorderTop = m.NewWidget("Frame", nil, nil) })
        for _, name in ipairs({ "MinimapZoomOut", "MinimapZoomIn", "MinimapToggleButton", "MinimapNorthTag",
                "MinimapBorder", "GameTimeFrame", "MinimapZoneTextButton" }) do
            rawset(_G, name, m.NewWidget("Button", nil, nil))
        end
        rawset(_G, "GetMinimapZoneText", function() return "Goldshire" end)
        rawset(_G, "COMMANDER_MINIMAP_EVENTS", { COMMANDER_MINIMAP = "COMMANDER_MINIMAP" })
        rawset(_G, "CommanderMinimapDB", { TidyAddonButtons = true, TidyFadedOpacity = 0, BoardStyle = "NONE",
                                           MinimapScale = 1.37 })
        -- an addon's minimap button, the kind the tidy fades
        CreateFrame("Button", "TestAddonMinimapButton", Minimap)
    end })
    local diag = AddOffset(400, -400, "Far north-east")
    local near = AddOffset(50, 30, "Near")
    Settle()
    EQ(type(rawget(_G, "GetMinimapShape")), "nil", "K: no shape before Commander_Minimap loads")
    W.phase = "minimap"
    local chunk, err = loadfile(ADDONS .. "/Commander_Minimap/CommanderMinimap.lua")
    CHECK(chunk ~= nil, "K: CommanderMinimap.lua compiles", err)
    local ok, runErr = pcall(chunk)
    CHECK(ok, "K: CommanderMinimap.lua runs", runErr)
    M.Fire("ADDON_LOADED", "Commander_Minimap")
    M.Fire("PLAYER_ENTERING_WORLD", false, false)
    W.phase = "runtime"
    NOERR("K Commander_Minimap")
    EQ(type(GetMinimapShape), "function", "K: GetMinimapShape defined with the square mask")
    EQ(GetMinimapShape and GetMinimapShape(), "SQUARE", "K: it answers SQUARE")
    local written = {}
    for _, w in ipairs(M.writes) do if w.phase == "minimap" then written[w.name] = true end end
    CHECK(written.GetMinimapShape, "K: written by Commander_Minimap")
    M.Advance(0.6)
    local pt = LastPoint(MiniPinFor(diag))
    NEAR(pt and pt.x, 63, 0.06, "K: Orders' pins clamp to the square corner")
    NEAR(pt and pt.y, 48, 0.06, "K: and under its zone name at the top (70 - 22)")
    EQ(TestAddonMinimapButton.__alpha, 0, "K: the tidy ran (an addon button is faded)")
    for i = 1, MiniCount() do
        local pin = I().Mini.pins[i]
        CHECK(pin.__alpha == nil or pin.__alpha == 1, "K: the tidy never fades an Orders pin", pin.__alpha)
    end
    CHECK(I().Mini.driver.__alpha == nil, "K: nor the driver")
    CHECK(Shown(MiniPinFor(near)), "K: the near pin still shows")
    NOERR("K end")
end)

-- ===========================================================================
-- L: living with Commander_QuestLog's drawer and the maximized map (review)
-- ===========================================================================
Section("L", function()
    local W = Boot({ player = GOLDSHIRE })
    -- a long route (two-digit badges) that is running, a standalone target,
    -- another waypoint, and a second route that is not running
    local stops = {}
    for i = 1, 11 do stops[i] = { map = 1429, x = 0.30 + i * 0.03, y = 0.45 } end
    local rid = O().AddRoute({ title = "Long walk", mode = "ORDERED", stops = stops })
    local idle = O().AddRoute({ title = "Idle", mode = "ORDERED", start = false, stops = {
        { map = 1429, x = 0.2, y = 0.8 }, { map = 1429, x = 0.25, y = 0.8 } } })
    local other = O().Add({ map = 1429, x = 0.85, y = 0.3, title = "Other", setArrow = false })
    Settle()
    local route = Store():GetRoute(rid)
    -- minimap: a two-digit number gets a wider badge (review: render)
    local m1, m10 = MiniPinFor(route.stops[1]), MiniPinFor(route.stops[10])
    EQ(m1 and m1.__w, 14, "L: a one-digit minimap badge stays 14")
    EQ(m10 and m10.__w, 18, "L: \"10\" gets an 18-unit badge")
    EQ(m10 and m10.number.__text, "10", "L: ...numbered 10")

    M.ShowMap(1429)
    Settle()
    local function Level(uid) local p = PinsFor(uid)[1] return p and p:GetFrameLevel() end
    local base = M.PIN_LEVELS.PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST
    EQ(Level(route.stops[1]), base + 1, "L: no drawer: the target one over the others")
    EQ(Level(other), base, "L: ...the rest at their level")
    M.HideMap()

    -- QuestLog's drawer, as QuestLog builds it: a child of WorldMapFrame at
    -- max(container + 2200, TOPMOST + 10), built and shown from QuestLog's
    -- own OnShow hook (it loads after Orders, so its hook runs after ours)
    local drawer
    local drawerLevel = math.max(W.map.container:GetFrameLevel() + 2200, M.PIN_LEVELS.PIN_FRAME_LEVEL_TOPMOST + 10)
    WorldMapFrame:HookScript("OnShow", function()
        if not drawer then
            drawer = CreateFrame("Frame", "CommanderQuestLogMapDrawer", WorldMapFrame)
            drawer:SetFrameLevel(drawerLevel)
            drawer:Hide()
        end
        drawer:Show()
    end)
    M.ShowMap(1429)
    M.Advance(0.1)
    NOERR("L drawer")
    EQ(I().OverLevel(), drawerLevel, "L: Orders works out the drawer's level the way QuestLog does")
    CHECK(I().World.drawerHooked, "L: the drawer is watched once it exists (a frame after the map shows)")
    CHECK((Level(route.stops[1]) or 0) > drawerLevel, "L: the arrow's target over the drawer", Level(route.stops[1]))
    -- review-r2 orders: the whole running route lifted sat on the drawer's
    -- quest rows and took their clicks; its other badges stay under it
    EQ(Level(route.stops[5]), base, "L: the running route's other badges stay under it, at their level (review-r2)")
    CHECK(Level(route.stops[1]) > Level(route.stops[5]), "L: the target over its own route's badges")
    local function Lifted()
        local out = {}
        for _, p in ipairs(WorldPins()) do
            if (p:GetFrameLevel() or 0) > drawerLevel then out[#out + 1] = p.data and p.data.uid or "?" end
        end
        return out
    end
    local lifted = Lifted()
    EQ(#lifted, 1, "L: one pin over the drawer, never more (review-r2)")
    EQ(lifted[1], route.stops[1], "L: ...the arrow's target")
    O().RouteNext(rid)
    Settle()
    lifted = Lifted()
    CHECK(#lifted == 1 and lifted[1] == route.stops[2], "L: the next stop: it goes over the drawer, alone", table.concat(lifted, ","))
    EQ(Level(route.stops[1]), base, "L: ...and the stop left behind goes back under it")
    O().RoutePrev(rid)
    Settle()
    EQ(Lifted()[1], route.stops[1], "L: (back on the first stop)")
    CHECK((Level(other) or 0) < drawerLevel, "L: other waypoints stay under it", Level(other))
    CHECK((Level(Store():GetRoute(idle).stops[1]) or 0) < drawerLevel, "L: so does a route that is not running")
    CHECK(Level(route.stops[1]) <= 9000 + 20, "L: under the frame-level ceiling")
    local coords = I().Coords.frame
    EQ(coords:GetFrameLevel(), drawerLevel - 1, "L: the coordinates one under the drawer (never a tie)")
    CHECK(coords:GetFrameLevel() > M.PIN_LEVELS.PIN_FRAME_LEVEL_TOPMOST, "L: ...and still over every map pin")
    drawer:Hide()
    M.Advance(0.1)
    EQ(Level(route.stops[1]), base + 1, "L: the drawer folded away: back to one over the others")
    drawer:Show()
    M.Advance(0.1)
    CHECK((Level(route.stops[1]) or 0) > drawerLevel, "L: shown again: over it again")

    -- a refusal is said on the map (the maximized map's blackout covers chat)
    M.SetMapMaximized(true)
    local ov = I().Overlay.frame
    M.ClearLog()
    M.SetModifier("CTRL", true)
    M.SetMapCursor(0.02, 0.5)
    M.SetMapID(1415)
    M.Click(ov, "RightButton")
    M.SetModifier("CTRL", false)
    local notice = I().Notice.frame
    CHECK(notice ~= nil and M.Visible(notice), "L: an ocean click says so on the map")
    EQ(notice and notice.text.__text, "Zoom in to place an order", "L: ...in the same words")
    CHECK(M.Has(M.prints, "Zoom in to place an order"), "L: ...and in chat, for after the map closes")
    CHECK(notice and notice:GetFrameLevel() > drawerLevel, "L: ...over the drawer too")
    EQ(notice and notice:GetParent(), WorldMapFrame, "L: ...on the map itself")
    M.Advance(3.2)
    CHECK(not M.Visible(notice), "L: and it fades after a few seconds")
    M.Click(ov, "RightButton")
    M.HideMap()
    M.ShowMap(1429)
    CHECK(not M.Visible(notice), "L: closing the map clears it")

    -- Copy /way line from a pin's menu over the maximized map: the dialog
    -- draws over it (StaticPopup puts every dialog at DIALOG, under the
    -- map's FULLSCREEN), so the copy box is never an unseen keyboard trap
    Settle()
    M.ClearLog()
    local pin = PinsFor(other)[1]
    CHECK(pin ~= nil, "L: the pin to right-click")
    if pin then pin.__scripts.OnMouseUp(pin, "RightButton", true) end
    CHECK(M.ClickMenu("Copy /way line"), "L: its menu copies the /way line", table.concat(M.MenuTexts(), "|"))
    local pop = M.popups[#M.popups]
    EQ(pop and pop.which, "COMMANDER_ORDERS_COPY", "L: the copy box")
    EQ(WorldMapFrame:GetFrameStrata(), "FULLSCREEN", "L: (the maximized map is FULLSCREEN)")
    CHECK(pop and M.StrataOver(pop.dialog:GetFrameStrata(), WorldMapFrame:GetFrameStrata()),
        "L: the copy box draws over the maximized map", pop and pop.dialog:GetFrameStrata())
    EQ(pop and pop.dialog.editBox.__focus, true, "L: ...and the keyboard it takes is in plain sight")
    M.SetMapMaximized(false)
    NOERR("L end")
end)

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
