local ActionPlanner = CreateFrame("Frame", "MyClassicAddonActionPlanner", UIParent, "BackdropTemplate")
ActionPlanner:SetSize(300, 400)  -- Increased size for more content
ActionPlanner:SetPoint("CENTER")
ActionPlanner:SetMovable(true)
ActionPlanner:EnableMouse(true)
ActionPlanner:RegisterForDrag("LeftButton")
ActionPlanner:SetScript("OnDragStart", ActionPlanner.StartMoving)
ActionPlanner:SetScript("OnDragStop", ActionPlanner.StopMovingOrSizing)

-- Set up the backdrop (border and background)
ActionPlanner:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
})
ActionPlanner:SetBackdropColor(0, 0, 0, 0.8)

ActionPlanner.title = ActionPlanner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
ActionPlanner.title:SetPoint("TOP", 0, -5)
ActionPlanner.title:SetText("Action Planner")

-- Create close button
ActionPlanner.closeButton = CreateFrame("Button", nil, ActionPlanner, "UIPanelCloseButton")
ActionPlanner.closeButton:SetPoint("TOPRIGHT", -5, -5)
ActionPlanner.closeButton:SetScript("OnClick", function() ActionPlanner:Hide() end)

ActionPlanner.scrollFrame = CreateFrame("ScrollFrame", nil, ActionPlanner, "UIPanelScrollFrameTemplate")
ActionPlanner.scrollFrame:SetPoint("TOPLEFT", 10, -30)
ActionPlanner.scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

ActionPlanner.content = CreateFrame("Frame", nil, ActionPlanner.scrollFrame)
ActionPlanner.content:SetSize(260, 1)  -- Width of 260, height will be set dynamically
ActionPlanner.scrollFrame:SetScrollChild(ActionPlanner.content)

ActionPlanner.contentText = ActionPlanner.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
ActionPlanner.contentText:SetPoint("TOPLEFT")
ActionPlanner.contentText:SetPoint("TOPRIGHT")
ActionPlanner.contentText:SetJustifyH("LEFT")
ActionPlanner.contentText:SetJustifyV("TOP")

local considerCastTime = false

