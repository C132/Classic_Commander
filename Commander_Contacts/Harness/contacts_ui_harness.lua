-- Commander Contacts UI harness (luajit).
--
-- Loads the REAL shared framework (CommanderSettingsUI.lua, CommanderEvents.lua)
-- plus all four Commander_Contacts files under the suite's permissive widget
-- mock, then drives the whole lifecycle without a client: login, the
-- settings panel, chat events filing into threads, party sessions opening
-- and closing on the roster, the window on all three tabs, the compose box
-- sending, the popups, and every slash entry point.
--
-- It exists to catch what the store smoke cannot: nil-global calls, wrong
-- widget signatures, and the wiring between the four files. The one check it
-- matters most for is R1 -- that Restore Defaults cannot delete a thread.
--
--   /opt/homebrew/bin/luajit contacts_ui_harness.lua


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
local function EQ(got, want, label)
    CHECK(got == want, label, string.format("got %s want %s", tostring(got), tostring(want)))
end

-- ===========================================================================
-- WoW mock (the shared suite harness preamble)
-- ===========================================================================

-- A REAL epoch: the login prune subtracts months from time(), so a toy clock
-- would sit below the cutoff and quietly prove nothing. GetTime stays a small
-- monotonic session clock, exactly as the client reports it.
local now = 1786000000
function time() return now end
function date(fmt, t) return os.date(fmt or "%c", t or now) end
function GetTime() return now - 1785999000 end
function GetBuildInfo() return "2.5.6", "68502", "Jul 7 2026", 20506 end

