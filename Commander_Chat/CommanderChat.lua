local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_STARTED_MOVING")
frame:RegisterEvent("PLAYER_STOPPED_MOVING")
frame:RegisterEvent("CHAT_MSG_CHANNEL")
frame:RegisterEvent("CHAT_MSG_SAY")
frame:RegisterEvent("CHAT_MSG_YELL")
frame:RegisterEvent("CHAT_MSG_WHISPER")
frame:RegisterEvent("CHAT_MSG_PARTY")
frame:RegisterEvent("CHAT_MSG_RAID")
frame:RegisterEvent("CHAT_MSG_GUILD")
frame:RegisterEvent("CHAT_MSG_OFFICER")
frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:RegisterEvent("CHAT_MSG_EMOTE")
frame:RegisterEvent("CHAT_MSG_TEXT_EMOTE")
frame:RegisterEvent("CHAT_MSG_MONSTER_SAY")
frame:RegisterEvent("CHAT_MSG_MONSTER_YELL")
frame:RegisterEvent("CHAT_MSG_MONSTER_WHISPER")
frame:RegisterEvent("CHAT_MSG_MONSTER_EMOTE")
frame:RegisterEvent("CHAT_MSG_ACHIEVEMENT")
frame:RegisterEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL")

local loaded = false

local chatElements = {
    ChatFrameChannelButton,
    ChatFrameMenuButton,
    ChatFrame1ButtonFrame,
    FriendsMicroButton
}

-- ---------------------------------------------------------------------------
-- Readability: short channel tags, timestamps, fade control, combat quiet
-- ---------------------------------------------------------------------------
local inCombat = false
local hiddenTabs = {}

local function NumWindows()
    return NUM_CHAT_WINDOWS or 10
end

local CHANNEL_TAGS = {
    { "%[Party Leader%]", "[PL]" },
    { "%[Party%]", "[P]" },
    { "%[Raid Leader%]", "[RL]" },
    { "%[Raid Warning%]", "[RW]" },
    { "%[Raid%]", "[R]" },
    { "%[Guild%]", "[G]" },
    { "%[Officer%]", "[O]" },
}

local function AbbreviateChannels(text)
    -- Most lines carry no channel tag at all — skip the eight-pattern
    -- gsub chain unless a bracket is even present (plain find, no pattern)
    if not text:find("[", 1, true) then return text end
    for _, rule in ipairs(CHANNEL_TAGS) do
        text = text:gsub(rule[1], rule[2])
    end
    -- "[2. Trade - City]" -> "[2]"
    text = text:gsub("%[(%d+)%.%s?[^%]]*%]", "[%1]")
    return text
end

-- Wrap AddMessage once per window; the DB flag gates per message, so the
-- toggle applies instantly without rehooking
local hookedAddMessage = {}
local function InstallChannelTagHooks()
    for i = 1, NumWindows() do
        local chatFrame = _G["ChatFrame" .. i]
        -- Never hook the combat log (ChatFrame2): its lines cannot carry a
        -- channel tag, and wrapping its AddMessage makes every combat-log
        -- line's history-buffer allocation land in THIS addon's memory
        -- accounting — dozens of lines per second of phantom retention
        if chatFrame == ChatFrame2 then chatFrame = nil end
        if chatFrame and chatFrame.AddMessage and not hookedAddMessage[chatFrame] then
            hookedAddMessage[chatFrame] = chatFrame.AddMessage
            chatFrame.AddMessage = function(self, text, r, g, b, ...)
                if CommanderChatDB.Enabled and CommanderChatDB.ShortChannels
                    and type(text) == "string" then
                    text = AbbreviateChannels(text)
                end
                -- The replacement window is fed from here rather than from the
                -- chat events: by this point Blizzard has done every bit of
                -- the formatting, so the mirror inherits all of it for free
                if self == ChatFrame1 and CommanderChatWindow_Receive then
                    CommanderChatWindow_Receive(text, r, g, b)
                end
                return hookedAddMessage[chatFrame](self, text, r, g, b, ...)
            end
        end
    end
end

