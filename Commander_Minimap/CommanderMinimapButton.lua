local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT") 
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
frame:RegisterEvent("PLAYER_XP_UPDATE")

-- XP calculation functions
local function GetXPPercentage()
    return math.floor((UnitXP("player") / UnitXPMax("player")) * 100)
end

local function GetRestedXPPercentage()
    return math.min(math.floor(((GetXPExhaustion() or 0) / UnitXPMax("player")) * 100), 150)
end

local function CalculateKillsToLevel()
    local xpNeeded = UnitXPMax("player") - UnitXP("player")
    return CommanderMinimapDB.lastXPGain and CommanderMinimapDB.lastXPGain > 0 and math.ceil(xpNeeded / CommanderMinimapDB.lastXPGain) or 0
end

local function GetDurability()
    local durability = 100
    for i = 1, 18 do
        local current, maximum = GetInventoryItemDurability(i)
        if current and maximum then
            durability = math.min(durability, current / maximum * 100)
        end
    end
    return durability
end

-- Menu creation functions
local function CreateLeftClickMenu()
    return {
        {text = "Character", func = function() ToggleCharacter("PaperDollFrame") end},
        {text = "Spellbook", func = function() ToggleSpellBook(BOOKTYPE_SPELL) end},
        {text = "Talents", func = function() ToggleTalentFrame() end},
        {text = "Quest Log", func = function() ToggleQuestLog() end},
        {text = "Social", func = function() ToggleFriendsFrame() end},
        {text = "World Map", func = function() ToggleWorldMap() end},
        {text = "Main Menu", func = function() ToggleGameMenu() end},
        {text = "All Bags", func = function() OpenAllBags() end},
        {text = "Settings", func = function() OpenSettings() end},
        {text = "Reload", func = function() ReloadUI() end},
    }
end

local function CreateRightClickMenu()
    local playerMoney = GetMoney()
    local durability = GetDurability()
    
    return {
        {text = "Current XP: " .. GetXPPercentage() .. "%", isTitle = true},
        {text = "Rested XP: " .. GetRestedXPPercentage() .. "%"},
        {text = "Last XP Gain: " .. (CommanderMinimapDB.lastXPGain or 0) .. " (" .. (CommanderMinimapDB.lastXPSource or "N/A") .. ")"},
        {text = "Kills to Level: " .. CalculateKillsToLevel()},
        {text = string.format("Gold: %dg %ds %dc", playerMoney / 10000, (playerMoney % 10000) / 100, playerMoney % 100)},
        {text = string.format("Durability: %.1f%%", durability)},
        {text = "Latency: " .. select(3, GetNetStats()) .. "ms"},
    }
end

local function CreateSubskillMenu(subSkills)
    local menuList = {}
    for _, subSkill in ipairs(subSkills) do
        table.insert(menuList, {
            text = subSkill.name .. " (" .. subSkill.skillLevel .. ")",
            func = function() CastSpellByName(subSkill.name) end
        })
    end
    return menuList
end

local function CreateProfessionMenuItem(profession)
    return {
        text = profession.name .. " (" .. profession.skillLevel .. ")",
        hasArrow = #profession.subSkills > 0,
        menuList = CreateSubskillMenu(profession.subSkills),
        func = function() CastSpellByName(profession.name) end
    }
end

local function AddProfessionSubskills(profession, index)
    if profession.name == "Mining" then
        for j = index + 1, GetNumSkillLines() do
            local subName, subIsHeader, _, subSkillLevel = GetSkillLineInfo(j)
            if subIsHeader then break end
            if subName == "Smelting" then
                table.insert(profession.subSkills, {name = "Smelting", skillLevel = subSkillLevel})
                break
            end
        end
        if GetSpellInfo(2580) then
            table.insert(profession.subSkills, {name = "Find Minerals", skillLevel = "Learned"})
        end
    elseif profession.name == "Herbalism" and GetSpellInfo(2383) then
        table.insert(profession.subSkills, {name = "Find Herbs", skillLevel = "Learned"})
    end
end

local function GetPlayerProfessions()
    local professions = {}
    local validProfessions = {
        Alchemy = true, Blacksmithing = true, Enchanting = true, Engineering = true,
        Herbalism = true, Leatherworking = true, Mining = true, Skinning = true,
        Tailoring = true, Cooking = true, ["First Aid"] = true, Fishing = true
    }
    
    for i = 1, GetNumSkillLines() do
        local name, isHeader, _, skillLevel = GetSkillLineInfo(i)
        if not isHeader and name and skillLevel > 0 and validProfessions[name] then
            local profession = {name = name, skillLevel = skillLevel, subSkills = {}}
            AddProfessionSubskills(profession, i)
            table.insert(professions, profession)
        end
    end
    return professions
end

local function CreateProfessionMenu()
    local professions = GetPlayerProfessions()
    if #professions == 0 then
        return {{text = "No professions available", disabled = true}}
    end
    
    local menuList = {}
    for _, profession in ipairs(professions) do
        table.insert(menuList, CreateProfessionMenuItem(profession))
    end
    return menuList
