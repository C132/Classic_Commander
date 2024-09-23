function PartyPlanner.UI:CreateInputField(parent)

    local inputFieldContainer = CreateFrame("FRAME", "partyPlanner-inputFieldContainer", parent, "BackdropTemplate")
    inputFieldContainer:SetSize(315, 32)
    inputFieldContainer:SetBackdrop({
        -- bgFile = "Interface\\AdventureMap\\AdventureMapParchmentTile", 
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 24,
        edgeSize = 24,
        insets = {
            left = 5,
            right = 5,
            top = 2,
            bottom = 2
        }
    })
    inputFieldContainer:SetBackdropColor(1.0, 1.0, 1.0, 1.0);
    
    local editBoxText = inputFieldContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editBoxText:SetPoint("TOPLEFT", inputFieldContainer, "TOPLEFT", 5, 17)
    editBoxText:SetText("Customise message: ")

    local resetDefaultText = CreateFrame("BUTTON", "partyPlanner-reset-default", inputFieldContainer)
    resetDefaultText:SetSize(12, 12)
    resetDefaultText:SetPoint("LEFT", editBoxText, "RIGHT", 5, 0)
    resetDefaultText:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
    
    resetDefaultText:SetScript("OnClick", function ()
        if (PartyPlanner.DATA.currentMode == "LFG") then
            PartyPlannerSettings.LFGmessage = PartyPlanner.DATA.defaultLFGMessage
        else
            PartyPlannerSettings.LFMmessage = PartyPlanner.DATA.defaultLFMMessage
        end
        PartyPlanner.UI:UpdateInputField()
        PartyPlanner.UI.editBox:ClearFocus()
        PartyPlanner.UI:UpdatePreviewText()
    end)

    resetDefaultText:SetScript("OnEnter", function()
        GameTooltip:SetOwner(resetDefaultText, "ANCHOR_LEFT", 0, 0)
        GameTooltip:AddLine("Reset to default text")
        GameTooltip:Show()
    end)
    resetDefaultText:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local editBoxInfo = CreateFrame("BUTTON", "partyPlanner-reset-default", inputFieldContainer)
    editBoxInfo:SetSize(16, 16)
    editBoxInfo:SetPoint("LEFT", resetDefaultText, "RIGHT", 5, 0)
    editBoxInfo:SetNormalTexture("Interface\\Buttons\\AdventureGuideMicrobuttonAlert")

    editBoxInfo:SetScript("OnEnter", function()
        GameTooltip:SetOwner(editBoxInfo, "ANCHOR_LEFT", 0, 0)
        GameTooltip:AddLine("Message formatting rules, ")
        GameTooltip:AddLine("use these to customise your message:")
        GameTooltip:AddLine("%n - Remaining player count needed")
        GameTooltip:AddLine("%i - Instance name or abbreviation")
        
        if (PartyPlanner.DATA.currentMode == "LFG") then
            GameTooltip:AddLine("%r - Your roles")
            GameTooltip:AddLine("%l - Your level")
            GameTooltip:AddLine("%c - Your class")
        else
            GameTooltip:AddLine("%r - Required roles")
        end
        
        -- GameTooltip:AddLine("%n - Remaining player count needed")

        GameTooltip:Show()
    end)
    editBoxInfo:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local editBox = PartyPlanner.UI:CreateEditBox(inputFieldContainer)
    
    PartyPlanner.UI.editBox = editBox
    PartyPlanner.UI:UpdateInputField()
    -- When a character changes
    editBox:SetScript("OnTextChanged", function(self)
        local message = PartyPlanner.UI.editBox:GetText()
        
        if (PartyPlanner.DATA.currentMode == "LFG") then
            PartyPlannerSettings.LFGmessage = message
        else
            PartyPlannerSettings.LFMmessage = message
        end
        PartyPlanner.UI:UpdatePreviewText()
    end)

    editBox:SetScript("OnEnterPressed", function(self) 
        PartyPlanner.UI.editBox:ClearFocus() 
        local message = PartyPlanner.UI.editBox:GetText()
        if (PartyPlanner.DATA.currentMode == "LFG") then
            PartyPlannerSettings.LFGmessage = message
        else
            PartyPlannerSettings.LFMmessage = message
        end
        PartyPlanner.UI:UpdatePreviewText()
    end)

    return inputFieldContainer
end

function PartyPlanner.UI:UpdateInputField()
    if (PartyPlanner.DATA.currentMode == "LFG") then
        PartyPlanner.UI.editBox:SetText(PartyPlannerSettings.LFGmessage)
    else
        PartyPlanner.UI.editBox:SetText(PartyPlannerSettings.LFMmessage)
    end
end