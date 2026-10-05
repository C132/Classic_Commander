-- Commander Quest Log: the WoW client the window harnesses run on (luajit).
--
-- Not a harness: the permissive client mock questlog_harness.lua was written
-- against, lifted out of it so another harness file can drive the window --
-- the Log, the Zones tab, the Reputations tab, the quest dialog -- on the
-- same client without copying six hundred lines. It installs its globals the
-- moment it is loaded, so load it FIRST, once per process:
--
--   local mock = dofile(ADDONS .. "/Commander_QuestLog/Harness/questlog_mock.lua")
--   local Fake = dofile(mock.ADDONS .. "/Commander_QuestLog/Harness/fake_questie.lua")
--   local world = Fake.DefaultWorld()          -- or a world of your own
--   local fake = Fake.Install(world)
--   Fake.InstallClient(world)
--   mock.LoadFramework()                       -- CommanderSettingsUI + CommanderEvents
--   mock.LoadModule(mock.TocFiles({ "CommanderQuestLogMap.lua" }))
--   mock.Login()                               -- ADDON_LOADED, then PLAYER_LOGIN
--   local CHECK, Done = mock.Checker()
--   ...
--   Done()                                     -- prints "n checks, m failures", exits
--
-- The quest log is `mock.state.log`, a list of entries in log order mutated by
-- hand (mock.Header(title), mock.Quest{ title, level, questID, objectives,
-- isComplete, frequency, description, objectivesText, money, rewards,
-- choices, spell, pushable, timeLeft }). Every other piece of client state the
-- mock keeps is in mock.state too: now, selection, watched, watchLimit,
-- abandoned, pushed, abandonArmed, expandCalls, inRaid, inParty, inGuild,
-- chatSent, popupsShown, hiddenPanels, savedInstances, raidInfoRequests.
-- mock.Bind lets a harness keep any of them in locals of its own instead
-- (questlog_harness.lua does, so its sections read `log` and `selection` as
-- they always have).
--
-- What the mock is careful about (each paid for in questlog_harness.lua):
--   * The quest log is MUTABLE and its INDICES MOVE. Every index bug this
--     module can have is an index that went stale between the row being drawn
--     and the button being pressed, and a fixture whose indices never move
--     proves nothing. Collapsing a header REMOVES its quests from the index
--     space exactly as the client does.
--   * Show/Hide fire OnShow/OnHide, because the window does all its work in
--     OnShow -- and, as in the client, Show on a frame that is already shown
--     fires NOTHING.
--   * A button's normal and highlight font objects are recorded, and the
--     fonts carry their own colours, so a hover's font swap (which puts the
--     font's colour back over a label's ink) can be acted out (HoverButton,
--     HoverIn, HoverOut).
--   * The vertical scroll offset of a ScrollFrame is kept, not a constant 0.
--   * Widths and heights are tracked for real; GetStringWidth answers 40 and
--     GetStringHeight 12 for every string.
--   * Frame levels are tracked, so "this sits above that" is a real check.
--   * Any other Set*/Get*/Is*/... method is a silent no-op (a Get answers
--     nil), so a widget call the mock never heard of costs nothing.

local M = {}

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
M.ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"

-- ===========================================================================
-- State
--
-- Every value the client functions below read or write, behind one table.
-- A key a harness has bound (mock.Bind) is read and written through the
-- harness's own getter and setter; every other key lives here.
-- ===========================================================================

local defaults = {
    now = 1000,
    log = {}, selection = 0, watched = {}, watchLimit = 5,
    abandoned = {}, pushed = {}, abandonArmed = nil, expandCalls = 0,
    inRaid = false, inParty = false, inGuild = true,
    chatSent = {}, popupsShown = {}, hiddenPanels = {},
    savedInstances = {}, raidInfoRequests = 0,
}
local bound, getter, setter = {}, nil, nil

local ST = setmetatable({}, {
    __index = function(_, key)
        if bound[key] then return getter(key) end
        return defaults[key]
    end,
    __newindex = function(_, key, value)
        if bound[key] then setter(key, value) else defaults[key] = value end
    end,
})
M.state = ST

