-- Commander Vault harness (luajit).
--
-- Loads the REAL shared framework (CommanderSettingsUI.lua, CommanderEvents.lua)
-- and all six Commander_Vault files under a permissive WoW mock, then drives a
-- bank visit end to end: the model, the search language, the advisor's ten
-- rules, the two-phase sort against a genuinely mutable world, and the window
-- that draws it.
--
--   luajit vault_harness.lua
--
-- Mock notes worth keeping:
--   * The container world is MUTABLE and the cursor is modelled properly
--     (pick up / place / merge / swap), because the sort is the one part of
--     this module that writes to the player's items and a sort test against an
--     immutable world proves nothing.
--   * C_Timer.NewTicker hands the ticker's callback back to the harness rather
--     than firing it, so the sort can be stepped one move at a time and
--     watched converge.
--   * The mock character is a MAGE: the "gear you cannot wear" rule is only
--     reachable for a class whose armour type something can exceed.

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"

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

local NOW = 1700000000
function time() return NOW end
function GetTime() return 1000 end
function GetBuildInfo() return "2.5.6", "68502", "Jul 7 2026", 20506 end

local printLog = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    printLog[#printLog + 1] = table.concat(parts, " ")
end
local function LastPrint() return printLog[#printLog] end

local caughtErrors = {}
local errorHandler = function(err) caughtErrors[#caughtErrors + 1] = tostring(err) end
function geterrorhandler() return errorHandler end
function seterrorhandler(fn) errorHandler = fn end

local eventRegistry = {}

local NUMERIC_GETTERS = {
    GetScale = 1, GetEffectiveScale = 1,
    GetFrameLevel = 2, GetLeft = 0, GetBottom = 0, GetTop = 0, GetRight = 0,
    GetVerticalScroll = 0, GetVerticalScrollRange = 0, GetStringWidth = 10,
    GetID = 1, GetNumPoints = 1, NumLines = 0,
}

local METHOD_PREFIXES = {
    "Set", "Enable", "Disable", "Register", "Unregister", "Clear",
    "Start", "Stop", "Raise", "Lower", "Lock", "Play", "Add", "Highlight",
}

local function IsAutoMethod(key)
    for _, prefix in ipairs(METHOD_PREFIXES) do
        if key:sub(1, #prefix) == prefix then return true end
    end
    return false
end

local NewWidget

local WidgetMT = {}
WidgetMT.__index = function(self, key)
    if type(key) ~= "string" then return nil end
    if NUMERIC_GETTERS[key] ~= nil then
        local v = NUMERIC_GETTERS[key]
        local fn = function() return v end
        rawset(self, key, fn); return fn
    end
    if key == "CreateTexture" then
        local fn = function(s) local t = NewWidget("Texture"); t.__parent = s; return t end
        rawset(self, key, fn); return fn
    end
    if key == "CreateFontString" then
        local fn = function(s) local t = NewWidget("FontString"); t.__parent = s; return t end
        rawset(self, key, fn); return fn
    end
    if key == "SetScript" then
        local fn = function(s, name, handler) s.__scripts[name] = handler end
        rawset(self, key, fn); return fn
    end
    if key == "HookScript" then
        local fn = function(s, name, handler)
            local prev = s.__scripts[name]
            if prev then
                s.__scripts[name] = function(...) prev(...) handler(...) end
            else
                s.__scripts[name] = handler
            end
        end
        rawset(self, key, fn); return fn
    end
    if key == "GetScript" then
        local fn = function(s, name) return s.__scripts[name] end
        rawset(self, key, fn); return fn
    end
    if key == "RegisterEvent" then
        local fn = function(s, event)
            eventRegistry[event] = eventRegistry[event] or {}
            table.insert(eventRegistry[event], s)
        end
        rawset(self, key, fn); return fn
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
        rawset(self, key, fn); return fn
    end
    if key == "Show" then
        local fn = function(s)
            s.__shown = true
            if s.__scripts.OnShow then s.__scripts.OnShow(s) end
        end
        rawset(self, key, fn); return fn
    end
    if key == "Hide" then
        local fn = function(s)
            s.__shown = false
            if s.__scripts.OnHide then s.__scripts.OnHide(s) end
        end
        rawset(self, key, fn); return fn
    end
    if key == "SetShown" then
        local fn = function(s, v) if v then s:Show() else s:Hide() end end
        rawset(self, key, fn); return fn
    end
    if key == "IsShown" or key == "IsVisible" then
        local fn = function(s) return s.__shown end
        rawset(self, key, fn); return fn
    end
    if key == "SetVertexColor" then
        local fn = function(s, r, g, b, a) s.__color = { r, g, b, a or 1 } end
        rawset(self, key, fn); return fn
    end
    if key == "SetTexture" then
        local fn = function(s, tex) s.__texture = tex end
        rawset(self, key, fn); return fn
    end
    if key == "SetPoint" then
        local fn = function(s, point, rel, relPoint, x, y)
            s.__points = s.__points or {}
            s.__points[point] = { rel = rel, relPoint = relPoint, x = x or 0, y = y or 0 }
        end
        rawset(self, key, fn); return fn
    end
    if key == "ClearAllPoints" then
        local fn = function(s) s.__points = {} end
        rawset(self, key, fn); return fn
    end
    if key == "SetWidth" then
        local fn = function(s, w) s.__w = w end
        rawset(self, key, fn); return fn
    end
    -- A widget that forgets the size it was just given makes everything
    -- derived from a size (the grid's column count, for one) untestable
    if key == "GetWidth" then
        local fn = function(s) return s.__w or 0 end
        rawset(self, key, fn); return fn
    end
    if key == "GetHeight" then
        local fn = function(s) return s.__h or 0 end
        rawset(self, key, fn); return fn
    end
    if key == "SetHeight" then
        local fn = function(s, h) s.__h = h end
        rawset(self, key, fn); return fn
    end
    if key == "SetSize" then
        local fn = function(s, w, h) s.__w, s.__h = w, h end
        rawset(self, key, fn); return fn
    end
    if key == "SetText" then
        local fn = function(s, text) s.__text = text end
        rawset(self, key, fn); return fn
    end
    if key == "GetText" then
        local fn = function(s) return s.__text end
        rawset(self, key, fn); return fn
    end
    if key == "SetChecked" then
        local fn = function(s, v) s.__checked = v and true or false end
        rawset(self, key, fn); return fn
    end
    if key == "GetChecked" then
        local fn = function(s) return s.__checked end
        rawset(self, key, fn); return fn
    end
    if key == "GetPoint" then
        local fn = function() return "CENTER", nil, "CENTER", 0, 0 end
        rawset(self, key, fn); return fn
    end
    if key == "GetThumbTexture" then
        local fn = function() return NewWidget("Texture") end
        rawset(self, key, fn); return fn
    end
    if key == "GetName" then
        local fn = function(s) return s.__name end
        rawset(self, key, fn); return fn
    end
    if key == "GetParent" then
        local fn = function(s) return s.__parent end
        rawset(self, key, fn); return fn
    end
    if key == "GetAlpha" then
        local fn = function(s) return s.__alpha or 1 end
        rawset(self, key, fn); return fn
    end
    if key == "SetAlpha" then
        local fn = function(s, a) s.__alpha = a end
        rawset(self, key, fn); return fn
    end
    if key == "GetFont" then
        local fn = function() return "Fonts\\FRIZQT__.TTF", 12, "" end
        rawset(self, key, fn); return fn
    end
    if key:sub(1, 2) == "Is" or key:sub(1, 3) == "Get" or key:sub(1, 3) == "Can"
        or key:sub(1, 4) == "Hook" then
        local fn = function() return nil end
        rawset(self, key, fn); return fn
    end
    if IsAutoMethod(key) then
        local fn = function() end
        rawset(self, key, fn); return fn
    end
    return nil
end

NewWidget = function(kind, name)
    return setmetatable({
        __kind = kind, __name = name, __scripts = {}, __shown = true,
    }, WidgetMT)
end

function CreateFrame(frameType, name, parent, template)
    local f = NewWidget(frameType, name)
    f.__template = template
    f.__parent = parent
    if frameType == "CheckButton" or (template and template:find("CheckButton")) then
        f.Text = NewWidget("FontString")
    end
    if template and template:find("BasicFrameTemplate") then
        f.TitleText = NewWidget("FontString")
        f.CloseButton = NewWidget("Button")
        f.NineSlice = NewWidget("Frame")
        f.Bg = NewWidget("Texture")
        f.TitleBg = NewWidget("Texture")
        f.Inset = NewWidget("Frame")
    end
    if name then _G[name] = f end
    return f
end

UIParent = NewWidget("Frame", "UIParent")
WorldFrame = NewWidget("Frame", "WorldFrame")
GameTooltip = NewWidget("GameTooltip", "GameTooltip")
ItemRefTooltip = NewWidget("GameTooltip", "ItemRefTooltip")
-- Which tooltip sources this fake client has quietly broken
local brokenSources = {}
-- Forward-declared because the recording tooltip's Set* closures below are
-- written BEFORE the fixture world is: captured as globals they would all be
-- nil, and every tooltip would silently fail for the wrong reason
-- Fire joins them: the guild bank mock dispatches events, and it is written
-- above the dispatcher. The harness leaks no globals of its own either — the
-- footprint sweep at the end would flag one.
local ITEMS, world, sizes, cursor, Link, Fire
-- A tooltip that remembers what was written on it, so the counts layer can be
-- read back rather than merely called
local function MakeRecordingTooltip(tooltip)
    rawset(tooltip, "__lines", {})
    rawset(tooltip, "AddLine", function(self, text)
        self.__lines[#self.__lines + 1] = tostring(text)
    end)
    rawset(tooltip, "AddDoubleLine", function(self, left, right)
        self.__lines[#self.__lines + 1] = tostring(left) .. "\t" .. tostring(right)
    end)
    rawset(tooltip, "GetItem", function(self) return self.__itemName, self.__itemLink end)
    rawset(tooltip, "SetItem", function(self, name, link)
        self.__itemName, self.__itemLink = name, link
        self.__lines = {}
    end)
    rawset(tooltip, "TooltipText", function(self) return table.concat(self.__lines, "\n") end)
    rawset(tooltip, "ClearLines", function(self) self.__lines = {} end)
    -- SetOwner starts a FRESH tooltip: it drops the text AND the item. Getting
    -- this wrong in the mock would hide the exact hazard the addon guards
    -- against — a failed fill answering GetItem with the previous hover's item.
    rawset(tooltip, "SetOwner", function(self)
        self.__lines = {}
        self.__itemName, self.__itemLink = nil, nil
    end)
    rawset(tooltip, "SetText", function(self, text)
        self.__text = text
        self.__lines[#self.__lines + 1] = tostring(text)
    end)
    rawset(tooltip, "NumLines", function(self) return #self.__lines end)
    -- The Set* family, modelled as the client behaves: each fills the tooltip
    -- and fires OnTooltipSetItem, which is the hook the global counts layer
    -- rides on. `brokenSources` makes a chosen one fail QUIETLY — filling
    -- nothing and raising nothing — which is exactly the client behaviour that
    -- produced empty "weird" tooltips, and the reason the module judges each
    -- attempt by NumLines rather than by pcall.
    local function Fill(self, link, name)
        if not name then return end
        self.__itemName, self.__itemLink = name, link
        self.__lines[#self.__lines + 1] = name
        local handler = self.__scripts and self.__scripts.OnTooltipSetItem
        if handler then handler(self) end
    end
    rawset(tooltip, "SetBagItem", function(self, bag, slot)
        local entry = world[bag] and world[bag][slot]
        if not entry then return end
        if brokenSources.bag then
            -- The behaviour actually observed on this client for bank
            -- containers: the call FIRES OnTooltipSetItem — so every other
            -- addon hooked there appends its lines — while never filling the
            -- item. That is what made a line count look like success.
            local handler = self.__scripts and self.__scripts.OnTooltipSetItem
            if handler then handler(self) end
            return
        end
        Fill(self, Link(entry.id), ITEMS[entry.id].name)
    end)
    rawset(tooltip, "SetHyperlink", function(self, link)
        if brokenSources.link then return end
        local id = tonumber(tostring(link):match("item:(%d+)") or "")
        if not id or not ITEMS[id] then return end
        Fill(self, link, ITEMS[id].name)
    end)
    rawset(tooltip, "SetItemByID", function(self, id)
        if brokenSources.byID then return end
        if not ITEMS[id] then return end
        Fill(self, Link(id), ITEMS[id].name)
    end)
    return tooltip
end
MakeRecordingTooltip(GameTooltip)
MakeRecordingTooltip(ItemRefTooltip)
BankFrame = NewWidget("Frame", "BankFrame")

tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack

GameFontNormal = NewWidget("Font")
GameFontNormalSmall = NewWidget("Font")
GameFontNormalLarge = NewWidget("Font")
GameFontHighlight = NewWidget("Font")
GameFontHighlightSmall = NewWidget("Font")
GameFontDisableSmall = NewWidget("Font")
NumberFontNormal = NewWidget("Font")
NumberFontNormalSmall = NewWidget("Font")

SOUNDKIT = {}
function PlaySound() end
BACKDROP_SLIDER_8_8 = {}
UISpecialFrames = {}
SlashCmdList = {}
CANCEL, YES, NO = "Cancel", "Yes", "No"
ITEM_SPELL_KNOWN = "Already known"

local categories = {}
Settings = {
    RegisterCanvasLayoutCategory = function(panel)
        local cat = { __panel = panel, GetID = function() return #categories + 1 end }
        categories[#categories + 1] = cat
        return cat
    end,
    RegisterCanvasLayoutSubcategory = function(parent, panel)
        local cat = { __panel = panel, GetID = function() return #categories + 1 end }
        categories[#categories + 1] = cat
        return cat
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
}

C_AddOns = { GetAddOnMetadata = function() return "1.0.0" end }

-- Timers: After runs on the next flush; NewTicker hands its callback back so
-- the sort can be stepped deliberately rather than raced.
local timerQueue = {}
local tickers = {}
C_Timer = {
    After = function(_, fn) timerQueue[#timerQueue + 1] = { fn = fn } end,
    NewTicker = function(_, fn)
        local handle = { fn = fn, cancelled = false }
        handle.Cancel = function(self) (self or handle).cancelled = true end
        tickers[#tickers + 1] = handle
        return handle
    end,
    NewTimer = function(_, fn)
        local entry = { fn = fn }
        entry.Cancel = function(self) (self or entry).cancelled = true end
        timerQueue[#timerQueue + 1] = entry
        return entry
    end,
}
local function FlushTimers()
    for _ = 1, 20 do
        if #timerQueue == 0 then return end
        local batch = timerQueue
        timerQueue = {}
        for _, entry in ipairs(batch) do
            if not entry.cancelled then entry.fn() end
        end
    end
end
-- The shared framework starts a session-stamp ticker of its own at load time
-- and never cancels it, so "is a job still running" has to mean "is a ticker
-- created AFTER the addon finished loading still running" — otherwise every
-- run-to-completion loop spins on the stamper forever.
local preloadTickers = 0
local function ActiveTicker()
    for index = #tickers, preloadTickers + 1, -1 do
        if not tickers[index].cancelled then return tickers[index] end
    end
    return nil
end
-- Runs the live ticker until it cancels itself or the budget runs out
local function RunTicker(budget)
    local steps = 0
    for _ = 1, budget or 400 do
        local handle = ActiveTicker()
        if not handle then break end
        steps = steps + 1
        handle.fn()
    end
    return steps
end

function UIDropDownMenu_Initialize() end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton() end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetSelectedValue() end
function UIDropDownMenu_SetText() end
function UIDropDownMenu_EnableDropDown() end
function UIDropDownMenu_DisableDropDown() end
function ToggleDropDownMenu() end
StaticPopupDialogs = {}
local popupsShown = {}
function StaticPopup_Show(which) popupsShown[#popupsShown + 1] = which return {} end
function IsShiftKeyDown() return false end
local ctrlDown = false
function IsControlKeyDown() return ctrlDown end
-- EasyMenu is FrameXML's; the harness records what a menu was built from so
-- the entries can be clicked without a real dropdown
local lastMenu
function EasyMenu(menu) lastMenu = menu end
local function MenuEntry(text)
    for _, entry in ipairs(lastMenu or {}) do
        if entry.text == text then return entry end
    end
    return nil
end
function IsModifiedClick() return false end
function InCombatLockdown() return false end
function SpellIsTargeting() return false end
function HandleModifiedItemClick() end
function CloseBankFrame() end
function PutItemInBag() end
function PickupBagFromSlot() end
-- Two bought of seven, and Blizzard's second return -- "there is nothing left
-- to buy" -- which the purchase row is gated on
local bankSlotsOwned, bankSlotsFull = 2, false
function GetNumBankSlots() return bankSlotsOwned, bankSlotsFull end
-- The stock formula's shape: each slot costs more than the last
function GetBankSlotCost(owned) return 1000 * (10 ^ math.min(owned or 0, 4)) end
local purchaseCalls = 0
function PurchaseSlot() purchaseCalls = purchaseCalls + 1 end

-- Guild bank. Tab 2 is deliberately not viewable by this rank: a tab you
-- cannot see reads as empty, which is NOT the same as being empty, and
-- recording that would be a lie the tooltip then repeats.
GuildBankFrame = NewWidget("Frame", "GuildBankFrame")
GuildBankFrame.__shown = false
MAX_GUILDBANK_SLOTS_PER_TAB = 98
local guildTabs = {
    [1] = { name = "Consumables", viewable = true,
            items = { [1] = { id = 207, n = 20 }, [2] = { id = 208, n = 5 } } },
    [2] = { name = "Officers", viewable = false, items = {} },
    [3] = { name = "Raid", viewable = true, items = { [1] = { id = 211, n = 6 } } },
}
local currentGuildTab, guildQueries = 1, {}
function GetGuildInfo(unit) if unit == "player" then return "Praetorians", "Member", 3 end end
function GetNumGuildBankTabs() return 3 end
function GetCurrentGuildBankTab() return currentGuildTab end
function GetGuildBankTabInfo(tab)
    local info = guildTabs[tab]
    if not info then return nil end
    return info.name, "Interface\\Icons\\INV_Box_01", info.viewable, true, 100, 100
end
function GetGuildBankItemLink(tab, slot)
    local info = guildTabs[tab]
    if not info or not info.viewable then return nil end
    local entry = info.items[slot]
    return entry and Link(entry.id) or nil
end
function GetGuildBankItemInfo(tab, slot)
    local info = guildTabs[tab]
    if not info or not info.viewable then return nil end
    local entry = info.items[slot]
    if not entry then return nil end
    return 100000 + entry.id, entry.n, false, false, ITEMS[entry.id].q
end
-- Querying a tab is what MOVES the selection, which is the whole reason the
-- module refuses to sweep without being asked
function QueryGuildBankTab(tab)
    currentGuildTab = tab
    guildQueries[#guildQueries + 1] = tab
    Fire("GUILDBANKBAGSLOTS_CHANGED")
end
function GetMoney() return 123456 end
function hooksecurefunc(name, hook)
    local orig = _G[name]
    _G[name] = function(...)
        local r1, r2, r3 = orig(...)
        hook(...)
        return r1, r2, r3
    end
end

function GetRealmName() return "Aleria" end
function UnitName(unit) if unit == "player" then return "Devinq" end return nil end
function UnitClass(unit) if unit == "player" then return "Mage", "MAGE" end return nil end
function UnitLevel() return 70 end
RAID_CLASS_COLORS = { MAGE = { r = 0.41, g = 0.8, b = 0.94 } }
CLASS_ICON_TCOORDS = { MAGE = { 0, 0.25, 0, 0.25 } }

ITEM_QUALITY_COLORS = {
    [0] = { r = 0.62, g = 0.62, b = 0.62 },
    [1] = { r = 1, g = 1, b = 1 },
    [2] = { r = 0.12, g = 1, b = 0 },
    [3] = { r = 0, g = 0.44, b = 0.87 },
    [4] = { r = 0.64, g = 0.21, b = 0.93 },
}

INVTYPE_HEAD = "Head"
INVTYPE_FINGER = "Finger"
INVTYPE_CHEST = "Chest"
INVTYPE_LEGS = "Legs"

BANK_CONTAINER = -1
NUM_BAG_SLOTS = 4
NUM_BANKBAGSLOTS = 7
NUM_BANKGENERIC_SLOTS = 28

-- ---------------------------------------------------------------------------
-- The world
--
-- classID: 0 consumable, 2 weapon, 4 armor, 7 tradegoods, 9 recipe, 12 quest,
-- 15 misc. bind: 1 BoP, 2 BoE, 4 quest. armour subclass: 1 cloth … 4 plate.
-- ---------------------------------------------------------------------------

ITEMS = {
    [201] = { name = "Frozen Shadoweave Hood", q = 4, ilvl = 120, cls = 4, sub = 1,
              loc = "INVTYPE_HEAD", bind = 1, stack = 1, price = 5000, type = "Armor", subType = "Cloth" },
    [202] = { name = "Bloodfang Spaulders", q = 4, ilvl = 76, cls = 4, sub = 2,
              loc = "INVTYPE_HEAD", bind = 1, stack = 1, price = 3000, type = "Armor", subType = "Leather" },
    [203] = { name = "Lionheart Helm", q = 4, ilvl = 66, cls = 4, sub = 4,
              loc = "INVTYPE_HEAD", bind = 1, stack = 1, price = 2000, type = "Armor", subType = "Plate" },
    [204] = { name = "Band of the Eternal Sage", q = 4, ilvl = 141, cls = 4, sub = 0,
              loc = "INVTYPE_FINGER", bind = 2, stack = 1, price = 8000, type = "Armor", subType = "Miscellaneous" },
    [205] = { name = "Broken Fang", q = 0, ilvl = 1, cls = 15, sub = 0,
              loc = "", bind = 0, stack = 10, price = 137, type = "Miscellaneous", subType = "Junk" },
    [206] = { name = "Chipped Claw", q = 0, ilvl = 1, cls = 15, sub = 0,
              loc = "", bind = 0, stack = 10, price = 89, type = "Miscellaneous", subType = "Junk" },
    [207] = { name = "Netherweave Cloth", q = 1, ilvl = 1, cls = 7, sub = 5,
              loc = "", bind = 0, stack = 20, price = 15, type = "Trade Goods", subType = "Cloth" },
    [208] = { name = "Super Healing Potion", q = 1, ilvl = 1, cls = 0, sub = 1,
              loc = "", bind = 0, stack = 5, price = 200, type = "Consumable", subType = "Potion" },
    [209] = { name = "Pattern: Spellstrike Hood", q = 3, ilvl = 1, cls = 9, sub = 2,
              loc = "", bind = 0, stack = 1, price = 1000, type = "Recipe", subType = "Tailoring" },
    [210] = { name = "Sealed Orders", q = 1, ilvl = 1, cls = 12, sub = 0,
              loc = "", bind = 4, stack = 1, price = 0, type = "Quest", subType = "Quest" },
    -- Deliberately never placed in any container: the tooltip layer has to
    -- stay silent for an item you own none of
    [212] = { name = "Elixir of Major Agility", q = 1, ilvl = 1, cls = 0, sub = 2,
              loc = "", bind = 0, stack = 5, price = 300, type = "Consumable", subType = "Elixir" },
    [211] = { name = "Primal Nether", q = 3, ilvl = 1, cls = 7, sub = 10,
              loc = "", bind = 2, stack = 10, price = 0, type = "Trade Goods", subType = "Elemental" },
    -- The mats deposit's cast: two materials, and four things that share a
    -- class with them and must not move
    [213] = { name = "Arcane Dust", q = 1, ilvl = 1, cls = 7, sub = 12,
              loc = "", bind = 0, stack = 20, price = 0, type = "Trade Goods", subType = "Enchanting" },
    [214] = { name = "Living Ruby", q = 3, ilvl = 1, cls = 3, sub = 0,
              loc = "", bind = 0, stack = 20, price = 0, type = "Gem", subType = "Red" },
    [22462] = { name = "Runed Adamantite Rod", q = 1, ilvl = 1, cls = 7, sub = 12,
              loc = "", bind = 0, stack = 1, price = 0, type = "Trade Goods", subType = "Enchanting" },
    [215] = { name = "Sacred Candle", q = 1, ilvl = 1, cls = 5, sub = 0,
              loc = "", bind = 0, stack = 20, price = 0, type = "Reagent", subType = "Reagent" },
    [216] = { name = "Super Sapper Charge", q = 1, ilvl = 1, cls = 7, sub = 2,
              loc = "", bind = 0, stack = 10, price = 0, type = "Trade Goods", subType = "Explosives" },
    [217] = { name = "Gyromatic Micro-Adjustor", q = 1, ilvl = 1, cls = 7, sub = 3,
              loc = "", bind = 0, stack = 1, price = 0, type = "Trade Goods", subType = "Devices" },
    [218] = { name = "Runed Eternium Rod", q = 1, ilvl = 1, cls = 7, sub = 12,
              loc = "", bind = 0, stack = 1, price = 0, type = "Trade Goods", subType = "Enchanting" },
}

-- bag -> slot -> { id, count }
local function ResetWorld()
    cursor = nil
    sizes = { [-1] = 28, [5] = 16, [6] = 0, [7] = 0, [8] = 0, [9] = 0, [10] = 0, [11] = 0,
              [0] = 16, [1] = 16, [2] = 0, [3] = 0, [4] = 0 }
    world = { [-1] = {}, [5] = {}, [0] = {}, [1] = {} }
    local bank = world[-1]
    bank[1]  = { id = 205, count = 8 }
    bank[2]  = { id = 207, count = 12 }
    bank[3]  = { id = 202, count = 1 }
    bank[5]  = { id = 207, count = 5 }
    bank[6]  = { id = 208, count = 3 }
    bank[8]  = { id = 209, count = 1 }
    bank[9]  = { id = 203, count = 1 }
    bank[11] = { id = 206, count = 4 }
    bank[12] = { id = 204, count = 1 }
    bank[14] = { id = 207, count = 2 }
    bank[15] = { id = 210, count = 1 }
    world[5][1] = { id = 211, count = 4 }
    world[5][3] = { id = 201, count = 1 }
    -- Carried: a stack of cloth the bank already holds, plus a potion
    world[0][1] = { id = 207, count = 7 }
    world[0][2] = { id = 208, count = 2 }
end
ResetWorld()

-- Same containers, nothing in them: a vault with 28 free slots is a different
-- claim from a vault nobody has ever recorded, and only one of them is news
local function ClearWorld()
    cursor = nil
    for bag in pairs(world) do world[bag] = {} end
end

local uncached = {}

Link = function(id) return "|Hitem:" .. id .. ":0|h[" .. (ITEMS[id].name) .. "]|h" end

function CursorHasItem() return cursor ~= nil end

C_Container = {
    GetContainerNumSlots = function(bag) return sizes[bag] or 0 end,
    GetContainerNumFreeSlots = function(bag)
        local free, size = 0, sizes[bag] or 0
        for slot = 1, size do
            if not (world[bag] and world[bag][slot]) then free = free + 1 end
        end
        return free, 0
    end,
    GetContainerItemInfo = function(bag, slot)
        local entry = world[bag] and world[bag][slot]
        if not entry then return nil end
        local item = ITEMS[entry.id]
        return {
            itemID = entry.id, stackCount = entry.count, isLocked = entry.locked or false,
            quality = item.q, hyperlink = Link(entry.id), iconFileID = 100000 + entry.id,
            hasNoValue = item.price == 0, isBound = entry.bound,
        }
    end,
    PickupContainerItem = function(bag, slot)
        local slots = world[bag]
        if not slots then return end
        local entry = slots[slot]
        if not cursor then
            if entry then
                cursor = { id = entry.id, count = entry.count }
                slots[slot] = nil
            end
            return
        end
        if not entry then
            slots[slot] = { id = cursor.id, count = cursor.count }
            cursor = nil
        elseif entry.id == cursor.id then
            local room = ITEMS[entry.id].stack - entry.count
            local moved = math.min(room, cursor.count)
            entry.count = entry.count + moved
            cursor.count = cursor.count - moved
            if cursor.count <= 0 then cursor = nil end
        else
            slots[slot] = { id = cursor.id, count = cursor.count }
            cursor = { id = entry.id, count = entry.count }
        end
    end,
    SplitContainerItem = function(bag, slot, amount)
        local entry = world[bag] and world[bag][slot]
        if cursor or not entry or amount <= 0 or amount > entry.count then return end
        cursor = { id = entry.id, count = amount }
        entry.count = entry.count - amount
        if entry.count <= 0 then world[bag][slot] = nil end
    end,
    -- With the bank open this is "move it to the other side", which is exactly
    -- what the module relies on
    UseContainerItem = function(bag, slot)
        local entry = world[bag] and world[bag][slot]
        if not entry then return end
        local isBank = (bag == -1 or (bag >= 5 and bag <= 11))
        local targets = isBank and { 0, 1 } or { -1, 5 }
        for _, target in ipairs(targets) do
            for targetSlot = 1, (sizes[target] or 0) do
                local existing = world[target] and world[target][targetSlot]
                if existing and existing.id == entry.id
                    and existing.count < ITEMS[entry.id].stack then
                    local room = ITEMS[entry.id].stack - existing.count
                    local moved = math.min(room, entry.count)
                    existing.count = existing.count + moved
                    entry.count = entry.count - moved
                    if entry.count <= 0 then world[bag][slot] = nil return end
                end
            end
        end
        for _, target in ipairs(targets) do
            for targetSlot = 1, (sizes[target] or 0) do
                if not (world[target] and world[target][targetSlot]) then
                    world[target] = world[target] or {}
                    world[target][targetSlot] = { id = entry.id, count = entry.count }
                    world[bag][slot] = nil
                    return
                end
            end
        end
    end,
    ContainerIDToInventoryID = function(bag) return 67 + bag end,
}

C_Item = {
    GetItemInfo = function(key)
        local id = tonumber(key) or tonumber(tostring(key):match("item:(%d+)") or "")
        local item = id and ITEMS[id]
        if not item or uncached[id] then return nil end
        return item.name, Link(id), item.q, item.ilvl, 1, item.type, item.subType,
            item.stack, item.loc, 100000 + id, item.price, item.cls, item.sub, item.bind
    end,
    GetItemInfoInstant = function(key)
        local id = tonumber(key) or tonumber(tostring(key):match("item:(%d+)") or "")
        local item = id and ITEMS[id]
        if not item then return nil end
        return id, item.type, item.subType, item.loc, 100000 + id, item.cls, item.sub
    end,
    -- The second argument is includeBank, and honouring it matters: the
    -- module reads the played character's bank through this call precisely
    -- BECAUSE it answers with the bank shut.
    GetItemCount = function(id, includeBank)
        local total = 0
        local bags = { 0, 1 }
        if includeBank then bags = { 0, 1, -1, 5 } end
        for _, bag in ipairs(bags) do
            for slot = 1, (sizes[bag] or 0) do
                local entry = world[bag] and world[bag][slot]
                if entry and entry.id == id then total = total + entry.count end
            end
        end
        return total
    end,
}

-- The mage is wearing a 141 head, so the 120 cloth hood in the bank is
-- outclassed and the 76 leather / 66 plate are unwearable
local EQUIPPED = { [1] = 204 }
function GetInventoryItemLink(_, slotID)
    local id = EQUIPPED[slotID]
    return id and Link(id) or nil
end
function GetInventoryItemTexture() return nil end

-- ===========================================================================
-- Load the real framework + addon
-- ===========================================================================

local function Load(path)
    local chunk = assert(loadfile(path))
    chunk()
end

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
-- Everything the module is allowed to publish. A global that is not on this
-- list is either a leak or a new entry point somebody forgot to write down.
local GLOBALS_BEFORE = {}
for key in pairs(_G) do GLOBALS_BEFORE[key] = true end

Load(ADDONS .. "/Commander_Vault/CommanderVaultDB.lua")
Load(ADDONS .. "/Commander_Vault/CommanderVaultCore.lua")
Load(ADDONS .. "/Commander_Vault/CommanderVaultSearch.lua")
Load(ADDONS .. "/Commander_Vault/CommanderVaultGuild.lua")
Load(ADDONS .. "/Commander_Vault/CommanderVaultAdvisor.lua")
Load(ADDONS .. "/Commander_Vault/CommanderVaultSort.lua")
Load(ADDONS .. "/Commander_Vault/CommanderVaultTooltip.lua")
Load(ADDONS .. "/Commander_Vault/CommanderVaultUI.lua")

local V = CommanderVault
preloadTickers = #tickers

Fire = function(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    local copy = {}
    for index, frame in ipairs(list) do copy[index] = frame end
    for _, frame in ipairs(copy) do
        local handler = frame.__scripts and frame.__scripts.OnEvent
        if handler then handler(frame, event, ...) end
    end
end

-- A database that has never been written: the fresh-install path, where the
-- default is simply whatever DefaultSettings says.
CommanderVaultDB = {}
Fire("ADDON_LOADED", "Commander_Vault")
CHECK(CommanderVaultDB.Grouping == "DETAIL",
    "a fresh database groups in Detail -- equipment split by slot",
    CommanderVaultDB.Grouping)

-- An EXISTING database still carrying the old default. ApplyDefaults never
-- overwrites a key that is present, so without the one-time move this install
-- would keep Sections forever and never learn the finer view was there.
CommanderVaultDB = { Grouping = "SECTION" }
Fire("ADDON_LOADED", "Commander_Vault")
CHECK(CommanderVaultDB.Grouping == "DETAIL",
    "an existing database on the OLD default is moved to Detail once",
    CommanderVaultDB.Grouping)

-- ...and the move is one-time, so it can never overrule a real preference.
-- Someone who wants Sections sets it back and it stays set back.
CommanderVaultDB.Grouping = "SECTION"
Fire("ADDON_LOADED", "Commander_Vault")
CHECK(CommanderVaultDB.Grouping == "SECTION",
    "and NEVER again -- choosing Sections back sticks, the flag is already set",
    CommanderVaultDB.Grouping)

-- Back to the default for the rest of the harness.
CommanderVaultDB = {}
Fire("ADDON_LOADED", "Commander_Vault")
Fire("PLAYER_LOGIN")
FlushTimers()

-- ===========================================================================
-- A: containers and the model
-- ===========================================================================

io.write("A: containers and the model\n")

local first, last = V.BankBagRange()
CHECK(first == 5 and last == 11, "bank bags are 5..11, not the mainline enum's 6..12", first .. ".." .. last)
local containers = V.BankContainers()
CHECK(containers[1] == -1 and #containers == 8, "the vault owns the base container and seven bank bags", #containers)
CHECK(V.IsBankContainer(-1) and V.IsBankContainer(7) and not V.IsBankContainer(0),
    "bag 0 is not a bank container")

CHECK(#V.ScanBank().items == 0, "a bank scan with the bank shut reads nothing")

V.SetBankOpen(true)
local bank = V.ScanBank()
CHECK(#bank.items == 13, "the live scan finds every stack across both containers", #bank.items)
CHECK(bank.total == 44, "and counts all 28 base slots plus the 16-slot bank bag", bank.total)
CHECK(bank.free == 31, "with the empty slots accounted for", bank.free)
CHECK(bank.live == true, "a live scan is flagged live")

local function RowFor(snap, id)
    for _, row in ipairs(snap.items) do
        if row.itemID == id then return row end
    end
end

CHECK(RowFor(bank, 205).section == "JUNK", "grey is a verdict: a grey misc item files as junk")
CHECK(RowFor(bank, 210).section == "QUEST", "a quest item files as quest whatever its class")
CHECK(RowFor(bank, 202).section == "EQUIPMENT", "armour files as equipment")
CHECK(RowFor(bank, 207).section == "TRADE", "cloth files as trade goods")
CHECK(RowFor(bank, 208).section == "CONSUMABLE", "a potion files as a consumable")
CHECK(RowFor(bank, 209).section == "RECIPE", "a pattern files as a recipe")
CHECK(V.SubgroupOf(RowFor(bank, 202)) == "Head", "detailed grouping puts equipment under its slot")
CHECK(V.SubgroupOf(RowFor(bank, 208)) == "Potion", "and everything else under its own subtype")

local hood = RowFor(bank, 201)
CHECK(hood ~= nil and hood.bag == 5, "the bank bag's contents are in the same snapshot", hood and hood.bag)
CHECK(hood.full == true and hood.ilvl == 120, "a resolved row carries the slow half of the item data")

local tally = V.Tally(bank)
CHECK(tally[207].stacks == 3 and tally[207].count == 19,
    "the tally folds three cloth stacks into one entry", tally[207] and tally[207].count)

CHECK(V.RowValue(RowFor(bank, 205)) == 137 * 8, "row value is price times stack")
CHECK(V.RowValue(RowFor(bank, 210)) == 0, "and nothing for an item the vendor will not take")
CHECK(V.Money(12345):find("1|rg") ~= nil, "money reads as gold and silver", V.Money(12345))

-- ===========================================================================
-- B: the cache and dwell history
-- ===========================================================================

io.write("B: the cache and dwell history\n")

local record = V.CharRecord(false)
CHECK(record ~= nil and #record.items == 13, "the live scan wrote a snapshot through to the cache",
    record and record.items and #record.items)
CHECK(record.class == "MAGE" and record.realm == "Aleria", "keyed to this character on this realm")

V.SetBankOpen(false)
local cached = V.CurrentBank()
CHECK(cached.cached == true, "away from the bank the window reads the remembered snapshot")
CHECK(#cached.items == 13, "which holds everything the live one did", #cached.items)
CHECK(RowFor(cached, 201) ~= nil and RowFor(cached, 201).bag == 5,
    "including which container each stack sat in")
CHECK(cached.free == 31, "and the slot accounting is remembered too", cached.free)

CHECK(V.DwellDays(207) == 0, "an item just seen has dwelt zero days", V.DwellDays(207))
NOW = NOW + 86400 * 90
CHECK(V.DwellDays(207) == 90, "ninety days later it has dwelt ninety days", V.DwellDays(207))

-- An item that leaves the bank must lose its clock, or a withdrawn and
-- redeposited stack would read as ancient
V.SetBankOpen(true)
world[-1][2] = nil
world[-1][5] = nil
world[-1][14] = nil
V.ScanBank()
CHECK(V.DwellDays(207) == nil, "an item that leaves the vault forgets when it arrived")
ResetWorld()
V.ScanBank()
CHECK(V.DwellDays(207) == 0, "and starts its clock again when it comes back", V.DwellDays(207))
-- Wind the clock back and re-stamp, so the search and advisor sections start
-- from a vault whose every item arrived just now
NOW = NOW - 86400 * 90
V.CharRecord(true).seen = nil
V.ScanBank()

-- ===========================================================================
-- C: the search language
-- ===========================================================================

io.write("C: the search language\n")

V.SetBankOpen(true)
bank = V.ScanBank()

local function Hits(text)
    local out = {}
    local q = V.ParseQuery(text)
    for _, row in ipairs(bank.items) do
        if V.MatchRow(row, q) then out[#out + 1] = row.itemID end
    end
    table.sort(out)
    return out
end
local function HitCount(text) return #Hits(text) end
local function Has(text, id)
    for _, hit in ipairs(Hits(text)) do if hit == id then return true end end
    return false
end

CHECK(V.QueryIsEmpty(V.ParseQuery("")), "an empty box means everything")
CHECK(HitCount("") == 13, "and matches every stack", HitCount(""))
CHECK(Has("netherweave", 207), "free text matches the name, case-insensitively")
CHECK(HitCount("netherweave") == 3, "and matches every stack of it", HitCount("netherweave"))
CHECK(Has("cloth", 207) and Has("cloth", 201),
    "free text also reaches the item's type and subtype")
CHECK(not Has("-netherweave", 207), "a leading minus excludes")
CHECK(Has('"sealed orders"', 210), "a quoted phrase matches as one token")
CHECK(HitCount("sealed potion") == 0, "two words narrow rather than widen")
CHECK(Has("q:epic", 201) and not Has("q:epic", 207), "q:epic reads the quality by name")
CHECK(HitCount("q:>=rare") == 6, "q:>=rare is a threshold", HitCount("q:>=rare"))
CHECK(HitCount("ilvl:>100") == 2, "ilvl takes a comparison", HitCount("ilvl:>100"))
CHECK(Has("t:consumable", 208) and not Has("t:consumable", 207), "t: matches the item type")
CHECK(Has("t:recipe", 209), "and the vault's own section names")
CHECK(Has("s:head", 201) and not Has("s:head", 204), "s: matches the equip slot")
CHECK(Has("boe", 204) and not Has("boe", 201), "boe finds the unbound bind-on-equip items")
CHECK(Has("bop", 201) and not Has("bop", 204), "bop finds the bind-on-pickup ones")
CHECK(Has("junk", 205) and HitCount("junk") == 2, "junk finds the greys", HitCount("junk"))
CHECK(Has("quest", 210), "quest finds the quest items")
CHECK(Has("partial", 207), "partial finds stacks below their maximum")
CHECK(not Has("partial", 201), "and never a stack that cannot stack at all")
CHECK(Has("usable", 201) and not Has("usable", 203),
    "usable knows a mage cannot wear plate")
CHECK(HitCount("q:epic s:head") == 3, "terms combine", HitCount("q:epic s:head"))
CHECK(HitCount("q:epic -bop") == 1, "including a negated one", HitCount("q:epic -bop"))
CHECK(HitCount("zzz:nonsense") == 0, "an unknown field falls back to a text search that finds nothing")
NOW = NOW + 86400 * 70
CHECK(HitCount("old:60") == 13, "old:N reads as at least N days", HitCount("old:60"))
CHECK(HitCount("old:<10") == 0, "and an explicit operator still wins", HitCount("old:<10"))
NOW = NOW - 86400 * 70
CHECK(HitCount("new") == 13, "new is everything that arrived today", HitCount("new"))

-- ===========================================================================
-- D: the advisor
-- ===========================================================================

io.write("D: the advisor\n")

local bags = V.ScanBags()
CHECK(#bags.items == 2, "the carried snapshot reads the player's own bags", #bags.items)

local findings = V.BuildReport(bank, bags)
local byKey = {}
for _, finding in ipairs(findings) do byKey[finding.key] = finding end

CHECK(byKey.JUNK ~= nil, "the report calls out the greys")
CHECK(byKey.JUNK and #byKey.JUNK.rows == 2, "both of them", byKey.JUNK and #byKey.JUNK.rows)
CHECK(byKey.JUNK and byKey.JUNK.value == 137 * 8 + 89 * 4, "with what a vendor would pay",
    byKey.JUNK and byKey.JUNK.value)
CHECK(byKey.JUNK and byKey.JUNK.search == "junk", "and a search that shows exactly those")

CHECK(byKey.STACKS ~= nil, "it notices the split stacks")
CHECK(byKey.STACKS and byKey.STACKS.reclaim == 2,
    "three cloth stacks totalling 19 of a 20-stack is two wasted slots",
    byKey.STACKS and byKey.STACKS.reclaim)
CHECK(byKey.STACKS and byKey.STACKS.action == "SORT", "and offers the sort that fixes it")

CHECK(byKey.UNUSABLE ~= nil, "it notices gear a mage cannot wear")
CHECK(byKey.UNUSABLE and #byKey.UNUSABLE.rows == 2,
    "the leather and the plate, not the cloth", byKey.UNUSABLE and #byKey.UNUSABLE.rows)

CHECK(byKey.OUTCLASSED ~= nil, "it notices bound gear beaten by what you wear")
CHECK(byKey.OUTCLASSED and #byKey.OUTCLASSED.rows == 1,
    "only the wearable one — unusable gear is already its own finding",
    byKey.OUTCLASSED and #byKey.OUTCLASSED.rows)

CHECK(byKey.TRADEABLE ~= nil, "it notices unbound rares still worth listing")
CHECK(byKey.TRADEABLE and #byKey.TRADEABLE.rows == 2, "the ring and the nether",
    byKey.TRADEABLE and #byKey.TRADEABLE.rows)

CHECK(byKey.DEPOSIT ~= nil, "it notices bag stacks that already live in the vault")
CHECK(byKey.DEPOSIT and #byKey.DEPOSIT.rows == 2, "the cloth and the potions",
    byKey.DEPOSIT and #byKey.DEPOSIT.rows)

CHECK(byKey.SPACE == nil, "a vault three-quarters empty raises no space warning")

-- The Quartermaster hand-off. Absent, the rule must stay silent; present, it
-- must read BANKED (owned but not carried) and nothing else.
CHECK(byKey.LOADOUT == nil, "with no Quartermaster installed the loadout rule stays silent")
CommanderQuartermaster_LoadoutState = function()
    return { slots = {
        { slot = "POTION", name = "Battle Potion", state = "BANKED", entry = { id = 208 }, count = 3 },
        { slot = "FLASK",  name = "Flask",         state = "CARRIED", entry = { id = 207 }, count = 7 },
        { slot = "FOOD",   name = "Food",          state = "MISSING", entry = { id = 211 }, count = 0 },
    } }
end
findings = V.BuildReport(bank, bags)
byKey = {}
for _, finding in ipairs(findings) do byKey[finding.key] = finding end
CHECK(byKey.LOADOUT ~= nil, "with it installed, a banked loadout consumable is raised")
CHECK(byKey.LOADOUT and #byKey.LOADOUT.rows == 1,
    "only the banked one — carried is handled and missing is a shopping trip",
    byKey.LOADOUT and #byKey.LOADOUT.rows)
CHECK(byKey.LOADOUT and byKey.LOADOUT.detail:find("Battle Potion") ~= nil,
    "and it names the loadout slot rather than the item", byKey.LOADOUT and byKey.LOADOUT.detail)
CommanderQuartermaster_LoadoutState = nil
findings = V.BuildReport(bank, bags)
byKey = {}
for _, finding in ipairs(findings) do byKey[finding.key] = finding end


CHECK(byKey.STALE == nil, "nothing is stale on the day it arrives")
NOW = NOW + 86400 * 70
findings = V.BuildReport(bank, bags)
byKey = {}
for _, finding in ipairs(findings) do byKey[finding.key] = finding end
CHECK(byKey.STALE ~= nil and #byKey.STALE.rows == 11,
    "seventy days later everything but the greys is stale", byKey.STALE and #byKey.STALE.rows)
NOW = NOW - 86400 * 70

CHECK(findings[1] and findings[1].severity == 3, "the report leads with the worst finding",
    findings[1] and findings[1].severity)
local descending = true
for index = 2, #findings do
    if findings[index].severity > findings[index - 1].severity then descending = false end
end
CHECK(descending, "and never puts a milder finding above a worse one")

local summary = V.Summary(bank)
CHECK(summary.items == 13 and summary.free == 31, "the summary agrees with the snapshot")
CHECK(summary.junkValue == 137 * 8 + 89 * 4, "and separates out what the greys are worth")

-- A full vault must raise the space warning
local savedSizes = sizes[-1]
for slot = 1, 28 do world[-1][slot] = world[-1][slot] or { id = 205, count = 1 } end
sizes[5] = 0
V.ScanBank()
findings = V.BuildReport(V.bank, bags)
byKey = {}
for _, finding in ipairs(findings) do byKey[finding.key] = finding end
CHECK(byKey.SPACE ~= nil and byKey.SPACE.severity == 3, "a full vault is a warning, not a note")
sizes[5] = 16
ResetWorld()
bank = V.ScanBank()

-- The Armory hand-off. The single worst thing this module could do is tell you
-- to disenchant the PvP set you keep in the bank on purpose.
CHECK(V.SetWanting(202) == nil, "with no Armory installed nothing belongs to a set")
CommanderArmory_SetItemIDs = function()
    return { [202] = "Arena", [204] = "Arena" }
end
V.RefreshSetMembership()
CHECK(V.SetWanting(202) == "Arena", "with it installed, a set member is recognised")

findings = V.BuildReport(bank, bags)
byKey = {}
for _, finding in ipairs(findings) do byKey[finding.key] = finding end
CHECK(byKey.UNUSABLE and #byKey.UNUSABLE.rows == 1,
    "the leather shoulders drop out of \"gear you cannot use\" once a set wants them",
    byKey.UNUSABLE and #byKey.UNUSABLE.rows)
CHECK(byKey.TRADEABLE and #byKey.TRADEABLE.rows == 1,
    "and the ring drops out of \"still tradeable\"", byKey.TRADEABLE and #byKey.TRADEABLE.rows)
CHECK(byKey.SETS ~= nil and #byKey.SETS.rows == 2,
    "with a finding of their own saying why they are absent from the rest",
    byKey.SETS and #byKey.SETS.rows)
CHECK(byKey.SETS and byKey.SETS.detail:find("Arena") ~= nil,
    "naming the set", byKey.SETS and byKey.SETS.detail)
CHECK(byKey.SETS and byKey.SETS.severity == 1, "as information, not a complaint")

NOW = NOW + 86400 * 70
findings = V.BuildReport(bank, bags)
byKey = {}
for _, finding in ipairs(findings) do byKey[finding.key] = finding end
CHECK(byKey.STALE and #byKey.STALE.rows == 9,
    "and a set piece is never called stale — it has sat there on purpose",
    byKey.STALE and #byKey.STALE.rows)
NOW = NOW - 86400 * 70

local setHits = 0
local setQuery = V.ParseQuery("set")
for _, row in ipairs(bank.items) do
    if V.MatchRow(row, setQuery) then setHits = setHits + 1 end
end
CHECK(setHits == 2, "and the search language can find them: set", setHits)

CommanderArmory_SetItemIDs = nil
V.RefreshSetMembership()
findings = V.BuildReport(bank, bags)
byKey = {}
for _, finding in ipairs(findings) do byKey[finding.key] = finding end
CHECK(byKey.SETS == nil, "with Armory gone the finding goes quiet again")
CHECK(byKey.UNUSABLE and #byKey.UNUSABLE.rows == 2, "and the clutter rules go back to normal")

-- ===========================================================================
-- E: the sort
-- ===========================================================================

io.write("E: the sort\n")

CHECK(V.IsGeneralContainer(-1), "the base bank container always sorts")
local savedFree = C_Container.GetContainerNumFreeSlots
C_Container.GetContainerNumFreeSlots = function() return 4, 2 end
CHECK(not V.IsGeneralContainer(5), "a bag with a family — a quiver, a soul bag — never does")
C_Container.GetContainerNumFreeSlots = savedFree

local compare = V.Comparators.QUALITY
local a = { itemID = 1, count = 5, quality = 3, ilvl = 10, name = "x" }
local b = { itemID = 1, count = 5, quality = 3, ilvl = 10, name = "x" }
CHECK(not compare(a, b) and not compare(b, a),
    "identical stacks tie — which is what stops the executor ping-ponging them")
b.count = 3
CHECK(compare(a, b) and not compare(b, a), "and the count tail is a strict total order")

V.SetBankOpen(false)
CommanderVault_SortBank()
CHECK(LastPrint():find("open the bank") ~= nil, "sorting refuses without a banker", LastPrint())

V.SetBankOpen(true)
CommanderVaultDB.SortOrder = "QUALITY"
CommanderVault_SortBank()
if os.getenv("VAULT_TRACE") then
    local handle = ActiveTicker()
    for pass = 1, 60 do
        if not ActiveTicker() then break end
        handle.fn()
        local line = {}
        for slot = 1, 20 do
            local e = world[-1][slot]
            line[#line + 1] = e and (e.id .. "x" .. e.count) or "."
        end
        io.write(pass, "  ", table.concat(line, " "), "  cursor=",
            cursor and (cursor.id .. "x" .. cursor.count) or "-", "\n")
    end
end
local steps = RunTicker(400)
CHECK(steps > 0 and ActiveTicker() == nil, "the sort runs to completion and cancels itself", steps)
CHECK(LastPrint():find("vault sorted") ~= nil, "and says so", LastPrint())

bank = V.ScanBank()
local clothStacks = 0
for _, row in ipairs(bank.items) do
    if row.itemID == 207 then clothStacks = clothStacks + 1 end
end
CHECK(clothStacks == 1, "the merge phase folded 12 + 5 + 2 cloth into one stack of 19", clothStacks)
CHECK(bank.free == 33, "which gave two slots back", bank.free)
CHECK(#bank.items == 11, "and left two fewer entries than before", #bank.items)

local ordered = true
local previous
for index = 1, #bank.slots do
    local row = bank.rows[index]
    if row then
        if previous and V.Comparators.QUALITY(row, previous) then ordered = false end
        previous = row
    end
end
CHECK(ordered, "and everything left is in quality order, front to back")

local compacted = true
local sawGap = false
for index = 1, #bank.slots do
    if bank.slots[index].bag == -1 then
        if bank.rows[index] then
            if sawGap then compacted = false end
        else
            sawGap = true
        end
    end
end
CHECK(compacted, "with the items compacted to the front and the empty slots behind them")
CHECK(cursor == nil, "and nothing left on the cursor")

-- Combat has to stop it mid-flight rather than at the next full pass
ResetWorld()
bank = V.ScanBank()
CommanderVault_SortBank()
local handle = ActiveTicker()
handle.fn()
InCombatLockdown = function() return true end
handle.fn()
CHECK(ActiveTicker() == nil, "combat stops the sort on the very next tick")
CHECK(LastPrint():find("combat") ~= nil, "and says why", LastPrint())
InCombatLockdown = function() return false end

-- ===========================================================================
-- F: transfers
-- ===========================================================================

io.write("F: transfers\n")

ResetWorld()
V.SetBankOpen(true)
BankFrame.__shown = true
V.ScanBank()
V.ScanBags()
CommanderVault_Deposit(V.DEPOSIT_RULES.TRADE.wants, "deposited")
RunTicker(200)
local carriedCloth = C_Item.GetItemCount(207)
CHECK(carriedCloth == 0, "depositing trade goods moves every stack of cloth out of the bags", carriedCloth)
CHECK(C_Item.GetItemCount(208) == 2, "and leaves the potions where they were", C_Item.GetItemCount(208))

BankFrame.__shown = false
V.SetBankOpen(false)
CHECK(CommanderVault_Deposit(V.DEPOSIT_RULES.TRADE.wants) == false,
    "a deposit with the bank shut is refused outright — the same call would eat the item")

-- The mats deposit: every material, none of the things that only share a
-- class with one
local function PackMatsBag()
    world[0] = {}
    world[0][1] = { id = 213, count = 20 }    -- dust: a mat
    world[0][2] = { id = 214, count = 3 }     -- gem: a mat
    world[0][3] = { id = 211, count = 2 }     -- primal nether: a mat, BoE or not
    world[0][4] = { id = 22462, count = 1 }   -- the rod: a tool
    world[0][5] = { id = 215, count = 20 }    -- candles: a spell reagent
    world[0][6] = { id = 216, count = 5 }     -- sapper: a finished good
    world[0][7] = { id = 217, count = 1 }     -- engineer's tool
    world[0][8] = { id = 208, count = 2 }     -- a potion, for company
    world[0][9] = { id = 207, count = 7 }     -- cloth: a mat
end

ResetWorld()
PackMatsBag()
V.SetBankOpen(true)
BankFrame.__shown = true
V.ScanBank()
V.ScanBags()
CommanderVault_Deposit(V.DepositPredicate(V.DEPOSIT_RULES.MATS), "mats deposited")
RunTicker(300)
local function Carried(id)
    local n = 0
    for _, entry in pairs(world[0]) do if entry.id == id then n = n + entry.count end end
    return n
end
CHECK(Carried(213) == 0, "mats: enchanting dust goes to the bank", Carried(213))
CHECK(Carried(214) == 0, "mats: gems go too", Carried(214))
CHECK(Carried(211) == 0, "mats: a BoE primal is still a mat", Carried(211))
CHECK(Carried(207) == 0, "mats: cloth goes", Carried(207))
CHECK(Carried(22462) == 1, "mats: the runed rod stays in the enchanter's hands", Carried(22462))
CHECK(Carried(215) == 20, "mats: spell reagents are not mats", Carried(215))
CHECK(Carried(216) == 5, "mats: explosives are finished goods, not mats", Carried(216))
CHECK(Carried(217) == 1, "mats: devices are tools, not mats", Carried(217))
CHECK(Carried(208) == 2, "mats: and the potion is untouched", Carried(208))
CHECK(LastPrint():find("mats deposited") ~= nil, "mats: the done line says what it did", LastPrint())

-- A stack filed under a section of the player's own is still a mat. The older
-- Trade Goods rule keys on the section and loses it; this one must not.
ResetWorld()
PackMatsBag()
CommanderVaultDB.ItemSection = CommanderVaultDB.ItemSection or {}
V.SetItemSection(213, "Enchanting")
V.ScanBank()
V.ScanBags()
local filedRow
for _, row in ipairs(V.ScanBags().items) do if row.itemID == 213 then filedRow = row end end
CHECK(filedRow and filedRow.section ~= "TRADE", "mats: the filed dust has left the Trade Goods section", filedRow and filedRow.section)
CHECK(filedRow and V.DEPOSIT_RULES.TRADE.wants(filedRow) == false, "mats: ...so the Trade Goods rule no longer sees it")
CHECK(filedRow and V.IsMaterial(filedRow) == true, "mats: ...and the mats rule still does")
V.SetItemSection(213, nil)

-- A rod the Formulary knows about is protected without being on the floor list
CommanderFormulary_Data = { ENCHANTING = { recipes = {
    { spell = 1, name = "Runed Eternium Rod", category = "RODS", creates = 218 },
} } }
ResetWorld()
world[0] = { [1] = { id = 218, count = 1 }, [2] = { id = 213, count = 5 } }
V.ScanBags()
local rodRow, dustRow
for _, row in ipairs(V.ScanBags().items) do
    if row.itemID == 218 then rodRow = row elseif row.itemID == 213 then dustRow = row end
end
CHECK(rodRow and V.IsMaterial(rodRow) == false, "mats: a rod the Formulary names is a tool, not a mat")
CHECK(dustRow and V.IsMaterial(dustRow) == true, "mats: dust beside the rod is still a mat")
CommanderFormulary_Data = nil
CHECK(rodRow and V.IsMaterial(rodRow) == true,
    "mats: ...and with the Formulary gone that rod is only the class it says it is")

-- The Quartermaster's loadout wins over the class: a mat it says to carry stays
CommanderQuartermaster_LoadoutState = function()
    return { slots = { { slot = "MISC", name = "Dust", state = "CARRIED", entry = { id = 213 }, count = 20 } } }
end
ResetWorld()
PackMatsBag()
V.ScanBank()
V.ScanBags()
CommanderVault_Deposit(V.DepositPredicate(V.DEPOSIT_RULES.MATS), "mats deposited")
RunTicker(300)
CHECK(Carried(213) == 20, "mats: a mat the loadout says to carry is left alone", Carried(213))
CHECK(Carried(214) == 0, "mats: ...while the rest still go", Carried(214))
CommanderQuartermaster_LoadoutState = nil

BankFrame.__shown = false
V.SetBankOpen(false)

-- ===========================================================================
-- G: the window
-- ===========================================================================

io.write("G: the window\n")

ResetWorld()
V.SetBankOpen(true)
BankFrame.__shown = true
V.ScanBank()

Fire("BANKFRAME_OPENED")
FlushTimers()
local win = _G.CommanderVaultFrame
CHECK(win ~= nil and win:IsShown(), "visiting a banker opens the vault")
CHECK(BankFrame:GetAlpha() == 0, "and puts the stock bank frame away without hiding it")
CHECK(BankFrame.__points and BankFrame.__points.TOPLEFT
    and BankFrame.__points.TOPLEFT.x == -4000, "by moving it off-screen instead")

local function ShownButtons()
    local count = 0
    for index = 1, 200 do
        local button = _G["CommanderVaultItem" .. index]
        if not button then break end
        if button:IsShown() then count = count + 1 end
    end
    return count
end

CommanderVaultDB.Grouping = "SECTION"
CommanderVaultDB.ShowSlotCounts = false
V.Refresh()
CHECK(ShownButtons() == 13, "the grid draws one button per stack", ShownButtons())

CommanderVaultDB.ShowSlotCounts = true
V.Refresh()
CHECK(ShownButtons() == 44, "with free-space drawn it draws every slot the vault has", ShownButtons())

local painted = _G.CommanderVaultItem1
CHECK(painted.row ~= nil and painted.icon.__texture ~= nil, "and paints the icon on it")

CommanderVaultDB.ShowSlotCounts = false
CommanderVaultDB.SearchMode = "HIDE"
CommanderVault_Search("netherweave")
CHECK(ShownButtons() == 3, "Hide the rest leaves only the matches on the grid", ShownButtons())
CommanderVaultDB.SearchMode = "DIM"
V.Refresh()
CHECK(ShownButtons() == 13, "Dim the rest keeps the shape of the vault", ShownButtons())
local dimmed, lit = 0, 0
for index = 1, 60 do
    local button = _G["CommanderVaultItem" .. index]
    if not button then break end
    if button:IsShown() then
        if (button.__alpha or 1) < 0.5 then dimmed = dimmed + 1 else lit = lit + 1 end
    end
end
CHECK(lit == 3 and dimmed == 10, "with the matches lit and the rest faded", lit .. "/" .. dimmed)

CommanderVault_Search("")
CommanderVaultDB.Grouping = "NONE"
V.Refresh()
CHECK(ShownButtons() == 44, "One Grid draws the raw slots, empties included", ShownButtons())
CommanderVaultDB.Grouping = "SECTION"
CommanderVaultDB.ShowSlotCounts = true

CommanderVaultDB.View = "REPORT"
V.Refresh()
CHECK(win.__scripts ~= nil, "the report view renders without erroring")
CommanderVaultDB.View = "GRID"
V.Refresh()

CHECK(win.footerFS:GetText():find("items") ~= nil, "the footer reports what is in there",
    win.footerFS:GetText())

-- Closing the bank must take the last snapshot BEFORE the flag flips, or the
-- cache is overwritten with the empty reads that follow
world[-1][20] = { id = 208, count = 1 }
Fire("BANKFRAME_CLOSED")
CHECK(not V.IsBankOpen(), "the bank closes")
CHECK(BankFrame:GetAlpha() == 1, "the stock frame is put back exactly as it was")
CHECK(#V.CharRecord(false).items == 14,
    "and the closing snapshot caught the last item added", #V.CharRecord(false).items)
CHECK(not win:IsShown(), "and the vault window closes with it")

CommanderVault_Toggle(true)
CHECK(win:IsShown(), "the vault reopens on demand away from the bank")
CHECK(V.CurrentBank().cached == true, "showing the remembered snapshot")
CommanderVault_Toggle()
CHECK(not win:IsShown(), "and toggles shut again")

CommanderVault_PrintReport()
CHECK(LastPrint() ~= nil, "the chat report prints")

-- ===========================================================================
-- H: the roster
-- ===========================================================================

io.write("H: the roster\n")

ResetWorld()
V.SetBankOpen(true)
V.ScanBank()
V.SetBankOpen(false)

CommanderVaultCache.chars["Aleria|Baldwin"] = {
    name = "Baldwin", realm = "Aleria", class = "WARRIOR", level = 70,
    at = NOW - 3600, free = 20, total = 28, money = 900000,
    items = {
        { id = 207, n = 20, q = 1, b = -1, s = 1 },
        { id = 203, n = 1,  q = 4, b = -1, s = 2 },
    },
}
CommanderVaultCache.chars["Elysium|Faroth"] = {
    name = "Faroth", realm = "Elysium", class = "PRIEST", level = 61,
    at = NOW - 7200, free = 4, total = 28,
    items = { { id = 207, n = 5, q = 1, b = -1, s = 1 } },
}
V.InvalidateRoster()

local roster = V.AllRecords()
CHECK(#roster == 3, "the roster lists every remembered character", #roster)
CHECK(roster[1].isPlayer, "with the one you are playing first — a name sort buries it")
CHECK(roster[2].name == "Baldwin", "then the freshest snapshot", roster[2].name)

CommanderVaultDB.RosterCurrentRealmOnly = true
local carried, vault, others, where = V.CountsFor(207)
CHECK(carried == 7, "counts read your bags live", carried)
CHECK(vault == 19, "and your vault live — GetItemCount answers with the bank shut", vault)
CHECK(others == 20, "an alt on this realm is counted", others)
CHECK(#where == 1 and where[1].name == "Baldwin", "and named", where[1] and where[1].name)
CommanderVaultDB.RosterCurrentRealmOnly = false
local _, _, allOthers, allWhere = V.CountsFor(207)
CHECK(allOthers == 25 and #allWhere == 2, "with the realm filter off, every character counts", allOthers)
CHECK(allWhere[1].count >= allWhere[2].count, "biggest holding first")
CommanderVaultDB.RosterCurrentRealmOnly = true

local altSnap = V.RecordSnapshot(CommanderVaultCache.chars["Aleria|Baldwin"])
CHECK(#altSnap.items == 2, "an alt's vault rebuilds as model rows", #altSnap.items)
CHECK(altSnap.items[1].section == "TRADE" and altSnap.items[2].section == "EQUIPMENT",
    "classified exactly as your own would be")
CHECK(altSnap.items[1].foreign == true, "and flagged as somebody else's")
CHECK(V.MatchRow(altSnap.items[2], V.ParseQuery("q:epic")), "so the same search language reaches it")

-- The roster in the window: pick an alt, browse its vault, come back
CommanderVault_Toggle(true)
CommanderVaultDB.View = "ROSTER"
CommanderVaultDB.ShowSlotCounts = false
V.Refresh()
CHECK(win.tabRoster ~= nil, "the window carries a Roster tab")
CHECK(ShownButtons() == 0, "which puts the item grid away")

CommanderVaultDB.RosterChar = "Aleria|Baldwin"
CommanderVaultDB.View = "GRID"
V.Refresh()
CHECK(ShownButtons() == 2, "selecting an alt draws that character's vault", ShownButtons())
CHECK(win.TitleText:GetText() == "Vault — Baldwin", "and says whose it is", win.TitleText:GetText())
CHECK(not win.sortBtn:IsShown(), "an alt's vault cannot be sorted — the button is gone, not merely inert")
CHECK(not win.depositBtn:IsShown(), "nor deposited into")
CommanderVaultDB.RosterChar = nil
V.Refresh()
CHECK(win.TitleText:GetText() == "Vault", "clearing the selection comes back to your own")

-- Dropping an item on the window
ResetWorld()
V.SetBankOpen(true)
BankFrame.__shown = true
V.ScanBank()
C_Container.PickupContainerItem(0, 2)
CHECK(CursorHasItem(), "an item is on the cursor")
win.__scripts.OnReceiveDrag(win)
CHECK(not CursorHasItem(), "dropping it on the window puts it away")
CHECK(world[-1][4] ~= nil and world[-1][4].id == 208,
    "into the first free vault slot and no other", world[-1][4] and world[-1][4].id)
V.SetBankOpen(false)
BankFrame.__shown = false
C_Container.PickupContainerItem(-1, 4)
win.__scripts.OnReceiveDrag(win)
CHECK(CursorHasItem(), "away from a banker the drop is refused rather than silently eaten")
CHECK(LastPrint():find("not at a banker") ~= nil, "and says why", LastPrint())
C_Container.PickupContainerItem(-1, 4)
CommanderVault_Toggle()

-- ===========================================================================
-- I: the tooltip line
-- ===========================================================================

io.write("I: the tooltip line\n")

V.HookTooltips()
CHECK(GameTooltip.__scripts.OnTooltipSetItem ~= nil, "the counts layer hooks the game tooltip")

local function Hover(link)
    GameTooltip:SetItem("x", link)
    GameTooltip.__scripts.OnTooltipSetItem(GameTooltip)
    return GameTooltip:TooltipText()
end

CommanderVaultDB.TooltipCounts = "ALL"
local text = Hover(Link(207))
CHECK(text:find("Vault\t19") ~= nil, "hovering an item you have banked says how many", text)
CHECK(text:find("Alts\t20") ~= nil, "and how many the rest of the account is holding", text)
CHECK(text:find("Baldwin\t20") ~= nil, "naming who", text)
CHECK(text:find("Bags") == nil, "your own bags stay off the tooltip unless asked for")

CommanderVaultDB.TooltipCarried = true
GameTooltip.__scripts.OnTooltipCleared(GameTooltip)
CHECK(Hover(Link(207)):find("Bags\t7") ~= nil, "and are added when they are")
CommanderVaultDB.TooltipCarried = false

-- A single hover fires the hook more than once on this client; the lines must
-- be written exactly once
GameTooltip.__scripts.OnTooltipSetItem(GameTooltip)
GameTooltip.__scripts.OnTooltipSetItem(GameTooltip)
local repeated = select(2, GameTooltip:TooltipText():gsub("Vault\t", ""))
CHECK(repeated == 1, "a repeated hook call on the same item writes nothing twice", repeated)

GameTooltip.__scripts.OnTooltipCleared(GameTooltip)
CHECK(Hover(Link(207)):find("Vault\t19") ~= nil, "and clearing the tooltip lets the next item speak")

CommanderVaultDB.TooltipCounts = "VAULT"
GameTooltip.__scripts.OnTooltipCleared(GameTooltip)
local vaultOnly = Hover(Link(207))
CHECK(vaultOnly:find("Vault\t19") ~= nil and vaultOnly:find("Alts") == nil,
    "This vault only drops the alt lines", vaultOnly)

CommanderVaultDB.TooltipCounts = "OFF"
GameTooltip.__scripts.OnTooltipCleared(GameTooltip)
CHECK(Hover(Link(207)) == "", "Off writes nothing at all")
CommanderVaultDB.TooltipCounts = "ALL"

GameTooltip.__scripts.OnTooltipCleared(GameTooltip)
CHECK(Hover(Link(212)) == "", "an item you own none of anywhere gets no lines either")

CHECK(V.ForgetCharacter("Elysium|Faroth"), "a character can be forgotten")
CHECK(#V.AllRecords() == 2, "and drops out of the roster immediately", #V.AllRecords())

-- ===========================================================================
-- J: framing and the item tooltip
-- ===========================================================================

io.write("J: framing and the item tooltip\n")

ResetWorld()
V.SetBankOpen(true)
BankFrame.__shown = true
V.ScanBank()
CommanderVaultDB.RosterChar = nil
CommanderVaultDB.View = "GRID"
CommanderVaultDB.ShowSlotCounts = false
CommanderVault_Toggle(true)
CommanderVault_Search("")

CommanderVaultDB.FrameStyle = "BANK"
V.Refresh()
CHECK(win.bankArt ~= nil and win.bankArt:IsShown(), "Bank style draws the stock bank dressing")
CHECK(win.headerPlate:IsShown() and win.bankTitle:GetText() == "Vault",
    "with the era's carved header plate carrying the title", win.bankTitle:GetText())
CHECK(win.NineSlice.__shown == false and win.Inset.__shown == false,
    "and the newer template's own dressing steps aside")
CHECK(win.TitleText.__shown == false, "including its title, so the name is not drawn twice")
local slot = _G.CommanderVaultItem1
-- The client's OWN bank socket, not a generic slot backing: Bank-Slot-BG out
-- of Interface\\BankFrame\\Bank-Parts, at the TexCoords BankFrame.xml gives it
CHECK(slot.bg.__texture == "Interface\\BankFrame\\Bank-Parts",
    "every item sits in the stock bank's own stone socket", slot.bg.__texture)
CHECK(win.bagRack ~= nil and #(win.bagSlots or {}) == 7,
    "and the bag rack carries a socket for all seven bank bags",
    win.bagSlots and #win.bagSlots)

CommanderVaultDB.FrameStyle = "WINDOW"
V.Refresh()
CHECK(not win.bankArt:IsShown(), "Window style puts the bank art away")
CHECK(win.NineSlice.__shown == true and win.TitleText.__shown == true,
    "and hands the window back to the template")
CHECK(slot.bg.__texture ~= "Interface\\Buttons\\UI-Slot-Background",
    "with flat sockets again", slot.bg.__texture)
CommanderVaultDB.FrameStyle = "BANK"
V.Refresh()

-- The tooltip. A vault slot must fill from the slot itself, must NOT collect
-- the global counts layer's block on top of its own, and must never end up an
-- empty box when a source fails quietly.
local function HoverSlot(index)
    local button = _G["CommanderVaultItem" .. index]
    GameTooltip.__lines = {}
    button.__scripts.OnEnter(button)
    return GameTooltip:TooltipText(), button
end

local text, hovered = HoverSlot(1)
CHECK(hovered.row ~= nil, "the first slot has an item on it")
CHECK(text:find(hovered.row.name, 1, true) ~= nil, "hovering it names the item", text)
CHECK(text:find("Vault\t") == nil,
    "and the global counts block stays out of the way — the vault writes its own", text)

-- A stacked trade good is the case that read as a wall of duplicated numbers
local clothIndex
for index = 1, 60 do
    local button = _G["CommanderVaultItem" .. index]
    if not button then break end
    if button:IsShown() and button.row and button.row.itemID == 207 then clothIndex = index break end
end
CHECK(clothIndex ~= nil, "the cloth is on the grid")
text = HoverSlot(clothIndex)
local blanks = select(2, text:gsub("\n \n", ""))
CHECK(blanks <= 1, "a stacked item gets ONE separator, not a block per layer", blanks)
CHECK(select(2, text:gsub("Also ", "")) == 1, "and one 'Also' line rather than two count blocks", text)
CHECK(text:find("Vendor x") ~= nil,
    "a stack prices the whole stack, which is the part no other addon works out", text)

-- A single item must NOT get a vendor line of its own: unit price is already
-- on the tooltip from Commander_Tooltip and from every auction addon, and a
-- third identical line is what the screenshot showed
local single
for index = 1, 60 do
    local button = _G["CommanderVaultItem" .. index]
    if not button then break end
    if button:IsShown() and button.row and (button.row.count or 1) == 1
        and (button.row.sellPrice or 0) > 0 then single = index break end
end
if single then
    local singleText = HoverSlot(single)
    CHECK(singleText:find("Vendor x") == nil,
        "and a single item leaves the unit price to whoever already prints it", singleText)
end

-- A third-party addon on the same hook, exactly like the auction-price addons
-- people actually run. It appends to whatever tooltip is being built, filled
-- or not — which is what makes "did this tooltip gain lines" a worthless test.
local thirdPartyLines = 0
GameTooltip:HookScript("OnTooltipSetItem", function(self)
    thirdPartyLines = thirdPartyLines + 1
    self:AddDoubleLine("Vendor", "3s 75c")
    self:AddDoubleLine("Auction", "unknown")
end)

-- The regression itself: a client whose SetBagItem fills nothing without
-- erroring must still produce a tooltip
brokenSources.bag = true
text = HoverSlot(1)
CHECK(text ~= "" and text:find(hovered.row.name, 1, true) ~= nil,
    "a quietly-failing SetBagItem falls through to the item link", text)
brokenSources.link = true
text = HoverSlot(1)
CHECK(text:find(hovered.row.name, 1, true) ~= nil,
    "and through that to the item id", text)
brokenSources.byID = true
text = HoverSlot(1)
CHECK(text:find(hovered.row.name, 1, true) ~= nil,
    "and with every source dead it draws what the module already knows", text)
CHECK(text:find(hovered.row.subType or "?", 1, true) ~= nil,
    "including the item type, rather than a stub saying it gave up", text)
brokenSources.bag, brokenSources.link, brokenSources.byID = nil, nil, nil

-- The exact shape of the reported bug: SetBagItem fires the hook, the other
-- addon's lines land on an EMPTY tooltip, and a line count therefore says
-- "filled" while the item's own name is nowhere on it.
brokenSources.bag = true
thirdPartyLines = 0
text = HoverSlot(1)
CHECK(thirdPartyLines > 0, "the other addon did append during the failed fill", thirdPartyLines)
CHECK(text:find(hovered.row.name, 1, true) ~= nil,
    "and the item is STILL named — a foreign addon's lines are not proof of a fill", text)
CHECK(text:find("Auction") ~= nil,
    "with the other addon's lines kept, because the retry re-runs its hook", text)
brokenSources.bag = nil

-- Hovering the same item twice must not let the first hover's success make the
-- second hover's failure look like one
text = HoverSlot(1)
CHECK(text:find(hovered.row.name, 1, true) ~= nil, "a good hover still works")
brokenSources.bag, brokenSources.link, brokenSources.byID = true, true, true
text = HoverSlot(1)
CHECK(text:find("Loading") == nil and text:find(hovered.row.name, 1, true) ~= nil,
    "and a failed hover right after it is not fooled by the last one's item", text)
brokenSources.bag, brokenSources.link, brokenSources.byID = nil, nil, nil

-- The global layer must come back the moment the vault is not the one asking
GameTooltip.__scripts.OnTooltipCleared(GameTooltip)
GameTooltip.__lines = {}
GameTooltip:SetItem("x", Link(207))
GameTooltip.__scripts.OnTooltipSetItem(GameTooltip)
CHECK(GameTooltip:TooltipText():find("Vault\t") ~= nil,
    "an ordinary tooltip elsewhere in the game still gets its counts",
    GameTooltip:TooltipText())

CommanderVaultDB.ShowSlotCounts = true
CommanderVault_Toggle()
V.SetBankOpen(false)
BankFrame.__shown = false

-- ===========================================================================
-- K: sections you named yourself
-- ===========================================================================

io.write("K: sections you named yourself\n")

ResetWorld()
V.SetBankOpen(true)
BankFrame.__shown = true
V.ScanBank()
CommanderVaultDB.ItemSection = {}
CommanderVaultDB.SectionOrder = {}

CHECK(V.UserSectionOf(208) == nil, "nothing is filed by hand to begin with")
V.SetItemSection(208, "Raid Supplies")
CHECK(V.UserSectionOf(208) == "Raid Supplies", "an item can be filed under a name of your own")
CHECK(V.IsUserSection("USER:Raid Supplies"), "authored keys are told apart from built-in ones")
CHECK(V.SectionTitle("USER:Raid Supplies") == "Raid Supplies", "and read back under that name")
CHECK(V.SectionTitle("JUNK") == "Junk", "while the built-in ones still read as before")

bank = V.ScanBank()
local potion = RowFor(bank, 208)
CHECK(potion.section == "USER:Raid Supplies",
    "a scan files it where you said, not where its item class says", potion.section)
CHECK(V.SubgroupOf(potion) == nil,
    "and Detailed grouping does not then split your own section up again")

-- The override has to beat every built-in rule, greys included: it is the one
-- filing decision that came from a person
V.SetItemSection(205, "Vendor Trash")
bank = V.ScanBank()
CHECK(RowFor(bank, 205).section == "USER:Vendor Trash",
    "an override beats even the grey verdict", RowFor(bank, 205).section)

CHECK(V.SectionRank("USER:Raid Supplies") < V.SectionRank("EQUIPMENT"),
    "authored sections outrank every built-in one — they are the deliberate ones")
CHECK(V.SectionRank("USER:Raid Supplies") < V.SectionRank("USER:Vendor Trash"),
    "and keep the order they were created in")

local ordered = V.OrderedSections()
CHECK(ordered[1].title == "Raid Supplies" and ordered[2].title == "Vendor Trash",
    "the grid walks them first", ordered[1] and ordered[1].title)
CHECK(ordered[3].key == "EQUIPMENT", "then the built-in ones", ordered[3] and ordered[3].key)

local sectionQuery = V.ParseQuery("raid supplies")
CHECK(V.MatchRow(potion, sectionQuery), "and the search language reaches your own section names")

-- The window
CommanderVaultDB.View = "GRID"
CommanderVaultDB.ShowSlotCounts = false
CommanderVault_Toggle(true)
CommanderVault_Search("")
V.Refresh()
CHECK(ShownButtons() == 13, "the grid still draws every stack", ShownButtons())

-- Filing from the grid: ctrl+right-click, and plain right-click must still
-- mean "move it to the other side"
local target
for index = 1, 60 do
    local button = _G["CommanderVaultItem" .. index]
    if not button then break end
    if button:IsShown() and button.row and button.row.itemID == 207 then target = button break end
end
CHECK(target ~= nil, "the cloth is on the grid")
ctrlDown = true
target.__scripts.OnClick(target, "RightButton")
ctrlDown = false
CHECK(lastMenu ~= nil, "ctrl+right-click opens the filing menu")
CHECK(MenuEntry("Raid Supplies") ~= nil, "listing the sections you already made")
CHECK(MenuEntry("New section…") ~= nil, "and an escape hatch for a new one")
CHECK(MenuEntry("Back where it belongs") == nil,
    "with no unfile option on an item that was never filed")
MenuEntry("Raid Supplies").func()
CHECK(V.UserSectionOf(207) == "Raid Supplies", "picking one files the item")

ctrlDown = true
target.__scripts.OnClick(target, "RightButton")
ctrlDown = false
CHECK(MenuEntry("Back where it belongs") ~= nil, "a filed item can be unfiled")
MenuEntry("Back where it belongs").func()
CHECK(V.UserSectionOf(207) == nil, "and is")

local clothBefore = C_Item.GetItemCount(207)
target.__scripts.OnClick(target, "RightButton")
CHECK(C_Item.GetItemCount(207) > clothBefore,
    "plain right-click still withdraws — filing never stole the common gesture")

-- Dissolving a section files its items back rather than destroying anything
V.SetItemSection(211, "Raid Supplies")
local dissolved = V.ClearUserSection("Raid Supplies")
CHECK(dissolved == 2, "dissolving a section clears every assignment in it", dissolved)
CHECK(V.UserSectionOf(208) == nil and V.UserSectionOf(211) == nil, "for every item")
bank = V.ScanBank()
CHECK(RowFor(bank, 208).section == "CONSUMABLE",
    "and they file themselves back where the item class says",
    RowFor(bank, 208).section)
local names = V.UserSectionList()
CHECK(#names == 1 and names[1] == "Vendor Trash",
    "leaving the sections that still hold something", #names)

-- Authored data must survive Restore Defaults: it is data, not an option
Commander.UI.ResetToDefaults(CommanderVaultDB, { Columns = 14, FrameStyle = "BANK" })
CHECK(V.UserSectionOf(205) == "Vendor Trash",
    "Restore Defaults resets options and keeps the sections you authored")

V.ClearUserSection("Vendor Trash")
CommanderVault_Toggle()
V.SetBankOpen(false)
BankFrame.__shown = false
CommanderVaultDB.ShowSlotCounts = true

-- ===========================================================================
-- L: cost, and the report with nothing to say
-- ===========================================================================

io.write("L: cost, and the report with nothing to say\n")

ResetWorld()
V.SetBankOpen(true)
BankFrame.__shown = true
V.ScanBank()
CommanderVaultDB.View = "GRID"
CommanderVault_Toggle(true)
CommanderVault_Search("")
FlushTimers()

-- GET_ITEM_INFO_RECEIVED fires city-wide and constantly. An open window is not
-- reason enough to relayout: the item has to be one the grid is still waiting
-- on, or standing in a capital rebuilds the vault dozens of times a second.
local refreshes = 0
local realRefresh = V.Refresh
local function CountRefreshes()
    refreshes = 0
    V.Refresh = function(...) refreshes = refreshes + 1 return realRefresh(...) end
end
local function StopCounting()
    V.Refresh = realRefresh
    return refreshes
end

CountRefreshes()
for _ = 1, 40 do Fire("GET_ITEM_INFO_RECEIVED", 999999) end
FlushTimers()
CHECK(StopCounting() == 0, "forty items the vault is not waiting on cost nothing at all", refreshes)

-- Now make the grid genuinely wait on something
uncached[207] = true
V.ScanBank()
V.Refresh()
CountRefreshes()
Fire("GET_ITEM_INFO_RECEIVED", 999999)
FlushTimers()
CHECK(refreshes == 0, "an unrelated item is still ignored while waiting on a real one", refreshes)
uncached[207] = nil
Fire("GET_ITEM_INFO_RECEIVED", 207)
FlushTimers()
CHECK(refreshes > 0, "but the one it was waiting on wakes it", refreshes)
refreshes = 0
Fire("GET_ITEM_INFO_RECEIVED", 207)
FlushTimers()
CHECK(StopCounting() == 0, "and it is not waited on a second time", refreshes)

-- The junk finding has to offer the step that is actually missing: the
-- auto-seller works on your BAGS, so junk in the vault is stuck there
bags = V.ScanBags()
bank = V.ScanBank()
findings = V.BuildReport(bank, bags)
byKey = {}
for _, finding in ipairs(findings) do byKey[finding.key] = finding end
CHECK(byKey.JUNK and byKey.JUNK.action == "WITHDRAW_JUNK",
    "the junk finding offers to carry it out", byKey.JUNK and byKey.JUNK.action)
CHECK(byKey.JUNK and byKey.JUNK.detail:find("sells itself") ~= nil,
    "and says why that is the useful step", byKey.JUNK and byKey.JUNK.detail)

CommanderVault_Withdraw(function(item) return item.quality == 0 and not item.noValue end, "withdrew")
RunTicker(200)
CHECK(C_Item.GetItemCount(205) == 8, "withdrawing junk really carries it", C_Item.GetItemCount(205))
CHECK(C_Item.GetItemCount(210) == 0, "and leaves the quest item where it was", C_Item.GetItemCount(210))

-- A vault in good order must SAY so rather than render an empty panel
ResetWorld()
for slot = 1, 28 do world[-1][slot] = nil end
for slot = 1, 16 do world[5][slot] = nil end
for slot = 1, 16 do world[0][slot] = nil; world[1][slot] = nil end
V.ScanBank()
findings = V.BuildReport(V.bank, V.ScanBags())
CHECK(#findings == 0, "a tidy vault produces no findings at all", #findings)
CommanderVaultDB.View = "REPORT"
V.Refresh()
CHECK(V.reportEmpty == true,
    "so the report shows its good-news state rather than an empty panel")

ResetWorld()
V.ScanBank()
findings = V.BuildReport(V.bank, V.ScanBags())
V.Refresh()
CHECK(V.reportEmpty == false,
    "and takes it back the moment there is something to say")

CommanderVaultDB.View = "GRID"
CommanderVault_Toggle()
V.SetBankOpen(false)
BankFrame.__shown = false

-- ===========================================================================
-- M: the guild bank
-- ===========================================================================

io.write("M: the guild bank\n")

CommanderVaultCache.guilds = {}
V.InvalidateRoster()
CommanderVaultDB.TrackGuildBank = true

local guildKey = V.GuildKey()
CHECK(guildKey == "Aleria|guild|Praetorians", "a guild bank is keyed by realm and guild name", guildKey)
CHECK(V.GuildCountFor(207) == 0, "and holds nothing until a tab has actually been read")

-- Passive: whatever tab you open is recorded, with no query of our own
GuildBankFrame.__shown = true
currentGuildTab = 1
Fire("GUILDBANKBAGSLOTS_CHANGED")
CHECK(V.GuildCountFor(207) == 20, "opening a tab records it", V.GuildCountFor(207))
local guildRecord = V.GuildRecord(false)
CHECK(guildRecord.scannedTabs == 1, "one tab so far", guildRecord.scannedTabs)
CHECK(V.GuildCountFor(211) == 0, "and a tab you have not opened is not guessed at")

-- A tab your rank cannot see must record as unreadable, not as empty
currentGuildTab = 2
Fire("GUILDBANKBAGSLOTS_CHANGED")
CHECK(guildRecord.tabs[2].viewable == false, "a tab your rank cannot see is marked unreadable")
CHECK(guildRecord.scannedTabs == 1, "and is not counted as read", guildRecord.scannedTabs)

-- The sweep: opt-in, one tab per tick, and it puts the view back
guildQueries = {}
currentGuildTab = 1
CHECK(CommanderVault_SweepGuildBank() == true, "a full sweep can be asked for")
RunTicker(20)
CHECK(#guildQueries >= 3, "which queries every tab", #guildQueries)
CHECK(currentGuildTab == 1, "and puts the tab you were looking at back", currentGuildTab)
CHECK(V.GuildCountFor(211) == 6, "so the unopened tab is now known too", V.GuildCountFor(211))
CHECK(guildRecord.scannedTabs == 2, "two readable tabs of three", guildRecord.scannedTabs)

GuildBankFrame.__shown = false
CHECK(CommanderVault_SweepGuildBank() == false, "and a sweep without the frame open is refused")

-- Counts reach the tooltip
ResetWorld()
V.SetBankOpen(true)
V.ScanBank()
V.SetBankOpen(false)
local _, _, _, _, guildCount = V.CountsFor(207)
CHECK(guildCount == 20, "the guild bank joins the count for an item", guildCount)
CommanderVaultDB.TooltipCounts = "ALL"
GameTooltip.__scripts.OnTooltipCleared(GameTooltip)
GameTooltip.__lines = {}
GameTooltip:SetItem("x", Link(207))
GameTooltip.__scripts.OnTooltipSetItem(GameTooltip)
CHECK(GameTooltip:TooltipText():find("Guild bank\t20") ~= nil,
    "and says so on the tooltip", GameTooltip:TooltipText())

CommanderVaultDB.TrackGuildBank = false
CHECK(V.GuildCountFor(207) == 0, "turning tracking off stops it counting")
CommanderVaultDB.TrackGuildBank = true

-- A guild bank browses like any other remembered vault
local guildSnap = V.RecordSnapshot(guildRecord)
CHECK(#guildSnap.items == 3, "a guild bank rebuilds as model rows", #guildSnap.items)
CHECK(guildSnap.items[1].section ~= nil, "classified like anything else")
CHECK(V.ForgetGuild(guildKey), "and can be forgotten")
CHECK(V.GuildCountFor(207) == 0, "after which it counts nothing again")

-- ===========================================================================
-- N: acting on the wrong vault
-- ===========================================================================

io.write("N: acting on the wrong vault\n")

-- The bug this section exists for: while browsing an ALT's vault the buttons
-- carry that record's coordinates, and your own bank is very likely open --
-- you are standing at a banker looking up what the alt has. Gating the click
-- on "is the bank open" therefore moved YOUR item at those coordinates.

ResetWorld()
V.SetBankOpen(true)
BankFrame.__shown = true
V.ScanBank()
CommanderVaultCache.chars["Aleria|Baldwin"] = {
    name = "Baldwin", realm = "Aleria", class = "WARRIOR", level = 70,
    at = NOW - 3600, free = 20, total = 28,
    items = { { id = 207, n = 20, q = 1, b = -1, s = 1 },
              { id = 203, n = 1,  q = 4, b = -1, s = 3 } },
}
V.InvalidateRoster()
CommanderVaultDB.View = "GRID"
CommanderVaultDB.ShowSlotCounts = false
CommanderVaultDB.RosterChar = "Aleria|Baldwin"
CommanderVault_Toggle(true)
CommanderVault_Search("")
V.Refresh()

local function WorldFingerprint()
    local parts = {}
    for _, bag in ipairs({ -1, 5, 0, 1 }) do
        for slot = 1, (sizes[bag] or 0) do
            local entry = world[bag] and world[bag][slot]
            parts[#parts + 1] = entry and (bag .. ":" .. slot .. "=" .. entry.id .. "x" .. entry.count) or ""
        end
    end
    return table.concat(parts, "|")
end

local altButton
for index = 1, 60 do
    local button = _G["CommanderVaultItem" .. index]
    if not button then break end
    if button:IsShown() and button.row then altButton = button break end
end
CHECK(altButton ~= nil, "the alt's vault is drawn")
CHECK(altButton.row.foreign == true, "and its rows are flagged as somebody else's")
CHECK(altButton.actionable == false,
    "so the button is not actionable, even with your own bank wide open")

local before = WorldFingerprint()
altButton.__scripts.OnClick(altButton, "LeftButton")
CHECK(WorldFingerprint() == before, "left-clicking an alt's item moves nothing of yours")
altButton.__scripts.OnClick(altButton, "RightButton")
CHECK(WorldFingerprint() == before, "and right-clicking it withdraws nothing of yours")
altButton.__scripts.OnDragStart(altButton)
CHECK(WorldFingerprint() == before and not CursorHasItem(),
    "and dragging from it picks nothing up")
altButton.__scripts.OnReceiveDrag(altButton)
CHECK(WorldFingerprint() == before, "and dropping onto it puts nothing anywhere")
altButton.SplitStack(altButton, 1)
CHECK(WorldFingerprint() == before, "and splitting it splits nothing")

-- Filing is the one thing that legitimately works on somebody else's vault,
-- because it is a judgement about the item rather than about the slot
ctrlDown = true
altButton.__scripts.OnClick(altButton, "RightButton")
ctrlDown = false
CHECK(lastMenu ~= nil, "but ctrl+right-click still files it — that is about the item")

-- Back on your own live vault, everything works again
CommanderVaultDB.RosterChar = nil
V.Refresh()
local mineButton
for index = 1, 60 do
    local button = _G["CommanderVaultItem" .. index]
    if not button then break end
    if button:IsShown() and button.row then mineButton = button break end
end
CHECK(mineButton.actionable == true, "your own live vault is actionable again")
mineButton.__scripts.OnClick(mineButton, "LeftButton")
CHECK(CursorHasItem(), "and a click picks the item up")
C_Container.PickupContainerItem(mineButton.bag, mineButton.slot)

-- With the bank shut, your own vault is a picture too
V.SetBankOpen(false)
BankFrame.__shown = false
V.Refresh()
for index = 1, 60 do
    local button = _G["CommanderVaultItem" .. index]
    if not button then break end
    if button:IsShown() and button.row then
        CHECK(button.actionable == false,
            "and away from a banker your own vault is a picture as well")
        break
    end
end

-- Focus must never be stolen by a window the player did not open: with an edit
-- box focused, WASD types letters instead of moving you
local searchBox = _G.CommanderVaultSearchBox
local focusCount = 0
rawset(searchBox, "SetFocus", function() focusCount = focusCount + 1 end)
CommanderVault_Toggle()

V.SetBankOpen(true)
BankFrame.__shown = true
CommanderVaultDB.AutoFocusSearch = true
focusCount = 0
Fire("BANKFRAME_OPENED")
FlushTimers()
CHECK(focusCount == 0, "walking up to a banker never takes the keyboard", focusCount)

Fire("BANKFRAME_CLOSED")
focusCount = 0
CommanderVault_Toggle(true)
CHECK(focusCount == 1, "but opening the vault yourself does", focusCount)
CommanderVault_Toggle()
focusCount = 0
CommanderVault_FocusSearch()
CHECK(focusCount >= 1, "and so does the search keybind", focusCount)
CommanderVault_Toggle()
CommanderVaultDB.ShowSlotCounts = true

-- ===========================================================================
-- S: the global footprint
-- ===========================================================================

io.write("O: the bag rack and buying a slot\n")

-- The reported bug: seven 26px squares in a corner with a dark red plus on
-- them, which neither said what they were nor bought anything.

ResetWorld()
bankSlotsOwned, bankSlotsFull = 2, false
V.SetBankOpen(true)
BankFrame.__shown = true
V.ScanBank()
CommanderVaultDB.RosterChar = false
CommanderVaultDB.View = "GRID"
CommanderVaultDB.FrameStyle = "BANK"
CommanderVault_Toggle(true)
CommanderVault_Search("")
V.Refresh()

local rack = win.bagSlots
CHECK(rack ~= nil and #rack == 7, "there is a socket for every bank bag slot", rack and #rack)
CHECK(win.bagRack ~= nil and win.bagRack:IsShown(), "and the rack is on screen for your own vault")
CHECK(win.baseSlot ~= nil and win.baseSlot.bag == -1,
    "with a socket at its head for the vault's own slots")
win.baseSlot.__scripts.OnClick(win.baseSlot)
CHECK(win.searchBox:GetText() == "bag:-1",
    "which isolates them like any other container", win.searchBox:GetText())
CHECK(win.baseSlot.ring:IsShown(), "and rings itself while it holds the filter")
win.baseSlot.__scripts.OnClick(win.baseSlot)
CHECK(win.searchBox:GetText() == "", "and lets go on a second click")
CHECK(rack[1].purchased == true and rack[2].purchased == true,
    "the slots you own read as owned")
CHECK(rack[3].purchased == false and rack[3].isNextToBuy == true,
    "the next one to buy knows that it is next")
CHECK(rack[7].purchased == false and rack[7].isNextToBuy == false,
    "and the ones behind it do not")
CHECK(rack[3].icon.__color and rack[3].icon.__color[1] == 1
    and rack[3].icon.__color[2] < 0.5,
    "an unbought slot is tinted red, the way the stock window marks one")

CHECK(win.buyRow:IsShown(), "the purchase row is offered at a banker")
local wantGold = math.floor(GetBankSlotCost(2) / 10000)
CHECK((win.buyRow.cost:GetText() or ""):find(wantGold .. "|rg", 1, true) ~= nil,
    "and it prices the next slot", win.buyRow.cost:GetText())

-- Clicking the unbought slot has to prime BankFrame.nextSlotCost before
-- raising the client's dialog: that dialog's OnShow reads the field rather
-- than the API, and a nil there takes MoneyFrame_Update down with it.
BankFrame.nextSlotCost = nil
popupsShown = {}
rack[3].__scripts.OnClick(rack[3], "LeftButton")
CHECK(BankFrame.nextSlotCost == GetBankSlotCost(2),
    "buying primes the price the stock dialog reads", tostring(BankFrame.nextSlotCost))
CHECK(popupsShown[#popupsShown] == "CONFIRM_BUY_BANK_SLOT",
    "and raises the client's own confirmation")

-- Away from a banker there is nothing to buy from, and the click must not
-- reach the dialog
V.SetBankOpen(false)
popupsShown = {}
rack[3].__scripts.OnClick(rack[3], "LeftButton")
CHECK(#popupsShown == 0, "away from a banker the purchase does not open")
V.SetBankOpen(true)
V.Refresh()

-- Clicking a slot you own narrows the grid to that container, and clicking it
-- again lets go. It goes through the search box on purpose: bag: is already a
-- term the query language understands.
rack[1].__scripts.OnClick(rack[1], "LeftButton")
CHECK(win.searchBox:GetText() == "bag:5", "a bought slot isolates its bag in the grid",
    win.searchBox:GetText())
CHECK(rack[1].ring:IsShown(), "and the slot the grid is narrowed to wears a ring")
rack[1].__scripts.OnClick(rack[1], "LeftButton")
CHECK(win.searchBox:GetText() == "", "clicking it again lets go")

-- Every slot bought: the row is removed rather than greyed, because a disabled
-- Purchase invites the question of what would enable it
bankSlotsOwned, bankSlotsFull = 7, true
V.Refresh()
CHECK(not win.buyRow:IsShown(), "with every slot bought the purchase row is gone")
CHECK(rack[7].purchased == true, "and the last slot reads as owned")

-- An alt's vault is somebody else's bank. Offering to spend your gold on a bag
-- slot for a grid you are only looking at is the same class of mistake as
-- withdrawing from it.
bankSlotsOwned, bankSlotsFull = 2, false
CommanderVaultCache.chars["Aleria|Cadwell"] = {
    name = "Cadwell", realm = "Aleria", class = "MAGE", level = 70,
    at = NOW - 60, free = 20, total = 28,
    items = { { id = 207, n = 5, q = 1, b = -1, s = 1 } },
}
V.InvalidateRoster()
CommanderVaultDB.RosterChar = "Aleria|Cadwell"
V.Refresh()
CHECK(not win.buyRow:IsShown(), "browsing an alt's vault withdraws the offer to buy")
CHECK(not win.bagRack:IsShown(), "and puts the rack away with it")
CommanderVaultDB.RosterChar = false
V.Refresh()
CHECK(win.bagRack:IsShown(), "coming back to your own vault brings both back")

io.write("P: resizing\n")

-- Columns are read OFF the window rather than dictated to it, so that the grip
-- and the Columns slider cannot disagree about how wide the grid is.
-- Sixteen columns, not the default fourteen: the drag two columns in has to
-- land above the toolbar's floor (MIN_W, 680) or the clamp answers instead
CommanderVaultDB.ButtonSize = 37
CommanderVaultDB.Columns = 16
CommanderVaultDB.FrameW, CommanderVaultDB.FrameH = nil, nil
V.Refresh()
local defaultWidth = win:GetWidth()
CHECK(V.GridColumns() == 16,
    "an undragged window is exactly as wide as the Columns slider asks", V.GridColumns())

local narrow = V.GridColumns()
CommanderVaultDB.FrameW = defaultWidth - 2 * (37 + 11)
V.Refresh()
narrow = V.GridColumns()
CHECK(narrow == 14, "dragging it narrower drops columns", narrow)
CHECK(win:GetWidth() == defaultWidth - 96, "and the window is the width it was dragged to",
    win:GetWidth())

-- ...and the toolbar's floor holds: narrower than the buttons fit is refused
CommanderVaultDB.FrameW = 500
V.Refresh()
CHECK(win:GetWidth() == 680, "a drag below the toolbar's floor stops at the floor", win:GetWidth())

CommanderVaultDB.FrameW = 100000
V.Refresh()
CHECK(win:GetWidth() <= 1800, "and the size is clamped rather than trusted", win:GetWidth())
CommanderVaultDB.FrameH = 1
V.Refresh()
CHECK(win:GetHeight() >= 320, "at both ends and on both axes", win:GetHeight())

CommanderVaultDB.FrameW, CommanderVaultDB.FrameH = nil, nil
V.Refresh()
CHECK(win:GetWidth() == defaultWidth, "clearing the dragged size restores the slider's")

-- The grip re-anchors before it sizes, and the saved position has to carry the
-- relative point or the window comes back a screen away from where it was left
CHECK(win.grip ~= nil, "the window has a size grip")
win.grip.__scripts.OnEnter(win.grip)
CHECK(GameTooltip.__lines ~= nil or true, "whose tooltip renders without erroring")
win.grip.__scripts.OnLeave(win.grip)

io.write("Q: an empty grid says which KIND of empty\n")

-- A blank pane reads as broken. The three ways the grid can come up empty are
-- three different pieces of news and only one of them is a problem, so the
-- state is named rather than merely drawn.

ResetWorld()
CommanderVaultDB.RosterChar = false
CommanderVaultDB.View = "GRID"
CommanderVaultDB.SearchMode = "HIDE"
CommanderVaultDB.ShowSlotCounts = true
V.SetBankOpen(true)
BankFrame.__shown = true
V.ScanBank()
CommanderVault_Toggle(true)
CommanderVault_Search("")
V.Refresh()
CHECK(V.gridEmpty == nil, "a vault with things in it is not empty at all", V.gridEmpty)

CommanderVault_Search("zzzz-nothing-is-called-this")
V.Refresh()
CHECK(V.gridEmpty == "NO_MATCH", "a search that excludes everything says so",
    tostring(V.gridEmpty))
CommanderVault_Search("")

-- A vault with slots and nothing in them is good news, not a fault
ClearWorld()
V.ScanBank()
V.Refresh()
CHECK(V.gridEmpty == "EMPTY", "an empty vault reads as empty", tostring(V.gridEmpty))

-- And a character who has never stood at a banker is a third thing again
local savedChars = CommanderVaultCache.chars
CommanderVaultCache.chars = {}
V.InvalidateRoster()
V.SetBankOpen(false)
V.Refresh()
CHECK(V.gridEmpty == "UNRECORDED", "a vault nobody ever recorded says THAT instead",
    tostring(V.gridEmpty))
CommanderVaultCache.chars = savedChars
V.InvalidateRoster()
V.SetBankOpen(true)
ResetWorld()
V.ScanBank()
V.Refresh()
CHECK(V.gridEmpty == nil, "and the good state comes back")

io.write("R: an item says which container it is in\n")

-- 28 base slots plus up to seven bags is a lot of places for one stack to be,
-- and the grid deliberately does not draw the containers in order
CHECK(V.ContainerName(-1) ~= nil and V.ContainerName(-1) ~= "container -1",
    "the base container has a name of its own", V.ContainerName(-1))
CHECK(V.ContainerName(5):find("1") ~= nil,
    "and the first bank bag is called 1, not 5", V.ContainerName(5))
CHECK(V.ContainerName(11):find("7") ~= nil,
    "and the last one is called 7, not 11", V.ContainerName(11))
CHECK(V.ContainerName(0) ~= nil and V.ContainerName(1) ~= nil,
    "carried bags are named too, since the second grid draws them")

local firstItem = _G.CommanderVaultItem1
firstItem.__scripts.OnEnter(firstItem)
local named = false
for _, line in ipairs(GameTooltip.__lines or {}) do
    if type(line) == "string" and line:find("^In ") then named = true end
end
CHECK(named, "and hovering an item in the grid says where it is")

io.write("S: the global footprint\n")

local ALLOWED = {
    CommanderVault = true, CommanderVaultDB = true, CommanderVaultCache = true,
    COMMANDER_VAULT_EVENTS = true,
    CommanderVault_Toggle = true, CommanderVault_Search = true,
    CommanderVault_PrintReport = true, CommanderVault_SortBank = true,
    CommanderVault_SortBags = true, CommanderVault_Deposit = true,
    CommanderVault_Withdraw = true,
    CommanderVault_FocusSearch = true,
    CommanderVault_SweepGuildBank = true,
    SLASH_COMMANDERVAULTFIND1 = true,
    -- The two key bindings and their header, read by name out of Bindings.xml
    BINDING_HEADER_COMMANDERVAULT = true,
    BINDING_NAME_COMMANDERVAULT_TOGGLE = true,
    BINDING_NAME_COMMANDERVAULT_SEARCH = true,
    -- Set and cleared by section D's Quartermaster hand-off test
    CommanderQuartermaster_LoadoutState = true,
    -- Set and cleared by section D's Armory hand-off test
    CommanderArmory_SetItemIDs = true,
    -- Set and cleared by section F's Formulary rod test
    CommanderFormulary_Data = true,
    -- Section J's recording tooltip
    ItemRefTooltip = true,
}
-- Named frames are a deliberate part of the module's surface (UISpecialFrames
-- needs the window to have a name, and the harness reaches the item buttons by
-- theirs), so they are matched by prefix rather than listed one by one.
local FRAME_PREFIXES = {
    "CommanderVaultFrame", "CommanderVaultItem", "CommanderVaultCarried",
    "CommanderVaultScroll", "CommanderVaultReportScroll", "CommanderVaultSearchBox",
    "CommanderVaultBankBag", "CommanderVaultBaseSlots", "CommanderVaultDepositMenu",
    "CommanderVaultWithdrawMenu", "CommanderVaultSectionMenu",
    "CommanderVaultScanTooltip",
    -- Published by the SHARED settings framework on this module's behalf: the
    -- three slash aliases, the numbered dropdown widgets its panel builds, and
    -- the page's scroll frame (named because UIPanelScrollFrameTemplate finds
    -- its scrollbar by name)
    "SLASH_COMMANDERUI_VAULT", "CommanderUIDropDown", "CommanderUIScrollVault",
}
local leaks = {}
for key in pairs(_G) do
    if not GLOBALS_BEFORE[key] and not ALLOWED[key] then
        local named = false
        for _, prefix in ipairs(FRAME_PREFIXES) do
            if key:sub(1, #prefix) == prefix then named = true break end
        end
        if not named then leaks[#leaks + 1] = key end
    end
end
table.sort(leaks)
CHECK(#leaks == 0, "the module publishes nothing it did not mean to", table.concat(leaks, ", "))

for name in pairs(ALLOWED) do
    if name:find("^CommanderVault_") then
        CHECK(type(_G[name]) == "function", "the entry point " .. name .. " exists")
    end
end
CHECK(SlashCmdList.COMMANDERVAULTFIND ~= nil, "/vfind is registered")
CHECK(SlashCmdList.COMMANDERUI_VAULT ~= nil, "and so is the module's own slash command")

-- Bindings.xml is parsed by the client, not by Lua, so the harness reads it as
-- text: every binding it declares must have a BINDING_NAME the addon publishes,
-- or the key shows up in the options list with no label at all.
local bindingsPath = ADDONS .. "/Commander_Vault/Bindings.xml"
local bindingsFile = io.open(bindingsPath, "r")
CHECK(bindingsFile ~= nil, "Bindings.xml is there")
if bindingsFile then
    local xml = bindingsFile:read("*a")
    bindingsFile:close()
    -- A double hyphen INSIDE a comment body is illegal XML and the parser
    -- rejects the whole file, registering zero bindings with only a
    -- LUA_WARNING to say so. The delimiters themselves are of course fine.
    local badComment = false
    for body in xml:gmatch("<!%-%-(.-)%-%->") do
        if body:find("%-%-") then badComment = true end
    end
    CHECK(not badComment, "and carries no double hyphen inside a comment, which would void the whole file")
    local declared = 0
    for name in xml:gmatch('<Binding name="([^"]+)"') do
        declared = declared + 1
        CHECK(_G["BINDING_NAME_" .. name] ~= nil,
            "the binding " .. name .. " has a name the options panel can show")
        local body = xml:match('<Binding name="' .. name .. '"[^>]*>%s*([%w_]+)%(')
        CHECK(body and type(_G[body]) == "function",
            "and calls a function that exists", name .. " -> " .. tostring(body))
    end
    CHECK(declared == 2, "both bindings are declared", declared)
end

CHECK(#caughtErrors == 0, "nothing errored across the whole run", caughtErrors[1])

io.write(("\n%d checks, %d failures\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
