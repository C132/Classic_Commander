-- CommanderMinimapWorldMap.lua — defog the world map.
--
-- A zone you have not walked is drawn as its dark base art; the bright terrain
-- is painted over it, one overlay texture per subzone, by Blizzard's
-- MapExplorationPin. The client only hands out the overlays you have EARNED
-- (C_MapExplorationInfo.GetExploredMapTextures) and there is no API for the
-- rest — so defogging means drawing the difference ourselves, from the overlay
-- table generated out of the client's own DB2s (CommanderMinimapFogData.lua,
-- see Harness/build_fogdata.py).
--
-- We post-hook the pin rather than replace it: Blizzard still draws every
-- explored overlay exactly as it always did, and we add only the ones it left
-- out, into our own texture pool one sublayer below so a revealed patch can
-- never cover a real one. Turning the option off releases our pool and the map
-- is Blizzard's again, untouched.

local ceil = math.ceil

-- Where the tile file ids start in a CommanderMinimapFogData entry:
--   offsetX, offsetY, width, height, cols, rows, fileID...
local FIRST_FILE = 7

local pin           -- Blizzard's MapExplorationPin, once we find it
local pool          -- our revealed-overlay textures, parented to that pin

local function Enabled()
    return CommanderMinimapDB and CommanderMinimapDB.DefogWorldMap and true or false
end

local function ReleaseAll()
    if pool then
        pool:ReleaseAll()
    end
end

-- Draw every overlay the client did not. Mirrors the tiling arithmetic in
-- MapExplorationPinMixin:RefreshOverlays — the last tile in a row or column is
-- a partial one, sitting in a power-of-two file that has to be cropped by
-- tex coords rather than stretched.
local function Defog()
    ReleaseAll()
    if not (pool and pin and Enabled()) then return end

    local map = pin:GetMap()
    local mapID = map and map:GetMapID()
    local overlays = mapID and CommanderMinimapFogData and CommanderMinimapFogData[mapID]
    if not overlays then return end

    local layers = C_Map.GetMapArtLayers(mapID)
    local layerInfo = layers and layers[map:GetCanvasContainer():GetCurrentLayerIndex()]
    if not layerInfo then return end
    local tileWidth, tileHeight = layerInfo.tileWidth, layerInfo.tileHeight
    if not (tileWidth and tileHeight) or tileWidth <= 0 or tileHeight <= 0 then return end

    -- What the client already drew. An overlay's first tile file is unique to
    -- it, so it identifies the overlay without matching geometry.
    local explored = {}
    local exploredTextures = C_MapExplorationInfo.GetExploredMapTextures(mapID)
    if exploredTextures then
        for _, info in ipairs(exploredTextures) do
            local first = info.fileDataIDs and info.fileDataIDs[1]
            if first then
                explored[first] = true
            end
        end
    end

    for _, overlay in ipairs(overlays) do
        local offsetX, offsetY = overlay[1], overlay[2]
        local width, height = overlay[3], overlay[4]
        local cols, rows = overlay[5], overlay[6]

        -- The table's grid was cut for this art style's tile size. If the layer
        -- the client is showing disagrees, our file ids would land in the wrong
        -- cells — skip rather than draw a scrambled zone.
        local fits = ceil(width / tileWidth) == cols and ceil(height / tileHeight) == rows

        if fits and not explored[overlay[FIRST_FILE]] then
            for row = 1, rows do
                local pixelHeight, fileHeight = tileHeight, tileHeight
                if row == rows then
                    pixelHeight = height % tileHeight
                    if pixelHeight == 0 then
                        pixelHeight = tileHeight
                    end
                    fileHeight = 16
                    while fileHeight < pixelHeight do
                        fileHeight = fileHeight * 2
                    end
                end

                for col = 1, cols do
                    local pixelWidth, fileWidth = tileWidth, tileWidth
                    if col == cols then
                        pixelWidth = width % tileWidth
                        if pixelWidth == 0 then
                            pixelWidth = tileWidth
                        end
                        fileWidth = 16
                        while fileWidth < pixelWidth do
                            fileWidth = fileWidth * 2
                        end
                    end

                    local texture = pool:Acquire()
                    texture:SetWidth(pixelWidth)
                    texture:SetHeight(pixelHeight)
                    texture:SetTexCoord(0, pixelWidth / fileWidth, 0, pixelHeight / fileHeight)
                    texture:SetPoint("TOPLEFT", pin, "TOPLEFT",
                        offsetX + (tileWidth * (col - 1)),
                        -(offsetY + (tileHeight * (row - 1))))
                    texture:SetTexture(overlay[FIRST_FILE + ((row - 1) * cols) + (col - 1)],
                        nil, nil, "TRILINEAR")
                    texture:Show()
                end
            end
        end
    end
end

-- The pin is built from its XML template, which copies MapExplorationPinMixin
-- onto the frame at creation — so hooking the mixin table after the world map
-- has loaded would do nothing. Hook the live pin instead. Blizzard_WorldMap is
-- not load-on-demand here, so it is already up by PLAYER_LOGIN; the world map's
-- OnShow is a second chance in case that ever changes.
local function EnsureHook()
    if pin then return true end
    if not (WorldMapFrame and WorldMapFrame.EnumeratePinsByTemplate) then return false end

    for candidate in WorldMapFrame:EnumeratePinsByTemplate("MapExplorationPinTemplate") do
        pin = candidate
        pool = CreateTexturePool(pin, "ARTWORK", -1)
        -- RefreshOverlays clears and redraws; RemoveAllData clears without a
        -- redraw (map change, canvas teardown) and must not leave one zone's
        -- terrain lying over the next one's.
        hooksecurefunc(pin, "RefreshOverlays", Defog)
        hooksecurefunc(pin, "RemoveAllData", ReleaseAll)
        return true
    end
    return false
end

local function ApplyDefog()
    if EnsureHook() then
        Defog()
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        ApplyDefog()
        if WorldMapFrame then
            WorldMapFrame:HookScript("OnShow", ApplyDefog)
        end
        Commander.AddListener(COMMANDER_MINIMAP_EVENTS.COMMANDER_MINIMAP, ApplyDefog)
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
