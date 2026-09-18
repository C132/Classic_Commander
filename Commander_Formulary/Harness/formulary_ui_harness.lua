-- Commander Formulary UI harness (luajit).
--
--   /opt/homebrew/bin/luajit formulary_ui_harness.lua
--
-- Loads the REAL shared framework (CommanderSettingsUI.lua, CommanderEvents.lua)
-- plus all four Commander_Tradecraft files under the suite's permissive widget
-- mock, on top of a fixtured character, then drives login, the settings page,
-- the guide window through a skill-up, a formula step, the trainer banner,
-- the alternatives, skipping, the craft button with its gear targeting and
-- replace-enchant answer, the ledger, the Auctionator hand-off and the
-- combat rule on the secure button. The route logic itself is proved by
-- tradecraft_engine_smoke.lua; this checks the wiring around it.
--
-- Mock preamble copied from Commander_Advisor/Harness/advisor_ui_harness.lua
-- and extended with the skill list, the craft window, bags and the popup.

local ADDONS = "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end

-- ===========================================================================
-- WoW mock
-- ===========================================================================

local now = 1000000
function time() return now end
function date(fmt, t) return os.date(fmt or "%c", t or now) end
function GetTime() return now - 999000 end
function GetBuildInfo() return "2.5.6", "68502", "Jul 7 2026", 20506 end

