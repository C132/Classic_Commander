-- Commander Quest Log: reputation on every surface that shows a quest (luajit).
--
-- The 1.6.0 brief: wherever a quest is shown, say what it is worth in
-- reputation -- one number, including "No reputation" -- and on a zone's
-- overview say whether 100%-ing the zone gets a faction anywhere. This
-- harness loads the whole module as the TOC does (the reputation data, the
-- rules engine, the adapter, the window, the catalogue and the Zones tab, the
-- quest dialog and the world-map drawer; not the Reputations tab, which has a
-- harness of its own) on the window harnesses' client (questlog_mock.lua),
-- over the fake Questie's reputation world (Fake.RepWorld(): a level-70 Human
-- paladin, real quest ids and Questie's real rows), with the 2.5.6 quest
-- dialog (questframe_mock.lua), a small world map for the drawer and a
-- recording Commander Orders. It asserts what lands on screen:
--
--   A  the Log's briefing: "Reputation: +275 Honor Hold" under REWARDS, or
--      under the facts when there is no REWARDS section; "No reputation";
--      the switches; ink on paper; "(seen in game)"; the Log's waypoint note;
--   B  the Zones tab's rows: a badge naming its faction ("+275 HH", "0")
--      left of the state word, its ink, a quest worth 0 still counted (never
--      dimmed for it), the row tooltip's line (light on the parchment too),
--      ZoneRowRep and ShowRepEverywhere;
--   C  the Zones briefing's REPUTATION: every effect with its kind and cap,
--      the multiplier, a shut spill window shown, not hidden; under the
--      quest's reason; 1.5.0's raw rows with ShowRepEverywhere off;
--   D  the overview's REPUTATION IN THIS ZONE, under the zone's completion:
--      what is left (the projection's), what was done, whether it reaches
--      the next standing and how far short of Exalted, what the spill window
--      lands (open, closing, shut), the dungeon quests' share, quests no
--      climb here reaches, steady dailies apart from the rotating Wanted
--      ones and Halaa's, the order hints, factions not met, the done-only
--      summary, worked out once a generation;
--   E  the By reputation grouping;
--   F  the map drawer: the badge (maximized only), the tooltip, the
--      waypoint's note;
--   G  the quest dialog;
--   H  THE CROSS-SURFACE CHECK: for each quest, the Log, the Zones row badge,
--      tooltip and briefing, the drawer's badge and tooltip, the waypoint's
--      note and the NPC dialog show the same number -- and still do when the
--      Wickerman changes it, and when a sample seen in game replaces it;
--   I  hygiene: no global beyond the module's documented ones, no glyph, no
--      error, no forbidden Questie call.
--
--   luajit Commander_QuestLog/Harness/questlog_rep_everywhere_harness.lua
--   CQL_WITH_REPS=1 luajit ...    -- also load CommanderQuestLogReputations.lua
--   CQL_UI= / CQL_ZONES= / CQL_QUESTFRAME= / CQL_MAP=/path/copy.lua luajit ...   -- a mutated copy

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local MODULE = ADDONS .. "/Commander_QuestLog/"

local mock = dofile(MODULE .. "Harness/questlog_mock.lua")
local Fake = dofile(MODULE .. "Harness/fake_questie.lua")
local QF = dofile(MODULE .. "Harness/questframe_mock.lua")
local CHECK, Done = mock.Checker()
local RunTimers = mock.RunTimers

-- ===========================================================================
-- Boot
-- ===========================================================================

-- The reputation world, with four quests in the log: 9355 (250 Honor Hold),
-- 91001 (pays nothing), 91002 (100 Honor Hold, and a row for a faction with
-- no standing slot), 10325 (the Aldor, with the rival's loss and the Sha'tar's
-- spillover)
local world = Fake.RepWorld()
for _, id in ipairs({ 9355, 91001, 91002, 10325 }) do world.log[id] = true end
local fake = Fake.Install(world)
Fake.InstallClient(world)

local dialog = QF.Install(mock)
local frames = dialog.frames

local orders = {}
CommanderOrders = {
    IsAvailable = function() return true end,
    Add = function(spec) orders[#orders + 1] = spec; return "w" .. #orders end,
    AddRoute = function(spec) orders[#orders + 1] = { route = spec }; return "r" .. #orders end,
    RegisterResolver = function() return true end,
}

-- A world map just big enough for the drawer: a ScrollContainer, a map id, a
-- maximized flag, the two methods the drawer post-hooks. No pin pools (the
-- map harness has the pins).
local map = CreateFrame("Frame", nil, UIParent)
map:Hide()
local container = CreateFrame("Frame", nil, map)
container:SetSize(1000, 600)
map.ScrollContainer = container
local mapState = { mapID = 1944, maximized = true }
map.GetMapID = function() return mapState.mapID end
map.SetMapID = function(self, id) mapState.mapID = id; self:OnMapChanged() end
map.OnMapChanged = function() end
map.SynchronizeDisplayState = function() end
map.IsMaximized = function() return mapState.maximized end
WorldMapFrame = map

mock.LoadFramework()
local FILES = { "CommanderQuestLogDB.lua", "CommanderQuestLogModel.lua", "CommanderQuestLogReputationData.lua",
    "CommanderQuestLogCompletion.lua", "CommanderQuestLogStanding.lua", "CommanderQuestLogQuestie.lua",
    "CommanderQuestLogUI.lua", "CommanderQuestLogCatalogue.lua", "CommanderQuestLogZones.lua" }
if os.getenv("CQL_WITH_REPS") then FILES[#FILES + 1] = "CommanderQuestLogReputations.lua" end
FILES[#FILES + 1] = "CommanderQuestLogQuestFrame.lua"
FILES[#FILES + 1] = "CommanderQuestLogMap.lua"
-- Mutation hooks: a copy of a file in place of the live one
local OVERRIDE = {
    ["CommanderQuestLogUI.lua"] = os.getenv("CQL_UI"), ["CommanderQuestLogZones.lua"] = os.getenv("CQL_ZONES"),
    ["CommanderQuestLogQuestFrame.lua"] = os.getenv("CQL_QUESTFRAME"), ["CommanderQuestLogMap.lua"] = os.getenv("CQL_MAP"),
}
local globalsBefore = {}
for key in pairs(_G) do globalsBefore[key] = true end
for _, file in ipairs(FILES) do mock.Load(OVERRIDE[file] or (MODULE .. file)) end
mock.Login()

mock.state.log = {
    mock.Header("Hellfire Peninsula"),
    mock.Quest({ title = "A Job for an Intelligent Man", level = 61, questID = 9355, money = 12000,
        objectives = { { text = "Scout the Legion camp: 0/1", finished = false } } }),
    mock.Quest({ title = "Scout the Perimeter", level = 61, questID = 91001, objectives = {} }),
    mock.Quest({ title = "A Strange Debt", level = 61, questID = 91002, objectives = {} }),
    mock.Header("Shattrath City"),
    mock.Quest({ title = "Marks of Kil'jaeden", level = 65, questID = 10325, objectives = {},
        rewards = { { name = "Aldor Tabard", texture = "t", quality = 1, id = 31779 } } }),
}
local function Settle() for _ = 1, 8 do RunTimers(1) end end
Settle()

local Q = CommanderQuestLog
local A, R, Z, M = Q.Questie, Q.Standing, Q.Zones, Q.Map
local kit = Q._kit
local db = CommanderQuestLogDB
CHECK(A.State() == "READY" and A.RepMultiplier() == 110, "boot: Questie ready, the rules loaded, a Human at 110%",
    A.State() .. " " .. tostring(A.RepMultiplier()))

-- ===========================================================================
-- Readers
-- ===========================================================================

local drawn = {}
local function Note(text) if type(text) == "string" then drawn[#drawn + 1] = text end end

local function Shown(blocks)
    local out = {}
    for _, fs in ipairs(blocks) do
        if fs:IsShown() and fs:GetText() then out[#out + 1] = fs:GetText(); Note(fs:GetText()) end
    end
    return out
end
local function Has(lines, text)
    for _, line in ipairs(lines) do
        if line:find(text, 1, true) then return line end
    end
    return nil
end
local function Same(lines, text)
    for _, line in ipairs(lines) do if line == text then return true end end
    return false
end
-- The shown block whose text is exactly `text`, and its TOPLEFT offsets
local function Block(blocks, text)
    for _, fs in ipairs(blocks) do
        if fs:IsShown() and fs:GetText() == text then
            local p = fs.__points and fs.__points[1] or {}
            return fs, p.x, p.y
        end
    end
    return nil
end
local function Lum(c) return c and (c[1] * 0.299 + c[2] * 0.587 + c[3] * 0.114) end
local function SameColour(c, r, g, b)
    return type(c) == "table" and math.abs(c[1] - r) < 1e-6 and math.abs(c[2] - g) < 1e-6 and math.abs(c[3] - b) < 1e-6
end
local INK_MAX = 0.34 + 0.001

local W = Z._Widgets()
local function ZoneRow(id)
    for _, row in ipairs(W.rows) do
        if row:IsShown() and row.entry and row.entry.id == id then return row end
    end
    return nil
end
local function ZoneHeader(title)
    for _, row in ipairs(W.rows) do
        if row:IsShown() and row.headerTitle == title then return row end
    end
    return nil
end
local function Badge(row)
    if row and row.badge and row.badge:IsShown() then return row.badge:GetText() end
    return nil
end
local function Tip(row)
    row:GetScript("OnEnter")(row)
    for _, line in ipairs(GameTooltip.__lines) do Note(line) end
    return GameTooltip.__lines
end

local function DrawerRow(id)
    for _, row in ipairs(M._Rows()) do
        if row.__shown and row.item and row.item.kind == "QUEST" and row.item.entry.id == id then return row end
    end
    return nil
end
local function DrawerBadge(row)
    if row and row.badge and row.badge.__shown then return row.badge:GetText() end
    return nil
end

-- The Log, on the quest with this title: its briefing's lines
local function LogBrief(title)
    db.ViewMode = "LOG"
    CommanderQuestLog_Show()
    Q.Select(title)
    return Shown(Q._DetailStrings())
end
local function LogBlocks() return Q._DetailStrings() end

-- The Zones tab on a zone, a quest selected (nil: the overview)
local function ZoneOn(areaId, questId)
    CommanderQuestLog_OpenToZone(areaId)
    Z.Select(questId)
    return Shown(W.blocks)
end

-- The REPUTATION section of a Zones briefing: the lines under its heading
local function RepSection(lines)
    local out, inside = {}, false
    for _, line in ipairs(lines) do
        if line == "REPUTATION" then
            inside = true
        elseif inside then
            if line:match("^[A-Z][A-Z ]+$") then break end
            out[#out + 1] = line
        end
    end
    return out
end

-- "+275 The Aldor  -302 The Scryers" from the section's effect lines: each
-- line's part before its notes, the multiplier's footnote left out
local function EffectsAsLine(section)
    local parts = {}
    for _, line in ipairs(section) do
        if not line:find("^Paid at") then parts[#parts + 1] = (line:gsub("  \194\183  .*$", "")) end
    end
    return table.concat(parts, "  ")
end

local function Refresh()
    A.Bump("harness")
    Settle()
    Q.Refresh()
end

-- "Reputation: L", or "No reputation" as it is
local function Phrase(line)
    if line == R.NO_REPUTATION then return line end
    return "Reputation: " .. line
end

-- ===========================================================================
-- A. The Log's briefing
-- ===========================================================================

do
    local brief = LogBrief("A Job for an Intelligent Man")
    CHECK(Same(brief, "Reputation: +275 Honor Hold"), "A: the Log says what 9355 is worth: +275 Honor Hold for a Human",
        table.concat(brief, " | "))
    local _, x, y = Block(LogBlocks(), "Reputation: +275 Honor Hold")
    local _, _, rewardsY = Block(LogBlocks(), "REWARDS")
    local _, _, moneyY = Block(LogBlocks(), "Money: 12000c")
    CHECK(rewardsY and moneyY and y and y < moneyY and moneyY < rewardsY,
        "A: ...as a reward line under REWARDS, after the money", tostring(y) .. " " .. tostring(moneyY))
    CHECK(x == kit.PAD + 6, "A: ...indented like the money line", x)

    brief = LogBrief("Scout the Perimeter")
    CHECK(Same(brief, "No reputation"), "A: a quest that pays nothing says No reputation", table.concat(brief, " | "))
    local _, _, noneY = Block(LogBlocks(), "No reputation")
    local _, _, turnInY = Block(LogBlocks(), "Turn in: Force Commander Danath \226\128\148 Hellfire Peninsula (56.6, 66.4)")
    local _, _, objectivesY = Block(LogBlocks(), "OBJECTIVES")
    CHECK(noneY and turnInY and objectivesY and noneY < turnInY and noneY > objectivesY,
        "A: ...under the facts (and the Turn in line) when there is no REWARDS section",
        tostring(noneY) .. " " .. tostring(turnInY) .. " " .. tostring(objectivesY))
    local none = Block(LogBlocks(), "No reputation")
    local primary, secondary = { kit.Ink("primary") }, { kit.Ink("secondary") }
    CHECK(none and SameColour(none.__color, kit.Paper(secondary[1], secondary[2], secondary[3])),
        "A: ...in the secondary ink")

    brief = LogBrief("A Strange Debt")
    CHECK(Same(brief, "Reputation: +110 Honor Hold"),
        "A: a row for a faction with no standing slot is dropped (+110 Honor Hold only)", table.concat(brief, " | "))
    brief = LogBrief("Marks of Kil'jaeden")
    CHECK(Same(brief, "Reputation: +275 The Aldor  -302 The Scryers  +137 The Sha'tar"),
        "A: every faction it moves: the Aldor, the rival's loss, the Sha'tar's spillover", table.concat(brief, " | "))

    -- The rewards switched off: the line moves under the facts
    db.ShowRewards = false
    LogBrief("A Job for an Intelligent Man")
    local _, _, offY = Block(LogBlocks(), "Reputation: +275 Honor Hold")
    local _, _, objY = Block(LogBlocks(), "OBJECTIVES")
    CHECK(offY and objY and offY > objY, "A: with Show Rewards off it sits under the facts", tostring(offY))
    db.ShowRewards = nil

    -- The switch
    db.ShowRepEverywhere = false
    brief = LogBrief("A Job for an Intelligent Man")
    CHECK(not Has(brief, "Reputation") and not Same(LogBrief("Scout the Perimeter"), "No reputation"),
        "A: Reputation on Every Quest off: no line on the Log")
    db.ShowRepEverywhere = nil

    -- Ink on paper
    db.FrameStyle = "PARCHMENT"
    LogBrief("A Job for an Intelligent Man")
    local line = Block(LogBlocks(), "Reputation: +275 Honor Hold")
    CHECK(line and Lum(line.__color) <= INK_MAX, "A: on paper the line is ink", line and Lum(line.__color))
    local paperInk = { kit.Ink("primary") }
    CHECK(line and SameColour(line.__color, kit.Paper(paperInk[1], paperInk[2], paperInk[3])),
        "A: ...the paper's primary ink")
    db.FrameStyle = nil
    Q.Refresh()

    -- The Log's own Waypoint carries the note
    LogBrief("A Job for an Intelligent Man")
    local before = #orders
    Q.LogWaypoint()
    CHECK(#orders == before + 1 and orders[#orders].note == "+275 Honor Hold" and orders[#orders].key == "quest:9355",
        "A: the Log's waypoint to the turn-in is noted with what it pays", orders[#orders] and orders[#orders].note)
end

-- ===========================================================================
-- B. The Zones tab's rows
-- ===========================================================================

do
    db.ZoneGroup = "GUIDE"
    ZoneOn(3483)
    CHECK(Q.ViewMode() == "ZONE" and Z._State().key == 3483, "B: the Zones tab on Hellfire Peninsula")
    CHECK(Badge(ZoneRow(9355)) == "+275 HH", "B: 9355's row: +275, and the faction it is for (HH)", Badge(ZoneRow(9355)))
    CHECK(Badge(ZoneRow(91002)) == "+110 HH", "B: 91002's row: +110 HH", Badge(ZoneRow(91002)))
    CHECK(Badge(ZoneRow(91001)) == "0", "B: a quest that pays nothing: 0", Badge(ZoneRow(91001)))
    CHECK(Badge(ZoneRow(10937)) == "+1,100 HH", "B: a done quest keeps what it was worth: +1,100 HH", Badge(ZoneRow(10937)))
    CHECK(Badge(ZoneRow(10106)) == "+165 HH", "B: a daily: +165 a turn-in", Badge(ZoneRow(10106)))
    -- the brief's surprise: a quest whose best gain is ANOTHER faction's must
    -- not read like an Honor Hold quest beside them
    CHECK(Badge(ZoneRow(11354)) == "+385 Cons", "B: an audited Wanted daily: its biggest direct gain, named (the Consortium's +385)",
        Badge(ZoneRow(11354)))
    -- A badge is held to 12 characters, so the 64-px cap never cuts the tag
    -- it carries: the comma goes first, then the tag to four letters
    -- (2026-10-05 review: "+1,000 Scryers" on Varedis Must Be Stopped)
    local fit = Q.Catalogue.RepBadgeText
    CHECK(fit(R, 1000, "Scryers") == "+1000 Scry" and fit(R, 2000, "Mag'har") == "+2000 Mag"
        and fit(R, 1000, "Thrall") == "+1000 Thrall" and fit(R, 385, "Scryers") == "+385 Scryers"
        and fit(R, 42000, "Neth") == "+42,000 Neth" and fit(R, 1100, "HH") == "+1,100 HH"
        and fit(R, -1000, "Scryers") == "-1000 Scry" and fit(R, 1000, nil) == "+1,000"
        and fit(R, 1000, "\208\159\209\128\208\190\208\178\208\184\208\180\209\134\209\139") == "+1000 \208\159\209\128\208\190\208\178",
        "B: the badge's fit: whole up to 12 characters, then no comma, then a four-letter tag (UTF-8 safe)",
        fit(R, 1000, "Scryers") .. " / " .. fit(R, 2000, "Mag'har"))
    ZoneOn(3703)
    CHECK(Badge(ZoneRow(10552)) == "+3850 Scry" and Badge(ZoneRow(10551)) == "+3,850 Aldor"
        and Badge(ZoneRow(10886)) == "+550 Sha'tar",
        "B: Shattrath: Allegiance to the Scryers reads +3850 Scry, never \"+3,850 Scryers\" cut by the cap",
        tostring(Badge(ZoneRow(10552))))
    ZoneOn(3483)
    local row = ZoneRow(9355)
    local point = row and row.badge.__points[1]
    CHECK(point and point.point == "RIGHT" and point.rel == row.state, "B: the badge sits left of the state word")
    local accent = { kit.Accent() }
    CHECK(row and SameColour(row.badge.__color, kit.Paper(accent[1], accent[2], accent[3])),
        "B: a gain is in the accent, through Paper()")
    local zero = ZoneRow(91001)
    local faint = { kit.Ink("faint") }
    CHECK(zero and SameColour(zero.badge.__color, kit.Paper(faint[1], faint[2], faint[3])), "B: a 0 is faint")
    CHECK(zero and zero.entry.counted and not SameColour(zero.title.__color, kit.Paper(faint[1], faint[2], faint[3])),
        "B: ...but a quest worth 0 that counts is never dimmed for it (dim means not counted here)")
    -- The tooltip
    local tip = Tip(row)
    CHECK(Has(tip, "Reputation: +275 Honor Hold"), "B: the row's tooltip carries the whole line", table.concat(tip, " | "))
    tip = Tip(zero)
    CHECK(Same(tip, "No reputation"), "B: ...No reputation included", table.concat(tip, " | "))
    -- The switches
    db.ZoneRowRep = false
    Q.Refresh()
    CHECK(Badge(ZoneRow(9355)) == nil and Badge(ZoneRow(91001)) == nil, "B: Reputation on Zone Rows off: no badges")
    CHECK(Has(Tip(ZoneRow(9355)), "Reputation: +275 Honor Hold"), "B: ...the tooltip keeps its line")
    db.ZoneRowRep = nil
    db.ShowRepEverywhere = false
    Q.Refresh()
    CHECK(Badge(ZoneRow(9355)) == nil and not Has(Tip(ZoneRow(9355)), "Reputation"),
        "B: Reputation on Every Quest off: no badge, no tooltip line")
    db.ShowRepEverywhere = nil
    Q.Refresh()
    CHECK(Badge(ZoneRow(9355)) == "+275 HH", "B: ...and back")
    -- The tooltip is the game's dark one on either sheet: its line is a
    -- light literal, never the parchment's dark ink
    db.FrameStyle = "PARCHMENT"
    Q.Refresh()
    local parchTip = Tip(ZoneRow(9355))
    local repColour
    for index, line in ipairs(parchTip) do
        if line == "Reputation: +275 Honor Hold" then repColour = GameTooltip.__colors[index] end
    end
    CHECK(repColour and Lum(repColour) >= 0.7, "B: on the parchment the tooltip's line is still light on the dark tooltip",
        repColour and Lum(repColour))
    db.FrameStyle = nil
    Q.Refresh()
end

-- ===========================================================================
-- C. The Zones briefing's REPUTATION
-- ===========================================================================

do
    local section = RepSection(ZoneOn(3483, 9355))
    CHECK(section[1] == "+275 Honor Hold" and section[2] == "Paid at 110% (Diplomacy).",
        "C: 9355: its effect, and the multiplier behind it", table.concat(section, " | "))
    section = RepSection(ZoneOn(3483, 91001))
    CHECK(section[1] == "No reputation" and #section == 2, "C: 91001: No reputation", table.concat(section, " | "))
    section = RepSection(ZoneOn(3703, 10325))
    CHECK(section[1] == "+275 The Aldor" and section[2] == "-302 The Scryers  \194\183  rival"
        and section[3] == "+137 The Sha'tar  \194\183  spillover",
        "C: 10325: direct, the rival's loss and the spillover, each named for what it is", table.concat(section, " | "))
    local scryers = Block(W.blocks, "-302 The Scryers  \194\183  rival")
    local bad = { Q.Catalogue.ToneRGB("bad") }
    CHECK(scryers and SameColour(scryers.__color, kit.Paper(bad[1], bad[2], bad[3])), "C: ...a loss in the bad tone")
    -- capped: the Aldor near the quest's 8,999 clamp (10326: More Marks)
    fake.SetRep(932, 8900)
    Refresh()
    section = RepSection(ZoneOn(3703, 10326))
    CHECK(section[1] == "+99 The Aldor  \194\183  this quest stops at 8,999" and section[2] == "-108 The Scryers  \194\183  rival"
        and section[3] == "+49 The Sha'tar  \194\183  spillover",
        "C: at 8,900 the marks pay +99 and stop; the spillover and the loss come from the +99",
        table.concat(section, " | "))
    fake.SetRep(932, 4000)
    -- the Sha'tar's window shut (Honored): shown as 0 with why, never hidden
    fake.SetRep(935, 9500)
    Refresh()
    section = RepSection(ZoneOn(3703, 10325))
    CHECK(Same(section, "0 The Sha'tar  \194\183  spillover, no spillover above Friendly"),
        "C: a spill window that is shut is shown as 0 with its reason", table.concat(section, " | "))
    CHECK(A.RepLine(10325) == "+275 The Aldor  -302 The Scryers",
        "C: ...which the one-line form leaves out", A.RepLine(10325))
    fake.SetRep(935, 2000)
    -- the Wickerman
    world.player.auras[24705] = true
    Refresh()
    section = RepSection(ZoneOn(3483, 9355))
    CHECK(section[1] == "+300 Honor Hold" and section[2] == "Paid at 120% (Diplomacy, Invocation of the Wickerman).",
        "C: under the Wickerman: 120%, and why", table.concat(section, " | "))
    world.player.auras[24705] = nil
    Refresh()
    -- Where it sits: straight under the quest's reason, before WHERE (a
    -- chain of thirty would push it out of the pane)
    local function IndexOf(lines, text)
        for i, line in ipairs(lines) do if line == text then return i end end
        return nil
    end
    local brief = ZoneOn(3483, 9355)
    local repAt, whereAt = IndexOf(brief, "REPUTATION"), IndexOf(brief, "WHERE")
    CHECK(repAt and whereAt and repAt < whereAt and repAt == 4,
        "C: the REPUTATION section comes straight under the title, facts and reason, before WHERE",
        tostring(repAt) .. " " .. tostring(whereAt))
    -- Reputation on Every Quest off: the briefing is 1.5.0's -- Questie's raw
    -- rows, at the end -- never the engine's figures
    db.ShowRepEverywhere = false
    Q.Refresh()
    brief = ZoneOn(3483, 9355)
    section = RepSection(brief)
    repAt, whereAt = IndexOf(brief, "REPUTATION"), IndexOf(brief, "WHERE")
    CHECK(Same(section, "+250  Honor Hold") and not Has(section, "+275") and not Has(section, "Paid at")
        and repAt and whereAt and repAt > whereAt,
        "C: Reputation on Every Quest off: Questie's own row (+250), at the end, no engine figure",
        table.concat(section, " | "))
    db.ShowRepEverywhere = nil
    Q.Refresh()
end

-- ===========================================================================
-- D. REPUTATION IN THIS ZONE
-- ===========================================================================

do
    local WANTED_HH = "4 rotating Wanted dailies here, up to +385 on a day one is offered (one normal and one heroic a day in all)."
    local lines = ZoneOn(3483)
    local at, nextUp, uncounted
    for i, line in ipairs(lines) do
        if line == "REPUTATION IN THIS ZONE" then at = i end
        if line == "NEXT UP" then nextUp = i end
        if line:find("(not counted)", 1, true) then uncounted = i end
    end
    CHECK(at ~= nil, "D: Hellfire's overview has the section", table.concat(lines, " | "))
    at = at or 0
    -- up front: right under the zone's completion, before NEXT UP and the
    -- chains (a 410-px pane holds little more than those in Hellfire)
    CHECK(uncounted and at == uncounted + 1 and nextUp and nextUp > at,
        "D: the section comes straight under the zone's completion, before NEXT UP",
        tostring(uncounted) .. " " .. tostring(at) .. " " .. tostring(nextUp))
    CHECK(lines[at + 1] == "Honor Hold  \194\183  Friendly 1,000 / 6,000", "D: Honor Hold first, with its standing",
        lines[at + 1])
    CHECK(lines[at + 2] == "+385 left in 2 quests  \194\183  about +1,100 done in 1 quest",
        "D: what is left once-only, and an estimate of what was done", lines[at + 2])
    CHECK(lines[at + 3] == "Quests here take it to Friendly 1,385 / 6,000: 4,615 short of Honored.",
        "D: whether it reaches the next standing: not here", lines[at + 3])
    CHECK(lines[at + 4] == "1 daily here, +165 a turn-in.",
        "D: then its dailies: the steady one alone, its own +165 (a Wanted heroic is no daily income)", lines[at + 4])
    CHECK(lines[at + 5] == WANTED_HH,
        "D: ...the rotating Wanted dailies apart, never counted as a daily a day", lines[at + 5])
    CHECK(lines[at + 6] == "The Consortium  \194\183  Neutral 2,200 / 3,000" and lines[at + 7] == "No one-time quest left"
        and lines[at + 8] == WANTED_HH,
        "D: the Consortium: only its Wanted dailies here", tostring(lines[at + 8]))
    CHECK(lines[at + 9] == "NEXT UP", "D: and nothing for the other side's Thrallmar", tostring(lines[at + 9]))
    local verdict = Block(W.blocks, "Quests here take it to Friendly 1,385 / 6,000: 4,615 short of Honored.")
    CHECK(verdict and verdict.__points[1].x == kit.PAD + 12, "D: the detail lines sit under their faction")
    local honor, _, honorY = Block(W.blocks, "Honor Hold  \194\183  Friendly 1,000 / 6,000")
    local strong = { kit.Ink("strong") }
    CHECK(honor and SameColour(honor.__color, kit.Paper(strong[1], strong[2], strong[3])), "D: a faction's line in the strong ink")
    local _, _, steadyY = Block(W.blocks, "1 daily here, +165 a turn-in.")
    local _, _, consY = Block(W.blocks, "The Consortium  \194\183  Neutral 2,200 / 3,000")
    local _, _, leftY = Block(W.blocks, "+385 left in 2 quests  \194\183  about +1,100 done in 1 quest")
    local wantedY
    for _, fs in ipairs(W.blocks) do
        if fs:IsShown() and fs:GetText() == WANTED_HH and not wantedY then wantedY = fs.__points[1].y end
    end
    CHECK(honorY and leftY and steadyY and wantedY and consY and (wantedY - consY) - (honorY - leftY) == 4,
        "D: a little air before the next faction", tostring(wantedY) .. " " .. tostring(consY))

    lines = ZoneOn(3703)
    CHECK(Has(lines, "The Sha'tar  \194\183  Neutral 2,000 / 3,000")
        and Same(lines, "+879 left in 1 quest, spillover included")
        and Same(lines, "Quests here take it to Neutral 2,879 / 3,000: 121 short of Friendly.")
        and Same(lines, "Of that, +329 spills over from the Aldor's quests here, only while Friendly or below."),
        "D: Shattrath: the Sha'tar with the window from the Aldor's quests (\"the Aldor's\", mid-sentence), and while it lasts",
        table.concat(lines, " | "))
    CHECK(Same(lines, "3 repeatables here, up to +385 a turn-in."), "D: ...the Aldor's repeatables")
    CHECK(Same(lines, "1 rotating Wanted daily here, +275 on a day it is offered (one normal and one heroic a day in all).")
        and not Has(lines, "1 daily here"), "D: ...and a Wanted daily given out in Shattrath is a rotating one, not a daily")

    -- The spill window shut, or about to: what lands, never the raw sum
    fake.SetRep(935, 8500)
    Refresh()
    lines = ZoneOn(3703)
    CHECK(Same(lines, "Of that, +329 spills over from the Aldor's quests here, only while Friendly or below.")
        and Same(lines, "Quests here reach Honored 379 / 12,000, 32,621 short of Exalted."),
        "D: the Sha'tar at Friendly 5,500: the window lands all 329 before it shuts, and Honored is reached",
        table.concat(lines, " | "))
    fake.SetRep(935, 9500)
    Refresh()
    lines = ZoneOn(3703)
    CHECK(Same(lines, "+550 left in 1 quest") and not Has(lines, "spills over") and not Has(lines, "spillover included"),
        "D: the Sha'tar at Honored: the window has shut, so no spillover is claimed", table.concat(lines, " | "))
    fake.SetRep(935, 2000)
    Refresh()
    -- The zone totals' raw spill sum adds both rival sources and ignores the
    -- window; the lines are the projection's (a totals table where the two
    -- differ, as the real Shattrath's do: 2,867 summed, 2,730 landed)
    do
        local real = A.ZoneRepTotals
        A.ZoneRepTotals = function()
            return { {
                factionId = 935, name = "The Sha'tar", value = 1000, met = true, rank = 3, word = "Neutral",
                remainingOnce = 2730, leftCount = 3, doneOnce = 0, doneCount = 0, repeatables = {},
                repeatablesPerTurnIn = 0, viaSpill = 2867, reach = 3730, reachRank = 4, reachesNext = true,
                reachesExalted = false,
                projection = { order = { 10886 }, unreached = {}, lockedOut = {}, orderHints = {}, left = 2730,
                    reach = 3730, spillWindow = { from = 1000, total = 2867, landed = 2180, lost = 687,
                    to = 8999, ["until"] = 8999, source = 934 } },
            }, {
                factionId = 946, name = "Honor Hold", value = 6000, met = true, rank = 5, word = "Honored",
                remainingOnce = 5417, leftCount = 14, extraCount = 6, extraLeft = 2255, doneOnce = 0, doneCount = 0,
                repeatables = {}, repeatablesPerTurnIn = 0, viaSpill = 0, reach = 11417, reachRank = 5,
                reachesNext = false, reachesExalted = false,
                projection = { order = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14 }, unreached = {}, lockedOut = {},
                    orderHints = {}, left = 5417, reach = 11417 },
            }, {
                factionId = 970, name = "Sporeggar", value = 500, met = false, rank = 3, word = "Neutral",
                remainingOnce = 0, leftCount = 2, doneOnce = 0, doneCount = 0, repeatables = {},
                repeatablesPerTurnIn = 0, viaSpill = 0, reach = 500, reachRank = 3,
                projection = { order = {}, unreached = { 9726, 9729 }, lockedOut = {}, orderHints = {}, left = 0, reach = 500 },
            } }
        end
        Refresh()
        lines = ZoneOn(3703)
        CHECK(Same(lines, "Of that, +2,180 spills over from the Scryers' quests here, only while Friendly or below.")
            and Same(lines, "+2,730 left in 1 quest, spillover included"),
            "D: the spill line is what the window LANDS from the source the projection chose (the Scryers'), never the raw sum",
            table.concat(lines, " | "))
        CHECK(Same(lines, "+5,417 left in 14 quests, +2,255 of it in dungeons"),
            "D: how much of what is left is the dungeon quests that start here", table.concat(lines, " | "))
        CHECK(Same(lines, "Nothing within reach yet") and not Same(lines, "0 left in 2 quests")
            and Same(lines, "2 quests here need a standing the quests here alone do not reach."),
            "D: quests that need a standing quests here never reach are said so, never \"0 left in 2 quests\"",
            table.concat(lines, " | "))
        A.ZoneRepTotals = real
        Refresh()
    end

    lines = ZoneOn(3518)
    CHECK(Same(lines, "+1,375 left in 4 quests") and Same(lines, "Quests here reach Friendly 575 / 6,000, 38,425 short of Exalted."),
        "D: Nagrand: the Consortium's quests reach Friendly, and how far that leaves Exalted", table.concat(lines, " | "))
    local hint = Block(W.blocks, "Do \"A Head Full of Ivory\" before Friendly, or it closes.")
    local warn = { Q.Catalogue.ToneRGB("warn") }
    CHECK(hint and SameColour(hint.__color, kit.Paper(warn[1], warn[2], warn[3]))
        and Same(lines, "Do \"Stealing from Thieves\" before Friendly, or it closes."),
        "D: ...and the two that close as it rises, to do first, in the warning tone")
    CHECK(Same(lines, "Kurenai (not met yet)  \194\183  Unfriendly 1,800 / 3,000")
        and Same(lines, "1 repeatable here, +550 a turn-in."),
        "D: a faction not met yet reads from its starting standing (Kurenai, -1,200)", table.concat(lines, " | "))
    CHECK(Same(lines, "1 daily here, +550 a turn-in, only while your side holds Halaa; not open to you yet."),
        "D: ...and Halaa's daily on a line of its own, with its condition, never counted with the steady ones")

    lines = ZoneOn(3520)
    CHECK(Same(lines, "Netherwing (not met yet)  \194\183  Hated 0 / 36,000") and Same(lines, "+42,000 left in 1 quest")
        and Same(lines, "Quests here reach Neutral 0 / 3,000, 42,000 short of Exalted."),
        "D: Shadowmoon: Ally of the Netherwing from Hated to Neutral 0", table.concat(lines, " | "))
    CHECK(Same(lines, "1 daily here, +275 a turn-in; none open to you yet."),
        "D: ...and a daily behind a standing is not one you can do yet", table.concat(lines, " | "))

    lines = ZoneOn(3519)
    CHECK(Same(lines, "Done here, nothing left: The Sha'tar (about +11)."),
        "D: a faction with nothing left here is one line at the end", table.concat(lines, " | "))

    -- At the ceiling (Exalted 999 / 1,000) every quest and daily here pays 0:
    -- Honor Hold is one name on one line, never "0 left in 2 quests", "0 a
    -- turn-in" or "up to 0"; just under it, what is left only fills Exalted's
    -- bar, which is never "Quests here reach Exalted" (2026-10-05 review)
    local function Zeros(list)
        for _, line in ipairs(list) do
            if line:find("^0 left in") or line:find(", 0 a turn-in", 1, true) or line:find("up to 0 ", 1, true) then
                return line
            end
        end
        return nil
    end
    fake.SetRep(946, 42999)
    Refresh()
    lines = ZoneOn(3483)
    CHECK(Same(lines, "Exalted, nothing more to earn here: Honor Hold.") and not Has(lines, "Honor Hold  \194\183  Exalted")
        and not Zeros(lines) and Same(lines, "The Consortium  \194\183  Neutral 2,200 / 3,000"),
        "D: Honor Hold at Exalted 999: one line, no zeros; the Consortium as before", table.concat(lines, " | "))
    fake.SetRep(946, 42500)
    Refresh()
    lines = ZoneOn(3483)
    CHECK(Same(lines, "Honor Hold  \194\183  Exalted 500 / 1,000") and Same(lines, "Already Exalted.")
        and not Same(lines, "Quests here reach Exalted.") and Same(lines, "+385 left in 2 quests  \194\183  about +1,100 done in 1 quest"),
        "D: Honor Hold at Exalted 500: what is left, and Already Exalted, never \"reach Exalted\"", table.concat(lines, " | "))
    fake.SetRep(946, 1000)
    Refresh()
    -- Below the ceiling a reward clamp can hold quests and repeatables to 0
    -- too: said in words, never as a 0
    do
        local real = A.ZoneRepTotals
        A.ZoneRepTotals = function()
            return { {
                factionId = 942, name = "Cenarion Expedition", value = 21000, met = true, rank = 6, word = "Revered",
                remainingOnce = 0, leftCount = 3, doneOnce = 0, doneCount = 0,
                repeatables = { { questId = 9784, perTurnIn = 0, open = true }, { questId = 9875, perTurnIn = 0, open = true },
                    { questId = 11502, perTurnIn = 0, open = true, daily = true, conditional = "HALAA" } },
                repeatablesPerTurnIn = 0, viaSpill = 0, reach = 21000, reachRank = 6,
                projection = { order = { 1, 2, 3 }, unreached = {}, lockedOut = {}, orderHints = {}, left = 0, reach = 21000 },
            }, {
                factionId = 946, name = "Honor Hold", value = 42999, met = true, rank = 7, word = "Exalted",
                remainingOnce = 0, leftCount = 2, doneOnce = 1100, doneCount = 1, repeatables = {},
                repeatablesPerTurnIn = 0, viaSpill = 0, reach = 42999, reachRank = 7,
                projection = { order = { 1, 2 }, unreached = {}, lockedOut = {}, orderHints = {}, left = 0, reach = 42999 },
            }, {
                factionId = 978, name = "Kurenai", value = 42999, met = true, rank = 7, word = "Exalted",
                remainingOnce = 0, leftCount = 0, doneOnce = 0, doneCount = 0,
                repeatables = { { questId = 10477, perTurnIn = 0, open = true } },
                repeatablesPerTurnIn = 0, viaSpill = 0, reach = 42999, reachRank = 7,
                projection = { order = {}, unreached = {}, lockedOut = {}, orderHints = {}, left = 0, reach = 42999 },
            } }
        end
        Refresh()
        lines = ZoneOn(3483)
        CHECK(Same(lines, "3 quests left, none pays anything more")
            and Same(lines, "2 repeatables here, none paying anything more at your standing.")
            and Same(lines, "1 daily here, paying nothing more at your standing, only while your side holds Halaa.")
            and Same(lines, "Exalted, nothing more to earn here: Honor Hold, Kurenai.") and not Zeros(lines),
            "D: quests and repeatables held to nothing say so, and two factions at the ceiling share one line",
            table.concat(lines, " | "))
        A.ZoneRepTotals = real
        Refresh()
    end

    -- once a generation: the projection is not redrawn on every log tick
    local calls, real = 0, A.ZoneRepTotals
    A.ZoneRepTotals = function(...) calls = calls + 1; return real(...) end
    Refresh()
    ZoneOn(3483)
    local after = calls
    Q.Refresh()
    Q.Refresh()
    CHECK(after >= 1 and calls == after, "D: worked out once a generation, whatever redraws", calls)
    -- nothing that pays
    A.ZoneRepTotals = function() calls = calls + 1; return {} end
    Refresh()
    CHECK(Same(ZoneOn(3483), "No quest here pays this character reputation."), "D: a zone where nothing pays says so")
    A.ZoneRepTotals = real
    Refresh()
    db.ShowRepEverywhere = false
    CHECK(not Same(ZoneOn(3483), "REPUTATION IN THIS ZONE"), "D: Reputation on Every Quest off: no section")
    db.ShowRepEverywhere = nil
end

-- ===========================================================================
-- E. By reputation
-- ===========================================================================

do
    db.ZoneGroup = "BYREP"
    ZoneOn(3483)
    local headers, order = {}, {}
    for _, row in ipairs(W.rows) do
        if row:IsShown() and row.headerTitle then headers[#headers + 1] = row.headerTitle end
    end
    CHECK(table.concat(headers, ",") == "Honor Hold,The Consortium,No reputation",
        "E: one heading per primary faction, the biggest earner first, No reputation last", table.concat(headers, ","))
    local inHonor = false
    for _, row in ipairs(W.rows) do
        if row:IsShown() then
            if row.headerTitle then inHonor = row.headerTitle == "Honor Hold"
            elseif inHonor then order[#order + 1] = row.entry.id end
        end
    end
    CHECK(table.concat(order, ",") == "10937,9355,10106,91002", "E: inside, the biggest gain first",
        table.concat(order, ","))
    CHECK(ZoneHeader("Honor Hold").state:GetText() == "4" and ZoneRow(91001).entry.header == "No reputation",
        "E: a heading counts its quests; a quest that pays nothing is under No reputation")
    local header = ZoneHeader("Honor Hold")
    header:GetScript("OnClick")(header, "LeftButton")
    CHECK(db.ZoneCollapsed["Honor Hold"] == true and ZoneRow(9355) == nil, "E: the faction's name is its fold key")
    header = ZoneHeader("Honor Hold")
    header:GetScript("OnClick")(header, "LeftButton")
    CHECK(ZoneRow(9355) ~= nil, "E: ...and opens again")
    -- the dropdown lists it
    local listed = {}
    local realAdd = UIDropDownMenu_AddButton
    UIDropDownMenu_AddButton = function(info) listed[#listed + 1] = info.text end
    W.groupDrop.__init(W.groupDrop)
    UIDropDownMenu_AddButton = realAdd
    CHECK(listed[#listed] == "By reputation", "E: By reputation is in the grouping dropdown", table.concat(listed, ","))
    db.ZoneGroup = "GUIDE"
    Q.Refresh()
end

-- ===========================================================================
-- F. The map drawer
-- ===========================================================================

do
    mapState.mapID = 1944
    map:Show()
    CHECK(M.IsBuilt() and M._State().width == 250, "F: the drawer on the maximized map")
    local row = DrawerRow(9355)
    CHECK(DrawerBadge(row) == "+275 HH", "F: the maximized drawer's row carries the badge, the faction named", DrawerBadge(row))
    CHECK(DrawerBadge(DrawerRow(91001)) == "0", "F: ...0 for a quest that pays nothing")
    CHECK(row and row.title:GetWidth() == (250 - 12 - 6) - 26 - (42 + 4) - (40 + 4),
        "F: ...and the title gives up its width", row and row.title:GetWidth())
    local tip = Tip(row)
    CHECK(Same(tip, "Reputation: +275 Honor Hold"), "F: the drawer's tooltip carries the line", table.concat(tip, " | "))
    CHECK(Same(Tip(DrawerRow(91001)), "No reputation"), "F: ...No reputation included")
    local before = #orders
    row:GetScript("OnClick")(row, "RightButton")
    CHECK(#orders == before + 1 and orders[#orders].note == "+275 Honor Hold",
        "F: a waypoint from the drawer is noted", orders[#orders] and orders[#orders].note)
    -- windowed: 30 px narrower, no badge
    mapState.maximized = false
    map:SynchronizeDisplayState()
    row = DrawerRow(9355)
    CHECK(M._State().width == 220 and DrawerBadge(row) == nil and row.title:GetWidth() == (220 - 12 - 6) - 26 - (42 + 4),
        "F: the windowed drawer has no badge and the title its full width", row and row.title:GetWidth())
    CHECK(Same(Tip(row), "Reputation: +275 Honor Hold"), "F: ...the tooltip keeps the line")
    mapState.maximized = true
    map:SynchronizeDisplayState()
    db.ShowRepEverywhere = false
    M.Refresh()
    CHECK(DrawerBadge(DrawerRow(9355)) == nil and not Has(Tip(DrawerRow(9355)), "Reputation"),
        "F: Reputation on Every Quest off: no badge, no line")
    db.ShowRepEverywhere = nil
    db.ZoneRowRep = false
    M.Refresh()
    CHECK(DrawerBadge(DrawerRow(9355)) == nil and Has(Tip(DrawerRow(9355)), "Reputation"),
        "F: Reputation on Zone Rows off takes the drawer's badge too, and leaves its tooltip")
    db.ZoneRowRep = nil
    M.Refresh()
    -- the drawer's badge has the tab's 64-px cap, and the tab's fit
    mapState.mapID = 1955
    M.Refresh()
    CHECK(DrawerBadge(DrawerRow(10552)) == "+3850 Scry" and DrawerBadge(DrawerRow(10886)) == "+550 Sha'tar",
        "F: Shattrath in the drawer: +3850 Scry, as on the tab", tostring(DrawerBadge(DrawerRow(10886))))
    mapState.mapID = 1944
    M.Refresh()
end

-- ===========================================================================
-- G. The quest dialog
-- ===========================================================================

do
    dialog.Offer({ id = 9355, title = "A Job for an Intelligent Man", money = 1200 })
    local _, text = Q.QuestFrame._Holder()
    CHECK(text and text:GetText() == "Reputation: +275 Honor Hold", "G: the NPC's dialog says the same",
        text and text:GetText())
    Note(text and text:GetText())
    dialog.Close()
end

-- ===========================================================================
-- H. The same quest, the same number, on every surface
-- ===========================================================================

local CASES = {
    { id = 9355, title = "A Job for an Intelligent Man", area = 3483, uiMap = 1944 },
    { id = 91001, title = "Scout the Perimeter", area = 3483, uiMap = 1944 },
    { id = 91002, title = "A Strange Debt", area = 3483, uiMap = 1944 },
    { id = 10325, title = "Marks of Kil'jaeden", area = 3703, uiMap = 1955 },
}

-- Every surface's answer for one quest, as drawn
local function Surfaces(case)
    local out = {}
    -- the Log's briefing
    local brief = LogBrief(case.title)
    out.log = Has(brief, "Reputation:") or (Same(brief, "No reputation") and "No reputation") or nil
    -- the Zones tab: the row's badge and tooltip, the briefing's effects
    ZoneOn(case.area, case.id)
    local row = ZoneRow(case.id)
    out.badge = Badge(row)
    local tip = row and Tip(row) or {}
    out.tip = Has(tip, "Reputation:") or (Same(tip, "No reputation") and "No reputation") or nil
    out.brief = EffectsAsLine(RepSection(Shown(W.blocks)))
    -- the Zones tab's Waypoint button
    local before = #orders
    W.waypointBtn:GetScript("OnClick")(W.waypointBtn)
    out.note = (#orders > before) and orders[#orders].note or nil
    -- the map drawer on the quest's zone
    mapState.mapID = case.uiMap
    M.Refresh()
    local drawerRow = DrawerRow(case.id)
    out.drawerBadge = DrawerBadge(drawerRow)
    local drawerTip = drawerRow and Tip(drawerRow) or {}
    out.drawerTip = Has(drawerTip, "Reputation:") or (Same(drawerTip, "No reputation") and "No reputation") or nil
    -- the NPC's dialog, offering it
    dialog.Offer({ id = case.id, title = case.title, money = 100 })
    local _, text = Q.QuestFrame._Holder()
    out.dialog = text and text:IsShown() and text:GetText() or nil
    dialog.Close()
    return out
end

-- The dialog's lines as the one line: a quest moving several factions has
-- them one per line under "Reputation:" (275 px wraps inside an effect),
-- and "(seen in game)" on that heading, for every line under it
local function Flat(text)
    if type(text) ~= "string" then return text end
    if text:find("^Reputation:\n") then return "Reputation: " .. (text:sub(13):gsub("\n", "  ")) end
    local seen = "Reputation (seen in game):\n"
    if text:sub(1, #seen) == seen then
        return "Reputation: " .. (text:sub(#seen + 1):gsub("\n", "  ")) .. " (seen in game)"
    end
    return text
end

local function Consistent(label, observed)
    for _, case in ipairs(CASES) do
        local line = A.RepLine(case.id)
        local effects = A.RepEffects(case.id)
        local primaryId, primary = R.Primary(effects)
        local phrase = Phrase(line) .. (observed and observed[case.id] and " (seen in game)" or "")
        -- the badge: the number, and the faction it is for
        local number = (primary and primary ~= 0) and R.FormatRep(primary) or "0"
        local badge = number == "0" and "0" or (number .. " " .. R.Abbrev(A.FactionName(primaryId)))
        local s = Surfaces(case)
        local id = label .. " " .. case.id .. ": "
        CHECK(s.log == phrase, id .. "the Log's briefing", s.log)
        CHECK(s.badge == badge and (line:sub(1, #number) == number or (line == R.NO_REPUTATION and badge == "0")),
            id .. "the Zones row's badge", s.badge)
        CHECK(s.tip == phrase, id .. "the Zones row's tooltip", s.tip)
        CHECK(s.brief == line or (line == R.NO_REPUTATION and s.brief == line), id .. "the Zones briefing's effects", s.brief)
        CHECK(s.note == line, id .. "the waypoint's note", s.note)
        CHECK(s.drawerBadge == badge, id .. "the map drawer's badge", s.drawerBadge)
        CHECK(s.drawerTip == phrase, id .. "the map drawer's tooltip", s.drawerTip)
        CHECK(Flat(s.dialog) == phrase and (s.dialog:find("\n", 1, true) ~= nil) == (line:find("  ", 1, true) ~= nil),
            id .. "the quest dialog (one faction a line when it moves several)", s.dialog)
    end
end

do
    db.ZoneGroup = "GUIDE"
    map:Show()
    Consistent("H")
    CHECK(A.RepLine(9355) == "+275 Honor Hold" and A.RepLine(91001) == "No reputation",
        "H: ...and the number is the rules engine's: +275 for a Human, not Questie's 250")
    -- the Wickerman moves every surface at once
    world.player.auras[24705] = true
    Refresh()
    CHECK(A.RepLine(9355) == "+300 Honor Hold", "H: the Wickerman: +300", A.RepLine(9355))
    Consistent("H (Wickerman)")
    world.player.auras[24705] = nil
    Refresh()
    -- a sample seen in game replaces the data everywhere
    -- (and one for a quest that moves several factions: the dialog puts the
    -- word on its heading, never on the last faction's line alone)
    CommanderQuestLogChar.RepObserved = {
        [9355] = { [946] = { raw = 200, n = 1, delta = 220, pct = 110, kind = "DIRECT" } },
        [10325] = { [932] = { raw = 250, n = 1, delta = 275, pct = 110, kind = "DIRECT" } },
    }
    Refresh()
    CHECK(A.RepLine(9355) == "+220 Honor Hold", "H: a sample seen in game: +220", A.RepLine(9355))
    Consistent("H (seen)", { [9355] = true, [10325] = true })
    dialog.Offer({ id = 10325, title = "Marks of Kil'jaeden", money = 100 })
    local _, seenText = Q.QuestFrame._Holder()
    seenText = seenText and seenText:GetText() or ""
    CHECK(seenText:find("^Reputation %(seen in game%):\n") and not seenText:find("%(seen in game%)$"),
        "H: several factions seen in game: the word heads the lines, not the last one", seenText)
    dialog.Close()
    CommanderQuestLogChar.RepObserved = nil
    Refresh()
end

-- ===========================================================================
-- I. Hygiene
-- ===========================================================================

do
    local ALLOWED = {
        BINDING_HEADER_COMMANDERQUESTLOG = true, BINDING_NAME_COMMANDERQUESTLOG_SEARCH = true,
        BINDING_NAME_COMMANDERQUESTLOG_TOGGLE = true, COMMANDER_QUESTLOG_EVENTS = true, CommanderQuestLog = true,
        CommanderQuestLogChar = true, CommanderQuestLogDB = true, CommanderQuestLogDetailScroll = true,
        CommanderQuestLogFrame = true, CommanderQuestLogNavScroll = true, CommanderQuestLogSearchBox = true,
        CommanderQuestLogSortDrop = true, CommanderQuestLogZoneGroupDrop = true, CommanderQuestLogZoneMenu = true,
        CommanderQuestLogRepGroupDrop = true, CommanderQuestLogRepMenu = true,
        CommanderQuestLog_FocusSearch = true, CommanderQuestLog_Hide = true, CommanderQuestLog_OpenToQuest = true,
        CommanderQuestLog_OpenToZone = true, CommanderQuestLog_Show = true, CommanderQuestLog_Toggle = true,
        CommanderQuestLogReputationData = true, CommanderQuestLogMapDrawer = true,
        SLASH_COMMANDERUI_QUESTLOG1 = true, SLASH_COMMANDERUI_QUESTLOG2 = true,
    }
    local extra = {}
    for key in pairs(_G) do
        local name = tostring(key)
        -- the Log's reward buttons are named (CommanderQuestLogReward<n>), as they
        -- always were; the shared framework names its own dropdowns and scrollers
        if not globalsBefore[key] and not ALLOWED[name] and not name:match("^CommanderUI")
            and not name:match("^CommanderQuestLogReward%d+$") then
            extra[#extra + 1] = name
        end
    end
    table.sort(extra)
    CHECK(#extra == 0, "I: no global beyond the module's documented ones", table.concat(extra, ","))
    local bad = {}
    for _, text in ipairs(drawn) do
        local stripped = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\194\183", ""):gsub("\226\128\148", "")
        if stripped:find("[\128-\255]") then bad[#bad + 1] = text end
    end
    CHECK(#bad == 0, "I: no shape glyph in anything drawn", bad[1])
    CHECK(#dialog.writes == 0, "I: no field written on the dialog's frames", table.concat(dialog.writes, ","))
    CHECK(#fake.forbidden == 0 and #fake.styleErrors == 0, "I: no forbidden or mis-styled Questie call",
        table.concat(fake.forbidden, ","))
    CHECK(A._LastError() == nil, "I: no adapter error", A._LastError())
    CHECK(Q.QuestFrame._State().lastError == nil and M._State().lastError == nil, "I: no hook error")
    CHECK(#mock.caughtErrors == 0, "I: no error reported", mock.caughtErrors[1])
end

Done()
