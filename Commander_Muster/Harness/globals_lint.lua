-- Commander Muster globals lint (luajit).
--
--   /opt/homebrew/bin/luajit globals_lint.lua
--
-- The Armory lint, applied here. luajit's bytecode listing names every global a
-- file touches, so this is EXACT: dump GGET/GSET, subtract the globals we mean
-- to touch, and anything left is a local used before it was declared (which
-- compiles, silently, to a nil global) or an API that does not exist.
--
-- Add a genuinely new WoW API to ALLOWED with a note on where it is called.
-- Do NOT add a name just to make this quiet.

local LUAJIT = "/opt/homebrew/bin/luajit"

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local MUSTER = HERE:match("^(.*)/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns/Commander_Muster"

local FILES = {
    "CommanderMusterData.lua",
    "CommanderMusterEngine.lua",
    "CommanderMusterDB.lua",
    "CommanderMuster.lua",
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

-- Suite framework, our saved variables, and what this module exports
allow [[
Commander
CommanderMusterDB CommanderMusterBests COMMANDER_MUSTER_EVENTS
CommanderMusterData CommanderMusterEngine CommanderMuster
CommanderMuster_Report CommanderMuster_Forget
]]

-- Client API this module touches, grouped by why.
allow [[
CreateFrame GameTooltip wipe
C_Timer C_AddOns C_Item C_EventUtils IsAddOnLoaded
GetTime InCombatLockdown IsInRaid
]]

-- Units and their kit
allow [[
UnitGUID UnitName UnitClass UnitIsPlayer GetInventoryItemLink
]]

-- The inspect channel (Blizzard_InspectUI frames are read behind nil checks)
allow [[
CanInspect NotifyInspect ClearInspectPlayer
HasInspectHonorData RequestInspectHonorData
InspectFrame InspectPaperDollFrame InspectModelFrame
]]

-- Arena, both season shapes (GetCurrentArenaSeason only stamps the
-- season-best ledger, behind a type check: Blizzard's own call is commented out)
allow [[
GetCurrentArenaSeasonUsesTeams GetCurrentArenaSeason
GetArenaTeam GetPersonalRatedInfo RequestRatedInfo
GetInspectArenaTeamData GetInspectArenaData
]]

-- The character panel and presentation
allow [[
PaperDollFrame CharacterModelFrame ITEM_QUALITY_COLORS
TooltipDataProcessor Enum
]]

local problems, scanned = 0, 0

for _, file in ipairs(FILES) do
    local path = MUSTER .. "/" .. file
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
