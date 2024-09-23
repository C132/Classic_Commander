
-- Create addon interface options tab for PartyPlanner settings
if not LibStub then error("PartyPlanner requires LibStub.") end

local LibDBIcon = LibStub("LibDBIcon-1.0")
local LDB = LibStub("LibDataBroker-1.1"):NewDataObject("PartyPlanner", {
    type = "launcher",
    icon = "Interface\\Icons\\Spell_Holy_PrayerofSpirit",
    OnClick = function(self, button)
        PartyPlanner.UI:ToggleUI()
    end,
    OnTooltipShow = function(tooltip)
        tooltip:SetText("Party Planner")
    end,
})


function PartyPlanner.UI:BuildShowButtons()
    -- Minimap icon
    LibDBIcon:Register("PartyPlanner", LDB, PartyPlannerSettings.miniMapIcon)
end

function PartyPlanner.UI:BuildFrameDecorations()
    PartyPlanner.UI.characterPortrait = CreateFrame("FRAME", "partyPlanner-character-portrait", PartyPlanner.UI)
    PartyPlanner.UI.characterPortrait:SetSize(64, 64)
    PartyPlanner.UI.characterPortrait:SetPoint("CENTER", PartyPlanner.UI, "TOPLEFT", 25, -21)
    PartyPlanner.UI.characterPortrait.texture = PartyPlanner.UI.characterPortrait:CreateTexture(nil,'ARTWORK')
    PartyPlanner.UI.characterPortrait.texture:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMaskSmall")
    PartyPlanner.UI.characterPortrait.texture:SetAllPoints()

    PartyPlanner.UI.characterPortrait.border = CreateFrame("FRAME", "partyPlanner-character-portrait-border", PartyPlanner.UI.characterPortrait)
    PartyPlanner.UI.characterPortrait.border:SetSize(63*1.28, 63*1.28)
    PartyPlanner.UI.characterPortrait.border:SetPoint("TOPLEFT", PartyPlanner.UI.characterPortrait, "TOPLEFT", -7.5, 1)
    PartyPlanner.UI.characterPortrait.border.texture = PartyPlanner.UI.characterPortrait.border:CreateTexture(nil,'ARTWORK')
    PartyPlanner.UI.characterPortrait.border.texture:SetTexture("Interface\\FrameGeneral\\UI-Frame")
    PartyPlanner.UI.characterPortrait.border.texture:SetAllPoints()
    PartyPlanner.UI.characterPortrait.border.texture:SetTexCoord(0, 0.625, 0, 0.625)   

    PartyPlanner.UI.title = PartyPlanner.UI:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    PartyPlanner.UI.title:SetPoint("LEFT", PartyPlanner.UI.TitleBg, "LEFT", 60, 0)
    PartyPlanner.UI.title:SetText("Party Planner")
    PartyPlanner.UI.title:SetFont("Fonts\\FRIZQT__.ttf", 11, "OUTLINE")

    PartyPlanner.UI.swapMiniButton = CreateFrame("BUTTON", "partyPlanner-swap-mini-button", PartyPlanner.UI)
    PartyPlanner.UI.swapMiniButton:SetSize(32, 32)
    PartyPlanner.UI.swapMiniButton:SetPoint("TOPRIGHT", PartyPlanner.UI, "TOPRIGHT", -18, 5)
    PartyPlanner.UI.swapMiniButton:SetNormalTexture("Interface\\Buttons\\UI-Panel-SmallerButton-Up")
    PartyPlanner.UI.swapMiniButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    PartyPlanner.UI.swapMiniButton:SetPushedTexture("Interface\\Buttons\\UI-Panel-SmallerButton-Down")
    PartyPlanner.UI.swapMiniButton:SetScript("OnClick", function ()
        PartyPlanner.UI:ToggleUI()
        PartyPlanner.MINI_UI:Show()
    end)
    PartyPlanner.UI.swapMiniButton:SetScript("OnEnter", function()
        GameTooltip:SetOwner(PartyPlanner.UI.swapMiniButton, "ANCHOR_LEFT", 0, 0)
        GameTooltip:AddLine("Minimise Party Planner")
        GameTooltip:AddLine("You can still send messages with the mini UI")
        GameTooltip:Show()
    end)
    PartyPlanner.UI.swapMiniButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    PartyPlanner.UI.swapMiniButton:Hide()


    -- PartyPlanner.UI.topBanner = PartyPlanner.UI:CreateTexture(nil,'ARTWORK')
    -- PartyPlanner.UI.topBanner:SetHorizTile(true)
    -- PartyPlanner.UI.topBanner:SetTexture("Interface\\COMMON\\UI-Goldborder-_tile", "REPEAT", "CLAMP", "LINEAR")
    -- PartyPlanner.UI.topBanner:SetSize(855, 64)
    -- PartyPlanner.UI.topBanner:SetPoint("TOP", PartyPlanner.UI, "TOP", -1, -23)
