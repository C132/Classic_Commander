-- Commander Quest Log harness (luajit).
--
-- Loads the REAL shared framework (CommanderSettingsUI.lua, CommanderEvents.lua)
-- and all three Commander_QuestLog files under a permissive WoW mock, then
-- drives a whole session against a MUTABLE quest log: scanning it, searching
-- it, folding zones shut, tracking and abandoning, and turning a quest in
-- underneath the window while it is open.
--
--   luajit questlog_harness.lua
--
-- Mock notes worth keeping:
--   * The quest log is MUTABLE and its INDICES MOVE. That is the whole point:
--     every index bug this module can have is an index that went stale between
--     the row being drawn and the button being pressed, and a fixture whose
--     indices never move proves nothing.
--   * Show/Hide fire OnShow/OnHide, because the window does all its work in
--     OnShow and a mock that skipped it would test an empty frame.
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
        fn = function(s) s.__shown = true; FireScript(s, "OnShow") end
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
UISpecialFrames = {}
tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack

for _, name in ipairs({ "GameFontNormal", "GameFontNormalLarge", "GameFontNormalHuge",
    "GameFontNormalSmall", "GameFontHighlight", "GameFontHighlightSmall",
    "GameFontDisableSmall", "NumberFontNormal" }) do
    _G[name] = NewWidget("Font", name)
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

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
Load(ADDONS .. "/Commander_QuestLog/CommanderQuestLogDB.lua")
Load(ADDONS .. "/Commander_QuestLog/CommanderQuestLogModel.lua")
Load(ADDONS .. "/Commander_QuestLog/CommanderQuestLogUI.lua")
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
-- N: the global footprint
-- ---------------------------------------------------------------------------
for _, name in ipairs({ "CommanderQuestLog_Toggle", "CommanderQuestLog_Show",
    "CommanderQuestLog_Hide", "CommanderQuestLog_FocusSearch", "CommanderQuestLog_OpenToQuest" }) do
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
