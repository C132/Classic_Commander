-- Commander Gladiator UI smoke (luajit)
--
--     luajit Commander_Gladiator/Harness/gladiator_ui_smoke.lua
--
-- The engine smoke next door covers the rules with no client attached. This
-- one covers the half the rules cannot reach: what the window does with a
-- match. It loads the module's files in .toc order over a small WoW mock,
-- opens the window the way a player would (the slash command), drives whole
-- matches through the real OnUpdate with fake frames, and asserts on what
-- got painted -- the texture on a token's face, the cooldown a health ring
-- was handed, the point a shadow was anchored to -- rather than on what the
-- window believes about itself.
--
-- Sections:
--   A  login: both events run clean, defaults fill round what was saved, the
--      slash command exists, nothing is on screen -- and the twelve matches
--      a fresh install would be dealt first are a fair opening
--   B  open: the window where a window never dragged opens, movable in fact
--      and not only in script; a match held at its gates, six tokens dressed
--      and placed, only the enemy's taking the mouse; the bar of three
--      buttons under the floor, the hint either side of it, the countdown
--      over the back row -- and then EVERY place on the engine's floor, not
--      just the six starting marks: on the floor, in the window, under the
--      header, clear of the pillars and of the bar
--   C  a whole match through the real OnUpdate: the gates hold it for their
--      two seconds; then, with one enormous frame in it, no error, tokens
--      glide between ticks, the step cap holds, the banner says the right
--      word in the right colour on its band, the record moves by one, and
--      the next match is dealt from the next seed and held at its gates
--   D  what is painted, forced through the engine's own doors, in five
--      parts. States: the sheep's face and its return, the ring at a real
--      fraction and at two uptimes, the shield rim, the glow, frost, the
--      stun pin, cyclone, fear, the kill marks, the dead, a teleport -- then
--      a clean slate at the next deal, a deal of six DIFFERENT units to
--      prove a token and a button are whatever they are handed, and one of a
--      class the client has no badge for. What flies: how each of the
--      eighteen rows is delivered, and one of each in the air -- a
--      projectile along its line, a bump toward its target, a call-out above
--      its token, numbers in their lanes rising and fading under the spell's
--      name, a fourth number stacked and not overwritten, the nova's ring
--      out to its range, a Charge run and not jumped. A forced draw. The
--      hand: the pointer's ring, a pin made, moved and let go by clicks at
--      the gates, a click that your own token standing on an enemy does not
--      eat, each button glowing, sweeping, dim and greyed and what a click
--      on each does, the tooltips, the hint through its two verbs, a pinned
--      sheep still wearing its pin, a dead token no longer clickable, and a
--      pin at the gates being the opening. And the header's healing line
--      through dampening and a rout.
--   E  pooling: two more matches create no widget at all, one of them with
--      a hand on it, and the banner has its three seconds at 2x. And the
--      audit that ran after every frame of every match played out up to
--      here: every ring showed its unit's health, nobody left the floor, the
--      healing line said what the match was doing, every button said what
--      its spell was doing, only living enemies took the mouse, the gold
--      disc was on the pin, and every kind of number was seen at least once,
--      by colour and by size
--   F  hidden means paused -- a match, a button's sweep, and the wait at the
--      gates -- and switched off means closed
--   G  depth: nearer the front is larger and drawn over, frame levels are
--      only touched when the order changes and follow a raised window; and
--      personal space -- two tokens on one spot are drawn apart, in a
--      corner and three in a row as well
--   H  speed: 2x is twice the match in the same frames and half the gates,
--      from the header button and from the settings page alike; a hitch at
--      the gates is capped; and Restore Defaults reaches the header and
--      brings the hint back
--   I  the .toc and the art: every listed file exists, every Lua file is
--      listed, every copied texture is referenced and every referenced one
--      was copied
--   J  each shipping file compiles, stays far below the 200-local ceiling,
--      and reads no global this smoke has not been told about
--   K  field proof: every widget method, client global and framework
--      function the module reached for is one some OTHER shipped Commander
--      module already uses. Anything that is not is printed, and is the
--      list of calls nobody has seen work in the game.
--   L  a second session: built again, the window opens where the first one
--      was dropped
--   M  a good player through real clicks: two hundred seeds played on the
--      second session's window by a script that looks only at widgets and
--      clicks only at points, held to the same policy played straight on
--      the engine, seed for seed
--
-- THE MOCK IS STRICT WHERE THE CLIENT IS. A method a real widget of that
-- kind does not have is nil here too, so an unguarded call to one is the
-- same "attempt to call a nil value" it would be in the game: SetScript on a
-- Texture, SetTexture on a Frame, a misspelt anything. A FontString with no
-- font refuses SetText; SetFont refuses flags it does not know; a template
-- or a draw layer that does not exist is an error; a cooldown started before
-- zero is an error; a NaN in a SetPoint is an error. And a hidden frame's
-- OnUpdate does not run, which is the whole of section F.
--
-- THE MOCK HAS A MOUSE. A click is made at a point of the window, not on a
-- widget: it goes to the frame the client would give it to -- shown, taking
-- the mouse, under the pointer, and the highest of those by frame level --
-- and runs that frame's OnClick if it is a Button with one. So "a dead token
-- does not take the click" and "the rogue standing on the pinned enemy does
-- not eat it" are things a check can see fail. The pointer stays where it
-- was put while the frames under it move, so OnEnter and OnLeave are worked
-- out again after every frame, and a HIGHLIGHT texture counts as drawn only
-- while the pointer is over the frame that owns it.
--
-- THE LAST LINE IS ALWAYS THE COUNT. A widget the window never painted is a
-- failed check, not an error: the readers the checks go through answer for
-- it with not-a-number (see NEVER), every section runs under a guard that
-- turns an error of the smoke's own into one failed check (see Section),
-- and "N checks, M failures" is printed whatever a check or a section did.
-- The one exception is a shipping file that will not compile or errors
-- while loading: nothing below it could mean anything, so the smoke stops
-- there with the file's name and the error.

local ADDONS = "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local HERE = ADDONS .. "/Commander_Gladiator"
local LUAJIT = "/opt/homebrew/bin/luajit"

-- Interpreted, as the engine smoke is and for its reasons: the client has no
-- JIT, and the engine's branchy loops run faster without one here.
if jit then jit.off() end

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end
local function EQ(got, want, label)
    CHECK(got == want, label, string.format("got %s want %s", tostring(got), tostring(want)))
end
local function NEAR(got, want, label, tol)
    CHECK(type(got) == "number" and math.abs(got - want) <= (tol or 0.001), label,
          string.format("got %s want %s", tostring(got), tostring(want)))
end

-- Every section below is run through here, so that the last line of a run
-- is always the count. This smoke reads fields straight off the mock's
-- widgets, and a field the window never wrote is a nil the next line
-- indexes: an error of the SMOKE's own, not the module's, which used to end
-- the run on a stack trace with no count under it. The readers above
-- section B (Colour, Foot and the rest) answer for a widget that was never
-- painted without raising anything; this is for whatever they do not
-- cover. A section that stops is one failed check with the error as its
-- detail, and the sections after it still run.
local function Section(name, body)
    local ok, err = pcall(body)
    if not ok then CHECK(false, name .. ": the smoke stopped on an error of its own", err) end
end

-- ===========================================================================
-- The mock
-- ===========================================================================
-- GetTime counts from the machine's boot, and a Mac that sleeps rather than
-- shuts down has been up for days. So the mock has too: past a day, a health
-- ring's frozen cooldown is exactly a day long, and that is the branch the
-- game will really run. (Section D hands one ring a young uptime by hand,
-- for the other branch.)
local now = 200000
function GetTime() return now end

local eventRegistry, caughtErrors = {}, {}
local allFrames = {}
local created = 0          -- every widget ever made: frames, textures, font strings
local levelSets = 0        -- every SetFrameLevel call
local called = {}          -- every method name the module reached for on a widget

local ANCHORS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
    RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
local LAYERS = { BACKGROUND = true, BORDER = true, ARTWORK = true, OVERLAY = true, HIGHLIGHT = true }
local STRATA = { BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true }
local BLENDS = { ADD = true, BLEND = true, DISABLE = true, ALPHAKEY = true, MOD = true }
local FONT_FLAGS = { [""] = true, OUTLINE = true, THICKOUTLINE = true, MONOCHROME = true }
local FONT_OBJECTS = {
    GameFontNormal = true, GameFontNormalSmall = true, GameFontNormalLarge = true,
    GameFontHighlight = true, GameFontHighlightSmall = true,
}
local SCRIPTS = {
    OnUpdate = true, OnShow = true, OnHide = true, OnEvent = true, OnDragStart = true,
    OnDragStop = true, OnClick = true, OnEnter = true, OnLeave = true,
}
-- What CreateFrame may be asked for, and the frame type each template is for
local FRAME_KINDS = { FRAME = "Frame", BUTTON = "Button", COOLDOWN = "Cooldown" }
local TEMPLATES = {
    CooldownFrameTemplate = "Cooldown", UIPanelCloseButton = "Button", UIPanelButtonTemplate = "Button",
}

local function Number(value, what)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
        error(what .. " must be a finite number, got " .. tostring(value), 3)
    end
    return value
end

local function Visible(widget)
    while widget do
        if not widget.__shown then return false end
        widget = widget.__parent
    end
    return true
end

local NewWidget
local impl = {}

function impl.SetPoint(s, point, a, b, c, d)
    if not ANCHORS[point] then error("SetPoint: bad point " .. tostring(point), 2) end
    local rel, relPoint, x, y
    if a == nil or type(a) == "number" then
        rel, relPoint, x, y = s.__parent, point, a or 0, b or 0
    else
        if type(a) ~= "table" then error("SetPoint: bad relative frame", 2) end
        rel, relPoint, x, y = a, b or point, c or 0, d or 0
    end
    if not ANCHORS[relPoint] then error("SetPoint: bad relative point " .. tostring(relPoint), 2) end
    s.__points = s.__points or {}
    s.__point = { point = point, rel = rel, relPoint = relPoint, x = Number(x, "SetPoint x"), y = Number(y, "SetPoint y") }
    s.__points[point] = s.__point
end
function impl.ClearAllPoints(s) s.__points, s.__point = {}, nil end
function impl.SetAllPoints(s, rel) s.__allPoints = rel or s.__parent end
function impl.GetPoint(s)
    local p = s.__point
    if not p then return nil end
    return p.point, p.rel, p.relPoint, p.x, p.y
end
function impl.SetSize(s, w, h) s.__w, s.__h = Number(w, "SetSize width"), Number(h, "SetSize height") end
function impl.SetWidth(s, w) s.__w = Number(w, "SetWidth") end
function impl.SetHeight(s, h) s.__h = Number(h, "SetHeight") end
function impl.GetWidth(s) return s.__w or 0 end
function impl.GetHeight(s) return s.__h or 0 end
function impl.Show(s)
    if s.__shown then return end
    s.__shown = true
    local handler = s.__scripts and s.__scripts.OnShow
    if handler and Visible(s) then handler(s) end
end
function impl.Hide(s)
    if not s.__shown then return end
    s.__shown = false
    local handler = s.__scripts and s.__scripts.OnHide
    if handler then handler(s) end
end
function impl.SetShown(s, shown) if shown then s:Show() else s:Hide() end end
function impl.IsShown(s) return s.__shown end
function impl.IsVisible(s) return Visible(s) end
function impl.SetAlpha(s, alpha)
    Number(alpha, "SetAlpha")
    if alpha < 0 or alpha > 1 then error("SetAlpha out of range: " .. alpha, 2) end
    s.__alpha = alpha
end
function impl.GetAlpha(s) return s.__alpha or 1 end
function impl.GetParent(s) return s.__parent end

function impl.SetScale(s, scale)
    if Number(scale, "SetScale") <= 0 then error("SetScale must be above zero", 2) end
    s.__scale = scale
end
function impl.GetScale(s) return s.__scale or 1 end
function impl.SetFrameLevel(s, level)
    if Number(level, "SetFrameLevel") < 0 or level ~= math.floor(level) then
        error("SetFrameLevel: bad level " .. level, 2)
    end
    s.__level = level
    levelSets = levelSets + 1
end
function impl.GetFrameLevel(s) return s.__level end
function impl.SetFrameStrata(s, strata)
    if not STRATA[strata] then error("SetFrameStrata: bad strata " .. tostring(strata), 2) end
    s.__strata = strata
end
function impl.SetToplevel(s, v) s.__toplevel = v end
function impl.SetMovable(s, v) s.__movable = v end
function impl.SetClampedToScreen(s, v) s.__clamped = v end
function impl.EnableMouse(s, v) s.__mouse = v end
function impl.RegisterForDrag(s, button) s.__drag = button end
function impl.StartMoving(s) s.__moving = true end
function impl.StopMovingOrSizing(s) s.__moving = false end
function impl.SetScript(s, name, handler)
    if not SCRIPTS[name] then error("SetScript: no such script " .. tostring(name), 2) end
    s.__scripts[name] = handler
end
function impl.GetScript(s, name) return s.__scripts[name] end
-- Chained, not replaced: that is what the client does
function impl.HookScript(s, name, handler)
    if not SCRIPTS[name] then error("HookScript: no such script " .. tostring(name), 2) end
    local old = s.__scripts[name]
    s.__scripts[name] = old and function(...) old(...) handler(...) end or handler
end
function impl.RegisterEvent(s, event)
    eventRegistry[event] = eventRegistry[event] or {}
    table.insert(eventRegistry[event], s)
end
function impl.UnregisterEvent(s, event)
    local list = eventRegistry[event] or {}
    for i = #list, 1, -1 do if list[i] == s then table.remove(list, i) end end
end
function impl.CreateTexture(s, _, layer, _, sublevel)
    if layer and not LAYERS[layer] then error("CreateTexture: bad layer " .. tostring(layer), 2) end
    if sublevel and (sublevel < -8 or sublevel > 7) then error("CreateTexture: bad sublevel", 2) end
    local t = NewWidget("Texture", s)
    t.__layer, t.__sublevel = layer or "ARTWORK", sublevel or 0
    return t
end
function impl.CreateFontString(s, _, layer, template)
    if layer and not LAYERS[layer] then error("CreateFontString: bad layer " .. tostring(layer), 2) end
    if template and not FONT_OBJECTS[template] then error("CreateFontString: no font object " .. tostring(template), 2) end
    local t = NewWidget("FontString", s)
    t.__font = template
    return t
end

function impl.SetCooldown(s, start, duration)
    Number(start, "SetCooldown start"); Number(duration, "SetCooldown duration")
    if start < 0 then error("SetCooldown: a start before zero", 2) end
    if duration <= 0 then error("SetCooldown: no duration", 2) end
    s.__cd = { start = start, duration = duration }
end
function impl.SetSwipeTexture(s, texture) s.__swipeTexture = texture end
function impl.SetSwipeColor(s, r, g, b, a) s.__swipe = { r, g, b, a } end
function impl.SetReverse(s, v) s.__reverse = v end
function impl.SetDrawEdge() end
function impl.SetDrawSwipe() end
function impl.SetDrawBling() end
function impl.SetHideCountdownNumbers() end

function impl.SetTexture(s, texture)
    if texture ~= nil and type(texture) ~= "string" then error("SetTexture: not a path", 2) end
    s.__texture, s.__colorTexture = texture, nil
end
function impl.GetTexture(s) return s.__texture end
function impl.SetColorTexture(s, r, g, b, a)
    s.__colorTexture = { Number(r, "r"), Number(g, "g"), Number(b, "b"), a }
end
function impl.SetTexCoord(s, l, r, t, b)
    s.__coords = { Number(l, "coord"), Number(r, "coord"), Number(t, "coord"), Number(b, "coord") }
end
function impl.SetVertexColor(s, r, g, b, a)
    s.__color = { Number(r, "r"), Number(g, "g"), Number(b, "b"), a }
end
function impl.SetDesaturated(s, v) s.__desat = not not v end
function impl.SetBlendMode(s, mode)
    if not BLENDS[mode] then error("SetBlendMode: bad mode " .. tostring(mode), 2) end
    s.__blend = mode
end

function impl.SetFont(s, font, size, flags)
    if type(font) ~= "string" then error("SetFont: no font path", 2) end
    Number(size, "SetFont size")
    if flags ~= nil and not FONT_FLAGS[flags] then error("SetFont: bad flags " .. tostring(flags), 2) end
    s.__font, s.__fontSize = font, size
end
function impl.SetText(s, text)
    if s.__kind == "FontString" and not s.__font then error("FontString:SetText(): Font not set", 2) end
    if text ~= nil and type(text) ~= "string" and type(text) ~= "number" then
        error("SetText: not text: " .. tostring(text), 2)
    end
    s.__text = text and tostring(text)
    s.__texts = (s.__texts or 0) + 1
end
function impl.GetText(s) return s.__text end
function impl.SetJustifyH(s, side)
    if side ~= "LEFT" and side ~= "CENTER" and side ~= "RIGHT" then error("SetJustifyH: bad side " .. tostring(side), 2) end
    s.__justify = side
end
function impl.SetTextColor(s, r, g, b, a)
    s.__color = { Number(r, "r"), Number(g, "g"), Number(b, "b"), a }
end

-- Which kind of widget owns which methods. Built from lists so the sets
-- nest the way the client's widget types do.
local function Set(...)
    local set = {}
    for _, list in ipairs({ ... }) do
        for _, name in ipairs(list) do set[name] = true end
    end
    return set
end
local REGION = {
    "SetPoint", "ClearAllPoints", "SetAllPoints", "GetPoint", "SetSize", "SetWidth", "SetHeight",
    "GetWidth", "GetHeight", "Show", "Hide", "SetShown", "IsShown", "IsVisible", "SetAlpha",
    "GetAlpha", "GetParent",
}
local FRAME = {
    "SetScale", "GetScale", "SetFrameLevel", "GetFrameLevel", "SetFrameStrata", "SetToplevel",
    "SetMovable", "SetClampedToScreen", "EnableMouse", "RegisterForDrag", "StartMoving",
    "StopMovingOrSizing", "SetScript", "GetScript", "HookScript", "RegisterEvent",
    "UnregisterEvent", "CreateTexture", "CreateFontString",
}
local OWNS = {
    Frame = Set(REGION, FRAME),
    Button = Set(REGION, FRAME, { "SetText", "GetText" }),
    Cooldown = Set(REGION, FRAME, {
        "SetCooldown", "SetSwipeTexture", "SetSwipeColor", "SetReverse", "SetDrawEdge",
        "SetDrawSwipe", "SetDrawBling", "SetHideCountdownNumbers",
    }),
    Texture = Set(REGION, {
        "SetTexture", "GetTexture", "SetColorTexture", "SetTexCoord", "SetVertexColor",
        "SetDesaturated", "SetBlendMode",
    }),
    FontString = Set(REGION, { "SetText", "GetText", "SetFont", "SetTextColor", "SetJustifyH" }),
}

-- The smoke itself never calls a widget method -- it reads the recorded
-- fields -- so everything that lands in `called` was the module's doing.
local WidgetMT = {}
WidgetMT.__index = function(self, key)
    if OWNS[rawget(self, "__kind")][key] then
        called[key] = true
        return impl[key]
    end
    return nil
end

-- A Button takes the mouse from the moment it is made; nothing else does
-- until it is told to.
NewWidget = function(kind, parent)
    created = created + 1
    return setmetatable({
        __kind = kind, __parent = parent, __shown = true, __mouse = kind == "Button",
        __scripts = kind ~= "Texture" and kind ~= "FontString" and {} or nil,
    }, WidgetMT)
end

