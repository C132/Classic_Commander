function PartyPlanner.UI:CreateMiniUI()

    PartyPlanner.MINI_UI = CreateFrame("FRAME", "partyPlanner-mini-ui", UIParent, "BasicFrameTemplate")
    PartyPlanner.MINI_UI:SetSize(130, 50)
    PartyPlanner.MINI_UI:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    PartyPlanner.MINI_UI:SetMovable(true)
    PartyPlanner.MINI_UI:EnableMouse(true)
    PartyPlanner.MINI_UI:RegisterForDrag("LeftButton")
    PartyPlanner.MINI_UI:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    PartyPlanner.MINI_UI:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)

    PartyPlanner.MINI_UI:Hide()

    -- PartyPlanner.MINI_UI.timer = nil

    -- local function updatetimer()
    --     print("Timer")
    --     PartyPlanner.DATA.timeSinceLastSend = PartyPlanner.DATA.timeSinceLastSend + 1
    --     print(PartyPlanner.DATA.timeSinceLastSend)
    -- end

    -- PartyPlanner.UI:SetScript("OnShow", function()
    --     if not PartyPlanner.MINI_UI.timer then
    --         PartyPlanner.MINI_UI.timer = CreateTimer(updatetimer, 1, true)
    --     end
    -- end)
    -- PartyPlanner.UI:SetScript("OnHide", function()
    --     if PartyPlanner.MINI_UI.timer then
    --         DestroyTimer(PartyPlanner.MINI_UI.timer)
    --         PartyPlanner.MINI_UI.timer = nil  -- Clear the timer handle
    --       end
    -- end)

    -- Same using C_Timer

    PartyPlanner.MINI_UI.timeText = PartyPlanner.MINI_UI:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    PartyPlanner.MINI_UI.timeText:SetPoint("LEFT", PartyPlanner.MINI_UI.TitleBg, "LEFT", 5, 0)
    PartyPlanner.MINI_UI.timeText:SetText("Party Planner")
    PartyPlanner.MINI_UI.timeText:SetFont("Fonts\\FRIZQT__.ttf", 11, "OUTLINE")




    PartyPlanner.MINI_UI.expandButton = CreateFrame("BUTTON", "partyPlanner-swap-mini-button", PartyPlanner.MINI_UI)
    PartyPlanner.MINI_UI.expandButton:SetSize(32, 32)
    PartyPlanner.MINI_UI.expandButton:SetPoint("TOPRIGHT", PartyPlanner.MINI_UI, "TOPRIGHT", -18, 5)
    PartyPlanner.MINI_UI.expandButton:SetNormalTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Up")
    PartyPlanner.MINI_UI.expandButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    PartyPlanner.MINI_UI.expandButton:SetPushedTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Down")
    PartyPlanner.MINI_UI.expandButton:SetScript("OnClick", function ()
        PartyPlanner.UI:ToggleUI()
    end)
    PartyPlanner.MINI_UI.expandButton:SetScript("OnEnter", function()
        GameTooltip:SetOwner(PartyPlanner.MINI_UI.expandButton, "ANCHOR_LEFT", 0, 0)
        GameTooltip:AddLine("Minimise Party Planner")
        GameTooltip:AddLine("You can still send messages with the mini UI")
        GameTooltip:Show()
    end)
    PartyPlanner.MINI_UI.expandButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local button = CreateFrame("BUTTON", "partyPlanner-SEND", PartyPlanner.MINI_UI, "UIPanelButtonTemplate")
    button:SetSize(120, 25)
    button:SetPoint("BOTTOM", PartyPlanner.MINI_UI, "BOTTOM", 0, 2)
    button:SetText("Send Message")
    button:SetScript("OnClick", function()
        PartyPlanner.UI:SendMessage()
    end)
end