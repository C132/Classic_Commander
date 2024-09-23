
function PartyPlanner:Reload()
    SetPortraitTexture(PartyPlanner.UI.characterPortrait.texture, "player");
    PartyPlanner.UI:UpdateChannelOptions()
end

function PartyPlanner.UI:SendMessage()
    local message = PartyPlanner.DATA.currentMessage
    -- print("Message to send:", message)
    local channels = {GetChannelList()}
    for i = 1, #channels, 3 do
        local id, name = channels[i], channels[i+1]
        local disabled = true
        if PartyPlannerSettings.channelSettings[name] ~= nil then
            disabled = PartyPlannerSettings.channelSettings[name].disabled
        else
            PartyPlannerSettings.channelSettings[name] = {
                id = id,
                name = name,
                disabled = true
            }
        end

        if not disabled then
            -- print(id..". "..name..": "..message)
            SendChatMessage(message, "CHANNEL", nil, id)
        end
        
    end
    PartyPlanner.DATA.timeSinceLastSend = 0
end

function PartyPlanner.UI:GetRolesText()
    local rolesText = ""
    local chosenRoles = {}
    local allChecked = true
    for i = 1, #PartyPlanner.UI.roleCheckboxes do
        local container = PartyPlanner.UI.roleCheckboxes[i]
        if container.checkbox:GetChecked() then
            -- print(container.role)
            chosenRoles[#chosenRoles+1] = container.role
        else
            allChecked = false
        end
    end

    if PartyPlannerSettings.useRoleAll and allChecked and PartyPlanner.DATA.currentMode == "LFM" then
        return "all"
    end

    for i = 1, #chosenRoles do
        if i == 1 then
            rolesText = chosenRoles[i]
        elseif i == #chosenRoles then
            if PartyPlanner.DATA.currentMode == "LFG" then
                rolesText = rolesText.." or "..chosenRoles[i]
            else
                rolesText = rolesText.." and "..chosenRoles[i]
            end
        else
            rolesText = rolesText..", "..chosenRoles[i]
        end
    end

    return rolesText
end

function PartyPlanner.UI:UpdatePreviewText()
    
    local message
    if PartyPlanner.DATA.currentMode == "LFG" then
        message = PartyPlannerSettings.LFGmessage
    else
        message = PartyPlannerSettings.LFMmessage
    end
    local parsedMessage = message

    local numOfPlayers = GetNumGroupMembers()
    if numOfPlayers == 0 then
        numOfPlayers = 1
    end

    -- %i - Instance name or abbreviation
    if PartyPlanner.DATA.selectedInstance == nil then
        parsedMessage = parsedMessage:gsub("%%i ", "")
        parsedMessage = parsedMessage:gsub("%%i", "")
        parsedMessage = parsedMessage:gsub(" %%n", "")
        parsedMessage = parsedMessage:gsub("%%n", "")
    else
        if PartyPlannerSettings.useAbreviation then
            parsedMessage = parsedMessage:gsub("%%i", PartyPlanner.DATA.selectedInstance.abr)
        else
            parsedMessage = parsedMessage:gsub("%%i", PartyPlanner.DATA.selectedInstance.name)
        end

        local remainingPlayers = PartyPlanner.DATA.selectedInstance.groupSize - numOfPlayers

        -- %n - Remaining player count needed (dependant on selectedInstance)
        if PartyPlannerSettings.useGroupSizeMin then
            if remainingPlayers > PartyPlannerSettings.groupSizeMin then
                parsedMessage = parsedMessage:gsub(" %%n", "")
                parsedMessage = parsedMessage:gsub("%%n", "")
            else
                parsedMessage = parsedMessage:gsub("%%n", remainingPlayers)
            end
        else
            parsedMessage = parsedMessage:gsub("%%n", remainingPlayers)
        end
    end

    -- %r - Required roles
    local rolesText = PartyPlanner.UI:GetRolesText()
    parsedMessage = parsedMessage:gsub("%%r", rolesText)

    -- %l - Character level
    parsedMessage = parsedMessage:gsub("%%l", PartyPlanner.DATA.characterLevel)

    -- %c - Character class
    parsedMessage = parsedMessage:gsub("%%c", PartyPlanner.DATA.characterClass)
    

    PartyPlanner.DATA.currentMessage = parsedMessage


    PartyPlanner.UI:UpdatePreviewField()
end

function PartyPlanner.UI:SelectMode(mode)
    if not ( mode == "LFM" or mode == "LFG" ) then
        return
    end

    PartyPlanner.DATA.currentMode = mode

    if mode == "LFM" then
        PartyPlanner.UI.mainView:Show()
        PartyPlanner.UI.menuView:Hide()
        PartyPlanner.UI.swapMiniButton:Show()
    else
        PartyPlanner.UI.mainView:Show()
        PartyPlanner.UI.menuView:Hide()
        PartyPlanner.UI.swapMiniButton:Show()
    end


    PartyPlanner.UI:UpdateRolesSelect()
    PartyPlanner.UI:UpdateInputField()
    PartyPlanner.UI:UpdatePreviewText()
end

function PartyPlanner.UI:CreateMainView()
    local mainView = CreateFrame("FRAME", "partyPlanner-main-view", PartyPlanner.UI)
    mainView:SetPoint("TOPLEFT", PartyPlanner.UI, "TOPLEFT", 0, 0)
    mainView:SetPoint("BOTTOMRIGHT", PartyPlanner.UI, "BOTTOMRIGHT", 0, 0)
    PartyPlanner.UI.mainView = mainView

    local dungSelect = PartyPlanner.UI:CreateDungeonSelect(mainView)

    local rolesOptionsContainer = PartyPlanner.UI:CreateRolesSelect(mainView)

    local channelOptionsContainer = PartyPlanner.UI:CreateChannelOptions(mainView)
    channelOptionsContainer:SetPoint("TOPLEFT", rolesOptionsContainer, "BOTTOMLEFT", 0, -15)

    local inputFieldContainer = PartyPlanner.UI:CreateInputField(mainView)
    inputFieldContainer:SetPoint("TOPLEFT", channelOptionsContainer, "BOTTOMLEFT", 0, -20)

    local previewTextContainer = PartyPlanner.UI:CreatePreviewField(mainView)
    previewTextContainer:SetPoint("TOPLEFT", inputFieldContainer, "BOTTOMLEFT", 0, -30)

    local button = CreateFrame("BUTTON", "partyPlanner-SEND", mainView, "UIPanelButtonTemplate")
    button:SetSize(120, 25)
    button:SetPoint("BOTTOMRIGHT", mainView, "BOTTOMRIGHT", -8, 8)
    button:SetText("Send Message")
    button:SetScript("OnClick", function()
        PartyPlanner.UI:SendMessage()
    end)

    local timeText = mainView:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    timeText:SetPoint("RIGHT", button, "LEFT", -5, 0)
    timeText:SetText("Party Planner")
    timeText:SetFont("Fonts\\FRIZQT__.ttf", 11, "OUTLINE")
    PartyPlanner.UI.timeText = timeText

    -- UI-SpellbookIcon-PrevPage-Up < use this as button image
    local resetButton = CreateFrame("BUTTON", "partyPlanner-reset", mainView)
    resetButton:SetSize(32, 32)
    resetButton:SetPoint("BOTTOMLEFT", mainView, "BOTTOMLEFT", 4, 4)
    resetButton:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    resetButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    resetButton:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
    resetButton:SetScript("OnClick", function ()
        PartyPlanner.UI.mainView:Hide()
        PartyPlanner.UI.menuView:Show()
        PartyPlanner.UI.swapMiniButton:Hide()
        PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN, "Master")
    end)

