-- Commander Quest Log harness (luajit).
--
-- Loads the REAL shared framework (CommanderSettingsUI.lua, CommanderEvents.lua)
-- and every Commander_QuestLog window file -- DB, Model, the completion engine,
-- the Questie adapter, the window and the Zones tab; not the map drawer, which
-- has its own harness -- under a permissive WoW mock, with a fake Questie
-- (fake_questie.lua) installed before any of them loads. Then it drives a
-- whole session against a MUTABLE quest log: scanning it, searching it,
-- folding zones shut, tracking and abandoning, and turning a quest in
-- underneath the window while it is open (A-P); then the Zones tab over the
-- fake Questie's Hellfire Peninsula (Q) and the review's fixes to it (Q2);
-- then a second load of the module with no Questie at all (R).
--
--   luajit questlog_harness.lua
--
-- Mock notes worth keeping:
--   * The quest log is MUTABLE and its INDICES MOVE. That is the whole point:
--     every index bug this module can have is an index that went stale between
--     the row being drawn and the button being pressed, and a fixture whose
--     indices never move proves nothing.
--   * Show/Hide fire OnShow/OnHide, because the window does all its work in
--     OnShow and a mock that skipped it would test an empty frame -- and, as
--     in the client, Show on a frame that is already shown fires NOTHING. A
--     mock that fired OnShow every time hid a window left half-switched by
--     CommanderQuestLog_OpenToQuest.
--   * A button's normal and highlight font objects are recorded, and the
--     fonts carry their own colours, so a hover's font swap (which puts the
--     font's colour back over a label's ink) can be acted out.
--   * The vertical scroll offset of a ScrollFrame is kept, not a constant 0,
--     so "this tab opens at its top" is a real check.
--   * Widths and heights are tracked for real: the navigator advances its
--     layout by each row's height and sizes its progress bars off the pane, so
--     a mock that answered 0 to both would draw every row on top of the first.

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
-- WoW mock
-- ===========================================================================

local now = 1000
function GetTime() return now end
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
local savedInstances = {}
local raidInfoRequests = 0
function RequestRaidInfo() raidInfoRequests = raidInfoRequests + 1 end
function GetNumSavedInstances() return #savedInstances end
function GetSavedInstanceInfo(index)
    local i = savedInstances[index]
    if not i then return nil end
    return i.name, 100 + index, i.reset, i.difficulty or 1, i.locked ~= false, i.extended or false,
        0, i.isRaid ~= false, i.maxPlayers or 10, i.difficultyName or "Normal"
end
function GetBuildInfo() return "2.5.6", "69546", "Aug 28 2026", 20506 end

