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

local FadeBags -- defined below; forward-declared for the UPDATE listener

-- Buttons memoize the itemID they were last colored for; bumping the
-- generation invalidates every memo at once (borders force-reset, settings
-- changed, or coloring toggled) without touching each button
local colorGen = 0

-- Whether a bind-on-equip item has bound is the one thing a settled slot can
-- still change, and the only thing here that costs a tooltip. Re-checking it
-- once per refresh burst catches it; re-checking it on all ten passes of the
-- burst just pays for the same answer ten times.
local bindGen = 0

-- Bind states. BOE covers bind-on-use as well: both mean "still tradeable,
-- still sellable, not yours yet".
local BIND_NONE, BIND_SOULBOUND, BIND_BOE = 0, 1, 2

local QUAD = "Interface\\Buttons\\WHITE8X8"

-- The quality ring is DRAWN, not borrowed. Blizzard's own IconBorder is a
-- soft WhiteIconFrame that ContainerFrame_Update repaints (and hides below
-- rare) on every bag event, so anything written into it lasted only until the
-- next Blizzard pass -- which is why the rarity color kept fading out. These
-- textures belong to this addon; nothing else in the UI touches them.
local function EnsureBorder(button)
    local ring = button.cbRing
    if ring then return ring end
    ring = {}
    for i = 1, 8 do
        -- Sublevel 5: over the icon and Blizzard's slot art, under the stack
        -- count and the cooldown frame
        local tex = button:CreateTexture(nil, "OVERLAY", nil, 5)
        tex:SetTexture(QUAD)
        tex:Hide()
        ring[i] = tex
    end
    button.cbRing = ring
    return ring
end

-- Four quads inset by `inset` from the icon's rect, `w` thick. Corners are
-- covered by the horizontals, so the verticals stop short of them.
local function LayoutRing(ring, first, anchor, inset, w)
    local top, bottom, left, right = ring[first], ring[first + 1], ring[first + 2], ring[first + 3]

    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", anchor, "TOPLEFT", inset, -inset)
    top:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -inset, -inset)
    top:SetHeight(w)

    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", inset, inset)
    bottom:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -inset, inset)
    bottom:SetHeight(w)

    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT", 0, 0)
    left:SetWidth(w)

    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT", 0, 0)
    right:SetWidth(w)
end

local function LayoutBorder(button, thickness)
    if button.cbThickness == thickness then return end
    button.cbThickness = thickness
    local ring = EnsureBorder(button)
    local anchor = button.icon or button
    LayoutRing(ring, 1, anchor, 0, thickness)          -- the ring itself
    LayoutRing(ring, 5, anchor, thickness, 1)          -- the halo just inside it
end

local function ShowBorder(button, r, g, b, thickness, halo)
    local ring = EnsureBorder(button)
    LayoutBorder(button, thickness)
    for i = 1, 4 do
        ring[i]:SetVertexColor(r, g, b, 1)
        ring[i]:Show()
    end
    for i = 5, 8 do
        if halo then
            ring[i]:SetVertexColor(r, g, b, 0.4)
            ring[i]:Show()
        else
            ring[i]:Hide()
        end
    end
end

local function HideBorder(button)
    local ring = button.cbRing
    if not ring then return end
    for i = 1, 8 do ring[i]:Hide() end
end

-- The bind badge: a padlock built from tinted quads rather than a texture
-- file, the same way the rest of the suite draws its chrome. Closed and dim
-- means soulbound; open and gold means the item is still bind-on-equip and
-- can still be traded, sold or disenchanted for someone else.
local BADGE = 13

local function EnsureBadge(button)
    local badge = button.cbBadge
    if badge then return badge end

    local function Quad(sublevel)
        local tex = button:CreateTexture(nil, "OVERLAY", nil, sublevel)
        tex:SetTexture(QUAD)
        return tex
    end

    badge = { plate = Quad(6), body = Quad(7), postL = Quad(7), postR = Quad(7), bar = Quad(7) }

    badge.plate:SetSize(BADGE, BADGE)
    -- Same rect the ring is drawn on, so the padlock sits inside the border
    -- rather than half under it
    badge.plate:SetPoint("BOTTOMLEFT", button.icon or button, "BOTTOMLEFT", 1, 1)

    -- Lock body sits on the plate's floor; the shackle's posts overlap its top
    -- edge by a pixel so the silhouette reads as one piece
    badge.body:SetSize(9, 5)
    badge.body:SetPoint("BOTTOM", badge.plate, "BOTTOM", 0, 2)
    badge.postL:SetSize(2, 4)
    badge.postR:SetSize(2, 4)
    badge.bar:SetHeight(2)

    button.cbBadge = badge
    return badge
