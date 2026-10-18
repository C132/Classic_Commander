-- Commander Quest Log: world-map drawer and pins harness (luajit).
--
-- Loads the REAL completion engine, the REAL Questie adapter (over
-- fake_questie.lua, a Questie that bites the way the real one does) and the
-- REAL map module, then drives a world map the way the client does: show it,
-- move it between a zone, a continent, a dungeon, an empty zone and a map no
-- zone resolves to, maximize and window it, resize its container, scroll the
-- drawer, click and hover rows, focus quests, flip every setting. What it
-- asserts is what lands on screen: the drawer's parent, anchors, width and
-- frame level, the strip's words and bar, the list's groups and folds, every
-- pin the provider acquires and where, the label pins on a continent, the
-- focus ring, and the waypoint and "open in the log" paths.
--
--   luajit questlog_map_harness.lua
--   CQL_MAP=/some/copy.lua luajit questlog_map_harness.lua    -- against a mutated copy
--
-- The window files are NOT loaded: the drawer has to work without the
-- window's kit (Q._kit) and without its DB defaults, and the harness proves it
-- does. Every scenario BOOTS FRESH -- new Questie fake, new world map, new
-- module instances -- so one scenario's hooks never fire into the next.
--
-- Mock notes worth keeping:
--   * WorldMapFrame is a PROXY whose every field write is recorded. Blizzard's
--     table must never be assigned to; the only sanctioned writes are
--     hooksecurefunc (which the mock performs behind the proxy, as the client
--     does natively) and a key added under pinPools (a separate table).
--   * The map mock calls the providers the way MapCanvasMixin does: on show
--     (RefreshAllData(true)) and on every map change (OnMapChanged, whose
--     default runs RefreshAllData).
--   * The pools are 2.5.6's (Blizzard_SharedXMLBase/Pools.lua).
--     CreateFramePool is the SECURE pool: a proxy whose Acquire runs the
--     private pool's own CreateFrame closure, so a write to the proxy's
--     createFunc / creationFunc is stored and never read -- the trap the
--     drawer's first pool fell into, which a mock honouring creationFunc hid.
--     Its sixth argument, postCreate, IS run. CreateUnsecuredRegionPoolInstance
--     is the plain pool whose createFunc / resetFunc fields are read, as
--     HereBeDragons uses it on this client.
--   * AcquirePin is Blizzard_MapCanvas.lua:155-198: a NEW pin always gets its
--     OnLoad, then Show and OnAcquired; SetPosition goes through the map to
--     ApplyFrameLevel, which takes an absolute level from the map's pin-level
--     manager (AREA_POI 2018, topmost 2757 on TBC). Acquiring or releasing
--     marks the canvas dirty, and the next frame calls a MapCanvasPinMixin
--     method on EVERY active pin, as ScrollContainer:OnUpdate does; a bare
--     frame without the mixin errors there, outside the drawer's pcall, and
--     the error is reported like any Blizzard error.
--   * FontString:SetText errors when no font was given, as in the client.
--   * Timers run by FRAME: an After(0) scheduled during a frame runs on the
--     next one, so the drawer's one-redraw-per-frame coalescing is observable.

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local MODULE = ADDONS .. "/Commander_QuestLog"
local MAP_FILE = os.getenv("CQL_MAP") or (MODULE .. "/CommanderQuestLogMap.lua")

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end
local function NEAR(a, b, eps)
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) < (eps or 1e-6)
end
local function SAME_COLOUR(c, r, g, b)
    return type(c) == "table" and NEAR(c[1], r, 1e-4) and NEAR(c[2], g, 1e-4) and NEAR(c[3], b, 1e-4)
end

unpack = unpack or table.unpack

-- ===========================================================================
-- WoW mock: output, errors, time
-- ===========================================================================