function CreateFrame(frameType, name, parent, template)
    local kind = FRAME_KINDS[tostring(frameType):upper()]
    if not kind then error("CreateFrame: no frame type " .. tostring(frameType), 2) end
    if template and TEMPLATES[template] ~= kind then
        error("CreateFrame: " .. tostring(template) .. " is not a " .. kind .. " template", 2)
    end
    local f = NewWidget(kind, parent)
    f.__name, f.__template = name, template
    -- The one template here that comes with a size of its own
    if template == "UIPanelCloseButton" then f.__w, f.__h = 32, 32 end
    f.__level = (parent and parent.__level or 0) + 1
    if name then _G[name] = f end
    allFrames[#allFrames + 1] = f
    return f
end

UIParent = NewWidget("Frame", nil)
UIParent.__level = 0
UISpecialFrames = {}
SlashCmdList = {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
RAID_CLASS_COLORS = {
    ROGUE = { r = 1.00, g = 0.96, b = 0.41 }, MAGE = { r = 0.41, g = 0.80, b = 0.94 },
    PRIEST = { r = 1.00, g = 1.00, b = 1.00 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    WARLOCK = { r = 0.58, g = 0.51, b = 0.79 }, DRUID = { r = 1.00, g = 0.49, b = 0.04 },
}
CLASS_ICON_TCOORDS = {
    WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 },
    ROGUE = { 0.49609375, 0.7421875, 0, 0.25 }, DRUID = { 0.7421875, 0.98828125, 0, 0.25 },
    PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 },
}
-- The client's one shared tooltip, as strict as the widgets: a method it
-- does not have is nil, it will not show with no owner, and its text has to
-- be text. What it was last told is kept for the checks to read.
local tooltip = { lines = {} }
local TIP_ANCHORS = { ANCHOR_RIGHT = true, ANCHOR_LEFT = true, ANCHOR_TOP = true, ANCHOR_BOTTOM = true }
local tipImpl = {}
function tipImpl.SetOwner(_, owner, anchor)
    if type(owner) ~= "table" or not rawget(owner, "__kind") then error("GameTooltip:SetOwner: no owner", 2) end
    if not TIP_ANCHORS[anchor] then error("GameTooltip:SetOwner: bad anchor " .. tostring(anchor), 2) end
    tooltip.owner, tooltip.anchor, tooltip.title, tooltip.lines, tooltip.shown = owner, anchor, nil, {}, false
end
function tipImpl.SetText(_, text)
    if type(text) ~= "string" then error("GameTooltip:SetText: not text: " .. tostring(text), 2) end
    tooltip.title, tooltip.lines = text, {}
end
function tipImpl.AddLine(_, text, _, _, _, wrap)
    if type(text) ~= "string" then error("GameTooltip:AddLine: not text: " .. tostring(text), 2) end
    tooltip.lines[#tooltip.lines + 1] = { text = text, wrap = wrap }
end
function tipImpl.Show()
    if not tooltip.owner then error("GameTooltip:Show: no owner", 2) end
    tooltip.shown = true
end
function tipImpl.Hide() tooltip.owner, tooltip.shown = nil, false end
GameTooltip = setmetatable({}, { __index = function(_, key)
    if tipImpl[key] then called[key] = true end
    return tipImpl[key]
end })

local prints = {}
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    prints[#prints + 1] = table.concat(parts, " ")
end

local function Fire(event, ...)
    local list = {}
    for i, f in ipairs(eventRegistry[event] or {}) do list[i] = f end
    for _, f in ipairs(list) do
        local handler = f.__scripts.OnEvent
        if handler then
            local ok, err = pcall(handler, f, event, ...)
            if not ok then caughtErrors[#caughtErrors + 1] = event .. ": " .. tostring(err) end
        end
    end
end

-- Run something of the module's the way the client would: an error is
-- caught and counted, not thrown through the smoke
local function Run(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then caughtErrors[#caughtErrors + 1] = label .. ": " .. tostring(err) end
end

-- ---------------------------------------------------------------------------
-- The mouse
-- ---------------------------------------------------------------------------
-- Where a frame is, in pixels from its window's bottom-left corner. A window
-- is whatever hangs straight off UIParent; everything else is one anchor to
-- something that can be placed the same way, with offsets and a size in the
-- frame's own scale.
local function Along(point)
    local x = (point:find("LEFT") and 0) or (point:find("RIGHT") and 1) or 0.5
    local y = (point:find("BOTTOM") and 0) or (point:find("TOP") and 1) or 0.5
    return x, y
end
local function Rect(widget)
    if widget.__parent == UIParent then return 0, 0, widget.__w or 0, widget.__h or 0 end
    if widget.__allPoints then return Rect(widget.__allPoints) end
    local p = widget.__point
    if not p then return 0 / 0, 0 / 0, 0 / 0, 0 / 0 end
    local scale, up = 1, widget
    while up do
        scale = scale * (up.__scale or 1)
        up = up.__parent
    end
    local x0, y0, x1, y1 = Rect(p.rel)
    local fx, fy = Along(p.relPoint)
    local ax, ay = x0 + (x1 - x0) * fx + p.x * scale, y0 + (y1 - y0) * fy + p.y * scale
    local w, h = (widget.__w or 0) * scale, (widget.__h or 0) * scale
    fx, fy = Along(p.point)
    return ax - w * fx, ay - h * fy, ax + w * (1 - fx), ay + h * (1 - fy)
end
local function Middle(widget)
    local x0, y0, x1, y1 = Rect(widget)
    return (x0 + x1) / 2, (y0 + y1) / 2
end

-- The frame a click at this point would go to, or nil: shown, taking the
-- mouse, under the point, and of those the highest level (the later made,
-- between two on one level)
local function Under(x, y)
    local best
    for _, f in ipairs(allFrames) do
        if f.__mouse and Visible(f) and (f.__point or f.__parent == UIParent) then
            local x0, y0, x1, y1 = Rect(f)
            if x >= x0 and x < x1 and y >= y0 and y < y1 and (not best or f.__level >= best.__level) then best = f end
        end
    end
    return best
end

local mouse = {}
local function Hover()
    local over = mouse.x and Under(mouse.x, mouse.y) or nil
    if over == mouse.over then return end
    local was = mouse.over
    mouse.over = over
    if was and was.__scripts.OnLeave then Run("OnLeave", was.__scripts.OnLeave, was) end
    if over and over.__scripts.OnEnter then Run("OnEnter", over.__scripts.OnEnter, over) end
end
local function MouseTo(x, y)
    mouse.x, mouse.y = x, y
    Hover()
    return mouse.over
end
-- A left click at a point of the window. Hands back the frame that took it.
local function ClickAt(x, y)
    local over = MouseTo(x, y)
    if over and over.__kind == "Button" and over.__scripts.OnClick then
        Run("OnClick", over.__scripts.OnClick, over, "LeftButton")
    end
    return over
end
-- A click on the middle of a widget -- which is not a promise that the
-- widget is what takes it
local function ClickOn(widget) return ClickAt(Middle(widget)) end
-- Whether a HIGHLIGHT texture is being drawn: only under the pointer
local function Highlighted(texture)
    return texture.__layer == "HIGHLIGHT" and texture.__shown and mouse.over ~= nil and mouse.over == texture.__parent
end

-- One frame of the client: every VISIBLE frame's OnUpdate, and no other's,
-- and then the pointer finds out what it is over now
local function Frame(elapsed)
    now = now + elapsed
    for _, f in ipairs(allFrames) do
        local handler = f.__scripts.OnUpdate
        if handler and Visible(f) then
            local ok, err = pcall(handler, f, elapsed)
            if not ok then caughtErrors[#caughtErrors + 1] = "OnUpdate: " .. tostring(err) end
        end
    end
    Hover()
end

local function Advance(seconds, step)
    step = step or 0.05
    for _ = 1, math.floor(seconds / step + 0.5) do Frame(step) end
end

-- ---------------------------------------------------------------------------
-- Commander: only what the module calls, and strict about it
-- ---------------------------------------------------------------------------
-- A name the module reaches for that is not stubbed here is an error, so a
-- misspelt framework call fails this smoke the way it would fail the game.
-- Every name it does reach for is remembered, and section K checks each one
-- against the real framework's source.
local used = {}
local function Strict(prefix, fields)
    return setmetatable({}, { __index = function(_, key)
        local value = fields[key]
        if value == nil then
            error(prefix .. tostring(key) .. " is not something this smoke has seen the module use", 2)
        end
        used[prefix .. key] = true
        return value
    end })
end

local function OnlyKeys(what, opts, allowed)
    for key in pairs(opts) do
        if not allowed[key] then error(what .. ": unknown option " .. tostring(key), 3) end
    end
end

local listeners = {}
local panelOpts, controls, settingsOpened = nil, {}, 0
-- Every table of defaults the module asked to have filled in, so section A
-- can read the seed a fresh install starts from without a second copy of it
local defaultsApplied = {}
local panelFields = {}
function panelFields.AddSection(_, text)
    controls[#controls + 1] = { kind = "section", label = text }
end
function panelFields.AddCheckbox(_, opts)
    OnlyKeys("AddCheckbox", opts, { label = true, tooltip = true, get = true, set = true, isEnabled = true })
    controls[#controls + 1] = { kind = "checkbox", label = opts.label, opts = opts }
end
function panelFields.AddDropdown(_, opts)
    OnlyKeys("AddDropdown", opts, {
        label = true, tooltip = true, options = true, get = true, set = true, width = true,
        isEnabled = true, onSelect = true,
    })
    controls[#controls + 1] = { kind = "dropdown", label = opts.label, opts = opts }
end
-- The slash wiring is the real Finalize's, line for line (CommanderSettingsUI
-- .lua): exact lower-cased match, "reset" wired to onDefaults, and "settings"
-- added when the bare command has been taken for something else
function panelFields.Finalize(_, opts)
    OnlyKeys("Finalize", opts, { onDefaults = true, defaultsTooltip = true })
    local key = "COMMANDERUI_" .. panelOpts.key:upper()
    for i, cmd in ipairs(panelOpts.slash) do _G["SLASH_" .. key .. i] = cmd end
    local handlers = panelOpts.slashHandlers or {}
    local function OpenPanel() settingsOpened = settingsOpened + 1 end
    if opts.onDefaults and not handlers.reset then handlers.reset = opts.onDefaults end
    if handlers[""] and not handlers.settings then handlers.settings = OpenPanel end
    SlashCmdList[key] = function(msg)
        msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if handlers[msg] then
            handlers[msg]()
        elseif msg == "" then
            OpenPanel()
        else
            print("Usage: " .. panelOpts.slash[1])
        end
    end
end

local function CopyValue(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = CopyValue(v) end
    return copy
end

Commander = Strict("Commander.", {
    AddListener = function(event, fn)
        listeners[event] = listeners[event] or {}
        table.insert(listeners[event], fn)
    end,
    Notify = function(event)
        for _, fn in ipairs(listeners[event] or {}) do Run("Notify", fn) end
    end,
    RoundIcon = function(icon)
        if rawget(icon, "__kind") ~= "Texture" then error("RoundIcon: not a texture", 2) end
        icon.__rounded = true
        return true
    end,
    UI = Strict("Commander.UI.", {
        ApplyDefaults = function(db, defaults)
            defaultsApplied[#defaultsApplied + 1] = defaults
            for key, value in pairs(defaults) do
                if db[key] == nil then db[key] = CopyValue(value) end
            end
        end,
        ResetToDefaults = function(db, defaults)
            for key, value in pairs(defaults) do db[key] = CopyValue(value) end
        end,
        ApplyStyleBackdrop = function(frame, style) frame.__style = style end,
        AttachTooltip = function(widget, title, text) widget.__tooltip = { title, text } end,
        NewPanel = function(opts)
            OnlyKeys("NewPanel", opts, {
                key = true, title = true, addonName = true, description = true, event = true,
                slash = true, slashHandlers = true, foldSections = true,
            })
            panelOpts = opts
            return Strict("panel.", panelFields)
        end,
    }),
})

-- ===========================================================================
-- Load, in .toc order -- read from the .toc, so the order is written once
-- ===========================================================================
local function ReadFile(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local text = handle:read("*a")
    handle:close()
    return text
end

local tocText = assert(ReadFile(HERE .. "/Commander_Gladiator.toc"), "the .toc is missing")
local tocFiles, tocFields = {}, {}
for line in tocText:gmatch("[^\r\n]+") do
    local field, value = line:match("^##%s*(%S+):%s*(.-)%s*$")
    if field then
        tocFields[field] = value
    elseif not line:match("^%s*#") and line:match("%S") then
        tocFiles[#tocFiles + 1] = line:match("^%s*(.-)%s*$")
    end
end

for index, file in ipairs(tocFiles) do
    local chunk, err = loadfile(HERE .. "/" .. file)
    if not chunk then error("could not load " .. file .. ": " .. tostring(err)) end
    local ok, runErr = pcall(chunk)
    if not ok then error("error running " .. file .. ": " .. tostring(runErr)) end
    -- The client swaps the saved table in after the files have run and
    -- before ADDON_LOADED. This is somebody's SECOND session: a record and a
    -- seed from last time, no settings yet (as if they were new keys), and a
    -- window that was never dragged anywhere.
    if index == #tocFiles then
        CommanderGladiatorDB = { Wins = 7, Losses = 3, Seed = 41 }
    end
end

local DATA, E, G = CommanderGladiator_Data, CommanderGladiator_Engine, CommanderGladiator
local ARENA, TICK = DATA.ARENA, DATA.ARENA.tick
local L, S = G.LAYOUT, G.state
local Slash

-- === A: login =================================================================
Section("A", function()
    Fire("ADDON_LOADED", "Commander_Events")
    EQ(CommanderGladiatorDB.Enabled, nil, "A: somebody else's ADDON_LOADED is not ours")
    Fire("ADDON_LOADED", "Commander_Gladiator")
    Fire("PLAYER_LOGIN")
    EQ(#caughtErrors, 0, "A: ADDON_LOADED and PLAYER_LOGIN run clean")
    local db = CommanderGladiatorDB
    EQ(db.Enabled, true, "A: Enabled defaults on")
    EQ(db.Speed, 1, "A: Speed defaults to 1x")
    EQ(db.Pinned, false, "A: nobody has pinned an enemy yet")
    EQ(db.Tapped, false, "A: nor tapped a spell")
    EQ(db.Draws, 0, "A: a missing book entry is filled in")
    EQ(db.Wins, 7, "A: saved wins are kept")
    EQ(db.Losses, 3, "A: saved losses are kept")
    EQ(db.Seed, 41, "A: the saved seed is kept")

    Slash = SlashCmdList.COMMANDERUI_GLADIATOR
    CHECK(Slash ~= nil, "A: the slash command is registered")
    EQ(SLASH_COMMANDERUI_GLADIATOR1, "/cglad", "A: and it is /cglad")
    EQ(panelOpts and panelOpts.addonName, "Commander_Gladiator", "A: the panel names its addon")
    EQ(panelOpts and panelOpts.event, COMMANDER_GLADIATOR_EVENTS.UPDATE, "A: the panel notifies the module's event")

    local labels = {}
    for _, control in ipairs(controls) do
        if control.opts then labels[#labels + 1] = control.label end
    end
    EQ(table.concat(labels, "|"), "Enable Gladiator|Match Speed", "A: two settings, each with a control")
    for _, control in ipairs(controls) do
        if control.opts then
            CHECK(type(control.opts.tooltip) == "string" and #control.opts.tooltip > 10, "A: " .. control.label .. " has a tooltip")
        end
    end

    EQ(CommanderGladiatorWindow, nil, "A: no window was built at login")
    EQ(S.match, nil, "A: and no match was dealt")

    -- Restore Defaults puts the settings back and leaves the book alone
    db.Speed, db.Enabled, db.Pinned, db.Tapped = 2, false, true, true
    Run("reset", Slash, "reset")
    EQ(db.Speed, 1, "A: reset restores the speed")
    EQ(db.Enabled, true, "A: reset restores the switch")
    CHECK(db.Pinned == false and db.Tapped == false, "A: and forgets that the hint was ever followed")
    EQ(db.Wins, 7, "A: reset keeps the record")
    EQ(db.Seed, 41, "A: reset keeps the seed")

    Run("settings", Slash, "settings")
    EQ(settingsOpened, 1, "A: /cglad settings opens the page")

    -- Switched off, the bare command opens nothing and says why
    db.Enabled = false
    local before = #prints
    Run("toggle off", Slash, "")
    EQ(CommanderGladiatorWindow, nil, "A: switched off, /cglad builds no window")
    CHECK(#prints == before + 1 and prints[#prints]:find("switched off", 1, true), "A: and says it is switched off")
    db.Enabled = true
    EQ(#caughtErrors, 0, "A: no error in any of that")

    -- A fresh install has no book, so what it watches first is the default
    -- seed and the ones after it, in order, the same on every machine. The
    -- balance is even over a thousand seeds and says nothing about any
    -- twelve of them: seeds 3 to 12 were once ten defeats in a row. So the
    -- first dozen are played here, with the shipped data and engine, and
    -- have to look like a fair game: a win to open on, about as many won as
    -- lost, and no run of more than three either way. A retune that turns
    -- this red wants a new default seed, not a wider line.
    local fresh
    for _, defaults in ipairs(defaultsApplied) do fresh = fresh or defaults.Seed end
    CHECK(type(fresh) == "number", "A: (setup) the book's defaults carry a seed", fresh)
    local letters, wins, run, longest = {}, 0, 0, 0
    for index = 1, 12 do
        local match = E.NewMatch(DATA.TEAMS.A, DATA.TEAMS.B, (fresh or 1) + index - 1)
        for _ = 1, 2000 do
            if match.over then break end
            match:Step()
        end
        local letter = match.winner == "DRAW" and "D" or match.winner or "?"
        run = letter == letters[index - 1] and run + 1 or 1
        longest = math.max(longest, run)
        if letter == "A" then wins = wins + 1 end
        letters[index] = letter
    end
    local dozen = table.concat(letters, " ")
    EQ(letters[1], "A", "A: a fresh install's first match is a win")
    CHECK(wins >= 5 and wins <= 7, "A: its first dozen are about even", dozen)
    CHECK(longest <= 3, "A: with no run of more than three either way", dozen)
end)

-- What was painted, read back off the widgets.
--
-- A widget the window never painted has none of what these read: no anchor,
-- no size, no colour, no cooldown. That is a failed check and must not be
-- an error, so where the window wrote nothing each reader hands back NEVER
-- in place of the number. NEVER is not-a-number: equal to nothing, itself
-- included, and neither above nor below anything, so every comparison made
-- with it is false, arithmetic on it is NEVER again, and the check that
-- asked goes red with "nan" in its detail. (A check that asks for an
-- ABSENCE -- a token clear of the pillars -- is not turned red by it, and
-- need not be: wherever there is one, the same numbers are read the
-- straight way by the checks beside it.)
local NEVER = 0 / 0
local function Anchor(widget, point)
    local p = widget.__points and widget.__points[point]
    if not p then return NEVER, NEVER end
    return p.x, p.y
end
local function Size(widget) return widget.__w or NEVER, widget.__h or NEVER end

local window, floor
local function Foot(token) return Anchor(token.shadow, "CENTER") end
local function TokenRect(token)
    local x, y = Anchor(token, "CENTER")
    local scale = token.__scale or 1
    local cx, cy, half = x * scale, y * scale, Size(token) / 2 * scale
    return cx - half, cy - half, cx + half, cy + half
end
local function OnFloor(x, y)
    local cx, cy = Anchor(floor, "CENTER")
    local w, h = Size(floor)
    local dx, dy = (x - cx) / (w / 2), (y - cy) / (h / 2)
    return dx * dx + dy * dy <= 1
end
-- A pillar's box: its body, and the round of its cap and foot above and below
local function PillarRect(body)
    local x, y = Anchor(body, "BOTTOM")
    local w, h = Size(body)
    local round = w * 0.18
    return x - w / 2, y - round, x + w / 2, y + h + round
end
local function Overlap(ax0, ay0, ax1, ay1, bx0, by0, bx1, by1)
    return ax0 < bx1 and bx0 < ax1 and ay0 < by1 and by0 < ay1
end
-- Where a token's middle was painted, in window pixels: its anchor is in the
-- token's own scaled units, so it is multiplied back out
local function Centre(token)
    local x, y = Anchor(token, "CENTER")
    local scale = token.__scale or 1
    return x * scale, y * scale
end
local function Colour(widget)
    local colour = widget.__color
    if not colour then return NEVER, NEVER, NEVER end
    return colour[1], colour[2], colour[3]
end
-- The floating numbers on screen now, and the projectiles
local function Showing(list)
    local shown = {}
    for _, widget in ipairs(list) do
        if widget.__shown then shown[#shown + 1] = widget end
    end
    return shown
end
-- The share a health ring is showing: 1 for the full texture, 0 for nothing,
-- and otherwise what the frozen cooldown it was handed works out to
local function ArcShare(arc)
    if arc.full.__shown then return 1 end
    if not arc.cd.__shown then return 0 end
    local cd = arc.cd.__cd
    if not cd then return NEVER end
    return 1 - (now - cd.start) / cd.duration
end
local function RingShare(token) return ArcShare(token.arc) end
-- A button's cooldown is drawn by the same recipe: the share still to run
local function SweepShare(button) return ArcShare(button.sweep) end

-- What a button is saying, from what was painted on it and nothing else:
-- grey is DEAD, a halo is LIT, a wedge is SWEEP, and none of them is DIM.
local function Says(button)
    if button.icon.__desat then return "DEAD" end
    if button.halo.__shown then return "LIT" end
    if SweepShare(button) > 0 then return "SWEEP" end
    return "DIM"
end
-- And what it ought to be saying, written from the brief and not from the
-- window: dead; else cooling down, with the share of the row's cooldown
-- still to run by the engine's own ticks; else lit if the gates are open
-- and a tap would fire; else dim.
local function Should(match, unit, gatesShut)
    if not unit.alive then return "DEAD", 0 end
    local left = (unit.ready[unit.big.key] or 0) - match.tick
    if left > 0 then return "SWEEP", left / (unit.big.cooldown * 10) end
    if not gatesShut and match:Lit(unit) then return "LIT", 0 end
    return "DIM", 0
end

-- === B: open ==================================================================
Section("B", function()
    -- No place has ever been saved: this is the first /cglad anybody types,
    -- and the window opens in the middle. (A saved place is section L.)
    EQ(CommanderGladiatorDB.Pos, nil, "B: (setup) the window has never been dragged")
    Run("open", Slash, "")
    window = CommanderGladiatorWindow
    CHECK(window ~= nil and window.__shown, "B: /cglad shows the window")
    EQ(#caughtErrors, 0, "B: without an error", caughtErrors[1])
    -- Everything after this reads what a clean opening painted. If it was
    -- not clean, the honest report is the error, not two hundred checks
    -- failing on the widgets it never reached.
    if not window or #caughtErrors > 0 then
        io.write("the window did not open cleanly; nothing further can be trusted\n")
        for _, err in ipairs(caughtErrors) do io.write("  error: ", err, "\n") end
        io.write(string.format("%d checks, %d failures\n", checks, fails))
        os.exit(1)
    end
    floor = G.floor
    EQ(window.__w, 560, "B: 560 wide")
    EQ(window.__h, 432, "B: 432 tall")
    EQ(window.__style, "DARK", "B: in the suite's dark panel")
    local middle = window.__points.CENTER
    CHECK(middle and middle.rel == UIParent and middle.relPoint == "CENTER", "B: never dragged, it opens on the middle of the screen")
    EQ(middle and middle.x, 0, "B: dead centre across")
    EQ(middle and middle.y, 60, "B: and a little above it")
    EQ(UISpecialFrames[1], "CommanderGladiatorWindow", "B: Escape closes it")
    -- A frame that never registered for a drag is never sent OnDragStart,
    -- whatever script it carries: the three together are "can be dragged"
    EQ(window.__movable, true, "B: movable")
    EQ(window.__mouse, true, "B: and takes the mouse to be dragged")
    EQ(window.__drag, "LeftButton", "B: by the left button")
    EQ(window.__toplevel, true, "B: a click raises it over other windows")
    EQ(window.__clamped, true, "B: and it cannot be dragged off the screen")

    -- Dragged somewhere: the place it was dropped is what is saved
    window.__scripts.OnDragStart(window)
    window.__point = { point = "BOTTOMRIGHT", rel = UIParent, relPoint = "BOTTOMRIGHT", x = -33, y = 44 }
    Run("drop", window.__scripts.OnDragStop, window)
    local pos = CommanderGladiatorDB.Pos
    CHECK(pos.point == "BOTTOMRIGHT" and pos.x == -33 and pos.y == 44, "B: a drag saves where it was dropped")
    EQ(window.__moving, false, "B: and stops the move")

    local match = S.match
    CHECK(match ~= nil and not match.over, "B: opening it deals a match")
    EQ(match.tick, 0, "B: which has not started")
    EQ(G.count.__shown, true, "B: it is held at its gates, and a line says so")
    EQ(G.count.__text, "Gates open in 2", "B: counting down from two")
    EQ(S.seed, 41, "B: from the saved seed")
    EQ(CommanderGladiatorDB.Seed, 42, "B: and the book has already moved on")
    EQ(G.record.__text, "7 won   3 lost", "B: the header shows the record")
    EQ(G.speedButton.__text, "1x", "B: and the speed")
    EQ(G.healing.__shown, false, "B: and nothing about healing, which is whole")
    EQ(#G.tokens, 6, "B: six tokens")

    local sides = { A = 0, B = 0 }
    local names = {}
    for id, token in ipairs(G.tokens) do
        local unit = match.units[id]
        local green = token.arc.full.__color[2] > token.arc.full.__color[1]
        sides[green and "A" or "B"] = sides[green and "A" or "B"] + 1
        EQ(green, unit.side == "A", "B: token " .. id .. " wears its side's colour")
        names[id] = token.name.__text
        local coords = CLASS_ICON_TCOORDS[unit.spec.class]
        CHECK(token.badge.__coords[1] == coords[1] and token.badge.__coords[3] == coords[3],
              "B: token " .. id .. " wears its class badge")
        local c = RAID_CLASS_COLORS[unit.spec.class]
        CHECK(token.disc.__color[1] == c.r and token.disc.__color[3] == c.b, "B: token " .. id .. " is its class colour")
        CHECK(token.__shown and token.badge.__shown and not token.swap.__shown, "B: token " .. id .. " shows its own face")
        EQ(RingShare(token), 1, "B: token " .. id .. " starts on a full ring")
        CHECK(not token.rim.__shown and not token.glow.__shown and not token.pin.__shown
              and not token.frost.__shown and not token.mark.__shown and not token.order.__shown,
              "B: token " .. id .. " starts unadorned")
        -- Only an enemy can be clicked, and the ring that says so is the
        -- client's own highlight: drawn under the pointer and nowhere else
        EQ(token.__kind, "Button", "B: token " .. id .. " is something a click can land on")
        EQ(token.__mouse, unit.side == "B", "B: token " .. id .. " takes the mouse only if it is an enemy")
        EQ(token.hover.__layer, "HIGHLIGHT", "B: token " .. id .. " has a ring for the pointer")
        local round = token.hover.__points and token.hover.__points.CENTER
        CHECK(round and round.rel == token and round.relPoint == "CENTER" and round.x == 0 and round.y == 0,
              "B: centred on token " .. id)
        EQ(Highlighted(token.hover), false, "B: which is not drawn with the pointer elsewhere")

        local fx, fy = Foot(token)
        local px, py, scale = G.Project(unit.x, unit.y)
        NEAR(fx, px, "B: token " .. id .. " stands where its unit is (x)")
        NEAR(fy, py, "B: token " .. id .. " stands where its unit is (y)")
        NEAR(token.__scale, scale, "B: token " .. id .. " is drawn at its depth's scale")
        CHECK(OnFloor(fx, fy), "B: token " .. id .. " is on the floor", fx .. "," .. fy)
        local x0, y0, x1, y1 = TokenRect(token)
        NEAR(y0, fy, "B: token " .. id .. " rests on its feet", 0.01)
        for _, body in ipairs(G.pillars) do
            CHECK(not Overlap(x0, y0, x1, y1, PillarRect(body)), "B: token " .. id .. " is clear of the pillars")
        end
    end
    EQ(sides.A, 3, "B: three on your side")
    EQ(sides.B, 3, "B: three on theirs")
    EQ(table.concat(names, " "), "Subtlety Frost Discipline Arms Affliction Restoration", "B: each wears its spec's short name")
    CHECK(Foot(G.tokens[1]) < Foot(G.tokens[4]), "B: your side starts on the left")

    EQ(#G.pillars, 2, "B: two pillars")
    for index, body in ipairs(G.pillars) do
        local x0, y0, x1, y1 = PillarRect(body)
        CHECK(OnFloor(x0, y0) and OnFloor(x1, y0), "B: pillar " .. index .. " stands on the floor")
        CHECK(y1 < L.height - L.header, "B: pillar " .. index .. " stays under the header")
    end

    -- The bar: a button for each of your three, in slot order, under the
    -- floor and clear of it, each big enough to hit and wearing its
    -- gladiator's big spell, class colour and short name
    local bar = G.buttons
    EQ(#bar, 3, "B: three buttons under the floor")
    local floorMidX, floorMidY = Anchor(floor, "CENTER")
    local _, floorTall = Size(floor)
    local slabBottom = floorMidY - floorTall / 2 - L.slab
    local barNames, barLeft, barRight, barTop = {}, math.huge, -math.huge, NEVER
    for slot, button in ipairs(bar) do
        local unit = match.units[slot]
        local x0, y0, x1, y1 = Rect(button)
        EQ(button.__kind, "Button", "B: button " .. slot .. " is a button")
        CHECK(x1 - x0 >= 36 and y1 - y0 >= 36, "B: button " .. slot .. " is large enough to hit", x1 - x0)
        EQ(button.icon.__texture, unit.big.icon, "B: button " .. slot .. " wears its gladiator's big spell")
        CHECK(button.icon.__shown and button.icon.__rounded and button.icon.__w == 36, "B: button " .. slot .. "'s icon is round and 36 across")
        barNames[slot] = button.name.__text
        CHECK(x0 >= barRight + 8 or slot == 1, "B: button " .. slot .. " stands to the right of the one before, with a gap", x0 - barRight)
        barLeft, barRight, barTop = math.min(barLeft, x0), x1, y1
        CHECK(y1 + 8 <= slabBottom, "B: button " .. slot .. " is clear of the floor's slab", slabBottom - y1)
        local under = button.name.__points and button.name.__points.TOP
        CHECK(under and under.rel == button and under.relPoint == "BOTTOM", "B: button " .. slot .. "'s name hangs under it")
        CHECK(under and y0 + under.y - 11 >= 4, "B: and is inside the window", y0)
        -- The rim is the class colour, however brightly it is drawn
        local c, rim = RAID_CLASS_COLORS[unit.spec.class], button.rim.__color
        local share = rim and rim[1] / c.r or NEVER
        CHECK(share > 0 and math.abs(rim[2] / c.g - share) < 0.001 and math.abs(rim[3] / c.b - share) < 0.001,
              "B: button " .. slot .. " is rimmed in its gladiator's class colour", share)
        EQ(Says(button), "DIM", "B: button " .. slot .. " is dim while the gates are shut")
        EQ(button.__mouse, true, "B: button " .. slot .. " takes the mouse")
    end
    EQ(table.concat(barNames, " "), "Subtlety Frost Discipline", "B: each button is named for its gladiator, in slot order")
    NEAR((barLeft + barRight) / 2, L.width / 2, "B: the bar is centred under the floor")
    CHECK(barLeft >= 0 and barRight <= L.width, "B: and inside the window")

    -- The hint: one verb either side of the bar, in the corners the round
    -- floor leaves empty
    EQ(#G.hints, 2, "B: the hint is in two halves")
    CHECK(G.hints[1].__shown and G.hints[2].__shown, "B: both shown to somebody who has done neither")
    EQ((tostring(G.hints[1].__text) .. " " .. tostring(G.hints[2].__text)):gsub("\n", " "),
       "Click an enemy to set the kill target. Tap a glowing spell to fire it now.", "B: and together they are the hint")
    CHECK(select(2, G.hints[1].__text:gsub("\n", "")) == 1 and select(2, G.hints[2].__text:gsub("\n", "")) == 1,
          "B: each broken into two lines")
    local hintLeft, hintLeftY = Anchor(G.hints[1], "RIGHT")
    local hintRight, hintRightY = Anchor(G.hints[2], "LEFT")
    local hintWide = G.hints[1].__w or NEVER
    CHECK(hintWide >= 120 and G.hints[2].__w == hintWide, "B: each half has a width to wrap in", hintWide)
    CHECK(hintLeft - hintWide >= 4 and hintLeft + 8 <= barLeft, "B: the first half is left of the bar and inside the window", hintLeft)
    CHECK(hintRight - 8 >= barRight and hintRight + hintWide <= L.width - 4, "B: the second is right of it and inside the window", hintRight)
    CHECK(G.hints[1].__justify == "RIGHT" and G.hints[2].__justify == "LEFT", "B: each is set against the bar")
    -- Three lines of small type is eighteen pixels either side of the middle
    CHECK(not OnFloor(hintLeft, hintLeftY + 18 + L.slab) and not OnFloor(hintRight, hintRightY + 18 + L.slab),
          "B: and neither half reaches the floor's slab")
    CHECK(hintLeftY - 18 >= 4, "B: nor the window's bottom edge", hintLeftY)

    -- The countdown is written over the heads of the back row and under
    -- the header
    local countX, countY = Anchor(G.count, "CENTER")
    NEAR(countX, L.width / 2, "B: the countdown is over the middle of the floor")
    CHECK(countY + 9 < L.height - L.header, "B: under the header", countY)
    for id, token in ipairs(G.tokens) do
        local _, _, _, top = TokenRect(token)
        CHECK(countY - 9 > top, "B: and over the head of token " .. id, countY - top)
    end

    -- Every place the engine can put a unit, not only the six it starts on:
    -- feet on the floor, token inside the window and under the header, its
    -- name clear of the bar, and never touching a pillar. This is what
    -- "where nobody walks" means.
    CHECK(barTop > 40, "B: (the bar's top edge is a real height)", barTop)
    local off, out, hit, places = 0, 0, 0, 0
    for x = ARENA.minX, ARENA.maxX do
        for y = ARENA.minY, ARENA.maxY do
            places = places + 1
            local px, py, scale = G.Project(x, y)
            local half = L.token / 2 * scale
            if not OnFloor(px, py) then off = off + 1 end
            -- A token's name hangs a line under its feet
            if px - half < 0 or px + half > L.width or py - 12 * scale < barTop or py + 2 * half > L.height - L.header then
                out = out + 1
            end
            for _, body in ipairs(G.pillars) do
                if Overlap(px - half, py, px + half, py + 2 * half, PillarRect(body)) then hit = hit + 1 end
            end
        end
    end
    EQ(places, 101 * 51, "B: the whole floor was swept")
    EQ(off, 0, "B: nowhere on the engine's floor is off the painted one")
    EQ(out, 0, "B: nowhere on it puts a token outside the window, over the header or onto the bar")
    EQ(hit, 0, "B: nowhere on it touches a pillar")
    EQ(#caughtErrors, 0, "B: no error opening it")
end)

-- Checked after every frame of every match from here on, and reported once
local audit = {
    frames = 0, ringOff = 0, offFloor = 0, ringDetail = nil, numbers = 0, shots = 0, pops = 0, bumps = 0, bursts = 0,
    damage = 0, heal = 0, absorb = 0, crits = 0, ticks = 0, basicPops = 0, healingOff = 0, healingDetail = nil,
    barOff = 0, barDetail = nil, mouseOff = 0, pinOff = 0, lit = 0, swept = 0, dim = 0, gateFrames = 0,
}
local basics = {}
for _, spec in pairs(CommanderGladiator_Data.SPECS) do basics[spec.basic.name] = true end
local function Audit()
    local match = S.match
    audit.frames = audit.frames + 1
    for id, token in ipairs(G.tokens) do
        local unit = match.units[id]
        local want = unit.alive and unit.health / unit.healthMax or 0
        -- Two thousandths: a ring within that of full is drawn as the full
        -- texture and within that of empty as nothing, and a sweep is only
        -- re-set once the share has moved a thousandth
        if math.abs(RingShare(token) - want) > 0.0021 then
            audit.ringOff = audit.ringOff + 1
            audit.ringDetail = audit.ringDetail or string.format("token %d shows %.4f, unit has %.4f at %.1f s", id, RingShare(token), want, match.time)
        end
        if not OnFloor(Foot(token)) then audit.offFloor = audit.offFloor + 1 end
        -- A click can land on an enemy that is standing in a match still
        -- being fought, and on nobody else; and the gold disc is on the
        -- enemy the match says is pinned, and on nobody else
        local open = unit.side == "B" and unit.alive and not match.over
        if token.__mouse ~= open then audit.mouseOff = audit.mouseOff + 1 end
        if token.order.__shown ~= (open and match.pin.A == unit) then audit.pinOff = audit.pinOff + 1 end
        if token.popIcon.__shown then
            audit.pops = audit.pops + 1
            if basics[token.popText.__text] then audit.basicPops = audit.basicPops + 1 end
        end
        -- A bump is a token painted off its own feet while nothing is
        -- swaying it
        local centre = token.__points.CENTER.x * token.__scale
        if not unit.disabled and math.abs(centre - Foot(token)) > 0.5 then audit.bumps = audit.bumps + 1 end
    end
    for _, fs in ipairs(G.numbers) do
        if fs.__shown then
            audit.numbers = audit.numbers + 1
            for _, kind in ipairs({ "damage", "heal", "absorb" }) do
                local c = G.COLOURS[kind]
                if fs.__color[1] == c[1] and fs.__color[2] == c[2] and fs.__color[3] == c[3] then
                    audit[kind] = audit[kind] + 1
                    -- A heal says so with its sign; a hit is a bare number
                    if (kind == "heal") ~= (fs.__text:sub(1, 1) == "+") then audit.missigned = fs.__text end
                end
            end
            if fs.__fontSize > 13 then audit.crits = audit.crits + 1 end
            if fs.__fontSize < 13 then audit.ticks = audit.ticks + 1 end
        end
    end
    for _, shot in ipairs(G.shots) do if shot.__shown then audit.shots = audit.shots + 1 end end
    if G.burst.__shown then audit.bursts = audit.bursts + 1 end
    -- The bar: every button says what its gladiator's big spell is doing,
    -- and its wedge is the share of the cooldown the engine has left
    local gatesShut = G.count.__shown
    if gatesShut then audit.gateFrames = audit.gateFrames + 1 end
    for slot, button in ipairs(G.buttons) do
        local unit = match.units[slot]
        local state, share = Should(match, unit, gatesShut)
        if Says(button) ~= state or math.abs(SweepShare(button) - share) > 0.0021 then
            audit.barOff = audit.barOff + 1
            audit.barDetail = audit.barDetail or string.format("button %d says %s %.4f, should say %s %.4f at %.1f s",
                slot, Says(button), SweepShare(button), state, share, match.time)
        end
        if state == "LIT" then audit.lit = audit.lit + 1 end
        if state == "SWEEP" then audit.swept = audit.swept + 1 end
        if state == "DIM" then audit.dim = audit.dim + 1 end
    end
    -- The header's healing line: empty while healing is whole, and otherwise
    -- the word for what the match is doing to it
    local share = match:Dampening()
    local want = (match.routed and "Routed") or (share <= 0 and "No healing") or (share < 1 and "Healing ") or nil
    local got = G.healing.__shown and G.healing.__text or nil
    if (want == nil) ~= (got == nil) or (want and got:sub(1, #want) ~= want) then
        audit.healingOff = audit.healingOff + 1
        audit.healingDetail = audit.healingDetail or string.format("%s at %.1f s, wanted %s", tostring(got), match.time, tostring(want))
    end
end

-- Frames until the match on the floor has left its gates, counted. Most
-- sections want a match that is running, and the wait is the window's.
local function OpenGates(step)
    local frames = 0
    while G.count.__shown and frames < 1000 do
        Frame(step or 0.05)
        frames = frames + 1
    end
    return frames
end

-- Frames until the match on the floor ends. Returns it, or nil if it never did.
local function PlayOut(step)
    local match = S.match
    for _ = 1, 4000 do
        if match.over then return match end
        Frame(step or 0.05)
        Audit()
    end
    return nil
end

local WORDS = { A = "Victory", B = "Defeat", DRAW = "Draw" }
local BOOK = { A = "Wins", B = "Losses", DRAW = "Draws" }
local outcomes = {}
local function Book()
    local db = CommanderGladiatorDB
    return { Wins = db.Wins, Losses = db.Losses, Draws = db.Draws }
end
-- The bell, checked the same way every time a match ends
local function CheckBell(tag, match, before)
    outcomes[match.winner] = true
    EQ(G.banner.__shown, true, tag .. ": the banner is up")
    EQ(G.bannerBand.__shown, true, tag .. ": on its dark band")
    EQ(G.banner.__text, WORDS[match.winner], tag .. ": and says the right word")
    -- Gold for a win, red for a defeat, grey for a draw
    local r, g, b = 0, 0, 0
    if G.banner.__color then r, g, b = Colour(G.banner) end
    if match.winner == "A" then
        CHECK(r > 0.9 and g > 0.7 and b < 0.5, tag .. ": in gold", r .. "," .. g .. "," .. b)
    elseif match.winner == "B" then
        CHECK(r > 0.8 and g < 0.5 and b < 0.5, tag .. ": in red", r .. "," .. g .. "," .. b)
    else
        CHECK(r > 0.5 and r == g and g == b, tag .. ": in grey", r .. "," .. g .. "," .. b)
    end
    local after, moved = Book(), 0
    for key in pairs(after) do moved = moved + (after[key] - before[key]) end
    EQ(moved, 1, tag .. ": the record moved by exactly one")
    EQ(after[BOOK[match.winner]], before[BOOK[match.winner]] + 1, tag .. ": in the winner's column")
    local marked, open = 0, 0
    for _, token in ipairs(G.tokens) do
        if token.mark.__shown or token.order.__shown then marked = marked + 1 end
        if token.__mouse then open = open + 1 end
    end
    EQ(marked, 0, tag .. ": nobody is anybody's target once it is over")
    EQ(open, 0, tag .. ": and nobody can be clicked")
    for slot, button in ipairs(G.buttons) do
        CHECK(not button.halo.__shown, tag .. ": button " .. slot .. " does not glow after the bell")
    end
end

-- === C: a whole match through the real OnUpdate ===============================
Section("C", function()
    local first = S.match
    -- The gates: two seconds of the match's own clock in which nothing
    -- moves. Thirty-eight frames in, it is still held and the line has
    -- counted down; two more and it is open, and the frame that opened it
    -- took no tick.
    for _ = 1, 38 do
        Frame(0.05)
        Audit()
    end
    EQ(first.tick, 0, "C: for the length of the gates the match does not move")
    EQ(G.count.__text, "Gates open in 1", "C: and the line counts down")
    for id, token in ipairs(G.tokens) do
        local fx, fy = Foot(token)
        local mark = ARENA.start[first.units[id].side][first.units[id].spec.role]
        local px, py = G.Project(mark.x, mark.y)
        CHECK(math.abs(fx - px) < 0.001 and math.abs(fy - py) < 0.001, "C: token " .. id .. " stands on its mark at the gates")
    end
    Advance(0.1)
    EQ(G.count.__shown, false, "C: two seconds in, the gates open and the line goes")
    EQ(first.tick, 0, "C: on a frame that takes no tick")
    Advance(2.0)
    NEAR(first.time, 2.0, "C: and from there two seconds of frames is two seconds of match", 0.051)

    -- Light smoothing: at five frames to a tick, a walking token moves on
    -- the frames BETWEEN ticks too. Unsmoothed, it would stand still for
    -- four frames and step on the fifth.
    local glides, tickFrames = 0, 0
    for _ = 1, 150 do
        local tick, before = first.tick, {}
        for id, token in ipairs(G.tokens) do before[id] = Foot(token) end
        Frame(0.02)
        Audit()
        if first.tick ~= tick then
            tickFrames = tickFrames + 1
        else
            for id, token in ipairs(G.tokens) do
                if math.abs(Foot(token) - before[id]) > 0.01 then glides = glides + 1 end
            end
        end
    end
    EQ(tickFrames, 30, "C: (setup) five frames to a tick")
    CHECK(glides > 60, "C: tokens move between ticks, not only on them", glides)

    -- One enormous frame -- a loading screen, an alt-tab. It costs maxSteps
    -- ticks and the rest is dropped, not owed.
    local tick = first.tick
    Frame(30)
    EQ(first.tick, tick + L.maxSteps, "C: a thirty-second frame takes exactly the step cap")
    CHECK(S.acc < TICK, "C: and leaves no backlog behind", S.acc)
    Frame(0.05)
    CHECK(first.tick <= tick + L.maxSteps + 1, "C: so the frame after it is an ordinary one")

    local before = Book()
    local ended = PlayOut()
    CHECK(ended == first, "C: the match ends")
    CHECK(first.time > 5 and first.time < DATA.RULES.cap + 0.01, "C: in a sane time", first.time)
    CheckBell("C", first, before)
    local db = CommanderGladiatorDB
    local text = string.format("%d won   %d lost", db.Wins, db.Losses)
    if db.Draws > 0 then text = text .. string.format("   %d drawn", db.Draws) end
    EQ(G.record.__text, text, "C: the header shows the new record")

    -- The banner has about three seconds, then the next match is dealt
    Advance(2.5)
    CHECK(S.match == first and G.banner.__shown, "C: the banner is still up after 2.5 s")
    Advance(1.0)
    CHECK(S.match ~= first, "C: a second match is dealt")
    EQ(S.seed, 42, "C: from the next seed")
    EQ(CommanderGladiatorDB.Seed, 43, "C: and the book moves on again")
    EQ(G.banner.__shown, false, "C: the banner comes down")
    EQ(G.bannerBand.__shown, false, "C: and its band with it")
    EQ(S.match.tick, 0, "C: the new match is at its gates")
    EQ(G.count.__shown, true, "C: with the line counting again")
    EQ(#caughtErrors, 0, "C: no Lua error in a whole match", caughtErrors[1])
end)

local function AbilityWith(unit, state)
    for _, ability in ipairs(unit.abilities) do
        for _, effect in ipairs(ability.effects) do
            if effect.state == state then return ability, effect end
        end
    end
    error("no ability on " .. unit.spec.name .. " leaves " .. state)
end

-- === D: state painting ========================================================
-- Forced through the engine's own doors (Use, Damage, Effects) on the match
-- the window dealt, and painted with zero-length frames so the match itself
-- does not move while each state is looked at.
Section("D, states", function()
    local match = S.match
    local rogue, mage, priest, warrior, warlock, druid = unpack(match.units)
    local T = G.tokens
    local function Paint() Frame(0) end
    OpenGates()

    -- Sheep: the face becomes the spell's icon, and comes back
    local poly = AbilityWith(mage, "sheeped")
    match:Use(mage, poly, druid)
    EQ(druid.disabled, "sheeped", "D: (setup) the druid is a sheep")
    Paint()
    EQ(T[6].swap.__shown, true, "D: a sheep's face is swapped")
    EQ(T[6].swap.__texture, poly.icon, "D: for the icon of the spell holding it")
    EQ(T[6].swap.__rounded, true, "D: rounded like the badge it replaces")
    EQ(T[6].badge.__shown, false, "D: and the class badge is put away")
    EQ(T[2].badge.__shown, true, "D: the mage who cast it keeps its own face")
    match:Damage(mage, druid, mage.spec.basic, 10, false, false)
    EQ(druid.disabled, nil, "D: (setup) damage broke the sheep")
    Paint()
    EQ(T[6].swap.__shown, false, "D: the sheep's face is taken off when it ends")
    EQ(T[6].badge.__shown, true, "D: and the class badge is back")

    -- The ring, at a share that is nobody's default
    NEAR(RingShare(T[6]), 890 / 900, "D: the ring follows a small hit", 0.0011)
    match:Damage(mage, druid, mage.spec.basic, 300, false, false)
    Paint()
    NEAR(RingShare(T[6]), 590 / 900, "D: the ring shows 590 of 900", 0.0011)
    EQ(T[6].arc.cd.__shown, true, "D: as a frozen cooldown")
    EQ(T[6].arc.cd.__swipeTexture, G.ART.ring, "D: cut from the ring's own art")
    EQ(T[6].arc.full.__shown, false, "D: with the full ring put away")
    local sr, sg = T[6].arc.cd.__swipe[1], T[6].arc.cd.__swipe[2]
    CHECK(sr > sg, "D: an enemy's ring is red")
    EQ(T[6].arc.cd.__reverse, false, "D: unwinding, not filling")
    CHECK(T[6].arc.cd.__cd.start >= 0, "D: started after the clock's zero")
    -- This machine has been up for more than a day, so the cooldown is the
    -- longest the window ever asks for: a day, and not the uptime
    EQ(T[6].arc.cd.__cd.duration, 86400, "D: on a machine up for days the frozen cooldown is one day long")
    -- A frozen arc is left alone while nothing changes...
    local stamp = T[6].arc.cd.__cd
    Paint()
    CHECK(T[6].arc.cd.__cd == stamp, "D: an unchanged ring is not set again")
    -- ...and re-set before it could visibly creep: a thousandth of a turn,
    -- which on a day-long cooldown is 86 seconds and not the 5 it is on a
    -- machine that booted a quarter of an hour ago
    now = now + T[6].arc.span * 0.001 - 1
    Paint()
    CHECK(T[6].arc.cd.__cd == stamp, "D: a ring that has not yet crept a thousandth of a turn is left alone")
    now = now + 2
    Paint()
    CHECK(T[6].arc.cd.__cd ~= stamp, "D: a ring left long enough to creep is set again")
    NEAR(RingShare(T[6]), 590 / 900, "D: to the same share", 0.0011)
    -- The other branch: a machine a quarter of an hour from boot cannot be
    -- handed a day-long cooldown, which would have started before zero. The
    -- arc is set by hand at that uptime (and at another share, so that it
    -- is set at all), and the next frame paints it back.
    Run("young ring", G.ArcSet, T[6].arc, 0.25, T[6].health, 1000)
    EQ(T[6].arc.cd.__cd.duration, 1000, "D: on a machine up for under a day the cooldown is as long as the uptime")
    EQ(T[6].arc.cd.__cd.start, 250, "D: and starts after the clock's zero, a quarter of the way to now")
    Paint()
    NEAR(RingShare(T[6]), 590 / 900, "D: (the ring is put back on the real clock)", 0.0011)
    EQ(T[6].arc.cd.__cd.duration, 86400, "D: (and on the day-long cooldown)")
    match:Damage(priest, rogue, mage.spec.basic, 440, false, false)
    Paint()
    NEAR(RingShare(T[1]), 660 / 1100, "D: one of yours: 660 of 1100", 0.0011)
    CHECK(T[1].arc.cd.__swipe[2] > T[1].arc.cd.__swipe[1], "D: and its ring is green")

    -- The shield rim: there while there is absorb, gone with the last of it
    EQ(T[1].rim.__shown, false, "D: no rim on an unshielded token")
    match:Use(priest, AbilityWith(priest, "shielded"), rogue)
    CHECK(rogue.absorb > 0, "D: (setup) the rogue is shielded", rogue.absorb)
    Paint()
    EQ(T[1].rim.__shown, true, "D: a shield shows its rim")
    local soaked = rogue.absorb - 1
    match:Damage(warrior, rogue, warrior.spec.basic, soaked, false, false)
    Paint()
    EQ(T[1].rim.__shown, true, "D: one point of shield is still a shield")
    match:Damage(warrior, rogue, warrior.spec.basic, 1, false, false)
    EQ(rogue.absorb, 0, "D: (setup) the shield is spent")
    EQ(rogue.health, 660, "D: (setup) and soaked all of it")
    Paint()
    EQ(T[1].rim.__shown, false, "D: the rim goes with the last of the shield")

    -- Pain Suppression glows
    EQ(T[1].glow.__shown, false, "D: no glow on an unguarded token")
    match:Use(priest, AbilityWith(priest, "suppressed"), rogue)
    Paint()
    EQ(T[1].glow.__shown, true, "D: Pain Suppression glows")
    EQ(T[1].glow.__blend, "ADD", "D: additively")

    -- Frost on the lower shoulder of the rooted
    local nova, rootEffect = AbilityWith(mage, "rooted")
    E.Effects.ROOT(match, mage, warrior, nova, rootEffect)
    Paint()
    EQ(T[4].frost.__shown, true, "D: a rooted token wears the frost")
    EQ(T[4].frost.__texture, nova.icon, "D: the icon of what rooted it")
    EQ(T[4].badge.__shown, true, "D: and keeps its face")
    -- Where it is pinned, in the face's own box (its bottom-left corner is
    -- 0,0): over the top of the name's line, which hangs from the bottom
    -- edge, and under the kill mark on the shoulder above. It used to sit
    -- across the name.
    local CORNER = {
        BOTTOMLEFT = { 0, 0 }, BOTTOM = { L.token / 2, 0 }, TOPLEFT = { 0, L.token }, TOPRIGHT = { L.token, L.token },
    }
    local function Pinned(widget, point)
        local p = widget.__points[point]
        return CORNER[p.relPoint][1] + p.x, CORNER[p.relPoint][2] + p.y
    end
    local frostX, frostY = Pinned(T[4].frost, "CENTER")
    local _, nameTop = Pinned(T[4].name, "TOP")
    local _, markY = Pinned(T[4].mark, "CENTER")
    CHECK(frostY - T[4].frost.__h / 2 >= nameTop, "D: the frost is clear of the name under the token", frostY - T[4].frost.__h / 2)
    CHECK(frostY + T[4].frost.__h / 2 <= markY - T[4].mark.__h / 2, "D: and of the kill mark above it")
    CHECK(frostX < L.token / 2 and frostX + T[4].frost.__w / 2 > 0, "D: on the token's left shoulder", frostX)

    -- A stun: dimmed, with the spell pinned on its shoulder
    local cheap, stunEffect = AbilityWith(rogue, "stunned")
    E.Effects.DISABLE(match, rogue, warrior, cheap, stunEffect)
    EQ(warrior.disabled, "stunned", "D: (setup) the warrior is stunned")
    Paint()
    EQ(T[4].pin.__shown, true, "D: a stun pins a marker")
    EQ(T[4].pin.__texture, cheap.icon, "D: the icon of what stunned it")
    local r, g, b = Colour(T[4].badge)
    CHECK(r < 0.5 and r == g and g == b, "D: and dims the token", r)
    EQ(T[4].swap.__shown, false, "D: without swapping its face")

    -- A cyclone: the swirl for a face, thinned
    local cyclone, cycloneEffect = AbilityWith(druid, "cycloned")
    E.Effects.DISABLE(match, druid, mage, cyclone, cycloneEffect)
    Paint()
    EQ(T[2].swap.__texture, cyclone.icon, "D: a cycloned token wears the swirl")
    EQ(T[2].swap.__shown, true, "D: in place of its face")
    NEAR(T[2].__alpha, 0.7, "D: and is thinned")

    -- A fear: tinted, face kept
    local fear, fearEffect = AbilityWith(warlock, "feared")
    E.Effects.DISABLE(match, warlock, priest, fear, fearEffect)
    Paint()
    r, g, b = Colour(T[3].badge)
    CHECK(b > r and r > g, "D: a feared token is tinted violet", r .. "," .. g .. "," .. b)
    EQ(T[3].badge.__shown, true, "D: and keeps its face")
    EQ(T[3].pin.__shown, false, "D: with no pin")

    -- The kill marks
    match.focus.A, match.focus.B = warlock, rogue
    Paint()
    EQ(T[5].mark.__shown, true, "D: the enemy your team is killing is marked")
    CHECK(T[5].mark.__coords[1] == 0.75 and T[5].mark.__coords[3] == 0.25, "D: with the skull")
    EQ(T[1].mark.__shown, true, "D: the one of yours they are killing is marked")
    CHECK(T[1].mark.__coords[1] == 0.5 and T[1].mark.__coords[3] == 0.25, "D: with the cross")
    EQ(T[4].mark.__shown, false, "D: and nobody else is")

    -- The dead: grey, ringless, unmarked, and still on the floor
    match:Damage(mage, warlock, mage.spec.basic, 99999, false, false)
    EQ(warlock.alive, false, "D: (setup) the warlock is dead")
    Paint()
    EQ(T[5].badge.__desat, true, "D: a dead token is desaturated")
    r, g, b = Colour(T[5].badge)
    CHECK(r == 0.5 and g == 0.5 and b == 0.5, "D: and dimmed to half", r)
    EQ(RingShare(T[5]), 0, "D: has no health ring")
    EQ(T[5].arc.track.__shown, false, "D: nor the track it ran in")
    EQ(T[5].mark.__shown, false, "D: and is nobody's target")
    EQ(T[1].badge.__desat, false, "D: the living are not")
    local scaleAlive = T[5].__scale
    -- Where the rogue has walked to by now depends on whom the dice opened
    -- it on, and the Shadowstep below needs it far from the druid whatever
    -- they said. So it is stood in the near left corner, by hand, while the
    -- match is held still and its token has a second to walk over.
    rogue.x, rogue.y = 10, 40
    match.over = true          -- hold the match still while the body settles
    Advance(1.0)
    match.over = false
    NEAR(T[5].__alpha, 0.45, "D: a dead token fades")
    CHECK(T[5].__scale < scaleAlive, "D: and shrinks as it sinks")
    EQ(T[5].__shown, true, "D: but stays on the floor")
    CHECK(OnFloor(Foot(T[5])), "D: where it fell")
    EQ(T[5].rank, 1, "D: under everybody still standing")
    EQ(#caughtErrors, 0, "D: no error painting any state", caughtErrors[1])

    -- A teleport is drawn as one: the token is THERE on the next frame, not
    -- gliding across the floor after its unit. (Smoothing alone would have
    -- left it a quarter of the way back, some ten units short.)
    local step
    for _, ability in ipairs(rogue.abilities) do
        for _, effect in ipairs(ability.effects) do
            if effect.mode == "TELEPORT" then step = ability end
        end
    end
    local gap = math.sqrt((rogue.x - druid.x) ^ 2 + (rogue.y - druid.y) ^ 2)
    CHECK(gap > 40, "D: (setup) the rogue is the width of the floor from the druid", gap)
    match:Use(rogue, step, druid)
    Frame(0.1)
    local fx, fy = Foot(T[1])
    local ux, uy = G.Project(rogue.x, rogue.y)
    local short = math.sqrt((fx - ux) ^ 2 + (fy - uy) ^ 2)
    CHECK(short < 20, "D: a Shadowstep lands its token at once", short)
    EQ(T[1].popText.__text, step.name, "D: and is called out by name")
    EQ(T[1].popIcon.__texture, step.icon, "D: and icon")
    EQ(T[1].popIcon.__shown, true, "D: above the token")

    -- That frame was the first real tick since this section began, so every
    -- hit forced above was only now heard and thrown as a number. A hit a
    -- shield soaked whole is ONE number -- what the shield took, small and
    -- grey -- and not a pale-red 0 beside it.
    local zero, grey
    for _, fs in ipairs(Showing(G.numbers)) do
        if fs.__text == "0" then zero = fs end
        if fs.__text == tostring(soaked) then grey = fs end
    end
    CHECK(zero == nil, "D: a hit soaked whole throws no 0")
    CHECK(grey ~= nil, "D: it throws what the shield took", soaked)
    if grey then
        local c = G.COLOURS.absorb
        CHECK(grey.__color[1] == c[1] and grey.__color[2] == c[2] and grey.__color[3] == c[3], "D: in the absorb grey")
        EQ(grey.__fontSize, 10, "D: and small")
    end

    -- Let what is left of it play out, and look at the next deal: every
    -- cached answer the painter kept has to be re-asked of the new units
    match.focus.A, match.focus.B = nil, nil
    local before = Book()
    local ended = PlayOut()
    CHECK(ended == match, "D: the tampered match still ends")
    CheckBell("D", match, before)
    Advance(3.2)
    CHECK(S.match ~= match, "D: and the next is dealt")
    for id, token in ipairs(G.tokens) do
        CHECK(token.badge.__shown and not token.swap.__shown and token.badge.__desat == false
              and token.__alpha == 1 and not token.pin.__shown and not token.frost.__shown
              and not token.glow.__shown and not token.rim.__shown and not token.order.__shown
              and token.arc.track.__shown,
              "D: token " .. id .. " starts the next match clean")
        local c = RAID_CLASS_COLORS[S.match.units[id].spec.class]
        NEAR(token.disc.__color[1], c.r, "D: token " .. id .. " is its class colour again")
    end

    -- A token is whatever unit it is dealt. Stage 1 never deals anything but
    -- the same six, so this swaps the two teams over to prove the window
    -- does not know that -- which is what a draft will lean on.
    local teamA, teamB = DATA.TEAMS.A, DATA.TEAMS.B
    DATA.TEAMS.A, DATA.TEAMS.B = teamB, teamA
    Run("deal", G.Deal)
    local names = {}
    for id, token in ipairs(G.tokens) do
        local unit = S.match.units[id]
        names[id] = token.name.__text
        local coords, c = CLASS_ICON_TCOORDS[unit.spec.class], RAID_CLASS_COLORS[unit.spec.class]
        CHECK(token.badge.__coords[1] == coords[1] and token.badge.__coords[3] == coords[3],
              "D: dealt a different unit, token " .. id .. " wears its badge")
        CHECK(token.disc.__color[1] == c.r and token.disc.__color[2] == c.g and token.disc.__color[3] == c.b,
              "D: and its class colour")
        EQ(token.arc.full.__color[2] > token.arc.full.__color[1], id <= 3, "D: but token " .. id .. " keeps its side's ring")
    end
    EQ(table.concat(names, " "), "Arms Affliction Restoration Subtlety Frost Discipline", "D: and its name")
    -- And so is a button: the bar is now the other three's big spells
    for slot, button in ipairs(G.buttons) do
        local unit = S.match.units[slot]
        EQ(button.icon.__texture, unit.big.icon, "D: dealt a different unit, button " .. slot .. " wears its big spell")
        EQ(button.name.__text, names[slot], "D: and its name")
        Frame(0)
        local c = RAID_CLASS_COLORS[unit.spec.class]
        NEAR(button.rim.__color[2] / button.rim.__color[1], c.g / c.r, "D: and its class colour")
    end
    MouseTo(Middle(G.buttons[1]))
    EQ(tooltip.title, "Mortal Strike", "D: and its tooltip is the new spell's")
    MouseTo(nil)
    DATA.TEAMS.A, DATA.TEAMS.B = teamA, teamB

    -- A class the client's two tables have never heard of still gets a
    -- token: a question mark for a badge, on a white disc
    local coords, classColour = CLASS_ICON_TCOORDS.DRUID, RAID_CLASS_COLORS.DRUID
    CLASS_ICON_TCOORDS.DRUID, RAID_CLASS_COLORS.DRUID = nil, nil
    Run("deal", G.Deal)
    EQ(G.tokens[6].badge.__texture, G.ART.unknown, "D: a class with no badge wears the question mark")
    CHECK(G.tokens[6].disc.__color[1] == 1 and G.tokens[6].disc.__color[2] == 1 and G.tokens[6].disc.__color[3] == 1,
          "D: and a class with no colour is white")
    EQ(G.tokens[5].badge.__texture, G.ART.classes, "D: the classes it does know keep their badge")
    CLASS_ICON_TCOORDS.DRUID, RAID_CLASS_COLORS.DRUID = coords, classColour

    Run("deal", G.Deal)
    EQ(G.tokens[1].name.__text, "Subtlety", "D: (the teams are put back)")
    EQ(G.tokens[6].badge.__texture, G.ART.classes, "D: (and the druid has its badge again)")
    EQ(#caughtErrors, 0, "D: no error dealing any of them", caughtErrors[1])
end)

-- === D, continued: what flies =================================================
-- The states above are read off the units; what follows is what the match
-- only SAYS -- a press, a hit, a heal -- and the window has to animate. One
-- fresh match in which nobody presses anything by itself (every unit's next
-- beat is put past the bell) and nobody walks (every unit is rooted where it
-- starts), so the only things in the air are the ones pressed here, and
-- where each ought to be on a given frame is arithmetic.
Section("D, what flies", function()
    local match = S.match
    local rogue, mage, priest, warrior, warlock, druid = unpack(match.units)
    local T = G.tokens
    local nova, rootEffect = AbilityWith(mage, "rooted")
    OpenGates()
    for _, unit in ipairs(match.units) do
        unit.wait = math.huge
        E.Effects.ROOT(match, mage, unit, nova, rootEffect)
    end
    -- Use leaves the presser a beat away from pressing again by itself
    local function Press(unit, ability, target)
        match:Use(unit, ability, target)
        unit.wait = math.huge
    end
    local function Spell(unit, name)
        for _, ability in ipairs(unit.abilities) do
            if ability.name == name then return ability end
        end
        error("no " .. name .. " on " .. unit.spec.name)
    end

    -- How each of the eighteen rows travels, written out by hand rather
    -- than worked out the way the window works it out: what a melee does is
    -- delivered by a bump, what a caster does is thrown, the nova is a ring
    -- on the floor, and a unit that moves is its own delivery.
    local DELIVERY = {
        ["Hemorrhage"] = "BUMP", ["Cheap Shot"] = "BUMP", ["Shadowstep"] = "SELF",
        ["Frostbolt"] = "SHOT", ["Polymorph"] = "SHOT", ["Frost Nova"] = "BURST",
        ["Flash Heal"] = "SHOT", ["Power Word: Shield"] = "SHOT", ["Pain Suppression"] = "SHOT",
        ["Weapon Swing"] = "BUMP", ["Charge"] = "SELF", ["Mortal Strike"] = "BUMP",
        ["Shadow Bolt"] = "SHOT", ["Corruption"] = "SHOT", ["Fear"] = "SHOT",
        ["Rejuvenation"] = "SHOT", ["Lifebloom"] = "SHOT", ["Cyclone"] = "SHOT",
    }
    local rows = 0
    for _, unit in ipairs(match.units) do
        for _, ability in ipairs(unit.abilities) do
            rows = rows + 1
            EQ(G.Delivery(ability), DELIVERY[ability.name], "D: " .. ability.name .. " is delivered the way it should be")
        end
    end
    EQ(rows, 18, "D: (all eighteen rows were asked)")

    -- One tick with four presses in it: the mage throws a Frostbolt at the
    -- warrior, the warlock a Shadow Bolt at the rogue, the warrior lands a
    -- Mortal Strike on the rogue, and the priest heals herself.
    EQ(#Showing(G.numbers), 0, "D: (setup) no number is in the air")
    EQ(#Showing(G.shots), 0, "D: (setup) and no projectile")
    local fromX, fromY = Centre(T[2])
    local frostbolt, bolt = mage.spec.basic, warlock.spec.basic
    local strike = Spell(warrior, "Mortal Strike")
    Press(mage, frostbolt, warrior)
    Press(warlock, bolt, rogue)
    Press(warrior, strike, rogue)
    Press(priest, priest.spec.basic, priest)
    Frame(0.1)

    -- Projectiles: two, each its own widget wearing its own spell, and
    -- nothing thrown by a unit at itself
    local shots = Showing(G.shots)
    EQ(#shots, 2, "D: two thrown spells are two projectiles, and a spell cast on oneself is none")
    local flying
    for _, shot in ipairs(shots) do
        if shot.__texture == frostbolt.icon then flying = shot end
    end
    CHECK(flying ~= nil, "D: the Frostbolt in the air is the Frostbolt's icon")
    CHECK(shots[1] and shots[2] and shots[1].__texture ~= shots[2].__texture, "D: and the Shadow Bolt is another")
    -- A tenth of a second into a flight of L.flight, on a straight line from
    -- where the mage stood to where the warrior is now, lifted in an arc
    local function Along(elapsed, label)
        if not flying then return end
        local p = elapsed / L.flight
        local toX, toY = Centre(T[4])
        local at = flying.__points.CENTER
        NEAR(at.x, fromX + (toX - fromX) * p, "D: " .. label .. " (across)", 0.01)
        NEAR(at.y, fromY + (toY - fromY) * p + math.sin(math.pi * p) * 8, "D: " .. label .. " (up)", 0.01)
    end
    Along(0.1, "a projectile leaves its caster for its target")
    CHECK(flying and math.abs(flying.__points.CENTER.x - fromX) > 30, "D: (which is a real distance)")

    -- The bump: the warrior is carried off its feet TOWARD the rogue, who
    -- stands to its left, and back again
    local warriorX, warriorY = Centre(T[4])
    local footX, footY = Foot(T[4])
    CHECK(warriorX - footX < -5, "D: a melee hit bumps its token toward the target", warriorX - footX)
    NEAR(warriorY - footY, L.token / 2 * T[4].__scale, "D: along the line between them, which here is level", 0.5)
    CHECK(math.abs(Centre(T[2]) - Foot(T[2])) < 0.01, "D: a caster throwing does not bump")

    -- The call-out: the spell's icon and name, riding above the token
    EQ(T[4].popIcon.__shown, true, "D: a signature spell is called out")
    EQ(T[4].popText.__text, "Mortal Strike", "D: by name")
    EQ(T[2].popIcon.__shown, false, "D: and a filler is not")
    local pop = T[4].popIcon.__points.CENTER
    local top = warriorY + L.token / 2 * T[4].__scale
    NEAR(pop.x, warriorX, "D: the call-out is over its own token", 0.01)
    CHECK(pop.y - T[4].popIcon.__h / 2 > top, "D: above the token's top edge", pop.y - top)
    EQ(T[4].popIcon.__alpha, 1, "D: at full strength while it is new")

    -- The slow the Frostbolt left is the one state drawn on the FLOOR: the
    -- shadow under a chilled token is blue
    local shade = T[4].shadow.__color
    CHECK(shade[3] > 0.9 and shade[1] < 0.5 and shade[4] > 0.5, "D: a slowed token stands on a blue shadow", shade[3])
    shade = T[1].shadow.__color
    CHECK(shade[1] == 0 and shade[2] == 0 and shade[3] == 0, "D: and nobody else does")

    -- Numbers: one on the warrior and two on the rogue. Each is its own
    -- font string; the two on one token are side by side in two lanes; and
    -- each starts ON its token, under the middle of it.
    local numbers = Showing(G.numbers)
    EQ(#numbers, 3, "D: three hits are three numbers")
    local rogueX, rogueY = Centre(T[1])
    local onWarrior, onRogue = nil, {}
    for _, fs in ipairs(numbers) do
        if math.abs(fs.__points.CENTER.x - rogueX) < 30 then onRogue[#onRogue + 1] = fs else onWarrior = fs end
    end
    local rise = L.numberRise * (1 - (1 - 0.1 / L.numberLife) ^ 2)
    EQ(#onRogue, 2, "D: two of them on the rogue")
    if #onRogue == 2 then
        local gap = math.abs(onRogue[1].__points.CENTER.x - onRogue[2].__points.CENTER.x)
        CHECK(gap > 13.9, "D: side by side, a lane apart", gap)
        NEAR(onRogue[1].__points.CENTER.y, onRogue[2].__points.CENTER.y, "D: at one height")
        NEAR(onRogue[1].__points.CENTER.y, rogueY - 8 + rise, "D: which is on the token, under its middle", 0.01)
    end
    CHECK(onWarrior ~= nil, "D: and one on the warrior")

    -- The life of that one, frame by frame: it rises all the way, it fades
    -- at the end, and it never climbs into the line the spell's name is
    -- written on -- the call-out over the warrior is up the whole time
    local rises, fell, faded, crossed, frames = 0, 0, false, 0, 0
    if onWarrior then
        local last = onWarrior.__points.CENTER.y
        EQ(onWarrior.__alpha, 1, "D: a number is solid when it is thrown")
        while onWarrior.__shown and frames < 100 do
            Frame(0.02)
            frames = frames + 1
            if onWarrior.__shown then
                local y = onWarrior.__points.CENTER.y
                if y > last then rises = rises + 1 else fell = fell + 1 end
                last = y
                if onWarrior.__alpha < 1 then faded = true end
                local icon = T[4].popIcon
                local nameBottom = icon.__points.CENTER.y - icon.__h / 2 - 1 - 10
                if not icon.__shown or y >= nameBottom then crossed = crossed + 1 end
            end
        end
    end
    CHECK(rises > 30 and fell == 0, "D: a number rises on every frame of its life", rises .. " up, " .. fell .. " not")
    EQ(faded, true, "D: and fades before it goes")
    NEAR(frames * 0.02, L.numberLife - 0.1, "D: which is when its time is up", 0.03)
    EQ(crossed, 0, "D: and it never reaches the line the spell's name is on")
    EQ(#Showing(G.shots), 0, "D: the projectiles have landed and gone")
    CHECK(math.abs(Centre(T[4]) - Foot(T[4])) < 0.01, "D: and the warrior is back on its feet")

    -- The call-out fades over its last quarter and then goes
    Advance(0.2, 0.02)
    EQ(T[4].popIcon.__shown, true, "D: the call-out is still up after a second")
    CHECK((T[4].popIcon.__alpha or 1) < 1, "D: fading", T[4].popIcon.__alpha)
    CHECK((T[4].popText.__alpha or 1) < 1, "D: icon and name together", T[4].popText.__alpha)
    Advance(0.2, 0.02)
    EQ(T[4].popIcon.__shown, false, "D: and gone when its time is up")
    EQ(T[4].popText.__shown, false, "D: name and all")

    -- The slow comes off, and the shadow with it
    for _, aura in ipairs(warrior.auras) do
        if aura.state == "slowed" then
            match:Fade(warrior, aura, "EXPIRED")
            break
        end
    end
    EQ(warrior:Is("slowed"), false, "D: (setup) the slow has faded")
    Frame(0)
    shade = T[4].shadow.__color
    CHECK(shade[1] == 0 and shade[3] == 0 and shade[4] < 0.5, "D: a token no longer slowed gets its own shadow back", shade[3])

    -- The area ring: from the caster's feet out to the spell's range
    Press(mage, nova, warrior)
    Frame(0.1)
    EQ(G.burst.__shown, true, "D: an area spell spreads a ring")
    local mageFootX, mageFootY = Foot(T[2])
    NEAR(G.burst.__points.CENTER.x, mageFootX, "D: from the caster's feet (across)", 0.01)
    NEAR(G.burst.__points.CENTER.y, mageFootY, "D: from the caster's feet (up)", 0.01)
    -- The art's band ends at 0.485 of its width, and twelve units of floor
    -- is 12 / 100 of twice walkFront across
    local reach = nova.range / (ARENA.maxX - ARENA.minX) * 2 * L.walkFront
    NEAR(G.burst.__w * 0.485, reach * 0.1 / L.burstTime, "D: a tenth of a second out, it has spread that share of its range", 0.01)
    CHECK(G.burst.__h < G.burst.__w, "D: and lies flat on the floor", G.burst.__h)
    local width, alpha, widest = G.burst.__w, G.burst.__alpha, G.burst.__w
    Frame(0.02)
    CHECK(G.burst.__w > width, "D: the ring grows", G.burst.__w)
    CHECK(G.burst.__alpha < alpha, "D: and thins as it goes", G.burst.__alpha)
    for _ = 1, 30 do
        if not G.burst.__shown then break end
        widest = G.burst.__w
        Frame(0.02)
    end
    EQ(G.burst.__shown, false, "D: and is gone")
    CHECK(widest * 0.485 > 0.85 * reach and widest * 0.485 <= reach, "D: having reached the spell's range and no further", widest * 0.485)

    -- Four numbers on one token in one tick. Three lanes hold three; the
    -- fourth comes back round to the first one's lane, at the same instant,
    -- and used to be written exactly over it. It is thrown a line higher.
    Advance(1.0, 0.02)
    EQ(#Showing(G.numbers), 0, "D: (setup) the air is clear again")
    local function Thrown(text)
        local found = {}
        for _, fs in ipairs(Showing(G.numbers)) do
            if fs.__text == text then found[#found + 1] = fs.__points.CENTER end
        end
        table.sort(found, function(a, b)
            if a.x ~= b.x then return a.x < b.x end
            return a.y < b.y
        end)
        return found
    end
    for _ = 1, 4 do match:Damage(mage, druid, frostbolt, 11, false, false) end
    Frame(0.1)
    local four = Thrown("11")
    EQ(#four, 4, "D: four hits in one tick are four numbers")
    local lanes, stacked = 0, nil
    for index = 1, #four do
        if index == 1 or four[index].x - four[index - 1].x > 13.9 then
            lanes = lanes + 1
        elseif math.abs(four[index].x - four[index - 1].x) < 0.01 then
            stacked = four[index].y - four[index - 1].y
        end
    end
    EQ(lanes, 3, "D: in three lanes")
    CHECK(stacked and stacked >= 10, "D: and the fourth is a line above the first, not on it", stacked)
    -- Two ticks later the lanes are their own again: the numbers in them
    -- have risen out of the way by themselves, and a lift now would put the
    -- new ones ON them
    Frame(0.1)
    local druidX, druidY = Centre(T[6])
    for _ = 1, 3 do match:Damage(mage, druid, frostbolt, 12, false, false) end
    Frame(0.1)
    local three = Thrown("12")
    EQ(#three, 3, "D: three more, two ticks on")
    for index, at in ipairs(three) do
        NEAR(at.y, druidY - 8 + rise, "D: later number " .. index .. " starts where a first one would", 0.01)
    end
    CHECK(math.abs(Centre(T[6]) - druidX) < 0.01, "D: (the druid has not moved)")

    -- A dash is the mirror of the Shadowstep above: the unit is across the
    -- floor at once and its token RUNS there. A frame later it is still a
    -- quarter of the way back; half a second later it has arrived.
    local charge = Spell(warrior, "Charge")
    local startX, startY = warrior.x, warrior.y
    Press(warrior, charge, mage)
    local ran = math.sqrt((warrior.x - startX) ^ 2 + (warrior.y - startY) ^ 2)
    CHECK(ran > 30, "D: (setup) the Charge crossed the floor", ran)
    Frame(0.1)
    local function Behind()
        local fx, fy = Foot(T[4])
        local ux, uy = G.Project(warrior.x, warrior.y)
        return math.sqrt((fx - ux) ^ 2 + (fy - uy) ^ 2)
    end
    CHECK(Behind() > 20, "D: a Charge is run: a frame later the token is still on its way", Behind())
    Advance(0.5)
    CHECK(Behind() < 12, "D: and has arrived half a second later", Behind())
    EQ(#caughtErrors, 0, "D: no error in anything that flew", caughtErrors[1])

    -- A draw, which no seed in this run will deal by itself: about one
    -- match in a thousand is one. Everybody is made whole, and the clock is
    -- put one tick short of the cap, where the bell goes to whoever holds
    -- the larger share of health -- and level is nobody.
    EQ(G.healing.__shown, false, "D: (nothing is said about healing a few seconds into a match)")
    for _, unit in ipairs(match.units) do
        unit.health, unit.wait = unit.healthMax, math.huge
    end
    match.tick = math.floor(DATA.RULES.cap / TICK + 0.5) - 1
    local before = Book()
    Frame(0.1)
    EQ(match.winner, "DRAW", "D: (setup) the match was drawn")
    CheckBell("D draw", match, before)
    CHECK(G.record.__text:find(string.format("   %d drawn$", before.Draws + 1)) ~= nil, "D: and the header gains a drawn column",
          G.record.__text)
    EQ(G.healing.__text, "No healing", "D: at the cap the header says there is no healing left")
    Advance(3.2)
    CHECK(S.match ~= match, "D: the next match is dealt after a draw too")
    EQ(G.bannerBand.__shown, false, "D: and the band comes down")
    EQ(G.healing.__shown, false, "D: and the new match has all its healing")
    EQ(#caughtErrors, 0, "D: no error in a drawn match", caughtErrors[1])
end)

-- === D, continued: the hand ===================================================
-- The player's two verbs, made the way a player makes them: a click at a
-- point of the window, taken by whatever frame the client would give it to.
-- One match dealt for the purpose, in which nobody presses anything by
-- itself once the gates are open, so that what each button says is the
-- doing of the lines here and of nothing else.
Section("D, the hand", function()
    local db = CommanderGladiatorDB
    local T, bar = G.tokens, G.buttons
    -- Everything the window hears pressed, and the first hit side A lands
    local heard, opening = {}, nil
    local onAbility, onDamage = G.On.ABILITY, G.On.DAMAGE
    G.On.ABILITY = function(event)
        heard[#heard + 1] = event
        return onAbility(event)
    end
    G.On.DAMAGE = function(event)
        if event.source <= 3 and event.target > 3 then opening = opening or event.target end
        return onDamage(event)
    end
    local function Paint() Frame(0) end
    local function Ordered()
        local ids = {}
        for id, token in ipairs(T) do
            if token.order.__shown then ids[#ids + 1] = id end
        end
        return table.concat(ids, ",")
    end
    local function HintUp() return G.hints[1].__shown and G.hints[2].__shown end

    CHECK(db.Pinned == false and db.Tapped == false, "D: (setup) nobody has pinned or tapped yet")
    CHECK(HintUp(), "D: the hint is up for somebody who has done neither")

    Run("deal", G.Deal)
    local match = S.match
    local rogue, mage, priest, warrior, warlock, druid = unpack(match.units)
    EQ(G.count.__shown, true, "D: (setup) a fresh match, at its gates")

    -- The pointer: over a living enemy it is over that token and the ring
    -- is drawn; one of your own is not there to be pointed at, and what is
    -- under the pointer then is the window
    EQ(MouseTo(Middle(T[5])), T[5], "D: the pointer over a living enemy is over its token")
    EQ(Highlighted(T[5].hover), true, "D: and the ring is drawn round it")
    EQ(T[5].hover.__blend, "ADD", "D: as light")
    CHECK(T[5].hover.__w > L.token, "D: wider than the token it is round", T[5].hover.__w)
    EQ(Highlighted(T[6].hover), false, "D: and round no other")
    EQ(MouseTo(Middle(T[2])), window, "D: over one of your own, the pointer is over the window behind it")
    EQ(Highlighted(T[2].hover), false, "D: and no ring is drawn")

    -- A pin, made at the gates: on the click, before the first tick
    EQ(ClickOn(T[5]), T[5], "D: a click on an enemy lands on its token")
    CHECK(match.pin.A == warlock, "D: and pins it")
    EQ(match.tick, 0, "D: before the first tick")
    Paint()
    EQ(Ordered(), "5", "D: the pinned enemy wears the gold disc")
    EQ(T[5].mark.__shown, true, "D: with the skull on it")
    CHECK(T[5].mark.__coords[1] == 0.75 and T[5].mark.__coords[3] == 0.25, "D: (the skull, not the cross)")
    local order, skull = T[5].order, T[5].mark
    CHECK(order.__layer == skull.__layer and order.__sublevel < skull.__sublevel, "D: the disc is behind the skull")
    CHECK(order.__points.CENTER and order.__points.CENTER.rel == skull, "D: centred on it")
    CHECK(order.__w > skull.__w and order.__w < L.token, "D: and shows round its edge", order.__w)
    local r, g, b = Colour(order)
    CHECK(r > 0.9 and g > 0.7 and b < 0.5, "D: in gold", r .. "," .. g .. "," .. b)
    EQ(db.Pinned, true, "D: the first pin is remembered")
    CHECK(HintUp(), "D: and the hint survives the first of its two verbs")

    -- Another enemy: the pin moves. The same one again: it is let go, and
    -- the plain skull stays on whoever the team is killing.
    ClickOn(T[6])
    CHECK(match.pin.A == druid, "D: a click on another enemy moves the pin")
    Paint()
    EQ(Ordered(), "6", "D: and the gold disc with it")
    EQ(T[5].mark.__shown, false, "D: the enemy it left is nobody's target")
    ClickOn(T[6])
    EQ(match.pin.A, nil, "D: a click on the pinned enemy lets the pin go")
    Paint()
    EQ(Ordered(), "", "D: and the gold disc goes")
    EQ(T[6].mark.__shown, true, "D: leaving the plain skull on the enemy the team is still killing")
    CHECK(ClickOn(T[1]) ~= T[1], "D: a click on one of your own does not land on it")
    EQ(match.pin.A, nil, "D: and pins nothing")

    -- The buttons at the gates: they show, and they do not fire
    EQ(match:Lit(mage), true, "D: (setup) the engine would fire Polymorph at the gates")
    EQ(Says(bar[2]), "DIM", "D: but its button does not glow while they are shut")
    local homeX, homeY = Anchor(bar[2], "CENTER")
    EQ(ClickOn(bar[2]), bar[2], "D: a click on it lands on it")
    EQ(mage.ready[mage.big.key], nil, "D: and fires nothing")
    EQ(#heard, 0, "D: so nothing is heard")
    EQ(db.Tapped, false, "D: and it does not count as a tap")
    Frame(0.05)
    CHECK(math.abs(Anchor(bar[2], "CENTER") - homeX) > 0.5, "D: the button shakes its head", Anchor(bar[2], "CENTER") - homeX)
    CHECK(math.abs(Anchor(bar[2], "CENTER") - homeX) <= L.shakeReach, "D: by a few pixels")
    EQ(select(2, Anchor(bar[2], "CENTER")), homeY, "D: from side to side")
    EQ((Anchor(bar[1], "CENTER")), homeX - L.buttonGap, "D: and its neighbour does not")
    Advance(0.4)
    EQ((Anchor(bar[2], "CENTER")), homeX, "D: and is back exactly where it was")
    EQ(match.tick, 0, "D: (setup) the gates are still shut")

    -- Pin the druid for the opening, open the gates, and stop everybody
    -- pressing anything by themselves
    ClickOn(T[6])
    CHECK(match.focus.A == druid, "D: a pin at the gates is the team's kill target before the first tick")
    OpenGates()
    EQ(match.tick, 0, "D: (setup) the gates are open and no tick has been taken")
    for _, unit in ipairs(match.units) do unit.wait = math.huge end

    -- LIT: a halo of light, the icon and its rim at full strength
    EQ(Says(bar[2]), "LIT", "D: with the gates open, a spell that would fire glows")
    local halo = bar[2].halo
    EQ(halo.__blend, "ADD", "D: the halo is light")
    CHECK(halo.__w > bar[2].__w, "D: wider than the button", halo.__w)
    CHECK((halo.__alpha or 1) > 0.3, "D: and bright", halo.__alpha)
    r, g, b = Colour(halo)
    CHECK(r > 0.9 and g > 0.7 and b < 0.5, "D: in the pin's gold", r .. "," .. g .. "," .. b)
    r, g, b = Colour(bar[2].icon)
    CHECK(r == 1 and g == 1 and b == 1, "D: a glowing button's icon is at full strength", r)
    local c = RAID_CLASS_COLORS.MAGE
    r, g, b = Colour(bar[2].rim)
    CHECK(r == c.r and g == c.g and b == c.b, "D: and so is its rim", r)
    -- DIM: the same spell with nothing to fire at. The rogue is the width
    -- of the floor from the druid, and nobody is hurt.
    EQ(Says(bar[1]), "DIM", "D: Cheap Shot with the kill target out of reach is dim")
    EQ(Says(bar[3]), "DIM", "D: Pain Suppression with nobody hurt is dim")
    r, g, b = Colour(bar[1].icon)
    CHECK(r < 0.5 and r == g and g == b and not bar[1].icon.__desat, "D: a dim button's icon is darkened, not greyed", r)
    c = RAID_CLASS_COLORS.ROGUE
    CHECK(bar[1].rim.__color[1] < 0.5 * c.r, "D: and its rim with it", bar[1].rim.__color[1])

    -- The tooltips: the spell, whose it is, and whom it will land on
    local TIPS = {
        { "Cheap Shot", "Subtlety Rogue: lands on your kill target." },
        { "Polymorph", "Frost Mage: lands on the enemy healer if she is not your kill target, else on another enemy." },
        { "Pain Suppression", "Discipline Priest: lands on your most hurt ally, once under 50% health." },
    }
    for slot, tip in ipairs(TIPS) do
        EQ(MouseTo(Middle(bar[slot])), bar[slot], "D: the pointer over button " .. slot .. " is over it")
        CHECK(tooltip.shown and tooltip.owner == bar[slot], "D: and button " .. slot .. " shows a tooltip of its own")
        EQ(tooltip.title, tip[1], "D: button " .. slot .. "'s tooltip names the spell")
        EQ(#tooltip.lines, 1, "D: in one line under it")
        EQ(tooltip.lines[1] and tooltip.lines[1].text, tip[2], "D: which says whose it is and whom it lands on")
        EQ(tooltip.lines[1] and tooltip.lines[1].wrap, true, "D: wrapped, not run off the screen")
    end
    MouseTo(Middle(T[4]))
    EQ(tooltip.shown, false, "D: the tooltip goes when the pointer leaves")

    -- The tap. With the druid as kill target Polymorph's rule picks the
    -- warrior; the click fires it there and then, and the window hears it
    -- on the click and not on the next tick.
    EQ(ClickOn(bar[2]), bar[2], "D: a click on a glowing button lands on it")
    local event = heard[#heard]
    CHECK(#heard == 1 and event.hand == true and event.ability == mage.big and event.source == 2 and event.target == 4,
          "D: and fires its spell by hand on the rule's target, heard at once", #heard)
    EQ(warrior.disabled, "sheeped", "D: the warrior is a sheep")
    EQ(mage.ready[mage.big.key], match.tick + 140, "D: and the spell's cooldown has started")
    EQ(db.Tapped, true, "D: the first tap is remembered")
    CHECK(not G.hints[1].__shown and not G.hints[2].__shown, "D: and with both verbs done once the hint goes")
    Paint()
    EQ(T[2].popIcon.__shown, true, "D: the call-out pops over the mage")
    EQ(T[2].popText.__text, "Polymorph", "D: by name")
    local thrown = Showing(G.shots)
    CHECK(#thrown == 1 and thrown[1].__texture == mage.big.icon, "D: and the spell is in the air", #thrown)
    EQ(T[4].swap.__shown, true, "D: at a warrior who is already a sheep")

    -- SWEEP: the whole cooldown to run on the tick it was pressed, as the
    -- plain dark disc; then a wedge that is the engine's own count
    mage.wait = math.huge
    EQ(Says(bar[2]), "SWEEP", "D: a button just pressed is cooling down")
    EQ(SweepShare(bar[2]), 1, "D: with its whole cooldown to run")
    local full = bar[2].sweep.full
    CHECK(full.__shown and full.__color[1] == 0 and full.__color[4] > 0.4 and full.__color[4] < 0.9, "D: drawn as a dark disc the icon shows through")
    EQ(full.__w, bar[2].icon.__w, "D: the size of the icon")
    EQ(bar[2].halo.__shown, false, "D: and the halo is gone")
    Advance(4.0)
    EQ(match.tick, 40, "D: (setup) four seconds on")
    NEAR(SweepShare(bar[2]), 100 / 140, "D: four seconds into fourteen, ten fourteenths of the wedge are left", 0.0011)
    local cd = bar[2].sweep.cd
    EQ(cd.__swipeTexture, G.ART.disc, "D: the wedge is cut from a disc")
    CHECK(cd.__swipe[1] == 0 and cd.__swipe[4] > 0.4 and cd.__swipe[4] < 0.9, "D: dark, and the icon shows through it")
    EQ(cd.__reverse, false, "D: unwinding, not filling")
    EQ(cd.__mouse, false, "D: and it does not take the click meant for the button")
    EQ(cd.__w, bar[2].icon.__w, "D: it is the size of the icon")
    r = Colour(bar[2].icon)
    EQ(r, 1, "D: under it the icon is at full strength, so the part that is back shows")
    local stamp = cd.__cd
    Paint()
    CHECK(cd.__cd == stamp, "D: a wedge that has not changed is not set again")
    -- A click on it now fires nothing
    local back = mage.ready[mage.big.key]
    homeX = Anchor(bar[2], "CENTER")
    ClickOn(bar[2])
    CHECK(mage.ready[mage.big.key] == back and #heard == 1, "D: a click on a button that is cooling down fires nothing")
    Frame(0.05)
    CHECK(math.abs(Anchor(bar[2], "CENTER") - homeX) > 0.5, "D: and is told so")
    Advance(0.4)

    -- Lit and dim, driven through the engine. The rogue is put in front of
    -- the druid (and its token with it, by the teleport's own door): Cheap
    -- Shot has its target in reach and glows.
    G.Hear({ { kind = "MOVE", mode = "TELEPORT", source = 1, toX = druid.x, toY = druid.y + 1 } })
    rogue.x, rogue.y = druid.x, druid.y + 1
    Paint()
    EQ(Says(bar[1]), "LIT", "D: Cheap Shot glows once the kill target is in reach")
    -- The rogue's token now stands in front of the druid's and over the
    -- lower part of it. A click there is on both, the rogue's is the one in
    -- front -- and the druid's takes it, because the rogue's never does.
    local dx0, dy0, dx1, dy1 = Rect(T[6])
    local rx0, ry0, rx1, ry1 = Rect(T[1])
    local clickX, clickY = (dx0 + dx1) / 2, (dy0 + ry1) / 2
    CHECK(clickX > rx0 and clickX < rx1 and clickY > ry0 and clickY < ry1 and clickY > dy0 and clickY < dy1,
          "D: (setup) the rogue's token overlaps the druid's", clickY)
    CHECK(T[1].__level > T[6].__level, "D: (setup) and is drawn in front of it")
    EQ(ClickAt(clickX, clickY), T[6], "D: a click where your rogue stands on an enemy lands on the enemy")
    EQ(match.pin.A, nil, "D: (and, the druid being the pin, lets it go)")
    EQ(ClickAt(clickX, clickY), T[6], "D: and again")
    CHECK(match.pin.A == druid, "D: (which pins it once more)")
    -- A stunned gladiator's button is dim, and a click on it fires nothing
    local charge, stun = AbilityWith(warrior, "stunned")
    E.Effects.DISABLE(match, warrior, rogue, charge, stun)
    EQ(rogue.disabled, "stunned", "D: (setup) the rogue is stunned")
    Paint()
    EQ(Says(bar[1]), "DIM", "D: a stunned gladiator's button is dim")
    ClickOn(bar[1])
    EQ(rogue.ready[rogue.big.key], nil, "D: and a click on it fires nothing")
    match:Fade(rogue, G.Aura(rogue, "stunned"), "EXPIRED")
    Paint()
    EQ(Says(bar[1]), "LIT", "D: and glows again when the stun ends")
    -- Pain Suppression waits for somebody under half, and in reach: the
    -- rogue is hurt first with the priest the width of the floor away
    match:Damage(warrior, rogue, warrior.spec.basic, 600, false, false)
    CHECK(rogue.health / rogue.healthMax < 0.5, "D: (setup) the rogue is under half", rogue.health)
    Paint()
    EQ(Says(bar[3]), "DIM", "D: Pain Suppression with its ally out of reach is still dim")
    priest.x = rogue.x - 30
    Paint()
    EQ(Says(bar[3]), "LIT", "D: Pain Suppression glows when an ally is under half")
    ClickOn(bar[3])
    priest.wait = math.huge
    event = heard[#heard]
    CHECK(#heard == 2 and event.hand == true and event.ability == priest.big and event.target == 1,
          "D: and a click on it lands the spell on the rogue", #heard)
    Paint()
    EQ(T[1].glow.__shown, true, "D: who glows with it")
    EQ(Says(bar[3]), "SWEEP", "D: and the button starts its sweep")

    -- The soft pin. The druid is pinned; she is made a sheep; the team's
    -- next look takes somebody else. The order was taken all the same, and
    -- her token goes on saying so.
    EQ(Ordered(), "6", "D: (setup) the druid wears the pin")
    local poly, sheep = AbilityWith(mage, "sheeped")
    E.Effects.DISABLE(match, mage, druid, poly, sheep)
    match:KillTarget("A")
    CHECK(druid.disabled == "sheeped" and match.pin.A == druid and match.focus.A ~= druid,
          "D: (setup) the team has left its sheeped pin for somebody else")
    Paint()
    EQ(Ordered(), "6", "D: a pinned enemy that is a sheep still wears the gold disc")
    EQ(T[6].mark.__shown, true, "D: and the skull on it")
    local other = T[match.focus.A.id]
    CHECK(other.mark.__shown and not other.order.__shown, "D: while the enemy the team is on meanwhile wears the plain skull")

    -- DEAD: grey, no wedge, and a click does nothing
    EQ(Says(bar[2]), "SWEEP", "D: (setup) Polymorph is still cooling down")
    match:Damage(warrior, mage, warrior.spec.basic, 99999, false, false)
    Paint()
    EQ(Says(bar[2]), "DEAD", "D: a dead gladiator's button is greyed")
    EQ(SweepShare(bar[2]), 0, "D: with no wedge on it")
    r, g, b = Colour(bar[2].icon)
    CHECK(r < 0.4 and r == g and g == b, "D: its icon darker than a dim one", r)
    r, g, b = Colour(bar[2].rim)
    CHECK(r < 0.5 and r == g and g == b, "D: its rim grey, with the class colour gone", r .. "," .. g .. "," .. b)
    r, g, b = Colour(bar[2].name)
    CHECK(r < 0.5 and r == g and g == b, "D: and its name grey", r)
    EQ(Colour(bar[1].name), 1, "D: the names of the living are white")
    EQ(bar[1].icon.__desat, false, "D: and their icons keep their colour")
    back = #heard
    ClickOn(bar[2])
    EQ(#heard, back, "D: a click on a dead gladiator's button fires nothing")

    -- A token stops taking the mouse when it dies, and its pin goes
    ClickOn(T[5])
    Paint()
    EQ(Ordered(), "5", "D: (setup) the pin is moved to the warlock")
    match:Damage(rogue, warlock, rogue.spec.basic, 99999, false, false)
    Paint()
    EQ(T[5].__mouse, false, "D: a dead token stops taking the mouse")
    EQ(Ordered(), "", "D: and its pin goes with it")
    CHECK(ClickOn(T[5]) ~= T[5], "D: a click on it does not land on it")
    EQ(match.pin.A, nil, "D: and pins nothing")
    EQ(Highlighted(T[5].hover), false, "D: and the pointer over it draws no ring")
    EQ(T[4].__mouse, true, "D: the enemies still standing still take it")
    EQ(#caughtErrors, 0, "D: no error under the hand", caughtErrors[1])

    -- A pin at the gates is the opening. A seed is found whose untouched
    -- match opens on somebody other than the druid; the window plays it
    -- once untouched and once with the druid clicked at the gates, and the
    -- first hit side A lands says which it was.
    local seed, untouched = 9000, 6
    while untouched == 6 and seed < 9100 do
        seed = seed + 1
        local plain = E.NewMatch(DATA.TEAMS.A, DATA.TEAMS.B, seed)
        untouched = nil
        while not untouched and not plain.over do
            plain:Step()
            for _, said in ipairs(plain:Drain()) do
                if said.kind == "DAMAGE" and said.source <= 3 and said.target > 3 then untouched = untouched or said.target end
            end
        end
    end
    CHECK(untouched ~= nil and untouched ~= 6, "D: (setup) a seed whose untouched match does not open on the druid", seed)
    local function Opening(click)
        db.Seed = seed
        Run("deal", G.Deal)
        opening = nil
        if click then ClickOn(T[6]) end
        for _ = 1, 400 do
            if opening then break end
            Frame(0.05)
            Audit()
        end
        return opening
    end
    EQ(Opening(false), untouched, "D: untouched, the window's match opens where the engine's does")
    EQ(Opening(true), 6, "D: with the druid clicked at the gates, it opens on the druid")

    G.On.ABILITY, G.On.DAMAGE = onAbility, onDamage
    MouseTo(nil)
    -- A fresh match for what follows
    Run("deal", G.Deal)
    EQ(#caughtErrors, 0, "D: no error in any of it", caughtErrors[1])
end)

-- === D, continued: dampening and the rout =====================================
-- The one line of the header that follows the match. The clock is moved by
-- hand to where dampening is, with nobody pressing anything, and then side
-- B's two damage dealers are killed so that the engine itself calls the rout.
Section("D, dampening and the rout", function()
    local match = S.match
    local mage, warrior, warlock, druid = match.units[2], match.units[4], match.units[5], match.units[6]
    OpenGates()
    for _, unit in ipairs(match.units) do unit.wait = math.huge end
    local function At(seconds)
        match.tick = math.floor(seconds / TICK + 0.5) - 1
        Frame(0.1)
    end
    At(DATA.RULES.dampenStart)
    EQ(G.healing.__shown, false, "D: at twenty seconds healing is still whole and nothing is said")
    At(DATA.RULES.dampenStart + 0.1)
    EQ(G.healing.__shown, true, "D: a tick later the header starts to count it down")
    EQ(G.healing.__text, "Healing 99%", "D: from 99%")
    At(28)
    EQ(G.healing.__text, "Healing 43%", "D: eight seconds in, six of fourteen are left: Healing 43%")
    local r, g, b = Colour(G.healing)
    CHECK(r == g and g == b, "D: in a neutral grey", r .. "," .. g .. "," .. b)
    local beside = G.healing.__points.LEFT
    CHECK(beside and beside.rel == G.record and beside.relPoint == "RIGHT" and beside.x > 0, "D: beside the record, to its right")
    local texts = G.healing.__texts
    Frame(0)
    Frame(0.02)
    EQ(G.healing.__texts, texts, "D: and the text is not written again while it says the same thing")
    At(DATA.RULES.dampenEnd - 0.1)
    EQ(G.healing.__text, "Healing 1%", "D: the last tick with any healing in it still says so")
    At(DATA.RULES.dampenEnd)
    EQ(G.healing.__text, "No healing", "D: and at thirty-four seconds there is none")

    -- The rout: with the warrior and the warlock dead, side B is a druid,
    -- who can hurt nobody. The engine says ROUT at the end of the next tick.
    EQ(match.routed, nil, "D: (setup) nobody is routed yet")
    match:Damage(mage, warrior, mage.spec.basic, 99999, false, false)
    match:Damage(mage, warlock, mage.spec.basic, 99999, false, false)
    Frame(0.1)
    EQ(match.routed, "B", "D: (setup) the engine routed side B")
    CHECK(not match.over and druid.alive, "D: (setup) and the match goes on to the kill")
    EQ(G.healing.__shown, true, "D: a rout is said in the header")
    EQ(G.healing.__text, "Routed", "D: in one word")
    r, g, b = Colour(G.healing)
    local ring = G.tokens[6].arc.full.__color
    CHECK(r == ring[1] and g == ring[2] and b == ring[3] and r > g, "D: in the routed side's own colour, the red of its rings",
          r .. "," .. g .. "," .. b)
    EQ(#caughtErrors, 0, "D: no error in the header's line", caughtErrors[1])
    -- The match is handed back for section E to play out: everybody may
    -- press again from the next tick, and what is left of it is the kill
    for _, unit in ipairs(match.units) do unit.wait = match.tick end
end)

-- === E: pooling ===============================================================
Section("E", function()
    CommanderGladiatorDB.Speed = 2
    local function PlayMatch(tag)
        local match, before = S.match, Book()
        CHECK(PlayOut() == match, tag .. ": the match ends")
        CheckBell(tag, match, before)
        -- The banner's three seconds are the player's, not the match's:
        -- these four are played at 2x and it stays up just as long
        Advance(2.5)
        CHECK(S.match == match and G.banner.__shown, tag .. ": the banner has its time at 2x too")
        Advance(0.7)
        CHECK(S.match ~= match, tag .. ": and the next is dealt")
    end
    PlayMatch("E1")
    PlayMatch("E2")
    local widgets = created
    -- The third with a hand on it: the pointer, a tooltip, a pin, a tap
    -- and a click that does nothing make no widget either
    OpenGates()
    ClickOn(G.tokens[6])
    MouseTo(Middle(G.buttons[2]))
    ClickOn(G.buttons[2])
    ClickOn(G.buttons[3])
    PlayMatch("E3")
    MouseTo(nil)
    PlayMatch("E4")
    EQ(created, widgets, "E: two more matches create no widget, with a hand on one of them or without")
    CommanderGladiatorDB.Speed = 1

    EQ(audit.ringOff, 0, "E: over every frame so far, every ring showed its unit's health", audit.ringDetail)
    EQ(audit.offFloor, 0, "E: and no token ever left the floor")
    CHECK(audit.frames > 1500, "E: (that was a real number of frames)", audit.frames)
    CHECK(audit.numbers > 0, "E: numbers floated")
    CHECK(audit.damage > 0, "E: damage in pale red")
    CHECK(audit.heal > 0, "E: heals in green")
    CHECK(audit.absorb > 0, "E: absorbs in grey")
    EQ(audit.missigned, nil, "E: heals carry a plus and hits do not")
    CHECK(audit.crits > 0, "E: crits are written larger")
    CHECK(audit.ticks > 0, "E: and periodic ticks smaller")
    EQ(audit.basicPops, 0, "E: a filler is never called out")
    CHECK(audit.shots > 0, "E: projectiles flew")
    CHECK(audit.pops > 0, "E: spells were called out")
    CHECK(audit.bumps > 0, "E: melee bumped")
    CHECK(audit.bursts > 0, "E: the nova spread")
    EQ(audit.healingOff, 0, "E: and the header's healing line said what the match was doing", audit.healingDetail)
    EQ(audit.barOff, 0, "E: every button said what its gladiator's big spell was doing, wedge and all", audit.barDetail)
    CHECK(audit.lit > 0 and audit.swept > 0 and audit.dim > 0, "E: (and was seen glowing, sweeping and dim)",
          audit.lit .. "/" .. audit.swept .. "/" .. audit.dim)
    CHECK(audit.gateFrames > 100, "E: (at the gates as well as after them)", audit.gateFrames)
    EQ(audit.mouseOff, 0, "E: only living enemies in a match still being fought took the mouse")
    EQ(audit.pinOff, 0, "E: and the gold disc was on the pinned enemy and on nobody else")
    CHECK(outcomes.A and outcomes.B, "E: the matches played were not all won, nor all lost")
    EQ(#caughtErrors, 0, "E: no error in any of them", caughtErrors[1])
end)

-- === F: hidden means paused ===================================================
Section("F", function()
    Advance(3.0)
    local match = S.match
    local tick, clock = match.tick, S.clock
    CHECK(tick > 0 and not match.over, "F: (setup) a match is under way", tick)
    -- A button in mid-sweep, to be looked at again after the pause: its
    -- cooldown is the match's and has to stand still with it
    local mage = match.units[2]
    mage.ready[mage.big.key] = tick + 100
    Frame(0)
    NEAR(SweepShare(G.buttons[2]), 100 / 140, "F: (setup) a button is in mid-sweep", 0.0011)
    Run("close", Slash, "")
    EQ(window.__shown, false, "F: /cglad closes it")
    Advance(5.0)
    EQ(match.tick, tick, "F: a hidden window's match does not advance")
    EQ(S.clock, clock, "F: nor do its animations")
    Run("reopen", Slash, "")
    EQ(window.__shown, true, "F: /cglad opens it again")
    CHECK(S.match == match, "F: on the same match, not a new deal")
    Frame(0)
    NEAR(SweepShare(G.buttons[2]), 100 / 140, "F: and the button's sweep is where it was left", 0.0011)
    Advance(1.0)
    NEAR(match.tick, tick + 10, "F: which carries on from where it stopped", 1)

    -- Switched off on the settings page while open: it closes
    CommanderGladiatorDB.Enabled = false
    Commander.Notify(COMMANDER_GLADIATOR_EVENTS.UPDATE)
    EQ(window.__shown, false, "F: switching the module off closes the window")
    CommanderGladiatorDB.Enabled = true
    Commander.Notify(COMMANDER_GLADIATOR_EVENTS.UPDATE)
    EQ(window.__shown, false, "F: switching it back on does not open it")
    Run("reopen", Slash, "")
    EQ(window.__shown, true, "F: the slash command does")

    -- Hidden is paused at the gates too: closed half way through the wait,
    -- it opens half way through the wait
    Run("deal", G.Deal)
    match = S.match
    Advance(1.0)
    EQ(G.count.__text, "Gates open in 1", "F: (setup) half way through the gates")
    Run("close", Slash, "")
    Advance(5.0)
    Run("reopen", Slash, "")
    Frame(0)
    CHECK(G.count.__shown and G.count.__text == "Gates open in 1" and match.tick == 0,
          "F: a window closed at the gates is still at them when it is opened")
    Advance(0.9)
    CHECK(G.count.__shown and match.tick == 0, "F: with the rest of the wait still to run")
    Advance(0.1)
    EQ(G.count.__shown, false, "F: and no more than the rest")
    Advance(1.0)
    NEAR(match.tick, 10, "F: after which the match runs", 1)
end)

-- === G: depth =================================================================
Section("G", function()
    local match = S.match
    local front, back = match.units[1], match.units[4]
    local T = G.tokens
    -- The match is held still so the two stay where they are put; everyone
    -- else is parked mid-floor, between them
    match.over = true
    for _, unit in ipairs(match.units) do unit.x, unit.y = 50, 25 end
    front.x, front.y = 30, 45
    back.x, back.y = 70, 5
    Advance(1.5)
    local _, frontY = Foot(T[1])
    local _, backY = Foot(T[4])
    CHECK(frontY < backY, "G: nearer the front is lower in the window")
    NEAR(T[1].__scale, L.scaleBack + (1 - L.scaleBack) * 0.9, "G: the front token is nearly full size", 0.002)
    NEAR(T[4].__scale, L.scaleBack + (1 - L.scaleBack) * 0.1, "G: the back token is nearly the back scale", 0.002)
    CHECK(T[1].__scale > T[4].__scale, "G: the front token is the larger")
    CHECK(T[1].__level > T[4].__level, "G: and is drawn over the back one", T[1].__level .. " vs " .. T[4].__level)
    EQ(T[1].rank, 6, "G: the front token is on top of all six")
    EQ(T[4].rank, 1, "G: the back token is under all six")
    CHECK(T[1].face.__level == T[1].__level + 2 and T[1].arc.cd.__level == T[1].__level + 1
          and T[1].arc.fullFrame.__level == T[1].__level + 1, "G: a token's ring and face move with it")
    CHECK(G.overlay.__level > T[1].face.__level, "G: numbers and projectiles are above every token")
    -- The row is narrower at the back: the same distance from the middle
    -- lands closer to it -- a tenth closer, for these two rows. (Measured
    -- with a margin: the two tokens glide to their marks and stop a
    -- billionth of a pixel short of them, and a bare "closer" was decided
    -- by which of the two was shorter.)
    local fx = Foot(T[1])
    local bx = Foot(T[4])
    CHECK(math.abs(bx - L.floorX) < 0.95 * math.abs(fx - L.floorX), "G: the back row converges on the middle",
          math.abs(bx - L.floorX) / math.abs(fx - L.floorX))

    local sets = levelSets
    Advance(1.0)
    EQ(levelSets, sets, "G: with the order unchanged, no frame level is touched")

    front.y, back.y = 5, 45
    Advance(1.5)
    CHECK(T[4].__level > T[1].__level, "G: swap them and the order swaps")
    CHECK(T[4].__scale > T[1].__scale, "G: and so do the sizes")
    CHECK(levelSets > sets, "G: which is when levels are set")

    -- The window is top-level: a click raises it, and its children's levels
    -- cannot be trusted to have come along. The tokens follow the stage.
    window.__level, G.stage.__level = window.__level + 20, G.stage.__level + 20
    -- (What was never given a level of its own does come along: the bar's
    -- buttons, like the header's, are simply children. Carried here by hand
    -- so that a click after this section still finds them over the window.)
    for _, button in ipairs(G.buttons) do
        button.__level, button.sweep.cd.__level = button.__level + 20, button.sweep.cd.__level + 20
    end
    Frame(0)
    local lowest, highest = math.huge, 0
    for _, token in ipairs(T) do
        lowest, highest = math.min(lowest, token.__level), math.max(highest, token.face.__level)
    end
    CHECK(lowest > G.stage.__level, "G: a raised window carries every token above its floor", lowest)
    CHECK(G.overlay.__level > highest, "G: and the numbers above every token")

    -- Personal space. Two living tokens on one spot are drawn `space` apart,
    -- the lower id to the left; a third standing clear of them is not moved.
    for _, unit in ipairs(match.units) do unit.x, unit.y = 20, 10 end
    local one, two, clear = match.units[2], match.units[5], match.units[3]
    one.x, one.y, two.x, two.y, clear.x, clear.y = 60, 30, 60, 30, 85, 40
    Advance(1.5)
    local ax, ay = Foot(T[2])
    local bx2, by = Foot(T[5])
    local wantA = G.Project(60 - L.space / 2, 30)
    local wantB = G.Project(60 + L.space / 2, 30)
    NEAR(ax, wantA, "G: two on one spot are drawn apart: the lower id half the space left", 0.01)
    NEAR(bx2, wantB, "G: and the other half the space right", 0.01)
    CHECK(bx2 - ax > 30, "G: which is room for two faces", bx2 - ax)
    NEAR(ay, by, "G: on the same row")
    local cx, cy = Foot(T[3])
    local wantX, wantY = G.Project(85, 40)
    CHECK(math.abs(cx - wantX) < 0.01 and math.abs(cy - wantY) < 0.01, "G: a token standing clear is drawn exactly where its unit is")
    EQ(one.x, 60, "G: the match never hears of it")
    -- In a corner the push stops at the wall. The half of it the wall took
    -- is not lost: the next round gives it to the token that can still
    -- move, and three rounds leave the pair seven eighths of their room
    -- where one left them half.
    one.x, one.y, two.x, two.y = 0, 0, 0, 0
    Advance(1.5)
    CHECK(OnFloor(Foot(T[2])) and OnFloor(Foot(T[5])), "G: two in a corner are both still on the floor")
    local unitWide = G.Project(1, 0) - G.Project(0, 0)
    local apart = (Foot(T[5]) - Foot(T[2])) / unitWide
    CHECK(apart > 0.85 * L.space, "G: and drawn nearly their whole room apart, not half of it", apart)
    CHECK(apart <= L.space + 0.001, "G: and no more than it", apart)
    -- Three in a row, six units apart: once round, the middle one is pushed
    -- clear of the first and then back onto it by the third
    one.x, one.y, two.x, two.y, clear.x, clear.y = 60, 30, 66, 30, 72, 30
    Advance(1.5)
    unitWide = G.Project(1, 30) - G.Project(0, 30)
    local left, right = (Foot(T[5]) - Foot(T[2])) / unitWide, (Foot(T[3]) - Foot(T[5])) / unitWide
    CHECK(left > 0.95 * L.space, "G: three in a row: the first two have their room", left)
    CHECK(right > 0.95 * L.space, "G: and the last two", right)
    -- The dead take no room: the living stand where they stand
    one.x, one.y, two.x, two.y = 60, 30, 60, 30
    two.alive, two.health = false, 0
    Advance(1.5)
    NEAR(Foot(T[2]), (G.Project(60, 30)), "G: a token standing on a corpse is not pushed off it", 0.01)
    two.alive, two.health = true, two.healthMax
    match.over = false
    EQ(#caughtErrors, 0, "G: no error", caughtErrors[1])
end)

-- === H: speed =================================================================
Section("H", function()
    Run("deal", G.Deal)
    local match = S.match
    EQ(OpenGates(), 40, "H: at 1x the gates are forty frames of a twentieth of a second: two seconds")
    Advance(2.0)
    local atOne = match.time
    NEAR(atOne, 2.0, "H: forty frames at 1x is two seconds of match", 0.051)

    -- The header's button flips the setting and says so
    Run("click", G.speedButton.__scripts.OnClick, G.speedButton)
    EQ(CommanderGladiatorDB.Speed, 2, "H: the header button sets 2x")
    EQ(G.speedButton.__text, "2x", "H: and reads 2x")
    Advance(2.0)
    NEAR(match.time - atOne, 2 * atOne, "H: the same forty frames at 2x is twice the match", 0.051)

    -- The gates are the match's clock too: at 2x they are half as long by
    -- the wall. And a hitch while they are shut costs the wait what it
    -- would cost a match, the step cap, and not the whole of it.
    Run("deal", G.Deal)
    EQ(OpenGates(), 20, "H: at 2x the gates are twenty of the same frames: two seconds of match, one by the wall")
    Run("deal", G.Deal)
    Frame(30)
    CHECK(G.count.__shown and G.count.__text == "Gates open in 2" and S.match.tick == 0,
          "H: a thirty-second frame at the gates does not throw them open", G.count.__text)
    EQ(OpenGates(), 15, "H: it costs the wait half a second of its two")
    -- A hundred and twenty frames of a sixtieth of a second are two seconds
    -- in arithmetic and a whisker under in floating point, and the gates
    -- open on the hundred and twentieth all the same
    CommanderGladiatorDB.Speed = 1
    Run("deal", G.Deal)
    EQ(OpenGates(1 / 60), 120, "H: frames that add up to the wait a hair's breadth short still open the gates")
    CommanderGladiatorDB.Speed = 2

    Run("click", G.speedButton.__scripts.OnClick, G.speedButton)
    EQ(CommanderGladiatorDB.Speed, 1, "H: and flips back")
    EQ(G.speedButton.__text, "1x", "H: reading 1x")

    -- The settings page's control is the same setting
    local dropdown
    for _, control in ipairs(controls) do
        if control.kind == "dropdown" then dropdown = control.opts end
    end
    EQ(dropdown.get(), 1, "H: the settings page reads the same speed")
    local values = {}
    for _, option in ipairs(dropdown.options) do values[#values + 1] = option.value end
    EQ(table.concat(values, ","), "1,2", "H: and offers 1x and 2x")
    dropdown.set(2)
    Commander.Notify(COMMANDER_GLADIATOR_EVENTS.UPDATE)
    EQ(G.speedButton.__text, "2x", "H: a change made there reaches the header")
    dropdown.set(1)
    Commander.Notify(COMMANDER_GLADIATOR_EVENTS.UPDATE)
    EQ(G.speedButton.__tooltip and G.speedButton.__tooltip[1], "Match Speed", "H: the button explains itself")

    -- Restore Defaults with the window open at 2x. The framework's button
    -- and its slash command call the module's reset and nothing else, so the
    -- header only hears of it because the reset says so itself.
    Run("click", G.speedButton.__scripts.OnClick, G.speedButton)
    EQ(G.speedButton.__text, "2x", "H: (setup) the header reads 2x")
    CHECK(not G.hints[1].__shown and not G.hints[2].__shown, "H: (setup) the hint has been followed and is gone")
    Run("reset", Slash, "reset")
    CHECK(G.hints[1].__shown and G.hints[2].__shown, "H: Restore Defaults brings the hint back, at once")
    EQ(CommanderGladiatorDB.Speed, 1, "H: Restore Defaults puts the speed back")
    -- And the hint goes again on the second verb, whichever comes second:
    -- section D pinned and then tapped; this taps and then pins
    EQ(S.match.tick, 0, "H: (setup) the match on the floor is at its first tick, gates open")
    EQ(ClickOn(G.buttons[2]), G.buttons[2], "H: (setup) a click lands on the Polymorph button")
    CHECK(CommanderGladiatorDB.Tapped and G.hints[1].__shown and G.hints[2].__shown, "H: after a tap alone the hint is still up")
    EQ(ClickOn(G.tokens[6]), G.tokens[6], "H: (setup) a click lands on the druid")
    CHECK(CommanderGladiatorDB.Pinned and not G.hints[1].__shown and not G.hints[2].__shown, "H: and the pin that follows takes it down")
    Run("reset", Slash, "reset")
    CHECK(G.hints[1].__shown and G.hints[2].__shown, "H: (and Restore Defaults brings it back again)")
    EQ(G.speedButton.__text, "1x", "H: and the header button says so at once")
    EQ(window.__shown, true, "H: with the window left open")

    -- The speed control is greyed while the module is switched off
    CHECK(type(dropdown.isEnabled) == "function" and dropdown.isEnabled() == true, "H: the speed control is live while the module is on")
    CommanderGladiatorDB.Enabled = false
    CHECK(type(dropdown.isEnabled) == "function" and dropdown.isEnabled() == false, "H: and greyed while it is off")
    CommanderGladiatorDB.Enabled = true
    EQ(#caughtErrors, 0, "H: no error", caughtErrors[1])
end)

-- === I: the .toc and the art ==================================================
local shipping = {}
Section("I", function()
    EQ(tocFields.Interface, "20506", "I: Interface 20506")
    EQ(tocFields.Title, "Commander Gladiator", "I: the title")
    EQ(tocFields.Category, "Commander", "I: in the Commander category")
    EQ(tocFields.SavedVariables, "CommanderGladiatorDB", "I: the saved table is declared")
    EQ(tocFields.RequiredDeps, "Commander_Events", "I: the framework is required")
    CHECK(tocFields.Notes and #tocFields.Notes > 40, "I: it has notes")
    EQ(tocFields.Version, "0.2.0", "I: version 0.2.0")
    CHECK(tocFields.Notes and not tocFields.Notes:lower():find("watch%-only") and tocFields.Notes:find("click an enemy", 1, true)
          and tocFields.Notes:find("tap a glowing spell", 1, true), "I: and the notes name the two things a player can do")
    EQ(table.concat(tocFiles, " "),
       "CommanderGladiatorData.lua CommanderGladiatorEngine.lua CommanderGladiatorDB.lua CommanderGladiator.lua",
       "I: data, engine, settings, window -- in that order")

    local listed = {}
    for _, file in ipairs(tocFiles) do
        listed[file] = true
        shipping[#shipping + 1] = file
        CHECK(ReadFile(HERE .. "/" .. file) ~= nil, "I: " .. file .. " exists")
    end
    local onDisk = 0
    for name in io.popen('/bin/ls "' .. HERE .. '"'):lines() do
        if name:match("%.lua$") then
            onDisk = onDisk + 1
            CHECK(listed[name], "I: " .. name .. " is listed in the .toc")
        end
    end
    EQ(onDisk, #tocFiles, "I: and nothing listed is missing from the folder")

    -- Copy only what you reference; reference only what you copied
    local prefix = "Interface\\AddOns\\Commander_Gladiator\\Textures\\"
    local referenced, count = {}, 0
    for _, path in pairs(G.ART) do
        if path:sub(1, #prefix) == prefix then
            local name = path:sub(#prefix + 1)
            referenced[name] = true
            count = count + 1
            CHECK(ReadFile(HERE .. "/Textures/" .. name) ~= nil, "I: " .. name .. " was copied")
        end
    end
    EQ(count, 4, "I: four pieces of copied art")
    for name in io.popen('/bin/ls "' .. HERE .. '/Textures"'):lines() do
        CHECK(referenced[name], "I: " .. name .. " is referenced by the window")
        local ours = ReadFile(HERE .. "/Textures/" .. name)
        local theirs = ReadFile(ADDONS .. "/Commander_Plates/Textures/" .. name)
        if theirs then CHECK(ours == theirs, "I: " .. name .. " is Plates' file, byte for byte") end
    end
end)

-- === J: compiles, locals, globals =============================================
-- Everything the module may read or write by global name. A name outside
-- this list is either a typo -- Lua compiles a misspelt local into a global
-- lookup and finds nil at run time -- or a client API nobody has vetted.
local CLIENT_GLOBALS = {
    "CreateFrame", "UIParent", "GetTime", "UISpecialFrames", "RAID_CLASS_COLORS",
    "CLASS_ICON_TCOORDS", "STANDARD_TEXT_FONT", "Commander", "GameTooltip",
}
Section("J", function()
    local allowed = {}
    for _, name in ipairs({
        "math", "string", "table", "ipairs", "pairs", "tostring", "tonumber", "setmetatable",
        "error", "print", "_G",
        "CommanderGladiator", "CommanderGladiatorDB", "CommanderGladiator_Data",
        "CommanderGladiator_Engine", "COMMANDER_GLADIATOR_EVENTS",
    }) do allowed[name] = true end
    for _, name in ipairs(CLIENT_GLOBALS) do allowed[name] = true end

    for _, file in ipairs(shipping) do
        local path = HERE .. "/" .. file
        local listing = io.popen(LUAJIT .. ' -bl "' .. path .. '" 2>&1'):read("*a")
        CHECK(listing:find("BYTECODE", 1, true) ~= nil, "J: " .. file .. " compiles", listing:sub(1, 200))
        local strangers = {}
        for name in listing:gmatch('G[GS]ET%s+%d+%s+%d+%s+; "([^"]+)"') do
            if not allowed[name] and not strangers[name] then
                strangers[name] = true
                strangers[#strangers + 1] = name
            end
        end
        EQ(table.concat(strangers, " "), "", "J: " .. file .. " touches no global it should not")

        -- Chunk-level locals: declarations starting in column one. The
        -- ceiling is 200 for a chunk; the house keeps well under it.
        local locals = 0
        for line in ReadFile(path):gmatch("[^\n]+") do
            local names = line:match("^local%s+function%s+([%w_]+)") or line:match("^local%s+([%w_,%s]-)%s*=") or line:match("^local%s+([%w_,%s]+)$")
            if names then
                locals = locals + 1
                for _ in names:gmatch(",") do locals = locals + 1 end
            end
        end
        CHECK(locals > 0 and locals < 150, "J: " .. file .. " keeps under 150 chunk-level locals", locals)
    end
end)

-- === K: field proof ===========================================================
-- Nobody can run the game from here, so the bar is: use only what some OTHER
-- shipped Commander module already uses. One grep over every Commander
-- module's shipping Lua (Harness folders, stale worktrees and this module
-- itself excluded) for every widget method the mock saw called and every
-- client global the files read; then the real framework's source for every
-- Commander function the strict stub handed out.
--
-- Section M comes after this one and drives the window again, so the count
-- of methods proved here is kept, and M's last check is that it called
-- nothing this section had not seen.
local provedMethods = 0
Section("K", function()
    local function Proved(names, pattern)
        local command = '/usr/bin/grep -rhoE "' .. pattern:format(table.concat(names, "|")) .. '" --include="*.lua"'
            .. ' --exclude-dir=Harness --exclude-dir=.claude --exclude-dir=Commander_Gladiator "'
            .. ADDONS .. '"/Commander_* | sort -u'
        local found = {}
        for line in io.popen(command):lines() do
            local name = line:match("([%w_]+)")
            if name then found[name] = true end
        end
        return found
    end

    local methods = {}
    for name in pairs(called) do methods[#methods + 1] = name end
    table.sort(methods)
    provedMethods = #methods
    CHECK(#methods > 30, "K: (the mock recorded the module's method calls)", #methods)
    local found = Proved(methods, "[:.](%s)[(]")
    local unproved = {}
    for _, name in ipairs(methods) do
        if not found[name] then unproved[#unproved + 1] = name end
    end
    EQ(table.concat(unproved, " "), "", "K: every widget method called is used by another shipped module")

    found = Proved(CLIENT_GLOBALS, "(%s)[^A-Za-z0-9_]")
    for _, name in ipairs(CLIENT_GLOBALS) do
        CHECK(found[name], "K: the client global " .. name .. " is read by another shipped module")
    end

    local events = assert(ReadFile(ADDONS .. "/Commander_Events/CommanderEvents.lua"))
    local settings = assert(ReadFile(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua"))
    local names = {}
    for name in pairs(used) do names[#names + 1] = name end
    table.sort(names)
    CHECK(#names >= 10, "K: (the stub recorded the module's framework calls)", #names)
    for _, name in ipairs(names) do
        local owner, field = name:match("^(.-)%.([%w_]+)$")
        local real
        if owner == "Commander" then
            real = field == "UI" or events:find("function Commander." .. field .. "(", 1, true)
        elseif owner == "Commander.UI" then
            real = settings:find("function UI." .. field .. "(", 1, true) or settings:find("UI." .. field .. " = ", 1, true)
        else
            real = settings:find("function PanelMethods." .. field .. "(", 1, true)
        end
        CHECK(real, "K: " .. name .. " exists in the real framework")
    end
    CHECK(settings:find('DARK = {', 1, true), "K: the DARK window style exists in the real framework")

    io.write(string.format("  K  %d widget methods, %d client globals, %d framework functions: ", #methods, #CLIENT_GLOBALS, #names))
    if #unproved == 0 then
        io.write("all in use elsewhere in the suite\n")
    else
        io.write("NOT field-proved: ", table.concat(unproved, " "), "\n")
    end
end)

-- === L: a second session =====================================================
-- The window is built once a session, so the only way to see it read a saved
-- place is to build it again: the place section B's drag wrote into the book
-- is where the next session's window opens. Last, because it leaves a second
-- window behind it.
Section("L", function()
    local pos = CommanderGladiatorDB.Pos
    CHECK(pos and pos.point == "BOTTOMRIGHT", "L: (setup) the book holds the place it was dropped")
    Run("build", G.Build)
    local second = CommanderGladiatorWindow
    CHECK(second ~= nil and second ~= window, "L: (setup) a second window was built")
    local at = second and second.__points.BOTTOMRIGHT
    CHECK(at and at.rel == UIParent and at.relPoint == "BOTTOMRIGHT", "L: a window with a saved place opens by that corner")
    EQ(at and at.x, -33, "L: at its saved place (x)")
    EQ(at and at.y, 44, "L: at its saved place (y)")
    EQ(second and second.__points.CENTER, nil, "L: and not in the middle")
    EQ(second and second.__shown, false, "L: built, it waits to be asked for")
end)

-- === M: a good player, through real clicks ====================================
-- The engine smoke's section G says what a hand is worth by calling Pin and
-- Tap. This says the window delivers it: the same policy played over two
-- hundred seeds twice -- once straight on the engine, and once on the second
-- session's window by a script that only LOOKS at widgets (which token wears
-- the cross, which the gold disc, whose badge has gone grey, the rogue's
-- ring, which buttons glow) and only CLICKS at points of the window.
--
-- The policy is the engine smoke's GOOD, in a player's words: at the gates
-- click the druid, and tap Polymorph the moment they open. When the enemy's
-- marker appears on your rogue or priest, click the warlock. Tap Polymorph
-- and Cheap Shot whenever they glow. When the first enemy dies: the druid,
-- click the warlock; the warlock, click the warrior -- unless it is past
-- eight seconds and their marker is on your rogue with a quarter of his
-- health gone, and then the druid. It sees four ticks late and makes one
-- input in seven ticks. It is copied here, not shared: the two smokes load
-- nothing of each other's.
local function Wants(seen, mind, id)
    if seen[id] and seen.pin ~= id and mind.want ~= id then
        mind.want = id
        return true
    end
    return false
end
local function GoodMove(seen, mind)
    if seen.polymorph then return "tap", 2 end
    if seen.cheapShot then return "tap", 1 end
    if seen.mark and not mind.answered then
        mind.answered = true
        if seen.mark ~= 2 and Wants(seen, mind, 5) then return "pin", 5 end
    end
    if mind.answered and not mind.followed then
        local dead = (not seen[4] and 4) or (not seen[5] and 5) or (not seen[6] and 6)
        if dead then
            mind.followed = true
            local nextPin
            if dead == 6 then
                nextPin = 5
            elseif dead == 5 then
                nextPin = (seen.mark == 1 and seen.rogue < 0.75 and seen.time >= 8) and 6 or 4
            end
            if nextPin and Wants(seen, mind, nextPin) then return "pin", nextPin end
        end
    end
    return nil
end
-- `look` fills in what is seen, `hand` makes an input, `shut` says whether
-- the gates are. Called once before every tick, and before every frame of
-- the gates.
local function GoodPlayer(look, hand, shut)
    local ring, mind, last = {}, { want = 6 }, 0
    for slot = 0, 4 do ring[slot] = {} end
    return function(match)
        local tick = match.tick
        if tick == 0 then
            if not mind.pinned then
                mind.pinned = true
                hand.pin(6)
            end
            if shut() then return end
            if not mind.tapped then
                mind.tapped = true
                hand.tap(2)
            end
        end
        look(match, ring[tick % 5])
        if tick < 4 or tick - last < 7 then return end
        local verb, id = GoodMove(ring[(tick - 4) % 5], mind)
        if verb then
            last = tick
            hand[verb](id)
        end
    end
end

Section("M", function()
    local SEEDS = 200
    local db = CommanderGladiatorDB
    -- Straight on the engine: what the policy is worth, and what nobody is
    local engineWon, nobodyWon, engineWins, nobodyWins = {}, {}, 0, 0
    for seed = 1, SEEDS do
        local match = E.NewMatch(DATA.TEAMS.A, DATA.TEAMS.B, seed)
        local move = GoodPlayer(function(m, seen)
            local mark = m.focus.B
            seen.time = m.time
            seen.mark = mark and mark.alive and mark.id or nil
            seen.pin = m.pin.A and m.pin.A.id or nil
            seen[4], seen[5], seen[6] = m.units[4].alive, m.units[5].alive, m.units[6].alive
            seen.rogue = m.units[1].health / m.units[1].healthMax
            seen.cheapShot, seen.polymorph = m:Lit(m.units[1]), m:Lit(m.units[2])
        end, {
            pin = function(id) match:Pin("A", match.units[id]) end,
            tap = function(id) match:Tap(match.units[id]) end,
        }, function() return false end)
        while not match.over do
            move(match)
            match:Step()
            match:Drain()
        end
        engineWon[seed] = match.winner == "A"
        if engineWon[seed] then engineWins = engineWins + 1 end

        local plain = E.NewMatch(DATA.TEAMS.A, DATA.TEAMS.B, seed)
        while not plain.over do plain:Step() end
        nobodyWon[seed] = plain.winner == "A"
        if nobodyWon[seed] then nobodyWins = nobodyWins + 1 end
    end

    -- Through the window: the second session's, the first one's being shut
    -- (a field written here, not a method called: the smoke calls none)
    rawset(window, "__shown", false)
    Run("open", Slash, "")
    local second = CommanderGladiatorWindow
    CHECK(second ~= window and second.__shown, "M: (setup) the second session's window is open")
    db.Speed = 1
    local T, bar = G.tokens, G.buttons
    local inputs, misses = 0, 0
    local hand = {
        pin = function(id)
            inputs = inputs + 1
            if ClickOn(T[id]) ~= T[id] then misses = misses + 1 end
        end,
        tap = function(id)
            inputs = inputs + 1
            if ClickOn(bar[id]) ~= bar[id] then misses = misses + 1 end
        end,
    }
    local function Look(match, seen)
        seen.time = match.tick / 10
        seen.mark, seen.pin = nil, nil
        for id = 1, 3 do
            if T[id].mark.__shown then seen.mark = id end
        end
        for id = 4, 6 do
            if T[id].order.__shown then seen.pin = id end
            seen[id] = not T[id].badge.__desat
        end
        seen.rogue = RingShare(T[1])
        seen.cheapShot, seen.polymorph = Says(bar[1]) == "LIT", Says(bar[2]) == "LIT"
    end
    local function Shut() return G.count.__shown end

    local function PlayByClick(seed, touch)
        db.Seed = seed
        Run("deal", G.Deal)
        local match = S.match
        local move = touch and GoodPlayer(Look, hand, Shut)
        for _ = 1, 2000 do
            if match.over then break end
            if move then move(match) end
            -- One tick to a frame once the gates are open, so the script
            -- sees and clicks between ticks exactly as it does on the engine
            Frame(Shut() and 0.5 or 0.1)
        end
        return match.winner == "A"
    end

    local widgets, same, clickWins, plainSame = nil, 0, 0, 0
    for seed = 1, SEEDS do
        local won = PlayByClick(seed, true)
        widgets = widgets or created
        if won then clickWins = clickWins + 1 end
        if won == engineWon[seed] then same = same + 1 end
    end
    -- And twenty of them with nobody's hand on the window: the gates, the
    -- bar and the pointer change nothing about a match nobody touches
    for seed = 1, 20 do
        if PlayByClick(seed, false) == nobodyWon[seed] then plainSame = plainSame + 1 end
    end
    local clicked, engine, nobody = clickWins / SEEDS, engineWins / SEEDS, nobodyWins / SEEDS
    io.write(string.format("  M  %d seeds: nobody %.3f, the good player on the engine %.3f, by clicks on the window %.3f (%d the same), %.2f inputs a match\n",
        SEEDS, nobody, engine, clicked, same, inputs / SEEDS))

    EQ(plainSame, 20, "M: twenty matches nobody touches end in the window as they do on the engine")
    CHECK(math.abs(clicked - engine) <= 0.01, "M: clicks on the window win as often as the same policy on the engine, to a point",
          clicked .. " vs " .. engine)
    -- The one thing the script reads less exactly off the window than off
    -- the engine is the rogue's ring, drawn to a thousandth of a turn
    CHECK(same >= SEEDS - 2, "M: and seed for seed the matches end the same way", same)
    CHECK(clicked >= nobody + 0.10, "M: the good player by clicks beats nobody clearly", clicked .. " vs " .. nobody)
    CHECK(clicked >= 0.62 and clicked <= 0.85, "M: and not always", clicked)
    EQ(misses, 0, "M: every click it made landed on the token or the button it was aimed at")
    CHECK(inputs / SEEDS >= 3 and inputs / SEEDS <= 9, "M: at a handful of inputs a match", inputs / SEEDS)
    EQ(created, widgets, "M: and two hundred matches under a hand create no widget")
    CHECK(db.Pinned and db.Tapped and not G.hints[1].__shown, "M: the second session's hint went with its first pin and tap")
    EQ(#caughtErrors, 0, "M: no error", caughtErrors[1])

    local methods = 0
    for _ in pairs(called) do methods = methods + 1 end
    EQ(methods, provedMethods, "M: nothing was called on a widget here that section K had not already proved")
end)

EQ(#caughtErrors, 0, "no Lua error anywhere in the run", caughtErrors[1])
for index = 1, math.min(#caughtErrors, 5) do io.write("  error: ", caughtErrors[index], "\n") end

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