local function ApplyReadability()
    -- Only write the timestamps CVar while this addon owns the setting:
    -- turning our toggle on claims it, turning it off releases it once.
    -- A user who configured timestamps outside the addon is never clobbered.
    if SetCVar then
        if CommanderChatDB.Timestamps then
            SetCVar("showTimestamps", "%H:%M ")
            CommanderChatDB.TimestampsApplied = true
        elseif CommanderChatDB.TimestampsApplied then
            SetCVar("showTimestamps", "none")
            CommanderChatDB.TimestampsApplied = nil
        end
    end
    local keepVisible = CommanderChatDB.KeepChatVisible
    for i = 1, NumWindows() do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame and chatFrame.SetFading then
            chatFrame:SetFading(not keepVisible)
        end
        -- How long a line stays on screen before it fades. Shorter is the
        -- whole point of a small chat window: the last few lines are live,
        -- everything older gets out of the way until you scroll or hover.
        if chatFrame and chatFrame.SetTimeVisible and not keepVisible then
            chatFrame:SetTimeVisible(CommanderChatDB.FadeDelay or 120)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Footprint: how much of the screen chat is allowed to occupy
-- ---------------------------------------------------------------------------
-- ChatFrame1's size is Edit Mode's on this client (FCF_RestorePositionAndDimensions
-- early-returns for the default window and the size lives in the layout's
-- WidthHundreds/HeightHundreds settings), so ours only holds until the next
-- layout apply — re-assert on the chat window events Blizzard fires then.
-- Scale is unclaimed: the chat system has no Edit Mode size setting, and
-- EditModeSystemMixin:SetScaleOverride compensates the anchor offsets so the
-- window stays put as it shrinks.
local originalSize = nil
local fontApplied = false

local function BlizzardFontSize(id)
    if type(GetChatWindowInfo) ~= "function" then return 14 end
    local size = select(2, GetChatWindowInfo(id))
    if not size or size == 0 then return 14 end
    return size
end

local function ApplyFootprint()
    local chatFrame = ChatFrame1
    if not chatFrame then return end

    chatFrame:SetScale(CommanderChatDB.ChatScale or 1)

    if CommanderChatDB.ResizeChat then
        -- Remember what the window was before we ever touched it, so turning
        -- the override off restores the real size instead of stranding
        -- whatever the sliders last happened to read
        if not originalSize then
            originalSize = { chatFrame:GetWidth(), chatFrame:GetHeight() }
        end
        local width = CommanderChatDB.ChatWidth or 430
        local height = CommanderChatDB.ChatHeight or 120
        if math.abs(chatFrame:GetWidth() - width) > 0.5
            or math.abs(chatFrame:GetHeight() - height) > 0.5 then
            chatFrame:SetSize(width, height)
        end
    elseif originalSize then
        chatFrame:SetSize(originalSize[1], originalSize[2])
        originalSize = nil
    end

    local size = CommanderChatDB.FontSize or 0
    if size > 0 or fontApplied then
        for i = 1, NumWindows() do
            local window = _G["ChatFrame" .. i]
            if window and window.GetFont then
                local file, current, flags = window:GetFont()
                -- 0 means "hands off" — restore what Blizzard has saved for
                -- the window rather than leaving our last value stuck on it
                local target = (size > 0) and size or BlizzardFontSize(i)
                if file and current and math.abs(current - target) > 0.1 then
                    window:SetFont(file, target, flags)
                end
            end
        end
        fontApplied = size > 0
    end
end

-- The boxed background art and its border. FCF_SetWindowAlpha also parks the
-- value in frame.oldAlpha, which is exactly the target Blizzard's own
-- mouseover fade returns to — so this survives hovering instead of being
-- undone by it. doNotSave keeps Blizzard's saved opacity intact underneath.
local function ApplyBackgroundAlpha()
    -- Adopt whatever opacity the window already has the first time we run, so
    -- installing the addon never restyles a chat frame the user had tuned in
    -- Blizzard's own chat menu. From then on the slider owns the value.
    if not CommanderChatDB.BackgroundAlphaSeeded and type(GetChatWindowInfo) == "function" then
        -- UPDATE_CHAT_WINDOWS can arrive before the server has sent the chat
        -- settings down, and an uninitialized window reports a blank name and
        -- a zero alpha. Only seed off a populated record, and stay unseeded
        -- until one shows up, or a first login would adopt a phantom 0%.
        local name, _, _, _, _, saved = GetChatWindowInfo(1)
        if type(name) == "string" and name ~= "" and type(saved) == "number" then
            CommanderChatDB.BackgroundAlpha = saved
            CommanderChatDB.BackgroundAlphaSeeded = true
        end
    end

    local alpha = CommanderChatDB.BackgroundAlpha
    if alpha == nil or type(FCF_SetWindowAlpha) ~= "function" then return end
    for i = 1, NumWindows() do
        local window = _G["ChatFrame" .. i]
        if window and window:IsShown() then
            FCF_SetWindowAlpha(window, alpha, true)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Focus: mouseover-only chat and combat quiet
