-- Commander Promotion: the level-up ceremony. PLAYER_LEVEL_UP delivers the
-- new level plus health/power/stat deltas in its payload; the ceremony is
-- a strong gold vignette burst (Impact's WorldFrame technique), a
-- PROMOTION banner, and the gains lined up underneath.

local BANNER_HOLD = 8

-- Flat white texture, not the LowHealth vignette: that art is itself red,
-- so vertex-tinting it gold still renders red. A white fill tinted gold
-- with ADD blending is an actual gold burst.
local pulse = WorldFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
pulse:SetTexture("Interface\\Buttons\\WHITE8X8")
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
    -- Flat fill needs less alpha than a vignette to read as a burst
    pulseAlpha = 0.35
    pulse:SetAlpha(pulseAlpha)
    pulseDriver:SetScript("OnUpdate", OnDecay)
end

local banner = CreateFrame("Frame", "CommanderPromotionBanner", UIParent)
banner:SetSize(600, 220)
banner:SetPoint("TOP", UIParent, "TOP", 0, -110)
banner:SetFrameStrata("HIGH")
banner:Hide()

-- Twin star rays spinning in opposite directions behind the numeral —
-- the client's cooldown-flash star art, tinted gold, additive
local rayA = banner:CreateTexture(nil, "BACKGROUND")
rayA:SetTexture("Interface\\Cooldown\\star4")
rayA:SetBlendMode("ADD")
rayA:SetVertexColor(1, 0.82, 0.15, 0.8)
rayA:SetSize(320, 320)
rayA:SetPoint("CENTER", banner, "TOP", 0, -110)

local rayB = banner:CreateTexture(nil, "BACKGROUND")
rayB:SetTexture("Interface\\Cooldown\\star4")
rayB:SetBlendMode("ADD")
rayB:SetVertexColor(1, 0.6, 0.1, 0.6)
rayB:SetSize(240, 240)
rayB:SetPoint("CENTER", banner, "TOP", 0, -110)

local rayRotation = 0
banner:SetScript("OnUpdate", function(self, elapsed)
    rayRotation = rayRotation + elapsed * 0.7
    rayA:SetRotation(rayRotation)
    rayB:SetRotation(-rayRotation * 1.4)
end)

local headline = banner:CreateFontString(nil, "OVERLAY")
headline:SetFontObject(GameFontNormalHuge)
headline:SetPoint("TOP", banner, "TOP", 0, 0)
headline:SetTextColor(1, 0.82, 0.15)

-- The oversized golden numeral is the centerpiece
local numeral = banner:CreateFontString(nil, "OVERLAY")
numeral:SetFontObject(GameFontNormalHuge)
do
    local fontPath = numeral:GetFont()
    if fontPath then
        numeral:SetFont(fontPath, 64, "THICKOUTLINE")
    end
end
numeral:SetPoint("TOP", headline, "BOTTOM", 0, -10)
numeral:SetTextColor(1, 0.85, 0.2)

local subline = banner:CreateFontString(nil, "OVERLAY")
subline:SetFontObject(GameFontNormal)
subline:SetPoint("TOP", numeral, "BOTTOM", 0, -8)
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
    numeral:SetText(tostring(level))
    subline:SetText("The war council salutes your new rank")

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
    -- Ceremony timeline: three staggered golden bursts and a layered
    -- fanfare — promotions are rare, they get the full parade
    if CommanderPromotionDB.PromotionFlash then
        GoldBurst()
        C_Timer.After(0.45, function()
            if generation == myGeneration then GoldBurst() end
        end)
        C_Timer.After(0.95, function()
            if generation == myGeneration then GoldBurst() end
        end)
    end
    if CommanderPromotionDB.PromotionSound then
        PlaySound(SOUNDKIT.RAID_WARNING, "Master")
        C_Timer.After(0.4, function()
            if generation == myGeneration then
                PlaySound(SOUNDKIT.READY_CHECK, "Master")
            end
        end)
        C_Timer.After(0.9, function()
            if generation == myGeneration then
                PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE, "Master")
            end
        end)
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
    -- Never announce a level beyond the TBC cap in the preview
    ShowCeremony(math.min((UnitLevel("player") or 59) + 1, 70), 42, 65, 1, 1, 2, 1, 1)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LEVEL_UP")
-- Retail-era engine payload: (level, healthDelta, powerDelta, newTalents,
-- newPvpTalentSlots, strDelta, agiDelta, stamDelta, intDelta) — position 5
-- is PvP talent slots (always 0 here), and there is no spirit delta. The
-- vanilla-era signature would shift every stat label by one.
events:SetScript("OnEvent", function(self, event, level, hp, power, talents, pvpTalents, str, agi, stam, int)
    if not IsOn() then return end
    ShowCeremony(level, hp, power, str, agi, stam, int, nil)
end)
