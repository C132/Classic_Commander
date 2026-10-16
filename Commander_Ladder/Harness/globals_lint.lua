-- Commander Ladder globals lint (luajit).
--
--   /opt/homebrew/bin/luajit globals_lint.lua
--
-- The Muster lint, applied here: luajit's bytecode listing names every global
-- a file touches, so an undeclared one is exact evidence of a local used
-- before it was declared or an API that does not exist. Add a genuinely new
-- WoW API to ALLOWED with a note; never add a name just to make it quiet.
-- CommanderLadderData.lua is generated and not linted.

local LUAJIT = "/opt/homebrew/bin/luajit"

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDON_DIR = HERE:match("^(.*)/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns/Commander_Ladder"

local FILES = {
    "CommanderLadder.lua",
    "CommanderLadderDB.lua",
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

-- Suite framework, our saved variables, the generated data, and our exports
allow [[
Commander
CommanderLadderDB CommanderLadderWanted CommanderLadderData
COMMANDER_LADDER_EVENTS CommanderLadder
]]

-- Client API (realm names for keys, behind type checks)
allow [[
CreateFrame wipe GetNormalizedRealmName GetRealmName
]]

local problems, scanned = 0, 0

for _, file in ipairs(FILES) do
    local path = ADDON_DIR .. "/" .. file
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
