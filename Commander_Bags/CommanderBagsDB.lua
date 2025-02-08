CommanderBagsDB = _G.CommanderBagsDB or {}

local colorCodeItemsCheckbox

COMMANDER_BAGS_EVENTS = {
    UPDATE = "COMMANDER_BAGS_UPDATE"
}

local DefaultSettings = {
    ColorCodeItems = true,
    BagPositions = {},
    FadeBagsWhileMoving = true
}

for key, value in pairs(DefaultSettings) do
    if CommanderBagsDB[key] == nil then
        CommanderBagsDB[key] = value
    end
end

local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
local loaded = false

local function Reset()
    print("Resetting Commander Bags")
    for key, value in pairs(DefaultSettings) do
        CommanderBagsDB[key] = value
    end
    
    -- Reset bag positions
    for i = 1, NUM_BAG_FRAMES do
        local frame = _G["ContainerFrame"..i]
        if frame then
            frame:ClearAllPoints()
            frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -50, 100)
        end
    end
    
    CommanderBagsDB.BagPositions = {}
    Notify(COMMANDER_BAGS_EVENTS.UPDATE)
end

local function InitializeSlashCommands(categoryID)
    SLASH_CB1 = "/cb"
    SlashCmdList["CB"] = function(msg)
        msg = msg:lower()
        if msg == "" then
            Settings.OpenToCategory(categoryID)
        elseif msg == "reset" then
            Reset()
            print("Commander Bags Reset")
        else
            print("Usage: /cb [reset]")
        end
    end
end

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Commander Bags"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Commander Bags Settings")

    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetText("Configure Commander Bags options below.")

    colorCodeItemsCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    colorCodeItemsCheckbox:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)
    colorCodeItemsCheckbox.Text:SetText("Color Code Item Icons")
    colorCodeItemsCheckbox:SetChecked(CommanderBagsDB.ColorCodeItems)
    colorCodeItemsCheckbox:SetScript("OnClick", function(self)
        CommanderBagsDB.ColorCodeItems = self:GetChecked()
        print("Color coding setting changed to:", self:GetChecked())
        Notify(COMMANDER_BAGS_EVENTS.UPDATE)
    end)

    -- Add Reset Position Button
    local resetPositionButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetPositionButton:SetSize(140, 22)
    resetPositionButton:SetPoint("TOPLEFT", colorCodeItemsCheckbox, "BOTTOMLEFT", 0, -16)
    resetPositionButton:SetText("Reset Bag Positions")
    resetPositionButton:SetScript("OnClick", function()
        Reset()
        print("Bag positions have been reset")
    end)

    -- Add Fade Bags While Moving checkbox
    local fadeBagsCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    fadeBagsCheckbox:SetPoint("TOPLEFT", resetPositionButton, "BOTTOMLEFT", 0, -8)
    fadeBagsCheckbox.Text:SetText("Fade Bags While Moving")
    fadeBagsCheckbox:SetChecked(CommanderBagsDB.FadeBagsWhileMoving)
    fadeBagsCheckbox:SetScript("OnClick", function(self)
        CommanderBagsDB.FadeBagsWhileMoving = self:GetChecked()
        print("Fade bags while moving setting changed to:", self:GetChecked())
        Notify(COMMANDER_BAGS_EVENTS.UPDATE)
    end)

    return panel
end

local function OnUpdate()
    if colorCodeItemsCheckbox then
        colorCodeItemsCheckbox:SetChecked(CommanderBagsDB.ColorCodeItems)
    end
end

local function OnAwake()
    -- Initialize BagPositions if it doesn't exist
    if CommanderBagsDB.BagPositions == nil then
        CommanderBagsDB.BagPositions = {}
    end
    
    local panel = CreateOptionsPanel()
    local category = Settings.RegisterCanvasLayoutSubcategory(MainCategory, panel, "Commander Bags")
    local categoryID = category:GetID()
    Settings.RegisterAddOnCategory(category)
    InitializeSlashCommands(categoryID)
    AddListener(COMMANDER_BAGS_EVENTS.UPDATE, OnUpdate)
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
