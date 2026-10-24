-- Commander Recruit UI harness (luajit).
--
-- Loads the REAL shared framework (CommanderSettingsUI.lua, CommanderEvents.lua)
-- plus Commander_Recruit's files under a permissive WoW mock, then drives a
-- sweep (one /who per press, the gap, the race split at the cap, the Who
-- window kept shut; and steered by a Commander Ladder roster, section R),
-- every source of "online" (/who, the group finder, chat
-- with the say/yell faction check, guild and friends on and off, players
-- seen), the three-column board off Muster's ratings, freshness, the row
-- clicks, the filters and the master switch.
--
-- Mock copied from Commander_Ladder/Harness/ladder_harness.lua (its generic
-- half: path resolution, CHECK, widgets, timers, the settings framework).
--
-- Run:  /opt/homebrew/bin/luajit recruit_ui_harness.lua

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
-- Recruit-specific mock
-- ===========================================================================

function GetNormalizedRealmName() return "Dreamscythe" end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
RAID_CLASS_COLORS.ROGUE = { r = 1, g = 0.96, b = 0.41 }
RAID_CLASS_COLORS.PRIEST = { r = 1, g = 1, b = 1 }
LOCALIZED_CLASS_NAMES_MALE = setmetatable({}, { __index = function(_, k) return k:sub(1, 1) .. k:sub(2):lower() end })
Enum = { SocialWhoOrigin = { Social = 2 } }

