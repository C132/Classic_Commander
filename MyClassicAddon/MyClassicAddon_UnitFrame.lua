local function CreateStatusBar(parent, anchorPoint, yOffset, color, height)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetSize(200, height)
    bar:SetPoint("TOP", parent, anchorPoint, 0, yOffset - 6)
    bar:SetStatusBarTexture("Interface\\AddOns\\MyClassicAddon\\BarTexture.png")
    bar:SetStatusBarColor(unpack(color))
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(100)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetTexture("Interface\\AddOns\\MyClassicAddon\\BarTexture.png")
    bg:SetVertexColor(0.2, 0.2, 0.2, 0.8)

    local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar.text = text

    -- Add spark texture
    local spark = bar:CreateTexture(nil, "OVERLAY")
    spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    spark:SetSize(32, height * 2)
    spark:SetBlendMode("ADD")
    spark:Hide()  -- Hide by default
    bar.spark = spark

    return bar
end

local function CreateCustomFrame(unit)
    local frameName = unit == "player" and "MyCustomPlayerFrame" or "MyCustomTargetFrame"
    local frame = CreateFrame("Button", frameName, UIParent, "BackdropTemplate")
    frame:SetSize(214, 62)
    frame:SetPoint("CENTER", UIParent, "CENTER", unit == "player" and -200 or 200, 0)
    
    -- Make the frame draggable
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    
    -- Set the frame background with a different edge file and slightly more visible background
    frame:SetBackdrop({
        bgFile = "Interface\\AddOns\\MyClassicAddon\\BarTexture.png",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = false,
        tileSize = 32,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0, 0, 0, .55)  -- Increased alpha from .5 to .55
    frame:SetBackdropBorderColor(0.7, 0.7, 0.7, 1)

    -- Add name text
    frame.nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.nameText:SetPoint("BOTTOM", frame, "TOP", 0, 5)

    frame.healthBar = CreateStatusBar(frame, "TOP", 0, {0, 1, 0}, 25)
    frame.manaBar = CreateStatusBar(frame, "TOP", -25, {1, 1, 0}, 20)
    
    frame.swingTimer = CreateStatusBar(frame, "TOP", -45, {1, 0.5, 0}, 5)
    frame.castBar = CreateStatusBar(frame, "TOP", -45, {1, 0.7, 0}, 5)
    frame.castBar:Hide()

    -- Create level indicator at top left for player and top right for target
    frame.levelIndicator = CreateFrame("Frame", nil, frame)
    frame.levelIndicator:SetSize(32, 32)
    if unit == "player" then
        frame.levelIndicator:SetPoint("TOPLEFT", frame, "TOPLEFT", -16, 18)  -- Moved up slightly
    else
        frame.levelIndicator:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 16, 16)
    end
    
    frame.levelIndicator.bg = frame.levelIndicator:CreateTexture(nil, "BACKGROUND")
    frame.levelIndicator.bg:SetAllPoints()
    frame.levelIndicator.bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    frame.levelIndicator.bg:SetVertexColor(0, 0, 0, 1)
    
    frame.levelIndicator.border = frame.levelIndicator:CreateTexture(nil, "BORDER")
    frame.levelIndicator.border:SetAllPoints()
    
    frame.levelIndicator.text = frame.levelIndicator:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.levelIndicator.text:SetPoint("CENTER", frame.levelIndicator, "CENTER", 0, 0)
    
    if unit == "player" then
        frame.levelIndicator.expText = frame.levelIndicator:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
        frame.levelIndicator.expText:SetPoint("TOP", frame.levelIndicator, "BOTTOM", 0, 12)  -- Centered below level
        frame.levelIndicator.expText:SetTextColor(1, 0, 1)  -- Purple color for exp
    end

    -- Create debuff and buff frames for both player and target
    frame.debuffs = CreateFrame("Frame", nil, frame)
    frame.debuffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -5)
    frame.debuffs:SetSize(214, 32)

    frame.buffs = CreateFrame("Frame", nil, frame)
    frame.buffs:SetPoint("TOPLEFT", frame.debuffs, "BOTTOMLEFT", 0, -5)
    frame.buffs:SetSize(214, 24)

    -- Add right-click menu and left-click functionality
    frame:RegisterForClicks("AnyUp")
    frame:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            -- PlayerFrameDropDown/TargetFrameDropDown no longer exist on the 2.5.5 client
            if unit == "player" then
                UnitPopup_OpenMenu("SELF", { unit = "player" })
            else
                UnitPopup_OpenMenu("TARGET", { unit = "target" })
            end
        elseif button == "LeftButton" and unit == "player" then
            TargetUnit("player")
        end
    end)

    -- Add full screen glow effect for player frame
    if unit == "player" then
        frame.fullScreenGlow = WorldFrame:CreateTexture(nil, "BACKGROUND", nil, -8)  -- -8 is the lowest drawable layer
        frame.fullScreenGlow:SetTexture("Interface\\AddOns\\MyClassicAddon\\FullScreenGlow.png")
        frame.fullScreenGlow:SetAllPoints(WorldFrame)
        frame.fullScreenGlow:SetBlendMode("ADD")
        frame.fullScreenGlow:SetAlpha(0)
    end

    return frame
