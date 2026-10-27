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
-- True while Blizzard's own code runs a Blizzard frame: secure execution,
-- where protected calls are allowed even in combat
local secureExecution = false
local function Guard(f, method)
    if combat and IsProtected(f) and not secureExecution then
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
-- A button's own slot textures, as SetNormalTexture and friends make them
local function SlotTexture(self, field, file)
    self[field] = self[field] or NewRegion("Texture", self)
    self[field].__texture = file
end
function W.SetNormalTexture(self, file) SlotTexture(self, "__normal", file) end
function W.SetPushedTexture(self, file) SlotTexture(self, "__pushed", file) end
function W.SetHighlightTexture(self, file) SlotTexture(self, "__highlight", file) end
function W.SetTexCoord(self, ...) self.__coords = { ... } end
function W.SetDesaturated(self, v) self.__desat = v and true or false end

-- Templates ---------------------------------------------------------------
RANGE_INDICATOR = "\226\151\143"

-- Blizzard's two action-button lists. The template's OnLoad appends every
-- button to ActionBarButtonEventsFrame.frames; Update() keys one holding an
-- action into ActionBarActionEventsFrame.frames. Both are walked in plain
-- loops, and an entry an addon wrote taints the REST of the walk: every
-- protected call after it counts as the addon's, Blizzard's own included.
-- (Addon frames are the ones named Commander*.)
ActionBarButtonEventsFrame = { frames = {} }
ActionBarActionEventsFrame = { frames = {} }
local function AddonMade(f) return (f.__name or ""):match("^Commander") ~= nil end
local function Walk(list, fn)
    local tainted = false
    for _, f in pairs(list) do
        tainted = tainted or AddonMade(f)
        secureExecution = not tainted
        fn(f)
    end
    secureExecution = false
    return tainted
end
-- An event as ActionBarButtonEventsFrame hands it out
local function FireActionButtonEvent(event, arg1)
    return Walk(ActionBarButtonEventsFrame.frames, function(f)
        if event == "ACTIONBAR_SLOT_CHANGED" and (arg1 == 0 or arg1 == f.action) then f:UpdateAction(true) end
    end)
end
-- One as ActionBarActionEventsFrame hands it out (SPELL_UPDATE_ICON: Update)
local function FireActionEvent()
    return Walk(ActionBarActionEventsFrame.frames, function(f) f:Update() end)
end
-- ActionBarController_UpdateAll on a zone-in or a page or stance change: the
-- walk, then ValidateActionBarTransition showing MainActionBar in the same
-- execution (writing its isShownExternal, tainted if the walk was)
local function ActionBarControllerUpdateAll()
    local tainted = Walk(ActionBarButtonEventsFrame.frames, function(f) f:UpdateAction(true) end)
    secureExecution = not tainted
    MainActionBar.__shownExternalTainted = tainted
    MainActionBar:Show()
    secureExecution = false
    return tainted
end

-- Blizzard's ActionBarButtonTemplate, as far as this addon touches it: an
-- ID-0 button reads its slot from the "action" attribute; UpdateHotkeys on a
-- button with no binding command blanks the hotkey to the range dot; and
-- Update() ends by writing the "pressAndHoldAction" attribute
-- (ActionBarActionButtonMixin:UpdatePressAndHoldAction)
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
        if name == "action" then
            self.action = value
            self:UpdateAction()
        end
    end
    f.UpdatePressAndHoldAction = function(self) self:SetAttribute("pressAndHoldAction", false) end
    -- Update's bookkeeping: holding an action joins ActionBarActionEventsFrame's
    -- list, holding none leaves it
    f.Update = function(self)
        if HasAction(self.action) then
            if not self.eventsRegistered then
                ActionBarActionEventsFrame.frames[self] = self
                self.eventsRegistered = true
            end
        elseif self.eventsRegistered then
            ActionBarActionEventsFrame.frames[self] = nil
            self.eventsRegistered = nil
        end
        self:UpdatePressAndHoldAction()
    end
    f.UpdateAction = function(self) self:Update() end
    f.OnEvent = function(self, event, arg1)
        if event == "ACTIONBAR_SLOT_CHANGED" then
            if arg1 == 0 or arg1 == self.action then self:UpdateAction(true) end
        elseif event == "ACTIONBAR_UPDATE_COOLDOWN" then
            self.__cooldownUpdates = (self.__cooldownUpdates or 0) + 1
        elseif event == "SPELL_UPDATE_ICON" then
            self:Update()
        elseif event == "UPDATE_BINDINGS" then
            self:UpdateHotkeys(self.buttonType)
        end
    end
    f.MatchesActiveButtonSpellID = function() return false end
    -- OnLoad: RegisterFrame, then UpdateAction
    table.insert(ActionBarButtonEventsFrame.frames, f)
    f:UpdateAction()
end

