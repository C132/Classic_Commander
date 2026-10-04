-- Commander Orders: pins on the minimap and the world map, the map click,
-- and the world-map coordinates.
--
-- The arrow says where ONE waypoint is. This file shows all of them: a pin
-- on the minimap for every waypoint on the landmass the player stands on
-- (TomTom showed only the ones in the current zone), pins on the world map
-- for the map being looked at and projected onto the continent and Azeroth
-- above it, numbered badges and connecting lines for a route, a
-- modifier+right-click on the map that drops a waypoint, and the player's and
-- the cursor's coordinates for the map on screen. Nothing here decides
-- anything about the waypoints themselves: the Store (through the runtime's
-- CommanderOrders.R surface) says what exists and where the arrow points, Geo
-- does every sum, and every change goes back through the public API
-- (CommanderOrders.Add / SetArrow / Update / Remove), so the arrow, the
-- manager and these pins can never disagree.
--
-- ---------------------------------------------------------------------------
-- The traps, each one paid for by somebody already
-- ---------------------------------------------------------------------------
-- * MINIMAP PINS HAVE NO NAME. Commander_Minimap's tidy fades every Minimap
--   child whose name looks like a minimap button (*MinimapButton*,
--   LibDBIcon*, *MinimapIcon*, *MinimapFrame*; critic 2.9). A pin called
--   CommanderOrdersMinimapIcon1 would vanish with the addon buttons. An
--   unnamed frame is never collected (its name is nil), so every pin, and the
--   driver frame that moves them, is created without one.
-- * MINIMAP GEOMETRY. There is no radius API on 2.5.6, so the radius is the
--   game's per-zoom diameter table (Geo.MINIMAP_DIAMETERS) halved; which half
--   of the table (indoors or out) comes from comparing Minimap:GetZoom() with
--   the minimapZoom / minimapInsideZoom CVars, IsIndoors() breaking a tie
--   (Geo.MinimapIndoors). Minimap:SetZoom is never nudged to find out, as
--   HereBeDragons does: Questie and RXP already nudge it in this session.
--   The shape is the ecosystem's GetMinimapShape() (Commander_Minimap
--   defines it as SQUARE while its square mask is on), else ROUND; a square
--   map clamps pins to its square rim, so the corners show what the mask
--   shows. The rotateMinimap CVar turns the picture with the player.
--   Commander_Minimap scales the Minimap (1.37); children inherit the scale,
--   so pixel offsets are in the Minimap's own units, never screen pixels.
-- * LAYERING. Commander_Radar's overlay is a LOW strata child of Minimap
--   one level above it; pins sit three levels above whichever is higher, so
--   radar blips never cover a waypoint.
-- * THE PER-FRAME COST. Pins move every frame while they are visible, and
--   only then: the driver is a child of the Minimap (so it stops when the
--   minimap is hidden) and is hidden itself whenever no pin is on the
--   landmass. Which waypoints get a pin is decided once a second and on
--   every change; per frame there is only a subtraction, Geo.MinimapPlace and
--   a SetPoint when the pin actually moved.
-- * A PORTAL INSIDE 530. Silvermoon to Shattrath, or Eversong to Hellfire,
--   keeps world instance 530, so "the instance changed" does not catch the
--   loading screen, and for up to a second the Quel'Thalas pins would be
--   placed against Outland coordinates (riding the rim, pointing nowhere).
--   A jump no mount or taxi makes between two frames (TELEPORT_YARDS) counts
--   as a loading screen too and rebuilds the pins on the spot.
-- * THE WORLD-MAP POOL (QuestLog 1.4.0's recipe, suite.md 7). 2.5.6's
--   CreateFramePool is the SECURE pool, a proxy that ignores writes to its
--   creation and reset functions and hands out bare frames: no mixin, no
--   OnLoad, and Blizzard's canvas code then errors every frame the map is
--   open. CreateUnsecuredRegionPoolInstance (Pools.lua) takes our functions;
--   CreateFramePool with a postCreate is the fallback only. The ResetPin is
--   also run on NEW pins (Pools.lua calls reset on creation), so it must
--   tolerate a fresh one.
-- * CLICKABLE PINS. Blizzard's AcquirePin wires the mouse of a NEW pin from
--   what it can already do: IsMouseClickEnabled gets OnMouseUp ->
--   pin:OnMouseUp then pin:OnClick, and OnMouseDown; IsMouseMotionEnabled gets
--   OnEnter / OnLeave -> OnMouseEnter / OnMouseLeave, after ASSERTING that the
--   pin has no OnEnter yet (Blizzard_MapCanvas.lua:148-197). So the pin is
--   made click- and motion-enabled in CreatePin and never given an OnEnter of
--   its own; the mixin's methods are the handlers.
-- * A REDRAW RELEASES EVERY PIN, the one being dragged and the one being
--   clicked included. So while a pin is dragged (Shift+Left) a change only
--   marks the map stale, and the redraw after a drop waits a frame: Blizzard
--   calls OnMouseUp and then OnClick on the SAME pin object, and a redraw in
--   between would have handed that object another waypoint's data, turning
--   the drop into a click on something else.
-- * ROUTE LINES are Line regions (Frame:CreateLine exists on 2.5.6: API docs
--   and the binary) on a canvas-sized frame, thickness divided by the canvas
--   scale so a leg is three pixels wide at any zoom. Should this client's
--   Line refuse its colour or anchors, lines are switched off for the
--   session with one report, and the numbered badges carry the route alone.
-- * FRAME LEVELS. The map's pins take absolute levels from its pin-level
--   manager. Questie's icons are at 2016 and up; ours use
--   PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST (above every quest icon, below the
--   party dots, the corpse and the player arrow), and the arrow's own target
--   one level higher. Route lines live on a plain canvas-sized frame at
--   PIN_FRAME_LEVEL_MAP_HIGHLIGHT: over the map art and the zone highlight,
--   under every icon. Commander_QuestLog's drawer sits over EVERY pin
--   (max(container + 2200, TOPMOST + 10)); while it shows, the arrow's
--   target alone is lifted over it, as QuestLog lifts its own pulsing pins
--   (a whole route lifted covered its quest rows), and the coordinates sit
--   one level under it.
-- * WorldMapFrame IS NEVER ASSIGNED TO. One key added under its pinPools
--   table (the HereBeDragons recipe), HookScript for show and hide, and
--   frames parented to it. No AddCanvasClickHandler: it is the taint factory
--   the old module and TomTom both suffered, it ties with the battleground
--   report-AFK handler at priority 0, and RemoveCanvasClickHandler errors on
--   this client (it calls table.remove with no table).
-- * THE MAP CLICK OVERLAY. A Button over WorldMapFrame.ScrollContainer, shown
--   only while the chosen modifier (and no other) is held with the map open.
--   SetPassThroughButtons is PROTECTED: refused in combat without an error.
--   TomTom called it every frame the modifier was held; here it is called
--   ONCE, at login out of combat (or on the first PLAYER_REGEN_ENABLED after
--   a login in combat), passing Left, Middle, Button4 and Button5 through so
--   only the right button is taken. Until it has been applied the overlay is
--   never shown, because it would swallow left clicks. Showing and hiding an
--   unprotected frame is legal in combat. The overlay sits a few levels over
--   the canvas and far under the pins, so Shift+Right on a pin always reaches
--   the pin, even when Shift is the map-click modifier.
-- * CONTINENT CLICKS. The continent maps hold two coordinate frames (the 530
--   sub-rectangles, critic C3), so a click on a world or continent map is
--   resolved to the zone under the cursor with Geo.ZoneAt and stored in zone
--   coordinates. Where no zone answers (ocean, the Cosmic map between worlds)
--   the player is told to zoom in. A dungeon map answers for itself and is
--   never told to zoom in: if it has no position data, it says so.
-- * COORDINATES. The readout is parented to WorldMapFrame and anchored to the
--   bottom-left of the ScrollContainer (clear of QuestLog's drawer on the
--   right), not to BorderFrame (TBC hides BorderFrame
--   in the windowed map: TomTom B2), so it shows in both map modes, for the
--   MAP ON SCREEN (TomTom showed the player's zone whatever was viewed). It
--   steps aside when Questie writes its own (Questie.db.profile.
--   mapCoordinatesEnabled, Questie's default; read only, never written).
-- * THE MAXIMIZED MAP covers UIParent with an opaque BlackoutFrame at
--   FULLSCREEN strata, the chat frame included, so a refused click or drop
--   is said over the map too (Notice), not only in chat.
-- * D11. No shape glyphs in any drawn text: ARIALN draws them as boxes.
--   Markers are our own textures; numbers and plain words only.
--
-- ---------------------------------------------------------------------------
-- What this file adds: CommanderOrders.Pins (O.Pins) only. No global, no
-- named frame. The runtime calls O.Pins.Refresh() after every change and
-- every settings update, and O.Pins.OnTarget(uid) when the arrow changes
-- hands. Settings read: EnableOrders, MinimapPins, MinimapEdge, WorldPins,
-- RouteLines, MapClickModifier, MapCoords.
-- ---------------------------------------------------------------------------

CommanderOrders = CommanderOrders or {}
local O = CommanderOrders
O.Pins = O.Pins or {}
local P = O.Pins
local G = O.Geo
local D = O.Data or {}

local type, pairs, ipairs, pcall, tostring = type, pairs, ipairs, pcall, tostring
local abs, max, min = math.abs, math.max, math.min
local format = string.format
local HUGE = math.huge

local TEX = D.TEXTURES or {}
local COLOURS = D.ICON_COLOURS or {}

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------
local PIN_TEMPLATE = "CommanderOrdersPinTemplate"     -- our key under WorldMapFrame.pinPools
local PIN_LEVEL = "PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST"
local LINE_LEVEL = "PIN_FRAME_LEVEL_MAP_HIGHLIGHT"
local TOPMOST_LEVEL = "PIN_FRAME_LEVEL_TOPMOST"

local MINI_SIZE = { DOT = 12, BADGE = 14, CORPSE = 14 }   -- Minimap units (its scale applies)
local MINI_BADGE_WIDE = 18            -- a badge whose number has two digits (10+ stops)
local MINI_EDGE = 12
-- Commander_Minimap writes the zone name across the top of its square map
-- (GameFontNormal at TOP -2: about 2..15 units down). On a square map an
-- edge chevron at the top rim (0.9 of the half height, 57..69 for a 12-unit
-- chevron) sat on its letters; it rides this far under the top edge instead
local MINI_TOP_STRIP = 22
local WORLD_SIZE = { DOT = 18, BADGE = 22, CORPSE = 22 }  -- canvas units at pin scale 1
local WORLD_ALT = 10                  -- the other spawns of a nearest-of-N waypoint
local RING_SCALE = 1.7                -- the focus ring's quad against its pin (Ring.png radius 0.39)
local MAX_ALT_PINS = 64               -- alternatives drawn per waypoint per map
local REACHED_ALPHA = 0.45            -- a waypoint kept after it was reached (Keep my own marks)
local ALT_ALPHA = 0.7
local LINE_THICKNESS = 3              -- screen pixels at any zoom
local LINE_ALPHA, LINE_DONE_ALPHA = 0.85, 0.3

local MINI_REBUILD = 1.0              -- seconds between deciding which waypoints get a minimap pin
local MINI_VIEW = 0.5                 -- seconds between re-reading zoom, shape and rotation
local MOVE_EPSILON = 0.05             -- Minimap units: a smaller move skips the SetPoint
local ROTATE_EPSILON = 0.002          -- radians: a smaller turn skips the SetRotation
local COORDS_INTERVAL = 0.1           -- seconds between coordinate readouts
local TELEPORT_YARDS = 250           -- a jump between two frames no mount or taxi makes
local DRAG_SLOP = 0.003               -- map units the cursor must travel before a press is a drag
local OVERLAY_LIFT = 3                -- levels over the ScrollContainer (the canvas is at +1)
local DRAWER_LIFT, LEVEL_CAP = 2200, 9000
local LEVEL_OVER_DRAWER = 10          -- QuestLog's own pulsing pins sit this far over its drawer
local NOTICE_SECONDS = 3              -- a refusal said on the map, then faded
local QUESTLOG_DRAWER = "CommanderQuestLogMapDrawer"

local PASS_THROUGH = { "LeftButton", "MiddleButton", "Button4", "Button5" }

-- A waypoint's source, when it names no icon of its own, to the tint it
-- wears, and to the words for it: Data's tables, shared with the manager
local SOURCE_ICONS = D.SOURCE_ICONS or {}
local SOURCE_WORDS = D.SOURCE_WORDS or {}

local LOOK_TEXTURES = { DOT = TEX.PIN, BADGE = TEX.BADGE, CORPSE = TEX.CORPSE }

local WHITE = { 1, 1, 1 }
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local ACTIVE_TEXT = { 0.40, 1.00, 0.86 }
local HINT_TEXT = { 0.60, 0.80, 1.00 }

-- Everything this file keeps between calls
local S = {
    attached = false,
    target = nil, targetKnown = false,      -- the arrow's target, from OnTarget
}
local Notice = { left = 0 }                 -- a refusal said on the map (defined with the coordinates)
local Coords = { acc = 0, writes = 0 }      -- the world-map coordinates (defined at the end)

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------
local function IsNum(v)
    return type(v) == "number" and v == v and v ~= HUGE and v ~= -HUGE
end

local function Report(err)
    S.lastError = tostring(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler(err) end
end

-- A hook or script that fails must not take the map or the minimap with it
local function Guarded(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then Report(err) end
    end
end

-- The runtime's surface, once it is there
local function Rt()
    local r = O.R
    if type(r) == "table" and type(r.Store) == "function" then return r end
    return nil
end

local function Store()
    local r = Rt()
    return r and r.Store() or nil
end

local function DB()
    local r = Rt()
    local db = r and r.DB and r.DB()
    if type(db) == "table" then return db end
    return O.Defaults or {}
end

local function Setting(key)
    return DB()[key]
end

-- Orders is on and has its store: anything may be drawn
local function Ready()
    return Store() ~= nil and Setting("EnableOrders") and true or false
end

local function Say(msg)
    local r = Rt()
    if r and r.Say then r.Say(msg) elseif print then print("Commander Orders: " .. msg) end
end

local function Env()
    local r = Rt()
    return r and r.Env() or {}
end

local function MapInfo(map)
    if type(map) ~= "number" or not (C_Map and C_Map.GetMapInfo) then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, map)
    if ok and type(info) == "table" then return info end
    return nil
end

local function CVar(name)
    local fn = (C_CVar and C_CVar.GetCVar) or GetCVar
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, name)
    if ok then return v end
    return nil
end

local function Shift()
    return IsShiftKeyDown and IsShiftKeyDown() and true or false
end

local function MapShown()
    return WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown() and true or false
end

-- A refusal of a map click, a drop or a pin click: on the map when it is
-- open (the maximized map's BlackoutFrame covers the chat frame), and in
-- chat, which keeps it for after the map closes
local function Refuse(msg)
    if MapShown() and Notice.Show then pcall(Notice.Show, msg) end
    Say(msg)
end

-- The level over every map pin: max(container + 2200, TOPMOST + 10), the
-- formula Commander_QuestLog's drawer takes its own level from
local function OverLevel()
    local container = WorldMapFrame and WorldMapFrame.ScrollContainer
    local level = ((container and container.GetFrameLevel and container:GetFrameLevel()) or 0) + DRAWER_LIFT
    local manager = WorldMapFrame and WorldMapFrame.GetPinFrameLevelsManager and WorldMapFrame:GetPinFrameLevelsManager()
    if manager and manager.GetValidFrameLevel then
        local ok, top = pcall(manager.GetValidFrameLevel, manager, TOPMOST_LEVEL)
        if ok and IsNum(top) then level = max(level, top + 10) end
    end
    return min(level, LEVEL_CAP)
end

-- Commander_QuestLog's completion drawer, when it is on the map. QuestLog
-- builds it the first time the map opens with Questie loaded and docks it on
-- the right (220 of 580 px windowed, 250 of 1002 maximized), open by
-- default, 88% opaque and mouse-enabled, at OverLevel(): over every pin.
local function DrawerShown()
    local d = _G[QUESTLOG_DRAWER]
    if type(d) ~= "table" or not d.IsShown then return false end
    local ok, shown = pcall(d.IsShown, d)
    return ok and shown and true or false
end

-- The arrow's target: what OnTarget last said, else what the arrow shows
local function ActiveUid()
    if S.targetKnown then return S.target end
    local r = Rt()
    local v = r and r.View and r.View()
    return v and v.wp and v.wp.uid or nil
end

-- The tint key a waypoint wears: its icon, else its kind, route or source
local function IconKey(wp)
    if type(wp.icon) == "string" and COLOURS[wp.icon] then return wp.icon end
    if wp.kind == "corpse" then return "CORPSE" end
    if wp.routeId then return "ROUTE" end
    local src = wp.source
    if type(src) == "string" then
        if SOURCE_ICONS[src] then return SOURCE_ICONS[src] end
        if src:sub(1, 6) == "share:" then return "SHARE" end
        if src:sub(1, 7) == "TomTom:" then return "TOMTOM" end
    end
    return "USER"
end

local function Tint(wp)
    local c = wp.colour
    if type(c) == "table" then
        local r, g, b = c.r or c[1], c.g or c[2], c.b or c[3]
        if IsNum(r) and IsNum(g) and IsNum(b) then return r, g, b end
    elseif type(c) == "string" and COLOURS[c] then
        local k = COLOURS[c]
        return k[1], k[2], k[3]
    end
    local k = COLOURS[IconKey(wp)] or WHITE
    return k[1], k[2], k[3]
end

-- DOT, BADGE (a numbered route stop) or CORPSE
local function Look(wp)
    if wp.kind == "corpse" or wp.icon == "CORPSE" then return "CORPSE" end
    if wp.routeId and wp.routeIndex then return "BADGE" end
    return "DOT"
end

-- Who set it, in words (nil for the corpse: its title already says)
local function SourceWords(wp)
    local src = wp.source
    if wp.kind == "corpse" or type(src) ~= "string" then return nil end
    if src == "user" or src == "legacy" then return "Set by you" end
    if src == "place" then return "One of your places" end
    if src == "guide" then return "The next leg of the way there" end
    if src:sub(1, 6) == "share:" then return "Shared by " .. src:sub(7) end
    if src:sub(1, 7) == "TomTom:" then return "From " .. src:sub(8) end
    return "From " .. (SOURCE_WORDS[src] or src)
end

local function SetArrow(uid)
    local fn = O.SetArrow
    if type(fn) ~= "function" then return end
    local ok, err = fn(uid)
    if not ok and err and err ~= "disabled" then Refuse("could not set the arrow (" .. tostring(err) .. ")") end
end

local function Menu(uid)
    local r = Rt()
    if not (r and r.WaypointMenu and r.ShowMenu) then return end
    local entries = r.WaypointMenu(uid)
    if type(entries) == "table" and #entries > 0 then r.ShowMenu(entries, "cursor") end
end

-- The hover card the minimap and the map share
local function Tooltip(owner, uid, hints)
    if not (GameTooltip and owner) then return end
    local store, r = Store(), Rt()
    local wp = store and store:Get(uid)
    if not (wp and r) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(r.Title(wp), 1, 1, 1)
    if wp.map then GameTooltip:AddLine(r.Where(wp), 0.8, 0.8, 0.8) end
    local active = uid == ActiveUid()
    local d = store:Distance(wp, r.Ctx())
    if d then
        local text = r.Distance(d) or ""
        local eta = active and r.Eta and r.Eta()
        local etaText = eta and G.FormatEta(eta)
        if etaText then text = text .. ", about " .. etaText end
        GameTooltip:AddLine(text, 1, 0.82, 0.3)
    end
    local route = wp.routeId and store:GetRoute(wp.routeId)
    if route and wp.routeIndex then
        local line = format("Stop %d of %d", wp.routeIndex, #route.stops)
        if route.title and route.title ~= "" then line = line .. ": " .. route.title end
        GameTooltip:AddLine(line, 0.4, 0.8, 1)
    end
    if type(wp.alternatives) == "table" and #wp.alternatives > 1 then
        GameTooltip:AddLine(format("The nearest of %d places", #wp.alternatives), 0.8, 0.8, 0.8)
    end
    local words = SourceWords(wp)
    if words then GameTooltip:AddLine(words, 0.6, 0.6, 0.6) end
    if wp.reached then GameTooltip:AddLine("Reached", 0.3, 1, 0.36) end
    if type(wp.note) == "string" and wp.note ~= "" then GameTooltip:AddLine(wp.note, 0.8, 0.84, 0.9, true) end
    if active then GameTooltip:AddLine("The arrow points here", ACTIVE_TEXT[1], ACTIVE_TEXT[2], ACTIVE_TEXT[3]) end
    for _, h in ipairs(hints or {}) do GameTooltip:AddLine(h, HINT_TEXT[1], HINT_TEXT[2], HINT_TEXT[3]) end
    GameTooltip:Show()
end

local function HideTooltip(owner)
    if GameTooltip and (owner == nil or not GameTooltip.GetOwner or GameTooltip:GetOwner() == owner) then
        GameTooltip:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- The minimap
-- ---------------------------------------------------------------------------
local Mini = { pins = {}, entries = {}, count = 0, rebuildAcc = 0, viewAcc = 0, places = 0 }
local MINI_HINTS = { "Shift-click: point the arrow here", "Right-click: menu" }

-- The radius in yards, the shape, the rotation and the size, read from the
-- client (on zoom events, and twice a second while pins are shown)
function Mini.ReadView()
    local zoom = 0
    if Minimap and Minimap.GetZoom then
        local ok, z = pcall(Minimap.GetZoom, Minimap)
        if ok and IsNum(z) then zoom = z end
    end
    local indoors = G.MinimapIndoors(zoom, CVar("minimapZoom"), CVar("minimapInsideZoom"),
        IsIndoors and IsIndoors())
    Mini.indoors = indoors
    Mini.radius = G.MinimapRadius(zoom, indoors)
    Mini.rotate = CVar("rotateMinimap") == "1"
    local shape = "ROUND"
    if type(GetMinimapShape) == "function" then
        local ok, s = pcall(GetMinimapShape)
        if ok and type(s) == "string" then shape = s end
    end
    Mini.shape = shape
    local w = Minimap and Minimap.GetWidth and Minimap:GetWidth()
    local h = Minimap and Minimap.GetHeight and Minimap:GetHeight()
    Mini.halfW = (IsNum(w) and w > 0) and w / 2 or 70
    Mini.halfH = (IsNum(h) and h > 0) and h / 2 or Mini.halfW
    Mini.edgeOn = Setting("MinimapEdge") ~= false
end

-- Over Commander_Radar's overlay, whichever is the higher
function Mini.Level()
    local base = (Minimap and Minimap.GetFrameLevel and Minimap:GetFrameLevel()) or 0
    local radar = CommanderRadarOverlay
    if type(radar) == "table" and radar.GetFrameLevel then
        local ok, level = pcall(radar.GetFrameLevel, radar)
        if ok and IsNum(level) and level > base then base = level end
    end
    return base + 3
end

function Mini.Driver()
    if Mini.driver then return Mini.driver end
    if not (CreateFrame and Minimap) then return nil end
    -- unnamed, and a child of the Minimap: hidden minimap, no work
    local f = CreateFrame("Frame", nil, Minimap)
    f:SetSize(1, 1)
    f:EnableMouse(false)
    f:Hide()
    f:SetScript("OnUpdate", Guarded(function(_, elapsed) Mini.OnUpdate(elapsed) end))
    Mini.driver = f
    return f
end

local function MiniClick(self, button)
    local e = self.entry
    if not e then return end
    if button == "RightButton" then
        Menu(e.uid)
    elseif Shift() then
        SetArrow(e.uid)
    end
end

function Mini.Pin(i)
    local pin = Mini.pins[i]
    if pin then return pin end
    pin = CreateFrame("Button", nil, Minimap)
    pin:SetSize(MINI_SIZE.DOT, MINI_SIZE.DOT)
    pin:EnableMouse(true)
    if pin.RegisterForClicks then pin:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    local ring = pin:CreateTexture(nil, "BACKGROUND")
    ring:SetTexture(TEX.RING)
    ring:SetPoint("CENTER", pin, "CENTER", 0, 0)
    ring:Hide()
    local icon = pin:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(pin)
    local edge = pin:CreateTexture(nil, "ARTWORK", nil, 1)
    edge:SetTexture(TEX.PIN_EDGE)
    edge:SetSize(MINI_EDGE, MINI_EDGE)
    edge:SetPoint("CENTER", pin, "CENTER", 0, 0)
    edge:Hide()
    local number = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
    number:SetPoint("CENTER", pin, "CENTER", 0, 0)
    number:Hide()
    pin.ring, pin.icon, pin.edge, pin.number = ring, icon, edge, number
    pin:SetScript("OnClick", Guarded(MiniClick))
    pin:SetScript("OnEnter", Guarded(function(self)
        if self.entry then Tooltip(self, self.entry.uid, MINI_HINTS) end
    end))
    pin:SetScript("OnLeave", function(self) HideTooltip(self) end)
    pin:Hide()
    Mini.pins[i] = pin
    return pin
end

-- Texture, size, tint, number and ring; written only when they change
function Mini.Style(pin, e)
    local wp = e.wp
    local look = Look(wp)
    local r, g, b = Tint(wp)
    local active = e.uid == ActiveUid()
    local number = look == "BADGE" and tostring(wp.routeIndex) or nil
    local alpha = wp.reached and REACHED_ALPHA or 1
    local key = format("%s|%s|%s|%.3f|%.3f|%.3f|%.2f", look, tostring(number), tostring(active), r, g, b, alpha)
    if pin.styleKey == key then return end
    pin.styleKey = key
    local size = MINI_SIZE[look] or MINI_SIZE.DOT
    -- "10" and up filled the 14-unit disc rim to rim (its light fill is
    -- about 9 units across; review: render)
    if number and #number >= 2 then size = MINI_BADGE_WIDE end
    pin:SetSize(size, size)
    pin.icon:SetTexture(LOOK_TEXTURES[look] or TEX.PIN)
    pin.icon:SetVertexColor(r, g, b)
    pin.icon:SetAlpha(alpha)
    pin.edge:SetVertexColor(r, g, b)
    pin.edge:SetAlpha(alpha)
    pin.ring:SetSize(size * RING_SCALE, size * RING_SCALE)
    pin.ring:SetVertexColor(r, g, b)
    pin.active, pin.numberText = active, number
    if number then pin.number:SetText(number) end
    pin.onEdge = nil               -- re-decide which parts show
end

-- Which waypoints get a pin: every one on the player's landmass, at the
-- position the arrow would use (the chosen spawn of a nearest-of-N one)
function Mini.Rebuild()
    Mini.rebuildAcc = 0
    local entries = Mini.entries
    local n = 0
    local store, r = Store(), Rt()
    local want = store and r and Minimap and CreateFrame and Ready() and Setting("MinimapPins")
    local pinst, pnorth, pwest
    if want then
        local pn, pw, inst = r.PlayerWorld()
        local pmap = r.PlayerMap()
        local pkey = pn and pmap and r.Landmass(pmap, inst)
        pinst, pnorth, pwest = inst, pn, pw
        if pkey then
            local ctx = r.Ctx()
            for _, wp in ipairs(store:List()) do
                if wp.kind ~= "unit" then
                    local pos = store:Position(wp, ctx)
                    local winst, north, west = r.PosWorld(pos)
                    if winst ~= nil and winst == inst and r.Landmass(pos.map, winst) == pkey then
                        n = n + 1
                        local e = entries[n]
                        if not e then
                            e = {}
                            entries[n] = e
                        end
                        e.uid, e.wp, e.n, e.w = wp.uid, wp, north, west
                    end
                end
            end
        end
    end
    for i = #entries, n + 1, -1 do entries[i] = nil end
    Mini.count, Mini.inst, Mini.lastN, Mini.lastW = n, pinst, pnorth, pwest
    local level = n > 0 and Mini.Level() or nil
    for i = 1, n do
        local pin = Mini.Pin(i)
        pin.entry = entries[i]
        if level and pin:GetFrameLevel() ~= level then pin:SetFrameLevel(level) end
        Mini.Style(pin, entries[i])
    end
    for i = n + 1, #Mini.pins do
        local pin = Mini.pins[i]
        pin.entry = nil
        if pin:IsShown() then pin:Hide() end
    end
    local driver = Mini.Driver()
    if driver then
        if n > 0 then
            if not driver:IsShown() then driver:Show() end
            Mini.ReadView()
            Mini.Place()
        elseif driver:IsShown() then
            driver:Hide()
        end
    end
end

-- Every frame while pins are up: where each one sits now
function Mini.Place()
    local r = Rt()
    if not r or Mini.count == 0 then return end
    local pn, pw, inst = r.PlayerWorld()
    -- A loading screen since the last rebuild: other landmass, other pins.
    -- The instance alone does not say so: a portal from Silvermoon to
    -- Shattrath stays in 530 (Geo trap 3), so a jump no mount can make
    -- between two frames counts too.
    if pn and (inst ~= Mini.inst or (Mini.lastN and abs(pn - Mini.lastN) + abs(pw - Mini.lastW) > TELEPORT_YARDS)) then
        Mini.Rebuild()
        return
    end
    Mini.lastN, Mini.lastW = pn, pw
    local facing = r.Facing()
    local radius, rotate, shape = Mini.radius, Mini.rotate, Mini.shape
    local halfW, halfH, edgeOn = Mini.halfW, Mini.halfH, Mini.edgeOn
    Mini.places = Mini.places + 1
    for i = 1, Mini.count do
        local e, pin = Mini.entries[i], Mini.pins[i]
        local px, py, onEdge, angle
        if pn and radius then
            px, py, onEdge, angle = G.MinimapPlace(e.n - pn, e.w - pw, radius, facing, rotate, shape, halfW, halfH)
            -- under Commander_Minimap's zone name on its square map (the
            -- chevron keeps its angle; only its spot on the rim moves down)
            if onEdge and shape == "SQUARE" and py > halfH - MINI_TOP_STRIP then py = halfH - MINI_TOP_STRIP end
        end
        if not px or (onEdge and not edgeOn) then
            if pin:IsShown() then pin:Hide() end
            pin.px = nil
        else
            if pin.onEdge ~= onEdge then
                pin.onEdge = onEdge
                pin.icon:SetShown(not onEdge)
                pin.edge:SetShown(onEdge)
                pin.ring:SetShown(pin.active and not onEdge)
                pin.number:SetShown(pin.numberText ~= nil and not onEdge)
                pin.angle = nil
            end
            if onEdge and (not pin.angle or abs(angle - pin.angle) > ROTATE_EPSILON) then
                pin.angle = angle
                pin.edge:SetRotation(angle)
            end
            if not pin.px or abs(px - pin.px) > MOVE_EPSILON or abs(py - pin.py) > MOVE_EPSILON then
                pin.px, pin.py = px, py
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", Minimap, "CENTER", px, py)
            end
            if not pin:IsShown() then pin:Show() end
        end
    end
end

function Mini.OnUpdate(elapsed)
    elapsed = IsNum(elapsed) and elapsed or 0
    Mini.rebuildAcc = Mini.rebuildAcc + elapsed
    Mini.viewAcc = Mini.viewAcc + elapsed
    if Mini.rebuildAcc >= MINI_REBUILD then
        Mini.Rebuild()
        return
    end
    if Mini.viewAcc >= MINI_VIEW then
        Mini.viewAcc = 0
        Mini.ReadView()
    end
    Mini.Place()
end

-- The zoom, the indoor flag or a CVar changed under pins already shown
function Mini.ViewChanged()
    if Mini.count == 0 then return end
    Mini.ReadView()
    Mini.Place()
end

-- ---------------------------------------------------------------------------
-- The world map: pins, badges, route lines
-- ---------------------------------------------------------------------------
local World = { lines = {}, linesUsed = 0, draws = 0 }
local WORLD_HINTS = { "Click: point the arrow here", "Right-click: menu" }
local WORLD_DRAG_HINTS = { "Click: point the arrow here", "Right-click: menu", "Shift-drag: move it" }

function World.Regions(pin)
    if pin.icon then return end
    local ring = pin:CreateTexture(nil, "BACKGROUND")
    ring:SetTexture(TEX.RING)
    ring:SetPoint("CENTER", pin, "CENTER", 0, 0)
    ring:Hide()
    local icon = pin:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(pin)
    local number = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
    number:SetPoint("CENTER", pin, "CENTER", 0, 0)
    number:Hide()
    pin.ring, pin.icon, pin.number = ring, icon, number
end

-- Also run from OnReleased, inside a redraw: it only clears, never redraws
local function EndDrag(pin)
    if pin.drag then
        pin.drag = nil
        if pin.SetScript then pin:SetScript("OnUpdate", nil) end
    end
    if World.dragging == pin then World.dragging = nil end
end

local function DragCursor(pin)
    local map = pin.GetMap and pin:GetMap()
    if not (map and map.GetNormalizedCursorPosition) then return nil end
    local nx, ny = map:GetNormalizedCursorPosition()
    if IsNum(nx) and IsNum(ny) then return nx, ny, map end
    return nil
end

local function DragUpdate(pin)
    local drag = pin.drag
    if not drag then return end
    local nx, ny = DragCursor(pin)
    if not nx then return end
    if not drag.moved and (abs(nx - drag.cx) > DRAG_SLOP or abs(ny - drag.cy) > DRAG_SLOP) then
        drag.moved = true
    end
    if drag.moved then pin:SetPosition(nx, ny) end
end
local DragUpdateGuarded = Guarded(DragUpdate)

-- A dragged pin dropped at (nx, ny) on `map`: the waypoint moves there, in
-- zone coordinates (a continent drop lands in the zone under it). Called
-- from OnMouseUp, so a refused drop only marks the map stale: the pin goes
-- back on the deferred redraw, after Blizzard's OnClick has run.
function World.Drop(uid, map, nx, ny)
    local zm, zx, zy = G.ZoneAt(Env(), map, nx, ny)
    if not zm then
        Refuse("Zoom in to move an order")
        World.pending = true
        return false
    end
    local fn = O.Update
    local wp, err
    if type(fn) == "function" then wp, err = fn(uid, { map = zm, x = zx, y = zy }) end
    if not wp then
        Refuse("could not move that order (" .. tostring(err) .. ")")
        World.pending = true
        return false
    end
    return true
end

local function NewPinMixin()
    local mixin = CreateFromMixins(MapCanvasPinMixin)
    local baseLevel = MapCanvasPinMixin.ApplyFrameLevel

    -- Idempotent: AcquirePin calls it for a new pin; OnAcquired makes sure
    function mixin:OnLoad()
        self._loaded = true
        self:UseFrameLevelType(PIN_LEVEL)
        self:SetScalingLimits(1, 1.0, 1.2)
    end

    function mixin:OnAcquired(data)
        if not self._loaded then self:OnLoad() end
        self:UseFrameLevelType(PIN_LEVEL)
        World.Regions(self)
        self.data = data
        local size = data.alt and WORLD_ALT or (WORLD_SIZE[data.look] or WORLD_SIZE.DOT)
        self:SetSize(size, size)
        self.icon:SetTexture(LOOK_TEXTURES[data.look] or TEX.PIN)
        self.icon:SetVertexColor(data.r, data.g, data.b)
        self.icon:SetAlpha(data.reached and REACHED_ALPHA or (data.alt and ALT_ALPHA or 1))
        if data.number and not data.alt then
            self.number:SetText(data.number)
            self.number:Show()
        else
            self.number:Hide()
        end
        if data.active and not data.alt then
            self.ring:SetSize(size * RING_SCALE, size * RING_SCALE)
            self.ring:SetVertexColor(data.r, data.g, data.b)
            self.ring:Show()
        else
            self.ring:Hide()
        end
        self:SetPosition(data.x, data.y)
    end

    function mixin:OnReleased()
        EndDrag(self)
        self.dragged = nil
        self.data = nil
    end

    function mixin:OnMouseEnter()
        local d = self.data
        if d then Tooltip(self, d.uid, d.draggable and WORLD_DRAG_HINTS or WORLD_HINTS) end
    end

    function mixin:OnMouseLeave()
        HideTooltip(self)
    end

    -- Shift+Left on a movable pin starts a drag; a press that never travels
    -- is still a click
    function mixin:OnMouseDown(button)
        local d = self.data
        if button ~= "LeftButton" or not Shift() or not (d and d.draggable) then return end
        local nx, ny = DragCursor(self)
        if not nx then return end
        self.drag = { cx = nx, cy = ny, moved = false }
        World.dragging = self
        self:SetScript("OnUpdate", DragUpdateGuarded)
    end

    -- Blizzard calls this before OnClick (OnPinMouseUp)
    function mixin:OnMouseUp(button)
        local drag = self.drag
        if button ~= "LeftButton" or not drag then return end
        local nx, ny, map = DragCursor(self)
        EndDrag(self)
        if nx and (drag.moved or abs(nx - drag.cx) > DRAG_SLOP or abs(ny - drag.cy) > DRAG_SLOP) then
            self.dragged = true
            local d = self.data
            if d and map.GetMapID then World.Drop(d.uid, map:GetMapID(), nx, ny) end
        end
        -- not now: Blizzard calls OnClick on this same pin right after, and
        -- a redraw would have handed it another waypoint's data
        if C_Timer and C_Timer.After then
            C_Timer.After(0, World.FlushDeferredGuarded)
        else
            World.FlushDeferred()
        end
    end

    function mixin:OnClick(button)
        if self.dragged then
            self.dragged = nil
            return
        end
        local d = self.data
        if not d then return end
        if button == "RightButton" then
            Menu(d.uid)
        elseif button == "LeftButton" then
            SetArrow(d.uid)
        end
    end

    -- The arrow's own target is drawn over the other waypoints. While
    -- QuestLog's drawer is on the map, the target alone goes over the
    -- drawer, as QuestLog lifts its own pulsing pins: under it, it was
    -- hidden and could not be clicked (review: render, surfaces). Every
    -- other pin stays under the drawer, as Blizzard's and QuestLog's do: a
    -- lifted route sat on the drawer's quest rows and took their clicks
    -- (review-r2 orders). The level is worked out, never read off the
    -- drawer, so the order the two re-level in does not matter.
    function mixin:ApplyFrameLevel()
        if baseLevel then baseLevel(self) end
        local d = self.data
        if not (d and not d.alt and self.GetFrameLevel) then return end
        if d.lift and DrawerShown() then
            self:SetFrameLevel(OverLevel() + LEVEL_OVER_DRAWER + (d.active and 1 or 0))
        elseif d.active then
            self:SetFrameLevel(self:GetFrameLevel() + 1)
        end
    end

    -- HereBeDragons' insurance: the map never gets to set pass-through
    -- buttons on a pin in combat
    mixin.SetPassThroughButtons = function() end
    return mixin
end

local function CreatePin()
    local pin = CreateFrame("Frame", nil, WorldMapFrame:GetCanvas())
    pin:SetSize(1, 1)
    Mixin(pin, World.mixin)
    -- before AcquirePin sees it: it wires the mouse from these (header)
    pin:EnableMouse(true)
    if pin.SetMouseClickEnabled then pin:SetMouseClickEnabled(true) end
    if pin.SetMouseMotionEnabled then pin:SetMouseMotionEnabled(true) end
    return pin
end

-- Also run on a brand-new pin (Pools.lua resets on creation)
local function ResetPin(_, pin)
    pin:Hide()
    pin:ClearAllPoints()
    if pin.OnReleased then pin:OnReleased() end
    pin.pinTemplate = nil
    pin.owningMap = nil
end

-- CreateFramePool's postCreate, for a client with only the secure pool
local function MixPin(pin)
    pin:SetSize(1, 1)
    Mixin(pin, World.mixin)
    pin:EnableMouse(true)
    if pin.SetMouseClickEnabled then pin:SetMouseClickEnabled(true) end
    if pin.SetMouseMotionEnabled then pin:SetMouseMotionEnabled(true) end
end

-- The canvas-sized frame the route lines are drawn on
function World.LineHost(map)
    local canvas = map and map.GetCanvas and map:GetCanvas()
    if not canvas then return nil end
    local host = World.host
    if not host then
        host = CreateFrame("Frame", nil, canvas)
        host:SetAllPoints(canvas)
        host:EnableMouse(false)
        World.host = host
    end
    local manager = map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
    if manager and manager.GetValidFrameLevel then
        local ok, level = pcall(manager.GetValidFrameLevel, manager, LINE_LEVEL)
        if ok and IsNum(level) and host:GetFrameLevel() ~= level then host:SetFrameLevel(level) end
    end
    return host, canvas
end

function World.HideLines()
    for i = 1, World.linesUsed do
        local line = World.lines[i]
        if line then line:Hide() end
    end
    World.linesUsed = 0
end

-- Line thickness in canvas units, so it stays the same on screen at any zoom
function World.Thickness(map)
    local scale = map and map.GetCanvasScale and map:GetCanvasScale()
    if IsNum(scale) and scale > 0 then return LINE_THICKNESS / scale end
    return LINE_THICKNESS
end

local function PaintLine(line, host, x1, y1, x2, y2, w, h, thickness, alpha)
    local c = COLOURS.ROUTE or WHITE
    if line.SetColorTexture then
        line:SetColorTexture(c[1], c[2], c[3], alpha)
    else
        line:SetTexture(WHITE_TEXTURE)
        line:SetVertexColor(c[1], c[2], c[3], alpha)
    end
    line:SetThickness(thickness)
    line:SetStartPoint("TOPLEFT", host, x1 * w, -y1 * h)
    line:SetEndPoint("TOPLEFT", host, x2 * w, -y2 * h)
    line:Show()
end

-- One leg. A client whose Line regions refuse any of this loses the lines
-- for the session (said once to the error handler); the badges carry on.
function World.Line(host, x1, y1, x2, y2, w, h, thickness, alpha)
    if World.linesBroken or not host.CreateLine then return nil end
    local i = World.linesUsed + 1
    local line = World.lines[i]
    if not line then
        local ok, made = pcall(host.CreateLine, host, nil, "ARTWORK")
        if not ok or not made then
            World.linesBroken = true
            Report(made or "CreateLine returned nothing")
            return nil
        end
        line = made
        World.lines[i] = line
    end
    World.linesUsed = i
    local ok, err = pcall(PaintLine, line, host, x1, y1, x2, y2, w, h, thickness, alpha)
    if not ok then
        World.linesBroken = true
        Report(err)
        World.HideLines()
        return nil
    end
    return line
end

local function Inside(x, y)
    return x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1
end

-- The active route, stop to stop, on the map being viewed. A leg whose
-- stops lie on two landmasses has no straight line and is left out.
function World.DrawLines(map, viewed)
    World.HideLines()
    local store, r = Store(), Rt()
    if not (store and r and Setting("RouteLines") ~= false) then return end
    local route = store:ActiveRoute()
    if not (route and #route.stops >= 2) then return end
    local host, canvas = World.LineHost(map)
    if not (host and host.CreateLine) then return end
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    if not (IsNum(w) and IsNum(h) and w > 0 and h > 0) then return end
    local env = Env()
    local thickness = World.Thickness(map)
    local legs = #route.stops - 1
    if route.loop and #route.stops > 2 then legs = #route.stops end
    for i = 1, legs do
        local a = store:Get(route.stops[i])
        local b = store:Get(route.stops[i % #route.stops + 1])
        if a and b and a.map and b.map then
            local ia = r.PosWorld(a)
            local ib = r.PosWorld(b)
            if ia and ia == ib and r.Landmass(a.map, ia) == r.Landmass(b.map, ib) then
                local x1, y1 = G.ProjectToMap(env, a.map, a.x, a.y, viewed)
                local x2, y2 = G.ProjectToMap(env, b.map, b.x, b.y, viewed)
                if Inside(x1, y1) and Inside(x2, y2) then
                    local done = (route.index or 1) > i and not route.loop
                    World.Line(host, x1, y1, x2, y2, w, h, thickness, done and LINE_DONE_ALPHA or LINE_ALPHA)
                end
            end
        end
    end
end

-- Every waypoint that lands on the viewed map, as pin data
function World.Collect(viewed)
    local out = {}
    local store = Store()
    if not store then return out end
    local env = Env()
    local active = ActiveUid()
    for _, wp in ipairs(store:List()) do
        if wp.kind ~= "unit" then
            -- the arrow's target alone goes over QuestLog's drawer: a whole
            -- route lifted sat on its quest rows and took their clicks
            -- (review-r2 orders); a running route's current stop is the target
            local lift = wp.uid == active
            local look = Look(wp)
            local r, g, b = Tint(wp)
            local number = look == "BADGE" and tostring(wp.routeIndex) or nil
            local alts = type(wp.alternatives) == "table" and #wp.alternatives > 1 and wp.alternatives or nil
            local draggable = not alts and wp.kind ~= "corpse" and wp.map ~= nil
            local chosen = alts and store:ChosenAlternative(wp.uid) or 1
            local list = alts or { wp }
            for i = 1, min(#list, MAX_ALT_PINS) do
                local p = list[i]
                if p and p.map then
                    local x, y = G.ProjectToMap(env, p.map, p.x, p.y, viewed)
                    if Inside(x, y) then
                        out[#out + 1] = {
                            uid = wp.uid, x = x, y = y, look = look, r = r, g = g, b = b,
                            number = number, active = wp.uid == active, alt = alts ~= nil and i ~= chosen,
                            reached = wp.reached ~= nil, draggable = draggable, lift = lift,
                        }
                    end
                end
            end
        end
    end
    return out
end

function World.Draw(provider)
    local map = (provider and provider.GetMap and provider:GetMap()) or WorldMapFrame
    if not (map and map.RemoveAllPinsByTemplate and map.AcquirePin and map.GetMapID) then return end
    map:RemoveAllPinsByTemplate(PIN_TEMPLATE)
    World.HideLines()
    if not (Ready() and Setting("WorldPins") ~= false) then return end
    local viewed = map:GetMapID()
    if type(viewed) ~= "number" then return end
    World.draws = World.draws + 1
    if not World.drawerHooked then World.WatchDrawer() end
    for _, data in ipairs(World.Collect(viewed)) do
        map:AcquirePin(PIN_TEMPLATE, data)
    end
    World.DrawLines(map, viewed)
end

function World.Build()
    if World.provider then return true end
    if not (WorldMapFrame and type(WorldMapFrame.pinPools) == "table" and WorldMapFrame.AddDataProvider
        and WorldMapFrame.GetCanvas and CreateFrame) then
        return false
    end
    if not (type(MapCanvasDataProviderMixin) == "table" and type(MapCanvasPinMixin) == "table"
        and CreateFromMixins and Mixin and (CreateUnsecuredRegionPoolInstance or CreateFramePool)) then
        return false
    end
    World.mixin = NewPinMixin()
    local canvas = WorldMapFrame:GetCanvas()
    local pool
    if CreateUnsecuredRegionPoolInstance then
        pool = CreateUnsecuredRegionPoolInstance(PIN_TEMPLATE, CreatePin, ResetPin)
    else
        pool = CreateFramePool("FRAME", canvas, nil, ResetPin, false, MixPin)
    end
    pool.parent = canvas
    -- both generations of the pool's field names, as HereBeDragons sets them
    pool.createFunc, pool.creationFunc = CreatePin, CreatePin
    pool.resetFunc, pool.resetterFunc = ResetPin, ResetPin
    WorldMapFrame.pinPools[PIN_TEMPLATE] = pool

    local provider = CreateFromMixins(MapCanvasDataProviderMixin)
    function provider:RemoveAllData()
        local map = self:GetMap()
        if map and map.RemoveAllPinsByTemplate then map:RemoveAllPinsByTemplate(PIN_TEMPLATE) end
        World.HideLines()
    end
    function provider:RefreshAllData()
        local ok, err = pcall(World.Draw, self)
        if not ok then Report(err) end
    end
    function provider:OnCanvasScaleChanged()
        local thickness = World.Thickness(self:GetMap())
        for i = 1, World.linesUsed do pcall(World.lines[i].SetThickness, World.lines[i], thickness) end
    end
    World.provider, World.pool = provider, pool
    WorldMapFrame:AddDataProvider(provider)
    return true
end

-- A redraw releases every pin, the one under a drag too, so while a pin is
-- being dragged a change (an arrival tick, the arrow changing hands) only
-- marks the map stale; the drop redraws it. Blizzard's own redraws (a map
-- change) still go straight through and end the drag.
function World.Refresh()
    if not (World.provider and MapShown()) then return end
    if World.dragging then
        World.pending = true
        return
    end
    World.provider:RefreshAllData()
end

function World.FlushDeferred()
    if World.pending and not World.dragging then
        World.pending = nil
        World.Refresh()
    end
end
World.FlushDeferredGuarded = Guarded(function() World.FlushDeferred() end)
World.RefreshGuarded = Guarded(function()
    World.Refresh()
    if Coords.Level and Coords.frame then Coords.Level() end
end)

-- QuestLog's drawer showing or hiding re-levels the pins. Hooked once it
-- exists: QuestLog builds it on the first map show with Questie loaded,
-- after this file's own OnShow hook has run, so the map show also checks
-- again a frame later.
function World.WatchDrawer()
    if World.drawerHooked then return end
    local d = _G[QUESTLOG_DRAWER]
    if type(d) ~= "table" or not d.HookScript then return end
    World.drawerHooked = true
    d:HookScript("OnShow", World.RefreshGuarded)
    d:HookScript("OnHide", World.RefreshGuarded)
    if DrawerShown() then World.RefreshGuarded() end
end
World.WatchDrawerGuarded = Guarded(function() World.WatchDrawer() end)

-- ---------------------------------------------------------------------------
-- The map click: modifier + right-click drops a waypoint
-- ---------------------------------------------------------------------------
local Overlay = { passCalls = 0 }

-- The chosen modifier, and no other
function Overlay.ModifierHeld()
    local m = Setting("MapClickModifier")
    if m ~= "CTRL" and m ~= "ALT" and m ~= "SHIFT" then return false end
    local ctrl = IsControlKeyDown and IsControlKeyDown() and true or false
    local alt = IsAltKeyDown and IsAltKeyDown() and true or false
    local shift = Shift()
    if m == "CTRL" then return ctrl and not alt and not shift end
    if m == "ALT" then return alt and not ctrl and not shift end
    return shift and not ctrl and not alt
end

-- A waypoint at a point of a map (the overlay's click; exported for the
-- manager's "add at cursor" and the harness)
function Overlay.Place(map, nx, ny)
    if type(map) ~= "number" or not (IsNum(nx) and IsNum(ny)) then return nil, "no position" end
    local info = MapInfo(map)
    local zm, zx, zy = G.ZoneAt(Env(), map, nx, ny)
    if not zm then
        Refuse("Zoom in to place an order")
        return nil, "zoom in"
    end
    local fn = O.Add
    if type(fn) ~= "function" then return nil, "loading" end
    local uid, err = fn({ map = zm, x = zx, y = zy, source = "user", setArrow = true })
    if uid then return uid end
    if err == "no world position" then
        local deep = info and IsNum(info.mapType) and info.mapType >= 4
        Refuse(deep and "this map has no positions to put an order on" or "Zoom in to place an order")
    elseif err == "disabled" then
        Refuse("Commander Orders is turned off (/corder to turn it on)")
    else
        Refuse("could not place an order there (" .. tostring(err) .. ")")
    end
    return nil, err
end

local function OverlayClick(_, button)
    if button ~= "RightButton" or not WorldMapFrame then return end
    local map = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    local nx, ny
    if WorldMapFrame.GetNormalizedCursorPosition then nx, ny = WorldMapFrame:GetNormalizedCursorPosition() end
    Overlay.Place(map, nx, ny)
end

-- Called once, out of combat: SetPassThroughButtons is protected
function Overlay.TryPassThrough()
    local f = Overlay.frame
    if not f or Overlay.passReady then return end
    if InCombatLockdown and InCombatLockdown() then
        Overlay.passPending = true
        return
    end
    if f.SetPassThroughButtons then
        Overlay.passCalls = Overlay.passCalls + 1
        local ok, err = pcall(f.SetPassThroughButtons, f, PASS_THROUGH[1], PASS_THROUGH[2], PASS_THROUGH[3],
            PASS_THROUGH[4])
        if not ok then Report(err) end
    end
    Overlay.passReady, Overlay.passPending = true, false
end

function Overlay.Build()
    if Overlay.frame then return Overlay.frame end
    local container = WorldMapFrame and WorldMapFrame.ScrollContainer
    if not (container and CreateFrame) then return nil end
    local f = CreateFrame("Button", nil, container)
    f:SetAllPoints(container)
    f:SetFrameLevel(((container.GetFrameLevel and container:GetFrameLevel()) or 0) + OVERLAY_LIFT)
    f:EnableMouse(true)
    if f.RegisterForClicks then f:RegisterForClicks("RightButtonUp") end
    f:SetScript("OnClick", Guarded(OverlayClick))
    f:Hide()
    Overlay.frame = f
    Overlay.TryPassThrough()
    return f
end

function Overlay.Update()
    local f = Overlay.frame
    if not f then return end
    local want = Overlay.passReady and Ready() and MapShown() and Overlay.ModifierHeld() and true or false
    if want ~= (f:IsShown() and true or false) then f:SetShown(want) end
end

-- ---------------------------------------------------------------------------
-- World-map coordinates
-- ---------------------------------------------------------------------------
-- Questie writes its own into the map title, on by default; then ours step
-- aside (read only)
function Coords.QuestieShows()
    local q = Questie
    local db = type(q) == "table" and q.db
    local profile = type(db) == "table" and db.profile
    return type(profile) == "table" and profile.mapCoordinatesEnabled and true or false
end

function Coords.Build()
    if Coords.frame then return Coords.frame end
    local container = WorldMapFrame and WorldMapFrame.ScrollContainer
    if not (container and CreateFrame) then return nil end
    local f = CreateFrame("Frame", nil, WorldMapFrame)
    f:SetSize(300, 16)
    -- bottom-left, clear of QuestLog's drawer on the right (centred, it ran
    -- into the drawer's bottom corner on the 580 px windowed map)
    f:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 8, 3)
    f:EnableMouse(false)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(0, 0, 0, 0.55)
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.bg, f.text = bg, text
    f:SetScript("OnUpdate", Guarded(function(_, elapsed) Coords.Tick(elapsed) end))
    f:Hide()
    Coords.frame = f
    return f
end

-- Over the map's pins (the player arrow included), one level under
-- QuestLog's drawer: the same level as the drawer left which one draws on
-- top undefined where they meet
function Coords.Level()
    local f = Coords.frame
    if not f then return end
    local level = OverLevel() - 1
    if f:GetFrameLevel() ~= level then f:SetFrameLevel(level) end
end

function Coords.Update()
    local f = Coords.frame
    if not f then return end
    local want = Ready() and Setting("MapCoords") ~= false and MapShown()
    if want then
        Coords.Level()
        Coords.acc = COORDS_INTERVAL      -- write on the next frame
        if not f:IsShown() then f:Show() end
    elseif f:IsShown() then
        f:Hide()
    end
end

-- The player's position on the map on screen, or nil
function Coords.Player(map)
    if not (C_Map and C_Map.GetPlayerMapPosition) then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not ok or (type(pos) ~= "table" and type(pos) ~= "userdata") then return nil end
    local x, y = pos.x, pos.y
    if (x == nil or y == nil) and pos.GetXY then x, y = pos:GetXY() end
    if not (IsNum(x) and IsNum(y)) or (x == 0 and y == 0) or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x, y
end

function Coords.Text()
    local map = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    if type(map) ~= "number" then return nil end
    local px, py = Coords.Player(map)
    local player = px and G.FormatCoords(px, py, 1) or "--"
    local cursor = "--"
    local container = WorldMapFrame.ScrollContainer
    if container and container.IsMouseOver and container:IsMouseOver() and WorldMapFrame.GetNormalizedCursorPosition then
        local cx, cy = WorldMapFrame:GetNormalizedCursorPosition()
        if IsNum(cx) and IsNum(cy) then cursor = G.FormatCoords(cx, cy, 1) or "--" end
    end
    return "Player  " .. player .. "      Cursor  " .. cursor
end

function Coords.Tick(elapsed)
    Coords.acc = Coords.acc + (IsNum(elapsed) and elapsed or 0)
    if Coords.acc < COORDS_INTERVAL then return end
    Coords.acc = 0
    local f = Coords.frame
    local hide = Coords.QuestieShows()
    if hide ~= Coords.suppressed then
        Coords.suppressed = hide
        f.bg:SetShown(not hide)
        f.text:SetShown(not hide)
    end
    if hide then return end
    local text = Coords.Text()
    if text and text ~= Coords.last then
        Coords.last = text
        Coords.writes = Coords.writes + 1
        f.text:SetText(text)
        local width = f.text.GetStringWidth and f.text:GetStringWidth()
        if IsNum(width) and width > 0 then f:SetWidth(width + 16) end
    end
end

-- ---------------------------------------------------------------------------
-- A refusal said on the map
-- ---------------------------------------------------------------------------
-- The maximized map (TBC's default) is FULLSCREEN strata with an opaque
-- BlackoutFrame over all of UIParent, the chat frame included: "Zoom in to
-- place an order" in chat was seen only once the map closed (review:
-- surfaces). Over the top of the map instead, for a few seconds, over
-- QuestLog's drawer too; Refuse also prints it.
function Notice.Build()
    if Notice.frame then return Notice.frame end
    local container = WorldMapFrame and WorldMapFrame.ScrollContainer
    if not (container and CreateFrame) then return nil end
    local f = CreateFrame("Frame", nil, WorldMapFrame)
    f:SetSize(320, 22)
    f:SetPoint("TOP", container, "TOP", 0, -36)
    f:EnableMouse(false)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(0, 0, 0, 0.7)
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.bg, f.text = bg, text
    f:SetScript("OnUpdate", Guarded(function(self, elapsed)
        Notice.left = Notice.left - (IsNum(elapsed) and elapsed or 0)
        if Notice.left <= 0 then self:Hide() end
    end))
    f:Hide()
    Notice.frame = f
    return f
end

function Notice.Show(msg)
    local f = Notice.frame or Notice.Build()
    if not (f and MapShown()) then return false end
    f:SetFrameLevel(OverLevel() + LEVEL_OVER_DRAWER + 2)
    f.text:SetText(msg)
    local width = f.text.GetStringWidth and f.text:GetStringWidth()
    if IsNum(width) and width > 0 then f:SetWidth(width + 24) end
    Notice.left = NOTICE_SECONDS
    f:Show()
    return true
end

-- ---------------------------------------------------------------------------
-- The hooks the runtime calls (guarded on its side)
-- ---------------------------------------------------------------------------
function P.Refresh()
    Mini.Rebuild()
    World.Refresh()
    Overlay.Update()
    Coords.Update()
end

function P.OnTarget(uid)
    S.target, S.targetKnown = uid, true
end

-- For the manager and the harness: drop a waypoint where a map point is
P.PlaceOnMap = function(map, nx, ny) return Overlay.Place(map, nx, ny) end

-- The harness reads the insides
function P._Internals()
    return { Mini = Mini, World = World, Overlay = Overlay, Coords = Coords, Notice = Notice, S = S,
             TEMPLATE = PIN_TEMPLATE, OverLevel = OverLevel }
end

-- ---------------------------------------------------------------------------
-- Attachment and events
-- ---------------------------------------------------------------------------
local function OnMapShow()
    Overlay.Update()
    Coords.Update()
    World.WatchDrawer()
    if not World.drawerHooked and C_Timer and C_Timer.After then
        C_Timer.After(0, World.WatchDrawerGuarded)
    end
end

local function OnMapHide()
    if World.dragging then EndDrag(World.dragging) end
    World.pending = nil
    if Notice.frame then Notice.frame:Hide() end
    Overlay.Update()
    Coords.Update()
end

-- Blizzard_WorldMap is loaded by login on this client; ADDON_LOADED is the
-- second chance should that ever change. The hooks go in once.
local function Attach()
    if S.attached then return true end
    if not (WorldMapFrame and WorldMapFrame.ScrollContainer and WorldMapFrame.HookScript) then return false end
    S.attached = true
    World.Build()
    Overlay.Build()
    Coords.Build()
    WorldMapFrame:HookScript("OnShow", Guarded(OnMapShow))
    WorldMapFrame:HookScript("OnHide", Guarded(OnMapHide))
    if MapShown() then
        World.Refresh()
        OnMapShow()
    end
    return true
end

local HANDLERS = {}

function HANDLERS.PLAYER_LOGIN()
    Attach()
    Mini.Driver()
    P.Refresh()
end

function HANDLERS.ADDON_LOADED(name)
    if name == "Blizzard_WorldMap" and S.loggedIn then Attach() end
end

function HANDLERS.PLAYER_REGEN_ENABLED()
    if Overlay.passPending then Overlay.TryPassThrough() end
    Overlay.Update()
end

function HANDLERS.MODIFIER_STATE_CHANGED()
    Overlay.Update()
end

HANDLERS.MINIMAP_UPDATE_ZOOM = function() Mini.ViewChanged() end
HANDLERS.ZONE_CHANGED_INDOORS = function() Mini.ViewChanged() end
HANDLERS.CVAR_UPDATE = function() Mini.ViewChanged() end
HANDLERS.ZONE_CHANGED = function() Mini.Rebuild() end
HANDLERS.ZONE_CHANGED_NEW_AREA = function() Mini.Rebuild() end
HANDLERS.PLAYER_ENTERING_WORLD = function() Mini.Rebuild() end

if CreateFrame then
    local events = CreateFrame("Frame")
    for event in pairs(HANDLERS) do events:RegisterEvent(event) end
    events:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_LOGIN" then S.loggedIn = true end
        if not S.loggedIn then return end
        local fn = HANDLERS[event]
        if not fn then return end
        local ok, err = pcall(fn, ...)
        if not ok then Report(err) end
    end)
end
