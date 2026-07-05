CommanderNameplateDB = _G.CommanderNameplateDB or {}

COMMANDER_NAMEPLATE_EVENTS = {
    UPDATE = "COMMANDER_NAMEPLATE_UPDATE"
}

local DefaultSettings = {
    showPlayerName = true,
    fadeWhileMoving = false,
    fadeIntensity = 0.5,
    showHealthPercent = false,
    showManaPercent = false,
    alwaysShowMana = false,
    position = {"CENTER", "UIParent", "CENTER", 0, 300}
}

local function CopyValue(value)
    if type(value) == "table" then
        local copy = {}
        for k, v in pairs(value) do
            copy[k] = v
        end
        return copy
    end
    return value
end

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local widgets = {}

local function Reset()
    print("Resetting Commander Nameplate")
    for key, value in pairs(DefaultSettings) do
        CommanderNameplateDB[key] = CopyValue(value)
    end
    Commander.Notify(COMMANDER_NAMEPLATE_EVENTS.UPDATE)
end

local function InitializeSlashCommands(categoryID)
    SLASH_CNP1 = "/cnp"
    SlashCmdList["CNP"] = function(msg)
        msg = msg:lower()
        if msg == "" then
            Settings.OpenToCategory(categoryID)
        elseif msg == "reset" then
            Reset()
            print("Commander Nameplate Reset")
        else
            print("Usage: /cnp [reset]")
        end
    end
end

local function CreateCheckbox(panel, name, label, description)
    local check = CreateFrame("CheckButton", "CommanderNameplate"..name.."CheckButton", panel, "InterfaceOptionsCheckButtonTemplate")
    check:SetScript("OnClick", function(self)
        CommanderNameplateDB[name] = self:GetChecked()
        Commander.Notify(COMMANDER_NAMEPLATE_EVENTS.UPDATE)
    end)
    check.label = _G[check:GetName().."Text"]
    check.label:SetText(label)
    check.tooltipText = label
    check.tooltipRequirement = description
    return check
end

local function CreateSlider(panel, name, label, minVal, maxVal, valueStep)
    local slider = CreateFrame("Slider", "CommanderNameplate"..name.."Slider", panel, "OptionsSliderTemplate")
    local editbox = CreateFrame("EditBox", "$parentEditBox", slider, "InputBoxTemplate")
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(valueStep)
    slider:SetObeyStepOnDrag(true)
    _G[slider:GetName().."Text"]:SetText(label)
    _G[slider:GetName().."Low"]:SetText(minVal)
    _G[slider:GetName().."High"]:SetText(maxVal)
    editbox:SetSize(50,30)
    editbox:ClearAllPoints()
    editbox:SetPoint("TOP", slider, "BOTTOM", 0, -5)
    editbox:SetFontObject(GameFontHighlightSmall)
    editbox:SetJustifyH("CENTER")
    editbox:SetAutoFocus(false)
    slider:SetScript("OnValueChanged", function(self, value)
        self.editbox:SetText(string.format("%.2f", value))
        if CommanderNameplateDB[name] ~= value then
            CommanderNameplateDB[name] = value
            Commander.Notify(COMMANDER_NAMEPLATE_EVENTS.UPDATE)
        end
    end)
    editbox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            self:GetParent():SetValue(val)
            self:ClearFocus()
        end
    end)
    slider.editbox = editbox
    return slider
end

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Commander Nameplate"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Commander Nameplate Settings")

    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetText("Configure Commander Nameplate options below.")

    widgets.showPlayerName = CreateCheckbox(panel, "showPlayerName", "Show Player Name", "Toggle visibility of player name on the nameplate")
    widgets.showPlayerName:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)
    widgets.fadeWhileMoving = CreateCheckbox(panel, "fadeWhileMoving", "Fade While Moving", "Fade out the nameplate when the player is moving")
    widgets.fadeWhileMoving:SetPoint("TOPLEFT", widgets.showPlayerName, "BOTTOMLEFT", 0, -24)
    widgets.fadeIntensity = CreateSlider(panel, "fadeIntensity", "Fade Intensity", 0, 1, 0.01)
    widgets.fadeIntensity:SetPoint("TOPLEFT", widgets.fadeWhileMoving, "BOTTOMLEFT", 0, -40)
    widgets.fadeIntensity:SetWidth(200)
    widgets.showHealthPercent = CreateCheckbox(panel, "showHealthPercent", "Show Health Percentage", "Display health percentage on the health bar")
    widgets.showHealthPercent:SetPoint("TOPLEFT", widgets.fadeIntensity, "BOTTOMLEFT", 0, -32)
    widgets.showManaPercent = CreateCheckbox(panel, "showManaPercent", "Show Mana Percentage", "Display mana percentage on the mana bar")
    widgets.showManaPercent:SetPoint("TOPLEFT", widgets.showHealthPercent, "BOTTOMLEFT", 0, -24)
    widgets.alwaysShowMana = CreateCheckbox(panel, "alwaysShowMana", "Always Show Mana Bar", "Always display the mana bar, even when out of combat")
    widgets.alwaysShowMana:SetPoint("TOPLEFT", widgets.showManaPercent, "BOTTOMLEFT", 0, -24)

    local resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetButton:SetSize(100, 22)
    resetButton:SetPoint("TOPLEFT", widgets.alwaysShowMana, "BOTTOMLEFT", 0, -24)
    resetButton:SetText("Reset")
    resetButton:SetScript("OnClick", function()
        Reset()
        print("Commander Nameplate Reset")
    end)

    return panel
end

local function RefreshWidgets()
    if not widgets.showPlayerName then return end
    widgets.showPlayerName:SetChecked(CommanderNameplateDB.showPlayerName)
    widgets.fadeWhileMoving:SetChecked(CommanderNameplateDB.fadeWhileMoving)
    widgets.fadeIntensity:SetValue(CommanderNameplateDB.fadeIntensity)
    widgets.fadeIntensity.editbox:SetText(string.format("%.2f", CommanderNameplateDB.fadeIntensity))
    widgets.showHealthPercent:SetChecked(CommanderNameplateDB.showHealthPercent)
    widgets.showManaPercent:SetChecked(CommanderNameplateDB.showManaPercent)
    widgets.alwaysShowMana:SetChecked(CommanderNameplateDB.alwaysShowMana)
end

local function OnAwake()
    local panel = CreateOptionsPanel()
    local category = Settings.RegisterCanvasLayoutSubcategory(Commander.MainCategory, panel, "Commander Nameplate")
    local categoryID = category:GetID()
    InitializeSlashCommands(categoryID)
    Commander.AddListener(COMMANDER_NAMEPLATE_EVENTS.UPDATE, RefreshWidgets)
    RefreshWidgets()
end

local function OnEvent(self, event, addon)
    if event == "ADDON_LOADED" and addon == "Commander_Nameplate" then
        CommanderNameplateDB = CommanderNameplateDB or {}
        for key, value in pairs(DefaultSettings) do
            if CommanderNameplateDB[key] == nil then
                CommanderNameplateDB[key] = CopyValue(value)
            end
        end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        OnAwake()
    end
end

frame:SetScript("OnEvent", OnEvent)
