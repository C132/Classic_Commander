

function PartyPlanner.UI:CreateChannelOption(frame, id, name, disabled)
    local channelOption = CreateFrame("FRAME", "partyPlanner-channel-option-"..id, frame, "BackdropTemplate")
    channelOption:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", 
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border", 
        tile = true, 
        tileSize = 24, 
        edgeSize = 8, 
        insets = { 
            left = 2, 
            right = 3, 
            top = 5, 
            bottom = 5 
        } 
    });
    channelOption:SetBackdropColor(1.0, 1.0, 1.0, 1.0);
    channelOption:SetSize(frame:GetWidth(), 28)
    channelOption:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -70)
    channelOption.id = id
    channelOption.name = name
    channelOption.disabled = disabled
    channelOption.text = channelOption:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    channelOption.text:SetPoint("LEFT", channelOption, "LEFT", 7, 0)
    channelOption.text:SetText(name)
    channelOption.checkbox = CreateFrame("CheckButton", "partyPlanner-channel-option-checkbox-"..id, channelOption, "InterfaceOptionsCheckButtonTemplate")
    channelOption.checkbox:SetPoint("RIGHT", channelOption, "RIGHT", 0, 0)
    channelOption.checkbox:SetScript("OnClick", function(self)
        -- print("Clicked", self:GetChecked(), channelOption.id, channelOption.name)

        PartyPlannerSettings.channelSettings[channelOption.name].disabled = not self:GetChecked()
    end)
    channelOption.checkbox:SetChecked(not disabled)

    function channelOption:UpdateOption(id, name, disabled)
        channelOption.id = id
        channelOption.name = name
        channelOption.disabled = disabled
        channelOption.text:SetText(id..". "..name)
        channelOption.checkbox:SetChecked(not disabled)
        -- print("Updating", channelOption.id, channelOption.name, channelOption.disabled)
    end
    -- channelOption:Hide()
    return channelOption

end


function PartyPlanner.UI:CreateChannelOptions(parent)
    
    local channelOptionHeight = 28
    local channelOptionPadding = 6

    PartyPlanner.UI.channelOptions = {}

    local channelOptionsContainer = CreateFrame("FRAME", "partyPlanner-inputFieldContainer", parent, "BackdropTemplate")
    channelOptionsContainer:SetSize(315, 135)
    channelOptionsContainer:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -65)  -- Adjust position as needed
    channelOptionsContainer:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", 
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border", 
        tile = true, 
        tileSize = 24, 
        edgeSize = 8, 
        insets = { 
            left = 2, 
            right = 3, 
            top = 5, 
            bottom = 5 
        } 
    });
    channelOptionsContainer:SetBackdropColor(1.0, 1.0, 1.0, 1.0);


    local channelOptionsSF = CreateFrame("ScrollFrame", nil, channelOptionsContainer, "UIPanelScrollFrameTemplate")
    channelOptionsSF:SetPoint("TOPLEFT", 3, -7)
    channelOptionsSF:SetPoint("BOTTOMRIGHT", -27, 6)

    local scrollChild = CreateFrame("Frame")
    channelOptionsSF:SetScrollChild(scrollChild)
    scrollChild:SetWidth(channelOptionsSF:GetWidth()-5)
    scrollChild:SetHeight(1) 

    -- 

    for i = 1, PartyPlanner.DATA.MAX_CHANNELS, 1 do
        -- local id, name, disabled = channels[i], channels[i+1], channels[i+2]
        local channelOption = PartyPlanner.UI:CreateChannelOption(scrollChild, i, "Temp Channel Name "..i, true)
        channelOption:SetPoint("TOPLEFT", channelOptionPadding, -((i-1)*(channelOptionHeight-channelOptionPadding)))
        PartyPlanner.UI.channelOptions[i] = channelOption
    end

    
    local channelText = channelOptionsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    channelText:SetPoint("TOPLEFT", channelOptionsContainer, "TOPLEFT", 5, 12)
    channelText:SetText("Select channels to post to: ")

    local joinLFGButton = CreateFrame("BUTTON", "partyPlanner-joinLFGButton", channelOptionsContainer, "UIPanelButtonTemplate")
    joinLFGButton:SetSize(70, 20)
    joinLFGButton:SetPoint("BOTTOMRIGHT", channelOptionsContainer, "TOPRIGHT", 0, -5)
    joinLFGButton:SetText("Join LFG")
    joinLFGButton:SetScript("OnClick", function()
        JoinChannelByName("LookingForGroup")
        JoinChannelByName("lfg")
    end)
    PartyPlanner.UI.joinLFGButton = joinLFGButton

    return channelOptionsContainer
end


function PartyPlanner.UI:UpdateChannelOptions()
    if not PartyPlanner.UI:IsShown() then
        return
    end
    local channels = {GetChannelList()}
    local joinedLookingForGroup = false
    local joinedLFG = false
    for i = 1, #channels, 3 do
        local name = channels[i+1]
        if string.lower(name) == "lookingforgroup" then
            joinedLookingForGroup = true
        elseif string.lower(name) == "lfg" then
            joinedLFG = true
        end
    end
    local joinedAllChannels = joinedLookingForGroup and joinedLFG

    if joinedAllChannels then
        PartyPlanner.UI.joinLFGButton:Hide()
    else
        PartyPlanner.UI.joinLFGButton:Show()
    end

    -- for i = 1, #channels, 3 do
    --     local id, name, disabled = channels[i], channels[i+1], channels[i+2]
    --     if not disabled then
    --         print(id, name)
    --     end
    -- end

    local validChannels = {}

    for i = 1, #channels, 3 do
        local id, name, disabled = channels[i], channels[i+1], channels[i+2]
        local isValid = true
        for j = 1, #PartyPlanner.DATA.forbidenChannels, 1 do
            if string.lower(PartyPlanner.DATA.forbidenChannels[j]) == string.lower(name) then
                isValid = false
            end
        end

        if isValid then
            validChannels[#validChannels+1] = id
            validChannels[#validChannels+1] = name
            validChannels[#validChannels+1] = disabled

            -- print(id, name, disabled)
        end
    end



    local totChannels = #validChannels/3

    for i = 1, PartyPlanner.DATA.MAX_CHANNELS, 1 do
        local channelOption = PartyPlanner.UI.channelOptions[i]

        if i <= totChannels then
            local id, name = validChannels[i*3-2], validChannels[i*3-1]

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

            channelOption:UpdateOption(id, name, disabled)
            channelOption:Show()
        else
            channelOption:Hide()
        end
    end
    
end
