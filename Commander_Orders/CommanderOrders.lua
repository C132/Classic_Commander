-- Commander Orders: RTS move orders. Ctrl+Right-click the world map to set
-- a destination; an on-screen arrow (with distance) points the way, using
-- world-coordinate math via C_Map.GetWorldPosFromMapPos. The order clears
-- itself on arrival and persists across reloads in CommanderOrdersDB.
--
-- NOTE on the bearing math: WoW world coordinates have x increasing north
-- and y increasing west; GetPlayerFacing() is 0 facing north, increasing
-- counterclockwise (toward west). atan2(dy, dx) therefore yields a bearing
-- in the same convention, and (bearing - facing) rotates the arrow texture
-- into screen space.

local ARRIVE_DISTANCE = 15
local UPDATE_INTERVAL = 0.1

-- ---------------------------------------------------------------------------
-- Arrow display
-- ---------------------------------------------------------------------------
local arrow = CreateFrame("Button", "CommanderOrdersArrow", UIParent)
arrow:SetSize(56, 72)
arrow:SetPoint("TOP", UIParent, "TOP", 0, -220)
arrow:SetFrameStrata("HIGH")
arrow:Hide()

local arrowTexture = arrow:CreateTexture(nil, "ARTWORK")
arrowTexture:SetSize(48, 48)
arrowTexture:SetPoint("TOP")
arrowTexture:SetTexture("Interface\\Minimap\\MiniMap-DeadArrow")
arrowTexture:SetVertexColor(0.3, 1, 0.4)

local distanceText = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
distanceText:SetPoint("TOP", arrowTexture, "BOTTOM", 0, -2)

arrow:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Move Order", 1, 1, 1)
    GameTooltip:AddLine("Click to cancel the order.", nil, nil, nil, true)
    GameTooltip:Show()
end)
arrow:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ---------------------------------------------------------------------------
-- Order state
-- ---------------------------------------------------------------------------
local function PlayOrderSound()
    if CommanderOrdersDB.OrderSound then
        PlaySound(SOUNDKIT.IG_QUEST_LOG_OPEN, "Master")
    end
end

-- Shared with the settings panel and /corder clear
function CommanderOrders_ClearOrder(announce)
    CommanderOrdersDB.Waypoint = nil
    arrow:Hide()
    if announce then
        print("Commander Orders: order cleared")
    end
end

arrow:SetScript("OnClick", function()
    CommanderOrders_ClearOrder(true)
end)

-- World-space position of a map point plus its continent (instance) ID;
-- nil when the map has no world data (cosmic/azeroth-level maps)
local function WorldPos(mapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, instance, world = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if ok and world then
        return world, instance
    end
    return nil
end

local function SetOrder(mapID, x, y)
    -- Resolve and cache the world position now: maps without world data are
    -- rejected up front instead of producing a dead order, and the arrow
    -- never needs to re-resolve the target
    local world, instance = WorldPos(mapID, x, y)
    if not world then
        print("Commander Orders: that map has no world coordinates — zoom in to a zone map first")
        return false
    end
    CommanderOrdersDB.Waypoint = {
        mapID = mapID, x = x, y = y,
        worldX = world.x, worldY = world.y, instance = instance,
    }
    PlayOrderSound()
    print(string.format("Commander Orders: move order issued (%.0f, %.0f)", x * 100, y * 100))
    return true
end

-- ---------------------------------------------------------------------------
-- Arrow updates
-- ---------------------------------------------------------------------------
local sinceUpdate = 0
local arrivedAnnounced = false

local function UpdateArrow(self, elapsed)
    sinceUpdate = sinceUpdate + elapsed
    if sinceUpdate < UPDATE_INTERVAL then return end
    sinceUpdate = 0

    local waypoint = CommanderOrdersDB.Waypoint
    if not (CommanderOrdersDB.EnableOrders and waypoint and waypoint.worldX) then
        arrow:Hide()
        return
    end

    local ok, playerMap = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or not playerMap then
        arrow:Hide()
        return
    end
    local okPos, playerPos = pcall(C_Map.GetPlayerMapPosition, playerMap, "player")
    if not okPos or not playerPos or not playerPos.x then
        arrow:Hide()
        return
    end

    local playerWorld, playerInstance = WorldPos(playerMap, playerPos.x, playerPos.y)
    if not playerWorld then
        arrow:Hide()
        return
    end

    -- Cross-continent: EK and Kalimdor world coordinates overlap, so
    -- distance math between instances is meaningless (and could even
    -- fake an arrival). Show a neutral waiting state instead.
    if playerInstance ~= waypoint.instance then
        arrowTexture:SetRotation(0)
        arrowTexture:SetVertexColor(0.6, 0.6, 0.6)
        distanceText:SetText("other continent")
        arrow:Show()
        arrivedAnnounced = false
        return
    end
    arrowTexture:SetVertexColor(0.3, 1, 0.4)

    local dx = waypoint.worldX - playerWorld.x
    local dy = waypoint.worldY - playerWorld.y
    local distance = math.sqrt(dx * dx + dy * dy)

    if distance <= ARRIVE_DISTANCE then
        if not arrivedAnnounced then
            arrivedAnnounced = true
            print("Commander Orders: destination reached")
            PlayOrderSound()
        end
        CommanderOrders_ClearOrder(false)
        return
    end
    arrivedAnnounced = false

    local bearing = math.atan2(dy, dx)
    local facing = GetPlayerFacing() or 0
    arrowTexture:SetRotation(bearing - facing)
    distanceText:SetFormattedText("%d yd", math.floor(distance + 0.5))
    arrow:Show()
end

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", UpdateArrow)

-- ---------------------------------------------------------------------------
-- World map click handler (Ctrl+Right-click issues an order)
--
-- Registered through WorldMapFrame:AddCanvasClickHandler, which runs BEFORE
-- Blizzard's own right-click handling and, by returning true, suppresses
-- the map's navigate-to-parent zoom-out. A plain OnMouseUp post-hook cannot
-- work here: Blizzard's handler swaps to the parent map first, so the hook
-- would read the wrong map and the wrong coordinates.
-- ---------------------------------------------------------------------------
local hooked = false

local function HookWorldMap()
    if hooked then return end
    if not (WorldMapFrame and WorldMapFrame.AddCanvasClickHandler) then return end
    hooked = true
    WorldMapFrame:AddCanvasClickHandler(function(map, mouseButton, x, y)
        if mouseButton ~= "RightButton" or not IsControlKeyDown() then return false end
        if not CommanderOrdersDB.EnableOrders then return false end
        local mapID = (map.GetMapID and map:GetMapID()) or WorldMapFrame:GetMapID()
        if mapID and x and y and x > 0 and x < 1 and y > 0 and y < 1 then
            SetOrder(mapID, x, y)
            -- Consume the click either way so the ctrl-click gesture never
            -- doubles as the map's zoom-out
            return true
        end
        return false
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, addonName)
    if event == "PLAYER_LOGIN" then
        HookWorldMap()
        Commander.AddListener(COMMANDER_ORDERS_EVENTS.UPDATE, function()
            if not CommanderOrdersDB.EnableOrders then
                arrow:Hide()
            end
        end)
    elseif event == "ADDON_LOADED" and addonName == "Blizzard_WorldMap" then
        -- The world map UI can be load-on-demand; hook it whenever it appears
        HookWorldMap()
    end
end)
