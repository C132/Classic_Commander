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
    if i == 3 then return "First Aid", false, false, me.faRank or 10, 0, 0, me.faMax or 75 end
    return nil
end
local expandedHeaders = 0
function ExpandSkillHeader() expandedHeaders = expandedHeaders + 1 end

-- Items
local EQUIPLOC = { [2140] = "INVTYPE_WRIST", [2141] = "INVTYPE_CLOAK", [2142] = "INVTYPE_ROBE", [2143] = "INVTYPE_SHIELD" }
-- A few gear items with quality, item level, sell price and class, for the
-- disenchant advice
local GEAR = { [2140] = { 2, 60, 3000, 4 }, [2141] = { 3, 115, 5000, 4 }, [2144] = { 1, 30, 50, 4 }, [2145] = { 2, 60, 2500, 2 } }
function GetItemInfo(id)
    if type(id) == "string" then id = tonumber(id:match("item:(%d+)")) or id end
    local D = CommanderFormulary_Data and CommanderFormulary_Data.ENCHANTING
    local FA = CommanderFormulary_Data and CommanderFormulary_Data.FIRSTAID
    local name = (D and D.items[id]) or (FA and FA.items[id]) or ("Item" .. id)
    local g = GEAR[id]
    return name, "|Hitem:" .. id .. "|h[" .. name .. "]|h", g and g[1] or 1, g and g[2] or 1, 1, "Armor", "Misc", 20, EQUIPLOC[id],
        "Interface\\Icons\\Item" .. id, g and g[3] or 0, g and g[4] or 7, 12
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
-- The trade skill window (First Aid): its own frame, its own list, and a
-- skill line that answers name, rank, maxRank
local trade = { shown = false, list = {}, skill = "First Aid" }
TradeSkillFrame = NewWidget("Frame", "TradeSkillFrame")
TradeSkillFrame.IsShown = function() return trade.shown end
function GetTradeSkillLine() return trade.skill, me.faRank or 10, me.faMax or 75 end
function GetNumTradeSkills() return #trade.list end
function GetTradeSkillInfo(i)
    local row = trade.list[i]
    if not row then return nil end
    return row.name, row.header and "header" or "optimal", row.available or 5, true
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
-- Commander Orders: a recording stand-in for its public table (Add answers
-- a uid, AddRoute a route id). TomTom is gone from the suite. 3.1's Go-to
-- (GoTo, PlaceFor, IsGoing, Reason, WayLineFor, SharePoint, CopyText,
-- FormatCoords) records the same way: a GoTo lands in `waypoints` with the
-- target's fields and the options merged, as Orders' GoTo hands Add, and
-- says "Waypoint set: <title>" as Orders does when it is not silent; a
-- locator query (no map) is answered by `locatorAnswers`, keyed by the
-- townsfolk name or "door:<instance>".
local waypoints, routes, shares, copies = {}, {}, {}, {}
local locatorAnswers = {}
local function QueryKey(target)
    if type(target) ~= "table" then return nil end
    if target.townsfolk then return target.townsfolk end
    if type(target.entrance) == "table" and target.entrance.instance then return "door:" .. target.entrance.instance end
    return nil