end

local function HideBadge(button)
    local badge = button.cbBadge
    if not badge then return end
    for _, tex in pairs(badge) do tex:Hide() end
end

local function ShowBadge(button, bound)
    local badge = EnsureBadge(button)
    local r, g, b = 1, 0.84, 0.3
    local plateAlpha = 0.7
    if bound then
        r, g, b = 0.74, 0.78, 0.88
        plateAlpha = 0.55
    end

    badge.plate:SetVertexColor(0, 0, 0, plateAlpha)
    badge.body:SetVertexColor(r, g, b, 1)
    badge.postL:SetVertexColor(r, g, b, 1)
    badge.postR:SetVertexColor(r, g, b, 1)
    badge.bar:SetVertexColor(r, g, b, 1)

    badge.postL:ClearAllPoints()
    badge.postR:ClearAllPoints()
    badge.bar:ClearAllPoints()
    if bound then
        -- Closed: both posts under a bar that spans them
        badge.postL:SetPoint("BOTTOM", badge.plate, "BOTTOM", -2.5, 6)
        badge.postR:SetPoint("BOTTOM", badge.plate, "BOTTOM", 2.5, 6)
        badge.bar:SetWidth(7)
        badge.bar:SetPoint("BOTTOM", badge.plate, "BOTTOM", 0, 9)
        badge.postR:Show()
    else
        -- Open: the shackle is hinged on the left and swung clear, so the
        -- right-hand post is simply gone
        badge.postL:SetPoint("BOTTOM", badge.plate, "BOTTOM", -2.5, 6)
        badge.bar:SetWidth(6)
        badge.bar:SetPoint("BOTTOM", badge.plate, "BOTTOM", 1.5, 9)
        badge.postR:Hide()
    end

    badge.plate:Show()
    badge.body:Show()
    badge.postL:Show()
    badge.bar:Show()
end

-- Restore Blizzard's own quality border for a slot. Turning this module's
-- coloring off used to leave every bag button with a hidden IconBorder until
-- the next full container update; handing the slot back to SetItemButtonQuality
-- puts the default UI back immediately.
local function RestoreBlizzardBorder(button, bagID, slot)
    if not button.IconBorder then return end
    local info = bagID and slot and C_Container.GetContainerItemInfo
        and C_Container.GetContainerItemInfo(bagID, slot)
    if SetItemButtonQuality and info then
        SetItemButtonQuality(button, info.quality, info.hyperlink)
    else
        button.IconBorder:Hide()
    end
end

-- Hidden container frames are swept too -- a frame keeps whatever was drawn on
-- it when it closed -- but only a shown one has a bag id worth trusting, so
-- only there is Blizzard's border rebuilt from the slot.
local function ResetItemColors()
    colorGen = colorGen + 1
    for i = 1, NUM_CONTAINER_FRAMES do
        local containerFrame = _G["ContainerFrame"..i]
        if containerFrame then
            local shown = containerFrame:IsShown()
            local bagID = containerFrame:GetID()
            for j = 1, containerFrame.size or 0 do
                local button = _G[containerFrame:GetName().."Item"..j]
                if button then
                    if button.icon then
                        button.icon:SetVertexColor(1, 1, 1, 1)
                    end
                    HideBorder(button)
                    HideBadge(button)
                    button.cbItemID, button.cbBind, button.cbBindUnstable = nil, nil, nil
                    if shown then
                        RestoreBlizzardBorder(button, bagID, button:GetID())
                    elseif button.IconBorder then
                        button.IconBorder:Hide()
                    end
                end
            end
        end
    end
end

-- Consumable-ness and quest-ness are properties of the ITEM, not the
-- slot -- cached per itemID, they cost ONE tooltip build ever. The old
-- code paid two SetBagItem rebuilds (one of the most expensive UI calls
-- in the client) per occupied slot per pass, ~1200-2000 per refresh
-- burst: the module's entire CPU story.
local itemFlags = {}

