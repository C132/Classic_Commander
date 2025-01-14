CommanderConsoleDB = _G.CommanderConsoleDB or {}

COMMANDER_CONSOLE_EVENTS = {
    UPDATE = "COMMANDER_CONSOLE_UPDATE"
}

local DefaultSettings = {
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
    panel.name = "Commander Console"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Commander Console Settings")

    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetText("Configure Commander Console options below.")
    
    local resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetButton:SetSize(100, 22)
    resetButton:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)
    resetButton:SetText("Reset")
    resetButton:SetScript("OnClick", function()
        Reset()
        print("Commander Console Reset")
    end)

    
    return panel
end

local function OnUpdate()

end

local function OnAwake()
    print("Commander Console Awake")
    local panel = CreateOptionsPanel()
    local category = Settings.RegisterCanvasLayoutSubcategory(MainCategory, panel, "Commander Console")
    local categoryID = category:GetID()
    Settings.RegisterAddOnCategory(category)
    InitializeSlashCommands(categoryID)
    AddListener(COMMANDER_CONSOLE_EVENTS.UPDATE, OnUpdate)
end

local function OnDestroy()
    print("Commander Console Destroy")
end

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