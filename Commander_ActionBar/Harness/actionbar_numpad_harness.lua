-- Commander Action Bar numpad harness (luajit).
--
-- Loads the REAL shared framework (CommanderSettingsUI.lua, CommanderEvents.lua)
-- plus both Commander_ActionBar files under a WoW mock that models the parts
-- the numpad card lives or dies by: anchors, parents and visibility, secure
-- attributes, the combat lockdown (any protected call on a protected frame in
-- combat is recorded as a violation), override bindings, and a key press
-- reaching a button through its binding the way the client delivers it.
--
-- Run:  /opt/homebrew/bin/luajit actionbar_numpad_harness.lua
-- Prints only failures; exits non-zero if there were any.

local ADDONS = "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail ~= nil and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end
local function NEAR(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.01 end

-- ===========================================================================
-- WoW mock
-- ===========================================================================

local now = 1000000
function time() return now end
function GetTime() return now - 999000 end
function GetBuildInfo() return "2.5.6", "68502", "Jul 7 2026", 20506 end

local printLog = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    printLog[#printLog + 1] = table.concat(parts, " ")
end

local luaErrors = {}
function geterrorhandler()
    return function(err) luaErrors[#luaErrors + 1] = tostring(err) end
end

-- Combat lockdown and what breaking it looks like
local combat = false
function InCombatLockdown() return combat end
local violations = {}
local function Violation(what) violations[#violations + 1] = what end

local eventRegistry = {}
local allFrames = {}

-- A protected frame: built from a secure template, an ancestor of one, or an
-- anchor target of one (the protected anchor family). Regions never are.
local function IsProtected(f)
    return f.__isFrame and (f.__secure or f.__secureDesc or f.__anchorFamily) and true or false
end
local function MarkUp(f, field)
    local p = f
    while p do
        p[field] = true
        p = p.__parent
    end
end
local function Guard(f, method)
    if combat and IsProtected(f) then
        Violation((f.__name or f.__kind or "?") .. ":" .. method)
    end
end

local W = {}
local WidgetMT = {
    __index = function(self, key)
        local m = W[key]
        if m then return m end
        if type(key) == "string" and key:match("^[A-Z]") then
            return function() end   -- permissive no-op for anything unmodelled
        end
        return nil
    end,
}

local function NewRegion(kind, parent)
    local r = setmetatable({ __kind = kind, __parent = parent, __shown = true, __points = {},
        __scripts = {}, __w = 0, __h = 0 }, WidgetMT)
    return r
end

local function NewFrame(kind, name, parent)
    local f = setmetatable({
        __kind = kind, __name = name, __parent = parent, __isFrame = true,
        __shown = true, __points = {}, __scripts = {}, __attrs = {},
        __w = 0, __h = 0, __scale = 1, __alpha = 1, __mouse = false,
        __strata = parent and parent.__strata or "MEDIUM",
        __level = parent and ((parent.__level or 0) + 1) or 1,
        __children = {},
    }, WidgetMT)
    if parent and parent.__children then table.insert(parent.__children, f) end
    allFrames[#allFrames + 1] = f
    return f
end

-- Geometry and hierarchy
function W.SetPoint(self, point, relTo, relPoint, x, y)
    Guard(self, "SetPoint")
    if type(relTo) == "number" then
        x, y, relTo, relPoint = relTo, relPoint, self.__parent, point
    elseif type(relTo) == "string" then
        relTo = _G[relTo]
    end
    if relTo == nil and relPoint == nil then relTo = self.__parent end
    if type(relPoint) ~= "string" then
        if type(relPoint) == "number" then x, y = relPoint, x end
        relPoint = point
    end
    for i = #self.__points, 1, -1 do
        if self.__points[i][1] == point then table.remove(self.__points, i) end
    end
    table.insert(self.__points, { point, relTo, relPoint, x or 0, y or 0 })
    if IsProtected(self) and type(relTo) == "table" and relTo.__isFrame then
        MarkUp(relTo, "__anchorFamily")
    end
end
function W.ClearAllPoints(self) Guard(self, "ClearAllPoints"); self.__points = {} end
function W.SetAllPoints(self, rel)
    Guard(self, "SetAllPoints")
    rel = rel or self.__parent
    self.__points = { { "TOPLEFT", rel, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0 } }
end
function W.GetPoint(self, i)
    local p = self.__points[i or 1]
    if not p then return nil end
    return p[1], p[2], p[3], p[4], p[5]
end
function W.GetNumPoints(self) return #self.__points end
function W.GetParent(self) return self.__parent end
function W.SetParent(self, p)
    Guard(self, "SetParent")
    if self.__parent and self.__parent.__children then
        for i, c in ipairs(self.__parent.__children) do
            if c == self then table.remove(self.__parent.__children, i) break end
        end
    end
    self.__parent = p
    if p and p.__children then table.insert(p.__children, self) end
end
function W.SetSize(self, w, h) Guard(self, "SetSize"); self.__w, self.__h = w, h end
function W.SetWidth(self, w) Guard(self, "SetWidth"); self.__w = w end
function W.SetHeight(self, h) Guard(self, "SetHeight"); self.__h = h end
function W.GetWidth(self) return self.__w or 0 end
function W.GetHeight(self) return self.__h or 0 end
function W.GetSize(self) return self.__w or 0, self.__h or 0 end
function W.SetScale(self, s) Guard(self, "SetScale"); self.__scale = s end
function W.GetScale(self) return self.__scale or 1 end
function W.GetEffectiveScale(self) return self.__scale or 1 end
function W.SetAlpha(self, a) self.__alpha = a end
function W.GetAlpha(self) return self.__alpha or 1 end
function W.SetFrameStrata(self, s) Guard(self, "SetFrameStrata"); self.__strata = s end
function W.GetFrameStrata(self) return self.__strata or "MEDIUM" end
function W.SetFrameLevel(self, l) Guard(self, "SetFrameLevel"); self.__level = l end
function W.GetFrameLevel(self) return self.__level or 1 end
function W.GetLeft() return 0 end
function W.GetRight() return 0 end
function W.GetTop() return 0 end
function W.GetBottom() return 0 end
function W.GetVerticalScroll() return 0 end
function W.GetVerticalScrollRange() return 0 end
function W.GetStringHeight() return 12 end
function W.GetStringWidth() return 40 end
function W.GetID(self) return self.__id or 0 end
function W.GetName(self) return self.__name end
function W.GetObjectType(self) return self.__kind end
function W.IsProtected(self) return IsProtected(self), self.__secure and true or false end

-- Visibility
function W.Show(self)
    Guard(self, "Show")
    self.__shown = true
    if self.__scripts.OnShow then self.__scripts.OnShow(self) end
end
function W.Hide(self) Guard(self, "Hide"); self.__shown = false end
function W.SetShown(self, v) if v then self:Show() else self:Hide() end end
function W.IsShown(self) return self.__shown and true or false end
function W.IsVisible(self)
    local p = self
    while p do
        if not p.__shown then return false end
        p = p.__parent
    end
    return true
end

-- Scripts, events, attributes, mouse
function W.SetScript(self, name, fn) self.__scripts[name] = fn end
function W.GetScript(self, name) return self.__scripts[name] end
function W.HookScript(self, name, fn)
    local prev = self.__scripts[name]
    if prev then
        self.__scripts[name] = function(...) prev(...); fn(...) end
    else
        self.__scripts[name] = fn
    end
end
function W.RegisterEvent(self, event)
    eventRegistry[event] = eventRegistry[event] or {}
    table.insert(eventRegistry[event], self)
end
W.RegisterUnitEvent = W.RegisterEvent
function W.UnregisterEvent(self, event)
    local list = eventRegistry[event]
    if not list then return end
    for i = #list, 1, -1 do if list[i] == self then table.remove(list, i) end end
end
function W.SetAttribute(self, name, value)
    Guard(self, "SetAttribute")
    self.__attrs[name] = value
    if self.__scripts.OnAttributeChanged then self.__scripts.OnAttributeChanged(self, name, value) end
end
function W.GetAttribute(self, name) return self.__attrs[name] end
function W.EnableMouse(self, v) Guard(self, "EnableMouse"); self.__mouse = v and true or false end
function W.IsMouseEnabled(self) return self.__mouse end
function W.SetMovable(self, v) self.__movable = v end
function W.IsMovable(self) return self.__movable end
function W.RegisterForDrag(self, ...) self.__drag = { ... } end
function W.RegisterForClicks(self, ...) Guard(self, "RegisterForClicks"); self.__clicks = { ... } end
function W.StartMoving(self) Guard(self, "StartMoving"); self.__moving = true end
function W.StopMovingOrSizing(self) self.__moving = false end

-- Region creation and content
function W.CreateTexture(self) return NewRegion("Texture", self) end
function W.CreateFontString(self) return NewRegion("FontString", self) end
function W.SetText(self, t) self.__text = t end
function W.GetText(self) return self.__text end
function W.SetFont(self, path, size, flags) self.__font = { path, size, flags } end
function W.GetFont(self) local f = self.__font or { "Fonts\\FRIZQT__.TTF", 12, "" } return f[1], f[2], f[3] end
function W.SetColorTexture(self, r, g, b, a) self.__colorTex = { r, g, b, a } end
function W.SetVertexColor(self, r, g, b, a) self.__vertex = { r, g, b, a } end
function W.SetTexture(self, t) self.__texture = t end
function W.GetDrawLayer() return "ARTWORK", 0 end
function W.SetChecked(self, v) self.__checked = v and true or false end
function W.GetChecked(self) return self.__checked end
function W.SetBackdrop(self, t) self.__backdrop = t end
function W.SetBackdropColor(self, ...) self.__bdColor = { ... } end
function W.SetBackdropBorderColor(self, ...) self.__bdBorder = { ... } end
function W.GetNormalTexture(self) return self.__normal end
function W.GetPushedTexture(self) return self.__pushed end
function W.GetHighlightTexture(self) return self.__highlight end
function W.GetCheckedTexture(self) return self.__checkedTex end
function W.GetThumbTexture() return NewRegion("Texture") end

-- Templates ---------------------------------------------------------------
RANGE_INDICATOR = "\226\151\143"

-- Blizzard's ActionBarButtonTemplate, as far as this addon touches it: an
-- ID-0 button reads its slot from the "action" attribute; UpdateHotkeys on a
-- button with no binding command blanks the hotkey to the range dot
local function MakeActionButton(f)
    f.__w, f.__h = 36, 36
    f.icon = NewRegion("Texture", f)
    f.Name = NewRegion("FontString", f)
    f.Count = NewRegion("FontString", f)
    f.HotKey = NewRegion("FontString", f)
    f.cooldown = NewFrame("Cooldown", nil, f)
    f.__normal = NewRegion("Texture", f)
    f.__normal.__w, f.__normal.__h = 66, 66
    f.__pushed = NewRegion("Texture", f)
    f.__highlight = NewRegion("Texture", f)
    f.__checkedTex = NewRegion("Texture", f)
    f.action = f.__id and f.__id > 0 and f.__id or 1
    f.__clicks = { "AnyUp", "LeftButtonDown", "RightButtonDown" }
    f.UpdateHotkeys = function(self)
        self.HotKey:SetText(RANGE_INDICATOR)
        self.HotKey:Hide()
    end
    f.__scripts.OnAttributeChanged = function(self, name, value)
        if name == "action" then self.action = value end
    end
end

-- The bare SecureActionButtonTemplate OnClick: SecureActionButton_OnClick with
-- no isKeyPress/isSecureAction, so it honours ActionButtonUseKeyDown
local cvars = { ActionButtonUseKeyDown = "1" }
function GetCVarBool(name) return cvars[name] == "1" end
function GetCVar(name) return cvars[name] end
local usedActions = {}
local function SecureOnClick(self, button, down)
    local useDown = GetCVarBool("ActionButtonUseKeyDown")
    if (down and useDown) or (not down and not useDown) then
        if self:GetAttribute("type") == "action" then
            usedActions[#usedActions + 1] = self:GetAttribute("action")
        end
    end
end

function CreateFrame(frameType, name, parent, template)
    template = template or ""
    local secure = template:find("SecureActionButtonTemplate") or template:find("ActionBarButtonTemplate")
    if secure and combat then
        Violation("CreateFrame(" .. template .. ") in combat: " .. tostring(name))
    end
    local f = NewFrame(frameType, name, parent)
    if secure then
        f.__secure = true
        MarkUp(f, "__secureDesc")
    end
    if template:find("ActionBarButtonTemplate") then
        MakeActionButton(f)
    elseif template:find("SecureActionButtonTemplate") then
        f.__scripts.OnClick = SecureOnClick
    end
    if frameType == "CheckButton" or template:find("CheckButton") then
        f.Text = NewRegion("FontString", f)
    end
    if name then _G[name] = f end
    return f
end

-- Override bindings and a key press arriving through one
local overrideBindings = {}
local bindWrites = 0
function SetOverrideBindingClick(owner, isPriority, key, buttonName, mouse)
    if combat then Violation("SetOverrideBindingClick in combat") end
    bindWrites = bindWrites + 1
    overrideBindings[key] = { owner = owner, button = buttonName, mouse = mouse or "LeftButton" }
end
function ClearOverrideBindings(owner)
    if combat then Violation("ClearOverrideBindings in combat") end
    bindWrites = bindWrites + 1
    for k, b in pairs(overrideBindings) do
        if b.owner == owner then overrideBindings[k] = nil end
    end
end
local function BoundKeys()
    local list = {}
    for k in pairs(overrideBindings) do list[#list + 1] = k end
    table.sort(list)
    return list
end
-- The client delivers a CLICK binding as a click on that button, down and
-- up, each only if the button registered for that phase
local function PressKey(key, down)
    local b = overrideBindings[key]
    if not b then return false end
    local btn = _G[b.button]
    if not btn then return false end
    local phase = b.mouse .. (down and "Down" or "Up")
    local registered = false
    for _, p in ipairs(btn.__clicks or {}) do
        if p == phase or (p == "AnyDown" and down) or (p == "AnyUp" and not down) then registered = true end
    end
    if not registered then return false end
    if btn.__scripts.OnClick then btn.__scripts.OnClick(btn, b.mouse, down) end
    if btn.__scripts.PostClick then btn.__scripts.PostClick(btn, b.mouse, down) end
    return true
end

function hooksecurefunc(a, b, c)
    local target, name, post = a, b, c
    if type(a) == "string" then target, name, post = _G, a, b end
    local original = target[name]
    target[name] = function(...)
        local r1, r2, r3 = original(...)
        post(...)
        return r1, r2, r3
    end
end

-- Globals the framework and the addon read
UIParent = NewFrame("Frame", "UIParent", nil)
GameTooltip = NewFrame("GameTooltip", "GameTooltip", UIParent)
SlashCmdList = {}
tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack
debugstack = function() return "stack" end
GameFontNormal, GameFontHighlight, GameFontHighlightSmall, GameFontDisableSmall =
    NewRegion("Font"), NewRegion("Font"), NewRegion("Font"), NewRegion("Font")
SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2 }
function PlaySound() end
BACKDROP_SLIDER_8_8 = {}
C_AddOns = { GetAddOnMetadata = function() return "2.2.0" end }
function GetCursorPosition() return 0, 0 end
function GetCursorInfo() return nil end
function MouseIsOver() return false end
function UnitClass() return "Priest", "PRIEST" end
function UnitFactionGroup() return "Alliance" end
function UnitRace() return "Human", "Human" end
RAID_CLASS_COLORS = { PRIEST = { r = 1, g = 1, b = 1 } }
CLASS_ICON_TCOORDS = { PRIEST = { 0.5, 0.75, 0.25, 0.5 } }

local actionSlots = {}   -- slot -> true when something is on it
function HasAction(slot) return actionSlots[slot] and true or false end
function GetActionCooldown() return 0, 0 end
function IsUsableAction() return true, false end
function IsActionInRange() return nil end

local timers = {}
C_Timer = {
    After = function(delay, fn) timers[#timers + 1] = fn end,
    NewTicker = function(interval, fn) return { Cancel = function() end } end,
}

-- Settings
local panelsByTitle = {}
local nextCategory = 0
local function Category(panel, title)
    nextCategory = nextCategory + 1
    local id = nextCategory
    if panel and title then panelsByTitle[title] = panel end
    return { GetID = function() return id end }
end
Settings = {
    RegisterCanvasLayoutCategory = Category,
    RegisterCanvasLayoutSubcategory = function(parent, panel, title) return Category(panel, title) end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
    GetValue = function() return true end,
}

-- Dropdowns: capture the initializer per frame so a test can pick an option
local dropdownInits, menu = {}, {}
function UIDropDownMenu_Initialize(frame, fn) dropdownInits[frame] = fn end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info) menu[#menu + 1] = info end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetSelectedValue() end
function UIDropDownMenu_SetText() end
function UIDropDownMenu_EnableDropDown() end
function UIDropDownMenu_DisableDropDown() end
local function OpenDropdown(frame)
    menu = {}
    dropdownInits[frame](frame)
    return menu
end
local function PickOption(frame, value)
    for _, info in ipairs(OpenDropdown(frame)) do
        if info.value == value then
            info.func({ value = value })
            return true
        end
    end
    return false
end

-- Blizzard's bars and satellites -------------------------------------------
local function BarOfButtons(barName, buttonPrefix, firstSlot)
    local bar = CreateFrame("Frame", barName, UIParent)
    for i = 1, 12 do
        local b = CreateFrame("CheckButton", buttonPrefix .. i, bar, "ActionBarButtonTemplate")
        b.action = firstSlot + i - 1
        b.__id = i
    end
    return bar
end
MainActionBar = BarOfButtons("MainActionBar", "ActionButton", 1)
MainActionBar.ActionBarPageNumber = NewFrame("Frame", nil, MainActionBar)
BarOfButtons("MultiBarBottomLeft", "MultiBarBottomLeftButton", 61)
BarOfButtons("MultiBarBottomRight", "MultiBarBottomRightButton", 49)
BarOfButtons("MultiBarRight", "MultiBarRightButton", 25)
BarOfButtons("MultiBarLeft", "MultiBarLeftButton", 37)
PetActionBar = CreateFrame("Frame", "PetActionBar", UIParent)
for i = 0, 3 do
    local slot = CreateFrame("CheckButton", "CharacterBag" .. i .. "Slot", UIParent, "SecureActionButtonTemplate")
    slot.__scripts.OnClick = nil
end
CreateFrame("Button", "KeyRingButton", UIParent)
CreateFrame("Button", "MainMenuBarBackpackButton", UIParent)

-- ===========================================================================
-- Load the real framework + addon
-- ===========================================================================
local function Load(path) assert(loadfile(path))() end
Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
Load(ADDONS .. "/Commander_ActionBar/CommanderActionBarDB.lua")
Load(ADDONS .. "/Commander_ActionBar/CommanderActionBar.lua")

local function Fire(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    for _, f in ipairs({ unpack(list) }) do
        if f.__scripts.OnEvent then f.__scripts.OnEvent(f, event, ...) end
    end
end

Fire("ADDON_LOADED", "Commander_ActionBar")
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD")

-- The poll frame is the one frame that listens for combat starting
local poll
for _, f in ipairs(eventRegistry.PLAYER_REGEN_DISABLED or {}) do
    if f.__scripts.OnUpdate then poll = f end
end
local function Tick(n)
    for _ = 1, n or 1 do poll.__scripts.OnUpdate(poll, 0.3) end
end
local function Notify() Commander.Notify(COMMANDER_ACTIONBAR_EVENTS.UPDATE) end
local function EnterCombat() combat = true; Fire("PLAYER_REGEN_DISABLED") end
local function LeaveCombat() combat = false; Fire("PLAYER_REGEN_ENABLED") end

local db = CommanderActionBarDB
local backdrop = _G.RTSActionBarBackdrop

-- Helpers over the settings pages
local function Descends(f, root)
    local p = f
    while p do
        if p == root then return true end
        p = p.__parent
    end
    return false
end
local function FindCheckbox(panel, label)
    for _, f in ipairs(allFrames) do
        if f.__kind == "CheckButton" and f.Text and f.Text.__text == label and Descends(f, panel) then
            return f
        end
    end
end
local function ClickCheckbox(check)
    check:SetChecked(not check:GetChecked())
    check.__scripts.OnClick(check)
end
local function FindDropdowns(panel, withValue)
    local found = {}
    for _, f in ipairs(allFrames) do
        if dropdownInits[f] and Descends(f, panel) then
            for _, info in ipairs(OpenDropdown(f)) do
                if info.value == withValue then found[#found + 1] = f break end
            end
        end
    end
    -- creation order
    return found
end
local function FindButton(panel, text)
    for _, f in ipairs(allFrames) do
        if f.__kind == "Button" and f.__text == text and Descends(f, panel) then return f end
    end
end
local function Point(f, i)
    local p = f.__points[i or 1]
    if not p then return {} end
    return { point = p[1], rel = p[2], relPoint = p[3], x = p[4], y = p[5] }
end

-- ===========================================================================
-- A. Login with the numpad off: nothing built, nothing bound, grid intact
-- ===========================================================================
CHECK(#luaErrors == 0, "login clean", luaErrors[1])
CHECK(#violations == 0, "login: no protected calls in combat", violations[1])
CHECK(backdrop ~= nil, "grid card exists")
CHECK(db.numpadEnabled == false and db.numpadBindKeys == true and db.numpadLayout == "APPLE"
    and db.numpadFunctionRow == false and db.numpadScale == 1
    and db.numpadAnchor == "RIGHT" and db.numpadDigitsBar == "BOTTOMRIGHT"
    and db.numpadOpsBar == "LEFT" and db.numpadNumLock == false, "numpad defaults applied")
CHECK(_G.CommanderActionBarNumpad == nil, "numpad card not built while off")
CHECK(_G.CommanderNumpadButton7 == nil, "no numpad buttons while off")
CHECK(#BoundKeys() == 0, "no override bindings while off")
CHECK(MultiBarBottomRight:GetParent() == UIParent, "bottom-right bar left alone while numpad off")
do
    local titles = {}
    for _, info in ipairs(Commander.GetModules()) do titles[info.key] = info.title end
    CHECK(titles.ActionBar and titles.ActionBarButtons and titles.ActionBarNumpad == "Action Bar Numpad",
        "three settings pages registered")
end
do  -- grid regression: slot 1 top-left, slot 13 (bottom-left bar) starts row 3
    local p1, p13 = Point(ActionButton1), Point(MultiBarBottomLeftButton1)
    CHECK(p1.rel == backdrop and p1.point == "TOPLEFT" and NEAR(p1.x, 14) and NEAR(p1.y, -14), "grid button 1 placed", p1.x)
    CHECK(p13.rel == backdrop and NEAR(p13.x, 14) and NEAR(p13.y, -(14 + 2 * 42)), "grid button 13 placed", p13.y)
end

-- ===========================================================================
-- B. Switched on IN COMBAT: nothing secure is built until combat drops
-- ===========================================================================
local numpadPanel = panelsByTitle["Action Bar Numpad"]
CHECK(numpadPanel ~= nil, "numpad page found")
local showBox = FindCheckbox(numpadPanel, "Show Numpad Bar")
CHECK(showBox ~= nil, "Show Numpad Bar checkbox")

EnterCombat()
ClickCheckbox(showBox)
Tick(3)
CHECK(db.numpadEnabled == true, "checkbox wrote the setting")
CHECK(_G.CommanderActionBarNumpad == nil, "numpad not built in combat")
CHECK(#BoundKeys() == 0, "nothing bound in combat")
CHECK(#violations == 0, "enable in combat: no protected calls", violations[1])
LeaveCombat()
Tick()

local card = _G.CommanderActionBarNumpad
CHECK(card ~= nil and card:IsShown(), "numpad built and shown when combat drops")
CHECK(#violations == 0, "build after combat: no violations", violations[1])
CHECK(#luaErrors == 0, "build clean", luaErrors[1])

-- ===========================================================================
-- C. The default keypad is the Mac's: shape, slots, binds, caps
-- ===========================================================================
local KEYS = {
    NUMPAD1 = "1", NUMPAD2 = "2", NUMPAD3 = "3", NUMPAD4 = "4", NUMPAD5 = "5",
    NUMPAD6 = "6", NUMPAD7 = "7", NUMPAD8 = "8", NUMPAD9 = "9", NUMPAD0 = "0",
    NUMPADDECIMAL = "DECIMAL", NUMPADPLUS = "PLUS", NUMPADDIVIDE = "DIVIDE",
    NUMPADMULTIPLY = "MULTIPLY", NUMPADMINUS = "MINUS", NUMPADEQUALS = "EQUALS", NUMLOCK = "NUMLOCK",
    F16 = "F16", F17 = "F17", F18 = "F18", F19 = "F19",
}
local function Face(key) return _G["CommanderNumpadButton" .. KEYS[key]] end
local function Shown(key) local f = Face(key) return f and f:IsShown() end
local function ShownCount()
    local n = 0
    for key in pairs(KEYS) do if Shown(key) then n = n + 1 end end
    return n
end
local function Tall(rows) return rows * 42 - 10 + 28 end

local created = 0
for key in pairs(KEYS) do if Face(key) then created = created + 1 end end
CHECK(created == 21, "every keypad key built once", created)
CHECK(card.__w == 4 * 42 - 10 + 28 and card.__h == Tall(5),
    "Mac pad without its F row is 4x5 keys at grid pitch", card.__w .. "x" .. card.__h)
CHECK(ShownCount() == 16, "Mac pad shows 16 keys", ShownCount())
CHECK(not Shown("NUMLOCK") and not Shown("F16") and not Shown("F19"), "Clear and F16-F19 are opt-in")

-- Cell (col,row) -> TOPLEFT offset at pad 14, pitch 42; spans centre the key
local function At(key, x, y)
    local p = Point(Face(key))
    CHECK(p.rel == card and p.point == "TOPLEFT" and NEAR(p.x, x) and NEAR(p.y, -y),
        key .. " sits at its keypad cell", tostring(p.x) .. "," .. tostring(p.y))
end
-- The unused F row is trimmed off: Clear's row is the top one
At("NUMPADEQUALS", 56, 14); At("NUMPADDIVIDE", 98, 14); At("NUMPADMULTIPLY", 140, 14)
At("NUMPAD7", 14, 56); At("NUMPAD8", 56, 56); At("NUMPAD9", 98, 56); At("NUMPADMINUS", 140, 56)
At("NUMPAD4", 14, 98); At("NUMPAD5", 56, 98); At("NUMPAD6", 98, 98); At("NUMPADPLUS", 140, 98)
At("NUMPAD1", 14, 140); At("NUMPAD2", 56, 140); At("NUMPAD3", 98, 140)
At("NUMPAD0", 14 + 21, 182)                 -- two wide: centred under 1 and 2
At("NUMPADDECIMAL", 98, 182)
CHECK(Face("NUMPAD7").__w == 32 and Face("NUMPAD7").__normal.__w > 32 and Face("NUMPAD7").__normal.__w < 66,
    "keys take the grid's button size, border rescaled", Face("NUMPAD7").__normal.__w)

-- Slots: the number block takes the bottom-right bar, operators Right Bar 2's first slots
local function SlotOf(key)
    local f = Face(key)
    return f:GetAttribute("action"), f.__cmdProxy and f.__cmdProxy:GetAttribute("action"), f.action
end
local expectSlots = {
    NUMPAD1 = 49, NUMPAD5 = 53, NUMPAD9 = 57, NUMPAD0 = 58, NUMPADDECIMAL = 59, NUMPADPLUS = 60,
    NUMPADDIVIDE = 37, NUMPADMULTIPLY = 38, NUMPADMINUS = 39, NUMPADEQUALS = 40,
}
for key, slot in pairs(expectSlots) do
    local face, proxy, live = SlotOf(key)
    CHECK(face == slot and proxy == slot and live == slot, key .. " -> slot " .. slot,
        tostring(face) .. "/" .. tostring(proxy) .. "/" .. tostring(live))
end

-- Binds: exactly the shown keys, each to its key proxy, never Enter or Num Lock
do
    local bound = BoundKeys()
    CHECK(#bound == 16, "16 keys bound", #bound)
    CHECK(overrideBindings.ENTER == nil and overrideBindings.NUMLOCK == nil, "Enter and Clear untouched")
    CHECK(overrideBindings.F16 == nil and overrideBindings.F19 == nil, "F16-F19 untouched by default")
    local b7 = overrideBindings.NUMPAD7
    CHECK(b7 and b7.button == "CommanderNumpadButton7Key" and b7.mouse == "LeftButton", "7 clicks its proxy", b7 and b7.button)
    local proxy = _G.CommanderNumpadButton7Key
    CHECK(proxy and proxy.__secure and proxy:GetAttribute("type") == "action", "proxy is a bare secure action button")
    CHECK(proxy and proxy.__clicks and proxy.__clicks[1] == "AnyDown" and proxy.__clicks[2] == "AnyUp",
        "proxy hears both phases")
    CHECK(proxy and proxy.__mouse == false, "proxy never takes the mouse")
    CHECK(proxy and proxy:GetAttribute("typerelease") == nil, "no press-and-hold release (no ReleaseAction here)")
end

-- Caps on the faces, and they survive Blizzard re-running UpdateHotkeys
Tick()
CHECK(Face("NUMPAD7").HotKey.__text == "7" and Face("NUMPAD7").HotKey.__shown, "7 wears its cap")
CHECK(Face("NUMPADPLUS").HotKey.__text == "+" and Face("NUMPADDIVIDE").HotKey.__text == "/"
    and Face("NUMPADEQUALS").HotKey.__text == "=", "operator caps")
Face("NUMPAD7"):UpdateHotkeys()
CHECK(Face("NUMPAD7").HotKey.__text == "7" and Face("NUMPAD7").HotKey.__shown, "cap restored after UPDATE_BINDINGS")

-- Docked right of the grid, sharing its bottom edge; same stack and framing
do
    local p = Point(card)
    CHECK(p.point == "BOTTOMLEFT" and p.rel == backdrop and p.relPoint == "BOTTOMRIGHT" and NEAR(p.x, 2) and NEAR(p.y, 0),
        "docked right of the card", tostring(p.point) .. " " .. tostring(p.relPoint))
    CHECK(card:GetFrameStrata() == backdrop:GetFrameStrata() and card:GetFrameLevel() == backdrop:GetFrameLevel(),
        "stacks with the grid card")
    CHECK(card.__backdrop ~= nil and card.__backdrop == backdrop.__backdrop, "same card framing as the grid")
    CHECK(card.__mouse == false, "docked numpad does not take the mouse")
end

-- The number block's bar is folded in; the operator bar is not
local hidden = MultiBarBottomRight:GetParent()
CHECK(hidden ~= UIParent and not hidden:IsShown(), "bottom-right bar parked while its slots live on the numpad")
CHECK(MultiBarLeft:GetParent() == UIParent, "operator bar left in place")

-- ===========================================================================
-- D. Key presses go through the proxy and honour ActionButtonUseKeyDown
-- ===========================================================================
for i = #usedActions, 1, -1 do usedActions[i] = nil end
cvars.ActionButtonUseKeyDown = "1"
PressKey("NUMPAD7", true)
CHECK(#usedActions == 1 and usedActions[1] == 55, "key-down mode: 7 fires slot 55 on press", usedActions[1])
CHECK(Face("NUMPAD7").__cmdPress and Face("NUMPAD7").__cmdPress.__shown, "press overlay lit while held")
PressKey("NUMPAD7", false)
CHECK(#usedActions == 1, "key-down mode: release does not fire again", #usedActions)
CHECK(not Face("NUMPAD7").__cmdPress.__shown, "press overlay off on release")
cvars.ActionButtonUseKeyDown = "0"
PressKey("NUMPADDIVIDE", true)
CHECK(#usedActions == 1, "key-up mode: press does not fire", #usedActions)
PressKey("NUMPADDIVIDE", false)
CHECK(#usedActions == 2 and usedActions[2] == 37, "key-up mode: / fires slot 37 on release", usedActions[2])
cvars.ActionButtonUseKeyDown = "1"
CHECK(Face("NUMPAD7").__cmdPress.__colorTex ~= nil, "press overlay wears the pushed-flash colour")

-- Mid-fight: presses, polls and a fade all stay legal
EnterCombat()
PressKey("NUMPAD5", true); PressKey("NUMPAD5", false)
db.oocFade = true
Tick(3)
CHECK(usedActions[#usedActions] == 53, "5 fires in combat")
CHECK(#violations == 0, "combat ticks and presses: no violations", violations[1])
LeaveCombat()
db.oocFade = false
Tick()

-- Fade: out of combat the numpad fades with the grid
db.oocFade = true; db.fadeOpacity = 0.4
Tick()
CHECK(NEAR(card.__alpha, 0.4) and NEAR(backdrop.__alpha, 0.4), "numpad fades with the grid", card.__alpha)
db.hideEmptySlots = true
actionSlots[55] = true
Tick()
CHECK(NEAR(Face("NUMPAD7").__alpha, 1), "a filled key stays at the card's alpha")
CHECK(NEAR(card.__alpha * Face("NUMPAD8").__alpha, 0.15), "an empty key dims to where a grid slot does",
    card.__alpha * Face("NUMPAD8").__alpha)
db.oocFade = false; db.hideEmptySlots = false
Tick()

-- ===========================================================================
-- E. The Mac pad's F16-F19 row and Clear, then the PC pad: shapes change,
-- actions stay on their keys
-- ===========================================================================
local fRowBox = FindCheckbox(numpadPanel, "F16-F19 Row")
CHECK(fRowBox ~= nil, "F16-F19 Row checkbox")
ClickCheckbox(fRowBox)
Tick()
CHECK(db.numpadFunctionRow == true, "F row opted in")
CHECK(card.__h == Tall(6) and ShownCount() == 20, "F row adds a sixth row of four keys", card.__h)
At("F16", 14, 14); At("F17", 56, 14); At("F18", 98, 14); At("F19", 140, 14)
At("NUMPADEQUALS", 56, 56); At("NUMPAD7", 14, 98); At("NUMPAD0", 14 + 21, 224)
CHECK(select(1, SlotOf("F16")) == 42 and select(1, SlotOf("F19")) == 45, "F16-F19 on the operator bar's slots 6-9")
CHECK(select(1, SlotOf("NUMPAD7")) == 55, "7 keeps its slot when the row arrives")
CHECK(#BoundKeys() == 20 and overrideBindings.F16 and overrideBindings.F16.button == "CommanderNumpadButtonF16Key",
    "F16-F19 bound to their proxies", #BoundKeys())
CHECK(Face("F17").HotKey.__text == "F17", "F17 cap")
ClickCheckbox(fRowBox)
Tick()
CHECK(card.__h == Tall(5) and overrideBindings.F16 == nil and not Shown("F16"),
    "F row off: row trimmed, keys given back")

local clearBox = FindCheckbox(numpadPanel, "Clear Key")
ClickCheckbox(clearBox)
Tick()
CHECK(Shown("NUMLOCK") and select(1, SlotOf("NUMLOCK")) == 41, "Clear shown on slot 41")
At("NUMLOCK", 14, 14)
CHECK(overrideBindings.NUMLOCK ~= nil and overrideBindings.ENTER == nil, "Clear bound when opted in; Enter never")
CHECK(Face("NUMLOCK").HotKey.__text == "Clr", "the Mac pad calls it Clear")

local layoutDrop = FindDropdowns(numpadPanel, "STANDARD")[1]
CHECK(layoutDrop ~= nil, "keypad dropdown found")
do
    local first = OpenDropdown(layoutDrop)[1]
    CHECK(first and first.value == "APPLE" and first.text == "Mac", "Mac listed first", first and first.text)
end
ClickCheckbox(fRowBox)          -- on, to prove the PC pad ignores it
EnterCombat()
PickOption(layoutDrop, "STANDARD")
CHECK(db.numpadLayout == "STANDARD", "keypad choice written")
CHECK(Point(Face("NUMPADDIVIDE")).x == 98, "nothing moves in combat")
CHECK(overrideBindings.NUMPADEQUALS ~= nil, "nothing rebinds in combat")
CHECK(#violations == 0, "layout change in combat: no violations", violations[1])
LeaveCombat()
Tick()
CHECK(card.__h == Tall(5) and not Shown("F16") and overrideBindings.F16 == nil, "the PC pad has no F row")
At("NUMLOCK", 14, 14); At("NUMPADDIVIDE", 56, 14); At("NUMPADMULTIPLY", 98, 14); At("NUMPADMINUS", 140, 14)
At("NUMPAD7", 14, 56); At("NUMPAD8", 56, 56); At("NUMPAD9", 98, 56)
At("NUMPADPLUS", 140, 56 + 21)              -- two tall: centred across 7-row and 4-row
At("NUMPAD4", 14, 98); At("NUMPAD1", 14, 140); At("NUMPAD0", 14 + 21, 182); At("NUMPADDECIMAL", 98, 182)
CHECK(not Shown("NUMPADEQUALS") and overrideBindings.NUMPADEQUALS == nil, "no = on the PC pad")
CHECK(select(1, SlotOf("NUMPADDIVIDE")) == 37 and select(1, SlotOf("NUMPADPLUS")) == 60, "/ and + keep their slots across pads")
CHECK(Face("NUMLOCK").HotKey.__text == "Num", "the PC pad calls it Num")
ClickCheckbox(clearBox)
ClickCheckbox(fRowBox)
PickOption(layoutDrop, "APPLE")
Tick()
CHECK(not Shown("NUMLOCK") and overrideBindings.NUMLOCK == nil and #BoundKeys() == 16,
    "back to the default Mac pad, Clear given back", #BoundKeys())

-- ===========================================================================
-- F. Bar choices swap rather than collide
-- ===========================================================================
local barDrops = FindDropdowns(numpadPanel, "PAGE2")
CHECK(#barDrops == 2, "number and operator bar dropdowns", #barDrops)
local digitsDrop, opsDrop = barDrops[1], barDrops[2]
PickOption(digitsDrop, "LEFT")
Tick()
CHECK(db.numpadDigitsBar == "LEFT" and db.numpadOpsBar == "BOTTOMRIGHT", "choosing the operator bar swaps the two")
CHECK(select(1, SlotOf("NUMPAD1")) == 37 and select(1, SlotOf("NUMPADDIVIDE")) == 49, "slots follow the swap")
CHECK(MultiBarLeft:GetParent() ~= UIParent and MultiBarBottomRight:GetParent() == UIParent,
    "the parked bar follows the number block")
PickOption(opsDrop, "PAGE2")
Tick()
CHECK(db.numpadOpsBar == "PAGE2" and db.numpadDigitsBar == "LEFT", "operators to page 2")
CHECK(select(1, SlotOf("NUMPADMINUS")) == 15, "- on page 2's third slot")
-- A bar the grid folds in is never parked from under it
db.includeRightBars = true
Notify(); Tick()
CHECK(MultiBarLeft:GetParent() == UIParent, "grid-owned bar not parked by the numpad")
db.includeRightBars = false
PickOption(digitsDrop, "BOTTOMRIGHT"); PickOption(opsDrop, "LEFT")
Tick()
CHECK(db.numpadDigitsBar == "BOTTOMRIGHT" and db.numpadOpsBar == "LEFT", "back to defaults")

-- ===========================================================================
-- G. Docking: left, free, and the satellites stepping out past it
-- ===========================================================================
db.bagPosition = "CARD"
Notify(); Tick()
do
    local p = Point(CharacterBag0Slot)
    CHECK(p.rel == card and p.relPoint == "BOTTOMRIGHT", "bags beside the card step out past a right-docked numpad")
end
local posDrop = FindDropdowns(numpadPanel, "FREE")[1]
PickOption(posDrop, "LEFT")
db.petBarPosition = "LEFT"
Notify(); Tick()
do
    local p = Point(card)
    CHECK(p.point == "BOTTOMRIGHT" and p.rel == backdrop and p.relPoint == "BOTTOMLEFT" and NEAR(p.x, -2),
        "docked left of the card")
    local pet = Point(PetActionBar)
    CHECK(pet.rel == card and pet.relPoint == "LEFT", "pet bar steps out past a left-docked numpad")
    local bag = Point(CharacterBag0Slot)
    CHECK(bag.rel == backdrop, "bags back beside the grid when the numpad is on the other side")
end
PickOption(posDrop, "FREE")
db.locked = false
Notify(); Tick()
do
    local p = Point(card)
    CHECK(p.rel == UIParent and p.point == "CENTER" and NEAR(p.x, 320), "free numpad at its own position")
    CHECK(card.__mouse == true, "free + unlocked: numpad drags")
    card.__scripts.OnDragStart(card)
    CHECK(card.__moving == true, "drag starts")
    card.__points = { { "TOPLEFT", UIParent, "TOPLEFT", 700, -400 } }
    card.__scripts.OnDragStop(card)
    CHECK(db.numpadPosition.point == "TOPLEFT" and db.numpadPosition.xOfs == 700, "drag saves the free position")
    Tick()
    local q = Point(card)
    CHECK(q.point == "TOPLEFT" and NEAR(q.x, 700) and NEAR(q.y, -400), "saved position re-applied")
end
EnterCombat()
card.__moving = false
card.__scripts.OnDragStart(card)
CHECK(card.__moving == false and #violations == 0, "no drag in combat", violations[1])
LeaveCombat()
db.locked = true
PickOption(posDrop, "RIGHT")
db.bagPosition = "BOTTOMRIGHT"; db.petBarPosition = "ABOVE"
Notify(); Tick()
CHECK(card.__mouse == false and Point(card).rel == backdrop, "docked again, mouse off")

-- ===========================================================================
-- G2. Numpad Scale: relative to Card Scale, deferred in combat, and a free
-- numpad grows and shrinks about its anchor instead of sliding away
-- ===========================================================================
-- Sliders notify through a trailing-edge C_Timer throttle
local function RunTimers()
    while #timers > 0 do
        table.remove(timers, 1)()
    end
end
local function FindSlider(panel)
    for _, f in ipairs(allFrames) do
        if f.__kind == "Slider" and f.__scripts.OnValueChanged and Descends(f, panel) then return f end
    end
end
local scaleSlider = FindSlider(numpadPanel)
CHECK(scaleSlider ~= nil, "Numpad Scale slider on the numpad page")
local function Slide(value)
    scaleSlider.__scripts.OnValueChanged(scaleSlider, value)
    RunTimers()
    Tick()
end
CHECK(db.numpadScale == 1 and NEAR(card.__scale, db.cardScale), "default: numpad matches Card Scale")
db.cardScale = 1.2
Notify(); Tick()
CHECK(NEAR(card.__scale, 1.2), "numpad follows Card Scale", card.__scale)
Slide(0.8)
CHECK(db.numpadScale == 0.8, "slider writes Numpad Scale", db.numpadScale)
CHECK(NEAR(card.__scale, 0.96), "numpad = Card Scale x Numpad Scale", card.__scale)
CHECK(NEAR(backdrop.__scale, 1.2), "the grid card keeps its own scale", backdrop.__scale)
CHECK(Face("NUMPAD7").__w == 32 and NEAR(Face("NUMPAD7").__scale, 1),
    "keys inherit the card's scale, not rescaled one by one")
do
    local p = Point(card)
    CHECK(p.point == "BOTTOMLEFT" and p.rel == backdrop and p.relPoint == "BOTTOMRIGHT",
        "still docked on the card's bottom edge")
end
EnterCombat()
Slide(1.3)
CHECK(db.numpadScale == 1.3 and NEAR(card.__scale, 0.96), "scale change waits out combat", card.__scale)
CHECK(#violations == 0, "scale change in combat: no violations", violations[1])
LeaveCombat()
Tick()
CHECK(NEAR(card.__scale, 1.56), "applied when combat drops", card.__scale)

-- Free: the position dragged at scale 1 (700, -400) stays put on screen
PickOption(posDrop, "FREE")
Tick()
do
    local p = Point(card)
    CHECK(p.point == "TOPLEFT" and NEAR(p.x * card.__scale, 700) and NEAR(p.y * card.__scale, -400),
        "free position saved at scale 1 lands in the same place at 156%", p.x)
    Slide(0.6)
    local q = Point(card)
    CHECK(NEAR(card.__scale, 0.72) and NEAR(q.x * card.__scale, 700) and NEAR(q.y * card.__scale, -400),
        "rescaling a free numpad keeps its place", q.x)
    -- Dragged at this scale: saved with it, and re-applied without a jump
    db.locked = false
    Notify(); Tick()
    card.__scripts.OnDragStart(card)
    card.__scripts.OnDragStop(card)
    db.locked = true
    CHECK(NEAR(db.numpadPosition.scale, 0.72), "a drag saves the scale it was taken at", db.numpadPosition.scale)
    Tick()
    local r = Point(card)
    CHECK(NEAR(r.x, q.x) and NEAR(r.y, q.y), "and re-applies it without moving", r.x)
end
PickOption(posDrop, "RIGHT")
db.cardScale = 1.0
Slide(1.0)
CHECK(NEAR(card.__scale, 1) and Point(card).rel == backdrop, "back to matched and docked")

-- ===========================================================================
-- H. Binding off, numpad off, slash toggle, page reset
-- ===========================================================================
local bindBox = FindCheckbox(numpadPanel, "Bind Numpad Keys")
ClickCheckbox(bindBox)
Tick()
CHECK(#BoundKeys() == 0, "Bind Numpad Keys off: every key given back")
CHECK(Face("NUMPAD7").HotKey.__text ~= "7", "no cap on a key that is not bound", Face("NUMPAD7").HotKey.__text)
CHECK(not PressKey("NUMPAD7", true), "the key no longer reaches the numpad")
ClickCheckbox(bindBox)
Tick()
CHECK(#BoundKeys() == 16 and Face("NUMPAD7").HotKey.__text == "7", "binding back on: keys and caps return")

do  -- no rebinding (and no UPDATE_BINDINGS storm) when nothing changed
    local before = bindWrites
    Notify(); Notify(); Tick(4)
    CHECK(bindWrites == before, "unchanged settings do not rebind", bindWrites - before)
end

EnterCombat()
SlashCmdList.COMMANDERUI_ACTIONBAR("numpad")
Tick()
CHECK(db.numpadEnabled == false, "/cab numpad toggles off")
CHECK(card:IsShown() and #BoundKeys() == 16, "still up and bound until combat drops")
CHECK(#violations == 0, "toggle in combat: no violations", violations[1])
LeaveCombat()
Tick()
CHECK(not card:IsShown(), "numpad hidden after combat")
CHECK(#BoundKeys() == 0, "numpad off: keys given back")
CHECK(MultiBarBottomRight:GetParent() == UIParent, "bottom-right bar restored")
SlashCmdList.COMMANDERUI_ACTIONBAR("numpad")
Tick()
CHECK(card:IsShown() and #BoundKeys() == 16, "/cab numpad toggles back on, same card")
CHECK(_G.CommanderActionBarNumpad == card, "card reused, not rebuilt")

do  -- the numpad page resets only numpad options
    db.cardStyle = "DARK"
    db.numpadLayout = "STANDARD"
    db.numpadFunctionRow = true
    db.numpadAnchor = "LEFT"
    db.numpadScale = 0.7
    local reset = FindButton(numpadPanel, "Restore Defaults")
    CHECK(reset ~= nil, "numpad page has Restore Defaults")
    if reset then reset.__scripts.OnClick(reset) end
    Tick()
    CHECK(db.numpadLayout == "APPLE" and db.numpadFunctionRow == false and db.numpadAnchor == "RIGHT"
        and db.numpadScale == 1,
        "numpad options reset")
    CHECK(db.cardStyle == "DARK", "the card's own options untouched")
    CHECK(card.__backdrop == backdrop.__backdrop, "numpad picks up the dark panel with the grid")
    CHECK(db.numpadEnabled == false and not card:IsShown(), "reset turns the numpad back off (its default)")
end

CHECK(#luaErrors == 0, "no Lua errors", luaErrors[1])
CHECK(#violations == 0, "no protected calls in combat anywhere", violations[1])

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
