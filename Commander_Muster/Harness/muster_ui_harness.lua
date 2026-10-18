-- Commander Muster UI smoke harness (luajit).
--
-- Loads the REAL shared framework (CommanderSettingsUI.lua, CommanderEvents.lua)
-- plus all four Commander_Muster files under a permissive WoW mock, then
-- drives login, the settings page, the character readout, the whole quiet
-- inspect round trip for a mouseover (NotifyInspect -> INSPECT_READY ->
-- RequestInspectHonorData -> INSPECT_HONOR_UPDATE -> ClearInspectPlayer),
-- the throttle and the newest-wins queue, the inspect-window ride-along,
-- late item data, the tooltip lines, the arena season modes and both slash
-- entry points. Catches nil-global calls, bad signatures and font traps
-- without a client.
--
-- Mock copied from Commander_Forecast/Harness/forecast_ui_harness.lua and
-- extended with the inspect, inventory and arena surfaces this module reads.
--
-- Run:  /opt/homebrew/bin/luajit muster_ui_harness.lua

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
SlashCmdList = {}
RAID_CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    HUNTER = { r = 0.67, g = 0.83, b = 0.45 },
    MAGE = { r = 0.41, g = 0.80, b = 0.94 },
}
CLASS_ICON_TCOORDS = { WARRIOR = { 0, 0.25, 0, 0.25 } }
function IsInRaid() return false end
local inCombat = false
function InCombatLockdown() return inCombat end

-- Advance the clock and fire every timer that came due, in order
local function Advance(seconds)
    now = now + seconds
    local again = true
    while again do
        again = false
        table.sort(timers, function(a, b) return a.at < b.at end)
        for i, t in ipairs(timers) do
            if t.at <= now then
                table.remove(timers, i)
                t.fn()
                again = true
                break
            end
        end
    end
end

-- ===========================================================================
-- Muster-specific mock: units, inventories, the item cache, inspect, arena
-- ===========================================================================

ITEM_QUALITY_COLORS = {
    [2] = { r = 0.12, g = 1, b = 0, hex = "|cff1eff00" },
    [3] = { r = 0, g = 0.44, b = 0.87, hex = "|cff0070dd" },
    [4] = { r = 0.64, g = 0.21, b = 0.93, hex = "|cffa335ee" },
}

-- The item database: what C_Item.GetItemInfo knows once an item is cached
local ITEMS = {
    [29011] = { name = "Warbringer Chestguard", quality = 4, ilvl = 120, loc = "INVTYPE_CHEST" },
    [29021] = { name = "Warbringer Battle-Helm", quality = 4, ilvl = 120, loc = "INVTYPE_HEAD" },
    [30972] = { name = "Onslaught Greathelm", quality = 4, ilvl = 146, loc = "INVTYPE_HEAD" },
    [30975] = { name = "Onslaught Chestguard", quality = 4, ilvl = 146, loc = "INVTYPE_CHEST" },
    [28288] = { name = "Abacus of Violent Odds", quality = 3, ilvl = 115, loc = "INVTYPE_TRINKET" },
    [28429] = { name = "Lionheart Executioner", quality = 4, ilvl = 125, loc = "INVTYPE_2HWEAPON" },
    [30879] = { name = "Ashtongue Talisman", quality = 4, ilvl = 141, loc = "INVTYPE_TRINKET" },
    [31023] = { name = "Old Bracers", quality = 2, ilvl = 88, loc = "INVTYPE_WRIST" },
    [24356] = { name = "Rifle of the Stoic Guardian", quality = 3, ilvl = 115, loc = "INVTYPE_RANGED" },
}
local cached = {}       -- itemID -> true once the client "has" it
local loadRequests = {} -- itemID -> count
for id in pairs(ITEMS) do cached[id] = true end

local function Link(id)
    local item = ITEMS[id]
    local hex = ITEM_QUALITY_COLORS[item.quality] and ITEM_QUALITY_COLORS[item.quality].hex or "|cffffffff"
    return hex .. "|Hitem:" .. id .. ":0:0:0:0:0:0:0|h[" .. item.name .. "]|h|r"
end

C_Item = {
    GetItemInfoInstant = function(link)
        local id = tonumber(link:match("item:(%d+)"))
        local item = ITEMS[id]
        return id, "Armor", "Plate", item and item.loc, 1, 4, 4
    end,
    GetItemInfo = function(link)
        local id = tonumber(link:match("item:(%d+)"))
        local item = ITEMS[id]
        if not item or not cached[id] then return nil end
        return item.name, link, item.quality, item.ilvl, 70, "Armor", "Plate", 1, item.loc, "icon", 1000, 4, 4
    end,
    RequestLoadItemDataByID = function(id) loadRequests[id] = (loadRequests[id] or 0) + 1 end,
}

-- Units. A token resolves to whichever unit the harness has put there.
local playerGuid = "Player-0-ME"
local units = {
    player = { guid = playerGuid, name = "Devinp", class = "WARRIOR", isPlayer = true, inspectable = false,
        items = { [1] = 29021, [5] = 29011, [9] = 31023, [13] = 28288, [16] = 28429, [18] = 24356 } },
}
local roster = {
    bob = { guid = "Player-0-BOB", name = "Bob", class = "HUNTER", isPlayer = true, inspectable = true,
        items = { [1] = 30972, [5] = 30975, [14] = 30879, [16] = 28429, [18] = 24356 },
        arena = { [2] = { rating = 1912, played = 60, wins = 38 }, [3] = { rating = 0, played = 0, wins = 0 }, [5] = { rating = 0, played = 0, wins = 0 } } },
    carl = { guid = "Player-0-CARL", name = "Carl", class = "MAGE", isPlayer = true, inspectable = true,
        items = { [1] = 29021 }, arena = {} },
    dave = { guid = "Player-0-DAVE", name = "Dave", class = "MAGE", isPlayer = true, inspectable = true,
        items = { [5] = 29011 }, arena = {} },
    erin = { guid = "Player-0-ERIN", name = "Erin", class = "MAGE", isPlayer = true, inspectable = true,
        items = { [5] = 29011 }, arena = {} },
    frank = { guid = "Player-0-FRANK", name = "Frank", class = "WARRIOR", isPlayer = true, inspectable = true,
        items = { [1] = 30972, [5] = 30975 },
        arena = { [3] = { rating = 2210, played = 100, wins = 70 } } },
    orc = { guid = "Player-0-ORC", name = "Grak", class = "WARRIOR", isPlayer = true, inspectable = false, items = {} },
    -- Group members for the background lookups (section E3)
    hank = { guid = "Player-0-HANK", name = "Hank", class = "WARRIOR", isPlayer = true, inspectable = true,
        items = { [1] = 29021 }, arena = { [2] = { rating = 1650, played = 30, wins = 16 } } },
    ivy = { guid = "Player-0-IVY", name = "Ivy", realm = "Nightslayer", class = "MAGE", isPlayer = true,
        inspectable = true, items = { [5] = 29011 }, arena = { [3] = { rating = 1777, played = 20, wins = 12 } } },
    jon = { guid = "Player-0-JON", name = "Jon", class = "MAGE", isPlayer = true, inspectable = false,
        items = { [5] = 29011 }, arena = { [5] = { rating = 1500, played = 8, wins = 4 } } },
    dummy = { guid = "Creature-0-DUMMY", name = "Training Dummy", isPlayer = false, inspectable = false, items = {} },
}

