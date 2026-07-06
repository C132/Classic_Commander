local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterUnitEvent("UNIT_AURA", "player")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
-- Edit Mode reapplies HUD frame positions on this client; re-apply ours after it does
frame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
local loaded = false

local buffAnchor
local isDragging = false

local function CreateMoveableAnchor(name, parent)
    local anchor = CreateFrame("Button", name, parent)
    anchor:SetSize(20, 20)
    anchor:SetNormalTexture("Interface\\Buttons\\WHITE8X8")
    anchor:SetPushedTexture("Interface\\Buttons\\WHITE8X8")
    anchor:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    anchor:Hide()
    
    -- Make the dot gray and semi-transparent
    local normal = anchor:GetNormalTexture()
    normal:SetVertexColor(0.6, 0.6, 0.6, 0.7)
    local pushed = anchor:GetPushedTexture()
    pushed:SetVertexColor(0.5, 0.5, 0.5, 0.8)
    local highlight = anchor:GetHighlightTexture()
    highlight:SetVertexColor(0.8, 0.8, 0.8, 0.5)

    -- Create settings button next to the anchor
    local settingsButton = CreateFrame("Button", name.."Settings", parent)
    settingsButton:SetSize(20, 20)
    settingsButton:SetNormalTexture("Interface\\BUTTONS\\UI-OptionsButton")
    settingsButton:SetPushedTexture("Interface\\BUTTONS\\UI-OptionsButton")
    settingsButton:SetHighlightTexture("Interface\\BUTTONS\\UI-Panel-MinimizeButton-Highlight")
    settingsButton:SetPoint("RIGHT", anchor, "LEFT", -2, 0)
    settingsButton:Hide()

    -- Settings button click handler
    settingsButton:SetScript("OnClick", function()
        -- Resolved through the module registry (Commander.RegisterModule)
        Commander.OpenModuleSettings("Buffs")
    end)

    anchor:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self:GetParent():StartMoving()
            isDragging = true
        end
    end)

    anchor:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            self:GetParent():StopMovingOrSizing()
            isDragging = false
            
            -- Save position with validation
            local point, _, _, xOfs, yOfs = self:GetParent():GetPoint(1)
            if point and type(point) == "string" then
                CommanderBuffsDB.BuffFramePoint = point
                CommanderBuffsDB.BuffFrameX = xOfs or -205
                CommanderBuffsDB.BuffFrameY = yOfs or -13
            end
        end
    end)

    -- Store settings button reference in anchor for visibility control
    anchor.settingsButton = settingsButton
    return anchor
end

local function InitializeFrames()
    -- Make buff frame moveable
    BuffFrame:SetMovable(true)
    BuffFrame:SetClampedToScreen(true)
    
    -- Create anchor button
    buffAnchor = CreateMoveableAnchor("BuffFrameAnchor", BuffFrame)
    buffAnchor:SetPoint("BOTTOMRIGHT", BuffFrame, "TOPRIGHT", 0, 0)
end

local function UpdateBuffFrame()
    BuffFrame:Show()

    -- Update position with validation
    BuffFrame:ClearAllPoints()
    
    -- Ensure we have valid point data
    local point = CommanderBuffsDB.BuffFramePoint
    if not point or type(point) ~= "string" then
        point = "TOPRIGHT"  -- Default if invalid
        CommanderBuffsDB.BuffFramePoint = point
    end
    
    local x = CommanderBuffsDB.BuffFrameX or -205  -- Default if nil
    local y = CommanderBuffsDB.BuffFrameY or -13   -- Default if nil
    
    -- Set position with validated values
    BuffFrame:SetPoint(point, UIParent, point, x, y)

    -- Update scale
    BuffFrame:SetScale(CommanderBuffsDB.BuffScale or 1.0)

    -- Show/hide anchor based on lock status and combat
    local showAnchor = not CommanderBuffsDB.LockBuffFrames and 
        (not InCombatLockdown() or CommanderBuffsDB.ShowAnchorInCombat)
    
    if buffAnchor then
        buffAnchor:SetShown(showAnchor)
        buffAnchor.settingsButton:SetShown(showAnchor)
    end

    -- Update buffs per row (BUFF_ACTUAL_DISPLAY is gone; the modern BuffFrame
    -- lays out via AuraContainer.iconStride, normally driven by Edit Mode)
    if BuffFrame.AuraContainer then
        BuffFrame.AuraContainer.iconStride = CommanderBuffsDB.BuffsPerRow
        if BuffFrame.auraFrames then
            BuffFrame:UpdateGridLayout()
        end
    end
end

local function OnUpdate()
    UpdateBuffFrame()
end

local function OnAwake()
    InitializeFrames()
    Commander.AddListener(COMMANDER_BUFFS_EVENTS.UPDATE, OnUpdate)
    Commander.Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
end

local function OnDestroy() end

local function OnEvent(self, event, ...)
    if event == "PLAYER_LOGIN" then
        OnAwake()
        loaded = true
    elseif event == "PLAYER_LOGOUT" then
        OnDestroy()
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        if loaded then
            OnUpdate()
        end
    elseif loaded then
        OnUpdate()
    end
end

frame:SetScript("OnEvent", OnEvent)
