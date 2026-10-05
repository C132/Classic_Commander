-- Commander Ping: the Commander Orders half (luajit).
--
--     /opt/homebrew/bin/luajit Commander_Ping/Harness/ping_orders_smoke.lua
--
-- Runs from the AddOns root, from this folder or from anywhere else: the root
-- is found from this file's own path. Mutation hook: PING_RUNTIME=/path of a
-- copy of CommanderPing.lua to load in its place.
--
-- A minimap ping is an offset from the minimap's centre, and the only honest
-- test of turning it into a place is to put the place back on the minimap.
-- So this boots the REAL Commander Orders (its Geo owns the minimap yard
-- table and the forward placement its pins use) over the shared client mock,
-- Commander_Orders/Harness/orders_mock.lua (this build's real UiMap rows),
-- loads Commander Ping on top, fires MINIMAP_PING, follows the callout's
-- link, and checks the waypoint two ways: its world point against the
-- player's position plus the offset worked out here by hand, and
-- Geo.MinimapPlace(waypoint) against the pixel the ping was drawn at.
--
--   A  loads clean beside Orders; the panel registers; nothing written but its own
--   B  east, north, south-west: world yards = 2 * offset * radius, signs right
--   C  every zoom outdoors and indoors, the indoor tie broken by IsIndoors
--   D  a rotating minimap at four facings (the inverse of MinimapPlace's turn)
--   E  forward(inverse(ping)) == ping over a grid, rotating and not
--   F  past the zone's edge: placed through the continent on the right zone,
--      and a point no zone owns kept on the continent, still in place
--   G  the 530 frame (Eversong): a zone of its own frame answers for it, across
--      the Thalassian border Ghostlands does, and off the coast nothing
--      pretends to (the continent's own frame is instance 0)
--   H  no position (inside an instance): a plain callout, no link, no waypoint
--   I  the link: pinned on click, one Ping waypoint that each ping moves,
--      session-only, too-old links refused, other addons' links ignored
--   J  "Waypoint on Group Pings": automatic, temporary, never steals your arrow
--   K  Orders off or missing: the callout is the old one and nothing errors
--   L  globals (static): the module writes only its own

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local M = dofile(ADDONS .. "/Commander_Orders/Harness/orders_mock.lua")
local PING = ADDONS .. "/Commander_Ping"
local LUAJIT = "/opt/homebrew/bin/luajit"

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
local function NOERR(label)
    CHECK(#M.errors == 0, label .. ": no errors", M.errors[1])
    CHECK(#M.loadErrors == 0, label .. ": no load errors", M.loadErrors[1])
end
local function Section(name, fn)
    local ok, err = pcall(fn)
    CHECK(ok, name .. ": ran to the end", err)
end

-- ---------------------------------------------------------------------------
-- The client pieces Ping needs beyond the shared mock
-- ---------------------------------------------------------------------------
local linkCallbacks
local function ClientStubs()
    linkCallbacks = {}
    -- 2.5.6 delivers MINIMAP_PING as an event when the client says it is one
    rawset(_G, "C_EventUtils", { IsEventValid = function(event) return event == "MINIMAP_PING" end })
    rawset(_G, "UnitIsUnit", function(a, b) return a == b end)
    -- EventRegistry's callback surface, as CallbackRegistryMixin shapes it:
    -- a function callback is called as fn(owner, ...)
    rawset(_G, "EventRegistry", {
        RegisterCallback = function(_, event, fn, owner)
            linkCallbacks[#linkCallbacks + 1] = { event = event, fn = fn, owner = owner }
            return owner
        end,
    })
    SOUNDKIT.TELL_MESSAGE = 3081
end

-- What SetItemRef does with an addon: link on this client
-- (ItemRefHandlersShared.lua: EventRegistry:TriggerEvent("SetItemRef", ...))
local function ClickLink(link)
    for _, cb in ipairs(linkCallbacks) do
        if cb.event == "SetItemRef" then cb.fn(cb.owner, link, "[Waypoint]", "LeftButton", nil) end
    end
end

local SKIP = { CommanderOrdersPins = true, CommanderOrdersUI = true }
local GOLDSHIRE = { 1429, 0.42, 0.655 }

local function Boot(opts)
    opts = opts or {}
    local saved = opts.ping or {}
    return M.Boot({
        files = opts.noOrders and {} or nil,
        skipFiles = SKIP,
        player = opts.player or GOLDSHIRE,
        before = function() ClientStubs() end,
        afterFiles = function(m, w)
            w.phase = "ping"
            for _, file in ipairs({ "CommanderPingDB.lua", "CommanderPing.lua" }) do
                local path = (file == "CommanderPing.lua" and os.getenv("PING_RUNTIME")) or (PING .. "/" .. file)
                local chunk, err = loadfile(path)
                if not chunk then
                    m.loadErrors[#m.loadErrors + 1] = file .. ": " .. tostring(err)
                else
                    local ok, runErr = pcall(chunk)
                    if not ok then m.loadErrors[#m.loadErrors + 1] = file .. ": " .. tostring(runErr) end
                end
            end
            local copy = {}
            for k, v in pairs(saved) do copy[k] = v end
            rawset(_G, "CommanderPingDB", copy)
            m.Fire("ADDON_LOADED", "Commander_Ping")
            w.phase = "orders"
        end,
    })
end

local function O() return CommanderOrders end
local function G() return CommanderOrders.Geo end

-- The last callout's link payload, or nil
local function LastLink()
    for i = #M.prints, 1, -1 do
        local payload = M.prints[i]:match("|H(addon:CommanderPing:%d+)|h%[Waypoint%]|h")
        if payload then return payload end
        if M.prints[i]:find("pinged the minimap", 1, true) then return nil end
    end
    return nil
end

local function PingWaypoint()
    for _, wp in ipairs(O().List({ source = "Ping" })) do return wp end
    return nil
end

-- Fire a ping, follow its link, and hand back the waypoint
local function PingAndFollow(x, y, unit)
    M.ClearLog()
    M.Fire("MINIMAP_PING", unit or "party1", x, y)
    local link = LastLink()
    if link then ClickLink(link) end
    M.Advance(0.1)
    return PingWaypoint(), link
end

-- Where the ping must be, worked out here: the yard radius from the zoom
-- table, east = screen right, north = screen up, turned back by the facing
-- when the minimap rotates
local DIAMETERS = {
    outdoor = { 1400 / 3, 400, 1000 / 3, 800 / 3, 200, 400 / 3 },
    indoor = { 300, 240, 180, 120, 80, 50 },
}
local function Expected(px, py, radius, rotate, facing)
    local right, up = 2 * px * radius, 2 * py * radius
    if rotate then
        local c, s = math.cos(facing), math.sin(facing)
        right, up = right * c - up * s, right * s + up * c
    end
    local p = M.W.player
    return p.north + up, p.west - right
end

local function WorldOfWp(wp)
    if not wp then return nil end
    local inst, n, w = M.World(wp.map, wp.x, wp.y)
    return inst, n, w
end

local function CheckAt(wp, n, w, label)
    CHECK(wp ~= nil, label .. ": a waypoint")
    if not wp then return end
    local inst, wn, ww = WorldOfWp(wp)
    EQ(inst, M.W.player.inst, label .. ": in the player's world frame")
    NEAR(wn, n, 0.05, label .. ": north")
    NEAR(ww, w, 0.05, label .. ": west")
end

-- ---------------------------------------------------------------------------
-- A  loads clean beside Orders
-- ---------------------------------------------------------------------------
Section("A", function()
    Boot()
    NOERR("A: Ping over Orders")
    CHECK(CommanderPingDB.EnablePing == true, "A: defaults applied")
    EQ(CommanderPingDB.PingWaypoint, false, "A: the automatic waypoint ships off")
    local registered = false
    for _, cb in ipairs(linkCallbacks) do
        if cb.event == "SetItemRef" and type(cb.owner) == "table" then registered = true end
    end
    CHECK(registered, "A: the link handler is on EventRegistry's SetItemRef, with an owner of its own")
    local panel
    for _, cat in ipairs(M.W.categories) do
        if cat.__panel and cat.__panel._key == "Ping" then panel = cat.__panel end
    end
    CHECK(panel ~= nil, "A: the Ping page registered")
    for _, w in ipairs(M.writes) do
        if w.phase == "ping" then
            CHECK(w.name == "CommanderPingDB" or w.name == "COMMANDER_PING_EVENTS"
                or w.name == "CommanderPingFlash" or w.name == "CommanderPing_Test",
                "A: load-time globals are Ping's own", w.name)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- B  directions and scale, minimap north-up
-- ---------------------------------------------------------------------------
Section("B", function()
    Boot()
    M.SetGroup("party", { "Zuljin" })
    local R = DIAMETERS.outdoor[1] / 2
    NEAR(G().MinimapRadius(0, false), R, 1e-9, "B: Orders' radius at zoom 0 outdoors is the table's")

    local wp, link = PingAndFollow(0.25, 0)
    CHECK(link ~= nil, "B: the callout carries a [Waypoint] link")
    local n, w = Expected(0.25, 0, R)
    CheckAt(wp, n, w, "B east")
    NEAR(w, M.W.player.west - R / 2, 1e-9, "B: a quarter of the width east is half the radius east (west falls)")
    NEAR(O().Distance(wp.uid), R / 2, 0.05, "B: Orders measures the same 116.7 yd")
    EQ(wp.title, "Zuljin's ping", "B: titled with the pinger")
    EQ(wp.source, "Ping", "B: source Ping")
    EQ(wp.persistent, false, "B: session-only")
    EQ(wp.temporary, true, "B: temporary")

    wp = PingAndFollow(0, 0.25)
    n, w = Expected(0, 0.25, R)
    CheckAt(wp, n, w, "B north")
    NEAR(n, M.W.player.north + R / 2, 1e-9, "B: up the screen is north (north grows)")

    wp = PingAndFollow(-0.2, -0.3)
    n, w = Expected(-0.2, -0.3, R)
    CheckAt(wp, n, w, "B south-west")
    CHECK(n < M.W.player.north and w > M.W.player.west, "B: down-left is south and west")
    EQ(#O().List({ source = "Ping" }), 1, "B: three pings, one Ping waypoint")
    NOERR("B")
end)

-- ---------------------------------------------------------------------------
-- C  zoom levels, outdoors and in
-- ---------------------------------------------------------------------------
Section("C", function()
    Boot()
    M.SetGroup("party", { "Zuljin" })
    for zoom = 0, 5 do
        M.SetZoom(zoom)
        M.W.cvars.minimapZoom = tostring(zoom)
        M.W.cvars.minimapInsideZoom = tostring((zoom + 1) % 6)
        M.SetIndoors(false)
        local R = DIAMETERS.outdoor[zoom + 1] / 2
        local wp = PingAndFollow(0.3, 0.1)
        local n, w = Expected(0.3, 0.1, R)
        CheckAt(wp, n, w, "C outdoor zoom " .. zoom)
    end
    -- Indoors: the zoom matches minimapInsideZoom
    for zoom = 0, 5 do
        M.SetZoom(zoom)
        M.W.cvars.minimapInsideZoom = tostring(zoom)
        M.W.cvars.minimapZoom = tostring((zoom + 2) % 6)
        local R = DIAMETERS.indoor[zoom + 1] / 2
        local wp = PingAndFollow(-0.1, 0.35)
        local n, w = Expected(-0.1, 0.35, R)
        CheckAt(wp, n, w, "C indoor zoom " .. zoom)
    end
    -- Both CVars equal: IsIndoors() breaks the tie
    M.SetZoom(2)
    M.W.cvars.minimapZoom, M.W.cvars.minimapInsideZoom = "2", "2"
    M.SetIndoors(true)
    local wp = PingAndFollow(0.2, 0.2)
    local n, w = Expected(0.2, 0.2, DIAMETERS.indoor[3] / 2)
    CheckAt(wp, n, w, "C tie, indoors")
    M.SetIndoors(false)
    wp = PingAndFollow(0.2, 0.2)
    n, w = Expected(0.2, 0.2, DIAMETERS.outdoor[3] / 2)
    CheckAt(wp, n, w, "C tie, outdoors")
    EQ(M.W.zoomNudges or 0, 0, "C: the minimap's zoom was never nudged to find out")
    NOERR("C")
end)

-- ---------------------------------------------------------------------------
-- D  a rotating minimap
-- ---------------------------------------------------------------------------
Section("D", function()
    Boot()
    M.SetGroup("party", { "Zuljin" })
    M.W.cvars.rotateMinimap = "1"
    local R = DIAMETERS.outdoor[1] / 2
    -- Facing west, screen up is west
    M.SetFacing(math.pi / 2)
    local wp = PingAndFollow(0, 0.25)
    local p = M.W.player
    CheckAt(wp, p.north, p.west + R / 2, "D facing west, ping up = west")
    -- Facing south, screen right is west
    M.SetFacing(math.pi)
    wp = PingAndFollow(0.25, 0)
    CheckAt(wp, p.north, p.west + R / 2, "D facing south, ping right = west")
    -- Facing east, screen up is east
    M.SetFacing(3 * math.pi / 2)
    wp = PingAndFollow(0, 0.25)
    CheckAt(wp, p.north, p.west - R / 2, "D facing east, ping up = east")
    -- An odd angle, against the formula
    M.SetFacing(0.7)
    wp = PingAndFollow(0.15, -0.3)
    local n, w = Expected(0.15, -0.3, R, true, 0.7)
    CheckAt(wp, n, w, "D facing 0.7 rad")
    -- No facing to turn by: no place, so no link
    M.SetFacing(nil)
    M.ClearLog()
    M.Fire("MINIMAP_PING", "party1", 0.1, 0.1)
    EQ(LastLink(), nil, "D: with no facing the callout has no link")
    M.SetFacing(0)
    M.W.cvars.rotateMinimap = "0"
    NOERR("D")
end)

-- ---------------------------------------------------------------------------
-- E  forward(inverse(ping)) == ping
-- ---------------------------------------------------------------------------
Section("E", function()
    Boot()
    M.SetGroup("party", { "Zuljin" })
    local half = M.W.minimap.__w / 2
    local worst = 0
    for _, rotate in ipairs({ false, true }) do
        M.W.cvars.rotateMinimap = rotate and "1" or "0"
        for _, facing in ipairs({ 0, 1.1, 2.6, 4.0, 5.9 }) do
            M.SetFacing(facing)
            for _, zoom in ipairs({ 0, 3, 5 }) do
                M.SetZoom(zoom)
                M.W.cvars.minimapZoom = tostring(zoom)
                M.W.cvars.minimapInsideZoom = tostring((zoom + 1) % 6)
                local R = G().MinimapRadius(zoom, false)
                for _, pt in ipairs({ { 0.31, -0.12 }, { -0.27, 0.2 }, { 0.05, 0.4 } }) do
                    local wp = PingAndFollow(pt[1], pt[2])
                    local _, wn, ww = WorldOfWp(wp)
                    if wn then
                        local p = M.W.player
                        local px, py = G().MinimapPlace(wn - p.north, ww - p.west, R, facing, rotate, "ROUND", half, half)
                        local ex, ey = pt[1] * M.W.minimap.__w, pt[2] * M.W.minimap.__h
                        local err = math.max(math.abs(px - ex), math.abs(py - ey))
                        if err > worst then worst = err end
                    else
                        worst = math.huge
                    end
                end
            end
        end
    end
    CHECK(worst < 0.01, "E: every ping placed back by Geo.MinimapPlace lands on its own pixel", worst)
    M.W.cvars.rotateMinimap = "0"
    M.SetFacing(0)
    NOERR("E")
end)

-- ---------------------------------------------------------------------------
-- F  past the zone's edge
-- ---------------------------------------------------------------------------
Section("F", function()
    -- Elwynn's eastern edge: 210 yd east is Redridge
    Boot({ player = { 1429, 0.98, 0.5 } })
    M.SetGroup("party", { "Zuljin" })
    local R = DIAMETERS.outdoor[1] / 2
    local wp = PingAndFollow(0.45, 0)
    local n, w = Expected(0.45, 0, R)
    EQ(wp and wp.map, 1433, "F: past Elwynn's edge, placed on Redridge (through the continent)")
    CheckAt(wp, n, w, "F Redridge")

    -- Off the top of Elwynn into a gap between zone rectangles: no zone owns
    -- the point, so Orders keeps it on the continent, still in the right place
    Boot({ player = { 1429, 0.5, 0.03 } })
    M.SetGroup("party", { "Zuljin" })
    wp = PingAndFollow(0, 0.45)
    n, w = Expected(0, 0.45, R)
    EQ(wp and wp.map, 1415, "F: a point no zone owns stays on the Eastern Kingdoms map")
    CheckAt(wp, n, w, "F gap")

    -- Two neighbours hold the point (Undercity's rectangle sits inside
    -- Tirisfal's): the smaller, more particular one is named
    Boot({ player = { 1421, 0.726, 0.0238 } })
    M.SetGroup("party", { "Zuljin" })
    wp = PingAndFollow(0, 0.25)
    n, w = Expected(0, 0.25, R)
    EQ(wp and wp.map, 1458, "F: north out of Silverpine into Undercity, not the Tirisfal around it")
    CheckAt(wp, n, w, "F nested")
    NOERR("F")
end)

-- ---------------------------------------------------------------------------
-- G  the 530 frame
-- ---------------------------------------------------------------------------
Section("G", function()
    Boot({ player = { 1941, 0.5, 0.5 } })
    M.SetGroup("party", { "Zuljin" })
    EQ(M.W.player.inst, 530, "G: Eversong lives in instance 530")
    local R = DIAMETERS.outdoor[1] / 2
    local wp = PingAndFollow(-0.2, 0.15)
    local n, w = Expected(-0.2, 0.15, R)
    EQ(wp and wp.map, 1941, "G: placed on Eversong")
    CheckAt(wp, n, w, "G")
    NEAR(O().Distance(wp.uid), math.sqrt((0.4 * R) ^ 2 + (0.3 * R) ^ 2), 0.05, "G: and Orders can measure to it")

    -- Across the Thalassian border: the Eastern Kingdoms map's own frame is
    -- instance 0 and cannot place a 530 point, Ghostlands (530) can
    Boot({ player = { 1941, 0.5, 0.98 } })
    M.SetGroup("party", { "Zuljin" })
    wp = PingAndFollow(0, -0.45)
    n, w = Expected(0, -0.45, R)
    EQ(wp and wp.map, 1942, "G: south of Eversong, placed on Ghostlands (a neighbour in the same frame)")
    CheckAt(wp, n, w, "G Ghostlands")

    -- Off Eversong's western shore no 530 zone answers, and the continent
    -- must not pretend to: its own frame is instance 0, whose numbers happen
    -- to cover this 530 point. No link rather than a wrong place.
    Boot({ player = { 1941, 0.02, 0.5 } })
    M.SetGroup("party", { "Zuljin" })
    M.ClearLog()
    M.Fire("MINIMAP_PING", "party1", -0.45, 0)
    EQ(LastLink(), nil, "G: a 530 point no 530 map holds gets no link (never placed in instance 0)")
    EQ(PingWaypoint(), nil, "G: and no waypoint")
    NOERR("G")
end)

-- ---------------------------------------------------------------------------
-- H  no position
-- ---------------------------------------------------------------------------
Section("H", function()
    Boot()
    M.SetGroup("party", { "Zuljin" })
    M.SetNoPosition(true)
    M.ClearLog()
    M.Fire("MINIMAP_PING", "party1", 0.2, 0.2)
    CHECK(M.Has(M.prints, "Zuljin pinged the minimap"), "H: the callout still names the pinger", M.prints[1])
    EQ(LastLink(), nil, "H: but carries no link it could not honour")
    EQ(PingWaypoint(), nil, "H: and no waypoint")
    M.SetNoPosition(false)
    NOERR("H")
end)

-- ---------------------------------------------------------------------------
-- I  the link
-- ---------------------------------------------------------------------------
Section("I", function()
    Boot()
    M.SetGroup("party", { "Zuljin" })
    -- With the setting off, a ping alone adds nothing: only the click does
    M.ClearLog()
    M.Fire("MINIMAP_PING", "party1", 0.2, 0)
    M.Advance(0.2)
    CHECK(LastLink() ~= nil, "I: the callout offers the link")
    EQ(PingWaypoint(), nil, "I: and nothing is added until it is clicked")
    -- A pin of your own, then a clicked ping: asked for, so it takes the arrow
    local mine = O().Add({ map = 1429, x = 0.48, y = 0.42, title = "Northshire" })
    M.Advance(0.2)
    local wp = PingAndFollow(0.2, 0)
    local active = O().Active()
    EQ(active and active.uid, wp and wp.uid, "I: a clicked ping takes the arrow")
    EQ(active and active.why, "PINNED", "I: pinned outright")
    CHECK(O().Get(mine) ~= nil, "I: your own waypoint is still there")

    -- Each ping moves the one Ping waypoint
    local first = wp and wp.uid
    wp = PingAndFollow(-0.2, 0)
    EQ(wp and wp.uid, first, "I: the next ping moves the same waypoint")
    EQ(#O().List({ source = "Ping" }), 1, "I: still one")

    -- A link from long ago
    M.ClearLog()
    M.Fire("MINIMAP_PING", "party1", 0.1, 0.1)
    local old = LastLink()
    for _ = 1, 25 do M.Fire("MINIMAP_PING", "party1", 0.1, 0.1) end
    M.ClearLog()
    ClickLink(old)
    CHECK(M.Has(M.prints, "too old"), "I: a link 25 pings old says so", M.prints[1])

    -- Somebody else's addon: link: not ours to answer
    M.ClearLog()
    local before = #O().List()
    ClickLink("addon:SomeoneElse:3")
    ClickLink("addon:CommanderPingX:3")
    EQ(#M.prints, 0, "I: other addons' links are ignored")
    EQ(#O().List(), before, "I: and change nothing")

    -- Session-only
    M.Reload()
    EQ(#O().List({ source = "Ping" }), 0, "I: gone after a reload")
    NOERR("I")
end)

-- ---------------------------------------------------------------------------
-- J  "Waypoint on Group Pings"
-- ---------------------------------------------------------------------------
Section("J", function()
    Boot({ ping = { PingWaypoint = true } })
    M.SetGroup("party", { "Zuljin" })
    M.ClearLog()
    M.Fire("MINIMAP_PING", "party1", 0.25, 0)
    M.Advance(0.2)
    local wp = PingWaypoint()
    CHECK(wp ~= nil, "J: a ping becomes a waypoint without a click")
    local active = O().Active()
    EQ(active and active.uid, wp and wp.uid, "J: with no waypoint of yours, it takes the arrow")

    local mine = O().Add({ map = 1429, x = 0.48, y = 0.42, title = "Northshire" })
    M.Advance(0.2)
    M.Fire("MINIMAP_PING", "party1", -0.25, 0)
    M.Advance(0.2)
    active = O().Active()
    EQ(active and active.uid, mine, "J: with one of yours pinned, a ping never steals the arrow")
    local p = M.W.player
    CheckAt(PingWaypoint(), p.north, p.west + DIAMETERS.outdoor[1] / 4, "J: but the Ping waypoint moved")

    -- Your own pings stay out of it unless you asked for them
    local where = PingWaypoint()
    M.Fire("MINIMAP_PING", "player", 0.4, 0.4)
    M.Advance(0.2)
    NEAR(PingWaypoint().x, where.x, 1e-12, "J: your own ping is ignored by default")

    -- The automatic ping never ASKS for the arrow. Orders refuses a
    -- temporary pin only over a pinned waypoint (Store PinFromAdd), so a
    -- ping that asked re-pinned the arrow away from a running route
    -- (StartRoute clears the pin), from a waypoint of yours followed as the
    -- closest, and out of a Clear.
    O().Remove(mine)
    local routeId = O().AddRoute({
        title = "Open quests: Elwynn", source = "QuestLog", key = "open:12", mode = "ORDERED",
        stops = {
            { map = 1429, x = 0.40, y = 0.50, title = "Giver A" },
            { map = 1429, x = 0.50, y = 0.40, title = "Giver B" },
        },
    })
    M.Advance(0.2)
    EQ(O().Active() and O().Active().why, "ROUTE", "J: (a route is running)")
    M.Fire("MINIMAP_PING", "party1", 0.15, 0.15)
    M.Advance(0.2)
    active = O().Active()
    EQ(active and active.why, "ROUTE", "J: a ping never takes the arrow from a running route")
    EQ(active and active.title, "Giver A", "J: ...it stays on the route's stop")
    O().RemoveRoute(routeId)
    local spot = O().Add({ map = 1429, x = 0.43, y = 0.66, title = "My spot", setArrow = false })
    M.Advance(0.2)
    EQ(O().Active() and O().Active().uid, spot, "J: (your mark is followed as the closest)")
    M.Fire("MINIMAP_PING", "party1", -0.15, 0.15)
    M.Advance(0.2)
    active = O().Active()
    EQ(active and active.uid, spot, "J: a ping never takes the arrow from your closest mark")
    EQ(active and active.why, "CLOSEST", "J: ...and pins nothing")
    O().ClearArrow()
    M.Advance(0.2)
    M.Fire("MINIMAP_PING", "party1", 0.1, -0.1)
    M.Advance(0.2)
    EQ(O().Active(), nil, "J: a ping never undoes a Clear")
    NOERR("J")
end)

-- ---------------------------------------------------------------------------
-- K  Orders off or missing
-- ---------------------------------------------------------------------------
Section("K", function()
    Boot({ ping = { PingWaypoint = true } })
    M.SetGroup("party", { "Zuljin" })
    CommanderOrdersDB.EnableOrders = false
    M.ClearLog()
    M.Fire("MINIMAP_PING", "party1", 0.2, 0.2)
    M.Advance(0.2)
    CHECK(M.Has(M.prints, "Zuljin pinged the minimap"), "K: Orders off: the callout as before")
    EQ(LastLink(), nil, "K: with no link")
    EQ(PingWaypoint(), nil, "K: and no waypoint, setting or not")

    Boot({ noOrders = true, ping = { PingWaypoint = true } })
    NOERR("K: Ping alone")
    M.SetGroup("party", { "Zuljin" })
    M.ClearLog()
    M.Fire("MINIMAP_PING", "party1", 0.2, 0.2)
    M.Advance(0.2)
    CHECK(M.Has(M.prints, "Zuljin pinged the minimap"), "K: no Orders: the callout as before")
    EQ(LastLink(), nil, "K: with no link")
    NOERR("K: a ping with no Orders")
end)

-- ---------------------------------------------------------------------------
-- L  globals (static)
-- ---------------------------------------------------------------------------
local ALLOWED_READ = {}
for name in ([[
type tonumber tostring ipairs pairs pcall print string math
CreateFrame Minimap C_Timer C_Map C_CVar GetCVar CreateVector2D UnitPosition GetPlayerFacing
IsIndoors UnitIsUnit UnitName PlaySound SOUNDKIT C_EventUtils EventRegistry
Commander CommanderPingDB COMMANDER_PING_EVENTS CommanderPing_Test CommanderOrders _G
]]):gmatch("[%w_]+") do ALLOWED_READ[name] = true end
local ALLOWED_WRITE = { CommanderPingDB = true, COMMANDER_PING_EVENTS = true, CommanderPing_Test = true }
Section("L", function()
    for _, file in ipairs({ "CommanderPingDB.lua", "CommanderPing.lua" }) do
        local pipe = assert(io.popen(string.format("%q -bl %q 2>/dev/null", LUAJIT, PING .. "/" .. file)))
        local seen = {}
        for line in pipe:lines() do
            local op, name = line:match("(G[GS]ET)%s+%d+%s+%d+%s+;%s+\"([%w_]+)\"")
            if op and not seen[op .. name] then
                seen[op .. name] = true
                if op == "GGET" then
                    CHECK(ALLOWED_READ[name], "L: " .. file .. " reads only what it means to", name)
                else
                    CHECK(ALLOWED_WRITE[name], "L: " .. file .. " writes only its own globals", name)
                end
            end
        end
        pipe:close()
    end
end)

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
