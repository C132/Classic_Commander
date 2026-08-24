-- Commander Armory globals lint (luajit).
--
--   /opt/homebrew/bin/luajit globals_lint.lua
--
-- Why this exists: in Lua a local declared AFTER a function body is not in that
-- body's scope, so the reference silently compiles to a GLOBAL access and reads
-- nil at runtime. Nothing warns. The call site looks correct, the file loads
-- clean, and the feature simply does nothing until somebody exercises the path.
-- Commander_Spoils paid for that bug five separate times before this check was
-- written, and Commander_Armory is the largest module in the suite: five files,
-- four of them with forward-declared locals near the top.
--
-- The same dump catches the other half of the family -- a helper that was
-- renamed or deleted while its call sites were left behind. That is not a
-- hypothetical here: an edit to CommanderArmoryUI.lua removed the local
-- HiddenMap() and left two calls to it, and this lint named the file, the
-- global and the reason in under a second.
--
-- luajit's bytecode listing names every global a file actually touches, so the
-- check is EXACT rather than heuristic: dump GGET/GSET, subtract the globals we
-- mean to touch, and anything left is a scoping bug or an undeclared API.
--
-- Add a genuinely new WoW API to ALLOWED, with a comment saying where it is
-- called from. Do NOT add a name just to make this quiet -- that is precisely
-- the failure mode it exists to prevent.

