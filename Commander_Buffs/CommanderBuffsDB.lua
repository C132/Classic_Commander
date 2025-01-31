CommanderBuffsDB = _G.CommanderBuffsDB or {}

local showBuffFrameCheckbox

COMMANDER_BUFFS_EVENTS = {
    UPDATE = "COMMANDER_BUFFS_UPDATE"
}

local DefaultSettings = {
    BuffScale = 1.0,
    LockBuffFrames = true,
    BuffFramePoint = "TOPRIGHT",
    BuffFrameX = -205,
    BuffFrameY = -13,
    ShowAnchorInCombat = false,
    BuffsPerRow = 8,
}

-- Ensure all settings exist with valid values
for key, value in pairs(DefaultSettings) do
    if CommanderBuffsDB[key] == nil or 
       (key == "BuffFramePoint" and type(CommanderBuffsDB[key]) ~= "string") then
        CommanderBuffsDB[key] = value
    end
end

local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
local loaded = false

local function Reset()
    print("Resetting Commander Buffs")
    for key, value in pairs(DefaultSettings) do
        CommanderBuffsDB[key] = value
    end
    Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
end

local function InitializeSlashCommands(categoryID)
    SLASH_CBUFF1 = "/cbuff"
    SlashCmdList["CBUFF"] = function(msg)
        msg = msg:lower()
        if msg == "" then
            Settings.OpenToCategory(categoryID)
        elseif msg == "reset" then
            Reset()
            print("Commander Buffs Reset")
        else
            print("Usage: /cbuff [reset]")
        end
    end
end

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Commander Buffs"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Commander Buffs Settings")

    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetText("Configure Commander Buffs options below.")

    -- Lock/Unlock Frames
    local lockFramesCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    lockFramesCheckbox:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)
    lockFramesCheckbox.Text:SetText("Lock Buff Frame")
    lockFramesCheckbox:SetChecked(CommanderBuffsDB.LockBuffFrames)
    lockFramesCheckbox:SetScript("OnClick", function(self)
        CommanderBuffsDB.LockBuffFrames = self:GetChecked()
        Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
    end)

    -- Show Anchors in Combat
    local showInCombatCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    showInCombatCheckbox:SetPoint("TOPLEFT", lockFramesCheckbox, "BOTTOMLEFT", 0, -8)
    showInCombatCheckbox.Text:SetText("Show Anchors in Combat")
    showInCombatCheckbox:SetChecked(CommanderBuffsDB.ShowAnchorInCombat)
    showInCombatCheckbox:SetScript("OnClick", function(self)
        CommanderBuffsDB.ShowAnchorInCombat = self:GetChecked()
        Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
    end)

    -- Scale Slider
    local scaleSlider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOPLEFT", showInCombatCheckbox, "BOTTOMLEFT", 0, -24)
    scaleSlider:SetWidth(200)
    scaleSlider.Text:SetText("Buff Frame Scale")
    scaleSlider.Low:SetText("0.5")
    scaleSlider.High:SetText("2.0")
    
    scaleSlider:SetMinMaxValues(0.5, 2.0)
    scaleSlider:SetValueStep(0.1)
    scaleSlider:SetValue(CommanderBuffsDB.BuffScale or 1.0)
    
    scaleSlider:SetScript("OnValueChanged", function(self, value)
        if value then
            CommanderBuffsDB.BuffScale = value
            Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
        end
    end)

    -- Buffs Per Row Slider
    local buffsPerRowSlider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    buffsPerRowSlider:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, -24)
    buffsPerRowSlider:SetWidth(200)
    buffsPerRowSlider.Text:SetText("Buffs Per Row")
    buffsPerRowSlider.Low:SetText("4")
    buffsPerRowSlider.High:SetText("16")
    
    buffsPerRowSlider:SetMinMaxValues(4, 16)
    buffsPerRowSlider:SetValueStep(1)
    buffsPerRowSlider:SetValue(CommanderBuffsDB.BuffsPerRow or 8)
    
    buffsPerRowSlider:SetScript("OnValueChanged", function(self, value)
        if value then
            CommanderBuffsDB.BuffsPerRow = math.floor(value)
            Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
        end
    end)

    -- Reset Position Button
    local resetPosButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetPosButton:SetPoint("TOPLEFT", buffsPerRowSlider, "BOTTOMLEFT", 0, -16)
    resetPosButton:SetText("Reset Position")
    resetPosButton:SetWidth(120)
    resetPosButton:SetScript("OnClick", function()
        CommanderBuffsDB.BuffFramePoint = DefaultSettings.BuffFramePoint
        CommanderBuffsDB.BuffFrameX = DefaultSettings.BuffFrameX
        CommanderBuffsDB.BuffFrameY = DefaultSettings.BuffFrameY
        CommanderBuffsDB.BuffScale = DefaultSettings.BuffScale
        Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
    end)

    return panel
end

local function OnUpdate()
    if showBuffFrameCheckbox then
        showBuffFrameCheckbox:SetChecked(CommanderBuffsDB.ShowBuffFrame)
    end
end

local function OnAwake()
    local panel = CreateOptionsPanel()
    local category = Settings.RegisterCanvasLayoutSubcategory(MainCategory, panel, "Commander Buffs")
    local categoryID = category:GetID()
    Settings.RegisterAddOnCategory(category)
    InitializeSlashCommands(categoryID)
    AddListener(COMMANDER_BUFFS_EVENTS.UPDATE, OnUpdate)
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
