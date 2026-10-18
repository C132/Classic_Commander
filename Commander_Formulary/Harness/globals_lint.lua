-- Commander Formulary globals lint (luajit).
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
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns/Commander_Formulary"

local FILES = {
    "CommanderFormularyData_Enchanting.lua",
    "CommanderFormularyData_FirstAid.lua",
    "CommanderFormularyModel.lua",
    "CommanderFormularyDB.lua",
    "CommanderFormularyUI.lua",
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
CommanderFormularyDB CommanderFormularyChar COMMANDER_FORMULARY_EVENTS
CommanderFormulary_Data CommanderFormulary_Model CommanderFormulary_Defaults CommanderFormulary
CommanderFormulary_Show CommanderFormulary_Hide CommanderFormulary_Toggle CommanderFormulary_Search CommanderFormulary_RefreshPrices
CommanderFormulary_Select CommanderFormulary_ResetChar CommanderFormulary_Status CommanderFormulary_View
CommanderFormulary_Profession CommanderFormulary_RouteTrips
CommanderFormulary_OnLogin
BINDING_HEADER_COMMANDERFORMULARY BINDING_NAME_COMMANDERFORMULARY_TOGGLE BINDING_NAME_COMMANDERFORMULARY_SEARCH
]]

-- Client framework
allow [[
CreateFrame UIParent GameTooltip GameFontNormal GameFontNormalSmall GameFontNormalLarge
GameFontHighlightSmall GameFontDisableSmall
C_Timer GetTime UISpecialFrames InCombatLockdown HideUIPanel ItemRefTooltip IsShiftKeyDown ITEM_SOULBOUND
IsControlKeyDown
UIDropDownMenu_Initialize UIDropDownMenu_CreateInfo UIDropDownMenu_AddButton
UIDropDownMenu_SetWidth UIDropDownMenu_SetSelectedValue UIDropDownMenu_SetText
ChatEdit_InsertLink GetSpellLink
]]

-- The skill line, the two stock windows (CRAFT for Enchanting, TRADE SKILL
-- for First Aid), the spellbook
allow [[
GetNumSkillLines GetSkillLineInfo ExpandSkillHeader
CraftFrame GetCraftDisplaySkillLine GetNumCrafts GetCraftInfo
TradeSkillFrame GetTradeSkillLine GetNumTradeSkills GetTradeSkillInfo
IsSpellKnown IsPlayerSpell GetSpellInfo GetSpellTexture GetInventoryItemID
]]

-- Items
allow [[
C_Item GetItemInfo GetItemCount GetItemIcon
]]

-- The player
allow [[
UnitClass UnitFactionGroup GetFactionInfoByID RAID_CLASS_COLORS
]]

-- Optional neighbours, read only when present (CommanderOrders: the Go
-- buttons and the trip routes, CommanderFormularyUI.lua's Waypoints section)
allow [[
CommanderOrders CommanderTradecraft_Plan Auctionator AuctionFrame AuctionHouseFrame
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
