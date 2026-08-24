-- Commander Who host + UI harness (luajit).
--
-- Loads the REAL shared framework (CommanderSettingsUI.lua, CommanderEvents.lua)
-- and all four Commander_Who files under a permissive widget mock, on top of a
-- fixtured Who window: seventeen recycled row buttons over a faux scroll frame,
-- exactly as FriendsFrame.xml lays them out.
--
-- The row pool is the whole point. Every reported symptom in the 2.1 build came
-- from treating those seventeen buttons as if there were one per player, so the
-- mock reproduces them faithfully -- fixed count, fixed widgets, an offset that
-- moves under them -- and the checks below scroll the list and assert that the
-- ticks stay with the players.
--
--   /opt/homebrew/bin/luajit who_ui_harness.lua

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end

-- ===========================================================================
-- Widget mock
-- ===========================================================================

local frames, eventRegistry = {}, {}
local NewWidget

local NUMERIC_GETTERS = {
    GetFrameLevel = 1, GetScale = 1, GetEffectiveScale = 1, GetHeight = 0,
    GetID = 0, GetNumPoints = 1, GetAlpha = 1, GetTop = 0, GetBottom = 0,
    GetLeft = 0, GetRight = 0, GetVerticalScroll = 0, GetNumLines = 1,
}

local WidgetMT = {}

local REAL = {}

