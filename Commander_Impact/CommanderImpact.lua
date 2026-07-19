-- Commander Impact: payoff feedback for the player's own blows, using the
-- same full-screen language as Commander Casting's glow (a WorldFrame
-- vignette texture with ADD blending) — but as a decaying pulse instead of
-- a rising buildup. Kills pulse gold with a TARGET ELIMINATED float; crits
-- past the threshold pulse red-orange, scaled to the damage.

local DECAY_PER_SECOND = 1.1
local TEXT_HOLD = 1.4

local pulse = WorldFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
pulse:SetTexture("Interface\\FullScreenTextures\\LowHealth")
pulse:SetAllPoints(WorldFrame)
pulse:SetBlendMode("ADD")
pulse:SetAlpha(0)

local driver = CreateFrame("Frame")
local pulseAlpha = 0

local function OnDecay(self, elapsed)
    pulseAlpha = pulseAlpha - elapsed * DECAY_PER_SECOND
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
    -- Scale from base intensity at the threshold up to +50% at 3x threshold
    local intensity = CommanderImpactDB.FlashIntensity or 0.4
    local scale = math.min(amount / (threshold * 3), 1)
    Pulse(1, 0.35, 0.1, intensity * (0.7 + 0.5 * scale))
end

local function ExtractDamage(subevent, ...)
    if subevent == "SWING_DAMAGE" then
        local amount, _, _, _, _, _, critical = select(12, ...)
        return amount, critical
    elseif subevent == "SPELL_DAMAGE" or subevent == "RANGE_DAMAGE"
        or subevent == "SPELL_PERIODIC_DAMAGE" then
        local amount, _, _, _, _, _, critical = select(15, ...)
        return amount, critical
    end
end

function CommanderImpact_Test()
    if not IsOn() then
        print("Commander Impact: module is disabled (enable it in settings or /cimpact)")
        return
    end
    OnKill("Test Dummy")
end

local events = CreateFrame("Frame")
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
events:SetScript("OnEvent", function()
    if not IsOn() then return end
    local payload = { CombatLogGetCurrentEventInfo() }
    local subevent, sourceGUID, destName = payload[2], payload[4], payload[9]
    if sourceGUID ~= UnitGUID("player") then return end
    if subevent == "PARTY_KILL" then
        OnKill(destName)
        return
    end
    local amount, critical = ExtractDamage(subevent, unpack(payload))
    if critical and amount then
        OnCrit(amount)
    end
end)
