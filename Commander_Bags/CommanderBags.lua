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

local loaded = false
local updateTimer = nil
local refreshTimer = nil
local refreshCount = 0
local MAX_REFRESH_COUNT = 10 -- Will refresh 10 times
local REFRESH_INTERVAL = 0.1 -- Every 0.1 seconds
local scanningTooltip = CreateFrame("GameTooltip", "CommanderBagsScanningTooltip", nil, "GameTooltipTemplate")
scanningTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function ResetItemColors()
    for i = 1, NUM_CONTAINER_FRAMES do
        local containerFrame = _G["ContainerFrame"..i]
        if containerFrame then
            for j = 1, containerFrame.size do
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
            for j = 1, containerFrame.size do
                local button = _G[containerFrame:GetName().."Item"..j]
                if button then
                    -- Get the actual bag slot from the button
                    local slot = button:GetID()
                    local itemLink = C_Container.GetContainerItemLink(bagID, slot)
                    
                    if itemLink then
                        local _, _, rarity, _, _, itemType = GetItemInfo(itemLink)
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
                            else
                                local r, g, b = GetItemQualityColor(rarity)
                                button.IconBorder:SetVertexColor(r, g, b, 1)
                                button.IconBorder:SetAlpha(1)
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

local function OnUpdate()
    UpdateItemColors()
end

local function OnAwake()
    AddListener(COMMANDER_BAGS_EVENTS.UPDATE, OnUpdate)
    Notify(COMMANDER_BAGS_EVENTS.UPDATE)
end

local function OnDestroy() end

-- Hook ContainerFrameItem_OnClick to catch direct item interactions
local function HookContainerItemButton(button)
    if not button:GetScript("OnClick") then
        button:SetScript("OnClick", function(self, ...)
            if loaded then
                StartRefreshWindow()
            end
        end)
    else
        local originalOnClick = button:GetScript("OnClick")
        button:SetScript("OnClick", function(self, ...)
            originalOnClick(self, ...)
            if loaded then
                StartRefreshWindow()
            end
        end)
    end
end

-- Hook MerchantFrame functions
local function HookMerchantFrame()
    if MerchantFrame then
        if not MerchantFrame:GetScript("OnShow") then
            MerchantFrame:SetScript("OnShow", function()
                if loaded then
                    StartRefreshWindow()
                end
            end)
        else
            local originalOnShow = MerchantFrame:GetScript("OnShow")
            MerchantFrame:SetScript("OnShow", function(...)
                originalOnShow(...)
                if loaded then
                    StartRefreshWindow()
                end
            end)
        end
    end
end

-- Hook ContainerFrame_OnShow to catch when container frames are shown
local function HookContainerFrame(frame)
    if not frame:GetScript("OnShow") then
        frame:SetScript("OnShow", function()
            if loaded then
                StartRefreshWindow()
                -- Hook all item buttons in this container
                for j = 1, frame.size do
                    local button = _G[frame:GetName().."Item"..j]
                    if button then
                        HookContainerItemButton(button)
                    end
                end
            end
        end)
    else
        local originalOnShow = frame:GetScript("OnShow")
        frame:SetScript("OnShow", function(...)
            originalOnShow(...)
            if loaded then
                StartRefreshWindow()
                -- Hook all item buttons in this container
                for j = 1, frame.size do
                    local button = _G[frame:GetName().."Item"..j]
                    if button then
                        HookContainerItemButton(button)
                    end
                end
            end
        end)
    end
end

-- Hook all container frames
for i = 1, NUM_BAG_FRAMES do
    local frame = _G["ContainerFrame"..i]
    if frame then
        HookContainerFrame(frame)
    end
end

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        OnAwake()
        loaded = true
        StartRefreshWindow()
        HookMerchantFrame()
    elseif event == "PLAYER_LOGOUT" then
        OnDestroy()
    elseif loaded then
        if event == "BAG_OPEN" then
            StartRefreshWindow()
        elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
            StartRefreshWindow()
        elseif event == "CURSOR_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" or event == "ITEM_UNLOCKED" then
            StartRefreshWindow()
        else
            ScheduleUpdate()
        end
    end
end)

-- Hook the OpenBag function to catch when bags are opened
local originalOpenBag = OpenBag
OpenBag = function(bag, ...)
    originalOpenBag(bag, ...)
    if loaded then
        StartRefreshWindow()
    end
end
