local frame = CreateFrame("FRAME")
local centerButton
local XP = CommanderMinimapXP
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
frame:RegisterEvent("PLAYER_XP_UPDATE")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("UPDATE_EXHAUSTION")
frame:RegisterEvent("PLAYER_UPDATE_RESTING")
if not C_EventUtils or C_EventUtils.IsEventValid("QUEST_TURNED_IN") then
    pcall(frame.RegisterEvent, frame, "QUEST_TURNED_IN")
end

local function Snapshot()
    return XP.Snapshot(GetTime())
end

local RenderXPText -- assigned once the button text exists at login

-- Drops the line into the chat box for the player to send (or not)
local function PasteXPToChat()
    local text = XP.ChatLine(Snapshot())
    local editBox = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
    if editBox then
        editBox:Insert(text)
    else
        ChatFrame_OpenChat(text)
    end
end

local function ResetXPSession()
    XP.ResetSession(GetTime())
    if RenderXPText then RenderXPText() end
    print("Commander Minimap: XP session reset")
end

-- ---------------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------------

local LABEL = {1, 0.82, 0}          -- gold labels, like the stock tooltips
local VALUE = {1, 1, 1}
local RESTED = {0.35, 0.65, 1}      -- the stock bar's rested blue
local MUTED = {0.6, 0.6, 0.6}
local HINT = {0.4, 0.9, 0.4}

local function Row(tooltip, label, value, color)
    color = color or VALUE
    tooltip:AddDoubleLine(label, value, LABEL[1], LABEL[2], LABEL[3], color[1], color[2], color[3])
end

local function Pct(value)
    return string.format("%.1f%%", value)
end

local function AddProgress(tooltip, s)
    Row(tooltip, "Current", XP.Number(s.xp) .. " / " .. XP.Number(s.max) .. "  (" .. Pct(s.pct) .. ")")
    Row(tooltip, "Remaining", XP.Number(s.remaining) .. "  (" .. Pct(s.remainingPct) .. ")")
    Row(tooltip, "Bars", string.format("%.1f / %d  (%.1f to go)", s.bubbles, XP.BUBBLES, XP.BUBBLES - s.bubbles))
end

local function AddRested(tooltip, s)
    tooltip:AddLine(" ")
    if s.rested > 0 then
        Row(tooltip, "Rested", XP.Number(s.rested) .. "  (" .. Pct(s.restedPct) .. ")", RESTED)
        if s.restedEndLevel == s.level then
            Row(tooltip, "Rested until", Pct(s.restedEndPct) .. " of this level", RESTED)
        elseif s.restedEndLevel then
            Row(tooltip, "Rested until", string.format("level %d, %.0f%%", s.restedEndLevel, s.restedEndPct), RESTED)
        end
        if s.restedKills then
            Row(tooltip, "Rested kills", "~" .. s.restedKills, RESTED)
        end
    else
        Row(tooltip, "Rested", "None", MUTED)
    end
    if s.resting then
        Row(tooltip, "Status", "Resting", RESTED)
        if s.restedFullIn then
            Row(tooltip, "Rested full in", XP.Duration(s.restedFullIn), RESTED)
        end
    else
        Row(tooltip, "Status", "Not resting", MUTED)
    end
end

local function AddSession(tooltip, s)
    tooltip:AddLine(" ")
    tooltip:AddLine("Session", LABEL[1], LABEL[2], LABEL[3])
    Row(tooltip, "Time", XP.Duration(s.elapsed) or "--")
    local gained = XP.Number(s.gained)
    if s.levelsGained > 0 then
        gained = gained .. string.format("  (+%d level%s)", s.levelsGained, s.levelsGained == 1 and "" or "s")
    end
    Row(tooltip, "XP gained", gained)
    Row(tooltip, "XP / hour", s.perHour and XP.Number(s.perHour) or "--", s.perHour and VALUE or MUTED)
    Row(tooltip, "Time to level", s.timeToLevel and XP.Duration(s.timeToLevel) or "--", s.timeToLevel and VALUE or MUTED)
    if s.gained > 0 then
        local function Share(amount) return string.format("%.0f%%", amount / s.gained * 100) end
        Row(tooltip, "From kills", string.format("%s  (%d, %s)", XP.Number(s.sessionKillXP), s.sessionKills, Share(s.sessionKillXP)))
        Row(tooltip, "From quests", string.format("%s  (%d, %s)", XP.Number(s.sessionQuestXP), s.sessionQuests, Share(s.sessionQuestXP)))
        if s.sessionOtherXP > 0 then
            Row(tooltip, "Other", XP.Number(s.sessionOtherXP) .. "  (" .. Share(s.sessionOtherXP) .. ")")
        end
    end
