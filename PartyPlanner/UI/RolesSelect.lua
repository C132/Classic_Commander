
function PartyPlanner.UI:CreateRolesSelect(parent) 

    local rolesOptionsContainer = CreateFrame("FRAME", "partyPlanner-inputFieldContainer", parent, "BackdropTemplate")
    rolesOptionsContainer:SetSize(315, 40)
    rolesOptionsContainer:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -80)  -- Adjust position as needed
    rolesOptionsContainer:SetBackdrop({
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
    rolesOptionsContainer:SetBackdropColor(1.0, 1.0, 1.0, 1.0);
    -- rolesOptionsContainer:Hide()

    local roleText = rolesOptionsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    roleText:SetPoint("TOPLEFT", rolesOptionsContainer, "TOPLEFT", 5, 12)
    roleText:SetText("Select required roles: ")
    PartyPlanner.UI.rolesInfoText = roleText

    -- Check boxes for the 3 roles
    local roleCheckboxes = {}
    local roles = {"Tank", "Healer", "DPS"} --

    for i = 1, #roles do

        local roleContainer = CreateFrame("FRAME", "partyPlanner-role-container-"..roles[i], rolesOptionsContainer, "BackdropTemplate")
        roleContainer:SetSize(100, 28)
        roleContainer:SetPoint("LEFT", rolesOptionsContainer, "LEFT", 7+(i-1)*100, 0)

        roleContainer.checkbox = CreateFrame("CheckButton", "partyPlannerRoleCheckbox"..roles[i], roleContainer, "ChatConfigCheckButtonTemplate")
        roleContainer.checkbox:SetPoint("LEFT", roleContainer, "LEFT", 15, 0)
        roleContainer.checkbox:SetChecked(true)
        roleContainer.checkbox:SetScript("OnClick", function(self)
            if PartyPlanner.DATA.currentMode == "LFG" then
                PartyPlannerCharacterSettings.LFGroles[roles[i]] = self:GetChecked()
            end

            PartyPlanner.UI:UpdatePreviewText()
        end)
        
        local checkboxText = getglobal(roleContainer.checkbox:GetName() .. 'Text')
        checkboxText:SetText(roles[i]);
        checkboxText:SetPoint("LEFT", roleContainer.checkbox, "RIGHT", 5, 0)

        roleContainer.checkbox:SetHitRectInsets(0, 0, 0, 0)

        roleContainer.role = roles[i]

        roleCheckboxes[i] = roleContainer
    end

    PartyPlanner.UI.roleCheckboxes = roleCheckboxes

    return rolesOptionsContainer
end


function PartyPlanner.UI:UpdateRolesSelect() 
    if PartyPlanner.DATA.currentMode == "LFM" then
        PartyPlanner.UI.rolesInfoText:SetText("Select required roles: ")
        for i = 1, #PartyPlanner.UI.roleCheckboxes do
            PartyPlanner.UI.roleCheckboxes[i].checkbox:SetChecked(true)
        end
    else
        PartyPlanner.UI.rolesInfoText:SetText("Select your role:")
        for i = 1, #PartyPlanner.UI.roleCheckboxes do
            if PartyPlannerCharacterSettings.LFGroles[PartyPlanner.UI.roleCheckboxes[i].role] then
                PartyPlanner.UI.roleCheckboxes[i].checkbox:SetChecked(true)
            else
                PartyPlanner.UI.roleCheckboxes[i].checkbox:SetChecked(false)
            end
        end
    end
end