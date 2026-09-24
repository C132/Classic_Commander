-- Commander Oracle globals lint (luajit). Same check Commander_Spoils runs, on
-- Oracle's files.
--
--   /opt/homebrew/bin/luajit globals_lint.lua
--
-- In Lua a local declared AFTER a function body is not in that body's scope, so
-- the reference silently compiles to a global read and comes back nil at
-- runtime — invisible until the path happens to run. luajit's bytecode listing
-- names every global a file actually touches, so this is exact rather than
-- heuristic: dump GGET/GSET, subtract what we mean to touch, and anything left
-- is a scoping bug or an undeclared API.
--
-- Add a genuinely new WoW API to ALLOWED; do not add a name to make this quiet.

local LUAJIT = "/opt/homebrew/bin/luajit"
local ORACLE = "/Applications/World of Warcraft/_anniversary_/Interface/AddOns/Commander_Oracle"
local FILES = {
    "CommanderOracleData.lua",
    "CommanderOracleEngine.lua",
    "CommanderOracleRoster.lua",
    "CommanderOracleDB.lua",
    "CommanderOracle.lua",
}

local ALLOWED = {}
local function allow(list)
    for name in list:gmatch("[%w_]+") do ALLOWED[name] = true end
end

-- Lua base library
allow[[
type tonumber tostring ipairs pairs select unpack pcall error print table math
string format setmetatable rawset rawget next time os assert _G
]]

-- Suite framework and Oracle's own exported globals
allow[[
Commander CommanderOracleDB COMMANDER_ORACLE_EVENTS
CommanderOracle_AB CommanderOracle_POI CommanderOracle_Engine
CommanderOracle_FACTION_COLORS CommanderOracle_Opposite CommanderOracle_Roster
CommanderOracle_Test CommanderOracle_Call CommanderOracle_Probe
CommanderOracle_Defend CommanderOracle_Take
CommanderOracle_Sections
]]

-- WoW client API this module deliberately touches. Every one of these was
-- checked against the 2.5.6.69546 client binary before it was used.
allow[[
CreateFrame UIParent C_Timer C_Map C_AreaPoiInfo C_UIWidgetManager C_EventUtils
Enum GetTime GetInstanceInfo UnitFactionGroup IsInGroup SendChatMessage
LE_PARTY_CATEGORY_INSTANCE PlaySound SOUNDKIT Settings
GetNumBattlefieldScores GetBattlefieldScore RequestBattlefieldScoreData
GetNumBattlefieldStats GetBattlefieldStatInfo GetBattlefieldStatData
GetBattlefieldInstanceRunTime InCombatLockdown
UnitName UnitExists UnitIsUnit UnitClass UnitPosition CheckInteractDistance
SetRaidTarget GetRaidTargetIndex CanBeRaidTarget
UnitIsGroupLeader UnitIsGroupAssistant
]]

local problems, scanned = 0, 0
for _, file in ipairs(FILES) do
    local pipe = assert(io.popen(string.format('%q -bl %q 2>/dev/null', LUAJIT, ORACLE .. "/" .. file)))
    local seen = {}
    for line in pipe:lines() do
        local op, name = line:match("(GGET)%s+%d+%s+%d+%s+;%s+\"([%w_]+)\"")
        if not op then
            op, name = line:match("(GSET)%s+%d+%s+%d+%s+;%s+\"([%w_]+)\"")
        end
        if name and not ALLOWED[name] and not seen[name] then
            seen[name] = true
            problems = problems + 1
            io.write("UNDECLARED GLOBAL  ", file, "  ", name,
                "  (a local declared after its use compiles to this)\n")
        end
    end
    pipe:close()
    scanned = scanned + 1
end

print(string.format("globals lint: %d files, %d undeclared globals", scanned, problems))
os.exit(problems > 0 and 1 or 0)
