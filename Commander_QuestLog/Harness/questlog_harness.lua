-- Commander Quest Log harness (luajit).
--
-- Loads the REAL shared framework (CommanderSettingsUI.lua, CommanderEvents.lua)
-- and every Commander_QuestLog window file -- DB, Model, the completion engine,
-- the Questie adapter, the window, the catalogue and the Zones tab; not the
-- map drawer, which has its own harness -- under a permissive WoW mock
-- (questlog_mock.lua), with a fake Questie (fake_questie.lua) installed before
-- any of them loads. Then it drives a whole session against a MUTABLE quest
-- log: scanning it, searching it, folding zones shut, tracking and
-- abandoning, and turning a quest in underneath the window while it is open
-- (A-P); then the Zones tab over the fake Questie's Hellfire Peninsula (Q),
-- the review's fixes to it (Q2), and the tab register with a second
-- catalogue registered beside it (Q3); then a second load of the module with
-- no Questie at all (R).
--
--   luajit questlog_harness.lua
--
-- The mock's own notes -- why the log is mutable and its indices move, why
-- Show fires OnShow only on a hidden frame, how a hover's font swap is acted
-- out, why scroll offsets and sizes are kept -- are in questlog_mock.lua's
-- header, with how a new harness file stands on it.

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
--
-- The client lives in Harness/questlog_mock.lua, so another harness file can
-- stand on the same one (see its header). It is loaded first: it installs
-- its globals as it loads. The sections below still read and assign the
-- client's state through the bare names they always have -- `log`,
-- `selection`, `watched`, `chatSent` and the rest -- because those are this
-- file's locals, bound into the mock: the mock's GetQuestLogTitle reads this
-- `log`, its SelectQuestLogEntry writes this `selection`.
-- ===========================================================================

local mock = dofile(ADDONS .. "/Commander_QuestLog/Harness/questlog_mock.lua")

local log, selection, watched, abandoned, pushed, abandonArmed = {}, 0, {}, {}, {}, nil
local expandCalls, raidInfoRequests, inRaid, inParty = 0, 0, false, false
local chatSent, popupsShown, hiddenPanels, savedInstances = {}, {}, {}, {}
mock.Bind({ "log", "selection", "watched", "abandoned", "pushed", "abandonArmed", "expandCalls",
    "raidInfoRequests", "inRaid", "inParty", "chatSent", "popupsShown", "hiddenPanels", "savedInstances" },
    function(key)
        if key == "log" then return log elseif key == "selection" then return selection
        elseif key == "watched" then return watched elseif key == "abandoned" then return abandoned
        elseif key == "pushed" then return pushed elseif key == "abandonArmed" then return abandonArmed
        elseif key == "expandCalls" then return expandCalls elseif key == "raidInfoRequests" then return raidInfoRequests
        elseif key == "inRaid" then return inRaid elseif key == "inParty" then return inParty
        elseif key == "chatSent" then return chatSent elseif key == "popupsShown" then return popupsShown
        elseif key == "hiddenPanels" then return hiddenPanels elseif key == "savedInstances" then return savedInstances
        end
    end,
    function(key, value)
        if key == "log" then log = value elseif key == "selection" then selection = value
        elseif key == "watched" then watched = value elseif key == "abandoned" then abandoned = value
        elseif key == "pushed" then pushed = value elseif key == "abandonArmed" then abandonArmed = value
        elseif key == "expandCalls" then expandCalls = value elseif key == "raidInfoRequests" then raidInfoRequests = value
        elseif key == "inRaid" then inRaid = value elseif key == "inParty" then inParty = value
        elseif key == "chatSent" then chatSent = value elseif key == "popupsShown" then popupsShown = value
        elseif key == "hiddenPanels" then hiddenPanels = value elseif key == "savedInstances" then savedInstances = value
        end
    end)