local function GetItemFlags(itemID, bagID, slot, resolved)
    local cached = itemFlags[itemID]
    if cached then return cached end
    scanningTooltip:ClearLines()
    scanningTooltip:SetBagItem(bagID, slot)
    local numLines = scanningTooltip:NumLines()

    -- Consumable: a "Use:" line with no "Equip:" line at or after it
    -- (same shape as the original scan, so borders do not change)
    local consumable = false
    for i = 2, numLines do
        local textLeft = _G["CommanderBagsScanningTooltipTextLeft" .. i]
        local text = textLeft and textLeft:GetText()
        if text and text:find("^Use: ") then
            consumable = true
            for j = i, numLines do
                local equipText = _G["CommanderBagsScanningTooltipTextLeft" .. j]
                local equip = equipText and equipText:GetText()
                if equip and equip:find("^Equip: ") then
                    consumable = false
                    break
                end
            end
            break
        end
    end

    local quest = false
    for i = 1, numLines do
        local textLeft = _G["CommanderBagsScanningTooltipTextLeft" .. i]
        local text = textLeft and textLeft:GetText()
        if text and (text:find("Quest Item") or text:find("This Item Begins a Quest")) then
            quest = true
            break
        end
    end

    local flags = { consumable = consumable, quest = quest }
    -- Only cache once the item's data is confirmed loaded -- early passes
    -- can see incomplete tooltips, and the refresh window retries those
    if resolved then
        itemFlags[itemID] = flags
    end
    return flags
end

-- Whether a bind-on-equip item has actually bound is a property of the SLOT,
-- not the itemID: two stacks of the same shoulders can sit side by side, one
-- looted and worn, one still tradeable. Only the tooltip knows, so only
-- bindType 2/3 items ever pay for this scan.
local function ScanIsSoulbound(bagID, slot)
    scanningTooltip:ClearLines()
    scanningTooltip:SetBagItem(bagID, slot)
    local numLines = math.min(scanningTooltip:NumLines(), 8)
    for i = 2, numLines do
        local textLeft = _G["CommanderBagsScanningTooltipTextLeft" .. i]
        local text = textLeft and textLeft:GetText()
        if text then
            if ITEM_SOULBOUND and text == ITEM_SOULBOUND then return true end
            if (ITEM_BIND_ON_EQUIP and text == ITEM_BIND_ON_EQUIP)
                or (ITEM_BIND_ON_USE and text == ITEM_BIND_ON_USE) then
                return false
            end
        end
    end
    return false
end

-- The container struct answers this outright on clients that carry the field;
-- the tooltip is the fallback, not the first resort.
local function IsSlotBound(bagID, slot)
    local info = C_Container.GetContainerItemInfo
        and C_Container.GetContainerItemInfo(bagID, slot)
    if info and info.isBound ~= nil then
        return info.isBound and true or false
    end
    return ScanIsSoulbound(bagID, slot)
end

-- bindType comes free with the item's cached info: 1 bind-on-pickup (in your
-- bags that means already yours), 2 bind-on-equip, 3 bind-on-use, 4 quest.
-- Everything else never binds and gets no badge at all. The second return is
-- whether the answer can still change while the item sits there.
local function GetBindState(bagID, slot, bindType)
    if bindType == 1 then
        return BIND_SOULBOUND, false
    elseif bindType == 2 or bindType == 3 then
        return IsSlotBound(bagID, slot) and BIND_SOULBOUND or BIND_BOE, true
    end
    return BIND_NONE, false
end

local function ApplyBadge(button, bind, badgeMode)
    if badgeMode == "OFF" or bind == BIND_NONE then
        HideBadge(button)
    elseif bind == BIND_BOE then
        ShowBadge(button, false)
    elseif badgeMode == "BOTH" then
        ShowBadge(button, true)
    else
        HideBadge(button)
    end
end

