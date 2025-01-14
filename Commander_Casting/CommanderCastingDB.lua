CommanderCastingDB = _G.CommanderCastingDB or {}

local showFullscreenEffectCheckbox
local colorBySpellSchoolCheckbox
local intensitySlider
local textureDropdown
local texturePreview
local textureHoverPreview

COMMANDER_CASTING_EVENTS = {
    UPDATE = "COMMANDER_CASTING_UPDATE"
}

local TEXTURE_PATH = "Interface\\AddOns\\Commander_Casting\\Textures\\"
local TEXTURE_FILES = {
    "Glow1.png",
    "Glow2.png", 
    "Glow3.png",
    "Glow4.png",
    "Glow5.png",
    "Glow6.png",
    "Glow7.png",
}

local DefaultSettings = {
    ShowFullscreenEffect = true,
    ColorBySpellSchool = true,
    EffectIntensity = 0.5,
    EffectTexture = TEXTURE_PATH .. TEXTURE_FILES[1]
}

for key, value in pairs(DefaultSettings) do
    if CommanderCastingDB[key] == nil then
        CommanderCastingDB[key] = value
    end
end

local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
local loaded = false

local function Reset()
    print("Resetting Commander Casting")
    for key, value in pairs(DefaultSettings) do
        CommanderCastingDB[key] = value
    end
    Notify(COMMANDER_CASTING_EVENTS.UPDATE)
end

local function InitializeSlashCommands(categoryID)
    SLASH_CCAST1 = "/ccast"
    SlashCmdList["CCAST"] = function(msg)
        msg = msg:lower()
        if msg == "" then
            Settings.OpenToCategory(categoryID)
        elseif msg == "reset" then
            Reset()
            print("Commander Casting Reset")
        else
            print("Usage: /ccast [reset]")
        end
    end
end

local function GetTextureDisplayName(filename)
    return filename:gsub("%.png$", "")
