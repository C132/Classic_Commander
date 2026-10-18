-- Commander Guide UI smoke (luajit)
--
--     /opt/homebrew/bin/luajit Commander_Guide/Harness/guide_ui_smoke.lua
--
-- The engine smoke next door covers the reasoning with no client attached.
-- This one covers what the runtime does with what a real client says: all
-- four files load over a WoW widget mock (the Plates board recorder set,
-- with a voice) PLUS the suite's REAL settings framework, so the page is
-- built the way the client builds it and every spoken line is recorded.
--
-- Sections:
--   A  login: defaults applied, the module registered, the banner built
--   B  targeting a boss out of combat reads the brief once
--   C  a pull by ENCOUNTER_START: START queues behind the brief, Garrote on
--      you speaks after it, Blind cuts in
--   D  a health threshold from UNIT_HEALTH; ENCOUNTER_END closes the pull
--   E  no ENCOUNTER_START: a creature id in combat opens the pull, leaving
--      combat closes it after the grace
--   F  the window: eleven bosses, the page's sections, a click, Show by key
--   G  the settings page on the real framework: voices, roles, slash words
--   H  voice off: banner still, no speech; module off: nothing at all
--   I  the voice's own signature: five arguments, no overlap
-- ===========================================================================

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then HERE = (os.getenv("PWD") or ".") .. "/" .. HERE end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"

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

local now = 1000
function GetTime() return now end
function time() return 1000000 + now end
function GetCursorPosition() return 0, 0 end

