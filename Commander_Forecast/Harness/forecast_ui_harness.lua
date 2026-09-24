-- Commander Forecast UI smoke harness (luajit).
--
-- Loads the REAL shared framework (CommanderSettingsUI.lua, CommanderEvents.lua)
-- plus all three Commander_Forecast files under a permissive WoW mock, then
-- drives login, the settings page, the repaint loop over mocked action
-- buttons, the combat log, and both slash subcommands. Catches nil-global
-- calls, bad signatures, and template/font traps without a client.
--
-- Mock copied from Commander_Meters/Harness/meters_ui_harness.lua and extended
-- with the action-bar, character-sheet and tooltip-scanning surfaces this
-- module reads.
--
-- Run:  /opt/homebrew/bin/luajit forecast_ui_harness.lua

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
-- Forecast-specific mock: character sheet, action bars, tooltip scanning
-- ===========================================================================

STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
NumberFontNormalSmall = NewWidget("Font")
CR_HIT_SPELL, CR_HIT_MELEE = 20, 6

function hooksecurefunc(target, name, post)
    local original = target[name]
    target[name] = function(...)
        local a, b, c = original(...)
        post(...)
        return a, b, c
    end
end

-- Character sheet
local sheet = {
    level = 70,
    spellPower = 500,
    healPower = 800,
    spellCrit = 20,
    meleeCrit = 25,
    weaponMin = 150, weaponMax = 250,
    hitSpell = 0, hitMelee = 0,
}
function GetSpellBonusDamage(school) return school == 1 and 0 or sheet.spellPower end
function GetSpellBonusHealing() return sheet.healPower end
function GetSpellCritChance(school) return school == 1 and 0 or sheet.spellCrit end
function GetCritChance() return sheet.meleeCrit end
function UnitDamage() return sheet.weaponMin, sheet.weaponMax, 0, 0, 0, 0, 100 end
function GetCombatRatingBonus(rating)
    return rating == CR_HIT_SPELL and sheet.hitSpell or sheet.hitMelee
end

-- Target
local targetState = { exists = true, name = "Training Dummy", level = 73, isPlayer = false, guid = "Creature-0-DUMMY" }
function UnitLevel(unit)
    if unit == "player" then return sheet.level end
    if unit == "target" and targetState.exists then return targetState.level end
    return nil
end
function UnitIsPlayer(unit) return unit == "target" and targetState.isPlayer or false end
function UnitCanAttack() return true end

-- The mock in the shared header answers only "player"; Forecast asks about the
-- target as well, and about the token it is holding on a combat-log victim.
UnitExists = function(unit)
    if unit == "player" then return true end
    if unit == "target" then return targetState.exists end
    return false
end
UnitName = function(unit)
    if unit == "player" then return "Devinp" end
    if unit == "target" and targetState.exists then return targetState.name end
    return nil
end
UnitGUID = function(unit)
    if unit == "player" then return "Player-0-ME" end
    if unit == "target" and targetState.exists then return targetState.guid end
    return nil
end