end
local function StubIsQuery(target) return type(target) == "table" and target.map == nil end
local IsControlDown = false
IsControlKeyDown = function() return IsControlDown end
CommanderOrders = {
    IsAvailable = function() return true end,
    Add = function(spec)
        waypoints[#waypoints + 1] = { map = spec.map, x = spec.x, y = spec.y, title = spec.title, spec = spec }
        return "w" .. #waypoints
    end,
    AddRoute = function(spec)
        routes[#routes + 1] = spec
        return "r" .. #routes
    end,
    GoTo = function(target, opts)
        opts = opts or {}
        local spec = {}
        if StubIsQuery(target) then
            local a = locatorAnswers[QueryKey(target) or "?"]
            if not a then
                if not opts.silent then print("Commander Orders: Needs Questie to look that up") end
                return nil, "noquestie"
            end
            for k, v in pairs(a) do spec[k] = v end
            spec.query = target
        else
            for k, v in pairs(target) do spec[k] = v end
        end
        for k, v in pairs(opts) do spec[k] = v end
        spec.setArrow = opts.setArrow ~= false
        waypoints[#waypoints + 1] = { map = spec.map, x = spec.x, y = spec.y, title = spec.title, spec = spec }
        if not opts.silent then print("Commander Orders: Waypoint set: " .. tostring(spec.title)) end
        return "w" .. #waypoints
    end,
    PlaceFor = function(target)
        if StubIsQuery(target) then
            local a = locatorAnswers[QueryKey(target) or "?"]
            if not a then return nil, "noquestie" end
            return { map = a.map, x = a.x, y = a.y, title = a.title }
        end
        return { map = target.map, x = target.x, y = target.y, title = target.title }
    end,
    IsGoing = function() return false end,
    Reason = function(why) return why == "noquestie" and "Needs Questie to look that up" or tostring(why) end,
    WayLineFor = function(m, x, y, t) return ("/way #%d %.2f %.2f%s"):format(m, x * 100, y * 100, t and (" " .. t) or "") end,
    FormatCoords = function(x, y) return ("%.1f, %.1f"):format(x * 100, y * 100) end,
    SharePoint = function(spec, channel) shares[#shares + 1] = { spec = spec, channel = channel } return true end,
    CopyText = function(text) copies[#copies + 1] = text return true end,
}
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
CRAFT_SHOW CRAFT_UPDATE CRAFT_CLOSE TRADE_SKILL_SHOW TRADE_SKILL_UPDATE TRADE_SKILL_CLOSE SPELLS_CHANGED NEW_RECIPE_LEARNED UPDATE_FACTION
UNIT_INVENTORY_CHANGED PLAYER_REGEN_ENABLED PLAYER_REGEN_DISABLED REPLACE_ENCHANT
GET_ITEM_INFO_RECEIVED UPDATE_MACROS AUCTION_HOUSE_SHOW AUCTION_HOUSE_CLOSED
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
    -- The last anchor is recorded, so stacked rows can be checked for overlap
    if key == "SetPoint" then
        local fn = function(s, point, rel, relPoint, x, y) s.__point = { point, rel, relPoint, x, y } end
        rawset(self, key, fn)
        return fn
    end
    return baseIndex2(self, key)
end
me.standing = { [989] = 5 }
-- Auctionator's prices
local PRICES = { [11083] = 300, [16204] = 5000, [16203] = 12000, [14344] = 36000, [22449] = 30000, [22450] = 40000,
    [4470] = 38, [10939] = 1500, [11288] = 4000, [2140] = 6000, [2141] = 20000 }
Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(caller, item) return PRICES[item] end } } }

-- ===========================================================================
-- Load
-- ===========================================================================

local function Load(path)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    chunk()
end

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderGoButton.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
Load(ADDONS .. "/Commander_Formulary/CommanderFormularyData_Enchanting.lua")
Load(ADDONS .. "/Commander_Formulary/CommanderFormularyData_FirstAid.lua")
Load(ADDONS .. "/Commander_Formulary/CommanderFormularyModel.lua")
for _, rec in ipairs(CommanderFormulary_Data.ENCHANTING.recipes) do DATA_NAMES[rec.spell] = rec.name end
for _, rec in ipairs(CommanderFormulary_Data.FIRSTAID.recipes) do DATA_NAMES[rec.spell] = rec.name end
DATA_NAMES[7411] = "Enchanting"
DATA_NAMES[3273] = "First Aid"
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

-- Under `root`, and under no hidden frame on the way: a pooled row that
-- was hidden keeps its text, and text under a hidden row is not on screen
local function Under(root, f)
    local p = f.__parent
    local depth = 0
    while p and depth < 8 do
        if p.__shown == false then return false end
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
CHECK(nav:find("Minor Health", 1, true) and not nav:find("Enchant Bracer - Minor Health", 1, true), "A6 recipe rows painted, slot prefix dropped under the slot header")
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
do
    -- Every Go in the briefing points the Commander Orders arrow at its place
    local before = #waypoints
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.__text == "Go" and f.__shown ~= false and Under(frame.detailPane, f) then
            f.__scripts.OnClick(f)
        end
    end
    local kulwia
    for i = before + 1, #waypoints do
        if waypoints[i].spec.key == "place:Kulwia@1442" then kulwia = waypoints[i] end
    end
    CHECK(kulwia and kulwia.map == 1442 and math.abs(kulwia.x - 0.454) < 0.001 and kulwia.spec.source == "Formulary"
        and kulwia.spec.setArrow == true and kulwia.spec.icon == "VENDOR",
        "B3 Go on a vendor: one owned Commander Orders waypoint, taking the arrow", kulwia and kulwia.spec.key)
end
CHECK(craftBtn.__parent.__shown == false, "B3 no craft button for an unknown recipe")
-- B3b (3.1) the Go is the suite's Commander.UI.GoButton: Shift-click shares
-- the place in chat, Ctrl-click copies its /way line, neither sends anything
do
    local go
    for _, f in ipairs(frames) do
        local o = rawget(f, "_fmOpts")
        if o and f.__shown ~= false and o.key == "place:Kulwia@1442" and Under(frame.detailPane, f) then go = f end
    end
    CHECK(go and rawget(go, "_goOpts") == rawget(go, "_fmOpts"), "B3b the vendor's Go is a Commander.UI.GoButton")
    if go then
        local before = #waypoints
        IsShiftKeyDown = function() return true end
        go.__scripts.OnClick(go)
        IsShiftKeyDown = function() return false end
        local sh = shares[#shares]
        CHECK(sh and sh.channel == "CHAT" and sh.spec.map == 1442 and sh.spec.title == "Kulwia", "B3b Shift-click shares Kulwia in chat")
        IsControlDown = true
        go.__scripts.OnClick(go)
        IsControlDown = false
        CHECK(copies[#copies] == "/way #1442 45.40 59.30 Kulwia", "B3b Ctrl-click copies the /way line", copies[#copies])
        CHECK(#waypoints == before, "B3b ...and neither sends a waypoint")
        IsShiftKeyDown = nil
        GameTooltip.__lines = {}
        go.__scripts.OnEnter(go)
        local tipText = table.concat(GameTooltip.__lines, " | ")
        CHECK(tipText:find("Go to: Kulwia", 1, true) and tipText:find("Points the Commander Orders arrow there.", 1, true)
            and tipText:find("Shift-click: share in chat", 1, true), "B3b its tooltip: where, what a press does, the gestures", tipText)
        -- B3c (2026-10-05 review) a greyed Go promises no press: 2.5.6
        -- delivers no OnClick to a disabled Button, so with Orders turned
        -- off the tooltip keeps the place and the red reason and drops the
        -- "Prints ..." line; without Orders a placed Go stays live, and its
        -- tooltip says the press prints the /way line
        local available = CommanderOrders.IsAvailable
        CommanderOrders.IsAvailable = function() return false, "disabled" end
        go:Refresh()
        GameTooltip.__lines = {}
        go.__scripts.OnEnter(go)
        tipText = table.concat(GameTooltip.__lines, " | ")
        CHECK(rawget(go, "_goReason") ~= nil and tipText:find("Go to: Kulwia", 1, true)
            and not tipText:find("Prints", 1, true) and not tipText:find("a press", 1, true),
            "B3c Orders turned off: the greyed Go promises no press", tipText)
        -- the Formulary's own line, whatever the GoButton chooses to show
        CHECK(rawget(go, "_fmOpts").tooltip(go) == nil, "B3c ...and the Go's own line is nil while Orders is off")
        CommanderOrders.IsAvailable = available
        local saved = CommanderOrders
        CommanderOrders = nil
        go:Refresh()
        GameTooltip.__lines = {}
        go.__scripts.OnEnter(go)
        tipText = table.concat(GameTooltip.__lines, " | ")
        CHECK(rawget(go, "_goReason") == nil
            and tipText:find("Prints the coordinates and a /way line to chat (Commander Orders is not loaded).", 1, true),
            "B3c without Orders the placed Go stays live and says it prints its /way line", tipText)
        CommanderOrders = saved
        go:Refresh()
        GameTooltip.__lines = {}
    end
end

CommanderFormulary_Select(27984)
Settle()
detail = TextUnder(frame.detailPane)
CHECK(detail:find("Drops from Moroes", 1, true) and detail:find("Karazhan", 1, true) and detail:find("5%", 1, true), "B4 Moroes at 5%", detail)
-- B4b (3.1, D18) a creature inside an instance carries the instance's map
-- id, and its Go is the instance's door through Orders' locator
do
    local moroes
    for npc, n in pairs(CommanderFormulary_Data.ENCHANTING.npcs) do
        if n.name == "Moroes" then moroes = n end
    end
    CHECK(moroes and moroes.instance == 532 and moroes.x == nil, "B4b the data names Moroes' instance: Karazhan, 532",
        moroes and tostring(moroes.instance))
    local go
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.__text == "Go" and f.__shown ~= false and Under(frame.detailPane, f) then go = f end
    end
    local o = go and rawget(go, "_fmOpts")
    CHECK(o and o.query and o.query.entrance and o.query.entrance.instance == 532 and o.key == "door:532"
        and o.title == "Moroes (Karazhan entrance)", "B4b the drop has a Go to Karazhan's door", o and o.key)
    if go then
        local before = #waypoints
        locatorAnswers["door:532"] = { map = 1430, x = 0.4659, y = 0.7411, title = "Karazhan" }
        go.__scripts.OnClick(go)
        local spec = waypoints[#waypoints] and waypoints[#waypoints].spec
        CHECK(#waypoints == before + 1 and spec.query.entrance.instance == 532 and spec.source == "Formulary"
            and spec.title == "Moroes (Karazhan entrance)" and spec.setArrow == true,
            "B4b ...one owned waypoint at the door, taking the arrow", spec and spec.title)
        locatorAnswers["door:532"] = nil
        -- B4d (2026-10-05 review) without Orders the door's Go is greyed,
        -- "Needs Commander Orders", and promises no print: a query has no
        -- place of its own to print
        local saved = CommanderOrders
        CommanderOrders = nil
        go:Refresh()
        GameTooltip.__lines = {}
        go.__scripts.OnEnter(go)
        local tip = table.concat(GameTooltip.__lines, " | ")
        CHECK(rawget(go, "_goReason") == "needsorders" and tip:find("Needs Commander Orders", 1, true)
            and not tip:find("Prints", 1, true), "B4d without Orders the door's Go is greyed and promises no print", tip)
        CHECK(rawget(go, "_fmOpts").tooltip(go) == nil, "B4d ...and the Go's own line is nil for a query without Orders")
        CommanderOrders = saved
        go:Refresh()
        GameTooltip.__lines = {}
    end
end

-- B4c (3.1) "any trainer will teach it now" goes to the nearest trainer
do
    local v = CommanderFormulary_View()
    local pick
    for spell, e in pairs(v.entries) do
        if not e.known and e.learnable == "trainer" and not e.rec.trainer.outland and (not pick or spell < pick) then pick = spell end
    end
    CHECK(pick ~= nil, "B4c (a recipe any trainer teaches now)")
    if pick then
        CommanderFormulary_Select(pick)
        Settle()
        CHECK(TextUnder(frame.detailPane):find("any trainer will teach it now", 1, true), "B4c (the line is there)")
        local go
        for _, f in ipairs(frames) do
            local o = rawget(f, "_fmOpts")
            if o and f.__shown ~= false and o.query and o.query.townsfolk and Under(frame.detailPane, f) then go = f end
        end
        local o = go and rawget(go, "_fmOpts")
        CHECK(o and o.query.townsfolk == "Enchanting Trainer" and o.title == "Nearest Enchanting trainer"
            and o.key == "trainer:ENCHANTING" and o.icon == "TRAINER", "B4c ...with a Go to the nearest Enchanting trainer", o and o.key)
        if go then
            local before = #waypoints
            locatorAnswers["Enchanting Trainer"] = { map = 1454, x = 0.53, y = 0.38, title = "Nearest Enchanting trainer" }
            go.__scripts.OnClick(go)
            local spec = waypoints[#waypoints] and waypoints[#waypoints].spec
            CHECK(#waypoints == before + 1 and spec.query.townsfolk == "Enchanting Trainer" and spec.setArrow == true,
                "B4c ...one waypoint, the arrow on it", spec and spec.key)
            locatorAnswers["Enchanting Trainer"] = nil
        end
    end
end

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

-- B7 stacked Go buttons never overlap: a single-line row is 12 + 3 high and
-- its Go 18 (review 2026-10-05: each sat 3 px inside the one above, so those
-- clicks went to the next row's place). Minor Mana has the longest column
-- of vendors and droppers, Minor Agility two vendors and the droppers, Major
-- Armor the Outland trainers.
local function GoColumn(spell)
    CommanderFormulary_Select(spell)
    Settle()
    local stack = {}
    for _, f in ipairs(frames) do
        local p = f.__point
        if rawget(f, "_fmOpts") and f.__shown ~= false and p and type(p[5]) == "number" and Under(frame.detailPane, f) then
            stack[#stack + 1] = { top = p[5], h = f.__h or 0 }
        end
    end
    table.sort(stack, function(a, b) return a.top > b.top end)
    local pairsOver, worst = 0, 0
    for i = 2, #stack do
        local over = stack[i].top - (stack[i - 1].top - stack[i - 1].h)
        if over > 0 then
            pairsOver = pairsOver + 1
            if over > worst then worst = over end
        end
    end
    return #stack, pairsOver, worst, stack[1] and stack[1].h
end
for _, case in ipairs({ { 7443, "Minor Mana", 10 }, { 13419, "Minor Agility", 3 }, { 27961, "Major Armor", 2 } }) do
    local n, over, worst, h = GoColumn(case[1])
    CHECK(n >= case[3], "B7 " .. case[2] .. ": a column of Go buttons", n)
    CHECK(over == 0, "B7 " .. case[2] .. ": ...none overlapping the one above", over .. " pairs, " .. worst .. " px")
    CHECK(h == 18, "B7 " .. case[2] .. ": (each Go is 18 high)", h)
end

-- ===========================================================================
-- C. Filters, search, sort, collapse
-- ===========================================================================

-- Rows are pooled and hidden, and the mock does not propagate a parent's
-- Hide to its font strings, so count the ROWS that are shown
local function NavRecipeCount()
    local n = 0
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.__shown ~= false and f.spell and Under(frame.navPane, f) then n = n + 1 end
    end
    return n
end
frame.filters.KNOWN.__scripts.OnClick(frame.filters.KNOWN)
Settle()
CHECK(CommanderFormularyDB.Filter == "KNOWN", "C1 filter set")
CHECK(NavRecipeCount() == 6, "C1 known filter shows the six known recipes", NavRecipeCount())
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
    CHECK(#GameTooltip.__lines == 0, "C6 not a formula, not gear: nothing added")
    -- Disenchant advice on gear: a green ilvl 60 chest (DE ~ 7g+) vs vendor 30s vs AH 60s
    GameTooltip.__lines = {}
    GameTooltip._cfmItem = nil
    GameTooltip.__itemLink = "|Hitem:2140:0|h[Bracers]|h"
    hooked(GameTooltip)
    CHECK(GameTooltip.__lines[1] and GameTooltip.__lines[1]:find("Disenchants into") and GameTooltip.__lines[1]:find("Illusion Dust"), "C6 DE materials line", GameTooltip.__lines[1])
    CHECK(GameTooltip.__lines[2] and GameTooltip.__lines[2]:find("disenchant it") and GameTooltip.__lines[2]:find("vendor 30s") and GameTooltip.__lines[2]:find("AH 60s"), "C6 DE verdict line", GameTooltip.__lines[2])
    CHECK(not GameTooltip.__lines[2]:find("→", 1, true), "C6 no arrow glyph")
    -- a soulbound copy: the auction house is off the table, and the line says so
    ITEM_SOULBOUND = "Soulbound"
    GameTooltip.GetName = function() return "GameTooltip" end
    GameTooltip.NumLines = function() return 2 end
    _G.GameTooltipTextLeft1 = { GetText = function() return "Bracers" end }
    _G.GameTooltipTextLeft2 = { GetText = function() return "Soulbound" end }
    GameTooltip.__lines = {}
    GameTooltip._cfmItem = nil
    -- a cheap green whose AH price would otherwise win: DE ~7g vs AH 60s is still DE; use the blue where AH 2g < DE 3g... make AH the winner
    PRICES[2140] = 900000
    hooked(GameTooltip)
    CHECK(GameTooltip.__lines[2]:find("soulbound, no AH") and not GameTooltip.__lines[2]:find("auction house"), "C6 soulbound: no auction option", GameTooltip.__lines[2])
    PRICES[2140] = 6000
    GameTooltip.NumLines = function() return 0 end
    -- a blue at 115: Large Prismatic Shard, 3g vs AH 2g -> disenchant
    GameTooltip.__lines = {}
    GameTooltip._cfmItem = nil
    GameTooltip.__itemLink = "|Hitem:2141:0|h[Cloak]|h"
    hooked(GameTooltip)
    CHECK(GameTooltip.__lines[1]:find("Large Prismatic Shard") and GameTooltip.__lines[2]:find("disenchant it"), "C6 blue -> shard", GameTooltip.__lines[2])
    -- a white item: nothing
    GameTooltip.__lines = {}
    GameTooltip._cfmItem = nil
    GameTooltip.__itemLink = "|Hitem:2144:0|h[Shirt]|h"
    hooked(GameTooltip)
    CHECK(#GameTooltip.__lines == 0, "C6 white item: nothing")
    -- option off
    CommanderFormularyDB.DisenchantAdvice = false
    GameTooltip.__lines = {}
    GameTooltip._cfmItem = nil
    GameTooltip.__itemLink = "|Hitem:2140:0|h[Bracers]|h"
    hooked(GameTooltip)
    CHECK(#GameTooltip.__lines == 0, "C6 advice off: nothing")
    CommanderFormularyDB.DisenchantAdvice = true
end

-- C7 gold in the briefing, and the Profit filter
me.known[14807] = true
CommanderFormulary_Select(14807)
Settle()
detail = TextUnder(frame.detailPane)
CHECK(detail:find("GOLD", 1, true) and detail:find("A cast costs 15s 38c", 1, true), "C7 wand cast cost (vendor wood + essence)", detail)
CHECK(detail:find("sells for 40s", 1, true) and detail:find("Profit of 24s 62c a cast", 1, true), "C7 wand profit", detail)
CommanderFormulary_Select(13419)
Settle()
detail = TextUnder(frame.detailPane)
CHECK(detail:find("To learn and try it: the formula 8s", 1, true), "C7 cost to learn on an unknown recipe", detail)
-- the cast cost sits beside the name with coin icons, rounded to the silver
local wandRow
for _, f in ipairs(frames) do
    if f.__kind == "Button" and f.__shown ~= false and f.name and f.name.__text and f.name.__text:find("Greater Magic Wand", 1, true) and Under(frame.navPane, f) then wandRow = f end
end
CHECK(wandRow and wandRow.cost.__text:find("15|TInterface\\MoneyFrame\\UI-SilverIcon", 1, true), "C7 cost column as coins (15s 38c -> 15 silver)", wandRow and wandRow.cost.__text)
CHECK(wandRow and not wandRow.cost.__text:find("38", 1, true), "C7 copper rounded away")
CHECK(wandRow and wandRow.name.__text == "Greater Magic Wand", "C7 the name column is only the name", wandRow and wandRow.name.__text)
frame.filters.PROFITABLE.__scripts.OnClick(frame.filters.PROFITABLE)
Settle()
CHECK(NavRecipeCount() == 1 and TextUnder(frame.navPane):find("Greater Magic Wand", 1, true), "C7 profit filter shows only the wand", TextUnder(frame.navPane))
frame.filters.ALL.__scripts.OnClick(frame.filters.ALL)
Settle()

-- C8 the Trips view: zones with vendors, right-click routes a zone
frame.filters.TRIPS.__scripts.OnClick(frame.filters.TRIPS)
Settle()
nav = TextUnder(frame.navPane)
CHECK(nav:find("Moonglade", 1, true) and nav:find("Lorelae Wintersong", 1, true), "C8 Moonglade trip listed with its vendor", nav)
CHECK(nav:find("Stonetalon Mountains", 1, true) and not nav:find("Ashenvale", 1, true), "C8 Horde sees Sun Rock Retreat, not Astranaar")
CHECK(TextUnder(frame.toolbar):find("across", 1, true) and TextUnder(frame.toolbar):find("at your skill", 1, true), "C8 header sums the trips", TextUnder(frame.toolbar))
local zoneRow
for _, f in ipairs(frames) do
    if f.__kind == "Button" and f.__shown ~= false and f.name and f.name.__text and f.name.__text:find("Moonglade", 1, true) and Under(frame.navPane, f) then zoneRow = f end
end
CHECK(zoneRow ~= nil, "C8 zone header row")
zoneRow.__scripts.OnClick(zoneRow, "RightButton")
CHECK(waypoints[#waypoints] and waypoints[#waypoints].map == 1450, "C8 right-click on a one-vendor zone sets a Moonglade waypoint", waypoints[#waypoints] and waypoints[#waypoints].map)
CHECK(waypoints[#waypoints] and waypoints[#waypoints].spec.key == "place:Lorelae Wintersong@1450"
    and waypoints[#waypoints].spec.source == "Formulary"
    and waypoints[#waypoints].spec.title:find("^Lorelae Wintersong: ") ~= nil,
    "C8 ...owned by the vendor and titled with what to buy there", waypoints[#waypoints] and waypoints[#waypoints].spec.title)
do
    -- Route All Trips: on the Trips view only, every formula bought once
    CHECK(frame.routeAllButton.__shown ~= false, "C8 Route All Trips is offered on the Trips view")
    local before = #routes
    frame.routeAllButton.__scripts.OnClick(frame.routeAllButton)
    local route = routes[#routes]
    CHECK(#routes == before + 1 and route.source == "Formulary" and route.key == "trips:ENCHANTING"
        and route.mode == "NEAREST" and route.start == true, "C8 one owned NEAREST route for every trip",
        route and route.key)
    local stopsCovered = 0
    for _, st in ipairs(route and route.stops or {}) do
        local more = tonumber(st.title:match("%(%+(%d+)%)$")) or 0
        stopsCovered = stopsCovered + 1 + more
        CHECK(type(st.map) == "number" and st.x >= 0 and st.x <= 1 and st.icon == "VENDOR",
            "C8 a stop is a uiMap position in 0..1: " .. st.title)
    end
    -- The oracle, read off the Trips list itself: every formula it names
    -- under a zone whose vendor has a place on the map (Lokhtos in Blackrock
    -- Depths and the wizard in Old Hillsbrad have none: no arrow goes there)
    local placedByName = {}
    for _, rec in pairs(CommanderFormulary_Data.ENCHANTING.npcs) do
        if rec.map then placedByName[rec.name] = true end
    end
    local routable, listed, zonePlaced = {}, 0, false
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.__shown ~= false and Under(frame.navPane, f) and f.name and f.name.__text then
            local text = f.name.__text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            local vendor = text:match("^.-  (.+)$")
            if vendor and (not f.cost or (f.cost.__text or "") == "") then
                zonePlaced = placedByName[vendor] == true
            elseif zonePlaced and not routable[text] then
                routable[text] = true
                listed = listed + 1
            end
        end
    end
    CHECK(listed > 0 and stopsCovered == listed,
        "C8 the route buys every listed formula a vendor on the map sells, each exactly once",
        stopsCovered .. " vs " .. listed)
    -- A zone with several vendors is routed, not just its first vendor
    local shatt
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.__shown ~= false and Under(frame.navPane, f) and f.name and f.name.__text
            and f.name.__text:find("^Shattrath City  ") then shatt = f end
    end
    CHECK(shatt ~= nil, "C8 the Shattrath trip is listed")
    if shatt then
        local n = #routes
        shatt.__scripts.OnClick(shatt, "RightButton")
        local zr = routes[#routes]
        CHECK(#routes == n + 1 and zr.key == "trip:ENCHANTING:Shattrath City" and zr.mode == "NEAREST" and #zr.stops >= 2,
            "C8 right-click on a zone of several vendors routes them all, nearest first", zr and #zr.stops)
        local inZone = true
        for _, st in ipairs(zr and zr.stops or {}) do if st.map ~= 1955 then inZone = false end end
        CHECK(inZone, "C8 ...and only that zone's vendors")
        before = #routes
    end
    printLog = {}
    local saved = CommanderOrders
    CommanderOrders = nil
    zoneRow.__scripts.OnClick(zoneRow, "RightButton")
    CHECK(printLog[#printLog] and printLog[#printLog]:find("/way #1450 48.20 40.10 Lorelae Wintersong: ", 1, true),
        "C8 without Commander Orders the right-click prints the place with its /way line", printLog[#printLog])
    frame.routeAllButton.__scripts.OnClick(frame.routeAllButton)
    CHECK(#routes == before and table.concat(printLog, "\n"):find("/way #1450", 1, true),
        "C8 ...and Route All Trips prints the stops' /way lines, sending nothing")
    CommanderOrders = saved
end
zoneRow.__scripts.OnClick(zoneRow, "LeftButton")
Settle()
CHECK(CommanderFormularyChar.collapsed["zone:Moonglade"] == true, "C8 left-click folds the zone")
zoneRow.__scripts.OnClick(zoneRow, "LeftButton")
Settle()
frame.filters.ALL.__scripts.OnClick(frame.filters.ALL)
Settle()
CHECK(frame.routeAllButton.__shown == false, "C8 Route All Trips leaves with the Trips view")

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
CHECK(CommanderFormularyChar.known[13419] == true and CommanderFormularyChar.scanned.ENCHANTING, "D1 craft list read into memory")
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

-- F the Refresh Prices button: only at the auction house with Auctionator
-- able to search, every priced item on a click, one recipe's on shift-click,
-- and a rebuild when Auctionator's search ends
CHECK(frame.refreshButton.__shown == false, "F1 no refresh button away from the auction house")
local searched, busListeners = nil, {}
Auctionator.API.v1.MultiSearchExact = function(caller, names) searched = names end
Auctionator.EventBus = { Register = function(self, listener, names) busListeners[#busListeners + 1] = { listener = listener, names = names } end }
Auctionator.Shopping = { Tab = { Events = { SearchEnd = "shopping tab search end" } } }
Auctionator.FullScan = { Events = { ScanComplete = "get_all_scan_complete" } }
AuctionFrame = { IsShown = function() return true end }
Fire("AUCTION_HOUSE_SHOW")
Settle()
CHECK(frame.refreshButton.__shown == true, "F1 refresh button at the auction house")
CHECK(#busListeners == 1 and #busListeners[1].names == 2, "F1 listening for the search end and the full scan", #busListeners)
printLog = {}
frame.refreshButton.__scripts.OnClick(frame.refreshButton)
CHECK(searched and #searched == 211, "F2 every priced item searched (110 reagents, 30 disenchant results, 82 formulas, 28 goods)", searched and #searched)
local seen = {}
for _, n in ipairs(searched or {}) do seen[n] = true end
CHECK(seen["Soul Dust"] and seen["Greater Magic Wand"] and seen["Formula: Enchant Chest - Minor Mana"] and seen["Arcane Dust"], "F2 reagents, goods, formulas and disenchant results by exact name")
CHECK(printLog[1] and printLog[1]:find("searching 211 items", 1, true), "F2 announced", printLog[1])
searched = nil
IsShiftKeyDown = function() return true end
frame.refreshButton.__scripts.OnClick(frame.refreshButton)
IsShiftKeyDown = function() return false end
table.sort(searched or {})
CHECK(searched and table.concat(searched, ", ") == "Soul Dust", "F3 shift-click searches the selected recipe's items only", searched and table.concat(searched, ", "))
searched = nil
CommanderFormulary_RefreshPrices("Greater Magic Wand")
table.sort(searched or {})
CHECK(searched and table.concat(searched, ", ") == "Greater Magic Essence, Greater Magic Wand, Simple Wood", "F3 /cfm refresh <recipe>", searched and table.concat(searched, ", "))
printLog = {}
busListeners[1].listener:ReceiveEvent("shopping tab search end", {})
Settle()
CHECK(printLog[1] and printLog[1]:find("prices refreshed", 1, true), "F4 rebuilt and announced when the search ends", printLog[1])
AuctionFrame = { IsShown = function() return false end }
Fire("AUCTION_HOUSE_CLOSED")
Settle()
CHECK(frame.refreshButton.__shown == false, "F5 button gone when the auction house closes")
printLog = {}
CommanderFormulary_RefreshPrices()
CHECK(printLog[1] and printLog[1]:find("open the auction house", 1, true), "F5 refresh away from the auction house says why", printLog[1])

-- ===========================================================================
-- G. First Aid: the second profession
-- ===========================================================================

-- The readout switches; the selection is kept per profession
CommanderFormulary_Show()
Settle()
CommanderFormulary_Select(13501)
Settle()
me.faRank, me.faMax = 200, 225
CommanderFormulary_Profession("firstaid")
Settle()
CHECK(CommanderFormularyChar.profession == "FIRSTAID", "G1 /cfm firstaid switches the profession", CommanderFormularyChar.profession)
CHECK(frame.TitleText and frame.TitleText.__text == "Formulary — First Aid", "G1 the title names it", frame.TitleText and frame.TitleText.__text)
view = CommanderFormulary_View()
CHECK(view and view.rank == 200 and view.maxRank == 225 and view.total == 15, "G1 the view is First Aid's", view and (view.rank .. " " .. view.total))
nav = TextUnder(frame.navPane)
CHECK(nav:find("Bandages", 1, true) and nav:find("Anti-Venom", 1, true) and nav:find("Heavy Silk Bandage", 1, true), "G2 First Aid categories and rows", nav:sub(1, 120))
CHECK(not nav:find("Bracer", 1, true), "G2 no Enchanting rows", nav)
header = TextUnder(frame.toolbar)
CHECK(header:find("First Aid", 1, true) and header:find("200 / 225", 1, true), "G2 the readout is First Aid's", header)
detail = TextUnder(frame.detailPane)
CHECK(detail:find("Pick a recipe", 1, true), "G2 the Enchanting selection does not carry over")
-- the readout's tooltip lists both professions and how the next rank comes
frame.rankButton.__scripts.OnEnter(frame.rankButton)
local tip = table.concat(GameTooltip.__lines, "\n")
CHECK(tip:find("Enchanting 146 / 150", 1, true) and tip:find("First Aid 200 / 225", 1, true), "G3 both professions in the tooltip", tip)
CHECK(tip:find("Triage", 1, true) and tip:find("Gregory Victor", 1, true) and not tip:find("VanHowzen", 1, true), "G3 Artisan First Aid is the Horde doctor's quest", tip)
CHECK(tip:find("Expert Enchanting is taught by any Enchanting trainers", 1, true), "G3 Expert Enchanting from a trainer", tip)
-- G3b (3.1) Ctrl+Right-click on the readout goes where the next rank comes
-- from (Orders' list-row gesture, its hint in the tooltip): the quest giver
CHECK(tip:find("Ctrl+Right-click: Go to Doctor Gregory Victor", 1, true), "G3b the readout's tooltip offers the next rank's Go", tip)
do
    local before = #waypoints
    frame.rankButton.__scripts.OnClick(frame.rankButton, "RightButton")
    CHECK(#waypoints == before and CommanderFormularyChar.profession == "FIRSTAID", "G3b a plain right-click does nothing")
    IsControlDown = true
    frame.rankButton.__scripts.OnClick(frame.rankButton, "RightButton")
    IsControlDown = false
    local spec = waypoints[#waypoints] and waypoints[#waypoints].spec
    CHECK(#waypoints == before + 1 and spec.map == 1417 and math.abs(spec.x - 0.734) < 1e-9 and spec.title == "Doctor Gregory Victor"
        and spec.key == "rank:FIRSTAID" and spec.icon == "QUEST" and spec.source == "Formulary",
        "G3b Ctrl+Right-click: the Triage giver, the arrow on him", spec and (tostring(spec.map) .. " " .. tostring(spec.title)))
    CHECK(CommanderFormularyChar.profession == "FIRSTAID", "G3b ...and the profession did not switch")
end
GameTooltip.__lines = {}
-- the Read Recipes button now casts First Aid
local openBtn = _G.CommanderFormularyOpen
CHECK(openBtn and openBtn.__attr and openBtn.__attr.spell == "First Aid", "G3 the open button casts First Aid", openBtn and openBtn.__attr and openBtn.__attr.spell)
-- a known bandage: the craft macro is a bare /cast, no gear line
CommanderFormularyChar.known[7929] = true
CommanderFormulary_Select(7929)
Settle()
CHECK(craftBtn.__attr.macrotext == "/cast Heavy Silk Bandage", "G4 bandage macro is /cast alone", craftBtn.__attr.macrotext)
detail = TextUnder(frame.detailPane)
CHECK(detail:find("Silk Cloth", 1, true) and detail:find("Manual: Heavy Silk Bandage", 1, true), "G4 reagents and the manual in the briefing", detail:sub(1, 200))
-- the trade skill window opening switches to First Aid, is read, and is put away
CommanderFormulary_Profession("enchanting")
Settle()
CHECK(CommanderFormularyChar.profession == "ENCHANTING", "G5 back to Enchanting")
frame:Hide()
trade.shown = true
trade.list = { { name = "Bandages", header = true }, { name = "Mageweave Bandage", spell = 10840 }, { name = "Runecloth Bandage", spell = 18629 } }
Fire("TRADE_SKILL_SHOW")
Settle()
CHECK(CommanderFormularyChar.profession == "FIRSTAID", "G5 the trade skill window brings First Aid on screen")
CHECK(CommanderFormularyChar.known[10840] == true and CommanderFormularyChar.scanned.FIRSTAID, "G5 its list read into memory")
CHECK(TradeSkillFrame.__hiddenViaPanel == true and frame.__shown == true, "G5 stock trade skill window put away, Formulary in its place")
Fire("TRADE_SKILL_CLOSE")
Settle()
-- and the craft window brings Enchanting back
craft.shown = true
Fire("CRAFT_SHOW")
Settle()
CHECK(CommanderFormularyChar.profession == "ENCHANTING", "G5 the craft window brings Enchanting back")
Fire("CRAFT_CLOSE")
Settle()
-- a trade skill window on a profession the Formulary does not carry is left alone
trade.skill = "Cooking"
frame:Hide()
TradeSkillFrame.__hiddenViaPanel = nil
Fire("TRADE_SKILL_SHOW")
Settle()
CHECK(frame.__shown == false and TradeSkillFrame.__hiddenViaPanel == nil, "G6 Cooking is left alone")
Fire("TRADE_SKILL_CLOSE")
trade.skill = "First Aid"
-- a First Aid manual's tooltip verdict is judged against First Aid's skill
-- while Enchanting is on screen
CommanderFormulary_Profession("enchanting")
Settle()
GameTooltip.__lines = {}
GameTooltip.GetItem = function() return "Manual: Mageweave Bandage", "|Hitem:16113|h[Manual: Mageweave Bandage]|h" end
GameTooltip._cfmItem = nil
GameTooltip.__scripts.OnTooltipSetItem(GameTooltip)
tip = table.concat(GameTooltip.__lines, "\n")
CHECK(tip:find("you already know this recipe", 1, true), "G7 a known manual (First Aid at 200, Mageweave read from the window)", tip)
GameTooltip.__lines = {}
GameTooltip.GetItem = function() return "Manual: Netherweave Bandage", "|Hitem:21992|h[Manual: Netherweave Bandage]|h" end
GameTooltip._cfmItem = nil
GameTooltip.__scripts.OnTooltipSetItem(GameTooltip)
tip = table.concat(GameTooltip.__lines, "\n")
CHECK(tip:find("learn this at 330 skill (you are 200)", 1, true), "G7 a manual out of reach, against First Aid's 200 not Enchanting's 146", tip)
GameTooltip.GetItem = nil

-- Restore defaults leaves the character's memory alone
CommanderFormularyChar.known[13501] = true
Commander.UI.ResetToDefaults(CommanderFormularyDB, CommanderFormulary_Defaults)
CHECK(CommanderFormularyChar.known[13501] == true and CommanderFormularyDB.Filter == "ALL", "E4 defaults leave memory alone")

CHECK(#harnessFailedErrors == 0, "Z no errors were swallowed", harnessFailedErrors[1])
io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
