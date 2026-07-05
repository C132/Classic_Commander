CommanderConsoleDB = _G.CommanderConsoleDB or {}

local showConsoleCheckbox

COMMANDER_CONSOLE_EVENTS = {
    UPDATE = "COMMANDER_CONSOLE_UPDATE"
}

local DefaultSettings = {
    ShowConsole = false,
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
local loaded = false

local function Reset()
    print("Resetting Commander Console")
    for key, value in pairs(DefaultSettings) do
        CommanderConsoleDB[key] = value
    end
    Commander.Notify(COMMANDER_CONSOLE_EVENTS.UPDATE)
end

local function InitializeSlashCommands(categoryID)
    SLASH_CC1 = "/cc"
    SlashCmdList["CC"] = function(msg)
        msg = msg:lower()
        if msg == "" then
            Settings.OpenToCategory(categoryID)
        elseif msg == "reset" then
            Reset()
            print("Commander Console Reset")
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

    showConsoleCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    showConsoleCheckbox:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)
    showConsoleCheckbox.Text:SetText("Show Console")
    showConsoleCheckbox:SetChecked(CommanderConsoleDB.ShowConsole)
    showConsoleCheckbox:SetScript("OnClick", function(self)
        CommanderConsoleDB.ShowConsole = self:GetChecked()
        Commander.Notify(COMMANDER_CONSOLE_EVENTS.UPDATE)
    end)

    local resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetButton:SetSize(100, 22)
    resetButton:SetPoint("TOPLEFT", showConsoleCheckbox, "BOTTOMLEFT", 0, -16)
    resetButton:SetText("Reset")
    resetButton:SetScript("OnClick", function()
        Reset()
        print("Commander Console Reset")
    end)

    
    return panel
end

local function OnUpdate()
    if showConsoleCheckbox then
        showConsoleCheckbox:SetChecked(CommanderConsoleDB.ShowConsole)
    end
end

local function OnAwake()
    -- Merge defaults here so SavedVariables are already loaded
    for key, value in pairs(DefaultSettings) do
        if CommanderConsoleDB[key] == nil then
            CommanderConsoleDB[key] = value
        end
    end
    local panel = CreateOptionsPanel()
    local category = Settings.RegisterCanvasLayoutSubcategory(Commander.MainCategory, panel, "Commander Console")
    local categoryID = category:GetID()
    InitializeSlashCommands(categoryID)
    Commander.AddListener(COMMANDER_CONSOLE_EVENTS.UPDATE, OnUpdate)
end

local function OnDestroy()
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