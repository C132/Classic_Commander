-- Commander Meters UI smoke harness (luajit).
-- Loads the REAL shared framework (CommanderSettingsUI.lua, CommanderEvents.lua)
-- plus all three Commander_Meters files under a permissive WoW mock, then
-- drives login, the settings panel, slash commands, menus, the repaint loop,
-- fight transitions, and resets. Catches nil-global calls, bad signatures,
-- and template/font traps without a client.

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
-- Load the real framework + addon
-- ===========================================================================

local function Load(path)
    local chunk = assert(loadfile(path))
    chunk()
end

-- Suite palette fixture: shaped exactly like Commander_Console's global
-- (array entries {text, value, r, g, b}; CLASS carries no rgb) so the
-- suite-accent resolution and the dropdown parenthetical-strip both
-- execute under test
CommanderConsole_Colors = {
    { text = "Steel (Default)", value = "STEEL", r = 1, g = 1, b = 1 },
    { text = "Fel", value = "FEL", r = 0.5, g = 0.95, b = 0.15 },
    { text = "Class Color", value = "CLASS" },
}
-- Saved variables from a "previous session": a suite accent key, so login
-- must resolve it through the Console palette, not the local five
CommanderMetersDB = { AccentColor = "FEL" }

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
Load(ADDONS .. "/Commander_Meters/CommanderMetersDB.lua")
Load(ADDONS .. "/Commander_Meters/CommanderMetersEngine.lua")
Load(ADDONS .. "/Commander_Meters/CommanderMeters.lua")

