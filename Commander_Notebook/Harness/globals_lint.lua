-- Commander Notebook globals lint (luajit).
--
--   /opt/homebrew/bin/luajit globals_lint.lua
--
-- Why this exists: in Lua a local declared AFTER a function body is not in
-- that body's scope, so the reference silently compiles to a global access and
-- reads nil at runtime. This module is full of mutually-recursive refresh
-- functions -- RefreshAll calls RefreshList calls SelectNote calls LoadNote --
-- which is exactly the shape that bug hides in, and none of it would raise
-- until a particular click order happened to run.
--
-- luajit's bytecode listing names every global a file actually touches, so the
-- check is exact rather than heuristic: dump GGET/GSET, subtract the globals
-- we mean to touch, and anything left is a scoping bug or an undeclared API.
-- Add a genuinely new WoW API to ALLOWED; do not add a name just to make this
-- quiet.

local LUAJIT = "/opt/homebrew/bin/luajit"

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ROOT = HERE:match("^(.*)/Harness$") or HERE

local FILES = {
    "CommanderNotebookStore.lua",
    "CommanderNotebookDB.lua",
    "CommanderNotebookUI.lua",
}

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
Commander CommanderNotebookDB CommanderNotebookStore CommanderNotebook
CommanderNotebook_Defaults COMMANDER_NOTEBOOK_EVENTS
CommanderNotebook_Toggle CommanderNotebook_Show CommanderNotebook_Hide
CommanderNotebook_NewNote CommanderNotebook_FocusSearch
CommanderNotebook_ShowTrash CommanderNotebook_PrintStats
CommanderNotebook_Capture CommanderNotebook_OpenToNote CommanderNotebook_Flush
CommanderConsole_Colors CommanderConsoleDB
SLASH_COMMANDERNOTEBOOKCAPTURE1 SLASH_COMMANDERNOTEBOOKCAPTURE2
]]

-- WoW client API this module deliberately touches.
-- Commander Orders, for a note's Go and its Announce In Chat switch (optional: every use is guarded)
allow[[
CommanderOrders CommanderOrdersDB
]]

allow[[
CreateFrame UIParent GameTooltip UISpecialFrames SlashCmdList
StaticPopupDialogs StaticPopup_Show SetItemRef ChatEdit_InsertLink
GetTime GetRealZoneText GetSubZoneText GetRealmName C_Map
UnitClass UnitName UnitLevel UnitExists RAID_CLASS_COLORS
PlaySound SOUNDKIT
UIDropDownMenu_CreateInfo UIDropDownMenu_AddButton UIDropDownMenu_Initialize
UIDropDownMenu_SetWidth UIDropDownMenu_SetSelectedValue UIDropDownMenu_SetText
ToggleDropDownMenu
GameFontNormalLarge GameFontHighlight GameFontHighlightSmall
]]

local problems, scanned = 0, 0
for _, file in ipairs(FILES) do
    local pipe = assert(io.popen(string.format('%q -bl %q 2>/dev/null',
        LUAJIT, ROOT .. "/" .. file)))
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
