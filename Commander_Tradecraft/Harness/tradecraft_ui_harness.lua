-- Commander Tradecraft UI harness (luajit).
--
--   /opt/homebrew/bin/luajit tradecraft_ui_harness.lua
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
-- Tradecraft-specific mock
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
    local D = CommanderTradecraft_Data
    local info = D and D.ITEMS[id]
    local name = info and info.name or ("Item" .. id)
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
local crafted = {}
local targeting = false
function DoCraft(i)
    crafted[#crafted + 1] = craft.list[i] and craft.list[i].name
    local row = craft.list[i]
    local D = CommanderTradecraft_Data
    local spell = row and row.spell
    targeting = spell and D.RECIPES[spell] and D.RECIPES[spell].target and true or false
end
function SpellIsTargeting() return targeting end
local popup = nil
local replaced = 0
function StaticPopup_Visible(which) return popup == which and 1 or nil end
function StaticPopup_Hide(which) if popup == which then popup = nil end end
function ReplaceEnchant() replaced = replaced + 1 end

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
GET_ITEM_INFO_RECEIVED
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
    return baseIndex(self, key)
end
GameTooltip.Show = function() end
GameTooltip.SetHyperlink = function(s, link) s.__link = link end
GameTooltip.SetOwner = function() end
local played = {}
function PlaySound(id) played[#played + 1] = id return true end
SOUNDKIT.IG_QUEST_LIST_COMPLETE = 1 ; SOUNDKIT.IG_QUEST_LIST_COMPLETE = 1

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
Load(ADDONS .. "/Commander_Tradecraft/CommanderTradecraftData.lua")
Load(ADDONS .. "/Commander_Tradecraft/CommanderTradecraftEngine.lua")
for spell, rec in pairs(CommanderTradecraft_Data.RECIPES) do DATA_NAMES[spell] = rec.name end
DATA_NAMES[7411] = "Enchanting"
Load(ADDONS .. "/Commander_Tradecraft/CommanderTradecraftDB.lua")
Load(ADDONS .. "/Commander_Tradecraft/CommanderTradecraft.lua")

local D = CommanderTradecraft_Data

local function Fire(event, ...)
    for _, f in ipairs(eventRegistry[event] or {}) do
        local handler = f.__scripts.OnEvent
        if handler then handler(f, event, ...) end
    end
end
-- Run every C_Timer.After that is due (the rebuild is scheduled at delay 0)
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
local function Advance(seconds) now = now + seconds Settle() end

-- Text of every visible font string on the guide, top to bottom-ish
local guide = _G.CommanderTradecraftGuide
local function GuideText()
    local out = {}
    for _, fs in ipairs(allFontStrings) do
        if fs.__parent == guide and fs.__shown ~= false and fs.__text and fs.__text ~= "" then
            out[#out + 1] = fs.__text
        end
    end
    return table.concat(out, "\n")
end
local function Has(text) return GuideText():find(text, 1, true) ~= nil end
-- Buttons on the guide (or in a holder on the guide) that are visible
local function Buttons()
    local out = {}
    for _, f in ipairs(frames) do
        local parent = f.__parent
        local onGuide = parent == guide or (type(parent) == "table" and parent.__parent == guide)
        local visible = f.__shown ~= false and (parent == guide or (type(parent) == "table" and parent.__shown ~= false))
        if f.__kind == "Button" and onGuide and visible and f.__text and f.__text ~= "" then
            out[f.__text] = f
        end
    end
    return out
end
-- The mock's CreateFrame does not record parents; patch it to
local BaseCreateFrame = CreateFrame
CreateFrame = function(frameType, name, parent, template)
    local f = BaseCreateFrame(frameType, name, parent, template)
    f.__parent = parent
    return f
end

-- ===========================================================================
-- A. Login
-- ===========================================================================

-- A previous session left a choice and a bit of memory behind
CommanderTradecraftChar = { choices = { ["156-185"] = "alt" }, knownRecipes = { [13501] = true } }
CommanderTradecraftDB = { Margin = 0.2 }

-- The frames were created at load with the mock's original CreateFrame; the
-- guide is found by name
guide = _G.CommanderTradecraftGuide
CHECK(guide ~= nil, "A1 guide frame exists")
-- Re-parent bookkeeping for pooled widgets created later: they use the
-- patched CreateFrame, but font strings record __parent already.

Fire("ADDON_LOADED", "Commander_Tradecraft")
Fire("PLAYER_LOGIN")
Settle()
CHECK(#harnessFailedErrors == 0, "A2 login raised no errors", harnessFailedErrors[1])
CHECK(CommanderTradecraftDB.EnableTradecraft == true, "A3 defaults applied")
CHECK(CommanderTradecraftDB.Margin == 0.2, "A3 saved setting kept")
CHECK(CommanderTradecraftChar.choices["156-185"] == "alt", "A3 choice kept")
CHECK(type(CommanderTradecraftChar.skipped) == "table", "A3 skipped table seeded")
CHECK(SlashCmdList["COMMANDER_TRADECRAFT"] ~= nil or next(SlashCmdList) ~= nil, "A4 slash registered")

local plan = CommanderTradecraft_Plan()
CHECK(plan ~= nil and plan.rank == 146 and plan.maxRank == 150, "A5 skill read from the list", plan and plan.rank)
CHECK(plan.current and plan.current.spell == 13501, "A6 current step is Lesser Stamina", plan.current and plan.current.key)
CHECK(guide.__shown, "A7 guide shown")
CHECK(Has("Enchant Bracer - Lesser Stamina"), "A8 step title painted")
CHECK(Has("Soul Dust"), "A8 reagent painted")
CHECK(Has("30 in bank"), "A8 bank share shown")
CHECK(Has("STEP"), "A8 step counter")
CHECK(Has("Expert"), "A9 expert trainer banner (rank 146 >= 125)")
CHECK(Has("Runed Golden Rod"), "A10 preview shows the next step")
local b = Buttons()
CHECK(b["Craft"] ~= nil and b["Craft"].__enabled == false, "A11 craft disabled with window closed")
CHECK(b["Open Enchanting"] ~= nil, "A11 secure open button offered")
CHECK(b["Skip"] and b["Route"] and b["Shopping"], "A11 footer buttons")
CHECK(b["Alternative"] ~= nil, "A11 alternative offered: 156-185 is coming and has two paths")

-- ===========================================================================
-- B. Skill-ups and the craft window
-- ===========================================================================

-- B0 a hunter's Beast Training is the same frame with no skill line: not ours
craft.shown = true
craft.skill = nil
craft.list = { { name = "Growl", spell = nil } }
CommanderTradecraftDB.ShowGuide = false
guide:Hide()
Fire("CRAFT_SHOW")
Settle()
CHECK(CommanderTradecraftDB.ShowGuide == false, "B0 beast training does not open the guide")
Fire("CRAFT_CLOSE")
Settle()
craft.skill = "Enchanting"

-- B1 opening the craft window scans it: a formula learned on this session
-- shows up as known, and the guide auto-opens
craft.shown = true
craft.list = {
    { name = "Bracer", header = true },
    { name = "Enchant Bracer - Lesser Stamina", spell = 13501 },
    { name = "Enchant Bracer - Minor Health", spell = 7418 },
    { name = "Enchant Cloak - Minor Agility", spell = 13419 },
}
Fire("CRAFT_SHOW")
Settle()
CHECK(CommanderTradecraftChar.knownRecipes[13419] == true, "B1 craft window scan remembers recipes")
CHECK(CommanderTradecraftDB.ShowGuide == true and guide.__shown, "B1 guide auto-opened with the craft window")
b = Buttons()
CHECK(b["Craft"] and b["Craft"].__enabled ~= false, "B1 craft enabled with the window open")
CHECK(b["Open Enchanting"] == nil, "B1 open button gone while open")

-- B2 the craft button: DoCraft, then the bracers, then the replace answer
me.lastPickup = nil
popup = "REPLACE_ENCHANT"
b["Craft"].__scripts.OnClick(b["Craft"])
CHECK(crafted[#crafted] == "Enchant Bracer - Lesser Stamina", "B2 DoCraft on the right index", crafted[#crafted])
Advance(0.05)
CHECK(me.lastPickup and me.lastPickup[1] == "slot" and me.lastPickup[2] == 9, "B2 cast on equipped bracers", me.lastPickup and me.lastPickup[2])
Advance(0.1)
CHECK(replaced == 1 and popup == nil, "B2 replace-enchant answered and hidden", replaced)
-- A popup that appears long after our cast is not ours to answer
popup = "REPLACE_ENCHANT"
Advance(5)
CHECK(replaced == 1 and popup == "REPLACE_ENCHANT", "B2 a late popup is left alone")
Fire("REPLACE_ENCHANT")
CHECK(replaced == 1, "B2 nor via the event")
popup = nil
-- The event path: the client raises REPLACE_ENCHANT as the cursor lands
b["Craft"].__scripts.OnClick(b["Craft"])
Advance(0.05)
popup = "REPLACE_ENCHANT"
Fire("REPLACE_ENCHANT")
CHECK(replaced == 2 and popup == nil, "B2 answered from the event", replaced)
Advance(1)
CHECK(replaced == 2, "B2 timers find nothing left to answer")
-- A tome in the shield slot is not a shield
me.equipped[17] = 9999
EQUIPLOC[9999] = "INVTYPE_HOLDABLE"
me.equipped[9] = nil
bagSlots[0] = nil

-- B3 no bracers equipped: the one in the bags is used; none at all: refused
bagSlots[0] = { [3] = 2140 }
b["Craft"].__scripts.OnClick(b["Craft"])
Advance(0.05)
CHECK(me.lastPickup[1] == "bag" and me.lastPickup[2] == 0 and me.lastPickup[3] == 3, "B3 bag bracers targeted")
bagSlots[0] = nil
local before = #crafted
printLog = {}
b["Craft"].__scripts.OnClick(b["Craft"])
CHECK(#crafted == before, "B3 no target -> no craft")
CHECK(printLog[#printLog] and printLog[#printLog]:find("bracers"), "B3 told what to equip", printLog[#printLog])
Fire("UNIT_INVENTORY_CHANGED", "player")
Settle()
CHECK(Has("You need bracers"), "B3 warning painted on the step")
me.equipped[9] = 2140

-- B4 turning off auto-target leaves the cursor alone
CommanderTradecraftDB.AutoTargetGear = false
me.lastPickup = nil
b = Buttons()
b["Craft"].__scripts.OnClick(b["Craft"])
Advance(0.2)
CHECK(me.lastPickup == nil, "B4 no targeting when off")
CommanderTradecraftDB.AutoTargetGear = true

-- B5 a skill-up: rank climbs to 155, the step completes with a chat line
-- and a sound, the next step (the golden rod) is current
printLog = {}
played = {}
me.rank = 155
Fire("SKILL_LINES_CHANGED")
Settle()
plan = CommanderTradecraft_Plan()
CHECK(plan.current and plan.current.spell == 13628, "B5 golden rod current", plan.current and plan.current.key)
CHECK(#printLog > 0 and printLog[#printLog]:find("done") and printLog[#printLog]:find("Runed Golden Rod"), "B5 step completion announced", printLog[#printLog])
CHECK(#played == 1, "B5 sound played")
CHECK(Has("You do not know this recipe yet") and Has("teaches it at 150"), "B5 unknown trainer recipe explained")
CHECK(Has("Runed Copper Rod") == false, "B5 no copper rod mention")
-- The rod step warns about the missing Runed Silver Rod reagent
CHECK(Has("Runed Silver Rod"), "B5 silver rod reagent listed")
CHECK(Has("it is a reagent, not just a tool"), "B5 rod warning")

-- B6 a bag update repaints counts
me.bags[11083] = 40
Fire("BAG_UPDATE_DELAYED")
Settle()
CHECK(Has("Soul Dust"), "B6 soul dust still on the rod step")

-- B7 the chosen alternative for 156-185 shows in the preview
CHECK(Has("Enchant Bracer - Lesser Stamina") and not Has("Buy Formula: Enchant Bracer - Lesser Strength"), "B7 alt path in preview")

-- ===========================================================================
-- C. Alternatives, skipping, the buy step
-- ===========================================================================

-- C1 back on the main path via the slash entry point. The current step
-- (the golden rod) has no alternative; the next segment does, and that is
-- the one the press applies to
b = Buttons()
CHECK(b["Alternative"] ~= nil, "C1 alternative offered for the coming segment")
CommanderTradecraft_Alternative("main")
Settle()
CHECK(CommanderTradecraftChar.choices["156-185"] == "main", "C1 choice written")
me.rank = 156
Fire("CHAT_MSG_SKILL")
Settle()
plan = CommanderTradecraft_Plan()
CHECK(plan.current and plan.current.kind == "buy" and plan.current.item == 11101, "C2 buy step current at 156", plan.current and plan.current.key)
CHECK(Has("Buy Formula: Enchant Bracer - Lesser Strength"), "C2 buy title painted")
CHECK(Has("Kulwia") and not Has("Dalria"), "C2 Horde sees Kulwia only")
CHECK(Has("25s"), "C2 price painted")
CHECK(Has("Stonetalon Mountains"), "C2 zone painted")
b = Buttons()
CHECK(b["Go"] ~= nil, "C3 waypoint button")
b["Go"].__scripts.OnClick(b["Go"])
CHECK(#waypoints == 1 and waypoints[1].map == 1442 and math.abs(waypoints[1].x - 0.454) < 0.001, "C3 TomTom waypoint on Stonetalon", waypoints[1] and waypoints[1].map)
CHECK(b["Alternative"] ~= nil, "C3 alternative button on a two-path segment")
-- toggling from the button flips to alt
b["Alternative"].__scripts.OnClick(b["Alternative"])
Settle()
CHECK(CommanderTradecraftChar.choices["156-185"] == "alt", "C3 button toggles the path")
b = Buttons()
b["Alternative"].__scripts.OnClick(b["Alternative"])
Settle()
CHECK(CommanderTradecraftChar.choices["156-185"] == "main", "C3 and back")

-- C3b a later segment can be decided ahead by key
CommanderTradecraft_Alternative("320-340 alt")
Settle()
CHECK(CommanderTradecraftChar.choices["320-340"] == "alt", "C3b segment key sets a later choice")
CommanderTradecraft_Alternative("320-340")
Settle()
CHECK(CommanderTradecraftChar.choices["320-340"] == "main", "C3b segment key alone toggles")
printLog = {}
CommanderTradecraft_Alternative("999-1000 alt")
CHECK(printLog[#printLog]:find("no segment"), "C3b unknown segment refused")
CommanderTradecraft_Alternative("90-100 alt")
CHECK(printLog[#printLog]:find("no alternative"), "C3b single-path segment refused")
CommanderTradecraftChar.choices["320-340"] = nil

-- C4 holding the formula
me.bags[11101] = 1
Fire("BAG_UPDATE_DELAYED")
Settle()
CHECK(Has("right-click it to learn"), "C4 holding hint")
-- learning it (SPELLS_CHANGED) moves on
me.bags[11101] = nil
me.known[13536] = true
Fire("SPELLS_CHANGED")
Settle()
plan = CommanderTradecraft_Plan()
CHECK(plan.current and plan.current.spell == 13536, "C4 learned -> craft step", plan.current and plan.current.key)

-- C5 skip and un-skip
CommanderTradecraft_Skip()
Settle()
plan = CommanderTradecraft_Plan()
CHECK(plan.current and plan.current.spell == 13661, "C5 skipped to Bracer - Strength", plan.current and plan.current.key)
CHECK(CommanderTradecraftChar.skipped["156-185:main:2"] == true, "C5 skip recorded")
CommanderTradecraft_Unskip()
Settle()
plan = CommanderTradecraft_Plan()
CHECK(plan.current and plan.current.spell == 13536, "C5 un-skipped", plan.current and plan.current.key)
CHECK(next(CommanderTradecraftChar.skipped) == nil, "C5 skip cleared")

-- C6 reset progress forgets choices and skips, never skill
CommanderTradecraftChar.choices["110-135"] = "alt"
CommanderTradecraft_ResetProgress()
Settle()
CHECK(next(CommanderTradecraftChar.choices) == nil and next(CommanderTradecraftChar.skipped) == nil, "C6 reset")
CHECK(CommanderTradecraft_Plan().rank == 156, "C6 skill untouched")

-- ===========================================================================
-- D. The trainer banner and the cap
-- ===========================================================================

me.rank = 225
me.maxRank = 225
me.known[13746] = true
Fire("SKILL_LINES_CHANGED")
Settle()
CHECK(Has("You are at your cap (225)"), "D1 capped banner")
CHECK(Has("Artisan"), "D1 names the rank")
CHECK(Has("At your skill cap"), "D1 step flagged capped")
me.maxRank = 300
Fire("SKILL_LINES_CHANGED")
Settle()
CHECK(not Has("At your skill cap"), "D2 trained -> flag gone")
-- Master: Horde trainers listed with waypoint buttons
me.rank = 285
Fire("SKILL_LINES_CHANGED")
Settle()
CHECK(Has("Master") and Has("Felannia") and not Has("Johan Barnes"), "D3 master trainers for the faction")
CHECK(Has("High Enchanter Bardolan"), "D3 neutral trainer listed")

-- D4 no profession at all
me.rank, me.maxRank = 0, 0
Fire("SKILL_LINES_CHANGED")
Settle()
plan = CommanderTradecraft_Plan()
CHECK(not plan.hasProfession, "D4 no profession")
CHECK(guide.__shown == false, "D4 hidden for a character without the profession")
CommanderTradecraft_Show()
Settle()
CHECK(guide.__shown == true, "D4 but shown when asked")
CHECK(Has("Learn Enchanting"), "D4 learn banner")
b = Buttons()
CHECK(b["Craft"] == nil and b["Skip"] == nil, "D4 no step buttons without a profession")
me.rank, me.maxRank = 285, 300

-- ===========================================================================
-- E. The ledger
-- ===========================================================================

CommanderTradecraft_Route()
Settle()
local ledger = _G.CommanderTradecraftLedger
CHECK(ledger and ledger.__shown, "E1 ledger opens")
CHECK(ledger.text:find(">|r", 1, true) and ledger.text:find("+|r", 1, true), "E1 route has current and done marks")
CHECK(ledger.text:find("taking:"), "E1 alternatives listed")
CHECK(ledger.text:find("Lorelae Wintersong"), "E1 vendor in route")
CHECK(ledger.text:find("JOURNEYMAN 75 – 150", 1, true) and ledger.text:find("done"), "E1 bracket headings with done tags")
CommanderTradecraft_Shopping()
Settle()
CHECK(ledger.title.__text:find("Shopping"), "E2 shopping mode")
CHECK(ledger.text:find("Illusion Dust"), "E2 illusion dust to buy")
CHECK(ledger.text:find("Formulas") and ledger.text:find("in all"), "E2 formula total")
CHECK(ledger.text:find("Made by Blacksmiths"), "E2 rod note")
CHECK(not ledger.text:find("Runed Truesilver Rod"), "E2 made rods not shopped")
CHECK(ledger.text:find("ARTISAN 225 – 300", 1, true) and ledger.text:find("you are here", 1, true), "E2 current bracket headed")
CHECK(ledger.text:find("EVERYTHING LEFT", 1, true), "E2 whole-route totals close the list")
CHECK(not ledger.text:find("APPRENTICE 1 – 75", 1, true), "E2 done brackets omitted")
CHECK(ledger.aucButton.__shown and ledger.aucAllButton.__shown, "E3 auctionator buttons shown")
-- Default hand-off is the current bracket (225-300: Dream and Illusion dust, pearls, rods);
-- "all" is the whole route
CommanderTradecraft_AuctionatorList()
CHECK(#aucLists == 1 and aucLists[1].name:find("Enchanting 225-300", 1, true) and #aucLists[1].items >= 3, "E3 bracket list handed to Auctionator", aucLists[1] and aucLists[1].name)
CHECK(aucLists[1].items[1]:sub(1, 1) == '"', "E3 exact search terms")
CommanderTradecraft_AuctionatorList("all")
CHECK(#aucLists == 2 and #aucLists[2].items > #aucLists[1].items, "E3 whole route is longer", aucLists[2] and #aucLists[2].items)
-- typing into the ledger is thrown away
ledger.edit.__scripts.OnTextChanged(ledger.edit, true)
CHECK(ledger.edit.__text == ledger.text, "E4 ledger is read-only in effect")

-- ===========================================================================
-- F. Settings and the combat rule
-- ===========================================================================

-- F1 disabling hides the guide; enabling brings it back
CommanderTradecraftDB.EnableTradecraft = false
Commander.Notify(COMMANDER_TRADECRAFT_EVENTS.UPDATE)
Settle()
CHECK(guide.__shown == false, "F1 disabled -> hidden")
CommanderTradecraftDB.EnableTradecraft = true
Commander.Notify(COMMANDER_TRADECRAFT_EVENTS.UPDATE)
Settle()
CHECK(guide.__shown == true, "F1 enabled -> shown")

-- F2 in combat the secure button is not touched or offered (on a craft
-- step: Shield - Greater Stamina at 265, formula already known)
craft.shown = false
Fire("CRAFT_CLOSE")
me.rank = 265
me.known[20017] = true
Fire("SKILL_LINES_CHANGED")
Settle()
CHECK(CommanderTradecraft_Plan().current.spell == 20017, "F2 on a craft step")
me.combat = true
Fire("PLAYER_REGEN_DISABLED")
Settle()
b = Buttons()
CHECK(b["Open Enchanting"] == nil, "F2 no secure button in combat")
me.combat = false
Fire("PLAYER_REGEN_ENABLED")
Settle()
b = Buttons()
CHECK(b["Open Enchanting"] ~= nil, "F2 back after combat", (function() local t = {} for k in pairs(b) do t[#t+1] = k end return table.concat(t, ",") end)())

-- F3 finished: hidden by default, and Show explains why
me.rank, me.maxRank = 375, 375
Fire("SKILL_LINES_CHANGED")
Settle()
CHECK(CommanderTradecraft_Plan().finished, "F3 finished")
CHECK(guide.__shown == false, "F3 hidden when finished")
printLog = {}
CommanderTradecraft_Show()
CHECK(printLog[#printLog] and printLog[#printLog]:find("complete"), "F3 show explains", printLog[#printLog])
CommanderTradecraftDB.HideWhenFinished = false
Commander.Notify(COMMANDER_TRADECRAFT_EVENTS.UPDATE)
Settle()
CHECK(guide.__shown == true and Has("complete"), "F3 shown with the option off")

-- F4 restore defaults touches settings only
CommanderTradecraftChar.choices["110-135"] = "alt"
Commander.UI.ResetToDefaults(CommanderTradecraftDB, CommanderTradecraft_Defaults)
CHECK(CommanderTradecraftDB.Margin == 0.10 and CommanderTradecraftChar.choices["110-135"] == "alt", "F4 defaults leave progress alone")

-- F5 the status line
printLog = {}
me.rank, me.maxRank = 200, 225
Fire("SKILL_LINES_CHANGED")
Settle()
CommanderTradecraft_Status()
CHECK(#printLog >= 2 and printLog[1]:find("200") and printLog[2]:find("step"), "F5 status", printLog[1])

CHECK(#harnessFailedErrors == 0, "Z no errors were swallowed", harnessFailedErrors[1])
-- The headers were expanded exactly once: for the no-profession case in
-- D4, where the line genuinely was not there. Never while it was.
CHECK(expandedHeaders == 1, "Z skill headers expanded only when the line was missing", expandedHeaders)

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
