CommanderActionBarDB = _G.CommanderActionBarDB or {}

COMMANDER_ACTIONBAR_EVENTS = {
    UPDATE = "COMMANDER_ACTIONBAR_UPDATE"
}

local DefaultSettings = {
    locked = true,
    showBagButtons = true,
    position = {
        point = "CENTER",
        relativePoint = "CENTER", 
        xOfs = 0,
        yOfs = 0
    }
}

for key, value in pairs(DefaultSettings) do
    if CommanderActionBarDB[key] == nil then
        CommanderActionBarDB[key] = value
    end
end

local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
local loaded = false

local function Reset()
    print("Resetting Commander Action Bar")
    for key, value in pairs(DefaultSettings) do
        CommanderActionBarDB[key] = value
    end
    Notify(COMMANDER_ACTIONBAR_EVENTS.UPDATE)
end

local function InitializeSlashCommands(categoryID)
    SLASH_CAB1 = "/cab"
    SlashCmdList["CAB"] = function(msg)
        msg = msg:lower()
        if msg == "" then
            Settings.OpenToCategory(categoryID)
        elseif msg == "reset" then
            Reset()
            print("Commander Action Bar Reset")
        elseif msg == "lock" then
            CommanderActionBarDB.locked = true
            Notify(COMMANDER_ACTIONBAR_EVENTS.UPDATE)
            print("Commander Action Bar Locked")
        elseif msg == "unlock" then
            CommanderActionBarDB.locked = false
            Notify(COMMANDER_ACTIONBAR_EVENTS.UPDATE)
            print("Commander Action Bar Unlocked")
        else
            print("Usage: /cab [reset|lock|unlock]")
        end
    end
end

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Commander Action Bar"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Commander Action Bar Settings")

    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetText("Configure Commander Action Bar options below.")
    
    local resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetButton:SetSize(100, 22)
    resetButton:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)
    resetButton:SetText("Reset")
    resetButton:SetScript("OnClick", function()
        Reset()
        print("Commander Action Bar Reset")
    end)

    local lockCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    lockCheckbox:SetPoint("TOPLEFT", resetButton, "BOTTOMLEFT", 0, -8)
    lockCheckbox.Text:SetText("Lock Action Bars")
    lockCheckbox:SetChecked(CommanderActionBarDB.locked)
    lockCheckbox:SetScript("OnClick", function(self)
        CommanderActionBarDB.locked = self:GetChecked()
        Notify(COMMANDER_ACTIONBAR_EVENTS.UPDATE)
    end)

    local bagButtonsCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    bagButtonsCheckbox:SetPoint("TOPLEFT", lockCheckbox, "BOTTOMLEFT", 0, -8)
    bagButtonsCheckbox.Text:SetText("Show Bag Buttons")
    bagButtonsCheckbox:SetChecked(CommanderActionBarDB.showBagButtons)
    bagButtonsCheckbox:SetScript("OnClick", function(self)
        CommanderActionBarDB.showBagButtons = self:GetChecked()
        Notify(COMMANDER_ACTIONBAR_EVENTS.UPDATE)
    end)
    
    return panel
end

local function OnUpdate()
    for i = 0, 3 do
        local bagButton = _G["CharacterBag" .. i .. "Slot"]
        bagButton:SetShown(CommanderActionBarDB.showBagButtons)
    end
end

local function OnAwake()
    print("Commander Action Bar DB Awake")
    local panel = CreateOptionsPanel()
    local category = Settings.RegisterCanvasLayoutSubcategory(MainCategory, panel, "Commander Action Bar")
    local categoryID = category:GetID()
    Settings.RegisterAddOnCategory(category)
    InitializeSlashCommands(categoryID)
    AddListener(COMMANDER_ACTIONBAR_EVENTS.UPDATE, OnUpdate)
end

local function OnDestroy()
    print("Commander Action Bar DB Destroy")
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
