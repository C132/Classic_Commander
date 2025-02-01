CommanderBagsDB = _G.CommanderBagsDB or {}

local colorCodeItemsCheckbox

COMMANDER_BAGS_EVENTS = {
    UPDATE = "COMMANDER_BAGS_UPDATE"
}

local DefaultSettings = {
    ColorCodeItems = true
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

    return panel
end

local function OnUpdate()
    if colorCodeItemsCheckbox then
        colorCodeItemsCheckbox:SetChecked(CommanderBagsDB.ColorCodeItems)
    end
end

local function OnAwake()
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
