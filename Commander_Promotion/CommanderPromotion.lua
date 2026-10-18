-- Commander Promotion: the level-up ceremony. PLAYER_LEVEL_UP delivers the
-- new level plus health/power/stat deltas in its payload; the ceremony is
-- a strong gold vignette burst (Impact's WorldFrame technique), a
-- PROMOTION banner, and the gains lined up underneath.
--
-- 2.2.0 (Commander Orders 3.1, its SPEC 5 and S9): new ranks wait at your
-- class trainer, so the ceremony says where the nearest one is (a line under
-- the gains, named by Orders' locator: { townsfolk = "Class Trainer" }, your
-- class, your faction, your landmass) and, with Trainer Offer on, marks it:
-- a quiet waypoint (source "Promotion", key "trainer") that is temporary,
-- never asks for the arrow and says nothing, the way Commander Adjutant
-- offers a repairer. It is never placed in combat (parked until
-- PLAYER_REGEN_ENABLED), it moves on the next level-up rather than piling
-- up, and it is taken down when you open a class trainer. /cpromo trainer is
-- the asked-for version: Orders' arrow there, and Orders says so. Nothing at
-- the level cap, where there are no new ranks to buy.

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

-- Where the new ranks are (Commander Orders; empty without it)
local trainerline = banner:CreateFontString(nil, "OVERLAY")
trainerline:SetFontObject(GameFontHighlightSmall)
trainerline:SetPoint("TOP", statline, "BOTTOM", 0, -6)
trainerline:SetTextColor(0.6, 0.8, 1)

local MAX_LEVEL = 70                  -- the TBC cap: no new ranks past it
local TRAINER = { townsfolk = "Class Trainer" }

-- Orders 3.1's API (GoTo is the one way in), or nil
local function Orders()
    local O = CommanderOrders
    if type(O) == "table" and type(O.GoTo) == "function" then return O end
    return nil
end

-- "Brother Wilhelm (Elwynn Forest 41.1, 65.8)": the trainer the arrow would
-- take (PlaceFor), named from the locator's own list; nil when Orders cannot
-- name one (absent, off, no Questie, none on your landmass)
local function NearestTrainer()
    local O = Orders()
    if not (O and type(O.PlaceFor) == "function" and type(O.Locate) == "function") then return nil end
    local spot = O.PlaceFor(TRAINER)
    if type(spot) ~= "table" or type(spot.map) ~= "number" then return nil end
    local name
    local places = O.Locate(TRAINER)
    for _, p in ipairs(type(places) == "table" and places or {}) do
        if p.map == spot.map and math.abs((p.x or -1) - spot.x) < 1e-6 and math.abs((p.y or -1) - spot.y) < 1e-6 then
            name = p.title
            break
        end
    end
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(spot.map)
    local coords = type(O.FormatCoords) == "function" and O.FormatCoords(spot.x, spot.y)
        or string.format("%.1f, %.1f", spot.x * 100, spot.y * 100)
    return (name or spot.title or "Class trainer") .. " (" .. ((info and info.name) and (info.name .. " ") or "") .. coords .. ")"
end

-- The quiet offer (Trainer Offer): parked out of combat, never the arrow
local offerPending = false
local function OfferTrainer()
    offerPending = false
    if not (CommanderPromotionDB and CommanderPromotionDB.EnablePromotion and CommanderPromotionDB.TrainerOffer) then
        return nil
    end
    if InCombatLockdown and InCombatLockdown() then
        offerPending = true
        return nil
    end
    local O = Orders()
    if not O then return nil end
    return O.GoTo(TRAINER, {
        source = "Promotion", key = "trainer", icon = "TRAINER",
        temporary = true, persistent = false, setArrow = false, silent = true,
    })
end

-- At a class trainer the offer has done its job
local function WithdrawTrainer()
    offerPending = false
    local O = CommanderOrders
    if type(O) == "table" and type(O.RemoveBy) == "function" then pcall(O.RemoveBy, "Promotion", "trainer") end
end

-- /cpromo trainer: asked for, so the arrow goes there and Orders says so
function CommanderPromotion_GoToTrainer()
    local O = Orders()
    if not O then
        print("Commander Promotion: Go to Class Trainer needs Commander Orders")
        return nil
    end
    return O.GoTo(TRAINER, { source = "Promotion", key = "trainer", icon = "TRAINER" })
end

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

    -- Where the new ranks are (Commander Orders), below the cap only
    local trainer = nil
    if level and level < MAX_LEVEL and CommanderPromotionDB.TrainerOffer ~= false then
        local ok, found = pcall(NearestTrainer)
        if ok then trainer = found end
    end
    if trainer then
        trainerline:SetText("New ranks at your class trainer: " .. trainer)
        trainerline:Show()
    else
        trainerline:SetText("")
        trainerline:Hide()
    end

    -- Commander Tracer draws centre-screen text in its own lanes when it
    -- runs; the bursts and the fanfare below still play
    local sub = trainer and ("New ranks at your class trainer: " .. trainer)
        or (statline:IsShown() and statline:GetText()) or nil
    local taken = CommanderTracer_Notice and CommanderTracer_Notice({
        text = string.format("PROMOTION: level %s", tostring(level)), sub = sub, r = 1, g = 0.82, b = 0.15,
    })
    if not taken then banner:Show() end
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
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("TRAINER_SHOW")
-- Retail-era engine payload: (level, healthDelta, powerDelta, newTalents,
-- newPvpTalentSlots, strDelta, agiDelta, stamDelta, intDelta): position 5
-- is PvP talent slots (always 0 here), and there is no spirit delta. The
-- vanilla-era signature would shift every stat label by one.
events:SetScript("OnEvent", function(self, event, level, hp, power, talents, pvpTalents, str, agi, stam, int)
    if event == "PLAYER_REGEN_ENABLED" then
        if offerPending then OfferTrainer() end
        return
    elseif event == "TRAINER_SHOW" then
        -- a class trainer, not a profession one: the offer is done
        if not (IsTradeskillTrainer and IsTradeskillTrainer()) then WithdrawTrainer() end
        return
    end
    if not IsOn() then return end
    ShowCeremony(level, hp, power, str, agi, stam, int, nil)
    if type(level) == "number" and level < MAX_LEVEL then
        local ok, err = pcall(OfferTrainer)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end
end)