local printLog = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    printLog[#printLog + 1] = table.concat(parts, " ")
end
local function Logged(pattern)
    for _, line in ipairs(printLog) do
        if line:find(pattern, 1, true) then return line end
    end
    return nil
end
local function WipeLog() for i = #printLog, 1, -1 do printLog[i] = nil end end

local caughtErrors = {}
local errorHandler = function(err) caughtErrors[#caughtErrors + 1] = tostring(err) end
function geterrorhandler() return errorHandler end
function seterrorhandler(fn) errorHandler = fn end

local eventRegistry = {}
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

local allFrames = {}
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
GameTooltip.__lines = {}
GameTooltip.SetOwner = function(self) self.__lines = {} end
GameTooltip.SetText = function(self, text) self.__lines[#self.__lines + 1] = tostring(text) end
GameTooltip.AddLine = function(self, text) self.__lines[#self.__lines + 1] = tostring(text) end
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
local function HoverButton(button)
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
local function HoverIn(button)
    local fs = button:GetFontString()
    local c = button.__highlightFont and button.__highlightFont.__fontColor
    if c then fs.__color = { c[1], c[2], c[3] } end
    FireScript(button, "OnEnter")
end
local function HoverOut(button)
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
local inRaid, inParty, inGuild = false, false, true
function IsInRaid() return inRaid end
function IsInGroup() return inParty or inRaid end
function IsInGuild() return inGuild end
local chatSent = {}
function SendChatMessage(text, channel) chatSent[#chatSent + 1] = { text = text, channel = channel } end
function GetCoinTextureString(copper) return string.format("%dc", copper) end
function ChatEdit_InsertLink() end
function PlaySound() end
SOUNDKIT = {}

local categories = {}
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
C_Timer = {
    After = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end,
    NewTicker = function(interval, fn)
        local t = { interval = interval, fn = fn }
        t.Cancel = function(self) self.cancelled = true end
        return t
    end,
}
local function RunTimers(seconds)
    now = now + (seconds or 1)
    for _, t in ipairs(timers) do
        if not t.done and t.at <= now then t.done = true; t.fn() end
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
local popupsShown = {}
function StaticPopup_Show(which, arg1)
    local dialog = { which = which, arg1 = arg1 }
    popupsShown[#popupsShown + 1] = dialog
    return dialog
end
-- Presses Yes on the popup the way the player would
local function AcceptPopup()
    local dialog = popupsShown[#popupsShown]
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

local log = {}
local selection = 0
local watched = {}
local watchLimit = 5
local abandoned = {}
local pushed = {}
local abandonArmed = nil

local function VisibleLog()
    local out, hidden = {}, false
    for _, entry in ipairs(log) do
        if entry.isHeader then
            out[#out + 1] = entry
            hidden = entry.collapsed and true or false
        elseif not hidden then
            out[#out + 1] = entry
        end
    end
    return out
end

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

local expandCalls = 0
function ExpandQuestHeader(which)
    expandCalls = expandCalls + 1
    for _, entry in ipairs(log) do
        if entry.isHeader then entry.collapsed = false end
    end
    -- The real client fires this off the back of the expand, which is exactly
    -- the loop the module's guard exists for
    _G.__Fire("QUEST_LOG_UPDATE")
end

function SelectQuestLogEntry(index) selection = index end
function GetQuestLogSelection() return selection end

local function SelectedQuest()
    local entry = VisibleLog()[selection]
    if entry and not entry.isHeader then return entry end
    return nil
end

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
    return key and watched[key] and true or false
end

function AddQuestWatch(index)
    local key = WatchKey(index)
    if not key then return end
    if GetNumQuestLeaderBoards(index) == 0 then return end
    local count = 0
    for _ in pairs(watched) do count = count + 1 end
    if count >= watchLimit then return end   -- the era declines silently
    watched[key] = true
end

function RemoveQuestWatch(index)
    local key = WatchKey(index)
    if key then watched[key] = nil end
end

function QuestWatch_Update() end

function QuestLogPushQuery(index)
    pushed[#pushed + 1] = WatchKey(index)
end

function SetAbandonQuest()
    abandonArmed = SelectedQuest() and SelectedQuest().title or nil
end

function AbandonQuest()
    if not abandonArmed then return end
    for position, entry in ipairs(log) do
        if entry.title == abandonArmed and not entry.isHeader then
            table.remove(log, position)
            abandoned[#abandoned + 1] = entry.title
            break
        end
    end
    abandonArmed = nil
end

QuestLogFrame = CreateFrame("Frame", "QuestLogFrame", UIParent)
QuestLogFrame:Hide()
local hiddenPanels = {}
function HideUIPanel(panel)
    hiddenPanels[#hiddenPanels + 1] = panel.__name or "?"
    panel.__shown = false
end
function ShowUIPanel(panel) panel:Show() end
function ToggleQuestLog()
    if QuestLogFrame:IsShown() then HideUIPanel(QuestLogFrame) else ShowUIPanel(QuestLogFrame) end
end

-- ===========================================================================
-- Load the framework and the module
-- ===========================================================================

local function Load(path) assert(loadfile(path))() end

local function Fire(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    local snap = {}
    for i, f in ipairs(list) do snap[i] = f end
    for _, f in ipairs(snap) do
        local handler = f.__scripts.OnEvent
        if handler then handler(f, event, ...) end
    end
end
_G.__Fire = Fire

-- Questie, faked (Harness/fake_questie.lua) and installed BEFORE the module
-- loads, so the adapter attaches at login exactly as it does in game. Its
-- world is a small Hellfire Peninsula for a level-62 paladin; sections A-P
-- never look at it (the Log works the same with Questie as without), section
-- Q drives the Zones tab over it, and section R loads the module again with
-- no Questie at all.
local Fake = dofile(ADDONS .. "/Commander_QuestLog/Harness/fake_questie.lua")
local world = Fake.DefaultWorld()
local fake = Fake.Install(world)
Fake.InstallClient(world)

-- The TOC's files in the TOC's order, minus the map drawer (it has its own
-- harness, questlog_map_harness.lua, and this mock has no world map)
local MODULE_FILES = {
    "CommanderQuestLogDB.lua", "CommanderQuestLogModel.lua", "CommanderQuestLogCompletion.lua",
    "CommanderQuestLogQuestie.lua", "CommanderQuestLogUI.lua", "CommanderQuestLogZones.lua",
}

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
for _, file in ipairs(MODULE_FILES) do Load(ADDONS .. "/Commander_QuestLog/" .. file) end
-- A log saved under the old default: on PARCHMENT because that is what it
-- was given, with no StyleGeneration. Login has to move it to stone once --
-- and section L then checks a parchment picked AFTER that is left alone.
CommanderQuestLogDB.FrameStyle = "PARCHMENT"
CommanderQuestLogDB.StyleGeneration = nil
Fire("ADDON_LOADED", "Commander_QuestLog")
Fire("PLAYER_LOGIN")

local Q = CommanderQuestLog
local db = CommanderQuestLogDB

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

local function Header(title) return { isHeader = true, title = title } end

local function Quest(spec) return spec end

local function BuildLog()
    log = {
        Header("Hellfire Peninsula"),
        Quest({
            title = "Cleansing the Waters", level = 61, questID = 9001,
            description = "The wells of Honor Hold have been fouled.",
            objectivesText = "Purify 3 wells.",
            objectives = {
                { text = "Well purified: 3/3", finished = true },
                { text = "Report to Vindicator Sedai: 0/1", finished = false },
            },
            money = 4500,
            rewards = { { name = "Honor Hold Tabard", texture = "t1", quality = 2, id = 111 } },
        }),
        Quest({
            title = "The Path of Anguish", level = 62, questID = 9002,
            isComplete = 1,
            description = "Return to me when the deed is done.",
            objectives = { { text = "Fel Orc slain: 12/12", finished = true } },
            choices = {
                { name = "Anguish Blade", texture = "t2", quality = 3, id = 222 },
                { name = "Anguish Shield", texture = "t3", quality = 3, id = 223, usable = false },
            },
            spell = "Summon Felsteed",
        }),
        Quest({
            title = "Ravager Egg Collection", level = 60, questID = 9003,
            objectives = { { text = "Ravager Egg: 4/8", finished = false } },
            pushable = false,
        }),
        Header("Zangarmarsh"),
        Quest({
            title = "The Umbrafen Tribe", level = 63, questID = 9004,
            objectives = { { text = "Umbrafen Slaver slain: 0/10", finished = false } },
        }),
        Quest({
            title = "A Damp Errand", level = 64, questID = 9005,
            isComplete = -1,
            objectives = { { text = "Sporeling Sample: 0/1", finished = false } },
        }),
        Header("Daily"),
        Quest({
            title = "Bombing Run", level = 70, questID = 9006, frequency = 2,
            objectives = { { text = "Bombs dropped: 0/5", finished = false } },
        }),
    }
    selection = 0
    watched = {}
    abandoned = {}
    pushed = {}
    abandonArmed = nil
end

BuildLog()

-- ---------------------------------------------------------------------------
-- A: the scan
-- ---------------------------------------------------------------------------
local entries, quests = Q.Scan()
CHECK(#entries == 9, "A: every header and quest is read", #entries)
CHECK(quests == 6, "A: six quests, headers not counted", quests)
CHECK(entries[1].isHeader and entries[1].title == "Hellfire Peninsula", "A: the first row is a zone heading")
CHECK(entries[2].title == "Cleansing the Waters" and entries[2].level == 61, "A: title and level")
CHECK(entries[2].header == "Hellfire Peninsula", "A: a quest carries its zone", entries[2].header)
CHECK(entries[3].isComplete == true and entries[3].isFailed == false, "A: 1 reads as complete")
CHECK(entries[7].isFailed == true and entries[7].isComplete == false,
    "A: -1 reads as FAILED, not as complete -- a plain truth test gets this wrong")
CHECK(entries[9].daily == true, "A: frequency 2 is a daily")
CHECK(entries[2].objectives[1].have == 3 and entries[2].objectives[1].need == 3,
    "A: an objective's have/need is parsed out of its text")
CHECK(entries[2].numObjectives == 2 and entries[2].numFinished == 1, "A: partial objective tally")
CHECK(entries[3].numFinished == entries[3].numObjectives,
    "A: a quest the server calls complete counts every objective done")
CHECK(entries[1].quests == 3 and entries[1].complete == 1, "A: the heading tallies its own zone")

-- The scan must not leave the client's selection wherever it finished
selection = 4
Q.Scan()
CHECK(selection == 4, "A: the scan puts the log selection back", selection)

-- ---------------------------------------------------------------------------
-- B: collapsed headers, and the loop the expand provokes
-- ---------------------------------------------------------------------------
log[5].collapsed = true
CHECK(select(1, GetNumQuestLogEntries()) == 7,
    "B: the client hides a collapsed zone's quests from the index space")
expandCalls = 0
entries = Q.Scan()
CHECK(expandCalls == 1, "B: the scan expands once", expandCalls)
CHECK(#entries == 9, "B: and then sees every quest again", #entries)
expandCalls = 0
Q.Scan()
CHECK(expandCalls == 0, "B: nothing collapsed, nothing expanded -- the call is not made unconditionally")
CHECK(Q.IsExpanding() == false, "B: the re-entry guard is clear once the expand is done")

-- ---------------------------------------------------------------------------
-- C: the display list
-- ---------------------------------------------------------------------------
entries = Q.Scan()

local list, shown = Q.BuildList(entries, {})
CHECK(#list == 9 and shown == 6, "C: an unfiltered list is the log", #list)

list, shown = Q.BuildList(entries, { search = "ravager" })
CHECK(shown == 1 and #list == 2, "C: a search over the name keeps its heading and nothing else", #list)
CHECK(list[1].header and list[1].header.title == "Hellfire Peninsula", "C: and the heading is the right one")

list, shown = Q.BuildList(entries, { search = "zangarmarsh" })
CHECK(shown == 2, "C: a search matches the zone name too", shown)

list, shown = Q.BuildList(entries, { search = "sporeling" })
CHECK(shown == 1, "C: and the text of an objective", shown)

list, shown = Q.BuildList(entries, { search = "SPORELING" })
CHECK(shown == 1, "C: case does not matter", shown)

list, shown = Q.BuildList(entries, { filter = "COMPLETE" })
CHECK(shown == 1, "C: Ready is quests the server calls complete", shown)
CHECK(list[1].header ~= nil and #list == 2, "C: a filtered list never shows a heading with nothing under it")

list, shown = Q.BuildList(entries, { filter = "ACTIVE" })
CHECK(shown == 5, "C: Active is everything else -- a FAILED quest is still active", shown)

watched["The Umbrafen Tribe"] = true
entries = Q.Scan()
list, shown = Q.BuildList(entries, { filter = "TRACKED" })
CHECK(shown == 1 and list[2].entry.title == "The Umbrafen Tribe", "C: Tracked reads the client's watch list")
watched = {}
entries = Q.Scan()

list = Q.BuildList(entries, { collapsed = { ["Hellfire Peninsula"] = true } })
CHECK(#list == 6, "C: folding a zone shut hides its quests and keeps its heading", #list)
CHECK(list[1].header.title == "Hellfire Peninsula" and list[1].collapsed == true,
    "C: and the heading knows it is shut")
CHECK(list[2].header ~= nil, "C: the next row is the next heading, not a stray quest")

list = Q.BuildList(entries, { sort = "LEVEL" })
CHECK(list[1].entry.level == 70 and list[#list].entry.level == 60, "C: a level sort is highest first")
CHECK(list[1].header == nil, "C: a sort drops the zone grouping rather than sorting inside it")
list = Q.BuildList(entries, { sort = "NAME" })
CHECK(list[1].entry.title == "A Damp Errand", "C: a name sort is alphabetical", list[1].entry.title)
list = Q.BuildList(entries, { sort = "PROGRESS" })
CHECK(list[1].entry.isComplete, "C: a progress sort puts the finished ones first")

-- A search and a fold at the same time: the search wins, because a heading
-- folded shut but matching a search that found nothing under it is a lie
list, shown = Q.BuildList(entries, {
    search = "ravager", collapsed = { ["Hellfire Peninsula"] = true },
})
CHECK(shown == 1 and #list == 1, "C: a folded heading still hides its quests under a search", #list)

-- ---------------------------------------------------------------------------
-- D: progress
-- ---------------------------------------------------------------------------
CHECK(Q.Progress(entries[3]) == 1, "D: a complete quest is fully progressed")
CHECK(math.abs(Q.Progress(entries[4]) - 0.5) < 0.001, "D: 4 of 8 is half", Q.Progress(entries[4]))
local partial = Q.Progress(entries[2])
CHECK(partial > 0.7 and partial < 0.8, "D: 3/3 and 0/1 weighs by count, not by objective", partial)

-- ---------------------------------------------------------------------------
-- E: the detail read
-- ---------------------------------------------------------------------------
selection = 7
local detail = Q.ReadDetail(3)
CHECK(selection == 7, "E: reading a detail puts the selection back", selection)
CHECK(detail.description == "Return to me when the deed is done.", "E: the description")
CHECK(#detail.choices == 2 and detail.choices[1].name == "Anguish Blade", "E: the reward choices")
CHECK(detail.choices[2].usable == false, "E: and whether you can use them")
CHECK(detail.choices[1].link ~= nil and detail.choices[1].link:find("Anguish Blade", 1, true),
    "E: each reward carries its item link")
CHECK(detail.spell and detail.spell.name == "Summon Felsteed", "E: a taught spell")
local moneyDetail = Q.ReadDetail(2)
CHECK(moneyDetail.money == 4500, "E: reward money", moneyDetail.money)
CHECK(#moneyDetail.rewards == 1, "E: rewards given outright")
CHECK(Q.ReadDetail(4).pushable == false, "E: a quest that cannot be shared says so")

-- ---------------------------------------------------------------------------
-- F: the window
-- ---------------------------------------------------------------------------
CommanderQuestLog_Toggle()
local window = _G.CommanderQuestLogFrame
CHECK(window ~= nil and window:IsShown(), "F: the window opens")
CHECK(window.searchBox.__focused ~= true, "F: and never takes keyboard focus, or WASD types into the search box")

CHECK(window.countFS:GetText():find("6", 1, true) ~= nil, "F: the readout counts the quests",
    window.countFS:GetText())
CHECK(window.trackBtn:IsEnabled(), "F: with a quest selected the actions are live")

-- Blizzard's disabled font is a mid-grey the suite has been bitten by before.
-- The filter labels take an explicit colour, and it has to be applied AFTER
-- the font object is swapped or the swap washes it straight out again.
db.Filter = "ALL"
Q.Refresh()
local allLabel = window.filters.ALL:GetFontString()
local readyLabel = window.filters.COMPLETE:GetFontString()
-- Asserted as a RELATIONSHIP, not as literal channel values. The window has
-- two skins and they are opposites: on the dark panel "lit" is brighter than
-- "dimmed", on parchment it is DARKER, because the paper is pale. A literal
-- `== 1` encodes the dark skin only, and it passed for as long as the
-- parchment never actually rendered.
local function Lum(c) return c and (c[1] * 0.299 + c[2] * 0.587 + c[3] * 0.114) end
CHECK(allLabel and allLabel.__color and readyLabel and readyLabel.__color,
    "F: both filter labels are coloured by the window, not left to the font")
CHECK(Lum(allLabel.__color) ~= Lum(readyLabel.__color),
    "F: the selected filter's label is set apart from an unselected one",
    tostring(Lum(allLabel.__color)) .. " vs " .. tostring(Lum(readyLabel.__color)))

-- The navigator laid its rows out at DISTINCT offsets. A row whose height
-- reads as zero stacks every quest on the first one, which looks like the
-- window drawing one quest rather than like a layout bug.
local seen, stacked = {}, false
for _, row in ipairs(Q._NavRows()) do
    if row:IsShown() then
        local point = row.__points and row.__points[#row.__points - 1]
        local y = point and point.y
        if y then
            if seen[y] then stacked = true end
            seen[y] = true
        end
    end
end
CHECK(not stacked, "F: every visible row sits at its own offset")

-- The briefing filled in: the quest's name, its objectives and its rewards
local briefing = {}
for _, fs in ipairs(Q._DetailStrings()) do
    if fs:IsShown() and fs:GetText() then briefing[#briefing + 1] = fs:GetText() end
end
local function Briefed(text)
    for _, line in ipairs(briefing) do
        if line:find(text, 1, true) then return true end
    end
    return false
end
CHECK(Briefed("Cleansing the Waters"), "F: the briefing carries the quest's name")
CHECK(Briefed("Well purified"), "F: and its objectives")
CHECK(Briefed("OBJECTIVES") and Briefed("DESCRIPTION"), "F: under their headings")
CHECK(Briefed("Hellfire Peninsula") and Briefed("Level 61"), "F: and the facts line")

Q.Select("The Path of Anguish")
briefing = {}
for _, fs in ipairs(Q._DetailStrings()) do
    if fs:IsShown() and fs:GetText() then briefing[#briefing + 1] = fs:GetText() end
end
CHECK(Briefed("Anguish Blade") and Briefed("Choose one of:"), "F: reward choices are drawn")
CHECK(Briefed("Summon Felsteed"), "F: and a taught spell")
CHECK(Briefed("Ready to turn in."), "F: a complete quest says so")

-- Blocks are pooled by POSITION, and two quests of different shape put
-- different kinds of line at the same position. "The Path of Anguish" is
-- complete, so its fifth block is the "Ready to turn in." heading line;
-- "Cleansing the Waters" is not, so its fifth block is an objective. A pooled
-- block handed over without re-applying the font renders that objective in
-- the heading's font for the rest of the session.
local function BlockFonts()
    local out = {}
    for _, fs in ipairs(Q._DetailStrings()) do
        if fs:IsShown() and fs:GetText() then out[fs:GetText()] = fs._template end
    end
    return out
end

Q.Select("The Path of Anguish")
local completeFonts = BlockFonts()
CHECK(completeFonts["Ready to turn in."] == "GameFontNormalSmall",
    "F: a complete quest's turn-in line is a heading font",
    tostring(completeFonts["Ready to turn in."]))

Q.Select("Cleansing the Waters")
local activeFonts = BlockFonts()
CHECK(activeFonts["The Path of Anguish"] == nil, "F: the previous quest's title is gone from the pane")
CHECK(activeFonts["\194\183 Well purified: 3/3"] == "GameFontHighlightSmall",
    "F: and a block the turn-in line had taken comes back at the body font",
    tostring(activeFonts["\194\183 Well purified: 3/3"]))
CHECK(activeFonts["Cleansing the Waters"] == "GameFontNormalLarge", "F: with the title still large")
CHECK(activeFonts["OBJECTIVES"] == "GameFontNormalSmall", "F: and the headings still headings")

-- Colour is pooled the same way and re-applied for the same reason. Block
-- nine is the accent-tinted REWARDS heading on a quest with given rewards and
-- the plain "Choose one of:" caption on a quest with a choice; a caption that
-- kept the heading's tint is a line shouting when it should be muttering.
local function BlockColors()
    local out = {}
    for _, fs in ipairs(Q._DetailStrings()) do
        if fs:IsShown() and fs:GetText() then out[fs:GetText()] = fs.__color end
    end
    return out
end
-- Same reasoning: what matters is that the caption does not INHERIT the
-- heading's tint from the pooled block, not what either colour literally is.
-- On parchment the accent is darkened for text (a STEEL accent is white, which
-- on paper is the paper), so a literal here would only ever describe one skin.
Q.Select("Cleansing the Waters")
local rewardsTint = BlockColors()["REWARDS"]
CHECK(rewardsTint ~= nil, "F: the REWARDS heading is tinted at all", tostring(rewardsTint))
local descTint = BlockColors()["A quest description."] or BlockColors()["OBJECTIVES"]
Q.Select("The Path of Anguish")
local caption = BlockColors()["Choose one of:"]
CHECK(caption ~= nil, "F: the caption is coloured by the window")
CHECK(caption and rewardsTint and
    (caption[1] ~= rewardsTint[1] or caption[2] ~= rewardsTint[2] or caption[3] ~= rewardsTint[3]),
    "F: and a caption reusing that block is muted rather than keeping the accent",
    caption and table.concat(caption, ",") .. " vs " .. table.concat(rewardsTint, ","))
local _ = descTint
Q.Select("Cleansing the Waters")

-- Share greys itself out for a quest the game will not let you share, rather
-- than offering a button that does nothing
Q.Select("Ravager Egg Collection")
CHECK(not window.shareBtn:IsEnabled(), "F: Share is dead for an unshareable quest")
Q.Select("The Umbrafen Tribe")
CHECK(window.shareBtn:IsEnabled(), "F: and live for one that can be shared")
Q.Select("Cleansing the Waters")

-- Something is always selected on open, so the briefing is never blank
CHECK(Q.Selected() ~= nil, "F: the window selects the first quest on its own")

db.Filter = "COMPLETE"
Q.Refresh()
CHECK(Q.Selected() ~= nil and Q.Selected().isComplete,
    "F: narrowing the filter past the selection re-selects something that is actually on screen")
db.Filter = "ALL"
Q.Refresh()

-- ---------------------------------------------------------------------------
-- G: acting on the selection, with the log moving underneath
-- ---------------------------------------------------------------------------
Q.Select("Ravager Egg Collection")
CHECK(Q.Selected().title == "Ravager Egg Collection", "G: a quest can be selected by name")

WipeLog()
Q.ToggleTrack()
CHECK(watched["Ravager Egg Collection"] == true, "G: Track puts it on the tracker")
Q.ToggleTrack()
CHECK(watched["Ravager Egg Collection"] == nil, "G: and takes it off again")

-- The tracker is full: the era declines silently, which reads as a broken
-- button unless the module says something
watched = { a = true, b = true, c = true, d = true, e = true }
WipeLog()
Q.ToggleTrack()
CHECK(Logged("tracker is full") ~= nil, "G: a full tracker is reported, not swallowed", printLog[1])
watched = {}

Q.Select("Ravager Egg Collection")
WipeLog()
Q.Share()
CHECK(#pushed == 0, "G: a quest the game will not share is not pushed")
CHECK(Logged("cannot be shared") ~= nil, "G: and the refusal is explained", printLog[1])

Q.Select("The Umbrafen Tribe")
Q.Share()
CHECK(pushed[#pushed] == "The Umbrafen Tribe", "G: a shareable quest is pushed", pushed[#pushed])

inParty = true
db.AnnounceChannel = "AUTO"
chatSent = {}
Q.Announce()
CHECK(#chatSent >= 2 and chatSent[1].channel == "PARTY", "G: Announce goes to the party")
CHECK(chatSent[1].text:find("Umbrafen", 1, true) ~= nil, "G: with the quest's name", chatSent[1].text)
CHECK(chatSent[2].text:find("Slaver", 1, true) ~= nil, "G: and its remaining objectives", chatSent[2].text)
inRaid = true
chatSent = {}
Q.Announce()
CHECK(chatSent[1].channel == "RAID", "G: a raid outranks a party")
inRaid, inParty = false, false
chatSent = {}
WipeLog()
Q.Announce()
CHECK(#chatSent == 0 and Logged("Umbrafen") ~= nil, "G: alone, it talks to you rather than erroring")

-- ---------------------------------------------------------------------------
-- H: abandoning, and the index that moved
--
-- The section exists for one bug. The confirmation dialog sits on screen
-- while the world keeps moving; the stock flow re-reads the SELECTION at
-- accept time and drops whatever has since slid into that slot.
-- ---------------------------------------------------------------------------
Q.Select("Ravager Egg Collection")
db.ConfirmAbandon = true
Q.Abandon()
CHECK(#popupsShown > 0 and popupsShown[#popupsShown].which == "COMMANDER_QUESTLOG_ABANDON",
    "H: abandoning asks first")
CHECK(popupsShown[#popupsShown].data == "Ravager Egg Collection",
    "H: and the dialog carries the quest by NAME, not by index",
    tostring(popupsShown[#popupsShown].data))

-- The player turns in a different quest while the dialog is up. Every index
-- below it moves by one.
table.remove(log, 2)
WipeLog()
AcceptPopup()
CHECK(abandoned[#abandoned] == "Ravager Egg Collection",
    "H: the right quest is abandoned even though its index moved",
    tostring(abandoned[#abandoned]))

-- And the quest simply being gone is refused rather than misapplied
popupsShown = {}
Q.Select("The Umbrafen Tribe")
Q.Abandon()
for position, entry in ipairs(log) do
    if entry.title == "The Umbrafen Tribe" then table.remove(log, position) break end
end
local before = #abandoned
WipeLog()
AcceptPopup()
CHECK(#abandoned == before, "H: a quest that left the log while the dialog was up is not abandoned")
CHECK(Logged("no longer in the log") ~= nil, "H: and the refusal says why", printLog[1])

BuildLog()
Q.Refresh()

-- Turning the confirmation off drops it outright rather than doing nothing
db.ConfirmAbandon = false
Q.Select("Bombing Run")
popupsShown = {}
Q.Abandon()
CHECK(#popupsShown == 0, "H: confirmation off asks nothing")
CHECK(abandoned[#abandoned] == "Bombing Run", "H: and abandons it", tostring(abandoned[#abandoned]))
db.ConfirmAbandon = true
BuildLog()
Q.Refresh()

-- ---------------------------------------------------------------------------
-- I: the selection survives the log moving
-- ---------------------------------------------------------------------------
Q.Select("The Umbrafen Tribe")
CHECK(Q.Selected().index == 6, "I: index before", Q.Selected().index)
table.remove(log, 2)            -- a quest turned in above it
Q.Refresh()
CHECK(Q.Selected() ~= nil and Q.Selected().title == "The Umbrafen Tribe",
    "I: the same quest is still selected after every index below it moved")
CHECK(Q.Selected().index == 5, "I: at its new index", Q.Selected().index)

-- The selected quest being turned in re-selects rather than blanking
Q.Select("The Umbrafen Tribe")
for position, entry in ipairs(log) do
    if entry.title == "The Umbrafen Tribe" then table.remove(log, position) break end
end
Q.Refresh()
CHECK(Q.Selected() ~= nil, "I: turning in the selected quest selects another rather than emptying the pane")

BuildLog()
Q.Refresh()

-- ---------------------------------------------------------------------------
-- J: cost
--
-- QUEST_LOG_UPDATE arrives in bursts. A pass per event relayouts the whole
-- window several times per accepted quest and on every objective tick.
-- ---------------------------------------------------------------------------
local passes = 0
local realRefresh = Q.Refresh
Q.Refresh = function(...) passes = passes + 1 return realRefresh(...) end
for _ = 1, 20 do Fire("QUEST_LOG_UPDATE") end
CHECK(passes == 0, "J: twenty events in one frame do no work yet", passes)
RunTimers(1)
CHECK(passes == 1, "J: and then exactly one pass", passes)
Q.Refresh = realRefresh

-- ---------------------------------------------------------------------------
-- K: taking over the stock quest log
-- ---------------------------------------------------------------------------
CommanderQuestLog_Hide()
db.TakeOverQuestLog = true
ToggleQuestLog()
CHECK(_G.CommanderQuestLogFrame:IsShown(), "K: the L key opens ours")
CHECK(not QuestLogFrame:IsShown(), "K: and not Blizzard's")
ToggleQuestLog()
CHECK(not _G.CommanderQuestLogFrame:IsShown(), "K: and closes it again")

-- Any other door into the stock frame comes here too
hiddenPanels = {}
QuestLogFrame:Show()
CHECK(_G.CommanderQuestLogFrame:IsShown(), "K: showing the stock frame by any other path opens ours")
CHECK(hiddenPanels[#hiddenPanels] == "QuestLogFrame", "K: and puts the stock frame away")

-- Turning the takeover off hands Blizzard's window straight back, no reload
CommanderQuestLog_Hide()
db.TakeOverQuestLog = false
hiddenPanels = {}
ToggleQuestLog()
CHECK(QuestLogFrame:IsShown(), "K: takeover off gives the stock window back")
CHECK(not _G.CommanderQuestLogFrame:IsShown(), "K: and leaves ours shut")
CHECK(#hiddenPanels == 0, "K: without stealing the show from it")
QuestLogFrame:Hide()
db.TakeOverQuestLog = true

-- ---------------------------------------------------------------------------
-- L: settings
-- ---------------------------------------------------------------------------
CHECK(db.EnableQuestLog == true, "L: on by default")
CHECK(db.FrameStyle == "STONE", "L: a log left on the old parchment default is moved to dark stone")
CHECK(db.StyleGeneration == 2, "L: ...and stamped with the style generation that did it")
-- ...once. A parchment picked on purpose after that survives a second login
db.FrameStyle = "PARCHMENT"
Commander.UI.ApplyDefaults(db, { FrameStyle = "STONE", StyleGeneration = 2 })
CHECK(db.FrameStyle == "PARCHMENT", "L: a parchment chosen after the move is not moved again")
db.FrameStyle = "STONE"
db.Collapsed["Zangarmarsh"] = true
db.ShowLevels = false
SlashCmdList["COMMANDERUI_QUESTLOG"]("reset")
CHECK(db.ShowLevels == true, "L: Restore Defaults puts the options back")
CHECK(db.Collapsed["Zangarmarsh"] == true,
    "L: but a folded zone is data the player authored, not an option -- it survives")

-- ---------------------------------------------------------------------------
-- M: difficulty colours
-- ---------------------------------------------------------------------------
local r, g, b = Q.DifficultyColor(70, 62)
CHECK(r == 1 and g == 0.1, "M: eight levels up is red")
r, g, b = Q.DifficultyColor(62, 62)
CHECK(r == 1 and g == 1 and b == 0, "M: your own level is yellow")
r, g, b = Q.DifficultyColor(58, 62)
CHECK(g > r, "M: a few levels down is green")
r, g, b = Q.DifficultyColor(20, 62)
CHECK(r == g and g == b, "M: far enough down is grey")

-- ---------------------------------------------------------------------------
-- O: ink on paper
-- ---------------------------------------------------------------------------
-- In-game report: the parchment log was hard to read. The neutrals had been
-- picked for the paper, but every SEMANTIC colour -- difficulty, quality, the
-- objective lines, "ready", the count -- was still the bright literal picked
-- for a dark panel, and bright on tan is within a shade of the tan. Now every
-- colour written on the sheet is scaled to ink luminance; on the dark panel
-- the same colours are left alone.
local function OpenAs(style)
    db.FrameStyle = style
    _G.CommanderQuestLogFrame:Hide()
    CommanderQuestLog_Show()
    db.Filter = "ALL"
    Q.Refresh()
end
local function RowByTitle(title)
    for _, row in ipairs(Q._NavRows()) do
        if row:IsShown() and row.title and row.title:GetText() == title then return row end
    end
end
local INK_MAX = 0.34 + 0.001

OpenAs("PARCHMENT")
Q.Select("Ravager Egg Collection")   -- level 60 to a level-62 reader: the loudest yellow
local row = RowByTitle("Ravager Egg Collection")
CHECK(row ~= nil, "O: the level-60 row is on the board")
CHECK(row and Lum(row.level.__color) <= INK_MAX,
    "O: on paper the difficulty yellow is brought down to ink", row and tostring(Lum(row.level.__color)))
CHECK(row and row.level.__color[1] == row.level.__color[2] and row.level.__color[3] == 0
    and row.level.__color[1] > 0.3,
    "O: ...and is still a yellow, not a grey", row and tostring(row.level.__color[1]))
local colors = BlockColors()
for text, c in pairs(colors) do
    CHECK(Lum(c) <= INK_MAX, "O: every briefing line reads as ink on paper: " .. text, tostring(Lum(c)))
end
CHECK(Lum(_G.CommanderQuestLogFrame.navPane.__backdropColor or { 0, 0, 0, 0.5 }) >= 0
    and (_G.CommanderQuestLogFrame.navPane.__backdropColor or { 0, 0, 0, 0.5 })[4] < 0.3,
    "O: the inset panes are not half-black over the paper")

OpenAs("STONE")
row = RowByTitle("Ravager Egg Collection")
CHECK(row and row.level.__color[1] == 1 and row.level.__color[2] == 1,
    "O: on the stone the yellow is the full yellow")
CHECK(Lum(BlockColors()["OBJECTIVES"]) > 0.5, "O: ...and the headings take the light ink")
CHECK(_G.CommanderQuestLogFrame.parchment and _G.CommanderQuestLogFrame.parchment._material == "STONE",
    "O: the sheet is cut from stone")
CHECK((_G.CommanderQuestLogFrame.navPane.__backdropColor or {})[4] == 0.5,
    "O: ...with the half-black inset over it")
OpenAs("PARCHMENT")
CHECK(_G.CommanderQuestLogFrame.parchment._material == "PARCHMENT",
    "O: switching to parchment re-cuts the same sheet")

OpenAs("DARK")
row = RowByTitle("Ravager Egg Collection")
CHECK(row and row.level.__color[1] == 1 and row.level.__color[2] == 1,
    "O: on the dark panel the same yellow is the full yellow")
CHECK((_G.CommanderQuestLogFrame.navPane.__backdropColor or {})[4] == 0.5,
    "O: ...and the panes go back to their half-black inset")
OpenAs("STONE")

-- ---------------------------------------------------------------------------
-- P: the reset clocks
-- ---------------------------------------------------------------------------
-- The daily reset is the era's own GetQuestResetTime. The weekly reset is
-- the modern C_DateAndTime answer when it is plausible, and otherwise is
-- COMPUTED as the next daily reset on the region's reset day -- a weekday
-- in SERVER-LOCAL time, because KR and TW reset Thursday 07:00 local, which
-- is Wednesday 22:00 UTC, and a UTC weekday there is a week off.
local DAY = 86400
CHECK(Q.ServerOffset(1700000000, 14, 13) == -8 * 3600, "P: the server's UTC offset is read off the game clock",
    Q.ServerOffset(1700000000, 14, 13))
CHECK(Q.ServerOffset(1700000000, 7, 14) == 9 * 3600, "P: ...a minute of truncation jitter rounds away",
    Q.ServerOffset(1700000000, 7, 14))
CHECK(Q.ServerOffset(1700000000, 7, 43) == 9.5 * 3600, "P: ...and a half-hour zone is kept",
    Q.ServerOffset(1700000000, 7, 43))
CHECK(Q.WeeklyFromDaily(60400, 1700000000, 1, -8 * 3600) == 60400 + 6 * DAY,
    "P: US: the Wednesday daily reset is six days short of the Tuesday weekly one")
CHECK(Q.WeeklyFromDaily(60400, 1700000000, 3, 3600) == 60400 + 0 * DAY,
    "P: EU: a Wednesday daily reset IS the weekly reset")
-- KR: the next daily reset is Wednesday 22:00 UTC, which is Thursday 07:00
-- in Seoul. Thursday is KR's reset day, so it is the weekly reset -- and a
-- UTC weekday would have called it Wednesday and put the weekly one a week out.
CHECK(Q.WeeklyFromDaily(85600, 1700000000, 2, 9 * 3600) == 85600,
    "P: KR: the weekly reset is found on the server's weekday, not UTC's",
    Q.WeeklyFromDaily(85600, 1700000000, 2, 9 * 3600))
CHECK(Q.WeeklyFromDaily(85600, 1700000000, 2, 0) == 85600 + DAY,
    "P: ...which a UTC weekday would have put a day late",
    Q.WeeklyFromDaily(85600, 1700000000, 2, 0))

local picked, source = Q.PickWeekly(578800, 60400, 999)
CHECK(picked == 578800 and source == "api", "P: a plausible API answer is believed")
picked, source = Q.PickWeekly(nil, 60400, 578800)
CHECK(picked == 578800 and source == "computed", "P: a missing API falls back to the computed clock")
picked, source = Q.PickWeekly(0, 60400, 578800)
CHECK(picked == 578800 and source == "computed", "P: ...so does zero")
picked, source = Q.PickWeekly(30000, 60400, 578800)
CHECK(picked == 578800 and source == "computed", "P: ...and a weekly reset before the next daily one")
picked, source = Q.PickWeekly(60400 + 6 * DAY + 5 * 3600, 60400, 578800)
CHECK(picked == 578800 and source == "computed", "P: ...and one that is not a whole number of days out")
picked, source = Q.PickWeekly(60400 + 6 * DAY + 3000, 60400, 578800)
CHECK(source == "api", "P: ...but the hour a DST shift can move it by is allowed")
picked, source = Q.PickWeekly(nil, nil, nil)
CHECK(picked == nil and source == "none", "P: no clock at all is reported as none, not as zero")

CHECK(Q.FormatCountdown(6 * DAY + 4 * 3600 + 59 * 60) == "6d 4h", "P: days read as days and hours")
CHECK(Q.FormatCountdown(4 * 3600 + 5 * 60 + 30) == "4h 05m", "P: hours read as hours and minutes")
CHECK(Q.FormatCountdown(12 * 60 + 5) == "12m 05s", "P: minutes read as minutes and seconds")
CHECK(Q.FormatCountdown(42) == "42s", "P: under a minute reads as seconds")
CHECK(Q.FormatCountdown(-5) == "0s", "P: a clock that has passed reads as zero, not as negative")
CHECK(Q.FormatCountdown(nil) == "--", "P: no clock reads as a dash")
CHECK(Q.FormatResetMoment(60400, 1700000000, -8 * 3600) == "Wednesday at 07:00",
    "P: the reset moment is spelled in server time", Q.FormatResetMoment(60400, 1700000000, -8 * 3600))

-- The footer on screen
OpenAs("STONE")
local window = _G.CommanderQuestLogFrame
CHECK(window.resets and window.resets:IsShown(), "P: the footer is up under the navigator")
CHECK(raidInfoRequests > 0, "P: opening the window asks the server for the lockout list")
CHECK(window.resetDaily.value:GetText() == "16h 46m", "P: the daily clock reads the daily reset",
    window.resetDaily.value:GetText())
CHECK(window.resetWeekly.value:GetText() == "6d 16h", "P: the weekly clock reads the weekly reset",
    window.resetWeekly.value:GetText())
local navBottom
for _, pt in ipairs(window.navPane.__points or {}) do
    if pt.point == "BOTTOMLEFT" then navBottom = pt.y end
end
CHECK(navBottom == 10 + 4 + 26 + 4, "P: the navigator stops short to leave room for it", navBottom)

-- It ticks. The tick reads the clocks live, so moving the mock's clock and
-- firing a second of OnUpdate moves the readout. The whole clock moves, not
-- just the countdown: it is now Wednesday 06:45:55 on the server, fourteen
-- minutes short of the same 07:00 reset.
clock.serverTime = 1700060400 - (14 * 60 + 5)
clock.gameHour, clock.gameMinute = 6, 45
clock.daily = 14 * 60 + 5
clock.apiWeekly = 14 * 60 + 5 + 6 * DAY
local tick = window.resets:GetScript("OnUpdate")
tick(window.resets, 0.4)
CHECK(window.resetDaily.value:GetText() == "16h 46m", "P: under a second, the clock has not moved")
tick(window.resets, 0.7)
CHECK(window.resetDaily.value:GetText() == "14m 05s", "P: a second on, the clock has ticked",
    window.resetDaily.value:GetText())
CHECK(window.resetDaily.value.__color and window.resetDaily.value.__color[1] == 1
    and window.resetDaily.value.__color[2] < 0.7,
    "P: with a quarter hour left the daily clock warms up")
CHECK(window.resetWeekly.value.__color and window.resetWeekly.value.__color[1] < 0.9,
    "P: ...and the weekly one, six days out, does not")

-- The tooltips
window.resetDaily:GetScript("OnEnter")(window.resetDaily)
local function TipHas(text)
    for _, line in ipairs(GameTooltip.__lines) do
        if line:find(text, 1, true) then return true end
    end
    return false
end
CHECK(TipHas("Daily quests reset in 14m 05s"), "P: the daily tooltip carries the countdown")
CHECK(TipHas("Wednesday at 07:00, server time"), "P: ...and the server-time moment", table.concat(GameTooltip.__lines, " | "))
CHECK(TipHas("3 of 25 daily quests done today"), "P: ...and the day's daily count")

savedInstances = {
    { name = "Karazhan", reset = 6 * DAY + 3600, isRaid = true },
    { name = "The Mechanar", reset = 14 * 60 + 5, isRaid = false, difficultyName = "Heroic" },
    { name = "Zul'Aman", reset = 2 * DAY, isRaid = true, extended = true },
    { name = "Gruul's Lair", reset = 0, isRaid = true, locked = false },
}
window.resetWeekly:GetScript("OnEnter")(window.resetWeekly)
CHECK(TipHas("Arena points are paid and raid lockouts clear in 6d 0h"),
    "P: the weekly tooltip says what the week resets", table.concat(GameTooltip.__lines, " | "))
CHECK(TipHas("Tuesday at 07:00, server time"), "P: ...on the region's reset day")
CHECK(TipHas("Your lockouts"), "P: ...and lists the lockouts")
CHECK(TipHas("Karazhan  6d 1h"), "P: each with its own clock")
CHECK(TipHas("Zul'Aman (extended)  2d 0h"), "P: an extended lock says so")
CHECK(TipHas("The Mechanar  14m 05s"), "P: a heroic's daily lock is listed too")
CHECK(not TipHas("Gruul"), "P: a lock that has lapsed is not")
local lockouts = Q.ReadLockouts()
CHECK(lockouts[1].name == "Zul'Aman" and lockouts[2].name == "Karazhan" and lockouts[3].name == "The Mechanar",
    "P: raids come first, soonest first, then the dungeons")
CHECK(not TipHas("Worked out from"), "P: an API-sourced weekly clock is not flagged as computed")

-- The API is not trusted blindly: a weekly answer before the daily one is
-- the computed clock instead (the same figure here, because the fixture's
-- API was telling the truth), and the tooltip says so
clock.apiWeekly = 10
tick(window.resets, 1)
CHECK(window.resetWeekly.value:GetText() == "6d 0h", "P: an implausible API weekly falls back to the calendar",
    window.resetWeekly.value:GetText())
window.resetWeekly:GetScript("OnEnter")(window.resetWeekly)
CHECK(TipHas("Worked out from the daily reset"), "P: ...and the tooltip says the figure is worked out")
C_DateAndTime = nil
tick(window.resets, 1)
CHECK(window.resetWeekly.value:GetText() == "6d 0h", "P: with no C_DateAndTime at all the calendar still answers")
clock.daily = nil
tick(window.resets, 1)
CHECK(window.resetDaily.value:GetText() == "--" and window.resetWeekly.value:GetText() == "--",
    "P: with no daily clock either, both read as a dash rather than as zero")
clock.daily = 60400
clock.apiWeekly = 578800
C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return clock.apiWeekly end }

-- The setting
db.ShowResetTimers = false
Q.AnchorNavPane()
CHECK(not window.resets:IsShown(), "P: turning the setting off hides the footer")
navBottom = nil
for _, pt in ipairs(window.navPane.__points or {}) do
    if pt.point == "BOTTOMLEFT" then navBottom = pt.y end
end
CHECK(navBottom == 10 + 4, "P: ...and the navigator takes the room back", navBottom)
db.ShowResetTimers = true
Q.AnchorNavPane()
CHECK(window.resets:IsShown(), "P: ...and on again brings it back")
SlashCmdList["COMMANDERUI_QUESTLOG"]("reset")
CHECK(db.ShowResetTimers == true, "P: on by default")

-- On paper the clocks are ink like everything else
OpenAs("PARCHMENT")
CHECK(Lum(window.resetDaily.value.__color) <= INK_MAX, "P: on paper the clock is ink",
    tostring(Lum(window.resetDaily.value.__color)))
CHECK(Lum(window.resetDaily.label.__color) <= INK_MAX, "P: ...and so is its label")
OpenAs("STONE")

-- ---------------------------------------------------------------------------
-- Q: the Zones tab
--
-- Over the fake Questie's small Hellfire Peninsula (fake_questie.lua's header
-- says what the engine makes of it: 13 count, 2 done, 15%). The quest log is
-- rebuilt to match the fake world's, where Force Commander Danath (9003) is
-- the one quest in the log. Each block is its own scope: the main chunk of
-- this file is already a long way into Lua's 200 locals.
-- ---------------------------------------------------------------------------
local orders = {}
-- A recording Commander Orders, shaped like its public table (Add answers a
-- uid, AddRoute a route id); the legacy single-slot order must never be used
local legacyOrders = 0
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
CommanderOrders_IssueOrder = function() legacyOrders = legacyOrders + 1 return true end

do
    local Z, A = Q.Zones, Q.Questie
    log = {
        Header("Hellfire Peninsula"),
        Quest({
            title = "Force Commander Danath", level = 60, questID = 9003,
            description = "Report to the Force Commander at Honor Hold.",
            objectivesText = "Report to Force Commander Danath.",
            objectives = { { text = "Report to Force Commander Danath: 0/1", finished = false } },
        }),
    }
    selection = 0
    watched = {}
    for _ = 1, 4 do RunTimers(1) end
    CHECK(A.State() == "READY", "Q: the fake Questie is ready by now", A.State())

    -- The Log first: with Questie ready, the briefing says where the quest is
    -- handed in, and the Waypoint button goes there
    db.ViewMode = "LOG"
    CommanderQuestLog_Hide()
    CommanderQuestLog_Show()
    local window = _G.CommanderQuestLogFrame
    Q.Select("Force Commander Danath")
    local function Shown(blocks)
        local out = {}
        for _, fs in ipairs(blocks) do
            if fs:IsShown() and fs:GetText() then out[#out + 1] = fs:GetText() end
        end
        return out
    end
    local function Has(lines, text)
        for _, line in ipairs(lines) do
            if line:find(text, 1, true) then return line end
        end
        return nil
    end
    CHECK(Has(Shown(Q._DetailStrings()), "Turn in: Force Commander Danath \226\128\148 Hellfire Peninsula (56.6, 66.4)"),
        "Q: the Log's briefing gains the Turn in line", table.concat(Shown(Q._DetailStrings()), " | "))
    CHECK(window.waypointBtn:IsShown() and window.waypointBtn:IsEnabled(), "Q: ...and its Waypoint button is live")
    orders = {}
    window.waypointBtn:GetScript("OnClick")(window.waypointBtn)
    CHECK(orders[1] and orders[1].uiMapId == 1944 and math.abs(orders[1].x - 0.566) < 1e-6
        and math.abs(orders[1].y - 0.664) < 1e-6,
        "Q: ...which sends Commander Orders to the turn-in (uiMap, 0..1 coordinates)",
        orders[1] and (orders[1].uiMapId .. " " .. orders[1].x .. " " .. orders[1].y))
    CHECK(orders[1] and orders[1].spec.source == "QuestLog" and orders[1].spec.key == "quest:9003"
        and orders[1].spec.setArrow == true,
        "Q: ...as the quest's own waypoint, taking the arrow", orders[1] and orders[1].spec.key)

    -- The tabs
    local W, S = Z._Widgets(), Z._State()
    CHECK(W.tabs and W.tabs.LOG:IsShown() and W.tabs.ZONE:IsShown(), "Q: the window carries a Log and a Zones tab")
    CHECK(W.tabs.LOG.underline.__color[4] > 0.5 and W.tabs.ZONE.underline.__color[4] == 0,
        "Q: ...and on the Log, the Log tab is the underlined one")
    CHECK((W.tabs.ZONE:GetFrameLevel() or 0) > (window:GetFrameLevel() or 0) + 1,
        "Q: the tabs sit above the drag strip, or it takes their clicks", W.tabs.ZONE:GetFrameLevel())

    W.tabs.ZONE:GetScript("OnClick")(W.tabs.ZONE)
    CHECK(db.ViewMode == "ZONE" and Q.ViewMode() == "ZONE", "Q: the Zones tab switches the window over")
    CHECK(W.tabs.ZONE.underline.__color[4] > 0.5 and W.tabs.LOG.underline.__color[4] == 0,
        "Q: ...and is now the underlined one")
    CHECK(not window.filters.ALL:IsShown() and not window.sortDrop:IsShown() and not window.countHit:IsShown(),
        "Q: the Log's filters, sort and count are put away")
    CHECK(not window.trackBtn:IsShown() and not window.abandonBtn:IsShown() and not window.waypointBtn:IsShown(),
        "Q: ...and its action bar")
    local logRowsShown = 0
    for _, row in ipairs(Q._NavRows()) do if row:IsShown() then logRowsShown = logRowsShown + 1 end end
    CHECK(logRowsShown == 0, "Q: ...and every one of its navigator rows", logRowsShown)
    CHECK(W.toolbar:IsShown() and W.card:IsShown() and W.actions:IsShown(),
        "Q: the zone toolbar, card and action bar are up")
    CHECK(W.filters.MISSED and W.filters.MISSED:IsShown(), "Q: five zone filters, Missed among them")
    local navTop
    for _, pt in ipairs(window.navPane.__points or {}) do
        if pt.point == "TOPLEFT" then navTop = pt.y end
    end
    CHECK(navTop == -8 - 50, "Q: the navigator moves down under the zone card", navTop)

    -- The zone card
    CHECK(W.card.name:GetText() == "Hellfire Peninsula", "Q: the card follows you to Hellfire Peninsula",
        W.card.name:GetText())
    CHECK(W.card.totals:GetText() == "2 / 13  \194\183  15%", "Q: ...with its totals", W.card.totals:GetText())
    CHECK(W.card.bar:IsShown() and math.abs(W.card.bar:GetWidth() - (296 - 16) * 2 / 13) < 0.01,
        "Q: ...and a completion bar 2/13 of the way across", W.card.bar:GetWidth())
    CHECK((W.card.note:GetText() or ""):find("Following you", 1, true), "Q: ...that says it is following you")
    CHECK(W.countFS:GetText() == "25 shown", "Q: the readout counts what is listed", W.countFS:GetText())

    -- The rows
    local function ZoneRow(title)
        for _, row in ipairs(W.rows) do
            if row:IsShown() and row.title:GetText() == title then return row end
        end
        return nil
    end
    local pick = ZoneRow("Pick up now")
    CHECK(pick and pick.headerTitle == "Pick up now" and pick.state:GetText() == "9",
        "Q: the Guide's Pick up now heading, with its count", pick and pick.state:GetText())
    local enemy = ZoneRow("Know Your Enemy")
    CHECK(enemy and enemy.state:GetText() == "open", "Q: an available quest says open",
        enemy and enemy.state:GetText())
    CHECK(enemy and enemy.strip:IsShown() and enemy.strip.__color ~= nil, "Q: ...with its status strip drawn")
    local kruush = ZoneRow("Wanted: Worg Master Kruush")
    CHECK(kruush and kruush.state:GetText() == "lv 63", "Q: a level-locked quest names the level",
        kruush and kruush.state:GetText())
    CHECK(enemy and kruush and (enemy.strip.__color[1] ~= kruush.strip.__color[1]
        or enemy.strip.__color[2] ~= kruush.strip.__color[2]),
        "Q: ...and its strip is a different colour from an open one")
    CHECK(ZoneRow("Ill Omens") and ZoneRow("Ill Omens").state:GetText() == "missed", "Q: a missed quest says missed")
    -- The player stands at 50, 60: Field Marshal Brock's choice (62.4, 60.6)
    -- is a few yards off, the Patrol Sentry (20, 20) is across the zone. By
    -- level the sentry's quest (61) would come first.
    local bladeAt, sentryAt
    for index, item in ipairs(S.rows) do
        if item.entry and item.entry.id == 9012 then bladeAt = index end
        if item.entry and item.entry.id == 9033 then sentryAt = index end
    end
    CHECK(bladeAt and sentryAt and bladeAt < sentryAt, "Q: Pick up now runs nearest giver first",
        tostring(bladeAt) .. " vs " .. tostring(sentryAt))
    local shield, blade = ZoneRow("Choose: the Shield"), ZoneRow("Choose: the Blade")
    CHECK(shield and blade and Lum(shield.title.__color) < Lum(blade.title.__color),
        "Q: the exclusive choice that does not count is dimmed by counted, not by bucket")
    for _, word in ipairs({ "\226\156\147", "\226\151\143", "\226\150\182", "\226\152\133" }) do
        local found = false
        for _, row in ipairs(W.rows) do
            if row:IsShown() and ((row.state:GetText() or ""):find(word, 1, true)) then found = true end
        end
        CHECK(not found, "Q: no shape glyph in a state word (D11)")
    end

    -- Folding goes into ZoneCollapsed, never the Log's Collapsed
    local doneHeader = ZoneRow("Done")
    doneHeader:GetScript("OnClick")(doneHeader, "LeftButton")
    CHECK(db.ZoneCollapsed["Done"] == true and db.Collapsed["Done"] == nil,
        "Q: folding a group writes ZoneCollapsed, not Collapsed")
    CHECK(ZoneRow("Done") ~= nil and ZoneRow("Arrival in Outland") == nil,
        "Q: ...hides its quests and keeps its heading")
    ZoneRow("Done"):GetScript("OnClick")(ZoneRow("Done"), "LeftButton")
    CHECK(ZoneRow("Arrival in Outland") ~= nil and db.ZoneCollapsed["Done"] == nil, "Q: ...and unfolds again")

    -- The overview: nothing selected
    CHECK(Z.Selected() == nil, "Q: nothing is selected on arrival; the briefing is the zone's overview")
    local overview = Shown(W.blocks)
    CHECK(Has(overview, "2 of 13 quests done  \194\183  15%"), "Q: the overview's completion line",
        table.concat(overview, " | "))
    CHECK(Has(overview, "Done 2  \194\183  In log 1  \194\183  Open 8  \194\183  Locked 2"),
        "Q: the breakdown sums to the 13 that count")
    CHECK(Has(overview, "Missed 3") and Has(overview, "Other choices 1") and Has(overview, "(not counted)"),
        "Q: ...and the uncounted line says what is left out")
    CHECK(Has(overview, "NEXT UP") and Has(overview, "Know Your Enemy \226\128\148 Sergeant Altumus"),
        "Q: NEXT UP lists what to do with who gives it")
    CHECK(Has(overview, "CHAINS") and Has(overview, "Arrival in Outland  2/4"), "Q: the chains with done/total")
    CHECK(Has(overview, "MISSED") and Has(overview, "Ill Omens \226\128\148 Your reputation is past"),
        "Q: the missed quests with their reasons")
    local fills = 0
    for _, quad in ipairs(W.quads) do if quad:IsShown() then fills = fills + 1 end end
    CHECK(fills >= 5, "Q: the overview draws its bars from quads", fills)
    -- NEXT UP is the Guide's own order (C.NextUp), and drawing it must not
    -- regroup the view: the navigator's rows find their headings through the
    -- header the LAST grouping wrote onto each entry
    local expected = Q.Completion.NextUp(S.view, 6, { playerPos = A.PlayerPos(3483) })
    local drawnAt = {}
    for index, line in ipairs(overview) do
        for position, entry in ipairs(expected) do
            if not drawnAt[position] and line:find("  " .. entry.title, 1, true) then drawnAt[position] = index end
        end
    end
    local inOrder = #expected == 6
    for position = 2, #expected do
        if not (drawnAt[position] and drawnAt[position - 1] and drawnAt[position] > drawnAt[position - 1]) then
            inOrder = false
        end
    end
    CHECK(inOrder, "Q: NEXT UP is the Guide's first six, in the Guide's order")
    CHECK(S.view.byId[9005].header == "Pick up now" and S.view.byId[9001].header == "Done",
        "Q: ...and drawing the overview leaves the navigator's headings alone",
        tostring(S.view.byId[9005].header))

    -- A quest: The Legion Reborn, locked behind the one in the log
    selection = 0
    ZoneRow("The Legion Reborn"):GetScript("OnClick")(ZoneRow("The Legion Reborn"), "LeftButton")
    CHECK(Z.Selected() and Z.Selected().id == 9004, "Q: clicking a row selects it")
    ZoneRow("The Legion Reborn"):GetScript("OnClick")(ZoneRow("The Legion Reborn"), "LeftButton")
    CHECK(Z.Selected() == nil, "Q: clicking it again goes back to the overview")
    ZoneRow("The Legion Reborn"):GetScript("OnClick")(ZoneRow("The Legion Reborn"), "LeftButton")
    CHECK(ZoneRow("The Legion Reborn").selection:IsShown(), "Q: ...with the selection band on its row")
    local brief = Shown(W.blocks)
    CHECK(brief[1] == "The Legion Reborn", "Q: the quest briefing leads with its title", brief[1])
    CHECK(Has(brief, "Level 62  \194\183  requires 61  \194\183  Hellfire Peninsula"), "Q: ...then its facts")
    CHECK(Has(brief, "Complete \"Force Commander Danath\" first."), "Q: ...then the engine's sentence")
    CHECK(Has(brief, "Starts  Force Commander Danath \226\128\148 Hellfire Peninsula 56.6, 66.4"),
        "Q: WHERE: the Starts line, giver, zone and spot")
    CHECK(Has(brief, "Ends  Force Commander Danath"), "Q: ...and the Ends line")
    CHECK(Has(brief, "CHAIN  \194\183  2 of 4 done"), "Q: CHAIN with the chain's own count")
    CHECK(Has(brief, "Arrival in Outland") and Has(brief, "Journey to Honor Hold"),
        "Q: ...every member of the chain, one line each")
    local band = W.bands[1]
    CHECK(band and band:IsShown(), "Q: ...the current quest's line carries the accent band")
    CHECK(selection == 0, "Q: drawing the Zones tab leaves the client's log selection alone (D2)", selection)
    Z.Select(9003)
    CHECK(Z.Selected() and Z.Selected().id == 9003 and selection == 0,
        "Q: ...even briefing the quest that IS in the log (Q.ReadDetail puts it back)", selection)

    -- D6: a selection the filter or a fold takes off the list falls back to
    -- the zone's overview rather than briefing a quest nobody can see
    Z.Select(9004)
    db.ZoneFilter = "MISSED"
    Q.Refresh()
    CHECK(Z.Selected() == nil and Shown(W.blocks)[1] == "Hellfire Peninsula",
        "Q: filtering the selected quest away drops the briefing to the overview")
    db.ZoneFilter = "ALL"
    Q.Refresh()
    CHECK(Z.Selected() == nil, "Q: ...and stays there when the filter opens up again")
    Z.Select(9004)
    db.ZoneCollapsed["After another quest"] = true
    Q.Refresh()
    CHECK(Z.Selected() == nil, "Q: ...and so does folding its group shut")
    db.ZoneCollapsed["After another quest"] = nil
    Z.Select(9004)

    -- The rest of a quest briefing: what it leads to, what it pays in standing
    Z.Select(9003)
    brief = Shown(W.blocks)
    CHECK(Has(brief, "LEADS TO") and Has(brief, "The Legion Reborn (Hellfire Peninsula)"),
        "Q: LEADS TO names the follow-up with its zone", table.concat(brief, " | "))
    Z.Select(9005)
    brief = Shown(W.blocks)
    CHECK(Has(brief, "REPUTATION") and Has(brief, "+250  Honor Hold"), "Q: REPUTATION lists what it pays")
    CHECK(Has(brief, "OBJECTIVES") and Has(brief, "Scout the Legion front."),
        "Q: a quest not in the log shows Questie's objective text")
    CHECK(not Has(brief, "REQUIRES"), "Q: no REQUIRES for a quest with nothing outside the zone in front of it")

    -- Tooltips: the row's reason and giver, and which way a waypoint goes
    local tipRow = ZoneRow("Wanted: Worg Master Kruush")
    tipRow:GetScript("OnEnter")(tipRow)
    local tip = table.concat(GameTooltip.__lines, " | ")
    CHECK(tip:find("Needs level 63", 1, true) and tip:find("Starts: Wing Commander Dabir", 1, true)
        and tip:find("Right-click for a waypoint", 1, true),
        "Q: a row's tooltip carries the reason, the giver and the hint", tip)
    W.waypointBtn:GetScript("OnEnter")(W.waypointBtn)
    tip = table.concat(GameTooltip.__lines, " | ")
    CHECK(tip:find("the Commander Orders arrow", 1, true), "Q: the Waypoint tooltip says which path will run", tip)
    window.waypointBtn:GetScript("OnEnter")(window.waypointBtn)
    CHECK(table.concat(GameTooltip.__lines, " | "):find("the Commander Orders arrow", 1, true),
        "Q: ...and so does the Log's")
    W.card:GetScript("OnEnter")(W.card)
    tip = table.concat(GameTooltip.__lines, " | ")
    CHECK(tip:find("Hellfire Peninsula", 1, true) and tip:find("Right-click to follow", 1, true),
        "Q: the card's tooltip names the zone and how to follow you", tip)

    -- Ink on paper: the Zones tab is held to D16 like the Log (section O)
    OpenAs("PARCHMENT")
    Z.Select(9004)
    for _, fs in ipairs(W.blocks) do
        if fs:IsShown() then
            CHECK(Lum(fs.__color) <= INK_MAX, "Q: zone briefing ink on paper: " .. tostring(fs:GetText()),
                tostring(Lum(fs.__color)))
        end
    end
    Z.Select(nil)
    for _, fs in ipairs(W.blocks) do
        if fs:IsShown() then
            CHECK(Lum(fs.__color) <= INK_MAX, "Q: zone overview ink on paper: " .. tostring(fs:GetText()),
                tostring(Lum(fs.__color)))
        end
    end
    local inkRow = ZoneRow("Know Your Enemy")
    CHECK(inkRow and Lum(inkRow.title.__color) <= INK_MAX and Lum(inkRow.state.__color) <= INK_MAX
        and Lum(inkRow.level.__color) <= INK_MAX, "Q: ...and the rows' title, state and level")
    CHECK(Lum(W.card.totals.__color) <= INK_MAX and Lum(W.card.name.__color) <= INK_MAX, "Q: ...and the card")
    OpenAs("STONE")
    CHECK(Q.ViewMode() == "ZONE", "Q: reopening the window keeps the tab it was left on")

    -- The action bar
    Z.Select(9004)
    CHECK(W.waypointBtn:IsEnabled() and W.mapBtn:IsEnabled() and W.ignoreBtn:IsEnabled(),
        "Q: a selected quest lights Waypoint, Show on Map and Ignore")
    CHECK(not W.logBtn:IsEnabled(), "Q: ...but not Open in Log for a quest that is not in it")
    orders = {}
    W.waypointBtn:GetScript("OnClick")(W.waypointBtn)
    CHECK(orders[1] and orders[1].uiMapId == 1944 and math.abs(orders[1].x - 0.566) < 1e-6,
        "Q: Waypoint goes through Commander Orders to where the quest starts")
    CHECK(orders[1] and orders[1].spec.key == "quest:9004" and orders[1].spec.source == "QuestLog",
        "Q: ...owned by that quest", orders[1] and orders[1].spec.key)
    orders = {}
    local fel = ZoneRow("Sentry Duty")
    fel:GetScript("OnClick")(fel, "RightButton")
    CHECK(orders[1] and math.abs(orders[1].x - 0.20) < 1e-6 and math.abs(orders[1].y - 0.20) < 1e-6,
        "Q: right-clicking a row sets its waypoint", orders[1] and (orders[1].x .. "," .. orders[1].y))
    CHECK(Z.Selected() and Z.Selected().id == 9004, "Q: ...without moving the selection")
    Z.Select(nil)
    CHECK(not W.waypointBtn:IsEnabled() and not W.ignoreBtn:IsEnabled() and W.mapBtn:IsEnabled()
        and W.routeBtn:IsEnabled(), "Q: on the overview only Show on Map and Route Zone are live")

    -- Route Zone: every open quest's giver as one Commander Orders route
    W.routeBtn:GetScript("OnEnter")(W.routeBtn)
    tip = table.concat(GameTooltip.__lines, " | ")
    CHECK(tip:find("route through every quest giver with an open quest in Hellfire Peninsula", 1, true)
        and tip:find("6 givers", 1, true), "Q: Route Zone's tooltip names the zone and counts the givers", tip)
    orders = {}
    W.routeBtn:GetScript("OnClick")(W.routeBtn)
    local route = orders[1] and orders[1].route
    CHECK(route and route.key == "open:3483" and route.source == "QuestLog" and route.mode == "NEAREST"
        and #route.stops == 6, "Q: ...and its click hands Orders one NEAREST route of six stops",
        route and (tostring(route.key) .. " " .. #route.stops))
    local savedOrders = CommanderOrders
    CommanderOrders = nil
    Z.UpdateActions()
    CHECK(not W.routeBtn:IsEnabled(), "Q: without Commander Orders, Route Zone is greyed out")
    W.routeBtn:GetScript("OnEnter")(W.routeBtn)
    CHECK(table.concat(GameTooltip.__lines, " | "):find("Needs Commander Orders", 1, true),
        "Q: ...and its tooltip says why")
    W.waypointBtn:GetScript("OnEnter")(W.waypointBtn)
    CHECK(table.concat(GameTooltip.__lines, " | "):find("a /way line (Commander Orders is not loaded)", 1, true),
        "Q: ...and the Waypoint tooltip says it will print")
    CommanderOrders = savedOrders
    Z.UpdateActions()

    -- Ignore is per character and moves the percentage, after the debounce
    Z.Select(9005)
    W.ignoreBtn:GetScript("OnClick")(W.ignoreBtn)
    CHECK(CommanderQuestLogChar.Ignored[9005] == true, "Q: Ignore writes the per-character list")
    CHECK(W.ignoreBtn:GetText() == "Count", "Q: ...and the button turns into Count at once")
    RunTimers(1)
    RunTimers(1)
    CHECK(W.card.totals:GetText() == "2 / 12  \194\183  16%", "Q: ...and the zone's total drops by one",
        W.card.totals:GetText())
    CHECK(ZoneRow("Know Your Enemy") and ZoneRow("Know Your Enemy").state:GetText() == "open"
        and Z.Selected() and Z.Selected().status == "IGNORED",
        "Q: the ignored quest stays listed, and selected, under Ignored")
    W.ignoreBtn:GetScript("OnClick")(W.ignoreBtn)
    RunTimers(1)
    RunTimers(1)
    CHECK(CommanderQuestLogChar.Ignored[9005] == nil and W.card.totals:GetText() == "2 / 13  \194\183  15%",
        "Q: Count puts it back", W.card.totals:GetText())

    -- Show on Map: out of combat only, then the map on this zone and the
    -- drawer told which quest
    local mapCalls, focused, focusedArea = {}, nil, nil
    WorldMapFrame = NewWidget("Frame", "WorldMapFrame")
    WorldMapFrame:Hide()
    WorldMapFrame.SetMapID = function(_, id) mapCalls[#mapCalls + 1] = id end
    WorldMapFrame.IsMaximized = function() return true end
    ToggleWorldMap = function() WorldMapFrame:Show() end
    Q.Map = { Focus = function(id, areaId) focused, focusedArea = id, areaId end }
    local inCombat = true
    InCombatLockdown = function() return inCombat end
    Z.Select(9004)
    WipeLog()
    W.mapBtn:GetScript("OnClick")(W.mapBtn)
    CHECK(#mapCalls == 0 and not WorldMapFrame:IsShown() and Logged("in combat"),
        "Q: Show on Map refuses in combat, and says so")
    inCombat = false
    W.mapBtn:GetScript("OnClick")(W.mapBtn)
    CHECK(WorldMapFrame:IsShown() and mapCalls[1] == 1944, "Q: ...and out of it opens the map on the zone's uiMap",
        tostring(mapCalls[1]))
    CHECK(focused == 9004, "Q: ...with the drawer focused on the selected quest")
    CHECK(focusedArea == 3483, "Q: ...and told the quest's zone, so it can move the map itself", tostring(focusedArea))
    CHECK(window:IsShown(), "Q: a maximised map covers the window rather than closing it")
    WorldMapFrame, ToggleWorldMap, InCombatLockdown = nil, nil, nil
    Q.Map = nil

    -- The live log is what says a quest is ready to hand in: the window hands
    -- every scan to the adapter, and the Guide moves it to Turn in
    -- (handed in, for this check, to the quartermaster at 54.0, 63.0, so the
    -- turn-in is not the same spot as the start)
    world.quests[9003].finishedBy = { { 20008 } }
    A.Bump("test")
    log[2].isComplete = 1
    log[2].objectives[1] = { text = "Report to Force Commander Danath: 1/1", finished = true }
    Q.Refresh()
    RunTimers(1)
    RunTimers(1)
    local danath = ZoneRow("Force Commander Danath")
    CHECK(danath and danath.state:GetText() == "ready" and ZoneRow("Turn in") ~= nil,
        "Q: a quest the log calls complete reads ready, under Turn in", danath and danath.state:GetText())
    Z.Select(9003)
    orders = {}
    W.waypointBtn:GetScript("OnClick")(W.waypointBtn)
    CHECK(orders[1] and math.abs(orders[1].x - 0.54) < 1e-6 and math.abs(orders[1].y - 0.63) < 1e-6,
        "Q: ...and its waypoint goes to the turn-in, not to where it started",
        orders[1] and (orders[1].x .. "," .. orders[1].y))
    CHECK(orders[1] and orders[1].spec.key == "quest:9003",
        "Q: ...moving the quest's one waypoint rather than adding a second", orders[1] and orders[1].spec.key)
    CHECK(legacyOrders == 0, "Q: the legacy single-slot order is never used", legacyOrders)
    world.quests[9003].finishedBy = { { 20002 } }
    A.Bump("test")
    log[2].isComplete = nil
    log[2].objectives[1] = { text = "Report to Force Commander Danath: 0/1", finished = false }
    Q.Refresh()
    RunTimers(1)
    RunTimers(1)

    -- Open in Log: only for a quest in the log, and it lands selected there
    Z.Select(9003)
    CHECK(W.logBtn:IsEnabled(), "Q: Open in Log is live for the quest in the log")
    CHECK(Has(Shown(W.blocks), "Report to Force Commander Danath: 0/1"),
        "Q: ...whose briefing carries its live objectives")
    W.logBtn:GetScript("OnClick")(W.logBtn)
    CHECK(Q.ViewMode() == "LOG" and Q.Selected() and Q.Selected().questID == 9003,
        "Q: Open in Log switches tabs with the quest selected")
    CHECK(window.trackBtn:IsShown() and window.filters.ALL:IsShown() and not W.card:IsShown(),
        "Q: ...the Log's widgets back, the zone card gone")
    navTop = nil
    for _, pt in ipairs(window.navPane.__points or {}) do
        if pt.point == "TOPLEFT" then navTop = pt.y end
    end
    CHECK(navTop == -8, "Q: ...and the navigator back at the top", navTop)

    -- Each tab keeps its own search
    local box = window.searchBox
    box:SetText("anguish")
    box:GetScript("OnTextChanged")(box, true)
    W.tabs.ZONE:GetScript("OnClick")(W.tabs.ZONE)
    CHECK((box:GetText() or "") == "", "Q: the Zones tab starts with its own, empty, search", box:GetText())
    box:SetText("legion")
    box:GetScript("OnTextChanged")(box, true)
    CHECK(W.countFS:GetText() == "1 shown" and ZoneRow("The Legion Reborn") ~= nil,
        "Q: a zone search narrows the list", W.countFS:GetText())
    W.tabs.LOG:GetScript("OnClick")(W.tabs.LOG)
    CHECK(box:GetText() == "anguish", "Q: back on the Log, the Log's search is back", box:GetText())
    W.tabs.ZONE:GetScript("OnClick")(W.tabs.ZONE)
    CHECK(box:GetText() == "legion" and W.countFS:GetText() == "1 shown", "Q: ...and the zone's on the Zones tab")
    Z.Select(9004)
    box:GetScript("OnEscapePressed")(box)
    CHECK(Z.SearchText() == "" and W.countFS:GetText() == "25 shown", "Q: Escape clears the zone search")
    CHECK(Z.Selected() and Z.Selected().id == 9004, "Q: ...and keeps the quest briefed")
    box:GetScript("OnEscapePressed")(box)
    CHECK(Z.Selected() == nil, "Q: Escape on an empty search goes back to the zone's overview")
    W.tabs.LOG:GetScript("OnClick")(W.tabs.LOG)
    box:GetScript("OnEscapePressed")(box)
    W.tabs.ZONE:GetScript("OnClick")(W.tabs.ZONE)

    -- Filters and groupings
    W.filters.MISSED:GetScript("OnClick")(W.filters.MISSED)
    CHECK(db.ZoneFilter == "MISSED" and W.countFS:GetText() == "3 shown", "Q: the Missed filter",
        W.countFS:GetText())
    CHECK(W.filters.MISSED.underline.__color[4] > 0.5 and W.filters.ALL.underline.__color[4] == 0,
        "Q: ...is the underlined one")
    W.filters.ALL:GetScript("OnClick")(W.filters.ALL)
    db.ZoneGroup = "CHAIN"
    Q.Refresh()
    local chainHead = ZoneRow("Arrival in Outland")
    CHECK(chainHead and chainHead.headerTitle == "Arrival in Outland" and chainHead.state:GetText() == "2/4",
        "Q: By chain: a heading per chain, reading done/total", chainHead and chainHead.state:GetText())
    db.ZoneGroup = "LEVEL"
    Q.Refresh()
    local headers, first = 0, nil
    for _, item in ipairs(S.rows) do
        if item.header then headers = headers + 1 elseif not first then first = item.entry end
    end
    CHECK(headers == 0 and first and first.level == 58, "Q: By level: one flat list, lowest first",
        first and first.level)
    db.ZoneGroup = "GUIDE"
    Q.Refresh()

    -- The zone menu: where I am, then categories, zones a level down
    local added = {}
    local realAdd = UIDropDownMenu_AddButton
    UIDropDownMenu_AddButton = function(info) added[#added + 1] = info end
    W.menu.__init(W.menu, 1)
    CHECK(added[1] and added[1].text == "Where I am" and added[1].checked, "Q: the zone menu leads with Where I am")
    local outland
    for _, info in ipairs(added) do if info.text == "Outland" then outland = info end end
    CHECK(outland and outland.hasArrow and outland.menuList == 3, "Q: ...then Questie's categories, each a submenu")
    added = {}
    W.menu.__init(W.menu, 2, 3)
    local terokkar, hellfire
    for _, info in ipairs(added) do
        if info.text:find("Terokkar Forest", 1, true) then terokkar = info end
        if info.text:find("Hellfire Peninsula", 1, true) then hellfire = info end
    end
    CHECK(hellfire and hellfire.text == "Hellfire Peninsula  15%", "Q: a computed zone shows its percentage",
        hellfire and hellfire.text)
    CHECK(terokkar and terokkar.arg1 == 3519, "Q: ...and every zone of the category is there", terokkar and terokkar.text)
    for _ = 1, 3 do RunTimers(1) end
    added = {}
    W.menu.__init(W.menu, 2, 3)
    for _, info in ipairs(added) do
        if info.text:find("Terokkar Forest", 1, true) then terokkar = info end
    end
    CHECK(terokkar and terokkar.text == "Terokkar Forest  0%",
        "Q: opening a category works its zones out in the background", terokkar and terokkar.text)
    UIDropDownMenu_AddButton = realAdd
    terokkar.func(nil, terokkar.arg1)
    CHECK(db.ZoneFollow == false and db.ZonePicked == 3519 and W.card.name:GetText() == "Terokkar Forest",
        "Q: picking a zone pins it", W.card.name:GetText())
    CHECK((W.card.note:GetText() or ""):find("Pinned", 1, true), "Q: ...and the card says it is pinned")
    W.card:GetScript("OnClick")(W.card, "RightButton")
    CHECK(db.ZoneFollow == true and W.card.name:GetText() == "Hellfire Peninsula",
        "Q: right-clicking the card follows you again")

    -- Opening from elsewhere: the map drawer's way in
    db.ZoneFilter = "DONE"
    CommanderQuestLog_Hide()
    CommanderQuestLog_OpenToZone(3519, 9014)
    CHECK(window:IsShown() and Q.ViewMode() == "ZONE", "Q: OpenToZone opens the window on the Zones tab")
    CHECK(W.card.name:GetText() == "Terokkar Forest" and db.ZoneFollow == false, "Q: ...pinned to that zone")
    CHECK(Z.Selected() and Z.Selected().id == 9014 and Shown(W.blocks)[1] == "Choose: the Staff",
        "Q: ...with the quest selected and briefed")
    CHECK(db.ZoneFilter == "ALL", "Q: ...the filter opened up to bring it into view")
    CommanderQuestLog_OpenToZone(3430)
    CHECK(W.emptyFS and W.emptyFS:IsShown()
        and (W.emptyFS:GetText() or ""):find("Questie lists no quests for Eversong Woods", 1, true),
        "Q: a zone with no quests says so", W.emptyFS and W.emptyFS:GetText())
    -- A quest link or the objective tracker opens the window to a LOG quest:
    -- that lands on the Log, whichever tab was up
    CommanderQuestLog_OpenToQuest(2)
    CHECK(Q.ViewMode() == "LOG" and Q.Selected() and Q.Selected().questID == 9003,
        "Q: opening the window to a quest in the log lands on the Log tab")

    -- The settings page: two new sections, every control where the player
    -- will look for it, and the pin kinds greyed out with the pins
    local function Control(label)
        for _, f in ipairs(allFrames) do
            if f.Text and f.Text.__text == label then return f end
            if f.__kind == "Button" and f.__text == label then return f end
        end
        return nil
    end
    for _, label in ipairs({ "Zones Tab", "Count Optional Quests", "Count Both Aldor and Scryers",
        "Count Dungeon and Class Quests That Start Here", "Completion Drawer", "Quest Giver Pins",
        "Locked Givers", "Available Givers Questie Hides", "Completed Givers", "Missed Givers",
        "Zone Percentages on Continent Maps", "Open Zones", "Clear Ignored (per character)" }) do
        CHECK(Control(label) ~= nil, "Q: the settings page has " .. label)
    end
    local settingsPanel
    for _, cat in ipairs(categories) do
        if cat.__panel and cat.__panel._key == "QuestLog" then settingsPanel = cat.__panel end
    end
    db.MapPins = false
    settingsPanel:Refresh()
    CHECK(Control("Locked Givers").__enabled == false and Control("Missed Givers").__enabled == false
        and Control("Zone Percentages on Continent Maps").__enabled == false
        and Control("Completion Drawer").__enabled ~= false,
        "Q: with the pins off, the kinds of pin (and the continent labels) grey out; the drawer does not")
    db.MapPins = true
    settingsPanel:Refresh()
    CHECK(Control("Locked Givers").__enabled == true, "Q: ...and come back with them")
    CommanderQuestLogChar.Ignored[9006] = true
    CommanderQuestLogChar.Ignored[9007] = true
    WipeLog()
    Control("Clear Ignored (per character)"):GetScript("OnClick")()
    CHECK(next(CommanderQuestLogChar.Ignored) == nil and Logged("2 ignored quests back in the count"),
        "Q: Clear Ignored empties this character's list, and says how many", printLog[1])
    RunTimers(1)

    -- Restore Defaults: the options go back, the folds and the per-character
    -- ignore list are the player's and stay
    db.ZoneCollapsed["Done"] = true
    db.MapCollapsed = { Done = false, Locked = true }
    db.CountRival = true
    db.ZoneGroup = "NAME"
    CommanderQuestLogChar.Ignored[9006] = true
    SlashCmdList["COMMANDERUI_QUESTLOG"]("reset")
    CHECK(db.CountRival == false and db.ZoneGroup == "GUIDE" and db.ShowZoneTab == true and db.MapPins == true,
        "Q: Restore Defaults puts the zone and map options back")
    CHECK(db.ZoneCollapsed["Done"] == true and db.MapCollapsed.Locked == true,
        "Q: ...but the Zones tab's and the drawer's folds survive it")
    CHECK(CommanderQuestLogChar.Ignored[9006] == true, "Q: ...and so does the per-character ignore list")
    db.ZoneCollapsed["Done"] = nil
    CommanderQuestLogChar.Ignored[9006] = nil
    RunTimers(1)

    -- The slash commands
    SlashCmdList["COMMANDERUI_QUESTLOG"]("zone")
    CHECK(db.ZoneFollow == true and W.card.name:GetText() == "Hellfire Peninsula",
        "Q: /cql zone opens on the zone you stand in, following you")
    WipeLog()
    SlashCmdList["COMMANDERUI_QUESTLOG"]("status")
    CHECK(Logged("Questie: READY") ~= nil, "Q: /cql status prints the adapter's lines", printLog[2])

    -- Questie still loading
    local realState = A.State
    A.State = function() return "LOADING", "Questie is still loading" end
    Q.Refresh()
    CHECK(W.emptyFS:IsShown() and (W.emptyFS:GetText() or ""):find("still loading", 1, true),
        "Q: while Questie loads, the navigator says so")
    A.State = realState

    -- The setting: no Zones tab means the Log, and no tabs at all
    db.ShowZoneTab = false
    Commander.Notify(COMMANDER_QUESTLOG_EVENTS.UPDATE)
    CHECK(Q.ViewMode() == "LOG" and window.trackBtn:IsShown() and not W.card:IsShown(),
        "Q: switching the Zones tab off puts the window on the Log")
    CHECK(not W.tabs.ZONE:IsShown() and not W.tabs.LOG:IsShown(), "Q: ...and takes both tabs away")
    db.ShowZoneTab = true
    Commander.Notify(COMMANDER_QUESTLOG_EVENTS.UPDATE)
    CHECK(Q.ViewMode() == "ZONE" and W.card:IsShown() and W.tabs.ZONE:IsShown(),
        "Q: ...and on again, back where it was")

    CHECK(#fake.forbidden == 0 and #fake.styleErrors == 0 and fake.returnTextMissing == 0,
        "Q: nothing reached a Questie call the adapter must never make",
        table.concat(fake.forbidden, ",") .. table.concat(fake.styleErrors, ","))
    db.ViewMode = "LOG"
    CommanderQuestLog_Hide()
end

-- ---------------------------------------------------------------------------
-- Q2: review fixes (2026-10-04) on the window
--
-- Each is a finding from the review that the checks above could not see:
-- the zone menu running off the screen, paper fills and the toolbar strip
-- vanishing on the parchment, labels losing their ink after a hover, titles
-- wrapping, Open in Log briefing the wrong quest, Restore Defaults leaving
-- the footer hidden, the status headings matching a search, the tabs sharing
-- a scroll offset, the card over the navigator with the module off, and
-- OpenToQuest leaving the window half-switched.
-- ---------------------------------------------------------------------------
do
    local Z, A = Q.Zones, Q.Questie
    local W = Z._Widgets()
    local window = _G.CommanderQuestLogFrame
    local function ZoneRow(title)
        for _, row in ipairs(W.rows) do
            if row:IsShown() and row.title:GetText() == title then return row end
        end
        return nil
    end
    local function NavPoint(which)
        for _, pt in ipairs(window.navPane.__points or {}) do
            if pt.point == which then return pt.y end
        end
        return nil
    end
    -- The parchment's own inks (UI.lua's INK.PARCHMENT), exactly
    local function IsInk(c, shade)
        local want = ({ faint = { 0.48, 0.40, 0.30 }, strong = { 0.36, 0.16, 0.02 } })[shade]
        return type(c) == "table" and math.abs(c[1] - want[1]) < 1e-6 and math.abs(c[2] - want[2]) < 1e-6
            and math.abs(c[3] - want[3]) < 1e-6
    end

    db.ViewMode = "ZONE"
    db.ZoneFollow = true
    CommanderQuestLog_Show()
    CHECK(window:IsShown() and Q.ViewMode() == "ZONE", "Q2: the window is up on the Zones tab")

    -- The zone menu: a long category is cut into pages a screen can hold,
    -- and a category row stays open when clicked rather than hovered
    local realMenu, realAdd = A.ZoneMenu, UIDropDownMenu_AddButton
    local many = {}
    for i = 1, 32 do
        many[i] = { areaId = 5000 + i, name = string.char(64 + math.ceil(i * 26 / 32)) .. " Dungeon " .. i }
    end
    A.ZoneMenu = function()
        return { { key = 3, text = "Outland", zones = { { areaId = 3483, name = "Hellfire Peninsula" } } },
                 { key = 9, text = "Dungeons", zones = many } }
    end
    local added = {}
    UIDropDownMenu_AddButton = function(info) added[#added + 1] = info end
    W.menu.__init(W.menu, 1)
    local pages, categories, kept = {}, 0, true
    for _, info in ipairs(added) do
        if info.hasArrow then
            categories = categories + 1
            if not info.keepShownOnClick then kept = false end
        end
        if type(info.menuList) == "table" and info.menuList.key == 9 then pages[#pages + 1] = info end
    end
    CHECK(#pages == 2 and pages[1].text == "Dungeons  A-M" and pages[2].text == "Dungeons  N-Z",
        "Q2: 32 dungeons become two pages, each named by its first letters",
        (pages[1] and pages[1].text or "-") .. " | " .. (pages[2] and pages[2].text or "-"))
    CHECK(categories == 3 and kept, "Q2: every category row keeps the menu open when clicked")
    local outland
    for _, info in ipairs(added) do if info.text == "Outland" then outland = info end end
    CHECK(outland and outland.menuList == 3, "Q2: a short category is still one row")
    local most = 0
    for _, page in ipairs(pages) do
        added = {}
        W.menu.__init(W.menu, 2, page.menuList)
        if #added > most then most = #added end
    end
    CHECK(most == 16, "Q2: each page holds 16 rows, under the 20 a 768-unit screen fits", most)
    added = {}
    W.menu.__init(W.menu, 2, pages[2] and pages[2].menuList)
    CHECK(added[1] and added[1].arg1 == 5017 and added[16] and added[16].arg1 == 5032,
        "Q2: ...the second page runs on from the first")

    -- (round 2) The real Dungeons list: an even cut falls inside the R's
    -- (Ragefire | Razorfen), and two pages both claiming R tell the player
    -- nothing. The cut moves to the nearest change of letter. And a name's
    -- first character is a whole UTF-8 sequence, not a lead byte on its own.
    local function Pages(names)
        local list = {}
        for i, name in ipairs(names) do list[i] = { areaId = 6000 + i, name = name } end
        A.ZoneMenu = function() return { { key = 9, text = "Dungeons", zones = list } } end
        added = {}
        W.menu.__init(W.menu, 1)
        local out = {}
        for _, info in ipairs(added) do
            if type(info.menuList) == "table" then
                out[#out + 1] = { text = info.text, size = info.menuList.last - info.menuList.first + 1 }
            end
        end
        return out
    end
    local function ValidUTF8(text)
        local i, n = 1, #text
        while i <= n do
            local c = text:byte(i)
            local len = (c < 0x80 and 1) or (c >= 0xC2 and c <= 0xDF and 2) or (c >= 0xE0 and c <= 0xEF and 3)
                or (c >= 0xF0 and c <= 0xF4 and 4) or nil
            if not len or i + len - 1 > n then return false end
            for j = i + 1, i + len - 1 do
                local b = text:byte(j)
                if b < 0x80 or b > 0xBF then return false end
            end
            i = i + len
        end
        return true
    end
    local real = Pages({ "Ahn'Qiraj", "Auchindoun", "Blackfathom Deeps", "Blackrock Depths", "Blackrock Spire",
        "Blackwing Lair", "Caverns of Time", "Dire Maul", "Gnomeregan", "Hellfire Citadel", "Karazhan",
        "Magtheridon's Lair", "Maraudon", "Molten Core", "Naxxramas", "Onyxia's Lair", "Ragefire Chasm",
        "Razorfen Downs", "Razorfen Kraul", "Ruins of Ahn'Qiraj", "Scarlet Monastery", "Scholomance",
        "Serpentshrine Cavern", "Shadowfang Keep", "Stratholme", "Tempest Keep", "The Slave Pens", "The Steamvault",
        "The Temple of Atal'Hakkar", "The Underbog", "Uldaman", "Wailing Caverns", "Zul'Farrak", "Zul'Gurub" })
    CHECK(#real == 2 and real[1].text == "Dungeons  A-O" and real[2].text == "Dungeons  R-Z"
        and real[1].size == 16 and real[2].size == 18,
        "Q2: the real 34 dungeons cut where the letter changes, A-O and R-Z, no letter on two pages",
        (real[1] and real[1].text .. " " .. real[1].size or "-") .. " | " .. (real[2] and real[2].text .. " " .. real[2].size or "-"))
    local german = {}
    for i = 1, 21 do german[i] = string.char(64 + i) .. "-Gebiet" end
    german[22], german[23] = "\195\150dland", "\195\150stliche Pestl\195\164nder"
    local de = Pages(german)
    CHECK(#de == 2 and ValidUTF8(de[1].text) and ValidUTF8(de[2].text) and de[2].text:sub(-2) == "\195\150",
        "Q2: a non-ASCII initial is a whole character in the page label (deDE)", de[2] and de[2].text)
    local same = {}
    for i = 1, 25 do same[i] = string.format("S%02d", i) end
    local runs = Pages(same)
    CHECK(#runs == 2 and runs[1].text == "Dungeons  S-S (1/2)" and runs[2].text == "Dungeons  S-S (2/2)",
        "Q2: one letter longer than a page is numbered, so the two rows still differ", runs[1] and runs[1].text)
    A.ZoneMenu, UIDropDownMenu_AddButton = realMenu, realAdd
    for _ = 1, 3 do RunTimers(1) end

    -- The zone search matches names, not the status headings
    local box = window.searchBox
    box:SetText("pick")
    box:GetScript("OnTextChanged")(box, true)
    CHECK(W.countFS:GetText() == "0 shown",
        "Q2: \"pick\" matches no quest name, so the Pick up now group is not listed", W.countFS:GetText())
    box:SetText("done")
    box:GetScript("OnTextChanged")(box, true)
    CHECK(W.countFS:GetText() == "0 shown", "Q2: ...and \"done\" does not list the Done group", W.countFS:GetText())
    box:GetScript("OnEscapePressed")(box)
    CHECK(W.countFS:GetText() == "25 shown", "Q2: Escape brings the list back", W.countFS:GetText())
    local tipBox = box.__scripts.OnEnter
    if tipBox then tipBox(box) end
    CHECK(table.concat(GameTooltip.__lines, " | "):find("in the zone on the card", 1, true),
        "Q2: the search box's tooltip says what the Zones search matches", table.concat(GameTooltip.__lines, " | "))

    -- Titles never wrap into the next row
    CHECK(ZoneRow("Know Your Enemy") and ZoneRow("Know Your Enemy").title.__wordWrap == false,
        "Q2: a zone row's title is one line")

    -- Each tab opens at its top
    local navScroll, detailScroll = Q._kit.NavScroll(), Q._kit.DetailScroll()
    navScroll:SetVerticalScroll(120)
    detailScroll:SetVerticalScroll(80)
    W.tabs.LOG:GetScript("OnClick")(W.tabs.LOG)
    CHECK(navScroll:GetVerticalScroll() == 0 and detailScroll:GetVerticalScroll() == 0,
        "Q2: switching tabs does not carry the other tab's scroll offset")
    local logRow = Q._NavRows()[2]
    CHECK(logRow and logRow.title.__wordWrap == false, "Q2: the Log's row titles are one line too")

    -- Ink on paper: fills, the toolbar strip, and labels after a hover
    OpenAs("PARCHMENT")
    CHECK(window.toolbarBg.__color and window.toolbarBg.__color[4] <= 0.2,
        "Q2: on paper the toolbar strip is a thin wash, not 45% black", window.toolbarBg.__color and window.toolbarBg.__color[4])
    Q.Select("Force Commander Danath")
    local danathRow = RowByTitle("Force Commander Danath")
    CHECK(danathRow and danathRow.selection:IsShown() and Lum(danathRow.selection.__color) <= INK_MAX,
        "Q2: the Log's selection band is ink on paper, not white on cream",
        danathRow and tostring(Lum(danathRow.selection.__color)))
    HoverButton(window.filters.ACTIVE)
    CHECK(not IsInk(window.filters.ACTIVE:GetFontString().__color, "faint"),
        "Q2: (a hover leaves the font's own grey on a Log filter)")
    RunTimers(0.01)
    CHECK(IsInk(window.filters.ACTIVE:GetFontString().__color, "faint"),
        "Q2: ...and the ink goes back on after the hover")
    W.tabs.ZONE:GetScript("OnClick")(W.tabs.ZONE)
    Z.Select(9004)
    local legion = ZoneRow("The Legion Reborn")
    CHECK(legion and legion.selection:IsShown() and Lum(legion.selection.__color) <= INK_MAX,
        "Q2: the Zones row selection is ink on paper", legion and tostring(Lum(legion.selection.__color)))
    CHECK(W.bands[1] and W.bands[1]:IsShown() and Lum(W.bands[1].__color) <= INK_MAX,
        "Q2: so is the chain's current-quest band")
    CHECK(Lum(W.tabs.ZONE.underline.__color) <= INK_MAX and W.tabs.ZONE.underline.__color[4] > 0.5,
        "Q2: and the active tab's underline")
    local pale = 0
    for _, quad in ipairs(W.quads) do
        if quad:IsShown() and quad.__color and Lum(quad.__color) > INK_MAX then pale = pale + 1 end
    end
    CHECK(pale == 0, "Q2: no quad on the briefing is a pale fill on paper", pale)
    HoverButton(W.tabs.ZONE)
    CHECK(not IsInk(W.tabs.ZONE:GetFontString().__color, "strong"), "Q2: (a hover leaves gold on the active tab)")
    RunTimers(0.01)
    CHECK(IsInk(W.tabs.ZONE:GetFontString().__color, "strong"), "Q2: ...until its ink is put back")
    HoverButton(W.filters.OPEN)
    CHECK(not IsInk(W.filters.OPEN:GetFontString().__color, "faint"), "Q2: (and grey on a zone filter)")
    RunTimers(0.01)
    CHECK(IsInk(W.filters.OPEN:GetFontString().__color, "faint"), "Q2: the zone filters get their ink back too")

    -- (round 2) WHILE hovered: the highlight font's white over the pale wash
    -- reads at 1.6:1, so on paper the hovered label is ink as well
    for _, button in ipairs({ W.filters.LOCKED, W.tabs.LOG, window.filters.TRACKED }) do
        HoverIn(button)
        CHECK(IsInk(button:GetFontString().__color, "strong"), "Q2: on paper a hovered label is ink, not white",
            table.concat(button:GetFontString().__color, ","))
        RunTimers(0.01)
        CHECK(IsInk(button:GetFontString().__color, "strong"), "Q2: ...still ink a frame later, after the client's swap")
        HoverOut(button)
        RunTimers(0.01)
        CHECK(IsInk(button:GetFontString().__color, "faint"), "Q2: ...and its idle ink once the pointer leaves")
    end
    OpenAs("STONE")
    HoverIn(W.filters.LOCKED)
    RunTimers(0.01)
    local white = W.filters.LOCKED:GetFontString().__color
    CHECK(white and white[1] == 1 and white[2] == 1 and white[3] == 1, "Q2: off the paper the hover keeps the white")
    HoverOut(W.filters.LOCKED)
    RunTimers(0.01)
    CHECK(window.toolbarBg.__color and window.toolbarBg.__color[4] == 0.45 and window.toolbarBg.__color[1] == 0,
        "Q2: on stone the strip is the dark one it always was")
    Z.Select(nil)

    -- Open in Log reveals the quest whatever the Log's fold, filter or search
    W.tabs.LOG:GetScript("OnClick")(W.tabs.LOG)
    box:SetText("zzz")
    box:GetScript("OnTextChanged")(box, true)
    db.Collapsed["Hellfire Peninsula"] = true
    db.Filter = "COMPLETE"
    -- Twenty quests of another zone ahead of it, so 9003 is the last quest
    -- of a log longer than the navigator, and a navigator 200 tall (the mock
    -- lays nothing out, so the client's height is given here)
    local savedLog = log
    local padded = { Header("Blade's Edge Mountains") }
    for i = 1, 20 do
        padded[#padded + 1] = Quest({ title = "Errand " .. i, level = 64, questID = 9900 + i,
            objectives = { { text = "Thing: 0/1", finished = false } } })
    end
    for _, item in ipairs(savedLog) do padded[#padded + 1] = item end
    log = padded
    navScroll:SetHeight(200)
    W.tabs.ZONE:GetScript("OnClick")(W.tabs.ZONE)
    Z.Select(9003)
    W.logBtn:GetScript("OnClick")(W.logBtn)
    CHECK(Q.ViewMode() == "LOG" and Q.Selected() and Q.Selected().questID == 9003,
        "Q2: Open in Log briefs the quest even with its zone folded, the filter on Ready and a search typed",
        Q.Selected() and Q.Selected().title)
    CHECK(db.Collapsed["Hellfire Peninsula"] == nil and db.Filter == "ALL" and (box:GetText() or "") == "",
        "Q2: ...by unfolding the zone, opening the filter and clearing the search")

    -- (round 2) ...and its row is in view: the tab switch put the navigator
    -- at its top, and the row sits far below the fold
    local function RowTop(row)
        for _, pt in ipairs(row.__points or {}) do
            if pt.point == "TOPLEFT" then return -(pt.y or 0) end
        end
        return nil
    end
    local function SelectedLogRow()
        for _, row in ipairs(Q._NavRows()) do
            if row:IsShown() and row.entry and row.entry == Q.Selected() then return row end
        end
        return nil
    end
    local function InView(row, scroll)
        local top, offset = row and RowTop(row), scroll:GetVerticalScroll()
        return top ~= nil and top >= offset and top + row:GetHeight() <= offset + scroll:GetHeight(), top, offset
    end
    local logSel = SelectedLogRow()
    local seen, top, offset = InView(logSel, navScroll)
    CHECK(logSel and top > 200 and seen, "Q2: Open in Log scrolls the navigator to the quest's row",
        tostring(top) .. " at offset " .. tostring(offset))
    RunTimers(0.01)
    CHECK(InView(SelectedLogRow(), navScroll), "Q2: ...and it is still there a frame later")
    navScroll:SetVerticalScroll(0)
    Q.Refresh()
    CHECK(navScroll:GetVerticalScroll() == 0, "Q2: an ordinary refresh leaves the player's own scrolling alone")
    CommanderQuestLog_OpenToQuest(GetQuestLogIndexByID(9003))
    CHECK(Q.Selected() and Q.Selected().questID == 9003 and InView(SelectedLogRow(), navScroll),
        "Q2: a quest link (OpenToQuest) brings its row into view too", navScroll:GetVerticalScroll())
    navScroll:SetVerticalScroll(0)
    -- The Zones tab, asked for its last quest by the map drawer
    W.tabs.ZONE:GetScript("OnClick")(W.tabs.ZONE)
    Z.Select(nil)
    local lastId
    for _, row in ipairs(W.rows) do
        if row:IsShown() and row.entry then lastId = row.entry.id end
    end
    navScroll:SetVerticalScroll(0)
    CommanderQuestLog_OpenToZone(3483, lastId)
    local zoneSel
    for _, row in ipairs(W.rows) do
        if row:IsShown() and row.entry and row.entry.id == lastId then zoneSel = row end
    end
    local zoneSeen, zoneTop = InView(zoneSel, navScroll)
    CHECK(lastId and Z.Selected() and Z.Selected().id == lastId and zoneTop and zoneTop > 200 and zoneSeen,
        "Q2: the map drawer's way in (OpenToZone) brings the zone row into view", tostring(zoneTop))
    navScroll:SetVerticalScroll(0)
    navScroll.__h = nil
    Z.Select(nil)
    log = savedLog
    W.tabs.LOG:GetScript("OnClick")(W.tabs.LOG)

    -- The Zones tab with the module switched off but the window still open
    db.EnableQuestLog = false
    W.tabs.ZONE:GetScript("OnClick")(W.tabs.ZONE)
    CHECK(Q.ViewMode() == "ZONE" and W.card:IsShown() and NavPoint("TOPLEFT") == -8 - 50,
        "Q2: whatever draws the card moves the navigator under it", NavPoint("TOPLEFT"))
    db.EnableQuestLog = true

    -- A quest link onto a heading while the Zones tab is up: Show() on a shown
    -- window fires nothing, so the switch has to draw on its own
    CommanderQuestLog_OpenToQuest(1)
    CHECK(Q.ViewMode() == "LOG" and not W.card:IsShown() and window.trackBtn:IsShown()
        and W.tabs.LOG.underline.__color[4] > 0.5,
        "Q2: OpenToQuest on a heading leaves the window on the Log, not half-switched")

    -- Restore Defaults turns the reset footer back on: the footer and the
    -- navigator follow, with the window open and with it shut
    db.ShowResetTimers = false
    Q.AnchorNavPane()
    CHECK(not window.resets:IsShown() and NavPoint("BOTTOMLEFT") == 10 + 4, "Q2: footer off, navigator to the bottom")
    SlashCmdList["COMMANDERUI_QUESTLOG"]("reset")
    CHECK(db.ShowResetTimers == true and window.resets:IsShown() and NavPoint("BOTTOMLEFT") == 10 + 4 + 26 + 4,
        "Q2: Restore Defaults brings the footer back and shortens the navigator", NavPoint("BOTTOMLEFT"))
    db.ShowResetTimers = false
    Q.AnchorNavPane()
    CommanderQuestLog_Hide()
    SlashCmdList["COMMANDERUI_QUESTLOG"]("reset")
    CommanderQuestLog_Show()
    CHECK(window.resets:IsShown() and NavPoint("BOTTOMLEFT") == 10 + 4 + 26 + 4,
        "Q2: ...and a reset made with the window shut is picked up when it opens", NavPoint("BOTTOMLEFT"))
    RunTimers(1)

    CHECK(#fake.forbidden == 0, "Q2: nothing forbidden reached Questie", table.concat(fake.forbidden, ","))
    db.ViewMode = "LOG"
    CommanderQuestLog_Hide()
end

-- ---------------------------------------------------------------------------
-- R: the module with no Questie at all
--
-- A second load of every file, as a session without Questie would run it:
-- the window opens, the Log works, the Zones tab says Questie is not loaded,
-- and nothing errors.
-- ---------------------------------------------------------------------------
do
    fake.Uninstall()
    for event in pairs(eventRegistry) do eventRegistry[event] = nil end
    CommanderQuestLog = nil
    CommanderQuestLogChar = nil
    CommanderQuestLog_OpenToZone = nil
    db.ViewMode = "ZONE"
    for _, file in ipairs(MODULE_FILES) do Load(ADDONS .. "/Commander_QuestLog/" .. file) end
    Fire("ADDON_LOADED", "Commander_QuestLog")
    Fire("PLAYER_LOGIN")
    Q = CommanderQuestLog
    BuildLog()
    RunTimers(1)

    CHECK(Q.Questie.State() == "ABSENT", "R: with no Questie the adapter says ABSENT", Q.Questie.State())
    CHECK(type(CommanderQuestLogChar) == "table" and type(CommanderQuestLogChar.Ignored) == "table",
        "R: the per-character table is made at load")
    CommanderQuestLog_Show()
    local window = _G.CommanderQuestLogFrame
    CHECK(window:IsShown() and Q.ViewMode() == "ZONE", "R: the window opens, on the tab it was left on")
    local W = Q.Zones._Widgets()
    CHECK(W.emptyFS and W.emptyFS:IsShown()
        and (W.emptyFS:GetText() or ""):find("Questie is not loaded", 1, true),
        "R: the Zones tab says Questie is not loaded", W.emptyFS and W.emptyFS:GetText())
    CHECK(not W.mapBtn:IsEnabled() and not W.waypointBtn:IsEnabled(), "R: ...with its actions greyed out")
    Q.SetViewMode("LOG")
    CHECK(Q.Selected() ~= nil and Q.Selected().title == "Cleansing the Waters", "R: the Log works, briefing a quest")
    local rowsShown = 0
    for _, row in ipairs(Q._NavRows()) do if row:IsShown() then rowsShown = rowsShown + 1 end end
    -- Section L folded Zangarmarsh; the fold is saved data and survives the reload
    CHECK(rowsShown == 7, "R: ...the navigator as it was left, Zangarmarsh still folded", rowsShown)
    local turnIn = false
    for _, fs in ipairs(Q._DetailStrings()) do
        if fs:IsShown() and (fs:GetText() or ""):find("Turn in:", 1, true) then turnIn = true end
    end
    CHECK(not turnIn and not window.waypointBtn:IsEnabled(), "R: ...with no Turn in line and no Waypoint")
    CommanderQuestLog_OpenToZone()
    CHECK(Q.ViewMode() == "ZONE" and W.emptyFS:IsShown(), "R: OpenToZone still opens the Zones tab, honestly empty")
    SlashCmdList["COMMANDERUI_QUESTLOG"]("status")
    RunTimers(1)
    CHECK(#caughtErrors == 0, "R: no errors anywhere in a Questie-less session", caughtErrors[1])
    db.ViewMode = "LOG"
    CommanderQuestLog_Hide()
end

-- ---------------------------------------------------------------------------
-- N: the global footprint
-- ---------------------------------------------------------------------------
for _, name in ipairs({ "CommanderQuestLog_Toggle", "CommanderQuestLog_Show",
    "CommanderQuestLog_Hide", "CommanderQuestLog_FocusSearch", "CommanderQuestLog_OpenToQuest",
    "CommanderQuestLog_OpenToZone" }) do
    CHECK(type(_G[name]) == "function", "N: " .. name .. " is published")
end
CHECK(_G.BINDING_NAME_COMMANDERQUESTLOG_TOGGLE ~= nil, "N: the toggle binding is named")
CHECK(_G.BINDING_NAME_COMMANDERQUESTLOG_SEARCH ~= nil, "N: the search binding is named")

-- Bindings.xml is read as TEXT, because the client parses it and not Lua. A
-- double hyphen anywhere in a comment is illegal XML and voids the WHOLE
-- file, registering zero bindings with only a LUA_WARNING to say so.
local xml = assert(io.open(ADDONS .. "/Commander_QuestLog/Bindings.xml")):read("*a")
for comment in xml:gmatch("<!%-%-(.-)%-%->") do
    CHECK(not comment:find("%-%-"), "N: no double hyphen inside an XML comment")
end
local declared = 0
for name in xml:gmatch('<Binding name="([^"]+)"') do
    declared = declared + 1
    CHECK(_G["BINDING_NAME_" .. name] ~= nil, "N: " .. name .. " has a BINDING_NAME")
end
CHECK(declared == 2, "N: two bindings declared", declared)
for call in xml:gmatch("</?Binding[^>]*>%s*([%w_]+)%(") do
    CHECK(type(_G[call]) == "function", "N: Bindings.xml calls " .. call .. ", which exists")
end

CHECK(#caughtErrors == 0, "no errors across the run", caughtErrors[1])

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
