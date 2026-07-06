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
-- impossible when nothing is ever anchored to another container frame. pcall
-- so a residual bad anchor state can never wedge the whole repair loop.
local function ApplyBagPosition(frame)
    if not frame or not frame:GetName() then return end
    if not CommanderBagsDB.BagPositions then return end

    local pos = CommanderBagsDB.BagPositions[frame:GetName()]
    if pos and type(pos.left) == "number" and type(pos.bottom) == "number" then
        pcall(frame.ClearAllPoints, frame)
        pcall(frame.SetPoint, frame, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", pos.left, pos.bottom)
    end
end

-- Re-apply saved positions to every shown container frame; frames without a
-- saved entry keep Blizzard's default layout. Frames being actively dragged
-- are skipped so this hook cannot yank a bag out from under the cursor when
-- another bag opens or closes mid-drag.
local function ApplySavedBagPositions()
    for i = 1, NUM_CONTAINER_FRAMES do
        local frame = _G["ContainerFrame"..i]
        if frame and frame:IsShown() and not frame.cbDrag then
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

-- Manual UIParent-relative dragging. StartMoving/StopMovingOrSizing is never
-- used: StartMoving re-anchors the frame into the SCREEN's anchor family (and
-- flags it user-placed), and a screen-rooted container frame makes Blizzard's
-- own bare SetPoint in UpdateContainerFrameAnchors throw "SetPoint would
-- result in anchor family connection". Moving the frame ourselves with a
-- single UIParent point keeps every container frame in UIParent's anchor
-- family at every instant of the drag, so that error is structurally
-- impossible. Never call SetUserPlaced here either -- the manual drag must not
-- involve the client's layout cache at all.
local function DragTick(frame)
    local d = frame.cbDrag
    if not d then return end
    local cx, cy = GetCursorPosition()
    local newLeft = d.left0 + (cx / d.scale - d.cx0)
    local newBottom = d.bottom0 + (cy / d.scale - d.cy0)
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", newLeft, newBottom)
end

local function BeginBagDrag(frame)
    local left0, bottom0 = frame:GetLeft(), frame:GetBottom()
    if not left0 or not bottom0 then return end
    local scale = frame:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    frame.cbDrag = {
        scale = scale,
        cx0 = cx / scale,
        cy0 = cy / scale,
        left0 = left0,
        bottom0 = bottom0
    }
    frame:SetScript("OnUpdate", DragTick)
end

local function EndBagDrag(frame)
    frame:SetScript("OnUpdate", nil)
    frame.cbDrag = nil
    SaveBagPosition(frame)
    ApplyBagPosition(frame)
end

-- Drift-style revert: once the last bag closes, drop every custom point so the
-- next Blizzard layout pass starts from the pristine point-less state the
-- container frames have in XML (ContainerFrame1..13 declare no anchors)
local function MaybeRevertAllBags()
    for i = 1, NUM_CONTAINER_FRAMES do
        local f = _G["ContainerFrame"..i]
        if f and f:IsShown() then return end
    end
    for i = 1, NUM_CONTAINER_FRAMES do
        local f = _G["ContainerFrame"..i]
        if f then
            pcall(f.ClearAllPoints, f)
        end
    end
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
        BeginBagDrag(self)
    end)

    frame:SetScript("OnDragStop", function(self)
        EndBagDrag(self)
    end)

    -- Make title frame draggable (using ClickableTitleFrame instead of Name)
    local titleFrame = frame.ClickableTitleFrame
    if titleFrame then
        titleFrame:EnableMouse(true)
        titleFrame:RegisterForDrag("LeftButton")
        titleFrame:SetScript("OnDragStart", function()
            BeginBagDrag(frame)
        end)
        titleFrame:SetScript("OnDragStop", function()
            EndBagDrag(frame)
        end)
    end

    -- Also make portrait button draggable
    local portraitButton = _G[frame:GetName().."PortraitButton"]
    if portraitButton then
        portraitButton:EnableMouse(true)
        portraitButton:RegisterForDrag("LeftButton")
        portraitButton:SetScript("OnDragStart", function()
            BeginBagDrag(frame)
        end)
        portraitButton:SetScript("OnDragStop", function()
            EndBagDrag(frame)
        end)
    end

    -- Safety net: if the bag (or an ancestor) is hidden mid-drag, OnDragStop
    -- never fires; finish the drag here so no frame is left with a live drag
    -- ticker. Then, once the last bag is closed, revert every container frame
    -- to the pristine point-less state. HookScript, NOT SetScript --
    -- ContainerFrame_OnHide is Blizzard's template handler and must keep
    -- running.
    frame:HookScript("OnHide", function(self)
        if self.cbDrag then
            EndBagDrag(self)
        end
        MaybeRevertAllBags()
    end)

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

