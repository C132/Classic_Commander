-- Commander Chat smoke (luajit):
--     luajit chat_smoke.lua
--
-- Covers the footprint work: window scale/size/font, the mouseover-only and
-- mouseover alpha driver, background opacity seeding, channel muting through
-- the CHAT_MSG_CHANNEL filter, and the quick layout presets. Mock modeled on
-- Commander_PartyFrames/Harness.

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

local now = 1000
function GetTime() return now end

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
        GetWidth = function(s) return s.__w or 430 end,
        GetHeight = function(s) return s.__h or 120 end,
        SetScale = function(s, v) s.__scale = v end,
        GetScale = function(s) return s.__scale or 1 end,
        SetFont = function(s, file, size, flags) s.__font = { file, size, flags } end,
        GetFont = function(s)
            local f = s.__font or { "Fonts\\FRIZQT__.TTF", 14, "" }
            return f[1], f[2], f[3]
        end,
        SetText = function(s, text) s.__text = text end,
        GetText = function(s) return s.__text end,
        SetAlpha = function(s, a)
            if s.__alpha ~= a then s.__alphaWrites = (s.__alphaWrites or 0) + 1 end
            s.__alpha = a
        end,
        GetAlpha = function(s) return s.__alpha or 1 end,
        Show = function(s) s.__shown = true end,
        Hide = function(s) s.__shown = false end,
        SetShown = function(s, shown) s.__shown = not not shown end,
        IsShown = function(s) return s.__shown end,
        IsVisible = function(s) return s.__shown end,
        IsMouseOver = function(s) return not not s.__hovered end,
        HasFocus = function(s) return not not s.__focused end,
        SetFading = function(s, v) s.__fading = not not v end,
        SetTimeVisible = function(s, v) s.__timeVisible = v end,
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
        AddMessage = function(s, text, r, g, b)
            s.__lastMessage = text
            s.__lastColor = { r, g, b }
        end,
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

local allFrames = {}
function CreateFrame(frameType, name, parent, template)
    local f = NewWidget(frameType, name)
    f.__template = template
    f.__parent = parent
    if frameType == "CheckButton" or (template and template:find("CheckButton")) then
        f.Text = NewWidget("FontString")
    end
    if name then _G[name] = f end
    allFrames[#allFrames + 1] = f
    return f
end

UIParent = NewWidget("Frame", "UIParent")
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
unpack = unpack or table.unpack

for _, f in ipairs({ "GameFontNormal", "GameFontNormalLarge", "GameFontNormalSmall",
    "GameFontHighlight", "GameFontHighlightSmall", "GameFontDisable", "GameFontDisableSmall" }) do
    _G[f] = NewWidget("Font")
end

SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2,
    IG_CHARACTER_INFO_TAB = 841 }
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
C_AddOns = { GetAddOnMetadata = function() return "2.2.0" end }

