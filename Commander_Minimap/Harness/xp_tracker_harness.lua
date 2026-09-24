-- Commander Minimap XP tracker harness (luajit).
-- Loads the REAL XP model and the REAL information-button file under a WoW
-- mock, drives the events the client sends (login, kill lines with and
-- without rested bonus, quest turn-ins, a level-up across the boundary) and
-- asserts the numbers the tooltip, menu and button text show.
--
--   /opt/homebrew/bin/luajit xp_tracker_harness.lua

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDON = HERE:match("^(.*)/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns/Commander_Minimap"

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

local player = { xp = 0, max = 1000, level = 10, rested = nil, resting = false }
local now = 1000

function UnitXP() return player.xp end
function UnitXPMax() return player.max end
function UnitLevel() return player.level end
function UnitName() return "Tester" end
function GetRealmName() return "Realm" end
function GetXPExhaustion() return player.rested end
function IsResting() return player.resting end
function GetMaxPlayerLevel() return 70 end
function IsXPUserDisabled() return false end
function GetTime() return now end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function GetMoney() return 123456 end
function GetInventoryItemDurability() return nil end
function GetNetStats() return 0, 0, 42 end
function print() end

COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
COMBATLOG_XPGAIN_EXHAUSTION1 = "%s dies, you gain %d experience. (%s exp %s bonus)"
COMBATLOG_XPGAIN_EXHAUSTION1_GROUP = "%s dies, you gain %d experience. (%s exp %s bonus, +%d group bonus)"
COMBATLOG_XPGAIN_EXHAUSTION1_RAID = "%s dies, you gain %d experience. (%s exp %s bonus, -%d raid penalty)"

-- Any method on a mock frame is a no-op unless defined
local function MockObject(extra)
    local o = extra or {}
    return setmetatable(o, { __index = function(t, k)
        return function() end
    end })
end

local fontStrings = {}
local frames = {}
function CreateFrame(kind, name)
    local f = MockObject({ __scripts = {} })
    function f:SetScript(event, fn) self.__scripts[event] = fn end
    function f:HookScript(event, fn) self.__scripts[event] = fn end
    function f:CreateFontString()
        local fs = MockObject({})
        function fs:SetText(t) self.__text = t end
        function fs:SetTextColor(r, g, b) self.__color = { r, g, b } end
        fontStrings[#fontStrings + 1] = fs
        return fs
    end
    frames[#frames + 1] = f
    if name then _G[name] = f end
    return f
end
Minimap = MockObject({})

local tooltipLines, tooltipOwner = {}, nil
GameTooltip = MockObject({})
function GameTooltip:SetOwner(owner) tooltipOwner = owner end
function GameTooltip:ClearLines() tooltipLines = {} end
function GameTooltip:AddLine(text) tooltipLines[#tooltipLines + 1] = { text } end
function GameTooltip:AddDoubleLine(l, r) tooltipLines[#tooltipLines + 1] = { l, r } end
function GameTooltip:IsOwned(owner) return tooltipOwner == owner end
function GameTooltip:Hide() tooltipOwner = nil end

local listeners = {}
Commander = { AddListener = function(event, fn) listeners[event] = fn end }
COMMANDER_MINIMAP_EVENTS = { COMMANDER_MINIMAP = "COMMANDER_MINIMAP" }
CommanderMinimapDB = { ShowMinimapButton = true, XPDisplayMode = "PERCENTAGE",
                       lastXPGain = 150, lastXPSource = "Old Mob" }

local chatText
local menuItems
function UIDropDownMenu_Initialize(frame, init) menuItems = {}; init(frame, 1) end
function UIDropDownMenu_AddButton(item) menuItems[#menuItems + 1] = item end
function ToggleDropDownMenu() end
function ChatFrame_OpenChat(text) chatText = text end

-- ===========================================================================
-- Load the real files
-- ===========================================================================

dofile(ADDON .. "/CommanderMinimapXP.lua")
local XP = CommanderMinimapXP
dofile(ADDON .. "/CommanderMinimapButton.lua")

local eventFrame = frames[1]
local button = CommanderMinimapButton
local function Fire(event, ...) eventFrame.__scripts.OnEvent(eventFrame, event, ...) end
local function Tooltip()
    button.__scripts.OnEnter(button)
    local rows = {}
    for _, line in ipairs(tooltipLines) do
        if line[2] then rows[line[1]] = line[2] end
    end
    return rows, tooltipLines
end
local buttonText = function() return fontStrings[1].__text end

-- ===========================================================================
-- Chat parsing
-- ===========================================================================

do
    local p = XP.PatternFromFormat("%s dies, you gain %d experience.", true)
    CHECK(p == "^(.-) dies, you gain (%d+) experience%.$", "pattern from format", p)

    local name, amount, bonus = XP.ParseKill("Kobold Miner dies, you gain 120 experience.")
    CHECK(name == "Kobold Miner" and amount == 120 and bonus == 0, "plain kill line", tostring(name) .. " " .. tostring(amount))

    name, amount, bonus = XP.ParseKill("Kobold Miner dies, you gain 240 experience. (+120 exp Rested bonus)")
    CHECK(name == "Kobold Miner" and amount == 240 and bonus == 120, "rested kill line", tostring(bonus))

    name, amount, bonus = XP.ParseKill("Defias Thug dies, you gain 90 experience. (+45 exp Rested bonus, +9 group bonus)")
    CHECK(amount == 90 and bonus == 45, "rested + group kill line", tostring(bonus))

    name, amount = XP.ParseKill("Dr. Mob (Elite) dies, you gain 1000 experience.")
    CHECK(name == "Dr. Mob (Elite)" and amount == 1000, "magic characters in the mob name", tostring(name))

    CHECK(XP.ParseKill("You gain 500 experience.") == nil, "unnamed XP (quest/explore) is not a kill")
    CHECK(XP.ParseKill(nil) == nil, "nil message")
end

-- ===========================================================================
-- Login, legacy seed, button text
-- ===========================================================================

player.xp, player.max, player.level, player.rested = 250, 1000, 10, nil
Fire("PLAYER_LOGIN")
CHECK(buttonText() == "25%", "button shows percentage at login", buttonText())
CHECK(fontStrings[1].__color[1] == 0.58, "no rested: purple text")
CHECK(CommanderMinimapDB.XPHistory["Tester-Realm"].kills[1] == 150, "old lastXPGain seeds the kill history")

local rows = Tooltip()
CHECK(rows["Current"] == "250 / 1,000  (25.0%)", "tooltip current", rows["Current"])
CHECK(rows["Remaining"] == "750  (75.0%)", "tooltip remaining", rows["Remaining"])
CHECK(rows["Bars"] == "5.0 / 20  (15.0 to go)", "tooltip bars", rows["Bars"])
CHECK(rows["Rested"] == "None", "tooltip rested none", rows["Rested"])
CHECK(rows["XP / hour"] == "--", "no pace before any XP")
CHECK(rows["Kills"] and rows["Kills"]:match("^~5 "), "kills from seeded average (750/150)", rows["Kills"])

-- ===========================================================================
-- Kills with rested, pace, estimates
-- ===========================================================================

player.rested = 200
Fire("UPDATE_EXHAUSTION")
CHECK(fontStrings[1].__color[1] == 0, "rested appears: text recolors to cyan")

-- Kill: base 100, rested bonus 100
now = now + 60
Fire("CHAT_MSG_COMBAT_XP_GAIN", "Wolf dies, you gain 200 experience. (+100 exp Rested bonus)")
player.xp, player.rested = 450, 100
Fire("PLAYER_XP_UPDATE")

-- Quest: 300 XP
now = now + 60
Fire("QUEST_TURNED_IN", 123, 300, 0)
player.xp = 750
Fire("PLAYER_XP_UPDATE")

-- Exploration: 50 XP, no kill line
now = now + 60
player.xp = 800
Fire("PLAYER_XP_UPDATE")

local s = XP.Snapshot(now)
CHECK(s.gained == 550, "session gained counts every source", s.gained)
CHECK(s.sessionKillXP == 200 and s.sessionQuestXP == 300 and s.sessionOtherXP == 50, "session split", s.sessionOtherXP)
CHECK(math.abs(s.perHour - 550 / 180 * 3600) < 1e-6, "XP/hour over the session", s.perHour)
CHECK(math.abs(s.timeToLevel - 200 / (550 / 180)) < 1e-6, "time to level at session pace", s.timeToLevel)
CHECK(s.avgKill == 125, "average is of base XP (150 seed, 100 base)", s.avgKill)
-- 200 left, 100 rested covers min(100, 200/2)=100 as bonus -> (200-100)/125 -> 1
CHECK(s.killsToLevel == 1, "kills to level applies rested doubling", s.killsToLevel)
CHECK(s.restedKills == 1, "rested kills", s.restedKills)
CHECK(s.questsToLevel == 1 and s.avgQuest == 300, "quests to level", s.questsToLevel)
CHECK(s.restedEndLevel == 10 and s.restedEndPct == 90, "rested marker inside this level", s.restedEndPct)

rows = Tooltip()
CHECK(rows["Last kill"] == "Wolf: 200 (+100 rested)", "tooltip last kill", rows["Last kill"])
CHECK(rows["From kills"] == "200  (1, 36%)", "tooltip kill share", rows["From kills"])
CHECK(rows["Other"] == "50  (9%)", "tooltip other share", rows["Other"])
CHECK(rows["Time"] == "3m", "tooltip session time", rows["Time"])

-- Live refresh while hovered: the tooltip rebuilds on XP events
player.xp = 810
Fire("PLAYER_XP_UPDATE")
rows = Tooltip()
CHECK(rows["Current"] == "810 / 1,000  (81.0%)", "tooltip refreshed after XP update", rows["Current"])

-- ===========================================================================
-- Kills-to-level math, directly
-- ===========================================================================

CHECK(XP.KillsToLevel(1000, 0, 100) == 10, "no rested")
CHECK(XP.KillsToLevel(1000, 2000, 100) == 5, "rested covers everything: half the kills")
CHECK(XP.KillsToLevel(1000, 200, 100) == 8, "partial rested")
CHECK(XP.KillsToLevel(1000, 0, nil) == nil, "no history -> no estimate")

-- ===========================================================================
-- Level-up across the boundary
-- ===========================================================================

player.xp = 990
Fire("PLAYER_XP_UPDATE")
local before = XP.Snapshot(now).gained
player.level, player.max, player.xp, player.rested = 11, 1200, 40, nil
Fire("PLAYER_LEVEL_UP")
s = XP.Snapshot(now)
CHECK(s.gained - before == 50, "level-up delta is old remainder + new XP", s.gained - before)
CHECK(s.levelsGained == 1, "levels gained counted", s.levelsGained)
Fire("PLAYER_XP_UPDATE") -- the second event for the same change adds nothing
CHECK(XP.Snapshot(now).gained - before == 50, "no double count when both events fire")

-- Rested marker spilling into the next level
player.xp, player.rested = 1000, 500
s = XP.Snapshot(now)
CHECK(s.restedEndLevel == 12 and math.abs(s.restedEndPct - 300 / 1200 * 100) < 1e-6, "rested marker spills into next level", s.restedEndPct)

-- Resting: time until the 150% cap at 5% per 8h
player.resting, player.rested = true, 0
s = XP.Snapshot(now)
CHECK(math.abs(s.restedFullIn - 30 * 8 * 3600) < 1, "rested full in 240h from empty", s.restedFullIn)

-- ===========================================================================
-- Display modes, chat line, reset, max level
-- ===========================================================================

player.rested = nil
player.resting = false
for mode, want in pairs({ REMAINING = "200", RESTED = "0%", KILLS_TO_LEVEL = "2" }) do
    CommanderMinimapDB.XPDisplayMode = mode
    listeners.COMMANDER_MINIMAP()
    CHECK(buttonText() == want, "button mode " .. mode, buttonText())
end
CommanderMinimapDB.XPDisplayMode = "TIME_TO_LEVEL"
listeners.COMMANDER_MINIMAP()
CHECK(buttonText():match("^%d+[mhd]$"), "button mode TIME_TO_LEVEL", buttonText())

button.__scripts.OnClick(button, "RightButton")
CHECK(menuItems[1].text == "Level 11: 83.3%" and menuItems[1].isTitle, "right-click menu title", menuItems[1].text)
local menuText = {}
for _, item in ipairs(menuItems) do menuText[item.text] = item end
CHECK(menuText["Kills to Level: ~2"], "menu kills to level")
CHECK(menuText["Paste XP to Chat"] and menuText["Paste XP to Chat"].func, "menu paste action")
CHECK(menuText["Latency: 42ms"], "menu keeps the character stats")
local line = XP.ChatLine(XP.Snapshot(now))
CHECK(line:match("^Level 11: 83%.3%% %(200 XP to go%)"), "chat line", line)
CHECK(not line:find("|", 1, true), "chat line has no escape pipes")

IsShiftKeyDown = function() return true end
button.__scripts.OnClick(button, "LeftButton")
CHECK(chatText == line, "shift-click pastes the chat line")
IsShiftKeyDown = function() return false end

IsControlKeyDown = function() return true end
button.__scripts.OnClick(button, "LeftButton")
IsControlKeyDown = function() return false end
s = XP.Snapshot(now)
CHECK(s.gained == 0 and s.sessionKills == 0 and s.perHour == nil, "ctrl-click resets the session")
CHECK(s.avgKill ~= nil, "reset keeps the per-character history")

CHECK(XP.Duration(59) == "<1m" and XP.Duration(3900) == "1h 05m" and XP.Duration(90000) == "1d 1h", "durations")
CHECK(XP.Short(32655) == "33k" and XP.Short(1500) == "1.5k" and XP.Short(999) == "999", "short numbers")

player.level = 70
CommanderMinimapDB.XPDisplayMode = "PERCENTAGE"
listeners.COMMANDER_MINIMAP()
CHECK(buttonText() == "Max", "max level button text", buttonText())
local _, lines = Tooltip()
CHECK(lines[2][1] == "Maximum level reached", "max level tooltip")

io.write(string.format("%d checks, %d failed\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
