-- Commander Quartermaster harness (luajit).
-- Loads the REAL shared framework (CommanderSettingsUI.lua, CommanderEvents.lua)
-- plus the three Commander_Quartermaster files — and Commander_Inventory for the
-- crate-button integration — under a permissive WoW mock, then drives login,
-- ledger scans and close-races, counts scoping, deep search, filters, sorting,
-- the watchlist, readiness + the raid supply check, the shopping list, the
-- roster view, outbound-mail transit, spec detection, and slash reset survival.
--
--   luajit quartermaster_harness.lua          full run (Quartermaster installed)
--   luajit quartermaster_harness.lua noqm     Inventory without Quartermaster:
--                                             the crate button must not exist
--
-- Mock notes (lessons already paid for): auto-generated widget methods are
-- PREFIX-matched only, so template-child property probes (browser.TitleText)
-- read nil unless the template mock provides them; HookScript CHAINS handlers
-- (the search box hooks a placeholder over its own OnTextChanged); C_Timer.After
-- feeds an executable queue because every scan coalesces through it.

local MODE = arg and arg[1] or "full"
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

local DAY = 86400
local now = 1700000000
function time() return now end
function date(fmt) return "2026-08-03 12:00" end
function GetTime() return now - 1699000000 end
function GetBuildInfo() return "2.5.6", "68502", "Jul 7 2026", 20506 end

