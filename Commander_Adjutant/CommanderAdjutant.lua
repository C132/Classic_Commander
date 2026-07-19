-- Commander Adjutant: RTS-style battle announcer. Shows a top-center banner
-- (and optionally a stock alert sound) for commander-relevant events. Every
-- alert is throttled so the adjutant informs rather than nags: attacks only
-- after a stretch of peace, critical damage once per fight, repair/storage
-- once per threshold crossing.

local BANNER_HOLD = 3.0
local BANNER_FADE_STEP = 0.06
local UNDER_ATTACK_COOLDOWN = 30

-- All keys verified against this client's SOUNDKIT table
local ALERT_SOUNDS = {
    UNDER_ATTACK = "RAID_WARNING",
    LOW_HEALTH = "RAID_BOSS_EMOTE_WARNING",
    REPAIR = "IG_CHARACTER_INFO_TAB",
    BAGS_FULL = "IG_CHARACTER_INFO_TAB",
    LEVEL_UP = "IG_QUEST_LIST_COMPLETE",
    REINFORCEMENTS = "READY_CHECK",
}

-- ---------------------------------------------------------------------------
-- Banner
-- ---------------------------------------------------------------------------
local banner = CreateFrame("Frame", "CommanderAdjutantBanner", UIParent)
banner:SetSize(600, 40)
banner:SetPoint("TOP", UIParent, "TOP", 0, -140)
banner:SetFrameStrata("HIGH")
banner:Hide()

local bannerText = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
bannerText:SetPoint("CENTER")
bannerText:SetTextColor(1, 0.85, 0.2)

local fadeTicker
local bannerGeneration = 0

local function StopFade()
    if fadeTicker then
        fadeTicker:Cancel()
        fadeTicker = nil
    end
end

local function ShowBanner(text, r, g, b)
    StopFade()
    -- Generation token invalidates hold callbacks from earlier banners:
    -- without it, banner A's uncancellable After() would start fading
    -- banner B partway through B's own hold
    bannerGeneration = bannerGeneration + 1
    local generation = bannerGeneration
    bannerText:SetText(text)
    bannerText:SetTextColor(r or 1, g or 0.85, b or 0.2)
    banner:SetAlpha(1)
    banner:Show()
    C_Timer.After(BANNER_HOLD, function()
        if generation ~= bannerGeneration then return end
        StopFade()
        fadeTicker = C_Timer.NewTicker(0.05, function()
            local alpha = banner:GetAlpha() - BANNER_FADE_STEP
            if alpha <= 0 then
                banner:Hide()
                banner:SetAlpha(1)
                StopFade()
            else
                banner:SetAlpha(alpha)
            end
        end)
    end)
end

local function Announce(alertKey, text, r, g, b)
    if not CommanderAdjutantDB.EnableAdjutant then return end
    ShowBanner(text, r, g, b)
    if CommanderAdjutantDB.PlaySounds then
        local soundKit = SOUNDKIT[ALERT_SOUNDS[alertKey] or ""]
        if soundKit then
            PlaySound(soundKit, "Master")
        end
    end
end

-- Shared with the settings panel's /cadj test subcommand
function CommanderAdjutant_TestAlert()
    Announce("UNDER_ATTACK", "Our forces are under attack!", 1, 0.3, 0.2)
end

-- ---------------------------------------------------------------------------
-- Alert state and triggers
-- ---------------------------------------------------------------------------
local lastCombatEnd = 0
local lowHealthAnnounced = false
local repairAnnounced = false
local bagsFullAnnounced = false
local lastGroupSize = 0
local lastReinforcement = 0
local loginTime = 0
local REINFORCEMENT_COOLDOWN = 30
local LOGIN_GRACE = 10

local function GroupSize()
    return (GetNumGroupMembers and GetNumGroupMembers()) or 0
end

local function CheckLowHealth()
    if not CommanderAdjutantDB.AlertLowHealth then return end
    local health, maxHealth = UnitHealth("player"), UnitHealthMax("player")
    if maxHealth <= 0 then return end
    local ratio = health / maxHealth
    -- Hysteresis: re-arm only after recovering comfortably above the
    -- threshold, so a fight that ENDS below 25% can't re-announce on the
    -- first out-of-combat regen tick
    if lowHealthAnnounced then
        if ratio >= 0.35 then
            lowHealthAnnounced = false
        end
        return
    end
    if ratio < 0.25 and health > 0 then
        lowHealthAnnounced = true
        Announce("LOW_HEALTH", "We're taking critical damage!", 1, 0.2, 0.2)
    end
end

local function CheckDurability()
    if not CommanderAdjutantDB.AlertRepair then return end
    local lowest = 1
    for slot = 1, 18 do
        local current, maximum = GetInventoryItemDurability(slot)
        if current and maximum and maximum > 0 then
            local ratio = current / maximum
            if ratio < lowest then lowest = ratio end
        end
    end
    if lowest < 0.2 then
        if not repairAnnounced then
            repairAnnounced = true
            Announce("REPAIR", "Units require repair", 1, 0.85, 0.2)
        end
    else
        repairAnnounced = false
    end
end

local function CheckBags()
    if not CommanderAdjutantDB.AlertBagsFull then return end
    local free = 0
    for bagID = 0, 4 do
        if (C_Container.GetContainerNumSlots(bagID) or 0) > 0 then
            free = free + (C_Container.GetContainerNumFreeSlots(bagID) or 0)
        end
    end
    if free == 0 then
        if not bagsFullAnnounced then
            bagsFullAnnounced = true
            Announce("BAGS_FULL", "Storage at full capacity", 1, 0.85, 0.2)
        end
    else
        bagsFullAnnounced = false
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterUnitEvent("UNIT_HEALTH", "player")
events:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
local loaded = false

events:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        lastGroupSize = GroupSize()
        lastCombatEnd = 0
        loginTime = GetTime()
        loaded = true
        return
    end
    if not loaded or not CommanderAdjutantDB.EnableAdjutant then return end

    if event == "PLAYER_REGEN_DISABLED" then
        -- A fresh engagement, not chained pulls: announce only after peace
        if CommanderAdjutantDB.AlertUnderAttack and (GetTime() - lastCombatEnd) > UNDER_ATTACK_COOLDOWN then
            Announce("UNDER_ATTACK", "Our forces are under attack!", 1, 0.3, 0.2)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        lastCombatEnd = GetTime()
        -- lowHealthAnnounced deliberately NOT cleared here; CheckLowHealth's
        -- hysteresis re-arms it once health recovers above 35%
    elseif event == "UNIT_HEALTH" then
        CheckLowHealth()
    elseif event == "UPDATE_INVENTORY_DURABILITY" then
        CheckDurability()
    elseif event == "BAG_UPDATE_DELAYED" then
        CheckBags()
    elseif event == "PLAYER_LEVEL_UP" then
        if CommanderAdjutantDB.AlertLevelUp then
            Announce("LEVEL_UP", "Upgrade complete", 0.3, 1, 0.4)
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        local size = GroupSize()
        -- Throttled (one announce per 30s window) so a filling battleground
        -- or raid announces once, not once per joiner — and never during
        -- the first seconds after login, when the roster is still settling
        if CommanderAdjutantDB.AlertReinforcements and size > lastGroupSize and size > 1
            and (GetTime() - loginTime) > LOGIN_GRACE
            and (GetTime() - lastReinforcement) > REINFORCEMENT_COOLDOWN then
            lastReinforcement = GetTime()
            Announce("REINFORCEMENTS", "Reinforcements have arrived", 0.4, 0.8, 1)
        end
        lastGroupSize = size
    end
end)