-- ---------------------------------------------------------------------------
-- Scoped deliberately to the chat frame's OWN alpha and nothing else.
--
-- An earlier version also drove the tab alpha, which is a fight this addon
-- cannot win and should never have picked: FCF_OnUpdate runs every frame and
-- animates each tab toward tab.noMouseAlpha / tab.mouseOverAlpha through
-- UIFrameFadeIn/Out off the same mouse state we were reading. Two animations
-- writing one alpha at different rates is exactly the vibration that showed
-- up in game. FrameXML wins by default and it is right to: this client
-- already ships CHAT_FRAME_TAB_*_NOMOUSE_ALPHA at 0, so idle tabs are
-- invisible on their own and there was nothing to add.
--
-- The frame's own alpha is genuinely unclaimed — FCF_FadeIn/OutChatFrame
-- touches the CHAT_FRAME_TEXTURES, the tab, and the button frame, never
-- chatFrame:SetAlpha — so this one write is safe to own.
local DRIVER_INTERVAL = 0.05
local FADE_RATE = 4.0 -- alpha per second; a full sweep in a quarter second

local driver = CreateFrame("Frame")
local driverRunning = false
local driverElapsed = 0
local currentAlpha = 1

-- Nil-safe: the replacement lives in its own file, and a load failure there
-- must degrade to the Blizzard-frame path, not error on every settings change
local function ReplacementActive()
    return CommanderChatWindow_IsActive and CommanderChatWindow_IsActive()
end

local function IsChatHovered()
    local chatFrame = ChatFrame1
    if not chatFrame or not chatFrame:IsShown() then return false end
    -- The same generous insets FCF_OnUpdate uses for its own fade-in, so our
    -- hover region agrees with Blizzard's instead of flickering against it
    if chatFrame:IsMouseOver(28, -2, -2, 2) then return true end
    -- Focus, not merely shown: the "im" chat style leaves the edit box up
    -- permanently, which would pin chat at full alpha forever
    local editBox = chatFrame.editBox
    if editBox and editBox:IsShown() and editBox:HasFocus() then return true end
    if chatFrame.buttonFrame and chatFrame.buttonFrame:IsShown()
        and chatFrame.buttonFrame:IsMouseOver() then
        return true
    end
    return false
end

local function ResolveAlpha()
    local alpha = 1
    if CommanderChatDB.CombatQuiet and inCombat then
        alpha = CommanderChatDB.CombatQuietAlpha or 0.15
    end
    if CommanderChatDB.MouseoverOnly then
        if IsChatHovered() then
            alpha = 1
        else
            local idle = CommanderChatDB.IdleAlpha or 0.2
            if idle < alpha then alpha = idle end
        end
    end
    return alpha
end

local function ApplyAlpha(alpha)
    if ChatFrame1 then ChatFrame1:SetAlpha(alpha) end
    for i = 2, NumWindows() do
        local secondary = _G["ChatFrame" .. i]
        if secondary and secondary:IsShown() then secondary:SetAlpha(alpha) end
    end
end

local function DriverTick(_, elapsed)
    driverElapsed = driverElapsed + elapsed
    if driverElapsed < DRIVER_INTERVAL then return end
    local step = driverElapsed * FADE_RATE
    driverElapsed = 0

    local target = ResolveAlpha()
    if currentAlpha < target then
        currentAlpha = math.min(currentAlpha + step, target)
    elseif currentAlpha > target then
        currentAlpha = math.max(currentAlpha - step, target)
    else
        -- Settled, and nothing else writes this value — so stop writing it.
        -- Re-asserting a stable alpha every tick is what turns a cooperating
        -- animation into a fighting one.
        return
    end
    ApplyAlpha(currentAlpha)
