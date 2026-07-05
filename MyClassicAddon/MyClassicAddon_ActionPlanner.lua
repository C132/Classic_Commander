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

-- Debug Frame
local DebugFrame = CreateFrame("Frame", "MyClassicAddonDebugFrame", UIParent, "BackdropTemplate")
DebugFrame:SetSize(400, 500)
DebugFrame:SetPoint("CENTER")
DebugFrame:SetMovable(true)
DebugFrame:EnableMouse(true)
DebugFrame:RegisterForDrag("LeftButton")
DebugFrame:SetScript("OnDragStart", DebugFrame.StartMoving)
DebugFrame:SetScript("OnDragStop", DebugFrame.StopMovingOrSizing)
DebugFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
})
DebugFrame:SetBackdropColor(0, 0, 0, 0.8)
DebugFrame:Hide()

DebugFrame.title = DebugFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
DebugFrame.title:SetPoint("TOP", 0, -5)
DebugFrame.title:SetText("Debug Information")

DebugFrame.closeButton = CreateFrame("Button", nil, DebugFrame, "UIPanelCloseButton")
DebugFrame.closeButton:SetPoint("TOPRIGHT", -5, -5)
DebugFrame.closeButton:SetScript("OnClick", function() DebugFrame:Hide() end)

DebugFrame.scrollFrame = CreateFrame("ScrollFrame", nil, DebugFrame, "UIPanelScrollFrameTemplate")
DebugFrame.scrollFrame:SetPoint("TOPLEFT", 10, -30)
DebugFrame.scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

DebugFrame.content = CreateFrame("Frame", nil, DebugFrame.scrollFrame)
DebugFrame.content:SetSize(360, 1)
DebugFrame.scrollFrame:SetScrollChild(DebugFrame.content)

DebugFrame.contentText = DebugFrame.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
DebugFrame.contentText:SetPoint("TOPLEFT")
DebugFrame.contentText:SetPoint("TOPRIGHT")
DebugFrame.contentText:SetJustifyH("LEFT")
DebugFrame.contentText:SetJustifyV("TOP")

local function UpdateDebugFrame()
    local debugInfo = "Spell IDs in ActionBarOutput:\n"
    if ActionBarOutput and type(ActionBarOutput.GetCachedOutputs) == "function" then
        local cachedOutputs = ActionBarOutput:GetCachedOutputs()
        for spellId, damage in pairs(cachedOutputs) do
            local spellName = GetSpellInfo(spellId)
            debugInfo = debugInfo .. string.format("ID: %d, Name: %s, Damage: %.2f\n", spellId, spellName or "Unknown", damage)
        end
    else
        debugInfo = debugInfo .. "ActionBarOutput is not properly initialized\n"
    end

    debugInfo = debugInfo .. "\nConsider Cast Time: " .. tostring(considerCastTime) .. "\n"
    
    debugInfo = debugInfo .. "\nPlayer Spells:\n"
    local i = 1
    while true do
        local spellName, spellRank = GetSpellBookItemName(i, BOOKTYPE_SPELL)
        if not spellName then break end
        local spellId = select(7, GetSpellInfo(spellName))
        debugInfo = debugInfo .. string.format("Name: %s, Rank: %s, ID: %s\n", spellName, spellRank or "N/A", spellId or "N/A")
        i = i + 1
    end

    DebugFrame.contentText:SetText(debugInfo)
    DebugFrame.content:SetHeight(DebugFrame.contentText:GetStringHeight() + 20)
end

local function GetSpellCost(spellId)
    -- Global GetSpellPowerCost does not exist on the 2.5.5 client; use C_Spell
    local costTable = C_Spell.GetSpellPowerCost(spellId)
    if costTable and #costTable > 0 then
        return costTable[1].cost
    end
    return 0
end

local function GetOptimalSequence(targetHealth, playerMana)
    local sequence = {}
    local remainingHealth = targetHealth
    local remainingMana = playerMana
    local spells = {}
    local cachedOutputs = (ActionBarOutput and type(ActionBarOutput.GetCachedOutputs) == "function")
        and ActionBarOutput:GetCachedOutputs() or {}

    -- Get player's spells
    local i = 1
    while true do
        local spellName, spellRank = GetSpellBookItemName(i, BOOKTYPE_SPELL)
        if not spellName then break end
        local spellId = select(7, GetSpellInfo(spellName))
        if spellId then
            table.insert(spells, {id = spellId, name = spellName, rank = spellRank})
        end
        i = i + 1
    end

    while remainingHealth > 0 and remainingMana > 0 do
        local bestSpell = nil
        local bestDamagePerMana = 0

        for _, spell in ipairs(spells) do
            local damage = cachedOutputs[spell.id] or 0
            local cost = GetSpellCost(spell.id)

            if cost > 0 and cost <= remainingMana then
                local damagePerMana = damage / cost
                if damagePerMana > bestDamagePerMana then
                    bestSpell = spell
                    bestDamagePerMana = damagePerMana
                end
            end
        end

        if bestSpell then
            table.insert(sequence, bestSpell.name .. (bestSpell.rank and " (" .. bestSpell.rank .. ")" or ""))
            local damage = cachedOutputs[bestSpell.id] or 0
            local cost = GetSpellCost(bestSpell.id)
            remainingHealth = remainingHealth - damage
            remainingMana = remainingMana - cost
        else
            break  -- No more suitable spells
        end
    end

    if #sequence == 0 then
        return "No optimal sequence found"
    else
        return table.concat(sequence, " -> ")
    end
end

local function UpdateActionPlanner()
    local targetHealth = UnitHealth("target")
    local playerMana = UnitPower("player", 0)  -- 0 is the type for Mana
    
    if targetHealth and playerMana then
        local sequence = GetOptimalSequence(targetHealth, playerMana)
        ActionPlanner.contentText:SetText(sequence)
        ActionPlanner.content:SetHeight(ActionPlanner.contentText:GetStringHeight() + 20)
    else
        ActionPlanner.contentText:SetText("No target selected or player mana unavailable")
    end
end

ActionPlanner:SetScript("OnEvent", function(self, event, ...)
    if not self:IsShown() then return end  -- Skip recomputing while hidden; Show() refreshes
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
local function ToggleActionPlanner()
    if ActionPlanner:IsShown() then
        ActionPlanner:Hide()
    else
        ActionPlanner:Show()
        UpdateActionPlanner()  -- Update when showing
    end
end

-- Create a slash command to toggle the frame
SLASH_ACTIONPLANNER1 = "/ap"
SlashCmdList["ACTIONPLANNER"] = ToggleActionPlanner

-- Toggle cast time consideration function
local function ToggleCastTimeConsideration()
    considerCastTime = not considerCastTime
    print("Cast time consideration is now " .. (considerCastTime and "ON" or "OFF"))
    UpdateActionPlanner()
    UpdateDebugFrame()
end

-- Create a slash command to toggle cast time consideration
SLASH_TOGGLECASTTIME1 = "/togglecasttime"
SlashCmdList["TOGGLECASTTIME"] = ToggleCastTimeConsideration

-- Toggle debug frame function
local function ToggleDebugFrame()
    if DebugFrame:IsShown() then
        DebugFrame:Hide()
    else
        DebugFrame:Show()
        UpdateDebugFrame()
    end
end

-- Create a slash command to toggle the debug frame
SLASH_DEBUGFRAME1 = "/apdebug"
SlashCmdList["DEBUGFRAME"] = ToggleDebugFrame

ActionPlanner:Hide()  -- Hide by default, only show when called