local function Fire(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    for _, frame in ipairs(list) do
        local handler = frame.__scripts.OnEvent
        if handler then handler(frame, event, ...) end
    end
end

-- Login sequence
Fire("ADDON_LOADED", "Commander_Meters")
Fire("PLAYER_LOGIN")

CHECK(#harnessFailedErrors == 0, "C: login clean", harnessFailedErrors[1])
CHECK(CommanderMetersDB.EnableMeters == true, "C: defaults applied")
CHECK(CommanderMetersDB.DBVersion == 2, "C: schema version stamped", CommanderMetersDB.DBVersion)
CHECK(CommanderMetersDB.TextSize == 11 and CommanderMetersDB.BgOpacity == 0.92,
    "C: appearance defaults applied")
CHECK(CommanderMetersDB.AccentColor == "FEL",
    "C: saved suite accent survives ApplyDefaults", CommanderMetersDB.AccentColor)
CHECK(SlashCmdList.COMMANDERUI_METERS ~= nil, "C: slash registered")
CHECK(_G.SLASH_COMMANDERUI_METERS1 == "/cmeters" and _G.SLASH_COMMANDERUI_METERS2 == "/cm",
    "C: slash aliases /cmeters + /cm")
CHECK(_G.CommanderMetersFrame ~= nil, "C: main window created")
CHECK(_G.CommanderMetersDetailFrame ~= nil, "C: detail window created")

-- Module registered with the suite
do
    local found
    for _, info in ipairs(Commander.GetModules()) do
        if info.key == "Meters" then found = info end
    end
    CHECK(found ~= nil, "C: module in Commander registry")
    CHECK(found and found.slash == "/cmeters", "C: registry slash")
end

-- Every FontString that set a font used valid flags (SetFont asserts inside)
CHECK(#allFontStrings > 0, "C: fontstrings created", #allFontStrings)

-- Repaint pass with empty data
local root = _G.CommanderMetersFrame
root.__scripts.OnUpdate(root, 0.6)
CHECK(#harnessFailedErrors == 0, "C: empty repaint clean", harnessFailedErrors[1])

-- Inject the test fight through the slash path
SlashCmdList.COMMANDERUI_METERS("test")
CHECK(CommanderMetersEngine.InFight(), "C: test fight open")
root.__scripts.OnUpdate(root, 0.6)
CHECK(#harnessFailedErrors == 0, "C: live repaint clean", harnessFailedErrors[1])

-- Find the top bar's name: the warlock should lead damage
do
    local found = false
    for _, fs in ipairs(allFontStrings) do
        if fs.__text == "Diabolist" then found = true end
    end
    CHECK(found, "C: bars painted actor names")
end

-- Let the ticker close the fight (test events end ~1s before now)
now = now + 6
RunTickers()
CHECK(not CommanderMetersEngine.InFight(), "C: ticker closed the test fight")
CHECK(#CommanderMetersEngine.GetFights() == 1, "C: fight archived to Last")
root.__scripts.OnUpdate(root, 0.6)
CHECK(#harnessFailedErrors == 0, "C: post-fight repaint clean", harnessFailedErrors[1])

-- Death made it into the log with an hp snapshot
do
    local f1 = CommanderMetersEngine.GetFights()[1]
    CHECK(#f1.deaths == 1, "C: test fight recorded the death")
    local d = f1.deaths[1]
    CHECK(d and #d.log > 0, "C: death has an event trail")
end

-- Menus: mode menu lists all eight modes; pick HEALING
do
    local modeBtn
    -- find via scripts: buttons whose OnClick opens a menu; drive the real one
    -- through the header button reference exposed by click behavior instead:
    -- simulate by calling the OnClick of each button child until menu captured
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.__scripts.OnClick then
            menuCaptured = {}
            f.__scripts.OnClick(f)
            if #menuCaptured == 8 and menuCaptured[1].text == "DAMAGE" then
                modeBtn = f
                break
            end
        end
    end
    CHECK(modeBtn ~= nil, "C: mode menu opens with 8 modes")
    if modeBtn then
        for _, info in ipairs(menuCaptured) do
            if info.text == "HEALING" then info.func() end
        end
        root.__scripts.OnUpdate(root, 0.6)
        CHECK(#harnessFailedErrors == 0, "C: healing mode repaint clean", harnessFailedErrors[1])
    end
end

-- Utility modes recorded from the test fixture
do
    local f1 = CommanderMetersEngine.GetFights()[1]
    local warrior = f1 and f1.actors["Player-0-CMTEST01"]
    local priest = f1 and f1.actors["Player-0-CMTEST03"]
    CHECK(warrior and warrior.ints == 1, "C: test fight recorded the interrupt")
    CHECK(priest and priest.dispels == 1, "C: test fight recorded the dispel")
end

-- Kill/wipe tagging via ENCOUNTER_END (fires while the fight is open)
SlashCmdList.COMMANDERUI_METERS("test")
Fire("ENCOUNTER_END", 101, "Gruul the Dragonkiller", 4, 25, 1)
now = now + 6
RunTickers()
do
    local f1 = CommanderMetersEngine.GetFights()[1]
    CHECK(f1 and f1.success == true and f1.name == "Gruul the Dragonkiller",
        "C: encounter end tagged the last fight")
    root.__scripts.OnUpdate(root, 0.6)
    CHECK(#harnessFailedErrors == 0, "C: tagged label repaint clean", harnessFailedErrors[1])
end

-- Report to chat: share menu offers channels, sending produces lines
do
    local shareBtn
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.glyphName == "share" and f.__scripts.OnClick then
            shareBtn = f
            break
        end
    end
    CHECK(shareBtn ~= nil, "C: share button found")
    if shareBtn then
        menuCaptured = {}
        shareBtn.__scripts.OnClick(shareBtn)
        CHECK(#menuCaptured >= 2, "C: share menu offers channels", #menuCaptured)
        local before = #sentChat
        for _, info in ipairs(menuCaptured) do
            if info.text == "GUILD" then info.func() end
        end
        CHECK(#sentChat > before, "C: report sent lines", #sentChat - before)
        CHECK(sentChat[before + 1] and sentChat[before + 1].msg:find("Commander Meters"),
            "C: report header line", sentChat[before + 1] and sentChat[before + 1].msg)
        CHECK(sentChat[before + 1] and sentChat[before + 1].channel == "GUILD",
            "C: report channel honored")
        CHECK(sentChat[before + 1] and not sentChat[before + 1].msg:find("|c", 1, true),
            "C: report is plain text (no color escapes)")
    end
end

-- An empty segment must not broadcast a bare header line
do
    SlashCmdList.COMMANDERUI_METERS("wipe")
    local shareBtn
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.glyphName == "share" and f.__scripts.OnClick then
            shareBtn = f
            break
        end
    end
    if shareBtn then
        menuCaptured = {}
        shareBtn.__scripts.OnClick(shareBtn)
        local before = #sentChat
        for _, info in ipairs(menuCaptured) do
            if info.text == "GUILD" then info.func() end
        end
        CHECK(#sentChat == before, "C: empty segment sends nothing", #sentChat - before)
    end
    SlashCmdList.COMMANDERUI_METERS("test") -- restore data for later blocks
    now = now + 6
    RunTickers()
end

-- Split view: toggle opens the second pane and repaints clean
do
    local splitBtn
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.glyphName == "split" and f.__scripts.OnClick then
            splitBtn = f
            break
        end
    end
    CHECK(splitBtn ~= nil, "C: split button found")
    if splitBtn then
        -- Locate the specific widgets whose split behavior is pinned:
        -- the header mode button, pane 2's caption, and one row per pane
        local modeButton, cap2, pct1, pct2
        for _, f in ipairs(frames) do
            if f.__kind == "Button" then
                if f.headerRole == "mode" then modeButton = f end
                if f.paneIndex == 2 and f.text and not f.rank then cap2 = f end
                if f.rank and f.pct then
                    if f.paneIndex == 1 and not pct1 then pct1 = f.pct end
                    if f.paneIndex == 2 and not pct2 then pct2 = f.pct end
                end
            end
        end
        splitBtn.__scripts.OnClick(splitBtn)
        CHECK(CommanderMetersDB.SplitOpen == true, "C: split toggled on")
        root.__scripts.OnUpdate(root, 0.6)
        CHECK(#harnessFailedErrors == 0, "C: split repaint clean", harnessFailedErrors[1])
        CHECK(root.__w == CommanderMetersDB.FrameWidth,
            "C: split keeps the window footprint", root.__w)
        CHECK(modeButton and modeButton.__shown == false,
            "C: header mode button steps aside while split")
        CHECK(cap2 and cap2.text.__shown == true,
            "C: second pane caption visible while split")
        CHECK(cap2 and type(cap2.text.__text) == "string"
            and cap2.text.__text:find("HEALING", 1, true) ~= nil
            and cap2.text.__text:find("·", 1, true) ~= nil,
            "C: second pane caption carries mode and segment",
            cap2 and cap2.text.__text)
        -- The active split glyph must wear the seeded suite accent —
        -- proving AccentColor="FEL" resolved through the Console palette
        CHECK(splitBtn.icon and splitBtn.icon[1] and splitBtn.icon[1].__color
            and splitBtn.icon[1].__color[1] == 0.5
            and splitBtn.icon[1].__color[2] == 0.95
            and splitBtn.icon[1].__color[3] == 0.15,
            "C: active glyph wears the suite accent (FEL via Console palette)")
        CHECK(pct1 and pct1.__shown == false and pct2 and pct2.__shown == false,
            "C: split condenses both panes' row columns")
        splitBtn.__scripts.OnClick(splitBtn)
        CHECK(CommanderMetersDB.SplitOpen == false, "C: split toggled off")
        CHECK(pct1 and pct1.__shown == true, "C: full columns return unsplit")
        CHECK(cap2 and cap2.text.__shown == false, "C: captions hide unsplit")
        CHECK(modeButton and modeButton.__shown == true, "C: mode button returns unsplit")
    end
end

-- Pie breakdown: click an ability row in the open detail
do
    -- reopen a detail on the top bar row
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.guid and f.__scripts.OnClick then
            f.__scripts.OnClick(f)
            break
        end
    end
    root.__scripts.OnUpdate(root, 0.6)
    local abilityRow
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.keyRef and f.listIndex == 1 and f.__shown then
            abilityRow = f
            break
        end
    end
    CHECK(abilityRow ~= nil, "C: detail ability row found")
    if abilityRow then
        abilityRow.__scripts.OnClick(abilityRow)
        root.__scripts.OnUpdate(root, 0.6)
        CHECK(#harnessFailedErrors == 0, "C: pie repaint clean", harnessFailedErrors[1])
        local pctFound = false
        for _, fs in ipairs(allFontStrings) do
            if fs.__text and tostring(fs.__text):find("%%$") then pctFound = true end
        end
        CHECK(pctFound, "C: pie center readout painted")
        -- Hover inspects with NO click: enter a DIFFERENT ability row and
        -- the pie readout must re-target to it, tooltip up. On leave the
        -- tooltip drops but the selection sticks.
        local otherRow
        for _, f in ipairs(frames) do
            if f.__kind == "Button" and f.keyRef and f.listIndex == 1
                and f.__shown and f.keyRef ~= abilityRow.keyRef then
                otherRow = f
                break
            end
        end
        CHECK(otherRow ~= nil, "C: second ability row found for hover")
        if otherRow then
            local hoveredKey = otherRow.keyRef
            GameTooltip:Hide()
            otherRow.__scripts.OnEnter(otherRow)
            root.__scripts.OnUpdate(root, 0.6)
            local hoverSel = false
            for _, fs in ipairs(allFontStrings) do
                if fs.__text == hoveredKey then hoverSel = true end
            end
            CHECK(hoverSel, "C: hover re-targets the pie readout", hoveredKey)
            CHECK(GameTooltip.__shown == true, "C: hover raises the stats tooltip")
            otherRow.__scripts.OnLeave(otherRow)
            CHECK(GameTooltip.__shown == false, "C: leave hides the tooltip")
            CHECK(#harnessFailedErrors == 0, "C: hover inspection clean", harnessFailedErrors[1])
        end
        abilityRow.__scripts.OnClick(abilityRow) -- click path still selects
        root.__scripts.OnUpdate(root, 0.6)
    end
end

-- Detail close glyph: hides the popup
do
    local closeBtn
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.glyphName == "close" and f.__scripts.OnClick then
            closeBtn = f
            break
        end
    end
    CHECK(closeBtn ~= nil, "C: close glyph found")
    if closeBtn then
        _G.CommanderMetersDetailFrame:Show()
        closeBtn.__scripts.OnClick(closeBtn)
        CHECK(_G.CommanderMetersDetailFrame.__shown == false,
            "C: close glyph hides the detail")
        root.__scripts.OnUpdate(root, 0.6)
        CHECK(#harnessFailedErrors == 0, "C: close repaint clean", harnessFailedErrors[1])
    end
end

-- Death log + health curve: switch to DEATHS mode and repaint
do
    local modeBtn
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.__scripts.OnClick then
            menuCaptured = {}
            f.__scripts.OnClick(f)
            if #menuCaptured == 8 and menuCaptured[1].text == "DAMAGE" then
                modeBtn = f
                break
            end
        end
    end
    if modeBtn then
        for _, info in ipairs(menuCaptured) do
            if info.text == "DEATHS" then info.func() end
        end
        root.__scripts.OnUpdate(root, 0.6)
        CHECK(#harnessFailedErrors == 0, "C: deaths + curve repaint clean", harnessFailedErrors[1])
        -- Death-log hover tooltips: the trail rows carry the log entry
        -- (real spell tooltip + the event's numbers), the deaths rows the
        -- killing blow. Both must raise the tooltip on enter.
        _G.CommanderMetersDetailFrame:Show()
        root.__scripts.OnUpdate(root, 0.6)
        local trailRow, deathRow
        for _, f in ipairs(frames) do
            if f.__kind == "Button" and f.__shown then
                if f.logRef and not trailRow then trailRow = f end
                if f.deathRef and not deathRow then deathRow = f end
            end
        end
        CHECK(trailRow ~= nil, "C: death trail row carries its log entry")
        if trailRow then
            CHECK(type(trailRow.logRef.id) == "number" or trailRow.logRef.what == "Melee",
                "C: trail entry carries a spell id (or is Melee)")
            GameTooltip:Hide()
            trailRow.__scripts.OnEnter(trailRow)
            CHECK(GameTooltip.__shown == true, "C: trail hover raises the spell tooltip")
            trailRow.__scripts.OnLeave(trailRow)
            CHECK(GameTooltip.__shown == false, "C: trail leave hides the tooltip")
        end
        CHECK(deathRow ~= nil and deathRow.blowRef ~= nil,
            "C: deaths row carries its killing blow")
        if deathRow and deathRow.blowRef then
            GameTooltip:Hide()
            deathRow.__scripts.OnEnter(deathRow)
            CHECK(GameTooltip.__shown == true, "C: death-row hover tooltips the blow")
            deathRow.__scripts.OnLeave(deathRow)
        end
        CHECK(#harnessFailedErrors == 0, "C: death-log hover clean", harnessFailedErrors[1])
        -- Death report: the detail head's share glyph exists exactly when
        -- a death is selected, opens the channel menu, and sends the trail
        -- as plain text — header first, killing blow last, ranking-weight cap
        local dShare = _G.CommanderMetersDetailFrame.share
        CHECK(dShare ~= nil and dShare.__shown == true,
            "C: death share glyph shown with a death selected")
        if dShare then
            menuCaptured = {}
            dShare.__scripts.OnClick(dShare)
            CHECK(#menuCaptured >= 2, "C: death share menu offers channels", #menuCaptured)
            local before = #sentChat
            for _, info in ipairs(menuCaptured) do
                if info.text == "GUILD" then info.func() end
            end
            local sent = #sentChat - before
            CHECK(sent >= 2 and sent <= 6, "C: death report is header + capped trail", sent)
            local head = sentChat[before + 1]
            CHECK(head and head.msg:find("DEATH: Confessor", 1, true) ~= nil,
                "C: death report header names the fallen", head and head.msg)
            CHECK(head and head.channel == "GUILD", "C: death report channel honored")
            local last = sentChat[#sentChat]
            CHECK(last and last.msg:find("Skull Crack", 1, true) ~= nil,
                "C: death report ends at the killing blow", last and last.msg)
            CHECK(last and not last.msg:find("|", 1, true),
                "C: death report is plain text (no escapes)")
        end
    end
end

-- Bar wheel scrolling path (offset clamp + repaint)
do
    for _, f in ipairs(frames) do
        if f.__scripts.OnMouseWheel then
            f.__scripts.OnMouseWheel(f, -1)
            f.__scripts.OnMouseWheel(f, 1)
        end
    end
    CHECK(#harnessFailedErrors == 0, "C: wheel scrolling clean", harnessFailedErrors[1])
end

-- Segment menu: overall + current + last + F#1
do
    local segBtn, entries
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.__scripts.OnClick then
            menuCaptured = {}
            f.__scripts.OnClick(f)
            if #menuCaptured >= 4 and menuCaptured[1].text == "OVERALL" then
                segBtn, entries = f, menuCaptured
                break
            end
        end
    end
    CHECK(segBtn ~= nil, "C: segment menu opens")
    if entries then
        CHECK(entries[2].text == "CURRENT" and entries[3].text == "LAST",
            "C: segment menu order")
        CHECK(entries[4] and entries[4].text:find("F#%d"), "C: fight entry listed", entries[4] and entries[4].text)
        entries[1].func() -- OVERALL
        root.__scripts.OnUpdate(root, 0.6)
        CHECK(#harnessFailedErrors == 0, "C: overall view repaint clean", harnessFailedErrors[1])
    end
end

-- Bar click opens the detail view
do
    local clicked = false
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.guid and f.__scripts.OnClick then
            f.__scripts.OnClick(f)
            clicked = true
            break
        end
    end
    CHECK(clicked, "C: found a clickable bar row")
    CHECK(_G.CommanderMetersDetailFrame.__shown, "C: detail opened on click")
    root.__scripts.OnUpdate(root, 0.6)
    CHECK(#harnessFailedErrors == 0, "C: detail repaint clean", harnessFailedErrors[1])
    -- Pie auto-opens on the top entry (its 16pt readout exists without any
    -- ability-row click), and the column header labels painted
    local pctFound, colFound = false, false
    for _, fs in ipairs(allFontStrings) do
        if fs.__font and fs.__font[2] == 16 and fs.__text
            and tostring(fs.__text):find("%%$") then
            pctFound = true
        end
        -- records modes label N/CRIT; deaths mode labels AMOUNT/TIME
        if fs.__text == "N/CRIT" or fs.__text == "AMOUNT" then colFound = true end
    end
    CHECK(pctFound or colFound, "C: pie auto-opened (records) or death labels shown")
    CHECK(colFound, "C: breakdown column labels painted")
end

-- Reset menu wipes
do
    local entries
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.__scripts.OnClick then
            menuCaptured = {}
            f.__scripts.OnClick(f)
            if #menuCaptured == 2 and menuCaptured[1].text:find("RESET FIGHT") then
                entries = menuCaptured
                break
            end
        end
    end
    CHECK(entries ~= nil, "C: reset menu opens with two labeled actions")
    if entries then
        entries[2].func() -- RESET EVERYTHING
        CHECK(#CommanderMetersEngine.GetFights() == 0, "C: reset everything cleared fights")
        CHECK(CommanderMetersEngine.GetOverall().totals.dmg == 0, "C: reset everything cleared overall")
        root.__scripts.OnUpdate(root, 0.6)
        CHECK(#harnessFailedErrors == 0, "C: post-reset repaint clean", harnessFailedErrors[1])
    end
end

-- Toggle + dump + health slash paths
SlashCmdList.COMMANDERUI_METERS("")
CHECK(CommanderMetersDB.WindowShown == false, "C: bare slash toggled window off")
SlashCmdList.COMMANDERUI_METERS("")
CHECK(CommanderMetersDB.WindowShown == true, "C: bare slash toggled window on")
SlashCmdList.COMMANDERUI_METERS("dump")
CHECK(CommanderMetersLog.events ~= nil, "C: dump capture armed")
SlashCmdList.COMMANDERUI_METERS("test")
CHECK(#CommanderMetersLog.events > 0, "C: raw events captured", #CommanderMetersLog.events)
SlashCmdList.COMMANDERUI_METERS("dump")
SlashCmdList.COMMANDERUI_METERS("health")
SlashCmdList.COMMANDERUI_METERS("wipefight")
SlashCmdList.COMMANDERUI_METERS("wipe")
SlashCmdList.COMMANDERUI_METERS("settings")
CHECK(#harnessFailedErrors == 0, "C: all slash paths clean", harnessFailedErrors[1])

-- Settings panel: flip every widget through its refreshers
do
    local panel
    for _, cat in ipairs(categories) do
        if cat.__title == "Meters" then panel = cat.__panel end
    end
    CHECK(panel ~= nil, "C: Meters subcategory registered")
    if panel then
        panel:Refresh()
        CHECK(#harnessFailedErrors == 0, "C: panel refresh clean", harnessFailedErrors[1])
    end
end

-- Graph toggle path
do
    local graphBtn
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.glyphName == "graph" then
            graphBtn = f
            break
        end
    end
    CHECK(graphBtn ~= nil, "C: graph button found")
    if graphBtn then
        SlashCmdList.COMMANDERUI_METERS("test")
        graphBtn.__scripts.OnClick(graphBtn)
        root.__scripts.OnUpdate(root, 0.6)
        CHECK(#harnessFailedErrors == 0, "C: graph repaint clean", harnessFailedErrors[1])
        graphBtn.__scripts.OnClick(graphBtn)
    end
end

-- Fight-follow behavior: AutoSwitchCurrent flashes and switches (indirect:
-- fresh fight then close, repaint stays clean and segment label updates)
now = now + 10
RunTickers()
root.__scripts.OnUpdate(root, 0.6)
CHECK(#harnessFailedErrors == 0, "C: follow-combat transitions clean", harnessFailedErrors[1])

-- Master switch gates the tester
CommanderMetersDB.EnableMeters = false
SlashCmdList.COMMANDERUI_METERS("test")
CHECK(not CommanderMetersEngine.InFight(), "C: test refused while disabled")
CommanderMetersDB.EnableMeters = true

-- Tooltips: bar hover and detail-row hover run clean and carry spell ids
do
    local barRow
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.guid and f.__scripts.OnEnter then
            barRow = f
            break
        end
    end
    CHECK(barRow ~= nil, "C: hoverable bar row found")
    if barRow then
        barRow.__scripts.OnEnter(barRow)
        barRow.__scripts.OnLeave(barRow)
    end
    local abilityRow
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.recRef and f.__scripts.OnEnter then
            abilityRow = f
            break
        end
    end
    if abilityRow then
        abilityRow.__scripts.OnEnter(abilityRow)
        abilityRow.__scripts.OnLeave(abilityRow)
        CHECK(type(abilityRow.recRef.id) == "number" or abilityRow.recRef.name == "Melee",
            "C: ability record carries a spell id (or is Melee)")
        -- A records-mode detail painted this row, so the death share glyph
        -- must have been put away by that same repaint
        CHECK(_G.CommanderMetersDetailFrame.share.__shown == false,
            "C: death share glyph hidden outside deaths mode")
    end
    CHECK(#harnessFailedErrors == 0, "C: tooltip paths clean", harnessFailedErrors[1])
end

-- Detail popup: draggable by its title bar
do
    local detail = _G.CommanderMetersDetailFrame
    local head
    for _, f in ipairs(frames) do
        if f.__scripts.OnDragStart and f.__scripts.OnDragStop and f ~= root then
            head = f
            break
        end
    end
    CHECK(head ~= nil, "C: detail title bar registers drag handlers")
    if head then
        head.__scripts.OnDragStart(head)
        head.__scripts.OnDragStop(head)
        CHECK(#harnessFailedErrors == 0, "C: detail drag cycle clean", harnessFailedErrors[1])
    end
end

-- Lock slashes drive the HudChrome state
SlashCmdList.COMMANDERUI_METERS("unlock")
CHECK(CommanderMetersDB.HudLocked == false, "C: /cmeters unlock")
SlashCmdList.COMMANDERUI_METERS("lock")
CHECK(CommanderMetersDB.HudLocked == true, "C: /cmeters lock")

-- Appearance toggles repaint clean (opacities live, click-through re-Apply)
CommanderMetersDB.BgOpacity = 0.5
CommanderMetersDB.BarOpacity = 0.6
CommanderMetersDB.ClickThrough = true
Commander.Notify(COMMANDER_METERS_EVENTS.UPDATE)
root.__scripts.OnUpdate(root, 0.6)
CHECK(#harnessFailedErrors == 0, "C: appearance + clickthrough clean", harnessFailedErrors[1])
CommanderMetersDB.ClickThrough = false
Commander.Notify(COMMANDER_METERS_EVENTS.UPDATE)

-- Session persistence: logout writes the snapshot only when opted in
CommanderMetersDB.PersistData = true
Fire("PLAYER_LOGOUT")
CHECK(type(CommanderMetersSession) == "table" and CommanderMetersSession.v == 1,
    "C: logout wrote the session snapshot")
CHECK(CommanderMetersSession.overall ~= nil, "C: snapshot carries Overall")
CommanderMetersDB.PersistData = false
Fire("PLAYER_LOGOUT")
CHECK(CommanderMetersSession == nil, "C: opt-out logout clears the snapshot")

-- Roster + regen + instance events
Fire("GROUP_ROSTER_UPDATE")
Fire("PLAYER_REGEN_DISABLED")
Fire("PLAYER_REGEN_ENABLED")
Fire("PLAYER_ENTERING_WORLD", false, false)
Fire("READY_CHECK", "Devinp", 30)
Fire("UNIT_PET", "player")
CHECK(#harnessFailedErrors == 0, "C: gameplay events clean", harnessFailedErrors[1])

-- Instance auto-reset baseline persists: a "reload" inside the same
-- instance must never wipe (the PersistData-cancellation regression)
do
    SlashCmdList.COMMANDERUI_METERS("test")
    now = now + 6
    RunTickers()
    local dmgBefore = CommanderMetersEngine.GetOverall().totals.dmg
    CHECK(dmgBefore > 0, "C: instance test has data")
    CommanderMetersDB.AutoResetOnInstance = true
    CommanderMetersDB.LastInstanceKey = "party42" -- persisted baseline
    instState.inInstance, instState.itype, instState.id = true, "party", 42
    Fire("PLAYER_ENTERING_WORLD", false, true) -- the post-/reload PEW
    CHECK(CommanderMetersEngine.GetOverall().totals.dmg == dmgBefore,
        "C: reload inside the same instance does not wipe")
    instState.id = 43
    Fire("PLAYER_ENTERING_WORLD", false, false) -- a REAL instance change
    CHECK(CommanderMetersEngine.GetOverall().totals.dmg == 0,
        "C: real instance transition wipes")
    CHECK(CommanderMetersDB.LastInstanceKey == "party43", "C: baseline persisted to DB")
    CommanderMetersDB.AutoResetOnInstance = false
    instState.inInstance, instState.itype, instState.id = false, "none", 0
    Fire("PLAYER_ENTERING_WORLD", false, false)
end

-- Restore Defaults on a changed bake-at-login option prints the reload hint
do
    CommanderMetersDB.AccentColor = "CYAN"
    SlashCmdList.COMMANDERUI_METERS("reset")
    local hinted = false
    for i = #printLog - 3, #printLog do
        if printLog[i] and printLog[i]:find("applies after /reload") then hinted = true end
    end
    CHECK(hinted, "C: restore defaults hints the reload for baked options")
    CHECK(CommanderMetersDB.AccentColor == "AMBER", "C: restore defaults reset the accent")
end

-- External live pane modes (the Commander_Threat embed contract): register,
-- show, paint from provider rows, menu entry, share, detail guard, retire
do
    local fakeRows = {
        { name = "Xena", class = "WARRIOR", valueText = "100%", pctText = "12.4k",
            rateText = "1.2k", barFrac = 1 },
        { name = "Gabrielle", class = "PRIEST", valueText = "85%", pctText = "9.1k",
            rateText = "800", barFrac = 0.85 },
    }
    CHECK(CommanderMeters_RegisterExternalMode({
        key = "XTEST", label = "XTEST",
        collect = function() return fakeRows, #fakeRows end,
        caption = function() return "FAKE MOB" end,
        empty = "Nothing live",
    }) == true, "C: external mode registers")
    CHECK(CommanderMeters_RegisterExternalMode({}) == false, "C: bad external spec refused")

    CHECK(CommanderMeters_ShowExternalPane("XTEST") == true, "C: show opens the pane")
    CHECK(CommanderMetersDB.SplitOpen == true and CommanderMetersDB.SplitMode == "XTEST",
        "C: split state adopted")
    local root = _G.CommanderMetersFrame
    root.__scripts.OnUpdate(root, 0.6)
    CHECK(#harnessFailedErrors == 0, "C: external pane repaint clean", harnessFailedErrors[1])
    local function fsShown(text)
        for _, fs in ipairs(allFontStrings) do
            if fs.__text ~= nil and tostring(fs.__text) == text then return true end
        end
        return false
    end
    local function fsMatching(pattern)
        for _, fs in ipairs(allFontStrings) do
            if type(fs.__text) == "string" and fs.__text:find(pattern) then return true end
        end
        return false
    end
    CHECK(fsShown("Xena") and fsShown("Gabrielle"), "C: provider rows painted")
    CHECK(fsShown("100%"), "C: provider value text painted")
    CHECK(fsMatching("FAKE MOB"), "C: external caption painted")

    -- The pane-2 caption's mode menu offers (and checks) the external mode
    local cap2
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.paneIndex == 2 and f.text and not f.bar
            and f.__scripts.OnClick then
            cap2 = f
        end
    end
    CHECK(cap2 ~= nil, "C: pane 2 caption found")
    if cap2 then
        menuCaptured = {}
        cap2.__scripts.OnClick(cap2)
        local hasX, checkedX = false, false
        for _, info in ipairs(menuCaptured) do
            if info.text == "XTEST" then
                hasX = true
                checkedX = info.checked and true or false
            end
        end
        CHECK(hasX, "C: mode menu offers the external mode", #menuCaptured)
        CHECK(checkedX, "C: external mode shows checked in its pane")
    end

    -- External pane 1: report lines come from the provider
    CommanderMetersDB.ViewMode = "XTEST"
    Commander.Notify(COMMANDER_METERS_EVENTS.UPDATE)
    local beforeChat = #sentChat
    local shareBtn
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.glyphName == "share" and f.__scripts.OnClick then
            shareBtn = f
        end
    end
    if shareBtn then
        menuCaptured = {}
        shareBtn.__scripts.OnClick(shareBtn)
        for _, info in ipairs(menuCaptured) do
            if info.text == "GUILD" then info.func() end
        end
    end
    CHECK(#sentChat > beforeChat and sentChat[beforeChat + 1].msg:find("XTEST") ~= nil,
        "C: external report header from the provider",
        sentChat[beforeChat + 1] and sentChat[beforeChat + 1].msg)
    CHECK(sentChat[beforeChat + 2] ~= nil and sentChat[beforeChat + 2].msg:find("Xena") ~= nil,
        "C: external report names the top row")

    -- External rows carry no guid: clicking one never opens the detail
    _G.CommanderMetersDetailFrame:Hide()
    local row2
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.paneIndex == 2 and f.bar and f.__scripts.OnClick then
            row2 = row2 or f
        end
    end
    CHECK(row2 ~= nil, "C: pane 2 row found")
    if row2 then
        row2.__scripts.OnClick(row2)
        CHECK(_G.CommanderMetersDetailFrame.__shown == false,
            "C: external rows never open the detail")
    end

    -- Retire: orphaned panes point back at real modes and repaint clean
    CommanderMeters_RetireExternalMode("XTEST")
    CHECK(CommanderMetersDB.ViewMode == "DMG" and CommanderMetersDB.SplitMode == "HEAL",
        "C: retire points orphaned panes at real modes")
    root.__scripts.OnUpdate(root, 0.6)
    CHECK(#harnessFailedErrors == 0, "C: post-retire repaint clean", harnessFailedErrors[1])
end

if fails > 0 then
    io.write(string.format("RESULT: %d/%d FAILED\n", fails, checks))
    for _, e in ipairs(harnessFailedErrors) do io.write("ERR: ", e, "\n") end
    os.exit(1)
end
io.write(string.format("STAGE C: all %d checks passed (%d fontstrings, %d frames)\n",
    checks, #allFontStrings, #frames))