local timers = {}
C_Timer = {
    After = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end,
    NewTicker = function(interval, fn) return { Cancel = function(s) s.cancelled = true end } end,
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

-- --- Chat-specific mock ----------------------------------------------------
NUM_CHAT_WINDOWS = 10
local cvars = { showTimestamps = "none" }
function SetCVar(name, value) cvars[name] = value end
function GetCVar(name) return cvars[name] end

local chatFrames = {}
for i = 1, NUM_CHAT_WINDOWS do
    local cf = CreateFrame("ScrollingMessageFrame", "ChatFrame" .. i)
    cf.__shown = (i <= 2)
    cf.AddMessage = function(s, text) s.__lastMessage = text end
    cf.editBox = CreateFrame("EditBox", "ChatFrame" .. i .. "EditBox", cf)
    cf.editBox.chatFrame = cf
    cf.editBox.__shown = false
    cf.buttonFrame = CreateFrame("Frame", "ChatFrame" .. i .. "ButtonFrame")
    local tab = CreateFrame("Button", "ChatFrame" .. i .. "Tab")
    tab.__shown = (i <= 2)
    cf.Tab = tab
    chatFrames[i] = cf
end
ChatFrameChannelButton = CreateFrame("Button", "ChatFrameChannelButton")
ChatFrameMenuButton = CreateFrame("Button", "ChatFrameMenuButton")
FriendsMicroButton = CreateFrame("Button", "FriendsMicroButton")

-- name, fontSize, r, g, b, alpha, shown, locked, docked, uninteractable
local savedWindowAlpha = 0.4
function GetChatWindowInfo(id)
    return "Window" .. id, 14, 0, 0, 0, savedWindowAlpha, true, true, true, false
end

local bgAlphaSaved = {}
function FCF_SetWindowAlpha(frame, alpha, doNotSave)
    frame.__bgAlpha = alpha
    if not doNotSave then bgAlphaSaved[frame] = alpha end
end

local messageFilters = {}
ChatFrameUtil = {
    AddMessageEventFilter = function(event, callback)
        messageFilters[event] = messageFilters[event] or {}
        table.insert(messageFilters[event], callback)
    end,
}

local channels = { { 1, "General", false }, { 2, "Trade", false }, { 5, "MyGuildAlts", false } }
function GetChannelList()
    local out = {}
    for _, c in ipairs(channels) do
        out[#out + 1] = c[1]; out[#out + 1] = c[2]; out[#out + 1] = c[3]
    end
    return unpack(out)
end
local leftChannels = {}
function LeaveChannelByName(name) leftChannels[#leftChannels + 1] = name end

ChatFontNormal = NewWidget("Font")
ChatFontNormal.GetFont = function() return "Fonts\\FRIZQT__.TTF", 14, "" end
function SetItemRef() end
function IsShiftKeyDown() return false end
GameTooltip = NewWidget("GameTooltip", "GameTooltip")

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

_G.CommanderChatDB = {}
Load(ADDONS .. "/Commander_Chat/CommanderChatDB.lua")
Fire("ADDON_LOADED", "Commander_Chat")
Load(ADDONS .. "/Commander_Chat/CommanderChatFrame.lua")
Load(ADDONS .. "/Commander_Chat/CommanderChat.lua")
Fire("PLAYER_LOGIN")

local DB = _G.CommanderChatDB
local chat1, tab1 = _G.ChatFrame1, _G.ChatFrame1Tab

local function Apply()
    Commander.Notify(COMMANDER_CHAT_EVENTS.UPDATE)
end

-- The alpha driver is the only frame in the addon that installs an OnUpdate
local function Driver()
    for _, f in ipairs(allFrames) do
        if f.__scripts.OnUpdate then return f end
    end
end

local function RunDriver(seconds)
    local driver = Driver()
    if not driver then return false end
    local step = 0.05
    for _ = 1, math.floor(seconds / step) do
        driver.__scripts.OnUpdate(driver, step)
    end
    return true
end

local function FireChannel(...)
    for _, filter in ipairs(messageFilters.CHAT_MSG_CHANNEL or {}) do
        if filter(chat1, "CHAT_MSG_CHANNEL", ...) then return true end
    end
    return false
end

-- ===========================================================================
-- Baseline: a fresh install changes nothing it was not asked to
-- ===========================================================================

CHECK(chat1.__shown, "chat window starts visible")
CHECK(chat1.__scale == 1, "scale untouched at defaults", chat1.__scale)
CHECK(chat1.__w == nil, "size untouched while the resize override is off")
CHECK(chat1.__font == nil, "font untouched at the Default setting")
CHECK(cvars.showTimestamps == "none", "timestamp CVar untouched while off")
CHECK(DB.BackgroundAlpha == savedWindowAlpha,
    "background opacity seeded from the window's existing value", DB.BackgroundAlpha)
CHECK(chat1.__bgAlpha == savedWindowAlpha, "and re-applied at that same value", chat1.__bgAlpha)
CHECK(bgAlphaSaved[chat1] == nil, "Blizzard's saved opacity is never written")
CHECK(Driver() == nil, "no OnUpdate ticker while nothing watches the mouse")
CHECK(chat1.__timeVisible == 120, "default fade delay is Blizzard's 120s", chat1.__timeVisible)

-- A chat settings record the server has not sent down yet reports a blank
-- name and a zero alpha; adopting that would blank the window on first login
DB.BackgroundAlphaSeeded = nil
DB.BackgroundAlpha = 0.4
local realWindowInfo = GetChatWindowInfo
GetChatWindowInfo = function() return "", 0, 0, 0, 0, 0, true, true, true, false end
Apply()
CHECK(DB.BackgroundAlphaSeeded == nil, "an undownloaded settings record is not seeded from")
CHECK(DB.BackgroundAlpha == 0.4, "background opacity left alone until it arrives", DB.BackgroundAlpha)
GetChatWindowInfo = realWindowInfo
Apply()
CHECK(DB.BackgroundAlphaSeeded == true, "seeded once the record populates")

-- ===========================================================================
-- Short channel tags flow through the AddMessage hook
-- ===========================================================================

chat1:AddMessage("|Hchannel:party|h[Party]|h Ben: inc")
CHECK(chat1.__lastMessage:find("[Party]", 1, true), "tags left alone while the toggle is off")

DB.ShortChannels = true
chat1:AddMessage("|Hchannel:party|h[Party]|h Ben: inc")
CHECK(chat1.__lastMessage:find("[P]", 1, true), "party tag abbreviated", chat1.__lastMessage)
chat1:AddMessage("[2. Trade - Ironforge] Vendor: WTS")
CHECK(chat1.__lastMessage:find("[2]", 1, true), "numbered channel collapsed", chat1.__lastMessage)
CHECK(_G.ChatFrame2.__lastMessage == nil, "the combat log is never hooked")
DB.ShortChannels = false

-- ===========================================================================
-- Footprint: scale, size, font
-- ===========================================================================

DB.ChatScale = 0.85
DB.ResizeChat = true
DB.ChatWidth = 320
DB.ChatHeight = 100
DB.FontSize = 11
Apply()

CHECK(chat1.__scale == 0.85, "scale applied", chat1.__scale)
CHECK(chat1.__w == 320 and chat1.__h == 100, "size applied", tostring(chat1.__w))
CHECK(select(2, chat1:GetFont()) == 11, "font size applied to the main window")
CHECK(select(2, _G.ChatFrame5:GetFont()) == 11, "font size applied to every window")

-- Blizzard re-lays the windows out from its own settings; ours must return
chat1:SetSize(430, 120)
chat1:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
Fire("UPDATE_CHAT_WINDOWS")
CHECK(chat1.__w == 320 and chat1.__h == 100, "size re-asserted after a layout update", tostring(chat1.__w))
CHECK(select(2, chat1:GetFont()) == 11, "font re-asserted after a layout update")

-- Turning the override off restores the size the window had at login
DB.ResizeChat = false
Apply()
CHECK(chat1.__w == 430 and chat1.__h == 120, "original size restored", tostring(chat1.__w))

DB.FontSize = 0
Apply()
CHECK(select(2, chat1:GetFont()) == 14, "Default font size restores Blizzard's saved value")

DB.ChatScale = 1.0
Apply()

-- ===========================================================================
-- Fade & focus
-- ===========================================================================

DB.FadeDelay = 20
DB.KeepChatVisible = false
Apply()
CHECK(chat1.__timeVisible == 20, "fade delay applied", chat1.__timeVisible)
CHECK(chat1.__fading == true, "fading on while Keep Chat Visible is off")

DB.KeepChatVisible = true
Apply()
CHECK(chat1.__fading == false, "Keep Chat Visible stops the fade")
DB.KeepChatVisible = false
Apply()

DB.MouseoverOnly = true
DB.IdleAlpha = 0.15
chat1.__hovered = false
Apply()
CHECK(Driver() ~= nil, "ticker installed once mouseover-only is on")
RunDriver(1.0)
CHECK(math.abs(chat1.__alpha - 0.15) < 0.001, "idles down to the idle opacity", chat1.__alpha)

chat1.__hovered = true
RunDriver(1.0)
CHECK(math.abs(chat1.__alpha - 1) < 0.001, "hovering brings it back to full", chat1.__alpha)

-- Typing counts as reading even with the mouse elsewhere
chat1.__hovered = false
chat1.editBox.__shown = true
chat1.editBox.__focused = true
RunDriver(1.0)
CHECK(math.abs(chat1.__alpha - 1) < 0.001, "an focused edit box holds chat up", chat1.__alpha)
-- ...but a permanently shown edit box with no focus must not pin it there
chat1.editBox.__focused = false
RunDriver(1.0)
CHECK(math.abs(chat1.__alpha - 0.15) < 0.001, "an unfocused edit box does not", chat1.__alpha)
chat1.editBox.__shown = false

-- Combat quiet composes with mouseover rather than overwriting it
DB.CombatQuiet = true
DB.CombatQuietAlpha = 0.05
Fire("PLAYER_REGEN_DISABLED")
RunDriver(1.0)
CHECK(math.abs(chat1.__alpha - 0.05) < 0.001, "combat takes the lower of the two", chat1.__alpha)
chat1.__hovered = true
RunDriver(1.0)
CHECK(math.abs(chat1.__alpha - 1) < 0.001, "hovering still wins in combat", chat1.__alpha)
chat1.__hovered = false
Fire("PLAYER_REGEN_ENABLED")
DB.CombatQuiet = false
Apply()

-- REGRESSION: the tab alpha belongs to FCF_FadeIn/OutChatFrame, which
-- animates it every frame off the same mouse state. Writing it from here at
-- 20Hz is what made the tabs vibrate in game. Nothing in this addon may
-- touch a tab's alpha again.
local tabWritesBefore = tab1.__alphaWrites or 0
DB.MouseoverOnly = true
chat1.__hovered = false
Apply()
RunDriver(1.0)
chat1.__hovered = true
RunDriver(1.0)
chat1.__hovered = false
RunDriver(1.0)
CHECK((tab1.__alphaWrites or 0) == tabWritesBefore,
    "tab alpha is never written while fading the window", tab1.__alphaWrites)

-- And once the alpha has settled the driver stops writing at all, so it can
-- never trade frames with another animation
local settledWrites = chat1.__alphaWrites
RunDriver(1.0)
CHECK(chat1.__alphaWrites == settledWrites,
    "a settled alpha is not re-asserted every tick", chat1.__alphaWrites - settledWrites)

DB.MouseoverOnly = false
Apply()
CHECK(Driver() == nil or Driver().__scripts.OnUpdate == nil, "ticker unhooked once nothing needs it")
CHECK(math.abs(chat1.__alpha - 1) < 0.001, "chat snaps back to full", chat1.__alpha)

-- Hiding the window entirely still works, and secondary tabs come back
DB.ShowChatWindow = false
Apply()
CHECK(chat1.__shown == false, "window hidden")
CHECK(_G.ChatFrame2Tab.__shown == false, "secondary tabs hidden with it")
DB.ShowChatWindow = true
Apply()
CHECK(chat1.__shown and _G.ChatFrame2Tab.__shown, "both restored")

-- Background opacity
DB.BackgroundAlpha = 0
Apply()
CHECK(chat1.__bgAlpha == 0, "background opacity applied", chat1.__bgAlpha)
CHECK(bgAlphaSaved[chat1] == nil, "still never written to Blizzard's saved value")

-- ===========================================================================
-- Channel noise
-- ===========================================================================

CHECK(messageFilters.CHAT_MSG_CHANNEL ~= nil, "channel filter registered")

-- (msg, author, lang, channelString, target, flags, zoneChannelID, index, baseName)
local function WorldLine()
    return FireChannel("WTS", "Vendor", "", "2. Trade - Ironforge", "", "", 2, 2, "Trade")
end
local function CustomLine()
    return FireChannel("hi", "Alt", "", "5. MyGuildAlts", "", "", 0, 5, "MyGuildAlts")
end

CHECK(WorldLine() == false, "world channel passes while unmuted")
DB.MuteWorldChannels = true
CHECK(WorldLine() == true, "world channel muted")
CHECK(CustomLine() == false, "a channel joined by name is not a world channel")

CommanderChat_SetChannelMuted("MyGuildAlts", true)
CHECK(CustomLine() == true, "named mute suppresses it")
CommanderChat_SetChannelMuted("MyGuildAlts", false)
CHECK(CustomLine() == false, "unmute lets it through")
CHECK(next(DB.MutedChannels) == nil, "unmuting clears the entry rather than storing false")
DB.MuteWorldChannels = false

local joined = CommanderChat_JoinedChannels()
CHECK(#joined == 3 and joined[2].name == "Trade", "channel list parsed", #joined)

CommanderChat_LeaveChannel("Trade")
CHECK(leftChannels[1] == "Trade", "leave routed to the client")

-- ===========================================================================
-- Presets
-- ===========================================================================

CommanderChat_ApplyPreset("MINIMAL")
CHECK(DB.MouseoverOnly and DB.ResizeChat and DB.MuteWorldChannels,
    "minimal preset sets the footprint switches")
CHECK(DB.ShowChatButton == false and DB.FontSize == 11, "and the chrome/font")
CHECK(chat1.__w == 330 and chat1.__scale == 0.85, "minimal preset lands on the frame", tostring(chat1.__w))
RunDriver(1.0)
CHECK(chat1.__alpha < 0.2, "minimal preset idles chat almost away", chat1.__alpha)

CommanderChat_ApplyPreset("STANDARD")
CHECK(not DB.MouseoverOnly and not DB.ResizeChat and not DB.ShortChannels,
    "standard preset hands the screen back")
CHECK(chat1.__scale == 1 and chat1.__w == 430, "and the frame with it", tostring(chat1.__w))
CHECK(math.abs(chat1.__alpha - 1) < 0.001, "at full opacity", chat1.__alpha)

-- ===========================================================================

CHECK(cvars.showTimestamps == "none", "timestamps never claimed across the run")
DB.Timestamps = true
Apply()
CHECK(cvars.showTimestamps ~= "none", "timestamps claimed when asked")
DB.Timestamps = false
Apply()
CHECK(cvars.showTimestamps == "none", "and released once")

-- ===========================================================================
-- The replacement window
-- ===========================================================================

DB.ReplaceChatFrame = true
Apply()
local win = _G.CommanderChatWindow
CHECK(win ~= nil and win.__shown, "replacement window built and shown")
CHECK(chat1.__alpha == 0, "Blizzard's frame parked at zero alpha", chat1.__alpha)
CHECK(chat1.__shown, "but still shown, so FrameXML's own logic keeps working")
CHECK(_G.ChatFrame1Tab.__shown == false, "its tabs are down")
CHECK(chat1.editBox.__parent == UIParent,
    "the edit box moved out from under the parked frame so it can still render")
CHECK(_G.ChatFrameMenuButton.__shown == false,
    "the loose chat buttons park too — zero alpha does not reach them")

-- Lines are mirrored out of Blizzard's finished formatting, not re-derived
DB.ShortChannels = false
local mirrored = _G.CommanderChatWindowBody
chat1:AddMessage("|cff00ff00[Guild]|r Ally: pull in 5", 0.25, 1, 0.25)
CHECK(mirrored.__lastMessage == "|cff00ff00[Guild]|r Ally: pull in 5",
    "the formatted line is mirrored verbatim", mirrored.__lastMessage)
CHECK(chat1.__lastMessage == "|cff00ff00[Guild]|r Ally: pull in 5",
    "and still reaches Blizzard's frame underneath")

-- The Blizzard-path driver must stand down so the two never both write alpha
DB.MouseoverOnly = true
Apply()
CHECK(chat1.__alpha == 0, "the parked frame's alpha is left alone", chat1.__alpha)

DB.ReplaceChatFrame = false
DB.MouseoverOnly = false
Apply()
CHECK(win.__shown == false, "replacement hidden when switched off")
CHECK(chat1.__alpha == 1 and chat1.__shown, "Blizzard's frame unparked", chat1.__alpha)
CHECK(_G.ChatFrame1Tab.__shown, "tabs back")
CHECK(chat1.editBox.__parent == chat1, "edit box handed back to its own frame")
CHECK(_G.ChatFrameMenuButton.__shown, "and the loose buttons come back")

-- ===========================================================================
-- The master switch
-- ===========================================================================

CommanderChat_ApplyPreset("MINIMAL")
DB.Timestamps = true
DB.ReplaceChatFrame = true
Apply()
CHECK(cvars.showTimestamps ~= "none" and chat1.__scale == 0.85, "module is doing its thing")

DB.Enabled = false
Apply()
CHECK(chat1.__shown and chat1.__alpha == 1, "chat window visible again", chat1.__alpha)
CHECK(chat1.__scale == 1, "scale released", chat1.__scale)
CHECK(chat1.__w == 430 and chat1.__h == 120, "size released", tostring(chat1.__w))
CHECK(select(2, chat1:GetFont()) == 14, "font released")
CHECK(cvars.showTimestamps == "none", "timestamp CVar released")
CHECK(chat1.__fading == true and chat1.__timeVisible == 120, "fading back to Blizzard's default")
CHECK(chat1.__bgAlpha == savedWindowAlpha, "background opacity back to Blizzard's saved value", chat1.__bgAlpha)
CHECK(_G.CommanderChatWindow.__shown == false, "replacement window down")
CHECK(chat1.editBox.__parent == chat1, "edit box home")
CHECK(_G.ChatFrameMenuButton.__shown, "chat buttons back")
CHECK(Driver() == nil or Driver().__scripts.OnUpdate == nil, "no ticker running")

-- Inert, not merely idle: the two permanent hooks must pass everything through
DB.MuteWorldChannels = true
CHECK(WorldLine() == false, "the channel filter passes everything while disabled")
DB.ShortChannels = true
chat1:AddMessage("[Party] Ben: inc")
CHECK(chat1.__lastMessage:find("[Party]", 1, true), "the AddMessage hook stops rewriting")
CHECK(mirrored.__lastMessage ~= "[Party] Ben: inc", "and stops mirroring")

DB.Enabled = true
Apply()
CHECK(chat1.__scale == 0.85, "and it all comes back on")
DB.Enabled = false
Apply()

CHECK(#caughtErrors == 0, "no errors across the run", caughtErrors[1])

io.write(string.format("[chat] %d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
