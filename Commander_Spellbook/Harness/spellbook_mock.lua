-- Commander Spellbook harness mock (luajit).
--
-- The suite's permissive widget mock (Commander_Tradecraft's, which copied
-- Commander_Advisor's) with two things it did not need:
--
--   * GEOMETRY. Every SetPoint is recorded and resolved to an absolute rect
--     the way the client does (Commander_ArenaFrames' render resolver), and a
--     ScrollFrame offsets its scroll child. GetLeft/GetTop/GetWidth/GetHeight
--     answer from that, so the cast buttons' placement and their clipping to
--     the scroll viewport are tested for real, and the render script can draw
--     the window from the layout code's own numbers.
--   * PROTECTION. A secure template makes the frame and its parent chain
--     protected; a protected frame anchored to another makes that one
--     protected too; in combat, Show/Hide/SetPoint/SetSize/SetScale on a
--     protected frame are refused and recorded in blockedCalls (the field's
--     ADDON_ACTION_BLOCKED). HookScript chains rather than replaces.
--
-- Fixtures and the spell API live in the harness; this is only the widget
-- layer and the shared client globals.

local M = {}

M.now = 1000000
function time() return M.now end
function date(fmt, t) return os.date(fmt or "%c", t or M.now) end
function GetTime() return M.now - 999000 end
function GetBuildInfo() return "2.5.6", "69795", "Oct 1 2026", 20506 end

M.printLog = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    M.printLog[#M.printLog + 1] = table.concat(parts, " ")
end

M.errors = {}
function geterrorhandler()
    return function(err) M.errors[#M.errors + 1] = tostring(err) end
end

M.chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) M.chat[#M.chat + 1] = msg end }

M.combat = false
function InCombatLockdown() return M.combat end

M.widgets = {}
M.eventRegistry = {}
M.blockedCalls = {}

local FONT_SIZE = {
    GameFontNormal = 12, GameFontNormalLarge = 16, GameFontHighlight = 12,
    GameFontNormalSmall = 10, GameFontHighlightSmall = 10, GameFontDisableSmall = 10,
    GameFontDisable = 12, NumberFontNormal = 12, GameFontNormalHuge = 20,
}

local function Blocked(s, what)
    if not (M.combat and rawget(s, "__protected")) then return false end
    M.blockedCalls[#M.blockedCalls + 1] = (rawget(s, "__name") or rawget(s, "__kind") or "?") .. ":" .. what
    return true
end

-- ---------------------------------------------------------------------------
-- Geometry
-- ---------------------------------------------------------------------------

local function AnchorOf(point, rect)
    local l, b, w, h = rect.l, rect.b, rect.w, rect.h
    local x, y
    if point:find("LEFT") then x = l elseif point:find("RIGHT") then x = l + w else x = l + w / 2 end
    if point:find("TOP") then y = b + h elseif point:find("BOTTOM") then y = b else y = b + h / 2 end
    return x, y
end

local function TextSize(s)
    local text = (s.__text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "WW")
    local size = (s.__font and s.__font[2]) or 10
    return #text * size * 0.5, size
end

local Resolve
-- Resolved fresh on every call: layout changes all the time in a harness and
-- a cache would only lie
local ResolveInner
-- The guard is the recursion stack, not a visited set: two siblings may
-- both anchor to UIParent, and only a frame anchored (through others) to
-- itself is a cycle
Resolve = function(s, guard)
    guard = guard or {}
    if guard[s] then return { l = 0, b = 0, w = 0, h = 0 } end
    guard[s] = true
    local r = ResolveInner(s, guard)
    guard[s] = nil
    return r
end

ResolveInner = function(s, guard)
    if s.__name == "UIParent" then return { l = 0, b = 0, w = 1600, h = 900 } end
    local parent = rawget(s, "__parent")
    local pr = type(parent) == "table" and Resolve(parent, guard) or nil
    local w, h = s.__w, s.__h
    if s.__kind == "FontString" then
        local tw, size = TextSize(s)
        local lines = 1
        if w and w > 0 and tw > w and not s.__nowrap then lines = math.ceil(tw / w) end
        w = w or tw
        h = h or size * 1.2 * lines
    end
    -- A scroll child sits at its scroll frame's top-left, moved up by the
    -- scroll offset
    local scroller = rawget(s, "__scroller")
    if scroller then
        local sr = Resolve(scroller, guard)
        local off = scroller.__vscroll or 0
        local cw = w or sr.w
        local ch = h or 1
        return { l = sr.l, b = sr.b + sr.h - ch + off, w = cw, h = ch }
    end
    if rawget(s, "__allPoints") then
        local ref = s.__allPoints
        local rr = (type(ref) == "table") and Resolve(ref, guard) or pr
        if rr then return { l = rr.l, b = rr.b, w = rr.w, h = rr.h } end
    end
    local points = rawget(s, "__points") or {}
    if #points == 0 then
        if pr and s.__kind == "Texture" then return { l = pr.l, b = pr.b, w = pr.w, h = pr.h } end
        if pr then return { l = pr.l, b = pr.b, w = w or pr.w, h = h or pr.h } end
        return { l = 0, b = 0, w = w or 0, h = h or 0 }
    end
    local left, right, cx, top, bottom, cy
    for _, p in ipairs(points) do
        local rel = p.rel
        if type(rel) ~= "table" then rel = parent end
        local rr = type(rel) == "table" and Resolve(rel, guard) or { l = 0, b = 0, w = 1600, h = 900 }
        local ax, ay = AnchorOf(p.relPoint or p.point, rr)
        ax, ay = ax + (p.x or 0), ay + (p.y or 0)
        local pt = p.point
        if pt:find("LEFT") then left = ax elseif pt:find("RIGHT") then right = ax else cx = ax end
        if pt:find("TOP") then top = ay elseif pt:find("BOTTOM") then bottom = ay else cy = ay end
    end
    local l, ww, b, hh
    if left and right then l, ww = left, right - left
    elseif left then l, ww = left, w or 0
    elseif right then ww = w or 0; l = right - ww
    elseif cx then ww = w or 0; l = cx - ww / 2
    else l, ww = pr and pr.l or 0, w or 0 end
    if top and bottom then b, hh = bottom, top - bottom
    elseif bottom then b, hh = bottom, h or 0
    elseif top then hh = h or 0; b = top - hh
    elseif cy then hh = h or 0; b = cy - hh / 2
    else b, hh = pr and pr.b or 0, h or 0 end
    return { l = l, b = b, w = ww, h = hh }
end

M.Resolve = Resolve

local function Visible(s)
    local w = s
    while type(w) == "table" do
        if w.__shown == false then return false end
        w = rawget(w, "__parent")
    end
    return true
end

M.Visible = Visible

-- ---------------------------------------------------------------------------
-- Widgets
-- ---------------------------------------------------------------------------

local NewWidget
local WidgetMT = {}

local function Method(self, key, fn)
    rawset(self, key, fn)
    return fn
end

local function RunScript(s, name, ...)
    local list = s.__scripts[name]
    if not list then return end
    for _, fn in ipairs(list) do fn(s, ...) end
end

M.RunScript = RunScript

local METHODS = {
    SetScript = function(s, name, fn) s.__scripts[name] = fn and { fn } or nil end,
    HookScript = function(s, name, fn)
        s.__scripts[name] = s.__scripts[name] or {}
        table.insert(s.__scripts[name], fn)
    end,
    GetScript = function(s, name) return s.__scripts[name] and s.__scripts[name][1] end,
    RegisterEvent = function(s, event)
        M.eventRegistry[event] = M.eventRegistry[event] or {}
        table.insert(M.eventRegistry[event], s)
    end,
    UnregisterEvent = function(s, event)
        local list = M.eventRegistry[event]
        if list then for i = #list, 1, -1 do if list[i] == s then table.remove(list, i) end end end
    end,
    Show = function(s)
        if Blocked(s, "Show") then return end
        local was = s.__shown
        s.__shown = true
        if not was then RunScript(s, "OnShow") end
    end,
    Hide = function(s)
        if Blocked(s, "Hide") then return end
        local was = s.__shown
        s.__shown = false
        if was then RunScript(s, "OnHide") end
    end,
    SetShown = function(s, v) if v then s:Show() else s:Hide() end end,
    IsShown = function(s) return s.__shown end,
    IsVisible = function(s) return Visible(s) end,
    SetSize = function(s, w, h) if Blocked(s, "SetSize") then return end s.__w, s.__h = w, h end,
    SetWidth = function(s, w) if Blocked(s, "SetWidth") then return end s.__w = w end,
    SetHeight = function(s, h) if Blocked(s, "SetHeight") then return end s.__h = h end,
    GetWidth = function(s) return Resolve(s).w end,
    GetHeight = function(s) return Resolve(s).h end,
    GetLeft = function(s) return Resolve(s).l end,
    GetBottom = function(s) return Resolve(s).b end,
    GetTop = function(s) local r = Resolve(s) return r.b + r.h end,
    GetRight = function(s) local r = Resolve(s) return r.l + r.w end,
    GetStringHeight = function(s)
        local tw, size = TextSize(s)
        local width = s.__w or tw
        if width <= 0 then width = tw end
        local lines = (s.__nowrap or tw <= width) and 1 or math.ceil(tw / width)
        return size * 1.2 * math.max(1, lines)
    end,
    GetStringWidth = function(s) return (TextSize(s)) end,
    SetWordWrap = function(s, v) s.__nowrap = not v end,
    SetPoint = function(s, point, rel, relPoint, x, y)
        if Blocked(s, "SetPoint") then return end
        if type(rel) == "number" then rel, relPoint, x, y = nil, nil, rel, relPoint
        elseif type(relPoint) == "number" then relPoint, x, y = nil, relPoint, x end
        if type(rel) == "string" then rel = _G[rel] end
        s.__points = rawget(s, "__points") or {}
        table.insert(s.__points, { point = point, rel = rel, relPoint = relPoint, x = x, y = y })
        if rawget(s, "__protected") and type(rel) == "table" then rel.__protected = true end
    end,
    ClearAllPoints = function(s)
        if Blocked(s, "ClearAllPoints") then return end
        s.__points = {}
        s.__allPoints = nil
    end,
    SetAllPoints = function(s, target)
        if Blocked(s, "SetAllPoints") then return end
        s.__allPoints = target or true
        if rawget(s, "__protected") and type(target) == "table" then target.__protected = true end
    end,
    GetPoint = function(s, i)
        local p = (rawget(s, "__points") or {})[i or 1]
        if not p then return nil end
        return p.point, p.rel, p.relPoint or p.point, p.x or 0, p.y or 0
    end,
    SetScale = function(s, v) if Blocked(s, "SetScale") then return end s.__scale = v end,
    GetScale = function(s) return s.__scale or 1 end,
    GetEffectiveScale = function(s)
        local scale, w = 1, s
        while type(w) == "table" do scale = scale * (w.__scale or 1) w = rawget(w, "__parent") end
        return scale
    end,
    SetBackdrop = function(s, bd) s.__backdrop = bd end,
    SetBackdropColor = function(s, r, g, b, a) s.__bdcolor = { r, g, b, a } end,
    SetBackdropBorderColor = function(s, r, g, b, a) s.__bdborder = { r, g, b, a } end,
    SetText = function(s, text) s.__text = text end,
    GetText = function(s) return s.__text or "" end,
    SetFormattedText = function(s, fmt, ...) s.__text = string.format(fmt, ...) end,
    SetTextColor = function(s, r, g, b, a) s.__color = { r, g, b, a } end,
    SetVertexColor = function(s, r, g, b, a) s.__color = { r, g, b, a } end,
    SetColorTexture = function(s, r, g, b, a) s.__color = { r, g, b, a } s.__texture = "COLOR" end,
    SetTexture = function(s, tex) s.__texture = tex end,
    GetTexture = function(s) return s.__texture end,
    SetDesaturated = function(s, v) s.__desat = v and true or false end,
    SetAlpha = function(s, a) s.__alpha = a end,
    GetAlpha = function(s) return s.__alpha or 1 end,
    SetFontObject = function(s, font)
        local name = type(font) == "string" and font or (type(font) == "table" and font.__name)
        s.__font = { "Fonts\\FRIZQT__.TTF", FONT_SIZE[name or ""] or 10, "" }
    end,
    SetFont = function(s, path, size, flags) s.__font = { path, size, flags } end,
    GetFont = function(s) local f = s.__font or { "Fonts\\FRIZQT__.TTF", 10, "" } return f[1], f[2], f[3] end,
    SetJustifyH = function(s, v) s.__justify = v end,
    SetFrameStrata = function(s, v) s.__strata = v end,
    GetFrameStrata = function(s) return s.__strata or "MEDIUM" end,
    SetFrameLevel = function(s, v) s.__level = v end,
    GetFrameLevel = function(s) return s.__level or 2 end,
    SetChecked = function(s, v) s.__checked = v and true or false end,
    GetChecked = function(s) return s.__checked end,
    GetName = function(s) return s.__name end,
    GetParent = function(s) return rawget(s, "__parent") end,
    SetEnabled = function(s, v) s.__enabled = v and true or false end,
    Enable = function(s) s.__enabled = true end,
    Disable = function(s) s.__enabled = false end,
    IsEnabled = function(s) return s.__enabled ~= false end,
    SetAttribute = function(s, k, v)
        if M.combat and rawget(s, "__protected") then
            M.blockedCalls[#M.blockedCalls + 1] = (s.__name or "?") .. ":SetAttribute"
            return
        end
        s.__attrs = s.__attrs or {}
        s.__attrs[k] = v
    end,
    GetAttribute = function(s, k) return s.__attrs and s.__attrs[k] end,
    SetVerticalScroll = function(s, v)
        s.__vscroll = v
        RunScript(s, "OnVerticalScroll", v)
    end,
    GetVerticalScroll = function(s) return s.__vscroll or 0 end,
    GetVerticalScrollRange = function(s)
        local child = rawget(s, "__child")
        if not child then return 0 end
        return math.max(0, (child.__h or 0) - Resolve(s).h)
    end,
    SetScrollChild = function(s, child) s.__child = child child.__scroller = s end,
    IsProtected = function(s) return rawget(s, "__protected") and true or false, false end,
    SetCooldown = function(s, start, duration) s.__cdStart, s.__cdDuration = start, duration end,
    SetHideCountdownNumbers = function(s, v) s.__cdNoNumbers = v end,
    LockHighlight = function(s) s.__lockedHighlight = true end,
    UnlockHighlight = function(s) s.__lockedHighlight = false end,
    Click = function(s, button) RunScript(s, "OnClick", button or "LeftButton") end,
    SetHighlightTexture = function(s, t) s.__highlight = t end,
    GetFontString = function(s)
        if not s.__fs then s.__fs = NewWidget("FontString") s.__fs.__parent = s end
        return s.__fs
    end,
    CreateTexture = function(s, name, layer, template, sublevel)
        local t = NewWidget("Texture", name)
        t.__parent = s
        t.__layer = layer
        t.__sublevel = sublevel
        return t
    end,
    CreateFontString = function(s, name, layer, template)
        local t = NewWidget("FontString", name)
        t.__parent = s
        t.__layer = layer
        t:SetFontObject(template or "GameFontNormalSmall")
        return t
    end,
    -- Tooltips (a GameTooltipTemplate frame, or GameTooltip itself)
    SetOwner = function(s, owner) s.__owner = owner s.__lines = {} end,
    SetSpellByID = function(s, id) s.__spell = id s.__lines = { "spell:" .. tostring(id) } s.__h = s.__h or 90 s.__w = s.__w or 260 end,
    SetSpellBookItem = function(s, slot, book) s.__spell = book .. ":" .. slot s.__lines = { "book:" .. book .. ":" .. slot } return true end,
    SetHyperlink = function(s, link) s.__spell = link end,
    AddLine = function(s, text) s.__lines = s.__lines or {} s.__lines[#s.__lines + 1] = text end,
    AddDoubleLine = function(s, a, b) s.__lines = s.__lines or {} s.__lines[#s.__lines + 1] = tostring(a) .. " = " .. tostring(b) end,
    GetOwner = function(s) return s.__owner end,
    NumLines = function(s) return #(s.__lines or {}) end,
}

-- Anything else a widget is asked to DO is accepted and ignored; a property
-- (frame.Text, frame.ScrollBar) that was never set is nil, as in the client
local VERBS = { "Set", "Get", "Is", "Can", "Enable", "Disable", "Register", "Unregister", "Hook",
    "Clear", "Create", "Show", "Hide", "Raise", "Lower", "Start", "Stop", "Add", "Lock", "Unlock",
    "Play", "Update", "Refresh", "Toggle", "Has", "Apply", "Fade", "Insert", "Highlight" }

local function IsVerb(key)
    for _, verb in ipairs(VERBS) do
        if key:sub(1, #verb) == verb then return true end
    end
    return false
end

WidgetMT.__index = function(self, key)
    if type(key) ~= "string" then return nil end
    local fn = METHODS[key]
    if fn then return Method(self, key, fn) end
    if IsVerb(key) then return Method(self, key, function() end) end
    return nil
end

NewWidget = function(kind, name)
    local w = setmetatable({ __kind = kind, __name = name, __scripts = {}, __shown = true }, WidgetMT)
    M.widgets[#M.widgets + 1] = w
    return w
end

M.NewWidget = NewWidget

function CreateFrame(frameType, name, parent, template)
    local f = NewWidget(frameType, name)
    f.__template = template
    if type(parent) == "string" then parent = _G[parent] end
    f.__parent = parent
    if template and template:find("Secure") then
        local p = f
        while type(p) == "table" and p.__name ~= "UIParent" do
            p.__protected = true
            p = rawget(p, "__parent")
        end
    end
    if template and template:find("BasicFrameTemplate") then
        f.CloseButton = NewWidget("Button")
        f.TitleText = NewWidget("FontString")
        f.TitleText.__parent = f
    end
    if template and template:find("UIPanelScrollFrameTemplate") and name then
        _G[name .. "ScrollBar"] = NewWidget("Slider", name .. "ScrollBar")
        _G[name .. "ScrollBarScrollUpButton"] = NewWidget("Button")
        _G[name .. "ScrollBarScrollDownButton"] = NewWidget("Button")
    end
    if frameType == "EditBox" then f.__text = "" end
    if frameType == "CheckButton" or (template and template:find("CheckButton")) then
        f.Text = NewWidget("FontString")
        f.Text.__parent = f
    end
    if name then _G[name] = f end
    return f
end

UIParent = NewWidget("Frame", "UIParent")
UIParent.__scale = 1
GameTooltip = NewWidget("GameTooltip", "GameTooltip")
WorldFrame = NewWidget("Frame", "WorldFrame")
UISpecialFrames = {}
tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack
strsplit = function(sep, str)
    local out = {}
    for piece in string.gmatch(str, "([^" .. sep .. "]+)") do out[#out + 1] = piece end
    return unpack(out)
end

for name in pairs(FONT_SIZE) do
    _G[name] = NewWidget("Font", name)
end

SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2,
    IG_SPELLBOOK_OPEN = 3, IG_SPELLBOOK_CLOSE = 4 }
M.sounds = {}
function PlaySound(id) M.sounds[#M.sounds + 1] = id end
BACKDROP_SLIDER_8_8 = {}

function hooksecurefunc(a, b, c)
    local target, name, hook
    if type(a) == "table" then target, name, hook = a, b, c else target, name, hook = _G, a, b end
    local original = target[name]
    target[name] = function(...)
        local r = { original(...) }
        hook(...)
        return unpack(r)
    end
end

-- Settings API
M.categories = {}
Settings = {
    RegisterCanvasLayoutCategory = function(panel, title)
        local cat = { __panel = panel, __title = title, GetID = function() return #M.categories + 1 end }
        M.categories[#M.categories + 1] = cat
        return cat
    end,
    RegisterCanvasLayoutSubcategory = function(parent, panel, title)
        local cat = { __panel = panel, __title = title, GetID = function() return #M.categories + 1 end }
        M.categories[#M.categories + 1] = cat
        return cat
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
}
C_AddOns = { GetAddOnMetadata = function() return "1.0.0" end }

-- Timers: After queues, Flush runs everything due (and what that queues)
M.timers = {}
C_Timer = {
    After = function(delay, fn) M.timers[#M.timers + 1] = { at = M.now + delay, fn = fn } end,
    NewTicker = function(interval, fn) return { Cancel = function() end } end,
}
function RunNextFrame(fn) C_Timer.After(0, fn) end

-- Let time pass until nothing is waiting: each round moves the clock on by
-- `seconds` and runs what is due, so a timer queued by a timer (a scan's
-- result asking for a repaint) runs in the same Flush
function M.Flush(seconds)
    for _ = 1, 20 do
        M.now = M.now + (seconds or 1)
        local due, keep = {}, {}
        for _, t in ipairs(M.timers) do
            if t.at <= M.now then due[#due + 1] = t else keep[#keep + 1] = t end
        end
        M.timers = keep
        for _, t in ipairs(due) do t.fn() end
        if #M.timers == 0 then break end
    end
end

-- Dropdowns
M.dropdownInits = {}
function UIDropDownMenu_Initialize(frame, fn) M.dropdownInits[frame] = fn end
function UIDropDownMenu_CreateInfo() return {} end
M.menuCaptured = {}
function UIDropDownMenu_AddButton(info) M.menuCaptured[#M.menuCaptured + 1] = info end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetSelectedValue() end
function UIDropDownMenu_SetText() end
function UIDropDownMenu_EnableDropDown() end
function UIDropDownMenu_DisableDropDown() end

function GetCursorPosition() return 0, 0 end
function IsShiftKeyDown() return M.shift == true end
function IsControlKeyDown() return M.ctrl == true end
function IsAltKeyDown() return false end
SlashCmdList = {}
RAID_CLASS_COLORS = { PRIEST = { r = 1, g = 1, b = 1 } }

function GetCoinTextureString(copper)
    local g = math.floor(copper / 10000)
    local s = math.floor(copper / 100) % 100
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

-- Fire an event at every frame registered for it
function M.Fire(event, ...)
    for _, f in ipairs(M.eventRegistry[event] or {}) do
        RunScript(f, "OnEvent", event, ...)
    end
end

return M
