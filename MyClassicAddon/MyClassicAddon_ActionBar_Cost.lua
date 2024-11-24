local ActionBarInfo = {}
ActionBarInfo.__index = ActionBarInfo

function ActionBarInfo:New()
    local self = setmetatable({}, ActionBarInfo)
    self.infoTexts = {}
    self.frame = CreateFrame("Frame")
    self.cachedSpellInfo = {}
    self.cachedCosts = {}
    self.lastPlayerMana = UnitPower("player", 0)
    return self
end

function ActionBarInfo:UpdateInfo(button, text)
    local actionType, id = GetActionInfo(button.action)
    if actionType ~= "spell" then
        text:Hide()
        return
    end

    local spellInfo = self.cachedSpellInfo[id]
    if not spellInfo then
        spellInfo = {GetSpellInfo(id)}
        self.cachedSpellInfo[id] = spellInfo
    end
    local spellName = spellInfo[1]
    if not spellName then
        text:Hide()
        return
    end

    local cost = self.cachedCosts[id]
    if not cost then
        local costTable = GetSpellPowerCost(spellName)
        if costTable and #costTable > 0 then
            cost = costTable[1].cost
            self.cachedCosts[id] = cost
        end
    end

    if not cost or cost <= 0 then
        text:Hide()
        return
    end

    local playerMana = UnitPower("player", 0)
    local displayText = ""
    
    if Config.ActionBarCostMode == "RAW_COST" then
        displayText = tostring(cost)
    elseif Config.ActionBarCostMode == "CASTS_AVAILABLE" then
        local castCount = playerMana / cost
        displayText = string.format("%.1f", castCount)
    elseif Config.ActionBarCostMode == "EFFICIENCY" then
        local spellDamage = Config.cachedOutputs[id]
        if spellDamage and spellDamage > 0 then
            local damagePerCost = spellDamage / cost
            displayText = string.format("%.2f", damagePerCost)
        end
    elseif Config.ActionBarCostMode == "TIME_TO_OOM" then
        local castTime = spellInfo[4] / 1000 or 1.5  -- Convert to seconds, default to 1.5 if instant
        local castsUntilOOM = playerMana / cost
        local timeToOOM = castsUntilOOM * castTime
        displayText = string.format("%.0fs", timeToOOM)
    end
    
    if displayText ~= "" then
        text:SetText(displayText)
        text:Show()
    else
        text:Hide()
    end
end

function ActionBarInfo:CreateOverlayText(button)
    local infoText = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    infoText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    infoText:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    infoText:SetTextColor(0, 0.82, 1)  -- Light blue color
    infoText:SetDrawLayer("OVERLAY", 7)  -- Set a high draw layer
    table.insert(self.infoTexts, infoText)
    return infoText
end

function ActionBarInfo:Initialize()
    for i = 1, 24 do
        local button = i <= 12 and _G["ActionButton" .. i] or _G["MultiBarBottomLeftButton" .. (i - 12)]
        if button then
            self:CreateOverlayText(button)
        end
    end
    self:SetupEventHandlers()
end

function ActionBarInfo:Update()
    local playerMana = UnitPower("player", 0)
    if playerMana ~= self.lastPlayerMana or self.forceUpdate then
        for i, infoText in ipairs(self.infoTexts) do
            local button = i <= 12 and _G["ActionButton" .. i] or _G["MultiBarBottomLeftButton" .. (i - 12)]
            self:UpdateInfo(button, infoText)
        end
        self.lastPlayerMana = playerMana
        self.forceUpdate = false
    end
end

function ActionBarInfo:SetupEventHandlers()
    self.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    self.frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    self.frame:RegisterEvent("UNIT_POWER_UPDATE")
    
    self.frame:SetScript("OnEvent", function(_, event, ...)
        if event == "UNIT_POWER_UPDATE" then
            local unit = ...
            if unit == "player" then
                self:Update()
            end
        elseif event == "ACTIONBAR_SLOT_CHANGED" then
            self.cachedSpellInfo = {}
            self.cachedCosts = {}
            self.forceUpdate = true
            self:Update()
        else
            self.forceUpdate = true
            self:Update()
        end
    end)

    self.frame:SetScript("OnUpdate", function()
        self:Update()
    end)
end

local actionBarInfo = ActionBarInfo:New()
actionBarInfo:Initialize()

AddListener(MY_CLASSIC_ADDON_EVENTS.ACTIONBAR_COST_MODE_CHANGED, function()
    actionBarInfo.forceUpdate = true
    actionBarInfo:Update()
end)

return actionBarInfo
