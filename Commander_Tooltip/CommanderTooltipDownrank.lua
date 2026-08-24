-- Commander Tooltip: TBC downrank economics for the spellbook.
--
-- Hovering a healing rank in the spellbook answers the only two questions that
-- matter when you build a downrank bar: how much of your +healing this rank
-- actually keeps after the TBC penalty, and what that surviving amount is worth
-- per mana and per second. Everything shown is the GEAR's contribution only --
-- the spell's own base heal is already on the tooltip above.

local GCD = 1.5                 -- instant casts still cost a global
local CAST_CAP = 3.5            -- TBC coefficient normalisation window
local MANA = 0                  -- Enum.PowerType.Mana

-- Rank -> the level the rank is learned at, plus the spell's base +healing
-- coefficient. This table is the module's only hand-maintained data and its
-- only point of failure, so the tooltip prints the level it used ("R4, L58")
-- next to the penalty: if a number here is ever wrong, the trainer disagrees
-- with the tooltip in plain sight.
--
-- Coefficients are the standard TBC values: direct heals are castTime / 3.5,
-- HoTs are duration / 15.
local SPELLS = {
    ["Heal"]              = { coef = 3.0 / CAST_CAP, levels = { 16, 22, 28, 34 } },
    ["Greater Heal"]      = { coef = 3.0 / CAST_CAP, levels = { 40, 46, 52, 58, 60, 66, 73 } },
    ["Flash Heal"]        = { coef = 1.5 / CAST_CAP, levels = { 20, 26, 32, 38, 44, 50, 56, 62, 68 } },
    ["Renew"]             = { coef = 15.0 / 15.0,    levels = { 8, 14, 20, 26, 32, 38, 44, 50, 56, 60, 65, 70 } },
    ["Circle of Healing"] = { coef = 1.5 / CAST_CAP, levels = { 40, 50, 60, 70 } },
}

local function RankNum(text)
    return text and tonumber(tostring(text):match("%d+")) or nil
end

-- The rank is the spell's SUBTEXT on this client -- it is not a return of
-- GetSpellInfo or GetSpellBookItemName, and it loads asynchronously, so it can
-- read empty on a cold first hover. The tooltip Blizzard just built in front of
-- us already has the rank line rendered, so that is the fallback: between the
-- two, a hover practically never comes up rankless.
local function RankOf(spellID, tooltip)
    if spellID and C_Spell and C_Spell.GetSpellSubtext then
        local rank = RankNum(C_Spell.GetSpellSubtext(spellID))
        if rank then return rank end
    end

    local name = tooltip:GetName()
    if not name then return nil end
    for i = 1, 4 do
        for _, side in ipairs({ "TextLeft", "TextRight" }) do
            local line = _G[name .. side .. i]
            local text = line and line:GetText()
            if text and text:find("Rank") then
                local rank = RankNum(text)
                if rank then return rank end
            end
        end
    end
    return nil
end

local function ManaCostOf(spellID)
    local costs = C_Spell and C_Spell.GetSpellPowerCost and C_Spell.GetSpellPowerCost(spellID)
    if type(costs) ~= "table" then return 0 end
    for _, cost in ipairs(costs) do
        if cost.type == MANA then return cost.cost or 0 end
    end
    return 0
end

-- Cast time arrives in milliseconds; an instant spell reports 0 and is really
-- limited by the global cooldown, which is what its throughput should be
-- measured against.
local function CastSecondsOf(spellID)
    local castMS = select(4, GetSpellInfo(spellID))
    if not castMS or castMS <= 0 then return GCD end
    return castMS / 1000
end

local function AddMetrics(tooltip, slotID, bookType)
    local name, _, spellID = GetSpellBookItemName(slotID, bookType)
    if not name or not spellID then return end

    local spell = SPELLS[name]
    if not spell then return end

    local rank = RankOf(spellID, tooltip)
    local learnedAt = rank and spell.levels[rank]
    if not learnedAt then return end

    -- TBC's penalty: a rank keeps full value for ten levels past the level it
    -- was learned at, then decays as (learnedAt + 11) / playerLevel. The cap is
    -- what makes the "more than 10 levels below" test unnecessary -- inside the
    -- grace window the quotient is already above 1.
    local playerLevel = UnitLevel("player") or 1
    local penalty = 1.0
    if playerLevel > 0 then
        penalty = math.min(1.0, (learnedAt + 11) / playerLevel)
    end

    local effective = spell.coef * penalty
    local bonus = (GetSpellBonusHealing() or 0) * effective

    local mana = ManaCostOf(spellID)
    local castSeconds = CastSecondsOf(spellID)

    tooltip:AddLine(" ")
    tooltip:AddLine("|cffffd100\226\128\148 TBC Downrank & Efficiency Metrics \226\128\148|r")

    tooltip:AddDoubleLine("Base Coefficient",
        string.format("%.1f%%", spell.coef * 100),
        0.8, 0.8, 0.8, 1, 1, 1)

    local penaltyLabel = string.format("TBC Downrank Penalty (R%d, L%d)", rank, learnedAt)
    if penalty >= 1.0 then
        tooltip:AddDoubleLine(penaltyLabel, "0% (Full Effectiveness)",
            0.8, 0.8, 0.8, 0.1, 1, 0.1)
    else
        tooltip:AddDoubleLine(penaltyLabel, string.format("-%.1f%%", (1 - penalty) * 100),
            0.8, 0.8, 0.8, 1, 0.2, 0.2)
    end

    tooltip:AddDoubleLine("Effective Coefficient", string.format("%.1f%%", effective * 100),
        0.8, 0.8, 0.8, 1, 1, 0)

    tooltip:AddDoubleLine("Bonus From Gear", string.format("+%d", bonus),
        0.8, 0.8, 0.8, 0.4, 0.8, 1)

    tooltip:AddDoubleLine("Gear HPM",
        mana > 0 and string.format("%.2f", bonus / mana) or "n/a",
        0.8, 0.8, 0.8, 0.6, 1, 0.6)

    tooltip:AddDoubleLine("Gear HPS", string.format("%d", bonus / castSeconds),
        0.8, 0.8, 0.8, 0.7, 0.5, 1)

    -- Lines added after the tooltip was sized need a re-show to be measured.
    tooltip:Show()
end

local hooked = false
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function()
    if hooked then return end
    hooked = true

    hooksecurefunc(GameTooltip, "SetSpellBookItem", function(tooltip, slotID, bookType)
        if bookType ~= BOOKTYPE_SPELL then return end
        -- Never let a data gap break someone's spellbook tooltip.
        pcall(AddMetrics, tooltip, slotID, bookType)
    end)
end)
