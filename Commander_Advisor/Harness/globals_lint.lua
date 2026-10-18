-- Commander Advisor globals lint (luajit).
--
--   /opt/homebrew/bin/luajit globals_lint.lua
--
-- In Lua a local declared AFTER a function body is not in that body's scope,
-- so the reference silently compiles to a GLOBAL access and reads nil at
-- runtime. luajit's bytecode listing names every global a file touches, so
-- the check is exact: dump GGET/GSET, subtract the globals we mean to touch,
-- and anything left is a scoping bug or an undeclared API.
--
-- Add a genuinely new WoW API to ALLOWED with a comment saying where it is
-- called from. Do NOT add a name just to make this quiet.

local LUAJIT = "/opt/homebrew/bin/luajit"

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ROOT = HERE:match("^(.*)/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns/Commander_Advisor"

local FILES = {
    "CommanderAdvisorData.lua",
    "CommanderAdvisorEngine.lua",
    "CommanderAdvisorDB.lua",
    "CommanderAdvisor.lua",
}

local ALLOWED = {}
local function allow(list)
    for name in list:gmatch("[%w_]+") do ALLOWED[name] = true end
end

-- Lua base library
allow [[
type tonumber tostring ipairs pairs next select unpack pcall xpcall error assert
print setmetatable getmetatable rawset rawget rawequal rawlen
table math string os time date bit debug _G
]]

-- Suite framework, our saved variable, and what this module exports
allow [[
Commander
CommanderAdvisorDB COMMANDER_ADVISOR_EVENTS
CommanderAdvisor_Data CommanderAdvisor_Engine CommanderAdvisor
CommanderAdvisor_Report CommanderAdvisor_Test
]]

-- Client framework
allow [[
CreateFrame GameTooltip hooksecurefunc C_Timer C_Texture GetTime
PlaySound PlaySoundFile SOUNDKIT
]]

-- The player
allow [[
UnitClass UnitGUID UnitHealth UnitHealthMax UnitPower UnitPowerMax UnitPowerType
UnitAffectingCombat UnitIsDeadOrGhost UnitExists UnitCanAttack UnitIsUnit UnitIsPlayer
UnitOnTaxi UnitCastingInfo UnitChannelInfo
IsMounted IsResting IsStealthed IsInGroup IsInInstance IsOutdoors IsEquippedItemType
GetShapeshiftForm GetShapeshiftFormInfo
C_UnitAuras C_LossOfControl C_NamePlate
]]

-- The spellbook and the bars
allow [[
GetNumSpellTabs GetSpellTabInfo GetSpellBookItemName IsPassiveSpell HasPetSpells
GetSpellInfo GetSpellCooldown IsUsableSpell C_Spell
HasAction GetActionInfo GetMacroSpell GetMacroItem
C_Item C_Container GetItemCooldown GetItemCount IsUsableItem GetItemInfo
]]

-- The combat log
allow [[
C_CombatLog CombatLogGetCurrentEventInfo
]]

-- The group (CommanderAdvisor.lua: the seats, teammates' auras and range,
-- the Mending reach estimate, and a macro's own @unit for the overlays)
allow [[
UnitName UnitCanAssist UnitInRange UnitIsConnected UnitPosition IsSpellInRange
IsInRaid GetNumGroupMembers GetRaidRosterInfo GetMacroBody SecureCmdOptionParse
RAID_CLASS_COLORS STANDARD_TEXT_FONT wipe
CommanderAdvisor_RangeReport
]]

local problems, scanned = 0, 0

for _, file in ipairs(FILES) do
    local path = ROOT .. "/" .. file
    local probe = io.open(path, "r")
    if not probe then
        problems = problems + 1
        io.write("MISSING FILE       ", file, "\n")
    else
        probe:close()
        local pipe = assert(io.popen(string.format('%q -bl %q 2>&1', LUAJIT, path)))
        local seen = {}
        local sawBytecode = false
        for line in pipe:lines() do
            if line:find("^%-%- BYTECODE") then sawBytecode = true end
            local op, name = line:match("(GGET)%s+%d+%s+%d+%s+;%s+\"([%w_]+)\"")
            if not op then
                op, name = line:match("(GSET)%s+%d+%s+%d+%s+;%s+\"([%w_]+)\"")
            end
            if name and not ALLOWED[name] and not seen[name] then
                seen[name] = true
                problems = problems + 1
                io.write("UNDECLARED GLOBAL  ", file, "  ", name,
                    "  (a local declared after its use, or deleted from under it,",
                    " compiles to exactly this)\n")
            end
        end
        pipe:close()
        if not sawBytecode then
            problems = problems + 1
            io.write("DID NOT COMPILE    ", file, "\n")
        end
        scanned = scanned + 1
    end
end

io.write(string.format("%d files, %d problems\n", scanned, problems))
os.exit(problems == 0 and 0 or 1)
