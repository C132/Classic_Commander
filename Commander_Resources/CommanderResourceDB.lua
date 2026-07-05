CommanderResourceDB = CommanderResourceDB or {}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

COMMANDER_RESOURCE_EVENTS = {
    FIVE_SECOND_RULE_CHANGED = "FIVE_SECOND_RULE_CHANGED",
}

local DefaultSettings = {
    ShowFiveSecondRule = true,
}

local categoryID

local function ApplyDefaultSettings()
    -- One-time migration: pre-2.0 code persisted ShowFiveSecondRule=false for
    -- every install ("... = CommanderResourceDB.ShowFiveSecondRule or false")
    -- and no UI could write true, so a saved false was never intentional.
    -- Flip it once to the new default; afterwards a user-set false sticks.
    if not CommanderResourceDB._defaultsV2 then
        if CommanderResourceDB.ShowFiveSecondRule == false then
            CommanderResourceDB.ShowFiveSecondRule = true
        end
        CommanderResourceDB._defaultsV2 = true
    end

    for key, value in pairs(DefaultSettings) do
        if CommanderResourceDB[key] == nil then
            CommanderResourceDB[key] = value
        end
    end
end

local function Reset()
    print("Resetting Commander Resources")
    for key, value in pairs(DefaultSettings) do
        CommanderResourceDB[key] = value
    end
    Commander.Notify(COMMANDER_RESOURCE_EVENTS.FIVE_SECOND_RULE_CHANGED)
end

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Commander Resources"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Commander Resources Settings")

    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetText("Configure Commander Resources options below.")

    local resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetButton:SetSize(100, 22)
    resetButton:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)
    resetButton:SetText("Reset")
    resetButton:SetScript("OnClick", function() Reset() end)

    local showFiveSecondRuleCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    showFiveSecondRuleCheckbox:SetPoint("TOPLEFT", resetButton, "BOTTOMLEFT", 0, -8)
    showFiveSecondRuleCheckbox.Text:SetText("Show Five Second Rule")
    showFiveSecondRuleCheckbox:SetChecked(CommanderResourceDB.ShowFiveSecondRule)
    showFiveSecondRuleCheckbox:SetScript("OnClick", function(self)
        CommanderResourceDB.ShowFiveSecondRule = self:GetChecked()
        Commander.Notify(COMMANDER_RESOURCE_EVENTS.FIVE_SECOND_RULE_CHANGED)
    end)

    -- Re-sync the checkbox when the setting changes elsewhere (Reset, MyClassicAddon)
    Commander.AddListener(COMMANDER_RESOURCE_EVENTS.FIVE_SECOND_RULE_CHANGED, function()
        showFiveSecondRuleCheckbox:SetChecked(CommanderResourceDB.ShowFiveSecondRule)
    end)

    return panel
end

local function OnAwake()
    -- SavedVariables replace the global after this file runs, so re-ensure the table here
    CommanderResourceDB = CommanderResourceDB or {}
    ApplyDefaultSettings()
    local panel = CreateOptionsPanel()
    local category = Settings.RegisterCanvasLayoutSubcategory(Commander.MainCategory, panel, "Commander Resources")
    categoryID = category:GetID()
end

-- Initialize any necessary components or features
local function OnStart()
end

-- Save any necessary data before logout
local function OnDestroy()
end

frame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Resources" then
        OnAwake()
    elseif event == "PLAYER_LOGOUT" then
        OnDestroy()
    elseif event == "PLAYER_ENTERING_WORLD" then
        OnStart()
    end
end)
