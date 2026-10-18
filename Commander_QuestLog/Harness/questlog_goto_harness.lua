-- Commander Quest Log: "Go to" in the window (luajit). DECISIONS D45.
--
--     /opt/homebrew/bin/luajit Commander_QuestLog/Harness/questlog_goto_harness.lua
--     CQL_UI= / CQL_CATALOGUE= / CQL_ADAPTER=/path/copy.lua luajit ...   (a mutated copy)
--
-- Commander Orders 3.1 made a waypoint press one thing across the suite: the
-- suite's Go button (Commander.UI.GoButton, in Commander_Events), Orders'
-- GoTo underneath it, one set of words ("Go to <Thing>" alone, "Go" on a
-- row) and one set of gestures (click Go, Shift-click share, Ctrl-click copy
-- the /way line; a list row's Ctrl+Right-click). The window harness
-- (questlog_harness.lua) drives the window WITHOUT the Go button file, so its
-- 1.5.0 checks keep proving the plain-button path; this one loads it, on the
-- same client (questlog_mock.lua), over the fake Questie's GoWorld (quest 9005
-- with an objective of every kind) and a recording Commander Orders 3.1:
--
--   A  the window's Go buttons are the suite's: "Go to Turn-in" on the Log's
--      action bar, "Go" on the Zones tab's
--   B  the Log's briefing: a row Go on each objective Questie can place, none
--      on a finished one or a reputation goal; the line keeps room for it;
--      a click is GoTo under (QuestLog, "quest:<id>:<n>") with every spot,
--      lit "Going" for that objective only; Shift-click shares, Ctrl-click
--      copies the /way line
--   C  Go to Turn-in: the finisher with every spawn under "quest:<id>",
--      Orders' words, the quest's other keys dropped (one waypoint per quest)
--   D  the Log's rows: Ctrl+Right-click is Go to its turn-in, a plain
--      right-click still tracks, and the tooltip says so
--   E  the Zones tab: the "Go" action on the selected quest, a LEADS TO
--      row's Go to that quest's giver, and an in-log quest's objective Go
--   F  Orders turned off: every Go button greyed with Orders' reason
--   G  hygiene: no error, plain ASCII words, no global written

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then HERE = (os.getenv("PWD") or ".") .. "/" .. HERE end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local MODULE = ADDONS .. "/Commander_QuestLog/"

local mock = dofile(MODULE .. "Harness/questlog_mock.lua")
local Fake = dofile(MODULE .. "Harness/fake_questie.lua")
local CHECK, Done = mock.Checker()
local function EQ(got, want, label) CHECK(got == want, label, "got " .. tostring(got) .. ", want " .. tostring(want)) end
local function HAS(s, needle, label) CHECK(type(s) == "string" and s:find(needle, 1, true) ~= nil, label, s) end

-- The client's Enable / Disable as the real buttons have them (the mock's
-- are silent no-ops; the Go button greys itself out with them)
do
    local probe = mock.NewWidget("Button")
    local mt = getmetatable(probe)
    local index = mt.__index
    mt.__index = function(self, key)
        if key == "Enable" then return function(s) s.__enabled = true end end
        if key == "Disable" then return function(s) s.__enabled = false end end
        if key == "LockHighlight" then return function(s) s.__locked = true end end
        if key == "UnlockHighlight" then return function(s) s.__locked = false end end
        return index(self, key)
    end
end

-- Modifier keys, held by hand
local mods = { SHIFT = false, CTRL = false }
function IsShiftKeyDown() return mods.SHIFT end
function IsControlKeyDown() return mods.CTRL end

