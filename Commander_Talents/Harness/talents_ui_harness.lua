-- Commander Talents UI smoke harness (luajit).
-- Loads the REAL shared framework (CommanderSettingsUI.lua, CommanderEvents.lua)
-- plus every Commander_Talents file under a permissive WoW mock (the Threat
-- harness preamble + item/talent/Quartermaster fixtures), then drives login,
-- the settings panel, the calculator window, tree binding on all nine classes,
-- talent clicks in both directions, tier/prerequisite refusals, preset and
-- custom loadouts, export/import popups, the briefing panel with and without
-- Quartermaster, and live-talent import. Catches nil-global calls, bad
-- signatures, and font traps without a client.
--
--   /opt/homebrew/bin/luajit talents_ui_harness.lua

-- Resolve the AddOns root from this file's own location so the harness runs
-- in a git worktree as well as the live AddOns directory
local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
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
local function PrintedMatching(pattern)
    for _, line in ipairs(printLog) do
        if line:find(pattern) then return line end
    end
end

local harnessFailedErrors = {}
function geterrorhandler()
    return function(err) harnessFailedErrors[#harnessFailedErrors + 1] = tostring(err) end
end

local VALID_FLAGS = { [""] = true, OUTLINE = true, THICKOUTLINE = true, MONOCHROME = true,
    ["OUTLINE, MONOCHROME"] = true }

local allFontStrings = {}
local eventRegistry = {}

local NUMERIC_GETTERS = {
    GetWidth = 240, GetHeight = 20, GetScale = 1, GetEffectiveScale = 1,
    GetFrameLevel = 2, GetLeft = 0, GetBottom = 0, GetTop = 0, GetRight = 0,
    GetVerticalScroll = 0, GetVerticalScrollRange = 0, GetStringWidth = 10,
    GetStringHeight = 12, GetID = 1, GetNumPoints = 1, GetAlpha = 1,
}

local function IsMethodName(key)
    return type(key) == "string" and (key:match("^Set") or key:match("^Get") or key:match("^Is")
        or key:match("^Can") or key:match("^Enable") or key:match("^Disable")
        or key:match("^Register") or key:match("^Unregister") or key:match("^Hook")
        or key:match("^Clear") or key:match("^Create") or key:match("^Show")
        or key:match("^Hide") or key:match("^Raise") or key:match("^Start")
        or key:match("^Stop") or key:match("^Add") or key:match("^Lock")
        or key:match("^Highlight") or key:match("^Insert"))
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
        local fn = function(s)
            local t = NewWidget("FontString")
            t.__parent = s
            allFontStrings[#allFontStrings + 1] = t
            return t
        end
        rawset(self, key, fn); return fn
    end
    if key == "SetScript" then
        local fn = function(s, name, handler) s.__scripts[name] = handler end
        rawset(self, key, fn); return fn
    end
    if key == "HookScript" then
        -- HookScript CHAINS (a replacement here would hide real bugs)
        local fn = function(s, name, handler)
            local prior = s.__scripts[name]
            if prior then
                s.__scripts[name] = function(...) prior(...) handler(...) end
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
                for i = #list, 1, -1 do if list[i] == s then table.remove(list, i) end end
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
        local fn = function(s) s.__shown = false end
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
    if key == "SetSize" then
        local fn = function(s, w, h) s.__w, s.__h = w, h end
        rawset(self, key, fn); return fn
    end
    if key == "SetWidth" then
        local fn = function(s, w) s.__w = w end
        rawset(self, key, fn); return fn
    end
    if key == "SetText" then
        local fn = function(s, text) s.__text = text end
        rawset(self, key, fn); return fn
    end
    if key == "GetText" then
        local fn = function(s) return s.__text or "" end
        rawset(self, key, fn); return fn
    end
    if key == "SetTexture" then
        local fn = function(s, tex) s.__texture = tex end
        rawset(self, key, fn); return fn
    end
    if key == "SetTexCoord" then
        local fn = function(s, ...) s.__texcoord = { ... } end
        rawset(self, key, fn); return fn
    end
    if key == "SetVertexColor" then
        local fn = function(s, r, g, b, a) s.__color = { r, g, b, a } end
        rawset(self, key, fn); return fn
    end
    if key == "SetDesaturated" then
        local fn = function(s, v) s.__desat = v and true or false end
        rawset(self, key, fn); return fn
    end
    if key == "SetAlpha" then
        local fn = function(s, a) s.__alpha = a end
        rawset(self, key, fn); return fn
    end
    if key == "SetEnabled" then
        local fn = function(s, v) s.__enabled = v and true or false end
        rawset(self, key, fn); return fn
    end
    if key == "IsEnabled" then
        local fn = function(s) if s.__enabled == nil then return true end return s.__enabled end
        rawset(self, key, fn); return fn
    end
    if key == "SetFont" then
        local fn = function(s, path, size, flags)
            assert(type(path) == "string" and type(size) == "number", "SetFont bad args")
            assert(flags == nil or VALID_FLAGS[flags], "SetFont invalid flags: " .. tostring(flags))
            s.__font = { path, size, flags }
        end
        rawset(self, key, fn); return fn
    end
    if key == "GetFont" then
        local fn = function(s)
            local f = s.__font or { "Fonts\\FRIZQT__.TTF", 12, "" }
            return f[1], f[2], f[3]
        end
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
    if key == "GetOwner" then
        local fn = function(s) return s.__owner end
        rawset(self, key, fn); return fn
    end
    if key == "SetOwner" then
        local fn = function(s, owner) s.__owner = owner; s.__lines = {} end
        rawset(self, key, fn); return fn
    end
    if key == "AddLine" or key == "AddDoubleLine" then
        local fn = function(s, text)
            s.__lines = s.__lines or {}
            s.__lines[#s.__lines + 1] = tostring(text)
        end
        rawset(self, key, fn); return fn
    end
    if key == "SetHyperlink" then
        local fn = function(s, link) s.__lines = { "item link " .. tostring(link) } end
        rawset(self, key, fn); return fn
    end
    if IsMethodName(key) then
        local fn = function() end
        rawset(self, key, fn); return fn
    end
    return nil
end

NewWidget = function(kind, name)
    return setmetatable({ __kind = kind, __name = name, __scripts = {}, __shown = true }, WidgetMT)
end

function CreateFrame(frameType, name, parent, template)
    local f = NewWidget(frameType, name)
    f.__template = template
    f.__parentFrame = parent
    if frameType == "CheckButton" or (template and template:find("CheckButton")) then
        f.Text = NewWidget("FontString")
    end
    if template and template:find("BasicFrameTemplate") then
        f.CloseButton = NewWidget("Button")
        f.TitleText = NewWidget("FontString")
        f.NineSlice = NewWidget("Texture")
        f.Bg = NewWidget("Texture")
        f.TitleBg = NewWidget("Texture")
        f.Inset = NewWidget("Frame")
    end
    if name then _G[name] = f end
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
GameFontNormalSmall = NewWidget("Font")
GameFontNormalLarge = NewWidget("Font")
GameFontHighlight = NewWidget("Font")
GameFontHighlightSmall = NewWidget("Font")
GameFontDisableSmall = NewWidget("Font")
GameFontDisable = NewWidget("Font")
NumberFontNormal = NewWidget("Font")

SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2 }
function PlaySound() end
BACKDROP_SLIDER_8_8 = {}
SAVE, CANCEL, DELETE, OKAY, ACCEPT = "Save", "Cancel", "Delete", "Okay", "Accept"

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

local timers = {}
C_Timer = {
    After = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end,
    NewTicker = function(interval, fn) return { interval = interval, fn = fn } end,
}
local function Advance(seconds)
    now = now + (seconds or 1)
    local due, keep = {}, {}
    for _, t in ipairs(timers) do
        if t.at <= now then due[#due + 1] = t else keep[#keep + 1] = t end
    end
    timers = keep
    for _, t in ipairs(due) do t.fn() end
end

local menuCaptured = {}
local dropdownInits = {}
function UIDropDownMenu_Initialize(frame, fn) dropdownInits[frame] = fn end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info) menuCaptured[#menuCaptured + 1] = info end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetSelectedValue() end
function UIDropDownMenu_SetText(frame, text) frame.__dropText = text end
function UIDropDownMenu_EnableDropDown() end
function UIDropDownMenu_DisableDropDown() end
function ToggleDropDownMenu(level, value, frame)
    menuCaptured = {}
    local init = dropdownInits[frame]
    if init then init(frame) end
    return menuCaptured
end

-- Static popups: the mock keeps the last shown dialog so tests can drive it
StaticPopupDialogs = {}
local lastPopup = nil
function StaticPopup_Show(which, arg1, arg2)
    local def = StaticPopupDialogs[which]
    if not def then return nil end
    local dialog = NewWidget("Frame", nil)
    dialog.which = which
    dialog.editBox = NewWidget("EditBox")
    dialog.editBox.GetParent = function() return dialog end
    dialog.__def = def
    lastPopup = dialog
    if def.OnShow then def.OnShow(dialog, dialog.data) end
    return dialog
end
local function PopupAccept(dialog, text)
    dialog = dialog or lastPopup
    if not dialog then return false end
    if text ~= nil then dialog.editBox:SetText(text) end
    if dialog.__def.OnAccept then dialog.__def.OnAccept(dialog, dialog.data) end
    return true
end

RAID_CLASS_COLORS = {}
for token, hex in pairs({
    WARRIOR = "ffc79c6e", PALADIN = "fff58cba", HUNTER = "ffabd473", ROGUE = "fffff569",
    PRIEST = "ffffffff", SHAMAN = "ff0070de", MAGE = "ff69ccf0", WARLOCK = "ff9482c9",
    DRUID = "ffff7d0a",
}) do
    RAID_CLASS_COLORS[token] = { r = 0.5, g = 0.5, b = 0.5, colorStr = hex }
end
LOCALIZED_CLASS_NAMES_MALE = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue",
    PRIEST = "Priest", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}
ITEM_QUALITY_COLORS = { [1] = { hex = "|cffffffff" }, [3] = { hex = "|cff0070dd" } }
SlashCmdList = {}

function GetRealmName() return "TestRealm" end
local playerClass = "WARRIOR"
function UnitClass(u) if u == "player" then return "Warrior", playerClass end end
function UnitName(u) if u == "player" then return "Devinp" end end
function UnitLevel() return 70 end
function IsShiftKeyDown() return false end
function ChatEdit_InsertLink() return true end
function InCombatLockdown() return false end

-- Item fixture (Quartermaster consumable rows)
local itemNames = {
    [22861] = { "Flask of Fortification", 3 },
    [22851] = { "Elixir of Major Fortitude", 1 },
    [27657] = { "Warp Burger", 1 },
}
C_Item = {
    GetItemInfo = function(id)
        local rec = itemNames[id]
        if not rec then return nil end
        return rec[1], "|cffitem|Hitem:" .. id .. "|h[" .. rec[1] .. "]|h|r", rec[2]
    end,
    GetItemIconByID = function(id) return itemNames[id] and ("Interface\\Icons\\inv_" .. id) end,
    GetItemCount = function() return 0 end,
}

-- Live talents fixture: classic (name-first) shape by default
local liveShape = "CLASSIC"
local liveTalents = {
    [1] = { { "Improved Heroic Strike", 3 }, { "Deflection", 2 } },
    [2] = { { "Cruelty", 5 } },
    [3] = {},
}
function GetTalentInfo(tab, idx)
    local rec = liveTalents[tab] and liveTalents[tab][idx]
    if not rec then return nil end
    if liveShape == "CLASSIC" then
        -- name, icon, tier, column, rank, maxRank
        return rec[1], "icon", 1, 1, rec[2], 5
    end
    -- id-first shape: id, name, icon, tier, column, rank
    return 1000 + idx, rec[1], "icon", 1, 1, rec[2]
end

-- ---------------------------------------------------------------------------
-- Quartermaster fixture (the cross-addon contract)
-- ---------------------------------------------------------------------------

CommanderQuartermasterData = {
    SlotNames = { FLASK = "Flask", FOOD = "Food", ELIXIR = "Elixir" },
    Recommendations = {
        WARRIOR = { specs = {
            { key = "PROTECTION", name = "Protection", role = "TANK", picks = {
                { slot = "FLASK", entries = { { id = 22861, name = "Flask of Fortification" } } },
                { slot = "FOOD", entries = { { id = 27657, name = "Warp Burger" } } },
            } },
            { key = "ARMS", name = "Arms", role = "MELEE", picks = {
                { slot = "ELIXIR", entries = { { id = 22851, name = "Elixir of Major Fortitude" } } },
            } },
        } },
    },
}
CommanderQuartermasterDB = { BrowserView = "BROWSE", BrowserClass = false, BrowserSpec = false }
local qmToggles = 0
function CommanderQuartermaster_Toggle() qmToggles = qmToggles + 1 end

-- ===========================================================================
-- Load the real framework + addon
-- ===========================================================================

local function Load(path) assert(loadfile(path))() end

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")

local TAL = ADDONS .. "/Commander_Talents/"
Load(TAL .. "CommanderTalentsData.lua")
for _, cls in ipairs({ "Warrior", "Paladin", "Hunter", "Rogue", "Priest",
                       "Shaman", "Mage", "Warlock", "Druid" }) do
    Load(TAL .. "CommanderTalentsData_" .. cls .. ".lua")
end
Load(TAL .. "CommanderTalentsEngine.lua")
Load(TAL .. "CommanderTalentsDB.lua")
Load(TAL .. "CommanderTalents.lua")

local function Fire(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    for _, frame in ipairs(list) do
        local handler = frame.__scripts.OnEvent
        if handler then handler(frame, event, ...) end
    end
end

local function TextMatching(pattern)
    for _, fs in ipairs(allFontStrings) do
        if type(fs.__text) == "string" and fs.__text:find(pattern) then return fs.__text end
    end
end

-- ===========================================================================
-- Login
-- ===========================================================================

Fire("ADDON_LOADED", "Commander_Talents")
Fire("PLAYER_LOGIN")

CHECK(#harnessFailedErrors == 0, "login clean", harnessFailedErrors[1])
CHECK(CommanderTalentsDB.EnableTalents == true, "defaults applied")
CHECK(CommanderTalentsDB.BrowserStyle == "WINDOW", "window style default")
CHECK(CommanderTalentsDB.ShowBriefing == true, "briefing on by default")
CHECK(SlashCmdList.COMMANDERUI_TALENTS ~= nil, "slash registered")
CHECK(_G.SLASH_COMMANDERUI_TALENTS1 == "/ctalents" and _G.SLASH_COMMANDERUI_TALENTS2 == "/ctal",
    "slash aliases /ctalents + /ctal")
CHECK(type(CommanderTalentsCustom) == "table", "custom build store bound")
CHECK(_G.CommanderTalentsFrame == nil, "window is lazy (not built at login)")

-- Data completeness reaches the UI layer
local classCount = 0
for _, token in ipairs(CommanderTalentsData.ClassOrder) do
    if CommanderTalentsData.Classes[token] then classCount = classCount + 1 end
end
CHECK(classCount == 9, "all nine classes loaded", classCount)

-- ===========================================================================
-- Open the calculator
-- ===========================================================================

CommanderTalents_Toggle()
local calc = _G.CommanderTalentsFrame
CHECK(calc ~= nil, "window created on toggle")
CHECK(calc.__shown == true, "window shown")
CHECK(#harnessFailedErrors == 0, "open clean", harnessFailedErrors[1])
CHECK(calc.TitleText.__text == "Talents", "title set")
CHECK(UISpecialFrames[#UISpecialFrames] == "CommanderTalentsFrame", "escape-close registered")
CHECK(#calc.panes == 3, "three tree panes")

-- Own class landed on its first preset (Warrior/Arms), 61 points placed
local state = calc._state()
CHECK(state ~= nil, "engine state bound")
CHECK(CommanderTalentsEngine.TotalSpent(state) == 61, "preset auto-loaded to 61 points",
    state and CommanderTalentsEngine.TotalSpent(state))
CHECK(CommanderTalentsDB.SelBuildKind == "PRESET", "preset selection remembered")
CHECK(TextMatching("Points remaining") ~= nil, "footer shows remaining points")
CHECK(TextMatching("Required level: |cffffffff70") ~= nil, "footer shows required level 70")

-- Panes bound with buttons and branches
local pane1 = calc.panes[1]
local btnCount = 0
for _ in pairs(pane1.buttons) do btnCount = btnCount + 1 end
CHECK(btnCount == #CommanderTalentsData.Classes.WARRIOR.trees[1].talents,
    "every Arms talent has a button", btnCount)
CHECK(#pane1.branchRecs > 0, "prerequisite branches drawn", #pane1.branchRecs)
CHECK(pane1.bgTL.__texture == "Interface\\TalentFrame\\WarriorArms-TopLeft",
    "tree art bound", pane1.bgTL.__texture)
CHECK(pane1.headerFS.__text:find("Arms"), "pane header names the tree")

-- Icons resolve to real icon paths
local anyIcon
for _, btn in pairs(pane1.buttons) do anyIcon = btn.icon.__texture; break end
CHECK(anyIcon and anyIcon:find("Interface\\Icons\\", 1, true) == 1,
    "talent icons pathed", anyIcon)

-- ===========================================================================
-- Talent clicking
-- ===========================================================================

local E = CommanderTalentsEngine
local function IdxOf(tree, name)
    for i, t in ipairs(CommanderTalentsData.Classes.WARRIOR.trees[tree].talents) do
        if t.name == name then return i end
    end
end
local function ClickTalent(paneIdx, talentIdx, button)
    local btn = calc.panes[paneIdx].buttons[talentIdx]
    btn.__scripts.OnClick(btn, button or "LeftButton")
end

-- At 61/61 every add must be refused by the cap. Pick a talent the preset
-- left room in (whose only obstacle can be the cap).
local iRoom
for i, t in ipairs(CommanderTalentsData.Classes.WARRIOR.trees[1].talents) do
    local block = E.AddBlock(state, 1, i)
    if block and block.type == "CAP" then iRoom = i break end
end
CHECK(iRoom ~= nil, "a cap-blocked talent exists at 61/61")
local beforeCap = E.TotalSpent(state)
ClickTalent(1, iRoom, "LeftButton")
CHECK(E.TotalSpent(state) == beforeCap, "cap refuses a 62nd point")
CHECK(calc.flashFS.__text:find("remaining"), "cap refusal explains itself", calc.flashFS.__text)

-- Remove a point, then the same add succeeds
local iRemovable
for i, rank in pairs(state.pts[1]) do
    if rank > 0 and E.CanRemove(state, 1, i) then iRemovable = i break end
end
CHECK(iRemovable ~= nil, "a removable point exists")
local priorRank = E.Rank(state, 1, iRemovable)
ClickTalent(1, iRemovable, "RightButton")
CHECK(E.Rank(state, 1, iRemovable) == priorRank - 1, "right-click removes a point")
CHECK(E.TotalSpent(state) == 60, "total drops to 60")
ClickTalent(1, iRoom, "LeftButton")
CHECK(E.TotalSpent(state) == 61, "left-click adds once room exists")

-- Rank badge reflects state
local badge = calc.panes[1].buttons[iRoom].rankFS.__text
CHECK(badge and badge:find("/"), "rank badge rendered", badge)

-- A locked deep talent refuses and explains the tier requirement
do
    -- through the Clear BUTTON, so the visuals repaint like they would in game
    calc.clearBtn.__scripts.OnClick(calc.clearBtn)
    local iMS = IdxOf(1, "Mortal Strike")
    ClickTalent(1, iMS, "LeftButton")
    local blockedFlash = calc.flashFS.__text
    CHECK(E.Rank(state, 1, iMS) == 0, "tier gate refuses a row-7 talent from scratch")
    CHECK(blockedFlash:find("Requires") and blockedFlash:find("Arms"),
        "tier refusal names the requirement", blockedFlash)
    -- and its icon is desaturated while locked
    CHECK(calc.panes[1].buttons[iMS].icon.__desat == true, "locked talents desaturated")
    CHECK(calc.panes[1].buttons[IdxOf(1, "Deflection")].icon.__desat == false,
        "open talents not desaturated")
end

-- Prerequisite refusal: satisfy the tier, leave the prerequisite empty.
-- The pair is discovered from the data (arrows move between patches).
do
    calc.clearBtn.__scripts.OnClick(calc.clearBtn)
    local talents = CommanderTalentsData.Classes.WARRIOR.trees[1].talents
    local depIdx, reqIdx
    for i, t in ipairs(talents) do
        if t.req then
            local ri = IdxOf(1, t.req)
            if ri and (not depIdx or t.row < talents[depIdx].row) then
                depIdx, reqIdx = i, ri
            end
        end
    end
    CHECK(depIdx ~= nil, "Arms has a prerequisite arrow to test")
    local dep = talents[depIdx]
    -- Fill the tier budget WITHOUT touching the prerequisite
    local need = (dep.row - 1) * 5
    local guard = 0
    while E.PointsAboveRow(state, 1, dep.row) < need and guard < 200 do
        guard = guard + 1
        for i, t in ipairs(talents) do
            if i ~= reqIdx and t.row < dep.row and E.CanAdd(state, 1, i)
                and E.PointsAboveRow(state, 1, dep.row) < need then
                E.Add(state, 1, i)
            end
        end
    end
    CHECK(E.PointsAboveRow(state, 1, dep.row) >= need, "tier currency in place",
        E.PointsAboveRow(state, 1, dep.row))
    CHECK(E.Rank(state, 1, reqIdx) == 0, "prerequisite left empty")
    ClickTalent(1, depIdx, "LeftButton")
    CHECK(E.Rank(state, 1, depIdx) == 0,
        "prerequisite gate refuses " .. dep.name)
    CHECK(calc.flashFS.__text:find(talents[reqIdx].name, 1, true),
        "prereq refusal names the prerequisite", calc.flashFS.__text)
end

-- Removal validation: a supporting point cannot leave
do
    calc.clearBtn.__scripts.OnClick(calc.clearBtn)
    local iHeroic2 = IdxOf(1, "Improved Heroic Strike")   -- row 1, max 3
    local iDeflect = IdxOf(1, "Deflection")               -- row 1, max 5
    local iCharge = IdxOf(1, "Improved Charge")           -- row 2
    for _ = 1, 3 do ClickTalent(1, iHeroic2, "LeftButton") end
    for _ = 1, 2 do ClickTalent(1, iDeflect, "LeftButton") end
    ClickTalent(1, iCharge, "LeftButton")   -- row 2, needs the 5 above
    CHECK(E.Rank(state, 1, iCharge) == 1, "row-2 talent placed with 5 above it")
    ClickTalent(1, iHeroic2, "RightButton")
    CHECK(E.Rank(state, 1, iHeroic2) == 3, "supporting point refuses removal")
    CHECK(calc.flashFS.__text:find("supports"), "support refusal explains itself",
        calc.flashFS.__text)
    -- but the dependent itself can always go, freeing the support
    ClickTalent(1, iCharge, "RightButton")
    ClickTalent(1, iHeroic2, "RightButton")
    CHECK(E.Rank(state, 1, iHeroic2) == 2, "support releases once the dependent leaves")
end

-- Tooltip renders for a talent (and does not error)
do
    local btn = calc.panes[1].buttons[IdxOf(1, "Mortal Strike")]
    btn.__scripts.OnEnter(btn)
    CHECK(GameTooltip.__lines and #GameTooltip.__lines > 0, "talent tooltip built")
    local joined = table.concat(GameTooltip.__lines, "\n")
    CHECK(joined:find("Rank %d/%d"), "tooltip carries a rank line", joined:sub(1, 60))
    btn.__scripts.OnLeave(btn)
end
CHECK(#harnessFailedErrors == 0, "clicking clean", harnessFailedErrors[1])

-- ===========================================================================
-- Sidebar: presets and custom builds
-- ===========================================================================

local function SidebarRow(pattern)
    for _, btn in ipairs(calc._sidebar) do
        if btn.__shown and type(btn.labelFS.__text) == "string"
            and btn.labelFS.__text:find(pattern) then return btn end
    end
end

local protRow = SidebarRow("Protection")
CHECK(protRow ~= nil, "preset rows listed in the sidebar")
protRow.__scripts.OnClick(protRow, "LeftButton")
CHECK(CommanderTalentsDB.SelBuildKey == "PROTECTION", "preset click selects it")
CHECK(E.TotalSpent(state) == 61, "preset applies 61 points")
CHECK(E.Spent(state, 3) > 40, "protection points land in the Protection tree",
    E.Spent(state, 3))
CHECK(#harnessFailedErrors == 0, "preset select clean", harnessFailedErrors[1])

-- Editing a preset marks it edited
local iShieldSpec = IdxOf(3, "Anticipation") or 1
do
    local before = calc.summaryFS.__text
    CHECK(not before:find("edited"), "clean preset is not marked edited")
    local anyRemovable
    for i in pairs(state.pts[3]) do
        if E.CanRemove(state, 3, i) then anyRemovable = i break end
    end
    if anyRemovable then
        local btn = calc.panes[3].buttons[anyRemovable]
        btn.__scripts.OnClick(btn, "RightButton")
    end
    CHECK(calc.summaryFS.__text:find("edited"), "editing marks the build edited",
        calc.summaryFS.__text)
end

-- Save a custom build
local saveRow = SidebarRow("Save Current Build")
CHECK(saveRow ~= nil, "save row present")
saveRow.__scripts.OnClick(saveRow, "LeftButton")
CHECK(lastPopup and lastPopup.which == "COMMANDER_TALENTS_SAVE", "save popup opened")
PopupAccept(nil, "My Prot Build")
CHECK(CommanderTalentsCustom.WARRIOR and #CommanderTalentsCustom.WARRIOR == 1,
    "custom build stored")
local saved = CommanderTalentsCustom.WARRIOR[1]
CHECK(saved.name == "My Prot Build", "custom build named")
CHECK(saved.basedOn == "PROTECTION", "custom build remembers its spec")
CHECK(type(saved.points) == "table" and next(saved.points[3]) ~= nil,
    "custom build stores points by name")
CHECK(CommanderTalentsDB.SelBuildKind == "CUSTOM", "saving selects the new build")
CHECK(not calc.summaryFS.__text:find("edited"), "saving clears the edited flag")

-- Re-select it from the sidebar after switching away
protRow = SidebarRow("Protection")
protRow.__scripts.OnClick(protRow, "LeftButton")
local mineRow = SidebarRow("My Prot Build")
CHECK(mineRow ~= nil, "custom build listed in MY BUILDS")
mineRow.__scripts.OnClick(mineRow, "LeftButton")
CHECK(CommanderTalentsDB.SelBuildKey == "My Prot Build", "custom build re-selected")
CHECK(E.TotalSpent(state) == 60, "custom build re-applies its exact points",
    E.TotalSpent(state))

-- Right-click deletes (through the confirm popup)
mineRow.__scripts.OnClick(mineRow, "RightButton")
CHECK(lastPopup and lastPopup.which == "COMMANDER_TALENTS_DELETE", "delete popup opened")
lastPopup.data = "My Prot Build"
PopupAccept()
CHECK(#CommanderTalentsCustom.WARRIOR == 0, "custom build deleted")
CHECK(SidebarRow("none saved yet") ~= nil, "empty state row returns")
CHECK(#harnessFailedErrors == 0, "custom build cycle clean", harnessFailedErrors[1])

-- A long build list must never push the save row off the sidebar
do
    local snapshot = E.SerializePoints(state)
    for i = 1, 30 do
        CommanderTalentsCustom.WARRIOR[i] =
            { name = "Build " .. i, points = snapshot, at = now }
    end
    calc:Hide(); calc:Show()   -- OnShow repaints the sidebar
    CHECK(SidebarRow("Save Current Build") ~= nil,
        "save row survives a long build list")
    CHECK(SidebarRow("and %d+ more") ~= nil, "hidden builds are announced")
    local visible = 0
    for _, btn in ipairs(calc._sidebar) do if btn.__shown then visible = visible + 1 end end
    CHECK(visible <= 19, "sidebar never overflows its rows", visible)
    for i = #CommanderTalentsCustom.WARRIOR, 1, -1 do
        CommanderTalentsCustom.WARRIOR[i] = nil
    end
    calc:Hide(); calc:Show()
    CHECK(SidebarRow("none saved yet") ~= nil, "list empties cleanly")
end

-- ===========================================================================
-- Export / import
-- ===========================================================================

SidebarRow("Arms").__scripts.OnClick(SidebarRow("Arms"), "LeftButton")
local armsExport = E.Export(state)
calc.exportBtn.__scripts.OnClick(calc.exportBtn)
CHECK(lastPopup and lastPopup.which == "COMMANDER_TALENTS_EXPORT", "export popup opened")
CHECK(lastPopup.editBox.__text == armsExport, "export string in the copy box",
    lastPopup.editBox.__text)

-- Import the same string back after clearing
calc.clearBtn.__scripts.OnClick(calc.clearBtn)
CHECK(E.TotalSpent(state) == 0, "clear empties the build")
calc.importBtn.__scripts.OnClick(calc.importBtn)
CHECK(lastPopup.which == "COMMANDER_TALENTS_IMPORT", "import popup opened")
PopupAccept(nil, armsExport)
CHECK(E.Export(state) == armsExport, "imported build round-trips")
CHECK(E.TotalSpent(state) == 61, "imported build is complete")
CHECK(calc.summaryFS.__text:find("Imported"), "import labels the selection",
    calc.summaryFS.__text)

-- A Wowhead URL imports the same way
calc.clearBtn.__scripts.OnClick(calc.clearBtn)
calc.importBtn.__scripts.OnClick(calc.importBtn)
PopupAccept(nil, "https://www.wowhead.com/tbc/talent-calc/warrior/" .. armsExport)
CHECK(E.Export(state) == armsExport, "wowhead URL import round-trips")

-- Garbage is refused with a message, leaving the build alone
calc.importBtn.__scripts.OnClick(calc.importBtn)
PopupAccept(nil, "not-a-build")
CHECK(E.Export(state) == armsExport, "bad import leaves the build untouched")
CHECK(calc.flashFS.__text ~= "", "bad import explains itself", calc.flashFS.__text)
CHECK(#harnessFailedErrors == 0, "export/import clean", harnessFailedErrors[1])

-- ===========================================================================
-- Briefing panel
-- ===========================================================================

local protSidebar = SidebarRow("Protection")
protSidebar.__scripts.OnClick(protSidebar, "LeftButton")
local brief = calc.brief
CHECK(brief.__shown == true, "briefing panel shown")
CHECK(brief.titleFS.__text == "Protection", "briefing names the loadout")
CHECK(brief.subFS.__text:find("Tank"), "briefing shows the role tag", brief.subFS.__text)
CHECK(brief.statsFS.__text and brief.statsFS.__text:find("1%."),
    "stat priority numbered", brief.statsFS.__text)
CHECK(brief.notesFS.__text ~= "", "notes rendered")

-- Quartermaster consumables for the same spec
local consShown = 0
for _, row in ipairs(brief.consRows) do if row.__shown then consShown = consShown + 1 end end
CHECK(consShown == 2, "quartermaster consumables listed", consShown)
CHECK(brief.consRows[1].nameFS.__text:find("Flask of Fortification"),
    "consumable name resolved", brief.consRows[1].nameFS.__text)
CHECK(brief.consRows[1].slotFS.__text:find("Flask"), "consumable slot labelled")
CHECK(brief.qmBtn.__shown == true, "Open in Quartermaster offered")

-- The jump sets Quartermaster's view to this exact loadout
brief.qmBtn.__scripts.OnClick(brief.qmBtn)
CHECK(qmToggles == 1, "quartermaster toggled open")
CHECK(CommanderQuartermasterDB.BrowserView == "LOADOUT", "QM switched to loadout view")
CHECK(CommanderQuartermasterDB.BrowserClass == "WARRIOR", "QM class set")
CHECK(CommanderQuartermasterDB.BrowserSpec == "PROTECTION", "QM spec set")

-- A spec Quartermaster has no loadout for degrades quietly
do
    local fury = SidebarRow("Fury")
    fury.__scripts.OnClick(fury, "LeftButton")
    local shown = 0
    for _, row in ipairs(brief.consRows) do if row.__shown then shown = shown + 1 end end
    CHECK(shown == 0, "no consumable rows for an unstocked spec", shown)
    CHECK(brief.qmBtn.__shown == false, "jump button hidden without a loadout")
    CHECK(brief.consHintFS.__shown == true, "hint explains the gap")
end

-- Quartermaster absent entirely: soft-fail, no error
do
    local savedData, savedToggle = CommanderQuartermasterData, CommanderQuartermaster_Toggle
    CommanderQuartermasterData, CommanderQuartermaster_Toggle = nil, nil
    local prot = SidebarRow("Protection")
    prot.__scripts.OnClick(prot, "LeftButton")
    CHECK(#harnessFailedErrors == 0, "briefing survives a missing Quartermaster",
        harnessFailedErrors[1])
    CHECK(brief.consHintFS.__text:find("Quartermaster"),
        "hint names the optional addon", brief.consHintFS.__text)
    CHECK(brief.qmBtn.__shown == false, "no jump button without Quartermaster")
    CommanderQuartermasterData, CommanderQuartermaster_Toggle = savedData, savedToggle
end

-- Briefing can be turned off from settings
CommanderTalentsDB.ShowBriefing = false
Commander.Notify(COMMANDER_TALENTS_EVENTS.UPDATE)
CHECK(brief.__shown == false, "briefing hidden when disabled")
CommanderTalentsDB.ShowBriefing = true
Commander.Notify(COMMANDER_TALENTS_EVENTS.UPDATE)
CHECK(brief.__shown == true, "briefing returns when re-enabled")

-- ===========================================================================
-- Class switching
-- ===========================================================================

local infos = ToggleDropDownMenu(nil, nil, calc.classDrop)
CHECK(#infos == 9, "class dropdown lists nine classes", #infos)
local function PickClass(token)
    for _, info in ipairs(ToggleDropDownMenu(nil, nil, calc.classDrop)) do
        if info.value == token then info.func({ value = token }) return true end
    end
end

CHECK(PickClass("DRUID"), "druid selectable")
CHECK(CommanderTalentsDB.SelClass == "DRUID", "class selection remembered")
local druidState = calc._state()
CHECK(druidState ~= state, "druid gets its own state")
CHECK(E.TotalSpent(druidState) == 61, "druid lands on a preset")
CHECK(calc.panes[2].headerFS.__text:find("Feral"), "druid trees rebound",
    calc.panes[2].headerFS.__text)
CHECK(calc.panes[1].bgTL.__texture:find("DruidBalance"), "druid art bound",
    calc.panes[1].bgTL.__texture)
CHECK(calc.myTalentsBtn.__enabled == false, "My Talents disabled off-class")
CHECK(SidebarRow("Feral Cat") ~= nil, "druid presets listed")
CHECK(SidebarRow("Feral Bear") ~= nil, "both feral loadouts listed")

-- Every class binds without error, and its 41-point talents sit at row 9
for _, token in ipairs(CommanderTalentsData.ClassOrder) do
    PickClass(token)
    local st = calc._state()
    CHECK(st ~= nil and E.TotalSpent(st) > 0, token .. ": preset loaded")
end
CHECK(#harnessFailedErrors == 0, "all nine classes bind clean", harnessFailedErrors[1])

-- The bent Rogue arrow renders with its elbow
PickClass("ROGUE")
do
    local bent
    for _, pane in ipairs(calc.panes) do
        for _, rec in ipairs(pane.branchRecs) do
            if rec.kind == "l" then bent = rec end
        end
    end
    CHECK(bent ~= nil, "bent prerequisite arrow drawn (Serrated Blades -> Hemorrhage)")
    if bent then
        CHECK(bent.corner ~= nil and bent.line2 ~= nil, "bent arrow has elbow and second run")
        CHECK(bent.corner.__texcoord ~= nil, "elbow texcoords applied")
    end
end

-- Returning to a class keeps in-progress work
PickClass("WARRIOR")
local warriorBack = calc._state()
CHECK(warriorBack == state, "returning reuses the same state")
CHECK(calc.myTalentsBtn.__enabled == true, "My Talents enabled on your own class")

-- ===========================================================================
-- Live talent import
-- ===========================================================================

calc.myTalentsBtn.__scripts.OnClick(calc.myTalentsBtn)
CHECK(E.Rank(state, 1, IdxOf(1, "Improved Heroic Strike")) == 3,
    "live talents imported (classic shape)")
CHECK(E.Rank(state, 1, IdxOf(1, "Deflection")) == 2, "second live talent imported")
CHECK(E.Spent(state, 2) == 5, "live talents land in the right tree", E.Spent(state, 2))
CHECK(calc.summaryFS.__text:find("My Talents"), "summary labels the live import")
CHECK(#harnessFailedErrors == 0, "live import clean", harnessFailedErrors[1])

-- The id-first API shape works too
liveShape = "IDFIRST"
calc.clearBtn.__scripts.OnClick(calc.clearBtn)
calc.myTalentsBtn.__scripts.OnClick(calc.myTalentsBtn)
CHECK(E.Rank(state, 1, IdxOf(1, "Improved Heroic Strike")) == 3,
    "live talents imported (id-first shape)")
liveShape = "CLASSIC"

-- Unknown live talents are reported, not fatal
do
    local savedLive = liveTalents[1]
    liveTalents[1] = { { "Nonexistent Talent", 2 } }
    calc.myTalentsBtn.__scripts.OnClick(calc.myTalentsBtn)
    CHECK(PrintedMatching("unmatched live talents") ~= nil, "unknown live talents reported")
    CHECK(#harnessFailedErrors == 0, "unknown live talents non-fatal", harnessFailedErrors[1])
    liveTalents[1] = savedLive
end

-- ===========================================================================
-- Settings application
-- ===========================================================================

CommanderTalentsDB.BrowserStyle = "DARK"
Commander.Notify(COMMANDER_TALENTS_EVENTS.UPDATE)
CHECK(calc.NineSlice.__shown == false, "dark style drops the window art")
CommanderTalentsDB.BrowserStyle = "WINDOW"
Commander.Notify(COMMANDER_TALENTS_EVENTS.UPDATE)
CHECK(calc.NineSlice.__shown == true, "window style restores the art")

CommanderTalentsDB.BrowserScale = 1.2
Commander.Notify(COMMANDER_TALENTS_EVENTS.UPDATE)
CHECK(#harnessFailedErrors == 0, "scale change clean", harnessFailedErrors[1])

-- Restore Defaults through the panel's own reset path
CommanderTalentsDB.BrowserPos = { point = "CENTER", x = 100, y = 50 }
SlashCmdList.COMMANDERUI_TALENTS("reset")
CHECK(CommanderTalentsDB.BrowserPos == false, "reset clears the saved position")
CHECK(CommanderTalentsDB.BrowserScale == 1.0, "reset restores scale")
CHECK(PrintedMatching("restored to defaults") ~= nil, "reset announces itself")

-- Toggle closed and back open
CommanderTalents_Toggle()
CHECK(calc.__shown == false, "toggle closes")
CommanderTalents_Toggle()
CHECK(calc.__shown == true, "toggle reopens")

-- Export slash prints the string
SlashCmdList.COMMANDERUI_TALENTS("export")
CHECK(PrintedMatching("Commander Talents") ~= nil, "export slash prints")

-- Master switch refuses to open
CommanderTalentsDB.EnableTalents = false
CommanderTalents_Toggle()
CommanderTalents_Toggle()
CHECK(PrintedMatching("is disabled") ~= nil, "disabled module explains itself")
CommanderTalentsDB.EnableTalents = true

-- Item info arriving late refreshes the briefing without error
Fire("GET_ITEM_INFO_RECEIVED", 22861)
Advance(0.2)
CHECK(#harnessFailedErrors == 0, "late item info clean", harnessFailedErrors[1])

CHECK(#harnessFailedErrors == 0, "no errors overall", harnessFailedErrors[1])

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
