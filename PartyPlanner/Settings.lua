-- Create addon interface options tab for PartyPlanner settings
if not LibStub then error("PartyPlanner requires LibStub.") end

local LibDBIcon = LibStub("LibDBIcon-1.0")

function PartyPlanner:BuildAddonSettings()
    local panel = CreateFrame("Frame")
    panel.name = "PartyPlanner"               -- see panel fields
    InterfaceOptions_AddCategory(panel)  -- see InterfaceOptions API

    -- add widgets to the panel as desired
    local title = panel:CreateFontString("ARTWORK", nil, "GameFontNormalLarge")
    title:SetPoint("TOP")
    title:SetText("PartyPlanner")

    local subtitle = panel:CreateFontString("ARTWORK", nil, "GameFontHighlightSmall")
    subtitle:SetHeight(40)
    subtitle:SetPoint("TOPLEFT", 16, -32)
    subtitle:SetPoint("RIGHT", panel, -32, 0)
    subtitle:SetNonSpaceWrap(true)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetJustifyV("TOP")
    subtitle:SetText("PartyPlanner is a tool to help you post messages to find people for dungeons and raids.")

    local info = panel:CreateFontString("ARTWORK", nil, "GameFontNormal")
    info:SetHeight(40)
    info:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -8)
    info:SetPoint("RIGHT", panel, -32, 0)
    info:SetNonSpaceWrap(true)
    info:SetJustifyH("LEFT")
    info:SetJustifyV("TOP")
    info:SetText("You can always use /pp or /partyplanner to toggle the Party Planner main window.")

    local showMinimapButton = CreateFrame("CheckButton", "PartyPlannerShowMinimapButton", panel, "InterfaceOptionsCheckButtonTemplate")
    showMinimapButton:SetPoint("TOPLEFT", showSpellbookButton, "BOTTOMLEFT", 0, -8)
    showMinimapButton.text = showMinimapButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    showMinimapButton.text:SetPoint("LEFT", showMinimapButton, "RIGHT", 0, 3)
    showMinimapButton.text:SetText("Show PartyPlanner button on minimap")
    showMinimapButton.tooltipText = "Show PartyPlanner button on minimap"
    showMinimapButton:SetScript("OnClick", function(self)
        PartyPlannerSettings.miniMapIcon.hide = not self:GetChecked()
        LibDBIcon:Refresh("PartyPlanner", PartyPlannerSettings.miniMapIcon)
        -- PartyPlanner.MM:ToggleMinimapButton()
    end)
    showMinimapButton:SetChecked(not PartyPlannerSettings.miniMapIcon.hide)

end