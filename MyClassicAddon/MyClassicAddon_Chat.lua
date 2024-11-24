local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

local function OnStart()
    AddListener(MY_CLASSIC_ADDON_EVENTS.CHAT_VISIBILITY_CHANGED, UpdateChatVisibility)
    UpdateChatVisibility()
end

frame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "MyClassicAddon" then
        -- OnAwake() was empty, so we removed it
    elseif event == "PLAYER_ENTERING_WORLD" then
        OnStart()
    end
end)

local chatElements = {
    ChatFrameChannelButton,
    ChatFrameMenuButton,
    ChatFrame1ButtonFrame,
    FriendsMicroButton
}

function UpdateChatVisibility()
    local method = Config.ShowChatWindow and "Show" or "Hide"
    for _, element in ipairs(chatElements) do
        element[method](element)
    end
end