-- One-time login heal: sessions that ran the old StartMoving-based drag could
-- leave a container frame anchored to the SCREEN's anchor family and flagged
-- user-placed; the client's layout cache then re-imposes that poisoned anchor
-- at every login, and Blizzard's UpdateContainerFrameAnchors throws "anchor
-- family connection" on its very first SetPoint. Purge the anchor, clear the
-- user-placed flag so the cache stops saving container positions, and undo any
-- SetMovable(false) damage from older reset code.
local function HealContainerAnchors()
    for i = 1, NUM_CONTAINER_FRAMES do
        local f = _G["ContainerFrame"..i]
        if f then
            pcall(f.ClearAllPoints, f)
            f:SetUserPlaced(false)
            f:SetMovable(true)
            if f.SetDontSavePosition then
                pcall(f.SetDontSavePosition, f, true)
            end
        end
    end
end

-- Capture the ground truth of any future anchor-family error so /cbags diag
-- can show what the frames were anchored to at the moment it fired
local lastAnchorError

local function SnapshotContainerPoints()
    local points = {}
    for i = 1, NUM_CONTAINER_FRAMES do
        local f = _G["ContainerFrame"..i]
        if f then
            local ok, point, relativeTo, relativePoint, x, y = pcall(f.GetPoint, f, 1)
            if ok and point then
                local relName
                if relativeTo then
                    relName = relativeTo:GetName() or "<unnamed>"
                else
                    relName = "<nil=SCREEN -- POISONED>"
                end
                points[#points + 1] = string.format("ContainerFrame%d: %s / %s / %s / %.1f / %.1f",
                    i, point, relName, relativePoint or "?", x or 0, y or 0)
            end
        end
    end
    return points
end

-- Chain the existing error handler so BugSack/Bugger keep working
local function InstallAnchorErrorCapture()
    local orig = geterrorhandler()
    seterrorhandler(function(msg, ...)
        if type(msg) == "string" and msg:find("anchor family connection", 1, true) then
            lastAnchorError = {
                msg = msg,
                at = date("%H:%M:%S"),
                inCombat = InCombatLockdown(),
                points = SnapshotContainerPoints()
            }
        end
        return orig(msg, ...)
    end)
end

local function PrintBagDiagnostics()
    print("Commander Bags diagnostics:")
    for i = 1, NUM_CONTAINER_FRAMES do
        local f = _G["ContainerFrame"..i]
        if f and (f:IsShown() or f:GetNumPoints() > 0) then
            print(string.format("  %s: shown=%s points=%d protected=%s userPlaced=%s movable=%s scale=%.2f dragging=%s",
                f:GetName(), tostring(f:IsShown()), f:GetNumPoints(), tostring(f:IsProtected()),
                tostring(f:IsUserPlaced()), tostring(f:IsMovable()), f:GetScale(), tostring(f.cbDrag ~= nil)))
            for k = 1, f:GetNumPoints() do
                local ok, point, relativeTo, relativePoint, x, y = pcall(f.GetPoint, f, k)
                if ok and point then
                    local relName
                    if relativeTo then
                        relName = relativeTo:GetName() or "<unnamed>"
                    else
                        relName = "<nil=SCREEN -- POISONED>"
                    end
                    print(string.format("    point %d: %s / %s / %s / %.1f / %.1f",
                        k, point, relName, relativePoint or "?", x or 0, y or 0))
                else
                    print(string.format("    point %d: <GetPoint failed: %s>", k, tostring(point)))
                end
            end
        end
    end
    print("  InCombatLockdown: " .. tostring(InCombatLockdown()))
    if CommanderBagsDB.BagPositions and next(CommanderBagsDB.BagPositions) then
        print("  Saved positions:")
        for name, pos in pairs(CommanderBagsDB.BagPositions) do
            print(string.format("    %s: left=%.1f bottom=%.1f",
                name, tonumber(pos.left) or 0, tonumber(pos.bottom) or 0))
        end
    else
        print("  Saved positions: none")
    end
    if lastAnchorError then
        print(string.format("  Last anchor error (at %s, inCombat=%s):",
            lastAnchorError.at, tostring(lastAnchorError.inCombat)))
        print("    " .. lastAnchorError.msg)
        for _, line in ipairs(lastAnchorError.points or {}) do
            print("    " .. line)
        end
    else
        print("  No anchor error captured this session")
    end
end

SLASH_CBAGSDIAG1 = "/cbags"
SlashCmdList["CBAGSDIAG"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "diag" then
        PrintBagDiagnostics()
    elseif msg == "reset" then
        -- CommanderBags_Reset is exposed by CommanderBagsDB.lua
        if CommanderBags_Reset then
            CommanderBags_Reset()
        else
            print("Commander Bags reset is unavailable")
        end
    else
        print("Usage: /cbags [diag|reset]")
    end
end

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        HealContainerAnchors()
        DiscardLegacyBagPositions()
        InstallAnchorErrorCapture()
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