local LUAJIT = "/opt/homebrew/bin/luajit"

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ARMORY = HERE:match("^(.*)/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns/Commander_Armory"

local FILES = {
    "CommanderArmoryData.lua",
    "CommanderArmoryEngine.lua",
    "CommanderArmoryDB.lua",
    "CommanderArmory.lua",
    "CommanderArmoryUI.lua",
}

local ALLOWED = {}
local function allow(list)
    for name in list:gmatch("[%w_]+") do ALLOWED[name] = true end
end

-- Lua base library and the two luajit extras this client also ships.
allow [[
type tonumber tostring ipairs pairs next select unpack pcall xpcall error assert
print setmetatable getmetatable rawset rawget rawequal rawlen
table math string os time date bit debug _G
]]

-- Suite framework, our own two saved variables, and every global this module
-- deliberately exports. Everything named CommanderArmory_* is a public entry
-- point called from the DB file's slash handlers or from Bindings.xml.
allow [[
Commander
CommanderArmoryDB CommanderArmorySets COMMANDER_ARMORY_EVENTS
CommanderArmoryData CommanderArmoryEngine CommanderArmory CommanderArmoryUI
CommanderArmory_CharKey CommanderArmory_CharStore
CommanderArmory_Toggle CommanderArmory_ListSets CommanderArmory_Probe
CommanderArmory_EquipSetByName CommanderArmory_SaveSetByName
CommanderArmory_WipeSets
CommanderConsole_Colors
]]

-- OptionalDeps. Every one of these is read behind an existence check, and a
-- missing addon costs a feature rather than erroring (the suite's guarding rule).
allow [[
PawnGetItemData PawnGetAllItemValues PawnIsScaleVisible
]]

-- The WoW client API this module deliberately touches. Grouped by why.
allow [[
CreateFrame UIParent WorldFrame GameTooltip UISpecialFrames geterrorhandler
hooksecurefunc wipe tinsert tremove strsplit
C_Timer C_AddOns C_Item C_Container C_EquipmentSet C_EventUtils C_PaperDollInfo
GetTime GetBuildInfo GetRealmName
]]

-- Containers and the bank. NUM_BAG_SLOTS/NUM_BANKBAGSLOTS are the ONLY way to
-- name the bank bags; Enum.BagIndex is the mainline enum and is wrong here.
allow [[
NUM_BAG_SLOTS NUM_BANKBAGSLOTS BANK_CONTAINER
GetContainerNumFreeSlots GetItemFamily GetItemStats
]]

-- The cursor state machine: the only path that can equip armor at all.
allow [[
ClearCursor CursorHasItem CursorCanGoInSlot PickupInventoryItem
IsInventoryItemLocked SpellIsTargeting EquipPendingItem
]]

-- The paperdoll.
allow [[
GetInventoryItemLink GetInventoryItemID GetInventoryItemCount
GetInventoryItemBroken GetInventoryItemTexture GetInventorySlotInfo
GetInventoryItemsForSlot
UnitClass UnitName UnitCastingInfo UnitIsDeadOrGhost UnitHasRelicSlot
UnitAffectingCombat InCombatLockdown CanDualWield
]]

-- Blizzard frames and templates we attach to but never replace.
allow [[
CharacterFrame CHARACTERFRAME_SUBFRAMES CharacterFrameTab_OnClick
CharacterFrame_ShowSubFrame ToggleCharacter
PanelTemplates_SetNumTabs PanelTemplates_TabResize PanelTemplates_SetTab
PaperDollItemSlotButton_Update PaperDollItemSlotButton_OnEnter
MerchantFrame ShoppingTooltip1 ShoppingTooltip2
StaticPopupDialogs StaticPopup_Show StaticPopup_Hide StaticPopup_Visible
]]

-- Presentation and input.
allow [[
ITEM_QUALITY_COLORS RELICSLOT
IsAltKeyDown IsShiftKeyDown IsControlKeyDown
GetMacroIcons GetNumMacroIcons GetMacroIconInfo
GetGameMessageInfo
]]

local problems, scanned, missing = 0, 0, 0

for _, file in ipairs(FILES) do
    local path = ARMORY .. "/" .. file
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
            -- luajit truncates long constant names in the listing, so the
            -- binding-label globals are matched by prefix rather than exactly.
            if name and name:sub(1, 8) == "BINDING_" then name = nil end
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

-- ---------------------------------------------------------------------------
-- XML well-formedness, and specifically the double hyphen
-- ---------------------------------------------------------------------------
-- This exists because it shipped. Bindings.xml carried a "--" inside a comment,
-- which XML forbids, and the client rejected the ENTIRE file: zero bindings
-- registered, and the in-combat weapon swap -- the one path with no fallback --
-- went with them. The only trace was a single LUA_WARNING at load, which is not
-- an error, does not appear in an error frame, and is trivially scrolled past.
--
-- Neither harness could see it. They load .lua files; the client loads this one
-- on its own, and nothing in Lua ever asks whether it parsed. So the check has
-- to be here, on the shipped file, as text.
--
-- Deliberately not a real XML parser: the failure mode we ship is prose written
-- by someone reaching for an em dash, and a scan that catches exactly that with
-- no dependency is worth more than a correct parser we might not have.
local XML_FILES = { "Bindings.xml" }

local xmlProblems = 0
for _, name in ipairs(XML_FILES) do
    local path = ARMORY .. "/" .. name
    local fh = io.open(path, "r")
    if not fh then
        -- Absent is fine. Bindings.xml is optional; a missing one binds nothing
        -- and breaks nothing, unlike a malformed one.
        io.write("xml: ", name, " absent, skipped\n")
    else
        local text = fh:read("*a")
        fh:close()

        local at = 1
        while true do
            local open = text:find("<!%-%-", at)
            if not open then break end
            local close = text:find("%-%->", open + 4)
            if not close then
                xmlProblems = xmlProblems + 1
                io.write("XML UNCLOSED COMMENT  ", name, "\n")
                break
            end
            local body = text:sub(open + 4, close - 1)
            local bad = body:find("%-%-")
            if bad then
                xmlProblems = xmlProblems + 1
                -- Report the line, because the client's own message gives a
                -- line:column that is easy to misread as a tag problem.
                local upto = text:sub(1, open + 3 + bad)
                local _, line = upto:gsub("\n", "")
                io.write("XML DOUBLE HYPHEN IN COMMENT  ", name, "  line ", line + 1,
                    "  (illegal in XML; the client rejects the whole file",
                    " and registers no bindings)\n")
            end
            at = close + 3
        end

        -- A cheap balance check for the one shape this file has. Not a parser;
        -- it only asserts that every element we open is closed or self-closed,
        -- which is enough to catch a truncated edit.
        local stripped = text:gsub("<!%-%-.-%-%->", "")
        local depth = 0
        for tag in stripped:gmatch("<([^>]+)>") do
            if tag:sub(1, 1) == "/" then
                depth = depth - 1
            elseif tag:sub(-1) ~= "/" and tag:sub(1, 1) ~= "?" then
                depth = depth + 1
            end
        end
        if depth ~= 0 then
            xmlProblems = xmlProblems + 1
            io.write("XML UNBALANCED TAGS  ", name, "  depth ", depth, "\n")
        end
    end
end

print(string.format("globals lint: %d files, %d undeclared globals; xml: %d problems",
    scanned, problems, xmlProblems))
os.exit((problems + missing + xmlProblems) > 0 and 1 or 0)
