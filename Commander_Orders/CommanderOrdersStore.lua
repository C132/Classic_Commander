-- Commander Orders: the model.
--
-- Every waypoint, every route and the rule that decides which one the arrow
-- follows live here as plain tables, with no frame and no client call in
-- sight. The runtime (CommanderOrders.lua) owns the clock, the player's
-- position and the world maths and passes them in; this file answers. The
-- harness (Harness/orders_store_smoke.lua) passes in fakes and asserts on
-- the answers, which is how the old module's bugs get pinned down for good.
--
-- WHY it is shaped like this (each paragraph is a bug it exists to prevent)
--
-- One slot was the old module's undoing (orders.md D3): every caller
-- overwrote the player's order and nobody could tell whose it was. Here a
-- waypoint is a record with a string uid ("w12"), unique per character and
-- never reused: the counter is saved with the records (even when no record
-- is), so a uid handed out before a /reload never comes back meaning a
-- different place.
--
-- Consumers own their waypoints through (source, key). Re-adding with the
-- same pair MOVES the existing record (same uid, same arrow) instead of
-- stacking a second one, and RemoveBy(source, key) finds it after a /reload
-- without the consumer keeping a handle anywhere. That is what Recovery's
-- float-equality clean-up and its account-wide IssuedOrder were reaching for.
-- A route is owned the same way: AddRoute with a (source, key) that already
-- exists replaces that route, under the same id.
--
-- Coordinates are compared with a tolerance (S.TOLERANCE, 1e-6 of a map),
-- never with ==. The client's saved-variable writer prints 16 significant
-- digits and a double can need 17, so 0.3820961713790894 can come back one
-- bit off. Questie keeps TomTom's uid in its own saved variables and hands
-- the stale copy back after a reload; the shim finds the restored waypoint
-- with Find, and a consumer re-adding the original numbers gets the restored
-- record back instead of a twin.
--
-- Nothing executable is ever persisted. TomTom copies its callbacks (a table
-- of functions) into the uid and lets the SV writer drop them on the floor;
-- here the shim's distance callbacks live in wp.callbacks, a runtime-only
-- side table that Serialize never touches (it writes a whitelist of plain
-- fields, so a stray frame or function on a record cannot leak into the SV).
--
-- Instance 530 holds both Outland and the Blood Elf / Draenei starting zones,
-- so two positions "on the same instance" can be a world apart and their raw
-- distance is garbage (orders.md D4, the grey arrow that never went away).
-- The store never measures between two maps unless ctx.sameLandmass says
-- they share a landmass; the runtime's rule is Geo.SameLandmass (SPEC 2).
--
-- ---------------------------------------------------------------------------
-- What the runtime passes in (ctx; every field optional, a nil ctx is legal)
-- ---------------------------------------------------------------------------
--   ctx.player           {map=, x=, y=} the player's position on a uiMap
--                        (C_Map.GetBestMapForUnit + GetPlayerMapPosition);
--                        nil when unknown (instances): no closest, no
--                        arrival, the pinned/route target still resolves
--   ctx.distance(a, b)   -> yards | nil. a and b are tables with map, x, y
--                        (records, alternatives, ctx.player). nil when the
--                        two cannot be compared. The store calls it with
--                        a == ctx.player for "distance from the player", so
--                        the runtime may answer that case from UnitPosition
--   ctx.sameLandmass(mA, mB) -> bool (SPEC 2 rule). Absent: one landmass
--   ctx.unitPosition(unit)   -> {map=, x=, y=} | nil, for kind "unit"
--   ctx.ghost            the player is a released ghost
--   ctx.corpseArrow      setting CorpseArrow (nil counts as on)
--   ctx.autoClosest      setting AutoClosest (nil counts as on)
--   ctx.arriveYards      setting ArriveYards, for records without .arrive
--   ctx.onTaxi           UnitOnTaxi("player")
--   ctx.now              monotonic seconds for the rescan throttle
--   ctx.closestScope     3.1, setting ClosestScope: "ZONE" keeps Follow the
--                        Closest (and Closest) to waypoints in the player's
--                        zone, through ctx.sameZone(mapA, mapB) -> bool;
--                        anything else (nil included) is the whole landmass
--   ctx.closestMine      3.1, setting ClosestMineOnly: Follow the Closest
--                        leaves out what other addons asked for through the
--                        TomTom bridge (source "TomTom:*"); the bridge's own
--                        GetClosestWaypoint passes anyOwner and still sees them
--
-- Clocks. S.New(clock, epoch): clock() is monotonic seconds (GetTime) and is
-- the fallback for Tick's now and ctx.now; epoch() is wall seconds (time) for
-- the created/reached stamps and defaults to clock. Only differences of one
-- clock are ever compared, so passing time alone also works, coarsely.
--
-- The runtime's tick, at 10 Hz while NeedsTick says so:
--     local wp, why = store:ActiveTarget(ctx)
--     local pos     = wp and store:Position(wp, ctx)    -- where to point
--     local d       = <yards to pos, or nil off-landmass / no position>
--     for _, e in ipairs(store:Tick(ctx, d, GetTime())) do ... end
-- and it polls store.version (bumped by every mutation) to refresh lists,
-- pins and the hub CHANGED event. store.onRemove = fn(wp, reason) is called
-- (pcall'd) for every record that leaves, whoever removed it, so the TomTom
-- shim can drop its side-table entries (thirdparty.md 5.2 lifecycle hook).
--
-- ---------------------------------------------------------------------------
-- API (O.Store = S; a store is S.New(...) or S.Load(...))
-- ---------------------------------------------------------------------------
--   S.New(clock, epoch) / S.Load(plain, clock, epoch)     store
--   S.ValidPosition(map, x, y) -> ok, reason   S.Copy(wp) -> detached plain copy
--   S.ANY (Find's any-title)   S.TOLERANCE, S.DEFAULT_ARRIVE, S.ARRIVE_HOLD, ...
--   store:Add(spec) -> wp, nil, "added"|"moved"|"existing"  | nil, reason
--   store:Get(uid)  :ByKey(source, key)  :Corpse()  :Find(map, x, y, title, tol)
--   store:List(filter) / :Count(filter)   filter = { source, map, kind,
--         routeId (false = standalone only), reached, temporary }
--   store:Update(uid, fields) -> wp | nil, reason
--   store:Remove(uid[, reason]) -> bool   :RemoveBy(source[, key]) -> n
--   store:Clear([filter[, reason]]) -> n
--   store:ActiveTarget(ctx) -> wp, why    :Position(wp|uid, ctx) -> pos, altIndex
--         (pos is READ ONLY: the record, a candidate, or ctx.unitPosition's table)
--   store:Distance(wp|uid, ctx) -> yards  :Closest(ctx[, anyOwner]) -> wp, yards (no hysteresis)
--   store:Retarget(uid, unit) (3.1: a unit follow moves to the member's new token)
--   store:ChosenAlternative(uid) -> index
--   store:SetPinned(uid) -> ok, reason    :ClearPinned([dismiss])  :Pinned()
--   store:Suppressed()   :MarkReached(uid) ("Mark arrived" on a kept mark)
--   store:Claim(uid, source) (a keyless standalone record changes owner)
--   store:AddRoute(spec[, ctx]) -> route, nil, skipped | nil, reason
--   store:AddStop(routeId, spec[, ctx])   :RemoveRoute(id)   :RouteStart(id[, ctx])
--   store:RouteNext([id]) / :RoutePrev([id]) -> stop | nil, reason
--   store:RouteReverse([id])   :RouteOptimize(playerPos, geo[, id])
--   store:GetRoute(id)   :Routes()   :ActiveRoute()   :FindRoute(source, key)
--   store:Tick(ctx, distance, now) -> events (S.NO_EVENTS when none)
--   store:State()   :ArrivalState() -> uid, state   :NeedsTick(ctx)
--   store:Serialize() -> plain table (CommanderOrdersChar.Store): persistent
--         records and routes, plus (3.1, SPEC D5) the record the arrow is
--         PINNED to (not a unit follow, not a temporary offer) and the
--         ACTIVE route, session-only or not, so a Go pressed before a
--         /reload still points after it, and the record a pinned "Guide
--         me" hop names in guideFor (its target); everything else a
--         consumer made stays session-only
--   store.version (bumped by every mutation)   store.onRemove = fn(wp, reason)
--   store.rescanInterval, store.arriveHold (tunable; the harness pins them)
-- Records and routes handed out are the live ones: read them, change them
-- through Update and the route calls (the public API hands out S.Copy).
--
-- ---------------------------------------------------------------------------
-- Who owns the arrow (ActiveTarget), first match wins
-- ---------------------------------------------------------------------------
--   1 CORPSE   the kind "corpse" record while ctx.ghost and CorpseArrow is on
--   2 PINNED   the waypoint the user chose. Pinning a route stop instead jumps
--              its route to that stop, so arriving there advances the route
--   3 ROUTE    the active route's current stop
--   4 CLOSEST  the nearest eligible waypoint on the player's landmass while
--              AutoClosest is on: never a route stop, a corpse, a unit
--              follow or one already reached; non-temporary before temporary
-- Temporary waypoints (Oracle nodes, pings, a repair offer) never take the
-- pin from a non-temporary pinned waypoint, nor the arrow from a running
-- route; they wait until the user has neither.
-- ClearPinned(true) means "the user dismissed the arrow": rules 3 and 4 stay
-- quiet until something arrow-shaped happens again (a pin, a route start or
-- step, an Add with setArrow). Without that, AutoClosest would put the arrow
-- straight back and Clear would look broken.
--
-- Hysteresis. Two quest-giver spawns at about the same distance made a plain
-- "nearest" flick between them with every step. Closest and the nearest-of-N
-- alternatives switch only when the challenger is BOTH 20% AND 30 yd closer
-- than the current choice (SWITCH_RATIO, SWITCH_YARDS); a choice that leaves
-- the player's landmass is dropped at once. Scans run at most every 0.5 s per
-- store version (store.rescanInterval), because alternatives can be hundreds
-- of spawns and the arrow ticks at 10 Hz.
--
-- ---------------------------------------------------------------------------
-- Arrival (Tick)
-- ---------------------------------------------------------------------------
-- NAVIGATING -> NEAR (within 3x the radius; it leaves NEAR only beyond 3.3x,
-- so a player standing on the edge does not pulse on and off) -> ARRIVED
-- (within the radius; the event fires once and the state is held 2.5 s so the
-- ring and the sound are seen) -> DONE (clear and/or advance the route). It
-- never arrives on a taxi: flying over a mark is not reaching it, landing on
-- it is. A target that loses the arrow while ARRIVED still gets its DONE.
-- A waypoint first measured inside its radius on the first tick after it was
-- created, moved or loaded does not arrive until the player has left the
-- radius and come back: /wayb and "Mark place here" must not clear
-- themselves under the player's feet. That is TomTom's lastdistance == nil
-- rule, without its trap of also refusing route stops that happen to stand
-- next to each other (those were created long before they became the target).
--
-- Distance bands (the TomTom shim). callbacks.distance[yards] =
-- fn("distance", handle, range, distance, lastDistance). The first tick fires
-- the innermost band holding the player with lastDistance nil (TomTom parity:
-- a caller can tell "already inside" from "walked in"); afterwards each band
-- crossed INWARD fires once, outermost first, even several in one tick.
-- Outward moves fire nothing (TomTom fired the outer band again, so its
-- arrival ping sounded on the way out too). Every call is pcall'd and an
-- error comes back as a CALLBACK_ERROR event for the runtime to hand to the
-- error handler, so a third-party bug never stops the arrow. Bands run for
-- every waypoint that has them, target or not, and on taxis (TomTom parity:
-- its callbacks check the taxi themselves).
--
-- Routes. ORDERED keeps the given order. NEAREST re-orders the stops still
-- ahead (the current one included) when the route starts and when a stop is
-- added: stops are grouped by landmass, the player's landmass first and the
-- rest in the order of their first stop, then chained nearest-neighbour from
-- the player (or from the group's first stop). Arrival on the current stop
-- clears it when clearOnArrive (otherwise marks it reached) and advances; the
-- last one ends the route (ROUTE_COMPLETE) and removes it. A looping route
-- never clears its stops, it wraps.

CommanderOrders = CommanderOrders or {}
local O = CommanderOrders
O.Store = O.Store or {}
local S = O.Store

local type, pairs, ipairs, next, pcall = type, pairs, ipairs, next, pcall
local tostring, tonumber, setmetatable = tostring, tonumber, setmetatable
local floor, abs, huge = math.floor, math.abs, math.huge
local tremove, tinsert, tsort = table.remove, table.insert, table.sort

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------
local SCHEMA = 1                 -- Serialize format; S.Load reads <= this
local DEFAULT_ARRIVE = 10        -- yards, when neither record nor ctx says
local NEAR_FACTOR = 3            -- NEAR within 3x the arrival radius
local NEAR_EXIT_FACTOR = 3.3     -- and leaves it beyond 3.3x
local ARRIVE_HOLD = 2.5          -- seconds ARRIVED is held before DONE
local SWITCH_RATIO = 0.8         -- hysteresis: challenger <= 80% of current
local SWITCH_YARDS = 30          -- ... and at least 30 yd nearer
local RESCAN_INTERVAL = 0.5      -- seconds between closest/alternative scans
local TOLERANCE = 1e-6           -- map units; dedup and Find
local MAX_TITLE = 255            -- bytes; cut on a UTF-8 boundary
local MAX_ALTERNATIVES = 256     -- nearest-of-N candidates kept per record

S.SCHEMA = SCHEMA
S.DEFAULT_ARRIVE = DEFAULT_ARRIVE
S.NEAR_FACTOR = NEAR_FACTOR
S.NEAR_EXIT_FACTOR = NEAR_EXIT_FACTOR
S.ARRIVE_HOLD = ARRIVE_HOLD
S.SWITCH_RATIO = SWITCH_RATIO
S.SWITCH_YARDS = SWITCH_YARDS
S.RESCAN_INTERVAL = RESCAN_INTERVAL
S.TOLERANCE = TOLERANCE
S.MAX_TITLE = MAX_TITLE
S.MAX_ALTERNATIVES = MAX_ALTERNATIVES

-- Pass as Find's title to match any title (nil only matches nil)
S.ANY = S.ANY or setmetatable({}, { __tostring = function() return "CommanderOrders.Store.ANY" end })
local ANY = S.ANY

local KINDS = { point = true, corpse = true, unit = true, stop = true }
local MODES = { ORDERED = true, NEAREST = true }

-- The record fields that reach the saved variables (alternatives handled
-- apart). Anything else on a record (callbacks, a consumer's stray field)
-- stays in this session.
local PERSIST_FIELDS = {
    "uid", "map", "x", "y", "title", "note", "source", "key", "kind", "unit",
    "icon", "colour", "arrive", "clearOnArrive", "persistent", "temporary",
    "routeId", "routeIndex", "created", "reached", "guideFor",
}

local EMPTY = {}

-- ---------------------------------------------------------------------------
-- Validation and normalising (pure helpers)
-- ---------------------------------------------------------------------------
local function IsNumber(v)
    return type(v) == "number" and v == v and v > -huge and v < huge
end

local function ValidMap(v)
    return IsNumber(v) and v > 0 and floor(v) == v
end

local function ValidCoord(v)
    return IsNumber(v) and v >= 0 and v <= 1
end

-- ok, reason: the one place the position rule is spelled out
function S.ValidPosition(map, x, y)
    if not ValidMap(map) then return false, "invalid map" end
    if not ValidCoord(x) then return false, "invalid x" end
    if not ValidCoord(y) then return false, "invalid y" end
    return true
end

-- Strings pass, numbers become strings, anything else is no title. Long
-- titles are cut on a UTF-8 boundary so a pasted wall of text cannot bloat
-- the SV or end in half a glyph; dedup compares the cut form both ways.
local function NormTitle(t)
    if type(t) == "number" then t = tostring(t) end
    if type(t) ~= "string" then return nil end
    if #t > MAX_TITLE then
        local cut = MAX_TITLE
        local b = t:byte(cut + 1)
        while cut > 0 and b and b >= 0x80 and b < 0xC0 do
            cut = cut - 1
            b = t:byte(cut + 1)
        end
        t = t:sub(1, cut)
    end
    return t
end
S.NormTitle = NormTitle

local function NormString(s)
    if type(s) == "string" and s ~= "" then return s end
    return nil
end

local function NormKey(k)
    if type(k) == "string" then return k end
    if IsNumber(k) then return k end
    return nil
end

local function NormSource(s)
    return NormString(s) or "user"
end

-- {map=, x=, y=} or {map, x, y} -> {map=, x=, y=} | nil
local function NormPos(p)
    if type(p) ~= "table" then return nil end
    local m, x, y = p.map, p.x, p.y
    if m == nil then m = p[1] end
    if x == nil then x = p[2] end
    if y == nil then y = p[3] end
    if ValidMap(m) and ValidCoord(x) and ValidCoord(y) then
        return { map = m, x = x, y = y }
    end
    return nil
end

local function SamePos(a, b, tol)
    return a.map == b.map and abs(a.x - b.x) <= tol and abs(a.y - b.y) <= tol
end

-- Valid candidates only, near-duplicates folded, capped. The primary
-- position (when there is one) is always alternatives[1]; a list that folds
-- down to the primary alone is no list at all.
local function NormAlternatives(list, primary)
    if type(list) ~= "table" then return nil end
    local out = {}
    if primary then out[1] = { map = primary.map, x = primary.x, y = primary.y } end
    for _, a in ipairs(list) do
        if #out >= MAX_ALTERNATIVES then break end
        local p = NormPos(a)
        if p then
            local dup = false
            for i = 1, #out do
                if SamePos(out[i], p, TOLERANCE) then dup = true break end
            end
            if not dup then out[#out + 1] = p end
        end
    end
    if #out < 2 then return nil end
    return out
end

-- callbacks.distance[yards] = fn, copied (never the caller's table), with the
-- band radii sorted ascending. handle is what the callback receives as its
-- uid argument (the shim's uid table); the record's own uid when absent.
local function NormCallbacks(cb, handle)
    if type(cb) ~= "table" or type(cb.distance) ~= "table" then return nil end
    local dist, bands = {}, {}
    for yards, fn in pairs(cb.distance) do
        if IsNumber(yards) and yards >= 0 and type(fn) == "function" then
            dist[yards] = fn
            bands[#bands + 1] = yards
        end
    end
    if #bands == 0 then return nil end
    tsort(bands)
    if handle == nil then handle = cb.handle end
    return { distance = dist, bands = bands, handle = handle }
end

local function KeyOf(source, key)
    return source .. "\1" .. type(key) .. "\1" .. tostring(key)
end

local function SeqOf(id, prefix)
    if type(id) ~= "string" then return nil end
    local n = id:match("^" .. prefix .. "(%d+)$")
    return n and tonumber(n) or nil
end

local function IndexOf(list, value)
    for i = 1, #list do
        if list[i] == value then return i end
    end
    return nil
end

-- Build a record from a spec, or nil, reason. No uid yet; the caller assigns
-- it once dedup has decided this really is a new record.
local function BuildRecord(spec, asStop)
    local kind = spec.kind
    if not KINDS[kind] then kind = "point" end
    if asStop then
        kind = "stop"
    elseif kind == "stop" then
        kind = "point"
    end
    local unit = NormString(spec.unit)
    if kind == "unit" and not unit then return nil, "invalid unit" end

    local m, x, y = spec.map, spec.x, spec.y
    local primary
    if m == nil and x == nil and y == nil then
        -- no position of its own: the first usable alternative is the primary
        if type(spec.alternatives) == "table" then
            for _, a in ipairs(spec.alternatives) do
                primary = NormPos(a)
                if primary then break end
            end
        end
        if not primary and kind ~= "unit" then return nil, "no position" end
    else
        local ok, err = S.ValidPosition(m, x, y)
        if not ok then return nil, err end
        primary = { map = m, x = x, y = y }
    end

    local source = NormSource(spec.source)
    local clear
    if spec.clearOnArrive == nil then
        clear = source ~= "place"
    else
        clear = spec.clearOnArrive and true or false
    end
    local arrive = spec.arrive
    if not (IsNumber(arrive) and arrive > 0) then arrive = nil end

    return {
        map = primary and primary.map, x = primary and primary.x, y = primary and primary.y,
        title = NormTitle(spec.title),
        note = NormString(spec.note),
        source = source,
        key = NormKey(spec.key),
        kind = kind,
        unit = (kind == "unit") and unit or nil,
        alternatives = NormAlternatives(spec.alternatives, primary),
        icon = NormString(spec.icon),
        colour = NormString(spec.colour),
        arrive = arrive,
        clearOnArrive = clear,
        persistent = spec.persistent ~= false,
        temporary = spec.temporary == true,
        callbacks = NormCallbacks(spec.callbacks, spec.handle),
        -- a "Guide me" hop: the uid of the record it leads to (3.1)
        guideFor = SeqOf(spec.guideFor, "w") and spec.guideFor or nil,
    }
end

-- A plain copy: the persisted fields plus alternatives as {map, x, y}
-- triples (compact in the SV; NormPos reads both shapes back).
local function PlainRecord(wp, keyedAlternatives)
    local out = {}
    for _, f in ipairs(PERSIST_FIELDS) do
        local v = wp[f]
        local t = type(v)
        if t == "string" or t == "boolean" or (t == "number" and v == v) then out[f] = v end
    end
    if wp.alternatives then
        local alts = {}
        for i, a in ipairs(wp.alternatives) do
            if keyedAlternatives then
                alts[i] = { map = a.map, x = a.x, y = a.y }
            else
                alts[i] = { a.map, a.x, a.y }
            end
        end
        out.alternatives = alts
    end
    return out
end

-- A detached copy for callers outside the store (the public API's Get/List):
-- no callbacks, alternatives keyed.
function S.Copy(wp)
    if type(wp) ~= "table" then return nil end
    return PlainRecord(wp, true)
end

-- ---------------------------------------------------------------------------
-- The store object
-- ---------------------------------------------------------------------------
local Store = {}
Store.__index = Store
S.Methods = Store

function S.New(clock, epoch)
    local self = setmetatable({}, Store)
    self.clock = type(clock) == "function" and clock or function() return 0 end
    self.epoch = type(epoch) == "function" and epoch or self.clock
    self.version = 0
    self.byUid = {}            -- uid -> record
    self.order = {}            -- uids in creation order (deterministic scans)
    self.byKey = {}            -- KeyOf(source, key) -> uid, standalone records only
    self.routes = {}           -- id -> route
    self.routeOrder = {}       -- ids in creation order
    self.nextUid = 1
    self.nextRoute = 1
    self.pinned = nil
    self.activeRoute = nil
    self.suppressed = false
    self.rescanInterval = RESCAN_INTERVAL
    self.arriveHold = ARRIVE_HOLD
    self.onRemove = nil
    -- runtime-only state, never serialized
    self._ticks = 0            -- completed Ticks; records are stamped with it
    self._inTick = false
    self._born = {}            -- uid -> _ticks when created/moved/loaded
    self._alt = {}             -- uid -> { index, at, version } chosen alternative
    self._closest = nil        -- { uid, at, version } AutoClosest choice
    self._arrival = nil        -- { uid, state, observed, armed, arrivedAt }
    self._finishing = {}       -- ARRIVED records that lost the arrow mid-hold
    self._bands = {}           -- uid -> { band, last } distance-callback state
    return self
end

local function Bump(self)
    self.version = self.version + 1
end

local function SafeCall(fn, a, b)
    local ok, r = pcall(fn, a, b)
    if ok then return r end
    return nil
end

local function SameLand(ctx, mapA, mapB)
    if mapA == nil or mapB == nil then return false end
    if mapA == mapB then return true end
    local fn = ctx and ctx.sameLandmass
    if type(fn) ~= "function" then return true end
    return SafeCall(fn, mapA, mapB) == true
end

local function Measure(ctx, a, b)
    local fn = ctx and ctx.distance
    if type(fn) ~= "function" or not a or not b then return nil end
    local d = SafeCall(fn, a, b)
    if IsNumber(d) and d >= 0 then return d end
    return nil
end

local function Now(self, ctx, now)
    if IsNumber(now) then return now end
    if ctx and IsNumber(ctx.now) then return ctx.now end
    return self.clock()
end

local function Fresh(self, at, now, version)
    return at and at.version == version and now >= at.at and now - at.at < self.rescanInterval
end

-- ---------------------------------------------------------------------------
-- Internal bookkeeping
-- ---------------------------------------------------------------------------
-- The tick a record counts as born in: the coming one, also for records a
-- distance callback adds while a Tick is running
local function BornStamp(self)
    return self._ticks + (self._inTick and 1 or 0)
end

local function Insert(self, wp)
    self.byUid[wp.uid] = wp
    self.order[#self.order + 1] = wp.uid
    if wp.key ~= nil and wp.routeId == nil then
        self.byKey[KeyOf(wp.source, wp.key)] = wp.uid
    end
    self._born[wp.uid] = BornStamp(self)
end

local function NewUid(self)
    local uid = "w" .. self.nextUid
    self.nextUid = self.nextUid + 1
    return uid
end

local function Reindex(self, route)
    for i, uid in ipairs(route.stops) do
        local wp = self.byUid[uid]
        if wp then wp.routeIndex = i end
    end
end

local function DropRoute(self, route)
    self.routes[route.id] = nil
    local i = IndexOf(self.routeOrder, route.id)
    if i then tremove(self.routeOrder, i) end
    if self.activeRoute == route.id then self.activeRoute = nil end
end

-- Forget everything about a record. keepRoute: the caller is taking the
-- route apart itself (RemoveRoute, a finished route), leave its list alone.
local function Unlink(self, wp, reason, keepRoute)
    local uid = wp.uid
    if self.byUid[uid] ~= wp then return end
    self.byUid[uid] = nil
    local i = IndexOf(self.order, uid)
    if i then tremove(self.order, i) end
    if wp.key ~= nil and wp.routeId == nil then
        local k = KeyOf(wp.source, wp.key)
        if self.byKey[k] == uid then self.byKey[k] = nil end
    end
    if not keepRoute and wp.routeId then
        local route = self.routes[wp.routeId]
        local pos = route and IndexOf(route.stops, uid)
        if pos then
            tremove(route.stops, pos)
            if pos < route.index then route.index = route.index - 1 end
            if #route.stops == 0 then
                DropRoute(self, route)
            else
                if route.index > #route.stops then
                    route.index = route.loop and 1 or #route.stops
                end
                if route.index < 1 then route.index = 1 end
                Reindex(self, route)
            end
        end
    end
    if self.pinned == uid then self.pinned = nil end
    self._alt[uid] = nil
    self._bands[uid] = nil
    self._born[uid] = nil
    for j = #self._finishing, 1, -1 do
        if self._finishing[j].uid == uid then tremove(self._finishing, j) end
    end
    if self._closest and self._closest.uid == uid then self._closest = nil end
    if type(self.onRemove) == "function" then
        pcall(self.onRemove, wp, reason or "remove")
    end
end

local function RemoveRouteInternal(self, route, reason)
    local stops = {}
    for i, uid in ipairs(route.stops) do stops[i] = uid end
    for _, uid in ipairs(stops) do
        local wp = self.byUid[uid]
        if wp then Unlink(self, wp, reason, true) end
    end
    DropRoute(self, route)
end

-- A record that moved (or was re-added in place) starts over: new
-- alternative choice, band state, arrival observation, not reached.
local function Restart(self, wp)
    wp.reached = nil
    self._alt[wp.uid] = nil
    self._bands[wp.uid] = nil
    self._born[wp.uid] = BornStamp(self)
    local a = self._arrival
    if a and a.uid == wp.uid then
        a.state, a.observed, a.armed, a.arrivedAt = "NAVIGATING", false, true, nil
    end
end

-- Pin from an Add with setArrow: a temporary waypoint never takes the arrow
-- from what the user chose, a non-temporary pin or a running route. A route
-- holds the arrow with NO pin (StartRoute lets it go), so the pin alone
-- does not say so: Adjutant's repair offer and an automatic group ping took
-- the arrow off a route stop before this rule (review: runtime).
local function PinFromAdd(self, wp)
    local cur = self.pinned and self.byUid[self.pinned]
    if wp.temporary then
        if cur and cur ~= wp and not cur.temporary then return false end
        local r = not cur and not self.suppressed and self.activeRoute and self.routes[self.activeRoute]
        if r and self.byUid[r.stops[r.index]] then return false end
    end
    local changed = self.pinned ~= wp.uid or self.suppressed or wp.reached
    self.pinned = wp.uid
    self.suppressed = false
    wp.reached = nil
    return changed and true or false
end

local function FindStandalone(self, rec)
    for _, uid in ipairs(self.order) do
        local wp = self.byUid[uid]
        if wp.routeId == nil and wp.kind ~= "corpse" and wp.kind ~= "unit" and wp.map
            and wp.title == rec.title and SamePos(wp, rec, TOLERANCE) then
            return wp
        end
    end
    return nil
end

local MOVE_FIELDS = {
    "map", "x", "y", "title", "note", "kind", "unit", "alternatives", "icon", "colour",
    "arrive", "clearOnArrive", "persistent", "temporary", "callbacks", "guideFor",
}

-- ---------------------------------------------------------------------------
-- Waypoints
-- ---------------------------------------------------------------------------
-- wp, nil, status ("added" | "moved" | "existing") or nil, reason.
-- spec: map, x, y (0..1), title, note, source, key, kind, unit, alternatives,
-- icon, colour, arrive, clearOnArrive, persistent, temporary, setArrow,
-- callbacks (TomTom-shaped: .distance[yards] = fn) and handle.
-- Identity, in order: the one corpse; (source, key) -> "moved", the spec
-- replaces the record's content; a unit follow by (unit, title); otherwise
-- the same place and title within S.TOLERANCE -> "existing", returned as it
-- is (TomTom parity: a duplicate's options are not applied) except that it
-- is promoted to persistent / non-temporary when this add asks for it, is no
-- longer "reached", and is pinned when setArrow says so.
function Store:Add(spec)
    if type(spec) ~= "table" then return nil, "no spec" end
    local rec, err = BuildRecord(spec, false)
    if not rec then return nil, err end

    local old, status
    if rec.kind == "corpse" then
        old = self:Corpse()
        status = old and "moved"
    end
    if not old and rec.key ~= nil then
        local uid = self.byKey[KeyOf(rec.source, rec.key)]
        old = uid and self.byUid[uid]
        status = old and "moved"
    end
    if not old and rec.kind == "unit" then
        for _, uid in ipairs(self.order) do
            local wp = self.byUid[uid]
            if wp.kind == "unit" and wp.routeId == nil and wp.unit == rec.unit and wp.title == rec.title then
                old, status = wp, "existing"
                break
            end
        end
    elseif not old and rec.kind ~= "corpse" then
        old = FindStandalone(self, rec)
        status = old and "existing"
    end

    if old and status == "moved" then
        -- (source, key) or the one corpse: the new spec replaces the old
        -- record's content, uid and created stamp kept
        if old.key ~= nil then
            local k = KeyOf(old.source, old.key)
            if self.byKey[k] == old.uid then self.byKey[k] = nil end
        end
        for _, f in ipairs(MOVE_FIELDS) do old[f] = rec[f] end
        old.source, old.key = rec.source, rec.key
        if old.key ~= nil then self.byKey[KeyOf(old.source, old.key)] = old.uid end
        Restart(self, old)
        if spec.setArrow then PinFromAdd(self, old) end
        Bump(self)
        return old, nil, "moved"
    elseif old then
        -- the same place again: hand back the existing record. A user re-add
        -- of a consumer's session-only mark makes it stay; asking again also
        -- means "I want to go there again".
        local changed = false
        if rec.persistent and not old.persistent then old.persistent = true changed = true end
        if not rec.temporary and old.temporary then old.temporary = false changed = true end
        if old.reached then old.reached = nil changed = true end
        if spec.setArrow and PinFromAdd(self, old) then changed = true end
        if changed then Bump(self) end
        return old, nil, "existing"
    end

    rec.uid = NewUid(self)
    rec.created = self.epoch()
    Insert(self, rec)
    if spec.setArrow then PinFromAdd(self, rec) end
    Bump(self)
    return rec, nil, "added"
end

function Store:Get(uid)
    return self.byUid[uid]
end

-- The one corpse record, if any
function Store:Corpse()
    for _, uid in ipairs(self.order) do
        local wp = self.byUid[uid]
        if wp.kind == "corpse" then return wp end
    end
    return nil
end

-- The standalone record a consumer owns under (source, key)
function Store:ByKey(source, key)
    key = NormKey(key)
    if key == nil then return nil end
    local uid = self.byKey[KeyOf(NormSource(source), key)]
    return uid and self.byUid[uid] or nil
end

-- true when something was removed. reason reaches onRemove.
function Store:Remove(uid, reason)
    local wp = self.byUid[uid]
    if not wp then return false end
    Unlink(self, wp, reason or "remove", false)
    Bump(self)
    return true
end

-- Standalone records of a source (and key), plus that source's routes (and
-- key) with their stops. Returns the number of records removed.
function Store:RemoveBy(source, key)
    if type(source) ~= "string" then return 0 end
    if key ~= nil then
        -- a key that cannot be a key matches nothing; never "the whole source"
        key = NormKey(key)
        if key == nil then return 0 end
    end
    local n = 0
    local doomed = {}
    for _, uid in ipairs(self.order) do
        local wp = self.byUid[uid]
        if wp.routeId == nil and wp.source == source and (key == nil or wp.key == key) then
            doomed[#doomed + 1] = wp
        end
    end
    for _, wp in ipairs(doomed) do
        Unlink(self, wp, "remove", false)
        n = n + 1
    end
    local routes = {}
    for _, id in ipairs(self.routeOrder) do
        local r = self.routes[id]
        if r.source == source and (key == nil or r.key == key) then routes[#routes + 1] = r end
    end
    for _, r in ipairs(routes) do
        n = n + #r.stops
        RemoveRouteInternal(self, r, "remove")
    end
    if n > 0 or #routes > 0 then Bump(self) end
    return n
end

-- filter = { source=, map=, routeId= (false: standalone only), kind=,
-- reached=, temporary= }; nil or {} matches every record.
local function Matches(wp, f)
    if not f then return true end
    if f.source ~= nil and wp.source ~= f.source then return false end
    if f.map ~= nil and wp.map ~= f.map then return false end
    if f.routeId ~= nil then
        if f.routeId == false then
            if wp.routeId ~= nil then return false end
        elseif wp.routeId ~= f.routeId then
            return false
        end
    end
    if f.kind ~= nil and wp.kind ~= f.kind then return false end
    if f.reached ~= nil and (wp.reached ~= nil) ~= (f.reached and true or false) then return false end
    if f.temporary ~= nil and wp.temporary ~= (f.temporary and true or false) then return false end
    return true
end

-- The live records in creation order. Read them; change them with Update.
function Store:List(filter)
    if type(filter) ~= "table" then filter = nil end
    local out = {}
    for _, uid in ipairs(self.order) do
        local wp = self.byUid[uid]
        if Matches(wp, filter) then out[#out + 1] = wp end
    end
    return out
end

function Store:Count(filter)
    return #self:List(filter)
end

-- Remove every match; a nil filter empties the store (routes, pin, active
-- route, the dismissed flag). Returns the number of records removed.
function Store:Clear(filter, reason)
    if type(filter) ~= "table" or next(filter) == nil then filter = nil end
    local doomed = self:List(filter)
    for _, wp in ipairs(doomed) do Unlink(self, wp, reason or "clear", false) end
    if not filter then
        -- every route lost its last stop above; this only sweeps strays
        local left = {}
        for _, r in pairs(self.routes) do left[#left + 1] = r end
        for _, r in ipairs(left) do DropRoute(self, r) end
        self.pinned, self.activeRoute, self.suppressed = nil, nil, false
    end
    if #doomed > 0 or not filter then Bump(self) end
    return #doomed
end

-- The first record (creation order, routes included) at map/x/y within
-- tolerance (default S.TOLERANCE) whose title equals title (nil matches nil
-- only; S.ANY matches any title).
function Store:Find(map, x, y, title, tolerance)
    if not (ValidMap(map) and IsNumber(x) and IsNumber(y)) then return nil end
    local tol = (IsNumber(tolerance) and tolerance >= 0) and tolerance or TOLERANCE
    if title ~= ANY then title = NormTitle(title) end
    local probe = { map = map, x = x, y = y }
    for _, uid in ipairs(self.order) do
        local wp = self.byUid[uid]
        if wp.map and (title == ANY or wp.title == title) and SamePos(wp, probe, tol) then
            return wp
        end
    end
    return nil
end

-- Rename, move, recolour. fields: title, note, icon, colour, arrive (false
-- clears any of these), map/x/y (validated together), alternatives (false
-- clears), clearOnArrive, persistent (standalone records only; a stop
-- follows its route), temporary. Identity (uid, source, key, kind) is fixed.
function Store:Update(uid, fields)
    local wp = self.byUid[uid]
    if not wp then return nil, "unknown" end
    if type(fields) ~= "table" then return nil, "no fields" end
    local changed, moved = false, false

    if fields.map ~= nil or fields.x ~= nil or fields.y ~= nil then
        local m = fields.map
        if m == nil then m = wp.map end
        local x = fields.x
        if x == nil then x = wp.x end
        local y = fields.y
        if y == nil then y = wp.y end
        local ok, err = S.ValidPosition(m, x, y)
        if not ok then return nil, err end
        if m ~= wp.map or x ~= wp.x or y ~= wp.y then
            wp.map, wp.x, wp.y = m, x, y
            if wp.alternatives then
                -- the new primary replaces the old one as candidate 1
                local rest = {}
                for i = 2, #wp.alternatives do rest[#rest + 1] = wp.alternatives[i] end
                wp.alternatives = NormAlternatives(rest, wp)
            end
            moved = true
        end
    end
    if fields.alternatives ~= nil then
        if fields.alternatives == false then
            wp.alternatives = nil
        else
            wp.alternatives = NormAlternatives(fields.alternatives, wp.map and wp or nil)
        end
        changed = true
        self._alt[uid] = nil
    end
    if fields.title ~= nil then
        local t = fields.title ~= false and NormTitle(fields.title) or nil
        if t ~= wp.title then wp.title = t changed = true end
    end
    for _, f in ipairs({ "note", "icon", "colour" }) do
        if fields[f] ~= nil then
            local v = fields[f] ~= false and NormString(fields[f]) or nil
            if v ~= wp[f] then wp[f] = v changed = true end
        end
    end
    if fields.arrive ~= nil then
        local v = fields.arrive
        if v == false then v = nil elseif not (IsNumber(v) and v > 0) then v = wp.arrive end
        if v ~= wp.arrive then wp.arrive = v changed = true end
    end
    if fields.clearOnArrive ~= nil then
        local v = fields.clearOnArrive and true or false
        if v ~= wp.clearOnArrive then wp.clearOnArrive = v changed = true end
    end
    if fields.persistent ~= nil and wp.routeId == nil then
        local v = fields.persistent and true or false
        if v ~= wp.persistent then wp.persistent = v changed = true end
    end
    if fields.temporary ~= nil then
        local v = fields.temporary and true or false
        if v ~= wp.temporary then wp.temporary = v changed = true end
    end
    if moved then Restart(self, wp) end
    if changed or moved then Bump(self) end
    return wp
end

-- ---------------------------------------------------------------------------
-- Positions, distances, the closest
-- ---------------------------------------------------------------------------
-- Where a record is right now, for the arrow: a unit's live position (its
-- last known one when the unit cannot be placed), the chosen alternative
-- (nearest on the player's landmass, with hysteresis), else the record.
-- Returns pos, alternativeIndex. Callers only read what comes back: a
-- unit's keyed {map=, x=, y=} is handed on as given, not copied (the
-- runtime's is one reused table a unit; a copy a call was 1.6 KB/s while
-- following someone on another landmass, and a fresh table missed the
-- runtime's world-position cache every frame: review-r2 orders).
local function PositionFor(self, wp, ctx, now)
    if wp.kind == "unit" then
        local fn = ctx and ctx.unitPosition
        local raw = type(fn) == "function" and SafeCall(fn, wp.unit) or nil
        if type(raw) == "table" and ValidMap(raw.map) and ValidCoord(raw.x) and ValidCoord(raw.y) then
            return raw
        end
        local p = NormPos(raw)
        if p then return p end
        if wp.map then return wp end
        return nil
    end
    local alts = wp.alternatives
    if not alts then return wp end
    local choice = self._alt[wp.uid]
    local player = ctx and ctx.player
    if not (player and player.map and ctx.distance) then
        local i = choice and choice.index or 1
        return alts[i] or alts[1], (alts[i] and i or 1)
    end
    now = Now(self, ctx, now)
    if Fresh(self, choice, now, self.version) and alts[choice.index]
        and SameLand(ctx, player.map, alts[choice.index].map) then
        return alts[choice.index], choice.index
    end
    local cur = choice and choice.index
    local bestI, bestD, curD
    for i, a in ipairs(alts) do
        if SameLand(ctx, player.map, a.map) then
            local d = Measure(ctx, player, a)
            if d then
                if i == cur then curD = d end
                if not bestD or d < bestD then bestI, bestD = i, d end
            end
        end
    end
    local index = (cur and alts[cur]) and cur or 1
    if bestI and bestI ~= index then
        if curD == nil or (bestD <= curD * SWITCH_RATIO and curD - bestD >= SWITCH_YARDS) then
            index = bestI
        end
    end
    self._alt[wp.uid] = { index = index, at = now, version = self.version }
    return alts[index], index
end

function Store:Position(wp, ctx)
    if type(wp) ~= "table" then wp = self.byUid[wp] end
    if not wp then return nil end
    return PositionFor(self, wp, ctx, nil)
end

-- The alternative index the arrow is using for a record (1 when none chosen)
function Store:ChosenAlternative(uid)
    local c = self._alt[uid]
    return c and c.index or 1
end

local function DistanceFor(self, wp, ctx, now)
    local player = ctx and ctx.player
    if not (player and player.map) then return nil end
    local pos = PositionFor(self, wp, ctx, now)
    if not pos or not SameLand(ctx, player.map, pos.map) then return nil end
    return Measure(ctx, player, pos)
end

-- Yards from the player, nil when it cannot be measured (other landmass,
-- no position)
function Store:Distance(wp, ctx)
    if type(wp) ~= "table" then wp = self.byUid[wp] end
    if not wp then return nil end
    return DistanceFor(self, wp, ctx, nil)
end

local function ClosestEligible(wp)
    return wp.routeId == nil and wp.kind ~= "corpse" and wp.kind ~= "unit" and not wp.reached
end

-- 3.1: what another addon asked for through the TomTom bridge
local function ThirdParty(wp)
    local src = wp.source
    return type(src) == "string" and src:sub(1, 7) == "TomTom:"
end

-- 3.1 scope and ownership (ctx.closestScope, ctx.closestMine): may this
-- record be the closest at all? The zone test reads the spot the arrow would
-- use (a nearest-of-N waypoint's chosen spawn).
local function InClosestScope(self, wp, ctx, now, anyOwner)
    if ctx.closestMine and not anyOwner and ThirdParty(wp) then return false end
    if ctx.closestScope == "ZONE" and type(ctx.sameZone) == "function" then
        local player = ctx.player
        local pos = PositionFor(self, wp, ctx, now)
        if not (pos and player and SafeCall(ctx.sameZone, player.map, pos.map)) then return false end
    end
    return true
end

-- One pass: the nearest non-temporary and nearest temporary candidates, and
-- the distance of `want` when it is a candidate.
local function ScanClosest(self, ctx, now, want, anyOwner)
    local player = ctx.player
    local b1, d1, b2, d2, wantD
    for _, uid in ipairs(self.order) do
        local wp = self.byUid[uid]
        if ClosestEligible(wp) and InClosestScope(self, wp, ctx, now, anyOwner) then
            local d = DistanceFor(self, wp, ctx, now)
            if d then
                if wp == want then wantD = d end
                if wp.temporary then
                    if not d2 or d < d2 then b2, d2 = wp, d end
                elseif not d1 or d < d1 then
                    b1, d1 = wp, d
                end
            end
        end
    end
    if b1 then return b1, d1, wantD end
    return b2, d2, wantD
end

-- No hysteresis, no cache: what /cway and TomTom:GetClosestWaypoint want.
-- Returns wp, yards. anyOwner: leave ctx.closestMine out of it (the TomTom
-- bridge asking for its callers' closest).
function Store:Closest(ctx, anyOwner)
    if not (ctx and ctx.player and ctx.player.map) then return nil end
    local wp, d = ScanClosest(self, ctx, Now(self, ctx, nil), nil, anyOwner)
    return wp, d
end

local function StickyClosest(self, ctx, now)
    local player = ctx.player
    if not (player and player.map and ctx.distance) then return nil end
    local c = self._closest
    local cur = c and c.uid and self.byUid[c.uid]
    if cur and not (ClosestEligible(cur) and InClosestScope(self, cur, ctx, now)) then cur = nil end
    if c and Fresh(self, c, now, self.version) then
        if not c.uid then return nil end
        if cur then
            local pos = PositionFor(self, cur, ctx, now)
            if pos and SameLand(ctx, player.map, pos.map) then return cur end
        end
    end
    local best, bestD, curD = ScanClosest(self, ctx, now, cur)
    local pick = best
    if cur and curD and best and best ~= cur then
        local curTier = cur.temporary and 2 or 1
        local bestTier = best.temporary and 2 or 1
        if bestTier >= curTier and not (bestD <= curD * SWITCH_RATIO and curD - bestD >= SWITCH_YARDS) then
            pick = cur
        end
    end
    self._closest = { uid = pick and pick.uid or nil, at = now, version = self.version }
    return pick
end

-- ---------------------------------------------------------------------------
-- Targeting
-- ---------------------------------------------------------------------------
local function TargetOf(self, ctx, now)
    ctx = ctx or EMPTY
    if ctx.ghost and ctx.corpseArrow ~= false then
        local c = self:Corpse()
        if c then return c, "CORPSE" end
    end
    local p = self.pinned and self.byUid[self.pinned]
    if p then return p, "PINNED" end
    if self.suppressed then return nil end
    local r = self.activeRoute and self.routes[self.activeRoute]
    if r then
        local wp = self.byUid[r.stops[r.index]]
        if wp then return wp, "ROUTE" end
    end
    if ctx.autoClosest ~= false then
        local wp = StickyClosest(self, ctx, Now(self, ctx, now))
        if wp then return wp, "CLOSEST" end
    end
    return nil
end

-- wp, why ("CORPSE" | "PINNED" | "ROUTE" | "CLOSEST") or nil
function Store:ActiveTarget(ctx)
    return TargetOf(self, ctx, nil)
end

local function StartRoute(self, route)
    self.activeRoute = route.id
    self.pinned = nil
    self.suppressed = false
end

-- The user chose this one. A route stop jumps its route there instead.
function Store:SetPinned(uid)
    local wp = self.byUid[uid]
    if not wp then return false, "unknown" end
    wp.reached = nil
    local route = wp.routeId and self.routes[wp.routeId]
    if route then
        route.index = IndexOf(route.stops, uid) or route.index
        StartRoute(self, route)
        Bump(self)
        return true
    end
    if self.pinned ~= uid or self.suppressed then
        self.pinned = uid
        self.suppressed = false
        Bump(self)
    end
    return true
end

-- "Mark arrived" on a waypoint that does not clear (Keep My Own Marks, a
-- shim waypoint with cleardistance 0): what its arrival would have done.
-- Stamped reached, so the closest rule leaves it out, and the pin let go.
-- Letting go of the pin alone handed it straight back as the closest.
function Store:MarkReached(uid)
    local wp = self.byUid[uid]
    if not wp then return false end
    wp.reached = self.epoch()
    if self.pinned == uid then self.pinned = nil end
    if self._closest and self._closest.uid == uid then self._closest = nil end
    Bump(self)
    return true
end

-- A standalone record without a key handed to another owner. The runtime
-- does this when the user re-adds a spot (a /way line, an accepted share)
-- that a TomTom-shim caller had put there: the caller removes its own by
-- handle, and it must not take the user's with it. A keyed record never
-- changes hands: (source, key) is how a consumer finds its own again.
function Store:Claim(uid, source)
    local wp = self.byUid[uid]
    source = NormSource(source)
    if not wp or wp.routeId ~= nil or wp.key ~= nil or wp.source == source then return false end
    wp.source = source
    Bump(self)
    return true
end

-- A unit follow re-pointed at the member's new unit token (3.1: a roster
-- change renumbers party1..4 and raid1..40; the runtime finds the member
-- again by GUID). Identity stays: the uid, the (source, key), the pin.
function Store:Retarget(uid, unit)
    local wp = self.byUid[uid]
    unit = NormString(unit)
    if not wp or wp.kind ~= "unit" or not unit then return false end
    if wp.unit == unit then return true end
    wp.unit = unit
    Bump(self)
    return true
end

-- suppress: the user dismissed the arrow (see the header)
function Store:ClearPinned(suppress)
    local changed = self.pinned ~= nil or (suppress and not self.suppressed)
    self.pinned = nil
    if suppress then self.suppressed = true end
    if changed then Bump(self) end
    return true
end

function Store:Pinned()
    return self.pinned and self.byUid[self.pinned] or nil
end

function Store:Suppressed()
    return self.suppressed
end

-- ---------------------------------------------------------------------------
-- Routes
-- ---------------------------------------------------------------------------
function Store:GetRoute(id)
    return self.routes[id]
end

function Store:Routes()
    local out = {}
    for i, id in ipairs(self.routeOrder) do out[i] = self.routes[id] end
    return out
end

function Store:ActiveRoute()
    return self.activeRoute and self.routes[self.activeRoute] or nil
end

function Store:FindRoute(source, key)
    key = NormKey(key)
    if key == nil then return nil end
    source = NormSource(source)
    for _, id in ipairs(self.routeOrder) do
        local r = self.routes[id]
        if r.source == source and r.key == key then return r end
    end
    return nil
end

local function RouteArg(self, id)
    if id ~= nil then return self.routes[id] end
    return self.activeRoute and self.routes[self.activeRoute] or nil
end

-- Re-order route.stops[route.index..] (see the header). geo carries distance
-- and sameLandmass (a ctx does); player is {map, x, y} or nil.
local function Optimize(self, route, player, geo)
    if not (geo and type(geo.distance) == "function") then return false end
    local first = route.index
    local rest = {}
    for i = first, #route.stops do
        local wp = self.byUid[route.stops[i]]
        if wp and wp.map then rest[#rest + 1] = wp end
    end
    if #rest < 1 then return false end
    -- group by landmass, in order of first appearance
    local groups = {}
    for _, wp in ipairs(rest) do
        local g
        for _, cand in ipairs(groups) do
            if SameLand(geo, cand.map, wp.map) then g = cand break end
        end
        if not g then
            g = { map = wp.map, items = {} }
            groups[#groups + 1] = g
        end
        g.items[#g.items + 1] = wp
    end
    local playerOk = player and player.map and NormPos(player) and true
    if playerOk then
        for i, g in ipairs(groups) do
            if SameLand(geo, player.map, g.map) then
                if i > 1 then tremove(groups, i) tinsert(groups, 1, g) end
                g.fromPlayer = true
                break
            end
        end
    end
    local ordered = {}
    for _, g in ipairs(groups) do
        local left = g.items
        local cur
        if g.fromPlayer then
            cur = player
        else
            cur = tremove(left, 1)
            ordered[#ordered + 1] = cur
        end
        while #left > 0 do
            local bestI, bestD = 1, huge
            for i, wp in ipairs(left) do
                local d = Measure(geo, cur, wp) or huge
                if d < bestD then bestI, bestD = i, d end
            end
            cur = tremove(left, bestI)
            ordered[#ordered + 1] = cur
        end
    end
    for i, wp in ipairs(ordered) do route.stops[first + i - 1] = wp.uid end
    Reindex(self, route)
    return true
end

-- route, nil, skipped or nil, reason. spec: title, source, key, mode
-- ("ORDERED" | "NEAREST"), loop, persistent, start (default true: the route
-- takes the arrow), stops = { waypoint spec, ... }. ctx (optional) orders a
-- NEAREST route from the player. Stops are always new records (kind
-- "stop"); they never merge with standalone waypoints.
function Store:AddRoute(spec, ctx)
    if type(spec) ~= "table" or type(spec.stops) ~= "table" then return nil, "no stops" end
    local source = NormSource(spec.source)
    local key = NormKey(spec.key)
    local persistent = spec.persistent ~= false
    local recs, skipped = {}, 0
    for _, st in ipairs(spec.stops) do
        local rec = type(st) == "table" and BuildRecord(st, true) or nil
        if rec then
            if st.source == nil then rec.source = source end
            rec.persistent = persistent
            recs[#recs + 1] = rec
        else
            skipped = skipped + 1
        end
    end
    if #recs == 0 then return nil, "no valid stops" end

    local id, wasActive
    local old = key ~= nil and self:FindRoute(source, key) or nil
    if old then
        id, wasActive = old.id, self.activeRoute == old.id
        RemoveRouteInternal(self, old, "replace")
    else
        id = "r" .. self.nextRoute
        self.nextRoute = self.nextRoute + 1
    end
    local route = {
        id = id, title = NormTitle(spec.title), source = source, key = key,
        mode = MODES[type(spec.mode) == "string" and spec.mode:upper() or ""] and spec.mode:upper() or "ORDERED",
        loop = spec.loop == true, index = 1, stops = {}, persistent = persistent, created = self.epoch(),
    }
    self.routes[id] = route
    self.routeOrder[#self.routeOrder + 1] = id
    for i, rec in ipairs(recs) do
        rec.uid = NewUid(self)
        rec.created = route.created
        rec.routeId = id
        rec.routeIndex = i
        Insert(self, rec)
        route.stops[i] = rec.uid
    end
    if route.mode == "NEAREST" then
        Optimize(self, route, ctx and ctx.player, ctx or nil)
    end
    if spec.start ~= false then
        StartRoute(self, route)
    elseif wasActive then
        self.activeRoute = id
    end
    Bump(self)
    return route, nil, skipped
end

-- Append a stop to a route (a NEAREST route re-orders what is ahead).
function Store:AddStop(routeId, spec, ctx)
    local route = self.routes[routeId]
    if not route then return nil, "unknown route" end
    if type(spec) ~= "table" then return nil, "no spec" end
    local rec, err = BuildRecord(spec, true)
    if not rec then return nil, err end
    if spec.source == nil then rec.source = route.source end
    rec.persistent = route.persistent
    rec.uid = NewUid(self)
    rec.created = self.epoch()
    rec.routeId = route.id
    Insert(self, rec)
    route.stops[#route.stops + 1] = rec.uid
    rec.routeIndex = #route.stops
    if route.mode == "NEAREST" then
        Optimize(self, route, ctx and ctx.player, ctx or nil)
    end
    Bump(self)
    return rec
end

function Store:RemoveRoute(id, reason)
    local route = self.routes[id]
    if not route then return false end
    RemoveRouteInternal(self, route, reason or "remove")
    Bump(self)
    return true
end

-- (Re)start a route where it stands; a NEAREST route re-orders from ctx.player.
function Store:RouteStart(id, ctx)
    local route = RouteArg(self, id)
    if not route then return false, "no route" end
    if route.mode == "NEAREST" then
        Optimize(self, route, ctx and ctx.player, ctx or nil)
    end
    StartRoute(self, route)
    Bump(self)
    return true
end

local function ClearReached(self, route)
    for _, uid in ipairs(route.stops) do
        local wp = self.byUid[uid]
        if wp then wp.reached = nil end
    end
end

-- Skip ahead (the arrow menu's Next / Skip). Stops at the last stop of an
-- open route rather than finishing it: finishing is what arriving is for.
-- Returns the new current stop or nil, reason.
function Store:RouteNext(id)
    local route = RouteArg(self, id)
    if not route then return nil, "no route" end
    if route.index < #route.stops then
        route.index = route.index + 1
    elseif route.loop then
        route.index = 1
        ClearReached(self, route)
    else
        return nil, "last stop"
    end
    StartRoute(self, route)
    Bump(self)
    return self.byUid[route.stops[route.index]]
end

function Store:RoutePrev(id)
    local route = RouteArg(self, id)
    if not route then return nil, "no route" end
    if route.index > 1 then
        route.index = route.index - 1
    elseif route.loop then
        route.index = #route.stops
    else
        return nil, "first stop"
    end
    local wp = self.byUid[route.stops[route.index]]
    if wp then wp.reached = nil end
    StartRoute(self, route)
    Bump(self)
    return wp
end

-- Reverse the stop order; the current stop stays current.
function Store:RouteReverse(id)
    local route = RouteArg(self, id)
    if not route then return false, "no route" end
    local n = #route.stops
    for i = 1, floor(n / 2) do
        route.stops[i], route.stops[n - i + 1] = route.stops[n - i + 1], route.stops[i]
    end
    route.index = n - route.index + 1
    Reindex(self, route)
    Bump(self)
    return true
end

-- "Optimise order" on any route: playerPos {map, x, y} or nil; geo carries
-- distance (+ sameLandmass). id defaults to the active route.
function Store:RouteOptimize(playerPos, geo, id)
    local route = RouteArg(self, id)
    if not route then return false, "no route" end
    if not Optimize(self, route, playerPos, geo) then return false, "no distance" end
    Bump(self)
    return true
end

-- ---------------------------------------------------------------------------
-- Arrival and distance bands
-- ---------------------------------------------------------------------------
-- Tick's events. The array is made on a tick's FIRST event, so the ticks
-- that say nothing (nearly all of them, ten a second for as long as there
-- is a target) allocate nothing and hand back one shared, read-only empty
-- list. Only the Tick call tree emits (FinishArrival runs from FinishDue and
-- Step alone), and Tick takes the list off the store before returning it.
local NO_EVENTS = setmetatable({}, {
    __newindex = function() error("Store: Tick's empty event list is shared and read only", 2) end,
})
S.NO_EVENTS = NO_EVENTS

local function Emit(self, e)
    local list = self._ev
    if not list then
        list = {}
        self._ev = list
    end
    list[#list + 1] = e
end

-- DONE for one record: clear or mark reached; a route stop advances its
-- route (or finishes it).
local function FinishArrival(self, uid)
    local wp = self.byUid[uid]
    if not wp then return end
    local route = wp.routeId and self.routes[wp.routeId]
    if route then
        local pos = IndexOf(route.stops, uid)
        local clear = wp.clearOnArrive and not route.loop
        Emit(self, { type = "DONE", uid = uid, title = wp.title, routeId = route.id, cleared = clear })
        if clear then
            if pos then
                tremove(route.stops, pos)
                if pos < route.index then route.index = route.index - 1 end
            end
            Unlink(self, wp, "arrived", true)
        else
            wp.reached = self.epoch()
            if pos and pos == route.index then route.index = route.index + 1 end
        end
        if route.index > #route.stops then
            if route.loop and #route.stops > 0 then
                route.index = 1
                ClearReached(self, route)
            else
                Emit(self, {
                    type = "ROUTE_COMPLETE", routeId = route.id, title = route.title,
                    source = route.source, key = route.key,
                })
                RemoveRouteInternal(self, route, "complete")
                Bump(self)
                return
            end
        end
        Reindex(self, route)
        Emit(self, {
            type = "ADVANCE", routeId = route.id, index = route.index, uid = route.stops[route.index],
        })
    else
        local clear = wp.clearOnArrive
        Emit(self, { type = "DONE", uid = uid, title = wp.title, cleared = clear })
        if clear then
            Unlink(self, wp, "arrived", false)
        else
            wp.reached = self.epoch()
            if self.pinned == uid then self.pinned = nil end
        end
    end
    Bump(self)
end

local function FinishDue(self, now)
    local i = 1
    while i <= #self._finishing do
        local f = self._finishing[i]
        if now - f.arrivedAt >= self.arriveHold then
            tremove(self._finishing, i)
            FinishArrival(self, f.uid)
        else
            i = i + 1
        end
    end
end

local function FireBand(self, wp, range, d, last)
    local fn = wp.callbacks.distance[range]
    if type(fn) ~= "function" then return end
    local handle = wp.callbacks.handle
    if handle == nil then handle = wp.uid end
    local ok, err = pcall(fn, "distance", handle, range, d, last)
    if not ok then
        Emit(self, { type = "CALLBACK_ERROR", uid = wp.uid, range = range, err = tostring(err) })
    end
end

local function DispatchBands(self, ctx, target, targetD, now)
    local list
    for _, uid in ipairs(self.order) do
        local wp = self.byUid[uid]
        if wp.callbacks then
            list = list or {}
            list[#list + 1] = wp
        end
    end
    if not list then return end
    for _, wp in ipairs(list) do
        if self.byUid[wp.uid] == wp and wp.callbacks then
            local d
            if wp == target and IsNumber(targetD) then d = targetD else d = DistanceFor(self, wp, ctx, now) end
            if d then
                local bands = wp.callbacks.bands
                local nb = #bands + 1
                for j = 1, #bands do
                    if d <= bands[j] then nb = j break end
                end
                local st = self._bands[wp.uid]
                if not st then
                    st = { band = nb }
                    self._bands[wp.uid] = st
                    if nb <= #bands then FireBand(self, wp, bands[nb], d, nil) end
                elseif nb < st.band then
                    local from, last = st.band, st.last
                    st.band = nb
                    for j = from - 1, nb, -1 do
                        if self.byUid[wp.uid] ~= wp or self._bands[wp.uid] ~= st then break end
                        FireBand(self, wp, bands[j], d, last)
                    end
                else
                    st.band = nb
                end
                st.last = d
            end
        end
    end
end

local function NewArrival(wp)
    return { uid = wp.uid, state = "NAVIGATING", observed = false, armed = true }
end

-- Bring the arrival record in line with the current target, emitting TARGET
-- when the arrow changes hands. An ARRIVED record that loses the arrow is
-- parked so its DONE still happens.
local function SyncTarget(self, ctx, now)
    local wp, why = TargetOf(self, ctx, now)
    local a = self._arrival
    local uid = wp and wp.uid
    if a and a.uid == uid and a.state ~= "DONE" then return wp, a end
    if a and a.uid == uid and a.state == "DONE" then
        -- the same record kept the arrow after its DONE (a kept corpse, a
        -- one-stop loop): it is here, so it must be left before it can
        -- arrive again
        a = { uid = uid, state = "NEAR", observed = true, armed = false }
        self._arrival = a
        Emit(self, { type = "NEAR", uid = uid })
        return wp, a
    end
    -- nobody had the arrow and nobody has it now: nothing changed hands, so
    -- an idle tick says nothing (the runtime would otherwise hear "no
    -- target" ten times a second)
    if a == nil and uid == nil then return nil, nil end
    if a and a.state == "ARRIVED" and self.byUid[a.uid] then
        self._finishing[#self._finishing + 1] = { uid = a.uid, arrivedAt = a.arrivedAt }
    end
    Emit(self, { type = "TARGET", uid = uid, previous = a and a.uid or nil, why = why })
    a = wp and NewArrival(wp) or nil
    if a then
        -- the arrow came back to a record still finishing its hold: resume
        -- the hold (one ARRIVED, one sound, one DONE at the original time)
        for j = #self._finishing, 1, -1 do
            local f = self._finishing[j]
            if f.uid == uid then
                tremove(self._finishing, j)
                a.state, a.observed, a.arrivedAt = "ARRIVED", true, f.arrivedAt
            end
        end
    end
    self._arrival = a
    return wp, a
end

local function SetState(self, a, state)
    if a.state ~= state then
        a.state = state
        Emit(self, { type = state, uid = a.uid })
    end
end

local function Step(self, a, wp, d, ctx, now)
    if a.state == "ARRIVED" then
        if now - a.arrivedAt >= self.arriveHold then
            a.state = "DONE"
            FinishArrival(self, wp.uid)
        end
        return
    end
    if d == nil then return end
    local r = wp.arrive or (IsNumber(ctx.arriveYards) and ctx.arriveYards > 0 and ctx.arriveYards) or DEFAULT_ARRIVE
    if not a.observed then
        a.observed = true
        local born = self._born[wp.uid]
        a.armed = not (d <= r and born ~= nil and born >= self._ticks)
    end
    if not a.armed then
        if d > r then
            a.armed = true
        else
            SetState(self, a, ctx.onTaxi and "NAVIGATING" or "NEAR")
            return
        end
    end
    if ctx.onTaxi then
        SetState(self, a, "NAVIGATING")
        return
    end
    if d <= r then
        a.state = "ARRIVED"
        a.arrivedAt = now
        Emit(self, { type = "ARRIVED", uid = wp.uid, title = wp.title, routeId = wp.routeId })
        return
    end
    if a.state == "NEAR" then
        if d > r * NEAR_EXIT_FACTOR then SetState(self, a, "NAVIGATING") end
    elseif d <= r * NEAR_FACTOR then
        SetState(self, a, "NEAR")
    end
end

-- One tick of the arrival machine and the distance bands. distance: yards
-- to the target the runtime got from ActiveTarget this tick (nil: measure
-- through ctx, or not measurable). Returns an array of events:
--   TARGET {uid|nil, previous, why}   NEAR {uid}   NAVIGATING {uid}
--   ARRIVED {uid, title, routeId}     DONE {uid, title, routeId, cleared}
--   ADVANCE {routeId, index, uid}     ROUTE_COMPLETE {routeId, title, source, key}
--   CALLBACK_ERROR {uid, range, err}
-- A tick with no event returns S.NO_EVENTS (shared, read only: never append
-- to what Tick returns).
function Store:Tick(ctx, distance, now)
    ctx = ctx or EMPTY
    now = Now(self, ctx, now)
    self._ev = nil
    local v0 = self.version
    self._inTick = true
    local t0 = TargetOf(self, ctx, now)
    FinishDue(self, now)
    DispatchBands(self, ctx, t0, self.version == v0 and distance or nil, now)

    local wp, a = SyncTarget(self, ctx, now)
    if wp then
        local d = distance
        if self.version ~= v0 or wp ~= t0 or not (IsNumber(d) and d >= 0) then
            d = DistanceFor(self, wp, ctx, now)
        end
        Step(self, a, wp, d, ctx, now)
        if a.state == "DONE" then SyncTarget(self, ctx, now) end
    end
    self._inTick = false
    self._ticks = self._ticks + 1
    local events = self._ev or NO_EVENTS
    self._ev = nil
    return events
end

-- The arrival record of the current target: { uid, state, armed, arrivedAt }
-- (a copy; ArrivalState is the allocation-free read the 10 Hz pass uses)
function Store:State()
    local a = self._arrival
    if not a then return nil end
    return { uid = a.uid, state = a.state, armed = a.armed, arrivedAt = a.arrivedAt }
end

-- uid, state of the current target's arrival record, or nil
function Store:ArrivalState()
    local a = self._arrival
    if not a then return nil end
    return a.uid, a.state
end

-- Whether the runtime's driver must keep ticking (old D17: it never slept)
function Store:NeedsTick(ctx)
    if #self._finishing > 0 then return true end
    if self._arrival and self._arrival.state == "ARRIVED" then return true end
    for _, uid in ipairs(self.order) do
        if self.byUid[uid].callbacks then return true end
    end
    return TargetOf(self, ctx, nil) ~= nil
end

-- ---------------------------------------------------------------------------
-- Saved variables
-- ---------------------------------------------------------------------------
-- A plain table for CommanderOrdersChar.Store: session-only records (and
-- non-persistent routes) are left out, callbacks never go in, the counters
-- always do.
-- 3.1 (SPEC D5): the record the arrow is pinned to and the active route
-- are kept even when session-only, so a Go pressed before a /reload still
-- points after it. They come back still session-only: the next save keeps
-- them only while they hold the arrow. A unit follow is never kept this way
-- (a unit token means another member after a relog), nor a temporary offer
-- (a group ping, a battleground node, a repair offer: the moment is gone).
local function KeptRoute(self, route)
    return route.persistent or route.id == self.activeRoute
end

function Store:Serialize()
    local out = {
        Schema = SCHEMA, NextUid = self.nextUid, NextRoute = self.nextRoute,
        Waypoints = {}, Routes = {},
    }
    local kept = {}
    for _, uid in ipairs(self.order) do
        local wp = self.byUid[uid]
        local route = wp.routeId and self.routes[wp.routeId]
        local keep
        if route then
            keep = KeptRoute(self, route)
        else
            keep = wp.persistent ~= false or (uid == self.pinned and wp.kind ~= "unit" and not wp.temporary)
        end
        if keep then
            out.Waypoints[#out.Waypoints + 1] = PlainRecord(wp, false)
            kept[uid] = true
        end
    end
    -- A pinned "Guide me" hop keeps the record it leads to, session-only or
    -- not (the same two exclusions; a route stop goes with its route), so
    -- the hand-back after the crossing still has somewhere to point
    local hop = self.pinned and kept[self.pinned] and self.byUid[self.pinned]
    local target = hop and hop.guideFor and self.byUid[hop.guideFor]
    if target and not kept[target.uid] and not target.routeId and target.kind ~= "unit"
        and not target.temporary then
        out.Waypoints[#out.Waypoints + 1] = PlainRecord(target, false)
        kept[target.uid] = true
    end
    for _, id in ipairs(self.routeOrder) do
        local r = self.routes[id]
        if KeptRoute(self, r) then
            local stops, before = {}, 0
            for i, uid in ipairs(r.stops) do
                if kept[uid] then
                    stops[#stops + 1] = uid
                    if i < r.index then before = before + 1 end
                end
            end
            local index = before + 1
            if index > #stops then index = #stops end
            if #stops > 0 then
                out.Routes[#out.Routes + 1] = {
                    id = r.id, title = r.title, source = r.source,
                    key = (type(r.key) == "string" or type(r.key) == "number") and r.key or nil,
                    mode = r.mode, loop = r.loop, index = index, stops = stops,
                    persistent = r.persistent and true or false,
                    created = IsNumber(r.created) and r.created or nil,
                }
            end
        end
    end
    if self.pinned and kept[self.pinned] then out.Pinned = self.pinned end
    if self.activeRoute and self.routes[self.activeRoute] then
        out.ActiveRoute = self.activeRoute
    end
    if self.suppressed then out.Suppressed = true end
    return out
end

-- One saved record back into a live one, or nil when it is unusable.
local function RestoreRecord(t)
    if type(t) ~= "table" or not SeqOf(t.uid, "w") then return nil end
    local rec = BuildRecord(t, t.kind == "stop")
    if not rec then return nil end
    rec.uid = t.uid
    rec.created = IsNumber(t.created) and t.created or nil
    rec.reached = IsNumber(t.reached) and t.reached or nil
    rec.routeId = SeqOf(t.routeId, "r") and t.routeId or nil
    rec.callbacks = nil
    return rec
end

-- A store from Serialize's output. Tolerant: garbage in, a smaller store
-- out, never an error. Newer schemas load field by field (every record is
-- re-validated), so a downgrade keeps what it understands.
function S.Load(plain, clock, epoch)
    local self = S.New(clock, epoch)
    if type(plain) ~= "table" then return self end
    local maxW, maxR = 0, 0
    local recs, seen = {}, {}
    local corpse = false
    for _, t in ipairs(type(plain.Waypoints) == "table" and plain.Waypoints or EMPTY) do
        local rec = RestoreRecord(t)
        if rec and not seen[rec.uid] and not (rec.kind == "corpse" and corpse) then
            seen[rec.uid] = rec
            recs[#recs + 1] = rec
            if rec.kind == "corpse" then corpse = true end
            local n = SeqOf(rec.uid, "w")
            if n > maxW then maxW = n end
        end
    end
    local claimed = {}
    for _, t in ipairs(type(plain.Routes) == "table" and plain.Routes or EMPTY) do
        local n = type(t) == "table" and SeqOf(t.id, "r")
        if n and not self.routes[t.id] then
            if n > maxR then maxR = n end
            local stops, before = {}, 0
            local want = IsNumber(t.index) and t.index or 1
            for i, uid in ipairs(type(t.stops) == "table" and t.stops or EMPTY) do
                local rec = seen[uid]
                if rec and not claimed[uid] and rec.routeId == t.id then
                    claimed[uid] = true
                    stops[#stops + 1] = uid
                    if i < want then before = before + 1 end
                end
            end
            local index = before + 1
            if #stops > 0 then
                local route = {
                    id = t.id, title = NormTitle(t.title), source = NormSource(t.source), key = NormKey(t.key),
                    mode = MODES[t.mode] and t.mode or "ORDERED", loop = t.loop == true,
                    index = index, stops = stops, persistent = t.persistent ~= false,
                    created = IsNumber(t.created) and t.created or nil,
                }
                self.routes[t.id] = route
                self.routeOrder[#self.routeOrder + 1] = t.id
            end
        end
    end
    local keys = {}
    for _, rec in ipairs(recs) do
        if not claimed[rec.uid] then
            rec.routeId, rec.routeIndex = nil, nil
            if rec.kind == "stop" then rec.kind = "point" end
        else
            rec.kind = "stop"
        end
        local k = rec.key ~= nil and rec.routeId == nil and KeyOf(rec.source, rec.key)
        if not (k and keys[k]) then
            if k then keys[k] = true end
            Insert(self, rec)
        end
    end
    for _, id in ipairs(self.routeOrder) do
        local route = self.routes[id]
        for i = #route.stops, 1, -1 do
            if not self.byUid[route.stops[i]] then tremove(route.stops, i) end
        end
        if route.index > #route.stops then route.index = #route.stops end
        Reindex(self, route)
    end
    for i = #self.routeOrder, 1, -1 do
        local route = self.routes[self.routeOrder[i]]
        if #route.stops == 0 then DropRoute(self, route) end
    end
    self.nextUid = maxW + 1
    if IsNumber(plain.NextUid) and plain.NextUid > self.nextUid then self.nextUid = floor(plain.NextUid) end
    self.nextRoute = maxR + 1
    if IsNumber(plain.NextRoute) and plain.NextRoute > self.nextRoute then self.nextRoute = floor(plain.NextRoute) end
    local p = self.byUid[plain.Pinned]
    if p and not p.routeId then self.pinned = p.uid end
    if type(plain.ActiveRoute) == "string" and self.routes[plain.ActiveRoute] then
        self.activeRoute = plain.ActiveRoute
    end
    self.suppressed = plain.Suppressed == true
    self.version = 1
    return self
end
