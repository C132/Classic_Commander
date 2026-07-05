local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("PLAYER_STARTED_MOVING")
frame:RegisterEvent("PLAYER_STOPPED_MOVING")

local function SaveBagPosition(bagID)
    local bagFrame = _G["ContainerFrame"..(bagID + 1)]
    if bagFrame then
        local point, _, relativePoint, xOfs, yOfs = bagFrame:GetPoint()
        Config.BagPositions = Config.BagPositions or {}
        Config.BagPositions[bagID] = {point = point, relativePoint = relativePoint, xOfs = xOfs, yOfs = yOfs}
    end
end

local function LoadBagPosition(bagID)
    local bagFrame = _G["ContainerFrame"..(bagID + 1)]
    if bagFrame and Config.BagPositions and Config.BagPositions[bagID] then
        local pos = Config.BagPositions[bagID]
        bagFrame:ClearAllPoints()
        if pos.point and pos.relativePoint and pos.xOfs and pos.yOfs then
            bagFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.xOfs, pos.yOfs)
        else
            -- Set a default position if saved position is incomplete
            bagFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    end
end

local function SetupBag(bagID)
    local bagFrame = _G["ContainerFrame"..(bagID + 1)]
    if bagFrame then
        bagFrame:SetMovable(true)
        bagFrame:EnableMouse(true)
        bagFrame:RegisterForDrag("LeftButton")
        bagFrame:SetScript("OnDragStart", bagFrame.StartMoving)
        bagFrame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            SaveBagPosition(bagID)
        end)
        LoadBagPosition(bagID)

        -- Make the title frame draggable
        local titleFrame = _G[bagFrame:GetName().."Name"]
        if titleFrame then
            titleFrame:EnableMouse(true)
            titleFrame:SetScript("OnMouseDown", function() 
                bagFrame:StartMoving() 
            end)
            titleFrame:SetScript("OnMouseUp", function()
                bagFrame:StopMovingOrSizing()
                SaveBagPosition(bagID)
            end)
        end
    end
end

local function FadeBags(fade)
    for i = 0, 4 do
        local bagFrame = _G["ContainerFrame"..(i + 1)]
        if bagFrame and bagFrame:IsShown() then
            if fade then
                bagFrame:SetAlpha(0.5)
            else
                bagFrame:SetAlpha(1)
            end
        end
    end
end

local function OnEvent(self, event, ...)
    if event == "ADDON_LOADED" and ... == "MyClassicAddon" then
        for i = 0, 4 do
            SetupBag(i)
        end
    elseif event == "PLAYER_LOGOUT" then
        for i = 0, 4 do
            SaveBagPosition(i)
        end
    elseif event == "BAG_UPDATE" then
        local bagID = ...
        if bagID >= 0 and bagID <= 4 then
            C_Timer.After(0.1, function() 
                LoadBagPosition(bagID)
            end)
        end
    elseif event == "PLAYER_STARTED_MOVING" and Config.FadeBagsWhileMoving then
        FadeBags(true)
    elseif event == "PLAYER_STOPPED_MOVING" and Config.FadeBagsWhileMoving then
        FadeBags(false)
    end
end

frame:SetScript("OnEvent", OnEvent)

-- Hook ToggleBackpack to ensure positions are applied
local originalToggleBackpack = ToggleBackpack
ToggleBackpack = function()
    originalToggleBackpack()
    C_Timer.After(0.1, function()
        for i = 0, 4 do
            LoadBagPosition(i)
        end
    end)
end

-- Fix tooltip anchor
local function FixTooltipAnchor(self)
--    if GameTooltip:IsOwned(self) then
--        GameTooltip:ClearAllPoints()
--        GameTooltip:SetPoint(UIParent:GetCenter() > self:GetCenter() and "BOTTOMRIGHT" or "BOTTOMLEFT", self, "TOPRIGHT")
--    end
end

hooksecurefunc("ContainerFrameItemButton_OnEnter", FixTooltipAnchor)

local originalUpdateContainerFrameAnchors = UpdateContainerFrameAnchors
UpdateContainerFrameAnchors = function(...)
    -- Only clear points for regular bag frames (1-5), not bank frames (6+)
    for i = 1, 5 do
        local frame = _G["ContainerFrame"..i]
        if frame then
            frame:ClearAllPoints()
        end
    end
    originalUpdateContainerFrameAnchors(...)
    C_Timer.After(0, function()
        for i = 0, 4 do
            LoadBagPosition(i)
        end
    end)
end

-- Listen for changes to the FadeBagsWhileMoving setting
AddListener(MY_CLASSIC_ADDON_EVENTS.FADE_BAGS_WHILE_MOVING_CHANGED, function()
    if Config.FadeBagsWhileMoving then
        if IsPlayerMoving() then
            FadeBags(true)
        else
            FadeBags(false)
        end
    else
        FadeBags(false)
    end
end)
