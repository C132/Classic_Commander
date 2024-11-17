local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
frame:RegisterEvent("PLAYER_XP_UPDATE")

local function MicroBarButtons()
    local centerButton = CreateFrame("Button", "MyCenterButton", Minimap)
    centerButton:SetSize(32, 32)
    centerButton:SetNormalTexture("Interface\\Minimap\\UI-Minimap-Background")
    centerButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    centerButton:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    centerButton:SetMovable(true)
    centerButton:EnableMouse(true)
    centerButton:RegisterForDrag("LeftButton")
    centerButton:SetScript("OnDragStart", function(self) self:StartMoving() end)
    centerButton:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    centerButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("XP Tracker")
        GameTooltip:AddLine("Left-click and drag to move")
        GameTooltip:Show()
    end)
    centerButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    local xpText = centerButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    xpText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    xpText:SetPoint("CENTER", centerButton, "CENTER", 1, 0)
    xpText:SetTextColor(GetXPExhaustion() and 0 or 0.64, GetXPExhaustion() and 1 or 0, GetXPExhaustion() and 1 or 0.96)
    xpText:SetDrawLayer("OVERLAY", 7)

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

    local function UpdateXPText()
        xpText:SetText(CommanderMinimapDB.XPDisplayMode == "KILLS_TO_LEVEL" and CalculateKillsToLevel() or GetXPPercentage() .. "%")
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
                
                if name == "Mining" then
                    for j = i + 1, GetNumSkillLines() do
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
                elseif name == "Herbalism" and GetSpellInfo(2383) then
                    table.insert(profession.subSkills, {name = "Find Herbs", skillLevel = "Learned"})
                end
                
                table.insert(professions, profession)
            end
        end
        return professions
    end

    centerButton:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    centerButton:SetScript("OnClick", function(self, button)
        local menuFrame = CreateFrame("Frame", "My" .. button .. "ButtonMenu", UIParent, "UIDropDownMenuTemplate")
        local menuList = {}
        
        if button == "LeftButton" then
            menuList = {
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
        elseif button == "RightButton" then
            local playerMoney = GetMoney()
            local durability = 100
            for i = 1, 18 do
                local current, maximum = GetInventoryItemDurability(i)
                if current and maximum then
                    durability = math.min(durability, current / maximum * 100)
                end
            end
            
            menuList = {
                {text = "Current XP: " .. GetXPPercentage() .. "%", isTitle = true},
                {text = "Rested XP: " .. GetRestedXPPercentage() .. "%"},
                {text = "Last XP Gain: " .. (CommanderMinimapDB.lastXPGain or 0) .. " (" .. (CommanderMinimapDB.lastXPSource or "N/A") .. ")"},
                {text = "Kills to Level: " .. CalculateKillsToLevel()},
                {text = string.format("Gold: %dg %ds %dc", playerMoney / 10000, (playerMoney % 10000) / 100, playerMoney % 100)},
                {text = string.format("Durability: %.1f%%", durability)},
                {text = "Latency: " .. select(3, GetNetStats()) .. "ms"},
            }
        elseif button == "MiddleButton" then
            local professions = GetPlayerProfessions()
            for _, profession in ipairs(professions) do
                local menuItem = {
                    text = profession.name .. " (" .. profession.skillLevel .. ")",
                    hasArrow = #profession.subSkills > 0,
                    menuList = {},
                    func = function() CastSpellByName(profession.name) end
                }
                
                for _, subSkill in ipairs(profession.subSkills) do
                    table.insert(menuItem.menuList, {
                        text = subSkill.name .. " (" .. subSkill.skillLevel .. ")",
                        func = function() CastSpellByName(subSkill.name) end
                    })
                end
                
                table.insert(menuList, menuItem)
            end
            
            if #menuList == 0 then
                table.insert(menuList, {text = "No professions available", disabled = true})
            end
        end
        
        UIDropDownMenu_Initialize(menuFrame, function(self, level)
            for _, item in ipairs(menuList) do
                UIDropDownMenu_AddButton(item, level)
            end
        end)
        ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)
    end)

    UpdateXPText()
    frame:HookScript("OnEvent", function(self, event)
        if event == "CHAT_MSG_COMBAT_XP_GAIN" or event == "PLAYER_XP_UPDATE" then
            UpdateXPText()
        end
    end)

    AddListener(EVENTS.XP_DISPLAY_MODE_CHANGED, UpdateXPText)

    return UpdateXPText
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
            end
        end
        if self.RenderXPText then self.RenderXPText() end
    elseif event == "PLAYER_XP_UPDATE" then
        if self.RenderXPText then self.RenderXPText() end
    end
end)