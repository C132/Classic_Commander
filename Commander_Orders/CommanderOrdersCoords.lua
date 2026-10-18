-- Commander Orders: your coordinates (3.1, SPEC 4 COORDS).
--
-- Before 3.1 a player of this suite saw no coordinates at all by default:
-- the TopBar segment was off, Questie's minimap numbers were written into a
-- zone text Commander_Minimap hides, and Orders' world-map readout stepped
-- aside for Questie's (critic 2). This file is the cure, in two parts:
--
--   * the COORDINATE BLOCK: a small plate on the suite's HUD chrome (prefix
--     "Coords": style, scale, lock, position; a solid plate under the Orders
--     arrow's default box) showing where you stand, "42.0, 65.5", over the
--     subzone and the zone. "--" inside instances and wherever the client
--     gives no position. OFF by default (CoordsBlock, D39): Commander_
--     Minimap's label is the default surface. /corder coords toggles it.
--   * the GESTURES every coordinate surface shares (one rule, SPEC 1; the
--     block, Commander_Minimap's label under its zone name, the TopBar's
--     coordinates, Orders' chat links): Left = a waypoint where you stand,
--     Shift = share it (into the chat box you are typing in, else your
--     group's chat or /say, as Orders' readable line), Ctrl = copy a /way
--     line, Right = a menu.
--
-- Commander_Minimap hosts the minimap half: its label asks C.MinimapText(),
-- its clicks go to C.Gesture(), and its Ctrl+Right-click wrapper asks
-- C.WantsMinimapClick() and then C.MinimapClick(Minimap).
--
-- ---------------------------------------------------------------------------
-- The traps
-- ---------------------------------------------------------------------------
-- * NO VECTOR FIVE TIMES A SECOND. C_Map.GetPlayerMapPosition allocates a
--   Vector2D a call (the old module's 19 KB/s; the runtime's own rule is one
--   map position a second). The block reads UnitPosition (plain numbers)
--   and turns it into map coordinates through the map's world rectangle,
--   read ONCE per map from two GetWorldPosFromMapPos probes and kept (a zone
--   map is linear in north and west; Commander_Ping's minimap inverse rests
--   on the same fact). In a battleground with no UnitPosition the runtime's
--   hedge answers (D6: the map position, at most ten times a second).
-- * ZONE NUMBERS. GetBestMapForUnit can be a cave, a city's sub-map or a
--   dungeon level. The block, the minimap label and every gesture speak in
--   the ZONE's coordinates (Geo.Zone), the ones the world map, Questie,
--   TomTom users and every /way line in chat use (coords 4.2); the map
--   itself only where the zone's rectangle does not hold you.
-- * THE TAXI. An unconditional 0.2 s throttle, written only when the text
--   changes (critic 1.6). PLAYER_STARTED_MOVING is player input: taxis,
--   boats, zeppelins, knockbacks and falls move you without it.
-- * HUD CHROME (D10). The chrome's first apply calls SetPassThroughButtons,
--   which is protected and refused in combat without an error, so the block
--   is first chromed at PLAYER_LOGIN out of combat, or on the first
--   PLAYER_REGEN_ENABLED after a login in combat. The root's mouse is the
--   chrome's; the click surface is a child Button (`hit`) five levels up,
--   under the chrome's drag overlay (+20), so an unlocked block still drags.
--   Nothing here is secure, nothing is named (no new global), and nothing
--   about the layout changes in combat.
-- * THE MINIMAP PING. Blizzard's Minimap_OnClick pings for ANY button
--   (Classic/Minimap.lua:130-141), so Commander_Minimap's wrapper skips it
--   when the gesture is ours: no ping reaches the group, and Commander_Ping
--   (IncludeOwnPings) echoes no second waypoint. Minimap_OnClick tests a
--   CIRCLE; the square map's corners are part of the map, so the placement
--   here takes the square when GetMinimapShape() says SQUARE. The offset is
--   turned back by your facing under rotateMinimap: the exact inverse of
--   Geo.MinimapPlace's forward turn.
-- * D11. No shape glyphs in any drawn text (" - ", never a middle dot).
--
-- ---------------------------------------------------------------------------
-- What this file adds: CommanderOrders.Coords (O.Coords) only. No global, no
-- named frame. Settings read (all in CommanderOrdersDB.lua's defaults):
-- EnableOrders, CoordsBlock and the chrome keys CoordsStyle / CoordsScale /
-- CoordsLocked / CoordsPos, CoordDecimals, MinimapCoords, MinimapClick.
--
--   C.Read() -> map, x, y | nil       where you stand, in zone numbers (0..1)
--   C.Text([decimals]) -> "42.0, 65.5" | "--"
--   C.Here() -> { map, x, y, title } | nil, reason   (title: a non-player
--                                     target's name, TomTom's habit, else nil)
--   C.Gesture(button, opts)           opts.surface = "block" | "minimap" |
--                                     anything else; opts.spec overrides Here
--   C.Tooltip(owner, opts)            the coordinate surfaces' hover card
--   C.Waypoint([spec]), C.Share([spec]), C.Copy([spec]), C.Menu(opts)
--   C.MinimapText() -> text | nil (nil: hide the label)
--   C.WantsMinimapClick() -> bool, C.MinimapPoint(minimap) -> spec | nil,
--   reason, C.MinimapClick(minimap) -> uid | nil, reason
--   C.Command(rest)                   "/corder coords ..." (the runtime's
--                                     COMMANDS.coords calls it)
--   C._Internals()                    the harness reads the block's insides
-- ---------------------------------------------------------------------------

CommanderOrders = CommanderOrders or {}
local O = CommanderOrders
O.Coords = O.Coords or {}
local C = O.Coords
local G = O.Geo

local type, pairs, ipairs, pcall, tostring, tonumber = type, pairs, ipairs, pcall, tostring, tonumber
local abs, cos, sin = math.abs, math.cos, math.sin
local HUGE = math.huge

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------
local PREFIX = "Coords"                     -- the HUD chrome's keys
-- Under the Orders arrow's default box (Data.ARROW: TOP +240, -340, 190 x
-- 158, so its bottom is 498 down), centred on it with a 6 px gap: the two
-- navigation readouts sit together. NOT under the minimap (3.1's first
-- spot, TOPRIGHT -21, -208): 2.5.6 manages the quest tracker
-- (QuestWatchFrame, UIParentRightManagedFrameTemplate) in a right-aligned
-- column from 192 down the right edge, up to about 290 wide, and its lines
-- 2 to 5 drew over the block (review: render). Clear of the right column,
-- of the top-centre toast band (110..330 down) and of the centred cast bar.
local DEFAULT_POINT = { point = "TOP", x = 240, y = -504 }
local BLOCK_W = 150
local BLOCK_H_TWO, BLOCK_H_THREE = 38, 50   -- coordinates + one or two place lines
local BLOCK_H_UNLOCKED = 62                 -- the numbers over the chrome's centred drag label
local INTERVAL = 0.2                        -- seconds between reads (critic 1.6)
local NONE = "--"
local EDGE = 0.001                          -- a zone's rectangle, give or take
local HIT_LIFT = 5                          -- under the chrome's drag overlay (+20)
local ZONE_TEXT = { 0.72, 0.74, 0.78 }
local HINT = { 0.60, 0.80, 1.00 }
local WARN = { 1.00, 0.30, 0.25 }

-- Everything kept between calls
local S = {
    rects = {},                             -- map -> world rectangle | false
    readAt = nil, map = nil, x = nil, y = nil,
    reads = 0, probes = 0,
}
local B = { acc = 0, writes = 0, text = {}, placeDirty = true, chromeReady = false, chromePending = false }

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------
local function IsNum(v)
    return type(v) == "number" and v == v and v ~= HUGE and v ~= -HUGE
end

local function Report(err)
    B.lastError = tostring(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler(err) end
end

-- A script that fails must not take the HUD or the minimap with it
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

local function DB()
    local r = Rt()
    local db = r and r.DB and r.DB()
    if type(db) == "table" then return db end
    return O.Defaults or {}
end

local function Setting(key)
    return DB()[key]
end

-- Orders is on and has its store
local function Ready()
    local r = Rt()
    return r ~= nil and r.Store() ~= nil and Setting("EnableOrders") and true or false
end

-- Why it is not: still loading, or turned off (Data.REASONS codes)
local function NotReadyWhy()
    local r = Rt()
    if not (r and r.Store()) then return "loading" end
    return "disabled"
end

local function Say(msg)
    local r = Rt()
    if r and r.Say then r.Say(msg) elseif print then print("Commander Orders: " .. msg) end
end

local function Reason(why)
    if type(O.Reason) == "function" then
        local text = O.Reason(why)
        if type(text) == "string" then return text end
    end
    return tostring(why)
end

local function Env()
    local r = Rt()
    return r and r.Env() or {}
end

local function Decimals()
    local r = Rt()
    if r and r.Decimals then
        local d = r.Decimals()
        if IsNum(d) then return d end
    end
    return 1
end

local function MapName(map)
    local r = Rt()
    return r and r.MapName and r.MapName(map) or nil
end

local function CVar(name)
    local fn = (C_CVar and C_CVar.GetCVar) or GetCVar
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, name)
    if ok then return v end
    return nil
end

local function Shape()
    if type(GetMinimapShape) ~= "function" then return "ROUND" end
    local ok, s = pcall(GetMinimapShape)
    if ok and type(s) == "string" then return s end
    return "ROUND"
end

local function Notify()
    if O.DB and O.DB.Notify then O.DB.Notify() end
end

local function InGroup()
    return IsInGroup and IsInGroup() and true or false
end

-- "instance" inside a dungeon or raid (no position by design), else "no position"
local function NoPositionWhy()
    if IsInInstance then
        local inside, kind = IsInInstance()
        if inside and kind ~= "pvp" then return "instance" end
    end
    return "no position"
end

local function Text(fn)
    if type(fn) ~= "function" then return nil end
    local ok, s = pcall(fn)
    if ok and type(s) == "string" and s ~= "" then return s end
    return nil
end

-- ---------------------------------------------------------------------------
-- Where you stand, without a Vector2D
-- ---------------------------------------------------------------------------
-- A map's world rectangle from two probes, kept for the session (a map's
-- rectangle never changes): the instance, north and west at x = y = 0, and
-- how far they run across the map. Probed inside the map (0.25 / 0.75), so
-- a row whose UI square starts past 0 still answers.
function C.Rect(map)
    if type(map) ~= "number" then return nil end
    local r = S.rects[map]
    if r == nil then
        r = false
        local env = Env()
        S.probes = S.probes + 1
        local i1, n1, w1 = G.ToWorld(env, map, 0.25, 0.25)
        local i2, n2, w2 = G.ToWorld(env, map, 0.75, 0.75)
        if i1 ~= nil and i1 == i2 and n1 ~= n2 and w1 ~= w2 then
            local dn, dw = (n2 - n1) / 0.5, (w2 - w1) / 0.5
            r = { inst = i1, n0 = n1 - 0.25 * dn, w0 = w1 - 0.25 * dw, dn = dn, dw = dw,
                  area = abs(dn * dw) }
        end
        S.rects[map] = r
    end
    return r or nil