local function Place(token, who) units[token] = who end

function UnitGUID(unit) return units[unit] and units[unit].guid end
function UnitName(unit)
    local u = units[unit]
    if not u then return nil end
    return u.name, u.realm
end
function GetNormalizedRealmName() return "Dreamscythe" end
function GetPlayerInfoByGUID(guid)
    for _, u in pairs(roster) do
        if u.guid == guid then return "Class", u.class, "Race", "Race", 2, u.name, u.realm or "" end
    end
end

-- Commander_Ladder, the web feed (D11): a data table the harness fills, and
-- the names Muster hands back for the next feed run
local ladderData, ladderWants, ladderBare = {}, {}, {}
CommanderLadder = {
    Lookup = function(name, realm, anyRealm)
        ladderBare[name] = anyRealm and true or false
        return ladderData[name .. "-" .. (realm or "Dreamscythe")]
    end,
    Want = function(name, realm)
        ladderWants[name .. "-" .. (realm or "Dreamscythe")] = time()
    end,
    Generated = function() return now - 3600 end,
}
function UnitClass(unit)
    local u = units[unit]
    if not u then return nil end
    return u.class, u.class
end
function UnitExists(unit) return units[unit] ~= nil end
function UnitIsPlayer(unit) return units[unit] and units[unit].isPlayer or false end
function CanInspect(unit, showError)
    assert(showError == false or showError == nil, "CanInspect must not raise the error text")
    return units[unit] and units[unit].inspectable or false
end

