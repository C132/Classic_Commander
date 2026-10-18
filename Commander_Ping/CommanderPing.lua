-- Commander Ping: RTS-style minimap ping alerts. WoW's native group ping is
-- a tiny blip that is trivially missed; this module reacts to MINIMAP_PING
-- with a sound, a bright expanding ring on the pinged spot, and a chat
-- callout naming the pinger.
--
-- ---------------------------------------------------------------------------
-- A ping you can walk to (Commander Orders)
-- ---------------------------------------------------------------------------
-- With Commander Orders loaded, the callout carries a [Go] link: click it and
-- the arrow points at the pinged spot. The opt-in setting "Waypoint on Group
-- Pings" does it for every ping without the click. Either way it is ONE
-- waypoint (source "Ping", key "ping"): each new ping moves it, it is
-- session-only, and it clears on arrival. The link is Orders' own chat link
-- (Orders 3.1: CommanderOrders.ChatLink, answered by CommanderOrdersChat.lua):
-- the place rides in the link itself, so it still goes somewhere after a
-- /reload; while this session lasts Ping claims its plain click
-- (CommanderOrders.ClaimChatLink) to move the one Ping waypoint, and Shift,
-- Ctrl and Right are Orders' (share, copy the /way line, menu). A reloaded
-- or long-forgotten ping link is Orders' plain Go: a waypoint of yours
-- there. Without Orders' chat file there is no link at all (no link that
-- would do nothing). The words and gestures are Orders' (its DECISIONS,
-- the 3.1 "Go to" entry): "[Go]" in chat, "Waypoint" only the noun.
-- The waypoint goes through CommanderOrders.GoTo (Orders 3.1): a clicked
-- ping says "Waypoint set: ..." or Orders' one refusal line, in Orders'
-- words (CommanderOrders.Reason), so Ping keeps no refusal table of its own;
-- the automatic one says nothing (silent). The automatic one is temporary in
-- Orders' sense and never asks for the arrow: Orders refuses a temporary pin
-- over a pinned waypoint and over a running route, and asking would still
-- re-pin the arrow away from a waypoint of yours followed as the closest and
-- out of a Clear. Unasked, Follow the Closest points at it only when nothing
-- of yours is left on the landmass. The clicked one was asked for, so it is
-- pinned outright.
--
-- The ping arrives as an offset from the minimap's centre, NOT a place, and
-- turning it into one is where the traps are:
--   * Scale. MINIMAP_PING's x, y are fractions of the minimap's WIDTH and
--     HEIGHT (-0.5 .. 0.5; the flash below is drawn at x * width, which in-game
--     testing settled, fb2b1ea3). The rim is therefore 0.5, and 0.5 must be the
--     minimap's radius in yards: yards = 2 * offset * radius. Reading the
--     offset as a fraction of the radius (critic 3.2's W - x * R) puts every
--     ping at half its distance.
--   * Radius. Yards per zoom level come from Commander Orders' Geo (the same
--     table its minimap pins use), indoor or outdoor decided from the zoom
--     CVars without nudging Minimap:SetZoom (Questie and RXP already do).
--   * Direction. Screen right is east, so WEST = west - right; screen up is
--     north, NORTH = north + up. With rotateMinimap on, screen up is the way
--     you face, and the offset is turned back by your facing first: the exact
--     inverse of Geo.MinimapPlace's forward turn, so a pin drawn there would
--     land on the ping.
--   * The map. The world point becomes map coordinates on the map you stand
--     on, through two GetWorldPosFromMapPos probes (a zone map is linear in
--     north and west). A ping past the zone's edge is tried on the zones
--     beside it (the other children of its continent, smallest first), and
--     only then on the continent itself, where Orders turns the point into
--     the zone under it. The neighbours come first because of the 530 frame:
--     Eversong and Ghostlands live in instance 530 while the Eastern Kingdoms
--     map's own frame is instance 0, so the continent cannot place a ping
--     across the Thalassian border, but Ghostlands can. A probe from another
--     world instance never answers for this one.
-- The link is an `addon:` hyperlink, which this client routes through
-- SetItemRef to EventRegistry's "SetItemRef" callback for addon code
-- (Blizzard_UIPanels_Game/Shared/ItemRefHandlersShared.lua), so no chat frame
-- is hooked and no Blizzard function is replaced. Orders' chat file owns that
-- callback; this file registers none of its own.

local FLASH_STEPS = 24
local FLASH_INTERVAL = 0.04
local LINK_TEXT = "Go"                       -- the callout's [Go] (Orders' word for a chat link)
local MAP_CLIMB = 4                          -- parent maps tried past a zone's edge
local MAP_WORLD = 1                          -- Enum.UIMapType.World: never placed on
local MAP_ZONE = 3                           -- Enum.UIMapType.Zone

local flash = CreateFrame("Frame", "CommanderPingFlash", Minimap)
flash:SetSize(28, 28)
flash:SetFrameStrata("HIGH")
flash:Hide()