end

-- x, y on `map` of a world point, when the map holds it
function C.MapXY(map, inst, north, west)
    local r = C.Rect(map)
    if not (r and r.inst == inst) then return nil end
    local x, y = (west - r.w0) / r.dw, (north - r.n0) / r.dn
    if x < -EDGE or x > 1 + EDGE or y < -EDGE or y > 1 + EDGE then return nil end
    if x < 0 then x = 0 elseif x > 1 then x = 1 end
    if y < 0 then y = 0 elseif y > 1 then y = 1 end
    return x, y
end

-- A world point as map, x, y: the zone of the map you stand on, that map
-- itself, and (wide = true: a minimap click past the zone's edge) the zones
-- beside it, smallest first. Commander_Ping's order, for the same reason: the
-- continent cannot place a point across the Thalassian border (Eversong and
-- Ghostlands are 530, the Eastern Kingdoms map's own frame is 0), a
-- neighbouring zone can.
function C.WorldToMap(inst, north, west, best, wide)
    if not (IsNum(north) and IsNum(west) and inst ~= nil and type(best) == "number") then return nil end
    local env = Env()
    local zone = G.Zone(env, best) or best
    local x, y = C.MapXY(zone, inst, north, west)
    if x then return zone, x, y end
    if zone ~= best then
        x, y = C.MapXY(best, inst, north, west)
        if x then return best, x, y end
    end
    if not wide then return nil end
    local info = env.mapInfo and env.mapInfo(zone)
    local parent = type(info) == "table" and info.parentMapID
    local kids = type(parent) == "number" and env.mapChildren and env.mapChildren(parent)
    if type(kids) ~= "table" then return nil end
    local bestMap, bestArea, bx, by
    for _, kid in ipairs(kids) do
        local id = type(kid) == "table" and kid.mapID
        if type(id) == "number" and id ~= zone and kid.mapType == G.MAP_TYPE.ZONE then
            local kx, ky = C.MapXY(id, inst, north, west)
            local r = kx and C.Rect(id)
            if r and (not bestMap or r.area < bestArea) then
                bestMap, bestArea, bx, by = id, r.area, kx, ky
            end
        end
    end
    if bestMap then return bestMap, bx, by end
    return nil
end

-- map, x, y where you stand (zone numbers), or nil; read once per frame
-- whoever asks (the block and the minimap label share it)
function C.Read()
    local now = GetTime and GetTime() or 0
    if S.readAt == now then return S.map, S.x, S.y end
    S.readAt = now
    S.map, S.x, S.y = nil, nil, nil
    local r = Rt()
    if not r then return nil end
    S.reads = S.reads + 1
    local north, west, inst = r.PlayerWorld()
    if not north then return nil end
    local best = r.PlayerMap()
    if not best then return nil end
    S.map, S.x, S.y = C.WorldToMap(inst, north, west, best, false)
    return S.map, S.x, S.y
end

function C.Text(decimals)
    local map, x, y = C.Read()
    if not map then return NONE end
    return G.FormatCoords(x, y, decimals or Decimals()) or NONE
end

-- The subzone and the zone you are in (either may be nil)
function C.Place()
    local zone = Text(GetZoneText) or Text(GetRealZoneText)
    if not zone then
        local map = C.Read()
        zone = map and MapName(map) or nil
    end
    local sub = Text(GetSubZoneText)
    if sub == zone then sub = nil end
    return sub, zone
end

local function PlaceWords()
    local sub, zone = C.Place()
    if sub and zone then return sub .. " - " .. zone end
    return sub or zone or "Your position"
end

-- The spot a gesture acts on: where you stand, named after the creature you
-- target (TomTom's habit), else left for Orders to name ("Zone x, y")
function C.Here()
    if not Ready() then return nil, NotReadyWhy() end
    local map, x, y = C.Read()
    if not map then return nil, NoPositionWhy() end
    local title
    if UnitExists and UnitExists("target") and not (UnitIsPlayer and UnitIsPlayer("target")) then
        local name = UnitName and UnitName("target")
        if type(name) == "string" and name ~= "" then title = name end
    end
    return { map = map, x = x, y = y, title = title }
end

-- ---------------------------------------------------------------------------
-- The gestures (SPEC 1: one rule for every coordinate surface)
-- ---------------------------------------------------------------------------
local function Spot(spec)
    if type(spec) == "table" and type(spec.map) == "number" then return spec end
    local here, why = C.Here()
    if not here then Say(Reason(why)) end
    return here, why
end

-- Left: a waypoint here, and the arrow on it (born where you stand, it waits
-- until you have walked away before it can arrive: the Store's arming rule)
function C.Waypoint(spec)
    local p, why = Spot(spec)
    if not p then return nil, why end
    local uid, err = O.Add({ map = p.map, x = p.x, y = p.y, title = p.title, source = "user", setArrow = true })
    if not uid then Say("could not set a waypoint here: " .. Reason(err)) end
    return uid, err
end

-- Shift: into the chat box being typed in (the readable line, never a link:
-- links are local only), else Orders' share in chat (your group's, or /say)
function C.Share(spec)
    local p, why = Spot(spec)
    if not p then return nil, why end
    local line = O.ChatText and O.ChatText(p.map, p.x, p.y, p.title)
    local util = ChatFrameUtil
    local active = util and util.GetActiveWindow and util.GetActiveWindow()
    if not active and ChatEdit_GetActiveWindow then active = ChatEdit_GetActiveWindow() end
    if active and type(line) == "string" then
        if util and util.InsertLink then
            util.InsertLink(line)
        elseif active.Insert then
            active:Insert(line)
        end
        return true
    end
    local ok, err = O.SharePoint({ map = p.map, x = p.x, y = p.y, title = p.title }, "CHAT")
    if not ok then Say("could not share: " .. Reason(err)) end
    return ok, err
end

-- Ctrl: the /way line in Orders' copy box
function C.Copy(spec)
    local p, why = Spot(spec)
    if not p then return nil, why end
    return O.CopyText(O.WayLineFor(p.map, p.x, p.y, p.title))
end

local function SetDecimals(d)
    DB().CoordDecimals = d
    Notify()
end

local function DecimalWords(d)
    if d == 0 then return "0 decimals (45, 66)" end
    if d == 2 then return "2 decimals (45.25, 66.80)" end
    return "1 decimal (45.2, 66.8)"
end

-- Right: the menu (R.ShowMenu: { text, func, isTitle, disabled })
function C.Menu(opts)
    opts = type(opts) == "table" and opts or {}
    local r = Rt()
    if not (r and r.ShowMenu) then return false end
    local surface = opts.surface
    local p = type(opts.spec) == "table" and opts.spec or C.Here()
    local none = p == nil
    local entries = { { text = PlaceWords(), isTitle = true } }
    entries[#entries + 1] = { text = "Waypoint here", disabled = none, func = function() C.Waypoint(p) end }
    entries[#entries + 1] = { text = "Share in chat", disabled = none, func = function() C.Share(p) end }
    if InGroup() then
        entries[#entries + 1] = { text = "Send to your group", disabled = none, func = function()
            if not p then return end
            local ok, err = O.SharePoint({ map = p.map, x = p.x, y = p.y, title = p.title })
            if not ok then Say("could not share: " .. Reason(err)) end
        end }
    end
    entries[#entries + 1] = { text = "Copy /way line", disabled = none, func = function() C.Copy(p) end }
    local now = Decimals()
    for d = 0, 2 do
        entries[#entries + 1] = { text = DecimalWords(d), disabled = d == now, func = function() SetDecimals(d) end }
    end
    if surface == "block" then
        local locked = Setting(PREFIX .. "Locked") ~= false
        entries[#entries + 1] = { text = locked and "Unlock to move" or "Lock in place",
            func = function() C.Command(locked and "unlock" or "lock") end }
        entries[#entries + 1] = { text = "Hide this block", func = function() C.Command("hide") end }
    elseif surface == "minimap" then
        entries[#entries + 1] = { text = "Hide the minimap coordinates", func = function()
            DB().MinimapCoords = false
            Notify()
            Say("minimap coordinates hidden (Map & Minimap in /corder brings them back)")
        end }
    end
    -- the block is opt-in (D39): every other surface offers it
    if surface ~= "block" and Setting("CoordsBlock") ~= true then
        entries[#entries + 1] = { text = "Show the coordinate block", func = function() C.Command("show") end }
    end
    entries[#entries + 1] = { text = "Open the manager", func = function() O.OpenManager() end }
    return r.ShowMenu(entries, opts.anchor or "cursor")
end

-- One click on a coordinate surface. Returns what the action returned.
function C.Gesture(button, opts)
    opts = type(opts) == "table" and opts or {}
    if not Ready() then
        local why = NotReadyWhy()
        Say(Reason(why))
        return nil, why
    end
    if button == "RightButton" then return C.Menu(opts) end
    local spec = type(opts.spec) == "table" and opts.spec or nil
    if IsShiftKeyDown and IsShiftKeyDown() then return C.Share(spec) end
    if IsControlKeyDown and IsControlKeyDown() then return C.Copy(spec) end
    return C.Waypoint(spec)
end

-- The hover card of a coordinate surface
function C.Tooltip(owner, opts)
    if not (GameTooltip and owner) then return end
    opts = type(opts) == "table" and opts or {}
    GameTooltip:SetOwner(owner, opts.anchor or "ANCHOR_LEFT")
    GameTooltip:SetText(PlaceWords(), 1, 1, 1)
    if not Ready() then
        GameTooltip:AddLine(Reason(NotReadyWhy()), WARN[1], WARN[2], WARN[3], true)
        GameTooltip:Show()
        return
    end
    local map, x, y = C.Read()
    if map then
        GameTooltip:AddLine((MapName(map) or ("map #" .. map)) .. " " .. (G.FormatCoords(x, y, Decimals()) or ""),
            0.8, 0.8, 0.8)
        GameTooltip:AddLine("Click: a waypoint where you stand", HINT[1], HINT[2], HINT[3])
        GameTooltip:AddLine("Shift-click: share in chat. Ctrl-click: copy a /way line.", HINT[1], HINT[2], HINT[3], true)
    else
        GameTooltip:AddLine(Reason(NoPositionWhy()), WARN[1], WARN[2], WARN[3], true)
    end
    GameTooltip:AddLine("Right-click: menu", HINT[1], HINT[2], HINT[3])
    GameTooltip:Show()
end

-- ---------------------------------------------------------------------------
-- The minimap (Commander_Minimap's label and its Ctrl+Right-click)
-- ---------------------------------------------------------------------------
-- The label's text, or nil to hide it
function C.MinimapText()
    if not Ready() or Setting("MinimapCoords") == false then return nil end
    return C.Text()
end

function C.WantsMinimapClick()
    return Ready() and Setting("MinimapClick") ~= false
end

-- The spot under the cursor on the minimap: { map, x, y } | nil, reason
-- ("outside": not on the map's face, nothing is said)
function C.MinimapPoint(minimap)
    minimap = minimap or Minimap
    if not (minimap and minimap.GetCenter and GetCursorPosition) then return nil, "nomap" end
    local scale = minimap.GetEffectiveScale and minimap:GetEffectiveScale()
    if not IsNum(scale) or scale <= 0 then scale = 1 end
    local cx, cy = GetCursorPosition()
    local mx, my = minimap:GetCenter()
    if not (IsNum(cx) and IsNum(cy) and IsNum(mx) and IsNum(my)) then return nil, "nomap" end
    local dx, dy = cx / scale - mx, cy / scale - my
    local halfW = (minimap:GetWidth() or 0) / 2
    local halfH = (minimap:GetHeight() or 0) / 2
    if not (IsNum(halfW) and halfW > 0) then return nil, "nomap" end
    if not (IsNum(halfH) and halfH > 0) then halfH = halfW end
    if Shape() == "SQUARE" then
        if abs(dx) > halfW or abs(dy) > halfH then return nil, "outside" end
    elseif (dx / halfW) * (dx / halfW) + (dy / halfH) * (dy / halfH) > 1 then
        return nil, "outside"
    end
    local r = Rt()
    if not r then return nil, "loading" end
    local north, west, inst = r.PlayerWorld()
    local best = r.PlayerMap()
    if not (north and best) then return nil, NoPositionWhy() end
    local zoom = minimap.GetZoom and minimap:GetZoom() or 0
    local indoors = G.MinimapIndoors(zoom, CVar("minimapZoom"), CVar("minimapInsideZoom"), IsIndoors and IsIndoors())
    local radius = G.MinimapRadius(zoom, indoors)
    if not (IsNum(radius) and radius > 0) then return nil, "nomap" end
    -- yards to the right (east) and up (north) of you; the rim is the radius
    local right, up = dx / halfW * radius, dy / halfH * radius
    if CVar("rotateMinimap") == "1" then
        local facing = r.Facing()
        if not IsNum(facing) then return nil, "no position" end
        local c, s = cos(facing), sin(facing)
        right, up = right * c - up * s, right * s + up * c
    end
    local map, x, y = C.WorldToMap(inst, north + up, west - right, best, true)
    if not map then return nil, "nomap" end
    return { map = map, x = x, y = y }
end

-- Ctrl+Right-click on the minimap: a waypoint there, the arrow on it
function C.MinimapClick(minimap)
    if not Ready() then return nil, NotReadyWhy() end
    local spec, why = C.MinimapPoint(minimap)
    if not spec then
        if why ~= "outside" then Say("no waypoint there: " .. Reason(why)) end
        return nil, why
    end
    local uid, err = O.Add({ map = spec.map, x = spec.x, y = spec.y, source = "user", setArrow = true })
    if not uid then Say("could not put a waypoint there: " .. Reason(err)) end
    return uid, err
end

-- ---------------------------------------------------------------------------
-- The coordinate block
-- ---------------------------------------------------------------------------
local function SetText(region, key, text)
    text = text or ""
    if B.text[key] ~= text then
        B.text[key] = text
        region:SetText(text)
        return true
    end
    return false
end

local function Unlocked()
    local UI = Commander and Commander.UI
    if UI and UI.HudUnlocked then return UI.HudUnlocked(DB(), PREFIX) and true or false end
    return Setting(PREFIX .. "Locked") == false
end

function B.Build()
    if B.root or not CreateFrame then return B.root end
    -- unnamed: no global (the runtime harness's rule), and Commander_
    -- Minimap's tidy, which collects by name, never sees it
    local root = CreateFrame("Frame", nil, UIParent)
    root:SetSize(BLOCK_W, BLOCK_H_TWO)
    root:SetFrameStrata("LOW")
    root:SetPoint(DEFAULT_POINT.point, UIParent, DEFAULT_POINT.point, DEFAULT_POINT.x, DEFAULT_POINT.y)
    root:EnableMouse(false)
    root:Hide()

    local coords = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    coords:SetPoint("TOP", root, "TOP", 0, -4)
    coords:SetJustifyH("CENTER")
    if coords.SetWordWrap then coords:SetWordWrap(false) end

    local sub = root:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sub:SetPoint("TOP", coords, "BOTTOM", 0, -2)
    sub:SetWidth(BLOCK_W - 8)
    sub:SetJustifyH("CENTER")
    if sub.SetWordWrap then sub:SetWordWrap(false) end

    local zone = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    zone:SetPoint("TOP", sub, "BOTTOM", 0, -1)
    zone:SetWidth(BLOCK_W - 8)
    zone:SetJustifyH("CENTER")
    if zone.SetWordWrap then zone:SetWordWrap(false) end
    zone:SetTextColor(ZONE_TEXT[1], ZONE_TEXT[2], ZONE_TEXT[3])

    -- the click surface (the chrome owns the root's mouse)
    local hit = CreateFrame("Button", nil, root)
    hit:SetAllPoints(root)
    hit:SetFrameLevel((root:GetFrameLevel() or 1) + HIT_LIFT)
    hit:EnableMouse(true)
    if hit.RegisterForClicks then hit:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    hit:SetScript("OnClick", Guarded(function(self, button)
        C.Gesture(button, { surface = "block", anchor = "cursor" })
    end))
    hit:SetScript("OnEnter", Guarded(function(self) C.Tooltip(self, { surface = "block" }) end))
    hit:SetScript("OnLeave", function(self)
        if GameTooltip and (not GameTooltip.GetOwner or GameTooltip:GetOwner() == self) then GameTooltip:Hide() end
    end)

    root:SetScript("OnUpdate", Guarded(function(_, elapsed) B.Tick(elapsed) end))
    B.root, B.coords, B.sub, B.zone, B.hit = root, coords, sub, zone, hit
    return root
end

-- First apply out of combat only (see the header)
function B.ApplyChrome()
    local root = B.root
    local UI = Commander and Commander.UI
    if not (root and UI and UI.ApplyHudChrome) then return end
    if not B.chromeReady and InCombatLockdown and InCombatLockdown() then
        B.chromePending = true
        return
    end
    UI.ApplyHudChrome(root, DB(), PREFIX, { defaultPoint = DEFAULT_POINT, title = "Coordinates" })
    B.chromeReady, B.chromePending = true, false
    -- the chrome locks on a right-click of its drag overlay (and on the
    -- Window style's lock button) by itself, without the settings event
    local overlay = root._hudDragOverlay
    if overlay and not B.overlayHooked and overlay.HookScript then
        B.overlayHooked = true
        overlay:HookScript("OnMouseUp", Guarded(function() B.Refresh(true) end))
    end
    local win = root._hudWindow
    if win and win.lockButton and not B.lockHooked and win.lockButton.HookScript then
        B.lockHooked = true
        win.lockButton:HookScript("OnClick", Guarded(function() B.Refresh(true) end))
    end
    if B.hit then B.hit:SetFrameLevel((root:GetFrameLevel() or 1) + HIT_LIFT) end
end

-- Shown: unlocked (a frame to drag, the chrome's rule), or Orders on with
-- the block wanted
function B.Want()
    if not B.root then return false end
    if Unlocked() then return true end
    return Ready() and Setting("CoordsBlock") == true
end

-- After a settings change; noChrome when the chrome has just applied itself
function B.Refresh(noChrome)
    if not B.root then return end
    if not noChrome then B.ApplyChrome() end
    local want = B.Want()
    if want then
        B.acc = INTERVAL                      -- written on the next frame
        B.placeDirty = true
        if not B.root:IsShown() then B.root:Show() end
    elseif B.root:IsShown() then
        B.root:Hide()
    end
end

-- The two place lines: the subzone (gold) over the zone (grey); the zone
-- alone in gold when there is no subzone. Unlocked, both are left blank and
-- the block grows to 62: the chrome's own drag overlay writes its "drag,
-- right-click locks" across the middle, and at 50 it ran into the numbers
-- (render: a placeholder of ours ran straight through it too).
function B.WritePlace()
    local subText, zoneText
    local unlocked = Unlocked()
    if unlocked then
        subText, zoneText = "", ""
    else
        local sub, zone = C.Place()
        if sub then subText, zoneText = sub, zone else subText, zoneText = zone or "", nil end
    end
    local changed = SetText(B.sub, "sub", subText)
    changed = SetText(B.zone, "zone", zoneText or "") or changed
    local three = zoneText ~= nil and zoneText ~= ""
    if B.zone.SetShown then B.zone:SetShown(three) end
    local h = unlocked and BLOCK_H_UNLOCKED or (three and BLOCK_H_THREE or BLOCK_H_TWO)
    if B.height ~= h then
        B.height = h
        B.root:SetHeight(h)
    end
    return changed
end

function B.Tick(elapsed)
    B.acc = B.acc + (IsNum(elapsed) and elapsed or 0)
    if B.acc < INTERVAL then return end
    B.acc = 0
    local wrote = SetText(B.coords, "coords", C.Text())
    if B.placeDirty then
        B.placeDirty = false
        wrote = B.WritePlace() or wrote
    end
    if wrote then B.writes = B.writes + 1 end
end

-- ---------------------------------------------------------------------------
-- /corder coords
-- ---------------------------------------------------------------------------
local USAGE = "/corder coords [on | off | lock | unlock | reset | 0 | 1 | 2 | where]: the coordinate block"

local function Show(on)
    DB().CoordsBlock = on and true or false
    Notify()
    Say(on and "coordinate block shown" or "coordinate block hidden (/corder coords brings it back)")
end

function C.Command(rest)
    local word = type(rest) == "string" and rest:lower():match("^%s*(%S*)") or ""
    if word == "" then
        Show(Setting("CoordsBlock") ~= true)
    elseif word == "on" or word == "show" then
        Show(true)
    elseif word == "off" or word == "hide" then
        Show(false)
    elseif word == "lock" or word == "unlock" then
        DB()[PREFIX .. "Locked"] = word == "lock"
        if word == "unlock" then DB().CoordsBlock = true end
        Notify()
        Say(word == "lock" and "coordinate block locked"
            or "coordinate block unlocked: drag it into place, then right-click it to lock")
    elseif word == "reset" then
        DB()[PREFIX .. "Pos"] = false
        Notify()
        Say("coordinate block back in its place under the arrow")
    elseif word == "0" or word == "1" or word == "2" then
        SetDecimals(tonumber(word))
        Say("coordinates with " .. DecimalWords(tonumber(word)))
    elseif word == "where" then
        local p, why = C.Here()
        if not p then
            Say(Reason(why))
        else
            local line = (MapName(p.map) or ("map #" .. p.map)) .. " " .. (G.FormatCoords(p.x, p.y, Decimals()) or "")
            local link = O.ChatLink and O.ChatLink(p.map, p.x, p.y, p.title)
            Say("you are at " .. line .. (link and (" " .. link) or ""))
        end
    else
        Say(USAGE)
    end
end

-- The harness reads the insides
function C._Internals()
    return { B = B, S = S, DEFAULT_POINT = DEFAULT_POINT, INTERVAL = INTERVAL, PREFIX = PREFIX }
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local HANDLERS = {}

function HANDLERS.PLAYER_LOGIN()
    B.Build()
    B.Refresh()
    if Commander and Commander.AddListener and COMMANDER_ORDERS_EVENTS and COMMANDER_ORDERS_EVENTS.UPDATE then
        Commander.AddListener(COMMANDER_ORDERS_EVENTS.UPDATE, function() B.Refresh() end)
    end
end

function HANDLERS.PLAYER_REGEN_ENABLED()
    if B.chromePending then B.Refresh() end
end

local function PlaceChanged() B.placeDirty = true end
HANDLERS.ZONE_CHANGED = PlaceChanged
HANDLERS.ZONE_CHANGED_INDOORS = PlaceChanged
HANDLERS.ZONE_CHANGED_NEW_AREA = PlaceChanged

-- A loading screen; and a second chance for a block the login could not
-- show (the store loads at ADDON_LOADED, so it should never be needed)
function HANDLERS.PLAYER_ENTERING_WORLD()
    B.placeDirty = true
    if B.root and not B.root:IsShown() and B.Want() then B.Refresh() end
end

if CreateFrame then
    local events = CreateFrame("Frame")
    for event in pairs(HANDLERS) do events:RegisterEvent(event) end
    events:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_LOGIN" then B.loggedIn = true end
        if not B.loggedIn then return end
        local fn = HANDLERS[event]
        if not fn then return end
        local ok, err = pcall(fn, ...)
        if not ok then Report(err) end
    end)
end