local function GetOptimalSequence(targetHealth, playerMana)
    local sequence = {}
    local totalTime = 0
    local totalDamage = 0
    local totalMana = 0

    if not ActionBarOutput or type(ActionBarOutput.GetCachedOutputs) ~= "function" then
        print("Error: ActionBarOutput is not properly initialized")
        return sequence, 0, 0, 0
    end

    local cachedOutputs = ActionBarOutput:GetCachedOutputs()

    if not cachedOutputs or next(cachedOutputs) == nil then
        return sequence, 0, 0, 0
    end

    local spells = {}
    local gcd = 1.5  -- Global Cooldown in seconds

    for spellId, damage in pairs(cachedOutputs) do
        local spellName, _, icon, castTime, _, _, _ = GetSpellInfo(spellId)
        castTime = considerCastTime and (castTime / 1000 or 0) or gcd
        local start, duration = GetSpellCooldown(spellId)
        local cooldownRemaining = start + duration - GetTime()
        local manaCost = select(4, GetSpellInfo(spellId)) or 0

        -- Get the correct rank of the spell
        local spellRank = GetSpellSubtext(spellId)
        if spellRank then
            local rankNumber = tonumber(string.match(spellRank, "(%d+)"))
            if rankNumber then
                -- Get the correct mana cost for the specific rank
                manaCost = select(4, GetSpellInfo(spellName .. "(Rank " .. rankNumber .. ")")) or manaCost
            end
        end
        
        if damage > 0 then
            table.insert(spells, {
                id = spellId,
                name = spellName,
                icon = icon,
                damage = damage,
                castTime = math.max(castTime, gcd),
                cooldown = cooldownRemaining,
                manaCost = manaCost
            })
        end
    end

    table.sort(spells, function(a, b) 
        return a.damage / a.castTime > b.damage / b.castTime
    end)

    local remainingHealth = targetHealth
    local remainingMana = playerMana
    local maxIterations = 1000
    local iterations = 0

    while remainingHealth > 0 and iterations < maxIterations do
        iterations = iterations + 1
        local bestSpell = nil
        for _, spell in ipairs(spells) do
            if spell.cooldown <= 0 and spell.manaCost <= remainingMana then
                bestSpell = spell
                break
            end
        end

        if not bestSpell then
            -- If no spell is available, wait for the shortest cooldown or mana regeneration
            local shortestWait = math.huge
            for _, spell in ipairs(spells) do
                if spell.cooldown > 0 and spell.cooldown < shortestWait then
                    shortestWait = spell.cooldown
                end
            end
            if shortestWait < math.huge then
                totalTime = totalTime + shortestWait
                for _, spell in ipairs(spells) do
                    spell.cooldown = math.max(0, spell.cooldown - shortestWait)
                end
                -- Simulate mana regeneration (you may want to adjust this based on your game's mechanics)
                remainingMana = math.min(playerMana, remainingMana + (shortestWait * 5))  -- Assuming 5 mana per second
            else
                break  -- No spells available and no cooldowns
            end
        else
            local actualDamage = math.min(bestSpell.damage, remainingHealth)
            table.insert(sequence, {
                name = bestSpell.name,
                icon = bestSpell.icon,
                damage = actualDamage,
                castTime = bestSpell.castTime,
                overkill = math.max(0, bestSpell.damage - remainingHealth),
                manaCost = bestSpell.manaCost
            })
            totalTime = totalTime + bestSpell.castTime
            totalDamage = totalDamage + actualDamage
            totalMana = totalMana + bestSpell.manaCost
            remainingHealth = remainingHealth - actualDamage
            remainingMana = remainingMana - bestSpell.manaCost

            -- Update cooldowns
            for _, spell in ipairs(spells) do
                spell.cooldown = math.max(0, spell.cooldown - bestSpell.castTime)
            end

            -- Reset cooldown for the used spell
            for _, spell in ipairs(spells) do
                if spell.id == bestSpell.id then
                    spell.cooldown = GetSpellBaseCooldown(spell.id) / 1000
                    break
                end
            end
        end

        -- Check if we've run out of mana
        if remainingMana <= 0 then
            break
        end
    end

    if remainingHealth > 0 then
        print("Warning: Unable to fully deplete target health. Remaining health:", remainingHealth)
    end

    return sequence, totalTime, totalDamage, totalMana
end

local function UpdateActionPlanner()
    local targetHealth = UnitHealth("target")
    local playerMana = UnitPower("player", 0)  -- 0 is the power type for mana
    if targetHealth and targetHealth > 0 then
        local sequence, totalTime, totalDamage, totalMana = GetOptimalSequence(targetHealth, playerMana)
        local content = "Target Health: " .. targetHealth .. "\nPlayer Mana: " .. playerMana .. "\n\nOptimal Sequence:\n"
        if #sequence > 0 then
            content = content .. string.format("Sequence Length: %d spells\n\n", #sequence)
            local remainingMana = playerMana
            for i, spell in ipairs(sequence) do
                local iconTexture = "|T" .. spell.icon .. ":0|t "
                content = content .. i .. ". " .. iconTexture .. spell.name .. " (" .. math.floor(spell.damage) .. " damage"
                if considerCastTime then
                    content = content .. ", " .. string.format("%.2f", spell.castTime) .. "s"
                end
                content = content .. ", " .. spell.manaCost .. " mana)"
                if spell.overkill > 0 then
                    content = content .. " [Overkill: " .. math.floor(spell.overkill) .. "]"
                end
                remainingMana = remainingMana - spell.manaCost
                content = content .. " [Remaining Mana: " .. remainingMana .. "]"
                content = content .. "\n"
                if remainingMana < 0 then
                    content = content .. "Warning: Not enough mana for this spell.\n"
                    break
                end
            end
            if considerCastTime then
                content = content .. string.format("\nEstimated time to kill: %.2f seconds", totalTime)
            end
            content = content .. string.format("\nTotal estimated damage: %d", math.floor(totalDamage))
            content = content .. string.format("\nTotal mana cost: %d", totalMana)
            if totalDamage < targetHealth then
                content = content .. string.format("\nWarning: Not enough damage to defeat the target. Missing %d damage.", targetHealth - totalDamage)
            end
            if totalMana > playerMana then
                content = content .. string.format("\nWarning: Not enough mana. Missing %d mana.", totalMana - playerMana)
            end
        else
            content = content .. "No optimal sequence found."
        end
        ActionPlanner.contentText:SetText(content)
        ActionPlanner.content:SetHeight(ActionPlanner.contentText:GetStringHeight() + 20)
    else
        ActionPlanner.contentText:SetText("No target selected or target is dead.")
        ActionPlanner.content:SetHeight(ActionPlanner.contentText:GetStringHeight() + 20)
    end
end

ActionPlanner:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_TARGET_CHANGED" or event == "UNIT_HEALTH" or event == "UNIT_POWER_UPDATE" then
        UpdateActionPlanner()
    end
end)

ActionPlanner:RegisterEvent("PLAYER_TARGET_CHANGED")
ActionPlanner:RegisterUnitEvent("UNIT_HEALTH", "target")
ActionPlanner:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")

-- Initialize
UpdateActionPlanner()

-- Toggle visibility function
function ToggleActionPlanner()
    if ActionPlanner:IsShown() then
        ActionPlanner:Hide()
    else
        ActionPlanner:Show()
        UpdateActionPlanner()  -- Update when showing
    end
end

-- Create a slash command to toggle the frame
SLASH_ACTIONPLANNER1 = "/actionplanner"
SlashCmdList["ACTIONPLANNER"] = ToggleActionPlanner

-- Toggle cast time consideration function
function ToggleCastTimeConsideration()
    considerCastTime = not considerCastTime
    print("Cast time consideration is now " .. (considerCastTime and "ON" or "OFF"))
    UpdateActionPlanner()
end

-- Create a slash command to toggle cast time consideration
SLASH_TOGGLECASTTIME1 = "/togglecasttime"
SlashCmdList["TOGGLECASTTIME"] = ToggleCastTimeConsideration

ActionPlanner:Show()
