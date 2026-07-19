-- Commander Honor: honorable-kill feedback and a session war record.
-- CHAT_MSG_COMBAT_HONOR_GAIN carries lines like
--   "Playername dies, honorable kill Rank: Grunt (Estimated Honor Points: 199)"
-- and (for dishonorable kills) other formats we deliberately ignore. The
-- registration is guarded like MINIMAP_PING's in case a patch moves it.

local TEXT_HOLD = 1.6

local pulse = WorldFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
pulse:SetTexture("Interface\\FullScreenTextures\\LowHealth")
pulse:SetAllPoints(WorldFrame)
pulse:SetBlendMode("ADD")
pulse:SetAlpha(0)

local pulseDriver = CreateFrame("Frame")
local pulseAlpha = 0
local function OnDecay(self, elapsed)
    pulseAlpha = pulseAlpha - elapsed * 1.0
    if pulseAlpha <= 0 then
        pulseAlpha = 0
        pulse:SetAlpha(0)
        pulseDriver:SetScript("OnUpdate", nil)
        return
    end
    pulse:SetAlpha(pulseAlpha)
end

local function CrimsonFlash()
    pulse:SetVertexColor(1, 0.15, 0.15)
    pulseAlpha = 0.45
    pulse:SetAlpha(pulseAlpha)
    pulseDriver:SetScript("OnUpdate", OnDecay)
end

local killText = UIParent:CreateFontString(nil, "OVERLAY")
killText:SetFontObject(GameFontNormalHuge)
killText:SetPoint("TOP", UIParent, "TOP", 0, -220)
killText:SetTextColor(1, 0.25, 0.2)
killText:Hide()

local generation = 0
local function ShowKillText(text)
    generation = generation + 1
    local myGeneration = generation
    killText:SetText(text)
    killText:Show()
    C_Timer.After(TEXT_HOLD, function()
        if generation == myGeneration then
            killText:Hide()
        end
    end)
end

local sessionKills = 0
local sessionHonor = 0

local function IsOn()
    return CommanderHonorDB and CommanderHonorDB.EnableHonor
end

local function Celebrate(victim, honor)
    sessionKills = sessionKills + 1
    sessionHonor = sessionHonor + (honor or 0)
    if CommanderHonorDB.HonorFlash then
        CrimsonFlash()
    end
    if CommanderHonorDB.HonorText then
        ShowKillText(victim and string.format("HONORABLE KILL: %s", victim) or "HONORABLE KILL")
    end
    if CommanderHonorDB.HonorSound then
        PlaySound(SOUNDKIT.RAID_WARNING, "Master")
    end
end

local function OnHonorMessage(message)
    if type(message) ~= "string" then return end
    -- Only honorable kills carry a victim name before "dies"
    local victim = message:match("^(%S+) dies, honorable kill")
    if not victim then return end
    local honor = tonumber(message:match("Estimated Honor Points: (%d+)"))
    Celebrate(victim, honor)
end

function CommanderHonor_Report()
    if sessionKills == 0 then
        print("Commander Honor: no honorable kills this session yet — the war record is clean")
        return
    end
    print(string.format("Commander Honor: %d honorable kill%s this session, ~%d honor",
        sessionKills, sessionKills == 1 and "" or "s", sessionHonor))
end

function CommanderHonor_Test()
    if not IsOn() then
        print("Commander Honor: module is disabled (enable it in settings or /chonor)")
        return
    end
    Celebrate("Testdummy", 0)
    sessionKills = sessionKills - 1
end

local events = CreateFrame("Frame")
if not C_EventUtils or (C_EventUtils.IsEventValid and C_EventUtils.IsEventValid("CHAT_MSG_COMBAT_HONOR_GAIN")) then
    pcall(events.RegisterEvent, events, "CHAT_MSG_COMBAT_HONOR_GAIN")
end
events:SetScript("OnEvent", function(self, event, message)
    if IsOn() then
        OnHonorMessage(message)
    end
end)
