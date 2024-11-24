local fiveSecondRule = CreateFrame("Frame", "CommanderFiveSecondRule", UIParent)
fiveSecondRule:SetSize(150, 25)
fiveSecondRule:SetPoint("CENTER")
fiveSecondRule:SetMovable(true)
fiveSecondRule:EnableMouse(true)
fiveSecondRule:RegisterForDrag("LeftButton")
fiveSecondRule:SetScript("OnDragStart", fiveSecondRule.StartMoving)
fiveSecondRule:SetScript("OnDragStop", fiveSecondRule.StopMovingOrSizing)

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

local lastManaChangeTime, playerIsFull, lastManaPower = 0, true, 0
local serverTickRate, lastRegenTime, tickOffset = 2, 0, 0
local wasReady, manaAtFiveSecondStart = true, 0
local readySound = SOUNDKIT.READY_CHECK

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
                if lastRegenTime > 0 then
                    serverTickRate = currentTime - lastRegenTime
                end
                lastRegenTime = currentTime
                tickOffset = currentTime % serverTickRate
            end
            playerIsFull = (currentMana == maxMana)
            lastManaPower = currentMana
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        AddListener(COMMANDER_RESOURCE_EVENTS.FIVE_SECOND_RULE_CHANGED, OnFiveSecondRuleChanged)
    end
end

function OnFiveSecondRuleChanged()
    if CommanderResourceDB and CommanderResourceDB.ShowFiveSecondRule ~= nil then
        fiveSecondRule:SetShown(CommanderResourceDB.ShowFiveSecondRule)
    end
end

local function OnUpdate(self, elapsed)
    local currentTime = GetTime()
    local timeSinceLastChange = currentTime - lastManaChangeTime
    local currentMana = UnitPower("player", Enum.PowerType.Mana)
    
    if playerIsFull then
        manaBar:SetValue(5)
        manaText:SetText("Ready")
        manaBar:SetStatusBarColor(0.2, 0.7, 1)
        
        if not wasReady then
            PlaySound(readySound, "Master")
            wasReady = true
        end
    else
        wasReady = false
        local remainingTime = math.min(5, 5 - timeSinceLastChange)
        if remainingTime > 0 then
            manaBar:SetValue(remainingTime)
            manaBar:SetMinMaxValues(0, 5)
            manaText:SetFormattedText("%.1fs", remainingTime)
            manaBar:SetStatusBarColor(1, 0.7, 0.2)
        else
            local timeInCurrentTick = (currentTime - tickOffset) % serverTickRate
            manaBar:SetMinMaxValues(0, serverTickRate)
            manaBar:SetValue(math.min(serverTickRate, math.max(0, timeInCurrentTick)))
            
            local spirit = UnitStat("player", 5)
            local intellect = UnitStat("player", 4)
            local estimatedManaPerTick = (spirit / 5 + 15) * (intellect / 100) * 2

            local manaGained = currentMana - manaAtFiveSecondStart
            manaText:SetFormattedText("+%.1f (%d)", estimatedManaPerTick, manaGained)
            manaBar:SetStatusBarColor(0.2, 0.9, 0.2)
        end
    end
end

fiveSecondRule:SetScript("OnEvent", OnEvent)
fiveSecondRule:SetScript("OnUpdate", OnUpdate)
fiveSecondRule:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
fiveSecondRule:RegisterEvent("PLAYER_ENTERING_WORLD")

fiveSecondRule:Show()

SLASH_RESETFSR1 = "/resetfsr"
SlashCmdList["RESETFSR"] = function()
    fiveSecondRule:ClearAllPoints()
    fiveSecondRule:SetPoint("CENTER")
    print("Five Second Rule frame position has been reset.")
end