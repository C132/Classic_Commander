local function CreatePlayerNameplate()
    local nameplate = CreateFrame("Frame", "CommanderPlayerNameplate", UIParent)
    nameplate:SetSize(128, 12)
    nameplate:SetPoint("CENTER", UIParent, "CENTER", 0, 300)
    nameplate.healthFrame = CreateFrame("Frame", nil, nameplate, "BackdropTemplate")
    nameplate.healthFrame:SetSize(115, 10)
    nameplate.healthFrame:SetPoint("CENTER")
    nameplate.healthFrame:SetFrameLevel(0)
    nameplate.healthBar = CreateFrame("StatusBar", nil, nameplate.healthFrame, "BackdropTemplate")
    nameplate.healthBar:SetAllPoints()
    nameplate.healthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    nameplate.healthBar:SetFrameLevel(1)
    nameplate.healthBar.bg = nameplate.healthBar:CreateTexture(nil, "BACKGROUND")
    nameplate.healthBar.bg:SetAllPoints()
    nameplate.healthBar.bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    nameplate.healthBar.bg:SetVertexColor(0.2, 0.2, 0.2, 0.8)
    nameplate.healthBar.text = nameplate.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameplate.healthBar.text:SetPoint("CENTER")
    nameplate.border = nameplate:CreateTexture(nil, "OVERLAY", nil, 7)
    nameplate.border:SetSize(280, 32)
    nameplate.border:SetPoint("CENTER", 80, 8)
    nameplate.border:SetTexture("Interface\\Addons\\Commander_Nameplate\\Nameplate-Border.PNG")
    nameplate.name = nameplate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameplate.name:SetPoint("TOP", 0, 16)
    nameplate.name:SetText(UnitName("player"))
    nameplate.name:SetFont(nameplate.name:GetFont(), 14, "BOLD")
    nameplate.level = nameplate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameplate.level:SetPoint("LEFT", nameplate, "RIGHT", 5, 0)
    nameplate.manaBorderFrame = CreateFrame("Frame", nil, nameplate)
    nameplate.manaBorderFrame:SetSize(110, 32)
    nameplate.manaBorderFrame:SetPoint("CENTER", 0, -8)
    nameplate.manaFrame = CreateFrame("Frame", nil, nameplate.manaBorderFrame, "BackdropTemplate")
    nameplate.manaFrame:SetSize(88, 10)
    nameplate.manaFrame:SetPoint("CENTER")
    nameplate.manaFrame:SetFrameLevel(0)
    nameplate.manaBar = CreateFrame("StatusBar", nil, nameplate.manaFrame, "BackdropTemplate")
    nameplate.manaBar:SetSize(88, 10)
    nameplate.manaBar:SetPoint("TOPLEFT", 8, -8)
    nameplate.manaBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    nameplate.manaBar:SetFrameLevel(1)
    nameplate.manaBar.bg = nameplate.manaBar:CreateTexture(nil, "BACKGROUND")
    nameplate.manaBar.bg:SetAllPoints()
    nameplate.manaBar.bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    nameplate.manaBar.bg:SetVertexColor(0.2, 0.2, 0.2, 0.5)
    nameplate.manaBar.text = nameplate.manaBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameplate.manaBar.text:SetPoint("CENTER")
    nameplate.manaBorderFrame.texture = nameplate.manaBorderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    nameplate.manaBorderFrame.texture:SetAllPoints()
    nameplate.manaBorderFrame.texture:SetTexture("Interface\\Addons\\Commander_Nameplate\\Nameplate-Border-Castbar.PNG")
    nameplate.castBar = CreateFrame("StatusBar", nil, nameplate.manaFrame, "BackdropTemplate")
    nameplate.castBar:SetSize(88, 10)
    nameplate.castBar:SetPoint("TOPLEFT", 8, -8)
    nameplate.castBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    nameplate.castBar:SetFrameLevel(2)
    nameplate.castBar:SetStatusBarColor(1, 0.7, 0)
    nameplate.castBar:Hide()
    nameplate.castBar.bg = nameplate.castBar:CreateTexture(nil, "BACKGROUND")
    nameplate.castBar.bg:SetAllPoints()
    nameplate.castBar.bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    nameplate.castBar.bg:SetVertexColor(0.2, 0.2, 0.2, 0.1)
    nameplate.castBar.icon = nameplate.castBar:CreateTexture(nil, "OVERLAY")
    nameplate.castBar.icon:SetSize(10, 10)
    nameplate.castBar.icon:SetPoint("LEFT", nameplate.castBar, "LEFT", -12, 0)
    nameplate.castBar.spellText = nameplate.castBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameplate.castBar.spellText:SetPoint("CENTER")
    nameplate.castBar.spellText:SetFont(nameplate.castBar.spellText:GetFont(), 8, "OUTLINE")

    nameplate.Update = function()
        local health, maxHealth = UnitHealth("player"), UnitHealthMax("player")
        local mana, maxMana = UnitPower("player"), UnitPowerMax("player")
        local inCombat = UnitAffectingCombat("player")
        
        if health == maxHealth and mana == maxMana and not inCombat then
            nameplate:Hide()
            return
        else
            nameplate:Show()
        end

        local healthPercentage = health / maxHealth
        nameplate.healthBar:SetMinMaxValues(0, maxHealth)
        nameplate.healthBar:SetValue(health)
        nameplate.level:SetText(UnitLevel("player"))
        nameplate.healthBar:SetStatusBarColor(healthPercentage > 0.5 and 0 or 1, healthPercentage > 0.2 and 1 or 0, 0)
        if CommanderNameplateDB and CommanderNameplateDB.showHealthPercent then
            nameplate.healthBar.text:SetText(string.format("%.0f%%", healthPercentage * 100))
            nameplate.healthBar.text:Show()
        else
            nameplate.healthBar.text:Hide()
        end
        nameplate.manaBar:SetMinMaxValues(0, maxMana)
        nameplate.manaBar:SetValue(mana)
        nameplate.manaBar:SetStatusBarColor(0, 0.44, 0.87)
        if CommanderNameplateDB and CommanderNameplateDB.showManaPercent then
            nameplate.manaBar.text:SetText(string.format("%.0f%%", mana / maxMana * 100))
            nameplate.manaBar.text:Show()
        else
            nameplate.manaBar.text:Hide()
        end
        local name, _, texture, startTime, endTime = UnitCastingInfo("player")
        if name then
            nameplate.castBar:Show()
            nameplate.manaBorderFrame:Show()
            nameplate.manaBar:Hide()
            local castDuration = (endTime - startTime) / 1000
            nameplate.castBar:SetMinMaxValues(0, castDuration)
            nameplate.castBar:SetValue(GetTime() - startTime / 1000)
            nameplate.castBar.spellText:SetText(name)
            nameplate.castBar.startTime = startTime / 1000
            nameplate.castBar.endTime = endTime / 1000
            nameplate.castBar.icon:SetTexture(texture)
            nameplate.castBar.icon:Show()
        else
            nameplate.castBar:Hide()
            nameplate.castBar.icon:Hide()
            if CommanderNameplateDB and (CommanderNameplateDB.alwaysShowMana or inCombat) then
                nameplate.manaBar:Show()
                nameplate.manaBorderFrame:Show()
            else
                nameplate.manaBar:Hide()
                nameplate.manaBorderFrame:Hide()
            end
        end
        if CommanderNameplateDB then
            nameplate.name:SetShown(CommanderNameplateDB.showPlayerName)
            nameplate:SetAlpha(CommanderNameplateDB.fadeWhileMoving and IsPlayerMoving() and CommanderNameplateDB.fadeIntensity or 1)
        else
            nameplate.name:Show()
            nameplate:SetAlpha(1)
        end
    end
    local events = {"UNIT_HEALTH", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD", "UNIT_POWER_UPDATE", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED"}
    for _, event in ipairs(events) do nameplate:RegisterEvent(event) end
    nameplate:SetScript("OnEvent", function(self, event, unit)
        if unit == "player" or event:match("^PLAYER_") then self.Update() end
    end)
    nameplate:SetScript("OnUpdate", function(self, elapsed)
        if UnitCastingInfo("player") then
            local name, _, _, startTime, endTime = UnitCastingInfo("player")
            if name then
                local castDuration = (endTime - startTime) / 1000
                local currentProgress = GetTime() - startTime / 1000
                self.castBar:SetValue(currentProgress)
            end
        end
        self.Update()
    end)
    return nameplate