local function PaintSlot(button, bagID, slot, itemID, thickness, halo, badgeMode)
    local _, _, rarity, _, _, _, _, _, _, _, _, _, _, bindType = C_Item.GetItemInfo(itemID)
    local resolved = rarity ~= nil
    local flags = GetItemFlags(itemID, bagID, slot, resolved)

    button.icon:SetVertexColor(1, 1, 1, 1)
    if button.IconBorder then
        -- One source of truth for the ring: Blizzard's soft border underneath
        -- ours would only wash the color back out
        button.IconBorder:Hide()
    end

    if flags.quest then
        ShowBorder(button, 1, 0.82, 0, thickness, halo)
    elseif rarity == 0 then -- Poor (Gray): vendor fodder
        ShowBorder(button, 1, 0.1, 0.1, thickness, halo)
    elseif flags.consumable then
        ShowBorder(button, 0, 0.8, 1, thickness, halo)
    elseif rarity == 1 then -- Common (White): left plain on purpose
        HideBorder(button)
    elseif rarity then
        local r, g, b = C_Item.GetItemQualityColor(rarity)
        ShowBorder(button, r, g, b, thickness, halo)
    else
        HideBorder(button) -- Item info not cached yet; refresh cycle will retry
    end

    local bind, unstable = BIND_NONE, false
    if resolved then
        bind, unstable = GetBindState(bagID, slot, bindType)
    end
    ApplyBadge(button, bind, badgeMode)

    button.cbBind = bind
    button.cbBindUnstable = unstable
    button.cbBindGen = bindGen
    if resolved then
        button.cbItemID, button.cbBag, button.cbGen = itemID, bagID, colorGen
    else
        -- Data not loaded -- leave unmemoized so the refresh window retries
        button.cbItemID = nil
    end
end

-- The reset is a transition, not a state: without this the ten passes of a
-- refresh burst would each hand every slot back to SetItemButtonQuality again
local colorsReset = false

local function UpdateItemColors()
    if not CommanderBagsDB.ColorCodeItems then
        if not colorsReset then
            ResetItemColors()
            colorsReset = true
        end
        return
    end
    colorsReset = false

    local thickness = CommanderBagsDB.BorderThickness or 2
    local halo = CommanderBagsDB.RarityHalo
    local badgeMode = CommanderBagsDB.BindBadges or "BOTH"

    -- For each container frame
    for i = 1, NUM_CONTAINER_FRAMES do
        local containerFrame = _G["ContainerFrame"..i]
        if containerFrame and containerFrame:IsShown() then
            local bagID = containerFrame:GetID()
            local baseName = containerFrame:GetName() .. "Item"

            -- Update each item button in the container. A button memoizes the
            -- itemID and bag it was last painted for: unchanged slots skip the
            -- item lookup and tooltip work entirely. The bag is part of the
            -- memo because ContainerFrame2 is whichever bag opened second, not
            -- a fixed one.
            for j = 1, containerFrame.size or 0 do
                local button = _G[baseName .. j]
                if button then
                    local slot = button:GetID()
                    local itemID = C_Container.GetContainerItemID
                        and C_Container.GetContainerItemID(bagID, slot)

                    if itemID then
                        if button.cbItemID ~= itemID or button.cbBag ~= bagID
                            or button.cbGen ~= colorGen then
                            PaintSlot(button, bagID, slot, itemID, thickness, halo, badgeMode)
                        elseif button.cbBindUnstable and button.cbBindGen ~= bindGen then
                            -- The one thing a settled slot can still change:
                            -- a bind-on-equip item binding where it sits
                            button.cbBindGen = bindGen
                            local bind = IsSlotBound(bagID, slot) and BIND_SOULBOUND or BIND_BOE
                            if bind ~= button.cbBind then
                                button.cbBind = bind
                                ApplyBadge(button, bind, badgeMode)
                            end
                        end
                    else
                        if button.cbItemID ~= false or button.cbBag ~= bagID
                            or button.cbGen ~= colorGen then
                            button.cbItemID, button.cbBag, button.cbGen = false, bagID, colorGen
                            button.cbBind, button.cbBindUnstable, button.cbBindGen = nil, nil, nil
                            HideBorder(button)
                            HideBadge(button)
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
end

-- Blizzard repaints IconBorder from its own container updates, mouseovers and
-- cursor changes. Nothing it does can reach the drawn ring, but the soft
-- border coming back underneath would still cloud it -- so put it away again
-- the moment Blizzard shows it on a slot this module owns.
if SetItemButtonQuality then
    hooksecurefunc("SetItemButtonQuality", function(button)
        if button and button.cbRing and CommanderBagsDB and CommanderBagsDB.ColorCodeItems
            and button.IconBorder then
            button.IconBorder:Hide()
        end
    end)
