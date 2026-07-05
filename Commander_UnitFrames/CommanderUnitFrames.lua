local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")

local DefaultSettings = {
    scale = 1.0,
    showPercentage = true
}

local function CreateSettingsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Commander Unit Frames"

    -- Title
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Commander Unit Frames Settings")

    -- Scale slider
    local scaleSlider = CreateFrame("Slider", "CommanderUnitFramesScaleSlider", panel, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -40)
    scaleSlider:SetWidth(200)
    scaleSlider:SetHeight(20)
    scaleSlider:SetMinMaxValues(0.5, 2.0)
    scaleSlider:SetValueStep(0.1)
    scaleSlider:SetValue(CommanderUnitFramesDB.scale or DefaultSettings.scale)

    scaleSlider.Text:SetText("Frame Scale")
    scaleSlider.Low:SetText("0.5")
    scaleSlider.High:SetText("2.0")

    scaleSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 10 + 0.5) / 10
        if CommanderUnitFramesDB.scale ~= value then
            CommanderUnitFramesDB.scale = value
            Commander.Notify(COMMANDER_UNIT_FRAMES_EVENTS.SCALE_CHANGED)
        end
    end)

    -- Show percentage checkbox
    local percentageCheckbox = CreateFrame("CheckButton", "CommanderUnitFramesPercentageCheckbox", panel, "UICheckButtonTemplate")
    percentageCheckbox:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, -20)
    percentageCheckbox.text = percentageCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    percentageCheckbox.text:SetPoint("LEFT", percentageCheckbox, "RIGHT", 0, 1)
    percentageCheckbox.text:SetText("Show Health/Mana Percentage")

    percentageCheckbox:SetChecked(CommanderUnitFramesDB.showPercentage)
    percentageCheckbox:SetScript("OnClick", function(self)
        CommanderUnitFramesDB.showPercentage = self:GetChecked() and true or false
        Commander.Notify(COMMANDER_UNIT_FRAMES_EVENTS.PERCENTAGE_DISPLAY_CHANGED)
    end)

    -- Reset button
    local resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetButton:SetSize(100, 22)
    resetButton:SetPoint("TOPLEFT", percentageCheckbox, "BOTTOMLEFT", 0, -20)
    resetButton:SetText("Reset")
    resetButton:SetScript("OnClick", function()
        CommanderUnitFramesDB.scale = DefaultSettings.scale
        CommanderUnitFramesDB.showPercentage = DefaultSettings.showPercentage
        Commander.Notify(COMMANDER_UNIT_FRAMES_EVENTS.SCALE_CHANGED)
        Commander.Notify(COMMANDER_UNIT_FRAMES_EVENTS.PERCENTAGE_DISPLAY_CHANGED)
    end)

    -- Keep the widgets in sync with the DB when settings change elsewhere
    Commander.AddListener(COMMANDER_UNIT_FRAMES_EVENTS.SCALE_CHANGED, function()
        scaleSlider:SetValue(CommanderUnitFramesDB.scale or DefaultSettings.scale)
    end)
    Commander.AddListener(COMMANDER_UNIT_FRAMES_EVENTS.PERCENTAGE_DISPLAY_CHANGED, function()
        percentageCheckbox:SetChecked(CommanderUnitFramesDB.showPercentage)
    end)

    local category = Settings.RegisterCanvasLayoutSubcategory(Commander.MainCategory, panel, "Commander Unit Frames")
    return category:GetID()
end

local settingsCategoryID

frame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_UnitFrames" then
        settingsCategoryID = CreateSettingsPanel()
    end
end)

SLASH_COMMANDERUF1 = "/cuf"
SlashCmdList["COMMANDERUF"] = function(msg)
    if settingsCategoryID then
        Settings.OpenToCategory(settingsCategoryID)
    end
end