end
local playerNameplate = CreatePlayerNameplate()
playerNameplate:SetMovable(true)
playerNameplate:EnableMouse(true)
playerNameplate:RegisterForDrag("LeftButton")
playerNameplate:SetScript("OnDragStart", playerNameplate.StartMoving)
playerNameplate:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
    CommanderNameplateDB.position = {point, "UIParent", relativePoint, xOfs, yOfs}
end)
playerNameplate.Update()
local settingsPanel = CreateFrame("Frame", "CommanderNameplateSettingsPanel", InterfaceOptionsFramePanelContainer)
settingsPanel.name = "Commander Nameplate"
Settings.RegisterCanvasLayoutCategory(optionsPanel, "Commander Nameplate")
local function CreateCheckbox(name, label, description, onClick)
    local check = CreateFrame("CheckButton", "CommanderNameplate"..name.."CheckButton", settingsPanel, "InterfaceOptionsCheckButtonTemplate")
    check:SetScript("OnClick", function(self) 
        onClick(self, self:GetChecked()) 
        CommanderNameplateDB[name] = self:GetChecked()
    end)
    check.label = _G[check:GetName().."Text"]
    check.label:SetText(label)
    check.tooltipText = label
    check.tooltipRequirement = description
    return check
end
local function CreateSlider(name, label, minVal, maxVal, valueStep)
    local slider = CreateFrame("Slider", "CommanderNameplate"..name.."Slider", settingsPanel, "OptionsSliderTemplate")
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
    slider:SetScript("OnValueChanged", function(self,value)
        self.editbox:SetText(string.format("%.2f", value))
        CommanderNameplateDB[name] = value
        playerNameplate.Update()
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
local showPlayerNameCheck = CreateCheckbox("showPlayerName", "Show Player Name", "Toggle visibility of player name on the nameplate", function(self, checked) 
    playerNameplate.Update()
end)
showPlayerNameCheck:SetPoint("TOPLEFT", 16, -16)
local fadeWhileMovingCheck = CreateCheckbox("fadeWhileMoving", "Fade While Moving", "Fade out the nameplate when the player is moving", function(self, checked) 
    playerNameplate.Update()
end)
fadeWhileMovingCheck:SetPoint("TOPLEFT", showPlayerNameCheck, "BOTTOMLEFT", 0, -24)
local fadeIntensitySlider = CreateSlider("fadeIntensity", "Fade Intensity", 0, 1, 0.01)
fadeIntensitySlider:SetPoint("TOPLEFT", fadeWhileMovingCheck, "BOTTOMLEFT", 0, -40)
fadeIntensitySlider:SetWidth(200)
local showHealthPercentCheck = CreateCheckbox("showHealthPercent", "Show Health Percentage", "Display health percentage on the health bar", function(self, checked) 
    playerNameplate.Update()
end)
showHealthPercentCheck:SetPoint("TOPLEFT", fadeIntensitySlider, "BOTTOMLEFT", 0, -32)
local showManaPercentCheck = CreateCheckbox("showManaPercent", "Show Mana Percentage", "Display mana percentage on the mana bar", function(self, checked) 
    playerNameplate.Update()
end)
showManaPercentCheck:SetPoint("TOPLEFT", showHealthPercentCheck, "BOTTOMLEFT", 0, -24)
local alwaysShowManaCheck = CreateCheckbox("alwaysShowMana", "Always Show Mana Bar", "Always display the mana bar, even when out of combat", function(self, checked) 
    playerNameplate.Update()
end)
alwaysShowManaCheck:SetPoint("TOPLEFT", showManaPercentCheck, "BOTTOMLEFT", 0, -24)

settingsPanel:RegisterEvent("ADDON_LOADED")
settingsPanel:SetScript("OnEvent", function(self, event, addon)
    if addon == "Commander_Nameplate" then
        CommanderNameplateDB = CommanderNameplateDB or {
            showPlayerName = true,
            fadeWhileMoving = false,
            fadeIntensity = 0.5,
            showHealthPercent = false,
            showManaPercent = false,
            alwaysShowMana = false
        }
        for k, v in pairs({showPlayerName = true, fadeWhileMoving = false, fadeIntensity = 0.5, showHealthPercent = false, showManaPercent = false, alwaysShowMana = false}) do
            CommanderNameplateDB[k] = CommanderNameplateDB[k] ~= nil and CommanderNameplateDB[k] or v
        end
        showPlayerNameCheck:SetChecked(CommanderNameplateDB.showPlayerName)
        fadeWhileMovingCheck:SetChecked(CommanderNameplateDB.fadeWhileMoving)
        fadeIntensitySlider:SetValue(CommanderNameplateDB.fadeIntensity)
        fadeIntensitySlider.editbox:SetText(string.format("%.2f", CommanderNameplateDB.fadeIntensity))
        showHealthPercentCheck:SetChecked(CommanderNameplateDB.showHealthPercent)
        showManaPercentCheck:SetChecked(CommanderNameplateDB.showManaPercent)
        alwaysShowManaCheck:SetChecked(CommanderNameplateDB.alwaysShowMana)
        playerNameplate.Update()
    end
end)
