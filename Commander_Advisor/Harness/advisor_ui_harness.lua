-- Commander Advisor UI harness (luajit).
--
--   luajit Commander_Advisor/Harness/advisor_ui_harness.lua
--
-- Loads the REAL shared framework (CommanderSettingsUI.lua, CommanderEvents.lua)
-- plus all four Commander_Advisor files under a permissive WoW mock, then
-- drives login, the settings page, the tick over mocked action buttons, the
-- combat log, the glow, the tooltip and the report. The judgement itself is
-- covered by advisor_engine_smoke.lua; this checks the wiring around it.
--
-- Mock copied from Commander_Forecast/Harness/forecast_ui_harness.lua and
-- extended with the aura, loss-of-control, spellbook, action-bar and
-- animation surfaces the Advisor reads.

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
-- Advisor-specific mock
-- ===========================================================================

-- The player: a priest this time
function UnitClass(unit) if unit == "player" then return "Priest", "PRIEST" end return nil end
RAID_CLASS_COLORS.PRIEST = { r = 1, g = 1, b = 1 }

local me = {
    hp = 8000, hpMax = 8000, mana = 5000, manaMax = 5000,
    combat = false, dead = false, mounted = false, taxi = false, resting = false,
    buffs = {}, debuffs = {}, casting = nil, form = 0, loc = {},
    hasTarget = false, pet = false,
}
function UnitHealth(unit) if unit == "player" then return me.hp end return 1000 end
function UnitHealthMax(unit) if unit == "player" then return me.hpMax end return 1000 end
function UnitPower(unit) return me.mana end
function UnitPowerMax(unit) return me.manaMax end
function UnitPowerType() return 0 end
function UnitAffectingCombat() return me.combat end
function UnitIsDeadOrGhost() return me.dead end
function IsMounted() return me.mounted end
function UnitOnTaxi() return me.taxi end
function IsResting() return me.resting end
function IsStealthed() return false end
function IsOutdoors() return true end
function IsEquippedItemType() return false end
function GetShapeshiftForm() return me.form end
function GetShapeshiftFormInfo() return "icon", true, true, 15473 end
function UnitExists(unit)
    if unit == "player" then return true end
    if unit == "target" then return me.hasTarget end
    if unit == "pet" then return me.pet end
    if unit == "nameplate1" or unit == "nameplate1target" then return true end
    return false
end
function UnitCanAttack(a, b) return b == "target" or b == "nameplate1" end
function UnitIsUnit(a, b)
    if a == b then return true end
    if a == "nameplate1target" and b == "player" then return me.plateTargetsMe end
    return false
end
function UnitIsPlayer(unit) return unit == "nameplate1" and me.plateIsPlayer or false end
function UnitGUID(unit)
    if unit == "player" then return "Player-0-ME" end
    if unit == "nameplate1" then return "Player-0-ENEMY" end
    return nil
end
function UnitCastingInfo(unit)
    if unit == "player" then
        if me.casting then return me.casting, me.casting, "", 0, (GetTime() + 2) * 1000, false, "x", false, 1 end
        return nil
    end
    if unit == "nameplate1" and me.plateCast then
        return me.plateCast, me.plateCast, "", 0, (GetTime() + 1.5) * 1000, false, "y", false, 5782
    end
    return nil
end
function UnitChannelInfo() return nil end

C_UnitAuras = {
    GetBuffDataByIndex = function(unit, i)
        local b = me.buffs[i]
        if not b then return nil end
        return { name = b.name, expirationTime = b.expire or 0, sourceUnit = b.mine and "player" or "party1", spellId = b.id or 1 }
    end,
    GetDebuffDataByIndex = function(unit, i)
        local d = me.debuffs[i]
        if not d then return nil end
        return { name = d.name, expirationTime = d.expire or 0, dispelName = d.kind, spellId = d.id or 2 }
    end,
}
C_LossOfControl = {
    GetActiveLossOfControlDataCount = function() return #me.loc end,
    GetActiveLossOfControlData = function(i) return { locType = me.loc[i] } end,
}
C_NamePlate = {
    GetNamePlates = function()
        if me.plateIsPlayer then return { { namePlateUnitToken = "nameplate1" } } end
        return {}
    end,
}
C_Texture = { GetAtlasInfo = function(name) if name:find("Flipbook") then return { width = 1, height = 1 } end return nil end }

