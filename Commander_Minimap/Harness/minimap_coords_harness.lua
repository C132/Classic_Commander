-- Commander_Minimap: the coordinate label and the Ctrl+Right-click wrapper
-- (Commander Orders 3.1), headless (luajit).
--
--     /opt/homebrew/bin/luajit minimap_coords_harness.lua
--
-- Loads the real CommanderMinimap.lua into a sandbox of its own (frames are
-- recording stubs; nothing of the client but what the file reads) and drives
-- it with a STAND-IN for Commander Orders' CommanderOrders.Coords surface,
-- so this answers for Commander_Minimap's half alone: what it shows, when it
-- asks, what it hands over, and that the minimap clicks exactly as before
-- whenever Orders is absent, off, or does not want the click. Orders' own
-- half (the numbers, the placement, the menu) is proven against the real
-- Commander_Minimap in Commander_Orders/Harness/orders_coords_harness.lua
-- (sections G and H).

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
local ADDON = HERE:gsub("/Harness$", "")
if ADDON == HERE then ADDON = HERE .. "/.." end
local MINIMAP_FILE = os.getenv("MINIMAP_FILE") or (ADDON .. "/CommanderMinimap.lua")

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail ~= nil and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end
local function EQ(got, want, label)
    CHECK(got == want, label, "got " .. tostring(got) .. ", want " .. tostring(want))
end

