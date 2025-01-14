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

local function UpdateChatVisibility()
    local isVisible = CommanderChatDB.ShowChatButton
    for _, element in ipairs(chatElements) do
        element:SetShown(isVisible)
        element:SetAlpha(isVisible and 1 or 0)
    end

    isVisible = CommanderChatDB.ShowChatWindow
    ChatFrame1:SetShown(isVisible)
    ChatFrame1:SetAlpha(isVisible and 1 or 0)
    ChatFrame1Tab:SetShown(isVisible)
    ChatFrame1Tab:SetAlpha(isVisible and 1 or 0)
    
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

local function OnDestroy() end

local function OnUpdate()
    UpdateChatVisibility()
end

local function OnAwake() 
    AddListener(COMMANDER_CHAT_EVENTS.UPDATE, OnUpdate)
    Notify(COMMANDER_CHAT_EVENTS.UPDATE)
end

frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        OnAwake()
        loaded = true
        OnUpdate()
    elseif event == "PLAYER_LOGOUT" then
        OnDestroy()
    elseif loaded and CommanderChatDB.ShowChatWindow == false then
        OnUpdate()
    end
end)