-- Commander Action Bar globals lint (luajit).
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
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns/Commander_ActionBar"

local FILES = {
    "CommanderActionBarDB.lua",
    "CommanderActionBar.lua",
}

local ALLOWED = {}
local function allow(list)
    for name in list:gmatch("[%w_]+") do ALLOWED[name] = true end
end

-- Lua base library
allow [[
type tonumber tostring ipairs pairs next select unpack pcall error print
table math string _G
]]

-- Suite framework, our saved variable and event table
allow [[
Commander CommanderActionBarDB COMMANDER_ACTIONBAR_EVENTS
]]

-- Client framework
allow [[
CreateFrame UIParent C_Timer GetTime InCombatLockdown hooksecurefunc wipe
SlashCmdList SLASH_COMMANDERACTIONBARDIAG1 debugstack GameFontHighlightSmall
MouseIsOver GetCursorInfo UnitClass RAID_CLASS_COLORS
]]

-- Blizzard's bars (CommanderActionBar.lua: the grid, the pet bar)
allow [[
MainActionBar PetActionBar
HasAction GetActionCooldown IsUsableAction IsActionInRange
]]

-- Blizzard's two action-button lists our faces leave (CommanderActionBar.lua:
-- DetachFace, LeaveActionList)
allow [[
ActionBarButtonEventsFrame ActionBarActionEventsFrame
]]

-- The numpad card's key binds (CommanderActionBar.lua: ApplyNumpadBindings)
allow [[
SetOverrideBindingClick ClearOverrideBindings
]]

-- The function-key row's raid-mark and party modes (CommanderActionBar.lua:
-- ToggleRaidMark, CreateMarkFace, PartySeatUnit, StyleModeFaces)
allow [[
GetRaidTargetIndex SetRaidTarget GetCVarBool
UnitExists UnitName UnitIsDeadOrGhost UnitIsConnected UnitInRange
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