local clock, printLog, caughtErrors, eventRegistry = mock.clock, mock.printLog, mock.caughtErrors, mock.eventRegistry
local allFrames, categories, NewWidget = mock.allFrames, mock.categories, mock.NewWidget
local Logged, WipeLog, RunTimers, AcceptPopup = mock.Logged, mock.WipeLog, mock.RunTimers, mock.AcceptPopup
local HoverButton, HoverIn, HoverOut = mock.HoverButton, mock.HoverIn, mock.HoverOut

-- ===========================================================================
-- Load the framework and the module
-- ===========================================================================

local Load, Fire = mock.Load, mock.Fire

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

-- The window's files in the TOC's order, minus the map drawer (it has its
-- own harness, questlog_map_harness.lua, and this mock has no world map).
-- The 1.6.0 files -- the reputation data, the standing engine, the
-- Reputations tab, the quest dialog -- are driven by harnesses of their own
-- on questlog_mock.lua, so the counts here stay this file's: section Q's
-- "takes both tabs away" is the two-tab window, and with a Reputations tab
-- loaded the Log and that tab would rightly stay (Q3 checks that rule).
local MODULE_FILES = {
    "CommanderQuestLogDB.lua", "CommanderQuestLogModel.lua", "CommanderQuestLogCompletion.lua",
    "CommanderQuestLogQuestie.lua", "CommanderQuestLogUI.lua", "CommanderQuestLogCatalogue.lua",
    "CommanderQuestLogZones.lua",
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
-- Q3: the tab register, and a second catalogue (1.6.0)
--
-- The window's tabs are a register now (Q.RegisterTab), not a Log | Zones
-- pair, and the Zones tab is one instance of the catalogue
-- (Q.NewCatalogue). A third tab is registered here the way the Reputations
-- tab will be: a catalogue of its own over the fake Hellfire Peninsula, with
-- every hook a spec can hand the catalogue answered by a stub. The register:
-- three buttons placed by width; moving off a tab puts ITS widgets away
-- whichever tab comes next; a quest link from it lands on the Log; its
-- switch takes its button away and puts the window on the Log; a ViewMode
-- nobody registered is the Log. The hooks: the spec's own groupings, filters,
-- badge, card, overview, briefing sections, words, menu and actions are what
-- the instance draws, its two named dropdowns are its own, and the Zones
-- tab's widgets are never touched.
-- ---------------------------------------------------------------------------
do
    local Z, A, C = Q.Zones, Q.Questie, Q.Catalogue
    local window = _G.CommanderQuestLogFrame
    local ZW = Z._Widgets()
    local kit = Q._kit
    local calls = { overview = 0, sections = 0, briefing = 0, group = 0, action = 0, rowTip = 0, filter = 0 }
    local stubKey = 3483
    local function TitleOf(id) return world.quests[id] and world.quests[id].name end

    db.ViewMode = "LOG"
    CommanderQuestLog_Show()
    CHECK(type(Q.RegisterTab) == "function" and type(Q.NewCatalogue) == "function" and C ~= nil,
        "Q3: the window publishes its register and the catalogue factory")
    CHECK(#Q.Tabs() == 2 and Q.Tabs()[1].id == "LOG" and Q.Tabs()[2].id == "ZONE",
        "Q3: before a third tab, the register holds the Log and the Zones tab, in that order")
    CHECK(ZW.tabs == Q.TabButtons(), "Q3: the Zones tab's W.tabs is the window's own buttons")

    local REP = Q.NewCatalogue({
        id = "REP", order = 30, label = "Reputations", title = "Reputations", width = 78,
        tooltip = "A faction's every quest.", prefix = "HarnessRep", showKey = "ShowRepTab",
        offMessage = "Commander Quest Log: the harness tab is switched off.",
        searchTip = "Matches a quest's name, among the faction's quests.",
        countTip = "Harness count words.",
        Resolve = function() if stubKey then return stubKey, "Honor Hold" end return nil, nil end,
        View = function(_, key) return A.ZoneView(key) end,
        groups = { "GUIDE", "BAND", "LEVEL" }, groupLabels = { BAND = "By band" },
        Group = function(cat, view, mode)
            if mode ~= "BAND" then return nil end
            calls.group = calls.group + 1
            local bands, order = {}, {}
            for _, entry in ipairs(view.entries) do
                local band = (entry.level or 0) >= 61 and 61 or 58
                if not bands[band] then bands[band] = {}; order[#order + 1] = band end
                table.insert(bands[band], entry)
            end
            table.sort(order)
            local list = {}
            for _, band in ipairs(order) do
                table.sort(bands[band], function(a, b) return a.id < b.id end)
                cat.Emit(list, "BAND" .. band, "Band " .. band, bands[band])
            end
            return list
        end,
        filterOrder = { "ALL", "OPEN", "DONE" },
        filterSpecs = { ALL = { label = "Every", tooltip = "Every quest of the faction." } },
        PassesFilter = function(_, entry, key)
            calls.filter = calls.filter + 1
            if key == "OPEN" then return entry.base == "AVAILABLE" end
            return nil
        end,
        RowRight = function(_, entry)
            if entry.id == 9005 then return "+250", "good" end
            if entry.id == 9004 then return "0", "faint", true end
            return nil
        end,
        RowTooltip = function() calls.rowTip = calls.rowTip + 1; GameTooltip:AddLine("Harness rep line") end,
        StateWord = function(_, entry) if entry.id == 9001 then return "rep", "good" end return nil end,
        Reason = function(_, entry) if entry.id == 9004 then return "Harness reason." end return nil end,
        PaintCard = function(_, card)
            card.name:SetText("Harness faction")
            card.totals:SetText("Friendly 1,250 / 6,000")
            card.bar:Hide()
            card.note:SetText("Harness note.")
        end,
        MenuInit = function(cat, level, menuList) calls.menuArgs = { cat, level, menuList } end,
        PaintOverview = function(cat, view)
            calls.overview = calls.overview + 1
            cat.Line("HARNESS OVERVIEW " .. tostring(view.name), "GameFontNormalLarge", cat.InkT("primary"))
        end,
        OverviewSections = function(cat)
            calls.sections = calls.sections + 1
            cat.Rule()
            cat.Heading("EXTRA SECTION")
        end,
        Reputation = function(cat, entry, detail)
            if detail and type(detail.repRewards) == "table" and #detail.repRewards > 0 then
                cat.Rule()
                cat.Heading("REPUTATION (hook) " .. entry.id)
            end
        end,
        BriefingSections = function(cat, entry)
            calls.briefing = calls.briefing + 1
            cat.Rule()
            cat.Heading("REP SECTION")
            cat.Line("for " .. entry.id, "GameFontHighlightSmall", cat.InkT("secondary"), 4)
        end,
        actions = {
            "WAYPOINT",
            { field = "watchBtn", label = "Watch", width = 70,
              onClick = function(cat) calls.action = calls.action + 1; calls.actionCat = cat end,
              Update = function(_, button, entry) button:SetEnabled(entry ~= nil) end },
            { stock = "IGNORE", tooltip = "Harness ignore words." },
        },
    })
    local RW, RS = REP._Widgets(), REP._State()
    local function RepRow(title)
        for _, row in ipairs(RW.rows) do
            if row:IsShown() and row.title:GetText() == title then return row end
        end
        return nil
    end
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
    local function AnyShown(list)
        for _, widget in ipairs(list) do if widget:IsShown() then return true end end
        return false
    end
    local function TopLeftX(widget)
        for _, pt in ipairs(widget.__points or {}) do
            if pt.point == "TOPLEFT" then return pt.x end
        end
        return nil
    end
    local function RightX(widget)
        local x
        for _, pt in ipairs(widget.__points or {}) do
            if pt.point == "RIGHT" then x = pt.x end
        end
        return x
    end
    local function NavTop()
        local y
        for _, pt in ipairs(window.navPane.__points or {}) do
            if pt.point == "TOPLEFT" then y = pt.y end
        end
        return y
    end

    -- The register
    CHECK(#Q.Tabs() == 3 and Q.Tabs()[3].id == "REP" and Q.Tabs()[3].instance == REP,
        "Q3: a catalogue registers itself, after the Zones tab by its order")
    Q.Refresh()
    local buttons = Q.TabButtons()
    CHECK(buttons.REP and buttons.REP:IsShown() and buttons.LOG:IsShown() and buttons.ZONE:IsShown(),
        "Q3: a tab registered after the window was built gets its button on the next pass")
    CHECK(TopLeftX(buttons.LOG) == 12 and TopLeftX(buttons.ZONE) == 72 and TopLeftX(buttons.REP) == 132,
        "Q3: the buttons sit one after another by width (12, 72, 132)",
        tostring(TopLeftX(buttons.LOG)) .. " " .. tostring(TopLeftX(buttons.ZONE)) .. " " .. tostring(TopLeftX(buttons.REP)))
    CHECK(buttons.REP.__w == 78 and buttons.REP:GetText() == "Reputations",
        "Q3: ...each as wide as its tab asks, with its own word")
    CHECK((buttons.REP:GetFrameLevel() or 0) > (window:GetFrameLevel() or 0) + 1,
        "Q3: the new tab sits above the drag strip too")
    local before = buttons.REP
    REP.tab.order = 15
    Q.RegisterTab(REP.tab)
    Q.Refresh()
    CHECK(Q.Tabs()[2].id == "REP" and TopLeftX(buttons.REP) == 72 and TopLeftX(buttons.ZONE) == 72 + 78 + 2,
        "Q3: the strip follows the order, each button placed by the widths before it",
        tostring(TopLeftX(buttons.REP)) .. " " .. tostring(TopLeftX(buttons.ZONE)))
    REP.tab.order = 30
    Q.RegisterTab(REP.tab)
    Q.Refresh()
    CHECK(#Q.Tabs() == 3 and Q.TabButtons().REP == before and TopLeftX(buttons.REP) == 132,
        "Q3: registering the same id again replaces it, keeping its one button")

    -- Onto the third tab
    buttons.REP:GetScript("OnClick")(buttons.REP)
    CHECK(db.ViewMode == "REP" and Q.ViewMode() == "REP", "Q3: the third tab switches the window over")
    CHECK(buttons.REP.underline.__color[4] > 0.5 and buttons.ZONE.underline.__color[4] == 0
        and buttons.LOG.underline.__color[4] == 0, "Q3: ...and is the one underlined")
    CHECK(RW.toolbar:IsShown() and RW.card:IsShown() and RW.actions:IsShown(),
        "Q3: its own toolbar, card and action bar are up")
    CHECK(not ZW.toolbar:IsShown() and not ZW.card:IsShown() and not ZW.actions:IsShown()
        and not AnyShown(ZW.rows) and not AnyShown(ZW.blocks),
        "Q3: the Zones tab's toolbar, card, action bar, rows and briefing are all put away")
    CHECK(not window.filters.ALL:IsShown() and not window.trackBtn:IsShown(), "Q3: ...and so are the Log's")
    CHECK(NavTop() == -8 - 50, "Q3: the navigator moves down under the new tab's card", NavTop())
    CHECK(RW.card.name:GetText() == "Harness faction" and RW.card.totals:GetText() == "Friendly 1,250 / 6,000"
        and RW.card.note:GetText() == "Harness note.", "Q3: the card is the spec's PaintCard")
    CHECK(_G.CommanderQuestLogHarnessRepGroupDrop == RW.groupDrop and _G.CommanderQuestLogHarnessRepMenu == RW.menu,
        "Q3: the new tab's two dropdowns are named after its prefix")
    CHECK(_G.CommanderQuestLogZoneGroupDrop == ZW.groupDrop and _G.CommanderQuestLogZoneMenu == ZW.menu
        and RW.groupDrop ~= ZW.groupDrop, "Q3: ...and the Zones tab keeps its own")
    CHECK(RS.key == 3483 and Z._State().areaId ~= nil and RS.areaId == nil,
        "Q3: each instance keeps its own state (areaId is the Zones tab's name for its key alone)")

    -- Its rows: the spec's badge, words and dimming
    local enemy = RepRow(TitleOf(9005))
    CHECK(enemy and enemy.badge and enemy.badge:IsShown() and enemy.badge:GetText() == "+250",
        "Q3: RowRight puts a badge on the row", enemy and enemy.badge and enemy.badge:GetText())
    CHECK(enemy and RightX(enemy.title) == -(46 + 10 + 40 + 4),
        "Q3: ...and the title gives up the badge's width", enemy and RightX(enemy.title))
    CHECK(enemy and enemy.badge.__points[1].rel == enemy.state and enemy.badge.__points[1].point == "RIGHT",
        "Q3: ...which sits just left of the state word")
    local legion = RepRow(TitleOf(9004))
    local fr, fg, fb = kit.Paper(kit.Ink("faint"))
    CHECK(legion and legion.title.__color[1] == fr and legion.title.__color[2] == fg and legion.title.__color[3] == fb,
        "Q3: a badge's dim flag inks a counted quest's title faint")
    local plain = RepRow(TitleOf(9033))
    CHECK(plain and RightX(plain.title) == -(46 + 10) and not (plain.badge and plain.badge:IsShown()),
        "Q3: a row with no badge keeps the full title width", plain and RightX(plain.title))
    local zoneHasBadge = false
    for _, row in ipairs(ZW.rows) do if row.badge then zoneHasBadge = true end end
    CHECK(not zoneHasBadge, "Q3: the Zones tab, with no RowRight, never makes a badge")
    local arrival = RepRow(TitleOf(9001))
    CHECK(arrival and arrival.state:GetText() == "rep", "Q3: StateWord answers for the quests it knows",
        arrival and arrival.state:GetText())
    CHECK(enemy and enemy.state:GetText() == "open", "Q3: ...and hands the rest to the engine")
    legion:GetScript("OnEnter")(legion)
    local tip = table.concat(GameTooltip.__lines, " | ")
    CHECK(tip:find("Harness reason.", 1, true) and tip:find("Harness rep line", 1, true)
        and tip:find("Right-click for a waypoint", 1, true),
        "Q3: a row's tooltip carries the spec's reason and its RowTooltip lines", tip)

    -- Groups and filters from the spec
    local added = {}
    local realAdd = UIDropDownMenu_AddButton
    UIDropDownMenu_AddButton = function(info) added[#added + 1] = info end
    RW.groupDrop.__init(RW.groupDrop)
    UIDropDownMenu_AddButton = realAdd
    CHECK(#added == 3 and added[1].text == "Guide" and added[2].text == "By band" and added[3].text == "By level",
        "Q3: the group dropdown lists the spec's modes with its words, the engine's words for the rest",
        (added[1] and added[1].text or "-") .. "," .. (added[2] and added[2].text or "-"))
    db.HarnessRepGroup = "BAND"
    Q.Refresh()
    local band = RepRow("Band 61")
    CHECK(calls.group > 0 and band and band.headerTitle == "Band 61" and RepRow("Band 58") ~= nil,
        "Q3: a spec's Group draws its own headings (cat.Emit)")
    band:GetScript("OnClick")(band, "LeftButton")
    CHECK(db.HarnessRepCollapsed and db.HarnessRepCollapsed["Band 61"] == true
        and (db.ZoneCollapsed or {})["Band 61"] == nil and RepRow(TitleOf(9005)) == nil,
        "Q3: folding one writes the tab's own fold table, never the Zones tab's")
    RepRow("Band 61"):GetScript("OnClick")(RepRow("Band 61"), "LeftButton")
    db.HarnessRepGroup = "GUIDE"
    Q.Refresh()
    CHECK(RepRow("Pick up now") ~= nil, "Q3: a mode the spec does not know goes to the engine")
    CHECK(RW.filters.ALL and RW.filters.ALL:GetText() == "Every" and RW.filters.OPEN
        and RW.filters.OPEN:GetText() == "Open" and RW.filters.MISSED == nil,
        "Q3: the filter buttons are the spec's (its words where it has them)")
    RW.filters.OPEN:GetScript("OnClick")(RW.filters.OPEN)
    local anyLog, anyOpen = false, false
    for _, item in ipairs(RS.rows) do
        if item.entry and item.entry.base == "LOG" then anyLog = true end
        if item.entry and item.entry.base == "AVAILABLE" then anyOpen = true end
    end
    CHECK(db.HarnessRepFilter == "OPEN" and anyOpen and not anyLog and calls.filter > 0,
        "Q3: the spec's PassesFilter decides its keys (Open without the quest in the log)")
    CHECK(db.ZoneFilter ~= "OPEN", "Q3: ...in the tab's own filter key")
    RW.filters.ALL:GetScript("OnClick")(RW.filters.ALL)

    -- The briefing: the spec's overview, then a quest with its sections
    local brief = Shown(RW.blocks)
    CHECK(calls.overview > 0 and Has(brief, "HARNESS OVERVIEW Hellfire Peninsula") and Has(brief, "EXTRA SECTION"),
        "Q3: the overview is the spec's PaintOverview, then its OverviewSections", table.concat(brief, " | "))
    REP.Select(9005)
    brief = Shown(RW.blocks)
    CHECK(brief[1] == TitleOf(9005) and Has(brief, "WHERE"), "Q3: a quest's briefing is the catalogue's own")
    CHECK(Has(brief, "REPUTATION (hook) 9005") and not Has(brief, "+250  Honor Hold"),
        "Q3: the spec's Reputation replaces the stock REPUTATION section")
    CHECK(Has(brief, "REP SECTION") and Has(brief, "for 9005"), "Q3: ...and BriefingSections come after it")
    CHECK(not AnyShown(ZW.blocks), "Q3: nothing of it lands in the Zones tab's briefing pool")

    -- The menu and the actions
    RW.menu.__init(RW.menu, 2, "harness")
    CHECK(calls.menuArgs and calls.menuArgs[1].instance == REP and calls.menuArgs[2] == 2
        and calls.menuArgs[3] == "harness", "Q3: the card's menu is the spec's MenuInit, handed the context")
    CHECK(RW.waypointBtn and RW.watchBtn and RW.ignoreBtn and RW.mapBtn == nil and RW.logBtn == nil
        and RW.routeBtn == nil, "Q3: the action bar is the spec's list, stock and custom")
    CHECK(RW.watchBtn.__points[1].rel == RW.waypointBtn and RW.ignoreBtn.__points[1].point == "RIGHT",
        "Q3: ...packed from the left, Ignore at the right")
    CHECK(RW.watchBtn:IsEnabled() and RW.ignoreBtn:IsEnabled(), "Q3: a custom action's Update runs (a quest selected)")
    RW.watchBtn:GetScript("OnClick")(RW.watchBtn)
    CHECK(calls.action == 1 and calls.actionCat and calls.actionCat.instance == REP,
        "Q3: ...and its onClick is handed the context")
    RW.ignoreBtn:GetScript("OnEnter")(RW.ignoreBtn)
    CHECK(table.concat(GameTooltip.__lines, " | "):find("Harness ignore words.", 1, true),
        "Q3: a stock action takes the spec's own words")
    RW.ignoreBtn:GetScript("OnClick")(RW.ignoreBtn)
    CHECK(CommanderQuestLogChar.Ignored[9005] == true and RW.ignoreBtn:GetText() == "Count",
        "Q3: Ignore on any tab writes the one per-character list")
    RW.ignoreBtn:GetScript("OnClick")(RW.ignoreBtn)
    RunTimers(1)
    RunTimers(1)
    REP.Select(nil)
    CHECK(not RW.watchBtn:IsEnabled(), "Q3: ...and with nothing selected, its Update greys it out")

    -- Each tab keeps its own search
    local box = window.searchBox
    box:SetText("legion")
    box:GetScript("OnTextChanged")(box, true)
    CHECK(REP.SearchText() == "legion" and Z.SearchText() == "" and RS.shown == 1,
        "Q3: typing on the new tab searches the new tab alone", RS.shown)
    local tipBox = box.__scripts.OnEnter
    if tipBox then tipBox(box) end
    CHECK(table.concat(GameTooltip.__lines, " | "):find("among the faction's quests", 1, true),
        "Q3: the search box's tooltip is the active tab's")
    buttons.ZONE:GetScript("OnClick")(buttons.ZONE)
    CHECK((box:GetText() or "") == "", "Q3: the Zones tab brings its own, empty, search", box:GetText())
    buttons.REP:GetScript("OnClick")(buttons.REP)
    CHECK(box:GetText() == "legion", "Q3: ...and the new tab its own again", box:GetText())
    box:GetScript("OnEscapePressed")(box)
    CHECK(REP.SearchText() == "", "Q3: Escape clears the new tab's search")

    -- Moving off the third tab puts ITS widgets away, whichever tab is next
    REP.Select(9004)
    buttons.ZONE:GetScript("OnClick")(buttons.ZONE)
    CHECK(Q.ViewMode() == "ZONE" and ZW.card:IsShown() and ZW.toolbar:IsShown(), "Q3: REP to Zones: the Zones tab is up")
    CHECK(not RW.toolbar:IsShown() and not RW.card:IsShown() and not RW.actions:IsShown()
        and not AnyShown(RW.rows) and not AnyShown(RW.blocks) and not AnyShown(RW.quads),
        "Q3: ...and every widget of the REP tab is put away")
    CHECK(AnyShown(ZW.rows) and not AnyShown(RW.rows), "Q3: ...the navigator holds the zone's rows only")
    buttons.REP:GetScript("OnClick")(buttons.REP)
    CHECK(not ZW.card:IsShown() and not AnyShown(ZW.rows) and RW.card:IsShown(), "Q3: ...and back the other way")
    CHECK(REP.Selected() and REP.Selected().id == 9004, "Q3: ...with the new tab's selection where it was left")

    -- A quest link from the third tab lands on the Log
    CommanderQuestLog_OpenToQuest(2)
    CHECK(db.ViewMode == "LOG" and Q.ViewMode() == "LOG" and Q.Selected() and Q.Selected().questID == 9003,
        "Q3: OpenToQuest from the new tab lands on the Log with the quest selected")
    CHECK(window.trackBtn:IsShown() and not RW.card:IsShown() and not AnyShown(RW.rows)
        and buttons.LOG.underline.__color[4] > 0.5, "Q3: ...the Log's widgets up, the new tab's away")

    -- Opening a tab from outside
    Q.OpenToTab("REP", 3519, 9014)
    CHECK(Q.ViewMode() == "REP" and db.HarnessRepFollow == false and db.HarnessRepPicked == 3519,
        "Q3: Q.OpenToTab opens a tab pinned to a key")
    stubKey = 3519
    Q.Refresh()
    CHECK(REP.Selected() == nil and RS.key == 3519, "Q3: (the stub follows its pin)")
    REP.PrepareOpen(nil, 9014)
    Q.Refresh()
    CHECK(REP.Selected() and REP.Selected().id == 9014 and db.HarnessRepFollow == true,
        "Q3: ...and a nil key follows, selecting the quest asked for")
    stubKey = nil
    Q.Refresh()
    CHECK(RW.emptyFS and RW.emptyFS:IsShown()
        and RW.emptyFS:GetText() == "Nothing to show here. Pick one from the card above.",
        "Q3: with nothing resolved, the stock empty sentence", RW.emptyFS and RW.emptyFS:GetText())
    CHECK(Shown(RW.blocks)[1] == "Reputations", "Q3: ...under the tab's title", Shown(RW.blocks)[1])
    stubKey = 3483
    RW.card:GetScript("OnClick")(RW.card, "RightButton")
    CHECK(db.HarnessRepFollow == true and db.HarnessRepPicked == false, "Q3: right-clicking the card follows")

    -- Its switch
    db.ShowRepTab = false
    Commander.Notify(COMMANDER_QUESTLOG_EVENTS.UPDATE)
    CHECK(Q.ViewMode() == "LOG" and window.trackBtn:IsShown() and not RW.card:IsShown(),
        "Q3: switching the new tab off puts the window on the Log")
    CHECK(not buttons.REP:IsShown() and buttons.LOG:IsShown() and buttons.ZONE:IsShown(),
        "Q3: ...and takes its button away, leaving the Log and the Zones tab")
    Q.SetViewMode("REP")
    CHECK(db.ViewMode == "LOG" and Q.ViewMode() == "LOG", "Q3: a switched-off tab cannot be switched to")
    WipeLog()
    Q.OpenToTab("REP", 3483)
    CHECK(Logged("the harness tab is switched off") and Q.ViewMode() == "LOG",
        "Q3: ...nor opened from outside, which says why")
    db.ShowRepTab = nil
    db.ShowZoneTab = false
    Q.Refresh()
    CHECK(buttons.LOG:IsShown() and not buttons.ZONE:IsShown() and buttons.REP:IsShown()
        and TopLeftX(buttons.REP) == 72, "Q3: with the Zones tab off, the new tab moves up beside the Log",
        TopLeftX(buttons.REP))
    db.ShowRepTab = false
    Q.Refresh()
    CHECK(not buttons.LOG:IsShown() and not buttons.ZONE:IsShown() and not buttons.REP:IsShown(),
        "Q3: with every other tab off there are no tabs at all")
    db.ShowRepTab = nil
    db.ShowZoneTab = true
    Q.Refresh()
    CHECK(TopLeftX(buttons.ZONE) == 72 and TopLeftX(buttons.REP) == 132 and buttons.REP:IsShown(),
        "Q3: ...and with both back, back in their places")

    -- A ViewMode nobody registered is the Log
    db.ViewMode = "NO_SUCH_TAB"
    Q.Refresh()
    CHECK(Q.ViewMode() == "LOG" and window.trackBtn:IsShown() and window.filters.ALL:IsShown()
        and not RW.card:IsShown() and not ZW.card:IsShown() and buttons.LOG.underline.__color[4] > 0.5,
        "Q3: an unknown ViewMode draws the Log, with nothing of the other tabs up")
    Q.SetViewMode("NO_SUCH_TAB")
    CHECK(db.ViewMode == "LOG", "Q3: ...and switching to one writes the Log", db.ViewMode)

    -- Ink on paper: the new tab's badge goes through Paper() like the rest
    db.ViewMode = "REP"
    OpenAs("PARCHMENT")
    enemy = RepRow(TitleOf(9005))
    CHECK(enemy and enemy.badge and Lum(enemy.badge.__color) <= INK_MAX,
        "Q3: on paper a row's badge is ink", enemy and enemy.badge and tostring(Lum(enemy.badge.__color)))
    OpenAs("STONE")

    CHECK(#fake.forbidden == 0, "Q3: nothing forbidden reached Questie", table.concat(fake.forbidden, ","))
    db.HarnessRepGroup, db.HarnessRepFilter, db.HarnessRepCollapsed = nil, nil, nil
    db.HarnessRepFollow, db.HarnessRepPicked, db.ShowRepTab = nil, nil, nil
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