end

-- Timer callbacks are file-level named functions: these debounces fire on
-- every bag/cursor event, and a fresh closure per scheduling call was
-- steady-state garbage
local function RefreshCycle()
    UpdateItemColors()
    refreshCount = refreshCount + 1

    if refreshCount < MAX_REFRESH_COUNT then
        refreshTimer = C_Timer.NewTimer(REFRESH_INTERVAL, RefreshCycle)
    else
        refreshTimer = nil
    end
end

local function StartRefreshWindow()
    if refreshTimer then
        refreshTimer:Cancel()
    end

    bindGen = bindGen + 1
    refreshCount = 0
    RefreshCycle()
end

local function RunScheduledUpdate()
    updateTimer = nil
    StartRefreshWindow()
end

local function ScheduleUpdate()
    if updateTimer then
        updateTimer:Cancel()
    end
    updateTimer = C_Timer.NewTimer(0.1, RunScheduledUpdate)
end

-- Cursor changes can fire many times per second while items are picked up and
-- dropped; restart a single short timer instead of running a full refresh burst
local function RunCursorRefresh()
    cursorRefreshTimer = nil
    -- Equipping a bind-on-equip item out of the bags lands here, so this pass
    -- has to be allowed to look at bind state again
    bindGen = bindGen + 1
    UpdateItemColors()
end

local function ScheduleCursorRefresh()
    if cursorRefreshTimer then
        cursorRefreshTimer:Cancel()
    end
    cursorRefreshTimer = C_Timer.NewTimer(CURSOR_REFRESH_DELAY, RunCursorRefresh)
end

local function OnUpdate()
    -- If fading was just disabled while bags were faded (e.g. mid-move),
    -- restore full opacity; nothing else ever writes container alpha back
    if not CommanderBagsDB.FadeBagsWhileMoving then
        FadeBags(false)
    end
    -- This only fires when a setting changed (or at login), and border
    -- thickness, the halo and the badge mode all live inside the per-button
    -- memo -- so invalidate it wholesale rather than trying to spot which
    -- knob moved
    colorGen = colorGen + 1
    bindGen = bindGen + 1
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
function FadeBags(fade)
    local fadedAlpha = CommanderBagsDB.FadeOpacity or 0.5
    for i = 1, NUM_CONTAINER_FRAMES do
        local bagFrame = _G["ContainerFrame"..i]
        if bagFrame and bagFrame:IsShown() then
            if fade then
                bagFrame:SetAlpha(fadedAlpha)
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

    -- Also make portrait button draggable, and make a plain left-click on it
    -- run the bag sort (right-click keeps the default bag menu; the override
    -- can be disabled in settings)
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

        local originalPortraitClick = portraitButton:GetScript("OnClick")
        portraitButton:SetScript("OnClick", function(self, mouseButton, ...)
            if mouseButton == "LeftButton" and CommanderBagsDB.PortraitSortClick then
                if CommanderBags_SortBags then
                    CommanderBags_SortBags()
                end
            elseif originalPortraitClick then
                originalPortraitClick(self, mouseButton, ...)
            end
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

-- /cb and /cbags (with reset and diag subcommands) are registered by the
-- settings panel in CommanderBagsDB.lua; it dispatches "diag" here
CommanderBags_PrintDiagnostics = PrintBagDiagnostics

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
        elseif event == "PLAYER_STOPPED_MOVING" then
            -- Unconditional: restores opacity even if fading was toggled off mid-move
            FadeBags(false)
        elseif event == "BAG_OPEN" then
            StartRefreshWindow()
            HookAllContainerFrames()
        elseif event == "MERCHANT_SHOW" then
            StartRefreshWindow()
        elseif event == "MERCHANT_UPDATE" then
            -- Fires once per transaction and in bursts when vendoring a
            -- bag of junk — debounce instead of a synchronous full pass
            ScheduleUpdate()
        elseif event == "CURSOR_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" or event == "ITEM_UNLOCKED" then
            ScheduleCursorRefresh()
        else
            ScheduleUpdate()
        end
    end
end)
