CommanderChatDB = _G.CommanderChatDB or {}

local showChatWindowCheckbox
local showChatButtonCheckbox

COMMANDER_CHAT_EVENTS = {
    UPDATE = "COMMANDER_CHAT_UPDATE"
}

local DefaultSettings = {
    ShowChatWindow = true,
    ShowChatButton = true,
}

for key, value in pairs(DefaultSettings) do
    if CommanderChatDB[key] == nil then
        CommanderChatDB[key] = value
    end
end

local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
local loaded = false

local function Reset()
    print("Resetting Commander Chat")
    for key, value in pairs(DefaultSettings) do
        CommanderChatDB[key] = value
    end
    Notify(COMMANDER_CHAT_EVENTS.UPDATE)
end

local function InitializeSlashCommands(categoryID)
    SLASH_CC1 = "/cc"
    SlashCmdList["CC"] = function(msg)
        msg = msg:lower()
        if msg == "" then
            Settings.OpenToCategory(categoryID)
        elseif msg == "reset" then
            Reset()
            print("Commander Chat Reset")
        else
            print("Usage: /cc [reset]")
        end
    end
end

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Commander Chat"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Commander Chat Settings")

    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetText("Configure Commander Chat options below.")

    showChatWindowCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    showChatWindowCheckbox:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)
    showChatWindowCheckbox.Text:SetText("Show Chat Window")
    showChatWindowCheckbox:SetChecked(CommanderChatDB.ShowChatWindow)
    showChatWindowCheckbox:SetScript("OnClick", function(self)
        CommanderChatDB.ShowChatWindow = self:GetChecked()
        Notify(COMMANDER_CHAT_EVENTS.UPDATE)
    end)

    showChatButtonCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate") 
    showChatButtonCheckbox:SetPoint("TOPLEFT", showChatWindowCheckbox, "BOTTOMLEFT", 0, -8)
    showChatButtonCheckbox.Text:SetText("Show Chat Button")
    showChatButtonCheckbox:SetChecked(CommanderChatDB.ShowChatButton)
    showChatButtonCheckbox:SetScript("OnClick", function(self)
        CommanderChatDB.ShowChatButton = self:GetChecked()
        Notify(COMMANDER_CHAT_EVENTS.UPDATE)
    end)

    return panel
end

local function OnUpdate()
    if showChatWindowCheckbox then
        showChatWindowCheckbox:SetChecked(CommanderChatDB.ShowChatWindow)
    end
    if showChatButtonCheckbox then
        showChatButtonCheckbox:SetChecked(CommanderChatDB.ShowChatButton)
    end
end

local function OnAwake()
    local panel = CreateOptionsPanel()
    local category = Settings.RegisterCanvasLayoutSubcategory(MainCategory, panel, "Commander Chat")
    local categoryID = category:GetID()
    Settings.RegisterAddOnCategory(category)
    InitializeSlashCommands(categoryID)
    AddListener(COMMANDER_CHAT_EVENTS.UPDATE, OnUpdate)
end

local function OnDestroy() end

local function OnEvent(self, event)
    if event == "PLAYER_LOGIN" then
        OnAwake()
        loaded = true
    elseif event == "PLAYER_LOGOUT" then
        OnDestroy()
    elseif loaded then
        OnUpdate()
    end
end

frame:SetScript("OnEvent", OnEvent)