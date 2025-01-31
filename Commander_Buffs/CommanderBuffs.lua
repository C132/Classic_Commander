local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
local loaded = false

local buffAnchor
local isDragging = false

local function CreateMoveableAnchor(name, parent)
    local anchor = CreateFrame("Button", name, parent)
    anchor:SetSize(20, 20)
    anchor:SetNormalTexture("Interface\\BUTTONS\\UI-Panel-SmallerButton-Up")
    anchor:SetPushedTexture("Interface\\BUTTONS\\UI-Panel-SmallerButton-Down")
    anchor:SetHighlightTexture("Interface\\BUTTONS\\UI-Panel-MinimizeButton-Highlight")
    anchor:Hide()

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
    end

    -- Update buffs per row
    BUFF_ACTUAL_DISPLAY = CommanderBuffsDB.BuffsPerRow
end

local function OnUpdate()
    UpdateBuffFrame()
end

local function OnAwake()
    InitializeFrames()
    AddListener(COMMANDER_BUFFS_EVENTS.UPDATE, OnUpdate)
    Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
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
