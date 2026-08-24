-- Commander Debug harness (luajit):
--     luajit debug_harness.lua
--
-- Covers the two capture paths (BugGrabber adapter and the built-in hook),
-- scope/filter/cap selection, addon attribution, and the markdown report
-- itself — header contents, per-error blocks, trimming, sanitising and the
-- page split. Mock modeled on Commander_Chat/Harness.
--
-- DUMP=1 prints the last built report in full.

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

local NOW = 1700000000
function time() return NOW end
date = os.date

local printLog = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    printLog[#printLog + 1] = table.concat(parts, " ")
end

local caughtErrors = {}
local errorHandler = function(err) caughtErrors[#caughtErrors + 1] = tostring(err) end
function geterrorhandler() return errorHandler end
function seterrorhandler(fn) errorHandler = fn end
function debugstack() return "mock stack line 1\nmock stack line 2\n" end

local NUMERIC_GETTERS = {
    GetScale = 1, GetEffectiveScale = 1, GetFrameLevel = 2,
    GetLeft = 0, GetBottom = 0, GetTop = 0, GetRight = 0,
    GetStringWidth = 10, GetNumPoints = 1, GetVerticalScroll = 0,
    GetVerticalScrollRange = 0,
}

local function IsMethodName(key)
    return type(key) == "string" and (key:match("^Set") or key:match("^Get") or key:match("^Is")
        or key:match("^Can") or key:match("^Enable") or key:match("^Disable")
        or key:match("^Register") or key:match("^Unregister") or key:match("^Hook")
        or key:match("^Clear") or key:match("^Create") or key:match("^Show")
        or key:match("^Hide") or key:match("^Raise") or key:match("^Start")
        or key:match("^Stop") or key:match("^Add") or key:match("^Lock"))
end

local eventRegistry = {}
local NewWidget

local WidgetMT = {}
WidgetMT.__index = function(self, key)
    if type(key) ~= "string" then return nil end
    if NUMERIC_GETTERS[key] ~= nil then
        local v = NUMERIC_GETTERS[key]
        local fn = function() return v end
        rawset(self, key, fn); return fn
    end
    local simple = {
        SetPoint = function() end,
        ClearAllPoints = function() end,
        SetSize = function(s, w, h) s.__w, s.__h = w, h end,
        GetWidth = function(s) return s.__w or 680 end,
        GetHeight = function(s) return s.__h or 520 end,
        SetText = function(s, text) s.__text = text end,
        GetText = function(s) return s.__text end,
        Show = function(s) s.__shown = true end,
        Hide = function(s) s.__shown = false end,
        SetShown = function(s, shown) s.__shown = not not shown end,
        IsShown = function(s) return s.__shown end,
        IsVisible = function(s) return s.__shown end,
        SetScript = function(s, name, handler) s.__scripts[name] = handler end,
        HookScript = function(s, name, handler) s.__scripts[name] = handler end,
        GetScript = function(s, name) return s.__scripts[name] end,
        RegisterEvent = function(s, event)
            eventRegistry[event] = eventRegistry[event] or {}
            table.insert(eventRegistry[event], s)
        end,
        UnregisterEvent = function(s, event)
            local list = eventRegistry[event]
            if list then
                for i = #list, 1, -1 do
                    if list[i] == s then table.remove(list, i) end
                end
            end
        end,
        CreateTexture = function(s) local t = NewWidget("Texture"); t.__parent = s; return t end,
        CreateFontString = function(s) local t = NewWidget("FontString"); t.__parent = s; return t end,
        SetScrollChild = function(s, child) s.__child = child end,
        SetParent = function(s, parent) s.__parent = parent end,
        GetParent = function(s) return s.__parent end,
        SetFocus = function(s) s.__focused = true end,
        HighlightText = function(s) s.__highlighted = (s.__highlighted or 0) + 1 end,
        SetCursorPosition = function(s, pos) s.__cursor = pos end,
    }
    local fn = simple[key]
    if fn then rawset(self, key, fn); return fn end
    if IsMethodName(key) then
        local blank = function() end
        rawset(self, key, blank); return blank
    end
    return nil
end

NewWidget = function(kind, name)
    return setmetatable({ __kind = kind, __name = name, __scripts = {}, __shown = true }, WidgetMT)
end

function CreateFrame(frameType, name, parent, template)
    local f = NewWidget(frameType, name)
    f.__template = template
    f.__parent = parent
    if frameType == "CheckButton" or (template and template:find("CheckButton")) then
        f.Text = NewWidget("FontString")
    end
    if name then _G[name] = f end
    return f
end

UIParent = NewWidget("Frame", "UIParent")
UISpecialFrames = {}
StaticPopupDialogs = {}
function StaticPopup_Show(which)
    local dialog = StaticPopupDialogs[which]
    if dialog and dialog.OnAccept then dialog.OnAccept() end
end
ACCEPT, CANCEL = "Accept", "Cancel"
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
unpack = unpack or table.unpack

for _, f in ipairs({ "GameFontNormal", "GameFontNormalLarge", "GameFontNormalSmall",
    "GameFontHighlight", "GameFontHighlightSmall", "GameFontDisable", "GameFontDisableSmall" }) do
    _G[f] = NewWidget("Font")
end

SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2 }
function PlaySound() end
BACKDROP_SLIDER_8_8 = {}

local categories = {}
Settings = {
    RegisterCanvasLayoutCategory = function(panel)
        local cat = { __panel = panel, GetID = function() return #categories + 1 end }
        categories[#categories + 1] = cat; return cat
    end,
    RegisterCanvasLayoutSubcategory = function(parent, panel)
        local cat = { __panel = panel, GetID = function() return #categories + 1 end }
        categories[#categories + 1] = cat; return cat
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
}

local ADDON_LIST = {
    { name = "Commander_Events", version = "2.1.0", loaded = true },
    { name = "Commander_Debug", version = "1.0.0", loaded = true },
    { name = "BugSack", version = "v12.0.20", loaded = true },
    { name = "NotLoadedAddon", version = "9.9", loaded = false },
}
C_AddOns = {
    GetAddOnMetadata = function(id, field)
        if field ~= "Version" then return nil end
        if type(id) == "number" then return ADDON_LIST[id] and ADDON_LIST[id].version end
        for _, a in ipairs(ADDON_LIST) do
            if a.name == id then return a.version end
        end
        return "1.0.0"
    end,
    GetNumAddOns = function() return #ADDON_LIST end,
    GetAddOnInfo = function(id) return ADDON_LIST[id] and ADDON_LIST[id].name end,
    IsAddOnLoaded = function(id)
        if type(id) == "number" then return ADDON_LIST[id] and ADDON_LIST[id].loaded end
        for _, a in ipairs(ADDON_LIST) do
            if a.name == id then return a.loaded end
        end
        return false
    end,
}

C_Timer = {
    After = function() end,
    NewTicker = function() return { Cancel = function(s) s.cancelled = true end } end,
}

function UIDropDownMenu_Initialize() end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton() end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetSelectedValue() end
function UIDropDownMenu_SetText() end
function UIDropDownMenu_EnableDropDown() end
function UIDropDownMenu_DisableDropDown() end
SlashCmdList = {}
GameTooltip = NewWidget("GameTooltip", "GameTooltip")

function GetBuildInfo() return "2.5.5", "68101", "Jul 22 2026", 20506 end
function GetLocale() return "enUS" end
function GetRealmName() return "Doomhowl" end
function UnitName() return "Bootyshaker" end
function UnitClass() return "Mage", "MAGE" end
function UnitLevel() return 70 end
RAID_CLASS_COLORS = { MAGE = { r = 0.4, g = 0.8, b = 0.9 } }
CLASS_ICON_TCOORDS = {}

local registryCallbacks = {}
EventRegistry = {
    RegisterCallback = function(_, event, fn, owner)
        registryCallbacks[event] = registryCallbacks[event] or {}
        table.insert(registryCallbacks[event], { fn = fn, owner = owner })
    end,
    TriggerEvent = function(_, event, ...)
        for _, entry in ipairs(registryCallbacks[event] or {}) do
            entry.fn(entry.owner, ...)
        end
    end,
}

-- ===========================================================================
-- Load the real framework + addon
-- ===========================================================================

local function Load(path) assert(loadfile(path))() end

local function Fire(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    local snap = {}
    for i, f in ipairs(list) do snap[i] = f end
    for _, frame in ipairs(snap) do
        local handler = frame.__scripts.OnEvent
        if handler then
            local ok, err = pcall(handler, frame, event, ...)
            if not ok then caughtErrors[#caughtErrors + 1] = event .. ": " .. tostring(err) end
        end
    end
end

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")

_G.CommanderDebugDB = {}
Load(ADDONS .. "/Commander_Debug/CommanderDebugDB.lua")
Fire("ADDON_LOADED", "Commander_Debug")
Load(ADDONS .. "/Commander_Debug/CommanderDebugCapture.lua")
Load(ADDONS .. "/Commander_Debug/CommanderDebug.lua")
Fire("PLAYER_LOGIN")

local DB = _G.CommanderDebugDB
local Capture = CommanderDebug.Capture
local Report = CommanderDebug.Report

-- ===========================================================================
-- Settings + panel wiring
-- ===========================================================================

CHECK(DB.Scope == "SESSION", "defaults applied", DB.Scope)
CHECK(DB.IncludeStacks == true and DB.IncludeLocals == false,
    "stacks default on, locals default off")
CHECK(SlashCmdList.COMMANDERUI_DEBUG ~= nil, "slash command registered")
CHECK(CommanderDebug.CategoryID ~= nil, "settings category recorded for the window button")

-- ===========================================================================
-- Attribution
-- ===========================================================================

local From = Capture.AddonFromText
CHECK(From([[Interface\AddOns\Commander_Spoils\CommanderSpoils.lua:1421: bad]]) == "Commander_Spoils",
    "attribution from a backslash path")
CHECK(From("Interface/AddOns/Commander_Buffs/CommanderBuffs.lua:12: bad") == "Commander_Buffs",
    "attribution from a forward-slash path")
CHECK(From([[...ce\AddOns\Commander_Meters\CommanderMeters.lua:88: bad]]) == "Commander_Meters",
    "attribution from a truncated path")
CHECK(From("[ADDON_ACTION_BLOCKED] AddOn 'Auctionator' tried to call the protected function 'x'.")
    == "Auctionator", "attribution from a blocked-action line")
CHECK(From("some error with no path at all") == nil, "no attribution when there is no path")

-- ===========================================================================
-- Native capture (no BugGrabber)
-- ===========================================================================

CHECK(Capture.Source() == "NATIVE", "native source when BugGrabber is absent", Capture.Source())
CHECK(Capture.SessionId() == 1, "native session id is 1")

-- PLAYER_LOGIN installed our handler; raising through it must record and chain
local chained = 0
local previousCount = #caughtErrors
Capture.StoreNative([[Interface\AddOns\Commander_Reticle\CommanderReticle.lua:10: first]],
    "stack A\nstack B")
Capture.StoreNative([[Interface\AddOns\Commander_Reticle\CommanderReticle.lua:10: first]])
Capture.StoreNative("plain error with no addon")

local native, nativeStats = Capture.GetErrors({ scope = "SESSION" })
CHECK(#native == 2, "repeat messages dedupe into one record", #native)
local repeated
for _, record in ipairs(native) do
    if record.message:match("first") then repeated = record end
end
CHECK(repeated and repeated.counter == 2, "repeat bumps the occurrence counter",
    repeated and repeated.counter)
CHECK(repeated and repeated.addon == "Commander_Reticle", "native record carries attribution")
CHECK(nativeStats.occurrences == 3, "occurrences count every firing", nativeStats.occurrences)
CHECK(nativeStats.unique == 2, "unique counts distinct messages", nativeStats.unique)

-- The live error handler path: raise through geterrorhandler as the client would
geterrorhandler()([[Interface\AddOns\Commander_Idle\CommanderIdle.lua:3: through the hook]])
local viaHook = select(1, Capture.GetErrors({ scope = "SESSION" }))
local found = false
for _, record in ipairs(viaHook) do
    if record.message:match("through the hook") then found = true end
end
CHECK(found, "the installed handler records what the client raises")
CHECK(#caughtErrors > previousCount, "the installed handler still chains to the previous one")
-- That raise was deliberate; drop it so the run's error list stays meaningful
for i = #caughtErrors, previousCount + 1, -1 do table.remove(caughtErrors, i) end

-- Commander-only filter
Capture.StoreNative([[Interface\AddOns\Auctionator\Something.lua:9: not mine]])
local onlyMine = Capture.GetErrors({ scope = "SESSION", onlyCommander = true })
for _, record in ipairs(onlyMine) do
    CHECK(record.addon and record.addon:match("^Commander"),
        "Commander-only filter drops foreign addons", record.addon)
end
local unfiltered, unfilteredStats = Capture.GetErrors({ scope = "SESSION" })
CHECK(#unfiltered > #onlyMine, "the filter actually removes something")
CHECK(select(2, Capture.GetErrors({ scope = "SESSION", onlyCommander = true })).hidden > 0,
    "filtered-out errors are counted as hidden")

-- Cap
local capped, cappedStats = Capture.GetErrors({ scope = "SESSION", max = 2 })
CHECK(#capped == 2, "max caps the record count", #capped)
CHECK(cappedStats.hidden >= unfilteredStats.total - 2, "capped-off errors count as hidden",
    cappedStats.hidden)

Capture.Clear()
CHECK(#Capture.GetErrors({ scope = "ALL" }) == 0, "clear empties the native store")

-- ===========================================================================
-- BugGrabber adapter
-- ===========================================================================

local grabberDB = {
    { message = [[Interface\AddOns\Commander_Buffs\CommanderBuffs.lua:100: old news]],
      stack = "old stack", counter = 3, time = NOW - 90000, session = 4 },
    { message = [[Interface\AddOns\Commander_Spoils\CommanderSpoils.lua:1421: attempt to index field 'roll' (a nil value)]],
      stack = "stack top\nstack mid\nstack tail", locals = "local a = 1\nlocal b = nil",
      counter = 4, time = NOW - 600, session = 7 },
    { message = [[Interface\AddOns\Auctionator\Core.lua:5: foreign trouble]],
      stack = "foreign stack", counter = 1, time = NOW - 60, session = 7 },
    { message = { "corrupt table message" }, counter = 1, time = NOW, session = 7 },
}

_G.BugGrabber = {
    GetDB = function() return grabberDB end,
    GetSessionId = function() return 7 end,
    Reset = function() grabberDB = {} end,
    GetErrorByID = function(_, id) return grabberDB[tonumber(id)] end,
}

CHECK(Capture.Source() == "BUGGRABBER", "BugGrabber wins once it is present")
CHECK(Capture.SourceLabel():match("BugSack"), "source label names BugSack when it is loaded",
    Capture.SourceLabel())

local session, sessionStats = Capture.GetErrors({ scope = "SESSION" })
CHECK(#session == 2, "session scope keeps only the current session", #session)
CHECK(sessionStats.hidden == 1, "the older session counts as hidden", sessionStats.hidden)
CHECK(sessionStats.total == 3, "the corrupt table entry is skipped entirely", sessionStats.total)
CHECK(session[1].message:match("foreign trouble"), "records come back newest first",
    session[1].message)

local all = Capture.GetErrors({ scope = "ALL" })
CHECK(#all == 3, "ALL scope reaches back through every session", #all)
CHECK(all[#all].message:match("old news"), "oldest lands last under ALL scope")

local mine = Capture.GetErrors({ scope = "ALL", onlyCommander = true })
CHECK(#mine == 2, "Commander-only filter works against BugGrabber too", #mine)

-- ===========================================================================
-- Report
-- ===========================================================================

local function Options(overrides)
    local opts = CommanderDebug.Options()
    for key, value in pairs(overrides or {}) do opts[key] = value end
    return opts
end

local ctx = CommanderDebug.Context()
CHECK(ctx.toc == 20506, "context carries the interface version", ctx.toc)
CHECK(ctx.player == "Bootyshaker" and ctx.realm == "Doomhowl", "context carries the character")

local commanderAddons, otherAddons = CommanderDebug.LoadedAddons()
CHECK(#commanderAddons == 2, "loaded-addon list splits the suite out", #commanderAddons)
CHECK(otherAddons[1] == "BugSack v12.0.20", "other addons carry versions", otherAddons[1])
for _, entry in ipairs(otherAddons) do
    CHECK(entry ~= "NotLoadedAddon 9.9", "unloaded addons stay out of the list")
end

local pages = CommanderDebug.BuildPages()
CHECK(#pages == 1, "a small report fits on one page", #pages)
local page = pages[1]
CHECK(page:match("^# Fix these World of Warcraft addon Lua errors"), "report opens with the brief")
CHECK(page:match("%*%*Source:%*%* BugGrabber"), "header names the capture source")
CHECK(page:match("this session only"), "header spells out the scope")
CHECK(page:match("2 unique, 5 total occurrences"), "header counts unique and total")
CHECK(page:match("2%.5%.5") and page:match("interface 20506"), "header carries the client build")
CHECK(page:match("Commander_Events v2%.1%.0"), "header lists the loaded suite")
CHECK(page:match("Commander_Spoils/CommanderSpoils%.lua:1421"), "block heading names file and line")
CHECK(page:match("4 occurrences"), "block heading carries the occurrence count")
CHECK(page:match("attempt to index field 'roll'"), "block carries the message")
CHECK(page:match("stack top"), "stacks are included by default")
CHECK(not page:match("local a = 1"), "locals stay out by default")
CHECK(page:match("Generated by Commander Debug"), "report is signed")
CHECK(not page:match("Part %d of"), "no part banner on a single-page report")

-- Locals on
DB.IncludeLocals = true
local withLocals = CommanderDebug.BuildPages()[1]
CHECK(withLocals:match("local a = 1"), "locals appear once switched on")
DB.IncludeLocals = false

-- Stacks off
DB.IncludeStacks = false
local noStacks = CommanderDebug.BuildPages()[1]
CHECK(not noStacks:match("stack top"), "stacks disappear once switched off")
CHECK(noStacks:match("call stacks were excluded"), "header says so when stacks are excluded")
DB.IncludeStacks = true

-- Trimming
local trimmed = CommanderDebug.TrimLines("a\nb\nc\nd\ne", 2)
CHECK(trimmed == "a\nb\n... (3 more lines trimmed)", "TrimLines keeps the head and says what it cut",
    trimmed)
CHECK(CommanderDebug.TrimLines(nil, 5) == nil, "TrimLines tolerates a missing stack")
CHECK(CommanderDebug.TrimLines("only one", 5) == "only one", "TrimLines leaves short text alone")

DB.StackLines = 2
local shortStacks = CommanderDebug.BuildPages()[1]
CHECK(shortStacks:match("1 more line trimmed"), "the stack-lines setting bites")
DB.StackLines = 14

-- Sanitising
local dirty = CommanderDebug.Sanitize("|cffff0000red|r and |Hitem:123|h[Thing]|h done   ")
CHECK(dirty == "red and [Thing] done", "colour codes and links are flattened", dirty)

-- Empty state
DB.OnlyCommander = true
_G.BugGrabber.GetDB = function() return {} end
local emptyPage = CommanderDebug.BuildPages()[1]
CHECK(emptyPage:match("No errors captured in this scope"), "empty scope still produces a prompt")
DB.OnlyCommander = false

-- ===========================================================================
-- Pagination
-- ===========================================================================

local many = {}
for i = 1, 40 do
    many[i] = {
        message = string.format([[Interface\AddOns\Commander_Test%d\File.lua:%d: error number %d]], i, i, i),
        stack = ("stack line\n"):rep(6),
        counter = i,
        time = NOW - i,
        session = 7,
    }
end
_G.BugGrabber.GetDB = function() return many end
DB.MaxErrors = 40
DB.PageSize = 6000

local manyPages, manyRecords, manyStats = CommanderDebug.BuildPages()
CHECK(#manyPages > 1, "a large report splits into pages", #manyPages)
CHECK(#manyRecords == 40, "every error made it through the cap", #manyRecords)
CHECK(manyStats.occurrences == 820, "occurrences add up across the set", manyStats.occurrences)

local seen, oversize = {}, 0
for index, text in ipairs(manyPages) do
    CHECK(text:match("^# Fix these"), "page " .. index .. " stands alone with the full header")
    CHECK(text:match("Part " .. index .. " of " .. #manyPages), "page " .. index .. " is labelled")
    if #text > DB.PageSize * 1.5 then oversize = oversize + 1 end
    for number in text:gmatch("error number (%d+)") do
        local n = tonumber(number)
        CHECK(not seen[n], "error " .. n .. " appears on exactly one page")
        seen[n] = true
    end
end
CHECK(oversize == 0, "no page blows well past the budget", oversize)
local total = 0
for _ in pairs(seen) do total = total + 1 end
CHECK(total == 40, "the split loses nothing", total)

-- Numbering runs continuously across pages rather than restarting
CHECK(manyPages[#manyPages]:match("### 40%."), "the last error keeps its global number")

-- A single error larger than the whole budget still gets a page of its own
_G.BugGrabber.GetDB = function()
    return { { message = "huge: " .. ("x"):rep(9000), counter = 1, time = NOW, session = 7 } }
end
DB.MaxErrors = 25
local hugePages = CommanderDebug.BuildPages()
CHECK(#hugePages == 1, "an oversized single error still yields one page", #hugePages)
CHECK(hugePages[1]:match("huge: xxx"), "the oversized error is not dropped")
DB.PageSize = 18000

-- ===========================================================================
-- Chat list + clear
-- ===========================================================================

_G.BugGrabber.GetDB = function() return grabberDB end
printLog = {}
CommanderDebug_List()
CHECK(#printLog >= 3, "list prints a summary plus a line per error", #printLog)
CHECK(printLog[1]:match("2 unique errors"), "list leads with the count", printLog[1])

printLog = {}
CommanderDebug_Clear()
CHECK(#grabberDB == 0, "clear empties the BugGrabber database")
CHECK(printLog[1] and printLog[1]:match("cleared"), "clear reports what it did")

-- ===========================================================================
-- Announce
-- ===========================================================================

DB.Announce = true
printLog = {}
Capture.Announce({ message = "x", addon = "Commander_Ping", counter = 1 }, true)
CHECK(printLog[1] and printLog[1]:match("Commander_Ping"), "announce names the addon", printLog[1])
printLog = {}
Capture.Announce({ message = "x", addon = "Commander_Ping", counter = 2 }, false)
CHECK(#printLog == 0, "repeat firings stay quiet")
DB.Announce = false

-- ===========================================================================
if os.getenv("DUMP") == "1" then
    io.write("\n", manyPages[1], "\n")
end

io.write(string.format("\n%d checks, %d failures\n", checks, fails))
if #caughtErrors > 0 then
    io.write("errors surfaced during the run:\n")
    for _, err in ipairs(caughtErrors) do io.write("  ", err, "\n") end
end
os.exit(fails == 0 and 0 or 1)
