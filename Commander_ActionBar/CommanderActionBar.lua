local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_STARTED_MOVING")
frame:RegisterEvent("PLAYER_STOPPED_MOVING")
local loaded = false

local backdrop

-- Frame names for the 2.5.5 (Anniversary) client; looked up by name so a missing
-- frame is skipped instead of truncating the list
local elementsToHide = {
    "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",
    "MainMenuBarTexture0", "MainMenuBarTexture1", "MainMenuBarTexture2", "MainMenuBarTexture3",
    "MainMenuMaxLevelBar0", "MainMenuMaxLevelBar1", "MainMenuMaxLevelBar2", "MainMenuMaxLevelBar3",
    "StatusTrackingBarManager",
    "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton", "QuestLogMicroButton",
    "GuildMicroButton", "WorldMapMicroButton", "SocialsMicroButton", "MainMenuMicroButton", "HelpMicroButton",
    "MainMenuBarBackpackButton", "MainMenuBarPerformanceBarFrame", "KeyRingButton",
    "StanceBar"
}

local function HideDefaults()
    for _, name in ipairs(elementsToHide) do
        local element = _G[name]
        if element then
            element:Hide()
        end
    end
    -- Page number and up/down arrows live on MainActionBar now
    if MainActionBar and MainActionBar.ActionBarPageNumber then
        MainActionBar.ActionBarPageNumber:Hide()
    end
    for i = 0, 3 do
        local bagButton = _G["CharacterBag" .. i .. "Slot"]
        if bagButton then
            bagButton:SetShown(CommanderActionBarDB.showBagButtons)
            if bagButton:IsShown() then
                bagButton:ClearAllPoints()
                bagButton:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -300, 8 + (i * 42))
            end
        end
    end
end

local function SetLockState()
    if not CommanderActionBarDB.locked then
        backdrop:SetMovable(true)
        backdrop:EnableMouse(true)
        backdrop:RegisterForDrag("LeftButton")
        backdrop:SetScript("OnDragStart", backdrop.StartMoving)
        backdrop:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
            CommanderActionBarDB.position = {point = point, relativePoint = relativePoint, xOfs = xOfs, yOfs = yOfs}
            Notify(COMMANDER_ACTIONBAR_EVENTS.UPDATE)
        end)
    else
        backdrop:SetMovable(false)
        backdrop:EnableMouse(false)
    end
end

local function CreateRTSBackdrop()
    if backdrop then return backdrop end
    
    backdrop = CreateFrame("Frame", "RTSActionBarBackdrop", UIParent, "BackdropTemplate")
    backdrop:SetFrameStrata("BACKGROUND")
    
    if CommanderActionBarDB.position and CommanderActionBarDB.position.point then
        backdrop:SetPoint(
            CommanderActionBarDB.position.point, 
            UIParent, 
            CommanderActionBarDB.position.relativePoint, 
            CommanderActionBarDB.position.xOfs, 
            CommanderActionBarDB.position.yOfs
        )
    else
        backdrop:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    
    backdrop:SetSize(274, 190)
    backdrop:SetBackdrop({
        bgFile = "Interface\\BankFrame\\Bank-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    backdrop:SetBackdropColor(.5, .5, .5, 1)
    backdrop:SetBackdropBorderColor(1, 1, 1, 1)
    SetLockState()

    return backdrop
end

local function MoveActionButtons()
    local buttonSize, spacing, buttonsPerRow = 32, 10, 6
    for i = 1, 24 do
        local button = i <= 12 and _G["ActionButton" .. i] or _G["MultiBarBottomLeftButton" .. (i - 12)]
        if button then
            button:ClearAllPoints()
            local row, col = math.ceil(i / buttonsPerRow), (i - 1) % buttonsPerRow + 1
            local xOffset, yOffset = (col - 1) * (buttonSize + spacing) + 13, (row - 1) * (buttonSize + spacing) + 14
            button:SetPoint("TOPLEFT", backdrop, "TOPLEFT", xOffset, -yOffset)
            button:Show()
            local pushedTexture = button:GetPushedTexture()
            if pushedTexture then pushedTexture:SetColorTexture(0, 1, 1, 0.3) end
        end
    end
end

local function MovePetBar()
    if PetActionBar and PetActionBar:IsShown() then
        PetActionBar:ClearAllPoints()
        PetActionBar:SetPoint("BOTTOM", backdrop, "TOP", 10, 5)
        PetActionBar:SetScale(0.7)
    end
end

local function OnUpdate()
    HideDefaults()
    MovePetBar()
    for i = 1, 120 do
        local button = _G["ActionButton" .. i]
        if button then button:Show() end
    end
    for i = 1, 12 do
        local button = _G["MultiBarBottomLeftButton" .. i]
        if button then button:Show() end
    end
end

-- Throttle so the hide/reposition work doesn't run every single frame
local UPDATE_INTERVAL = 0.5
local timeSinceUpdate = 0
local function OnUpdateThrottled(self, elapsed)
    timeSinceUpdate = timeSinceUpdate + elapsed
    if timeSinceUpdate < UPDATE_INTERVAL then return end
    timeSinceUpdate = 0
    OnUpdate()
end

local function OnAwake()
    CreateRTSBackdrop()
    MoveActionButtons()
    frame:SetScript("OnUpdate", OnUpdateThrottled)
    AddListener(COMMANDER_ACTIONBAR_EVENTS.UPDATE, SetLockState)
end

local function OnDestroy()
end

local function OnEvent(self, event)
    if event == "PLAYER_LOGIN" then
        OnAwake()
        loaded = true
    elseif event == "PLAYER_LOGOUT" then
        OnDestroy()
    elseif loaded then
        OnUpdate()
    end
end

frame:SetScript("OnEvent", OnEvent)