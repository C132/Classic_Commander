local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")

local function OnAwake()
    if not CommanderUnitFramesDB then
        CommanderUnitFramesDB = {}
    end
    CommanderUnitFramesDB.scale = CommanderUnitFramesDB.scale or 1.0
    if CommanderUnitFramesDB.showPercentage == nil then
        CommanderUnitFramesDB.showPercentage = true
    end
end

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
    scaleSlider:SetValue(CommanderUnitFramesDB.scale)
    
    scaleSlider.Text:SetText("Frame Scale")
    scaleSlider.Low:SetText("0.5")
    scaleSlider.High:SetText("2.0")

    scaleSlider:SetScript("OnValueChanged", function(self, value)
        CommanderUnitFramesDB.scale = value
        -- Add scale update logic here when unit frame is implemented
    end)

    -- Show percentage checkbox
    local percentageCheckbox = CreateFrame("CheckButton", "CommanderUnitFramesPercentageCheckbox", panel, "UICheckButtonTemplate")
    percentageCheckbox:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, -20)
    percentageCheckbox.text = percentageCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    percentageCheckbox.text:SetPoint("LEFT", percentageCheckbox, "RIGHT", 0, 1)
    percentageCheckbox.text:SetText("Show Health/Mana Percentage")
    
    percentageCheckbox:SetChecked(CommanderUnitFramesDB.showPercentage)
    percentageCheckbox:SetScript("OnClick", function(self)
        CommanderUnitFramesDB.showPercentage = self:GetChecked()
        -- Add percentage display update logic here when unit frame is implemented
    end)

    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    return panel, category
end

local settingsPanel
local settingsCategory

frame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_UnitFrames" then
        OnAwake()
        settingsPanel, settingsCategory = CreateSettingsPanel()
    end
end)

SLASH_COMMANDERUF1 = "/cuf"
SlashCmdList["COMMANDERUF"] = function(msg)
    if settingsCategory then
        Settings.OpenToCategory(settingsCategory:GetID())
    end
end