-- ---------------------------------------------------------------------------
-- The sandbox
-- ---------------------------------------------------------------------------
local function Sandbox()
    local W = { frames = {}, pings = 0, mods = {}, writes = {}, errors = {}, tooltipHidden = 0 }
    local Widget
    local function New(kind, name, parent)
        local w = setmetatable({ __kind = kind, __name = name, __parent = parent, __scripts = {}, __shown = true,
                                 __points = {}, __children = {}, __events = {} }, Widget)
        if parent and parent.__children then parent.__children[#parent.__children + 1] = w end
        W.frames[#W.frames + 1] = w
        return w
    end
    local methods = {
        SetPoint = function(s, point, rel, relPoint, x, y)
            s.__points[#s.__points + 1] = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
        end,
        SetScript = function(s, name, fn) s.__scripts[name] = fn end,
        GetScript = function(s, name) return s.__scripts[name] end,
        HookScript = function(s, name, fn)
            local old = s.__scripts[name]
            s.__scripts[name] = old and function(...) old(...) fn(...) end or fn
        end,
        Show = function(s) s.__shown = true end,
        Hide = function(s) s.__shown = false end,
        IsShown = function(s) return s.__shown end,
        SetText = function(s, text) s.__text = text; s.__sets = (s.__sets or 0) + 1 end,
        GetText = function(s) return s.__text end,
        SetFontObject = function(s, f) s.__font = f end,
        SetFrameLevel = function(s, l) s.__level = l end,
        GetFrameLevel = function(s) return s.__level or 2 end,
        EnableMouse = function(s, on) s.__mouse = on end,
        RegisterForClicks = function(s, ...) s.__clicks = { ... } end,
        RegisterEvent = function(s, e) s.__events[e] = true end,
        GetName = function(s) return s.__name end,
        CreateFontString = function(s, name) return New("FontString", name, s) end,
        GetChildren = function(s) return unpack(s.__children) end,
        SetMaskTexture = function(s, path) s.__mask = path end,
    }
    Widget = { __index = function(_, key)
        if methods[key] then return methods[key] end
        if type(key) ~= "string" or key:sub(1, 2) == "__" then return nil end
        return function() end
    end }
    local minimap = New("Minimap", "Minimap", nil)
    -- Blizzard's Minimap_OnClick: a ping for ANY button (Classic/Minimap.lua:130-141)
    minimap.__scripts.OnMouseUp = function() W.pings = W.pings + 1 end
    W.minimap = minimap
    local env = {
        CreateFrame = function(kind, name, parent) return New(kind, name, parent) end,
        Minimap = minimap,
        MinimapCluster = { BorderTop = New("Frame") },
        MinimapZoomOut = New("Button"), MinimapZoomIn = New("Button"), MinimapToggleButton = New("Button"),
        MinimapNorthTag = New("Frame"), MinimapBorder = New("Frame"), GameTimeFrame = New("Button"),
        MinimapZoneTextButton = New("Button"),
        GameFontNormal = { name = "GameFontNormal" }, GameFontHighlightSmall = { name = "GameFontHighlightSmall" },
        GetMinimapZoneText = function() return "Goldshire" end,
        Commander = { AddListener = function() end, UI = { ApplyStyleBackdrop = function() end } },
        COMMANDER_MINIMAP_EVENTS = { COMMANDER_MINIMAP = "COMMANDER_MINIMAP" },
        CommanderMinimapDB = { BoardStyle = "NONE", TidyAddonButtons = false, MinimapScale = 1.37 },
        C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end },
        IsControlKeyDown = function() return W.mods.CTRL end,
        IsShiftKeyDown = function() return W.mods.SHIFT end,
        IsAltKeyDown = function() return W.mods.ALT end,
        GameTooltip = { GetOwner = function(self) return self.owner end, Hide = function() W.tooltipHidden = W.tooltipHidden + 1 end },
        type = type, pairs = pairs, ipairs = ipairs, pcall = pcall, math = math, string = string, table = table,
        tostring = tostring, select = select, unpack = unpack, print = function() end,
    }
    setmetatable(env, { __newindex = function(t, k, v)
        W.writes[#W.writes + 1] = k
        rawset(t, k, v)
    end })
    local chunk = assert(loadfile(MINIMAP_FILE))
    setfenv(chunk, env)
    chunk()
    W.env = env
    -- the parts this harness looks at
    for _, f in ipairs(minimap.__children) do
        local pt = f.__points[1]
        if f.__kind == "FontString" and pt and pt.rel == minimap then W.zoneText = f end
    end
    for _, f in ipairs(minimap.__children) do
        local pt = f.__points[1]
        if f.__kind == "FontString" and pt and pt.rel == W.zoneText then W.label = f end
    end
    for _, f in ipairs(minimap.__children) do
        local pt = f.__points[1]
        if f.__kind == "Button" and pt and pt.rel == W.label then W.hit = f end
        if f.__kind == "Frame" and f.__scripts.OnUpdate and #f.__points == 0 then W.driver = f end
    end
    function W.Tick(seconds, step)
        step = step or 0.05
        local t = 0
        while t < seconds - 1e-9 do
            if W.driver.__shown and W.minimap.__shown then W.driver.__scripts.OnUpdate(W.driver, step) end
            t = t + step
        end
    end
    function W.Up(button, mods)
        W.mods = mods or {}
        minimap.__scripts.OnMouseUp(minimap, button)
        W.mods = {}
    end
    return W
end

-- A stand-in for CommanderOrders.Coords: records every call
local function Orders(W, opts)
    opts = opts or {}
    local calls = { text = 0, wants = 0, click = {}, gesture = {}, tooltip = {} }
    local coords = {
        MinimapText = function()
            calls.text = calls.text + 1
            if opts.textError then error("text boom") end
            return opts.text
        end,
        WantsMinimapClick = function()
            calls.wants = calls.wants + 1
            if opts.wantsError then error("wants boom") end
            return opts.wants
        end,
        MinimapClick = function(minimap)
            calls.click[#calls.click + 1] = minimap
            if opts.clickError then error("click boom") end
            return 1
        end,
        Gesture = function(button, o) calls.gesture[#calls.gesture + 1] = { button = button, opts = o } end,
        Tooltip = function(owner, o) calls.tooltip[#calls.tooltip + 1] = { owner = owner, opts = o } end,
    }
    rawset(W.env, "CommanderOrders", { Coords = coords })
    return calls, opts
end

-- ===========================================================================
-- Loading
-- ===========================================================================
local W = Sandbox()
CHECK(W.label ~= nil, "load: a coordinate label under the zone name")
EQ(W.label and W.label.__points[1].relPoint, "BOTTOM", "load: anchored to the zone name's bottom")
EQ(W.label and W.label.__font, W.env.GameFontHighlightSmall, "load: GameFontHighlightSmall")
EQ(W.label and W.label.__shown, false, "load: hidden until Orders says what to show")
CHECK(W.hit ~= nil, "load: a click surface over the label")
EQ(W.hit and #W.hit.__points, 2, "load: anchored to the label's two corners only (the rest of the edge keeps its pings)")
EQ(W.hit and W.hit.__shown, false, "load: hidden with the label")
EQ(W.hit and W.hit.__name, nil, "load: unnamed (the tidy collects by name)")
EQ(W.hit and W.hit.__level, 4, "load: two levels over the Minimap")
EQ(W.hit and table.concat(W.hit.__clicks or {}, ","), "LeftButtonUp,RightButtonUp", "load: left and right clicks")
CHECK(W.driver ~= nil and W.driver.__parent == W.minimap and W.driver.__name == nil,
    "load: an unnamed driver on the Minimap (a hidden minimap costs nothing)")
EQ(#W.writes, 0, "load: no global written by loading the file", table.concat(W.writes, " "))
CHECK(W.minimap.__scripts.OnMouseUp ~= nil, "load: the Minimap's OnMouseUp is wrapped")

-- ===========================================================================
-- Without Commander Orders: nothing shown, every click pings as before
-- ===========================================================================
W.Tick(1)
EQ(W.label.__shown, false, "no Orders: no label")
W.Up("RightButton", { CTRL = true })
EQ(W.pings, 1, "no Orders: Ctrl+Right-click pings, as before")
W.Up("RightButton")
W.Up("LeftButton")
EQ(W.pings, 3, "no Orders: every click pings")
W.hit.__scripts.OnClick(W.hit, "LeftButton")
W.hit.__scripts.OnEnter(W.hit)
CHECK(true, "no Orders: the label's surface does nothing, raises nothing")

-- ===========================================================================
-- With Orders: the label
-- ===========================================================================
local calls, opts = Orders(W, { text = "42.0, 65.5", wants = true })
W.Tick(0.25)
EQ(W.label.__text, "42.0, 65.5", "label: Orders' text")
EQ(W.label.__shown, true, "label: shown")
EQ(W.hit.__shown, true, "label: its surface with it")
local asks = calls.text
W.Tick(1)
CHECK(calls.text - asks >= 4 and calls.text - asks <= 6, "label: asked five times a second", calls.text - asks)
local sets = W.label.__sets
W.Tick(1)
EQ(W.label.__sets, sets, "label: the same text is not written again")
opts.text = "43.1, 65.5"
W.Tick(0.25)
EQ(W.label.__text, "43.1, 65.5", "label: follows")
EQ(W.label.__sets, sets + 1, "label: one write for one change")
W.minimap.__shown = false
asks = calls.text
W.Tick(1)
EQ(calls.text, asks, "label: minimap hidden: not asked")
W.minimap.__shown = true
opts.text = nil
W.Tick(0.25)
EQ(W.label.__shown, false, "label: Orders says nil (setting off, Orders off): hidden")
EQ(W.hit.__shown, false, "label: ...and its surface")
opts.text = "--"
W.Tick(0.25)
EQ(W.label.__text, "--", "label: back, whatever Orders says (\"--\")")
EQ(W.label.__shown, true, "label: shown again")
opts.textError = true
W.Tick(0.25)
EQ(W.label.__shown, false, "label: an Orders error hides it, raises nothing")
opts.textError = nil

-- ===========================================================================
-- With Orders: the label's clicks and hover go to Orders' gestures
-- ===========================================================================
W.hit.__scripts.OnClick(W.hit, "LeftButton")
W.hit.__scripts.OnClick(W.hit, "RightButton")
EQ(#calls.gesture, 2, "surface: both clicks go to Orders")
EQ(calls.gesture[1] and calls.gesture[1].button, "LeftButton", "surface: the button handed over")
EQ(calls.gesture[2] and calls.gesture[2].opts.surface, "minimap", "surface: as the minimap's surface")
W.hit.__scripts.OnEnter(W.hit)
EQ(calls.tooltip[1] and calls.tooltip[1].owner, W.hit, "surface: hover: Orders' card, owned by the surface")
W.env.GameTooltip.owner = W.hit
W.hit.__scripts.OnLeave(W.hit)
EQ(W.tooltipHidden, 1, "surface: leaving hides the card it owns")
W.env.GameTooltip.owner = nil
W.hit.__scripts.OnLeave(W.hit)
EQ(W.tooltipHidden, 1, "surface: ...and nobody else's")
EQ(W.pings, 3, "surface: the label's clicks never ping")

-- ===========================================================================
-- With Orders: Ctrl+Right-click on the map
-- ===========================================================================
W.Up("RightButton", { CTRL = true })
EQ(#calls.click, 1, "click: Ctrl+Right-click goes to Orders")
EQ(calls.click[1], W.minimap, "click: with the Minimap")
EQ(W.pings, 3, "click: and NO ping (Minimap_OnClick skipped)")
W.Up("RightButton")
EQ(W.pings, 4, "click: a plain right-click still pings")
W.Up("LeftButton", { CTRL = true })
EQ(W.pings, 5, "click: Ctrl+Left pings (only Ctrl+Right is Orders')")
W.Up("RightButton", { CTRL = true, SHIFT = true })
EQ(W.pings, 6, "click: Ctrl+Shift+Right pings (Ctrl alone)")
W.Up("RightButton", { CTRL = true, ALT = true })
EQ(W.pings, 7, "click: Ctrl+Alt+Right pings")
EQ(#calls.click, 1, "click: none of those reached Orders")
opts.wants = false
W.Up("RightButton", { CTRL = true })
EQ(W.pings, 8, "click: Orders does not want it (setting off, Orders off): it pings")
EQ(#calls.click, 1, "click: ...and Orders is not asked to place anything")
opts.wants = true
opts.wantsError = true
W.Up("RightButton", { CTRL = true })
EQ(W.pings, 9, "click: Orders erring on the question: the ping, as if absent")
opts.wantsError = nil
opts.clickError = true
W.Up("RightButton", { CTRL = true })
EQ(W.pings, 9, "click: Orders erring on the placement: still no ping (the click was its)")
opts.clickError = nil
-- a handler another addon put there first is the one kept
local W2 = Sandbox()
EQ(W2.pings, 0, "kept: (a fresh sandbox)")
W2.Up("RightButton", { CTRL = true })
EQ(W2.pings, 1, "kept: the earlier handler runs for the clicks Orders does not take")

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