local printLog = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    printLog[#printLog + 1] = table.concat(parts, " ")
end

local caughtErrors = {}
function geterrorhandler()
    return function(err) caughtErrors[#caughtErrors + 1] = tostring(err) end
end

-- ===========================================================================
-- The widget mock
-- ===========================================================================
local NUMERIC_GETTERS = {
    GetScale = 1, GetEffectiveScale = 1, GetFrameLevel = 2, GetLeft = 0, GetBottom = 0,
    GetTop = 0, GetRight = 0, GetStringWidth = 10, GetID = 1, GetNumPoints = 1,
    GetVerticalScroll = 0, GetVerticalScrollRange = 0,
}
local function IsMethodName(key) return type(key) == "string" and key:match("^[A-Z]") end
local eventRegistry = {}
local NewWidget
local allFrames = {}
local WidgetMT = {}
WidgetMT.__index = function(self, key)
    if type(key) ~= "string" then return nil end
    if key == "GetWidth" or key == "GetHeight" then
        local field = (key == "GetWidth") and "__w" or "__h"
        local fn = function(s) return rawget(s, field) or ((field == "__w") and 680 or 520) end
        rawset(self, key, fn); return fn
    end
    local recorders = {
        SetScale = function(s, v) s.__scale = v end,
        GetScale = function(s) return rawget(s, "__scale") or 1 end,
        SetFont = function(s, path, size, flags) s.__font = { path, size, flags } end,
        GetFont = function(s) local f = rawget(s, "__font"); if f then return f[1], f[2], f[3] end return "Fonts\\FRIZQT__.TTF", 10, "" end,
        SetFrameLevel = function(s, v) s.__level = v end,
        GetFrameLevel = function(s) return rawget(s, "__level") or 2 end,
        SetFrameStrata = function(s, v) s.__strata = v end,
        EnableMouse = function(s, v) s.__mouse = not not v end,
        SetPoint = function(s, point, rel, relPoint, x, y)
            s.__points = s.__points or {}
            s.__points[#s.__points + 1] = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
        end,
        GetPoint = function(s)
            local p = s.__points and s.__points[1]
            if not p then return nil end
            return p.point, p.rel, p.relPoint, p.x, p.y
        end,
        ClearAllPoints = function(s) s.__points = {} end,
        SetAllPoints = function(s) s.__allPoints = true end,
        SetSize = function(s, w, h) s.__w, s.__h = w, h end,
        SetWidth = function(s, w) s.__w = w end,
        SetHeight = function(s, h) s.__h = h end,
        SetTexture = function(s, tex) s.__texture = tex end,
        GetTexture = function(s) return s.__texture end,
        SetTexCoord = function(s, ...) s.__coords = { ... } end,
        SetVertexColor = function(s, r, g, b, a) s.__color = { r, g, b, a } end,
        SetColorTexture = function(s, r, g, b, a) s.__color = { r, g, b, a } end,
        SetTextColor = function(s, r, g, b, a) s.__color = { r, g, b, a } end,
        SetText = function(s, text)
            if s.__kind == "FontString" and not (rawget(s, "__font") or rawget(s, "__fontObject")) then
                error("FontString:SetText(): Font not set")
            end
            s.__text = text
        end,
        SetFontObject = function(s, obj) s.__fontObject = obj or "?" end,
        GetText = function(s) return s.__text end,
        GetStringHeight = function(s)
            local text = s.__text or ""
            if text == "" then return 0 end
            local width = (s.__w and s.__w > 0) and s.__w or 430
            return math.max(12, math.ceil(#text * 5 / width) * 12)
        end,
        SetAlpha = function(s, a) s.__alpha = a end,
        GetAlpha = function(s) return s.__alpha or 1 end,
        Show = function(s) s.__shown = true; local h = s.__scripts.OnShow; if h then h(s) end end,
        Hide = function(s) s.__shown = false end,
        SetShown = function(s, shown) s.__shown = not not shown end,
        IsShown = function(s) return s.__shown end,
        IsVisible = function(s) return s.__shown end,
        SetChecked = function(s, v) s.__checked = not not v end,
        GetChecked = function(s) return s.__checked end,
        SetEnabled = function(s, v) s.__enabled = not not v end,
        Enable = function(s) s.__enabled = true end,
        Disable = function(s) s.__enabled = false end,
        SetValue = function(s, v) s.__value = v end,
        GetValue = function(s) return s.__value end,
        SetMinMaxValues = function(s, a, b) s.__min, s.__max = a, b end,
        SetScrollChild = function(s, child) s.__child = child end,
        SetBackdrop = function(s, b) s.__backdrop = b end,
        SetBackdropColor = function(s, r, g, b, a) s.__bdColor = { r, g, b, a } end,
        SetBackdropBorderColor = function(s, r, g, b, a) s.__bdBorder = { r, g, b, a } end,
        CreateTexture = function(s, _, layer, _, sublevel)
            local t = NewWidget("Texture")
            t.__parent, t.__layer, t.__sublevel = s, layer, sublevel or 0
            s.__children[#s.__children + 1] = t
            return t
        end,
        CreateFontString = function(s, _, _, template)
            local t = NewWidget("FontString")
            t.__parent = s
            t.__fontObject = template
            s.__children[#s.__children + 1] = t
            return t
        end,
        GetParent = function(s) return s.__parent end,
        SetScript = function(s, name, handler) s.__scripts[name] = handler end,
        HookScript = function(s, name, handler) s.__scripts[name] = handler end,
        GetScript = function(s, name) return s.__scripts[name] end,
        RegisterEvent = function(s, event)
            eventRegistry[event] = eventRegistry[event] or {}
            table.insert(eventRegistry[event], s)
        end,
        UnregisterEvent = function(s, event)
            local list = eventRegistry[event] or {}
            for i = #list, 1, -1 do if list[i] == s then table.remove(list, i) end end
        end,
    }
    local fn = recorders[key]
    if fn then rawset(self, key, fn); return fn end
    if NUMERIC_GETTERS[key] ~= nil then
        local v = NUMERIC_GETTERS[key]
        fn = function() return v end
        rawset(self, key, fn); return fn
    end
    if IsMethodName(key) then
        fn = function() end
        rawset(self, key, fn); return fn
    end
    return nil
end
NewWidget = function(kind, name)
    return setmetatable({ __kind = kind, __name = name, __scripts = {}, __children = {}, __shown = true }, WidgetMT)
end
function CreateFrame(frameType, name, parent, template)
    local f = NewWidget(frameType, name)
    f.__template = template
    f.__parent = parent
    if parent and parent.__children then parent.__children[#parent.__children + 1] = f end
    if frameType == "CheckButton" or (template and template:find("CheckButton")) then
        f.Text = NewWidget("FontString"); f.Text.__fontObject = "GameFontNormal"
    end
    if template and template:find("BasicFrameTemplate") then
        f.TitleText = NewWidget("FontString"); f.TitleText.__fontObject = "GameFontNormal"
        f.CloseButton = NewWidget("Button")
    end
    if name then _G[name] = f end
    allFrames[#allFrames + 1] = f
    return f
end

UIParent = NewWidget("Frame", "UIParent")
GameTooltip = NewWidget("GameTooltip", "GameTooltip")
UISpecialFrames = {}
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack
bit = bit or require("bit")
for _, f in ipairs({ "GameFontNormal", "GameFontNormalLarge", "GameFontNormalHuge", "GameFontNormalSmall",
    "GameFontHighlight", "GameFontHighlightLarge", "GameFontHighlightSmall", "GameFontDisable", "GameFontDisableSmall" }) do
    _G[f] = NewWidget("Font")
end
SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2 }
function PlaySound() return true end
BACKDROP_SLIDER_8_8 = {}
SlashCmdList = {}
local categories = {}
Settings = {
    RegisterCanvasLayoutCategory = function(panel)
        local cat = { __panel = panel, GetID = function() return #categories + 1 end }
        categories[#categories + 1] = cat; return cat
    end,
    RegisterCanvasLayoutSubcategory = function(_, panel)
        local cat = { __panel = panel, GetID = function() return #categories + 1 end }
        categories[#categories + 1] = cat; return cat
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
}
C_AddOns = { GetAddOnMetadata = function() return "1.0.0" end }

-- timers that really fire, driven by Advance()
local timers = {}
C_Timer = {
    After = function(seconds, fn) timers[#timers + 1] = { due = now + seconds, fn = fn } end,
    NewTicker = function(seconds, fn)
        local t = { due = now + seconds, fn = fn, every = seconds }
        timers[#timers + 1] = t
        return { Cancel = function() t.cancelled = true end }
    end,
}
function UIDropDownMenu_Initialize(frame, fn)
    if not (frame and fn) then return end
    frame.__ddEntries = {}
    _G.__ddCurrent = frame
    local ok, err = pcall(fn, frame)
    if not ok then caughtErrors[#caughtErrors + 1] = "dropdown init: " .. tostring(err) end
    _G.__ddCurrent = nil
end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info)
    local f = _G.__ddCurrent
    if f and f.__ddEntries and info then f.__ddEntries[#f.__ddEntries + 1] = info end
end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetSelectedValue(frame, value) if frame then frame.__ddValue = value end end
function UIDropDownMenu_SetText(frame, text) if frame then frame.__ddText = text end end
function UIDropDownMenu_EnableDropDown() end
function UIDropDownMenu_DisableDropDown() end
RAID_CLASS_COLORS = { PRIEST = { r = 1, g = 1, b = 1 } }
CommanderConsole_Colors = { { text = "Steel (Default)", value = "STEEL", r = 0.62, g = 0.72, b = 0.85 } }
CommanderConsoleDB = { ConsoleColor = "STEEL" }

-- The client
local inCombat = false
function InCombatLockdown() return inCombat end
local targetGUID, targetHealth, targetMax = nil, 100, 100
function UnitGUID(unit)
    if unit == "player" then return "Player-1-ME" end
    if unit == "target" then return targetGUID end
    return nil
end
function UnitExists(unit) if unit == "target" then return targetGUID ~= nil end return unit == "player" end
function UnitClass(unit) return "Priest", "PRIEST" end
function UnitHealth(unit) return targetHealth end
function UnitHealthMax(unit) return targetMax end
function GetSpellTexture(id) return "Interface\\Icons\\Spell_" .. tostring(id) end
function GetSpellInfo(id) return "Spell " .. tostring(id) end
local instanceMapID = 0
function GetInstanceInfo() return "Karazhan", "raid", 1, "10 Player", 10, 0, false, instanceMapID end
COMBATLOG_OBJECT_TYPE_PLAYER = 0x400
COMBATLOG_OBJECT_REACTION_FRIENDLY = 0x10

-- The voice
local spoken, stops = {}, 0
local voices = { { voiceID = 1, name = "Samantha" }, { voiceID = 2, name = "Daniel" } }
C_VoiceChat = {
    SpeakText = function(voiceID, text, rate, volume, overlap)
        spoken[#spoken + 1] = { voiceID = voiceID, text = text, rate = rate, volume = volume, overlap = overlap, n = select("#", voiceID, text, rate, volume, overlap) }
    end,
    StopSpeakingText = function() stops = stops + 1 end,
    GetTtsVoices = function() return voices end,
}
C_TTSSettings = { GetVoiceOptionID = function() return 2 end }
Enum = { TtsVoiceType = { Standard = 0, Alternate = 1 } }

local cleuArgs
function CombatLogGetCurrentEventInfo() return unpack(cleuArgs, 1, cleuArgs.n) end

local function Fire(event, ...)
    local list = {}
    for i, f in ipairs(eventRegistry[event] or {}) do list[i] = f end
    for _, f in ipairs(list) do
        local handler = f.__scripts.OnEvent
        if handler then
            local ok, err = pcall(handler, f, event, ...)
            if not ok then caughtErrors[#caughtErrors + 1] = event .. ": " .. tostring(err) end
        end
    end
end

local ME = "Player-1-ME"
local FRIEND = 0x10 + 0x400
local HOSTILE = 0x40 + 0x800
local function GUID(npc) return ("Creature-0-4379-532-19862-%d-00002B6E9A"):format(npc) end
local function CLEU(sub, sg, sn, sf, dg, dn, df, ...)
    cleuArgs = { now, sub, false, sg, sn, sf, 0, dg, dn, df, 0, ... }
    cleuArgs.n = 11 + select("#", ...)
    Fire("COMBAT_LOG_EVENT_UNFILTERED")
end

local function Advance(seconds)
    local steps = math.floor(seconds / 0.1 + 0.5)
    for _ = 1, steps do
        now = now + 0.1
        for _, f in ipairs(allFrames) do
            local handler = f.__scripts.OnUpdate
            if handler then
                local ok, err = pcall(handler, f, 0.1)
                if not ok then caughtErrors[#caughtErrors + 1] = "OnUpdate: " .. tostring(err) end
            end
        end
        local list = timers
        timers = {}
        for _, t in ipairs(list) do
            if t.cancelled then
            elseif t.due <= now + 1e-9 then
                local ok, err = pcall(t.fn)
                if not ok then caughtErrors[#caughtErrors + 1] = "timer: " .. tostring(err) end
                if t.every then t.due = now + t.every; timers[#timers + 1] = t end
            else
                timers[#timers + 1] = t
            end
        end
    end
end

local function LastSpoken() return spoken[#spoken] and spoken[#spoken].text end
local function Finished() Fire("VOICE_CHAT_TTS_PLAYBACK_FINISHED", 1, 1, 1) end

-- ===========================================================================
-- Load: the real framework, then the module in TOC order
-- ===========================================================================
local function Load(path) assert(loadfile(path))() end
Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
Load(ADDONS .. "/Commander_Guide/CommanderGuideData.lua")
Load(ADDONS .. "/Commander_Guide/CommanderGuideEngine.lua")
Load(ADDONS .. "/Commander_Guide/CommanderGuideDB.lua")
Load(ADDONS .. "/Commander_Guide/CommanderGuide.lua")

local D, E = CommanderGuide_Data, CommanderGuide_Engine

-- A ------------------------------------------------------------------------
Fire("ADDON_LOADED", "Commander_Guide")
EQ(CommanderGuideDB.Enable, true, "A: defaults applied")
EQ(CommanderGuideDB.Role, "HEALER", "A: healer's seat by default")
EQ(CommanderGuideDB.BannerStyle, "NONE", "A: banner chrome keys present")
instanceMapID = 532
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD")
local registered = false
for _, m in ipairs(Commander.GetModules()) do if m.key == "Guide" then registered = true end end
CHECK(registered, "A: module registered with the hub")
local dbg = CommanderGuide_Debug()
CHECK(dbg.ctx ~= nil, "A: session built")
EQ(dbg.inRaidMap, true, "A: Karazhan recognised by instance map id")
CHECK(dbg.banner ~= nil and dbg.banner.__shown == false, "A: banner built and hidden")
EQ(#spoken, 0, "A: nothing spoken at login")
EQ(#caughtErrors, 0, "A: no errors at login", caughtErrors[1])

-- B ------------------------------------------------------------------------
targetGUID = GUID(15687)
Fire("PLAYER_TARGET_CHANGED")
EQ(#spoken, 1, "B: targeting Moroes reads the brief")
CHECK((LastSpoken() or ""):sub(1, 7) == "Moroes.", "B: the brief opens with the boss", LastSpoken())
CHECK((LastSpoken() or ""):find("Your job.", 1, true), "B: and reads your job")
CHECK(not (LastSpoken() or ""):find("Phase 1", 1, true), "B: short brief by default")
CHECK(dbg.banner.__shown and (dbg.banner.text.__text or ""):find("Moroes"), "B: banner shows the boss line")
targetGUID = nil
Fire("PLAYER_TARGET_CHANGED")
targetGUID = GUID(15687)
Fire("PLAYER_TARGET_CHANGED")
EQ(#spoken, 1, "B: the same boss is not briefed again straight away")
Finished()

-- C ------------------------------------------------------------------------
Fire("PLAYER_REGEN_DISABLED")
inCombat = true
Fire("ENCOUNTER_START", 653, "Moroes", 1, 10)
EQ(dbg.ctx.boss and dbg.ctx.boss.key, "MOROES", "C: the pull is Moroes")
EQ(dbg.ctx.source, "encounter", "C: named by ENCOUNTER_START")
EQ(#spoken, 2, "C: START spoken (the brief had finished)")
CHECK((LastSpoken() or ""):find("Adds first"), "C: START text", LastSpoken())
-- Garrote on me while START is still being said: queued
CLEU("SPELL_AURA_APPLIED", GUID(15687), "Moroes", HOSTILE, ME, "Me", FRIEND, 37066, "Garrote", 1, "DEBUFF")
EQ(#spoken, 2, "C: Garrote waits behind START")
Finished()
EQ(#spoken, 3, "C: then it speaks")
EQ(LastSpoken(), "Garrote on you. Heal yourself between casts.", "C: Garrote on you")
CHECK(dbg.banner.text.__text == LastSpoken(), "C: banner carries the same line")
-- Blind on me cuts in
local stopsBefore = stops
CLEU("SPELL_AURA_APPLIED", GUID(15687), "Moroes", HOSTILE, ME, "Me", FRIEND, 34694, "Blind", 1, "DEBUFF")
EQ(stops, stopsBefore + 1, "C: an urgent line stops the current one")
EQ(LastSpoken(), "You are blind. Others cover your targets.", "C: and speaks at once")
Finished()
-- Garrote on a friend
CLEU("SPELL_AURA_APPLIED", GUID(15687), "Moroes", HOSTILE, "Player-1-THRALL", "Thrall-Whitemane", FRIEND, 37066, "Garrote", 1, "DEBUFF")
EQ(LastSpoken(), "Garrote on Thrall. Keep a heal on them.", "C: friend's name, realm stripped")
Finished()
-- a hostile target of the same spell is silent
local countBefore = #spoken
CLEU("SPELL_AURA_APPLIED", ME, "Me", FRIEND, GUID(15687), "Moroes", HOSTILE, 37066, "Garrote", 1, "DEBUFF")
EQ(#spoken, countBefore, "C: a debuff on the boss is silent")
-- the fallback timer pumps when no playback event arrives
CLEU("SPELL_CAST_SUCCESS", GUID(15687), "Moroes", HOSTILE, nil, nil, 0, 29448, "Vanish", 1)
EQ(LastSpoken(), "Vanish. Garrote coming. Top everyone up.", "C: Vanish spoken")
CLEU("SPELL_AURA_APPLIED", GUID(15687), "Moroes", HOSTILE, "Player-1-JAINA", "Jaina", FRIEND, 29425, "Gouge", 1, "DEBUFF")
EQ(#spoken, countBefore + 1, "C: Gouge queued while Vanish plays")
Advance(2)
EQ(#spoken, countBefore + 1, "C: still queued two seconds in")
Advance(4)
EQ(LastSpoken(), "Gouge on Jaina. Off tank has him.", "C: the fallback timer speaks it")
EQ(#caughtErrors, 0, "C: no errors", caughtErrors[1])

-- D ------------------------------------------------------------------------
Finished()
targetGUID = GUID(15687)
targetHealth, targetMax = 55, 100
Fire("UNIT_HEALTH", "target")
CHECK(LastSpoken() ~= "Moroes enraged. Everything on the tank.", "D: 55 percent is quiet")
Advance(1)
targetHealth = 30
Fire("UNIT_HEALTH", "target")
EQ(LastSpoken(), "Moroes enraged. Everything on the tank.", "D: 30 percent fires the enrage line")
Finished()
Advance(1)
targetHealth = 10
Fire("UNIT_HEALTH", "target")
EQ(LastSpoken(), "Moroes enraged. Everything on the tank.", "D: the threshold does not repeat")
Fire("ENCOUNTER_END", 653, "Moroes", 1, 10, 1)
EQ(dbg.ctx.boss, nil, "D: ENCOUNTER_END closes the pull")
inCombat = false
Fire("PLAYER_REGEN_ENABLED")
Advance(1)

-- E ------------------------------------------------------------------------
targetGUID = nil
local before = #spoken
Fire("PLAYER_REGEN_DISABLED")
inCombat = true
CLEU("SPELL_CAST_START", GUID(16457), "Maiden of Virtue", HOSTILE, "Player-1-JAINA", "Jaina", FRIEND, 29522, "Holy Fire", 2)
EQ(dbg.ctx.boss and dbg.ctx.boss.key, "MAIDEN", "E: Maiden's creature id opens the pull without ENCOUNTER_START")
EQ(dbg.ctx.source, "npc", "E: source npc")
EQ(#spoken, before + 1, "E: START spoken")
CHECK((LastSpoken() or ""):find("Maiden"), "E: it is Maiden's START", LastSpoken())
Finished()
CLEU("SPELL_AURA_APPLIED", GUID(16457), "Maiden of Virtue", HOSTILE, "Player-1-JAINA", "Jaina", FRIEND, 29522, "Holy Fire", 2, "DEBUFF")
EQ(LastSpoken(), "Holy Fire on Jaina. Dispel it.", "E: Holy Fire on a friend")
Finished()
inCombat = false
Fire("PLAYER_REGEN_ENABLED")
Advance(3)
CHECK(dbg.ctx.boss ~= nil, "E: three seconds out of combat, the pull is still open")
Advance(4)
EQ(dbg.ctx.boss, nil, "E: after the grace it closes")
-- re-entering combat within the grace keeps it
Fire("PLAYER_REGEN_DISABLED"); inCombat = true
CLEU("SPELL_CAST_START", GUID(16457), "Maiden of Virtue", HOSTILE, nil, nil, 0, 29511, "Repentance", 2)
Finished()
CHECK(dbg.ctx.boss ~= nil, "E: pull reopened")
inCombat = false
Fire("PLAYER_REGEN_ENABLED")
Advance(2)
Fire("PLAYER_REGEN_DISABLED"); inCombat = true
Advance(6)
CHECK(dbg.ctx.boss ~= nil, "E: back in combat before the grace ran out keeps the pull")
inCombat = false
Fire("PLAYER_REGEN_ENABLED")
Advance(7)
EQ(dbg.ctx.boss, nil, "E: closed")
EQ(#caughtErrors, 0, "E: no errors", caughtErrors[1])

-- F ------------------------------------------------------------------------
CommanderGuide_Toggle()
local f = CommanderGuideFrame
CHECK(f ~= nil and f.__shown, "F: window shown")
CHECK(UISpecialFrames[1] == "CommanderGuideFrame", "F: ESC closes it")
local shownButtons = 0
for _, b in ipairs(f.bossButtons) do if b.__shown then shownButtons = shownButtons + 1 end end
EQ(shownButtons, 11, "F: eleven boss rows")
EQ(f.bossButtons[2].label.__text, "2.  Moroes", "F: row text")
EQ(f.raidTitle.__text, "Karazhan", "F: raid title")
local function PageTexts()
    local texts = {}
    for _, c in ipairs(f.content.__children) do
        if c.__kind == "FontString" and c.__shown and c.__text and c.__text ~= "" then texts[#texts + 1] = c.__text end
    end
    return texts
end
local function HasText(needle)
    for _, t in ipairs(PageTexts()) do if t:find(needle, 1, true) then return true end end
    return false
end
CHECK(HasText("The fight in one line"), "F: lead header")
CHECK(HasText("Your job"), "F: job header")
CHECK(HasText("Watch list"), "F: watch header")
CHECK(HasText("What the voice will say"), "F: callouts header")
CHECK(HasText("On the pull"), "F: a When() sentence")
local icons = 0
for _, c in ipairs(f.content.__children) do if c.__kind == "Texture" and c.__shown and c.__texture then icons = icons + 1 end end
CHECK(icons >= 3, "F: watch rows carry icons", icons)
CHECK((f.content.__h or 0) > 400, "F: content height grows with the page", f.content.__h)
-- click Aran
f.bossButtons[7].__scripts.OnClick(f.bossButtons[7])
EQ(f.title.__text, "Shade of Aran", "F: clicking a row renders that boss")
CHECK(HasText("Flame Wreath"), "F: Aran's page mentions Flame Wreath")
CHECK(f.bossButtons[7].selected.__shown and not f.bossButtons[2].selected.__shown, "F: selection moves")
-- Show by key
EQ(CommanderGuide_Show("KARAZHAN", "PRINCE"), true, "F: Show by key")
EQ(f.title.__text, "Prince Malchezaar", "F: Prince rendered")
EQ(CommanderGuide_Show("KARAZHAN", "NOBODY"), false, "F: unknown key refused")
-- Read Brief button speaks the selected boss
local sBefore = #spoken
f.briefButton.__scripts.OnClick(f.briefButton)
EQ(#spoken, sBefore + 1, "F: Read Brief speaks")
CHECK((LastSpoken() or ""):sub(1, 18) == "Prince Malchezaar.", "F: the selected boss", LastSpoken())
Finished()
-- the window follows the pull
Fire("PLAYER_REGEN_DISABLED"); inCombat = true
Fire("ENCOUNTER_START", 662, "Nightbane", 1, 10)
EQ(f.title.__text, "Nightbane", "F: the open window follows the pull")
Fire("ENCOUNTER_END", 662, "Nightbane", 1, 10, 0)
inCombat = false
Fire("PLAYER_REGEN_ENABLED")
Finished()
CommanderGuide_Toggle()
CHECK(not f.__shown, "F: toggle hides")
EQ(#caughtErrors, 0, "F: no errors", caughtErrors[1])

-- G ------------------------------------------------------------------------
local panel
for _, cat in ipairs(categories) do
    if cat.__panel and cat.__panel._key == "Guide" then panel = cat.__panel end
end
CHECK(panel ~= nil, "G: settings page exists")
if panel then
    panel:Refresh()
    local dropdowns = {}
    local function Walk(w)
        for _, c in ipairs(w.__children or {}) do
            if c.__ddEntries then dropdowns[#dropdowns + 1] = c end
            Walk(c)
        end
    end
    Walk(panel)
    local roleDD, voiceDD
    for _, dd in ipairs(dropdowns) do
        for _, e in ipairs(dd.__ddEntries) do
            if e.value == "HEALER" then roleDD = dd end
            if e.text == "Samantha" then voiceDD = dd end
        end
    end
    CHECK(roleDD ~= nil, "G: role dropdown has entries")
    if roleDD then EQ(#roleDD.__ddEntries, 3, "G: three seats listed") end
    CHECK(voiceDD ~= nil, "G: voice dropdown lists the client's voices")
    if voiceDD then
        EQ(#voiceDD.__ddEntries, 3, "G: client default plus two voices")
        EQ(voiceDD.__ddEntries[1].value, false, "G: client default first")
    end
end
local slash = SlashCmdList["COMMANDERUI_GUIDE"]
CHECK(type(slash) == "function", "G: slash registered")
if slash then
    local sBefore = #spoken
    slash("test")
    EQ(#spoken, sBefore + 1, "G: /cguide test speaks")
    EQ(LastSpoken(), "Garrote on you. Heal yourself between casts.", "G: the test line")
    Finished()
    slash("")
    CHECK(CommanderGuideFrame.__shown, "G: bare /cguide opens the window")
    slash("")
    CHECK(not CommanderGuideFrame.__shown, "G: and closes it")
    slash("validate")
    CHECK(printLog[#printLog]:find("validates clean"), "G: /cguide validate", printLog[#printLog])
    targetGUID = GUID(15690)
    sBefore = #spoken
    slash("brief")
    EQ(#spoken, sBefore + 1, "G: /cguide brief reads the target")
    CHECK((LastSpoken() or ""):find("Prince"), "G: Prince's brief", LastSpoken())
    slash("stop")
    Finished()
end

-- H ------------------------------------------------------------------------
CommanderGuideDB.Voice = false
Commander.Notify(COMMANDER_GUIDE_EVENTS.UPDATE)
local sBefore = #spoken
Fire("PLAYER_REGEN_DISABLED"); inCombat = true
Fire("ENCOUNTER_START", 656, "The Curator", 1, 10)
EQ(#spoken, sBefore, "H: voice off, nothing spoken")
CHECK((dbg.banner.text.__text or ""):find("Curator"), "H: the banner still shows the START line", dbg.banner.text.__text)
CLEU("SPELL_CAST_START", GUID(15691), "The Curator", HOSTILE, nil, nil, 0, 30254, "Evocation", 64)
CHECK((dbg.banner.text.__text or ""):find("Evocation"), "H: and the next line at once (nothing to wait for)")
Fire("ENCOUNTER_END", 656, "The Curator", 1, 10, 0)
inCombat = false
Fire("PLAYER_REGEN_ENABLED")
CommanderGuideDB.Voice = true
CommanderGuideDB.Enable = false
Commander.Notify(COMMANDER_GUIDE_EVENTS.UPDATE)
Fire("PLAYER_REGEN_DISABLED"); inCombat = true
Fire("ENCOUNTER_START", 657, "Terestian Illhoof", 1, 10)
EQ(dbg.ctx.boss, nil, "H: module off, the pull is not even tracked")
EQ(#spoken, sBefore, "H: nothing spoken")
inCombat = false
Fire("PLAYER_REGEN_ENABLED")
CommanderGuideDB.Enable = true
Commander.Notify(COMMANDER_GUIDE_EVENTS.UPDATE)

-- I ------------------------------------------------------------------------
CommanderGuideDB.Rate = 3
CommanderGuideDB.Volume = 80
CommanderGuide_Test()
local last = spoken[#spoken]
EQ(last.n, 5, "I: SpeakText takes five arguments (voiceID, text, rate, volume, overlap)")
EQ(last.rate, 3, "I: rate from settings")
EQ(last.volume, 80, "I: volume from settings")
EQ(last.overlap, false, "I: never overlaps")
EQ(last.voiceID, 2, "I: client default resolves to the Standard voice option")
CommanderGuideDB.VoiceID = 1
CommanderGuide_Test()
EQ(spoken[#spoken].voiceID, 1, "I: a chosen voice is used")
CommanderGuideDB.VoiceID = 99
CommanderGuide_Test()
EQ(spoken[#spoken].voiceID, 2, "I: a missing voice falls back")
EQ(#caughtErrors, 0, "I: no errors anywhere", caughtErrors[1])
for _, e in ipairs(caughtErrors) do io.write("      ", e, "\n") end

-- J ------------------------------------------------------------------------
-- The way in (1.1.0, DECISIONS D11). Commander Orders is a stub here that
-- records what it is handed; the real API's acceptance of the same spec is
-- what Commander_Logistics/Harness/logistics_orders_smoke.lua section G
-- proves against the real Orders runtime.
local orderAdds, entranceAsks = {}, {}
local ordersAnswer = { "w7" }          -- what Add returns, unpacked
local resolverAnswer = nil             -- what Entrance returns
local function StubOrders()
    CommanderOrders = {
        Add = function(spec) orderAdds[#orderAdds + 1] = spec; return unpack(ordersAnswer) end,
        Entrance = function(map) entranceAsks[#entranceAsks + 1] = map; return resolverAnswer end,
        Describe = function() return "Commander Orders arrow" end,
    }
end
local function LastPrint() return printLog[#printLog] or "" end
local tipLines = {}
GameTooltip.SetText = function(_, text) tipLines = { tostring(text) } end
GameTooltip.AddLine = function(_, text) tipLines[#tipLines + 1] = tostring(text) end
local function TipText(widget)
    tipLines = {}
    local enter = widget.__scripts.OnEnter
    if enter then enter(widget) end
    return table.concat(tipLines, " | ")
end

-- Inside Karazhan the door is behind you: refused, and the button greys out
instanceMapID = 532
Fire("PLAYER_ENTERING_WORLD")
CommanderGuide_Show("KARAZHAN", "MOROES")
local g = CommanderGuideFrame
CHECK(g.entrance ~= nil, "J: the window carries the entrance button")
EQ(g.entrance and g.entrance.__text, "Go to Entrance", "J: labelled")
CHECK(g.entrance and g.entrance.__points and g.entrance.__points[1].rel == g.list,
    "J: it sits on the boss list, the raid's column")
EQ(g.entrance and g.entrance.__enabled, false, "J: greyed out inside Karazhan")
StubOrders()
local ok, why = CommanderGuide_Entrance()
EQ(ok, false, "J: refused inside")
EQ(why, "inside", "J: ...because you are inside")
EQ(#orderAdds, 0, "J: nothing handed to Orders from inside")
CHECK(LastPrint():find("already inside Karazhan", 1, true), "J: and it says why", LastPrint())
CHECK(TipText(g.entrance):find("inside Karazhan", 1, true), "J: the tooltip says so too")

-- Outside: zoning out re-enables the open window's button
instanceMapID = 0
Fire("PLAYER_ENTERING_WORLD")
EQ(g.entrance.__enabled, true, "J: zoning out lights the button on the open window")

-- Orders present, no resolver answer: the cited table, both doors
ok, why = CommanderGuide_Entrance()
EQ(ok, true, "J: Orders took the waypoint")
EQ(why, "w7", "J: ...and the uid comes back")
EQ(entranceAsks[#entranceAsks], 350, "J: Orders' resolvers were asked for Karazhan's own uiMap first")
local s = orderAdds[#orderAdds]
CHECK(s and s.map == 1430 and s.x == 0.467 and s.y == 0.702, "J: the table's first door on Deadwind Pass",
    s and (tostring(s.map) .. " " .. tostring(s.x) .. " " .. tostring(s.y)))
EQ(s and s.alternatives and #s.alternatives, 2, "J: both doors offered as alternatives")
EQ(s and s.source, "Guide", "J: source Guide")
EQ(s and s.key, "entrance:KARAZHAN", "J: keyed per raid")
EQ(s and s.setArrow, true, "J: a press takes the arrow")
EQ(s and s.title, "Karazhan entrance", "J: titled")
CHECK(LastPrint():find("the arrow points to the Karazhan entrance in Deadwind Pass", 1, true),
    "J: a one-line confirmation", LastPrint())

-- A resolver answer wins
resolverAnswer = { map = 1430, x = 0.5, y = 0.75, title = "Karazhan" }
CommanderGuide_Entrance()
s = orderAdds[#orderAdds]
CHECK(s and s.x == 0.5 and s.y == 0.75 and s.alternatives == nil, "J: Orders' resolver answer is used as is")
-- ...unless it throws, which falls back to the table without an error
CommanderOrders.Entrance = function() error("resolver blew up") end
local nBefore = #orderAdds
CommanderGuide_Entrance()
EQ(#orderAdds, nBefore + 1, "J: a throwing resolver still gets a waypoint")
EQ(orderAdds[#orderAdds].x, 0.467, "J: ...from the table")
resolverAnswer = nil
StubOrders()

-- The button and the slash word reach the same place
nBefore = #orderAdds
g.entrance.__scripts.OnClick(g.entrance)
EQ(#orderAdds, nBefore + 1, "J: the button sets the waypoint")
local slashJ = SlashCmdList["COMMANDERUI_GUIDE"]
if slashJ then slashJ("entrance") end
EQ(#orderAdds, nBefore + 2, "J: /cguide entrance sets it too")
EQ(BINDING_NAME_COMMANDERGUIDE_ENTRANCE, "Go to the raid's entrance", "J: the key binding is named")
local bx = io.open(ADDONS .. "/Commander_Guide/Bindings.xml", "r")
local bindingsXml = bx and bx:read("*a") or ""
if bx then bx:close() end
CHECK(bindingsXml:find('name="COMMANDERGUIDE_ENTRANCE"', 1, true) and bindingsXml:find("CommanderGuide_Entrance()", 1, true),
    "J: Bindings.xml binds it")
CHECK(not bindingsXml:find("<!%-%-.-%-%-.-%-%->"), "J: no '--' inside an XML comment")
local tip = TipText(g.entrance)
CHECK(tip:find("Commander Orders arrow", 1, true) and tip:find("Deadwind Pass", 1, true),
    "J: the tooltip names the arrow and the zone", tip)

-- Orders refuses: the reason in words, and the line to paste
ordersAnswer = { nil, "disabled" }
ok, why = CommanderGuide_Entrance()
EQ(ok, false, "J: a refusal is not a success")
EQ(why, "disabled", "J: ...and keeps Orders' reason")
CHECK(LastPrint():find("Commander Orders is turned off (/corder)", 1, true)
    and LastPrint():find("/way #1430 46.70 70.20 Karazhan entrance", 1, true),
    "J: turned off: says so and prints the /way line", LastPrint())
-- Orders throws: still never an error out of the guide
CommanderOrders.Add = function() error("orders blew up") end
local errsBefore = #caughtErrors
ok, why = CommanderGuide_Entrance()
EQ(why, "error", "J: a throwing Add is caught")
CHECK(LastPrint():find("/way #1430", 1, true), "J: ...and the line is printed", LastPrint())
EQ(#caughtErrors, errsBefore, "J: ...without an error escaping")
ordersAnswer = { "w7" }

-- Orders absent: the /way line, the button still does something
CommanderOrders = nil
nBefore = #orderAdds
ok, why = CommanderGuide_Entrance()
EQ(ok, false, "J: no Orders, no waypoint")
EQ(why, "absent", "J: ...because Orders is absent")
CHECK(LastPrint():find("Karazhan entrance -- /way #1430 46.70 70.20 Karazhan entrance", 1, true),
    "J: the /way line is printed instead", LastPrint())
CHECK(TipText(g.entrance):find("/way", 1, true), "J: and the tooltip says that is what it will do")
EQ(#orderAdds, nBefore, "J: nothing recorded without Orders")

-- An unknown raid key falls back to the page's raid; the module switch holds
StubOrders()
ok = CommanderGuide_Entrance("KARAZHAN")
EQ(ok, true, "J: by raid key")
CommanderGuideDB.Enable = false
nBefore = #orderAdds
ok, why = CommanderGuide_Entrance()
EQ(why, "disabled", "J: the guide switched off refuses")
EQ(#orderAdds, nBefore, "J: ...and hands nothing over")
CommanderGuideDB.Enable = true

-- The settings page carries the button and explains it
local found
local function FindButton(w)
    for _, c in ipairs(w.__children or {}) do
        if c.__text == "Go to Entrance" and c.__kind == "Button" then found = c end
        FindButton(c)
    end
end
for _, cat in ipairs(categories) do
    if cat.__panel and cat.__panel._key == "Guide" then FindButton(cat.__panel) end
end
CHECK(found ~= nil, "J: the settings page has a Go to Entrance button")
if found then
    nBefore = #orderAdds
    found.__scripts.OnClick(found)
    EQ(#orderAdds, nBefore + 1, "J: ...that sets the waypoint")
end
CommanderOrders = nil
CommanderGuide_Toggle()
EQ(#caughtErrors, 0, "J: no errors", caughtErrors[1])
for _, e in ipairs(caughtErrors) do io.write("      ", e, "\n") end

io.write(string.format("%d checks, %d failed\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