REAL.Show      = function(s) s.__shown = true end
REAL.Hide      = function(s) s.__shown = false end
REAL.IsShown   = function(s) return s.__shown and true or false end
REAL.IsVisible = function(s) return s.__shown and true or false end
REAL.SetShown  = function(s, v) s.__shown = v and true or false end
REAL.SetChecked = function(s, v) s.__checked = v and true or false end
REAL.GetChecked = function(s) return s.__checked and true or false end
REAL.SetEnabled = function(s, v) s.__enabled = v and true or false end
REAL.Enable     = function(s) s.__enabled = true end
REAL.Disable    = function(s) s.__enabled = false end
REAL.IsEnabled  = function(s) return s.__enabled ~= false end
REAL.SetText    = function(s, t) s.__text = t end
REAL.GetText    = function(s) return s.__text or "" end
REAL.SetWidth   = function(s, w) s.__width = w end
REAL.GetWidth   = function(s) return s.__width or 0 end
REAL.GetStringWidth = function(s) return s.__stringWidth or #tostring(s.__text or "") * 6 end
REAL.SetSize    = function(s, w, h) s.__width, s.__height = w, h end
REAL.GetName    = function(s) return s.__name end
REAL.GetParent  = function(s) return s.__parent end
REAL.SetParent  = function(s, p) s.__parent = p end
REAL.ClearAllPoints = function(s) s.__points = {} end
REAL.SetPoint = function(s, point, rel, relPoint, x, y)
    s.__points = s.__points or {}
    -- The 3-argument form (point, x, y) is legal and the module uses it.
    if type(rel) == "number" then
        point, rel, relPoint, x, y = point, nil, point, rel, relPoint
    end
    s.__points[#s.__points + 1] =
        { point = point, rel = rel, relPoint = relPoint, x = x or 0, y = y or 0 }
end
REAL.GetPoint = function(s, index)
    local p = s.__points and s.__points[index or 1]
    if not p then return nil end
    return p.point, p.rel, p.relPoint, p.x, p.y
end
REAL.SetScript = function(s, name, handler) s.__scripts[name] = handler end
REAL.HookScript = function(s, name, handler)
    local existing = s.__scripts[name]
    if existing then
        s.__scripts[name] = function(...) existing(...) handler(...) end
    else
        s.__scripts[name] = handler
    end
end
REAL.GetScript = function(s, name) return s.__scripts[name] end
REAL.RegisterEvent = function(s, event)
    eventRegistry[event] = eventRegistry[event] or {}
    for _, existing in ipairs(eventRegistry[event]) do
        if existing == s then return end
    end
    table.insert(eventRegistry[event], s)
end
REAL.UnregisterEvent = function(s, event)
    local list = eventRegistry[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == s then table.remove(list, i) end
    end
end

WidgetMT.__index = function(self, key)
    if type(key) ~= "string" then return nil end
    local real = REAL[key]
    if real then rawset(self, key, real) return real end
    if NUMERIC_GETTERS[key] ~= nil then
        local v = NUMERIC_GETTERS[key]
        local fn = function() return v end
        rawset(self, key, fn)
        return fn
    end
    if key == "CreateTexture" then
        local fn = function(s, name)
            local t = NewWidget("Texture", type(name) == "string" and name or nil)
            t.__parent = s
            return t
        end
        rawset(self, key, fn) return fn
    end
    if key == "CreateFontString" then
        local fn = function(s, name)
            local t = NewWidget("FontString", type(name) == "string" and name or nil)
            t.__parent = s
            if type(name) == "string" then _G[name] = t end
            return t
        end
        rawset(self, key, fn) return fn
    end
    if key:match("^Set") or key:match("^Get") or key:match("^Is") or key:match("^Can")
        or key:match("^Register") or key:match("^Unregister") or key:match("^Hook")
        or key:match("^Clear") or key:match("^Create") or key:match("^Start")
        or key:match("^Stop") or key:match("^Add") or key:match("^Raise")
        or key:match("^Lock") or key:match("^Enable") or key:match("^Disable")
        or key:match("^Insert") or key:match("^Highlight") or key:match("^Update") then
        local fn = function() end
        rawset(self, key, fn) return fn
    end
    return nil
end

NewWidget = function(kind, name)
    local w = setmetatable({
        __kind = kind, __name = name, __scripts = {}, __shown = true, __points = {},
    }, WidgetMT)
    if name then _G[name] = w end
    frames[#frames + 1] = w
    return w
end

function CreateFrame(frameType, name, parent, template)
    local f = NewWidget(frameType, name)
    f.__template = template
    f.__parent = parent
    if frameType == "CheckButton" then
        f.Text = NewWidget("FontString")
        f.__checked = false
    end
    if template and tostring(template):find("BasicFrameTemplate") then
        f.CloseButton = NewWidget("Button")
        f.TitleText = NewWidget("FontString")
        f.Inset = NewWidget("Frame")
    end
    return f
end

local function Fire(event, ...)
    for _, frame in ipairs(eventRegistry[event] or {}) do
        local handler = frame.__scripts.OnEvent
        if handler then handler(frame, event, ...) end
    end
end

local function Click(widget, ...)
    local handler = widget and widget.__scripts and widget.__scripts.OnClick
    CHECK(handler ~= nil, "widget has an OnClick", widget and widget.__name)
    if handler then handler(widget, ...) end
end

-- ===========================================================================
-- Client globals
-- ===========================================================================

UIParent = NewWidget("Frame", "UIParent")
UISpecialFrames = {}
CANCEL = "Cancel"
tinsert, tremove = table.insert, table.remove
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
strsplit = function(sep, str)
    local out = {}
    for piece in tostring(str):gmatch("[^" .. sep .. "]+") do out[#out + 1] = piece end
    return unpack(out)
end
strtrim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
strupper, strlower, strfind, strsub = string.upper, string.lower, string.find, string.sub
format = string.format
date = os.date
time = os.time
getmetatable("").__index.trim = strtrim

local printed = {}
local realPrint = print
print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end

geterrorhandler = function()
    return function(err) fails = fails + 1 io.write("LUA ERROR  ", tostring(err), "\n") end
end

local shiftDown = false
IsShiftKeyDown = function() return shiftDown end
IsControlKeyDown = function() return false end
IsAltKeyDown = function() return false end
GetTime = function() return 0 end
GetCursorPosition = function() return 0, 0 end

UnitName = function(unit) return unit == "player" and "Eirik" or "Unknown" end
UnitClass = function() return "Warrior", "WARRIOR" end

LOCALIZED_CLASS_NAMES_MALE = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue",
    PRIEST = "Priest", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock",
    DRUID = "Druid",
}
LOCALIZED_CLASS_NAMES_FEMALE = LOCALIZED_CLASS_NAMES_MALE

RAID_CLASS_COLORS = {}
NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 }

GameTooltip = NewWidget("Frame", "GameTooltip")
GameFontNormal = {}

-- Deferred work, driven by the harness rather than by a clock.
local pending, tickers = {}, {}
C_Timer = {
    After = function(delay, fn) pending[#pending + 1] = { delay = delay, fn = fn } end,
    NewTicker = function(delay, fn, iterations)
        local ticker = { delay = delay, fn = fn, iterations = iterations, cancelled = false }
        function ticker:Cancel() self.cancelled = true end
        tickers[#tickers + 1] = ticker
        return ticker
    end,
}

local function FlushTimers()
    local todo = pending
    pending = {}
    for _, item in ipairs(todo) do item.fn() end
end

-- Advances every live ticker by n beats.
local function TickAll(n)
    for _ = 1, n do
        for _, ticker in ipairs(tickers) do
            if not ticker.cancelled then ticker.fn() end
        end
    end
end

local whispers = {}
SendChatMessage = function(message, channel, language, target)
    whispers[#whispers + 1] = { message = message, channel = channel, target = target }
end

local popups = {}
StaticPopupDialogs = {}
StaticPopup_Show = function(which, arg1, arg2, data)
    popups[#popups + 1] = { which = which, text = arg1, data = data }
    return popups[#popups]
end
local function AcceptLastPopup()
    local popup = popups[#popups]
    CHECK(popup ~= nil, "a popup was raised")
    if not popup then return end
    StaticPopupDialogs[popup.which].OnAccept(nil, popup.data)
end

C_AddOns = { GetAddOnMetadata = function() return "3.0.0" end }
SlashCmdList = {}

function UIDropDownMenu_Initialize() end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton() end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetSelectedValue() end
function UIDropDownMenu_SetText() end
function UIDropDownMenu_EnableDropDown() end
function UIDropDownMenu_DisableDropDown() end

Settings = {
    RegisterCanvasLayoutCategory = function(_, name)
        return { GetID = function() return name end, ID = name, name = name }
    end,
    RegisterCanvasLayoutSubcategory = function(_, panel, name)
        return { GetID = function() return name end, ID = name, name = name }
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
}

local hooks = {}
function hooksecurefunc(name, post)
    local original = _G[name]
    hooks[#hooks + 1] = name
    _G[name] = function(...)
        local results = { original(...) }
        post(...)
        return unpack(results)
    end
end

-- ---------------------------------------------------------------------------
-- The Who window, as FriendsFrame.xml builds it
-- ---------------------------------------------------------------------------

local WHOS_TO_DISPLAY_COUNT = 17
WHOS_TO_DISPLAY = WHOS_TO_DISPLAY_COUNT

FriendsFrame = CreateFrame("Frame", "FriendsFrame", UIParent)
WhoFrame = CreateFrame("Frame", "WhoFrame", FriendsFrame)
WhoListScrollFrame = CreateFrame("ScrollFrame", "WhoListScrollFrame", WhoFrame)
WhoListScrollFrame.__offset = 0

for i = 1, WHOS_TO_DISPLAY_COUNT do
    local button = CreateFrame("Button", "WhoFrameButton" .. i, WhoFrame)
    button:SetSize(300, 16)
    local nameText = button:CreateFontString("WhoFrameButton" .. i .. "Name")
    -- A real column width, so the narrowing branch in ShiftName is exercised.
    nameText:SetWidth(100)
    nameText.__stringWidth = 40
    nameText:SetPoint("LEFT", button, "LEFT", 5, 0)
end

FauxScrollFrame_GetOffset = function(f) return f.__offset or 0 end
FauxScrollFrame_Update = function(f, num, display, height)
    f.__numItems, f.__display, f.__step = num, display, height
end
FauxScrollFrame_OnVerticalScroll = function(f, offset, step, updater)
    f.__offset = math.floor((offset or 0) / (step or 1))
    if updater then updater() end
end

-- The client's own list repaint. Our hook rides on it, so the harness calls
-- this to mean "Blizzard redrew the list", exactly as a scroll or a sort does.
local whoListUpdates = 0
function WhoList_Update()
    whoListUpdates = whoListUpdates + 1
end

local whoResults = {}
C_FriendList = {
    GetNumWhoResults = function() return #whoResults end,
    GetWhoInfo = function(i) return whoResults[i] end,
}

local function Who(name, level, class, token, zone, guild)
    return { fullName = name, level = level, classStr = class, filename = token,
             area = zone, fullGuildName = guild or "", raceStr = "Human", gender = 2 }
end

local ROSTER = {
    Who("Alaric",  70, "Paladin", "PALADIN", "Shattrath City", "Vanguard"),
    Who("Brenna",  68, "Mage",    "MAGE",    "Nagrand"),
    Who("Corwin",  70, "Rogue",   "ROGUE",   "Terokkar Forest"),
    Who("Dagny",   64, "Shaman",  "SHAMAN",  "Zangarmarsh"),
    Who("Eirik",   70, "Warrior", "WARRIOR", "Shadowmoon Valley"),   -- the player
    Who("Fenna",   70, "Priest",  "PRIEST",  "Shattrath City"),
    Who("Gorrim",  61, "Hunter",  "HUNTER",  "Hellfire Peninsula"),
    Who("Halvard", 70, "Warlock", "WARLOCK", "Netherstorm"),
    Who("Ingrid",  70, "Druid",   "DRUID",   "Blade's Edge"),
    Who("Jorund",  58, "Warrior", "WARRIOR", "Blasted Lands"),
}

local function SetResults(list)
    whoResults = list
    Fire("WHO_LIST_UPDATE")
end

local function Scroll(offset)
    WhoListScrollFrame.__offset = offset
    WhoList_Update()          -- the hook rides on this, as it does in the client
end

-- ===========================================================================
-- Load
-- ===========================================================================

local function Load(path) assert(loadfile(path))() end

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")

CHECK(type(Commander.AddListener) == "function", "the real event bus loaded")
CHECK(type(Commander.UI.NewPanel) == "function", "the real settings framework loaded")

-- A saved-variables table from the 2.1 schema, so the migration is exercised
-- rather than assumed.
CommanderWhoDB = {
    ShowWhoWindow = false,
    ShowWhoButton = true,
    MaxWhisperCount = 50,
    WhisperDelay = 0.2,
}

Load(ADDONS .. "/Commander_Who/CommanderWhoEngine.lua")
Load(ADDONS .. "/Commander_Who/CommanderWhoDB.lua")
Load(ADDONS .. "/Commander_Who/CommanderWho.lua")
Load(ADDONS .. "/Commander_Who/CommanderWhoUI.lua")

Fire("ADDON_LOADED", "Commander_Who")
Fire("PLAYER_LOGIN")
FlushTimers()

local E = CommanderWhoEngine
local Host = CommanderWho
local Win = CommanderWhoUI

-- ===========================================================================
-- Saved variables and slash commands
-- ===========================================================================

CHECK(CommanderWhoDB.ShowToolbar == true, "ShowWhoButton migrated to ShowToolbar")
CHECK(CommanderWhoDB.ShowWhoButton == nil, "the old key is gone")
CHECK(CommanderWhoDB.ShowWhoWindow == nil,
    "ShowWhoWindow is deleted -- it hid Blizzard's own Who panel out from under its tab")
CHECK(CommanderWhoDB.WhisperDelay == 0.3, "a sub-floor saved delay is clamped into the slider's range")
CHECK(CommanderWhoDB.MaxWhisperCount == 50, "a legal saved cap is left alone")
CHECK(CommanderWhoDB.SelectNewResults == false, "new results are not pre-selected by default")
CHECK(CommanderWhoDB.ConfirmBeforeSending == true, "confirmation is on by default")
CHECK(CommanderWhoDB.WindowStyle ~= nil, "the shared window chrome defaults are installed")

do
    -- The reported chat bug. "/cw" is two characters away from the whisper
    -- family in the chat edit box's command matching, and it was the only
    -- source of that string anywhere in the suite.
    local registered = {}
    for key in pairs(SlashCmdList or {}) do
        for i = 1, 8 do
            local cmd = _G["SLASH_" .. key .. i]
            if not cmd then break end
            registered[cmd:lower()] = key
        end
    end
    CHECK(registered["/cw"] == nil, "'/cw' is no longer registered")
    CHECK(registered["/cwho"] ~= nil, "'/cwho' still is")
    CHECK(registered["/w"] == nil, "and nothing in this module claims '/w'")
end

-- ===========================================================================
-- The Who tab
-- ===========================================================================

CHECK(WhoFrameButton1 ~= nil, "the fixture built the row pool")

SetResults(ROSTER)

local function RowCheck(i)
    -- Whatever the module hung off the row button, found the way a reader
    -- would: the only CheckButton parented to it.
    for _, widget in ipairs(frames) do
        if widget.__kind == "CheckButton" and widget.__parent == _G["WhoFrameButton" .. i] then
            return widget
        end
    end
end

CHECK(RowCheck(1) ~= nil, "a tick box was added to row 1")
CHECK(RowCheck(17) ~= nil, "and to row 17")
CHECK(RowCheck(1):IsShown(), "row 1's box is shown -- there is a result there")
CHECK(RowCheck(10):IsShown(), "row 10's box is shown -- ten results")
CHECK(RowCheck(11):IsShown() == false, "row 11's box is hidden -- past the end of the list")

CHECK(Host.Records() and #Host.Records() == 10, "the host built ten records")
CHECK(Host.SelectedCount() == 0, "nothing is selected by default")
CHECK(RowCheck(1):GetChecked() == false, "and no box starts ticked")

-- --- the reported scrolling bug ---------------------------------------------

Click(RowCheck(1))           -- the mock's CheckButton does not auto-toggle
CHECK(false == RowCheck(1):GetChecked(), "sanity: the mock leaves toggling to the client")
RowCheck(1):SetChecked(true)
Click(RowCheck(1))
CHECK(Host.SelectedCount() == 1, "ticking row 1 selects one player")
CHECK(Host.IsSelected("alaric"), "and it is Alaric, the player in row 1")

RowCheck(6):SetChecked(true)
Click(RowCheck(6))
CHECK(Host.SelectedCount() == 2, "ticking row 6 selects a second")
CHECK(Host.IsSelected("fenna"), "and it is Fenna")

Scroll(4)
CHECK(RowCheck(1):GetChecked() == false,
    "AFTER SCROLLING, row 1 now holds Eirik and is NOT wearing Alaric's tick")
CHECK(RowCheck(2):GetChecked() == true, "and Fenna, now in row 2, still carries hers")
CHECK(Host.SelectedCount() == 2, "scrolling changed no selection")

Scroll(6)
CHECK(RowCheck(1):GetChecked() == false, "row 1 is Gorrim, unticked")
CHECK(RowCheck(4):GetChecked() == false, "row 4 is Jorund, unticked")
CHECK(RowCheck(5):IsShown() == false, "row 5 is past the end and hidden")

Scroll(0)
CHECK(RowCheck(1):GetChecked() == true, "scrolling back restores Alaric's tick")
CHECK(RowCheck(6):GetChecked() == true, "and Fenna's")
CHECK(Host.SelectedCount() == 2, "still exactly two selected")

-- --- ticking while scrolled -------------------------------------------------

Scroll(5)
RowCheck(1):SetChecked(true)   -- row 1 at offset 5 is Fenna... no: index 6
Click(RowCheck(1))
CHECK(Host.IsSelected("fenna"), "row 1 at offset 5 is Fenna and she stays selected")
RowCheck(3):SetChecked(true)
Click(RowCheck(3))
CHECK(Host.IsSelected("halvard"), "row 3 at offset 5 is Halvard, and ticking it selects HIM")
CHECK(Host.IsSelected("corwin") == false, "not Corwin, who is the third player in the list")
Scroll(0)
CHECK(RowCheck(8):GetChecked() == true, "back at the top, Halvard's box (row 8) is the ticked one")
CHECK(RowCheck(3):GetChecked() == false, "and Corwin's (row 3) is not")

-- --- shift-click ranges -----------------------------------------------------

Host.SelectNone()
CHECK(Host.SelectedCount() == 0, "cleared")
RowCheck(2):SetChecked(true)
Click(RowCheck(2))
shiftDown = true
RowCheck(6):SetChecked(true)
Click(RowCheck(6))
shiftDown = false
CHECK(Host.SelectedCount() == 5, "shift-click fills the range from the anchor", Host.SelectedCount())
CHECK(Host.IsSelected("brenna") and Host.IsSelected("fenna"), "inclusive at both ends")
CHECK(Host.IsSelected("alaric") == false, "and stops at the anchor")

-- --- select all / none / invert ---------------------------------------------

Host.SelectAll()
CHECK(Host.SelectedCount() == 10, "Select All ticks every result")
CHECK(RowCheck(1):GetChecked() and RowCheck(10):GetChecked(), "and the boxes repaint")
Host.SelectInvert()
CHECK(Host.SelectedCount() == 0, "Invert of everything is nothing")
Host.SelectInvert()
CHECK(Host.SelectedCount() == 10, "and back")
Host.SelectNone()
CHECK(Host.SelectedCount() == 0, "Select None clears")
CHECK(RowCheck(4):GetChecked() == false, "and repaints")

-- --- selection survives a re-search ------------------------------------------

Host.SetSelected("brenna", true)
Host.SetSelected("halvard", true)
SetResults({ ROSTER[2], ROSTER[3], ROSTER[5] })   -- Brenna, Corwin, Eirik
CHECK(#Host.Records() == 3, "a narrower search replaces the record list")
CHECK(Host.IsSelected("brenna"), "a tick survives for a player who is still in the results")
CHECK(Host.IsSelected("halvard") == false, "and is dropped for one who is not")
CHECK(Host.SelectedCount() == 1, "so the count cannot promise a send it cannot make")
CHECK(RowCheck(4):IsShown() == false, "rows past the new, shorter list are hidden")

SetResults(ROSTER)
CHECK(Host.IsSelected("brenna"), "searching again keeps the tick you had already made")
CHECK(Host.SelectedCount() == 1, "and does not resurrect the dropped one")

-- --- pre-select option -------------------------------------------------------

CommanderWhoDB.SelectNewResults = true
SetResults(ROSTER)
CHECK(Host.SelectedCount() == 10, "with the option on, a new search arrives fully ticked")
CommanderWhoDB.SelectNewResults = false
Host.SelectNone()

-- --- the tick boxes are reversible -------------------------------------------

do
    local nameText = WhoFrameButton1Name
    local _, _, _, shiftedX = nameText:GetPoint(1)
    CHECK(shiftedX == 20, "the name font string was shifted right to make room", shiftedX)
    CHECK(nameText:GetWidth() == 85, "and narrowed by the same amount", nameText:GetWidth())

    CommanderWhoDB.ShowRowCheckboxes = false
    Commander.Notify(COMMANDER_WHO_EVENTS.UPDATE)
    CHECK(RowCheck(1):IsShown() == false, "turning the option off hides the boxes")
    local _, _, _, restoredX = nameText:GetPoint(1)
    CHECK(restoredX == 5, "and puts the name font string back where Blizzard had it", restoredX)
    CHECK(nameText:GetWidth() == 100, "at its original width", nameText:GetWidth())

    CommanderWhoDB.ShowRowCheckboxes = true
    Commander.Notify(COMMANDER_WHO_EVENTS.UPDATE)
    CHECK(RowCheck(1):IsShown() == true, "and turning it back on restores them")
    local _, _, _, reshiftedX = WhoFrameButton1Name:GetPoint(1)
    CHECK(reshiftedX == 20, "shifted once, not twice", reshiftedX)
end

-- --- the toolbar --------------------------------------------------------------

do
    local bar = CommanderWhoToolbar
    CHECK(bar ~= nil, "the toolbar exists")
    CHECK(bar:IsShown(), "and is shown by default")
    Host.SelectNone()
    CHECK(bar.count:GetText() == "0 / 10", "it counts nothing selected", bar.count:GetText())
    Host.SetSelected("corwin", true)
    CHECK(bar.count:GetText() == "1 / 10", "and updates as you tick", bar.count:GetText())
    Host.SelectAll()
    CHECK(bar.count:GetText() == "10 / 10", "and when you take the lot", bar.count:GetText())

    CommanderWhoDB.ShowToolbar = false
    Commander.Notify(COMMANDER_WHO_EVENTS.UPDATE)
    CHECK(bar:IsShown() == false, "the option hides it")
    CHECK(WhoFrame:IsShown(), "and never touches Blizzard's Who frame")
    CommanderWhoDB.ShowToolbar = true
    Commander.Notify(COMMANDER_WHO_EVENTS.UPDATE)
    CHECK(bar:IsShown(), "and shows it again")
end

-- ===========================================================================
-- The mass whisper window
-- ===========================================================================

Win.Open()
local win = Win.Frame()
CHECK(win ~= nil and win:IsShown(), "the window opens")

local function WindowRows()
    local out = {}
    for _, widget in ipairs(frames) do
        if widget.__kind == "Button" and widget.__parent == win and widget.name and widget.check then
            out[#out + 1] = widget
        end
    end
    table.sort(out, function(a, b) return (a.recordIndex or 99) < (b.recordIndex or 99) end)
    return out
end

do
    Host.SelectNone()
    Host.SetSelected("brenna", true)
    Host.SetSelected("halvard", true)
    local rows = WindowRows()
    CHECK(#rows == 14, "the window pools fourteen rows for any result count", #rows)

    local shown = 0
    for _, row in ipairs(rows) do
        if row:IsShown() then shown = shown + 1 end
    end
    CHECK(shown == 10, "ten of them are painted for ten results", shown)

    local byName = {}
    for _, row in ipairs(rows) do
        if row.record then byName[row.record.name] = row end
    end
    CHECK(byName.Brenna and byName.Brenna.check:GetChecked() == true,
        "Brenna's row in the window shows the tick made on the Who tab")
    CHECK(byName.Alaric and byName.Alaric.check:GetChecked() == false,
        "and an unticked player shows unticked")
    CHECK(byName.Brenna.class:GetText() == "Mage",
        "the class column is populated -- 2.1 read a field this client does not send",
        byName.Brenna.class:GetText())
    CHECK(byName.Brenna.level:GetText() == "68", "as is the level")
    CHECK(byName.Brenna.zone:GetText() == "Nagrand", "and the zone")
end

do
    -- Ticking in the window moves the tick on the Who tab: one model, two views.
    local rows = WindowRows()
    local alaric
    for _, row in ipairs(rows) do
        if row.record and row.record.name == "Alaric" then alaric = row end
    end
    alaric.check:SetChecked(true)
    Click(alaric.check)
    CHECK(Host.IsSelected("alaric"), "ticking a window row selects the player")
    CHECK(RowCheck(1):GetChecked() == true, "and the Who tab's row 1 box ticks with it")
    alaric.check:SetChecked(false)
    Click(alaric.check)
    CHECK(Host.IsSelected("alaric") == false, "and unticking unselects")
    CHECK(RowCheck(1):GetChecked() == false, "on both views")
end

-- --- the reported mass whisper bug --------------------------------------------

do
    whispers = {}
    popups = {}
    Host.SelectNone()
    Host.SetSelected("brenna", true)
    Host.SetSelected("halvard", true)

    local plan = Host.BuildPlan()
    CHECK(plan.count == 2, "the plan targets exactly the two ticked players", plan.count)

    local ok, why = Host.StartRun("")
    CHECK(ok == false and why:find("Type a message"), "an empty message is refused", why)
    CHECK(#whispers == 0, "and nothing was sent")

    Host.StartRun("Recruiting for Kara, whisper back")
    CHECK(#popups == 1, "confirmation is asked for first")
    CHECK(popups[1].text:find("Whispering 2 players"), "and names the count", popups[1].text)
    CHECK(#whispers == 0, "nothing goes out before the confirm")

    AcceptLastPopup()
    CHECK(#whispers == 1, "the first whisper goes out immediately", #whispers)
    CHECK(whispers[1].target == "Brenna", "to the first ticked player in list order", whispers[1].target)
    CHECK(whispers[1].channel == "WHISPER", "on the whisper channel")
    CHECK(whispers[1].message == "Recruiting for Kara, whisper back", "with the typed message")

    TickAll(1)
    CHECK(#whispers == 2, "the ticker sends the second")
    CHECK(whispers[2].target == "Halvard", "to the other ticked player")

    TickAll(3)
    CHECK(#whispers == 2, "AND STOPS -- the eight unticked players are never messaged", #whispers)
    CHECK(Host.IsRunning() == false, "the run finished")
    CHECK(Host.CurrentRun():Progress() == "Sent 2 whispers.",
        "and says so, which the 2.1 build never managed",
        Host.CurrentRun():Progress())
end

-- --- the cap is reported, not silently applied ---------------------------------

do
    whispers = {}
    popups = {}
    CommanderWhoDB.MaxWhisperCount = 3
    Host.SelectAll()
    local plan = Host.BuildPlan()
    CHECK(plan.selected == 10, "ten are ticked")
    CHECK(plan.count == 3, "three fit under the cap")
    CHECK(plan.skippedSelf == 1, "and the player themself is not one of the recipients")
    CHECK(plan.overCap == 6, "leaving six over the cap", plan.overCap)

    Host.StartRun("hello")
    CHECK(popups[1].text:find("6 over the 3 cap"), "the confirm names the shortfall", popups[1].text)
    AcceptLastPopup()
    TickAll(5)
    CHECK(#whispers == 3, "exactly three go out")
    for _, whisper in ipairs(whispers) do
        CHECK(whisper.target ~= "Eirik", "and never to yourself", whisper.target)
    end
    CommanderWhoDB.MaxWhisperCount = 50
end

-- --- stop mid-run ---------------------------------------------------------------

do
    whispers = {}
    popups = {}
    Host.SelectAll()
    Host.StartRun("hi")
    AcceptLastPopup()
    CHECK(#whispers == 1, "one sent")
    TickAll(1)
    CHECK(#whispers == 2, "two sent")
    CHECK(Host.IsRunning(), "still running")
    Host.StopRun()
    CHECK(Host.IsRunning() == false, "Stop ends the run")
    TickAll(5)
    CHECK(#whispers == 2, "and no further whisper goes out", #whispers)
    CHECK(Host.CurrentRun():Progress():find("Stopped after 2 of 9"),
        "the window can say where it stopped", Host.CurrentRun():Progress())
end

-- --- a second run cannot start on top of the first ---------------------------

do
    whispers = {}
    CommanderWhoDB.ConfirmBeforeSending = false
    Host.SelectAll()
    Host.StartRun("first")
    CHECK(Host.IsRunning(), "the run started without a confirm when the option is off")
    local ok, why = Host.StartRun("second")
    CHECK(ok == false and why:find("already running"), "a second run is refused", why)
    Host.StopRun()
    CommanderWhoDB.ConfirmBeforeSending = true
end

-- --- declining the confirmation ------------------------------------------------

do
    whispers = {}
    popups = {}
    Win.Open()
    Host.SelectNone()
    Host.SetSelected("brenna", true)
    Host.SetSelected("corwin", true)
    Host.StartRun("maybe not")
    CHECK(#popups == 1, "the confirm is raised")
    StaticPopupDialogs[popups[1].which].OnCancel()
    CHECK(#whispers == 0, "declining sends nothing")
    CHECK(Host.IsRunning() == false, "and starts no run")
    CHECK(CommanderWhoWhisperFrame ~= nil, "the window is still there")
end

-- --- the idle progress line previews what Send would do -------------------------

do
    Win.Open()
    Host.SelectNone()
    Host.SetSelected("brenna", true)
    Host.SetSelected("corwin", true)
    local line
    for _, widget in ipairs(frames) do
        if widget.__kind == "FontString" and widget.__parent == Win.Frame()
            and tostring(widget:GetText()):find("^Whispering") then
            line = widget:GetText()
        end
    end
    CHECK(line == "Whispering 2 players.",
        "with two ticked and no run going, the window says what Send would do", line)
end

-- --- an over-length message ----------------------------------------------------

do
    Host.SelectNone()
    Host.SetSelected("brenna", true)
    local ok, why = Host.StartRun(string.rep("z", 300))
    CHECK(ok == false and why:find("over the 255 limit"), "an over-length message is refused", why)
end

-- --- nothing selected ----------------------------------------------------------

do
    Host.SelectNone()
    local ok, why = Host.StartRun("anyone about?")
    CHECK(ok == false and why:find("Nothing is selected"), "sending with nothing ticked is refused", why)
end

-- --- the window scrolls ---------------------------------------------------------

do
    local many = {}
    for i = 1, 40 do
        many[i] = Who("Filler" .. i, 70, "Mage", "MAGE", "Nagrand")
    end
    SetResults(many)
    Win.Open()
    local scroll = CommanderWhoWhisperScroll
    CHECK(scroll.__numItems == 40, "the faux scroll frame is told the real item count", scroll.__numItems)
    CHECK(scroll.__display == 14, "and how many rows are visible")

    local first
    for _, row in ipairs(WindowRows()) do
        if row.recordIndex == 1 then first = row end
    end
    CHECK(first and first.record.name == "Filler1", "row 1 is the first result")

    FauxScrollFrame_OnVerticalScroll(scroll, 18 * 20, 18, scroll.__scriptUpdater)
    scroll.__offset = 20
    Win.Open()
    local top
    for _, row in ipairs(WindowRows()) do
        if row:IsShown() and (not top or row.recordIndex < top.recordIndex) then top = row end
    end
    CHECK(top and top.record.name == "Filler21",
        "after scrolling the top row is the twenty-first result",
        top and top.record and top.record.name)
    scroll.__offset = 0
end

-- ===========================================================================
-- Nothing errored, nothing leaked
-- ===========================================================================

do
    SetResults(ROSTER)
    Host.SelectNone()
    Win.Close()
    CHECK(win:IsShown() == false, "the window closes")
    -- A repaint with the window closed must be a no-op, not an error.
    Commander.Notify(COMMANDER_WHO_EVENTS.SELECTION)
    Commander.Notify(COMMANDER_WHO_EVENTS.UPDATE)
    CHECK(true, "notifies with the window closed are harmless")

    local escapes = 0
    for _, name in ipairs(UISpecialFrames) do
        if name == "CommanderWhoWhisperFrame" then escapes = escapes + 1 end
    end
    CHECK(escapes == 1, "the window is registered for Escape exactly once", escapes)
end

do
    local hooked = {}
    for _, name in ipairs(hooks) do hooked[name] = true end
    CHECK(hooked.WhoList_Update, "the module rides Blizzard's own list repaint")
end

-- ===========================================================================

if fails > 0 then
    realPrint(string.format("\n%d/%d checks FAILED", fails, checks))
    os.exit(1)
end
realPrint(string.format("who_ui_harness: %d checks passed", checks))
