-- Cast bar color presets offered in settings
local CASTBAR_COLORS = {
    GOLD = { 1, 0.7, 0 },
    GREEN = { 0.3, 1, 0.4 },
    BLUE = { 0.35, 0.65, 1 },
    PURPLE = { 0.7, 0.35, 1 },
    RED = { 1, 0.3, 0.25 },
}

-- Power bar colored by actual power type (mana/rage/energy), not always
-- mana blue; falls back to the client's own PowerBarColor when present
local FALLBACK_POWER_COLORS = {
    [0] = { r = 0, g = 0.44, b = 0.87 },  -- mana
    [1] = { r = 1, g = 0.2, b = 0.2 },    -- rage
    [2] = { r = 1, g = 0.5, b = 0.25 },   -- focus
    [3] = { r = 1, g = 0.9, b = 0.3 },    -- energy
}

local function PowerColor()
    local powerType = UnitPowerType("player")
    local color = (PowerBarColor and PowerBarColor[powerType]) or FALLBACK_POWER_COLORS[powerType]
        or FALLBACK_POWER_COLORS[0]
    return color.r, color.g, color.b
end

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
    -- "BOLD" is not a valid font flag and the 2.5.6 client rejects it with an
    -- error (aborting this whole file); OUTLINE gives the intended emphasis
    nameplate.name:SetFont(nameplate.name:GetFont(), 14, "OUTLINE")
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

        -- "Power is fine" means empty for rage (idles at 0), full for
        -- mana/energy — a warrior at full health should not show a plate
        -- forever just because rage is not maxed
        local powerIdle
        if UnitPowerType("player") == 1 then
            powerIdle = (mana == 0)
        else
            powerIdle = (mana == maxMana)
        end
        local casting = UnitCastingInfo("player") or UnitChannelInfo("player")
        local alwaysShow = CommanderNameplateDB and CommanderNameplateDB.alwaysShowPlate
        if health == maxHealth and powerIdle and not inCombat and not casting
            and not alwaysShow and not nameplate._dragging then
            nameplate:Hide()
            return
        else
            nameplate:Show()
        end

        local healthPercentage = health / maxHealth
        nameplate.healthBar:SetMinMaxValues(0, maxHealth)
        nameplate.healthBar:SetValue(health)
        nameplate.level:SetText(UnitLevel("player"))
        nameplate.level:SetShown(not CommanderNameplateDB or CommanderNameplateDB.showLevel)
        -- Low-health pulse: driven from the 0.1s update cadence
        if CommanderNameplateDB and CommanderNameplateDB.lowHealthFlash and healthPercentage <= 0.25 then
            nameplate.healthBar:SetAlpha(0.55 + 0.45 * math.abs(math.sin(GetTime() * 5)))
        else
            nameplate.healthBar:SetAlpha(1)
        end
        if CommanderNameplateDB and CommanderNameplateDB.classColorHealth then
            local _, classToken = UnitClass("player")
            local color = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
            if color then
                nameplate.healthBar:SetStatusBarColor(color.r, color.g, color.b)
            end
        else
            nameplate.healthBar:SetStatusBarColor(healthPercentage > 0.5 and 0 or 1, healthPercentage > 0.2 and 1 or 0, 0)
        end
        if CommanderNameplateDB and CommanderNameplateDB.showHealthPercent then
            nameplate.healthBar.text:SetText(string.format("%.0f%%", healthPercentage * 100))
            nameplate.healthBar.text:Show()
        else
            nameplate.healthBar.text:Hide()
        end
        nameplate.manaBar:SetMinMaxValues(0, maxMana)
        nameplate.manaBar:SetValue(mana)
        nameplate.manaBar:SetStatusBarColor(PowerColor())
        if CommanderNameplateDB and CommanderNameplateDB.showManaPercent then
            nameplate.manaBar.text:SetText(string.format("%.0f%%", mana / maxMana * 100))
            nameplate.manaBar.text:Show()
        else
            nameplate.manaBar.text:Hide()
        end
        local castColor = CASTBAR_COLORS[CommanderNameplateDB and CommanderNameplateDB.castBarColor or "GOLD"]
            or CASTBAR_COLORS.GOLD
        nameplate.castBar:SetStatusBarColor(castColor[1], castColor[2], castColor[3])
        local hidePower = CommanderNameplateDB and CommanderNameplateDB.hidePowerBar
        local name, _, texture, startTime, endTime = UnitCastingInfo("player")
        if not name then
            -- Channels share the first five return positions
            name, _, texture, startTime, endTime = UnitChannelInfo("player")
        end
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
            nameplate.castBar.icon:SetShown(not CommanderNameplateDB or CommanderNameplateDB.showCastIcon)
        else
            nameplate.castBar:Hide()
            nameplate.castBar.icon:Hide()
            if not hidePower and CommanderNameplateDB and (CommanderNameplateDB.alwaysShowMana or inCombat) then
                nameplate.manaBar:Show()
                nameplate.manaBorderFrame:Show()
            else
                nameplate.manaBar:Hide()
                nameplate.manaBorderFrame:Hide()
            end
        end
        if CommanderNameplateDB then
            nameplate.name:SetShown(CommanderNameplateDB.showPlayerName)
            nameplate:SetScale(CommanderNameplateDB.plateScale or 1)
            -- Mouse only while unlocked: a permanently mouse-enabled plate
            -- silently eats clicks near the top-center of the screen
            nameplate:EnableMouse(CommanderNameplateDB.unlockPlate or false)
            nameplate:SetAlpha(CommanderNameplateDB.fadeWhileMoving and IsPlayerMoving() and CommanderNameplateDB.fadeIntensity or 1)
        else
            nameplate.name:Show()
            nameplate:SetAlpha(1)
        end
    end
    local unitEvents = {"UNIT_HEALTH", "UNIT_POWER_UPDATE", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED"}
    for _, event in ipairs(unitEvents) do nameplate:RegisterUnitEvent(event, "player") end
    local events = {"PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED"}
    for _, event in ipairs(events) do nameplate:RegisterEvent(event) end
    nameplate:SetScript("OnEvent", function(self, event, unit)
        if unit == "player" or event:match("^PLAYER_") then self.Update() end
    end)
    nameplate.updateElapsed = 0
    nameplate:SetScript("OnUpdate", function(self, elapsed)
        if self.castBar:IsShown() then
            local name, _, _, startTime = UnitCastingInfo("player")
            if not name then
                name, _, _, startTime = UnitChannelInfo("player")
            end
            if name then
                self.castBar:SetValue(GetTime() - startTime / 1000)
            end
        end
        self.updateElapsed = self.updateElapsed + elapsed
        if self.updateElapsed >= 0.1 then
            self.updateElapsed = 0
            self.Update()
        end
    end)
    return nameplate
end
local playerNameplate = CreatePlayerNameplate()
playerNameplate:SetMovable(true)
playerNameplate:RegisterForDrag("LeftButton")
playerNameplate:SetScript("OnDragStart", function(self)
    self._dragging = true
    self:StartMoving()
end)
playerNameplate:SetScript("OnDragStop", function(self)
    self._dragging = false
    self:StopMovingOrSizing()
    local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
    -- Screen-space offsets (scale multiplied out) so a later Plate Scale
    -- change keeps the plate where the user dragged it; the 6th field
    -- marks the new format
    local scale = self:GetScale() or 1
    CommanderNameplateDB.position = {point, "UIParent", relativePoint, xOfs * scale, yOfs * scale, true}
end)
playerNameplate.Update()

local function ApplySavedPosition()
    if CommanderNameplateDB and CommanderNameplateDB.position then
        local point, _, relativePoint, xOfs, yOfs, screenSpace = unpack(CommanderNameplateDB.position)
        playerNameplate:ClearAllPoints()
        if screenSpace then
            local scale = CommanderNameplateDB.plateScale or 1
            playerNameplate:SetPoint(point, UIParent, relativePoint, xOfs / scale, yOfs / scale)
        else
            playerNameplate:SetPoint(point, UIParent, relativePoint, xOfs, yOfs)
        end
    end
end

Commander.AddListener(COMMANDER_NAMEPLATE_EVENTS.UPDATE, function()
    ApplySavedPosition()
    playerNameplate.Update()
end)

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, addon)
    if addon == "Commander_Nameplate" then
        self:UnregisterEvent("ADDON_LOADED")
        ApplySavedPosition()
        playerNameplate.Update()
    end
end)