end

-- The ticker exists only for mouseover-only. With it off, the alpha is static
-- and the OnUpdate is unhooked entirely.
local function UpdateDriver()
    local needed = (CommanderChatDB.Enabled
        and CommanderChatDB.ShowChatWindow ~= false
        and CommanderChatDB.MouseoverOnly
        and not ReplacementActive()) and true or false
    if needed == driverRunning then return end
    driverRunning = needed
    driver:SetScript("OnUpdate", needed and DriverTick or nil)
    driverElapsed = 0
end

local function UpdateChatVisibility()
    -- The replacement window parks ChatFrame1 itself; leave it alone here so
    -- the two are never both writing the same alpha
    if ReplacementActive() then
        UpdateDriver()
        return
    end

    local isVisible = CommanderChatDB.ShowChatButton
    for _, element in ipairs(chatElements) do
        element:SetShown(isVisible)
        element:SetAlpha(isVisible and 1 or 0)
    end

    isVisible = CommanderChatDB.ShowChatWindow
    ChatFrame1:SetShown(isVisible)
    ChatFrame1Tab:SetShown(isVisible)

    local chatFrame = _G["ChatFrame1"]
    if chatFrame and chatFrame.Tab then
        chatFrame.Tab:SetShown(isVisible)
    end

    -- Remember which secondary tabs WE hid: on re-show, `IsShown()` is
    -- false for exactly the tabs we need to restore, so filtering on it
    -- when showing would leave them hidden forever
    for i = 2, NumWindows() do
        local tab = _G["ChatFrame" .. i .. "Tab"]
        if tab then
            if not isVisible then
                if tab:IsShown() then
                    hiddenTabs[i] = true
                    tab:SetShown(false)
                end
            elseif hiddenTabs[i] then
                hiddenTabs[i] = nil
                tab:SetShown(true)
            end
        end
    end

    if isVisible then
        -- Snap on a settings change so the panel's effect is immediate; the
        -- driver eases every later transition
        currentAlpha = ResolveAlpha()
        ApplyAlpha(currentAlpha)
    else
        ChatFrame1:SetAlpha(0)
    end
    UpdateDriver()
end

-- ---------------------------------------------------------------------------
-- Channel noise: mute the world channels without leaving them
-- ---------------------------------------------------------------------------
-- CHAT_MSG_CHANNEL's arg7 is the zoneChannelID — nonzero only for the
-- server's built-in zone channels (General, Trade, LocalDefense,
-- LookingForGroup, ...) and zero for anything the player joined by name.
-- That split is locale-proof, which name matching would not be.
local function ChannelMessageFilter(_, _, _, _, _, _, _, _, zoneChannelID, _, channelBaseName)
    if not CommanderChatDB.Enabled then return false end
    if CommanderChatDB.MuteWorldChannels and (tonumber(zoneChannelID) or 0) > 0 then
        return true
    end
    local muted = CommanderChatDB.MutedChannels
    if muted and type(channelBaseName) == "string" and muted[channelBaseName:lower()] then
        return true
    end
    return false
end

local function InstallChannelFilters()
    -- Registered once and left in place: the filter reads the DB per message,
    -- so toggling a setting takes effect without add/remove churn. The modern
    -- entry point is ChatFrameUtil; the global is a deprecation shim gated on
    -- the loadDeprecationFallbacks CVar, so it may not exist.
    local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
        or ChatFrame_AddMessageEventFilter
    if type(add) == "function" then
        add("CHAT_MSG_CHANNEL", ChannelMessageFilter)
    end
end