-- ===========================================================================
-- A recording Commander Orders 3.1: the API the Go buttons and the adapter
-- call, answering the way the real one does (GoTo merges opts into the
-- place; IsGoing matches the arrow's owner; one record per (source, key))
-- ===========================================================================
local O = { gone = {}, records = {}, order = {}, active = nil, available = true, copied = nil, shared = nil, removed = {} }
COMMANDER_ORDERS_EVENTS = { CHANGED = "COMMANDER_ORDERS_CHANGED", UPDATE = "COMMANDER_ORDERS_UPDATE" }
local function Changed() if Commander and Commander.Notify then Commander.Notify(COMMANDER_ORDERS_EVENTS.CHANGED) end end
CommanderOrders = {
    IsAvailable = function()
        if O.available then return true end
        return false, "disabled"
    end,
    Reason = function(why)
        if why == "disabled" then return "Commander Orders is turned off (/corder)" end
        return "Reason: " .. tostring(why)
    end,
    GoTo = function(target, opts)
        O.gone[#O.gone + 1] = { target = target, opts = opts }
        if not O.available then return nil, "disabled" end
        local s = {}
        for k, v in pairs(target) do s[k] = v end
        for _, f in ipairs({ "source", "key", "title", "icon", "note" }) do
            if opts[f] ~= nil then s[f] = opts[f] end
        end
        local id = tostring(s.source) .. "|" .. tostring(s.key)
        if not O.records[id] then O.order[#O.order + 1] = id end
        s.uid = "w" .. #O.order
        O.records[id] = s
        O.active = s
        Changed()
        return s.uid
    end,
    IsGoing = function(source, key)
        local a = O.active
        return a ~= nil and O.records[tostring(a.source) .. "|" .. tostring(a.key)] == a and a.source == source
            and (key == nil or a.key == key)
    end,
    PlaceFor = function(target)
        if type(target) == "table" and target.map then
            return { map = target.map, x = target.x, y = target.y, title = target.title }
        end
        return nil, "nowhere"
    end,
    FormatCoords = function(x, y) return string.format("%.1f, %.1f", x * 100, y * 100) end,
    WayLineFor = function(m, x, y, t)
        return string.format("/way #%d %.2f %.2f%s", m, x * 100, y * 100, t and (" " .. t) or "")
    end,
    CopyText = function(text) O.copied = text end,
    SharePoint = function(spec, channel) O.shared = { spec = spec, channel = channel } return true end,
    List = function(filter)
        local out = {}
        for _, id in ipairs(O.order) do
            local r = O.records[id]
            if r and (not filter or not filter.source or r.source == filter.source) then out[#out + 1] = r end
        end
        return out
    end,
    RemoveBy = function(source, key)
        local id = tostring(source) .. "|" .. tostring(key)
        if O.records[id] then
            O.records[id] = nil
            O.removed[#O.removed + 1] = key
            return 1
        end
        return 0
    end,
    Add = function() error("Orders 3.1: the Go path never calls Add") end,
    AddRoute = function() return "r1" end,
    RegisterResolver = function() return true end,
    Describe = function() return "Commander Orders arrow" end,
}
local function Rec(key) return O.records["QuestLog|" .. key] end
local function Keys()
    local out = {}
    for _, id in ipairs(O.order) do if O.records[id] then out[#out + 1] = O.records[id].key end end
    table.sort(out)
    return table.concat(out, ",")
end

-- ===========================================================================
-- Boot: the GoWorld, quest 9005 in the log with its six objectives
-- ===========================================================================
local world = Fake.GoWorld()
world.log[9005] = true
Fake.Install(world)
Fake.InstallClient(world)

mock.LoadFramework()
mock.Load(ADDONS .. "/Commander_Events/CommanderGoButton.lua")
local globalsBefore = {}
for key in pairs(_G) do globalsBefore[key] = true end
local FILES = { "CommanderQuestLogDB.lua", "CommanderQuestLogModel.lua", "CommanderQuestLogCompletion.lua",
    "CommanderQuestLogQuestie.lua", "CommanderQuestLogUI.lua", "CommanderQuestLogCatalogue.lua",
    "CommanderQuestLogZones.lua" }
local OVERRIDE = {
    ["CommanderQuestLogUI.lua"] = os.getenv("CQL_UI"), ["CommanderQuestLogCatalogue.lua"] = os.getenv("CQL_CATALOGUE"),
    ["CommanderQuestLogQuestie.lua"] = os.getenv("CQL_ADAPTER"),
}
for _, file in ipairs(FILES) do mock.Load(OVERRIDE[file] or (MODULE .. file)) end
mock.Login()

mock.state.log = {
    mock.Header("Hellfire Peninsula"),
    mock.Quest({ title = "Know Your Enemy", level = 61, questID = 9005,
        objectives = {
            { text = "Wanted Poster read: 0/1", finished = false },
            { text = "Patrol Sentry slain: 3/8", finished = false },
            { text = "Legion Missive: 1/1", finished = true },
            { text = "Honor Hold: Friendly", finished = false },
            { text = "Caza'rez slain: 0/1", finished = false },
            { text = "Scout the Legion front", finished = false },
        } }),
    mock.Quest({ title = "Force Commander Danath", level = 60, questID = 9003,
        objectives = { { text = "Report to Force Commander Danath: 0/1", finished = false } } }),
}
local function Settle() for _ = 1, 8 do mock.RunTimers(1) end end
Settle()

local Q = CommanderQuestLog
local A, Z = Q.Questie, Q.Zones
local kit = Q._kit
local db = CommanderQuestLogDB
CHECK(A.State() == "READY", "boot: the fake Questie is ready", A.State())

local function Tip(widget)
    local enter = widget:GetScript("OnEnter")
    if enter then enter(widget) end
    return table.concat(GameTooltip.__lines, " | ")
end
local function Click(button, how)
    mods.SHIFT, mods.CTRL = how == "SHIFT", how == "CTRL"
    button:GetScript("OnClick")(button, "LeftButton")
    mods.SHIFT, mods.CTRL = false, false
end
local function ShownGo(pool)
    local out = {}
    for _, b in ipairs(pool) do if b:IsShown() then out[#out + 1] = b end end
    return out
end
-- The Log's objective Go pool: the buttons parented to the briefing whose
-- label is a row Go's (the window keeps them; this finds them)
local function LogGo()
    local out = {}
    for _, f in ipairs(mock.allFrames) do
        if f.__kind == "Button" and f._lineOpts and f.__shown and f.__parent == kit.DetailChild()
            and f._lineOpts.target and f._lineOpts.key and f._lineOpts.key:find("^quest:9005:") then
            out[#out + 1] = f
        end
    end
    table.sort(out, function(a, b) return a._lineOpts.key < b._lineOpts.key end)
    return out
end

-- ===========================================================================
-- A. The window's Go buttons are the suite's
-- ===========================================================================
db.ViewMode = "LOG"
CommanderQuestLog_Show()
Q.Select("Know Your Enemy")
local window = CommanderQuestLogFrame
local turnIn = window.waypointBtn
CHECK(turnIn and turnIn._cqlGo == true, "A: the Log's turn-in button is Commander.UI.GoButton")
EQ(turnIn and turnIn.__text, "Go to Turn-in", "A: worded Go to Turn-in (a standalone button: Go to <Thing>)")
EQ(turnIn and turnIn.__w, 120, "A: wide enough for Going to Turn-in")
EQ(turnIn and turnIn:IsEnabled(), true, "A: live on a quest whose turn-in Questie knows")

-- ===========================================================================
-- B. The Log's briefing: a row Go per objective Questie can place
-- ===========================================================================
local gos = LogGo()
local keys = {}
for i, b in ipairs(gos) do keys[i] = b._lineOpts.key end
EQ(table.concat(keys, ","), "quest:9005:1,quest:9005:2,quest:9005:5,quest:9005:6",
    "B: Go on the poster, the sentries, Caza'rez and the trigger; none on the finished missive or the reputation goal")
for _, b in ipairs(gos) do
    EQ(b.__text, "Go", "B: each worded Go (a row button) " .. b._lineOpts.key)
    EQ(b.__w, kit.LINE_GO_W, "B: ...the row Go width " .. b._lineOpts.key)
end
local sentryGo = gos[2]
local p = sentryGo and sentryGo.__points[1]
CHECK(p and p.point == "TOPRIGHT" and p.rel == kit.DetailChild(), "B: at the briefing's right edge", p and p.point)
local sentryLine
for _, fs in ipairs(Q._DetailStrings()) do
    if fs:IsShown() and fs:GetText() and fs:GetText():find("Patrol Sentry slain", 1, true) then sentryLine = fs end
end
local plainLine
for _, fs in ipairs(Q._DetailStrings()) do
    if fs:IsShown() and fs:GetText() and fs:GetText():find("Legion Missive", 1, true) then plainLine = fs end
end
CHECK(sentryLine and plainLine and sentryLine.__w == plainLine.__w - kit.LINE_GO_W - 6,
    "B: an objective with a Go keeps room for it at the line's end", sentryLine and sentryLine.__w)
HAS(Tip(sentryGo), "Where Questie places Patrol Sentry (8 spots; the arrow takes the nearest).",
    "B: the tooltip says where it goes")
HAS(Tip(sentryGo), "Go to: Know Your Enemy: Patrol Sentry - Hellfire Peninsula", "B: ...and the Go button's own line")
Click(sentryGo)
local gone = O.gone[#O.gone]
EQ(gone and gone.opts.source, "QuestLog", "B: a click is GoTo: source QuestLog")
EQ(gone and gone.opts.key, "quest:9005:2", "B: ...keyed by the quest and the objective")
CHECK(gone and gone.target.alternatives and #gone.target.alternatives == 8, "B: ...with every spawn of the sentry")
EQ(gone and gone.target.title, "Know Your Enemy: Patrol Sentry", "B: ...titled quest: target")
EQ(sentryGo.__text, "Going", "B: lit Going while the arrow is on it")
EQ(gos[1].__text, "Go", "B: ...and only that objective's button")
EQ(turnIn.__text, "Go to Turn-in", "B: ...not the turn-in's")
Click(sentryGo, "SHIFT")
CHECK(O.shared and O.shared.channel == "CHAT" and O.shared.spec.title == "Know Your Enemy: Patrol Sentry",
    "B: Shift-click shares it in chat (Orders' SharePoint)")
Click(sentryGo, "CTRL")
HAS(O.copied, "/way #1944 ", "B: Ctrl-click copies its /way line")
Click(gos[3])
EQ(O.gone[#O.gone].target.map, 1944, "B: Caza'rez, only inside the Blood Furnace, goes to its entrance on Hellfire")
EQ(Keys(), "quest:9005:5", "B: and the quest still has one waypoint (the sentry Go was dropped)")

-- ===========================================================================
-- C. Go to Turn-in
-- ===========================================================================
Click(turnIn)
gone = O.gone[#O.gone]
EQ(gone.opts.key, "quest:9005", "C: the turn-in Go is keyed quest:<id>, as since 1.5.0")
EQ(gone.target.title, "Know Your Enemy (Sergeant Altumus)", "C: titled with the finisher")
EQ(Keys(), "quest:9005", "C: one waypoint per quest: the objective's is gone")
EQ(turnIn.__text, "Going to Turn-in", "C: lit Going to Turn-in")
EQ(LogGo()[3].__text, "Go", "C: and the objective goes back to Go")
HAS(Tip(turnIn), "Go to where this quest is handed in.", "C: the tooltip's own sentence")
HAS(Tip(turnIn), "Shift-click: share in chat. Ctrl-click: copy a /way line.", "C: ...and the gestures")

-- ===========================================================================
-- D. The Log's rows: Ctrl+Right-click is Go, a right-click still tracks
-- ===========================================================================
local danathRow
for _, row in ipairs(Q._NavRows()) do
    if row.__shown and row.entry and row.entry.questID == 9003 then danathRow = row end
end
CHECK(danathRow ~= nil, "D: (the Danath row)")
mods.CTRL = true
danathRow:GetScript("OnClick")(danathRow, "RightButton")
mods.CTRL = false
gone = O.gone[#O.gone]
EQ(gone.opts.key, "quest:9003", "D: Ctrl+Right-click goes to that quest's turn-in")
EQ(gone.target.title, "Force Commander Danath (Force Commander Danath)", "D: ...the finisher's")
EQ(Rec("quest:9005") ~= nil, true, "D: (another quest's waypoint is left alone)")
EQ(mock.state.watched["Force Commander Danath"], nil, "D: (Danath is not tracked) and the Go tracked nothing")
local nGone = #O.gone
danathRow:GetScript("OnClick")(danathRow, "RightButton")
EQ(#O.gone, nGone, "D: a plain right-click is no Go")
EQ(mock.state.watched["Force Commander Danath"], true, "D: ...it tracks, as it always has")
HAS(Tip(danathRow), "Ctrl+Right-click: Go (to where it is handed in).", "D: the row's tooltip names the gesture")
Q.Select("Force Commander Danath")
EQ(#LogGo(), 0, "D: briefing a quest with nothing to place puts the objective Go buttons away")
Q.Select("Know Your Enemy")
EQ(#LogGo(), 4, "D: (and back)")

-- ===========================================================================
-- E. The Zones tab
-- ===========================================================================
CommanderQuestLog_OpenToZone(3483)
local W = Z._Widgets()
CHECK(W.waypointBtn and W.waypointBtn._cqlGo == true, "E: the Zones tab's Go is the suite's")
EQ(W.waypointBtn.__text, "Go", "E: worded Go (it acts on the selected quest, like Track or Share)")
Z.Select(9033)
EQ(W.waypointBtn:IsEnabled(), true, "E: live on a quest Questie can place")
Click(W.waypointBtn)
gone = O.gone[#O.gone]
EQ(gone.opts.key, "quest:9033", "E: Go: the quest's own key")
CHECK(gone.target.alternatives and #gone.target.alternatives == 8, "E: ...with every spawn of its giver")
EQ(W.waypointBtn.__text, "Going", "E: lit")
Z.Select(nil)
EQ(W.waypointBtn:IsEnabled(), false, "E: greyed with nothing selected")
-- LEADS TO: the follow-up's Go to where it starts
Z.Select(9003)
local refGo
for _, b in ipairs(ShownGo(W.goLines)) do
    if b._lineOpts.key == "quest:9004" then refGo = b end
end
CHECK(refGo ~= nil, "E: LEADS TO The Legion Reborn carries a Go")
if refGo then
    Click(refGo)
    gone = O.gone[#O.gone]
    EQ(gone.target.title, "The Legion Reborn (Force Commander Danath)", "E: ...to where that quest starts")
    HAS(Tip(refGo), "Go to where this quest starts.", "E: ...and says so")
end
-- An in-log quest's objectives on the Zones tab: the same row Go
Z.Select(9005)
local zoneKeys, followUp = {}, false
for _, b in ipairs(ShownGo(W.goLines)) do
    local key = b._lineOpts.key
    if key:find("^quest:9005:") then zoneKeys[#zoneKeys + 1] = key end
    if key == "quest:9007" then followUp = true end
end
table.sort(zoneKeys)
EQ(table.concat(zoneKeys, ","), "quest:9005:1,quest:9005:2,quest:9005:5,quest:9005:6",
    "E: the Zones briefing's objectives carry the same Go as the Log's")
CHECK(followUp, "E: ...and its LEADS TO (Wanted: Worg Master Kruush) a Go to that quest's giver")
Z.Select(9033)
EQ(#ShownGo(W.goLines), 0, "E: a quest with nothing to place has none (the pool is put away)")

-- ===========================================================================
-- F. Orders turned off: greyed, with Orders' reason
-- ===========================================================================
O.available = false
Commander.Notify(COMMANDER_ORDERS_EVENTS.UPDATE)
EQ(W.waypointBtn:IsEnabled(), false, "F: the Zones Go greys out")
HAS(Tip(W.waypointBtn), "Commander Orders is turned off (/corder)", "F: ...saying why in Orders' words")
-- A greyed Go promises no press (2026-10-05 review): 2.5.6 delivers no
-- OnClick to a disabled Button, so neither the hover nor the module's own
-- line (read straight from the button's options, whatever the GoButton
-- chooses to show) says "a press says so"; the line names the row's gesture
local function OwnLine(button)
    local o = button and button._goOpts
    local fn = o and o.tooltip
    return type(fn) == "function" and fn(button) or fn
end
local function NoPress(s) return type(s) == "string" and not s:find("a press says so", 1, true) and not s:find("Goes to", 1, true) end
CHECK(NoPress(Tip(W.waypointBtn)), "F: the greyed Zones Go's tooltip promises no press", Tip(W.waypointBtn))
local zonesLine = OwnLine(W.waypointBtn)
CHECK(NoPress(zonesLine) and zonesLine:find("Greyed out while Commander Orders is turned off (/corder); right-clicking a row then says so in chat", 1, true),
    "F: ...its own line says the row's right-click answers in chat instead", zonesLine)
db.ViewMode = "LOG"
CommanderQuestLog_Show()
Q.Select("Know Your Enemy")
Q.Refresh()
EQ(turnIn:IsEnabled(), false, "F: Go to Turn-in too")
CHECK(NoPress(Tip(turnIn)), "F: the greyed Go to Turn-in's tooltip promises no press", Tip(turnIn))
local turnInLine = OwnLine(turnIn)
CHECK(NoPress(turnInLine) and turnInLine:find("Ctrl+Right-clicking a row in the list then says so in chat, with the place and its [Go] link", 1, true),
    "F: ...its own line says the row's Ctrl+Right-click answers in chat instead", turnInLine)
CHECK(LogGo()[1] and LogGo()[1]:IsEnabled() == false, "F: and the objective Go buttons")
O.available = true
Commander.Notify(COMMANDER_ORDERS_EVENTS.UPDATE)
Q.Refresh()
EQ(turnIn:IsEnabled(), true, "F: on again, live again")
HAS(OwnLine(turnIn), "Goes to the Commander Orders arrow", "F: ...and its line names the arrow again")

-- ===========================================================================
-- G. Hygiene
-- ===========================================================================
EQ(#mock.caughtErrors, 0, "G: no errors", mock.caughtErrors[1])
local function Plain(s) return type(s) == "string" and not s:find("[\128-\255]") end
CHECK(Plain(turnIn.__text) and Plain(W.waypointBtn.__text) and Plain(Tip(turnIn)) and Plain(Tip(sentryGo)),
    "G: the Go words are plain ASCII (no glyphs)")
local fresh = {}
for key in pairs(_G) do
    if not globalsBefore[key] and type(key) == "string" and not key:find("^CommanderQuestLog")
        and not key:find("^COMMANDER_QUESTLOG") and not key:find("^BINDING_") and not key:find("^SLASH_")
        and not key:find("^CommanderUI") then
        fresh[#fresh + 1] = key
    end
end
table.sort(fresh)
EQ(table.concat(fresh, ","), "", "G: no global written beyond the module's own")

Done()