end

local function UpdateCustomFrame(frame, unit)
    local health = UnitHealth(unit)
    local maxHealth = UnitHealthMax(unit)
    frame.healthBar:SetMinMaxValues(0, maxHealth)
    
    -- Check if health is within the valid range before setting the value
    if health >= -3.402823e+38 and health <= 3.402823e+38 then
        frame.healthBar:SetValue(health)
    else
        -- If health is outside the valid range, set it to 0 or maxHealth
        frame.healthBar:SetValue(health < 0 and 0 or maxHealth)
    end
    
    frame.healthBar.text:SetText(tostring(health) .. " / " .. tostring(maxHealth))

    -- Update name
    local name = UnitName(unit)
    if unit == "target" and UnitClassification(unit) == "elite" then
        frame.nameText:SetText("|cFFA335EE" .. name .. "|r")  -- Purple color for elite targets
    else
        frame.nameText:SetText(name)
    end

    -- Color target's health bar based on hostility
    if unit == "target" then
        local r, g, b
        if UnitIsFriend("player", unit) then
            r, g, b = 0, 1, 0 -- Green for friendly
        elseif UnitIsEnemy("player", unit) then
            r, g, b = 1, 0, 0 -- Red for hostile
        else
            r, g, b = 1, 1, 0 -- Yellow for neutral
        end
        frame.healthBar:SetStatusBarColor(r, g, b)
    end

    local powerType = UnitPowerType(unit)
    local power = UnitPower(unit, powerType)
    local maxPower = UnitPowerMax(unit, powerType)
    frame.manaBar:SetMinMaxValues(0, maxPower)
    frame.manaBar:SetValue(power)
    frame.manaBar.text:SetText(tostring(power) .. " / " .. tostring(maxPower))

    -- Update mana bar spark
    local powerPercentage = power / maxPower
    if powerPercentage > 0.15 then
        frame.manaBar.spark:Show()
        local sparkPosition = frame.manaBar:GetWidth() * powerPercentage
        frame.manaBar.spark:SetPoint("CENTER", frame.manaBar, "LEFT", sparkPosition, 0)
    else
        frame.manaBar.spark:Hide()
    end

    -- Update swing timer or cast bar
    local name, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible = UnitCastingInfo(unit)
    if not name then
        name, text, texture, startTime, endTime, isTradeSkill = UnitChannelInfo(unit)
    end
    if name then
        frame.swingTimer:Hide()
        frame.castBar:Show()
        local castDuration = endTime - startTime
        local castElapsed = GetTime() * 1000 - startTime
        frame.castBar:SetMinMaxValues(0, castDuration)
        frame.castBar:SetValue(castElapsed)
        frame.castBar.text:SetText(name)

        -- Adjust mana bar and cast bar heights
        frame.manaBar:SetHeight(13)  -- 20 - 7
        frame.castBar:SetHeight(12)  -- 5 + 7
        frame.manaBar:SetPoint("TOP", frame, "TOP", 0, -31)  -- Adjust position
        frame.castBar:SetPoint("TOP", frame, "TOP", 0, -44)  -- Adjust position

        -- Parse the spell name to determine the spell school
        local function getSpellSchool(spellName)
            spellName = string.lower(spellName)
            
            local frostKeywords = {"frost", "ice", "freeze", "blizzard", "frostbolt", "cone of cold"}
            local holyKeywords = {"holy", "light", "heal", "smite", "flash", "prayer", "resurrection", "exorcism", "consecration"}
            local fireKeywords = {"fire", "flame", "immolate", "scorch", "pyroblast", "blast wave", "flamestrike", "searing", "incinerate"}
            local natureKeywords = {"nature", "lightning", "wrath", "bolt", "starfire", "hurricane", "tranquility", "healing", "touch"}
            local shadowKeywords = {"shadow", "mind", "psychic", "flay", "blast", "mana burn", "devouring plague"}
            local arcaneKeywords = {"arcane", "mana", "magic", "polymorph", "missiles", "explosion", "conjure", "evocation", "counterspell"}
            
            for _, keyword in ipairs(frostKeywords) do
                if string.find(spellName, keyword) then return "Frost" end
            end
            for _, keyword in ipairs(natureKeywords) do
                if string.find(spellName, keyword) then return "Nature" end
            end
            for _, keyword in ipairs(holyKeywords) do
                if string.find(spellName, keyword) then return "Holy" end
            end
            for _, keyword in ipairs(fireKeywords) do
                if string.find(spellName, keyword) then return "Fire" end
            end
            for _, keyword in ipairs(shadowKeywords) do
                if string.find(spellName, keyword) then return "Shadow" end
            end
            for _, keyword in ipairs(arcaneKeywords) do
                if string.find(spellName, keyword) then return "Arcane" end
            end
            
            return "Unknown"
        end

        -- Set a default color for the cast bar
        local spellSchool = getSpellSchool(name)
        local r, g, b = 1, 0.7, 0  -- Default color (yellow-orange)
        
        if spellSchool == "Holy" then
            r, g, b = 1, 0.95, 0.2  -- Bright golden yellow
        elseif spellSchool == "Fire" then
            r, g, b = 1, 0.2, 0  -- Vivid orange-red
        elseif spellSchool == "Nature" then
            r, g, b = 0, 1, .3  -- Vibrant green
        elseif spellSchool == "Frost" then
            r, g, b = 0, 0.8, 1  -- Electric blue
        elseif spellSchool == "Shadow" then
            r, g, b = 0.6, 0, 1  -- Deep purple
        elseif spellSchool == "Arcane" then
            r, g, b = 1, 0.3, 1  -- Bright magenta
        end
        
        frame.castBar:SetStatusBarColor(r, g, b)

        -- Animate full screen glow for player
        if unit == "player" then
            local castProgress = castElapsed / castDuration
            local glowIntensity = math.max(0, math.min(1, castProgress))  -- Ensure glowIntensity is between 0 and 1
            frame.fullScreenGlow:SetVertexColor(r, g, b)
            frame.fullScreenGlow:SetAlpha(glowIntensity)
        end
    else
        frame.castBar:Hide()
        frame.swingTimer:Show()
        -- Reset mana bar and swing timer heights
        frame.manaBar:SetHeight(20)
        frame.swingTimer:SetHeight(5)
        frame.manaBar:SetPoint("TOP", frame, "TOP", 0, -31)  -- Reset position
        frame.swingTimer:SetPoint("TOP", frame, "TOP", 0, -51)  -- Reset position
        local mainHandSpeed, offHandSpeed = UnitAttackSpeed(unit)
        local swingTime = mainHandSpeed or 0
        if swingTime > 0 then
            local currentTime = GetTime()
            local elapsedTime = currentTime % swingTime
            frame.swingTimer:SetMinMaxValues(0, swingTime)
            frame.swingTimer:SetValue(elapsedTime)
            frame.swingTimer.text:SetText(string.format("%.1f", math.floor(swingTime * 10) / 10))
        else
            frame.swingTimer:SetMinMaxValues(0, 1)
            frame.swingTimer:SetValue(0)
            frame.swingTimer.text:SetText("")
        end

        -- Hide full screen glow for player when not casting
        if unit == "player" then
            frame.fullScreenGlow:SetAlpha(0)
        end
    end

    -- Update debuffs
    for i = 1, 40 do
        -- UnitDebuff is a deprecation shim on the 2.5.5 client; use C_UnitAuras
        local aura = C_UnitAuras.GetDebuffDataByIndex(unit, i)
        local name, icon, count, debuffType, duration, expirationTime
        if aura then
            name, icon, count, debuffType, duration, expirationTime =
                aura.name, aura.icon, aura.applications, aura.dispelName, aura.duration, aura.expirationTime
        end
        if name then
            local debuffFrame = frame.debuffs[i]
            if not debuffFrame then
                debuffFrame = CreateFrame("Frame", nil, frame.debuffs)
                debuffFrame:SetSize(24, 24)
                debuffFrame.icon = debuffFrame:CreateTexture(nil, "BACKGROUND")
                debuffFrame.icon:SetAllPoints()
                debuffFrame.count = debuffFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
                debuffFrame.count:SetPoint("BOTTOMRIGHT", 2, 2)
                debuffFrame.cooldown = CreateFrame("Cooldown", nil, debuffFrame, "CooldownFrameTemplate")
                debuffFrame.cooldown:SetAllPoints()
                debuffFrame.cooldown:SetReverse(true)
                debuffFrame.border = debuffFrame:CreateTexture(nil, "OVERLAY")
                debuffFrame.border:SetAllPoints()
                debuffFrame.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
                debuffFrame.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
                frame.debuffs[i] = debuffFrame

                -- Enable tooltip for debuff
                debuffFrame:EnableMouse(true)
                debuffFrame:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetUnitDebuff(unit, i)
                    GameTooltip:Show()
                end)
                debuffFrame:SetScript("OnLeave", function(self)
                    GameTooltip:Hide()
                end)
            end
            debuffFrame.icon:SetTexture(icon)
            if count > 1 then
                debuffFrame.count:SetText(count)
            else
                debuffFrame.count:SetText("")
            end
            debuffFrame:SetPoint("TOPLEFT", frame.debuffs, "TOPLEFT", (i-1)*26, 0)
            debuffFrame:Show()
            
            if duration and duration > 0 then
                debuffFrame.cooldown:SetCooldown(expirationTime - duration, duration)
                debuffFrame.cooldown:Show()
            else
                debuffFrame.cooldown:Hide()
            end

            -- Color the border based on debuff type
            local color
            if debuffType == "Magic" then
                color = {0.2, 0.6, 1.0}
            elseif debuffType == "Curse" then
                color = {0.6, 0.0, 1.0}
            elseif debuffType == "Disease" then
                color = {0.6, 0.4, 0}
            elseif debuffType == "Poison" then
                color = {0.0, 0.6, 0}
            else
                color = {0.8, 0, 0}
            end
            debuffFrame.border:SetVertexColor(unpack(color))
        elseif frame.debuffs[i] then
            frame.debuffs[i]:Hide()
        else
            break
        end
    end

    -- Update buffs
    for i = 1, 40 do
        -- UnitBuff is a deprecation shim on the 2.5.5 client; use C_UnitAuras
        local aura = C_UnitAuras.GetBuffDataByIndex(unit, i)
        local name, icon, count, buffType, duration, expirationTime
        if aura then
            name, icon, count, buffType, duration, expirationTime =
                aura.name, aura.icon, aura.applications, aura.dispelName, aura.duration, aura.expirationTime
        end
        if name then
            local buffFrame = frame.buffs[i]
            if not buffFrame then
                buffFrame = CreateFrame("Frame", nil, frame.buffs)
                buffFrame:SetSize(20, 20)  -- Slightly smaller than debuffs
                buffFrame.icon = buffFrame:CreateTexture(nil, "BACKGROUND")
                buffFrame.icon:SetAllPoints()
                buffFrame.count = buffFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
                buffFrame.count:SetPoint("BOTTOMRIGHT", 2, 2)
                buffFrame.cooldown = CreateFrame("Cooldown", nil, buffFrame, "CooldownFrameTemplate")
                buffFrame.cooldown:SetAllPoints()
                buffFrame.cooldown:SetReverse(true)
                frame.buffs[i] = buffFrame

                -- Enable tooltip for buff
                buffFrame:EnableMouse(true)
                buffFrame:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetUnitBuff(unit, i)
                    GameTooltip:Show()
                end)
                buffFrame:SetScript("OnLeave", function(self)
                    GameTooltip:Hide()
                end)
            end
            buffFrame.icon:SetTexture(icon)
            if count > 1 then
                buffFrame.count:SetText(count)
            else
                buffFrame.count:SetText("")
            end
            buffFrame:SetPoint("TOPLEFT", frame.buffs, "TOPLEFT", (i-1)*22, 0)  -- Adjust spacing for smaller size
            buffFrame:Show()
            
            if duration and duration > 0 then
                buffFrame.cooldown:SetCooldown(expirationTime - duration, duration)
                buffFrame.cooldown:Show()
            else
                buffFrame.cooldown:Hide()
            end
        elseif frame.buffs[i] then
            frame.buffs[i]:Hide()
        else
            break
        end
    end

    -- Update level indicator for both player and target
    local level = UnitLevel(unit)
    frame.levelIndicator.text:SetText(tostring(level))

    if unit == "player" then
        local currentXP = UnitXP("player")
        local maxXP = UnitXPMax("player")
        local xpPercentage = math.floor((currentXP / maxXP) * 100)
        frame.levelIndicator.expText:SetText(xpPercentage .. "%")
    end
end

local function HideDefaultFrames()
--    PlayerFrame:Hide()
--    PlayerFrame:UnregisterAllEvents()
--    TargetFrame:Hide()
--    TargetFrame:UnregisterAllEvents()
--    CastingBarFrame:Hide()
--    CastingBarFrame:UnregisterAllEvents()
end

local customPlayerFrame = CreateCustomFrame("player")
local customTargetFrame = CreateCustomFrame("target")
HideDefaultFrames()

local updateFrame = CreateFrame("Frame")
updateFrame:SetScript("OnUpdate", function()
    if Config.HideUnitFrames then
        customPlayerFrame:Hide()
        customTargetFrame:Hide()
    else
        UpdateCustomFrame(customPlayerFrame, "player")
        customPlayerFrame:Show()
        if UnitExists("target") then
            customTargetFrame:Show()
            UpdateCustomFrame(customTargetFrame, "target")
        else
            customTargetFrame:Hide()
        end
    end
end)
