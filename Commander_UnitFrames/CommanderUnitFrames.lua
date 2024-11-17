local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")

local function OnAwake()
    if not CommanderUnitFramesDB then
        CommanderUnitFramesDB = {}
    end
    CommanderUnitFramesDB.scale = CommanderUnitFramesDB.scale or 1.0
    CommanderUnitFramesDB.showPercentage = CommanderUnitFramesDB.showPercentage or true
end

local function CreateSettingsWindow() 
    local window = CreateFrame("Frame", "CommanderUnitFramesSettings", UIParent, "BasicFrameTemplateWithInset")
    window:SetSize(300, 200)
    window:SetPoint("CENTER")
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:Hide()

    window.title = window:CreateFontString(nil, "OVERLAY")
    window.title:SetFontObject("GameFontHighlight")
    window.title:SetPoint("TOP", window.TitleBg, "TOP", 0, -5)
    window.title:SetText("Unit Frame Settings")

    -- Scale slider
    local scaleSlider = CreateFrame("Slider", "CommanderUnitFramesScaleSlider", window, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOP", window, "TOP", 0, -50)
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
    local percentageCheckbox = CreateFrame("CheckButton", "CommanderUnitFramesPercentageCheckbox", window, "UICheckButtonTemplate")
    percentageCheckbox:SetPoint("TOP", scaleSlider, "BOTTOM", 0, -20)
    percentageCheckbox.text = percentageCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    percentageCheckbox.text:SetPoint("LEFT", percentageCheckbox, "RIGHT", 0, 1)
    percentageCheckbox.text:SetText("Show Health/Mana Percentage")
    
    percentageCheckbox:SetChecked(CommanderUnitFramesDB.showPercentage)
    percentageCheckbox:SetScript("OnClick", function(self)
        CommanderUnitFramesDB.showPercentage = self:GetChecked()
        -- Add percentage display update logic here when unit frame is implemented
    end)

    return window
end

local settingsWindow

SLASH_COMMANDERUF1 = "/cuf"
SlashCmdList["COMMANDERUF"] = function(msg)
    if not settingsWindow then
        settingsWindow = CreateSettingsWindow()
    end
    
    if settingsWindow:IsShown() then
        settingsWindow:Hide()
    else
        settingsWindow:Show()
    end
end

frame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_UnitFrames" then
        OnAwake()
    end
end)