local printLog = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    printLog[#printLog + 1] = table.concat(parts, " ")
end

local caughtErrors = {}
function geterrorhandler() return function(err) caughtErrors[#caughtErrors + 1] = tostring(err) end end

-- Milliseconds; a frame is 16 ms
local now = 0
local timers, timerSeq = {}, 0
local frameHooks = {}        -- run at the end of every frame (the map canvas's OnUpdate)
function GetTime() return now / 1000 end
C_Timer = {
    After = function(delay, fn)
        timerSeq = timerSeq + 1
        timers[#timers + 1] = { at = now + math.floor((delay or 0) * 1000 + 0.5), fn = fn, seq = timerSeq }
    end,
}
local function Frame(dt)
    now = now + (dt or 16)
    local due, keep = {}, {}
    for _, t in ipairs(timers) do
        if t.at <= now then due[#due + 1] = t else keep[#keep + 1] = t end
    end
    timers = keep
    table.sort(due, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.seq < b.seq end)
    for _, t in ipairs(due) do t.fn() end
    for _, hook in ipairs(frameHooks) do hook() end
end
local function Advance(ms)
    local target = now + ms
    while now < target do Frame(math.min(16, target - now)) end
end
-- Runs frames until nothing short is pending (the 3 s focus pulse included)
local function Settle()
    for _ = 1, 5000 do
        if #timers == 0 then return true end
        Frame()
    end
    return false
end

-- ===========================================================================
-- WoW mock: widgets
-- ===========================================================================

local registry = {}          -- event -> frames
local allFrames = {}
local strataCalls = {}
local textLog = {}           -- every string any FontString was given

local NewWidget
local WidgetMT = {}

local function FireScript(widget, name, ...)
    local handler = widget.__scripts and widget.__scripts[name]
    if handler then return handler(widget, ...) end
end

local METHOD_PREFIXES = {
    "Set", "Enable", "Disable", "Register", "Unregister", "Clear", "Start", "Stop", "Raise",
    "Lower", "Lock", "Play", "Add", "Highlight", "Is", "Can", "Get", "Hook", "Create", "Update",
}
local function IsAutoMethod(key)
    for _, prefix in ipairs(METHOD_PREFIXES) do
        if key:sub(1, #prefix) == prefix then return true end
    end
    return false
end

local METHODS = {}
function METHODS.SetWidth(s, w) s.__w = w end
function METHODS.GetWidth(s) return s.__w or 0 end
function METHODS.SetHeight(s, h) s.__h = h end
function METHODS.GetHeight(s) return s.__h or 0 end
function METHODS.SetSize(s, w, h) s.__w, s.__h = w, h end
function METHODS.SetPoint(s, point, rel, relPoint, x, y)
    s.__points = s.__points or {}
    s.__points[#s.__points + 1] = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
end
function METHODS.ClearAllPoints(s) s.__points = {} end
function METHODS.GetNumPoints(s) return #(s.__points or {}) end
function METHODS.SetAllPoints(s, rel) s.__allPoints = rel or true end
function METHODS.SetFrameLevel(s, level) s.__level = level end
function METHODS.GetFrameLevel(s) return s.__level or 1 end
function METHODS.SetFrameStrata(s, strata)
    s.__strata = strata
    strataCalls[#strataCalls + 1] = s
end
function METHODS.SetText(s, text)
    if s.__kind == "FontString" and not s.__font then
        error("FontString:SetText(): Font not set", 2)
    end
    s.__text = text
    textLog[#textLog + 1] = tostring(text)
end
function METHODS.GetText(s) return s.__text end
function METHODS.SetFontObject(s, font) s.__font = font end
function METHODS.SetFont(s, path) s.__font = path end
function METHODS.GetStringWidth(s) return #(s.__text or "") * 5 end
function METHODS.SetTextColor(s, r, g, b, a) s.__textColor = { r, g, b, a } end
function METHODS.SetColorTexture(s, r, g, b, a) s.__color = { r, g, b, a } end
function METHODS.SetVertexColor(s, r, g, b, a) s.__vertex = { r, g, b, a } end
function METHODS.SetTexture(s, file) s.__texture = file end
function METHODS.SetAlpha(s, a) s.__alpha = a end
function METHODS.GetAlpha(s) return s.__alpha or 1 end
function METHODS.SetRotation(s, angle) s.__rotation = angle end
function METHODS.Show(s) s.__shown = true; FireScript(s, "OnShow") end
function METHODS.Hide(s) s.__shown = false; FireScript(s, "OnHide") end
function METHODS.SetShown(s, shown) if shown then s:Show() else s:Hide() end end
function METHODS.IsShown(s) return s.__shown end
function METHODS.IsVisible(s)
    local w = s
    while w do
        if w.__shown == false then return false end
        w = w.__parent
        if type(w) == "table" and w.IsShown and not w.__kind then return w:IsShown() end
    end
    return true
end
function METHODS.EnableMouse(s, on) s.__mouse = on and true or false end
function METHODS.EnableMouseWheel(s, on) s.__wheel = on and true or false end
function METHODS.SetMouseMotionEnabled(s, on) s.__motion = on and true or false end
function METHODS.SetMouseClickEnabled(s, on) s.__click = on and true or false end
function METHODS.RegisterForClicks(s, ...) s.__clicks = { ... } end
-- The real widget method, as HereBeDragons met it: protected in combat. A pin
-- without the no-op override would reach this one.
function METHODS.SetPassThroughButtons() error("SetPassThroughButtons: blocked (protected in combat)", 2) end
function METHODS.SetScript(s, name, handler) s.__scripts[name] = handler end
function METHODS.GetScript(s, name) return s.__scripts[name] end
function METHODS.HookScript(s, name, handler)
    local previous = s.__scripts[name]
    if previous then
        s.__scripts[name] = function(...) previous(...) handler(...) end
    else
        s.__scripts[name] = handler
    end
end
function METHODS.RegisterEvent(s, event)
    registry[event] = registry[event] or {}
    table.insert(registry[event], s)
end
function METHODS.UnregisterEvent(s, event)
    local list = registry[event]
    if list then
        for i = #list, 1, -1 do if list[i] == s then table.remove(list, i) end end
    end
end
function METHODS.CreateTexture(s, name, layer, template, sublevel)
    local t = NewWidget("Texture", nil, s)
    t.__layer, t.__sublevel = layer, sublevel
    s.__textures = s.__textures or {}
    s.__textures[#s.__textures + 1] = t
    return t
end
function METHODS.CreateFontString(s, name, layer, template)
    local t = NewWidget("FontString", nil, s)
    t.__layer, t.__font = layer, template
    s.__fontStrings = s.__fontStrings or {}
    s.__fontStrings[#s.__fontStrings + 1] = t
    return t
end

WidgetMT.__index = function(self, key)
    if type(key) ~= "string" then return nil end
    local fn = METHODS[key]
    if not fn and IsAutoMethod(key) then fn = function() end end
    if fn then rawset(self, key, fn) end
    return fn
end

NewWidget = function(kind, name, parent)
    return setmetatable({ __kind = kind, __name = name, __parent = parent, __scripts = {}, __shown = true }, WidgetMT)
end

function CreateFrame(frameType, name, parent, template)
    local f = NewWidget(frameType, name, parent)
    f.__template = template
    if name then _G[name] = f end
    allFrames[#allFrames + 1] = f
    return f
end

local function Fire(event, ...)
    local list = {}
    for i, frame in ipairs(registry[event] or {}) do list[i] = frame end
    for _, frame in ipairs(list) do
        local handler = frame.__scripts.OnEvent
        if handler then handler(frame, event, ...) end
    end
end

UIParent = NewWidget("Frame", "UIParent")

local tooltipLines = {}
GameTooltip = NewWidget("GameTooltip", "GameTooltip")
GameTooltip.SetOwner = function(self, owner, anchor)
    tooltipLines = {}
    self.__owner, self.__anchor = owner, anchor
end
GameTooltip.SetText = function(_, text) tooltipLines[#tooltipLines + 1] = tostring(text) end
GameTooltip.AddLine = function(_, text) tooltipLines[#tooltipLines + 1] = tostring(text) end
GameTooltip.AddDoubleLine = function(_, left, right)
    tooltipLines[#tooltipLines + 1] = tostring(left) .. "  " .. tostring(right)
end
local function TooltipHas(text)
    for _, line in ipairs(tooltipLines) do
        if line:find(text, 1, true) then return true end
    end
    return false
end
local function AllTooltipText() return table.concat(tooltipLines, "\n") end

-- hooksecurefunc writes behind a proxy's back, the way the client's native one
-- replaces a method without the write passing through Lua
function hooksecurefunc(target, name, post)
    if type(target) == "string" then target, name, post = _G, target, name end
    local original = target[name]
    assert(type(original) == "function", "hooksecurefunc on a missing method " .. tostring(name))
    local wrapper = function(...)
        local results = { original(...) }
        post(...)
        return unpack(results)
    end
    local mt = getmetatable(target)
    if mt and mt.__fields then mt.__fields[name] = wrapper else rawset(target, name, wrapper) end
end

function Mixin(object, ...)
    for i = 1, select("#", ...) do
        for k, v in pairs((select(i, ...))) do object[k] = v end
    end
    return object
end
function CreateFromMixins(...) return Mixin({}, ...) end

MapCanvasDataProviderMixin = {
    OnAdded = function(self, map) self.owningMap = map end,
    OnRemoved = function(self) self.owningMap = nil end,
    GetMap = function(self) return self.owningMap end,
    OnMapChanged = function(self) self:RefreshAllData() end,
    RemoveAllData = function() end,
    RefreshAllData = function() end,
}
MapCanvasPinMixin = {
    OnLoad = function() end,
    OnAcquired = function() end,
    OnReleased = function() end,
    OnMouseEnter = function() end,
    OnMouseLeave = function() end,
    GetMap = function(self) return self.owningMap end,
    UseFrameLevelType = function(self, levelType, index)
        self.__levelType, self.pinFrameLevelType, self.pinFrameLevelIndex = levelType, levelType, index
    end,
    SetScalingLimits = function(self, a, b, c) self.__scaling = { a, b, c } end,
    -- The real one goes through the map (SetPinPosition -> ApplyPinPosition),
    -- which applies the pin's frame level
    SetPosition = function(self, x, y)
        self.__x, self.__y = x, y
        self:ApplyFrameLevel()
    end,
    ApplyFrameLevel = function(self)
        local map = self:GetMap()
        local manager = map and map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
        if manager then self:SetFrameLevel(manager:GetValidFrameLevel(self.pinFrameLevelType, self.pinFrameLevelIndex)) end
    end,
    -- What the canvas's OnUpdate calls on every pin (CallMethodOnPinsAndDataProviders,
    -- UpdatePinNudging)
    OnCanvasScaleChanged = function() end,
    OnCanvasPanChanged = function() end,
    OnCanvasSizeChanged = function() end,
    SetNudgeVector = function() end,
}

-- ObjectPoolMixin (Pools.lua:118-195): createFunc / resetFunc are READ from
-- the pool on every Acquire / Release, and a new object is reset too
local function NewObjectPool(createFunc, resetFunc)
    local pool = { createFunc = createFunc, resetFunc = resetFunc, activeObjects = {}, inactiveObjects = {},
                   activeObjectCount = 0, created = 0 }
    function pool:Acquire()
        local object = table.remove(self.inactiveObjects)
        local new = object == nil
        if new then
            object = self.createFunc(self)
            assert(type(object) == "table")
            self.created = self.created + 1
            self.resetFunc(self, object, new)
        end
        self.activeObjects[object] = true
        self.activeObjectCount = self.activeObjectCount + 1
        return object, new
    end
    function pool:Release(object)
        if not self.activeObjects[object] then return false end
        self.resetFunc(self, object)
        self.inactiveObjects[#self.inactiveObjects + 1] = object
        self.activeObjects[object] = nil
        self.activeObjectCount = self.activeObjectCount - 1
        return true
    end
    function pool:ReleaseAll()
        for object in pairs(self.activeObjects) do self:Release(object) end
    end
    function pool:EnumerateActive() return pairs(self.activeObjects) end
    function pool:GetNumActive() return self.activeObjectCount end
    return pool
end
local function HideAndClearAnchors(_, region)
    region:Hide()
    region:ClearAllPoints()
end

function CreateUnsecuredRegionPoolInstance(template, createFunc, resetFunc)
    local pool = NewObjectPool(createFunc, resetFunc or HideAndClearAnchors)
    pool.GetTemplate = function() return template end
    return pool
end
local unsecuredPoolApi = CreateUnsecuredRegionPoolInstance

-- 2.5.6's CreateFramePool = CreateSecureFramePool: the private pool creates
-- with its own closure (postCreate honoured) and the caller gets a PROXY.
-- Writes to the proxy's fields land on the proxy table and are never read.
local proxyPrivate = setmetatable({}, { __mode = "k" })
function CreateFramePool(frameType, parent, template, resetFunc, forbidden, postCreate)
    local proxy = {}
    local private = NewObjectPool(function()
        local frame = CreateFrame(frameType, nil, parent, template)
        if postCreate then postCreate(frame) end
        return frame
    end, function(_, object, new)
        if resetFunc then resetFunc(proxy, object, new) else HideAndClearAnchors(proxy, object) end
    end)
    proxyPrivate[proxy] = private
    return setmetatable(proxy, { __index = {
        Acquire = function() return private:Acquire() end,
        Release = function(_, object) return private:Release(object) end,
        ReleaseAll = function() return private:ReleaseAll() end,
        EnumerateActive = function() return private:EnumerateActive() end,
        GetNumActive = function() return private:GetNumActive() end,
    } })
end

-- Every active pin of a pool, through its own API (proxy or not)
local function PoolPins(pool)
    local out = {}
    if pool then for pin in pool:EnumerateActive() do out[#out + 1] = pin end end
    return out
end

local hidePanelCalls = {}
function HideUIPanel(frame)
    hidePanelCalls[#hidePanelCalls + 1] = frame
    if frame and frame.Hide then frame:Hide() end
end
local ctrlDown = false
function IsControlKeyDown() return ctrlDown end

-- ===========================================================================
-- WoW mock: the world map
-- ===========================================================================

local WM            -- the current map mock's bookkeeping
frameHooks[#frameHooks + 1] = function() if WM and WM.CanvasPass then WM.CanvasPass() end end

-- The pin-level manager's absolute levels on TBC (the real manager run over
-- Blizzard_WorldMap.lua's AddFrameLevel list): AREA_POI 2018, and the topmost
-- type is the area banner at 2757, above the player arrow at 2754
local PIN_LEVELS = { PIN_FRAME_LEVEL_AREA_POI = 2018, PIN_FRAME_LEVEL_GROUP_MEMBER = 2754,
                     PIN_FRAME_LEVEL_TOPMOST = 2757 }

local function NewWorldMap()
    local wm = {
        writes = {}, providers = {}, providerAdds = 0, mapID = 1944, maximized = true,
        syncs = 0, removeCalls = 0, canvasDirty = false, canvasPasses = 0, canvasErrors = 0,
    }
    local container = NewWidget("Frame", nil, nil)
    container.__level, container.__h, container.__w = 5, 600, 900
    local canvas = NewWidget("Frame", nil, container)
    local fields = { __scripts = {}, __shown = false, pinPools = {}, ScrollContainer = container }
    wm.fields, wm.container, wm.canvas = fields, container, canvas

    function fields.HookScript(self, name, fn)
        local previous = fields.__scripts[name]
        if previous then
            fields.__scripts[name] = function(...) previous(...) fn(...) end
        else
            fields.__scripts[name] = fn
        end
    end
    function fields.SetScript(self, name, fn) fields.__scripts[name] = fn end
    function fields.GetScript(self, name) return fields.__scripts[name] end
    function fields.Show(self)
        fields.__shown = true
        local handler = fields.__scripts.OnShow
        if handler then handler(self) end
    end
    function fields.Hide(self)
        fields.__shown = false
        local handler = fields.__scripts.OnHide
        if handler then handler(self) end
    end
    function fields.IsShown() return fields.__shown end
    function fields.IsVisible() return fields.__shown end
    function fields.GetFrameLevel() return 1 end
    function fields.GetMapID() return wm.mapID end
    function fields.SetMapID(self, uiMapId)
        wm.mapID = uiMapId
        self:OnMapChanged()
    end
    -- MapCanvasMixin:OnMapChanged hands the change to every provider
    function fields.OnMapChanged()
        for _, provider in ipairs(wm.providers) do provider:OnMapChanged() end
    end
    function fields.IsMaximized() return wm.maximized end
    function fields.SynchronizeDisplayState() wm.syncs = wm.syncs + 1 end
    wm.originalSync, wm.originalChanged = fields.SynchronizeDisplayState, fields.OnMapChanged
    function fields.GetCanvas() return canvas end
    function fields.GetCanvasContainer() return container end
    function fields.AddDataProvider(self, provider)
        wm.providerAdds = wm.providerAdds + 1
        wm.providers[#wm.providers + 1] = provider
        provider:OnAdded(self)
    end
    local levels = { GetValidFrameLevel = function(_, levelType) return PIN_LEVELS[levelType] or 2000 end }
    function fields.GetPinFrameLevelsManager() return levels end
    -- Blizzard_MapCanvas.lua:155-198, in its order
    function fields.AcquirePin(self, template, ...)
        local pool = fields.pinPools[template]
        assert(pool, "AcquirePin: no pool for " .. tostring(template))
        local pin, isNew = pool:Acquire()
        pin.pinTemplate = template
        pin.owningMap = self
        if isNew then pin:OnLoad() end
        wm.canvasDirty = true
        pin:Show()
        pin:OnAcquired(...)
        return pin
    end
    function fields.RemoveAllPinsByTemplate(_, template)
        wm.removeCalls = wm.removeCalls + 1
        local pool = fields.pinPools[template]
        if pool then
            pool:ReleaseAll()
            wm.canvasDirty = true
        end
    end
    function fields.EnumeratePinsByTemplate(_, template)
        local list = PoolPins(fields.pinPools[template])
        local i = 0
        return function() i = i + 1; return list[i] end
    end
    -- ScrollContainer:OnUpdate after MarkCanvasDirty: a method on every pin of
    -- every pool, outside any provider's pcall
    function wm.CanvasPass()
        if not wm.canvasDirty then return end
        wm.canvasDirty = false
        wm.canvasPasses = wm.canvasPasses + 1
        for _, pool in pairs(fields.pinPools) do
            for _, pin in ipairs(PoolPins(pool)) do
                local ok, err = pcall(function() pin:OnCanvasScaleChanged(); pin:SetNudgeVector(nil, nil, nil, nil) end)
                if not ok then
                    wm.canvasErrors = wm.canvasErrors + 1
                    caughtErrors[#caughtErrors + 1] = "Blizzard_MapCanvas: " .. tostring(err)
                end
            end
        end
    end
    -- Blizzard's own OnShow: optionally moves to the player's map first (a map
    -- change INSIDE OnShow, before any post-hook), then refreshes every provider
    fields.__scripts.OnShow = function(self)
        if wm.showMapID and wm.showMapID ~= wm.mapID then self:SetMapID(wm.showMapID) end
        for _, provider in ipairs(wm.providers) do provider:RefreshAllData(true) end
    end

    wm.frame = setmetatable({}, {
        __fields = fields,
        __index = fields,
        __newindex = function(_, key, value)
            wm.writes[#wm.writes + 1] = tostring(key)
            fields[key] = value
        end,
    })
    return wm
end

-- ===========================================================================
-- WoW mock: the suite
-- ===========================================================================

local hubListeners = {}
local attachedTooltips = {}
Commander = {
    AddListener = function(event, fn)
        hubListeners[event] = hubListeners[event] or {}
        for _, existing in ipairs(hubListeners[event]) do if existing == fn then return end end
        table.insert(hubListeners[event], fn)
    end,
    Notify = function(event, ...)
        for _, fn in ipairs(hubListeners[event] or {}) do
            local ok, err = pcall(fn, ...)
            if not ok then caughtErrors[#caughtErrors + 1] = tostring(err) end
        end
    end,
    UI = {
        AttachTooltip = function(widget, title, text, anchor)
            attachedTooltips[widget] = { title = title, text = text, anchor = anchor }
        end,
    },
}
COMMANDER_QUESTLOG_EVENTS = { UPDATE = "COMMANDER_QUESTLOG_UPDATE" }
C_AddOns = { GetAddOnMetadata = function() return nil end }
function UnitClass() return "Paladin", "PALADIN", 2 end

local orders = {}
local openCalls = {}

-- ===========================================================================
-- Boot: a fresh world, fresh module instances
-- ===========================================================================

local Fake = dofile(MODULE .. "/Harness/fake_questie.lua")
local Q, M, A, C
local fake, world
local requestLog = {}

local function Boot(opts)
    opts = opts or {}
    timers = {}
    registry = {}
    for k in pairs(hubListeners) do hubListeners[k] = nil end
    for k in pairs(attachedTooltips) do attachedTooltips[k] = nil end
    strataCalls = {}
    orders, openCalls, requestLog = {}, {}, {}
    ctrlDown = false
    _G.CommanderQuestLogMapDrawer = nil
    CommanderQuestLog = {}
    Q = CommanderQuestLog
    CommanderQuestLogDB = opts.db or {}
    CommanderQuestLogChar = { Ignored = {} }
    -- A recording Commander Orders shaped like its public table; the legacy
    -- single-slot order counts as a failure if anything still calls it
    CommanderOrders = {
        IsAvailable = function() return true end,
        Add = function(spec)
            orders[#orders + 1] = { uiMapId = spec.map, x = spec.x, y = spec.y, spec = spec }
            return "w" .. #orders
        end,
        AddRoute = function(spec)
            orders[#orders + 1] = { route = spec }
            return "r" .. #orders
        end,
        RegisterResolver = function() return true end,
    }
    CommanderOrders_IssueOrder = function()
        orders[#orders + 1] = { legacy = true }
        return true
    end
    CommanderQuestLog_OpenToZone = function(areaId, questId)
        openCalls[#openCalls + 1] = { areaId = areaId, questId = questId }
    end

    world = Fake.DefaultWorld()
    if opts.edit then opts.edit(world) end
    if opts.absent then
        Questie, QuestieLoader = nil, nil
        fake = nil
    else
        fake = Fake.Install(world)
    end
    Fake.InstallClient(world, { force = true })

    if opts.noMap then
        WM, WorldMapFrame = nil, nil
    else
        WM = NewWorldMap()
        WorldMapFrame = WM.frame
    end

    assert(loadfile(MODULE .. "/CommanderQuestLogCompletion.lua"))()
    assert(loadfile(MODULE .. "/CommanderQuestLogQuestie.lua"))()
    local before = {}
    for k in pairs(_G) do before[k] = true end
    assert(loadfile(MAP_FILE))()
    Fire("ADDON_LOADED", "Commander_QuestLog")
    Fire("PLAYER_LOGIN")
    Settle()
    M, A, C = Q.Map, Q.Questie, Q.Completion
    -- Record what the drawer asks the adapter for, without changing it
    local request = A.RequestSummaries
    A.RequestSummaries = function(ids, onEach)
        local copy = {}
        for i, id in ipairs(ids or {}) do copy[i] = id end
        requestLog[#requestLog + 1] = copy
        return request(ids, onEach)
    end
    return before
end

-- ===========================================================================
-- Readers
-- ===========================================================================

local PIN_TEMPLATE = "CommanderQuestLogPinTemplate"

local function Drawer() return M._Drawer() end

local function ShownRows()
    local out = {}
    for _, row in ipairs(M._Rows()) do
        if row.__shown and row.item then out[#out + 1] = row end
    end
    return out
end

local function QuestRow(id)
    for _, row in ipairs(ShownRows()) do
        if row.item.kind == "QUEST" and row.item.entry.id == id then return row end
    end
    return nil
end

local function HeaderRow(title)
    for _, row in ipairs(ShownRows()) do
        if row.item.kind == "HEADER" and row.item.title == title then return row end
    end
    return nil
end

local function ZoneRow(name)
    for _, row in ipairs(ShownRows()) do
        if row.item.kind == "ZONE" and row.item.zone.name == name then return row end
    end
    return nil
end

local function ActivePins()
    return PoolPins(WM and WM.fields.pinPools[PIN_TEMPLATE])
end

local function GiverPins()
    local out = {}
    for _, pin in ipairs(ActivePins()) do
        if pin.data and pin.data.kind == "GIVER" then out[#out + 1] = pin end
    end
    return out
end

local function LabelPins()
    local out = {}
    for _, pin in ipairs(ActivePins()) do
        if pin.data and pin.data.kind == "LABEL" then out[#out + 1] = pin end
    end
    return out
end

local function PinHas(pin, id)
    for _, entry in ipairs(pin.data and pin.data.quests or {}) do
        if entry.id == id then return true end
    end
    return false
end

local function PinsWith(id)
    local out = {}
    for _, pin in ipairs(GiverPins()) do
        if PinHas(pin, id) then out[#out + 1] = pin end
    end
    return out
end

local function PinAt(x, y)
    for _, pin in ipairs(ActivePins()) do
        if NEAR(pin.__x, x, 1e-6) and NEAR(pin.__y, y, 1e-6) then return pin end
    end
    return nil
end

local function RingShown(pin)
    local ring = pin.ring or {}
    if #ring ~= 4 then return false end
    for _, bar in ipairs(ring) do if not bar.__shown then return false end end
    return true
end

local function Click(widget, button) return widget.__scripts.OnClick(widget, button or "LeftButton") end
local function Hover(widget) return widget.__scripts.OnEnter(widget) end

local function SetSetting(key, value)
    CommanderQuestLogDB[key] = value
    Commander.Notify(COMMANDER_QUESTLOG_EVENTS.UPDATE)
    Settle()
end

local function FindPoint(widget, point)
    for _, p in ipairs(widget.__points or {}) do
        if p.point == point then return p end
    end
    return nil
end

local function ViewOf(areaId) return A.ZoneView(areaId) end

-- Drawn text may use the middle dot and the em dash, and no other multi-byte
-- character: every other one is a shape glyph ARIALN draws as a box (D11)
local function GlyphFree(text)
    local stripped = tostring(text):gsub("\194\183", ""):gsub("\226\128\148", "")
    return not stripped:find("[\128-\255]")
end

-- ===========================================================================
-- A. Load and attach: hooks in, nothing built
-- ===========================================================================

-- 9003's finisher stands apart from its giver, so a waypoint to the one can
-- be told from a waypoint to the other
local function MainWorld(w) w.quests[9003].finishedBy = { { 20008 } } end
local globalsBefore = Boot({ edit = MainWorld })

CHECK(type(M) == "table", "A: Q.Map published")
CHECK(type(M.Refresh) == "function" and type(M.Focus) == "function" and type(M.IsBuilt) == "function",
    "A: Refresh, Focus and IsBuilt are public")
CHECK(M._State().attached == true, "A: attached at PLAYER_LOGIN")
CHECK(M.IsBuilt() == false, "A: nothing built before the map is shown")
CHECK(_G.CommanderQuestLogMapDrawer == nil, "A: no drawer frame before the first show")
CHECK(WM.providerAdds == 0, "A: no data provider before the first show")
CHECK(next(WM.fields.pinPools) == nil, "A: no pin pool before the first show")
CHECK(type(WM.fields.__scripts.OnShow) == "function", "A: the map's OnShow is hooked")
CHECK(type(WM.container.__scripts.OnSizeChanged) == "function", "A: the container's OnSizeChanged is hooked")
CHECK(WM.fields.SynchronizeDisplayState ~= nil, "A: SynchronizeDisplayState still callable")
CHECK(#WM.writes == 0, "A: no field was ASSIGNED on WorldMapFrame", table.concat(WM.writes, ","))
CHECK(A.State() == "READY", "A: the fake Questie is ready")

-- A map change while the map is hidden builds nothing
WorldMapFrame:SetMapID(1944)
CHECK(M.IsBuilt() == false, "A: a map change while hidden builds nothing")
CHECK(M._State().refreshes == 0, "A: and draws nothing")

-- ===========================================================================
-- B. First show on Hellfire: the drawer
-- ===========================================================================

WorldMapFrame:Show()
local drawer = Drawer()
local container = WM.container

CHECK(M.IsBuilt() == true, "B: drawer built on first show")
CHECK(drawer ~= nil and drawer == _G.CommanderQuestLogMapDrawer, "B: the drawer is the one named global frame")
CHECK(drawer and drawer.__parent == WorldMapFrame, "B: parented to WorldMapFrame")
CHECK(drawer and drawer.__shown == true, "B: shown")
CHECK(#strataCalls == 0, "B: SetFrameStrata never called", #strataCalls)
local topRight = drawer and FindPoint(drawer, "TOPRIGHT")
local bottomRight = drawer and FindPoint(drawer, "BOTTOMRIGHT")
CHECK(topRight and topRight.rel == container and topRight.relPoint == "TOPRIGHT"
    and topRight.x == -8 and topRight.y == -40, "B: TOPRIGHT anchored to the ScrollContainer at (-8, -40)")
CHECK(bottomRight and bottomRight.rel == container and bottomRight.relPoint == "BOTTOMRIGHT"
    and bottomRight.x == -8 and bottomRight.y == 8, "B: BOTTOMRIGHT anchored to the ScrollContainer at (-8, 8)")
CHECK(drawer and drawer.__w == 250, "B: 250 wide on the maximized map", drawer and drawer.__w)
CHECK(drawer and drawer.__level == 2757 + 10,
    "B: frame level = ten over the map's topmost pin level, which the container + 2200 (2205) is not",
    drawer and drawer.__level)
CHECK(drawer and drawer.__level > 2016 and drawer.__level > 2754,
    "B: above Questie's 2016+ icons and the player arrow and party dots (2754)")
CHECK(drawer and drawer.header.__level == drawer.__level + 2, "B: the header strip sits above the panel")
CHECK(drawer and drawer.__mouse == true, "B: the panel takes the mouse (clicks never reach the canvas)")
CHECK(drawer and drawer.__wheel == true, "B: the panel takes the wheel")
CHECK(drawer and type(drawer.__scripts.OnMouseWheel) == "function", "B: wheel handler set")
CHECK(drawer and SAME_COLOUR(drawer.base.__color, 0.04, 0.04, 0.05) and NEAR(drawer.base.__color[4], 0.88),
    "B: dark quad base (0.04, 0.04, 0.05, 0.88)")
CHECK(drawer and #drawer.edges == 4 and SAME_COLOUR(drawer.edges[1].__color, 0.55, 0.65, 0.80),
    "B: 1px border quads in the steel fallback accent (no window kit loaded)")
CHECK(drawer and drawer.edges[1].__color and NEAR(drawer.edges[1].__color[4], 0.35), "B: border at low alpha")

local header = drawer.header
local hellfire = ViewOf(3483)
CHECK(hellfire ~= nil, "B: the adapter has a Hellfire view")
CHECK(header.name.__text == "Hellfire Peninsula", "B: header names the zone", header.name.__text)
CHECK(header.totals.__text == "2/13 \194\183 15%", "B: header shows done/counted and the floored percent",
    header.totals.__text)
CHECK(header.totals.__text == C.TotalsText(hellfire.totals, true), "B: header totals are the engine's compact text")
CHECK(SAME_COLOUR(header.name.__textColor, 1.00, 0.82, 0.30), "B: zone name in the dark-skin title ink")
CHECK(SAME_COLOUR(header.totals.__textColor, 0.92, 0.90, 0.86), "B: totals in the primary ink")
CHECK(header.message.__shown == false, "B: no message line when the zone has a view")
CHECK(header.barBg.__shown and header.barBg.__h == 3, "B: 3px bar track under the strip")
CHECK(header.barFill.__shown and NEAR(header.barFill.__w, (250 - 16) * (2 / 13), 1e-6),
    "B: bar fill is the completed fraction of the strip", header.barFill.__w)
CHECK(header.chevron and header.chevron[1].__shown and header.chevron[2].__shown, "B: quad chevron drawn")
CHECK(header.__level ~= nil and header.__scripts.OnClick ~= nil, "B: the strip is clickable")
local tip = attachedTooltips[header]
CHECK(tip and tip.anchor == "ANCHOR_LEFT", "B: strip tooltip attached through Commander.UI.AttachTooltip")
CHECK(tip and type(tip.text) == "function" and tip.text():find("100%", 1, true) ~= nil,
    "B: strip tooltip explains what counts toward 100%")

local counted = hellfire.totals.countedByStatus
local expectedBreakdown = string.format("Done %d \194\183 In log %d \194\183 Open %d \194\183 Locked %d",
    counted.DONE, counted.LOG, counted.AVAILABLE, counted.LOCKED)
CHECK(drawer.breakdown.__shown and drawer.breakdown.__text == expectedBreakdown,
    "B: breakdown line from the counted buckets", drawer.breakdown.__text)
CHECK(drawer.breakdown.__text == "Done 2 \194\183 In log 1 \194\183 Open 8 \194\183 Locked 2",
    "B: breakdown adds up to the denominator", drawer.breakdown.__text)
CHECK(counted.DONE + counted.LOG + counted.AVAILABLE + counted.LOCKED == hellfire.totals.counted,
    "B: (and the four numbers do sum to 13)")

-- The list: STATUS-like groups, Done folded by default
local model = M._Model()
local headers = {}
for _, item in ipairs(model) do
    if item.kind == "HEADER" then headers[#headers + 1] = item.title end
end
CHECK(table.concat(headers, "|") == "In your log|Open|Locked|Missed|Done", "B: groups in order",
    table.concat(headers, "|"))
local doneHeader
for _, item in ipairs(model) do if item.kind == "HEADER" and item.title == "Done" then doneHeader = item end end
CHECK(doneHeader and doneHeader.collapsed == true and doneHeader.count == 2, "B: Done folded by default, count 2")
local doneRows = 0
for _, item in ipairs(model) do
    if item.kind == "QUEST" and item.entry.status == "DONE" then doneRows = doneRows + 1 end
end
CHECK(doneRows == 0, "B: no Done quest rows while folded")
CHECK(type(CommanderQuestLogDB.MapCollapsed) == "table" and CommanderQuestLogDB.MapCollapsed.Done == true,
    "B: a DB without the key gets MapCollapsed = { Done = true }")
CHECK(#model == 20, "B: 5 headers + 15 quest rows", #model)
CHECK(#ShownRows() == 20, "B: every row fits on a 600px container", #ShownRows())

local logRow = QuestRow(9003)
CHECK(logRow ~= nil, "B: the quest in the log has a row")
CHECK(logRow and logRow.item.entry.status == "LOG", "B: 9003 is under In your log")
CHECK(logRow and logRow.state.__text == "log", "B: state word from the engine", logRow and logRow.state.__text)
CHECK(logRow and logRow.title.__text == "Force Commander Danath", "B: title")
CHECK(logRow and logRow.level.__text == "60", "B: level", logRow and logRow.level.__text)
CHECK(logRow and logRow.strip.__shown and logRow.strip.__w == 3, "B: 3px status strip")
CHECK(logRow and SAME_COLOUR(logRow.strip.__color, 1.00, 0.85, 0.35), "B: strip tinted by the state's colour key")
CHECK(logRow and SAME_COLOUR(logRow.title.__textColor, 0.92, 0.90, 0.86), "B: counted title in primary ink")
CHECK(logRow and SAME_COLOUR(logRow.level.__textColor, 0.72, 0.70, 0.66),
    "B: level in secondary ink when the model's difficulty colours are not loaded")
CHECK(logRow and logRow.__h == 16, "B: rows are 16px")
local slotRow = QuestRow(9013)
CHECK(slotRow and SAME_COLOUR(slotRow.title.__textColor, 0.50, 0.50, 0.50),
    "B: an uncounted slot member's title is dimmed")
local lockedRow = QuestRow(9007)
CHECK(lockedRow and lockedRow.state.__text == "lv 63" and SAME_COLOUR(lockedRow.state.__textColor, 0.95, 0.60, 0.30),
    "B: level-locked state word in the warn ink", lockedRow and lockedRow.state.__text)
local missedRow = QuestRow(9021)
CHECK(missedRow and missedRow.state.__text == "missed", "B: a missed quest is listed under Missed")
local openHeader = HeaderRow("Open")
CHECK(openHeader and openHeader.state.__text == "9" and openHeader.chevron[1].__shown,
    "B: header row: chevron, title, count", openHeader and openHeader.state.__text)
CHECK(openHeader and openHeader.strip.__shown == false and openHeader.level.__shown == false,
    "B: header rows carry no strip and no level")
CHECK(QuestRow(9011) == nil and QuestRow(9008) == nil and QuestRow(9016) == nil,
    "B: rival, daily and starts-here quests are not in the drawer's five groups")
local firstRow = ShownRows()[1]
CHECK(firstRow and FindPoint(firstRow, "TOPLEFT") and FindPoint(firstRow, "TOPLEFT").y == -48,
    "B: the list starts under the strip and the breakdown line")
CHECK(firstRow and firstRow.__w == 250 - 12 - 6, "B: rows span the drawer minus padding and the gutter")
CHECK(firstRow and firstRow.__level == drawer.__level + 2, "B: rows above the panel")
CHECK(drawer.track.__shown == false, "B: no scroll indicator when everything fits")

-- ===========================================================================
-- C. Pins on Hellfire
-- ===========================================================================

local provider, pool = M._Provider()
CHECK(WM.providerAdds == 1, "C: data provider registered once")
CHECK(provider and WM.providers[1] == provider, "C: it is our provider")
CHECK(pool and WM.fields.pinPools[PIN_TEMPLATE] == pool, "C: pool registered under CommanderQuestLogPinTemplate")
CHECK(pool and pool.GetTemplate and pool:GetTemplate() == PIN_TEMPLATE and getmetatable(pool) == nil,
    "C: the unsecured pool (HereBeDragons' route on 2.5.6), not CreateFramePool's proxy")
CHECK(pool and pool.creationFunc == pool.createFunc and type(pool.createFunc) == "function",
    "C: creationFunc AND createFunc set (both generations)")
CHECK(pool and pool.resetterFunc == pool.resetFunc and type(pool.resetFunc) == "function",
    "C: resetterFunc AND resetFunc set")
CHECK(pool and pool.parent == WM.canvas, "C: pool parent is the canvas")

local giverPins = GiverPins()
CHECK(#giverPins > 0, "C: giver pins acquired")
local pin9004 = PinsWith(9004)[1]
CHECK(pin9004 ~= nil, "C: the locked 9004 has a pin")
CHECK(pin9004 and NEAR(pin9004.__x, 0.566) and NEAR(pin9004.__y, 0.664), "C: at its giver, 0..1",
    pin9004 and (tostring(pin9004.__x) .. "," .. tostring(pin9004.__y)))
CHECK(pin9004 and pin9004.data.look == "LOCKED", "C: locked look")
CHECK(pin9004 and pin9004.icon.__texture == "Interface\\AddOns\\Questie\\Icons\\available_gray.blp",
    "C: Questie's grey available icon")
CHECK(pin9004 and pin9004.__w == 16 and pin9004.__h == 16, "C: 16px")
CHECK(pin9004 and #pin9004.data.quests == 1, "C: the done 9002 and the logged 9003 at that giver are left off",
    pin9004 and #pin9004.data.quests)
CHECK(pin9004 and pin9004.__parent == WM.canvas, "C: pins live on the canvas")
CHECK(pin9004 and pin9004.pinTemplate == PIN_TEMPLATE and pin9004.owningMap == WorldMapFrame,
    "C: acquired through the map")
local pin9007 = PinsWith(9007)[1]
CHECK(pin9007 and NEAR(pin9007.__x, 0.78) and NEAR(pin9007.__y, 0.34) and pin9007.data.look == "LOCKED",
    "C: the level-locked 9007 at (78.0, 34.0)")
CHECK(#PinsWith(9005) == 0 and #PinsWith(9006) == 0, "C: nothing for the quests Questie draws itself")
CHECK(#PinsWith(9010) == 1 and PinsWith(9010)[1].data.look == "AVAILABLE"
    and PinsWith(9010)[1].icon.__texture == "Interface\\AddOns\\Questie\\Icons\\available.blp",
    "C: an available quest Questie does not draw gets the available look")
CHECK(#PinsWith(9015) == 1 and NEAR(PinsWith(9015)[1].__x, 0.58) and NEAR(PinsWith(9015)[1].__y, 0.40),
    "C: a giver standing in a subzone is drawn on the parent zone's map")
CHECK(#PinsWith(9033) == 5, "C: one giver with eight spawns: five pins", #PinsWith(9033))
CHECK(#PinsWith(9022) == 0, "C: an item-started quest has no pin")
CHECK(#PinsWith(9023) == 0, "C: a quest whose giver stands in Terokkar has no pin on Hellfire")
CHECK(#PinsWith(9001) == 0 and PinAt(0.874, 0.507) == nil, "C: no Done pins while MapPinsDone is off")
CHECK(#PinsWith(9009) == 0 and #PinsWith(9020) == 0 and #PinsWith(9021) == 0, "C: no Missed pins by default")
CHECK(#PinsWith(9008) == 0 and #PinsWith(9011) == 0 and #PinsWith(9016) == 0 and #PinsWith(9018) == 0
    and #PinsWith(9019) == 0, "C: never a pin for daily, rival, starts-here, optional or seasonal quests")
local mixinOk, stubOk = true, true
for _, p in ipairs(giverPins) do
    if p.__levelType ~= "PIN_FRAME_LEVEL_AREA_POI" then mixinOk = false end
    local scaling = p.__scaling
    if not (scaling and scaling[1] == 1 and scaling[2] == 1.0 and scaling[3] == 1.2) then mixinOk = false end
    if type(p.SetPassThroughButtons) ~= "function" or not pcall(p.SetPassThroughButtons, p, "LeftButton") then
        stubOk = false
    end
end
CHECK(mixinOk, "C: every pin: PIN_FRAME_LEVEL_AREA_POI, scaling limits (1, 1.0, 1.2)")
CHECK(pin9004 and pin9004.__level == 2018 and pin9004._loaded,
    "C: a pin got its OnLoad from AcquirePin and its level (2018) from the map's manager", pin9004 and pin9004.__level)
CHECK(stubOk, "C: every pin carries the SetPassThroughButtons no-op")
CHECK(pin9004 and pin9004.__motion == true and pin9004.__click == false,
    "C: pins take mouse motion only, so clicks reach the map")
CHECK(pin9004 and type(pin9004.__scripts.OnEnter) == "function" and type(pin9004.__scripts.OnLeave) == "function",
    "C: pin hover wired")
CHECK(pin9004 and RingShown(pin9004) == false, "C: no focus ring until something is focused")

-- Pin tooltip: the giver, then each quest with its word and reason
if pin9004 then Hover(pin9004) end
local entry9004 = hellfire.byId[9004]
local reason9004 = C.Reason(entry9004, A.Character(), hellfire)
CHECK(TooltipHas("Force Commander Danath"), "C: pin tooltip names the giver", AllTooltipText())
CHECK(TooltipHas("The Legion Reborn  chain"), "C: each quest with its state word", AllTooltipText())
CHECK(TooltipHas(reason9004) and reason9004 ~= "", "C: and the engine's reason", reason9004)

-- Each filter, live
SetSetting("MapPinsDone", true)
local donePin = PinAt(0.874, 0.507)
CHECK(donePin and PinHas(donePin, 9001) and donePin.data.look == "DONE", "C: MapPinsDone draws the done giver")
CHECK(donePin and donePin.icon.__texture == "Interface\\AddOns\\Questie\\Icons\\checkmark.tga"
    and donePin.__w == 14, "C: done look is Questie's checkmark at 14px")
pin9004 = PinsWith(9004)[1]
CHECK(pin9004 and PinHas(pin9004, 9002) and pin9004.data.look == "LOCKED",
    "C: a shared giver wears the best look (locked over done)")
SetSetting("MapPinsMissed", true)
local missedPin = PinAt(0.565, 0.655)
CHECK(missedPin and PinHas(missedPin, 9020) and missedPin.data.look == "MISSED",
    "C: MapPinsMissed draws the missed giver")
CHECK(missedPin and SAME_COLOUR(missedPin.icon.__vertex, 0.9, 0.35, 0.3) and NEAR(missedPin.icon.__alpha, 0.7),
    "C: missed look is the grey icon tinted red at 0.7")
CHECK(#PinsWith(9009) == 1 and PinsWith(9009)[1].data.look == "MISSED" and not PinHas(PinsWith(9009)[1], 9008),
    "C: a missed quest shares no pin with a daily at the same giver")
SetSetting("MapPinsLocked", false)
CHECK(#PinsWith(9007) == 0 and #PinsWith(9004) == 0, "C: MapPinsLocked off removes the locked givers")
CHECK(#PinsWith(9021) == 1 and PinsWith(9021)[1].data.look == "MISSED", "C: the missed quest at 9007's giver stays")
SetSetting("MapPinsAvailable", false)
CHECK(#PinsWith(9010) == 0 and #PinsWith(9033) == 0, "C: MapPinsAvailable off removes the available givers")
SetSetting("MapPins", false)
CHECK(#ActivePins() == 0, "C: MapPins off: no pins at all")
SetSetting("MapPins", nil)
SetSetting("MapPinsAvailable", nil)
SetSetting("MapPinsLocked", nil)
SetSetting("MapPinsDone", nil)
SetSetting("MapPinsMissed", nil)
CHECK(#PinsWith(9004) == 1 and #PinsWith(9001) == 0 and #PinsWith(9020) == 0, "C: defaults restored")
fake.SetAvailable(9010, true)
A.Bump("test")
Settle()
CHECK(#PinsWith(9010) == 0, "C: once Questie draws a quest, our pin for it goes")
fake.SetAvailable(9010, false)
A.Bump("test")
Settle()
CHECK(#PinsWith(9010) == 1, "C: and comes back when Questie stops")

-- ===========================================================================
-- D. Drawer interactions
-- ===========================================================================

-- The strip folds the drawer away, persists, and does not recompute anything
local generation = A.generation
Click(header)
Settle()
CHECK(CommanderQuestLogDB.MapDrawerOpen == false, "D: strip click persists MapDrawerOpen = false")
CHECK(drawer.__points and #drawer.__points == 1 and FindPoint(drawer, "TOPRIGHT") and drawer.__h == 30,
    "D: folded: one anchor, 30px strip", drawer.__h)
CHECK(#ShownRows() == 0 and drawer.breakdown.__shown == false, "D: folded: no list, no breakdown")
CHECK(header.totals.__text == "2/13 \194\183 15%" and header.barBg.__shown, "D: folded strip keeps totals and bar")
CHECK(header.chevron[1].__shown, "D: folded strip keeps its chevron")
CHECK(A.generation == generation, "D: folding does not bump the adapter's generation")
Click(header)
CHECK(CommanderQuestLogDB.MapDrawerOpen == true and #ShownRows() == 20, "D: a second click opens it again")
CHECK(FindPoint(drawer, "BOTTOMRIGHT") ~= nil, "D: open again: bottom anchor back")

-- Group folds
Click(HeaderRow("Open"))
CHECK(CommanderQuestLogDB.MapCollapsed.Open == true, "D: a group header folds into MapCollapsed")
local openRows = 0
for _, row in ipairs(ShownRows()) do
    if row.item.kind == "QUEST" and row.item.entry.status == "AVAILABLE" then openRows = openRows + 1 end
end
CHECK(openRows == 0 and HeaderRow("Open") ~= nil, "D: folded group keeps its header, loses its rows")
-- SetRotation turns counter-clockwise: "\" over "/" is ">", the other way
-- round it was "<"
CHECK(HeaderRow("Open").chevron[1].__rotation == -math.pi / 4 and HeaderRow("Open").chevron[2].__rotation == math.pi / 4,
    "D: folded chevron points right (top bar falling, bottom bar rising)")
Click(HeaderRow("Open"))
CHECK(not CommanderQuestLogDB.MapCollapsed.Open and QuestRow(9010) ~= nil, "D: and unfolds")
CHECK(CommanderQuestLogDB.Collapsed == nil, "D: the log's own Collapsed table is never touched")

-- Row tooltip
local row9004 = QuestRow(9004)
Hover(row9004)
CHECK(tooltipLines[1] == "[62] The Legion Reborn", "D: row tooltip title with level", tooltipLines[1])
CHECK(TooltipHas(reason9004), "D: row tooltip carries the reason sentence", AllTooltipText())
CHECK(TooltipHas("Starts: Force Commander Danath \226\128\148 Hellfire Peninsula 56.6, 66.4"),
    "D: row tooltip carries the giver line", AllTooltipText())
CHECK(TooltipHas("Right-click: Go") and TooltipHas("Ctrl-click"), "D: row tooltip hints")
CHECK(GameTooltip.__anchor == "ANCHOR_LEFT", "D: tooltips open away from the right edge")
Hover(QuestRow(9023))
CHECK(TooltipHas("Starts: Terokkar Exile \226\128\148 Terokkar Forest 40.0, 30.0"),
    "D: a giver in another zone is named with its zone", AllTooltipText())

-- Left click focuses: selection band, pin ring
Click(row9004, "LeftButton")
row9004 = QuestRow(9004)
CHECK(M._State().selected == 9004, "D: left click selects")
CHECK(row9004 and row9004.band.__shown and row9004.band.__color and NEAR(row9004.band.__color[4], 0.22),
    "D: selected row wears the accent band")
CHECK(QuestRow(9007).band.__shown == false, "D: no band on the others")
pin9004 = PinsWith(9004)[1]
CHECK(pin9004 and RingShown(pin9004), "D: the clicked quest's pin pulses")
CHECK(pin9004 and SAME_COLOUR(pin9004.ring[1].__color, 0.55, 0.65, 0.80), "D: ring in the accent")
CHECK(pin9004 and type(pin9004.__scripts.OnUpdate) == "function", "D: the ring breathes while it pulses")
if pin9004 and pin9004.__scripts.OnUpdate then pin9004.__scripts.OnUpdate(pin9004, 0.016) end
CHECK(pin9004 and type(pin9004.ring[1].__alpha) == "number" and pin9004.ring[1].__alpha <= 1,
    "D: the pulse animates the ring's alpha")
CHECK(not RingShown(PinsWith(9007)[1]), "D: other pins do not pulse")
Advance(3100)
CHECK(not RingShown(PinsWith(9004)[1]), "D: the pulse ends after about three seconds")
CHECK(M._State().focusQuest == nil, "D: focus cleared when the pulse ends")
CHECK(M._State().selected == 9004, "D: the selection outlives the pulse")

-- Right click: waypoint to the giver through Commander Orders
orders = {}
Click(QuestRow(9004), "RightButton")
CHECK(#orders == 1 and orders[1].uiMapId == 1944 and NEAR(orders[1].x, 0.566) and NEAR(orders[1].y, 0.664),
    "D: right-click sends the giver to Commander Orders (uiMap, 0..1)", #orders)
CHECK(orders[1] and orders[1].spec and orders[1].spec.key == "quest:9004" and orders[1].spec.source == "QuestLog",
    "D: ...as that quest's own waypoint", orders[1] and orders[1].spec and orders[1].spec.key)

-- Right click on the header strip: the zone's open quests, one route
orders = {}
local openBefore = CommanderQuestLogDB.MapDrawerOpen
Click(drawer.header, "RightButton")
local route = orders[1] and orders[1].route
CHECK(#orders == 1 and route and route.key == "open:3483" and route.source == "QuestLog" and route.mode == "NEAREST"
    and #route.stops == 6, "D: right-click on the strip routes Hellfire's open quests through Commander Orders",
    route and (tostring(route.key) .. " " .. #route.stops))
CHECK(CommanderQuestLogDB.MapDrawerOpen == openBefore, "D: ...without folding the drawer")
CHECK(attachedTooltips[drawer.header].text():find("Right-click for a Commander Orders route", 1, true),
    "D: the strip's tooltip says so")

-- Ctrl-click: the map closes, then the window opens on the quest
ctrlDown = true
hidePanelCalls = {}
Click(QuestRow(9004), "LeftButton")
ctrlDown = false
CHECK(WorldMapFrame:IsShown() == false and #hidePanelCalls == 1 and hidePanelCalls[1] == WorldMapFrame,
    "D: ctrl-click closes the map through HideUIPanel (never WorldMapFrame:Hide)")
CHECK(#openCalls == 1 and openCalls[1].areaId == 3483 and openCalls[1].questId == 9004,
    "D: then CommanderQuestLog_OpenToZone(3483, 9004)")
WorldMapFrame:Show()
CHECK(M._State().refreshes > 0 and drawer.__shown, "D: the map comes back with the drawer")

-- In combat HideUIPanel from addon code is refused (and the client says an
-- AddOn was blocked): the map stays, the window still opens, and a line
-- says how to see it
InCombatLockdown = function() return true end
ctrlDown = true
hidePanelCalls, openCalls = {}, {}
Click(QuestRow(9004), "LeftButton")
ctrlDown = false
InCombatLockdown = nil
CHECK(#hidePanelCalls == 0 and WorldMapFrame:IsShown(),
    "D: in combat, ctrl-click does not call HideUIPanel (it would be refused)", #hidePanelCalls)
CHECK(#openCalls == 1 and openCalls[1].questId == 9004, "D: ...the quest log still opens on the quest")
CHECK((printLog[#printLog] or ""):find("close it (M)", 1, true), "D: ...and a line says how to see it",
    printLog[#printLog])

-- Mouse wheel on a short container
container.__h = 200
container.__scripts.OnSizeChanged(container)
local visible = M._State().visibleRows
CHECK(visible == 6, "D: a 200px container shows six rows", visible)
CHECK(#ShownRows() == 6, "D: six rows drawn", #ShownRows())
CHECK(drawer.track.__shown and drawer.thumb.__shown, "D: the quad scroll indicator appears")
CHECK(drawer.track.__h == 6 * 16 and drawer.thumb.__h >= 10 and drawer.thumb.__h < drawer.track.__h,
    "D: thumb is a share of the track", drawer.thumb.__h)
local topBefore = ShownRows()[1].item
drawer.__scripts.OnMouseWheel(drawer, -1)
CHECK(M._State().offset == 2 and ShownRows()[1].item == M._Model()[3], "D: one notch down scrolls two rows")
CHECK(ShownRows()[1].item ~= topBefore, "D: the first row changed")
CHECK(FindPoint(drawer.thumb, "TOPRIGHT").y < -48, "D: the thumb moved down")
drawer.__scripts.OnMouseWheel(drawer, -100)
CHECK(M._State().offset == #M._Model() - 6, "D: scrolling clamps at the end", M._State().offset)
drawer.__scripts.OnMouseWheel(drawer, 100)
CHECK(M._State().offset == 0, "D: and at the top")
container.__h = 600
container.__scripts.OnSizeChanged(container)
CHECK(#ShownRows() == 20 and drawer.track.__shown == false, "D: a tall container again: no indicator")

-- Ready to turn in: the waypoint goes to the finisher instead. The quest log
-- window is never opened in this harness, so no window scan says so: the
-- drawer has it from the client's own log, after Questie's quest-update
-- callback moved the generation on
world.logComplete = { [9003] = 1 }
fake.FireQuestUpdate(9003, 2, 1)
Settle()
local ready = QuestRow(9003)
CHECK(ready and ready.item.entry.ready == true and ready.state.__text == "ready",
    "D: a quest the client's log calls complete reads ready, with no window scan", ready and ready.state.__text)
orders = {}
Click(ready, "RightButton")
CHECK(#orders == 1 and NEAR(orders[1].x, 0.54) and NEAR(orders[1].y, 0.63),
    "D: right-click on a ready quest waypoints its finisher", orders[1] and orders[1].x)

-- ===========================================================================
-- E. Relayout: windowed map, container level, the window's kit
-- ===========================================================================

WM.maximized = false
WorldMapFrame:SynchronizeDisplayState()
CHECK(WM.syncs == 1, "E: Blizzard's SynchronizeDisplayState still runs under the hook")
CHECK(drawer.__w == 220, "E: 220 wide on the windowed map", drawer.__w)
CHECK(ShownRows()[1].__w == 220 - 18, "E: rows follow the width")
CHECK(NEAR(header.barBg.__w, 220 - 16), "E: the strip's bar follows the width")
WM.maximized = true
WorldMapFrame:SynchronizeDisplayState()
CHECK(drawer.__w == 250, "E: back to 250 maximized")
container.__level = 8000
container.__scripts.OnSizeChanged(container)
CHECK(drawer.__level == 9000, "E: frame level capped at 9000", drawer.__level)
container.__level = 5
container.__scripts.OnSizeChanged(container)
CHECK(drawer.__level == 2767, "E: and comes back down to the pins' floor", drawer.__level)
CHECK(#strataCalls == 0, "E: still no SetFrameStrata after relayouts")

Q._kit = { Accent = function() return 0.2, 0.4, 0.9 end }
M.Refresh()
CHECK(SAME_COLOUR(drawer.edges[1].__color, 0.2, 0.4, 0.9), "E: the window kit's Accent drives the border when present")
CHECK(SAME_COLOUR(header.barFill.__color, 0.2, 0.4, 0.9), "E: and the bar fill")
Q._kit = { Accent = function() error("kit broke") end }
M.Refresh()
CHECK(SAME_COLOUR(drawer.edges[1].__color, 0.55, 0.65, 0.80), "E: a kit that errors falls back to steel")
Q._kit = nil

-- ===========================================================================
-- F. A continent: zone rows, summaries, label pins
-- ===========================================================================

requestLog = {}
WorldMapFrame:SetMapID(1945)
CHECK(header.name.__text == "Outland", "F: header names the continent", header.name.__text)
local zoneNames = {}
for _, row in ipairs(ShownRows()) do
    zoneNames[#zoneNames + 1] = row.item.kind == "ZONE" and row.item.zone.name or "?"
end
CHECK(table.concat(zoneNames, "|") == "Hellfire Peninsula|Terokkar Forest", "F: the continent's quest zones, by name",
    table.concat(zoneNames, "|"))
local terokkarRow = ZoneRow("Terokkar Forest")
CHECK(terokkarRow and terokkarRow.state.__text == "..." and SAME_COLOUR(terokkarRow.state.__textColor, 0.5, 0.5, 0.5),
    "F: a zone not yet counted reads ... in faint ink", terokkarRow and terokkarRow.state.__text)
local asked = false
for _, ids in ipairs(requestLog) do for _, id in ipairs(ids) do if id == 3519 then asked = true end end end
CHECK(asked, "F: the missing summary is requested from the adapter")
CHECK(drawer.breakdown.__text:find("still counting", 1, true) ~= nil, "F: the breakdown says counting is under way",
    drawer.breakdown.__text)
CHECK(#GiverPins() == 0, "F: no giver pins on a continent")
orders = {}
Click(header, "RightButton")
CHECK(#orders == 0, "F: a continent has no zone to route: right-click on the strip does nothing", #orders)
CHECK(not attachedTooltips[header].text():find("Right-click", 1, true), "F: ...and its tooltip offers none")
Settle()
terokkarRow = ZoneRow("Terokkar Forest")
local hellfireRow = ZoneRow("Hellfire Peninsula")
CHECK(terokkarRow and terokkarRow.state.__text == "0%", "F: the summary arrives and the row redraws",
    terokkarRow and terokkarRow.state.__text)
CHECK(hellfireRow and hellfireRow.state.__text == "15%", "F: Hellfire 15%", hellfireRow and hellfireRow.state.__text)
CHECK(hellfireRow and hellfireRow.barBg.__shown and hellfireRow.barBg.__h == 3
    and hellfireRow.barFill.__shown and NEAR(hellfireRow.barFill.__w, (232 - 4) * 2 / 13),
    "F: each zone row has a 3px bar", hellfireRow and hellfireRow.barFill.__w)
CHECK(terokkarRow and terokkarRow.barFill.__shown == false, "F: a 0% zone has an empty bar")
CHECK(header.totals.__text == "2/15 \194\183 13%", "F: the continent header sums its zones", header.totals.__text)
CHECK(drawer.breakdown.__text == "2 zones with quests", "F: breakdown once every zone is counted",
    drawer.breakdown.__text)
local labels = LabelPins()
CHECK(#labels == 2, "F: one label pin per counted zone", #labels)
local hellfireLabel = PinAt(0.65, 0.55)
local terokkarLabel = PinAt(0.5, 0.75)
CHECK(hellfireLabel and hellfireLabel.data.kind == "LABEL" and hellfireLabel.label.__text == "15%",
    "F: Hellfire's label at the centre of its rectangle on Outland")
CHECK(terokkarLabel and terokkarLabel.label.__text == "0%", "F: Terokkar's label")
CHECK(hellfireLabel and hellfireLabel.icon.__shown == false and hellfireLabel.labelBg.__shown,
    "F: a label pin is words on a dark quad, no icon")
if hellfireLabel then Hover(hellfireLabel) end
CHECK(TooltipHas("Hellfire Peninsula") and TooltipHas("2/13"), "F: label tooltip", AllTooltipText())
Hover(hellfireRow)
CHECK(TooltipHas("Hellfire Peninsula") and TooltipHas("Click to open this zone's map."), "F: zone row tooltip")
SetSetting("MapZoneLabels", false)
CHECK(#LabelPins() == 0, "F: MapZoneLabels off removes the labels")
SetSetting("MapZoneLabels", nil)
CHECK(#LabelPins() == 2, "F: and back")
Click(ZoneRow("Terokkar Forest"))
CHECK(WorldMapFrame:GetMapID() == 1952, "F: a zone row opens that zone's map")
CHECK(header.name.__text == "Terokkar Forest" and header.totals.__text == "0/2 \194\183 0%",
    "F: and the drawer follows", header.totals.__text)
CHECK(header.barFill.__shown == false, "F: 0% draws no fill")

-- ===========================================================================
-- G. Maps with nothing to list
-- ===========================================================================

WorldMapFrame:SetMapID(1941)      -- Eversong Woods: zoneMap junk only
CHECK(header.name.__text == "Eversong Woods", "G: an empty zone keeps its name", header.name.__text)
CHECK(header.message.__shown and header.message.__text == "No quests are filed here.",
    "G: one-line message", header.message.__text)
CHECK(drawer.__h == 30 and #drawer.__points == 1, "G: the drawer collapses to the strip")
CHECK(#ShownRows() == 0 and header.totals.__text == "" and header.barBg.__shown == false,
    "G: no rows, no totals, no bar")
CHECK(header.chevron[1].__shown == false, "G: no chevron on a message strip")
local openSetting = CommanderQuestLogDB.MapDrawerOpen
Click(header)
CHECK(CommanderQuestLogDB.MapDrawerOpen == openSetting, "G: the strip does not toggle with nothing to show")
CHECK(#GiverPins() == 0 and #LabelPins() == 0, "G: no pins")

WorldMapFrame:SetMapID(9999)      -- ZoneDB throws for it
CHECK(header.name.__text == "Nowhere" and header.message.__text == "No quest zone on this map.",
    "G: a map no zone resolves to", header.message.__text)

WorldMapFrame:SetMapID(1946)      -- Zangarmarsh: only a dungeon quest starts here
CHECK(header.name.__text == "Zangarmarsh" and drawer.listMessage.__shown
    and drawer.listMessage.__text == "Only quests outside your 100% are filed here.",
    "G: a zone whose only quests are uncounted says so", drawer.listMessage.__text)

-- Cosmic, where zooming out of Outland lands: every quest zone, not "none".
-- Its summaries land four in a fifth of a second; they redraw the drawer and
-- the labels once, not once each
A.Bump("test")
Settle()
local refreshesBefore = M._State().refreshes
WorldMapFrame:SetMapID(946)
CHECK(header.name.__text == "Cosmic" and not header.message.__shown and #ShownRows() >= 4,
    "G: Cosmic lists the quest zones of every continent", header.message.__text)
Advance(200)
CHECK(M._State().refreshes == refreshesBefore + 1,
    "G: summaries landing inside a quarter second do not each redraw the drawer",
    M._State().refreshes - refreshesBefore)
Settle()
CHECK(M._State().refreshes == refreshesBefore + 2, "G: ...they redraw it once, together",
    M._State().refreshes - refreshesBefore)
local cosmicRows = {}
for _, row in ipairs(ShownRows()) do cosmicRows[#cosmicRows + 1] = row.item.zone.name .. "=" .. tostring(row.state.__text) end
CHECK(ZoneRow("Elwynn Forest") and ZoneRow("Elwynn Forest").state.__text == "100%"
    and ZoneRow("Azuremyst Isle") and ZoneRow("Azuremyst Isle").state.__text == "0%", "G: ...with every zone's figure",
    table.concat(cosmicRows, ", "))

WorldMapFrame:SetMapID(347)       -- Hellfire Ramparts: the Hellfire Citadel group
local citadel = ViewOf(3563)
CHECK(citadel ~= nil, "G: a dungeon map resolves to its group's view")
CHECK(header.name.__text == "Hellfire Citadel" and header.totals.__text == C.TotalsText(citadel.totals, true),
    "G: dungeon maps get the drawer too", header.name.__text)

-- ===========================================================================
-- H. Focus
-- ===========================================================================

WorldMapFrame:SetMapID(1952)
local found = M.Focus(9004, 3483)
CHECK(WorldMapFrame:GetMapID() == 1944, "H: Focus moves the map to the quest's zone first")
CHECK(found == true and M._State().selected == 9004, "H: and selects the quest")
CHECK(QuestRow(9004) and QuestRow(9004).band.__shown, "H: its row is on screen with the band")
CHECK(RingShown(PinsWith(9004)[1]), "H: and its pin pulses")
Settle()
CHECK(not RingShown(PinsWith(9004)[1]), "H: the pulse ends")

-- Wing Commander Dabir (78.0, 34.0) stands under the open drawer, which
-- covers the map's east quarter: while his quest pulses, his pin is lifted
-- over the drawer, and it drops back when the pulse ends
M.Focus(9007)
local east = PinsWith(9007)[1]
CHECK(east and RingShown(east) and east.__level > Drawer().__level,
    "H: a pulsing giver under the drawer is drawn over it", east and (east.__level .. " vs " .. Drawer().__level))
Settle()
east = PinsWith(9007)[1]
CHECK(east and east.__level == 2018, "H: ...and back at its own level once the pulse ends", east and east.__level)

-- A quest the drawer lists no row for (a daily) is not reported found
CHECK(M.Focus(9008) == false, "H: Focus on a quest with no drawer row (a daily) reports not found")
Settle()

-- A done quest in the folded group, with Done pins off
CommanderQuestLogDB.MapCollapsed.Done = true
container.__h = 200
container.__scripts.OnSizeChanged(container)
M.Focus(9001)
CHECK(CommanderQuestLogDB.MapCollapsed.Done == false, "H: focusing a folded quest unfolds its group")
local doneRow = QuestRow(9001)
CHECK(doneRow ~= nil, "H: and scrolls it into view", M._State().offset)
CHECK(M._State().offset > 0, "H: (the list had to scroll)")
local forced = PinsWith(9001)[1]
CHECK(forced and forced.data.look == "DONE" and RingShown(forced), "H: a filtered-out quest gets a pin while it pulses")
Settle()
CHECK(#PinsWith(9001) == 0, "H: which goes when the pulse ends")
container.__h = 600
container.__scripts.OnSizeChanged(container)

-- Focus on a quest Questie draws: our pin appears only for the pulse
M.Focus(9005)
CHECK(#PinsWith(9005) == 1 and RingShown(PinsWith(9005)[1]), "H: even a quest Questie draws is ringed for the pulse")
Settle()
CHECK(#PinsWith(9005) == 0, "H: then left to Questie")
CHECK(M.Focus(nil) == false and M.Focus("x") == false, "H: Focus refuses junk")
container.__h = 200
container.__scripts.OnSizeChanged(container)
drawer.__scripts.OnMouseWheel(drawer, 100)
WorldMapFrame:Hide()
CHECK(M.Focus(9004) == false, "H: Focus with the map closed selects but reports not found")
CHECK(M._State().selected == 9004, "H: (the selection is kept for the next show)")
WorldMapFrame:Show()
CHECK(QuestRow(9004) ~= nil and M._State().offset > 0, "H: the next show scrolls to the quest focused while closed",
    M._State().offset)
CHECK(RingShown(PinsWith(9004)[1]), "H: and its pin pulses if the pulse is still running")
Settle()

-- Focus with the drawer FOLDED: the offset is sized by the rows the open
-- list will hold, so the quest is in view when the player unfolds it
drawer.__scripts.OnMouseWheel(drawer, 100)
Click(drawer.header)
CHECK(CommanderQuestLogDB.MapDrawerOpen == false, "H: (the drawer is folded)")
M.Focus(9010)
Click(drawer.header)
CHECK(QuestRow(9010) ~= nil, "H: a quest focused while the drawer was folded is in view when it unfolds",
    M._State().offset)
Settle()
container.__h = 600
container.__scripts.OnSizeChanged(container)

-- ===========================================================================
-- I. Settings that hide things
-- ===========================================================================

SetSetting("MapDrawer", false)
CHECK(drawer.__shown == false, "I: MapDrawer off hides the drawer")
CHECK(#GiverPins() > 0, "I: pins do not depend on the drawer")
SetSetting("MapDrawer", true)
CHECK(drawer.__shown == true, "I: MapDrawer on shows it again")
SetSetting("EnableQuestLog", false)
CHECK(drawer.__shown == false and #ActivePins() == 0, "I: the module switch hides the drawer and every pin")
SetSetting("EnableQuestLog", nil)
CHECK(drawer.__shown == true and #GiverPins() > 0, "I: and both come back")

-- ===========================================================================
-- J. Hygiene for the main run
-- ===========================================================================

local leaked = {}
for k in pairs(_G) do
    if not globalsBefore[k] and k ~= "CommanderQuestLogMapDrawer" then leaked[#leaked + 1] = tostring(k) end
end
CHECK(#leaked == 0, "J: no global but CommanderQuestLogMapDrawer", table.concat(leaked, ","))
CHECK(#WM.writes == 0, "J: never assigned a field on WorldMapFrame", table.concat(WM.writes, ","))
local containerKeys = {}
for k, v in pairs(container) do
    if type(v) ~= "function" and type(k) == "string" and k:sub(1, 2) ~= "__" then
        containerKeys[#containerKeys + 1] = k
    end
end
CHECK(#containerKeys == 0, "J: nothing assigned on the ScrollContainer", table.concat(containerKeys, ","))
CHECK(#strataCalls == 0, "J: SetFrameStrata never called on anything")
CHECK(WM.providerAdds == 1, "J: the provider was added exactly once over the whole run")
local pinKeys = {}
for k in pairs(WM.fields.pinPools) do pinKeys[#pinKeys + 1] = k end
CHECK(#pinKeys == 1 and pinKeys[1] == PIN_TEMPLATE, "J: exactly one pool key added under pinPools")
CHECK(#fake.forbidden == 0, "J: no forbidden Questie call", table.concat(fake.forbidden, ","))
CHECK(#fake.styleErrors == 0, "J: no dot/colon misuse", table.concat(fake.styleErrors, ","))
CHECK(#fake.ModulesCreated() == 0, "J: no Questie module conjured")
CHECK(#caughtErrors == 0, "J: no error reported", caughtErrors[1])
CHECK(WM.canvasPasses > 0 and WM.canvasErrors == 0,
    "J: Blizzard's every-pin canvas pass ran over our pins and found none bare", WM.canvasErrors)
CHECK(M._State().lastError == nil, "J: no hook error swallowed", M._State().lastError)
local glyphBad = {}
for _, text in ipairs(textLog) do if not GlyphFree(text) then glyphBad[#glyphBad + 1] = text end end
CHECK(#glyphBad == 0, "J: no shape glyph in any drawn string", glyphBad[1])
local framesNamed = 0
for _, f in ipairs(allFrames) do if f.__name then framesNamed = framesNamed + 1 end end
CHECK(framesNamed == 1, "J: one named frame in all", framesNamed)
CHECK(WM.fields.SynchronizeDisplayState ~= WM.originalSync and WM.fields.OnMapChanged ~= WM.originalChanged,
    "J: SynchronizeDisplayState and OnMapChanged went through hooksecurefunc")

-- ===========================================================================
-- K. Questie still loading on first show; AcquirePin calling OnLoad
-- ===========================================================================

caughtErrors = {}
Boot({ edit = function(w) w.ready = false end })
CHECK(A.State() == "LOADING", "K: the fake says loading")
WorldMapFrame:Show()
drawer = Drawer()
CHECK(M.IsBuilt() and drawer.__shown, "K: the drawer is built while Questie loads")
CHECK(drawer.header.message.__text == "Questie is still loading..." and drawer.__h == 30,
    "K: one-line loading message, collapsed", drawer.header.message.__text)
CHECK(drawer.header.name.__text == "Hellfire Peninsula", "K: named from the map while loading")
CHECK(#ActivePins() == 0, "K: no pins before Questie is ready")
fake.SetReady()
Settle()
CHECK(A.State() == "READY", "K: ready")
CHECK(drawer.header.totals.__text == "2/13 \194\183 15%" and drawer.header.message.__shown == false,
    "K: the drawer fills in on its own when Questie is ready", drawer.header.totals.__text)
CHECK(#ShownRows() == 20, "K: with its list")
local k9004 = PinsWith(9004)[1]
CHECK(k9004 and k9004._loaded and k9004.__levelType == "PIN_FRAME_LEVEL_AREA_POI",
    "K: pins work when AcquirePin itself calls OnLoad")
CHECK(#caughtErrors == 0, "K: no errors", caughtErrors[1])

-- ===========================================================================
-- L. Questie absent: nothing built, nothing raised
-- ===========================================================================

caughtErrors = {}
Boot({ absent = true })
CHECK(A.State() == "ABSENT", "L: no Questie")
WorldMapFrame:Show()
WorldMapFrame:SetMapID(1952)
CHECK(M.IsBuilt() == false, "L: no drawer")
CHECK(_G.CommanderQuestLogMapDrawer == nil, "L: no drawer global")
CHECK(WM.providerAdds == 0 and next(WM.fields.pinPools) == nil, "L: no provider, no pool")
CHECK(M.Focus(9004, 3483) == false, "L: Focus declines")
local refreshOk = pcall(M.Refresh)
CHECK(refreshOk, "L: Refresh is harmless")
CHECK(#caughtErrors == 0, "L: no errors", caughtErrors[1])
CHECK(#WM.writes == 0, "L: WorldMapFrame untouched")

-- ===========================================================================
-- M. Settings off before the first show; the late world map
-- ===========================================================================

caughtErrors = {}
Boot({ db = { MapDrawer = false } })
WorldMapFrame:Show()
CHECK(M.IsBuilt() == false, "M: MapDrawer off at first show: the drawer is not built")
CHECK(WM.providerAdds == 1 and #GiverPins() > 0, "M: but the pins are")
SetSetting("MapDrawer", true)
CHECK(M.IsBuilt() and Drawer().__shown, "M: turning it on builds and shows the drawer")

caughtErrors = {}
Boot({ noMap = true })
CHECK(M._State().attached == false, "M: no world map at PLAYER_LOGIN: not attached")
WM = NewWorldMap()
WorldMapFrame = WM.frame
Fire("ADDON_LOADED", "SomeOtherAddon")
CHECK(M._State().attached == false, "M: another addon loading changes nothing")
Fire("ADDON_LOADED", "Blizzard_WorldMap")
CHECK(M._State().attached == true, "M: ADDON_LOADED Blizzard_WorldMap is the second chance")
Fire("ADDON_LOADED", "Blizzard_WorldMap")
Fire("PLAYER_LOGIN")
WorldMapFrame:Show()
CHECK(M.IsBuilt(), "M: built on the late map's first show")
local before, removes = M._State().refreshes, WM.removeCalls
WorldMapFrame:SetMapID(1952)
CHECK(M._State().refreshes == before + 1, "M: hooked once: one refresh per map change",
    M._State().refreshes - before)
CHECK(WM.removeCalls == removes + 1, "M: the pins are redrawn once per map change, by the map's own provider pass",
    WM.removeCalls - removes)
CHECK(Drawer().header.name.__text == "Terokkar Forest", "M: and it draws")
-- Blizzard's own OnShow has refreshed every provider before the post-hook
-- runs; the hook must not draw the pins a second time
WorldMapFrame:Hide()
removes = WM.removeCalls
WorldMapFrame:Show()
CHECK(WM.removeCalls == removes + 1, "M: a re-show redraws the pins once, in the map's own provider pass",
    WM.removeCalls - removes)
CHECK(#caughtErrors == 0, "M: no errors", caughtErrors[1])

-- Blizzard moves the map to the player's zone inside its own OnShow, so our
-- map-change hook runs (map shown, nothing built yet) before our OnShow hook
caughtErrors = {}
Boot()
WM.mapID, WM.showMapID = 1952, 1944
WorldMapFrame:Show()
CHECK(WorldMapFrame:GetMapID() == 1944 and M.IsBuilt(), "M: a map change inside Blizzard's OnShow builds the drawer")
CHECK(Drawer().header.name.__text == "Hellfire Peninsula", "M: for the map the player ends up on")
CHECK(WM.providerAdds == 1 and #PinsWith(9004) == 1, "M: one provider, and its pins are drawn for that map")
CHECK(#caughtErrors == 0, "M: no errors", caughtErrors[1])

-- A broken view does not break the map: the adapter answers ADAPTER_ERROR
caughtErrors = {}
Boot()
WorldMapFrame:Show()
local realView = A.ZoneView
A.ZoneView = function() return nil, "ADAPTER_ERROR" end
M.Refresh()
CHECK(Drawer().header.message.__text == "Zone unreadable: /cql status",
    "M: a view error is a message, not a Lua error", Drawer().header.message.__text)
-- The error lines are one 10-pt line in the windowed drawer's 194 px (the
-- review's 5.5 px a character): cut, they lost the "/cql status" part
CHECK(#Drawer().header.message.__text * 5.5 <= 194, "M: the zone error fits the windowed strip",
    #Drawer().header.message.__text * 5.5)
local realState = A.State
A.State = function() return "BROKEN", "a test" end
M.Refresh()
CHECK(Drawer().header.message.__text == "Questie unreadable: /cql status"
    and #Drawer().header.message.__text * 5.5 <= 194, "M: so does the Questie error",
    Drawer().header.message.__text)
A.State = realState
A.ZoneView = realView
M.Refresh()
CHECK(Drawer().header.totals.__text == "2/13 \194\183 15%", "M: and recovers on the next draw")
CHECK(#caughtErrors == 0, "M: no errors", caughtErrors[1])

-- ===========================================================================
-- N. A client without CreateUnsecuredRegionPoolInstance: CreateFramePool's
-- proxy, which ignores the creation function, still makes real pins
-- because the mixin goes in through its postCreate
-- ===========================================================================

caughtErrors = {}
CreateUnsecuredRegionPoolInstance = nil
Boot()
WorldMapFrame:Show()
local _, proxyPool = M._Provider()
CHECK(proxyPool and getmetatable(proxyPool) ~= nil, "N: the pool is CreateFramePool's proxy")
local nPin = PinsWith(9004)[1]
CHECK(nPin and nPin._loaded and nPin.data and nPin.data.kind == "GIVER" and nPin.__level == 2018,
    "N: ...and its pins still carry the mixin, through postCreate")
Settle()
CHECK(WM.canvasErrors == 0 and #caughtErrors == 0, "N: Blizzard's every-pin pass finds nothing bare",
    caughtErrors[1])
CreateUnsecuredRegionPoolInstance = unsecuredPoolApi

-- ===========================================================================
-- O. Reputation (1.6.0): every quest on the map says what it is worth
--
-- The drawer's row tooltip and every quest in a giver pin's tooltip carry the
-- adapter's one line ("Reputation: +275 Honor Hold", "No reputation"), and
-- the maximized drawer's rows a badge ("+275 HH", "0": the figure and the
-- faction it is for) left of the state word.
-- Over Fake.RepWorld() (a level-70 Human, real quest ids and Questie's real
-- rows) with the REAL rules engine and generated data, loaded for this
-- section only; every section above ran without them, and the default world
-- shows no reputation at all (O0), so their counts are their own.
-- ===========================================================================

do
    -- O0. Without the rules there is no number: no badge, no line
    caughtErrors = {}
    Boot({ edit = MainWorld })
    WorldMapFrame:Show()
    local plainRow = QuestRow(9004)
    Hover(plainRow)
    CHECK(plainRow and not (plainRow.badge and plainRow.badge.__shown) and not TooltipHas("Reputation"),
        "O0: without the reputation rules, the drawer shows no badge and no reputation line")

    -- The reputation world, with the rules behind the adapter
    local function RepWorld(w)
        for key in pairs(w) do w[key] = nil end
        for key, value in pairs(Fake.RepWorld()) do w[key] = value end
    end
    caughtErrors = {}
    Boot({ edit = RepWorld })
    -- (the boot installs the fake client's reputation calls; what the module
    -- itself adds from here on is the data and the drawer, nothing else)
    local globalsBeforeRep = {}
    for key in pairs(_G) do globalsBeforeRep[key] = true end
    assert(loadfile(MODULE .. "/CommanderQuestLogReputationData.lua"))()
    assert(loadfile(MODULE .. "/CommanderQuestLogStanding.lua"))()
    A.Bump("rules")
    Settle()
    CHECK(A.RepLine(9355) == "+275 Honor Hold" and A.RepLine(91001) == "No reputation",
        "O: the rules are in: 250 Honor Hold is +275 to a Human", A.RepLine(9355))
    WM.mapID, WM.maximized = 1944, true
    WorldMapFrame:Show()
    local row = QuestRow(9355)
    CHECK(row and row.badge and row.badge.__shown and row.badge.__text == "+275 HH",
        "O1: the maximized drawer's row carries the badge, the faction named", row and row.badge and row.badge.__text)
    CHECK(QuestRow(91002) and QuestRow(91002).badge.__text == "+110 HH" and QuestRow(91001).badge.__text == "0",
        "O1: +110 HH for 91002 (its row for a faction with no standing slot dropped), 0 for a quest that pays nothing")
    local badgePoint = row and FindPoint(row.badge, "RIGHT")
    CHECK(badgePoint and badgePoint.rel == row and badgePoint.x == -(42 + 4), "O1: the badge sits left of the state word",
        badgePoint and badgePoint.x)
    CHECK(row and row.title.__w == (250 - 12 - 6) - 26 - (42 + 4) - (35 + 4),
        "O1: ...and the title gives up the badge's width", row and row.title.__w)
    local accentR, accentG, accentB = 0.55, 0.65, 0.80
    CHECK(row and SAME_COLOUR(row.badge.__textColor, accentR, accentG, accentB),
        "O1: a gain in the accent (steel without the window's kit)")
    CHECK(SAME_COLOUR(QuestRow(91001).badge.__textColor, 0.5, 0.5, 0.5), "O1: a 0 in the faint ink")
    Hover(row)
    CHECK(TooltipHas("Reputation: +275 Honor Hold"), "O2: the row's tooltip carries the line", AllTooltipText())
    Hover(QuestRow(91001))
    CHECK(TooltipHas("No reputation"), "O2: ...No reputation included")
    -- A giver's pin: every quest it holds, each with its line
    local pin = PinsWith(9355)[1]
    CHECK(pin and PinHas(pin, 91001) and PinHas(pin, 91002), "O3: Force Commander Danath's pin holds the three")
    if pin then Hover(pin) end
    CHECK(TooltipHas("Reputation: +275 Honor Hold") and TooltipHas("Reputation: +110 Honor Hold")
        and TooltipHas("No reputation"), "O3: the pin's tooltip says what each quest is worth", AllTooltipText())
    -- A waypoint from the drawer carries the note
    local before = #orders
    Click(row, "RightButton")
    CHECK(#orders == before + 1 and orders[#orders].spec.note == "+275 Honor Hold",
        "O4: a waypoint from the drawer is noted with the line", orders[#orders] and orders[#orders].spec.note)
    -- Windowed: no badge, the title its full width
    WM.maximized = false
    WorldMapFrame:SynchronizeDisplayState()
    row = QuestRow(9355)
    CHECK(row and not row.badge.__shown and row.title.__w == (220 - 12 - 6) - 26 - (42 + 4),
        "O5: the windowed drawer has no badge, and the title its full width", row and row.title.__w)
    Hover(row)
    CHECK(TooltipHas("Reputation: +275 Honor Hold"), "O5: ...the tooltip keeps the line")
    WM.maximized = true
    WorldMapFrame:SynchronizeDisplayState()
    -- The Wickerman: the drawer follows the multiplier
    world.player.auras[24705] = true
    A.Bump("aura")
    Settle()
    CHECK(QuestRow(9355).badge.__text == "+300 HH", "O6: under the Wickerman the badge reads +300 HH", QuestRow(9355).badge.__text)
    Hover(QuestRow(9355))
    CHECK(TooltipHas("Reputation: +300 Honor Hold"), "O6: ...and so does the tooltip")
    world.player.auras[24705] = nil
    A.Bump("aura")
    Settle()
    -- What was seen in game, and says so
    CommanderQuestLogChar.RepObserved = { [9355] = { [946] = { raw = 200, n = 1, delta = 220, pct = 110, kind = "DIRECT" } } }
    A.Bump("calibration")
    Settle()
    Hover(QuestRow(9355))
    CHECK(QuestRow(9355).badge.__text == "+220 HH" and TooltipHas("Reputation: +220 Honor Hold (seen in game)"),
        "O7: a sample seen in game replaces the data on the map, marked as seen", AllTooltipText())
    CommanderQuestLogChar.RepObserved = nil
    A.Bump("calibration")
    Settle()
    -- The switches
    SetSetting("ShowRepEverywhere", false)
    row = QuestRow(9355)
    Hover(row)
    CHECK(row and not row.badge.__shown and not TooltipHas("Reputation"), "O8: Reputation on Every Quest off: no badge, no line")
    if pin then
        Hover(PinsWith(9355)[1])
        CHECK(not TooltipHas("Reputation") and not TooltipHas("No reputation"), "O8: ...nor on a pin")
    end
    SetSetting("ShowRepEverywhere", nil)
    SetSetting("ZoneRowRep", false)
    row = QuestRow(9355)
    Hover(row)
    CHECK(row and not row.badge.__shown and TooltipHas("Reputation: +275 Honor Hold"),
        "O8: Reputation on Zone Rows off takes the badge and leaves the line")
    SetSetting("ZoneRowRep", nil)
    -- A header or a zone row reuses the pool: no badge left behind
    WorldMapFrame:SetMapID(1945)
    Settle()
    local stale = 0
    for _, shown in ipairs(ShownRows()) do
        if shown.item.kind ~= "QUEST" and shown.badge and shown.badge.__shown then stale = stale + 1 end
    end
    CHECK(#ShownRows() > 0 and stale == 0, "O9: a continent's zone rows carry no badge left over from a quest row", stale)
    -- O10. The badge names its faction, so a zone that pays several tells
    -- them apart: a quest whose best gain is ANOTHER faction's never reads
    -- like one for the faction beside it (the brief's Hellfire surprise)
    WorldMapFrame:SetMapID(1955)
    Settle()
    CHECK(QuestRow(10325) and QuestRow(10325).badge.__text == "+275 Aldor"
        and QuestRow(10886) and QuestRow(10886).badge.__text == "+550 Sha'tar",
        "O10: Shattrath: the Aldor's quest and the Sha'tar's each name their faction",
        (QuestRow(10325) and QuestRow(10325).badge.__text or "-") .. " / " .. (QuestRow(10886) and QuestRow(10886).badge.__text or "-"))
    WorldMapFrame:SetMapID(1944)
    Settle()
    Click(HeaderRow("Done"))
    CHECK(QuestRow(10937) and QuestRow(10937).badge.__text == "+1,100 HH" and QuestRow(10937).badge.__w == 45,
        "O10: +1,100 HH fits the badge's 64 px whole", QuestRow(10937) and QuestRow(10937).badge.__w)
    Click(HeaderRow("Done"))
    -- Hygiene
    local leakedRep = {}
    for key in pairs(_G) do
        local name = tostring(key)
        if not globalsBeforeRep[key] and name ~= "CommanderQuestLogMapDrawer" and name ~= "CommanderQuestLogReputationData" then
            leakedRep[#leakedRep + 1] = name
        end
    end
    CHECK(#leakedRep == 0, "O: no global but the drawer's and the data's", table.concat(leakedRep, ","))
    CHECK(#WM.writes == 0, "O: never assigned a field on WorldMapFrame", table.concat(WM.writes, ","))
    local glyphs = {}
    for _, text in ipairs(textLog) do if not GlyphFree(text) then glyphs[#glyphs + 1] = text end end
    for _, text in ipairs(tooltipLines) do if not GlyphFree(text) then glyphs[#glyphs + 1] = text end end
    CHECK(#glyphs == 0, "O: no shape glyph in any drawn string", glyphs[1])
    CHECK(#caughtErrors == 0 and M._State().lastError == nil and A._LastError() == nil, "O: no errors",
        caughtErrors[1] or M._State().lastError or A._LastError())
    Fake.UninstallRepClient()
    Q.Standing, CommanderQuestLogReputationData = nil, nil
end

-- ===========================================================================

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
