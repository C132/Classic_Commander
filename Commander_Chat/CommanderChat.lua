local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
local loaded = false

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
    elseif event == "PLAYER_LOGOUT" then
        OnDestroy()
    elseif loaded then
        OnUpdate()
    end
end)

local chatElements = {
    ChatFrameChannelButton,
    ChatFrameMenuButton,
    ChatFrame1ButtonFrame,
    FriendsMicroButton
}

function UpdateChatVisibility()
    local method = CommanderChatDB.ShowChatButton and "Show" or "Hide"
    for _, element in ipairs(chatElements) do
        element[method](element)
    end

    method = CommanderChatDB.ShowChatWindow and "Show" or "Hide"
    ChatFrame1:SetShown(method == "Show")   
end