end

local function AddEstimates(tooltip, s)
    tooltip:AddLine(" ")
    tooltip:AddLine("To Level", LABEL[1], LABEL[2], LABEL[3])
    if s.lastKill then
        local last = XP.Number(s.lastKill.xp)
        if (s.lastKill.bonus or 0) > 0 then
            last = last .. " (+" .. XP.Number(s.lastKill.bonus) .. " rested)"
        end
        Row(tooltip, "Last kill", (s.lastKill.name and (s.lastKill.name .. ": ") or "") .. last)
    end
    if s.avgKill then
        Row(tooltip, "Kills", string.format("~%d  (avg %s base, last %d)", s.killsToLevel or 0, XP.Number(s.avgKill), s.killSamples))
    else
        Row(tooltip, "Kills", "--  (no kills recorded)", MUTED)
    end
    if s.avgQuest then
        Row(tooltip, "Quests", string.format("~%d  (avg %s, last %d)", s.questsToLevel or 0, XP.Number(s.avgQuest), s.questSamples))
    else
        Row(tooltip, "Quests", "--  (no quests recorded)", MUTED)
    end
end

local function AddHints(tooltip)
    tooltip:AddLine(" ")
    tooltip:AddLine("Left-click: Game windows", HINT[1], HINT[2], HINT[3])
    tooltip:AddLine("Right-click: Character stats", HINT[1], HINT[2], HINT[3])
    tooltip:AddLine("Middle-click: Professions", HINT[1], HINT[2], HINT[3])
    tooltip:AddLine("Shift-click: Paste XP to chat", HINT[1], HINT[2], HINT[3])
    tooltip:AddLine("Ctrl-click: Reset XP session", HINT[1], HINT[2], HINT[3])
end