local ring = flash:CreateTexture(nil, "OVERLAY")
ring:SetAllPoints()
ring:SetTexture("Interface\\Minimap\\UI-Minimap-Ping-Expand")
ring:SetVertexColor(1, 0.9, 0.2, 1)

local flashTicker
local flashStep = 0

local function StopFlash()
    if flashTicker then
        flashTicker:Cancel()
        flashTicker = nil
    end
    flash:Hide()
end

-- x/y from MINIMAP_PING are normalized offsets from the minimap center
-- (-0.5 .. 0.5 on each axis)
local function StartFlash(x, y)
    StopFlash()
    local width, height = Minimap:GetWidth(), Minimap:GetHeight()
    flash:ClearAllPoints()
    flash:SetPoint("CENTER", Minimap, "CENTER", x * width, y * height)
    flashStep = 0
    flash:SetAlpha(1)
    flash:SetSize(20, 20)
    flash:Show()
    flashTicker = C_Timer.NewTicker(FLASH_INTERVAL, function()
        flashStep = flashStep + 1
        if flashStep >= FLASH_STEPS then
            StopFlash()
            return
        end
        -- Ring grows and fades, twice, for a radar-pulse feel
        local phase = (flashStep % (FLASH_STEPS / 2)) / (FLASH_STEPS / 2)
        local size = 20 + phase * 36
        flash:SetSize(size, size)
        flash:SetAlpha(1 - phase * 0.9)
    end)
end

-- Shared with /cping test
function CommanderPing_Test()
    StartFlash(0.15, 0.15)
    if CommanderPingDB.PingSound then
        PlaySound(SOUNDKIT.TELL_MESSAGE, "Master")
    end
    if CommanderPingDB.PingCallout then
        print("|cff40c0ffCommander Ping:|r this is what a group ping looks like")
    end
end

-- ---------------------------------------------------------------------------
-- Where a ping is (see the header for the traps)
-- ---------------------------------------------------------------------------
-- Orders 3.1's API (GoTo is the one way in), or nil
local function Orders()
    local api = CommanderOrders
    if type(api) == "table" and type(api.GoTo) == "function" then return api end
    return nil
end

local function CVar(name)
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
    if GetCVar then return GetCVar(name) end
    return nil
end

-- instance, north, west of a point on a map (vector .x is north)
local function WorldAt(mapID, x, y)
    local ok, instance, v = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if not ok or instance == nil or v == nil then return nil end
    local north, west = v.x, v.y
    if (north == nil or west == nil) and v.GetXY then north, west = v:GetXY() end
    if type(north) ~= "number" or type(west) ~= "number" then return nil end
    return instance, north, west
end

-- A world point on one map: x, y and the map's area in square yards, or nil
-- when it lies off that map or the map is in another world frame. Zone maps
-- are linear: x with -west, y with -north.
local function MapPos(mapID, instance, north, west)
    local i1, n1, w1 = WorldAt(mapID, 0.25, 0.25)
    local i2, n2, w2 = WorldAt(mapID, 0.75, 0.75)
    if i1 == nil or i1 ~= instance or i2 ~= instance or n1 == n2 or w1 == w2 then return nil end
    local x = 0.25 + (west - w1) / (w2 - w1) * 0.5
    local y = 0.25 + (north - n1) / (n2 - n1) * 0.5
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x, y, math.abs((n2 - n1) * (w2 - w1)) * 4
end

-- The smallest zone beside mapID (same parent) holding the point
local function Neighbour(mapID, parent, instance, north, west)
    if not (parent and C_Map.GetMapChildrenInfo) then return nil end
    local ok, kids = pcall(C_Map.GetMapChildrenInfo, parent)
    if not ok or type(kids) ~= "table" then return nil end
    local best, bestArea, bestX, bestY
    for _, kid in ipairs(kids) do
        if type(kid) == "table" and kid.mapType == MAP_ZONE and kid.mapID ~= mapID then
            local x, y, area = MapPos(kid.mapID, instance, north, west)
            if x and (not best or area < bestArea) then
                best, bestArea, bestX, bestY = kid.mapID, area, x, y
            end
        end
    end
    return best, bestX, bestY
end

