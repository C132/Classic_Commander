-- Commander Momentum logic harness (luajit).
-- Loads the REAL shared framework (CommanderSettingsUI.lua, CommanderEvents.lua)
-- plus both Commander_Momentum files under a permissive WoW mock, then drives
-- login, kill chains, window expiry, death, zone transitions, the tester, and
-- slash commands. Focus: the per-zone record books — live writes, baseline
-- captures, end-of-chain recaps, lament stats, and reset survival.

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
-- WoW mock (same skeleton as Commander_Meters/Harness)
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

-- Find a printed line containing the pattern (plain find), searching only
-- lines printed AFTER index `since` (a #printLog mark); returns line or nil
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

local VALID_FLAGS = { [""] = true, OUTLINE = true, THICKOUTLINE = true, MONOCHROME = true,
    ["OUTLINE, MONOCHROME"] = true }

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
        local fn = function(s) local t = NewWidget("FontString"); t.__parent = s; return t end
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
            assert(type(path) == "string" and type(size) == "number", "SetFont bad args")
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
        local fn = function() return NewWidget("Texture") end
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
    return setmetatable({
        __kind = kind, __name = name, __scripts = {}, __shown = true,
    }, WidgetMT)
end

function CreateFrame(frameType, name, parent, template)
    local f = NewWidget(frameType, name)
    f.__template = template
    if frameType == "CheckButton" or (template and template:find("CheckButton")) then
        f.Text = NewWidget("FontString")
    end
    if name then _G[name] = f end
    frames[#frames + 1] = f
    return f
end

UIParent = NewWidget("Frame", "UIParent")
GameTooltip = NewWidget("GameTooltip", "GameTooltip")
PlayerFrame = NewWidget("Frame", "PlayerFrame")
PlayerPortrait = NewWidget("Texture", "PlayerPortrait")
tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack

GameFontNormal = NewWidget("Font")
GameFontNormalLarge = NewWidget("Font")
GameFontNormalHuge = NewWidget("Font")
GameFontHighlight = NewWidget("Font")
GameFontHighlightSmall = NewWidget("Font")
GameFontDisableSmall = NewWidget("Font")

SOUNDKIT = { READY_CHECK = 8960, IG_MAINMENU_OPTION_CHECKBOX_ON = 856,
    IG_MAINMENU_OPTION_CHECKBOX_OFF = 857 }
function PlaySound() end
BACKDROP_SLIDER_8_8 = {}

local categories = {}
Settings = {
    RegisterCanvasLayoutCategory = function(panel, title)
        local cat = { __panel = panel, GetID = function() return #categories + 1 end }
        categories[#categories + 1] = cat
        return cat
    end,
    RegisterCanvasLayoutSubcategory = function(parent, panel, title)
        local cat = { __panel = panel, GetID = function() return #categories + 1 end }
        categories[#categories + 1] = cat
        return cat
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
}
C_AddOns = { GetAddOnMetadata = function() return "2.2.0" end }

local tickers = {}
C_Timer = {
    After = function() end,
    NewTicker = function(interval, fn)
        tickers[#tickers + 1] = { interval = interval, fn = fn }
    end,
}
local function RunTickers()
    for _, t in ipairs(tickers) do t.fn() end
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

local playerGuid = "Player-0-ME"
function UnitGUID(unit) if unit == "player" then return playerGuid end return nil end
function UnitName(unit) if unit == "player" then return "Devinp" end return nil end
function UnitClass(unit) if unit == "player" then return "Warrior", "WARRIOR" end return nil end
RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
CLASS_ICON_TCOORDS = { WARRIOR = { 0, 0.25, 0, 0.25 } }
SlashCmdList = {}

local sentChat = {}
function SendChatMessage(msg, channel)
    sentChat[#sentChat + 1] = { msg = msg, channel = channel }
end
local emotes = {}
function DoEmote(token) emotes[#emotes + 1] = token end

-- Zone state the harness scripts against
local zone = { itype = "none", mapId = 0, name = "Azeroth", realZone = "Westfall" }
function GetInstanceInfo()
    return zone.name, zone.itype, 0, "", 5, 0, false, zone.mapId, 5
end
function GetRealZoneText() return zone.realZone end

COMBATLOG_OBJECT_REACTION_HOSTILE = 0x00000040
COMBATLOG_OBJECT_CONTROL_NPC = 0x00000200
COMBATLOG_OBJECT_TYPE_PET = 0x00001000
COMBATLOG_OBJECT_TYPE_GUARDIAN = 0x00002000
bit = bit or require("bit")

local pendingCLEU
function CombatLogGetCurrentEventInfo() return unpack(pendingCLEU, 1, 12) end

-- ===========================================================================
-- Load the real framework + addon
-- ===========================================================================

local function Load(path)
    local chunk = assert(loadfile(path))
    chunk()
end

CommanderConsole_Colors = {
    { text = "Steel (Default)", value = "STEEL", r = 1, g = 1, b = 1 },
    { text = "Class Color", value = "CLASS" },
}
CommanderMomentumDB = {}

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
Load(ADDONS .. "/Commander_Momentum/CommanderMomentumDB.lua")
Load(ADDONS .. "/Commander_Momentum/CommanderMomentum.lua")

local function Fire(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    -- Snapshot: handlers may unregister themselves mid-fire
    local snapshot = {}
    for i, frame in ipairs(list) do snapshot[i] = frame end
    for _, frame in ipairs(snapshot) do
        local handler = frame.__scripts.OnEvent
        if handler then handler(frame, event, ...) end
    end
end

local function Kill()
    pendingCLEU = { now, "PARTY_KILL", false, playerGuid, "Devinp", 0, 0,
        "Creature-0-1", "Boar", 0x00000240, 0, 0 }
    Fire("COMBAT_LOG_EVENT_UNFILTERED")
end

local function Chain(n, gap)
    for _ = 1, n do
        Kill()
        now = now + (gap or 2)
    end
end

local function Expire()
    now = now + (CommanderMomentumDB.Window or 20) + 1
    RunTickers()
end

local Records = function() return CommanderMomentumDB.Records or {} end

-- ===========================================================================
-- A: login
-- ===========================================================================

Fire("ADDON_LOADED", "Commander_Momentum")
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD")

CHECK(#harnessFailedErrors == 0, "A: login clean", harnessFailedErrors[1])
CHECK(CommanderMomentumDB.EnableMomentum == true, "A: defaults applied")
CHECK(CommanderMomentumDB.Session ~= nil, "A: session block created")
CHECK(next(Records()) == nil, "A: no records yet")

-- ===========================================================================
-- B: first chain x8 in Westfall — records open
-- ===========================================================================

local mark = #printLog
Chain(8)
CHECK(CommanderMomentum_GetStreakInfo() == 8, "B: live streak x8")
CHECK(Records().Westfall and Records().Westfall.best == 8, "B: Westfall record written live",
    Records().Westfall and Records().Westfall.best)
CHECK(CommanderMomentumDB.Session.chainZone == "Westfall", "B: session mirrors chain zone")
CHECK(CommanderMomentumDB.Session.chainBasesCaptured == true, "B: session mirrors baselines")
Expire()
CHECK(CommanderMomentum_GetStreakInfo() == 0, "B: streak ended on the clock")
local line = FindPrint("chain ends", mark)
CHECK(line and line:find("session best x8", 1, true)
    and line:find("record books open in Westfall", 1, true),
    "B: first-record recap", line)

-- ===========================================================================
-- C: small chain x3 — no recap noise
-- ===========================================================================

mark = #printLog
Chain(3)
Expire()
CHECK(not FindPrint("chain ends", mark), "C: x3 end is silent", FindPrint("chain ends", mark))
CHECK(Records().Westfall.best == 8, "C: record untouched by lesser chain")

-- ===========================================================================
-- D: x12 — new all-time high in the same zone
-- ===========================================================================

mark = #printLog
Chain(12)
Expire()
line = FindPrint("chain ends", mark)
CHECK(line and line:find("session best x12", 1, true)
    and line:find("NEW ALL-TIME HIGH in Westfall!", 1, true)
    and line:find("previous x8 — set right here", 1, true),
    "D: same-zone all-time recap", line)
CHECK(Records().Westfall.best == 12, "D: Westfall record now x12")

-- ===========================================================================
-- E: open-world border crossing mid-chain — record lands in the new zone
-- ===========================================================================

mark = #printLog
Chain(3)
zone.realZone = "Duskwood"   -- walked across the border, no loading screen
Chain(4)
Expire()
CHECK(Records().Duskwood and Records().Duskwood.best == 7, "E: Duskwood record from crossing chain",
    Records().Duskwood and Records().Duskwood.best)
CHECK(Records().Westfall.best == 12, "E: Westfall record untouched")
line = FindPrint("chain ends", mark)
CHECK(line and line:find("x7 chain ends", 1, true)
    and line:find("first record for Duskwood", 1, true)
    and line:find("all-time high x12 (Westfall)", 1, true)
    and not line:find("session best", 1, true),
    "E: non-session-best record break still reports", line)

-- ===========================================================================
-- F: lament carries the all-time high (chain below the session best)
-- ===========================================================================

zone.realZone = "Westfall"
CommanderMomentumDB.BreakEmotes = true
mark = #printLog
local chatMark = #sentChat
Chain(11)
Expire()
CHECK(#sentChat == chatMark + 1, "F: lament sent")
local lament = sentChat[#sentChat]
CHECK(lament and lament.channel == "EMOTE"
    and lament.msg:find("x11", 1, true)
    and lament.msg:find("best chain x12", 1, true)
    and lament.msg:find("all-time high x12", 1, true)
    and not lament.msg:find("NEW all-time", 1, true),
    "F: lament stats include standing all-time", lament and lament.msg)
CHECK(not FindPrint("chain ends", mark), "F: no recap for an also-ran chain")

-- ===========================================================================
-- G: x16 — new all-time, lament brags, /cry fires
-- ===========================================================================

mark = #printLog
chatMark = #sentChat
local emoteMark = #emotes
Chain(16)
Expire()
line = FindPrint("chain ends", mark)
CHECK(line and line:find("NEW ALL-TIME HIGH in Westfall!", 1, true)
    and line:find("previous x12", 1, true), "G: all-time recap", line)
lament = sentChat[#sentChat]
CHECK(#sentChat == chatMark + 1 and lament.msg:find("a NEW all-time high x16", 1, true),
    "G: lament brags the new all-time", lament and lament.msg)
CHECK(emotes[#emotes] == "CRY" and #emotes == emoteMark + 1, "G: x16 earns the sob")
CommanderMomentumDB.BreakEmotes = false

-- ===========================================================================
-- H: death ends the session-best chain with the standing recap
-- ===========================================================================

Fire("PLAYER_DEAD")  -- no live chain: just zeroes the session numbers
zone.realZone = "Duskwood"
mark = #printLog
Chain(6)
Fire("PLAYER_DEAD")
line = FindPrint("chain ends", mark)
CHECK(line and line:find("session best x6", 1, true)
    and line:find("Duskwood record x7", 1, true)
    and line:find("all-time high x16 (Westfall)", 1, true),
    "H: death recap shows zone record and all-time", line)
CommanderMomentum_Report()
line = printLog[#printLog]
CHECK(line:find("0 kills this session, best chain x0", 1, true),
    "H: death zeroed the session stats", line)

-- ===========================================================================
-- I: zone transition quietly ends the chain — recap names the OLD zone
-- ===========================================================================

mark = #printLog
Chain(8)  -- Duskwood: x8 beats the x7 record
CHECK(Records().Duskwood.best == 8, "I: Duskwood record raised live")
zone.itype, zone.mapId, zone.name = "party", 36, "The Deadmines"
Fire("PLAYER_ENTERING_WORLD")
line = FindPrint("chain ends", mark)
CHECK(line and line:find("session best x8", 1, true)
    and line:find("new record for Duskwood (was x7)", 1, true)
    and line:find("all-time high x16 (Westfall)", 1, true),
    "I: zone-change recap credits the old zone", line)
CHECK(CommanderMomentum_GetStreakInfo() == 0, "I: chain gone after the loading screen")

-- ===========================================================================
-- J: instance chains score under the instance name
-- ===========================================================================

mark = #printLog
Chain(9)
Expire()
CHECK(Records()["The Deadmines"] and Records()["The Deadmines"].best == 9,
    "J: instance record keyed by instance name")
line = FindPrint("chain ends", mark)
CHECK(line and line:find("first record for The Deadmines", 1, true), "J: instance recap", line)

-- ===========================================================================
-- K: the tester never touches the books
-- ===========================================================================

zone.itype, zone.mapId, zone.name = "none", 0, "Azeroth"
zone.realZone = "Stranglethorn Vale"
Fire("PLAYER_ENTERING_WORLD")
mark = #printLog
chatMark = #sentChat
CommanderMomentum_Test()
CHECK(CommanderMomentum_GetStreakInfo() == 2, "K: test chain live")
Expire()
CHECK(Records()["Stranglethorn Vale"] == nil, "K: test kills wrote no record")
CHECK(not FindPrint("chain ends", mark), "K: test chain ends without a recap")
CHECK(#sentChat == chatMark, "K: test chain sends no public chat")

-- ===========================================================================
-- L: reports and the record books listing
-- ===========================================================================

CommanderMomentum_Report()
line = printLog[#printLog]
CHECK(line:find("no record for Stranglethorn Vale yet", 1, true)
    and line:find("all-time high x16 (Westfall)", 1, true),
    "L: report shows the standing from a virgin zone", line)

mark = #printLog
SlashCmdList.COMMANDERUI_MOMENTUM("records")
CHECK(FindPrint("zone records (3 zones)", mark), "L: records header", printLog[mark + 1])
local first = printLog[mark + 2]
CHECK(first and first:find("x16 — Westfall", 1, true) and first:find("all-time high", 1, true),
    "L: top record tagged as the all-time high", first)
local second, third = printLog[mark + 3], printLog[mark + 4]
CHECK(second and second:find("x9 — The Deadmines", 1, true)
    and not second:find("all-time high", 1, true), "L: sorted second, untagged", second)
CHECK(third and third:find("x8 — Duskwood", 1, true), "L: sorted third", third)
CHECK(printLog[mark + 5] == nil, "L: exactly three rows", printLog[mark + 5])

-- ===========================================================================
-- M: settings reset leaves the record books alone
-- ===========================================================================

CommanderMomentumDB.Window = 45
SlashCmdList.COMMANDERUI_MOMENTUM("reset")
CHECK(CommanderMomentumDB.Window == 20, "M: settings reset to defaults")
CHECK(Records().Westfall and Records().Westfall.best == 16, "M: records survive the reset")

-- ===========================================================================

CHECK(#harnessFailedErrors == 0, "Z: no swallowed errors", harnessFailedErrors[1])

-- DUMP=1 luajit momentum_harness.lua — eyeball every line the addon printed
-- or sent to chat, in order, with the color codes stripped
if os.getenv("DUMP") then
    io.write("--- prints ---\n")
    for _, l in ipairs(printLog) do
        io.write((l:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")), "\n")
    end
    io.write("--- chat ---\n")
    for _, c in ipairs(sentChat) do
        io.write(c.channel, ": ", c.msg, "\n")
    end
    io.write("--- emotes: ", table.concat(emotes, ", "), "\n")
end

if fails == 0 then
    io.write(string.format("MOMENTUM: all %d checks passed\n", checks))
else
    io.write(string.format("MOMENTUM: %d/%d checks FAILED\n", fails, checks))
    os.exit(1)
end