end

local function GetMenuListForButton(button)
    if button == "LeftButton" then
        return CreateLeftClickMenu()
    elseif button == "RightButton" then
        return CreateRightClickMenu()
    elseif button == "MiddleButton" then
        return CreateProfessionMenu()
    end
    return {}
end

-- Click handler setup
local function SetupClickHandlers(centerButton)
    centerButton:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    centerButton:SetScript("OnClick", function(self, button)
        local menuFrame = CreateFrame("Frame", "My" .. button .. "ButtonMenu", UIParent, "UIDropDownMenuTemplate")
        local menuList = GetMenuListForButton(button)
        
        UIDropDownMenu_Initialize(menuFrame, function(self, level)
            for _, item in ipairs(menuList) do
                UIDropDownMenu_AddButton(item, level)
            end
        end)
        ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)
    end)
end

-- Button creation and configuration
local function CreateCenterButton()
    local centerButton = CreateFrame("Button", "MyCenterButton", Minimap)
    centerButton:SetSize(32, 32)
    centerButton:SetNormalTexture("Interface\\Minimap\\UI-Minimap-Background")
    centerButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    centerButton:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
    
    -- Make button movable
    centerButton:SetMovable(true)
    centerButton:EnableMouse(true)
    centerButton:RegisterForDrag("LeftButton")
    centerButton:SetScript("OnDragStart", function(self) self:StartMoving() end)
    centerButton:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    
    -- Set up tooltip
    centerButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("XP Tracker")
        GameTooltip:AddLine("Left-click and drag to move")
        GameTooltip:Show()
    end)
    centerButton:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    return centerButton
end

-- XP text creation and configuration 
local function CreateXPText(centerButton)
    local xpText = centerButton:CreateFontString(GetXPPercentage(), "OVERLAY")
    xpText:SetFontObject(GameFontHighlight)
    xpText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    xpText:SetPoint("CENTER", centerButton, "CENTER")
    -- Set color based on rested XP status
    if GetXPExhaustion() and GetXPExhaustion() > 0 then
        xpText:SetTextColor(0.6, 0.39, 0.98) -- Purple color for rested XP
    else
        xpText:SetTextColor(0.58, 0.0, 0.55) -- Pink/magenta color for normal XP
    end
    xpText:SetDrawLayer("OVERLAY", 7)
    return xpText
end

-- XP text updating
local function CreateXPTextUpdater(xpText)
    local function UpdateXPText()
        local text = CommanderMinimapDB.XPDisplayMode == "KILLS_TO_LEVEL" and CalculateKillsToLevel() or GetXPPercentage() .. "%"
        xpText:SetText(text)
        xpText:Show()
    end
    return UpdateXPText
end

local function SetupXPEventHandlers(updateXPText)
    frame:HookScript("OnEvent", function(self, event)
        if event == "CHAT_MSG_COMBAT_XP_GAIN" or event == "PLAYER_XP_UPDATE" then
            updateXPText()
        end
    end)
    
    AddListener(COMMANDER_MINIMAP_EVENTS.COMMANDER_MINIMAP_XP_DISPLAY_MODE_CHANGED, updateXPText)
end

local function MicroBarButtons()
    -- Create and configure the main button
    local centerButton = CreateCenterButton()
    local xpText = CreateXPText(centerButton)
    
    -- Set up click handlers
    SetupClickHandlers(centerButton)
    
    -- Set up XP text updating
    local updateXPText = CreateXPTextUpdater(xpText)
    SetupXPEventHandlers(updateXPText)
    
    -- Initial update
    updateXPText()
    
    return updateXPText
end

local function OnAwake()
    CommanderMinimapDB.lastXPGain = CommanderMinimapDB.lastXPGain or 0
    CommanderMinimapDB.lastXPSource = CommanderMinimapDB.lastXPSource or ""
    CommanderMinimapDB.lastKnownXP = UnitXP("player")
    frame.RenderXPText = MicroBarButtons()
end

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" and ... == "Commander_Minimap" then
        OnAwake()
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        local message = ...
        local mobName, xpGain = message:match("^(.+) dies, you gain (%d+) experience")
        if mobName then
            CommanderMinimapDB.lastXPSource = mobName
            xpGain = tonumber(xpGain)
            if xpGain then
                CommanderMinimapDB.lastXPGain = xpGain
                CommanderMinimapDB.lastKnownXP = UnitXP("player")
                UpdateLastXPGain(xpGain, mobName) -- Call DB update function
            end
        end
        if frame.RenderXPText then 
            frame.RenderXPText()
            UpdateKillsToLevel() -- Update kills needed after XP gain
        end
    elseif event == "PLAYER_XP_UPDATE" then
        if frame.RenderXPText then
            frame.RenderXPText()
            UpdateKillsToLevel() -- Update kills needed after any XP change
        end
    end
end)