-- Commander Spoils headless harness (luajit).
--
--   /opt/homebrew/bin/luajit spoils_harness.lua
--
-- Loads the REAL shared framework (Commander_Events/CommanderSettingsUI.lua +
-- CommanderEvents.lua) and all three Commander_Spoils files under a permissive
-- WoW mock, then drives: the Blizzard-takeover suppression layer in both
-- directions, the GlobalString pattern builder against this client's literal
-- TBC strings, loot/money/currency parsing, bucket classification, the bag
-- census, the reconciler's context-flag attribution, the roll lifecycle
-- including the misclick guard and reload recovery, the interest model,
-- segment folds, and retention.
--
-- Mock notes: C_Timer.After feeds an executable queue because both the settle
-- debounce and auto-pass coalesce through it; HookScript CHAINS handlers;
-- IsEventRegistered is real, because the suppression layer's exactness
-- depends on it.

local ADDONS = "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local SPOILS = ADDONS .. "/Commander_Spoils"

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end
local function eq(a, b, label)
    CHECK(a == b, label, tostring(a) .. " ~= " .. tostring(b))
end

-- ===========================================================================
-- WoW mock
-- ===========================================================================
local now = 1700000000
function time() return now end
function date() return "2026-08-05 12:00" end
local gameTime = 1000
function GetTime() return gameTime end
function GetBuildInfo() return "2.5.6", "68502", "Jul 7 2026", 20506 end

