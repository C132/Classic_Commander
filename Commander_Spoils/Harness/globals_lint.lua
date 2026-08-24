-- Commander Spoils globals lint (luajit).
--
--   /opt/homebrew/bin/luajit globals_lint.lua
--
-- Why this exists: in Lua a local declared AFTER a function body is not in that
-- body's scope, so the reference silently compiles to a global access and reads
-- nil at runtime. This module hit that bug three separate times (`segments` in
-- E.Wipe, `viewOffset` in WireQuiet, `salvageClosing`/`AnchorSalvage` in
-- BuildSalvage) and each one was invisible until something happened to exercise
-- the path.
--
-- luajit's bytecode listing names every global the file actually touches, so
-- the check is exact rather than heuristic: dump GGET/GSET, subtract the
-- globals we mean to touch, and anything left is a scoping bug or an
-- undeclared API. Add a genuinely new WoW API to ALLOWED; do not add a name
-- just to make this quiet.

local LUAJIT = "/opt/homebrew/bin/luajit"
local SPOILS = "/Applications/World of Warcraft/_anniversary_/Interface/AddOns/Commander_Spoils"
local FILES = { "CommanderSpoilsDB.lua", "CommanderSpoilsEngine.lua", "CommanderSpoils.lua" }

local ALLOWED = {}
local function allow(list)
    for name in list:gmatch("[%w_]+") do ALLOWED[name] = true end
end

-- Lua base library
allow[[
type tonumber tostring ipairs pairs select unpack pcall error print table math
string format setmetatable rawset rawget next time date os assert _G
]]

-- Suite framework and our own exported globals
allow[[
Commander CommanderSpoilsDB CommanderSpoilsData CommanderSpoilsEngine
COMMANDER_SPOILS_EVENTS CommanderSpoils_Suppression CommanderSpoils_Ready
CommanderSpoils_Toggle CommanderSpoils_Report CommanderSpoils_Wipe
CommanderSpoils_ToggleFarm CommanderSpoils_Test CommanderSpoils_PrintSize
CommanderSpoils_RollNeed CommanderSpoils_RollGreed CommanderSpoils_RollPass
CommanderSpoils_PassAll CommanderSpoils_CycleRoll
BINDING_HEADER_COMMANDERSPOILS
BINDING_NAME_COMMANDERSPOILS_TOGGLE BINDING_NAME_COMMANDERSPOILS_ROLL_NEED
BINDING_NAME_COMMANDERSPOILS_ROLL_GREED BINDING_NAME_COMMANDERSPOILS_ROLL_PASS
BINDING_NAME_COMMANDERSPOILS_ROLL_PASSALL BINDING_NAME_COMMANDERSPOILS_ROLL_CYCLE
CommanderConsole_Colors CommanderBags_SortBags CommanderLogisticsDB Auctionator
]]

-- WoW client API this module deliberately touches. Every entry here should be
-- traceable to FINDINGS.md.
allow[[
CreateFrame UIParent WorldFrame GameTooltip UISpecialFrames geterrorhandler
C_Timer C_Item C_Container C_CurrencyInfo C_LootHistory C_Map C_PartyInfo
GetTime GetCursorPosition GetRealZoneText GetZoneText IsInInstance IsInGroup
IsInRaid GetNumGroupMembers UnitClass UnitName UnitGUID UnitIsDead
UnitIsDeadOrGhost UnitIsConnected IsShiftKeyDown IsControlKeyDown strsplit
PlaySound SOUNDKIT ITEM_QUALITY_COLORS CreateColor SendChatMessage
ChatEdit_InsertLink DressUpItemLink ChatFrameUtil StaticPopup_Hide
UIDropDownMenu_CreateInfo UIDropDownMenu_AddButton UIDropDownMenu_Initialize
ToggleDropDownMenu MAX_RAID_MEMBERS NUM_GROUP_LOOT_FRAMES MASTER_LOOT_THREHOLD
GroupLootContainer GroupLootFrame_OpenNewFrame LootHistoryFrame MasterLooterFrame
BonusRollFrame
GetNumLootItems LootSlotHasItem GetLootSlotInfo GetLootSlotLink GetLootSlotType
GetLootSourceInfo GetLootThreshold IsFishingLoot IsMasterLooter
GetLootRollItemInfo GetLootRollItemLink GetLootRollTimeLeft GetActiveLootRollIDs
GetMasterLootCandidate
]]

local problems, scanned = 0, 0
for _, file in ipairs(FILES) do
    local pipe = assert(io.popen(string.format('%q -bl %q 2>/dev/null', LUAJIT, SPOILS .. "/" .. file)))
    local seen = {}
    for line in pipe:lines() do
        local op, name = line:match("(GGET)%s+%d+%s+%d+%s+;%s+\"([%w_]+)\"")
        if not op then
            op, name = line:match("(GSET)%s+%d+%s+%d+%s+;%s+\"([%w_]+)\"")
        end
        -- luajit truncates long constant names in the listing, so the binding
        -- globals are matched by prefix rather than exactly.
        if name and name:sub(1, 8) == "BINDING_" then name = nil end
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
