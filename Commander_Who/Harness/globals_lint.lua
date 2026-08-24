-- Commander Who globals lint (luajit).
--
--   /opt/homebrew/bin/luajit globals_lint.lua
--
-- Why this exists: in Lua a local declared AFTER a function body is not in that
-- body's scope, so the reference silently compiles to a GLOBAL access and reads
-- nil at runtime. Nothing warns. The file loads clean and the feature simply
-- does nothing until somebody exercises the path -- which, in a module whose
-- whole job is a list you have to scroll to see, could easily be never.
--
-- Commander_Who has three forward-declared locals across its four files
-- (RefreshRows in the host, Repaint in the UI, and the engine's Selection
-- metatable), which is exactly the shape that produces the bug.
--
-- luajit's bytecode listing names every global a file actually touches, so the
-- check is EXACT rather than heuristic: dump GGET/GSET, subtract the globals we
-- mean to touch, and anything left is a scoping bug or an undeclared API.
--
-- Add a genuinely new WoW API to ALLOWED with a comment saying where it is
-- called from. Do NOT add a name just to make this quiet -- that is precisely
-- the failure mode it exists to prevent.

local LUAJIT = "/opt/homebrew/bin/luajit"

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local WHO = HERE:match("^(.*)/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns/Commander_Who"

local FILES = {
    "CommanderWhoEngine.lua",
    "CommanderWhoDB.lua",
    "CommanderWho.lua",
    "CommanderWhoUI.lua",
}

local ALLOWED = {}
local function allow(list)
    for name in list:gmatch("[%w_]+") do ALLOWED[name] = true end
end

-- Lua base library and the luajit extras this client also ships.
allow [[
type tonumber tostring ipairs pairs next select unpack pcall xpcall error assert
print setmetatable getmetatable rawset rawget rawequal
table math string os bit debug _G
]]

-- Suite framework, our saved variable, and everything this module exports.
allow [[
Commander
CommanderWhoDB COMMANDER_WHO_EVENTS COMMANDER_WHO_CHROME COMMANDER_WHO_DEFAULTS
CommanderWhoEngine CommanderWho CommanderWhoUI
]]

-- The client API this module deliberately touches, grouped by why.

-- Widgets, timers, tooltips, the event bus.
allow [[
CreateFrame UIParent GameTooltip UISpecialFrames geterrorhandler hooksecurefunc
C_Timer
]]

-- The Who list itself. WhoFrameButton1..N and their $parentName font strings
-- are reached through _G by name, so they never appear here.
allow [[
C_FriendList WhoFrame WhoListScrollFrame FriendsFrame
FauxScrollFrame_GetOffset FauxScrollFrame_Update FauxScrollFrame_OnVerticalScroll
WhoList_Update
]]

-- Chat, the player, input, and the confirmation dialog.
allow [[
SendChatMessage UnitName IsShiftKeyDown
StaticPopupDialogs StaticPopup_Show CANCEL
LOCALIZED_CLASS_NAMES_MALE LOCALIZED_CLASS_NAMES_FEMALE
]]

local problems, scanned, missing = 0, 0, 0

for _, file in ipairs(FILES) do
    local path = WHO .. "/" .. file
    local probe = io.open(path, "r")
    if not probe then
        missing = missing + 1
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

print(string.format("globals lint: %d files, %d undeclared globals", scanned, problems))
os.exit((problems + missing) > 0 and 1 or 0)