-- The one inspect target the client holds, and the calls that move it
local inspected            -- guid whose inventory the client currently knows
local notifyLog, clearLog, honorRequests = {}, 0, 0
local honorReady = false
function NotifyInspect(unit)
    notifyLog[#notifyLog + 1] = units[unit] and units[unit].guid or ("?" .. tostring(unit))
    inspected = nil
    honorReady = false
end
function ClearInspectPlayer() clearLog = clearLog + 1; inspected = nil; honorReady = false end
function HasInspectHonorData() return honorReady end
function RequestInspectHonorData() honorRequests = honorRequests + 1 end

local function UnitByGuid(guid)
    for _, u in pairs(roster) do if u.guid == guid then return u end end
    if guid == playerGuid then return units.player end
end

function GetInventoryItemLink(unit, slot)
    local u = units[unit]
    if not u then return nil end
    if unit ~= "player" and u.guid ~= inspected then return nil end
    local id = u.items[slot]
    return id and Link(id) or nil
end

-- Arena: solo season by default, teams on demand
local usesTeams = false
function GetCurrentArenaSeasonUsesTeams() return usesTeams end
local arenaSeason = 3
function GetCurrentArenaSeason() return arenaSeason end
local ratedRequests = 0
function RequestRatedInfo() ratedRequests = ratedRequests + 1 end
local ownArena = { [2] = { rating = 1850, played = 40, wins = 25, best = 1902 }, [3] = { rating = 0, played = 0, wins = 0 }, [5] = { rating = 0, played = 0, wins = 0 } }
local SIZE_AT = { 2, 3, 5 }
function GetPersonalRatedInfo(index)
    local size = SIZE_AT[index]
    local b = size and ownArena[size]
    if not b then return nil end
    return b.rating, b.best or 0, 0, b.played, b.wins, 4, 2, 0, 0, 0, 0, size
end
function GetInspectArenaData(index)
    local u = UnitByGuid(inspected)
    local size = SIZE_AT[index]
    local b = u and u.arena and size and u.arena[size]
    if not b then return nil end
    return b.rating, b.played, b.wins, 0, 0, 0, size
end
local ownTeams = {
    [1] = { name = "Bad Manners", size = 2, teamRating = 1902, played = 50, wins = 30, playerRating = 1877 },
    [2] = { name = "Trio", size = 3, teamRating = 1610, played = 12, wins = 5, playerRating = 1590 },
}
function GetArenaTeam(index)
    local t = ownTeams[index]
    if not t then return nil end
    return t.name, t.size, t.teamRating, 5, 3, t.played, t.wins, 20, 40, 3, t.playerRating
end
function GetInspectArenaTeamData(index)
    local t = ownTeams[index]
    if not t or not inspected then return nil end
    return t.name, t.size, t.teamRating, t.played, t.wins, 40, t.playerRating
end

-- Tooltip: unit-aware
GameTooltip.SetOwner = function(s, owner) s.__owner = owner end
GameTooltip.GetOwner = function(s) return s.__owner end
GameTooltip.SetText = function(s, text) s.__lines = { text }; s.__title = text end
GameTooltip.GetUnit = function(s) return s.__unitName, s.__unit end
GameTooltip.SetUnit = function(s, unit)
    s.__unit, s.__unitName = unit, UnitName(unit)
    s.__lines = { UnitName(unit) or "?" }
    s.__shown = true
    if s.__scripts.OnTooltipSetUnit then s.__scripts.OnTooltipSetUnit(s) end
end
GameTooltip.Hide = function(s) s.__shown = false; s.__unit = nil; s.__lines = {} end
GameTooltip.__shown = false
local function TooltipHas(pattern)
    for _, line in ipairs(GameTooltip.__lines) do
        if tostring(line):find(pattern) then return true end
    end
    return false
end
local function TooltipCount(pattern)
    local n = 0
    for _, line in ipairs(GameTooltip.__lines) do
        if tostring(line):find(pattern) then n = n + 1 end
    end
    return n
end

-- hooksecurefunc: the original runs, then the hook, with the same arguments
function hooksecurefunc(name, hook)
    local original = _G[name]
    _G[name] = function(...)
        local results = { original(...) }
        hook(...)
        return unpack(results)
    end
end

-- Blizzard's friends list (D13): the button update Muster hooks
FRIENDS_BUTTON_TYPE_WOW = 3
local friendsList = {}
C_FriendList = { GetFriendInfoByIndex = function(i) return friendsList[i] end }
function FriendsFrame_UpdateFriendButton(button)
    button.buttonType = FRIENDS_BUTTON_TYPE_WOW
    button.id = button.index
    local info = friendsList[button.index]
    button.info:SetText(info and info.area or "")
end

-- The guild roster's rows and its data
local guildRoster = {}
function GetGuildRosterInfo(index)
    local g = guildRoster[index]
    if not g then return nil end
    return g.name, "Member", 2, 70, "Mage", "Shattrath City", "", "", true, 0, g.class
end
function Ambiguate(name) return (name:gsub("%-Dreamscythe$", "")) end
local guildRow = CreateFrame("Button", "GuildFrameButton1")

-- The group finder's search results (its own addon loads later, section E4)
local lfgResults = {}
C_LFGList = {
    GetSearchResultInfo = function(id) return lfgResults[id] and lfgResults[id].info end,
    GetSearchResultPlayerInfo = function(id, i) return lfgResults[id] and lfgResults[id].members[i] end,
}

-- The character panel: PaperDollFrame with its model
PaperDollFrame = CreateFrame("Frame", "PaperDollFrame")
CharacterModelFrame = CreateFrame("PlayerModel", "CharacterModelFrame", PaperDollFrame)
PaperDollFrame:Hide()

-- Blizzard_InspectUI is load-on-demand; the harness loads it later
local inspectLoaded = false
C_AddOns.IsAddOnLoaded = function(name) return name == "Blizzard_InspectUI" and inspectLoaded end

-- ===========================================================================
-- Load the real framework + addon
-- ===========================================================================

local function Load(path)
    local chunk = assert(loadfile(path))
    chunk()
end

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
Load(ADDONS .. "/Commander_Muster/CommanderMusterData.lua")
Load(ADDONS .. "/Commander_Muster/CommanderMusterEngine.lua")
Load(ADDONS .. "/Commander_Muster/CommanderMusterDB.lua")
Load(ADDONS .. "/Commander_Muster/CommanderMuster.lua")
Load(ADDONS .. "/Commander_Muster/CommanderMusterSurfaces.lua")

local function Fire(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    for _, frame in ipairs(list) do
        local handler = frame.__scripts.OnEvent
        if handler then handler(frame, event, ...) end
    end
end

-- Answer an inspect: the client now knows this GUID's inventory
local function AnswerInspect(guid)
    inspected = guid
    Fire("INSPECT_READY", guid)
end
local function AnswerHonor()
    honorReady = true
    Fire("INSPECT_HONOR_UPDATE")
end

Fire("ADDON_LOADED", "Commander_Muster")
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD")
Fire("PVP_RATED_STATS_UPDATE")

local readout = _G.CommanderMusterCharacterReadout
local E = CommanderMusterEngine

-- ===========================================================================
-- A. Login: our own record and the character readout
-- ===========================================================================

CHECK(#harnessFailedErrors == 0, "login raised no errors", harnessFailedErrors[1])
CHECK(CommanderMusterDB.EnableMuster == true, "defaults applied")
CHECK(ratedRequests >= 1, "a teamless season asks for rated info at login", ratedRequests)
CHECK(readout ~= nil, "the character readout exists")

do
    local rec = CommanderMuster.RecordFor(playerGuid)
    CHECK(rec and rec.result, "our own record is scored at login")
    -- head 145 + chest 145 + bracers (88 green: (88-8)/2*0.5625*1.8618 = 41) + trinket (115 rare: 66)
    -- + 2H (125 epic: 307) + ranged (115 rare: 37)
    CHECK(rec.result.score == 145 + 145 + 41 + 66 + 307 + 37, "own score adds up slot by slot", rec.result.score)
    CHECK(rec.result.count == 6, "six pieces counted", rec.result.count)
    CHECK(rec.result.complete == true, "everything was cached")
    CHECK(rec.result.weakest and rec.result.weakest.slot == 9, "weakest piece is the old bracers")
    CHECK(rec.arena.known and rec.arena[2] and rec.arena[2].rating == 1850, "own 2v2 rating read from the personal rated info")
    CHECK(rec.arena[3] and rec.arena[3].rating == 0, "an unplayed bracket is present but zero")
    CHECK(rec.arena[2].best == 1902 and rec.arena[2].bestFromServer, "own season high read from the second return",
        rec.arena[2].best)
    CHECK(rec.arena[3].best == nil, "an unplayed bracket has no best")
    local r = CommanderMuster.RatingsFor(playerGuid)
    CHECK(r and r[2].rating == 1850 and r[2].source == "live" and r[2].best == 1902,
        "RatingsFor reads our own live rating and season high")
    CHECK(CommanderMuster.RatingsFor("player")[2].rating == 1850, "a unit token works too")
    local line = CommanderMuster.RatingsLine("Devinp")
    CHECK(line and line:find("2s") and line:find("1850") and not line:find("%d[mhd]|r"),
        "the line by bare name, live so with no age", line)
end

PaperDollFrame:Show()
CHECK(readout:IsShown(), "readout shows with the paper doll")
CHECK(readout.line1:GetText():find("Gear score") and readout.line1:GetText():find("741"), "line 1 carries the score", readout.line1:GetText())
CHECK(readout.line1:GetText():find("ilvl 1%d%d"), "line 1 carries the average item level", readout.line1:GetText())
CHECK(readout.line2:GetText():find("Arena") and readout.line2:GetText():find("2v2") and readout.line2:GetText():find("1850"), "line 2 carries the rated bracket", readout.line2:GetText())
CHECK(not readout.line2:GetText():find("3v3"), "an unplayed bracket is left off the readout", readout.line2:GetText())

-- Hovering the readout opens the breakdown
readout.__scripts.OnEnter(readout)
CHECK(GameTooltip.__title == "Devinp", "breakdown is titled with the name")
CHECK(TooltipHas("Weakest piece: Wrist"), "breakdown names the weakest piece")
CHECK(TooltipHas("Warbringer Chestguard"), "breakdown lists the pieces")
CHECK(TooltipHas("2v2") and TooltipHas("25–15"), "breakdown shows the arena record")
CHECK(TooltipHas("25–15.*best.*1902"), "breakdown shows the season best after the win–loss")
CHECK(not TooltipHas("Best: the highest"), "our own server high needs no footnote")
readout.__scripts.OnLeave(readout)
CHECK(readout.line2:GetText():find("1850") and not readout.line2:GetText():find("1902"),
    "the readout's arena line stays the current rating", readout.line2:GetText())

-- ===========================================================================
-- B. Late item data on our own kit
-- ===========================================================================

do
    cached[28429] = nil   -- the two-hander drops out of the cache
    Fire("PLAYER_EQUIPMENT_CHANGED", 16)
    local rec = CommanderMuster.RecordFor(playerGuid)
    CHECK(rec.result.complete == false, "an uncached piece marks the record incomplete")
    CHECK(loadRequests[28429] and loadRequests[28429] >= 1, "the piece was requested from the server")
    CHECK(readout.line1:GetText():find("…"), "readout says the score is still settling", readout.line1:GetText())
    CHECK(rec.result.score == 741 - 307, "the uncached piece is left out, not invented", rec.result.score)
    cached[28429] = true
    Fire("GET_ITEM_INFO_RECEIVED", 28429, true)
    rec = CommanderMuster.RecordFor(playerGuid)
    CHECK(rec.result.complete == true and rec.result.score == 741, "the piece is scored once it arrives", rec.result.score)
    CHECK(not readout.line1:GetText():find("…"), "readout settles", readout.line1:GetText())
end

-- ===========================================================================
-- C. Mouseover: the quiet inspect round trip
-- ===========================================================================

Place("mouseover", roster.bob)
GameTooltip:SetUnit("mouseover")
CHECK(#notifyLog == 1 and notifyLog[1] == roster.bob.guid, "first hover of a stranger sends NotifyInspect", notifyLog[1])
CHECK(not TooltipHas("Gear score"), "nothing is printed before the answer")
AnswerInspect(roster.bob.guid)
CHECK(honorRequests == 1, "gear arrived, the honor page is asked for")
CHECK(clearLog == 0, "the inspect is held open while the honor page is pending")
CHECK(not TooltipHas("Gear score"), "still nothing printed until the record is whole")
AnswerHonor()
CHECK(clearLog == 1, "ClearInspectPlayer after the answer")
CHECK(TooltipHas("Gear score"), "tooltip rebuilt with the score line")
CHECK(TooltipHas("Arena") and TooltipHas("1912"), "tooltip carries the 2v2 rating")
CHECK(TooltipCount("Gear score") == 1, "the score line appears once")
do
    local rec = CommanderMuster.RecordFor(roster.bob.guid)
    CHECK(rec and rec.class == "HUNTER", "the record knows the class")
    -- hunter: ranged (115 rare: 37 x 5.3224 = 196.9), 2H 125 epic 307 x 0.3164 = 97.1,
    -- head 186, chest 186, trinket 141 epic: (141-26)/1.2*0.5625*1.8618 = 100
    CHECK(rec.result.score == math.floor(186 + 186 + 100 + 307 * 0.3164 + 37 * 5.3224), "hunter weighting applied to the stranger", rec.result.score)
end

-- Second hover: cache hit, synchronous, no new inspect
GameTooltip:Hide()
GameTooltip:SetUnit("mouseover")
CHECK(#notifyLog == 1, "a remembered player costs no second inspect")
CHECK(TooltipHas("Gear score") and TooltipHas("1912"), "lines come straight from the book")

-- What a stranger's inspect leaves on disk
do
    local players = CommanderMusterBests.players
    local entry = players[roster.bob.guid]
    CHECK(entry and entry[2] and entry[2].best == 1912 and entry.name == "Bob", "Bob's 2v2 best is in the saved ledger")
    CHECK(entry and entry[3] == nil, "his unplayed brackets are not")
    CHECK(entry and entry.key == "Bob-Dreamscythe", "his ledger entry is keyed by Name-Realm")
    local r = CommanderMuster.RatingsFor("Bob")
    CHECK(r and r[2].rating == 1912 and r[2].source == "live", "RatingsFor finds him by bare name")
    CHECK(CommanderMuster.RatingsFor("Bob-Dreamscythe") and CommanderMuster.RatingsFor(roster.bob.guid),
        "by Name-Realm and by GUID too")
    CHECK(CommanderMusterBests.season == 3, "the ledger is stamped with the season")
    CHECK(players[playerGuid] and players[playerGuid][2].best == 1902, "our own server high is in the ledger too")
end

-- ===========================================================================
-- D. Throttle, newest wins, timeout and backoff
-- ===========================================================================

GameTooltip:Hide()
Place("mouseover", roster.carl)
GameTooltip:SetUnit("mouseover")
CHECK(#notifyLog == 1, "inside the cooldown nothing goes out yet")
Place("mouseover", roster.dave)
GameTooltip:SetUnit("mouseover")
Advance(2)
CHECK(#notifyLog == 2 and notifyLog[2] == roster.dave.guid, "after the cooldown the NEWEST hover is inspected", notifyLog[2])
AnswerInspect(roster.dave.guid)
AnswerHonor()
Advance(0.5)
CHECK(#notifyLog == 2, "Carl, hovered and then left, is not chased", #notifyLog)

Advance(5)
Place("mouseover", roster.erin)
GameTooltip:SetUnit("mouseover")
CHECK(#notifyLog == 3 and notifyLog[3] == roster.erin.guid, "a fresh hover after the cooldown goes out at once")
local clearsBefore = clearLog
Advance(5.5)   -- no answer ever comes
CHECK(clearLog == clearsBefore + 1, "a timed-out inspect is cleared")
GameTooltip:Hide()
GameTooltip:SetUnit("mouseover")
Advance(2)
CHECK(#notifyLog == 3, "a failed GUID is not retried inside the backoff")
Advance(31)
GameTooltip:Hide()
GameTooltip:SetUnit("mouseover")
CHECK(#notifyLog == 4 and notifyLog[4] == roster.erin.guid, "after the backoff it is tried again")
AnswerInspect(roster.erin.guid)
AnswerHonor()

-- Honor page never answers: gear is kept, arena stays pending
Advance(5)
GameTooltip:Hide()
Place("mouseover", roster.carl)
GameTooltip:SetUnit("mouseover")
CHECK(notifyLog[#notifyLog] == roster.carl.guid, "Carl is inspected now that he is hovered again")
AnswerInspect(roster.carl.guid)
Advance(3.5)
do
    local rec = CommanderMuster.RecordFor(roster.carl.guid)
    CHECK(rec and rec.result.score > 0, "gear survives a silent honor page")
    CHECK(rec.arena.known == false, "arena stays unknown")
    CHECK(TooltipHas("Gear score") and not TooltipHas("Arena"), "tooltip shows the score and no arena line")
end

-- A stranger whose piece is not cached: item data lands BEFORE the honor
-- page does, and the record must still complete
Advance(5)
GameTooltip:Hide()
cached[29011] = nil
Place("mouseover", roster.dave)
CommanderMuster_Forget()
GameTooltip:SetUnit("mouseover")
AnswerInspect(roster.dave.guid)
do
    local rec = CommanderMuster.RecordFor(roster.dave.guid)
    CHECK(rec == nil, "record is not in the book while the honor page is pending")
    cached[29011] = true
    Fire("GET_ITEM_INFO_RECEIVED", 29011, true)
    AnswerHonor()
    rec = CommanderMuster.RecordFor(roster.dave.guid)
    CHECK(rec and rec.result.complete == true and rec.result.score == 145, "item data that lands mid-inspect is scored", rec and rec.result.score)
    CHECK(TooltipHas("Gear score") and not TooltipHas("…"), "tooltip shows the settled score", table.concat(GameTooltip.__lines, " | "))
    CHECK(CommanderMusterBests.players[roster.dave.guid] == nil, "an unrated player is not written to disk")
end

-- A later look at a lower rating keeps the season best
Advance(5)
GameTooltip:Hide()
roster.bob.arena[2] = { rating = 1880, played = 62, wins = 39 }
CommanderMuster_Forget()
Place("mouseover", roster.bob)
GameTooltip:SetUnit("mouseover")
AnswerInspect(roster.bob.guid)
AnswerHonor()
do
    local rec = CommanderMuster.RecordFor(roster.bob.guid)
    CHECK(rec and rec.arena[2].rating == 1880 and rec.arena[2].best == 1912, "a lower rating later keeps the best",
        rec and rec.arena[2].best)
    CHECK(rec and not rec.arena[2].bestFromServer, "a stranger's best is a seen best")
    local entry = CommanderMusterBests.players[roster.bob.guid]
    CHECK(entry and entry[2] and entry[2].played == 62, "the ledger follows his games")
    CHECK(TooltipHas("1880") and not TooltipHas("1912"), "the tooltip's arena line is the current rating")
end

-- ===========================================================================
-- E. Who is never inspected
-- ===========================================================================

do
    local before = #notifyLog
    Advance(5)
    GameTooltip:Hide()
    Place("mouseover", roster.orc)
    GameTooltip:SetUnit("mouseover")
    Advance(2)
    CHECK(#notifyLog == before, "the other faction is never asked for")
    CHECK(not TooltipHas("Gear score"), "and gets no line")
    GameTooltip:Hide()
    Place("mouseover", roster.dummy)
    GameTooltip:SetUnit("mouseover")
    Advance(2)
    CHECK(#notifyLog == before, "a creature is never asked for")
    GameTooltip:Hide()
    Place("mouseover", units.player)
    GameTooltip:SetUnit("mouseover")
    CHECK(#notifyLog == before, "we never inspect ourselves")
    CHECK(TooltipHas("Gear score") and TooltipHas("741"), "our own tooltip reads from our own record")

    -- Combat gate
    inCombat = true
    GameTooltip:Hide()
    Place("mouseover", roster.frank)
    GameTooltip:SetUnit("mouseover")
    Advance(2)
    CHECK(#notifyLog == before, "no inspect in combat by default")
    CommanderMusterDB.InspectInCombat = true
    GameTooltip:Hide()
    GameTooltip:SetUnit("mouseover")
    Advance(2)
    CHECK(#notifyLog == before + 1, "…unless asked to")
    AnswerInspect(roster.frank.guid)
    AnswerHonor()
    inCombat = false
    CommanderMusterDB.InspectInCombat = false
end

-- ===========================================================================
-- E2. Ratings without an inspect: the web feed (D11)
-- ===========================================================================

do
    local before = #notifyLog
    ladderData["Grak-Dreamscythe"] = { [2] = { 2105, 80, 40 }, [3] = { 1990, 30, 30 }, t = now - 13 * 3600 }
    Advance(5)
    GameTooltip:Hide()
    Place("mouseover", roster.orc)
    GameTooltip:SetUnit("mouseover")
    Advance(2)
    CHECK(#notifyLog == before, "the other faction is still never inspected")
    CHECK(TooltipHas("Arena") and TooltipHas("2105") and TooltipHas("1990"),
        "but the feed gives their tooltip an arena line", table.concat(GameTooltip.__lines, " | "))
    CHECK(TooltipHas("13h"), "with the feed's age")
    CHECK(not TooltipHas("Gear score"), "and still no gear line: gear needs an inspect")
    local r = CommanderMuster.RatingsFor("Grak")
    CHECK(r and r[2].rating == 2105 and r[2].source == "feed" and r[2].played == 120 and r[2].wins == 80,
        "RatingsFor by bare name reads the feed")
    CHECK(r and r[5] == nil, "a bracket the feed lacks stays empty")
    r = CommanderMuster.RatingsFor(roster.orc.guid)
    CHECK(r and r[2].rating == 2105, "a GUID never inspected is named through GetPlayerInfoByGUID")

    ladderData["Zed-Nightslayer"] = { [5] = { 1888, 10, 2 } }
    r = CommanderMuster.RatingsFor("Zed-Nightslayer")
    CHECK(r and r[5].rating == 1888 and r[5].at == now - 3600,
        "a cross-realm name nobody has met, timed by the feed file")
    local line = CommanderMuster.RatingsLine("Zed-Nightslayer")
    CHECK(line and line:find("5s") and line:find("1h"), "the one-call line carries the age", line)

    local wantsBefore = 0
    for _ in pairs(ladderWants) do wantsBefore = wantsBefore + 1 end
    CHECK(CommanderMuster.RatingsFor("Creature-0-4372-0-42-1234-0000ABCDEF") == nil
        and CommanderMuster.RatingsFor("Pet-0-4372-0-42-1234-0000ABCDEF") == nil, "a creature or pet GUID has no ratings")
    local wantsAfter = 0
    for _ in pairs(ladderWants) do wantsAfter = wantsAfter + 1 end
    CHECK(wantsAfter == wantsBefore, "and is never handed to the feed as a name")

    CHECK(CommanderMuster.RatingsFor("Nobody-Nightslayer") == nil, "a name nobody knows has no ratings")
    CHECK(ladderWants["Nobody-Nightslayer"] ~= nil, "and is handed to the feed for its next run")
    CHECK(CommanderMuster.RatingsFor(playerGuid) and ladderWants["Devinp-Dreamscythe"] == nil,
        "we never ask the feed for ourselves")

    -- The newest reading wins: what we saw of Bob beats an older feed entry...
    ladderData["Bob-Dreamscythe"] = { [2] = { 1700, 50, 50 }, t = now - 86400 }
    r = CommanderMuster.RatingsFor(roster.bob.guid)
    CHECK(r and r[2].rating == 1880 and r[2].source ~= "feed", "what we saw beats an older feed", r and r[2].rating)
    CHECK(r and r[2].best == 1912, "and the season best still comes from the ledger")
    -- ...and a newer feed beats what we saw
    ladderData["Bob-Dreamscythe"] = { [2] = { 1950, 70, 52 }, t = now }
    r = CommanderMuster.RatingsFor(roster.bob.guid)
    CHECK(r and r[2].rating == 1950 and r[2].source == "feed" and r[2].best == 1950,
        "a newer feed beats what we saw", r and r[2].rating)
    ladderData["Bob-Dreamscythe"] = nil
    GameTooltip:Hide()
end

-- ===========================================================================
-- E3. Group lookups (D12): party members one at a time, behind any hover
-- ===========================================================================

do
    Advance(5)
    Place("mouseover", nil)
    Place("party1", roster.hank)
    Place("party2", roster.ivy)
    Place("party3", roster.jon)
    local before = #notifyLog
    Fire("GROUP_ROSTER_UPDATE")
    Advance(1.1)
    CHECK(#notifyLog == before + 1 and notifyLog[#notifyLog] == roster.hank.guid,
        "a roster change looks up the first party member", notifyLog[#notifyLog])
    AnswerInspect(roster.hank.guid)
    AnswerHonor()
    local r = CommanderMuster.RatingsFor("party1")
    CHECK(r and r[2].rating == 1650, "the party member's rating is known")

    -- A hover that arrives now goes before the next member
    CommanderMuster_Forget()
    Place("mouseover", roster.frank)
    GameTooltip:SetUnit("mouseover")
    Advance(2)
    CHECK(notifyLog[#notifyLog] == roster.frank.guid, "a hover goes before the group", notifyLog[#notifyLog])
    AnswerInspect(roster.frank.guid)
    AnswerHonor()
    GameTooltip:Hide()
    Place("mouseover", nil)
    Advance(2)
    CHECK(notifyLog[#notifyLog] == roster.ivy.guid, "then the group carries on", notifyLog[#notifyLog])
    AnswerInspect(roster.ivy.guid)
    AnswerHonor()
    r = CommanderMuster.RatingsFor("Ivy-Nightslayer")
    CHECK(r and r[3].rating == 1777, "a cross-realm member is found by Name-Realm")
    CHECK(CommanderMusterBests.players[roster.ivy.guid].key == "Ivy-Nightslayer", "the ledger keys her by her own realm")

    local count = #notifyLog
    Advance(20)
    CHECK(#notifyLog == count, "a member out of reach is passed over")
    roster.jon.inspectable = true
    Advance(16)
    CHECK(notifyLog[#notifyLog] == roster.jon.guid, "and looked up once in reach", notifyLog[#notifyLog])
    AnswerInspect(roster.jon.guid)
    AnswerHonor()

    count = #notifyLog
    Fire("GROUP_ROSTER_UPDATE")
    Advance(20)
    CHECK(#notifyLog == count, "an answered group is not looked up again inside half an hour")

    Advance(1801)
    inCombat = true
    Fire("GROUP_ROSTER_UPDATE")
    Advance(2)
    CHECK(#notifyLog == count, "no group lookups in combat")
    inCombat = false
    Fire("PLAYER_REGEN_ENABLED")
    Advance(1.1)
    CHECK(#notifyLog == count + 1 and notifyLog[#notifyLog] == roster.hank.guid,
        "leaving combat resumes them, half an hour on", notifyLog[#notifyLog])
    CommanderMusterDB.InspectGroup = false
    AnswerInspect(roster.hank.guid)
    AnswerHonor()
    count = #notifyLog
    Fire("GROUP_ROSTER_UPDATE")
    Advance(20)
    CHECK(#notifyLog == count, "Look Up Your Group off: nothing more goes out")
    CommanderMusterDB.InspectGroup = true

    Place("party1", nil)
    Place("party2", nil)
    Place("party3", nil)
    CommanderMuster_Forget()
end

-- ===========================================================================
-- E4. Blizzard's lists (D13): friends, guild roster, group finder
-- ===========================================================================

do
    ladderData["Kay-Dreamscythe"] = { [3] = { 2010, 40, 20 }, t = now - 7200 }
    friendsList[1] = { name = "Kay", guid = "Player-0-KAY", connected = true, area = "Shattrath City" }
    friendsList[2] = { name = "Nemo", connected = true, area = "Ironforge" }
    local holder = CreateFrame("Frame")
    local kay = { index = 1, info = holder:CreateFontString() }
    FriendsFrame_UpdateFriendButton(kay)
    local text = kay.info:GetText() or ""
    CHECK(text:find("^3s ") and text:find("2010") and text:find("Shattrath City"),
        "a friend's ratings lead the line, before their zone", text)
    FriendsFrame_UpdateFriendButton(kay)
    local _, times = (kay.info:GetText() or ""):gsub("3s ", "")
    CHECK(times == 1, "an update never doubles them", kay.info:GetText())
    local nemo = { index = 2, info = holder:CreateFontString() }
    FriendsFrame_UpdateFriendButton(nemo)
    CHECK(nemo.info:GetText() == "Ironforge", "a friend nobody knows keeps the plain line", nemo.info:GetText())
    CHECK(ladderWants["Nemo-Dreamscythe"] ~= nil, "and is handed to the feed")
    -- Ladder L8: a name with no realm says so, so Ladder may answer from the
    -- other realm and the feed tries them all; a written realm never does
    CHECK(ladderBare["Nemo"] == true, "a bare name is passed on as realm-unknown")
    CommanderMuster.RatingsFor("Nemo-Nightslayer")
    CHECK(ladderBare["Nemo"] == false, "...and a Name-Realm is not")
    CommanderMusterDB.RatingsOnLists = false
    FriendsFrame_UpdateFriendButton(kay)
    CHECK(kay.info:GetText() == "Shattrath City", "the setting turns them off", kay.info:GetText())
    CommanderMusterDB.RatingsOnLists = true

    guildRoster[3] = { name = "Kay-Dreamscythe", class = "MAGE" }
    guildRoster[4] = { name = "Nemo-Dreamscythe", class = "MAGE" }
    guildRow.guildIndex = 3
    GameTooltip:Hide()
    guildRow.__scripts.OnEnter(guildRow)
    CHECK(GameTooltip:GetOwner() == guildRow and TooltipHas("Kay") and TooltipHas("Arena") and TooltipHas("2010")
        and TooltipHas("2h"), "hovering a guild member shows their ratings with the feed's age",
        table.concat(GameTooltip.__lines, " | "))
    guildRow.__scripts.OnLeave(guildRow)
    CHECK(not GameTooltip.__shown, "and leaving hides them")
    guildRow.guildIndex = 4
    GameTooltip.__owner = nil
    guildRow.__scripts.OnEnter(guildRow)
    CHECK(GameTooltip:GetOwner() ~= guildRow, "a member nobody knows gets no tooltip")

    -- The group finder's own addon loads after login
    function LFGBrowseSearchEntry_Update(entry) end
    LFGBrowseSearchEntryTooltip = CreateFrame("Frame")
    LFGBrowseSearchEntryTooltip:Show()
    Fire("ADDON_LOADED", "Blizzard_GroupFinder_VanillaStyle")
    lfgResults[7] = {
        info = { numMembers = 2,
            leaderPvpRatingInfo = { { bracket = 0, rating = 1534, activityName = "Arena 2v2", tier = 0 } } },
        members = { { name = "Kay", classFilename = "MAGE", isLeader = true }, { name = "Nemo" } },
    }
    local entry = CreateFrame("Button")
    entry.resultID = 7
    LFGBrowseSearchEntry_Update(entry)
    CHECK(entry.__scripts.OnEnter ~= nil, "a listing row is hooked the first time Blizzard fills it")
    entry.__scripts.OnEnter(entry)
    CHECK(GameTooltip:GetOwner() == entry and TooltipHas("Arena ratings") and TooltipHas("2010"),
        "hovering a listing shows its members' ratings", table.concat(GameTooltip.__lines, " | "))
    CHECK(TooltipHas("leader") and TooltipHas("not known"), "the leader is marked, an unknown member says so")
    CHECK(TooltipHas("Listing: Arena 2v2 1534"), "the listing's own leader rating is shown when sent")
    entry.__scripts.OnLeave(entry)

    lfgResults[8] = { info = { numMembers = 1, leaderPvpRatingInfo = {} }, members = { { name = "Nemo" } } }
    local quiet = CreateFrame("Button")
    quiet.resultID = 8
    LFGBrowseSearchEntry_Update(quiet)
    GameTooltip.__owner = nil
    quiet.__scripts.OnEnter(quiet)
    CHECK(GameTooltip:GetOwner() ~= quiet, "a listing of unknowns shows nothing")
    GameTooltip:Hide()
end

-- ===========================================================================
-- F. Blizzard's inspect window: ride along, never interfere
-- ===========================================================================

InspectFrame = CreateFrame("Frame", "InspectFrame")
InspectPaperDollFrame = CreateFrame("Frame", "InspectPaperDollFrame", InspectFrame)
InspectModelFrame = CreateFrame("PlayerModel", "InspectModelFrame", InspectPaperDollFrame)
InspectFrame:Hide()
inspectLoaded = true
Fire("ADDON_LOADED", "Blizzard_InspectUI")
local inspectReadout = _G.CommanderMusterInspectReadout
CHECK(inspectReadout ~= nil, "the inspect readout is built when Blizzard_InspectUI loads")

-- Forget Frank so the window's answer is what fills him in
CommanderMuster_Forget()
CHECK(CommanderMuster.RecordFor(roster.frank.guid) == nil, "forget empties the book")

Place("target", roster.frank)
InspectFrame.unit = "target"          -- InspectFrame_Show sets this before NotifyInspect
notifyLog[#notifyLog + 1] = "blizzard"
inspected = nil
do
    local before = #notifyLog
    Advance(5)
    GameTooltip:Hide()
    Place("mouseover", roster.bob)
    CommanderMuster_Forget()
    GameTooltip:SetUnit("mouseover")
    Advance(2)
    CHECK(#notifyLog == before, "no quiet inspect while the window is opening on somebody")
end
InspectFrame:Show()
InspectPaperDollFrame:Show()
AnswerInspect(roster.frank.guid)
CHECK(CommanderMuster.RecordFor(roster.frank.guid) ~= nil, "the window's answer fills the book")
CHECK(inspectReadout:IsShown() and inspectReadout.line1:GetText():find("Gear score"), "inspect readout painted from the window's answer", inspectReadout.line1:GetText())
CHECK(inspectReadout.line2:GetText():find("…"), "arena pending on the inspect readout", inspectReadout.line2:GetText())
CHECK(honorRequests >= 1, "the honor page was requested for the window's target")
AnswerHonor()
CHECK(inspectReadout.line2:GetText():find("3v3") and inspectReadout.line2:GetText():find("2210"), "inspect readout carries the 3v3 rating", inspectReadout.line2:GetText())
inspectReadout.__scripts.OnEnter(inspectReadout)
CHECK(TooltipHas("30.*best.*2210"), "the inspect breakdown shows the remembered best", table.concat(GameTooltip.__lines, " | "))
CHECK(TooltipHas("Best: the highest Muster has seen"), "a seen best is footnoted")
inspectReadout.__scripts.OnLeave(inspectReadout)
do
    local clears = clearLog
    Advance(1)
    CHECK(clearLog == clears, "we never ClearInspectPlayer under an open window")
end
InspectFrame.unit = nil
InspectFrame:Hide()
-- The mock's Hide runs no OnHide; the client does, and a hidden parent
-- hides its children anyway. Run the hook by hand to prove it clears.
InspectFrame.__scripts.OnHide(InspectFrame)
CHECK(not inspectReadout:IsShown(), "inspect readout hides with the window")

-- Hovering Frank now reads from the book the window filled
Advance(5)
GameTooltip:Hide()
Place("mouseover", roster.frank)
do
    local before = #notifyLog
    GameTooltip:SetUnit("mouseover")
    CHECK(#notifyLog == before, "the window's answer spares the hover an inspect")
    CHECK(TooltipHas("2210"), "and the tooltip has his rating")
end

-- ===========================================================================
-- G. Teams season
-- ===========================================================================

usesTeams = true
Fire("ARENA_TEAM_UPDATE")
do
    local rec = CommanderMuster.RecordFor(playerGuid)
    CHECK(rec.arena[2] and rec.arena[2].teamName == "Bad Manners", "team name read in a teams season")
    CHECK(rec.arena[2].rating == 1877 and rec.arena[2].teamRating == 1902, "personal rating shown, team rating kept")
    CHECK(rec.arena[3] and rec.arena[3].rating == 1590, "3v3 team read")
    CHECK(rec.arena[5] == nil, "no 5v5 team")
    readout.__scripts.OnEnter(readout)
    CHECK(TooltipHas("Bad Manners") and TooltipHas("team 1902"), "breakdown shows team name and team rating")
    readout.__scripts.OnLeave(readout)
end
-- and a stranger in a teams season
Advance(5)
GameTooltip:Hide()
CommanderMuster_Forget()
Place("mouseover", roster.bob)
GameTooltip:SetUnit("mouseover")
AnswerInspect(roster.bob.guid)
AnswerHonor()
do
    local rec = CommanderMuster.RecordFor(roster.bob.guid)
    CHECK(rec.arena[2] and rec.arena[2].teamName == "Bad Manners" and rec.arena[2].rating == 1877, "inspect team data read in a teams season")
end
usesTeams = false

-- ===========================================================================
-- G2. A new season empties the ledger
-- ===========================================================================

arenaSeason = 0
Fire("PLAYER_ENTERING_WORLD")
CHECK(CommanderMusterBests.players[roster.frank.guid] ~= nil, "a season that still reads 0 empties nothing")
arenaSeason = 4
Fire("PLAYER_ENTERING_WORLD")
CHECK(CommanderMusterBests.season == 4 and CommanderMusterBests.players[roster.frank.guid] == nil,
    "a new season empties the ledger")
CHECK(CommanderMusterBests.players[playerGuid] ~= nil, "and our own best is written straight back")
Advance(5)
GameTooltip:Hide()
CommanderMuster_Forget()
Place("mouseover", roster.frank)
GameTooltip:SetUnit("mouseover")
AnswerInspect(roster.frank.guid)
AnswerHonor()
CHECK(CommanderMusterBests.players[roster.frank.guid] ~= nil, "the new season's ledger fills again")

-- ===========================================================================
-- H. Settings and slash commands
-- ===========================================================================

CommanderMusterDB.EnableMuster = false
Commander.Notify(COMMANDER_MUSTER_EVENTS.UPDATE)
CHECK(not readout:IsShown(), "master switch off hides the readout")
do
    local before = #notifyLog
    Advance(5)
    GameTooltip:Hide()
    CommanderMuster_Forget()
    GameTooltip:SetUnit("mouseover")
    Advance(2)
    CHECK(#notifyLog == before and not TooltipHas("Gear score"), "off: no lines, no inspect")
    CHECK(CommanderMuster.RatingsFor(playerGuid) == nil and CommanderMuster.RatingsLine("Grak") == nil,
        "off: no ratings for any other addon either")
end
CommanderMusterDB.EnableMuster = true
Commander.Notify(COMMANDER_MUSTER_EVENTS.UPDATE)
CHECK(readout:IsShown(), "back on, the readout returns")

CommanderMusterDB.ShowArenaOnReadout = false
Commander.Notify(COMMANDER_MUSTER_EVENTS.UPDATE)
CHECK(not readout.line2:IsShown(), "arena line can be turned off")
CommanderMusterDB.ShowArenaOnReadout = true
CommanderMusterDB.TooltipItemLevel = false
Commander.Notify(COMMANDER_MUSTER_EVENTS.UPDATE)
GameTooltip:Hide()
Place("mouseover", units.player)
GameTooltip:SetUnit("mouseover")
CHECK(TooltipHas("Gear score") and not TooltipHas("ilvl"), "tooltip item level can be turned off")
CommanderMusterDB.TooltipItemLevel = true

CHECK(type(SlashCmdList.COMMANDERUI_MUSTER) == "function", "slash command registered")
CHECK(SLASH_COMMANDERUI_MUSTER1 == "/cmuster" and SLASH_COMMANDERUI_MUSTER2 == "/gs", "both slash spellings")
SlashCmdList.COMMANDERUI_MUSTER("report")
CHECK(PrintedMatching and true or true, "report ran")
do
    local found = false
    for _, line in ipairs(printLog) do if line:find("gear score") then found = true end end
    CHECK(found, "report prints the score")
end
SlashCmdList.COMMANDERUI_MUSTER("forget")
CHECK(CommanderMuster.RecordFor(roster.bob.guid) == nil, "forget via slash empties the book")
CHECK(CommanderMusterBests.players[roster.frank.guid] ~= nil, "forget leaves the season bests alone")

-- Settings page renders
do
    local ok, err = pcall(function()
        for _, cat in ipairs(categories) do
            if cat.__title == "Muster" then
                local panel = cat.__panel
                if panel.__scripts.OnShow then panel.__scripts.OnShow(panel) end
            end
        end
    end)
    CHECK(ok, "settings page refreshes without error", err)
end

CHECK(#harnessFailedErrors == 0, "no errors were swallowed by the error handler", harnessFailedErrors[1])

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
