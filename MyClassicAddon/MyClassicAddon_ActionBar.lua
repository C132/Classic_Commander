local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

local backdrop
local savedPosition = {}

local function HideDefaults()
    -- Look elements up by name; several of these no longer exist on the 2.5.5
    -- client (StanceBarFrame is now StanceBar, the old XP bar textures are gone)
    local elementsToHide = {
        "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",
        "MainMenuBarTexture0", "MainMenuBarTexture1", "MainMenuBarTexture2", "MainMenuBarTexture3",
        "MainMenuMaxLevelBar0", "MainMenuMaxLevelBar1", "MainMenuMaxLevelBar2", "MainMenuMaxLevelBar3",
        "MainMenuXPBarTexture0", "MainMenuXPBarTexture1", "MainMenuXPBarTexture2", "MainMenuXPBarTexture3",
        "ActionBarUpButton", "ActionBarDownButton", "MainMenuBarPageNumber",
        "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton", "QuestLogMicroButton",
        "GuildMicroButton", "WorldMapMicroButton", "MainMenuMicroButton", "HelpMicroButton",
        "MainMenuBarBackpackButton", "MainMenuBarPerformanceBarFrame", "KeyRingButton",
        "StanceBar", "MainMenuExpBar"
    }
    for _, elementName in ipairs(elementsToHide) do
        local element = _G[elementName]
        if element then
            element:Hide()
        end
    end
    for i = 0, 3 do
        local bagButton = _G["CharacterBag" .. i .. "Slot"]
        if bagButton then
            bagButton:SetShown(Config.ShowBagButtons)
            if bagButton:IsShown() then
                bagButton:ClearAllPoints()
                bagButton:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -300, 8 + (i * 42))
            end
        end
    end
end

local function SetLockState()
    if Config.UnlockActionBar then
        backdrop:SetMovable(true)
        backdrop:EnableMouse(true)
        backdrop:RegisterForDrag("LeftButton")
        backdrop:SetScript("OnDragStart", backdrop.StartMoving)
        backdrop:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
            Config.ActionBarPosition = {point = point, relativePoint = relativePoint, xOfs = xOfs, yOfs = yOfs}
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
    
    if Config.ActionBarPosition and Config.ActionBarPosition.point then
        backdrop:SetPoint(Config.ActionBarPosition.point, UIParent, Config.ActionBarPosition.relativePoint, Config.ActionBarPosition.xOfs, Config.ActionBarPosition.yOfs)
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
        button:ClearAllPoints()
        local row, col = math.ceil(i / buttonsPerRow), (i - 1) % buttonsPerRow + 1
        local xOffset, yOffset = (col - 1) * (buttonSize + spacing) + 13, (row - 1) * (buttonSize + spacing) + 14
        button:SetPoint("TOPLEFT", backdrop, "TOPLEFT", xOffset, -yOffset)
        button:Show()
        local pushedTexture = button:GetPushedTexture()
        if pushedTexture then pushedTexture:SetColorTexture(0, 1, 1, 0.3) end
    end
end

local function MovePetBar()
    -- PetActionBarFrame was renamed to PetActionBar on the 2.5.5 client
    if PetActionBar and PetActionBar:IsShown() then
        PetActionBar:ClearAllPoints()
        PetActionBar:SetPoint("BOTTOM", backdrop, "TOP", 10, 5)
        PetActionBar:SetScale(0.7)
    end
end

local updateElapsed = 0
local function OnUpdate(self, elapsed)
    -- Throttle: hiding/re-anchoring the default UI every single frame is wasteful
    updateElapsed = updateElapsed + (elapsed or 0)
    if updateElapsed < 0.25 then return end
    updateElapsed = 0
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

local function OnStart()
    CreateRTSBackdrop()
    MoveActionButtons()
    frame:SetScript("OnUpdate", OnUpdate)
    AddListener(MY_CLASSIC_ADDON_EVENTS.ACTIONBAR_UNLOCKED, SetLockState)
end

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" and ... == "MyClassicAddon" then
        Config = Config or {}
        Config.ActionBarPosition = Config.ActionBarPosition or {}
    elseif event == "PLAYER_LOGOUT" then
        -- Position is now saved when dragging stops, so we don't need to save it here
    elseif event == "PLAYER_ENTERING_WORLD" then
        OnStart()
    end
end)