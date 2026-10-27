-- Commander Spellbook globals lint (luajit). Commander_Formulary's, pointed here.
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
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns/Commander_Spellbook"

local FILES = {
    "CommanderSpellbookData.lua",
    "CommanderSpellbookDB.lua",
    "CommanderSpellbookModel.lua",
    "CommanderSpellbookTraining.lua",
    "CommanderSpellbookSecure.lua",
    "CommanderSpellbookUI.lua",
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
Commander CommanderConsoleDB CommanderConsole_Colors
CommanderSpellbookDB CommanderSpellbookChar COMMANDER_SPELLBOOK_EVENTS CommanderSpellbook CommanderSpellbookData
CommanderSpellbook_Show CommanderSpellbook_Hide CommanderSpellbook_Toggle CommanderSpellbook_Open
CommanderSpellbook_TogglePet CommanderSpellbook_FocusSearch
BINDING_HEADER_COMMANDERSPELLBOOK BINDING_NAME_COMMANDERSPELLBOOK_TOGGLE BINDING_NAME_COMMANDERSPELLBOOK_PETBOOK
BINDING_NAME_COMMANDERSPELLBOOK_TRAINING BINDING_NAME_COMMANDERSPELLBOOK_SEARCH
]]

-- Client framework
allow [[
CreateFrame UIParent GameTooltip GameFontNormalSmall GameFontHighlightSmall GameFontDisableSmall
C_Timer UISpecialFrames InCombatLockdown HideUIPanel IsShiftKeyDown IsControlKeyDown GetCursorPosition
UIDropDownMenu_Initialize UIDropDownMenu_CreateInfo UIDropDownMenu_AddButton
UIDropDownMenu_SetWidth UIDropDownMenu_SetSelectedValue UIDropDownMenu_SetText
ChatEdit_InsertLink ChatFrameUtil PlaySound SOUNDKIT hooksecurefunc
GetBindingKey SetOverrideBinding ClearOverrideBindings C_Map GetCoinTextureString GetMoney
]]

-- The spellbook, spells and the stock book (Blizzard_UIPanels_Game/Vanilla/SpellBookFrame.lua
-- calls every legacy one of these with the same arguments)
allow [[
GetNumSpellTabs GetSpellTabInfo GetSpellBookItemInfo GetSpellBookItemName IsPassiveSpell
GetSpellTexture GetSpellAutocast HasPetSpells PetHasSpellbook IsPlayerSpell IsSpellKnown
GetSpellInfo GetSpellSubtext GetSpellLink C_Spell Spell PickupSpell PickupSpellBookItem
SpellBookFrame BOOKTYPE_PET C_SpellBook
]]

-- The player
allow [[
UnitClass UnitRace UnitLevel UnitFactionGroup RAID_CLASS_COLORS
]]

-- Optional neighbours, read only when present
allow [[
CommanderRankCheck COMMANDER_RANKCHECK_EVENTS CommanderOrders
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
