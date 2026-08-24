-- Commander Debug globals lint (luajit).
--
--   /opt/homebrew/bin/luajit globals_lint.lua
--
-- Same check Commander_Spoils runs, for the same reason: in Lua a local
-- declared AFTER a function body is not in that body's scope, so the
-- reference silently compiles to a global read and returns nil at runtime.
-- luajit's bytecode listing names every global a file touches, so dumping
-- GGET/GSET and subtracting the ones we mean to touch is exact rather than
-- heuristic. Add a genuinely new WoW API to ALLOWED; do not add a name just
-- to make this quiet.

local LUAJIT = "/opt/homebrew/bin/luajit"
local DEBUG = "/Applications/World of Warcraft/_anniversary_/Interface/AddOns/Commander_Debug"
local FILES = { "CommanderDebugDB.lua", "CommanderDebugCapture.lua", "CommanderDebug.lua" }

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
Commander CommanderDebug CommanderDebugDB COMMANDER_DEBUG_EVENTS
COMMANDER_DEBUG_SCOPES CommanderDebug_Show CommanderDebug_Hide
CommanderDebug_Toggle CommanderDebug_Copy CommanderDebug_Clear
CommanderDebug_List CommanderDebug_RaiseTestError
BugGrabber BugGrabberDB
]]

-- WoW client API this module deliberately touches.
allow[[
CreateFrame UIParent UISpecialFrames Settings EventRegistry StaticPopupDialogs
StaticPopup_Show ACCEPT CANCEL C_AddOns C_Timer GetNumAddOns GetAddOnInfo
GetAddOnMetadata IsAddOnLoaded GetBuildInfo GetLocale GetRealmName UnitName
UnitClass UnitLevel IsMacClient geterrorhandler seterrorhandler debugstack
debuglocals wipe GameFontHighlightSmall
]]

local problems, scanned = 0, 0
for _, file in ipairs(FILES) do
    local pipe = assert(io.popen(string.format('%q -bl %q 2>/dev/null', LUAJIT, DEBUG .. "/" .. file)))
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