local function FillTooltip(owner)
    local s = Snapshot()
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddDoubleLine("Experience", "Level " .. s.level, 1, 1, 1, LABEL[1], LABEL[2], LABEL[3])
    if s.capped then
        GameTooltip:AddLine("Maximum level reached", MUTED[1], MUTED[2], MUTED[3])
    else
        if s.disabled then
            GameTooltip:AddLine("Experience gain is turned off", 1, 0.3, 0.3)
        end
        AddProgress(GameTooltip, s)
        AddRested(GameTooltip, s)
        AddSession(GameTooltip, s)
        AddEstimates(GameTooltip, s)
    end
    AddHints(GameTooltip)
    GameTooltip:Show()
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
        -- Commander Spellbook's window when it has taken the book over: an
        -- addon calling Blizzard's ToggleSpellBook would only have it put
        -- straight away again (and taints the stock book's state)
        {text = "Spellbook", func = function()
            local book = CommanderSpellbook
            if type(book) == "table" and book.TakingOver and book.TakingOver() and CommanderSpellbook_Toggle then
                CommanderSpellbook_Toggle()
            else
                ToggleSpellBook(BOOKTYPE_SPELL)
            end
        end},
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
    local s = Snapshot()
    local menu = {}
    if s.capped then
        menu[#menu + 1] = {text = "Level " .. s.level .. " (max level)", isTitle = true}
    else
        menu[#menu + 1] = {text = string.format("Level %d: %.1f%%", s.level, s.pct), isTitle = true}
        menu[#menu + 1] = {text = "XP: " .. XP.Number(s.xp) .. " / " .. XP.Number(s.max)}
        menu[#menu + 1] = {text = string.format("Rested: %s (%.0f%%)", XP.Number(s.rested), s.restedPct)}
        if s.lastKill then
            menu[#menu + 1] = {text = "Last Kill: " .. XP.Number(s.lastKill.xp) .. " (" .. (s.lastKill.name or "unknown") .. ")"}
        end
        menu[#menu + 1] = {text = "Kills to Level: " .. (s.killsToLevel and ("~" .. s.killsToLevel) or "--")}
        menu[#menu + 1] = {text = "XP / Hour: " .. (s.perHour and XP.Number(s.perHour) or "--")}
        menu[#menu + 1] = {text = "Paste XP to Chat", notCheckable = true, func = function() PasteXPToChat() end}
        menu[#menu + 1] = {text = "Reset XP Session", notCheckable = true, func = function() ResetXPSession() end}
    end
    for _, item in ipairs({
        {text = string.format("Gold: %dg %ds %dc", playerMoney / 10000, (playerMoney % 10000) / 100, playerMoney % 100)},
        {text = string.format("Durability: %.1f%%", durability)},
        {text = "Latency: " .. select(3, GetNetStats()) .. "ms"},
    }) do
        menu[#menu + 1] = item
    end
    return menu
end

-- Informational only: CastSpellByName is protected and cannot be called
-- from an insecure dropdown click
local function CreateSubskillMenu(subSkills)
    local menuList = {}
    for _, subSkill in ipairs(subSkills) do
        table.insert(menuList, {
            text = subSkill.name .. " (" .. subSkill.skillLevel .. ")",
        })
    end
    return menuList
end

local function CreateProfessionMenuItem(profession)
    return {
        text = profession.name .. " (" .. profession.skillLevel .. ")",
        hasArrow = #profession.subSkills > 0,
        menuList = CreateSubskillMenu(profession.subSkills),
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
    xpText:SetDrawLayer("OVERLAY", 7)
    return xpText
end

local BUTTON_TEXT = {
    PERCENTAGE = function(s) return math.floor(s.pct) .. "%" end,
    KILLS_TO_LEVEL = function(s) return s.killsToLevel and tostring(s.killsToLevel) or "--" end,
    REMAINING = function(s) return XP.Short(s.remaining) end,
    RESTED = function(s) return math.floor(s.restedPct) .. "%" end,
    TIME_TO_LEVEL = function(s) return XP.ShortDuration(s.timeToLevel) end,
}

local function CreateXPTextUpdater(xpText)
    local function UpdateXPText()
        local s = Snapshot()
        local render = BUTTON_TEXT[CommanderMinimapDB.XPDisplayMode] or BUTTON_TEXT.PERCENTAGE
        xpText:SetText(s.capped and "Max" or render(s))
        -- Recolored on every update: rested comes and goes during a session
        if s.rested > 0 and not s.capped then
            xpText:SetTextColor(0, 1, 1)
        else
            xpText:SetTextColor(0.58, 0.0, 0.55)
        end
        xpText:Show()
    end
    return UpdateXPText
end

local function ApplyButtonVisibility()
    if CommanderMinimapDB.ShowMinimapButton then
        centerButton:Show()
    else
        centerButton:Hide()
    end
end

local function Refresh()
    if RenderXPText then RenderXPText() end
    if centerButton and GameTooltip:IsOwned(centerButton) then
        FillTooltip(centerButton)
    end
end

centerButton = CreateFrame("Button", "CommanderMinimapButton", Minimap)
centerButton:SetSize(30, 30)
centerButton:SetAlpha(1)
centerButton:SetScale(1)
centerButton:SetNormalTexture("Interface\\Minimap\\UI-Minimap-Background")
centerButton:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", 36, -32)
centerButton:SetClampedToScreen(true)
centerButton:EnableMouse(true)
centerButton:SetScript("OnEnter", function(self)
    FillTooltip(self)
end)
centerButton:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
end)
-- Session time and pace keep moving while the tooltip is up
local tooltipElapsed = 0
centerButton:SetScript("OnUpdate", function(self, elapsed)
    tooltipElapsed = tooltipElapsed + elapsed
    if tooltipElapsed < 1 then return end
    tooltipElapsed = 0
    if GameTooltip:IsOwned(self) then
        FillTooltip(self)
    end
end)
centerButton:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
local menuFrames = {} -- reuse one dropdown frame per button instead of leaking a new frame every click
centerButton:SetScript("OnClick", function(self, button)
    if IsShiftKeyDown() then
        PasteXPToChat()
        return
    elseif IsControlKeyDown() then
        ResetXPSession()
        return
    end
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
    XP.Init(CommanderMinimapDB, GetTime())
    RenderXPText = CreateXPTextUpdater(CreateXPText())
    Commander.AddListener(COMMANDER_MINIMAP_EVENTS.COMMANDER_MINIMAP, function()
        ApplyButtonVisibility()
        RenderXPText()
    end)
    RenderXPText()
    ApplyButtonVisibility()
end

local function OnEvent(self, event, ...)
    if event == "PLAYER_LOGIN" then
        OnAwake()
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        XP.OnKillMessage((...))
        Refresh()
    elseif event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" then
        XP.OnXPUpdate()
        Refresh()
    elseif event == "QUEST_TURNED_IN" then
        -- (questID, xpReward, moneyReward)
        local _, xpReward = ...
        XP.OnQuestTurnedIn(xpReward)
        Refresh()
    elseif event == "UPDATE_EXHAUSTION" or event == "PLAYER_UPDATE_RESTING" then
        Refresh()
    end
end

frame:SetScript("OnEvent", OnEvent)
