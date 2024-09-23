
function PartyPlanner.UI:CreatePreviewField(parent)
    
    local previewTextContainer = CreateFrame("FRAME", "partyPlanner-preview-text-container", parent)
    previewTextContainer:SetSize(315, 32)

    local previewTextDynamic = PartyPlanner.UI:CreateEditBox(previewTextContainer)    
    PartyPlanner.UI.previewTextDynamic = previewTextDynamic
    previewTextDynamic:SetMultiLine(true)
    previewTextDynamic:SetScript("OnTextChanged", function(self)
        PartyPlanner.UI.previewTextDynamic:ClearFocus() 
        PartyPlanner.UI:UpdatePreviewText()
    end)
    previewTextDynamic:SetScript("OnEnterPressed", function(self)
        PartyPlanner.UI.previewTextDynamic:ClearFocus() 
        PartyPlanner.UI:UpdatePreviewText()
    end)

    local previewText = previewTextContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    previewText:SetPoint("TOPLEFT", previewTextContainer, "TOPLEFT", 5, 17)
    previewText:SetText("Preview: ")

    local useAbrevButton = CreateFrame("BUTTON", "partyPlanner-reset-default", previewTextContainer)
    useAbrevButton:SetSize(24, 24)
    useAbrevButton:SetPoint("LEFT", previewText, "RIGHT", 5, 0)
    useAbrevButton.UpdateTexture = function (self)
        if PartyPlannerSettings.useAbreviation then
            self:SetNormalTexture("Interface\\Buttons\\UI-Panel-HideButton-Up")
        else
            self:SetNormalTexture("Interface\\Buttons\\UI-Panel-ExpandButton-Up")
        end
    end
    useAbrevButton:UpdateTexture()
    useAbrevButton:SetScript("OnClick", function ()
        PartyPlannerSettings.useAbreviation = not PartyPlannerSettings.useAbreviation
        useAbrevButton:UpdateTexture()
        PartyPlanner.UI:UpdatePreviewText()
    end)

    useAbrevButton:SetScript("OnEnter", function()
        GameTooltip:SetOwner(useAbrevButton, "ANCHOR_LEFT", 0, 0)
        GameTooltip:AddLine("Toggle instance abbreviation or full name")
        GameTooltip:Show()
    end)
    useAbrevButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return previewTextContainer
end

function PartyPlanner.UI:UpdatePreviewField()

    PartyPlanner.UI.previewTextDynamic:SetText(PartyPlanner.DATA.currentMessage)

    return true
end