local printLog = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    printLog[#printLog + 1] = table.concat(parts, " ")
end

local function PrintedMatching(pattern)
    for _, line in ipairs(printLog) do
        if line:find(pattern) then return true end
    end
    return false
end

local harnessFailedErrors = {}
function geterrorhandler()
    return function(err)
        harnessFailedErrors[#harnessFailedErrors + 1] = tostring(err)
    end
end

local VALID_FLAGS = { [""] = true, OUTLINE = true, THICKOUTLINE = true, MONOCHROME = true,
    ["OUTLINE, MONOCHROME"] = true }

local allFontStrings = {}
local allTextures = {}
local frames = {}
local eventRegistry = {}

local NUMERIC_GETTERS = {
    GetWidth = 300, GetHeight = 0, GetScale = 1, GetEffectiveScale = 1,
    GetFrameLevel = 2, GetLeft = 0, GetBottom = 0, GetTop = 0, GetRight = 0,
    GetVerticalScroll = 0, GetVerticalScrollRange = 0, GetStringWidth = 10,
    GetID = 1, GetNumPoints = 1, GetAlpha = 1, GetValue = 0,
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
        local fn = function(s)
            local t = NewWidget("Texture")
            t.__parent = s
            allTextures[#allTextures + 1] = t
            return t
        end
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
        local fn = function(s, name, handler)
            -- HookScript must CHAIN, never replace (a suite harness lesson)
            local existing = s.__scripts[name]
            if key == "HookScript" and existing then
                s.__scripts[name] = function(...) existing(...) handler(...) end
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
    if key == "RegisterEvent" or key == "RegisterUnitEvent" then
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
    if key == "SetTextColor" then
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
    if key == "SetAlpha" then
        local fn = function(s, a) s.__alpha = a end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetPoint" then
        local fn = function() return "CENTER", nil, "CENTER", 0, 0 end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetPoint" then
        local fn = function(s, point, rel, relPoint, x, y)
            s.__points = s.__points or {}
            s.__points[#s.__points + 1] =
                { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
        end
        rawset(self, key, fn)
        return fn
    end
    if key == "ClearAllPoints" then
        local fn = function(s) s.__points = nil end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetFrameLevel" then
        local fn = function(s, level) s.__level = level end
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
    f.__parent = parent
    if frameType == "CheckButton" or (template and template:find("CheckButton")) then
        f.Text = NewWidget("FontString")
    end
    if template and template:find("BasicFrameTemplate") then
        -- The permissive metatable hands back a bare function for an unknown
        -- key, which explodes on a child method call — these have to be real
        f.CloseButton = NewWidget("Button")
        f.TitleText = NewWidget("FontString")
        f.Bg = NewWidget("Texture")
        f.TitleBg = NewWidget("Texture")
        f.Inset = NewWidget("Frame")
        f.NineSlice = NewWidget("Frame")
    end
    if name then _G[name] = f end
    frames[#frames + 1] = f
    return f
end

UIParent = NewWidget("Frame", "UIParent")
GameTooltip = NewWidget("GameTooltip", "GameTooltip")
WorldFrame = NewWidget("Frame", "WorldFrame")
UISpecialFrames = {}
tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack

GameFontNormal = NewWidget("Font")
GameFontNormalLarge = NewWidget("Font")
GameFontNormalSmall = NewWidget("Font")
GameFontHighlight = NewWidget("Font")
GameFontHighlightSmall = NewWidget("Font")
GameFontDisableSmall = NewWidget("Font")
GameFontDisable = NewWidget("Font")
NumberFontNormal = NewWidget("Font")

SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2,
    RAID_WARNING = 8959 }
local soundLog = {}
function PlaySound(id) soundLog[#soundLog + 1] = id end
local function KlaxonCount()
    local c = 0
    for _, id in ipairs(soundLog) do
        if id == 8959 then c = c + 1 end
    end
    return c
end
BACKDROP_SLIDER_8_8 = {}

-- FrameXML owns this table on a live client; the addon only adds a key to it and
-- deliberately never assigns the global (that would taint it), so the harness has
-- to stand the table up itself.
StaticPopupDialogs = {}
local popupsShown = {}
function StaticPopup_Show(which)
    popupsShown[#popupsShown + 1] = which
end

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

local function Advance(seconds, step)
    step = step or 0.25
    local elapsed = 0
    while elapsed < seconds do
        now = now + step
        elapsed = elapsed + step
        RunTickers()
    end
end

local dropdownInits = {}
local menuCaptured = {}
function UIDropDownMenu_Initialize(frame, fn) dropdownInits[frame] = fn end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info) menuCaptured[#menuCaptured + 1] = info end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetSelectedValue() end
function UIDropDownMenu_SetText() end
function UIDropDownMenu_EnableDropDown() end
function UIDropDownMenu_DisableDropDown() end
function ToggleDropDownMenu(level, value, frame)
    menuCaptured = {}
    local init = dropdownInits[frame]
    if init then init(frame) end
end

-- ---------------------------------------------------------------------------
-- Fixture-driven unit + combat-log API
-- ---------------------------------------------------------------------------

COMBATLOG_OBJECT_TYPE_PLAYER = 0x00000400
COMBATLOG_OBJECT_REACTION_HOSTILE = 0x00000040
COMBATLOG_OBJECT_REACTION_FRIENDLY = 0x00000010

local F_ENEMY = COMBATLOG_OBJECT_TYPE_PLAYER + COMBATLOG_OBJECT_REACTION_HOSTILE
local F_FRIEND = COMBATLOG_OBJECT_TYPE_PLAYER + COMBATLOG_OBJECT_REACTION_FRIENDLY
local F_MOB = COMBATLOG_OBJECT_REACTION_HOSTILE

-- guid -> { name, realm, class, race, level, guild }
local players = {
    ["P-me"] = { name = "Devinp", realm = "TestRealm", class = "PRIEST", race = "Human", level = 70 },
    ["P-vexa"] = { name = "Vexa", realm = "Blackrock", class = "ROGUE", race = "Undead", level = 70, guild = "Nightfall" },
    ["P-mira"] = { name = "Miralei", realm = "TestRealm", class = "WARLOCK", race = "Orc", level = 70 },
    ["P-ally"] = { name = "Brakk", realm = "TestRealm", class = "WARRIOR", race = "Tauren", level = 70 },
}
local units = { player = "P-me" }
local combat = false

function GetRealmName() return "TestRealm" end
function GetRealZoneText() return "Nagrand Arena" end
function UnitExists(u) return units[u] ~= nil end
function UnitIsPlayer(u) return units[u] ~= nil end
function UnitGUID(u) return units[u] end
function UnitName(u)
    local p = players[units[u] or ""]
    if not p then return nil end
    return p.name, p.realm
end
function UnitClass(u)
    local p = players[units[u] or ""]
    if p then return p.class, p.class end
end
function UnitRace(u)
    local p = players[units[u] or ""]
    if p then return p.race, p.race end
end
function UnitLevel(u)
    local p = players[units[u] or ""]
    return p and p.level or 0
end
function GetGuildInfo(u)
    local p = players[units[u] or ""]
    return p and p.guild or nil
end
function GetPlayerInfoByGUID(guid)
    local p = players[guid]
    if not p then error("no such guid") end
    return p.class, p.class, p.race, p.race, 1, p.name, p.realm
end
function InCombatLockdown() return combat end
function IsInInstance() return false, "none" end

local SPELL_NAMES = {
    [853] = "Hammer of Justice", [1833] = "Cheap Shot", [5211] = "Bash",
    [9005] = "Pounce", [24394] = "Intimidation", [30283] = "Shadowfury",
    [12809] = "Concussion Blow", [7922] = "Charge Stun", [20253] = "Intercept Stun",
    [20549] = "War Stomp", [16922] = "Celestial Focus", [19410] = "Improved Concussive Shot",
    [12355] = "Impact", [20170] = "Seal of Justice", [15269] = "Blackout",
    [18093] = "Pyroclasm", [39796] = "Stoneclaw Stun", [12798] = "Revenge Stun",
    [1513] = "Scare Beast", [10326] = "Turn Evil", [8122] = "Psychic Scream",
    [5782] = "Fear", [6358] = "Seduction", [5484] = "Howl of Terror",
    [5246] = "Intimidating Shout", [2637] = "Hibernate", [22570] = "Maim",
    [3355] = "Freezing Trap Effect", [19386] = "Wyvern Sting", [118] = "Polymorph",
    [20066] = "Repentance", [6770] = "Sap", [1776] = "Gouge", [710] = "Banish",
    [2094] = "Blind", [33786] = "Cyclone", [339] = "Entangling Roots",
    [19975] = "Nature's Grasp", [122] = "Frost Nova", [33395] = "Freeze",
    [19185] = "Entrapment", [19229] = "Improved Wing Clip", [12494] = "Frostbite",
    [23694] = "Improved Hamstring", [605] = "Mind Control", [676] = "Disarm",
    [14251] = "Riposte", [19503] = "Scatter Shot", [31661] = "Dragon's Breath",
    [19306] = "Counterattack", [44041] = "Chastise", [408] = "Kidney Shot",
    [31117] = "Unstable Affliction", [6789] = "Death Coil",
}
function GetSpellInfo(id) return SPELL_NAMES[id] end

RAID_CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    ROGUE = { r = 1, g = 0.96, b = 0.41 },
    PRIEST = { r = 1, g = 1, b = 1 },
    WARLOCK = { r = 0.53, g = 0.53, b = 0.93 },
    MAGE = { r = 0.41, g = 0.80, b = 0.94 },
}
CLASS_ICON_TCOORDS = {
    WARRIOR = { 0, 0.25, 0, 0.25 }, ROGUE = { 0.49, 0.74, 0, 0.25 },
    PRIEST = { 0.49, 0.74, 0.25, 0.5 }, WARLOCK = { 0.74, 0.98, 0.25, 0.5 },
}
SlashCmdList = {}

-- ===========================================================================
-- Contacts-specific mock
--
-- Edit boxes get real focus and real text (the compose box, the notes box
-- and the search box all branch on HasFocus). The social API is a fixture:
-- a friends list, an ignore list, one Battle.net friend, and a group
-- roster the test flips between party, raid and nothing.
-- ===========================================================================

local focused = nil

local RawNewWidget = NewWidget
NewWidget = function(kind, name)
    local widget = RawNewWidget(kind, name)
    rawset(widget, "SetShown", function(self, shown)
        self.__shown = shown and true or false
    end)
    if kind == "EditBox" then
        rawset(widget, "SetFocus", function(self) focused = self end)
        rawset(widget, "ClearFocus", function(self)
            if focused == self then
                focused = nil
                local handler = self.__scripts.OnEditFocusLost
                if handler then handler(self) end
            end
        end)
        rawset(widget, "HasFocus", function(self) return focused == self end)
        rawset(widget, "Enable", function(self) self.__enabled = true end)
        rawset(widget, "Disable", function(self) self.__enabled = false end)
        rawset(widget, "SetText", function(self, text)
            self.__text = text
            local handler = self.__scripts.OnTextChanged
            if handler then handler(self, false) end
        end)
    end
    return widget
end

local function Type(box, text)
    box:SetFocus()
    box.__text = text
    local handler = box.__scripts.OnTextChanged
    if handler then handler(box, true) end
end

local function Enter(box)
    local handler = box.__scripts.OnEnterPressed
    if handler then handler(box) end
end

local function Click(widget, button)
    local handler = widget.__scripts.OnClick
    if handler then handler(widget, button or "LeftButton") end
end

function GetNormalizedRealmName() return "TestRealm" end
LE_PARTY_CATEGORY_INSTANCE = 2
LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Mage", PRIEST = "Priest", ROGUE = "Rogue",
    WARLOCK = "Warlock", WARRIOR = "Warrior" }
LOCALIZED_CLASS_NAMES_FEMALE = {}
UNKNOWNOBJECT = "Unknown"

-- The group the player is in: nil, "PARTY", "RAID" or "INSTANCE"
local groupState = nil
local function SetGroup(kind, members)
    groupState = kind
    for key in pairs(units) do
        if key ~= "player" then units[key] = nil end
    end
    if kind then
        local prefix = kind == "RAID" and "raid" or "party"
        local index = 0
        if kind == "RAID" then
            index = 1
            units["raid1"] = "P-me"
        end
        for _, guid in ipairs(members or {}) do
            index = index + 1
            units[prefix .. index] = guid
        end
        units.__count = index + (kind == "RAID" and 0 or 1)
    else
        units.__count = 0
    end
end
function IsInGroup(category)
    if category == LE_PARTY_CATEGORY_INSTANCE then return groupState == "INSTANCE" end
    return groupState ~= nil
end
function IsInRaid() return groupState == "RAID" end
function GetNumGroupMembers() return units.__count or 0 end

local sent = {}
function SendChatMessage(text, chatType, language, target)
    sent[#sent + 1] = { text = text, chatType = chatType, target = target }
end

local friends = {
    { name = "Miralei", connected = true, className = "Mage", level = 70, area = "Shattrath City",
        notes = "healer", guid = "P-mira", afk = false, dnd = false },
    { name = "Brakk", connected = false, className = nil, level = 0, area = nil,
        notes = "", guid = "P-ally", afk = false, dnd = false },
}
local ignores = { "Troll" }
local friendLog = {}
local showFriendsCalls = 0
C_FriendList = {
    GetNumFriends = function() return #friends end,
    GetFriendInfoByIndex = function(index) return friends[index] end,
    GetNumIgnores = function() return #ignores end,
    GetIgnoreName = function(index) return ignores[index] end,
    ShowFriends = function() showFriendsCalls = showFriendsCalls + 1 end,
    AddFriend = function(name, notes)
        friendLog[#friendLog + 1] = { op = "add", name = name }
        friends[#friends + 1] = { name = name, connected = false, level = 0, notes = notes or "" }
    end,
    RemoveFriend = function(name)
        friendLog[#friendLog + 1] = { op = "remove", name = name }
        for index, friend in ipairs(friends) do
            if friend.name == name then table.remove(friends, index) return true end
        end
        return false
    end,
    SetFriendNotes = function(name, notes)
        friendLog[#friendLog + 1] = { op = "notes", name = name, notes = notes }
        for _, friend in ipairs(friends) do
            if friend.name == name then friend.notes = notes return true end
        end
        return false
    end,
    AddIgnore = function(name)
        friendLog[#friendLog + 1] = { op = "ignore", name = name }
        ignores[#ignores + 1] = name
        return true
    end,
    DelIgnore = function(name)
        friendLog[#friendLog + 1] = { op = "unignore", name = name }
        for index, entry in ipairs(ignores) do
            if entry == name then table.remove(ignores, index) return true end
        end
        return false
    end,
}
local function LastOp(op)
    for index = #friendLog, 1, -1 do
        if friendLog[index].op == op then return friendLog[index] end
    end
    return nil
end

local bnFriends = {
    { bnetAccountID = 77, accountName = "Jordan", battleTag = "Jordan#1234", note = "", isAFK = false,
        isDND = false, customMessage = "raiding tonight",
        gameAccountInfo = { gameAccountID = 9001, clientProgram = "WoW", isOnline = true,
            characterName = "Jordy", className = "Warrior", characterLevel = 70,
            areaName = "Netherstorm", realmName = "TestRealm" } },
}
function BNGetNumFriends() return #bnFriends, 1 end
local bnSent, bnInvites = {}, {}
C_BattleNet = {
    GetFriendAccountInfo = function(index) return bnFriends[index] end,
    GetAccountInfoByID = function(id)
        for _, account in ipairs(bnFriends) do
            if account.bnetAccountID == id then return account end
        end
        return nil
    end,
    SendWhisper = function(id, text) bnSent[#bnSent + 1] = { id = id, text = text } return true end,
    InviteFriend = function(id) bnInvites[#bnInvites + 1] = id end,
}

local invites = {}
C_PartyInfo = { InviteUnit = function(name) invites[#invites + 1] = name end }
local tells = {}
ChatFrameUtil = { SendTell = function(name) tells[#tells + 1] = name end }
local itemRefs = {}
function SetItemRef(link, text, button) itemRefs[#itemRefs + 1] = link end

-- Blizzard's friends window: the two sub-frames and their bottom buttons
FriendsListFrame = NewWidget("Frame", "FriendsListFrame")
IgnoreListFrame = NewWidget("Frame", "IgnoreListFrame")
FriendsFrameAddFriendButton = NewWidget("Button", "FriendsFrameAddFriendButton")
FriendsFrameSendMessageButton = NewWidget("Button", "FriendsFrameSendMessageButton")
FriendsFrameIgnorePlayerButton = NewWidget("Button", "FriendsFrameIgnorePlayerButton")
FriendsFrameUnsquelchButton = NewWidget("Button", "FriendsFrameUnsquelchButton")

local popupData = {}
local realStaticPopupShow = StaticPopup_Show
function StaticPopup_Show(which, arg1, arg2, data)
    popupData[which] = { arg1 = arg1, data = data }
    realStaticPopupShow(which, arg1, arg2, data)
    return { data = data }
end

local function AcceptPopup(which, typed)
    local dialog = StaticPopupDialogs[which]
    if not dialog then return false end
    local record = popupData[which] or {}
    local host = { data = record.data }
    if dialog.hasEditBox then
        local box = NewWidget("EditBox")
        box.__text = typed or ""
        host.editBox = box
        if dialog.OnShow then dialog.OnShow(host, record.data) end
        box.__text = typed or ""
    end
    if dialog.OnAccept then dialog.OnAccept(host, record.data) end
    return true
end

local function LastPopup()
    return popupsShown[#popupsShown]
end

-- ===========================================================================
-- Load the real framework + addon
-- ===========================================================================

local function Load(path)
    assert(loadfile(path))()
end

CommanderConsole_Colors = {
    { text = "Steel (Default)", value = "STEEL", r = 1, g = 1, b = 1 },
    { text = "Fel", value = "FEL", r = 0.5, g = 0.95, b = 0.15 },
    { text = "Class Color", value = "CLASS" },
}
CommanderConsoleDB = { ConsoleColor = "FEL" }

-- Saved variables from a previous session: a thread whose only line is
-- older than the default retention, a group that ended but was left
-- marked active, a remembered tab, and a setting the defaults pass must not
-- overwrite.
CommanderContactsDB = {
    FrameStyle = "WINDOW",
    LastTab = "activity",
    ActiveGroup = "group:3",
    NextID = 4,
    Conversations = {
        ["dm:Old"] = { kind = "dm", name = "Old", messages = {
            { t = now - 200 * 86400, from = "Old", text = "ancient" } },
            created = now - 200 * 86400, updated = now - 200 * 86400 },
        ["dm:Keeper"] = { kind = "dm", name = "Keeper", messages = {
            { t = now - 3600, from = "Keeper", text = "recent |Hitem:19019::::::::70:::::|h[Thunderfury]|h" } },
            created = now - 3600, updated = now - 3600, unread = 1 },
        ["group:3"] = { kind = "group", name = "Old Run", groupType = "PARTY", members = { "Keeper" },
            messages = { { t = now - 7200, from = "Keeper", text = "gg" } },
            started = now - 8000, ended = now - 7000, created = now - 8000, updated = now - 7200 },
    },
}

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
-- A stand-in Commander_Muster: its event table and its record lookup, both
-- present before the addon loads, the way OptionalDeps orders them live.
COMMANDER_MUSTER_EVENTS = { RECORD = "COMMANDER_MUSTER_RECORD" }
local musterRecords = {}
CommanderMuster = { RecordFor = function(guid) return musterRecords[guid] end }

-- Battleground fixture: instance type, zone, the scoreboard and the winner
local instanceType, zoneText = "none", "Nagrand Arena"
function IsInInstance() return instanceType ~= "none", instanceType end
function GetRealZoneText() return zoneText end
function UnitFactionGroup() return "Horde" end
local scoreboard, winner = {}, nil
function GetNumBattlefieldScores() return #scoreboard end
function GetBattlefieldScore(index)
    local row = scoreboard[index]
    if not row then return nil end
    return row.name, row.kb, 0, 0, 0, row.faction, 0, "Orc", row.class, row.class, row.dmg, row.heal, 0, 0
end
function GetBattlefieldWinner() return winner end
players["P-glad"] = { name = "Gladys", realm = "TestRealm", class = "WARRIOR", level = 70, title = "Merciless Gladiator" }
players["P-plain"] = { name = "Plain", realm = "TestRealm", class = "HUNTER", level = 70 }
function UnitPVPName(u)
    local p = players[units[u] or ""]
    if not p then return nil end
    if p.title then return p.title .. " " .. p.name end
    return p.name
end

Load(ADDONS .. "/Commander_Contacts/CommanderContactsStore.lua")
Load(ADDONS .. "/Commander_Contacts/CommanderContactsScout.lua")
Load(ADDONS .. "/Commander_Contacts/CommanderContactsDB.lua")
Load(ADDONS .. "/Commander_Contacts/CommanderContacts.lua")
-- Mutation hook (Orders 3.1 work): CONTACTS_UI=/path of a copy to load instead
Load(os.getenv("CONTACTS_UI") or (ADDONS .. "/Commander_Contacts/CommanderContactsUI.lua"))

local S = CommanderContactsStore
local H = CommanderContacts

local function Fire(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    local copy = {}
    for index, f in ipairs(list) do copy[index] = f end
    for _, f in ipairs(copy) do
        local handler = f.__scripts.OnEvent
        if handler then handler(f, event, ...) end
    end
end

local function NoErrors(label)
    CHECK(#harnessFailedErrors == 0, label, harnessFailedErrors[1])
end

-- A whisper event with the payload in the documented positions: text,
-- sender, then nine fields we do not read, then the GUID and the Battle.net
-- sender id.
local function Whisper(event, text, sender, guid, bnetID)
    Fire(event, text, sender, "Common", "", sender, "", 0, 0, "", 0, 1, guid or "", bnetID or 0)
end

-- ===========================================================================
-- A. Login
-- ===========================================================================

Fire("ADDON_LOADED", "Commander_Contacts")
EQ(CommanderContactsDB.EnableContacts, true, "A1 defaults applied at ADDON_LOADED")
EQ(CommanderContactsDB.FrameStyle, "WINDOW", "A1 a saved setting survives defaults")
EQ(CommanderContactsDB.KeepDays, 90, "A1 a missing setting is filled in")
CHECK(S.Attached(), "A2 the store is attached at ADDON_LOADED")
EQ(CommanderContactsDB.ActiveGroup, nil, "A2 attach cleared the stale active group")
EQ(S.MaxMessages(), 400, "A2 the line cap follows the setting")

Fire("PLAYER_LOGIN")
CHECK(SlashCmdList["COMMANDERUI_CONTACTS"] ~= nil, "A3 the panel registered its slash command")
EQ(SLASH_COMMANDERUI_CONTACTS1, "/ccontacts", "A3 slash command name")
EQ(SLASH_COMMANDERUI_CONTACTS2, "/cfriends", "A3 second slash command")
CHECK(showFriendsCalls >= 1, "A4 the friends list was requested at login")
EQ(S.Conversation("dm:Old"), nil, "A5 the 200-day-old thread was pruned at login")
CHECK(S.Conversation("dm:Keeper") ~= nil, "A5 the recent thread survived")
CHECK(PrintedMatching("dropped 1 old line"), "A5 the prune was reported")
EQ(H.OwnName(), "Devinp", "A6 own name")
EQ(H.OwnRealm(), "TestRealm", "A6 own realm")
EQ(H.Shorten("Bob-TestRealm"), "Bob", "A6 shorten strips own realm without Ambiguate")
EQ(H.Shorten("Bob-Blackrock"), "Bob-Blackrock", "A6 shorten keeps a foreign realm")
CHECK(H.IsSelf("Devinp-TestRealm"), "A6 IsSelf")
EQ(H.TokenForClassName("Mage"), "MAGE", "A7 localised class -> token")
EQ(H.TokenForClassName("Druid"), "DRUID", "A7 unknown class upper-cased")
local ffb = H.FriendsFrameButtons()
CHECK(ffb.friends ~= nil and ffb.friends.__parent == FriendsListFrame, "A9 a Contacts button sits on the Friends tab")
CHECK(ffb.ignore ~= nil and ffb.ignore.__parent == IgnoreListFrame, "A9 and on the Ignore tab")
CHECK(ffb.friends:IsShown(), "A9 shown by default")
NoErrors("A8 no errors through login")

-- ===========================================================================
-- B. Whispers file into threads
-- ===========================================================================

Whisper("CHAT_MSG_WHISPER", "yo", "Vexa-Blackrock", "P-vexa")
local vexa = S.Conversation("dm:Vexa-Blackrock")
CHECK(vexa ~= nil, "B1 a whisper from another realm keeps the realm in the key")
EQ(vexa and vexa.class, "ROGUE", "B1 class resolved from the GUID")
EQ(vexa and vexa.unread, 1, "B1 unread")
EQ(vexa and vexa.target, "Vexa-Blackrock", "B1 target kept")

Whisper("CHAT_MSG_WHISPER", "hi", "Miralei-TestRealm", "P-mira")
local mira = S.Conversation("dm:Miralei")
CHECK(mira ~= nil, "B2 a same-realm whisper is keyed by the short name")
EQ(mira and #mira.messages, 1, "B2 one line")

Whisper("CHAT_MSG_WHISPER_INFORM", "sup", "Miralei-TestRealm", "P-mira")
EQ(#mira.messages, 2, "B3 an outgoing whisper is filed")
CHECK(mira.messages[2].out, "B3 marked outgoing")
EQ(mira.messages[2].from, "Devinp", "B3 from you")
EQ(mira.messages[2].cls, "PRIEST", "B3 your class on your own line")
EQ(mira.unread, 1, "B3 outgoing does not add to unread")

CommanderContactsDB.LogOutgoing = false
Whisper("CHAT_MSG_WHISPER_INFORM", "quiet", "Miralei-TestRealm", "P-mira")
EQ(#mira.messages, 2, "B4 outgoing not filed when switched off")
CommanderContactsDB.LogOutgoing = true
CommanderContactsDB.LogWhispers = false
Whisper("CHAT_MSG_WHISPER", "ignored", "Miralei-TestRealm", "P-mira")
EQ(#mira.messages, 2, "B4 whispers not filed when switched off")
CommanderContactsDB.LogWhispers = true

Whisper("CHAT_MSG_BN_WHISPER", "hey", "|Kq77|k", "", 77)
local jordan = S.Conversation("bn:77")
CHECK(jordan ~= nil, "B5 a Battle.net whisper is keyed by account id")
EQ(jordan and jordan.name, "Jordan", "B5 named from the account record, not the token")
Whisper("CHAT_MSG_BN_WHISPER_INFORM", "hey back", "|Kq77|k", "", 77)
EQ(jordan and #jordan.messages, 2, "B5 outgoing Battle.net whisper filed")
CHECK(jordan.messages[2].out, "B5 marked outgoing")
CommanderContactsDB.LogBattleNet = false
Whisper("CHAT_MSG_BN_WHISPER", "no", "|Kq77|k", "", 77)
EQ(#jordan.messages, 2, "B5 Battle.net not filed when switched off")
CommanderContactsDB.LogBattleNet = true
NoErrors("B6 no errors filing whispers")

-- ===========================================================================
-- C. Party sessions follow the roster
-- ===========================================================================

EQ(S.ActiveGroup(), nil, "C1 no group yet")
SetGroup("PARTY", { "P-mira", "P-ally" })
Fire("GROUP_ROSTER_UPDATE")
local run = S.ActiveGroup()
CHECK(run ~= nil, "C2 joining a party opens a thread")
EQ(run and #run.members, 2, "C2 members from the roster")
CHECK(run and S.IsMember(run.key, "Miralei") and S.IsMember(run.key, "Brakk"), "C2 the right members")
CHECK(run and not S.IsMember(run.key, "Devinp"), "C2 you are not listed as a member of your own party")
EQ(run and run.groupType, "PARTY", "C2 type")

Fire("CHAT_MSG_PARTY", "pull in 3", "Miralei-TestRealm", "Common", "", "", "", 0, 0, "", 0, 1, "P-mira")
Fire("CHAT_MSG_PARTY_LEADER", "ok", "Devinp-TestRealm", "Common", "", "", "", 0, 0, "", 0, 1, "P-me")
EQ(#run.messages, 2, "C3 party lines file into the live thread")
CHECK(not run.messages[1].out and run.messages[2].out, "C3 yours is outgoing, theirs is not")
EQ(run.messages[2].ch, "LEADER", "C3 the leader channel is tagged")
EQ(run.unread, 1, "C3 only their line counts as unread")

SetGroup("RAID", { "P-mira", "P-ally", "P-vexa" })
Fire("GROUP_ROSTER_UPDATE")
EQ(S.ActiveGroup(), run, "C4 a party growing into a raid stays one thread")
EQ(run.groupType, "RAID", "C4 type follows")
EQ(#run.members, 3, "C4 new members added")
CHECK(run.name:match("^Raid") ~= nil, "C4 name follows the type", run.name)
Fire("CHAT_MSG_RAID_WARNING", "GO", "Vexa-Blackrock", "Common", "", "", "", 0, 0, "", 0, 1, "P-vexa")
EQ(run.messages[3].ch, "RAID_WARNING", "C4 raid warnings tagged")

SetGroup(nil)
Fire("GROUP_LEFT")
EQ(S.ActiveGroup(), nil, "C5 leaving closes the thread")
CHECK(run.ended ~= nil, "C5 ended stamped")

-- A line that arrives before any roster event opens a session on its own
Fire("CHAT_MSG_PARTY", "early", "Brakk-TestRealm", "Common", "", "", "", 0, 0, "", 0, 1, "P-ally")
local early = S.ActiveGroup()
CHECK(early ~= nil and early ~= run, "C6 a stray party line opens a new thread rather than being lost")
EQ(early and #early.messages, 1, "C6 the line landed")
SetGroup(nil)
Fire("GROUP_ROSTER_UPDATE")
EQ(S.ActiveGroup(), nil, "C6 and the roster closes it again")

CommanderContactsDB.LogGroups = false
SetGroup("PARTY", { "P-mira" })
Fire("GROUP_JOINED")
EQ(S.ActiveGroup(), nil, "C7 no thread opens while group logging is off")
CommanderContactsDB.LogGroups = true
SetGroup(nil)
Fire("GROUP_LEFT")
NoErrors("C8 no errors through group sessions")

-- ===========================================================================
-- D. The window: Activity
-- ===========================================================================

H.Show()
local state, frame = H.State()
CHECK(frame ~= nil and frame:IsShown(), "D1 the window opens")
EQ(state.tab, "activity", "D1 opens on the remembered tab")
EQ(#frame.tabs, 3, "D1 three tabs")
CHECK(showFriendsCalls >= 2, "D1 opening requests a fresh friends list")

-- Sidebar rows are pooled buttons; read them back through their entries
local function Rows()
    local list = {}
    for _, f in ipairs(frames) do
        if f.entry and f.__shown and f.__kind == "Button" and f.entry.kind ~= "header" and f.entry.id then
            list[#list + 1] = f
        end
    end
    return list
end
local function RowFor(id)
    for _, row in ipairs(Rows()) do
        if row.entry.id == id then return row end
    end
    return nil
end
local function HeaderLabels()
    local list = {}
    for _, f in ipairs(frames) do
        if f.entry and f.__shown and f.entry.kind == "header" then list[#list + 1] = f.entry.label end
    end
    return list
end

local headers = HeaderLabels()
EQ(#headers, 2, "D2 activity shows PEOPLE and GROUPS")
EQ(headers[1], "PEOPLE", "D2 people first")
EQ(headers[2], "GROUPS", "D2 groups second")
CHECK(RowFor("dm:Keeper") ~= nil, "D2 the fixture thread is listed")
CHECK(RowFor("dm:Vexa-Blackrock") ~= nil, "D2 the stranger from another realm is listed")
CHECK(RowFor("bn:77") ~= nil, "D2 the Battle.net thread is listed")
CHECK(RowFor(run.key) ~= nil, "D2 the raid is listed")
CHECK(RowFor("dm:Miralei").entry.marked, "D2 a friend's thread carries the friend marker")
CHECK(not RowFor("dm:Vexa-Blackrock").entry.marked, "D2 a stranger's does not")
EQ(RowFor("dm:Keeper").entry.sub, "recent [Thunderfury]", "D2 preview strips the link to its label")
CHECK(frame.TitleText:GetText():match("%(%d+%)") ~= nil, "D3 unread count on the title", frame.TitleText:GetText())
local activityTab = frame.tabs[3]
CHECK(activityTab.label:GetText():match("^Activity %(%d+%)$") ~= nil, "D3 unread count on the tab", activityTab.label:GetText())

Click(RowFor("dm:Miralei"))
EQ(state.selected.activity, "dm:Miralei", "D4 clicking a row selects it")
EQ(CommanderContactsDB.LastSelected.activity, "dm:Miralei", "D4 selection remembered")
CHECK(frame.currentView ~= nil and frame.currentView.title == "Miralei", "D4 the header names them")
CHECK(frame.currentView.subtitle:find("Friend · online", 1, true) ~= nil, "D4 the subtitle knows they are a friend and online", frame.currentView.subtitle)
EQ(mira.unread, 0, "D4 opening a thread marks it read")
CHECK(frame.currentView.canCompose, "D4 you can reply")
EQ(frame.composeHint:GetText(), "Message Miralei", "D4 compose hint")

Type(frame.composeBox, "on my way")
Enter(frame.composeBox)
EQ(#sent, 1, "D5 enter sends")
EQ(sent[1].chatType, "WHISPER", "D5 as a whisper")
EQ(sent[1].target, "Miralei-TestRealm", "D5 to the full name the whisper came from")
EQ(sent[1].text, "on my way", "D5 the text")
EQ(frame.composeBox:GetText(), "", "D5 the box clears")
EQ(#mira.messages, 2, "D5 nothing is filed locally; the client's echo is the record")
Whisper("CHAT_MSG_WHISPER_INFORM", "on my way", "Miralei-TestRealm", "P-mira")
EQ(#mira.messages, 3, "D5 the echo files it")

-- An incoming line on the open thread is read at once; on another it is not
Whisper("CHAT_MSG_WHISPER", "k", "Miralei-TestRealm", "P-mira")
EQ(mira.unread, 0, "D6 a line arriving on the open thread is read immediately")
Whisper("CHAT_MSG_WHISPER", "psst", "Vexa-Blackrock", "P-vexa")
EQ(vexa.unread, 2, "D6 a line on another thread stays unread")
CHECK(RowFor("dm:Vexa-Blackrock").pill:IsShown(), "D6 and shows a pill")
EQ(RowFor("dm:Vexa-Blackrock").pillText:GetText(), "2", "D6 with the count")

-- Transcript rows: one per line plus a day divider
local lineRows = 0
for _, f in ipairs(frames) do
    if f.__kind == "Frame" and f.__shown and f.text and f.author and f.day then
        lineRows = lineRows + 1
    end
end
CHECK(lineRows >= 4, "D7 transcript rows drawn for four lines and a divider", lineRows)

-- An ended group cannot be replied to
Click(RowFor(run.key))
CHECK(not frame.currentView.canCompose, "D8 an ended group has no reply")
EQ(frame.composeHint:GetText(), "This group has ended.", "D8 says so")
CHECK(frame.currentView.subtitle:find("Raid with", 1, true) ~= nil, "D8 subtitle names the members", frame.currentView.subtitle)
Type(frame.composeBox, "too late")
Enter(frame.composeBox)
EQ(#sent, 1, "D8 nothing sent")

-- A live group can
SetGroup("PARTY", { "P-mira" })
Fire("GROUP_JOINED")
local live = S.ActiveGroup()
Click(RowFor(live.key))
CHECK(frame.currentView.canCompose, "D9 a live group takes replies")
Type(frame.composeBox, "inc")
Enter(frame.composeBox)
EQ(sent[#sent].chatType, "PARTY", "D9 sent on party")
SetGroup("RAID", { "P-mira", "P-ally" })
Fire("GROUP_ROSTER_UPDATE")
Type(frame.composeBox, "inc raid")
Enter(frame.composeBox)
EQ(sent[#sent].chatType, "RAID", "D9 sent on raid once it is one")
SetGroup(nil)
Fire("GROUP_LEFT")
CHECK(not frame.currentView.canCompose, "D9 leaving disables the reply box while it is open")

-- Battle.net replies go through C_BattleNet
Click(RowFor("bn:77"))
Type(frame.composeBox, "bnet hi")
Enter(frame.composeBox)
EQ(#bnSent, 1, "D10 Battle.net whisper sent through C_BattleNet")
EQ(bnSent[1].id, 77, "D10 to the account")

-- Search narrows the sidebar; the filter drops groups
Type(frame.searchBox, "vexa")
CHECK(RowFor("dm:Vexa-Blackrock") ~= nil, "D11 search keeps the match")
EQ(RowFor("dm:Keeper"), nil, "D11 search drops the rest")
Type(frame.searchBox, "thunderfury")
CHECK(RowFor("dm:Keeper") ~= nil, "D11 search matches inside a link label")
frame.searchBox:SetText("")
frame.searchBox:ClearFocus()
ToggleDropDownMenu(1, nil, frame.filterDrop)
local groupsOnly
for _, info in ipairs(menuCaptured) do
    if info.value == "groups" then groupsOnly = info end
end
CHECK(groupsOnly ~= nil, "D12 the filter menu offers Groups")
groupsOnly.func({ value = "groups" })
EQ(state.filter, "groups", "D12 filter applied")
EQ(HeaderLabels()[1], "GROUPS", "D12 only groups listed")
EQ(#HeaderLabels(), 1, "D12 no people header")
EQ(RowFor("dm:Keeper"), nil, "D12 people gone")
local everyone
for _, info in ipairs(menuCaptured) do
    if info.value == "all" then everyone = info end
end
everyone.func({ value = "all" })
EQ(state.filter, "all", "D12 back to everyone")
CHECK(RowFor("dm:Keeper") ~= nil, "D12 people back")

-- Right-click menu on a stranger offers Add Friend and Ignore
Click(RowFor("dm:Vexa-Blackrock"), "RightButton")
local menuTexts = {}
for _, info in ipairs(menuCaptured) do menuTexts[info.text] = info end
CHECK(menuTexts["Add Friend"] ~= nil, "D13 a stranger's menu offers Add Friend")
CHECK(menuTexts["Ignore..."] ~= nil, "D13 and Ignore")
CHECK(menuTexts["Pin To Top"] ~= nil, "D13 and Pin")
menuTexts["Pin To Top"].func()
CHECK(vexa.pinned, "D13 pinned")
CHECK(Rows()[1].entry.id == "dm:Vexa-Blackrock", "D13 a pinned thread is listed first")
menuTexts["Add Friend"].func()
EQ(LastOp("add").name, "Vexa-Blackrock", "D13 Add Friend calls the client with the full name")
NoErrors("D14 no errors on the activity tab")

-- ===========================================================================
-- E. The window: Friends
-- ===========================================================================

Click(frame.tabs[1])
EQ(state.tab, "friends", "E1 the Friends tab")
EQ(CommanderContactsDB.LastTab, "friends", "E1 remembered")
local fh = HeaderLabels()
EQ(fh[1], "ONLINE", "E2 online section")
EQ(fh[2], "OFFLINE", "E2 offline section")
EQ(fh[3], "BATTLE.NET", "E2 Battle.net section")
local miraRow = RowFor("friend:Miralei")
CHECK(miraRow ~= nil, "E2 the online friend is listed")
CHECK(miraRow.entry.online, "E2 online")
EQ(miraRow.entry.sub, "Level 70 Mage · Shattrath City", "E2 status line")
CHECK(miraRow.dot:IsShown(), "E2 online marker")
CHECK(RowFor("friend:Brakk") ~= nil and not RowFor("friend:Brakk").entry.online, "E2 the offline friend is listed offline")
local jordanRow = RowFor("bn:77")
CHECK(jordanRow ~= nil, "E2 the Battle.net friend is listed")
EQ(jordanRow.entry.sub, "Jordy · 70 Warrior · Netherstorm", "E2 with their character")
CHECK(RowFor("friend:Vexa-Blackrock") ~= nil, "E2 the friend added from Activity is here")

CommanderContactsDB.ShowOffline = false
Commander.Notify(COMMANDER_CONTACTS_EVENTS.UPDATE)
EQ(RowFor("friend:Brakk"), nil, "E3 offline friends hidden when switched off")
CommanderContactsDB.ShowOffline = true
Commander.Notify(COMMANDER_CONTACTS_EVENTS.UPDATE)
CHECK(RowFor("friend:Brakk") ~= nil, "E3 and back")

-- The Battle.net folder
local function HeaderRow(label)
    for _, f in ipairs(frames) do
        if f.entry and f.__shown and f.entry.kind == "header" and f.entry.label == label then return f end
    end
    return nil
end
CHECK(HeaderRow("BATTLE.NET").entry.fold ~= nil, "E3b the Battle.net heading folds")
Click(HeaderRow("BATTLE.NET"))
EQ(CommanderContactsDB.FoldBattleNet, true, "E3b clicking the heading folds it")
EQ(RowFor("bn:77"), nil, "E3b folded: no Battle.net rows")
CHECK(HeaderRow("BATTLE.NET") ~= nil, "E3b folded: the heading stays")
Type(frame.searchBox, "jordy")
CHECK(RowFor("bn:77") ~= nil, "E3b a search unfolds a hit")
frame.searchBox:SetText("")
frame.searchBox:ClearFocus()
EQ(RowFor("bn:77"), nil, "E3b and it folds again when the search clears")
Click(HeaderRow("BATTLE.NET"))
EQ(CommanderContactsDB.FoldBattleNet, false, "E3b clicking again unfolds")
CHECK(RowFor("bn:77") ~= nil, "E3b rows back")
CommanderContactsDB.ShowBattleNet = false
Commander.Notify(COMMANDER_CONTACTS_EVENTS.UPDATE)
EQ(HeaderRow("BATTLE.NET"), nil, "E3c Battle.net hidden entirely when switched off")
CommanderContactsDB.ShowBattleNet = true
Commander.Notify(COMMANDER_CONTACTS_EVENTS.UPDATE)
CHECK(RowFor("bn:77") ~= nil, "E3c and back")

Click(RowFor("friend:Miralei"))
EQ(frame.currentView.title, "Miralei", "E4 the friend card")
CHECK(frame.currentView.subtitle:find("Online · Level 70 Mage", 1, true) ~= nil, "E4 status", frame.currentView.subtitle)
CHECK(CommanderContactsNotesBox:IsShown(), "E4 the notes box is shown for a friend")
EQ(CommanderContactsNotesBox:GetText(), "healer", "E4 with their notes")
EQ(#frame.currentView.actions, 4, "E4 four verbs: whisper, invite, ignore, remove")
CHECK(frame.currentView.conv == mira, "E4 the friend's thread is the one whispers filed into")
Type(CommanderContactsNotesBox, "healer, kara")
CommanderContactsNotesBox:ClearFocus()
local notesOp = LastOp("notes")
CHECK(notesOp ~= nil and notesOp.name == "Miralei" and notesOp.notes == "healer, kara", "E5 leaving the notes box saves the note")
Type(frame.composeBox, "hey friend")
Enter(frame.composeBox)
EQ(sent[#sent].target, "Miralei-TestRealm", "E6 replying from the friends tab whispers the known full name")

-- A friend with no thread yet: the send makes one and the echo lands in it
Click(RowFor("friend:Brakk"))
EQ(frame.currentView.conv, nil, "E7 no thread with Brakk yet")
Type(frame.composeBox, "you there?")
Enter(frame.composeBox)
EQ(sent[#sent].target, "Brakk", "E7 whispered by the friends-list name")
CHECK(S.Conversation("dm:Brakk") ~= nil, "E7 the send created the thread")
Whisper("CHAT_MSG_WHISPER_INFORM", "you there?", "Brakk-TestRealm", "P-ally")
CHECK(frame.currentView.conv ~= nil and #frame.currentView.conv.messages == 1, "E7 the echo shows in the card at once")

-- Verbs
frame.currentView.actions[1].onClick()
EQ(tells[#tells], "Brakk-TestRealm", "E8 Whisper puts /w in the chat box, with the full name the echo taught it")
frame.currentView.actions[2].onClick()
EQ(invites[#invites], "Brakk-TestRealm", "E8 Invite invites by the same full name")
frame.currentView.actions[4].onClick()
EQ(LastPopup(), "COMMANDER_CONTACTS_REMOVEFRIEND", "E8 Remove confirms first")
AcceptPopup("COMMANDER_CONTACTS_REMOVEFRIEND")
EQ(LastOp("remove").name, "Brakk", "E8 confirming removes")
EQ(RowFor("friend:Brakk"), nil, "E8 and the row goes")

Click(frame.addFriend)
EQ(LastPopup(), "COMMANDER_CONTACTS_ADDFRIEND", "E9 Add Friend opens the name dialog")
AcceptPopup("COMMANDER_CONTACTS_ADDFRIEND", "Newguy")
EQ(LastOp("add").name, "Newguy", "E9 the typed name is added")
AcceptPopup("COMMANDER_CONTACTS_ADDFRIEND", "Devinp")
CHECK(PrintedMatching("that is you"), "E9 adding yourself is refused with a message")

Click(RowFor("bn:77"))
EQ(frame.currentView.title, "Jordan", "E10 the Battle.net card")
CHECK(frame.currentView.subtitle:find("Jordy, level 70 Warrior on TestRealm", 1, true) ~= nil, "E10 character line", frame.currentView.subtitle)
CHECK(frame.currentView.subtitle:find("raiding tonight", 1, true) ~= nil, "E10 broadcast shown")
EQ(CommanderContactsNotesBox:GetText(), "Jordan#1234", "E10 the BattleTag sits in the read-only box")
frame.currentView.actions[1].onClick()
EQ(bnInvites[#bnInvites], 9001, "E10 Invite goes to the game account")
NoErrors("E11 no errors on the friends tab")

-- ===========================================================================
-- F. The window: Ignore
-- ===========================================================================

Click(frame.tabs[2])
EQ(state.tab, "ignore", "F1 the Ignore tab")
EQ(HeaderLabels()[1], "IGNORED", "F1 one section")
CHECK(RowFor("ignore:Troll") ~= nil, "F1 the ignored name is listed")
Click(RowFor("ignore:Troll"))
EQ(frame.currentView.title, "Troll", "F2 the card")
CHECK(not frame.currentView.canCompose, "F2 no replying to someone you ignore")
EQ(#frame.currentView.actions, 1, "F2 one verb")
Click(frame.addIgnore)
EQ(LastPopup(), "COMMANDER_CONTACTS_ADDIGNORE", "F3 Ignore Someone opens the dialog")
AcceptPopup("COMMANDER_CONTACTS_ADDIGNORE", "Spammer")
EQ(LastOp("ignore").name, "Spammer", "F3 the typed name is ignored")
frame.currentView.actions[1].onClick()
EQ(LastOp("unignore").name, "Troll", "F4 Stop Ignoring removes")
EQ(state.selected.ignore, nil, "F4 selection cleared")
NoErrors("F5 no errors on the ignore tab")

-- ===========================================================================
-- G. Deleting, clearing, restore defaults, disable
-- ===========================================================================

Click(frame.tabs[3])
Click(RowFor("dm:Keeper"))
frame.currentView.actions[#frame.currentView.actions - 1].onClick()
EQ(LastPopup(), "COMMANDER_CONTACTS_CLEAR", "G1 Clear confirms")
AcceptPopup("COMMANDER_CONTACTS_CLEAR")
EQ(#S.Messages("dm:Keeper"), 0, "G1 cleared")
CHECK(S.Conversation("dm:Keeper") ~= nil, "G1 the thread stays")
frame.currentView.actions[#frame.currentView.actions].onClick()
EQ(LastPopup(), "COMMANDER_CONTACTS_DELETE", "G2 Delete confirms")
AcceptPopup("COMMANDER_CONTACTS_DELETE")
EQ(S.Conversation("dm:Keeper"), nil, "G2 deleted")
EQ(state.selected.activity, nil, "G2 selection cleared")

Click(RowFor(run.key))
StaticPopup_Show("COMMANDER_CONTACTS_RENAME", run.name, nil, run.key)
AcceptPopup("COMMANDER_CONTACTS_RENAME", "Gruul Night")
EQ(run.name, "Gruul Night", "G3 rename through the dialog")
EQ(frame.currentView.title, "Gruul Night", "G3 the card follows")

-- R1: the defaults table cannot reach the record
CHECK(CommanderContacts_Defaults.Conversations == nil, "R1 defaults do not name Conversations")
CHECK(CommanderContacts_Defaults.NextID == nil, "R1 defaults do not name NextID")
CHECK(CommanderContacts_Defaults.LastTab == nil, "R1 defaults do not name the view state")
-- R2: the real reset path
local before = S.Count()
CommanderContactsDB.KeepDays = 5
SlashCmdList["COMMANDERUI_CONTACTS"]("reset")
EQ(CommanderContactsDB.KeepDays, 90, "R2 reset restores a setting")
EQ(S.Count(), before, "R2 reset does not touch a single thread")
CHECK(PrintedMatching("conversations were not touched"), "R2 and says so")

SlashCmdList["COMMANDERUI_CONTACTS"]("stats")
CHECK(PrintedMatching("lines kept"), "G4 stats prints")
SlashCmdList["COMMANDERUI_CONTACTS"]("ignore")
EQ(state.tab, "ignore", "G5 /ccontacts ignore switches tab")
SlashCmdList["COMMANDERUI_CONTACTS"]("friends")
EQ(state.tab, "friends", "G5 /ccontacts friends switches tab")
CHECK(H.OpenConversation("dm:Vexa-Blackrock"), "G6 OpenConversation")
EQ(state.tab, "activity", "G6 lands on activity")
EQ(state.selected.activity, "dm:Vexa-Blackrock", "G6 with the thread selected")
EQ(vexa.unread, 0, "G6 and read")
CHECK(not H.OpenConversation("dm:Nobody"), "G6 an unknown key is refused")

SlashCmdList["COMMANDERUI_CONTACTS"]("")
CHECK(not frame:IsShown(), "G7 bare command toggles closed")
SlashCmdList["COMMANDERUI_CONTACTS"]("")
CHECK(frame:IsShown(), "G7 and open again")

CommanderContactsDB.EnableContacts = false
Commander.Notify(COMMANDER_CONTACTS_EVENTS.UPDATE)
CHECK(not frame:IsShown(), "G8 switching off closes the window")
H.Show()
CHECK(not frame:IsShown(), "G8 and it will not open")
CHECK(PrintedMatching("switched off"), "G8 with a message")
Whisper("CHAT_MSG_WHISPER", "while off", "Vexa-Blackrock", "P-vexa")
EQ(#vexa.messages, 2, "G8 nothing is filed while off")
CommanderContactsDB.EnableContacts = true
Commander.Notify(COMMANDER_CONTACTS_EVENTS.UPDATE)
H.Show()
CHECK(frame:IsShown(), "G8 back on")

CommanderContactsDB.MaxMessages = 100
Commander.Notify(COMMANDER_CONTACTS_EVENTS.UPDATE)
EQ(S.MaxMessages(), 100, "G9 the line cap follows a settings change")

-- The button on Blizzard's window opens ours on the matching tab, and obeys its switch
Click(ffb.ignore)
EQ(state.tab, "ignore", "G9b the Ignore-tab button opens Contacts on Ignore")
Click(ffb.friends)
EQ(state.tab, "friends", "G9b the Friends-tab button opens Contacts on Friends")
CommanderContactsDB.FriendsFrameButton = false
Commander.Notify(COMMANDER_CONTACTS_EVENTS.UPDATE)
CHECK(not ffb.friends:IsShown() and not ffb.ignore:IsShown(), "G9b switched off, both buttons hide")
CommanderContactsDB.FriendsFrameButton = true
Commander.Notify(COMMANDER_CONTACTS_EVENTS.UPDATE)
CHECK(ffb.friends:IsShown(), "G9b and back")
CommanderContactsDB.EnableContacts = false
Commander.Notify(COMMANDER_CONTACTS_EVENTS.UPDATE)
CHECK(not ffb.friends:IsShown(), "G9b the master switch hides them too")
CommanderContactsDB.EnableContacts = true
Commander.Notify(COMMANDER_CONTACTS_EVENTS.UPDATE)

CHECK(type(CommanderContacts_Toggle) == "function", "G10 binding global: toggle")
CHECK(type(CommanderContacts_ShowTab) == "function", "G10 binding global: show tab")
EQ(BINDING_HEADER_COMMANDERCONTACTS, "Commander Contacts", "G10 binding header")

-- The Window style hides the dark backdrop rather than erroring
CommanderContactsDB.FrameStyle = "WINDOW"
Commander.Notify(COMMANDER_CONTACTS_EVENTS.UPDATE)
CommanderContactsDB.FrameStyle = "DARK"
Commander.Notify(COMMANDER_CONTACTS_EVENTS.UPDATE)
NoErrors("G11 no errors through the rest")

-- ===========================================================================
-- S. Suggested friends: the scout fed from the client
-- ===========================================================================

local T = CommanderContactsScout
CHECK(T.Attached(), "S1 the scout is attached")
-- The master-switch check above left the window hidden; open it again so
-- the notify-driven redraws below have something to draw.
H.Show()
CHECK(frame:IsShown(), "S1 window open for the checks below")

local function Score(name, faction, class, dmg, heal, kb)
    return { name = name, faction = faction, class = class, dmg = dmg, heal = heal, kb = kb }
end
scoreboard = {
    Score("Devinp", 0, "PRIEST", 300000, 100000, 3),
    Score("Topdps", 0, "MAGE", 400000, 0, 12),
    Score("Healz", 0, "PRIEST", 5000, 250000, 1),
    Score("Miralei", 0, "MAGE", 50000, 0, 20),
    Score("Enemyguy", 1, "ROGUE", 350000, 0, 19),
    Score("Xrealm-Blackrock", 0, "WARLOCK", 380000, 0, 15),
}
winner = 1
Fire("UPDATE_BATTLEFIELD_SCORE")
EQ(T.Record("Topdps"), nil, "S2 a board outside a battleground is ignored")

instanceType, zoneText = "pvp", "Arathi Basin"
Fire("PLAYER_ENTERING_WORLD")
winner = nil
Fire("UPDATE_BATTLEFIELD_SCORE")
EQ(T.Record("Topdps"), nil, "S3 no winner yet, nothing recorded")
winner = 1
Fire("UPDATE_BATTLEFIELD_SCORE")
local top = T.Record("Topdps")
CHECK(top ~= nil, "S4 the board is read when a winner is declared")
EQ(top and top.dmgTop, 1, "S4 top damage of the match")
EQ(top and top.lastMap, "Arathi Basin", "S4 map from the zone")
EQ(top and top.class, "MAGE", "S4 class token")
CHECK(T.Record("Healz") ~= nil and T.Record("Healz").healTop == 1, "S4 the healer")
CHECK(T.Record("Miralei") ~= nil and T.Record("Miralei").kbTop == 1, "S4 a friend is recorded too (filtered at list time)")
EQ(T.Record("Enemyguy"), nil, "S4 the other faction is not")
EQ(T.Record("Xrealm-Blackrock"), nil, "S4 nor another realm")
EQ(T.Record("Devinp"), nil, "S4 nor me")
Fire("UPDATE_BATTLEFIELD_SCORE")
EQ(top.games, 1, "S5 the same board is not counted twice")
instanceType = "none"
Fire("PLAYER_ENTERING_WORLD")
instanceType = "pvp"
zoneText = "Warsong Gulch"
Fire("PLAYER_ENTERING_WORLD")
Fire("UPDATE_BATTLEFIELD_SCORE")
EQ(top.games, 2, "S5 a new battleground is a new board")
EQ(top.lastMap, "Warsong Gulch", "S5 map moves on")

-- Titles off the raid inside a battleground
SetGroup("RAID", { "P-glad", "P-plain", "P-mira" })
Fire("GROUP_ROSTER_UPDATE")
local glad = T.Record("Gladys")
CHECK(glad ~= nil, "S6 a titled teammate is recorded from the roster")
EQ(glad and glad.title, "Merciless Gladiator", "S6 the title, without the name")
EQ(glad and glad.class, "WARRIOR", "S6 class from the unit")
EQ(T.Record("Plain"), nil, "S6 an untitled teammate is not recorded by the roster alone")
SetGroup(nil)
Fire("GROUP_LEFT")
instanceType = "none"
Fire("PLAYER_ENTERING_WORLD")
SetGroup("RAID", { "P-glad" })
players["P-glad"].title = "Vengeful Gladiator"
Fire("GROUP_ROSTER_UPDATE")
EQ(glad.title, "Merciless Gladiator", "S7 titles are only read inside a battleground")
SetGroup(nil)
Fire("GROUP_LEFT")

-- Ratings from Muster's inspect
musterRecords["P-rated"] = { name = "Rated", class = "MAGE", arena = { known = true, [3] = { rating = 2210 }, [2] = { rating = 0 } } }
Commander.Notify("COMMANDER_MUSTER_RECORD", "P-rated")
local rated = T.Record("Rated")
CHECK(rated ~= nil, "S8 a Muster record with ratings is recorded")
EQ(rated and rated.ratings[3], 2210, "S8 the 3v3 rating")
EQ(rated and rated.ratings[2], nil, "S8 a zero bracket is skipped")
musterRecords["P-me"] = { name = "Devinp", class = "PRIEST", arena = { [2] = { rating = 2500 } } }
Commander.Notify("COMMANDER_MUSTER_RECORD", "P-me")
EQ(T.Record("Devinp"), nil, "S8 my own record is not a suggestion")

-- The list
local suggestions = H.Suggestions()
local byName = {}
for _, entry in ipairs(suggestions) do byName[entry.name] = entry end
CHECK(byName.Topdps and byName.Healz and byName.Gladys and byName.Rated, "S9 the four are suggested")
EQ(byName.Miralei, nil, "S9 a friend is not")
CHECK(byName.Topdps.reason:find("Top damage in all 2 games", 1, true) ~= nil, "S9 Topdps's reason", byName.Topdps.reason)
CHECK(byName.Rated.reason:find("Gladiator range", 1, true) ~= nil, "S9 Rated's reason", byName.Rated.reason)
CHECK(byName.Gladys.reason:find("Wears the Merciless Gladiator title", 1, true) ~= nil, "S9 Gladys's reason")
EQ(suggestions[1].name, "Gladys", "S9 best first: a Gladiator title (100) beats two top-damage games (60 + kills)")

-- In the window
Click(frame.tabs[1])
local sh = HeaderLabels()
EQ(sh[#sh], "SUGGESTED", "S10 the Suggested section sits under the friends")
local topRow = RowFor("suggest:Topdps")
CHECK(topRow ~= nil, "S10 a suggestion row")
EQ(topRow and topRow.entry.sub, byName.Topdps.reason, "S10 with the reason as its second line")
Click(topRow)
EQ(frame.currentView.title, "Topdps", "S11 the card")
CHECK(frame.currentView.subtitle:find("Top damage", 1, true) ~= nil, "S11 the reason on the card")
CHECK(frame.currentView.subtitle:find("seen in 2 battlegrounds", 1, true) ~= nil, "S11 and the detail", frame.currentView.subtitle)
EQ(#frame.currentView.actions, 4, "S11 add, whisper, invite, not interested")
CHECK(frame.currentView.canCompose, "S11 you can whisper them")
Type(frame.composeBox, "gg wp")
Enter(frame.composeBox)
EQ(sent[#sent].target, "Topdps", "S11 sent as a whisper to them")
frame.currentView.actions[4].onClick()
EQ(T.Record("Topdps"), nil, "S12 Not Interested drops the record")
CHECK(CommanderContactsDB.Dismissed.Topdps, "S12 and remembers the dismissal")
EQ(RowFor("suggest:Topdps"), nil, "S12 the row is gone")
Click(RowFor("suggest:Healz"))
frame.currentView.actions[1].onClick()
EQ(LastOp("add").name, "Healz", "S13 Add Friend from the card")
Fire("FRIENDLIST_UPDATE")
EQ(RowFor("suggest:Healz"), nil, "S13 once a friend, no longer suggested")
CHECK(RowFor("friend:Healz") ~= nil, "S13 and listed as a friend")

Click(RowFor("suggest:Gladys"), "RightButton")
local sm = {}
for _, info in ipairs(menuCaptured) do sm[info.text] = info end
CHECK(sm["Add Friend"] and sm["Not Interested"] and sm["Whisper In Chat"], "S14 the row menu")

Type(frame.searchBox, "merciless")
CHECK(RowFor("suggest:Gladys") ~= nil, "S15 search matches the reason")
EQ(RowFor("suggest:Rated"), nil, "S15 and drops the rest")
frame.searchBox:SetText("")
frame.searchBox:ClearFocus()

CommanderContactsDB.FoldSuggested = true
Commander.Notify(COMMANDER_CONTACTS_EVENTS.UPDATE)
EQ(RowFor("suggest:Gladys"), nil, "S16 folded")
CommanderContactsDB.FoldSuggested = false
CommanderContactsDB.SuggestFriends = false
Commander.Notify(COMMANDER_CONTACTS_EVENTS.UPDATE)
local sh2 = HeaderLabels()
EQ(sh2[#sh2], "BATTLE.NET", "S16 switched off, no section at all")
instanceType = "pvp"
Fire("PLAYER_ENTERING_WORLD")
Fire("UPDATE_BATTLEFIELD_SCORE")
EQ(T.Record("Healz").games, 2, "S16 and no scouting either")
instanceType = "none"
CommanderContactsDB.SuggestFriends = true
Commander.Notify(COMMANDER_CONTACTS_EVENTS.UPDATE)

CommanderContacts_ForgetSuggestions()
EQ(T.Count(), 0, "S17 Forget Suggestions empties the record")
CHECK(CommanderContactsDB.Dismissed.Topdps, "S17 but dismissals stay")
CHECK(CommanderContacts_Defaults.Performers == nil and CommanderContacts_Defaults.Dismissed == nil, "S18 the record is out of reach of Restore Defaults")
NoErrors("S19 no errors through scouting")

-- ===========================================================================
-- G. Commander Orders 3.1 (1.1.0, DECISIONS D12): Arrow To Them, [Go] links
-- in the log, and an Orders link's hover. Orders is a recording stand-in
-- here; contacts_orders_smoke.lua drives the same against the real Orders.
-- ===========================================================================
do
    local goes, linkified, triggered = {}, {}, {}
    CommanderOrders = {
        GoTo = function(target, opts)
            local spec = {}
            for k, v in pairs(target or {}) do spec[k] = v end
            for k, v in pairs(opts or {}) do spec[k] = v end
            goes[#goes + 1] = spec
            return "w1"
        end,
        Linkify = function(text)
            linkified[#linkified + 1] = text
            local out = text:gsub("(Nagrand %d+%.%d, %d+%.%d)", "%1 |cff71d5ff|Haddon:CommanderOrders:w:1951:0.4:0.6:|h[Go]|h|r")
            return out
        end,
    }
    EventRegistry = { TriggerEvent = function(_, event, ...) triggered[#triggered + 1] = { event = event, ... } end }

    -- Miralei is a friend; in your party, her menu offers Arrow To Them
    H.ShowTab("friends")
    SetGroup("PARTY", { "P-mira" })
    Click(RowFor("friend:Miralei"), "RightButton")
    local m = {}
    for _, info in ipairs(menuCaptured) do m[info.text] = info end
    CHECK(m["Arrow To Them"] ~= nil, "G1 a grouped friend's menu offers Arrow To Them")
    if m["Arrow To Them"] then m["Arrow To Them"].func() end
    local g = goes[#goes] or {}
    EQ(g.kind, "unit", "G1 Orders follows them (a unit follow)")
    EQ(g.unit, "party1", "G1 on their group token")
    EQ(g.guid, "P-mira", "G1 named by GUID, so Orders finds them again")
    EQ(g.source, "Contacts", "G1 source Contacts")
    EQ(g.key, "follow", "G1 one follow, moved by the next ask")
    EQ(g.title, "Miralei", "G1 titled with their name")
    EQ(g.icon, "UNIT", "G1 in the group-member tint")
    CHECK(not g.silent, "G1 not silent: Orders says Waypoint set or why not")
    -- Not grouped: nothing offered (a zone name is not a place)
    SetGroup(nil)
    Click(RowFor("friend:Miralei"), "RightButton")
    m = {}
    for _, info in ipairs(menuCaptured) do m[info.text] = info end
    EQ(m["Arrow To Them"], nil, "G2 not in your group: no Arrow To Them")
    -- A whisper thread's menu too, by the thread's GUID, in a raid
    SetGroup("RAID", { "P-ally", "P-vexa" })
    H.ShowTab("activity")
    Click(RowFor("dm:Vexa-Blackrock"), "RightButton")
    m = {}
    for _, info in ipairs(menuCaptured) do m[info.text] = info end
    CHECK(m["Arrow To Them"] ~= nil, "G3 a grouped stranger's thread offers it too")
    if m["Arrow To Them"] then m["Arrow To Them"].func() end
    g = goes[#goes] or {}
    EQ(g.unit, "raid3", "G3 on the raid token")
    EQ(g.title, "Vexa", "G3 titled with the short name")
    -- Without Orders: nothing offered
    local keep = CommanderOrders
    CommanderOrders = nil
    Click(RowFor("dm:Vexa-Blackrock"), "RightButton")
    m = {}
    for _, info in ipairs(menuCaptured) do m[info.text] = info end
    EQ(m["Arrow To Them"], nil, "G4 without Commander Orders: nothing offered")
    CommanderOrders = keep
    SetGroup(nil)

    -- A logged line naming a zone and coordinates carries Orders' [Go]
    Whisper("CHAT_MSG_WHISPER", "meet at Nagrand 42.5, 61.2 now", "Vexa-Blackrock", "P-vexa")
    Click(RowFor("dm:Vexa-Blackrock"))
    local linkedRow
    for _, f in ipairs(frames) do
        if f.__kind == "Frame" and f.__shown and f.text and f.author and f.text.__text
            and tostring(f.text.__text):find("|h[Go]|h", 1, true) then linkedRow = f end
    end
    CHECK(linkedRow ~= nil, "G5 a logged line carries Orders' [Go] link")
    local n = #linkified
    Commander.Notify(COMMANDER_CONTACTS_EVENTS.UPDATE)
    Click(RowFor("dm:Vexa-Blackrock"))
    EQ(#linkified, n, "G5 kept per line: a redraw does not ask again")
    -- Hovering an Orders link fires what a chat frame fires
    if linkedRow then
        triggered = {}
        linkedRow.__scripts.OnHyperlinkEnter(linkedRow, "addon:CommanderOrders:w:1951:0.4:0.6:", "[Go]")
        EQ(triggered[1] and triggered[1].event, "ChatFrame.OnHyperlinkEnter", "G6 hovering [Go] fires the chat frame's hover")
        EQ(triggered[1] and triggered[1][1], linkedRow, "G6 ...with the row as the frame")
        linkedRow.__scripts.OnHyperlinkLeave(linkedRow, "addon:CommanderOrders:w:1951:0.4:0.6:", "[Go]")
        EQ(triggered[2] and triggered[2].event, "ChatFrame.OnHyperlinkLeave", "G6 and leaving it, its leave")
        triggered = {}
        linkedRow.__scripts.OnHyperlinkEnter(linkedRow, "item:19019", "[Thunderfury]")
        EQ(#triggered, 0, "G6 an item link keeps the game tooltip")
    end
    CommanderOrders = nil
    EventRegistry = nil
    NoErrors("G7 no errors through the Orders additions")
end

if fails > 0 then
    io.write(string.format("contacts ui harness: %d/%d checks FAILED\n", fails, checks))
    os.exit(1)
end
io.write(string.format("contacts ui harness: %d checks passed\n", checks))
