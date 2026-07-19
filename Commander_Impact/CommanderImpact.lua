-- Commander Impact: payoff feedback for the player's own blows, using the
-- same full-screen language as Commander Casting's glow (a WorldFrame
-- vignette texture with ADD blending) — but as a decaying pulse instead of
-- a rising buildup. Kills pulse gold with a TARGET ELIMINATED float; crits
-- past the threshold pulse red-orange, scaled to the damage.

local TEXT_HOLD = 1.4

local pulse = WorldFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
pulse:SetTexture("Interface\\FullScreenTextures\\LowHealth")
pulse:SetAllPoints(WorldFrame)
pulse:SetBlendMode("ADD")
pulse:SetAlpha(0)

local driver = CreateFrame("Frame")
local pulseAlpha = 0
local decayRate = 1.1

local function OnDecay(self, elapsed)
    pulseAlpha = pulseAlpha - elapsed * decayRate
    if pulseAlpha <= 0 then
        pulseAlpha = 0
        pulse:SetAlpha(0)
        driver:SetScript("OnUpdate", nil)
        return
    end
    pulse:SetAlpha(pulseAlpha)
end

local function Pulse(r, g, b, strength)
    pulse:SetVertexColor(r, g, b)
    pulseAlpha = math.max(pulseAlpha, strength)
    -- Linger control: the pulse fades to nothing over Flash Duration
    decayRate = pulseAlpha / (CommanderImpactDB.FlashDuration or 1)
    pulse:SetAlpha(pulseAlpha)
    driver:SetScript("OnUpdate", OnDecay)
end

-- Floating confirmation text
local killText = UIParent:CreateFontString(nil, "OVERLAY")
killText:SetFontObject(GameFontNormalHuge)
killText:SetPoint("TOP", UIParent, "TOP", 0, -180)
killText:SetTextColor(1, 0.82, 0.15)
killText:Hide()

local textGeneration = 0

local function ShowKillText(text)
    textGeneration = textGeneration + 1
    local myGeneration = textGeneration
    killText:SetText(text)
    killText:Show()
    C_Timer.After(TEXT_HOLD, function()
        if textGeneration == myGeneration then
            killText:Hide()
        end
    end)
end

local function IsOn()
    return CommanderImpactDB and CommanderImpactDB.EnableImpact
end

local function OnKill(destName)
    if CommanderImpactDB.KillFlash then
        Pulse(1, 0.82, 0.15, CommanderImpactDB.FlashIntensity or 0.4)
    end
    if CommanderImpactDB.KillText then
        ShowKillText(destName and string.format("TARGET ELIMINATED: %s", destName) or "TARGET ELIMINATED")
    end
    if CommanderImpactDB.KillSound then
        PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE, "Master")
    end
end

local function OnCrit(amount)
    if not CommanderImpactDB.CritFlash then return end
    local threshold = CommanderImpactDB.CritThreshold or 400
    if amount < threshold then return end
    -- 70% of Flash Intensity at the threshold, ramping to the full
    -- configured intensity at 3x threshold — never brighter than the
    -- slider promises
    local intensity = CommanderImpactDB.FlashIntensity or 0.4
    local ramp = math.min((amount - threshold) / (threshold * 2), 1)
    Pulse(1, 0.35, 0.1, intensity * (0.7 + 0.3 * ramp))
end

function CommanderImpact_Test()
    if not IsOn() then
        print("Commander Impact: module is disabled (enable it in settings or /cimpact)")
        return
    end
    OnKill("Test Dummy")
end

-- Hot path: this fires for EVERY combat log event in range. No table
-- allocation — capture the needed positions directly and bail on
-- non-player sources first. Player GUID is stable per session.
local playerGUID

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        playerGUID = UnitGUID("player")
        return
    end
    if not IsOn() then return end
    local _, subevent, _, sourceGUID, _, _, _, _, destName, _, _,
        a12, _, _, a15, _, _, a18, _, _, a21 = CombatLogGetCurrentEventInfo()
    if sourceGUID ~= (playerGUID or UnitGUID("player")) then return end
    if subevent == "PARTY_KILL" then
        OnKill(destName)
        return
    end
    local amount, critical
    if subevent == "SWING_DAMAGE" then
        amount, critical = a12, a18
    elseif subevent == "SPELL_DAMAGE" or subevent == "RANGE_DAMAGE"
        or subevent == "SPELL_PERIODIC_DAMAGE" then
        amount, critical = a15, a21
    end
    if critical and amount then
        OnCrit(amount)
    end
end)
