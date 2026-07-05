local frame = CreateFrame("FRAME")
local centerButton
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
frame:RegisterEvent("PLAYER_XP_UPDATE")

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

local function CreateLeftClickMenu()
    return {
        {text = "Character", func = function() ToggleCharacter("PaperDollFrame") end},
        {text = "Spellbook", func = function() ToggleSpellBook(BOOKTYPE_SPELL) end},
        {text = "Talents", func = function() ToggleTalentFrame() end},
        {text = "Quest Log", func = function() ToggleQuestLog() end},
        {text = "Social", func = function() ToggleFriendsFrame() end},
        {text = "World Map", func = function() ToggleWorldMap() end},
        {text = "System Menu", func = function() GameMenuFrame:Show() end},
        {text = "All Bags", func = function() OpenAllBags() end},
        {text = "Settings", func = function() SettingsPanel:Open() end}, -- OpenSettings() does not exist on 2.5.5
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
        -- GetSpellInfo returns data for any valid spell ID, learned or not;
        -- C_SpellBook.IsSpellKnown is the real "is it learned" check
        if C_SpellBook.IsSpellKnown(2580, Enum.SpellBookSpellBank.Player) then
            table.insert(profession.subSkills, {name = "Find Minerals", skillLevel = "Learned"})
        end
    elseif profession.name == "Herbalism" and C_SpellBook.IsSpellKnown(2383, Enum.SpellBookSpellBank.Player) then
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

local function CreateXPText()
    local xpText = centerButton:CreateFontString(nil, "OVERLAY")
    xpText:SetFontObject(GameFontHighlight)
    xpText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    xpText:SetPoint("CENTER", centerButton, "CENTER")
    if GetXPExhaustion() and GetXPExhaustion() > 0 then
        xpText:SetTextColor(0, 1, 1)
    else
        xpText:SetTextColor(0.58, 0.0, 0.55)
    end
    xpText:SetDrawLayer("OVERLAY", 7)
    return xpText
end

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
    
    AddListener(COMMANDER_MINIMAP_EVENTS.COMMANDER_MINIMAP, updateXPText)
end

local function MicroBarButtons()
    local xpText = CreateXPText()
    local updateXPText = CreateXPTextUpdater(xpText)
    SetupXPEventHandlers(updateXPText)
    
    updateXPText()    
    return updateXPText
end

centerButton = CreateFrame("Button", "CommanderMinimapButton", Minimap)
centerButton:SetSize(30, 30)
centerButton:SetAlpha(1)
centerButton:SetScale(1)
centerButton:SetNormalTexture("Interface\\Minimap\\UI-Minimap-Background")
centerButton:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", 36, -32)
--centerButton:SetMovable(true)
centerButton:SetClampedToScreen(true)
centerButton:EnableMouse(true)
--centerButton:RegisterForDrag("LeftButton")
centerButton:SetScript("OnDragStart", function(self)
    if not CommanderMinimapDB.MinimapButtonLocked then
        self:StartMoving()
    end
end)
centerButton:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
end)
centerButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("XP Tracker")
    GameTooltip:AddLine("Left-click and drag to move")
    GameTooltip:Show()
end)
centerButton:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
end)
centerButton:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
local menuFrames = {} -- reuse one dropdown frame per button instead of leaking a new frame every click
centerButton:SetScript("OnClick", function(self, button)
    local menuFrame = menuFrames[button]
    if not menuFrame then
        menuFrame = CreateFrame("Frame", "My" .. button .. "ButtonMenu", UIParent, "UIDropDownMenuTemplate")
        menuFrames[button] = menuFrame
    end
    local menuList = GetMenuListForButton(button)

    UIDropDownMenu_Initialize(menuFrame, function(self, level, list)
        -- list is the submenu's menuList when a nested level opens (e.g. profession subskills)
        for _, item in ipairs(list or menuList) do
            UIDropDownMenu_AddButton(item, level)
        end
    end)
    ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)
end)


local function OnAwake()
    CommanderMinimapDB.lastXPGain = CommanderMinimapDB.lastXPGain or 0
    CommanderMinimapDB.lastXPSource = CommanderMinimapDB.lastXPSource or ""
    CommanderMinimapDB.lastKnownXP = UnitXP("player")
    frame.RenderXPText = MicroBarButtons()
end 

local function OnEvent(self, event, ...)
    if event == "PLAYER_LOGIN" then
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
                UpdateLastXPGain(xpGain, mobName)
            end
        end
        if frame.RenderXPText then 
            frame.RenderXPText()
            UpdateKillsToLevel()
        end
    elseif event == "PLAYER_XP_UPDATE" then
        if frame.RenderXPText then
            frame.RenderXPText()
            UpdateKillsToLevel()
        end
    end
end

frame:SetScript("OnEvent", OnEvent)