-- Strata and top-level are recorded: which layer a window draws on is the
-- whole of a "renders behind" bug
do
    local base = WidgetMT.__index
    WidgetMT.__index = function(self, key)
        if key == "SetFrameStrata" then
            local fn = function(w, v) w.__strata = v end
            rawset(self, key, fn); return fn
        end
        if key == "SetToplevel" then
            local fn = function(w, v) w.__toplevel = v and true or false end
            rawset(self, key, fn); return fn
        end
        -- Layout, recorded: a cell that wraps, or one given a guessed width
        -- where it should stretch, is the overlap bug
        if key == "SetWordWrap" then
            local fn = function(w, v) w.__wrap = v and true or false end
            rawset(self, key, fn); return fn
        end
        if key == "SetPoint" then
            local fn = function(w, point, rel, relPoint, x, y)
                w.__points = w.__points or {}
                w.__points[#w.__points + 1] = { point = point, rel = rel }
            end
            rawset(self, key, fn); return fn
        end
        if key == "SetWidth" then
            local fn = function(w, v) w.__w = v end
            rawset(self, key, fn); return fn
        end
        if key == "SetTexture" then
            local fn = function(w, v) w.__texture = v end
            rawset(self, key, fn); return fn
        end
        if key == "SetEnabled" then
            local fn = function(w, v) w.__enabled = v and true or false end
            rawset(self, key, fn); return fn
        end
        if key == "SetAtlas" then
            local fn = function(w, v) w.__atlas = v end
            rawset(self, key, fn); return fn
        end
        return base(self, key)
    end
end

-- The units: the player, and whoever the test puts under the cursor
local units = { player = { name = "Devinp", guid = "Player-ME", faction = "Alliance", class = "PRIEST", level = 70 } }
function UnitExists(u) return units[u] ~= nil end
function UnitIsPlayer(u) return units[u] ~= nil end
function UnitIsUnit(a, b) return units[a] ~= nil and units[a] == units[b] end
function UnitGUID(u) return units[u] and units[u].guid end
function UnitName(u) return units[u] and units[u].name end
function GetUnitName(u) return units[u] and units[u].name end
function UnitClass(u) local x = units[u]; if x then return x.class, x.class end end
function UnitLevel(u) return units[u] and units[u].level or 0 end
function UnitFactionGroup(u) return units[u] and units[u].faction end

-- /who: queries recorded; the test answers them
local who = { sent = {}, toUi = {}, results = {}, total = 0 }
C_FriendList = {
    SendWho = function(text, origin)
        who.sent[#who.sent + 1] = { text = text, origin = origin }
        if who.popWindow then FriendsFrame.__shown = true end
    end,
    SetWhoToUi = function(v) who.toUi[#who.toUi + 1] = v end,
    GetNumWhoResults = function() return #who.results, who.total end,
    GetWhoInfo = function(i) return who.results[i] end,
}
local friends = {}
local friendAdds, friendRemoves = {}, {}
C_FriendList.AddFriend = function(name, notes)
    friendAdds[#friendAdds + 1] = { name = name, notes = notes }
end
C_FriendList.RemoveFriend = function(name)
    friendRemoves[#friendRemoves + 1] = name
    for i = #friends, 1, -1 do if friends[i].name == name then table.remove(friends, i) end end
    return true
end
C_FriendList.GetNumFriends = function() return #friends end
C_FriendList.GetFriendInfoByIndex = function(i) return friends[i] end
C_FriendList.ShowFriends = function() end
FriendsFrame = NewWidget("Frame", "FriendsFrame")
FriendsFrame.__shown = false
FriendsFrame.CloseButton = NewWidget("Button")
local hidPanels = {}
function HideUIPanel(f) hidPanels[#hidPanels + 1] = f; f.__shown = false end

-- The group finder
local lfg = {}
C_LFGList = {
    GetSearchResults = function() local ids = {} for id in pairs(lfg) do ids[#ids + 1] = id end return #ids, ids end,
    GetSearchResultInfo = function(id) return lfg[id] and { numMembers = #lfg[id], isDelisted = false } end,
    GetSearchResultPlayerInfo = function(id, i) return lfg[id] and lfg[id][i] end,
}

-- The guild
local guild = {}
function IsInGuild() return true end
function GetNumGuildMembers() return #guild end
function GetGuildRosterInfo(i)
    local g = guild[i]
    if g then return g.name, "Member", 2, g.level, g.class, g.zone, "", "", g.online, 0, g.class end
end
C_GuildInfo = { GuildRoster = function() end }

-- Who a GUID is
local guids = {
    ["Player-T"] = { "Rogue", "ROGUE", "Human", "Human" },
    ["Player-ORC"] = { "Warrior", "WARRIOR", "Orc", "Orc" },
    ["Player-GNOME"] = { "Mage", "MAGE", "Gnome", "Gnome" },
}
guids["Player-TINKER"] = { "Mage", "MAGE", "Gnome", "Gnome", 3 }
function GetPlayerInfoByGUID(g) local x = guids[g]; if x then return x[1], x[2], x[3], x[4], x[5] end end
function UnitRace(u) local x = units[u]; if x and x.race then return x.race, x.race end end
function UnitSex(u) local x = units[u]; return x and x.sex or 1 end
-- The client's race atlases (R22); the test can take one away
local missingAtlas = {}
C_Texture = { GetAtlasInfo = function(name)
    if name:match("^raceicon%-") and not missingAtlas[name] then return { width = 64, height = 64 } end
    return nil
end }

-- Whispers and invites
local told, invited = {}, {}
local chatFilters = {}
ChatFrameUtil = {
    SendTell = function(name) told[#told + 1] = name end,
    AddMessageEventFilter = function(event, fn) chatFilters[#chatFilters + 1] = { event = event, fn = fn } end,
}
C_PartyInfo = { InviteUnit = function(name) invited[#invited + 1] = name end }

-- Commander Muster: ratings by whatever name it is asked with
local ratings, asked = {}, {}
-- Like the real one, a bare name is tried on our realm first (Muster D14)
CommanderMuster = { RatingsFor = function(w)
    asked[#asked + 1] = w
    return ratings[w] or (not w:find("-", 1, true) and ratings[w .. "-Dreamscythe"]) or nil
end }
local function R(r2, r3, r5)
    local t = {}
    if r2 then t[2] = { rating = r2, wins = 30, played = 50 } end
    if r3 then t[3] = { rating = r3, wins = 10, played = 12 } end
    if r5 then t[5] = { rating = r5, wins = 5, played = 9 } end
    return t
end

local function Load(path)
    local chunk = assert(loadfile(path))
    chunk()
end

local function Fire(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    for _, f in ipairs(list) do
        local handler = f.__scripts.OnEvent
        if handler then handler(f, event, ...) end
    end
end

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
Load(ADDONS .. "/Commander_Recruit/CommanderRecruitEngine.lua")
Load(ADDONS .. "/Commander_Recruit/CommanderRecruitDB.lua")
Load(ADDONS .. "/Commander_Recruit/CommanderRecruit.lua")
Fire("ADDON_LOADED", "Commander_Recruit")
Fire("PLAYER_LOGIN")
CHECK(#harnessFailedErrors == 0, "login raised no errors", harnessFailedErrors[1])
CHECK(CommanderRecruitDB.EnableRecruit == true and CommanderRecruitDB.FreshMinutes == 15, "defaults applied")
CHECK(BINDING_NAME_COMMANDERRECRUIT_NEXT ~= nil, "the sweep key has a name in Key Bindings")

local function Tick() RunTickers() end
local function Col(size)
    local w = CommanderRecruit.Window()
    for _, c in ipairs(w.columns) do if c.size == size then return c end end
end
local function Shown(col)
    local out = {}
    for _, row in ipairs(col.rows) do if row.__shown and row.entry then out[#out + 1] = row end end
    return out
end
local function Repaint()
    -- A change marks the board dirty; the 1s ticker paints it
    Tick()
end

-- ===========================================================================
-- S. The button in the Social window (O)
-- ===========================================================================
do
    local b = CommanderRecruit.SocialButton()
    CHECK(b ~= nil and b.__shown, "the Social window gets a Recruit button")
    CHECK(b.__kind == "Button" and b.__template == nil,
        "...a plain Button with no secure template, so nothing protected is touched", tostring(b.__template))
    b.__scripts.OnClick(b)
    CHECK(CommanderRecruit.Window() and CommanderRecruit.Window().__shown, "...and clicking it opens Recruit")
    b.__scripts.OnClick(b)
    CHECK(not CommanderRecruit.Window().__shown, "...and clicking again shuts it")
    CommanderRecruitDB.SocialButton = false
    Commander.Notify(COMMANDER_RECRUIT_EVENTS.UPDATE)
    CHECK(not b.__shown, "the setting takes the button away")
    CommanderRecruitDB.SocialButton = true
    Commander.Notify(COMMANDER_RECRUIT_EVENTS.UPDATE)
    CHECK(b.__shown, "...and brings it back")
    Fire("PLAYER_ENTERING_WORLD")
    CHECK(CommanderRecruit.SocialButton() == b, "a second install is a no-op, never a second button")
end

-- ===========================================================================
-- F0. The friends list the client already holds is read with no event, and a
-- probe friend the removed Probe Ladder left behind comes off (R17)
-- ===========================================================================
do
    CommanderRecruitProbe = { ["Earlybird-Dreamscythe"] = { given = "Earlybird", at = now } }
    friends = { { name = "Earlybird", connected = false, level = 70, guid = "Player-T", notes = "Recruit probe" } }
    Tick()
    CHECK(friendRemoves[#friendRemoves] == "Earlybird" and #friends == 0,
        "leftover: a list the client already has is read without an event, and Recruit's leftover probe comes off")
    CHECK(CommanderRecruitProbe == nil, "leftover: ...and the record of leftovers goes away once empty")
    wipe(friendRemoves) -- the watch section counts from zero
end

-- ===========================================================================
-- A. The window
-- ===========================================================================
CommanderRecruit_Toggle()
local win = CommanderRecruit.Window()
CHECK(win and win.__shown, "/crecruit opens the window")
CHECK(win.__strata == "HIGH" and win.__toplevel == true, "on the suite's window layer, raised when clicked",
    tostring(win.__strata) .. " " .. tostring(win.__toplevel))
CHECK(#win.columns == 3 and win.columns[1].size == 2 and win.columns[2].size == 3 and win.columns[3].size == 5,
    "three columns side by side: 2v2, 3v3, 5v5")
Repaint()
CHECK(Col(2).count.__text == "nobody yet", "an empty board says so", Col(2).count.__text)
local inSpecial = false
for _, n in ipairs(UISpecialFrames) do if n == "CommanderRecruitFrame" then inSpecial = true end end
CHECK(inSpecial, "Escape closes it")

-- The row layout: every cell on one line; the name stretched between the
-- left cells and the numbers, never given a width of its own; the numbers
-- chained from the right edge, so no font size can make two of them meet
do
    local row = Col(2).rows[1]
    local cells = { "rank", "name", "rating", "record", "age" }
    local wraps = true
    for _, k in ipairs(cells) do if row[k].__wrap ~= false then wraps = false end end
    CHECK(wraps, "layout: no cell in a row may wrap onto a second line")
    local np = row.name.__points or {}
    CHECK(#np == 2 and np[1].point == "LEFT" and np[2].point == "RIGHT" and np[2].rel == row.rating
        and row.name.__w == nil, "layout: the name stretches from the rank to the rating")
    CHECK(row.age.__points[1].point == "RIGHT" and row.age.__points[1].rel == row,
        "layout: the age sits at the row's right edge")
    CHECK(row.record.__points[1].rel == row.age and row.rating.__points[1].rel == row.record,
        "layout: the win-loss and the rating chain off it, right to left")
    CHECK((row.record.__w or 0) >= 56, "layout: the win-loss has room for 456-505", row.record.__w)
    CHECK(row.eye.dot and row.eye.dot.__texture == "Interface\\Buttons\\WHITE8X8",
        "layout: the watch mark is a small dot, not an icon", row.eye.dot and row.eye.dot.__texture)
    CHECK(Col(2).__w == 280 and win.__w == 1064, "layout: three 280-wide columns beside the 176-wide search order",
        tostring(Col(2).__w) .. "/" .. tostring(win.__w))
end

-- ===========================================================================
-- B. The sweep: one /who per press
-- ===========================================================================
who.popWindow = true
CommanderRecruit_SweepStep()
CHECK(#who.sent == 1 and who.sent[1].text == '70-70 c-"Warrior"', "a press sends the first query",
    who.sent[1] and who.sent[1].text)
CHECK(who.sent[1].origin == 2, "...from the social origin, as the Who window does")
CHECK(who.toUi[#who.toUi] == true, "...with the answer routed to the list, not to chat")
CommanderRecruit_SweepStep()
CHECK(#who.sent == 1, "a second press while waiting sends nothing")
Repaint()
CHECK(win.sweepBar.text.__text:find("waiting for /who to answer"), "the sweep bar says it is waiting", win.sweepBar.text.__text)
CHECK(win.sweep.__text == "Sweep" and win.probe == nil and win.probeBar == nil,
    "one button and one bar: the probe is gone (R17)")

who.results = {
    { fullName = "Tanky-Dreamscythe", level = 70, filename = "WARRIOR", area = "Shattrath City", fullGuildName = "Lords" },
    { fullName = "Smashy", level = 70, filename = "WARRIOR", area = "Nagrand", fullGuildName = "" },
}
who.total = 2
ratings["Tanky-Dreamscythe"] = R(2100, 1900, nil)
-- /who gives a same-realm player bare; Muster is asked with the bare name
ratings["Smashy"] = R(1700, nil, 2050)
Fire("WHO_LIST_UPDATE")
CHECK(who.toUi[#who.toUi] == false, "the answer puts /who back to chat for your own use")
CHECK(#hidPanels == 1 and hidPanels[1] == FriendsFrame, "a Who window the sweep opened is shut again")
who.popWindow = false
CHECK(CommanderRecruit.Book().players["Tanky-Dreamscythe"] ~= nil, "who answered is on the book")
CommanderRecruit_SweepStep()
CHECK(#who.sent == 1, "the next press inside five seconds waits")
Advance(5)
CommanderRecruit_SweepStep()
CHECK(#who.sent == 2 and who.sent[2].text == '70-70 c-"Paladin"', "after the gap, the next class", who.sent[2] and who.sent[2].text)
who.results, who.total = {}, 120
for i = 1, 50 do who.results[i] = { fullName = "Pally" .. i, level = 70, filename = "PALADIN" } end
Fire("WHO_LIST_UPDATE")
Advance(5)
Repaint()
CHECK(win.sweepBar.text.__text:find("Sweep: 2 of 12 queries"), "the sweep bar counts the split in", win.sweepBar.text.__text)
CHECK(math.abs((win.sweepBar.fraction or 0) - 2 / 12) < 0.001, "...and fills to match", win.sweepBar.fraction)
who.popWindow = false
FriendsFrame.__shown = true          -- the player has the Who window open
CommanderRecruit_SweepStep()
CHECK(who.sent[3].text == '70-70 c-"Paladin" r-"Human"', "a class past the cap is asked race by race", who.sent[3].text)
who.results, who.total = {}, 0
Fire("WHO_LIST_UPDATE")
CHECK(#hidPanels == 1 and FriendsFrame.__shown, "a Who window the player opened is left open")
Advance(5)
CommanderRecruit_SweepStep()
CHECK(who.sent[4].text == '70-70 c-"Paladin" r-"Dwarf"', "the next race", who.sent[4].text)
-- An answer that never comes is given up on
Advance(9)
CommanderRecruit_SweepStep()
CHECK(#who.sent == 5 and who.sent[5].text == '70-70 c-"Paladin" r-"Draenei"',
    "an answer that never comes counts as nobody, and the sweep moves on (asking again looped for ever)",
    who.sent[5] and who.sent[5].text)

-- ===========================================================================
-- C. The board
-- ===========================================================================
Repaint()
local two = Shown(Col(2))
CHECK(#two == 2 and two[1].name.__text == "Tanky" and two[1].rating.__text == 2100, "2v2: highest first",
    two[1] and tostring(two[1].name.__text))
CHECK(two[2].name.__text == "Smashy" and two[2].record.__text == "30-20", "...with the win-loss")
local five = Shown(Col(5))
CHECK(#five == 1 and five[1].name.__text == "Smashy", "5v5 has its own order")
CHECK(Col(2).count.__text == "2 online", "the column counts its players", Col(2).count.__text)
CHECK(win.status.__text:find("^2 rated players online, of 53"), "the status counts rated and seen (you among them, R25)", win.status.__text)
CHECK(win.foot.__text:find("^51 online with no rating"), "the unrated are counted below", win.foot.__text)

-- A click whispers, a right-click invites; a bare name is used bare
-- With Commander Contacts: the conversation with them, history and all
local opened = {}
CommanderContacts_OpenWhisper = function(name, fields)
    opened[#opened + 1] = { name = name, class = fields and fields.class }
    return true
end
two[1].__scripts.OnClick(two[1], "LeftButton")
CHECK(opened[1] and opened[1].name == "Tanky-Dreamscythe" and opened[1].class == "WARRIOR" and #told == 0,
    "left-click opens their conversation in Contacts, not a bare whisper", opened[1] and opened[1].name)
-- Contacts switched off answers false: a plain whisper instead
CommanderContacts_OpenWhisper = function() return false end
two[1].__scripts.OnClick(two[1], "LeftButton")
CHECK(told[1] == "Tanky-Dreamscythe", "without Contacts, left-click whispers them in chat", told[1])
CommanderContacts_OpenWhisper = nil
two[2].__scripts.OnClick(two[2], "RightButton")
CHECK(invited[1] == "Smashy", "right-click invites them, by the name the game gave", invited[1])
CHECK(two[1].name.__text == "Tanky", "a home-realm player is written without a realm tag")
GameTooltip.__lines = {}
two[1].__scripts.OnEnter(two[1])
local tip = table.concat(GameTooltip.__lines or {}, " | ")
CHECK(tip:find("Lords") and tip:find("Shattrath City") and tip:find("/who"), "the tooltip says who, where and how they were seen", tip)

-- ===========================================================================
-- D. Every other source of "online"
-- ===========================================================================
lfg[7] = { { name = "Lfgguy", classFilename = "ROGUE", level = 70 } }
ratings["Lfgguy"] = R(nil, 2250, nil)
Fire("LFG_LIST_SEARCH_RESULTS_RECEIVED")
Repaint()
local sawBare = false
for _, w in ipairs(asked) do if w == "Lfgguy" then sawBare = true end end
CHECK(sawBare, "a group finder name with no realm is asked for bare (Ladder L8)")
local three = Shown(Col(3))
CHECK(three[1] and three[1].name.__text == "Lfgguy" and three[1].rating.__text == 2250, "the group finder fills the board")

ratings["Talker-Nightslayer"] = R(nil, 2400, nil)
Fire("CHAT_MSG_CHANNEL", "lfm 3s", "Talker-Nightslayer", "", "2. Trade", "", "", 0, 2, "Trade", 0, 1, "Player-T")
CHECK(CommanderRecruit.Book().players["Talker-Nightslayer"] and CommanderRecruit.Book().players["Talker-Nightslayer"].class == "ROGUE",
    "a channel line is a sighting, its class from the GUID")

-- Hide other realms (R27), on by default
do
    local list = win.search
    local function Names(size)
        local out = {}
        for _, r in ipairs(Shown(Col(size))) do out[#out + 1] = r.name.__text end
        return table.concat(out, ",")
    end
    Repaint()
    CHECK(CommanderRecruitDB.HideOtherRealms == true and list.hideAway.__checked == true,
        "other realms: Hide other realms is on by default")
    CHECK(not Names(3):find("Talker"), "other realms: a rated player written with another realm is hidden", Names(3))
    local askedTalker = false
    for _, w in ipairs(asked) do if w == "Talker-Nightslayer" then askedTalker = true end end
    CHECK(not askedTalker, "other realms: ...and never asked about, so the feed is handed no Nightslayer names")
    CHECK(win.status.__text:find("1 from other realms hidden"), "other realms: the header counts them", win.status.__text)

    -- A bare group finder name the feed has on another realm only
    CommanderLadder = { Lookup = function(name, realm, anyRealm)
        if name == "Farguy" and anyRealm then return { [3] = { 2300, 10, 2 } } end
    end }
    lfg[8] = { { name = "Farguy", classFilename = "MAGE", level = 70 } }
    ratings["Farguy"] = R(nil, 2300, nil)
    Fire("LFG_LIST_SEARCH_RESULTS_RECEIVED")
    Repaint()
    CHECK(not Names(3):find("Farguy"), "other realms: a group finder name the feed has only elsewhere is hidden", Names(3))
    CHECK(Names(3):find("Lfgguy"), "other realms: ...one the feed cannot place stays", Names(3))
    CHECK(win.status.__text:find("2 from other realms hidden"), "other realms: ...and is counted", win.status.__text)

    -- Switched off: both come back marked *, and neither can be watched
    list.hideAway.__scripts.OnClick(list.hideAway)
    Repaint()
    CHECK(CommanderRecruitDB.HideOtherRealms == false and list.hideAway.__checked == false,
        "other realms: the switch turns it off")
    local shown = Names(3)
    CHECK(shown:find("Talker|cff888888*|r", 1, true) and shown:find("Farguy|cff888888*|r", 1, true),
        "other realms: ...both come back, marked *", shown)
    CHECK(not win.status.__text:find("other realms"), "other realms: ...and the header stops counting", win.status.__text)
    CHECK(not CommanderRecruit.CanFriend(CommanderRecruit.Book().players["Farguy-Dreamscythe"]),
        "other realms: a finder name placed elsewhere cannot be watched")
    list.hideAway.__scripts.OnClick(list.hideAway)
    Repaint()
    CHECK(CommanderRecruitDB.HideOtherRealms == true and not Names(3):find("Talker") and not Names(3):find("Farguy"),
        "other realms: on again, hidden again", Names(3))
    CommanderLadder = nil
    lfg[8] = nil
    CommanderRecruit.Book().players["Farguy-Dreamscythe"] = nil
end
Fire("CHAT_MSG_SAY", "zug", "Grunt", "", "", "", "", 0, 0, "", 0, 2, "Player-ORC")
CHECK(CommanderRecruit.Book().players["Grunt-Dreamscythe"] == nil, "say from the other faction is not")
Fire("CHAT_MSG_SAY", "hi", "Gnomey", "", "", "", "", 0, 0, "", 0, 3, "Player-GNOME")
CHECK(CommanderRecruit.Book().players["Gnomey-Dreamscythe"] ~= nil, "say from your own faction is")
Fire("CHAT_MSG_GUILD", "hey", "Devinp", "", "", "", "", 0, 0, "", 0, 4, "Player-ME")
CHECK(CommanderRecruit.Book().players["Devinp-Dreamscythe"] and CommanderRecruit.Book().players["Devinp-Dreamscythe"].source == "self",
    "your own chat line is no sighting: you are listed as yourself (R25)")

guild = { { name = "Mate-Dreamscythe", level = 70, class = "MAGE", zone = "Ironforge", online = true } }
Fire("GUILD_ROSTER_UPDATE")
CHECK(CommanderRecruit.Book().players["Mate-Dreamscythe"] ~= nil, "a guildmate online is a sighting")
guild[1].online = false
Fire("GUILD_ROSTER_UPDATE")
CHECK(CommanderRecruit.Book().players["Mate-Dreamscythe"] == nil, "...and off the board when the roster says offline")

friends = { { name = "Pal", connected = true, level = 70, area = "Nagrand", guid = "Player-GNOME" } }
Fire("FRIENDLIST_UPDATE")
CHECK(CommanderRecruit.Book().players["Pal-Dreamscythe"] ~= nil, "an online friend is a sighting")
friends[1].connected = false
Fire("FRIENDLIST_UPDATE")
CHECK(CommanderRecruit.Book().players["Pal-Dreamscythe"] == nil, "...and gone when they log off")

units.mouseover = { name = "Passer", guid = "Player-P", faction = "Alliance", class = "DRUID", level = 70 }
Fire("UPDATE_MOUSEOVER_UNIT")
CHECK(CommanderRecruit.Book().players["Passer-Dreamscythe"] ~= nil, "a friendly player under the cursor is a sighting")
units.mouseover = { name = "Enemy", guid = "Player-E", faction = "Horde", class = "ROGUE", level = 70 }
Fire("UPDATE_MOUSEOVER_UNIT")
CHECK(CommanderRecruit.Book().players["Enemy-Dreamscythe"] == nil, "the other faction is not")

-- Each source has its own switch
CommanderRecruitDB.UseChat = false
Fire("CHAT_MSG_CHANNEL", "wts", "Seller", "", "", "", "", 0, 2, "", 0, 5, "Player-T")
CHECK(CommanderRecruit.Book().players["Seller-Dreamscythe"] == nil, "Chat off: a channel line is ignored")
CommanderRecruitDB.UseChat = true

-- ===========================================================================
-- W. The watch list: friends Recruit adds, and only those it removes
-- ===========================================================================
do
    friends = { { name = "Oldpal", connected = true, level = 70, guid = "Player-GNOME", notes = "" } }
    Fire("FRIENDLIST_UPDATE")
    ratings["Oldpal"] = R(1950, nil, nil)      -- a same-realm friend is bare, like /who
    Repaint()
    local function RowOf(size, name)
        for _, row in ipairs(Shown(Col(size))) do if row.name.__text == name then return row end end
    end

    -- Tanky (from the sweep) is not a friend: watching adds them, noted
    local tanky = RowOf(2, "Tanky")
    CHECK(tanky and not CommanderRecruit.IsWatched(tanky.entry.player), "watch: nobody is watched to begin with")
    tanky.eye.__scripts.OnClick(tanky.eye)
    CHECK(#friendAdds == 1 and friendAdds[1].name == "Tanky-Dreamscythe" and friendAdds[1].notes == "Recruit watch",
        "watch: the eye adds them to your friends list, with the note", friendAdds[1] and friendAdds[1].name)
    CHECK(CommanderRecruit.IsWatched(tanky.entry.player), "watch: ...and they are watched")
    CHECK(CommanderRecruitWatch["Tanky-Dreamscythe"] and CommanderRecruitWatch["Tanky-Dreamscythe"].byUs == true,
        "watch: saved per character, as added by Recruit")
    -- The server's list arrives with them on it
    friends[#friends + 1] = { name = "Tanky", connected = true, level = 70, guid = "Player-T", notes = "Recruit watch" }
    Fire("FRIENDLIST_UPDATE")
    CHECK(CommanderRecruitWatch["Tanky-Dreamscythe"].confirmed and not CommanderRecruitWatch["Tanky-Dreamscythe"].pendingAt,
        "watch: the friends list confirms the add")
    Repaint()
    CHECK(win.status.__text:find("watching 1, 1 on"), "watch: the header counts them", win.status.__text)

    -- An existing friend is only marked
    local old = RowOf(2, "Oldpal")
    CHECK(old ~= nil, "watch: an online friend is on the board")
    old.eye.__scripts.OnClick(old.eye)
    CHECK(#friendAdds == 1, "watch: an existing friend is not added again")
    CHECK(CommanderRecruitWatch["Oldpal-Dreamscythe"].byUs == false, "watch: ...and is marked as yours")
    -- Un-watching: Recruit's friend comes off, yours stays
    old.eye.__scripts.OnClick(old.eye)
    CHECK(#friendRemoves == 0 and not CommanderRecruit.IsWatched(old.entry.player),
        "watch: un-watching a friend you already had leaves them your friend")
    tanky = RowOf(2, "Tanky")
    tanky.eye.__scripts.OnClick(tanky.eye)
    CHECK(#friendRemoves == 1 and friendRemoves[1] == "Tanky",
        "watch: un-watching a friend Recruit added takes them off, by the list's own name", friendRemoves[1])

    -- Offline watched friends leave the board at once; online ones need no sweep
    tanky = RowOf(2, "Tanky")
    tanky.eye.__scripts.OnClick(tanky.eye)
    friends[#friends + 1] = { name = "Tanky", connected = false, level = 70, guid = "Player-T", notes = "Recruit watch" }
    CommanderRecruitDB.UseFriends = false
    Fire("FRIENDLIST_UPDATE")
    CHECK(CommanderRecruit.Book().players["Tanky-Dreamscythe"] == nil,
        "watch: a watched friend logging off is off the board, even with the Friends source off")
    friends[#friends].connected = true
    Fire("FRIENDLIST_UPDATE")
    CHECK(CommanderRecruit.Book().players["Tanky-Dreamscythe"] ~= nil, "watch: ...and back when they log on")
    CommanderRecruitDB.UseFriends = true

    -- Your own rewrite of the note makes them yours
    friends[#friends].notes = "my 2s partner"
    Fire("FRIENDLIST_UPDATE")
    CHECK(CommanderRecruitWatch["Tanky-Dreamscythe"].byUs == false, "watch: a rewritten note makes them a friend Recruit never removes")
    friends[#friends].notes = "Recruit watch"
    CommanderRecruitWatch["Tanky-Dreamscythe"].byUs = true

    -- Removed by hand: no longer watched
    table.remove(friends, #friends)
    Fire("FRIENDLIST_UPDATE")
    CHECK(CommanderRecruitWatch["Tanky-Dreamscythe"] == nil, "watch: a friend you removed yourself is no longer watched")

    -- An empty list (login) is not a removal
    CommanderRecruitWatch["Oldpal-Dreamscythe"] = { name = "Oldpal", byUs = false, confirmed = true }
    local keep = friends
    friends = {}
    Fire("FRIENDLIST_UPDATE")
    CHECK(CommanderRecruitWatch["Oldpal-Dreamscythe"] ~= nil, "watch: an empty friends list removes nobody from the watch")
    friends = keep
    Fire("FRIENDLIST_UPDATE")

    -- An add that never lands is given up on, and says why
    local smashy = RowOf(2, "Smashy")
    printLog = {}
    smashy.eye.__scripts.OnClick(smashy.eye)
    CHECK(friendAdds[#friendAdds].name == "Smashy", "watch: a bare name is added as the game gave it", friendAdds[#friendAdds].name)
    Advance(11)
    Tick()
    CHECK(CommanderRecruitWatch["Smashy-Dreamscythe"] == nil, "watch: an add that never shows up is dropped")
    local said = table.concat(printLog, " | ")
    CHECK(said:find("could not add Smashy"), "watch: ...and the chat says so", said)

    -- Another realm cannot be friended (R11): no dot, and no add if asked
    local talker = { key = "Talker-Nightslayer", name = "Talker", realm = "Nightslayer", bare = false }
    CHECK(not CommanderRecruit.CanFriend(talker), "watch: a player on another realm cannot be friended")
    local addsBefore = #friendAdds
    CommanderRecruit.ToggleWatch(talker)
    CHECK(#friendAdds == addsBefore and not CommanderRecruit.IsWatched(talker),
        "watch: ...so asking to watch one adds nobody")
    CHECK(CommanderRecruit.CanFriend({ key = "Lfgguy-Dreamscythe", name = "Lfgguy", bare = true }),
        "watch: a bare name is tried as the game gave it")

    -- Stop Watching All: removes only what Recruit added
    local t2 = RowOf(2, "Tanky")
    t2.eye.__scripts.OnClick(t2.eye)
    friends[#friends + 1] = { name = "Tanky", connected = true, level = 70, guid = "Player-T", notes = "Recruit watch" }
    Fire("FRIENDLIST_UPDATE")
    local before = #friendRemoves
    local removed, kept = CommanderRecruit.UnwatchAll()
    CHECK(removed == 1 and kept == 1 and #friendRemoves == before + 1 and friendRemoves[#friendRemoves] == "Tanky",
        "watch: Stop Watching All removes Recruit's friends and keeps yours", removed .. "/" .. kept)
    CHECK(next(CommanderRecruitWatch) == nil, "watch: ...and watches nobody")
    local oldpalStill = false
    for _, f in ipairs(friends) do if f.name == "Oldpal" then oldpalStill = true end end
    CHECK(oldpalStill, "watch: your own friend is still on your list")
end

-- ===========================================================================
-- L. Leftovers of the removed probe (R17): only Recruit's, only by its note
-- ===========================================================================
do
    friends = {
        { name = "Oldpal", connected = true, level = 70, guid = "Player-GNOME", notes = "" },
        { name = "Left", connected = false, level = 70, guid = "Player-T", notes = "Recruit probe" },
        { name = "Claimed", connected = false, level = 70, guid = "Player-T", notes = "my 2s partner" },
        { name = "Watched", connected = false, level = 70, guid = "Player-T", notes = "Recruit probe" },
        { name = "Noteless", connected = false, level = 70, guid = "Player-T", notes = nil },
        { name = "", connected = false, level = 0, guid = "Player-X", notes = "Recruit probe" },
    }
    CommanderRecruitWatch["Watched-Dreamscythe"] = { name = "Watched", byUs = false, at = now, confirmed = true }
    CommanderRecruitProbe = {
        ["Left-Dreamscythe"] = { given = "Left", at = now },
        ["Claimed-Dreamscythe"] = { given = "Claimed", at = now },
        ["Watched-Dreamscythe"] = { given = "Watched", at = now },
        ["Noteless-Dreamscythe"] = { given = "Noteless", at = now },
        ["Away-Dreamscythe"] = { given = "Away", at = now },
        ["Ancient-Dreamscythe"] = { given = "Ancient", at = now - 2 * 86400 },
    }
    local removes0 = #friendRemoves
    local ok, err = pcall(Fire, "FRIENDLIST_UPDATE")
    CHECK(ok, "leftover: a row with no name yet is no error", err)
    local function OnList(name)
        for _, f in ipairs(friends) do if f.name == name then return true end end
        return false
    end
    CHECK(#friendRemoves == removes0 + 1 and friendRemoves[removes0 + 1] == "Left" and not OnList("Left"),
        "leftover: only the one carrying Recruit's note, not watched, comes off")
    CHECK(OnList("Oldpal") and OnList("Claimed") and OnList("Watched") and OnList("Noteless"),
        "leftover: your friend, a note you wrote, a watched one and a noteless one all stay")
    local rec = CommanderRecruitProbe or {}
    CHECK(rec["Claimed-Dreamscythe"] == nil and rec["Watched-Dreamscythe"] == nil and rec["Ancient-Dreamscythe"] == nil,
        "leftover: yours, watched and two-day-old records are let go")
    CHECK(rec["Noteless-Dreamscythe"] ~= nil and rec["Away-Dreamscythe"] ~= nil,
        "leftover: a noteless one and one not on the list yet are kept for a day")
    for _, f in ipairs(friends) do if f.name == "Noteless" then f.notes = "Recruit probe" end end
    Fire("FRIENDLIST_UPDATE")
    CHECK(not OnList("Noteless"), "leftover: its note back, it comes off")
    -- A day on (aged in the record, not on the clock: the board's sightings must stay fresh)
    for _, r in pairs(CommanderRecruitProbe or {}) do r.at = now - 86400 - 60 end
    Fire("FRIENDLIST_UPDATE")
    CHECK(CommanderRecruitProbe == nil, "leftover: a day on, nothing is left to track")
    CommanderRecruitWatch["Watched-Dreamscythe"] = nil
    friends = {}
    Fire("FRIENDLIST_UPDATE")
    CHECK(BINDING_NAME_COMMANDERRECRUIT_PROBE == nil and BINDING_NAME_COMMANDERRECRUIT_SWEEP == nil
        and BINDING_NAME_COMMANDERRECRUIT_NEXT == "Sweep: Next /who", "one sweep key, under the name already bound")
    CHECK(CommanderRecruit_ProbeStep == nil, "the probe's press is gone")
end

-- ===========================================================================
-- Q. Scrolling and the ticker do not rebuild the board (R18)
-- ===========================================================================
do
    Commander.Notify(COMMANDER_RECRUIT_EVENTS.UPDATE)
    who.results, who.total = {}, 0
    for i = 1, 40 do
        local name = string.format("Scroller%02d", i)
        who.results[i] = { fullName = name .. "-Dreamscythe", level = 70, filename = "ROGUE", area = "Shattrath City",
            fullGuildName = "" }
        ratings[name .. "-Dreamscythe"] = R(2500 - i, nil, nil)
    end
    who.total = 40
    Fire("WHO_LIST_UPDATE")
    Repaint()
    local col = Col(2)
    CHECK(col.rows[1].name.__text == "Scroller01", "scroll: the best first", col.rows[1].name.__text)
    local asked0 = #asked
    col.__scripts.OnMouseWheel(col, -1)
    CHECK(col.rows[1].name.__text == "Scroller04" and col.rows[1].rank.__text == 4,
        "scroll: a notch moves three rows at once", tostring(col.rows[1].name.__text))
    for _ = 1, 5 do col.__scripts.OnMouseWheel(col, -1) end
    col.__scripts.OnMouseWheel(col, 1)
    CHECK(#asked == asked0, "scroll: no rating is looked up while scrolling", #asked - asked0)
    Tick()
    CHECK(#asked == asked0, "scroll: a tick with nothing new looks nothing up", #asked - asked0)
    CHECK(col.offset > 0, "scroll: the ticker keeps where you scrolled to", col.offset)
    Advance(6)
    Tick()
    CHECK(#asked == asked0, "scroll: the periodic rebuild reuses the ratings it has", #asked - asked0)
    Fire("CHAT_MSG_CHANNEL", "lf 2s", "Newcomer", "", "2. Trade", "", "", 0, 2, "Trade", 0, 9, "Player-NEW")
    Tick()
    CHECK(#asked == asked0 + 1, "scroll: a new player costs one lookup, not one per player", #asked - asked0)
    Advance(301)
    Tick()
    CHECK(#asked > asked0 + 1, "scroll: after five minutes ratings are looked up again", #asked - asked0)
    who.results, who.total = {}, 0
    for i = 1, 40 do
        local key = string.format("Scroller%02d", i) .. "-Dreamscythe"
        ratings[key], CommanderRecruit.Book().players[key] = nil, nil
    end
    CommanderRecruit.Book().players["Newcomer-Dreamscythe"] = nil
    col.offset = 0
end

-- ===========================================================================
-- E. Filters, freshness, the master switch
-- ===========================================================================
CommanderRecruitDB.MinRating = 2000
Commander.Notify(COMMANDER_RECRUIT_EVENTS.UPDATE)
Repaint()
two = Shown(Col(2))
CHECK(#two == 1 and two[1].name.__text == "Tanky", "a lowest rating hides the rest of 2v2")
CHECK(#Shown(Col(5)) == 1, "...and keeps a 2050 in 5v5")
CommanderRecruitDB.MinRating = 0
Commander.Notify(COMMANDER_RECRUIT_EVENTS.UPDATE)

Advance(16 * 60)
Repaint()
CHECK(#Shown(Col(2)) == 0 and #Shown(Col(3)) == 0, "fifteen minutes unseen: off the board")
Fire("LFG_LIST_SEARCH_RESULT_UPDATED")
Repaint()
CHECK(#Shown(Col(3)) == 1, "seen again: back on")

CHECK(CommanderRecruit.Status():find("rated: 0 in 2v2, 1 in 3v3"), "the status line", CommanderRecruit.Status())

CommanderRecruitDB.EnableRecruit = false
Commander.Notify(COMMANDER_RECRUIT_EVENTS.UPDATE)
CHECK(not win.__shown, "the master switch shuts the window")
local sent = #who.sent
CommanderRecruit_SweepStep()
CHECK(#who.sent == sent, "...and the sweep sends nothing")
Fire("CHAT_MSG_CHANNEL", "x", "Ghost", "", "", "", "", 0, 2, "", 0, 6, "Player-T")
CHECK(CommanderRecruit.Book().players["Ghost-Dreamscythe"] == nil, "...and nothing is watched")
CommanderRecruitDB.EnableRecruit = true

CommanderRecruit.Clear()
CHECK(next(CommanderRecruit.Book().players) == nil, "Forget All empties the book")

-- ===========================================================================
-- R. The steered sweep (R20): Commander Ladder's roster aims each /who
-- ===========================================================================
do
    -- these fixtures are sized for the stop at 1 (R20); R23's stop is checked on its own
    local stopWas = CommanderRecruit_Engine.MIN_EXPECT
    CommanderRecruit_Engine.MIN_EXPECT = 1.0
    local depthWas = CommanderRecruitDB.SweepDepth
    CommanderRecruitDB.SweepDepth = 1
    local fragmentsWere = CommanderRecruit_Engine.NAME_FRAGMENTS
    CommanderRecruit_Engine.NAME_FRAGMENTS = false -- class and guild logic only (R26 has its own section)
    local DAY = 86400
    local function L(name, class, race, guild, best, faction)
        return { key = name .. "-Dreamscythe", name = name, faction = faction or "A", class = class, race = race,
            guild = guild, last = now - 3600, best = best or 2100 }
    end
    local ladderRoster = {
        L("Lion1", "PRIEST", "Human", "Lions"), L("Lion2", "WARRIOR", "Dwarf", "Lions"),
        L("Lion3", "MAGE", "Gnome", "Lions"), L("Lion4", "ROGUE", "NightElf", "Lions"),
        L("Lion5", "PRIEST", "Dwarf", "Lions"), L("Lion6", "WARRIOR", "Human", "Lions"),
        L("Lion7", "MAGE", "Human", "Lions"), L("Lion8", "ROGUE", "Human", "Lions"),
        L("Lowly", "HUNTER", "Dwarf", "Lions", 1500),
        L("Solo1", "PALADIN", "Human"), L("Solo2", "PALADIN", "Human"), L("Solo3", "PALADIN", "Human"),
        L("Solo4", "PALADIN", "Human"), L("Solo5", "PALADIN", "Human"), L("Solo6", "PALADIN", "Human"),
        L("Solo7", "PALADIN", "Human"),
        L("Grunt", "WARRIOR", "Orc", "Horde Guild", 2400, "H"),
    }
    local rosterAsked = {}
    CommanderLadder = { Roster = function(realm)
        rosterAsked[#rosterAsked + 1] = realm
        return ladderRoster
    end }
    win:Show()
    Advance(6)
    Repaint()
    local bar = function() return win.sweepBar.text.__text end
    CHECK(rosterAsked[1] == "Dreamscythe", "steer: the roster is asked for our realm", rosterAsked[1])
    CHECK(bar():find("^Sweep: not started · aimed by the ladder at 16 rated Alliance here, ~%d+ presses for ~%d+ of them · first: arena matches %(~10 rated%) · ready"),
        "steer: the bar says the sweep is aimed, at how many, and what it asks first", bar())
    local sent0 = #who.sent
    CommanderRecruit_SweepStep()
    CHECK(#who.sent == sent0 + 1 and who.sent[#who.sent].text == '70-70 z-"Arena"',
        "steer: the first press asks who is in an arena", who.sent[#who.sent] and who.sent[#who.sent].text)
    CHECK(CommanderRecruit.Sweep().mode == "steered", "steer: the sweep is the steered one")
    Repaint()
    CHECK(bar():find("waiting for /who to answer: arena matches"), "steer: the bar says what it is waiting on", bar())
    who.results = { { fullName = "Lion2", level = 70, filename = "WARRIOR", area = "Nagrand Arena", fullGuildName = "Lions" } }
    who.total = 1
    Fire("WHO_LIST_UPDATE")
    CHECK(CommanderRecruit.Book().players["Lion2-Dreamscythe"] ~= nil and CommanderRecruit.Sweep().found == 1,
        "steer: an arena answer puts its rated player on the board and counts the find")
    CHECK(CommanderRecruit.Learned().arenas.arena.est == 5.5, "steer: the arena's estimate learns from what it found",
        CommanderRecruit.Learned().arenas.arena.est)
    Advance(5)
    Repaint()
    CHECK(bar():find("next: Ruins of Lordaeron %(~5%.0 rated%) · ready"), "steer: the bar says what kind of query is next", bar())
    CHECK(bar():find("^Sweep: 1 asked, ~%d+ to go"), "steer: the bar counts what was asked and the presses forecast to go (R23)", bar())
    CommanderRecruit_SweepStep()
    CHECK(who.sent[#who.sent].text == '70-70 z-"Ruins of Lordaeron"', "steer: then the Ruins of Lordaeron")
    Advance(9) -- no answer: counted as nobody
    Repaint()
    CHECK(bar():find("next: guild <Lions> %(~2%.0 rated%)"), "steer: then the guild with the most rated players not yet seen", bar())
    CommanderRecruit_SweepStep()
    CHECK(who.sent[#who.sent].text == '70-70 g-"Lions"', "steer: one /who for the whole guild", who.sent[#who.sent].text)
    who.results = {
        { fullName = "Lion1", level = 70, filename = "PRIEST", area = "Shattrath City", fullGuildName = "Lions" },
        { fullName = "Lion2", level = 70, filename = "WARRIOR", area = "Nagrand Arena", fullGuildName = "Lions" },
        { fullName = "Cub", level = 70, filename = "DRUID", area = "Darnassus", fullGuildName = "Lions" },
    }
    who.total = 3
    Fire("WHO_LIST_UPDATE")
    CHECK(CommanderRecruit.Sweep().found == 2, "steer: the guild's new rated player counted, the one seen in the arena not twice")
    -- Solo3 is on the board from chat; the paladins' answer will not list them
    Fire("CHAT_MSG_CHANNEL", "lf 3s", "Solo3", "", "2. Trade", "", "", 0, 2, "Trade", 0, 9, "Player-SOLO3")
    CHECK(CommanderRecruit.Book().players["Solo3-Dreamscythe"] ~= nil, "steer: a paladin seen in chat is on the book")
    Advance(5)
    Repaint()
    CHECK(bar():find("next: Paladin %(~1%.5 rated%)"), "steer: then a whole class, expected under 50", bar())
    CommanderRecruit_SweepStep()
    CHECK(who.sent[#who.sent].text == '70-70 c-"Paladin"', "steer: asked whole", who.sent[#who.sent].text)
    printLog = {}
    who.results = { { fullName = "Solo1", level = 70, filename = "PALADIN", area = "Ironforge", fullGuildName = "" } }
    who.total = 1
    Fire("WHO_LIST_UPDATE")
    CHECK(CommanderRecruit.Book().players["Solo3-Dreamscythe"] == nil,
        "steer: a class answered under 50 without them takes a rated player seen earlier off the board")
    local said = table.concat(printLog, " | ")
    CHECK(said:find("sweep done: 4 queries, 3 rated players found"), "steer: the sweep says when it is done and what it found", said)
    Repaint()
    CHECK(bar():find("^Sweep: done, 4 queries, 3 rated found %(1 unanswered%)"), "steer: ...and so does the bar", bar())
    CHECK(math.abs((win.sweepBar.fraction or 0) - 1) < 0.001, "steer: ...full")
    do
        local full = ladderRoster
        ladderRoster = { L("Solo1", "PALADIN", "Human") }
        Advance(6)
        local sentD = #who.sent
        CommanderRecruit_SweepStep()
        Repaint()
        CHECK(#who.sent == sentD and bar():find("^Sweep: done, 4 queries, 3 rated found"),
            "steer: a press with nothing worth asking sends nothing and keeps the last sweep's count", bar())
        ladderRoster = full
    end

    -- The lowest rating shown narrows who is looked for
    CommanderRecruitDB.MinRating = 2000
    Commander.Notify(COMMANDER_RECRUIT_EVENTS.UPDATE)
    Advance(6)
    Repaint()
    CHECK(bar():find("again from: nothing worth a /who now"),
        "steer: done, a new sweep right after remembers who it just proved offline and what it just asked (R23)", bar())
    CommanderRecruit.Clear()
    Advance(6)
    Repaint()
    CHECK(bar():find("aimed by the ladder at 15 rated Alliance"), "steer: a 1500 is not looked for when 2000 is the lowest shown", bar())
    CommanderRecruitDB.MinRating = 0
    Commander.Notify(COMMANDER_RECRUIT_EVENTS.UPDATE)

    -- Nothing worth a /who: the bar says so and a press sends nothing
    ladderRoster = { L("Solo1", "PALADIN", "Human") }
    CommanderRecruit.Learned().arenas.arena.at = now
    CommanderRecruit.Learned().arenas.ruins = { est = 1.5, at = now }
    Advance(6)
    Repaint()
    CHECK(bar():find("nothing worth a /who now"), "steer: nothing worth asking is said", bar())
    CHECK(win.sweep.__enabled == false, "steer: ...and the button greys out", tostring(win.sweep.__enabled))
    local sentN = #who.sent
    CommanderRecruit_SweepStep()
    CHECK(#who.sent == sentN, "steer: ...and a press sends nothing")

    -- No class, race or guild in the ladder data: today's plan
    ladderRoster = {}
    CommanderRecruit.Clear()
    Advance(6)
    Repaint()
    CHECK(bar():find("each press asks /who for the next class at level 70 · first: Warrior · ready"),
        "steer: without the roster, the fixed plan, and the bar names its first class", bar())
    CommanderRecruit_SweepStep()
    CHECK(who.sent[#who.sent].text == '70-70 c-"Warrior"' and CommanderRecruit.Sweep().mode == nil,
        "steer: ...and the press asks for it", who.sent[#who.sent].text)
    Advance(9)
    CommanderLadder = nil
    CommanderRecruit.Clear()
    CommanderRecruit_Engine.MIN_EXPECT = stopWas
    CommanderRecruitDB.SweepDepth = depthWas
    CommanderRecruit_Engine.NAME_FRAGMENTS = fragmentsWere
end

-- ===========================================================================
-- O. The search order (R21): a class list to reorder by dragging, and to
-- switch classes off; the sweep follows it
-- ===========================================================================
do
    -- these fixtures are sized for the stop at 1 (R20); R23's stop is checked on its own
    local stopWas = CommanderRecruit_Engine.MIN_EXPECT
    CommanderRecruit_Engine.MIN_EXPECT = 1.0
    local depthWas = CommanderRecruitDB.SweepDepth
    CommanderRecruitDB.SweepDepth = 1
    local fragmentsWere = CommanderRecruit_Engine.NAME_FRAGMENTS
    CommanderRecruit_Engine.NAME_FRAGMENTS = false -- class and guild logic only (R26 has its own section)
    -- the session remembers what section R asked and found (R23): start this one clean
    wipe(CommanderRecruit.Learned().askedAt)
    wipe(CommanderRecruit.Learned().players)
    local function L(name, class, guild)
        return { key = name .. "-Dreamscythe", name = name, faction = "A", class = class, race = "Human",
            guild = guild, last = now - 3600, best = 2100 }
    end
    local ladderRoster = {}
    for i = 1, 12 do ladderRoster[#ladderRoster + 1] = L("Pal" .. i, "PALADIN") end
    for i = 1, 6 do ladderRoster[#ladderRoster + 1] = L("Pri" .. i, "PRIEST", "G") end
    for i = 1, 4 do ladderRoster[#ladderRoster + 1] = L("Rog" .. i, "ROGUE", "G") end
    CommanderLadder = { Roster = function() return ladderRoster end }
    CommanderRecruit.Learned().arenas.arena = { est = 0.5, at = now }  -- arenas quiet: classes decide
    CommanderRecruit.Learned().arenas.ruins = { est = 0.5, at = now }
    CommanderRecruit.Clear()
    local list = win.search
    local bar = function() return win.sweepBar.text.__text end
    local function RowOf(class)
        for _, row in ipairs(list.rows) do if row.class == class then return row end end
    end
    Advance(6)
    Repaint()
    CHECK(list and #list.rows == 9 and list.title.__text == "Search order", "order: a list of the nine classes beside the board")
    CHECK(list.rows[1].class == "WARRIOR" and list.rows[9].class == "DRUID", "order: in the default order to start")
    CHECK(RowOf("PRIEST").count.__text == "0/6" and RowOf("PALADIN").count.__text == "0/12",
        "order: each class says how many are on the board of its rated players", RowOf("PRIEST").count.__text)
    CHECK(RowOf("PALADIN").check.__checked == true, "order: every class is searched to start")
    CHECK(bar():find("first: Paladin"), "order: best first, the paladins lead", bar())
    CHECK(RowOf("PALADIN").next.__shown == true and RowOf("PRIEST").next.__shown ~= true,
        "order: the class the next press searches for is marked")

    -- A click switches a class off: none of its queries, and the next class leads
    RowOf("PALADIN").__scripts.OnClick(RowOf("PALADIN"))
    CHECK(CommanderRecruitDB.SweepOff.PALADIN == true and RowOf("PALADIN").check.__checked == false,
        "order: a click switches a class off, and the box says so")
    CHECK(bar():find("first: guild <G>") and not bar():find("Paladin"), "order: the sweep stops looking for it", bar())
    RowOf("PALADIN").check.__scripts.OnClick(RowOf("PALADIN").check)
    CHECK(not CommanderRecruitDB.SweepOff.PALADIN and bar():find("first: Paladin"), "order: its box switches it back on", bar())

    -- Dragging the rogues to the top: the order follows the drop and turns on
    local rogue = RowOf("ROGUE")
    local from = rogue.index
    GetCursorPosition = function() return 0, 0 end
    list.GetTop = function() return 300 end      -- the first row's top is at 300 - 24
    list.GetEffectiveScale = function() return 1 end
    rogue.__scripts.OnDragStart(rogue)
    GetCursorPosition = function() return 0, 300 - 24 - 2 end -- just under the first row's top: gap 1
    list.__scripts.OnUpdate(list)
    CHECK(list.marker.__shown == true, "order: a drag shows where the row would land")
    rogue.__scripts.OnDragStop(rogue)
    CHECK(from == 4 and list.rows[1].class == "ROGUE" and list.rows[2].class == "WARRIOR",
        "order: dropped at the top, the rogues come first", list.rows[1].class)
    CHECK(CommanderRecruitDB.SweepInOrder == true and list.inOrder.__checked == true,
        "order: dragging turns Search in this order on")
    CHECK(bar():find("first: guild <G>"), "order: the rogues' guild first (it holds most of them)", bar())
    CHECK(RowOf("ROGUE").next.__shown == true, "order: ...marked as the rogues'")
    -- Down one place: the priests' row dropped below the warriors'
    local priest = RowOf("PRIEST")
    priest.__scripts.OnDragStart(priest)
    GetCursorPosition = function() return 0, 300 - 24 - 2 * 22 end -- the gap under row 2
    priest.__scripts.OnDragStop(priest)
    CHECK(list.rows[3].class == "PRIEST" and list.rows[2].class == "WARRIOR",
        "order: a row can be dropped between two others", list.rows[3].class)
    -- A drop where it was moves nothing (the rows are repainted: find it again)
    local before = table.concat(CommanderRecruit.SearchOptions().order, ",")
    priest = RowOf("PRIEST")
    priest.__scripts.OnDragStart(priest)
    priest.__scripts.OnDragStop(priest)
    CHECK(table.concat(CommanderRecruit.SearchOptions().order, ",") == before, "order: dropped back in place, nothing moves")

    -- The sweep follows the order once under way
    local sent0 = #who.sent
    CommanderRecruit_SweepStep()
    CHECK(who.sent[#who.sent].text == '70-70 g-"G"', "order: the first press asks the rogues' guild", who.sent[#who.sent].text)
    ratings["Pri1-Dreamscythe"], ratings["Pal1-Dreamscythe"] = R(2100, nil, nil), R(nil, 2050, nil)
    who.results = {
        { fullName = "Pri1", level = 70, filename = "PRIEST", area = "Ironforge", fullGuildName = "G" },
        { fullName = "Pal1", level = 70, filename = "PALADIN", area = "Ironforge", fullGuildName = "" },
    }
    who.total = 2
    Fire("WHO_LIST_UPDATE")
    -- Switched off mid-sweep: the next press already knows
    RowOf("ROGUE").__scripts.OnClick(RowOf("ROGUE"))
    Advance(6)
    Repaint()
    CHECK(not bar():find("Rogue") and RowOf("ROGUE").next.__shown ~= true, "order: a class switched off mid-sweep is dropped at once", bar())
    CHECK(RowOf("PRIEST").count.__text == "1/6", "order: the counts follow the board", RowOf("PRIEST").count.__text)

    -- Hide unchecked classes: the board shows the searched ones only
    RowOf("PALADIN").__scripts.OnClick(RowOf("PALADIN"))
    Repaint()
    local names = {}
    for _, r in ipairs(Shown(Col(2))) do names[#names + 1] = r.name.__text end
    for _, r in ipairs(Shown(Col(3))) do names[#names + 1] = r.name.__text end
    local joined = table.concat(names, ",")
    CHECK(not joined:find("Pal1"), "order: a paladin switched off is hidden on the board", joined)
    CHECK(win.status.__text:find("of unchecked classes hidden"), "order: ...and the header says some are hidden", win.status.__text)
    list.hideOff.__scripts.OnClick(list.hideOff)
    CHECK(CommanderRecruitDB.SweepHideOff == false and list.hideOff.__checked == false, "order: the switch shows them again")
    list.hideOff.__scripts.OnClick(list.hideOff)
    list.inOrder.__scripts.OnClick(list.inOrder)
    CHECK(CommanderRecruitDB.SweepInOrder == false, "order: Search in this order switches off")

    -- Reset: every class, the default order, best first
    list.reset.__scripts.OnClick(list.reset)
    CHECK(list.rows[1].class == "WARRIOR" and RowOf("PALADIN").check.__checked == true
        and CommanderRecruitDB.SweepInOrder == false, "order: Reset puts it all back")

    -- Without the roster: the fixed plan, in the order, without classes off
    ladderRoster = {}
    CommanderRecruit.Clear()
    CommanderRecruit.MoveClass(9, 1)
    CommanderRecruit.ToggleClass("WARRIOR")
    Advance(6)
    Repaint()
    CHECK(bar():find("first: Druid"), "order: the fixed plan starts at the top of the list", bar())
    CommanderRecruit_SweepStep()
    CHECK(who.sent[#who.sent].text == '70-70 c-"Druid"', "order: ...and asks it", who.sent[#who.sent].text)
    Advance(9)
    Repaint()
    CHECK(not bar():find("Warrior"), "order: a class switched off is never in the fixed plan", bar())
    CHECK(RowOf("DRUID").count.__text == "0 on", "order: without the roster a row counts who is on only", RowOf("DRUID").count.__text)
    CommanderRecruit.ResetSearch()
    CommanderLadder = nil
    CommanderRecruit.Clear()
    who.results, who.total = {}, 0
    ratings["Pri1-Dreamscythe"], ratings["Pal1-Dreamscythe"] = nil, nil
    CommanderRecruit_Engine.MIN_EXPECT = stopWas
    CommanderRecruitDB.SweepDepth = depthWas
    CommanderRecruit_Engine.NAME_FRAGMENTS = fragmentsWere
end

-- ===========================================================================
-- I. Race and talent-tree icons before the name (R22)
-- ===========================================================================
do
    CommanderRecruit.Clear()
    CommanderLadder = { Roster = function()
        return {
            { key = "Stabby-Dreamscythe", name = "Stabby", faction = "A", class = "ROGUE", race = "NightElf",
                sex = "F", spec = "SUBTLETY", best = 2300, last = now },
            { key = "Healz-Dreamscythe", name = "Healz", faction = "A", class = "PRIEST", race = "Dwarf",
                sex = "M", spec = "DISCIPLINE", best = 2250, last = now },
        }
    end }
    missingAtlas["raceicon-draenei-female"] = true
    who.results = {
        -- the ladder says female; /who's gender is not trusted over it
        { fullName = "Stabby", level = 70, filename = "ROGUE", raceStr = "Night Elf", gender = 2, area = "Shattrath City", fullGuildName = "" },
        { fullName = "Walker", level = 70, filename = "WARRIOR", raceStr = "Dwarf", gender = 2, area = "Ironforge", fullGuildName = "" },
        { fullName = "Mystery", level = 70, filename = "MAGE", raceStr = "", gender = 0, area = "Ironforge", fullGuildName = "" },
        { fullName = "Shiny", level = 70, filename = "PALADIN", raceStr = "Draenei", gender = 3, area = "Exodar", fullGuildName = "" },
        { fullName = "Healz", level = 70, filename = "PRIEST", raceStr = "Dwarf", gender = 2, area = "Ironforge", fullGuildName = "" },
    }
    who.total = #who.results
    for i, name in ipairs({ "Stabby", "Walker", "Mystery", "Shiny", "Healz", "Tinker" }) do
        ratings[name .. "-Dreamscythe"] = R(2400 - i * 10)
    end
    Fire("WHO_LIST_UPDATE")
    -- Tinker only spoke in chat: race and sex come from the GUID
    Fire("CHAT_MSG_CHANNEL", "lf 2s", "Tinker", "", "2. Trade", "", "", 0, 2, "Trade", 0, 9, "Player-TINKER")
    win:Show()
    Commander.Notify(COMMANDER_RECRUIT_EVENTS.UPDATE)
    Repaint()
    local byName = {}
    for _, row in ipairs(Shown(Col(2))) do byName[row.name.__text] = row end
    local stab, walk, myst, shiny, healz, tink = byName.Stabby, byName.Walker, byName.Mystery, byName.Shiny,
        byName.Healz, byName.Tinker
    CHECK(stab and walk and myst and shiny and healz and tink, "icons: all six rated players are on the board")
    if stab and walk and myst and shiny and healz and tink then
        CHECK(stab.race.__shown and stab.race.__atlas == "raceicon-nightelf-female",
            "icons: the ladder's race and sex draw the race icon", stab.race.__atlas)
        CHECK(stab.spec.__shown and stab.spec.__texture == "Interface\\Icons\\Ability_Stealth",
            "icons: the ladder's talent tree draws the tree icon", stab.spec.__texture)
        CHECK(healz.spec.__texture == "Interface\\Icons\\Spell_Holy_WordFortitude", "icons: a discipline priest's tree")
        CHECK(walk.race.__shown and walk.race.__atlas == "raceicon-dwarf-male" and not walk.spec.__shown,
            "icons: off the roster, /who's race and gender draw the race; no tree is known", walk.race.__atlas)
        CHECK(tink.race.__shown and tink.race.__atlas == "raceicon-gnome-female",
            "icons: a chat line's GUID gives race and sex", tink.race.__atlas)
        CHECK(not myst.race.__shown and not myst.spec.__shown, "icons: nothing known, both left empty")
        CHECK(not shiny.race.__shown, "icons: an atlas the client lacks is not drawn")
        local np = myst.name.__points or {}
        CHECK(np[1] and np[1].rel == myst.spec and myst.spec.__points[1].rel == myst.race
            and myst.race.__points[1].rel == myst.rank,
            "icons: rank, race, tree, name, so the names stay in one column with or without icons")
        GameTooltip.__lines = {}
        stab.__scripts.OnEnter(stab)
        local tipText = table.concat(GameTooltip.__lines, " | ")
        CHECK(tipText:find("Night Elf · Subtlety %(talents, from the ladder feed%)"),
            "icons: the tooltip names the race and the tree", tipText)
    end
    -- Without the ladder the race still comes from the game, the tree does not
    CommanderLadder = nil
    Commander.Notify(COMMANDER_RECRUIT_EVENTS.UPDATE)
    Repaint()
    byName = {}
    for _, row in ipairs(Shown(Col(2))) do byName[row.name.__text] = row end
    CHECK(byName.Stabby and byName.Stabby.race.__atlas == "raceicon-nightelf-male" and not byName.Stabby.spec.__shown,
        "icons: no ladder: /who's race and gender, no tree", byName.Stabby and byName.Stabby.race.__atlas)
    for _, name in ipairs({ "Stabby", "Walker", "Mystery", "Shiny", "Healz", "Tinker" }) do
        ratings[name .. "-Dreamscythe"] = nil
    end
    who.results, who.total = {}, 0
    CommanderRecruit.Clear()
end

-- ===========================================================================
-- K. Under 70 is never asked about, so the feed is not handed their names (R24)
-- ===========================================================================
do
    CommanderRecruit.Clear()
    win:Show()
    who.results = {
        { fullName = "Lowbie", level = 42, filename = "MAGE", raceStr = "Gnome", gender = 2, area = "Ironforge", fullGuildName = "" },
        { fullName = "Capped", level = 70, filename = "MAGE", raceStr = "Gnome", gender = 2, area = "Ironforge", fullGuildName = "" },
    }
    who.total = 2
    local before = #asked
    Fire("WHO_LIST_UPDATE")
    Repaint()
    local askedNow = {}
    for i = before + 1, #asked do askedNow[asked[i]] = true end
    CHECK(not askedNow["Lowbie"] and askedNow["Capped"], "level: a level 42 is not asked for a rating, a level 70 is")
    CHECK(win.foot.__text:find("^2 online with no rating known yet: /reload hands them to the Ladder feed"),
        "level: the footer counts the 70 only and says how the names reach the feed", win.foot.__text)
    who.results, who.total = {}, 0
    CommanderRecruit.Clear()
end

-- ===========================================================================
-- Z. Sweep Depth reaches the sweep (R26)
-- ===========================================================================
do
    CommanderRecruit.Clear()
    local deep = {}
    for i = 1, 8 do
        deep[i] = { key = "Deep" .. i .. "-Dreamscythe", name = "Deep" .. i, faction = "A", class = "MAGE", race = "Gnome",
            best = 1900, last = now }
    end
    CommanderLadder = { Roster = function() return deep end }
    CommanderRecruitDB.SweepDepth = 0.5
    Advance(10)
    CommanderRecruit_SweepStep()
    CHECK(CommanderRecruit.Sweep() and CommanderRecruit.Sweep().minExpect == 0.5, "depth: a new sweep takes Sweep Depth",
        CommanderRecruit.Sweep() and CommanderRecruit.Sweep().minExpect)
    CommanderRecruitDB.SweepDepth = 1
    Commander.Notify(COMMANDER_RECRUIT_EVENTS.UPDATE)
    CHECK(CommanderRecruit.Sweep().minExpect == 1, "depth: a change reaches the sweep under way")
    CommanderRecruitDB.SweepDepth = 2
    Advance(10)
    CommanderLadder = nil
    CommanderRecruit.Clear()
end

-- ===========================================================================
-- Y. You are always on your own board (R25)
-- ===========================================================================
do
    local before = #asked
    ratings["player"] = R(1834, 1700, 1896)
    CommanderRecruit.Clear()
    win:Show()
    Repaint()
    local me = CommanderRecruit.Book().players["Devinp-Dreamscythe"]
    CHECK(me and me.self and me.source == "self" and me.class == "PRIEST" and me.level == 70,
        "self: you are in the book with no sighting at all, as yourself")
    local askedSelf = false
    for i = before + 1, #asked do if asked[i] == "player" then askedSelf = true end end
    CHECK(askedSelf, "self: your ratings are asked for by unit, so Muster answers with your live ones")
    local mine
    for _, row in ipairs(Shown(Col(2))) do if row.name.__text == "Devinp" then mine = row end end
    CHECK(mine and mine.rating.__text == 1834, "self: your row is on the 2v2 board with your rating", mine and mine.rating.__text)
    Advance(16 * 60)
    Repaint()
    mine = nil
    for _, row in ipairs(Shown(Col(5))) do if row.name.__text == "Devinp" then mine = row end end
    CHECK(mine ~= nil, "self: and stays there past the freshness window")
    if mine then
        GameTooltip.__lines = {}
        mine.__scripts.OnEnter(mine)
        CHECK(table.concat(GameTooltip.__lines, " | "):find("via you %(always listed%)"), "self: the tooltip says why",
            table.concat(GameTooltip.__lines, " | "))
    end
    ratings["player"] = nil
    CommanderRecruit.Clear()
end

CHECK(#harnessFailedErrors == 0, "no errors were swallowed anywhere", harnessFailedErrors[1])
io.write(string.format("%d checks, %d failed\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
