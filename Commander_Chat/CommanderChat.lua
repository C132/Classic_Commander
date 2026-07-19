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
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame and chatFrame.AddMessage and not hookedAddMessage[chatFrame] then
            hookedAddMessage[chatFrame] = chatFrame.AddMessage
            chatFrame.AddMessage = function(self, text, ...)
                if CommanderChatDB.ShortChannels and type(text) == "string" then
                    text = AbbreviateChannels(text)
                end
                return hookedAddMessage[chatFrame](self, text, ...)
            end
        end
    end
end

local function ApplyReadability()
    if SetCVar then
        SetCVar("showTimestamps", CommanderChatDB.Timestamps and "%H:%M " or "none")
    end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame and chatFrame.SetFading then
            chatFrame:SetFading(not CommanderChatDB.KeepChatVisible)
        end
    end
end

local function UpdateChatVisibility()
    local isVisible = CommanderChatDB.ShowChatButton
    for _, element in ipairs(chatElements) do
        element:SetShown(isVisible)
        element:SetAlpha(isVisible and 1 or 0)
    end

    isVisible = CommanderChatDB.ShowChatWindow
    -- Combat quiet dims (rather than hides) so incoming lines still land
    local windowAlpha = 1
    if CommanderChatDB.CombatQuiet and inCombat then
        windowAlpha = 0.15
    end
    ChatFrame1:SetShown(isVisible)
    ChatFrame1:SetAlpha(isVisible and windowAlpha or 0)
    ChatFrame1Tab:SetShown(isVisible)
    ChatFrame1Tab:SetAlpha(isVisible and windowAlpha or 0)
    
    local chatFrame = _G["ChatFrame1"]
    if chatFrame and chatFrame.Tab then
        chatFrame.Tab:SetShown(isVisible)
        chatFrame.Tab:SetAlpha(isVisible and 1 or 0)
    end
    
    for i = 2, NUM_CHAT_WINDOWS do
        local tab = _G["ChatFrame" .. i .. "Tab"]
        if tab and tab:IsShown() then
            tab:SetShown(isVisible)
            tab:SetAlpha(isVisible and 1 or 0)
        end
    end
end

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

local function OnDestroy() end

local function OnUpdate()
    UpdateChatVisibility()
    ApplyReadability()
end

local function OnAwake()
    InstallChannelTagHooks()
    Commander.AddListener(COMMANDER_CHAT_EVENTS.UPDATE, OnUpdate)
    Commander.Notify(COMMANDER_CHAT_EVENTS.UPDATE)
end

frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

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
    elseif event == "CHAT_MSG_WHISPER" then
        PlaySoundPing("whisper")
    elseif event == "CHAT_MSG_PARTY" then
        PlaySoundPing("party")
    elseif loaded and CommanderChatDB.ShowChatWindow == false then
        OnUpdate()
    end
end)