-- Parsed defensively: GetChannelList returns a flat run of (id, name) with a
-- disabled flag between entries on some builds, so walk for number+string
-- pairs rather than assuming a stride.
function CommanderChat_JoinedChannels()
    local list = {}
    if type(GetChannelList) ~= "function" then return list end
    local raw = { GetChannelList() }
    local i = 1
    while i <= #raw do
        if type(raw[i]) == "number" and type(raw[i + 1]) == "string" and raw[i + 1] ~= "" then
            list[#list + 1] = { id = raw[i], name = raw[i + 1] }
            i = i + 2
        else
            i = i + 1
        end
    end
    return list
end

function CommanderChat_SetChannelMuted(name, muted)
    if type(name) ~= "string" or name == "" then return end
    CommanderChatDB.MutedChannels = CommanderChatDB.MutedChannels or {}
    CommanderChatDB.MutedChannels[name:lower()] = muted or nil
    print(string.format("Commander Chat: %s is now %s",
        name, muted and "muted" or "unmuted"))
end

function CommanderChat_LeaveChannel(name)
    if type(name) ~= "string" or name == "" then return end
    if type(LeaveChannelByName) ~= "function" then
        print("Commander Chat: this client offers no way to leave a channel from an addon")
        return
    end
    LeaveChannelByName(name)
    print("Commander Chat: left " .. name)
end

function CommanderChat_ReportChannels()
    local list = CommanderChat_JoinedChannels()
    if #list == 0 then
        print("Commander Chat: no channels joined")
        return
    end
    local muted = CommanderChatDB.MutedChannels or {}
    print("Commander Chat: joined channels")
    for _, channel in ipairs(list) do
        print(string.format("  %d. %s%s", channel.id, channel.name,
            muted[channel.name:lower()] and " |cffff7f7f(muted)|r" or ""))
    end
    if CommanderChatDB.MuteWorldChannels then
        print("  |cffffd100World channels are muted|r — you can still post to them")
    end
end

function CommanderChat_InCombat()
    return inCombat
end

-- ---------------------------------------------------------------------------
-- Presets: one click between a full chat window and a footnote
-- ---------------------------------------------------------------------------
local PRESETS = {
    MINIMAL = {
        ResizeChat = true, ChatWidth = 330, ChatHeight = 110,
        ChatScale = 0.85, FontSize = 11,
        MouseoverOnly = true, IdleAlpha = 0.15, FadeDelay = 20,
        ShowChatButton = false, BackgroundAlpha = 0,
        KeepChatVisible = false, CombatQuiet = true,
        ShortChannels = true, MuteWorldChannels = true,
    },
    STANDARD = {
        ResizeChat = false, ChatScale = 1.0, FontSize = 0,
        MouseoverOnly = false, IdleAlpha = 0.2, FadeDelay = 120,
        ShowChatButton = true, BackgroundAlpha = 0.25,
        KeepChatVisible = false, CombatQuiet = false,
        ShortChannels = false, MuteWorldChannels = false,
    },
}

function CommanderChat_ApplyPreset(name)
    local preset = PRESETS[name]
    if not preset then return end
    for key, value in pairs(preset) do
        CommanderChatDB[key] = value
    end
    Commander.Notify(COMMANDER_CHAT_EVENTS.UPDATE)
    print(string.format("Commander Chat: applied the %s layout",
        name == "MINIMAL" and "minimal" or "standard"))
end

-- ---------------------------------------------------------------------------
-- The master switch
-- ---------------------------------------------------------------------------
-- Enabled = false has to leave the client exactly as it found it, because the
-- whole point of the flag is being able to rule this addon out while
-- diagnosing something else. Everything below is the inverse of every write
-- this file makes. The two hooks that cannot be removed once installed (the
-- AddMessage wrapper and the CHAT_MSG_CHANNEL filter) both read the DB per
-- call and pass everything through when disabled, so they are inert too.
local function RestoreBlizzard()
    if CommanderChatWindow_Restore then CommanderChatWindow_Restore() end

    driverRunning = false
    driver:SetScript("OnUpdate", nil)

    for _, element in ipairs(chatElements) do
        element:SetShown(true)
        element:SetAlpha(1)
    end

    for i = 1, NumWindows() do
        local window = _G["ChatFrame" .. i]
        if window then
            window:SetAlpha(1)
            window:EnableMouse(true)
            if window.SetFading then window:SetFading(true) end
            if window.SetTimeVisible then window:SetTimeVisible(120) end
        end
    end
    for index in pairs(hiddenTabs) do
        local tab = _G["ChatFrame" .. index .. "Tab"]
        if tab then tab:SetShown(true) end
        hiddenTabs[index] = nil
    end
    if ChatFrame1 then ChatFrame1:SetShown(true) end
    if ChatFrame1Tab then ChatFrame1Tab:SetShown(true) end

    -- Give back the size, scale and font we took
    if ChatFrame1 then
        ChatFrame1:SetScale(1)
        if originalSize then
            ChatFrame1:SetSize(originalSize[1], originalSize[2])
            originalSize = nil
        end
    end
    if fontApplied then
        for i = 1, NumWindows() do
            local window = _G["ChatFrame" .. i]
            if window and window.GetFont then
                local file, _, flags = window:GetFont()
                if file then window:SetFont(file, BlizzardFontSize(i), flags) end
            end
        end
        fontApplied = false
    end

    -- Blizzard's saved opacity was never written over, so handing it back is
    -- just re-applying what has been sitting under ours the whole time
    if type(FCF_SetWindowAlpha) == "function" and type(GetChatWindowInfo) == "function" then
        for i = 1, NumWindows() do
            local window = _G["ChatFrame" .. i]
            if window and window:IsShown() then
                local saved = select(6, GetChatWindowInfo(i))
                FCF_SetWindowAlpha(window, type(saved) == "number" and saved or 0.25, true)
            end
        end
    end

    if SetCVar and CommanderChatDB.TimestampsApplied then
        SetCVar("showTimestamps", "none")
        CommanderChatDB.TimestampsApplied = nil
    end
end

local function OnDestroy() end

local function OnUpdate()
    if not CommanderChatDB.Enabled then
        RestoreBlizzard()
        return
    end
    if CommanderChatWindow_Update then CommanderChatWindow_Update() end
    UpdateChatVisibility()
    ApplyReadability()
    ApplyFootprint()
    ApplyBackgroundAlpha()
end

function CommanderChat_ToggleEnabled()
    CommanderChatDB.Enabled = not CommanderChatDB.Enabled
    Commander.Notify(COMMANDER_CHAT_EVENTS.UPDATE)
    print("Commander Chat: " .. (CommanderChatDB.Enabled
        and "enabled" or "disabled — Blizzard's chat restored"))
end

local function OnAwake()
    InstallChannelTagHooks()
    InstallChannelFilters()
    Commander.AddListener(COMMANDER_CHAT_EVENTS.UPDATE, OnUpdate)
    Commander.Notify(COMMANDER_CHAT_EVENTS.UPDATE)
end

frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UPDATE_CHAT_WINDOWS")
frame:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS")
frame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
pcall(frame.RegisterEvent, frame, "CHAT_MSG_BN_WHISPER")

local function PlaySoundPing(soundType)
    local soundKit, channel

    if soundType == "whisper" and CommanderChatDB.SoundPingWhisper then
        soundKit = SOUNDKIT[CommanderChatDB.WhisperSound or "IG_CHARACTER_INFO_TAB"]
        channel = CommanderChatDB.SoundChannel or "Master"
    elseif soundType == "party" and CommanderChatDB.SoundPingParty then
        soundKit = SOUNDKIT[CommanderChatDB.PartySound or "IG_CHARACTER_INFO_TAB"]
        channel = CommanderChatDB.SoundChannel or "Master"
    end

    if soundKit and channel then
        -- Play the sound directly - volume is controlled by the game's sound settings
        PlaySound(soundKit, channel)
    end
end

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        OnAwake()
        loaded = true
        OnUpdate()
    elseif event == "PLAYER_LOGOUT" then
        OnDestroy()
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        UpdateChatVisibility()
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        UpdateChatVisibility()
    elseif event == "UPDATE_CHAT_WINDOWS" or event == "UPDATE_FLOATING_CHAT_WINDOWS"
        or event == "PLAYER_ENTERING_WORLD" then
        -- Blizzard re-lays out the windows from its own saved settings here
        -- (an Edit Mode layout apply lands on the same path), which puts the
        -- default size and font back. Re-assert, but leave the alpha driver
        -- alone so a hover in progress is not interrupted.
        if loaded and CommanderChatDB.Enabled then
            ApplyFootprint()
            ApplyBackgroundAlpha()
            ApplyReadability()
        end
    elseif event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER" then
        PlaySoundPing("whisper")
    elseif event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" then
        PlaySoundPing("party")
    elseif loaded and CommanderChatDB.ShowChatWindow == false then
        -- Blizzard re-shows chat elements on new messages; keep them
        -- hidden. Visibility only — no need to re-run CVar/fading writes
        -- on every incoming chat line.
        UpdateChatVisibility()
    end
end)
