local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("BAG_OPEN")
frame:RegisterEvent("ITEM_LOCK_CHANGED")
frame:RegisterEvent("BANKFRAME_OPENED")
frame:RegisterEvent("BANKFRAME_CLOSED")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("MERCHANT_CLOSED")
frame:RegisterEvent("MERCHANT_UPDATE")
frame:RegisterEvent("CURSOR_CHANGED")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("ITEM_UNLOCKED")
frame:RegisterEvent("PLAYER_STARTED_MOVING")
frame:RegisterEvent("PLAYER_STOPPED_MOVING")

local loaded = false
local updateTimer = nil
local refreshTimer = nil
local refreshCount = 0
local MAX_REFRESH_COUNT = 10 -- Will refresh 10 times
local REFRESH_INTERVAL = 0.1 -- Every 0.1 seconds
local cursorRefreshTimer = nil
local CURSOR_REFRESH_DELAY = 0.2 -- Coalesce cursor-driven refreshes into one deferred pass
local scanningTooltip = CreateFrame("GameTooltip", "CommanderBagsScanningTooltip", nil, "GameTooltipTemplate")
scanningTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

local NUM_CONTAINER_FRAMES = 13 -- Maximum number of container frames

local function ResetItemColors()
    for i = 1, NUM_CONTAINER_FRAMES do
        local containerFrame = _G["ContainerFrame"..i]
        if containerFrame then
            for j = 1, containerFrame.size or 0 do
                local button = _G[containerFrame:GetName().."Item"..j]
                if button then
                    if button.icon then
                        button.icon:SetVertexColor(1, 1, 1, 1)
                    end
                    if button.IconBorder then
                        button.IconBorder:Hide()
                    end
                end
            end
        end
    end
end

local function IsConsumable(bagID, slot)
    scanningTooltip:ClearLines()
    scanningTooltip:SetBagItem(bagID, slot)
    
    -- Check first line for "Use:" or "Equip:"
    local firstLine = _G["CommanderBagsScanningTooltipTextLeft1"]
    if not firstLine then return false end
    
    for i = 2, scanningTooltip:NumLines() do
        local textLeft = _G["CommanderBagsScanningTooltipTextLeft" .. i]
        if textLeft then
            local text = textLeft:GetText()
            if text and text:find("^Use: ") then
                -- Check if it's not equipment (items with "Equip:" are not consumables)
                for j = i, scanningTooltip:NumLines() do
                    local equipText = _G["CommanderBagsScanningTooltipTextLeft" .. j]
                    if equipText and equipText:GetText() and equipText:GetText():find("^Equip: ") then
                        return false
                    end
                end
                return true
            end
        end
    end
    return false
end

local function UpdateItemColors()
    if not CommanderBagsDB.ColorCodeItems then 
        ResetItemColors()
        return 
    end
    
    -- For each container frame
    for i = 1, NUM_CONTAINER_FRAMES do
        local containerFrame = _G["ContainerFrame"..i]
        if containerFrame and containerFrame:IsShown() then
            local bagID = containerFrame:GetID()
            
            -- Update each item button in the container
            for j = 1, containerFrame.size or 0 do
                local button = _G[containerFrame:GetName().."Item"..j]
                if button then
                    -- Get the actual bag slot from the button
                    local slot = button:GetID()
                    local itemLink = C_Container.GetContainerItemLink(bagID, slot)
                    
                    if itemLink then
                        local _, _, rarity, _, _, itemType = C_Item.GetItemInfo(itemLink)
                        local isQuestItem = false
                        local isConsumable = IsConsumable(bagID, slot)
                        
                        -- Check if item is a quest item using tooltip scanning
                        scanningTooltip:ClearLines()
                        scanningTooltip:SetBagItem(bagID, slot)
                        
                        for i = 1, scanningTooltip:NumLines() do
                            local textLeft = _G["CommanderBagsScanningTooltipTextLeft" .. i]
                            if textLeft then
                                local text = textLeft:GetText()
                                if text and (text:find("Quest Item") or text:find("This Item Begins a Quest")) then
                                    isQuestItem = true
                                    break
                                end
                            end
                        end
                        
                        button.icon:SetVertexColor(1, 1, 1, 1)
                        
                        if button.IconBorder then
                            button.IconBorder:Show()
                            
                            if isQuestItem then
                                button.IconBorder:SetVertexColor(1, 0.8, 0, 1) -- Bright yellow
                                button.IconBorder:SetAlpha(1)
                            elseif rarity == 0 then -- Poor (Gray)
                                button.IconBorder:SetVertexColor(1, 0.1, 0.1, 1) -- Even brighter, more saturated red
                                button.IconBorder:SetAlpha(1)
                            elseif isConsumable then -- Consumable items
                                button.IconBorder:SetVertexColor(0, 0.8, 1, 1) -- Bright cyan
                                button.IconBorder:SetAlpha(1)
                            elseif rarity == 1 then -- Common (White)
                                button.IconBorder:Hide() -- Hide border for common items
                            elseif rarity then
                                local r, g, b = C_Item.GetItemQualityColor(rarity)
                                button.IconBorder:SetVertexColor(r, g, b, 1)
                                button.IconBorder:SetAlpha(1)
                            else
                                button.IconBorder:Hide() -- Item info not cached yet; refresh cycle will retry
                            end
                        end
                    else
                        if button.IconBorder then
                            button.IconBorder:Hide()
                        end
                        button.icon:SetVertexColor(1, 1, 1, 1)
                    end
                end
            end
        end
    end