end

function PartyPlanner.UI:CreateMenu()
    local menuView = CreateFrame("FRAME", "partyPlanner-main-menu", PartyPlanner.UI)
    menuView:SetPoint("TOPLEFT", PartyPlanner.UI, "TOPLEFT", 0, 0)
    menuView:SetPoint("BOTTOMRIGHT", PartyPlanner.UI, "BOTTOMRIGHT", 0, 0)
    PartyPlanner.UI.menuView = menuView

    local lfmButton = CreateFrame("BUTTON", "partyPlanner-menuLFM", menuView, "UIPanelButtonTemplate")
    lfmButton:SetSize(240, 40)
    lfmButton:SetPoint("CENTER", menuView, "CENTER", 0, 50)
    lfmButton:SetText("Create a party")
    lfmButton:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN, "Master")
        PartyPlanner.UI:SelectMode("LFM")
    end)

    local lfgButton = CreateFrame("BUTTON", "partyPlanner-menuLFG", menuView, "UIPanelButtonTemplate")
    lfgButton:SetSize(240, 40)
    lfgButton:SetPoint("CENTER", menuView, "CENTER", 0, -50)
    lfgButton:SetText("LFG mode")
    lfgButton:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN, "Master")
        PartyPlanner.UI:SelectMode("LFG")
    end)

    local orText = menuView:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    orText:SetPoint("CENTER", menuView, "CENTER", 0, 0)
    orText:SetText("--- OR ---")
