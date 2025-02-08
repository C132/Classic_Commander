CommanderWhoDB = _G.CommanderWhoDB or {}

local showWhoWindowCheckbox
local showWhoButtonCheckbox

COMMANDER_WHO_EVENTS = {
    UPDATE = "COMMANDER_WHO_UPDATE"
}

local DefaultSettings = {
    ShowWhoWindow = true,
    ShowWhoButton = true,
    MaxWhisperCount = 50,  -- Add safety limit for max whispers
    WhisperDelay = 0.5,   -- Delay between whispers in seconds
}

for key, value in pairs(DefaultSettings) do
    if CommanderWhoDB[key] == nil then
        CommanderWhoDB[key] = value
    end
end

local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
local loaded = false

local function Reset()
    print("Resetting Commander Who")
    for key, value in pairs(DefaultSettings) do
        CommanderWhoDB[key] = value
    end
    Notify(COMMANDER_WHO_EVENTS.UPDATE)
end

local function InitializeSlashCommands(categoryID)
    SLASH_CW1 = "/cw"
    SlashCmdList["CW"] = function(msg)
        msg = msg:lower()
        if msg == "" then
            Settings.OpenToCategory(categoryID)
        elseif msg == "reset" then
            Reset()
            print("Commander Who Reset")
        else
            print("Usage: /cw [reset]")
        end
    end
end

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Commander Who"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Commander Who Settings")

    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetText("Configure Commander Who options below.")

    showWhoWindowCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    showWhoWindowCheckbox:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)
    showWhoWindowCheckbox.Text:SetText("Show Who Window")
    showWhoWindowCheckbox:SetChecked(CommanderWhoDB.ShowWhoWindow)
    showWhoWindowCheckbox:SetScript("OnClick", function(self)
        CommanderWhoDB.ShowWhoWindow = self:GetChecked()
        Notify(COMMANDER_WHO_EVENTS.UPDATE)
    end)

    showWhoButtonCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    showWhoButtonCheckbox:SetPoint("TOPLEFT", showWhoWindowCheckbox, "BOTTOMLEFT", 0, -8)
    showWhoButtonCheckbox.Text:SetText("Show Who Button")
    showWhoButtonCheckbox:SetChecked(CommanderWhoDB.ShowWhoButton)
    showWhoButtonCheckbox:SetScript("OnClick", function(self)
        CommanderWhoDB.ShowWhoButton = self:GetChecked()
        Notify(COMMANDER_WHO_EVENTS.UPDATE)
    end)

    return panel
end

local function OnUpdate()
    if showWhoWindowCheckbox then
        showWhoWindowCheckbox:SetChecked(CommanderWhoDB.ShowWhoWindow)
    end
    if showWhoButtonCheckbox then
        showWhoButtonCheckbox:SetChecked(CommanderWhoDB.ShowWhoButton)
    end
end

local function OnAwake()
    local panel = CreateOptionsPanel()
    local category = Settings.RegisterCanvasLayoutSubcategory(MainCategory, panel, "Commander Who")
    local categoryID = category:GetID()
    Settings.RegisterAddOnCategory(category)
    InitializeSlashCommands(categoryID)
    AddListener(COMMANDER_WHO_EVENTS.UPDATE, OnUpdate)
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