-- MINIMAP_PING's offsets -> map, x, y (0..1), or nil
local function Locate(px, py)
    local api = Orders()
    local G = api and api.Geo
    if not (G and G.MinimapRadius and G.MinimapIndoors) then return nil end
    if type(px) ~= "number" or type(py) ~= "number" then return nil end
    if not (UnitPosition and Minimap and Minimap.GetZoom and C_Map and C_Map.GetBestMapForUnit
        and C_Map.GetWorldPosFromMapPos and C_Map.GetMapInfo and CreateVector2D) then return nil end
    local ok, north, west, _, instance = pcall(UnitPosition, "player")
    if not ok or type(north) ~= "number" or type(west) ~= "number" or instance == nil then return nil end

    local zoom = Minimap:GetZoom()
    local indoors = G.MinimapIndoors(zoom, CVar("minimapZoom"), CVar("minimapInsideZoom"), IsIndoors and IsIndoors())
    local radius = G.MinimapRadius(zoom, indoors)
    if type(radius) ~= "number" or radius <= 0 then return nil end
    local right, up = 2 * px * radius, 2 * py * radius
    if CVar("rotateMinimap") == "1" then
        local facing = GetPlayerFacing and GetPlayerFacing()
        if type(facing) ~= "number" then return nil end
        local c, s = math.cos(facing), math.sin(facing)
        right, up = right * c - up * s, right * s + up * c
    end
    local targetNorth, targetWest = north + up, west - right

    local okMap, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not okMap then return nil end
    for step = 1, MAP_CLIMB do
        if type(mapID) ~= "number" then return nil end
        local info = C_Map.GetMapInfo(mapID)
        if not info or (info.mapType or 0) <= MAP_WORLD then return nil end
        local x, y = MapPos(mapID, instance, targetNorth, targetWest)
        if x then return mapID, x, y end
        if step == 1 then
            local beside, bx, by = Neighbour(mapID, info.parentMapID, instance, targetNorth, targetWest)
            if beside then return beside, bx, by end
        end
        mapID = info.parentMapID
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- The waypoint, and the chat link that asks for it
-- ---------------------------------------------------------------------------
-- explicit: the user clicked the link, so the arrow goes there (SetArrow,
-- below) and Orders says so, or says in its own words why not. Otherwise
-- (the automatic setting) the waypoint is temporary, never asks for the
-- arrow, waits its turn behind everything of yours and says nothing.
local function SetWaypoint(ping, explicit)
    local api = Orders()
    if not api then return nil, "needsorders" end
    local uid, why = api.GoTo({ map = ping.map, x = ping.x, y = ping.y, title = ping.name .. "'s ping" }, {
        source = "Ping", key = "ping", temporary = true, persistent = false,
        setArrow = false, silent = not explicit,
    })
    if uid and explicit and api.SetArrow then api.SetArrow(uid) end
    return uid, why
end

-- The callout's [Go]: Orders' chat link for the ping's place, its plain
-- click claimed for this session (see the header). nil when Orders cannot
-- answer a click on it. A refused click is said by Orders (GoTo, not
-- silent), once.
local function CalloutLink(ping)
    local api = Orders()
    if not (api and type(api.ChatLink) == "function" and type(api.ClaimChatLink) == "function") then
        return nil
    end
    local link = api.ChatLink(ping.map, ping.x, ping.y, ping.name .. "'s ping", LINK_TEXT)
    if type(link) ~= "string" then return nil end
    api.ClaimChatLink(link, function() SetWaypoint(ping, true) end)
    return link
end

-- MINIMAP_PING payload is (unitTarget, x, y): normalized offsets from the
-- minimap center. (An earlier build assumed y-first; in-game testing showed
-- bottom-right clicks flashing top-left, the signature of swapped axes.)
local function OnPing(unit, x, y)
    if not (CommanderPingDB and CommanderPingDB.EnablePing) then return end
    local isOwn = UnitIsUnit and UnitIsUnit(unit, "player")
    if isOwn and not CommanderPingDB.IncludeOwnPings then return end

    StartFlash(x or 0, y or 0)
    if CommanderPingDB.PingSound then
        PlaySound(SOUNDKIT.TELL_MESSAGE, "Master")
    end
    local name = UnitName(unit) or "Someone"
    -- Only where Orders could act on it: no link that would do nothing
    local ping
    local api = Orders()
    if api and api.IsAvailable and api.IsAvailable() then
        local mapID, mx, my = Locate(x, y)
        if mapID then ping = { map = mapID, x = mx, y = my, name = name } end
    end
    if CommanderPingDB.PingCallout then
        local link = ping and CalloutLink(ping)
        print(string.format("|cff40c0ffCommander Ping:|r %s pinged the minimap%s", name, link and (" " .. link) or ""))
    end
    if ping and CommanderPingDB.PingWaypoint then
        SetWaypoint(ping, false)
    end
end

-- The 2.5.6 patch made MINIMAP_PING a callback-only event: RegisterEvent
-- raises "unknown event" for it (Blizzard's own minimap switched to
-- RegisterEventCallback in the same patch). Pick the mechanism the client
-- actually supports; everything is guarded so the module always loads.
local events = CreateFrame("Frame")
if C_EventUtils and C_EventUtils.IsEventValid and C_EventUtils.IsEventValid("MINIMAP_PING") then
    events:RegisterEvent("MINIMAP_PING")
    events:SetScript("OnEvent", function(self, event, unit, x, y)
        OnPing(unit, x, y)
    end)
elseif events.RegisterEventCallback then
    pcall(events.RegisterEventCallback, events, "MINIMAP_PING", function(owner, unit, x, y)
        OnPing(unit, x, y)
    end)
end
