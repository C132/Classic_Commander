-- Commander Promotion: the level-up ceremony. PLAYER_LEVEL_UP delivers the
-- new level plus health/power/stat deltas in its payload; the ceremony is
-- a strong gold vignette burst (Impact's WorldFrame technique), a
-- PROMOTION banner, and the gains lined up underneath.

local BANNER_HOLD = 5

local pulse = WorldFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
pulse:SetTexture("Interface\\FullScreenTextures\\LowHealth")
pulse:SetAllPoints(WorldFrame)
pulse:SetBlendMode("ADD")
pulse:SetAlpha(0)

local pulseDriver = CreateFrame("Frame")
local pulseAlpha = 0
local function OnDecay(self, elapsed)
    pulseAlpha = pulseAlpha - elapsed * 0.5
    if pulseAlpha <= 0 then
        pulseAlpha = 0
        pulse:SetAlpha(0)
        pulseDriver:SetScript("OnUpdate", nil)
        return
    end
    pulse:SetAlpha(pulseAlpha)
end

local function GoldBurst()
    pulse:SetVertexColor(1, 0.82, 0.15)
    pulseAlpha = 0.55
    pulse:SetAlpha(pulseAlpha)
    pulseDriver:SetScript("OnUpdate", OnDecay)
end

local banner = CreateFrame("Frame", "CommanderPromotionBanner", UIParent)
banner:SetSize(600, 90)
banner:SetPoint("TOP", UIParent, "TOP", 0, -140)
banner:SetFrameStrata("HIGH")
banner:Hide()

local headline = banner:CreateFontString(nil, "OVERLAY")
headline:SetFontObject(GameFontNormalHuge)
headline:SetPoint("TOP", banner, "TOP", 0, 0)
headline:SetTextColor(1, 0.82, 0.15)

local subline = banner:CreateFontString(nil, "OVERLAY")
subline:SetFontObject(GameFontNormal)
subline:SetPoint("TOP", headline, "BOTTOM", 0, -6)
subline:SetTextColor(0.95, 0.95, 0.95)

local statline = banner:CreateFontString(nil, "OVERLAY")
statline:SetFontObject(GameFontHighlightSmall)
statline:SetPoint("TOP", subline, "BOTTOM", 0, -6)
statline:SetTextColor(0.3, 1, 0.4)

local generation = 0

local function ShowCeremony(level, hp, power, str, agi, stam, int, spi)
    generation = generation + 1
    local myGeneration = generation

    headline:SetText("PROMOTION")
    subline:SetText(string.format("Level %d attained", level))

    if CommanderPromotionDB.StatReadout then
        local parts = {}
        local stats = {
            { str, "Str" }, { agi, "Agi" }, { stam, "Stam" },
            { int, "Int" }, { spi, "Spi" },
        }
        for _, stat in ipairs(stats) do
            if stat[1] and stat[1] > 0 then
                parts[#parts + 1] = string.format("+%d %s", stat[1], stat[2])
            end
        end
        if hp and hp > 0 then
            parts[#parts + 1] = string.format("+%d Health", hp)
        end
        if power and power > 0 then
            parts[#parts + 1] = string.format("+%d Power", power)
        end
        statline:SetText(table.concat(parts, "   "))
        statline:Show()
    else
        statline:Hide()
    end

    banner:Show()
    if CommanderPromotionDB.PromotionFlash then
        GoldBurst()
    end
    if CommanderPromotionDB.PromotionSound then
        PlaySound(SOUNDKIT.READY_CHECK, "Master")
    end
    C_Timer.After(BANNER_HOLD, function()
        if generation == myGeneration then
            banner:Hide()
        end
    end)
end

local function IsOn()
    return CommanderPromotionDB and CommanderPromotionDB.EnablePromotion
end

function CommanderPromotion_Test()
    if not IsOn() then
        print("Commander Promotion: module is disabled (enable it in settings or /cpromo)")
        return
    end
    ShowCeremony((UnitLevel("player") or 59) + 1, 42, 65, 1, 1, 2, 1, 1)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:SetScript("OnEvent", function(self, event, level, hp, power, talents, str, agi, stam, int, spi)
    if not IsOn() then return end
    ShowCeremony(level, hp, power, str, agi, stam, int, spi)
end)
