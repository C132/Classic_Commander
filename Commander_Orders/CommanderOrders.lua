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

local function SetOrder(mapID, x, y)
    CommanderOrdersDB.Waypoint = { mapID = mapID, x = x, y = y }
    PlayOrderSound()
    print(string.format("Commander Orders: move order issued (%.0f, %.0f)", x * 100, y * 100))
end

-- World-space position of a map point; nil when the map has no world data
local function WorldPos(mapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, _, world = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if ok and world then
        return world
    end
    return nil
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
    if not (CommanderOrdersDB.EnableOrders and waypoint) then
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

    local playerWorld = WorldPos(playerMap, playerPos.x, playerPos.y)
    local targetWorld = WorldPos(waypoint.mapID, waypoint.x, waypoint.y)
    if not playerWorld or not targetWorld then
        arrow:Hide()
        return
    end

    local dx = targetWorld.x - playerWorld.x
    local dy = targetWorld.y - playerWorld.y
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
-- World map click hook (Ctrl+Right-click issues an order)
-- ---------------------------------------------------------------------------
local hooked = false

local function HookWorldMap()
    if hooked then return end
    if not (WorldMapFrame and WorldMapFrame.ScrollContainer) then return end
    hooked = true
    WorldMapFrame.ScrollContainer:HookScript("OnMouseUp", function(container, mouseButton)
        if mouseButton ~= "RightButton" or not IsControlKeyDown() then return end
        if not CommanderOrdersDB.EnableOrders then return end
        local x, y = container:GetNormalizedCursorPosition()
        local mapID = WorldMapFrame:GetMapID()
        if mapID and x and y and x > 0 and x < 1 and y > 0 and y < 1 then
            SetOrder(mapID, x, y)
        end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        HookWorldMap()
        Commander.AddListener(COMMANDER_ORDERS_EVENTS.UPDATE, function()
            if not CommanderOrdersDB.EnableOrders then
                arrow:Hide()
            end
        end)
    end
end)