local printLog = {}
local realPrint = print
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    printLog[#printLog + 1] = table.concat(parts, " ")
end
local function FindPrint(needle, since)
    for i = (since or 0) + 1, #printLog do
        if printLog[i]:find(needle, 1, true) then return printLog[i] end
    end
end

local errors = {}
function geterrorhandler()
    return function(err) errors[#errors + 1] = tostring(err) end
end

-- ---- widgets --------------------------------------------------------------
local eventRegistry = {}
local NewWidget

local NUMERIC = {
    GetHeight = 16, GetScale = 1, GetEffectiveScale = 1,
    GetFrameLevel = 2, GetLeft = 0, GetBottom = 0, GetTop = 0, GetRight = 0,
    GetVerticalScroll = 0, GetVerticalScrollRange = 0, GetStringWidth = 10,
    GetID = 1, GetNumPoints = 1, GetAlpha = 1,
}
local PREFIXES = { "Set", "Enable", "Disable", "Clear", "Start", "Stop",
                   "Raise", "Lower", "Lock", "Play", "Add", "Highlight",
                   "Register", "Unregister", "Show", "Hide" }

local WidgetMT = {}
WidgetMT.__index = function(self, key)
    if type(key) ~= "string" then return nil end
    local fn
    if NUMERIC[key] ~= nil then
        local value = NUMERIC[key]
        fn = function() return value end
    elseif key == "CreateTexture" or key == "CreateFontString" then
        fn = function(s) local w = NewWidget(); w.__parent = s; return w end
    elseif key == "SetScript" then
        fn = function(s, name, handler) s.__scripts[name] = handler end
    elseif key == "HookScript" then
        fn = function(s, name, handler)
            local prev = s.__scripts[name]
            s.__scripts[name] = prev and function(...) prev(...) handler(...) end or handler
        end
    elseif key == "GetScript" then
        fn = function(s, name) return s.__scripts[name] end
    elseif key == "RegisterEvent" then
        fn = function(s, event)
            s.__events[event] = true
            eventRegistry[event] = eventRegistry[event] or {}
            for _, existing in ipairs(eventRegistry[event]) do
                if existing == s then return end
            end
            table.insert(eventRegistry[event], s)
        end
    elseif key == "UnregisterEvent" then
        fn = function(s, event)
            s.__events[event] = nil
            local list = eventRegistry[event]
            if list then
                for i = #list, 1, -1 do
                    if list[i] == s then table.remove(list, i) end
                end
            end
        end
    elseif key == "IsEventRegistered" then
        fn = function(s, event) return s.__events[event] == true end
    elseif key == "UnregisterAllEvents" then
        fn = function(s)
            for event in pairs(s.__events) do s:UnregisterEvent(event) end
        end
    elseif key == "Show" then
        fn = function(s) s.__shown = true; if s.__scripts.OnShow then s.__scripts.OnShow(s) end end
    elseif key == "Hide" then
        -- The real client fires OnHide, and Spoils' loot-session teardown
        -- hangs off it. A mock that skips it hides real bugs.
        fn = function(s)
            local was = s.__shown
            s.__shown = false
            if was and s.__scripts.OnHide then s.__scripts.OnHide(s) end
        end
    elseif key == "SetShown" then
        fn = function(s, v) if v then s:Show() else s:Hide() end end
    elseif key == "IsShown" or key == "IsVisible" then
        fn = function(s) return s.__shown == true end
    elseif key == "SetWidth" then
        -- Tracked, not a no-op: the adaptive header/mode-strip layout is only
        -- testable if a width can be read back.
        fn = function(s, value) s.__w = value end
    elseif key == "GetWidth" then
        fn = function(s) return s.__w or 200 end
    elseif key == "SetSize" then
        fn = function(s, w, h) s.__w, s.__h = w, h end
    elseif key == "SetText" then
        fn = function(s, text) s.__text = text end
    elseif key == "GetText" then
        fn = function(s) return s.__text or "" end
    elseif key == "GetName" then
        fn = function(s) return s.__name end
    elseif key == "GetParent" then
        fn = function(s) return s.__parent end
    elseif key == "GetPoint" then
        fn = function() return "CENTER", nil, "CENTER", 0, 0 end
    elseif key == "GetChecked" then
        fn = function(s) return s.__checked end
    elseif key == "GetThumbTexture" then
        fn = function() return NewWidget() end
    elseif key == "GetFont" then
        fn = function() return "Fonts\\ARIALN.TTF", 11, "" end
    elseif key == "GetObjectType" then
        fn = function(s) return s.__type or "Frame" end
    else
        for _, prefix in ipairs(PREFIXES) do
            if key:sub(1, #prefix) == prefix then
                fn = function() end
                break
            end
        end
    end
    if fn then rawset(self, key, fn) end
    return fn
end

-- Every widget is tracked so the harness can drive OnUpdate. The ticker is an
-- anonymous local in the addon, and leaving it undriven meant the whole
-- dirty-repaint and visibility-reconcile path had zero coverage.
local allWidgets = {}

NewWidget = function(kind, name)
    local w = setmetatable({
        __scripts = {}, __events = {}, __type = kind, __name = name, __shown = false,
    }, WidgetMT)
    if name then _G[name] = w end
    allWidgets[#allWidgets + 1] = w
    return w
end

local function RunFrames(elapsed, steps)
    for _ = 1, (steps or 1) do
        gameTime = gameTime + elapsed
        for i = 1, #allWidgets do
            local handler = allWidgets[i].__scripts.OnUpdate
            if handler then handler(allWidgets[i], elapsed) end
        end
    end
end

-- Auto-generated widget methods are PREFIX-matched only, so a template child
-- probe reads nil unless the template mock provides it explicitly.
function CreateFrame(kind, name, parent, template)
    local w = NewWidget(kind, name)
    w.__parent = parent
    w.__template = template
    if kind == "CheckButton" or (template and template:find("CheckButton")) then
        w.Text = NewWidget("FontString")
    end
    if template and template:find("BasicFrameTemplate") then
        w.TitleText = NewWidget("FontString")
    end
    return w
end

UIParent = NewWidget("Frame", "UIParent")
UIParent.__shown = true    -- the real UIParent is visible; the loot-session
                           -- teardown guard checks it
WorldFrame = NewWidget("Frame", "WorldFrame")
GameTooltip = NewWidget("Frame", "GameTooltip")
UISpecialFrames = {}

local function Fire(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    for _, frame in ipairs({ unpack(list) }) do
        local handler = frame.__scripts.OnEvent
        if handler then handler(frame, event, ...) end
    end
end

-- ---- timers ---------------------------------------------------------------
local timerQueue = {}
C_Timer = {
    After = function(delay, fn) timerQueue[#timerQueue + 1] = { at = gameTime + delay, fn = fn } end,
    NewTicker = function() return { Cancel = function() end } end,
}
local function RunTimers(advance)
    gameTime = gameTime + (advance or 0)
    local ran = 0
    for _ = 1, 40 do
        local pending = timerQueue
        timerQueue = {}
        local deferred = {}
        for _, entry in ipairs(pending) do
            if entry.at <= gameTime then
                entry.fn()
                ran = ran + 1
            else
                deferred[#deferred + 1] = entry
            end
        end
        for _, entry in ipairs(deferred) do timerQueue[#timerQueue + 1] = entry end
        if #timerQueue == #deferred and ran == 0 then break end
        if ran > 0 and #timerQueue == 0 then break end
        ran = 0
    end
end

-- ---- game state -----------------------------------------------------------
local playerClassToken = "HUNTER"
function UnitClass(unit)
    if unit == "player" or unit == "Selune" then return "Hunter", playerClassToken end
    return "Warrior", "WARRIOR"
end
partyRoster = { "Grimbold", "Selune" }
function UnitName(unit)
    if unit == "player" then return "Testchar" end
    local index = tostring(unit):match("^party(%d+)$")
    if index then return partyRoster[tonumber(index)] end
    return "Grimbold"
end
function UnitGUID() return "Creature-0-1-2-3-18692-000000" end
function UnitIsDead() return true end
function UnitIsDeadOrGhost() return false end
function UnitIsConnected() return true end
function IsInGroup() return groupState == true end
function IsInRaid() return false end
function IsInInstance() return instanceState or false, instanceState and "party" or "none" end
function GetRealZoneText() return zoneName or "Nagrand" end
function GetZoneText() return GetRealZoneText() end
function GetNumGroupMembers() return #partyRoster + 1 end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function GetCursorPosition() return 100, 200 end
-- WoW's strsplit returns exactly the delimited fields, including trailing
-- empties. A gmatch over "([^sep]*)" yields a spurious empty between every
-- pair and silently shifted every packed roll field by one.
function strsplit(sep, str)
    local out, current = {}, ""
    for i = 1, #str do
        local ch = str:sub(i, i)
        if sep:find(ch, 1, true) then
            out[#out + 1] = current
            current = ""
        else
            current = current .. ch
        end
    end
    out[#out + 1] = current
    return unpack(out)
end
function PlaySound() end
SOUNDKIT = setmetatable({}, { __index = function() return 1 end })
MAX_RAID_MEMBERS = 40
NUM_GROUP_LOOT_FRAMES = 4
MASTER_LOOT_THREHOLD = 4
ITEM_QUALITY_COLORS = {}
for q = 0, 5 do ITEM_QUALITY_COLORS[q] = { r = 1, g = 1, b = 1, hex = "|cffffffff" } end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
function SendChatMessage() end

-- Settings framework the real CommanderSettingsUI needs
Settings = {
    RegisterCanvasLayoutCategory = function(_, name)
        return { GetID = function() return name end }
    end,
    RegisterCanvasLayoutSubcategory = function(_, _, name)
        return { GetID = function() return name end }
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
}
C_AddOns = { GetAddOnMetadata = function() return "3.0.0" end }
function GetAddOnMetadata() return "3.0.0" end
SlashCmdList = {}
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton() end
function UIDropDownMenu_Initialize() end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetText() end
function UIDropDownMenu_JustifyText() end
function UIDropDownMenu_EnableDropDown() end
function UIDropDownMenu_DisableDropDown() end
function UIDropDownMenu_SetSelectedValue() end
function UIDropDownMenu_GetSelectedValue() end
function UIDropDownMenu_Refresh() end
function ToggleDropDownMenu() end
BACKDROP_SLIDER_8_8 = {}
GameFontNormal, GameFontNormalLarge, GameFontHighlight = {}, {}, {}
GameFontHighlightSmall, GameFontDisableSmall, GameFontNormalSmall = {}, {}, {}

-- ---- item database --------------------------------------------------------
-- classID/subClassID pairs chosen to exercise the Armor/Cloth (4/1) vs
-- Tradegoods/Cloth (7/5) trap that a name-keyed classifier fails.
local ITEMS = {
    [21877] = { name = "Netherweave Cloth", q = 1, class = 7, sub = 5, sell = 300, stack = 20 },
    [21840] = { name = "Netherweave Bolt", q = 1, class = 7, sub = 5, sell = 900, stack = 20 },
    [24252] = { name = "Netherweave Robe", q = 2, class = 4, sub = 1, sell = 4000, stack = 1, equip = "INVTYPE_CHEST" },
    [23445] = { name = "Elixir of Major Agility", q = 1, class = 0, sub = 1, sell = 250, stack = 5 },
    [22452] = { name = "Primal Earth", q = 1, class = 7, sub = 10, sell = 1500, stack = 10 },
    [ 2589] = { name = "Linen Cloth", q = 1, class = 7, sub = 5, sell = 100, stack = 20 },
    [ 5637] = { name = "Large Fang", q = 0, class = 15, sub = 0, sell = 750, stack = 10 },
    [ 6522] = { name = "Deviate Fish", q = 1, class = 0, sub = 1, sell = 40, stack = 20 },
    [28429] = { name = "Girdle of Ferocity", q = 4, class = 4, sub = 4, sell = 90000, stack = 1, bind = 1, equip = "INVTYPE_WAIST" },
    [22526] = { name = "Star of Elune", q = 3, class = 3, sub = 0, sell = 25000, stack = 1 },
    [21024] = { name = "Pattern: Netherweave Robe", q = 2, class = 9, sub = 1, sell = 2000, stack = 1 },
    [   -1] = { name = "Uncached", q = nil, class = 15, sub = 0, sell = nil, stack = 1 },
}
local uncachedIDs = {}

C_Item = {
    GetItemInfoInstant = function(itemID)
        local row = ITEMS[tonumber(itemID)]
        if not row then return nil end
        return tonumber(itemID), "Type", "Sub", row.equip, 12345, row.class, row.sub
    end,
    GetItemInfo = function(itemID)
        local id = tonumber(itemID)
        local row = ITEMS[id]
        if not row or uncachedIDs[id] then return nil end
        return row.name, "|cffffffff|Hitem:" .. id .. "::::::::70:::::|h[" .. row.name .. "]|h|r",
            row.q, 100, 60, "Type", "Sub", row.stack, row.equip, 12345, row.sell,
            row.class, row.sub, row.bind
    end,
    RequestLoadItemDataByID = function() end,
    GetItemSubClassInfo = function(_, sub) return "sub" .. sub end,
    GetItemCount = function() return 0 end,
}

-- ---- containers -----------------------------------------------------------
-- bag 0 is the backpack; slot content is { itemID, count }
local bags = {
    [0] = { size = 16, slots = {} },
    [1] = { size = 16, slots = {} },
    [2] = { size = 0, slots = {} },
    [3] = { size = 0, slots = {} },
    [4] = { size = 0, slots = {} },
}
local function SetBag(bag, slot, itemID, count)
    bags[bag].slots[slot] = itemID and { itemID = itemID, count = count or 1 } or nil
end
C_Container = {
    GetContainerNumSlots = function(bag) return bags[bag] and bags[bag].size or 0 end,
    GetContainerNumFreeSlots = function(bag)
        local record = bags[bag]
        if not record then return 0 end
        local used = 0
        for _ in pairs(record.slots) do used = used + 1 end
        return record.size - used, 0
    end,
    GetContainerItemInfo = function(bag, slot)
        local record = bags[bag] and bags[bag].slots[slot]
        if not record then return nil end
        local row = ITEMS[record.itemID]
        return {
            itemID = record.itemID, stackCount = record.count,
            quality = row and row.q, itemName = row and row.name,
            hasNoValue = (row and row.sell or 0) == 0,
            hyperlink = "|Hitem:" .. record.itemID .. "|h",
        }
    end,
}
C_CurrencyInfo = { GetCoinTextureString = function(copper) return tostring(copper) .. "c" end }
C_Map = { GetBestMapForUnit = function() return 1951 end }
C_PartyInfo = { GetLootMethod = function() return lootMethod or 3 end }

-- ---- loot -----------------------------------------------------------------
local lootSlots = {}
function GetNumLootItems() return #lootSlots end
function LootSlotHasItem(slot) return lootSlots[slot] ~= nil end
function GetLootSlotInfo(slot)
    local entry = lootSlots[slot]
    if not entry then return nil end
    local row = ITEMS[entry.itemID]
    return 12345, (not entry.uncached) and row.name or nil, entry.count,
        entry.currencyID, (not entry.uncached) and row.q or nil, false
end
function GetLootSlotLink(slot)
    local entry = lootSlots[slot]
    return entry and ("|Hitem:" .. entry.itemID .. "|h") or nil
end
function GetLootSlotType(slot) return lootSlots[slot] and lootSlots[slot].slotType or 1 end
function LootSlot() end
function ConfirmLootSlot() end
local closeLootCalls = 0
function CloseLoot() closeLootCalls = closeLootCalls + 1 end
function IsFishingLoot() return false end
local sourceInfoEnabled = true
function GetLootSourceInfo(slot)
    if not sourceInfoEnabled then return nil end
    return "Creature-0-1-2-3-18692-000000", 1
end
local masterCandidates = { [3] = "Grimbold", [7] = "Selune", [11] = "Rakthar" }
function GetMasterLootCandidate(_, index) return masterCandidates[index] end
local gaveMasterLoot
function GiveMasterLoot(slot, index) gaveMasterLoot = { slot = slot, index = index } end
function IsMasterLooter() return isML == true end
function GetLootThreshold() return 2 end

local rollDB = {}
local rolledCalls = {}
function GetLootRollItemInfo(rollID)
    local row = rollDB[rollID]
    if not row then return nil end
    local item = ITEMS[row.itemID]
    return 12345, item.name, row.count or 1, item.q, row.bop, row.canNeed,
        row.canGreed, false, row.reasonNeed, row.reasonGreed
end
function GetLootRollItemLink(rollID)
    local row = rollDB[rollID]
    return row and ("|Hitem:" .. row.itemID .. "|h") or nil
end
function GetLootRollTimeLeft(rollID)
    local row = rollDB[rollID]
    return row and row.timeLeft or nil
end
function RollOnLoot(rollID, rollType) rolledCalls[#rolledCalls + 1] = { rollID, rollType } end
function ConfirmLootRoll() end
local activeRollIDs = {}
function GetActiveLootRollIDs() return activeRollIDs end

C_LootHistory = {
    GetNumItems = function() return #historyItems end,
    GetItem = function(i)
        local row = historyItems[i]
        if not row then return nil end
        return row.rollID, row.link, #row.players, row.done, row.winnerIdx, false, false
    end,
    GetPlayerInfo = function(i, p)
        local row = historyItems[i]
        local entry = row and row.players[p]
        if not entry then return nil end
        return entry.name, entry.class, entry.rollType, entry.roll, entry.winner, entry.me
    end,
}
historyItems = {}

-- ---- Blizzard frames the suppression layer touches ------------------------
local blizzLoot = NewWidget("Frame", "LootFrame")
for _, event in ipairs({ "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_SLOT_CHANGED",
                         "LOOT_CLOSED", "LOOT_READY", "OPEN_MASTER_LOOT_LIST",
                         "UPDATE_MASTER_LOOT_LIST" }) do
    blizzLoot:RegisterEvent(event)
end
for i = 1, 4 do
    local frame = NewWidget("Frame", "GroupLootFrame" .. i)
    frame:RegisterEvent("CANCEL_LOOT_ROLL")
end
NewWidget("Frame", "GroupLootContainer")
NewWidget("Frame", "MasterLooterFrame")
NewWidget("Frame", "BonusRollFrame")
local blizzHistory = NewWidget("Frame", "LootHistoryFrame")
for _, event in ipairs({ "LOOT_HISTORY_FULL_UPDATE", "LOOT_HISTORY_ROLL_CHANGED",
                         "LOOT_HISTORY_ROLL_COMPLETE", "LOOT_HISTORY_AUTO_SHOW" }) do
    blizzHistory:RegisterEvent(event)
end
for _, name in ipairs({ "MainMenuBarBackpackButton", "CharacterBag0Slot",
                        "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot" }) do
    NewWidget("Button", name):RegisterEvent("ITEM_PUSH")
end
local originalOpenNewFrame = function() end
GroupLootFrame_OpenNewFrame = originalOpenNewFrame
function StaticPopup_Hide() end

local chatFilters = {}
ChatFrameUtil = {
    AddMessageEventFilter = function(event, fn)
        chatFilters[event] = chatFilters[event] or {}
        table.insert(chatFilters[event], fn)
    end,
    RemoveMessageEventFilter = function(event, fn)
        local list = chatFilters[event] or {}
        for i = #list, 1, -1 do
            if list[i] == fn then table.remove(list, i) end
        end
    end,
}

-- ---- GlobalStrings: this build's literal enUS values -----------------------
LOOT_ITEM_SELF                  = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE         = "You receive loot: %sx%d."
LOOT_ITEM_PUSHED_SELF           = "You receive item: %s."
LOOT_ITEM_PUSHED_SELF_MULTIPLE  = "You receive item: %sx%d."
LOOT_ITEM_CREATED_SELF          = "You create: %s."
LOOT_ITEM_CREATED_SELF_MULTIPLE = "You create: %sx%d."
LOOT_ITEM                       = "%s receives loot: %s."
LOOT_ITEM_MULTIPLE              = "%s receives loot: %sx%d."
LOOT_ITEM_PUSHED                = "%s receives item: %s."
LOOT_ITEM_PUSHED_MULTIPLE       = "%s receives item: %sx%d."
CREATED_ITEM                    = "%s creates: %s."
CREATED_ITEM_MULTIPLE           = "%s creates: %sx%d."
YOU_LOOT_MONEY                  = "You loot %s"
LOOT_MONEY_SPLIT                = "Your share of the loot is %s."
CURRENCY_GAINED                 = "You receive currency: %s."
CURRENCY_GAINED_MULTIPLE        = "You receive currency: %s x%d."
GOLD_AMOUNT                     = "%d Gold"
SILVER_AMOUNT                   = "%d Silver"
COPPER_AMOUNT                   = "%d Copper"
LOOT_ROLL_ROLLED_NEED  = "|HlootHistory:%d|h[Loot]|h: Need Roll - %d for %s by %s"
LOOT_ROLL_ROLLED_GREED = "|HlootHistory:%d|h[Loot]|h: Greed Roll - %d for %s by %s"
LOOT_ROLL_WON          = "|HlootHistory:%d|h[Loot]|h: %s won: %s"
LOOT_ROLL_YOU_WON      = "|HlootHistory:%d|h[Loot]|h: You won: %s"
LOOT_ROLL_ALL_PASSED   = "|HlootHistory:%d|h[Loot]|h: Everyone passed on: %s"
LOOT_ROLL_INELIGIBLE_REASON1 = "Your class may not roll need on this item."
INVTYPE_WAIST = "Waist"
INVTYPE_CHEST = "Chest"

local function Link(itemID)
    local row = ITEMS[itemID]
    return "|cffffffff|Hitem:" .. itemID .. "::::::::70:::::|h[" .. row.name .. "]|h|r"
end

-- ===========================================================================
-- Load
-- ===========================================================================
local function Load(path)
    local chunk, err = loadfile(path)
    if not chunk then
        realPrint("LOAD ERROR " .. path .. ": " .. tostring(err))
        os.exit(1)
    end
    chunk()
end

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
Load(SPOILS .. "/CommanderSpoilsDB.lua")
Load(SPOILS .. "/CommanderSpoilsEngine.lua")
Load(SPOILS .. "/CommanderSpoils.lua")

Fire("ADDON_LOADED", "Commander_Spoils")
Fire("PLAYER_LOGIN")
RunTimers(0)

local E = CommanderSpoilsEngine
local S = CommanderSpoils_Suppression
local DB = CommanderSpoilsDB

CHECK(CommanderSpoils_Ready == true, "login: UI reached the ready flag")
eq(#errors, 0, "login: no handler errors", errors[1])

-- ===========================================================================
-- 1. Suppression
-- ===========================================================================
-- First run must suppress NOTHING until the player has seen what changes.
eq(DB.SeenIntro, true, "first run: intro marked seen")
eq(DB.SuppressLootWindow, false, "first run: loot window untouched")
CHECK(blizzLoot:IsEventRegistered("LOOT_OPENED"), "first run: Blizzard loot frame still live")
CHECK(GroupLootFrame_OpenNewFrame == originalOpenNewFrame, "first run: roll popups untouched")

S.TakeOverAll()
CHECK(not blizzLoot:IsEventRegistered("LOOT_OPENED"), "takeover: loot frame silenced")
CHECK(not blizzLoot:IsEventRegistered("UPDATE_MASTER_LOOT_LIST"), "takeover: master loot list silenced")
CHECK(GroupLootFrame_OpenNewFrame ~= originalOpenNewFrame, "takeover: OpenNewFrame replaced")
CHECK(#(chatFilters.CHAT_MSG_LOOT or {}) == 1, "takeover: one loot chat filter")
CHECK(#(chatFilters.CHAT_MSG_MONEY or {}) == 1, "takeover: one money chat filter")
CHECK(not blizzHistory:IsEventRegistered("LOOT_HISTORY_FULL_UPDATE"), "takeover: history frame silenced")
-- ItemPush is the one surface a takeover must not grab.
eq(DB.SuppressItemPush, false, "takeover: item push stays opt-in")
CHECK(_G.MainMenuBarBackpackButton:IsEventRegistered("ITEM_PUSH"), "takeover: bag flyin untouched")

-- Sync is idempotent: a second call must not double-register filters.
S.Sync()
CHECK(#(chatFilters.CHAT_MSG_LOOT or {}) == 1, "sync: idempotent, no duplicate filter")

-- Restore is EXACT: only the events that were on come back.
blizzLoot.__events.LOOT_READY = nil   -- pretend this one was never registered
S.Undo()
S.Sync()
S.Undo()
CHECK(blizzLoot:IsEventRegistered("LOOT_OPENED"), "restore: registered event came back")
eq(#(chatFilters.CHAT_MSG_LOOT or {}), 0, "restore: chat filter removed")
CHECK(GroupLootFrame_OpenNewFrame == originalOpenNewFrame, "restore: OpenNewFrame handed back")

-- Undo must NOT untick settings; RestoreAll must.
S.Sync()
CHECK(S.IsActive("SuppressLootWindow"), "undo: re-applied after Sync")
S.Undo()
eq(DB.SuppressLootWindow, true, "undo: leaves the setting alone")
S.Sync()
S.RestoreAll(true)
eq(DB.SuppressLootWindow, false, "restoreAll: unticks the switch")
CHECK(S.StatusText():find("NOTHING SUPPRESSED"), "status: reads clean when nothing is on")

-- The master switch is an exit path of its own.
S.TakeOverAll()
DB.EnableSpoils = false
S.Sync()
CHECK(blizzLoot:IsEventRegistered("LOOT_OPENED"), "master off: Blizzard restored")
DB.EnableSpoils = true
S.Sync()
CHECK(not blizzLoot:IsEventRegistered("LOOT_OPENED"), "master on: suppression resumes")

-- ===========================================================================
-- 2. Pattern building
-- ===========================================================================
local pattern = E.ToPattern(LOOT_ROLL_ROLLED_NEED)
CHECK(pattern and pattern:find("%[Loot%]", 1, true) ~= nil,
    "pattern: lootHistory prefix brackets escaped", pattern)
local h, r, item, who = ("|HlootHistory:7|h[Loot]|h: Need Roll - 94 for [Ironfoe] by Grimbold"):match(pattern)
eq(h, "7", "pattern: history index captured")
eq(r, "94", "pattern: roll captured")
eq(who, "Grimbold", "pattern: roller captured (roll, item, player order)")

-- The greedy-capture trap: an item name containing "x" must not be mis-split.
local matchers = { { pattern = E.ToPattern(LOOT_ITEM_SELF_MULTIPLE), fields = { "item", "count" } } }
local _, caps = E.Match(matchers, "You receive loot: [Flaxseed Oil]x5.")
eq(caps.item, "[Flaxseed Oil]", "pattern: non-greedy capture survives an x in the name")
eq(caps.count, "5", "pattern: count captured past the x")

-- ===========================================================================
-- 3. Bucket classification — the 4/1 vs 7/5 trap
-- ===========================================================================
eq(E.BucketOf(7, 5), "CLOTH", "bucket: Tradegoods/Cloth is a material")
eq(E.BucketOf(4, 1), "GEAR", "bucket: Armor/Cloth is gear, NOT a material")
eq(E.BucketOf(7, 10), "ELEMENTAL", "bucket: motes and primals")
eq(E.BucketOf(15, 0), "JUNK", "bucket: misc/junk")
eq(E.BucketOf(9, 1), "RECIPE", "bucket: recipes")
eq(E.BucketOf(0, 1), "CONSUMABLE", "bucket: consumables")

playerClassToken = "HUNTER"
CHECK(E.IsMyArmor(4, 3), "armor: hunter wears mail")
CHECK(not E.IsMyArmor(4, 4), "armor: hunter does not wear plate")
CHECK(not E.IsMyArmor(7, 5), "armor: a cloth MATERIAL is not armor")

-- ===========================================================================
-- 4. Loot parsing
-- ===========================================================================
local baselineEvents = #E.Data.events
E.OnLootMessage("You receive loot: " .. Link(21877) .. "x5.")
eq(#E.Data.events, baselineEvents + 1, "loot: self stack recorded")
local row = E.Data.events[#E.Data.events]
eq(row[2], 21877, "loot: itemID from the link, not the name")
eq(row[3], 5, "loot: count")
eq(row[7], E.SrcKind.LOOTED, "loot: attributed as looted")

E.OnLootMessage("You create: " .. Link(21840) .. ".")
eq(E.Data.events[#E.Data.events][7], E.SrcKind.CREATED, "loot: crafting attributed separately")

E.OnLootMessage("You receive item: " .. Link(23445) .. ".")
eq(E.Data.events[#E.Data.events][7], E.SrcKind.PUSHED, "loot: pushed attributed separately")

local before = #E.Data.events
E.OnLootMessage("Grimbold receives loot: " .. Link(28429) .. ".")
eq(#E.Data.events, before, "loot: another player's pickup never enters OUR ledger")
CHECK(E.Party.Grimbold and E.Party.Grimbold.items == 1, "loot: party row credited")
eq(E.Party.Grimbold.bestItemID, 28429, "loot: party best find tracked")

E.OnMoneyMessage("You loot 1 Gold 20 Silver 5 Copper")
eq(E.Fold(E.SegmentFor("SESSION")).gold, 12005, "money: coin text parsed to copper")
E.OnMoneyMessage("Your share of the loot is 5 Silver.")
eq(E.Fold(E.SegmentFor("SESSION")).gold, 12505, "money: split parsed")
-- Coin folds out of the persisted log by timestamp, so every scope sees it —
-- HOUR previously reported zero coin under the same VENDOR label.
eq(E.Fold(E.SegmentFor("HOUR")).gold, 12505, "money: HOUR scope sees coin too")

-- ===========================================================================
-- 5. Census and the reconciler
-- ===========================================================================
SetBag(0, 1, 21877, 20)
SetBag(0, 2, 21877, 4)     -- a partial stack of the same item
SetBag(0, 3, 5637, 1)      -- junk
SetBag(0, 4, 5637, 1)      -- more junk
SetBag(1, 1, 28429, 1)
E.baselined = false
E.ArmSettle(); RunTimers(2)

local census = E.Census()
eq(census.slotsTotal, 32, "census: total slots across two real bags")
eq(census.slotsFree, 27, "census: free slots")
eq(census.junk.stacks, 2, "census: junk stacks counted")
eq(census.junk.value, 1500, "census: junk value from sellPrice, not hasNoValue")
eq(census.reclaimable, 1, "census: one slot reclaimable from the partial stack")
eq(census.byBucket[E.BucketIndex.CLOTH].items, 24, "census: cloth bucket totals")

-- The first scan is a BASELINE. Without that, the reconciler reads the whole
-- inventory as freshly acquired.
local afterBaseline = #E.Data.events
CHECK(afterBaseline == before, "reconcile: baseline scan recorded nothing",
    (afterBaseline - before) .. " rows appeared")

-- A removal with a merchant open is a sale, not a mystery.
local outflows = {}
Commander.AddListener(COMMANDER_SPOILS_EVENTS.OUTFLOW, function(entry, reason)
    outflows[#outflows + 1] = { id = entry.itemID, count = entry.count, reason = reason }
end)
E.context.merchant = true
SetBag(0, 3, nil); SetBag(0, 4, nil)
E.ArmSettle(); RunTimers(2)
E.context.merchant = false
eq(#outflows, 1, "reconcile: one outflow for the vendored junk")
eq(outflows[1].reason, "VENDORED", "reconcile: merchant context attributes the sale")
eq(outflows[1].count, 2, "reconcile: both junk stacks counted")

-- The bank is only readable while it is open, so a deposit is indistinguishable
-- from destruction. Suppress rather than guess.
local outflowCount = #outflows
E.context.bank = true
SetBag(1, 1, nil)
E.ArmSettle(); RunTimers(2)
E.context.bank = false
eq(#outflows, outflowCount, "reconcile: bank-open suppresses outflow entirely")

-- A gain with no chat line is still ours — file it, do not drop it.
local eventsBefore = #E.Data.events
SetBag(0, 5, 22526, 1)
E.ArmSettle(); RunTimers(2)
eq(#E.Data.events, eventsBefore + 1, "reconcile: silent acquisition recorded")
eq(E.Data.events[#E.Data.events][7], E.SrcKind.OTHER, "reconcile: attributed as OTHER")

-- A vendor purchase or a mail collection is not income. It stays in the
-- ledger and stays out of the headline, the rate, and the best-find.
local otherStats = E.Fold(E.SegmentFor("SESSION"))
CHECK(otherStats.otherValue > 0, "reconcile: OTHER value tracked separately", otherStats.otherValue)
CHECK(otherStats.bestItemID ~= 22526, "reconcile: an OTHER row is never the best find")
local valueBefore = otherStats.value
SetBag(0, 6, 28429, 1)
E.ArmSettle(); RunTimers(2)
eq(E.Fold(E.SegmentFor("SESSION")).value, valueBefore,
    "reconcile: a silent 9g acquisition does not inflate the headline")

-- ===========================================================================
-- 6. Rolls
-- ===========================================================================
rollDB[101] = { itemID = 28429, canNeed = true, canGreed = true, bop = true,
                timeLeft = 60000, count = 1 }
Fire("START_LOOT_ROLL", 101, 60000)
local roll = E.rollByID[101]
CHECK(roll ~= nil, "roll: created from START_LOOT_ROLL")
eq(roll.bop, true, "roll: bind-on-pickup surfaced")
eq(roll.itemID, 28429, "roll: itemID resolved from the link")

-- The misclick guard: a roll button under a cursor aimed at the world must
-- not fire the instant the row appears.
local rollsBefore = #rolledCalls
E.Roll(101, 1)
eq(#rolledCalls, rollsBefore, "roll: guard rejects a click inside the arm window")
RunTimers(1)
E.Roll(101, 1)
eq(#rolledCalls, rollsBefore + 1, "roll: accepted after the guard expires")
eq(rolledCalls[#rolledCalls][2], 1, "roll: NEED sent")

-- Ineligibility is enforced, not just drawn.
rollDB[102] = { itemID = 24252, canNeed = false, canGreed = true, reasonNeed = 1,
                timeLeft = 60000, count = 1 }
Fire("START_LOOT_ROLL", 102, 60000)
RunTimers(1)
local blocked = #rolledCalls
E.Roll(102, 1)
eq(#rolledCalls, blocked, "roll: a Need we cannot cast is never sent")
E.Roll(102, 2)
eq(#rolledCalls, blocked + 1, "roll: Greed still works")

-- Resolution
historyItems = { { rollID = 101, link = Link(28429), done = true, winnerIdx = 1,
    players = {
        { name = "Testchar", class = "HUNTER", rollType = 1, roll = 94, winner = true, me = true },
        { name = "Grimbold", class = "WARRIOR", rollType = 2, roll = 71 },
    } } }
Fire("LOOT_HISTORY_FULL_UPDATE")
eq(roll.resolved, true, "roll: resolved from loot history")
eq(roll.won, true, "roll: win detected")
eq(roll.myRoll, 94, "roll: own roll number captured")
eq(roll.decided, 2, "roll: decided count is players who ANSWERED")

-- A withdrawn roll is not a missed roll. Mislabelling it would destroy the
-- credibility of the missed counter.
rollDB[103] = { itemID = 21877, canNeed = true, canGreed = true, timeLeft = 5000 }
Fire("START_LOOT_ROLL", 103, 60000)
Fire("CANCEL_LOOT_ROLL", 103)
eq(E.rollByID[103].cancelled, true, "roll: cancel marks withdrawn")
CHECK(not E.rollByID[103].missed, "roll: a withdrawn roll is NOT marked missed")

-- An unanswered roll that someone else wins IS missed.
rollDB[104] = { itemID = 22526, canNeed = true, canGreed = true, timeLeft = 1000 }
Fire("START_LOOT_ROLL", 104, 60000)
E.ResolveRoll(104, "Grimbold", "WARRIOR", 2, 55)
eq(E.rollByID[104].missed, true, "roll: unanswered + someone won = missed")
local logged = E.Data.rolls[#E.Data.rolls]
eq(logged.my, -1, "roll log: a missed roll is stamped -1")

-- Per-player detail is packed strings, not nested tables.
local packedRoll
for i = #E.Data.rolls, 1, -1 do
    if E.Data.rolls[i].p then packedRoll = E.Data.rolls[i]; break end
end
CHECK(packedRoll and type(packedRoll.p[1]) == "string",
    "roll log: player detail stored as packed strings")
CHECK(packedRoll and packedRoll.p[1]:find(":"), "roll log: packed field separator present")

-- Reload recovery: a live roll must survive a UI reload.
E.rolls, E.rollByID = {}, {}
rollDB[201] = { itemID = 28429, canNeed = true, canGreed = true, timeLeft = 42000 }
activeRollIDs = { 201 }
Fire("PLAYER_ENTERING_WORLD")
RunTimers(2)
CHECK(E.rollByID[201] ~= nil, "roll: GetActiveLootRollIDs rebuilds after a reload")
activeRollIDs = {}

-- A server-supplied format string must never reach format() unguarded.
local ok = pcall(E.FormatConfirm, "Rolling Need on %s will bind it to you.", "Girdle")
CHECK(ok, "confirm: well-formed reason formats cleanly")
ok = pcall(E.FormatConfirm, "broken %d %s %s %s", "Girdle")
CHECK(ok, "confirm: a mismatched specifier does not throw")

-- ===========================================================================
-- 7. Interest model
-- ===========================================================================
DB.MinQuality = 4
DB.FilterTradeGoods = false
DB.FilterArmor = false
DB.FilterBoP = false
DB.FilterRecipes = false
DB.FilterConsumables = false
DB.FilterQuest = false
CHECK(not E.IsNotable(21877, 1), "interest: a grey-ish material is quiet under a high floor")
DB.FilterTradeGoods = true
CHECK(E.IsNotable(21877, 1), "interest: the trade-goods switch beats the floor")
E.Pin(21877, false)
CHECK(not E.IsNotable(21877, 1), "interest: a never-pin beats the class switch")
E.Pin(21877, nil)
CHECK(E.IsNotable(21877, 1), "interest: clearing the pin restores the class rule")
CHECK(E.IsNotable(28429, 4), "interest: an epic passes the floor")

-- ===========================================================================
-- 8. Value
-- ===========================================================================
DB.ValueMode = "VENDOR"
local value, tier = E.UnitValue(21877)
eq(value, 300, "value: vendor price")
eq(tier, "VENDOR", "value: labelled as vendor")
uncachedIDs[6522] = true
E.Meta(6522)
local unknown = E.UnitValue(6522)
CHECK(unknown == nil, "value: an uncached price is nil, never zero", tostring(unknown))
uncachedIDs[6522] = nil

-- ===========================================================================
-- 9. Folds
-- ===========================================================================
local stats = E.Fold(E.SegmentFor("SESSION"))
CHECK(stats.items > 0, "fold: session has items")
CHECK(stats.value > 0, "fold: session has value")
CHECK(stats.bestItemID ~= 22526, "fold: a reconciled row is never the best find")
local hourA = E.SegmentFor("HOUR")
local hourB = E.SegmentFor("HOUR")
CHECK(hourA == hourB, "fold: the hour segment is reused so its fold can cache")

-- ===========================================================================
-- 10. Retention
-- ===========================================================================
for i = 1, E.Limits.rolls + 30 do
    E.Data.rolls[#E.Data.rolls + 1] = { t = now, id = 21877, q = 1, p = { "a:b:1:2" } }
end
E.Prune()
CHECK(#E.Data.rolls <= E.Limits.rolls, "prune: roll log respects its cap", #E.Data.rolls)
local withDetail = 0
for _, entry in ipairs(E.Data.rolls) do
    if entry.p then withDetail = withDetail + 1 end
end
CHECK(withDetail <= E.Limits.rollFull, "prune: only the newest rolls keep player detail", withDetail)

E.Data.events[1][1] = now - 400 * 86400
DB.HistoryDays = 30
local eventsPre = #E.Data.events
E.Prune()
CHECK(#E.Data.events < eventsPre, "prune: age cutoff drops stale events")

-- ===========================================================================
-- 11. Master loot
-- ===========================================================================
local candidates = E.MasterCandidates(1)
eq(#candidates, 3, "master loot: sparse probe finds every candidate")
eq(candidates[1].index, 3, "master loot: the RAW probe index is carried, not the position")
eq(candidates[3].index, 11, "master loot: sparse indices preserved")

-- ===========================================================================
-- 12. Loot slots
-- ===========================================================================
lootSlots = {
    { itemID = 21877, count = 5, slotType = 1 },
    { itemID = 28429, count = 1, slotType = 1, uncached = true },
}
local slots = E.RebuildSlots()
eq(#slots, 2, "slots: both slots modelled")
eq(slots[1].name, "Netherweave Cloth", "slots: cached name read")
eq(slots[2].cached, false, "slots: uncached slot flagged")
CHECK(slots[2].quality ~= nil, "slots: nil quality falls back through the link, never nil-indexed")
eq(slots[2].itemID, 28429, "slots: itemID resolved even while uncached")

-- ===========================================================================
-- 13. UI smoke — every pane, every scope, both roll renderers, the corpse
-- ===========================================================================
DB.EnableSpoils = true
DB.Expanded = false
CommanderSpoils_Toggle()
CHECK(CommanderSpoilsFrame:IsShown(), "ui: toggle opens the panes")
CHECK(DB.Expanded, "ui: toggle sets the expanded state")

local function RowTexts()
    local found = 0
    for i = 1, 40 do
        local row = _G["__row" .. i]
        if row then found = found + 1 end
    end
    return found
end

for _, mode in ipairs({ "FEED", "HAUL", "ROLLS", "BAGS", "PARTY" }) do
    local errorsBefore = #errors
    DB.ViewMode = mode
    Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
    eq(#errors, errorsBefore, "ui: " .. mode .. " paints without error", errors[#errors])
end

for _, scope in ipairs({ "SESSION", "RUN", "HOUR" }) do
    local errorsBefore = #errors
    DB.ViewScope = scope
    DB.ViewMode = "HAUL"
    Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
    eq(#errors, errorsBefore, "ui: scope " .. scope .. " paints without error", errors[#errors])
end

for _, filter in ipairs({ "ALL", "MINE", "NOTABLE" }) do
    local errorsBefore = #errors
    DB.ViewMode, DB.FeedFilter = "FEED", filter
    Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
    eq(#errors, errorsBefore, "ui: feed filter " .. filter .. " paints", errors[#errors])
end
DB.ViewScope = "SESSION"

-- The Salvage panel follows the loot session, never our own visibility.
lootSlots = {
    { itemID = 21877, count = 5, slotType = 1 },
    { itemID = 5637, count = 1, slotType = 1 },
}
local salvageErrors = #errors
Fire("LOOT_OPENED", false)
eq(#errors, salvageErrors, "ui: the corpse band opens without error", errors[#errors])
CHECK(CommanderSpoilsCorpse:IsShown(), "ui: corpse band shown on LOOT_OPENED")
CHECK(CommanderSpoilsCorpse:GetParent() == CommanderSpoilsFrame,
    "ui: the corpse is a band INSIDE the one frame, not its own window")
Fire("LOOT_CLOSED")
CHECK(not CommanderSpoilsCorpse:IsShown(), "ui: corpse band closes with the session")

-- Autoloot that sweeps a corpse clean must present nothing at all.
lootSlots = {}
Fire("LOOT_OPENED", true)
CHECK(not CommanderSpoilsCorpse:IsShown(), "ui: a clean autoloot shows no band")
Fire("LOOT_CLOSED")

-- The bands make the ONE frame appear on their own; the panes never do.
DB.Expanded = false
CommanderSpoils_Test("clear")
for i = #E.rolls, 1, -1 do E.rolls[i] = nil end
for id in pairs(E.rollByID) do E.rollByID[id] = nil end
Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
CHECK(not CommanderSpoilsFrame:IsShown(), "ui: collapsed with nothing to say, the frame is gone")
rollDB[301] = { itemID = 28429, canNeed = true, canGreed = true, timeLeft = 30000 }
local contestErrors = #errors
Fire("START_LOOT_ROLL", 301, 60000)
eq(#errors, contestErrors, "ui: a roll paints without error", errors[#errors])
CHECK(CommanderSpoilsFrame:IsShown(), "ui: a live roll brings the frame up on its own")
CHECK(CommanderSpoilsRolls:IsShown(), "ui: the roll band is shown")
CHECK(CommanderSpoilsRolls:GetParent() == CommanderSpoilsFrame,
    "ui: rolls are a band INSIDE the one frame")
CHECK(not DB.Expanded, "ui: the panes stay closed for a roll")
Fire("CANCEL_LOOT_ROLL", 301)
Commander.Notify(COMMANDER_SPOILS_EVENTS.ROLL, E.rollByID[301], "update")

local slashErrors = #errors
CommanderSpoils_Report()
CommanderSpoils_PrintSize()
CommanderSpoils_Test("pickup")
CommanderSpoils_ToggleFarm()
CHECK(E.FarmActive(), "ui: farm starts")
CommanderSpoils_ToggleFarm()
CHECK(not E.FarmActive(), "ui: farm stops")
eq(#errors, slashErrors, "ui: every slash-facing entry point runs clean", errors[#errors])

-- The watchdog is armed at login and must NOT fire while the UI is healthy.
S.TakeOverAll()
RunTimers(5)
CHECK(not blizzLoot:IsEventRegistered("LOOT_OPENED"),
    "watchdog: a healthy UI keeps its suppressions")
S.RestoreAll(true)

-- ===========================================================================
-- 14b. Iteration-2 regressions
-- ===========================================================================
-- The CRAFTED context flag lived in a later scope than the function that set
-- it, so the assignment created a global and every reagent consumption was
-- filed as USED. Found by globals_lint.lua, not by a human.
SetBag(1, 4, 2589, 10)
E.baselined = false
E.ArmSettle(); RunTimers(2)
local craftOutflows = {}
local craftListener = function(entry, reason)
    craftOutflows[#craftOutflows + 1] = reason
end
Commander.AddListener(COMMANDER_SPOILS_EVENTS.OUTFLOW, craftListener)
E.OnLootMessage("You create: " .. Link(21840) .. ".")
SetBag(1, 4, nil)
E.ArmSettle(); RunTimers(2)
local sawCrafted = false
for _, reason in ipairs(craftOutflows) do
    if reason == "CRAFTED" then sawCrafted = true end
end
CHECK(sawCrafted, "regression: reagents consumed by a craft are attributed CRAFTED",
    table.concat(craftOutflows, ","))

-- The party ledger is keyed to the group, not the login.
groupState = true
partyRoster = { "Grimbold", "Selune" }
E.partyKey = nil
E.CheckParty()
E.Party.Grimbold = { name = "Grimbold", items = 5, bestQuality = -1,
                     need = 0, greed = 0, pass = 0, won = 0 }
Fire("GROUP_ROSTER_UPDATE")
CHECK(E.Party.Grimbold ~= nil, "regression: the same group keeps its ledger")
partyRoster = { "Rakthar", "Nimue" }
Fire("GROUP_ROSTER_UPDATE")
CHECK(E.Party.Grimbold == nil, "regression: a new group starts a new ledger")
groupState = false
Fire("GROUP_ROSTER_UPDATE")

-- Escape hides the ONE frame directly; its OnHide is what ends the server
-- session, and a restyle-driven hide must NOT.
DB.SuppressLootWindow, DB.EnableSpoils = true, true
S.Sync()
lootSlots = { { itemID = 21877, count = 3, slotType = 1 } }
Fire("LOOT_OPENED", false)
CHECK(CommanderSpoilsCorpse:IsShown(), "regression: corpse open for the escape test")
local closesBefore = closeLootCalls
CommanderSpoilsFrame:Hide()          -- what UISpecialFrames does
CHECK(closeLootCalls == closesBefore + 1,
    "regression: escaping the frame ends the loot session")
CHECK(not DB.Expanded, "regression: escape also collapses the panes")
Fire("LOOT_CLOSED")
local closesAfter = closeLootCalls
Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)   -- a restyle
eq(closeLootCalls, closesAfter, "regression: a restyle never closes a loot session")

-- ===========================================================================
-- 14d. Field report, 2026-08-05: width, squish, ROLLS, HAUL duplicates,
--      feed noise, lag.
-- ===========================================================================
CommanderSpoils_Test("clear")
for i = #E.rolls, 1, -1 do E.rolls[i] = nil end
for id in pairs(E.rollByID) do E.rollByID[id] = nil end
E.Wipe(true)
DB.Expanded, DB.MaxRows = true, 12

-- (a) HAUL must never render one itemID on two rows. The fold used to pool
--     its per-item tables BY INDEX, so a row held across two folds could come
--     back pointing at a different item.
for round = 1, 4 do
    for _, id in ipairs({ 21877, 21840, 24252, 23445, 2589 }) do
        E.OnLootMessage("You receive loot: " .. Link(id) .. ".")
    end
    E.ArmSettle(); RunTimers(2)
    DB.ViewMode = "HAUL"
    Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
end
local seenIDs, haulDupes = {}, 0
for i = 1, DB.MaxRows do
    local row = _G["CommanderSpoilsRow" .. i]
    if row and row.__shown and row.itemID then
        if seenIDs[row.itemID] then haulDupes = haulDupes + 1 end
        seenIDs[row.itemID] = true
    end
end
eq(haulDupes, 0, "field: HAUL renders each item exactly once")
-- and the pooled row for an item is that item's, permanently
local foldA = E.Fold(E.SegmentFor("SESSION"))
local held = foldA.byItem[21877]
E.Fold(E.SegmentFor("HOUR"))
E.OnLootMessage("You receive loot: " .. Link(22526) .. ".")
E.Fold(E.SegmentFor("SESSION"))
eq(held.itemID, 21877, "field: a held fold row never re-points at another item")

-- (b) The ROLLS pane shows every participant inline, not behind a click.
E.Wipe(true)
rollDB[901] = { itemID = 28429, canNeed = true, canGreed = true, timeLeft = 30000 }
Fire("START_LOOT_ROLL", 901, 60000)
historyItems = { { rollID = 901, link = Link(28429), done = true, winnerIdx = 1,
    players = {
        { name = "Grimbold", class = "WARRIOR", rollType = 1, roll = 94, winner = true },
        { name = "Selune", class = "PRIEST", rollType = 2, roll = 71 },
        { name = "Rakthar", class = "ROGUE", rollType = 0 },
    } } }
Fire("LOOT_HISTORY_FULL_UPDATE")
historyItems = {}
DB.ViewMode, DB.ViewScope = "ROLLS", "SESSION"
Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
local names, choices, numbers = {}, {}, {}
for i = 1, DB.MaxRows do
    local row = _G["CommanderSpoilsRow" .. i]
    if row and row.__shown then
        names[#names + 1] = row.name:GetText() or ""
        choices[#choices + 1] = row.mid:GetText() or ""
        numbers[#numbers + 1] = row.right:GetText() or ""
    end
end
local blob = table.concat(names, "|") .. "//" .. table.concat(choices, "|")
    .. "//" .. table.concat(numbers, "|")
CHECK(blob:find("Grimbold", 1, true), "field: ROLLS names every participant", blob)
CHECK(blob:find("Selune", 1, true), "field: ROLLS lists the losers too")
CHECK(blob:find("NEED", 1, true) and blob:find("GREED", 1, true) and blob:find("PASS", 1, true),
    "field: ROLLS says what each of them chose", blob)
CHECK(blob:find("94", 1, true), "field: ROLLS shows the numbers they rolled")

-- (c) The feed merges consecutive identical pickups instead of listing twenty.
E.Wipe(true)
for _ = 1, 20 do
    E.OnLootMessage("You receive loot: " .. Link(21877) .. "x5.")
end
DB.ViewMode, DB.FeedFilter = "FEED", "ALL"
Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
local feedRows, clothText = 0, nil
for i = 1, DB.MaxRows do
    local row = _G["CommanderSpoilsRow" .. i]
    if row and row.__shown and row.itemID == 21877 then
        feedRows = feedRows + 1
        clothText = row.name:GetText()
    end
end
eq(feedRows, 1, "field: twenty identical pickups are one feed row")
CHECK(clothText and clothText:find("x100", 1, true),
    "field: the merged row carries the running total", clothText)

-- (d) FixedSize caps every band, so the frame's height stops jumping.
DB.FixedSize, DB.MaxRollRows = true, 2
for i = #E.rolls, 1, -1 do E.rolls[i] = nil end
for id in pairs(E.rollByID) do E.rollByID[id] = nil end
for i = 1, 6 do
    rollDB[910 + i] = { itemID = 21877, canNeed = true, canGreed = true, timeLeft = 30000 }
    Fire("START_LOOT_ROLL", 910 + i, 60000)
end
Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
local shownRolls = 0
for i = 1, 12 do
    local row = _G["CommanderSpoilsRollRow" .. i]
    if row and row.__shown then shownRolls = shownRolls + 1 end
end
eq(shownRolls, 2, "field: FixedSize caps the roll band")
CHECK((CommanderSpoilsRolls.captionRight:GetText() or ""):find("MORE", 1, true),
    "field: the overflow is stated, never silent",
    CommanderSpoilsRolls.captionRight:GetText())
DB.MaxRollRows = 3

-- (e) Dense mode drops the timer strip rather than crowding the buttons, and
--     the roll buttons are never hidden by a layout decision.
local denseRow = CommanderSpoilsRollRow1
CHECK(denseRow.buttons[1]:IsShown(), "field: the NEED button survives dense mode")
CHECK(denseRow.buttons[3]:IsShown(), "field: the PASS button survives dense mode")
CommanderSpoils_Test("clear")
for i = #E.rolls, 1, -1 do E.rolls[i] = nil end
for id in pairs(E.rollByID) do E.rollByID[id] = nil end

-- (f) The chrome fits the frame it is in. The header used fixed offsets sized
--     for 420px, so at 350 the elastic field's left edge sat right of its own
--     right edge — the overlap in the field report.
for _, width in ipairs({ 280, 350, 420, 520 }) do
    DB.FrameWidth = width
    DB.Expanded = true
    Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
    eq(CommanderSpoilsFrame:GetWidth(), width, "field: the frame honours width " .. width)

    -- Five mode buttons plus the scope must fit inside the frame.
    local used = 4
    for i = 1, 5 do used = used + _G["CommanderSpoilsModeButton" .. i]:GetWidth() end
    used = used + CommanderSpoilsScopeButton:GetWidth() + 4
    CHECK(used <= width, "field: the mode strip fits at " .. width, used .. " > " .. width)

    -- The elastic best-find field yields rather than overlapping its neighbour.
    if CommanderSpoilsHeaderBest.__shown then
        CHECK(CommanderSpoilsHeaderBest:GetWidth() >= 60,
            "field: the best-find field is never crushed at " .. width,
            CommanderSpoilsHeaderBest:GetWidth())
    else
        CHECK(width < 400, "field: best-find only hides on a narrow frame", width)
    end
end
DB.FrameWidth = 350
Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)

-- ===========================================================================
-- 14e. Round-3 fixes
-- ===========================================================================
-- (a) "Restore Defaults" must restore BLIZZARD, not take it over. With every
--     Suppress* defaulting true it did the exact opposite of what it says.
S.TakeOverAll()
CHECK(not blizzLoot:IsEventRegistered("LOOT_OPENED"), "round3: takeover applied")
SlashCmdList["COMMANDERUI_SPOILS"]("reset")
CHECK(blizzLoot:IsEventRegistered("LOOT_OPENED"),
    "round3: Restore Defaults hands Blizzard's loot window back")
eq(DB.SuppressLootWindow, false, "round3: defaults leave the takeover off")

-- (b) The FEED is the chat replacement, so it has to survive a /reload.
E.Wipe(true)
for _ = 1, 5 do E.OnLootMessage("You receive loot: " .. Link(21877) .. "x5.") end
for i = #E.Feed, 1, -1 do E.Feed[i] = nil end          -- what a reload looks like
eq(#E.Feed, 0, "round3: feed emptied for the reload test")
E.RehydrateFeed(120)
CHECK(#E.Feed >= 5, "round3: the feed is rebuilt from the persisted log", #E.Feed)
eq(E.Feed[1].itemID, 21877, "round3: rehydrated rows carry their item")
CHECK(E.Feed[1].restored, "round3: rehydrated rows are marked as such")

-- (c) Wiping a season of history is two-step.
E.Wipe(true)
E.OnLootMessage("You receive loot: " .. Link(21877) .. ".")
local eventsBeforeWipe = #E.Data.events
gameTime = gameTime + 60
CommanderSpoils_Wipe()
eq(#E.Data.events, eventsBeforeWipe, "round3: the first wipe click only arms")
CommanderSpoils_Wipe()
eq(#E.Data.events, 0, "round3: the second click erases")

-- (d) Lifetime counts what you LOOTED, not what you bought.
E.Wipe(true)
E.OnLootMessage("You receive loot: " .. Link(21877) .. "x5.")
E.ArmSettle(); RunTimers(2)
local lootedLifetime = E.Data.lifetime[21877] and E.Data.lifetime[21877][1] or 0
E.Record(21877, 40, E.SrcKind.OTHER, nil, nil, nil)
eq(E.Data.lifetime[21877][1], lootedLifetime,
    "round3: a reconciled arrival never inflates the lifetime total")

-- (e) The roster signature sees a raid.
groupState = true
partyRoster = { "A", "B", "C" }
E.partyKey = nil
E.CheckParty()
local partyKey = E.partyKey
CHECK(partyKey and partyKey ~= "solo", "round3: a party has a signature", partyKey)
groupState = false

-- (f) Master-loot candidates refresh on the events that revise them.
CHECK(eventRegistry["OPEN_MASTER_LOOT_LIST"] ~= nil,
    "round3: the master loot list open event is registered")
CHECK(eventRegistry["UPDATE_MASTER_LOOT_LIST"] ~= nil,
    "round3: the master loot list update event is registered")

-- (g) Ending a farm cannot strand the scope selector on FARM.
E.StartFarm("Test")
DB.ViewScope = "FARM"
E.StopFarm()
DB.ViewMode = "HAUL"
Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
eq(DB.ViewScope, "SESSION", "round3: the scope falls back when the farm ends")

-- ===========================================================================
-- 14f. Round-3 review fixes
-- ===========================================================================
CommanderSpoils_Test("clear")
for i = #E.rolls, 1, -1 do E.rolls[i] = nil end
for id in pairs(E.rollByID) do E.rollByID[id] = nil end
E.Wipe(true)
DB.Expanded, DB.EnableSpoils = false, true

-- (a) The rehydrated feed must read newest-first, like the live one.
for _, id in ipairs({ 21877, 22526, 5637, 28429 }) do
    now = now + 10
    E.OnLootMessage("You receive loot: " .. Link(id) .. ".")
end
local liveFirst = E.Feed[1].itemID
for i = #E.Feed, 1, -1 do E.Feed[i] = nil end
E.RehydrateFeed(50)
eq(E.Feed[1].itemID, liveFirst, "round3: the rehydrated feed is newest-first")
eq(E.Feed[1].itemID, 28429, "round3: the newest pickup leads the restored feed")

-- (b) An outflow row must not swallow the pickup of the same item.
E.Wipe(true)
E.OnLootMessage("You receive loot: " .. Link(5637) .. "x5.")
E.RecordOutflow(5637, 20, "VENDORED")
DB.Expanded, DB.ViewMode, DB.FeedFilter = true, "FEED", "ALL"
Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
local kinds = {}
for i = 1, DB.MaxRows do
    local row = _G["CommanderSpoilsRow" .. i]
    if row and row.__shown and row.name:GetText() ~= "" then
        kinds[#kinds + 1] = row.name:GetText()
    end
end
local joined = table.concat(kinds, " | ")
CHECK(joined:find("−", 1, true), "round3: the outflow row survives", joined)
CHECK(joined:find("Large Fang", 1, true) and #kinds >= 2,
    "round3: the pickup is not swallowed by the outflow", joined)

-- (c) An expired pickup notice must take the frame down with it, not leave a
--     bare header strip on screen for the rest of the session.
DB.Expanded = false
CommanderSpoils_Test("clear")
Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
CHECK(not CommanderSpoilsFrame:IsShown(), "round3: idle and collapsed means no frame")
CommanderSpoils_Test("pickup")
CHECK(CommanderSpoilsFrame:IsShown(), "round3: a pickup brings the frame up")
RunTimers(8)                       -- the notice expires
CHECK(not CommanderSpoilsPickups:IsShown(), "round3: the pickup band expired")
CHECK(not CommanderSpoilsFrame:IsShown(),
    "round3: the frame goes with it instead of leaving an empty header")

-- (d) Late item data has to reach the painter.
local dirtyBefore = 0
E.OnDataDirty = function() dirtyBefore = dirtyBefore + 1 end
uncachedIDs[6522] = true
E.Meta(6522)
uncachedIDs[6522] = nil
Fire("GET_ITEM_INFO_RECEIVED", 6522, true)
CHECK(dirtyBefore > 0, "round3: item data arriving marks the window dirty")

-- (e) The header's fixed fields yield instead of colliding at narrow widths.
for _, width in ipairs({ 280, 300, 320, 330, 420 }) do
    DB.FrameWidth, DB.Expanded = width, true
    Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
    if width < 330 then
        CHECK(not CommanderSpoilsHeaderBest.__shown and not _G.CommanderSpoilsFrame.__itemsShown,
            "round3: narrow header sheds its optional fields at " .. width)
    end
end
DB.FrameWidth = 350
Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)

-- (f) One frame means one chrome block.
eq(CommanderSpoilsDB.ContestStyle, nil, "round3: no orphaned Contest chrome")
eq(CommanderSpoilsDB.SalvageScale, nil, "round3: no orphaned Salvage chrome")
eq(CommanderSpoilsDB.WirePos, nil, "round3: no orphaned Wire chrome")
CHECK(CommanderSpoilsDB.HudStyle ~= nil, "round3: the one chrome block is present")

-- (g) A corpse is one kill, not one per slot.
E.Wipe(true)
lootSlots = {
    { itemID = 21877, count = 1, slotType = 1 },
    { itemID = 22526, count = 1, slotType = 1 },
    { itemID = 5637, count = 1, slotType = 1 },
}
sourceInfoEnabled = true
E.RebuildSlots()
local kills = 0
for _, n in pairs(E.Data.kills) do kills = kills + n end
eq(kills, 1, "round3: a three-slot corpse counts one kill")

-- (h) ROLLS honours the scope selector on every scope, not just SESSION.
E.Wipe(true)
E.Data.rolls[#E.Data.rolls + 1] = { t = 1, id = 21877, q = 1 }   -- 1970
DB.ViewMode = "ROLLS"
for _, scope in ipairs({ "SESSION", "RUN", "HOUR" }) do
    DB.ViewScope = scope
    Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
    local first = CommanderSpoilsRow1
    CHECK(not (first and first.__shown and first.itemID == 21877),
        "round3: scope " .. scope .. " excludes a 1970 roll")
end
DB.ViewScope, DB.ViewMode = "SESSION", "FEED"

-- (i) The ticker's early-out actually fires. With nothing pending and nothing
--     dirty the OnUpdate must not be rebuilding lists.
E.Wipe(true)
DB.Expanded = false
Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
RunFrames(0.1, 5)                   -- let the dirty flag settle
local repaints = 0
local realFold = E.Fold
E.Fold = function(...) repaints = repaints + 1; return realFold(...) end
RunFrames(0.1, 30)                  -- three seconds of idle
E.Fold = realFold
eq(repaints, 0, "round3: an idle collapsed window costs nothing per frame", repaints)

-- ===========================================================================
-- 14h. Always show
-- ===========================================================================
CommanderSpoils_Test("clear")
for i = #E.rolls, 1, -1 do E.rolls[i] = nil end
for id in pairs(E.rollByID) do E.rollByID[id] = nil end
E.Wipe(true)
DB.Expanded, DB.AlwaysShow = false, false
Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
CHECK(not CommanderSpoilsFrame:IsShown(), "always: off, an idle collapsed window is gone")
DB.AlwaysShow = true
Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
CHECK(CommanderSpoilsFrame:IsShown(), "always: on, it stays with nothing happening")
CHECK(not CommanderSpoilsRolls:IsShown(), "always: the bands still stay out of the way")
CHECK(not CommanderSpoilsCorpse:IsShown(), "always: no corpse band either")
-- ...and it still costs nothing per frame while parked.
RunFrames(0.1, 5)
local folds = 0
local realFold = E.Fold
E.Fold = function(...) folds = folds + 1; return realFold(...) end
RunFrames(0.1, 30)
E.Fold = realFold
eq(folds, 0, "always: a parked window is still free per frame", folds)
DB.AlwaysShow = false
Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
CHECK(not CommanderSpoilsFrame:IsShown(), "always: turning it off puts it away again")

-- ===========================================================================
-- 14g. Field report: text overlapping at the bottom of the window
-- ===========================================================================
E.Wipe(true)
DB.Expanded, DB.EnableSpoils = true, true

-- The status line's left field was anchored on ONE side, so it ran underneath
-- the filter buttons and the row count. Every element now owns a lane.
for _, width in ipairs({ 280, 350, 420, 520 }) do
    DB.FrameWidth = width
    for _, mode in ipairs({ "FEED", "HAUL" }) do
        DB.ViewMode = mode
        Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
        local reserved = 6 + ((mode == "FEED") and (3 * 46) or 74)
        -- The left field must end before the reserved block begins.
        local leftRoom = width - 6 - reserved - 4
        CHECK(leftRoom > 40,
            "field: the status line leaves room for its left field (" .. mode .. ", " .. width .. ")",
            leftRoom)
    end
end
DB.FrameWidth, DB.ViewMode = 350, "FEED"
Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)

-- Consecutive pickups by the SAME other player merge; two different players
-- looting the same item must not.
E.Wipe(true)
E.OnLootMessage("Deddeye receives loot: " .. Link(24252) .. ".")
E.OnLootMessage("Deddeye receives loot: " .. Link(24252) .. ".")
DB.ViewMode, DB.FeedFilter = "FEED", "ALL"
Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
local rowsWithItem = 0
for i = 1, DB.MaxRows do
    local row = _G["CommanderSpoilsRow" .. i]
    if row and row.__shown and row.itemID == 24252 then rowsWithItem = rowsWithItem + 1 end
end
eq(rowsWithItem, 1, "field: one player looting the same thing twice is one row")

E.Wipe(true)
E.OnLootMessage("Deddeye receives loot: " .. Link(24252) .. ".")
E.OnLootMessage("Moremojito receives loot: " .. Link(24252) .. ".")
Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
rowsWithItem = 0
for i = 1, DB.MaxRows do
    local row = _G["CommanderSpoilsRow" .. i]
    if row and row.__shown and row.itemID == 24252 then rowsWithItem = rowsWithItem + 1 end
end
eq(rowsWithItem, 2, "field: two players looting the same thing stay two rows")

-- ===========================================================================
-- 14c. The Try It buttons — they drive the real painting code, so a broken
--      band shows up here rather than in a raid.
-- ===========================================================================
CommanderSpoils_Test("clear")
for i = #E.rolls, 1, -1 do E.rolls[i] = nil end
for id in pairs(E.rollByID) do E.rollByID[id] = nil end
DB.Expanded = false
local testErrors = #errors

CommanderSpoils_Test("pickup")
eq(#errors, testErrors, "try it: pickup runs clean", errors[#errors])
CHECK(CommanderSpoilsFrame:IsShown(), "try it: a pickup brings the frame up")
CHECK(CommanderSpoilsPickups:IsShown(), "try it: the pickup band is shown")
CHECK((CommanderSpoilsPickupRow1.label:GetText() or ""):find("Girdle", 1, true),
    "try it: the pickup row names the item", CommanderSpoilsPickupRow1.label:GetText())

CommanderSpoils_Test("roll")
CHECK(CommanderSpoilsRolls:IsShown(), "try it: the roll band is shown")
CHECK((CommanderSpoilsRollRow1.name:GetText() or ""):find("Girdle", 1, true),
    "try it: the fake roll paints a real row")
-- A fake roll must never reach the server.
local sentBefore = #rolledCalls
gameTime = gameTime + 1
CommanderSpoils_RollNeed()
eq(#rolledCalls, sentBefore, "try it: a fake roll never calls RollOnLoot")

CommanderSpoils_Test("win")
CHECK((CommanderSpoilsRollRow1.verdict:GetText() or ""):find("WON", 1, true),
    "try it: the win test paints the win verdict", CommanderSpoilsRollRow1.verdict:GetText())

CommanderSpoils_Test("wave")
CHECK(#E.rolls >= 6, "try it: the wave test opens six rolls", #E.rolls)

CommanderSpoils_Test("corpse")
CHECK(CommanderSpoilsCorpse:IsShown(), "try it: the corpse band is shown")
eq(CommanderSpoilsSlotRow1.sub:GetText(), "BINDS TO YOU",
    "try it: the corpse test also shows the inline bind confirm")

CommanderSpoils_Test("clear")
CHECK(not CommanderSpoilsCorpse:IsShown(), "try it: clear closes the corpse")
local anyFake = false
for _, roll in ipairs(E.rolls) do if roll.fake then anyFake = true end end
CHECK(not anyFake, "try it: clear removes every fake roll")
eq(#errors, testErrors, "try it: the whole set runs without an error", errors[#errors])

-- ===========================================================================
-- 14. Regressions — one check per defect the peer review found, each written
--     so it fails under the exact mutation it exists to catch.
-- ===========================================================================
local function RowText(name) local w = _G[name]; return w and w.name and w.name:GetText() end
-- Resolved rolls linger for six seconds by design; clear them so the row
-- indices below address the roll each check is actually about.
local function ClearRolls()
    for _, roll in ipairs(E.rolls) do
        roll.resolved, roll.resolvedAt = true, 0
    end
    gameTime = gameTime + 30
    E.PruneRolls()
    Commander.Notify(COMMANDER_SPOILS_EVENTS.ROLL, nil, "update")
end
ClearRolls()
DB.SuppressLootWindow, DB.SuppressBindConfirm, DB.EnableSpoils = true, true, true
S.Sync()

-- (a) The bind-confirm blocker: hiding Blizzard's dialog without repainting our
--     own row made every bind-on-pickup item unlootable.
lootSlots = { { itemID = 28429, count = 1, slotType = 1 } }
Fire("LOOT_OPENED", false)
CHECK(CommanderSpoilsCorpse:IsShown(), "regression: salvage open for the BoP test")
Fire("LOOT_BIND_CONFIRM", 1)
local salvageSub = CommanderSpoilsSlotRow1 and CommanderSpoilsSlotRow1.sub:GetText()
eq(salvageSub, "BINDS TO YOU", "regression: bind confirm repaints the corpse row")
eq(E.bindSlot, 1, "regression: bind slot recorded")
Fire("LOOT_CLOSED")
CHECK(E.bindSlot == nil, "regression: bind slot cleared with the session")

-- (b) An ineligible roll must never be logged as MISSED.
rollDB[401] = { itemID = 24252, canNeed = false, canGreed = false,
                reasonNeed = 1, reasonGreed = 1, timeLeft = 30000 }
Fire("START_LOOT_ROLL", 401, 60000)
E.ResolveRoll(401, "Grimbold", "WARRIOR", 1, 88)
CHECK(not E.rollByID[401].missed, "regression: a roll you could not enter is not MISSED")

-- (c) CollapseIneligible must actually collapse the row.
ClearRolls()
DB.Expanded = false
DB.CollapseIneligible = true
rollDB[402] = { itemID = 24252, canNeed = false, canGreed = false,
                reasonNeed = 1, reasonGreed = 1, timeLeft = 30000 }
Fire("START_LOOT_ROLL", 402, 60000)
Commander.Notify(COMMANDER_SPOILS_EVENTS.ROLL, E.rollByID[402], "update")
local collapsedText = CommanderSpoilsRollRow1 and CommanderSpoilsRollRow1.note:GetText()
CHECK(collapsedText == LOOT_ROLL_INELIGIBLE_REASON1,
    "regression: CollapseIneligible shows the server's reason", collapsedText)
Fire("CANCEL_LOOT_ROLL", 401)
Fire("CANCEL_LOOT_ROLL", 402)

-- (d) Auto-pass leaves a visible ghost, never a silent pass.
ClearRolls()
DB.AutoPassBelowQuality = 3
rollDB[403] = { itemID = 21877, canNeed = true, canGreed = true, timeLeft = 30000 }
Fire("START_LOOT_ROLL", 403, 60000)
RunTimers(3)
CHECK(E.rollByID[403].auto == true, "regression: auto-pass fired below the floor")
Commander.Notify(COMMANDER_SPOILS_EVENTS.ROLL, E.rollByID[403], "update")
local ghost = CommanderSpoilsRollRow1 and CommanderSpoilsRollRow1.note:GetText()
CHECK(ghost and ghost:find("auto-passed", 1, true), "regression: auto-pass leaves a ghost row", ghost)
DB.AutoPassBelowQuality = 0
Fire("CANCEL_LOOT_ROLL", 403)

-- (e) The chime fires when a roll OPENS, not 45 seconds later.
ClearRolls()
local sounds = 0
local realPlaySound = PlaySound
PlaySound = function(...) sounds = sounds + 1; return realPlaySound(...) end
rollDB[404] = { itemID = 28429, canNeed = true, canGreed = true, timeLeft = 60000 }
Fire("START_LOOT_ROLL", 404, 60000)
Commander.Notify(COMMANDER_SPOILS_EVENTS.ROLL, E.rollByID[404], "start")
CHECK(sounds > 0, "regression: a roll opening at full time chimes immediately")
-- ...and a second roll opening in the same second must not chime again.
local afterFirst = sounds
rollDB[405] = { itemID = 22526, canNeed = true, canGreed = true, timeLeft = 60000 }
Fire("START_LOOT_ROLL", 405, 60000)
Commander.Notify(COMMANDER_SPOILS_EVENTS.ROLL, E.rollByID[405], "start")
eq(sounds, afterFirst, "regression: urgency is aggregate — one chime per batch")
PlaySound = realPlaySound
Fire("CANCEL_LOOT_ROLL", 404)
Fire("CANCEL_LOOT_ROLL", 405)

-- (f) Toasts merge by item, so farming one material cannot produce 200 rows.
DB.Expanded = false
DB.FilterTradeGoods = true
Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
for _ = 1, 6 do
    E.OnLootMessage("You receive loot: " .. Link(21877) .. "x5.")
end
local merged = CommanderSpoilsPickupRow1 and CommanderSpoilsPickupRow1.label:GetText()
CHECK(merged and merged:find("x30"), "regression: repeat pickups merge into one toast", merged)
CHECK(not (CommanderSpoilsPickupRow2 and CommanderSpoilsPickupRow2:IsShown()),
    "regression: six identical pickups occupy one toast row")

-- (g) Currency is not counted twice.
local currencyBefore = #E.Data.events
E.OnCurrencyMessage("You receive currency: " .. Link(2589) .. " x3.")
E.ArmSettle(); RunTimers(2)
eq(#E.Data.events, currencyBefore + 1, "regression: currency recorded exactly once")

-- (h) Party roll tallies are idempotent across repeated history refreshes.
ClearRolls()
rollDB[501] = { itemID = 28429, canNeed = true, canGreed = true, timeLeft = 60000 }
Fire("START_LOOT_ROLL", 501, 60000)
historyItems = { { rollID = 501, link = Link(28429), done = false, winnerIdx = nil,
    players = { { name = "Rakthar", class = "ROGUE", rollType = 1, roll = 61 } } } }
E.Party.Rakthar = nil
Fire("LOOT_HISTORY_FULL_UPDATE")
Fire("LOOT_HISTORY_FULL_UPDATE")
Fire("LOOT_HISTORY_ROLL_CHANGED", 1, 1)
eq(E.Party.Rakthar and E.Party.Rakthar.need, 1,
    "regression: a roller is credited once, not once per refresh")
historyItems = {}
Fire("CANCEL_LOOT_ROLL", 501)

-- (i) Pruning the front of the log rebases every index range that points into it.
DB.HistoryDays = 60
local seg = E.SegmentFor("SESSION")
local itemsBefore = E.Fold(seg).items
for i = 1, math.min(12, #E.Data.events) do
    E.Data.events[i][1] = now - 400 * 86400   -- age the oldest rows out
end
DB.HistoryDays = 30
local shed = E.Prune()
CHECK(shed > 0, "regression: prune shed stale rows", shed)
local itemsAfter = E.Fold(E.SegmentFor("SESSION")).items
CHECK(itemsAfter <= itemsBefore, "regression: prune never inflates a segment", itemsAfter)
CHECK(E.Segments.SESSION.fromIdx >= 1, "regression: session index stayed valid")
DB.HistoryDays = 60

-- (j) The watchdog blocks re-suppression, so investigating the warning cannot
--     re-break a dead UI with one checkbox.
S.RestoreAll(true)
S.Block()
CommanderSpoilsDB.SuppressLootWindow = true
S.Sync()
CHECK(blizzLoot:IsEventRegistered("LOOT_OPENED"),
    "regression: a blocked suppression layer refuses to re-apply")
S.RestoreAll(true)
CommanderSpoilsDB.SuppressLootWindow = true
S.Sync()
CHECK(not blizzLoot:IsEventRegistered("LOOT_OPENED"),
    "regression: /cspoils restore clears the block")
S.RestoreAll(true)

-- (k) Content assertions on the panes: a pane that silently renders nothing
--     must not read as a pass.
DB.Expanded = true
DB.ViewMode, DB.ViewScope, DB.FeedFilter = "FEED", "SESSION", "ALL"
Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
local anyFeedText = false
for i = 1, DB.MaxRows do
    local text = RowText("CommanderSpoilsRow" .. i)
    if text and text ~= "" then anyFeedText = true break end
end
CHECK(anyFeedText, "regression: the FEED actually renders row text")

DB.ViewMode = "BAGS"
Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
eq(RowText("CommanderSpoilsRow1"), "FREE", "regression: BAGS leads with free slots")

DB.ViewMode = "HAUL"
Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
local haulText = RowText("CommanderSpoilsRow1")
CHECK(haulText and haulText ~= "", "regression: HAUL renders an item name", haulText)

DB.ViewMode = "ROLLS"
Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
local anyRollText = false
for i = 1, DB.MaxRows do
    local text = RowText("CommanderSpoilsRow" .. i)
    if text and text ~= "" then anyRollText = true break end
end
CHECK(anyRollText, "regression: ROLLS renders the persisted log")
DB.ViewMode = "FEED"

-- ===========================================================================
-- 14. Wipe keeps settings
-- ===========================================================================
DB.MinQuality = 2
E.Wipe(true)
eq(#E.Data.events, 0, "wipe: history cleared")
eq(DB.MinQuality, 2, "wipe: settings untouched")

-- ===========================================================================
eq(#errors, 0, "no unhandled errors across the run", errors[1])
if #errors > 0 then
    local seen = {}
    for _, err in ipairs(errors) do
        if not seen[err] then
            seen[err] = true
            realPrint("ERROR  " .. err)
        end
    end
end
realPrint(string.format("%d checks, %d failed", checks, fails))
os.exit(fails > 0 and 1 or 0)
