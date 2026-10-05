-- Commander Quest Log: the Reputations tab harness (luajit).
--
-- The window's third tab over Fake.RepWorld() -- real quest ids with
-- Questie's real reputation rows, a level-70 human paladin who pledged to
-- the Aldor -- with the REAL rules engine (CommanderQuestLogStanding.lua),
-- the REAL generated data (CommanderQuestLogReputationData.lua), the real
-- adapter, catalogue and window, on the shared client mock
-- (questlog_mock.lua). Every TOC file loads but the map drawer (its own
-- harness, and a world map this mock does not have) and the NPC quest
-- dialog (its own harness).
--
--   luajit Commander_QuestLog/Harness/questlog_reps_harness.lua
--
-- The client's Reputation pane is modelled here, because nothing else needs
-- it: a list of rows (headings that fold, factions under them) behind
-- GetNumFactions / GetFactionInfo, the watched faction behind
-- C_Reputation.GetWatchedFactionData, and SetWatchedFactionIndex /
-- ExpandFactionHeader recorded, so "Watch Faction never unfolds the pane"
-- is a real check. Mutation hook: CQL_REPS=/path/copy.lua loads a mutated
-- copy of the tab instead of the live file.

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"

local mock = dofile(ADDONS .. "/Commander_QuestLog/Harness/questlog_mock.lua")
local Fake = dofile(ADDONS .. "/Commander_QuestLog/Harness/fake_questie.lua")
local CHECK, Done, counts = mock.Checker()
local ST, RunTimers, Fire, Logged, WipeLog = mock.state, mock.RunTimers, mock.Fire, mock.Logged, mock.WipeLog
local printLog, caughtErrors = mock.printLog, mock.caughtErrors

-- ===========================================================================
-- The world, the client, the module
-- ===========================================================================

local world = Fake.RepWorld()
local fake = Fake.Install(world)
Fake.InstallClient(world)
-- The mock's player is the Log's level-62 warrior; this world is a level-70
-- human paladin, and the reputation client is forced over the mock's
Fake.InstallRepClient(world, { force = true })
UnitLevel = function() return world.player.level end
RAID_CLASS_COLORS.PALADIN = { r = 0.96, g = 0.55, b = 0.73 }

-- The game's reputation bar colours, as FrameXML defines them
FACTION_BAR_COLORS = {
    { r = 0.8, g = 0.3, b = 0.22 }, { r = 0.8, g = 0.3, b = 0.22 }, { r = 0.75, g = 0.27, b = 0 },
    { r = 0.9, g = 0.7, b = 0 }, { r = 0, g = 0.6, b = 0.1 }, { r = 0, g = 0.6, b = 0.1 },
    { r = 0, g = 0.6, b = 0.1 }, { r = 0, g = 0.6, b = 0.1 },
}