end

local function StartRefreshWindow()
    if refreshTimer then
        refreshTimer:Cancel()
    end
    
    refreshCount = 0
    
    local function RefreshCycle()
        UpdateItemColors()
        refreshCount = refreshCount + 1
        
        if refreshCount < MAX_REFRESH_COUNT then
            refreshTimer = C_Timer.NewTimer(REFRESH_INTERVAL, RefreshCycle)
        else
            refreshTimer = nil
        end
    end
    
    RefreshCycle()
end

local function ScheduleUpdate()
    if updateTimer then
        updateTimer:Cancel()
    end

    updateTimer = C_Timer.NewTimer(0.1, function()
        StartRefreshWindow()
        updateTimer = nil
    end)
end

-- Cursor changes can fire many times per second while items are picked up and
-- dropped; restart a single short timer instead of running a full refresh burst
local function ScheduleCursorRefresh()
    if cursorRefreshTimer then
        cursorRefreshTimer:Cancel()
    end

    cursorRefreshTimer = C_Timer.NewTimer(CURSOR_REFRESH_DELAY, function()
        cursorRefreshTimer = nil
        UpdateItemColors()
    end)
end

local function OnUpdate()
    UpdateItemColors()
end

local function OnAwake()
    Commander.AddListener(COMMANDER_BAGS_EVENTS.UPDATE, OnUpdate)
    Commander.Notify(COMMANDER_BAGS_EVENTS.UPDATE)
end

local function OnDestroy() end

-- Refresh item colors after clicks; tooltip anchoring is left entirely to
-- Blizzard (ContainerFrameItemButton_CalculateItemTooltipAnchors) and
-- Commander_Tooltip
local function HookContainerItemButton(button)
    if button.isHooked then return end  -- Add flag to prevent double-hooking
    button.isHooked = true

    -- Post-hook so Blizzard's secure OnClick runs untainted
    button:HookScript("OnClick", function(self, ...)
        if loaded then
            StartRefreshWindow()
        end
    end)
end

-- Hook MerchantFrame functions
local function HookMerchantFrame()
    if MerchantFrame then
        -- Post-hook so Blizzard's own OnShow runs untainted
        MerchantFrame:HookScript("OnShow", function()
            if loaded then
                StartRefreshWindow()
            end
        end)
    end
end

-- Save only UIParent-relative coordinates. Storing frame:GetPoint() captured
-- Blizzard's container-to-container anchor chain (UpdateContainerFrameAnchors
-- anchors each bag to the previous one), and replaying it created anchor
-- cycles that made Blizzard's own SetPoint throw.
local function SaveBagPosition(frame)
    if not frame or not frame:GetName() then return end
    if not CommanderBagsDB.BagPositions then
        CommanderBagsDB.BagPositions = {}
    end

    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if left and bottom then
        CommanderBagsDB.BagPositions[frame:GetName()] = {
            left = left,
            bottom = bottom
        }
    end
end

-- Re-anchor one frame with a single point on UIParent; anchor cycles are
-- impossible when nothing is ever anchored to another container frame
local function ApplyBagPosition(frame)
    if not frame or not frame:GetName() then return end
    if not CommanderBagsDB.BagPositions then return end

    local pos = CommanderBagsDB.BagPositions[frame:GetName()]
    if pos and type(pos.left) == "number" and type(pos.bottom) == "number" then
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", pos.left, pos.bottom)
    end
end