-- Spellbook. Cast time is the 4th return and the spell ID the 7th, exactly as
-- the real GetSpellInfo hands them back.
local SPELLS = {
    [133] = { name = "Fireball", cast = 3500, mana = 465, lines = {
        "Fireball", "Rank 13", "465 Mana", "35 yd range", "3.5 sec cast",
        "Hurls a fiery ball that causes 649 to 821 Fire damage and an additional 84 Fire damage over 8 sec.",
    } },
    [172] = { name = "Corruption", cast = 0, mana = 370, lines = {
        "Corruption", "Rank 8", "370 Mana", "30 yd range", "Instant",
        "Corrupts the target, causing 900 Shadow damage over 18 sec.",
    } },
    [2061] = { name = "Flash Heal", cast = 1500, mana = 510, lines = {
        "Flash Heal", "Rank 9", "510 Mana", "40 yd range", "1.5 sec cast",
        "Heals a friendly target for 890 to 1034.",
    } },
    [30455] = { name = "Ice Lance", cast = 0, mana = 150, lines = {
        "Ice Lance", "Rank 1", "150 Mana", "30 yd range", "Instant",
        "Deals 161 to 187 Frost damage to an enemy target.  Causes triple damage against Frozen targets.",
    } },
    [11426] = { name = "Ice Barrier", cast = 0, mana = 480, lines = {
        "Ice Barrier", "Rank 6", "480 Mana", "Instant",
        "Instantly shields you, absorbing 1075 damage.  Lasts 1 min.  While the shield holds, spells will not be interrupted.",
    } },
    [6143] = { name = "Frost Ward", cast = 0, mana = 320, lines = {
        "Frost Ward", "Rank 6", "320 Mana", "Instant",
        "Absorbs 675 Frost damage.  Lasts 30 sec.",
    } },
    [7386] = { name = "Sunder Armor", cast = 0, mana = 0, lines = {
        "Sunder Armor", "Rank 5", "15 Rage", "Melee Range", "Instant",
        "Reduces an enemy target's armor by 1400 for 30 sec.",
    } },
}
local ITEMS = {
    [22105] = { lines = { "Master Healthstone", "Use: Restores 2080 health." } },
}

function GetSpellInfo(id)
    local spell = SPELLS[id]
    if not spell then return nil end
    return spell.name, "", "Interface\\Icons\\Icon" .. id, spell.cast, 0, 40, id