end

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Commander Casting"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Commander Casting Settings")

    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetText("Configure Commander Casting options below.")

    showFullscreenEffectCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    showFullscreenEffectCheckbox:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)
    showFullscreenEffectCheckbox.Text:SetText("Show Fullscreen Casting Effect")
    showFullscreenEffectCheckbox:SetChecked(CommanderCastingDB.ShowFullscreenEffect)
    showFullscreenEffectCheckbox:SetScript("OnClick", function(self)
        CommanderCastingDB.ShowFullscreenEffect = self:GetChecked()
        Notify(COMMANDER_CASTING_EVENTS.UPDATE)
    end)

    colorBySpellSchoolCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    colorBySpellSchoolCheckbox:SetPoint("TOPLEFT", showFullscreenEffectCheckbox, "BOTTOMLEFT", 0, -8)
    colorBySpellSchoolCheckbox.Text:SetText("Color Effect by Spell School")
    colorBySpellSchoolCheckbox:SetChecked(CommanderCastingDB.ColorBySpellSchool)
    colorBySpellSchoolCheckbox:SetScript("OnClick", function(self)
        CommanderCastingDB.ColorBySpellSchool = self:GetChecked()
        Notify(COMMANDER_CASTING_EVENTS.UPDATE)
    end)

    intensitySlider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    intensitySlider:SetPoint("TOPLEFT", colorBySpellSchoolCheckbox, "BOTTOMLEFT", 0, -24)
    intensitySlider:SetMinMaxValues(0, 1)
    intensitySlider:SetValue(CommanderCastingDB.EffectIntensity or 0.5)
    intensitySlider:SetValueStep(0.1)
    intensitySlider:SetWidth(200)
    intensitySlider.Text:SetText("Effect Intensity")
    intensitySlider.Low:SetText("0%")
    intensitySlider.High:SetText("100%")
    intensitySlider:SetScript("OnValueChanged", function(self, value)
        if value then
            CommanderCastingDB.EffectIntensity = value
            Notify(COMMANDER_CASTING_EVENTS.UPDATE)
        end
    end)

    local textureLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    textureLabel:SetPoint("TOPLEFT", intensitySlider, "BOTTOMLEFT", 0, -16)
    textureLabel:SetText("Effect Texture:")

    textureDropdown = CreateFrame("Frame", "CommanderCastingTextureDropdown", panel, "UIDropDownMenuTemplate")
    textureDropdown:SetPoint("TOPLEFT", textureLabel, "BOTTOMLEFT", -16, -8)

    -- Create texture preview frame
    local previewFrame = CreateFrame("Frame", nil, panel)
    previewFrame:SetSize(64, 64)
    previewFrame:SetPoint("LEFT", textureDropdown, "RIGHT", 16, 0)

    -- Current texture preview
    texturePreview = previewFrame:CreateTexture(nil, "ARTWORK")
    texturePreview:SetAllPoints()
    texturePreview:SetTexture(CommanderCastingDB.EffectTexture)
    texturePreview:SetBlendMode("ADD")

    -- Hover preview
    textureHoverPreview = previewFrame:CreateTexture(nil, "ARTWORK")
    textureHoverPreview:SetAllPoints()
    textureHoverPreview:SetBlendMode("ADD")
    textureHoverPreview:Hide()

    local function OnTextureSelect(self, texture)
        CommanderCastingDB.EffectTexture = texture
        UIDropDownMenu_SetSelectedValue(textureDropdown, texture)
        texturePreview:SetTexture(texture)
        Notify(COMMANDER_CASTING_EVENTS.UPDATE)
    end

    local function InitializeDropdown(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, filename in ipairs(TEXTURE_FILES) do
            local fullPath = TEXTURE_PATH .. filename
            info.text = GetTextureDisplayName(filename)
            info.value = fullPath
            info.func = OnTextureSelect
            info.arg1 = fullPath
            info.checked = (CommanderCastingDB.EffectTexture == fullPath)
            info.tooltipOnButton = true
            info.tooltipTitle = GetTextureDisplayName(filename)
            info.tooltipText = " "  -- Need non-empty string for tooltip to show
            info.mouseOverHandler = function(self)
                textureHoverPreview:SetTexture(fullPath)
                textureHoverPreview:Show()
                texturePreview:Hide()
            end
            info.mouseLeaveHandler = function(self)
                textureHoverPreview:Hide()
                texturePreview:Show()
            end
            UIDropDownMenu_AddButton(info)
        end
    end

    UIDropDownMenu_Initialize(textureDropdown, InitializeDropdown)
    UIDropDownMenu_SetWidth(textureDropdown, 150)
    UIDropDownMenu_SetSelectedValue(textureDropdown, CommanderCastingDB.EffectTexture)

    for _, filename in ipairs(TEXTURE_FILES) do
        local fullPath = TEXTURE_PATH .. filename
        if fullPath == CommanderCastingDB.EffectTexture then
            UIDropDownMenu_SetText(textureDropdown, GetTextureDisplayName(filename))
            break
        end
    end

    return panel
end

local function OnUpdate()
    if showFullscreenEffectCheckbox then
        showFullscreenEffectCheckbox:SetChecked(CommanderCastingDB.ShowFullscreenEffect)
    end
    if colorBySpellSchoolCheckbox then
        colorBySpellSchoolCheckbox:SetChecked(CommanderCastingDB.ColorBySpellSchool)
    end
    if intensitySlider and CommanderCastingDB.EffectIntensity then
        intensitySlider:SetValue(CommanderCastingDB.EffectIntensity)
    end
    if textureDropdown then
        UIDropDownMenu_SetSelectedValue(textureDropdown, CommanderCastingDB.EffectTexture)
        for _, filename in ipairs(TEXTURE_FILES) do
            local fullPath = TEXTURE_PATH .. filename
            if fullPath == CommanderCastingDB.EffectTexture then
                UIDropDownMenu_SetText(textureDropdown, GetTextureDisplayName(filename))
                texturePreview:SetTexture(fullPath)
                break
            end
        end
    end
end

local function OnAwake()
    local panel = CreateOptionsPanel()
    local category = Settings.RegisterCanvasLayoutSubcategory(MainCategory, panel, "Commander Casting")
    local categoryID = category:GetID()
    Settings.RegisterAddOnCategory(category)
    InitializeSlashCommands(categoryID)
    AddListener(COMMANDER_CASTING_EVENTS.UPDATE, OnUpdate)
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