end

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- UI Build

function PartyPlanner.UI:Build()
    PartyPlanner.UI:SetFrameStrata("DIALOG")
    PartyPlanner.UI:SetSize(338, 422)
    PartyPlanner.UI:SetPoint("CENTER") -- Doesn't need to be ("CENTER", UIParent, "CENTER")
    PartyPlanner.UI:SetMovable(true)
    PartyPlanner.UI:EnableMouse(true)
    PartyPlanner.UI:RegisterForDrag("LeftButton")
    function PartyPlanner.UI:ToggleUI()
        if PartyPlanner.UI:IsShown() then
            PartyPlanner.UI:Hide()
        else
            PartyPlanner.UI:Show()
            PartyPlanner.MINI_UI:Hide()
        end
    end
    PartyPlanner.UI:Hide()
    PartyPlanner.UI:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    PartyPlanner.UI:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)


    PartyPlanner.UI:SetScript("OnShow", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN, "Master");
        PartyPlanner:Reload()
    end)
    PartyPlanner.UI:SetScript("OnHide", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE, "Master");
    end)

    PartyPlanner.UI:CreateMiniUI()

    
    PartyPlanner.UI.timer = nil

    local function updatetimer()
        if PartyPlanner.DATA.timeSinceLastSend > PartyPlanner.DATA.maxTrackedTime then
            PartyPlanner.MINI_UI.timeText:SetText("")
            PartyPlanner.UI.timeText:SetText("")
        else
            PartyPlanner.DATA.timeSinceLastSend = PartyPlanner.DATA.timeSinceLastSend + 1
            PartyPlanner.MINI_UI.timeText:SetText(PartyPlanner.DATA.timeSinceLastSend.."s")
            PartyPlanner.UI.timeText:SetText(PartyPlanner.DATA.timeSinceLastSend.."s")
        end
    end

    local function updatewho()
        if PartyPlanner.UI:IsShown() then
            C_FriendList:SendWho("c-Paladin")
            local numWhos, totalCount = C_FriendList:GetNumWhoResults();
            if numWhos > 0 then
                for index = 1, numWhos do
                    local name, guild, level, race, class, zone, classFileName = C_FriendList:GetWhoInfo(index)
                    print(name, race, class)
                end
            end
        end
    end
    PartyPlanner.MINI_UI.whotimer = C_Timer.NewTicker(10, updatewho)

    PartyPlanner.MINI_UI.timer = C_Timer.NewTicker(1, updatetimer)


    -- Setup the show/hide button
    PartyPlanner.UI:BuildShowButtons()

    -- Pretty up the frame
    PartyPlanner.UI:BuildFrameDecorations()

    PartyPlanner.UI:CreateMenu()

    PartyPlanner.UI:CreateMainView()

    PartyPlanner.UI.mainView:Hide()
    
    PartyPlanner.UI:UpdatePreviewText()

    PartyPlanner.UI.isReady = true
end