-- The bare SecureActionButtonTemplate OnClick: SecureActionButton_OnClick with
-- no isKeyPress/isSecureAction, so it honours ActionButtonUseKeyDown
local cvars = { ActionButtonUseKeyDown = "1" }
function GetCVarBool(name) return cvars[name] == "1" end
function GetCVar(name) return cvars[name] end
local usedActions = {}
local targetedUnits = {}
local function SecureOnClick(self, button, down)
    local useDown = GetCVarBool("ActionButtonUseKeyDown")
    if (down and useDown) or (not down and not useDown) then
        if self:GetAttribute("type") == "action" then
            usedActions[#usedActions + 1] = self:GetAttribute("action")
        elseif self:GetAttribute("type") == "target" then
            -- SECURE_ACTIONS.target: no unit, no action at all
            local unit = self:GetAttribute("unit")
            if unit then targetedUnits[#targetedUnits + 1] = unit end
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
-- Who is around: you, a party the tests fill in, and a target that can
-- wear a raid mark
local roster = { player = { name = "Devin", class = "PRIEST" } }
function UnitClass(unit)
    local u = roster[unit or "player"]
    if not u then return nil end
    return u.class:sub(1, 1) .. u.class:sub(2):lower(), u.class
end
function UnitExists(unit) return roster[unit] ~= nil end
function UnitName(unit) local u = roster[unit] return u and u.name end
function UnitIsDeadOrGhost(unit) local u = roster[unit] return u and u.dead or false end
function UnitIsConnected(unit) local u = roster[unit] return u ~= nil and not u.offline end
-- Group members only, as on the client: your own unit is never checked
function UnitInRange(unit)
    local u = roster[unit]
    if not u or unit == "player" then return false, false end
    return not u.far, true
end
local raidMarks, markCalls = {}, {}
function GetRaidTargetIndex(unit) return raidMarks[unit] end
function SetRaidTarget(unit, mark)
    markCalls[#markCalls + 1] = mark
    raidMarks[unit] = (mark ~= 0) and mark or nil
end
function UnitFactionGroup() return "Alliance" end
function UnitRace() return "Human", "Human" end
RAID_CLASS_COLORS = { PRIEST = { r = 1, g = 1, b = 1 } }
CLASS_ICON_TCOORDS = { PRIEST = { 0.5, 0.75, 0.25, 0.5 }, WARRIOR = { 0, 0.25, 0, 0.25 },
    MAGE = { 0.25, 0.5, 0, 0.25 }, ROGUE = { 0.5, 0.75, 0, 0.25 }, PALADIN = { 0, 0.25, 0.5, 0.75 } }

local actionSlots = { [1] = true }   -- slot -> true when something is on it
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

-- `luajit actionbar_numpad_harness.lua combatboot`: a /reload mid-fight,
-- with the numpad (and its F16-F19 row), the function-key row in party mode
-- and the out-of-combat fade all saved on. It runs section Z and exits; the
-- plain run is an ordinary login, which every section from A on assumes.
local COMBAT_BOOT = arg and arg[1] == "combatboot"
if COMBAT_BOOT then
    -- SavedVariables land after the file runs and before ADDON_LOADED
    CommanderActionBarDB = { numpadEnabled = true, numpadFunctionRow = true,
        fkeyEnabled = true, fkeyMode = "PARTY", oocFade = true, fadeOpacity = 0.4 }
    combat = true
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
-- Z. (combatboot only) A /reload mid-fight: nothing secure is built, moved
-- or bound until combat drops, and the bar knows it is in a fight
-- ===========================================================================
if COMBAT_BOOT then
    Tick(3)
    CHECK(#luaErrors == 0, "combat boot clean", luaErrors[1])
    CHECK(#violations == 0, "combat boot: no protected calls", violations[1])
    CHECK(_G.CommanderActionBarNumpad == nil and _G.CommanderActionBarFKeys == nil,
        "neither keyed card built mid-fight")
    CHECK(#BoundKeys() == 0, "nothing bound mid-fight", #BoundKeys())
    CHECK(NEAR(backdrop.__alpha, 1), "no out-of-combat fade in the fight it reloaded into", backdrop.__alpha)
    LeaveCombat()
    Tick()
    local np, row = _G.CommanderActionBarNumpad, _G.CommanderActionBarFKeys
    CHECK(np and np:IsShown() and row and row:IsShown(), "both cards built when combat drops")
    CHECK(#BoundKeys() == 26, "the numpad (with F16-F19) and the row bound", #BoundKeys())
    CHECK(_G.CommanderFKeyPartyF1 and _G.CommanderFKeyPartyF1:GetAttribute("unit") == "player"
        and overrideBindings.F1 and overrideBindings.F1.button == "CommanderFKeyPartyF1", "party seats taken after combat")
    CHECK(Point(ActionButton1).rel == backdrop, "the grid laid out after combat")
    CHECK(NEAR(backdrop.__alpha, 0.4), "the fade arrives once the fight is over", backdrop.__alpha)
    EnterCombat(); Tick(2); LeaveCombat(); Tick()
    CHECK(#violations == 0 and #luaErrors == 0, "a second fight after the reload: clean", violations[1] or luaErrors[1])
    io.write(string.format("%d checks, %d failures (combatboot)\n", checks, fails))
    os.exit(fails == 0 and 0 or 1)
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
CHECK(db.fkeyEnabled == false and db.fkeyBindKeys == true and db.fkeyAnchor == "ABOVE"
    and db.fkeyBar == "RIGHT" and db.fkeyScale == 1 and db.fkeyMode == "ACTIONS", "function-key row defaults applied")
CHECK(_G.CommanderActionBarFKeys == nil and _G.CommanderFKeyButtonF1 == nil, "function-key row not built while off")
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

-- ===========================================================================
-- I. The function-key row (2.4.0): built out of combat, ` F1-F5 on top of
-- the grid, each key over a grid column, bound beside the numpad's keys
-- ===========================================================================
local fkeyPanel = panelsByTitle["Action Bar Function Keys"]
CHECK(fkeyPanel ~= nil, "function-key page found")
do
    local titles = {}
    for _, info in ipairs(Commander.GetModules()) do titles[info.key] = info.title end
    CHECK(titles.ActionBarFKeys == "Action Bar Function Keys", "fourth settings page registered")
end
-- The numpad back on beside it: the row has to share the console with it
ClickCheckbox(showBox)
Tick()
CHECK(card:IsShown() and #BoundKeys() == 16, "numpad back up for the row's checks", #BoundKeys())

local fShowBox = FindCheckbox(fkeyPanel, "Show Function Key Bar")
CHECK(fShowBox ~= nil, "Show Function Key Bar checkbox")
EnterCombat()
ClickCheckbox(fShowBox)
Tick(3)
CHECK(db.fkeyEnabled == true, "row checkbox wrote the setting")
CHECK(_G.CommanderActionBarFKeys == nil, "row not built in combat")
CHECK(#BoundKeys() == 16, "nothing new bound in combat", #BoundKeys())
CHECK(#violations == 0, "row enabled in combat: no protected calls", violations[1])
LeaveCombat()
Tick()

local row = _G.CommanderActionBarFKeys
CHECK(row ~= nil and row:IsShown(), "row built and shown when combat drops")
CHECK(#violations == 0 and #luaErrors == 0, "row build clean", violations[1] or luaErrors[1])

local ROW_KEYS = { "`", "F1", "F2", "F3", "F4", "F5" }
local ROW_NAMES = { ["`"] = "Grave", F1 = "F1", F2 = "F2", F3 = "F3", F4 = "F4", F5 = "F5" }
local function FFace(key) return _G["CommanderFKeyButton" .. ROW_NAMES[key]] end
local function FSlot(key) return FFace(key):GetAttribute("action") end

-- Shape: one row of six grid keys at grid pitch, as wide as the six-column grid
CHECK(row.__w == 6 * 42 - 10 + 28 and row.__h == 32 + 28, "one row of six keys at grid pitch",
    row.__w .. "x" .. row.__h)
CHECK(row.__w == backdrop.__w, "as wide as the grid card", backdrop.__w)
for i, key in ipairs(ROW_KEYS) do
    local f = FFace(key)
    local p = Point(f)
    CHECK(f and f:IsShown() and p.rel == row and p.point == "TOPLEFT"
        and NEAR(p.x, 14 + (i - 1) * 42) and NEAR(p.y, -14),
        key .. " over grid column " .. i, tostring(p.x) .. "," .. tostring(p.y))
    CHECK(f.__w == 32 and f.__normal.__w > 32 and f.__normal.__w < 66, key .. " is a grid-sized key", f.__w)
    local slot = 24 + i
    CHECK(f:GetAttribute("action") == slot and f.__cmdProxy:GetAttribute("action") == slot and f.action == slot,
        key .. " -> slot " .. slot, tostring(f:GetAttribute("action")))
end

-- Docked on top: left edges lined up, a 2px gap, stacked and framed with the grid
do
    local p = Point(row)
    CHECK(p.point == "BOTTOMLEFT" and p.rel == backdrop and p.relPoint == "TOPLEFT" and NEAR(p.x, 0) and NEAR(p.y, 2),
        "docked on the grid's top edge", tostring(p.point) .. " " .. tostring(p.relPoint))
    CHECK(row:GetFrameStrata() == backdrop:GetFrameStrata() and row:GetFrameLevel() == backdrop:GetFrameLevel(),
        "row stacks with the grid card")
    CHECK(row.__backdrop ~= nil and row.__backdrop == backdrop.__backdrop, "row wears the grid's framing")
    CHECK(row.__mouse == false, "docked row does not take the mouse")
    CHECK(Point(card).rel == backdrop and Point(card).relPoint == "BOTTOMRIGHT", "numpad still docked beside the grid")
end
CHECK(MultiBarRight:GetParent() == UIParent, "the row's bar is not parked: it uses six of its twelve slots")

-- Binds: six more on top of the numpad's sixteen, each to its own proxy
do
    CHECK(#BoundKeys() == 22, "row adds six binds", #BoundKeys())
    local grave = overrideBindings["`"]
    CHECK(grave and grave.button == "CommanderFKeyButtonGraveKey" and grave.mouse == "LeftButton",
        "` clicks its proxy", grave and grave.button)
    CHECK(overrideBindings.F1 and overrideBindings.F1.button == "CommanderFKeyButtonF1Key"
        and overrideBindings.F5 and overrideBindings.F5.button == "CommanderFKeyButtonF5Key", "F1 and F5 click theirs")
    CHECK(overrideBindings.F6 == nil and overrideBindings["SHIFT-F1"] == nil and overrideBindings["SHIFT-`"] == nil,
        "only the six bare keys are taken")
    CHECK(overrideBindings.NUMPAD7 and overrideBindings.NUMPAD7.button == "CommanderNumpadButton7Key",
        "the numpad's binds untouched")
    CHECK(grave and overrideBindings.NUMPAD7 and grave.owner ~= overrideBindings.NUMPAD7.owner,
        "each card owns its own binds")
    local proxy = _G.CommanderFKeyButtonF1Key
    CHECK(proxy and proxy.__secure and proxy:GetAttribute("type") == "action" and proxy.__mouse == false
        and proxy.__clicks[1] == "AnyDown" and proxy.__clicks[2] == "AnyUp", "row proxies built like the numpad's")
end

-- Caps, and they survive Blizzard re-running UpdateHotkeys
Tick()
CHECK(FFace("`").HotKey.__text == "`" and FFace("`").HotKey.__shown, "` wears its cap")
CHECK(FFace("F3").HotKey.__text == "F3" and FFace("F5").HotKey.__text == "F5", "F-key caps")
FFace("F1"):UpdateHotkeys()
CHECK(FFace("F1").HotKey.__text == "F1" and FFace("F1").HotKey.__shown, "F1 cap restored after UPDATE_BINDINGS")

-- The numpad's own F16-F19 row binds alongside without a clash
ClickCheckbox(fRowBox)
Tick()
CHECK(#BoundKeys() == 26 and overrideBindings.F16 and overrideBindings.F1
    and overrideBindings.F1.button == "CommanderFKeyButtonF1Key", "F16-F19 and F1-F5 bound side by side", #BoundKeys())
ClickCheckbox(fRowBox)
Tick()
CHECK(#BoundKeys() == 22 and overrideBindings.F1 ~= nil, "F16-F19 off: the row's binds stay", #BoundKeys())

-- Presses go through the proxy in both key modes
for i = #usedActions, 1, -1 do usedActions[i] = nil end
cvars.ActionButtonUseKeyDown = "1"
PressKey("`", true)
CHECK(#usedActions == 1 and usedActions[1] == 25, "key-down mode: ` fires slot 25 on press", usedActions[1])
CHECK(FFace("`").__cmdPress and FFace("`").__cmdPress.__shown, "row press overlay lit while held")
PressKey("`", false)
CHECK(#usedActions == 1 and not FFace("`").__cmdPress.__shown, "release: no second fire, overlay off")
cvars.ActionButtonUseKeyDown = "0"
PressKey("F2", true)
CHECK(#usedActions == 1, "key-up mode: press does not fire", #usedActions)
PressKey("F2", false)
CHECK(#usedActions == 2 and usedActions[2] == 27, "key-up mode: F2 fires slot 27 on release", usedActions[2])
cvars.ActionButtonUseKeyDown = "1"

-- Mid-fight: presses, polls and a fade stay legal
EnterCombat()
PressKey("F4", true); PressKey("F4", false)
db.oocFade = true
Tick(3)
CHECK(usedActions[#usedActions] == 29, "F4 fires in combat", usedActions[#usedActions])
CHECK(#violations == 0, "row in combat: no violations", violations[1])
LeaveCombat()
db.oocFade = false
Tick()

-- The pet bar, above the card, steps up past the docked row
do
    local pet = Point(PetActionBar)
    CHECK(pet.point == "BOTTOM" and pet.rel == row and pet.relPoint == "TOP", "pet bar above the row, not under it",
        pet.rel and pet.rel.__name)
end

-- One console for the fade: the row fades with the rest, and hovering it wakes all three
db.oocFade = true; db.fadeOpacity = 0.4
Tick()
CHECK(NEAR(row.__alpha, 0.4) and NEAR(backdrop.__alpha, 0.4) and NEAR(card.__alpha, 0.4),
    "row fades with the grid and the numpad", row.__alpha)
do
    local realMouseIsOver = MouseIsOver
    MouseIsOver = function(f) return f == row end
    Tick()
    CHECK(NEAR(row.__alpha, 1) and NEAR(backdrop.__alpha, 1) and NEAR(card.__alpha, 1),
        "hovering the row wakes the whole console", backdrop.__alpha)
    MouseIsOver = realMouseIsOver
end
db.hideEmptySlots = true
actionSlots[25] = true
Tick()
CHECK(NEAR(FFace("`").__alpha, 1), "a filled row key stays at the card's alpha")
CHECK(NEAR(row.__alpha * FFace("F1").__alpha, 0.15), "an empty row key dims to where a grid slot does",
    row.__alpha * FFace("F1").__alpha)
db.oocFade = false; db.hideEmptySlots = false
Tick()

-- ===========================================================================
-- J. Bars: the row and the numpad's two blocks never share one
-- ===========================================================================
local fBarDrop = FindDropdowns(fkeyPanel, "PAGE2")[1]
CHECK(fBarDrop ~= nil, "row bar dropdown found")
do
    local before = bindWrites
    PickOption(fBarDrop, "LEFT")   -- the numpad's operator bar
    Tick()
    CHECK(db.fkeyBar == "LEFT" and db.numpadOpsBar == "RIGHT" and db.numpadDigitsBar == "BOTTOMRIGHT",
        "row takes the operator bar, operators take the row's", db.numpadOpsBar)
    CHECK(FSlot("`") == 37 and FSlot("F5") == 42, "row slots follow", FSlot("`"))
    CHECK(select(1, SlotOf("NUMPADDIVIDE")) == 25 and select(1, SlotOf("NUMPADEQUALS")) == 28, "operator slots follow")
    CHECK(bindWrites == before, "a bar change moves slots, not binds", bindWrites - before)
end
PickOption(digitsDrop, "LEFT")     -- from the numpad page, onto the row's bar
Tick()
CHECK(db.numpadDigitsBar == "LEFT" and db.fkeyBar == "BOTTOMRIGHT" and db.numpadOpsBar == "RIGHT",
    "the numpad page trades with the row too", db.fkeyBar)
CHECK(FSlot("`") == 49 and select(1, SlotOf("NUMPAD1")) == 37, "slots follow the trade")
CHECK(MultiBarLeft:GetParent() ~= UIParent and MultiBarBottomRight:GetParent() == UIParent,
    "the parked bar follows the number block, never the row")
-- The numpad page's Restore Defaults takes its bars back; the row gives way
do
    local reset = FindButton(numpadPanel, "Restore Defaults")
    reset.__scripts.OnClick(reset)
    Tick()
    CHECK(db.numpadDigitsBar == "BOTTOMRIGHT" and db.numpadOpsBar == "LEFT" and db.fkeyBar == "RIGHT",
        "numpad reset: the row moves to the first free bar", db.fkeyBar)
    CHECK(db.fkeyEnabled == true and row:IsShown() and FSlot("`") == 25, "the row itself is left up", FSlot("`"))
end
ClickCheckbox(showBox)
Tick()
CHECK(card:IsShown() and #BoundKeys() == 22, "numpad back on", #BoundKeys())

-- ===========================================================================
-- K. Free and docked, and Function Key Scale
-- ===========================================================================
local fPosDrop = FindDropdowns(fkeyPanel, "FREE")[1]
CHECK(fPosDrop ~= nil, "row position dropdown found")
PickOption(fPosDrop, "FREE")
db.locked = false
Notify(); Tick()
do
    local p = Point(row)
    CHECK(p.rel == UIParent and p.point == "CENTER" and NEAR(p.x, 0) and NEAR(p.y, 160), "free row at its own position")
    CHECK(row.__mouse == true, "free + unlocked: row drags")
    CHECK(Point(PetActionBar).rel == backdrop, "pet bar back on the grid once the row is not on top")
    row.__scripts.OnDragStart(row)
    CHECK(row.__moving == true, "row drag starts")
    row.__points = { { "TOPLEFT", UIParent, "TOPLEFT", 500, -300 } }
    row.__scripts.OnDragStop(row)
    CHECK(db.fkeyPosition.point == "TOPLEFT" and db.fkeyPosition.xOfs == 500 and db.fkeyPosition.scale == 1,
        "drag saves the row's position and scale")
    CHECK(db.numpadPosition.xOfs ~= 500, "and not the numpad's")
    Tick()
    local q = Point(row)
    CHECK(q.point == "TOPLEFT" and NEAR(q.x, 500) and NEAR(q.y, -300), "saved row position re-applied")
    CHECK(card.__mouse == false, "the docked numpad stays put while the row is free")
end
EnterCombat()
row.__moving = false
row.__scripts.OnDragStart(row)
CHECK(row.__moving == false and #violations == 0, "no row drag in combat", violations[1])
LeaveCombat()
db.locked = true
PickOption(fPosDrop, "ABOVE")
Notify(); Tick()
CHECK(row.__mouse == false and Point(row).rel == backdrop and Point(PetActionBar).rel == row,
    "docked on top again, mouse off, pet bar above it")

local fScaleSlider = FindSlider(fkeyPanel)
CHECK(fScaleSlider ~= nil, "Function Key Scale slider")
local function FSlide(value)
    fScaleSlider.__scripts.OnValueChanged(fScaleSlider, value)
    RunTimers()
    Tick()
end
db.cardScale = 1.2
Notify(); Tick()
CHECK(NEAR(row.__scale, 1.2), "row follows Card Scale", row.__scale)
FSlide(0.8)
CHECK(db.fkeyScale == 0.8 and NEAR(row.__scale, 0.96), "row = Card Scale x Function Key Scale", row.__scale)
CHECK(NEAR(backdrop.__scale, 1.2) and NEAR(card.__scale, 1.2), "grid and numpad keep their own scale")
CHECK(Point(row).rel == backdrop and Point(row).relPoint == "TOPLEFT", "still on the grid's top edge")
EnterCombat()
FSlide(1.3)
CHECK(db.fkeyScale == 1.3 and NEAR(row.__scale, 0.96), "row scale waits out combat", row.__scale)
CHECK(#violations == 0, "row scale in combat: no violations", violations[1])
LeaveCombat()
Tick()
CHECK(NEAR(row.__scale, 1.56), "row scale applied when combat drops", row.__scale)
db.cardScale = 1.0
FSlide(1.0)
CHECK(NEAR(row.__scale, 1), "back to matched", row.__scale)

-- ===========================================================================
-- L. Binding off, the row off, /cab fkeys, the page's own reset
-- ===========================================================================
local fBindBox = FindCheckbox(fkeyPanel, "Bind Function Keys")
ClickCheckbox(fBindBox)
Tick()
CHECK(#BoundKeys() == 16 and overrideBindings.F1 == nil and overrideBindings["`"] == nil,
    "Bind Function Keys off: the six keys given back", #BoundKeys())
CHECK(overrideBindings.NUMPAD7 ~= nil, "the numpad keeps its keys")
CHECK(FFace("F1").HotKey.__text ~= "F1", "no cap on a row key that is not bound", FFace("F1").HotKey.__text)
CHECK(Face("NUMPAD7").HotKey.__text == "7", "the numpad keeps its caps")
ClickCheckbox(fBindBox)
Tick()
CHECK(#BoundKeys() == 22 and FFace("F1").HotKey.__text == "F1", "binding back on: keys and caps return")
do
    local before = bindWrites
    Notify(); Notify(); Tick(4)
    CHECK(bindWrites == before, "unchanged settings do not rebind either card", bindWrites - before)
end

EnterCombat()
SlashCmdList.COMMANDERUI_ACTIONBAR("fkeys")
Tick()
CHECK(db.fkeyEnabled == false, "/cab fkeys toggles off")
CHECK(row:IsShown() and #BoundKeys() == 22, "row up and bound until combat drops")
CHECK(#violations == 0, "row toggle in combat: no violations", violations[1])
LeaveCombat()
Tick()
CHECK(not row:IsShown(), "row hidden after combat")
CHECK(#BoundKeys() == 16 and overrideBindings.F1 == nil, "row off: its keys given back, the numpad's kept", #BoundKeys())
CHECK(Point(PetActionBar).rel == backdrop, "pet bar back on the grid")
SlashCmdList.COMMANDERUI_ACTIONBAR("fkeys")
Tick()
CHECK(row:IsShown() and #BoundKeys() == 22, "/cab fkeys toggles back on")
CHECK(_G.CommanderActionBarFKeys == row, "row reused, not rebuilt")

-- ===========================================================================
-- M. F1-F5 modes (2.5.0): raid marks on the target, then the party with you
-- last; ` presses its action throughout
-- ===========================================================================
local modeDrop = FindDropdowns(fkeyPanel, "MARKS")[1]
CHECK(modeDrop ~= nil, "F1-F5 Keys dropdown found")
do
    local opts = OpenDropdown(modeDrop)
    CHECK(#opts == 3 and opts[1].value == "ACTIONS" and opts[2].value == "MARKS" and opts[3].value == "PARTY",
        "Row Actions, Raid Marks, Party Targets", #opts)
end
CHECK(db.fkeyMode == "ACTIONS", "row actions by default")
local function Mark(key) return _G["CommanderFKeyMark" .. key] end
local function Seat(key) return _G["CommanderFKeyParty" .. key] end
local MARK_OF = { F1 = 8, F2 = 7, F3 = 6, F4 = 5, F5 = 4 }
CHECK(Mark("F1") and not Mark("F1"):IsShown() and Seat("F5") and not Seat("F5"):IsShown(),
    "mode faces built with the row, hidden in Row Actions")
CHECK(Mark("`") == nil and Seat("`") == nil, "` has no mode faces")
CHECK(Seat("F1").__secure and not Mark("F1").__secure, "party faces secure, mark faces not")

-- Raid marks, chosen mid-fight: nothing swaps or rebinds until combat drops
EnterCombat()
PickOption(modeDrop, "MARKS")
Tick()
CHECK(db.fkeyMode == "MARKS", "mode written")
CHECK(FFace("F1"):IsShown() and not Mark("F1"):IsShown()
    and overrideBindings.F1.button == "CommanderFKeyButtonF1Key", "nothing swaps in combat")
CHECK(#violations == 0, "mode change in combat: no violations", violations[1])
LeaveCombat()
Tick()
for i, key in ipairs(ROW_KEYS) do
    if key == "`" then
        CHECK(FFace(key):IsShown() and FSlot(key) == 25 and overrideBindings[key].button == "CommanderFKeyButtonGraveKey",
            "` keeps its action in Raid Marks")
    else
        local f, p = Mark(key), Point(Mark(key))
        CHECK(f:IsShown() and not FFace(key):IsShown() and p.rel == row and NEAR(p.x, 14 + (i - 1) * 42) and NEAR(p.y, -14),
            key .. " mark face in the action face's place", tostring(p.x))
        CHECK(f.icon.__texture == "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. MARK_OF[key],
            key .. " shows mark " .. MARK_OF[key], f.icon.__texture)
        CHECK(overrideBindings[key] and overrideBindings[key].button == "CommanderFKeyMark" .. key,
            key .. " bound to its mark face")
    end
end
CHECK(Mark("F1").__w == 32 and NEAR(Mark("F1").__normal.__w, 32 * 66 / 36), "mark faces are grid keys, border to scale",
    Mark("F1").__normal.__w)
CHECK(#BoundKeys() == 22 and overrideBindings.NUMPAD7 ~= nil, "same 22 keys held, the numpad's untouched", #BoundKeys())
CHECK(Mark("F1").HotKey.__text == "F1" and Mark("F1").HotKey.__shown, "mark faces wear their caps")

-- Marking: the press the key-down setting picks, toggled like Blizzard's bind
roster.target = { name = "Boss", class = "WARRIOR" }
for i = #markCalls, 1, -1 do markCalls[i] = nil end
cvars.ActionButtonUseKeyDown = "1"
PressKey("F1", true)
CHECK(#markCalls == 1 and raidMarks.target == 8, "F1 puts the skull on the target on press", raidMarks.target)
CHECK(Mark("F1").__cmdPress and Mark("F1").__cmdPress.__shown, "mark face lit while held")
PressKey("F1", false)
CHECK(#markCalls == 1 and not Mark("F1").__cmdPress.__shown, "release does not mark again")
Tick()
CHECK(Mark("F1").__cmdLit.__shown and not Mark("F2").__cmdLit.__shown, "the skull lit while the target wears it")
PressKey("F1", true); PressKey("F1", false)
CHECK(raidMarks.target == nil and markCalls[#markCalls] == 0, "F1 again takes the skull off")
Tick()
CHECK(not Mark("F1").__cmdLit.__shown, "and the skull goes dark")
cvars.ActionButtonUseKeyDown = "0"
PressKey("F2", true)
CHECK(raidMarks.target == nil, "key-up mode: no mark on press")
PressKey("F2", false)
CHECK(raidMarks.target == 7, "key-up mode: the cross lands on release", raidMarks.target)
cvars.ActionButtonUseKeyDown = "1"
EnterCombat()
PressKey("F5", true); PressKey("F5", false)
Tick(2)
CHECK(raidMarks.target == 4 and Mark("F5").__cmdLit.__shown, "marking mid-fight: the triangle", raidMarks.target)
CHECK(#violations == 0, "marks in combat: no violations", violations[1])
LeaveCombat()
Mark("F3").__scripts.OnClick(Mark("F3"), "LeftButton", true)
CHECK(raidMarks.target == 6, "clicking a mark face marks too", raidMarks.target)
roster.target, raidMarks.target = nil, nil
do
    local n = #markCalls
    PressKey("F4", true); PressKey("F4", false)
    CHECK(#markCalls == n, "no target: nothing marked")
end

-- Party targets: your party in order, you after the last of them
PickOption(modeDrop, "PARTY")
Tick()
CHECK(Seat("F1"):IsShown() and not Mark("F1"):IsShown() and not FFace("F1"):IsShown(), "party faces swap in")
CHECK(overrideBindings.F1 and overrideBindings.F1.button == "CommanderFKeyPartyF1"
    and overrideBindings.F5.button == "CommanderFKeyPartyF5", "F1-F5 bound to the party faces")
CHECK(overrideBindings["`"].button == "CommanderFKeyButtonGraveKey" and FFace("`"):IsShown(), "` keeps its action")
local function Units()
    local out = {}
    for i, key in ipairs({ "F1", "F2", "F3", "F4", "F5" }) do out[i] = Seat(key):GetAttribute("unit") or "-" end
    return table.concat(out, " ")
end
CHECK(Seat("F1"):GetAttribute("type") == "target" and Units() == "player - - - -", "solo: F1 is you", Units())
CHECK(Seat("F1").Name.__text == "Devin" and NEAR(Seat("F1").__alpha, 1) and NEAR(Seat("F2").__alpha, 0.35),
    "your seat named, empty seats dimmed")

roster.party1 = { name = "Alpha", class = "WARRIOR" }
roster.party2 = { name = "Bravo", class = "MAGE" }
Tick()
CHECK(Units() == "party1 party2 player - -", "3v3: two partners, then you", Units())
CHECK(Seat("F1").Name.__text == "Alpha" and Seat("F2").Name.__text == "Bravo" and Seat("F3").Name.__text == "Devin",
    "the seats show who they target")
CHECK(Seat("F1").icon.__coords and Seat("F1").icon.__coords[1] == 0 and Seat("F2").icon.__coords[1] == 0.25
    and Seat("F1").icon.__shown, "class icons on the seats")
CHECK(not Seat("F4").icon.__shown and (Seat("F4").Name.__text or "") == "", "an empty seat shows nobody")
for i = #targetedUnits, 1, -1 do targetedUnits[i] = nil end
PressKey("F3", true)
CHECK(#targetedUnits == 1 and targetedUnits[1] == "player", "F3 targets you on press", targetedUnits[1])
CHECK(Seat("F3").__cmdPress and Seat("F3").__cmdPress.__shown, "party face lit while held")
PressKey("F3", false)
CHECK(#targetedUnits == 1 and not Seat("F3").__cmdPress.__shown, "release does not target again")
PressKey("F1", true); PressKey("F1", false)
CHECK(targetedUnits[2] == "party1", "F1 targets the first partner", targetedUnits[2])
PressKey("F4", true); PressKey("F4", false)
CHECK(#targetedUnits == 2, "an empty seat targets nobody", #targetedUnits)

-- Someone joins mid-fight: the seats hold, and say so, until combat drops
EnterCombat()
roster.party3 = { name = "Charlie", class = "ROGUE" }
Tick(2)
CHECK(Units() == "party1 party2 player - -" and Seat("F3").Name.__text == "Devin",
    "a join mid-fight waits: F3 still targets you and says so", Units())
PressKey("F2", true); PressKey("F2", false)
CHECK(targetedUnits[#targetedUnits] == "party2", "party keys work mid-fight")
CHECK(#violations == 0, "roster change in combat: no violations", violations[1])
LeaveCombat()
Tick()
CHECK(Units() == "party1 party2 party3 player -" and Seat("F4").Name.__text == "Devin", "re-seated when combat drops", Units())
roster.party4 = { name = "Delta", class = "PALADIN" }
Tick()
CHECK(Units() == "party1 party2 party3 party4 player", "full party: F5 is you", Units())
roster.party1.dead = true
Tick()
CHECK(Seat("F1").icon.__desat == true, "a dead partner greys out")
roster.party1.dead = nil
roster.party2.offline = true
Tick()
CHECK(Seat("F1").icon.__desat == false and Seat("F2").icon.__desat == true, "back to colour; offline greys too")
roster.party2.offline = nil

-- Out-of-Range Tint reaches the seats: a partner out of range goes red
db.rangeTint = true
roster.party2.far = true
Tick()
CHECK(Seat("F2").icon.__vertex and Seat("F2").icon.__vertex[2] < 0.5 and Seat("F1").icon.__vertex[2] == 1,
    "a partner out of range goes red, one in range does not", Seat("F2").icon.__vertex and Seat("F2").icon.__vertex[2])
CHECK(Seat("F5").icon.__vertex and Seat("F5").icon.__vertex[2] == 1, "your own seat never tints")
EnterCombat()
roster.party2.far = nil
Tick()
CHECK(Seat("F2").icon.__vertex[2] == 1 and #violations == 0, "back in range mid-fight: the red clears", violations[1])
roster.party2.far = true
LeaveCombat()
db.rangeTint = false
Tick()
CHECK(Seat("F2").icon.__vertex[2] == 1, "Out-of-Range Tint off: no red")
roster.party2.far = nil

-- Binding off in a mode: the keys go back and the caps come off our faces
ClickCheckbox(fBindBox)
Tick()
CHECK(overrideBindings.F1 == nil and #BoundKeys() == 16, "bind off: F1-F5 given back", #BoundKeys())
CHECK(not Seat("F1").HotKey.__shown, "no cap on an unbound party face")
ClickCheckbox(fBindBox)
Tick()
CHECK(overrideBindings.F1 and overrideBindings.F1.button == "CommanderFKeyPartyF1" and Seat("F1").HotKey.__shown,
    "bind on: back on the party faces")
do
    local before = bindWrites
    Notify(); Notify(); Tick(4)
    CHECK(bindWrites == before, "unchanged mode does not rebind", bindWrites - before)
end

-- Back to row actions: the action faces, their slots and their proxies
PickOption(modeDrop, "ACTIONS")
Tick()
CHECK(FFace("F1"):IsShown() and not Seat("F1"):IsShown() and not Mark("F1"):IsShown()
    and FSlot("F1") == 26 and overrideBindings.F1.button == "CommanderFKeyButtonF1Key", "row actions back")
roster.party1, roster.party2, roster.party3, roster.party4 = nil, nil, nil, nil
Tick()

-- ===========================================================================
-- N. Blizzard's action-button events reach our faces as us (2.5.1): a slot
-- changing mid-fight must not end in a blocked SetAttribute
-- ===========================================================================
CHECK(Face("NUMPAD7").UpdatePressAndHoldAction ~= ActionButton1.UpdatePressAndHoldAction,
    "our faces never rewrite pressAndHoldAction; Blizzard's are untouched")
EnterCombat()
Fire("ACTIONBAR_SLOT_CHANGED", 55)    -- the numpad's 7, through our own dispatcher (section O)
Fire("ACTIONBAR_SLOT_CHANGED", 25)    -- the row's `
Fire("ACTIONBAR_SLOT_CHANGED", 0)     -- every face at once
FireActionButtonEvent("ACTIONBAR_SLOT_CHANGED", 0)   -- and Blizzard's own walk
CHECK(#violations == 0, "slot changes mid-fight: no blocked call on our faces", violations[1])
LeaveCombat()
FireActionButtonEvent("ACTIONBAR_SLOT_CHANGED", 0)
CHECK(ActionButton1:GetAttribute("pressAndHoldAction") == false, "Blizzard's own buttons still update theirs")
CHECK(#violations == 0, "and out of combat nothing is blocked either", violations[1])

-- ===========================================================================
-- O. Our faces stay out of Blizzard's button lists (2.6.0, round 4), so no
-- Blizzard walk runs tainted, and our own frame hands them their events
-- ===========================================================================
do
    local function OursIn(list)
        for _, f in pairs(list) do if AddonMade(f) then return f.__name end end
    end
    CHECK(OursIn(ActionBarButtonEventsFrame.frames) == nil, "no face of ours in ActionBarButtonEventsFrame",
        OursIn(ActionBarButtonEventsFrame.frames))
    CHECK(OursIn(ActionBarActionEventsFrame.frames) == nil, "none in ActionBarActionEventsFrame",
        OursIn(ActionBarActionEventsFrame.frames))
    CHECK(#ActionBarButtonEventsFrame.frames == 60, "Blizzard's own 60 buttons all still listed",
        #ActionBarButtonEventsFrame.frames)
    -- A face that holds an action is flagged as Blizzard flags it, yet stays out
    CHECK(Face("NUMPAD7").eventsRegistered == true and ActionBarActionEventsFrame.frames[Face("NUMPAD7")] == nil,
        "a face holding an action keeps Blizzard's flag but not the list")
    -- Blizzard's own grid buttons holding actions are in it, as they should be
    actionSlots[2] = true
    secureExecution = true; ActionButton2:Update(); secureExecution = false
    CHECK(ActionBarActionEventsFrame.frames[ActionButton2] == ActionButton2, "Blizzard's buttons still in their list")

    -- A stance or page change mid-fight: Blizzard's walks and the bar shown after
    EnterCombat()
    CHECK(ActionBarControllerUpdateAll() == false and MainActionBar.__shownExternalTainted == false,
        "page change: the controller's walk and MainActionBar's show stay secure")
    CHECK(FireActionEvent() == false, "SPELL_UPDATE_ICON: Blizzard's action walk stays secure")
    CHECK(#violations == 0, "no blocked call from either walk mid-fight", violations[1])

    -- Our dispatcher hands the faces the same events
    local np, gr = Face("NUMPAD7").__cooldownUpdates or 0, FFace("`").__cooldownUpdates or 0
    Fire("ACTIONBAR_UPDATE_COOLDOWN")
    CHECK((Face("NUMPAD7").__cooldownUpdates or 0) == np + 1 and (FFace("`").__cooldownUpdates or 0) == gr + 1,
        "cooldown updates reach both cards' faces")
    Fire("SPELL_UPDATE_ICON")
    Fire("PLAYER_ENTERING_WORLD")
    CHECK(#violations == 0 and #luaErrors == 0, "our dispatch mid-fight: clean", violations[1] or luaErrors[1])
    LeaveCombat()
    -- Right-clicks never reach a face: the template's right-click path reads
    -- self.action, which we wrote, before casting
    local clicks = table.concat(Face("NUMPAD7").__clicks, " ")
    CHECK(not clicks:find("Right") and not clicks:find("Any"), "faces take the left button only", clicks)
    -- The grid card does not start moving mid-fight
    db.locked = false
    Notify(); Tick()
    EnterCombat()
    backdrop.__moving = false
    backdrop.__scripts.OnDragStart(backdrop)
    CHECK(backdrop.__moving == false and #violations == 0, "no grid drag mid-fight", violations[1])
    backdrop.__scripts.OnDragStop(backdrop)
    LeaveCombat()
    db.locked = true
    Notify(); Tick()
end

-- ===========================================================================
-- P. Settings changed mid-fight: binds wait for combat to drop, and the caps
-- and faces keep showing what the keys really do until then (2.6.0)
-- ===========================================================================
EnterCombat()
ClickCheckbox(bindBox)                      -- Bind Numpad Keys off
Tick()
CHECK(overrideBindings.NUMPAD7 ~= nil and Face("NUMPAD7").HotKey.__text == "7" and Face("NUMPAD7").HotKey.__shown,
    "numpad binds off mid-fight: 7 still bound, and still capped", Face("NUMPAD7").HotKey.__text)
LeaveCombat()
Tick()
CHECK(overrideBindings.NUMPAD7 == nil and Face("NUMPAD7").HotKey.__text ~= "7", "after combat: unbound, cap gone")
ClickCheckbox(bindBox)
Tick()
CHECK(overrideBindings.NUMPAD7 ~= nil and Face("NUMPAD7").HotKey.__text == "7", "numpad binds back")

PickOption(modeDrop, "MARKS")
Tick()
roster.target = { name = "Boss", class = "WARRIOR" }
raidMarks.target = 8
EnterCombat()
PickOption(modeDrop, "PARTY")               -- chosen mid-fight
Tick()
CHECK(Mark("F1"):IsShown() and not Seat("F1"):IsShown() and overrideBindings.F1.button == "CommanderFKeyMarkF1",
    "Party Targets chosen mid-fight: the marks stay up and bound")
CHECK(Mark("F1").__cmdLit.__shown and Mark("F1").HotKey.__shown and Mark("F1").HotKey.__text == "F1",
    "and keep their lit skull and their caps")
ClickCheckbox(fBindBox)                     -- Bind Function Keys off, still mid-fight
Tick()
CHECK(overrideBindings.F2 ~= nil and Mark("F2").HotKey.__shown, "row binds off mid-fight: F2 still bound and capped")
CHECK(#violations == 0, "mid-fight setting changes: no violations", violations[1])
LeaveCombat()
Tick()
CHECK(Seat("F1"):IsShown() and not Mark("F1"):IsShown() and overrideBindings.F1 == nil
    and not Seat("F1").HotKey.__shown, "after combat: party faces, unbound, no caps")
ClickCheckbox(fBindBox)
Tick()
CHECK(overrideBindings.F1 and overrideBindings.F1.button == "CommanderFKeyPartyF1" and Seat("F1").HotKey.__shown,
    "row binds back, on the party faces")
PickOption(modeDrop, "ACTIONS")
Tick()
roster.target, raidMarks.target = nil, nil

do  -- the row's page resets only row options, and gives way on a held bar
    PickOption(digitsDrop, "RIGHT")    -- the numpad takes the row's default bar
    Tick()
    CHECK(db.numpadDigitsBar == "RIGHT" and db.fkeyBar == "BOTTOMRIGHT", "numpad on the row's bar, row traded")
    db.fkeyScale = 0.7
    db.fkeyAnchor = "FREE"
    db.fkeyBindKeys = false
    db.fkeyMode = "PARTY"
    local reset = FindButton(fkeyPanel, "Restore Defaults")
    CHECK(reset ~= nil, "row page has Restore Defaults")
    if reset then reset.__scripts.OnClick(reset) end
    Tick()
    CHECK(db.fkeyScale == 1 and db.fkeyAnchor == "ABOVE" and db.fkeyBindKeys == true
        and db.fkeyMode == "ACTIONS", "row options reset")
    CHECK(db.fkeyBar == "PAGE2" and db.numpadDigitsBar == "RIGHT",
        "the numpad keeps its bar; the row takes the first free one", db.fkeyBar)
    CHECK(db.numpadEnabled == true and db.cardStyle == "DARK", "numpad and card options untouched")
    CHECK(db.fkeyEnabled == false and not row:IsShown() and overrideBindings.F1 == nil,
        "reset turns the row back off (its default)")
    CHECK(card:IsShown() and overrideBindings.NUMPAD7 ~= nil, "the numpad stays up")
end

CHECK(#luaErrors == 0, "no Lua errors", luaErrors[1])
CHECK(#violations == 0, "no protected calls in combat anywhere", violations[1])

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