-- keys: the names a harness keeps itself; get(key) -> value, set(key, value)
function M.Bind(keys, get, set)
    for _, key in ipairs(keys) do bound[key] = true end
    getter, setter = get, set
end

-- ===========================================================================
-- WoW mock
-- ===========================================================================

function GetTime() return ST.now end
function time() return 1700000000 end
date = os.date

-- The two reset clocks. Server epoch 1700000000 is Tuesday 2023-11-14
-- 22:13:20 UTC; the server is a US realm on Pacific Standard Time, so
-- GetGameTime answers 14:13. The next daily reset is Wednesday 15:00 UTC,
-- 60400 seconds out, and the next Tuesday reset is six days after that.
local clock = {
    serverTime = 1700000000, gameHour = 14, gameMinute = 13, region = 1,
    daily = 60400, apiWeekly = 60400 + 6 * 86400,
    dailyDone = 3, dailyMax = 25,
}
M.clock = clock
function GetServerTime() return clock.serverTime end
function GetGameTime() return clock.gameHour, clock.gameMinute end
function GetCurrentRegion() return clock.region end
function GetQuestResetTime() return clock.daily end
function GetDailyQuestsCompleted() return clock.dailyDone end
function GetMaxDailyQuests() return clock.dailyMax end
C_DateAndTime = {
    GetSecondsUntilWeeklyReset = function() return clock.apiWeekly end,
    GetSecondsUntilDailyReset = function() return clock.daily end,
}
function RequestRaidInfo() ST.raidInfoRequests = ST.raidInfoRequests + 1 end
function GetNumSavedInstances() return #ST.savedInstances end
function GetSavedInstanceInfo(index)
    local i = ST.savedInstances[index]
    if not i then return nil end
    return i.name, 100 + index, i.reset, i.difficulty or 1, i.locked ~= false, i.extended or false,
        0, i.isRaid ~= false, i.maxPlayers or 10, i.difficultyName or "Normal"
end
function GetBuildInfo() return "2.5.6", "69546", "Aug 28 2026", 20506 end