local printLog = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    printLog[#printLog + 1] = table.concat(parts, " ")
end

local harnessFailedErrors = {}
function geterrorhandler()
    return function(err)
        harnessFailedErrors[#harnessFailedErrors + 1] = tostring(err)
    end
end

-- Fonts: SetFont must reject garbage flags, per the client's hard-error trap
local VALID_FLAGS = { [""] = true, OUTLINE = true, THICKOUTLINE = true, MONOCHROME = true,
    ["OUTLINE, MONOCHROME"] = true }

local allFontStrings = {}
local frames = {}
local eventRegistry = {} -- event -> { frame, ... }

local NUMERIC_GETTERS = {
    GetWidth = 0, GetHeight = 0, GetScale = 1, GetEffectiveScale = 1,
    GetFrameLevel = 2, GetLeft = 0, GetBottom = 0, GetTop = 0, GetRight = 0,
    GetVerticalScroll = 0, GetVerticalScrollRange = 0, GetStringWidth = 10,
    GetID = 1, GetNumPoints = 1,
}

local function IsMethodName(key)
    return type(key) == "string" and key:match("^[A-Z]") and not key:match("^[A-Z][a-z]*$")
        or (type(key) == "string" and (key:match("^Set") or key:match("^Get") or key:match("^Is")
        or key:match("^Can") or key:match("^Enable") or key:match("^Disable")
        or key:match("^Register") or key:match("^Unregister") or key:match("^Hook")
        or key:match("^Clear") or key:match("^Create") or key:match("^Show")
        or key:match("^Hide") or key:match("^Raise") or key:match("^Start")
        or key:match("^Stop") or key:match("^Add") or key:match("^Lock")))
end

local NewWidget

local WidgetMT = {}
WidgetMT.__index = function(self, key)
    if type(key) ~= "string" then return nil end
    if NUMERIC_GETTERS[key] ~= nil then
        local v = NUMERIC_GETTERS[key]
        local fn = function() return v end
        rawset(self, key, fn)
        return fn
    end
    if key == "CreateTexture" then
        local fn = function(s) local t = NewWidget("Texture"); t.__parent = s; return t end
        rawset(self, key, fn)
        return fn
    end
    if key == "CreateFontString" then
        local fn = function(s)
            local t = NewWidget("FontString")
            t.__parent = s
            allFontStrings[#allFontStrings + 1] = t
            return t
        end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetScript" or key == "HookScript" then
        local fn = function(s, name, handler) s.__scripts[name] = handler end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetScript" then
        local fn = function(s, name) return s.__scripts[name] end
        rawset(self, key, fn)
        return fn
    end
    if key == "RegisterEvent" then
        local fn = function(s, event)
            eventRegistry[event] = eventRegistry[event] or {}
            table.insert(eventRegistry[event], s)
        end
        rawset(self, key, fn)
        return fn
    end
    if key == "UnregisterEvent" then
        local fn = function(s, event)
            local list = eventRegistry[event]
            if list then
                for i = #list, 1, -1 do
                    if list[i] == s then table.remove(list, i) end
                end
            end
        end
        rawset(self, key, fn)
        return fn
    end
    if key == "Show" then
        local fn = function(s)
            s.__shown = true
            if s.__scripts.OnShow then s.__scripts.OnShow(s) end
        end
        rawset(self, key, fn)
        return fn
    end
    if key == "Hide" then
        local fn = function(s) s.__shown = false end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetShown" then
        local fn = function(s, v) if v then s:Show() else s:Hide() end end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetSize" then
        local fn = function(s, w, h) s.__w, s.__h = w, h end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetVertexColor" then
        local fn = function(s, r, g, b, a) s.__color = { r, g, b, a } end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetWidth" then
        local fn = function(s, w) s.__w = w end
        rawset(self, key, fn)
        return fn
    end
    if key == "IsShown" or key == "IsVisible" then
        local fn = function(s) return s.__shown end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetText" then
        local fn = function(s, text) s.__text = text end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetText" then
        local fn = function(s) return s.__text or "" end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetFont" then
        local fn = function(s, path, size, flags)
            assert(type(path) == "string" and type(size) == "number",
                "SetFont bad args")
            assert(flags == nil or VALID_FLAGS[flags],
                "SetFont invalid flags: " .. tostring(flags))
            s.__font = { path, size, flags }
        end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetFont" then
        local fn = function(s)
            local f = s.__font or { "Fonts\\FRIZQT__.TTF", 12, "" }
            return f[1], f[2], f[3]
        end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetChecked" then
        local fn = function(s, v) s.__checked = v and true or false end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetChecked" then
        local fn = function(s) return s.__checked end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetPoint" then
        local fn = function() return "CENTER", nil, "CENTER", 0, 0 end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetThumbTexture" then
        local fn = function(s) return NewWidget("Texture") end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetName" then
        local fn = function(s) return s.__name end
        rawset(self, key, fn)
        return fn
    end
    if IsMethodName(key) then
        local fn = function() end
        rawset(self, key, fn)
        return fn
    end
    return nil
end

NewWidget = function(kind, name)
    local w = setmetatable({
        __kind = kind, __name = name, __scripts = {}, __shown = true,
    }, WidgetMT)
    return w
end

function CreateFrame(frameType, name, parent, template)
    local f = NewWidget(frameType, name)
    f.__template = template
    if frameType == "CheckButton" or (template and template:find("CheckButton")) then
        f.Text = NewWidget("FontString")
    end
    if template and template:find("BasicFrameTemplate") then
        f.CloseButton = NewWidget("Button")
        f.TitleText = NewWidget("FontString")
    end
    if name then _G[name] = f end
    frames[#frames + 1] = f
    return f
end

UIParent = NewWidget("Frame", "UIParent")
GameTooltip = NewWidget("GameTooltip", "GameTooltip")
GameTooltip.__lines = {}
GameTooltip.AddLine = function(s, text) s.__lines[#s.__lines + 1] = text end
GameTooltip.AddDoubleLine = function(s, left, right)
    s.__lines[#s.__lines + 1] = tostring(left) .. " = " .. tostring(right)
end
WorldFrame = NewWidget("Frame", "WorldFrame")
UISpecialFrames = {}
tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack
strsplit = function(sep, str) local out = {} for piece in string.gmatch(str, "([^" .. sep .. "]+)") do out[#out + 1] = piece end return unpack(out) end

GameFontNormal = NewWidget("Font")
GameFontNormalLarge = NewWidget("Font")
GameFontHighlight = NewWidget("Font")
GameFontHighlightSmall = NewWidget("Font")
GameFontDisableSmall = NewWidget("Font")
NumberFontNormal = NewWidget("Font")

SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2 }
function PlaySound() end
BACKDROP_SLIDER_8_8 = {}

-- Settings API
local categories = {}
Settings = {
    RegisterCanvasLayoutCategory = function(panel, title)
        local cat = { __panel = panel, __title = title, GetID = function() return #categories + 1 end }
        categories[#categories + 1] = cat
        return cat
    end,
    RegisterCanvasLayoutSubcategory = function(parent, panel, title)
        local cat = { __panel = panel, __title = title, GetID = function() return #categories + 1 end }
        categories[#categories + 1] = cat
        return cat
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
}
C_AddOns = { GetAddOnMetadata = function() return "2.1.0" end }

-- Timers
local timers, tickers = {}, {}
C_Timer = {
    After = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end,
    NewTicker = function(interval, fn)
        local t = { interval = interval, fn = fn }
        tickers[#tickers + 1] = t
        return t
    end,
}

local function RunTickers()
    for _, t in ipairs(tickers) do t.fn() end
end

-- Dropdown machinery
local menuCaptured = {}
local dropdownInits = {}
function UIDropDownMenu_Initialize(frame, fn, mode) dropdownInits[frame] = fn end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info) menuCaptured[#menuCaptured + 1] = info end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetSelectedValue() end
function UIDropDownMenu_SetText() end
function UIDropDownMenu_EnableDropDown() end
function UIDropDownMenu_DisableDropDown() end
function ToggleDropDownMenu(level, value, frame, anchor)
    menuCaptured = {}
    local init = dropdownInits[frame]
    if init then init(frame) end
end

-- Unit API
local playerGuid = "Player-0-ME"
function UnitGUID(unit)
    if unit == "player" then return playerGuid end
    return nil
end
function UnitName(unit) if unit == "player" then return "Devinp" end return nil end
function UnitClass(unit) if unit == "player" then return "Warrior", "WARRIOR" end return nil end
function UnitExists(unit) return unit == "player" end
function UnitHealth() return 5000 end
function UnitHealthMax() return 8000 end
function UnitIsFeignDeath() return false end
function IsInRaid() return false end
function GetNumGroupMembers() return 0 end
local instState = { inInstance = false, itype = "none", id = 0 }
function IsInInstance() return instState.inInstance, instState.itype end
function GetInstanceInfo()
    return "Azeroth", instState.itype, 0, "", 5, 0, false, instState.id, 5
end
function GetCursorPosition() return 0, 0 end
function InCombatLockdown() return false end
function IsInGroup(category) return false end
function IsInGuild() return true end
function GetSpellInfo(id) return "Spell" .. tostring(id), nil, "Interface\\Icons\\Icon" .. tostring(id) end
function GetSpellTexture(id) return "Interface\\Icons\\Icon" .. tostring(id) end
LE_PARTY_CATEGORY_INSTANCE = 2
local sentChat = {}
function SendChatMessage(msg, channel)
    sentChat[#sentChat + 1] = { msg = msg, channel = channel }
end
RAID_CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    WARLOCK = { r = 0.53, g = 0.53, b = 0.93 },
    PRIEST = { r = 1, g = 1, b = 1 },
    SHAMAN = { r = 0, g = 0.44, b = 0.87 },
}
CLASS_ICON_TCOORDS = { WARRIOR = { 0, 0.25, 0, 0.25 } }
SlashCmdList = {}


-- ===========================================================================

-- ===========================================================================
-- Formulary-specific mock
-- ===========================================================================

-- The character: a Horde enchanter, mid route
local me = {
    rank = 146, maxRank = 150,
    known = { [13501] = true, [7457] = true, [14807] = true, [7418] = true, [7421] = true, [7795] = true },
    bags = { [11083] = 10 },
    bank = { [11083] = 30 },
    equipped = { [9] = 2140 }, -- bracers
    faction = "Horde",
    standing = {},
    combat = false,
}
function InCombatLockdown() return me.combat end
function UnitFactionGroup() return me.faction end
function GetFactionInfoByID(id) return "Faction" .. id, "", me.standing[id] end

-- Spells: real recipe names so the craft window matches by name
local DATA_NAMES = {}
function GetSpellInfo(id)
    local name = DATA_NAMES[id] or ("Spell" .. tostring(id))
    return name, nil, "Interface\\Icons\\Icon" .. tostring(id)
end
function GetSpellTexture(id) return "Interface\\Icons\\Icon" .. tostring(id) end
function IsSpellKnown(id) return me.known[id] == true end
IsPlayerSpell = nil

-- The skill list, with a header first the way the client shows it
function GetNumSkillLines() return me.maxRank > 0 and 3 or 1 end
function GetSkillLineInfo(i)
    if i == 1 then return "Professions", true end
    if i == 2 and me.maxRank > 0 then return "Enchanting", false, false, me.rank, 0, 0, me.maxRank end
    if i == 3 then return "First Aid", false, false, 10, 0, 0, 75 end
    return nil
end
local expandedHeaders = 0
function ExpandSkillHeader() expandedHeaders = expandedHeaders + 1 end

-- Items
local EQUIPLOC = { [2140] = "INVTYPE_WRIST", [2141] = "INVTYPE_CLOAK", [2142] = "INVTYPE_ROBE", [2143] = "INVTYPE_SHIELD" }
function GetItemInfo(id)
    local D = CommanderFormulary_Data and CommanderFormulary_Data.ENCHANTING
    local name = D and D.items[id] or ("Item" .. id)
    return name, "|Hitem:" .. id .. "|h[" .. name .. "]|h", 1, 1, 1, "Armor", "Misc", 20, EQUIPLOC[id], "Interface\\Icons\\Item" .. id
end
function GetItemCount(id, includeBank)
    return (me.bags[id] or 0) + (includeBank and (me.bank[id] or 0) or 0)
end
function GetItemIcon(id) return "Interface\\Icons\\Item" .. id end
C_Item = nil
local bagSlots = {} -- bag -> slot -> item id
C_Container = {
    GetContainerNumSlots = function(bag) return 16 end,
    GetContainerItemID = function(bag, slot) return bagSlots[bag] and bagSlots[bag][slot] end,
    PickupContainerItem = function(bag, slot) me.lastPickup = { "bag", bag, slot } end,
}
function GetInventoryItemID(unit, slot) return me.equipped[slot] end
function PickupInventoryItem(slot) me.lastPickup = { "slot", slot } end

-- The craft window
local craft = { shown = false, list = {}, skill = "Enchanting" }
CraftFrame = NewWidget("Frame", "CraftFrame")
CraftFrame.IsShown = function() return craft.shown end
function GetCraftDisplaySkillLine() return craft.skill, me.rank, me.maxRank end
function GetNumCrafts() return #craft.list end
function GetCraftInfo(i)
    local row = craft.list[i]
    if not row then return nil end
    return row.name, nil, row.header and "header" or "optimal", row.available or 5
end
-- Macros
-- Account macros index 1..120, character macros 121+, as the client does
local macros = {}
local macroWrites = 0
MAX_ACCOUNT_MACROS = 120
function GetMacroInfo(name) local m = macros[name]; if m then return name, m.icon, m.body end end
function GetMacroIndexByName(name) local m = macros[name]; if not m then return 0 end return m.perChar and 121 or 1 end
function GetNumMacros() local a, c = 0, 0 for _, m in pairs(macros) do if m.perChar then c = c + 1 else a = a + 1 end end return a, c end
function CreateMacro(name, icon, body, perChar)
    if me.combat then error("CreateMacro in combat") end
    macros[name] = { icon = icon, body = body, perChar = perChar and true or false }; macroWrites = macroWrites + 1
end
function EditMacro(name, newName, icon, body)
    if me.combat then error("EditMacro in combat") end
    macros[name].body = body; if icon then macros[name].icon = icon end; macroWrites = macroWrites + 1
end
function DeleteMacro(index)
    for name, m in pairs(macros) do if (m.perChar and 121 or 1) == index then macros[name] = nil end end
end

-- DoCraft is protected on this client; the mock makes calling it a hard
-- error so no insecure path back to it can creep in
function DoCraft() error("ADDON_ACTION_FORBIDDEN: DoCraft()") end
local popup = nil
local replaced = 0
function StaticPopup_Visible(which) return popup == which and 1 or nil end
function StaticPopup_Hide(which) if popup == which then popup = nil end end
function ReplaceEnchant() replaced = replaced + 1; error("ADDON_ACTION_FORBIDDEN: ReplaceEnchant()") end

-- Neighbours
local waypoints = {}
TomTom = { AddWaypoint = function(self, map, x, y, opts) waypoints[#waypoints + 1] = { map = map, x = x, y = y, title = opts.title } end }
local aucLists = {}
Auctionator = { API = { v1 = {
    ConvertToSearchString = function(caller, term) return '"' .. term.searchString .. '"' end,
    CreateShoppingList = function(caller, name, items) aucLists[#aucLists + 1] = { name = name, items = items } end,
} } }

function hooksecurefunc(tbl, name, fn) end
-- Events this client actually has, from Blizzard_APIDocumentationGenerated
-- (classic_anniversary, 2026-09-17). The real client throws on an unknown
-- name and the throw took every later registration down with it once; the
-- mock throws the same way so the list can never drift again.
local KNOWN_EVENTS = {}
for name in ([[
ADDON_LOADED PLAYER_LOGIN PLAYER_LOGOUT PLAYER_ENTERING_WORLD
SKILL_LINES_CHANGED CHAT_MSG_SKILL BAG_UPDATE_DELAYED PLAYERBANKSLOTS_CHANGED BANKFRAME_OPENED
CRAFT_SHOW CRAFT_UPDATE CRAFT_CLOSE SPELLS_CHANGED NEW_RECIPE_LEARNED UPDATE_FACTION
UNIT_INVENTORY_CHANGED PLAYER_REGEN_ENABLED PLAYER_REGEN_DISABLED REPLACE_ENCHANT
GET_ITEM_INFO_RECEIVED UPDATE_MACROS
]]):gmatch("%S+") do KNOWN_EVENTS[name] = true end
-- Buttons remember whether they are enabled
local baseIndex = WidgetMT.__index
WidgetMT.__index = function(self, key)
    if key == "RegisterEvent" then
        local fn = function(s, event)
            if not KNOWN_EVENTS[event] then
                error('Frame:RegisterEvent(): Attempt to register unknown event "' .. tostring(event) .. '"')
            end
            eventRegistry[event] = eventRegistry[event] or {}
            table.insert(eventRegistry[event], s)
        end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetEnabled" then
        local fn = function(s, v) s.__enabled = v and true or false end
        rawset(self, key, fn)
        return fn
    end
    if key == "IsEnabled" then
        local fn = function(s) return s.__enabled ~= false end
        rawset(self, key, fn)
        return fn
    end
    if key == "RegisterForClicks" then
        local fn = function(s, ...) s.__clicks = { ... } end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetAttribute" then
        local fn = function(s, name, value)
            if me.combat then error("attribute written in combat") end
            s.__attr = s.__attr or {}
            s.__attr[name] = value
        end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetAttribute" then
        local fn = function(s, name) return s.__attr and s.__attr[name] end
        rawset(self, key, fn)
        return fn
    end
    return baseIndex(self, key)
end
GameTooltip.Show = function() end
GameTooltip.SetHyperlink = function(s, link) s.__link = link end
GameTooltip.SetOwner = function() end
local played = {}
function PlaySound(id) played[#played + 1] = id return true end
SOUNDKIT.IG_QUEST_LIST_COMPLETE = 1 ; SOUNDKIT.IG_QUEST_LIST_COMPLETE = 1


-- Frames the Formulary uses beyond the shared mock
function HideUIPanel(f) f.__hiddenViaPanel = true; f:Hide() end
function GetSpellLink(id) return "|Henchant:" .. id .. "|h[spell]|h" end
local inserted = {}
function ChatEdit_InsertLink(link) inserted[#inserted + 1] = link; return true end
GameTooltip.SetHyperlink = function(s, link) s.__link = link end
GameTooltip.SetOwner = function() end
GameTooltip.Show = function() end
local baseIndex2 = WidgetMT.__index
WidgetMT.__index = function(self, key)
    if key == "SetHyperlink" then
        local fn = function(s, link) s.__link = link end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetFontString" then
        local fn = function(s) s.__fs = s.__fs or NewWidget("FontString"); return s.__fs end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetStringHeight" then
        local fn = function() return 12 end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetHeight" then
        local fn = function(s) return s.__h or 0 end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetHeight" then
        local fn = function(s, h) s.__h = h end
        rawset(self, key, fn)
        return fn
    end
    return baseIndex2(self, key)
end
me.standing = { [989] = 5 }

-- ===========================================================================
-- Load
-- ===========================================================================

local function Load(path)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    chunk()
end

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
Load(ADDONS .. "/Commander_Formulary/CommanderFormularyData_Enchanting.lua")
Load(ADDONS .. "/Commander_Formulary/CommanderFormularyModel.lua")
for _, rec in ipairs(CommanderFormulary_Data.ENCHANTING.recipes) do DATA_NAMES[rec.spell] = rec.name end
DATA_NAMES[7411] = "Enchanting"
Load(ADDONS .. "/Commander_Formulary/CommanderFormularyDB.lua")
Load(ADDONS .. "/Commander_Formulary/CommanderFormularyUI.lua")

local D = CommanderFormulary_Data.ENCHANTING

local function Fire(event, ...)
    for _, f in ipairs(eventRegistry[event] or {}) do
        local handler = f.__scripts.OnEvent
        if handler then handler(f, event, ...) end
    end
end
local function Settle()
    for _ = 1, 5 do
        local due = {}
        for i = #timers, 1, -1 do
            if timers[i].at <= now then due[#due + 1] = table.remove(timers, i) end
        end
        for i = #due, 1, -1 do due[i].fn() end
        if #due == 0 then break end
    end
end

local BaseCreateFrame = CreateFrame
CreateFrame = function(frameType, name, parent, template)
    local f = BaseCreateFrame(frameType, name, parent, template)
    f.__parent = parent
    return f
end

local function Under(root, f)
    local p = f.__parent
    local depth = 0
    while p and depth < 8 do
        if p == root then return true end
        p = p.__parent
        depth = depth + 1
    end
    return false
end
local function TextUnder(root)
    local out = {}
    for _, fs in ipairs(allFontStrings) do
        if fs.__shown ~= false and fs.__text and fs.__text ~= "" and Under(root, fs) then
            out[#out + 1] = fs.__text
        end
    end
    return (table.concat(out, "\n"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- ===========================================================================
-- A. Login and the window
-- ===========================================================================

CommanderFormularyChar = { known = { [13501] = true }, collapsed = {} }
CommanderFormularyDB = {}
me.rank, me.maxRank = 146, 150
me.known = { [7418] = true, [7421] = true, [7457] = true, [13501] = true, [14807] = true, [7795] = true }
me.bags = { [11083] = 20, [11039] = 1 }
me.bank = { [11083] = 40, [16224] = 1 }

Fire("ADDON_LOADED", "Commander_Formulary")
Fire("PLAYER_LOGIN")
Settle()
CHECK(#harnessFailedErrors == 0, "A1 login raised no errors", harnessFailedErrors[1])
CHECK(CommanderFormularyDB.EnableFormulary == true and CommanderFormularyDB.Filter == "ALL", "A2 defaults applied")
CHECK(_G.CommanderFormularyFrame == nil, "A3 no window built until asked")

CommanderFormulary_Show()
Settle()
local frame = _G.CommanderFormularyFrame
CHECK(frame ~= nil and frame.__shown, "A4 window built and shown")
local view = CommanderFormulary_View()
CHECK(view and view.rank == 146 and view.total == #D.recipes and view.known == 6, "A5 view built from the world", view and view.known)
local nav = TextUnder(frame.navPane)
CHECK(nav:find("Bracer", 1, true) and nav:find("Weapon", 1, true) and nav:find("Rods", 1, true), "A6 category headers painted")
CHECK(nav:find("Enchant Bracer - Minor Health", 1, true), "A6 recipe rows painted")
CHECK(nav:find("3 / ", 1, true), "A6 bracer count 3 known")
CHECK(nav:find("Vendor", 1, true) and nav:find("Trainer", 1, true), "A6 source words on unknown rows")
local header = TextUnder(frame.toolbar)
CHECK(header:find("146 / 150", 1, true) and header:find("6 / " .. #D.recipes .. " known", 1, true), "A7 header rank and count", header)
CHECK(header:find("learnable now", 1, true), "A7 learnable count in header")
CHECK(header:find("Expert trainable", 1, true), "A7 next rank trainable")
local detail = TextUnder(frame.detailPane)
CHECK(detail:find("Pick a recipe", 1, true), "A8 nothing selected yet")

-- ===========================================================================
-- B. Selecting, the briefing, the craft button
-- ===========================================================================

CommanderFormulary_Select(13501)
Settle()
detail = TextUnder(frame.detailPane)
CHECK(detail:find("Enchant Bracer - Lesser Stamina", 1, true), "B1 title")
CHECK(detail:find("REAGENTS", 1, true) and detail:find("Soul Dust", 1, true), "B1 reagents")
CHECK(detail:find("+40 bank", 1, true), "B1 bank share shown")
CHECK(detail:find("30 times", 1, true), "B1 craftable count ((20 + 40 bank) / 2)")
CHECK(detail:find("WHERE IT CAME FROM", 1, true) and detail:find("trainers at 130", 1, true), "B1 trainer source", detail)
CHECK(_G.CommanderFormularyRecipeTip and _G.CommanderFormularyRecipeTip.__link == "enchant:13501", "B1 embedded tooltip set to the recipe")
local craftBtn = _G.CommanderFormularyCraft
CHECK(craftBtn and craftBtn.__attr and craftBtn.__attr.macrotext == "/cast Enchant Bracer - Lesser Stamina", "B2 craft macro, cursor left to aim", craftBtn and craftBtn.__attr and craftBtn.__attr.macrotext)
CommanderFormularyDB.AutoTargetGear = true
me.equipped[9] = 2140
CommanderFormulary_Select(13501)
Settle()
CHECK(craftBtn.__attr.macrotext == "/cast Enchant Bracer - Lesser Stamina\n/use 9\n/click StaticPopup1Button1", "B2 on my gear adds /use and the answer", craftBtn.__attr.macrotext)
CommanderFormularyDB.AutoTargetGear = false

CommanderFormulary_Select(13419)
Settle()
detail = TextUnder(frame.detailPane)
CHECK(detail:find("not known", 1, true) and detail:find("HOW TO LEARN IT", 1, true), "B3 unknown recipe briefing")
CHECK(detail:find("IN YOUR BAGS", 1, true) and detail:find("Right-click it", 1, true), "B3 formula held")
CHECK(detail:find("Sold by Dalria", 1, true) and detail:find("Sold by Kulwia", 1, true), "B3 both vendors listed")
CHECK(detail:find("other faction", 1, true), "B3 the other faction's vendor marked")
CHECK(craftBtn.__parent.__shown == false, "B3 no craft button for an unknown recipe")

CommanderFormulary_Select(27984)
Settle()
detail = TextUnder(frame.detailPane)
CHECK(detail:find("Drops from Moroes", 1, true) and detail:find("Karazhan", 1, true) and detail:find("5%", 1, true), "B4 Moroes at 5%", detail)

CommanderFormulary_Select(27924)
Settle()
detail = TextUnder(frame.detailPane)
CHECK(detail:find("Requires Honored with Keepers of Time", 1, true), "B5 reputation line")
CHECK(detail:find("reputation", 1, true), "B5 vendor marked short")

CommanderFormulary_Select(27961)
Settle()
detail = TextUnder(frame.detailPane)
CHECK(detail:find("Outland trainers at 310", 1, true), "B6 outland trainer line", detail)
CHECK(detail:find("Felannia", 1, true) and not detail:find("Johan Barnes", 1, true), "B6 faction trainers only")

-- ===========================================================================
-- C. Filters, search, sort, collapse
-- ===========================================================================

-- Rows are pooled and hidden, and the mock does not propagate a parent's
-- Hide to its font strings, so count the ROWS that are shown
local function NavRecipeCount()
    local n = 0
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.__shown ~= false and f.name and f.name.__text and Under(frame.navPane, f)
            and f.name.__text:find("Enchant ", 1, true) then n = n + 1 end
    end
    return n
end
frame.filters.KNOWN.__scripts.OnClick(frame.filters.KNOWN)
Settle()
CHECK(CommanderFormularyDB.Filter == "KNOWN", "C1 filter set")
CHECK(NavRecipeCount() == 3, "C1 known filter shows the three known enchants", NavRecipeCount())
frame.filters.LEARNABLE.__scripts.OnClick(frame.filters.LEARNABLE)
Settle()
CHECK(NavRecipeCount() >= 2 and NavRecipeCount() < 40, "C1 learnable filter narrows", NavRecipeCount())
frame.filters.ALL.__scripts.OnClick(frame.filters.ALL)
Settle()
CommanderFormulary_Search("mongoose")
Settle()
CHECK(NavRecipeCount() == 1, "C2 search narrows to one", NavRecipeCount())
CommanderFormulary_Search("")
Settle()
CHECK(NavRecipeCount() > 100, "C2 search cleared")
local before = NavRecipeCount()
local wristHeader
for _, f in ipairs(frames) do
    if f.__kind == "Button" and f.name and f.name.__text == "Bracer" and f.__shown ~= false and f.__scripts.OnClick then wristHeader = f end
end
CHECK(wristHeader ~= nil, "C3 bracer header row found")
wristHeader.__scripts.OnClick(wristHeader)
Settle()
CHECK(CommanderFormularyChar.collapsed.WRIST == true, "C3 collapsed recorded")
CHECK(NavRecipeCount() < before, "C3 fewer rows when collapsed", NavRecipeCount() .. " < " .. before)
wristHeader.__scripts.OnClick(wristHeader)
Settle()
CHECK(CommanderFormularyChar.collapsed.WRIST == nil and NavRecipeCount() == before, "C3 expanded again")
wristHeader.__scripts.OnClick(wristHeader, "RightButton")
Settle()
CHECK(NavRecipeCount() == 0 and CommanderFormularyChar.collapsed.WEAPON == true, "C3 right-click folds every slot", NavRecipeCount())
wristHeader.__scripts.OnClick(wristHeader, "RightButton")
Settle()
CHECK(NavRecipeCount() == before, "C3 right-click again unfolds every slot", NavRecipeCount())

-- C4 the trainers at the foot of the navigator, and a trainer's briefing
local trainerRow
for _, f in ipairs(frames) do
    if f.__kind == "Button" and f.__shown ~= false and f.name and f.name.__text == "Felannia" and Under(frame.navPane, f) then trainerRow = f end
end
CHECK(trainerRow ~= nil, "C4 Horde trainer row listed")
local johan
for _, f in ipairs(frames) do
    if f.__kind == "Button" and f.__shown ~= false and f.name and f.name.__text == "Johan Barnes" and Under(frame.navPane, f) then johan = f end
end
CHECK(johan == nil, "C4 the other faction's trainer not listed")
trainerRow.__scripts.OnClick(trainerRow)
Settle()
detail = TextUnder(frame.detailPane)
CHECK(detail:find("Felannia", 1, true) and detail:find("Hellfire Peninsula (52.3, 36.0)", 1, true), "C4 trainer briefing with coordinates", detail)
CHECK(detail:find("WOULD TEACH YOU NOW", 1, true) and detail:find("Enchant Shield - Minor Stamina", 1, true), "C4 what the trainer would teach now", detail)

-- C5 the Craftable filter and the header's percent
frame.filters.CRAFTABLE.__scripts.OnClick(frame.filters.CRAFTABLE)
Settle()
CHECK(NavRecipeCount() == 1, "C5 one craftable recipe (Lesser Stamina from the soul dust)", NavRecipeCount())
frame.filters.ALL.__scripts.OnClick(frame.filters.ALL)
Settle()
CHECK(TextUnder(frame.toolbar):find("known (3%)", 1, true), "C5 header shows the percent", TextUnder(frame.toolbar))

-- C6 a formula's tooltip gets a verdict line
GameTooltip.GetItem = function(s) return "x", s.__itemLink end
GameTooltip.__lines = {}
GameTooltip.__itemLink = "|Hitem:11039:0|h[Formula]|h"
Fire("PLAYER_LOGIN") -- no-op for the hooks; they were installed at login
for _, f in ipairs(frames) do end
local hooked = GameTooltip.__scripts.OnTooltipSetItem
CHECK(hooked ~= nil, "C6 tooltip hook installed")
if hooked then
    hooked(GameTooltip)
    CHECK(GameTooltip.__lines[#GameTooltip.__lines] and GameTooltip.__lines[#GameTooltip.__lines]:find("can learn this now"), "C6 verdict: learnable", GameTooltip.__lines[#GameTooltip.__lines])
    GameTooltip.__lines = {}
    GameTooltip._cfmItem = nil
    GameTooltip.__itemLink = "|Hitem:22559:0|h[Formula]|h"
    hooked(GameTooltip)
    CHECK(GameTooltip.__lines[#GameTooltip.__lines]:find("at 375 skill"), "C6 verdict: needs skill", GameTooltip.__lines[#GameTooltip.__lines])
    GameTooltip.__lines = {}
    GameTooltip._cfmItem = nil
    GameTooltip.__itemLink = "|Hitem:6217:0|h[Rod]|h"
    hooked(GameTooltip)
    CHECK(#GameTooltip.__lines == 0, "C6 not a formula: nothing added")
end

-- ===========================================================================
-- D. The stock craft window is read and put away
-- ===========================================================================

frame:Hide()
craft.shown = true
craft.list = {
    { name = "Bracer", header = true },
    { name = "Enchant Bracer - Minor Stamina", spell = 7457 },
    { name = "Enchant Cloak - Minor Agility", spell = 13419 },
}
Fire("CRAFT_SHOW")
Settle()
CHECK(CommanderFormularyChar.known[13419] == true and CommanderFormularyChar.scanned, "D1 craft list read into memory")
CHECK(CraftFrame.__hiddenViaPanel == true, "D2 stock craft window put away")
CHECK(frame.__shown == true, "D2 formulary shown in its place")
Fire("CRAFT_CLOSE")
Settle()
-- with replacement off, the stock window is left alone
CommanderFormularyDB.ReplaceCraftWindow = false
CraftFrame.__hiddenViaPanel = nil
frame:Hide()
Fire("CRAFT_SHOW")
Settle()
CHECK(CraftFrame.__hiddenViaPanel == nil and frame.__shown == false, "D3 replacement off -> stock window stays")
Fire("CRAFT_CLOSE")
CommanderFormularyDB.ReplaceCraftWindow = true
-- a hunter's Beast Training is not ours
craft.skill = nil
Fire("CRAFT_SHOW")
Settle()
CHECK(frame.__shown == false, "D4 beast training ignored")
Fire("CRAFT_CLOSE")
craft.skill = "Enchanting"

-- ===========================================================================
-- E. Status, reset, combat
-- ===========================================================================

printLog = {}
CommanderFormulary_Status()
CHECK(#printLog == 2 and printLog[1]:find("146 / 150") and printLog[2]:find("spellbook"), "E1 status", printLog[1])
CommanderFormulary_ResetChar()
CHECK(next(CommanderFormularyChar.known) == nil, "E2 memory forgotten")

CommanderFormulary_Show()
Settle()
CommanderFormulary_Select(13501)
Settle()
me.combat = true
Fire("PLAYER_REGEN_DISABLED")
Settle()
CHECK(#harnessFailedErrors == 0, "E3 no attribute written in combat", harnessFailedErrors[1])
CHECK(craftBtn.__parent.__shown == false, "E3 craft holder hidden in combat")
me.combat = false
Fire("PLAYER_REGEN_ENABLED")
Settle()
CHECK(craftBtn.__parent.__shown == true, "E3 craft back after combat")

-- Restore defaults leaves the character's memory alone
CommanderFormularyChar.known[13501] = true
Commander.UI.ResetToDefaults(CommanderFormularyDB, CommanderFormulary_Defaults)
CHECK(CommanderFormularyChar.known[13501] == true and CommanderFormularyDB.Filter == "ALL", "E4 defaults leave memory alone")

CHECK(#harnessFailedErrors == 0, "Z no errors were swallowed", harnessFailedErrors[1])
io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