end
function GetSpellLink(id) return SPELLS[id] and ("|Hspell:" .. id .. "|h") or nil end
local textArrived = { [30455] = false }
local loadRequests = {}
C_Spell = {
    IsSpellDataCached = function(id) return textArrived[id] ~= false end,
    RequestLoadSpellData = function(id) loadRequests[#loadRequests + 1] = id end,
    GetSpellPowerCost = function(id)
        local spell = SPELLS[id]
        if not spell then return nil end
        return { { type = 0, cost = spell.mana } }
    end,
}

-- Tooltip scanning: a real fill, real line count, real TextLeftN globals.
local BaseCreateFrame = CreateFrame
function CreateFrame(frameType, name, parent, template)
    local f = BaseCreateFrame(frameType, name, parent, template)
    f.__parentFrame = parent
    if frameType == "GameTooltip" and name then
        local lineWidgets = {}
        for i = 1, 16 do
            local widget = NewWidget("FontString", name .. "TextLeft" .. i)
            _G[name .. "TextLeft" .. i] = widget
            lineWidgets[i] = widget
        end
        f.__count = 0
        f.SetOwner = function() end
        f.ClearLines = function(self)
            self.__count = 0
            for _, widget in ipairs(lineWidgets) do widget.__text = nil end
        end
        f.NumLines = function(self) return self.__count end
        local function fill(self, lines)
            self:ClearLines()
            if not lines then return end
            for i, text in ipairs(lines) do lineWidgets[i].__text = text end
            self.__count = #lines
        end
        f.SetSpellByID = function(self, id)
            if textArrived[id] == false then
                -- The name and nothing under it: what the client hands back
                -- before the spell's text has been sent
                fill(self, { SPELLS[id].name })
                return
            end
            fill(self, SPELLS[id] and SPELLS[id].lines)
        end
        f.SetItemByID = function(self, id) fill(self, ITEMS[id] and ITEMS[id].lines) end
        f.SetHyperlink = function(self, link)
            local id = tonumber(tostring(link):match("spell:(%d+)"))
            fill(self, id and SPELLS[id] and SPELLS[id].lines)
        end
    end
    return f
end

-- Action bars
local slots = {}
function HasAction(slot) return slots[slot] ~= nil end
function GetActionInfo(slot)
    local action = slots[slot]
    if not action then return nil end
    return action[1], action[2], nil
end
function GetMacroSpell(id) return id == 1 and 133 or nil end

for index = 1, 12 do
    local button = CreateFrame("CheckButton", "ActionButton" .. index)
    button.action = index
end
slots[1] = { "spell", 133 }     -- Fireball
slots[2] = { "spell", 172 }     -- Corruption
slots[3] = { "spell", 2061 }    -- Flash Heal
slots[4] = { "spell", 7386 }    -- Sunder Armor: no readable output
slots[5] = { "item", 22105 }    -- Master Healthstone
slots[6] = { "macro", 1 }       -- a macro that resolves to Fireball
slots[7] = { "spell", 30455 }   -- Ice Lance: text arrives late, triples on Frozen
slots[8] = { "spell", 11426 }   -- Ice Barrier: description begins "Instantly"
slots[9] = { "spell", 6143 }    -- Frost Ward: an absorb, not damage

-- Combat log
local cleu = {}
function CombatLogGetCurrentEventInfo() return unpack(cleu, 1, cleu.n) end

-- ===========================================================================
-- Load the real framework + addon
-- ===========================================================================

local function Load(path)
    local chunk = assert(loadfile(path))
    chunk()
end

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
Load(ADDONS .. "/Commander_Forecast/CommanderForecastDB.lua")
Load(ADDONS .. "/Commander_Forecast/CommanderForecastModel.lua")
Load(ADDONS .. "/Commander_Forecast/CommanderForecast.lua")

local function Fire(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    for _, frame in ipairs(list) do
        local handler = frame.__scripts.OnEvent
        if handler then handler(frame, event, ...) end
    end
end

Fire("ADDON_LOADED", "Commander_Forecast")
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD")

CHECK(#harnessFailedErrors == 0, "login clean", harnessFailedErrors[1])
CHECK(CommanderForecastDB.EnableForecast == true, "defaults applied")
CHECK(CommanderForecastDB.Metric == "TOTAL", "metric default")
CHECK(SlashCmdList.COMMANDERUI_FORECAST ~= nil, "slash registered")
CHECK(_G.SLASH_COMMANDERUI_FORECAST1 == "/cforecast"
    and _G.SLASH_COMMANDERUI_FORECAST2 == "/cfc", "slash aliases")

do
    local found
    for _, info in ipairs(Commander.GetModules()) do
        if info.key == "Forecast" then found = info end
    end
    CHECK(found ~= nil, "module in the Commander registry")
    CHECK(found and found.slash == "/cforecast", "registry slash")
end

-- ===========================================================================
-- The numbers on the buttons
-- ===========================================================================

local function ButtonText(index)
    local button = _G["ActionButton" .. index]
    for _, fs in ipairs(allFontStrings) do
        if fs.__parent and fs.__parent.__parentFrame == button then return fs end
    end
    return nil
end

local function Refresh()
    Commander.Notify(COMMANDER_FORECAST_EVENTS.UPDATE)
end

local function FireCleu(...)
    cleu = { n = select("#", ...), ... }
    Fire("COMBAT_LOG_EVENT_UNFILTERED")
end

CHECK(ButtonText(1) ~= nil, "an overlay was hung on ActionButton1")

do
    local fireball = ButtonText(1)
    CHECK(fireball:GetText() ~= "", "Fireball carries a number", fireball:GetText())
    CHECK(ButtonText(2):GetText() ~= "", "Corruption carries a number", ButtonText(2):GetText())
    CHECK(ButtonText(3):GetText() ~= "", "Flash Heal carries a number", ButtonText(3):GetText())
    CHECK(ButtonText(4):GetText() == "", "Sunder Armor carries none — nothing to say")
    CHECK(ButtonText(5):GetText() == "2.1k",
        "the healthstone is its printed 2080 flat — no spell power, no crit",
        ButtonText(5):GetText())
    CHECK(ButtonText(6):GetText() == fireball:GetText(),
        "a macro that resolves to Fireball shows Fireball's number")

    if os.getenv("FORECAST_DUMP") then
        for index = 1, 6 do
            io.write(string.format("  button %d -> %q\n", index, ButtonText(index):GetText()))
        end
    end
end

-- SetTextColor is a generic no-op in the shared mock; capture it here so the
-- source coloring can actually be asserted.
for _, fs in ipairs(allFontStrings) do
    fs.SetTextColor = function(self, r, g, b) self.__rgb = { r, g, b } end
end
Refresh()

do
    local fireball = ButtonText(1)
    CHECK(fireball.__rgb and fireball.__rgb[3] == 1.00 and fireball.__rgb[1] < 0.9,
        "a modeled number is drawn in the modeled color",
        fireball.__rgb and table.concat(fireball.__rgb, ","))
end

local modeledTotal = ButtonText(1):GetText()

-- ===========================================================================
-- The mage bar from the field (2026-09-10)
-- ===========================================================================

do
    CHECK(ButtonText(8):GetText() ~= "", "Ice Barrier carries a number", ButtonText(8):GetText())
    -- 675 + 500 * 0.1 = 725: no crit, no cast-window coefficient.
    CHECK(ButtonText(9):GetText() == "725", "Frost Ward is 725, not a crit-rolled 1.5k",
        ButtonText(9):GetText())

    -- Ice Lance's text has not arrived. No number, but ALSO no permanent
    -- "nothing to say" — the data was requested and the scan will retry.
    CHECK(ButtonText(7):GetText() == "", "Ice Lance is blank while its text is missing")
    CHECK(#loadRequests > 0 and loadRequests[1] == 30455, "and its data was requested", loadRequests[1])

    textArrived[30455] = true
    Fire("SPELL_TEXT_UPDATE", 30455)
    for _ = 1, 2 do RunTickers() end
    local lance = ButtonText(7):GetText()
    CHECK(lance ~= "", "once the text arrives Ice Lance gets its number", lance)

    -- A Frost Nova from a DIFFERENT mage lands on the target: Ice Lance triples.
    FireCleu(now, "SPELL_AURA_APPLIED", false, "Player-0-OTHERMAGE", "Frostina", 0, 0,
        targetState.guid, targetState.name, 0, 0, 122, "Frost Nova", 16, "DEBUFF")
    local frozenLance = ButtonText(7):GetText()
    CHECK(frozenLance ~= lance, "a Frozen target flexes Ice Lance immediately", frozenLance)
    do
        local function num(t) local v, k = t:match("([%d%.]+)(k?)"); v = tonumber(v); return k == "k" and v * 1000 or v end
        CHECK(num(frozenLance) > num(lance) * 2.5, "and by about three times", frozenLance .. " vs " .. lance)
    end
    CHECK(ButtonText(1):GetText() == modeledTotal, "Fireball is untouched by the freeze")

    -- Our own Ice Lance lands INTO the frozen target and breaks the freeze:
    -- the hit files under the frozen variant, because the damage event comes
    -- before the break.
    FireCleu(now, "SPELL_DAMAGE", false, "Player-0-ME", "Devinp", 0, 0,
        targetState.guid, targetState.name, 0, 0,
        30455, "Ice Lance", 16, 900, 0, 16, 0, 0, 0, false)
    FireCleu(now, "SPELL_AURA_BROKEN", false, "Player-0-ME", "Devinp", 0, 0,
        targetState.guid, targetState.name, 0, 0, 122, "Frost Nova", 16, "DEBUFF")
    local spell = CommanderForecastLog.spells[30455]
    local frozenBucket
    for key in pairs(spell) do if type(key) == "string" and key:find("f$") then frozenBucket = key end end
    CHECK(frozenBucket ~= nil, "the frozen hit was filed in a frozen-variant bucket")
    CHECK(ButtonText(7):GetText() == lance, "and the break drops Ice Lance back to its unfrozen number",
        ButtonText(7):GetText())

    -- Tooltip says why.
    FireCleu(now, "SPELL_AURA_APPLIED", false, "Player-0-OTHERMAGE", "Frostina", 0, 0,
        targetState.guid, targetState.name, 0, 0, 122, "Frost Nova", 16, "DEBUFF")
    GameTooltip.__lines = {}
    GameTooltip:SetAction(7)
    CHECK(table.concat(GameTooltip.__lines, "\n"):find("Frozen"), "the breakdown names the Frozen multiplier")
    FireCleu(now, "SPELL_AURA_REMOVED", false, "Player-0-OTHERMAGE", "Frostina", 0, 0,
        targetState.guid, targetState.name, 0, 0, 122, "Frost Nova", 16, "DEBUFF")
    CHECK(#harnessFailedErrors == 0, "mage bar clean", harnessFailedErrors[1])
end

-- ===========================================================================
-- Metrics
-- ===========================================================================

CommanderForecastDB.Metric = "PER_SECOND"
Refresh()
local perSecond = ButtonText(1):GetText()
CHECK(perSecond ~= modeledTotal, "per second is a different number", perSecond)

CommanderForecastDB.Metric = "PER_MANA"
Refresh()
CHECK(ButtonText(1):GetText() ~= perSecond, "per mana is a different number again",
    ButtonText(1):GetText())
CHECK(ButtonText(4):GetText() == "", "a rage ability has no per-mana number")

CommanderForecastDB.Metric = "TOTAL"
Refresh()
CHECK(ButtonText(1):GetText() == modeledTotal, "and switching back restores the first number")

-- ===========================================================================
-- Learning from the combat log
-- ===========================================================================

-- ts, subevent, hideCaster, srcGUID, srcName, srcFlags, srcRaidFlags,
-- dstGUID, dstName, dstFlags, dstRaidFlags, spellId, spellName, school,
-- amount, overkill, school, resisted, blocked, absorbed, critical
local function SpellDamage(spellID, amount, crit)
    FireCleu(now, "SPELL_DAMAGE", false, "Player-0-ME", "Devinp", 0, 0,
        targetState.guid, targetState.name, 0, 0,
        spellID, "Fireball", 4, amount, 0, 4, 0, 0, 0, crit or false)
end

for _ = 1, 6 do SpellDamage(133, 4000, false) end
Refresh()

do
    local fireball = ButtonText(1)
    CHECK(fireball:GetText() ~= modeledTotal,
        "six landed casts move Fireball off its modeled number", fireball:GetText())
    CHECK(fireball.__rgb and fireball.__rgb[1] == 1 and fireball.__rgb[3] == 1,
        "and repaint it in the measured color",
        fireball.__rgb and table.concat(fireball.__rgb, ","))
    CHECK(#harnessFailedErrors == 0, "combat log clean", harnessFailedErrors[1])
end

-- A DoT: ticks counted between the aura landing and the aura leaving.
do
    local function Periodic(spellID, amount)
        FireCleu(now, "SPELL_PERIODIC_DAMAGE", false, "Player-0-ME", "Devinp", 0, 0,
            targetState.guid, targetState.name, 0, 0,
            spellID, "Corruption", 32, amount, 0, 32, 0, 0, 0, false)
    end
    local function Aura(subevent, spellID)
        FireCleu(now, subevent, false, "Player-0-ME", "Devinp", 0, 0,
            targetState.guid, targetState.name, 0, 0, spellID, "Corruption", 32, "DEBUFF")
    end
    for _ = 1, 3 do
        Aura("SPELL_AURA_APPLIED", 172)
        for _ = 1, 6 do Periodic(172, 250) end
        Aura("SPELL_AURA_REMOVED", 172)
    end
    Refresh()
    CHECK(ButtonText(2):GetText() == "1.5k",
        "Corruption reads six measured ticks of 250", ButtonText(2):GetText())
end

-- Misses are counted and drag the average down.
do
    local before = ButtonText(1):GetText()
    for _ = 1, 20 do
        FireCleu(now, "SPELL_MISSED", false, "Player-0-ME", "Devinp", 0, 0,
            targetState.guid, targetState.name, 0, 0, 133, "Fireball", 4, "RESIST")
    end
    Refresh()
    CHECK(ButtonText(1):GetText() ~= before,
        "twenty resists change the expected average", ButtonText(1):GetText())
end

-- A different target level is a different bucket, and the fallback still
-- answers with what we know.
do
    targetState.level = 60
    Fire("PLAYER_TARGET_CHANGED")
    CHECK(ButtonText(1):GetText() ~= "", "a fresh bucket still shows a number",
        ButtonText(1):GetText())
    targetState.level = 73
    Fire("PLAYER_TARGET_CHANGED")
end

-- ===========================================================================
-- Switches
-- ===========================================================================

do
    targetState.exists = false
    CommanderForecastDB.RequireTarget = true
    Fire("PLAYER_TARGET_CHANGED")
    CHECK(ButtonText(1):GetText() == "", "Only With A Target clears the bars")
    targetState.exists = true
    CommanderForecastDB.RequireTarget = false
    Fire("PLAYER_TARGET_CHANGED")
    CHECK(ButtonText(1):GetText() ~= "", "and a target brings them back")
end

do
    CommanderForecastDB.Source = "MODEL"
    Refresh()
    CHECK(ButtonText(1):GetText() == modeledTotal,
        "model-only ignores everything learned", ButtonText(1):GetText())
    CommanderForecastDB.Source = "AUTO"
    Refresh()
end

do
    CommanderForecastDB.ShowOnItems = false
    Refresh()
    CHECK(ButtonText(5):GetText() == "", "items can be switched off")
    CommanderForecastDB.ShowOnItems = true
    Refresh()
end

do
    CommanderForecastDB.EnableForecast = false
    Refresh()
    CHECK(ButtonText(1):GetText() == "", "the master switch clears every number")
    CommanderForecastDB.EnableForecast = true
    Refresh()
    CHECK(ButtonText(1):GetText() ~= "", "and brings them back")
end

do
    CommanderForecastDB.Anchor = "TOP"
    CommanderForecastDB.FontSize = 16
    Refresh()
    local font = ButtonText(1).__font
    CHECK(font and font[2] == 16, "font size follows the slider", font and font[2])
    CHECK(font and font[3] == "OUTLINE", "and uses a legal flag string")
    CommanderForecastDB.Anchor = "BOTTOM"
    Refresh()
end

-- ===========================================================================
-- Tooltip breakdown
-- ===========================================================================

do
    GameTooltip.__lines = {}
    GameTooltip:SetAction(1)
    CHECK(#GameTooltip.__lines > 0, "the action tooltip gains a breakdown", #GameTooltip.__lines)
    local joined = table.concat(GameTooltip.__lines, "\n")
    CHECK(joined:find("Forecast"), "and it is labelled")
    CHECK(joined:find("Samples"), "a measured spell shows its sample count", joined)

    GameTooltip.__lines = {}
    GameTooltip:SetAction(4)
    CHECK(#GameTooltip.__lines == 0, "a spell with no forecast adds no lines")

    CommanderForecastDB.ShowTooltipBreakdown = false
    GameTooltip.__lines = {}
    GameTooltip:SetAction(1)
    CHECK(#GameTooltip.__lines == 0, "and the breakdown can be switched off")
    CommanderForecastDB.ShowTooltipBreakdown = true
end

-- ===========================================================================
-- Slash surface
-- ===========================================================================

do
    printLog = {}
    SlashCmdList.COMMANDERUI_FORECAST("report")
    local joined = table.concat(printLog, "\n")
    CHECK(joined:find("Fireball"), "report names a learned spell", joined)

    printLog = {}
    SlashCmdList.COMMANDERUI_FORECAST("forget")
    CHECK(next(CommanderForecastLog.spells) == nil, "forget empties the log")
    Refresh()
    CHECK(ButtonText(1):GetText() == modeledTotal,
        "and the model takes back over", ButtonText(1):GetText())

    printLog = {}
    SlashCmdList.COMMANDERUI_FORECAST("reset")
    CHECK(CommanderForecastDB.Anchor == "BOTTOM", "reset restores settings defaults")
end

-- ===========================================================================
-- The repaint loop itself
-- ===========================================================================

do
    for _ = 1, 12 do RunTickers() end
    CHECK(#harnessFailedErrors == 0, "twelve ticker sweeps clean", harnessFailedErrors[1])
end

CHECK(#harnessFailedErrors == 0, "no errors at any point", harnessFailedErrors[1])

io.write(string.format("\n%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