end

function PartyPlanner.UI:CreateTabManager()
    return {
        infoTabButtons={},
        infoTabs={},
        selectedTab="default",
        Select = function (self, tabName)
            if self.selectedTab == tabName then
                return
            end
            -- print("Selecting tab "..tabName)
            for k, v in pairs(self.infoTabs) do
                if k == tabName then
                    v:Show()
                    if self.infoTabButtons[k] ~= nil then
                        self.infoTabButtons[k]:SetSelected(true)
                    end

                else
                    v:Hide()
                    if self.infoTabButtons[k] ~= nil then
                        self.infoTabButtons[k]:SetSelected(false)
                    end
                end
            end
            self.selectedTab = tabName
        end,
        CreateTabButton = function(self, tabName, parent, tabSelectedText, tabDeselectedText)
            local tabButton = CreateFrame("BUTTON", "partyPlanner-tab-button-"..#self.infoTabButtons+1, parent, "UIPanelButtonTemplate")
            tabButton:SetSize(120, 20)
            tabButton.tabName = tabName
            tabButton.selected = false
            tabButton:SetText(tabDeselectedText)
            tabButton.highlightTexture = tabButton:CreateTexture(nil,'ARTWORK')
            tabButton.highlightTexture:SetTexture("Interface\\UNITPOWERBARALT\\MetalBronze_Horizontal_Frame")
            tabButton.highlightTexture:SetSize(154, 35)
            tabButton.highlightTexture:SetPoint("CENTER", 0, 0)
            tabButton.highlightTexture:SetVertexColor(1.0, 1.0, 1.0, 1.0)
            tabButton.highlightTexture:Hide()
            tabButton:SetScript("OnClick", function()
                if tabButton.selected then
                    self:Select("default")
                    return
                end
                self:Select(tabButton.tabName)
            end)
            tabButton.SetSelected = function(self, selected)
                if selected then
                    self.selected = true
                    self:SetText(tabDeselectedText)
                    self.highlightTexture:Show()
                else
                    self.selected = false
                    self:SetText(tabSelectedText)
                    self.highlightTexture:Hide()
                end
            end
            return tabButton
        end,
        Register = function(self, tabName, tabButton, tabFrame)
            self.infoTabButtons[tabName] = tabButton
            self.infoTabs[tabName] = tabFrame
        end
    }
end

function PartyPlanner.UI:CreateEditBox(frame)
    -- local scroll  = CreateFrame("ScrollFrame", nil, frame, "ScrollFrameTemplate")
    -- scroll:SetSize(frame:GetWidth() - 20, frame:GetHeight() - 25)
    -- scroll:SetPoint("TOPLEFT", frame, 12, -5)
    -- scroll:SetPoint("BOTTOMRIGHT", frame, -10, 5)

    local eb = CreateFrame('EditBox', nil, frame)
    -- scroll:SetScrollChild(eb)
    -- eb:SetSize(frame:GetWidth() - 25, frame:GetHeight())
    eb:SetPoint("TOPLEFT", frame, 15, 0)
    eb:SetPoint("BOTTOMRIGHT", frame, -15, 0)
    eb:EnableMouse(true)
    eb:SetAutoFocus(false)
    eb:SetMultiLine(false)
    eb:SetFontObject(GameTooltipText)
    eb:SetMaxLetters(999999)

    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return eb
end