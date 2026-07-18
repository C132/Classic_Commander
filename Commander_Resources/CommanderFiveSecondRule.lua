local fiveSecondRule = CreateFrame("Frame", "CommanderFiveSecondRule", UIParent)
fiveSecondRule:SetSize(150, 25)
fiveSecondRule:SetPoint("CENTER")
fiveSecondRule:SetMovable(true)
fiveSecondRule:EnableMouse(true)
fiveSecondRule:RegisterForDrag("LeftButton")
-- Position is persisted explicitly in CommanderResourceDB.BarPosition (a
-- single UIParent-relative point); opt out of the client's layout cache so
-- there is exactly one source of truth for where the bar lives
if fiveSecondRule.SetDontSavePosition then
    pcall(fiveSecondRule.SetDontSavePosition, fiveSecondRule, true)
end

local ApplyBarLayout -- defined below, after the bar's regions exist

local function IsAttachedToPlayerFrame()
    return CommanderResourceDB and CommanderResourceDB.BarMode == "PLAYER_FRAME"
end

fiveSecondRule:SetScript("OnDragStart", function(self)
    if IsAttachedToPlayerFrame() then return end
    if CommanderResourceDB and CommanderResourceDB.LockBar then return end
    self:StartMoving()
end)
fiveSecondRule:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self:SetUserPlaced(false)
    local left, bottom = self:GetLeft(), self:GetBottom()
    if CommanderResourceDB and left and bottom then
        CommanderResourceDB.BarPosition = { left = left, bottom = bottom }
    end
    ApplyBarLayout()
end)

local background = fiveSecondRule:CreateTexture(nil, "BACKGROUND")
background:SetAllPoints()
background:SetColorTexture(0.1, 0.1, 0.1, 0.8)

local border = CreateFrame("Frame", nil, fiveSecondRule, "BackdropTemplate")
border:SetAllPoints()
border:SetBackdrop({edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 1})
border:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

local manaBar = CreateFrame("StatusBar", nil, fiveSecondRule)
manaBar:SetPoint("TOPLEFT", 2, -2)
manaBar:SetPoint("BOTTOMRIGHT", -2, 2)
manaBar:SetStatusBarTexture("Interface\\AddOns\\Commander_Resources\\BarTexture.png")
manaBar:SetMinMaxValues(0, 5)
manaBar:SetValue(5)
manaBar:SetStatusBarColor(0.2, 0.7, 1)

local manaText = manaBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
manaText:SetPoint("CENTER")
manaText:SetText("Ready")

-- The attached bar sits in the player frame's name band, so the name text
-- yields to it: hidden (alpha 0) only while the bar is attached AND shown,
-- restored the moment the bar floats, hides, or the class has no mana.
-- Blizzard's name updates SetText only — they never touch alpha.
local function UpdateNameOverlay()
    local nameText = _G["PlayerName"]
    if not nameText then return end
    if IsAttachedToPlayerFrame() and fiveSecondRule:IsShown() then
        nameText:SetAlpha(0)
    else
        nameText:SetAlpha(1)
    end
end