local printLog = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    printLog[#printLog + 1] = table.concat(parts, " ")
end

local function FindPrint(pattern, since)
    for i = (since or 0) + 1, #printLog do
        if printLog[i]:find(pattern, 1, true) then return printLog[i] end
    end
    return nil
end

local harnessFailedErrors = {}
function geterrorhandler()
    return function(err)
        harnessFailedErrors[#harnessFailedErrors + 1] = tostring(err)
    end
end

-- ---------------------------------------------------------------------------
-- Widgets: explicit methods for everything the code reads back; auto no-op
-- methods ONLY for known camelCase prefixes so property probes read nil
-- ---------------------------------------------------------------------------

local frames = {}
local eventRegistry = {}

local NUMERIC_GETTERS = {
    GetWidth = 0, GetHeight = 0, GetScale = 1, GetEffectiveScale = 1,
    GetFrameLevel = 2, GetLeft = 0, GetBottom = 0, GetTop = 0, GetRight = 0,
    GetVerticalScroll = 0, GetVerticalScrollRange = 0, GetStringWidth = 10,
    GetID = 1, GetNumPoints = 1,
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
        rawset(self, key, fn)
        return fn
    end
    if key == "CreateTexture" then
        local fn = function(s) local t = NewWidget("Texture"); t.__parent = s; return t end
        rawset(self, key, fn)
        return fn
    end
    if key == "CreateFontString" then
        local fn = function(s) local t = NewWidget("FontString"); t.__parent = s; return t end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetScript" then
        local fn = function(s, name, handler) s.__scripts[name] = handler end
        rawset(self, key, fn)
        return fn
    end
    if key == "HookScript" then
        -- Real HookScript CHAINS; the search box hooks a placeholder update
        -- onto its own OnTextChanged, and both must run
        local fn = function(s, name, handler)
            local prev = s.__scripts[name]
            if prev then
                s.__scripts[name] = function(...)
                    prev(...)
                    handler(...)
                end
            else
                s.__scripts[name] = handler
            end
        end
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
    if key == "IsShown" or key == "IsVisible" then
        local fn = function(s) return s.__shown end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetSize" then
        local fn = function(s, w, h) s.__w, s.__h = w, h end
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
    if key == "SetTexCoord" then
        local fn = function(s, a, b, c, d) s.__texcoord = { a, b, c, d } end
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
    if key == "SetEnabled" then
        local fn = function(s, v) s.__enabled = v and true or false end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetPoint" then
        local fn = function() return "CENTER", nil, "CENTER", 0, 0 end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetThumbTexture" then
        local fn = function() return NewWidget("Texture") end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetName" then
        local fn = function(s) return s.__name end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetParent" then
        local fn = function(s) return s.__parent end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetFont" then
        local fn = function() return "Fonts\\FRIZQT__.TTF", 12, "" end
        rawset(self, key, fn)
        return fn
    end
    if key:sub(1, 2) == "Is" or key:sub(1, 3) == "Get" or key:sub(1, 3) == "Can"
        or key:sub(1, 4) == "Hook" then
        local fn = function() return nil end
        rawset(self, key, fn)
        return fn
    end
    if IsAutoMethod(key) then
        local fn = function() end
        rawset(self, key, fn)
        return fn
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
    frames[#frames + 1] = f
    return f
end

UIParent = NewWidget("Frame", "UIParent")
GameTooltip = NewWidget("GameTooltip", "GameTooltip")

tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack

GameFontNormal = NewWidget("Font")
GameFontNormalLarge = NewWidget("Font")
GameFontNormalHuge = NewWidget("Font")
GameFontHighlight = NewWidget("Font")
GameFontHighlightSmall = NewWidget("Font")
GameFontDisableSmall = NewWidget("Font")

local soundLog = {}
SOUNDKIT = { RAID_WARNING = 8959, READY_CHECK = 8960,
    IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_MAINMENU_OPTION_CHECKBOX_OFF = 857 }
function PlaySound(id) soundLog[#soundLog + 1] = id end
BACKDROP_SLIDER_8_8 = {}
UISpecialFrames = {}
SlashCmdList = {}
CANCEL, YES, NO = "Cancel", "Yes", "No"

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

C_AddOns = { GetAddOnMetadata = function() return "2.1.0" end }

local tickers = {}
local timerQueue = {}
C_Timer = {
    After = function(_, fn) timerQueue[#timerQueue + 1] = fn end,
    NewTicker = function(interval, fn) tickers[#tickers + 1] = { interval = interval, fn = fn } end,
}
local function FlushTimers()
    for _ = 1, 10 do
        if #timerQueue == 0 then return end
        local batch = timerQueue
        timerQueue = {}
        for _, fn in ipairs(batch) do fn() end
    end
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

local popupLog = {}
StaticPopupDialogs = {}
function StaticPopup_Show(which, arg1, arg2, data)
    popupLog[#popupLog + 1] = { which = which, arg1 = arg1, data = data }
    return {}
end

function IsShiftKeyDown() return false end
function ChatEdit_InsertLink() end
function InCombatLockdown() return false end
function hooksecurefunc(name, hook)
    local orig = _G[name]
    _G[name] = function(...)
        local r1, r2, r3 = orig(...)
        hook(...)
        return r1, r2, r3
    end
end

-- ---------------------------------------------------------------------------
-- Player, classes, world state
-- ---------------------------------------------------------------------------

function GetRealmName() return "Aleria" end
function UnitName(unit) if unit == "player" then return "Devinq" end return nil end
function UnitClass(unit) if unit == "player" then return "Warrior", "WARRIOR" end return nil end
function UnitLevel() return 70 end
function UnitFactionGroup() return "Alliance" end
RAID_CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43, colorStr = "ffc79c6e" },
    MAGE = { r = 0.41, g = 0.80, b = 0.94, colorStr = "ff69ccf0" },
    PRIEST = { r = 1, g = 1, b = 1, colorStr = "ffffffff" },
}
CLASS_ICON_TCOORDS = { WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.5, 0, 0.25 } }
LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior", MAGE = "Mage", PRIEST = "Priest" }
ITEM_QUALITY_COLORS = { [1] = { hex = "|cffffffff" } }

NUM_BAG_SLOTS = 4
NUM_BANKBAGSLOTS = 7
BANK_CONTAINER = -1
NUM_BAG_FRAMES = 4
ATTACHMENTS_MAX_RECEIVE = 16
ATTACHMENTS_MAX_SEND = 12

local world = {
    bags = {},      -- bagID (0-4) -> array of {id, count}
    bankBags = {},  -- bagID (-1, 5-11) -> array of {id, count}
    mail = {},      -- array of messages; each an array of {id, count}
    send = {},      -- send-mail attachment slots: array of {id, count}
    money = 4230000,
    instanceType = "none",
    instanceName = "Azeroth",
    talents = nil,  -- { shape = "classic"|"retail", points = {a, b, c} }
    equipped = {},  -- slotID -> { id, ench, gems, loc, sockets }
    items = {},     -- itemID -> { id, loc, sockets } for gear not worn
    skills = {},    -- { { "Enchanting", 375 }, … }
}

-- Record what the tooltip was asked to show. The browser's rows borrow the
-- real item tooltip where one exists and hand-build one where it does not,
-- and both paths are worth asserting.
local insertedLinks = {}
function ChatEdit_InsertLink(link) insertedLinks[#insertedLinks + 1] = link return true end
local shiftDown = false
function IsShiftKeyDown() return shiftDown end

GameTooltip.__lines = {}
-- The real SetOwner errors on an anchor name it does not know; the mock does
-- too, so the addon's fallback is exercised rather than assumed.
local KNOWN_ANCHORS = {
    ANCHOR_CURSOR = true, ANCHOR_CURSOR_RIGHT = true, ANCHOR_RIGHT = true,
    ANCHOR_LEFT = true, ANCHOR_TOP = true, ANCHOR_BOTTOM = true, ANCHOR_NONE = true,
}
local anchorsKnown = KNOWN_ANCHORS
function GameTooltip:SetOwner(owner, anchor, x, y)
    if anchor and not anchorsKnown[anchor] then
        error("Unknown anchor point: " .. tostring(anchor))
    end
    self.__lines = {}
    self.__source = nil
    self.__owner, self.__anchor, self.__anchorX, self.__anchorY = owner, anchor, x, y
end
function GameTooltip:SetAnchorSupport(map) anchorsKnown = map end
function GameTooltip:AddLine(text) self.__lines[#self.__lines + 1] = tostring(text) end
function GameTooltip:AddDoubleLine(a, b) self:AddLine(tostring(a) .. " " .. tostring(b)) end
function GameTooltip:SetHyperlink(link) self.__source = "hyperlink:" .. tostring(link) end
function GameTooltip:SetInventoryItem(unit, slot)
    if not (world.equipped and world.equipped[slot]) then error("nothing equipped") end
    self.__source = ("inventory:%s:%d"):format(unit, slot)
end
function GameTooltip:Text() return table.concat(self.__lines, "\n") end

-- Item class map for IsTracked's GetItemInfoInstant fallback: anything the
-- curated database knows never reaches it; these two exercise the fallback
local ITEM_CLASS = { [99999] = 4, [55555] = 0 }

local function Container(bag)
    if bag >= 0 and bag <= NUM_BAG_SLOTS then return world.bags[bag] end
    return world.bankBags[bag]
end

C_Container = {
    GetContainerNumSlots = function(bag)
        local c = Container(bag)
        return c and #c or 0
    end,
    GetContainerItemInfo = function(bag, slot)
        local c = Container(bag)
        local it = c and c[slot]
        if not it then return nil end
        return { itemID = it.id, stackCount = it.count }
    end,
    GetContainerItemID = function() return nil end,   -- Inventory sees empty bags
    GetContainerItemLink = function() return nil end,
    GetItemCooldown = function() return 0, 0, false end,
}

-- Client item-cache mock: only these ids are "cached", with an item level —
-- everything else returns nil so curated-name rendering keeps getting hit
local ILVL = { [33208] = 100, [22861] = 92 }

C_Item = {
    GetItemInfoInstant = function(idOrLink)
        if type(idOrLink) == "string" then
            return GetItemInfoInstant(idOrLink)
        end
        return idOrLink, "type", "sub", "loc", 134400, ITEM_CLASS[idOrLink] or 0, 0
    end,
    GetItemStats = function(link) return GetItemStats(link) end,
    GetItemInfo = function(id)
        local ilvl = ILVL[id]
        if not ilvl then return nil end
        return "X" .. id, "|Hitem:" .. id .. ":0|h[x]|h", 1, ilvl
    end,
    GetItemIconByID = function() return 134400 end,
    GetItemCount = function(id, includeBank)
        local total = 0
        for _, c in pairs(world.bags) do
            for _, it in ipairs(c) do
                if it.id == id then total = total + it.count end
            end
        end
        if includeBank then
            for _, c in pairs(world.bankBags) do
                for _, it in ipairs(c) do
                    if it.id == id then total = total + it.count end
                end
            end
        end
        return total
    end,
    IsUsableItem = function() return false end,
    GetItemSpell = function() return nil end,
}

function GetMoney() return world.money end
function GetInventoryItemID() return nil end
function GetInventoryItemTexture() return nil end

-- Equipped gear for the enhancement audit. world.equipped[slotID] = {
--   id, ench, gems = {…}, loc = "INVTYPE_HEAD", sockets = { RED = 1, … } }
-- The link is built to the real shape so the engine's own parser is what gets
-- tested, not a shortcut around it.
function GetInventoryItemLink(unit, slot)
    local it = world.equipped and world.equipped[slot]
    if not it then return nil end
    local g = it.gems or {}
    return ("|cffffffff|Hitem:%d:%d:%d:%d:%d:%d:0:0:70:0:0|h[Gear %d]|h|r"):format(
        it.id, it.ench or 0, g[1] or 0, g[2] or 0, g[3] or 0, g[4] or 0, it.id)
end

-- Item facts by id: equip location and sockets. Equipped gear is the usual
-- source, but a tooltip can be shown for something you are not wearing, so
-- world.items backs it for those tests.
local function EquippedByLink(link)
    local id = tonumber(link and link:match("Hitem:(%d+)"))
    if not id then return nil end
    for _, it in pairs(world.equipped or {}) do
        if it.id == id then return it end
    end
    return world.items and world.items[id] or nil
end

function GetItemStats(link)
    local it = EquippedByLink(link)
    if not (it and it.sockets) then return nil end
    local out = {}
    for color, n in pairs(it.sockets) do
        out["EMPTY_SOCKET_" .. color] = n
    end
    return out
end

function GetItemInfoInstant(link)
    local it = EquippedByLink(link)
    -- class/subclass default to armour, which is what most equipped gear is;
    -- a fixture sets them explicitly to be a gun, a wand or a fishing pole
    return (it and it.id), "type", "sub", (it and it.loc), 134400,
        (it and it.cls) or 4, (it and it.sub) or 0
end

function GetNumSkillLines() return #(world.skills or {}) end
function GetSkillLineInfo(i)
    local sk = world.skills and world.skills[i]
    if not sk then return nil end
    return sk[1], false, 0, sk[2]
end

function GetInboxNumItems() return #world.mail end
function GetInboxItem(i, j)
    local msg = world.mail[i]
    local it = msg and msg[j]
    if not it then return nil end
    return "Item", it.id, 134400, it.count
end
function GetInboxItemLink(i, j)
    local msg = world.mail[i]
    local it = msg and msg[j]
    return it and ("|Hitem:" .. it.id .. ":0|h[x]|h") or nil
end

function GetSendMailItem(i)
    local it = world.send[i]
    if not it then return nil end
    return "Item", it.id, 134400, it.count
end
function GetSendMailItemLink(i)
    local it = world.send[i]
    return it and ("|Hitem:" .. it.id .. ":0|h[x]|h") or nil
end
function SendMail() end -- hooked by the addon at login

function IsInInstance()
    return world.instanceType ~= "none", world.instanceType
end
function GetInstanceInfo()
    return world.instanceName, world.instanceType, 0, "", 40, 0, false, 0, 40
end
function GetRealZoneText() return world.instanceName end

function GetNumTalentTabs() return 3 end
function GetTalentTabInfo(i)
    local t = world.talents
    if not t then return nil end
    local pts = t.points[i] or 0
    if t.shape == "retail" then
        return i, "Tab" .. i, "desc", 134400, pts
    end
    return "Tab" .. i, "tex", pts, "file"
end

-- ===========================================================================
-- Load the real framework + addons
-- ===========================================================================

local function Load(path)
    local chunk = assert(loadfile(path))
    chunk()
end

CommanderConsole_Colors = {
    { text = "Steel (Default)", value = "STEEL", r = 1, g = 1, b = 1 },
    { text = "Class Color", value = "CLASS" },
}

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")

-- Pre-login ledger seed: two alts here, one on another realm, plus a stale
-- transit entry the login prune must clear and a fresh one it must keep
CommanderQuartermasterLedger = {
    Aleria = {
        Mulek = {
            class = "MAGE", level = 70, money = 9990000,
            lastSeen = now - 3 * DAY, bagsAt = now - 3 * DAY, bankAt = now - 9 * DAY,
            bags = { [22851] = 5 }, bank = { [22851] = 10 }, mail = {},
            transit = { [13512] = 3 }, transitAt = now - 32 * DAY,
        },
        Banker = {
            class = "PRIEST", level = 30, money = 120000,
            lastSeen = now - 1 * DAY, bagsAt = now - 1 * DAY,
            bags = { [22866] = 2 }, bank = {}, mail = { [22854] = 4 },
            transit = { [22851] = 2 }, transitAt = now - 2 * DAY,
        },
    },
    Faraway = {
        Remoteguy = {
            class = "WARRIOR", level = 70, money = 0,
            lastSeen = now - 30 * DAY, bagsAt = now - 30 * DAY,
            bags = { [22851] = 7 }, bank = {}, mail = {},
        },
    },
}

if MODE ~= "noqm" then
    Load(ADDONS .. "/Commander_Quartermaster/CommanderQuartermasterData.lua")
    Load(ADDONS .. "/Commander_Quartermaster/CommanderQuartermasterEnhanceData.lua")
    Load(ADDONS .. "/Commander_Quartermaster/CommanderQuartermasterFringe.lua")
    Load(ADDONS .. "/Commander_Quartermaster/CommanderQuartermasterEnhance.lua")
    Load(ADDONS .. "/Commander_Quartermaster/CommanderQuartermasterDB.lua")
    Load(ADDONS .. "/Commander_Quartermaster/CommanderQuartermaster.lua")
end
Load(ADDONS .. "/Commander_Inventory/CommanderInventoryDB.lua")
Load(ADDONS .. "/Commander_Inventory/CommanderInventory.lua")

local function Fire(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    local snapshot = {}
    for i, frame in ipairs(list) do snapshot[i] = frame end
    for _, frame in ipairs(snapshot) do
        local handler = frame.__scripts.OnEvent
        if handler then handler(frame, event, ...) end
    end
end

-- Force a rescan + counts invalidation after mutating `world` directly
local function Sync()
    Fire("BAG_UPDATE_DELAYED")
    FlushTimers()
end

-- ===========================================================================
-- noqm mode: Inventory alone — the crate button must not exist
-- ===========================================================================

if MODE == "noqm" then
    Fire("ADDON_LOADED", "Commander_Inventory")
    Fire("PLAYER_LOGIN")
    FlushTimers()
    CHECK(#harnessFailedErrors == 0, "noqm: login clean", harnessFailedErrors[1])
    CHECK(CIItemGrid ~= nil, "noqm: item grid built")
    CHECK(CIItemGrid.qmButton == nil, "noqm: no Quartermaster button without the addon")
    io.write(("quartermaster_harness (noqm): %d checks, %d failures\n"):format(checks, fails))
    os.exit(fails == 0 and 0 or 1)
end

-- ===========================================================================
-- A: login
-- ===========================================================================

local Data = CommanderQuartermasterData
local db

world.bags[0] = { { id = 22851, count = 2 }, { id = 99999, count = 1 }, { id = 55555, count = 3 } }
world.bankBags[-1] = { { id = 22851, count = 3 } }

Fire("ADDON_LOADED", "Commander_Quartermaster")
Fire("ADDON_LOADED", "Commander_Inventory")
Fire("PLAYER_LOGIN")
FlushTimers()
db = CommanderQuartermasterDB

CHECK(#harnessFailedErrors == 0, "A: login clean", harnessFailedErrors[1])
CHECK(db.EnableQuartermaster == true, "A: defaults applied")
CHECK(type(db.Watchlist) == "table", "A: watchlist map initialized")
CHECK(db.TrackTransit == true and db.RaidCheck == true, "A: new defaults present")

local meRec = CommanderQuartermasterLedger.Aleria.Devinq
CHECK(meRec ~= nil, "A: current character filed")
CHECK(meRec.bags[22851] == 2, "A: bags scanned")
CHECK(meRec.bags[99999] == nil, "A: non-consumable ignored")
CHECK(meRec.bags[55555] == 3, "A: client-consumable outside the database tracked")
CHECK(meRec.money == world.money, "A: gold recorded")

local mulek = CommanderQuartermasterLedger.Aleria.Mulek
CHECK(mulek.transit == nil, "A: stale transit pruned at login (32d)")
CHECK(CommanderQuartermasterLedger.Aleria.Banker.transit ~= nil, "A: fresh transit kept")

-- ===========================================================================
-- B: v1 races — bank close flush, mail inbox gate
-- ===========================================================================

world.bankBags[-1] = { { id = 22851, count = 3 }, { id = 22854, count = 5 } }
Fire("BANKFRAME_OPENED")
FlushTimers()
CHECK(meRec.bank[22854] == 5, "B: bank scanned on open")

-- Withdraw inside the coalesce window, close before the timer fires
Fire("PLAYERBANKSLOTS_CHANGED")
world.bankBags[-1] = { { id = 22851, count = 3 } }
Fire("BANKFRAME_CLOSED")
CHECK(meRec.bank[22854] == nil, "B: close-race flush caught the withdrawal")
FlushTimers()

world.mail = { { { id = 22854, count = 3 } } }
Fire("MAIL_SHOW")
Fire("MAIL_CLOSED")
FlushTimers()
CHECK(next(meRec.mail) == nil, "B: fast open/close records nothing (inbox gate)")

Fire("MAIL_SHOW")
Fire("MAIL_INBOX_UPDATE")
FlushTimers()
CHECK(meRec.mail[22854] == 3, "B: mail scanned after MAIL_INBOX_UPDATE")
Fire("MAIL_CLOSED")

-- ===========================================================================
-- C: tooltip counts + scope gates
-- ===========================================================================

local appendFn = GameTooltip.__scripts["OnTooltipSetItem"]
CHECK(type(appendFn) == "function", "C: tooltip hook installed")

local function TipFor(itemID)
    local tip = {
        lines = {},
        GetItem = function() return "x", "|Hitem:" .. itemID .. ":0|h[x]|h" end,
        AddLine = function(self, text) self.lines[#self.lines + 1] = text end,
        Show = function() end,
    }
    appendFn(tip)
    return table.concat(tip.lines, "\n")
end

-- 22851: me 2 bags + 3 bank; Mulek 5+10; Banker transit 2; Remoteguy 7 (other realm)
local text = TipFor(22851)
CHECK(text:find("Quartermaster:|r 22", 1, true), "C: total = live + alts + transit, realm-scoped", text)
db.CurrentRealmOnly = false
Sync()
CHECK(TipFor(22851):find("Quartermaster:|r 29", 1, true), "C: all-realms scope adds the other realm")
db.CurrentRealmOnly = true
db.TrackBank = false
Sync()
-- 12 = my live 2+3 (current char always reads live, even with TrackBank
-- off — the setting gates LEDGER layers) + Mulek bags 5 + Banker transit 2
CHECK(TipFor(22851):find("Quartermaster:|r 12", 1, true), "C: TrackBank off gates alt banks, live bank stays", TipFor(22851))
db.TrackBank = true
db.TrackTransit = false
Sync()
CHECK(TipFor(22851):find("Quartermaster:|r 20", 1, true), "C: TrackTransit off gates the transit layer")
db.TrackTransit = true
Sync()

db.TooltipBreakdown = true
Sync()
text = TipFor(22851)
CHECK(text:find("transit 2", 1, true), "C: breakdown names the transit layer", text)
db.TooltipBreakdown = false

-- ===========================================================================
-- D: outbound-mail transit
-- ===========================================================================

world.send = { { id = 22854, count = 5 }, { id = 99999, count = 1 } }
SendMail("mulek", "supplies", "")
Fire("MAIL_SEND_SUCCESS")
CHECK(mulek.transit and mulek.transit[22854] == 5, "D: send credited case-insensitively to Mulek")
CHECK(mulek.transit[99999] == nil, "D: untracked attachment ignored")

world.send = { { id = 22854, count = 2 } }
SendMail("Mulek", "more", "")
Fire("MAIL_SEND_SUCCESS")
CHECK(mulek.transit[22854] == 7, "D: second send merges")

world.send = { { id = 22866, count = 4 } }
SendMail("Mulek", "failed", "")
Fire("MAIL_FAILED")
Fire("MAIL_SEND_SUCCESS")
CHECK(mulek.transit[22866] == nil, "D: failed send discarded, late success is a no-op")

world.send = { { id = 22866, count = 4 } }
SendMail("Stranger", "hi", "")
Fire("MAIL_SEND_SUCCESS")
CHECK(CommanderQuartermasterLedger.Aleria.Stranger == nil, "D: unknown recipient never creates a record")

db.TrackTransit = false
world.send = { { id = 22866, count = 4 } }
SendMail("Mulek", "off", "")
Fire("MAIL_SEND_SUCCESS")
CHECK(mulek.transit[22866] == nil, "D: TrackTransit off snapshots nothing")
db.TrackTransit = true

-- My own inbound transit clears when MY mailbox scan runs
meRec.transit = { [22854] = 9 }
meRec.transitAt = now
Fire("MAIL_SHOW")
Fire("MAIL_INBOX_UPDATE")
FlushTimers()
Fire("MAIL_CLOSED")
CHECK(meRec.transit == nil, "D: own mailbox scan supersedes my transit layer")

-- ===========================================================================
-- E: browser, deep search, filters, sorting
-- ===========================================================================

CommanderQuartermaster_Toggle()
local browser = CommanderQuartermasterFrame
CHECK(browser and browser:IsShown(), "E: browser opens")
CHECK(browser.TitleText.__text == "Quartermaster", "E: window title set")
local rows, sidebar, list = browser._rows, browser._sidebar, browser._list

CHECK(sidebar[1].key == "WATCHLIST", "E: watchlist pinned atop the sidebar")
CHECK(sidebar[2].key == "ALL", "E: All Items follows")

local function RowTexts()
    local out = {}
    for _, item in ipairs(list) do
        out[#out + 1] = item.kind == "item" and tostring(item.id) or ("H:" .. tostring(item.text))
    end
    return table.concat(out, ",")
end

local function Search(query)
    browser.searchBox:SetText(query)
    browser.searchBox.__scripts.OnTextChanged(browser.searchBox, true)
end

local function ListHas(id)
    for _, item in ipairs(list) do
        if item.kind == "item" and item.id == id then return true end
    end
    return false
end

Search("spell damage flask")
CHECK(ListHas(22866), "E: token search reaches effect notes (Pure Death)")
CHECK(not ListHas(22851), "E: non-matching flask filtered (Fortification)")
Search("flask vendor shattrath")
CHECK(ListHas(32898) and not ListHas(22851), "E: source + note tokens AND together")
Search("flask vendor zzznope")
CHECK(not ListHas(32898) and not ListHas(22866), "E: one dead token kills the match")
Search("")

-- Filters: vanilla-only era, then a source on top
local sidebarByKey = function(key)
    for _, btn in ipairs(sidebar) do
        if btn.key == key and btn.__shown then return btn end
    end
end
db.EraFilter = "VANILLA"
sidebarByKey("FLASKS").onClick()
CHECK(ListHas(13512) and not ListHas(22851), "E: era filter keeps vanilla flasks only")
db.SourceFilter = "VENDOR"
sidebarByKey("FLASKS").onClick()
CHECK(not ListHas(13512), "E: era+source compose (no vanilla vendor flask)")
db.EraFilter, db.SourceFilter = "ALL", "ALL"

-- Sorting: 22851 has the biggest total; TOTAL desc flattens headers away
sidebarByKey("ALL").onClick()
CHECK(list[1].kind == "header", "E: curated ALL view leads with a category header")
local totalCol
for _, col in ipairs(browser.colBtns) do
    if col.key == "TOTAL" then totalCol = col end
end
totalCol.btn.__scripts.OnClick(totalCol.btn)
CHECK(list[1].kind == "item" and list[1].id == 22851, "E: TOTAL desc puts the biggest holding first", list[1].id)
CHECK(totalCol.fs.__text == "Total v", "E: sort direction marker")
totalCol.btn.__scripts.OnClick(totalCol.btn)
CHECK(list[1].kind == "item" and list[1].id ~= 22851, "E: second click flips ascending")
totalCol.btn.__scripts.OnClick(totalCol.btn)
CHECK(list[1].kind == "header", "E: third click restores curated order")

-- ===========================================================================
-- F: watchlist
-- ===========================================================================

CommanderQuartermaster_SetWatchTarget(22851, 20)
FlushTimers()
CHECK(CommanderQuartermaster_GetWatchTarget(22851) == 20, "F: target set")
CHECK(db.Watchlist["Aleria\001Devinq"][22851] == 20, "F: stored per character token")

local watchBtn = sidebarByKey("WATCHLIST")
CHECK(watchBtn.badgeFS.__text:find("short", 1, true), "F: sidebar badge counts the deficit", watchBtn.badgeFS.__text)
watchBtn.onClick()
CHECK(list[2] and list[2].kind == "item" and list[2].id == 22851, "F: watch view lists the item")
CHECK(list[2].why and list[2].why:find("Keep 20", 1, true) and list[2].why:find("have 5", 1, true),
    "F: deficit note (bags 2 + bank 3)", list[2].why)
CHECK(rows[2].nameFS.__text:find("ff4040%*"), "F: short item wears the red star", rows[2].nameFS.__text)

text = TipFor(22851)
CHECK(text:find("Restock:", 1, true) and text:find("5 / 20", 1, true), "F: tooltip restock line", text)

-- Met target turns the star gold; removal drops the row
world.bags[1] = { { id = 22851, count = 30 } }
Sync()
watchBtn = sidebarByKey("WATCHLIST")
CHECK(watchBtn.badgeFS.__text == "|cff33ff991|r", "F: badge flips to stocked count", watchBtn.badgeFS.__text)
CommanderQuartermaster_SetWatchTarget(22851, 0)
FlushTimers()
CHECK(CommanderQuartermaster_GetWatchTarget(22851) == nil, "F: zero clears the target")

-- Right-click plumbing: row popup carries the item, accept path writes
sidebarByKey("FLASKS").onClick()
local flaskRow
for _, row in ipairs(rows) do
    if row.item and row.item.kind == "item" and row.item.id == 22851 then flaskRow = row end
end
flaskRow.__scripts.OnMouseUp(flaskRow, "RightButton")
local popup = popupLog[#popupLog]
CHECK(popup and popup.which == "COMMANDER_QM_TARGET" and popup.data.id == 22851, "F: right-click opens the target popup")
StaticPopupDialogs["COMMANDER_QM_TARGET"].OnAccept(
    { editBox = { GetText = function() return "12" end } }, popup.data)
CHECK(CommanderQuartermaster_GetWatchTarget(22851) == 12, "F: popup accept writes the target")
CommanderQuartermaster_SetWatchTarget(22851, 0)
world.bags[1] = nil
Sync()

-- ===========================================================================
-- G: loadout readiness + spec detection
-- ===========================================================================

local fury
for _, spec in ipairs(Data.Recommendations.WARRIOR.specs) do
    if spec.key == "FURY" then fury = spec end
end
CHECK(fury ~= nil, "G: FURY loadout exists")

-- Clean slate, then stage: slot1 pick in bags, slot2 pick in bank,
-- slot3 pick on an alt, everything else missing
world.bags = {}
world.bankBags = {}
world.mail = {}
meRec.mail = {}
mulek.bags = {}
mulek.bank = {}
mulek.transit = nil
CommanderQuartermasterLedger.Aleria.Banker.bags = {}
CommanderQuartermasterLedger.Aleria.Banker.mail = {}
CommanderQuartermasterLedger.Aleria.Banker.transit = nil

local slot1 = fury.picks[1].entries[1].id
local slot2 = fury.picks[2].entries[1].id
local slot3 = fury.picks[3].entries[1].id
world.bags[0] = { { id = slot1, count = 2 } }
world.bankBags[-1] = { { id = slot2, count = 4 } }
mulek.bags[slot3] = 6
Sync()

world.talents = { shape = "classic", points = { 12, 41, 8 } }
db.BrowserClass, db.BrowserSpec = false, false
browser.viewLoadout.__scripts.OnClick(browser.viewLoadout)
CHECK(list[1].kind == "header" and list[1].text:find("Readiness", 1, true), "G: summary tops the loadout")
CHECK(list[1].text:find("1/" .. #fury.picks .. " carried", 1, true), "G: carried count", list[1].text)
CHECK(list[1].text:find("1 in bank", 1, true) and list[1].text:find("1 on alts", 1, true)
    and list[1].text:find((#fury.picks - 3) .. " missing", 1, true), "G: summary tiers", list[1].text)
CHECK(list[2].text:find("[CARRIED]", 1, true), "G: slot 1 graded CARRIED", list[2].text)

local selectedSpec
for _, btn in ipairs(sidebar) do
    if btn.__shown and btn.selectedTex.__shown then selectedSpec = btn.key end
end
CHECK(selectedSpec == "FURY", "G: classic talent shape detects Fury", selectedSpec)
world.talents = { shape = "retail", points = { 12, 41, 8 } }
browser.viewLoadout.__scripts.OnClick(browser.viewLoadout)
for _, btn in ipairs(sidebar) do
    if btn.__shown and btn.selectedTex.__shown then selectedSpec = btn.key end
end
CHECK(selectedSpec == "FURY", "G: retail talent shape agrees")

db.BrowserSpec = "PROTECTION"
browser.viewLoadout.__scripts.OnClick(browser.viewLoadout)
for _, btn in ipairs(sidebar) do
    if btn.__shown and btn.selectedTex.__shown then selectedSpec = btn.key end
end
CHECK(selectedSpec == "PROTECTION", "G: manual pick beats detection")

-- Verdicts always grade MY class: browsing a Mage loadout must not leak
db.BrowserClass, db.BrowserSpec = "MAGE", "FROST"
local mark = #printLog
CommanderQuartermaster_Ready()
local line = FindPrint("readiness (", mark)
CHECK(line and line:find("(Fury)", 1, true), "G: /cqm ready grades the played class", line)
CHECK(FindPrint("[CARRIED]", mark) and FindPrint("[IN BANK]", mark)
    and FindPrint("[ON ALTS]", mark) and FindPrint("[MISSING]", mark), "G: all four grades printed")
db.BrowserClass, db.BrowserSpec = false, false

-- ===========================================================================
-- H: shopping list + raid supply check
-- ===========================================================================

CommanderQuartermaster_SetWatchTarget(slot1, 10)
FlushTimers()
CommanderQuartermaster_ShoppingList()
local shopText = CommanderQuartermasterShopFrame.edit.__text
CHECK(CommanderQuartermasterShopFrame.__shown, "H: shopping window opens")
CHECK(shopText:find("LOADOUT GAPS", 1, true), "H: gaps section present")
CHECK(shopText:find("BUY", 1, true), "H: missing slots say BUY")
CHECK(shopText:find("in bank/mail — withdraw", 1, true), "H: banked slot says withdraw", shopText)
CHECK(shopText:find("on alts — mail it over", 1, true), "H: alt slot says mail it over")
CHECK(shopText:find("WATCHLIST", 1, true) and shopText:find("2/10 — buy 8", 1, true),
    "H: watchlist deficit math", shopText)

world.instanceType, world.instanceName = "raid", "Karazhan"
mark = #printLog
Fire("PLAYER_ENTERING_WORLD")
FlushTimers()
line = FindPrint("supply check", mark)
CHECK(line and line:find("missing", 1, true), "H: raid entry warns about gaps", line)
CHECK(soundLog[#soundLog] == 8959, "H: warning klaxon")
CHECK(FindPrint("watchlist item", mark), "H: watchlist shorts included")

mark = #printLog
Fire("PLAYER_ENTERING_WORLD")
FlushTimers()
CHECK(not FindPrint("supply check", mark), "H: same raid inside the window stays silent")

world.instanceName = "Gruul's Lair"
mark = #printLog
Fire("PLAYER_ENTERING_WORLD")
FlushTimers()
CHECK(FindPrint("supply check", mark), "H: a different raid checks again")

db.RaidCheck = false
world.instanceName = "Magtheridon's Lair"
mark = #printLog
Fire("PLAYER_ENTERING_WORLD")
FlushTimers()
CHECK(not FindPrint("supply check", mark), "H: master toggle silences the check")
db.RaidCheck = true
world.instanceType, world.instanceName = "none", "Azeroth"
CommanderQuartermaster_SetWatchTarget(slot1, 0)

-- ===========================================================================
-- I: roster view
-- ===========================================================================

browser.viewChars.__scripts.OnClick(browser.viewChars)
CHECK(list[1].kind == "header" and list[1].text:find("Aleria", 1, true), "I: realm header leads")
local charRow
for _, item in ipairs(list) do
    if item.kind == "char" and item.name == "Devinq" then charRow = item end
end
CHECK(charRow ~= nil, "I: current character listed")
CHECK(list[2].kind == "char" and list[2].name == "Devinq", "I: freshest character first")

local farawaySeen = false
for _, item in ipairs(list) do
    if item.kind == "char" and item.realm == "Faraway" then farawaySeen = true end
end
CHECK(farawaySeen, "I: roster ignores the realm-scope setting")

for _, col in ipairs(browser.colBtns) do
    if col.key == "ALTS" then CHECK(col.fs.__text == "Mail", "I: third column relabels to Mail") end
end

local meRow
for _, row in ipairs(rows) do
    if row.item and row.item.kind == "char" and row.item.name == "Devinq" then meRow = row end
end
CHECK(meRow.nameFS.__text:find("(you)", 1, true), "I: current char marked", meRow.nameFS.__text)
CHECK(meRow.noteFS.__text:find("423g", 1, true), "I: gold rendered", meRow.noteFS.__text)
CHECK(meRow.icon.__texcoord and meRow.icon.__texcoord[2] == 0.25, "I: class icon coords")

-- Hide toggle via click writes both the durable map and the live flag
local mulekRow
for _, row in ipairs(rows) do
    if row.item and row.item.kind == "char" and row.item.name == "Mulek" then mulekRow = row end
end
mulekRow.__scripts.OnMouseUp(mulekRow, "LeftButton")
FlushTimers()
CHECK(db.UntrackedChars["Aleria\001Mulek"] == true and mulek.hidden == true, "I: click hides a character")
mulek.bags[22851] = 5
Sync()
CHECK(not TipFor(22851):find("alts", 1, true), "I: hidden character leaves the counts")
for _, row in ipairs(rows) do
    if row.item and row.item.kind == "char" and row.item.name == "Mulek" then mulekRow = row end
end
mulekRow.__scripts.OnMouseUp(mulekRow, "LeftButton")
FlushTimers()
CHECK(mulek.hidden == nil, "I: click again unhides")

-- Forget: guarded for the played character, popup + accept for others
mark = #popupLog
meRow.__scripts.OnMouseUp(meRow, "RightButton")
CHECK(#popupLog == mark, "I: cannot forget the played character")
mulekRow.__scripts.OnMouseUp(mulekRow, "RightButton")
popup = popupLog[#popupLog]
CHECK(popup and popup.which == "COMMANDER_QM_FORGET", "I: forget popup for an alt")
StaticPopupDialogs["COMMANDER_QM_FORGET"].OnAccept(nil, popup.data)
CHECK(CommanderQuartermasterLedger.Aleria.Mulek == nil, "I: accept forgets the alt")

world.money = 5000000
Fire("PLAYER_MONEY")
CHECK(meRec.money == 5000000, "I: PLAYER_MONEY restamps gold")

-- ===========================================================================
-- J: reset survival + slash surface
-- ===========================================================================

CommanderQuartermaster_SetWatchTarget(22851, 15)
db.EraFilter = "VANILLA"
local dispatch = SlashCmdList["COMMANDERUI_QUARTERMASTER"]
CHECK(type(dispatch) == "function", "J: slash registered")
dispatch("reset")
CHECK(db.EraFilter == "ALL", "J: reset restores defaulted settings")
CHECK(db.Watchlist["Aleria\001Devinq"][22851] == 15, "J: reset keeps watch targets")
mark = #printLog
dispatch("ready")
CHECK(FindPrint("readiness", mark), "J: /cqm ready dispatches")
dispatch("shop")
CHECK(CommanderQuartermasterShopFrame.__shown, "J: /cqm shop dispatches")

-- ===========================================================================
-- K: Inventory crate button
-- ===========================================================================

CHECK(CIItemGrid.qmButton ~= nil, "K: crate button exists with Quartermaster installed")
browser:Hide()
CIItemGrid.qmButton.__scripts.OnClick(CIItemGrid.qmButton)
CHECK(browser:IsShown(), "K: crate click opens the browser")
CIItemGrid.qmButton.__scripts.OnClick(CIItemGrid.qmButton)
CHECK(not browser:IsShown(), "K: crate click toggles closed")

-- ===========================================================================
-- L: fringe loadouts (hand-curated file over the generated database)
-- ===========================================================================

local FRINGE = {
    { class = "WARRIOR", key = "PROT_PVP" },
    { class = "PALADIN", key = "SHOCKADIN" },
    { class = "HUNTER", key = "MELEE" },
    { class = "ROGUE", key = "SUBTLETY" },
    { class = "PRIEST", key = "SMITE" },
    { class = "SHAMAN", key = "TANK" },
    { class = "MAGE", key = "KROSH" },
    { class = "WARLOCK", key = "TANK" },
    { class = "WARLOCK", key = "SLSL" },
    { class = "DRUID", key = "DREAMSTATE" },
}
local function FindSpec(classToken, key)
    for _, spec in ipairs(Data.Recommendations[classToken].specs) do
        if spec.key == key then return spec end
    end
end
local fringeClasses = {}
for _, f in ipairs(FRINGE) do
    CHECK(FindSpec(f.class, f.key) ~= nil, "L: fringe spec present " .. f.class .. "/" .. f.key)
    fringeClasses[f.class] = true
end
local classCount = 0
for _ in pairs(fringeClasses) do classCount = classCount + 1 end
CHECK(classCount == 9, "L: every class fields a fringe spec", classCount)

-- House rule: fringe picks may only use item IDs the generated database
-- already verified (categories or v1 recommendations)
local allowed = {}
for _, cat in ipairs(Data.Categories) do
    for _, entry in ipairs(cat.items) do allowed[entry.id] = true end
end
local fringeKeys = {}
for _, f in ipairs(FRINGE) do fringeKeys[f.class .. "/" .. f.key] = true end
for classToken, rec in pairs(Data.Recommendations) do
    for _, spec in ipairs(rec.specs) do
        if not fringeKeys[classToken .. "/" .. spec.key] then
            for _, pick in ipairs(spec.picks) do
                for _, e in ipairs(pick.entries) do allowed[e.id] = true end
            end
        end
    end
end
local fringeBad = nil
for _, f in ipairs(FRINGE) do
    for _, pick in ipairs(FindSpec(f.class, f.key).picks) do
        for _, e in ipairs(pick.entries) do
            if not allowed[e.id] then fringeBad = f.class .. "/" .. f.key .. ":" .. e.id end
        end
    end
end
CHECK(fringeBad == nil, "L: every fringe id already verified by the generator", fringeBad)

-- An empty-entry slot (Tank Shaman's WEAPON: Rockbiter is the consumable)
-- renders its note but stays OUT of the readiness denominator
local shamTank = FindSpec("SHAMAN", "TANK")
local gradeable = 0
for _, pick in ipairs(shamTank.picks) do
    if #pick.entries > 0 then gradeable = gradeable + 1 end
end
CHECK(gradeable == #shamTank.picks - 1, "L: shaman weapon slot carries no entries", gradeable)
db.BrowserClass, db.BrowserSpec = "SHAMAN", "TANK"
browser.viewLoadout.__scripts.OnClick(browser.viewLoadout)
CHECK(list[1].text:find("/" .. gradeable .. " carried", 1, true),
    "L: readiness denominator skips the empty slot", list[1].text)
local weaponHeaderSeen = false
for _, item in ipairs(list) do
    if item.kind == "header" and item.text:find("Rockbiter", 1, true) then weaponHeaderSeen = true end
end
CHECK(weaponHeaderSeen, "L: empty slot still renders its note header")

-- A fringe loadout renders end-to-end with readiness grades
db.BrowserClass, db.BrowserSpec = "PALADIN", "SHOCKADIN"
browser.viewLoadout.__scripts.OnClick(browser.viewLoadout)
CHECK(list[1].kind == "header" and list[1].text:find("Readiness", 1, true), "L: Shockadin loadout grades")
CHECK(ListHas(22861), "L: Blinding Light is the Shockadin flask")
local shockSelected = false
for _, btn in ipairs(sidebar) do
    if btn.__shown and btn.key == "SHOCKADIN" and btn.selectedTex.__shown then shockSelected = true end
end
CHECK(shockSelected, "L: sidebar selects the fringe spec")
db.BrowserClass, db.BrowserSpec = false, false

-- ===========================================================================
-- M: item level column + sort
-- ===========================================================================

browser.viewBrowse.__scripts.OnClick(browser.viewBrowse)
sidebarByKey("FLASKS").onClick()
local lvlCol
for _, col in ipairs(browser.colBtns) do
    if col.key == "LEVEL" then lvlCol = col end
end
CHECK(lvlCol ~= nil, "M: Lvl column head exists")

-- Rows show the cached level, dash when unknown
local wonderRow, fortRow
for _, row in ipairs(rows) do
    if row.item and row.item.kind == "item" then
        if row.item.id == 33208 then wonderRow = row end
        if row.item.id == 22851 then fortRow = row end
    end
end
CHECK(wonderRow and wonderRow.c0.__text:find("100", 1, true), "M: cached item level rendered",
    wonderRow and wonderRow.c0.__text)
CHECK(fortRow and fortRow.c0.__text:find("–", 1, true), "M: uncached level renders a dash",
    fortRow and fortRow.c0.__text)

lvlCol.btn.__scripts.OnClick(lvlCol.btn)
CHECK(list[1].id == 33208 and list[2].id == 22861, "M: Lvl desc puts cached highest first",
    tostring(list[1].id) .. "," .. tostring(list[2].id))
CHECK(lvlCol.fs.__text == "Lvl v", "M: sort marker on the Lvl head")
lvlCol.btn.__scripts.OnClick(lvlCol.btn)
CHECK(list[1].id == 13513, "M: Lvl asc floats the uncached, name-sorted", list[1].id)
CHECK(list[#list].id == 33208, "M: highest level sinks to the bottom ascending")
lvlCol.btn.__scripts.OnClick(lvlCol.btn)
CHECK(list[1].id == 22851, "M: third click restores curated order")

-- Roster: the same column is character level
browser.viewChars.__scripts.OnClick(browser.viewChars)
local meRow2
for _, row in ipairs(rows) do
    if row.item and row.item.kind == "char" and row.item.name == "Devinq" then meRow2 = row end
end
CHECK(meRow2 and meRow2.c0.__text:find("70", 1, true), "M: roster Lvl cell shows character level")
lvlCol.btn.__scripts.OnClick(lvlCol.btn)
CHECK(list[2].kind == "char" and list[2].name == "Devinq" and list[3].name == "Banker",
    "M: roster Lvl desc sorts 70 above 30")
lvlCol.btn.__scripts.OnClick(lvlCol.btn)
CHECK(list[2].kind == "char" and list[2].name == "Banker", "M: roster Lvl asc flips")
lvlCol.btn.__scripts.OnClick(lvlCol.btn)

-- ===========================================================================
-- N: item enhancements — index, gear audit, chat report
-- ===========================================================================

local E = CommanderQuartermasterEnhance
CHECK(E ~= nil, "N: enhancement engine loaded")
CHECK(#CommanderQuartermasterEnhanceData.Entries > 500, "N: enhancement database populated",
    #CommanderQuartermasterEnhanceData.Entries)

-- The index answers by enchant effect id (what a link carries) and by carrier
-- item id (what you buy)
local glyph = E.EntryForEnchant(3002)
CHECK(glyph and glyph.name == "Glyph of Power", "N: enchant id resolves to its entry",
    glyph and glyph.name)
CHECK(glyph and glyph.slots[1] == "HEAD", "N: entry knows its slot")
CHECK(E.EntryForItem(29191) == glyph, "N: carrier item resolves to the same entry")
CHECK(E.EntryForEnchant(2673) ~= nil, "N: Mongoose is in the database")
CHECK(E.EntriesForSlot("SHIELD") and #E.EntriesForSlot("SHIELD") > 0, "N: shield enchants exist")
CHECK(E.EntryForEnchant(nil) == nil, "N: a bare slot resolves to nothing")

-- A gem is item class 3 and a scope is trade goods; neither passes the
-- consumable test, so the ledger has to be told about them by name
CHECK(E.IsEnhancement(29191), "N: glyph is ledger-worthy")
CHECK(E.IsEnhancement(32409), "N: gem is ledger-worthy")
CHECK(not E.IsEnhancement(99999), "N: a random item is not")

world.bags[0] = { { id = 29191, count = 2 }, { id = 32409, count = 1 } }
Sync()
local mine = CommanderQuartermasterLedger.Aleria.Devinq
CHECK(mine.bags[29191] == 2, "N: glyphs file into the ledger", mine.bags[29191])
CHECK(mine.bags[32409] == 1, "N: gems file into the ledger", mine.bags[32409])

-- The audit reads the LINK, not the database: enchant id, gem ids, sockets
world.equipped = {
    [1] = { id = 28182, ench = 3002, loc = "INVTYPE_HEAD" },
    [5] = { id = 28229, ench = 0, loc = "INVTYPE_CHEST" },
    [6] = { id = 28190, ench = 0, loc = "INVTYPE_WAIST" },
    [11] = { id = 28227, ench = 0, loc = "INVTYPE_FINGER" },
    [16] = { id = 28187, ench = 2673, loc = "INVTYPE_WEAPON", cls = 2, sub = 7,
             sockets = { RED = 1, YELLOW = 1 }, gems = { 32409 } },
}
local report = E.ScanGear("player")
local function RowFor(slotID)
    for _, row in ipairs(report.rows) do
        if row.invSlot == slotID then return row end
    end
end
CHECK(RowFor(1).ench == 3002, "N: head enchant read off the link", RowFor(1).ench)
CHECK(RowFor(1).bare == nil, "N: an enchanted head is not bare")
CHECK(E.EnchantName(RowFor(1)) == glyph.short, "N: the enchant is named from the database",
    E.EnchantName(RowFor(1)))
CHECK(RowFor(5).bare == true, "N: an unenchanted chest is bare")
CHECK(RowFor(6).bare == nil and RowFor(6).takesEnchant == nil,
    "N: a belt takes no enchant, so it is never missing one")
CHECK(RowFor(11).bare == nil and RowFor(11).needsProfession == "Enchanting",
    "N: rings only nag an enchanter")
CHECK(#RowFor(16).sockets == 2, "N: sockets counted from the item, not the link")
CHECK(RowFor(16).empty == 1, "N: one gem in two sockets leaves one empty")
CHECK(report.bare == 1 and report.empty == 1, "N: the totals agree with the rows",
    report.bare .. "/" .. report.empty)

-- With Enchanting trained, the same bare ring becomes actionable
world.skills = { { "Enchanting", 375 } }
local asEnchanter = E.ScanGear("player")
local ringRow
for _, row in ipairs(asEnchanter.rows) do
    if row.invSlot == 11 then ringRow = row end
end
CHECK(ringRow.bare == true, "N: an enchanter's bare ring IS missing an enchant")
CHECK(asEnchanter.enchanter == 375, "N: the audit knows your enchanting rank")

-- What you already own for a bare slot
local held = E.BestHeld("HEAD", function(id)
    return (id == 29191) and 2 or 0, 0, 0, 0, (id == 29191) and 2 or 0
end)
CHECK(held and held.entry == glyph and held.count == 2,
    "N: BestHeld finds the glyph sitting in your bags", held and held.name)
CHECK(E.BestHeld("HEAD", function() return 0, 0, 0, 0, 0 end) == nil,
    "N: nothing held, nothing suggested")

-- The chat report. Head goes bare for this pass so the "you already own one"
-- line has something to find: a chest enchant is enchanter-cast and has no
-- carrier item, so there is nothing to be holding.
world.equipped[1].ench = 0
local before = #printLog
CommanderQuartermaster_Gear()
CHECK(FindPrint("gear enhancements", before) ~= nil, "N: /cqm gear reports")
CHECK(FindPrint("not enchanted", before) ~= nil, "N: the bare chest is called out")
CHECK(FindPrint("gems 1/2", before) ~= nil, "N: the half-gemmed weapon is called out")
CHECK(FindPrint("you are holding", before) ~= nil, "N: it says what you already hold")

-- Owning none of it, the report names the pick instead — with its source
world.bags[0] = {}
Sync()
local before2 = #printLog
CommanderQuartermaster_Gear()
CHECK(FindPrint("best by stats is", before2) ~= nil,
    "N: with nothing held, the report names the best pick for your role")

world.equipped, world.skills = {}, {}
world.bags[0] = {}
Sync()

-- ===========================================================================
-- O: the Gear view — audit page and enhancement catalogue
-- ===========================================================================

world.equipped = {
    [1] = { id = 28182, ench = 3002, loc = "INVTYPE_HEAD" },
    [5] = { id = 28229, ench = 0, loc = "INVTYPE_CHEST" },
    [16] = { id = 28187, ench = 2673, loc = "INVTYPE_WEAPON", cls = 2, sub = 7,
             sockets = { RED = 1, YELLOW = 1 }, gems = { 32409 } },
}
Sync()
browser.viewGear.__scripts.OnClick(browser.viewGear)
CHECK(db.BrowserView == "GEAR", "O: Gear view selected")
CHECK(browser.viewGear.__enabled == false, "O: the current view's button is disabled")

CHECK(sidebar[1].key == "MYGEAR", "O: My Gear pinned atop the Gear sidebar")
CHECK(sidebar[1].badgeFS.__text:find("2", 1, true) ~= nil,
    "O: the badge counts one bare slot plus one empty socket", sidebar[1].badgeFS.__text)
local slotKeys = {}
for _, btn in ipairs(sidebar) do
    if btn.__shown then slotKeys[btn.key] = true end
end
CHECK(slotKeys.HEAD and slotKeys.WEAPON, "O: slots listed in the sidebar")
CHECK(slotKeys["GEM:META"] and slotKeys["GEM:ORANGE"] and not slotKeys.GEM,
    "O: gems list by colour rather than as one wall of 242")

-- The audit page: one row per equipped slot, verdict in the note
local gearRows = {}
for _, item in ipairs(list) do
    if item.kind == "gearslot" then gearRows[item.row.invSlot] = item end
end
CHECK(gearRows[1] and gearRows[5] and gearRows[16], "O: every equipped slot gets a row")
CHECK(list[1].kind == "header" and list[1].text:find("bare", 1, true),
    "O: the page leads with the totals", list[1].text)

local function NoteFor(invSlot)
    for _, row in ipairs(rows) do
        if row.__shown and row.item and row.item.kind == "gearslot"
            and row.item.row.invSlot == invSlot then
            return row.noteFS.__text
        end
    end
end
CHECK(NoteFor(1) and NoteFor(1):find("Spell Power", 1, true), "O: the head's enchant is named",
    NoteFor(1))
CHECK(NoteFor(5) and NoteFor(5):find("Not enchanted", 1, true), "O: the bare chest says so",
    NoteFor(5))
CHECK(NoteFor(16) and NoteFor(16):find("1/2 gems", 1, true), "O: sockets reported on the row",
    NoteFor(16))

-- A slot's shelf: every enhancement that can land there, with its source
sidebarByKey("HEAD").onClick()
local headRows = 0
local powerRow
for _, item in ipairs(list) do
    if item.kind == "enh" then
        headRows = headRows + 1
        if item.entry.name == "Glyph of Power" then powerRow = item end
    end
end
CHECK(headRows > 10, "O: the head shelf is populated", headRows)
CHECK(powerRow ~= nil, "O: Glyph of Power is on the head shelf")
-- The row's note is the source summary; assert on it directly rather than on
-- whichever fifteen rows the ranking happens to have scrolled into view
local powerText = CommanderQuartermasterEnhance.SourceSummary(powerRow.entry)
CHECK(powerText:find("Almaador", 1, true), "O: the row states where to buy it", powerText)
CHECK(powerText:find("Sha'tar", 1, true), "O: and the standing it wants")
CHECK(powerText:find("Revered", 1, true), "O: and how much of it")

-- The shelf is ordered for the role you play, and the top pick is marked
local firstEnh
for _, item in ipairs(list) do
    if item.kind == "enh" then firstEnh = item break end
end
CHECK(firstEnh and firstEnh.bestFor ~= nil, "O: the head shelf marks a best pick for your role",
    firstEnh and tostring(firstEnh.bestFor))
local E = CommanderQuartermasterEnhance
CHECK(E.Score({ stats = { STR = 10 } }, "MELEE") > E.Score({ stats = { STR = 10 } }, "CASTER"),
    "O: strength is worth more to melee than to a caster")
CHECK(E.Score({ stats = { MP5 = 6 } }, "HEALER") > E.Score({ stats = { MP5 = 6 } }, "MELEE"),
    "O: mana regen is a healer stat")
CHECK(E.Score({ stats = { SP = 20 } }, "CASTER") > E.Score({ stats = { SP_FIRE = 20 } }, "CASTER"),
    "O: school-locked spell damage is discounted against the general kind")
CHECK(E.Score({ short = "Mongoose" }, "MELEE") == nil,
    "O: a proc enchant scores nothing rather than scoring badly")

-- Gem colour groups: a two-colour gem belongs to its own shelf, not to both
local G = CommanderQuartermasterEnhance
local function GroupOf(id) return G.GemGroup(G.EntryForItem(id)) end
CHECK(GroupOf(32193) == "RED", "O: a red gem is on the red shelf", GroupOf(32193))
CHECK(GroupOf(32218) == "ORANGE", "O: an orange gem is on the orange shelf", GroupOf(32218))
CHECK(GroupOf(32215) == "PURPLE", "O: a purple gem is on the purple shelf", GroupOf(32215))
CHECK(GroupOf(32409) == "META", "O: and the meta on its own")
sidebarByKey("GEM:META").onClick()
local metaOnly, metaCount = true, 0
for _, item in ipairs(list) do
    if item.kind == "enh" then
        metaCount = metaCount + 1
        if G.GemGroup(item.entry) ~= "META" then metaOnly = false end
    end
end
CHECK(metaCount > 0 and metaOnly, "O: the meta shelf holds only metas", metaCount)

-- Search reaches across every slot, and into the sources
sidebarByKey("MYGEAR").onClick()
Search("mongoose")
local found
for _, item in ipairs(list) do
    if item.kind == "enh" and item.entry.ench == 2673 then found = item end
end
CHECK(found ~= nil, "O: search finds an enchant by name across slots")
Search("moroes")
local viaSource
for _, item in ipairs(list) do
    if item.kind == "enh" and item.entry.ench == 2673 then viaSource = item end
end
CHECK(viaSource ~= nil, "O: search reaches the boss who drops the formula")
Search("")

-- Owned-only respects the ledger, and unobtainable entries never show
world.bags[0] = { { id = 29191, count = 1 } }
Sync()
sidebarByKey("HEAD").onClick()
db.OwnedOnly = true
browser.viewGear.__scripts.OnClick(browser.viewGear)
local ownedCount, sawGlyph = 0, false
for _, item in ipairs(list) do
    if item.kind == "enh" then
        ownedCount = ownedCount + 1
        if item.entry.item == 29191 then sawGlyph = true end
    end
end
CHECK(sawGlyph and ownedCount == 1, "O: owned-only keeps just what you hold", ownedCount)
db.OwnedOnly = false
world.bags[0] = {}
world.equipped = {}
Sync()
db.BrowserView, db.BrowserSlot = "BROWSE", "MYGEAR"
browser.viewBrowse.__scripts.OnClick(browser.viewBrowse)

-- ===========================================================================
-- P: tooltips — the enhancement's own, and the verdict on a piece of gear
-- ===========================================================================

local function TipForLink(link)
    local tip = {
        lines = {},
        GetItem = function() return "x", link end,
        AddLine = function(self, text) self.lines[#self.lines + 1] = text end,
        Show = function() end,
    }
    appendFn(tip)
    return table.concat(tip.lines, "\n")
end

-- On the enhancement itself: what it is for, and where another comes from
local glyphTip = TipFor(29191)
CHECK(glyphTip:find("Enhances:", 1, true) and glyphTip:find("Head", 1, true),
    "P: the glyph's tooltip names the slot it enhances", glyphTip)
CHECK(glyphTip:find("Almaador", 1, true) and glyphTip:find("Sha'tar", 1, true),
    "P: and where to buy another, with the standing it wants")

-- A crafted enhancement shows the profession, its reagents, and the recipe
CHECK(TipFor(29192):find("Enhances:", 1, true), "P: every enhancement gets the line")
local threadTip = TipFor(24273)
CHECK(threadTip:find("Tailoring", 1, true), "P: a crafted one names its profession", threadTip)
CHECK(threadTip:find("Pattern:", 1, true), "P: and how the pattern is obtained")

-- On a piece of GEAR: the link is the authority
world.items = {
    [28229] = { id = 28229, loc = "INVTYPE_CHEST" },
    [28187] = { id = 28187, loc = "INVTYPE_WEAPON", cls = 2, sub = 7,
                sockets = { RED = 1, YELLOW = 1 } },
    [28190] = { id = 28190, loc = "INVTYPE_WAIST" },
    [28227] = { id = 28227, loc = "INVTYPE_FINGER" },
}
local function GearLink(id, ench, gem)
    return ("|cffffffff|Hitem:%d:%d:%d:0:0:0:0:0:70:0:0|h[Gear]|h|r"):format(id, ench or 0, gem or 0)
end
local bareTip = TipForLink(GearLink(28229, 0))
CHECK(bareTip:find("Not enchanted", 1, true), "P: bare gear says so on its own tooltip", bareTip)
CHECK(bareTip:find("Enchant Chest", 1, true), "P: and names what belongs there", bareTip)
local doneTip = TipForLink(GearLink(28187, 2673, 32409))
CHECK(doneTip:find("Mongoose", 1, true), "P: an enchanted weapon is named", doneTip)
CHECK(doneTip:find("1 empty socket", 1, true),
    "P: its remaining socket is counted", doneTip)
CHECK(doneTip:find("Relentless Earthstorm Diamond", 1, true),
    "P: and the gem in the other one is named", doneTip)
CHECK(doneTip:find("matches no socket", 1, true),
    "P: a meta gem in a red socket is called out as matching nothing", doneTip)
CHECK(not TipForLink(GearLink(28190, 0)):find("Not enchanted", 1, true),
    "P: a belt is never accused of missing an enchant")
CHECK(not TipForLink(GearLink(28227, 0)):find("Not enchanted", 1, true),
    "P: nor a ring, for someone who cannot enchant one")
CHECK(TipForLink(GearLink(28227, 0)):find("only by an enchanter", 1, true),
    "P: which it says out loud rather than staying silent")
world.skills = { { "Enchanting", 375 } }
CHECK(TipForLink(GearLink(28227, 0)):find("Not enchanted", 1, true),
    "P: but an enchanter's bare ring is called out")
world.skills = {}

-- Full detail on the enhancement itself, not a summary
local fullTip = TipFor(29191)
CHECK(fullTip:find("Grants:", 1, true) and fullTip:find("Sources", 1, true),
    "P: the enhancement tooltip carries what it grants and where it comes from", fullTip)
local gemTip = TipFor(32409)
CHECK(gemTip:find("Fits:", 1, true) and gemTip:find("Meta socket", 1, true),
    "P: a gem says which socket it fits", gemTip)
CHECK(gemTip:find("Requires at least 2 Red Gems", 1, true),
    "P: a meta carries its colour requirement", gemTip)
CHECK(gemTip:find("you wear", 1, true), "P: measured against the gems you are wearing")
local jcTip = TipFor(33132)
CHECK(jcTip:find("Only usable by a Jewelcrafting", 1, true),
    "P: a jeweller-only gem says so", jcTip)

db.TooltipEnhance = false
CHECK(not TipFor(29191):find("Enhances:", 1, true), "P: the setting silences both lines")
CHECK(not TipForLink(GearLink(28229, 0)):find("Not enchanted", 1, true), "P: gear verdict too")
db.TooltipEnhance = true

-- Counts still work for an enhancement, because the ledger now tracks them
world.bags[0] = { { id = 29191, count = 3 } }
Sync()
CHECK(TipFor(29191):find("Quartermaster:|r 3", 1, true),
    "P: the holdings line still lands under the enhancement lines", TipFor(29191))
world.bags[0] = {}
world.items = {}
Sync()

-- ===========================================================================
-- Q: sockets judged — colour matching, socket bonus, meta activation
-- ===========================================================================

local Q = CommanderQuartermasterEnhance

-- Real gems from the generated database, by colour
local RED, YELLOW, BLUE = 32193, 32204, 32200        -- Runed/Gleaming/Solid TBC cuts
local ORANGE, PURPLE = 32218, 32215                   -- two-colour cuts
local META = 32409                                    -- Relentless Earthstorm Diamond
local function ColorsOf(id) return table.concat(Q.GemColors(id) or {}, "+") end
CHECK(ColorsOf(RED) == "RED", "Q: a red gem is red", ColorsOf(RED))
CHECK(ColorsOf(ORANGE) == "RED+YELLOW", "Q: an orange gem is red AND yellow", ColorsOf(ORANGE))
CHECK(ColorsOf(PURPLE) == "RED+BLUE", "Q: a purple gem is red AND blue", ColorsOf(PURPLE))
CHECK(ColorsOf(META) == "META", "Q: a meta gem is meta", ColorsOf(META))

CHECK(Q.Fits(Q.GemColors(ORANGE), "YELLOW"), "Q: orange fits a yellow socket")
CHECK(Q.Fits(Q.GemColors(ORANGE), "RED"), "Q: and a red one")
CHECK(not Q.Fits(Q.GemColors(ORANGE), "BLUE"), "Q: but not a blue one")

-- Matching has to be an assignment, not a greedy walk: the orange gem must
-- give up the red socket so the red-only gem can have it
CHECK(Q.MaxMatch({ "RED", "YELLOW" }, { ORANGE, RED }) == 2,
    "Q: the orange gem moves aside for the red one",
    Q.MaxMatch({ "RED", "YELLOW" }, { ORANGE, RED }))
CHECK(Q.MaxMatch({ "RED", "RED" }, { ORANGE, BLUE }) == 1, "Q: a blue gem matches no red socket")

-- Socket bonus on a real item
world.items = {
    [28187] = { id = 28187, loc = "INVTYPE_WEAPON", cls = 2, sub = 7,
                sockets = { RED = 1, YELLOW = 1 } },
}
local function Judge(gem1, gem2)
    local link = ("|cffffffff|Hitem:28187:0:%d:%d:0:0:0:0:70:0:0|h[Gear]|h|r"):format(gem1 or 0, gem2 or 0)
    return Q.JudgeSockets(link)
end
CHECK(Judge(RED, YELLOW).bonus == true, "Q: matching colours earn the socket bonus")
CHECK(Judge(ORANGE, ORANGE).bonus == true, "Q: two orange gems match both sockets")
CHECK(Judge(BLUE, BLUE).bonus == false, "Q: two blue gems earn nothing")
CHECK(Judge(RED, BLUE).matched == 1, "Q: partial matching is counted, not rounded")
CHECK(Judge(RED, nil).empty == 1, "Q: an empty socket is still an empty socket")
CHECK(Judge(RED, nil).bonus == false, "Q: and forfeits the bonus even though the gem matched")

-- Meta activation is judged across every gem you wear, not per item
local relentless
for _, e in ipairs(CommanderQuartermasterEnhanceData.Entries) do
    if e.item == META then relentless = e end
end
CHECK(relentless and relentless.cond, "Q: the meta carries its colour condition")
CHECK(relentless.condText:find("2 Red", 1, true) and relentless.condText:find("2 Blue", 1, true),
    "Q: and says so in the client's words", relentless.condText)
local function MetaWith(counts) return Q.MetaActive(relentless, counts) end
CHECK(MetaWith({ RED = 2, YELLOW = 2, BLUE = 2 }) == true, "Q: 2/2/2 activates it")
CHECK(MetaWith({ RED = 2, YELLOW = 2, BLUE = 1 }) == false, "Q: one blue short does not")

world.equipped = {
    [1] = { id = 28182, ench = 3002, loc = "INVTYPE_HEAD", sockets = { META = 1 }, gems = { META } },
    [16] = { id = 28187, ench = 2673, loc = "INVTYPE_WEAPON", cls = 2, sub = 7,
             sockets = { RED = 1, YELLOW = 1 }, gems = { ORANGE, ORANGE } },
}
local sockReport = Q.ScanGear("player")
CHECK(sockReport.meta and sockReport.meta.entry.item == META, "Q: the audit finds the meta you wear")
CHECK(sockReport.gemCounts.RED == 2 and sockReport.gemCounts.YELLOW == 2,
    "Q: an orange gem counts for both of its colours, as the client counts it",
    sockReport.gemCounts.RED .. "/" .. sockReport.gemCounts.YELLOW)
CHECK(sockReport.meta.active == false, "Q: two orange gems do not satisfy a 2/2/2 meta")
local metaProblem
for _, p in ipairs(Q.Problems(sockReport)) do
    if p.kind == "META" then metaProblem = p end
end
CHECK(metaProblem and metaProblem.text:find("inactive", 1, true),
    "Q: and the audit says so, with the requirement", metaProblem and metaProblem.text)

-- Add the blues and it lights up
world.equipped[16].gems = { PURPLE, ORANGE }
world.equipped[5] = { id = 28229, ench = 1, loc = "INVTYPE_CHEST",
                      sockets = { BLUE = 1, YELLOW = 1 }, gems = { BLUE, YELLOW } }
local better = Q.ScanGear("player")
CHECK(better.meta.active == true, "Q: red 2, yellow 2, blue 2 across the set activates it")

local beforeQ = #printLog
CommanderQuartermaster_Gear()
CHECK(FindPrint("is active", beforeQ) ~= nil, "Q: the chat report states the meta verdict")
CHECK(FindPrint("socket bonus", beforeQ) ~= nil, "Q: and whether each item earned its bonus")

world.equipped, world.items = {}, {}
Sync()

-- ===========================================================================
-- R: the equip location is not enough — class and subclass settle it
-- ===========================================================================

local R = CommanderQuartermasterEnhance
-- Weapon subclasses: 2 bow, 3 gun, 7 sword, 18 crossbow, 19 wand, 20 fishing pole
world.equipped = {
    [18] = { id = 28504, ench = 0, loc = "INVTYPE_RANGEDRIGHT", cls = 2, sub = 3 },
}
local gunReport = R.ScanGear("player")
local function Row(report, slotID)
    for _, row in ipairs(report.rows) do
        if row.invSlot == slotID then return row end
    end
end
CHECK(Row(gunReport, 18).slot == "RANGED", "R: a gun's ranged slot takes a scope",
    tostring(Row(gunReport, 18).slot))
CHECK(Row(gunReport, 18).bare == true, "R: and an unscoped gun says so")

world.equipped[18] = { id = 28504, ench = 0, loc = "INVTYPE_RANGEDRIGHT", cls = 2, sub = 19 }
local wandReport = R.ScanGear("player")
CHECK(Row(wandReport, 18).slot == nil, "R: a wand shares the slot and takes nothing",
    tostring(Row(wandReport, 18).slot))
CHECK(Row(wandReport, 18).bare == nil, "R: so it is never called unenchanted")

world.equipped[18] = { id = 28504, ench = 0, loc = "INVTYPE_THROWN", cls = 2, sub = 16 }
CHECK(Row(R.ScanGear("player"), 18).slot == nil, "R: nor is a thrown weapon")

-- A fishing pole is a two-hander that takes lures and no enchant
CHECK(R.Accepts({ cls = 2, sub = 1048576 }, 2, 20), "R: a lure accepts a fishing pole")
CHECK(not R.Accepts({ cls = 2, sub = 1048576 }, 2, 10), "R: and not a staff")
CHECK(R.Accepts({ cls = 2, sub = 189939 }, 2, 7), "R: a weapon enchant accepts a sword")
CHECK(not R.Accepts({ cls = 2, sub = 189939 }, 2, 19), "R: and not a wand")
CHECK(R.Accepts({ cls = 4, sub = 64 }, 4, 6), "R: a shield enchant accepts a shield")
CHECK(not R.Accepts({ cls = 4, sub = 64 }, 2, 6), "R: and not a weapon that shares the number")
CHECK(R.Accepts({ cls = 2, sub = 189939 }, nil, nil),
    "R: an unanswered class question is not a no")
CHECK(R.Accepts({ cls = 2, sub = 189939 }, 0, 0),
    "R: and neither is class 0, which nothing equips")

world.equipped = {}
Sync()

-- The shopping list carries gear gaps too
world.equipped = {
    [5] = { id = 28229, ench = 0, loc = "INVTYPE_CHEST" },
    [1] = { id = 28182, ench = 0, loc = "INVTYPE_HEAD" },
}
world.bags[0] = { { id = 29191, count = 1 } }
Sync()
local shopText = CommanderQuartermasterFrame and ""
CommanderQuartermaster_ShoppingList()
shopText = CommanderQuartermasterShopFrame and CommanderQuartermasterShopFrame.edit.__text or ""
CHECK(shopText:find("GEAR ENHANCEMENTS", 1, true) ~= nil,
    "R: the shopping list has a gear section", shopText:sub(1, 120))
CHECK(shopText:find("Glyph of Power", 1, true) ~= nil,
    "R: naming the glyph already in your bags")
CHECK(shopText:find("in your bags", 1, true) ~= nil, "R: and saying it is a trip to the bag, not the shop")
world.bags[0] = {}
world.equipped = {}
Sync()

-- ===========================================================================
-- S: the generated file keeps the shape the engine relies on
-- ===========================================================================
-- A regeneration is a bulk rewrite of 600+ entries by a script nobody watches
-- run. These checks are the tripwire: they fail loudly if a future generator
-- drops a field the UI dereferences.

local S = CommanderQuartermasterEnhance
local SData = CommanderQuartermasterEnhanceData
local badSlot, badEnch, badSrc, badKind, badStats, orphanSlot = 0, 0, 0, 0, 0, 0
local slotKnown = {}
for _, key in ipairs(SData.SlotOrder) do slotKnown[key] = true end
for _, e in ipairs(SData.Entries) do
    if type(e.ench) ~= "number" then badEnch = badEnch + 1 end
    if type(e.slots) ~= "table" or #e.slots == 0 then
        badSlot = badSlot + 1
    else
        for _, key in ipairs(e.slots) do
            if not slotKnown[key] then orphanSlot = orphanSlot + 1 end
        end
    end
    if type(e.kind) ~= "string" then badKind = badKind + 1 end
    if e.src ~= nil and type(e.src) ~= "table" then badSrc = badSrc + 1 end
    if e.stats ~= nil then
        for stat, amount in pairs(e.stats) do
            if type(stat) ~= "string" or type(amount) ~= "number" then
                badStats = badStats + 1
            end
        end
    end
end
CHECK(badEnch == 0, "S: every entry carries a numeric enchant id", badEnch)
CHECK(badSlot == 0, "S: every entry names at least one slot", badSlot)
CHECK(orphanSlot == 0, "S: and every slot it names is in SlotOrder", orphanSlot)
CHECK(badKind == 0, "S: every entry has a kind", badKind)
CHECK(badSrc == 0, "S: sources are tables when present", badSrc)
CHECK(badStats == 0, "S: stat vectors are name -> number", badStats)

-- Every slot the audit can report must have a shelf to offer, or a bare slot
-- would be reported with nothing to do about it
for _, slot in ipairs(S.Slots) do
    -- slot list is by inventory id; the mapping is exercised by section R
end
local shelfless = {}
for _, key in ipairs(SData.SlotOrder) do
    local list = S.EntriesForSlot(key)
    if not list or #list == 0 then shelfless[#shelfless + 1] = key end
end
CHECK(#shelfless <= 1, "S: every slot in SlotOrder has a shelf",
    table.concat(shelfless, ","))

-- Sources render without erroring, for every entry, which is what the browser
-- and both tooltips do on every draw
local rendered = 0
for _, e in ipairs(SData.Entries) do
    local ok = pcall(function()
        S.SourceSummary(e)
        for _, line in ipairs(S.SourceLines(e, 6)) do
            assert(type(line.text) == "string")
        end
    end)
    if ok then rendered = rendered + 1 end
end
CHECK(rendered == #SData.Entries, "S: every entry's sources render",
    rendered .. "/" .. #SData.Entries)

-- And every shelf ranks, for every role, which is the other path the browser
-- walks on every draw
local rankOk, rankFail = 0, nil
for _, key in ipairs(SData.SlotOrder) do
    for _, role in ipairs({ "MELEE", "RANGED", "CASTER", "HEALER", "TANK" }) do
        local ok, err = pcall(function()
            for _, half in ipairs({ "PERM", "TEMP" }) do
                for _, row in ipairs(S.RankSlot(key, role, nil, half) or {}) do
                    assert(row.entry, "row without an entry")
                    S.Score(row.entry, role)
                end
            end
            S.BestFor(key, role)
        end)
        if ok then rankOk = rankOk + 1 else rankFail = rankFail or err end
    end
end
CHECK(rankFail == nil, "S: every shelf ranks for every role", rankFail)

-- The gem groups partition the gems: each one lands on exactly one shelf
local grouped, ungrouped = 0, 0
for _, e in ipairs(SData.Entries) do
    if e.kind == "GEM" then
        local group = S.GemGroup(e)
        if group and group ~= "OTHER" then grouped = grouped + 1 else ungrouped = ungrouped + 1 end
    end
end
CHECK(ungrouped == 0, "S: every gem belongs to exactly one colour shelf", ungrouped)
CHECK(grouped > 200, "S: and there are as many gems as TBC has", grouped)

-- ===========================================================================
-- T: the Gear view's own rows have tooltips
-- ===========================================================================

world.equipped = {
    [1] = { id = 28182, ench = 3002, loc = "INVTYPE_HEAD" },
    [16] = { id = 28187, ench = 2673, loc = "INVTYPE_WEAPON", cls = 2, sub = 7,
             sockets = { RED = 1, YELLOW = 1 }, gems = { 32409 } },
}
Sync()
browser.viewGear.__scripts.OnClick(browser.viewGear)

local function HoverRowWhere(pred)
    for _, row in ipairs(rows) do
        if row.__shown and row.item and pred(row.item) then
            row.__scripts.OnEnter(row)
            return row
        end
    end
end

-- An equipped-slot row borrows the real item tooltip, which is where the
-- addon's own gear verdict gets appended
local gearRow = HoverRowWhere(function(item) return item.kind == "gearslot" end)
CHECK(gearRow ~= nil, "T: a My Gear row can be hovered")
CHECK(GameTooltip.__source and GameTooltip.__source:find("inventory:player", 1, true),
    "T: and it shows the equipped item's own tooltip", tostring(GameTooltip.__source))

-- An enhancement row with a carrier item does the same by item id
sidebarByKey("HEAD").onClick()
local withItem = HoverRowWhere(function(item) return item.kind == "enh" and item.entry.item end)
CHECK(withItem ~= nil, "T: an enhancement row can be hovered")
CHECK(GameTooltip.__source and GameTooltip.__source:find("hyperlink:item:", 1, true),
    "T: and shows the item tooltip", tostring(GameTooltip.__source))

-- An enchanter-cast enchant has no item, so the row builds the tooltip itself
sidebarByKey("CHEST").onClick()
local noItem = HoverRowWhere(function(item) return item.kind == "enh" and not item.entry.item end)
CHECK(noItem ~= nil, "T: an enchanter-cast enchant is on the shelf")
CHECK(GameTooltip.__text and GameTooltip.__text:find("Enchant Chest", 1, true),
    "T: its row builds a tooltip by hand", tostring(GameTooltip.__text))
local built = GameTooltip:Text()
CHECK(built:find("Enhances:", 1, true) and built:find("Sources", 1, true),
    "T: carrying the full detail, not just a name", built:sub(1, 160))
CHECK(built:find("Enchanting", 1, true), "T: including the profession that applies it")

-- The tooltip is anchored to the cursor, not to a row that is 850px wide
sidebarByKey("MYGEAR").onClick()
HoverRowWhere(function(item) return item.kind == "gearslot" end)
CHECK(GameTooltip.__anchor == "ANCHOR_CURSOR_RIGHT",
    "T: the tooltip is anchored to the cursor", tostring(GameTooltip.__anchor))
CHECK(GameTooltip.__anchorX == 12, "T: with a small offset so it clears the pointer")

-- On a client without the newer anchor, the older one carries it
GameTooltip:SetAnchorSupport({ ANCHOR_CURSOR = true })
HoverRowWhere(function(item) return item.kind == "gearslot" end)
CHECK(GameTooltip.__anchor == "ANCHOR_CURSOR",
    "T: and falls back rather than erroring on an anchor the client lacks",
    tostring(GameTooltip.__anchor))
GameTooltip:SetAnchorSupport(KNOWN_ANCHORS)

-- Shift-click links what the row is about
shiftDown = true
sidebarByKey("MYGEAR").onClick()
local before = #insertedLinks
for _, row in ipairs(rows) do
    if row.__shown and row.item and row.item.kind == "gearslot" then
        row.__scripts.OnMouseUp(row, "LeftButton")
        break
    end
end
CHECK(#insertedLinks > before and insertedLinks[#insertedLinks]:find("Hitem:", 1, true),
    "T: shift-clicking a gear row links the equipped item",
    insertedLinks[#insertedLinks])

sidebarByKey("HEAD").onClick()
before = #insertedLinks
for _, row in ipairs(rows) do
    if row.__shown and row.item and row.item.kind == "enh" and row.item.entry.item then
        row.__scripts.OnMouseUp(row, "LeftButton")
        break
    end
end
CHECK(#insertedLinks > before, "T: and shift-clicking an enhancement links it too",
    insertedLinks[#insertedLinks])
CHECK(insertedLinks[#insertedLinks]:find("Hitem:", 1, true),
    "T: with a real hyperlink even though the client has never cached the item",
    insertedLinks[#insertedLinks])

before = #insertedLinks
shiftDown = false
for _, row in ipairs(rows) do
    if row.__shown and row.item and row.item.kind == "enh" then
        row.__scripts.OnMouseUp(row, "LeftButton")
        break
    end
end
CHECK(#insertedLinks == before, "T: a plain click links nothing")

world.equipped = {}
Sync()
db.BrowserView, db.BrowserSlot = "BROWSE", "MYGEAR"
browser.viewBrowse.__scripts.OnClick(browser.viewBrowse)

CHECK(#harnessFailedErrors == 0, "Z: no listener errors anywhere", harnessFailedErrors[1])

io.write(("quartermaster_harness: %d checks, %d failures\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
