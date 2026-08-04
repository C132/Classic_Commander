-- Commander Buffs UI smoke harness (luajit).
-- Loads the REAL shared framework (CommanderSettingsUI.lua, CommanderEvents.lua)
-- plus all four Commander_Buffs files under a permissive WoW mock (the Threat
-- harness preamble + a fixture-driven aura API), then drives login, the
-- settings panel, the aura block, the Buffs-On-Top mirror, the deferred hide
-- of Blizzard's frames, the portrait sentinel, and the whole rule editor —
-- list operations, the inspector, the live trace, and Capture.
--
--   /opt/homebrew/bin/luajit buffs_ui_harness.lua

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
-- Resolve the AddOns root from this file's own location so the harness runs
-- from a worktree as happily as from the live folder (the Talents lesson).
local ADDONS = here .. "../../"

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end

-- ===========================================================================
-- WoW mock (the Meters harness widget machinery)
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
local frames = {}
local eventRegistry = {}

local NUMERIC_GETTERS = {
    GetWidth = 240, GetHeight = 0, GetScale = 1, GetEffectiveScale = 1,
    GetFrameLevel = 2, GetLeft = 0, GetBottom = 0, GetTop = 0, GetRight = 0,
    GetVerticalScroll = 0, GetVerticalScrollRange = 0, GetStringWidth = 10,
    GetID = 1, GetNumPoints = 1, GetAlpha = 1,
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

GameFontNormal = NewWidget("Font")
GameFontNormalLarge = NewWidget("Font")
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

-- ===========================================================================
-- Buffs-specific mock: unit frames, Blizzard aura frames, and the aura API
-- ===========================================================================

-- RegisterUnitEvent is not in the shared preamble; route it to the same
-- registry so UNIT_AURA reaches the module.
local baseIndex = WidgetMT.__index
WidgetMT.__index = function(self, key)
    if key == "RegisterUnitEvent" then
        local fn = function(s, event) s:RegisterEvent(event) end
        rawset(self, key, fn)
        return fn
    end
    if key == "HasFocus" then
        local fn = function() return false end
        rawset(self, key, fn)
        return fn
    end
    return baseIndex(self, key)
end

GameFontHighlightLarge = NewWidget("Font")
NumberFontNormalSmall = NewWidget("Font")
SlashCmdList = {}
RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
function GetCursorPosition() return 0, 0 end
function IsInInstance() return false, "none" end

-- BasicFrameTemplateWithInset ships more named regions than the shared
-- preamble mocks, and the framing toggle sets SetShown on all of them. The
-- permissive widget metatable would hand back a bare function for each,
-- which indexes fine and then explodes on the method call.
local baseCreateFrame = CreateFrame
function CreateFrame(frameType, name, parent, template)
    local f = baseCreateFrame(frameType, name, parent, template)
    if template and template:find("BasicFrameTemplate") then
        f.NineSlice = NewWidget("Frame")
        f.Bg = NewWidget("Texture")
        f.TitleBg = NewWidget("Texture")
        f.Inset = NewWidget("Frame")
    end
    return f
end

local combat = false
function InCombatLockdown() return combat end

local hooks = {}
function hooksecurefunc(target, name, fn)
    if type(target) == "string" then target, name, fn = _G, target, name end
    local original = target[name]
    hooks[#hooks + 1] = { target = target, name = name }
    target[name] = function(...)
        if original then original(...) end
        fn(...)
    end
end

local cancelled = {}
function CancelUnitBuff(unit, index) cancelled[#cancelled + 1] = index end

DebuffTypeColor = {
    Magic = { r = 0.2, g = 0.6, b = 1 },
    Curse = { r = 0.6, g = 0, b = 1 },
    Disease = { r = 0.6, g = 0.4, b = 0 },
    Poison = { r = 0, g = 0.6, b = 0 },
    none = { r = 0.8, g = 0, b = 0 },
}

PlayerFrame = NewWidget("Frame", "PlayerFrame")
PlayerPortrait = NewWidget("Texture", "PlayerPortrait")
TargetFrame = NewWidget("Frame", "TargetFrame")
BuffFrame = NewWidget("Frame", "BuffFrame")
DebuffFrame = NewWidget("Frame", "DebuffFrame")
TemporaryEnchantFrame = NewWidget("Frame", "TemporaryEnchantFrame")
frames[#frames + 1] = PlayerFrame

local buffFixtures, debuffFixtures = {}, {}

C_UnitAuras = {
    GetBuffDataByIndex = function(_, index) return buffFixtures[index] end,
    GetDebuffDataByIndex = function(_, index) return debuffFixtures[index] end,
}

-- t: name, id, icon, duration, left, stacks, school, mine, boss, stealable
local function MakeAura(t)
    return {
        name = t.name,
        icon = t.icon or 100,
        spellId = t.id,
        applications = t.stacks or 0,
        duration = t.duration or 0,
        expirationTime = (t.duration or 0) > 0 and (GetTime() + (t.left or t.duration)) or 0,
        dispelName = t.school,
        isFromPlayerOrPlayerPet = t.mine or false,
        isBossAura = t.boss or false,
        isStealable = t.stealable or false,
        sourceUnit = t.mine and "player" or "party1",
    }
end

local function SetStack(buffs, debuffs)
    for i = #buffFixtures, 1, -1 do buffFixtures[i] = nil end
    for i = #debuffFixtures, 1, -1 do debuffFixtures[i] = nil end
    for i, row in ipairs(buffs or {}) do buffFixtures[i] = MakeAura(row) end
    for i, row in ipairs(debuffs or {}) do debuffFixtures[i] = MakeAura(row) end
end

-- ===========================================================================
-- Load the real framework + addon
-- ===========================================================================

local function Load(path)
    local chunk = assert(loadfile(path), "missing file: " .. path)
    chunk()
end

CommanderConsole_Colors = {
    { text = "Steel (Default)", value = "STEEL", r = 1, g = 1, b = 1 },
    { text = "Fel", value = "FEL", r = 0.5, g = 0.95, b = 0.15 },
    { text = "Class Color", value = "CLASS" },
}

-- Saved variables left behind by the RETIRED v1 module (the 2026-07-06 buff
-- frame mover). Login must migrate them away without losing anything real.
CommanderBuffsDB = {
    BuffScale = 1.4,
    LockBuffFrames = false,
    BuffFramePoint = "TOPRIGHT",
    BuffFrameX = -205,
    BuffFrameY = -13,
    ShowAnchorInCombat = true,
    BuffsPerRow = 6,
}

function UnitName(u) return u == "player" and "Devinp" or nil end
function GetRealmName() return "TestRealm" end

Load(ADDONS .. "Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "Commander_Events/CommanderEvents.lua")
Load(ADDONS .. "Commander_Buffs/CommanderBuffsDB.lua")
Load(ADDONS .. "Commander_Buffs/CommanderBuffsEngine.lua")
Load(ADDONS .. "Commander_Buffs/CommanderBuffs.lua")
Load(ADDONS .. "Commander_Buffs/CommanderBuffsEditor.lua")

local function Fire(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    -- Copy: handlers may unregister mid-dispatch
    local copy = {}
    for i, frame in ipairs(list) do copy[i] = frame end
    for _, frame in ipairs(copy) do
        local handler = frame.__scripts.OnEvent
        if handler then handler(frame, event, ...) end
    end
end

local function Tick(elapsed)
    for _, frame in ipairs(frames) do
        local handler = frame.__scripts and frame.__scripts.OnUpdate
        if handler and frame.__shown ~= false then handler(frame, elapsed or 0.2) end
    end
end

local function ButtonWithText(text)
    for _, frame in ipairs(frames) do
        if frame.__text == text and frame.__scripts and frame.__scripts.OnClick then
            return frame
        end
    end
    return nil
end

local function ButtonStartingWith(prefix)
    for _, frame in ipairs(frames) do
        if type(frame.__text) == "string" and frame.__text:find(prefix, 1, true)
            and frame.__scripts and frame.__scripts.OnClick then
            return frame
        end
    end
    return nil
end

local function Click(button, mouse)
    if not button then return false end
    button.__scripts.OnClick(button, mouse or "LeftButton")
    return true
end

local function TextShownSomewhere(text)
    for _, fs in ipairs(allFontStrings) do
        if fs.__text ~= nil and tostring(fs.__text) == text then return true end
    end
    return false
end

local function TextMatching(pattern)
    for _, fs in ipairs(allFontStrings) do
        if type(fs.__text) == "string" and fs.__text:find(pattern) then return fs.__text end
    end
    return nil
end

local function ListRows()
    local out = {}
    for _, frame in ipairs(frames) do
        if frame.chip and frame.enable and frame.score then out[#out + 1] = frame end
    end
    return out
end

local function TraceRows()
    local out = {}
    for _, frame in ipairs(frames) do
        if frame.icon and frame.rule and frame.score then out[#out + 1] = frame end
    end
    return out
end

local function ShownIcons(prefix)
    local count = 0
    local index = 1
    while _G[prefix .. index] do
        if _G[prefix .. index].__shown then count = count + 1 end
        index = index + 1
    end
    return count
end

-- ===========================================================================
-- Login
-- ===========================================================================

Fire("ADDON_LOADED", "Commander_Buffs")

CHECK(CommanderBuffsDB.DBVersion == 2, "L: schema stamped", CommanderBuffsDB.DBVersion)
CHECK(CommanderBuffsDB.BuffScale == nil, "L: retired module's keys migrated away")
CHECK(CommanderBuffsDB.BuffFramePoint == nil, "L: retired module's anchor migrated away")
CHECK(CommanderBuffsDB.EnableBuffs == true, "L: defaults applied")
CHECK(CommanderBuffsDB.BuffSize == 21, "L: buff size mirrors the client's large aura size")
CHECK(type(CommanderBuffsDB.Rules) == "table" and #CommanderBuffsDB.Rules == 9,
    "L: the nine shipped rules are seeded", CommanderBuffsDB.Rules and #CommanderBuffsDB.Rules)

Fire("PLAYER_LOGIN")

CHECK(#harnessFailedErrors == 0, "L: login clean", harnessFailedErrors[1])
CHECK(SlashCmdList.COMMANDERUI_BUFFS ~= nil, "L: slash registered")
CHECK(_G.SLASH_COMMANDERUI_BUFFS1 == "/cbuffs", "L: primary slash")
CHECK(_G.SLASH_COMMANDERUI_BUFFS2 == "/cbuff", "L: legacy slash kept as an alias")
do
    local found = false
    for _, module in ipairs(Commander.GetModules()) do
        if module.key == "Buffs" then found = true end
    end
    CHECK(found, "L: module registered with the suite")
end
CHECK(_G.CommanderBuffsBlock ~= nil, "L: block frame built")
CHECK(_G.CommanderBuffsSentinel ~= nil, "L: sentinel frame built")

-- ===========================================================================
-- The block
-- ===========================================================================

SetStack({
    { name = "Arcane Intellect", id = 10157, duration = 1800, left = 1500 },
    { name = "Renew", id = 139, duration = 15, left = 9, mine = true },
    { name = "Ice Block", id = 45438, duration = 10, left = 2, mine = true },
}, {
    { name = "Polymorph", id = 118, duration = 10, left = 6, school = "Magic" },
    { name = "Sunder Armor", id = 7386, duration = 30, left = 20, stacks = 5 },
})
Fire("UNIT_AURA", "player")

CHECK(_G.CommanderBuffsBlock.__shown, "B: block shows with auras up")
CHECK(ShownIcons("CommanderBuffsIcon") == 5, "B: one icon per aura",
    ShownIcons("CommanderBuffsIcon"))

do
    local auras, auraN, ranked = CommanderBuffs_GetTrace()
    CHECK(auraN == 5, "B: five auras scanned", auraN)
    CHECK(auras[1].name == "Arcane Intellect", "B: buffs scanned first")
    CHECK(auras[4].isHarmful, "B: debuffs follow the buffs")
    CHECK(auras[2].mine, "B: my own aura is flagged mine")
    CHECK(auras[5].stacks == 5, "B: stack count read")
    CHECK(#ranked > 0, "B: the policy ranked the stack")
    CHECK(ranked[1].aura.spellId == 45438, "B: Ice Block about to drop leads the ranking",
        ranked[1] and ranked[1].aura.name)
end

-- Fewer auras must release the extra icons
SetStack({ { name = "Renew", id = 139, duration = 15, left = 9, mine = true } }, {})
Fire("UNIT_AURA", "player")
CHECK(ShownIcons("CommanderBuffsIcon") == 1, "B: icons released as the stack shrinks",
    ShownIcons("CommanderBuffsIcon"))

-- The block filter borrows the policy's HIDE rules
SetStack({
    { name = "Arcane Intellect", id = 10157, duration = 1800, left = 1500 },
    { name = "Renew", id = 139, duration = 15, left = 9, mine = true },
}, {})
CommanderBuffsDB.BlockFilter = "RULES"
Fire("UNIT_AURA", "player")
CHECK(ShownIcons("CommanderBuffsIcon") == 1,
    "B: Rules Applied drops the hidden raid buff", ShownIcons("CommanderBuffsIcon"))
CommanderBuffsDB.BlockFilter = "ALL"
Fire("UNIT_AURA", "player")
CHECK(ShownIcons("CommanderBuffsIcon") == 2, "B: Everything shows the whole stack")

-- Disabling the block hides it outright
CommanderBuffsDB.EnableBlock = false
Commander.Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
CHECK(not _G.CommanderBuffsBlock.__shown, "B: block hides when switched off")
CommanderBuffsDB.EnableBlock = true
Commander.Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
CHECK(_G.CommanderBuffsBlock.__shown, "B: block comes back")

-- ===========================================================================
-- Buffs On Top, mirrored from the target frame
-- ===========================================================================

TargetFrame.buffsOnTop = nil
CHECK(CommanderBuffs_MirrorAvailable() == false, "M: no source means no mirror")
CHECK(CommanderBuffs_BuffsOnTop() == false, "M: unavailable mirror falls back to debuffs on top")

TargetFrame.buffsOnTop = true
CHECK(CommanderBuffs_MirrorAvailable() == true, "M: the target frame is a source")
CHECK(CommanderBuffs_BuffsOnTop() == true, "M: mirror follows the target frame")
TargetFrame.buffsOnTop = false
CHECK(CommanderBuffs_BuffsOnTop() == false, "M: mirror follows the target frame back")

CommanderBuffsDB.BuffsOnTopMode = "ON"
CHECK(CommanderBuffs_BuffsOnTop() == true, "M: explicit ON overrides the mirror")
CommanderBuffsDB.BuffsOnTopMode = "OFF"
TargetFrame.buffsOnTop = true
CHECK(CommanderBuffs_BuffsOnTop() == false, "M: explicit OFF overrides the mirror")
CommanderBuffsDB.BuffsOnTopMode = "MIRROR_TARGET"

-- Group order actually changes: with buffs on top the first icon is a buff.
SetStack({ { name = "Renew", id = 139, duration = 15, left = 9, mine = true } },
         { { name = "Polymorph", id = 118, duration = 10, left = 6, school = "Magic" } })
TargetFrame.buffsOnTop = true
Fire("UNIT_AURA", "player")
CHECK(_G.CommanderBuffsIcon1.auraFilter == "HELPFUL", "M: buffs on top draws the buff first",
    _G.CommanderBuffsIcon1.auraFilter)
TargetFrame.buffsOnTop = false
Fire("UNIT_AURA", "player")
CHECK(_G.CommanderBuffsIcon1.auraFilter == "HARMFUL", "M: debuffs on top draws the debuff first",
    _G.CommanderBuffsIcon1.auraFilter)

-- Edit Mode re-asserting its layout must not undo any of it
Fire("EDIT_MODE_LAYOUTS_UPDATED")
CHECK(_G.CommanderBuffsBlock.__shown, "M: block survives an Edit Mode layout update")

-- ===========================================================================
-- Blizzard's own frames
-- ===========================================================================

CHECK(BuffFrame.__shown == false, "D: the default buff frame is hidden")
CHECK(DebuffFrame.__shown == false, "D: the default debuff frame is hidden")
CHECK(TemporaryEnchantFrame.__shown ~= false,
    "D: weapon enchants are left alone by default")

CommanderBuffsDB.HideTempEnchants = true
Commander.Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
CHECK(TemporaryEnchantFrame.__shown == false, "D: weapon enchants hide on request")
CommanderBuffsDB.HideTempEnchants = false
Commander.Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
CHECK(TemporaryEnchantFrame.__shown == true, "D: weapon enchants come back")

-- The hide is only ever honored while we are drawing a replacement
CommanderBuffsDB.EnableBlock = false
Commander.Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
CHECK(BuffFrame.__shown == true, "D: no block means no hide — never zero auras")
CommanderBuffsDB.EnableBlock = true
Commander.Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
CHECK(BuffFrame.__shown == false, "D: hidden again once the block is back")

-- Blizzard re-showing its own frame must not win
BuffFrame:Show()
CHECK(BuffFrame.__shown == false, "D: a re-show from the client is put back down")

-- In combat the hide waits for PLAYER_REGEN_ENABLED
combat = true
CommanderBuffsDB.HideDefaultAuras = false
Commander.Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
CHECK(BuffFrame.__shown == false, "D: combat defers the change")
combat = false
Fire("PLAYER_REGEN_ENABLED")
CHECK(BuffFrame.__shown == true, "D: the deferred change lands on leaving combat")
CommanderBuffsDB.HideDefaultAuras = true
Commander.Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
CHECK(BuffFrame.__shown == false, "D: and hides again out of combat")

-- Master switch restores everything
CommanderBuffsDB.EnableBuffs = false
Commander.Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
CHECK(BuffFrame.__shown == true, "D: the master switch gives the client its frames back")
CHECK(not _G.CommanderBuffsBlock.__shown, "D: and takes the block away")
CommanderBuffsDB.EnableBuffs = true
Commander.Notify(COMMANDER_BUFFS_EVENTS.UPDATE)

-- ===========================================================================
-- The portrait sentinel
-- ===========================================================================

SetStack({
    { name = "Arcane Intellect", id = 10157, duration = 1800, left = 1500 },
    { name = "Ice Block", id = 45438, duration = 10, left = 2, mine = true },
}, {
    { name = "Polymorph", id = 118, duration = 10, left = 6, school = "Magic" },
})
Fire("UNIT_AURA", "player")

CHECK(_G.CommanderBuffsSentinel.__shown, "S: sentinel shows")
CHECK(_G.CommanderBuffsSentinel1.__shown, "S: slot one is painted")
CHECK(_G.CommanderBuffsSentinel1.auraName == "Polymorph"
    or _G.CommanderBuffsSentinel1.auraName == "Ice Block",
    "S: slot one carries a top-priority aura", _G.CommanderBuffsSentinel1.auraName)
CHECK(_G.CommanderBuffsSentinel2 == nil or not _G.CommanderBuffsSentinel2.__shown,
    "S: a single slot by default")

CommanderBuffsDB.Slots = 3
Commander.Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
CHECK(_G.CommanderBuffsSentinel2 and _G.CommanderBuffsSentinel2.__shown,
    "S: extra slots appear on request")
CommanderBuffsDB.Slots = 1
Commander.Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
CHECK(not _G.CommanderBuffsSentinel2.__shown, "S: extra slots retire again")

-- Minimum Score is the quiet dial
CommanderBuffsDB.MinScore = 200
Commander.Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
CHECK(not _G.CommanderBuffsSentinel.__shown, "S: a high floor silences the sentinel")
CommanderBuffsDB.MinScore = 0
Commander.Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
CHECK(_G.CommanderBuffsSentinel.__shown, "S: a floor of zero is never empty")
CommanderBuffsDB.MinScore = 40
Commander.Notify(COMMANDER_BUFFS_EVENTS.UPDATE)

CommanderBuffsDB.EnablePortrait = false
Commander.Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
CHECK(not _G.CommanderBuffsSentinel.__shown, "S: sentinel switches off")
CommanderBuffsDB.EnablePortrait = true
Commander.Notify(COMMANDER_BUFFS_EVENTS.UPDATE)

-- The ticker must survive with no aura data at all
SetStack({}, {})
Fire("UNIT_AURA", "player")
Tick(0.2)
CHECK(#harnessFailedErrors == 0, "S: an empty stack ticks clean", harnessFailedErrors[1])
CHECK(not _G.CommanderBuffsSentinel.__shown, "S: nothing to show means nothing shown")

-- ===========================================================================
-- The test stack
-- ===========================================================================

CommanderBuffs_Test()
CHECK(ShownIcons("CommanderBuffsIcon") == 9, "T: the test stack renders nine auras",
    ShownIcons("CommanderBuffsIcon"))
CHECK(_G.CommanderBuffsIcon1.auraIndex == nil,
    "T: test auras carry no aura index — a bogus one would tooltip the wrong aura")
CHECK(PrintedMatching("test stack"), "T: the tester says so")

-- ===========================================================================
-- The editor
-- ===========================================================================

CommanderBuffs_ToggleEditor()
local win = _G.CommanderBuffsEditorFrame
CHECK(win ~= nil and win.__shown, "E: the editor opens")
CHECK(TextShownSomewhere("Silence & incapacitate"), "E: the rule list renders rule names")
CHECK(TextMatching("^9 rules$") ~= nil, "E: the rule count is reported",
    TextMatching("rules"))
CHECK(TextShownSomewhere("Priority Rules"), "E: the list is headed")
CHECK(TextMatching("auras on you") ~= nil, "E: the trace counts your auras")

-- The trace shows every aura, including the ones the policy drops
CHECK(TextShownSomewhere("Arcane Intellect"), "E: a hidden aura still appears in the trace")
CHECK(TextMatching("hidden by") ~= nil, "E: and says which rule hid it",
    TextMatching("hidden by"))

do
    local rows = ListRows()
    CHECK(#rows == 17, "E: the list builds its row pool", #rows)
    CHECK(rows[1].index == 1, "E: rows carry their rule index")
end

-- List operations
local before = #CommanderBuffsDB.Rules
CHECK(Click(ButtonWithText("New")), "E: New is clickable")
CHECK(#CommanderBuffsDB.Rules == before + 1, "E: New adds a rule")
CHECK(Click(ButtonWithText("Duplicate")), "E: Duplicate is clickable")
CHECK(#CommanderBuffsDB.Rules == before + 2, "E: Duplicate adds a rule")
CHECK(Click(ButtonWithText("Delete")), "E: Delete is clickable")
CHECK(#CommanderBuffsDB.Rules == before + 1, "E: Delete removes a rule")

do
    -- Select the top rule and push it down, then back
    local rows = ListRows()
    rows[1].__scripts.OnClick(rows[1], "LeftButton")
    local topName = CommanderBuffsDB.Rules[1].name
    Click(ButtonWithText("Move Down"))
    CHECK(CommanderBuffsDB.Rules[2].name == topName, "E: Move Down reorders the policy")
    Click(ButtonWithText("Move Up"))
    CHECK(CommanderBuffsDB.Rules[1].name == topName, "E: Move Up puts it back")
end

-- Inspector: the cycle buttons drive the selected rule
do
    local rows = ListRows()
    rows[1].__scripts.OnClick(rows[1], "LeftButton")
    local rule = CommanderBuffsDB.Rules[1]
    local action = ButtonStartingWith("Action:")
    CHECK(action ~= nil, "E: the inspector has an action control")
    local wasAction = rule.action
    Click(action)
    CHECK(rule.action ~= wasAction, "E: cycling changes the rule's action", rule.action)
    Click(action)
    CHECK(rule.action == wasAction, "E: cycling all the way round restores it")

    local typeButton = ButtonStartingWith("Type:")
    local wasType = rule.match.auraType
    Click(typeButton)
    CHECK(rule.match.auraType ~= wasType, "E: cycling changes the matcher")
    Click(typeButton, "RightButton")
    CHECK(rule.match.auraType == wasType, "E: right-click cycles back")
end

-- The trace's Capture button builds a spell-id rule from a live aura
do
    local rows = TraceRows()
    local picked
    for _, row in ipairs(rows) do
        if row.__shown and row.entry then picked = row; break end
    end
    CHECK(picked ~= nil, "E: the trace has rows to capture from")
    if picked then
        local spellId = picked.entry.aura.spellId
        picked.__scripts.OnClick(picked, "LeftButton")
        local count = #CommanderBuffsDB.Rules
        CHECK(Click(ButtonWithText("Capture Rule")), "E: Capture is clickable")
        CHECK(#CommanderBuffsDB.Rules == count + 1, "E: Capture adds a rule")
        CHECK(CommanderBuffsDB.Rules[1].match.spellIds[1] == spellId,
            "E: the captured rule carries the aura's spell id")
        CHECK(CommanderBuffsDB.Rules[1].score == 110, "E: and outranks everything by default")
    end
end

-- Restore Default Rules is the only thing that replaces the list
Click(ButtonWithText("Defaults"))
CHECK(#CommanderBuffsDB.Rules == 9, "E: Defaults restores the shipped nine",
    #CommanderBuffsDB.Rules)
CHECK(PrintedMatching("restored to the shipped nine"), "E: and says so")

-- Settings Restore Defaults must NOT touch the rules
do
    CommanderBuffsDB.Rules[1].name = "Hand written"
    CommanderBuffsDB.BuffSize = 33
    local reset = ButtonStartingWith("Restore Defaults")
    CHECK(reset ~= nil, "E: the settings page has a Restore Defaults button")
    CHECK(Click(reset), "E: Restore Defaults is clickable")
    CHECK(CommanderBuffsDB.BuffSize == 21, "E: the settings reset does reset settings",
        CommanderBuffsDB.BuffSize)
    CHECK(CommanderBuffsDB.Rules[1].name == "Hand written",
        "E: the settings page's reset leaves hand-authored rules alone")
end

-- The editor ticks and closes
Tick(0.25)
CHECK(#harnessFailedErrors == 0, "E: the editor ticks clean", harnessFailedErrors[1])
CommanderBuffs_ToggleEditor()
CHECK(not win.__shown, "E: toggling closes it")

CommanderBuffsDB.EnableBuffs = false
CommanderBuffs_ToggleEditor()
CHECK(not win.__shown, "E: a disabled module refuses to open the editor")
CHECK(PrintedMatching("disabled"), "E: and explains why")
CommanderBuffsDB.EnableBuffs = true

-- ===========================================================================
-- Panel behaviour
-- ===========================================================================

do
    local handler = SlashCmdList.COMMANDERUI_BUFFS
    CHECK(handler ~= nil, "P: slash handler present")
    handler("")
    CHECK(_G.CommanderBuffsEditorFrame.__shown, "P: a bare slash opens the editor")
    handler("")
    handler("test")
    CHECK(PrintedMatching("test stack"), "P: /cbuffs test runs the tester")
end

-- Every panel refresher must survive a repaint with the module off
CommanderBuffsDB.EnableBuffs = false
for _, frame in ipairs(frames) do
    local onShow = frame.__scripts and frame.__scripts.OnShow
    if onShow and frame.__name and tostring(frame.__name):find("Commander") then
        pcall(onShow, frame)
    end
end
CHECK(#harnessFailedErrors == 0, "P: panels repaint with the module off",
    harnessFailedErrors[1])
CommanderBuffsDB.EnableBuffs = true

-- ===========================================================================
-- A full tick with everything on
-- ===========================================================================

SetStack({
    { name = "Ice Block", id = 45438, duration = 10, left = 1.5, mine = true },
    { name = "Renew", id = 139, duration = 15, left = 9, mine = true },
}, {
    { name = "Sunder Armor", id = 7386, duration = 30, left = 20, stacks = 5 },
})
CommanderBuffsDB.ShowTimers = true
CommanderBuffsDB.IconSweep = true
CommanderBuffsDB.SweepStyle = "WEDGE"
CommanderBuffsDB.PortraitTimer = true
Commander.Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
Fire("UNIT_AURA", "player")
Tick(0.2)
Tick(0.2)
CHECK(#harnessFailedErrors == 0, "F: a full tick is clean", harnessFailedErrors[1])
CHECK(_G.CommanderBuffsSentinel1.auraName == "Ice Block",
    "F: the expiring defensive holds the portrait", _G.CommanderBuffsSentinel1.auraName)

CommanderBuffsDB.SweepStyle = "RING"
Commander.Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
Tick(0.2)
CHECK(#harnessFailedErrors == 0, "F: the ring style ticks clean", harnessFailedErrors[1])

io.write(string.format("\n%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