-- Re-apply saved positions to every shown container frame; frames without a
-- saved entry keep Blizzard's default layout
local function ApplySavedBagPositions()
    for i = 1, NUM_CONTAINER_FRAMES do
        local frame = _G["ContainerFrame"..i]
        if frame and frame:IsShown() then
            ApplyBagPosition(frame)
        end
    end
end

-- Old saves stored point/relativeTo pairs that replayed Blizzard's
-- container-to-container anchors; they are poison, so drop anything that is
-- not the plain left/bottom format
local function DiscardLegacyBagPositions()
    if not CommanderBagsDB.BagPositions then return end
    for name, pos in pairs(CommanderBagsDB.BagPositions) do
        if type(pos) ~= "table" or type(pos.left) ~= "number" or type(pos.bottom) ~= "number"
            or pos.point or pos.relativeTo then
            CommanderBagsDB.BagPositions[name] = nil
        end
    end
end

local function OnBagDragStop(frame)
    frame:StopMovingOrSizing()
    -- StartMoving marks movable frames as user-placed; clear that so the
    -- client's layout cache does not fight the saved position
    frame:SetUserPlaced(false)
    SaveBagPosition(frame)
    ApplyBagPosition(frame)
end

-- Add function to fade bags
local function FadeBags(fade)
    for i = 1, NUM_CONTAINER_FRAMES do
        local bagFrame = _G["ContainerFrame"..i]
        if bagFrame and bagFrame:IsShown() then
            if fade then
                bagFrame:SetAlpha(0.5)
            else
                bagFrame:SetAlpha(1)
            end
        end
    end
end

-- Modify HookContainerFrame to make frames draggable
local function HookContainerFrame(frame)
    -- Make frame draggable
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    
    -- Set up drag functionality
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    
    frame:SetScript("OnDragStop", function(self)
        OnBagDragStop(self)
    end)

    -- Make title frame draggable (using ClickableTitleFrame instead of Name)
    local titleFrame = frame.ClickableTitleFrame
    if titleFrame then
        titleFrame:EnableMouse(true)
        titleFrame:RegisterForDrag("LeftButton")
        titleFrame:SetScript("OnDragStart", function()
            frame:StartMoving()
        end)
        titleFrame:SetScript("OnDragStop", function()
            OnBagDragStop(frame)
        end)
    end

    -- Also make portrait button draggable
    local portraitButton = _G[frame:GetName().."PortraitButton"]
    if portraitButton then
        portraitButton:EnableMouse(true)
        portraitButton:RegisterForDrag("LeftButton")
        portraitButton:SetScript("OnDragStart", function()
            frame:StartMoving()
        end)
        portraitButton:SetScript("OnDragStop", function()
            OnBagDragStop(frame)
        end)
    end

    -- Post-hook so Blizzard's own OnShow runs untainted
    frame:HookScript("OnShow", function(self)
        if loaded then
            StartRefreshWindow()
            -- Hook all item buttons in this container
            for j = 1, self.size or 0 do
                local button = _G[self:GetName().."Item"..j]
                if button then
                    HookContainerItemButton(button)
                end
            end
        end
    end)
end

-- Blizzard re-anchors every shown container frame on each bag open/close and
-- on resolution changes; running right after that pass keeps saved positions
-- in charge without fighting the default layout
hooksecurefunc("UpdateContainerFrameAnchors", ApplySavedBagPositions)

-- Add this new function
local function HookAllContainerFrames()
    for i = 1, NUM_CONTAINER_FRAMES do
        local frame = _G["ContainerFrame"..i]
        if frame and not frame.isHooked then  -- Add flag to prevent double-hooking
            HookContainerFrame(frame)
            frame.isHooked = true
        end
    end
end

-- Hook all container frames
HookAllContainerFrames()

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        DiscardLegacyBagPositions()
        OnAwake()
        loaded = true
        StartRefreshWindow()
        HookMerchantFrame()
        HookAllContainerFrames()
    elseif event == "PLAYER_LOGOUT" then
        OnDestroy()
    elseif loaded then
        if event == "PLAYER_STARTED_MOVING" and CommanderBagsDB.FadeBagsWhileMoving then
            FadeBags(true)
        elseif event == "PLAYER_STOPPED_MOVING" and CommanderBagsDB.FadeBagsWhileMoving then
            FadeBags(false)
        elseif event == "BAG_OPEN" then
            StartRefreshWindow()
            HookAllContainerFrames()
        elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
            StartRefreshWindow()
        elseif event == "CURSOR_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" or event == "ITEM_UNLOCKED" then
            ScheduleCursorRefresh()
        else
            ScheduleUpdate()
        end
    end
end)
