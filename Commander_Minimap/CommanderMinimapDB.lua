CommanderMinimapDB = CommanderMinimapDB or {}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

COMMANDER_MINIMAP_EVENTS = {
    COMMANDER_MINIMAP = "COMMANDER_MINIMAP",
}

local defaultSettings = {
    ShowMinimapButton = true,
    XPDisplayMode = "PERCENTAGE",
}

local XP_DISPLAY_MODES = {
    {text = "Percentage", value = "PERCENTAGE"},
    {text = "Kills to Level", value = "KILLS_TO_LEVEL"},
}

local showMinimapButtonCheckbox
local xpDisplayModeDropdown
local optionsCategoryID

-- Defaults are applied in ADDON_LOADED: SavedVariables replace the global
-- after this file runs, so applying them at file scope would be overwritten
local function ApplyDefaults()
    for key, value in pairs(defaultSettings) do
        if CommanderMinimapDB[key] == nil then
            CommanderMinimapDB[key] = value
        end
    end
end

local function GetXPDisplayModeText(mode)
    for _, entry in ipairs(XP_DISPLAY_MODES) do
        if entry.value == mode then
            return entry.text
        end
    end
    return XP_DISPLAY_MODES[1].text
end

local function Reset()
    for key, value in pairs(defaultSettings) do
        CommanderMinimapDB[key] = value
    end
    Commander.Notify(COMMANDER_MINIMAP_EVENTS.COMMANDER_MINIMAP)
end

-- Re-sync the panel widgets from the DB (covers Reset and writes from
-- other addons that mirror these settings)
local function OnUpdate()
    if showMinimapButtonCheckbox then
        showMinimapButtonCheckbox:SetChecked(CommanderMinimapDB.ShowMinimapButton)
    end
    if xpDisplayModeDropdown then
        UIDropDownMenu_SetText(xpDisplayModeDropdown, GetXPDisplayModeText(CommanderMinimapDB.XPDisplayMode))
    end
end

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Commander Minimap"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Commander Minimap Settings")

    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetText("Configure Commander Minimap options below.")

    showMinimapButtonCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    showMinimapButtonCheckbox:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)
    showMinimapButtonCheckbox.Text:SetText("Show Minimap Button")
    showMinimapButtonCheckbox:SetChecked(CommanderMinimapDB.ShowMinimapButton)
    showMinimapButtonCheckbox:SetScript("OnClick", function(self)
        CommanderMinimapDB.ShowMinimapButton = self:GetChecked()
        Commander.Notify(COMMANDER_MINIMAP_EVENTS.COMMANDER_MINIMAP)
    end)

    local xpDisplayModeLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    xpDisplayModeLabel:SetPoint("TOPLEFT", showMinimapButtonCheckbox, "BOTTOMLEFT", 0, -16)
    xpDisplayModeLabel:SetText("XP Display Mode")

    xpDisplayModeDropdown = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
    xpDisplayModeDropdown:SetPoint("TOPLEFT", xpDisplayModeLabel, "BOTTOMLEFT", -15, -8)
    UIDropDownMenu_SetWidth(xpDisplayModeDropdown, 120)
    UIDropDownMenu_SetText(xpDisplayModeDropdown, GetXPDisplayModeText(CommanderMinimapDB.XPDisplayMode))

    local function XPDisplayModeDropdown_Initialize(self, level)
        local info = UIDropDownMenu_CreateInfo()
        info.func = function(self)
            CommanderMinimapDB.XPDisplayMode = self.value
            UIDropDownMenu_SetText(xpDisplayModeDropdown, GetXPDisplayModeText(self.value))
            Commander.Notify(COMMANDER_MINIMAP_EVENTS.COMMANDER_MINIMAP)
        end

        for _, entry in ipairs(XP_DISPLAY_MODES) do
            info.text = entry.text
            info.value = entry.value
            info.checked = (CommanderMinimapDB.XPDisplayMode == entry.value)
            UIDropDownMenu_AddButton(info)
        end
    end

    UIDropDownMenu_Initialize(xpDisplayModeDropdown, XPDisplayModeDropdown_Initialize)

    local resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetButton:SetPoint("TOPLEFT", xpDisplayModeDropdown, "BOTTOMLEFT", 15, -16)
    resetButton:SetSize(100, 22)
    resetButton:SetText("Reset")
    resetButton:SetScript("OnClick", function() Reset() end)

    return panel
end

local function OnAwake()
    -- Booleans are handled by ApplyDefaults (nil checks), so a saved "false" is not clobbered
    CommanderMinimapDB.lastXPGain = CommanderMinimapDB.lastXPGain or 0
    CommanderMinimapDB.killsToLevel = CommanderMinimapDB.killsToLevel or 0
    CommanderMinimapDB.lastXPSource = CommanderMinimapDB.lastXPSource or ""

    local panel = CreateOptionsPanel()
    local category = Settings.RegisterCanvasLayoutSubcategory(Commander.MainCategory, panel, "Commander Minimap")
    optionsCategoryID = category:GetID()
    Commander.AddListener(COMMANDER_MINIMAP_EVENTS.COMMANDER_MINIMAP, OnUpdate)
end

local function OnEvent(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "Commander_Minimap" then
            ApplyDefaults()
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        OnAwake()
    end
end

frame:SetScript("OnEvent", OnEvent)