-- The Reputation pane: headings and the met factions under them, in the
-- client's order; a folded heading's factions are out of the index space
local pane = {
    watched = nil, setCalls = {}, expandCalls = 0,
    rows = {
        { header = true, name = "Outland", id = 980 },
        { id = 946 }, { id = 933 }, { id = 942 },
        { header = true, name = "Shattrath City", id = 936 },
        { id = 932 }, { id = 934 }, { id = 935 }, { id = 1011 },
        { header = true, name = "Alliance", id = 469 },
        { id = 72 }, { id = 47 }, { id = 54 }, { id = 69 }, { id = 930 },
        { header = true, name = "Other", id = 0 },
        { id = 21 }, { id = 369 }, { id = 470 }, { id = 577 }, { id = 87 },
        { id = 989 }, { id = 967 }, { id = 990 },
    },
}
local function PaneVisible()
    local out, folded = {}, false
    for _, row in ipairs(pane.rows) do
        if row.header then
            out[#out + 1] = row
            folded = row.collapsed and true or false
        elseif not folded and world.factions[row.id] then
            out[#out + 1] = row
        end
    end
    return out
end
function GetNumFactions() return #PaneVisible() end
function GetFactionInfo(index)
    local row = PaneVisible()[index]
    if not row then return nil end
    if row.header then
        return row.name, "", 4, 0, 0, 0, false, false, true, row.collapsed and true or false, false, false, false,
            row.id
    end
    local name = world.factions[row.id]
    return name, "", 4, 0, 3000, world.reps[row.id] or 0, false, false, false, false, true,
        pane.watched == row.id, false, row.id
end
function SetWatchedFactionIndex(index)
    pane.setCalls[#pane.setCalls + 1] = index
    local row = PaneVisible()[index]
    pane.watched = (row and not row.header) and row.id or nil
end
function ExpandFactionHeader() pane.expandCalls = pane.expandCalls + 1 end
C_Reputation = {
    GetWatchedFactionData = function()
        if not pane.watched then return nil end
        return { factionID = pane.watched, name = world.factions[pane.watched] or "" }
    end,
}


-- Saved variables left in a shape the module did not write: the fold table
-- is not a table, and the calibration store is not one either. Login puts
-- both right (A).
CommanderQuestLogDB = { RepCollapsed = "junk" }
CommanderQuestLogChar = { RepObserved = 5 }

mock.LoadFramework()
local files = mock.TocFiles({ "CommanderQuestLogMap.lua", "CommanderQuestLogQuestFrame.lua" })
local REPS_COPY = os.getenv("CQL_REPS")
-- The tab's file is loaded with a trap on new globals: it may publish none
-- (its two dropdowns are named frames, made on first use, not at load)
local newGlobals = {}
for _, file in ipairs(files) do
    if file == "CommanderQuestLogReputations.lua" then
        setmetatable(_G, { __newindex = function(t, key, value)
            newGlobals[#newGlobals + 1] = tostring(key)
            rawset(t, key, value)
        end })
        mock.Load(REPS_COPY or (ADDONS .. "/Commander_QuestLog/" .. file))
        setmetatable(_G, nil)
    else
        mock.Load(ADDONS .. "/Commander_QuestLog/" .. file)
    end
end
mock.Login()

local Q = CommanderQuestLog
local db = CommanderQuestLogDB
local A = Q.Questie
local R = Q.Standing
local kit = Q._kit
for _ = 1, 4 do RunTimers(1) end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Timers run, the generation steps, the window's queued pass draws
local function Settle(times)
    for _ = 1, (times or 3) do RunTimers(1) end
end

local REP = Q.Reps
local W, S = REP and REP._Widgets() or {}, REP and REP._State() or {}

local function Shown(list)
    local out = {}
    for _, fs in ipairs(list or {}) do
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

local function Blocks() return Shown(W.blocks) end

local function Row(title)
    for _, row in ipairs(W.rows or {}) do
        if row:IsShown() and row.title:GetText() == title then return row end
    end
    return nil
end

local function Headings()
    local out = {}
    for _, row in ipairs(W.rows or {}) do
        if row:IsShown() and row.headerTitle then out[#out + 1] = row.headerTitle end
    end
    return out
end

-- The quests under one heading, in order
local function Under(heading)
    local out, inside = {}, false
    for _, row in ipairs(W.rows or {}) do
        if row:IsShown() then
            if row.headerTitle then
                inside = row.headerTitle == heading
            elseif inside and row.entry then
                out[#out + 1] = row.entry.id
            end
        end
    end
    return out
end

local function BadgeOf(row)
    return row and row.badge and row.badge:IsShown() and row.badge:GetText() or nil
end

local function Same(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

local function Colour(widget)
    local c = widget and widget.__color
    return c and string.format("%.3f,%.3f,%.3f", c[1] or 0, c[2] or 0, c[3] or 0) or "-"
end

local function RGB(r, g, b) return string.format("%.3f,%.3f,%.3f", r, g, b) end

local function TipLines() return table.concat(GameTooltip.__lines, " | ") end

local function Open(factionId, questId)
    Q.OpenToTab("REP", factionId, questId)
    Settle()
    Q.Refresh()
end

local function Control(label)
    for _, f in ipairs(mock.allFrames) do
        if f.Text and f.Text.__text == label then return f end
        if f.__kind == "Button" and f.__text == label then return f end
    end
    return nil
end

local function SettingsPanel()
    for _, category in ipairs(mock.categories) do
        if category.__panel and category.__panel._key == "QuestLog" then return category.__panel end
    end
    return nil
end

-- Everything drawn in the tab, for the glyph sweep (O)
local drawn = {}
local function Sweep(tag)
    for _, text in ipairs(Blocks()) do drawn[#drawn + 1] = { tag, text } end
    for _, row in ipairs(W.rows or {}) do
        if row:IsShown() then
            drawn[#drawn + 1] = { tag, row.title:GetText() or "" }
            drawn[#drawn + 1] = { tag, row.state:GetText() or "" }
            if BadgeOf(row) then drawn[#drawn + 1] = { tag, BadgeOf(row) } end
        end
    end
    if W.card then
        for _, fs in ipairs({ W.card.name, W.card.totals, W.card.note }) do drawn[#drawn + 1] = { tag, fs:GetText() or "" } end
    end
    if W.emptyFS and W.emptyFS:IsShown() then drawn[#drawn + 1] = { tag, W.emptyFS:GetText() or "" } end
end

-- ===========================================================================
-- A. The tab, its settings and its slash command
-- ===========================================================================

CHECK(type(REP) == "table" and type(REP.Refresh) == "function" and REP.tab and REP.tab.id == "REP",
    "A: Q.Reps is a catalogue instance registered as REP")
local tabs = Q.Tabs()
CHECK(#tabs == 3 and tabs[1].id == "LOG" and tabs[2].id == "ZONE" and tabs[3].id == "REP",
    "A: the strip is Log, Zones, Reputations, in that order", #tabs)
CHECK(REP.tab.label == "Reputations" and REP.tab.width == 78 and REP.tab.order == 30,
    "A: the button says Reputations, 78 px wide, after the Zones tab")
CHECK(#newGlobals == 0, "A: loading the tab publishes no global", table.concat(newGlobals, ","))
local defaults = {
    ShowRepTab = true, RepFilter = "ALL", RepGroup = "GUIDE", RepFollow = true, RepPicked = false,
    RepIncludeClassic = true, ShowRepEverywhere = true, ZoneRowRep = true, RepInQuestDialog = true,
}
for key, value in pairs(defaults) do
    CHECK(db[key] == value, "A: default " .. key .. " = " .. tostring(value), tostring(db[key]))
end
CHECK(type(db.RepCollapsed) == "table" and next(db.RepCollapsed) == nil,
    "A: a fold table saved as something else is made a table at login", type(db.RepCollapsed))
CHECK(CommanderQuestLogChar.RepObserved == nil and type(CommanderQuestLogChar.Ignored) == "table",
    "A: a calibration store that is not a table is dropped, the ignore list made")
for _, label in ipairs({ "Reputations Tab", "Classic Factions in the Picker", "Reputation on Every Quest",
    "Reputation on Zone Rows", "Reputation in the Quest Dialog", "Open Reputations", "Zones Tab" }) do
    CHECK(Control(label) ~= nil, "A: the settings page has " .. label)
end
do
    local panel = SettingsPanel()
    db.ShowRepEverywhere = false
    if panel then panel:Refresh() end
    CHECK(Control("Reputation on Zone Rows").__enabled == false and Control("Reputation in the Quest Dialog").__enabled == false
        and Control("Reputations Tab").__enabled ~= false,
        "A: with reputation off everywhere, its two surfaces grey out; the tab does not")
    db.ShowRepEverywhere = true
    if panel then panel:Refresh() end
    CHECK(Control("Reputation on Zone Rows").__enabled == true, "A: ...and come back with it")
end
-- Restore Defaults: the options go back, the tab's folds stay
db.RepCollapsed["Done"] = true
db.RepGroup, db.RepIncludeClassic, db.ZoneRowRep, db.RepFollow, db.RepPicked = "BYZONE", false, false, false, 933
SlashCmdList["COMMANDERUI_QUESTLOG"]("reset")
CHECK(db.RepGroup == "GUIDE" and db.RepIncludeClassic == true and db.ZoneRowRep == true and db.RepFollow == true
    and db.RepPicked == false, "A: Restore Defaults puts the reputation options back")
CHECK(db.RepCollapsed["Done"] == true, "A: ...but the Reputations tab's folds survive it")
db.RepCollapsed["Done"] = nil
Settle()

-- ===========================================================================
-- B. Following, the index, the card
-- ===========================================================================

local buttons = Q.TabButtons()
CommanderQuestLog_Show()
buttons.REP:GetScript("OnClick")(buttons.REP)
CHECK(Q.ViewMode() == "REP" and db.ViewMode == "REP", "B: the tab button switches the window over")
CHECK(S.key == nil and W.emptyFS and W.emptyFS:IsShown()
    and (W.emptyFS:GetText() or ""):find("You watch no faction this tab lists", 1, true),
    "B: nothing watched and nothing in the log: the tab says what to do", W.emptyFS and W.emptyFS:GetText())
CHECK(W.card.name:GetText() == "Reputations" and W.card.note:GetText() == "You watch no faction. Click to pick one."
    and not W.card.bar:IsShown(), "B: ...under the tab's own title on the card", W.card.note:GetText())
CHECK(_G.CommanderQuestLogRepGroupDrop == W.groupDrop and _G.CommanderQuestLogRepMenu == W.menu
    and W.groupDrop ~= Q.Zones._Widgets().groupDrop, "B: the tab's two dropdowns are its own, named after its prefix")
CHECK(A.FactionIndexState() == "NONE", "B: no faction asked about yet: the index has not been read")
Sweep("empty")

-- A quest in the log that pays a faction: following lands on it
ST.log = { mock.Header("Shattrath City"), mock.Quest({ title = "Trial of the Naaru: Tenacity", level = 70, questID = 10886,
    objectives = { { text = "Heroic Shadow Labyrinth", finished = false } } }) }
Q.Refresh()
CHECK(S.key == 935 and S.followedBy == "LOG", "B: following, the faction your log pays most is shown (the Sha'tar)",
    tostring(S.key) .. " " .. tostring(S.followedBy))
CHECK(S.err == "INDEXING" and (W.emptyFS:GetText() or ""):find("Reading Questie's reputation rewards", 1, true)
    and (W.card.note:GetText() or ""):find("Reading Questie's reputation rewards", 1, true),
    "B: the first faction asked for starts the index, and the tab says it is reading", tostring(S.err))
CHECK(W.card.totals:GetText() == "Neutral 2,000 / 3,000", "B: ...the card has the standing even before the view",
    W.card.totals:GetText())
W.card:GetScript("OnEnter")(W.card)
CHECK(TipLines():find("this is the one your log's quests pay most", 1, true), "B: the card says why it shows this faction",
    TipLines())
Sweep("indexing")
Settle()
CHECK(A.FactionIndexState() == "READY" and S.err == nil and S.view ~= nil,
    "B: once the index is read, the generation step redraws the view", tostring(S.err))

-- Only a DIRECT gain makes a faction the log's: a quest whose biggest
-- effect is spillover (stubbed here) still follows the faction it pays
do
    local realEffects = A.RepEffects
    A.RepEffects = function(questId, ...)
        if questId == 99001 then
            return { { factionId = 935, delta = 100, kind = "DIRECT" }, { factionId = 932, delta = 300, kind = "SPILL" } }
        end
        return realEffects(questId, ...)
    end
    local saved = ST.log
    ST.log = { mock.Header("Shattrath City"), mock.Quest({ title = "A Stub", level = 70, questID = 99001 }) }
    Q.Refresh()
    CHECK(S.key == 935, "B: the log's faction is summed over direct gains, never spillover", S.key)
    A.RepEffects = realEffects
    ST.log = saved
    Q.Refresh()
end

-- The watched faction comes first -- when the tab can show it
pane.watched = 947
Q.Refresh()
CHECK(S.key == 935 and S.followedBy == "LOG", "B: the other side's faction watched is passed over")
pane.watched = 980
Q.Refresh()
CHECK(S.key == 935, "B: so is a heading (Outland)")
pane.watched = 933
Fire("UPDATE_FACTION")
Settle()
CHECK(S.key == 933 and S.followedBy == "WATCHED" and S.view ~= nil, "B: the faction you watch is followed (UPDATE_FACTION)",
    tostring(S.key))

-- The card
local span = kit.NAV_W - 16
CHECK(W.card.name:GetText() == "The Consortium" and W.card.totals:GetText() == "Neutral 2,200 / 3,000",
    "B: the card: the faction and its standing", W.card.totals:GetText())
CHECK(W.card.note:GetText() == "+1,375 in quests  \194\183  reaches Friendly",
    "B: ...and what is left in quests, and where it gets you", W.card.note:GetText())
CHECK(W.card.note.__wordWrap == false,
    "B: ...on one line, cut short rather than wrapped below the card onto the navigator")
CHECK(W.card.bar:IsShown() and math.abs((W.card.bar.__w or 0) - span * 2200 / 3000) < 0.01,
    "B: the bar is the standing's place in its rank", W.card.bar.__w)
CHECK(Colour(W.card.bar) == RGB(0.9, 0.7, 0), "B: ...in the game's own colour for Neutral", Colour(W.card.bar))
local namePoints = W.card.name.__points or {}
CHECK(#namePoints == 2 and namePoints[2].point == "RIGHT" and namePoints[2].rel == W.card.totals
    and namePoints[2].relPoint == "LEFT", "B: the name gives way to the standing beside it")
W.card:GetScript("OnEnter")(W.card)
local tip = TipLines()
CHECK(tip:find("Neutral 2,200 / 3,000", 1, true) and tip:find("+1,375 left in quests, which reach Friendly 575 / 6,000", 1, true)
    and tip:find("Following the faction you watch", 1, true), "B: the card's tooltip says it in full", tip)

-- The picker
do
    local added = {}
    local realAdd = UIDropDownMenu_AddButton
    UIDropDownMenu_AddButton = function(info, level) added[#added + 1] = { info = info, level = level } end
    W.menu.__init(W.menu, 1)
    local first = added[1] and added[1].info
    CHECK(first and first.text == "The faction I watch" and first.checked == true, "B: the menu starts with following")
    local groups = {}
    for i = 2, #added do groups[#groups + 1] = added[i].info.text end
    CHECK(groups[1] == "Outland" and groups[2] == "Shattrath City" and groups[3] == "Other (TBC)" and Has(groups, "Alliance")
        and not Has(groups, "Horde"), "B: ...then the factions' groups, TBC first, your side's", table.concat(groups, ","))
    local outland
    for i = 2, #added do if added[i].info.text == "Outland" then outland = added[i].info end end
    added = {}
    W.menu.__init(W.menu, 2, outland and outland.menuList)
    local texts, consortium = {}, nil
    for _, item in ipairs(added) do
        texts[#texts + 1] = item.info.text
        if item.info.arg1 == 933 then consortium = item.info end
    end
    CHECK(consortium and consortium.text:find("^The Consortium  Neutral") and consortium.func ~= nil
        and consortium.tooltipText == "Neutral  \194\183  12 quests  \194\183  2 not in this phase yet",
        "B: each faction says its standing, and its tooltip how many quests pay it",
        consortium and (consortium.text .. " / " .. tostring(consortium.tooltipText)))
    CHECK(not Has(texts, "Thrallmar"), "B: the other side's factions are never offered")
    added = {}
    db.RepIncludeClassic = false
    W.menu.__init(W.menu, 1)
    groups = {}
    for i = 2, #added do groups[#groups + 1] = added[i].info.text end
    CHECK(#groups == 3 and not Has(groups, "Alliance"), "B: Classic Factions off: the TBC groups alone",
        table.concat(groups, ","))
    db.RepIncludeClassic = true
    UIDropDownMenu_AddButton = realAdd
    REP._Context().Pick(nil, 946)
    CHECK(db.RepFollow == false and db.RepPicked == 946 and S.key == 946,
        "B: picking a faction pins it")
    CHECK(W.card.note:GetText() == "+385 in quests  \194\183  stays Friendly  \194\183  pinned",
        "B: ...and the card says it is pinned", W.card.note:GetText())
    W.card:GetScript("OnClick")(W.card, "RightButton")
    CHECK(db.RepFollow == true and db.RepPicked == false and S.key == 933, "B: right-click follows again")
end

-- ===========================================================================
-- C. Rows and groupings (the Consortium)
-- ===========================================================================

CHECK(Same(Headings(), { "Will lock soon", "Pick up now", "Repeatable sources", "Dailies" }),
    "C: the Guide: closing doors first, then what to pick up, then the sources", table.concat(Headings(), ","))
CHECK(Same(Under("Will lock soon"), { 9914, 9882 }), "C: Will lock soon: the soonest to close first (2,999, then 3,000)",
    table.concat(Under("Will lock soon"), ","))
CHECK(Same(Under("Pick up now"), { 10165, 9900 }), "C: Pick up now: the most reputation first",
    table.concat(Under("Pick up now"), ","))
CHECK(#Under("Dailies") == 6 and #Under("Repeatable sources") == 2,
    "C: repeatables and dailies are sources, in groups of their own")
local undercut = Row("Undercutting the Competition")
CHECK(BadgeOf(undercut) == "+550" and BadgeOf(Row("Gava'xi")) == "+275", "C: each row carries what it pays (a Human: 500 is +550)",
    BadgeOf(undercut))
CHECK(Colour(undercut.badge) == RGB(kit.Paper(kit.Accent())), "C: ...in the accent, on the paper like every colour",
    Colour(undercut.badge))
CHECK(Row("More Crystal Fragments").state:GetText() == "open", "C: a repeatable you can do reads open, not daily")
CHECK(Row("Wanted: Coilfang Myrmidons").state:GetText() == "today", "C: a daily you can do reads today")
local wanted = Row("Wanted: Coilfang Myrmidons")
wanted:GetScript("OnEnter")(wanted)
CHECK(TipLines():find("A Wanted daily: +275, on the days it is offered (one normal and one heroic a day, in rotation); not counted here.", 1, true),
    "C: a Wanted daily's reason says it is one of a rotation", TipLines())
local crystals = Row("More Crystal Fragments")
crystals:GetScript("OnEnter")(crystals)
CHECK(TipLines():find("A repeatable source: +275 a turn-in, 3 turn-ins to Friendly. Not counted here.", 1, true),
    "C: a repeatable's reason says it is a source, not part of a count", TipLines())
local ivory = Row("A Head Full of Ivory")
ivory:GetScript("OnEnter")(ivory)
tip = TipLines()
CHECK(tip:find("Reputation: +275 The Consortium", 1, true), "C: a row's tooltip carries the whole reputation line", tip)
-- Folding writes the tab's own table
local lock = Row("Will lock soon")
lock:GetScript("OnClick")(lock, "LeftButton")
CHECK(db.RepCollapsed["Will lock soon"] == true and (db.ZoneCollapsed or {})["Will lock soon"] == nil
    and (db.Collapsed or {})["Will lock soon"] == nil and Row("A Head Full of Ivory") == nil,
    "C: folding a group writes RepCollapsed, never the Zones tab's or the Log's")
Row("Will lock soon"):GetScript("OnClick")(Row("Will lock soon"), "LeftButton")
CHECK(Row("A Head Full of Ivory") ~= nil, "C: ...and unfolds")
-- The dropdown and the other groupings
do
    local added = {}
    local realAdd = UIDropDownMenu_AddButton
    UIDropDownMenu_AddButton = function(info) added[#added + 1] = info.text end
    W.groupDrop.__init(W.groupDrop)
    UIDropDownMenu_AddButton = realAdd
    CHECK(Same(added, { "Guide", "By zone", "By value", "By status", "By chain" }), "C: five ways to group",
        table.concat(added, ","))
end
db.RepGroup = "BYZONE"
Q.Refresh()
CHECK(Same(Headings(), { "Auchindoun", "Coilfang Reservoir", "Hellfire Citadel", "Nagrand" }),
    "C: By zone: one heading per zone the quests are filed under", table.concat(Headings(), ","))
CHECK(Same(Under("Nagrand"), { 9914, 9882, 10165, 9900, 9883, 9915 }),
    "C: ...each zone's own quests under it, the counted ones first, each part by level",
    table.concat(Under("Nagrand"), ","))
db.RepGroup = "BYVALUE"
Q.Refresh()
CHECK(Same(Headings(), { "+550", "+275", "Repeatable sources", "Dailies" }),
    "C: By value: what is still to gain, the biggest first; then the sources", table.concat(Headings(), ","))
CHECK(Same(Under("+275"), { 9914, 9882, 9900 }) and Same(Under("+550"), { 10165 }),
    "C: ...each value's quests by level", table.concat(Under("+275"), ","))
db.RepGroup = "STATUS"
Q.Refresh()
CHECK(Has(Headings(), "Available") and Has(Headings(), "Dailies and repeatables"),
    "C: By status is the engine's", table.concat(Headings(), ","))
db.RepGroup = "CHAIN"
Q.Refresh()
CHECK(Has(Headings(), "Standalone quests"), "C: By chain is the engine's", table.concat(Headings(), ","))
db.RepGroup = "GUIDE"
Q.Refresh()
Sweep("consortium rows")

-- ===========================================================================
-- D. The overview (the Consortium)
-- ===========================================================================

local brief = Blocks()
CHECK(brief[1] == "The Consortium" and brief[2] == "Neutral 2,200 / 3,000", "D: the standing block heads it", brief[2])
CHECK(Has(brief, "800 to Friendly  \194\183  39,800 to Exalted"), "D: what is left to the next standing and to Exalted")
CHECK(Has(brief, "Every gain is paid at 110%: Diplomacy."), "D: the multiplier and why")
CHECK(Has(brief, "4 quests left: worth 1,375 in the best order") and Has(brief, "Quests alone reach Friendly 575 / 6,000."),
    "D: QUESTS: what is left, in the best order, and where it gets you")
CHECK(Has(brief, "WILL LOCK SOON") and Has(brief, "Do \"A Head Full of Ivory\" before Friendly")
    and Has(brief, "Do \"Stealing from Thieves\" before Friendly"), "D: the quests to do before their door shuts")
CHECK(Has(brief, "REPEATABLE SOURCES") and Has(brief, "More Crystal Fragments  +275 a turn-in")
    and Has(brief, "3 turn-ins to Friendly  \194\183  offered only below Friendly  \194\183  item 25416 x10 a turn-in (30 to Friendly)"),
    "D: a repeatable: turn-ins to the next standing, where it stops, what it costs", Has(brief, "turn-ins to Friendly"))
-- An item name the client did not have arrives later: the overview redraws
world.itemCache[25416] = "Oshu'gun Crystal Fragment"
Fire("GET_ITEM_INFO_RECEIVED", 25416, true)
RunTimers(0.1)        -- the window's queued pass, and nothing else
brief = Blocks()
CHECK(Has(brief, "Oshu'gun Crystal Fragment x10 a turn-in (30 to Friendly)") and not Has(brief, " each"),
    "D: ...and the item's name once the client has it (the count after it: an item name is never pluralised by hand)",
    Has(brief, "Crystal"))
CHECK(Has(brief, "DAILIES") and Has(brief, "+275 a day from 1 daily (the game allows 25 dailies a day)"),
    "D: DAILIES: what a day is worth, held to the game's cap")
CHECK(Has(brief, "Wanted (normal): today's is Wanted: Coilfang Myrmidons, +275")
    and Has(brief, "Wanted (heroic): 3 in the rotation pay it, up to +385 on a day one of them is offered; today's not known yet")
    and not Has(brief, "one of 3 a day"),
    "D: the Wanted dailies: today's when Questie knows it, never summed, never \"one of N a day\"")
CHECK(Has(brief, "NOT IN THIS PHASE") and Has(brief, "2 quests that would pay the Consortium come with a later content phase"),
    "D: the quests a later phase holds back are counted, not dropped")
CHECK(Has(brief, "CALIBRATION") and Has(brief, "None of these seen in game yet"), "D: and whether any was seen in game")
Sweep("consortium overview")

-- A quest's briefing
REP.Select(9914)
brief = Blocks()
CHECK(brief[1] == "A Head Full of Ivory" and brief[2] == "Level 66  \194\183  requires 64  \194\183  Nagrand",
    "D: a quest: its facts are its level and its own zone (the faction is on the card)", brief[2])
CHECK(Has(brief, "REPUTATION") and Has(brief, "+275 The Consortium") and Has(brief, "Paid at 110% (Diplomacy)."),
    "D: ...its REPUTATION section, in the Zones tab's words")
CHECK(Has(brief, "Do it before Friendly: it is offered only below 2,999."), "D: ...and when its door shuts")
Sweep("9914")
REP.Select(nil)

-- The Wickerman: every number moves with the buff, read at the time. (The
-- adapter hears UNIT_AURA through RegisterUnitEvent, which this mock's
-- frames take silently, so the generation is stepped here instead.)
fake.SetAura(24705, true)
A.Bump("aura")
Settle()
CHECK(BadgeOf(Row("Undercutting the Competition")) == "+600" and Has(Blocks(), "Every gain is paid at 120%: Diplomacy and Invocation of the Wickerman."),
    "D: under Invocation of the Wickerman a Human is paid 120%", BadgeOf(Row("Undercutting the Competition")))
fake.SetAura(24705, false)
A.Bump("aura")
Settle()
CHECK(BadgeOf(Row("Undercutting the Competition")) == "+550", "D: ...and 110% again when it goes")

-- What the game was seen to pay overrides the data, everywhere, and says so
CommanderQuestLogChar.RepObserved = { [9900] = { [933] = { raw = 300, n = 1, delta = 330, pct = 110, kind = "DIRECT" } } }
A.Bump("calibration")
Settle()
CHECK(BadgeOf(Row("Gava'xi")) == "+330" and Has(Blocks(), "Seen in game on 1 quest: those numbers are what the game paid you"),
    "D: a quest seen in game shows what the game paid, and the overview counts it", BadgeOf(Row("Gava'xi")))
REP.Select(9900)
CHECK(Has(Blocks(), "+330 The Consortium  \194\183  seen in game"), "D: ...its briefing marks the number as seen in game")
local gava = Row("Gava'xi")
gava:GetScript("OnEnter")(gava)
CHECK(TipLines():find("Seen in game: what the game paid you", 1, true), "D: ...and so does its row's tooltip", TipLines())
REP.Select(nil)
CommanderQuestLogChar.RepObserved = nil
A.Bump("calibration")
Settle()

-- ===========================================================================
-- E. The Sha'tar: the spill window, a quest in the log
-- ===========================================================================

Open(935)
local via = "Via Aldor/Scryers (until Honored)"
CHECK(Same(Headings(), { "In progress", "Done", via }), "E: the Sha'tar: its own quests, then the window's",
    table.concat(Headings(), ","))
CHECK(#Under(via) == 10, "E: ...the Aldor's and the Scryers' quests that spill into it", #Under(via))
local zahlia = Row("A Cure for Zahlia")
CHECK(BadgeOf(zahlia) == "+192" and Colour(zahlia.title) == RGB(kit.Paper(kit.Ink("faint"))),
    "E: a window quest shows the spill it pays (half of +385), and is not counted", BadgeOf(zahlia))
CHECK(Row("Single Firewing Signet").state:GetText() == "rival", "E: a rival repeatable reads rival, not daily",
    Row("Single Firewing Signet").state:GetText())
zahlia:GetScript("OnEnter")(zahlia)
tip = TipLines()
CHECK(tip:find("Pays the Sha'tar only as spillover: half of what it pays the Aldor, while the Sha'tar is Friendly or below", 1, true),
    "E: its reason says how it pays", tip)
brief = Blocks()
CHECK(Has(brief, "1 quest left, and 2 more by spillover: worth 879 in the best order"),
    "E: QUESTS counts the spill quests the projection counts", Has(brief, "left"))
CHECK(Has(brief, "VIA SPILLOVER") and Has(brief, "From the Aldor's quests: half of each, while the Sha'tar is Friendly or below")
    and Has(brief, "2 quests and 3 repeatables still to do; in the best order about +329 lands from the quests before it stops at 8,999."),
    "E: VIA SPILLOVER: the window, what is left in it, what lands", Has(brief, "still to do"))
CHECK(not Has(brief, "Scryers' quests"), "E: ...and not the side you did not pick, with nothing left in it")
CHECK(BadgeOf(Row("Trial of the Naaru: Tenacity")) == "+550" and Row("Trial of the Naaru: Tenacity").state:GetText() == "log",
    "E: the quest in the log is In progress")
Sweep("shatar")
-- Past Friendly the window is shut: no Via group, one line saying so
fake.SetRep(935, 9500)
Fire("UPDATE_FACTION")
Settle()
CHECK(not Has(Headings(), "Via") and Has(Blocks(), "Spillover from the Aldor and the Scryers has stopped")
    and Has(Blocks(), "The Sha'tar is past Friendly, where that spillover ends."),
    "E: Honored with the Sha'tar: the window is shut and the overview says so", table.concat(Headings(), ","))
fake.SetRep(935, 2000)
Fire("UPDATE_FACTION")
Settle()

-- ===========================================================================
-- F. The Aldor: repeatables, costs, a quest's every effect, a cap
-- ===========================================================================

Open(932)
brief = Blocks()
CHECK(Has(brief, "Fel Armaments  +385 a turn-in")
    and Has(brief, "13 turn-ins to Honored  \194\183  99 to Exalted  \194\183  Fel Armament x1 a turn-in (13 to Honored)"),
    "F: a repeatable with no gate: to Honored, to Exalted, its cost (named from Questie's items)")
CHECK(Has(brief, "19 turn-ins, then it pays nothing past the top of Friendly  \194\183  Mark of Kil'jaeden x10 a turn-in"),
    "F: a repeatable with a reward clamp says where it stops paying")
CHECK(Has(brief, "Repeatables can carry it on to Exalted."), "F: QUESTS: and how far repeatables carry it")
CHECK(Has(brief, "COSTS") and Has(brief, "3 quests lower the Aldor (1 no longer open to you)")
    and Has(brief, "-302  Firewing Signets (pays the Scryers)"), "F: COSTS: the rival's quests, with what each takes")
CHECK(not Has(brief, "Allegiance to the Scryers"), "F: ...a choice already made against them is not listed as a cost")
local spied = {}
local realDetail = A.QuestDetail
A.QuestDetail = function(...)
    spied[#spied + 1] = { ... }
    return realDetail(...)
end
REP.Select(10326)
A.QuestDetail = realDetail
db.RepGroup = "BYVALUE"
Q.Refresh()
CHECK(Same(Headings(), { "+385", "+275", "Done", "Repeatable sources" }) and Same(Under("Done"), { 10551, 10021 }),
    "F: By value: what is still to gain by value, done quests apart (the biggest first)", table.concat(Headings(), ","))
db.RepGroup = "GUIDE"
Q.Refresh()
brief = Blocks()
CHECK(spied[1] and spied[1][1] == 10326 and spied[1][2] == 932 and spied[1][3] == "FACTION",
    "F: a quest's detail is read from the faction cache (faction ids collide with zones)",
    spied[1] and tostring(spied[1][3]))
CHECK(brief[2] == "Level 65  \194\183  requires 62  \194\183  Shattrath City  \194\183  repeatable  \194\183  not counted",
    "F: a repeatable's facts say so", brief[2])
CHECK(Has(brief, "+275 The Aldor") and Has(brief, "-302 The Scryers  \194\183  rival")
    and Has(brief, "+137 The Sha'tar  \194\183  spillover"), "F: REPUTATION lists every effect: direct, the rival's loss, spillover")
CHECK(Has(brief, "AS A SOURCE") and Has(brief, "+275 a turn-in to the Aldor"), "F: ...and the quest as a source")
Sweep("10326")
-- At the top of Friendly the marks pay nothing: the row says so, dimmed
fake.SetRep(932, 8999)
Fire("UPDATE_FACTION")
Settle()
local marks = Row("More Marks of Kil'jaeden")
CHECK(BadgeOf(marks) == "0 capped" and Colour(marks.title) == RGB(kit.Paper(kit.Ink("faint"))),
    "F: capped at 8,999: the row reads 0 capped and dims", BadgeOf(marks))
REP.Select(10326)
CHECK(Has(Blocks(), "0 The Aldor  \194\183  this quest stops at 8,999"), "F: ...and the briefing says why",
    table.concat(Blocks(), " | "))
marks = Row("More Marks of Kil'jaeden")
marks:GetScript("OnEnter")(marks)
CHECK(TipLines():find("Capped: this quest stops at 8,999.", 1, true) and TipLines():find("Reputation: 0 The Aldor (capped)", 1, true),
    "F: ...and so does the row's tooltip", TipLines())
fake.SetRep(932, 4000)
Fire("UPDATE_FACTION")
Settle()
REP.Select(nil)

-- ===========================================================================
-- G. Honor Hold, Netherwing (not met), Stormwind (a capital)
-- ===========================================================================

Open(946)
brief = Blocks()
CHECK(Has(Headings(), "Dailies") and Row("Wanted: Nazan's Riding Crop") ~= nil and BadgeOf(Row("Wanted: Nazan's Riding Crop")) == "+385",
    "G: the audited Wanted dailies pay Honor Hold")
CHECK(Has(brief, "Hellfire Fortifications  +165") and Has(brief, "Wanted (normal): today's pays another faction"),
    "G: DAILIES: the steady one, and today's Wanted pick paying someone else")
local fortifications = Row("Hellfire Fortifications")
fortifications:GetScript("OnEnter")(fortifications)
CHECK(TipLines():find("A daily: +165 a turn-in, once a day; not counted here.", 1, true), "G: a daily's reason", TipLines())
Sweep("honor hold")
do
    -- At the ceiling (Exalted 999 / 1,000) the engine holds every daily and
    -- quest to 0: DAILIES is one line, never "None you can do today.", a
    -- Wanted pick blamed, or a list of zeros; QUESTS never says "worth 0"
    -- (2026-10-05 review)
    local before = world.reps[946]
    fake.SetRep(946, 42999)
    Fire("UPDATE_FACTION")
    Settle()
    Open(946)
    brief = Blocks()
    CHECK(Has(brief, "Exalted 999 / 1,000: dailies pay nothing more.") and not Has(brief, "None you can do today.")
        and not Has(brief, "Nothing to count on yet") and not Has(brief, "Hellfire Fortifications  0")
        and not Has(brief, "up to 0") and not Has(brief, "today's pays another faction"),
        "G: at the ceiling, today's Wanted known: DAILIES says nothing more is paid, in one line", table.concat(brief, " | "))
    CHECK(Has(brief, "2 quests left, none pays anything more") and not Has(brief, "worth 0") and Has(brief, "Already Exalted."),
        "G: ...and QUESTS: the quests left pay nothing more, never \"worth 0 in the best order\"")
    Sweep("honor hold ceiling")
    fake.ResetDailies()
    Fire("UPDATE_FACTION")
    Settle()
    Open(946)
    brief = Blocks()
    CHECK(Has(brief, "Exalted 999 / 1,000: dailies pay nothing more.") and not Has(brief, "Nothing to count on yet")
        and not Has(brief, "not known yet") and not Has(brief, "up to 0"),
        "G: ...today's Wanted not known: the pick is not blamed for a day that pays nothing whatever is offered",
        table.concat(brief, " | "))
    -- Just under it the day is held to the room left, and still counted
    fake.SetRep(946, 42900)
    Fire("UPDATE_FACTION")
    Settle()
    Open(946)
    brief = Blocks()
    CHECK(Has(brief, "+99 a day from 1 daily (the game allows 25 dailies a day)") and Has(brief, "Hellfire Fortifications  +99")
        and Has(brief, "up to +99 on a day one of them is offered") and Has(brief, "2 quests left: worth 99 in the best order"),
        "G: at Exalted 900 the dailies and quests are held to the 99 left, and said as before", table.concat(brief, " | "))
    -- Open dailies held to nothing below the ceiling (a reward clamp), and a
    -- Wanted pool none of which pays from here: never "up to 0" or a pick
    -- blamed (the engine's figures, as R.DailyIncome would hand them)
    local real = S.view.rep.dailies
    S.view.rep.dailies = { perDay = 0, count = 1, max = 25, steady = { { questId = 10106, gain = 0 } }, conditional = {},
        rotating = { HEROIC = { candidates = 3, best = 0 } } }
    Q.Refresh()
    brief = Blocks()
    CHECK(Has(brief, "None of today's pays anything more at your standing.") and not Has(brief, "Nothing to count on yet")
        and Has(brief, "Wanted (heroic): none in the rotation pays anything more at your standing") and not Has(brief, "up to 0"),
        "G: open dailies paying 0 below the ceiling say so; a pool that pays nothing is no reason to wait",
        table.concat(brief, " | "))
    S.view.rep.dailies = real
    -- The chain on this tab holds only the quests that pay the faction, so
    -- its heading says what it counts (the Zones tab's CHAIN of the same
    -- quest may be longer: a 0-rep step breaks the faction's chain). The fake
    -- world's faction views have no chain, so one is handed to the view.
    local view = S.view
    local first, second = view.entries[1], view.entries[2]
    view.chains = view.chains or {}
    view.chains[#view.chains + 1] = { id = "harness", done = 1, total = 2, members = { first.id, second.id } }
    first.chain, second.chain = "harness", "harness"
    REP.Select(second.id)
    brief = Blocks()
    CHECK(Has(brief, "CHAIN (quests that pay Honor Hold)  \194\183  1 of 2 done"),
        "G: CHAIN names what the faction's chain counts: the quests that pay it", Has(brief, "CHAIN"))
    REP.Select(nil)
    first.chain, second.chain = nil, nil
    table.remove(view.chains)
    for _, id in ipairs({ 11354, 11364, 11376 }) do fake.SetUnavailable(id, true) end
    fake.SetRep(946, before)
    Fire("UPDATE_FACTION")
    Settle()
    Open(946)
    CHECK(Has(Blocks(), "+165 a day from 1 daily") and Has(Blocks(), "Wanted (normal): today's pays another faction"),
        "G: ...and back at Friendly, the day as it was")
end
Open(1015)
CHECK(W.card.totals:GetText() == "Hated 0 / 36,000" and W.card.note:GetText() == "+42,000 in quests  \194\183  reaches Neutral  \194\183  pinned",
    "G: Netherwing, not met: its base standing, and Ally of the Netherwing landing on 0", W.card.note:GetText())
brief = Blocks()
CHECK(brief[2] == "Hated 0 / 36,000  (not met yet)" and Has(brief, "Not met yet: every character of your race and class starts at Hated -42,000."),
    "G: ...the overview says it is not met and where everyone starts")
CHECK(Row("Netherwing Crystals").state:GetText() == "Neutral", "G: a daily behind a standing names the standing")
do
    -- Met, and already at 0: Ally of the Netherwing (counted) pays nothing more
    fake.Meet(1015, 0)
    Fire("UPDATE_FACTION")
    Settle()
    local ally = Row("Ally of the Netherwing")
    CHECK(ally and ally.entry.counted and BadgeOf(ally) == "0 capped" and Colour(ally.title) == RGB(kit.Paper(kit.Ink("faint"))),
        "G: a counted quest capped to nothing reads 0 capped, its title dimmed", ally and BadgeOf(ally))
    world.factions[1015], world.reps[1015] = nil, nil
    Fire("UPDATE_FACTION")
    Settle()
end
brief = Blocks()
CHECK(Has(brief, "None you can do today.") and Has(brief, "Netherwing Crystals  +275, from Neutral"),
    "G: DAILIES: none open yet, and the one that opens at Neutral")
local netherCrystals = Row("Netherwing Crystals")
netherCrystals:GetScript("OnEnter")(netherCrystals)
CHECK(TipLines():find("Then a daily: +275 a turn-in; not counted here.", 1, true),
    "G: a locked daily's reason is the lock, then what it will pay", TipLines())
CHECK(not W.watchBtn:IsEnabled(), "G: Watch Faction is greyed out for a faction not met")
WipeLog()
W.watchBtn:GetScript("OnClick")(W.watchBtn)
CHECK(Logged("you have not met Netherwing yet") and #pane.setCalls == 0, "G: ...and says why if pressed anyway")
Sweep("netherwing")
Open(72)
CHECK(Has(Blocks(), "From Ironforge's quests: a quarter of each") and Has(Blocks(), "+68 from 1 quest not done yet, with no cap."),
    "G: a capital's quarter from the other capitals is one summary line, not rows")
Sweep("stormwind")

-- ===========================================================================
-- H. Actions
-- ===========================================================================

Open(933)
CHECK(W.waypointBtn and W.mapBtn and W.logBtn and W.watchBtn and W.ignoreBtn and W.routeBtn == nil,
    "H: Waypoint, Show on Map, Open in Log, Watch Faction, Ignore")
local leftWidth = 80 + 96 + 92 + 104 + 3 * 4
local paneWidth = kit.FRAME_W - kit.PAD - (kit.PAD + kit.NAV_W + 8)
CHECK(W.watchBtn.__points[1].rel == W.logBtn and W.ignoreBtn.__points[1].point == "RIGHT"
    and leftWidth + 4 + 72 <= paneWidth, "H: ...packed from the left with Ignore at the right, inside the pane",
    leftWidth + 76 .. " of " .. paneWidth)
CHECK(not W.mapBtn:IsEnabled() and not W.waypointBtn:IsEnabled(), "H: with nothing selected the quest actions are greyed")
CHECK(not W.watchBtn:IsEnabled(), "H: Watch Faction is greyed for the faction already watched")
local mapAsked = {}
local realUiMap = A.UiMapForArea
A.UiMapForArea = function(areaId)
    mapAsked[#mapAsked + 1] = areaId
    return realUiMap(areaId)
end
REP.Select(9914)
A.UiMapForArea = realUiMap
CHECK(W.mapBtn:IsEnabled() and mapAsked[#mapAsked] == 3518, "H: Show on Map opens the zone the quest starts in (Nagrand)",
    tostring(mapAsked[#mapAsked]))
local askedFaction = false
for _, areaId in ipairs(mapAsked) do if areaId == 933 then askedFaction = true end end
CHECK(not askedFaction, "H: ...and never asks the map for the faction's id")
CHECK(W.waypointBtn:IsEnabled() and not W.logBtn:IsEnabled(), "H: Waypoint is live; Open in Log only for a quest in the log")
W.ignoreBtn:GetScript("OnEnter")(W.ignoreBtn)
CHECK(TipLines():find("here and on the Zones tab", 1, true), "H: Ignore says it is one list for both tabs")
W.ignoreBtn:GetScript("OnClick")(W.ignoreBtn)
Settle()
CHECK(CommanderQuestLogChar.Ignored[9914] == true and W.ignoreBtn:GetText() == "Count" and Has(Headings(), "Ignored"),
    "H: Ignore writes the per-character list; the quest moves under Ignored")
W.ignoreBtn:GetScript("OnClick")(W.ignoreBtn)
Settle()
CHECK(CommanderQuestLogChar.Ignored[9914] == nil and not Has(Headings(), "Ignored"), "H: Count puts it back")
REP.Select(nil)
-- Watch Faction: a read-only walk of the pane, then the game's own call
Open(946)
CHECK(W.watchBtn:IsEnabled(), "H: Watch Faction is live for a met faction you do not watch")
W.watchBtn:GetScript("OnClick")(W.watchBtn)
CHECK(#pane.setCalls == 1 and pane.setCalls[1] == 2 and pane.watched == 946 and pane.expandCalls == 0,
    "H: it watches the faction's own row (index 2) without unfolding anything", tostring(pane.setCalls[1]))
pane.rows[1].collapsed = true
Open(942)
WipeLog()
W.watchBtn:GetScript("OnClick")(W.watchBtn)
CHECK(#pane.setCalls == 1 and pane.expandCalls == 0 and Logged("is under a folded heading in the game's Reputation pane"),
    "H: a faction under a folded heading is reported, never unfolded", printLog[1])
pane.rows[1].collapsed = false
-- Open in Log for the quest in the log
Open(935, 10886)
CHECK(REP.Selected() and REP.Selected().id == 10886 and W.logBtn:IsEnabled(), "H: Open in Log is live for a quest in the log")
W.logBtn:GetScript("OnClick")(W.logBtn)
CHECK(Q.ViewMode() == "LOG" and Q.Selected() and Q.Selected().questID == 10886, "H: ...and lands on it in the Log")

-- ===========================================================================
-- I. /cql rep [name]
-- ===========================================================================

local slash = SlashCmdList["COMMANDERUI_QUESTLOG"]
db.RepFollow, db.RepPicked = false, 946
slash("rep")
CHECK(Q.ViewMode() == "REP" and db.RepFollow == true and db.RepPicked == false, "I: /cql rep opens the tab, following")
slash("rep shatar")
CHECK(db.RepFollow == false and db.RepPicked == 935, "I: /cql rep shatar finds the Sha'tar (no apostrophe, any case)")
slash("REP Honor Hold")
CHECK(db.RepPicked == 946, "I: /cql rep Honor Hold")
slash("rep cons")
CHECK(db.RepPicked == 933, "I: /cql rep cons: the start of a name")
slash("rep 942")
CHECK(db.RepPicked == 942, "I: /cql rep 942: an id")
WipeLog()
slash("rep thrallmar")
CHECK(db.RepPicked == 942 and Logged("no faction called \"thrallmar\""), "I: the other side's faction is not found", printLog[1])
WipeLog()
slash("rep zzz")
CHECK(Logged("no faction called \"zzz\""), "I: nor is nonsense")
WipeLog()
slash("status")
CHECK(Logged("Questie: READY") ~= nil, "I: every other subcommand still goes to the framework")
WipeLog()
slash("bogus")
CHECK((printLog[1] or ""):find("rep", 1, true) ~= nil, "I: the usage line lists rep", printLog[1])
CHECK(REP.FindFaction("The Scryers") == 934 and REP.FindFaction("aldor") == 932 and REP.FindFaction("sporeggar") == 970
    and REP.FindFaction("stormwind") == 72 and REP.FindFaction("undercity") == nil,
    "I: FindFaction: exact, a prefix, a faction not met, a capital; never the other side's")

-- ===========================================================================
-- J. Nothing to show: the other side, no quests, no rules
-- ===========================================================================

-- RepPicked is account-wide: a pin of the other side's faction comes from an
-- alt, and is passed over rather than shown as a dead end this character
-- could never have picked
Open(947)
CHECK(S.key == nil and S.pinnedOther == 947
    and (W.emptyFS:GetText() or "") == "Thrallmar, pinned on another character, is the other side's faction. Pick one from the card above.",
    "J: the other side's faction pinned (an alt's pin) is passed over, and the navigator says whose it was", W.emptyFS:GetText())
CHECK(W.card.note:GetText() == "Click to pick a faction." and (W.card.totals:GetText() or "") == "",
    "J: ...and the card asks for a pick", W.card.note:GetText())
Sweep("other side")
Open(1038)
CHECK(S.err == "NO_QUESTS" and (W.emptyFS:GetText() or ""):find("Questie lists no quest that pays Ogri'la for this character", 1, true),
    "J: a faction with no quests for you says so", W.emptyFS:GetText())
local realRules = Q.Standing
Q.Standing = nil
A.Bump("harness")
Settle()
Q.Refresh()
CHECK(S.err == "NO_RULES" and (W.emptyFS:GetText() or ""):find("The reputation rules are not loaded", 1, true)
    and #mock.caughtErrors == 0, "J: with the rules engine gone the tab says so, and nothing errors", tostring(S.err))
Q.Standing = realRules
A.Bump("harness")
Settle()

-- ===========================================================================
-- K. The register: moving off, switching off
-- ===========================================================================

Open(933)
local ZW = Q.Zones._Widgets()
buttons.ZONE:GetScript("OnClick")(buttons.ZONE)
local anyRow = false
for _, row in ipairs(W.rows) do if row:IsShown() then anyRow = true end end
CHECK(Q.ViewMode() == "ZONE" and not W.toolbar:IsShown() and not W.card:IsShown() and not W.actions:IsShown()
    and not anyRow and #Shown(W.blocks) == 0 and ZW.card:IsShown(),
    "K: Reputations to Zones: every widget of this tab is put away")
buttons.REP:GetScript("OnClick")(buttons.REP)
CHECK(Q.ViewMode() == "REP" and W.card:IsShown() and not ZW.card:IsShown(), "K: ...and back")
db.ShowRepTab = false
Q.Refresh()
CHECK(Q.ViewMode() == "LOG" and not buttons.REP:IsShown() and buttons.ZONE:IsShown(),
    "K: Reputations Tab off: its button goes and the window is on the Log")
WipeLog()
Q.OpenToTab("REP", 933)
CHECK(Logged("the Reputations tab is switched off") and Q.ViewMode() == "LOG", "K: ...and opening it says so")
db.ShowRepTab = true
db.ViewMode = "REP"
Q.Refresh()

-- ===========================================================================
-- L. On the parchment
-- ===========================================================================

db.FrameStyle = "PARCHMENT"
_G.CommanderQuestLogFrame:Hide()
CommanderQuestLog_Show()
Open(933)
CHECK(Colour(Row("Undercutting the Competition").badge) == RGB(kit.Paper(kit.Accent())),
    "L: the badge goes on the paper as ink")
CHECK(Colour(W.card.bar) == RGB(kit.Paper(0.9, 0.7, 0)) and Colour(W.card.bar) ~= RGB(0.9, 0.7, 0),
    "L: so does the standing bar's colour", Colour(W.card.bar))
local fillInk = false
for _, quad in ipairs(W.quads) do
    if quad:IsShown() and Colour(quad) == RGB(kit.Paper(0.9, 0.7, 0)) then fillInk = true end
end
CHECK(fillInk, "L: ...and the overview's standing bar")
db.FrameStyle = "STONE"
_G.CommanderQuestLogFrame:Hide()
CommanderQuestLog_Show()

-- ===========================================================================
-- M. Standing words are the client's, for the player's sex
-- ===========================================================================

UnitSex = function() return 3 end
_G.FACTION_STANDING_LABEL6_FEMALE = "HonoredF"
REP._Labels()
Open(946)
CHECK(Has(Blocks(), "5,000 to HonoredF"), "M: the tab's own words take GetText's female form", Has(Blocks(), "to Honored"))
UnitSex = function() return world.player.sex or 2 end
REP._Labels()
Q.Refresh()

-- ===========================================================================
-- N. One number: every row's badge is the adapter's effect on the faction
-- ===========================================================================

for _, factionId in ipairs({ 933, 935, 932, 946, 1015 }) do
    Open(factionId)
    local bad = {}
    for _, row in ipairs(W.rows) do
        if row:IsShown() and row.entry then
            local effect = R.For(A.RepEffects(row.entry.id), factionId)
            local want = effect and (effect.delta == 0 and (effect.capped and "0 capped" or "0") or R.FormatRep(effect.delta))
            if BadgeOf(row) ~= want then bad[#bad + 1] = row.entry.id .. ":" .. tostring(BadgeOf(row)) .. "/" .. tostring(want) end
        end
    end
    CHECK(#bad == 0, "N: faction " .. factionId .. ": every badge is A.RepEffects' number", table.concat(bad, " "))
end
for _, pair in ipairs({ { 932, 10326 }, { 946, 11354 }, { 1015, 10871 }, { 933, 10165 } }) do
    Open(pair[1], pair[2])
    local line = A.RepLine(pair[2])
    local missing = {}
    for part in (line .. "  "):gmatch("(.-)  ") do
        local delta, name = part:match("^(%S+) (.+)$")
        if delta and not Has(Blocks(), delta .. " " .. name) then missing[#missing + 1] = part end
    end
    CHECK(line ~= "No reputation" and #missing == 0, "N: quest " .. pair[2] .. ": the briefing lists the line every surface shows ("
        .. line .. ")", table.concat(missing, ";"))
end
REP.Select(nil)

-- ===========================================================================
-- P. Words that say what they count (the 1.6.0 review)
-- ===========================================================================

-- The picker: a count of the once-only quests done, never a bare percentage
-- beside the standing word (it read as progress through the standing)
do
    Open(933)
    local added = {}
    local realAdd = UIDropDownMenu_AddButton
    UIDropDownMenu_AddButton = function(info, level) added[#added + 1] = { info = info, level = level } end
    W.menu.__init(W.menu, 1)
    local outland
    for _, item in ipairs(added) do if item.info.text == "Outland" then outland = item.info end end
    added = {}
    W.menu.__init(W.menu, 2, outland and outland.menuList)
    UIDropDownMenu_AddButton = realAdd
    local consortium
    for _, item in ipairs(added) do if item.info.arg1 == 933 then consortium = item.info.text end end
    CHECK(consortium == "The Consortium  Neutral  \194\183  0/4 done" and not consortium:find("%", 1, true),
        "P: the picker says what its number counts: once-only quests done, not a percentage", consortium)
end

-- Today's Wanted dailies not known: not "None you can do today" for a faction
-- every Wanted daily pays
do
    fake.ResetDailies()
    A.Bump("harness")
    Settle()
    Open(933)
    local brief = Blocks()
    CHECK(Has(brief, "Nothing to count on yet: today's Wanted dailies are not known.") and not Has(brief, "None you can do today"),
        "P: the Consortium with today's Wanted not known: nothing to count on yet, never none today", table.concat(brief, " | "))
    CHECK(Has(brief, "Wanted (normal): 3 in the rotation pay it, up to +275 on a day one of them is offered; today's not known yet"),
        "P: ...each pool in words that never promise it every day", Has(brief, "Wanted (normal)"))
    for _, id in ipairs({ 11354, 11364, 11376 }) do fake.SetUnavailable(id, true) end
    A.Bump("harness")
    Settle()
end

-- A faction whose quests a later content phase holds back, every one: not
-- the search's doing
do
    Open(1077)
    CHECK(S.view ~= nil and #(S.view.entries or {}) == 0
        and (W.emptyFS:GetText() or "") == "Every quest that pays Shattered Sun Offensive comes with a later content phase (4 quests); Questie lists them then.",
        "P: the Shattered Sun before its phase: the navigator says why it is empty, not \"matches this search\"",
        W.emptyFS:GetText())
    Sweep("sso")
end

-- What a quest pays comes straight under its reason on this tab, the quest
-- as a source with it: a long chain never pushes them out of the pane
do
    Open(932, 10326)
    local brief = Blocks()
    local at = {}
    for i, line in ipairs(brief) do if not at[line] then at[line] = i end end
    CHECK(at.REPUTATION == 4 and at["AS A SOURCE"] and at.WHERE and at["AS A SOURCE"] < at.WHERE,
        "P: REPUTATION and AS A SOURCE come before WHERE", tostring(at.REPUTATION) .. " " .. tostring(at.WHERE))
    REP.Select(nil)
end

-- ===========================================================================
-- O. No glyphs (D11): middle dot, em dash and ellipsis are the only
-- characters outside ASCII the tab draws
-- ===========================================================================

do
    local bad = {}
    for _, item in ipairs(drawn) do
        local stripped = item[2]:gsub("\194\183", ""):gsub("\226\128\148", ""):gsub("\226\128\166", "")
        if stripped:find("[\128-\255]") then bad[#bad + 1] = item[1] .. ": " .. item[2] end
    end
    CHECK(#drawn > 200 and #bad == 0, "O: nothing drawn carries a glyph (" .. #drawn .. " strings)", bad[1])
end

-- ===========================================================================
-- Z. Clean
-- ===========================================================================

CHECK(#mock.caughtErrors == 0, "Z: no error reached the error handler", mock.caughtErrors[1])
CHECK(#fake.forbidden == 0 and #fake.styleErrors == 0, "Z: nothing called Questie the way it must not be",
    fake.forbidden[1] or fake.styleErrors[1])
CHECK(pane.expandCalls == 0, "Z: the Reputation pane was never unfolded")
local lastError = A._LastError and A._LastError()
CHECK(lastError == nil, "Z: the adapter noted no error", type(lastError) == "table" and tostring(lastError.message or lastError[1]) or tostring(lastError))

Done()