local printLog = {}
M.printLog = printLog
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    printLog[#printLog + 1] = table.concat(parts, " ")
end
-- The first printed line holding `pattern` (plain text, not a Lua pattern)
function M.Logged(pattern)
    for _, line in ipairs(printLog) do
        if line:find(pattern, 1, true) then return line end
    end
    return nil
end
function M.WipeLog() for i = #printLog, 1, -1 do printLog[i] = nil end end

local caughtErrors = {}
M.caughtErrors = caughtErrors
local errorHandler = function(err) caughtErrors[#caughtErrors + 1] = tostring(err) end
function geterrorhandler() return errorHandler end
function seterrorhandler(fn) errorHandler = fn end

local eventRegistry = {}
M.eventRegistry = eventRegistry
local NewWidget

local NUMERIC_GETTERS = {
    GetScale = 1, GetEffectiveScale = 1, GetFrameLevel = 2,
    GetLeft = 0, GetBottom = 0, GetTop = 0, GetRight = 0,
    GetVerticalScroll = 0, GetVerticalScrollRange = 0,
    GetStringWidth = 40, GetStringHeight = 12,
    GetID = 1, GetNumPoints = 1, NumLines = 0,
}

local METHOD_PREFIXES = {
    "Set", "Enable", "Disable", "Register", "Unregister", "Clear",
    "Start", "Stop", "Raise", "Lower", "Lock", "Play", "Add", "Highlight",
    "Is", "Can", "Get", "Hook", "Create", "Update",
}

local function IsAutoMethod(key)
    for _, prefix in ipairs(METHOD_PREFIXES) do
        if key:sub(1, #prefix) == prefix then return true end
    end
    return false
end

local WidgetMT = {}
local FireScript

WidgetMT.__index = function(self, key)
    if type(key) ~= "string" then return nil end
    local fn
    if key == "SetWidth" then fn = function(s, w) s.__w = w end
    elseif key == "GetWidth" then fn = function(s) return s.__w or 0 end
    elseif key == "SetHeight" then fn = function(s, h) s.__h = h end
    elseif key == "GetHeight" then fn = function(s) return s.__h or 0 end
    elseif key == "SetSize" then fn = function(s, w, h) s.__w, s.__h = w, h end
    elseif key == "SetPoint" then
        fn = function(s, point, rel, relPoint, x, y)
            s.__points = s.__points or {}
            s.__points[#s.__points + 1] = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
        end
    elseif key == "GetPoint" then
        fn = function(s)
            local p = s.__points and s.__points[1]
            if not p then return nil end
            return p.point, p.rel, p.relPoint, p.x or 0, p.y or 0
        end
    elseif key == "ClearAllPoints" then fn = function(s) s.__points = {} end
    elseif key == "SetText" then fn = function(s, text) s.__text = text end
    elseif key == "GetText" then fn = function(s) return s.__text end
    elseif key == "SetTextColor" or key == "SetColorTexture" or key == "SetVertexColor" then
        fn = function(s, r, g, b, a) s.__color = { r, g, b, a } end
    elseif key == "SetBackdropColor" then
        fn = function(s, r, g, b, a) s.__backdropColor = { r, g, b, a } end
    elseif key == "SetAlpha" then fn = function(s, a) s.__alpha = a end
    elseif key == "GetAlpha" then fn = function(s) return s.__alpha or 1 end
    elseif key == "Show" then
        fn = function(s)
            local was = s.__shown
            s.__shown = true
            if not was then FireScript(s, "OnShow") end
        end
    elseif key == "Hide" then
        fn = function(s) s.__shown = false; FireScript(s, "OnHide") end
    elseif key == "SetShown" then
        fn = function(s, shown)
            shown = not not shown
            if s.__shown ~= shown then
                s.__shown = shown
                FireScript(s, shown and "OnShow" or "OnHide")
            end
        end
    elseif key == "IsShown" or key == "IsVisible" then fn = function(s) return s.__shown end
    -- Frame levels are tracked, so "this sits above that" is a real check
    elseif key == "SetFrameLevel" then fn = function(s, level) s.__level = level end
    elseif key == "SetWordWrap" then fn = function(s, on) s.__wordWrap = on end
    elseif key == "SetVerticalScroll" then fn = function(s, offset) s.__vscroll = offset end
    elseif key == "GetVerticalScroll" then fn = function(s) return s.__vscroll or 0 end
    elseif key == "SetNormalFontObject" then fn = function(s, font) s.__normalFont = font end
    elseif key == "SetHighlightFontObject" then fn = function(s, font) s.__highlightFont = font end
    elseif key == "GetFrameLevel" then fn = function(s) return s.__level or 2 end
    elseif key == "SetFocus" then fn = function(s) s.__focused = true end
    elseif key == "ClearFocus" then fn = function(s) s.__focused = false end
    elseif key == "HasFocus" then fn = function(s) return s.__focused == true end
    elseif key == "SetEnabled" then fn = function(s, on) s.__enabled = not not on end
    elseif key == "IsEnabled" then fn = function(s) return s.__enabled ~= false end
    elseif key == "CreateTexture" then
        fn = function(s, name, layer)
            local t = NewWidget("Texture"); t.__parent = s; t.__layer = layer
            s.__textures = s.__textures or {}
            s.__textures[#s.__textures + 1] = t
            return t
        end
    elseif key == "CreateFontString" then
        fn = function(s, name, layer, template)
            local t = NewWidget("FontString"); t.__parent = s; t.__template = template
            s.__fontStrings = s.__fontStrings or {}
            s.__fontStrings[#s.__fontStrings + 1] = t
            return t
        end
    elseif key == "SetScript" or key == "HookScript" then
        fn = function(s, name, handler)
            if key == "HookScript" and s.__scripts[name] then
                local previous = s.__scripts[name]
                s.__scripts[name] = function(...) previous(...) handler(...) end
            else
                s.__scripts[name] = handler
            end
        end
    elseif key == "GetScript" then fn = function(s, name) return s.__scripts[name] end
    elseif key == "RegisterEvent" then
        fn = function(s, event)
            eventRegistry[event] = eventRegistry[event] or {}
            table.insert(eventRegistry[event], s)
        end
    elseif key == "UnregisterEvent" then
        fn = function(s, event)
            local list = eventRegistry[event]
            if list then
                for i = #list, 1, -1 do if list[i] == s then table.remove(list, i) end end
            end
        end
    elseif NUMERIC_GETTERS[key] ~= nil then
        local v = NUMERIC_GETTERS[key]
        fn = function() return v end
    elseif IsAutoMethod(key) then
        fn = function() end
    end
    if fn then rawset(self, key, fn) end
    return fn
end

FireScript = function(widget, name, ...)
    local handler = widget.__scripts and widget.__scripts[name]
    if handler then handler(widget, ...) end
end

NewWidget = function(kind, name)
    return setmetatable({ __kind = kind, __name = name, __scripts = {}, __shown = true }, WidgetMT)
end
M.NewWidget, M.FireScript = NewWidget, FireScript

local allFrames = {}
M.allFrames = allFrames
function CreateFrame(frameType, name, parent, template)
    local f = NewWidget(frameType, name)
    f.__template = template
    f.__parent = parent
    if template and template:find("CheckButton") then f.Text = NewWidget("FontString") end
    do
        local fs = NewWidget("FontString")
        f.GetFontString = function() return fs end
    end
    if template == "BasicFrameTemplateWithInset" then
        f.TitleText = NewWidget("FontString")
        f.CloseButton = NewWidget("Button")
        f.Bg, f.TitleBg, f.Inset, f.NineSlice =
            NewWidget("Texture"), NewWidget("Texture"), NewWidget("Frame"), NewWidget("Frame")
    end
    if name then _G[name] = f end
    allFrames[#allFrames + 1] = f
    return f
end

UIParent = NewWidget("Frame", "UIParent")
GameTooltip = NewWidget("GameTooltip", "GameTooltip")
-- __lines is every line's text; __colors[i] the r, g, b line i was given
-- (the tooltip is the game's dark one whatever the window's sheet, so a
-- line's colour is checkable against it)
GameTooltip.__lines, GameTooltip.__colors = {}, {}
GameTooltip.SetOwner = function(self) self.__lines, self.__colors = {}, {} end
GameTooltip.SetText = function(self, text, r, g, b)
    self.__lines[#self.__lines + 1] = tostring(text)
    self.__colors[#self.__lines] = r and { r, g, b } or nil
end
GameTooltip.AddLine = function(self, text, r, g, b)
    self.__lines[#self.__lines + 1] = tostring(text)
    self.__colors[#self.__lines] = r and { r, g, b } or nil
end
GameTooltip.AddDoubleLine = function(self, left, right)
    self.__lines[#self.__lines + 1] = tostring(left) .. "  " .. tostring(right)
end
UISpecialFrames = {}
tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack

for _, name in ipairs({ "GameFontNormal", "GameFontNormalLarge", "GameFontNormalHuge",
    "GameFontNormalSmall", "GameFontHighlight", "GameFontHighlightSmall",
    "GameFontDisableSmall", "NumberFontNormal" }) do
    _G[name] = NewWidget("Font", name)
end
-- The fonts' own colours: what a font swap puts back over a label's ink
GameFontNormalSmall.__fontColor = { 1, 0.82, 0 }
GameFontDisableSmall.__fontColor = { 0.5, 0.5, 0.5 }
GameFontHighlightSmall.__fontColor = { 1, 1, 1 }
-- A hover as the client acts it out on a Button with a highlight font: the
-- label takes the highlight font (and its colour), OnEnter runs; on leaving
-- it takes the normal font back (and THAT font's colour), OnLeave runs.
function M.HoverButton(button)
    local fs = button:GetFontString()
    local function Swap(font)
        local c = font and font.__fontColor
        if c then fs.__color = { c[1], c[2], c[3] } end
    end
    Swap(button.__highlightFont)
    FireScript(button, "OnEnter")
    Swap(button.__normalFont)
    FireScript(button, "OnLeave")
end
-- The same hover in two halves, so a check can look at the label WHILE the
-- pointer is on it
function M.HoverIn(button)
    local fs = button:GetFontString()
    local c = button.__highlightFont and button.__highlightFont.__fontColor
    if c then fs.__color = { c[1], c[2], c[3] } end
    FireScript(button, "OnEnter")
end
function M.HoverOut(button)
    local fs = button:GetFontString()
    local c = button.__normalFont and button.__normalFont.__fontColor
    if c then fs.__color = { c[1], c[2], c[3] } end
    FireScript(button, "OnLeave")
end
BACKDROP_SLIDER_8_8 = {}
YES, NO = "Yes", "No"

RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
function UnitClass() return "Warrior", "WARRIOR" end
function UnitLevel() return 62 end
function GetCursorPosition() return 0, 0 end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function IsInRaid() return ST.inRaid end
function IsInGroup() return ST.inParty or ST.inRaid end
function IsInGuild() return ST.inGuild end
function SendChatMessage(text, channel)
    local sent = ST.chatSent
    sent[#sent + 1] = { text = text, channel = channel }
end
function GetCoinTextureString(copper) return string.format("%dc", copper) end
function ChatEdit_InsertLink() end
function PlaySound() end
SOUNDKIT = {}

local categories = {}
M.categories = categories
Settings = {
    RegisterCanvasLayoutCategory = function(panel)
        local cat = { __panel = panel, GetID = function() return #categories + 1 end }
        categories[#categories + 1] = cat; return cat
    end,
    RegisterCanvasLayoutSubcategory = function(parent, panel)
        local cat = { __panel = panel, GetID = function() return #categories + 1 end }
        categories[#categories + 1] = cat; return cat
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
}
C_AddOns = { GetAddOnMetadata = function() return "1.0.0" end }

local timers = {}
M.timers = timers
C_Timer = {
    After = function(delay, fn) timers[#timers + 1] = { at = ST.now + delay, fn = fn } end,
    NewTicker = function(interval, fn)
        local t = { interval = interval, fn = fn }
        t.Cancel = function(self) self.cancelled = true end
        return t
    end,
}
-- The clock moves on by `seconds` (default 1) and every timer now due runs
function M.RunTimers(seconds)
    ST.now = ST.now + (seconds or 1)
    for _, t in ipairs(timers) do
        if not t.done and t.at <= ST.now then t.done = true; t.fn() end
    end
end

function UIDropDownMenu_Initialize(dropdown, fn) dropdown.__init = fn end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton() end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetSelectedValue() end
function UIDropDownMenu_SetText() end
function UIDropDownMenu_EnableDropDown() end
function UIDropDownMenu_DisableDropDown() end
function ToggleDropDownMenu() end
SlashCmdList = {}

StaticPopupDialogs = {}
function StaticPopup_Show(which, arg1)
    local dialog = { which = which, arg1 = arg1 }
    local shown = ST.popupsShown
    shown[#shown + 1] = dialog
    return dialog
end
-- Presses Yes on the popup the way the player would
function M.AcceptPopup()
    local shown = ST.popupsShown
    local dialog = shown[#shown]
    if not dialog then return false end
    local spec = StaticPopupDialogs[dialog.which]
    if spec and spec.OnAccept then spec.OnAccept(dialog, dialog.data) end
    return true
end

-- ---------------------------------------------------------------------------
-- The quest log
--
-- A list of entries in log order, mutated by hand. Collapsing a header REMOVES
-- its quests from the index space exactly as the client does, which is the
-- behaviour the module's expand-first scan exists to survive.
-- ---------------------------------------------------------------------------

local function VisibleLog()
    local out, hidden = {}, false
    for _, entry in ipairs(ST.log) do
        if entry.isHeader then
            out[#out + 1] = entry
            hidden = entry.collapsed and true or false
        elseif not hidden then
            out[#out + 1] = entry
        end
    end
    return out
end
M.VisibleLog = VisibleLog

function GetNumQuestLogEntries()
    local visible = VisibleLog()
    local quests = 0
    for _, entry in ipairs(visible) do
        if not entry.isHeader then quests = quests + 1 end
    end
    return #visible, quests
end

function GetQuestLogTitle(index)
    local entry = VisibleLog()[index]
    if not entry then return nil end
    if entry.isHeader then
        return entry.title, 0, nil, true, entry.collapsed and true or false, nil, nil, 0
    end
    return entry.title, entry.level, entry.group, false, false,
        entry.isComplete, entry.frequency or 1, entry.questID
end

-- The client's questID -> index, in the same (collapse-aware) index space:
-- 0 for a quest under a folded heading or not in the log at all
function GetQuestLogIndexByID(questID)
    for index, entry in ipairs(VisibleLog()) do
        if not entry.isHeader and entry.questID == questID then return index end
    end
    return 0
end

function ExpandQuestHeader(which)
    ST.expandCalls = ST.expandCalls + 1
    for _, entry in ipairs(ST.log) do
        if entry.isHeader then entry.collapsed = false end
    end
    -- The real client fires this off the back of the expand, which is exactly
    -- the loop the module's guard exists for
    M.Fire("QUEST_LOG_UPDATE")
end

function SelectQuestLogEntry(index) ST.selection = index end
function GetQuestLogSelection() return ST.selection end

local function SelectedQuest()
    local entry = VisibleLog()[ST.selection]
    if entry and not entry.isHeader then return entry end
    return nil
end
M.SelectedQuest = SelectedQuest

function GetNumQuestLeaderBoards(index)
    local entry = VisibleLog()[index]
    if not entry or entry.isHeader then return 0 end
    return #(entry.objectives or {})
end

function GetQuestLogLeaderBoard(objective, index)
    local entry = VisibleLog()[index]
    if not entry or entry.isHeader then return nil end
    local row = (entry.objectives or {})[objective]
    if not row then return nil end
    return row.text, row.kind or "monster", row.finished and true or false
end

function GetQuestLogQuestText()
    local entry = SelectedQuest()
    if not entry then return "", "" end
    return entry.description or "", entry.objectivesText or ""
end

function GetQuestLogTimeLeft()
    local entry = SelectedQuest()
    return entry and entry.timeLeft or nil
end

function GetQuestLogPushable()
    local entry = SelectedQuest()
    return entry and entry.pushable ~= false
end

function GetQuestLogRewardMoney()
    local entry = SelectedQuest()
    return entry and entry.money or 0
end

function GetNumQuestLogChoices()
    local entry = SelectedQuest()
    return entry and #(entry.choices or {}) or 0
end

function GetQuestLogChoiceInfo(slot)
    local entry = SelectedQuest()
    local item = entry and (entry.choices or {})[slot]
    if not item then return nil end
    return item.name, item.texture, item.count or 1, item.quality or 1, item.usable ~= false
end

function GetNumQuestLogRewards()
    local entry = SelectedQuest()
    return entry and #(entry.rewards or {}) or 0
end

function GetQuestLogRewardInfo(slot)
    local entry = SelectedQuest()
    local item = entry and (entry.rewards or {})[slot]
    if not item then return nil end
    return item.name, item.texture, item.count or 1, item.quality or 1, item.usable ~= false
end

function GetQuestLogItemLink(kind, slot)
    local entry = SelectedQuest()
    if not entry then return nil end
    local list = (kind == "choice") and entry.choices or entry.rewards
    local item = list and list[slot]
    return item and ("|cffffffff|Hitem:" .. (item.id or 1) .. "|h[" .. item.name .. "]|h|r") or nil
end

function GetQuestLogRewardSpell()
    local entry = SelectedQuest()
    if not entry or not entry.spell then return nil end
    return "Interface\\Icons\\Spell", entry.spell
end

local function WatchKey(index)
    local entry = VisibleLog()[index]
    return entry and entry.title or nil
end

function IsQuestWatched(index)
    local key = WatchKey(index)
    return key and ST.watched[key] and true or false
end

function AddQuestWatch(index)
    local key = WatchKey(index)
    if not key then return end
    if GetNumQuestLeaderBoards(index) == 0 then return end
    local count = 0
    for _ in pairs(ST.watched) do count = count + 1 end
    if count >= ST.watchLimit then return end   -- the era declines silently
    ST.watched[key] = true
end

function RemoveQuestWatch(index)
    local key = WatchKey(index)
    if key then ST.watched[key] = nil end
end

function QuestWatch_Update() end

function QuestLogPushQuery(index)
    local pushed = ST.pushed
    pushed[#pushed + 1] = WatchKey(index)
end

function SetAbandonQuest()
    ST.abandonArmed = SelectedQuest() and SelectedQuest().title or nil
end

function AbandonQuest()
    local armed = ST.abandonArmed
    if not armed then return end
    local log = ST.log
    for position, entry in ipairs(log) do
        if entry.title == armed and not entry.isHeader then
            table.remove(log, position)
            local abandoned = ST.abandoned
            abandoned[#abandoned + 1] = entry.title
            break
        end
    end
    ST.abandonArmed = nil
end

QuestLogFrame = CreateFrame("Frame", "QuestLogFrame", UIParent)
QuestLogFrame:Hide()
function HideUIPanel(panel)
    local hidden = ST.hiddenPanels
    hidden[#hidden + 1] = panel.__name or "?"
    panel.__shown = false
end
function ShowUIPanel(panel) panel:Show() end
function ToggleQuestLog()
    if QuestLogFrame:IsShown() then HideUIPanel(QuestLogFrame) else ShowUIPanel(QuestLogFrame) end
end

-- Log fixtures: a zone heading, and a quest (its spec is the entry itself)
function M.Header(title) return { isHeader = true, title = title } end
function M.Quest(spec) return spec end

-- ===========================================================================
-- Events, loading, checks
-- ===========================================================================

-- Fires a client event at every frame registered for it, in registration
-- order, as the client does
function M.Fire(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    local snap = {}
    for i, f in ipairs(list) do snap[i] = f end
    for _, f in ipairs(snap) do
        local handler = f.__scripts.OnEvent
        if handler then handler(f, event, ...) end
    end
end
_G.__Fire = M.Fire

function M.Load(path) assert(loadfile(path))() end

-- The shared framework every Commander module stands on
function M.LoadFramework()
    M.Load(M.ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
    M.Load(M.ADDONS .. "/Commander_Events/CommanderEvents.lua")
end

-- Commander_QuestLog's files, by name, in the order given
function M.LoadModule(files)
    for _, file in ipairs(files) do M.Load(M.ADDONS .. "/Commander_QuestLog/" .. file) end
end

-- The TOC's Lua files in the TOC's order -- the ones that exist on disk (the
-- client skips a missing file with a warning; so does this), minus any named
-- in `exclude` (the map drawer, say, which wants a world map this mock does
-- not have)
function M.TocFiles(exclude)
    local skip = {}
    for _, name in ipairs(exclude or {}) do skip[name] = true end
    local out = {}
    local toc = assert(io.open(M.ADDONS .. "/Commander_QuestLog/Commander_QuestLog.toc"))
    for line in toc:lines() do
        local file = line:match("^%s*([%w_]+%.lua)%s*$")
        if file and not skip[file] then
            local handle = io.open(M.ADDONS .. "/Commander_QuestLog/" .. file)
            if handle then
                handle:close()
                out[#out + 1] = file
            end
        end
    end
    toc:close()
    return out
end

-- The client's login: the module's saved variables arrive, then the player
function M.Login()
    M.Fire("ADDON_LOADED", "Commander_QuestLog")
    M.Fire("PLAYER_LOGIN")
end

-- A CHECK of a new harness's own, and its closing line: "n checks, m
-- failures" and an exit code (0 only with no failures)
function M.Checker()
    local counts = { checks = 0, fails = 0 }
    local function CHECK(cond, label, detail)
        counts.checks = counts.checks + 1
        if not cond then
            counts.fails = counts.fails + 1
            io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
        end
    end
    local function Done()
        io.write(string.format("%d checks, %d failures\n", counts.checks, counts.fails))
        os.exit(counts.fails == 0 and 0 or 1)
    end
    return CHECK, Done, counts
end

return M