-- Spellbook: a level-70 priest with a few racials
local BOOK = {
    { "Inner Fire", 10952 }, { "Power Word: Fortitude", 25389 }, { "Power Word: Shield", 25218 },
    { "Renew", 25222 }, { "Flash Heal", 25235 }, { "Desperate Prayer", 25437 }, { "Psychic Scream", 10890 },
    { "Fade", 25429 }, { "Dispel Magic", 988 }, { "Shadow Protection", 25433 }, { "Fear Ward", 6346 },
    { "Smite", 25364 }, { "Mind Blast", 25375 },
}
function GetNumSpellTabs() return 1 end
function GetSpellTabInfo() return "General", "", 0, #BOOK end
function GetSpellBookItemName(i, book) local e = BOOK[i]; if e then return e[1], "", e[2] end end
function IsPassiveSpell() return false end
function HasPetSpells() return nil end
local NAME_BY_ID = {}
for _, e in ipairs(BOOK) do NAME_BY_ID[e[2]] = e[1] end
function GetSpellInfo(id)
    if type(id) == "number" then return NAME_BY_ID[id], nil, "icon", 0, 0, 0, id end
    for _, e in ipairs(BOOK) do if e[1] == id then return e[1], nil, "icon", 0, 0, 0, e[2] end end
    return nil
end
local cooldowns = {}       -- name -> remaining seconds from "now"
function GetSpellCooldown(name)
    local cd = cooldowns[name]
    if cd and cd > 0 then return GetTime(), cd, 1 end
    return 0, 0, 1
end
function IsUsableSpell() return true, false end

-- Items
local ITEM_NAMES = { [22105] = "Master Healthstone", [28100] = "Volatile Healing Potion", [21566] = "Heavy Netherweave Bandage", [28235] = "Medallion of the Alliance" }
C_Item = {
    GetItemNameByID = function(id) return ITEM_NAMES[id] end,
    GetItemCooldown = function() return 0, 0 end,
    GetItemCount = function() return 3 end,
    IsUsableItem = function() return true end,
}

-- Action bars: twelve buttons on the main bar, the rest empty
local slots = {}           -- slot -> { "spell"|"item", id }
function HasAction(slot) return slots[slot] ~= nil end
function GetActionInfo(slot) local s = slots[slot]; if s then return s[1], s[2] end end
function GetMacroSpell() return nil end
function GetMacroItem() return nil end

for i = 1, 12 do
    local b = CreateFrame("CheckButton", "ActionButton" .. i)
    b.action = i
    b.GetSize = function() return 36, 36 end
    b.__shown = true
end
for _, prefix in ipairs({ "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton", "MultiBarLeftButton" }) do
    for i = 1, 12 do
        local b = CreateFrame("CheckButton", prefix .. i)
        b.action = 12 + i
        b.GetSize = function() return 36, 36 end
    end
end

-- Animations: groups and animations are plain widgets; IsPlaying tracks Play/Stop
local BaseCreateFrame = CreateFrame
local animCalls = { flipbooks = 0 }
local function AnimGroup()
    local g = NewWidget("AnimationGroup")
    g.__playing = false
    g.Play = function(s) s.__playing = true end
    g.Stop = function(s) s.__playing = false end
    g.IsPlaying = function(s) return s.__playing end
    g.CreateAnimation = function(s, kind)
        local a = NewWidget("Animation")
        if kind == "FlipBook" then animCalls.flipbooks = animCalls.flipbooks + 1 end
        return a
    end
    return g
end
local baseIndex = WidgetMT.__index
WidgetMT.__index = function(self, key)
    if key == "CreateAnimationGroup" then
        local fn = function() return AnimGroup() end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetAtlas" then
        local fn = function(s, name) s.__atlas = name end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetAlpha" then
        local fn = function(s, a) s.__alpha = a end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetAlpha" then
        local fn = function(s) return s.__alpha or 1 end
        rawset(self, key, fn)
        return fn
    end
    return baseIndex(self, key)
end

