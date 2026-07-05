local SettingsFrame = CreateFrame("Frame", "MyClassicAddonFrame", UIParent)
SettingsFrame.name = "My Classic Addon"
SettingsFrame:RegisterEvent("ADDON_LOADED")
SettingsFrame:RegisterEvent("PLAYER_LOGOUT")

local lastUI

local function CreateTitle()
    local title = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("My Classic Addon Settings")
    lastUI = title
end

local function DrawCheckBox(label, configKey, event)
    local checkbox = CreateFrame("CheckButton", nil, SettingsFrame, "InterfaceOptionsCheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", lastUI, "BOTTOMLEFT", 0, -10)
    checkbox.Text:SetText(label)
    checkbox:SetChecked(Config[configKey])
    checkbox:SetScript("OnClick", function(self)
        Config[configKey] = self:GetChecked()
        Raise(event)
    end)
    lastUI = checkbox
    return checkbox
end

local function DrawDropDown(label, configKey, options, event)
    local dropdown = CreateFrame("Frame", nil, SettingsFrame, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", lastUI, "BOTTOMLEFT", -15, -10)
    
    local labelText = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 20, 5)
    labelText:SetText(label)
    
    UIDropDownMenu_SetWidth(dropdown, 200)
    
    local function UpdateDropDownText(value)
        for _, option in ipairs(options) do
            if option.value == value then
                UIDropDownMenu_SetText(dropdown, option.text)
                return
            end
        end
    end
    
    UpdateDropDownText(Config[configKey])
    
    UIDropDownMenu_Initialize(dropdown, function()
        local info = UIDropDownMenu_CreateInfo()
        for _, option in ipairs(options) do
            info.text = option.text
            info.value = option.value
            info.checked = (option.value == UIDropDownMenu_GetSelectedValue(dropdown))
            info.func = function(self)
                UIDropDownMenu_SetSelectedValue(dropdown, self.value)
                UpdateDropDownText(self.value)
                Config[configKey] = self.value
                Raise(event)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    
    UIDropDownMenu_SetSelectedValue(dropdown, Config[configKey])
    
    lastUI = dropdown
    return dropdown
end

local function CreateReloadButton()
    local reloadButton = CreateFrame("Button", nil, SettingsFrame, "UIPanelButtonTemplate")
    reloadButton:SetText("Reload")
    reloadButton:SetSize(100, 25)
    reloadButton:SetPoint("TOPLEFT", lastUI, "BOTTOMLEFT", 0, -20)
    reloadButton:SetScript("OnClick", ReloadUI)
    lastUI = reloadButton
end

local function GeneralSettings()
    CreateTitle()
    
    DrawCheckBox("Show Chat", "ShowChatWindow", MY_CLASSIC_ADDON_EVENTS.CHAT_VISIBILITY_CHANGED)
    DrawCheckBox("Unlock Action Bar", "UnlockActionBar", MY_CLASSIC_ADDON_EVENTS.ACTIONBAR_UNLOCKED)
    DrawCheckBox("Show Five Second Rule", "ShowFiveSecondRule", MY_CLASSIC_ADDON_EVENTS.FIVE_SECOND_RULE_CHANGED)
    DrawCheckBox("Show Bag Buttons", "ShowBagButtons", MY_CLASSIC_ADDON_EVENTS.BAG_BUTTONS_VISIBILITY_CHANGED)
    DrawCheckBox("Fade Bags While Moving", "FadeBagsWhileMoving", MY_CLASSIC_ADDON_EVENTS.FADE_BAGS_WHILE_MOVING_CHANGED)
    DrawCheckBox("Show Minimap Button", "ShowMinimapButton", MY_CLASSIC_ADDON_EVENTS.MINIMAP_BUTTON_VISIBILITY_CHANGED)
    DrawCheckBox("Hide Player and Target Frames", "HideUnitFrames", MY_CLASSIC_ADDON_EVENTS.UNIT_FRAMES_VISIBILITY_CHANGED)

    DrawDropDown("Action Bar Cost Display", "ActionBarCostMode", {
        {text = "Raw Cost", value = "RAW_COST"},
        {text = "Casts Available", value = "CASTS_AVAILABLE"},
        {text = "Efficiency (Damage/Cost)", value = "EFFICIENCY"},
        {text = "Time to OOM", value = "TIME_TO_OOM"}
    }, MY_CLASSIC_ADDON_EVENTS.ACTIONBAR_COST_MODE_CHANGED)

    DrawDropDown("XP Display Mode", "XPDisplayMode", {
        {text = "Percentage", value = "PERCENTAGE"},
        {text = "Kills to Level", value = "KILLS_TO_LEVEL"}
    }, MY_CLASSIC_ADDON_EVENTS.XP_DISPLAY_MODE_CHANGED)

    CreateReloadButton()
end

SettingsFrame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "MyClassicAddon" then
        GeneralSettings()
    end
end)

function OpenSettings()
    Settings.OpenToCategory("My Classic Addon Settings")
end

-- Add slash command
SLASH_MYCLASSICADDON1 = "/mca"
SlashCmdList["MYCLASSICADDON"] = function(msg)
    msg = msg:lower()
    if msg == "" or msg == "settings" then
        OpenSettings()
    else
        print("Usage: /mca [settings]")
        print("  /mca or /mca settings - Open MyClassicAddon settings")
    end
end

Settings.RegisterCanvasLayoutCategory(SettingsFrame, "My Classic Addon Settings")