-- Commander Minimap world-map defog harness (luajit).
-- Loads the REAL fog table, the REAL settings file and the REAL defog module
-- under a WoW mock, drives the same calls the client makes (PLAYER_LOGIN, the
-- exploration pin's RefreshOverlays, a settings Notify) and asserts what
-- actually lands on the canvas: the tile grid, the partial-tile crop at the
-- right and bottom edges, the anchor offsets, the skip for ground the client
-- already drew, and the release paths.
--
-- The tiling arithmetic is a transcription of Blizzard's
-- MapExplorationPinMixin:RefreshOverlays, so it is checked here against a
-- synthetic overlay whose numbers are worked out by hand rather than against
-- the generated table (which is checked separately, for shape).
--
--   /opt/homebrew/bin/luajit worldmap_defog_harness.lua

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local ADDON = ADDONS .. "/Commander_Minimap"

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end

-- ===========================================================================
-- WoW mock
-- ===========================================================================

function hooksecurefunc(target, name, post)
    local original = target[name]
    target[name] = function(...)
        local a, b, c = original(...)
        post(...)
        return a, b, c
    end
end

local textures = {}      -- every texture the pool ever handed out
local function NewTexture(parent, layer, subLayer)
    local t = {
        __parent = parent, __layer = layer, __subLayer = subLayer,
        __shown = false, __point = nil,
    }
    function t:SetWidth(w) self.__w = w end
    function t:SetHeight(h) self.__h = h end
    function t:SetTexCoord(l, r, tp, b) self.__coord = { l, r, tp, b } end
    function t:SetPoint(point, relTo, relPoint, x, y)
        self.__point = { point = point, relTo = relTo, relPoint = relPoint, x = x, y = y }
    end
    function t:ClearAllPoints() self.__point = nil end
    function t:SetTexture(file) self.__file = file end
    function t:Show() self.__shown = true end
    function t:Hide() self.__shown = false end
    textures[#textures + 1] = t
    return t
end

function CreateTexturePool(parent, layer, subLayer)
    local pool = { __all = {}, __free = {}, __active = {} }
    function pool:Acquire()
        local t = table.remove(self.__free)
        if not t then
            t = NewTexture(parent, layer, subLayer)
            self.__all[#self.__all + 1] = t
        end
        self.__active[t] = true
        return t
    end
    function pool:ReleaseAll()
        for t in pairs(self.__active) do
            t:Hide()
            t:ClearAllPoints()
            self.__free[#self.__free + 1] = t
        end
        self.__active = {}
    end
    function pool:Active()
        local out = {}
        for t in pairs(self.__active) do out[#out + 1] = t end
        table.sort(out, function(a, b) return (a.__file or 0) < (b.__file or 0) end)
        return out
    end
    return pool
end

local eventFrames = {}
function CreateFrame(_, _, _, _)
    local f = { __events = {}, __scripts = {} }
    function f:RegisterEvent(e) self.__events[e] = true end
    function f:UnregisterEvent(e) self.__events[e] = nil end
    function f:SetScript(s, fn) self.__scripts[s] = fn end
    function f:HookScript(s, fn)
        local prev = self.__scripts[s]
        self.__scripts[s] = function(...) if prev then prev(...) end fn(...) end
    end
    function f:GetScript(s) return self.__scripts[s] end
    eventFrames[#eventFrames + 1] = f
    return f
end

local function Fire(event, ...)
    for _, f in ipairs(eventFrames) do
        if f.__events[event] and f.__scripts.OnEvent then
            f.__scripts.OnEvent(f, event, ...)
        end
    end
end

-- The exploration pin, as the world map hands it over
local currentMapID, currentLayerIndex = nil, 1
local layerTileSize = 256
local exploredByMap = {}

C_Map = {
    GetMapArtLayers = function(_)
        return { { tileWidth = layerTileSize, tileHeight = layerTileSize } }
    end,
}
C_MapExplorationInfo = {
    GetExploredMapTextures = function(mapID) return exploredByMap[mapID] end,
}

local canvasContainer = {
    GetCurrentLayerIndex = function() return currentLayerIndex end,
}
local mapCanvas = {
    GetMapID = function() return currentMapID end,
    GetCanvasContainer = function() return canvasContainer end,
}
local explorationPin = {
    GetMap = function() return mapCanvas end,
    RefreshOverlays = function(_, _) end,   -- Blizzard's own draw, stubbed out
    RemoveAllData = function(_) end,
}

WorldMapFrame = { __scripts = {} }
function WorldMapFrame:EnumeratePinsByTemplate(template)
    local sent = false
    return function()
        if template ~= "MapExplorationPinTemplate" or sent then return nil end
        sent = true
        return explorationPin
    end
end
function WorldMapFrame:HookScript(s, fn) self.__scripts[s] = fn end

-- Settings framework: enough of Commander.UI for the real DB file to build its
-- panel, plus the listener bus the module refreshes off.
local listeners = {}
local panelWidgets = {}
Commander = {
    AddListener = function(event, fn)
        listeners[event] = listeners[event] or {}
        table.insert(listeners[event], fn)
    end,
    Notify = function(event)
        for _, fn in ipairs(listeners[event] or {}) do fn() end
    end,
    UI = {
        FormatPercent = function(v) return tostring(v) end,
        ApplyDefaults = function(db, defaults)
            for k, v in pairs(defaults) do
                if db[k] == nil then db[k] = v end
            end
        end,
        ResetToDefaults = function(db, defaults)
            for k, v in pairs(defaults) do db[k] = v end
        end,
        NewPanel = function()
            local panel = {}
            function panel:AddSection(title) panelWidgets[#panelWidgets + 1] = { section = title } end
            local function add(kind)
                return function(_, spec)
                    spec.kind = kind
                    panelWidgets[#panelWidgets + 1] = spec
                end
            end
            panel.AddCheckbox = add("checkbox")
            panel.AddSlider = add("slider")
            panel.AddDropdown = add("dropdown")
            function panel:Finalize() end
            return panel
        end,
    },
}

local function Widget(label)
    for _, w in ipairs(panelWidgets) do
        if w.label == label then return w end
    end
end

-- ===========================================================================
-- Load the real files
-- ===========================================================================

assert(loadfile(ADDON .. "/CommanderMinimapDB.lua"))()
assert(loadfile(ADDON .. "/CommanderMinimapFogData.lua"))()
assert(loadfile(ADDON .. "/CommanderMinimapWorldMap.lua"))()

Fire("ADDON_LOADED", "Commander_Minimap")

CHECK(CommanderMinimapDB.DefogWorldMap == true, "defog defaults on")

Fire("PLAYER_LOGIN")

local checkbox = Widget("Defog the World Map")
CHECK(checkbox ~= nil, "the option is reachable in the panel")
CHECK(checkbox and checkbox.kind == "checkbox", "the option is a checkbox")
CHECK(checkbox and checkbox.get() == true, "the checkbox reads the saved setting")

-- ===========================================================================
-- The generated table: shape, not content
-- ===========================================================================

local maps, overlays, tiles = 0, 0, 0
local shapeBad, dupBad = 0, 0
for mapID, entries in pairs(CommanderMinimapFogData) do
    maps = maps + 1
    local firstFiles = {}
    for _, e in ipairs(entries) do
        overlays = overlays + 1
        local w, h, cols, rows = e[3], e[4], e[5], e[6]
        local count = #e - 6
        tiles = tiles + count
        if count ~= cols * rows or w <= 0 or h <= 0
            or math.ceil(w / 256) ~= cols or math.ceil(h / 256) ~= rows then
            shapeBad = shapeBad + 1
        end
        -- The skip test keys on the first tile, so it has to be unique per map
        if firstFiles[e[7]] then dupBad = dupBad + 1 end
        firstFiles[e[7]] = true
        if type(mapID) ~= "number" then shapeBad = shapeBad + 1 end
    end
end
CHECK(maps == 52, "every zone map with overlays is in the table", maps)
CHECK(overlays == 750, "overlay count", overlays)
CHECK(tiles == 1170, "tile count", tiles)
CHECK(shapeBad == 0, "every entry's grid matches its size", shapeBad)
CHECK(dupBad == 0, "first tile file is unique within a map", dupBad)
CHECK(CommanderMinimapFogData[1944] ~= nil, "Hellfire Peninsula present")
CHECK(CommanderMinimapFogData[1434] ~= nil, "Stranglethorn Vale present")

-- ===========================================================================
-- The draw: a synthetic zone whose tiling is worked out by hand
--
-- 300x260 at offset (40, 70) on a 256px layer:
--   cols = ceil(300/256) = 2, rows = 2
--   right column  is 300 % 256 = 44 wide,  in a 64px file  -> u1 = 44/64
--   bottom row    is 260 % 256 = 4 tall,   in a 16px file  -> v1 = 4/16
-- ===========================================================================

local TEST_MAP = 99001
CommanderMinimapFogData[TEST_MAP] = {
    { 40, 70, 300, 260, 2, 2, 8001, 8002, 8003, 8004 },
    { 500, 20, 128, 128, 1, 1, 8100 },
}

currentMapID = TEST_MAP
explorationPin:RefreshOverlays(true)

local function Drawn()
    local out = {}
    for _, t in ipairs(textures) do
        if t.__shown then out[#out + 1] = t end
    end
    table.sort(out, function(a, b) return a.__file < b.__file end)
    return out
end

local drawn = Drawn()
CHECK(#drawn == 5, "both overlays drew every tile", #drawn)

local tl, tr, bl, br = drawn[1], drawn[2], drawn[3], drawn[4]
CHECK(tl.__file == 8001 and br.__file == 8004, "tiles are laid out row-major")
CHECK(tl.__w == 256 and tl.__h == 256, "full tile keeps the layer's tile size")
CHECK(tr.__w == 44 and tr.__h == 256, "right column is cropped to the remainder", tr.__w)
CHECK(bl.__w == 256 and bl.__h == 4, "bottom row is cropped to the remainder", bl.__h)
CHECK(br.__w == 44 and br.__h == 4, "corner tile is cropped in both axes")
CHECK(tl.__coord[2] == 1 and tl.__coord[4] == 1, "full tile uses the whole file")
CHECK(math.abs(tr.__coord[2] - 44 / 64) < 1e-9, "partial width crops to the next power of two", tr.__coord[2])
CHECK(math.abs(bl.__coord[4] - 4 / 16) < 1e-9, "partial height crops to the next power of two", bl.__coord[4])

CHECK(tl.__point.point == "TOPLEFT" and tl.__point.relPoint == "TOPLEFT",
    "tiles anchor top-left of the pin")
CHECK(tl.__point.relTo == explorationPin, "tiles are parented to the exploration pin")
CHECK(tl.__point.x == 40 and tl.__point.y == -70, "first tile sits at the overlay offset")
CHECK(tr.__point.x == 40 + 256 and tr.__point.y == -70, "second column steps by a tile width")
CHECK(bl.__point.x == 40 and bl.__point.y == -(70 + 256), "second row steps by a tile height")
CHECK(tl.__layer == "ARTWORK" and tl.__subLayer == -1,
    "revealed ground draws below the client's own overlays")

-- ===========================================================================
-- Ground the client already drew is left to the client
-- ===========================================================================

exploredByMap[TEST_MAP] = { { fileDataIDs = { 8001, 8002, 8003, 8004 } } }
explorationPin:RefreshOverlays(true)
drawn = Drawn()
CHECK(#drawn == 1 and drawn[1].__file == 8100, "explored overlays are not drawn twice", #drawn)

exploredByMap[TEST_MAP] = nil
explorationPin:RefreshOverlays(true)
CHECK(#Drawn() == 5, "and come back when they are unexplored again")

-- ===========================================================================
-- Release paths and the toggle
-- ===========================================================================

explorationPin:RemoveAllData()
CHECK(#Drawn() == 0, "RemoveAllData drops our textures too")

explorationPin:RefreshOverlays(true)
CHECK(#Drawn() == 5, "and a refresh puts them back")

CommanderMinimapDB.DefogWorldMap = false
Commander.Notify(COMMANDER_MINIMAP_EVENTS.COMMANDER_MINIMAP)
CHECK(#Drawn() == 0, "turning the option off clears the map immediately")

explorationPin:RefreshOverlays(true)
CHECK(#Drawn() == 0, "and it stays clear while off")

CommanderMinimapDB.DefogWorldMap = true
Commander.Notify(COMMANDER_MINIMAP_EVENTS.COMMANDER_MINIMAP)
CHECK(#Drawn() == 5, "turning it back on redraws without reopening the map")

-- A layer whose tiles are not the size the table was cut for would scatter a
-- multi-tile overlay's files into the wrong cells; that overlay is skipped
-- rather than scrambled. A single-tile overlay has no grid to get wrong and
-- still draws correctly, so it is left alone.
layerTileSize = 512
explorationPin:RefreshOverlays(true)
drawn = Drawn()
CHECK(#drawn == 1 and drawn[1].__file == 8100,
    "a mismatched tile size skips the tiled overlay, not the single-tile one", #drawn)
CHECK(drawn[1] and drawn[1].__w == 128 and drawn[1].__h == 128,
    "the single-tile overlay is still sized from its own art")
layerTileSize = 256

-- Unknown maps (continents, instances, anything the table has no art for)
currentMapID = 1415
explorationPin:RefreshOverlays(true)
CHECK(#Drawn() == 0, "a map with no overlays draws nothing")

currentMapID = nil
explorationPin:RefreshOverlays(true)
CHECK(#Drawn() == 0, "no map id draws nothing")

-- ===========================================================================

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