-- Combat log
local cleu = {}
function CombatLogGetCurrentEventInfo() return unpack(cleu, 1, 24) end
function hooksecurefunc(tbl, name, fn)
    local orig = tbl[name]
    tbl[name] = function(...)
        if orig then orig(...) end
        fn(...)
    end
end
GameTooltip.SetAction = function() end
GameTooltip.Show = function() end

local played = {}
function PlaySound(id) played[#played + 1] = id return true end
function PlaySoundFile(file) played[#played + 1] = file return true end
SOUNDKIT.RAID_WARNING = 8959

-- ===========================================================================
-- Load
-- ===========================================================================

local function Load(path)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    chunk()
end

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
Load(ADDONS .. "/Commander_Advisor/CommanderAdvisorData.lua")
Load(ADDONS .. "/Commander_Advisor/CommanderAdvisorEngine.lua")
Load(ADDONS .. "/Commander_Advisor/CommanderAdvisorDB.lua")
Load(ADDONS .. "/Commander_Advisor/CommanderAdvisor.lua")

local function Fire(event, ...)
    for _, f in ipairs(eventRegistry[event] or {}) do
        local handler = f.__scripts.OnEvent
        if handler then handler(f, event, ...) end
    end
end
local function FireCleu(...)
    cleu = { ... }
    Fire("COMBAT_LOG_EVENT_UNFILTERED")
end
local function Advance(seconds)
    now = now + seconds
end
-- One tick of every ticker; the Advisor's own is the 0.2s one
local function Tick(times, dt)
    for _ = 1, (times or 1) do
        Advance(dt or 0.2)
        RunTickers()
    end
end
local function Glow(i)
    local b = _G["ActionButton" .. i]
    for _, f in ipairs(frames) do
        if f.__parent == b or f.__parentFrame == b then return f end
    end
end
-- CreateFrame in the shared mock does not record the parent; find our
-- holders by the tier field the client writes on them, via the button's
-- children we can recognise: we track them at creation instead.
local holdersByButton = {}
CreateFrame = function(frameType, name, parent, template)
    local f = BaseCreateFrame(frameType, name, parent, template)
    if parent and type(parent) == "table" and parent.__name and parent.__name:find("Button%d+$") then
        holdersByButton[parent.__name] = f
    end
    return f
end

-- Login
Fire("ADDON_LOADED", "Commander_Advisor")
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD")
CHECK(#harnessFailedErrors == 0, "login raised no errors", harnessFailedErrors[1])
CHECK(CommanderAdvisorDB.EnableAdvisor == true, "defaults applied")
CHECK(CommanderAdvisorDB.Caution == "CONSERVATIVE", "ships conservative")

local function Holder(i) return holdersByButton["ActionButton" .. i] end
CHECK(Holder(1) ~= nil, "a glow holder hangs on every button")
CHECK(Holder(1).loop ~= nil and Holder(1).loop.__atlas == "UI-HUD-ActionBar-Proc-Loop-Flipbook", "the proc loop atlas is used")
CHECK(animCalls.flipbooks >= 60, "flipbook animations were created", animCalls.flipbooks)

-- The bars: Inner Fire on 1, PWS on 2, Renew on 3, Flash Heal on 4, healthstone on 5, trinket on 6, Smite on 7
slots[1] = { "spell", 10952 }
slots[2] = { "spell", 25218 }
slots[3] = { "spell", 25222 }
slots[4] = { "spell", 25235 }
slots[5] = { "item", 22105 }
slots[6] = { "item", 28235 }
slots[7] = { "spell", 25364 }
Fire("ACTIONBAR_SLOT_CHANGED", 1)

-- ===========================================================================
-- Out of combat: a missing Inner Fire, after the grace and the rise
-- ===========================================================================
me.buffs = { { name = "Power Word: Fortitude", mine = true, expire = 0 } }
Tick(1)
CHECK(not Holder(1).tier, "missing Inner Fire: quiet inside the missing grace")
Tick(25)   -- 5s: grace 3s + rise 1s well past
CHECK(Holder(1).tier == 1, "missing Inner Fire glows low", Holder(1).tier)
CHECK(Holder(1).__shown, "the holder is shown")
CHECK(Holder(1).loopAnim.__playing, "the loop is playing")
CHECK(Holder(1).pips[1].__shown and not Holder(1).pips[2].__shown, "one pip at low")
CHECK(not Holder(2).tier, "PWS quiet out of combat at full health")
CHECK(not Holder(7).tier, "Smite never glows")
CHECK(#played == 0, "low tier ships silent")

-- Cast it: the glow drops on the SENT event, before the aura arrives
Fire("UNIT_SPELLCAST_SENT", "player", "player", "cast-1", 10952)
CHECK(not Holder(1).tier, "casting Inner Fire drops its glow at once")
me.buffs[#me.buffs + 1] = { name = "Inner Fire", mine = true, expire = 0 }
Tick(30)
CHECK(not Holder(1).tier, "Inner Fire up: stays quiet")

-- Tooltip on a quiet button says nothing
GameTooltip.__lines = {}
GameTooltip.SetAction(GameTooltip, 1)
CHECK(#GameTooltip.__lines == 0, "no tooltip lines on a quiet button")

-- ===========================================================================
-- Combat: hit hard, the shield lights high, with a sound
-- ===========================================================================
me.combat = true
Fire("PLAYER_REGEN_DISABLED")
me.hp = 2400
-- three melee hits inside two seconds from one warrior
FireCleu(now, "SWING_DAMAGE", false, "Player-0-ENEMY", "Enemy", 0, 0, "Player-0-ME", "Devinp", 0, 0, 1500, 0, 1, 0)
Advance(0.5)
FireCleu(now, "SWING_DAMAGE", false, "Player-0-ENEMY", "Enemy", 0, 0, "Player-0-ME", "Devinp", 0, 0, 1500, 0, 1, 0)
Advance(0.5)
FireCleu(now, "SWING_DAMAGE", false, "Player-0-ENEMY", "Enemy", 0, 0, "Player-0-ME", "Devinp", 0, 0, 1500, 0, 1, 0)
Tick(1)
CHECK(Holder(2).tier == 3, "PWS glows high at 30% under a melee burst", Holder(2).tier)
CHECK(Holder(2).start and Holder(2).start.__shown, "the birth burst played on the new high signal")
CHECK(Holder(2).pips[3].__shown, "three pips at high")
CHECK(#played == 1 and played[1] == 8959, "the high sound played once", played[1])
-- Conservative caution scales the 30% rungs to 24%: at 30% the shield's
-- own 40% rung is high, the potion and the heal are medium
CHECK(not Holder(5).tier and not Holder(4).tier, "medium signals wait their 0.4s rise")
Tick(3)
CHECK(Holder(5).tier == 2, "the healthstone glows medium at 30% under conservative caution", Holder(5).tier)
CHECK(Holder(4).tier == 2, "Flash Heal: medium at 30% under conservative caution", Holder(4).tier)
CHECK(not Holder(3).tier, "Renew: fourth in line, cut by the cap of three", Holder(3).tier)
local litCount = 0
for i = 1, 12 do if Holder(i).tier then litCount = litCount + 1 end end
CHECK(litCount <= CommanderAdvisorDB.MaxSignals, "no more than the cap glow at once", litCount)
Tick(5)
CHECK(#played == 1, "the sound is not repeated while the signal holds")

-- Tooltip carries the reason
GameTooltip.__lines = {}
GameTooltip.SetAction(GameTooltip, 2)
CHECK(#GameTooltip.__lines >= 2, "tooltip lines on a glowing button", #GameTooltip.__lines)
local found = false
for _, line in ipairs(GameTooltip.__lines) do if tostring(line):find("health 30%%") then found = true end end
CHECK(found, "tooltip names the health", GameTooltip.__lines[3])

-- Weakened Soul blocks the shield; the glow is gone the same tick
me.debuffs = { { name = "Weakened Soul", kind = "", expire = now + 15 } }
Tick(1)
CHECK(not Holder(2).tier, "Weakened Soul drops the shield glow at once")
me.debuffs = {}

-- Report prints without error and names the signals
printLog = {}
CommanderAdvisor_Report()
CHECK(#printLog > 5, "report printed", #printLog)
local sawHigh = false
for _, line in ipairs(printLog) do if line:find("High") then sawHigh = true end end
CHECK(sawHigh, "report names a high signal")

-- Stunned: only the trinket
me.loc = { "STUN" }
Tick(2)
CHECK(Holder(6).tier == 3, "stunned at 30%: the trinket glows high", Holder(6).tier)
CHECK(not Holder(2).tier and not Holder(4).tier, "stunned: spells are quiet")
me.loc = {}

-- Nothing hits you for a while: the emergency lapses
Tick(30)
CHECK(not Holder(2).tier, "quiet once nothing has hit you for seconds")
CHECK(not Holder(5).tier, "healthstone quiet once nothing is hitting you")

-- A fear being cast at you lights Fear Ward high (on bar 8)
slots[8] = { "spell", 6346 }
Fire("ACTIONBAR_SLOT_CHANGED", 8)
me.plateTargetsMe, me.plateCast = true, "Fear"
Fire("UNIT_SPELLCAST_START", "nameplate1", "cast-9", 5782)
Tick(1)
CHECK(Holder(8).tier == 3, "Fear Ward glows high while Fear is cast at you", Holder(8).tier)
Fire("UNIT_SPELLCAST_INTERRUPTED", "nameplate1", "cast-9", 5782)
Tick(8)
CHECK(not Holder(8).tier, "... and clears when the cast stops")

-- ===========================================================================
-- Settings: the page, the rule dropdowns, a colour change, the switch
-- ===========================================================================
local panel
for _, cat in ipairs(categories) do
    if cat.__title == "Advisor" then panel = cat.__panel end
end
CHECK(panel ~= nil, "the Advisor settings page registered")
if panel then
    panel:Refresh()
    CHECK(#harnessFailedErrors == 0, "settings page refreshed clean", harnessFailedErrors[1])
end
-- every priest rule got a dropdown: count menu inits with a rule mode getter
local ruleDropdowns = 0
for frame, init in pairs(dropdownInits) do
    ToggleDropDownMenu(1, nil, frame)
    for _, info in ipairs(menuCaptured) do
        if info.text == "As written" then ruleDropdowns = ruleDropdowns + 1 break end
    end
end
local priestRules = #CommanderAdvisor_Data.RulesForClass("PRIEST")
CHECK(ruleDropdowns == priestRules, "one mode dropdown per priest rule", ruleDropdowns .. " vs " .. priestRules)

-- Change the high colour and the layout: repaint keeps a lit button lit
me.combat, me.hp = true, 2400
FireCleu(now, "SWING_DAMAGE", false, "Player-0-ENEMY", "Enemy", 0, 0, "Player-0-ME", "Devinp", 0, 0, 1500, 0, 1, 0)
Tick(1)
CHECK(Holder(2).tier == 3, "back under fire: shield high")
CommanderAdvisorDB.Tier3Color = "CYAN"
CommanderAdvisorDB.GlowStyle = "BORDER"
Commander.Notify(COMMANDER_ADVISOR_EVENTS.UPDATE)
CHECK(Holder(2).tier == 3, "still lit after a settings change")
CHECK(Holder(2).border.__shown and not Holder(2).loop.__shown, "border style swaps the art")
CHECK(Holder(2).border.__color[3] == 1.0 and Holder(2).border.__color[1] == 0.3, "new colour applied", Holder(2).border.__color[1])

-- OFF clears everything
CommanderAdvisorDB.EnableAdvisor = false
Commander.Notify(COMMANDER_ADVISOR_EVENTS.UPDATE)
CHECK(not Holder(2).tier, "the master switch clears the glow")
Tick(2)
CHECK(not Holder(2).tier, "... and it stays clear")
CommanderAdvisorDB.EnableAdvisor = true
Commander.Notify(COMMANDER_ADVISOR_EVENTS.UPDATE)

-- Test lights three buttons
printLog = {}
CommanderAdvisor_Test()
local lit = 0
for i = 1, 12 do if Holder(i).tier then lit = lit + 1 end end
CHECK(lit == 3, "test lights three buttons", lit)
CHECK(Holder(1).tier == 1 and Holder(2).tier == 2 and Holder(3).tier == 3, "... low, medium, high in order")

CHECK(#harnessFailedErrors == 0, "no errors were swallowed anywhere", harnessFailedErrors[1])
io.write(string.format("%d checks, %d failed\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
