-- Commander Orders: the runtime.
--
-- The model (CommanderOrdersStore.lua) decides which waypoint the arrow
-- follows and when one is reached; the geometry (CommanderOrdersGeo.lua) does
-- every sum. This file is where the client comes in: it reads the player's
-- position and facing, feeds both to them, and draws what they answer. It
-- also owns the public API every consumer calls, the /way family, the TomTom
-- compatibility shim, group sharing, the corpse run, places and the paste
-- import.
--
-- ---------------------------------------------------------------------------
-- What the old module got wrong, and where each one is fixed here
-- ---------------------------------------------------------------------------
-- D1  It paired UnitPosition's WEST with the waypoint's NORTH: 12,952 yd
--     shown for a 582 yd walk, an arrow that never arrived. Here the
--     player's position is `north, west = UnitPosition("player")`, the
--     waypoint's is Geo.ToWorld (vector .x = north), and only Geo pairs them.
--     orders_harness.lua walks Goldshire to Northshire through the real
--     UnitPosition axis order and checks the arrow reads 582 yd.
-- D2  Account-wide persistence. Waypoints now live per character
--     (CommanderOrdersChar.Store); see CommanderOrdersDB.lua.
-- D3  One slot that every caller overwrote. Waypoints are records with an
--     owner (source, key); the Store's targeting rule says who has the arrow.
-- D4  Raw instance ids: Eversong and Hellfire are both 530. The straight
--     arrow is drawn only when the world instance AND the landmass match
--     (Geo.SameLandmass); otherwise the arrow says where the target is and
--     how to get there (Data.CONNECTIONS), never a fake straight line.
-- D5/D12  Silent states. Every state the arrow can be in is named on it:
--     turn around, other landmass, no position here, in flight, arrived,
--     group member not visible, no heading. It never points north because a
--     value was missing.
-- D7  IssueOrder ignored the master switch. Every add refuses with
--     "disabled" while Orders is off, the legacy wrapper returns false.
-- D8  A canvas click handler on the world map (the taint factory TomTom
--     removed). Map input is CommanderOrdersPins.lua's overlay; nothing here
--     touches the canvas.
-- D9  A left-click on the arrow cancelled the order, and the arrow ate every
--     click and camera turn. Locked, the arrow is click-through (DECISIONS
--     D9, Tracer D12's precedent); it takes the mouse only while the chosen
--     modifier is held, and then a left-click opens the manager and a right-
--     click opens a menu. Nothing is ever cleared by a stray click.
-- D10 Fixed at TOP -220, in the raid warning band. The arrow wears the
--     suite's HUD chrome (move, scale, style, lock), defaulting to TOP -340,
--     under the top-centre band the suite's toasts, Blizzard's zone text and
--     the raid warnings share (3.0's -140 sat inside it; review: render).
-- D11 18 degree steps. The arrow turns every frame (one SetRotation), eased
--     by Geo.AngleFilter; only the text is throttled, to 10 Hz, and written
--     only when it changes.
-- D15 One sound for issued and arrived. Two cues now (Data.SOUNDS).
-- D17 The driver ran every frame for the whole session. It sleeps whenever
--     the Store says nothing needs ticking and wakes on the events that can
--     change that.
--
-- ---------------------------------------------------------------------------
-- Traps worth knowing before changing anything
-- ---------------------------------------------------------------------------
-- * The shared HUD chrome calls SetPassThroughButtons once, on its first
--   apply. That call is protected: in combat it is refused WITHOUT raising,
--   the pcall says ok, and the chrome would then believe the frame passes
--   left clicks through (critic 2.12). So the arrow is built and first
--   chromed at PLAYER_LOGIN out of combat; a login in combat (a /reload mid
--   fight) waits for PLAYER_REGEN_ENABLED before the first apply.
-- * The chrome owns the root frame's mouse and its OnMouseUp. After every
--   ApplyHudChrome the root's mouse is switched off again here, and the
--   clickable surface is a child Button (`hit`), enabled only while the
--   modifier is down. MODIFIER_STATE_CHANGED toggling the mouse of an
--   unprotected frame is legal in combat.
-- * GetPlayerMapPosition allocates a Vector2D per call (the old module's
--   19 KB/s of garbage). The per-frame arrow uses UnitPosition only; the map
--   position is refreshed once a second, and on demand for "here" and routes.
--   A followed group member is measured through UnitPosition(unit) and its
--   map id too, and a quiet 10 Hz pass allocates nothing (Store:Tick's
--   shared empty event list, Store:ArrivalState).
-- * The global sin/cos/atan2 take degrees on this client. Only Geo does
--   trigonometry, with math.*; this file only feeds it.
-- * The Store hands out its LIVE records. The public API hands out copies
--   (Store.Copy), so a consumer can never edit a waypoint behind the Store's
--   back. The pins and the manager (same addon) read the live store through
--   CommanderOrders.R.
-- * FrameXML tables are only ever ADDED to: keys in StaticPopupDialogs and
--   SlashCmdList, hooks on WorldMapFrame. TomTom is the one global created
--   that another addon could have owned, and only while it is absent.
--
-- ---------------------------------------------------------------------------
-- Globals written (and nothing else): CommanderOrders (the API, shared with
-- the other Orders files), CommanderOrdersDB / CommanderOrdersChar (in the DB
-- file), COMMANDER_ORDERS_EVENTS, the legacy CommanderOrders_* functions,
-- BINDING_*, SLASH_COMMANDERORDERS_* with their SlashCmdList entries, the
-- frames CommanderOrdersArrow and CommanderOrdersMenu, and TomTom (the shim,
-- only when no TomTom is loaded and the setting allows it).
--
-- CommanderOrders.R is the surface CommanderOrdersPins.lua and
-- CommanderOrdersUI.lua build on: the live store, a fresh ctx, world
-- positions, the arrow's current view, menus and the copy box. Their hooks
-- are called guarded: O.Pins.Refresh() after any change, O.Pins.OnTarget(uid)
-- when the arrow changes hands, O.UI.Open(uid) / O.UI.OpenPaste(text) /
-- O.UI.Toggle() for the manager.
--
-- The public API (every function pcall'd at the boundary, "The public API"
-- below) is SPEC 6 plus what the consumers asked for while being wired in:
-- Entrance(map) for Commander_Guide's raid doors, Status() for the TopBar's
-- Nav segment, SharePoint(spec, channel) for "Rally on me" and the TopBar's
-- Shift-click, and the route, place, paste and manager functions the pins
-- and the manager use. DECISIONS.md D21 lists them all.

CommanderOrders = CommanderOrders or {}
local O = CommanderOrders
local G = O.Geo
local S = O.Store
local D = O.Data
O.R = O.R or {}
local R = O.R

BINDING_HEADER_COMMANDERORDERS = "Commander Orders"
BINDING_NAME_COMMANDERORDERS_MANAGER = "Open or close the waypoint manager"
BINDING_NAME_COMMANDERORDERS_CLEAR = "Remove the active waypoint"
BINDING_NAME_COMMANDERORDERS_HERE = "Waypoint where you stand"
BINDING_NAME_COMMANDERORDERS_NEXT = "Next route stop"
BINDING_NAME_COMMANDERORDERS_PREV = "Previous route stop"
BINDING_NAME_COMMANDERORDERS_CLOSEST = "Point the arrow at the closest waypoint"
BINDING_NAME_COMMANDERORDERS_SHARE = "Share the active waypoint with your group"
BINDING_NAME_COMMANDERORDERS_ARROW = "Show or hide the arrow"

local type, pairs, ipairs, pcall, tostring, tonumber = type, pairs, ipairs, pcall, tostring, tonumber
local format, strlower = string.format, string.lower
local abs, floor, sin, PI = math.abs, math.floor, math.sin, math.pi
local HUGE = math.huge

local AR = D.ARROW
local TEX = D.TEXTURES
local PAL = D.PALETTE
local TURN_AROUND = AR.TURN_AROUND * PI / 180
local DEAD_AHEAD = AR.DEAD_AHEAD * PI / 180
local POSITION_REFRESH = 1.0        -- seconds between map-position samples for ctx.player
local TOLERANCE = S.TOLERANCE

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local store                         -- the Store (S.Load at ADDON_LOADED)
local env                           -- the Geo env, built once
local loggedIn = false
local resolvers = { entrance = {}, zone = {} }
local removeListeners = {}
local mapNames = {}

-- The arrow's state; the view is what the 10 Hz pass decided to show
local A = {
    built = false, chromeReady = false, chromePending = false,
    angle = {}, eta = {}, textAcc = 0,
    view = { mode = "NONE" }, text = {}, colour = {}, rel = nil,
    inCombat = false, mapShown = false, pulse = 0,
    hintKey = nil, resolverGen = 0,
    unitPos = {},                       -- { map } of a followed unit, reused every pass
}

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------
local function IsNum(v)
    return type(v) == "number" and v == v and v ~= HUGE and v ~= -HUGE
end

local function DB()
    local db = CommanderOrdersDB
    if type(db) ~= "table" then return O.Defaults or {} end
    return db
end

local function Report(err)
    if geterrorhandler then
        local handler = geterrorhandler()
        if handler then handler(err) end
    end
end

local function Say(msg)
    print("Commander Orders: " .. msg)
end

local function Announce(msg)
    if DB().Announce then Say(msg) end
end

local function Clock()
    return GetTime and GetTime() or 0
end

local function Epoch()
    return time and time() or 0
end

local function Trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Cut to n bytes on a UTF-8 boundary, with "..." (three plain dots: D11)
local function Cut(s, n)
    if type(s) ~= "string" or #s <= n then return s end
    local cut = n - 3
    while cut > 0 do
        local b = s:byte(cut + 1)
        if not b or b < 0x80 or b >= 0xC0 then break end
        cut = cut - 1
    end
    return s:sub(1, cut) .. "..."
end

local function UidOf(v)
    if type(v) == "table" then return v.uid end
    return v
end

local function Cue(kind)
    local db = DB()
    if not db.Sounds then return end
    local sound = D.SOUNDS[kind]
    if not (sound and PlaySound) then return end
    local id = (SOUNDKIT and SOUNDKIT[sound.kit]) or sound.id
    pcall(PlaySound, id, db.SoundChannel == "Master" and "Master" or "SFX")
end

local function Notify(event, ...)
    if Commander and Commander.Notify then Commander.Notify(event, ...) end
end

local function CallPins(method, ...)
    local pins = O.Pins
    local fn = type(pins) == "table" and pins[method]
    if type(fn) == "function" then
        local ok, err = pcall(fn, ...)
        if not ok then Report(err) end
    end
end

local function CallUI(method, ...)
    local ui = O.UI
    local fn = type(ui) == "table" and ui[method]
    if type(fn) ~= "function" then return false end
    local ok, err = pcall(fn, ...)
    if not ok then Report(err) end
    return true
end

-- The Console accent (the TopBar soft-fail), lifted when it is too dark to
-- read as text over the world (Console's Void is near black)
local function Accent()
    local key = (CommanderConsoleDB and CommanderConsoleDB.ConsoleColor) or "STEEL"
    local r, g, b = 1, 1, 1
    if key == "CLASS" then
        local class = UnitClass and select(2, UnitClass("player"))
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then r, g, b = c.r, c.g, c.b end
    else
        for _, c in ipairs(CommanderConsole_Colors or {}) do
            if c.value == key then r, g, b = c.r or 1, c.g or 1, c.b or 1 break end
        end
    end
    local lum = 0.3 * r + 0.59 * g + 0.11 * b
    if lum < 0.55 then
        local k = (0.55 - lum) / (1 - lum + 1e-6)
        r, g, b = r + (1 - r) * k, g + (1 - g) * k, b + (1 - b) * k
    end
    return r, g, b
end

-- ---------------------------------------------------------------------------
-- The client: maps and positions
-- ---------------------------------------------------------------------------
local function Env()
    if env then return env end
    env = {}
    if C_Map then
        env.mapInfo = function(id) return C_Map.GetMapInfo(id) end
        env.worldPos = function(m, x, y)
            return C_Map.GetWorldPosFromMapPos(m, CreateVector2D(x, y))
        end
        env.rectOnMap = function(child, top) return C_Map.GetMapRectOnMap(child, top) end
        env.mapInfoAtPosition = function(m, x, y) return C_Map.GetMapInfoAtPosition(m, x, y) end
        env.mapChildren = function(id) return C_Map.GetMapChildrenInfo(id) end
    end
    return env
end

local function MapInfo(map)
    if type(map) ~= "number" or not (C_Map and C_Map.GetMapInfo) then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, map)
    if ok and type(info) == "table" then return info end
    return nil
end

local function MapName(map)
    if type(map) ~= "number" then return nil end
    local name = mapNames[map]
    if name == nil then
        local info = MapInfo(map)
        name = info and info.name or false
        mapNames[map] = name
    end
    return name or nil
end

local function PlayerMap()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
    if ok and type(map) == "number" then return map end
    return nil
end

local function VectorXY(v)
    if type(v) ~= "table" and type(v) ~= "userdata" then return nil end
    local x, y = v.x, v.y
    if (x == nil or y == nil) and v.GetXY then x, y = v:GetXY() end
    if IsNum(x) and IsNum(y) then return x, y end
    return nil
end

local function UnitMapPos(unit)
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local ok, map = pcall(C_Map.GetBestMapForUnit, unit)
    if not ok or type(map) ~= "number" then return nil end
    local ok2, pos = pcall(C_Map.GetPlayerMapPosition, map, unit)
    if not ok2 then return nil end
    local x, y = VectorXY(pos)
    if not x or x < 0 or x > 1 or y < 0 or y > 1 or (x == 0 and y == 0) then return nil end
    return map, x, y
end

local function PlayerMapPos()
    return UnitMapPos("player")
end

-- north, west, instance of a unit (the player by default), nil when the
-- client has none (instances, loading)
local function UnitWorld(unit)
    if not UnitPosition then return nil end
    local ok, north, west, _, inst = pcall(UnitPosition, unit or "player")
    if ok and IsNum(north) and IsNum(west) and inst ~= nil then return north, west, inst end
    return nil
end

local function Facing()
    if not GetPlayerFacing then return nil end
    local ok, f = pcall(GetPlayerFacing)
    if ok and IsNum(f) then return f end
    return nil
end

-- World position of any {map, x, y} table, cached on the table and checked
-- against its numbers (records, alternatives and the player table all reuse
-- their tables; GetWorldPosFromMapPos allocates)
local worldCache = setmetatable({}, { __mode = "k" })
local function PosWorld(p)
    if type(p) ~= "table" or type(p.map) ~= "number" then return nil end
    local c = worldCache[p]
    if not (c and c.map == p.map and c.x == p.x and c.y == p.y) then
        local inst, n, w = G.ToWorld(Env(), p.map, p.x, p.y)
        c = { map = p.map, x = p.x, y = p.y, inst = inst, n = n, w = w }
        worldCache[p] = c
    end
    if c.inst == nil then return nil end
    return c.inst, c.n, c.w
end

local function Landmass(map, inst)
    return G.Landmass(Env(), map, inst)
end

-- A point on a world or continent map, as the zone under it (DECISIONS D13:
-- a continent map holds two coordinate frames, a zone one). Any other map,
-- or a point no zone answers for, comes back as it was given.
local function OnZone(m, x, y)
    local info = MapInfo(m)
    if info and type(info.mapType) == "number" and info.mapType <= 2 then
        local zm, zx, zy = G.ZoneAt(Env(), m, x, y)
        if zm then return zm, zx, zy end
    end
    return m, x, y
end

-- The map a unit is on (C_Map.GetBestMapForUnit: a number, no allocation)
local function UnitMap(unit)
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local ok, map = pcall(C_Map.GetBestMapForUnit, unit)
    if ok and type(map) == "number" then return map end
    return nil
end

local function Faction()
    if not UnitFactionGroup then return nil end
    local f = UnitFactionGroup("player")
    return f
end

local function Metric()
    if A.metric == nil then
        local ok, region = pcall(function() return GetCurrentRegion and GetCurrentRegion() end)
        A.metric = (ok and type(region) == "number" and region ~= 1) or false
    end
    return A.metric
end

local function Distance(yards)
    return G.FormatDistance(yards, DB().Units or "AUTO", Metric())
end

-- A font object by name, or a stock one with an outline put on it. Only the
-- outlined variants the 2.5.6 FrameXML is seen to use are certain to exist
-- (GameFontHighlightOutline, GameFontHighlightSmallOutline); a FontString
-- inheriting a missing one has no font, and its first SetText raises.
local function OutlinedText(parent, name, fallback)
    if type(_G[name]) == "table" then return parent:CreateFontString(nil, "OVERLAY", name) end
    local fs = parent:CreateFontString(nil, "OVERLAY", fallback)
    local file, size = fs:GetFont()
    if file and size then fs:SetFont(file, size, "OUTLINE") end
    return fs
end

-- ---------------------------------------------------------------------------
-- ctx: what the Store needs to know about the player (one reused table)
-- ---------------------------------------------------------------------------
local ctx = {}
local ctxPlayer = { map = nil, x = 0.5, y = 0.5 }
local playerNow = { at = -1 }          -- UnitPosition sampled for the current pass

local function SamplePlayer(now)
    if playerNow.at == now then return end
    playerNow.at = now
    playerNow.n, playerNow.w, playerNow.inst = UnitWorld("player")
end

ctx.sameLandmass = function(a, b) return G.SameLandmass(Env(), a, b) end

ctx.distance = function(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return nil end
    if b == ctx.player then a, b = b, a end
    if a == ctx.player then
        local pn, pw, pinst = playerNow.n, playerNow.w, playerNow.inst
        if not pn then return nil end
        local bi, bn, bw = PosWorld(b)
        if bi == nil or bi ~= pinst then return nil end
        if not G.SameLandmass(Env(), a.map, b.map, pinst, bi) then return nil end
        return G.Distance(pn, pw, bn, bw)
    end
    local ai, an, aw = PosWorld(a)
    local bi, bn, bw = PosWorld(b)
    if ai == nil or bi == nil or ai ~= bi then return nil end
    if not G.SameLandmass(Env(), a.map, b.map, ai, bi) then return nil end
    return G.Distance(an, aw, bn, bw)
end

-- A group member's map position for the Store (kind "unit"): sampled at
-- most once a second per unit into one reused table. GetPlayerMapPosition
-- allocates a Vector2D on every call; the 10 Hz pass and the per-frame arrow
-- measure a followed unit through UnitPosition instead (UnitDistance), so
-- this answers only the Store's own occasional asks (the manager's rows,
-- API.Distance, a tick whose distance the runtime could not measure).
local unitPos = {}
ctx.unitPosition = function(unit)
    local now = Clock()
    local p = unitPos[unit]
    if not (p and p.at and now - p.at < POSITION_REFRESH and now >= p.at) then
        if not p then
            p = {}
            unitPos[unit] = p
        end
        p.at = now
        p.map, p.x, p.y = UnitMapPos(unit)
    end
    if not p.map then return nil end
    return p
end

-- force: sample the map position now (here, routes, Optimize)
local function BuildCtx(now, force)
    now = now or Clock()
    local db = DB()
    local map = PlayerMap()
    if map then
        if force or map ~= ctxPlayer.map or not ctxPlayer.at or now - ctxPlayer.at >= POSITION_REFRESH then
            local m2, x, y = PlayerMapPos()
            if m2 == map then ctxPlayer.x, ctxPlayer.y = x, y end
            ctxPlayer.at = now
        end
        ctxPlayer.map = map
        ctx.player = ctxPlayer
    else
        ctx.player = nil
    end
    ctx.ghost = (UnitIsGhost and UnitIsGhost("player")) and true or false
    ctx.corpseArrow = db.CorpseArrow ~= false
    ctx.autoClosest = db.AutoClosest ~= false
    ctx.arriveYards = db.ArriveYards
    ctx.onTaxi = (UnitOnTaxi and UnitOnTaxi("player")) and true or false
    ctx.now = now
    SamplePlayer(now)
    return ctx
end

-- ---------------------------------------------------------------------------
-- The store, saving it, and telling everyone it changed
-- ---------------------------------------------------------------------------
local changePending, changeReason, changeForced = false, nil, false
local seenVersion = -1
local Wake        -- the driver's alarm clock (defined with the driver)

local function SaveStore()
    if not store then return end
    if type(CommanderOrdersChar) ~= "table" then return end
    local ok, plain = pcall(store.Serialize, store)
    if ok then CommanderOrdersChar.Store = plain else Report(plain) end
end

local function Flush()
    changePending = false
    if not store then return end
    local reason, forced = changeReason, changeForced
    changeReason, changeForced = nil, false
    if store.version ~= seenVersion or forced then
        if store.version ~= seenVersion then
            seenVersion = store.version
            SaveStore()
        end
        Notify(COMMANDER_ORDERS_EVENTS.CHANGED, reason or "change")
        CallPins("Refresh")
    end
    if Wake then Wake() end
end

-- Debounced: one CHANGED (and one pin refresh) per frame however many
-- mutations a frame makes
local function Changed(reason, force)
    changeReason = changeReason or reason
    if force then changeForced = true end
    if changePending then return end
    changePending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, Flush)
    else
        Flush()
    end
end

local function LoadStore()
    if store then return store end
    local char = CommanderOrdersChar
    local plain = type(char) == "table" and type(char.Store) == "table" and char.Store or nil
    store = S.Load(plain, Clock, Epoch)
    store.onRemove = function(wp, reason)
        for _, fn in ipairs(removeListeners) do
            local ok, err = pcall(fn, wp, reason)
            if not ok then Report(err) end
        end
    end
    seenVersion = store.version
    return store
end

local function Available()
    if not store then return false, "loading" end
    if not DB().EnableOrders then return false, "disabled" end
    return true
end

-- ---------------------------------------------------------------------------
-- Words about a waypoint
-- ---------------------------------------------------------------------------
local function Coords(x, y)
    return G.FormatCoords(x, y, 1) or ""
end

local function Where(wp)
    if type(wp) ~= "table" or not wp.map then return "" end
    return (MapName(wp.map) or ("map " .. wp.map)) .. " " .. Coords(wp.x, wp.y)
end

local function Title(wp)
    if type(wp) ~= "table" then return "" end
    if wp.title and wp.title ~= "" then return wp.title end
    if wp.kind == "corpse" then return "Your corpse" end
    if wp.kind == "unit" then
        local name = UnitName and UnitName(wp.unit)
        return name or "Group member"
    end
    if wp.kind == "stop" and wp.routeIndex then return "Stop " .. wp.routeIndex end
    return Where(wp)
end

-- Where a waypoint is for the player now: the spawn the arrow follows of a
-- nearest-of-N waypoint (its chosen alternative; QuestLog hands every giver
-- spawn), else the record itself. The readouts, the copied /way line and a
-- share all say this place, never a primary spawn the arrow is not on.
local function ShownPos(wp)
    if type(wp) ~= "table" then return nil end
    local alts = wp.alternatives
    if type(alts) == "table" and store then
        local p = alts[store:ChosenAlternative(wp.uid)]
        if type(p) == "table" and type(p.map) == "number" then return p end
    end
    return wp
end

-- "Title (Zone 45.2, 66.8)", or just the place when it has no title; at the
-- spawn the arrow follows
local function Describe(wp)
    if type(wp) ~= "table" then return "" end
    if not wp.title or wp.title == "" then return Title(wp) end
    local pos = ShownPos(wp)
    if not pos.map then return wp.title end
    return wp.title .. " (" .. Where(pos) .. ")"
end

local function Copy(wp)
    local c = S.Copy(wp)
    if c then c.zone = MapName(c.map) end
    return c
end

local function UserSource(source)
    if source == nil then return true end
    if type(source) ~= "string" then return false end
    if D.USER_SOURCES[source] then return true end
    return source:sub(1, 6) == "share:"
end

-- ---------------------------------------------------------------------------
-- The API's insides (exported, pcall-wrapped, further down)
-- ---------------------------------------------------------------------------
local API = {}

-- Defaults applied to a copy of the caller's spec, never to the spec itself
local function PrepareSpec(spec)
    local s = {}
    for k, v in pairs(spec) do s[k] = v end
    if s.source == nil then s.source = "user" end
    local user = UserSource(s.source)
    if s.persistent == nil then s.persistent = user and true or false end
    if s.setArrow == nil then s.setArrow = true end
    if s.clearOnArrive == nil and DB().KeepMyMarks and (s.source == "user" or s.source == "place") then
        s.clearOnArrive = false
    end
    if s.kind == "unit" then
        if type(s.unit) ~= "string" or not D.FOLLOW_UNITS[s.unit] then return nil, "invalid unit" end
        return s
    end
    -- A point on a world or continent map becomes the zone under it: the
    -- continent maps hold two coordinate frames (critic C3), a zone one
    if type(s.map) == "number" and IsNum(s.x) and IsNum(s.y) then
        s.map, s.x, s.y = OnZone(s.map, s.x, s.y)
    end
    -- A position the client has no world data for can never be pointed at
    local e = Env()
    if e.worldPos and (type(s.map) == "number" or type(s.alternatives) == "table") then
        local any = type(s.map) == "number" and IsNum(s.x) and IsNum(s.y)
            and G.ToWorld(e, s.map, s.x, s.y) ~= nil
        if not any and type(s.alternatives) == "table" then
            for _, alt in ipairs(s.alternatives) do
                local m, x, y = alt.map or alt[1], alt.x or alt[2], alt.y or alt[3]
                if type(m) == "number" and IsNum(x) and IsNum(y) and G.ToWorld(e, m, x, y) then
                    any = true
                    break
                end
            end
        end
        if not any and type(s.map) == "number" and S.ValidPosition(s.map, s.x, s.y) then
            return nil, "no world position"
        end
    end
    return s
end

function API.Add(spec)
    local ok, why = Available()
    if not ok then return nil, why end
    if type(spec) ~= "table" then return nil, "no spec" end
    local s, err = PrepareSpec(spec)
    if not s then return nil, err end
    local wp, err2, status = store:Add(s)
    if not wp then return nil, err2 end
    -- The user re-adding a spot a TomTom-shim caller put there (a /way line,
    -- an accepted share, a place) makes it the user's: Questie removes its
    -- own by handle when it moves on, and must not take this one with it
    if status == "existing" and UserSource(s.source) and type(wp.source) == "string"
        and wp.source:sub(1, 7) == "TomTom:" then
        store:Claim(wp.uid, s.source)
    end
    if s.setArrow and store:Pinned() == wp and not s.silent then
        Cue("SET")
        if UserSource(s.source) then Announce("waypoint set: " .. Describe(wp)) end
    end
    Changed("add")
    return wp.uid, nil, status
end

function API.AddRoute(spec)
    local ok, why = Available()
    if not ok then return nil, why end
    if type(spec) ~= "table" or type(spec.stops) ~= "table" then return nil, "no stops" end
    local s = {}
    for k, v in pairs(spec) do s[k] = v end
    if s.source == nil then s.source = "user" end
    if s.persistent == nil then s.persistent = UserSource(s.source) and true or false end
    local stops = {}
    for _, st in ipairs(spec.stops) do
        if type(st) == "table" then
            local p = PrepareSpec(st)
            if p then
                p.source = st.source
                stops[#stops + 1] = p
            end
        end
    end
    s.stops = stops
    local route, err = store:AddRoute(s, BuildCtx(Clock(), true))
    if not route then return nil, err end
    if s.start ~= false then Cue("SET") end
    Changed("route")
    return route.id
end

function API.Remove(uid)
    if not store then return false end
    local done = store:Remove(UidOf(uid))
    if done then Changed("remove") end
    return done
end

function API.RemoveBy(source, key)
    if not store then return 0 end
    local n = store:RemoveBy(source, key)
    if n > 0 then Changed("remove") end
    return n
end

function API.Clear(filter)
    if not store then return 0 end
    local n = store:Clear(type(filter) == "table" and filter or nil)
    A.guide = nil
    Changed("clear")
    return n
end

function API.SetArrow(uid)
    local ok, why = Available()
    if not ok then return nil, why end
    local done, err = store:SetPinned(UidOf(uid))
    if not done then return nil, err end
    Cue("SET")
    Changed("arrow", true)
    return true
end

function API.ClearArrow()
    if not store then return false end
    store:ClearPinned(true)
    Changed("arrow", true)
    return true
end

function API.Get(uid)
    if not store then return nil end
    local wp = store:Get(UidOf(uid))
    return wp and Copy(wp) or nil
end

function API.List(filter)
    local out = {}
    if not store then return out end
    for i, wp in ipairs(store:List(type(filter) == "table" and filter or nil)) do out[i] = Copy(wp) end
    return out
end

function API.Distance(uid)
    if not store then return nil end
    local wp = store:Get(UidOf(uid))
    if not wp then return nil end
    return store:Distance(wp, BuildCtx(Clock()))
end

function API.Active()
    if not store or not DB().EnableOrders then return nil end
    local c = BuildCtx(Clock())
    local wp, why = store:ActiveTarget(c)
    if not wp then return nil end
    local copy = Copy(wp)
    copy.why = why
    copy.distance = store:Distance(wp, c)
    return copy
end

-- What the arrow is showing now, in the arrow's own words, so a readout
-- elsewhere (Commander_TopBar's Nav segment and its coordinates tooltip) can
-- never disagree with it: nil, or a copy
--   { uid, title, zone, map, x, y, mode, why, near, distance, distanceText,
--     eta, etaText, landName, hopName }
-- mode is the arrow's view mode (NAV | ARRIVED | OTHER | NOPOS | NOWORLD |
-- UNIT_LOST). nil while Orders is off or loading or has no target. The
-- driver composes the view at 10 Hz whether or not the arrow is on screen
-- (ShowArrow off does not starve it), so right after a change it is one
-- pass behind: a listener of CHANGED reads it a moment later, not inside
-- the event. eta follows ShowEta and is given only while navigating.
function API.Status()
    if not store or not DB().EnableOrders then return nil end
    local v = A.view
    local wp = v and v.wp
    if not wp or v.mode == nil or v.mode == "NONE" then return nil end
    -- the view is one pass behind a removal: never describe a waypoint
    -- that has already gone
    if not store:Get(wp.uid) then return nil end
    local pos = ShownPos(wp)
    local out = {
        uid = wp.uid, title = Title(wp), zone = MapName(pos.map), map = pos.map, x = pos.x, y = pos.y,
        mode = v.mode, why = v.why, near = v.near and true or nil,
        distance = v.distance, landName = v.landName, hopName = v.hop and v.hop.name or nil,
    }
    if v.distance then out.distanceText = Distance(v.distance) end
    if v.mode == "NAV" and DB().ShowEta and IsNum(A.eta.eta) then
        out.eta = A.eta.eta
        out.etaText = G.FormatEta(out.eta)
    end
    return out
end

function API.IsAvailable()
    return Available()
end

function API.Describe()
    return "Commander Orders arrow"
end

function API.Here(title)
    local ok, why = Available()
    if not ok then return nil, why end
    local map, x, y = PlayerMapPos()
    if not map then return nil, "no position" end
    title = Trim(title)
    return API.Add({ map = map, x = x, y = y, title = title ~= "" and title or nil, source = "user", setArrow = true })
end

function API.WayLine(uid)
    if not store then return nil end
    local wp = store:Get(UidOf(uid))
    local pos = ShownPos(wp)
    if not (pos and pos.map) then return nil end
    return G.WayLine(pos.map, pos.x, pos.y, wp.title)
end

function API.RegisterResolver(kind, fn)
    if type(fn) ~= "function" or type(resolvers[kind]) ~= "table" then return false end
    for _, existing in ipairs(resolvers[kind]) do
        if existing == fn then return true end
    end
    local list = resolvers[kind]
    list[#list + 1] = fn
    A.resolverGen = A.resolverGen + 1      -- hints are worked out again
    return true
end

-- The first answer a registered resolver gives (pcall'd each)
local function Resolve(kind, ...)
    for _, fn in ipairs(resolvers[kind] or {}) do
        local ok, a = pcall(fn, ...)
        if ok and a ~= nil then return a end
    end
    return nil
end

function API.Update(uid, fields)
    if not store then return nil, "loading" end
    if type(fields) ~= "table" then return nil, "no fields" end
    local wp, err = store:Update(UidOf(uid), fields)
    if not wp then return nil, err end
    Changed("update")
    return Copy(wp)
end

-- Routes ---------------------------------------------------------------------
local function RouteCopy(r)
    if not r then return nil end
    local stops = {}
    for i, uid in ipairs(r.stops) do stops[i] = uid end
    return { id = r.id, title = r.title, source = r.source, key = r.key, mode = r.mode,
             loop = r.loop, index = r.index, stops = stops, persistent = r.persistent }
end

function API.Routes()
    local out = {}
    if not store then return out end
    for i, r in ipairs(store:Routes()) do out[i] = RouteCopy(r) end
    return out
end

function API.GetRoute(id)
    if not store then return nil end
    return RouteCopy(store:GetRoute(id))
end

function API.ActiveRoute()
    if not store then return nil end
    return RouteCopy(store:ActiveRoute())
end

function API.RouteStart(id)
    if not store then return nil, "loading" end
    local ok, err = store:RouteStart(id, BuildCtx(Clock(), true))
    if ok then Changed("route", true) end
    return ok, err
end

function API.RouteNext(id)
    if not store then return nil, "loading" end
    local wp, err = store:RouteNext(id)
    if wp then Changed("route", true) end
    return wp and wp.uid or nil, err
end

function API.RoutePrev(id)
    if not store then return nil, "loading" end
    local wp, err = store:RoutePrev(id)
    if wp then Changed("route", true) end
    return wp and wp.uid or nil, err
end

function API.RouteReverse(id)
    if not store then return nil, "loading" end
    local ok, err = store:RouteReverse(id)
    if ok then Changed("route") end
    return ok, err
end

function API.RouteOptimize(id)
    if not store then return nil, "loading" end
    local c = BuildCtx(Clock(), true)
    local ok, err = store:RouteOptimize(c.player, c, id)
    if ok then Changed("route") end
    return ok, err
end

function API.RemoveRoute(id)
    if not store then return false end
    local done = store:RemoveRoute(id)
    if done then Changed("route") end
    return done
end

-- A "Guide me" hop is done with (arrived, marked arrived, removed by hand,
-- or the player crossed to another landmass without walking onto it): the
-- arrow goes back to what the player was being guided to. remove: the hop
-- itself goes too (it still exists).
local function GuideHandBack(remove)
    local guide = A.guide
    if not guide then return end
    A.guide = nil
    if not store then return end
    if remove and store:Get(guide.uid) then store:Remove(guide.uid, "guide") end
    if guide.target and store:Get(guide.target) then store:SetPinned(guide.target) end
    Changed("arrow", true)
end

-- The arrow's "Mark arrived": what arriving would have done, now
function API.MarkArrived(uid)
    if not store then return false end
    local wp
    if uid ~= nil then
        wp = store:Get(UidOf(uid))
    else
        wp = store:ActiveTarget(BuildCtx(Clock()))
    end
    if not wp then return false end
    local route = wp.routeId and store:GetRoute(wp.routeId)
    if route then
        local last = (not route.loop) and route.stops[#route.stops] == wp.uid
        if last then
            local title = route.title
            store:RemoveRoute(route.id, "arrived")
            Announce("route complete" .. (title and (": " .. title) or ""))
        elseif wp.clearOnArrive then
            store:Remove(wp.uid, "arrived")
        else
            store:RouteNext(route.id)
        end
    elseif wp.clearOnArrive then
        store:Remove(wp.uid, "arrived")
    else
        -- stamped reached as arrival stamps it, or the closest rule hands
        -- the same waypoint straight back (Keep My Own Marks, a shim
        -- waypoint with cleardistance 0)
        store:MarkReached(wp.uid)
    end
    if A.guide and A.guide.uid == wp.uid then GuideHandBack(false) end
    Changed("arrived", true)
    return true
end

-- ---------------------------------------------------------------------------
-- Landmass hints: "In Outland, via the Dark Portal in the Blasted Lands"
-- ---------------------------------------------------------------------------
local function LandmassName(key, pos)
    if key and D.LANDMASS_NAMES[key] then return D.LANDMASS_NAMES[key] end
    local info = pos and MapInfo(pos.map)
    if info and info.mapType == 4 then return MapName(pos.map) end
    local cont = pos and G.Continent(Env(), pos.map)
    return MapName(cont) or (pos and MapName(pos.map)) or "another land"
end

-- The first connection on the way from one landmass to another (breadth
-- first over Data.CONNECTIONS, this faction's and everyone's; the first
-- listed of equal length wins, which is why the spots with coordinates come
-- first in the table)
local function FirstHop(fromKey, toKey)
    if not fromKey or not toKey or fromKey == toKey then return nil end
    local faction = Faction()
    local via = { [fromKey] = false }
    local queue, head = { fromKey }, 1
    while queue[head] do
        local here = queue[head]
        head = head + 1
        for _, c in ipairs(D.CONNECTIONS) do
            if c.from == here and via[c.to] == nil and (not c.faction or c.faction == faction) then
                via[c.to] = c
                if c.to == toKey then
                    local step = c
                    while via[step.from] do step = via[step.from] end
                    return step
                end
                queue[#queue + 1] = c.to
            end
        end
    end
    return nil
end

-- The built-in entrance resolver of last resort: the client's own dungeon
-- entrance list for the zone around a dungeon map, matched by name. On 2.5.6
-- it may hold nothing (ASSUMPTIONS A8, probe P9); then it simply answers nil.
local function ClientEntrance(map)
    local info = MapInfo(map)
    if not (info and info.mapType == 4 and info.name) then return nil end
    local ej = C_EncounterJournal
    if not (ej and ej.GetDungeonEntrancesForMap) then return nil end
    local zone = info.parentMapID
    for _ = 1, 4 do
        local zinfo = MapInfo(zone)
        if not zinfo or zinfo.mapType ~= 4 then break end
        zone = zinfo.parentMapID
    end
    local ok, list = pcall(ej.GetDungeonEntrancesForMap, zone)
    if not ok or type(list) ~= "table" then return nil end
    for _, e in ipairs(list) do
        if type(e) == "table" and e.name == info.name then
            local x, y = VectorXY(e.position)
            if x then return { map = zone, x = x, y = y, title = info.name .. " entrance" } end
        end
    end
    return nil
end

local function Entrance(map)
    local e = Resolve("entrance", map)
    if type(e) ~= "table" then e = ClientEntrance(map) end
    if type(e) == "table" and type(e.map) == "number" and S.ValidPosition(e.map, e.x, e.y) then return e end
    return nil
end

-- The door of a dungeon or raid uiMap, found the way the arrow's own
-- dungeon hint finds it: the registered "entrance" resolvers first (QuestLog
-- registers one from Questie's dungeon table), then the client's list.
-- Commander_Guide asks this before its own cited raid table. A copy: a
-- resolver's table is never handed out (the runtime caches a world
-- position on the tables it is given).
function API.Entrance(map)
    local e = Entrance(map)
    if type(e) ~= "table" then return nil end
    return { map = e.map, x = e.x, y = e.y, title = e.title }
end

-- What to tell a player whose target is not on their landmass:
-- landName, hop ({ name, map, x, y, note } or nil)
local function Hint(playerKey, pos, targetKey)
    local landName = LandmassName(targetKey, pos)
    local info = MapInfo(pos.map)
    if info and info.mapType == 4 then
        local e = Entrance(pos.map)
        if e then
            local ei = PosWorld(e)
            local eKey = ei and Landmass(e.map, ei)
            if eKey == playerKey then
                return landName, { name = "the entrance of " .. (MapName(pos.map) or "the instance"),
                                   map = e.map, x = e.x, y = e.y, entrance = true }
            end
            local hop = FirstHop(playerKey, eKey)
            if hop then return landName, hop end
            return landName, nil
        end
    end
    return landName, FirstHop(playerKey, targetKey)
end

-- ---------------------------------------------------------------------------
-- The arrow
-- ---------------------------------------------------------------------------
local Arrow = {}

local function Unlocked()
    return DB().ArrowLocked == false
end

local function ModifierDown()
    local m = DB().ArrowModifier
    if m == "CTRL" then return IsControlKeyDown and IsControlKeyDown() and true or false end
    if m == "ALT" then return IsAltKeyDown and IsAltKeyDown() and true or false end
    return IsShiftKeyDown and IsShiftKeyDown() and true or false
end

local function SetText(region, key, text)
    text = text or ""
    if A.text[key] ~= text then
        A.text[key] = text
        region:SetText(text)
    end
end

local function SetColour(tex, key, r, g, b)
    local c = A.colour[key]
    if not c then
        c = {}
        A.colour[key] = c
    end
    if c[1] and abs(c[1] - r) < 0.004 and abs(c[2] - g) < 0.004 and abs(c[3] - b) < 0.004 then return end
    c[1], c[2], c[3] = r, g, b
    tex:SetVertexColor(r, g, b)
end

-- Red behind, yellow square to the side, green ahead, the "locked on" tint
-- inside a few degrees
local function AlignmentColour(rel)
    if abs(rel) <= DEAD_AHEAD then
        return PAL.AHEAD[1], PAL.AHEAD[2], PAL.AHEAD[3]
    end
    local a = G.Alignment(rel) or 0
    local lo, hi, t
    if a >= 0.5 then
        lo, hi, t = PAL.MID, PAL.GOOD, (a - 0.5) * 2
    else
        lo, hi, t = PAL.BAD, PAL.MID, a * 2
    end
    return lo[1] + (hi[1] - lo[1]) * t, lo[2] + (hi[2] - lo[2]) * t, lo[3] + (hi[3] - lo[3]) * t
end

function Arrow.Build()
    if A.built or not CreateFrame then return end
    local root = CreateFrame("Frame", "CommanderOrdersArrow", UIParent)
    root:SetSize(AR.WIDTH, AR.HEIGHT)
    root:SetFrameStrata("MEDIUM")
    root:SetPoint(AR.DEFAULT_POINT.point, UIParent, AR.DEFAULT_POINT.point, AR.DEFAULT_POINT.x, AR.DEFAULT_POINT.y)
    root:EnableMouse(false)
    root:Hide()
    A.root = root

    local title = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline")
    title:SetPoint("TOP", root, "TOP", 0, 0)
    title:SetWidth(AR.WIDTH)
    title:SetJustifyH("CENTER")
    if title.SetWordWrap then title:SetWordWrap(false) end
    A.title = title

    local art = CreateFrame("Frame", nil, root)
    art:SetSize(AR.QUAD, AR.QUAD)
    art:SetPoint("TOP", root, "TOP", 0, -14)
    art:EnableMouse(false)
    A.art = art

    local shadow = art:CreateTexture(nil, "ARTWORK", nil, 0)
    shadow:SetTexture(TEX.SHADOW)
    shadow:SetSize(AR.QUAD, AR.QUAD)
    shadow:SetPoint("CENTER", art, "CENTER", AR.SHADOW_OFFSET_X, AR.SHADOW_OFFSET_Y)
    shadow:SetVertexColor(PAL.SHADOW[1], PAL.SHADOW[2], PAL.SHADOW[3])
    shadow:SetAlpha(AR.SHADOW_ALPHA)
    A.shadow = shadow

    local ring = art:CreateTexture(nil, "ARTWORK", nil, 1)
    ring:SetTexture(TEX.RING)
    ring:SetSize(AR.QUAD, AR.QUAD)
    ring:SetPoint("CENTER", art, "CENTER", 0, 0)
    ring:Hide()
    A.ring = ring

    local arrow = art:CreateTexture(nil, "ARTWORK", nil, 2)
    arrow:SetTexture(TEX.ARROW)
    arrow:SetSize(AR.QUAD, AR.QUAD)
    arrow:SetPoint("CENTER", art, "CENTER", 0, 0)
    A.arrow = arrow

    local arrived = art:CreateTexture(nil, "ARTWORK", nil, 3)
    arrived:SetTexture(TEX.ARRIVED)
    arrived:SetSize(AR.QUAD, AR.QUAD)
    arrived:SetPoint("CENTER", art, "CENTER", 0, 0)
    arrived:SetVertexColor(PAL.ARRIVED[1], PAL.ARRIVED[2], PAL.ARRIVED[3])
    arrived:Hide()
    A.arrived = arrived

    local dist = OutlinedText(root, "GameFontNormalLargeOutline", "GameFontNormalLarge")
    dist:SetPoint("TOP", art, "BOTTOM", 0, 4)
    dist:SetJustifyH("CENTER")
    A.dist = dist

    local eta = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
    eta:SetPoint("TOP", dist, "BOTTOM", 0, -2)
    eta:SetJustifyH("CENTER")
    eta:SetTextColor(0.86, 0.88, 0.92)
    A.etaText = eta

    -- The root's own width, two lines at most: a 300 px line ran past every
    -- chrome panel (drawn around the 190 px root) and past the screen clamp
    -- (which holds the root only), "via the Thalassian Pass, from the
    -- Eastern Plaguelands" being the longest (review: render). Two lines of
    -- the small font end inside AR.HEIGHT.
    local status = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
    status:SetPoint("TOP", eta, "BOTTOM", 0, -2)
    status:SetWidth(AR.WIDTH)
    status:SetJustifyH("CENTER")
    if status.SetWordWrap then status:SetWordWrap(true) end
    if status.SetMaxLines then status:SetMaxLines(2) end
    status:SetTextColor(PAL.STATUS[1], PAL.STATUS[2], PAL.STATUS[3])
    A.status = status

    -- The only clickable surface, and only while the modifier is held
    local hit = CreateFrame("Button", nil, root)
    hit:SetAllPoints(root)
    hit:SetFrameLevel((root:GetFrameLevel() or 1) + 5)
    hit:EnableMouse(false)
    if hit.RegisterForClicks then hit:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    hit:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            Arrow.Menu()
        else
            local wp = A.view.wp
            O.OpenManager(wp and wp.uid)
        end
    end)
    hit:SetScript("OnEnter", function(self) Arrow.Tooltip(self) end)
    hit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    A.hit = hit

    A.built = true
    title:SetTextColor(Accent())
end

function Arrow.UpdateMouse()
    if not A.built then return end
    local want = A.root:IsShown() and not Unlocked() and ModifierDown()
    A.root:EnableMouse(false)
    A.hit:EnableMouse(want and true or false)
    if not want and A.hit.IsMouseOver and GameTooltip and GameTooltip.GetOwner
        and GameTooltip:GetOwner() == A.hit then
        GameTooltip:Hide()
    end
end

-- First apply out of combat only (see the header)
function Arrow.ApplyChrome()
    if not A.built then return end
    local UI = Commander and Commander.UI
    if not (UI and UI.ApplyHudChrome) then return end
    if not A.chromeReady and InCombatLockdown and InCombatLockdown() then
        A.chromePending = true
        return
    end
    UI.ApplyHudChrome(A.root, DB(), "Arrow", { defaultPoint = AR.DEFAULT_POINT, title = "Orders" })
    A.chromeReady, A.chromePending = true, false
    A.shownState = nil                  -- the next Refresh asserts it once (Reset Position reopens)
    -- The chrome locks on a right-click of its drag overlay (and on the
    -- Window style's lock button) by itself, without the settings event:
    -- follow it, or the drag placeholder would stay on screen
    local overlay = A.root._hudDragOverlay
    if overlay and not A.overlayHooked and overlay.HookScript then
        A.overlayHooked = true
        overlay:HookScript("OnMouseUp", function() Arrow.Refresh(); Wake() end)
    end
    local win = A.root._hudWindow
    if win and win.lockButton and not A.lockHooked and win.lockButton.HookScript then
        A.lockHooked = true
        win.lockButton:HookScript("OnClick", function() Arrow.Refresh(); Wake() end)
    end
    -- Click-through when locked: the chrome leaves a locked frame
    -- mouse-enabled for its triple right-click; this arrow never is
    A.root:EnableMouse(false)
    A.title:SetTextColor(Accent())
    Arrow.UpdateMouse()
end

-- Whether the arrow is on screen at all
local function ShouldShow()
    local db = DB()
    if not A.built then return false end
    if Unlocked() then return true end
    if not db.EnableOrders or not db.ShowArrow then return false end
    if db.HideInCombat and (A.inCombat or (InCombatLockdown and InCombatLockdown())) then return false end
    if db.HideWithMap and A.mapShown then return false end
    if db.HideInInstances and IsInInstance then
        local inside = IsInInstance()
        if inside then return false end
    end
    local mode = A.view.mode
    if mode == "NONE" and db.HideNoTarget then return false end
    return true
end

function Arrow.Refresh()
    if not A.built then return end
    local show = ShouldShow()
    -- Asserted when the wanted state changes, and whenever the frame shows
    -- while it should not (the chrome shows a frame it unlocks). Never
    -- re-shown pass after pass once something else hid it: the Window
    -- style's close button hides it for the session from an OnShow hook,
    -- which re-showing would run ten times a second (review: runtime).
    -- ApplyChrome forgets the state, so Reset Position, which reopens a
    -- closed window, is obeyed on the next Refresh.
    if show ~= A.shownState or (not show and A.root:IsShown()) then
        A.shownState = show
        A.root:SetShown(show)
    end
    Arrow.Paint()
    Arrow.UpdateMouse()
end

-- Regions per mode; text was decided by Compose
function Arrow.Paint()
    if not A.built then return end
    local v = A.view
    local mode = Unlocked() and "UNLOCKED" or v.mode
    local navigating = mode == "NAV" or mode == "UNLOCKED"
    A.arrow:SetShown(navigating and not v.noHeading)
    A.shadow:SetShown(navigating and not v.noHeading)
    A.arrived:SetShown(mode == "ARRIVED")
    A.ring:SetShown(mode == "NAV" and v.near and true or false)
    if mode == "UNLOCKED" then
        A.arrow:SetRotation(0)
        A.shadow:SetRotation(0)
        SetColour(A.arrow, "arrow", PAL.IDLE[1], PAL.IDLE[2], PAL.IDLE[3])
        SetText(A.title, "title", "Commander Orders")
        SetText(A.dist, "dist", "125 yd")
        SetText(A.etaText, "eta", "1m 05s")
        SetText(A.status, "status", "Drag to move; right-click to lock")
    end
end

-- Decide what to show (10 Hz). c is this pass's ctx.
function Arrow.Compose(c, dt)
    local v = A.view
    local db = DB()
    local wp, why = nil, nil
    if store and db.EnableOrders then wp, why = store:ActiveTarget(c) end
    if v.wp ~= wp then
        v.wp = wp
        A.angle.value, A.angle.velocity = nil, 0
    end
    v.why = why
    v.near, v.hop, v.landName, v.distance, v.noHeading = false, nil, nil, nil, false
    local titleText, distText, etaText, statusText = "", "", "", ""
    if not wp then
        v.mode = "NONE"
        titleText, distText = "Commander Orders", "No waypoint"
    else
        titleText = Cut(Title(wp), AR.TITLE_MAX)
        local au, astate = store:ArrivalState()
        local state = au == wp.uid and astate or "NAVIGATING"
        local pn, pw, pinst = playerNow.n, playerNow.w, playerNow.inst
        local pos, ti, tn, tw
        if wp.kind == "unit" then
            -- UnitPosition and the unit's map id: nothing allocated. The
            -- map position (a Vector2D a call) only when UnitPosition fails
            tn, tw, ti = UnitWorld(wp.unit)
            local umap = tn and UnitMap(wp.unit)
            if umap then
                A.unitPos.map = umap
                pos = A.unitPos
            else
                pos = store:Position(wp, c)
                if not tn and pos then ti, tn, tw = PosWorld(pos) end
            end
        else
            pos = store:Position(wp, c)
            if pos then ti, tn, tw = PosWorld(pos) end
        end
        v.ti, v.tn, v.tw = ti, tn, tw
        if wp.kind == "unit" and not tn then
            v.mode = "UNIT_LOST"
            distText, statusText = "Not visible", "Party member not visible"
        elseif not pn or not c.player then
            v.mode = "NOPOS"
            distText, statusText = "No position here", "No position inside instances"
        elseif not ti then
            v.mode = "NOWORLD"
            distText, statusText = "No map position", "This map has no world coordinates"
        else
            local pKey = Landmass(c.player.map, pinst)
            local tKey = pos and Landmass(pos.map, ti)
            if ti ~= pinst or not pKey or pKey ~= tKey then
                v.mode = "OTHER"
                -- worked out once per pair of landmasses (and target map),
                -- not ten times a second
                local key = format("%s|%s|%s|%s|%d", tostring(pKey), tostring(tKey),
                    tostring(pos and pos.map), tostring(Faction()), A.resolverGen)
                if A.hintKey ~= key then
                    A.hintKey = key
                    A.hintLand, A.hintHop = Hint(pKey, pos or wp, tKey)
                end
                local landName, hop = A.hintLand, A.hintHop
                v.landName, v.hop = landName, hop
                distText = "In " .. landName
                if hop then
                    statusText = "via " .. hop.name
                else
                    statusText = "No known way there"
                end
            else
                local d = G.Distance(pn, pw, tn, tw)
                v.distance = d
                if state == "ARRIVED" then
                    v.mode = "ARRIVED"
                    distText = "Arrived"
                else
                    v.mode = "NAV"
                    v.near = state == "NEAR"
                    distText = Distance(d) or ""
                    if Facing() == nil then
                        v.noHeading = true
                        statusText = "No heading"
                    elseif c.onTaxi then
                        statusText = "In flight"
                    elseif A.rel and abs(A.rel) > TURN_AROUND then
                        statusText = "Turn around"
                    end
                    -- the ETA: own ground speed, never on a taxi
                    local eta
                    if db.ShowEta and not c.onTaxi then
                        A.eta.target = wp.uid
                        local speed = GetUnitSpeed and GetUnitSpeed("player")
                        eta = G.EtaFilter(A.eta, d, dt or AR.TEXT_INTERVAL, speed)
                    else
                        G.EtaReset(A.eta)
                    end
                    etaText = G.FormatEta(eta) or ""
                end
                if wp.routeId and statusText == "" then
                    local route = store:GetRoute(wp.routeId)
                    if route and wp.routeIndex then
                        statusText = format("Stop %d of %d", wp.routeIndex, #route.stops)
                    end
                end
            end
        end
    end
    if A.built and not Unlocked() then
        SetText(A.title, "title", titleText)
        SetText(A.dist, "dist", distText)
        SetText(A.etaText, "eta", etaText)
        SetText(A.status, "status", statusText)
        if v.mode == "OTHER" or v.mode == "NOWORLD" then
            A.status:SetTextColor(PAL.HINT[1], PAL.HINT[2], PAL.HINT[3])
        else
            A.status:SetTextColor(PAL.STATUS[1], PAL.STATUS[2], PAL.STATUS[3])
        end
    end
    Arrow.Refresh()
end

-- Every frame while awake: turn the arrow, pulse the ring
function Arrow.Frame(elapsed)
    if not (A.built and A.root:IsShown()) then return end
    local v = A.view
    if Unlocked() or v.mode ~= "NAV" then return end
    local n, w, inst = UnitWorld("player")
    local tn, tw = v.tn, v.tw
    if v.wp and v.wp.kind == "unit" then
        local un, uw, ui = UnitWorld(v.wp.unit)
        if un and ui == inst then tn, tw = un, uw end
    end
    local facing = Facing()
    if not (n and inst == v.ti and tn) then return end
    if facing == nil then
        if not v.noHeading then
            v.noHeading = true
            Arrow.Paint()
        end
        return
    end
    local rel = G.Relative(G.Bearing(n, w, tn, tw), facing)
    if not rel then return end
    A.rel = rel
    local shown = rel
    if DB().SmoothArrow then shown = G.AngleFilter(A.angle, rel, elapsed, AR.SMOOTH_TAU) or rel end
    A.arrow:SetRotation(shown)
    A.shadow:SetRotation(shown)
    SetColour(A.arrow, "arrow", AlignmentColour(shown))
    if v.near then
        A.pulse = (A.pulse + elapsed) % AR.PULSE_PERIOD
        local s = 0.5 + 0.5 * sin(A.pulse / AR.PULSE_PERIOD * 2 * PI)
        A.ring:SetAlpha(0.25 + 0.45 * s)
        local size = AR.QUAD * (1.0 + 0.10 * s)
        A.ring:SetSize(size, size)
        SetColour(A.ring, "ring", AlignmentColour(shown))
    end
end

function Arrow.Tooltip(owner)
    if not GameTooltip then return end
    local v = A.view
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    GameTooltip:SetText(v.wp and Title(v.wp) or "Commander Orders", 1, 1, 1)
    if v.wp then
        local pos = ShownPos(v.wp)
        if pos.map then GameTooltip:AddLine(Where(pos), 0.8, 0.8, 0.8) end
        if v.distance then GameTooltip:AddLine(Distance(v.distance), 1, 0.82, 0.3) end
        if v.mode == "OTHER" and v.hop and v.hop.note then
            GameTooltip:AddLine("Or " .. v.hop.note:gsub("^or ", ""), 0.8, 0.84, 0.9, true)
        end
    end
    GameTooltip:AddLine("Click: open the manager", 0.6, 0.8, 1)
    GameTooltip:AddLine("Right-click: menu", 0.6, 0.8, 1)
    GameTooltip:Show()
end

-- ---------------------------------------------------------------------------
-- Menus and popups (shared with the pins and the manager through R)
-- ---------------------------------------------------------------------------
local menuFrame

-- entries: { text, func, isTitle, disabled }
local function ShowMenu(entries, anchor)
    if not (CreateFrame and UIDropDownMenu_Initialize and ToggleDropDownMenu) then return false end
    if not menuFrame then
        menuFrame = CreateFrame("Frame", "CommanderOrdersMenu", UIParent, "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(menuFrame, function()
        for _, entry in ipairs(entries) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = entry.text
            info.notCheckable = true
            info.isTitle = entry.isTitle
            info.disabled = entry.disabled
            info.func = entry.func
            if entry.isTitle then info.notClickable = true end
            UIDropDownMenu_AddButton(info)
        end
    end, "MENU")
    ToggleDropDownMenu(1, nil, menuFrame, anchor or "cursor", 0, 0)
    return true
end

-- StaticPopup_Show parents every dialog to UIParent at DIALOG strata
-- (StaticPopup_SetUpPosition), and the maximized world map (TBC's default)
-- is FULLSCREEN with an opaque BlackoutFrame over all of UIParent: a dialog
-- opened from a map pin, or a share arriving while the map is open, was
-- hidden behind it, the copy box holding the keyboard unseen. Raised the
-- way Blizzard raises its own dialog over the map (GameDialogDefs.lua
-- 3218-3221); the next StaticPopup_Show puts the frame back to DIALOG.
local function RaisePopup(dialog)
    if type(dialog) ~= "table" then return end
    if dialog.SetFrameStrata then dialog:SetFrameStrata("FULLSCREEN_DIALOG") end
    if dialog.SetFrameLevel then dialog:SetFrameLevel(3000) end
end

local function CopyLine(text)
    if type(text) ~= "string" or text == "" then return false end
    if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs.COMMANDER_ORDERS_COPY then
        A.copyText = text
        StaticPopup_Show("COMMANDER_ORDERS_COPY")
        return true
    end
    Say(text)
    return true
end

local function InGroup()
    return IsInGroup and IsInGroup() and true or false
end

-- A menu's "Share with group": says why when it cannot
local function ShareFromMenu(uid)
    local ok, err = O.Share(uid)
    if not ok then Say("could not share: " .. tostring(err)) end
end

-- The actions every waypoint offers, wherever it is clicked
local function WaypointMenu(uid)
    local wp = store and store:Get(UidOf(uid))
    if not wp then return {} end
    local id = wp.uid
    local entries = { { text = Cut(Title(wp), 40), isTitle = true } }
    entries[#entries + 1] = { text = "Set as arrow", func = function() O.SetArrow(id) end }
    if InGroup() then
        entries[#entries + 1] = { text = "Share with group", func = function() ShareFromMenu(id) end }
    end
    if wp.map then
        entries[#entries + 1] = { text = "Copy /way line", func = function() CopyLine(O.WayLine(id)) end }
    end
    entries[#entries + 1] = { text = "Remove", func = function() O.Remove(id) end }
    return entries
end

-- Pin a waypoint at the next leg (the OTHER LANDMASS "Guide me")
function API.Guide()
    local ok, why = Available()
    if not ok then return nil, why end
    local v = A.view
    local hop = v.mode == "OTHER" and v.hop
    if not (hop and hop.map) then return nil, "no guide" end
    local target = v.wp and v.wp.uid
    local uid, err = API.Add({
        map = hop.map, x = hop.x, y = hop.y, title = Cut("To " .. (v.landName or "there"), 60),
        source = "guide", key = "hop", setArrow = true, persistent = false, clearOnArrive = true,
        note = "via " .. hop.name, icon = "ROUTE",
    })
    if uid then A.guide = { uid = uid, target = target } end
    return uid, err
end

function Arrow.Menu()
    local v = A.view
    local wp = v.wp
    local entries = { { text = wp and Cut(Title(wp), 40) or "Commander Orders", isTitle = true } }
    local route = wp and wp.routeId and store:GetRoute(wp.routeId)
    if route then
        entries[#entries + 1] = { text = "Next stop", func = function() O.RouteNext(route.id) end }
        entries[#entries + 1] = { text = "Previous stop", func = function() O.RoutePrev(route.id) end }
    end
    if v.mode == "OTHER" and v.hop and v.hop.map then
        entries[#entries + 1] = { text = Cut("Guide me: " .. v.hop.name, 60), func = function() O.Guide() end }
    end
    if wp then
        local id = wp.uid
        entries[#entries + 1] = { text = "Mark arrived", func = function() O.MarkArrived(id) end }
        entries[#entries + 1] = { text = "Clear arrow", func = function() O.ClearArrow() end }
        entries[#entries + 1] = { text = "Remove waypoint", func = function() O.Remove(id) end }
        if InGroup() then
            entries[#entries + 1] = { text = "Share with group", func = function() ShareFromMenu(id) end }
        end
        if wp.map then
            entries[#entries + 1] = { text = "Copy /way line", func = function() CopyLine(O.WayLine(id)) end }
        end
    end
    entries[#entries + 1] = { text = "Open manager", func = function() O.OpenManager(wp and wp.uid) end }
    entries[#entries + 1] = { text = Unlocked() and "Lock arrow" or "Unlock arrow",
        func = function() O.Command(Unlocked() and "lock" or "unlock") end }
    ShowMenu(entries, A.hit)
end

-- ---------------------------------------------------------------------------
-- The driver: 10 Hz arrival and text, every frame the arrow; asleep when
-- there is nothing to do
-- ---------------------------------------------------------------------------
local driver

local function HandleEvents(events, now)
    for _, e in ipairs(events) do
        local t = e.type
        if t == "TARGET" then
            -- only a real change of hands counts. The Store is silent on
            -- an idle tick; this check is the defence should a TARGET ever
            -- name its own previous uid, which would fire CHANGED every pass
            if e.uid ~= e.previous then
                G.EtaReset(A.eta)
                A.angle.value, A.angle.velocity = nil, 0
                A.rel = nil
                CallPins("OnTarget", e.uid)
                Changed("target", true)
            end
        elseif t == "ARRIVED" then
            Cue("ARRIVE")
        elseif t == "DONE" then
            if A.guide and A.guide.uid == e.uid then GuideHandBack(false) end
            if A.corpse and A.corpse.uid == e.uid then A.corpse.reached = true end
            Changed("arrived", true)
        elseif t == "ADVANCE" then
            Changed("advance", true)
        elseif t == "ROUTE_COMPLETE" then
            Announce("route complete" .. (e.title and (": " .. e.title) or ""))
            Changed("route", true)
        elseif t == "CALLBACK_ERROR" then
            Report(e.err)
        end
    end
end

-- Yards to a followed group member from UnitPosition, which allocates
-- nothing (the map-position route costs a Vector2D and two tables a call,
-- ten times a second: review runtime, the churn 0bfa0d12 removed). nil when
-- the unit cannot be placed or is on another landmass.
local function UnitDistance(unit, c)
    local pn, pw, pinst = playerNow.n, playerNow.w, playerNow.inst
    if not (pn and c.player) then return nil end
    local un, uw, ui = UnitWorld(unit)
    if not un or ui ~= pinst then return nil end
    local umap = UnitMap(unit)
    if not umap or Landmass(umap, ui) ~= Landmass(c.player.map, pinst) then return nil end
    return G.Distance(pn, pw, un, uw)
end

-- A "Guide me" hop holds the arrow only while it is the pin on the player's
-- own landmass. Removed by hand: the target is pinned again. Pinned no more
-- (the player chose something else): the guide lets go. The player crossed
-- to another landmass without walking onto it (a portal, a hearthstone, the
-- other boat): the hop goes and the target is pinned again, so the arrow
-- never sends anyone back across the crossing just made.
local function GuideCheck(c)
    local guide = A.guide
    if not guide then return end
    local hop = store:Get(guide.uid)
    if not hop then
        if store:Pinned() == nil and not store:Suppressed() then
            GuideHandBack(false)
        else
            A.guide = nil
        end
        return
    end
    if store:Pinned() ~= hop then
        A.guide = nil
        return
    end
    local pinst = playerNow.inst
    if not (c.player and pinst ~= nil) then return end
    local hi = PosWorld(hop)
    local hKey = hi and Landmass(hop.map, hi)
    local pKey = Landmass(c.player.map, pinst)
    if hKey and pKey and hKey ~= pKey then GuideHandBack(true) end
end

local function Pass(dt)
    if not store then return end
    local now = Clock()
    local c = BuildCtx(now)
    if DB().EnableOrders then
        if A.guide then GuideCheck(c) end
        local wp = store:ActiveTarget(c)
        local d
        if wp and c.player then
            if wp.kind == "unit" then
                d = UnitDistance(wp.unit, c)
            else
                local pos = store:Position(wp, c)
                d = pos and ctx.distance(c.player, pos)
            end
        end
        local events = store:Tick(c, d, now)
        HandleEvents(events, now)
    end
    Arrow.Compose(c, dt)
    if store.version ~= seenVersion then Changed("tick") end
    if not (DB().EnableOrders and store:NeedsTick(c)) and not Unlocked() then
        driver:Hide()
    end
end

local function OnFrame(_, elapsed)
    A.textAcc = A.textAcc + elapsed
    if A.textAcc >= AR.TEXT_INTERVAL then
        local dt = A.textAcc
        A.textAcc = 0
        local ok, err = pcall(Pass, dt)
        if not ok then Report(err) end
    end
    if driver:IsShown() then Arrow.Frame(elapsed) end
end

Wake = function()
    if not (driver and store) then return end
    if not driver:IsShown() then
        A.textAcc = AR.TEXT_INTERVAL     -- run a pass on the very next frame
        driver:Show()
    end
end

-- ---------------------------------------------------------------------------
-- /way and friends
-- ---------------------------------------------------------------------------
local Way = {}

function Way.Resolver()
    if not Way.index then Way.index = G.ZoneIndex(Env(), D.ZONE_ALIASES) end
    local index = Way.index
    return function(text)
        local map, candidates = G.MatchZone(index, text)
        if map then return map end
        if type(candidates) == "table" and #candidates > 0 then return nil, candidates end
        local other = Resolve("zone", text)
        if type(other) == "number" then return other end
        return nil, {}
    end
end

local function ListLines(list, header)
    if #list == 0 then
        Say(header and (header .. ": none") or "no waypoints")
        return
    end
    Say(header .. ":")
    for _, wp in ipairs(list) do
        print(format("  %s  %s  [%s]", wp.uid, Describe(wp), tostring(wp.source)))
    end
end

function Way.List(localOnly)
    if not store then return end
    if localOnly then
        local map = PlayerMap()
        ListLines(map and store:List({ map = map }) or {}, "waypoints on " .. (MapName(map) or "this map"))
    else
        ListLines(store:List(), "waypoints")
    end
end

function Way.ArrowReport()
    local v = A.view
    local parts = { "arrow " .. (v.mode or "?") }
    if v.wp then parts[#parts + 1] = Describe(v.wp) end
    if v.why then parts[#parts + 1] = "(" .. strlower(v.why) .. ")" end
    if v.distance then parts[#parts + 1] = Distance(v.distance) end
    Say(table.concat(parts, " "))
end

local function Plural(n, one, many)
    return n .. " " .. (n == 1 and one or many)
end

function Way.Reset(cmd)
    if not store then return end
    if cmd.scope == "ALL" then
        if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs.COMMANDER_ORDERS_CLEAR_ALL then
            StaticPopup_Show("COMMANDER_ORDERS_CLEAR_ALL")
        else
            API.Clear()
            Say("every waypoint removed")
        end
        return
    end
    local here = PlayerMap()
    local doomed = {}
    for _, wp in ipairs(store:List()) do
        local m = wp.map
        local hit
        if cmd.scope == "AWAY" then
            hit = m ~= here
        elseif cmd.scope == "ZONE" then
            hit = m == cmd.map
        elseif cmd.scope == "NOT_ZONE" then
            hit = m ~= cmd.map
        end
        if hit and wp.kind ~= "corpse" then doomed[#doomed + 1] = wp.uid end
    end
    for _, uid in ipairs(doomed) do store:Remove(uid, "reset") end
    Changed("remove")
    Say(Plural(#doomed, "waypoint", "waypoints") .. " removed")
end

-- One /way line, from the slash or the paste window
function Way.Run(msg)
    local ok, why = Available()
    if not ok then
        Say(why == "disabled" and "Commander Orders is turned off (/corder to turn it on)" or "still loading")
        return
    end
    local cmd = G.ParseWay(msg or "", Way.Resolver())
    local kind = cmd.kind
    if kind == "ADD" then
        local map = cmd.map or PlayerMap()
        if not map then
            Say("there is no map here to put a waypoint on")
            return
        end
        if cmd.byId and not MapInfo(map) then
            Say("there is no map #" .. map)
            return
        end
        local uid, err = API.Add({ map = map, x = cmd.x, y = cmd.y, title = cmd.title, source = "user", setArrow = true })
        if not uid then
            if err == "no world position" then
                Say("that map has no world coordinates; use a zone map")
            else
                Say("could not set that waypoint (" .. tostring(err) .. ")")
            end
        end
    elseif kind == "LIST" then
        Way.List(false)
    elseif kind == "LOCAL" then
        Way.List(true)
    elseif kind == "ARROW" then
        Way.ArrowReport()
    elseif kind == "RESET" then
        Way.Reset(cmd)
    elseif kind == "USAGE" then
        for _, line in ipairs(G.WayUsage(cmd.topic)) do print(line) end
    else
        Say(cmd.message or "could not read that /way line")
        for i, c in ipairs(cmd.candidates or {}) do
            if i > 8 then break end
            print("  " .. tostring(c.line))
        end
    end
end

function Way.Closest()
    if not store then return end
    local wp = store:Closest(BuildCtx(Clock(), true))
    if not wp then
        Say("no waypoint on this landmass")
        return
    end
    store:SetPinned(wp.uid)
    Cue("SET")
    Changed("arrow", true)
    Announce("arrow set to the closest: " .. Describe(wp))
end

local function TomTomLoaded()
    local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if type(fn) ~= "function" then return false end
    local ok, loaded = pcall(fn, "TomTom")
    return ok and loaded and true or false
end

-- /way, /tway, /wayb, /wayback, /cway, /closestway: only when no TomTom is
-- loaded, under our own keys (never TOMTOM_WAY). /corder way always works.
function Way.Register()
    if Way.registered or not DB().ClaimWaySlash or TomTomLoaded() then return end
    if not SlashCmdList then return end
    Way.registered = true
    SLASH_COMMANDERORDERS_WAY1 = "/way"
    SLASH_COMMANDERORDERS_WAY2 = "/tway"
    SlashCmdList.COMMANDERORDERS_WAY = function(msg) O.Command("way", msg) end
    SLASH_COMMANDERORDERS_WAYBACK1 = "/wayb"
    SLASH_COMMANDERORDERS_WAYBACK2 = "/wayback"
    SlashCmdList.COMMANDERORDERS_WAYBACK = function(msg) O.Command("here", msg) end
    SLASH_COMMANDERORDERS_CWAY1 = "/cway"
    SLASH_COMMANDERORDERS_CWAY2 = "/closestway"
    SlashCmdList.COMMANDERORDERS_CWAY = function() O.Command("closest") end
end

-- ---------------------------------------------------------------------------
-- The TomTom compatibility shim (thirdparty.md 5; critic 3.6)
-- ---------------------------------------------------------------------------
-- Tier 1 is what Questie and WhatsTraining call: AddWaypoint returns
-- TomTom's own plain-data uid {m, x, y, title=, from=} with the numbers
-- exactly as passed (Questie compares uid[2] ~= x) and only scalar options
-- copied in (Questie keeps the uid in its saved variables; a function in it
-- would be dropped by the writer and a frame would drag a whole widget in).
-- RemoveWaypoint is silent for anything it does not know: Questie hands back
-- a stale copy after every /reload, and may still hold a real TomTom uid from
-- before TomTom was removed. It finds by identity, then by a tolerant key,
-- then by place and title among TomTom-sourced waypoints, because the saved
-- copy can come back one bit off (16 printed digits).
-- Tier 3 is deliberately absent: no db/profile tables, no catch-all
-- metatable, no arrow hijack, no ClearAllWaypoints. IsAddOnLoaded("TomTom")
-- is never faked, so Questie's options still say TomTom is not installed.
local Shim = { handle = {}, byKey = {}, byOrders = {}, installed = false }
local TT = { isCommanderShim = true, version = "Commander_Orders" }
O.TomTomShim = TT

local function TolKey(m, x, y, title)
    return format("%d:%.6f:%.6f:%s", m, x, y, tostring(title))
end

local function ShimLive(u)
    local h = Shim.handle[u]
    if h and store and store:Get(h) then return h end
    return nil
end

local function ShimForget(wp)
    local u = Shim.byOrders[wp.uid]
    if not u then return end
    Shim.byOrders[wp.uid] = nil
    Shim.handle[u] = nil
    for k, v in pairs(Shim.byKey) do
        if v == u then Shim.byKey[k] = nil end
    end
end

-- A TomTom-sourced record at this place and title (tolerant), for uids that
-- outlived the session that made them
local function ShimRecord(m, x, y, title)
    if not store then return nil end
    title = S.NormTitle(title)
    for _, wp in ipairs(store:List({ routeId = false })) do
        if type(wp.source) == "string" and wp.source:sub(1, 7) == "TomTom:"
            and wp.map == m and wp.title == title
            and abs(wp.x - x) <= TOLERANCE and abs(wp.y - y) <= TOLERANCE then
            return wp
        end
    end
    return nil
end

local function ShimUid(wp)
    local u = Shim.byOrders[wp.uid]
    if u and Shim.handle[u] == wp.uid then return u end
    local from = type(wp.source) == "string" and wp.source:match("^TomTom:(.*)$") or wp.source
    u = { wp.map, wp.x, wp.y, title = wp.title, from = from or "?" }
    Shim.handle[u], Shim.byOrders[wp.uid] = wp.uid, u
    Shim.byKey[TolKey(wp.map, wp.x, wp.y, wp.title)] = u
    return u
end

-- The Orders uid a TomTom uid stands for, live or restored
local function ShimResolve(u)
    if type(u) ~= "table" then return nil end
    local h = ShimLive(u)
    if h then return h end
    local m, x, y = u[1], u[2], u[3]
    if not (IsNum(m) and IsNum(x) and IsNum(y)) then return nil end
    local hit = Shim.byKey[TolKey(m, x, y, u.title)]
    h = hit and ShimLive(hit)
    if h then return h end
    -- a uid given on a continent (Questie's Blackrock Mountain and Silithus
    -- NPCs sit on 1414 / 1415) names a record stored on the zone under it
    -- (D13): compare like with like, or it outlives every reload
    local zm, zx, zy = OnZone(m, x, y)
    local wp = ShimRecord(zm, zx, zy, u.title)
    return wp and wp.uid or nil
end

local SHIM = {}

function SHIM.AddWaypoint(m, x, y, opts)
    if not (IsNum(m) and IsNum(x) and IsNum(y)) then return nil end
    if type(opts) ~= "table" then opts = {} end
    if not Available() then return nil end
    local title = opts.title
    local key = TolKey(m, x, y, title)
    local live = Shim.byKey[key]
    if live and ShimLive(live) then
        -- TomTom returns the duplicate without re-arming the arrow (its
        -- B16); asking again means "go there", so the arrow follows
        if opts.crazy ~= false then
            store:SetPinned(Shim.handle[live])
            Changed("tomtom", true)
        end
        return live
    end
    local from = type(opts.from) == "string" and opts.from or "?"
    local u = { m, x, y, title = title, from = from }
    for k, v in pairs(opts) do
        local t = type(v)
        if type(k) == "string" and u[k] == nil and (t == "string" or t == "number" or t == "boolean") then
            u[k] = v
        end
    end
    local spec = {
        map = m, x = x, y = y, title = title, source = "TomTom:" .. from,
        persistent = opts.persistent ~= false, setArrow = opts.crazy ~= false, icon = "TOMTOM",
        handle = u, callbacks = type(opts.callbacks) == "table" and opts.callbacks or nil,
    }
    local clear = opts.cleardistance
    if IsNum(clear) then
        if clear > 0 then
            spec.arrive = clear
        else
            spec.clearOnArrive = false
            if IsNum(opts.arrivaldistance) and opts.arrivaldistance > 0 then spec.arrive = opts.arrivaldistance end
        end
    end
    local uid = API.Add(spec)
    if not uid then return nil end
    Shim.handle[u], Shim.byKey[key], Shim.byOrders[uid] = uid, u, u
    return u
end

-- Only a waypoint a TomTom caller still owns is removed. One that was the
-- user's or a group member's share before the caller's AddWaypoint landed
-- on it (the Store's same place and title is the same record), or that the
-- user has re-added since (API.Add claims it), stays; the handle lets go.
function SHIM.RemoveWaypoint(u)
    local h = ShimResolve(u)
    local wp = h and store and store:Get(h)
    if not wp then return end
    if type(wp.source) == "string" and wp.source:sub(1, 7) == "TomTom:" then
        if store:Remove(h, "tomtom") then Changed("tomtom") end
        return
    end
    ShimForget(wp)
    if Shim.handle[u] then
        Shim.handle[u] = nil
        for k, v in pairs(Shim.byKey) do
            if v == u then Shim.byKey[k] = nil end
        end
    end
end

function SHIM.SetCustomWaypoint(m, x, y, opts)
    local copy = {}
    for k, v in pairs(type(opts) == "table" and opts or {}) do copy[k] = v end
    copy.persistent = false
    return SHIM.AddWaypoint(m, x, y, copy)
end

function SHIM.AddWaypointToCurrentZone(x, y, desc)
    if not (IsNum(x) and IsNum(y)) then return nil end
    local map = PlayerMap()
    if not map then return nil end
    return SHIM.AddWaypoint(map, x / 100, y / 100, { title = desc })
end

function SHIM.IsValidWaypoint(u)
    return ShimResolve(u) ~= nil
end

function SHIM.WaypointExists(m, x, y, title)
    if not (store and IsNum(m) and IsNum(x) and IsNum(y)) then return false end
    return store:Find(m, x, y, title) ~= nil
end

-- TomTom's own key format, for callers that compare keys
function SHIM.GetKeyArgs(m, x, y, title)
    if not (IsNum(m) and IsNum(x) and IsNum(y)) then return nil end
    return format("%d:%s:%s:%s", m, tostring(x * 1e9), tostring(y * 1e9), tostring(title))
end

function SHIM.GetKey(u)
    if type(u) ~= "table" then return nil end
    return SHIM.GetKeyArgs(u[1], u[2], u[3], u.title)
end

function SHIM.GetCurrentPlayerPosition()
    return PlayerMapPos()
end

function SHIM.GetCurrentCoords()
    local _, x, y = PlayerMapPos()
    return x, y
end

function SHIM.GetDistanceToWaypoint(u)
    local h = ShimResolve(u)
    return h and API.Distance(h) or nil
end

-- World bearing, counter-clockwise from north (TomTom's sense)
function SHIM.GetDirectionToWaypoint(u)
    local h = ShimResolve(u)
    local wp = h and store:Get(h)
    if not wp then return nil end
    local n, w, inst = UnitWorld("player")
    local ti, tn, tw = PosWorld(wp)
    if not n or ti ~= inst then return nil end
    return G.Bearing(n, w, tn, tw)
end

function SHIM.SetCrazyArrow(u)
    local h = ShimResolve(u)
    if h then API.SetArrow(h) end
end

function SHIM.IsCrazyArrowEmpty()
    return API.Active() == nil
end

function SHIM.GetClosestWaypoint()
    if not store then return nil end
    local wp = store:Closest(BuildCtx(Clock(), true))
    return wp and ShimUid(wp) or nil
end

function SHIM.SetClosestWaypoint(verbose)
    if not store then return nil end
    local wp = store:Closest(BuildCtx(Clock(), true))
    if not wp then
        if verbose then Say("no waypoint on this landmass") end
        return nil
    end
    store:SetPinned(wp.uid)
    Changed("arrow", true)
    return ShimUid(wp)
end

-- Distance bands are honoured; the minimap/world click and tooltip
-- callbacks are accepted and ignored (pins draw their own)
function SHIM.DefaultCallbacks()
    return { minimap = {}, world = {}, distance = {} }
end

-- Methods take self (TomTom:AddWaypoint), never raise into the caller
for name, fn in pairs(SHIM) do
    TT[name] = function(_, ...)
        local results = { pcall(fn, ...) }
        if results[1] then return unpack(results, 2, table.maxn(results)) end
        Report(results[2])
        return nil
    end
end

-- Only while Orders is on: with it off every add is refused, and a shim
-- that answered nothing would leave Questie's and WhatsTraining's waypoint
-- buttons showing (they look for the TomTom global alone) and doing nothing
function Shim.Sync()
    local db = DB()
    local want = (db.TomTomShim and db.EnableOrders) and true or false
    if want and not Shim.installed then
        if rawget(_G, "TomTom") ~= nil or TomTomLoaded() then return end
        _G.TomTom = TT
        Shim.installed = true
    elseif not want and Shim.installed then
        if rawget(_G, "TomTom") == TT then _G.TomTom = nil end
        Shim.installed = false
    end
end

-- ---------------------------------------------------------------------------
-- Sharing (addon messages; receiving never steals the arrow)
-- ---------------------------------------------------------------------------
local Share = { recent = {} }
local SH = D.SHARE

local function Escape(s)
    return (s:gsub("[%%:|%c]", function(ch) return format("%%%02X", ch:byte()) end))
end

local function Unescape(s)
    return (s:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

function Share.Encode(wp)
    local title = Cut(wp.title or "", SH.MAX_TITLE)
    return format("%d:%d:%.5f:%.5f:%s", SH.VERSION, wp.map, wp.x, wp.y, Escape(title or ""))
end

function Share.Decode(text)
    if type(text) ~= "string" then return nil end
    local version, map, x, y, title = text:match("^(%d+):(%d+):([%d%.]+):([%d%.]+):(.*)$")
    if tonumber(version) ~= SH.VERSION then return nil end
    return tonumber(map), tonumber(x), tonumber(y), Unescape(title or "")
end

function Share.Register()
    local chat = C_ChatInfo
    if not (chat and chat.RegisterAddonMessagePrefix) then return end
    if not Share.registered then
        Share.registered = true
        pcall(chat.RegisterAddonMessagePrefix, SH.PREFIX)
    end
    if DB().ListenTomTom and not Share.tomtom then
        Share.tomtom = true
        pcall(chat.RegisterAddonMessagePrefix, SH.TOMTOM_PREFIX)
    end
end

local RESULT_WORDS = {
    [1] = "invalid prefix", [2] = "invalid message", [3] = "too many messages, try again",
    [4] = "that channel is not available", [5] = "not in a group", [8] = "too many messages, try again",
    [10] = "not in a guild", [11] = "chat is locked down",
}

local function GroupChannel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end

-- One spot ({ map, x, y, title }) onto the wire or into chat. channel:
-- nil/"GROUP" (your group, the right channel for it), "PARTY", "RAID",
-- "INSTANCE_CHAT", "GUILD", "CHAT" (the /way line as a chat message, for
-- players without addons: your group's chat, else /say) or "SAY". The chat
-- forms need a hardware event (a click or a key), so they come from menus.
-- quiet skips the Announce line (a caller whose own chat line says it).
function Share.Send(rec, channel, quiet)
    if type(channel) == "string" then channel = channel:upper() end
    if channel == "CHAT" or channel == "SAY" then
        local line = G.WayLine(rec.map, rec.x, rec.y, rec.title)
        local chatType = channel == "SAY" and "SAY" or (GroupChannel() or "SAY")
        if not SendChatMessage then return nil, "no chat" end
        local sent, err = pcall(SendChatMessage, line, chatType)
        if not sent then return nil, tostring(err) end
        return true
    end
    if channel == nil or channel == "GROUP" or channel == "" then channel = GroupChannel() end
    if not channel then return nil, "not in a group" end
    local chat = C_ChatInfo
    if not (chat and chat.SendAddonMessage) then return nil, "no addon messages" end
    if chat.InChatMessagingLockdown then
        local okL, locked = pcall(chat.InChatMessagingLockdown)
        if okL and locked then return nil, "chat is locked down" end
    end
    Share.Register()
    local sent, result = pcall(chat.SendAddonMessage, SH.PREFIX, Share.Encode(rec), channel)
    if not sent then return nil, tostring(result) end
    -- Every enum value is a truthy number: 0 is the only success
    if result ~= nil and result ~= true and result ~= 0 then
        return nil, RESULT_WORDS[result] or ("send failed (" .. tostring(result) .. ")")
    end
    if not quiet then
        Announce("shared " .. Describe(rec) .. " with your " .. strlower(channel == "INSTANCE_CHAT" and "group" or channel))
    end
    return true
end

-- One of your waypoints, to your group (channel as Share.Send)
function API.Share(uid, channel)
    local ok, why = Available()
    if not ok then return nil, why end
    local wp = store:Get(UidOf(uid))
    local pos = ShownPos(wp)
    if not (pos and pos.map) then return nil, "unknown waypoint" end
    -- the spawn the arrow follows, not a primary one it is not on
    return Share.Send({ map = pos.map, x = pos.x, y = pos.y, title = wp.title }, channel, false)
end

-- A spot that is NOT one of your waypoints ("Rally on me" in
-- Commander_Comms, the TopBar's Shift-click on its coordinates), shared
-- without adding it first: Add + Share + Remove would pin the arrow at your
-- own feet, play the set sound, and could remove a waypoint of yours that
-- sits at the same spot. spec = { map, x, y, title, silent }; silent skips
-- the Announce line. Same wire, channels and result words as Share.
function API.SharePoint(spec, channel)
    local ok, why = Available()
    if not ok then return nil, why end
    if type(spec) ~= "table" then return nil, "no spec" end
    local map, x, y = spec.map, spec.x, spec.y
    if not (S.ValidPosition(map, x, y) and MapInfo(map)) then return nil, "invalid position" end
    local title = Trim(spec.title)
    local rec = { map = map, x = x, y = y, title = title ~= "" and title or nil }
    return Share.Send(rec, channel, spec.silent)
end

local function ShortName(sender)
    if type(sender) ~= "string" then return "?" end
    if Ambiguate then
        local ok, short = pcall(Ambiguate, sender, "none")
        if ok and type(short) == "string" then return short end
    end
    return sender
end

local function IsSelf(sender)
    local me = UnitName and UnitName("player")
    if not me or type(sender) ~= "string" then return false end
    if sender == me or ShortName(sender) == me then return true end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    return realm ~= nil and sender == (me .. "-" .. realm)
end

local function InMyGroup(sender)
    local name = ShortName(sender)
    if UnitInParty and UnitInParty(name) then return true end
    if UnitInRaid and UnitInRaid(name) then return true end
    return false
end

local function Throttled(sender, now)
    local list = Share.recent[sender]
    if not list then
        list = {}
        Share.recent[sender] = list
    end
    for i = #list, 1, -1 do
        if now - list[i] > SH.WINDOW then table.remove(list, i) end
    end
    if #list >= SH.BURST then return true end
    list[#list + 1] = now
    return false
end

-- A received title as plain words. Every UI escape a sender can put in (%7C
-- on our wire, a raw | on TomTom's) would otherwise render in the dialog,
-- under the arrow, in the tooltips and the manager rows: |T a texture of any
-- size, |H a clickable link, |c a colour bleeding into what follows (review:
-- blizzard). A link keeps its text, the rest go, and any | or control
-- character left over is dropped.
local function PlainTitle(t)
    t = tostring(t or "")
    t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    t = t:gsub("|H.-|h(.-)|h", "%1")
    t = t:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|K.-|k", "")
    t = t:gsub("|n", " ")
    return (t:gsub("[|%c]", ""))
end

-- "Add" (and Add from my group) keeps the share temporary: never pinned, and
-- behind every waypoint of your own when Follow the Closest picks, so it
-- points the arrow only when you have nothing else. "Add and go" pins it.
function Share.Accept(rec, go)
    if type(rec) ~= "table" then return nil end
    local uid = API.Add({
        map = rec.map, x = rec.x, y = rec.y, title = rec.title ~= "" and rec.title or ("From " .. rec.sender),
        source = "share:" .. rec.sender, setArrow = go and true or false, persistent = true,
        temporary = not go, icon = "SHARE", silent = not go,
    })
    if uid and not go then Announce("added " .. rec.text .. " from " .. rec.sender) end
    return uid
end

function Share.OnMessage(prefix, text, channel, sender)
    local tomtom = prefix == SH.TOMTOM_PREFIX
    if prefix ~= SH.PREFIX and not tomtom then return end
    if tomtom and not DB().ListenTomTom then return end
    if not Available() then return end
    local policy = DB().ShareAccept
    if policy == "OFF" or IsSelf(sender) then return end
    local map, x, y, title
    if tomtom then
        local m, xs, ys, t = (text or ""):match("^(%d+):([%d%.]+):([%d%.]+):(.*)$")
        map, x, y, title = tonumber(m), tonumber(xs), tonumber(ys), t
    else
        map, x, y, title = Share.Decode(text)
    end
    if not (map and S.ValidPosition(map, x, y) and MapInfo(map)) then return end
    if Throttled(sender, Clock()) then return end
    title = PlainTitle(title)
    local rec = { map = map, x = x, y = y, title = Cut(Trim(title), 255), sender = ShortName(sender) }
    rec.text = Describe({ map = map, x = x, y = y, title = rec.title ~= "" and rec.title or nil })
    Cue("SET")
    if policy == "GROUP_AUTO_ADD" and channel ~= "GUILD" and InMyGroup(sender) then
        Share.Accept(rec, false)
        return
    end
    if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs.COMMANDER_ORDERS_SHARE then
        StaticPopup_Show("COMMANDER_ORDERS_SHARE", rec.sender, rec.text, rec)
    else
        Say(rec.sender .. " shared a waypoint: " .. rec.text .. " (/corder manager to add it)")
    end
end

-- ---------------------------------------------------------------------------
-- The corpse run
-- ---------------------------------------------------------------------------
-- Orders owns the corpse arrow (it used to be Commander_Recovery issuing a
-- normal order that overwrote yours). The death is remembered per character
-- (CommanderOrdersChar.Corpse) so a /reload or a relog while dead still finds
-- the way back (Recovery R1); the corpse itself is the client's own answer,
-- C_DeathInfo.GetCorpseMapPosition, asked on the map you are on and then
-- each parent up to the continent, the way Blizzard's corpse pin asks for
-- whatever map is shown. Feign Death is not a death (R2); battlegrounds and
-- arenas resurrect you at a graveyard on a timer, so they get no arrow (R3);
-- a death inside an instance points at its entrance when a resolver knows it
-- (R4). The corpse record never replaces your own target: the Store's rule 1
-- puts it first only while you are a ghost, and it is removed when you live.
local Corpse = {}

local function CharState()
    if type(CommanderOrdersChar) ~= "table" then return nil end
    return CommanderOrdersChar
end

local function PvPInstance()
    if not IsInInstance then return false end
    local inside, kind = IsInInstance()
    return inside and (kind == "pvp" or kind == "arena") or false
end

function Corpse.OnDead()
    if UnitIsFeignDeath and UnitIsFeignDeath("player") then return end
    if UnitIsDeadOrGhost and not UnitIsDeadOrGhost("player") then return end
    local char = CharState()
    if not char then return end
    local inside, kind = false, nil
    if IsInInstance then inside, kind = IsInInstance() end
    char.Corpse = {
        map = PlayerMap(), at = Epoch(),
        instance = inside and kind or nil,
        pvp = (kind == "pvp" or kind == "arena") or nil,
    }
    A.corpse = { reached = false }
end

function Corpse.Clear()
    local char = CharState()
    if char then char.Corpse = nil end
    A.corpse = nil
    if store then
        local c = store:Corpse()
        if c then
            store:Remove(c.uid, "alive")
            Changed("corpse")
        end
    end
end

-- The corpse on the map chain from where you stand: map, x, y
local function CorpseOnMaps()
    local api = C_DeathInfo and C_DeathInfo.GetCorpseMapPosition
    if type(api) ~= "function" then return nil end
    local map = PlayerMap()
    for _ = 1, 8 do
        if type(map) ~= "number" then return nil end
        local ok, pos = pcall(api, map)
        local x, y
        if ok then x, y = VectorXY(pos) end
        if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 and not (x == 0 and y == 0) then
            return map, x, y
        end
        local info = MapInfo(map)
        if not info or info.mapType <= 2 then return nil end
        map = info.parentMapID
    end
    return nil
end

function Corpse.Resolve()
    if not (store and DB().EnableOrders and DB().CorpseArrow) then return end
    if not (UnitIsGhost and UnitIsGhost("player")) then return end
    local char = CharState()
    local death = char and char.Corpse
    if (death and death.pvp) or PvPInstance() then return end
    if A.corpse and A.corpse.reached then return end
    local map, x, y = CorpseOnMaps()
    -- Found only on the continent (the ghost is a zone or two away): store
    -- it on the zone under it, never in a continent map's two frames
    if map then map, x, y = OnZone(map, x, y) end
    local title = "Your corpse"
    if not map and death and type(death.map) == "number" then
        local e = Entrance(death.map)
        if e then
            map, x, y = e.map, e.x, e.y
            title = "Your corpse: " .. (MapName(death.map) or "instance") .. " entrance"
        end
    end
    if not map then return end
    local wp = store:Add({
        kind = "corpse", source = "corpse", title = title, map = map, x = x, y = y,
        persistent = true, clearOnArrive = true, setArrow = false, icon = "CORPSE",
    })
    if wp then
        A.corpse = A.corpse or { reached = false }
        A.corpse.uid = wp.uid
        Changed("corpse", true)
    end
end

function Corpse.OnAlive()
    if UnitIsGhost and UnitIsGhost("player") then
        Corpse.Resolve()
    else
        Corpse.Clear()
    end
end

-- Login and zoning: a ghost gets the arrow back, the living lose a stale one
function Corpse.Check()
    if not store then return end
    local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")
    if dead then
        if UnitIsGhost and UnitIsGhost("player") then Corpse.Resolve() end
    elseif store:Corpse() or (CharState() and CharState().Corpse) then
        Corpse.Clear()
    end
end

-- Commander_Recovery's "Corpse arrow (Commander Orders)" option drives this
-- one setting through the API rather than writing Orders' saved variables
function API.CorpseArrow()
    return DB().CorpseArrow ~= false
end

function API.SetCorpseArrow(on)
    DB().CorpseArrow = on and true or false
    if O.DB and O.DB.Notify then O.DB.Notify() end
    if on then Corpse.Check() else
        local c = store and store:Corpse()
        if c then
            store:Remove(c.uid, "setting")
            Changed("corpse")
        end
    end
    return DB().CorpseArrow
end

-- ---------------------------------------------------------------------------
-- Places (account-wide named spots; the old rally points live here)
-- ---------------------------------------------------------------------------
local Places = {}

local function PlaceList()
    local db = DB()
    if type(db.Places) ~= "table" then db.Places = {} end
    return db.Places
end

local function FindPlace(ref)
    local list = PlaceList()
    if type(ref) == "number" then return list[ref], ref end
    if type(ref) ~= "string" then return nil end
    local want = strlower(Trim(ref))
    if want == "" then return nil end
    local n = tonumber(want)
    if n and list[n] then return list[n], n end
    for i, p in ipairs(list) do
        if type(p.title) == "string" and strlower(p.title) == want then return p, i end
    end
    return nil
end

function API.MarkPlace(title)
    local ok, why = Available()
    if not ok then return nil, why end
    local map, x, y = PlayerMapPos()
    if not map then return nil, "no position" end
    if not G.ToWorld(Env(), map, x, y) then return nil, "no world position" end
    local list = PlaceList()
    title = Trim(title)
    if title == "" then
        local n = #list + 1
        while FindPlace("Place " .. n) do n = n + 1 end
        title = "Place " .. n
    end
    local place, index = FindPlace(title)
    if not place then
        place = {}
        index = #list + 1
        list[index] = place
    end
    place.title, place.map, place.x, place.y = title, map, x, y
    place.faction, place.created = Faction(), Epoch()
    Cue("SET")
    Announce("place marked: " .. title .. " (" .. Where(place) .. ")")
    Changed("place", true)
    return index
end

function API.GoPlace(ref)
    local ok, why = Available()
    if not ok then return nil, why end
    local place = FindPlace(ref)
    if not place then return nil, "unknown place" end
    return API.Add({
        map = place.map, x = place.x, y = place.y, title = place.title,
        source = "place", key = "place:" .. strlower(place.title or ""), setArrow = true,
        clearOnArrive = true, persistent = true, icon = "PLACE",
    })
end

function API.Places()
    local out = {}
    for i, p in ipairs(PlaceList()) do
        out[i] = { index = i, title = p.title, map = p.map, x = p.x, y = p.y, faction = p.faction,
                   created = p.created, zone = MapName(p.map) }
    end
    return out
end

function API.RemovePlace(ref)
    local _, index = FindPlace(ref)
    if not index then return false end
    table.remove(PlaceList(), index)
    Changed("place", true)
    return true
end

function API.RenamePlace(ref, title)
    local place = FindPlace(ref)
    title = Trim(title)
    if not place or title == "" then return false end
    place.title = title
    Changed("place", true)
    return true
end

function Places.List()
    local list = PlaceList()
    if #list == 0 then
        Say("no places yet (/corder mark <name> while standing somewhere worth coming back to)")
        return
    end
    Say("places:")
    local mine = Faction()
    for i, p in ipairs(list) do
        local other = p.faction and mine and p.faction ~= mine
        print(format("  %d. %s (%s)%s", i, tostring(p.title), Where(p), other and (" [" .. p.faction .. "]") or ""))
    end
end

-- ---------------------------------------------------------------------------
-- Paste and export (the manager's paste window drives these)
-- ---------------------------------------------------------------------------
-- opts: route (true: one route), mode ("ORDERED" | "NEAREST"), title,
-- setArrow (default true: the first waypoint takes the arrow), source.
-- Returns added, errors ({ line, text, message, candidates }), routeId.
function API.Import(text, opts)
    local ok, why = Available()
    if not ok then return 0, { { line = 0, message = why } } end
    opts = type(opts) == "table" and opts or {}
    local specs, errors = {}, {}
    local resolver = Way.Resolver()
    local n = 0
    -- every line counts, empty ones too, so "Line 6" is the box's sixth line
    local src = (tostring(text or ""):gsub("\r\n?", "\n"))
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        if Trim(line) ~= "" then
            local cmd = G.ParseWay(line, resolver)
            if cmd.kind == "ADD" then
                local map = cmd.map or PlayerMap()
                if map and (not cmd.byId or MapInfo(map)) then
                    specs[#specs + 1] = { map = map, x = cmd.x, y = cmd.y, title = cmd.title, source = opts.source }
                else
                    errors[#errors + 1] = { line = n, text = line, message = "no such map" }
                end
            elseif cmd.kind == "ERROR" then
                errors[#errors + 1] = { line = n, text = line, message = cmd.message, candidates = cmd.candidates }
            else
                errors[#errors + 1] = { line = n, text = line, message = "not a waypoint line" }
            end
        end
    end
    if #specs == 0 then return 0, errors end
    if opts.route then
        local id, err = API.AddRoute({
            title = opts.title or "Pasted route", source = opts.source, mode = opts.mode or "ORDERED",
            stops = specs, start = opts.setArrow ~= false,
        })
        if not id then
            errors[#errors + 1] = { line = 0, message = tostring(err) }
            return 0, errors
        end
        local route = store:GetRoute(id)
        return route and #route.stops or 0, errors, id
    end
    local added = 0
    for i, spec in ipairs(specs) do
        spec.setArrow = (i == 1) and opts.setArrow ~= false or false
        spec.silent = i > 1
        local uid, err = API.Add(spec)
        if uid then added = added + 1 else errors[#errors + 1] = { line = 0, message = tostring(err) } end
    end
    return added, errors
end

-- /way lines for waypoints (a filter, a route id, or every standalone one)
function API.Export(filter)
    local lines = {}
    if not store then return lines end
    local list
    if type(filter) == "string" and store:GetRoute(filter) then
        list = {}
        for _, uid in ipairs(store:GetRoute(filter).stops) do list[#list + 1] = store:Get(uid) end
    else
        list = store:List(type(filter) == "table" and filter or { routeId = false })
    end
    for _, wp in ipairs(list) do
        if wp.map and wp.kind ~= "corpse" then lines[#lines + 1] = G.WayLine(wp.map, wp.x, wp.y, wp.title) end
    end
    return lines
end

local function PageList()
    local db = DB()
    if type(db.PastePages) ~= "table" then db.PastePages = {} end
    return db.PastePages
end

function API.PastePages()
    local out = {}
    for i, p in ipairs(PageList()) do out[i] = { name = p.name, text = p.text, saved = p.saved } end
    return out
end

function API.SavePastePage(name, text)
    name = Trim(name)
    if name == "" or type(text) ~= "string" then return false end
    local list = PageList()
    for _, p in ipairs(list) do
        if strlower(p.name or "") == strlower(name) then
            p.text, p.saved = text, Epoch()
            return true
        end
    end
    list[#list + 1] = { name = name, text = text, saved = Epoch() }
    return true
end

function API.DeletePastePage(name)
    local list = PageList()
    for i, p in ipairs(list) do
        if strlower(p.name or "") == strlower(Trim(name)) then
            table.remove(list, i)
            return true
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- The manager (CommanderOrdersUI.lua, when present)
-- ---------------------------------------------------------------------------
function API.OpenManager(uid)
    if CallUI("Open", uid) then return true end
    Way.List(false)
    return false
end

function API.ToggleManager()
    if CallUI("Toggle") then return true end
    return API.OpenManager()
end

-- text (optional): /way lines to put in the box, for a consumer that wants
-- the player to look them over before adding them
function API.OpenPaste(text)
    if CallUI("OpenPaste", type(text) == "string" and text or nil) then return true end
    Say("the paste window is part of the manager; /way lines can be typed one at a time")
    return false
end

-- ---------------------------------------------------------------------------
-- Commands (/corder, /way family, key bindings)
-- ---------------------------------------------------------------------------
local function ActiveWp()
    if not store then return nil end
    return store:ActiveTarget(BuildCtx(Clock()))
end

local function SetLock(locked)
    DB().ArrowLocked = locked
    if O.DB and O.DB.Notify then O.DB.Notify() end
    Say(locked and "arrow locked" or "arrow unlocked: drag it into place, then right-click it to lock")
end

local function Rally(word, rest)
    local slot = tonumber(rest)
    if not (slot and slot >= 1 and slot <= 4 and floor(slot) == slot) then return false end
    if word == "set" then
        CommanderOrders_RallySet(slot)
    else
        CommanderOrders_RallyGo(slot)
    end
    return true
end

local COMMANDS = {}

function COMMANDS.way(rest) Way.Run(rest) end
function COMMANDS.list() Way.List(false) end
function COMMANDS.arrow() Way.ArrowReport() end
function COMMANDS.unlock() SetLock(false) end
function COMMANDS.lock() SetLock(true) end
function COMMANDS.manager() API.ToggleManager() end
function COMMANDS.paste() API.OpenPaste() end
function COMMANDS.closest() Way.Closest() end
function COMMANDS.places() Places.List() end

function COMMANDS.here(rest)
    local uid, err = API.Here(rest)
    if not uid then
        Say(err == "no position" and "no map position here (instances have none)" or ("could not mark here (" .. tostring(err) .. ")"))
    end
end

function COMMANDS.clear()
    local wp = ActiveWp()
    if not wp then
        Say("no active waypoint")
        return
    end
    local text = Describe(wp)
    API.Remove(wp.uid)
    Announce("removed " .. text)
end

function COMMANDS.clearall()
    Way.Reset({ scope = "ALL" })
end

function COMMANDS.share(rest)
    local wp = ActiveWp()
    if not wp then
        Say("no active waypoint to share")
        return
    end
    local ok, err = API.Share(wp.uid, Trim(rest) ~= "" and Trim(rest) or nil)
    if not ok then Say("could not share: " .. tostring(err)) end
end

function COMMANDS.next()
    local uid, err = API.RouteNext()
    if not uid then Say(err == "no route" and "no route is running" or "that was the last stop") end
end

function COMMANDS.prev()
    local uid, err = API.RoutePrev()
    if not uid then Say(err == "no route" and "no route is running" or "that was the first stop") end
end

function COMMANDS.guide()
    local uid, err = API.Guide()
    if not uid then Say(err == "no guide" and "nothing to guide you to from here" or tostring(err)) end
end

function COMMANDS.mark(rest)
    local index, err = API.MarkPlace(rest)
    if not index then Say("could not mark a place here (" .. tostring(err) .. ")") end
end

function COMMANDS.go(rest)
    if Rally("go", rest) then return end
    if Trim(rest) == "" then
        Places.List()
        return
    end
    local uid, err = API.GoPlace(rest)
    if not uid then Say("no place called \"" .. Trim(rest) .. "\" (/corder places lists them)") end
    return uid, err
end

function COMMANDS.set(rest)
    if not Rally("set", rest) then Say("usage: /corder set 1-4 (or /corder mark <name>)") end
end

function API.Command(word, rest)
    word = strlower(Trim(word))
    local fn = COMMANDS[word]
    if not fn then return false end
    fn(type(rest) == "string" and rest or "")
    return true
end

local BINDINGS = {
    MANAGER = function() API.ToggleManager() end,
    CLEAR = function() COMMANDS.clear() end,
    HERE = function() COMMANDS.here("") end,
    NEXT = function() COMMANDS.next() end,
    PREV = function() COMMANDS.prev() end,
    CLOSEST = function() Way.Closest() end,
    SHARE = function() COMMANDS.share("") end,
    ARROW = function()
        DB().ShowArrow = not DB().ShowArrow
        if O.DB and O.DB.Notify then O.DB.Notify() end
    end,
}

function API.Binding(action)
    local fn = BINDINGS[action]
    if fn then fn() end
end

-- ---------------------------------------------------------------------------
-- The public API: every function pcall'd at the boundary, never raising
-- ---------------------------------------------------------------------------
local function Pack(ok, ...)
    if ok then return ... end
    Report((...))
    return nil, "error"
end

for name, fn in pairs(API) do
    O[name] = function(...) return Pack(pcall(fn, ...)) end
end

-- The surface the pins and the manager build on (same addon, live data):
--   R.Store()            the live Store (read records; mutate through O.*)
--   R.Env()              the Geo env (C_Map wrapped for Geo)
--   R.Ctx(force)         a ctx for Store calls (force: sample the map position now)
--   R.PosWorld(p)        inst, north, west of any {map, x, y} (cached per table)
--   R.PlayerWorld()      north, west, inst of the player (UnitPosition)
--   R.PlayerMap(), R.PlayerMapPos() -> map[, x, y], R.Facing()
--   R.View()             the arrow's view: mode ("NAV" | "ARRIVED" | "OTHER" |
--                        "NOPOS" | "NOWORLD" | "UNIT_LOST" | "NONE"), wp, why,
--                        distance, near, hop, landName
--   R.Eta()              seconds or nil, R.Distance(yards) -> "582 yd"
--   R.Title(wp), R.Where(wp), R.Describe(wp), R.MapName(map), R.Landmass(map, inst)
--   R.ShowMenu(entries, anchor)   entries = { { text, func, isTitle, disabled } }
--   R.WaypointMenu(uid)  the entries every waypoint offers (set, share, copy, remove)
--   R.CopyLine(text)     the "copy this /way line" box
--   R.RaisePopup(dialog) a StaticPopup's OnShow: over the maximized world map
--   R.Changed(reason, force), R.Cue("SET" | "ARRIVE"), R.Accent() -> r, g, b,
--   R.Say(msg), R.Resolve(kind, ...), R.Unlocked(), R.DB(), R.OnRemove(fn)
--   R.Arrow(), R.ArrowState(), R.Driver()   (the harnesses read these)
R.Store = function() return store end
R.Env = Env
R.Ctx = function(force) return BuildCtx(Clock(), force) end
R.PosWorld = PosWorld
R.PlayerWorld = function() return UnitWorld("player") end
R.PlayerMap = PlayerMap
R.PlayerMapPos = PlayerMapPos
R.Facing = Facing
R.View = function() return A.view end
R.Eta = function() return A.eta.eta end
R.DB = DB
R.Title = Title
R.Where = Where
R.Describe = Describe
R.MapName = MapName
R.Distance = Distance
R.ShowMenu = ShowMenu
R.WaypointMenu = WaypointMenu
R.CopyLine = CopyLine
R.RaisePopup = RaisePopup
R.Changed = Changed
R.Cue = Cue
R.Accent = Accent
R.Say = Say
R.Resolve = Resolve
R.Landmass = Landmass
R.Unlocked = Unlocked
R.OnRemove = function(fn)
    if type(fn) == "function" then removeListeners[#removeListeners + 1] = fn end
end
R.Arrow = function() return A.root end
-- For the harnesses: the arrow's regions and state, and the driver frame
R.ArrowState = function() return A end
R.Driver = function() return driver end
removeListeners[#removeListeners + 1] = ShimForget

-- ---------------------------------------------------------------------------
-- Legacy globals (documented wrappers; keep working for old callers)
-- ---------------------------------------------------------------------------
-- IssueOrder keeps the old single-slot feel for whoever still calls it: one
-- record under (legacy, order), moved by every new order, taking the arrow.
function CommanderOrders_IssueOrder(mapID, x01, y01)
    local uid = O.Add({ map = mapID, x = x01, y = y01, source = "legacy", key = "order", setArrow = true })
    return uid ~= nil
end

-- Clears the legacy order, else dismisses whatever the arrow follows; says
-- so only when something was cleared (the old one announced an empty clear)
function CommanderOrders_ClearOrder(announce)
    if not store then return end
    local wp = store:ByKey("legacy", "order")
    local cleared = false
    if wp then
        cleared = O.Remove(wp.uid) and true or false
    elseif store:Pinned() then
        cleared = O.ClearArrow() and true or false
    end
    if announce and cleared then Say("order cleared") end
end

function CommanderOrders_RallySet(slot)
    if type(slot) ~= "number" or slot < 1 or slot > 4 then return end
    local ok, why = Available()
    if not ok then
        Say(why == "disabled" and "Commander Orders is turned off (/corder to turn it on)" or "still loading")
        return
    end
    local index, err = O.MarkPlace("Rally " .. slot)
    if not index then Say("cannot mark a rally point here (" .. tostring(err) .. ")") end
end

function CommanderOrders_RallyGo(slot)
    if type(slot) ~= "number" or slot < 1 or slot > 4 then return end
    local ok, why = Available()
    if not ok then
        Say(why == "disabled" and "Commander Orders is turned off (/corder to turn it on)" or "still loading")
        return
    end
    if not FindPlace("Rally " .. slot) then
        Say(format("no rally point marked in slot %d (use /corder set %d)", slot, slot))
        return
    end
    O.GoPlace("Rally " .. slot)
end

function CommanderOrders_RallyList()
    Places.List()
end

-- ---------------------------------------------------------------------------
-- Popups (keys added to Blizzard's table, never the table itself)
-- ---------------------------------------------------------------------------
local function PopupEditBox(self)
    return self.editBox or (self.GetEditBox and self:GetEditBox())
end

local function DefinePopups()
    if type(StaticPopupDialogs) ~= "table" then return end
    StaticPopupDialogs.COMMANDER_ORDERS_SHARE = {
        text = "%s shared a waypoint:\n%s",
        button1 = "Add", button2 = "Ignore", button3 = "Add and go",
        selectCallbackByIndex = true,
        OnButton1 = function(_, data) Share.Accept(data, false) end,
        OnButton2 = function() end,
        OnButton3 = function(_, data) Share.Accept(data, true) end,
        OnAlt = function(_, data) Share.Accept(data, true) end,
        OnShow = RaisePopup,
        timeout = 60, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopupDialogs.COMMANDER_ORDERS_COPY = {
        text = "Copy this /way line (Ctrl-C), then paste it in chat:",
        button1 = OKAY or "Okay",
        hasEditBox = true, editBoxWidth = 320,
        OnShow = function(self)
            RaisePopup(self)
            local box = PopupEditBox(self)
            if box then
                box:SetText(A.copyText or "")
                box:HighlightText()
                box:SetFocus()
            end
        end,
        EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopupDialogs.COMMANDER_ORDERS_CLEAR_ALL = {
        text = "Remove every waypoint and route, including the ones other addons set?",
        button1 = "Remove all", button2 = CANCEL or "Cancel",
        OnAccept = function()
            local n = O.Clear()
            Say((n or 0) .. " waypoints removed")
        end,
        OnShow = RaisePopup,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end

-- ---------------------------------------------------------------------------
-- Settings changed
-- ---------------------------------------------------------------------------
local function ApplySettings()
    A.metric = nil
    if A.built then
        Arrow.ApplyChrome()
        A.title:SetTextColor(Accent())
    end
    Shim.Sync()
    Share.Register()
    Way.Register()
    if not DB().EnableOrders and driver then driver:Hide() end
    Arrow.Refresh()
    Wake()
    CallPins("Refresh")
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local function HookWorldMap()
    if A.mapHooked or not (WorldMapFrame and WorldMapFrame.HookScript) then return end
    A.mapHooked = true
    WorldMapFrame:HookScript("OnShow", function()
        A.mapShown = true
        Arrow.Refresh()
    end)
    WorldMapFrame:HookScript("OnHide", function()
        A.mapShown = false
        Arrow.Refresh()
    end)
    A.mapShown = WorldMapFrame.IsShown and WorldMapFrame:IsShown() and true or false
end

local function OnLogin()
    if O.DB and O.DB.Init then O.DB.Init() end
    LoadStore()
    driver = CreateFrame("Frame")
    driver:Hide()
    driver:SetScript("OnUpdate", OnFrame)
    Arrow.Build()
    A.inCombat = InCombatLockdown and InCombatLockdown() and true or false
    Arrow.ApplyChrome()
    DefinePopups()
    HookWorldMap()
    Shim.Sync()
    Share.Register()
    Way.Register()
    if Commander and Commander.AddListener then
        Commander.AddListener(COMMANDER_ORDERS_EVENTS.UPDATE, ApplySettings)
    end
    loggedIn = true
    Corpse.Check()
    Arrow.Refresh()
    Wake()
end

local HANDLERS = {}

function HANDLERS.ADDON_LOADED(name)
    if name ~= "Commander_Orders" then return end
    if O.DB and O.DB.Init then O.DB.Init() end
    LoadStore()
end

function HANDLERS.PLAYER_LOGIN()
    OnLogin()
end

function HANDLERS.PLAYER_ENTERING_WORLD()
    Corpse.Check()
    Arrow.Refresh()
    Wake()
end

HANDLERS.ZONE_CHANGED_NEW_AREA = function() Corpse.Check(); Wake() end
HANDLERS.ZONE_CHANGED = function() Wake() end
HANDLERS.ZONE_CHANGED_INDOORS = function() Wake() end
HANDLERS.GROUP_ROSTER_UPDATE = function() Wake() end
HANDLERS.PLAYER_DEAD = function() Corpse.OnDead() end
HANDLERS.PLAYER_ALIVE = function() Corpse.OnAlive(); Wake() end
HANDLERS.PLAYER_UNGHOST = function() Corpse.Clear(); Wake() end
HANDLERS.CORPSE_POSITION_UPDATE = function() Corpse.Resolve(); Wake() end

function HANDLERS.PLAYER_REGEN_DISABLED()
    A.inCombat = true
    Arrow.Refresh()
end

function HANDLERS.PLAYER_REGEN_ENABLED()
    A.inCombat = false
    if A.chromePending then Arrow.ApplyChrome() end
    Arrow.Refresh()
end

function HANDLERS.MODIFIER_STATE_CHANGED()
    Arrow.UpdateMouse()
end

function HANDLERS.CHAT_MSG_ADDON(prefix, text, channel, sender)
    Share.OnMessage(prefix, text, channel, sender)
end

function HANDLERS.PLAYER_LOGOUT()
    SaveStore()
end

local events = CreateFrame("Frame")
for event in pairs(HANDLERS) do events:RegisterEvent(event) end
events:SetScript("OnEvent", function(_, event, ...)
    local fn = HANDLERS[event]
    if not fn then return end
    if event ~= "ADDON_LOADED" and event ~= "PLAYER_LOGIN" and not loggedIn then return end
    local ok, err = pcall(fn, ...)
    if not ok then Report(err) end
end)