-- Lay the bar out for the current placement mode.
-- FLOATING: a standalone movable bar on UIParent at the saved (or default
-- center) position — always a single UIParent point, so the frame can never
-- leave UIParent's anchor family.
-- PLAYER_FRAME: a slim strip parented to the player frame, occupying the
-- name band above the health bar (where the player's name normally sits),
-- mouse-disabled so it can never eat clicks meant for the (protected) unit
-- frame; it inherits the frame's scale and visibility.
function ApplyBarLayout()
    fiveSecondRule:ClearAllPoints()
    if IsAttachedToPlayerFrame() and PlayerFrame then
        fiveSecondRule:SetParent(PlayerFrame)
        fiveSecondRule:EnableMouse(false)
        manaText:SetFontObject(GameFontHighlightSmall)
        local healthBar = _G["PlayerFrameHealthBar"]
        if healthBar then
            local width = healthBar:GetWidth()
            fiveSecondRule:SetSize((width and width > 0) and width or 119, 12)
            -- Name band: the strip's bottom edge rests on the health bar's top
            fiveSecondRule:SetPoint("BOTTOMLEFT", healthBar, "TOPLEFT", 0, 2)
        else
            -- Classic frame geometry fallback: bars span x 90-209, name at ~y -27
            fiveSecondRule:SetSize(119, 12)
            fiveSecondRule:SetPoint("TOP", PlayerFrame, "TOP", 34, -27)
        end
    else
        fiveSecondRule:SetParent(UIParent)
        fiveSecondRule:EnableMouse(true)
        manaText:SetFontObject(GameFontHighlight)
        fiveSecondRule:SetSize(150, 25)
        local pos = CommanderResourceDB and CommanderResourceDB.BarPosition
        if pos and type(pos.left) == "number" and type(pos.bottom) == "number" then
            fiveSecondRule:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", pos.left, pos.bottom)
        else
            fiveSecondRule:SetPoint("CENTER")
        end
    end
    UpdateNameOverlay()
end

local lastManaChangeTime, playerIsFull, lastManaPower = 0, true, 0
local serverTickRate, lastRegenTime, tickOffset = 2, 0, 0
local wasReady, manaAtFiveSecondStart = true, 0
local readySound = SOUNDKIT.READY_CHECK
local OnFiveSecondRuleChanged
local UpdateVisibility

local function OnEvent(self, event, unit, powerType)
    if event == "UNIT_POWER_UPDATE" and unit == "player" and powerType == "MANA" then
        local currentTime = GetTime()
        local currentMana = UnitPower("player", Enum.PowerType.Mana)
        local maxMana = UnitPowerMax("player", Enum.PowerType.Mana)
        
        if currentMana ~= lastManaPower then
            if currentMana < lastManaPower then
                lastManaChangeTime = currentTime
                manaAtFiveSecondStart = currentMana
            elseif currentMana > lastManaPower then
                if lastRegenTime > 0 and currentTime > lastRegenTime then
                    serverTickRate = currentTime - lastRegenTime
                end
                lastRegenTime = currentTime
                tickOffset = currentTime % serverTickRate
            end
            playerIsFull = (currentMana == maxMana)
            lastManaPower = currentMana
        end
    elseif event == "UNIT_DISPLAYPOWER" then
        -- Display power changed (e.g. druid shapeshift); re-check the mana-user gate
        UpdateVisibility()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Fires on every loading screen; only register the listener once
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        Commander.AddListener(COMMANDER_RESOURCE_EVENTS.FIVE_SECOND_RULE_CHANGED, OnFiveSecondRuleChanged)
        ApplyBarLayout()
        UpdateVisibility()
    end
end

function OnFiveSecondRuleChanged()
    -- Settings changed: re-apply placement (mode may have switched) and the
    -- show/hide gate
    ApplyBarLayout()
    UpdateVisibility()
end

local function OnUpdate(self, elapsed)
    local currentTime = GetTime()
    local timeSinceLastChange = currentTime - lastManaChangeTime

    if playerIsFull then
        if not wasReady then
            manaBar:SetMinMaxValues(0, 5)
            manaBar:SetValue(5)
            manaText:SetText("Ready")
            manaBar:SetStatusBarColor(0.2, 0.7, 1)
            if not CommanderResourceDB or CommanderResourceDB.PlayReadySound ~= false then
                PlaySound(readySound, "Master")
            end
            wasReady = true
        end
    else
        wasReady = false
        local remainingTime = math.min(5, 5 - timeSinceLastChange)
        if remainingTime > 0 then
            manaBar:SetMinMaxValues(0, 5)
            manaBar:SetValue(remainingTime)
            manaText:SetFormattedText("%.1fs", remainingTime)
            manaBar:SetStatusBarColor(1, 0.7, 0.2)
        else
            local timeInCurrentTick = (currentTime - tickOffset) % serverTickRate
            manaBar:SetMinMaxValues(0, serverTickRate)
            manaBar:SetValue(math.min(serverTickRate, math.max(0, timeInCurrentTick)))

            local spirit = UnitStat("player", 5)
            local intellect = UnitStat("player", 4)
            local estimatedManaPerTick = (spirit / 5 + 15) * (intellect / 100) * 2

            local currentMana = UnitPower("player", Enum.PowerType.Mana)
            local manaGained = currentMana - manaAtFiveSecondStart
            manaText:SetFormattedText("+%.1f (%d)", estimatedManaPerTick, manaGained)
            manaBar:SetStatusBarColor(0.2, 0.9, 0.2)
        end
    end
end

-- Only mana users get the five second rule display (and its per-frame OnUpdate cost)
function UpdateVisibility()
    local isManaUser = UnitPowerType("player") == Enum.PowerType.Mana
    if isManaUser and CommanderResourceDB and CommanderResourceDB.ShowFiveSecondRule then
        fiveSecondRule:SetScript("OnUpdate", OnUpdate)
        fiveSecondRule:Show()
    else
        fiveSecondRule:SetScript("OnUpdate", nil)
        fiveSecondRule:Hide()
    end
    -- The player-frame name text yields only while the attached bar is shown
    UpdateNameOverlay()
end

fiveSecondRule:SetScript("OnEvent", OnEvent)
fiveSecondRule:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
fiveSecondRule:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
fiveSecondRule:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Hidden until PLAYER_ENTERING_WORLD applies the saved setting and mana-user gate
fiveSecondRule:Hide()

-- Shared with the options panel's "Reset Bar Position" button
function CommanderResources_ResetBarPosition()
    if CommanderResourceDB then
        CommanderResourceDB.BarPosition = nil
    end
    ApplyBarLayout()
    print("Commander Resources: bar position reset")
end

SLASH_RESETFSR1 = "/resetfsr"
SlashCmdList["RESETFSR"] = CommanderResources_ResetBarPosition