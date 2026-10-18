-- Commander Recruit globals lint (luajit).
--
--   /opt/homebrew/bin/luajit globals_lint.lua
--
-- The Muster lint, applied here: luajit's bytecode listing names every global
-- a file touches, so an undeclared one is exact evidence of a local used
-- before it was declared or an API that does not exist. Add a genuinely new
-- WoW API to ALLOWED with a note; never add a name just to make it quiet.

local LUAJIT = "/opt/homebrew/bin/luajit"

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDON_DIR = HERE:match("^(.*)/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns/Commander_Recruit"

local FILES = {
    "CommanderRecruitEngine.lua",
    "CommanderRecruitDB.lua",
    "CommanderRecruit.lua",
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

-- Suite framework, our saved variables and exports, and the two modules we read
allow [[
Commander
CommanderRecruitDB CommanderRecruitWatch CommanderRecruitProbe COMMANDER_RECRUIT_EVENTS CommanderRecruit CommanderRecruit_Engine
CommanderRecruit_SweepStep CommanderRecruit_Toggle CommanderRecruit_ProbeStep CommanderRecruit_NextStep
BINDING_HEADER_COMMANDERRECRUIT BINDING_NAME_COMMANDERRECRUIT_SWEEP BINDING_NAME_COMMANDERRECRUIT_TOGGLE BINDING_NAME_COMMANDERRECRUIT_PROBE BINDING_NAME_COMMANDERRECRUIT_NEXT
CommanderMuster CommanderLadder
]]

-- Client framework and the window
allow [[
CreateFrame UIParent GameTooltip UISpecialFrames tinsert wipe C_Timer GetTime
RAID_CLASS_COLORS LOCALIZED_CLASS_NAMES_MALE CLASS_ICON_TCOORDS GetCursorPosition Enum
]]

-- Names, units and realms
allow [[
GetNormalizedRealmName GetRealmName GetPlayerInfoByGUID C_CreatureInfo
UnitExists UnitIsPlayer UnitIsUnit UnitGUID UnitName GetUnitName UnitClass UnitLevel UnitFactionGroup
]]

-- Where "online" comes from: /who, the group finder, the guild, friends
allow [[
C_FriendList FriendsFrame FriendsFrameCloseButton HideUIPanel C_LFGList
IsInGuild GetNumGuildMembers GetGuildRosterInfo C_GuildInfo
]]

-- Whisper and invite from a row
allow [[
ChatFrameUtil ChatFrame_SendTell ChatFrame_OpenChat C_PartyInfo InviteUnit CommanderContacts_OpenWhisper
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
